/// 并行 JIT 编译器
/// 
/// 功能：
/// - 多线程 JIT 编译
/// - 编译任务队列管理
/// - 编译结果缓存
/// - 线程安全的任务调度
/// 
/// @concurrency-model GUARDED_BY(queue_mutex)
/// @thread-safety ATOMIC
/// @ownership NON-OWNING (allocator)

const std = @import("std");
const Compiler = @import("compiler.zig").Compiler;
const CodeCache = @import("code_cache.zig").CodeCache;
const imports = @import("imports.zig");
const CompiledFunc = imports.CompiledFunc;
const HotspotDetector = @import("hotspot_detector.zig").HotspotDetector;
const FallbackManager = @import("fallback.zig").FallbackManager;

/// 编译任务
pub const CompilationTask = struct {
    func: *const CompiledFunc,
    type_profile: ?*const anyopaque,
    osr_ip: ?usize,
    priority: u8, // 0-255, 越高越优先
    timestamp: i128, // 提交时间
    
    /// 比较优先级（用于优先队列）
    pub fn compare(_: void, a: CompilationTask, b: CompilationTask) std.math.Order {
        // 先按优先级，再按时间戳
        if (a.priority != b.priority) {
            // 高优先级在前
            return if (a.priority > b.priority) .lt else .gt;
        }
        // 早提交的在前
        return if (a.timestamp < b.timestamp) .lt else if (a.timestamp > b.timestamp) .gt else .eq;
    }
};

/// 编译结果
pub const CompilationResult = struct {
    func_name: []const u8,
    code: *const anyopaque,
    osr_entry_offset: usize,
    compile_time_ns: u64,
    success: bool,
    error_msg: ?[]const u8,
};

/// 编译结果缓存
/// @concurrency-model GUARDED_BY(cache_mutex)
pub const ResultCache = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(CompilationResult),
    cache_mutex: std.Thread.Mutex,
    hit_count: std.atomic.Value(u64),
    miss_count: std.atomic.Value(u64),
    
    pub fn init(allocator: std.mem.Allocator) ResultCache {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap(CompilationResult).init(allocator),
            .cache_mutex = .{},
            .hit_count = std.atomic.Value(u64).init(0),
            .miss_count = std.atomic.Value(u64).init(0),
        };
    }
    
    pub fn deinit(self: *ResultCache) void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.error_msg) |msg| {
                self.allocator.free(msg);
            }
        }
        self.cache.deinit();
    }
    
    /// 查找缓存
    /// @thread-safety GUARDED_BY(cache_mutex)
    pub fn get(self: *ResultCache, func_name: []const u8) ?CompilationResult {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        
        if (self.cache.get(func_name)) |result| {
            _ = self.hit_count.fetchAdd(1, .monotonic);
            return result;
        }
        
        _ = self.miss_count.fetchAdd(1, .monotonic);
        return null;
    }
    
    /// 插入缓存
    /// @thread-safety GUARDED_BY(cache_mutex)
    pub fn put(self: *ResultCache, func_name: []const u8, result: CompilationResult) !void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        
        try self.cache.put(func_name, result);
    }
    
    /// 获取缓存命中率
    pub fn getHitRate(self: *ResultCache) f64 {
        const hits = self.hit_count.load(.monotonic);
        const misses = self.miss_count.load(.monotonic);
        const total = hits + misses;
        
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(total));
    }
    
    /// 清空缓存
    pub fn clear(self: *ResultCache) void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.error_msg) |msg| {
                self.allocator.free(msg);
            }
        }
        self.cache.clearRetainingCapacity();
        
        self.hit_count.store(0, .monotonic);
        self.miss_count.store(0, .monotonic);
    }
};

