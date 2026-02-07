const std = @import("std");
const BenchmarkResult = @import("regression_detector.zig").BenchmarkResult;

const aot_rt = @import("aot_runtime");

pub fn runAll(allocator: std.mem.Allocator) ![]BenchmarkResult {
    var results = try std.ArrayList(BenchmarkResult).initCapacity(allocator, 3);
    errdefer results.deinit(allocator);

    try results.append(allocator, try benchAotArrayOps(allocator));
    try results.append(allocator, try benchAotStringConcat(allocator));
    try results.append(allocator, try benchAotCallableInvoke(allocator));

    return results.toOwnedSlice(allocator);
}

fn Stats(comptime N: usize) type {
    return struct {
        samples: [N]u64,
        iterations: u32,
    };
}

fn computeStats(comptime N: usize, name: []const u8, stats: Stats(N)) BenchmarkResult {
    var sum: f64 = 0;
    var min: u64 = std.math.maxInt(u64);
    var max: u64 = 0;
    for (stats.samples) |s| {
        sum += @as(f64, @floatFromInt(s));
        min = @min(min, s);
        max = @max(max, s);
    }
    const mean = sum / @as(f64, @floatFromInt(N));

    var var_sum: f64 = 0;
    for (stats.samples) |s| {
        const d = @as(f64, @floatFromInt(s)) - mean;
        var_sum += d * d;
    }
    const stddev = @sqrt(var_sum / @as(f64, @floatFromInt(N)));

    return .{
        .benchmark_name = name,
        .avg_time_ns = @intFromFloat(mean),
        .min_time_ns = min,
        .max_time_ns = max,
        .stddev_ns = stddev,
        .iterations = stats.iterations,
    };
}

fn measure(comptime N: usize, iterations: u32, func: *const fn () void) Stats(N) {
    for (0..3) |_| func();

    var samples: [N]u64 = undefined;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const start = std.time.nanoTimestamp();
        var j: u32 = 0;
        while (j < iterations) : (j += 1) {
            func();
        }
        const end = std.time.nanoTimestamp();
        samples[i] = @as(u64, @intCast(end - start));
    }
    return .{ .samples = samples, .iterations = iterations };
}

fn benchAotArrayOps(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();

    const f = struct {
        fn run() void {
            const a = aot_rt.PHPArray.init(aot_rt.runtime_allocator) catch return;
            defer a.release(aot_rt.runtime_allocator);

            var i: i64 = 0;
            while (i < 16) : (i += 1) {
                a.push(aot_rt.runtime_allocator, aot_rt.Value.initInt(i)) catch return;
            }
            _ = aot_rt.php_array_pop(aot_rt.Value.initArray(a), aot_rt.runtime_allocator) catch {};
            _ = aot_rt.php_array_shift(aot_rt.Value.initArray(a), aot_rt.runtime_allocator) catch {};
            _ = aot_rt.php_array_unshift(aot_rt.Value.initArray(a), &[_]aot_rt.Value{aot_rt.Value.initInt(0)}, aot_rt.runtime_allocator) catch {};
        }
    }.run;

    const stats = measure(20, 200, f);
    return computeStats(20, "aot_runtime_array_ops", stats);
}

fn benchAotStringConcat(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();

    const f = struct {
        fn run() void {
            const s1 = aot_rt.PHPString.init(aot_rt.runtime_allocator, "hello") catch return;
            const s2 = aot_rt.PHPString.init(aot_rt.runtime_allocator, "world") catch return;
            defer s1.release(aot_rt.runtime_allocator);
            defer s2.release(aot_rt.runtime_allocator);

            const out = s1.concat(s2, aot_rt.runtime_allocator) catch return;
            out.release(aot_rt.runtime_allocator);
        }
    }.run;

    const stats = measure(20, 200, f);
    return computeStats(20, "aot_runtime_string_concat", stats);
}

fn benchAotCallableInvoke(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();

    const add = struct {
        fn f(ctx: aot_rt.Value, args: []const aot_rt.Value, alloc: std.mem.Allocator) !aot_rt.Value {
            _ = ctx;
            _ = alloc;
            return aot_rt.php_add(args[0], args[1]);
        }
    }.f;

    const closure = try aot_rt.PHPClosure.init(allocator, add, &.{});
    defer closure.release(allocator);
    const cb = aot_rt.Value.initFunction(closure);
    const args = [_]aot_rt.Value{ aot_rt.Value.initInt(1), aot_rt.Value.initInt(2) };

    const f = struct {
        var callback: aot_rt.Value = undefined;
        var argv: []const aot_rt.Value = undefined;

        fn run() void {
            _ = aot_rt.php_invoke_callable(callback, argv, aot_rt.runtime_allocator) catch {};
        }
    };
    f.callback = cb;
    f.argv = args[0..];

    const stats = measure(20, 500, f.run);
    return computeStats(20, "aot_runtime_callable_invoke", stats);
}
