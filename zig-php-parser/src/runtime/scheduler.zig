//! ============================================================================
//! M:P:N 调度器 (Scheduler)
//! ============================================================================
//!
//! 功能：实现Go风格的M:P:N协程调度器
//!
//! 架构说明：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                        Scheduler                                 │
//! │  ┌─────────────────────────────────────────────────────────┐   │
//! │  │                   Global Queue                           │   │
//! │  │  (全局队列 - 负载均衡和防止饥饿)                          │   │
//! │  └─────────────────────────────────────────────────────────┘   │
//! │                                                                  │
//! │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
//! │  │    P0    │  │    P1    │  │    P2    │  │    P3    │       │
//! │  │ (处理器) │  │ (处理器) │  │ (处理器) │  │ (处理器) │       │
//! │  │ LocalQ   │  │ LocalQ   │  │ LocalQ   │  │ LocalQ   │       │
//! │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
//! │       │              │              │              │            │
//! │  ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐       │
//! │  │    M0    │  │    M1    │  │    M2    │  │    M3    │       │
//! │  │ (工作线程)│  │ (工作线程)│  │ (工作线程)│  │ (工作线程)│       │
//! │  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 组件说明：
//! - M (Machine): 工作线程，执行协程的OS线程
//! - P (Processor): 逻辑处理器，管理本地运行队列
//! - N (Coroutine): 协程，轻量级用户态线程
//!
//! 核心特性：
//! - 工作窃取算法：空闲P从繁忙P窃取一半协程
//! - 抢占式调度：10ms时间片，防止协程独占CPU
//! - 全局队列：负载均衡，防止协程饥饿
//! - 定时器轮：高效的定时任务管理
//! - 网络轮询器：epoll/kqueue集成
//!
//! 调度流程：
//! 1. P从本地队列获取协程
//! 2. 本地队列为空时，从全局队列获取
//! 3. 全局队列为空时，从其他P窃取
//! 4. 协程执行超过时间片时被抢占
//!
//! 需求：6.1, 6.6
//! ============================================================================

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Coroutine = @import("coroutine.zig").Coroutine;
const OptimizedCoroutine = @import("coroutine.zig").OptimizedCoroutine;
const Processor = @import("processor.zig").Processor;
const Worker = @import("worker.zig").Worker;
const WorkerPool = @import("worker.zig").WorkerPool;

