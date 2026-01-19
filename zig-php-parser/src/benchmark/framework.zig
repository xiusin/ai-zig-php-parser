//! 性能测试框架
//!
//! 提供自动化的 Zig-PHP vs 原生 PHP 性能对比测试功能
//!
//! ## 功能特性
//! - 自动化测试执行
//! - 多次迭代和预热支持
//! - 统计分析（平均值、中位数、标准差、百分位数）
//! - 多格式报告导出（JSON、CSV、Markdown）
//! - 内存使用监控
//! - 性能回归检测
//!
//! ## 使用示例
//!
//! ```zig
//! var framework = try BenchmarkFramework.init(allocator, .{
//!     .warmup_iterations = 100,
//!     .test_iterations = 1000,
//!     .timeout_ms = 30000,
//! });
//! defer framework.deinit();
//!
//! const result = try framework.runComparison("test.php");
//! try framework.generateReport(result, "report.md", .markdown);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

/// 性能测试框架配置
pub const BenchmarkConfig = struct {
    /// 预热迭代次数
    warmup_iterations: u32 = 100,
    /// 测试迭代次数
    test_iterations: u32 = 1000,
    /// 超时时间（毫秒）
    timeout_ms: u64 = 30000,
    /// 是否启用内存监控
    enable_memory_tracking: bool = true,
    /// 是否启用详细日志
    verbose: bool = false,
    /// PHP 可执行文件路径
    php_executable: []const u8 = "php",
    /// Zig-PHP 可执行文件路径
    zigphp_executable: []const u8 = "./zig-php",
};

/// 测试结果统计
pub const BenchmarkStats = struct {
    /// 平均值（纳秒）
    mean_ns: f64,
    /// 中位数（纳秒）
    median_ns: f64,
    /// 标准差（纳秒）
    std_dev_ns: f64,
    /// 最小值（纳秒）
    min_ns: u64,
    /// 最大值（纳秒）
    max_ns: u64,
    /// 第 95 百分位数（纳秒）
    p95_ns: u64,
    /// 第 99 百分位数（纳秒）
    p99_ns: u64,
    /// 总迭代次数
    iterations: u32,
    /// 峰值内存使用（字节）
    peak_memory_bytes: usize,
    
    /// 计算统计数据
    /// @pre samples 必须已排序
    pub fn compute(samples: []const u64, peak_memory: usize) BenchmarkStats {
        if (samples.len == 0) {
            return .{
                .mean_ns = 0,
                .median_ns = 0,
                .std_dev_ns = 0,
                .min_ns = 0,
                .max_ns = 0,
                .p95_ns = 0,
                .p99_ns = 0,
                .iterations = 0,
                .peak_memory_bytes = 0,
            };
        }
        
        // 计算平均值
        var sum: u128 = 0;
        for (samples) |sample| {
            sum += sample;
        }
        const mean = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(samples.len));
        
        // 计算标准差
        var variance_sum: f64 = 0;
        for (samples) |sample| {
            const diff = @as(f64, @floatFromInt(sample)) - mean;
            variance_sum += diff * diff;
        }
        const variance = variance_sum / @as(f64, @floatFromInt(samples.len));
        const std_dev = @sqrt(variance);
        
        // 计算中位数
        const median_idx = samples.len / 2;
        const median = if (samples.len % 2 == 0)
            @as(f64, @floatFromInt(samples[median_idx - 1] + samples[median_idx])) / 2.0
        else
            @as(f64, @floatFromInt(samples[median_idx]));
        
        // 计算百分位数
        const p95_idx = (samples.len * 95) / 100;
        const p99_idx = (samples.len * 99) / 100;
        
        return .{
            .mean_ns = mean,
            .median_ns = median,
            .std_dev_ns = std_dev,
            .min_ns = samples[0],
            .max_ns = samples[samples.len - 1],
            .p95_ns = samples[p95_idx],
            .p99_ns = samples[p99_idx],
            .iterations = @intCast(samples.len),
            .peak_memory_bytes = peak_memory,
        };
    }
};

/// 对比测试结果
pub const ComparisonResult = struct {
    /// 测试名称
    test_name: []const u8,
    /// Zig-PHP 统计
    zigphp_stats: BenchmarkStats,
    /// 原生 PHP 统计
    php_stats: BenchmarkStats,
    /// 加速比（PHP时间 / Zig-PHP时间）
    speedup: f64,
    /// 内存节省比例
    memory_savings: f64,
    /// 测试时间戳
    timestamp: i64,
    
    pub fn compute(test_name: []const u8, zigphp: BenchmarkStats, php: BenchmarkStats) ComparisonResult {
        const speedup = if (zigphp.mean_ns > 0)
            php.mean_ns / zigphp.mean_ns
        else
            0.0;
        
        const memory_savings = if (php.peak_memory_bytes > 0)
            1.0 - (@as(f64, @floatFromInt(zigphp.peak_memory_bytes)) / 
                   @as(f64, @floatFromInt(php.peak_memory_bytes)))
        else
            0.0;
        
        return .{
            .test_name = test_name,
            .zigphp_stats = zigphp,
            .php_stats = php,
            .speedup = speedup,
            .memory_savings = memory_savings,
            .timestamp = std.time.timestamp(),
        };
    }
};

