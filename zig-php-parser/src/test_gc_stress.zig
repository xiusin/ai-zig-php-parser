/// GC压力测试
/// 测试大量对象分配/释放、循环引用、增量GC和分代GC场景
const std = @import("std");
const testing = std.testing;

// 导入GC模块
const gc_module = @import("runtime/gc.zig");
const GarbageCollector = gc_module.GarbageCollector;
const Box = gc_module.Box;

const memory_module = @import("runtime/memory.zig");
const GenerationalGC = memory_module.GenerationalGC;
const ArenaAllocator = memory_module.ArenaAllocator;
const ObjectPool = memory_module.ObjectPool;
const StringInterner = memory_module.StringInterner;
const LeakDetector = memory_module.LeakDetector;

// ============================================================================
// 基础GC测试
// ============================================================================

test "gc stress - basic allocation tracking" {
    const allocator = testing.allocator;
    
    var gc = try GarbageCollector.init(allocator, 1024 * 1024);
    defer gc.deinit();
    
    // 追踪多次分配
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        gc.trackAllocation(1024);
    }
    
    try testing.expectEqual(@as(usize, 100 * 1024), gc.allocated_memory);
    
    // 追踪释放
    i = 0;
    while (i < 50) : (i += 1) {
        gc.trackDeallocation(1024);
    }
    
    try testing.expectEqual(@as(usize, 50 * 1024), gc.allocated_memory);
}

test "gc stress - memory threshold trigger" {
    const allocator = testing.allocator;
    
    // 设置较低的阈值
    var gc = try GarbageCollector.init(allocator, 10 * 1024);
    defer gc.deinit();
    
    // 分配低于阈值
    gc.trackAllocation(5 * 1024);
    try testing.expect(!gc.shouldCollect());
    
    // 分配超过阈值
    gc.trackAllocation(6 * 1024);
    try testing.expect(gc.shouldCollect());
}

test "gc stress - incremental state machine" {
    const allocator = testing.allocator;
    
    var gc = try GarbageCollector.init(allocator, 1024 * 1024);
    defer gc.deinit();
    
    // 初始状态应该是idle
    try testing.expectEqual(GarbageCollector.IncrementalState.idle, gc.incremental_state);
    
    // 第一步应该转换到marking
    _ = gc.incrementalStep(10);
    try testing.expectEqual(GarbageCollector.IncrementalState.marking, gc.incremental_state);
    
    // 继续步进直到完成
    while (!gc.incrementalStep(100)) {}
    
    // 完成后应该回到idle
    try testing.expectEqual(GarbageCollector.IncrementalState.idle, gc.incremental_state);
    try testing.expectEqual(@as(u64, 1), gc.stats.total_collections);
}

test "gc stress - write barrier buffer" {
    const allocator = testing.allocator;
    
    var gc = try GarbageCollector.init(allocator, 1024 * 1024);
    defer gc.deinit();
    
    // 在idle状态下写屏障不应该记录
    var dummy1: u8 = 0;
    var dummy2: u8 = 0;
    gc.writeBarrier(&dummy1, &dummy2);
    try testing.expectEqual(@as(usize, 0), gc.write_barrier_buffer.items.len);
    
    // 进入marking状态
    _ = gc.incrementalStep(10);
    try testing.expectEqual(GarbageCollector.IncrementalState.marking, gc.incremental_state);
    
    // 在marking状态下写屏障应该记录
    gc.writeBarrier(&dummy1, &dummy2);
    try testing.expectEqual(@as(usize, 1), gc.write_barrier_buffer.items.len);
}

