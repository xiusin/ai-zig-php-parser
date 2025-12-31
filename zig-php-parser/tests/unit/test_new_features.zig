const std = @import("std");
const string_utils = @import("../../src/runtime/string_utils.zig");
const string_wrapper = @import("../../src/runtime/string_wrapper.zig");
const array_wrapper = @import("../../src/runtime/array_wrapper.zig");
const http_client = @import("../../src/runtime/http_client.zig");

/// 测试转义序列处理
test "escape sequence processing" {
    const allocator = std.testing.allocator;

    // 测试基本转义
    const result1 = try string_utils.processEscapeSequences(allocator, "hello\\nworld");
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("hello\nworld", result1);

    // 测试制表符
    const result2 = try string_utils.processEscapeSequences(allocator, "col1\\tcol2");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("col1\tcol2", result2);

    // 测试引号转义
    const result3 = try string_utils.processEscapeSequences(allocator, "say\\\"hello\\\"");
    defer allocator.free(result3);
    try std.testing.expectEqualStrings("say\"hello\"", result3);

    // 测试反斜杠转义
    const result4 = try string_utils.processEscapeSequences(allocator, "path\\\\to\\\\file");
    defer allocator.free(result4);
    try std.testing.expectEqualStrings("path\\to\\file", result4);

    // 测试回车换行
    const result5 = try string_utils.processEscapeSequences(allocator, "line1\\r\\nline2");
    defer allocator.free(result5);
    try std.testing.expectEqualStrings("line1\r\nline2", result5);
}

/// 测试StringWrapper链式操作
test "StringWrapper chaining" {
    const allocator = std.testing.allocator;

    var wrapper = try string_wrapper.StringWrapper.init(allocator, "  Hello World  ");
    defer wrapper.deinit();

    // 测试trim
    var trimmed = try wrapper.trim();
    defer trimmed.deinit();
    try std.testing.expectEqualStrings("Hello World", trimmed.data());

    // 测试toUpper
    var upper = try trimmed.toUpper();
    defer upper.deinit();
    try std.testing.expectEqualStrings("HELLO WORLD", upper.data());

    // 测试toLower
    var lower = try upper.toLower();
    defer lower.deinit();
    try std.testing.expectEqualStrings("hello world", lower.data());
}

/// 测试StringWrapper搜索功能
test "StringWrapper search" {
    const allocator = std.testing.allocator;

    var wrapper = try string_wrapper.StringWrapper.init(allocator, "hello world hello");
    defer wrapper.deinit();

    try std.testing.expectEqual(@as(i64, 0), wrapper.indexOf("hello"));
    try std.testing.expectEqual(@as(i64, 12), wrapper.lastIndexOf("hello"));
    try std.testing.expectEqual(@as(i64, -1), wrapper.indexOf("foo"));
    try std.testing.expect(wrapper.contains("world"));
    try std.testing.expect(!wrapper.contains("bar"));
    try std.testing.expect(wrapper.startsWith("hello"));
    try std.testing.expect(wrapper.endsWith("hello"));
}

/// 测试StringWrapper替换功能
test "StringWrapper replace" {
    const allocator = std.testing.allocator;

    var wrapper = try string_wrapper.StringWrapper.init(allocator, "hello world");
    defer wrapper.deinit();

    var replaced = try wrapper.replace("world", "zig");
    defer replaced.deinit();
    try std.testing.expectEqualStrings("hello zig", replaced.data());
}

/// 测试StringWrapper子串功能
test "StringWrapper substring" {
    const allocator = std.testing.allocator;

    var wrapper = try string_wrapper.StringWrapper.init(allocator, "hello world");
    defer wrapper.deinit();

    var sub1 = try wrapper.substring(0, 5);
    defer sub1.deinit();
    try std.testing.expectEqualStrings("hello", sub1.data());

    var sub2 = try wrapper.substring(6, null);
    defer sub2.deinit();
    try std.testing.expectEqualStrings("world", sub2.data());
}

/// 测试ArrayWrapper基本操作
test "ArrayWrapper basic operations" {
    const allocator = std.testing.allocator;
    const types = @import("../../src/runtime/types.zig");
    const Value = types.Value;

    var wrapper = try array_wrapper.ArrayWrapper.init(allocator);
    defer wrapper.deinit();

    try std.testing.expect(wrapper.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), wrapper.length());

    _ = try wrapper.push(Value.initInt(1));
    _ = try wrapper.push(Value.initInt(2));
    _ = try wrapper.push(Value.initInt(3));

    try std.testing.expect(!wrapper.isEmpty());
    try std.testing.expectEqual(@as(usize, 3), wrapper.length());

    // 测试get
    if (wrapper.get(0)) |val| {
        try std.testing.expectEqual(@as(i64, 1), val.data.integer);
    } else {
        try std.testing.expect(false);
    }
}

/// 测试ArrayWrapper切片
test "ArrayWrapper slice" {
    const allocator = std.testing.allocator;
    const types = @import("../../src/runtime/types.zig");
    const Value = types.Value;

    var wrapper = try array_wrapper.ArrayWrapper.init(allocator);
    defer wrapper.deinit();

    _ = try wrapper.push(Value.initInt(1));
    _ = try wrapper.push(Value.initInt(2));
    _ = try wrapper.push(Value.initInt(3));
    _ = try wrapper.push(Value.initInt(4));
    _ = try wrapper.push(Value.initInt(5));

    var sliced = try wrapper.slice(1, 4);
    defer sliced.deinit();

    try std.testing.expectEqual(@as(usize, 3), sliced.length());
}

/// 测试URL解析
test "URL parsing" {
    const url1 = try http_client.parseUrl("http://example.com/path");
    try std.testing.expectEqualStrings("http", url1.scheme);
    try std.testing.expectEqualStrings("example.com", url1.host);
    try std.testing.expectEqual(@as(u16, 80), url1.port);
    try std.testing.expectEqualStrings("/path", url1.path);

    const url2 = try http_client.parseUrl("https://api.example.com:8080/v1/users");
    try std.testing.expectEqualStrings("https", url2.scheme);
    try std.testing.expectEqualStrings("api.example.com", url2.host);
    try std.testing.expectEqual(@as(u16, 8080), url2.port);
}

/// 测试转义序列检测
test "escape sequence detection" {
    try std.testing.expect(string_utils.hasEscapeSequences("hello\\nworld"));
    try std.testing.expect(string_utils.hasEscapeSequences("tab\\there"));
    try std.testing.expect(!string_utils.hasEscapeSequences("hello world"));
    try std.testing.expect(!string_utils.hasEscapeSequences("no escapes here"));
}
