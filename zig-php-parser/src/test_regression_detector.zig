const std = @import("std");
const testing = std.testing;
const RegressionDetector = @import("profiler/regression_detector.zig").RegressionDetector;
const BenchmarkResults = @import("profiler/regression_detector.zig").BenchmarkResults;
const BenchmarkResult = @import("profiler/regression_detector.zig").BenchmarkResult;

// Feature: advanced-compiler-optimization, Property 39: 性能回归检测准确性
test "regression detector accuracy - detects performance degradation" {
    const allocator = testing.allocator;

    // 创建基准结果
    var baseline = BenchmarkResults.init(allocator);
    try baseline.add(.{
        .name = "test1",
        .mean_time_ns = 1000,
        .std_dev_ns = 10,
        .iterations = 100,
    });

    var detector = RegressionDetector.init(allocator, baseline, 0.05); // 5% 阈值
    defer detector.deinit();

    // 创建当前结果（性能下降 10%）
    var current = BenchmarkResults.init(allocator);
    defer current.deinit();
    try current.add(.{
        .name = "test1",
        .mean_time_ns = 1100,
        .std_dev_ns = 10,
        .iterations = 100,
    });

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const has_regression = try detector.compare(current, buffer.writer(allocator));

    // 验证：检测到回归
    try testing.expect(has_regression);
    const output = buffer.items;
    try testing.expect(std.mem.indexOf(u8, output, "REGRESSION") != null);
}

// 测试性能改进检测
test "regression detector improvement detection" {
    const allocator = testing.allocator;

    var baseline = BenchmarkResults.init(allocator);
    try baseline.add(.{
        .name = "test1",
        .mean_time_ns = 1000,
        .std_dev_ns = 10,
        .iterations = 100,
    });

    var detector = RegressionDetector.init(allocator, baseline, 0.05);
    defer detector.deinit();

    // 性能改进 10%
    var current = BenchmarkResults.init(allocator);
    defer current.deinit();
    try current.add(.{
        .name = "test1",
        .mean_time_ns = 900,
        .std_dev_ns = 10,
        .iterations = 100,
    });

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const has_regression = try detector.compare(current, buffer.writer(allocator));

    // 验证：无回归，但有改进
    try testing.expect(!has_regression);
    const output = buffer.items;
    try testing.expect(std.mem.indexOf(u8, output, "IMPROVEMENT") != null);
}

// 测试新基准测试
test "regression detector new benchmark" {
    const allocator = testing.allocator;

    var baseline = BenchmarkResults.init(allocator);
    _ = &baseline; // 消除未修改警告
    var detector = RegressionDetector.init(allocator, baseline, 0.05);
    defer detector.deinit();

    var current = BenchmarkResults.init(allocator);
    defer current.deinit();
    try current.add(.{
        .name = "new_test",
        .mean_time_ns = 1000,
        .std_dev_ns = 10,
        .iterations = 100,
    });

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const has_regression = try detector.compare(current, buffer.writer(allocator));

    // 验证：无回归，标记为新测试
    try testing.expect(!has_regression);
    const output = buffer.items;
    try testing.expect(std.mem.indexOf(u8, output, "NEW") != null);
}

// 测试阈值边界
test "regression detector threshold boundary" {
    const allocator = testing.allocator;

    var baseline = BenchmarkResults.init(allocator);
    try baseline.add(.{
        .name = "test1",
        .mean_time_ns = 1000,
        .std_dev_ns = 10,
        .iterations = 100,
    });

    var detector = RegressionDetector.init(allocator, baseline, 0.05);
    defer detector.deinit();

    // 性能下降 4%（低于阈值）
    var current = BenchmarkResults.init(allocator);
    defer current.deinit();
    try current.add(.{
        .name = "test1",
        .mean_time_ns = 1040,
        .std_dev_ns = 10,
        .iterations = 100,
    });

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const has_regression = try detector.compare(current, buffer.writer(allocator));

    // 验证：无回归（低于阈值）
    try testing.expect(!has_regression);
}

// 测试多个基准测试
test "regression detector multiple benchmarks" {
    const allocator = testing.allocator;

    var baseline = BenchmarkResults.init(allocator);
    try baseline.add(.{
        .name = "test1",
        .mean_time_ns = 1000,
        .std_dev_ns = 10,
        .iterations = 100,
    });
    try baseline.add(.{
        .name = "test2",
        .mean_time_ns = 2000,
        .std_dev_ns = 20,
        .iterations = 100,
    });

    var detector = RegressionDetector.init(allocator, baseline, 0.05);
    defer detector.deinit();

    var current = BenchmarkResults.init(allocator);
    defer current.deinit();
    try current.add(.{
        .name = "test1",
        .mean_time_ns = 1100, // 回归
        .std_dev_ns = 10,
        .iterations = 100,
    });
    try current.add(.{
        .name = "test2",
        .mean_time_ns = 1900, // 改进
        .std_dev_ns = 20,
        .iterations = 100,
    });

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const has_regression = try detector.compare(current, buffer.writer(allocator));

    // 验证：检测到回归
    try testing.expect(has_regression);
    const output = buffer.items;
    try testing.expect(std.mem.indexOf(u8, output, "REGRESSION") != null);
    try testing.expect(std.mem.indexOf(u8, output, "IMPROVEMENT") != null);
}
