const std = @import("std");
const testing = std.testing;
const SlabAllocator = @import("algorithms/slab_allocator.zig").SlabAllocator;

const TestObject = struct {
    value: i32,
};

// Feature: advanced-compiler-optimization, Property 35: Slab 分配器正确性
test "slab allocator allocation and deallocation" {
    const allocator = testing.allocator;
    var slab = SlabAllocator(TestObject).init(allocator);
    defer slab.deinit();

    // 分配多个对象
    var objects: [10]*TestObject = undefined;
    for (&objects, 0..) |*obj, i| {
        obj.* = try slab.alloc();
        obj.*.value = @intCast(i);
    }

    // 验证：所有对象值正确
    for (objects, 0..) |obj, i| {
        try testing.expectEqual(@as(i32, @intCast(i)), obj.value);
    }

    // 释放所有对象
    for (objects) |obj| {
        slab.free(obj);
    }
}

// 测试 slab 扩展
test "slab allocator expands when full" {
    const allocator = testing.allocator;
    var slab = SlabAllocator(TestObject).init(allocator);
    defer slab.deinit();

    // 分配超过一个 slab 的对象
    var objects: [100]*TestObject = undefined;
    for (&objects) |*obj| {
        obj.* = try slab.alloc();
    }

    // 验证：所有对象都已分配
    for (objects) |obj| {
        obj.value = 42;
        try testing.expectEqual(@as(i32, 42), obj.value);
    }

    // 释放
    for (objects) |obj| {
        slab.free(obj);
    }
}

// 测试重用
test "slab allocator reuses freed objects" {
    const allocator = testing.allocator;
    var slab = SlabAllocator(TestObject).init(allocator);
    defer slab.deinit();

    // 分配
    const obj1 = try slab.alloc();
    const addr1 = @intFromPtr(obj1);

    // 释放
    slab.free(obj1);

    // 再次分配应该重用
    const obj2 = try slab.alloc();
    const addr2 = @intFromPtr(obj2);

    try testing.expectEqual(addr1, addr2);

    slab.free(obj2);
}

// 测试混合分配释放
test "slab allocator mixed alloc and free" {
    const allocator = testing.allocator;
    var slab = SlabAllocator(TestObject).init(allocator);
    defer slab.deinit();

    const obj1 = try slab.alloc();
    const obj2 = try slab.alloc();
    const obj3 = try slab.alloc();

    obj1.value = 1;
    obj2.value = 2;
    obj3.value = 3;

    slab.free(obj2);

    const obj4 = try slab.alloc();
    obj4.value = 4;

    try testing.expectEqual(@as(i32, 1), obj1.value);
    try testing.expectEqual(@as(i32, 4), obj4.value);
    try testing.expectEqual(@as(i32, 3), obj3.value);

    slab.free(obj1);
    slab.free(obj3);
    slab.free(obj4);
}

// 测试空 slab
test "slab allocator empty slab" {
    const allocator = testing.allocator;
    var slab = SlabAllocator(TestObject).init(allocator);
    defer slab.deinit();

    // 不分配任何对象，直接销毁
}
