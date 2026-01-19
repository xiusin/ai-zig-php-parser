//! JIT 性能测试运行器
//!
//! 演示如何使用 JIT 性能测试框架进行完整的性能测试

const std = @import("std");
const JITBenchmark = @import("../../src/benchmark/jit_benchmark.zig").JITBenchmark;
const JITBenchmarkConfig = @import("../../src/benchmark/jit_benchmark.zig").JITBenchmarkConfig;
const TestScenarioConfig = @import("../../src/benchmark/jit_benchmark.zig").TestScenarioConfig;
const TestScenario = @import("../../src/benchmark/jit_benchmark.zig").TestScenario;
const ReportFormat = @import("../../src/benchmark/jit_benchmark.zig").ReportFormat;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 配置 JIT 性能测试
    const config = JITBenchmarkConfig{
        .warmup_iterations = 10,
        .test_iterations = 100,
        .verbose = true,
        .code_cache_size = 1024 * 1024, // 1MB
    };
    
    // 初始化测试框架
    const benchmark = try JITBenchmark.init(allocator, config);
    defer benchmark.deinit();
    
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("JIT 性能测试套件\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});
    
    // 定义测试场景
    const scenarios = [_]TestScenarioConfig{
        .{
            .name = "简单函数",
            .scenario = .simple_function,
        },
        .{
            .name = "循环密集型 (1000次)",
            .scenario = .loop_intensive,
            .loop_count = 1000,
        },
        .{
            .name = "循环密集型 (10000次)",
            .scenario = .loop_intensive,
            .loop_count = 10000,
        },
        .{
            .name = "数学计算密集型",
            .scenario = .math_intensive,
        },
        .{
            .name = "条件分支密集型",
            .scenario = .branch_intensive,
        },
    };
    
    // 运行批量测试
    const results = try benchmark.runBatchTests(&scenarios);
    defer allocator.free(results);
    
    // 生成汇总报告
    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("测试汇总\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});
    
    var total_speedup: f64 = 0;
    var total_memory_overhead: f64 = 0;
    var successful_tests: u32 = 0;
    
    for (results) |result| {
        if (result.compile_stats.success) {
            total_speedup += result.speedup;
            total_memory_overhead += result.memory_overhead;
            successful_tests += 1;
        }
    }
    
    const avg_speedup = if (successful_tests > 0)
        total_speedup / @as(f64, @floatFromInt(successful_tests))
    else
        0.0;
    
    const avg_memory_overhead = if (successful_tests > 0)
        total_memory_overhead / @as(f64, @floatFromInt(successful_tests))
    else
        0.0;
    
    std.debug.print("总测试数: {d}\n", .{scenarios.len});
    std.debug.print("成功测试: {d}\n", .{successful_tests});
    std.debug.print("平均加速比: {d:.2}x\n", .{avg_speedup});
    std.debug.print("平均内存开销: {d:.1}%\n\n", .{avg_memory_overhead * 100});
    
    // 生成详细报告
    std.debug.print("生成详细报告...\n", .{});
    
    for (results, 0..) |result, i| {
        // Markdown 报告
        const md_filename = try std.fmt.allocPrint(
            allocator,
            "jit_benchmark_{d}_{s}.md",
            .{i, result.test_name},
        );
        defer allocator.free(md_filename);
        
        try benchmark.generateReport(result, md_filename, .markdown);
        std.debug.print("  ✓ {s}\n", .{md_filename});
        
        // JSON 报告
        const json_filename = try std.fmt.allocPrint(
            allocator,
            "jit_benchmark_{d}_{s}.json",
            .{i, result.test_name},
        );
        defer allocator.free(json_filename);
        
        try benchmark.generateReport(result, json_filename, .json);
        std.debug.print("  ✓ {s}\n", .{json_filename});
    }
    
    std.debug.print("\n测试完成！\n", .{});
}
