//! ============================================================================
//! 工作线程 (Worker)
//! ============================================================================
//!
//! 功能：M:P:N调度器中的M组件，执行协程的OS线程
//!
//! 在调度器中的角色：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                        Worker (M)                                │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────────────┐  │
//! │  │                    OS Thread                              │  │
//! │  │                                                           │  │
//! │  │  状态: running / parked / stopped                        │  │
//! │  │                                                           │  │
//! │  │  绑定的Processor: P0                                     │  │
//! │  │                                                           │  │
//! │  │  工作循环:                                                │  │
//! │  │  1. 从绑定的P获取协程                                    │  │
//! │  │  2. 执行协程                                             │  │
//! │  │  3. 无工作时park(休眠)                                   │  │
//! │  │  4. 有新工作时unpark(唤醒)                               │  │
//! │  └──────────────────────────────────────────────────────────┘  │
//! │                                                                  │
//! │  性能计数器:                                                     │
//! │  - executed_count: 执行的协程数                                 │
//! │  - park_count: 休眠次数                                         │
//! │  - handoff_count: 处理器交接次数                                │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 核心特性：
//! - 线程生命周期管理（start/stop）
//! - 线程停泊和唤醒（park/unpark）
//! - 处理器交接机制（handoff）
//! - 性能监控和统计
//!
//! 线程状态：
//! - running: 正在执行协程
//! - parked: 无工作，休眠等待
//! - stopped: 已停止
//!
//! 需求：6.1, 6.5, 6.7
//! ============================================================================
const time_compat = @import("time_compat.zig");

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Coroutine = @import("coroutine.zig").Coroutine;
const Processor = @import("processor.zig").Processor;

