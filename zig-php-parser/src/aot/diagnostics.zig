//! Diagnostic Engine for AOT Compiler
//!
//! Provides error and warning collection, formatting, and reporting
//! for the AOT compilation process.

const std = @import("std");

/// Severity level of a diagnostic message
pub const Severity = enum {
    /// Informational message
    note,
    /// Warning that doesn't prevent compilation
    warning,
    /// Error that prevents successful compilation
    @"error",

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .note => "note",
            .warning => "warning",
            .@"error" => "error",
        };
    }

    pub fn toColor(self: Severity) []const u8 {
        return switch (self) {
            .note => "\x1b[36m", // Cyan
            .warning => "\x1b[33m", // Yellow
            .@"error" => "\x1b[31m", // Red
        };
    }
};

/// CWE (Common Weakness Enumeration) identifier
/// @see https://cwe.mitre.org/
pub const CWE = enum(u32) {
    // Memory Safety
    buffer_overflow = 119,
    use_after_free = 416,
    null_pointer_dereference = 476,
    double_free = 415,
    memory_leak = 401,
    uninitialized_memory = 457,

    // Type Safety
    type_confusion = 843,
    improper_type_validation = 1287,

    // Resource Management
    resource_exhaustion = 400,
    improper_resource_shutdown = 404,

    // Code Quality
    dead_code = 561,
    // unreachable_code shares same CWE as dead_code

    // Concurrency
    data_race = 362,
    deadlock = 833,

    // Input Validation
    improper_input_validation = 20,
    integer_overflow = 190,
    division_by_zero = 369,

    // Logic Errors
    incorrect_calculation = 682,
    off_by_one = 193,

    // Security
    injection = 94,
    path_traversal = 22,

    // Undefined Behavior
    undefined_behavior = 758,

    // Other
    unknown = 0,

    pub fn toString(self: CWE) []const u8 {
        return switch (self) {
            .buffer_overflow => "CWE-119: Buffer Overflow",
            .use_after_free => "CWE-416: Use After Free",
            .null_pointer_dereference => "CWE-476: NULL Pointer Dereference",
            .double_free => "CWE-415: Double Free",
            .memory_leak => "CWE-401: Memory Leak",
            .uninitialized_memory => "CWE-457: Use of Uninitialized Variable",
            .type_confusion => "CWE-843: Type Confusion",
            .improper_type_validation => "CWE-1287: Improper Type Validation",
            .resource_exhaustion => "CWE-400: Resource Exhaustion",
            .improper_resource_shutdown => "CWE-404: Improper Resource Shutdown",
            .dead_code => "CWE-561: Dead Code",
            .data_race => "CWE-362: Data Race",
            .deadlock => "CWE-833: Deadlock",
            .improper_input_validation => "CWE-20: Improper Input Validation",
            .integer_overflow => "CWE-190: Integer Overflow",
            .division_by_zero => "CWE-369: Division by Zero",
            .incorrect_calculation => "CWE-682: Incorrect Calculation",
            .off_by_one => "CWE-193: Off-by-one Error",
            .injection => "CWE-94: Code Injection",
            .path_traversal => "CWE-22: Path Traversal",
            .undefined_behavior => "CWE-758: Undefined Behavior",
            .unknown => "CWE-0: Unknown",
        };
    }

    pub fn getUrl(self: CWE) []const u8 {
        var buf: [100]u8 = undefined;
        const url = std.fmt.bufPrint(&buf, "https://cwe.mitre.org/data/definitions/{d}.html", .{@intFromEnum(self)}) catch return "";
        return url;
    }
};

/// Fix suggestion for a diagnostic
pub const FixSuggestion = struct {
    /// Description of the fix
    description: []const u8,
    /// Optional code replacement
    replacement: ?[]const u8 = null,
    /// Location where the fix should be applied
    location: ?SourceLocation = null,
};

