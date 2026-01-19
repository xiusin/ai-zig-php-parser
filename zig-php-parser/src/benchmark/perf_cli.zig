// 性能基线管理命令行工具

const std = @import("std");
const RegressionDetector = @import("regression_detector.zig").RegressionDetector;
const BenchmarkResult = @import("regression_detector.zig").BenchmarkResult;
const CIRunner = @import("ci_integration.zig").CIRunner;
const CIConfig = @import("ci_integration.zig").CIConfig;

const Command = enum {
    check,
    update,
    list,
    compare,
    reset,
    help,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        try printHelp();
        return;
    }
    
    const command = std.meta.stringToEnum(Command, args[1]) orelse {
        std.debug.print("Unknown command: {s}\n", .{args[1]});
        try printHelp();
        return;
    };
    
    switch (command) {
        .check => try runCheck(allocator, args[2..]),
        .update => try runUpdate(allocator, args[2..]),
        .list => try runList(allocator, args[2..]),
        .compare => try runCompare(allocator, args[2..]),
        .reset => try runReset(allocator, args[2..]),
        .help => try printHelp(),
    }
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\Performance Baseline Management Tool
        \\
        \\Usage: perf-cli <command> [options]
        \\
        \\Commands:
        \\  check      - Run performance tests and check for regressions
        \\  update     - Update performance baselines
        \\  list       - List all baselines
        \\  compare    - Compare two sets of results
        \\  reset      - Reset all baselines
        \\  help       - Show this help message
        \\
        \\Options:
        \\  --baseline-dir <dir>    - Baseline directory (default: .perf_baselines)
        \\  --threshold <percent>   - Regression threshold (default: 5.0)
        \\  --commit <sha>          - Git commit SHA
        \\  --fail-on-regression    - Exit with error on regression
        \\
        \\Examples:
        \\  perf-cli check --threshold 10.0
        \\  perf-cli update --commit abc123
        \\  perf-cli list
        \\  perf-cli compare baseline1.json baseline2.json
        \\
    );
}

fn runCheck(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var config = try CIConfig.fromEnv(allocator);
    
    // 解析命令行参数
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--baseline-dir") and i + 1 < args.len) {
            config.baseline_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--threshold") and i + 1 < args.len) {
            config.threshold_percent = try std.fmt.parseFloat(f64, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--fail-on-regression")) {
            config.fail_on_regression = true;
        }
    }
    
    var runner = try CIRunner.init(allocator, config);
    
    std.debug.print("Running performance regression check...\n", .{});
    std.debug.print("Baseline directory: {s}\n", .{config.baseline_dir});
    std.debug.print("Regression threshold: {d:.1}%\n\n", .{config.threshold_percent});
    
    // 这里应该运行实际的基准测试
    // 为了演示，我们创建一些模拟结果
    const results = [_]BenchmarkResult{
        .{
            .benchmark_name = "string_operations",
            .avg_time_ns = 1500,
            .min_time_ns = 1400,
            .max_time_ns = 1600,
            .stddev_ns = 50.0,
            .iterations = 1000,
        },
        .{
            .benchmark_name = "array_operations",
            .avg_time_ns = 2500,
            .min_time_ns = 2300,
            .max_time_ns = 2700,
            .stddev_ns = 100.0,
            .iterations = 1000,
        },
    };
    
    const success = try runner.runAndCheck(&results);
    
    if (!success) {
        std.process.exit(1);
    }
}

fn runUpdate(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var baseline_dir: []const u8 = ".perf_baselines";
    var git_commit: []const u8 = "unknown";
    
    // 解析命令行参数
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--baseline-dir") and i + 1 < args.len) {
            baseline_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--commit") and i + 1 < args.len) {
            git_commit = args[i + 1];
            i += 1;
        }
    }
    
    var detector = try RegressionDetector.init(allocator, baseline_dir, 5.0);
    
    std.debug.print("Updating performance baselines...\n", .{});
    std.debug.print("Baseline directory: {s}\n", .{baseline_dir});
    std.debug.print("Git commit: {s}\n\n", .{git_commit});
    
    // 这里应该运行实际的基准测试
    const results = [_]BenchmarkResult{
        .{
            .benchmark_name = "string_operations",
            .avg_time_ns = 1500,
            .min_time_ns = 1400,
            .max_time_ns = 1600,
            .stddev_ns = 50.0,
            .iterations = 1000,
        },
    };
    
    try detector.updateBaselines(&results, git_commit);
    
    std.debug.print("✅ Baselines updated successfully\n", .{});
}

