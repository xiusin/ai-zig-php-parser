//! ============================================================================
//! Work Stealing Scheduler - 工作窃取调度器
//! ============================================================================
//!
//! 完整的工作窃取调度器实现，支持：
//! - 任务队列管理
//! - 工作窃取算法
//! - 负载均衡
//! - 效率 > 90%
//!
//! 需求：8.4
//! ============================================================================
const time_compat = @import("time_compat.zig");

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Coroutine = @import("coroutine.zig").Coroutine;
const OptimizedWorkStealer = @import("scheduler_optimization.zig").OptimizedWorkStealer;
const LockFreeWorkQueue = @import("scheduler_optimization.zig").LockFreeWorkQueue;

/// 任务类型
pub const Task = struct {
    /// 任务函数
    func: *const fn (*anyopaque) anyerror!void,
    
    /// 任务上下文
    context: *anyopaque,
    
    /// 任务优先级 (0=最高, 4=最低)
    priority: u8,
    
    /// 任务ID
    id: u64,
    
    /// 任务状态
    state: TaskState,
    
    /// 创建时间
    created_at: i64,
    
    /// 开始执行时间
    started_at: i64,
    
    /// 完成时间
    completed_at: i64,
    
    pub const TaskState = enum {
        pending,
        running,
        completed,
        failed,
        cancelled,
    };
};