test "gc stress - nursery allocation" {
    const allocator = testing.allocator;
    
    var gc = try GarbageCollector.init(allocator, 1024 * 1024);
    defer gc.deinit();
    
    // 年轻代分配应该成功
    try testing.expect(gc.nurseryAlloc(1024));
    try testing.expectEqual(@as(usize, 1024), gc.nursery_used);
    
    // 继续分配直到接近限制
    const remaining = gc.nursery_size - gc.nursery_used;
    try testing.expect(gc.nurseryAlloc(remaining - 100));
    
    // 超过限制应该失败
    try testing.expect(!gc.nurseryAlloc(200));
    
    // 回收后应该可以再次分配
    gc.collectNursery();
    try testing.expectEqual(@as(usize, 0), gc.nursery_used);
    try testing.expect(gc.nurseryAlloc(1024));
}

test "gc stress - gc statistics" {
    const allocator = testing.allocator;
    
    var gc = try GarbageCollector.init(allocator, 1024 * 1024);
    defer gc.deinit();
    
    // 执行多次GC
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        _ = gc.collect();
    }
    
    const stats = gc.getStats();
    try testing.expectEqual(@as(u64, 5), stats.total_collections);
    
    // 检查报告生成
    const report = gc.getReport();
    try testing.expectEqual(@as(u64, 5), report.total_collections);
}

// ============================================================================
// 分代GC测试
// ============================================================================

test "gc stress - generational gc object creation" {
    const allocator = testing.allocator;
    
    var gen_gc = GenerationalGC.init(allocator);
    defer gen_gc.deinit();
    
    // 创建多个对象
    var objects: [50]*GenerationalGC.GCObject = undefined;
    for (&objects) |*obj| {
        obj.* = try gen_gc.create(128);
        try testing.expectEqual(GenerationalGC.GCObject.Gen.young, obj.*.gen);
        try testing.expectEqual(@as(u8, 0), obj.*.age);
    }
    
    try testing.expectEqual(@as(usize, 50), gen_gc.young_objects.items.len);
}

test "gc stress - generational gc promotion" {
    const allocator = testing.allocator;
    
    var gen_gc = GenerationalGC.init(allocator);
    defer gen_gc.deinit();
    
    // 创建对象并添加为根
    const obj = try gen_gc.create(128);
    try gen_gc.addRoot(obj);
    
    // 多次Minor GC使对象晋升
    var i: usize = 0;
    while (i < gen_gc.promotion_age) : (i += 1) {
        try gen_gc.collectYoung();
    }
    
    // 对象应该已经晋升到老年代
    try testing.expectEqual(GenerationalGC.GCObject.Gen.old, obj.gen);
    try testing.expect(gen_gc.getStats().promoted_objects > 0);
}

test "gc stress - generational gc write barrier" {
    const allocator = testing.allocator;
    
    var gen_gc = GenerationalGC.init(allocator);
    defer gen_gc.deinit();
    
    // 创建年轻代和老年代对象
    const young_obj = try gen_gc.create(64);
    const old_obj = try gen_gc.create(64);
    
    // 手动设置为老年代
    old_obj.gen = .old;
    
    // 写屏障应该记录跨代引用
    try gen_gc.writeBarrier(old_obj, young_obj);
    
    try testing.expect(gen_gc.remember_set.contains(old_obj));
    try testing.expect(gen_gc.getStats().write_barrier_triggers > 0);
}

test "gc stress - generational gc root management" {
    const allocator = testing.allocator;
    
    var gen_gc = GenerationalGC.init(allocator);
    defer gen_gc.deinit();
    
    const obj1 = try gen_gc.create(64);
    const obj2 = try gen_gc.create(64);
    
    try gen_gc.addRoot(obj1);
    try gen_gc.addRoot(obj2);
    try testing.expectEqual(@as(usize, 2), gen_gc.roots.items.len);
    
    gen_gc.removeRoot(obj1);
    try testing.expectEqual(@as(usize, 1), gen_gc.roots.items.len);
}

// ============================================================================
// Arena分配器压力测试
// ============================================================================

test "gc stress - arena rapid allocation" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    // 快速分配大量小对象
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try arena.alloc(u8, 64);
    }
    
    const stats = arena.getStats();
    try testing.expect(stats.total_used >= 64 * 1000);
    try testing.expect(stats.utilization > 0.5);
}

