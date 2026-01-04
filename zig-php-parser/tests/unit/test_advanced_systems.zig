const std = @import("std");
const testing = std.testing;

/// 高级系统综合测试套件
/// 覆盖：内存管理、错误处理、性能监控、字节码系统

// ============================================================================
// 内存管理测试
// ============================================================================

const advanced_memory = @import("../../src/runtime/advanced_memory.zig");
const HeapLayout = advanced_memory.HeapLayout;
const GarbageCollector = advanced_memory.GarbageCollector;
const LeakProtector = advanced_memory.LeakProtector;

test "HeapLayout - 分代内存分配" {
    var heap = HeapLayout.init(testing.allocator);
    defer heap.deinit();

    // 小对象分配到Young Gen
    const small_obj = try heap.alloc(100);
    try testing.expect(small_obj.len == 100);

    // 大对象分配到Large Object Space
    const large_obj = try heap.alloc(100 * 1024);
    try testing.expect(large_obj.len == 100 * 1024);

    const stats = heap.getStats();
    try testing.expect(stats.young_allocations >= 1);
    try testing.expect(stats.large_allocations >= 1);
}

test "GarbageCollector - GC流程" {
    var gc = GarbageCollector.init(testing.allocator);
    defer gc.deinit();

    try gc.collect();

    const stats = gc.getStats();
    try testing.expect(stats.total_collections >= 1);
    try testing.expect(stats.ref_count_cycles >= 1);
}

test "LeakProtector - 内存泄漏检测" {
    var protector = LeakProtector.init(testing.allocator);
    defer protector.deinit();

    // 模拟分配
    try protector.trackAllocation(0x1000, 100, &[_]usize{});
    try protector.trackAllocation(0x2000, 200, &[_]usize{});

    // 释放一个
    protector.trackDeallocation(0x1000);

    // 检测泄漏
    const report = try protector.detectLeaks();
    try testing.expect(report.leaked_allocations == 1);
    try testing.expect(report.leaked_bytes == 200);
    try testing.expect(report.has_leaks);
}

test "LeakProtector - 无泄漏场景" {
    var protector = LeakProtector.init(testing.allocator);
    defer protector.deinit();

    try protector.trackAllocation(0x1000, 100, &[_]usize{});
    protector.trackDeallocation(0x1000);

    const report = try protector.detectLeaks();
    try testing.expect(!report.has_leaks);
    try testing.expect(report.leaked_allocations == 0);
}

// ============================================================================
// 错误处理测试
// ============================================================================

const advanced_error = @import("../../src/runtime/advanced_error_handling.zig");
const ErrorType = advanced_error.ErrorType;
const ErrorContext = advanced_error.ErrorContext;
const ErrorInfo = advanced_error.ErrorInfo;
const ErrorHandler = advanced_error.ErrorHandler;
const ErrorRecoveryStrategy = advanced_error.ErrorRecoveryStrategy;
const AdvancedErrorSystem = advanced_error.AdvancedErrorSystem;

test "ErrorContext - 错误分类" {
    var context = ErrorContext.init(testing.allocator, .type_error, "类型不匹配", "test.php", 42);
    defer context.deinit(testing.allocator);

    try testing.expect(context.error_type == .type_error);
    try testing.expect(context.severity == .err);
    try testing.expectEqualStrings("类型不匹配", context.message);
    try testing.expect(context.line == 42);
}

test "ErrorContext - 添加建议" {
    var context = ErrorContext.init(testing.allocator, .parse_error, "语法错误", "test.php", 10);
    defer context.deinit(testing.allocator);

    try context.addSuggestion(testing.allocator, "检查括号是否匹配");
    try context.addSuggestion(testing.allocator, "确认语句以分号结尾");

    try testing.expect(context.suggestions.items.len == 2);
}

test "ErrorRecoveryStrategy - 词法恢复" {
    var strategy = ErrorRecoveryStrategy.init(testing.allocator);
    defer strategy.deinit();

    var error_info = ErrorInfo.init(testing.allocator, .lexer_error, "无效字符", "test.php", 5);
    defer error_info.deinit(testing.allocator);

    const recovered = try strategy.recoverLexerError(&error_info);
    try testing.expect(recovered);

    const stats = strategy.getRecoveryStats();
    try testing.expect(stats.lexer_recoveries == 1);
    try testing.expect(stats.successful_recoveries == 1);
}

test "ErrorRecoveryStrategy - 语法恢复" {
    var strategy = ErrorRecoveryStrategy.init(testing.allocator);
    defer strategy.deinit();

    var error_info = ErrorInfo.init(testing.allocator, .parse_error, "缺少分号", "test.php", 10);
    defer error_info.deinit(testing.allocator);

    const recovered = try strategy.recoverParserError(&error_info);
    try testing.expect(recovered);

    const stats = strategy.getRecoveryStats();
    try testing.expect(stats.parser_recoveries == 1);
}

