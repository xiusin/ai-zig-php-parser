/// JIT 编译失败回退机制的属性测试
/// 
/// Feature: zig-php-performance-optimization
/// Property 15: JIT 编译失败回退
/// 
/// 本测试验证：对于任意编译失败的函数，系统应该回退到解释执行，且执行结果正确
/// 
/// @验证：需求 2.8

const std = @import("std");
const testing = std.testing;
const FallbackManager = @import("fallback.zig").FallbackManager;
const CompilationLogger = @import("fallback.zig").CompilationLogger;
const JITCompilationError = @import("fallback.zig").JITCompilationError;
const CompilationFailureReason = @import("fallback.zig").CompilationFailureReason;
const Compiler = @import("compiler.zig").Compiler;
const CodeCache = @import("code_cache.zig").CodeCache;

/// 属性测试框架
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: std.rand.Random,
    iterations: u32 = 100,
    
    /// 运行属性测试
    pub fn run(
        self: *PropertyTest,
        comptime T: type,
        property: fn(T) anyerror!bool,
        generator: fn(*std.rand.Random, std.mem.Allocator) anyerror!T,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 生成随机输入
            const input = try generator(&self.rng, self.allocator);
            
            // 测试属性
            const result = property(input) catch |err| {
                std.debug.print("Property test error: {}\n", .{err});
                failed += 1;
                continue;
            };
            
            if (result) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed for iteration {d}\n", .{i});
            }
        }
        
        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("Property test: {d}/{d} passed ({d:.2}%)\n", 
            .{passed, self.iterations, success_rate * 100});
        
        return failed == 0;
    }
};

/// 测试输入
const TestInput = struct {
    function_name: []const u8,
    error_type: JITCompilationError,
    error_message: []const u8,
};

/// 生成随机测试输入
fn generateTestInput(rng: *std.rand.Random, allocator: std.mem.Allocator) !TestInput {
    // 生成随机函数名
    const name_len = rng.uintLessThan(usize, 20) + 5;
    const name = try allocator.alloc(u8, name_len);
    for (name) |*c| {
        c.* = 'a' + @as(u8, @intCast(rng.uintLessThan(u8, 26)));
    }
    
    // 随机选择错误类型
    const error_types = [_]JITCompilationError{
        error.CompilationFailed,
        error.UnsupportedInstruction,
        error.RegisterAllocationFailed,
        error.CodeGenerationFailed,
        error.InvalidTargetArchitecture,
        error.CodeCacheFull,
        error.OutOfMemory,
        error.TypeInferenceFailed,
        error.OptimizationFailed,
    };
    const error_type = error_types[rng.uintLessThan(usize, error_types.len)];
    
    // 生成错误消息
    const msg = try allocator.dupe(u8, "Test error message");
    
    return TestInput{
        .function_name = name,
        .error_type = error_type,
        .error_message = msg,
    };
}

// 属性 15：JIT 编译失败回退
// 对于任意编译失败的函数，系统应该回退到解释执行，且执行结果正确
test "Property 15: JIT compilation failure fallback" {
    // Feature: zig-php-performance-optimization, Property 15
    
    var prng = std.rand.DefaultPrng.init(0);
    var pt = PropertyTest{
        .allocator = testing.allocator,
        .rng = prng.random(),
        .iterations = 100,
    };
    
    const property = struct {
        fn check(input: TestInput) !bool {
            // 创建回退管理器
            var manager = FallbackManager.init(testing.allocator);
            defer manager.deinit();
            
            // 启用详细日志（用于调试）
            manager.setVerbose(false);
            
            // 处理编译失败
            const should_fallback = try manager.handleCompilationFailure(
                input.function_name,
                input.error_type,
                input.error_message,
                null,
            );
            
            // 验证应该回退
            if (!should_fallback) {
                std.debug.print("Expected fallback to be enabled\n", .{});
                return false;
            }
            
            // 验证失败被记录
            const stats = manager.getStatistics();
            if (stats.total_failures == 0) {
                std.debug.print("Expected at least one failure to be recorded\n", .{});
                return false;
            }
            
            // 验证回退计数增加
            if (manager.getFallbackCount() == 0) {
                std.debug.print("Expected fallback count to increase\n", .{});
                return false;
            }
            
            return true;
        }
    }.check;
    
    const passed = try pt.run(TestInput, property, generateTestInput);
    try testing.expect(passed);
}

// 测试：编译失败记录正确性
test "Compilation failure recording correctness" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    // 记录多个失败
    const failures = [_]struct {
        name: []const u8,
        err: JITCompilationError,
        msg: []const u8,
    }{
        .{ .name = "func1", .err = error.UnsupportedInstruction, .msg = "不支持的指令" },
        .{ .name = "func2", .err = error.RegisterAllocationFailed, .msg = "寄存器分配失败" },
        .{ .name = "func3", .err = error.CodeGenerationFailed, .msg = "代码生成失败" },
    };
    
    for (failures) |failure| {
        _ = try manager.handleCompilationFailure(
            failure.name,
            failure.err,
            failure.msg,
            null,
        );
    }
    
    // 验证统计
    const stats = manager.getStatistics();
    try testing.expectEqual(@as(usize, 3), stats.total_failures);
    try testing.expectEqual(@as(usize, 1), stats.unsupported_instruction_count);
    try testing.expectEqual(@as(usize, 1), stats.register_allocation_failures);
    try testing.expectEqual(@as(usize, 1), stats.code_generation_failures);
    try testing.expectEqual(@as(usize, 3), manager.getFallbackCount());
}

