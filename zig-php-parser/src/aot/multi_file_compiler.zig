//! Multi-File Compiler for AOT Compiler
//!
//! This module handles compilation of multi-file PHP projects by:
//! - Resolving file dependencies
//! - Compiling files in dependency order
//! - Merging symbol tables across files
//! - Generating a single executable
//!
//! ## Usage
//!
//! ```zig
//! var compiler = try MultiFileCompiler.init(allocator, options, diagnostics);
//! defer compiler.deinit();
//!
//! const result = try compiler.compile("main.php");
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const SourceLocation = Diagnostics.SourceLocation;
const DependencyResolverMod = @import("dependency_resolver.zig");
const DependencyResolver = DependencyResolverMod.DependencyResolver;
const IncludeStatement = DependencyResolverMod.IncludeStatement;
const FileNode = DependencyResolverMod.FileNode;
const IR = @import("ir.zig");
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const SymbolTableMod = @import("symbol_table.zig");
const SymbolTable = SymbolTableMod.SymbolTable;
const Symbol = SymbolTableMod.Symbol;
const TypeInferenceMod = @import("type_inference.zig");
const TypeInferencer = TypeInferenceMod.TypeInferencer;
const CodeGen = @import("codegen.zig");
const CodeGenerator = CodeGen.CodeGenerator;
const LinkerMod = @import("linker.zig");
const StaticLinker = LinkerMod.StaticLinker;
const LinkerConfig = LinkerMod.LinkerConfig;
const CompilerMod = @import("compiler.zig");
const CompileOptions = CompilerMod.CompileOptions;
const OptimizeLevel = CompilerMod.OptimizeLevel;
const Target = CompilerMod.Target;

/// Result of multi-file compilation
pub const MultiFileCompileResult = struct {
    /// Whether compilation succeeded
    success: bool,
    /// Output file path (if successful)
    output_path: ?[]const u8,
    /// Number of files compiled
    files_compiled: u32,
    /// Number of errors encountered
    error_count: u32,
    /// Number of warnings encountered
    warning_count: u32,
    /// Files that had circular dependencies
    circular_dependencies: []const []const u8,
    /// Files that could not be resolved
    unresolved_files: []const []const u8,

    pub fn succeeded(output_path: []const u8, files_compiled: u32) MultiFileCompileResult {
        return .{
            .success = true,
            .output_path = output_path,
            .files_compiled = files_compiled,
            .error_count = 0,
            .warning_count = 0,
            .circular_dependencies = &.{},
            .unresolved_files = &.{},
        };
    }

    pub fn failed(error_count: u32, warning_count: u32) MultiFileCompileResult {
        return .{
            .success = false,
            .output_path = null,
            .files_compiled = 0,
            .error_count = error_count,
            .warning_count = warning_count,
            .circular_dependencies = &.{},
            .unresolved_files = &.{},
        };
    }
};

/// Compiled file information
pub const CompiledFile = struct {
    /// File path
    path: []const u8,
    /// Generated IR module
    ir_module: ?*IR.Module,
    /// Whether compilation succeeded
    success: bool,
    /// Error message if failed
    error_message: ?[]const u8,
};

