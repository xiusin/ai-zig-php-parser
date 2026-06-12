//! FastValue 性能基准测试
//! 测试 FastValue (NaN-boxing) 的性能特性
//!
//! 测试项目:
//! 1. 整数创建性能
//! 2. 整数算术运算性能
//! 3. 类型检查性能
//! 4. 浮点运算性能
//! 5. 混合类型运算性能
//! 6. 48位大整数性能
//!
//! 运行方式: zig test src/runtime/benchmark_fast_value.zig -OReleaseFast

const std = @import("std");
const fast_value = @import("fast_value.zig");

const FastValue = fast_value.FastValue;
const FastOps = fast_value.FastOps;

const ITERATIONS: u64 = 10_000_000;
const WARMUP_ITERATIONS: u64 = 100_000;

/// 基准测试结果
const BenchResult = struct {
    name: []const u8,
    total_ns: u64,
    ns_per_op: u64,
    ops_per_sec: u64,

    pub fn print(self: BenchResult) void {
        if (self.ns_per_op == 0) {
            std.debug.print(
                "| {s:<30} | {d:>6} ms total | <1 ns/op | >1B ops/s |\n",
                .{ self.name, self.total_ns / 1_000_000 },
            );
        } else {
            std.debug.print(
                "| {s:<30} | {d:>6} ms total | {d:>3} ns/op | {d:>6}M ops/s |\n",
                .{ self.name, self.total_ns / 1_000_000, self.ns_per_op, self.ops_per_sec / 1_000_000 },
            );
        }
    }
};

/// 防止编译器优化掉结果 - 使用 volatile 写入
var sink: u64 = 0;
fn doNotOptimize(val: anytype) void {
    const T = @TypeOf(val);
    if (T == FastValue) {
        const ptr: *volatile u64 = &sink;
        ptr.* = val.bits;
    } else if (@typeInfo(T) == .int) {
        const ptr: *volatile u64 = &sink;
        ptr.* = @bitCast(val);
    } else if (@typeInfo(T) == .float) {
        const ptr: *volatile u64 = &sink;
        ptr.* = @bitCast(val);
    }
}

// ============================================================================
// FastValue 基准测试
// ============================================================================

