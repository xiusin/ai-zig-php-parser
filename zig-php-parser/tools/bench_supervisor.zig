const std = @import("std");

const BenchmarkResult = struct {
    name: []const u8,
    time_ms: f64,
};

const BenchmarkSuite = struct {
    timestamp: i64,
    results: []BenchmarkResult,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var update_baseline = false;
    if (args.len > 1 and std.mem.eql(u8, args[1], "--update-baseline")) {
        update_baseline = true;
    }

    const php_bin = "zig-out/bin/php-interpreter";
    const bench_script = "examples/bench/performance_benchmark.php";
    const baseline_file = "examples/bench/baseline_results.json";

    std.debug.print("Running benchmark: {s} {s}\n", .{php_bin, bench_script});

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ php_bin, bench_script },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
         std.debug.print("Stdout captured: {d} bytes\n", .{result.stdout.len});
    } else {
         std.debug.print("Stdout is empty!\n", .{});
    }

    if (result.term.Exited != 0) {
        std.debug.print("Benchmark failed with exit code {d}\n", .{result.term.Exited});
        std.debug.print("Stderr: {s}\n", .{result.stderr});
        return error.BenchmarkFailed;
    }

    const current_results = try parseOutput(allocator, result.stdout);
    defer {
        for (current_results) |r| allocator.free(r.name);
        allocator.free(current_results);
    }

    // Print current results
    std.debug.print("\n=== Current Results ===\n", .{});
    for (current_results) |r| {
        std.debug.print("{s}: {d:.2} ms\n", .{r.name, r.time_ms});
    }

    if (update_baseline) {
        try saveBaseline(allocator, baseline_file, current_results);
        std.debug.print("\nBaseline updated successfully.\n", .{});
    } else {
        checkAgainstBaseline(allocator, baseline_file, current_results) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("\nNo baseline found. Saving current results as baseline.\n", .{});
                try saveBaseline(allocator, baseline_file, current_results);
            } else {
                return err;
            }
        };
    }
}

fn parseOutput(allocator: std.mem.Allocator, output: []const u8) ![]BenchmarkResult {
    var results = std.ArrayListUnmanaged(BenchmarkResult){};
    errdefer {
        for (results.items) |r| allocator.free(r.name);
        results.deinit(allocator);
    }

    var lines = std.mem.splitSequence(u8, output, "\n");
    var current_test_name: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len == 0) continue;

        if (std.mem.indexOf(u8, trimmed, ". ") != null and std.mem.indexOf(u8, trimmed, "Time:") == null) {
            // Likely a test header like "1. Integer Arithmetic..."
            if (current_test_name) |name| allocator.free(name);
            current_test_name = try allocator.dupe(u8, trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "Time:")) {
            if (current_test_name) |name| {
                // Parse "Time: 12.34 ms"
                var parts = std.mem.splitSequence(u8, trimmed, " ");
                _ = parts.next(); // "Time:"
                const time_str = parts.next() orelse continue;
                const time_ms = try std.fmt.parseFloat(f64, time_str);

                try results.append(allocator, .{
                    .name = try allocator.dupe(u8, name),
                    .time_ms = time_ms,
                });
            }
        }
    }
    if (current_test_name) |name| allocator.free(name);
    return results.toOwnedSlice(allocator);
}

fn saveBaseline(allocator: std.mem.Allocator, path: []const u8, results: []BenchmarkResult) !void {
    _ = allocator;
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    
    var buf: [1024]u8 = undefined;
    var s = try std.fmt.bufPrint(&buf, "{{\n  \"timestamp\": {d},\n  \"results\": [\n", .{std.time.timestamp()});
    try file.writeAll(s);

    for (results, 0..) |r, i| {
        s = try std.fmt.bufPrint(&buf, "    {{\n      \"name\": \"{s}\",\n      \"time_ms\": {d:.4}\n    }}", .{r.name, r.time_ms});
        try file.writeAll(s);
        if (i < results.len - 1) {
            try file.writeAll(",\n");
        } else {
            try file.writeAll("\n");
        }
    }
    try file.writeAll("  ]\n}\n");
}

fn checkAgainstBaseline(allocator: std.mem.Allocator, path: []const u8, current: []BenchmarkResult) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(BenchmarkSuite, allocator, content, .{});
    defer parsed.deinit();

    std.debug.print("\n=== Baseline Comparison ===\n", .{});
    var failed = false;

    for (current) |curr| {
        for (parsed.value.results) |base| {
            if (std.mem.eql(u8, curr.name, base.name)) {
                const diff = curr.time_ms - base.time_ms;
                const percent = (diff / base.time_ms) * 100.0;
                
                var status: []const u8 = "OK";
                if (percent > 5.0) {
                    status = "SLOW";
                    failed = true;
                } else if (percent < -5.0) {
                    status = "FAST";
                }

                std.debug.print("{s}: {d:.2}ms vs {d:.2}ms ({d:.2}%) [{s}]\n", 
                    .{curr.name, curr.time_ms, base.time_ms, percent, status});
                break;
            }
        }
    }

    if (failed) {
        std.debug.print("\nWARNING: Performance regression detected!\n", .{});
        return error.PerformanceRegression;
    } else {
        std.debug.print("\nPerformance is stable.\n", .{});
    }
}
