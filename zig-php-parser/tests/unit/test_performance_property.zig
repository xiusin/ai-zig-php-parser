//! ============================================================================
//! Performance Property Tests - Property 26: Thread-safe VM access
//! ============================================================================
//!
//! This module implements property-based tests for thread-safe VM access
//! and performance optimizations.
//!
//! Property 26: Thread-safe VM access
//! - Multiple threads can safely access VM resources concurrently
//! - No data races or memory corruption under concurrent access
//! - Performance scales with number of threads
//!
//! Validates: Requirements 12.2
//! ============================================================================

const std = @import("std");
const performance_pool = @import("../../src/runtime/performance_pool.zig");
const scheduler_opt = @import("../../src/runtime/scheduler_optimization.zig");
const types = @import("../../src/runtime/types.zig");
const Value = types.Value;

/// Property 26: Thread-safe VM access
/// Tests that concurrent access to shared resources is safe
test "Property 26: Thread-safe lock-free pool access" {
    const TestStruct = struct {
        value: u64,
        data: [56]u8,
    };
    
    var pool = performance_pool.LockFreePool(TestStruct).init(std.testing.allocator);
    defer pool.deinit();
    
    const thread_count = 4;
    const iterations_per_thread = 100;
    
    var success_count = std.atomic.Value(u64).init(0);
    var error_count = std.atomic.Value(u64).init(0);
    
    const ThreadContext = struct {
        pool_ptr: *performance_pool.LockFreePool(TestStruct),
        success_ptr: *std.atomic.Value(u64),
        error_ptr: *std.atomic.Value(u64),
        thread_id: usize,
    };
    
    const threadFunc = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < iterations_per_thread) : (i += 1) {
                // Acquire from pool
                if (ctx.pool_ptr.acquire()) |obj| {
                    // Write thread-specific data
                    obj.value = @as(u64, ctx.thread_id) * 1000 + i;
                    
                    // Verify data integrity
                    if (obj.value == @as(u64, ctx.thread_id) * 1000 + i) {
                        _ = ctx.success_ptr.fetchAdd(1, .monotonic);
                    } else {
                        _ = ctx.error_ptr.fetchAdd(1, .monotonic);
                    }
                    
                    // Release back to pool
                    ctx.pool_ptr.release(obj);
                } else |_| {
                    _ = ctx.error_ptr.fetchAdd(1, .monotonic);
                }
            }
        }
    }.run;
    
    var threads: [thread_count]std.Thread = undefined;
    
    // Spawn threads
    for (0..thread_count) |i| {
        threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ThreadContext{
            .pool_ptr = &pool,
            .success_ptr = &success_count,
            .error_ptr = &error_count,
            .thread_id = i,
        }});
    }
    
    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }
    
    // Verify no errors occurred
    const errors = error_count.load(.monotonic);
    const successes = success_count.load(.monotonic);
    
    try std.testing.expectEqual(@as(u64, 0), errors);
    try std.testing.expectEqual(@as(u64, thread_count * iterations_per_thread), successes);
    
    // Verify pool statistics are consistent
    const stats = pool.getStats();
    try std.testing.expect(stats.total_acquired >= thread_count * iterations_per_thread);
    try std.testing.expect(stats.total_released >= thread_count * iterations_per_thread);
}

