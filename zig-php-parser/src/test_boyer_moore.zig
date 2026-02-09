const std = @import("std");
const testing = std.testing;
const BoyerMoore = @import("algorithms/boyer_moore.zig").BoyerMoore;

// Feature: advanced-compiler-optimization, Property 34: 字符串搜索正确性
test "boyer-moore search correctness - same results as naive search" {
    const allocator = testing.allocator;

    const test_cases = [_]struct {
        text: []const u8,
        pattern: []const u8,
        expected: ?usize,
    }{
        .{ .text = "hello world", .pattern = "world", .expected = 6 },
        .{ .text = "hello world", .pattern = "hello", .expected = 0 },
        .{ .text = "hello world", .pattern = "xyz", .expected = null },
        .{ .text = "aaaaaaa", .pattern = "aaa", .expected = 0 },
        .{ .text = "abcdefg", .pattern = "cde", .expected = 2 },
    };

    for (test_cases) |case| {
        var bm = try BoyerMoore.init(allocator, case.pattern);
        defer bm.deinit();

        const result = bm.search(case.text);
        try testing.expectEqual(case.expected, result);
    }
}

// 测试空模式
test "boyer-moore empty pattern" {
    const allocator = testing.allocator;
    var bm = try BoyerMoore.init(allocator, "");
    defer bm.deinit();

    const result = bm.search("hello");
    try testing.expectEqual(@as(?usize, 0), result);
}

// 测试模式长于文本
test "boyer-moore pattern longer than text" {
    const allocator = testing.allocator;
    var bm = try BoyerMoore.init(allocator, "hello world");
    defer bm.deinit();

    const result = bm.search("hello");
    try testing.expectEqual(@as(?usize, null), result);
}

// 测试多次搜索
test "boyer-moore multiple searches" {
    const allocator = testing.allocator;
    var bm = try BoyerMoore.init(allocator, "test");
    defer bm.deinit();

    try testing.expectEqual(@as(?usize, 0), bm.search("test"));
    try testing.expectEqual(@as(?usize, 5), bm.search("this test works"));
    try testing.expectEqual(@as(?usize, null), bm.search("no match"));
}

// 测试单字符模式
test "boyer-moore single character pattern" {
    const allocator = testing.allocator;
    var bm = try BoyerMoore.init(allocator, "x");
    defer bm.deinit();

    try testing.expectEqual(@as(?usize, 2), bm.search("abxyz"));
}