/// 编译任务队列
/// @concurrency-model GUARDED_BY(queue_mutex)
pub const CompilationQueue = struct {
    allocator: std.mem.Allocator,
    queue: std.PriorityQueue(CompilationTask, void, CompilationTask.compare),
    queue_mutex: std.Thread.Mutex,
    queue_cond: std.Thread.Condition,
    shutdown: std.atomic.Value(bool),
    pending_count: std.atomic.Value(usize),
    
    pub fn init(allocator: std.mem.Allocator) CompilationQueue {
        return .{
            .allocator = allocator,
            .queue = std.PriorityQueue(CompilationTask, void, CompilationTask.compare).init(allocator, {}),
            .queue_mutex = .{},
            .queue_cond = .{},
            .shutdown = std.atomic.Value(bool).init(false),
            .pending_count = std.atomic.Value(usize).init(0),
        };
    }
    
    pub fn deinit(self: *CompilationQueue) void {
        self.queue.deinit();
    }
    
    /// 提交编译任务
    /// @thread-safety GUARDED_BY(queue_mutex)
    pub fn submit(self: *CompilationQueue, task: CompilationTask) !void {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();
        
        try self.queue.add(task);
        _ = self.pending_count.fetchAdd(1, .monotonic);
        
        // 唤醒一个等待的工作线程
        self.queue_cond.signal();
    }
    
    /// 获取下一个任务（阻塞）
    /// @thread-safety GUARDED_BY(queue_mutex)
    pub fn take(self: *CompilationQueue) ?CompilationTask {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();
        
        while (true) {
            // 检查是否关闭
            if (self.shutdown.load(.monotonic)) {
                return null;
            }
            
            // 尝试获取任务
            if (self.queue.removeOrNull()) |task| {
                _ = self.pending_count.fetchSub(1, .monotonic);
                return task;
            }
            
            // 没有任务，等待
            self.queue_cond.wait(&self.queue_mutex);
        }
    }
    
    /// 尝试获取任务（非阻塞）
    /// @thread-safety GUARDED_BY(queue_mutex)
    pub fn tryTake(self: *CompilationQueue) ?CompilationTask {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();
        
        if (self.queue.removeOrNull()) |task| {
            _ = self.pending_count.fetchSub(1, .monotonic);
            return task;
        }
        
        return null;
    }
    
    /// 获取队列大小
    pub fn size(self: *CompilationQueue) usize {
        return self.pending_count.load(.monotonic);
    }
    
    /// 关闭队列
    pub fn shutdown_queue(self: *CompilationQueue) void {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();
        
        self.shutdown.store(true, .monotonic);
        
        // 唤醒所有等待的线程
        self.queue_cond.broadcast();
    }
};

/// 工作线程
const WorkerThread = struct {
    thread: std.Thread,
    id: usize,
    compiler: *ParallelCompiler,
    
    /// 工作线程主循环
    fn run(self: *WorkerThread) void {
        while (true) {
            // 获取任务
            const task = self.compiler.queue.take() orelse break;
            
            // 执行编译
            _ = self.compiler.compileTask(task) catch |err| {
                std.debug.print("Worker {d}: 编译失败: {}\n", .{self.id, err});
            };
        }
    }
};

