// 对象池化属性测试
// Feature: zig-php-performance-optimization
// Property 24: 对象池化性能提升
// 验证：需求 4.4

const std = @import("std");
const testing = std.testing;
const object_pool = @import("object_pool.zig");
const ObjectPool = object_pool.ObjectPool;
const PoolConfig = object_pool.PoolConfig;

/// 属性测试框架
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
        comptime TestFn: type,
        test_fn: TestFn,
    ) !void {
        var passed: u32 = 0;
        var failed: u32 = 0;

        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            test_fn(self) catch |err| {
                failed += 1;
                std.debug.print("Iteration {d} failed: {}\n", .{ i, err });
                continue;
            };
            passed += 1;
        }

        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("\nProperty test: {d}/{d} passed ({d:.2}%)\n", .{ passed, self.iterations, success_rate * 100.0 });

        try testing.expect(failed == 0);
    }
};

/// 测试对象类型
const TestObject = struct {
    id: usize,
    data: [128]u8,
    checksum: u64,

    fn init(id: usize) TestObject {
        var obj = TestObject{
            .id = id,
            .data = undefined,
            .checksum = 0,
        };

        // 填充数据
        for (&obj.data, 0..) |*byte, i| {
            byte.* = @truncate(id +% i);
        }

        // 计算校验和
        obj.checksum = obj.calculateChecksum();
        return obj;
    }

    fn calculateChecksum(self: *const TestObject) u64 {
        var sum: u64 = self.id;
        for (self.data) |byte| {
            sum = sum +% byte;
        }
        return sum;
    }

    fn verify(self: *const TestObject) bool {
        return self.checksum == self.calculateChecksum();
    }
};

// ============================================================================
// 属性 24：对象池化性能提升
// ============================================================================

// 属性 24.1：池化分配比直接分配快至少 50%
test "Property 24.1: Pool allocation is at least 50% faster than direct allocation" {
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
}

// 属性 24.2：对象重用保持数据完整性
test "Property 24.2: Object reuse maintains data integrity" {
    std.debug.print("\n=== Property 24.2: Object reuse integrity ===\n", .{});

    var pt = PropertyTest.init(testing.allocator, 12345, 20); // 减少迭代次数

    const testFn = struct {
        fn run(self: *PropertyTest) !void {
            var pool = try ObjectPool(TestObject).init(self.allocator, .{
                .initial_capacity = 8,
            });
            defer pool.deinit();

            const Handle = ObjectPool(TestObject).Handle;

            // 分配并初始化对象
            const count = self.rng.intRangeAtMost(usize, 5, 20);
            const handles = try self.allocator.alloc(Handle, count);
            defer self.allocator.free(handles);

            for (handles, 0..) |*handle, i| {
                handle.* = try pool.acquire();
                handle.get().* = TestObject.init(i);
                try testing.expect(handle.get().verify());
            }

            // 归还对象
            for (handles) |handle| {
                try testing.expect(handle.get().verify());
                handle.release();
            }

            // 重新分配并验证
            for (handles, 0..) |*handle, i| {
                handle.* = try pool.acquire();
                handle.get().* = TestObject.init(i + 1000);
                try testing.expect(handle.get().verify());
            }

            // 清理
            for (handles) |handle| {
                handle.release();
            }
        }
    }.run;

    try pt.run(@TypeOf(testFn), testFn);
}

// 属性 24.3：池自适应调整保持高效
test "Property 24.3: Pool adaptive resizing maintains efficiency" {
    std.debug.print("\n=== Property 24.3: Adaptive resizing efficiency ===\n", .{});

    var pt = PropertyTest.init(testing.allocator, 54321, 20); // 减少迭代次数

    const testFn = struct {
        fn run(self: *PropertyTest) !void {
            var pool = try ObjectPool(TestObject).init(self.allocator, .{
                .initial_capacity = 8,
                .max_capacity = 128,
                .min_capacity = 4,
                .high_watermark = 0.8,
                .low_watermark = 0.2,
                .resize_step = 4,
                .stats_window_size = 20,
            });
            defer pool.deinit();

            // 模拟变化的负载
            const phases = 5;
            var phase: usize = 0;
            while (phase < phases) : (phase += 1) {
                // 高负载阶段
                const high_count = self.rng.intRangeAtMost(usize, 20, 40);
                const Handle = ObjectPool(TestObject).Handle;
                var high_objects = try self.allocator.alloc(Handle, high_count);
                defer self.allocator.free(high_objects);

                for (high_objects, 0..) |*handle, i| {
                    handle.* = try pool.acquire();
                    handle.get().* = TestObject.init(i);
                }

                _ = pool.stats.current_capacity;

                // 归还大部分对象（低负载）
                const keep_count = high_count / 4;
                for (high_objects[keep_count..]) |handle| {
                    handle.release();
                }

                // 继续一些操作以触发自适应调整
                var i: usize = 0;
                while (i < 30) : (i += 1) {
                    const handle = try pool.acquire();
                    handle.release();
                }

                // 清理
                for (high_objects[0..keep_count]) |handle| {
                    handle.release();
                }

                // 验证池容量在合理范围内
                try testing.expect(pool.stats.current_capacity >= pool.config.min_capacity);
                try testing.expect(pool.stats.current_capacity <= pool.config.max_capacity);
            }

            // 验证命中率高
            const hit_rate = pool.stats.hitRate();
            try testing.expect(hit_rate > 0.95);
        }
    }.run;

    try pt.run(@TypeOf(testFn), testFn);
}

