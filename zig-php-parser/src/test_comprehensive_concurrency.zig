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
const scheduler_mod = @import("runtime/scheduler.zig");
const Scheduler = scheduler_mod.Scheduler;
const coroutine_mod = @import("runtime/coroutine.zig");
const OptimizedCoroutine = coroutine_mod.OptimizedCoroutine;
const OptimizedCoroutinePool = coroutine_mod.OptimizedCoroutinePool;
const channel_mod = @import("runtime/channel.zig");
const Channel = channel_mod.Channel;
const sync_mod = @import("runtime/sync.zig");
const Mutex = sync_mod.Mutex;
const RWMutex = sync_mod.RWMutex;
const WaitGroup = sync_mod.WaitGroup;
const types = @import("runtime/types.zig");
const Value = types.Value;
const performance_pool = @import("runtime/performance_pool.zig");
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
};

const config = TestConfig{};

// ============================================================================
// Stress Tests - Requirement 10.7, 10.8
// ============================================================================

test "stress test: create and destroy thousands of coroutines" {
    const allocator = testing.allocator;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 2000,
        .default_stack_size = 16 * 1024,
        .enable_auto_cleanup = true,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    var created_count: usize = 0;
    var released_count: usize = 0;
    
    for (0..config.stress_coroutine_count) |i| {
        const coro = pool.acquire(@intCast(i + 1), callback, &args) catch continue;
        created_count += 1;
        
        coro.state = .running;
        coro.scheduled_count += 1;
        coro.state = .completed;
        
        pool.release(coro);
        released_count += 1;
    }
    
    try testing.expectEqual(config.stress_coroutine_count, created_count);
    try testing.expectEqual(config.stress_coroutine_count, released_count);
    
    const stats = pool.getStats();
    try testing.expect(stats.total_created > 0);
    try testing.expect(stats.total_reused > 0);
}

test "stress test: concurrent channel operations" {
    const allocator = testing.allocator;
    const channel_count = 10;
    const messages_per_channel = 100;
    
    var channels: [channel_count]*Channel = undefined;
    for (&channels) |*ch| {
        ch.* = try Channel.initWithCapacity(allocator, 50);
    }
    defer {
        for (channels) |ch| {
            ch.deinit();
        }
    }
    
    var total_sent: usize = 0;
    for (channels, 0..) |ch, ch_idx| {
        for (0..messages_per_channel) |msg_idx| {
            const value = Value.initInt(@intCast(ch_idx * 1000 + msg_idx));
            if (ch.trySend(value)) {
                total_sent += 1;
            }
        }
    }
    
    var total_received: usize = 0;
    for (channels) |ch| {
        while (ch.tryRecv()) |_| {
            total_received += 1;
        }
    }
    
    try testing.expect(total_sent > 0);
    try testing.expectEqual(total_sent, total_received);
}

test "stress test: mutex contention simulation" {
    const allocator = testing.allocator;
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var counter: i64 = 0;
    const iterations = 1000;
    
    for (0..iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        mutex.lock(coroutine_id);
        counter += 1;
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
    
    for (0..read_iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        rwmutex.readLock(coroutine_id);
        // Read shared value
        if (shared_value >= 0) {
            // Simulate read operation
        }
        rwmutex.readUnlock(coroutine_id);
    }
    
    for (0..write_iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1000);
        rwmutex.writeLock(coroutine_id);
        shared_value += 1;
        rwmutex.writeUnlock(coroutine_id);
    }
    
    try testing.expectEqual(@as(i64, write_iterations), shared_value);
}

test "stress test: waitgroup synchronization" {
    const allocator = testing.allocator;
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    const task_count = 100;
    
    try wg.add(task_count);
    try testing.expectEqual(@as(i32, task_count), wg.getCount());
    
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
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 100,
        .default_stack_size = 16 * 1024,
        .enable_auto_cleanup = false,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    for (0..config.memory_leak_iterations) |cycle| {
        var coroutines: [10]*OptimizedCoroutine = undefined;
        
        for (&coroutines, 0..) |*coro, i| {
            coro.* = try pool.acquire(@intCast(cycle * 10 + i + 1), callback, &args);
        }
        
        for (coroutines) |coro| {
            pool.release(coro);
        }
    }
    
    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 0), stats.active_count);
    try testing.expect(stats.total_reused > 0);
}

