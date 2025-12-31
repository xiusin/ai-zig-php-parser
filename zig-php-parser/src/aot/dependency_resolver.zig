//! File Dependency Resolver for AOT Compiler
//!
//! This module handles multi-file PHP project compilation by:
//! - Parsing include/require statements from PHP source files
//! - Building a dependency graph of all files
//! - Detecting circular dependencies
//! - Providing topological ordering for compilation
//!
//! ## Usage
//!
//! ```zig
//! var resolver = try DependencyResolver.init(allocator, diagnostics);
//! defer resolver.deinit();
//!
//! try resolver.resolveFile("main.php");
//! const order = try resolver.getCompilationOrder();
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const SourceLocation = Diagnostics.SourceLocation;

/// Represents an include/require statement
pub const IncludeStatement = struct {
    /// The path expression (may be a string literal or expression)
    path: []const u8,
    /// Whether this is a require (vs include)
    is_require: bool,
    /// Whether this is _once variant
    is_once: bool,
    /// Source location of the statement
    location: SourceLocation,
    /// The resolved absolute path (if resolvable)
    resolved_path: ?[]const u8,
};

/// Represents a file in the dependency graph
pub const FileNode = struct {
    /// Absolute path to the file
    path: []const u8,
    /// List of files this file depends on (includes/requires)
    dependencies: std.ArrayListUnmanaged([]const u8),
    /// List of include statements found in this file
    includes: std.ArrayListUnmanaged(IncludeStatement),
    /// Whether this file has been fully processed
    processed: bool,
    /// Whether this file is currently being processed (for cycle detection)
    in_progress: bool,
    /// Source content (loaded when processing)
    source: ?[]const u8,

    pub fn init() FileNode {
        return .{
            .path = "",
            .dependencies = .{},
            .includes = .{},
            .processed = false,
            .in_progress = false,
            .source = null,
        };
    }

    pub fn deinit(self: *FileNode, allocator: Allocator) void {
        self.dependencies.deinit(allocator);
        for (self.includes.items) |*inc| {
            if (inc.resolved_path) |rp| {
                allocator.free(rp);
            }
        }
        self.includes.deinit(allocator);
        if (self.source) |src| {
            allocator.free(src);
        }
    }
};

/// Circular dependency information
pub const CircularDependency = struct {
    /// The cycle path (list of file paths forming the cycle)
    cycle: []const []const u8,
    /// Starting file of the cycle
    start_file: []const u8,
};

/// Result of dependency resolution
pub const ResolutionResult = struct {
    /// All files in the project (in dependency order)
    files: []const []const u8,
    /// Whether any circular dependencies were detected
    has_cycles: bool,
    /// Detected circular dependencies
    cycles: []const CircularDependency,
    /// Files that could not be resolved
    unresolved: []const UnresolvedFile,
};

/// Information about an unresolved file
pub const UnresolvedFile = struct {
    /// The path that could not be resolved
    path: []const u8,
    /// The file that referenced this path
    referenced_from: []const u8,
    /// Location of the reference
    location: SourceLocation,
    /// Reason for failure
    reason: Reason,

    pub const Reason = enum {
        file_not_found,
        permission_denied,
        invalid_path,
        dynamic_path,
    };
};

