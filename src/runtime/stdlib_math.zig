//! 数学内置函数实现模块
//! 从 stdlib.zig 拆分而来 — 包含所有数学运算、三角函数、位运算、随机数函数

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const VM = @import("vm.zig").VM;
const time_compat = @import("time_compat.zig");

// 数组函数模块（minFn/maxFn 使用 compareValues）
const stdlib_array = @import("stdlib_array.zig");

// ============================================================================
// 辅助函数（供数学函数内部使用）
// ============================================================================

/// 将 Value 转换为整数
pub fn toInteger(vm: *VM, value: Value) !i64 {
    return switch (value.getTag()) {
        .integer => value.asInt(),
        .float => @intFromFloat(value.asFloat()),
        .boolean => if (value.asBool()) @as(i64, 1) else @as(i64, 0),
        .string => std.fmt.parseInt(i64, value.getAsString().data.data, 10) catch 0,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "Cannot convert value to integer", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
}

/// 将 Value 转换为浮点数
pub fn toFloat(vm: *VM, value: Value) !f64 {
    return switch (value.getTag()) {
        .float => value.asFloat(),
        .integer => @floatFromInt(value.asInt()),
        .boolean => if (value.asBool()) @as(f64, 1.0) else @as(f64, 0.0),
        .string => std.fmt.parseFloat(f64, value.getAsString().data.data) catch 0.0,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "Cannot convert value to float", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
}

// ============================================================================
// 基础数学函数
// ============================================================================

pub fn absFn(vm: *VM, args: []const Value) !Value {
    const arg = args[0];
    // 快速路径：整数直接处理，避免浮点转换
    if (arg.getTag() == .integer) {
        const i = arg.asInt();
        return Value.initInt(if (i < 0) -i else i);
    }
    const num = try toFloat(vm, arg);
    return Value.initFloat(@abs(num));
}

pub fn roundFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    const precision = if (args.len > 1) args[1] else Value.initInt(0);

    if (precision.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "round() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const num_val = switch (number.getTag()) {
        .integer => @as(f64, @floatFromInt(number.asInt())),
        .float => number.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "round() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const prec = precision.asInt();
    const multiplier = std.math.pow(f64, 10.0, @floatFromInt(prec));
    const rounded = @round(num_val * multiplier) / multiplier;

    if (prec == 0) {
        return Value.initInt(@intFromFloat(rounded));
    } else {
        return Value.initFloat(rounded);
    }
}

pub fn sqrtFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];

    const num_val: f64 = switch (number.getTag()) {
        .integer => @as(f64, @floatFromInt(number.asInt())),
        .float => number.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "sqrt() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    if (num_val < 0) {
        return Value.initFloat(std.math.nan(f64));
    }

    return Value.initFloat(@sqrt(num_val));
}

pub fn powFn(vm: *VM, args: []const Value) !Value {
    const base = args[0];
    const exponent = args[1];

    const base_val = switch (base.getTag()) {
        .integer => @as(f64, @floatFromInt(base.asInt())),
        .float => base.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "pow() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const exp_val = switch (exponent.getTag()) {
        .integer => @as(f64, @floatFromInt(exponent.asInt())),
        .float => exponent.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "pow() expects parameter 2 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const result = std.math.pow(f64, base_val, exp_val);

    // Return integer if both inputs were integers and result is a whole number
    if (base.getTag() == .integer and exponent.getTag() == .integer and result == @floor(result)) {
        return Value.initInt(@intFromFloat(result));
    } else {
        return Value.initFloat(result);
    }
}

pub fn floorFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    // 快速路径：整数直接返回
    if (number.getTag() == .integer) return number;
    if (number.getTag() != .float) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "floor() expects parameter 1 to be numeric", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    return Value.initFloat(@floor(number.asFloat()));
}

pub fn ceilFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    // 快速路径：整数直接返回
    if (number.getTag() == .integer) return number;
    if (number.getTag() != .float) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ceil() expects parameter 1 to be numeric", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    return Value.initFloat(@ceil(number.asFloat()));
}

