//! 性能测试框架使用示例
//!
//! 演示如何使用 BenchmarkFramework 进行性能测试

const std = @import("std");
const framework = @import("framework.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 配置测试框架
    const config = framework.BenchmarkConfig{
        .warmup_iterations = 100,
        .test_iterations = 1000,
        .timeout_ms = 30000,
        .enable_memory_tracking = true,
        .verbose = true,
        .php_executable = "php",
        .zigphp_executable = "./zig-out/bin/zig-php",
    };
    
    const bench = try framework.BenchmarkFramework.init(allocator, config);
    defer bench.deinit();
    
    std.debug.print("\n=== Zig-PHP 性能测试框架 ===\n\n", .{});
    
    // 示例 1: 单个测试
    std.debug.print("示例 1: 运行单个测试\n", .{});
    std.debug.print("------------------------\n", .{});
    
    const single_result = bench.runComparison("tests/simple_benchmark.php") catch |err| {
        std.debug.print("测试失败: {s}\n", .{@errorName(err)});
        return;
    };
    
    // 生成单个测试报告
    try bench.generateReport(single_result, "benchmark_report.md", .markdown);
    try bench.generateReport(single_result, "benchmark_report.json", .json);
    try bench.generateReport(single_result, "benchmark_report.html", .html);
    
    std.debug.print("\n单个测试完成！\n", .{});
    std.debug.print("  - Markdown 报告: benchmark_report.md\n", .{});
    std.debug.print("  - JSON 报告: benchmark_report.json\n", .{});
    std.debug.print("  - HTML 报告: benchmark_report.html\n", .{});
    
    // 示例 2: 批量测试
    std.debug.print("\n示例 2: 运行批量测试\n", .{});
    std.debug.print("------------------------\n", .{});
    
    const test_scripts = [_][]const u8{
        "tests/simple_benchmark.php",
        "tests/comprehensive_benchmark.php",
        "examples/benchmark.php",
    };
    
    const batch_result = bench.runBatchTests(&test_scripts) catch |err| {
        std.debug.print("批量测试失败: {s}\n", .{@errorName(err)});
        return;
    };
    
    // 生成批量测试报告
    try bench.generateBatchReport(batch_result, "batch_report.md", .markdown);
    try bench.generateBatchReport(batch_result, "batch_report.json", .json);
    try bench.generateBatchReport(batch_result, "batch_report.csv", .csv);
    try bench.generateBatchReport(batch_result, "batch_report.html", .html);
    
    std.debug.print("\n批量测试完成！\n", .{});
    std.debug.print("  - Markdown 报告: batch_report.md\n", .{});
    std.debug.print("  - JSON 报告: batch_report.json\n", .{});
    std.debug.print("  - CSV 报告: batch_report.csv\n", .{});
    std.debug.print("  - HTML 报告: batch_report.html\n", .{});
    
    // 示例 3: 性能基线管理
    std.debug.print("\n示例 3: 性能基线管理\n", .{});
    std.debug.print("------------------------\n", .{});
    
    // 保存当前性能作为基线
    try bench.saveBaseline("simple_benchmark", single_result.zigphp_stats);
    try bench.saveBaselinesToFile("performance_baseline.json");
    
    std.debug.print("已保存性能基线到: performance_baseline.json\n", .{});
    
    // 示例 4: 性能回归检测
    std.debug.print("\n示例 4: 性能回归检测\n", .{});
    std.debug.print("------------------------\n", .{});
    
    const regression = try bench.detectRegression(
        "simple_benchmark",
        single_result.zigphp_stats,
        5.0, // 5% 阈值
    );
    
    if (regression.has_regression) {
        std.debug.print("⚠️  检测到性能回归！\n", .{});
        std.debug.print("  平均值变化: {d:.2}%\n", .{regression.mean_change_percent});
        std.debug.print("  中位数变化: {d:.2}%\n", .{regression.median_change_percent});
        std.debug.print("  P95 变化: {d:.2}%\n", .{regression.p95_change_percent});
    } else {
        std.debug.print("✓ 无性能回归\n", .{});
    }
    
    std.debug.print("\n=== 测试完成 ===\n", .{});
}
