//! 数学运算性能测试的单元测试

const std = @import("std");
const testing = std.testing;
const MathBenchmark = @import("math_benchmark.zig").MathBenchmark;
const MathBenchmarkConfig = @import("math_benchmark.zig").MathBenchmarkConfig;

test "MathBenchmark initialization" {
    const allocator = testing.allocator;

    const config = MathBenchmarkConfig{
        .iterations = 1000,
        .verbose = false,
        .generate_php_scripts = false,
    };

    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();

    try testing.expectEqual(@as(u32, 1000), benchmark.config.iterations);
    try testing.expect(!benchmark.config.verbose);
}

test "Integer operations - addition" {
    const allocator = testing.allocator;

    const config = MathBenchmarkConfig{
        .iterations = 10_000,
        .verbose = false,
        .generate_php_scripts = false,
    };

    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();

    const result = try benchmark.testIntegerAddition();

    try testing.expect(result.operations_per_second > 0);
    try testing.expectEqual(@as(u32, 10_000), result.iterations);
    try testing.expectEqualStrings("integer_addition", result.test_name);
}

test "Float operations - addition" {
    const allocator = testing.allocator;

    const config = MathBenchmarkConfig{
        .iterations = 10_000,
        .verbose = false,
        .generate_php_scripts = false,
    };

    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();

    const result = try benchmark.testFloatAddition();

    try testing.expect(result.operations_per_second > 0);
    try testing.expectEqual(@as(u32, 10_000), result.iterations);
}

test "Math functions - sqrt" {
    const allocator = testing.allocator;

    const config = MathBenchmarkConfig{
        .iterations = 10_000,
        .verbose = false,
        .generate_php_scripts = false,
    };

    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();

    const result = try benchmark.testMathSqrt();

    try testing.expect(result.operations_per_second > 0);
    try testing.expectEqual(@as(u32, 10_000), result.iterations);
}

test "Complex operations - addition" {
    const allocator = testing.allocator;

    const config = MathBenchmarkConfig{
        .iterations = 10_000,
        .verbose = false,
        .generate_php_scripts = false,
    };

    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();

    const result = try benchmark.testComplexAddition();

    try testing.expect(result.operations_per_second > 0);
    try testing.expectEqual(@as(u32, 10_000), result.iterations);
}

test "Matrix operations - addition" {
    const allocator = testing.allocator;

    const config = MathBenchmarkConfig{
        .iterations = 10_000,
        .verbose = false,
        .generate_php_scripts = false,
    };

    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();

    const result = try benchmark.testMatrixAddition();

    try testing.expect(result.operations_per_second > 0);
    try testing.expectEqual(@as(u32, 10_000), result.iterations);
}

test "Run all integer tests" {
    const allocator = testing.allocator;

    const config = MathBenchmarkConfig{
        .iterations = 1000,
        .verbose = false,
        .generate_php_scripts = false,
    };

    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();

    const results = try benchmark.runIntegerTests();
    defer allocator.free(results);

    try testing.expect(results.len > 0);
    for (results) |result| {
        try testing.expect(result.operations_per_second > 0);
    }
}

test "Run all tests" {
    const allocator = testing.allocator;

    const config = MathBenchmarkConfig{
        .iterations = 1000,
        .verbose = false,
        .generate_php_scripts = false,
    };

    var benchmark = try MathBenchmark.init(allocator, config);
    defer benchmark.deinit();

    const result = try benchmark.runAllTests();

    defer allocator.free(result.integer_results);
    defer allocator.free(result.float_results);
    defer allocator.free(result.math_func_results);
    defer allocator.free(result.complex_results);
    defer allocator.free(result.matrix_results);

    try testing.expect(result.integer_results.len > 0);
    try testing.expect(result.float_results.len > 0);
    try testing.expect(result.math_func_results.len > 0);
    try testing.expect(result.complex_results.len > 0);
    try testing.expect(result.matrix_results.len > 0);
    try testing.expect(result.total_time_ns > 0);
}