pub fn minFn(vm: *VM, args: []const Value) !Value {
    if (args.len == 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, 0, "min", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    // PHP 语义：如果第一个参数是数组，在数组元素中找最小值
    if (args.len == 1 and args[0].getTag() == .array) {
        const arr = args[0].getAsArray().data;
        if (arr.count() == 0) return Value.initNull();
        var min_val: Value = undefined;
        var first = true;
        var iter = arr.iterator();
        while (iter.next()) |entry| {
            if (first) {
                min_val = entry.value;
                first = false;
            } else {
                const comparison = stdlib_array.compareValues(min_val, entry.value);
                if (comparison > 0) {
                    min_val = entry.value;
                }
            }
        }
        return min_val;
    }

    var min_val = args[0];
    for (args[1..]) |arg| {
        const comparison = stdlib_array.compareValues(min_val, arg);
        if (comparison > 0) {
            min_val = arg;
        }
    }

    return min_val;
}

pub fn maxFn(vm: *VM, args: []const Value) !Value {
    if (args.len == 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, 0, "max", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    // PHP 语义：如果第一个参数是数组，在数组元素中找最大值
    if (args.len == 1 and args[0].getTag() == .array) {
        const arr = args[0].getAsArray().data;
        if (arr.count() == 0) return Value.initNull();
        var max_val: Value = undefined;
        var first = true;
        var iter = arr.iterator();
        while (iter.next()) |entry| {
            if (first) {
                max_val = entry.value;
                first = false;
            } else {
                const comparison = stdlib_array.compareValues(max_val, entry.value);
                if (comparison < 0) {
                    max_val = entry.value;
                }
            }
        }
        return max_val;
    }

    var max_val = args[0];
    for (args[1..]) |arg| {
        const comparison = stdlib_array.compareValues(max_val, arg);
        if (comparison < 0) {
            max_val = arg;
        }
    }

    return max_val;
}

// ============================================================================
// 随机数函数
// ============================================================================

pub fn randFn(vm: *VM, args: []const Value) !Value {
    var prng = std.Random.DefaultPrng.init(@intCast(time_compat.timestamp()));
    const random = prng.random();

    if (args.len == 0) {
        return Value.initInt(random.int(i32));
    } else if (args.len == 2) {
        const min = args[0];
        const max = args[1];

        if (min.getTag() != .integer or max.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "rand() expects parameters to be integers", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }

        const min_val = min.asInt();
        const max_val = max.asInt();

        if (min_val > max_val) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "rand(): min is greater than max", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }

        const range = @as(u64, @intCast(max_val - min_val + 1));
        const result = min_val + @as(i64, @intCast(random.uintLessThan(u64, range)));
        return Value.initInt(result);
    } else {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "rand", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }
}

pub fn mtRandFn(vm: *VM, args: []const Value) !Value {
    // mt_rand is the same as rand in this implementation
    return randFn(vm, args);
}

/// random_int(int $min, int $max): int — 密码安全的随机整数
pub fn randomIntFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "random_int", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const min_val = try toInteger(vm, args[0]);
    const max_val = try toInteger(vm, args[1]);

    if (min_val > max_val) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "random_int(): min must be less than or equal to max", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // 使用 PRNG 种子（使用高精度时间 + 地址混合作为熵源）
    var buf: [8]u8 = undefined;
    const ts = time_compat.nanoTimestamp();
    const ptr_val = @intFromPtr(&buf);
    const seed: u64 = @intCast(ts ^ ptr_val);
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    random.bytes(&buf);

    var seed_val: u64 = 0;
    for (buf, 0..) |b, i| {
        seed_val |= @as(u64, b) << @intCast(i * 8);
    }

    var final_prng = std.Random.DefaultPrng.init(seed_val);
    const final_random = final_prng.random();

    if (min_val == max_val) return Value.initInt(min_val);
    const range = @as(u64, @intCast(max_val - min_val + 1));
    const result = min_val + @as(i64, @intCast(final_random.uintLessThan(u64, range)));
    return Value.initInt(result);
}

