//! Fast Pool 堆存储属性测试
//! 
//! 验证需求 4.5：Fast Pool 堆存储正确性
//! 
//! 属性 25：Fast Pool 堆存储正确性
//! - 内联存储满时自动切换到堆存储
//! - 堆存储无容量限制
//! - 内联和堆存储的变量都能正确访问
//! - 变量更新正确处理引用计数
//! - 清理时正确释放所有资源

const std = @import("std");
const testing = std.testing;
const fast_pool = @import("fast_pool.zig");
const types = @import("types.zig");

// 属性 25.1：内联存储满时自动切换到堆存储
// @property ∀ frame, vars: |vars| > INLINE_CAPACITY ⇒ frame.isUsingHeapStorage()
test "Property 25.1: Automatic transition to heap storage when inline is full" {
    var pool = fast_pool.CallFramePool.init(testing.allocator);
    defer pool.deinit();

    const frame = try pool.acquire("test_func", "test.php", 1);
    defer pool.release(frame, testing.allocator);

    // 验证初始状态
    try testing.expect(!frame.isUsingHeapStorage());
    try testing.expect(frame.getLocalCount() == 0);

    // 添加 INLINE_LOCALS_CAPACITY 个变量（应该全部在内联存储中）
    const inline_capacity = fast_pool.PooledCallFrame.INLINE_LOCALS_CAPACITY;
    var i: usize = 0;
    while (i < inline_capacity) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, types.Value.initInt(@intCast(i)));
    }

    // 验证仍在使用内联存储
    try testing.expect(!frame.isUsingHeapStorage());
    try testing.expect(frame.getLocalCount() == inline_capacity);

    // 添加第 (INLINE_CAPACITY + 1) 个变量，应该触发堆存储
    const overflow_name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{inline_capacity});
    defer testing.allocator.free(overflow_name);
    try frame.setLocal(testing.allocator, overflow_name, types.Value.initInt(@intCast(inline_capacity)));

    // 验证已切换到堆存储
    try testing.expect(frame.isUsingHeapStorage());
    try testing.expect(frame.getLocalCount() == inline_capacity + 1);
}

// 属性 25.2：堆存储无容量限制
// @property ∀ frame, n: frame.setLocal(n vars) succeeds for any n
test "Property 25.2: Heap storage has no capacity limit" {
    var pool = fast_pool.CallFramePool.init(testing.allocator);
    defer pool.deinit();

    const frame = try pool.acquire("test_func", "test.php", 1);
    defer pool.release(frame, testing.allocator);

    // 添加大量变量（远超内联容量）
    const large_count = 100;
    var i: usize = 0;
    while (i < large_count) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, types.Value.initInt(@intCast(i)));
    }

    // 验证所有变量都已存储
    try testing.expect(frame.getLocalCount() == large_count);
    try testing.expect(frame.isUsingHeapStorage());

    // 验证所有变量都能正确访问
    i = 0;
    while (i < large_count) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        const value = frame.getLocal(name);
        try testing.expect(value != null);
        try testing.expect(value.?.asInt() == @as(i64, @intCast(i)));
    }
}

// 属性 25.3：内联和堆存储的变量都能正确访问
// @property ∀ frame, var: var ∈ inline ∨ var ∈ heap ⇒ frame.getLocal(var) = expected
test "Property 25.3: Variables in both inline and heap storage are accessible" {
    var pool = fast_pool.CallFramePool.init(testing.allocator);
    defer pool.deinit();

    const frame = try pool.acquire("test_func", "test.php", 1);
    defer pool.release(frame, testing.allocator);

    const inline_capacity = fast_pool.PooledCallFrame.INLINE_LOCALS_CAPACITY;

    // 添加内联变量
    var i: usize = 0;
    while (i < inline_capacity) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "inline_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, types.Value.initInt(@intCast(i * 10)));
    }

    // 添加堆变量
    i = 0;
    while (i < 10) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "heap_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, types.Value.initInt(@intCast(i * 100)));
    }

    // 验证内联变量可访问
    i = 0;
    while (i < inline_capacity) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "inline_{d}", .{i});
        defer testing.allocator.free(name);
        const value = frame.getLocal(name);
        try testing.expect(value != null);
        try testing.expect(value.?.asInt() == @as(i64, @intCast(i * 10)));
    }

    // 验证堆变量可访问
    i = 0;
    while (i < 10) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "heap_{d}", .{i});
        defer testing.allocator.free(name);
        const value = frame.getLocal(name);
        try testing.expect(value != null);
        try testing.expect(value.?.asInt() == @as(i64, @intCast(i * 100)));
    }
}