test "Property 26: Thread-safe lock-free work queue" {
    var queue = scheduler_opt.LockFreeWorkQueue(256).init();
    
    const producer_count = 2;
    const consumer_count = 2;
    const items_per_producer = 50;
    
    var produced_count = std.atomic.Value(u64).init(0);
    var consumed_count = std.atomic.Value(u64).init(0);
    var running = std.atomic.Value(bool).init(true);
    
    const ProducerContext = struct {
        queue_ptr: *scheduler_opt.LockFreeWorkQueue(256),
        produced_ptr: *std.atomic.Value(u64),
        items_to_produce: usize,
    };
    
    const ConsumerContext = struct {
        queue_ptr: *scheduler_opt.LockFreeWorkQueue(256),
        consumed_ptr: *std.atomic.Value(u64),
        running_ptr: *std.atomic.Value(bool),
    };
    
    const producerFunc = struct {
        fn run(ctx: ProducerContext) void {
            var i: usize = 0;
            while (i < ctx.items_to_produce) : (i += 1) {
                // Create mock coroutine pointer
                const mock_coro: *@import("../../src/runtime/coroutine.zig").Coroutine = @ptrFromInt(0x1000 + i);
                
                // Try to enqueue with backoff
                var attempts: u32 = 0;
                while (!ctx.queue_ptr.tryEnqueue(mock_coro) and attempts < 100) {
                    attempts += 1;
                    std.atomic.spinLoopHint();
                }
                
                if (attempts < 100) {
                    _ = ctx.produced_ptr.fetchAdd(1, .monotonic);
                }
            }
        }
    }.run;
    
    const consumerFunc = struct {
        fn run(ctx: ConsumerContext) void {
            while (ctx.running_ptr.load(.monotonic) or !ctx.queue_ptr.isEmpty()) {
                if (ctx.queue_ptr.tryDequeue()) |_| {
                    _ = ctx.consumed_ptr.fetchAdd(1, .monotonic);
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    }.run;
    
    var producers: [producer_count]std.Thread = undefined;
    var consumers: [consumer_count]std.Thread = undefined;
    
    // Start consumers first
    for (0..consumer_count) |i| {
        consumers[i] = try std.Thread.spawn(.{}, consumerFunc, .{ConsumerContext{
            .queue_ptr = &queue,
            .consumed_ptr = &consumed_count,
            .running_ptr = &running,
        }});
    }
    
    // Start producers
    for (0..producer_count) |i| {
        producers[i] = try std.Thread.spawn(.{}, producerFunc, .{ProducerContext{
            .queue_ptr = &queue,
            .produced_ptr = &produced_count,
            .items_to_produce = items_per_producer,
        }});
    }
    
    // Wait for producers
    for (producers) |thread| {
        thread.join();
    }
    
    // Signal consumers to stop
    running.store(false, .monotonic);
    
    // Wait for consumers
    for (consumers) |thread| {
        thread.join();
    }
    
    // Verify all produced items were consumed
    const produced = produced_count.load(.monotonic);
    const consumed = consumed_count.load(.monotonic);
    
    try std.testing.expectEqual(produced, consumed);
    
    // Verify queue statistics
    const stats = queue.getStats();
    try std.testing.expectEqual(stats.enqueue_count, stats.dequeue_count);
}

test "Property 26: Thread-safe cache-aligned arena" {
    var arena = performance_pool.CacheAlignedArena.init(std.testing.allocator);
    defer arena.deinit();
    
    // Test that allocations are properly aligned
    const data1 = try arena.alloc(u64, 10);
    try std.testing.expect(data1.len == 10);
    try std.testing.expect(@intFromPtr(data1.ptr) % 64 == 0); // Cache-line aligned
    
    const data2 = try arena.alloc(u8, 100);
    try std.testing.expect(data2.len == 100);
    try std.testing.expect(@intFromPtr(data2.ptr) % 64 == 0); // Cache-line aligned
    
    // Verify statistics
    const stats = arena.getStats();
    try std.testing.expect(stats.allocation_count == 2);
    try std.testing.expect(stats.total_used > 0);
    try std.testing.expect(stats.utilization > 0.0);
}

test "Property 26: Thread-safe coroutine memory pool" {
    var pool = performance_pool.CoroutineMemoryPool.init(std.testing.allocator);
    defer pool.deinit();
    
    const thread_count = 4;
    const iterations_per_thread = 10;
    
    var success_count = std.atomic.Value(u64).init(0);
    
    const ThreadContext = struct {
        pool_ptr: *performance_pool.CoroutineMemoryPool,
        success_ptr: *std.atomic.Value(u64),
    };
    
    const threadFunc = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < iterations_per_thread) : (i += 1) {
                // Acquire stack
                if (ctx.pool_ptr.acquireStack(16 * 1024)) |stack| {
                    // Write to stack to verify it's usable
                    stack[0] = 0xAA;
                    stack[stack.len - 1] = 0xBB;
                    
                    // Verify data integrity
                    if (stack[0] == 0xAA and stack[stack.len - 1] == 0xBB) {
                        _ = ctx.success_ptr.fetchAdd(1, .monotonic);
                    }
                    
                    // Release stack
                    ctx.pool_ptr.releaseStack(stack);
                } else |_| {}
            }
        }
    }.run;
    
    var threads: [thread_count]std.Thread = undefined;
    
    for (0..thread_count) |i| {
        threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ThreadContext{
            .pool_ptr = &pool,
            .success_ptr = &success_count,
        }});
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    const successes = success_count.load(.monotonic);
    try std.testing.expectEqual(@as(u64, thread_count * iterations_per_thread), successes);
}

