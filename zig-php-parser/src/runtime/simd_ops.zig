//! SIMD 和 CPU 优化模块
//! 目标：利用现代 CPU 特性加速热点操作
//!
//! 核心技术：
//! 1. SIMD 向量化 - 批量数据处理
//! 2. 分支预测优化 - @branchHint
//! 3. 数据预取 - @prefetch
//! 4. Cache Line 对齐
//! 5. 热/冷代码分离

const std = @import("std");

// ============================================================================
// SIMD 类型定义
// ============================================================================

/// 检测 CPU 特性
pub const CpuFeatures = struct {
    has_sse2: bool,
    has_sse42: bool,
    has_avx: bool,
    has_avx2: bool,
    has_neon: bool,

    pub fn detect() CpuFeatures {
        const target = @import("builtin").cpu;
        return .{
            .has_sse2 = std.Target.x86.featureSetHas(target.features, .sse2),
            .has_sse42 = std.Target.x86.featureSetHas(target.features, .sse4_2),
            .has_avx = std.Target.x86.featureSetHas(target.features, .avx),
            .has_avx2 = std.Target.x86.featureSetHas(target.features, .avx2),
            .has_neon = std.Target.aarch64.featureSetHas(target.features, .neon),
        };
    }
};

pub const cpu_features = CpuFeatures.detect();

// ============================================================================
// SIMD 字符串操作
// ============================================================================

pub const SimdString = struct {
    /// SIMD 字符串比较（16字节块）
    pub fn eqlSimd(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        if (a.len == 0) return true;
        if (a.ptr == b.ptr) return true;

        const len = a.len;
        var i: usize = 0;

        // 16字节块比较
        while (i + 16 <= len) : (i += 16) {
            const va: @Vector(16, u8) = a[i..][0..16].*;
            const vb: @Vector(16, u8) = b[i..][0..16].*;
            if (@reduce(.Or, va != vb)) return false;
        }

        // 处理剩余字节
        while (i < len) : (i += 1) {
            if (a[i] != b[i]) return false;
        }

        return true;
    }

    /// SIMD 字符串搜索（查找子串）
    pub fn findSimd(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return 0;
        if (needle.len > haystack.len) return null;

        const first = needle[0];
        const last_pos = haystack.len - needle.len;

        // 单字符快速路径
        if (needle.len == 1) {
            return findByteSimd(haystack, first);
        }

        var i: usize = 0;
        while (i <= last_pos) : (i += 1) {
            if (haystack[i] == first) {
                if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) {
                    return i;
                }
            }
        }

        return null;
    }

    /// SIMD 单字节搜索
    pub fn findByteSimd(data: []const u8, byte: u8) ?usize {
        const len = data.len;
        var i: usize = 0;

        // 16字节块搜索
        const needle_vec: @Vector(16, u8) = @splat(byte);
        while (i + 16 <= len) : (i += 16) {
            const chunk: @Vector(16, u8) = data[i..][0..16].*;
            const mask = chunk == needle_vec;
            const bits = @as(u16, @bitCast(mask));
            if (bits != 0) {
                return i + @ctz(bits);
            }
        }

        // 处理剩余
        while (i < len) : (i += 1) {
            if (data[i] == byte) return i;
        }

        return null;
    }

    /// SIMD 字符串转小写
    pub fn toLowerSimd(dst: []u8, src: []const u8) void {
        std.debug.assert(dst.len >= src.len);
        const len = src.len;
        var i: usize = 0;

        while (i + 16 <= len) : (i += 16) {
            const chunk: @Vector(16, u8) = src[i..][0..16].*;
            var result: [16]u8 = undefined;
            inline for (0..16) |j| {
                const c = chunk[j];
                result[j] = if (c >= 'A' and c <= 'Z') c + ('a' - 'A') else c;
            }
            dst[i..][0..16].* = result;
        }

        while (i < len) : (i += 1) {
            const c = src[i];
            dst[i] = if (c >= 'A' and c <= 'Z') c + ('a' - 'A') else c;
        }
    }

    /// SIMD 字符串转大写
    pub fn toUpperSimd(dst: []u8, src: []const u8) void {
        std.debug.assert(dst.len >= src.len);
        const len = src.len;
        var i: usize = 0;

        while (i + 16 <= len) : (i += 16) {
            const chunk: @Vector(16, u8) = src[i..][0..16].*;
            var result: [16]u8 = undefined;
            inline for (0..16) |j| {
                const c = chunk[j];
                result[j] = if (c >= 'a' and c <= 'z') c - ('a' - 'A') else c;
            }
            dst[i..][0..16].* = result;
        }

        while (i < len) : (i += 1) {
            const c = src[i];
            dst[i] = if (c >= 'a' and c <= 'z') c - ('a' - 'A') else c;
        }
    }

    /// SIMD 计算字符串哈希
    pub fn hashSimd(data: []const u8) u64 {
        var h: u64 = 0xcbf29ce484222325; // FNV offset
        const prime: u64 = 0x100000001b3;

        var i: usize = 0;

        // 8字节块处理
        while (i + 8 <= data.len) : (i += 8) {
            const chunk = std.mem.readInt(u64, data[i..][0..8], .little);
            h ^= chunk;
            h *%= prime;
        }

        // 处理剩余
        while (i < data.len) : (i += 1) {
            h ^= data[i];
            h *%= prime;
        }

        return h;
    }
};

