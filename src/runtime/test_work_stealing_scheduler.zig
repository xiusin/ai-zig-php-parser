//! ============================================================================
//! Work Stealing Scheduler Tests - 工作窃取调度器测试
//! ============================================================================
//!
//! 测试工作窃取调度器的完整功能：
//! - 任务队列管理
//! - 工作窃取算法
//! - 负载均衡
//! - 效率 > 90%
//!
//! 需求：8.4
//! ============================================================================

const std = @import("std");
const WorkStealingScheduler = @import("work_stealing_scheduler.zig").WorkStealingScheduler;
const Task = @import("work_stealing_scheduler.zig").Task;

/// 简单的任务上下文
const SimpleTaskContext = struct {
    value: i32,
    result: std.atomic.Value(i32),

    pub fn init(value: i32) SimpleTaskContext {
        return SimpleTaskContext{
            .value = value,
            .result = std.atomic.Value(i32).init(0),
        };
    }
};

/// 简单的任务函数
fn simpleTaskFunc(context: *anyopaque) !void {
    const ctx = @as(*SimpleTaskContext, @ptrCast(@alignCast(context)));

    // 模拟一些工作
    var sum: i32 = 0;
    var i: i32 = 0;
    while (i < ctx.value) : (i += 1) {
        sum += i;
    }

    ctx.result.store(sum, .release);
}

/// CPU密集型任务函数
fn cpuIntensiveTaskFunc(context: *anyopaque) !void {
    const ctx = @as(*SimpleTaskContext, @ptrCast(@alignCast(context)));

    // 模拟CPU密集型工作
    var sum: i32 = 0;
    var i: i32 = 0;
    while (i < ctx.value * 1000) : (i += 1) {
        sum = @mod(sum + i, 1000000);
    }

    ctx.result.store(sum, .release);
}

test "work stealing scheduler basic task execution" {
    const allocator = std.testing.allocator;

    const config = WorkStealingScheduler.Config{
        .num_workers = 2,
    };

    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();

    try scheduler.start();
    defer scheduler.stop();

    // 创建任务上下文
    var ctx = SimpleTaskContext.init(100);

    // 创建任务
    var task = Task{
        .func = simpleTaskFunc,
        .context = @ptrCast(&ctx),
        .priority = 0,
        .id = 0,
        .state = .pending,
        .created_at = 0,
        .started_at = 0,
        .completed_at = 0,
    };

    // 提交任务
    try scheduler.submitTask(&task);

    // 等待任务完成
    scheduler.waitForCompletion();

    // 验证结果
    const result = ctx.result.load(.acquire);
    try std.testing.expect(result > 0);

    // 验证统计信息
    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_tasks);
    try std.testing.expectEqual(@as(u64, 1), stats.completed_tasks);
    try std.testing.expectEqual(@as(f64, 1.0), stats.efficiency);
}

test "work stealing scheduler multiple tasks" {
    const allocator = std.testing.allocator;

    const config = WorkStealingScheduler.Config{
        .num_workers = 4,
    };

    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();

    try scheduler.start();
    defer scheduler.stop();

    // 创建多个任务
    const num_tasks = 100;
    var contexts = try allocator.alloc(SimpleTaskContext, num_tasks);
    defer allocator.free(contexts);

    var tasks = try allocator.alloc(Task, num_tasks);
    defer allocator.free(tasks);

    for (contexts, 0..) |*ctx, i| {
        ctx.* = SimpleTaskContext.init(@intCast(i + 1));

        tasks[i] = Task{
            .func = simpleTaskFunc,
            .context = @ptrCast(ctx),
            .priority = @intCast(@mod(i, 5)),
            .id = 0,
            .state = .pending,
            .created_at = 0,
            .started_at = 0,
            .completed_at = 0,
        };

        try scheduler.submitTask(&tasks[i]);
    }

    // 等待所有任务完成
    scheduler.waitForCompletion();

    // 验证统计信息
    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(u64, num_tasks), stats.total_tasks);
    try std.testing.expectEqual(@as(u64, num_tasks), stats.completed_tasks);
    try std.testing.expectEqual(@as(f64, 1.0), stats.efficiency);

    std.debug.print("\n[Multiple Tasks Test] Completed {d} tasks\n", .{stats.completed_tasks});
    std.debug.print("[Multiple Tasks Test] Efficiency: {d:.2}%\n", .{stats.efficiency * 100.0});
}