/// File Dependency Resolver
pub const DependencyResolver = struct {
    allocator: Allocator,
    diagnostics: *DiagnosticEngine,
    /// Map of file path to FileNode
    files: std.StringHashMapUnmanaged(FileNode),
    /// Base directory for resolving relative paths
    base_dir: []const u8,
    /// Include paths to search for files
    include_paths: std.ArrayListUnmanaged([]const u8),
    /// Detected circular dependencies
    cycles: std.ArrayListUnmanaged(CircularDependency),
    /// Unresolved files
    unresolved: std.ArrayListUnmanaged(UnresolvedFile),
    /// Stack for cycle detection during DFS
    visit_stack: std.ArrayListUnmanaged([]const u8),

    const Self = @This();

    /// Initialize a new dependency resolver
    pub fn init(allocator: Allocator, diagnostics: *DiagnosticEngine) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .diagnostics = diagnostics,
            .files = .{},
            .base_dir = "",
            .include_paths = .{},
            .cycles = .{},
            .unresolved = .{},
            .visit_stack = .{},
        };
        return self;
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self) void {
        // Free all file nodes
        var it = self.files.iterator();
        while (it.next()) |entry| {
            var node = entry.value_ptr;
            node.deinit(self.allocator);
        }
        self.files.deinit(self.allocator);

        // Free include paths
        for (self.include_paths.items) |path| {
            self.allocator.free(path);
        }
        self.include_paths.deinit(self.allocator);

        // Free cycles
        for (self.cycles.items) |cycle| {
            self.allocator.free(cycle.cycle);
        }
        self.cycles.deinit(self.allocator);

        // Free unresolved
        self.unresolved.deinit(self.allocator);

        // Free visit stack
        self.visit_stack.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Set the base directory for resolving relative paths
    pub fn setBaseDir(self: *Self, dir: []const u8) !void {
        self.base_dir = try self.allocator.dupe(u8, dir);
    }

    /// Add an include path to search for files
    pub fn addIncludePath(self: *Self, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.include_paths.append(self.allocator, path_copy);
    }

    /// Resolve all dependencies starting from the given entry file
    pub fn resolveFile(self: *Self, entry_file: []const u8) !void {
        // Resolve the entry file path
        const abs_path = try self.resolvePath(entry_file, null);
        if (abs_path == null) {
            self.diagnostics.reportError(
                .{ .file = entry_file },
                "entry file not found: {s}",
                .{entry_file},
            );
            return error.FileNotFound;
        }

        // Set base directory from entry file
        if (self.base_dir.len == 0) {
            if (std.fs.path.dirname(abs_path.?)) |dir| {
                self.base_dir = try self.allocator.dupe(u8, dir);
            }
        }

        // Process the entry file and all its dependencies
        try self.processFile(abs_path.?);
    }

    /// Process a single file and its dependencies
    fn processFile(self: *Self, file_path: []const u8) !void {
        // Check if already processed
        if (self.files.get(file_path)) |node| {
            if (node.processed) return;
            if (node.in_progress) {
                // Circular dependency detected
                try self.recordCycle(file_path);
                return;
            }
        }

        // Create or get file node
        const gop = try self.files.getOrPut(self.allocator, file_path);
        if (!gop.found_existing) {
            gop.value_ptr.* = FileNode.init();
            gop.value_ptr.path = file_path;
        }

        // Mark as in progress
        gop.value_ptr.in_progress = true;
        try self.visit_stack.append(self.allocator, file_path);

        // Load and parse the file
        const source = self.loadFile(file_path) catch |err| {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "failed to load file: {s}",
                .{@errorName(err)},
            );
            gop.value_ptr.in_progress = false;
            _ = self.visit_stack.pop();
            return;
        };
        gop.value_ptr.source = source;

        // Extract include/require statements
        const includes = try self.extractIncludes(source, file_path);

        // Process each include
        for (includes) |inc| {
            try gop.value_ptr.includes.append(self.allocator, inc);

            if (inc.resolved_path) |resolved| {
                try gop.value_ptr.dependencies.append(self.allocator, resolved);
                // Recursively process the dependency
                try self.processFile(resolved);
            } else {
                // Record unresolved file
                try self.unresolved.append(self.allocator, .{
                    .path = inc.path,
                    .referenced_from = file_path,
                    .location = inc.location,
                    .reason = if (self.isDynamicPath(inc.path)) .dynamic_path else .file_not_found,
                });
            }
        }

        // Mark as processed
        gop.value_ptr.in_progress = false;
        gop.value_ptr.processed = true;
        _ = self.visit_stack.pop();
    }

    /// Load a file's contents
    fn loadFile(self: *Self, file_path: []const u8) ![]const u8 {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const source = try self.allocator.alloc(u8, file_size);
        const bytes_read = try file.readAll(source);
        if (bytes_read != file_size) {
            return error.IncompleteRead;
        }
        return source;
    }

    /// Extract include/require statements from source code
    pub fn extractIncludes(self: *Self, source: []const u8, file_path: []const u8) ![]IncludeStatement {
        var includes = std.ArrayListUnmanaged(IncludeStatement){};
        errdefer {
            for (includes.items) |inc| {
                self.allocator.free(inc.path);
                if (inc.resolved_path) |rp| {
                    self.allocator.free(rp);
                }
            }
            includes.deinit(self.allocator);
        }

        var line: u32 = 1;
        var col: u32 = 1;
        var i: usize = 0;

        while (i < source.len) {
            // Track line and column
            if (source[i] == '\n') {
                line += 1;
                col = 1;
                i += 1;
                continue;
            }

            // Look for include/require keywords
            if (self.matchKeyword(source[i..], "include_once")) {
                const inc = try self.parseIncludeStatement(source, i, line, col, false, true, file_path);
                if (inc) |statement| {
                    try includes.append(self.allocator, statement);
                }
                i += 12; // length of "include_once"
            } else if (self.matchKeyword(source[i..], "include")) {
                const inc = try self.parseIncludeStatement(source, i, line, col, false, false, file_path);
                if (inc) |statement| {
                    try includes.append(self.allocator, statement);
                }
                i += 7; // length of "include"
            } else if (self.matchKeyword(source[i..], "require_once")) {
                const inc = try self.parseIncludeStatement(source, i, line, col, true, true, file_path);
                if (inc) |statement| {
                    try includes.append(self.allocator, statement);
                }
                i += 12; // length of "require_once"
            } else if (self.matchKeyword(source[i..], "require")) {
                const inc = try self.parseIncludeStatement(source, i, line, col, true, false, file_path);
                if (inc) |statement| {
                    try includes.append(self.allocator, statement);
                }
                i += 7; // length of "require"
            } else {
                col += 1;
                i += 1;
            }
        }

        const result = try self.allocator.dupe(IncludeStatement, includes.items);
        includes.deinit(self.allocator);
        return result;
    }

    /// Check if source starts with a keyword (followed by non-alphanumeric)
    fn matchKeyword(self: *Self, source: []const u8, keyword: []const u8) bool {
        _ = self;
        if (source.len < keyword.len) return false;
        if (!std.mem.eql(u8, source[0..keyword.len], keyword)) return false;
        if (source.len > keyword.len) {
            const next = source[keyword.len];
            if (std.ascii.isAlphanumeric(next) or next == '_') return false;
        }
        return true;
    }

    /// Parse an include/require statement and extract the path
    fn parseIncludeStatement(
        self: *Self,
        source: []const u8,
        start: usize,
        line: u32,
        col: u32,
        is_require: bool,
        is_once: bool,
        current_file: []const u8,
    ) !?IncludeStatement {
        // Skip the keyword
        var i = start;
        while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
            i += 1;
        }

        // Skip whitespace
        while (i < source.len and (source[i] == ' ' or source[i] == '\t')) {
            i += 1;
        }

        // Check for optional parenthesis
        const has_paren = i < source.len and source[i] == '(';
        if (has_paren) i += 1;

        // Skip whitespace
        while (i < source.len and (source[i] == ' ' or source[i] == '\t')) {
            i += 1;
        }

        // Extract the path
        var path: ?[]const u8 = null;
        var is_dynamic = false;

        if (i < source.len) {
            if (source[i] == '\'' or source[i] == '"') {
                // String literal path
                const quote = source[i];
                i += 1;
                const path_start = i;
                while (i < source.len and source[i] != quote) {
                    if (source[i] == '\\' and i + 1 < source.len) {
                        i += 2; // Skip escaped character
                    } else {
                        i += 1;
                    }
                }
                if (i < source.len) {
                    path = source[path_start..i];
                }
            } else if (source[i] == '$' or std.ascii.isAlphanumeric(source[i])) {
                // Variable or expression - mark as dynamic
                is_dynamic = true;
                // Try to extract the expression for error reporting
                const expr_start = i;
                while (i < source.len and source[i] != ';' and source[i] != ')') {
                    i += 1;
                }
                path = source[expr_start..i];
            }
        }

        if (path == null) return null;

        // Resolve the path
        var resolved_path: ?[]const u8 = null;
        if (!is_dynamic) {
            resolved_path = try self.resolvePath(path.?, current_file);
        }

        return IncludeStatement{
            .path = try self.allocator.dupe(u8, path.?),
            .is_require = is_require,
            .is_once = is_once,
            .location = .{
                .file = current_file,
                .line = line,
                .column = col,
            },
            .resolved_path = resolved_path,
        };
    }

    /// Check if a path expression is dynamic (contains variables)
    pub fn isDynamicPath(self: *Self, path: []const u8) bool {
        _ = self;
        for (path) |c| {
            if (c == '$') return true;
        }
        return false;
    }

    /// Resolve a path to an absolute path
    fn resolvePath(self: *Self, path: []const u8, current_file: ?[]const u8) !?[]const u8 {
        // Handle absolute paths
        if (std.fs.path.isAbsolute(path)) {
            if (self.fileExists(path)) {
                return try self.allocator.dupe(u8, path);
            }
            return null;
        }

        // Try relative to current file first
        if (current_file) |cf| {
            if (std.fs.path.dirname(cf)) |dir| {
                const relative_path = try std.fs.path.join(self.allocator, &.{ dir, path });
                defer self.allocator.free(relative_path);
                if (self.fileExists(relative_path)) {
                    return try self.allocator.dupe(u8, relative_path);
                }
            }
        }

        // Try relative to base directory
        if (self.base_dir.len > 0) {
            const base_path = try std.fs.path.join(self.allocator, &.{ self.base_dir, path });
            defer self.allocator.free(base_path);
            if (self.fileExists(base_path)) {
                return try self.allocator.dupe(u8, base_path);
            }
        }

        // Try include paths
        for (self.include_paths.items) |inc_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ inc_path, path });
            defer self.allocator.free(full_path);
            if (self.fileExists(full_path)) {
                return try self.allocator.dupe(u8, full_path);
            }
        }

        // Try current working directory
        if (self.fileExists(path)) {
            const cwd = std.fs.cwd();
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const abs_path = cwd.realpath(path, &buf) catch return null;
            return try self.allocator.dupe(u8, abs_path);
        }

        return null;
    }

    /// Check if a file exists
    fn fileExists(self: *Self, path: []const u8) bool {
        _ = self;
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Record a circular dependency
    fn recordCycle(self: *Self, file_path: []const u8) !void {
        // Find where the cycle starts in the visit stack
        var cycle_start: usize = 0;
        for (self.visit_stack.items, 0..) |item, i| {
            if (std.mem.eql(u8, item, file_path)) {
                cycle_start = i;
                break;
            }
        }

        // Extract the cycle
        const cycle_len = self.visit_stack.items.len - cycle_start + 1;
        const cycle = try self.allocator.alloc([]const u8, cycle_len);
        for (self.visit_stack.items[cycle_start..], 0..) |item, i| {
            cycle[i] = item;
        }
        cycle[cycle_len - 1] = file_path; // Close the cycle

        try self.cycles.append(self.allocator, .{
            .cycle = cycle,
            .start_file = file_path,
        });

        // Report the error
        self.diagnostics.reportError(
            .{ .file = file_path },
            "circular dependency detected",
            .{},
        );
    }

    /// Get the compilation order (topological sort)
    pub fn getCompilationOrder(self: *Self) ![]const []const u8 {
        var order = std.ArrayListUnmanaged([]const u8){};
        var visited = std.StringHashMapUnmanaged(void){};
        defer visited.deinit(self.allocator);

        // Perform topological sort using DFS
        var it = self.files.iterator();
        while (it.next()) |entry| {
            try self.topologicalSort(entry.key_ptr.*, &order, &visited);
        }

        return try self.allocator.dupe([]const u8, order.items);
    }

    /// Topological sort helper (DFS post-order)
    fn topologicalSort(
        self: *Self,
        file_path: []const u8,
        order: *std.ArrayListUnmanaged([]const u8),
        visited: *std.StringHashMapUnmanaged(void),
    ) !void {
        if (visited.contains(file_path)) return;
        try visited.put(self.allocator, file_path, {});

        // Visit dependencies first
        if (self.files.get(file_path)) |node| {
            for (node.dependencies.items) |dep| {
                try self.topologicalSort(dep, order, visited);
            }
        }

        // Add this file after its dependencies
        try order.append(self.allocator, file_path);
    }

    /// Get all detected circular dependencies
    pub fn getCircularDependencies(self: *const Self) []const CircularDependency {
        return self.cycles.items;
    }

    /// Get all unresolved files
    pub fn getUnresolvedFiles(self: *const Self) []const UnresolvedFile {
        return self.unresolved.items;
    }

    /// Check if there are any circular dependencies
    pub fn hasCircularDependencies(self: *const Self) bool {
        return self.cycles.items.len > 0;
    }

    /// Check if there are any unresolved files
    pub fn hasUnresolvedFiles(self: *const Self) bool {
        return self.unresolved.items.len > 0;
    }

    /// Get the number of files in the dependency graph
    pub fn getFileCount(self: *const Self) usize {
        return self.files.count();
    }

    /// Get a file node by path
    pub fn getFileNode(self: *const Self, path: []const u8) ?FileNode {
        return self.files.get(path);
    }

    /// Get all file paths
    pub fn getAllFiles(self: *Self) ![]const []const u8 {
        var paths = std.ArrayListUnmanaged([]const u8){};
        var it = self.files.iterator();
        while (it.next()) |entry| {
            try paths.append(self.allocator, entry.key_ptr.*);
        }
        return try self.allocator.dupe([]const u8, paths.items);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "DependencyResolver initialization" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    try std.testing.expectEqual(@as(usize, 0), resolver.getFileCount());
    try std.testing.expect(!resolver.hasCircularDependencies());
    try std.testing.expect(!resolver.hasUnresolvedFiles());
}

test "DependencyResolver.matchKeyword" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    try std.testing.expect(resolver.matchKeyword("include 'file.php'", "include"));
    try std.testing.expect(resolver.matchKeyword("include('file.php')", "include"));
    try std.testing.expect(!resolver.matchKeyword("include_once 'file.php'", "include"));
    try std.testing.expect(resolver.matchKeyword("include_once 'file.php'", "include_once"));
    try std.testing.expect(resolver.matchKeyword("require 'file.php'", "require"));
    try std.testing.expect(!resolver.matchKeyword("required 'file.php'", "require"));
}

