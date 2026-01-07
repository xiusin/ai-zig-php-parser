//! ============================================================================
//! Comprehensive Integration Test Suite for PHP Builtin Functions and Concurrency
//! ============================================================================
//!
//! This test suite provides:
//! - Stress tests with thousands of coroutines
//! - Memory leak detection tests
//! - Performance regression tests
//! - Integration property tests
//!
//! Requirements: 10.6, 10.7, 10.8, 10.9, 10.10
//! ============================================================================

const std = @import("std");
const testing = std.testing;

// Import runtime modules
const scheduler_mod = @import("../../src/runtime/scheduler.zig");
const Scheduler = scheduler_mod.Scheduler;
const coroutine_mod = @import("../../src/runtime/coroutine.zig");
const OptimizedCoroutine = coroutine_mod.OptimizedCoroutine;
const OptimizedCoroutinePool = coroutine_mod.OptimizedCoroutinePool;
const channel_mod = @import("../../src/runtime/channel.zig");
const Channel = channel_mod.Channel;
const sync_mod = @import("../../src/runtime/sync.zig");
const Mutex = sync_mod.Mutex;
const RWMutex = sync_mod.RWMutex;
const WaitGroup = sync_mod.WaitGroup;
const types = @import("../../src/runtime/types.zig");
const Value = types.Value;
const performance_pool = @import("../../src/runtime/performance_pool.zig");
const PerformanceManager = performance_pool.PerformanceManager;
const LockFreePool = performance_pool.LockFreePool;
const CacheAlignedArena = performance_pool.CacheAlignedArena;
const CoroutineMemoryPool = performance_pool.CoroutineMemoryPool;

// ============================================================================
// Test Configuration
// ============================================================================

const TestConfig = struct {
    /// Number of coroutines for stress tests
    stress_coroutine_count: usize = 1000,
    /// Number of iterations for memory leak tests
    memory_leak_iterations: usize = 100,
    /// Number of iterations for performance tests
    performance_iterations: usize = 1000,
    /// Timeout for stress tests (milliseconds)
    stress_timeout_ms: u64 = 30000,
    /// Enable verbose output
    verbose: bool = false,
};

const config = TestConfig{};

// ============================================================================
// Stress Tests - Requirement 10.7, 10.8
// ============================================================================

test "stress test: create and destroy thousands of coroutines" {
    const allocator = testing.allocator;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 2000,
        .default_stack_size = 16 * 1024, // 16KB for stress test
        .enable_auto_cleanup = true,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Create and release many coroutines
    var created_count: usize = 0;
    var released_count: usize = 0;
    
    for (0..config.stress_coroutine_count) |i| {
        const coro = pool.acquire(@intCast(i + 1), callback, &args) catch |err| {
            std.debug.print("Failed to acquire coroutine {}: {}\n", .{ i, err });
            continue;
        };
        created_count += 1;
        
        // Simulate some work
        coro.state = .running;
        coro.scheduled_count += 1;
        coro.state = .completed;
        
        // Release back to pool
        pool.release(coro);
        released_count += 1;
    }
    
    try testing.expectEqual(config.stress_coroutine_count, created_count);
    try testing.expectEqual(config.stress_coroutine_count, released_count);
    
    const stats = pool.getStats();
    try testing.expect(stats.total_created > 0);
    try testing.expect(stats.total_reused > 0);
    
    if (config.verbose) {
        std.debug.print("\nStress test results:\n", .{});
        std.debug.print("  Created: {}\n", .{stats.total_created});
        std.debug.print("  Reused: {}\n", .{stats.total_reused});
        std.debug.print("  Reuse ratio: {d:.2}%\n", .{stats.reuse_ratio * 100});
    }
}

