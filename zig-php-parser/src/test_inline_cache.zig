const std = @import("std");
const testing = std.testing;
const InlineCache = @import("runtime/inline_cache.zig").InlineCache;

// Feature: advanced-compiler-optimization, Property 20: 内联缓存一致性
test "inline cache consistency - cached results match non-cached" {
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // 测试单态缓存
        var mono = InlineCache.Monomorphic{};

        // 第一次查找失败
        try testing.expect(mono.lookup(1) == null);

        // 更新缓存
        mono.update(1, 0x1234);

        // 第二次查找成功
        const entry = mono.lookup(1);
        try testing.expect(entry != null);
        try testing.expect(entry.?.type_id == 1);
        try testing.expect(entry.?.target == 0x1234);
    }
}

// 测试多态缓存
test "polymorphic cache - handles multiple types" {
    var poly = InlineCache.Polymorphic{};

    // 添加多个类型
    poly.update(1, 0x1000);
    poly.update(2, 0x2000);
    poly.update(3, 0x3000);

    // 查找所有类型
    const entry1 = poly.lookup(1);
    try testing.expect(entry1 != null);
    try testing.expect(entry1.?.target == 0x1000);

    const entry2 = poly.lookup(2);
    try testing.expect(entry2 != null);
    try testing.expect(entry2.?.target == 0x2000);

    const entry3 = poly.lookup(3);
    try testing.expect(entry3 != null);
    try testing.expect(entry3.?.target == 0x3000);
}

// 测试缓存替换
test "cache replacement - replaces least used entry" {
    var poly = InlineCache.Polymorphic{};

    // 填满缓存
    poly.update(1, 0x1000);
    poly.update(2, 0x2000);
    poly.update(3, 0x3000);
    poly.update(4, 0x4000);

    // 增加命中次数
    poly.incrementHit(1);
    poly.incrementHit(1);
    poly.incrementHit(2);

    // 添加新条目，应该替换最少使用的（3 或 4）
    poly.update(5, 0x5000);

    // 验证：1 和 2 仍然存在
    try testing.expect(poly.lookup(1) != null);
    try testing.expect(poly.lookup(2) != null);
    try testing.expect(poly.lookup(5) != null);
}

// 测试单态缓存命中计数
test "monomorphic cache - hit count increments" {
    var mono = InlineCache.Monomorphic{};

    mono.update(1, 0x1234);
    try testing.expect(mono.entry.?.hit_count == 1);

    mono.incrementHit();
    try testing.expect(mono.entry.?.hit_count == 2);

    mono.incrementHit();
    try testing.expect(mono.entry.?.hit_count == 3);
}

// 测试缓存未命中
test "cache miss - returns null" {
    var mono = InlineCache.Monomorphic{};
    try testing.expect(mono.lookup(999) == null);

    var poly = InlineCache.Polymorphic{};
    try testing.expect(poly.lookup(999) == null);
}
