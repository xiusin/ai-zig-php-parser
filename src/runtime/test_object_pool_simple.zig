// 对象池化简化属性测试
// Feature: zig-php-performance-optimization
// Property 24: 对象池化性能提升
// 验证：需求 4.4

const std = @import("std");
const testing = std.testing;
const object_pool = @import("object_pool.zig");
const ObjectPool = object_pool.ObjectPool;

/// 测试对象类型
const TestObject = struct {
    id: usize,
    data: [128]u8,

    fn init(id: usize) TestObject {
        var obj = TestObject{
            .id = id,
            .data = undefined,
        };

        // 填充数据
        for (&obj.data, 0..) |*byte, i| {
            byte.* = @truncate(id +% i);
        }

        return obj;
    }
};

// 属性 24.1：池化分配比直接分配快至少 50%
test "Property 24.1: Pool allocation is at least 50% faster" {
    std.debug.print("\n=== Property 24.1: Pool allocation performance ===\n", .{});

    const iterations: usize = 10000;

    // 测试直接分配
    var timer = try std.time.Timer.start();
    {
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            const obj = try testing.allocator.create(TestObject);
            obj.* = TestObject.init(i);
            testing.allocator.destroy(obj);
        }
    }
    const direct_time = timer.read();

    // 测试池化分配
    timer.reset();
    {
        var pool = try ObjectPool(TestObject).init(testing.allocator, .{
            .initial_capacity = 64,
            .max_capacity = 256,
        });
        defer pool.deinit();

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            const handle = try pool.acquire();
            handle.get().* = TestObject.init(i);
            handle.release();
        }
    }
    const pool_time = timer.read();

    const speedup = @as(f64, @floatFromInt(direct_time)) / @as(f64, @floatFromInt(pool_time));
    const reduction = (1.0 - (@as(f64, @floatFromInt(pool_time)) / @as(f64, @floatFromInt(direct_time)))) * 100.0;

    std.debug.print("Direct allocation: {d} ns\n", .{direct_time});
    std.debug.print("Pool allocation: {d} ns\n", .{pool_time});
    std.debug.print("Speedup: {d:.2}x\n", .{speedup});
    std.debug.print("Allocation overhead reduction: {d:.1}%\n", .{reduction});

    // 验证：池化分配应该减少至少 50% 的开销
    try testing.expect(reduction >= 50.0);

    std.debug.print("✓ Property 24.1 passed\n", .{});
}

// 综合性能测试
test "Property 24: Comprehensive performance validation" {
    std.debug.print("\n=== Property 24: Comprehensive Performance Test ===\n", .{});

    const iterations: usize = 50000;
    const pool_size: usize = 128;

    // 创建池
    var pool = try ObjectPool(TestObject).init(testing.allocator, .{
        .initial_capacity = pool_size,
        .max_capacity = pool_size * 2,
    });
    defer pool.deinit();

    const Handle = ObjectPool(TestObject).Handle;

    // 预热池
    var warmup_handles: [pool_size]Handle = undefined;
    for (&warmup_handles, 0..) |*handle, i| {
        handle.* = try pool.acquire();
        handle.get().* = TestObject.init(i);
    }
    for (warmup_handles) |handle| {
        handle.release();
    }

    // 重置统计
    pool.resetStats();

    // 执行性能测试
    var timer = try std.time.Timer.start();
    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    var active_handles = try std.ArrayList(Handle).initCapacity(testing.allocator, pool_size);
    defer active_handles.deinit(testing.allocator);

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        if (active_handles.items.len < pool_size / 2 and rng.boolean()) {
            const handle = try pool.acquire();
            handle.get().* = TestObject.init(i);
            try active_handles.append(testing.allocator, handle);
        } else if (active_handles.items.len > 0) {
            const idx = rng.intRangeLessThan(usize, 0, active_handles.items.len);
            const handle = active_handles.orderedRemove(idx);
            handle.release();
        }
    }

    const elapsed = timer.read();

    // 清理
    for (active_handles.items) |handle| {
        handle.release();
    }

    const stats = pool.getStats();
    const hit_rate = stats.hitRate();
    const avg_time_per_op = elapsed / iterations;

    std.debug.print("\n=== Performance Results ===\n", .{});
    std.debug.print("Total operations: {d}\n", .{iterations});
    std.debug.print("Total time: {d} ns\n", .{elapsed});
    std.debug.print("Average time per operation: {d} ns\n", .{avg_time_per_op});
    std.debug.print("Pool hit rate: {d:.2}%\n", .{hit_rate * 100.0});
    std.debug.print("Peak usage: {d}/{d}\n", .{ stats.peak_usage, stats.current_capacity });
    std.debug.print("Resize count: {d}\n", .{stats.resize_count});

    // 验证性能目标
    try testing.expect(hit_rate > 0.95); // 命中率 > 95%
    try testing.expect(avg_time_per_op < 1000); // 平均操作时间 < 1μs

    std.debug.print("\n✓ All performance targets met\n", .{});
}