/// Source location information
pub const SourceLocation = struct {
    /// File path or name
    file: []const u8 = "<unknown>",
    /// Line number (1-based)
    line: u32 = 0,
    /// Column number (1-based)
    column: u32 = 0,
    /// Length of the source span (for highlighting)
    length: u32 = 1,

    pub fn format(
        self: SourceLocation,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (self.line > 0) {
            try writer.print("{s}:{d}:{d}", .{ self.file, self.line, self.column });
        } else {
            try writer.print("{s}", .{self.file});
        }
    }

    /// Convert to string for display
    pub fn toString(self: SourceLocation, allocator: std.mem.Allocator) ![]const u8 {
        if (self.line > 0) {
            return std.fmt.allocPrint(allocator, "{s}:{d}:{d}", .{ self.file, self.line, self.column });
        }

        return std.fmt.allocPrint(allocator, "{s}", .{self.file});
    }
};

/// A single diagnostic message
pub const Diagnostic = struct {
    /// Severity level
    severity: Severity,
    /// Main diagnostic message
    message: []const u8,
    /// Source location where the diagnostic occurred
    location: SourceLocation,
    /// Optional CWE identifier
    cwe: ?CWE = null,
    /// Optional hint for fixing the issue
    hint: ?[]const u8 = null,
    /// Optional fix suggestions
    fix_suggestions: []const FixSuggestion = &.{},
    /// Optional related notes
    notes: []const Note = &.{},

    pub const Note = struct {
        message: []const u8,
        location: ?SourceLocation = null,
    };
};

