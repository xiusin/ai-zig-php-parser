//! 高级功能集成示例
//!
//! 演示并发GC、增量编译和性能监控的集成使用

const std = @import("std");

// 导入新实现的高级功能
const concurrent_gc = @import("src/runtime/concurrent_gc.zig");
const performance_monitor = @import("src/runtime/performance_monitor.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== 高级功能集成示例 ===\n\n", .{});

    // 1. 并发GC示例
    try testConcurrentGC(allocator);

    // 2. 性能监控示例
    try testPerformanceMonitoring(allocator);

    std.debug.print("\n=== 所有测试完成 ===\n", .{});
}

/// 测试并发GC
fn testConcurrentGC(allocator: std.mem.Allocator) !void {
    std.debug.print("1. 并发GC测试\n", .{});
    std.debug.print("----------------\n", .{});

    // 初始化并发GC（假设有2个线程）
    var gc = concurrent_gc.ConcurrentGC.init(allocator, 2);
    defer gc.deinit();

    std.debug.print("  - 初始化并发GC: OK\n", .{});
    std.debug.print("  - 当前阶段: {}\n", .{gc.getPhase()});

    // 添加一些根对象
    const Value = @import("src/runtime/types.zig").Value;
    try gc.addRoot(Value.initNull());
    try gc.addRoot(Value.initInt(42));
    try gc.addRoot(Value.initString(allocator, "Hello"));

    std.debug.print("  - 添加根对象: OK\n", .{});

    // 获取统计信息
    const stats = gc.getStats();
    std.debug.print("  - GC统计:\n", .{});
    std.debug.print("    * GC次数: {}\n", .{stats.gc_count});
    std.debug.print("  - 标记对象数: {}\n", .{stats.marked_objects});
    std.debug.print("  - 扫描对象数: {}\n", .{stats.scanned_objects});
    std.debug.print("  - 回收对象数: {}\n", .{stats.collected_objects});

    std.debug.print("\n", .{});
}

/// 测试性能监控
fn testPerformanceMonitoring(allocator: std.mem.Allocator) !void {
    std.debug.print("2. 性能监控测试\n", .{});
    std.debug.print("----------------\n", .{});

    // 初始化性能监控器
    var profiler = performance_monitor.RealTimeProfiler.init(allocator);
    defer profiler.deinit();

    std.debug.print("  - 初始化性能监控器: OK\n", .{});

    // 启动性能分析
    profiler.start();
    std.debug.print("  - 启动性能分析: OK\n", .{});

    // 模拟一些工作
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try profiler.sample();
        std.time.sleep(1000); // 1ms
    }

    std.debug.print("  - 采样完成: 1000次\n", .{});

    // 获取性能报告
    const report = try profiler.getPerformanceReport();
    std.debug.print("  - 性能报告:\n", .{});
    std.debug.print("    * IPC: {d:.2}\n", .{report.cpu_ipc});
    std.debug.print("    * 缓存命中率: {d:.2%}\n", .{report.cpu_cache_hit_rate});
    std.debug.print("    * 分支预测准确率: {d:.2%}\n", .{report.cpu_branch_accuracy});
    std.debug.print("    * 当前内存分配: {} bytes\n", .{report.memory_current_allocated});
    std.debug.print("    * 峰值内存分配: {} bytes\n", .{report.memory_peak_allocated});
    std.debug.print("    * 总分配次数: {}\n", .{report.memory_total_allocations});
    std.debug.print("    * 活跃分配数: {}\n", .{report.memory_active_allocations});
    std.debug.print("    * GC总次数: {}\n", .{report.gc_total_count});
    std.debug.print("    * GC平均停顿: {} ns\n", .{report.gc_avg_pause_ns});
    std.debug.print("    * GC吞吐量: {d:.2} MB/s\n", .{report.gc_throughput / (1024.0 * 1024.0)});
    std.debug.print("    * 热点函数数: {}\n", .{report.hotspots.items.len});
    std.debug.print("    * 采样数: {}\n", .{report.sample_count});

    // 显示热点函数
    if (report.hotspots.items.len > 0) {
        std.debug.print("  - 热点函数:\n", .{});
        for (report.hotspots.items, 0..) |hotspot, idx| {
            std.debug.print("    {}. {}\n", .{ idx + 1, hotspot });
            allocator.free(hotspot);
        }
    }
    report.hotspots.deinit();

    // 停止性能分析
    profiler.stop();
    std.debug.print("  - 停止性能分析: OK\n", .{});

    std.debug.print("\n", .{});
}

/// 测试内存分配追踪
fn testAllocationTracking(allocator: std.mem.Allocator) !void {
    std.debug.print("3. 内存分配追踪测试\n", .{});
    std.debug.print("----------------\n", .{});

    // 初始化分配追踪器
    var tracker = performance_monitor.AllocationTracker.init(allocator);
    defer tracker.deinit();

    std.debug.print("  - 初始化分配追踪器: OK\n", .{});

    // 模拟一些分配
    const ptr1 = try allocator.alloc(u8, 1024);
    const location1 = performance_monitor.AllocationTracker.SourceLocation{
        .file = "test.php",
        .line = 10,
        .function = "test_func",
    };
    try tracker.recordAllocation(ptr1, 1024, location1, "string");

    const ptr2 = try allocator.alloc(u8, 2048);
    const location2 = performance_monitor.AllocationTracker.SourceLocation{
        .file = "test.php",
        .line = 20,
        .function = "test_func2",
    };
    try tracker.recordAllocation(ptr2, 2048, location2, "array");

    std.debug.print("  - 记录分配: OK\n", .{});

    // 获取内存统计
    const stats = tracker.getMemoryStats();
    std.debug.print("  - 内存统计:\n", .{});
    std.debug.print("    * 当前分配: {} bytes\n", .{stats.current_allocated});
    std.debug.print("    * 峰值分配: {} bytes\n", .{stats.peak_allocated});
    std.debug.print("    * 总分配次数: {}\n", .{stats.total_allocations});
    std.debug.print("    * 总释放次数: {}\n", .{stats.total_deallocations});
    std.debug.print("    * 活跃分配数: {}\n", .{stats.active_allocations});
    std.debug.print("    * 分配率: {d:.2%}\n", .{stats.allocation_rate});

    // 模拟释放
    tracker.recordDeallocation(ptr1);
    allocator.free(ptr1);

    std.debug.print("  - 释放内存: OK\n", .{});

    // 获取更新后的统计
    const stats2 = tracker.getMemoryStats();
    std.debug.print("  - 更新后统计:\n", .{});
    std.debug.print("    * 当前分配: {} bytes\n", .{stats2.current_allocated});
    std.debug.print("    * 总释放次数: {}\n", .{stats2.total_deallocations});

    // 清理
    tracker.recordDeallocation(ptr2);
    allocator.free(ptr2);

    std.debug.print("\n", .{});
}

