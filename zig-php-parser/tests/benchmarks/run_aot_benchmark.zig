//! AOT 性能测试运行器
//!
//! 演示如何使用 AOT 性能测试框架

const std = @import("std");
const AOTBenchmark = @import("../../src/benchmark/aot_benchmark.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 初始化 AOT 性能测试框架
    var framework = try AOTBenchmark.AOTBenchmarkFramework.init(allocator, .{
        .warmup_iterations = 10,
        .test_iterations = 100,
        .timeout_ms = 60000,
        .verbose = true,
        .php_executable = "php",
        .aot_compiler = "./zig-php-aot",
        .temp_dir = "/tmp/aot_benchmark",
        .optimize_level = "ReleaseFast",
    });
    defer framework.deinit();
    
    std.debug.print("\n╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║          AOT 编译器性能测试框架                            ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n\n", .{});
    
    // 测试脚本列表
    const test_scripts = [_][]const u8{
        "examples/hello.php",
        "examples/arrays.php",
        "examples/functions.php",
    };
    
    // 运行测试
    for (test_scripts) |script| {
        std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
        std.debug.print("测试脚本: {s}\n", .{script});
        std.debug.print("=" ** 60 ++ "\n", .{});
        
        const result = framework.runFullBenchmark(script) catch |err| {
            std.debug.print("❌ 测试失败: {s}\n", .{@errorName(err)});
            continue;
        };
        
        // 生成报告
        const report_basename = std.fs.path.basename(script);
        const report_name = if (std.mem.lastIndexOf(u8, report_basename, ".")) |idx|
            report_basename[0..idx]
        else
            report_basename;
        
        // 生成 Markdown 报告
        const md_path = try std.fmt.allocPrint(
            allocator,
            "aot_report_{s}.md",
            .{report_name},
        );
        defer allocator.free(md_path);
        
        try framework.generateReport(result, md_path, .markdown);
        std.debug.print("\n✓ Markdown 报告已生成: {s}\n", .{md_path});
        
        // 生成 JSON 报告
        const json_path = try std.fmt.allocPrint(
            allocator,
            "aot_report_{s}.json",
            .{report_name},
        );
        defer allocator.free(json_path);
        
        try framework.generateReport(result, json_path, .json);
        std.debug.print("✓ JSON 报告已生成: {s}\n", .{json_path});
        
        // 生成 CSV 报告
        const csv_path = try std.fmt.allocPrint(
            allocator,
            "aot_report_{s}.csv",
            .{report_name},
        );
        defer allocator.free(csv_path);
        
        try framework.generateReport(result, csv_path, .csv);
        std.debug.print("✓ CSV 报告已生成: {s}\n", .{csv_path});
    }
    
    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("所有测试完成！\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});
}
