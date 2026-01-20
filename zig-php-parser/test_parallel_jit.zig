/// 并行 JIT 编译器独立测试
const std = @import("std");
const ParallelCompiler = @import("src/jit/parallel_compiler.zig").ParallelCompiler;
const CompilationQueue = @import("src/jit/parallel_compiler.zig").CompilationQueue;
const ResultCache = @import("src/jit/parallel_compiler.zig").ResultCache;
const CompilationTask = @import("src/jit/parallel_compiler.zig").CompilationTask;
const CompilationResult = @import("src/jit/parallel_compiler.zig").CompilationResult;
const CodeCache = @import("src/jit/code_cache.zig").CodeCache;
const CompiledFunc = @import("src/runtime/func.zig").CompiledFunc;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== 并行 JIT 编译器测试 ===\n\n", .{});
    
    // 测试 1: 编译任务队列
    std.debug.print("测试 1: 编译任务队列...\n", .{});
    try testCompilationQueue(allocator);
    std.debug.print("✓ 测试 1 通过\n\n", .{});
    
    // 测试 2: 结果缓存
    std.debug.print("测试 2: 结果缓存...\n", .{});
    try testResultCache(allocator);
    std.debug.print("✓ 测试 2 通过\n\n", .{});
    
    // 测试 3: 优先级队列
    std.debug.print("测试 3: 优先级队列...\n", .{});
    try testPriorityQueue(allocator);
    std.debug.print("✓ 测试 3 通过\n\n", .{});
    
    // 测试 4: 并行编译器基本功能
    std.debug.print("测试 4: 并行编译器基本功能...\n", .{});
    try testParallelCompilerBasic(allocator);
    std.debug.print("✓ 测试 4 通过\n\n", .{});
    
    std.debug.print("=== 所有测试通过 ===\n", .{});
}

fn testCompilationQueue(allocator: std.mem.Allocator) !void {
    var queue = CompilationQueue.init(allocator);
    defer queue.deinit();
    
    // 创建测试函数
    const FastValue = @import("src/runtime/fast_value.zig").FastValue;
    const test_func = CompiledFunc{
        .name = "test",
        .code = &[_]u8{},
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 0,
    };
    
    // 提交任务
    const task = CompilationTask{
        .func = &test_func,
        .type_profile = null,
        .osr_ip = null,
        .priority = 100,
        .timestamp = std.time.nanoTimestamp(),
    };
    
    try queue.submit(task);
    
    const size = queue.size();
    std.debug.print("  队列大小: {d}\n", .{size});
    
    if (size != 1) {
        return error.QueueSizeIncorrect;
    }
    
    // 获取任务
    const retrieved = queue.tryTake();
    if (retrieved == null) {
        return error.TaskNotRetrieved;
    }
    
    const final_size = queue.size();
    std.debug.print("  取出后队列大小: {d}\n", .{final_size});
    
    if (final_size != 0) {
        return error.QueueNotEmpty;
    }
}

fn testResultCache(allocator: std.mem.Allocator) !void {
    var cache = ResultCache.init(allocator);
    defer cache.deinit();
    
    // 插入结果
    const result = CompilationResult{
        .func_name = "test",
        .code = undefined,
        .osr_entry_offset = 0,
        .compile_time_ns = 1000,
        .success = true,
        .error_msg = null,
    };
    
    try cache.put("test", result);
    
    // 查找结果
    const cached = cache.get("test");
    if (cached == null) {
        return error.CacheNotFound;
    }
    
    std.debug.print("  缓存函数名: {s}\n", .{cached.?.func_name});
    std.debug.print("  编译时间: {d} ns\n", .{cached.?.compile_time_ns});
    
    // 验证命中率
    _ = cache.get("test"); // 再次命中
    _ = cache.get("nonexistent"); // 未命中
    
    const hit_rate = cache.getHitRate();
    std.debug.print("  缓存命中率: {d:.2}%\n", .{hit_rate * 100.0});
    
    if (hit_rate <= 0.0) {
        return error.InvalidHitRate;
    }
}

fn testPriorityQueue(allocator: std.mem.Allocator) !void {
    var queue = CompilationQueue.init(allocator);
    defer queue.deinit();
    
    const FastValue = @import("src/runtime/fast_value.zig").FastValue;
    const test_func = CompiledFunc{
        .name = "test",
        .code = &[_]u8{},
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 0,
    };
    
    // 提交不同优先级的任务
    const low_priority = CompilationTask{
        .func = &test_func,
        .type_profile = null,
        .osr_ip = null,
        .priority = 50,
        .timestamp = std.time.nanoTimestamp(),
    };
    
    const high_priority = CompilationTask{
        .func = &test_func,
        .type_profile = null,
        .osr_ip = null,
        .priority = 200,
        .timestamp = std.time.nanoTimestamp(),
    };
    
    try queue.submit(low_priority);
    try queue.submit(high_priority);
    
    // 高优先级应该先出队
    const first = queue.tryTake();
    if (first == null) {
        return error.TaskNotRetrieved;
    }
    
    std.debug.print("  第一个任务优先级: {d}\n", .{first.?.priority});
    
    if (first.?.priority != 200) {
        return error.PriorityOrderIncorrect;
    }
    
    const second = queue.tryTake();
    if (second == null) {
        return error.TaskNotRetrieved;
    }
    
    std.debug.print("  第二个任务优先级: {d}\n", .{second.?.priority});
    
    if (second.?.priority != 50) {
        return error.PriorityOrderIncorrect;
    }
}

fn testParallelCompilerBasic(allocator: std.mem.Allocator) !void {
    // 创建代码缓存
    var code_cache = try CodeCache.init(allocator, 1024 * 1024);
    defer code_cache.deinit();
    
    // 创建并行编译器（2个线程）
    var parallel_compiler = try ParallelCompiler.init(
        allocator,
        &code_cache,
        2,
    );
    defer parallel_compiler.deinit();
    
    std.debug.print("  线程数: {d}\n", .{parallel_compiler.num_threads});
    std.debug.print("  工作线程数: {d}\n", .{parallel_compiler.workers.len});
    
    if (parallel_compiler.num_threads != 2) {
        return error.IncorrectThreadCount;
    }
    
    if (parallel_compiler.workers.len != 2) {
        return error.IncorrectWorkerCount;
    }
    
    // 打印统计信息
    parallel_compiler.printStats();
}
