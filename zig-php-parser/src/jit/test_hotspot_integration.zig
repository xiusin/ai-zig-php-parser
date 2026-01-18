/// 热点检测器集成测试
const std = @import("std");
const HotspotDetector = @import("hotspot_detector.zig").HotspotDetector;
const HotspotConfig = @import("hotspot_detector.zig").HotspotConfig;

test "集成测试: 热点检测触发逻辑" {
    const allocator = std.testing.allocator;
    
    // 创建热点检测器（低阈值以便测试）
    var config = HotspotConfig{};
    config.function_threshold = 5;
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    // 模拟函数执行
    const func_name = "test_function";
    
    // 前几次执行不应触发编译
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        try detector.recordExecution(func_name);
        try std.testing.expect(!detector.isHotspot(func_name));
    }
    
    // 第 5 次执行应触发热点检测
    try detector.recordExecution(func_name);
    try std.testing.expect(detector.isHotspot(func_name));
    
    // 验证统计
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 5), stats.total_function_calls);
    try std.testing.expectEqual(@as(u32, 1), stats.hotspot_functions_detected);
}

test "集成测试: 循环热点检测" {
    const allocator = std.testing.allocator;
    
    // 创建热点检测器
    var config = HotspotConfig{};
    config.loop_backedge_threshold = 100;
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    const func_name = "loop_function";
    const loop_offset: usize = 50;
    
    // 模拟循环执行
    var i: u32 = 0;
    while (i < 150) : (i += 1) {
        try detector.recordLoopBackedge(func_name, loop_offset);
    }
    
    // 验证循环成为热点
    try std.testing.expect(detector.isLoopHotspot(func_name, loop_offset));
    
    // 验证计数
    const count = detector.getLoopBackedgeCount(func_name, loop_offset);
    try std.testing.expectEqual(@as(u32, 150), count);
}

test "集成测试: 多函数热点检测" {
    const allocator = std.testing.allocator;
    
    var config = HotspotConfig{};
    config.function_threshold = 10;
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    // 模拟多个函数执行
    const functions = [_][]const u8{ "func_a", "func_b", "func_c" };
    const counts = [_]u32{ 15, 8, 20 };
    
    for (functions, counts) |func_name, count| {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try detector.recordExecution(func_name);
        }
    }
    
    // 验证热点
    try std.testing.expect(detector.isHotspot("func_a")); // 15 >= 10
    try std.testing.expect(!detector.isHotspot("func_b")); // 8 < 10
    try std.testing.expect(detector.isHotspot("func_c")); // 20 >= 10
    
    // 验证统计
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 43), stats.total_function_calls);
    try std.testing.expectEqual(@as(u32, 3), stats.unique_functions_tracked);
    try std.testing.expectEqual(@as(u32, 2), stats.hotspot_functions_detected);
}

test "集成测试: 热点检测性能" {
    const allocator = std.testing.allocator;
    
    const detector = try HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 测量记录执行的性能
    const iterations: u32 = 10000;
    const func_name = "perf_test_func";
    
    var timer = try std.time.Timer.start();
    
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        try detector.recordExecution(func_name);
    }
    
    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / iterations;
    
    // 每次操作应该很快（< 1000 ns）
    std.debug.print("\n热点检测性能: {d} ns/op\n", .{ns_per_op});
    try std.testing.expect(ns_per_op < 1000);
}

test "集成测试: 配置禁用热点检测" {
    const allocator = std.testing.allocator;
    
    var config = HotspotConfig{};
    config.enabled = false;
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    // 记录执行
    try detector.recordExecution("test_func");
    
    // 验证不会检测热点
    try std.testing.expect(!detector.isHotspot("test_func"));
    
    // 统计应该为 0
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_function_calls);
}

test "集成测试: 热点检测器重置功能" {
    const allocator = std.testing.allocator;
    
    var config = HotspotConfig{};
    config.function_threshold = 5;
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    // 记录执行并触发热点
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try detector.recordExecution("test_func");
    }
    
    try std.testing.expect(detector.isHotspot("test_func"));
    
    // 重置
    detector.reset();
    
    // 验证重置后状态
    try std.testing.expect(!detector.isHotspot("test_func"));
    try std.testing.expectEqual(@as(u32, 0), detector.getExecutionCount("test_func"));
    
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_function_calls);
    try std.testing.expectEqual(@as(u32, 0), stats.hotspot_functions_detected);
}