test "Property 26: Thread-safe work stealer" {
    var stealer = scheduler_opt.OptimizedWorkStealer.init(std.testing.allocator, 4);
    
    const thread_count = 4;
    const iterations_per_thread = 100;
    
    const ThreadContext = struct {
        stealer_ptr: *scheduler_opt.OptimizedWorkStealer,
        thread_id: usize,
    };
    
    const threadFunc = struct {
        fn run(ctx: ThreadContext) void {
            const loads = [_]f64{ 0.1, 0.5, 0.8, 0.3 };
            
            var i: usize = 0;
            while (i < iterations_per_thread) : (i += 1) {
                // Select victim
                const victim = ctx.stealer_ptr.selectVictim(ctx.thread_id, &loads);
                _ = victim;
                
                // Record result (alternating success/failure)
                ctx.stealer_ptr.recordStealResult(i % 2 == 0, if (i % 2 == 0) 5 else 0);
            }
        }
    }.run;
    
    var threads: [thread_count]std.Thread = undefined;
    
    for (0..thread_count) |i| {
        threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ThreadContext{
            .stealer_ptr = &stealer,
            .thread_id = i,
        }});
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    // Verify statistics are consistent
    const stats = stealer.getStats();
    try std.testing.expectEqual(@as(u64, thread_count * iterations_per_thread), stats.steal_attempts);
    try std.testing.expect(stats.steal_successes > 0);
    try std.testing.expect(stats.steal_failures > 0);
}

test "Property 26: Thread-safe performance manager" {
    var manager = performance_pool.PerformanceManager.init(std.testing.allocator);
    defer manager.deinit();
    
    const thread_count = 4;
    const iterations_per_thread = 20;
    
    var success_count = std.atomic.Value(u64).init(0);
    
    const ThreadContext = struct {
        manager_ptr: *performance_pool.PerformanceManager,
        success_ptr: *std.atomic.Value(u64),
    };
    
    const threadFunc = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < iterations_per_thread) : (i += 1) {
                // Test coroutine stack allocation
                if (ctx.manager_ptr.acquireCoroutineStack(16 * 1024)) |stack| {
                    stack[0] = 0xCC;
                    ctx.manager_ptr.releaseCoroutineStack(stack);
                    _ = ctx.success_ptr.fetchAdd(1, .monotonic);
                } else |_| {}
                
                // Test value pool
                if (ctx.manager_ptr.acquireValue()) |value| {
                    value.* = Value.initNull();
                    ctx.manager_ptr.releaseValue(value);
                    _ = ctx.success_ptr.fetchAdd(1, .monotonic);
                } else |_| {}
            }
        }
    }.run;
    
    var threads: [thread_count]std.Thread = undefined;
    
    for (0..thread_count) |i| {
        threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ThreadContext{
            .manager_ptr = &manager,
            .success_ptr = &success_count,
        }});
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    const successes = success_count.load(.monotonic);
    // Each thread does 2 operations per iteration
    try std.testing.expectEqual(@as(u64, thread_count * iterations_per_thread * 2), successes);
    
    // Verify manager statistics
    const report = manager.getStats();
    try std.testing.expect(report.global_stats.total_allocations > 0);
}

test "Property 26: Scheduler optimization manager thread safety" {
    const config = scheduler_opt.SchedulerOptimizationManager.OptimizationConfig{
        .num_processors = 4,
        .batch_size = 16,
    };
    
    var manager = try scheduler_opt.SchedulerOptimizationManager.init(std.testing.allocator, config);
    defer manager.deinit();
    
    const thread_count = 4;
    const iterations_per_thread = 50;
    
    const ThreadContext = struct {
        manager_ptr: *scheduler_opt.SchedulerOptimizationManager,
        thread_id: usize,
    };
    
    const threadFunc = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < iterations_per_thread) : (i += 1) {
                // Record operations
                ctx.manager_ptr.recordOperation();
                
                // Select steal victim
                const victim = ctx.manager_ptr.selectStealVictim(ctx.thread_id);
                _ = victim;
                
                // Update processor state
                if (ctx.thread_id < ctx.manager_ptr.processor_states.len) {
                    ctx.manager_ptr.processor_states[ctx.thread_id].updateQueueSize(1);
                    ctx.manager_ptr.processor_states[ctx.thread_id].recordActivity();
                    ctx.manager_ptr.processor_states[ctx.thread_id].updateQueueSize(-1);
                }
            }
        }
    }.run;
    
    var threads: [thread_count]std.Thread = undefined;
    
    for (0..thread_count) |i| {
        threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ThreadContext{
            .manager_ptr = &manager,
            .thread_id = i,
        }});
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    // Verify statistics
    const stats = manager.getStats();
    try std.testing.expectEqual(@as(u64, thread_count * iterations_per_thread), stats.total_operations);
}