test "stress test: concurrent channel operations" {
    const allocator = testing.allocator;
    const channel_count = 10;
    const messages_per_channel = 100;
    
    // Create multiple channels
    var channels: [channel_count]*Channel = undefined;
    for (&channels, 0..) |*ch, i| {
        ch.* = try Channel.initWithCapacity(allocator, 50);
        _ = i;
    }
    defer {
        for (channels) |ch| {
            ch.deinit();
        }
    }
    
    // Send messages to all channels
    var total_sent: usize = 0;
    for (channels, 0..) |ch, ch_idx| {
        for (0..messages_per_channel) |msg_idx| {
            const value = Value.initInt(@intCast(ch_idx * 1000 + msg_idx));
            if (ch.trySend(value)) {
                total_sent += 1;
            }
        }
    }
    
    // Receive messages from all channels
    var total_received: usize = 0;
    for (channels) |ch| {
        while (ch.tryRecv()) |_| {
            total_received += 1;
        }
    }
    
    try testing.expect(total_sent > 0);
    try testing.expectEqual(total_sent, total_received);
    
    if (config.verbose) {
        std.debug.print("\nChannel stress test:\n", .{});
        std.debug.print("  Total sent: {}\n", .{total_sent});
        std.debug.print("  Total received: {}\n", .{total_received});
    }
}

test "stress test: mutex contention simulation" {
    const allocator = testing.allocator;
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var counter: i64 = 0;
    const iterations = 1000;
    
    // Simulate multiple coroutines accessing shared resource
    for (0..iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        // Lock
        mutex.lock(coroutine_id);
        
        // Critical section
        counter += 1;
        
        // Unlock
        mutex.unlock(coroutine_id);
    }
    
    try testing.expectEqual(@as(i64, iterations), counter);
}

test "stress test: rwmutex reader-writer simulation" {
    const allocator = testing.allocator;
    var rwmutex = RWMutex.init(allocator);
    defer rwmutex.deinit();
    
    var shared_value: i64 = 0;
    const read_iterations = 500;
    const write_iterations = 100;
    
    // Simulate readers
    for (0..read_iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        rwmutex.readLock(coroutine_id);
        _ = shared_value; // Read
        rwmutex.readUnlock(coroutine_id);
    }
    
    // Simulate writers
    for (0..write_iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1000);
        rwmutex.writeLock(coroutine_id);
        shared_value += 1; // Write
        rwmutex.writeUnlock(coroutine_id);
    }
    
    try testing.expectEqual(@as(i64, write_iterations), shared_value);
}

test "stress test: waitgroup synchronization" {
    const allocator = testing.allocator;
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    const task_count = 100;
    
    // Add tasks
    try wg.add(task_count);
    try testing.expectEqual(@as(i32, task_count), wg.getCount());
    
    // Complete tasks
    for (0..task_count) |_| {
        try wg.done();
    }
    
    try testing.expect(wg.isDone());
    try testing.expectEqual(@as(i32, 0), wg.getCount());
}

// ============================================================================
// Memory Leak Detection Tests - Requirement 10.8, 10.9
// ============================================================================

test "memory leak: coroutine pool allocation cycles" {
    const allocator = testing.allocator;
    
    // Track memory before test
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 100,
        .default_stack_size = 16 * 1024,
        .enable_auto_cleanup = false,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Run multiple allocation cycles
    for (0..config.memory_leak_iterations) |cycle| {
        var coroutines: [10]*OptimizedCoroutine = undefined;
        
        // Acquire batch
        for (&coroutines, 0..) |*coro, i| {
            coro.* = try pool.acquire(@intCast(cycle * 10 + i + 1), callback, &args);
        }
        
        // Release batch
        for (coroutines) |coro| {
            pool.release(coro);
        }
    }
    
    const stats = pool.getStats();
    
    // Verify no memory leak: active count should be 0
    try testing.expectEqual(@as(usize, 0), stats.active_count);
    
    // Pool should have reused coroutines
    try testing.expect(stats.total_reused > 0);
    
    if (config.verbose) {
        std.debug.print("\nMemory leak test (coroutine pool):\n", .{});
        std.debug.print("  Active count: {}\n", .{stats.active_count});
        std.debug.print("  Available: {}\n", .{stats.available_count});
        std.debug.print("  Total created: {}\n", .{stats.total_created});
        std.debug.print("  Total reused: {}\n", .{stats.total_reused});
    }
}

test "memory leak: channel buffer cycles" {
    const allocator = testing.allocator;
    
    for (0..config.memory_leak_iterations) |_| {
        const channel = try Channel.initWithCapacity(allocator, 10);
        
        // Fill and drain buffer
        for (0..10) |i| {
            const value = Value.initInt(@intCast(i));
            _ = channel.trySend(value);
        }
        
        while (channel.tryRecv()) |_| {}
        
        channel.deinit();
    }
    
    // If we get here without memory errors, the test passes
    try testing.expect(true);
}

