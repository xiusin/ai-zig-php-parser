//! CI 性能回归检测运行器
//!
//! 用于持续集成环境中的自动化性能测试和回归检测

const std = @import("std");
const framework = @import("framework.zig");

/// CI 运行器配置
pub const CIConfig = struct {
    /// 基线文件路径
    baseline_path: []const u8 = "performance_baseline.json",
    /// 测试脚本目录
    test_dir: []const u8 = "tests/benchmarks",
    /// 回归阈值（百分比）
    regression_threshold: f64 = 5.0,
    /// 输出目录
    output_dir: []const u8 = "benchmark_results",
    /// 是否在检测到回归时失败
    fail_on_regression: bool = true,
};

/// CI 运行结果
pub const CIResult = struct {
    total_tests: u32,
    passed_tests: u32,
    failed_tests: u32,
    regressions_detected: u32,
    batch_result: framework.BatchTestResult,
    regression_results: []framework.RegressionResult,
};

/// CI 运行器
pub const CIRunner = struct {
    allocator: std.mem.Allocator,
    config: CIConfig,
    benchmark: *framework.BenchmarkFramework,

    const Self = @This();

    /// 初始化 CI 运行器
    pub fn init(allocator: std.mem.Allocator, config: CIConfig) !*Self {
        const bench_config = framework.BenchmarkConfig{
            .warmup_iterations = 50,
            .test_iterations = 500,
            .timeout_ms = 60000,
            .enable_memory_tracking = true,
            .verbose = false, // CI 环境中减少输出
        };

        const benchmark = try framework.BenchmarkFramework.init(allocator, bench_config);

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .benchmark = benchmark,
        };

        return self;
    }

    /// 清理资源
    pub fn deinit(self: *Self) void {
        self.benchmark.deinit();
        self.allocator.destroy(self);
    }

    /// 运行 CI 测试
    pub fn run(self: *Self) !CIResult {
        std.debug.print("=== CI 性能测试开始 ===\n", .{});

        // 1. 加载性能基线
        std.debug.print("加载性能基线: {s}\n", .{self.config.baseline_path});
        self.benchmark.loadBaselines(self.config.baseline_path) catch |err| {
            std.debug.print("警告: 无法加载基线文件: {s}\n", .{@errorName(err)});
        };

        // 2. 发现测试脚本
        std.debug.print("扫描测试目录: {s}\n", .{self.config.test_dir});
        const test_scripts = try self.discoverTestScripts();
        defer self.allocator.free(test_scripts);

        std.debug.print("发现 {d} 个测试脚本\n", .{test_scripts.len});

        // 3. 运行批量测试
        std.debug.print("运行批量测试...\n", .{});
        const batch_result = try self.benchmark.runBatchTests(test_scripts);

        // 4. 检测性能回归
        std.debug.print("检测性能回归...\n", .{});
        var regression_results = std.ArrayList(framework.RegressionResult).init(self.allocator);
        defer regression_results.deinit();

        var regressions_detected: u32 = 0;

        for (batch_result.results) |result| {
            const regression = try self.benchmark.detectRegression(
                result.test_name,
                result.zigphp_stats,
                self.config.regression_threshold,
            );

            try regression_results.append(regression);

            if (regression.has_regression) {
                regressions_detected += 1;
                std.debug.print("⚠️  回归: {s}\n", .{result.test_name});
            }
        }

        // 5. 生成报告
        std.debug.print("生成报告...\n", .{});
        try self.generateCIReports(batch_result, regression_results.items);

        // 6. 更新基线（如果没有回归）
        if (regressions_detected == 0) {
            std.debug.print("更新性能基线...\n", .{});
            for (batch_result.results) |result| {
                try self.benchmark.saveBaseline(result.test_name, result.zigphp_stats);
            }
            try self.benchmark.saveBaselinesToFile(self.config.baseline_path);
        }

        std.debug.print("=== CI 性能测试完成 ===\n", .{});

        return CIResult{
            .total_tests = batch_result.total_tests,
            .passed_tests = batch_result.passed_tests,
            .failed_tests = batch_result.failed_tests,
            .regressions_detected = regressions_detected,
            .batch_result = batch_result,
            .regression_results = try regression_results.toOwnedSlice(),
        };
    }

    /// 发现测试脚本
    fn discoverTestScripts(self: *Self) ![][]const u8 {
        var scripts = std.ArrayList([]const u8).init(self.allocator);
        errdefer scripts.deinit();

        // 打开测试目录
        var dir = std.fs.cwd.openIterableDir(self.config.test_dir, .{}) catch |err| {
            std.debug.print("无法打开测试目录: {s}\n", .{@errorName(err)});
            return &[_][]const u8{};
        };
        defer dir.close();

        // 遍历目录
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                // 检查是否是 PHP 文件
                if (std.mem.endsWith(u8, entry.name, ".php")) {
                    const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.config.test_dir, entry.name });
                    try scripts.append(full_path);
                }
            }
        }

        return scripts.toOwnedSlice();
    }

    /// 生成 CI 报告
    fn generateCIReports(
        self: *Self,
        batch_result: framework.BatchTestResult,
        regression_results: []framework.RegressionResult,
    ) !void {
        // 创建输出目录
        std.fs.cwd.makeDir(self.config.output_dir) catch {};

        // 生成批量测试报告
        const batch_md = try std.fmt.allocPrint(self.allocator, "{s}/batch_report.md", .{self.config.output_dir});
        defer self.allocator.free(batch_md);
        try self.benchmark.generateBatchReport(batch_result, batch_md, .markdown);

        const batch_json = try std.fmt.allocPrint(self.allocator, "{s}/batch_report.json", .{self.config.output_dir});
        defer self.allocator.free(batch_json);
        try self.benchmark.generateBatchReport(batch_result, batch_json, .json);

        // 生成回归报告
        const regression_report = try std.fmt.allocPrint(self.allocator, "{s}/regression_report.md", .{self.config.output_dir});
        defer self.allocator.free(regression_report);
        try self.generateRegressionReport(regression_report, regression_results);

        std.debug.print("报告已生成到: {s}\n", .{self.config.output_dir});
    }

    /// 生成回归报告
    fn generateRegressionReport(
        self: *Self,
        output_path: []const u8,
        regression_results: []framework.RegressionResult,
    ) !void {
        const file = try std.fs.cwd.createFile(output_path, .{});
        defer file.close();

        const writer = file.writer();

        try writer.writeAll("# 性能回归检测报告\n\n");
        try writer.print("**阈值**: {d:.1}%\n\n", .{self.config.regression_threshold});

        // 统计回归数量
        var regression_count: u32 = 0;
        for (regression_results) |result| {
            if (result.has_regression) {
                regression_count += 1;
            }
        }

        try writer.print("**检测到的回归**: {d}/{d}\n\n", .{ regression_count, regression_results.len });

        if (regression_count > 0) {
            try writer.writeAll("## 回归详情\n\n");
            try writer.writeAll("| 测试名称 | 平均值变化 | 中位数变化 | P95 变化 |\n");
            try writer.writeAll("|----------|-----------|-----------|----------|\n");

            for (regression_results) |result| {
                if (result.has_regression) {
                    try writer.print("| {s} | {d:.2}% | {d:.2}% | {d:.2}% |\n", .{
                        result.test_name,
                        result.mean_change_percent,
                        result.median_change_percent,
                        result.p95_change_percent,
                    });
                }
            }
        } else {
            try writer.writeAll("✓ 未检测到性能回归\n");
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 解析命令行参数
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // 跳过程序名

    var config = CIConfig{};

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--baseline")) {
            config.baseline_path = args.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--test-dir")) {
            config.test_dir = args.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--threshold")) {
            const threshold_str = args.next() orelse return error.MissingArgument;
            config.regression_threshold = try std.fmt.parseFloat(f64, threshold_str);
        } else if (std.mem.eql(u8, arg, "--output-dir")) {
            config.output_dir = args.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--no-fail-on-regression")) {
            config.fail_on_regression = false;
        }
    }

    // 运行 CI 测试
    const runner = try CIRunner.init(allocator, config);
    defer runner.deinit();

    const result = try runner.run();
    defer allocator.free(result.regression_results);

    // 打印摘要
    std.debug.print("\n=== 测试摘要 ===\n", .{});
    std.debug.print("总测试数: {d}\n", .{result.total_tests});
    std.debug.print("通过: {d}\n", .{result.passed_tests});
    std.debug.print("失败: {d}\n", .{result.failed_tests});
    std.debug.print("回归: {d}\n", .{result.regressions_detected});
    std.debug.print("平均加速比: {d:.2}x\n", .{result.batch_result.average_speedup});

    // 如果检测到回归且配置为失败，则退出码为 1
    if (config.fail_on_regression and result.regressions_detected > 0) {
        std.debug.print("\n❌ CI 失败: 检测到性能回归\n", .{});
        std.process.exit(1);
    }

    std.debug.print("\n✓ CI 成功\n", .{});
}
