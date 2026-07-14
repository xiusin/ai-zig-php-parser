//! FastVM 性能基准测试
//! 测试 FastVM 的执行性能
//!
//! 测试项目:
//! 1. 简单算术运算
//! 2. 循环性能
//! 3. 超级指令性能
//! 4. 类型特化指令性能
//!
//! 运行方式: zig test src/runtime/benchmark_fast_vm.zig -OReleaseFast
const time_compat = @import("time_compat.zig");

const std = @import("std");
const fast_vm = @import("fast_vm.zig");
const fast_value = @import("fast_value.zig");

const FastVM = fast_vm.FastVM;
const FastValue = fast_value.FastValue;
const OpCode = fast_vm.OpCode;
const CompiledFunc = fast_vm.CompiledFunc;

const ITERATIONS: u64 = 1_000_000;
const WARMUP_ITERATIONS: u64 = 10_000;

/// 基准测试结果
const BenchResult = struct {
    name: []const u8,
    total_ns: u64,
    ns_per_op: u64,
    ops_per_sec: u64,

    pub fn print(self: BenchResult) void {
        if (self.ns_per_op == 0) {
            std.debug.print(
                "| {s:<35} | {d:>6} ms | <1 ns/op | >1B ops/s |\n",
                .{ self.name, self.total_ns / 1_000_000 },
            );
        } else {
            std.debug.print(
                "| {s:<35} | {d:>6} ms | {d:>3} ns/op | {d:>6}M ops/s |\n",
                .{ self.name, self.total_ns / 1_000_000, self.ns_per_op, self.ops_per_sec / 1_000_000 },
            );
        }
    }
};

/// 防止编译器优化掉结果
var sink: i64 = 0;
fn doNotOptimize(val: anytype) void {
    const ptr: *volatile i64 = &sink;
    if (@TypeOf(val) == FastValue) {
        ptr.* = val.asInt();
    } else if (@TypeOf(val) == i64) {
        ptr.* = val;
    }
}

// ============================================================================
// 基准测试函数
// ============================================================================