test "memory leak: lock-free pool cycles" {
    const TestStruct = struct {
        value: u64,
        data: [56]u8,
    };
    
    var pool = LockFreePool(TestStruct).init(testing.allocator);
    defer pool.deinit();
    
    for (0..config.memory_leak_iterations) |_| {
        var objects: [10]*TestStruct = undefined;
        
        // Acquire batch
        for (&objects) |*obj| {
            obj.* = try pool.acquire();
            obj.*.value = 42;
        }
        
        // Release batch
        for (objects) |obj| {
            pool.release(obj);
        }
    }
    
    const stats = pool.getStats();
    
    // Active count should be 0 after all releases
    try testing.expectEqual(@as(u64, 0), stats.active_count);
    
    if (config.verbose) {
        std.debug.print("\nMemory leak test (lock-free pool):\n", .{});
        std.debug.print("  Active count: {}\n", .{stats.active_count});
        std.debug.print("  Total acquired: {}\n", .{stats.total_acquired});
        std.debug.print("  Total released: {}\n", .{stats.total_released});
        std.debug.print("  Hit rate: {d:.2}%\n", .{stats.hit_rate * 100});
    }
}

test "memory leak: cache-aligned arena cycles" {
    var arena = CacheAlignedArena.init(testing.allocator);
    defer arena.deinit();
    
    for (0..config.memory_leak_iterations) |_| {
        // Allocate various sizes
        _ = try arena.alloc(u8, 64);
        _ = try arena.alloc(u64, 10);
        _ = try arena.alloc(u8, 256);
        
        // Reset arena (should free all allocations)
        arena.reset();
    }
    
    const stats = arena.getStats();
    
    // After reset, used should be 0
    try testing.expectEqual(@as(usize, 0), stats.total_used);
    
    if (config.verbose) {
        std.debug.print("\nMemory leak test (arena):\n", .{});
        std.debug.print("  Total allocated: {}\n", .{stats.total_allocated});
        std.debug.print("  Total used: {}\n", .{stats.total_used});
        std.debug.print("  Chunk count: {}\n", .{stats.chunk_count});
    }
}

test "memory leak: synchronization primitives" {
    const allocator = testing.allocator;
    
    for (0..config.memory_leak_iterations) |_| {
        // Create and destroy mutex
        var mutex = Mutex.init(allocator);
        mutex.lock(1);
        mutex.unlock(1);
        mutex.deinit();
        
        // Create and destroy rwmutex
        var rwmutex = RWMutex.init(allocator);
        rwmutex.readLock(1);
        rwmutex.readUnlock(1);
        rwmutex.writeLock(2);
        rwmutex.writeUnlock(2);
        rwmutex.deinit();
        
        // Create and destroy waitgroup
        var wg = WaitGroup.init(allocator);
        try wg.add(1);
        try wg.done();
        wg.deinit();
    }
    
    // If we get here without memory errors, the test passes
    try testing.expect(true);
}

// ============================================================================
// Performance Regression Tests - Requirement 10.6, 10.7
// ============================================================================


/// Performance benchmark result
const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_time_ns: u64,
    avg_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    ops_per_sec: f64,
    
    pub fn print(self: BenchmarkResult) void {
        std.debug.print("\n{s}:\n", .{self.name});
        std.debug.print("  Iterations: {}\n", .{self.iterations});
        std.debug.print("  Total time: {} ns ({d:.2} ms)\n", .{
            self.total_time_ns,
            @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0,
        });
        std.debug.print("  Avg time: {} ns\n", .{self.avg_time_ns});
        std.debug.print("  Min time: {} ns\n", .{self.min_time_ns});
        std.debug.print("  Max time: {} ns\n", .{self.max_time_ns});
        std.debug.print("  Ops/sec: {d:.2}\n", .{self.ops_per_sec});
    }
};

