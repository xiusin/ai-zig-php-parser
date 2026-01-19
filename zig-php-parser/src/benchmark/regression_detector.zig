// 性能回归检测系统
// 用于检测性能下降并生成报警

const std = @import("std");
const fs = std.fs;
const json = std.json;

/// 性能基线数据
pub const PerformanceBaseline = struct {
    benchmark_name: []const u8,
    avg_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    stddev_ns: f64,
    timestamp: i64,
    git_commit: []const u8,
    
    pub fn format(
        self: PerformanceBaseline,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Baseline({s}): avg={d}ns, stddev={d:.2}ns, commit={s}", .{
            self.benchmark_name,
            self.avg_time_ns,
            self.stddev_ns,
            self.git_commit,
        });
    }
};

/// 性能测试结果
pub const BenchmarkResult = struct {
    benchmark_name: []const u8,
    avg_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    stddev_ns: f64,
    iterations: u32,
    
    pub fn format(
        self: BenchmarkResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Result({s}): avg={d}ns, stddev={d:.2}ns, iters={d}", .{
            self.benchmark_name,
            self.avg_time_ns,
            self.stddev_ns,
            self.iterations,
        });
    }
};

/// 回归检测结果
pub const RegressionResult = struct {
    benchmark_name: []const u8,
    baseline_avg_ns: u64,
    current_avg_ns: u64,
    regression_percent: f64,
    is_regression: bool,
    
    pub fn format(
        self: RegressionResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const status = if (self.is_regression) "REGRESSION" else "OK";
        try writer.print("{s}: {s} ({d:.2}% change, baseline={d}ns, current={d}ns)", .{
            self.benchmark_name,
            status,
            self.regression_percent,
            self.baseline_avg_ns,
            self.current_avg_ns,
        });
    }
};

