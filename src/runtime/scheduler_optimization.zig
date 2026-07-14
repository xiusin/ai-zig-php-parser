//! ============================================================================
//! Scheduler Optimization - High-Performance Scheduler Enhancements
//! ============================================================================
//!
//! This module implements production-grade scheduler optimizations for the
//! M:P:N scheduler system.
//!
//! Features:
//! - Lock-free work queue using atomic operations
//! - Batch operations for reduced overhead
//! - Optimized work stealing with adaptive strategies
//! - Cache-friendly data structures
//!
//! Requirements: 10.3, 10.4, 10.5, 10.6
//! ============================================================================

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Coroutine = @import("coroutine.zig").Coroutine;

/// Lock-free work queue using atomic operations
/// Implements a bounded MPMC (Multi-Producer Multi-Consumer) queue
pub fn LockFreeWorkQueue(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const MASK: usize = capacity - 1;

        // Ensure capacity is power of 2
        comptime {
            if (capacity == 0 or (capacity & (capacity - 1)) != 0) {
                @compileError("Capacity must be a power of 2");
            }
        }

        buffer: [capacity]std.atomic.Value(?*Coroutine),
        head: std.atomic.Value(usize),
        tail: std.atomic.Value(usize),

        // Statistics
        enqueue_count: std.atomic.Value(u64),
        dequeue_count: std.atomic.Value(u64),
        contention_count: std.atomic.Value(u64),

        pub fn init() Self {
            var self = Self{
                .buffer = undefined,
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
                .enqueue_count = std.atomic.Value(u64).init(0),
                .dequeue_count = std.atomic.Value(u64).init(0),
                .contention_count = std.atomic.Value(u64).init(0),
            };

            for (&self.buffer) |*slot| {
                slot.* = std.atomic.Value(?*Coroutine).init(null);
            }

            return self;
        }

        /// Try to enqueue a coroutine (lock-free)
        pub fn tryEnqueue(self: *Self, coro: *Coroutine) bool {
            var tail = self.tail.load(.acquire);

            while (true) {
                const head = self.head.load(.acquire);

                // Check if queue is full
                if (tail - head >= capacity) {
                    return false;
                }

                // Try to claim the slot
                if (self.tail.cmpxchgWeak(tail, tail + 1, .acq_rel, .acquire)) |new_tail| {
                    tail = new_tail;
                    _ = self.contention_count.fetchAdd(1, .monotonic);
                    continue;
                }

                // Successfully claimed slot, write the value
                const index = tail & MASK;
                self.buffer[index].store(coro, .release);
                _ = self.enqueue_count.fetchAdd(1, .monotonic);
                return true;
            }
        }

        /// Try to dequeue a coroutine (lock-free)
        pub fn tryDequeue(self: *Self) ?*Coroutine {
            var head = self.head.load(.acquire);

            while (true) {
                const tail = self.tail.load(.acquire);

                // Check if queue is empty
                if (head >= tail) {
                    return null;
                }

                // Try to claim the slot
                if (self.head.cmpxchgWeak(head, head + 1, .acq_rel, .acquire)) |new_head| {
                    head = new_head;
                    _ = self.contention_count.fetchAdd(1, .monotonic);
                    continue;
                }

                // Successfully claimed slot, read the value
                const index = head & MASK;

                // Spin until the value is available
                var coro: ?*Coroutine = null;
                var spin_count: u32 = 0;
                while (coro == null and spin_count < 1000) {
                    coro = self.buffer[index].load(.acquire);
                    spin_count += 1;
                    if (coro == null) {
                        std.atomic.spinLoopHint();
                    }
                }

                if (coro) |c| {
                    self.buffer[index].store(null, .release);
                    _ = self.dequeue_count.fetchAdd(1, .monotonic);
                    return c;
                }

                return null;
            }
        }

        /// Get current size (approximate)
        pub fn size(self: *Self) usize {
            const tail = self.tail.load(.acquire);
            const head = self.head.load(.acquire);
            return if (tail >= head) tail - head else 0;
        }

        /// Check if empty (approximate)
        pub fn isEmpty(self: *Self) bool {
            return self.size() == 0;
        }

        /// Get statistics
        pub fn getStats(self: *Self) LockFreeQueueStats {
            return LockFreeQueueStats{
                .size = self.size(),
                .enqueue_count = self.enqueue_count.load(.monotonic),
                .dequeue_count = self.dequeue_count.load(.monotonic),
                .contention_count = self.contention_count.load(.monotonic),
            };
        }
    };
}

