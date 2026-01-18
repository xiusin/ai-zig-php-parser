/// 热点检测器演示程序
/// 
/// 展示如何使用热点检测器来识别频繁执行的函数和循环
const std = @import("std");
const jit = @import("../src/jit/root.zig");
const HotspotDetector = jit.HotspotDetector;
const HotspotConfig = jit.HotspotConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== 热点检测器演示 ===\n\n", .{});
    
    // 创建热点检测器
    var config = HotspotConfig{};
    config.function_threshold = 100;
    config.loop_backedge_threshold = 1000;
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    std.debug.print("配置:\n", .{});
    std.debug.print("  函数热点阈值: {d}\n", .{config.function_threshold});
    std.debug.print("  循环热点阈值: {d}\n\n", .{config.loop_backedge_threshold});
    
    // 模拟程序执行
    std.debug.print("模拟程序执行...\n\n", .{});
    
    // 场景 1: 频繁调用的函数
    std.debug.print("场景 1: 模拟频繁调用的函数\n", .{});
    var i: u32 = 0;
    while (i < 150) : (i += 1) {
        try detector.recordExecution("calculate_sum");
        
        // 每 50 次检查一次
        if ((i + 1) % 50 == 0) {
            const is_hot = detector.isHotspot("calculate_sum");
            const count = detector.getExecutionCount("calculate_sum");
            std.debug.print("  执行 {d} 次后: 计数={d}, 热点={s}\n", .{
                i + 1,
                count,
                if (is_hot) "是" else "否",
            });
        }
    }
    std.debug.print("\n", .{});
    
    // 场景 2: 不同频率的函数
    std.debug.print("场景 2: 模拟不同频率的函数调用\n", .{});
    const functions = [_]struct { name: []const u8, count: u32 }{
        .{ .name = "hot_function", .count = 200 },
        .{ .name = "warm_function", .count = 80 },
        .{ .name = "cold_function", .count = 10 },
    };
    
    for (functions) |func| {
        var j: u32 = 0;
        while (j < func.count) : (j += 1) {
            try detector.recordExecution(func.name);
        }
        
        const is_hot = detector.isHotspot(func.name);
        std.debug.print("  {s}: {d} 次调用, 热点={s}\n", .{
            func.name,
            func.count,
            if (is_hot) "是" else "否",
        });
    }
    std.debug.print("\n", .{});
    
    // 场景 3: 循环热点检测
    std.debug.print("场景 3: 模拟循环执行\n", .{});
    const loop_iterations: u32 = 1500;
    var k: u32 = 0;
    while (k < loop_iterations) : (k += 1) {
        try detector.recordLoopBackedge("process_data", 42);
        
        if ((k + 1) % 500 == 0) {
            const is_hot = detector.isLoopHotspot("process_data", 42);
            const count = detector.getLoopBackedgeCount("process_data", 42);
            std.debug.print("  循环回边 {d} 次后: 计数={d}, 热点={s}\n", .{
                k + 1,
                count,
                if (is_hot) "是" else "否",
            });
        }
    }
    std.debug.print("\n", .{});
    
    // 打印最终统计
    detector.printStats();
    
    // 性能测试
    std.debug.print("\n=== 性能测试 ===\n", .{});
    const perf_iterations: u32 = 100000;
    var timer = try std.time.Timer.start();
    
    var m: u32 = 0;
    while (m < perf_iterations) : (m += 1) {
        try detector.recordExecution("perf_test");
    }
    
    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / perf_iterations;
    const ops_per_sec = 1_000_000_000 / ns_per_op;
    
    std.debug.print("记录 {d} 次执行耗时: {d} ms\n", .{
        perf_iterations,
        elapsed_ns / 1_000_000,
    });
    std.debug.print("平均每次操作: {d} ns\n", .{ns_per_op});
    std.debug.print("吞吐量: {d} ops/sec\n", .{ops_per_sec});
    
    std.debug.print("\n演示完成！\n", .{});
}