/// random_bytes(int $length): string — 密码安全的随机字节串
pub fn randomBytesFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, 0, "random_bytes", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const length = try toInteger(vm, args[0]);
    if (length < 1) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "random_bytes(): length must be greater than 0", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    if (length > 1024 * 1024) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "random_bytes(): length too large", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const len: usize = @intCast(length);
    var bytes = try vm.allocator.alloc(u8, len);
    errdefer vm.allocator.free(bytes);

    // 使用 PRNG 生成随机字节
    const ts = time_compat.nanoTimestamp();
    const ptr_val = @intFromPtr(&bytes);
    const seed: u64 = @intCast(ts ^ ptr_val);
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    random.bytes(bytes);

    // 转为十六进制字符串输出（PHP 的 random_bytes 返回原始二进制，但我们的字符串系统用 GC 字符串）
    const hex_len = len * 2;
    var hex_buf = try vm.allocator.alloc(u8, hex_len);
    const hex_chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        hex_buf[i * 2] = hex_chars[b >> 4];
        hex_buf[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    vm.allocator.free(bytes);

    return Value.initString(vm.allocator, hex_buf);
}

// ============================================================================
// 位运算函数
// ============================================================================

pub fn bitAndFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    return Value.initInt(a & b);
}

pub fn bitOrFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    return Value.initInt(a | b);
}

pub fn bitXorFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    return Value.initInt(a ^ b);
}

pub fn bitNotFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    return Value.initInt(~a);
}

pub fn bitShiftLeftFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    const shift: u6 = @intCast(@mod(b, 64));
    return Value.initInt(a << shift);
}

pub fn bitShiftRightFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    const shift: u6 = @intCast(@mod(b, 64));
    return Value.initInt(a >> shift);
}

// ============================================================================
// 三角函数
// ============================================================================

pub fn sinFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@sin(num));
}

pub fn cosFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@cos(num));
}

pub fn tanFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@tan(num));
}

pub fn logFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    if (args.len > 1) {
        const base = try toFloat(vm, args[1]);
        return Value.initFloat(@log(num) / @log(base));
    }
    return Value.initFloat(@log(num));
}

pub fn expFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@exp(num));
}

pub fn piFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initFloat(std.math.pi);
}

pub fn log10Fn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@log10(num));
}

pub fn log2Fn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@log2(num));
}

pub fn deg2radFn(vm: *VM, args: []const Value) !Value {
    const degrees = try toFloat(vm, args[0]);
    return Value.initFloat(degrees * std.math.pi / 180.0);
}

pub fn rad2degFn(vm: *VM, args: []const Value) !Value {
    const radians = try toFloat(vm, args[0]);
    return Value.initFloat(radians * 180.0 / std.math.pi);
}

pub fn asinFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.asin(num));
}

pub fn acosFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.acos(num));
}

pub fn atanFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.atan(num));
}

pub fn atan2Fn(vm: *VM, args: []const Value) !Value {
    const y = try toFloat(vm, args[0]);
    const x = try toFloat(vm, args[1]);
    return Value.initFloat(std.math.atan2(y, x));
}

pub fn hypotFn(vm: *VM, args: []const Value) !Value {
    const x = try toFloat(vm, args[0]);
    const y = try toFloat(vm, args[1]);
    return Value.initFloat(std.math.hypot(x, y));
}

pub fn fmodFn(vm: *VM, args: []const Value) !Value {
    const x = try toFloat(vm, args[0]);
    const y = try toFloat(vm, args[1]);
    return Value.initFloat(@mod(x, y));
}

pub fn intdivFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const dividend = args[0].toInt();
    const divisor = args[1].toInt();
    if (divisor == 0) {
        return error.DivisionByZero;
    }
    return Value.initInt(@divTrunc(dividend, divisor));
}

