const std = @import("std");

/// NumberWrapper - 数字方法文档说明
/// 
/// 重要：所有数字方法调用通过 VM 的 evaluateMethodCall 自动处理
/// 使用 PHP 的 -> 语法：(3)->pow(2)
/// 
/// 数学方法（返回浮点数）：
/// - abs()        : 绝对值
/// - ceil()       : 向上取整
/// - floor()      : 向下取整
/// - round()      : 四舍五入
/// - sqrt()       : 平方根
/// - sin()        : 正弦
/// - cos()        : 余弦
/// - tan()        : 正切
/// - log()        : 自然对数
/// - exp()        : e的幂
/// - pow(n)       : 幂运算
///
/// 位运算方法（返回整数）：
/// - bitAnd(n)        : 按位与
/// - bit_and(n)       : 按位与（别名）
/// - bitOr(n)         : 按位或
/// - bit_or(n)        : 按位或（别名）
/// - bitXor(n)        : 按位异或
/// - bit_xor(n)       : 按位异或（别名）
/// - bitNot()         : 按位取反
/// - bit_not()        : 按位取反（别名）
/// - bitShiftLeft(n)  : 左移
/// - bit_shift_left(n): 左移（别名）
/// - bitShiftRight(n) : 右移
/// - bit_shift_right(n): 右移（别名）
///
/// 示例：
/// ```php
/// $result = (3)->pow(2);           // 9
/// $abs = (-5)->abs();              // 5
/// $and = (12)->bitAnd(10);         // 8
/// $chain = (16)->sqrt()->pow(2);   // 16 (支持链式调用)
/// ```
///
/// 注意：
/// 1. 所有方法由 VM 的 evaluateMethodCall 自动调用
/// 2. 整数和浮点数自动转换
/// 3. 支持方法链式调用
/// 4. 位运算自动将浮点数转换为整数
pub const NumberWrapper = struct {
    value: union(enum) {
        integer: i64,
        float: f64,
    },

    pub fn initInt(value: i64) NumberWrapper {
        return NumberWrapper{ .value = .{ .integer = value } };
    }

    pub fn initFloat(value: f64) NumberWrapper {
        return NumberWrapper{ .value = .{ .float = value } };
    }

    pub fn toFloat(self: NumberWrapper) f64 {
        return switch (self.value) {
            .integer => |v| @floatFromInt(v),
            .float => |v| v,
        };
    }

    pub fn toInt(self: NumberWrapper) i64 {
        return switch (self.value) {
            .integer => |v| v,
            .float => |v| @intFromFloat(v),
        };
    }

    // 以下方法由 VM 的 evaluateMethodCall 调用
    // 不需要在这里重复实现业务逻辑
    
    pub fn abs(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @abs(val);
    }

    pub fn ceil(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @ceil(val);
    }

    pub fn floor(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @floor(val);
    }

    pub fn round(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @round(val);
    }

    pub fn sqrt(self: NumberWrapper) f64 {
        const val = self.toFloat();
        if (val < 0) return std.math.nan(f64);
        return @sqrt(val);
    }

    pub fn sin(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @sin(val);
    }

    pub fn cos(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @cos(val);
    }

    pub fn tan(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @tan(val);
    }

    pub fn log(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @log(val);
    }

    pub fn exp(self: NumberWrapper) f64 {
        const val = self.toFloat();
        return @exp(val);
    }

    pub fn pow(self: NumberWrapper, exponent: NumberWrapper) f64 {
        const base = self.toFloat();
        const exp_val = exponent.toFloat();
        return std.math.pow(f64, base, exp_val);
    }

    pub fn bitAnd(self: NumberWrapper, other: NumberWrapper) i64 {
        const a = self.toInt();
        const b = other.toInt();
        return a & b;
    }

    pub fn bitOr(self: NumberWrapper, other: NumberWrapper) i64 {
        const a = self.toInt();
        const b = other.toInt();
        return a | b;
    }

    pub fn bitXor(self: NumberWrapper, other: NumberWrapper) i64 {
        const a = self.toInt();
        const b = other.toInt();
        return a ^ b;
    }

    pub fn bitNot(self: NumberWrapper) i64 {
        const a = self.toInt();
        return ~a;
    }

    pub fn bitShiftLeft(self: NumberWrapper, shift: NumberWrapper) i64 {
        const a = self.toInt();
        const s = shift.toInt();
        const shift_amount = @as(u6, @intCast(@mod(s, 64)));
        return a << shift_amount;
    }

    pub fn bitShiftRight(self: NumberWrapper, shift: NumberWrapper) i64 {
        const a = self.toInt();
        const s = shift.toInt();
        const shift_amount = @as(u6, @intCast(@mod(s, 64)));
        return a >> shift_amount;
    }
};
