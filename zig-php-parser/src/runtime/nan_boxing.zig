const std = @import("std");

/// NaN-Boxing 值表示
/// 使用 64 位浮点数的 NaN 位模式存储类型标签和数据
pub const Value = packed struct {
    bits: u64,

    // 类型标签（使用 NaN 的高位）
    const TAG_MASK: u64 = 0xFFFF_0000_0000_0000;
    const TAG_INT: u64 = 0xFFF8_0000_0000_0000;
    const TAG_BOOL: u64 = 0xFFF9_0000_0000_0000;
    const TAG_NULL: u64 = 0xFFFA_0000_0000_0000;
    const TAG_OBJ: u64 = 0xFFFB_0000_0000_0000;

    /// 创建整数值
    pub inline fn makeInt(val: i32) Value {
        const extended: i64 = val;
        const unsigned: u64 = @bitCast(extended);
        return .{ .bits = TAG_INT | (unsigned & 0xFFFF_FFFF) };
    }

    /// 创建浮点值
    pub inline fn makeFloat(val: f64) Value {
        return .{ .bits = @bitCast(val) };
    }

    /// 创建布尔值
    pub inline fn makeBool(val: bool) Value {
        return .{ .bits = TAG_BOOL | @as(u64, if (val) 1 else 0) };
    }

    /// 创建 null 值
    pub inline fn makeNull() Value {
        return .{ .bits = TAG_NULL };
    }

    /// 创建对象值
    pub inline fn makeObject(ptr: usize) Value {
        return .{ .bits = TAG_OBJ | ptr };
    }

    /// 判断是否为整数
    pub inline fn isInt(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_INT;
    }

    /// 判断是否为浮点数
    pub inline fn isFloat(self: Value) bool {
        // 浮点数的标签不是 0xFFFF 开头
        return (self.bits & TAG_MASK) < TAG_INT;
    }

    /// 判断是否为布尔值
    pub inline fn isBool(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_BOOL;
    }

    /// 判断是否为 null
    pub inline fn isNull(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_NULL;
    }

    /// 判断是否为对象
    pub inline fn isObject(self: Value) bool {
        return (self.bits & TAG_MASK) == TAG_OBJ;
    }

    /// 转换为整数
    pub inline fn asInt(self: Value) i32 {
        const masked = self.bits & 0xFFFF_FFFF;
        const signed: i32 = @bitCast(@as(u32, @truncate(masked)));
        return signed;
    }

    /// 转换为浮点数
    pub inline fn asFloat(self: Value) f64 {
        return @bitCast(self.bits);
    }

    /// 转换为布尔值
    pub inline fn asBool(self: Value) bool {
        return (self.bits & 1) != 0;
    }

    /// 转换为对象指针
    pub inline fn asObject(self: Value) usize {
        return self.bits & ~TAG_MASK;
    }

    /// 值相等性比较
    pub fn equals(self: Value, other: Value) bool {
        if (self.isInt() and other.isInt()) {
            return self.asInt() == other.asInt();
        }
        if (self.isFloat() and other.isFloat()) {
            return self.asFloat() == other.asFloat();
        }
        if (self.isBool() and other.isBool()) {
            return self.asBool() == other.asBool();
        }
        if (self.isNull() and other.isNull()) {
            return true;
        }
        if (self.isObject() and other.isObject()) {
            return self.asObject() == other.asObject();
        }
        return false;
    }
};