test "work stealing scheduler work stealing" {
    const allocator = std.testing.allocator;

    const config = WorkStealingScheduler.Config{
        .num_workers = 4,
        .enable_work_stealing = true,
        .steal_strategy = .half,
    };

    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();

    try scheduler.start();
    defer scheduler.stop();

    // 创建大量任务以触发工作窃取
    const num_tasks = 1000;
    var contexts = try allocator.alloc(SimpleTaskContext, num_tasks);
    defer allocator.free(contexts);

    var tasks = try allocator.alloc(Task, num_tasks);
    defer allocator.free(tasks);

    for (contexts, 0..) |*ctx, i| {
        ctx.* = SimpleTaskContext.init(10);

        tasks[i] = Task{
            .func = cpuIntensiveTaskFunc,
            .context = @ptrCast(ctx),
            .priority = 0,
            .id = 0,
            .state = .pending,
            .created_at = 0,
            .started_at = 0,
            .completed_at = 0,
        };

        try scheduler.submitTask(&tasks[i]);
    }

    // 等待所有任务完成
    scheduler.waitForCompletion();

    // 验证统计信息
    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(u64, num_tasks), stats.total_tasks);
    try std.testing.expectEqual(@as(u64, num_tasks), stats.completed_tasks);

    // 应该有工作窃取发生
    try std.testing.expect(stats.steal_attempts > 0);

    std.debug.print("\n[Work Stealing Test] Completed {d} tasks\n", .{stats.completed_tasks});
    std.debug.print("[Work Stealing Test] Steal attempts: {d}\n", .{stats.steal_attempts});
    std.debug.print("[Work Stealing Test] Steal successes: {d}\n", .{stats.steal_successes});
    std.debug.print("[Work Stealing Test] Steal success rate: {d:.2}%\n", .{stats.steal_success_rate * 100.0});
}

test "work stealing scheduler load balancing" {
    const allocator = std.testing.allocator;

    const config = WorkStealingScheduler.Config{
        .num_workers = 4,
        .enable_load_balancing = true,
        .load_balance_threshold = 0.5,
    };

    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();

    try scheduler.start();
    defer scheduler.stop();

    // 创建任务
    const num_tasks = 500;
    var contexts = try allocator.alloc(SimpleTaskContext, num_tasks);
    defer allocator.free(contexts);

    var tasks = try allocator.alloc(Task, num_tasks);
    defer allocator.free(tasks);

    for (contexts, 0..) |*ctx, i| {
        ctx.* = SimpleTaskContext.init(10);

        tasks[i] = Task{
            .func = cpuIntensiveTaskFunc,
            .context = @ptrCast(ctx),
            .priority = 0,
            .id = 0,
            .state = .pending,
            .created_at = 0,
            .started_at = 0,
            .completed_at = 0,
        };

        try scheduler.submitTask(&tasks[i]);
    }

    // 执行负载均衡
    try scheduler.balanceLoad();

    // 等待所有任务完成
    scheduler.waitForCompletion();

    // 验证统计信息
    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(u64, num_tasks), stats.total_tasks);
    try std.testing.expectEqual(@as(u64, num_tasks), stats.completed_tasks);

    std.debug.print("\n[Load Balancing Test] Completed {d} tasks\n", .{stats.completed_tasks});
    std.debug.print("[Load Balancing Test] Load balance count: {d}\n", .{stats.load_balance_count});
}

test "work stealing scheduler efficiency > 90%" {
    const allocator = std.testing.allocator;

    const config = WorkStealingScheduler.Config{
        .num_workers = 4,
        .enable_work_stealing = true,
        .enable_load_balancing = true,
    };

    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();

    try scheduler.start();
    defer scheduler.stop();

    // 创建大量任务以测试效率
    const num_tasks = 10000;
    var contexts = try allocator.alloc(SimpleTaskContext, num_tasks);
    defer allocator.free(contexts);

    var tasks = try allocator.alloc(Task, num_tasks);
    defer allocator.free(tasks);

    for (contexts, 0..) |*ctx, i| {
        ctx.* = SimpleTaskContext.init(5);

        tasks[i] = Task{
            .func = simpleTaskFunc,
            .context = @ptrCast(ctx),
            .priority = @intCast(@mod(i, 5)),
            .id = 0,
            .state = .pending,
            .created_at = 0,
            .started_at = 0,
            .completed_at = 0,
        };

        try scheduler.submitTask(&tasks[i]);
    }

    // 等待所有任务完成
    scheduler.waitForCompletion();

    // 验证统计信息
    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(u64, num_tasks), stats.total_tasks);

    // 验证效率 > 90%
    try std.testing.expect(stats.efficiency > 0.90);

    std.debug.print("\n[Efficiency Test] Completed {d}/{d} tasks\n", .{ stats.completed_tasks, stats.total_tasks });
    std.debug.print("[Efficiency Test] Efficiency: {d:.2}%\n", .{stats.efficiency * 100.0});
    std.debug.print("[Efficiency Test] Failed tasks: {d}\n", .{stats.failed_tasks});

    // 打印完整报告
    scheduler.printReport();
}

