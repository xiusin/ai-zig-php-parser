const std = @import("std");
const memory = @import("src/runtime/memory.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== 性能基准测试验证 ===", .{});

    // 1. Arena分配器性能测试
    std.log.info("1. Arena分配器性能测试", .{});

    const iterations = 10000;
    var timer = try std.time.Timer.start();

    // 测试Arena分配器
    var arena = memory.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const start = timer.lap();
    for (0..iterations) |_| {
        const data = try arena.alloc(u8, 64);
        _ = data;
    }
    const arena_time = timer.read() - start;

    std.log.info("   - Arena分配 {} 次: {} ns", .{ iterations, arena_time });
    std.log.info("   - 平均每次分配: {} ns", .{arena_time / iterations});

    // 2. 对象池性能测试
    std.log.info("2. 对象池性能测试", .{});

    var pool = memory.ObjectPool([]u8).init(allocator);
    defer pool.deinit();

    // 预分配一些对象
    for (0..1000) |_| {
        const obj = try pool.acquire();
        pool.release(obj);
    }

    const pool_start = timer.lap();
    for (0..iterations) |_| {
        const obj = try pool.acquire();
        // 模拟使用
        obj.* = try allocator.dupe(u8, "test data");
        allocator.free(obj.*);
        pool.release(obj);
    }
    const pool_time = timer.read() - pool_start;

    const pool_stats = pool.getStats();
    std.log.info("   - 对象池操作 {} 次: {} ns", .{ iterations, pool_time });
    std.log.info("   - 复用率: {d:.2}%", .{pool_stats.pool_efficiency * 100});

    // 3. 字符串驻留性能测试
    std.log.info("3. 字符串驻留性能测试", .{});

    var interner = memory.StringInterner.init(allocator);
    defer interner.deinit();

    const strings = [_][]const u8{
        "hello", "world", "php", "zig", "parser", "memory", "optimization",
        "hello", "world", "php", "zig", "parser", "memory", "optimization", // 重复
    };

    const intern_start = timer.lap();
    for (strings) |str| {
        _ = try interner.intern(str);
    }
    const intern_time = timer.read() - intern_start;

    const intern_stats = interner.getStats();
    std.log.info("   - 字符串驻留 {} 个: {} ns", .{ strings.len, intern_time });
    std.log.info("   - 节省字节: {}", .{intern_stats.bytes_saved});
    std.log.info("   - 命中率: {d:.2}%", .{intern_stats.hit_rate * 100});

    // 4. 分代GC性能测试
    std.log.info("4. 分代GC性能测试", .{});

    var gc = memory.GenerationalGC.init(allocator);
    defer gc.deinit();

    // 创建一些GC对象
    for (0..1000) |_| {
        const obj = try gc.create(64);
        try gc.addRoot(obj);
    }

    const gc_start = timer.lap();
    for (0..100) |_| {
        try gc.collectYoung();
    }
    const gc_time = timer.read() - gc_start;

    const gc_stats = gc.getStats();
    std.log.info("   - 100次Young GC: {} ns", .{gc_time});
    std.log.info("   - 平均每次GC: {} ns", .{gc_time / 100});
    std.log.info("   - Young GC次数: {}", .{gc_stats.young_gc_count});
    std.log.info("   - 释放字节数: {}", .{gc_stats.total_freed});

    // 5. 内存管理器综合性能测试
    std.log.info("5. 内存管理器综合性能测试", .{});

    var mem_mgr = memory.MemoryManager.init(allocator);
    defer mem_mgr.deinit();

    const mgr_start = timer.lap();
    for (0..1000) |_| {
        // 模拟典型PHP操作的内存分配模式
        _ = try mem_mgr.string_pool.intern("dynamic_string");
        const obj = try mem_mgr.gc.create(32);
        try mem_mgr.gc.addRoot(obj);
    }
    const mgr_time = timer.read() - mgr_start;

    std.log.info("   - 综合内存操作 1000 次: {} ns", .{mgr_time});
    std.log.info("   - 平均每次操作: {} ns", .{mgr_time / 1000});

    const mgr_stats = mem_mgr.getStats();
    std.log.info("   - 字符串池效率: {d:.2}%", .{mgr_stats.string_stats.hit_rate * 100});

    // 6. 性能对比测试
    std.log.info("6. 性能对比测试", .{});

    // 直接分配器 vs Arena分配器
    const direct_start = timer.lap();
    var direct_allocations = std.ArrayListUnmanaged([]u8){};
    defer {
        for (direct_allocations.items) |item| {
            allocator.free(item);
        }
        direct_allocations.deinit(allocator);
    }

    for (0..1000) |_| {
        const mem = try allocator.alloc(u8, 32);
        try direct_allocations.append(allocator, mem);
    }
    const direct_time = timer.read() - direct_start;

    // Arena分配器
    var arena2 = memory.ArenaAllocator.init(allocator);
    defer arena2.deinit();

    const arena_start = timer.lap();
    for (0..1000) |_| {
        _ = try arena2.alloc(u8, 32);
    }
    const arena_time2 = timer.read() - arena_start;

    const speedup = @as(f64, @floatFromInt(direct_time)) / @as(f64, @floatFromInt(arena_time2));
    std.log.info("   - 直接分配器: {} ns", .{direct_time});
    std.log.info("   - Arena分配器: {} ns", .{arena_time2});
    std.log.info("   - 性能提升: {d:.2}x", .{speedup});

    std.log.info("=== 性能基准测试完成 ===", .{});
}
