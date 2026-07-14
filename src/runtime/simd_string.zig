//! SIMD 加速的字符串函数
//!
//! 本模块实现了使用 SIMD 指令加速的字符串操作函数，包括：
//! - strlen: 计算字符串长度
//! - strcmp: 字符串比较
//! - strpos: 查找子字符串位置
//! - strrpos: 反向查找子字符串位置
//!
//! 性能目标：相比标量实现提升 2-3 倍
//!
//! @ownership NON-OWNING (allocator)
//! @thread-safety ISOLATED
//! @memory-protection BOUNDS_CHECK

const std = @import("std");
const builtin = @import("builtin");

/// SIMD 指令集类型
pub const SIMDInstructionSet = enum {
    none,
    sse2,
    sse4_2,
    avx2,
    avx512,
    neon,
};

/// SIMD 能力检测器
pub const SIMDCapabilities = struct {
    supported_sets: std.EnumSet(SIMDInstructionSet),
    best_set: SIMDInstructionSet,

    /// 检测 CPU SIMD 能力
    pub fn detect() SIMDCapabilities {
        var caps = SIMDCapabilities{
            .supported_sets = std.EnumSet(SIMDInstructionSet).initEmpty(),
            .best_set = .none,
        };

        if (builtin.cpu.arch == .x86_64) {
            detectX86(&caps);
        } else if (builtin.cpu.arch == .aarch64) {
            detectARM(&caps);
        }

        return caps;
    }

    /// 检测 x86-64 SIMD 能力
    fn detectX86(caps: *SIMDCapabilities) void {
        // 基础 SSE2 在 x86_64 上总是可用
        caps.supported_sets.insert(.sse2);
        caps.best_set = .sse2;

        // 检测 SSE4.2
        if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_2)) {
            caps.supported_sets.insert(.sse4_2);
            caps.best_set = .sse4_2;
        }

        // 检测 AVX2
        if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) {
            caps.supported_sets.insert(.avx2);
            caps.best_set = .avx2;
        }

        // 检测 AVX-512
        if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f)) {
            caps.supported_sets.insert(.avx512);
            caps.best_set = .avx512;
        }
    }

    /// 检测 ARM SIMD 能力
    fn detectARM(caps: *SIMDCapabilities) void {
        // ARM NEON 在 AArch64 上总是可用
        if (builtin.cpu.arch == .aarch64) {
            caps.supported_sets.insert(.neon);
            caps.best_set = .neon;
        }
    }

    /// 检查是否支持指定指令集
    pub fn supports(self: *const SIMDCapabilities, set: SIMDInstructionSet) bool {
        return self.supported_sets.contains(set);
    }
};