test "memory leak: channel buffer cycles" {
    const allocator = testing.allocator;
    
    for (0..config.memory_leak_iterations) |_| {
        const channel = try Channel.initWithCapacity(allocator, 10);
        
        for (0..10) |i| {
            const value = Value.initInt(@intCast(i));
            _ = channel.trySend(value);
        }
        
        while (channel.tryRecv()) |_| {}
        
        channel.deinit();
    }
    
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
        
        for (&objects) |*obj| {
            obj.* = try pool.acquire();
            obj.*.value = 42;
        }
        
        for (objects) |obj| {
            pool.release(obj);
        }
    }
    
    const stats = pool.getStats();
    try testing.expectEqual(@as(u64, 0), stats.active_count);
}

test "memory leak: cache-aligned arena cycles" {
    var arena = CacheAlignedArena.init(testing.allocator);
    defer arena.deinit();
    
    for (0..config.memory_leak_iterations) |_| {
        _ = try arena.alloc(u8, 64);
        _ = try arena.alloc(u64, 10);
        _ = try arena.alloc(u8, 256);
        arena.reset();
    }
    
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 0), stats.total_used);
}

test "memory leak: synchronization primitives" {
    const allocator = testing.allocator;
    
    for (0..config.memory_leak_iterations) |_| {
        var mutex = Mutex.init(allocator);
        mutex.lock(1);
        mutex.unlock(1);
        mutex.deinit();
        
        var rwmutex = RWMutex.init(allocator);
        rwmutex.readLock(1);
        rwmutex.readUnlock(1);
        rwmutex.writeLock(2);
        rwmutex.writeUnlock(2);
        rwmutex.deinit();
        
        var wg = WaitGroup.init(allocator);
        try wg.add(1);
        try wg.done();
        wg.deinit();
    }
    
    try testing.expect(true);
}

// ============================================================================
// Performance Regression Tests - Requirement 10.6, 10.7
// ============================================================================

const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_time_ns: u64,
    avg_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    ops_per_sec: f64,
};

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

fn runBenchmark(
    name: []const u8,
    iterations: u64,
    warmup: u64,
    comptime benchFn: fn () void,
) BenchmarkResult {
    for (0..warmup) |_| {
        benchFn();
    }
    
    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;
    
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
    
    try testing.expect(result.ops_per_sec > 10000);
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
    
    try testing.expect(result.ops_per_sec > 100000);
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
    
    try testing.expect(result.ops_per_sec > 100000);
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
    
    try testing.expect(result.ops_per_sec > 1000000);
    arena.reset();
}

test "performance: coroutine memory efficiency" {
    const allocator = testing.allocator;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 100,
        .default_stack_size = 4 * 1024,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    const coro = try pool.acquire(1, callback, &args);
    defer pool.release(coro);
    
    const memory_usage = coro.getMemoryUsage();
    const max_allowed = 8 * 1024;
    try testing.expect(memory_usage <= max_allowed);
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
    
    const coro = try pool.acquire(1, callback, &args);
    
    try testing.expectEqual(OptimizedCoroutine.State.created, coro.state);
    try testing.expect(coro.isReady());
    try testing.expect(!coro.isFinished());
    
    coro.state = .running;
    try testing.expect(!coro.isReady());
    try testing.expect(!coro.isFinished());
    
    coro.complete(Value.initInt(42));
    try testing.expectEqual(OptimizedCoroutine.State.completed, coro.state);
    try testing.expect(coro.isFinished());
    
    pool.release(coro);
}

test "integration: channel communication patterns" {
    const allocator = testing.allocator;
    
    const unbuffered = try Channel.init(allocator);
    defer unbuffered.deinit();
    
    try testing.expect(unbuffered.isUnbuffered());
    try testing.expect(unbuffered.isEmpty());
    
    const buffered = try Channel.initWithCapacity(allocator, 5);
    defer buffered.deinit();
    
    try testing.expect(buffered.isBuffered());
    try testing.expectEqual(@as(usize, 5), buffered.getCapacity());
    
    for (0..5) |i| {
        const value = Value.initInt(@intCast(i));
        try testing.expect(buffered.trySend(value));
    }
    
    try testing.expect(buffered.isFull());
    
    for (0..5) |_| {
        const received = buffered.tryRecv();
        try testing.expect(received != null);
    }
    
    try testing.expect(buffered.isEmpty());
}