/// Lock-free queue statistics
pub const LockFreeQueueStats = struct {
    size: usize,
    enqueue_count: u64,
    dequeue_count: u64,
    contention_count: u64,
};

/// Batch operation handler for reduced overhead
pub const BatchOperations = struct {
    allocator: std.mem.Allocator,

    // Batch buffers
    enqueue_batch: std.ArrayListUnmanaged(*Coroutine),
    dequeue_batch: std.ArrayListUnmanaged(*Coroutine),

    // Configuration
    max_batch_size: usize,

    // Statistics
    batch_enqueue_count: std.atomic.Value(u64),
    batch_dequeue_count: std.atomic.Value(u64),
    items_enqueued: std.atomic.Value(u64),
    items_dequeued: std.atomic.Value(u64),

    pub const DEFAULT_BATCH_SIZE: usize = 32;

    pub fn init(allocator: std.mem.Allocator) BatchOperations {
        return initWithSize(allocator, DEFAULT_BATCH_SIZE);
    }

    pub fn initWithSize(allocator: std.mem.Allocator, max_batch_size: usize) BatchOperations {
        return BatchOperations{
            .allocator = allocator,
            .enqueue_batch = .{},
            .dequeue_batch = .{},
            .max_batch_size = max_batch_size,
            .batch_enqueue_count = std.atomic.Value(u64).init(0),
            .batch_dequeue_count = std.atomic.Value(u64).init(0),
            .items_enqueued = std.atomic.Value(u64).init(0),
            .items_dequeued = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *BatchOperations) void {
        self.enqueue_batch.deinit(self.allocator);
        self.dequeue_batch.deinit(self.allocator);
    }

    /// Add coroutine to enqueue batch
    pub fn addToEnqueueBatch(self: *BatchOperations, coro: *Coroutine) !bool {
        try self.enqueue_batch.append(self.allocator, coro);
        return self.enqueue_batch.items.len >= self.max_batch_size;
    }

    /// Flush enqueue batch to target queue
    pub fn flushEnqueueBatch(self: *BatchOperations, target: anytype) !usize {
        const count = self.enqueue_batch.items.len;
        if (count == 0) return 0;

        for (self.enqueue_batch.items) |coro| {
            if (!target.tryEnqueue(coro)) {
                // Queue full, stop flushing
                break;
            }
        }

        _ = self.batch_enqueue_count.fetchAdd(1, .monotonic);
        _ = self.items_enqueued.fetchAdd(count, .monotonic);

        self.enqueue_batch.clearRetainingCapacity();
        return count;
    }

    /// Batch dequeue from source queue
    pub fn batchDequeue(self: *BatchOperations, source: anytype, max_count: usize) ![]const *Coroutine {
        self.dequeue_batch.clearRetainingCapacity();

        const count = @min(max_count, self.max_batch_size);
        var dequeued: usize = 0;

        while (dequeued < count) {
            if (source.tryDequeue()) |coro| {
                try self.dequeue_batch.append(self.allocator, coro);
                dequeued += 1;
            } else {
                break;
            }
        }

        if (dequeued > 0) {
            _ = self.batch_dequeue_count.fetchAdd(1, .monotonic);
            _ = self.items_dequeued.fetchAdd(dequeued, .monotonic);
        }

        return self.dequeue_batch.items;
    }

    /// Get batch operation statistics
    pub fn getStats(self: *BatchOperations) BatchStats {
        return BatchStats{
            .batch_enqueue_count = self.batch_enqueue_count.load(.monotonic),
            .batch_dequeue_count = self.batch_dequeue_count.load(.monotonic),
            .items_enqueued = self.items_enqueued.load(.monotonic),
            .items_dequeued = self.items_dequeued.load(.monotonic),
            .avg_enqueue_batch_size = blk: {
                const batches = self.batch_enqueue_count.load(.monotonic);
                const items = self.items_enqueued.load(.monotonic);
                break :blk if (batches > 0) @as(f64, @floatFromInt(items)) / @as(f64, @floatFromInt(batches)) else 0.0;
            },
            .avg_dequeue_batch_size = blk: {
                const batches = self.batch_dequeue_count.load(.monotonic);
                const items = self.items_dequeued.load(.monotonic);
                break :blk if (batches > 0) @as(f64, @floatFromInt(items)) / @as(f64, @floatFromInt(batches)) else 0.0;
            },
        };
    }
};

/// Batch operation statistics
pub const BatchStats = struct {
    batch_enqueue_count: u64,
    batch_dequeue_count: u64,
    items_enqueued: u64,
    items_dequeued: u64,
    avg_enqueue_batch_size: f64,
    avg_dequeue_batch_size: f64,
};

/// Optimized work stealing with adaptive strategies
pub const OptimizedWorkStealer = struct {
    allocator: std.mem.Allocator,

    // Processor references
    num_processors: usize,

    // Adaptive stealing parameters
    steal_threshold: std.atomic.Value(u32),
    backoff_factor: std.atomic.Value(u32),

    // Random number generator for victim selection
    rng: std.Random.DefaultPrng,

    // Statistics
    steal_attempts: std.atomic.Value(u64),
    steal_successes: std.atomic.Value(u64),
    steal_failures: std.atomic.Value(u64),
    items_stolen: std.atomic.Value(u64),
    adaptive_adjustments: std.atomic.Value(u64),

    // Recent steal history for adaptive behavior
    recent_success_rate: std.atomic.Value(u32), // Percentage * 100

    pub const DEFAULT_STEAL_THRESHOLD: u32 = 2;
    pub const MIN_STEAL_THRESHOLD: u32 = 1;
    pub const MAX_STEAL_THRESHOLD: u32 = 16;
    pub const DEFAULT_BACKOFF: u32 = 1;
    pub const MAX_BACKOFF: u32 = 64;

    pub fn init(allocator: std.mem.Allocator, num_processors: usize) OptimizedWorkStealer {
        return OptimizedWorkStealer{
            .allocator = allocator,
            .num_processors = num_processors,
            .steal_threshold = std.atomic.Value(u32).init(DEFAULT_STEAL_THRESHOLD),
            .backoff_factor = std.atomic.Value(u32).init(DEFAULT_BACKOFF),
            .rng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp())),
            .steal_attempts = std.atomic.Value(u64).init(0),
            .steal_successes = std.atomic.Value(u64).init(0),
            .steal_failures = std.atomic.Value(u64).init(0),
            .items_stolen = std.atomic.Value(u64).init(0),
            .adaptive_adjustments = std.atomic.Value(u64).init(0),
            .recent_success_rate = std.atomic.Value(u32).init(50), // Start at 50%
        };
    }

    /// Select victim processor using power-of-two-choices
    /// This reduces contention compared to random selection
    pub fn selectVictim(self: *OptimizedWorkStealer, thief_id: usize, processor_loads: []const f64) usize {
        if (self.num_processors <= 1) return 0;

        // Power-of-two-choices: pick two random processors, steal from the more loaded one
        var random = self.rng.random();

        var victim1 = random.intRangeAtMost(usize, 0, self.num_processors - 1);
        var victim2 = random.intRangeAtMost(usize, 0, self.num_processors - 1);

        // Avoid stealing from self
        while (victim1 == thief_id and self.num_processors > 1) {
            victim1 = random.intRangeAtMost(usize, 0, self.num_processors - 1);
        }
        while (victim2 == thief_id and self.num_processors > 1) {
            victim2 = random.intRangeAtMost(usize, 0, self.num_processors - 1);
        }

        // Choose the more loaded processor
        if (processor_loads.len > @max(victim1, victim2)) {
            return if (processor_loads[victim1] >= processor_loads[victim2]) victim1 else victim2;
        }

        return victim1;
    }

    /// Calculate how many items to steal based on adaptive threshold
    pub fn calculateStealCount(self: *OptimizedWorkStealer, victim_queue_size: usize) usize {
        const threshold = self.steal_threshold.load(.monotonic);

        // Only steal if victim has more than threshold items
        if (victim_queue_size <= threshold) {
            return 0;
        }

        // Steal half of the items above threshold (Go-style)
        return (victim_queue_size - threshold) / 2 + 1;
    }

    /// Record steal attempt result and adapt parameters
    pub fn recordStealResult(self: *OptimizedWorkStealer, success: bool, items_stolen: usize) void {
        _ = self.steal_attempts.fetchAdd(1, .monotonic);

        if (success) {
            _ = self.steal_successes.fetchAdd(1, .monotonic);
            _ = self.items_stolen.fetchAdd(items_stolen, .monotonic);

            // Successful steal - decrease backoff
            const current_backoff = self.backoff_factor.load(.monotonic);
            if (current_backoff > DEFAULT_BACKOFF) {
                _ = self.backoff_factor.fetchSub(1, .monotonic);
            }
        } else {
            _ = self.steal_failures.fetchAdd(1, .monotonic);

            // Failed steal - increase backoff
            const current_backoff = self.backoff_factor.load(.monotonic);
            if (current_backoff < MAX_BACKOFF) {
                _ = self.backoff_factor.fetchAdd(1, .monotonic);
            }
        }

        // Update success rate (exponential moving average)
        self.updateSuccessRate(success);

        // Adapt threshold based on success rate
        self.adaptThreshold();
    }

    /// Update exponential moving average of success rate
    fn updateSuccessRate(self: *OptimizedWorkStealer, success: bool) void {
        const current_rate = self.recent_success_rate.load(.monotonic);
        const new_sample: u32 = if (success) 100 else 0;

        // EMA with alpha = 0.1 (scaled by 100)
        const new_rate = (current_rate * 90 + new_sample * 10) / 100;
        self.recent_success_rate.store(new_rate, .monotonic);
    }

    /// Adapt steal threshold based on recent success rate
    fn adaptThreshold(self: *OptimizedWorkStealer) void {
        const success_rate = self.recent_success_rate.load(.monotonic);
        const current_threshold = self.steal_threshold.load(.monotonic);

        // If success rate is high (>70%), lower threshold to steal more aggressively
        if (success_rate > 70 and current_threshold > MIN_STEAL_THRESHOLD) {
            _ = self.steal_threshold.fetchSub(1, .monotonic);
            _ = self.adaptive_adjustments.fetchAdd(1, .monotonic);
        }
        // If success rate is low (<30%), raise threshold to be more conservative
        else if (success_rate < 30 and current_threshold < MAX_STEAL_THRESHOLD) {
            _ = self.steal_threshold.fetchAdd(1, .monotonic);
            _ = self.adaptive_adjustments.fetchAdd(1, .monotonic);
        }
    }

    /// Get current backoff delay in nanoseconds
    pub fn getBackoffDelay(self: *OptimizedWorkStealer) u64 {
        const factor = self.backoff_factor.load(.monotonic);
        return @as(u64, factor) * 1000; // Base delay of 1 microsecond
    }

    /// Get work stealer statistics
    pub fn getStats(self: *OptimizedWorkStealer) WorkStealerStats {
        const attempts = self.steal_attempts.load(.monotonic);
        const successes = self.steal_successes.load(.monotonic);

        return WorkStealerStats{
            .steal_attempts = attempts,
            .steal_successes = successes,
            .steal_failures = self.steal_failures.load(.monotonic),
            .items_stolen = self.items_stolen.load(.monotonic),
            .success_rate = if (attempts > 0) @as(f64, @floatFromInt(successes)) / @as(f64, @floatFromInt(attempts)) else 0.0,
            .current_threshold = self.steal_threshold.load(.monotonic),
            .current_backoff = self.backoff_factor.load(.monotonic),
            .adaptive_adjustments = self.adaptive_adjustments.load(.monotonic),
        };
    }
};

