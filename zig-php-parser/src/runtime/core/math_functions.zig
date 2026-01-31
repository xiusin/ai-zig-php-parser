//! 数学核心函数实现
//!
//! 提供与执行模式无关的数学运算核心逻辑。
//! 所有函数都是纯函数，不依赖全局状态。
//!
//! @ownership NON-OWNING
//! @thread-safety ISOLATED

const std = @import("std");
const math = std.math;
const common = @import("common.zig");
const CoreError = common.CoreError;
const NumberResult = common.NumberResult;

/// abs - 绝对值（通用版本）
/// @param value 输入值（整数或浮点数）
/// @return 绝对值
pub fn abs(value: NumberResult) NumberResult {
    return switch (value) {
        .int => |i| .{ .int = if (i < 0) -i else i },
        .float => |f| .{ .float = @abs(f) },
    };
}

/// abs_int - 整数绝对值（快速路径）
pub inline fn abs_int(value: i64) i64 {
    return if (value < 0) -value else value;
}

/// abs_float - 浮点数绝对值（快速路径）
pub inline fn abs_float(value: f64) f64 {
    return @abs(value);
}

/// round - 四舍五入
/// @param value 浮点数
/// @param precision 精度（小数位数）
/// @return 四舍五入后的值
pub fn round(value: f64, precision: i32) f64 {
    if (precision == 0) {
        return @round(value);
    }
    const multiplier = math.pow(f64, 10.0, @floatFromInt(precision));
    return @round(value * multiplier) / multiplier;
}

/// floor - 向下取整
/// @param value 浮点数
/// @return 向下取整后的值
pub fn floor(value: f64) f64 {
    return @floor(value);
}

/// ceil - 向上取整
/// @param value 浮点数
/// @return 向上取整后的值
pub fn ceil(value: f64) f64 {
    return @ceil(value);
}

/// sqrt - 平方根
/// @param value 非负数
/// @return 平方根，负数返回 NaN
pub fn sqrt(value: f64) f64 {
    if (value < 0) return math.nan(f64);
    return @sqrt(value);
}

/// pow - 幂运算
/// @param base 底数
/// @param exponent 指数
/// @return 幂值
pub fn pow(base: f64, exponent: f64) f64 {
    return math.pow(f64, base, exponent);
}

/// min - 最小值
/// @param a 第一个值
/// @param b 第二个值
/// @return 较小的值
pub fn min(a: f64, b: f64) f64 {
    return @min(a, b);
}

/// max - 最大值
/// @param a 第一个值
/// @param b 第二个值
/// @return 较大的值
pub fn max(a: f64, b: f64) f64 {
    return @max(a, b);
}

/// sin - 正弦
/// @param value 弧度值
/// @return 正弦值
pub fn sin(value: f64) f64 {
    return @sin(value);
}

/// cos - 余弦
/// @param value 弧度值
/// @return 余弦值
pub fn cos(value: f64) f64 {
    return @cos(value);
}

/// tan - 正切
/// @param value 弧度值
/// @return 正切值
pub fn tan(value: f64) f64 {
    return @tan(value);
}

/// log - 自然对数
/// @param value 正数
/// @return 自然对数，非正数返回 NaN 或 -Inf
pub fn log(value: f64) f64 {
    if (value <= 0) {
        if (value == 0) return -math.inf(f64);
        return math.nan(f64);
    }
    return @log(value);
}

/// log10 - 常用对数
/// @param value 正数
/// @return 常用对数
pub fn log10(value: f64) f64 {
    if (value <= 0) {
        if (value == 0) return -math.inf(f64);
        return math.nan(f64);
    }
    return @log10(value);
}

/// exp - e 的幂
/// @param value 指数
/// @return e^value
pub fn exp(value: f64) f64 {
    return @exp(value);
}

/// fmod - 浮点取模
/// @param x 被除数
/// @param y 除数
/// @return 余数
pub fn fmod(x: f64, y: f64) !f64 {
    if (y == 0) return CoreError.DivisionByZero;
    return @mod(x, y);
}

/// deg2rad - 度数转弧度
/// @param degrees 度数
/// @return 弧度
pub fn deg2rad(degrees: f64) f64 {
    return degrees * math.pi / 180.0;
}

/// rad2deg - 弧度转度数
/// @param radians 弧度
/// @return 度数
pub fn rad2deg(radians: f64) f64 {
    return radians * 180.0 / math.pi;
}

/// pi - 返回圆周率
/// @return π 的值
pub fn pi() f64 {
    return math.pi;
}

/// 位运算：按位与
pub fn bit_and(a: i64, b: i64) i64 {
    return a & b;
}

/// 位运算：按位或
pub fn bit_or(a: i64, b: i64) i64 {
    return a | b;
}

/// 位运算：按位异或
pub fn bit_xor(a: i64, b: i64) i64 {
    return a ^ b;
}

/// 位运算：按位取反
pub fn bit_not(a: i64) i64 {
    return ~a;
}

/// 位运算：左移
pub fn bit_shift_left(a: i64, b: u6) i64 {
    return a << b;
}

/// 位运算：右移
pub fn bit_shift_right(a: i64, b: u6) i64 {
    return a >> b;
}

// ============================================================================
// 测试
// ============================================================================

test "abs" {
    try std.testing.expectEqual(@as(i64, 5), abs(.{ .int = -5 }).int);
    try std.testing.expectEqual(@as(i64, 5), abs(.{ .int = 5 }).int);
    try std.testing.expectEqual(@as(f64, 3.14), abs(.{ .float = -3.14 }).float);
}

test "round" {
    try std.testing.expectEqual(@as(f64, 3.0), round(3.4, 0));
    try std.testing.expectEqual(@as(f64, 4.0), round(3.5, 0));
    try std.testing.expectEqual(@as(f64, 3.14), round(3.1415, 2));
}

test "floor and ceil" {
    try std.testing.expectEqual(@as(f64, 3.0), floor(3.9));
    try std.testing.expectEqual(@as(f64, 4.0), ceil(3.1));
}

test "sqrt" {
    try std.testing.expectEqual(@as(f64, 2.0), sqrt(4.0));
    try std.testing.expectEqual(@as(f64, 3.0), sqrt(9.0));
    try std.testing.expect(math.isNan(sqrt(-1.0)));
}

test "pow" {
    try std.testing.expectEqual(@as(f64, 8.0), pow(2.0, 3.0));
    try std.testing.expectEqual(@as(f64, 1.0), pow(5.0, 0.0));
}

test "min and max" {
    try std.testing.expectEqual(@as(f64, 1.0), min(1.0, 5.0));
    try std.testing.expectEqual(@as(f64, 5.0), max(1.0, 5.0));
}

test "trigonometric functions" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), sin(0.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), cos(0.0), 0.0001);
}

test "log functions" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), log(1.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), log10(10.0), 0.0001);
}

test "deg2rad and rad2deg" {
    try std.testing.expectApproxEqAbs(math.pi, deg2rad(180.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 180.0), rad2deg(math.pi), 0.0001);
}

test "bit operations" {
    try std.testing.expectEqual(@as(i64, 0b0100), bit_and(0b0110, 0b0101));
    try std.testing.expectEqual(@as(i64, 0b0111), bit_or(0b0110, 0b0101));
    try std.testing.expectEqual(@as(i64, 0b0011), bit_xor(0b0110, 0b0101));
    try std.testing.expectEqual(@as(i64, 8), bit_shift_left(2, 2));
    try std.testing.expectEqual(@as(i64, 2), bit_shift_right(8, 2));
}
