const std = @import("std");

/// 高级性能监控系统
/// 实现性能指标采集、热点检测、执行统计、内存监控

// ============================================================================
// 性能指标采集
// ============================================================================

pub const PerformanceMonitor = struct {
    allocator: std.mem.Allocator,
    metrics: MetricsCollector,
    hotspot_detector: HotspotDetector,
    execution_stats: ExecutionStats,
    memory_stats: MemoryStats,
    profiler: SamplingProfiler,
    start_time: i64,

    pub fn init(allocator: std.mem.Allocator) PerformanceMonitor {
        return .{
            .allocator = allocator,
            .metrics = MetricsCollector.init(allocator),
            .hotspot_detector = HotspotDetector.init(allocator),
            .execution_stats = ExecutionStats.init(),
            .memory_stats = MemoryStats.init(),
            .profiler = SamplingProfiler.init(allocator),
            .start_time = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *PerformanceMonitor) void {
        self.metrics.deinit();
        self.hotspot_detector.deinit();
        self.profiler.deinit();
    }

    /// 记录函数调用
    pub fn recordFunctionCall(self: *PerformanceMonitor, func_name: []const u8, duration_ns: u64) !void {
        try self.hotspot_detector.recordCall(func_name, duration_ns);
        self.execution_stats.total_function_calls += 1;
        self.execution_stats.total_execution_time_ns += duration_ns;
    }

    /// 记录内存分配
    pub fn recordAllocation(self: *PerformanceMonitor, size: usize) void {
        self.memory_stats.total_allocations += 1;
        self.memory_stats.total_bytes_allocated += size;
        self.memory_stats.current_memory_usage += size;
        if (self.memory_stats.current_memory_usage > self.memory_stats.peak_memory_usage) {
            self.memory_stats.peak_memory_usage = self.memory_stats.current_memory_usage;
        }
    }

    /// 记录内存释放
    pub fn recordDeallocation(self: *PerformanceMonitor, size: usize) void {
        self.memory_stats.total_deallocations += 1;
        if (self.memory_stats.current_memory_usage >= size) {
            self.memory_stats.current_memory_usage -= size;
        }
    }

    /// 记录GC事件
    pub fn recordGCEvent(self: *PerformanceMonitor, gc_time_ns: u64, objects_collected: usize, bytes_freed: usize) void {
        self.memory_stats.gc_events += 1;
        self.memory_stats.total_gc_time_ns += gc_time_ns;
        self.memory_stats.objects_collected += objects_collected;
        self.memory_stats.bytes_freed_by_gc += bytes_freed;
    }

    /// 生成性能报告
    pub fn generateReport(self: *PerformanceMonitor) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        const uptime = std.time.timestamp() - self.start_time;

        try writer.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
        try writer.print("║            性能监控报告 (Performance Monitor Report)           ║\n", .{});
        try writer.print("╠══════════════════════════════════════════════════════════════╣\n", .{});
        try writer.print("║ 运行时间: {} 秒                                               \n", .{uptime});
        try writer.print("╠══════════════════════════════════════════════════════════════╣\n", .{});

        // 执行统计
        try writer.print("║ [执行统计]                                                    \n", .{});
        try writer.print("║   函数调用总数: {}                                            \n", .{self.execution_stats.total_function_calls});
        try writer.print("║   总执行时间: {} ns                                           \n", .{self.execution_stats.total_execution_time_ns});
        try writer.print("║   字节码指令数: {}                                            \n", .{self.execution_stats.bytecode_instructions_executed});
        try writer.print("║   异常抛出数: {}                                              \n", .{self.execution_stats.exceptions_thrown});
        try writer.print("╠══════════════════════════════════════════════════════════════╣\n", .{});

        // 内存统计
        try writer.print("║ [内存统计]                                                    \n", .{});
        try writer.print("║   当前内存使用: {} bytes                                      \n", .{self.memory_stats.current_memory_usage});
        try writer.print("║   峰值内存使用: {} bytes                                      \n", .{self.memory_stats.peak_memory_usage});
        try writer.print("║   总分配次数: {}                                              \n", .{self.memory_stats.total_allocations});
        try writer.print("║   总释放次数: {}                                              \n", .{self.memory_stats.total_deallocations});
        try writer.print("║   GC事件数: {}                                                \n", .{self.memory_stats.gc_events});
        try writer.print("║   GC总耗时: {} ns                                             \n", .{self.memory_stats.total_gc_time_ns});
        try writer.print("╠══════════════════════════════════════════════════════════════╣\n", .{});

        // 热点函数
        try writer.print("║ [热点函数 Top 5]                                              \n", .{});
        const hotspots = self.hotspot_detector.getTopHotspots(5);
        for (hotspots, 0..) |hs, i| {
            try writer.print("║   {}: {} - {} 次调用, {} ns 总耗时\n", .{ i + 1, hs.name, hs.call_count, hs.total_time_ns });
        }
        try writer.print("╚══════════════════════════════════════════════════════════════╝\n", .{});

        return buffer.toOwnedSlice();
    }

    /// 获取执行统计
    pub fn getExecutionStats(self: *const PerformanceMonitor) ExecutionStats {
        return self.execution_stats;
    }

    /// 获取内存统计
    pub fn getMemoryStats(self: *const PerformanceMonitor) MemoryStats {
        return self.memory_stats;
    }

    /// 检查是否需要JIT编译
    pub fn shouldJIT(self: *PerformanceMonitor, func_name: []const u8) bool {
        return self.hotspot_detector.isHotspot(func_name);
    }
};