test "ErrorRecoveryStrategy - 运行时恢复" {
    var strategy = ErrorRecoveryStrategy.init(testing.allocator);
    defer strategy.deinit();

    var error_info = ErrorInfo.init(testing.allocator, .type_error, "类型错误", "test.php", 20);
    defer error_info.deinit(testing.allocator);

    const recovered = try strategy.recoverRuntimeError(&error_info);
    try testing.expect(recovered);

    const stats = strategy.getRecoveryStats();
    try testing.expect(stats.runtime_recoveries == 1);
}

test "ErrorHandler - 错误报告" {
    var handler = ErrorHandler.init(testing.allocator);
    defer handler.deinit();

    try handler.reportError(.lexer_error, "意外的令牌", "test.php", 5);

    const stats = handler.getStats();
    try testing.expect(stats.total_errors == 1);
    try testing.expect(stats.handled_errors == 1);
}

test "AdvancedErrorSystem - 综合错误处理" {
    var system = AdvancedErrorSystem.init(testing.allocator);
    defer system.deinit();

    try system.handleError(.argument_error, "参数数量错误", "test.php", 20);

    const stats = try system.getComprehensiveStats();
    try testing.expect(stats.total_errors_processed == 1);
    try testing.expect(stats.errors_recovered == 1);
}

// ============================================================================
// 性能监控测试
// ============================================================================

const performance = @import("../../src/runtime/performance_monitor.zig");
const PerformanceMonitor = performance.PerformanceMonitor;
const MetricsCollector = performance.MetricsCollector;
const HotspotDetector = performance.HotspotDetector;
const ExecutionStats = performance.ExecutionStats;
const MemoryStats = performance.MemoryStats;

test "PerformanceMonitor - 基础功能" {
    var monitor = PerformanceMonitor.init(testing.allocator);
    defer monitor.deinit();

    try monitor.recordFunctionCall("test_func", 1000);
    monitor.recordAllocation(1024);
    monitor.recordDeallocation(512);

    const exec_stats = monitor.getExecutionStats();
    try testing.expect(exec_stats.total_function_calls == 1);

    const mem_stats = monitor.getMemoryStats();
    try testing.expect(mem_stats.total_allocations == 1);
    try testing.expect(mem_stats.current_memory_usage == 512);
}

test "HotspotDetector - 热点检测" {
    var detector = HotspotDetector.init(testing.allocator);
    defer detector.deinit();

    detector.setThreshold(.{ .min_call_count = 3 });

    // 调用不足阈值
    try detector.recordCall("cold_func", 100);
    try testing.expect(!detector.isHotspot("cold_func"));

    // 调用达到阈值
    try detector.recordCall("hot_func", 100);
    try detector.recordCall("hot_func", 100);
    try detector.recordCall("hot_func", 100);
    try testing.expect(detector.isHotspot("hot_func"));
}

test "MetricsCollector - 指标收集" {
    var collector = MetricsCollector.init(testing.allocator);
    defer collector.deinit();

    try collector.recordMetric("cpu_usage", 75.5, "%", .gauge);
    try collector.incrementCounter("requests");
    try collector.incrementCounter("requests");

    const cpu_metric = collector.getMetric("cpu_usage");
    try testing.expect(cpu_metric != null);
    try testing.expect(cpu_metric.?.value == 75.5);

    const req_metric = collector.getMetric("requests");
    try testing.expect(req_metric != null);
    try testing.expect(req_metric.?.value == 2);
}

test "ExecutionStats - 缓存命中率" {
    var stats = ExecutionStats.init();

    stats.cache_hits = 80;
    stats.cache_misses = 20;

    const hit_rate = stats.getCacheHitRate();
    try testing.expect(hit_rate == 0.8);
}

test "ExecutionStats - 分支预测率" {
    var stats = ExecutionStats.init();

    stats.branch_taken = 70;
    stats.branch_not_taken = 30;

    const pred_rate = stats.getBranchPredictionRate();
    try testing.expect(pred_rate == 0.7);
}

test "MemoryStats - 碎片率计算" {
    var stats = MemoryStats.init();

    stats.total_bytes_allocated = 1000;
    stats.bytes_freed_by_gc = 300;

    const frag_rate = stats.getFragmentationRate();
    try testing.expect(frag_rate == 0.3);
}

test "MemoryStats - 平均GC时间" {
    var stats = MemoryStats.init();

    stats.gc_events = 5;
    stats.total_gc_time_ns = 50000;

    const avg_gc = stats.getAverageGCTime();
    try testing.expect(avg_gc == 10000);
}

// ============================================================================
// 字节码系统测试
// ============================================================================

const bytecode = @import("../../src/bytecode/instruction.zig");
const Instruction = bytecode.Instruction;
const OpCode = bytecode.OpCode;

test "Instruction - 指令创建" {
    const inst = Instruction.init(.push_const, 42, 0);
    try testing.expect(inst.opcode == .push_const);
    try testing.expect(inst.operand1 == 42);
    try testing.expect(inst.operand2 == 0);
}

test "Instruction - 类型提示" {
    const inst = Instruction.withTypeHint(.add_int, 0, 0, .integer);
    try testing.expect(inst.flags.type_hint == .integer);
}

