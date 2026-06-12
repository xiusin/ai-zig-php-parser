/// 性能剖析集成测试
/// 
/// 测试 Profiler, PerfIntegration 和 TracyIntegration 的集成
/// 
/// **Feature: zig-php-performance-optimization**
/// **Task 53: 实现性能剖析集成**
/// **验证：需求 10.4**

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const Profiler = @import("profiler.zig").Profiler;
const PerfIntegration = @import("perf_integration.zig").PerfIntegration;
const TracyIntegration = @import("tracy_integration.zig").TracyIntegration;

// ============================================================================
// 集成测试
// ============================================================================

test "Profiler + PerfIntegration 集成" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    
    const allocator = testing.allocator;
    
    // 初始化 Profiler
    var profiler = try Profiler.init(allocator, .perf);
    defer profiler.deinit();
    
    // 初始化 Perf 集成
    var perf = try PerfIntegration.init(allocator, &profiler);
    defer perf.deinit();
    
    // 启动性能监控
    try perf.start();
    
    // 模拟函数调用
    try profiler.enterFunction("test_func");
    
    // 模拟工作
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 10000) : (i += 1) {
        sum += i * i;
    }
    
    try profiler.exitFunction("test_func");
    
    // 停止性能监控
    try perf.stop();
    
    // 验证统计
    const stats = profiler.getFunctionStats("test_func");
    try testing.expect(stats != null);
    try testing.expectEqual(@as(u64, 1), stats.?.call_count);
    
    // 读取性能计数器
    const counters = try perf.readCounters();
    try testing.expect(counters.cpu_cycles > 0);
}

test "Profiler + TracyIntegration 集成" {
    const allocator = testing.allocator;
    
    // 初始化 Profiler
    var profiler = try Profiler.init(allocator, .tracy);
    defer profiler.deinit();
    
    // 初始化 Tracy 集成
    var tracy = TracyIntegration.init(allocator, &profiler);
    defer tracy.deinit();
    
    // 模拟函数调用
    var zone = tracy.enterFunction("test_func");
    
    // 模拟工作
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 10000) : (i += 1) {
        sum += i * i;
    }
    
    tracy.exitFunction(&zone);
    
    // 验证统计
    try testing.expectEqual(@as(u64, 1), tracy.zone_count);
}

test "完整性能剖析工作流" {
    const allocator = testing.allocator;
    
    // 初始化 Profiler
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 初始化 Tracy 集成
    var tracy = TracyIntegration.init(allocator, &profiler);
    defer tracy.deinit();
    
    // 模拟多个函数调用
    const functions = [_][]const u8{ "func1", "func2", "func3" };
    
    for (functions) |func_name| {
        var zone = tracy.enterFunction(func_name);
        try profiler.enterFunction(func_name);
        
        // 模拟工作
        var sum: u64 = 0;
        var i: u64 = 0;
        while (i < 1000) : (i += 1) {
            sum += i;
        }
        
        try profiler.exitFunction(func_name);
        tracy.exitFunction(&zone);
    }
    
    // 验证统计
    for (functions) |func_name| {
        const stats = profiler.getFunctionStats(func_name);
        try testing.expect(stats != null);
        try testing.expectEqual(@as(u64, 1), stats.?.call_count);
    }
    
    try testing.expectEqual(@as(u64, 3), tracy.zone_count);
}