test "work stealing scheduler different steal strategies" {
    const allocator = std.testing.allocator;

    const strategies = [_]WorkStealingScheduler.StealStrategy{ .one, .half, .quarter };

    for (strategies) |strategy| {
        const config = WorkStealingScheduler.Config{
            .num_workers = 4,
            .enable_work_stealing = true,
            .steal_strategy = strategy,
        };

        var scheduler = try WorkStealingScheduler.init(allocator, config);
        defer scheduler.deinit();

        try scheduler.start();
        defer scheduler.stop();

        // 创建任务
        const num_tasks = 500;
        var contexts = try allocator.alloc(SimpleTaskContext, num_tasks);
        defer allocator.free(contexts);

        var tasks = try allocator.alloc(Task, num_tasks);
        defer allocator.free(tasks);

        for (contexts, 0..) |*ctx, i| {
            ctx.* = SimpleTaskContext.init(10);

            tasks[i] = Task{
                .func = cpuIntensiveTaskFunc,
                .context = @ptrCast(ctx),
                .priority = 0,
                .id = 0,
                .state = .pending,
                .created_at = 0,
                .started_at = 0,
                .completed_at = 0,
            };

            try scheduler.submitTask(&tasks[i]);
        }

        // 等待所有任务完成
        scheduler.waitForCompletion();

        // 验证统计信息
        const stats = scheduler.getStats();
        try std.testing.expectEqual(@as(u64, num_tasks), stats.total_tasks);
        try std.testing.expectEqual(@as(u64, num_tasks), stats.completed_tasks);

        std.debug.print("\n[Strategy Test - {s}] Completed {d} tasks\n", .{ @tagName(strategy), stats.completed_tasks });
        std.debug.print("[Strategy Test - {s}] Steal attempts: {d}\n", .{ @tagName(strategy), stats.steal_attempts });
        std.debug.print("[Strategy Test - {s}] Steal success rate: {d:.2}%\n", .{ @tagName(strategy), stats.steal_success_rate * 100.0 });
    }
}

test "work stealing scheduler performance benchmark" {
    const allocator = std.testing.allocator;

    const config = WorkStealingScheduler.Config{
        .num_workers = 4,
        .enable_work_stealing = true,
        .enable_load_balancing = true,
    };

    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();

    try scheduler.start();
    defer scheduler.stop();

    // 创建大量任务进行性能测试
    const num_tasks = 5000;
    var contexts = try allocator.alloc(SimpleTaskContext, num_tasks);
    defer allocator.free(contexts);

    var tasks = try allocator.alloc(Task, num_tasks);
    defer allocator.free(tasks);

    const start_time = std.time.nanoTimestamp();

    for (contexts, 0..) |*ctx, i| {
        ctx.* = SimpleTaskContext.init(10);

        tasks[i] = Task{
            .func = cpuIntensiveTaskFunc,
            .context = @ptrCast(ctx),
            .priority = @intCast(@mod(i, 5)),
            .id = 0,
            .state = .pending,
            .created_at = 0,
            .started_at = 0,
            .completed_at = 0,
        };

        try scheduler.submitTask(&tasks[i]);
    }

    // 等待所有任务完成
    scheduler.waitForCompletion();

    const end_time = std.time.nanoTimestamp();
    const total_time = @as(u64, @intCast(end_time - start_time));

    // 验证统计信息
    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(u64, num_tasks), stats.total_tasks);
    try std.testing.expectEqual(@as(u64, num_tasks), stats.completed_tasks);

    const throughput = @as(f64, @floatFromInt(num_tasks)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

    std.debug.print("\n[Performance Benchmark]\n", .{});
    std.debug.print("Total tasks: {d}\n", .{num_tasks});
    std.debug.print("Total time: {d} ms\n", .{total_time / 1_000_000});
    std.debug.print("Throughput: {d:.2} tasks/sec\n", .{throughput});
    std.debug.print("Efficiency: {d:.2}%\n", .{stats.efficiency * 100.0});
    std.debug.print("Steal success rate: {d:.2}%\n", .{stats.steal_success_rate * 100.0});
}