fn runList(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var baseline_dir: []const u8 = ".perf_baselines";
    
    // 解析命令行参数
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--baseline-dir") and i + 1 < args.len) {
            baseline_dir = args[i + 1];
            i += 1;
        }
    }
    
    std.debug.print("Performance Baselines in {s}:\n\n", .{baseline_dir});
    
    var dir = try std.fs.cwd().openDir(baseline_dir, .{ .iterate = true });
    defer dir.close();
    
    var iter = dir.iterate();
    var count: usize = 0;
    
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
            count += 1;
            
            // 读取基线文件
            const file = try dir.openFile(entry.name, .{});
            defer file.close();
            
            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(content);
            
            const parsed = try std.json.parseFromSlice(
                @import("regression_detector.zig").PerformanceBaseline,
                allocator,
                content,
                .{},
            );
            defer parsed.deinit();
            
            const baseline = parsed.value;
            
            std.debug.print("{d}. {s}\n", .{ count, baseline.benchmark_name });
            std.debug.print("   Average: {d} ns\n", .{baseline.avg_time_ns});
            std.debug.print("   Std Dev: {d:.2} ns\n", .{baseline.stddev_ns});
            std.debug.print("   Commit:  {s}\n", .{baseline.git_commit});
            std.debug.print("   Updated: {d}\n\n", .{baseline.timestamp});
        }
    }
    
    if (count == 0) {
        std.debug.print("No baselines found.\n", .{});
    } else {
        std.debug.print("Total: {d} baseline(s)\n", .{count});
    }
}

fn runCompare(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: perf-cli compare <file1> <file2>\n", .{});
        return;
    }
    
    const file1_path = args[0];
    const file2_path = args[1];
    
    std.debug.print("Comparing performance results:\n", .{});
    std.debug.print("  File 1: {s}\n", .{file1_path});
    std.debug.print("  File 2: {s}\n\n", .{file2_path});
    
    // 读取两个文件
    const file1 = try std.fs.cwd().openFile(file1_path, .{});
    defer file1.close();
    
    const file2 = try std.fs.cwd().openFile(file2_path, .{});
    defer file2.close();
    
    const content1 = try file1.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content1);
    
    const content2 = try file2.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content2);
    
    const parsed1 = try std.json.parseFromSlice(
        @import("regression_detector.zig").PerformanceBaseline,
        allocator,
        content1,
        .{},
    );
    defer parsed1.deinit();
    
    const parsed2 = try std.json.parseFromSlice(
        @import("regression_detector.zig").PerformanceBaseline,
        allocator,
        content2,
        .{},
    );
    defer parsed2.deinit();
    
    const baseline1 = parsed1.value;
    const baseline2 = parsed2.value;
    
    const avg1 = @as(f64, @floatFromInt(baseline1.avg_time_ns));
    const avg2 = @as(f64, @floatFromInt(baseline2.avg_time_ns));
    const change_percent = ((avg2 - avg1) / avg1) * 100.0;
    
    std.debug.print("Benchmark: {s}\n\n", .{baseline1.benchmark_name});
    std.debug.print("File 1:\n", .{});
    std.debug.print("  Average: {d} ns\n", .{baseline1.avg_time_ns});
    std.debug.print("  Std Dev: {d:.2} ns\n", .{baseline1.stddev_ns});
    std.debug.print("  Commit:  {s}\n\n", .{baseline1.git_commit});
    
    std.debug.print("File 2:\n", .{});
    std.debug.print("  Average: {d} ns\n", .{baseline2.avg_time_ns});
    std.debug.print("  Std Dev: {d:.2} ns\n", .{baseline2.stddev_ns});
    std.debug.print("  Commit:  {s}\n\n", .{baseline2.git_commit});
    
    const sign = if (change_percent >= 0) "+" else "";
    std.debug.print("Change: {s}{d:.2}%\n", .{ sign, change_percent });
    
    if (change_percent > 5.0) {
        std.debug.print("⚠️  Performance regression detected!\n", .{});
    } else if (change_percent < -5.0) {
        std.debug.print("✅ Performance improvement!\n", .{});
    } else {
        std.debug.print("✅ Performance stable\n", .{});
    }
}

fn runReset(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var baseline_dir: []const u8 = ".perf_baselines";
    
    // 解析命令行参数
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--baseline-dir") and i + 1 < args.len) {
            baseline_dir = args[i + 1];
            i += 1;
        }
    }
    
    std.debug.print("⚠️  This will delete all baselines in {s}\n", .{baseline_dir});
    std.debug.print("Are you sure? (y/N): ", .{});
    
    const stdin = std.io.getStdIn().reader();
    var buf: [10]u8 = undefined;
    const input = try stdin.readUntilDelimiterOrEof(&buf, '\n');
    
    if (input) |line| {
        if (std.mem.eql(u8, std.mem.trim(u8, line, &std.ascii.whitespace), "y")) {
            try std.fs.cwd().deleteTree(baseline_dir);
            std.debug.print("✅ All baselines deleted\n", .{});
        } else {
            std.debug.print("Cancelled\n", .{});
        }
    }
}