test "integration: synchronization primitives coordination" {
    const allocator = testing.allocator;
    
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
    
    const stack = try manager.acquireCoroutineStack(16 * 1024);
    try testing.expect(stack.len >= 16 * 1024);
    manager.releaseCoroutineStack(stack);
    
    const value = try manager.acquireValue();
    value.* = Value.initInt(42);
    manager.releaseValue(value);
    
    const temp_data = try manager.allocTemp(u8, 100);
    try testing.expectEqual(@as(usize, 100), temp_data.len);
    manager.resetTemp();
    
    const report = manager.getStats();
    try testing.expect(report.global_stats.total_allocations > 0);
}

test "integration: high load simulation" {
    const allocator = testing.allocator;
    
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
    
    const task_count = 100;
    try wg.add(task_count);
    
    var completed_tasks: i64 = 0;
    
    for (0..task_count) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        const coro = pool.acquire(coroutine_id, callback, &args) catch continue;
        
        coro.state = .running;
        
        const value = Value.initInt(@intCast(i));
        _ = channel.trySend(value);
        
        mutex.lock(coroutine_id);
        completed_tasks += 1;
        mutex.unlock(coroutine_id);
        
        coro.state = .completed;
        pool.release(coro);
        
        try wg.done();
    }
    
    try testing.expect(wg.isDone());
    try testing.expectEqual(@as(i64, task_count), completed_tasks);
    
    var received_count: usize = 0;
    while (channel.tryRecv()) |_| {
        received_count += 1;
    }
    
    try testing.expect(received_count > 0);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "edge case: empty channel operations" {
    const allocator = testing.allocator;
    
    const channel = try Channel.initWithCapacity(allocator, 5);
    defer channel.deinit();
    
    const result = channel.tryRecv();
    try testing.expect(result == null);
    
    channel.close();
    try testing.expect(channel.isClosed());
    
    const closed_result = channel.tryRecv();
    try testing.expect(closed_result != null);
}

test "edge case: mutex double unlock" {
    const allocator = testing.allocator;
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    mutex.lock(1);
    mutex.unlock(1);
    mutex.unlock(1);
    
    try testing.expect(!mutex.isLocked());
}

test "edge case: waitgroup zero add" {
    const allocator = testing.allocator;
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
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
    
    coro.setPriority(0);
    try testing.expectEqual(@as(u8, 0), coro.priority);
    
    coro.setPriority(4);
    try testing.expectEqual(@as(u8, 4), coro.priority);
    
    coro.setPriority(255);
    try testing.expectEqual(@as(u8, 4), coro.priority);
}

// ============================================================================
// Benchmarking and Profiling Tests - Requirement 10.6, 10.7
// ============================================================================

/// Memory profiling structure
const MemoryProfile = struct {
    initial_usage: usize,
    peak_usage: usize,
    final_usage: usize,
    allocations: u64,
    deallocations: u64,
    
    pub fn init() MemoryProfile {
        return MemoryProfile{
            .initial_usage = 0,
            .peak_usage = 0,
            .final_usage = 0,
            .allocations = 0,
            .deallocations = 0,
        };
    }
};

/// Latency measurement structure
const LatencyStats = struct {
    samples: []u64,
    count: usize,
    
    pub fn init(allocator: std.mem.Allocator, max_samples: usize) !LatencyStats {
        return LatencyStats{
            .samples = try allocator.alloc(u64, max_samples),
            .count = 0,
        };
    }
    
    pub fn deinit(self: *LatencyStats, allocator: std.mem.Allocator) void {
        allocator.free(self.samples);
    }
    
    pub fn record(self: *LatencyStats, latency_ns: u64) void {
        if (self.count < self.samples.len) {
            self.samples[self.count] = latency_ns;
            self.count += 1;
        }
    }
    
    pub fn getPercentile(self: *LatencyStats, percentile: f64) u64 {
        if (self.count == 0) return 0;
        
        // Sort samples for percentile calculation
        std.mem.sort(u64, self.samples[0..self.count], {}, std.sort.asc(u64));
        
        const index = @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.count - 1)) * percentile / 100.0));
        return self.samples[index];
    }
    
    pub fn getAverage(self: *LatencyStats) u64 {
        if (self.count == 0) return 0;
        
        var sum: u64 = 0;
        for (self.samples[0..self.count]) |sample| {
            sum += sample;
        }
        return sum / self.count;
    }
    
    pub fn getMin(self: *LatencyStats) u64 {
        if (self.count == 0) return 0;
        
        var min_val: u64 = std.math.maxInt(u64);
        for (self.samples[0..self.count]) |sample| {
            if (sample < min_val) min_val = sample;
        }
        return min_val;
    }
    
    pub fn getMax(self: *LatencyStats) u64 {
        if (self.count == 0) return 0;
        
        var max_val: u64 = 0;
        for (self.samples[0..self.count]) |sample| {
            if (sample > max_val) max_val = sample;
        }
        return max_val;
    }
};

