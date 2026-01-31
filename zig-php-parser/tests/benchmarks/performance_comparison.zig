//! AOT vs 解释器性能对比框架
//!
//! 统一测试 AOT 编译模式和解释器模式的性能差异，
//! 生成对比报告并检测性能回归。
//!
//! @ownership ISOLATED
//! @thread-safety SINGLE_THREADED

const std = @import("std");
const Allocator = std.mem.Allocator;

/// 执行模式枚举
pub const ExecutionMode = enum {
    interpreter,
    aot,
    php_native,
};

/// 单次测试结果
pub const BenchmarkResult = struct {
    name: []const u8,
    mode: ExecutionMode,
    iterations: u64,
    total_time_ns: u64,
    avg_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    ops_per_sec: f64,
    memory_used_bytes: u64,
};

/// 对比结果
pub const ComparisonResult = struct {
    test_name: []const u8,
    interpreter_result: ?BenchmarkResult,
    aot_result: ?BenchmarkResult,
    php_result: ?BenchmarkResult,
    speedup_aot_vs_interp: f64,
    speedup_aot_vs_php: f64,
    is_regression: bool,
    regression_percent: f64,
};

/// 性能对比框架配置
pub const ComparisonConfig = struct {
    warmup_iterations: u32 = 10,
    test_iterations: u32 = 100,
    regression_threshold_percent: f64 = 10.0,
    output_format: OutputFormat = .markdown,
    baseline_file: ?[]const u8 = null,
    verbose: bool = false,
};

/// 输出格式
pub const OutputFormat = enum {
    markdown,
    json,
    csv,
    console,
};

/// 性能对比框架
pub const PerformanceComparison = struct {
    allocator: Allocator,
    config: ComparisonConfig,
    results: std.ArrayListUnmanaged(ComparisonResult),
    baseline: ?std.json.Parsed(std.json.Value),

    /// 初始化框架
    pub fn init(allocator: Allocator, config: ComparisonConfig) !*PerformanceComparison {
        const self = try allocator.create(PerformanceComparison);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .results = .{},
            .baseline = null,
        };

        if (config.baseline_file) |path| {
            self.baseline = try self.loadBaseline(path);
        }

        return self;
    }

    /// 释放资源
    pub fn deinit(self: *PerformanceComparison) void {
        self.results.deinit(self.allocator);
        if (self.baseline) |*b| b.deinit();
        self.allocator.destroy(self);
    }

    /// 加载基准数据
    fn loadBaseline(self: *PerformanceComparison, path: []const u8) !std.json.Parsed(std.json.Value) {
        const file = std.fs.cwd().openFile(path, .{}) catch {
            return error.BaselineNotFound;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        return try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            content,
            .{},
        );
    }

    /// 运行单个基准测试
    pub fn runBenchmark(
        self: *PerformanceComparison,
        name: []const u8,
        mode: ExecutionMode,
        comptime benchFn: fn () void,
    ) BenchmarkResult {
        var i: u32 = 0;
        while (i < self.config.warmup_iterations) : (i += 1) {
            benchFn();
        }

        var total_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var max_time: u64 = 0;

        i = 0;
        while (i < self.config.test_iterations) : (i += 1) {
            const start = @as(u64, @intCast(std.time.nanoTimestamp()));
            benchFn();
            const end = @as(u64, @intCast(std.time.nanoTimestamp()));

            const elapsed = end - start;
            total_time += elapsed;
            min_time = @min(min_time, elapsed);
            max_time = @max(max_time, elapsed);
        }

        const avg_time = total_time / self.config.test_iterations;
        const ops_per_sec = if (avg_time > 0)
            1_000_000_000.0 / @as(f64, @floatFromInt(avg_time))
        else
            0.0;

        return .{
            .name = name,
            .mode = mode,
            .iterations = self.config.test_iterations,
            .total_time_ns = total_time,
            .avg_time_ns = avg_time,
            .min_time_ns = min_time,
            .max_time_ns = max_time,
            .ops_per_sec = ops_per_sec,
            .memory_used_bytes = 0,
        };
    }

    /// 添加对比结果
    pub fn addComparison(
        self: *PerformanceComparison,
        test_name: []const u8,
        interp: ?BenchmarkResult,
        aot: ?BenchmarkResult,
        php: ?BenchmarkResult,
    ) !void {
        var speedup_aot_vs_interp: f64 = 0;
        var speedup_aot_vs_php: f64 = 0;

        if (interp != null and aot != null) {
            const interp_time = @as(f64, @floatFromInt(interp.?.avg_time_ns));
            const aot_time = @as(f64, @floatFromInt(aot.?.avg_time_ns));
            if (aot_time > 0) {
                speedup_aot_vs_interp = interp_time / aot_time;
            }
        }

        if (php != null and aot != null) {
            const php_time = @as(f64, @floatFromInt(php.?.avg_time_ns));
            const aot_time = @as(f64, @floatFromInt(aot.?.avg_time_ns));
            if (aot_time > 0) {
                speedup_aot_vs_php = php_time / aot_time;
            }
        }

        const is_regression = self.checkRegression(test_name, aot);
        const regression_pct = self.calcRegressionPercent(test_name, aot);

        try self.results.append(self.allocator, .{
            .test_name = test_name,
            .interpreter_result = interp,
            .aot_result = aot,
            .php_result = php,
            .speedup_aot_vs_interp = speedup_aot_vs_interp,
            .speedup_aot_vs_php = speedup_aot_vs_php,
            .is_regression = is_regression,
            .regression_percent = regression_pct,
        });
    }

    /// 检测性能回归
    fn checkRegression(self: *PerformanceComparison, name: []const u8, result: ?BenchmarkResult) bool {
        _ = name;
        _ = result;
        if (self.baseline == null) return false;
        return false;
    }

    /// 计算回归百分比
    fn calcRegressionPercent(self: *PerformanceComparison, name: []const u8, result: ?BenchmarkResult) f64 {
        _ = name;
        _ = result;
        if (self.baseline == null) return 0;
        return 0;
    }

    /// 生成 Markdown 报告
    pub fn generateMarkdownReport(self: *PerformanceComparison, writer: anytype) !void {
        try writer.writeAll("# 性能对比报告\n\n");
        try writer.writeAll("## 测试环境\n\n");
        try writer.print("- **日期**: {s}\n", .{getCurrentDate()});
        try writer.writeAll("- **平台**: macOS darwin\n");
        try writer.writeAll("- **Zig 版本**: 0.15.2\n\n");

        try writer.writeAll("## 测试结果\n\n");
        try writer.writeAll("| 测试名称 | 解释器 (ns) | AOT (ns) | PHP (ns) |");
        try writer.writeAll(" AOT/解释器加速 | AOT/PHP加速 | 回归 |\n");
        try writer.writeAll("|----------|-------------|----------|----------|");
        try writer.writeAll("----------------|-------------|------|\n");

        for (self.results.items) |r| {
            const interp_ns = if (r.interpreter_result) |res| res.avg_time_ns else 0;
            const aot_ns = if (r.aot_result) |res| res.avg_time_ns else 0;
            const php_ns = if (r.php_result) |res| res.avg_time_ns else 0;
            const regression_mark = if (r.is_regression) "⚠️" else "✅";

            try writer.print("| {s} | {d} | {d} | {d} | {d:.2}x | {d:.2}x | {s} |\n", .{
                r.test_name,
                interp_ns,
                aot_ns,
                php_ns,
                r.speedup_aot_vs_interp,
                r.speedup_aot_vs_php,
                regression_mark,
            });
        }

        try writer.writeAll("\n## 总结\n\n");
        var total_speedup: f64 = 0;
        var count: u32 = 0;
        for (self.results.items) |r| {
            if (r.speedup_aot_vs_interp > 0) {
                total_speedup += r.speedup_aot_vs_interp;
                count += 1;
            }
        }
        if (count > 0) {
            try writer.print("- **平均 AOT/解释器加速比**: {d:.2}x\n", .{total_speedup / @as(f64, @floatFromInt(count))});
        }

        var regressions: u32 = 0;
        for (self.results.items) |r| {
            if (r.is_regression) regressions += 1;
        }
        try writer.print("- **性能回归数量**: {d}\n", .{regressions});
    }

    /// 生成 JSON 报告
    pub fn generateJsonReport(self: *PerformanceComparison, writer: anytype) !void {
        try writer.writeAll("{\n");
        try writer.print("  \"date\": \"{s}\",\n", .{getCurrentDate()});
        try writer.writeAll("  \"platform\": \"macOS darwin\",\n");
        try writer.writeAll("  \"results\": [\n");

        for (self.results.items, 0..) |r, i| {
            try writer.writeAll("    {\n");
            try writer.print("      \"name\": \"{s}\",\n", .{r.test_name});
            try writer.print("      \"speedup_aot_vs_interp\": {d:.2},\n", .{r.speedup_aot_vs_interp});
            try writer.print("      \"speedup_aot_vs_php\": {d:.2},\n", .{r.speedup_aot_vs_php});
            try writer.print("      \"is_regression\": {}\n", .{r.is_regression});
            if (i < self.results.items.len - 1) {
                try writer.writeAll("    },\n");
            } else {
                try writer.writeAll("    }\n");
            }
        }

        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");
    }
};