// ============================================================================
// 指标收集器
// ============================================================================

pub const MetricsCollector = struct {
    allocator: std.mem.Allocator,
    metrics: std.StringHashMapUnmanaged(Metric),
    history: std.ArrayListUnmanaged(MetricSnapshot),

    pub const Metric = struct {
        name: []const u8,
        value: f64,
        unit: []const u8,
        timestamp: i64,
        metric_type: MetricType,
    };

    pub const MetricType = enum {
        counter,
        gauge,
        histogram,
        timer,
    };

    pub const MetricSnapshot = struct {
        timestamp: i64,
        metrics: []Metric,
    };

    pub fn init(allocator: std.mem.Allocator) MetricsCollector {
        return .{
            .allocator = allocator,
            .metrics = .{},
            .history = .{},
        };
    }

    pub fn deinit(self: *MetricsCollector) void {
        self.metrics.deinit(self.allocator);
        self.history.deinit(self.allocator);
    }

    pub fn recordMetric(self: *MetricsCollector, name: []const u8, value: f64, unit: []const u8, metric_type: MetricType) !void {
        try self.metrics.put(self.allocator, name, .{
            .name = name,
            .value = value,
            .unit = unit,
            .timestamp = std.time.timestamp(),
            .metric_type = metric_type,
        });
    }

    pub fn incrementCounter(self: *MetricsCollector, name: []const u8) !void {
        if (self.metrics.getPtr(name)) |metric| {
            metric.value += 1;
            metric.timestamp = std.time.timestamp();
        } else {
            try self.recordMetric(name, 1, "count", .counter);
        }
    }

    pub fn getMetric(self: *const MetricsCollector, name: []const u8) ?Metric {
        return self.metrics.get(name);
    }
};

// ============================================================================
// 热点检测器
// ============================================================================

