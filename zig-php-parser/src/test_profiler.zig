const std = @import("std");
const testing = std.testing;
const Profiler = @import("profiler/profiler.zig").Profiler;

// Feature: advanced-compiler-optimization, Property 36: 性能分析器记录准确性
test "profiler recording accuracy - records correct call counts" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 1000);
    defer profiler.deinit();

    // 记录函数调用
    try profiler.recordFunctionCall("func1", 100);
    try profiler.recordFunctionCall("func1", 150);
    try profiler.recordFunctionCall("func2", 200);

    // 验证：调用次数正确
    const stats1 = profiler.getStats("func1").?;
    try testing.expectEqual(@as(u64, 2), stats1.call_count);
    try testing.expectEqual(@as(u64, 250), stats1.total_time_ns);

    const stats2 = profiler.getStats("func2").?;
    try testing.expectEqual(@as(u64, 1), stats2.call_count);
    try testing.expectEqual(@as(u64, 200), stats2.total_time_ns);
}

// 测试平均时间计算
test "profiler average time calculation" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 1000);
    defer profiler.deinit();

    try profiler.recordFunctionCall("func", 100);
    try profiler.recordFunctionCall("func", 200);
    try profiler.recordFunctionCall("func", 300);

    const stats = profiler.getStats("func").?;
    try testing.expectEqual(@as(u64, 3), stats.call_count);
    try testing.expectEqual(@as(u64, 200), stats.avgTime());
}

// 测试火焰图生成
test "profiler flame graph generation" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 1000);
    defer profiler.deinit();

    try profiler.recordFunctionCall("main", 1000);
    try profiler.recordFunctionCall("helper", 500);

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    try profiler.generateFlameGraph(buffer.writer(allocator));

    const output = buffer.items;
    try testing.expect(std.mem.indexOf(u8, output, "main") != null);
    try testing.expect(std.mem.indexOf(u8, output, "helper") != null);
}

// 测试采样循环
test "profiler sampling loop" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 100); // 100us 采样间隔
    defer profiler.deinit();

    try profiler.start();
    std.Thread.sleep(500 * 1000); // 休眠 500us
    profiler.stop();

    // 验证：至少记录了一些采样
    const stats = profiler.getStats("main");
    try testing.expect(stats != null);
    try testing.expect(stats.?.call_count > 0);
}

// 测试零调用次数
test "profiler zero call count average" {
    const allocator = testing.allocator;
    var profiler = try Profiler.init(allocator, 1000);
    defer profiler.deinit();

    try profiler.recordFunctionCall("func", 0);

    const stats = profiler.getStats("func").?;
    try testing.expectEqual(@as(u64, 0), stats.avgTime());
}