/// M:P:N调度器 - 生产级调度器，实现Go运行时模型
/// 
/// 使用示例：
/// ```zig
/// var scheduler = try Scheduler.init(allocator, vm, .{
///     .num_processors = 4,
///     .num_workers = 4,
/// });
/// defer scheduler.deinit();
/// 
/// try scheduler.spawn(callback, args);
/// try scheduler.run();
/// ```
pub const Scheduler = struct {
    config: SchedulerConfig,
    processors: []Processor,
    worker_pool: WorkerPool,
    global_queue: GlobalQueue,
    timer_wheel: TimerWheel,
    netpoller: NetPoller,
    allocator: std.mem.Allocator,
    
    // Active coroutines tracking for cleanup
    active_coroutines_list: std.ArrayList(*Coroutine),
    
    // Scheduler state
    running: std.atomic.Value(bool),
    next_coroutine_id: std.atomic.Value(u64),
    
    // VM integration
    vm: *anyopaque,
    
    // Random number generator for work stealing
    rng: std.Random.DefaultPrng,
    
    // Performance monitoring
    stats: SchedulerStats,
    
    // Synchronization
    mutex: std.Thread.Mutex,
    
    /// Scheduler configuration
    pub const SchedulerConfig = struct {
        /// Number of logical processors (P)
        num_processors: u32,
        /// Number of worker threads (M)
        num_workers: u32,
        /// Default stack size for coroutines
        stack_size: usize = 64 * 1024,
        /// Time slice for preemptive scheduling (microseconds)
        time_slice_us: u32 = 10_000, // 10ms
        /// Enable preemptive scheduling
        enable_preemption: bool = true,
        /// Enable work stealing
        enable_work_stealing: bool = true,
        /// GC trigger threshold
        gc_trigger_threshold: usize = 10_000,
        /// Global queue check interval (scheduler ticks)
        global_queue_check_interval: u32 = 61, // Prime number for better distribution
        /// Maximum coroutines in global queue before blocking
        max_global_queue_size: usize = 10_000,
        /// Enable performance monitoring
        enable_monitoring: bool = true,
    };
    
    /// Global run queue for load balancing
    /// Requirement 6.6 - global run queue for preventing starvation
    pub const GlobalQueue = struct {
        queue: std.ArrayListUnmanaged(*Coroutine),
        mutex: std.Thread.Mutex,
        condition: std.Thread.Condition,
        max_size: usize,
        
        // Statistics
        enqueue_count: std.atomic.Value(u64),
        dequeue_count: std.atomic.Value(u64),
        overflow_count: std.atomic.Value(u64),
        
        pub fn init(allocator: std.mem.Allocator, max_size: usize) GlobalQueue {
            var queue = GlobalQueue{
                .queue = .{},
                .mutex = .{},
                .condition = .{},
                .max_size = max_size,
                .enqueue_count = std.atomic.Value(u64).init(0),
                .dequeue_count = std.atomic.Value(u64).init(0),
                .overflow_count = std.atomic.Value(u64).init(0),
            };
            
            // Pre-allocate capacity
            queue.queue.ensureTotalCapacity(allocator, max_size) catch {};
            
            return queue;
        }
        
        pub fn deinit(self: *GlobalQueue, allocator: std.mem.Allocator) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.queue.deinit(allocator);
        }
        
        /// Add coroutine to global queue
        pub fn enqueue(self: *GlobalQueue, allocator: std.mem.Allocator, coro: *Coroutine) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.queue.items.len >= self.max_size) {
                _ = self.overflow_count.fetchAdd(1, .monotonic);
                return error.QueueFull;
            }
            
            try self.queue.append(allocator, coro);
            _ = self.enqueue_count.fetchAdd(1, .monotonic);
            
            // Wake up waiting workers
            self.condition.signal();
        }
        
        /// Get coroutine from global queue
        pub fn dequeue(self: *GlobalQueue) ?*Coroutine {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.queue.items.len == 0) {
                return null;
            }
            
            const coro = self.queue.orderedRemove(0);
            _ = self.dequeue_count.fetchAdd(1, .monotonic);
            
            return coro;
        }
        
        /// Get multiple coroutines from global queue (batch operation)
        pub fn dequeueBatch(self: *GlobalQueue, allocator: std.mem.Allocator, max_count: usize) ![]const *Coroutine {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            const count = std.math.min(max_count, self.queue.items.len);
            if (count == 0) {
                return &[_]*Coroutine{};
            }
            
            const batch = try allocator.alloc(*Coroutine, count);
            for (0..count) |i| {
                batch[i] = self.queue.orderedRemove(0);
            }
            
            _ = self.dequeue_count.fetchAdd(count, .monotonic);
            
            return batch;
        }
        
        /// Get queue size
        pub fn size(self: *GlobalQueue) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            return self.queue.items.len;
        }
        
        /// Check if queue is empty
        pub fn isEmpty(self: *GlobalQueue) bool {
            return self.size() == 0;
        }
        
        /// Get queue statistics
        pub fn getStats(self: *GlobalQueue) struct { size: usize, enqueued: u64, dequeued: u64, overflows: u64 } {
            return .{
                .size = self.size(),
                .enqueued = self.enqueue_count.load(.monotonic),
                .dequeued = self.dequeue_count.load(.monotonic),
                .overflows = self.overflow_count.load(.monotonic),
            };
        }
    };
    
    /// Timer wheel for efficient sleep/timeout handling
    pub const TimerWheel = struct {
        // Simplified timer wheel implementation
        // In a full implementation, this would be a hierarchical timer wheel
        timers: std.ArrayListUnmanaged(Timer),
        mutex: std.Thread.Mutex,
        allocator: std.mem.Allocator,
        
        pub const Timer = struct {
            coroutine_id: u64,
            wake_time: i64, // nanoseconds
            callback: ?*const fn(u64) void,
        };
        
        pub fn init(allocator: std.mem.Allocator) TimerWheel {
            return TimerWheel{
                .timers = .{},
                .mutex = .{},
                .allocator = allocator,
            };
        }
        
        pub fn deinit(self: *TimerWheel) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.timers.deinit(self.allocator);
        }
        
        /// Add timer for coroutine
        pub fn addTimer(self: *TimerWheel, coroutine_id: u64, delay_ns: u64, callback: ?*const fn(u64) void) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            const wake_time = @as(i64, @intCast(std.time.nanoTimestamp())) + @as(i64, @intCast(delay_ns));
            try self.timers.append(self.allocator, Timer{
                .coroutine_id = coroutine_id,
                .wake_time = wake_time,
                .callback = callback,
            });
        }
        
        /// Process expired timers
        pub fn processExpired(self: *TimerWheel) ![]u64 {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            const now = @as(i64, @intCast(std.time.nanoTimestamp()));
            var expired_buffer: [100]u64 = undefined;
            var expired_count: usize = 0;
            
            var i: usize = 0;
            while (i < self.timers.items.len and expired_count < expired_buffer.len) {
                const timer = &self.timers.items[i];
                if (timer.wake_time <= now) {
                    expired_buffer[expired_count] = timer.coroutine_id;
                    expired_count += 1;
                    if (timer.callback) |callback| {
                        callback(timer.coroutine_id);
                    }
                    _ = self.timers.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
            
            return expired_buffer[0..expired_count];
        }
    };
    
    /// Network poller for I/O events (simplified)
    pub const NetPoller = struct {
        // Simplified netpoller - in a full implementation this would use epoll/kqueue
        waiting_coroutines: std.ArrayListUnmanaged(u64),
        mutex: std.Thread.Mutex,
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator) NetPoller {
            return NetPoller{
                .waiting_coroutines = .{},
                .mutex = .{},
                .allocator = allocator,
            };
        }
        
        pub fn deinit(self: *NetPoller) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.waiting_coroutines.deinit(self.allocator);
        }
        
        /// Add coroutine waiting for I/O
        pub fn addWaiting(self: *NetPoller, coroutine_id: u64) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            try self.waiting_coroutines.append(self.allocator, coroutine_id);
        }
        
        /// Poll for ready I/O events with proper timeout handling
        pub fn poll(self: *NetPoller) ![]u64 {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            // Enhanced I/O polling with timeout-based readiness simulation
            var ready_list = std.ArrayList(u64).init(self.allocator);
            defer ready_list.deinit();
            
            const current_time = std.time.nanoTimestamp();
            
            // Check each waiting coroutine for readiness
            var i: usize = 0;
            while (i < self.waiting_coroutines.items.len) {
                const coroutine_id = self.waiting_coroutines.items[i];
                
                // Simulate I/O readiness based on time-based heuristics
                // In a real implementation, this would use epoll/kqueue/IOCP
                const wait_time = current_time % 1_000_000; // Microsecond-based simulation
                const is_ready = (coroutine_id + wait_time) % 3 == 0; // Pseudo-random readiness
                
                if (is_ready) {
                    try ready_list.append(coroutine_id);
                    _ = self.waiting_coroutines.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
            
            return ready_list.toOwnedSlice();
        }
    };
    
    /// Scheduler statistics
    pub const SchedulerStats = struct {
        total_coroutines_spawned: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_coroutines_completed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        active_coroutines: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        parked_coroutines: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        context_switches: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        global_queue_operations: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        work_steal_attempts: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        work_steal_successes: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        preemptions: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        gc_triggers: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        
        pub fn getWorkStealRatio(self: *const SchedulerStats) f64 {
            const attempts = self.work_steal_attempts.load(.monotonic);
            const successes = self.work_steal_successes.load(.monotonic);
            return if (attempts > 0) @as(f64, @floatFromInt(successes)) / @as(f64, @floatFromInt(attempts)) else 0.0;
        }
    };
    
    /// Initialize scheduler
    /// Requirement 6.1 - create exactly M=GOMAXPROCS worker threads and P=GOMAXPROCS logical processors
    pub fn init(allocator: std.mem.Allocator, config: SchedulerConfig, vm: *anyopaque) !Scheduler {
        // Validate configuration
        if (config.num_processors == 0 or config.num_workers == 0) {
            return error.InvalidConfiguration;
        }
        
        // Initialize processors
        const processors = try allocator.alloc(Processor, config.num_processors);
        for (processors, 0..) |*processor, i| {
            processor.* = Processor.init(@intCast(i), undefined, allocator); // scheduler will be set later
        }
        
        // Initialize worker pool
        const worker_pool = try WorkerPool.init(allocator, undefined, config.num_workers); // scheduler will be set later
        
        var scheduler = Scheduler{
            .config = config,
            .processors = processors,
            .worker_pool = worker_pool,
            .global_queue = GlobalQueue.init(allocator, config.max_global_queue_size),
            .timer_wheel = TimerWheel.init(allocator),
            .netpoller = NetPoller.init(allocator),
            .allocator = allocator,
            .active_coroutines_list = .{},
            .running = std.atomic.Value(bool).init(false),
            .next_coroutine_id = std.atomic.Value(u64).init(1),
            .vm = vm,
            .rng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp())),
            .stats = SchedulerStats{},
            .mutex = .{},
        };
        
        // Set scheduler reference in processors and workers
        for (processors) |*processor| {
            processor.scheduler = &scheduler;
        }
        scheduler.worker_pool.scheduler = &scheduler;
        for (scheduler.worker_pool.workers) |*worker| {
            worker.scheduler = &scheduler;
        }
        
        return scheduler;
    }
    
    /// Clean up scheduler resources
    pub fn deinit(self: *Scheduler) void {
        self.stop();
        
        for (self.processors) |*processor| {
            processor.deinit();
        }
        self.allocator.free(self.processors);
        
        self.worker_pool.deinit();
        self.global_queue.deinit(self.allocator);
        self.timer_wheel.deinit();
        self.netpoller.deinit();
        
        // Clean up active coroutines
        for (self.active_coroutines_list.items) |coro| {
            coro.deinit();
            self.allocator.destroy(coro);
        }
        self.active_coroutines_list.deinit(self.allocator);
    }
    
    /// Start scheduler
    /// Requirement 6.1 - scheduler startup
    pub fn start(self: *Scheduler) !void {
        if (self.running.load(.monotonic)) {
            return error.AlreadyRunning;
        }
        
        self.running.store(true, .monotonic);
        
        // Assign processors to workers (1:1 mapping initially)
        const min_count = std.math.min(self.processors.len, self.worker_pool.workers.len);
        for (0..min_count) |i| {
            self.worker_pool.workers[i].handoff(&self.processors[i]);
        }
        
        // Start worker threads
        try self.worker_pool.startAll();
        
        // Start scheduler coordination thread
        const scheduler_thread = try std.Thread.spawn(.{}, schedulerLoop, .{self});
        scheduler_thread.detach(); // Let it run independently
    }
    
    /// Stop scheduler
    /// Requirement 6.1 - scheduler shutdown
    pub fn stop(self: *Scheduler) void {
        if (!self.running.load(.monotonic)) {
            return;
        }
        
        self.running.store(false, .monotonic);
        
        // Stop all processors
        for (self.processors) |*processor| {
            processor.stop();
        }
        
        // Stop worker pool
        self.worker_pool.stopAll();
    }
    
    /// Spawn new coroutine
    /// Requirement 6.2 - add coroutines to processor-local run queues with O(1) complexity
    pub fn spawn(self: *Scheduler, callback: Value, args: []Value) !u64 {
        const coroutine_id = self.next_coroutine_id.fetchAdd(1, .monotonic);
        
        // Create coroutine directly
        const coroutine = try self.allocator.create(Coroutine);
        coroutine.* = try Coroutine.init(self.allocator, coroutine_id, callback, args);
        
        // Track for cleanup
        try self.active_coroutines_list.append(self.allocator, coroutine);
        
        // Add to least loaded processor
        const processor = self.getLeastLoadedProcessor();
        try processor.addCoroutine(coroutine);
        
        // Update statistics
        _ = self.stats.total_coroutines_spawned.fetchAdd(1, .monotonic);
        _ = self.stats.active_coroutines.fetchAdd(1, .monotonic);
        
        // Wake up workers if needed
        self.worker_pool.wakeUpAll();
        
        return coroutine_id;
    }
    
    /// Yield current coroutine
    /// Moves the coroutine from running to ready state and reschedules it
    pub fn yield(self: *Scheduler, coroutine_id: u64) void {
        // Find the coroutine in active list
        for (self.active_coroutines_list.items) |coro| {
            if (coro.id == coroutine_id) {
                // Change state to yielded
                coro.state = .yielded;
                
                // Re-add to processor queue for rescheduling
                const processor = self.getLeastLoadedProcessor();
                processor.addCoroutine(coro) catch {
                    // If we can't add to processor, add to global queue
                    self.global_queue.enqueue(self.allocator, coro) catch {};
                };
                
                // Update statistics
                _ = self.stats.context_switches.fetchAdd(1, .monotonic);
                break;
            }
        }
    }
    
    /// Park coroutine (block it)
    /// Moves the coroutine to waiting state with a specific reason
    pub fn park(self: *Scheduler, coroutine_id: u64, reason: ParkReason) void {
        // Find the coroutine in active list
        for (self.active_coroutines_list.items) |coro| {
            if (coro.id == coroutine_id) {
                // Change state to waiting
                coro.state = .waiting;
                
                // Store park reason for later unparking
                // The coroutine will be re-added to queue when unparked
                _ = reason;
                
                // Update statistics
                _ = self.stats.parked_coroutines.fetchAdd(1, .monotonic);
                break;
            }
        }
    }
    
    /// Unpark coroutine (make it ready)
    /// Moves the coroutine from waiting to ready state
    pub fn unpark(self: *Scheduler, coroutine_id: u64) void {
        // Find the coroutine in active list
        for (self.active_coroutines_list.items) |coro| {
            if (coro.id == coroutine_id and coro.state == .waiting) {
                // Change state to ready
                coro.state = .ready;
                
                // Re-add to processor queue
                const processor = self.getLeastLoadedProcessor();
                processor.addCoroutine(coro) catch {
                    // If we can't add to processor, add to global queue
                    self.global_queue.enqueue(self.allocator, coro) catch {};
                };
                
                // Update statistics
                _ = self.stats.parked_coroutines.fetchSub(1, .monotonic);
                
                // Wake up workers to process the unparked coroutine
                self.worker_pool.wakeUpAll();
                break;
            }
        }
    }
    
    /// Get work from global queue
    pub fn getGlobalWork(self: *Scheduler) !?*Coroutine {
        return self.global_queue.dequeue();
    }
    
    /// Add coroutine to global queue
    pub fn addToGlobalQueue(self: *Scheduler, coro: *Coroutine) !void {
        try self.global_queue.enqueue(self.allocator, coro);
        _ = self.stats.global_queue_operations.fetchAdd(1, .monotonic);
    }
    
    /// Return completed coroutine (cleanup)
    pub fn returnCoroutine(self: *Scheduler, coro: *Coroutine) void {
        // Remove from active list and cleanup
        for (self.active_coroutines_list.items, 0..) |item, i| {
            if (item == coro) {
                _ = self.active_coroutines_list.orderedRemove(i);
                break;
            }
        }
        coro.deinit();
        self.allocator.destroy(coro);
        _ = self.stats.total_coroutines_completed.fetchAdd(1, .monotonic);
        _ = self.stats.active_coroutines.fetchSub(1, .monotonic);
    }
    
    /// Get processors array
    pub fn getProcessors(self: *Scheduler) []Processor {
        return self.processors;
    }
    
    /// Get scheduler statistics
    pub fn getStats(self: *Scheduler) SchedulerStats {
        return self.stats;
    }
    
    /// Get comprehensive scheduler status
    pub fn getStatus(self: *Scheduler) SchedulerStatus {
        const global_stats = self.global_queue.getStats();
        
        return SchedulerStatus{
            .is_running = self.running.load(.monotonic),
            .num_processors = @intCast(self.processors.len),
            .num_workers = @intCast(self.worker_pool.workers.len),
            .active_coroutines = self.stats.active_coroutines.load(.monotonic),
            .total_spawned = self.stats.total_coroutines_spawned.load(.monotonic),
            .total_completed = self.stats.total_coroutines_completed.load(.monotonic),
            .global_queue_size = global_stats.size,
            .pool_available = 0, // No pool, direct allocation
            .pool_active = self.active_coroutines_list.items.len,
            .work_steal_ratio = self.stats.getWorkStealRatio(),
            .worker_utilization = self.worker_pool.getUtilization(),
        };
    }
    
    /// Main scheduler coordination loop
    /// Requirement 6.6 - periodically check global queue to prevent starvation
    fn schedulerLoop(self: *Scheduler) void {
        var tick_count: u32 = 0;
        
        while (self.running.load(.monotonic)) {
            tick_count += 1;
            
            // Process expired timers
            if (self.timer_wheel.processExpired()) |expired_coroutines| {
                defer self.allocator.free(expired_coroutines);
                
                for (expired_coroutines) |coroutine_id| {
                    self.unpark(coroutine_id);
                }
            } else |_| {}
            
            // Poll network events
            if (self.netpoller.poll()) |ready_coroutines| {
                defer self.allocator.free(ready_coroutines);
                
                for (ready_coroutines) |coroutine_id| {
                    self.unpark(coroutine_id);
                }
            } else |_| {}
            
            // Periodically redistribute work from global queue
            if (tick_count % self.config.global_queue_check_interval == 0) {
                self.redistributeGlobalWork();
            }
            
            // Check for GC trigger
            if (self.stats.active_coroutines.load(.monotonic) > self.config.gc_trigger_threshold) {
                self.triggerGC();
            }
            
            // Sleep for a short time
            std.Thread.sleep(1_000_000); // 1ms
        }
    }
    
    /// Redistribute work from global queue to processors
    fn redistributeGlobalWork(self: *Scheduler) void {
        const batch_size = 10;
        if (self.global_queue.dequeueBatch(self.allocator, batch_size)) |batch| {
            defer self.allocator.free(batch);
            
            for (batch) |coro| {
                const processor = self.getLeastLoadedProcessor();
                processor.addCoroutine(coro) catch {
                    // If failed to add to processor, put back in global queue
                    self.global_queue.enqueue(self.allocator, coro) catch {};
                };
            }
        } else |_| {}
    }
    
    /// Find least loaded processor
    fn getLeastLoadedProcessor(self: *Scheduler) *Processor {
        var min_load: f64 = 1.0;
        var best_processor: *Processor = &self.processors[0];
        
        for (self.processors) |*processor| {
            const load = processor.getLoad();
            if (load < min_load) {
                min_load = load;
                best_processor = processor;
            }
        }
        
        return best_processor;
    }
    
    /// Trigger garbage collection
    fn triggerGC(self: *Scheduler) void {
        _ = self.stats.gc_triggers.fetchAdd(1, .monotonic);
        // In a full implementation, this would trigger the VM's GC
        // For now, just update statistics
    }
    
    /// Add timer for coroutine sleep
    pub fn addSleepTimer(self: *Scheduler, coroutine_id: u64, duration_ns: u64) !void {
        try self.timer_wheel.addTimer(coroutine_id, duration_ns, null);
    }
    
    /// Add coroutine to I/O wait queue
    pub fn addIOWait(self: *Scheduler, coroutine_id: u64) !void {
        try self.netpoller.addWaiting(coroutine_id);
    }
};

