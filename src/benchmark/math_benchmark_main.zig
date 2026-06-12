//! 数学运算性能测试主程序
//!
//! 运行完整的数学运算性能测试套件并生成报告

const std = @import("std");
const MathBenchmark = @import("math_benchmark.zig").MathBenchmark;
const MathBenchmarkConfig = @import("math_benchmark.zig").MathBenchmarkConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 解析命令行参数
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    _ = args.skip(); // 跳过程序名
    
    var iterations: u32 = 100_000;
    var verbose = false;
    var generate_scripts = true;
    var output_path: []const u8 = "math_benchmark_report.md";
    
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--iterations")) {
            if (args.next()) |iter_str| {
                iterations = try std.fmt.parseInt(u32, iter_str, 10);
            }
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--no-scripts")) {
            generate_scripts = false;
        } else if (std.mem.eql(u8, arg, "--output")) {
            if (args.next()) |path| {
                output_path = path;
            }
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printHelp();
            return;
        }
    }
    
    // 创建配置
    const config = MathBenchmarkConfig{
        .iterations = iterations,
        .verbose = verbose,
        .generate_php_scripts = generate_scripts,
    };
    
    // 运行测试
    std.debug.print("初始化数学运算性能测试...\n", .{});
    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();
    
    std.debug.print("运行测试套件...\n", .{});
    const result = try benchmark.runAllTests();
    
    defer allocator.free(result.integer_results);
    defer allocator.free(result.float_results);
    defer allocator.free(result.math_func_results);
    defer allocator.free(result.complex_results);
    defer allocator.free(result.matrix_results);
    
    // 生成报告
    std.debug.print("生成报告: {s}\n", .{output_path});
    try benchmark.generateReport(result, output_path);
    
    // 打印摘要
    std.debug.print("\n╔════════════════════════════════════════╗\n", .{});
    std.debug.print("║  测试完成                              ║\n", .{});
    std.debug.print("╚════════════════════════════════════════╝\n", .{});
    std.debug.print("\n测试统计:\n", .{});
    std.debug.print("  整数运算测试: {d} 项\n", .{result.integer_results.len});
    std.debug.print("  浮点运算测试: {d} 项\n", .{result.float_results.len});
    std.debug.print("  数学函数测试: {d} 项\n", .{result.math_func_results.len});
    std.debug.print("  复数运算测试: {d} 项\n", .{result.complex_results.len});
    std.debug.print("  矩阵运算测试: {d} 项\n", .{result.matrix_results.len});
    std.debug.print("  总测试时间: {d:.2} 秒\n", .{
        @as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000_000.0
    });
    std.debug.print("\n报告已保存到: {s}\n", .{output_path});
}

fn printHelp() !void {
    std.debug.print(
        \\数学运算性能测试
        \\
        \\用法: math_benchmark [选项]
        \\
        \\选项:
        \\  --iterations <N>    设置迭代次数 (默认: 100000)
        \\  --verbose           启用详细输出
        \\  --no-scripts        不生成 PHP 测试脚本
        \\  --output <path>     设置报告输出路径 (默认: math_benchmark_report.md)
        \\  --help              显示此帮助信息
        \\
        \\示例:
        \\  math_benchmark --iterations 50000 --verbose
        \\  math_benchmark --output results/report.md
        \\
    , .{});
}
