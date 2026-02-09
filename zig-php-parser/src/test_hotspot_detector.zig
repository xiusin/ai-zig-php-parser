const std = @import("std");
const HotspotDetector = @import("jit/hotspot_detector.zig").HotspotDetector;

// Feature: advanced-compiler-optimization, Property 26: 热点识别准确性
test "hotspot detection - correctly identifies hot functions" {
    const allocator = std.testing.allocator;
    var detector = HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 记录函数调用
    const function_name = "testFunction";
    
    // 前 999 次不应触发热点
    var i: u32 = 0;
    while (i < 999) : (i += 1) {
        const is_hot = try detector.recordFunctionCall(function_name);
        try std.testing.expect(!is_hot);
    }
    
    // 第 1000 次应触发热点
    const is_hot = try detector.recordFunctionCall(function_name);
    try std.testing.expect(is_hot);
    
    // 验证计数
    const count = detector.getFunctionCount(function_name);
    try std.testing.expectEqual(@as(u32, 1000), count);
}

test "hotspot detection - correctly identifies hot loops" {
    const allocator = std.testing.allocator;
    var detector = HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 创建循环
    var loop = HotspotDetector.Loop{
        .id = 1,
        .function_name = "testFunction",
        .start_offset = 10,
        .end_offset = 50,
    };
    
    // 前 9999 次不应触发热点
    var i: u32 = 0;
    while (i < 9999) : (i += 1) {
        const is_hot = try detector.recordLoopIteration(&loop);
        try std.testing.expect(!is_hot);
    }
    
    // 第 10000 次应触发热点
    const is_hot = try detector.recordLoopIteration(&loop);
    try std.testing.expect(is_hot);
    
    // 验证计数
    const count = detector.getLoopCount(&loop);
    try std.testing.expectEqual(@as(u32, 10000), count);
}

test "hotspot detection - tracks multiple functions" {
    const allocator = std.testing.allocator;
    var detector = HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 记录多个函数
    _ = try detector.recordFunctionCall("func1");
    _ = try detector.recordFunctionCall("func2");
    _ = try detector.recordFunctionCall("func1");
    
    try std.testing.expectEqual(@as(u32, 2), detector.getFunctionCount("func1"));
    try std.testing.expectEqual(@as(u32, 1), detector.getFunctionCount("func2"));
    try std.testing.expectEqual(@as(u32, 0), detector.getFunctionCount("func3"));
}

test "hotspot detection - reset clears counters" {
    const allocator = std.testing.allocator;
    var detector = HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 记录一些调用
    _ = try detector.recordFunctionCall("func1");
    _ = try detector.recordFunctionCall("func1");
    
    try std.testing.expectEqual(@as(u32, 2), detector.getFunctionCount("func1"));
    
    // 重置
    detector.reset();
    
    try std.testing.expectEqual(@as(u32, 0), detector.getFunctionCount("func1"));
}

test "hotspot detection - get hot functions" {
    const allocator = std.testing.allocator;
    var detector = HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 创建热点函数
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        _ = try detector.recordFunctionCall("hotFunc");
    }
    
    // 创建非热点函数
    _ = try detector.recordFunctionCall("coldFunc");
    
    // 获取热点函数
    const hot_functions = try detector.getHotFunctions(allocator);
    defer allocator.free(hot_functions);
    
    try std.testing.expectEqual(@as(usize, 1), hot_functions.len);
    try std.testing.expectEqualStrings("hotFunc", hot_functions[0]);
}