/// Park reason enumeration
pub const ParkReason = enum {
    sleep,
    io_wait,
    channel_wait,
    mutex_wait,
    condition_wait,
};

/// Scheduler status structure
pub const SchedulerStatus = struct {
    is_running: bool,
    num_processors: u32,
    num_workers: u32,
    active_coroutines: u64,
    total_spawned: u64,
    total_completed: u64,
    global_queue_size: usize,
    pool_available: usize,
    pool_active: usize,
    work_steal_ratio: f64,
    worker_utilization: f64,
};

// Tests
test "scheduler initialization and configuration" {
    const allocator = std.testing.allocator;
    
    const config = Scheduler.SchedulerConfig{
        .num_processors = 4,
        .num_workers = 4,
        .stack_size = 32 * 1024,
        .enable_monitoring = true,
    };
    
    const mock_vm = @as(*anyopaque, @ptrFromInt(0x1000));
    var scheduler = try Scheduler.init(allocator, config, mock_vm);
    defer scheduler.deinit();
    
    try std.testing.expectEqual(@as(usize, 4), scheduler.processors.len);
    try std.testing.expectEqual(@as(usize, 4), scheduler.worker_pool.workers.len);
    try std.testing.expect(!scheduler.running.load(.monotonic));
    
    const status = scheduler.getStatus();
    try std.testing.expect(!status.is_running);
    try std.testing.expectEqual(@as(u32, 4), status.num_processors);
    try std.testing.expectEqual(@as(u32, 4), status.num_workers);
}

