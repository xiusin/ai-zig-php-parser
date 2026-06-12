// ============================================================================
// 并发安全属性测试
// ============================================================================
//
// 本文件实现并发安全机制的属性测试，验证：
// - 属性 32：无数据竞争
// - 验证需求 7.5, 7.6, 7.8, 8.7
//
// Feature: zig-php-performance-optimization
// ============================================================================

const std = @import("std");
const concurrency = @import("concurrency.zig");
const testing = std.testing;

// ============================================================================
// 属性测试框架
// ============================================================================

const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: std.Random,
    iterations: u32,
    
    fn init(allocator: std.mem.Allocator, seed: u64, iterations: u32) PropertyTest {
        var prng = std.Random.DefaultPrng.init(seed);
        return .{
            .allocator = allocator,
            .rng = prng.random(),
            .iterations = iterations,
        };
    }
    
    fn run(
        self: *PropertyTest,
        comptime T: type,
        property: fn(*PropertyTest, T) anyerror!bool,
        generator: fn(*PropertyTest) anyerror!T,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const input = try generator(self);
            
            if (try property(self, input)) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed at iteration {d}\n", .{i});
            }
        }
        
        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("Property test: {d}/{d} passed ({d:.2}%)\n", 
            .{passed, self.iterations, success_rate * 100.0});
        
        return failed == 0;
    }
};

// ============================================================================
// 属性 32：无数据竞争
// ============================================================================
// 验证需求 7.5, 7.6, 7.8, 8.7
//
// 对于任意共享数据，所有访问应该被适当的同步机制保护
// ============================================================================

/// 测试输入：并发操作序列
const ConcurrentOperations = struct {
    thread_count: u32,
    operations_per_thread: u32,
    operation_type: OperationType,
    
    const OperationType = enum {
        channel_send_recv,
        cache_read_write,
        counter_increment,
        rwlock_operations,
        lockfree_stack,
    };
};

/// 生成随机并发操作
fn generateConcurrentOps(pt: *PropertyTest) !ConcurrentOperations {
    return .{
        .thread_count = pt.rng.intRangeAtMost(u32, 2, 8),
        .operations_per_thread = pt.rng.intRangeAtMost(u32, 100, 1000),
        .operation_type = @enumFromInt(pt.rng.intRangeAtMost(u8, 0, 4)),
    };
}

/// 属性 32：无数据竞争
fn property32_no_data_races(pt: *PropertyTest, input: ConcurrentOperations) !bool {
    return switch (input.operation_type) {
        .channel_send_recv => try testChannelNoRaces(pt, input),
        .cache_read_write => try testCacheNoRaces(pt, input),
        .counter_increment => try testCounterNoRaces(pt, input),
        .rwlock_operations => try testRWLockNoRaces(pt, input),
        .lockfree_stack => try testLockFreeStackNoRaces(pt, input),
    };
}

/// 测试 Channel 无数据竞争
fn testChannelNoRaces(pt: *PropertyTest, input: ConcurrentOperations) !bool {
    var channel = try concurrency.Channel(i32).init(pt.allocator, 100);
    defer channel.deinit();
    
    // 创建发送者线程
    const senders = try pt.allocator.alloc(std.Thread, input.thread_count);
    defer pt.allocator.free(senders);
    
    // 创建接收者线程
    const receivers = try pt.allocator.alloc(std.Thread, input.thread_count);
    defer pt.allocator.free(receivers);
    
    const SenderContext = struct {
        channel: *concurrency.Channel(i32),
        count: u32,
        start_value: i32,
    };
    
    const ReceiverContext = struct {
        channel: *concurrency.Channel(i32),
        count: u32,
        received: *std.ArrayList(i32),
        mutex: *std.Thread.Mutex,
        allocator: std.mem.Allocator,
    };
    
    // 启动发送者
    for (senders, 0..) |*sender, i| {
        const ctx = try pt.allocator.create(SenderContext);
        ctx.* = .{
            .channel = channel,
            .count = input.operations_per_thread,
            .start_value = @as(i32, @intCast(i * 10000)),
        };
        
        sender.* = try std.Thread.spawn(.{}, struct {
            fn run(context: *SenderContext) void {
                var j: u32 = 0;
                while (j < context.count) : (j += 1) {
                    context.channel.send(context.start_value + @as(i32, @intCast(j))) catch {};
                }
            }
        }.run, .{ctx});
    }
    
    // 准备接收数据
    var received: std.ArrayList(i32) = .{};
    defer received.deinit(pt.allocator);
    var recv_mutex = std.Thread.Mutex{};
    
    // 启动接收者
    for (receivers) |*receiver| {
        const ctx = try pt.allocator.create(ReceiverContext);
        ctx.* = .{
            .channel = channel,
            .count = input.operations_per_thread,
            .received = &received,
            .mutex = &recv_mutex,
            .allocator = pt.allocator,
        };
        
        receiver.* = try std.Thread.spawn(.{}, struct {
            fn run(context: *ReceiverContext) void {
                var j: u32 = 0;
                while (j < context.count) : (j += 1) {
                    if (context.channel.recv()) |value| {
                        context.mutex.lock();
                        defer context.mutex.unlock();
                        context.received.append(context.allocator, value) catch {};
                    } else |_| {
                        break;
                    }
                }
            }
        }.run, .{ctx});
    }
    
    // 等待所有发送者完成
    for (senders) |sender| {
        sender.join();
    }
    
    // 关闭 channel
    channel.close();
    
    // 等待所有接收者完成
    for (receivers) |receiver| {
        receiver.join();
    }
    
    // 验证：发送和接收的数量应该匹配
    const expected_count = input.thread_count * input.operations_per_thread;
    const actual_count = received.items.len;
    
    if (actual_count != expected_count) {
        std.debug.print("Channel race detected: expected {d} items, got {d}\n", 
            .{expected_count, actual_count});
        return false;
    }
    
    // 验证：没有重复的值
    var seen = std.AutoHashMap(i32, void).init(pt.allocator);
    defer seen.deinit();
    
    for (received.items) |value| {
        if (seen.contains(value)) {
            std.debug.print("Duplicate value detected: {d}\n", .{value});
            return false;
        }
        try seen.put(value, {});
    }
    
    return true;
}

