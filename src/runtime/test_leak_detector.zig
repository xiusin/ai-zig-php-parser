//! 内存泄漏检测器集成测试
//!
//! 验证需求：10.5

const std = @import("std");
const testing = std.testing;
const LeakDetector = @import("leak_detector.zig").LeakDetector;
const LeakAnalyzer = @import("leak_detector.zig").LeakAnalyzer;
const StackTrace = @import("leak_detector.zig").StackTrace;
const AllocationInfo = @import("leak_detector.zig").AllocationInfo;

// ============================================================================
// 集成测试
// ============================================================================

test "LeakDetector - full workflow" {
    var detector = try LeakDetector.init(testing.allocator);
    defer detector.deinit();

    // 模拟真实的分配和释放场景

    // 场景 1：正常分配和释放
    try detector.recordAllocation(0x1000, 100, "String");
    try detector.recordAllocation(0x2000, 200, "Array");
    detector.recordFree(0x1000);
    detector.recordFree(0x2000);

    // 场景 2：部分泄漏
    try detector.recordAllocation(0x3000, 300, "Object");
    try detector.recordAllocation(0x4000, 400, "HashMap");
    detector.recordFree(0x3000);
    // 0x4000 未释放 - 泄漏

    // 场景 3：多个相同类型的泄漏
    try detector.recordAllocation(0x5000, 150, "String");
    try detector.recordAllocation(0x6000, 250, "String");
    // 两个 String 都未释放 - 泄漏

    // 检查泄漏
    const leaks = try detector.checkLeaks();
    defer {
        for (leaks) |*leak| {
            leak.deinit(testing.allocator);
        }
        testing.allocator.free(leaks);
    }

    // 验证泄漏数量
    try testing.expectEqual(@as(usize, 3), leaks.len);

    // 验证统计信息
    const stats = detector.getStats();
    try testing.expectEqual(@as(u64, 6), stats.total_allocations);
    try testing.expectEqual(@as(u64, 3), stats.total_frees);
    try testing.expectEqual(@as(usize, 3), stats.active_allocations);
    try testing.expectEqual(@as(usize, 800), stats.current_bytes); // 400 + 150 + 250
}

test "LeakDetector - report generation" {
    var detector = try LeakDetector.init(testing.allocator);
    defer detector.deinit();

    // 创建多种类型的泄漏
    try detector.recordAllocation(0x1000, 1024, "String");
    try detector.recordAllocation(0x2000, 2048, "Array");
    try detector.recordAllocation(0x3000, 512, "Object");
    try detector.recordAllocation(0x4000, 256, "String");
    try detector.recordAllocation(0x5000, 4096, "HashMap");

    // 生成报告
    var buffer = std.ArrayList(u8).initCapacity(testing.allocator, 0) catch unreachable;
    defer buffer.deinit(testing.allocator);

    try detector.generateReport(buffer.writer(testing.allocator));

    const report = buffer.items;

    // 验证报告内容
    try testing.expect(std.mem.indexOf(u8, report, "Memory Leak Detection Report") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Total Allocations: 5") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Total Frees: 0") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Active Allocations: 5") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Detected 5 memory leak(s)") != null);

    // 验证类型汇总
    try testing.expect(std.mem.indexOf(u8, report, "Summary by Type") != null);
    try testing.expect(std.mem.indexOf(u8, report, "String: 2 leak(s)") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Array: 1 leak(s)") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Object: 1 leak(s)") != null);
    try testing.expect(std.mem.indexOf(u8, report, "HashMap: 1 leak(s)") != null);
}

test "LeakAnalyzer - comprehensive analysis" {
    var detector = try LeakDetector.init(testing.allocator);
    defer detector.deinit();

    // 创建复杂的泄漏场景
    // 大量 String 泄漏
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try detector.recordAllocation(0x1000 + i, 100 + i * 10, "String");
    }

    // 少量其他类型
    try detector.recordAllocation(0x2000, 500, "Array");
    try detector.recordAllocation(0x3000, 1000, "Object");
    try detector.recordAllocation(0x4000, 2000, "HashMap");

    // 分析泄漏模式
    var analyzer = LeakAnalyzer.init(testing.allocator, &detector);
    var pattern = try analyzer.analyzeLeakPatterns();
    defer pattern.deinit(testing.allocator);

    // 验证分析结果
    try testing.expectEqual(@as(usize, 13), pattern.total_leaks);
    try testing.expect(pattern.total_leaked_bytes > 0);
    try testing.expect(pattern.most_common_type != null);
    try testing.expectEqualStrings("String", pattern.most_common_type.?);
    try testing.expectEqual(@as(usize, 2000), pattern.largest_leak_size);

    // 生成修复建议
    var buffer = std.ArrayList(u8).initCapacity(testing.allocator, 0) catch unreachable;
    defer buffer.deinit(testing.allocator);

    try analyzer.generateFixSuggestions(buffer.writer(testing.allocator));

    const suggestions = buffer.items;
    try testing.expect(std.mem.indexOf(u8, suggestions, "Fix Suggestions") != null);
    try testing.expect(std.mem.indexOf(u8, suggestions, "Focus on Type 'String'") != null);
}

test "LeakDetector - stress test" {
    var detector = try LeakDetector.init(testing.allocator);
    defer detector.deinit();

    // 大量分配和释放
    const count = 1000;
    var j: usize = 0;
    while (j < count) : (j += 1) {
        try detector.recordAllocation(0x10000 + j, 100, "TestType");
    }

    // 释放一半
    var k: usize = 0;
    while (k < count / 2) : (k += 1) {
        detector.recordFree(0x10000 + k);
    }

    // 验证统计
    const stats = detector.getStats();
    try testing.expectEqual(@as(u64, count), stats.total_allocations);
    try testing.expectEqual(@as(u64, count / 2), stats.total_frees);
    try testing.expectEqual(@as(usize, count / 2), stats.active_allocations);

    // 检查泄漏
    const leaks = try detector.checkLeaks();
    defer {
        for (leaks) |*leak| {
            leak.deinit(testing.allocator);
        }
        testing.allocator.free(leaks);
    }

    try testing.expectEqual(@as(usize, count / 2), leaks.len);
}

test "LeakDetector - memory overhead" {
    var detector = try LeakDetector.init(testing.allocator);
    defer detector.deinit();

    // 执行一些操作
    try detector.recordAllocation(0x1000, 100, "String");
    try detector.recordAllocation(0x2000, 200, "Array");
    detector.recordFree(0x1000);

    // 验证内存统计准确性
    const final_stats = detector.getStats();
    try testing.expectEqual(@as(usize, 200), final_stats.current_bytes);
    try testing.expectEqual(@as(usize, 300), final_stats.peak_bytes);
    try testing.expectEqual(@as(u64, 300), final_stats.total_allocated_bytes);
    try testing.expectEqual(@as(u64, 100), final_stats.total_freed_bytes);
}

test "LeakDetector - edge cases" {
    var detector = try LeakDetector.init(testing.allocator);
    defer detector.deinit();

    // 边界情况 1：释放不存在的地址
    detector.recordFree(0x9999); // 不应该崩溃

    // 边界情况 2：重复释放
    try detector.recordAllocation(0x1000, 100, "String");
    detector.recordFree(0x1000);
    detector.recordFree(0x1000); // 不应该崩溃

    // 边界情况 3：零大小分配
    try detector.recordAllocation(0x2000, 0, "Empty");

    // 边界情况 4：非常大的分配
    try detector.recordAllocation(0x3000, 1024 * 1024 * 1024, "LargeBuffer");

    const stats = detector.getStats();
    try testing.expect(stats.total_allocations >= 2);
}