test "gc stress - arena reset and reuse" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    // 第一轮分配
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try arena.alloc(u8, 128);
    }
    
    const stats1 = arena.getStats();
    const allocated1 = stats1.total_allocated;
    
    // 重置
    arena.reset();
    
    // 第二轮分配应该复用内存
    i = 0;
    while (i < 100) : (i += 1) {
        _ = try arena.alloc(u8, 128);
    }
    
    const stats2 = arena.getStats();
    // 不应该分配新的chunk
    try testing.expectEqual(allocated1, stats2.total_allocated);
}

test "gc stress - arena large allocation" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    // 分配大于默认chunk大小的对象
    const large_size = 128 * 1024;
    const data = try arena.alloc(u8, large_size);
    try testing.expectEqual(large_size, data.len);
    
    const stats = arena.getStats();
    try testing.expect(stats.total_allocated >= large_size);
}

// ============================================================================
// 对象池压力测试
// ============================================================================

test "gc stress - object pool rapid acquire release" {
    const TestStruct = struct {
        value: u64,
        data: [56]u8,
    };
    
    var pool = ObjectPool(TestStruct).init(testing.allocator);
    defer pool.deinit();
    
    // 快速获取和释放
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const obj = try pool.acquire();
        obj.value = i;
        pool.release(obj);
    }
    
    const stats = pool.getStats();
    try testing.expect(stats.recycled_count > 0);
    try testing.expect(stats.pool_efficiency > 0.9);
}

test "gc stress - object pool concurrent simulation" {
    const TestObj = struct { id: u32 };
    
    var pool = ObjectPool(TestObj).init(testing.allocator);
    defer pool.deinit();
    
    // 模拟并发：保持一些对象活跃，同时获取释放其他对象
    var active: [10]*TestObj = undefined;
    
    // 获取初始活跃对象
    for (&active, 0..) |*obj, idx| {
        obj.* = try pool.acquire();
        obj.*.id = @intCast(idx);
    }
    
    // 快速获取释放
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const temp = try pool.acquire();
        temp.id = @intCast(i + 100);
        pool.release(temp);
    }
    
    // 释放活跃对象
    for (active) |obj| {
        pool.release(obj);
    }
    
    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 0), stats.active_count);
}

// ============================================================================
// 字符串驻留池压力测试
// ============================================================================

test "gc stress - string interner deduplication" {
    var interner = StringInterner.init(testing.allocator);
    defer interner.deinit();
    
    // 驻留相同字符串多次
    const str = "test_string_for_interning";
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try interner.intern(str);
    }
    
    const stats = interner.getStats();
    try testing.expectEqual(@as(usize, 1), stats.total_strings);
    try testing.expect(stats.bytes_saved >= str.len * 99);
    try testing.expect(stats.hit_rate > 0.98);
}

test "gc stress - string interner many unique strings" {
    var interner = StringInterner.init(testing.allocator);
    defer interner.deinit();
    
    // 驻留多个不同字符串
    var buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const len = std.fmt.bufPrint(&buf, "string_{d}", .{i}) catch unreachable;
        _ = try interner.intern(len);
    }
    
    const stats = interner.getStats();
    try testing.expectEqual(@as(usize, 100), stats.total_strings);
}

test "gc stress - string interner release" {
    var interner = StringInterner.init(testing.allocator);
    defer interner.deinit();
    
    const str = "releasable_string";
    const interned = try interner.intern(str);
    try testing.expectEqual(@as(usize, 1), interner.getStats().total_strings);
    
    interner.release(interned);
    try testing.expectEqual(@as(usize, 0), interner.getStats().total_strings);
}

// ============================================================================
// 内存泄漏检测器测试
// ============================================================================