/// 性能回归检测器
pub const RegressionDetector = struct {
    allocator: std.mem.Allocator,
    baseline_dir: []const u8,
    threshold_percent: f64, // 回归阈值（百分比）
    
    /// 初始化回归检测器
    /// @param allocator 内存分配器
    /// @param baseline_dir 基线数据目录
    /// @param threshold_percent 回归阈值（默认 5.0%）
    pub fn init(
        allocator: std.mem.Allocator,
        baseline_dir: []const u8,
        threshold_percent: f64,
    ) !RegressionDetector {
        // 确保基线目录存在
        fs.cwd().makePath(baseline_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        
        return RegressionDetector{
            .allocator = allocator,
            .baseline_dir = baseline_dir,
            .threshold_percent = threshold_percent,
        };
    }
    
    /// 加载基线数据
    pub fn loadBaseline(self: *RegressionDetector, benchmark_name: []const u8) !?PerformanceBaseline {
        const filename = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.json",
            .{ self.baseline_dir, benchmark_name },
        );
        defer self.allocator.free(filename);
        
        const file = fs.cwd().openFile(filename, .{}) catch |err| {
            if (err == error.FileNotFound) return null;
            return err;
        };
        defer file.close();
        
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        
        const parsed = try json.parseFromSlice(
            PerformanceBaseline,
            self.allocator,
            content,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();
        
        // 直接返回值类型，不需要额外分配
        return parsed.value;
    }
    
    /// 保存基线数据
    pub fn saveBaseline(
        self: *RegressionDetector,
        result: BenchmarkResult,
        git_commit: []const u8,
    ) !void {
        const baseline = PerformanceBaseline{
            .benchmark_name = result.benchmark_name,
            .avg_time_ns = result.avg_time_ns,
            .min_time_ns = result.min_time_ns,
            .max_time_ns = result.max_time_ns,
            .stddev_ns = result.stddev_ns,
            .timestamp = std.time.timestamp(),
            .git_commit = git_commit,
        };
        
        const filename = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.json",
            .{ self.baseline_dir, result.benchmark_name },
        );
        defer self.allocator.free(filename);
        
        // 手动序列化 JSON
        const json_content = try std.fmt.allocPrint(
            self.allocator,
            \\{{
            \\  "benchmark_name": "{s}",
            \\  "avg_time_ns": {d},
            \\  "min_time_ns": {d},
            \\  "max_time_ns": {d},
            \\  "stddev_ns": {d},
            \\  "timestamp": {d},
            \\  "git_commit": "{s}"
            \\}}
            \\
        , .{
            baseline.benchmark_name,
            baseline.avg_time_ns,
            baseline.min_time_ns,
            baseline.max_time_ns,
            baseline.stddev_ns,
            baseline.timestamp,
            baseline.git_commit,
        });
        defer self.allocator.free(json_content);
        
        try fs.cwd().writeFile(.{
            .sub_path = filename,
            .data = json_content,
        });
    }
    
    /// 检测性能回归
    pub fn detectRegression(
        self: *RegressionDetector,
        result: BenchmarkResult,
    ) !RegressionResult {
        const baseline_opt = try self.loadBaseline(result.benchmark_name);
        
        if (baseline_opt) |baseline| {
            const baseline_avg = @as(f64, @floatFromInt(baseline.avg_time_ns));
            const current_avg = @as(f64, @floatFromInt(result.avg_time_ns));
            
            // 计算性能变化百分比
            const change_percent = ((current_avg - baseline_avg) / baseline_avg) * 100.0;
            
            // 判断是否为回归（性能下降超过阈值）
            const is_regression = change_percent > self.threshold_percent;
            
            return RegressionResult{
                .benchmark_name = result.benchmark_name,
                .baseline_avg_ns = baseline.avg_time_ns,
                .current_avg_ns = result.avg_time_ns,
                .regression_percent = change_percent,
                .is_regression = is_regression,
            };
        } else {
            // 没有基线数据，不算回归
            return RegressionResult{
                .benchmark_name = result.benchmark_name,
                .baseline_avg_ns = 0,
                .current_avg_ns = result.avg_time_ns,
                .regression_percent = 0.0,
                .is_regression = false,
            };
        }
    }
    
    /// 批量检测回归
    pub fn detectRegressions(
        self: *RegressionDetector,
        results: []const BenchmarkResult,
    ) ![]RegressionResult {
        var regressions = try std.ArrayList(RegressionResult).initCapacity(self.allocator, results.len);
        
        for (results) |result| {
            const regression = try self.detectRegression(result);
            try regressions.append(self.allocator, regression);
        }
        
        return regressions.toOwnedSlice(self.allocator);
    }
    
    /// 生成回归报告
    pub fn generateReport(
        self: *RegressionDetector,
        regressions: []const RegressionResult,
        file: std.fs.File,
    ) !void {
        // 统计回归数量
        var regression_count: usize = 0;
        for (regressions) |reg| {
            if (reg.is_regression) regression_count += 1;
        }
        
        // 生成报告头部
        const header = try std.fmt.allocPrint(self.allocator,
            \\# 性能回归检测报告
            \\
            \\检测时间: {d}
            \\回归阈值: {d:.1}%
            \\
            \\## 总结
            \\
            \\- 总测试数: {d}
            \\- 回归数: {d}
            \\- 通过数: {d}
            \\
            \\
        , .{
            std.time.timestamp(),
            self.threshold_percent,
            regressions.len,
            regression_count,
            regressions.len - regression_count,
        });
        defer self.allocator.free(header);
        
        try file.writeAll(header);
        
        // 如果有回归，生成回归表格
        if (regression_count > 0) {
            const regression_header =
                \\## ⚠️ 检测到性能回归
                \\
                \\| 基准测试 | 基线 (ns) | 当前 (ns) | 变化 (%) | 状态 |
                \\|---------|----------|----------|---------|------|
                \\
            ;
            try file.writeAll(regression_header);
            
            for (regressions) |reg| {
                if (reg.is_regression) {
                    const row = try std.fmt.allocPrint(self.allocator,
                        "| {s} | {d} | {d} | +{d:.2} | ❌ REGRESSION |\n",
                        .{
                            reg.benchmark_name,
                            reg.baseline_avg_ns,
                            reg.current_avg_ns,
                            reg.regression_percent,
                        }
                    );
                    defer self.allocator.free(row);
                    try file.writeAll(row);
                }
            }
            try file.writeAll("\n");
        }
        
        // 生成所有测试结果表格
        const all_results_header =
            \\## 所有测试结果
            \\
            \\| 基准测试 | 基线 (ns) | 当前 (ns) | 变化 (%) | 状态 |
            \\|---------|----------|----------|---------|------|
            \\
        ;
        try file.writeAll(all_results_header);
        
        for (regressions) |reg| {
            const status = if (reg.is_regression) "❌" else "✅";
            const sign = if (reg.regression_percent >= 0) "+" else "";
            
            const row = if (reg.baseline_avg_ns > 0)
                try std.fmt.allocPrint(self.allocator,
                    "| {s} | {d} | {d} | {s}{d:.2} | {s} |\n",
                    .{
                        reg.benchmark_name,
                        reg.baseline_avg_ns,
                        reg.current_avg_ns,
                        sign,
                        reg.regression_percent,
                        status,
                    }
                )
            else
                try std.fmt.allocPrint(self.allocator,
                    "| {s} | N/A | {d} | N/A | 🆕 NEW |\n",
                    .{
                        reg.benchmark_name,
                        reg.current_avg_ns,
                    }
                );
            defer self.allocator.free(row);
            try file.writeAll(row);
        }
    }
    
    /// 更新所有基线
    pub fn updateBaselines(
        self: *RegressionDetector,
        results: []const BenchmarkResult,
        git_commit: []const u8,
    ) !void {
        for (results) |result| {
            try self.saveBaseline(result, git_commit);
        }
    }
};