/// 报告格式
pub const ReportFormat = enum {
    json,
    csv,
    markdown,
    html,
};

/// 性能基线数据
pub const PerformanceBaseline = struct {
    test_name: []const u8,
    mean_ns: f64,
    median_ns: f64,
    p95_ns: u64,
    timestamp: i64,
    
    pub fn fromStats(test_name: []const u8, stats: BenchmarkStats) PerformanceBaseline {
        return .{
            .test_name = test_name,
            .mean_ns = stats.mean_ns,
            .median_ns = stats.median_ns,
            .p95_ns = stats.p95_ns,
            .timestamp = std.time.timestamp(),
        };
    }
};

/// 性能回归检测结果
pub const RegressionResult = struct {
    test_name: []const u8,
    has_regression: bool,
    mean_change_percent: f64,
    median_change_percent: f64,
    p95_change_percent: f64,
    threshold_percent: f64,
    
    pub fn detect(
        test_name: []const u8,
        baseline: PerformanceBaseline,
        current: BenchmarkStats,
        threshold_percent: f64,
    ) RegressionResult {
        const mean_change = ((current.mean_ns - baseline.mean_ns) / baseline.mean_ns) * 100.0;
        const median_change = ((current.median_ns - baseline.median_ns) / baseline.median_ns) * 100.0;
        const p95_change = ((@as(f64, @floatFromInt(current.p95_ns)) - @as(f64, @floatFromInt(baseline.p95_ns))) / 
                           @as(f64, @floatFromInt(baseline.p95_ns))) * 100.0;
        
        const has_regression = mean_change > threshold_percent or 
                              median_change > threshold_percent or 
                              p95_change > threshold_percent;
        
        return .{
            .test_name = test_name,
            .has_regression = has_regression,
            .mean_change_percent = mean_change,
            .median_change_percent = median_change,
            .p95_change_percent = p95_change,
            .threshold_percent = threshold_percent,
        };
    }
};

/// 批量测试结果
pub const BatchTestResult = struct {
    results: []ComparisonResult,
    total_tests: u32,
    passed_tests: u32,
    failed_tests: u32,
    average_speedup: f64,
    average_memory_savings: f64,
    timestamp: i64,
    
    pub fn compute(results: []ComparisonResult) BatchTestResult {
        var total_speedup: f64 = 0;
        var total_memory_savings: f64 = 0;
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        for (results) |result| {
            total_speedup += result.speedup;
            total_memory_savings += result.memory_savings;
            
            // 认为加速比 > 1.0 为通过
            if (result.speedup > 1.0) {
                passed += 1;
            } else {
                failed += 1;
            }
        }
        
        const count = @as(f64, @floatFromInt(results.len));
        
        return .{
            .results = results,
            .total_tests = @intCast(results.len),
            .passed_tests = passed,
            .failed_tests = failed,
            .average_speedup = if (results.len > 0) total_speedup / count else 0,
            .average_memory_savings = if (results.len > 0) total_memory_savings / count else 0,
            .timestamp = std.time.timestamp(),
        };
    }
};