test "性能剖析热点分析" {
    const allocator = testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 创建不同执行时间的函数
    const TestFunc = struct {
        fn fast() void {
            var sum: u64 = 0;
            var i: u64 = 0;
            while (i < 100) : (i += 1) {
                sum += i;
            }
        }
        
        fn medium() void {
            var sum: u64 = 0;
            var i: u64 = 0;
            while (i < 1000) : (i += 1) {
                sum += i;
            }
        }
        
        fn slow() void {
            var sum: u64 = 0;
            var i: u64 = 0;
            while (i < 10000) : (i += 1) {
                sum += i;
            }
        }
    };
    
    // 执行函数
    try profiler.enterFunction("fast");
    TestFunc.fast();
    try profiler.exitFunction("fast");
    
    try profiler.enterFunction("medium");
    TestFunc.medium();
    try profiler.exitFunction("medium");
    
    try profiler.enterFunction("slow");
    TestFunc.slow();
    try profiler.exitFunction("slow");
    
    // 获取热点函数
    const hotspots = try profiler.getHotspots(allocator, 2);
    defer allocator.free(hotspots);
    
    try testing.expectEqual(@as(usize, 2), hotspots.len);
    
    // 验证热点函数按时间排序
    try testing.expect(hotspots[0].total_time_ns >= hotspots[1].total_time_ns);
}

test "性能剖析 JSON 导出" {
    const allocator = testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 执行一些函数
    try profiler.enterFunction("func1");
    try profiler.exitFunction("func1");
    
    try profiler.enterFunction("func2");
    try profiler.exitFunction("func2");
    
    // 导出为 JSON
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    defer buffer.deinit(allocator);
    
    try profiler.exportJSON(buffer.writer(allocator));
    
    const json = buffer.items;
    
    // 验证 JSON 格式
    try testing.expect(std.mem.indexOf(u8, json, "\"profiler_type\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"total_calls\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"functions\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"func1\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"func2\"") != null);
}

test "性能剖析并发安全" {
    const allocator = testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 创建多个线程同时进行剖析
    const ThreadContext = struct {
        profiler: *Profiler,
        thread_id: usize,
        
        fn worker(ctx: *@This()) void {
            var i: usize = 0;
            while (i < 10) : (i += 1) {
                const func_name = std.fmt.allocPrint(
                    std.testing.allocator,
                    "thread_{d}_func_{d}",
                    .{ ctx.thread_id, i },
                ) catch return;
                defer std.testing.allocator.free(func_name);
                
                ctx.profiler.enterFunction(func_name) catch return;
                
                // 模拟工作
                var sum: u64 = 0;
                var j: u64 = 0;
                while (j < 100) : (j += 1) {
                    sum += j;
                }
                
                ctx.profiler.exitFunction(func_name) catch return;
            }
        }
    };
    
    var threads: [4]std.Thread = undefined;
    var contexts: [4]ThreadContext = undefined;
    
    // 启动线程
    for (&threads, 0..) |*thread, i| {
        contexts[i] = .{
            .profiler = &profiler,
            .thread_id = i,
        };
        thread.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{&contexts[i]});
    }
    
    // 等待线程完成
    for (threads) |thread| {
        thread.join();
    }
    
    // 验证统计
    try testing.expect(profiler.total_calls >= 40); // 至少 4 * 10 次调用
}

test "性能剖析内存使用" {
    const allocator = testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 执行大量函数调用
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const func_name = try std.fmt.allocPrint(allocator, "func_{d}", .{i});
        defer allocator.free(func_name);
        
        try profiler.enterFunction(func_name);
        try profiler.exitFunction(func_name);
    }
    
    // 验证统计
    try testing.expectEqual(@as(u64, 1000), profiler.total_calls);
    
    // 获取所有统计
    const all_stats = try profiler.getAllStats(allocator);
    defer allocator.free(all_stats);
    
    try testing.expectEqual(@as(usize, 1000), all_stats.len);
}

test "性能剖析重置功能" {
    const allocator = testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 执行一些函数
    try profiler.enterFunction("func1");
    try profiler.exitFunction("func1");
    
    try profiler.enterFunction("func2");
    try profiler.exitFunction("func2");
    
    // 验证有统计
    try testing.expectEqual(@as(u64, 2), profiler.total_calls);
    
    // 重置
    profiler.reset();
    
    // 验证统计被清空
    try testing.expectEqual(@as(u64, 0), profiler.total_calls);
    try testing.expect(profiler.getFunctionStats("func1") == null);
    try testing.expect(profiler.getFunctionStats("func2") == null);
}