// 测试
test "RegressionDetector - basic functionality" {
    const allocator = std.testing.allocator;
    
    // 创建临时目录
    const test_dir = "test_baselines";
    defer fs.cwd().deleteTree(test_dir) catch {};
    
    var detector = try RegressionDetector.init(allocator, test_dir, 5.0);
    
    // 创建测试结果
    const result1 = BenchmarkResult{
        .benchmark_name = "test_benchmark",
        .avg_time_ns = 1000,
        .min_time_ns = 900,
        .max_time_ns = 1100,
        .stddev_ns = 50.0,
        .iterations = 100,
    };
    
    // 保存基线
    try detector.saveBaseline(result1, "abc123");
    
    // 加载基线
    const baseline = try detector.loadBaseline("test_benchmark");
    try std.testing.expect(baseline != null);
    try std.testing.expectEqual(@as(u64, 1000), baseline.?.avg_time_ns);
    
    // 测试无回归情况
    const result2 = BenchmarkResult{
        .benchmark_name = "test_benchmark",
        .avg_time_ns = 1030, // +3% 变化
        .min_time_ns = 950,
        .max_time_ns = 1150,
        .stddev_ns = 55.0,
        .iterations = 100,
    };
    
    const regression1 = try detector.detectRegression(result2);
    try std.testing.expect(!regression1.is_regression);
    
    // 测试回归情况
    const result3 = BenchmarkResult{
        .benchmark_name = "test_benchmark",
        .avg_time_ns = 1100, // +10% 变化
        .min_time_ns = 1000,
        .max_time_ns = 1200,
        .stddev_ns = 60.0,
        .iterations = 100,
    };
    
    const regression2 = try detector.detectRegression(result3);
    try std.testing.expect(regression2.is_regression);
    try std.testing.expect(regression2.regression_percent > 5.0);
}

test "RegressionDetector - batch detection" {
    const allocator = std.testing.allocator;
    
    const test_dir = "test_baselines_batch";
    defer fs.cwd().deleteTree(test_dir) catch {};
    
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
    };
    
    const regressions = try detector.detectRegressions(&new_results);
    defer allocator.free(regressions);
    
    try std.testing.expectEqual(@as(usize, 2), regressions.len);
    try std.testing.expect(regressions[0].is_regression); // bench1 回归
    try std.testing.expect(!regressions[1].is_regression); // bench2 正常
}