test "DependencyResolver.isDynamicPath" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    try std.testing.expect(!resolver.isDynamicPath("config.php"));
    try std.testing.expect(!resolver.isDynamicPath("lib/utils.php"));
    try std.testing.expect(resolver.isDynamicPath("$dir/config.php"));
    try std.testing.expect(resolver.isDynamicPath("${base}/file.php"));
}

test "DependencyResolver.extractIncludes basic" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source =
        \\<?php
        \\include 'config.php';
        \\require 'lib/utils.php';
        \\include_once "helpers.php";
        \\require_once('database.php');
    ;

    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| {
                allocator.free(rp);
            }
        }
        allocator.free(includes);
    }

    try std.testing.expectEqual(@as(usize, 4), includes.len);

    // Check first include
    try std.testing.expectEqualStrings("config.php", includes[0].path);
    try std.testing.expect(!includes[0].is_require);
    try std.testing.expect(!includes[0].is_once);

    // Check require
    try std.testing.expectEqualStrings("lib/utils.php", includes[1].path);
    try std.testing.expect(includes[1].is_require);
    try std.testing.expect(!includes[1].is_once);

    // Check include_once
    try std.testing.expectEqualStrings("helpers.php", includes[2].path);
    try std.testing.expect(!includes[2].is_require);
    try std.testing.expect(includes[2].is_once);

    // Check require_once
    try std.testing.expectEqualStrings("database.php", includes[3].path);
    try std.testing.expect(includes[3].is_require);
    try std.testing.expect(includes[3].is_once);
}

test "DependencyResolver add include path" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    try resolver.addIncludePath("/usr/share/php");
    try resolver.addIncludePath("/var/www/lib");

    try std.testing.expectEqual(@as(usize, 2), resolver.include_paths.items.len);
}
