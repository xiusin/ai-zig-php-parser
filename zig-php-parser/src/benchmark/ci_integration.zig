// CI 集成模块
// 用于在持续集成环境中运行性能测试和回归检测

const std = @import("std");
const RegressionDetector = @import("regression_detector.zig").RegressionDetector;
const BenchmarkResult = @import("regression_detector.zig").BenchmarkResult;

/// CI 环境配置
pub const CIConfig = struct {
    baseline_dir: []const u8 = ".perf_baselines",
    report_dir: []const u8 = ".perf_reports",
    threshold_percent: f64 = 5.0,
    mem_threshold_percent: f64 = 1.0,
    fail_on_regression: bool = true,
    update_baseline_on_main: bool = true,
    
    pub fn fromEnv(allocator: std.mem.Allocator) !CIConfig {
        var config = CIConfig{};
        
        // 从环境变量读取配置
        if (std.process.getEnvVarOwned(allocator, "PERF_BASELINE_DIR")) |dir| {
            config.baseline_dir = dir;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(allocator, "PERF_THRESHOLD")) |threshold_str| {
            defer allocator.free(threshold_str);
            config.threshold_percent = try std.fmt.parseFloat(f64, threshold_str);
        } else |_| {}

        if (std.process.getEnvVarOwned(allocator, "PERF_MEM_THRESHOLD")) |threshold_str| {
            defer allocator.free(threshold_str);
            config.mem_threshold_percent = try std.fmt.parseFloat(f64, threshold_str);
        } else |_| {}
        
        if (std.process.getEnvVarOwned(allocator, "PERF_FAIL_ON_REGRESSION")) |fail_str| {
            defer allocator.free(fail_str);
            config.fail_on_regression = std.mem.eql(u8, fail_str, "true");
        } else |_| {}
        
        return config;
    }
};