/// Diagnostic engine for collecting and reporting compilation diagnostics
pub const DiagnosticEngine = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.ArrayListUnmanaged(Diagnostic),
    error_count: u32 = 0,
    warning_count: u32 = 0,
    /// Whether to use colored output
    use_colors: bool = true,
    /// Source code lines for context display (optional)
    source_lines: ?[]const []const u8 = null,
    path_base: ?[]const u8 = null,

    const Self = @This();

    /// Initialize a new diagnostic engine
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .diagnostics = .{},
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        if (self.path_base) |base| {
            self.allocator.free(base);
            self.path_base = null;
        }
        // Free allocated messages
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.diagnostics.deinit(self.allocator);

        // Free source lines if allocated
        if (self.source_lines) |lines| {
            self.allocator.free(lines);
        }
    }

    /// Set source code for context display
    pub fn setSource(self: *Self, source: []const u8) !void {
        var lines = std.ArrayListUnmanaged([]const u8){};
        errdefer lines.deinit(self.allocator);

        var it = std.mem.splitScalar(u8, source, '\n');
        while (it.next()) |line| {
            try lines.append(self.allocator, line);
        }

        self.source_lines = try lines.toOwnedSlice(self.allocator);
    }

    pub fn setPathBase(self: *Self, base_dir: []const u8) !void {
        if (self.path_base) |old| {
            self.allocator.free(old);
            self.path_base = null;
        }

        const has_sep = base_dir.len > 0 and (base_dir[base_dir.len - 1] == std.fs.path.sep);
        const normalized = if (has_sep)
            try self.allocator.dupe(u8, base_dir)
        else
            try std.fmt.allocPrint(self.allocator, "{s}{c}", .{ base_dir, std.fs.path.sep });
        self.path_base = normalized;
    }

    fn relativizePath(self: *const Self, path: []const u8) []const u8 {
        const base = self.path_base orelse return path;
        if (std.mem.startsWith(u8, path, base)) {
            return path[base.len..];
        }
        return path;
    }

    /// Report an error
    pub fn reportError(self: *Self, location: SourceLocation, comptime fmt: []const u8, args: anytype) void {
        self.report(.@"error", location, fmt, args);
    }

    /// Report an error with CWE
    pub fn reportErrorWithCWE(
        self: *Self,
        location: SourceLocation,
        cwe: CWE,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return;

        self.diagnostics.append(self.allocator, .{
            .severity = .@"error",
            .message = message,
            .location = location,
            .cwe = cwe,
        }) catch return;

        self.error_count += 1;
    }

    /// Report an error with CWE and fix suggestion
    pub fn reportErrorWithFix(
        self: *Self,
        location: SourceLocation,
        cwe: CWE,
        message: []const u8,
        fix_suggestions: []const FixSuggestion,
    ) void {
        self.diagnostics.append(self.allocator, .{
            .severity = .@"error",
            .message = message,
            .location = location,
            .cwe = cwe,
            .fix_suggestions = fix_suggestions,
        }) catch return;

        self.error_count += 1;
    }

    /// Report a warning with CWE
    pub fn reportWarningWithCWE(
        self: *Self,
        location: SourceLocation,
        cwe: CWE,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return;

        self.diagnostics.append(self.allocator, .{
            .severity = .warning,
            .message = message,
            .location = location,
            .cwe = cwe,
        }) catch return;

        self.warning_count += 1;
    }

    /// Report a warning
    pub fn reportWarning(self: *Self, location: SourceLocation, comptime fmt: []const u8, args: anytype) void {
        self.report(.warning, location, fmt, args);
    }

    /// Report a note
    pub fn reportNote(self: *Self, location: SourceLocation, comptime fmt: []const u8, args: anytype) void {
        self.report(.note, location, fmt, args);
    }

    /// Report a diagnostic with the given severity
    pub fn report(self: *Self, severity: Severity, location: SourceLocation, comptime fmt: []const u8, args: anytype) void {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return;

        self.diagnostics.append(self.allocator, .{
            .severity = severity,
            .message = message,
            .location = location,
        }) catch return;

        switch (severity) {
            .@"error" => self.error_count += 1,
            .warning => self.warning_count += 1,
            .note => {},
        }
    }

    /// Report a diagnostic with a hint
    pub fn reportWithHint(
        self: *Self,
        severity: Severity,
        location: SourceLocation,
        message: []const u8,
        hint: []const u8,
    ) void {
        self.diagnostics.append(self.allocator, .{
            .severity = severity,
            .message = message,
            .location = location,
            .hint = hint,
        }) catch return;

        switch (severity) {
            .@"error" => self.error_count += 1,
            .warning => self.warning_count += 1,
            .note => {},
        }
    }

    /// Check if there are any errors
    pub fn hasErrors(self: *const Self) bool {
        return self.error_count > 0;
    }

    /// Check if there are any warnings
    pub fn hasWarnings(self: *const Self) bool {
        return self.warning_count > 0;
    }

    /// Get total diagnostic count
    pub fn count(self: *const Self) usize {
        return self.diagnostics.items.len;
    }

    /// Clear all diagnostics
    pub fn clear(self: *Self) void {
        // Free allocated messages
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.diagnostics.clearRetainingCapacity();
        self.error_count = 0;
        self.warning_count = 0;
    }

    /// Print all diagnostics to the given writer
    pub fn render(self: *const Self, writer: anytype) !void {
        for (self.diagnostics.items) |diag| {
            try self.renderDiagnostic(writer, diag);
        }

        // Print summary
        if (self.error_count > 0 or self.warning_count > 0) {
            try writer.writeAll("\n");
            if (self.use_colors) {
                if (self.error_count > 0) {
                    try writer.print("\x1b[31m{d} error(s)\x1b[0m", .{self.error_count});
                    if (self.warning_count > 0) {
                        try writer.writeAll(", ");
                    }
                }
                if (self.warning_count > 0) {
                    try writer.print("\x1b[33m{d} warning(s)\x1b[0m", .{self.warning_count});
                }
            } else {
                if (self.error_count > 0) {
                    try writer.print("{d} error(s)", .{self.error_count});
                    if (self.warning_count > 0) {
                        try writer.writeAll(", ");
                    }
                }
                if (self.warning_count > 0) {
                    try writer.print("{d} warning(s)", .{self.warning_count});
                }
            }
            try writer.writeAll(" generated.\n");
        }
    }

    /// Render a single diagnostic
    fn renderDiagnostic(self: *const Self, writer: anytype, diag: Diagnostic) !void {
        const reset = if (self.use_colors) "\x1b[0m" else "";
        const bold = if (self.use_colors) "\x1b[1m" else "";
        const color = if (self.use_colors) diag.severity.toColor() else "";

        // Print location and severity
        try writer.print("{s}", .{bold});

        const rel_path = self.relativizePath(diag.location.file);

        if (diag.location.line > 0) {
            try writer.print("{s}:{d}:{d}", .{ rel_path, diag.location.line, diag.location.column });
        } else {
            try writer.print("{s}", .{rel_path});
        }
        try writer.print("{s}: {s}{s}{s}: {s}", .{
            reset,
            color,
            diag.severity.toString(),
            reset,
            diag.message,
        });

        // Print CWE if available
        if (diag.cwe) |cwe| {
            try writer.print(" [{s}]", .{cwe.toString()});
        }

        try writer.writeAll("\n");

        // Print source context if available
        if (self.source_lines) |lines| {
            if (diag.location.line > 0 and diag.location.line <= lines.len) {
                const line_idx = diag.location.line - 1;
                const source_line = lines[line_idx];

                // Print line number and source
                try writer.print("  {d} | {s}\n", .{ diag.location.line, source_line });

                // Print caret indicator
                try writer.writeAll("    | ");
                var col: u32 = 1;
                while (col < diag.location.column) : (col += 1) {
                    try writer.writeByte(' ');
                }
                try writer.print("{s}^", .{color});
                var len: u32 = 1;
                while (len < diag.location.length) : (len += 1) {
                    try writer.writeByte('~');
                }
                try writer.print("{s}\n", .{reset});
            }
        }

        // Print hint if available
        if (diag.hint) |hint| {
            const hint_color = if (self.use_colors) "\x1b[32m" else "";
            try writer.print("    {s}hint{s}: {s}\n", .{ hint_color, reset, hint });
        }

        // Print fix suggestions
        if (diag.fix_suggestions.len > 0) {
            const fix_color = if (self.use_colors) "\x1b[32m" else "";
            try writer.print("    {s}fix{s}:\n", .{ fix_color, reset });
            for (diag.fix_suggestions) |fix| {
                try writer.print("      - {s}\n", .{fix.description});
                if (fix.replacement) |replacement| {
                    try writer.print("        {s}suggestion{s}: {s}\n", .{ fix_color, reset, replacement });
                }
            }
        }

        // Print CWE URL if available
        if (diag.cwe) |cwe| {
            if (@intFromEnum(cwe) > 0) {
                const url_color = if (self.use_colors) "\x1b[34m" else "";
                try writer.print("    {s}info{s}: https://cwe.mitre.org/data/definitions/{d}.html\n", .{ url_color, reset, @intFromEnum(cwe) });
            }
        }

        // Print related notes
        for (diag.notes) |note| {
            if (note.location) |loc| {
                const note_path = self.relativizePath(loc.file);
                if (loc.line > 0) {
                    try writer.print(
                        "    {s}note{s}: {s}:{d}:{d}: {s}\n",
                        .{ color, reset, note_path, loc.line, loc.column, note.message },
                    );
                } else {
                    try writer.print("    {s}note{s}: {s}: {s}\n", .{ color, reset, note_path, note.message });
                }
            } else {
                try writer.print("    {s}note{s}: {s}\n", .{ color, reset, note.message });
            }
        }
    }

    /// Print diagnostics to stderr
    pub fn printToStderr(self: *const Self) void {
        // Use debug print for stderr output
        for (self.diagnostics.items) |diag| {
            self.printDiagnostic(diag);
        }

        // Print summary
        if (self.error_count > 0 or self.warning_count > 0) {
            std.debug.print("\n", .{});
            if (self.error_count > 0) {
                if (self.use_colors) {
                    std.debug.print("\x1b[31m{d} error(s)\x1b[0m", .{self.error_count});
                } else {
                    std.debug.print("{d} error(s)", .{self.error_count});
                }
                if (self.warning_count > 0) {
                    std.debug.print(", ", .{});
                }
            }
            if (self.warning_count > 0) {
                if (self.use_colors) {
                    std.debug.print("\x1b[33m{d} warning(s)\x1b[0m", .{self.warning_count});
                } else {
                    std.debug.print("{d} warning(s)", .{self.warning_count});
                }
            }
            std.debug.print(" generated.\n", .{});
        }
    }

    /// Print a single diagnostic using debug.print
    fn printDiagnostic(self: *const Self, diag: Diagnostic) void {
        const reset = if (self.use_colors) "\x1b[0m" else "";
        const bold = if (self.use_colors) "\x1b[1m" else "";
        const color = if (self.use_colors) diag.severity.toColor() else "";

        const rel_path = self.relativizePath(diag.location.file);

        if (diag.location.line > 0) {
            std.debug.print("{s}{s}:{d}:{d}{s}: {s}{s}{s}: {s}", .{
                bold,
                rel_path,
                diag.location.line,
                diag.location.column,
                reset,
                color,
                diag.severity.toString(),
                reset,
                diag.message,
            });
        } else {
            std.debug.print("{s}{s}{s}: {s}{s}{s}: {s}", .{
                bold,
                rel_path,
                reset,
                color,
                diag.severity.toString(),
                reset,
                diag.message,
            });
        }

        // Print CWE if available
        if (diag.cwe) |cwe| {
            std.debug.print(" [{s}]", .{cwe.toString()});
        }

        std.debug.print("\n", .{});

        // Print source context if available
        if (self.source_lines) |lines| {
            if (diag.location.line > 0 and diag.location.line <= lines.len) {
                const line_idx = diag.location.line - 1;
                const source_line = lines[line_idx];

                // Print line number and source
                std.debug.print("  {d} | {s}\n", .{ diag.location.line, source_line });

                // Print caret indicator
                std.debug.print("    | ", .{});
                var col: u32 = 1;
                while (col < diag.location.column) : (col += 1) {
                    std.debug.print(" ", .{});
                }
                std.debug.print("{s}^", .{color});
                var len: u32 = 1;
                while (len < diag.location.length) : (len += 1) {
                    std.debug.print("~", .{});
                }
                std.debug.print("{s}\n", .{reset});
            }
        }

        // Print hint if available
        if (diag.hint) |hint| {
            const hint_color = if (self.use_colors) "\x1b[32m" else "";
            std.debug.print("    {s}hint{s}: {s}\n", .{ hint_color, reset, hint });
        }

        // Print fix suggestions
        if (diag.fix_suggestions.len > 0) {
            const fix_color = if (self.use_colors) "\x1b[32m" else "";
            std.debug.print("    {s}fix{s}:\n", .{ fix_color, reset });
            for (diag.fix_suggestions) |fix| {
                std.debug.print("      - {s}\n", .{fix.description});
                if (fix.replacement) |replacement| {
                    std.debug.print("        {s}suggestion{s}: {s}\n", .{ fix_color, reset, replacement });
                }
            }
        }

        // Print CWE URL if available
        if (diag.cwe) |cwe| {
            if (@intFromEnum(cwe) > 0) {
                const url_color = if (self.use_colors) "\x1b[34m" else "";
                std.debug.print("    {s}info{s}: https://cwe.mitre.org/data/definitions/{d}.html\n", .{ url_color, reset, @intFromEnum(cwe) });
            }
        }

        // Print related notes
        for (diag.notes) |note| {
            if (note.location) |loc| {
                const note_path = self.relativizePath(loc.file);
                if (loc.line > 0) {
                    std.debug.print("    {s}note{s}: {s}:{d}:{d}: {s}\n", .{ color, reset, note_path, loc.line, loc.column, note.message });
                } else {
                    std.debug.print("    {s}note{s}: {s}: {s}\n", .{ color, reset, note_path, note.message });
                }
            } else {
                std.debug.print("    {s}note{s}: {s}\n", .{ color, reset, note.message });
            }
        }
    }
};