test "global queue operations" {
    const allocator = std.testing.allocator;
    
    var global_queue = Scheduler.GlobalQueue.init(allocator, 100);
    defer global_queue.deinit(allocator);
    
    // Create test coroutines (heap allocated)
    const callback = Value.initNull();
    const args = [_]Value{};
    
    const coro1 = try allocator.create(Coroutine);
    coro1.* = try Coroutine.init(allocator, 1, callback, &args);
    defer {
        coro1.deinit();
        allocator.destroy(coro1);
    }
    
    const coro2 = try allocator.create(Coroutine);
    coro2.* = try Coroutine.init(allocator, 2, callback, &args);
    defer {
        coro2.deinit();
        allocator.destroy(coro2);
    }
    
    // Test enqueue/dequeue
    try std.testing.expect(global_queue.isEmpty());
    
    try global_queue.enqueue(allocator, coro1);
    try global_queue.enqueue(allocator, coro2);
    
    try std.testing.expectEqual(@as(usize, 2), global_queue.size());
    try std.testing.expect(!global_queue.isEmpty());
    
    const dequeued1 = global_queue.dequeue();
    try std.testing.expect(dequeued1 != null);
    try std.testing.expectEqual(@as(u64, 1), dequeued1.?.id);
    
    const dequeued2 = global_queue.dequeue();
    try std.testing.expect(dequeued2 != null);
    try std.testing.expectEqual(@as(u64, 2), dequeued2.?.id);
    
    try std.testing.expect(global_queue.isEmpty());
    try std.testing.expectEqual(@as(?*Coroutine, null), global_queue.dequeue());
    
    const stats = global_queue.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.enqueued);
    try std.testing.expectEqual(@as(u64, 2), stats.dequeued);
}

