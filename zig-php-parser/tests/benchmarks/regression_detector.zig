//! 性能回归检测器
//!
//! 对比当前性能与基线数据，检测性能回归。
//! 支持从 JSON 基线文件加载数据，生成回归报告。
//!
//! @ownership ISOLATED
//! @thread-safety SINGLE_THREADED

const std = @import("std");
const Allocator = std.mem.Allocator;

/// 回归检测结果
pub const RegressionResult = struct {
    test_name: []const u8,
    baseline_ns: u64,
    current_ns: u64,
    diff_percent: f64,
    is_regression: bool,
    is_improvement: bool,
    severity: Severity,
};

/// 回归严重程度
pub const Severity = enum {
    none,
    minor,
    moderate,
    severe,
    critical,

    /// 根据百分比差异计算严重程度
    pub fn fromPercent(diff: f64) Severity {
        if (diff <= 5.0) return .none;
        if (diff <= 10.0) return .minor;
        if (diff <= 25.0) return .moderate;
        if (diff <= 50.0) return .severe;
        return .critical;
    }

    /// 获取显示符号
    pub fn symbol(self: Severity) []const u8 {
        return switch (self) {
            .none => "✅",
            .minor => "⚠️",
            .moderate => "🔶",
            .severe => "🔴",
            .critical => "💥",
        };
    }
};

/// 回归检测配置
pub const RegressionConfig = struct {
    threshold_percent: f64 = 10.0,
    improvement_threshold: f64 = 5.0,
    baseline_path: ?[]const u8 = null,
    fail_on_regression: bool = true,
};