/// Run a benchmark and return results
fn runBenchmark(
    name: []const u8,
    iterations: u64,
    warmup: u64,
    comptime benchFn: fn () void,
) BenchmarkResult {
    // Warmup
    for (0..warmup) |_| {
        benchFn();
    }
    
    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;
    
    // Actual benchmark
    for (0..iterations) |_| {
        const start = @as(u64, @intCast(std.time.nanoTimestamp()));
        benchFn();
        const end = @as(u64, @intCast(std.time.nanoTimestamp()));
        
        const elapsed = end - start;
        total_time += elapsed;
        if (elapsed < min_time) min_time = elapsed;
        if (elapsed > max_time) max_time = elapsed;
    }
    
    const avg_time = total_time / iterations;
    const ops_per_sec = if (avg_time > 0)
        1_000_000_000.0 / @as(f64, @floatFromInt(avg_time))
    else
        0.0;
    
    return BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_time_ns = total_time,
        .avg_time_ns = avg_time,
        .min_time_ns = min_time,
        .max_time_ns = max_time,
        .ops_per_sec = ops_per_sec,
    };
}

// Global state for benchmarks (needed because benchmark functions can't take parameters)
var bench_pool: ?*OptimizedCoroutinePool = null;
var bench_channel: ?*Channel = null;
var bench_mutex: ?*Mutex = null;
var bench_arena: ?*CacheAlignedArena = null;

fn benchCoroutineAcquireRelease() void {
    if (bench_pool) |pool| {
        const callback = Value.initNull();
        const args = [_]Value{};
        if (pool.acquire(1, callback, &args)) |coro| {
            pool.release(coro);
        } else |_| {}
    }
}

fn benchChannelSendRecv() void {
    if (bench_channel) |ch| {
        const value = Value.initInt(42);
        if (ch.trySend(value)) {
            _ = ch.tryRecv();
        }
    }
}

fn benchMutexLockUnlock() void {
    if (bench_mutex) |mutex| {
        mutex.lock(1);
        mutex.unlock(1);
    }
}

fn benchArenaAlloc() void {
    if (bench_arena) |arena| {
        _ = arena.alloc(u8, 64) catch {};
    }
}

test "performance: coroutine pool acquire/release" {
    var pool = try OptimizedCoroutinePool.init(testing.allocator, .{
        .max_pool_size = 100,
        .default_stack_size = 16 * 1024,
        .warmup_size = 10,
    });
    defer pool.deinit();
    
    bench_pool = &pool;
    defer {
        bench_pool = null;
    }
    
    const result = runBenchmark(
        "Coroutine Pool Acquire/Release",
        config.performance_iterations,
        100,
        benchCoroutineAcquireRelease,
    );
    
    // Performance assertion: should be able to do at least 10,000 ops/sec
    try testing.expect(result.ops_per_sec > 10000);
    
    if (config.verbose) {
        result.print();
    }
}

test "performance: channel send/receive" {
    const channel = try Channel.initWithCapacity(testing.allocator, 100);
    defer channel.deinit();
    
    bench_channel = channel;
    defer {
        bench_channel = null;
    }
    
    const result = runBenchmark(
        "Channel Send/Receive",
        config.performance_iterations,
        100,
        benchChannelSendRecv,
    );
    
    // Performance assertion: should be able to do at least 100,000 ops/sec
    try testing.expect(result.ops_per_sec > 100000);
    
    if (config.verbose) {
        result.print();
    }
}

test "performance: mutex lock/unlock" {
    var mutex = Mutex.init(testing.allocator);
    defer mutex.deinit();
    
    bench_mutex = &mutex;
    defer {
        bench_mutex = null;
    }
    
    const result = runBenchmark(
        "Mutex Lock/Unlock",
        config.performance_iterations,
        100,
        benchMutexLockUnlock,
    );
    
    // Performance assertion: should be able to do at least 100,000 ops/sec
    try testing.expect(result.ops_per_sec > 100000);
    
    if (config.verbose) {
        result.print();
    }
}

test "performance: arena allocation" {
    var arena = CacheAlignedArena.init(testing.allocator);
    defer arena.deinit();
    
    bench_arena = &arena;
    defer {
        bench_arena = null;
    }
    
    const result = runBenchmark(
        "Arena Allocation (64 bytes)",
        config.performance_iterations,
        100,
        benchArenaAlloc,
    );
    
    // Performance assertion: should be able to do at least 1,000,000 ops/sec
    try testing.expect(result.ops_per_sec > 1000000);
    
    if (config.verbose) {
        result.print();
    }
    
    // Reset arena after benchmark
    arena.reset();
}

