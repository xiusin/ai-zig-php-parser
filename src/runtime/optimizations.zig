//! 运行时优化模块
//!
//! 实现小整数缓存、字符串池化和快速路径优化。
//!
//! @ownership ISOLATED
//! @thread-safety SINGLE_THREADED

const std = @import("std");
const Allocator = std.mem.Allocator;
const nanbox_abi = @import("nanbox_abi");

// ============================================================================
// 12.1 小整数缓存
// ============================================================================

/// 小整数缓存范围
pub const SMALL_INT_MIN: i64 = -128;
pub const SMALL_INT_MAX: i64 = 127;
pub const SMALL_INT_CACHE_SIZE: usize = 256;

/// 小整数缓存
/// 缓存 -128 到 127 的整数值，避免重复创建
pub const SmallIntCache = struct {
    /// 预编码的整数值（NaN boxing 格式）
    cache: [SMALL_INT_CACHE_SIZE]u64,
    initialized: bool,

    const Self = @This();

    /// 编译时生成缓存
    pub fn init() Self {
        var self = Self{
            .cache = undefined,
            .initialized = true,
        };

        comptime var i: i64 = SMALL_INT_MIN;
        inline while (i <= SMALL_INT_MAX) : (i += 1) {
            const idx = @as(usize, @intCast(i - SMALL_INT_MIN));
            self.cache[idx] = encodeInt(i);
        }

        return self;
    }

    /// 获取缓存的整数值
    pub fn get(self: *const Self, i: i64) ?u64 {
        if (i >= SMALL_INT_MIN and i <= SMALL_INT_MAX) {
            const idx = @as(usize, @intCast(i - SMALL_INT_MIN));
            return self.cache[idx];
        }
        return null;
    }

    /// 检查整数是否在缓存范围内
    pub fn isSmallInt(i: i64) bool {
        return i >= SMALL_INT_MIN and i <= SMALL_INT_MAX;
    }

    /// 编码整数为 NaN boxing 格式
    fn encodeInt(i: i64) u64 {
        return nanbox_abi.encodeInt(i);
    }
};

/// 全局小整数缓存（编译时初始化）
pub const small_int_cache = SmallIntCache.init();

// ============================================================================
// 12.2 字符串池化
// ============================================================================

/// 字符串池
/// 缓存常用字符串，避免重复分配
pub const StringPool = struct {
    allocator: Allocator,
    pool: std.StringHashMap([]const u8),
    stats: PoolStats,

    const Self = @This();

    pub const PoolStats = struct {
        hits: u64 = 0,
        misses: u64 = 0,
        total_bytes_saved: u64 = 0,
    };

    /// 初始化字符串池
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .pool = std.StringHashMap([]const u8).init(allocator),
            .stats = .{},
        };
    }

    /// 释放字符串池
    pub fn deinit(self: *Self) void {
        var iter = self.pool.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.pool.deinit();
    }

    /// 获取或添加字符串到池中
    pub fn intern(self: *Self, str: []const u8) ![]const u8 {
        if (self.pool.get(str)) |pooled| {
            self.stats.hits += 1;
            self.stats.total_bytes_saved += str.len;
            return pooled;
        }

        self.stats.misses += 1;

        const owned = try self.allocator.dupe(u8, str);
        try self.pool.put(owned, owned);
        return owned;
    }

    /// 获取池统计信息
    pub fn getStats(self: *const Self) PoolStats {
        return self.stats;
    }

    /// 获取池大小
    pub fn size(self: *const Self) usize {
        return self.pool.count();
    }
};

// ============================================================================
// 12.3 快速路径优化
// ============================================================================

/// 快速整数加法（溢出检查）
pub inline fn fastIntAdd(a: i64, b: i64) ?i64 {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) return null;
    return result[0];
}

/// 快速整数减法（溢出检查）
pub inline fn fastIntSub(a: i64, b: i64) ?i64 {
    const result = @subWithOverflow(a, b);
    if (result[1] != 0) return null;
    return result[0];
}

/// 快速整数乘法（溢出检查）
pub inline fn fastIntMul(a: i64, b: i64) ?i64 {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) return null;
    return result[0];
}

/// 快速整数除法（除零检查）
pub inline fn fastIntDiv(a: i64, b: i64) ?i64 {
    if (b == 0) return null;
    if (a == std.math.minInt(i64) and b == -1) return null;
    return @divTrunc(a, b);
}

/// 快速整数取模（除零检查）
pub inline fn fastIntMod(a: i64, b: i64) ?i64 {
    if (b == 0) return null;
    return @mod(a, b);
}

/// 快速字符串比较（长度优先）
pub inline fn fastStringCompare(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    return std.mem.eql(u8, a, b);
}

/// 快速字符串哈希
pub inline fn fastStringHash(str: []const u8) u64 {
    return std.hash.Wyhash.hash(0, str);
}

/// 快速数组边界检查
pub inline fn fastBoundsCheck(index: i64, len: usize) ?usize {
    if (index < 0) {
        const abs_idx = @as(usize, @intCast(-index));
        if (abs_idx > len) return null;
        return len - abs_idx;
    }
    const idx = @as(usize, @intCast(index));
    if (idx >= len) return null;
    return idx;
}