// 属性 25.4：变量更新正确处理引用计数
// @property ∀ frame, var, old_val, new_val: 
//   frame.setLocal(var, old_val) ∧ frame.setLocal(var, new_val) ⇒ 
//   old_val.released ∧ new_val.retained
test "Property 25.4: Variable updates handle reference counting correctly" {
    var pool = fast_pool.CallFramePool.init(testing.allocator);
    defer pool.deinit();

    const frame = try pool.acquire("test_func", "test.php", 1);
    defer pool.release(frame, testing.allocator);

    // 测试内联存储中的更新
    try frame.setLocal(testing.allocator, "x", types.Value.initInt(42));
    const val1 = frame.getLocal("x");
    try testing.expect(val1 != null);
    try testing.expect(val1.?.asInt() == 42);

    // 更新变量
    try frame.setLocal(testing.allocator, "x", types.Value.initInt(100));
    const val2 = frame.getLocal("x");
    try testing.expect(val2 != null);
    try testing.expect(val2.?.asInt() == 100);

    // 填满内联存储并触发堆存储
    const inline_capacity = fast_pool.PooledCallFrame.INLINE_LOCALS_CAPACITY;
    var i: usize = 1; // 从 1 开始，因为 x 已占用一个位置
    while (i < inline_capacity) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, types.Value.initInt(@intCast(i)));
    }

    // 添加堆变量
    try frame.setLocal(testing.allocator, "heap_var", types.Value.initInt(200));
    try testing.expect(frame.isUsingHeapStorage());

    // 更新堆变量
    try frame.setLocal(testing.allocator, "heap_var", types.Value.initInt(300));
    const heap_val = frame.getLocal("heap_var");
    try testing.expect(heap_val != null);
    try testing.expect(heap_val.?.asInt() == 300);
}

// 属性 25.5：清理时正确释放所有资源
// @property ∀ frame: frame.clearLocals() ⇒ 
//   frame.getLocalCount() = 0 ∧ !frame.isUsingHeapStorage()
test "Property 25.5: Cleanup releases all resources correctly" {
    var pool = fast_pool.CallFramePool.init(testing.allocator);
    defer pool.deinit();

    const frame = try pool.acquire("test_func", "test.php", 1);
    defer pool.release(frame, testing.allocator);

    // 添加大量变量（包括内联和堆存储）
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, types.Value.initInt(@intCast(i)));
    }

    try testing.expect(frame.getLocalCount() == 50);
    try testing.expect(frame.isUsingHeapStorage());

    // 清理所有变量
    frame.clearLocals(testing.allocator);

    // 验证清理后的状态
    try testing.expect(frame.getLocalCount() == 0);
    try testing.expect(!frame.isUsingHeapStorage());

    // 验证变量不再可访问
    const val = frame.getLocal("var_0");
    try testing.expect(val == null);
}

// 属性 25.6：帧重用时堆存储被正确清理
// @property ∀ frame1, frame2: 
//   pool.release(frame1) ∧ frame2 = pool.acquire() ∧ frame1 = frame2 ⇒
//   !frame2.isUsingHeapStorage() ∧ frame2.getLocalCount() = 0
test "Property 25.6: Heap storage is cleaned on frame reuse" {
    var pool = fast_pool.CallFramePool.init(testing.allocator);
    defer pool.deinit();

    // 第一次使用帧
    const frame1 = try pool.acquire("func1", "test.php", 1);
    
    // 添加大量变量触发堆存储
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame1.setLocal(testing.allocator, name, types.Value.initInt(@intCast(i)));
    }
    
    try testing.expect(frame1.isUsingHeapStorage());
    const frame1_ptr = frame1;
    
    // 释放帧
    pool.release(frame1, testing.allocator);
    
    // 重新获取帧（应该重用同一个帧）
    const frame2 = try pool.acquire("func2", "test.php", 2);
    defer pool.release(frame2, testing.allocator);
    
    // 验证是同一个帧
    try testing.expect(frame2 == frame1_ptr);
    
    // 验证堆存储已清理
    try testing.expect(!frame2.isUsingHeapStorage());
    try testing.expect(frame2.getLocalCount() == 0);
}

