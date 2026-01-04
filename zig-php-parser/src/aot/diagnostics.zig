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
            .note => "\x1b[36m",    // Cyan
            .warning => "\x1b[33m", // Yellow
            .@"error" => "\x1b[31m", // Red
        };
    }
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
};

/// A single diagnostic message
pub const Diagnostic = struct {
    /// Severity level
    severity: Severity,
    /// Main diagnostic message
    message: []const u8,
    /// Source location where the diagnostic occurred
    location: SourceLocation,
    /// Optional hint for fixing the issue
    hint: ?[]const u8 = null,
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

    /// Report an error
    pub fn reportError(self: *Self, location: SourceLocation, comptime fmt: []const u8, args: anytype) void {
        self.report(.@"error", location, fmt, args);
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
        try writer.print("{s}{}{s}: {s}{s}{s}: {s}\n", .{
            bold,
            diag.location,
            reset,
            color,
            diag.severity.toString(),
            reset,
            diag.message,
        });

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

        // Print related notes
        for (diag.notes) |note| {
            if (note.location) |loc| {
                try writer.print("    {s}note{s}: {}: {s}\n", .{ color, reset, loc, note.message });
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

        // Print location and severity
        if (diag.location.line > 0) {
            std.debug.print("{s}{s}:{d}:{d}{s}: {s}{s}{s}: {s}\n", .{
                bold,
                diag.location.file,
                diag.location.line,
                diag.location.column,
                reset,
                color,
                diag.severity.toString(),
                reset,
                diag.message,
            });
        } else {
            std.debug.print("{s}{s}{s}: {s}{s}{s}: {s}\n", .{
                bold,
                diag.location.file,
                reset,
                color,
                diag.severity.toString(),
                reset,
                diag.message,
            });
        }

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

        // Print related notes
        for (diag.notes) |note| {
            if (note.location) |loc| {
                if (loc.line > 0) {
                    std.debug.print("    {s}note{s}: {s}:{d}:{d}: {s}\n", .{ color, reset, loc.file, loc.line, loc.column, note.message });
                } else {
                    std.debug.print("    {s}note{s}: {s}: {s}\n", .{ color, reset, loc.file, note.message });
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
