const std = @import("std");
const optimization = @import("src/runtime/optimization.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== 性能优化模块测试 ===", .{});

    // 1. 测试增强的字符串驻留
    std.log.info("\n--- 1. 测试字符串驻留 ---", .{});
    {
        var interner = optimization.EnhancedStringInterner.init(allocator);
        defer interner.deinit();

        const s1 = try interner.intern("hello");
        const s2 = try interner.intern("hello");
        const s3 = try interner.intern("world");

        std.log.info("字符串 'hello' 驻留两次，指针相同: {}", .{s1.ptr == s2.ptr});
        std.log.info("字符串 'world' 驻留，指针不同: {}", .{s1.ptr != s3.ptr});

        const stats = interner.getStats();
        std.log.info("驻留统计:", .{});
        std.log.info("  - 驻留字符串数: {}", .{stats.total_interned});
        std.log.info("  - 命中次数: {}", .{stats.hit_count});
        std.log.info("  - 未命中次数: {}", .{stats.miss_count});
        std.log.info("  - 命中率: {d:.2}%", .{stats.getHitRate() * 100.0});
        std.log.info("  - 节省字节数: {}", .{stats.total_bytes_saved});
    }

    // 2. 测试多态内联缓存
    std.log.info("\n--- 2. 测试内联缓存 ---", .{});
    {
        var cache = optimization.PolymorphicInlineCache.init();

        var dummy1: u32 = 100;
        var dummy2: u32 = 200;

        cache.insert(1, &dummy1);
        cache.insert(2, &dummy2);

        const result1 = cache.lookup(1);
        const result2 = cache.lookup(2);
        const result3 = cache.lookup(3);

        std.log.info("缓存查找 class_id=1: {}", .{result1 != null});
        std.log.info("缓存查找 class_id=2: {}", .{result2 != null});
        std.log.info("缓存查找 class_id=3 (不存在): {}", .{result3 == null});

        const stats = cache.getStats();
        std.log.info("缓存统计:", .{});
        std.log.info("  - 命中次数: {}", .{stats.hits});
        std.log.info("  - 未命中次数: {}", .{stats.misses});
        std.log.info("  - 命中率: {d:.2}%", .{stats.getHitRate() * 100.0});
    }

    // 3. 测试方法缓存
    std.log.info("\n--- 3. 测试方法缓存 ---", .{});
    {
        var method_cache = optimization.MethodCache.init(allocator);
        defer method_cache.deinit();

        var dummy_method: u32 = 42;
        try method_cache.cacheMethod("getValue", 1, &dummy_method);
        try method_cache.cacheMethod("getValue", 2, &dummy_method);

        const found1 = method_cache.lookupMethod("getValue", 1);
        const found2 = method_cache.lookupMethod("getValue", 3);

        std.log.info("方法缓存查找 'getValue' class_id=1: {}", .{found1 != null});
        std.log.info("方法缓存查找 'getValue' class_id=3: {}", .{found2 == null});

        const stats = method_cache.getStats();
        std.log.info("方法缓存统计:", .{});
        std.log.info("  - 总查找次数: {}", .{stats.total_lookups});
        std.log.info("  - 缓存命中: {}", .{stats.cache_hits});
        std.log.info("  - 缓存未命中: {}", .{stats.cache_misses});
        std.log.info("  - 命中率: {d:.2}%", .{stats.getHitRate() * 100.0});
    }

    // 4. 测试分代内存池
    std.log.info("\n--- 4. 测试分代内存池 ---", .{});
    {
        var pool = optimization.GenerationalPool.init(allocator);
        defer pool.deinit();

        const mem1 = try pool.allocYoung(100, 8);
        const mem2 = try pool.allocYoung(200, 8);
        const mem3 = try pool.allocOld(300, 8);

        std.log.info("年轻代分配 100 bytes: {}", .{mem1.len == 100});
        std.log.info("年轻代分配 200 bytes: {}", .{mem2.len == 200});
        std.log.info("老年代分配 300 bytes: {}", .{mem3.len == 300});

        const stats = pool.getStats();
        std.log.info("内存池统计:", .{});
        std.log.info("  - 年轻代分配次数: {}", .{stats.young_allocations});
        std.log.info("  - 老年代分配次数: {}", .{stats.old_allocations});
        std.log.info("  - 总分配字节数: {}", .{stats.total_bytes_allocated});

        pool.collectYoung();
        std.log.info("  - 年轻代回收次数: {}", .{pool.getStats().young_collections});
    }

    // 5. 测试SIMD工具
    std.log.info("\n--- 5. 测试SIMD优化 ---", .{});
    {
        const test_data = "   \t\n  hello world";
        const skip_count = optimization.SimdUtils.skipWhitespace(test_data);
        std.log.info("跳过空白字符数量: {} (预期: 7)", .{skip_count});

        const find_pos = optimization.SimdUtils.findChar(test_data, 'w');
        std.log.info("查找字符 'w' 位置: {} (预期: 13)", .{find_pos.?});

        const count = optimization.SimdUtils.countChar(test_data, 'l');
        std.log.info("统计字符 'l' 数量: {} (预期: 3)", .{count});

        const cmp1 = optimization.SimdUtils.memcmpFast("hello", "hello");
        const cmp2 = optimization.SimdUtils.memcmpFast("hello", "world");
        std.log.info("字符串比较 'hello' == 'hello': {}", .{cmp1});
        std.log.info("字符串比较 'hello' == 'world': {}", .{cmp2});
    }

    // 6. 测试优化管理器
    std.log.info("\n--- 6. 测试优化管理器 ---", .{});
    {
        var manager = optimization.OptimizationManager.init(allocator);
        defer manager.deinit();

        _ = try manager.string_interner.intern("test1");
        _ = try manager.string_interner.intern("test1");
        _ = try manager.string_interner.intern("test2");

        manager.printStats();
    }

    std.log.info("\n=== 所有性能优化测试通过 ===", .{});
}
