/// 性能基准测试运行器
/// 测试各个组件的性能并生成报告
const std = @import("std");

// 导入运行时模块
const memory = @import("../../src/runtime/memory.zig");
const gc_module = @import("../../src/runtime/gc.zig");
const GarbageCollector = gc_module.GarbageCollector;

/// 基准测试结果
const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_time_ns: u64,
    avg_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    ops_per_sec: f64,
};

/// 基准测试套件
const BenchmarkSuite = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(BenchmarkResult),
    
    pub fn init(allocator: std.mem.Allocator) BenchmarkSuite {
        return .{
            .allocator = allocator,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
        };
    }
    
    pub fn deinit(self: *BenchmarkSuite) void {
        self.results.deinit();
    }
    
    pub fn addResult(self: *BenchmarkSuite, result: BenchmarkResult) !void {
        try self.results.append(result);
    }
    
    pub fn printReport(self: *BenchmarkSuite) void {
        std.debug.print("\n{'='**60}\n", .{});
        std.debug.print("           PERFORMANCE BENCHMARK REPORT\n", .{});
        std.debug.print("{'='**60}\n\n", .{});
        
        for (self.results.items) |result| {
            std.debug.print("Benchmark: {s}\n", .{result.name});
            std.debug.print("  Iterations:    {d}\n", .{result.iterations});
            std.debug.print("  Total time:    {d} ns ({d:.2} ms)\n", .{
                result.total_time_ns,
                @as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0,
            });
            std.debug.print("  Avg time:      {d} ns\n", .{result.avg_time_ns});
            std.debug.print("  Min time:      {d} ns\n", .{result.min_time_ns});
            std.debug.print("  Max time:      {d} ns\n", .{result.max_time_ns});
            std.debug.print("  Ops/sec:       {d:.2}\n", .{result.ops_per_sec});
            std.debug.print("\n", .{});
        }
        
        std.debug.print("{'='**60}\n", .{});
    }
};

/// 运行基准测试并测量时间
fn runBenchmark(
    name: []const u8,
    iterations: u64,
    warmup_iterations: u64,
    comptime benchFn: fn (*anyopaque) void,
    context: *anyopaque,
) BenchmarkResult {
    // 预热
    var i: u64 = 0;
    while (i < warmup_iterations) : (i += 1) {
        benchFn(context);
    }
    
    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;
    
    // 实际测试
    i = 0;
    while (i < iterations) : (i += 1) {
        const start = @as(u64, @intCast(std.time.nanoTimestamp()));
        benchFn(context);
        const end = @as(u64, @intCast(std.time.nanoTimestamp()));
        
        const elapsed = end - start;
        total_time += elapsed;
        if (elapsed < min_time) min_time = elapsed;
        if (elapsed > max_time) max_time = elapsed;
    }
    
    const avg_time = total_time / iterations;
    const ops_per_sec = if (avg_time > 0)
        1_000_000_000.0 / @as(f64, @floatFromInt(avg_time))
    else
        0.0;
    
    return .{
        .name = name,
        .iterations = iterations,
        .total_time_ns = total_time,
        .avg_time_ns = avg_time,
        .min_time_ns = min_time,
        .max_time_ns = max_time,
        .ops_per_sec = ops_per_sec,
    };
}

// ============================================================================
// 基准测试函数
// ============================================================================

const ArenaContext = struct {
    arena: *memory.ArenaAllocator,
    alloc_size: usize,
};

fn benchArenaAlloc(ctx: *anyopaque) void {
    const context: *ArenaContext = @ptrCast(@alignCast(ctx));
    _ = context.arena.alloc(u8, context.alloc_size) catch {};
}

const PoolContext = struct {
    pool: *memory.ObjectPool(TestObject),
};

const TestObject = struct {
    value: u64,
    data: [56]u8,
};

fn benchPoolAcquireRelease(ctx: *anyopaque) void {
    const context: *PoolContext = @ptrCast(@alignCast(ctx));
    const obj = context.pool.acquire() catch return;
    obj.value = 42;
    context.pool.release(obj);
}

const StringContext = struct {
    interner: *memory.StringInterner,
    strings: []const []const u8,
    index: usize,
};

fn benchStringIntern(ctx: *anyopaque) void {
    const context: *StringContext = @ptrCast(@alignCast(ctx));
    const str = context.strings[context.index % context.strings.len];
    _ = context.interner.intern(str) catch {};
    context.index += 1;
}

const GCContext = struct {
    gc: *memory.GenerationalGC,
};

fn benchGCCreate(ctx: *anyopaque) void {
    const context: *GCContext = @ptrCast(@alignCast(ctx));
    _ = context.gc.create(64) catch {};
}