// Convenience functions for creating common diagnostics

/// Create a syntax error diagnostic
pub fn syntaxError(location: SourceLocation, message: []const u8) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
    };
}

/// Create a type error diagnostic
pub fn typeError(location: SourceLocation, message: []const u8) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
    };
}

/// Create an undefined symbol error
pub fn undefinedSymbol(location: SourceLocation, symbol_name: []const u8, allocator: std.mem.Allocator) !Diagnostic {
    const message = try std.fmt.allocPrint(allocator, "undefined symbol '{s}'", .{symbol_name});
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
    };
}

/// Create a buffer overflow error with CWE and fix suggestion
pub fn bufferOverflowError(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
        .cwe = .buffer_overflow,
        .fix_suggestions = fix_suggestions,
    };
}

/// Create a null pointer dereference error
pub fn nullPointerError(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
        .cwe = .null_pointer_dereference,
        .fix_suggestions = fix_suggestions,
    };
}

/// Create a memory leak warning
pub fn memoryLeakWarning(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .warning,
        .message = message,
        .location = location,
        .cwe = .memory_leak,
        .fix_suggestions = fix_suggestions,
    };
}

/// Create a data race error
pub fn dataRaceError(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
        .cwe = .data_race,
        .fix_suggestions = fix_suggestions,
    };
}