test "benchmark: coroutine pool throughput" {
    const allocator = testing.allocator;
    const iterations = 10000;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 1000,
        .default_stack_size = 16 * 1024,
        .warmup_size = 100,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    const start = @as(u64, @intCast(std.time.nanoTimestamp()));
    
    for (0..iterations) |i| {
        const coro = try pool.acquire(@intCast(i + 1), callback, &args);
        pool.release(coro);
    }
    
    const end = @as(u64, @intCast(std.time.nanoTimestamp()));
    const total_time_ns = end - start;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) * 1_000_000_000.0 / @as(f64, @floatFromInt(total_time_ns));
    
    // Verify throughput is reasonable (at least 10,000 ops/sec)
    try testing.expect(ops_per_sec > 10000);
    
    // Verify pool reuse is working
    const stats = pool.getStats();
    try testing.expect(stats.total_reused > 0);
    try testing.expect(stats.reuse_ratio > 0.5); // At least 50% reuse
}

test "benchmark: channel throughput" {
    const allocator = testing.allocator;
    const iterations = 10000;
    
    const channel = try Channel.initWithCapacity(allocator, 1000);
    defer channel.deinit();
    
    const start = @as(u64, @intCast(std.time.nanoTimestamp()));
    
    // Send and receive in batches
    var sent: usize = 0;
    var received: usize = 0;
    
    for (0..iterations) |i| {
        const value = Value.initInt(@intCast(i));
        if (channel.trySend(value)) {
            sent += 1;
        }
        
        if (channel.tryRecv()) |_| {
            received += 1;
        }
    }
    
    // Drain remaining
    while (channel.tryRecv()) |_| {
        received += 1;
    }
    
    const end = @as(u64, @intCast(std.time.nanoTimestamp()));
    const total_time_ns = end - start;
    const ops_per_sec = @as(f64, @floatFromInt(sent + received)) * 1_000_000_000.0 / @as(f64, @floatFromInt(total_time_ns));
    
    // Verify throughput is reasonable
    try testing.expect(ops_per_sec > 100000);
    try testing.expectEqual(sent, received);
}

test "benchmark: mutex contention latency" {
    const allocator = testing.allocator;
    const iterations = 1000;
    
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var latency_stats = try LatencyStats.init(allocator, iterations);
    defer latency_stats.deinit(allocator);
    
    for (0..iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        const start = @as(u64, @intCast(std.time.nanoTimestamp()));
        mutex.lock(coroutine_id);
        mutex.unlock(coroutine_id);
        const end = @as(u64, @intCast(std.time.nanoTimestamp()));
        
        latency_stats.record(end - start);
    }
    
    const avg_latency = latency_stats.getAverage();
    const p99_latency = latency_stats.getPercentile(99);
    
    // Verify latency is reasonable (less than 1ms average)
    try testing.expect(avg_latency < 1_000_000);
    // P99 should be less than 10ms
    try testing.expect(p99_latency < 10_000_000);
}