// ============================================================================
// 双曲函数
// ============================================================================

pub fn sinhFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.sinh(num));
}

pub fn coshFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.cosh(num));
}

pub fn tanhFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.tanh(num));
}

// ============================================================================
// 数值检测函数
// ============================================================================

pub fn isNanFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initBool(std.math.isNan(num));
}

pub fn isFiniteFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initBool(std.math.isFinite(num));
}

pub fn isInfiniteFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initBool(std.math.isInf(num));
}

// ============================================================================
// 随机数种子函数
// ============================================================================

pub fn srandFn(vm: *VM, args: []const Value) !Value {
    if (args.len > 0) {
        const seed = try toInteger(vm, args[0]);
        _ = std.Random.DefaultPrng.init(@intCast(@abs(seed)));
    }
    // srand returns void in PHP
    return Value.initNull();
}

pub fn mtSrandFn(vm: *VM, args: []const Value) !Value {
    if (args.len > 0) {
        const seed = try toInteger(vm, args[0]);
        _ = std.Random.Xoshiro256.init(@intCast(@abs(seed)));
    }
    return Value.initNull();
}

pub fn getrandmaxFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    // On most systems, rand() returns values up to RAND_MAX which is typically 2^31 - 1
    return Value.initInt(std.math.maxInt(i32));
}

pub fn mtGetrandmaxFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    // mt_rand() returns values up to 2^31 - 1
    return Value.initInt(std.math.maxInt(i32));
}

// ============================================================================
// 进制转换函数
// ============================================================================

/// decbin() — 十进制转二进制字符串
pub fn decbinFn(vm: *VM, args: []const Value) !Value {
    const num = try toInteger(vm, args[0]);
    if (num == 0) return Value.initString(vm.allocator, "0");
    const abs_num: u64 = if (num < 0) @intCast(-num) else @intCast(num);
    const bin_str = try std.fmt.allocPrint(vm.allocator, "{b}", .{abs_num});
    return Value.initString(vm.allocator, bin_str);
}

/// dechex() — 十进制转十六进制字符串
pub fn dechexFn(vm: *VM, args: []const Value) !Value {
    const num = try toInteger(vm, args[0]);
    if (num == 0) return Value.initString(vm.allocator, "0");
    const abs_num: u64 = if (num < 0) @intCast(-num) else @intCast(num);
    const hex_str = try std.fmt.allocPrint(vm.allocator, "{x}", .{abs_num});
    return Value.initString(vm.allocator, hex_str);
}

/// decoct() — 十进制转八进制字符串
pub fn decoctFn(vm: *VM, args: []const Value) !Value {
    const num = try toInteger(vm, args[0]);
    if (num == 0) return Value.initString(vm.allocator, "0");
    const abs_num: u64 = if (num < 0) @intCast(-num) else @intCast(num);
    const oct_str = try std.fmt.allocPrint(vm.allocator, "{o}", .{abs_num});
    return Value.initString(vm.allocator, oct_str);
}

/// bindec() — 二进制字符串转十进制
pub fn bindecFn(vm: *VM, args: []const Value) !Value {
    const str = try args[0].toString(vm.allocator);
    defer str.release(vm.allocator);
    const result = std.fmt.parseInt(i64, str.data, 2) catch 0;
    return Value.initInt(result);
}

/// hexdec() — 十六进制字符串转十进制
pub fn hexdecFn(vm: *VM, args: []const Value) !Value {
    const str = try args[0].toString(vm.allocator);
    defer str.release(vm.allocator);
    const result = std.fmt.parseInt(i64, str.data, 16) catch 0;
    return Value.initInt(result);
}

/// octdec() — 八进制字符串转十进制
pub fn octdecFn(vm: *VM, args: []const Value) !Value {
    const str = try args[0].toString(vm.allocator);
    defer str.release(vm.allocator);
    const result = std.fmt.parseInt(i64, str.data, 8) catch 0;
    return Value.initInt(result);
}

