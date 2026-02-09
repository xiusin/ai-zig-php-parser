const std = @import("std");

/// SIMD 加速的字符串操作
pub const SimdString = struct {
    /// 使用 SIMD 查找字符
    pub fn findChar(haystack: []const u8, needle: u8) ?usize {
        const vec_size = 16; // SSE: 128 位 = 16 字节
        var i: usize = 0;

        // SIMD 处理对齐部分
        while (i + vec_size <= haystack.len) : (i += vec_size) {
            const chunk: @Vector(vec_size, u8) = haystack[i..][0..vec_size].*;
            const needle_vec: @Vector(vec_size, u8) = @splat(needle);
            const mask = chunk == needle_vec;

            if (@reduce(.Or, mask)) {
                // 找到匹配，精确定位
                for (0..vec_size) |j| {
                    if (mask[j]) return i + j;
                }
            }
        }

        // 处理剩余部分
        while (i < haystack.len) : (i += 1) {
            if (haystack[i] == needle) return i;
        }

        return null;
    }

    /// 使用 SIMD 比较字符串
    pub fn compare(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;

        const vec_size = 16;
        var i: usize = 0;

        while (i + vec_size <= a.len) : (i += vec_size) {
            const va: @Vector(vec_size, u8) = a[i..][0..vec_size].*;
            const vb: @Vector(vec_size, u8) = b[i..][0..vec_size].*;
            if (!@reduce(.And, va == vb)) return false;
        }

        while (i < a.len) : (i += 1) {
            if (a[i] != b[i]) return false;
        }

        return true;
    }
};

/// SIMD 加速的数组操作
pub const SimdArray = struct {
    /// 使用 SIMD 求和
    pub fn sum(arr: []const i32) i64 {
        const vec_size = 4; // SSE: 128 位 = 4 个 i32
        var result: i64 = 0;
        var i: usize = 0;

        var acc: @Vector(vec_size, i32) = @splat(0);

        while (i + vec_size <= arr.len) : (i += vec_size) {
            const chunk: @Vector(vec_size, i32) = arr[i..][0..vec_size].*;
            acc += chunk;
        }

        // 归约向量
        for (0..vec_size) |j| {
            result += acc[j];
        }

        // 处理剩余元素
        while (i < arr.len) : (i += 1) {
            result += arr[i];
        }

        return result;
    }

    /// 使用 SIMD 映射
    pub fn map(arr: []const i32, result: []i32, factor: i32) void {
        const vec_size = 4;
        var i: usize = 0;

        const factor_vec: @Vector(vec_size, i32) = @splat(factor);

        while (i + vec_size <= arr.len) : (i += vec_size) {
            const chunk: @Vector(vec_size, i32) = arr[i..][0..vec_size].*;
            const mapped = chunk * factor_vec;
            result[i..][0..vec_size].* = mapped;
        }

        while (i < arr.len) : (i += 1) {
            result[i] = arr[i] * factor;
        }
    }
};
