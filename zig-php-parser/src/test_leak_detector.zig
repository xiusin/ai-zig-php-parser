const std = @import("std");
const testing = std.testing;
const LeakDetector = @import("profiler/leak_detector.zig").LeakDetector;

// Feature: advanced-compiler-optimization, Property 37: 内存泄漏检测准确性
test "leak detector accuracy - tracks all unfreed allocations" {
    const allocator = testing.allocator;
    var detector = LeakDetector.init(allocator);
    defer detector.deinit();

    detector.enable();

    // 记录分配
    try detector.recordAllocation(0x1000, 100);
    try detector.recordAllocation(0x2000, 200);
    try detector.recordAllocation(0x3000, 300);

    // 释放一个
    detector.recordDeallocation(0x2000);

    // 验证：还有 2 个泄漏
    try testing.expectEqual(@as(usize, 2), detector.getLeakCount());
}

// 测试泄漏报告生成
test "leak detector report generation" {
    const allocator = testing.allocator;
    var detector = LeakDetector.init(allocator);
    defer detector.deinit();

    detector.enable();

    try detector.recordAllocation(0x1000, 100);
    try detector.recordAllocation(0x2000, 200);

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    try detector.checkLeaks(buffer.writer(allocator));

    const output = buffer.items;
    try testing.expect(std.mem.indexOf(u8, output, "Detected 2 memory leaks") != null);
    try testing.expect(std.mem.indexOf(u8, output, "0x1000") != null);
    try testing.expect(std.mem.indexOf(u8, output, "0x2000") != null);
}

// 测试无泄漏情况
test "leak detector no leaks" {
    const allocator = testing.allocator;
    var detector = LeakDetector.init(allocator);
    defer detector.deinit();

    detector.enable();

    try detector.recordAllocation(0x1000, 100);
    detector.recordDeallocation(0x1000);

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    try detector.checkLeaks(buffer.writer(allocator));

    const output = buffer.items;
    try testing.expect(std.mem.indexOf(u8, output, "No memory leaks detected") != null);
}

// 测试禁用状态
test "leak detector disabled state" {
    const allocator = testing.allocator;
    var detector = LeakDetector.init(allocator);
    defer detector.deinit();

    // 不启用，记录应该被忽略
    try detector.recordAllocation(0x1000, 100);

    try testing.expectEqual(@as(usize, 0), detector.getLeakCount());
}

// 测试启用/禁用切换
test "leak detector enable/disable toggle" {
    const allocator = testing.allocator;
    var detector = LeakDetector.init(allocator);
    defer detector.deinit();

    detector.enable();
    try detector.recordAllocation(0x1000, 100);

    detector.disable();
    try detector.recordAllocation(0x2000, 200);

    // 验证：只记录了第一个
    try testing.expectEqual(@as(usize, 1), detector.getLeakCount());
}