/// Create a dead code warning
pub fn deadCodeWarning(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .warning,
        .message = message,
        .location = location,
        .cwe = .dead_code,
        .fix_suggestions = fix_suggestions,
    };
}

/// Create an integer overflow error
pub fn integerOverflowError(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
        .cwe = .integer_overflow,
        .fix_suggestions = fix_suggestions,
    };
}

/// Create a division by zero error
pub fn divisionByZeroError(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
        .cwe = .division_by_zero,
        .fix_suggestions = fix_suggestions,
    };
}

/// Create a type confusion error
pub fn typeConfusionError(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
        .cwe = .type_confusion,
        .fix_suggestions = fix_suggestions,
    };
}

// Tests
test "DiagnosticEngine basic usage" {
    const allocator = std.testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    engine.reportError(.{ .file = "test.php", .line = 10, .column = 5 }, "unexpected token '{s}'", .{";"});
    engine.reportWarning(.{ .file = "test.php", .line = 15, .column = 1 }, "unused variable '{s}'", .{"$x"});

    try std.testing.expectEqual(@as(u32, 1), engine.error_count);
    try std.testing.expectEqual(@as(u32, 1), engine.warning_count);
    try std.testing.expect(engine.hasErrors());
    try std.testing.expect(engine.hasWarnings());
}