fn benchIntCreate() u64 {
    var timer = std.time.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |i| {
        const v = FastValue.initInt(@intCast(i & 0xFFFF));
        acc +%= v.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

fn benchIntAdd() u64 {
    var a = FastValue.initInt(42);
    const b = FastValue.initInt(17);

    var timer = std.time.Timer.start() catch unreachable;

    for (0..ITERATIONS) |_| {
        a = FastOps.addInt(a, b);
    }
    doNotOptimize(a);

    return timer.read();
}

fn benchIntMul() u64 {
    var result = FastValue.initInt(1);
    const factor = FastValue.initInt(1); // 乘以1保持值不变

    var timer = std.time.Timer.start() catch unreachable;

    for (0..ITERATIONS) |i| {
        _ = i;
        result = FastOps.mulInt(result, factor);
    }
    doNotOptimize(result);

    return timer.read();
}

fn benchIntDiv() u64 {
    const a = FastValue.initInt(1_000_000_000);
    const b = FastValue.initInt(7);

    var timer = std.time.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |_| {
        const result = FastOps.divInt(a, b);
        acc +%= result.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

fn benchTypeCheck() u64 {
    const values = [_]FastValue{
        FastValue.initInt(42),
        FastValue.initFloat(3.14),
        FastValue.nil,
        FastValue.true,
        FastValue.false,
    };

    var timer = std.time.Timer.start() catch unreachable;

    var count: u64 = 0;
    for (0..ITERATIONS) |i| {
        const v = values[i % values.len];
        if (v.isInt()) count +%= 1;
        if (v.isFloat()) count +%= 2;
        if (v.isNil()) count +%= 4;
        if (v.isBool()) count +%= 8;
    }
    doNotOptimize(count);

    return timer.read();
}

fn benchFloatAdd() u64 {
    var a = FastValue.initFloat(3.14159);
    const b = FastValue.initFloat(0.00001);

    var timer = std.time.Timer.start() catch unreachable;

    for (0..ITERATIONS) |_| {
        a = FastOps.addFloat(a, b);
    }
    doNotOptimize(a);

    return timer.read();
}

fn benchFloatMul() u64 {
    var a = FastValue.initFloat(1.0000001);
    const b = FastValue.initFloat(1.0000001);

    var timer = std.time.Timer.start() catch unreachable;

    for (0..ITERATIONS) |_| {
        a = FastOps.mulFloat(a, b);
    }
    doNotOptimize(a);

    return timer.read();
}

fn benchMixedAdd() u64 {
    var a = FastValue.initInt(0);
    const b = FastValue.initFloat(0.1);

    var timer = std.time.Timer.start() catch unreachable;

    for (0..ITERATIONS) |i| {
        a = FastValue.initInt(@intCast(i & 0xFFFF));
        const result = FastOps.add(a, b);
        doNotOptimize(result);
    }

    return timer.read();
}

fn benchInt48Add() u64 {
    // 测试大整数 (超出32位范围)
    var a = FastValue.initInt(100_000_000_000);
    const b = FastValue.initInt(1);

    var timer = std.time.Timer.start() catch unreachable;

    for (0..ITERATIONS) |_| {
        a = FastOps.add(a, b);
    }
    doNotOptimize(a);

    return timer.read();
}

fn benchInt48Mul() u64 {
    // 测试大整数乘法
    const a = FastValue.initInt(1_000_000);
    const b = FastValue.initInt(1_000_000);

    var timer = std.time.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |_| {
        const result = FastOps.mul(a, b);
        acc +%= result.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

fn benchComparison() u64 {
    const values = [_]FastValue{
        FastValue.initInt(42),
        FastValue.initInt(17),
        FastValue.initInt(100),
        FastValue.initInt(0),
    };

    var timer = std.time.Timer.start() catch unreachable;

    var count: u64 = 0;
    for (0..ITERATIONS) |i| {
        const a = values[i % values.len];
        const b = values[(i + 1) % values.len];
        if (FastOps.lt(a, b).asBool()) count +%= 1;
        if (FastOps.gt(a, b).asBool()) count +%= 2;
        if (FastOps.eq(a, b).asBool()) count +%= 4;
    }
    doNotOptimize(count);

    return timer.read();
}

fn benchBitOps() u64 {
    var a = FastValue.initInt(0xABCDEF);
    const b = FastValue.initInt(0x123456);

    var timer = std.time.Timer.start() catch unreachable;

    for (0..ITERATIONS) |_| {
        a = FastOps.bitAnd(a, b);
        a = FastOps.bitOr(a, b);
        a = FastOps.bitXor(a, b);
    }
    doNotOptimize(a);

    return timer.read();
}

fn benchSmallIntCache() u64 {
    var timer = std.time.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |i| {
        const idx: i64 = @intCast(i % 256);
        const v = fast_value.small_int_cache.get(idx - 128);
        acc +%= v.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

// ============================================================================
// 运行基准测试
// ============================================================================

fn runBenchmark(name: []const u8, bench_fn: *const fn () u64) BenchResult {
    // Warmup
    for (0..WARMUP_ITERATIONS / 1000) |_| {
        _ = bench_fn();
    }

    // 多次运行取最小值
    var min_ns: u64 = std.math.maxInt(u64);

    for (0..5) |_| {
        const ns = bench_fn();
        min_ns = @min(min_ns, ns);
    }

    const ns_per_op = min_ns / ITERATIONS;
    const ops_per_sec = if (min_ns > 0) (ITERATIONS * 1_000_000_000) / min_ns else 0;

    return .{
        .name = name,
        .total_ns = min_ns,
        .ns_per_op = ns_per_op,
        .ops_per_sec = ops_per_sec,
    };
}

pub fn runAllBenchmarks() void {
    std.debug.print("\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("FastValue 性能基准测试 (NaN-boxing, 48-bit integers)\n", .{});
    std.debug.print("迭代次数: {d}\n", .{ITERATIONS});
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("| {s:<30} | {s:>11} | {s:>14} |\n", .{
        "测试项目",
        "延迟",
        "吞吐量",
    });
    std.debug.print("|" ++ "-" ** 32 ++ "|" ++ "-" ** 13 ++ "|" ++ "-" ** 16 ++ "|\n", .{});

    const benchmarks = [_]struct {
        name: []const u8,
        bench_fn: *const fn () u64,
    }{
        .{ .name = "整数创建", .bench_fn = benchIntCreate },
        .{ .name = "整数加法 (inline)", .bench_fn = benchIntAdd },
        .{ .name = "整数乘法 (inline)", .bench_fn = benchIntMul },
        .{ .name = "整数除法 (inline)", .bench_fn = benchIntDiv },
        .{ .name = "类型检查 (4种)", .bench_fn = benchTypeCheck },
        .{ .name = "浮点加法", .bench_fn = benchFloatAdd },
        .{ .name = "浮点乘法", .bench_fn = benchFloatMul },
        .{ .name = "混合类型加法", .bench_fn = benchMixedAdd },
        .{ .name = "48位大整数加法", .bench_fn = benchInt48Add },
        .{ .name = "48位大整数乘法", .bench_fn = benchInt48Mul },
        .{ .name = "比较操作 (3种)", .bench_fn = benchComparison },
        .{ .name = "位操作 (3种)", .bench_fn = benchBitOps },
        .{ .name = "小整数缓存", .bench_fn = benchSmallIntCache },
    };

    for (benchmarks) |b| {
        const result = runBenchmark(b.name, b.bench_fn);
        result.print();
    }

    std.debug.print("=" ** 60 ++ "\n", .{});
}

// ============================================================================
// 测试入口
// ============================================================================

test "FastValue benchmark" {
    runAllBenchmarks();
}

test "FastValue memory size" {
    // 验证内存大小
    std.debug.print("\n内存大小:\n", .{});
    std.debug.print("  FastValue: {d} bytes (64-bit NaN-boxed)\n", .{@sizeOf(FastValue)});

    try std.testing.expectEqual(@as(usize, 8), @sizeOf(FastValue));
}

test "FastValue 48-bit range verification" {
    // 验证48位整数范围
    const max48 = FastValue.maxInt48();
    const min48 = FastValue.minInt48();

    std.debug.print("\n48位整数范围:\n", .{});
    std.debug.print("  最大值: {d}\n", .{max48});
    std.debug.print("  最小值: {d}\n", .{min48});
    std.debug.print("  范围:   ±{d} 万亿\n", .{@divTrunc(max48, 1_000_000_000_000)});

    // 验证边界值
    const v_max = FastValue.initInt(max48);
    try std.testing.expect(v_max.isInt());
    try std.testing.expectEqual(max48, v_max.asInt());

    const v_min = FastValue.initInt(min48);
    try std.testing.expect(v_min.isInt());
    try std.testing.expectEqual(min48, v_min.asInt());

    // 验证溢出转浮点
    const v_overflow = FastValue.initInt(max48 + 1);
    try std.testing.expect(v_overflow.isFloat());
}

test "FastValue arithmetic correctness" {
    // 验证算术正确性
    const a = FastValue.initInt(100_000_000_000);
    const b = FastValue.initInt(200_000_000_000);

    const sum = FastOps.add(a, b);
    try std.testing.expect(sum.isInt());
    try std.testing.expectEqual(@as(i64, 300_000_000_000), sum.asInt());

    const diff = FastOps.sub(b, a);
    try std.testing.expect(diff.isInt());
    try std.testing.expectEqual(@as(i64, 100_000_000_000), diff.asInt());

    // 乘法可能溢出
    const c = FastValue.initInt(1_000_000);
    const d = FastValue.initInt(1_000_000);
    const prod = FastOps.mul(c, d);
    try std.testing.expect(prod.isInt());
    try std.testing.expectEqual(@as(i64, 1_000_000_000_000), prod.asInt());
}