/// 并行 JIT 编译器统计
pub const ParallelCompilerStats = struct {
    total_tasks: std.atomic.Value(u64),
    completed_tasks: std.atomic.Value(u64),
    failed_tasks: std.atomic.Value(u64),
    total_compile_time_ns: std.atomic.Value(u64),
    cache_hits: std.atomic.Value(u64),
    cache_misses: std.atomic.Value(u64),
    
    pub fn init() ParallelCompilerStats {
        return .{
            .total_tasks = std.atomic.Value(u64).init(0),
            .completed_tasks = std.atomic.Value(u64).init(0),
            .failed_tasks = std.atomic.Value(u64).init(0),
            .total_compile_time_ns = std.atomic.Value(u64).init(0),
            .cache_hits = std.atomic.Value(u64).init(0),
            .cache_misses = std.atomic.Value(u64).init(0),
        };
    }
    
    pub fn recordTask(self: *ParallelCompilerStats) void {
        _ = self.total_tasks.fetchAdd(1, .monotonic);
    }
    
    pub fn recordCompletion(self: *ParallelCompilerStats, compile_time_ns: u64) void {
        _ = self.completed_tasks.fetchAdd(1, .monotonic);
        _ = self.total_compile_time_ns.fetchAdd(compile_time_ns, .monotonic);
    }
    
    pub fn recordFailure(self: *ParallelCompilerStats) void {
        _ = self.failed_tasks.fetchAdd(1, .monotonic);
    }
    
    pub fn recordCacheHit(self: *ParallelCompilerStats) void {
        _ = self.cache_hits.fetchAdd(1, .monotonic);
    }
    
    pub fn recordCacheMiss(self: *ParallelCompilerStats) void {
        _ = self.cache_misses.fetchAdd(1, .monotonic);
    }
    
    pub fn getAverageCompileTime(self: *ParallelCompilerStats) u64 {
        const completed = self.completed_tasks.load(.monotonic);
        if (completed == 0) return 0;
        
        const total_time = self.total_compile_time_ns.load(.monotonic);
        return total_time / completed;
    }
    
    pub fn getCacheHitRate(self: *ParallelCompilerStats) f64 {
        const hits = self.cache_hits.load(.monotonic);
        const misses = self.cache_misses.load(.monotonic);
        const total = hits + misses;
        
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(total));
    }
    
    pub fn printReport(self: *ParallelCompilerStats) void {
        const total = self.total_tasks.load(.monotonic);
        const completed = self.completed_tasks.load(.monotonic);
        const failed = self.failed_tasks.load(.monotonic);
        const avg_time = self.getAverageCompileTime();
        const hit_rate = self.getCacheHitRate();
        
        std.debug.print("\n=== 并行 JIT 编译器统计 ===\n", .{});
        std.debug.print("总任务数: {d}\n", .{total});
        std.debug.print("已完成: {d}\n", .{completed});
        std.debug.print("失败: {d}\n", .{failed});
        std.debug.print("平均编译时间: {d} ns\n", .{avg_time});
        std.debug.print("缓存命中率: {d:.2}%\n", .{hit_rate * 100.0});
    }
};

