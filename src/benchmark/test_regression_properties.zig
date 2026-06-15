// 性能回归检测属性测试
// Feature: zig-php-performance-optimization
// Property 37: 性能回归检测
// 验证：需求 6.7

const std = @import("std");
const testing = std.testing;
const RegressionDetector = @import("regression_detector.zig").RegressionDetector;
const BenchmarkResult = @import("regression_detector.zig").BenchmarkResult;
const PerformanceBaseline = @import("regression_detector.zig").PerformanceBaseline;

/// 属性测试框架
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: std.Random,
    iterations: u32 = 100,
    
    fn init(allocator: std.mem.Allocator, seed: u64) PropertyTest {
        var prng = std.Random.DefaultPrng.init(seed);
        return PropertyTest{
            .allocator = allocator,
            .rng = prng.random(),
            .iterations = 100,
        };
    }
    
    fn run(
        self: *PropertyTest,
        comptime T: type,
        property: fn (T) anyerror!bool,
        generator: fn (*std.Random, std.mem.Allocator) anyerror!T,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const input = try generator(&self.rng, self.allocator);
            
            const result = property(input) catch |err| {
                std.debug.print("Property error at iteration {d}: {}\n", .{i, err});
                failed += 1;
                continue;
            };
            
            if (result) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed at iteration {d}\n", .{i});
            }
        }
        
        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("Property test: {d}/{d} passed ({d:.2}%)\n", .{
            passed,
            self.iterations,
            success_rate * 100.0,
        });
        
        return failed == 0;
    }
};

/// 测试输入生成器
const TestInput = struct {
    baseline_avg_ns: u64,
    current_avg_ns: u64,
    threshold_percent: f64,
};

fn generateTestInput(rng: *std.Random, allocator: std.mem.Allocator) !TestInput {
    _ = allocator;
    
    const baseline_avg = rng.intRangeAtMost(u64, 100, 10000);
    
    // 生成不同程度的性能变化
    const change_type = rng.intRangeAtMost(u8, 0, 2);
    const current_avg = switch (change_type) {
        0 => baseline_avg, // 无变化
        1 => baseline_avg + rng.intRangeAtMost(u64, 1, baseline_avg / 10), // 小幅上升
        2 => baseline_avg + rng.intRangeAtMost(u64, baseline_avg / 5, baseline_avg / 2), // 大幅上升
        else => unreachable,
    };
    
    const threshold = rng.float(f64) * 10.0 + 1.0; // 1-11%
    
    return TestInput{
        .baseline_avg_ns = baseline_avg,
        .current_avg_ns = current_avg,
        .threshold_percent = threshold,
    };
}

// ============================================================================
// 属性 37：性能回归检测
// ============================================================================

// 属性 37.1：回归检测一致性
// 对于任意基线和当前性能数据，如果性能下降超过阈值，
// 回归检测器应该始终报告回归
test "Property 37.1: Regression detection consistency" {
    const allocator = testing.allocator;
    
    var pt = PropertyTest.init(allocator, 12345);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            const test_dir = "test_prop_37_1";
            defer std.fs.cwd.deleteTree(test_dir) catch {};
            
            var detector = try RegressionDetector.init(
                testing.allocator,
                test_dir,
                input.threshold_percent,
            );
            
            // 创建基线
            const baseline_result = BenchmarkResult{
                .benchmark_name = "test_bench",
                .avg_time_ns = input.baseline_avg_ns,
                .min_time_ns = input.baseline_avg_ns - 100,
                .max_time_ns = input.baseline_avg_ns + 100,
                .stddev_ns = 50.0,
                .iterations = 100,
            };
            
            try detector.saveBaseline(baseline_result, "baseline_commit");
            
            // 创建当前结果
            const current_result = BenchmarkResult{
                .benchmark_name = "test_bench",
                .avg_time_ns = input.current_avg_ns,
                .min_time_ns = input.current_avg_ns - 100,
                .max_time_ns = input.current_avg_ns + 100,
                .stddev_ns = 50.0,
                .iterations = 100,
            };
            
            // 检测回归
            const regression = try detector.detectRegression(current_result);
            
            // 计算预期的变化百分比
            const baseline_f = @as(f64, @floatFromInt(input.baseline_avg_ns));
            const current_f = @as(f64, @floatFromInt(input.current_avg_ns));
            const expected_change = ((current_f - baseline_f) / baseline_f) * 100.0;
            
            // 验证回归检测结果
            const should_be_regression = expected_change > input.threshold_percent;
            
            return regression.is_regression == should_be_regression;
        }
    }.check;
    
    const passed = try pt.run(TestInput, property, generateTestInput);
    try testing.expect(passed);
}

