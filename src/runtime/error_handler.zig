//! 运行时错误处理模块
//!
//! 实现除零检测、数组越界检测、类型错误检测等运行时错误处理。
//!
//! @ownership ISOLATED
//! @thread-safety SINGLE_THREADED

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// 运行时错误类型
// ============================================================================

/// PHP 运行时错误类型
pub const RuntimeErrorType = enum {
    division_by_zero,
    array_index_out_of_bounds,
    type_error,
    null_reference,
    undefined_variable,
    undefined_function,
    argument_count_error,
    value_error,
    overflow_error,
    memory_error,
    fatal_error,

    /// 获取错误名称
    pub fn name(self: RuntimeErrorType) []const u8 {
        return switch (self) {
            .division_by_zero => "DivisionByZeroError",
            .array_index_out_of_bounds => "OutOfBoundsError",
            .type_error => "TypeError",
            .null_reference => "NullReferenceError",
            .undefined_variable => "UndefinedVariableError",
            .undefined_function => "UndefinedFunctionError",
            .argument_count_error => "ArgumentCountError",
            .value_error => "ValueError",
            .overflow_error => "OverflowError",
            .memory_error => "MemoryError",
            .fatal_error => "FatalError",
        };
    }

    /// 获取 PHP 错误级别
    pub fn level(self: RuntimeErrorType) ErrorLevel {
        return switch (self) {
            .division_by_zero => .warning,
            .undefined_variable => .notice,
            .type_error, .argument_count_error, .value_error => .fatal,
            .null_reference, .undefined_function => .fatal,
            .array_index_out_of_bounds => .warning,
            .overflow_error, .memory_error, .fatal_error => .fatal,
        };
    }
};

/// PHP 错误级别
pub const ErrorLevel = enum(u32) {
    notice = 8,
    warning = 2,
    fatal = 1,
    deprecated = 8192,

    pub fn toString(self: ErrorLevel) []const u8 {
        return switch (self) {
            .notice => "Notice",
            .warning => "Warning",
            .fatal => "Fatal error",
            .deprecated => "Deprecated",
        };
    }
};

/// 运行时错误
pub const RuntimeError = struct {
    error_type: RuntimeErrorType,
    message: []const u8,
    file: []const u8,
    line: u32,
    trace: ?[]const StackFrame,

    /// 格式化错误信息
    pub fn format(
        self: RuntimeError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}: {s} in {s} on line {d}", .{
            self.error_type.level().toString(),
            self.message,
            self.file,
            self.line,
        });
    }
};

/// 堆栈帧
pub const StackFrame = struct {
    function: []const u8,
    file: []const u8,
    line: u32,
    args: ?[]const []const u8,
};

// ============================================================================
// 运行时错误处理器
// ============================================================================

/// 错误处理器配置
pub const ErrorHandlerConfig = struct {
    display_errors: bool = true,
    log_errors: bool = true,
    error_reporting: u32 = 0xFFFFFFFF,
    max_stack_depth: u32 = 100,
};

/// 运行时错误处理器
pub const RuntimeErrorHandler = struct {
    allocator: Allocator,
    config: ErrorHandlerConfig,
    errors: std.ArrayListUnmanaged(RuntimeError),
    stack: std.ArrayListUnmanaged(StackFrame),

    const Self = @This();

    /// 初始化错误处理器
    pub fn init(allocator: Allocator, config: ErrorHandlerConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .errors = .{},
            .stack = .{},
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
        self.stack.deinit(self.allocator);
    }

    /// 压入堆栈帧
    pub fn pushFrame(self: *Self, frame: StackFrame) !void {
        if (self.stack.items.len < self.config.max_stack_depth) {
            try self.stack.append(self.allocator, frame);
        }
    }

    /// 弹出堆栈帧
    pub fn popFrame(self: *Self) void {
        if (self.stack.items.len > 0) {
            _ = self.stack.pop();
        }
    }

    /// 报告错误
    pub fn report(
        self: *Self,
        error_type: RuntimeErrorType,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        errdefer self.allocator.free(message);

        const frame = if (self.stack.items.len > 0)
            self.stack.items[self.stack.items.len - 1]
        else
            StackFrame{ .function = "<main>", .file = "<unknown>", .line = 0, .args = null };

        try self.errors.append(self.allocator, .{
            .error_type = error_type,
            .message = message,
            .file = frame.file,
            .line = frame.line,
            .trace = null,
        });

        if (self.config.display_errors) {
            self.displayError(self.errors.items[self.errors.items.len - 1]);
        }
    }

    /// 显示错误
    fn displayError(self: *const Self, err: RuntimeError) void {
        _ = self;
        std.debug.print("\n{s}: {s} in {s} on line {d}\n", .{
            err.error_type.level().toString(),
            err.message,
            err.file,
            err.line,
        });
    }

    /// 检查是否有致命错误
    pub fn hasFatalError(self: *const Self) bool {
        for (self.errors.items) |err| {
            if (err.error_type.level() == .fatal) return true;
        }
        return false;
    }

    /// 获取错误数量
    pub fn errorCount(self: *const Self) usize {
        return self.errors.items.len;
    }

    /// 清除所有错误
    pub fn clear(self: *Self) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.clearRetainingCapacity();
    }
};