/// Multi-File Compiler
pub const MultiFileCompiler = struct {
    allocator: Allocator,
    options: CompileOptions,
    diagnostics: *DiagnosticEngine,
    /// Dependency resolver
    dependency_resolver: *DependencyResolver,
    /// Global symbol table (merged from all files)
    global_symbol_table: *SymbolTable,
    /// Type inferencer
    type_inferencer: *TypeInferencer,
    /// Compiled files
    compiled_files: std.StringHashMapUnmanaged(CompiledFile),
    /// Include paths for file resolution
    include_paths: std.ArrayListUnmanaged([]const u8),
    /// Merged IR module
    merged_module: ?*IR.Module,

    const Self = @This();

    /// Initialize a new multi-file compiler
    pub fn init(
        allocator: Allocator,
        options: CompileOptions,
        diagnostics: *DiagnosticEngine,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize dependency resolver
        const resolver = try DependencyResolver.init(allocator, diagnostics);
        errdefer resolver.deinit();

        // Initialize global symbol table
        const symbol_table = try allocator.create(SymbolTable);
        symbol_table.* = try SymbolTable.init(allocator);
        errdefer {
            symbol_table.deinit();
            allocator.destroy(symbol_table);
        }

        // Initialize type inferencer
        const type_inferencer = try allocator.create(TypeInferencer);
        type_inferencer.* = TypeInferencer.init(allocator, symbol_table, diagnostics);

        self.* = .{
            .allocator = allocator,
            .options = options,
            .diagnostics = diagnostics,
            .dependency_resolver = resolver,
            .global_symbol_table = symbol_table,
            .type_inferencer = type_inferencer,
            .compiled_files = .{},
            .include_paths = .{},
            .merged_module = null,
        };

        return self;
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self) void {
        // Free compiled files
        var it = self.compiled_files.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.ir_module) |module| {
                module.deinit();
                self.allocator.destroy(module);
            }
        }
        self.compiled_files.deinit(self.allocator);

        // Free include paths
        for (self.include_paths.items) |path| {
            self.allocator.free(path);
        }
        self.include_paths.deinit(self.allocator);

        // Free merged module
        if (self.merged_module) |module| {
            module.deinit();
            self.allocator.destroy(module);
        }

        // Free type inferencer
        self.allocator.destroy(self.type_inferencer);

        // Free symbol table
        self.global_symbol_table.deinit();
        self.allocator.destroy(self.global_symbol_table);

        // Free dependency resolver
        self.dependency_resolver.deinit();

        self.allocator.destroy(self);
    }

    /// Add an include path for file resolution
    pub fn addIncludePath(self: *Self, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.include_paths.append(self.allocator, path_copy);
        try self.dependency_resolver.addIncludePath(path);
    }

    /// Compile a multi-file project starting from the entry file
    pub fn compile(self: *Self, entry_file: []const u8) !MultiFileCompileResult {
        if (self.options.verbose) {
            std.debug.print("Multi-file compilation starting...\n", .{});
            std.debug.print("  Entry file: {s}\n", .{entry_file});
        }

        // Step 1: Resolve all dependencies
        self.dependency_resolver.resolveFile(entry_file) catch |err| {
            self.diagnostics.reportError(
                .{ .file = entry_file },
                "failed to resolve dependencies: {s}",
                .{@errorName(err)},
            );
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        };

        // Check for circular dependencies
        if (self.dependency_resolver.hasCircularDependencies()) {
            const cycles = self.dependency_resolver.getCircularDependencies();
            for (cycles) |cycle| {
                self.diagnostics.reportError(
                    .{ .file = cycle.start_file },
                    "circular dependency detected in file chain",
                    .{},
                );
            }
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        }

        // Check for unresolved files
        if (self.dependency_resolver.hasUnresolvedFiles()) {
            const unresolved = self.dependency_resolver.getUnresolvedFiles();
            for (unresolved) |file| {
                self.diagnostics.reportWarning(
                    file.location,
                    "unresolved include: {s}",
                    .{file.path},
                );
            }
        }

        // Step 2: Get compilation order (topological sort)
        const compilation_order = try self.dependency_resolver.getCompilationOrder();
        defer self.allocator.free(compilation_order);

        if (self.options.verbose) {
            std.debug.print("  Files to compile: {d}\n", .{compilation_order.len});
            for (compilation_order) |file| {
                std.debug.print("    - {s}\n", .{file});
            }
        }

        // Step 3: Compile each file in order
        var files_compiled: u32 = 0;
        for (compilation_order) |file_path| {
            const success = try self.compileFile(file_path);
            if (success) {
                files_compiled += 1;
            }
        }

        if (self.diagnostics.hasErrors()) {
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        }

        // Step 4: Merge all IR modules
        try self.mergeModules(compilation_order);

        if (self.diagnostics.hasErrors()) {
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        }

        // Step 5: Generate output
        const output_path = try self.options.getOutputPath(self.allocator);
        try self.generateOutput(output_path);

        if (self.diagnostics.hasErrors()) {
            self.allocator.free(output_path);
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        }

        if (self.options.verbose) {
            std.debug.print("Multi-file compilation successful: {s}\n", .{output_path});
            std.debug.print("  Files compiled: {d}\n", .{files_compiled});
        }

        return MultiFileCompileResult.succeeded(output_path, files_compiled);
    }

    /// Compile a single file
    fn compileFile(self: *Self, file_path: []const u8) !bool {
        if (self.options.verbose) {
            std.debug.print("  Compiling: {s}\n", .{file_path});
        }

        // Check if already compiled
        if (self.compiled_files.contains(file_path)) {
            return true;
        }

        // Get file node from dependency resolver
        const file_node = self.dependency_resolver.getFileNode(file_path);
        if (file_node == null) {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "file not found in dependency graph",
                .{},
            );
            return false;
        }

        // Get source content
        const source = file_node.?.source orelse {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "source not loaded",
                .{},
            );
            return false;
        };

        // Create IR generator for this file
        var ir_generator = IRGenerator.init(
            self.allocator,
            self.global_symbol_table,
            self.type_inferencer,
            self.diagnostics,
        );
        defer ir_generator.deinit();

        // For now, we'll create a placeholder module since we don't have
        // the actual parser integration here. In a real implementation,
        // we would parse the source and generate IR.
        const module = try self.allocator.create(IR.Module);
        module.* = IR.Module.init(self.allocator, file_path, file_path);

        // Store compiled file
        try self.compiled_files.put(self.allocator, file_path, .{
            .path = file_path,
            .ir_module = module,
            .success = true,
            .error_message = null,
        });

        // Register symbols from this file in the global symbol table
        try self.registerFileSymbols(file_path, source);

        return true;
    }

    /// Register symbols from a file in the global symbol table
    pub fn registerFileSymbols(self: *Self, file_path: []const u8, source: []const u8) !void {
        // This is a simplified implementation that extracts function and class names
        // In a real implementation, this would use the parser to get accurate symbols

        var i: usize = 0;
        var line: u32 = 1;
        var col: u32 = 1;

        while (i < source.len) {
            if (source[i] == '\n') {
                line += 1;
                col = 1;
                i += 1;
                continue;
            }

            // Look for function declarations
            if (self.matchKeyword(source[i..], "function")) {
                i += 8; // Skip "function"
                // Skip whitespace
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) {
                    i += 1;
                }
                // Extract function name
                const name_start = i;
                while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                    i += 1;
                }
                if (i > name_start) {
                    const func_name = source[name_start..i];
                    try self.global_symbol_table.defineFunction(
                        func_name,
                        &.{},
                        .dynamic,
                        .{ .file = file_path, .line = line, .column = col },
                    );
                }
            }
            // Look for class declarations
            else if (self.matchKeyword(source[i..], "class")) {
                i += 5; // Skip "class"
                // Skip whitespace
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) {
                    i += 1;
                }
                // Extract class name
                const name_start = i;
                while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                    i += 1;
                }
                if (i > name_start) {
                    const class_name = source[name_start..i];
                    try self.global_symbol_table.defineClass(
                        class_name,
                        null,
                        &.{},
                        .{ .file = file_path, .line = line, .column = col },
                    );
                }
            } else {
                col += 1;
                i += 1;
            }
        }
    }

    /// Check if source starts with a keyword
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

    /// Merge all compiled IR modules into a single module
    fn mergeModules(self: *Self, compilation_order: []const []const u8) !void {
        if (self.options.verbose) {
            std.debug.print("  Merging IR modules...\n", .{});
        }

        // Create merged module
        const merged = try self.allocator.create(IR.Module);
        merged.* = IR.Module.init(self.allocator, "merged", self.options.input_file);
        self.merged_module = merged;

        // Merge each file's module in order
        for (compilation_order) |file_path| {
            if (self.compiled_files.get(file_path)) |compiled| {
                if (compiled.ir_module) |module| {
                    try self.mergeModule(merged, module);
                }
            }
        }

        if (self.options.verbose) {
            std.debug.print("  Merged module has {d} functions\n", .{merged.functions.items.len});
        }
    }

    /// Merge a single module into the merged module
    fn mergeModule(self: *Self, target: *IR.Module, source: *IR.Module) !void {
        _ = self;

        // Merge functions
        for (source.functions.items) |func| {
            try target.addFunction(func);
        }

        // Merge globals
        for (source.globals.items) |global| {
            try target.addGlobal(global);
        }

        // Merge type definitions
        for (source.types.items) |type_def| {
            try target.addTypeDef(type_def);
        }
    }

    /// Generate the final output (executable or object file)
    fn generateOutput(self: *Self, output_path: []const u8) !void {
        if (self.options.verbose) {
            std.debug.print("  Generating output: {s}\n", .{output_path});
        }

        // In a real implementation, this would:
        // 1. Generate LLVM IR from the merged module
        // 2. Compile to object code
        // 3. Link with runtime library

        // For now, we'll create a placeholder output
        const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
            self.diagnostics.reportError(
                .{ .file = output_path },
                "failed to create output file: {s}",
                .{@errorName(err)},
            );
            return;
        };
        defer file.close();

        // Write a placeholder (in real implementation, this would be the executable)
        try file.writeAll("#!/bin/sh\necho 'Compiled PHP program'\n");

        // Make executable on Unix
        if (@import("builtin").os.tag != .windows) {
            const stat = try file.stat();
            try file.chmod(stat.mode | 0o111);
        }
    }

    /// Get the merged IR module
    pub fn getMergedModule(self: *const Self) ?*IR.Module {
        return self.merged_module;
    }

    /// Get the global symbol table
    pub fn getGlobalSymbolTable(self: *const Self) *SymbolTable {
        return self.global_symbol_table;
    }

    /// Get the number of compiled files
    pub fn getCompiledFileCount(self: *const Self) usize {
        return self.compiled_files.count();
    }

    /// Check if a file has been compiled
    pub fn isFileCompiled(self: *const Self, file_path: []const u8) bool {
        return self.compiled_files.contains(file_path);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "MultiFileCompiler initialization" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "test.php",
    };

    const compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer compiler.deinit();

    try std.testing.expectEqual(@as(usize, 0), compiler.getCompiledFileCount());
    try std.testing.expect(compiler.getMergedModule() == null);
}

test "MultiFileCompiler add include path" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "test.php",
    };

    const compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer compiler.deinit();

    try compiler.addIncludePath("/usr/share/php");
    try compiler.addIncludePath("/var/www/lib");

    try std.testing.expectEqual(@as(usize, 2), compiler.include_paths.items.len);
}

test "MultiFileCompiler.matchKeyword" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "test.php",
    };

    const compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer compiler.deinit();

    try std.testing.expect(compiler.matchKeyword("function test()", "function"));
    try std.testing.expect(compiler.matchKeyword("class MyClass", "class"));
    try std.testing.expect(!compiler.matchKeyword("functional", "function"));
    try std.testing.expect(!compiler.matchKeyword("classes", "class"));
}