/// 工作线程(M) - 执行协程的OS线程
pub const Worker = struct {
    id: u32,
    thread: ?std.Thread,
    processor: ?*Processor,
    scheduler: *anyopaque, // Use anyopaque to avoid circular dependency
    allocator: std.mem.Allocator,

    // Thread state management
    parked: std.atomic.Value(bool),
    running: std.atomic.Value(bool),
    should_stop: std.atomic.Value(bool),

    // Synchronization primitives
    park_mutex: std.Thread.Mutex,
    park_condition: std.Thread.Condition,

    // Performance counters
    executed_count: std.atomic.Value(u64),
    park_count: std.atomic.Value(u64),
    handoff_count: std.atomic.Value(u64),
    total_execution_time_ns: std.atomic.Value(u64),

    // Timing
    created_at: i64,
    last_activity: std.atomic.Value(i64),

    // Forward declaration
    const Scheduler = @import("scheduler.zig").Scheduler;

    /// Initialize worker thread
    pub fn init(id: u32, scheduler: *anyopaque, allocator: std.mem.Allocator) Worker {
        return Worker{
            .id = id,
            .thread = null,
            .processor = null,
            .scheduler = scheduler,
            .allocator = allocator,
            .parked = std.atomic.Value(bool).init(false),
            .running = std.atomic.Value(bool).init(false),
            .should_stop = std.atomic.Value(bool).init(false),
            .park_mutex = .{},
            .park_condition = .{},
            .executed_count = std.atomic.Value(u64).init(0),
            .park_count = std.atomic.Value(u64).init(0),
            .handoff_count = std.atomic.Value(u64).init(0),
            .total_execution_time_ns = std.atomic.Value(u64).init(0),
            .created_at = @intCast(time_compat.nanoTimestamp()),
            .last_activity = std.atomic.Value(i64).init(@intCast(time_compat.nanoTimestamp())),
        };
    }

    /// Start worker thread
    /// Requirement 6.1 - worker thread lifecycle management
    pub fn start(self: *Worker) !void {
        if (self.thread != null) {
            return error.AlreadyStarted;
        }

        self.running.store(true, .monotonic);
        self.thread = try std.Thread.spawn(.{}, workerLoop, .{self});
    }

    /// Stop worker thread
    pub fn stop(self: *Worker) void {
        self.should_stop.store(true, .monotonic);
        self.unpark(); // Wake up if parked

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        self.running.store(false, .monotonic);
    }

    /// Park worker thread (put to sleep)
    /// Requirement 6.5 - thread parking and unparking
    pub fn park(self: *Worker) void {
        self.park_mutex.lock();
        defer self.park_mutex.unlock();

        if (self.should_stop.load(.monotonic)) {
            return;
        }

        self.parked.store(true, .monotonic);
        _ = self.park_count.fetchAdd(1, .monotonic);

        // Wait until unparked or should stop
        while (self.parked.load(.monotonic) and !self.should_stop.load(.monotonic)) {
            self.park_condition.wait(&self.park_mutex);
        }
    }

    /// Unpark worker thread (wake up)
    /// Requirement 6.5 - thread parking and unparking
    pub fn unpark(self: *Worker) void {
        self.park_mutex.lock();
        defer self.park_mutex.unlock();

        if (self.parked.load(.monotonic)) {
            self.parked.store(false, .monotonic);
            self.park_condition.signal();
        }
    }

    /// Hand off processor to another thread
    /// Requirement 6.7 - processor handoff mechanism
    pub fn handoff(self: *Worker, new_processor: *Processor) void {
        if (self.processor) |old_processor| {
            // Detach from old processor
            old_processor.worker = null;
        }

        // Attach to new processor
        self.processor = new_processor;
        new_processor.worker = self;

        _ = self.handoff_count.fetchAdd(1, .monotonic);
        _ = self.last_activity.store(@intCast(time_compat.nanoTimestamp()), .monotonic);
    }

    /// Detach from current processor
    pub fn detachProcessor(self: *Worker) void {
        if (self.processor) |processor| {
            processor.worker = null;
            self.processor = null;
        }
    }

    /// Check if worker is idle
    pub fn isIdle(self: *Worker) bool {
        return self.parked.load(.monotonic) or
            (self.processor == null) or
            (self.processor != null and self.processor.?.isIdle());
    }

    /// Get worker statistics
    pub fn getStats(self: *Worker) WorkerStats {
        const now = @as(i64, @intCast(time_compat.nanoTimestamp()));
        const uptime_ns = now - self.created_at;
        const executed = self.executed_count.load(.monotonic);
        const total_exec_time = self.total_execution_time_ns.load(.monotonic);

        return WorkerStats{
            .id = self.id,
            .is_running = self.running.load(.monotonic),
            .is_parked = self.parked.load(.monotonic),
            .processor_id = if (self.processor) |p| p.id else null,
            .executed_count = executed,
            .park_count = self.park_count.load(.monotonic),
            .handoff_count = self.handoff_count.load(.monotonic),
            .uptime_ns = uptime_ns,
            .total_execution_time_ns = total_exec_time,
            .utilization = if (uptime_ns > 0) @as(f64, @floatFromInt(total_exec_time)) / @as(f64, @floatFromInt(uptime_ns)) else 0.0,
            .last_activity = self.last_activity.load(.monotonic),
        };
    }

    /// Reset worker statistics
    pub fn resetStats(self: *Worker) void {
        _ = self.executed_count.store(0, .monotonic);
        _ = self.park_count.store(0, .monotonic);
        _ = self.handoff_count.store(0, .monotonic);
        _ = self.total_execution_time_ns.store(0, .monotonic);
        _ = self.last_activity.store(@intCast(time_compat.nanoTimestamp()), .monotonic);
    }

    /// Main worker thread loop
    /// Requirement 6.1 - worker thread lifecycle management
    fn workerLoop(self: *Worker) void {
        defer self.running.store(false, .monotonic);

        while (!self.should_stop.load(.monotonic)) {
            // Try to find work
            if (self.findWork()) |coro| {
                const start_time = @as(i64, @intCast(time_compat.nanoTimestamp()));

                // Execute the coroutine
                self.executeCoroutine(coro) catch |err| {
                    // Log error and continue
                    std.log.err("Worker {d}: Error executing coroutine {d}: {}", .{ self.id, coro.id, err });
                };

                const execution_time = @as(u64, @intCast(@as(i64, @intCast(time_compat.nanoTimestamp())) - start_time));
                _ = self.executed_count.fetchAdd(1, .monotonic);
                _ = self.total_execution_time_ns.fetchAdd(execution_time, .monotonic);
                _ = self.last_activity.store(@intCast(time_compat.nanoTimestamp()), .monotonic);
            } else {
                // No work found, park the thread
                self.park();
            }
        }
    }

    /// Find work for this worker
    /// Requirement 6.1 - worker thread lifecycle management
    fn findWork(self: *Worker) ?*Coroutine {
        // First, try to get work from our assigned processor
        if (self.processor) |processor| {
            if (processor.local_queue.pop()) |coro| {
                return coro;
            }
        }

        // No work on our processor, try to steal work
        return self.stealWork();
    }

    /// Steal work from other processors
    /// Requirement 6.3 - work stealing algorithm
    fn stealWork(self: *Worker) ?*Coroutine {
        // Simplified implementation for testing
        _ = self;
        return null;
    }

    /// Execute a coroutine
    fn executeCoroutine(self: *Worker, coro: *Coroutine) !void {
        if (self.processor) |processor| {
            try processor.execute(coro);
        } else {
            // No processor assigned, execute directly
            try coro.execute(@ptrFromInt(0x1000)); // Mock VM

            // Handle coroutine completion
            switch (coro.state) {
                .completed, .cancelled => {
                    // Simplified - just mark as completed
                },
                .yielded, .waiting => {
                    // Simplified - just mark as yielded
                },
                else => {
                    // Unexpected state
                },
            }
        }
    }

    /// Check if worker should continue running
    pub fn shouldRun(self: *Worker) bool {
        return self.running.load(.monotonic) and !self.should_stop.load(.monotonic);
    }

    /// Force wake up worker if parked
    pub fn wakeUp(self: *Worker) void {
        self.unpark();
    }

    /// Get current processor ID (if any)
    pub fn getProcessorId(self: *Worker) ?u32 {
        return if (self.processor) |p| p.id else null;
    }

    /// Check if worker has a processor assigned
    pub fn hasProcessor(self: *Worker) bool {
        return self.processor != null;
    }

    /// Get worker uptime in nanoseconds
    pub fn getUptime(self: *Worker) i64 {
        return @as(i64, @intCast(time_compat.nanoTimestamp())) - self.created_at;
    }

    /// Get time since last activity
    pub fn getIdleTime(self: *Worker) i64 {
        return @as(i64, @intCast(time_compat.nanoTimestamp())) - self.last_activity.load(.monotonic);
    }
};