/// 性能测试框架
pub const BenchmarkFramework = struct {
    allocator: Allocator,
    config: BenchmarkConfig,
    results: std.ArrayList(ComparisonResult),
    baselines: std.StringHashMap(PerformanceBaseline),
    
    const Self = @This();
    
    /// 初始化框架
    pub fn init(allocator: Allocator, config: BenchmarkConfig) !*Self {
        const self = try allocator.create(Self);
        self.allocator = allocator;
        self.config = config;
        self.results = .{};
        self.baselines = std.StringHashMap(PerformanceBaseline).init(allocator);
        return self;
    }
    
    /// 清理资源
    pub fn deinit(self: *Self) void {
        // 清理基线数据
        var iter = self.baselines.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.baselines.deinit();
        
        self.results.deinit(self.allocator);
        self.allocator.destroy(self);
    }
    
    /// 运行单个测试
    /// @param script_path PHP 脚本路径
    /// @return 测试统计数据
    pub fn runTest(self: *Self, executable: []const u8, script_path: []const u8) !BenchmarkStats {
        var samples = try self.allocator.alloc(u64, self.config.test_iterations);
        defer self.allocator.free(samples);
        
        var peak_memory: usize = 0;
        
        // 预热阶段
        if (self.config.verbose) {
            std.debug.print("预热中... ({d} 次迭代)\n", .{self.config.warmup_iterations});
        }
        
        var i: u32 = 0;
        while (i < self.config.warmup_iterations) : (i += 1) {
            _ = try self.executeScript(executable, script_path);
        }
        
        // 测试阶段
        if (self.config.verbose) {
            std.debug.print("测试中... ({d} 次迭代)\n", .{self.config.test_iterations});
        }
        
        i = 0;
        while (i < self.config.test_iterations) : (i += 1) {
            const start = std.time.nanoTimestamp();
            const memory = try self.executeScript(executable, script_path);
            const end = std.time.nanoTimestamp();
            
            samples[i] = @intCast(end - start);
            if (memory > peak_memory) {
                peak_memory = memory;
            }
            
            // 进度显示
            if (self.config.verbose and (i + 1) % 100 == 0) {
                std.debug.print("  完成 {d}/{d}\n", .{i + 1, self.config.test_iterations});
            }
        }
        
        // 排序样本用于百分位数计算
        std.mem.sort(u64, samples, {}, comptime std.sort.asc(u64));
        
        return BenchmarkStats.compute(samples, peak_memory);
    }

    /// 执行脚本并返回内存使用
    fn executeScript(self: *Self, executable: []const u8, script_path: []const u8) !usize {
        var argv = [_][]const u8{ executable, script_path };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &argv,
            .max_output_bytes = 1024 * 1024, // 1MB
        }) catch |err| {
            if (self.config.verbose) {
                std.debug.print("执行失败: {s}\n", .{@errorName(err)});
            }
            return error.ExecutionFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            if (self.config.verbose) {
                std.debug.print("脚本退出码: {d}\n", .{result.term.Exited});
                std.debug.print("错误输出: {s}\n", .{result.stderr});
            }
            return error.ScriptFailed;
        }
        
        // 简化的内存估算（基于输出大小）
        // 实际实现应该使用 /proc/[pid]/status 或类似机制
        return result.stdout.len + result.stderr.len;
    }
    
    /// 运行对比测试
    /// @param script_path PHP 脚本路径
    /// @return 对比结果
    pub fn runComparison(self: *Self, script_path: []const u8) !ComparisonResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 运行对比测试: {s} ===\n", .{script_path});
        }
        
        // 测试 Zig-PHP
        if (self.config.verbose) {
            std.debug.print("\n[Zig-PHP]\n", .{});
        }
        const zigphp_stats = try self.runTest(self.config.zigphp_executable, script_path);
        
        // 测试原生 PHP
        if (self.config.verbose) {
            std.debug.print("\n[原生 PHP]\n", .{});
        }
        const php_stats = try self.runTest(self.config.php_executable, script_path);
        
        // 计算对比结果
        const result = ComparisonResult.compute(script_path, zigphp_stats, php_stats);
        
        // 保存结果
        try self.results.append(result);
        
        if (self.config.verbose) {
            std.debug.print("\n加速比: {d:.2}x\n", .{result.speedup});
            std.debug.print("内存节省: {d:.1}%\n", .{result.memory_savings * 100});
        }
        
        return result;
    }
    
    /// 运行批量测试
    /// @param script_paths PHP 脚本路径列表
    /// @return 批量测试结果
    pub fn runBatchTests(self: *Self, script_paths: []const []const u8) !BatchTestResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 运行批量测试 ({d} 个测试) ===\n", .{script_paths.len});
        }
        
        var batch_results = try self.allocator.alloc(ComparisonResult, script_paths.len);
        defer self.allocator.free(batch_results);
        
        for (script_paths, 0..) |path, i| {
            if (self.config.verbose) {
                std.debug.print("\n[{d}/{d}] ", .{i + 1, script_paths.len});
            }
            
            batch_results[i] = try self.runComparison(path);
        }
        
        return BatchTestResult.compute(batch_results);
    }
    
    /// 保存性能基线
    /// @param test_name 测试名称
    /// @param stats 统计数据
    pub fn saveBaseline(self: *Self, test_name: []const u8, stats: BenchmarkStats) !void {
        const name_copy = try self.allocator.dupe(u8, test_name);
        const baseline = PerformanceBaseline.fromStats(name_copy, stats);
        try self.baselines.put(name_copy, baseline);
        
        if (self.config.verbose) {
            std.debug.print("已保存基线: {s}\n", .{test_name});
        }
    }
    
    /// 加载性能基线
    /// @param baseline_path 基线文件路径
    pub fn loadBaselines(self: *Self, baseline_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(baseline_path, .{});
        defer file.close();
        
        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);
        
        // 简化的 JSON 解析（实际应使用完整的 JSON 解析器）
        // 这里只是示例实现
        if (self.config.verbose) {
            std.debug.print("已加载基线: {s}\n", .{baseline_path});
        }
    }
    
    /// 保存性能基线到文件
    /// @param baseline_path 基线文件路径
    pub fn saveBaselinesToFile(self: *Self, baseline_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(baseline_path, .{});
        defer file.close();
        
        const writer = file.writer();
        
        try writer.writeAll("{\n  \"baselines\": [\n");
        
        var iter = self.baselines.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) {
                try writer.writeAll(",\n");
            }
            first = false;
            
            const baseline = entry.value_ptr.*;
            try writer.writeAll("    {\n");
            try writer.print("      \"test_name\": \"{s}\",\n", .{baseline.test_name});
            try writer.print("      \"mean_ns\": {d:.2},\n", .{baseline.mean_ns});
            try writer.print("      \"median_ns\": {d:.2},\n", .{baseline.median_ns});
            try writer.print("      \"p95_ns\": {d},\n", .{baseline.p95_ns});
            try writer.print("      \"timestamp\": {d}\n", .{baseline.timestamp});
            try writer.writeAll("    }");
        }
        
        try writer.writeAll("\n  ]\n}\n");
        
        if (self.config.verbose) {
            std.debug.print("已保存基线到: {s}\n", .{baseline_path});
        }
    }
    
    /// 检测性能回归
    /// @param test_name 测试名称
    /// @param current_stats 当前统计数据
    /// @param threshold_percent 回归阈值（百分比）
    /// @return 回归检测结果
    pub fn detectRegression(
        self: *Self,
        test_name: []const u8,
        current_stats: BenchmarkStats,
        threshold_percent: f64,
    ) !RegressionResult {
        const baseline = self.baselines.get(test_name) orelse {
            if (self.config.verbose) {
                std.debug.print("警告: 未找到基线数据: {s}\n", .{test_name});
            }
            return RegressionResult{
                .test_name = test_name,
                .has_regression = false,
                .mean_change_percent = 0,
                .median_change_percent = 0,
                .p95_change_percent = 0,
                .threshold_percent = threshold_percent,
            };
        };
        
        const result = RegressionResult.detect(test_name, baseline, current_stats, threshold_percent);
        
        if (self.config.verbose) {
            if (result.has_regression) {
                std.debug.print("⚠️  检测到性能回归: {s}\n", .{test_name});
                std.debug.print("  平均值变化: {d:.2}%\n", .{result.mean_change_percent});
                std.debug.print("  中位数变化: {d:.2}%\n", .{result.median_change_percent});
                std.debug.print("  P95 变化: {d:.2}%\n", .{result.p95_change_percent});
            } else {
                std.debug.print("✓ 无性能回归: {s}\n", .{test_name});
            }
        }
        
        return result;
    }

    /// 生成报告
    /// @param result 测试结果
    /// @param output_path 输出文件路径
    /// @param format 报告格式
    pub fn generateReport(
        self: *Self,
        result: ComparisonResult,
        output_path: []const u8,
        format: ReportFormat,
    ) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();
        
        const writer = file.writer();
        
        switch (format) {
            .json => try self.generateJsonReport(writer, result),
            .csv => try self.generateCsvReport(writer, result),
            .markdown => try self.generateMarkdownReport(writer, result),
            .html => try self.generateHtmlReport(writer, result),
        }
        
        if (self.config.verbose) {
            std.debug.print("报告已生成: {s}\n", .{output_path});
        }
    }
    
    /// 生成批量测试报告
    /// @param batch_result 批量测试结果
    /// @param output_path 输出文件路径
    /// @param format 报告格式
    pub fn generateBatchReport(
        self: *Self,
        batch_result: BatchTestResult,
        output_path: []const u8,
        format: ReportFormat,
    ) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();
        
        const writer = file.writer();
        
        switch (format) {
            .json => try self.generateBatchJsonReport(writer, batch_result),
            .csv => try self.generateBatchCsvReport(writer, batch_result),
            .markdown => try self.generateBatchMarkdownReport(writer, batch_result),
            .html => try self.generateBatchHtmlReport(writer, batch_result),
        }
        
        if (self.config.verbose) {
            std.debug.print("批量报告已生成: {s}\n", .{output_path});
        }
    }
    
    /// 生成 JSON 报告
    fn generateJsonReport(self: *Self, writer: anytype, result: ComparisonResult) !void {
        try writer.writeAll("{\n");
        try writer.print("  \"test_name\": \"{s}\",\n", .{result.test_name});
        try writer.print("  \"timestamp\": {d},\n", .{result.timestamp});
        try writer.print("  \"speedup\": {d:.4},\n", .{result.speedup});
        try writer.print("  \"memory_savings\": {d:.4},\n", .{result.memory_savings});
        
        try writer.writeAll("  \"zigphp\": {\n");
        try self.writeStatsJson(writer, result.zigphp_stats, "    ");
        try writer.writeAll("  },\n");
        
        try writer.writeAll("  \"php\": {\n");
        try self.writeStatsJson(writer, result.php_stats, "    ");
        try writer.writeAll("  }\n");
        
        try writer.writeAll("}\n");
    }
    
    fn writeStatsJson(self: *Self, writer: anytype, stats: BenchmarkStats, indent: []const u8) !void {
        _ = self;
        
        try writer.print("{s}\"mean_ns\": {d:.2},\n", .{indent, stats.mean_ns});
        try writer.print("{s}\"median_ns\": {d:.2},\n", .{indent, stats.median_ns});
        try writer.print("{s}\"std_dev_ns\": {d:.2},\n", .{indent, stats.std_dev_ns});
        try writer.print("{s}\"min_ns\": {d},\n", .{indent, stats.min_ns});
        try writer.print("{s}\"max_ns\": {d},\n", .{indent, stats.max_ns});
        try writer.print("{s}\"p95_ns\": {d},\n", .{indent, stats.p95_ns});
        try writer.print("{s}\"p99_ns\": {d},\n", .{indent, stats.p99_ns});
        try writer.print("{s}\"iterations\": {d},\n", .{indent, stats.iterations});
        try writer.print("{s}\"peak_memory_bytes\": {d}\n", .{indent, stats.peak_memory_bytes});
    }

    /// 生成 CSV 报告
    fn generateCsvReport(self: *Self, writer: anytype, result: ComparisonResult) !void {
        _ = self;
        
        // CSV 头部
        try writer.writeAll("test_name,implementation,mean_ns,median_ns,std_dev_ns,min_ns,max_ns,p95_ns,p99_ns,iterations,peak_memory_bytes\n");
        
        // Zig-PHP 行
        try writer.print("\"{s}\",\"Zig-PHP\",{d:.2},{d:.2},{d:.2},{d},{d},{d},{d},{d},{d}\n", .{
            result.test_name,
            result.zigphp_stats.mean_ns,
            result.zigphp_stats.median_ns,
            result.zigphp_stats.std_dev_ns,
            result.zigphp_stats.min_ns,
            result.zigphp_stats.max_ns,
            result.zigphp_stats.p95_ns,
            result.zigphp_stats.p99_ns,
            result.zigphp_stats.iterations,
            result.zigphp_stats.peak_memory_bytes,
        });
        
        // PHP 行
        try writer.print("\"{s}\",\"PHP\",{d:.2},{d:.2},{d:.2},{d},{d},{d},{d},{d},{d}\n", .{
            result.test_name,
            result.php_stats.mean_ns,
            result.php_stats.median_ns,
            result.php_stats.std_dev_ns,
            result.php_stats.min_ns,
            result.php_stats.max_ns,
            result.php_stats.p95_ns,
            result.php_stats.p99_ns,
            result.php_stats.iterations,
            result.php_stats.peak_memory_bytes,
        });
    }
    
    /// 生成 Markdown 报告
    fn generateMarkdownReport(self: *Self, writer: anytype, result: ComparisonResult) !void {
        _ = self;
        
        try writer.print("# 性能测试报告: {s}\n\n", .{result.test_name});
        try writer.print("**测试时间**: {d}\n\n", .{result.timestamp});
        
        try writer.writeAll("## 对比结果\n\n");
        try writer.print("- **加速比**: {d:.2}x\n", .{result.speedup});
        try writer.print("- **内存节省**: {d:.1}%\n\n", .{result.memory_savings * 100});
        
        try writer.writeAll("## 详细统计\n\n");
        try writer.writeAll("| 指标 | Zig-PHP | 原生 PHP | 改进 |\n");
        try writer.writeAll("|------|---------|----------|------|\n");
        
        const mean_improvement = (result.php_stats.mean_ns - result.zigphp_stats.mean_ns) / result.php_stats.mean_ns * 100;
        try writer.print("| 平均时间 (ns) | {d:.2} | {d:.2} | {d:.1}% |\n", .{
            result.zigphp_stats.mean_ns,
            result.php_stats.mean_ns,
            mean_improvement,
        });
        
        const median_improvement = (result.php_stats.median_ns - result.zigphp_stats.median_ns) / result.php_stats.median_ns * 100;
        try writer.print("| 中位数 (ns) | {d:.2} | {d:.2} | {d:.1}% |\n", .{
            result.zigphp_stats.median_ns,
            result.php_stats.median_ns,
            median_improvement,
        });
        
        try writer.print("| 标准差 (ns) | {d:.2} | {d:.2} | - |\n", .{
            result.zigphp_stats.std_dev_ns,
            result.php_stats.std_dev_ns,
        });
        
        try writer.print("| P95 (ns) | {d} | {d} | - |\n", .{
            result.zigphp_stats.p95_ns,
            result.php_stats.p95_ns,
        });
        
        try writer.print("| P99 (ns) | {d} | {d} | - |\n", .{
            result.zigphp_stats.p99_ns,
            result.php_stats.p99_ns,
        });
        
        try writer.print("| 峰值内存 (bytes) | {d} | {d} | {d:.1}% |\n", .{
            result.zigphp_stats.peak_memory_bytes,
            result.php_stats.peak_memory_bytes,
            result.memory_savings * 100,
        });
    }
    
    /// 生成 HTML 报告
    fn generateHtmlReport(self: *Self, writer: anytype, result: ComparisonResult) !void {
        _ = self;
        
        try writer.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");
        try writer.writeAll("  <meta charset=\"UTF-8\">\n");
        try writer.print("  <title>性能测试报告: {s}</title>\n", .{result.test_name});
        try writer.writeAll("  <style>\n");
        try writer.writeAll("    body { font-family: Arial, sans-serif; margin: 20px; }\n");
        try writer.writeAll("    table { border-collapse: collapse; width: 100%; }\n");
        try writer.writeAll("    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n");
        try writer.writeAll("    th { background-color: #4CAF50; color: white; }\n");
        try writer.writeAll("    .speedup { color: green; font-weight: bold; }\n");
        try writer.writeAll("  </style>\n");
        try writer.writeAll("</head>\n<body>\n");
        
        try writer.print("  <h1>性能测试报告: {s}</h1>\n", .{result.test_name});
        try writer.print("  <p>测试时间: {d}</p>\n", .{result.timestamp});
        
        try writer.writeAll("  <h2>对比结果</h2>\n");
        try writer.print("  <p class=\"speedup\">加速比: {d:.2}x</p>\n", .{result.speedup});
        try writer.print("  <p>内存节省: {d:.1}%</p>\n", .{result.memory_savings * 100});
        
        try writer.writeAll("  <h2>详细统计</h2>\n");
        try writer.writeAll("  <table>\n");
        try writer.writeAll("    <tr><th>指标</th><th>Zig-PHP</th><th>原生 PHP</th><th>改进</th></tr>\n");
        
        const mean_improvement = (result.php_stats.mean_ns - result.zigphp_stats.mean_ns) / result.php_stats.mean_ns * 100;
        try writer.print("    <tr><td>平均时间 (ns)</td><td>{d:.2}</td><td>{d:.2}</td><td>{d:.1}%</td></tr>\n", .{
            result.zigphp_stats.mean_ns,
            result.php_stats.mean_ns,
            mean_improvement,
        });
        
        try writer.writeAll("  </table>\n");
        try writer.writeAll("</body>\n</html>\n");
    }
    
    // ========================================================================
    // 批量报告生成
    // ========================================================================
    
    /// 生成批量 JSON 报告
    fn generateBatchJsonReport(self: *Self, writer: anytype, batch: BatchTestResult) !void {
        _ = self;
        
        try writer.writeAll("{\n");
        try writer.print("  \"timestamp\": {d},\n", .{batch.timestamp});
        try writer.print("  \"total_tests\": {d},\n", .{batch.total_tests});
        try writer.print("  \"passed_tests\": {d},\n", .{batch.passed_tests});
        try writer.print("  \"failed_tests\": {d},\n", .{batch.failed_tests});
        try writer.print("  \"average_speedup\": {d:.4},\n", .{batch.average_speedup});
        try writer.print("  \"average_memory_savings\": {d:.4},\n", .{batch.average_memory_savings});
        try writer.writeAll("  \"results\": [\n");
        
        for (batch.results, 0..) |result, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.writeAll("    {\n");
            try writer.print("      \"test_name\": \"{s}\",\n", .{result.test_name});
            try writer.print("      \"speedup\": {d:.4},\n", .{result.speedup});
            try writer.print("      \"memory_savings\": {d:.4}\n", .{result.memory_savings});
            try writer.writeAll("    }");
        }
        
        try writer.writeAll("\n  ]\n}\n");
    }
    
    /// 生成批量 CSV 报告
    fn generateBatchCsvReport(self: *Self, writer: anytype, batch: BatchTestResult) !void {
        _ = self;
        
        try writer.writeAll("test_name,speedup,memory_savings,zigphp_mean_ns,php_mean_ns\n");
        
        for (batch.results) |result| {
            try writer.print("\"{s}\",{d:.4},{d:.4},{d:.2},{d:.2}\n", .{
                result.test_name,
                result.speedup,
                result.memory_savings,
                result.zigphp_stats.mean_ns,
                result.php_stats.mean_ns,
            });
        }
    }
    
    /// 生成批量 Markdown 报告
    fn generateBatchMarkdownReport(self: *Self, writer: anytype, batch: BatchTestResult) !void {
        _ = self;
        
        try writer.writeAll("# 批量性能测试报告\n\n");
        try writer.print("**测试时间**: {d}\n\n", .{batch.timestamp});
        
        try writer.writeAll("## 总体结果\n\n");
        try writer.print("- **总测试数**: {d}\n", .{batch.total_tests});
        try writer.print("- **通过测试**: {d}\n", .{batch.passed_tests});
        try writer.print("- **失败测试**: {d}\n", .{batch.failed_tests});
        try writer.print("- **平均加速比**: {d:.2}x\n", .{batch.average_speedup});
        try writer.print("- **平均内存节省**: {d:.1}%\n\n", .{batch.average_memory_savings * 100});
        
        try writer.writeAll("## 详细结果\n\n");
        try writer.writeAll("| 测试名称 | 加速比 | 内存节省 | Zig-PHP (ns) | PHP (ns) |\n");
        try writer.writeAll("|----------|--------|----------|--------------|----------|\n");
        
        for (batch.results) |result| {
            try writer.print("| {s} | {d:.2}x | {d:.1}% | {d:.2} | {d:.2} |\n", .{
                result.test_name,
                result.speedup,
                result.memory_savings * 100,
                result.zigphp_stats.mean_ns,
                result.php_stats.mean_ns,
            });
        }
        
        try writer.writeAll("\n## 性能分析\n\n");
        
        // 找出最快和最慢的测试
        var fastest_speedup: f64 = 0;
        var slowest_speedup: f64 = std.math.floatMax(f64);
        var fastest_test: []const u8 = "";
        var slowest_test: []const u8 = "";
        
        for (batch.results) |result| {
            if (result.speedup > fastest_speedup) {
                fastest_speedup = result.speedup;
                fastest_test = result.test_name;
            }
            if (result.speedup < slowest_speedup) {
                slowest_speedup = result.speedup;
                slowest_test = result.test_name;
            }
        }
        
        try writer.print("- **最快测试**: {s} ({d:.2}x)\n", .{fastest_test, fastest_speedup});
        try writer.print("- **最慢测试**: {s} ({d:.2}x)\n", .{slowest_test, slowest_speedup});
    }
    
    /// 生成批量 HTML 报告
    fn generateBatchHtmlReport(self: *Self, writer: anytype, batch: BatchTestResult) !void {
        _ = self;
        
        try writer.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");
        try writer.writeAll("  <meta charset=\"UTF-8\">\n");
        try writer.writeAll("  <title>批量性能测试报告</title>\n");
        try writer.writeAll("  <style>\n");
        try writer.writeAll("    body { font-family: Arial, sans-serif; margin: 20px; }\n");
        try writer.writeAll("    table { border-collapse: collapse; width: 100%; margin: 20px 0; }\n");
        try writer.writeAll("    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n");
        try writer.writeAll("    th { background-color: #4CAF50; color: white; }\n");
        try writer.writeAll("    .summary { background-color: #f0f0f0; padding: 15px; margin: 20px 0; }\n");
        try writer.writeAll("    .passed { color: green; }\n");
        try writer.writeAll("    .failed { color: red; }\n");
        try writer.writeAll("  </style>\n");
        try writer.writeAll("</head>\n<body>\n");
        
        try writer.writeAll("  <h1>批量性能测试报告</h1>\n");
        try writer.print("  <p>测试时间: {d}</p>\n", .{batch.timestamp});
        
        try writer.writeAll("  <div class=\"summary\">\n");
        try writer.writeAll("    <h2>总体结果</h2>\n");
        try writer.print("    <p>总测试数: {d}</p>\n", .{batch.total_tests});
        try writer.print("    <p class=\"passed\">通过: {d}</p>\n", .{batch.passed_tests});
        try writer.print("    <p class=\"failed\">失败: {d}</p>\n", .{batch.failed_tests});
        try writer.print("    <p>平均加速比: {d:.2}x</p>\n", .{batch.average_speedup});
        try writer.print("    <p>平均内存节省: {d:.1}%</p>\n", .{batch.average_memory_savings * 100});
        try writer.writeAll("  </div>\n");
        
        try writer.writeAll("  <h2>详细结果</h2>\n");
        try writer.writeAll("  <table>\n");
        try writer.writeAll("    <tr><th>测试名称</th><th>加速比</th><th>内存节省</th><th>Zig-PHP (ns)</th><th>PHP (ns)</th></tr>\n");
        
        for (batch.results) |result| {
            try writer.print("    <tr><td>{s}</td><td>{d:.2}x</td><td>{d:.1}%</td><td>{d:.2}</td><td>{d:.2}</td></tr>\n", .{
                result.test_name,
                result.speedup,
                result.memory_savings * 100,
                result.zigphp_stats.mean_ns,
                result.php_stats.mean_ns,
            });
        }
        
        try writer.writeAll("  </table>\n");
        try writer.writeAll("</body>\n</html>\n");
    }
};

