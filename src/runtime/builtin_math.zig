//! ============================================================================
//! 数学内置函数 (Math Builtin Functions)
//! ============================================================================
//!
//! 功能：实现PHP数学相关的内置函数
//!
//! 支持的函数：
//! - abs(): 绝对值
//! - ceil(): 向上取整
//! - floor(): 向下取整
//! - round(): 四舍五入
//! - min(): 最小值
//! - max(): 最大值
//!
//! 需求：3.1, 3.2, 3.3, 3.4, 3.5, 3.6
//! ============================================================================

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const builtin_registry = @import("builtin_registry.zig");
const BuiltinFunction = builtin_registry.BuiltinFunction;
const BuiltinError = builtin_registry.BuiltinError;
const Category = builtin_registry.Category;

// 核心数学函数模块（DRY 原则）
const core_math = @import("core/math_functions.zig");

/// 数学内置函数实现
/// Mathematical builtin functions implementation
/// Provides high-performance mathematical operations with proper error handling
pub const MathBuiltins = struct {
    /// PHP abs() - Returns absolute value of a number（调用 core_math）
    /// Requirements: 3.1
    pub fn abs(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        if (args.len != 1) return BuiltinError.ArgumentCountMismatch;
        const arg = args[0];
        return switch (arg.getTag()) {
            .integer => Value.initInt(core_math.abs_int(arg.asInt())),
            .float => Value.initFloat(core_math.abs_float(arg.asFloat())),
            else => BuiltinError.InvalidArgumentType,
        };
    }

    /// PHP ceil() - Returns ceiling value（调用 core_math）
    /// Requirements: 3.2
    pub fn ceil(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        if (args.len != 1) return BuiltinError.ArgumentCountMismatch;
        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };
        return Value.initFloat(core_math.ceil(float_val));
    }

    /// PHP floor() - Returns floor value（调用 core_math）
    /// Requirements: 3.3
    pub fn floor(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        if (args.len != 1) return BuiltinError.ArgumentCountMismatch;
        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };
        return Value.initFloat(core_math.floor(float_val));
    }

    /// PHP round() - Returns rounded value
    /// Requirements: 3.4, 3.5
    pub fn round(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len < 1 or args.len > 2) {
            return BuiltinError.ArgumentCountMismatch;
        }

        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        // Get precision (default is 0)
        const precision: i32 = if (args.len >= 2) blk: {
            switch (args[1].getTag()) {
                .integer => break :blk @intCast(args[1].asInt()),
                .float => break :blk @intFromFloat(args[1].asFloat()),
                else => return BuiltinError.InvalidArgumentType,
            }
        } else 0;

        if (precision == 0) {
            return Value.initFloat(@round(float_val));
        } else {
            const multiplier = std.math.pow(f64, 10.0, @floatFromInt(precision));
            const rounded = @round(float_val * multiplier) / multiplier;
            return Value.initFloat(rounded);
        }
    }

    /// PHP sqrt() - Returns square root
    /// Requirements: 3.6
    pub fn sqrt(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }

        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        if (float_val < 0.0) {
            return BuiltinError.MathDomainError;
        }

        return Value.initFloat(@sqrt(float_val));
    }

    /// PHP pow() - Returns base raised to exponent
    /// Requirements: 3.7
    pub fn pow(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len != 2) {
            return BuiltinError.ArgumentCountMismatch;
        }

        const base_arg = args[0];
        const exp_arg = args[1];

        const base = switch (base_arg.getTag()) {
            .integer => @as(f64, @floatFromInt(base_arg.asInt())),
            .float => base_arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        const exponent = switch (exp_arg.getTag()) {
            .integer => @as(f64, @floatFromInt(exp_arg.asInt())),
            .float => exp_arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        // Check for domain errors
        if (base == 0.0 and exponent < 0.0) {
            return BuiltinError.MathDomainError;
        }
        if (base < 0.0 and @floor(exponent) != exponent) {
            return BuiltinError.MathDomainError;
        }

        const result = std.math.pow(f64, base, exponent);

        // Check for overflow/underflow
        if (std.math.isInf(result) or std.math.isNan(result)) {
            return BuiltinError.MathDomainError;
        }

        return Value.initFloat(result);
    }

    /// PHP sin() - Returns sine of angle in radians
    /// Requirements: 3.8
    pub fn sin(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }

        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        return Value.initFloat(@sin(float_val));
    }

    /// PHP cos() - Returns cosine of angle in radians
    /// Requirements: 3.8
    pub fn cos(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }

        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        return Value.initFloat(@cos(float_val));
    }

    /// PHP tan() - Returns tangent of angle in radians
    /// Requirements: 3.8
    pub fn tan(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }

        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        const result = @tan(float_val);

        // Check for overflow (tan approaches infinity at π/2 + nπ)
        if (std.math.isInf(result)) {
            return BuiltinError.MathDomainError;
        }

        return Value.initFloat(result);
    }

    /// PHP log() - Returns natural logarithm
    /// Requirements: 3.9
    pub fn log(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }

        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        if (float_val <= 0.0) {
            return BuiltinError.MathDomainError;
        }

        return Value.initFloat(@log(float_val));
    }

    /// PHP log10() - Returns base-10 logarithm
    /// Requirements: 3.10
    pub fn log10(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }

        const arg = args[0];
        const float_val = switch (arg.getTag()) {
            .integer => @as(f64, @floatFromInt(arg.asInt())),
            .float => arg.asFloat(),
            else => return BuiltinError.InvalidArgumentType,
        };

        if (float_val <= 0.0) {
            return BuiltinError.MathDomainError;
        }

        return Value.initFloat(@log10(float_val));
    }

    /// Get all basic math builtin functions
    pub fn getBasicFunctions() [10]BuiltinFunction {
        return [_]BuiltinFunction{
            BuiltinFunction.init("abs", .math, abs, 1, 1, "Returns absolute value of a number"),
            BuiltinFunction.init("ceil", .math, ceil, 1, 1, "Returns ceiling value (round up)"),
            BuiltinFunction.init("floor", .math, floor, 1, 1, "Returns floor value (round down)"),
            BuiltinFunction.init("round", .math, round, 1, 2, "Returns rounded value with optional precision"),
            BuiltinFunction.init("sqrt", .math, sqrt, 1, 1, "Returns square root"),
            BuiltinFunction.init("pow", .math, pow, 2, 2, "Returns base raised to exponent"),
            BuiltinFunction.init("sin", .math, sin, 1, 1, "Returns sine of angle in radians"),
            BuiltinFunction.init("cos", .math, cos, 1, 1, "Returns cosine of angle in radians"),
            BuiltinFunction.init("tan", .math, tan, 1, 1, "Returns tangent of angle in radians"),
            BuiltinFunction.init("log", .math, log, 1, 1, "Returns natural logarithm"),
        };
    }

    /// PHP min() - Returns minimum value from variadic arguments
    /// Requirements: 3.11
    pub fn min(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len == 0) {
            return BuiltinError.ArgumentCountMismatch;
        }

        // Handle single array argument
        if (args.len == 1 and args[0].getTag() == .array) {
            const array_box = args[0].getAsArray();
            const array = array_box.data;

            if (array.count() == 0) {
                return BuiltinError.ArgumentCountMismatch;
            }

            var min_val = array.getByIndex(0) orelse return BuiltinError.InvalidArgumentType;

            for (1..array.count()) |i| {
                const current = array.getByIndex(i) orelse continue;
                if (compareValues(current, min_val) < 0) {
                    min_val = current;
                }
            }

            return min_val;
        }

        // Handle multiple arguments
        var min_val = args[0];

        for (args[1..]) |arg| {
            if (compareValues(arg, min_val) < 0) {
                min_val = arg;
            }
        }

        return min_val;
    }

    /// PHP max() - Returns maximum value from variadic arguments
    /// Requirements: 3.12
    pub fn max(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;

        if (args.len == 0) {
            return BuiltinError.ArgumentCountMismatch;
        }

        // Handle single array argument
        if (args.len == 1 and args[0].getTag() == .array) {
            const array_box = args[0].getAsArray();
            const array = array_box.data;

            if (array.count() == 0) {
                return BuiltinError.ArgumentCountMismatch;
            }

            var max_val = array.getByIndex(0) orelse return BuiltinError.InvalidArgumentType;

            for (1..array.count()) |i| {
                const current = array.getByIndex(i) orelse continue;
                if (compareValues(current, max_val) > 0) {
                    max_val = current;
                }
            }

            return max_val;
        }

        // Handle multiple arguments
        var max_val = args[0];

        for (args[1..]) |arg| {
            if (compareValues(arg, max_val) > 0) {
                max_val = arg;
            }
        }

        return max_val;
    }

    /// Compare two values for min/max operations
    /// Returns: -1 if a < b, 0 if a == b, 1 if a > b
    fn compareValues(a: Value, b: Value) i8 {
        const a_tag = a.getTag();
        const b_tag = b.getTag();

        // Handle same types
        if (a_tag == b_tag) {
            return switch (a_tag) {
                .integer => {
                    const a_val = a.asInt();
                    const b_val = b.asInt();
                    if (a_val < b_val) return -1;
                    if (a_val > b_val) return 1;
                    return 0;
                },
                .float => {
                    const a_val = a.asFloat();
                    const b_val = b.asFloat();
                    if (a_val < b_val) return -1;
                    if (a_val > b_val) return 1;
                    return 0;
                },
                .string => {
                    const a_str = a.getAsString().data.data;
                    const b_str = b.getAsString().data.data;
                    const cmp = std.mem.order(u8, a_str, b_str);
                    return switch (cmp) {
                        .lt => -1,
                        .gt => 1,
                        .eq => 0,
                    };
                },
                else => 0, // Consider equal for unsupported types
            };
        }

        // Handle mixed numeric types
        if ((a_tag == .integer or a_tag == .float) and (b_tag == .integer or b_tag == .float)) {
            const a_float = if (a_tag == .integer) @as(f64, @floatFromInt(a.asInt())) else a.asFloat();
            const b_float = if (b_tag == .integer) @as(f64, @floatFromInt(b.asInt())) else b.asFloat();

            if (a_float < b_float) return -1;
            if (a_float > b_float) return 1;
            return 0;
        }

        // For different non-numeric types, consider them equal
        return 0;
    }

    /// Get all math builtin functions
    pub fn getAllFunctions() [13]BuiltinFunction {
        const basic = [_]BuiltinFunction{
            BuiltinFunction.init("abs", .math, abs, 1, 1, "Returns absolute value of a number"),
            BuiltinFunction.init("ceil", .math, ceil, 1, 1, "Returns ceiling value (round up)"),
            BuiltinFunction.init("floor", .math, floor, 1, 1, "Returns floor value (round down)"),
            BuiltinFunction.init("round", .math, round, 1, 2, "Returns rounded value with optional precision"),
            BuiltinFunction.init("sqrt", .math, sqrt, 1, 1, "Returns square root"),
            BuiltinFunction.init("pow", .math, pow, 2, 2, "Returns base raised to exponent"),
            BuiltinFunction.init("sin", .math, sin, 1, 1, "Returns sine of angle in radians"),
            BuiltinFunction.init("cos", .math, cos, 1, 1, "Returns cosine of angle in radians"),
            BuiltinFunction.init("tan", .math, tan, 1, 1, "Returns tangent of angle in radians"),
            BuiltinFunction.init("log", .math, log, 1, 1, "Returns natural logarithm"),
        };
        const log_funcs = [_]BuiltinFunction{
            BuiltinFunction.init("log10", .math, log10, 1, 1, "Returns base-10 logarithm"),
        };
        const variadic = [_]BuiltinFunction{
            BuiltinFunction.init("min", .math, min, 1, 255, "Returns minimum value from arguments"),
            BuiltinFunction.init("max", .math, max, 1, 255, "Returns maximum value from arguments"),
        };

        var all_funcs: [13]BuiltinFunction = undefined;
        @memcpy(all_funcs[0..10], &basic);
        @memcpy(all_funcs[10..11], &log_funcs);
        @memcpy(all_funcs[11..13], &variadic);

        return all_funcs;
    }
};