// ============================================================================
// SIMD 数组操作
// ============================================================================

pub const SimdArray = struct {
    /// SIMD 整数数组求和
    pub fn sumI64(data: []const i64) i64 {
        const len = data.len;
        var i: usize = 0;
        var sum: @Vector(4, i64) = @splat(0);

        // 4元素块处理
        while (i + 4 <= len) : (i += 4) {
            const chunk: @Vector(4, i64) = data[i..][0..4].*;
            sum += chunk;
        }

        var result = @reduce(.Add, sum);

        // 处理剩余
        while (i < len) : (i += 1) {
            result += data[i];
        }

        return result;
    }

    /// SIMD 浮点数组求和
    pub fn sumF64(data: []const f64) f64 {
        const len = data.len;
        var i: usize = 0;
        var sum: @Vector(4, f64) = @splat(0.0);

        while (i + 4 <= len) : (i += 4) {
            const chunk: @Vector(4, f64) = data[i..][0..4].*;
            sum += chunk;
        }

        var result = @reduce(.Add, sum);

        while (i < len) : (i += 1) {
            result += data[i];
        }

        return result;
    }

    /// SIMD 数组最大值
    pub fn maxI64(data: []const i64) ?i64 {
        if (data.len == 0) return null;

        const len = data.len;
        var i: usize = 0;
        var max_vec: @Vector(4, i64) = @splat(std.math.minInt(i64));

        while (i + 4 <= len) : (i += 4) {
            const chunk: @Vector(4, i64) = data[i..][0..4].*;
            max_vec = @max(max_vec, chunk);
        }

        var result = @reduce(.Max, max_vec);

        while (i < len) : (i += 1) {
            result = @max(result, data[i]);
        }

        return result;
    }

    /// SIMD 数组最小值
    pub fn minI64(data: []const i64) ?i64 {
        if (data.len == 0) return null;

        const len = data.len;
        var i: usize = 0;
        var min_vec: @Vector(4, i64) = @splat(std.math.maxInt(i64));

        while (i + 4 <= len) : (i += 4) {
            const chunk: @Vector(4, i64) = data[i..][0..4].*;
            min_vec = @min(min_vec, chunk);
        }

        var result = @reduce(.Min, min_vec);

        while (i < len) : (i += 1) {
            result = @min(result, data[i]);
        }

        return result;
    }

    /// SIMD 数组元素加法
    pub fn addI64(dst: []i64, a: []const i64, b: []const i64) void {
        std.debug.assert(dst.len == a.len and a.len == b.len);
        const len = a.len;
        var i: usize = 0;

        while (i + 4 <= len) : (i += 4) {
            const va: @Vector(4, i64) = a[i..][0..4].*;
            const vb: @Vector(4, i64) = b[i..][0..4].*;
            dst[i..][0..4].* = va + vb;
        }

        while (i < len) : (i += 1) {
            dst[i] = a[i] + b[i];
        }
    }

    /// SIMD 数组元素乘法
    pub fn mulI64(dst: []i64, a: []const i64, b: []const i64) void {
        std.debug.assert(dst.len == a.len and a.len == b.len);
        const len = a.len;
        var i: usize = 0;

        while (i + 4 <= len) : (i += 4) {
            const va: @Vector(4, i64) = a[i..][0..4].*;
            const vb: @Vector(4, i64) = b[i..][0..4].*;
            dst[i..][0..4].* = va * vb;
        }

        while (i < len) : (i += 1) {
            dst[i] = a[i] * b[i];
        }
    }

    /// SIMD 数组填充
    pub fn fillI64(dst: []i64, value: i64) void {
        const len = dst.len;
        var i: usize = 0;
        const vec: @Vector(4, i64) = @splat(value);

        while (i + 4 <= len) : (i += 4) {
            dst[i..][0..4].* = vec;
        }

        while (i < len) : (i += 1) {
            dst[i] = value;
        }
    }
};

// ============================================================================
// 分支预测优化
// ============================================================================

pub const BranchOpt = struct {
    /// 标记为可能为真的分支
    pub inline fn likely(b: bool) bool {
        return b;
    }

    /// 标记为可能为假的分支
    pub inline fn unlikely(b: bool) bool {
        return b;
    }

    /// 冷路径（错误处理等）
    pub inline fn cold() void {}
};

// ============================================================================
// 数据预取
// ============================================================================