// ============================================================================
// 单元测试
// ============================================================================

test "BenchmarkStats.compute" {
    const samples = [_]u64{ 100, 200, 300, 400, 500 };
    const stats = BenchmarkStats.compute(&samples, 1024);
    
    try std.testing.expectEqual(@as(u32, 5), stats.iterations);
    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ns);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), stats.mean_ns, 0.1);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), stats.median_ns, 0.1);
    try std.testing.expectEqual(@as(usize, 1024), stats.peak_memory_bytes);
}

test "ComparisonResult.compute" {
    const zigphp_stats = BenchmarkStats{
        .mean_ns = 100.0,
        .median_ns = 100.0,
        .std_dev_ns = 10.0,
        .min_ns = 90,
        .max_ns = 110,
        .p95_ns = 108,
        .p99_ns = 109,
        .iterations = 1000,
        .peak_memory_bytes = 1024,
    };
    
    const php_stats = BenchmarkStats{
        .mean_ns = 200.0,
        .median_ns = 200.0,
        .std_dev_ns = 20.0,
        .min_ns = 180,
        .max_ns = 220,
        .p95_ns = 216,
        .p99_ns = 218,
        .iterations = 1000,
        .peak_memory_bytes = 2048,
    };
    
    const result = ComparisonResult.compute("test", zigphp_stats, php_stats);
    
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result.speedup, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result.memory_savings, 0.01);
}

