// 数组基准测试运行器
// 运行所有 60+ 数组函数的性能测试

const std = @import("std");
const ArrayBenchmark = @import("array_benchmark").ArrayBenchmark;
const ArrayBenchmarkConfig = @import("array_benchmark").ArrayBenchmarkConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("           数组操作性能测试 - Zig-PHP vs 原生 PHP\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
    
    // 配置测试
    const config = ArrayBenchmarkConfig{
        .iterations = 5_000,
        .verbose = true,
        .generate_php_scripts = true,
        .script_output_dir = "tests/benchmarks/array",
    };
    
    // 初始化测试
    var benchmark = try ArrayBenchmark.init(allocator, config);
    defer benchmark.deinit();
    
    std.debug.print("配置:\n", .{});
    std.debug.print("  迭代次数: {d}\n", .{config.iterations});
    std.debug.print("  生成 PHP 脚本: {}\n", .{config.generate_php_scripts});
    std.debug.print("  脚本输出目录: {s}\n", .{config.script_output_dir});
    std.debug.print("\n", .{});
    
    // 运行所有测试
    const start_time = std.time.milliTimestamp();
    const results = try benchmark.runAllTests();
    const end_time = std.time.milliTimestamp();
    
    // 打印结果
    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("                           测试结果\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});

    
    // 按类别打印结果
    printCategoryResults("数组创建与初始化", results.creation_results);
    printCategoryResults("数组访问与修改", results.access_results);
    printCategoryResults("数组搜索", results.search_results);
    printCategoryResults("数组排序", results.sort_results);
    printCategoryResults("数组过滤与映射", results.filter_results);
    printCategoryResults("数组合并与分割", results.merge_results);
    printCategoryResults("数组统计", results.stats_results);
    printCategoryResults("数组键值操作", results.key_results);
    printCategoryResults("数组集合操作", results.set_results);
    printCategoryResults("其他数组操作", results.misc_results);
    
    // 打印总结
    const total_tests = results.creation_results.len + 
                       results.access_results.len +
                       results.search_results.len +
                       results.sort_results.len +
                       results.filter_results.len +
                       results.merge_results.len +
                       results.stats_results.len +
                       results.key_results.len +
                       results.set_results.len +
                       results.misc_results.len;
    
    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("                           总结\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("总测试数: {d}\n", .{total_tests});
    std.debug.print("总耗时: {d} ms\n", .{end_time - start_time});
    std.debug.print("平均耗时: {d:.2} ms/测试\n", .{@as(f64, @floatFromInt(end_time - start_time)) / @as(f64, @floatFromInt(total_tests))});
    std.debug.print("\n", .{});
    
    // 生成 JSON 报告
    try generateJsonReport(allocator, results, "tests/benchmarks/array_benchmark_results.json");
    std.debug.print("JSON 报告已生成: tests/benchmarks/array_benchmark_results.json\n", .{});
    std.debug.print("\n", .{});
    
    std.debug.print("提示: 运行 PHP 脚本进行对比:\n", .{});
    std.debug.print("  cd tests/benchmarks/array && php array_push.php\n", .{});
    std.debug.print("\n", .{});
}

fn printCategoryResults(category_name: []const u8, results: []const @import("array_benchmark").ArrayOpResult) void {
    if (results.len == 0) return;
    
    std.debug.print("\n{s}:\n", .{category_name});
    std.debug.print("--------------------------------------------------------------------------------\n", .{});
    
    for (results) |result| {
        std.debug.print("  {s:<30} {d:>10.2} M ops/s  {d:>10.2} ms\n", .{
            result.test_name,
            result.operations_per_second / 1_000_000.0,
            @as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0,
        });
    }
}


fn generateJsonReport(
    allocator: std.mem.Allocator,
    results: @import("array_benchmark").ArrayBenchmarkResult,
    output_path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    
    // 使用 allocPrint 生成 JSON 字符串
    const json_content = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "timestamp": {d},
        \\  "total_time_ns": {d},
        \\  "creation_results": [],
        \\  "access_results": [],
        \\  "search_results": [],
        \\  "sort_results": [],
        \\  "filter_results": [],
        \\  "merge_results": [],
        \\  "stats_results": [],
        \\  "key_results": [],
        \\  "set_results": [],
        \\  "misc_results": []
        \\}}
        \\
    , .{results.timestamp, results.total_time_ns});
    defer allocator.free(json_content);
    
    try file.writeAll(json_content);
}
