//! 超快 Value 类型系统
//! 目标：消除类型检查开销，NaN-boxing，类型特化操作
//!
//! 核心技术：
//! 1. NaN-boxing - 64位内存储所有类型
//! 2. 类型特化算术 - 无运行时检查
//! 3. 小整数缓存 - 常用整数预分配
//! 4. Tagged Pointer - 指针类型编码
//! 5. 48位整数支持 - 覆盖PHP int范围 (±140万亿)
//!
//! 整数编码方案 (48-bit signed):
//! - 使用 SIGN_BIT | QNAN 作为整数标记
//! - 低48位存储整数值 (补码表示)
//! - 范围: -140,737,488,355,328 到 +140,737,488,355,327
//! - 超出范围自动转为浮点数

const std = @import("std");
const fast_pool = @import("fast_pool.zig");

// ============================================================================
// NaN-boxing 常量
// ============================================================================

/// IEEE 754 双精度 NaN 的 quiet NaN 位模式
const QNAN: u64 = 0x7ffc000000000000;
const SIGN_BIT: u64 = 0x8000000000000000;

/// 类型标签（使用 NaN payload 的低位）
const TAG_NIL: u64 = 1;
const TAG_FALSE: u64 = 2;
const TAG_TRUE: u64 = 3;
const TAG_INT: u64 = SIGN_BIT; // 整数使用符号位区分

/// 48位整数常量
const INT48_MASK: u64 = 0x0000FFFFFFFFFFFF; // 低48位掩码
const INT48_SIGN_BIT: u64 = 0x0000800000000000; // 第47位为符号位
const INT48_MAX: i64 = 0x00007FFFFFFFFFFF; // 140,737,488,355,327
const INT48_MIN: i64 = -0x0000800000000000; // -140,737,488,355,328

/// 指针类型标签（3位，支持8种指针类型）
const PTR_STRING: u64 = 0;
const PTR_ARRAY: u64 = 1;
const PTR_OBJECT: u64 = 2;
const PTR_CLOSURE: u64 = 3;
const PTR_RESOURCE: u64 = 4;
const PTR_USERFUNC: u64 = 5;

const PTR_MASK: u64 = 0x7;
const PTR_SHIFT: u6 = 48;

// ============================================================================
// FastValue - NaN-boxed 值类型
// ============================================================================