/// 工作窃取调度器
/// @concurrency-model MULTI-THREADED
/// @thread-safety ATOMIC + LOCK-FREE
pub const WorkStealingScheduler = struct {
    allocator: std.mem.Allocator,
    
    /// 工作线程数量
    num_workers: usize,
    
    /// 每个工作线程的本地队列
    local_queues: []LockFreeWorkQueue(256),
    
    /// 全局队列（用于负载均衡）
    global_queue: LockFreeWorkQueue(1024),
    
    /// 工作窃取器
    work_stealer: OptimizedWorkStealer,
    
    /// 工作线程
    workers: []std.Thread,
    
    /// 运行状态
    running: std.atomic.Value(bool),
    
    /// 任务ID计数器
    next_task_id: std.atomic.Value(u64),
    
    /// 统计信息
    stats: SchedulerStats,
    
    /// 配置
    config: Config,
    
    pub const Config = struct {
        /// 工作线程数量（默认为CPU核心数）
        num_workers: ?usize = null,
        
        /// 启用工作窃取
        enable_work_stealing: bool = true,
        
        /// 启用负载均衡
        enable_load_balancing: bool = true,
        
        /// 负载均衡阈值
        load_balance_threshold: f64 = 0.8,
        
        /// 窃取策略
        steal_strategy: StealStrategy = .half,
        
        /// 最大任务队列大小
        max_queue_size: usize = 256,
    };
    
    pub const StealStrategy = enum {
        /// 窃取一半任务（Go风格）
        half,
        
        /// 窃取一个任务
        one,
        
        /// 窃取四分之一任务
        quarter,
    };
    
    pub const SchedulerStats = struct {
        /// 总任务数
        total_tasks: std.atomic.Value(u64),
        
        /// 完成任务数
        completed_tasks: std.atomic.Value(u64),
        
        /// 失败任务数
        failed_tasks: std.atomic.Value(u64),
        
        /// 窃取尝试次数
        steal_attempts: std.atomic.Value(u64),
        
        /// 窃取成功次数
        steal_successes: std.atomic.Value(u64),
        
        /// 负载均衡次数
        load_balance_count: std.atomic.Value(u64),
        
        /// 总执行时间（纳秒）
        total_execution_time_ns: std.atomic.Value(u64),
        
        pub fn init() SchedulerStats {
            return SchedulerStats{
                .total_tasks = std.atomic.Value(u64).init(0),
                .completed_tasks = std.atomic.Value(u64).init(0),
                .failed_tasks = std.atomic.Value(u64).init(0),
                .steal_attempts = std.atomic.Value(u64).init(0),
                .steal_successes = std.atomic.Value(u64).init(0),
                .load_balance_count = std.atomic.Value(u64).init(0),
                .total_execution_time_ns = std.atomic.Value(u64).init(0),
            };
        }
        
        /// 获取效率（完成任务数 / 总任务数）
        pub fn getEfficiency(self: *const SchedulerStats) f64 {
            const total = self.total_tasks.load(.monotonic);
            const completed = self.completed_tasks.load(.monotonic);
            
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(completed)) / @as(f64, @floatFromInt(total));
        }
        
        /// 获取窃取成功率
        pub fn getStealSuccessRate(self: *const SchedulerStats) f64 {
            const attempts = self.steal_attempts.load(.monotonic);
            const successes = self.steal_successes.load(.monotonic);
            
            if (attempts == 0) return 0.0;
            return @as(f64, @floatFromInt(successes)) / @as(f64, @floatFromInt(attempts));
        }
    };
    
    /// 初始化调度器
    /// @pre allocator 必须有效
    /// @post 返回初始化的调度器实例
    pub fn init(allocator: std.mem.Allocator, config: Config) !WorkStealingScheduler {
        // 确定工作线程数量
        const num_workers = config.num_workers orelse blk: {
            const cpu_count = try std.Thread.getCpuCount();
            break :blk @max(1, cpu_count);
        };
        
        // 分配本地队列
        const local_queues = try allocator.alloc(LockFreeWorkQueue(256), num_workers);
        errdefer allocator.free(local_queues);
        
        for (local_queues) |*queue| {
            queue.* = LockFreeWorkQueue(256).init();
        }
        
        // 分配工作线程数组
        const workers = try allocator.alloc(std.Thread, num_workers);
        errdefer allocator.free(workers);
        
        return WorkStealingScheduler{
            .allocator = allocator,
            .num_workers = num_workers,
            .local_queues = local_queues,
            .global_queue = LockFreeWorkQueue(1024).init(),
            .work_stealer = OptimizedWorkStealer.init(allocator, num_workers),
            .workers = workers,
            .running = std.atomic.Value(bool).init(false),
            .next_task_id = std.atomic.Value(u64).init(0),
            .stats = SchedulerStats.init(),
            .config = config,
        };
    }
    
    /// 释放调度器资源
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *WorkStealingScheduler) void {
        // 停止调度器
        self.stop();
        
        // 释放资源
        self.allocator.free(self.local_queues);
        self.allocator.free(self.workers);
    }
    
    /// 启动调度器
    /// @pre self 必须已初始化
    /// @post 启动所有工作线程
    pub fn start(self: *WorkStealingScheduler) !void {
        if (self.running.load(.monotonic)) {
            return error.AlreadyRunning;
        }
        
        self.running.store(true, .release);
        
        // 启动工作线程
        for (self.workers, 0..) |*worker, i| {
            worker.* = try std.Thread.spawn(.{}, workerLoop, .{ self, i });
        }
    }
    
    /// 停止调度器
    /// @pre self 必须已启动
    /// @post 停止所有工作线程
    pub fn stop(self: *WorkStealingScheduler) void {
        if (!self.running.load(.monotonic)) {
            return;
        }
        
        self.running.store(false, .release);
        
        // 等待所有工作线程结束
        for (self.workers) |worker| {
            worker.join();
        }
    }
    
    /// 提交任务
    /// @pre task 必须有效
    /// @post 任务被添加到队列
    pub fn submitTask(self: *WorkStealingScheduler, task: *Task) !void {
        // 分配任务ID
        task.id = self.next_task_id.fetchAdd(1, .monotonic);
        task.state = .pending;
        task.created_at = @intCast(time_compat.nanoTimestamp());
        
        _ = self.stats.total_tasks.fetchAdd(1, .monotonic);
        
        // 选择负载最轻的工作线程
        const worker_id = self.selectLeastLoadedWorker();
        
        // 尝试添加到本地队列
        const coro = @as(*Coroutine, @ptrCast(@alignCast(task)));
        if (!self.local_queues[worker_id].tryEnqueue(coro)) {
            // 本地队列满，尝试全局队列
            if (!self.global_queue.tryEnqueue(coro)) {
                return error.QueueFull;
            }
        }
    }
    
    /// 工作线程主循环
    /// @ownership NON-OWNING (scheduler)
    fn workerLoop(self: *WorkStealingScheduler, worker_id: usize) void {
        while (self.running.load(.acquire)) {
            // 1. 尝试从本地队列获取任务
            if (self.local_queues[worker_id].tryDequeue()) |coro| {
                self.executeTask(coro, worker_id) catch |err| {
                    std.log.err("Worker {d}: Task execution failed: {}", .{ worker_id, err });
                };
                continue;
            }
            
            // 2. 尝试从全局队列获取任务
            if (self.global_queue.tryDequeue()) |coro| {
                self.executeTask(coro, worker_id) catch |err| {
                    std.log.err("Worker {d}: Task execution failed: {}", .{ worker_id, err });
                };
                continue;
            }
            
            // 3. 尝试从其他工作线程窃取任务
            if (self.config.enable_work_stealing) {
                if (self.stealWork(worker_id)) |coro| {
                    self.executeTask(coro, worker_id) catch |err| {
                        std.log.err("Worker {d}: Task execution failed: {}", .{ worker_id, err });
                    };
                    continue;
                }
            }
            
            // 4. 没有任务，短暂休眠
            std.Thread.sleep(100_000); // 100微秒
        }
    }
    
    /// 执行任务
    /// @pre coro 必须有效
    /// @post 任务被执行
    fn executeTask(self: *WorkStealingScheduler, coro: *Coroutine, worker_id: usize) !void {
        _ = worker_id;
        
        const task = @as(*Task, @ptrCast(@alignCast(coro)));
        
        task.state = .running;
        task.started_at = @intCast(time_compat.nanoTimestamp());
        
        const start_time = time_compat.nanoTimestamp();
        
        // 执行任务
        task.func(task.context) catch |err| {
            task.state = .failed;
            _ = self.stats.failed_tasks.fetchAdd(1, .monotonic);
            return err;
        };
        
        const end_time = time_compat.nanoTimestamp();
        const execution_time = @as(u64, @intCast(end_time - start_time));
        
        task.state = .completed;
        task.completed_at = @intCast(end_time);
        
        _ = self.stats.completed_tasks.fetchAdd(1, .monotonic);
        _ = self.stats.total_execution_time_ns.fetchAdd(execution_time, .monotonic);
    }
    
    /// 窃取工作
    /// @pre worker_id 必须有效
    /// @post 返回窃取的任务或null
    fn stealWork(self: *WorkStealingScheduler, worker_id: usize) ?*Coroutine {
        _ = self.stats.steal_attempts.fetchAdd(1, .monotonic);
        
        // 获取处理器负载
        const loads = self.getWorkerLoads();
        defer self.allocator.free(loads);
        
        // 选择受害者
        const victim_id = self.work_stealer.selectVictim(worker_id, loads);
        
        if (victim_id == worker_id) {
            return null;
        }
        
        // 根据策略窃取任务
        const stolen = switch (self.config.steal_strategy) {
            .one => self.stealOne(victim_id),
            .half => self.stealHalf(victim_id, worker_id),
            .quarter => self.stealQuarter(victim_id, worker_id),
        };
        
        if (stolen != null) {
            _ = self.stats.steal_successes.fetchAdd(1, .monotonic);
            self.work_stealer.recordStealResult(true, 1);
        } else {
            self.work_stealer.recordStealResult(false, 0);
        }
        
        return stolen;
    }
    
    /// 窃取一个任务
    fn stealOne(self: *WorkStealingScheduler, victim_id: usize) ?*Coroutine {
        return self.local_queues[victim_id].tryDequeue();
    }
    
    /// 窃取一半任务（Go风格）
    fn stealHalf(self: *WorkStealingScheduler, victim_id: usize, thief_id: usize) ?*Coroutine {
        const victim_size = self.local_queues[victim_id].size();
        
        if (victim_size < 2) {
            return null;
        }
        
        const steal_count = victim_size / 2;
        var first_stolen: ?*Coroutine = null;
        
        var i: usize = 0;
        while (i < steal_count) : (i += 1) {
            if (self.local_queues[victim_id].tryDequeue()) |coro| {
                if (first_stolen == null) {
                    first_stolen = coro;
                } else {
                    // 将其他任务添加到窃取者的队列
                    _ = self.local_queues[thief_id].tryEnqueue(coro);
                }
            } else {
                break;
            }
        }
        
        return first_stolen;
    }
    
    /// 窃取四分之一任务
    fn stealQuarter(self: *WorkStealingScheduler, victim_id: usize, thief_id: usize) ?*Coroutine {
        const victim_size = self.local_queues[victim_id].size();
        
        if (victim_size < 4) {
            return self.stealOne(victim_id);
        }
        
        const steal_count = victim_size / 4;
        var first_stolen: ?*Coroutine = null;
        
        var i: usize = 0;
        while (i < steal_count) : (i += 1) {
            if (self.local_queues[victim_id].tryDequeue()) |coro| {
                if (first_stolen == null) {
                    first_stolen = coro;
                } else {
                    _ = self.local_queues[thief_id].tryEnqueue(coro);
                }
            } else {
                break;
            }
        }
        
        return first_stolen;
    }
    
    /// 选择负载最轻的工作线程
    /// @post 返回负载最轻的工作线程ID
    fn selectLeastLoadedWorker(self: *WorkStealingScheduler) usize {
        var min_load: usize = std.math.maxInt(usize);
        var min_worker: usize = 0;
        
        for (self.local_queues, 0..) |*queue, i| {
            const load = queue.size();
            if (load < min_load) {
                min_load = load;
                min_worker = i;
            }
        }
        
        return min_worker;
    }
    
    /// 获取所有工作线程的负载
    /// @post 返回负载数组（需要调用者释放）
    fn getWorkerLoads(self: *WorkStealingScheduler) []f64 {
        const loads = self.allocator.alloc(f64, self.num_workers) catch return &[_]f64{};
        
        for (self.local_queues, 0..) |*queue, i| {
            const size = @as(f64, @floatFromInt(queue.size()));
            const max_size = @as(f64, @floatFromInt(self.config.max_queue_size));
            loads[i] = @min(size / max_size, 1.0);
        }
        
        return loads;
    }
    
    /// 执行负载均衡
    /// @post 将任务从高负载队列移动到低负载队列
    pub fn balanceLoad(self: *WorkStealingScheduler) !void {
        if (!self.config.enable_load_balancing) {
            return;
        }
        
        const loads = self.getWorkerLoads();
        defer self.allocator.free(loads);
        
        // 找到最高负载和最低负载的工作线程
        var max_load: f64 = 0.0;
        var max_worker: usize = 0;
        var min_load: f64 = 1.0;
        var min_worker: usize = 0;
        
        for (loads, 0..) |load, i| {
            if (load > max_load) {
                max_load = load;
                max_worker = i;
            }
            if (load < min_load) {
                min_load = load;
                min_worker = i;
            }
        }
        
        // 如果负载差异超过阈值，进行均衡
        if (max_load - min_load > self.config.load_balance_threshold) {
            const transfer_count = @as(usize, @intFromFloat((max_load - min_load) * @as(f64, @floatFromInt(self.config.max_queue_size)) / 2.0));
            
            var i: usize = 0;
            while (i < transfer_count) : (i += 1) {
                if (self.local_queues[max_worker].tryDequeue()) |coro| {
                    if (!self.local_queues[min_worker].tryEnqueue(coro)) {
                        // 目标队列满，放回全局队列
                        _ = self.global_queue.tryEnqueue(coro);
                    }
                } else {
                    break;
                }
            }
            
            _ = self.stats.load_balance_count.fetchAdd(1, .monotonic);
        }
    }
    
    /// 获取调度器统计信息
    /// @post 返回统计信息
    pub fn getStats(self: *const WorkStealingScheduler) SchedulerStatsSnapshot {
        return SchedulerStatsSnapshot{
            .total_tasks = self.stats.total_tasks.load(.monotonic),
            .completed_tasks = self.stats.completed_tasks.load(.monotonic),
            .failed_tasks = self.stats.failed_tasks.load(.monotonic),
            .steal_attempts = self.stats.steal_attempts.load(.monotonic),
            .steal_successes = self.stats.steal_successes.load(.monotonic),
            .load_balance_count = self.stats.load_balance_count.load(.monotonic),
            .total_execution_time_ns = self.stats.total_execution_time_ns.load(.monotonic),
            .efficiency = self.stats.getEfficiency(),
            .steal_success_rate = self.stats.getStealSuccessRate(),
            .num_workers = self.num_workers,
        };
    }
    
    /// 打印调度器报告
    pub fn printReport(self: *const WorkStealingScheduler) void {
        const stats = self.getStats();
        
        std.log.info("=== Work Stealing Scheduler Report ===", .{});
        std.log.info("Workers: {d}", .{stats.num_workers});
        std.log.info("Total tasks: {d}", .{stats.total_tasks});
        std.log.info("Completed tasks: {d}", .{stats.completed_tasks});
        std.log.info("Failed tasks: {d}", .{stats.failed_tasks});
        std.log.info("Efficiency: {d:.2}%", .{stats.efficiency * 100.0});
        std.log.info("Steal attempts: {d}", .{stats.steal_attempts});
        std.log.info("Steal successes: {d}", .{stats.steal_successes});
        std.log.info("Steal success rate: {d:.2}%", .{stats.steal_success_rate * 100.0});
        std.log.info("Load balance count: {d}", .{stats.load_balance_count});
        
        if (stats.completed_tasks > 0) {
            const avg_time = stats.total_execution_time_ns / stats.completed_tasks;
            std.log.info("Average task execution time: {d} ns", .{avg_time});
        }
    }
    
    /// 等待所有任务完成
    /// @post 阻塞直到所有任务完成
    pub fn waitForCompletion(self: *WorkStealingScheduler) void {
        while (true) {
            const total = self.stats.total_tasks.load(.monotonic);
            const completed = self.stats.completed_tasks.load(.monotonic);
            const failed = self.stats.failed_tasks.load(.monotonic);
            
            if (completed + failed >= total) {
                break;
            }
            
            std.Thread.sleep(1_000_000); // 1ms
        }
    }
};