/// 测试热点函数追踪
fn testHotspotTracking(allocator: std.mem.Allocator) !void {
    std.debug.print("4. 热点函数追踪测试\n", .{});
    std.debug.print("----------------\n", .{});

    // 初始化热点追踪器
    var tracker = performance_monitor.HotspotTracker.init(allocator);
    defer tracker.deinit();

    std.debug.print("  - 初始化热点追踪器: OK\n", .{});

    // 模拟函数调用
    try tracker.enterFunction("main", "index.php", 1);
    std.time.sleep(1_000); // 1ms

    try tracker.enterFunction("processRequest", "index.php", 10);
    std.time.sleep(2_000); // 2ms
    try tracker.exitFunction();

    try tracker.enterFunction("renderResponse", "index.php", 20);
    std.time.sleep(1_000); // 1ms
    try tracker.exitFunction();

    try tracker.exitFunction();

    std.debug.print("  - 模拟函数调用: OK\n", .{});

    // 模拟热点函数
    var i: usize = 0;
    while (i < performance_monitor.HOTSPOT_THRESHOLD + 100) : (i += 1) {
        try tracker.enterFunction("db_query", "database.php", 50);
        std.time.sleep(100); // 0.1ms
        try tracker.exitFunction();
    }

    std.debug.print("  - 模拟热点函数: OK\n", .{});

    // 获取热点函数
    const hotspots = try tracker.getHotspots();
    std.debug.print("  - 热点函数数: {}\n", .{hotspots.items.len});

    if (hotspots.items.len > 0) {
        std.debug.print("  - 热点函数列表:\n", .{});
        for (hotspots.items, 0..) |hotspot, idx| {
            std.debug.print("    {}. {}\n", .{ idx + 1, hotspot });

            // 获取详细统计
            if (tracker.getFunctionStats(hotspot)) |stats| {
                std.debug.print("       调用次数: {}\n", .{stats.call_count});
                std.debug.print("       平均时间: {} ns\n", .{stats.avg_time_ns});
                std.debug.print("       最大时间: {} ns\n", .{stats.max_time_ns});
                std.debug.print("       最小时间: {} ns\n", .{stats.min_time_ns});
                std.debug.print("       是否热点: {}\n", .{stats.is_hotspot});
            }

            allocator.free(hotspot);
        }
    }
    hotspots.deinit();

    std.debug.print("\n", .{});
}

/// 测试GC追踪
fn testGCTracking(allocator: std.mem.Allocator) !void {
    std.debug.print("5. GC追踪测试\n", .{});
    std.debug.print("----------------\n", .{});

    // 初始化GC追踪器
    var tracker = performance_monitor.GCTracker.init(allocator);
    defer tracker.deinit();

    std.debug.print("  - 初始化GC追踪器: OK\n", .{});

    // 模拟GC周期
    tracker.startGC(.minor);
    std.time.sleep(5_000); // 5ms
    try tracker.endGC(1_000_000, 2_000_000, 3_000_000, 1000, 1024 * 1024, 10 * 1024 * 1024, 9 * 1024 * 1024);

    std.debug.print("  - 模拟Minor GC: OK\n", .{});

    tracker.startGC(.major);
    std.time.sleep(10_000); // 10ms
    try tracker.endGC(5_000_000, 10_000_000, 15_000_000, 5000, 5 * 1024 * 1024, 20 * 1024 * 1024, 15 * 1024 * 1024);

    std.debug.print("  - 模拟Major GC: OK\n", .{});

    // 获取GC统计
    const stats = tracker.getGCStats();
    std.debug.print("  - GC统计:\n", .{});
    std.debug.print("    * 总GC次数: {}\n", .{stats.total_gc_count});
    std.debug.print("    * Minor GC次数: {}\n", .{stats.minor_gc_count});
    std.debug.print("    * Major GC次数: {}\n", .{stats.major_gc_count});
    std.debug.print("    * Full GC次数: {}\n", .{stats.full_gc_count});
    std.debug.print("    * 总停顿时间: {} ms\n", .{stats.total_pause_ns / 1_000_000});
    std.debug.print("    * 平均停顿时间: {} ms\n", .{stats.avg_pause_ns / 1_000_000});
    std.debug.print("    * 总回收对象: {}\n", .{stats.total_collected_objects});
    std.debug.print("    * 总回收内存: {} MB\n", .{stats.total_collected_bytes / (1024 * 1024)});
    std.debug.print("    * GC吞吐量: {d:.2} MB/s\n", .{stats.gc_throughput / (1024.0 * 1024.0)});

    std.debug.print("\n", .{});
}
