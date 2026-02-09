const std = @import("std");
const testing = std.testing;
const HotspotAnalyzer = @import("profiler/hotspot_analyzer.zig").HotspotAnalyzer;

// Feature: advanced-compiler-optimization, Property 38: 热点识别准确性
test "hotspot analyzer accuracy - identifies most frequent code paths" {
    const allocator = testing.allocator;
    var analyzer = HotspotAnalyzer.init(allocator);
    defer analyzer.deinit();

    // 记录基本块执行
    try analyzer.recordBlockExecution("block1");
    try analyzer.recordBlockExecution("block1");
    try analyzer.recordBlockExecution("block1");
    try analyzer.recordBlockExecution("block2");

    // 验证：block1 是热点
    try testing.expectEqual(@as(u64, 3), analyzer.getBlockCount("block1"));
    try testing.expectEqual(@as(u64, 1), analyzer.getBlockCount("block2"));
}

// 测试边执行计数
test "hotspot analyzer edge counting" {
    const allocator = testing.allocator;
    var analyzer = HotspotAnalyzer.init(allocator);
    defer analyzer.deinit();

    try analyzer.recordEdgeExecution("A", "B");
    try analyzer.recordEdgeExecution("A", "B");
    try analyzer.recordEdgeExecution("B", "C");

    try testing.expectEqual(@as(u64, 2), analyzer.getEdgeCount("A", "B"));
    try testing.expectEqual(@as(u64, 1), analyzer.getEdgeCount("B", "C"));
}

// 测试热点查找
test "hotspot analyzer find hot blocks" {
    const allocator = testing.allocator;
    var analyzer = HotspotAnalyzer.init(allocator);
    defer analyzer.deinit();

    try analyzer.recordBlockExecution("hot1");
    try analyzer.recordBlockExecution("hot1");
    try analyzer.recordBlockExecution("hot1");
    try analyzer.recordBlockExecution("cold");

    const hot_blocks = try analyzer.findHotBlocks(2);
    defer allocator.free(hot_blocks);

    try testing.expectEqual(@as(usize, 1), hot_blocks.len);
    try testing.expectEqualStrings("hot1", hot_blocks[0]);
}

// 测试报告生成
test "hotspot analyzer report generation" {
    const allocator = testing.allocator;
    var analyzer = HotspotAnalyzer.init(allocator);
    defer analyzer.deinit();

    try analyzer.recordBlockExecution("main");
    try analyzer.recordBlockExecution("main");
    try analyzer.recordBlockExecution("helper");

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    try analyzer.generateReport(buffer.writer(allocator));

    const output = buffer.items;
    try testing.expect(std.mem.indexOf(u8, output, "Hotspot Analysis Report") != null);
    try testing.expect(std.mem.indexOf(u8, output, "main") != null);
}

// 测试零执行计数
test "hotspot analyzer zero count" {
    const allocator = testing.allocator;
    var analyzer = HotspotAnalyzer.init(allocator);
    defer analyzer.deinit();

    try testing.expectEqual(@as(u64, 0), analyzer.getBlockCount("nonexistent"));
}