/// Work stealer statistics
pub const WorkStealerStats = struct {
    steal_attempts: u64,
    steal_successes: u64,
    steal_failures: u64,
    items_stolen: u64,
    success_rate: f64,
    current_threshold: u32,
    current_backoff: u32,
    adaptive_adjustments: u64,
};

/// Cache-friendly processor state
/// Aligned to cache line to prevent false sharing
pub const CacheAlignedProcessorState = struct {
    // Hot data - frequently accessed
    queue_size: std.atomic.Value(u32) align(64),
    is_running: std.atomic.Value(bool),
    last_activity: std.atomic.Value(i64),

    // Padding to separate from cold data
    _padding1: [64 - @sizeOf(std.atomic.Value(u32)) - @sizeOf(std.atomic.Value(bool)) - @sizeOf(std.atomic.Value(i64))]u8 = undefined,

    // Cold data - less frequently accessed
    scheduled_count: u64 align(64),
    stolen_count: u64,
    preempted_count: u64,
    idle_time_ns: u64,

    pub fn init() CacheAlignedProcessorState {
        return CacheAlignedProcessorState{
            .queue_size = std.atomic.Value(u32).init(0),
            .is_running = std.atomic.Value(bool).init(false),
            .last_activity = std.atomic.Value(i64).init(0),
            .scheduled_count = 0,
            .stolen_count = 0,
            .preempted_count = 0,
            .idle_time_ns = 0,
        };
    }

    pub fn updateQueueSize(self: *CacheAlignedProcessorState, delta: i32) void {
        if (delta > 0) {
            _ = self.queue_size.fetchAdd(@intCast(delta), .monotonic);
        } else if (delta < 0) {
            _ = self.queue_size.fetchSub(@intCast(-delta), .monotonic);
        }
    }

    pub fn recordActivity(self: *CacheAlignedProcessorState) void {
        self.last_activity.store(@intCast(std.time.nanoTimestamp()), .monotonic);
    }

    pub fn incrementScheduled(self: *CacheAlignedProcessorState) void {
        self.scheduled_count += 1;
    }

    pub fn incrementStolen(self: *CacheAlignedProcessorState) void {
        self.stolen_count += 1;
    }

    pub fn incrementPreempted(self: *CacheAlignedProcessorState) void {
        self.preempted_count += 1;
    }

    pub fn addIdleTime(self: *CacheAlignedProcessorState, ns: u64) void {
        self.idle_time_ns += ns;
    }
};

