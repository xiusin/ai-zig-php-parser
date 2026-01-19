// 字符串基准测试运行器
// 运行所有 80+ 字符串函数的性能测试

const std = @import("std");
const StringBenchmark = @import("string_benchmark").StringBenchmark;
const StringBenchmarkConfig = @import("string_benchmark").StringBenchmarkConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("           字符串操作性能测试 - Zig-PHP vs 原生 PHP\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
    
    // 配置测试
    const config = StringBenchmarkConfig{
        .iterations = 10_000,
        .verbose = true,
        .generate_php_scripts = true,
        .script_output_dir = "tests/benchmarks/string",
    };
    
    // 初始化测试
    var benchmark = try StringBenchmark.init(allocator, config);
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
    printCategoryResults("字符串查找与替换", results.search_results);
    printCategoryResults("字符串转换", results.transform_results);
    printCategoryResults("字符串分割与连接", results.split_results);
    printCategoryResults("字符串比较", results.compare_results);
    printCategoryResults("字符串修剪", results.trim_results);
    printCategoryResults("字符串编码", results.encode_results);
    printCategoryResults("字符串格式化", results.format_results);
    printCategoryResults("字符串解析", results.parse_results);
    
    // 打印总结
    const total_tests = results.search_results.len + 
                       results.transform_results.len +
                       results.split_results.len +
                       results.compare_results.len +
                       results.trim_results.len +
                       results.encode_results.len +
                       results.format_results.len +
                       results.parse_results.len;
    
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
    try generateJsonReport(allocator, results, "tests/benchmarks/string_benchmark_results.json");
    std.debug.print("JSON 报告已生成: tests/benchmarks/string_benchmark_results.json\n", .{});
    std.debug.print("\n", .{});
    
    std.debug.print("提示: 运行 PHP 脚本进行对比:\n", .{});
    std.debug.print("  cd tests/benchmarks/string && php strlen.php\n", .{});
    std.debug.print("\n", .{});
}

fn printCategoryResults(category_name: []const u8, results: []const @import("string_benchmark").StringOpResult) void {
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
    results: @import("string_benchmark").StringBenchmarkResult,
    output_path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    
    // 使用 allocPrint 生成 JSON 字符串
    const json_content = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "timestamp": {d},
        \\  "total_time_ns": {d},
        \\  "search_results": [],
        \\  "transform_results": [],
        \\  "split_results": [],
        \\  "compare_results": [],
        \\  "trim_results": [],
        \\  "encode_results": [],
        \\  "format_results": [],
        \\  "parse_results": []
        \\}}
        \\
    , .{results.timestamp, results.total_time_ns});
    defer allocator.free(json_content);
    
    try file.writeAll(json_content);
}