/// 测试 Cache 无数据竞争
fn testCacheNoRaces(pt: *PropertyTest, input: ConcurrentOperations) !bool {
    var cache = concurrency.ThreadSafeCache(u32, i32).init(pt.allocator);
    defer cache.deinit();
    
    // 预填充一些数据
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try cache.put(i, @as(i32, @intCast(i * 10)));
    }
    
    const threads = try pt.allocator.alloc(std.Thread, input.thread_count);
    defer pt.allocator.free(threads);
    
    const Context = struct {
        cache: *concurrency.ThreadSafeCache(u32, i32),
        operations: u32,
        rng: std.Random,
    };
    
    // 启动线程执行混合读写操作
    for (threads) |*thread| {
        var prng = std.Random.DefaultPrng.init(pt.rng.int(u64));
        const ctx = try pt.allocator.create(Context);
        ctx.* = .{
            .cache = &cache,
            .operations = input.operations_per_thread,
            .rng = prng.random(),
        };
        
        thread.* = try std.Thread.spawn(.{}, struct {
            fn run(context: *Context) void {
                var j: u32 = 0;
                while (j < context.operations) : (j += 1) {
                    const key = context.rng.intRangeAtMost(u32, 0, 99);
                    
                    if (context.rng.boolean()) {
                        // 读操作
                        _ = context.cache.get(key);
                    } else {
                        // 写操作
                        const value = context.rng.int(i32);
                        context.cache.put(key, value) catch {};
                    }
                }
            }
        }.run, .{ctx});
    }
    
    // 等待所有线程完成
    for (threads) |thread| {
        thread.join();
    }
    
    // 验证：访问计数应该等于总操作数
    const expected_reads = input.thread_count * input.operations_per_thread;
    const actual_reads = cache.getAccessCount();
    
    // 由于有写操作，实际读取次数可能少于总操作数
    // 但访问计数应该在合理范围内
    if (actual_reads > expected_reads) {
        std.debug.print("Cache race detected: access count {d} exceeds expected {d}\n", 
            .{actual_reads, expected_reads});
        return false;
    }
    
    return true;
}

/// 测试 Counter 无数据竞争
fn testCounterNoRaces(pt: *PropertyTest, input: ConcurrentOperations) !bool {
    var counter = concurrency.AtomicCounter.init(0);
    
    const threads = try pt.allocator.alloc(std.Thread, input.thread_count);
    defer pt.allocator.free(threads);
    
    const Context = struct {
        counter: *concurrency.AtomicCounter,
        operations: u32,
    };
    
    // 启动线程执行增量操作
    for (threads) |*thread| {
        const ctx = try pt.allocator.create(Context);
        ctx.* = .{
            .counter = &counter,
            .operations = input.operations_per_thread,
        };
        
        thread.* = try std.Thread.spawn(.{}, struct {
            fn run(context: *Context) void {
                var j: u32 = 0;
                while (j < context.operations) : (j += 1) {
                    _ = context.counter.increment();
                }
            }
        }.run, .{ctx});
    }
    
    // 等待所有线程完成
    for (threads) |thread| {
        thread.join();
    }
    
    // 验证：最终计数应该等于总操作数
    const expected = @as(i64, @intCast(input.thread_count * input.operations_per_thread));
    const actual = counter.get();
    
    if (actual != expected) {
        std.debug.print("Counter race detected: expected {d}, got {d}\n", .{expected, actual});
        return false;
    }
    
    return true;
}