pub const HotspotDetector = struct {
    allocator: std.mem.Allocator,
    function_stats: std.StringHashMapUnmanaged(FunctionStats),
    hotspot_threshold: HotspotThreshold,

    pub const FunctionStats = struct {
        name: []const u8,
        call_count: u64,
        total_time_ns: u64,
        avg_time_ns: u64,
        is_hot: bool,
        last_call_time: i64,
    };

    pub const HotspotThreshold = struct {
        min_call_count: u64 = 1000,
        min_total_time_ns: u64 = 1_000_000,
        min_avg_time_ns: u64 = 1000,
    };

    pub fn init(allocator: std.mem.Allocator) HotspotDetector {
        return .{
            .allocator = allocator,
            .function_stats = .{},
            .hotspot_threshold = .{},
        };
    }

    pub fn deinit(self: *HotspotDetector) void {
        self.function_stats.deinit(self.allocator);
    }

    pub fn recordCall(self: *HotspotDetector, func_name: []const u8, duration_ns: u64) !void {
        if (self.function_stats.getPtr(func_name)) |stats| {
            stats.call_count += 1;
            stats.total_time_ns += duration_ns;
            stats.avg_time_ns = stats.total_time_ns / stats.call_count;
            stats.last_call_time = std.time.timestamp();
            stats.is_hot = self.checkHotspot(stats.*);
        } else {
            try self.function_stats.put(self.allocator, func_name, .{
                .name = func_name,
                .call_count = 1,
                .total_time_ns = duration_ns,
                .avg_time_ns = duration_ns,
                .is_hot = false,
                .last_call_time = std.time.timestamp(),
            });
        }
    }

    fn checkHotspot(self: *const HotspotDetector, stats: FunctionStats) bool {
        return stats.call_count >= self.hotspot_threshold.min_call_count or
            stats.total_time_ns >= self.hotspot_threshold.min_total_time_ns;
    }

    pub fn isHotspot(self: *const HotspotDetector, func_name: []const u8) bool {
        if (self.function_stats.get(func_name)) |stats| {
            return stats.is_hot;
        }
        return false;
    }

    pub fn getTopHotspots(self: *const HotspotDetector, count: usize) []const FunctionStats {
        _ = count;
        // 简化实现：返回所有热点函数
        var hotspots: [5]FunctionStats = undefined;
        var hotspot_count: usize = 0;

        var iter = self.function_stats.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.is_hot and hotspot_count < 5) {
                hotspots[hotspot_count] = entry.value_ptr.*;
                hotspot_count += 1;
            }
        }

        return hotspots[0..hotspot_count];
    }

    pub fn setThreshold(self: *HotspotDetector, threshold: HotspotThreshold) void {
        self.hotspot_threshold = threshold;
    }
};

// ============================================================================
// 执行统计
// ============================================================================

pub const ExecutionStats = struct {
    total_function_calls: u64,
    total_execution_time_ns: u64,
    bytecode_instructions_executed: u64,
    exceptions_thrown: u64,
    cache_hits: u64,
    cache_misses: u64,
    loop_iterations: u64,
    branch_taken: u64,
    branch_not_taken: u64,

    pub fn init() ExecutionStats {
        return .{
            .total_function_calls = 0,
            .total_execution_time_ns = 0,
            .bytecode_instructions_executed = 0,
            .exceptions_thrown = 0,
            .cache_hits = 0,
            .cache_misses = 0,
            .loop_iterations = 0,
            .branch_taken = 0,
            .branch_not_taken = 0,
        };
    }

    pub fn reset(self: *ExecutionStats) void {
        self.* = ExecutionStats.init();
    }

    pub fn getCacheHitRate(self: *const ExecutionStats) f64 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total));
    }

    pub fn getBranchPredictionRate(self: *const ExecutionStats) f64 {
        const total = self.branch_taken + self.branch_not_taken;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.branch_taken)) / @as(f64, @floatFromInt(total));
    }
};

// ============================================================================
// 内存统计
// ============================================================================