test "DiagnosticEngine clear" {
    const allocator = std.testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    engine.reportError(.{}, "test error", .{});
    try std.testing.expectEqual(@as(u32, 1), engine.error_count);

    engine.clear();
    try std.testing.expectEqual(@as(u32, 0), engine.error_count);
    try std.testing.expect(!engine.hasErrors());
}

test "SourceLocation format" {
    const loc = SourceLocation{ .file = "test.php", .line = 42, .column = 10 };

    // Test the format function directly by using a buffer writer
    var buf: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try loc.format("", .{}, fbs.writer());
    const result = fbs.getWritten();
    try std.testing.expectEqualStrings("test.php:42:10", result);
}

test "Severity toString" {
    try std.testing.expectEqualStrings("error", Severity.@"error".toString());
    try std.testing.expectEqualStrings("warning", Severity.warning.toString());
    try std.testing.expectEqualStrings("note", Severity.note.toString());
}

test "CWE toString" {
    try std.testing.expectEqualStrings("CWE-119: Buffer Overflow", CWE.buffer_overflow.toString());
    try std.testing.expectEqualStrings("CWE-416: Use After Free", CWE.use_after_free.toString());
    try std.testing.expectEqualStrings("CWE-476: NULL Pointer Dereference", CWE.null_pointer_dereference.toString());
    try std.testing.expectEqualStrings("CWE-362: Data Race", CWE.data_race.toString());
}