// 属性 37.2：回归百分比计算正确性
// 对于任意基线和当前性能数据，回归百分比应该正确计算
test "Property 37.2: Regression percentage calculation correctness" {
    const allocator = testing.allocator;
    
    var pt = PropertyTest.init(allocator, 54321);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            const test_dir = "test_prop_37_2";
            defer std.fs.cwd.deleteTree(test_dir) catch {};
            
            var detector = try RegressionDetector.init(
                testing.allocator,
                test_dir,
                input.threshold_percent,
            );
            
            // 创建基线
            const baseline_result = BenchmarkResult{
                .benchmark_name = "test_bench",
                .avg_time_ns = input.baseline_avg_ns,
                .min_time_ns = input.baseline_avg_ns - 100,
                .max_time_ns = input.baseline_avg_ns + 100,
                .stddev_ns = 50.0,
                .iterations = 100,
            };
            
            try detector.saveBaseline(baseline_result, "baseline_commit");
            
            // 创建当前结果
            const current_result = BenchmarkResult{
                .benchmark_name = "test_bench",
                .avg_time_ns = input.current_avg_ns,
                .min_time_ns = input.current_avg_ns - 100,
                .max_time_ns = input.current_avg_ns + 100,
                .stddev_ns = 50.0,
                .iterations = 100,
            };
            
            // 检测回归
            const regression = try detector.detectRegression(current_result);
            
            // 计算预期的变化百分比
            const baseline_f = @as(f64, @floatFromInt(input.baseline_avg_ns));
            const current_f = @as(f64, @floatFromInt(input.current_avg_ns));
            const expected_change = ((current_f - baseline_f) / baseline_f) * 100.0;
            
            // 验证百分比计算（允许浮点误差）
            const diff = @abs(regression.regression_percent - expected_change);
            return diff < 0.01; // 0.01% 误差容忍度
        }
    }.check;
    
    const passed = try pt.run(TestInput, property, generateTestInput);
    try testing.expect(passed);
}

// 属性 37.3：基线持久化正确性
// 对于任意基线数据，保存后应该能够正确加载
test "Property 37.3: Baseline persistence correctness" {
    const allocator = testing.allocator;
    
    var pt = PropertyTest.init(allocator, 98765);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            const test_dir = "test_prop_37_3";
            defer std.fs.cwd.deleteTree(test_dir) catch {};
            
            var detector = try RegressionDetector.init(
                testing.allocator,
                test_dir,
                input.threshold_percent,
            );
            
            // 创建基线
            const baseline_result = BenchmarkResult{
                .benchmark_name = "test_bench",
                .avg_time_ns = input.baseline_avg_ns,
                .min_time_ns = input.baseline_avg_ns - 100,
                .max_time_ns = input.baseline_avg_ns + 100,
                .stddev_ns = 50.0,
                .iterations = 100,
            };
            
            // 保存基线
            try detector.saveBaseline(baseline_result, "test_commit");
            
            // 加载基线
            const loaded_baseline = try detector.loadBaseline("test_bench");
            
            if (loaded_baseline) |baseline| {
                // 验证数据一致性
                return baseline.avg_time_ns == input.baseline_avg_ns and
                    baseline.min_time_ns == input.baseline_avg_ns - 100 and
                    baseline.max_time_ns == input.baseline_avg_ns + 100;
            }
            
            return false;
        }
    }.check;
    
    const passed = try pt.run(TestInput, property, generateTestInput);
    try testing.expect(passed);
}

