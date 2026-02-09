const std = @import("std");
const testing = std.testing;
const simd = @import("runtime/simd.zig");
const SimdString = simd.SimdString;
const SimdArray = simd.SimdArray;

// Feature: advanced-compiler-optimization, Property 18: SIMD 字符串操作正确性
test "SIMD string operations - correct results" {
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // 测试字符查找
        const haystack = "Hello, World!";
        const pos = SimdString.findChar(haystack, 'W');
        try testing.expect(pos != null);
        try testing.expect(pos.? == 7);

        // 测试未找到
        const not_found = SimdString.findChar(haystack, 'X');
        try testing.expect(not_found == null);

        // 测试字符串比较
        const str1 = "Hello";
        const str2 = "Hello";
        const str3 = "World";
        try testing.expect(SimdString.compare(str1, str2));
        try testing.expect(!SimdString.compare(str1, str3));
    }
}

// Feature: advanced-compiler-optimization, Property 19: SIMD 数组操作正确性
test "SIMD array operations - correct results" {
    const allocator = testing.allocator;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // 测试数组求和
        const arr = [_]i32{ 1, 2, 3, 4, 5 };
        const sum = SimdArray.sum(&arr);
        try testing.expect(sum == 15);

        // 测试数组映射
        const result = try allocator.alloc(i32, arr.len);
        defer allocator.free(result);

        SimdArray.map(&arr, result, 2);
        try testing.expect(result[0] == 2);
        try testing.expect(result[1] == 4);
        try testing.expect(result[2] == 6);
        try testing.expect(result[3] == 8);
        try testing.expect(result[4] == 10);
    }
}

// 测试长字符串查找
test "SIMD string find - long strings" {
    const haystack = "a" ** 100 ++ "b" ++ "a" ** 100;
    const pos = SimdString.findChar(haystack, 'b');
    try testing.expect(pos != null);
    try testing.expect(pos.? == 100);
}

// 测试空数组
test "SIMD array sum - empty array" {
    const arr = [_]i32{};
    const sum = SimdArray.sum(&arr);
    try testing.expect(sum == 0);
}

// 测试负数
test "SIMD array operations - negative numbers" {
    const arr = [_]i32{ -1, -2, -3, -4, -5 };
    const sum = SimdArray.sum(&arr);
    try testing.expect(sum == -15);
}