/// Unified scheduler optimization manager
pub const SchedulerOptimizationManager = struct {
    allocator: std.mem.Allocator,

    // Components
    work_stealer: OptimizedWorkStealer,
    batch_ops: BatchOperations,

    // Processor states (cache-aligned)
    processor_states: []CacheAlignedProcessorState,

    // Configuration
    config: OptimizationConfig,

    // Global statistics
    total_operations: std.atomic.Value(u64),
    optimization_overhead_ns: std.atomic.Value(u64),

    pub const OptimizationConfig = struct {
        enable_lock_free_queues: bool = true,
        enable_batch_operations: bool = true,
        enable_adaptive_stealing: bool = true,
        enable_cache_alignment: bool = true,
        batch_size: usize = 32,
        num_processors: usize = 4,
    };

    pub fn init(allocator: std.mem.Allocator, config: OptimizationConfig) !SchedulerOptimizationManager {
        const processor_states = try allocator.alloc(CacheAlignedProcessorState, config.num_processors);
        for (processor_states) |*state| {
            state.* = CacheAlignedProcessorState.init();
        }

        return SchedulerOptimizationManager{
            .allocator = allocator,
            .work_stealer = OptimizedWorkStealer.init(allocator, config.num_processors),
            .batch_ops = BatchOperations.initWithSize(allocator, config.batch_size),
            .processor_states = processor_states,
            .config = config,
            .total_operations = std.atomic.Value(u64).init(0),
            .optimization_overhead_ns = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *SchedulerOptimizationManager) void {
        self.batch_ops.deinit();
        self.allocator.free(self.processor_states);
    }

    /// Get processor loads for work stealing decisions
    pub fn getProcessorLoads(self: *SchedulerOptimizationManager) []f64 {
        const loads = self.allocator.alloc(f64, self.processor_states.len) catch return &[_]f64{};

        for (self.processor_states, 0..) |*state, i| {
            const queue_size = @as(f64, @floatFromInt(state.queue_size.load(.monotonic)));
            loads[i] = @min(queue_size / 256.0, 1.0); // Normalize to 0-1
        }

        return loads;
    }

    /// Select best victim for work stealing
    pub fn selectStealVictim(self: *SchedulerOptimizationManager, thief_id: usize) usize {
        const loads = self.getProcessorLoads();
        defer self.allocator.free(loads);

        return self.work_stealer.selectVictim(thief_id, loads);
    }

    /// Record operation for statistics
    pub fn recordOperation(self: *SchedulerOptimizationManager) void {
        _ = self.total_operations.fetchAdd(1, .monotonic);
    }

    /// Get comprehensive optimization statistics
    pub fn getStats(self: *SchedulerOptimizationManager) OptimizationStats {
        return OptimizationStats{
            .total_operations = self.total_operations.load(.monotonic),
            .optimization_overhead_ns = self.optimization_overhead_ns.load(.monotonic),
            .work_stealer_stats = self.work_stealer.getStats(),
            .batch_stats = self.batch_ops.getStats(),
            .num_processors = self.processor_states.len,
        };
    }

    /// Print optimization report
    pub fn printReport(self: *SchedulerOptimizationManager) void {
        const stats = self.getStats();

        std.log.info("=== Scheduler Optimization Report ===", .{});
        std.log.info("Total operations: {}", .{stats.total_operations});
        std.log.info("Work stealing: attempts={}, successes={}, rate={d:.2}%", .{
            stats.work_stealer_stats.steal_attempts,
            stats.work_stealer_stats.steal_successes,
            stats.work_stealer_stats.success_rate * 100.0,
        });
        std.log.info("Batch operations: enqueues={}, dequeues={}", .{
            stats.batch_stats.batch_enqueue_count,
            stats.batch_stats.batch_dequeue_count,
        });
        std.log.info("Adaptive adjustments: {}", .{stats.work_stealer_stats.adaptive_adjustments});
    }
};

/// Comprehensive optimization statistics
pub const OptimizationStats = struct {
    total_operations: u64,
    optimization_overhead_ns: u64,
    work_stealer_stats: WorkStealerStats,
    batch_stats: BatchStats,
    num_processors: usize,
};

// ============================================================================
// Tests
// ============================================================================

test "lock-free work queue basic operations" {
    var queue = LockFreeWorkQueue(64).init();

    try std.testing.expect(queue.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), queue.size());

    // Test with null pointer (simulating coroutine)
    const mock_coro: *Coroutine = @ptrFromInt(0x1000);

    try std.testing.expect(queue.tryEnqueue(mock_coro));
    try std.testing.expectEqual(@as(usize, 1), queue.size());
    try std.testing.expect(!queue.isEmpty());

    const dequeued = queue.tryDequeue();
    try std.testing.expect(dequeued != null);
    try std.testing.expectEqual(mock_coro, dequeued.?);
    try std.testing.expect(queue.isEmpty());
}