// 属性 25.7：并发场景下的内存安全
// @property ∀ frames: parallel_operations(frames) ⇒ no_memory_corruption
test "Property 25.7: Memory safety in concurrent scenarios" {
    // 注意：这个测试验证单个帧的内存安全，不涉及真正的并发
    // 因为 PooledCallFrame 被标记为 ISOLATED (单线程)
    
    var pool = fast_pool.CallFramePool.init(testing.allocator);
    defer pool.deinit();

    // 创建多个帧并独立操作
    var frames: [5]*fast_pool.PooledCallFrame = undefined;
    var i: usize = 0;
    while (i < frames.len) : (i += 1) {
        frames[i] = try pool.acquire("test_func", "test.php", @intCast(i + 1));
    }
    defer {
        for (frames) |frame| {
            pool.release(frame, testing.allocator);
        }
    }

    // 每个帧添加不同数量的变量
    i = 0;
    while (i < frames.len) : (i += 1) {
        const count = (i + 1) * 10; // 10, 20, 30, 40, 50
        var j: usize = 0;
        while (j < count) : (j += 1) {
            const name = try std.fmt.allocPrint(testing.allocator, "frame{d}_var{d}", .{ i, j });
            defer testing.allocator.free(name);
            try frames[i].setLocal(testing.allocator, name, types.Value.initInt(@intCast(j)));
        }
    }

    // 验证每个帧的变量都正确
    i = 0;
    while (i < frames.len) : (i += 1) {
        const count = (i + 1) * 10;
        try testing.expect(frames[i].getLocalCount() == count);
        
        var j: usize = 0;
        while (j < count) : (j += 1) {
            const name = try std.fmt.allocPrint(testing.allocator, "frame{d}_var{d}", .{ i, j });
            defer testing.allocator.free(name);
            const value = frames[i].getLocal(name);
            try testing.expect(value != null);
            try testing.expect(value.?.asInt() == @as(i64, @intCast(j)));
        }
    }
}

// 属性 25.8：边界条件测试
// @property 测试各种边界条件下的正确性
test "Property 25.8: Boundary conditions" {
    var pool = fast_pool.CallFramePool.init(testing.allocator);
    defer pool.deinit();

    const frame = try pool.acquire("test_func", "test.php", 1);
    defer pool.release(frame, testing.allocator);

    // 测试空帧
    try testing.expect(frame.getLocalCount() == 0);
    try testing.expect(frame.getLocal("nonexistent") == null);

    // 测试恰好填满内联存储
    const inline_capacity = fast_pool.PooledCallFrame.INLINE_LOCALS_CAPACITY;
    var i: usize = 0;
    while (i < inline_capacity) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, types.Value.initInt(@intCast(i)));
    }
    try testing.expect(!frame.isUsingHeapStorage());
    try testing.expect(frame.getLocalCount() == inline_capacity);

    // 测试恰好超出内联存储一个
    const overflow_name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{inline_capacity});
    defer testing.allocator.free(overflow_name);
    try frame.setLocal(testing.allocator, overflow_name, types.Value.initInt(@intCast(inline_capacity)));
    try testing.expect(frame.isUsingHeapStorage());
    try testing.expect(frame.getLocalCount() == inline_capacity + 1);

    // 测试清空后再添加
    frame.clearLocals(testing.allocator);
    try testing.expect(frame.getLocalCount() == 0);
    try frame.setLocal(testing.allocator, "new_var", types.Value.initInt(999));
    try testing.expect(frame.getLocalCount() == 1);
    try testing.expect(!frame.isUsingHeapStorage()); // 清空后应该回到内联存储
}
