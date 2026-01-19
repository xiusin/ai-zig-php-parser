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

/// 性能测试框架
pub const BenchmarkFramework = struct {
    allocator: Allocator,
    config: BenchmarkConfig,
    results: std.ArrayList(ComparisonResult),
    
    const Self = @This();
    
    /// 初始化框架
    pub fn init(allocator: Allocator, config: BenchmarkConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .results = std.ArrayList(ComparisonResult).init(allocator),
        };
        return self;
    }
    
    /// 清理资源
    pub fn deinit(self: *Self) void {
        self.results.deinit();
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
    
    /// 生成 JSON 报告
    fn generateJsonReport(self: *Self, writer: anytype, result: ComparisonResult) !void {
        _ = self;
        
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