test "benchmark: arena allocation speed" {
    const allocator = testing.allocator;
    const iterations = 10000;
    
    var arena = CacheAlignedArena.init(allocator);
    defer arena.deinit();
    
    const start = @as(u64, @intCast(std.time.nanoTimestamp()));
    
    for (0..iterations) |_| {
        _ = try arena.alloc(u8, 64);
        _ = try arena.alloc(u8, 128);
        _ = try arena.alloc(u8, 256);
    }
    
    const end = @as(u64, @intCast(std.time.nanoTimestamp()));
    const total_time_ns = end - start;
    const allocs_per_sec = @as(f64, @floatFromInt(iterations * 3)) * 1_000_000_000.0 / @as(f64, @floatFromInt(total_time_ns));
    
    // Verify allocation speed (at least 1M allocs/sec)
    try testing.expect(allocs_per_sec > 1_000_000);
    
    arena.reset();
}

test "profile: memory usage under load" {
    const allocator = testing.allocator;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 100,
        .default_stack_size = 16 * 1024,
        .warmup_size = 0,
        .enable_monitoring = true,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Allocate many coroutines
    var coroutines: [50]*OptimizedCoroutine = undefined;
    for (&coroutines, 0..) |*coro, i| {
        coro.* = try pool.acquire(@intCast(i + 1), callback, &args);
    }
    
    // Measure peak stats
    const peak_stats = pool.getStats();
    try testing.expectEqual(@as(usize, 50), peak_stats.active_count);
    
    // Release all coroutines
    for (coroutines) |coro| {
        pool.release(coro);
    }
    
    // Measure final stats
    const final_stats = pool.getStats();
    
    // Verify memory behavior - active count should be 0 after release
    try testing.expectEqual(@as(usize, 0), final_stats.active_count);
    // Pool should have coroutines available for reuse
    try testing.expect(final_stats.available_count > 0);
}

test "profile: scheduler status reporting" {
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
    
    // Get initial status
    const initial_status = scheduler.getStatus();
    try testing.expect(!initial_status.is_running);
    try testing.expectEqual(@as(u64, 0), initial_status.active_coroutines);
    try testing.expectEqual(@as(u64, 0), initial_status.total_spawned);
    
    // Spawn some coroutines
    const callback = Value.initNull();
    const args = [_]Value{};
    
    for (0..5) |_| {
        _ = try scheduler.spawn(callback, &args);
    }
    
    // Get updated status
    const updated_status = scheduler.getStatus();
    try testing.expectEqual(@as(u64, 5), updated_status.total_spawned);
    try testing.expectEqual(@as(u64, 5), updated_status.active_coroutines);
}

test "profile: lock-free pool efficiency" {
    const TestStruct = struct {
        value: u64,
        data: [56]u8,
    };
    
    var pool = LockFreePool(TestStruct).init(testing.allocator);
    defer pool.deinit();
    
    const iterations = 1000;
    
    // Measure acquire/release cycles
    const start = @as(u64, @intCast(std.time.nanoTimestamp()));
    
    for (0..iterations) |_| {
        const obj = try pool.acquire();
        obj.value = 42;
        pool.release(obj);
    }
    
    const end = @as(u64, @intCast(std.time.nanoTimestamp()));
    const total_time_ns = end - start;
    const ops_per_sec = @as(f64, @floatFromInt(iterations * 2)) * 1_000_000_000.0 / @as(f64, @floatFromInt(total_time_ns));
    
    // Verify efficiency
    try testing.expect(ops_per_sec > 100000);
    
    const stats = pool.getStats();
    try testing.expectEqual(@as(u64, 0), stats.active_count);
    try testing.expect(stats.total_acquired > 0);
}

// ============================================================================
// Integration Property Tests - All Requirements
// ============================================================================

test "property: coroutine pool maintains invariants" {
    const allocator = testing.allocator;
    const iterations = 100;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 50,
        .default_stack_size = 16 * 1024,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    for (0..iterations) |cycle| {
        // Acquire random number of coroutines
        const count = (cycle % 10) + 1;
        var acquired: [10]*OptimizedCoroutine = undefined;
        
        for (0..count) |i| {
            acquired[i] = try pool.acquire(@intCast(cycle * 10 + i + 1), callback, &args);
        }
        
        // Verify invariants
        const stats = pool.getStats();
        try testing.expectEqual(count, stats.active_count);
        
        // Release all
        for (0..count) |i| {
            pool.release(acquired[i]);
        }
        
        // Verify cleanup
        const final_stats = pool.getStats();
        try testing.expectEqual(@as(usize, 0), final_stats.active_count);
    }
}