/// 简单加法: 1 + 2
fn benchSimpleAdd(allocator: std.mem.Allocator) !u64 {
    var vm = try FastVM.init(allocator);
    defer vm.deinit();

    const code = [_]u8{
        @intFromEnum(OpCode.push_int), 1,                         0, 0, 0,
        @intFromEnum(OpCode.push_int), 2,                         0, 0, 0,
        @intFromEnum(OpCode.add_i),    @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "bench_add",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 8,
    };

    var timer = time_compat.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |_| {
        const result = try vm.execute(&func);
        acc +%= result.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

/// 循环求和: sum = 0; for i = 1 to 100: sum += i
fn benchLoop(allocator: std.mem.Allocator) !u64 {
    var vm = try FastVM.init(allocator);
    defer vm.deinit();

    // 局部变量: 0=sum, 1=i
    const code = [_]u8{
        // sum = 0
        @intFromEnum(OpCode.push_0),
        @intFromEnum(OpCode.store_local),
        0,
        // i = 1
        @intFromEnum(OpCode.push_1),
        @intFromEnum(OpCode.store_local),
        1,
        // loop:
        // sum = sum + i
        @intFromEnum(OpCode.push_local),
        0,
        @intFromEnum(OpCode.push_local),
        1,
        @intFromEnum(OpCode.add_i),
        @intFromEnum(OpCode.store_local),
        0,
        // i++
        @intFromEnum(OpCode.load_inc_store),
        1,
        // if i <= 100 goto loop
        @intFromEnum(OpCode.push_local),
        1,
        @intFromEnum(OpCode.push_int),
        100,
        0,
        0,
        0,
        @intFromEnum(OpCode.le),
        @intFromEnum(OpCode.jnz),
        @as(u8, @bitCast(@as(i8, -18))),
        0xFF,
        // return sum
        @intFromEnum(OpCode.push_local),
        0,
        @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "bench_loop",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 2,
        .params_count = 0,
        .max_stack = 8,
    };

    var timer = time_compat.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS / 100) |_| { // 每次循环100次，所以减少外层迭代
        const result = try vm.execute(&func);
        acc +%= result.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

/// 超级指令: load_inc_store
fn benchSuperInstruction(allocator: std.mem.Allocator) !u64 {
    var vm = try FastVM.init(allocator);
    defer vm.deinit();

    // 使用超级指令 load_inc_store 进行 1000 次自增
    var code_list = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer code_list.deinit(allocator);

    // i = 0
    try code_list.append(allocator, @intFromEnum(OpCode.push_0));
    try code_list.append(allocator, @intFromEnum(OpCode.store_local));
    try code_list.append(allocator, 0);

    // 1000 次 load_inc_store
    for (0..1000) |_| {
        try code_list.append(allocator, @intFromEnum(OpCode.load_inc_store));
        try code_list.append(allocator, 0);
    }

    // return i
    try code_list.append(allocator, @intFromEnum(OpCode.push_local));
    try code_list.append(allocator, 0);
    try code_list.append(allocator, @intFromEnum(OpCode.halt));

    const func = CompiledFunc{
        .name = "bench_super",
        .code = code_list.items,
        .constants = &[_]FastValue{},
        .locals_count = 1,
        .params_count = 0,
        .max_stack = 8,
    };

    var timer = time_compat.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS / 1000) |_| {
        const result = try vm.execute(&func);
        acc +%= result.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

/// 类型特化指令: add_i vs add
fn benchTypeSpecialized(allocator: std.mem.Allocator) !u64 {
    var vm = try FastVM.init(allocator);
    defer vm.deinit();

    // 使用类型特化的 add_i 指令
    const code = [_]u8{
        @intFromEnum(OpCode.push_int), 42, 0, 0, 0,
        @intFromEnum(OpCode.push_int), 17, 0, 0, 0,
        @intFromEnum(OpCode.add_i), // 类型特化，无类型检查
        @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "bench_typed",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 8,
    };

    var timer = time_compat.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |_| {
        const result = try vm.execute(&func);
        acc +%= result.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

/// 通用指令: add (带类型检查)
fn benchGenericAdd(allocator: std.mem.Allocator) !u64 {
    var vm = try FastVM.init(allocator);
    defer vm.deinit();

    // 使用通用的 add 指令（带类型检查）
    const code = [_]u8{
        @intFromEnum(OpCode.push_int), 42, 0, 0, 0,
        @intFromEnum(OpCode.push_int), 17, 0, 0, 0,
        @intFromEnum(OpCode.add), // 通用，有类型检查
        @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "bench_generic",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 8,
    };

    var timer = time_compat.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |_| {
        const result = try vm.execute(&func);
        acc +%= result.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

/// 浮点运算
fn benchFloatOps(allocator: std.mem.Allocator) !u64 {
    var vm = try FastVM.init(allocator);
    defer vm.deinit();

    // 构建浮点运算字节码: 3.14159 * 2.71828
    const pi_bits: u64 = @bitCast(@as(f64, 3.14159));
    const e_bits: u64 = @bitCast(@as(f64, 2.71828));
    const pi_bytes = std.mem.toBytes(pi_bits);
    const e_bytes = std.mem.toBytes(e_bits);

    const code = [_]u8{
        @intFromEnum(OpCode.push_float),
        pi_bytes[0],
        pi_bytes[1],
        pi_bytes[2],
        pi_bytes[3],
        pi_bytes[4],
        pi_bytes[5],
        pi_bytes[6],
        pi_bytes[7],
        @intFromEnum(OpCode.push_float),
        e_bytes[0],
        e_bytes[1],
        e_bytes[2],
        e_bytes[3],
        e_bytes[4],
        e_bytes[5],
        e_bytes[6],
        e_bytes[7],
        @intFromEnum(OpCode.mul_f),
        @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "bench_float",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 8,
    };

    var timer = time_compat.Timer.start() catch unreachable;

    var acc: f64 = 0;
    for (0..ITERATIONS) |_| {
        const result = try vm.execute(&func);
        acc += result.asFloat();
    }
    // 防止优化
    const ptr: *volatile f64 = @ptrCast(@alignCast(&sink));
    ptr.* = acc;

    return timer.read();
}

/// 栈操作: push/pop/dup
fn benchStackOps(allocator: std.mem.Allocator) !u64 {
    var vm = try FastVM.init(allocator);
    defer vm.deinit();

    const code = [_]u8{
        @intFromEnum(OpCode.push_1),
        @intFromEnum(OpCode.dup),
        @intFromEnum(OpCode.dup),
        @intFromEnum(OpCode.add_i),
        @intFromEnum(OpCode.add_i),
        @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "bench_stack",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 8,
    };

    var timer = time_compat.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |_| {
        const result = try vm.execute(&func);
        acc +%= result.asInt();
    }
    doNotOptimize(acc);

    return timer.read();
}

/// 比较操作
fn benchComparison(allocator: std.mem.Allocator) !u64 {
    var vm = try FastVM.init(allocator);
    defer vm.deinit();

    const code = [_]u8{
        @intFromEnum(OpCode.push_int), 42,                        0, 0, 0,
        @intFromEnum(OpCode.push_int), 17,                        0, 0, 0,
        @intFromEnum(OpCode.lt_i),     @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "bench_cmp",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 8,
    };

    var timer = time_compat.Timer.start() catch unreachable;

    var acc: i64 = 0;
    for (0..ITERATIONS) |_| {
        const result = try vm.execute(&func);
        if (result.isBool() and !result.asBool()) acc +%= 1;
    }
    doNotOptimize(acc);

    return timer.read();
}

// ============================================================================
// 基准测试运行器
// ============================================================================

fn calcResult(name: []const u8, total_ns: u64, iterations: u64) BenchResult {
    const ns_per_op = if (iterations > 0) total_ns / iterations else 0;
    const ops_per_sec = if (ns_per_op > 0) 1_000_000_000 / ns_per_op else 0;
    return BenchResult{
        .name = name,
        .total_ns = total_ns,
        .ns_per_op = ns_per_op,
        .ops_per_sec = ops_per_sec,
    };
}

/// 运行所有基准测试
pub fn runAllBenchmarks(allocator: std.mem.Allocator) !void {
    std.debug.print("\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});
    std.debug.print("FastVM Performance Benchmarks\n", .{});
    std.debug.print("Iterations: {d}\n", .{ITERATIONS});
    std.debug.print("=" ** 70 ++ "\n", .{});
    std.debug.print("| {s:<35} | {s:>9} | {s:>9} | {s:>12} |\n", .{
        "Benchmark", "Total", "Per Op", "Throughput",
    });
    std.debug.print("-" ** 70 ++ "\n", .{});

    // 简单加法
    const add_ns = try benchSimpleAdd(allocator);
    calcResult("Simple Add (1+2)", add_ns, ITERATIONS).print();

    // 循环
    const loop_ns = try benchLoop(allocator);
    calcResult("Loop Sum (1..100)", loop_ns, ITERATIONS / 100).print();

    // 超级指令
    const super_ns = try benchSuperInstruction(allocator);
    calcResult("Super Instruction (1000x inc)", super_ns, ITERATIONS / 1000).print();

    // 类型特化
    const typed_ns = try benchTypeSpecialized(allocator);
    calcResult("Type-Specialized Add (add_i)", typed_ns, ITERATIONS).print();

    // 通用加法
    const generic_ns = try benchGenericAdd(allocator);
    calcResult("Generic Add (add)", generic_ns, ITERATIONS).print();

    // 浮点运算
    const float_ns = try benchFloatOps(allocator);
    calcResult("Float Multiply (pi*e)", float_ns, ITERATIONS).print();

    // 栈操作
    const stack_ns = try benchStackOps(allocator);
    calcResult("Stack Ops (push/dup/add)", stack_ns, ITERATIONS).print();

    // 比较操作
    const cmp_ns = try benchComparison(allocator);
    calcResult("Comparison (lt_i)", cmp_ns, ITERATIONS).print();

    std.debug.print("=" ** 70 ++ "\n", .{});

    // 性能对比
    std.debug.print("\nPerformance Analysis:\n", .{});
    if (typed_ns > 0 and generic_ns > 0) {
        const speedup = @as(f64, @floatFromInt(generic_ns)) / @as(f64, @floatFromInt(typed_ns));
        std.debug.print("  Type-specialized vs Generic: {d:.2}x faster\n", .{speedup});
    }
}

// ============================================================================
// 测试入口
// ============================================================================

test "FastVM benchmark - simple add" {
    const allocator = std.testing.allocator;
    const ns = try benchSimpleAdd(allocator);
    try std.testing.expect(ns > 0);
}

test "FastVM benchmark - loop" {
    const allocator = std.testing.allocator;
    const ns = try benchLoop(allocator);
    try std.testing.expect(ns > 0);
}

test "FastVM benchmark - super instruction" {
    const allocator = std.testing.allocator;
    const ns = try benchSuperInstruction(allocator);
    try std.testing.expect(ns > 0);
}

test "FastVM benchmark - type specialized" {
    const allocator = std.testing.allocator;
    const ns = try benchTypeSpecialized(allocator);
    try std.testing.expect(ns > 0);
}

test "FastVM benchmark - generic add" {
    const allocator = std.testing.allocator;
    const ns = try benchGenericAdd(allocator);
    try std.testing.expect(ns > 0);
}

test "FastVM benchmark - float ops" {
    const allocator = std.testing.allocator;
    const ns = try benchFloatOps(allocator);
    try std.testing.expect(ns > 0);
}

test "FastVM benchmark - stack ops" {
    const allocator = std.testing.allocator;
    const ns = try benchStackOps(allocator);
    try std.testing.expect(ns > 0);
}

test "FastVM benchmark - comparison" {
    const allocator = std.testing.allocator;
    const ns = try benchComparison(allocator);
    try std.testing.expect(ns > 0);
}

test "FastVM benchmark - run all" {
    const allocator = std.testing.allocator;
    try runAllBenchmarks(allocator);
}