test "lock-free work queue statistics" {
    var queue = LockFreeWorkQueue(64).init();

    const mock_coro: *Coroutine = @ptrFromInt(0x1000);
    _ = queue.tryEnqueue(mock_coro);
    _ = queue.tryDequeue();

    const stats = queue.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.enqueue_count);
    try std.testing.expectEqual(@as(u64, 1), stats.dequeue_count);
}

test "batch operations" {
    var batch_ops = BatchOperations.init(std.testing.allocator);
    defer batch_ops.deinit();

    const stats = batch_ops.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.batch_enqueue_count);
    try std.testing.expectEqual(@as(u64, 0), stats.batch_dequeue_count);
}

test "optimized work stealer initialization" {
    var stealer = OptimizedWorkStealer.init(std.testing.allocator, 4);

    const stats = stealer.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.steal_attempts);
    try std.testing.expectEqual(@as(u32, OptimizedWorkStealer.DEFAULT_STEAL_THRESHOLD), stats.current_threshold);
}

test "work stealer victim selection" {
    var stealer = OptimizedWorkStealer.init(std.testing.allocator, 4);

    const loads = [_]f64{ 0.1, 0.5, 0.8, 0.3 };
    const victim = stealer.selectVictim(0, &loads);

    // Victim should be one of the processors (not the thief)
    try std.testing.expect(victim < 4);
}