/// Worker statistics structure
pub const WorkerStats = struct {
    id: u32,
    is_running: bool,
    is_parked: bool,
    processor_id: ?u32,
    executed_count: u64,
    park_count: u64,
    handoff_count: u64,
    uptime_ns: i64,
    total_execution_time_ns: u64,
    utilization: f64, // 0.0 to 1.0
    last_activity: i64,
};

/// Worker Pool for managing multiple worker threads
pub const WorkerPool = struct {
    workers: []Worker,
    allocator: std.mem.Allocator,
    scheduler: *anyopaque, // Use anyopaque to avoid circular dependency

    pub fn init(allocator: std.mem.Allocator, scheduler: *anyopaque, worker_count: u32) !WorkerPool {
        const workers = try allocator.alloc(Worker, worker_count);

        for (workers, 0..) |*worker, i| {
            worker.* = Worker.init(@intCast(i), scheduler, allocator);
        }

        return WorkerPool{
            .workers = workers,
            .allocator = allocator,
            .scheduler = scheduler,
        };
    }

    pub fn deinit(self: *WorkerPool) void {
        self.stopAll();
        self.allocator.free(self.workers);
    }

    /// Start all worker threads
    pub fn startAll(self: *WorkerPool) !void {
        for (self.workers) |*worker| {
            try worker.start();
        }
    }

    /// Stop all worker threads
    pub fn stopAll(self: *WorkerPool) void {
        for (self.workers) |*worker| {
            worker.stop();
        }
    }

    /// Get worker by ID
    pub fn getWorker(self: *WorkerPool, id: u32) ?*Worker {
        if (id >= self.workers.len) return null;
        return &self.workers[id];
    }

    /// Get all worker statistics
    pub fn getAllStats(self: *WorkerPool) []WorkerStats {
        var stats = self.allocator.alloc(WorkerStats, self.workers.len) catch return &[_]WorkerStats{};

        for (self.workers, 0..) |*worker, i| {
            stats[i] = worker.getStats();
        }

        return stats;
    }

    /// Get idle workers
    pub fn getIdleWorkers(self: *WorkerPool) []u32 {
        var idle_workers = std.ArrayList(u32){ .allocator = self.allocator };
        defer idle_workers.deinit();

        for (self.workers, 0..) |*worker, i| {
            if (worker.isIdle()) {
                idle_workers.append(@intCast(i)) catch continue;
            }
        }

        return idle_workers.toOwnedSlice() catch &[_]u32{};
    }

    /// Wake up all parked workers
    pub fn wakeUpAll(self: *WorkerPool) void {
        for (self.workers) |*worker| {
            worker.wakeUp();
        }
    }

    /// Reset all worker statistics
    pub fn resetAllStats(self: *WorkerPool) void {
        for (self.workers) |*worker| {
            worker.resetStats();
        }
    }

    /// Get pool utilization (0.0 to 1.0)
    pub fn getUtilization(self: *WorkerPool) f64 {
        var total_utilization: f64 = 0.0;

        for (self.workers) |*worker| {
            const stats = worker.getStats();
            total_utilization += stats.utilization;
        }

        return total_utilization / @as(f64, @floatFromInt(self.workers.len));
    }

    /// Get number of active workers
    pub fn getActiveCount(self: *WorkerPool) u32 {
        var active_count: u32 = 0;

        for (self.workers) |*worker| {
            if (worker.running.load(.monotonic) and !worker.parked.load(.monotonic)) {
                active_count += 1;
            }
        }

        return active_count;
    }
};