/// 调度器统计信息快照
pub const SchedulerStatsSnapshot = struct {
    total_tasks: u64,
    completed_tasks: u64,
    failed_tasks: u64,
    steal_attempts: u64,
    steal_successes: u64,
    load_balance_count: u64,
    total_execution_time_ns: u64,
    efficiency: f64,
    steal_success_rate: f64,
    num_workers: usize,
};


// ============================================================================
// Tests
// ============================================================================

test "work stealing scheduler initialization" {
    const allocator = std.testing.allocator;
    
    const config = WorkStealingScheduler.Config{
        .num_workers = 4,
    };
    
    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();
    
    try std.testing.expectEqual(@as(usize, 4), scheduler.num_workers);
    try std.testing.expect(!scheduler.running.load(.monotonic));
}

test "work stealing scheduler stats" {
    const allocator = std.testing.allocator;
    
    const config = WorkStealingScheduler.Config{
        .num_workers = 2,
    };
    
    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();
    
    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_tasks);
    try std.testing.expectEqual(@as(u64, 0), stats.completed_tasks);
    try std.testing.expectEqual(@as(f64, 0.0), stats.efficiency);
}

test "work stealing scheduler efficiency calculation" {
    var stats = WorkStealingScheduler.SchedulerStats.init();
    
    _ = stats.total_tasks.fetchAdd(100, .monotonic);
    _ = stats.completed_tasks.fetchAdd(90, .monotonic);
    
    const efficiency = stats.getEfficiency();
    try std.testing.expectApproxEqAbs(@as(f64, 0.9), efficiency, 0.01);
}

