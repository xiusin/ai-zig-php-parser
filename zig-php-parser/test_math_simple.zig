const std = @import("std");
const MathBenchmark = @import("src/benchmark/math_benchmark.zig").MathBenchmark;
const MathBenchmarkConfig = @import("src/benchmark/math_benchmark.zig").MathBenchmarkConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = MathBenchmarkConfig{
        .iterations = 10_000,
        .verbose = true,
        .generate_php_scripts = false,
    };
    
    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();
    
    std.debug.print("运行整数加法测试...\n", .{});
    const result = try benchmark.testIntegerAddition();
    
    std.debug.print("测试完成！\n", .{});
    std.debug.print("  操作数/秒: {d:.2} M ops/s\n", .{result.operations_per_second / 1_000_000.0});
    std.debug.print("  总时间: {d:.2} ms\n", .{@as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0});
}
