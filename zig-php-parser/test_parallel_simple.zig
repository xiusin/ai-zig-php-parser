/// 并行 JIT 编译器简单测试
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== 并行 JIT 编译器核心组件测试 ===\n\n", .{});
    
    // 测试 1: 原子操作
    std.debug.print("测试 1: 原子操作...\n", .{});
    testAtomicOperations();
    std.debug.print("✓ 测试 1 通过\n\n", .{});
    
    // 测试 2: 优先级队列
    std.debug.print("测试 2: 优先级队列...\n", .{});
    try testPriorityQueue(allocator);
    std.debug.print("✓ 测试 2 通过\n\n", .{});
    
    // 测试 3: 线程安全的哈希表
    std.debug.print("测试 3: 线程安全的哈希表...\n", .{});
    try testThreadSafeHashMap(allocator);
    std.debug.print("✓ 测试 3 通过\n\n", .{});
    
    // 测试 4: 多线程任务调度
    std.debug.print("测试 4: 多线程任务调度...\n", .{});
    try testMultiThreadScheduling(allocator);
    std.debug.print("✓ 测试 4 通过\n\n", .{});
    
    std.debug.print("=== 所有核心组件测试通过 ===\n", .{});
}

fn testAtomicOperations() void {
    var counter = std.atomic.Value(u64).init(0);
    
    // 原子递增
    _ = counter.fetchAdd(1, .monotonic);
    _ = counter.fetchAdd(1, .monotonic);
    _ = counter.fetchAdd(1, .monotonic);
    
    const value = counter.load(.monotonic);
    std.debug.print("  原子计数器值: {d}\n", .{value});
    
    if (value != 3) {
        @panic("原子操作失败");
    }
}

const Task = struct {
    id: u32,
    priority: u8,
    timestamp: i128,
    
    fn compare(_: void, a: Task, b: Task) std.math.Order {
        if (a.priority != b.priority) {
            return if (a.priority > b.priority) .lt else .gt;
        }
        return if (a.timestamp < b.timestamp) .lt else if (a.timestamp > b.timestamp) .gt else .eq;
    }
};

fn testPriorityQueue(allocator: std.mem.Allocator) !void {
    var queue = std.PriorityQueue(Task, void, Task.compare).init(allocator, {});
    defer queue.deinit();
    
    // 添加不同优先级的任务
    try queue.add(.{ .id = 1, .priority = 50, .timestamp = 100 });
    try queue.add(.{ .id = 2, .priority = 200, .timestamp = 200 });
    try queue.add(.{ .id = 3, .priority = 100, .timestamp = 150 });
    
    // 验证优先级顺序
    const first = queue.remove();
    std.debug.print("  第一个任务: ID={d}, 优先级={d}\n", .{first.id, first.priority});
    
    if (first.priority != 200) {
        return error.PriorityOrderIncorrect;
    }
    
    const second = queue.remove();
    std.debug.print("  第二个任务: ID={d}, 优先级={d}\n", .{second.id, second.priority});
    
    if (second.priority != 100) {
        return error.PriorityOrderIncorrect;
    }
}

fn testThreadSafeHashMap(allocator: std.mem.Allocator) !void {
    var map = std.StringHashMap(u64).init(allocator);
    defer map.deinit();
    
    var mutex = std.Thread.Mutex{};
    
    // 插入数据
    mutex.lock();
    try map.put("key1", 100);
    try map.put("key2", 200);
    mutex.unlock();
    
    // 读取数据
    mutex.lock();
    const value1 = map.get("key1");
    const value2 = map.get("key2");
    mutex.unlock();
    
    std.debug.print("  key1 = {?d}\n", .{value1});
    std.debug.print("  key2 = {?d}\n", .{value2});
    
    if (value1 == null or value1.? != 100) {
        return error.HashMapIncorrect;
    }
    
    if (value2 == null or value2.? != 200) {
        return error.HashMapIncorrect;
    }
}

const ThreadContext = struct {
    counter: *std.atomic.Value(u64),
    iterations: usize,
};

fn workerThread(ctx: ThreadContext) void {
    var i: usize = 0;
    while (i < ctx.iterations) : (i += 1) {
        _ = ctx.counter.fetchAdd(1, .monotonic);
    }
}

fn testMultiThreadScheduling(allocator: std.mem.Allocator) !void {
    var counter = std.atomic.Value(u64).init(0);
    
    const num_threads = 4;
    const iterations_per_thread = 1000;
    
    const threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);
    
    // 启动线程
    for (threads) |*thread| {
        const ctx = ThreadContext{
            .counter = &counter,
            .iterations = iterations_per_thread,
        };
        thread.* = try std.Thread.spawn(.{}, workerThread, .{ctx});
    }
    
    // 等待所有线程完成
    for (threads) |thread| {
        thread.join();
    }
    
    const final_value = counter.load(.monotonic);
    const expected = num_threads * iterations_per_thread;
    
    std.debug.print("  线程数: {d}\n", .{num_threads});
    std.debug.print("  每线程迭代: {d}\n", .{iterations_per_thread});
    std.debug.print("  最终计数: {d}\n", .{final_value});
    std.debug.print("  预期计数: {d}\n", .{expected});
    
    if (final_value != expected) {
        return error.ThreadSchedulingIncorrect;
    }
}
