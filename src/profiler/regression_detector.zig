const std = @import("std");
const Allocator = std.mem.Allocator;

/// 基准测试结果
pub const BenchmarkResult = struct {
    name: []const u8,
    mean_time_ns: u64,
    std_dev_ns: u64,
    iterations: u32,
};

/// 基准测试结果集合
pub const BenchmarkResults = struct {
    allocator: Allocator,
    benchmarks: std.StringHashMap(BenchmarkResult),

    pub fn init(allocator: Allocator) BenchmarkResults {
        return BenchmarkResults{
            .allocator = allocator,
            .benchmarks = std.StringHashMap(BenchmarkResult).init(allocator),
        };
    }

    pub fn deinit(self: *BenchmarkResults) void {
        self.benchmarks.deinit();
    }

    pub fn add(self: *BenchmarkResults, result: BenchmarkResult) !void {
        try self.benchmarks.put(result.name, result);
    }

    pub fn get(self: *BenchmarkResults, name: []const u8) ?BenchmarkResult {
        return self.benchmarks.get(name);
    }
};

/// 性能回归检测器
pub const RegressionDetector = struct {
    allocator: Allocator,
    /// 基准测试结果
    baseline: BenchmarkResults,
    /// 回归阈值（百分比）
    threshold: f64,

    pub fn init(allocator: Allocator, baseline: BenchmarkResults, threshold: f64) RegressionDetector {
        return RegressionDetector{
            .allocator = allocator,
            .baseline = baseline,
            .threshold = threshold,
        };
    }

    pub fn deinit(self: *RegressionDetector) void {
        self.baseline.deinit();
    }

    pub fn compare(self: *RegressionDetector, current: BenchmarkResults, writer: anytype) !bool {
        var has_regression = false;

        try writer.writeAll("=== Performance Regression Report ===\n\n");

        var it = current.benchmarks.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const current_result = entry.value_ptr.*;

            const baseline_result = self.baseline.benchmarks.get(name) orelse {
                try writer.print("NEW: {s}\n", .{name});
                continue;
            };

            const change = @as(f64, @floatFromInt(current_result.mean_time_ns)) /
                @as(f64, @floatFromInt(baseline_result.mean_time_ns)) - 1.0;

            if (change > self.threshold) {
                has_regression = true;
                try writer.print("REGRESSION: {s}\n", .{name});
                try writer.print("  Baseline: {d} ns\n", .{baseline_result.mean_time_ns});
                try writer.print("  Current:  {d} ns\n", .{current_result.mean_time_ns});
                try writer.print("  Change:   {d:.2}%\n\n", .{change * 100});
            } else if (change < -self.threshold) {
                try writer.print("IMPROVEMENT: {s}\n", .{name});
                try writer.print("  Baseline: {d} ns\n", .{baseline_result.mean_time_ns});
                try writer.print("  Current:  {d} ns\n", .{current_result.mean_time_ns});
                try writer.print("  Change:   {d:.2}%\n\n", .{change * 100});
            }
        }

        return has_regression;
    }
};
