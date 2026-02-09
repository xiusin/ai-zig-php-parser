const std = @import("std");
const testing = std.testing;
const RobinHoodHashMap = @import("algorithms/robin_hood_hashmap.zig").RobinHoodHashMap;

// Feature: advanced-compiler-optimization, Property 32: 哈希表往返一致性
test "hash table round trip preserves key-value pairs" {
    const allocator = testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32).init(allocator, 16);
    defer map.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // 插入键值对
        try map.put("key1", 100);
        try map.put("key2", 200);
        try map.put("key3", 300);

        // 验证：所有键值对可查询
        try testing.expectEqual(@as(i32, 100), map.get("key1").?);
        try testing.expectEqual(@as(i32, 200), map.get("key2").?);
        try testing.expectEqual(@as(i32, 300), map.get("key3").?);

        // 清空
        _ = map.remove("key1");
        _ = map.remove("key2");
        _ = map.remove("key3");
    }
}

// Feature: advanced-compiler-optimization, Property 33: 哈希表自动扩容
test "hash table auto resize when load factor exceeds threshold" {
    const allocator = testing.allocator;
    var map = try RobinHoodHashMap(i32, i32).init(allocator, 4);
    defer map.deinit();

    const initial_capacity = map.capacity;

    // 插入足够多的元素触发扩容
    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        try map.put(i, i * 2);
    }

    // 验证：容量已扩大
    try testing.expect(map.capacity > initial_capacity);

    // 验证：所有键值对仍然可访问
    i = 0;
    while (i < 10) : (i += 1) {
        try testing.expectEqual(i * 2, map.get(i).?);
    }
}

// 测试更新现有键
test "hash table update existing key" {
    const allocator = testing.allocator;
    var map = try RobinHoodHashMap(i32, i32).init(allocator, 16);
    defer map.deinit();

    try map.put(1, 100);
    try map.put(1, 200);

    try testing.expectEqual(@as(i32, 200), map.get(1).?);
    try testing.expectEqual(@as(usize, 1), map.len);
}

// 测试删除
test "hash table remove" {
    const allocator = testing.allocator;
    var map = try RobinHoodHashMap(i32, i32).init(allocator, 16);
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);

    try testing.expect(map.remove(1));
    try testing.expectEqual(@as(?i32, null), map.get(1));
    try testing.expectEqual(@as(i32, 200), map.get(2).?);
}

// 测试不存在的键
test "hash table get nonexistent key" {
    const allocator = testing.allocator;
    var map = try RobinHoodHashMap(i32, i32).init(allocator, 16);
    defer map.deinit();

    try testing.expectEqual(@as(?i32, null), map.get(999));
}