test "MathBuiltins.abs" {
    const testing = std.testing;

    // Mock VM for testing
    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test positive integer
    const pos_int = Value.initInt(42);
    const result1 = try MathBuiltins.abs(vm_ptr, &[_]Value{pos_int});
    try testing.expect(result1.getTag() == .integer);
    try testing.expect(result1.asInt() == 42);

    // Test negative integer
    const neg_int = Value.initInt(-42);
    const result2 = try MathBuiltins.abs(vm_ptr, &[_]Value{neg_int});
    try testing.expect(result2.getTag() == .integer);
    try testing.expect(result2.asInt() == 42);

    // Test positive float
    const pos_float = Value.initFloat(3.14);
    const result3 = try MathBuiltins.abs(vm_ptr, &[_]Value{pos_float});
    try testing.expect(result3.getTag() == .float);
    try testing.expect(result3.asFloat() == 3.14);

    // Test negative float
    const neg_float = Value.initFloat(-3.14);
    const result4 = try MathBuiltins.abs(vm_ptr, &[_]Value{neg_float});
    try testing.expect(result4.getTag() == .float);
    try testing.expect(result4.asFloat() == 3.14);
}

test "MathBuiltins.ceil" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test positive float
    const pos_float = Value.initFloat(3.14);
    const result1 = try MathBuiltins.ceil(vm_ptr, &[_]Value{pos_float});
    try testing.expect(result1.getTag() == .float);
    try testing.expect(result1.asFloat() == 4.0);

    // Test negative float
    const neg_float = Value.initFloat(-3.14);
    const result2 = try MathBuiltins.ceil(vm_ptr, &[_]Value{neg_float});
    try testing.expect(result2.getTag() == .float);
    try testing.expect(result2.asFloat() == -3.0);

    // Test integer
    const int_val = Value.initInt(5);
    const result3 = try MathBuiltins.ceil(vm_ptr, &[_]Value{int_val});
    try testing.expect(result3.getTag() == .float);
    try testing.expect(result3.asFloat() == 5.0);
}

