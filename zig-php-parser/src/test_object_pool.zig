const std = @import("std");
const testing = std.testing;
const object_pool = @import("runtime/object_pool.zig");
const ObjectPool = object_pool.ObjectPool;
const StringInterner = object_pool.StringInterner;

// Feature: advanced-compiler-optimization, Property 21: 字符串共享正确性
test "string sharing - shared strings have same pointer" {
    const allocator = testing.allocator;

    var interner = StringInterner.init(allocator);
    defer interner.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const str1 = try interner.intern("hello");
        const str2 = try interner.intern("hello");

        // 验证：相同字符串共享内存
        try testing.expect(str1.ptr == str2.ptr);
        try testing.expect(std.mem.eql(u8, str1, str2));
    }
}

// 测试对象池
test "object pool - reuses objects" {
    const allocator = testing.allocator;

    var pool = try ObjectPool.init(allocator, 10);
    defer pool.deinit();

    // 释放对象到池
    try pool.release(0x1000);
    try pool.release(0x2000);

    try testing.expect(pool.size() == 2);

    // 从池获取对象
    const obj1 = pool.acquire();
    try testing.expect(obj1 != null);
    try testing.expect(obj1.? == 0x2000);

    const obj2 = pool.acquire();
    try testing.expect(obj2 != null);
    try testing.expect(obj2.? == 0x1000);

    try testing.expect(pool.size() == 0);
}

// 测试池容量限制
test "object pool - respects max size" {
    const allocator = testing.allocator;

    var pool = try ObjectPool.init(allocator, 2);
    defer pool.deinit();

    try pool.release(0x1000);
    try pool.release(0x2000);
    try pool.release(0x3000); // 超过容量

    try testing.expect(pool.size() == 2);
}

// 测试字符串驻留计数
test "string interner - counts unique strings" {
    const allocator = testing.allocator;

    var interner = StringInterner.init(allocator);
    defer interner.deinit();

    _ = try interner.intern("hello");
    _ = try interner.intern("hello");
    _ = try interner.intern("world");

    try testing.expect(interner.count() == 2);
}

// 测试空池
test "object pool - empty pool returns null" {
    const allocator = testing.allocator;

    var pool = try ObjectPool.init(allocator, 10);
    defer pool.deinit();

    const obj = pool.acquire();
    try testing.expect(obj == null);
}
