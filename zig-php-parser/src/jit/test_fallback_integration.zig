/// JIT 编译失败回退机制的集成测试
/// 
/// 本测试验证回退机制与 JIT 编译器的完整集成

const std = @import("std");
const testing = std.testing;
const Compiler = @import("compiler.zig").Compiler;
const FallbackManager = @import("fallback.zig").FallbackManager;
const CodeCache = @import("code_cache.zig").CodeCache;

// 集成测试：编译器与回退管理器协同工作
test "Compiler and FallbackManager integration" {
    var fallback_manager = FallbackManager.init(testing.allocator);
    defer fallback_manager.deinit();
    
    // 启用详细日志用于调试
    fallback_manager.setVerbose(false);
    
    // 创建编译器并关联回退管理器
    var compiler = Compiler.initWithFallback(testing.allocator, &fallback_manager);
    defer fast_compiler.deinit();
    
    // 验证编译器正确关联了回退管理器
    try testing.expect(compiler.fallback_manager != null);
    
    // 验证初始状态
    try testing.expectEqual(@as(usize, 0), fallback_manager.getFallbackCount());
}

// 集成测试：回退管理器统计功能
test "FallbackManager statistics tracking" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    // 模拟多次编译失败
    const test_cases = [_]struct {
        name: []const u8,
        err: anyerror,
        msg: []const u8,
    }{
        .{ .name = "func1", .err = error.UnsupportedInstruction, .msg = "不支持的指令" },
        .{ .name = "func2", .err = error.RegisterAllocationFailed, .msg = "寄存器分配失败" },
        .{ .name = "func3", .err = error.CodeGenerationFailed, .msg = "代码生成失败" },
        .{ .name = "func4", .err = error.UnsupportedInstruction, .msg = "另一个不支持的指令" },
    };
    
    for (test_cases) |case| {
        _ = try manager.handleCompilationFailure(case.name, case.err, case.msg, null);
    }
    
    // 验证统计信息
    const stats = manager.getStatistics();
    try testing.expectEqual(@as(usize, 4), stats.total_failures);
    try testing.expectEqual(@as(usize, 2), stats.unsupported_instruction_count);
    try testing.expectEqual(@as(usize, 1), stats.register_allocation_failures);
    try testing.expectEqual(@as(usize, 1), stats.code_generation_failures);
    try testing.expectEqual(@as(usize, 4), manager.getFallbackCount());
}

// 集成测试：回退可以被动态启用/禁用
test "Dynamic fallback enable/disable" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    // 初始状态：回退启用
    var should_fallback = try manager.handleCompilationFailure(
        "test1",
        error.CompilationFailed,
        "测试1",
        null,
    );
    try testing.expect(should_fallback);
    
    // 禁用回退
    manager.setFallbackEnabled(false);
    should_fallback = try manager.handleCompilationFailure(
        "test2",
        error.CompilationFailed,
        "测试2",
        null,
    );
    try testing.expect(!should_fallback);
    
    // 重新启用回退
    manager.setFallbackEnabled(true);
    should_fallback = try manager.handleCompilationFailure(
        "test3",
        error.CompilationFailed,
        "测试3",
        null,
    );
    try testing.expect(should_fallback);
    
    // 验证所有失败都被记录
    const stats = manager.getStatistics();
    try testing.expectEqual(@as(usize, 3), stats.total_failures);
}

// 性能测试：大量失败的处理性能
test "Performance with many failures" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    const num_failures: usize = 10000;
    var timer = try std.time.Timer.start();
    
    var i: usize = 0;
    while (i < num_failures) : (i += 1) {
        _ = try manager.handleCompilationFailure(
            "perf_test",
            error.CompilationFailed,
            "性能测试",
            null,
        );
    }
    
    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / num_failures;
    
    std.debug.print("\n大量失败处理性能: {d} ns/op ({d} 次失败)\n", .{ ns_per_op, num_failures });
    
    // 验证性能合理（应该 < 10 微秒/操作）
    try testing.expect(ns_per_op < 10_000);
    
    // 验证统计正确
    const stats = manager.getStatistics();
    try testing.expectEqual(num_failures, stats.total_failures);
}

// 内存测试：确保没有内存泄漏
test "No memory leaks in failure handling" {
    var manager = FallbackManager.init(testing.allocator);
    defer manager.deinit();
    
    // 记录大量失败
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try manager.handleCompilationFailure(
            "leak_test",
            error.CompilationFailed,
            "内存泄漏测试",
            null,
        );
    }
    
    // 清除统计
    manager.resetStatistics();
    
    // 验证统计被清空
    const stats = manager.getStatistics();
    try testing.expectEqual(@as(usize, 0), stats.total_failures);
    try testing.expectEqual(@as(usize, 0), manager.getFallbackCount());
    
    // 如果有内存泄漏，testing.allocator 会在 deinit 时报错
}