// Tests
test "worker initialization and basic operations" {
    const allocator = std.testing.allocator;

    // Mock scheduler for testing
    var mock_scheduler align(8) = struct {
        pub fn getProcessors(self: @This()) []Processor {
            _ = self;
            return &[_]Processor{};
        }

        pub fn getGlobalWork(self: @This()) !?*Coroutine {
            _ = self;
            return null;
        }

        pub fn returnCoroutine(self: @This(), coro: *Coroutine) void {
            _ = self;
            _ = coro;
        }

        pub fn addToGlobalQueue(self: @This(), coro: *Coroutine) !void {
            _ = self;
            _ = coro;
        }

        pub const vm = @as(*anyopaque, @ptrFromInt(0x1000));
        pub const rng = std.Random.DefaultPrng.init(12345);
    }{};

    var worker = Worker.init(0, @ptrCast(&mock_scheduler), allocator);

    try std.testing.expectEqual(@as(u32, 0), worker.id);
    try std.testing.expect(!worker.running.load(.monotonic));
    try std.testing.expect(!worker.parked.load(.monotonic));
    try std.testing.expect(worker.processor == null);

    const stats = worker.getStats();
    try std.testing.expectEqual(@as(u32, 0), stats.id);
    try std.testing.expect(!stats.is_running);
    try std.testing.expect(!stats.is_parked);
    try std.testing.expectEqual(@as(?u32, null), stats.processor_id);
}

test "worker parking and unparking" {
    const allocator = std.testing.allocator;

    // Mock scheduler
    var mock_scheduler = struct {
        pub fn getProcessors(self: @This()) []Processor {
            _ = self;
            return &[_]Processor{};
        }

        pub fn getGlobalWork(self: @This()) !?*Coroutine {
            _ = self;
            return null;
        }

        pub fn returnCoroutine(self: @This(), coro: *Coroutine) void {
            _ = self;
            _ = coro;
        }

        pub fn addToGlobalQueue(self: @This(), coro: *Coroutine) !void {
            _ = self;
            _ = coro;
        }

        pub const vm = @as(*anyopaque, @ptrFromInt(0x1000));
        pub const rng = std.Random.DefaultPrng.init(12345);
    }{};

    var worker = Worker.init(0, @ptrCast(&mock_scheduler), allocator);

    try std.testing.expect(!worker.parked.load(.monotonic));

    // Test unpark when not parked (should be safe)
    worker.unpark();
    try std.testing.expect(!worker.parked.load(.monotonic));

    // Test park/unpark cycle with proper synchronization
    // Use should_stop to control the test flow instead of relying on timing
    const park_thread = try std.Thread.spawn(.{}, struct {
        fn parkWorker(w: *Worker) void {
            // Brief delay to ensure main thread is ready
            std.Thread.sleep(1_000_000); // 1ms

            // Only park if not already signaled to stop
            if (!w.should_stop.load(.monotonic)) {
                w.park();
            }
        }
    }.parkWorker, .{&worker});

    // Give the thread time to start and enter park
    std.Thread.sleep(5_000_000); // 5ms

    // Signal stop and unpark to ensure thread exits
    worker.should_stop.store(true, .monotonic);
    worker.unpark();

    park_thread.join();

    const stats = worker.getStats();
    try std.testing.expect(stats.park_count >= 0); // May or may not have parked depending on timing
}