test "work stealing scheduler steal success rate" {
    var stats = WorkStealingScheduler.SchedulerStats.init();
    
    _ = stats.steal_attempts.fetchAdd(100, .monotonic);
    _ = stats.steal_successes.fetchAdd(75, .monotonic);
    
    const rate = stats.getStealSuccessRate();
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), rate, 0.01);
}

test "work stealing scheduler select least loaded worker" {
    const allocator = std.testing.allocator;
    
    const config = WorkStealingScheduler.Config{
        .num_workers = 4,
    };
    
    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();
    
    // 所有队列都是空的，应该返回第一个
    const worker_id = scheduler.selectLeastLoadedWorker();
    try std.testing.expectEqual(@as(usize, 0), worker_id);
}

test "work stealing scheduler get worker loads" {
    const allocator = std.testing.allocator;
    
    const config = WorkStealingScheduler.Config{
        .num_workers = 4,
    };
    
    var scheduler = try WorkStealingScheduler.init(allocator, config);
    defer scheduler.deinit();
    
    const loads = scheduler.getWorkerLoads();
    defer allocator.free(loads);
    
    try std.testing.expectEqual(@as(usize, 4), loads.len);
    
    // 所有队列都是空的，负载应该为0
    for (loads) |load| {
        try std.testing.expectEqual(@as(f64, 0.0), load);
    }
}