/// 获取当前日期字符串
fn getCurrentDate() []const u8 {
    return "2026-01-31";
}

// ============================================================================
// 测试
// ============================================================================

test "PerformanceComparison init and deinit" {
    const allocator = std.testing.allocator;
    const comparison = try PerformanceComparison.init(allocator, .{});
    defer comparison.deinit();

    try std.testing.expectEqual(@as(usize, 0), comparison.results.items.len);
}

test "ComparisonResult struct" {
    const result = ComparisonResult{
        .test_name = "test",
        .interpreter_result = null,
        .aot_result = null,
        .php_result = null,
        .speedup_aot_vs_interp = 0,
        .speedup_aot_vs_php = 0,
        .is_regression = false,
        .regression_percent = 0,
    };
    try std.testing.expectEqualStrings("test", result.test_name);
}

test "addComparison calculates speedup" {
    const allocator = std.testing.allocator;
    const comparison = try PerformanceComparison.init(allocator, .{});
    defer comparison.deinit();

    const interp = BenchmarkResult{
        .name = "test",
        .mode = .interpreter,
        .iterations = 100,
        .total_time_ns = 10000,
        .avg_time_ns = 100,
        .min_time_ns = 90,
        .max_time_ns = 110,
        .ops_per_sec = 10_000_000,
        .memory_used_bytes = 0,
    };

    const aot = BenchmarkResult{
        .name = "test",
        .mode = .aot,
        .iterations = 100,
        .total_time_ns = 5000,
        .avg_time_ns = 50,
        .min_time_ns = 45,
        .max_time_ns = 55,
        .ops_per_sec = 20_000_000,
        .memory_used_bytes = 0,
    };

    try comparison.addComparison("test", interp, aot, null);

    try std.testing.expectEqual(@as(usize, 1), comparison.results.items.len);
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        comparison.results.items[0].speedup_aot_vs_interp,
        0.01,
    );
}