test "MathBuiltins.floor" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test positive float
    const pos_float = Value.initFloat(3.14);
    const result1 = try MathBuiltins.floor(vm_ptr, &[_]Value{pos_float});
    try testing.expect(result1.getTag() == .float);
    try testing.expect(result1.asFloat() == 3.0);

    // Test negative float
    const neg_float = Value.initFloat(-3.14);
    const result2 = try MathBuiltins.floor(vm_ptr, &[_]Value{neg_float});
    try testing.expect(result2.getTag() == .float);
    try testing.expect(result2.asFloat() == -4.0);
}

test "MathBuiltins.round" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test basic rounding
    const float_val = Value.initFloat(3.14159);
    const result1 = try MathBuiltins.round(vm_ptr, &[_]Value{float_val});
    try testing.expect(result1.getTag() == .float);
    try testing.expect(result1.asFloat() == 3.0);

    // Test rounding with precision
    const precision = Value.initInt(2);
    const result2 = try MathBuiltins.round(vm_ptr, &[_]Value{ float_val, precision });
    try testing.expect(result2.getTag() == .float);
    try testing.expect(@abs(result2.asFloat() - 3.14) < 0.001);
}

test "MathBuiltins.sqrt" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test positive number
    const pos_val = Value.initFloat(16.0);
    const result1 = try MathBuiltins.sqrt(vm_ptr, &[_]Value{pos_val});
    try testing.expect(result1.getTag() == .float);
    try testing.expect(result1.asFloat() == 4.0);

    // Test zero
    const zero_val = Value.initFloat(0.0);
    const result2 = try MathBuiltins.sqrt(vm_ptr, &[_]Value{zero_val});
    try testing.expect(result2.getTag() == .float);
    try testing.expect(result2.asFloat() == 0.0);

    // Test negative number (should error)
    const neg_val = Value.initFloat(-1.0);
    const result3 = MathBuiltins.sqrt(vm_ptr, &[_]Value{neg_val});
    try testing.expectError(BuiltinError.MathDomainError, result3);
}