/// 并行 JIT 编译器
/// @concurrency-model MULTI-THREADED
/// @thread-safety ATOMIC + GUARDED_BY(各自的mutex)
pub const ParallelCompiler = struct {
    allocator: std.mem.Allocator,
    code_cache: *CodeCache,
    queue: CompilationQueue,
    result_cache: ResultCache,
    workers: []WorkerThread,
    num_threads: usize,
    hotspot_detector: ?*HotspotDetector,
    fallback_manager: ?*FallbackManager,
    stats: ParallelCompilerStats,
    
    /// 初始化并行编译器
    /// @pre allocator 必须有效
    /// @pre code_cache 必须已初始化
    /// @pre num_threads > 0
    /// @post 返回初始化的并行编译器
    pub fn init(
        allocator: std.mem.Allocator,
        code_cache: *CodeCache,
        num_threads: usize,
    ) !*ParallelCompiler {
        const self = try allocator.create(ParallelCompiler);
        errdefer allocator.destroy(self);
        
        self.* = .{
            .allocator = allocator,
            .code_cache = code_cache,
            .queue = CompilationQueue.init(allocator),
            .result_cache = ResultCache.init(allocator),
            .workers = &[_]WorkerThread{},
            .num_threads = num_threads,
            .hotspot_detector = null,
            .fallback_manager = null,
            .stats = ParallelCompilerStats.init(),
        };
        
        // 创建工作线程
        self.workers = try allocator.alloc(WorkerThread, num_threads);
        errdefer allocator.free(self.workers);
        
        for (self.workers, 0..) |*worker, i| {
            worker.* = .{
                .thread = undefined,
                .id = i,
                .compiler = self,
            };
            
            worker.thread = try std.Thread.spawn(.{}, WorkerThread.run, .{worker});
        }
        
        return self;
    }
    
    /// 初始化并行编译器（带热点检测）
    pub fn initWithHotspot(
        allocator: std.mem.Allocator,
        code_cache: *CodeCache,
        num_threads: usize,
        hotspot_detector: *HotspotDetector,
    ) !*ParallelCompiler {
        const self = try init(allocator, code_cache, num_threads);
        self.hotspot_detector = hotspot_detector;
        return self;
    }
    
    /// 初始化并行编译器（带回退管理器）
    pub fn initWithFallback(
        allocator: std.mem.Allocator,
        code_cache: *CodeCache,
        num_threads: usize,
        fallback_manager: *FallbackManager,
    ) !*ParallelCompiler {
        const self = try init(allocator, code_cache, num_threads);
        self.fallback_manager = fallback_manager;
        return self;
    }
    
    /// 初始化并行编译器（完整配置）
    pub fn initFull(
        allocator: std.mem.Allocator,
        code_cache: *CodeCache,
        num_threads: usize,
        hotspot_detector: *HotspotDetector,
        fallback_manager: *FallbackManager,
    ) !*ParallelCompiler {
        const self = try init(allocator, code_cache, num_threads);
        self.hotspot_detector = hotspot_detector;
        self.fallback_manager = fallback_manager;
        return self;
    }
    
    /// 清理资源
    pub fn deinit(self: *ParallelCompiler) void {
        // 关闭队列
        self.queue.shutdown_queue();
        
        // 等待所有工作线程完成
        for (self.workers) |*worker| {
            worker.thread.join();
        }
        
        // 释放资源
        self.allocator.free(self.workers);
        self.queue.deinit();
        self.result_cache.deinit();
        self.allocator.destroy(self);
    }
    
    /// 提交编译任务（异步）
    /// @pre func 必须有效
    /// @post 任务被添加到队列
    pub fn submitAsync(
        self: *ParallelCompiler,
        func: *const CompiledFunc,
        type_profile: ?*const anyopaque,
        osr_ip: ?usize,
        priority: u8,
    ) !void {
        // 检查缓存
        if (self.result_cache.get(func.name)) |_| {
            self.stats.recordCacheHit();
            return; // 已经编译过
        }
        
        self.stats.recordCacheMiss();
        self.stats.recordTask();
        
        const task = CompilationTask{
            .func = func,
            .type_profile = type_profile,
            .osr_ip = osr_ip,
            .priority = priority,
            .timestamp = std.time.nanoTimestamp(),
        };
        
        try self.queue.submit(task);
    }
    
    /// 编译任务（同步）
    /// @pre func 必须有效
    /// @post 返回编译结果
    pub fn compileSync(
        self: *ParallelCompiler,
        func: *const CompiledFunc,
        type_profile: ?*const anyopaque,
        osr_ip: ?usize,
    ) !CompilationResult {
        // 检查缓存
        if (self.result_cache.get(func.name)) |result| {
            self.stats.recordCacheHit();
            return result;
        }
        
        self.stats.recordCacheMiss();
        self.stats.recordTask();
        
        const task = CompilationTask{
            .func = func,
            .type_profile = type_profile,
            .osr_ip = osr_ip,
            .priority = 255, // 最高优先级
            .timestamp = std.time.nanoTimestamp(),
        };
        
        return try self.compileTask(task);
    }
    
    /// 执行编译任务
    /// @pre task 必须有效
    /// @post 返回编译结果并更新缓存
    fn compileTask(self: *ParallelCompiler, task: CompilationTask) !CompilationResult {
        const start_time = std.time.nanoTimestamp();
        
        // 创建编译器实例
        var compiler = Compiler.init(self.allocator);
        defer compiler.deinit();
        
        // 设置热点检测器和回退管理器
        if (self.hotspot_detector) |detector| {
            compiler.hotspot_detector = detector;
        }
        if (self.fallback_manager) |manager| {
            compiler.fallback_manager = manager;
        }
        
        // 执行编译
        const jit_result = compiler.compile(
            self.code_cache,
            task.func,
            task.type_profile orelse @as(*const anyopaque, @ptrCast(&[_]u8{})),
            task.osr_ip,
        ) catch |err| {
            const end_time = std.time.nanoTimestamp();
            const compile_time = @as(u64, @intCast(end_time - start_time));
            
            self.stats.recordFailure();
            
            const error_msg = try std.fmt.allocPrint(
                self.allocator,
                "编译失败: {}",
                .{err},
            );
            
            const result = CompilationResult{
                .func_name = task.func.name,
                .code = undefined,
                .osr_entry_offset = 0,
                .compile_time_ns = compile_time,
                .success = false,
                .error_msg = error_msg,
            };
            
            try self.result_cache.put(task.func.name, result);
            return result;
        };
        
        const end_time = std.time.nanoTimestamp();
        const compile_time = @as(u64, @intCast(end_time - start_time));
        
        self.stats.recordCompletion(compile_time);
        
        const result = if (jit_result) |jr| CompilationResult{
            .func_name = task.func.name,
            .code = jr.code,
            .osr_entry_offset = jr.osr_entry_offset,
            .compile_time_ns = compile_time,
            .success = true,
            .error_msg = null,
        } else CompilationResult{
            .func_name = task.func.name,
            .code = undefined,
            .osr_entry_offset = 0,
            .compile_time_ns = compile_time,
            .success = false,
            .error_msg = try self.allocator.dupe(u8, "未编译（不是热点函数）"),
        };
        
        try self.result_cache.put(task.func.name, result);
        return result;
    }
    
    /// 等待所有任务完成
    pub fn waitAll(self: *ParallelCompiler) void {
        while (self.queue.size() > 0) {
            std.time.sleep(1_000_000); // 1ms
        }
    }
    
    /// 获取统计信息
    pub fn getStats(self: *ParallelCompiler) ParallelCompilerStats {
        return self.stats;
    }
    
    /// 打印统计报告
    pub fn printStats(self: *ParallelCompiler) void {
        self.stats.printReport();
    }
    
    /// 清空缓存
    pub fn clearCache(self: *ParallelCompiler) void {
        self.result_cache.clear();
    }
};