/// 测试 RWLock 无数据竞争
fn testRWLockNoRaces(pt: *PropertyTest, input: ConcurrentOperations) !bool {
    var lock = concurrency.RWLock.init();
    var shared_data: i32 = 0;
    
    const threads = try pt.allocator.alloc(std.Thread, input.thread_count);
    defer pt.allocator.free(threads);
    
    const Context = struct {
        lock: *concurrency.RWLock,
        data: *i32,
        operations: u32,
        is_writer: bool,
    };
    
    // 启动读者和写者线程
    for (threads, 0..) |*thread, i| {
        const ctx = try pt.allocator.create(Context);
        ctx.* = .{
            .lock = &lock,
            .data = &shared_data,
            .operations = input.operations_per_thread,
            .is_writer = (i % 4 == 0), // 25% 写者，75% 读者
        };
        
        thread.* = try std.Thread.spawn(.{}, struct {
            fn run(context: *Context) void {
                var j: u32 = 0;
                while (j < context.operations) : (j += 1) {
                    if (context.is_writer) {
                        // 写操作
                        context.lock.lockWrite();
                        defer context.lock.unlockWrite();
                        context.data.* += 1;
                    } else {
                        // 读操作
                        context.lock.lockRead();
                        defer context.lock.unlockRead();
                        _ = context.data.*;
                    }
                }
            }
        }.run, .{ctx});
    }
    
    // 等待所有线程完成
    for (threads) |thread| {
        thread.join();
    }
    
    // 验证：写操作的次数应该正确
    const writer_count = (input.thread_count + 3) / 4; // 向上取整
    const expected = @as(i32, @intCast(writer_count * input.operations_per_thread));
    
    if (shared_data != expected) {
        std.debug.print("RWLock race detected: expected {d}, got {d}\n", .{expected, shared_data});
        return false;
    }
    
    return true;
}

/// 测试 LockFreeStack 无数据竞争
fn testLockFreeStackNoRaces(pt: *PropertyTest, input: ConcurrentOperations) !bool {
    var stack = concurrency.LockFreeStack(i32).init(pt.allocator);
    defer stack.deinit();
    
    const threads = try pt.allocator.alloc(std.Thread, input.thread_count);
    defer pt.allocator.free(threads);
    
    const Context = struct {
        stack: *concurrency.LockFreeStack(i32),
        operations: u32,
        start_value: i32,
    };
    
    // 启动线程执行 push 操作
    for (threads, 0..) |*thread, i| {
        const ctx = try pt.allocator.create(Context);
        ctx.* = .{
            .stack = &stack,
            .operations = input.operations_per_thread,
            .start_value = @as(i32, @intCast(i * 10000)),
        };
        
        thread.* = try std.Thread.spawn(.{}, struct {
            fn run(context: *Context) void {
                var j: u32 = 0;
                while (j < context.operations) : (j += 1) {
                    context.stack.push(context.start_value + @as(i32, @intCast(j))) catch {};
                }
            }
        }.run, .{ctx});
    }
    
    // 等待所有线程完成
    for (threads) |thread| {
        thread.join();
    }
    
    // 验证：pop 出的元素数量应该等于 push 的数量
    var popped_count: u32 = 0;
    var seen = std.AutoHashMap(i32, void).init(pt.allocator);
    defer seen.deinit();
    
    while (stack.pop()) |value| {
        popped_count += 1;
        
        // 检查是否有重复
        if (seen.contains(value)) {
            std.debug.print("Duplicate value in lock-free stack: {d}\n", .{value});
            return false;
        }
        try seen.put(value, {});
    }
    
    const expected_count = input.thread_count * input.operations_per_thread;
    if (popped_count != expected_count) {
        std.debug.print("LockFreeStack race detected: expected {d} items, got {d}\n", 
            .{expected_count, popped_count});
        return false;
    }
    
    return true;
}

// ============================================================================
// 主测试
// ============================================================================