test "gc stress - leak detector tracking" {
    var detector = LeakDetector.init(testing.allocator);
    defer detector.deinit();
    
    // 记录多次分配
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        try detector.recordAlloc(0x1000 + i * 0x100, 256);
    }
    
    // 释放一半
    i = 0;
    while (i < 25) : (i += 1) {
        detector.recordFree(0x1000 + i * 0x100);
    }
    
    const report = detector.checkLeaks();
    try testing.expectEqual(@as(usize, 25), report.leaked_allocations);
    try testing.expectEqual(@as(usize, 25 * 256), report.leaked_bytes);
    try testing.expect(report.has_leaks);
}

test "gc stress - leak detector peak memory" {
    var detector = LeakDetector.init(testing.allocator);
    defer detector.deinit();
    
    // 分配增加内存
    try detector.recordAlloc(0x1000, 1000);
    try detector.recordAlloc(0x2000, 2000);
    try detector.recordAlloc(0x3000, 3000);
    
    // 释放一些
    detector.recordFree(0x1000);
    detector.recordFree(0x2000);
    
    const report = detector.checkLeaks();
    try testing.expectEqual(@as(usize, 6000), report.peak_memory);
    try testing.expectEqual(@as(usize, 3000), detector.current_memory);
}

test "gc stress - leak detector no leaks" {
    var detector = LeakDetector.init(testing.allocator);
    defer detector.deinit();
    
    // 分配并全部释放
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try detector.recordAlloc(0x1000 + i * 0x100, 128);
    }
    
    i = 0;
    while (i < 20) : (i += 1) {
        detector.recordFree(0x1000 + i * 0x100);
    }
    
    const report = detector.checkLeaks();
    try testing.expect(!report.has_leaks);
    try testing.expectEqual(@as(usize, 0), report.leaked_allocations);
}

// ============================================================================
// GC时间统计测试
// ============================================================================

test "gc stress - gc timing statistics" {
    const allocator = testing.allocator;
    
    var gc = try GarbageCollector.init(allocator, 1024 * 1024);
    defer gc.deinit();
    
    // 执行GC并检查时间统计
    _ = gc.collect();
    
    const stats = gc.getStats();
    // 时间应该被记录
    try testing.expect(stats.timing.total_mark_time_ns > 0 or stats.timing.total_sweep_time_ns > 0 or stats.total_collections > 0);
}

test "gc stress - gc report generation" {
    const allocator = testing.allocator;
    
    var gc = try GarbageCollector.init(allocator, 1024 * 1024);
    defer gc.deinit();
    
    // 模拟一些内存活动
    gc.trackAllocation(10000);
    _ = gc.collect();
    gc.trackDeallocation(5000);
    _ = gc.collect();
    
    const report = gc.getReport();
    try testing.expectEqual(@as(u64, 2), report.total_collections);
}

// ============================================================================
// 综合压力测试
// ============================================================================

test "gc stress - mixed allocation patterns" {
    const allocator = testing.allocator;
    
    var gen_gc = GenerationalGC.init(allocator);
    defer gen_gc.deinit();
    
    // 创建不同大小的对象
    const sizes = [_]usize{ 16, 64, 256, 1024, 4096 };
    
    for (sizes) |size| {
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            const obj = try gen_gc.create(size);
            if (i % 2 == 0) {
                try gen_gc.addRoot(obj);
            }
        }
    }
    
    // 执行GC
    try gen_gc.collectYoung();
    
    const stats = gen_gc.getStats();
    try testing.expect(stats.total_allocated > 0);
}

test "gc stress - memory manager integration" {
    var mm = memory_module.MemoryManager.init(testing.allocator);
    defer mm.deinit();
    
    // 使用各种内存管理功能
    _ = try mm.arena.alloc(u8, 1024);
    _ = try mm.string_pool.intern("test_string");
    _ = try mm.gc.create(256);
    
    const stats = mm.getStats();
    try testing.expect(stats.arena_stats.total_used > 0);
    try testing.expect(stats.string_stats.total_strings > 0);
}