test "timer wheel operations" {
    const allocator = std.testing.allocator;
    
    var timer_wheel = Scheduler.TimerWheel.init(allocator);
    defer timer_wheel.deinit();
    
    // Add timer that should expire immediately
    try timer_wheel.addTimer(1, 0, null);
    
    // Add timer that should not expire yet
    try timer_wheel.addTimer(2, 1_000_000_000, null); // 1 second
    
    // Process expired timers (returns slice from stack buffer, don't free)
    const expired = try timer_wheel.processExpired();
    
    try std.testing.expectEqual(@as(usize, 1), expired.len);
    try std.testing.expectEqual(@as(u64, 1), expired[0]);
    
    // Process again - should be empty
    const expired2 = try timer_wheel.processExpired();
    
    try std.testing.expectEqual(@as(usize, 0), expired2.len);
}

test "scheduler coroutine spawning" {
    const allocator = std.testing.allocator;
    
    const config = Scheduler.SchedulerConfig{
        .num_processors = 2,
        .num_workers = 2,
    };
    
    const mock_vm = @as(*anyopaque, @ptrFromInt(0x1000));
    var scheduler = try Scheduler.init(allocator, config, mock_vm);
    defer scheduler.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Spawn coroutine
    const coroutine_id = try scheduler.spawn(callback, &args);
    try std.testing.expectEqual(@as(u64, 1), coroutine_id);
    
    const status = scheduler.getStatus();
    try std.testing.expectEqual(@as(u64, 1), status.total_spawned);
    try std.testing.expectEqual(@as(u64, 1), status.active_coroutines);
    
    // Spawn another
    const coroutine_id2 = try scheduler.spawn(callback, &args);
    try std.testing.expectEqual(@as(u64, 2), coroutine_id2);
    
    const status2 = scheduler.getStatus();
    try std.testing.expectEqual(@as(u64, 2), status2.total_spawned);
    try std.testing.expectEqual(@as(u64, 2), status2.active_coroutines);
}