pub const MemoryStats = struct {
    current_memory_usage: usize,
    peak_memory_usage: usize,
    total_allocations: usize,
    total_deallocations: usize,
    total_bytes_allocated: usize,
    gc_events: usize,
    total_gc_time_ns: u64,
    objects_collected: usize,
    bytes_freed_by_gc: usize,

    pub fn init() MemoryStats {
        return .{
            .current_memory_usage = 0,
            .peak_memory_usage = 0,
            .total_allocations = 0,
            .total_deallocations = 0,
            .total_bytes_allocated = 0,
            .gc_events = 0,
            .total_gc_time_ns = 0,
            .objects_collected = 0,
            .bytes_freed_by_gc = 0,
        };
    }

    pub fn getFragmentationRate(self: *const MemoryStats) f64 {
        if (self.total_bytes_allocated == 0) return 0.0;
        const freed = self.bytes_freed_by_gc;
        return @as(f64, @floatFromInt(freed)) / @as(f64, @floatFromInt(self.total_bytes_allocated));
    }

    pub fn getAverageGCTime(self: *const MemoryStats) u64 {
        if (self.gc_events == 0) return 0;
        return self.total_gc_time_ns / self.gc_events;
    }
};

// ============================================================================
// 采样分析器
// ============================================================================

pub const SamplingProfiler = struct {
    allocator: std.mem.Allocator,
    samples: std.ArrayListUnmanaged(Sample),
    call_graph: CallGraph,
    is_running: bool,
    sample_interval_ns: u64,

    pub const Sample = struct {
        timestamp: i64,
        function_name: []const u8,
        stack_depth: usize,
        cpu_time_ns: u64,
        memory_usage: usize,
    };

    pub const CallGraph = struct {
        nodes: std.StringHashMapUnmanaged(CallNode),
        edges: std.ArrayListUnmanaged(CallEdge),

        pub const CallNode = struct {
            function_name: []const u8,
            total_time_ns: u64,
            self_time_ns: u64,
            call_count: u64,
        };

        pub const CallEdge = struct {
            from: []const u8,
            to: []const u8,
            call_count: u64,
            total_time_ns: u64,
        };

        pub fn init() CallGraph {
            return .{
                .nodes = .{},
                .edges = .{},
            };
        }

        pub fn deinit(self: *CallGraph, allocator: std.mem.Allocator) void {
            self.nodes.deinit(allocator);
            self.edges.deinit(allocator);
        }
    };

    pub fn init(allocator: std.mem.Allocator) SamplingProfiler {
        return .{
            .allocator = allocator,
            .samples = .{},
            .call_graph = CallGraph.init(),
            .is_running = false,
            .sample_interval_ns = 1_000_000, // 1ms
        };
    }

    pub fn deinit(self: *SamplingProfiler) void {
        self.samples.deinit(self.allocator);
        self.call_graph.deinit(self.allocator);
    }

    pub fn start(self: *SamplingProfiler) void {
        self.is_running = true;
    }

    pub fn stop(self: *SamplingProfiler) void {
        self.is_running = false;
    }

    pub fn takeSample(self: *SamplingProfiler, function_name: []const u8, stack_depth: usize, cpu_time_ns: u64, memory_usage: usize) !void {
        if (!self.is_running) return;

        try self.samples.append(self.allocator, .{
            .timestamp = std.time.timestamp(),
            .function_name = function_name,
            .stack_depth = stack_depth,
            .cpu_time_ns = cpu_time_ns,
            .memory_usage = memory_usage,
        });
    }

    pub fn generateFlameGraph(self: *const SamplingProfiler) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        try writer.print("Flame Graph Data:\n", .{});
        for (self.samples.items) |sample| {
            try writer.print("{s};{};{}\n", .{ sample.function_name, sample.stack_depth, sample.cpu_time_ns });
        }

        return buffer.toOwnedSlice();
    }
};

// ============================================================================
// 性能优化建议生成器
// ============================================================================