/// CI 运行器
pub const CIRunner = struct {
    allocator: std.mem.Allocator,
    config: CIConfig,
    detector: RegressionDetector,
    
    pub fn init(allocator: std.mem.Allocator, config: CIConfig) !CIRunner {
        const detector = try RegressionDetector.init(
            allocator,
            config.baseline_dir,
            config.threshold_percent,
            config.mem_threshold_percent,
        );
        
        // 确保报告目录存在
        std.fs.cwd().makePath(config.report_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        
        return CIRunner{
            .allocator = allocator,
            .config = config,
            .detector = detector,
        };
    }
    
    /// 获取当前 Git commit
    fn getGitCommit(self: *CIRunner) ![]u8 {
        // 尝试从环境变量获取
        if (std.process.getEnvVarOwned(self.allocator, "GIT_COMMIT")) |commit| {
            return commit;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "GITHUB_SHA")) |commit| {
            return commit;
        } else |_| {}
        
        // 尝试从 git 命令获取
        var child = std.process.Child.init(
            &[_][]const u8{ "git", "rev-parse", "HEAD" },
            self.allocator,
        );
        child.stdout_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024);
        _ = try child.wait();
        
        // 去除换行符并复制为可变切片
        const trimmed = std.mem.trim(u8, stdout, &std.ascii.whitespace);
        defer self.allocator.free(stdout);
        return try self.allocator.dupe(u8, trimmed);
    }
    
    /// 获取当前分支
    fn getGitBranch(self: *CIRunner) ![]u8 {
        // 尝试从环境变量获取
        if (std.process.getEnvVarOwned(self.allocator, "GIT_BRANCH")) |branch| {
            return branch;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "GITHUB_REF_NAME")) |branch| {
            return branch;
        } else |_| {}
        
        // 尝试从 git 命令获取
        var child = std.process.Child.init(
            &[_][]const u8{ "git", "rev-parse", "--abbrev-ref", "HEAD" },
            self.allocator,
        );
        child.stdout_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024);
        _ = try child.wait();
        
        // 去除换行符并复制为可变切片
        const trimmed = std.mem.trim(u8, stdout, &std.ascii.whitespace);
        defer self.allocator.free(stdout);
        return try self.allocator.dupe(u8, trimmed);
    }
    
    /// 运行性能测试并检测回归
    pub fn runAndCheck(
        self: *CIRunner,
        results: []const BenchmarkResult,
    ) !bool {
        const git_commit = try self.getGitCommit();
        defer self.allocator.free(git_commit);
        
        const git_branch = try self.getGitBranch();
        defer self.allocator.free(git_branch);
        
        std.debug.print("Running performance regression check...\n", .{});
        std.debug.print("Git commit: {s}\n", .{git_commit});
        std.debug.print("Git branch: {s}\n", .{git_branch});
        
        // 检测回归
        const regressions = try self.detector.detectRegressions(results);
        defer self.allocator.free(regressions);
        
        // 生成报告
        const report_filename = try std.fmt.allocPrint(
            self.allocator,
            "{s}/perf_report_{d}.md",
            .{ self.config.report_dir, std.time.timestamp() },
        );
        defer self.allocator.free(report_filename);
        
        const report_file = try std.fs.cwd().createFile(report_filename, .{});
        defer report_file.close();
        
        // 生成报告（直接传递文件）
        try self.detector.generateReport(regressions, report_file);
        
        std.debug.print("Performance report saved to: {s}\n", .{report_filename});
        
        // 统计回归数量
        var regression_count: usize = 0;
        for (regressions) |reg| {
            if (reg.is_regression) {
                regression_count += 1;
                std.debug.print("⚠️  REGRESSION: {s} (+{d:.2}%)\n", .{
                    reg.benchmark_name,
                    reg.regression_percent,
                });
            }
        }
        
        // 如果在主分支且配置允许，更新基线
        const is_main_branch = std.mem.eql(u8, git_branch, "main") or
            std.mem.eql(u8, git_branch, "master");
        
        if (is_main_branch and self.config.update_baseline_on_main) {
            std.debug.print("Updating baselines on main branch...\n", .{});
            try self.detector.updateBaselines(results, git_commit);
        }
        
        // 返回是否有回归
        const has_regression = regression_count > 0;
        
        if (has_regression) {
            std.debug.print("\n❌ Performance regression detected: {d} test(s) failed\n", .{regression_count});
            if (self.config.fail_on_regression) {
                return false;
            }
        } else {
            std.debug.print("\n✅ All performance tests passed\n", .{});
        }
        
        return !has_regression or !self.config.fail_on_regression;
    }
    
    /// 生成 GitHub Actions 注释
    pub fn generateGitHubComment(
        _: *CIRunner,
        regressions: []const @import("regression_detector.zig").RegressionResult,
        writer: anytype,
    ) !void {
        try writer.writeAll("## 🔍 Performance Regression Check\n\n");
        
        var regression_count: usize = 0;
        for (regressions) |reg| {
            if (reg.is_regression) regression_count += 1;
        }
        
        if (regression_count > 0) {
            try writer.print("⚠️ **{d} performance regression(s) detected**\n\n", .{regression_count});
            
            try writer.writeAll("| Benchmark | Baseline | Current | Change | Status |\n");
            try writer.writeAll("|-----------|----------|---------|--------|--------|\n");
            
            for (regressions) |reg| {
                if (reg.is_regression) {
                    try writer.print("| `{s}` | {d} ns | {d} ns | +{d:.2}% | ❌ |\n", .{
                        reg.benchmark_name,
                        reg.baseline_avg_ns,
                        reg.current_avg_ns,
                        reg.regression_percent,
                    });
                }
            }
        } else {
            try writer.writeAll("✅ **All performance tests passed**\n\n");
            
            try writer.writeAll("<details>\n<summary>View all results</summary>\n\n");
            try writer.writeAll("| Benchmark | Baseline | Current | Change |\n");
            try writer.writeAll("|-----------|----------|---------|--------|\n");
            
            for (regressions) |reg| {
                if (reg.baseline_avg_ns > 0) {
                    const sign = if (reg.regression_percent >= 0) "+" else "";
                    try writer.print("| `{s}` | {d} ns | {d} ns | {s}{d:.2}% |\n", .{
                        reg.benchmark_name,
                        reg.baseline_avg_ns,
                        reg.current_avg_ns,
                        sign,
                        reg.regression_percent,
                    });
                }
            }
            
            try writer.writeAll("\n</details>\n");
        }
    }
};

// 测试
test "CIRunner - basic functionality" {
    const allocator = std.testing.allocator;
    
    const config = CIConfig{
        .baseline_dir = "test_ci_baselines",
        .report_dir = "test_ci_reports",
        .threshold_percent = 5.0,
        .mem_threshold_percent = 1.0,
        .fail_on_regression = true,
        .update_baseline_on_main = false,
    };
    
    defer std.fs.cwd().deleteTree(config.baseline_dir) catch {};
    defer std.fs.cwd().deleteTree(config.report_dir) catch {};
    
    var runner = try CIRunner.init(allocator, config);
    
    // 创建测试结果
    const results = [_]BenchmarkResult{
        .{
            .benchmark_name = "test1",
            .avg_time_ns = 1000,
            .min_time_ns = 900,
            .max_time_ns = 1100,
            .stddev_ns = 50.0,
            .iterations = 100,
        },
    };
    
    // 第一次运行（没有基线）
    const success1 = try runner.runAndCheck(&results);
    try std.testing.expect(success1);
    
    // 更新基线
    try runner.detector.updateBaselines(&results, "test_commit");
    
    // 第二次运行（有基线，无回归）
    const success2 = try runner.runAndCheck(&results);
    try std.testing.expect(success2);
}