fn benchGCCollect(ctx: *anyopaque) void {
    const context: *GCContext = @ptrCast(@alignCast(ctx));
    context.gc.collectYoung() catch {};
}

const IncrementalGCContext = struct {
    gc: *GarbageCollector,
};

fn benchIncrementalStep(ctx: *anyopaque) void {
    const context: *IncrementalGCContext = @ptrCast(@alignCast(ctx));
    _ = context.gc.incrementalStep(10);
}

// ============================================================================
// 主函数
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n", .{});
    std.debug.print("Starting Performance Benchmarks...\n", .{});
    std.debug.print("\n", .{});
    
    var suite = BenchmarkSuite.init(allocator);
    defer suite.deinit();
    
    // 1. Arena分配器基准测试
    {
        std.debug.print("Running: Arena Allocator Benchmark\n", .{});
        var arena = memory.ArenaAllocator.init(allocator);
        defer arena.deinit();
        
        var ctx = ArenaContext{
            .arena = &arena,
            .alloc_size = 64,
        };
        
        const result = runBenchmark(
            "Arena Allocator (64 bytes)",
            10000,
            1000,
            benchArenaAlloc,
            @ptrCast(&ctx),
        );
        try suite.addResult(result);
        arena.reset();
    }
    
    // 2. 对象池基准测试
    {
        std.debug.print("Running: Object Pool Benchmark\n", .{});
        var pool = memory.ObjectPool(TestObject).init(allocator);
        defer pool.deinit();
        
        var ctx = PoolContext{
            .pool = &pool,
        };
        
        const result = runBenchmark(
            "Object Pool Acquire/Release",
            10000,
            1000,
            benchPoolAcquireRelease,
            @ptrCast(&ctx),
        );
        try suite.addResult(result);
    }
    
    // 3. 字符串驻留基准测试
    {
        std.debug.print("Running: String Interner Benchmark\n", .{});
        var interner = memory.StringInterner.init(allocator);
        defer interner.deinit();
        
        const test_strings = [_][]const u8{
            "hello", "world", "php", "zig", "benchmark",
            "performance", "test", "string", "intern", "cache",
        };
        
        var ctx = StringContext{
            .interner = &interner,
            .strings = &test_strings,
            .index = 0,
        };
        
        const result = runBenchmark(
            "String Interner",
            10000,
            1000,
            benchStringIntern,
            @ptrCast(&ctx),
        );
        try suite.addResult(result);
    }
    
    // 4. 分代GC对象创建基准测试
    {
        std.debug.print("Running: Generational GC Create Benchmark\n", .{});
        var gc = memory.GenerationalGC.init(allocator);
        defer gc.deinit();
        
        var ctx = GCContext{
            .gc = &gc,
        };
        
        const result = runBenchmark(
            "Generational GC Object Create",
            5000,
            500,
            benchGCCreate,
            @ptrCast(&ctx),
        );
        try suite.addResult(result);
    }
    
    // 5. 分代GC收集基准测试
    {
        std.debug.print("Running: Generational GC Collect Benchmark\n", .{});
        var gc = memory.GenerationalGC.init(allocator);
        defer gc.deinit();
        
        // 预先创建一些对象
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            const obj = try gc.create(64);
            try gc.addRoot(obj);
        }
        
        var ctx = GCContext{
            .gc = &gc,
        };
        
        const result = runBenchmark(
            "Generational GC Young Collection",
            100,
            10,
            benchGCCollect,
            @ptrCast(&ctx),
        );
        try suite.addResult(result);
    }
    
    // 6. 增量GC步进基准测试
    {
        std.debug.print("Running: Incremental GC Step Benchmark\n", .{});
        var gc = try GarbageCollector.init(allocator, 1024 * 1024);
        defer gc.deinit();
        
        var ctx = IncrementalGCContext{
            .gc = &gc,
        };
        
        const result = runBenchmark(
            "Incremental GC Step",
            1000,
            100,
            benchIncrementalStep,
            @ptrCast(&ctx),
        );
        try suite.addResult(result);
    }
    
    // 打印报告
    suite.printReport();
    
    // 生成JSON结果
    std.debug.print("Benchmark results can be compared with baseline_results.json\n", .{});
}

// ============================================================================
// 测试
// ============================================================================

test "benchmark suite initialization" {
    const allocator = std.testing.allocator;
    var suite = BenchmarkSuite.init(allocator);
    defer suite.deinit();
    
    try suite.addResult(.{
        .name = "test",
        .iterations = 100,
        .total_time_ns = 1000,
        .avg_time_ns = 10,
        .min_time_ns = 5,
        .max_time_ns = 20,
        .ops_per_sec = 100_000_000.0,
    });
    
    try std.testing.expectEqual(@as(usize, 1), suite.results.items.len);
}