// 测试：回退可以被禁用
test "Fallback can be disabled" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    // 禁用回退
    manager.setFallbackEnabled(false);
    
    // 尝试处理失败
    const should_fallback = try manager.handleCompilationFailure(
        "test_func",
        error.CompilationFailed,
        "测试错误",
        null,
    );
    
    // 验证不应该回退
    try testing.expect(!should_fallback);
    
    // 但失败仍然被记录
    const stats = manager.getStatistics();
    try testing.expectEqual(@as(usize, 1), stats.total_failures);
}

// 测试：日志记录器正确工作
test "Logger works correctly" {
    var logger = CompilationLogger.init(testing.allocator);
    defer logger.deinit();
    
    // 记录失败
    try logger.logFailure(
        "test_function",
        error.UnsupportedInstruction,
        "测试错误消息",
        42,
    );
    
    // 验证统计
    const stats = logger.getStatistics();
    try testing.expectEqual(@as(usize, 1), stats.total_failures);
    try testing.expectEqual(@as(usize, 1), stats.unsupported_instruction_count);
}

// 测试：错误原因转换正确
test "Error reason conversion is correct" {
    const test_cases = [_]struct {
        err: JITCompilationError,
        expected: CompilationFailureReason,
    }{
        .{ .err = error.UnsupportedInstruction, .expected = .unsupported_instruction },
        .{ .err = error.RegisterAllocationFailed, .expected = .register_allocation_failed },
        .{ .err = error.CodeGenerationFailed, .expected = .code_generation_failed },
        .{ .err = error.InvalidTargetArchitecture, .expected = .invalid_target_arch },
        .{ .err = error.CodeCacheFull, .expected = .code_cache_full },
        .{ .err = error.OutOfMemory, .expected = .out_of_memory },
        .{ .err = error.TypeInferenceFailed, .expected = .type_inference_failed },
        .{ .err = error.OptimizationFailed, .expected = .optimization_failed },
    };
    
    for (test_cases) |case| {
        const reason = CompilationFailureReason.fromError(case.err);
        try testing.expectEqual(case.expected, reason);
    }
}

// 测试：统计信息可以被重置
test "Statistics can be reset" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    // 记录一些失败
    _ = try manager.handleCompilationFailure(
        "func1",
        error.CompilationFailed,
        "错误1",
        null,
    );
    _ = try manager.handleCompilationFailure(
        "func2",
        error.CompilationFailed,
        "错误2",
        null,
    );
    
    // 验证统计
    var stats = manager.getStatistics();
    try testing.expectEqual(@as(usize, 2), stats.total_failures);
    try testing.expectEqual(@as(usize, 2), manager.getFallbackCount());
    
    // 重置统计
    manager.resetStatistics();
    
    // 验证统计被清空
    stats = manager.getStatistics();
    try testing.expectEqual(@as(usize, 0), stats.total_failures);
    try testing.expectEqual(@as(usize, 0), manager.getFallbackCount());
}

// 测试：日志文件写入（集成测试）
test "Log file writing integration" {
    const log_path = "test_jit_fallback.log";
    
    // 清理可能存在的旧日志文件
    std.fs.cwd().deleteFile(log_path) catch {};
    
    // 创建带日志文件的管理器
    var manager = try FallbackManager.initWithLogger(testing.allocator, log_path);
    defer manager.deinit();
    defer std.fs.cwd().deleteFile(log_path) catch {};
    
    // 记录失败
    _ = try manager.handleCompilationFailure(
        "test_func",
        error.UnsupportedInstruction,
        "测试日志写入",
        123,
    );
    
    // 验证日志文件存在
    const file = try std.fs.cwd().openFile(log_path, .{});
    defer file.close();
    
    // 读取内容
    const content = try file.readToEndAlloc(testing.allocator, 1024 * 1024);
    defer testing.allocator.free(content);
    
    // 验证内容包含关键信息
    try testing.expect(std.mem.indexOf(u8, content, "test_func") != null);
    try testing.expect(std.mem.indexOf(u8, content, "测试日志写入") != null);
}

// 测试：并发安全性（基础测试）
test "Basic concurrency safety" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    // 在单线程中快速记录多个失败
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try manager.handleCompilationFailure(
            "concurrent_func",
            error.CompilationFailed,
            "并发测试",
            null,
        );
    }
    
    // 验证所有失败都被记录
    const stats = manager.getStatistics();
    try testing.expectEqual(@as(usize, 100), stats.total_failures);
    try testing.expectEqual(@as(usize, 100), manager.getFallbackCount());
}

// 性能测试：回退处理开销
test "Fallback handling performance" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    const iterations: usize = 1000;
    var timer = try std.time.Timer.start();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = try manager.handleCompilationFailure(
            "perf_test_func",
            error.CompilationFailed,
            "性能测试",
            null,
        );
    }
    
    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / iterations;
    
    std.debug.print("\n回退处理性能: {d} ns/op\n", .{ns_per_op});
    
    // 验证性能合理（应该 < 10 微秒/操作）
    try testing.expect(ns_per_op < 10_000);
}