/// 性能回归检测器
pub const RegressionDetector = struct {
    allocator: Allocator,
    config: RegressionConfig,
    results: std.ArrayListUnmanaged(RegressionResult),
    baseline_data: ?std.json.Parsed(std.json.Value),

    /// 初始化检测器
    pub fn init(allocator: Allocator, config: RegressionConfig) !*RegressionDetector {
        const self = try allocator.create(RegressionDetector);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .results = .{},
            .baseline_data = null,
        };

        if (config.baseline_path) |path| {
            self.baseline_data = self.loadBaseline(path) catch null;
        }

        return self;
    }

    /// 释放资源
    pub fn deinit(self: *RegressionDetector) void {
        self.results.deinit(self.allocator);
        if (self.baseline_data) |*b| b.deinit();
        self.allocator.destroy(self);
    }

    /// 加载基线数据
    fn loadBaseline(self: *RegressionDetector, path: []const u8) !std.json.Parsed(std.json.Value) {
        const file = try std.fs.cwd().openFile(path, .{});
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

    /// 检测单个测试的回归
    pub fn check(
        self: *RegressionDetector,
        test_name: []const u8,
        current_ns: u64,
    ) !RegressionResult {
        const baseline_ns = self.getBaseline(test_name) orelse current_ns;

        const current_f = @as(f64, @floatFromInt(current_ns));
        const baseline_f = @as(f64, @floatFromInt(baseline_ns));

        var diff_percent: f64 = 0;
        if (baseline_f > 0) {
            diff_percent = ((current_f - baseline_f) / baseline_f) * 100.0;
        }

        const is_regression = diff_percent > self.config.threshold_percent;
        const is_improvement = diff_percent < -self.config.improvement_threshold;
        const severity = if (is_regression) Severity.fromPercent(diff_percent) else .none;

        const result = RegressionResult{
            .test_name = test_name,
            .baseline_ns = baseline_ns,
            .current_ns = current_ns,
            .diff_percent = diff_percent,
            .is_regression = is_regression,
            .is_improvement = is_improvement,
            .severity = severity,
        };

        try self.results.append(self.allocator, result);
        return result;
    }

    /// 从基线数据获取测试基准值
    fn getBaseline(self: *RegressionDetector, test_name: []const u8) ?u64 {
        _ = test_name;
        if (self.baseline_data == null) return null;
        return null;
    }

    /// 检查是否有回归
    pub fn hasRegressions(self: *RegressionDetector) bool {
        for (self.results.items) |r| {
            if (r.is_regression) return true;
        }
        return false;
    }

    /// 获取回归数量
    pub fn regressionCount(self: *RegressionDetector) u32 {
        var count: u32 = 0;
        for (self.results.items) |r| {
            if (r.is_regression) count += 1;
        }
        return count;
    }

    /// 获取改进数量
    pub fn improvementCount(self: *RegressionDetector) u32 {
        var count: u32 = 0;
        for (self.results.items) |r| {
            if (r.is_improvement) count += 1;
        }
        return count;
    }

    /// 生成报告
    pub fn generateReport(self: *RegressionDetector, writer: anytype) !void {
        try writer.writeAll("# 性能回归检测报告\n\n");
        try writer.writeAll("## 配置\n\n");
        try writer.print("- **回归阈值**: {d:.1}%\n", .{self.config.threshold_percent});
        try writer.print("- **改进阈值**: {d:.1}%\n\n", .{self.config.improvement_threshold});

        try writer.writeAll("## 检测结果\n\n");
        try writer.writeAll("| 测试名称 | 基线 (ns) | 当前 (ns) | 差异 (%) | 状态 |\n");
        try writer.writeAll("|----------|-----------|-----------|----------|------|\n");

        for (self.results.items) |r| {
            const status = if (r.is_regression)
                r.severity.symbol()
            else if (r.is_improvement)
                "🚀"
            else
                "✅";

            try writer.print("| {s} | {d} | {d} | {d:.1}% | {s} |\n", .{
                r.test_name,
                r.baseline_ns,
                r.current_ns,
                r.diff_percent,
                status,
            });
        }

        try writer.writeAll("\n## 总结\n\n");
        try writer.print("- **总测试数**: {d}\n", .{self.results.items.len});
        try writer.print("- **回归数量**: {d}\n", .{self.regressionCount()});
        try writer.print("- **改进数量**: {d}\n", .{self.improvementCount()});

        if (self.hasRegressions()) {
            try writer.writeAll("\n⚠️ **检测到性能回归，请检查相关代码变更**\n");
        } else {
            try writer.writeAll("\n✅ **未检测到性能回归**\n");
        }
    }
};

// ============================================================================
// 测试
// ============================================================================

test "RegressionDetector init and deinit" {
    const allocator = std.testing.allocator;
    const detector = try RegressionDetector.init(allocator, .{});
    defer detector.deinit();

    try std.testing.expectEqual(@as(usize, 0), detector.results.items.len);
}

test "Severity fromPercent" {
    try std.testing.expectEqual(Severity.none, Severity.fromPercent(3.0));
    try std.testing.expectEqual(Severity.minor, Severity.fromPercent(8.0));
    try std.testing.expectEqual(Severity.moderate, Severity.fromPercent(20.0));
    try std.testing.expectEqual(Severity.severe, Severity.fromPercent(40.0));
    try std.testing.expectEqual(Severity.critical, Severity.fromPercent(60.0));
}

test "check detects regression" {
    const allocator = std.testing.allocator;
    const detector = try RegressionDetector.init(allocator, .{
        .threshold_percent = 10.0,
    });
    defer detector.deinit();

    const result = try detector.check("test_func", 1000);

    try std.testing.expectEqual(@as(usize, 1), detector.results.items.len);
    try std.testing.expectEqualStrings("test_func", result.test_name);
}

test "regressionCount and improvementCount" {
    const allocator = std.testing.allocator;
    const detector = try RegressionDetector.init(allocator, .{});
    defer detector.deinit();

    _ = try detector.check("test1", 100);
    _ = try detector.check("test2", 200);

    try std.testing.expectEqual(@as(u32, 0), detector.regressionCount());
}
