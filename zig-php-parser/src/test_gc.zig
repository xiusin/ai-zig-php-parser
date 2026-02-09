const std = @import("std");
const testing = std.testing;
const GenerationalGC = @import("gc/generational_gc.zig").GenerationalGC;
const Object = @import("gc/generational_gc.zig").Object;

// Feature: advanced-compiler-optimization, Property 22: GC 停顿时间限制
test "GC pause time - minor GC under 5ms" {
    const allocator = testing.allocator;
    
    var gc = try GenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 添加对象到年轻代
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try gc.young_gen.objects.append(allocator, Object{
            .id = i,
            .marked = i % 2 == 0, // 50% 存活
            .age = 0,
        });
    }
    
    const stats = try gc.minorGC();
    
    // 验证：停顿时间 < 5ms
    const pause_time_ms = stats.pause_time_ns / 1_000_000;
    try testing.expect(pause_time_ms < 5);
}

// 测试 Major GC 停顿时间
test "GC pause time - major GC under 20ms" {
    const allocator = testing.allocator;
    
    var gc = try GenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 添加对象到老年代
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try gc.old_gen.objects.append(allocator, Object{
            .id = i,
            .marked = i % 2 == 0,
            .age = 15,
        });
    }
    
    const stats = try gc.majorGC();
    
    // 验证：停顿时间 < 20ms
    const pause_time_ms = stats.pause_time_ns / 1_000_000;
    try testing.expect(pause_time_ms < 20);
}

// Feature: advanced-compiler-optimization, Property 23: 内存碎片压缩
test "memory compaction - reduces fragmentation" {
    const allocator = testing.allocator;
    
    var gc = try GenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 执行压缩
    try gc.compact();
    
    // 验证：碎片率降低
    const frag_rate = gc.fragmentationRate();
    try testing.expect(frag_rate < 0.3);
}

// 测试对象晋升
test "object promotion - promotes old objects" {
    const allocator = testing.allocator;
    
    var gc = try GenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 添加老对象
    try gc.young_gen.objects.append(allocator, Object{
        .id = 1,
        .marked = true,
        .age = 14,
    });
    
    _ = try gc.minorGC();
    
    // 验证：对象晋升到老年代
    try testing.expect(gc.old_gen.objects.items.len > 0);
}

// 测试 GC 统计
test "GC stats - tracks collection metrics" {
    const allocator = testing.allocator;
    
    var gc = try GenerationalGC.init(allocator);
    defer gc.deinit();
    
    try gc.young_gen.objects.append(allocator, Object{
        .id = 1,
        .marked = true,
        .age = 0,
    });
    
    try gc.young_gen.objects.append(allocator, Object{
        .id = 2,
        .marked = false,
        .age = 0,
    });
    
    const stats = try gc.minorGC();
    
    // 验证：统计信息正确
    try testing.expect(stats.survived == 1);
    try testing.expect(stats.collected == 1);
}