pub const OptimizationAdvisor = struct {
    allocator: std.mem.Allocator,

    pub const Suggestion = struct {
        category: Category,
        priority: Priority,
        description: []const u8,
        expected_improvement: []const u8,
    };

    pub const Category = enum {
        memory,
        cpu,
        io,
        algorithm,
        caching,
    };

    pub const Priority = enum {
        low,
        medium,
        high,
        critical,
    };

    pub fn init(allocator: std.mem.Allocator) OptimizationAdvisor {
        return .{
            .allocator = allocator,
        };
    }

    pub fn analyze(self: *OptimizationAdvisor, monitor: *const PerformanceMonitor) ![]Suggestion {
        var suggestions = std.ArrayList(Suggestion).init(self.allocator);

        const memory_stats = monitor.getMemoryStats();
        const exec_stats = monitor.getExecutionStats();

        // 内存优化建议
        if (memory_stats.getFragmentationRate() > 0.3) {
            try suggestions.append(.{
                .category = .memory,
                .priority = .high,
                .description = "高内存碎片率，建议启用内存压缩",
                .expected_improvement = "减少10-30%内存使用",
            });
        }

        // 缓存优化建议
        if (exec_stats.getCacheHitRate() < 0.8) {
            try suggestions.append(.{
                .category = .caching,
                .priority = .medium,
                .description = "缓存命中率较低，建议优化缓存策略",
                .expected_improvement = "提升20-50%性能",
            });
        }

        // GC优化建议
        if (memory_stats.getAverageGCTime() > 10_000_000) { // > 10ms
            try suggestions.append(.{
                .category = .memory,
                .priority = .high,
                .description = "GC耗时过长，建议启用增量GC",
                .expected_improvement = "减少GC停顿时间50%",
            });
        }

        return suggestions.toOwnedSlice();
    }
};

// ============================================================================
// 测试
// ============================================================================

test "performance monitor basic" {
    var monitor = PerformanceMonitor.init(std.testing.allocator);
    defer monitor.deinit();

    try monitor.recordFunctionCall("test_func", 1000);
    monitor.recordAllocation(1024);
    monitor.recordDeallocation(512);

    const exec_stats = monitor.getExecutionStats();
    try std.testing.expect(exec_stats.total_function_calls == 1);

    const mem_stats = monitor.getMemoryStats();
    try std.testing.expect(mem_stats.total_allocations == 1);
    try std.testing.expect(mem_stats.current_memory_usage == 512);
}

test "hotspot detector" {
    var detector = HotspotDetector.init(std.testing.allocator);
    defer detector.deinit();

    detector.setThreshold(.{ .min_call_count = 3 });

    try detector.recordCall("hot_func", 100);
    try detector.recordCall("hot_func", 100);
    try detector.recordCall("hot_func", 100);

    try std.testing.expect(detector.isHotspot("hot_func"));
    try std.testing.expect(!detector.isHotspot("cold_func"));
}

test "metrics collector" {
    var collector = MetricsCollector.init(std.testing.allocator);
    defer collector.deinit();

    try collector.recordMetric("cpu_usage", 75.5, "%", .gauge);
    try collector.incrementCounter("requests");
    try collector.incrementCounter("requests");

    const cpu_metric = collector.getMetric("cpu_usage");
    try std.testing.expect(cpu_metric != null);
    try std.testing.expect(cpu_metric.?.value == 75.5);

    const req_metric = collector.getMetric("requests");
    try std.testing.expect(req_metric != null);
    try std.testing.expect(req_metric.?.value == 2);
}

test "execution stats" {
    var stats = ExecutionStats.init();

    stats.cache_hits = 80;
    stats.cache_misses = 20;

    const hit_rate = stats.getCacheHitRate();
    try std.testing.expect(hit_rate == 0.8);
}

test "memory stats" {
    var stats = MemoryStats.init();

    stats.total_bytes_allocated = 1000;
    stats.bytes_freed_by_gc = 300;
    stats.gc_events = 3;
    stats.total_gc_time_ns = 30000;

    const frag_rate = stats.getFragmentationRate();
    try std.testing.expect(frag_rate == 0.3);

    const avg_gc_time = stats.getAverageGCTime();
    try std.testing.expect(avg_gc_time == 10000);
}
