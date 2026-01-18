/// JIT 编译失败回退机制演示
/// 
/// 本示例展示如何使用 JIT 编译失败回退机制

const std = @import("std");
const Compiler = @import("../src/jit/compiler.zig").Compiler;
const FallbackManager = @import("../src/jit/fallback.zig").FallbackManager;
const CodeCache = @import("../src/jit/code_cache.zig").CodeCache;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== JIT 编译失败回退机制演示 ===\n\n", .{});
    
    // 1. 创建回退管理器（带日志文件）
    std.debug.print("1. 创建回退管理器...\n", .{});
    var fallback_manager = try FallbackManager.initWithLogger(
        allocator,
        "jit_fallback_demo.log"
    );
    defer fallback_manager.deinit();
    
    // 启用详细日志
    fallback_manager.setVerbose(true);
    std.debug.print("   ✓ 回退管理器已创建，日志文件: jit_fallback_demo.log\n\n", .{});
    
    // 2. 创建编译器并关联回退管理器
    std.debug.print("2. 创建 JIT 编译器...\n", .{});
    var compiler = Compiler.initWithFallback(allocator, &fallback_manager);
    defer compiler.deinit();
    std.debug.print("   ✓ JIT 编译器已创建并关联回退管理器\n\n", .{});
    
    // 3. 模拟编译失败场景
    std.debug.print("3. 模拟编译失败场景...\n", .{});
    
    const test_cases = [_]struct {
        name: []const u8,
        err: anyerror,
        msg: []const u8,
    }{
        .{
            .name = "calculate_fibonacci",
            .err = error.RegisterAllocationFailed,
            .msg = "函数过于复杂，寄存器不足",
        },
        .{
            .name = "process_simd_array",
            .err = error.UnsupportedInstruction,
            .msg = "遇到不支持的 AVX-512 指令",
        },
        .{
            .name = "optimize_hot_loop",
            .err = error.CodeGenerationFailed,
            .msg = "循环展开失败",
        },
        .{
            .name = "inline_recursive_call",
            .err = error.OptimizationFailed,
            .msg = "递归内联深度超过限制",
        },
    };
    
    for (test_cases, 0..) |case, i| {
        std.debug.print("   [{d}] 编译函数: {s}\n", .{ i + 1, case.name });
        
        const should_fallback = try fallback_manager.handleCompilationFailure(
            case.name,
            case.err,
            case.msg,
            null,
        );
        
        if (should_fallback) {
            std.debug.print("       → 编译失败，回退到解释执行\n", .{});
            std.debug.print("       → 原因: {s}\n", .{case.msg});
        }
    }
    
    std.debug.print("\n", .{});
    
    // 4. 显示统计信息
    std.debug.print("4. 编译失败统计信息:\n", .{});
    const stats = fallback_manager.getStatistics();
    
    std.debug.print("   总失败次数: {d}\n", .{stats.total_failures});
    std.debug.print("   回退次数: {d}\n", .{fallback_manager.getFallbackCount()});
    std.debug.print("\n   详细统计:\n", .{});
    std.debug.print("   - 不支持的指令: {d}\n", .{stats.unsupported_instruction_count});
    std.debug.print("   - 寄存器分配失败: {d}\n", .{stats.register_allocation_failures});
    std.debug.print("   - 代码生成失败: {d}\n", .{stats.code_generation_failures});
    std.debug.print("   - 优化失败: {d}\n", .{stats.optimization_failures});
    std.debug.print("\n", .{});
    
    // 5. 演示回退控制
    std.debug.print("5. 演示回退控制...\n", .{});
    
    // 禁用回退
    std.debug.print("   禁用回退机制\n", .{});
    fallback_manager.setFallbackEnabled(false);
    
    const should_fallback = try fallback_manager.handleCompilationFailure(
        "test_function",
        error.CompilationFailed,
        "测试编译失败",
        null,
    );
    
    if (!should_fallback) {
        std.debug.print("   ✓ 回退已禁用，编译失败将传播错误\n", .{});
    }
    
    // 重新启用回退
    std.debug.print("   重新启用回退机制\n", .{});
    fallback_manager.setFallbackEnabled(true);
    std.debug.print("   ✓ 回退已启用\n\n", .{});
    
    // 6. 性能测试
    std.debug.print("6. 性能测试...\n", .{});
    const iterations: usize = 10000;
    var timer = try std.time.Timer.start();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = try fallback_manager.handleCompilationFailure(
            "perf_test",
            error.CompilationFailed,
            "性能测试",
            null,
        );
    }
    
    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / iterations;
    const us_per_op = @as(f64, @floatFromInt(ns_per_op)) / 1000.0;
    
    std.debug.print("   处理 {d} 次失败\n", .{iterations});
    std.debug.print("   平均耗时: {d:.2} 微秒/操作\n", .{us_per_op});
    std.debug.print("   总耗时: {d:.2} 毫秒\n\n", .{@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0});
    
    // 7. 清理并显示最终统计
    std.debug.print("7. 最终统计信息:\n", .{});
    const final_stats = fallback_manager.getStatistics();
    std.debug.print("   总失败次数: {d}\n", .{final_stats.total_failures});
    std.debug.print("   总回退次数: {d}\n", .{fallback_manager.getFallbackCount()});
    
    std.debug.print("\n=== 演示完成 ===\n", .{});
    std.debug.print("查看日志文件 'jit_fallback_demo.log' 了解详细信息\n", .{});
}