// 属性 37.4：阈值敏感性
// 对于任意阈值，回归检测应该正确响应阈值变化
test "Property 37.4: Threshold sensitivity" {
    const allocator = testing.allocator;
    
    const test_dir = "test_prop_37_4";
    defer std.fs.cwd.deleteTree(test_dir) catch {};
    
    // 创建固定的测试数据
    const baseline_avg: u64 = 1000;
    const current_avg: u64 = 1080; // +8% 变化
    
    // 测试不同阈值
    const thresholds = [_]f64{ 5.0, 7.0, 9.0, 10.0 };
    
    for (thresholds) |threshold| {
        var detector = try RegressionDetector.init(
            allocator,
            test_dir,
            threshold,
        );
        
        // 创建基线
        const baseline_result = BenchmarkResult{
            .benchmark_name = "test_bench",
            .avg_time_ns = baseline_avg,
            .min_time_ns = baseline_avg - 100,
            .max_time_ns = baseline_avg + 100,
            .stddev_ns = 50.0,
            .iterations = 100,
        };
        
        try detector.saveBaseline(baseline_result, "baseline_commit");
        
        // 创建当前结果
        const current_result = BenchmarkResult{
            .benchmark_name = "test_bench",
            .avg_time_ns = current_avg,
            .min_time_ns = current_avg - 100,
            .max_time_ns = current_avg + 100,
            .stddev_ns = 50.0,
            .iterations = 100,
        };
        
        // 检测回归
        const regression = try detector.detectRegression(current_result);
        
        // 8% 变化应该在 5% 和 7% 阈值下触发回归，但不在 9% 和 10% 阈值下
        const should_be_regression = threshold < 8.0;
        
        try testing.expectEqual(should_be_regression, regression.is_regression);
    }
}

// 属性 37.5：批量检测一致性
// 对于任意多个基准测试，批量检测应该与单独检测结果一致
test "Property 37.5: Batch detection consistency" {
    const allocator = testing.allocator;
    
    const test_dir = "test_prop_37_5";
    defer std.fs.cwd.deleteTree(test_dir) catch {};
    
    var detector = try RegressionDetector.init(allocator, test_dir, 5.0);
    
    // 创建多个基线
    const baseline_results = [_]BenchmarkResult{
        .{
            .benchmark_name = "bench1",
            .avg_time_ns = 1000,
            .min_time_ns = 900,
            .max_time_ns = 1100,
            .stddev_ns = 50.0,
            .iterations = 100,
        },
        .{
            .benchmark_name = "bench2",
            .avg_time_ns = 2000,
            .min_time_ns = 1800,
            .max_time_ns = 2200,
            .stddev_ns = 100.0,
            .iterations = 100,
        },
        .{
            .benchmark_name = "bench3",
            .avg_time_ns = 3000,
            .min_time_ns = 2700,
            .max_time_ns = 3300,
            .stddev_ns = 150.0,
            .iterations = 100,
        },
    };
    
    try detector.updateBaselines(&baseline_results, "baseline_commit");
    
    // 创建新的测试结果
    const new_results = [_]BenchmarkResult{
        .{
            .benchmark_name = "bench1",
            .avg_time_ns = 1150, // +15% 回归
            .min_time_ns = 1050,
            .max_time_ns = 1250,
            .stddev_ns = 60.0,
            .iterations = 100,
        },
        .{
            .benchmark_name = "bench2",
            .avg_time_ns = 2050, // +2.5% 正常
            .min_time_ns = 1900,
            .max_time_ns = 2300,
            .stddev_ns = 110.0,
            .iterations = 100,
        },
        .{
            .benchmark_name = "bench3",
            .avg_time_ns = 3100, // +3.3% 正常
            .min_time_ns = 2800,
            .max_time_ns = 3400,
            .stddev_ns = 160.0,
            .iterations = 100,
        },
    };
    
    // 批量检测
    const batch_regressions = try detector.detectRegressions(&new_results);
    defer allocator.free(batch_regressions);
    
    // 单独检测并比较
    for (new_results, 0..) |result, i| {
        const single_regression = try detector.detectRegression(result);
        
        // 验证批量检测和单独检测结果一致
        try testing.expectEqual(single_regression.is_regression, batch_regressions[i].is_regression);
        try testing.expectEqual(single_regression.baseline_avg_ns, batch_regressions[i].baseline_avg_ns);
        try testing.expectEqual(single_regression.current_avg_ns, batch_regressions[i].current_avg_ns);
        
        // 验证百分比计算一致（允许浮点误差）
        const diff = @abs(single_regression.regression_percent - batch_regressions[i].regression_percent);
        try testing.expect(diff < 0.01);
    }
}