/// 快速类型判断（整数）
pub inline fn isQuickInt(val: u64) bool {
    const SIGN_BIT: u64 = 0x8000000000000000;
    const QNAN: u64 = 0x7FFC000000000000;
    const TAG_INT_MARKER: u64 = SIGN_BIT | QNAN;
    return (val & TAG_INT_MARKER) == TAG_INT_MARKER;
}

/// 快速提取整数值
pub inline fn quickExtractInt(val: u64) i64 {
    const INT48_MASK: u64 = 0x0000FFFFFFFFFFFF;
    const INT48_SIGN_BIT: u64 = 0x0000800000000000;

    const raw = val & INT48_MASK;
    if ((raw & INT48_SIGN_BIT) != 0) {
        return @bitCast(raw | 0xFFFF000000000000);
    }
    return @bitCast(raw);
}

/// 快速整数运算（两个 NaN-boxed 整数相加）
pub inline fn quickIntAddValues(a: u64, b: u64) ?u64 {
    if (!isQuickInt(a) or !isQuickInt(b)) return null;

    const a_int = quickExtractInt(a);
    const b_int = quickExtractInt(b);

    if (fastIntAdd(a_int, b_int)) |result| {
        return small_int_cache.get(result) orelse SmallIntCache.encodeInt(result);
    }
    return null;
}

// ============================================================================
// 测试
// ============================================================================

test "SmallIntCache initialization" {
    try std.testing.expect(small_int_cache.initialized);
    try std.testing.expect(small_int_cache.get(0) != null);
    try std.testing.expect(small_int_cache.get(-128) != null);
    try std.testing.expect(small_int_cache.get(127) != null);
    try std.testing.expect(small_int_cache.get(128) == null);
    try std.testing.expect(small_int_cache.get(-129) == null);
}

test "SmallIntCache.isSmallInt" {
    try std.testing.expect(SmallIntCache.isSmallInt(0));
    try std.testing.expect(SmallIntCache.isSmallInt(-128));
    try std.testing.expect(SmallIntCache.isSmallInt(127));
    try std.testing.expect(!SmallIntCache.isSmallInt(128));
    try std.testing.expect(!SmallIntCache.isSmallInt(-129));
}

test "StringPool basic operations" {
    const allocator = std.testing.allocator;
    var pool = StringPool.init(allocator);
    defer pool.deinit();

    const s1 = try pool.intern("hello");
    const s2 = try pool.intern("hello");
    const s3 = try pool.intern("world");

    try std.testing.expectEqual(s1.ptr, s2.ptr);
    try std.testing.expect(s1.ptr != s3.ptr);
    try std.testing.expectEqual(@as(usize, 2), pool.size());
}

test "StringPool stats" {
    const allocator = std.testing.allocator;
    var pool = StringPool.init(allocator);
    defer pool.deinit();

    _ = try pool.intern("test");
    _ = try pool.intern("test");
    _ = try pool.intern("test");

    const stats = pool.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.misses);
    try std.testing.expectEqual(@as(u64, 2), stats.hits);
}

test "fastIntAdd overflow" {
    try std.testing.expectEqual(@as(?i64, 3), fastIntAdd(1, 2));
    try std.testing.expectEqual(@as(?i64, 0), fastIntAdd(-1, 1));
    try std.testing.expectEqual(@as(?i64, null), fastIntAdd(std.math.maxInt(i64), 1));
}

test "fastIntSub overflow" {
    try std.testing.expectEqual(@as(?i64, -1), fastIntSub(1, 2));
    try std.testing.expectEqual(@as(?i64, null), fastIntSub(std.math.minInt(i64), 1));
}

test "fastIntMul overflow" {
    try std.testing.expectEqual(@as(?i64, 6), fastIntMul(2, 3));
    try std.testing.expectEqual(@as(?i64, null), fastIntMul(std.math.maxInt(i64), 2));
}

test "fastIntDiv" {
    try std.testing.expectEqual(@as(?i64, 2), fastIntDiv(6, 3));
    try std.testing.expectEqual(@as(?i64, null), fastIntDiv(1, 0));
}

test "fastStringCompare" {
    try std.testing.expect(fastStringCompare("hello", "hello"));
    try std.testing.expect(!fastStringCompare("hello", "world"));
    try std.testing.expect(!fastStringCompare("hello", "hell"));
}

test "fastBoundsCheck" {
    try std.testing.expectEqual(@as(?usize, 0), fastBoundsCheck(0, 5));
    try std.testing.expectEqual(@as(?usize, 4), fastBoundsCheck(-1, 5));
    try std.testing.expectEqual(@as(?usize, null), fastBoundsCheck(5, 5));
    try std.testing.expectEqual(@as(?usize, null), fastBoundsCheck(-6, 5));
}

test "isQuickInt and quickExtractInt" {
    const encoded_zero = small_int_cache.get(0).?;
    try std.testing.expect(isQuickInt(encoded_zero));
    try std.testing.expectEqual(@as(i64, 0), quickExtractInt(encoded_zero));

    const encoded_neg = small_int_cache.get(-1).?;
    try std.testing.expect(isQuickInt(encoded_neg));
    try std.testing.expectEqual(@as(i64, -1), quickExtractInt(encoded_neg));
}

test "quickIntAddValues" {
    const a = small_int_cache.get(10).?;
    const b = small_int_cache.get(20).?;
    const result = quickIntAddValues(a, b);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 30), quickExtractInt(result.?));
}