test "property: channel preserves message order" {
    const allocator = testing.allocator;
    const message_count = 100;
    
    const channel = try Channel.initWithCapacity(allocator, message_count);
    defer channel.deinit();
    
    // Send messages in order
    for (0..message_count) |i| {
        const value = Value.initInt(@intCast(i));
        try testing.expect(channel.trySend(value));
    }
    
    // Receive and verify order
    for (0..message_count) |i| {
        const received = channel.tryRecv();
        try testing.expect(received != null);
        try testing.expectEqual(@as(i64, @intCast(i)), received.?.asInt());
    }
}

test "property: mutex ensures mutual exclusion" {
    const allocator = testing.allocator;
    const iterations = 100;
    
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var counter: i64 = 0;
    
    for (0..iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        mutex.lock(coroutine_id);
        
        // Critical section - verify exclusive access
        const before = counter;
        counter += 1;
        try testing.expectEqual(before + 1, counter);
        
        mutex.unlock(coroutine_id);
    }
    
    try testing.expectEqual(@as(i64, iterations), counter);
}

test "property: waitgroup synchronization correctness" {
    const allocator = testing.allocator;
    const task_count = 50;
    
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    // Add tasks
    try wg.add(task_count);
    try testing.expectEqual(@as(i32, task_count), wg.getCount());
    try testing.expect(!wg.isDone());
    
    // Complete tasks one by one
    for (0..task_count) |i| {
        try wg.done();
        const remaining = @as(i32, @intCast(task_count - i - 1));
        try testing.expectEqual(remaining, wg.getCount());
    }
    
    try testing.expect(wg.isDone());
}

// ============================================================================
// Integration Property Tests - Subtask 15.3
// Tests all properties together in complex scenarios
// Verifies system behavior under high load
// ============================================================================

test "integration property: full system stress test" {
    const allocator = testing.allocator;
    
    // Initialize all components
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 200,
        .default_stack_size = 16 * 1024,
        .warmup_size = 20,
    });
    defer pool.deinit();
    
    const channel = try Channel.initWithCapacity(allocator, 50);
    defer channel.deinit();
    
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var rwmutex = RWMutex.init(allocator);
    defer rwmutex.deinit();
    
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    var arena = CacheAlignedArena.init(allocator);
    defer arena.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Simulate high load scenario
    const task_count = 100;
    try wg.add(task_count);
    
    var shared_counter: i64 = 0;
    var messages_sent: usize = 0;
    var messages_received: usize = 0;
    
    for (0..task_count) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        // Acquire coroutine
        const coro = pool.acquire(coroutine_id, callback, &args) catch continue;
        coro.state = .running;
        
        // Allocate from arena
        _ = arena.alloc(u8, 64) catch {};
        
        // Use mutex for counter
        mutex.lock(coroutine_id);
        shared_counter += 1;
        mutex.unlock(coroutine_id);
        
        // Use rwmutex for reads
        rwmutex.readLock(coroutine_id);
        const read_val = shared_counter; // Read
        _ = read_val;
        rwmutex.readUnlock(coroutine_id);
        
        // Send to channel
        const value = Value.initInt(@intCast(i));
        if (channel.trySend(value)) {
            messages_sent += 1;
        }
        
        // Receive from channel
        if (channel.tryRecv()) |_| {
            messages_received += 1;
        }
        
        coro.state = .completed;
        pool.release(coro);
        try wg.done();
    }
    
    // Drain channel
    while (channel.tryRecv()) |_| {
        messages_received += 1;
    }
    
    // Verify all invariants
    try testing.expect(wg.isDone());
    try testing.expectEqual(@as(i64, task_count), shared_counter);
    try testing.expectEqual(messages_sent, messages_received);
    
    const pool_stats = pool.getStats();
    try testing.expectEqual(@as(usize, 0), pool_stats.active_count);
    try testing.expect(pool_stats.total_reused > 0);
    
    arena.reset();
}