test "Tracy 帧标记和绘图" {
    const allocator = testing.allocator;
    
    var profiler = try Profiler.init(allocator, .tracy);
    defer profiler.deinit();
    
    var tracy = TracyIntegration.init(allocator, &profiler);
    defer tracy.deinit();
    
    // 模拟游戏循环
    var frame: usize = 0;
    while (frame < 10) : (frame += 1) {
        tracy.markFrame();
        
        // 模拟帧工作
        var zone = tracy.enterFunction("frame_update");
        
        var sum: u64 = 0;
        var i: u64 = 0;
        while (i < 1000) : (i += 1) {
            sum += i;
        }
        
        tracy.exitFunction(&zone);
        
        // 绘制性能指标
        tracy.plotMetrics();
    }
    
    try testing.expectEqual(@as(u64, 10), tracy.frame_count);
}

// ============================================================================
// 性能基准测试
// ============================================================================

test "性能剖析开销基准" {
    const allocator = testing.allocator;
    
    // 测试无剖析的执行时间
    const start_no_profiling = std.time.nanoTimestamp();
    
    var sum1: u64 = 0;
    var i: u64 = 0;
    while (i < 100000) : (i += 1) {
        sum1 += i * i;
    }
    
    const end_no_profiling = std.time.nanoTimestamp();
    const time_no_profiling = end_no_profiling - start_no_profiling;
    
    // 测试有剖析的执行时间
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    const start_with_profiling = std.time.nanoTimestamp();
    
    try profiler.enterFunction("benchmark_func");
    
    var sum2: u64 = 0;
    var j: u64 = 0;
    while (j < 100000) : (j += 1) {
        sum2 += j * j;
    }
    
    try profiler.exitFunction("benchmark_func");
    
    const end_with_profiling = std.time.nanoTimestamp();
    const time_with_profiling = end_with_profiling - start_with_profiling;
    
    // 计算开销
    const overhead = time_with_profiling - time_no_profiling;
    const overhead_percent = @as(f64, @floatFromInt(overhead)) / @as(f64, @floatFromInt(time_no_profiling)) * 100.0;
    
    std.debug.print("\n性能剖析开销:\n", .{});
    std.debug.print("  无剖析: {d} ns\n", .{time_no_profiling});
    std.debug.print("  有剖析: {d} ns\n", .{time_with_profiling});
    std.debug.print("  开销: {d} ns ({d:.2}%)\n", .{ overhead, overhead_percent });
    
    // 验证开销在合理范围内 (< 5%)
    try testing.expect(overhead_percent < 5.0);
}

test "多层嵌套函数剖析" {
    const allocator = testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    const TestFunc = struct {
        fn level1(prof: *Profiler) !void {
            try prof.enterFunction("level1");
            defer prof.exitFunction("level1") catch {};
            
            try level2(prof);
            try level2(prof);
        }
        
        fn level2(prof: *Profiler) !void {
            try prof.enterFunction("level2");
            defer prof.exitFunction("level2") catch {};
            
            try level3(prof);
        }
        
        fn level3(prof: *Profiler) !void {
            try prof.enterFunction("level3");
            defer prof.exitFunction("level3") catch {};
            
            var sum: u64 = 0;
            var i: u64 = 0;
            while (i < 100) : (i += 1) {
                sum += i;
            }
        }
    };
    
    try TestFunc.level1(&profiler);
    
    // 验证统计
    const level1_stats = profiler.getFunctionStats("level1");
    const level2_stats = profiler.getFunctionStats("level2");
    const level3_stats = profiler.getFunctionStats("level3");
    
    try testing.expect(level1_stats != null);
    try testing.expect(level2_stats != null);
    try testing.expect(level3_stats != null);
    
    try testing.expectEqual(@as(u64, 1), level1_stats.?.call_count);
    try testing.expectEqual(@as(u64, 2), level2_stats.?.call_count);
    try testing.expectEqual(@as(u64, 2), level3_stats.?.call_count);
}