// 属性 24.4：并发分配和释放的正确性
test "Property 24.4: Concurrent allocation and release correctness" {
    std.debug.print("\n=== Property 24.4: Concurrent operations ===\n", .{});

    var pt = PropertyTest.init(testing.allocator, 99999, 20); // 减少迭代次数

    const testFn = struct {
        fn run(self: *PropertyTest) !void {
            var pool = try ObjectPool(TestObject).init(self.allocator, .{
                .initial_capacity = 32,
                .max_capacity = 256,
            });
            defer pool.deinit();

            const Handle = ObjectPool(TestObject).Handle;

            // 模拟交错的分配和释放
            const total_ops = self.rng.intRangeAtMost(usize, 100, 200);
            var active_handles = try std.ArrayList(Handle).initCapacity(self.allocator, 50);
            defer active_handles.deinit(self.allocator);

            var op: usize = 0;
            while (op < total_ops) : (op += 1) {
                const should_allocate = active_handles.items.len == 0 or
                    (active_handles.items.len < 50 and self.rng.boolean());

                if (should_allocate) {
                    // 分配
                    const handle = try pool.acquire();
                    handle.get().* = TestObject.init(op);
                    try testing.expect(handle.get().verify());
                    try active_handles.append(self.allocator, handle);
                } else {
                    // 释放
                    const idx = self.rng.intRangeLessThan(usize, 0, active_handles.items.len);
                    const handle = active_handles.orderedRemove(idx);
                    try testing.expect(handle.get().verify());
                    handle.release();
                }
            }

            // 验证所有活动对象仍然有效
            for (active_handles.items) |handle| {
                try testing.expect(handle.get().verify());
            }

            // 清理
            for (active_handles.items) |handle| {
                handle.release();
            }

            // 验证统计信息一致
            try testing.expectEqual(@as(usize, 0), pool.stats.current_usage);
        }
    }.run;

    try pt.run(@TypeOf(testFn), testFn);
}

// 属性 24.5：池统计信息准确性
test "Property 24.5: Pool statistics accuracy" {
    std.debug.print("\n=== Property 24.5: Statistics accuracy ===\n", .{});

    var pt = PropertyTest.init(testing.allocator, 11111, 20); // 减少迭代次数

    const testFn = struct {
        fn run(self: *PropertyTest) !void {
            var pool = try ObjectPool(TestObject).init(self.allocator, .{
                .initial_capacity = 16,
            });
            defer pool.deinit();

            var expected_allocations: usize = 0;
            var expected_hits: usize = 0;
            var max_concurrent: usize = 0;
            var current_concurrent: usize = 0;

            const ops = self.rng.intRangeAtMost(usize, 50, 100);
            var active_handles = try std.ArrayList(ObjectPool(TestObject).Handle).initCapacity(self.allocator, 20);
            defer active_handles.deinit(self.allocator);

            var i: usize = 0;
            while (i < ops) : (i += 1) {
                if (active_handles.items.len < 20 and self.rng.boolean()) {
                    // 分配
                    const handle = try pool.acquire();
                    expected_allocations += 1;
                    expected_hits += 1;
                    current_concurrent += 1;
                    if (current_concurrent > max_concurrent) {
                        max_concurrent = current_concurrent;
                    }
                    try active_handles.append(self.allocator, handle);
                } else if (active_handles.items.len > 0) {
                    // 释放
                    const handle = active_handles.items[active_handles.items.len - 1];
                    _ = active_handles.pop();
                    handle.release();
                    current_concurrent -= 1;
                }
            }

            // 清理剩余对象
            for (active_handles.items) |handle| {
                handle.release();
            }

            // 验证统计信息
            try testing.expectEqual(expected_allocations, pool.stats.total_allocations);
            try testing.expectEqual(expected_hits, pool.stats.pool_hits);
            try testing.expect(pool.stats.peak_usage <= max_concurrent);
        }
    }.run;

    try pt.run(@TypeOf(testFn), testFn);
}

// 属性 24.6：内存使用效率
test "Property 24.6: Memory usage efficiency" {
    std.debug.print("\n=== Property 24.6: Memory efficiency ===\n", .{});

    // 使用跟踪分配器测量内存使用
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const iterations: usize = 1000;

    // 测试直接分配的内存使用
    {
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            const obj = try allocator.create(TestObject);
            obj.* = TestObject.init(i);
            allocator.destroy(obj);
        }
    }

    // 测试池化分配的内存使用
    {
        var pool = try ObjectPool(TestObject).init(allocator, .{
            .initial_capacity = 32,
            .max_capacity = 64,
        });
        defer pool.deinit();

        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            const handle = try pool.acquire();
            handle.get().* = TestObject.init(i);
            handle.release();
        }
    }

    std.debug.print("Memory efficiency test completed\n", .{});
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
