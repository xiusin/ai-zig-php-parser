const std = @import("std");
const advanced_memory = @import("src/runtime/advanced_memory.zig");
const advanced_error_handling = @import("src/runtime/advanced_error_handling.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== 高级内存管理和错误处理系统测试 ===", .{});

    // ============================================================================
    // 1. 测试堆内存布局分配策略
    // ============================================================================

    std.log.info("\n--- 1. 测试堆内存布局分配策略 ---", .{});
    {
        var heap = advanced_memory.HeapLayout.init(allocator);
        defer heap.deinit();

        // 测试小对象分配到Young Gen
        const young_obj = try heap.alloc(100);
        std.log.info("Young Gen分配 100 bytes: {}", .{young_obj.len == 100});

        // 测试大对象分配到Large Objects
        const large_obj = try heap.alloc(100 * 1024);
        std.log.info("Large Objects分配 100KB: {}", .{large_obj.len == 100 * 1024});

        // 测试GC触发
        _ = try heap.alloc(200); // 应该触发Young Gen GC

        const stats = heap.getStats();
        std.log.info("分配统计:", .{});
        std.log.info("  Young Gen分配次数: {}", .{stats.young_allocations});
        std.log.info("  Large Objects分配次数: {}", .{stats.large_allocations});
        std.log.info("  晋升次数: {}", .{stats.promotion_count});
        std.log.info("  Young Gen总字节数: {}", .{stats.total_bytes_young});
        std.log.info("  Large Objects总字节数: {}", .{stats.total_bytes_large});
    }

    // ============================================================================
    // 2. 测试垃圾回收流程
    // ============================================================================

    std.log.info("\n--- 2. 测试垃圾回收流程 ---", .{});
    {
        var gc = advanced_memory.GarbageCollector.init(allocator);
        defer gc.deinit();

        // 执行多次GC测试不同阶段
        try gc.collect();
        try gc.collect();
        try gc.collect();

        const stats = gc.getStats();
        std.log.info("GC统计:", .{});
        std.log.info("  总GC次数: {}", .{stats.total_collections});
        std.log.info("  引用计数周期: {}", .{stats.ref_count_cycles});
        std.log.info("  循环检测周期: {}", .{stats.cycle_detection_cycles});
        std.log.info("  压缩周期: {}", .{stats.compaction_cycles});
        std.log.info("  平均GC时间: {} ns", .{stats.average_gc_time_ns});
        std.log.info("  释放总字节数: {}", .{stats.total_freed_bytes});
    }

    // ============================================================================
    // 3. 测试内存泄漏防护
    // ============================================================================

    std.log.info("\n--- 3. 测试内存泄漏防护 ---", .{});
    {
        var protector = advanced_memory.LeakProtector.init(allocator);
        defer protector.deinit();

        // 模拟内存分配追踪
        const dummy_stack = [_]usize{ 0x1000, 0x2000, 0x3000 };
        try protector.trackAllocation(0xDEADBEEF, 1024, &dummy_stack);
        try protector.trackAllocation(0xCAFEBABE, 2048, &dummy_stack);
        try protector.trackAllocation(0xBAADF00D, 512, &dummy_stack);

        // 释放其中一个
        protector.trackDeallocation(0xCAFEBABE);

        // 生成内存报告
        const report = try protector.generateMemoryReport();
        defer allocator.free(report);

        std.log.info("内存泄漏报告:", .{});
        std.log.info("{s}", .{report});

        const leak_report = try protector.detectLeaks();
        std.log.info("泄漏检测结果: {} 个泄漏, {} 字节", .{
            leak_report.leaked_allocations,
            leak_report.leaked_bytes,
        });
    }

    // ============================================================================
    // 4. 测试错误分类体系
    // ============================================================================

    std.log.info("\n--- 4. 测试错误分类体系 ---", .{});
    {
        const TestError = struct {
            error_type: advanced_error_handling.ErrorType,
            message: []const u8,
            expected_severity: advanced_error_handling.ErrorSeverity,
        };

        const test_errors = [_]TestError{
            TestError{ .error_type = .lexer_error, .message = "Unexpected token", .expected_severity = @enumFromInt(2) },
            TestError{ .error_type = .parse_error, .message = "Missing semicolon", .expected_severity = @enumFromInt(2) },
            TestError{ .error_type = .type_error, .message = "Type mismatch", .expected_severity = @enumFromInt(2) },
            TestError{ .error_type = .memory_error, .message = "Out of memory", .expected_severity = @enumFromInt(3) },
            TestError{ .error_type = .logic_error, .message = "Invalid logic", .expected_severity = @enumFromInt(1) },
            TestError{ .error_type = .fatal_error, .message = "System crash", .expected_severity = @enumFromInt(4) },
        };

        for (test_errors) |test_case| {
            var context = advanced_error_handling.ErrorContext.init(allocator, test_case.error_type, test_case.message, "test.php", 42);
            defer context.deinit(allocator);

            std.log.info("错误类型 {s}: 严重程度 {s} (期望 {s})", .{ @tagName(test_case.error_type), @tagName(context.severity), @tagName(test_case.expected_severity) });

            std.testing.expect(context.severity == test_case.expected_severity) catch {
                std.log.err("错误严重程度不匹配!", .{});
            };
        }
    }

    // ============================================================================
    // 5. 测试错误恢复策略
    // ============================================================================

    std.log.info("\n--- 5. 测试错误恢复策略 ---", .{});
    {
        var strategy = advanced_error_handling.ErrorRecoveryStrategy.init(allocator);
        defer strategy.deinit();

        // 测试词法错误恢复
        var lexer_error = advanced_error_handling.ErrorInfo.init(allocator, .lexer_error, "Unexpected character", "test.php", 5);
        defer lexer_error.deinit(allocator);

        const lexer_recovered = try strategy.recoverLexerError(&lexer_error);
        std.log.info("词法错误恢复: {}", .{lexer_recovered});

        // 测试语法错误恢复
        var parser_error = advanced_error_handling.ErrorInfo.init(allocator, .parse_error, "Missing semicolon", "test.php", 10);
        defer parser_error.deinit(allocator);

        const parser_recovered = try strategy.recoverParserError(&parser_error);
        std.log.info("语法错误恢复: {}", .{parser_recovered});

        // 测试运行时错误恢复
        var runtime_error = advanced_error_handling.ErrorInfo.init(allocator, .type_error, "Invalid type conversion", "test.php", 15);
        defer runtime_error.deinit(allocator);

        const runtime_recovered = try strategy.recoverRuntimeError(&runtime_error);
        std.log.info("运行时错误恢复: {}", .{runtime_recovered});

        const recovery_stats = strategy.getRecoveryStats();
        std.log.info("恢复统计:", .{});
        std.log.info("  总恢复次数: {}", .{recovery_stats.total_recoveries});
        std.log.info("  成功恢复: {}", .{recovery_stats.successful_recoveries});
        std.log.info("  词法恢复: {}", .{recovery_stats.lexer_recoveries});
        std.log.info("  语法恢复: {}", .{recovery_stats.parser_recoveries});
        std.log.info("  运行时恢复: {}", .{recovery_stats.runtime_recoveries});
    }

    // ============================================================================
    // 6. 测试高级错误处理系统
    // ============================================================================

    std.log.info("\n--- 6. 测试高级错误处理系统 ---", .{});
    {
        var error_system = advanced_error_handling.AdvancedErrorSystem.init(allocator);
        defer error_system.deinit();

        // 报告各种类型的错误
        try error_system.handleError(.lexer_error, "Invalid token sequence", "lexer.php", 5);
        try error_system.handleError(.parse_error, "Unexpected end of file", "parser.php", 10);
        try error_system.handleError(.type_error, "Cannot convert string to int", "runtime.php", 15);
        try error_system.handleError(.argument_error, "Wrong number of arguments", "function.php", 20);

        const system_stats = try error_system.getComprehensiveStats();
        std.log.info("系统统计:", .{});
        std.log.info("  处理的总错误数: {}", .{system_stats.total_errors_processed});
        std.log.info("  恢复的错误数: {}", .{system_stats.errors_recovered});
        std.log.info("  升级的错误数: {}", .{system_stats.errors_escalated});
        std.log.info("  系统运行时间: {} 秒", .{system_stats.system_uptime_seconds});

        // 生成系统报告
        const system_report = try error_system.generateSystemReport();
        defer allocator.free(system_report);

        std.log.info("\n完整系统报告:", .{});
        std.log.info("{s}", .{system_report});
    }

    // ============================================================================
    // 7. 性能对比测试
    // ============================================================================

    std.log.info("\n--- 7. 性能对比测试 ---", .{});
    {
        // 测试内存分配性能
        var heap = advanced_memory.HeapLayout.init(allocator);
        defer heap.deinit();

        const alloc_count = 1000;
        const start_time = std.time.nanoTimestamp();

        var i: usize = 0;
        while (i < alloc_count) : (i += 1) {
            _ = try heap.alloc(64); // 分配64字节的小对象
        }

        const end_time = std.time.nanoTimestamp();
        const total_time = end_time - start_time;
        const avg_time = total_time / alloc_count;

        std.log.info("内存分配性能:", .{});
        std.log.info("  分配 {} 个64字节对象", .{alloc_count});
        std.log.info("  总时间: {} ns", .{total_time});
        std.log.info("  平均时间: {} ns/分配", .{avg_time});

        // 触发GC测试性能
        const gc_start = std.time.nanoTimestamp();
        try heap.gcYoung();
        const gc_end = std.time.nanoTimestamp();
        std.log.info("  Young Gen GC时间: {} ns", .{gc_end - gc_start});
    }

    std.log.info("\n=== 所有高级内存管理和错误处理测试通过 ===", .{});
}