test "MathBuiltins.pow" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test basic power
    const base = Value.initFloat(2.0);
    const exp = Value.initFloat(3.0);
    const result1 = try MathBuiltins.pow(vm_ptr, &[_]Value{ base, exp });
    try testing.expect(result1.getTag() == .float);
    try testing.expect(result1.asFloat() == 8.0);

    // Test power of zero
    const zero_base = Value.initFloat(0.0);
    const pos_exp = Value.initFloat(2.0);
    const result2 = try MathBuiltins.pow(vm_ptr, &[_]Value{ zero_base, pos_exp });
    try testing.expect(result2.getTag() == .float);
    try testing.expect(result2.asFloat() == 0.0);
}

test "MathBuiltins.trigonometric" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test sin(0)
    const zero = Value.initFloat(0.0);
    const sin_result = try MathBuiltins.sin(vm_ptr, &[_]Value{zero});
    try testing.expect(sin_result.getTag() == .float);
    try testing.expect(@abs(sin_result.asFloat()) < 0.0001);

    // Test cos(0)
    const cos_result = try MathBuiltins.cos(vm_ptr, &[_]Value{zero});
    try testing.expect(cos_result.getTag() == .float);
    try testing.expect(@abs(cos_result.asFloat() - 1.0) < 0.0001);

    // Test tan(0)
    const tan_result = try MathBuiltins.tan(vm_ptr, &[_]Value{zero});
    try testing.expect(tan_result.getTag() == .float);
    try testing.expect(@abs(tan_result.asFloat()) < 0.0001);
}