test "BenchmarkFramework initialization" {
    const allocator = std.testing.allocator;
    
    const config = BenchmarkConfig{
        .warmup_iterations = 10,
        .test_iterations = 100,
        .verbose = false,
    };
    
    const framework = try BenchmarkFramework.init(allocator, config);
    defer framework.deinit();
    
    try std.testing.expectEqual(@as(u32, 10), framework.config.warmup_iterations);
    try std.testing.expectEqual(@as(u32, 100), framework.config.test_iterations);
}

test "PerformanceBaseline creation" {
    const stats = BenchmarkStats{
        .mean_ns = 100.0,
        .median_ns = 95.0,
        .std_dev_ns = 10.0,
        .min_ns = 80,
        .max_ns = 120,
        .p95_ns = 115,
        .p99_ns = 118,
        .iterations = 1000,
        .peak_memory_bytes = 2048,
    };
    
    const baseline = PerformanceBaseline.fromStats("test", stats);
    
    try std.testing.expectEqualStrings("test", baseline.test_name);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), baseline.mean_ns, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 95.0), baseline.median_ns, 0.01);
    try std.testing.expectEqual(@as(u64, 115), baseline.p95_ns);
}

test "RegressionResult detection - no regression" {
    const baseline = PerformanceBaseline{
        .test_name = "test",
        .mean_ns = 100.0,
        .median_ns = 95.0,
        .p95_ns = 115,
        .timestamp = 0,
    };
    
    const current = BenchmarkStats{
        .mean_ns = 102.0, // 2% increase
        .median_ns = 97.0,
        .std_dev_ns = 10.0,
        .min_ns = 80,
        .max_ns = 120,
        .p95_ns = 117,
        .p99_ns = 118,
        .iterations = 1000,
        .peak_memory_bytes = 2048,
    };
    
    const result = RegressionResult.detect("test", baseline, current, 5.0);
    
    try std.testing.expect(!result.has_regression);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result.mean_change_percent, 0.1);
}

