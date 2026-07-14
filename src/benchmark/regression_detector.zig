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
    alloc_bytes: ?u64 = null,
    alloc_count: ?u64 = null,
    alloc_peak_live_bytes: ?u64 = null,
    alloc_peak_live_allocs: ?u64 = null,
    php_object_objects: ?u64 = null,
    php_object_live_objects: ?u64 = null,
    php_object_peak_live_objects: ?u64 = null,
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
    alloc_bytes: ?u64 = null,
    alloc_count: ?u64 = null,
    alloc_peak_live_bytes: ?u64 = null,
    alloc_peak_live_allocs: ?u64 = null,
    php_object_objects: ?u64 = null,
    php_object_live_objects: ?u64 = null,
    php_object_peak_live_objects: ?u64 = null,

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
    baseline_alloc_bytes: ?u64 = null,
    current_alloc_bytes: ?u64 = null,
    alloc_bytes_change_percent: ?f64 = null,
    baseline_alloc_count: ?u64 = null,
    current_alloc_count: ?u64 = null,
    alloc_count_change_percent: ?f64 = null,
    baseline_alloc_peak_live_bytes: ?u64 = null,
    current_alloc_peak_live_bytes: ?u64 = null,
    alloc_peak_live_bytes_change_percent: ?f64 = null,
    baseline_alloc_peak_live_allocs: ?u64 = null,
    current_alloc_peak_live_allocs: ?u64 = null,
    alloc_peak_live_allocs_change_percent: ?f64 = null,

    baseline_php_object_objects: ?u64 = null,
    current_php_object_objects: ?u64 = null,
    php_object_objects_change_percent: ?f64 = null,

    baseline_php_object_live_objects: ?u64 = null,
    current_php_object_live_objects: ?u64 = null,
    php_object_live_objects_change_percent: ?f64 = null,

    baseline_php_object_peak_live_objects: ?u64 = null,
    current_php_object_peak_live_objects: ?u64 = null,
    php_object_peak_live_objects_change_percent: ?f64 = null,

    pub fn format(
        self: RegressionResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const status = if (self.is_regression) "REGRESSION" else "OK";
        if (self.alloc_bytes_change_percent) |p| {
            try writer.print("{s}: {s} (time {d:.2}%, alloc_bytes {d:.2}%, baseline={d}ns, current={d}ns)", .{
                self.benchmark_name,
                status,
                self.regression_percent,
                p,
                self.baseline_avg_ns,
                self.current_avg_ns,
            });
            return;
        }
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
    threshold_percent: f64, // 时间回归阈值（百分比）
    mem_threshold_percent: f64, // 内存回归阈值（百分比）

    /// 初始化回归检测器
    /// @param allocator 内存分配器
    /// @param baseline_dir 基线数据目录
    /// @param threshold_percent 时间回归阈值（默认 5.0%）
    /// @param mem_threshold_percent 内存回归阈值（默认 1.0%）
    pub fn init(
        allocator: std.mem.Allocator,
        baseline_dir: []const u8,
        threshold_percent: f64,
        mem_threshold_percent: f64,
    ) !RegressionDetector {
        // 确保基线目录存在
        fs.cwd().makePath(baseline_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return RegressionDetector{
            .allocator = allocator,
            .baseline_dir = baseline_dir,
            .threshold_percent = threshold_percent,
            .mem_threshold_percent = mem_threshold_percent,
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
            .alloc_bytes = result.alloc_bytes,
            .alloc_count = result.alloc_count,
            .alloc_peak_live_bytes = result.alloc_peak_live_bytes,
            .alloc_peak_live_allocs = result.alloc_peak_live_allocs,
            .php_object_objects = result.php_object_objects,
            .php_object_live_objects = result.php_object_live_objects,
            .php_object_peak_live_objects = result.php_object_peak_live_objects,
            .timestamp = std.time.timestamp(),
            .git_commit = git_commit,
        };

        const filename = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.json",
            .{ self.baseline_dir, result.benchmark_name },
        );
        defer self.allocator.free(filename);

        const alloc_bytes_str = if (baseline.alloc_bytes) |v|
            try std.fmt.allocPrint(self.allocator, "{d}", .{v})
        else
            try self.allocator.dupe(u8, "null");
        defer self.allocator.free(alloc_bytes_str);

        const alloc_count_str = if (baseline.alloc_count) |v|
            try std.fmt.allocPrint(self.allocator, "{d}", .{v})
        else
            try self.allocator.dupe(u8, "null");
        defer self.allocator.free(alloc_count_str);

        const alloc_peak_live_bytes_str = if (baseline.alloc_peak_live_bytes) |v|
            try std.fmt.allocPrint(self.allocator, "{d}", .{v})
        else
            try self.allocator.dupe(u8, "null");
        defer self.allocator.free(alloc_peak_live_bytes_str);

        const alloc_peak_live_allocs_str = if (baseline.alloc_peak_live_allocs) |v|
            try std.fmt.allocPrint(self.allocator, "{d}", .{v})
        else
            try self.allocator.dupe(u8, "null");
        defer self.allocator.free(alloc_peak_live_allocs_str);

        const php_object_objects_str = if (baseline.php_object_objects) |v|
            try std.fmt.allocPrint(self.allocator, "{d}", .{v})
        else
            try self.allocator.dupe(u8, "null");
        defer self.allocator.free(php_object_objects_str);

        const php_object_live_objects_str = if (baseline.php_object_live_objects) |v|
            try std.fmt.allocPrint(self.allocator, "{d}", .{v})
        else
            try self.allocator.dupe(u8, "null");
        defer self.allocator.free(php_object_live_objects_str);

        const php_object_peak_live_objects_str = if (baseline.php_object_peak_live_objects) |v|
            try std.fmt.allocPrint(self.allocator, "{d}", .{v})
        else
            try self.allocator.dupe(u8, "null");
        defer self.allocator.free(php_object_peak_live_objects_str);

        const json_content = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "benchmark_name": "{s}",
            \\  "avg_time_ns": {d},
            \\  "min_time_ns": {d},
            \\  "max_time_ns": {d},
            \\  "stddev_ns": {d},
            \\  "alloc_bytes": {s},
            \\  "alloc_count": {s},
            \\  "alloc_peak_live_bytes": {s},
            \\  "alloc_peak_live_allocs": {s},
            \\  "php_object_objects": {s},
            \\  "php_object_live_objects": {s},
            \\  "php_object_peak_live_objects": {s},
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
            alloc_bytes_str,
            alloc_count_str,
            alloc_peak_live_bytes_str,
            alloc_peak_live_allocs_str,
            php_object_objects_str,
            php_object_live_objects_str,
            php_object_peak_live_objects_str,
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

            var alloc_bytes_change_percent: ?f64 = null;
            var alloc_count_change_percent: ?f64 = null;
            var alloc_peak_live_bytes_change_percent: ?f64 = null;
            var alloc_peak_live_allocs_change_percent: ?f64 = null;
            var php_object_objects_change_percent: ?f64 = null;
            var php_object_live_objects_change_percent: ?f64 = null;
            var php_object_peak_live_objects_change_percent: ?f64 = null;
            var alloc_bytes_reg = false;
            var alloc_count_reg = false;
            var alloc_peak_live_bytes_reg = false;
            var alloc_peak_live_allocs_reg = false;
            var php_object_objects_reg = false;
            var php_object_live_objects_reg = false;
            var php_object_peak_live_objects_reg = false;

            if (baseline.alloc_bytes) |b| {
                if (result.alloc_bytes) |c| {
                    if (b > 0) {
                        const bf = @as(f64, @floatFromInt(b));
                        const cf = @as(f64, @floatFromInt(c));
                        const p = ((cf - bf) / bf) * 100.0;
                        alloc_bytes_change_percent = p;
                        alloc_bytes_reg = p > self.mem_threshold_percent;
                    }
                }
            }

            if (baseline.alloc_count) |b| {
                if (result.alloc_count) |c| {
                    if (b > 0) {
                        const bf = @as(f64, @floatFromInt(b));
                        const cf = @as(f64, @floatFromInt(c));
                        const p = ((cf - bf) / bf) * 100.0;
                        alloc_count_change_percent = p;
                        alloc_count_reg = p > self.mem_threshold_percent;
                    }
                }
            }

            if (baseline.alloc_peak_live_bytes) |b| {
                if (result.alloc_peak_live_bytes) |c| {
                    if (b > 0) {
                        const bf = @as(f64, @floatFromInt(b));
                        const cf = @as(f64, @floatFromInt(c));
                        const p = ((cf - bf) / bf) * 100.0;
                        alloc_peak_live_bytes_change_percent = p;
                        alloc_peak_live_bytes_reg = p > self.mem_threshold_percent;
                    }
                }
            }

            if (baseline.alloc_peak_live_allocs) |b| {
                if (result.alloc_peak_live_allocs) |c| {
                    if (b > 0) {
                        const bf = @as(f64, @floatFromInt(b));
                        const cf = @as(f64, @floatFromInt(c));
                        const p = ((cf - bf) / bf) * 100.0;
                        alloc_peak_live_allocs_change_percent = p;
                        alloc_peak_live_allocs_reg = p > self.mem_threshold_percent;
                    }
                }
            }

            if (baseline.php_object_objects) |b| {
                if (result.php_object_objects) |c| {
                    if (b > 0) {
                        const bf = @as(f64, @floatFromInt(b));
                        const cf = @as(f64, @floatFromInt(c));
                        const p = ((cf - bf) / bf) * 100.0;
                        php_object_objects_change_percent = p;
                        php_object_objects_reg = p > self.mem_threshold_percent;
                    }
                }
            }

            if (baseline.php_object_live_objects) |b| {
                if (result.php_object_live_objects) |c| {
                    if (b > 0) {
                        const bf = @as(f64, @floatFromInt(b));
                        const cf = @as(f64, @floatFromInt(c));
                        const p = ((cf - bf) / bf) * 100.0;
                        php_object_live_objects_change_percent = p;
                        php_object_live_objects_reg = p > self.mem_threshold_percent;
                    }
                }
            }

            if (baseline.php_object_peak_live_objects) |b| {
                if (result.php_object_peak_live_objects) |c| {
                    if (b > 0) {
                        const bf = @as(f64, @floatFromInt(b));
                        const cf = @as(f64, @floatFromInt(c));
                        const p = ((cf - bf) / bf) * 100.0;
                        php_object_peak_live_objects_change_percent = p;
                        php_object_peak_live_objects_reg = p > self.mem_threshold_percent;
                    }
                }
            }

            const is_regression = (change_percent > self.threshold_percent) or alloc_bytes_reg or alloc_count_reg or alloc_peak_live_bytes_reg or alloc_peak_live_allocs_reg or php_object_objects_reg or php_object_live_objects_reg or php_object_peak_live_objects_reg;

            return RegressionResult{
                .benchmark_name = result.benchmark_name,
                .baseline_avg_ns = baseline.avg_time_ns,
                .current_avg_ns = result.avg_time_ns,
                .regression_percent = change_percent,
                .is_regression = is_regression,
                .baseline_alloc_bytes = baseline.alloc_bytes,
                .current_alloc_bytes = result.alloc_bytes,
                .alloc_bytes_change_percent = alloc_bytes_change_percent,
                .baseline_alloc_count = baseline.alloc_count,
                .current_alloc_count = result.alloc_count,
                .alloc_count_change_percent = alloc_count_change_percent,
                .baseline_alloc_peak_live_bytes = baseline.alloc_peak_live_bytes,
                .current_alloc_peak_live_bytes = result.alloc_peak_live_bytes,
                .alloc_peak_live_bytes_change_percent = alloc_peak_live_bytes_change_percent,
                .baseline_alloc_peak_live_allocs = baseline.alloc_peak_live_allocs,
                .current_alloc_peak_live_allocs = result.alloc_peak_live_allocs,
                .alloc_peak_live_allocs_change_percent = alloc_peak_live_allocs_change_percent,
                .baseline_php_object_objects = baseline.php_object_objects,
                .current_php_object_objects = result.php_object_objects,
                .php_object_objects_change_percent = php_object_objects_change_percent,
                .baseline_php_object_live_objects = baseline.php_object_live_objects,
                .current_php_object_live_objects = result.php_object_live_objects,
                .php_object_live_objects_change_percent = php_object_live_objects_change_percent,
                .baseline_php_object_peak_live_objects = baseline.php_object_peak_live_objects,
                .current_php_object_peak_live_objects = result.php_object_peak_live_objects,
                .php_object_peak_live_objects_change_percent = php_object_peak_live_objects_change_percent,
            };
        } else {
            // 没有基线数据，不算回归
            return RegressionResult{
                .benchmark_name = result.benchmark_name,
                .baseline_avg_ns = 0,
                .current_avg_ns = result.avg_time_ns,
                .regression_percent = 0.0,
                .is_regression = false,
                .baseline_alloc_bytes = null,
                .current_alloc_bytes = result.alloc_bytes,
                .alloc_bytes_change_percent = null,
                .baseline_alloc_count = null,
                .current_alloc_count = result.alloc_count,
                .alloc_count_change_percent = null,
                .baseline_alloc_peak_live_bytes = null,
                .current_alloc_peak_live_bytes = result.alloc_peak_live_bytes,
                .alloc_peak_live_bytes_change_percent = null,
                .baseline_alloc_peak_live_allocs = null,
                .current_alloc_peak_live_allocs = result.alloc_peak_live_allocs,
                .alloc_peak_live_allocs_change_percent = null,
                .baseline_php_object_objects = null,
                .current_php_object_objects = result.php_object_objects,
                .php_object_objects_change_percent = null,
                .baseline_php_object_live_objects = null,
                .current_php_object_live_objects = result.php_object_live_objects,
                .php_object_live_objects_change_percent = null,
                .baseline_php_object_peak_live_objects = null,
                .current_php_object_peak_live_objects = result.php_object_peak_live_objects,
                .php_object_peak_live_objects_change_percent = null,
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
            \\时间阈值: {d:.1}%
            \\内存阈值: {d:.1}%
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
            self.mem_threshold_percent,
            regressions.len,
            regression_count,
            regressions.len - regression_count,
        });
        defer self.allocator.free(header);

        try file.writeAll(header);

        // 如果有回归，生成回归表格和摘要
        if (regression_count > 0) {
            // 生成 Top 回归摘要
            try file.writeAll("## 🚨 Top 回归摘要\n\n");

            // 复制索引以便排序
            const indices = try self.allocator.alloc(usize, regressions.len);
            defer self.allocator.free(indices);
            for (indices, 0..) |*idx, i| idx.* = i;

            // 按时间回归幅度排序（降序）
            std.sort.block(usize, indices, regressions, struct {
                pub fn lessThan(context: []const RegressionResult, lhs: usize, rhs: usize) bool {
                    return context[lhs].regression_percent > context[rhs].regression_percent;
                }
            }.lessThan);

            try file.writeAll("### ⏳ 时间回归 Top 3\n");
            var count: usize = 0;
            for (indices) |idx| {
                const reg = regressions[idx];
                if (reg.is_regression and reg.regression_percent > self.threshold_percent) {
                    const line = try std.fmt.allocPrint(self.allocator, "- **{s}**: +{d:.2}% (当前: {d}ns)\n", .{ reg.benchmark_name, reg.regression_percent, reg.current_avg_ns });
                    defer self.allocator.free(line);
                    try file.writeAll(line);
                    count += 1;
                    if (count >= 3) break;
                }
            }
            if (count == 0) try file.writeAll("- 无显著时间回归\n");
            try file.writeAll("\n");

            // 按内存回归幅度排序（使用 alloc_bytes）
            std.sort.block(usize, indices, regressions, struct {
                pub fn lessThan(context: []const RegressionResult, lhs: usize, rhs: usize) bool {
                    const l = context[lhs].alloc_bytes_change_percent orelse -100.0;
                    const r = context[rhs].alloc_bytes_change_percent orelse -100.0;
                    return l > r;
                }
            }.lessThan);

            try file.writeAll("### 💾 内存回归 Top 3\n");
            count = 0;
            for (indices) |idx| {
                const reg = regressions[idx];
                const mem_pct = reg.alloc_bytes_change_percent orelse 0.0;
                if (reg.is_regression and mem_pct > self.mem_threshold_percent) {
                    const line = try std.fmt.allocPrint(self.allocator, "- **{s}**: +{d:.2}% (当前: {d} bytes)\n", .{ reg.benchmark_name, mem_pct, reg.current_alloc_bytes orelse 0 });
                    defer self.allocator.free(line);
                    try file.writeAll(line);
                    count += 1;
                    if (count >= 3) break;
                }
            }
            if (count == 0) try file.writeAll("- 无显著内存回归\n");
            try file.writeAll("\n");

            const regression_header =
                \\## ⚠️ 详细回归列表
                \\
                \\| 基准测试 | 基线 (ns) | 当前 (ns) | 变化 (%) | 基线 alloc_bytes | 当前 alloc_bytes | alloc_bytes Δ% | 基线 peak_live_bytes | 当前 peak_live_bytes | peak_live_bytes Δ% | 基线 Obj Allocs | 当前 Obj Allocs | Obj Allocs Δ% | 基线 Obj Peak | 当前 Obj Peak | Obj Peak Δ% | 状态 |
                \\|---------|----------|----------|---------|-----------------|-----------------|--------------|----------------------|----------------------|-------------------|-----------------|-----------------|--------------|---------------|--------------|-------------|------|
                \\
            ;
            try file.writeAll(regression_header);

            for (regressions) |reg| {
                if (reg.is_regression) {
                    const b_ab = reg.baseline_alloc_bytes orelse 0;
                    const c_ab = reg.current_alloc_bytes orelse 0;
                    const abp = reg.alloc_bytes_change_percent orelse 0.0;
                    const b_plb = reg.baseline_alloc_peak_live_bytes orelse 0;
                    const c_plb = reg.current_alloc_peak_live_bytes orelse 0;
                    const plbp = reg.alloc_peak_live_bytes_change_percent orelse 0.0;

                    const b_oa = reg.baseline_php_object_objects orelse 0;
                    const c_oa = reg.current_php_object_objects orelse 0;
                    const oap = reg.php_object_objects_change_percent orelse 0.0;
                    const b_op = reg.baseline_php_object_peak_live_objects orelse 0;
                    const c_op = reg.current_php_object_peak_live_objects orelse 0;
                    const opp = reg.php_object_peak_live_objects_change_percent orelse 0.0;

                    // 判断状态详情
                    var status_slice: []const u8 = "❌ REGRESSION";

                    const time_reg = reg.regression_percent > self.threshold_percent;
                    const mem_reg = (abp > self.mem_threshold_percent) or (plbp > self.mem_threshold_percent) or (oap > self.mem_threshold_percent) or (opp > self.mem_threshold_percent);

                    if (time_reg and mem_reg) {
                        status_slice = "❌ TIME+MEM";
                    } else if (time_reg) {
                        status_slice = "❌ TIME";
                    } else if (mem_reg) {
                        status_slice = "❌ MEM";
                    }

                    const row = try std.fmt.allocPrint(
                        self.allocator,
                        "| {s} | {d} | {d} | +{d:.2} | {d} | {d} | +{d:.2} | {d} | {d} | +{d:.2} | {d} | {d} | +{d:.2} | {d} | {d} | +{d:.2} | {s} |\n",
                        .{
                            reg.benchmark_name,
                            reg.baseline_avg_ns,
                            reg.current_avg_ns,
                            reg.regression_percent,
                            b_ab,
                            c_ab,
                            abp,
                            b_plb,
                            c_plb,
                            plbp,
                            b_oa,
                            c_oa,
                            oap,
                            b_op,
                            c_op,
                            opp,
                            status_slice,
                        },
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
            \\| 基准测试 | 基线 (ns) | 当前 (ns) | 变化 (%) | 基线 alloc_bytes | 当前 alloc_bytes | alloc_bytes Δ% | 基线 peak_live_bytes | 当前 peak_live_bytes | peak_live_bytes Δ% | 基线 Obj Allocs | 当前 Obj Allocs | Obj Allocs Δ% | 基线 Obj Peak | 当前 Obj Peak | Obj Peak Δ% | 状态 |
            \\|---------|----------|----------|---------|-----------------|-----------------|--------------|----------------------|----------------------|-------------------|-----------------|-----------------|--------------|---------------|--------------|-------------|------|
            \\
        ;
        try file.writeAll(all_results_header);

        for (regressions) |reg| {
            var status: []const u8 = "✅";
            if (reg.is_regression) {
                const abp = reg.alloc_bytes_change_percent orelse 0.0;
                const plbp = reg.alloc_peak_live_bytes_change_percent orelse 0.0;
                const oap = reg.php_object_objects_change_percent orelse 0.0;
                const opp = reg.php_object_peak_live_objects_change_percent orelse 0.0;
                const time_reg = reg.regression_percent > self.threshold_percent;
                const mem_reg = (abp > self.mem_threshold_percent) or (plbp > self.mem_threshold_percent) or (oap > self.mem_threshold_percent) or (opp > self.mem_threshold_percent);

                if (time_reg and mem_reg) {
                    status = "❌ MIXED";
                } else if (time_reg) {
                    status = "❌ TIME";
                } else if (mem_reg) {
                    status = "❌ MEM";
                } else {
                    status = "❌ REG";
                }
            }

            const sign = if (reg.regression_percent >= 0) "+" else "";
            const ab_sign = if ((reg.alloc_bytes_change_percent orelse 0.0) >= 0) "+" else "";
            const plb_sign = if ((reg.alloc_peak_live_bytes_change_percent orelse 0.0) >= 0) "+" else "";
            const oa_sign = if ((reg.php_object_objects_change_percent orelse 0.0) >= 0) "+" else "";
            const op_sign = if ((reg.php_object_peak_live_objects_change_percent orelse 0.0) >= 0) "+" else "";

            const row = if (reg.baseline_avg_ns > 0) blk: {
                const b_ab_str = if (reg.baseline_alloc_bytes) |v|
                    try std.fmt.allocPrint(self.allocator, "{d}", .{v})
                else
                    try self.allocator.dupe(u8, "N/A");
                defer self.allocator.free(b_ab_str);

                const c_ab_str = if (reg.current_alloc_bytes) |v|
                    try std.fmt.allocPrint(self.allocator, "{d}", .{v})
                else
                    try self.allocator.dupe(u8, "N/A");
                defer self.allocator.free(c_ab_str);

                const b_plb_str = if (reg.baseline_alloc_peak_live_bytes) |v|
                    try std.fmt.allocPrint(self.allocator, "{d}", .{v})
                else
                    try self.allocator.dupe(u8, "N/A");
                defer self.allocator.free(b_plb_str);

                const c_plb_str = if (reg.current_alloc_peak_live_bytes) |v|
                    try std.fmt.allocPrint(self.allocator, "{d}", .{v})
                else
                    try self.allocator.dupe(u8, "N/A");
                defer self.allocator.free(c_plb_str);

                const b_oa_str = if (reg.baseline_php_object_objects) |v|
                    try std.fmt.allocPrint(self.allocator, "{d}", .{v})
                else
                    try self.allocator.dupe(u8, "N/A");
                defer self.allocator.free(b_oa_str);

                const c_oa_str = if (reg.current_php_object_objects) |v|
                    try std.fmt.allocPrint(self.allocator, "{d}", .{v})
                else
                    try self.allocator.dupe(u8, "N/A");
                defer self.allocator.free(c_oa_str);

                const b_op_str = if (reg.baseline_php_object_peak_live_objects) |v|
                    try std.fmt.allocPrint(self.allocator, "{d}", .{v})
                else
                    try self.allocator.dupe(u8, "N/A");
                defer self.allocator.free(b_op_str);

                const c_op_str = if (reg.current_php_object_peak_live_objects) |v|
                    try std.fmt.allocPrint(self.allocator, "{d}", .{v})
                else
                    try self.allocator.dupe(u8, "N/A");
                defer self.allocator.free(c_op_str);

                break :blk try std.fmt.allocPrint(
                    self.allocator,
                    "| {s} | {d} | {d} | {s}{d:.2} | {s} | {s} | {s}{d:.2} | {s} | {s} | {s}{d:.2} | {s} | {s} | {s}{d:.2} | {s} | {s} | {s}{d:.2} | {s} |\n",
                    .{
                        reg.benchmark_name,
                        reg.baseline_avg_ns,
                        reg.current_avg_ns,
                        sign,
                        reg.regression_percent,
                        b_ab_str,
                        c_ab_str,
                        ab_sign,
                        reg.alloc_bytes_change_percent orelse 0.0,
                        b_plb_str,
                        c_plb_str,
                        plb_sign,
                        reg.alloc_peak_live_bytes_change_percent orelse 0.0,
                        b_oa_str,
                        c_oa_str,
                        oa_sign,
                        reg.php_object_objects_change_percent orelse 0.0,
                        b_op_str,
                        c_op_str,
                        op_sign,
                        reg.php_object_peak_live_objects_change_percent orelse 0.0,
                        status,
                    },
                );
            } else try std.fmt.allocPrint(self.allocator, "| {s} | N/A | {d} | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | 🆕 NEW |\n", .{
                reg.benchmark_name,
                reg.current_avg_ns,
            });
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

    var detector = try RegressionDetector.init(allocator, test_dir, 5.0, 1.0);

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

    var detector = try RegressionDetector.init(allocator, test_dir, 5.0, 1.0);

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