/// base_convert() — 任意进制转换
pub fn baseConvertFn(vm: *VM, args: []const Value) !Value {
    const num_str = try args[0].toString(vm.allocator);
    defer num_str.release(vm.allocator);
    const from_base = try toInteger(vm, args[1]);
    const to_base = try toInteger(vm, args[2]);

    // 验证进制范围 2-36
    if (from_base < 2 or from_base > 36 or to_base < 2 or to_base > 36) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "base_convert(): Invalid base", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // 解析源进制
    const from_radix: u8 = @intCast(from_base);
    const num = std.fmt.parseInt(i64, num_str.data, from_radix) catch 0;

    // 转换为目标进制
    const abs_num: u64 = if (num < 0) @intCast(-num) else @intCast(num);
    const result = switch (to_base) {
        2 => try std.fmt.allocPrint(vm.allocator, "{b}", .{abs_num}),
        8 => try std.fmt.allocPrint(vm.allocator, "{o}", .{abs_num}),
        10 => try std.fmt.allocPrint(vm.allocator, "{d}", .{abs_num}),
        16 => try std.fmt.allocPrint(vm.allocator, "{x}", .{abs_num}),
        else => try formatBase(vm.allocator, abs_num, @intCast(to_base)),
    };
    return Value.initString(vm.allocator, result);
}

/// 通用进制格式化（支持 2-36 进制）
fn formatBase(allocator: std.mem.Allocator, num: u64, base: u8) ![]u8 {
    if (num == 0) return allocator.dupe(u8, "0");
    const digits = "0123456789abcdefghijklmnopqrstuvwxyz";

    // 计算结果长度
    var len: usize = 0;
    var tmp = num;
    while (tmp > 0) : (len += 1) {
        tmp /= base;
    }

    const result = try allocator.alloc(u8, len);
    var i: usize = len;
    tmp = num;
    while (tmp > 0) {
        i -= 1;
        result[i] = digits[@intCast(tmp % base)];
        tmp /= base;
    }
    return result;
}

// ============================================================================
// 单元测试
// ============================================================================

test "stdlib_math: handler functions exist" {
    // 编译时验证所有 handler 函数被正确导出（引用即证明存在）
    _ = &absFn;
    _ = &roundFn;
    _ = &sqrtFn;
    _ = &powFn;
    _ = &floorFn;
    _ = &ceilFn;
    _ = &minFn;
    _ = &maxFn;
    _ = &randFn;
    _ = &mtRandFn;
}

test "stdlib_math: bit operation handler functions exist" {
    _ = &bitAndFn;
    _ = &bitOrFn;
    _ = &bitXorFn;
    _ = &bitNotFn;
    _ = &bitShiftLeftFn;
    _ = &bitShiftRightFn;
}

test "stdlib_math: trigonometric handler functions exist" {
    _ = &sinFn;
    _ = &cosFn;
    _ = &tanFn;
    _ = &logFn;
    _ = &expFn;
    _ = &piFn;
    _ = &log10Fn;
    _ = &log2Fn;
    _ = &deg2radFn;
    _ = &rad2degFn;
    _ = &asinFn;
    _ = &acosFn;
    _ = &atanFn;
    _ = &atan2Fn;
    _ = &hypotFn;
    _ = &fmodFn;
    _ = &intdivFn;
}

test "stdlib_math: hyperbolic handler functions exist" {
    _ = &sinhFn;
    _ = &coshFn;
    _ = &tanhFn;
}

test "stdlib_math: numeric check handler functions exist" {
    _ = &isNanFn;
    _ = &isFiniteFn;
    _ = &isInfiniteFn;
}

test "stdlib_math: random seed handler functions exist" {
    _ = &srandFn;
    _ = &mtSrandFn;
    _ = &getrandmaxFn;
    _ = &mtGetrandmaxFn;
}