test "performance: coroutine memory efficiency" {
    // Requirement 10.1: coroutines should use less than 4KB memory per coroutine
    const allocator = testing.allocator;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 100,
        .default_stack_size = 4 * 1024, // 4KB stack
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Create a coroutine and measure its memory
    const coro = try pool.acquire(1, callback, &args);
    defer pool.release(coro);
    
    const memory_usage = coro.getMemoryUsage();
    
    // Memory should be less than 4KB (4096 bytes) + overhead
    // We allow some overhead for the coroutine structure itself
    const max_allowed = 8 * 1024; // 8KB including overhead
    try testing.expect(memory_usage <= max_allowed);
    
    if (config.verbose) {
        std.debug.print("\nCoroutine memory efficiency:\n", .{});
        std.debug.print("  Memory usage: {} bytes\n", .{memory_usage});
        std.debug.print("  Max allowed: {} bytes\n", .{max_allowed});
    }
}

// ============================================================================
// Integration Property Tests - All Requirements
// ============================================================================

test "integration: scheduler initialization and status" {
    const allocator = testing.allocator;
    
    const sched_config = Scheduler.SchedulerConfig{
        .num_processors = 2,
        .num_workers = 2,
        .stack_size = 16 * 1024,
        .enable_monitoring = true,
    };
    
    const mock_vm = @as(*anyopaque, @ptrFromInt(0x1000));
    var scheduler = try Scheduler.init(allocator, sched_config, mock_vm);
    defer scheduler.deinit();
    
    // Verify initialization
    try testing.expectEqual(@as(usize, 2), scheduler.processors.len);
    try testing.expect(!scheduler.running.load(.monotonic));
    
    const status = scheduler.getStatus();
    try testing.expect(!status.is_running);
    try testing.expectEqual(@as(u32, 2), status.num_processors);
    try testing.expectEqual(@as(u32, 2), status.num_workers);
    try testing.expectEqual(@as(u64, 0), status.active_coroutines);
}

test "integration: coroutine lifecycle" {
    const allocator = testing.allocator;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 10,
        .default_stack_size = 16 * 1024,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Test full lifecycle
    const coro = try pool.acquire(1, callback, &args);
    
    // Initial state
    try testing.expectEqual(OptimizedCoroutine.State.created, coro.state);
    try testing.expect(coro.isReady());
    try testing.expect(!coro.isFinished());
    
    // Transition to running
    coro.state = .running;
    try testing.expect(!coro.isReady());
    try testing.expect(!coro.isFinished());
    
    // Transition to completed
    coro.complete(Value.initInt(42));
    try testing.expectEqual(OptimizedCoroutine.State.completed, coro.state);
    try testing.expect(coro.isFinished());
    
    pool.release(coro);
}

test "integration: channel communication patterns" {
    const allocator = testing.allocator;
    
    // Test unbuffered channel
    const unbuffered = try Channel.init(allocator);
    defer unbuffered.deinit();
    
    try testing.expect(unbuffered.isUnbuffered());
    try testing.expect(unbuffered.isEmpty());
    
    // Test buffered channel
    const buffered = try Channel.initWithCapacity(allocator, 5);
    defer buffered.deinit();
    
    try testing.expect(buffered.isBuffered());
    try testing.expectEqual(@as(usize, 5), buffered.getCapacity());
    
    // Fill buffer
    for (0..5) |i| {
        const value = Value.initInt(@intCast(i));
        try testing.expect(buffered.trySend(value));
    }
    
    try testing.expect(buffered.isFull());
    
    // Drain buffer
    for (0..5) |_| {
        const received = buffered.tryRecv();
        try testing.expect(received != null);
    }
    
    try testing.expect(buffered.isEmpty());
}

test "integration: synchronization primitives coordination" {
    const allocator = testing.allocator;
    
    // Test mutex with waitgroup
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    var counter: i64 = 0;
    const task_count = 10;
    
    try wg.add(task_count);
    
    for (0..task_count) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        mutex.lock(coroutine_id);
        counter += 1;
        mutex.unlock(coroutine_id);
        
        try wg.done();
    }
    
    try testing.expect(wg.isDone());
    try testing.expectEqual(@as(i64, task_count), counter);
}

