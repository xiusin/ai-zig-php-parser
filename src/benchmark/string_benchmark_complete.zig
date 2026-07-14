// 完整的字符串基准测试 - 补充主文件缺失的方法

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringBenchmark = @import("string_benchmark.zig").StringBenchmark;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

// 导入辅助测试模块
const transforms = @import("string_benchmark_transforms.zig");
const splits = @import("string_benchmark_split.zig");
const misc = @import("string_benchmark_misc.zig");

/// 为 StringBenchmark 添加缺失的测试方法
pub fn addMissingMethods() void {
    // 这个文件提供了所有缺失测试方法的实现
}

/// 运行转换测试的实现
pub fn runTransformTests(benchmark: *StringBenchmark) ![]StringOpResult {
    var transform_tests = transforms.StringTransformTests{
        .allocator = benchmark.allocator,
        .iterations = benchmark.config.iterations,
        .verbose = benchmark.config.verbose,
        .generate_php_scripts = benchmark.config.generate_php_scripts,
        .script_output_dir = benchmark.config.script_output_dir,
    };

    return try transform_tests.runAll();
}

/// 运行分割测试的实现
pub fn runSplitTests(benchmark: *StringBenchmark) ![]StringOpResult {
    var split_tests = splits.StringSplitTests{
        .allocator = benchmark.allocator,
        .iterations = benchmark.config.iterations,
        .verbose = benchmark.config.verbose,
    };

    return try split_tests.runAll();
}

/// 运行比较测试的实现
pub fn runCompareTests(benchmark: *StringBenchmark) ![]StringOpResult {
    var compare_tests = misc.StringCompareTests{
        .allocator = benchmark.allocator,
        .iterations = benchmark.config.iterations,
        .verbose = benchmark.config.verbose,
    };

    return try compare_tests.runAll();
}

/// 运行修剪测试的实现
pub fn runTrimTests(benchmark: *StringBenchmark) ![]StringOpResult {
    var trim_tests = misc.StringTrimTests{
        .allocator = benchmark.allocator,
        .iterations = benchmark.config.iterations,
        .verbose = benchmark.config.verbose,
    };

    return try trim_tests.runAll();
}

/// 运行编码测试的实现
pub fn runEncodeTests(benchmark: *StringBenchmark) ![]StringOpResult {
    var encode_tests = misc.StringEncodeTests{
        .allocator = benchmark.allocator,
        .iterations = benchmark.config.iterations,
        .verbose = benchmark.config.verbose,
    };

    return try encode_tests.runAll();
}

/// 运行格式化测试的实现
pub fn runFormatTests(benchmark: *StringBenchmark) ![]StringOpResult {
    var format_tests = misc.StringFormatTests{
        .allocator = benchmark.allocator,
        .iterations = benchmark.config.iterations,
        .verbose = benchmark.config.verbose,
    };

    return try format_tests.runAll();
}

/// 运行解析测试的实现
pub fn runParseTests(benchmark: *StringBenchmark) ![]StringOpResult {
    var parse_tests = misc.StringParseTests{
        .allocator = benchmark.allocator,
        .iterations = benchmark.config.iterations,
        .verbose = benchmark.config.verbose,
    };

    return try parse_tests.runAll();
}

/// 生成 PHP 测试脚本的辅助函数
pub fn generatePhpScript(benchmark: *StringBenchmark, test_name: []const u8, script_content: []const u8) !void {
    const file_path = try std.fmt.allocPrint(
        benchmark.allocator,
        "{s}/{s}.php",
        .{ benchmark.config.script_output_dir, test_name },
    );
    defer benchmark.allocator.free(file_path);

    const file = try std.fs.cwd.createFile(file_path, .{});
    defer file.close();

    try file.writeAll(script_content);
}