test "MathBuiltins.logarithmic" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test log(e)
    const e_val = Value.initFloat(std.math.e);
    const log_result = try MathBuiltins.log(vm_ptr, &[_]Value{e_val});
    try testing.expect(log_result.getTag() == .float);
    try testing.expect(@abs(log_result.asFloat() - 1.0) < 0.0001);

    // Test log10(10)
    const ten_val = Value.initFloat(10.0);
    const log10_result = try MathBuiltins.log10(vm_ptr, &[_]Value{ten_val});
    try testing.expect(log10_result.getTag() == .float);
    try testing.expect(@abs(log10_result.asFloat() - 1.0) < 0.0001);

    // Test log of negative number (should error)
    const neg_val = Value.initFloat(-1.0);
    const log_error = MathBuiltins.log(vm_ptr, &[_]Value{neg_val});
    try testing.expectError(BuiltinError.MathDomainError, log_error);
}

test "MathBuiltins.min" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test min with integers
    const val1 = Value.initInt(5);
    const val2 = Value.initInt(3);
    const val3 = Value.initInt(8);
    const result1 = try MathBuiltins.min(vm_ptr, &[_]Value{ val1, val2, val3 });
    try testing.expect(result1.getTag() == .integer);
    try testing.expect(result1.asInt() == 3);

    // Test min with mixed types
    const int_val = Value.initInt(5);
    const float_val = Value.initFloat(3.14);
    const result2 = try MathBuiltins.min(vm_ptr, &[_]Value{ int_val, float_val });
    try testing.expect(result2.getTag() == .float);
    try testing.expect(@abs(result2.asFloat() - 3.14) < 0.001);

    // Test min with single value
    const single_val = Value.initInt(42);
    const result3 = try MathBuiltins.min(vm_ptr, &[_]Value{single_val});
    try testing.expect(result3.getTag() == .integer);
    try testing.expect(result3.asInt() == 42);
}

test "MathBuiltins.max" {
    const testing = std.testing;

    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));

    // Test max with integers
    const val1 = Value.initInt(5);
    const val2 = Value.initInt(3);
    const val3 = Value.initInt(8);
    const result1 = try MathBuiltins.max(vm_ptr, &[_]Value{ val1, val2, val3 });
    try testing.expect(result1.getTag() == .integer);
    try testing.expect(result1.asInt() == 8);

    // Test max with mixed types
    const int_val = Value.initInt(5);
    const float_val = Value.initFloat(7.5);
    const result2 = try MathBuiltins.max(vm_ptr, &[_]Value{ int_val, float_val });
    try testing.expect(result2.getTag() == .float);
    try testing.expect(@abs(result2.asFloat() - 7.5) < 0.001);

    // Test max with single value
    const single_val = Value.initInt(42);
    const result3 = try MathBuiltins.max(vm_ptr, &[_]Value{single_val});
    try testing.expect(result3.getTag() == .integer);
    try testing.expect(result3.asInt() == 42);
}

test "MathBuiltins.compareValues" {
    const testing = std.testing;

    // Test integer comparison
    const int1 = Value.initInt(5);
    const int2 = Value.initInt(3);
    try testing.expect(MathBuiltins.compareValues(int1, int2) == 1);
    try testing.expect(MathBuiltins.compareValues(int2, int1) == -1);
    try testing.expect(MathBuiltins.compareValues(int1, int1) == 0);

    // Test float comparison
    const float1 = Value.initFloat(5.5);
    const float2 = Value.initFloat(3.3);
    try testing.expect(MathBuiltins.compareValues(float1, float2) == 1);
    try testing.expect(MathBuiltins.compareValues(float2, float1) == -1);

    // Test mixed numeric comparison
    const int_val = Value.initInt(5);
    const float_val = Value.initFloat(5.0);
    try testing.expect(MathBuiltins.compareValues(int_val, float_val) == 0);
}