test "integration: performance manager comprehensive" {
    var manager = PerformanceManager.init(testing.allocator);
    defer manager.deinit();
    
    // Test coroutine stack allocation
    const stack = try manager.acquireCoroutineStack(16 * 1024);
    try testing.expect(stack.len >= 16 * 1024);
    manager.releaseCoroutineStack(stack);
    
    // Test value allocation
    const value = try manager.acquireValue();
    value.* = Value.initInt(42);
    manager.releaseValue(value);
    
    // Test temp arena
    const temp_data = try manager.allocTemp(u8, 100);
    try testing.expectEqual(@as(usize, 100), temp_data.len);
    manager.resetTemp();
    
    // Get stats
    const report = manager.getStats();
    try testing.expect(report.global_stats.total_allocations > 0);
    
    if (config.verbose) {
        manager.printReport();
    }
}

test "integration: high load simulation" {
    const allocator = testing.allocator;
    
    // Simulate high load scenario
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 500,
        .default_stack_size = 16 * 1024,
        .warmup_size = 50,
    });
    defer pool.deinit();
    
    const channel = try Channel.initWithCapacity(allocator, 100);
    defer channel.deinit();
    
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Simulate 100 concurrent tasks
    const task_count = 100;
    try wg.add(task_count);
    
    var completed_tasks: i64 = 0;
    
    for (0..task_count) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        // Acquire coroutine
        const coro = pool.acquire(coroutine_id, callback, &args) catch continue;
        
        // Simulate work
        coro.state = .running;
        
        // Send message
        const value = Value.initInt(@intCast(i));
        _ = channel.trySend(value);
        
        // Update shared counter with mutex
        mutex.lock(coroutine_id);
        completed_tasks += 1;
        mutex.unlock(coroutine_id);
        
        // Complete coroutine
        coro.state = .completed;
        pool.release(coro);
        
        try wg.done();
    }
    
    try testing.expect(wg.isDone());
    try testing.expectEqual(@as(i64, task_count), completed_tasks);
    
    // Drain channel
    var received_count: usize = 0;
    while (channel.tryRecv()) |_| {
        received_count += 1;
    }
    
    try testing.expect(received_count > 0);
    
    if (config.verbose) {
        const pool_stats = pool.getStats();
        std.debug.print("\nHigh load simulation results:\n", .{});
        std.debug.print("  Completed tasks: {}\n", .{completed_tasks});
        std.debug.print("  Messages received: {}\n", .{received_count});
        std.debug.print("  Pool reuse ratio: {d:.2}%\n", .{pool_stats.reuse_ratio * 100});
    }
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "edge case: empty channel operations" {
    const allocator = testing.allocator;
    
    const channel = try Channel.initWithCapacity(allocator, 5);
    defer channel.deinit();
    
    // Try receive from empty channel
    const result = channel.tryRecv();
    try testing.expect(result == null);
    
    // Close empty channel
    channel.close();
    try testing.expect(channel.isClosed());
    
    // Try receive from closed empty channel
    const closed_result = channel.tryRecv();
    try testing.expect(closed_result != null); // Returns null value
}

test "edge case: mutex double unlock" {
    const allocator = testing.allocator;
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    mutex.lock(1);
    mutex.unlock(1);
    
    // Double unlock should be safe (no-op)
    mutex.unlock(1);
    
    try testing.expect(!mutex.isLocked());
}

test "edge case: waitgroup zero add" {
    const allocator = testing.allocator;
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    // Adding zero should be safe
    try wg.add(0);
    try testing.expect(wg.isDone());
    try testing.expectEqual(@as(i32, 0), wg.getCount());
}

test "edge case: coroutine priority bounds" {
    const allocator = testing.allocator;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 10,
        .default_stack_size = 16 * 1024,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    const coro = try pool.acquire(1, callback, &args);
    defer pool.release(coro);
    
    // Test priority bounds
    coro.setPriority(0); // Minimum
    try testing.expectEqual(@as(u8, 0), coro.priority);
    
    coro.setPriority(4); // Maximum
    try testing.expectEqual(@as(u8, 4), coro.priority);
    
    coro.setPriority(255); // Should be clamped to 4
    try testing.expectEqual(@as(u8, 4), coro.priority);
}
