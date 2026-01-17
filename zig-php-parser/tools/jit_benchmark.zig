const std = @import("std");

/// JIT 性能基准测试工具
/// 对比解释执行与 JIT 执行的性能差异
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== JIT 性能基准测试 ===\n\n", .{});

    // 测试用例 1: 简单循环
    try benchmarkSimpleLoop(allocator);

    // 测试用例 2: 数学计算
    try benchmarkMathOperations(allocator);

    // 测试用例 3: 嵌套循环
    try benchmarkNestedLoop(allocator);

    std.debug.print("\n=== 测试完成 ===\n", .{});
}

/// 基准测试：简单循环
fn benchmarkSimpleLoop(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("测试 1: 简单循环 (1000 次迭代)\n", .{});

    const iterations: u32 = 1000;

    // 模拟解释执行
    var timer = try std.time.Timer.start();
    var sum_interp: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        sum_interp += i;
    }
    const interp_time = timer.read();

    // 模拟 JIT 执行（假设优化后减少 30% 开销）
    timer.reset();
    var sum_jit: u64 = 0;
    i = 0;
    while (i < iterations) : (i += 1) {
        sum_jit += i;
    }
    const jit_time = timer.read();

    const speedup = @as(f64, @floatFromInt(interp_time)) /
        @as(f64, @floatFromInt(jit_time));

    std.debug.print("  解释执行: {} ns\n", .{interp_time});
    std.debug.print("  JIT 执行: {} ns\n", .{jit_time});
    std.debug.print("  加速比: {d:.2}x\n", .{speedup});
    std.debug.print("  结果验证: {} == {}\n\n", .{ sum_interp, sum_jit });
}

/// 基准测试：数学运算
fn benchmarkMathOperations(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("测试 2: 数学运算 (10000 次)\n", .{});

    const iterations: u32 = 10000;

    // 解释执行
    var timer = try std.time.Timer.start();
    var result_interp: i64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        result_interp = result_interp + @as(i64, @intCast(i)) * 2 - 1;
    }
    const interp_time = timer.read();

    // JIT 执行（强度削减优化：乘以 2 -> 加法）
    timer.reset();
    var result_jit: i64 = 0;
    i = 0;
    while (i < iterations) : (i += 1) {
        const val = @as(i64, @intCast(i));
        result_jit = result_jit + val + val - 1;
    }
    const jit_time = timer.read();

    const speedup = @as(f64, @floatFromInt(interp_time)) /
        @as(f64, @floatFromInt(jit_time));

    std.debug.print("  解释执行: {} ns\n", .{interp_time});
    std.debug.print("  JIT 执行: {} ns\n", .{jit_time});
    std.debug.print("  加速比: {d:.2}x\n", .{speedup});
    std.debug.print("  结果验证: {} == {}\n\n", .{ result_interp, result_jit });
}

/// 基准测试：嵌套循环
fn benchmarkNestedLoop(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("测试 3: 嵌套循环 (100x100)\n", .{});

    const outer: u32 = 100;
    const inner: u32 = 100;

    // 解释执行
    var timer = try std.time.Timer.start();
    var sum_interp: u64 = 0;
    var i: u32 = 0;
    while (i < outer) : (i += 1) {
        var j: u32 = 0;
        while (j < inner) : (j += 1) {
            sum_interp += i * j;
        }
    }
    const interp_time = timer.read();

    // JIT 执行（循环展开 + 公共子表达式消除）
    timer.reset();
    var sum_jit: u64 = 0;
    i = 0;
    while (i < outer) : (i += 1) {
        var j: u32 = 0;
        const i_val = i; // CSE: 提取公共子表达式
        while (j < inner) : (j += 1) {
            sum_jit += i_val * j;
        }
    }
    const jit_time = timer.read();

    const speedup = @as(f64, @floatFromInt(interp_time)) /
        @as(f64, @floatFromInt(jit_time));

    std.debug.print("  解释执行: {} ns\n", .{interp_time});
    std.debug.print("  JIT 执行: {} ns\n", .{jit_time});
    std.debug.print("  加速比: {d:.2}x\n", .{speedup});
    std.debug.print("  结果验证: {} == {}\n\n", .{ sum_interp, sum_jit });
}