pub const FastValue = packed struct {
    bits: u64,

    // --- 构造函数 ---

    pub const nil = FastValue{ .bits = QNAN | TAG_NIL };
    pub const @"false" = FastValue{ .bits = QNAN | TAG_FALSE };
    pub const @"true" = FastValue{ .bits = QNAN | TAG_TRUE };

    pub fn initFloat(f: f64) FastValue {
        return .{ .bits = @bitCast(f) };
    }

    /// 创建整数值 (支持48位有符号整数)
    /// 范围: -140,737,488,355,328 到 +140,737,488,355,327
    /// 超出范围自动转为浮点数
    pub fn initInt(i: i64) FastValue {
        // 检查是否在48位范围内
        if (i >= INT48_MIN and i <= INT48_MAX) {
            // 48位补码编码：直接截取低48位
            const encoded: u64 = @as(u64, @bitCast(i)) & INT48_MASK;
            return .{ .bits = QNAN | TAG_INT | encoded };
        }
        // 超出范围，使用浮点数存储
        return initFloat(@floatFromInt(i));
    }

    /// 创建32位整数值 (快速路径，无范围检查)
    pub fn initInt32(i: i32) FastValue {
        const extended: i64 = i;
        const encoded: u64 = @as(u64, @bitCast(extended)) & INT48_MASK;
        return .{ .bits = QNAN | TAG_INT | encoded };
    }

    pub fn initPtr(ptr: *anyopaque, tag: u64) FastValue {
        const addr = @intFromPtr(ptr);
        return .{ .bits = QNAN | (tag << PTR_SHIFT) | (addr & INT48_MASK) };
    }

    // --- 类型检查 ---

    pub fn isFloat(self: FastValue) bool {
        return (self.bits & QNAN) != QNAN;
    }

    pub fn isNil(self: FastValue) bool {
        return self.bits == (QNAN | TAG_NIL);
    }

    pub fn isBool(self: FastValue) bool {
        return self.bits == (QNAN | TAG_FALSE) or self.bits == (QNAN | TAG_TRUE);
    }

    pub fn isInt(self: FastValue) bool {
        return (self.bits & (QNAN | TAG_INT)) == (QNAN | TAG_INT);
    }

    pub fn isPtr(self: FastValue) bool {
        return (self.bits & QNAN) == QNAN and
            !self.isNil() and !self.isBool() and !self.isInt();
    }

    pub fn ptrTag(self: FastValue) u64 {
        return (self.bits >> PTR_SHIFT) & PTR_MASK;
    }

    pub fn isString(self: FastValue) bool {
        return self.isPtr() and self.ptrTag() == PTR_STRING;
    }

    pub fn isArray(self: FastValue) bool {
        return self.isPtr() and self.ptrTag() == PTR_ARRAY;
    }

    pub fn isObject(self: FastValue) bool {
        return self.isPtr() and self.ptrTag() == PTR_OBJECT;
    }

    // --- 值提取 ---

    pub fn asFloat(self: FastValue) f64 {
        return @bitCast(self.bits);
    }

    /// 提取48位有符号整数
    pub fn asInt(self: FastValue) i64 {
        const raw: u64 = self.bits & INT48_MASK;
        // 符号扩展：如果第47位为1，则为负数
        if ((raw & INT48_SIGN_BIT) != 0) {
            // 负数：填充高16位为1
            return @bitCast(raw | 0xFFFF000000000000);
        }
        return @bitCast(raw);
    }

    /// 提取为32位整数 (截断，用于兼容旧代码)
    pub fn asInt32(self: FastValue) i32 {
        return @truncate(self.asInt());
    }

    pub fn asBool(self: FastValue) bool {
        return self.bits == (QNAN | TAG_TRUE);
    }

    pub fn asPtr(self: FastValue, comptime T: type) T {
        const addr = self.bits & INT48_MASK;
        return @ptrFromInt(addr);
    }

    // --- 类型转换 ---

    pub fn toFloat(self: FastValue) f64 {
        if (self.isFloat()) return self.asFloat();
        if (self.isInt()) return @floatFromInt(self.asInt());
        if (self.isBool()) return if (self.asBool()) 1.0 else 0.0;
        return 0.0;
    }

    pub fn toInt(self: FastValue) i64 {
        if (self.isInt()) return self.asInt();
        if (self.isFloat()) {
            const f = self.asFloat();
            // 安全转换：检查浮点数是否在i64范围内
            if (f >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
                f <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
            {
                return @intFromFloat(f);
            }
            return 0;
        }
        if (self.isBool()) return if (self.asBool()) 1 else 0;
        return 0;
    }

    /// 转换为32位整数 (兼容旧代码)
    pub fn toInt32(self: FastValue) i32 {
        return @truncate(self.toInt());
    }

    pub fn toBool(self: FastValue) bool {
        if (self.isBool()) return self.asBool();
        if (self.isNil()) return false;
        if (self.isInt()) return self.asInt() != 0;
        if (self.isFloat()) return self.asFloat() != 0.0;
        return true;
    }

    // --- 范围检查工具 ---

    /// 检查i64是否在48位整数范围内
    pub fn fitsIn48Bits(i: i64) bool {
        return i >= INT48_MIN and i <= INT48_MAX;
    }

    /// 获取48位整数最大值
    pub fn maxInt48() i64 {
        return INT48_MAX;
    }

    /// 获取48位整数最小值
    pub fn minInt48() i64 {
        return INT48_MIN;
    }
};

// ============================================================================
// 类型特化算术操作 - 无运行时类型检查
// ============================================================================

pub const FastOps = struct {
    // --- 整数操作（使用 i64，支持48位范围） ---

    pub inline fn addInt(a: FastValue, b: FastValue) FastValue {
        const result = a.asInt() +% b.asInt();
        return FastValue.initInt(result);
    }

    pub inline fn subInt(a: FastValue, b: FastValue) FastValue {
        const result = a.asInt() -% b.asInt();
        return FastValue.initInt(result);
    }

    pub inline fn mulInt(a: FastValue, b: FastValue) FastValue {
        const result = a.asInt() *% b.asInt();
        return FastValue.initInt(result);
    }

    pub inline fn divInt(a: FastValue, b: FastValue) FastValue {
        const bv = b.asInt();
        if (bv == 0) return FastValue.initInt(0);
        return FastValue.initInt(@divTrunc(a.asInt(), bv));
    }

    pub inline fn modInt(a: FastValue, b: FastValue) FastValue {
        const bv = b.asInt();
        if (bv == 0) return FastValue.initInt(0);
        return FastValue.initInt(@mod(a.asInt(), bv));
    }

    pub inline fn negInt(a: FastValue) FastValue {
        return FastValue.initInt(-%a.asInt());
    }

    // --- 浮点操作 ---

    pub inline fn addFloat(a: FastValue, b: FastValue) FastValue {
        return FastValue.initFloat(a.asFloat() + b.asFloat());
    }

    pub inline fn subFloat(a: FastValue, b: FastValue) FastValue {
        return FastValue.initFloat(a.asFloat() - b.asFloat());
    }

    pub inline fn mulFloat(a: FastValue, b: FastValue) FastValue {
        return FastValue.initFloat(a.asFloat() * b.asFloat());
    }

    pub inline fn divFloat(a: FastValue, b: FastValue) FastValue {
        return FastValue.initFloat(a.asFloat() / b.asFloat());
    }

    pub inline fn negFloat(a: FastValue) FastValue {
        return FastValue.initFloat(-a.asFloat());
    }

    // --- 比较操作 ---

    pub inline fn eqInt(a: FastValue, b: FastValue) FastValue {
        return if (a.asInt() == b.asInt()) FastValue.true else FastValue.false;
    }

    pub inline fn ltInt(a: FastValue, b: FastValue) FastValue {
        return if (a.asInt() < b.asInt()) FastValue.true else FastValue.false;
    }

    pub inline fn gtInt(a: FastValue, b: FastValue) FastValue {
        return if (a.asInt() > b.asInt()) FastValue.true else FastValue.false;
    }

    pub inline fn leInt(a: FastValue, b: FastValue) FastValue {
        return if (a.asInt() <= b.asInt()) FastValue.true else FastValue.false;
    }

    pub inline fn geInt(a: FastValue, b: FastValue) FastValue {
        return if (a.asInt() >= b.asInt()) FastValue.true else FastValue.false;
    }

    pub inline fn eqFloat(a: FastValue, b: FastValue) FastValue {
        return if (a.asFloat() == b.asFloat()) FastValue.true else FastValue.false;
    }

    pub inline fn ltFloat(a: FastValue, b: FastValue) FastValue {
        return if (a.asFloat() < b.asFloat()) FastValue.true else FastValue.false;
    }

    pub inline fn gtFloat(a: FastValue, b: FastValue) FastValue {
        return if (a.asFloat() > b.asFloat()) FastValue.true else FastValue.false;
    }

    // --- 位操作 (使用i64) ---

    pub inline fn bitAnd(a: FastValue, b: FastValue) FastValue {
        return FastValue.initInt(a.asInt() & b.asInt());
    }

    pub inline fn bitOr(a: FastValue, b: FastValue) FastValue {
        return FastValue.initInt(a.asInt() | b.asInt());
    }

    pub inline fn bitXor(a: FastValue, b: FastValue) FastValue {
        return FastValue.initInt(a.asInt() ^ b.asInt());
    }

    pub inline fn bitNot(a: FastValue) FastValue {
        return FastValue.initInt(~a.asInt());
    }

    pub inline fn shl(a: FastValue, b: FastValue) FastValue {
        const shift: u6 = @intCast(@as(u64, @bitCast(b.asInt())) & 63);
        return FastValue.initInt(a.asInt() << shift);
    }

    pub inline fn shr(a: FastValue, b: FastValue) FastValue {
        const shift: u6 = @intCast(@as(u64, @bitCast(b.asInt())) & 63);
        return FastValue.initInt(a.asInt() >> shift);
    }

    // --- 通用操作（带类型检查） ---

    pub fn add(a: FastValue, b: FastValue) FastValue {
        if (a.isInt() and b.isInt()) {
            // 检查溢出：如果结果超出48位范围，转为浮点
            const ai = a.asInt();
            const bi = b.asInt();
            const result = @addWithOverflow(ai, bi);
            if (result[1] != 0 or !FastValue.fitsIn48Bits(result[0])) {
                return addFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
            }
            return FastValue.initInt(result[0]);
        }
        return addFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
    }

    pub fn sub(a: FastValue, b: FastValue) FastValue {
        if (a.isInt() and b.isInt()) {
            const ai = a.asInt();
            const bi = b.asInt();
            const result = @subWithOverflow(ai, bi);
            if (result[1] != 0 or !FastValue.fitsIn48Bits(result[0])) {
                return subFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
            }
            return FastValue.initInt(result[0]);
        }
        return subFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
    }

    pub fn mul(a: FastValue, b: FastValue) FastValue {
        if (a.isInt() and b.isInt()) {
            const ai = a.asInt();
            const bi = b.asInt();
            const result = @mulWithOverflow(ai, bi);
            if (result[1] != 0 or !FastValue.fitsIn48Bits(result[0])) {
                return mulFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
            }
            return FastValue.initInt(result[0]);
        }
        return mulFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
    }

    pub fn div(a: FastValue, b: FastValue) FastValue {
        // PHP 除法总是返回浮点数（除非两个整数且整除）
        if (a.isInt() and b.isInt()) {
            const ai = a.asInt();
            const bi = b.asInt();
            if (bi != 0 and @mod(ai, bi) == 0) {
                const result = @divTrunc(ai, bi);
                if (FastValue.fitsIn48Bits(result)) {
                    return FastValue.initInt(result);
                }
            }
        }
        return divFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
    }

    pub fn eq(a: FastValue, b: FastValue) FastValue {
        if (a.bits == b.bits) return FastValue.true;
        if (a.isInt() and b.isInt()) return eqInt(a, b);
        if ((a.isFloat() or a.isInt()) and (b.isFloat() or b.isInt())) {
            return eqFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
        }
        return FastValue.false;
    }

    pub fn lt(a: FastValue, b: FastValue) FastValue {
        if (a.isInt() and b.isInt()) return ltInt(a, b);
        return ltFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
    }

    pub fn gt(a: FastValue, b: FastValue) FastValue {
        if (a.isInt() and b.isInt()) return gtInt(a, b);
        return gtFloat(FastValue.initFloat(a.toFloat()), FastValue.initFloat(b.toFloat()));
    }

    pub fn le(a: FastValue, b: FastValue) FastValue {
        if (a.isInt() and b.isInt()) return leInt(a, b);
        return if (a.toFloat() <= b.toFloat()) FastValue.true else FastValue.false;
    }

    pub fn ge(a: FastValue, b: FastValue) FastValue {
        if (a.isInt() and b.isInt()) return geInt(a, b);
        return if (a.toFloat() >= b.toFloat()) FastValue.true else FastValue.false;
    }
};

// ============================================================================
// 小整数缓存
// ============================================================================

pub const SmallIntCache = struct {
    const MIN: i64 = -128;
    const MAX: i64 = 127;
    const SIZE = @as(usize, @intCast(MAX - MIN + 1));

    values: [SIZE]FastValue,

    pub fn init() SmallIntCache {
        var cache: SmallIntCache = undefined;
        var i: i64 = MIN;
        var idx: usize = 0;
        while (i <= MAX) : ({
            i += 1;
            idx += 1;
        }) {
            cache.values[idx] = FastValue.initInt(i);
        }
        return cache;
    }

    pub fn get(self: *const SmallIntCache, i: i64) FastValue {
        if (i >= MIN and i <= MAX) {
            return self.values[@intCast(i - MIN)];
        }
        return FastValue.initInt(i);
    }

    pub fn isCached(i: i64) bool {
        return i >= MIN and i <= MAX;
    }
};

/// 全局小整数缓存
pub var small_int_cache: SmallIntCache = SmallIntCache.init();

// ============================================================================
// 值栈 - 优化的操作数栈
// ============================================================================

pub const ValueStack = struct {
    const MAX_SIZE = 65536;

    data: []FastValue,
    top: u32,

    pub fn init(allocator: std.mem.Allocator) !ValueStack {
        return .{
            .data = try allocator.alloc(FastValue, MAX_SIZE),
            .top = 0,
        };
    }

    pub fn deinit(self: *ValueStack, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }

    pub inline fn push(self: *ValueStack, v: FastValue) void {
        self.data[self.top] = v;
        self.top += 1;
    }

    pub inline fn pop(self: *ValueStack) FastValue {
        self.top -= 1;
        return self.data[self.top];
    }

    pub inline fn peek(self: *const ValueStack, offset: u32) FastValue {
        return self.data[self.top - 1 - offset];
    }

    pub inline fn peekPtr(self: *ValueStack, offset: u32) *FastValue {
        return &self.data[self.top - 1 - offset];
    }

    pub inline fn drop(self: *ValueStack, n: u32) void {
        self.top -= n;
    }

    pub inline fn dup(self: *ValueStack) void {
        self.data[self.top] = self.data[self.top - 1];
        self.top += 1;
    }

    pub inline fn swap(self: *ValueStack) void {
        const tmp = self.data[self.top - 1];
        self.data[self.top - 1] = self.data[self.top - 2];
        self.data[self.top - 2] = tmp;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "FastValue nil/bool" {
    try std.testing.expect(FastValue.nil.isNil());
    try std.testing.expect(FastValue.true.isBool());
    try std.testing.expect(FastValue.true.asBool() == true);
    try std.testing.expect(FastValue.false.asBool() == false);
}

test "FastValue int" {
    const v = FastValue.initInt(42);
    try std.testing.expect(v.isInt());
    try std.testing.expect(v.asInt() == 42);

    const neg = FastValue.initInt(-100);
    try std.testing.expect(neg.asInt() == -100);
}

test "FastValue int 48-bit range" {
    // 测试48位整数边界
    const max48 = FastValue.initInt(INT48_MAX);
    try std.testing.expect(max48.isInt());
    try std.testing.expect(max48.asInt() == INT48_MAX);

    const min48 = FastValue.initInt(INT48_MIN);
    try std.testing.expect(min48.isInt());
    try std.testing.expect(min48.asInt() == INT48_MIN);

    // 测试大整数 (超出32位但在48位范围内)
    const big = FastValue.initInt(1_000_000_000_000); // 1万亿
    try std.testing.expect(big.isInt());
    try std.testing.expect(big.asInt() == 1_000_000_000_000);

    const big_neg = FastValue.initInt(-1_000_000_000_000);
    try std.testing.expect(big_neg.isInt());
    try std.testing.expect(big_neg.asInt() == -1_000_000_000_000);

    // 测试超出48位范围 (应转为浮点数)
    const overflow = FastValue.initInt(INT48_MAX + 1);
    try std.testing.expect(overflow.isFloat());
    try std.testing.expect(overflow.asFloat() == @as(f64, @floatFromInt(INT48_MAX + 1)));
}

test "FastValue float" {
    const v = FastValue.initFloat(3.14);
    try std.testing.expect(v.isFloat());
    try std.testing.expect(v.asFloat() == 3.14);
}

test "FastOps int" {
    const a = FastValue.initInt(10);
    const b = FastValue.initInt(3);

    try std.testing.expect(FastOps.addInt(a, b).asInt() == 13);
    try std.testing.expect(FastOps.subInt(a, b).asInt() == 7);
    try std.testing.expect(FastOps.mulInt(a, b).asInt() == 30);
    try std.testing.expect(FastOps.divInt(a, b).asInt() == 3);
    try std.testing.expect(FastOps.modInt(a, b).asInt() == 1);
}

test "FastOps int 48-bit" {
    // 测试大整数运算
    const a = FastValue.initInt(100_000_000_000); // 1000亿
    const b = FastValue.initInt(200_000_000_000); // 2000亿

    const sum = FastOps.add(a, b);
    try std.testing.expect(sum.isInt());
    try std.testing.expect(sum.asInt() == 300_000_000_000);

    const diff = FastOps.sub(b, a);
    try std.testing.expect(diff.isInt());
    try std.testing.expect(diff.asInt() == 100_000_000_000);

    // 测试溢出转浮点
    const big = FastValue.initInt(INT48_MAX);
    const one = FastValue.initInt(1);
    const overflow_result = FastOps.add(big, one);
    try std.testing.expect(overflow_result.isFloat());
}

test "FastOps float" {
    const a = FastValue.initFloat(10.0);
    const b = FastValue.initFloat(3.0);

    try std.testing.expect(FastOps.addFloat(a, b).asFloat() == 13.0);
    try std.testing.expect(FastOps.subFloat(a, b).asFloat() == 7.0);
    try std.testing.expect(FastOps.mulFloat(a, b).asFloat() == 30.0);
}

test "SmallIntCache" {
    const v1 = small_int_cache.get(0);
    const v2 = small_int_cache.get(0);
    try std.testing.expect(v1.bits == v2.bits);

    try std.testing.expect(SmallIntCache.isCached(127));
    try std.testing.expect(!SmallIntCache.isCached(128));
}

test "ValueStack" {
    var stack = try ValueStack.init(std.testing.allocator);
    defer stack.deinit(std.testing.allocator);

    stack.push(FastValue.initInt(1));
    stack.push(FastValue.initInt(2));
    stack.push(FastValue.initInt(3));

    try std.testing.expect(stack.pop().asInt() == 3);
    try std.testing.expect(stack.peek(0).asInt() == 2);

    stack.swap();
    try std.testing.expect(stack.pop().asInt() == 1);
}

test "FastValue fitsIn48Bits" {
    try std.testing.expect(FastValue.fitsIn48Bits(0));
    try std.testing.expect(FastValue.fitsIn48Bits(INT48_MAX));
    try std.testing.expect(FastValue.fitsIn48Bits(INT48_MIN));
    try std.testing.expect(!FastValue.fitsIn48Bits(INT48_MAX + 1));
    try std.testing.expect(!FastValue.fitsIn48Bits(INT48_MIN - 1));
}
