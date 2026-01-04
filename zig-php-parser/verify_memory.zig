const std = @import("std");
const memory = @import("src/runtime/memory.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Zig-PHP-Parser 功能验证 ===", .{});

    // 1. 验证Arena分配器
    std.log.info("1. 测试Arena分配器", .{});
    var arena = memory.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const data1 = try arena.alloc(u8, 100);
    const data2 = try arena.alloc(i32, 50);

    std.log.info("   - 分配了{}字节和{}个i32", .{ data1.len, data2.len });
    const stats = arena.getStats();
    std.log.info("   - 内存利用率: {d:.2}%", .{stats.utilization * 100});

    // 2. 验证对象池
    std.log.info("2. 测试对象池", .{});
    var pool = memory.ObjectPool([]u8).init(allocator);
    defer pool.deinit();

    const obj1 = try pool.acquire();
    obj1.* = try allocator.dupe(u8, "test data");
    defer allocator.free(obj1.*);

    pool.release(obj1);

    const pool_stats = pool.getStats();
    std.log.info("   - 复用率: {d:.2}%", .{pool_stats.pool_efficiency * 100});

    // 3. 验证字符串驻留
    std.log.info("3. 测试字符串驻留", .{});
    var interner = memory.StringInterner.init(allocator);
    defer interner.deinit();

    const str1 = try interner.intern("hello world");
    const str2 = try interner.intern("hello world");
    const str3 = try interner.intern("different string");

    std.log.info("   - 相同字符串共享: {}", .{str1.ptr == str2.ptr});
    std.log.info("   - 不同字符串独立: {}", .{str1.ptr != str3.ptr});

    const intern_stats = interner.getStats();
    std.log.info("   - 字符串数: {}, 节省字节: {}, 命中率: {d:.2}%", .{ intern_stats.total_strings, intern_stats.bytes_saved, intern_stats.hit_rate * 100 });

    // 4. 验证分代GC
    std.log.info("4. 测试分代垃圾回收", .{});
    var gc = memory.GenerationalGC.init(allocator);
    defer gc.deinit();

    const obj_gc1 = try gc.create(100);
    const obj_gc2 = try gc.create(200);

    try gc.addRoot(obj_gc1);
    try gc.addRoot(obj_gc2);

    std.log.info("   - 创建了{}个GC对象", .{2});

    // 执行GC
    try gc.collectYoung();

    const gc_stats = gc.getStats();
    std.log.info("   - Young GC次数: {}", .{gc_stats.young_gc_count});
    std.log.info("   - 释放字节数: {}", .{gc_stats.total_freed});
    std.log.info("   - 晋升对象数: {}", .{gc_stats.promoted_objects});

    // 5. 验证内存泄漏检测
    std.log.info("5. 测试内存泄漏检测", .{});
    var leak_detector = memory.LeakDetector.init(allocator);
    defer leak_detector.deinit();

    try leak_detector.recordAlloc(0x1000, 100);
    try leak_detector.recordAlloc(0x2000, 200);
    leak_detector.recordFree(0x1000);

    leak_detector.printReport();

    // 6. 验证MemoryManager
    std.log.info("6. 测试MemoryManager整合", .{});
    var mem_mgr = memory.MemoryManager.init(allocator);
    defer mem_mgr.deinit();

    std.log.info("   - MemoryManager初始化成功", .{});

    const mgr_stats = mem_mgr.getStats();
    std.log.info("   - Arena利用率: {d:.2}%", .{mgr_stats.arena_stats.utilization * 100});
    std.log.info("   - 字符串命中率: {d:.2}%", .{mgr_stats.string_stats.hit_rate * 100});

    std.log.info("=== 所有功能验证完成 ===", .{});
}