test "integration property: concurrent data structure consistency" {
    const allocator = testing.allocator;
    
    // Test that all data structures maintain consistency under simulated concurrent access
    const iterations = 50;
    
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var rwmutex = RWMutex.init(allocator);
    defer rwmutex.deinit();
    
    const channel = try Channel.initWithCapacity(allocator, 100);
    defer channel.deinit();
    
    var counter: i64 = 0;
    var read_count: u64 = 0;
    
    for (0..iterations) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        // Writer operation
        if (i % 5 == 0) {
            rwmutex.writeLock(coroutine_id);
            counter += 1;
            rwmutex.writeUnlock(coroutine_id);
        } else {
            // Reader operation
            rwmutex.readLock(coroutine_id);
            const read_val = counter;
            _ = read_val;
            read_count += 1;
            rwmutex.readUnlock(coroutine_id);
        }
        
        // Channel operation
        const value = Value.initInt(@intCast(i));
        _ = channel.trySend(value);
    }
    
    // Verify consistency
    const expected_writes = iterations / 5;
    try testing.expectEqual(@as(i64, @intCast(expected_writes)), counter);
    try testing.expect(read_count > 0);
    
    // Drain and count channel messages
    var channel_count: usize = 0;
    while (channel.tryRecv()) |_| {
        channel_count += 1;
    }
    try testing.expect(channel_count > 0);
}

test "integration property: resource cleanup under failure" {
    const allocator = testing.allocator;
    
    // Test that resources are properly cleaned up even when operations fail
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 10,
        .default_stack_size = 16 * 1024,
        .warmup_size = 0,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Acquire all available coroutines
    var acquired: [10]*OptimizedCoroutine = undefined;
    var acquired_count: usize = 0;
    
    for (0..10) |i| {
        if (pool.acquire(@intCast(i + 1), callback, &args)) |coro| {
            acquired[acquired_count] = coro;
            acquired_count += 1;
        } else |_| {
            break;
        }
    }
    
    // Verify we acquired some coroutines
    try testing.expect(acquired_count > 0);
    
    // Simulate failure - release all coroutines
    for (0..acquired_count) |i| {
        pool.release(acquired[i]);
    }
    
    // Verify cleanup
    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 0), stats.active_count);
}

test "integration property: scheduler and pool coordination" {
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
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Spawn multiple coroutines
    const spawn_count = 10;
    for (0..spawn_count) |_| {
        _ = try scheduler.spawn(callback, &args);
    }
    
    // Verify scheduler state
    const status = scheduler.getStatus();
    try testing.expectEqual(@as(u64, spawn_count), status.total_spawned);
    try testing.expectEqual(@as(u64, spawn_count), status.active_coroutines);
    try testing.expectEqual(@as(u32, 2), status.num_processors);
    try testing.expectEqual(@as(u32, 2), status.num_workers);
}

test "integration property: memory pool efficiency under churn" {
    const allocator = testing.allocator;
    
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 50,
        .default_stack_size = 16 * 1024,
        .warmup_size = 10,
        .enable_performance_tracking = true,
    });
    defer pool.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Simulate high churn - rapid acquire/release cycles
    const cycles = 100;
    
    for (0..cycles) |cycle| {
        // Acquire batch
        const batch_size = (cycle % 5) + 1;
        var batch: [5]*OptimizedCoroutine = undefined;
        
        for (0..batch_size) |i| {
            batch[i] = try pool.acquire(@intCast(cycle * 5 + i + 1), callback, &args);
        }
        
        // Release batch
        for (0..batch_size) |i| {
            pool.release(batch[i]);
        }
    }
    
    // Verify efficiency
    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 0), stats.active_count);
    try testing.expect(stats.total_reused > 0);
    try testing.expect(stats.reuse_ratio > 0.3); // At least 30% reuse
}

test "integration property: channel backpressure handling" {
    const allocator = testing.allocator;
    
    // Small capacity to test backpressure
    const channel = try Channel.initWithCapacity(allocator, 5);
    defer channel.deinit();
    
    // Fill channel to capacity
    var sent: usize = 0;
    for (0..10) |i| {
        const value = Value.initInt(@intCast(i));
        if (channel.trySend(value)) {
            sent += 1;
        }
    }
    
    // Should have sent exactly capacity
    try testing.expectEqual(@as(usize, 5), sent);
    try testing.expect(channel.isFull());
    
    // Receive one to make room
    const received = channel.tryRecv();
    try testing.expect(received != null);
    try testing.expect(!channel.isFull());
    
    // Should be able to send one more
    const value = Value.initInt(100);
    try testing.expect(channel.trySend(value));
    try testing.expect(channel.isFull());
    
    // Drain and verify count
    var drain_count: usize = 0;
    while (channel.tryRecv()) |_| {
        drain_count += 1;
    }
    try testing.expectEqual(@as(usize, 5), drain_count);
}