// 属性 37.6：无基线情况处理
// 对于没有基线的基准测试，不应该报告回归
test "Property 37.6: No baseline handling" {
    const allocator = testing.allocator;
    
    var pt = PropertyTest.init(allocator, 11111);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            const test_dir = "test_prop_37_6";
            defer std.fs.cwd.deleteTree(test_dir) catch {};
            
            var detector = try RegressionDetector.init(
                testing.allocator,
                test_dir,
                input.threshold_percent,
            );
            
            // 创建当前结果（没有基线）
            const current_result = BenchmarkResult{
                .benchmark_name = "new_bench",
                .avg_time_ns = input.current_avg_ns,
                .min_time_ns = input.current_avg_ns - 100,
                .max_time_ns = input.current_avg_ns + 100,
                .stddev_ns = 50.0,
                .iterations = 100,
            };
            
            // 检测回归
            const regression = try detector.detectRegression(current_result);
            
            // 没有基线时不应该报告回归
            return !regression.is_regression and regression.baseline_avg_ns == 0;
        }
    }.check;
    
    const passed = try pt.run(TestInput, property, generateTestInput);
    try testing.expect(passed);
}

// ============================================================================
// 集成测试
// ============================================================================

test "Integration: Full regression detection workflow" {
    const allocator = testing.allocator;
    
    const test_dir = "test_integration";
    defer std.fs.cwd.deleteTree(test_dir) catch {};
    
    var detector = try RegressionDetector.init(allocator, test_dir, 5.0);
    
    // 第一次运行：建立基线
    const initial_results = [_]BenchmarkResult{
        .{
            .benchmark_name = "string_ops",
            .avg_time_ns = 1000,
            .min_time_ns = 900,
            .max_time_ns = 1100,
            .stddev_ns = 50.0,
            .iterations = 1000,
        },
        .{
            .benchmark_name = "array_ops",
            .avg_time_ns = 2000,
            .min_time_ns = 1800,
            .max_time_ns = 2200,
            .stddev_ns = 100.0,
            .iterations = 1000,
        },
    };
    
    try detector.updateBaselines(&initial_results, "commit_1");
    
    // 第二次运行：性能正常
    const normal_results = [_]BenchmarkResult{
        .{
            .benchmark_name = "string_ops",
            .avg_time_ns = 1030, // +3%
            .min_time_ns = 930,
            .max_time_ns = 1130,
            .stddev_ns = 55.0,
            .iterations = 1000,
        },
        .{
            .benchmark_name = "array_ops",
            .avg_time_ns = 2040, // +2%
            .min_time_ns = 1840,
            .max_time_ns = 2240,
            .stddev_ns = 105.0,
            .iterations = 1000,
        },
    };
    
    const normal_regressions = try detector.detectRegressions(&normal_results);
    defer allocator.free(normal_regressions);
    
    // 验证无回归
    for (normal_regressions) |reg| {
        try testing.expect(!reg.is_regression);
    }
    
    // 第三次运行：性能回归
    const regression_results = [_]BenchmarkResult{
        .{
            .benchmark_name = "string_ops",
            .avg_time_ns = 1200, // +20% 回归
            .min_time_ns = 1100,
            .max_time_ns = 1300,
            .stddev_ns = 60.0,
            .iterations = 1000,
        },
        .{
            .benchmark_name = "array_ops",
            .avg_time_ns = 2050, // +2.5% 正常
            .min_time_ns = 1900,
            .max_time_ns = 2250,
            .stddev_ns = 110.0,
            .iterations = 1000,
        },
    };
    
    const detected_regressions = try detector.detectRegressions(&regression_results);
    defer allocator.free(detected_regressions);
    
    // 验证检测到回归
    try testing.expect(detected_regressions[0].is_regression); // string_ops 回归
    try testing.expect(!detected_regressions[1].is_regression); // array_ops 正常
    
    // 生成报告
    var report_buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer report_buffer.deinit(allocator);
    
    try detector.generateReport(detected_regressions, report_buffer.writer(allocator));
    
    const report = report_buffer.items;
    try testing.expect(report.len > 0);
    try testing.expect(std.mem.indexOf(u8, report, "REGRESSION") != null);
}