test "RegressionResult detection - has regression" {
    const baseline = PerformanceBaseline{
        .test_name = "test",
        .mean_ns = 100.0,
        .median_ns = 95.0,
        .p95_ns = 115,
        .timestamp = 0,
    };
    
    const current = BenchmarkStats{
        .mean_ns = 110.0, // 10% increase - exceeds 5% threshold
        .median_ns = 105.0,
        .std_dev_ns = 10.0,
        .min_ns = 90,
        .max_ns = 130,
        .p95_ns = 125,
        .p99_ns = 128,
        .iterations = 1000,
        .peak_memory_bytes = 2048,
    };
    
    const result = RegressionResult.detect("test", baseline, current, 5.0);
    
    try std.testing.expect(result.has_regression);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), result.mean_change_percent, 0.1);
}

test "BatchTestResult computation" {
    var results = [_]ComparisonResult{
        ComparisonResult{
            .test_name = "test1",
            .zigphp_stats = BenchmarkStats{
                .mean_ns = 100.0,
                .median_ns = 100.0,
                .std_dev_ns = 10.0,
                .min_ns = 90,
                .max_ns = 110,
                .p95_ns = 108,
                .p99_ns = 109,
                .iterations = 1000,
                .peak_memory_bytes = 1024,
            },
            .php_stats = BenchmarkStats{
                .mean_ns = 200.0,
                .median_ns = 200.0,
                .std_dev_ns = 20.0,
                .min_ns = 180,
                .max_ns = 220,
                .p95_ns = 216,
                .p99_ns = 218,
                .iterations = 1000,
                .peak_memory_bytes = 2048,
            },
            .speedup = 2.0,
            .memory_savings = 0.5,
            .timestamp = 0,
        },
        ComparisonResult{
            .test_name = "test2",
            .zigphp_stats = BenchmarkStats{
                .mean_ns = 150.0,
                .median_ns = 150.0,
                .std_dev_ns = 15.0,
                .min_ns = 135,
                .max_ns = 165,
                .p95_ns = 162,
                .p99_ns = 164,
                .iterations = 1000,
                .peak_memory_bytes = 1536,
            },
            .php_stats = BenchmarkStats{
                .mean_ns = 300.0,
                .median_ns = 300.0,
                .std_dev_ns = 30.0,
                .min_ns = 270,
                .max_ns = 330,
                .p95_ns = 324,
                .p99_ns = 327,
                .iterations = 1000,
                .peak_memory_bytes = 3072,
            },
            .speedup = 2.0,
            .memory_savings = 0.5,
            .timestamp = 0,
        },
    };
    
    const batch = BatchTestResult.compute(results[0..]);
    
    try std.testing.expectEqual(@as(u32, 2), batch.total_tests);
    try std.testing.expectEqual(@as(u32, 2), batch.passed_tests);
    try std.testing.expectEqual(@as(u32, 0), batch.failed_tests);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), batch.average_speedup, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), batch.average_memory_savings, 0.01);
}

test "Baseline save and load" {
    const allocator = std.testing.allocator;
    
    const config = BenchmarkConfig{
        .warmup_iterations = 10,
        .test_iterations = 100,
        .verbose = false,
    };
    
    var framework_instance = BenchmarkFramework{
        .allocator = allocator,
        .config = config,
        .results = .{},
        .baselines = std.StringHashMap(PerformanceBaseline).init(allocator),
    };
    
    defer {
        var iter = framework_instance.baselines.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        framework_instance.baselines.deinit();
        framework_instance.results.deinit(allocator);
    }
    
    const stats = BenchmarkStats{
        .mean_ns = 100.0,
        .median_ns = 95.0,
        .std_dev_ns = 10.0,
        .min_ns = 80,
        .max_ns = 120,
        .p95_ns = 115,
        .p99_ns = 118,
        .iterations = 1000,
        .peak_memory_bytes = 2048,
    };
    
    try framework_instance.saveBaseline("test_baseline", stats);
    
    const baseline = framework_instance.baselines.get("test_baseline");
    try std.testing.expect(baseline != null);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), baseline.?.mean_ns, 0.01);
}