test "integration property: synchronization primitive composition" {
    const allocator = testing.allocator;
    
    // Test using multiple sync primitives together
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    const channel = try Channel.initWithCapacity(allocator, 20);
    defer channel.deinit();
    
    const task_count = 20;
    try wg.add(task_count);
    
    var results: [20]i64 = undefined;
    var result_count: usize = 0;
    
    for (0..task_count) |i| {
        const coroutine_id: u64 = @intCast(i + 1);
        
        // Send to channel
        const value = Value.initInt(@intCast(i * 2));
        _ = channel.trySend(value);
        
        // Protected result storage
        mutex.lock(coroutine_id);
        if (result_count < results.len) {
            results[result_count] = @intCast(i);
            result_count += 1;
        }
        mutex.unlock(coroutine_id);
        
        try wg.done();
    }
    
    // Verify completion
    try testing.expect(wg.isDone());
    try testing.expectEqual(@as(usize, task_count), result_count);
    
    // Verify channel contents
    var channel_count: usize = 0;
    while (channel.tryRecv()) |_| {
        channel_count += 1;
    }
    try testing.expectEqual(@as(usize, task_count), channel_count);
}

test "integration property: performance manager under load" {
    var manager = PerformanceManager.init(testing.allocator);
    defer manager.deinit();
    
    const iterations = 50;
    
    // Simulate varied allocation patterns
    for (0..iterations) |i| {
        // Stack allocation
        const stack = try manager.acquireCoroutineStack(16 * 1024);
        
        // Value allocation
        const value = try manager.acquireValue();
        value.* = Value.initInt(@intCast(i));
        
        // Temp allocation
        const temp = try manager.allocTemp(u8, 128);
        _ = temp;
        
        // Release
        manager.releaseCoroutineStack(stack);
        manager.releaseValue(value);
    }
    
    // Reset temp allocations
    manager.resetTemp();
    
    // Verify stats
    const report = manager.getStats();
    try testing.expect(report.global_stats.total_allocations > 0);
}

test "integration property: end-to-end workflow simulation" {
    const allocator = testing.allocator;
    
    // Simulate a complete workflow: spawn tasks, communicate via channels, synchronize
    var pool = try OptimizedCoroutinePool.init(allocator, .{
        .max_pool_size = 100,
        .default_stack_size = 16 * 1024,
        .warmup_size = 10,
    });
    defer pool.deinit();
    
    const input_channel = try Channel.initWithCapacity(allocator, 20);
    defer input_channel.deinit();
    
    const output_channel = try Channel.initWithCapacity(allocator, 20);
    defer output_channel.deinit();
    
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    // Producer: send work items
    const work_items = 15;
    for (0..work_items) |i| {
        const value = Value.initInt(@intCast(i));
        _ = input_channel.trySend(value);
    }
    
    // Workers: process work items
    const worker_count = 5;
    try wg.add(worker_count);
    
    var processed: i64 = 0;
    
    for (0..worker_count) |w| {
        const coroutine_id: u64 = @intCast(w + 1);
        const coro = try pool.acquire(coroutine_id, callback, &args);
        coro.state = .running;
        
        // Process available work
        while (input_channel.tryRecv()) |input| {
            // Simulate processing
            const result = Value.initInt(input.asInt() * 2);
            _ = output_channel.trySend(result);
            
            mutex.lock(coroutine_id);
            processed += 1;
            mutex.unlock(coroutine_id);
        }
        
        coro.state = .completed;
        pool.release(coro);
        try wg.done();
    }
    
    // Verify completion
    try testing.expect(wg.isDone());
    try testing.expectEqual(@as(i64, work_items), processed);
    
    // Verify output
    var output_count: usize = 0;
    while (output_channel.tryRecv()) |_| {
        output_count += 1;
    }
    try testing.expectEqual(@as(usize, work_items), output_count);
    
    // Verify pool cleanup
    const pool_stats = pool.getStats();
    try testing.expectEqual(@as(usize, 0), pool_stats.active_count);
}