test "Instruction - 尾调用标记" {
    const inst = Instruction.init(.call, 10, 2).asTailCall();
    try testing.expect(inst.flags.is_tail_call);
}

test "OpCode - 跳转指令识别" {
    try testing.expect(OpCode.jmp.isJump());
    try testing.expect(OpCode.jz.isJump());
    try testing.expect(OpCode.jnz.isJump());
    try testing.expect(!OpCode.add_int.isJump());
    try testing.expect(!OpCode.push_const.isJump());
}

test "OpCode - 调用指令识别" {
    try testing.expect(OpCode.call.isCall());
    try testing.expect(OpCode.call_method.isCall());
    try testing.expect(OpCode.call_static.isCall());
    try testing.expect(!OpCode.add_int.isCall());
}

test "OpCode - 终结指令识别" {
    try testing.expect(OpCode.ret.isTerminator());
    try testing.expect(OpCode.ret_void.isTerminator());
    try testing.expect(OpCode.throw.isTerminator());
    try testing.expect(OpCode.halt.isTerminator());
    try testing.expect(OpCode.jmp.isTerminator()); // 无条件跳转也是终结
    try testing.expect(!OpCode.add_int.isTerminator());
}

// ============================================================================
// 优化器测试
// ============================================================================

const optimizer = @import("../../src/bytecode/optimizer.zig");
const BytecodeOptimizer = optimizer.BytecodeOptimizer;
const TypeInference = optimizer.TypeInference;
const InlineCache = optimizer.InlineCache;
const EscapeAnalyzer = optimizer.EscapeAnalyzer;

test "TypeInference - 变量类型推导" {
    var inference = TypeInference.init(testing.allocator);
    defer inference.deinit();

    try inference.setVariableType("count", .integer);
    try inference.setVariableType("name", .string);

    try testing.expect(inference.inferVariable("count") == .integer);
    try testing.expect(inference.inferVariable("name") == .string);
    try testing.expect(inference.inferVariable("unknown") == .unknown);
}

test "TypeInference - 二元操作类型推导" {
    // 整数运算
    try testing.expect(TypeInference.inferBinaryOp(.integer, .integer, .add_int) == .integer);
    try testing.expect(TypeInference.inferBinaryOp(.integer, .integer, .div_int) == .float);
    try testing.expect(TypeInference.inferBinaryOp(.integer, .integer, .eq_int) == .boolean);

    // 浮点运算
    try testing.expect(TypeInference.inferBinaryOp(.float, .float, .add_float) == .float);
    try testing.expect(TypeInference.inferBinaryOp(.integer, .float, .mul_float) == .float);

    // 字符串操作
    try testing.expect(TypeInference.inferBinaryOp(.string, .string, .concat) == .string);
    try testing.expect(TypeInference.inferBinaryOp(.string, .string, .eq) == .boolean);
}

test "InlineCache - 单态缓存" {
    var cache = InlineCache.init();

    // 首次调用 - 未命中
    try testing.expect(cache.lookup(1) == null);
    try testing.expect(cache.state == .uninitialized);

    // 更新缓存
    cache.update(1, 100);
    try testing.expect(cache.state == .monomorphic);

    // 再次调用 - 命中
    try testing.expect(cache.lookup(1) == 100);
}

test "InlineCache - 多态缓存" {
    var cache = InlineCache.init();

    cache.update(1, 100);
    try testing.expect(cache.state == .monomorphic);

    cache.update(2, 200);
    try testing.expect(cache.state == .polymorphic);

    cache.update(3, 300);
    cache.update(4, 400);
    try testing.expect(cache.state == .polymorphic);

    // 超过限制变为超多态
    cache.update(5, 500);
    try testing.expect(cache.state == .megamorphic);
}

test "EscapeAnalyzer - 栈分配判断" {
    var analyzer = EscapeAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    // 未分析的变量默认不逃逸
    try testing.expect(analyzer.canStackAllocate("local_var"));
    try testing.expect(analyzer.getEscapeState("local_var") == .no_escape);
}

// ============================================================================
// 综合集成测试
// ============================================================================

test "集成测试 - 内存+错误+性能" {
    // 初始化所有系统
    var monitor = PerformanceMonitor.init(testing.allocator);
    defer monitor.deinit();

    var error_system = AdvancedErrorSystem.init(testing.allocator);
    defer error_system.deinit();

    var protector = LeakProtector.init(testing.allocator);
    defer protector.deinit();

    // 模拟程序执行
    try monitor.recordFunctionCall("main", 5000);
    monitor.recordAllocation(1024);

    try protector.trackAllocation(0x1000, 1024, &[_]usize{});

    // 模拟错误
    try error_system.handleError(.type_error, "测试错误", "main.php", 1);

    // 验证统计
    const exec_stats = monitor.getExecutionStats();
    try testing.expect(exec_stats.total_function_calls == 1);

    const error_stats = try error_system.getComprehensiveStats();
    try testing.expect(error_stats.total_errors_processed == 1);

    // 清理
    protector.trackDeallocation(0x1000);
    const leak_report = try protector.detectLeaks();
    try testing.expect(!leak_report.has_leaks);
}