test "Property 32: No data races - Channel" {
    std.debug.print("\n=== Property 32: No data races (Channel) ===\n", .{});
    std.debug.print("Feature: zig-php-performance-optimization\n", .{});
    std.debug.print("Validates: Requirements 7.5, 7.6, 7.8, 8.7\n\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 12345, 20); // 减少迭代次数以加快测试
    
    const passed = try pt.run(
        ConcurrentOperations,
        property32_no_data_races,
        struct {
            fn gen(_: *PropertyTest) !ConcurrentOperations {
                return .{
                    .thread_count = 4,
                    .operations_per_thread = 100,
                    .operation_type = .channel_send_recv,
                };
            }
        }.gen,
    );
    
    try testing.expect(passed);
}

test "Property 32: No data races - Cache" {
    std.debug.print("\n=== Property 32: No data races (Cache) ===\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 12346, 20);
    
    const passed = try pt.run(
        ConcurrentOperations,
        property32_no_data_races,
        struct {
            fn gen(_: *PropertyTest) !ConcurrentOperations {
                return .{
                    .thread_count = 4,
                    .operations_per_thread = 100,
                    .operation_type = .cache_read_write,
                };
            }
        }.gen,
    );
    
    try testing.expect(passed);
}

test "Property 32: No data races - Counter" {
    std.debug.print("\n=== Property 32: No data races (Counter) ===\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 12347, 20);
    
    const passed = try pt.run(
        ConcurrentOperations,
        property32_no_data_races,
        struct {
            fn gen(_: *PropertyTest) !ConcurrentOperations {
                return .{
                    .thread_count = 4,
                    .operations_per_thread = 1000,
                    .operation_type = .counter_increment,
                };
            }
        }.gen,
    );
    
    try testing.expect(passed);
}

test "Property 32: No data races - RWLock" {
    std.debug.print("\n=== Property 32: No data races (RWLock) ===\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 12348, 20);
    
    const passed = try pt.run(
        ConcurrentOperations,
        property32_no_data_races,
        struct {
            fn gen(_: *PropertyTest) !ConcurrentOperations {
                return .{
                    .thread_count = 4,
                    .operations_per_thread = 100,
                    .operation_type = .rwlock_operations,
                };
            }
        }.gen,
    );
    
    try testing.expect(passed);
}

test "Property 32: No data races - LockFreeStack" {
    std.debug.print("\n=== Property 32: No data races (LockFreeStack) ===\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 12349, 20);
    
    const passed = try pt.run(
        ConcurrentOperations,
        property32_no_data_races,
        struct {
            fn gen(_: *PropertyTest) !ConcurrentOperations {
                return .{
                    .thread_count = 4,
                    .operations_per_thread = 100,
                    .operation_type = .lockfree_stack,
                };
            }
        }.gen,
    );
    
    try testing.expect(passed);
}

// ============================================================================
// 额外的并发安全测试
// ============================================================================

test "Channel: concurrent send and receive stress test" {
    const allocator = testing.allocator;
    
    var channel = try concurrency.Channel(i32).init(allocator, 10);
    defer channel.deinit();
    
    const thread_count = 4;
    const ops_per_thread = 1000;
    
    const senders = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(senders);
    
    const receivers = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(receivers);
    
    // 启动发送者
    for (senders, 0..) |*sender, i| {
        sender.* = try std.Thread.spawn(.{}, struct {
            fn run(ch: *concurrency.Channel(i32), start: i32) void {
                var j: u32 = 0;
                while (j < ops_per_thread) : (j += 1) {
                    ch.send(start + @as(i32, @intCast(j))) catch {};
                }
            }
        }.run, .{channel, @as(i32, @intCast(i * 10000))});
    }
    
    var received_count = std.atomic.Value(u32).init(0);
    
    // 启动接收者
    for (receivers) |*receiver| {
        receiver.* = try std.Thread.spawn(.{}, struct {
            fn run(ch: *concurrency.Channel(i32), counter: *std.atomic.Value(u32)) void {
                var j: u32 = 0;
                while (j < ops_per_thread) : (j += 1) {
                    if (ch.recv()) |_| {
                        _ = counter.fetchAdd(1, .monotonic);
                    } else |_| {
                        break;
                    }
                }
            }
        }.run, .{channel, &received_count});
    }
    
    // 等待发送者
    for (senders) |sender| {
        sender.join();
    }
    
    channel.close();
    
    // 等待接收者
    for (receivers) |receiver| {
        receiver.join();
    }
    
    const expected = thread_count * ops_per_thread;
    const actual = received_count.load(.monotonic);
    
    try testing.expectEqual(expected, actual);
}

test "AsyncFrameMetadata: depth limit enforcement" {
    var frames: [10]*concurrency.AsyncFrameMetadata = undefined;
    
    // 创建嵌套帧
    var parent: ?*concurrency.AsyncFrameMetadata = null;
    for (&frames, 0..) |*frame_ptr, i| {
        const frame = try testing.allocator.create(concurrency.AsyncFrameMetadata);
        frame.* = try concurrency.AsyncFrameMetadata.init(parent);
        frame_ptr.* = frame;
        parent = frame;
        
        try testing.expectEqual(@as(u32, @intCast(i)), frame.depth);
    }
    
    // 清理
    for (frames) |frame| {
        testing.allocator.destroy(frame);
    }
}