// ============================================================================
// 测试
// ============================================================================

test "ParallelCompiler: 基本功能" {
    const testing = std.testing;
    
    // 创建代码缓存
    var code_cache = try CodeCache.init(testing.allocator, 1024 * 1024);
    defer code_cache.deinit();
    
    // 创建并行编译器（2个线程）
    var parallel_compiler = try ParallelCompiler.init(
        testing.allocator,
        &code_cache,
        2,
    );
    defer parallel_compiler.deinit();
    
    // 验证初始化
    try testing.expectEqual(@as(usize, 2), parallel_compiler.num_threads);
    try testing.expectEqual(@as(usize, 2), parallel_compiler.workers.len);
}

test "ParallelCompiler: 任务队列" {
    const testing = std.testing;
    
    var queue = CompilationQueue.init(testing.allocator);
    defer queue.deinit();
    
    // 创建测试函数
    const test_func = CompiledFunc{
        .name = "test",
        .code = &[_]u8{},
        .constants = &[_]u8{},
        .local_count = 0,
        .param_count = 0,
    };
    
    // 提交任务
    const task1 = CompilationTask{
        .func = &test_func,
        .type_profile = null,
        .osr_ip = null,
        .priority = 100,
        .timestamp = std.time.nanoTimestamp(),
    };
    
    try queue.submit(task1);
    try testing.expectEqual(@as(usize, 1), queue.size());
    
    // 获取任务
    const task2 = queue.tryTake();
    try testing.expect(task2 != null);
    try testing.expectEqual(@as(usize, 0), queue.size());
}

test "ParallelCompiler: 结果缓存" {
    const testing = std.testing;
    
    var cache = ResultCache.init(testing.allocator);
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
    try testing.expect(cached != null);
    try testing.expectEqualStrings("test", cached.?.func_name);
    
    // 验证命中率
    _ = cache.get("test"); // 再次命中
    _ = cache.get("nonexistent"); // 未命中
    
    const hit_rate = cache.getHitRate();
    try testing.expect(hit_rate > 0.0);
}

test "ParallelCompiler: 优先级队列" {
    const testing = std.testing;
    
    var queue = CompilationQueue.init(testing.allocator);
    defer queue.deinit();
    
    const test_func = CompiledFunc{
        .name = "test",
        .code = &[_]u8{},
        .constants = &[_]u8{},
        .local_count = 0,
        .param_count = 0,
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
    try testing.expect(first != null);
    try testing.expectEqual(@as(u8, 200), first.?.priority);
}
