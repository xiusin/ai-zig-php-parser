const std = @import("std");
const BenchmarkResult = @import("regression_detector.zig").BenchmarkResult;

const aot_rt = @import("aot_runtime");
const aot = @import("aot");

pub fn runAll(allocator: std.mem.Allocator) ![]BenchmarkResult {
    var results = try std.ArrayList(BenchmarkResult).initCapacity(allocator, 11);
    errdefer results.deinit(allocator);

    try results.append(allocator, try benchAotArrayOps(allocator));
    try results.append(allocator, try benchAotArrayOpsLarge(allocator));
    try results.append(allocator, try benchAotStringConcat(allocator));
    try results.append(allocator, try benchAotStringSearch(allocator));
    try results.append(allocator, try benchAotCallableInvoke(allocator));
    try results.append(allocator, try benchAotArraySort(allocator));
    try results.append(allocator, try benchAotExceptionThrowClear(allocator));
    try results.append(allocator, try benchAotClosureCreateInvoke(allocator));
    try results.append(allocator, try benchAotObjectPropertyAccess(allocator));
    try results.append(allocator, try benchAotObjectLifecycle(allocator));
    try results.append(allocator, try benchAotCompilePipeline(allocator));

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

fn fillAllocFields(r: *BenchmarkResult) void {
    const mem = aot_rt.getAllocStats();
    r.alloc_bytes = mem.alloc_bytes;
    r.alloc_count = mem.alloc_count;
    r.alloc_peak_live_bytes = mem.peak_live_bytes;
    r.alloc_peak_live_allocs = mem.peak_live_allocs;
    r.php_object_objects = mem.php_object_objects;
    r.php_object_live_objects = mem.php_object_live_objects;
    r.php_object_peak_live_objects = mem.php_object_peak_live_objects;
}

fn benchAotArrayOps(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

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
    var r = computeStats(20, "aot_runtime_array_ops", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotArrayOpsLarge(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

    const f = struct {
        fn run() void {
            const a = aot_rt.PHPArray.init(aot_rt.runtime_allocator) catch return;
            defer a.release(aot_rt.runtime_allocator);

            var i: i64 = 0;
            while (i < 4096) : (i += 1) {
                a.push(aot_rt.runtime_allocator, aot_rt.Value.initInt(i)) catch return;
            }
            _ = aot_rt.php_array_pop(aot_rt.Value.initArray(a), aot_rt.runtime_allocator) catch {};
            _ = aot_rt.php_array_shift(aot_rt.Value.initArray(a), aot_rt.runtime_allocator) catch {};
            _ = aot_rt.php_array_unshift(aot_rt.Value.initArray(a), &[_]aot_rt.Value{aot_rt.Value.initInt(0)}, aot_rt.runtime_allocator) catch {};
        }
    }.run;

    const stats = measure(20, 10, f);
    var r = computeStats(20, "aot_runtime_array_ops_large", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotStringConcat(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

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

    const stats = measure(20, 2000, f);
    var r = computeStats(20, "aot_runtime_string_concat", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotStringSearch(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();

    const alphabet = "abcdefghijklmnopqrstuvwxyz";
    const hay_buf = try aot_rt.runtime_allocator.alloc(u8, alphabet.len * 256);
    defer aot_rt.runtime_allocator.free(hay_buf);
    for (0..256) |i| {
        const start = i * alphabet.len;
        @memcpy(hay_buf[start .. start + alphabet.len], alphabet);
    }

    const hay = try aot_rt.PHPString.init(aot_rt.runtime_allocator, hay_buf);
    defer hay.release(aot_rt.runtime_allocator);
    const needle = try aot_rt.PHPString.init(aot_rt.runtime_allocator, "wxyz");
    defer needle.release(aot_rt.runtime_allocator);
    aot_rt.resetAllocStats();

    const f = struct {
        var h: aot_rt.Value = undefined;
        var n: aot_rt.Value = undefined;

        fn run() void {
            _ = aot_rt.php_strpos(h, n, aot_rt.Value.initInt(0)) catch {};
        }
    };
    f.h = aot_rt.Value.initString(hay);
    f.n = aot_rt.Value.initString(needle);

    const stats = measure(20, 2000, f.run);
    var r = computeStats(20, "aot_runtime_string_search", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotCallableInvoke(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

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
    var r = computeStats(20, "aot_runtime_callable_invoke", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotArraySort(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

    const f = struct {
        fn run() void {
            const a = aot_rt.PHPArray.init(aot_rt.runtime_allocator) catch return;
            defer a.release(aot_rt.runtime_allocator);

            var i: i64 = 256;
            while (i > 0) : (i -= 1) {
                a.push(aot_rt.runtime_allocator, aot_rt.Value.initInt(i)) catch return;
            }
            _ = aot_rt.php_sort(aot_rt.Value.initArray(a), aot_rt.runtime_allocator) catch {};
        }
    }.run;

    const stats = measure(20, 30, f);
    var r = computeStats(20, "aot_runtime_array_sort", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotExceptionThrowClear(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

    const f = struct {
        fn run() void {
            _ = aot_rt.throwException("microbench exception", aot_rt.runtime_allocator) catch return;
            aot_rt.clearException();
        }
    }.run;

    const stats = measure(20, 500, f);
    var r = computeStats(20, "aot_runtime_exception_throw_clear", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotClosureCreateInvoke(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

    const add = struct {
        fn f(ctx: aot_rt.Value, args: []const aot_rt.Value, alloc: std.mem.Allocator) !aot_rt.Value {
            _ = ctx;
            _ = alloc;
            return aot_rt.php_add(args[0], args[1]);
        }
    }.f;

    const args = [_]aot_rt.Value{ aot_rt.Value.initInt(1), aot_rt.Value.initInt(2) };

    const f = struct {
        var argv: []const aot_rt.Value = undefined;

        fn run() void {
            const closure = aot_rt.PHPClosure.init(aot_rt.runtime_allocator, add, &.{}) catch return;
            defer closure.release(aot_rt.runtime_allocator);

            const cb = aot_rt.Value.initFunction(closure);
            _ = aot_rt.php_invoke_callable(cb, argv, aot_rt.runtime_allocator) catch {};
        }
    };
    f.argv = args[0..];

    const stats = measure(20, 200, f.run);
    var r = computeStats(20, "aot_runtime_closure_create_invoke", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotObjectPropertyAccess(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

    const f = struct {
        fn run() void {
            const obj = aot_rt.PHPObject.init(aot_rt.runtime_allocator, "TestClass") catch return;
            defer obj.release();

            var i: i64 = 0;
            while (i < 1000) : (i += 1) {
                _ = obj.setProperty("prop", aot_rt.Value.initInt(i)) catch {};
                const v = obj.getProperty("prop");
                _ = v;
            }
        }
    }.run;

    const stats = measure(20, 100, f);
    var r = computeStats(20, "aot_runtime_object_property_access", stats);
    fillAllocFields(&r);
    return r;
}

fn benchAotObjectLifecycle(allocator: std.mem.Allocator) !BenchmarkResult {
    aot_rt.initRuntime(allocator);
    defer aot_rt.deinitRuntime();
    aot_rt.resetAllocStats();

    const f = struct {
        fn run() void {
            var i: usize = 0;
            while (i < 1000) : (i += 1) {
                const obj = aot_rt.PHPObject.init(aot_rt.runtime_allocator, "Temp") catch return;
                obj.release();
            }
        }
    }.run;

    const stats = measure(20, 100, f);
    var r = computeStats(20, "aot_runtime_object_lifecycle", stats);
    fillAllocFields(&r);
    return r;
}

fn compileSampleOnce(allocator: std.mem.Allocator) void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const options = aot.CompileOptions{
        .input_file = "src/benchmark/aot_compile_sample.php",
        .optimize_level = .release_fast,
        .static_link = false,
        .debug_info = false,
        .link_executable = false,
    };

    const c = aot.AOTCompiler.init(arena.allocator(), options) catch return;
    defer c.deinit();
    _ = c.compile() catch {};
}

fn benchAotCompilePipeline(allocator: std.mem.Allocator) !BenchmarkResult {
    compileSampleOnce(allocator);

    const N = 10;
    var samples: [N]u64 = undefined;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const start = std.time.nanoTimestamp();
        compileSampleOnce(allocator);
        const end = std.time.nanoTimestamp();
        samples[i] = @as(u64, @intCast(end - start));
    }

    const stats: Stats(N) = .{ .samples = samples, .iterations = 1 };
    return computeStats(N, "aot_compile_pipeline", stats);
}