// ============================================================================
// 运行时检查函数
// ============================================================================

/// 除零检测
pub fn checkDivisionByZero(divisor: i64) !void {
    if (divisor == 0) {
        return error.DivisionByZero;
    }
}

/// 浮点除零检测
pub fn checkFloatDivisionByZero(divisor: f64) !void {
    if (divisor == 0.0) {
        return error.DivisionByZero;
    }
}

/// 数组边界检测
pub fn checkArrayBounds(index: i64, length: usize) !usize {
    if (index < 0) {
        const abs_idx = @as(usize, @intCast(-index));
        if (abs_idx > length) {
            return error.IndexOutOfBounds;
        }
        return length - abs_idx;
    }
    const idx = @as(usize, @intCast(index));
    if (idx >= length) {
        return error.IndexOutOfBounds;
    }
    return idx;
}

/// 空值检测
pub fn checkNotNull(comptime T: type, value: ?*T) !*T {
    return value orelse error.NullReference;
}

/// 整数溢出检测（加法）
pub fn checkedIntAdd(a: i64, b: i64) !i64 {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) {
        return error.IntegerOverflow;
    }
    return result[0];
}

/// 整数溢出检测（减法）
pub fn checkedIntSub(a: i64, b: i64) !i64 {
    const result = @subWithOverflow(a, b);
    if (result[1] != 0) {
        return error.IntegerOverflow;
    }
    return result[0];
}

/// 整数溢出检测（乘法）
pub fn checkedIntMul(a: i64, b: i64) !i64 {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) {
        return error.IntegerOverflow;
    }
    return result[0];
}

/// 类型检查
pub fn checkType(comptime expected: type, value: anytype) !expected {
    const T = @TypeOf(value);
    if (T != expected) {
        return error.TypeError;
    }
    return value;
}

// ============================================================================
// 测试
// ============================================================================

test "RuntimeErrorType name and level" {
    try std.testing.expectEqualStrings(
        "DivisionByZeroError",
        RuntimeErrorType.division_by_zero.name(),
    );
    try std.testing.expectEqual(ErrorLevel.warning, RuntimeErrorType.division_by_zero.level());
    try std.testing.expectEqual(ErrorLevel.fatal, RuntimeErrorType.type_error.level());
}

test "RuntimeErrorHandler init and deinit" {
    const allocator = std.testing.allocator;
    var handler = RuntimeErrorHandler.init(allocator, .{});
    defer handler.deinit();

    try std.testing.expectEqual(@as(usize, 0), handler.errorCount());
}

test "RuntimeErrorHandler report" {
    const allocator = std.testing.allocator;
    var handler = RuntimeErrorHandler.init(allocator, .{ .display_errors = false });
    defer handler.deinit();

    try handler.report(.division_by_zero, "Division by zero", .{});
    try std.testing.expectEqual(@as(usize, 1), handler.errorCount());
}

test "RuntimeErrorHandler stack operations" {
    const allocator = std.testing.allocator;
    var handler = RuntimeErrorHandler.init(allocator, .{});
    defer handler.deinit();

    try handler.pushFrame(.{
        .function = "test_func",
        .file = "test.php",
        .line = 10,
        .args = null,
    });
    try std.testing.expectEqual(@as(usize, 1), handler.stack.items.len);

    handler.popFrame();
    try std.testing.expectEqual(@as(usize, 0), handler.stack.items.len);
}

test "checkDivisionByZero" {
    try checkDivisionByZero(5);
    try std.testing.expectError(error.DivisionByZero, checkDivisionByZero(0));
}

test "checkArrayBounds" {
    try std.testing.expectEqual(@as(usize, 2), try checkArrayBounds(2, 5));
    try std.testing.expectEqual(@as(usize, 4), try checkArrayBounds(-1, 5));
    try std.testing.expectError(error.IndexOutOfBounds, checkArrayBounds(5, 5));
    try std.testing.expectError(error.IndexOutOfBounds, checkArrayBounds(-6, 5));
}

test "checkedIntAdd" {
    try std.testing.expectEqual(@as(i64, 5), try checkedIntAdd(2, 3));
    try std.testing.expectError(error.IntegerOverflow, checkedIntAdd(std.math.maxInt(i64), 1));
}

test "checkedIntSub" {
    try std.testing.expectEqual(@as(i64, -1), try checkedIntSub(2, 3));
    try std.testing.expectError(error.IntegerOverflow, checkedIntSub(std.math.minInt(i64), 1));
}

test "checkedIntMul" {
    try std.testing.expectEqual(@as(i64, 6), try checkedIntMul(2, 3));
    try std.testing.expectError(error.IntegerOverflow, checkedIntMul(std.math.maxInt(i64), 2));
}