test "DiagnosticEngine with CWE" {
    const allocator = std.testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{ .file = "test.php", .line = 10, .column = 5 };
    engine.reportErrorWithCWE(loc, .buffer_overflow, "potential buffer overflow detected", .{});

    try std.testing.expectEqual(@as(u32, 1), engine.error_count);
    try std.testing.expect(engine.hasErrors());

    const diag = engine.diagnostics.items[0];
    try std.testing.expectEqual(CWE.buffer_overflow, diag.cwe.?);
}

test "DiagnosticEngine with fix suggestions" {
    const allocator = std.testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{ .file = "test.php", .line = 10, .column = 5 };

    // 使用静态数组避免内存问题
    const fix1 = FixSuggestion{
        .description = "Add bounds checking before array access",
        .replacement = "if (index < array.len) { ... }",
    };
    const fix2 = FixSuggestion{
        .description = "Use safe array access method",
        .replacement = "array.get(index)",
    };
    const fixes = [_]FixSuggestion{ fix1, fix2 };

    const message = try std.fmt.allocPrint(allocator, "array index out of bounds", .{});
    engine.reportErrorWithFix(loc, .buffer_overflow, message, &fixes);

    try std.testing.expectEqual(@as(u32, 1), engine.error_count);

    const diag = engine.diagnostics.items[0];
    try std.testing.expectEqual(@as(usize, 2), diag.fix_suggestions.len);
    try std.testing.expectEqualStrings("Add bounds checking before array access", diag.fix_suggestions[0].description);
}

test "Convenience diagnostic functions" {
    const allocator = std.testing.allocator;
    const loc = SourceLocation{ .file = "test.php", .line = 10, .column = 5 };

    const fixes = [_]FixSuggestion{
        .{ .description = "Check for null before dereferencing" },
    };

    const diag1 = bufferOverflowError(loc, "buffer overflow", &fixes);
    try std.testing.expectEqual(CWE.buffer_overflow, diag1.cwe.?);
    try std.testing.expectEqual(Severity.@"error", diag1.severity);

    const diag2 = nullPointerError(loc, "null pointer", &fixes);
    try std.testing.expectEqual(CWE.null_pointer_dereference, diag2.cwe.?);

    const diag3 = dataRaceError(loc, "data race", &fixes);
    try std.testing.expectEqual(CWE.data_race, diag3.cwe.?);

    const diag4 = deadCodeWarning(loc, "unreachable code", &fixes);
    try std.testing.expectEqual(CWE.dead_code, diag4.cwe.?);
    try std.testing.expectEqual(Severity.warning, diag4.severity);

    _ = allocator;
}

test "DiagnosticEngine render with CWE and fixes" {
    const allocator = std.testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{ .file = "test.php", .line = 10, .column = 5, .length = 3 };
    const fix1 = FixSuggestion{
        .description = "Add null check",
        .replacement = "if (ptr != null) { ... }",
    };
    const fixes = [_]FixSuggestion{fix1};

    const message = try std.fmt.allocPrint(allocator, "potential null pointer dereference", .{});
    engine.reportErrorWithFix(loc, .null_pointer_dereference, message, &fixes);

    // Test rendering to a buffer
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try engine.render(fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "CWE-476") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Add null check") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "https://cwe.mitre.org") != null);
}

test "DiagnosticEngine path base relativize" {
    const allocator = std.testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();
    engine.use_colors = false;

    try engine.setPathBase("/repo/project");
    engine.reportError(.{ .file = "/repo/project/examples/tests/basic/test.php", .line = 3, .column = 2 }, "msg", .{});

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try engine.render(fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, output, "examples/tests/basic/test.php:3:2"));
}