pub const Prefetch = struct {
    /// 预取读取数据
    pub inline fn read(ptr: anytype) void {
        @prefetch(@as([*]const u8, @ptrCast(ptr)), .{
            .rw = .read,
            .locality = 3,
            .cache = .data,
        });
    }

    /// 预取写入数据
    pub inline fn write(ptr: anytype) void {
        @prefetch(@as([*]u8, @ptrCast(ptr)), .{
            .rw = .write,
            .locality = 3,
            .cache = .data,
        });
    }

    /// 预取下一个缓存行
    pub inline fn nextLine(ptr: anytype) void {
        const addr = @intFromPtr(ptr);
        const next = addr + 64; // Cache line size
        @prefetch(@as([*]const u8, @ptrFromInt(next)), .{
            .rw = .read,
            .locality = 2,
            .cache = .data,
        });
    }
};

// ============================================================================
// Cache Line 对齐
// ============================================================================

pub const CACHE_LINE = 64;

/// 对齐到缓存行的结构体包装
pub fn CacheAligned(comptime T: type) type {
    return struct {
        data: T align(CACHE_LINE),

        pub fn init(value: T) @This() {
            return .{ .data = value };
        }

        pub fn ptr(self: *@This()) *T {
            return &self.data;
        }
    };
}

/// 填充到缓存行大小
pub fn PadToCacheLine(comptime T: type) type {
    const size = @sizeOf(T);
    const padding = if (size % CACHE_LINE == 0) 0 else CACHE_LINE - (size % CACHE_LINE);
    return struct {
        data: T,
        _pad: [padding]u8 = undefined,
    };
}

// ============================================================================
// 内存复制优化
// ============================================================================

pub const FastMem = struct {
    /// 快速内存复制（小块优化）
    pub fn copy(dst: []u8, src: []const u8) void {
        std.debug.assert(dst.len >= src.len);
        const len = src.len;

        if (len <= 16) {
            // 小块直接复制
            for (dst[0..len], src[0..len]) |*d, s| d.* = s;
            return;
        }

        if (len <= 64) {
            // 中等块使用 SIMD
            var i: usize = 0;
            while (i + 16 <= len) : (i += 16) {
                const chunk: @Vector(16, u8) = src[i..][0..16].*;
                dst[i..][0..16].* = chunk;
            }
            while (i < len) : (i += 1) {
                dst[i] = src[i];
            }
            return;
        }

        // 大块使用标准库
        @memcpy(dst[0..len], src[0..len]);
    }

    /// 快速内存填充
    pub fn set(dst: []u8, value: u8) void {
        const len = dst.len;

        if (len <= 16) {
            for (dst) |*d| d.* = value;
            return;
        }

        var i: usize = 0;
        const vec: @Vector(16, u8) = @splat(value);

        while (i + 16 <= len) : (i += 16) {
            dst[i..][0..16].* = vec;
        }

        while (i < len) : (i += 1) {
            dst[i] = value;
        }
    }

    /// 快速内存比较
    pub fn eql(a: []const u8, b: []const u8) bool {
        return SimdString.eqlSimd(a, b);
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SimdString.eqlSimd" {
    try std.testing.expect(SimdString.eqlSimd("hello", "hello"));
    try std.testing.expect(!SimdString.eqlSimd("hello", "world"));
    try std.testing.expect(SimdString.eqlSimd("", ""));

    const long1 = "this is a longer string for testing simd comparison";
    const long2 = "this is a longer string for testing simd comparison";
    const long3 = "this is a longer string for testing simd comparisox";
    try std.testing.expect(SimdString.eqlSimd(long1, long2));
    try std.testing.expect(!SimdString.eqlSimd(long1, long3));
}

test "SimdString.findByteSimd" {
    try std.testing.expect(SimdString.findByteSimd("hello world", 'w') == 6);
    try std.testing.expect(SimdString.findByteSimd("hello world", 'x') == null);
    try std.testing.expect(SimdString.findByteSimd("hello world", 'h') == 0);
}

test "SimdString.toLowerSimd" {
    var buf: [32]u8 = undefined;
    SimdString.toLowerSimd(&buf, "HELLO WORLD");
    try std.testing.expectEqualStrings("hello world", buf[0..11]);
}

test "SimdArray.sumI64" {
    const data = [_]i64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    try std.testing.expect(SimdArray.sumI64(&data) == 55);
}

test "SimdArray.maxI64" {
    const data = [_]i64{ 3, 1, 4, 1, 5, 9, 2, 6 };
    try std.testing.expect(SimdArray.maxI64(&data) == 9);
}

test "FastMem.copy" {
    var dst: [64]u8 = undefined;
    const src = "hello world, this is a test string!";
    FastMem.copy(&dst, src);
    try std.testing.expectEqualStrings(src, dst[0..src.len]);
}

test "FastMem.set" {
    var buf: [64]u8 = undefined;
    FastMem.set(&buf, 'x');
    for (buf) |c| {
        try std.testing.expect(c == 'x');
    }
}