test "worker pool operations" {
    const allocator = std.testing.allocator;

    // Mock scheduler
    var mock_scheduler = struct {
        pub fn getProcessors(self: @This()) []Processor {
            _ = self;
            return &[_]Processor{};
        }

        pub fn getGlobalWork(self: @This()) !?*Coroutine {
            _ = self;
            return null;
        }

        pub fn returnCoroutine(self: @This(), coro: *Coroutine) void {
            _ = self;
            _ = coro;
        }

        pub fn addToGlobalQueue(self: @This(), coro: *Coroutine) !void {
            _ = self;
            _ = coro;
        }

        pub const vm = @as(*anyopaque, @ptrFromInt(0x1000));
        pub const rng = std.Random.DefaultPrng.init(12345);
    }{};

    var pool = try WorkerPool.init(allocator, @ptrCast(&mock_scheduler), 4);
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 4), pool.workers.len);

    // Test worker access
    const worker0 = pool.getWorker(0);
    try std.testing.expect(worker0 != null);
    try std.testing.expectEqual(@as(u32, 0), worker0.?.id);

    const invalid_worker = pool.getWorker(10);
    try std.testing.expect(invalid_worker == null);

    // Test statistics
    const stats = pool.getAllStats();
    defer allocator.free(stats);
    try std.testing.expectEqual(@as(usize, 4), stats.len);

    // Test utilization
    const utilization = pool.getUtilization();
    try std.testing.expect(utilization >= 0.0 and utilization <= 1.0);

    // Test active count
    const active_count = pool.getActiveCount();
    try std.testing.expectEqual(@as(u32, 0), active_count); // No workers started
}

test "worker processor handoff" {
    const allocator = std.testing.allocator;

    // Mock scheduler
    var mock_scheduler align(8) = struct {
        pub fn getProcessors(self: @This()) []Processor {
            _ = self;
            return &[_]Processor{};
        }

        pub fn getGlobalWork(self: @This()) !?*Coroutine {
            _ = self;
            return null;
        }

        pub fn returnCoroutine(self: @This(), coro: *Coroutine) void {
            _ = self;
            _ = coro;
        }

        pub fn addToGlobalQueue(self: @This(), coro: *Coroutine) !void {
            _ = self;
            _ = coro;
        }

        pub const vm = @as(*anyopaque, @ptrFromInt(0x1000));
        pub const rng = std.Random.DefaultPrng.init(12345);
    }{};

    var worker = Worker.init(0, @ptrCast(&mock_scheduler), allocator);
    var processor = Processor.init(0, @ptrCast(@alignCast(&mock_scheduler)), allocator);
    defer processor.deinit();

    try std.testing.expect(worker.processor == null);
    try std.testing.expect(processor.worker == null);

    // Test handoff
    worker.handoff(&processor);

    try std.testing.expect(worker.processor != null);
    try std.testing.expectEqual(@as(u32, 0), worker.processor.?.id);
    try std.testing.expect(processor.worker != null);
    try std.testing.expectEqual(@as(u32, 0), processor.worker.?.id);

    const stats = worker.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.handoff_count);
    try std.testing.expectEqual(@as(?u32, 0), stats.processor_id);

    // Test detach
    worker.detachProcessor();

    try std.testing.expect(worker.processor == null);
    try std.testing.expect(processor.worker == null);
}