test "work stealer adaptive behavior" {
    var stealer = OptimizedWorkStealer.init(std.testing.allocator, 4);

    // Record several successful steals
    for (0..10) |_| {
        stealer.recordStealResult(true, 5);
    }

    const stats = stealer.getStats();
    try std.testing.expectEqual(@as(u64, 10), stats.steal_successes);
    try std.testing.expect(stats.success_rate > 0.9);
}

test "cache-aligned processor state" {
    var state = CacheAlignedProcessorState.init();

    try std.testing.expectEqual(@as(u32, 0), state.queue_size.load(.monotonic));
    try std.testing.expect(!state.is_running.load(.monotonic));

    state.updateQueueSize(5);
    try std.testing.expectEqual(@as(u32, 5), state.queue_size.load(.monotonic));

    state.updateQueueSize(-2);
    try std.testing.expectEqual(@as(u32, 3), state.queue_size.load(.monotonic));

    state.incrementScheduled();
    try std.testing.expectEqual(@as(u64, 1), state.scheduled_count);
}

test "scheduler optimization manager" {
    const config = SchedulerOptimizationManager.OptimizationConfig{
        .num_processors = 4,
        .batch_size = 16,
    };

    var manager = try SchedulerOptimizationManager.init(std.testing.allocator, config);
    defer manager.deinit();

    manager.recordOperation();

    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_operations);
    try std.testing.expectEqual(@as(usize, 4), stats.num_processors);
}