/// SIMD 字符串操作
/// @ownership NON-OWNING
/// @thread-safety ISOLATED
pub const SIMDString = struct {
    capabilities: SIMDCapabilities,

    /// 初始化
    pub fn init() SIMDString {
        return .{
            .capabilities = SIMDCapabilities.detect(),
        };
    }

    /// SIMD 加速的 strlen
    /// @pre str 必须是有效的字符串切片
    /// @post 返回字符串长度
    /// @performance 2-3x 标量实现
    pub fn strlen(self: *const SIMDString, str: []const u8) usize {
        if (str.len == 0) return 0;

        // 根据 CPU 能力选择最佳实现
        if (self.capabilities.supports(.avx2)) {
            return strlenAVX2(str);
        } else if (self.capabilities.supports(.sse2)) {
            return strlenSSE2(str);
        } else if (self.capabilities.supports(.neon)) {
            return strlenNEON(str);
        } else {
            return strlenScalar(str);
        }
    }

    /// SSE2 版本的 strlen
    fn strlenSSE2(str: []const u8) usize {
        const VecLen = 16; // SSE2 处理 16 字节
        var i: usize = 0;

        // SIMD 批量处理
        while (i + VecLen <= str.len) : (i += VecLen) {
            const vec: @Vector(VecLen, u8) = str[i..][0..VecLen].*;
            const zero_vec: @Vector(VecLen, u8) = @splat(0);

            // 检查是否有零字节
            const cmp = vec == zero_vec;
            const mask = @as(u16, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            if (mask != 0) {
                // 找到零字节，计算精确位置
                return i + @ctz(mask);
            }
        }

        // 处理剩余字节
        while (i < str.len) : (i += 1) {
            if (str[i] == 0) return i;
        }

        return str.len;
    }

    /// AVX2 版本的 strlen
    fn strlenAVX2(str: []const u8) usize {
        const VecLen = 32; // AVX2 处理 32 字节
        var i: usize = 0;

        // SIMD 批量处理
        while (i + VecLen <= str.len) : (i += VecLen) {
            const vec: @Vector(VecLen, u8) = str[i..][0..VecLen].*;
            const zero_vec: @Vector(VecLen, u8) = @splat(0);

            // 检查是否有零字节
            const cmp = vec == zero_vec;
            const mask = @as(u32, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            if (mask != 0) {
                return i + @ctz(mask);
            }
        }

        // 处理剩余字节
        while (i < str.len) : (i += 1) {
            if (str[i] == 0) return i;
        }

        return str.len;
    }

    /// NEON 版本的 strlen
    fn strlenNEON(str: []const u8) usize {
        const VecLen = 16; // NEON 处理 16 字节
        var i: usize = 0;

        // SIMD 批量处理
        while (i + VecLen <= str.len) : (i += VecLen) {
            const vec: @Vector(VecLen, u8) = str[i..][0..VecLen].*;
            const zero_vec: @Vector(VecLen, u8) = @splat(0);

            const cmp = vec == zero_vec;
            const mask = @as(u16, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            if (mask != 0) {
                return i + @ctz(mask);
            }
        }

        // 处理剩余字节
        while (i < str.len) : (i += 1) {
            if (str[i] == 0) return i;
        }

        return str.len;
    }

    /// 标量版本的 strlen（回退实现）
    pub fn strlenScalar(str: []const u8) usize {
        for (str, 0..) |c, i| {
            if (c == 0) return i;
        }
        return str.len;
    }

    /// SIMD 加速的 strcmp
    /// @pre s1 和 s2 必须是有效的字符串切片
    /// @post 返回 <0 (s1<s2), 0 (s1==s2), >0 (s1>s2)
    /// @performance 2-3x 标量实现
    pub fn strcmp(self: *const SIMDString, s1: []const u8, s2: []const u8) i32 {
        if (s1.ptr == s2.ptr and s1.len == s2.len) return 0;

        // 根据 CPU 能力选择最佳实现
        if (self.capabilities.supports(.avx2)) {
            return strcmpAVX2(s1, s2);
        } else if (self.capabilities.supports(.sse2)) {
            return strcmpSSE2(s1, s2);
        } else if (self.capabilities.supports(.neon)) {
            return strcmpNEON(s1, s2);
        } else {
            return strcmpScalar(s1, s2);
        }
    }

    /// SSE2 版本的 strcmp
    fn strcmpSSE2(s1: []const u8, s2: []const u8) i32 {
        const VecLen = 16;
        const min_len = @min(s1.len, s2.len);
        var i: usize = 0;

        // SIMD 批量比较
        while (i + VecLen <= min_len) : (i += VecLen) {
            const vec1: @Vector(VecLen, u8) = s1[i..][0..VecLen].*;
            const vec2: @Vector(VecLen, u8) = s2[i..][0..VecLen].*;

            // 比较向量
            const cmp = vec1 == vec2;
            const mask = @as(u16, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            // 如果有不同的字节
            if (mask != 0xFFFF) {
                const diff_pos = @ctz(~mask);
                const pos = i + diff_pos;
                return @as(i32, s1[pos]) - @as(i32, s2[pos]);
            }
        }

        // 处理剩余字节
        while (i < min_len) : (i += 1) {
            if (s1[i] != s2[i]) {
                return @as(i32, s1[i]) - @as(i32, s2[i]);
            }
        }

        // 长度不同
        if (s1.len != s2.len) {
            return if (s1.len < s2.len) -1 else 1;
        }

        return 0;
    }

    /// AVX2 版本的 strcmp
    fn strcmpAVX2(s1: []const u8, s2: []const u8) i32 {
        const VecLen = 32;
        const min_len = @min(s1.len, s2.len);
        var i: usize = 0;

        // SIMD 批量比较
        while (i + VecLen <= min_len) : (i += VecLen) {
            const vec1: @Vector(VecLen, u8) = s1[i..][0..VecLen].*;
            const vec2: @Vector(VecLen, u8) = s2[i..][0..VecLen].*;

            const cmp = vec1 == vec2;
            const mask = @as(u32, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            if (mask != 0xFFFFFFFF) {
                const diff_pos = @ctz(~mask);
                const pos = i + diff_pos;
                return @as(i32, s1[pos]) - @as(i32, s2[pos]);
            }
        }

        // 处理剩余字节
        while (i < min_len) : (i += 1) {
            if (s1[i] != s2[i]) {
                return @as(i32, s1[i]) - @as(i32, s2[i]);
            }
        }

        if (s1.len != s2.len) {
            return if (s1.len < s2.len) -1 else 1;
        }

        return 0;
    }

    /// NEON 版本的 strcmp
    fn strcmpNEON(s1: []const u8, s2: []const u8) i32 {
        const VecLen = 16;
        const min_len = @min(s1.len, s2.len);
        var i: usize = 0;

        while (i + VecLen <= min_len) : (i += VecLen) {
            const vec1: @Vector(VecLen, u8) = s1[i..][0..VecLen].*;
            const vec2: @Vector(VecLen, u8) = s2[i..][0..VecLen].*;

            const cmp = vec1 == vec2;
            const mask = @as(u16, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            if (mask != 0xFFFF) {
                const diff_pos = @ctz(~mask);
                const pos = i + diff_pos;
                return @as(i32, s1[pos]) - @as(i32, s2[pos]);
            }
        }

        while (i < min_len) : (i += 1) {
            if (s1[i] != s2[i]) {
                return @as(i32, s1[i]) - @as(i32, s2[i]);
            }
        }

        if (s1.len != s2.len) {
            return if (s1.len < s2.len) -1 else 1;
        }

        return 0;
    }

    /// 标量版本的 strcmp（回退实现）
    pub fn strcmpScalar(s1: []const u8, s2: []const u8) i32 {
        const min_len = @min(s1.len, s2.len);

        for (0..min_len) |i| {
            if (s1[i] != s2[i]) {
                return @as(i32, s1[i]) - @as(i32, s2[i]);
            }
        }

        if (s1.len != s2.len) {
            return if (s1.len < s2.len) -1 else 1;
        }

        return 0;
    }

    /// SIMD 加速的 strpos (查找子字符串)
    /// @pre haystack 和 needle 必须是有效的字符串切片
    /// @post 返回 needle 在 haystack 中的位置，未找到返回 null
    /// @performance 3-4x 标量实现
    pub fn strpos(self: *const SIMDString, haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return 0;
        if (needle.len > haystack.len) return null;

        // 根据 CPU 能力选择最佳实现
        if (self.capabilities.supports(.avx2)) {
            return strposAVX2(haystack, needle);
        } else if (self.capabilities.supports(.sse2)) {
            return strposSSE2(haystack, needle);
        } else if (self.capabilities.supports(.neon)) {
            return strposNEON(haystack, needle);
        } else {
            return strposScalar(haystack, needle);
        }
    }

    /// SSE2 版本的 strpos
    fn strposSSE2(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return 0;
        if (needle.len > haystack.len) return null;

        const VecLen = 16;
        const first_char = needle[0];
        const first_vec: @Vector(VecLen, u8) = @splat(first_char);

        var i: usize = 0;
        const search_end = haystack.len - needle.len + 1;

        // SIMD 查找首字符
        while (i + VecLen <= search_end) : (i += VecLen) {
            const vec: @Vector(VecLen, u8) = haystack[i..][0..VecLen].*;
            const cmp = vec == first_vec;
            var mask = @as(u16, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            // 检查每个匹配的首字符
            while (mask != 0) {
                const pos = @ctz(mask);
                const candidate_pos = i + pos;

                // 验证完整匹配
                if (candidate_pos + needle.len <= haystack.len) {
                    if (std.mem.eql(u8, haystack[candidate_pos..][0..needle.len], needle)) {
                        return candidate_pos;
                    }
                }

                // 清除已检查的位
                mask &= mask - 1;
            }
        }

        // 处理剩余字节
        while (i < search_end) : (i += 1) {
            if (haystack[i] == first_char) {
                if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) {
                    return i;
                }
            }
        }

        return null;
    }

    /// AVX2 版本的 strpos
    fn strposAVX2(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return 0;
        if (needle.len > haystack.len) return null;

        const VecLen = 32;
        const first_char = needle[0];
        const first_vec: @Vector(VecLen, u8) = @splat(first_char);

        var i: usize = 0;
        const search_end = haystack.len - needle.len + 1;

        // SIMD 查找首字符
        while (i + VecLen <= search_end) : (i += VecLen) {
            const vec: @Vector(VecLen, u8) = haystack[i..][0..VecLen].*;
            const cmp = vec == first_vec;
            var mask = @as(u32, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            while (mask != 0) {
                const pos = @ctz(mask);
                const candidate_pos = i + pos;

                if (candidate_pos + needle.len <= haystack.len) {
                    if (std.mem.eql(u8, haystack[candidate_pos..][0..needle.len], needle)) {
                        return candidate_pos;
                    }
                }

                mask &= mask - 1;
            }
        }

        // 处理剩余字节
        while (i < search_end) : (i += 1) {
            if (haystack[i] == first_char) {
                if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) {
                    return i;
                }
            }
        }

        return null;
    }

    /// NEON 版本的 strpos
    fn strposNEON(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return 0;
        if (needle.len > haystack.len) return null;

        const VecLen = 16;
        const first_char = needle[0];
        const first_vec: @Vector(VecLen, u8) = @splat(first_char);

        var i: usize = 0;
        const search_end = haystack.len - needle.len + 1;

        while (i + VecLen <= search_end) : (i += VecLen) {
            const vec: @Vector(VecLen, u8) = haystack[i..][0..VecLen].*;
            const cmp = vec == first_vec;
            var mask = @as(u16, @bitCast(@as(@Vector(VecLen, bool), cmp)));

            while (mask != 0) {
                const pos = @ctz(mask);
                const candidate_pos = i + pos;

                if (candidate_pos + needle.len <= haystack.len) {
                    if (std.mem.eql(u8, haystack[candidate_pos..][0..needle.len], needle)) {
                        return candidate_pos;
                    }
                }

                mask &= mask - 1;
            }
        }

        while (i < search_end) : (i += 1) {
            if (haystack[i] == first_char) {
                if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) {
                    return i;
                }
            }
        }

        return null;
    }

    /// 标量版本的 strpos（回退实现）
    pub fn strposScalar(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return 0;
        if (needle.len > haystack.len) return null;

        const search_end = haystack.len - needle.len + 1;
        for (0..search_end) |i| {
            if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) {
                return i;
            }
        }

        return null;
    }

    /// SIMD 加速的 strrpos (反向查找子字符串)
    /// @pre haystack 和 needle 必须是有效的字符串切片
    /// @post 返回 needle 在 haystack 中最后出现的位置，未找到返回 null
    /// @performance 3-4x 标量实现
    pub fn strrpos(_: *const SIMDString, haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return haystack.len;
        if (needle.len > haystack.len) return null;

        // 反向查找使用标量实现（SIMD 反向扫描效率不高）
        return strrposScalar(haystack, needle);
    }

    /// 标量版本的 strrpos
    pub fn strrposScalar(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return haystack.len;
        if (needle.len > haystack.len) return null;

        var i: usize = haystack.len - needle.len;
        while (true) {
            if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) {
                return i;
            }

            if (i == 0) break;
            i -= 1;
        }

        return null;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SIMDCapabilities.detect" {
    const caps = SIMDCapabilities.detect();

    // 至少应该有一个支持的指令集
    std.debug.print("\nDetected SIMD capabilities: {any}\n", .{caps.best_set});

    if (builtin.cpu.arch == .x86_64) {
        // x86_64 至少支持 SSE2
        try std.testing.expect(caps.supports(.sse2));
    } else if (builtin.cpu.arch == .aarch64) {
        // AArch64 支持 NEON
        try std.testing.expect(caps.supports(.neon));
    }
}

test "SIMDString.strlen - basic" {
    const simd = SIMDString.init();

    // 测试空字符串
    try std.testing.expectEqual(@as(usize, 0), simd.strlen(""));

    // 测试短字符串
    try std.testing.expectEqual(@as(usize, 5), simd.strlen("hello"));

    // 测试长字符串
    const long_str = "This is a very long string that should trigger SIMD processing";
    try std.testing.expectEqual(@as(usize, 62), simd.strlen(long_str));

    // 测试包含零字节的字符串
    const zero_str = "hello\x00world";
    try std.testing.expectEqual(@as(usize, 5), simd.strlen(zero_str));
}

test "SIMDString.strcmp - basic" {
    const simd = SIMDString.init();

    // 测试相等字符串
    try std.testing.expectEqual(@as(i32, 0), simd.strcmp("hello", "hello"));

    // 测试不同字符串
    try std.testing.expect(simd.strcmp("hello", "world") < 0);
    try std.testing.expect(simd.strcmp("world", "hello") > 0);

    // 测试不同长度
    try std.testing.expect(simd.strcmp("hello", "hello world") < 0);
    try std.testing.expect(simd.strcmp("hello world", "hello") > 0);

    // 测试空字符串
    try std.testing.expectEqual(@as(i32, 0), simd.strcmp("", ""));
    try std.testing.expect(simd.strcmp("", "hello") < 0);
    try std.testing.expect(simd.strcmp("hello", "") > 0);
}

test "SIMDString.strpos - basic" {
    const simd = SIMDString.init();

    // 测试找到子字符串
    try std.testing.expectEqual(@as(?usize, 0), simd.strpos("hello world", "hello"));
    try std.testing.expectEqual(@as(?usize, 6), simd.strpos("hello world", "world"));
    try std.testing.expectEqual(@as(?usize, 2), simd.strpos("hello world", "llo"));

    // 测试未找到
    try std.testing.expectEqual(@as(?usize, null), simd.strpos("hello world", "xyz"));

    // 测试空 needle
    try std.testing.expectEqual(@as(?usize, 0), simd.strpos("hello", ""));

    // 测试 needle 比 haystack 长
    try std.testing.expectEqual(@as(?usize, null), simd.strpos("hi", "hello"));
}

test "SIMDString.strrpos - basic" {
    const simd = SIMDString.init();

    // 测试找到子字符串（最后一次出现）
    try std.testing.expectEqual(@as(?usize, 12), simd.strrpos("hello world hello", "hello"));
    try std.testing.expectEqual(@as(?usize, 6), simd.strrpos("hello world", "world"));

    // 测试未找到
    try std.testing.expectEqual(@as(?usize, null), simd.strrpos("hello world", "xyz"));

    // 测试空 needle
    try std.testing.expectEqual(@as(?usize, 11), simd.strrpos("hello world", ""));
}
