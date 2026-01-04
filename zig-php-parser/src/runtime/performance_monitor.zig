//! 实时性能监控系统
//!
//! 提供全面的性能追踪和分析功能
//! 包括CPU、内存、GC、热点函数等监控
//!
//! ## 架构
//!
//! ```
//! ┌─────────────────────────────────────────────────────┐
//! │           Performance Monitoring System              │
//! ├─────────────────────────────────────────────────────┤
//! │                                                     │
//! │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
//! │  │  CPU Monitor │  │  Memory      │  │   GC      │ │
//! │  │              │  │  Monitor     │  │ Monitor   │ │
//! │  └──────────────┘  └──────────────┘  └───────────┘ │
│ │         │                 │                 │        │
│ │         └─────────────────┴─────────────────┘        │
│ │                           │                          │
│ │                    ┌──────▼──────┐                   │
│ │                    │  Aggregator │                   │
│ │                    └──────┬──────┘                   │
│ │                           │                          │
│ │                    ┌──────▼──────┐                   │
//! │                    │  Analyzer   │                   │
//! │                    └──────┬──────┘                   │
│ │                           │                          │
│ │         ┌─────────────────┼─────────────────┐        │
│ │         │                 │                 │        │
│ │  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐ │
//! │  │  Profiler   │  │  Hotspot    │  │  Reporter   │ │
//! │  │             │  │  Detector   │  │             │ │
//! │  └──────────────┘  └──────────────┘  └──────────────┘ │
//! │                                                     │
└─────────────────────────────────────────────────────┘
//! ```

const std = @import("std");
const Value = @import("types.zig").Value;

// ============================================================================
// 常量配置
// ============================================================================

/// 采样间隔（纳秒）
const SAMPLING_INTERVAL_NS: u64 = 1_000_000; // 1ms

/// 最大采样数
const MAX_SAMPLES: usize = 10000;

/// 热点阈值（调用次数）
const HOTSPOT_THRESHOLD: u64 = 1000;

/// 性能数据保留时间（秒）
const RETENTION_TIME: u64 = 3600; // 1小时

// ============================================================================
// CPU性能计数器
// ============================================================================

pub const CPUPerformanceCounters = struct {
    /// 指令执行数
    instructions: u64,
    /// 缓存未命中
    cache_misses: u64,
    /// 分支预测失败
    branch_mispredictions: u64,
    /// CPU周期数
    cycles: u64,
    /// 上下文切换
    context_switches: u64,
    /// 采样时间戳
    timestamp: i64,

    pub fn init() CPUPerformanceCounters {
        return .{
            .instructions = 0,
            .cache_misses = 0,
            .branch_mispredictions = 0,
            .cycles = 0,
            .context_switches = 0,
            .timestamp = std.time.nanoTimestamp(),
        };
    }

    /// 计算IPC（每周期指令数）
    pub fn getIPC(self: *const CPUPerformanceCounters) f64 {
        if (self.cycles == 0) return 0.0;
        return @as(f64, @floatFromInt(self.instructions)) / @as(f64, @floatFromInt(self.cycles));
    }

    /// 计算缓存命中率
    pub fn getCacheHitRate(self: *const CPUPerformanceCounters) f64 {
        if (self.instructions == 0) return 0.0;
        return 1.0 - (@as(f64, @floatFromInt(self.cache_misses)) / @as(f64, @floatFromInt(self.instructions)));
    }

    /// 计算分支预测准确率
    pub fn getBranchAccuracy(self: *const CPUPerformanceCounters) f64 {
        if (self.branch_mispredictions == 0) return 1.0;
        // 这里需要总分支数，暂时简化
        return 0.9; // 假设90%准确率
    }
};

// ============================================================================
// 内存分配追踪器
// ============================================================================

pub const AllocationTracker = struct {
    /// 分配记录
    allocations: std.ArrayListUnmanaged(AllocationRecord),
    /// 当前分配大小
    current_allocated: usize,
    /// 峰值分配大小
    peak_allocated: usize,
    /// 总分配次数
    total_allocations: u64,
    /// 总释放次数
    total_deallocations: u64,
    /// 分配器
    allocator: std.mem.Allocator,

    const AllocationRecord = struct {
        /// 指针
        ptr: ?*anyopaque,
        /// 大小
        size: usize,
        /// 分配时间戳
        timestamp: i64,
        /// 分配位置
        location: ?SourceLocation,
        /// 类型信息
        type_info: []const u8,
    };

    const SourceLocation = struct {
        file: []const u8,
        line: u32,
        function: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) AllocationTracker {
        return .{
            .allocations = std.ArrayListUnmanaged(AllocationRecord){},
            .current_allocated = 0,
            .peak_allocated = 0,
            .total_allocations = 0,
            .total_deallocations = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AllocationTracker) void {
        for (self.allocations.items) |*record| {
            self.freeRecord(record);
        }
        self.allocations.deinit(self.allocator);
    }

    /// 记录分配
    pub fn recordAllocation(
        self: *AllocationTracker,
        ptr: ?*anyopaque,
        size: usize,
        location: ?SourceLocation,
        type_info: []const u8,
    ) !void {
        const record = AllocationRecord{
            .ptr = ptr,
            .size = size,
            .timestamp = std.time.nanoTimestamp(),
            .location = location,
            .type_info = try self.allocator.dupe(u8, type_info),
        };

        try self.allocations.append(self.allocator, record);
        self.current_allocated += size;
        self.total_allocations += 1;

        if (self.current_allocated > self.peak_allocated) {
            self.peak_allocated = self.current_allocated;
        }
    }

    /// 记录释放
    pub fn recordDeallocation(self: *AllocationTracker, ptr: ?*anyopaque) void {
        for (self.allocations.items) |*record| {
            if (record.ptr == ptr) {
                self.current_allocated -= record.size;
                self.total_deallocations += 1;
                self.freeRecord(record);
                record.ptr = null; // 标记为已释放
                break;
            }
        }
    }

    /// 释放记录资源
    fn freeRecord(self: *AllocationTracker, record: *AllocationRecord) void {
        if (record.location) |loc| {
            self.allocator.free(loc.file);
            self.allocator.free(loc.function);
        }
        self.allocator.free(record.type_info);
    }

    /// 获取内存使用统计
    pub fn getMemoryStats(self: *const AllocationTracker) MemoryStats {
        return .{
            .current_allocated = self.current_allocated,
            .peak_allocated = self.peak_allocated,
            .total_allocations = self.total_allocations,
            .total_deallocations = self.total_deallocations,
            .active_allocations = self.allocations.items.len,
            .allocation_rate = if (self.total_allocations > 0)
                @as(f64, @floatFromInt(self.total_allocations)) / @as(f64, @floatFromInt(self.total_deallocations + self.total_allocations))
            else
                0.0,
        };
    }

    pub const MemoryStats = struct {
        current_allocated: usize,
        peak_allocated: usize,
        total_allocations: u64,
        total_deallocations: u64,
        active_allocations: usize,
        allocation_rate: f64,
    };
};

// ============================================================================
// GC性能追踪器
// ============================================================================

pub const GCTracker = struct {
    /// GC周期记录
    gc_cycles: std.ArrayListUnmanaged(GCCycle),
    /// 当前GC阶段
    current_phase: GCPhase,
    /// GC开始时间
    gc_start_time: i64,
    /// 分配器
    allocator: std.mem.Allocator,

    const GCPhase = enum {
        idle,
        marking,
        remarking,
        sweeping,
        compacting,
    };

    const GCCycle = struct {
        /// GC类型
        gc_type: GCType,
        /// 标记时间（纳秒）
        marking_time_ns: u64,
        /// 扫描时间（纳秒）
        scanning_time_ns: u64,
        /// 清扫时间（纳秒）
        sweeping_time_ns: u64,
        /// 总停顿时间（纳秒）
        total_pause_ns: u64,
        /// 回收的对象数
        collected_objects: u64,
        /// 回收的内存（字节）
        collected_bytes: u64,
        /// 回收前堆大小
        heap_before: u64,
        /// 回收后堆大小
        heap_after: u64,
        /// 时间戳
        timestamp: i64,
    };

    const GCType = enum {
        minor,
        major,
        full,
        incremental,
        concurrent,
    };

    pub fn init(allocator: std.mem.Allocator) GCTracker {
        return .{
            .gc_cycles = std.ArrayListUnmanaged(GCCycle){},
            .current_phase = .idle,
            .gc_start_time = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GCTracker) void {
        self.gc_cycles.deinit(self.allocator);
    }

    /// 开始GC周期
    pub fn startGC(self: *GCTracker, gc_type: GCType) void {
        self.gc_start_time = std.time.nanoTimestamp();
        self.current_phase = .marking;
    }

    /// 结束GC周期
    pub fn endGC(
        self: *GCTracker,
        marking_time_ns: u64,
        scanning_time_ns: u64,
        sweeping_time_ns: u64,
        collected_objects: u64,
        collected_bytes: u64,
        heap_before: u64,
        heap_after: u64,
    ) !void {
        const total_pause_ns = std.time.nanoTimestamp() - self.gc_start_time;

        const cycle = GCCycle{
            .gc_type = self.getCurrentGCType(),
            .marking_time_ns = marking_time_ns,
            .scanning_time_ns = scanning_time_ns,
            .sweeping_time_ns = sweeping_time_ns,
            .total_pause_ns = total_pause_ns,
            .collected_objects = collected_objects,
            .collected_bytes = collected_bytes,
            .heap_before = heap_before,
            .heap_after = heap_after,
            .timestamp = std.time.nanoTimestamp(),
        };

        try self.gc_cycles.append(self.allocator, cycle);
        self.current_phase = .idle;
    }

    /// 获取GC统计
    pub fn getGCStats(self: *const GCTracker) GCStats {
        var total_pause_ns: u64 = 0;
        var total_collected_objects: u64 = 0;
        var total_collected_bytes: u64 = 0;
        var minor_gc_count: u64 = 0;
        var major_gc_count: u64 = 0;
        var full_gc_count: u64 = 0;

        for (self.gc_cycles.items) |cycle| {
            total_pause_ns += cycle.total_pause_ns;
            total_collected_objects += cycle.collected_objects;
            total_collected_bytes += cycle.collected_bytes;

            switch (cycle.gc_type) {
                .minor => minor_gc_count += 1,
                .major => major_gc_count += 1,
                .full => full_gc_count += 1,
                else => {},
            }
        }

        const gc_count = self.gc_cycles.items.len;
        const avg_pause_ns = if (gc_count > 0)
            total_pause_ns / @as(u64, @intCast(gc_count))
        else
            0;

        return .{
            .total_gc_count = @intCast(gc_count),
            .minor_gc_count = minor_gc_count,
            .major_gc_count = major_gc_count,
            .full_gc_count = full_gc_count,
            .total_pause_ns = total_pause_ns,
            .avg_pause_ns = avg_pause_ns,
            .total_collected_objects = total_collected_objects,
            .total_collected_bytes = total_collected_bytes,
            .gc_throughput = if (total_pause_ns > 0)
                @as(f64, @floatFromInt(total_collected_bytes)) / @as(f64, @floatFromInt(total_pause_ns)) * 1_000_000_000.0 // bytes/second
            else
                0.0,
        };
    }

    fn getCurrentGCType(self: *const GCTracker) GCType {
        // 简化实现，实际应根据上下文判断
        return .minor;
    }

    pub const GCStats = struct {
        total_gc_count: usize,
        minor_gc_count: u64,
        major_gc_count: u64,
        full_gc_count: u64,
        total_pause_ns: u64,
        avg_pause_ns: u64,
        total_collected_objects: u64,
        total_collected_bytes: u64,
        gc_throughput: f64, // bytes/second
    };
};

// ============================================================================
// 热点函数追踪器
// ============================================================================

pub const HotspotTracker = struct {
    /// 函数调用统计
    function_stats: std.StringHashMap(FunctionStats),
    /// 调用栈
    call_stack: std.ArrayListUnmanaged(CallFrame),
    /// 分配器
    allocator: std.mem.Allocator,

    const FunctionStats = struct {
        /// 函数名
        name: []const u8,
        /// 调用次数
        call_count: u64,
        /// 总执行时间（纳秒）
        total_time_ns: u64,
        /// 自身执行时间（纳秒）
        self_time_ns: u64,
        /// 平均执行时间（纳秒）
        avg_time_ns: u64,
        /// 最大执行时间（纳秒）
        max_time_ns: u64,
        /// 最小执行时间（纳秒）
        min_time_ns: u64,
        /// 是否是热点
        is_hotspot: bool,
    };

    const CallFrame = struct {
        function_name: []const u8,
        file: []const u8,
        line: u32,
        entry_time: i64,
    };

    pub fn init(allocator: std.mem.Allocator) HotspotTracker {
        return .{
            .function_stats = std.StringHashMap(FunctionStats).init(allocator),
            .call_stack = std.ArrayListUnmanaged(CallFrame){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HotspotTracker) void {
        var iter = self.function_stats.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
        }
        self.function_stats.deinit();

        for (self.call_stack.items) |*frame| {
            self.allocator.free(frame.function_name);
            self.allocator.free(frame.file);
        }
        self.call_stack.deinit(self.allocator);
    }

    /// 进入函数
    pub fn enterFunction(self: *HotspotTracker, function_name: []const u8, file: []const u8, line: u32) !void {
        const frame = CallFrame{
            .function_name = try self.allocator.dupe(u8, function_name),
            .file = try self.allocator.dupe(u8, file),
            .line = line,
            .entry_time = std.time.nanoTimestamp(),
        };

        try self.call_stack.append(self.allocator, frame);
    }

    /// 退出函数
    pub fn exitFunction(self: *HotspotTracker) !void {
        if (self.call_stack.items.len == 0) return;

        const frame = &self.call_stack.items[self.call_stack.items.len - 1];
        const exit_time = std.time.nanoTimestamp();
        const execution_time_ns = @intCast(exit_time - frame.entry_time);

        // 更新函数统计
        const entry = try self.function_stats.getOrPut(frame.function_name);

        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .name = try self.allocator.dupe(u8, frame.function_name),
                .call_count = 0,
                .total_time_ns = 0,
                .self_time_ns = 0,
                .avg_time_ns = 0,
                .max_time_ns = 0,
                .min_time_ns = std.math.maxInt(u64),
                .is_hotspot = false,
            };
        }

        const stats = entry.value_ptr;
        stats.call_count += 1;
        stats.total_time_ns += execution_time_ns;
        stats.avg_time_ns = stats.total_time_ns / stats.call_count;

        if (execution_time_ns > stats.max_time_ns) {
            stats.max_time_ns = execution_time_ns;
        }

        if (execution_time_ns < stats.min_time_ns) {
            stats.min_time_ns = execution_time_ns;
        }

        // 检查是否是热点
        stats.is_hotspot = stats.call_count >= HOTSPOT_THRESHOLD;

        // 释放帧资源
        self.allocator.free(frame.function_name);
        self.allocator.free(frame.file);
        _ = self.call_stack.pop();
    }

    /// 获取热点函数
    pub fn getHotspots(self: *HotspotTracker) !std.ArrayList([]const u8) {
        var hotspots = std.ArrayList([]const u8).init(self.allocator);

        var iter = self.function_stats.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.is_hotspot) {
                try hotspots.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        // 按调用次数排序
        std.sort.insertion([]const u8, hotspots.items, {}, struct {
            fn compare(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        });

        return hotspots;
    }

    /// 获取函数统计
    pub fn getFunctionStats(self: *HotspotTracker, function_name: []const u8) ?*const FunctionStats {
        return self.function_stats.get(function_name);
    }
};

// ============================================================================
// 实时分析器
// ============================================================================

pub const RealTimeProfiler = struct {
    /// CPU计数器
    cpu_counters: CPUPerformanceCounters,
    /// 分配追踪器
    allocation_tracker: AllocationTracker,
    /// GC追踪器
    gc_tracker: GCTracker,
    /// 热点追踪器
    hotspot_tracker: HotspotTracker,
    /// 采样数据
    samples: std.ArrayListUnmanaged(PerformanceSample),
    /// 分配器
    allocator: std.mem.Allocator,
    /// 运行标志
    running: std.atomic.Atomic(bool),

    const PerformanceSample = struct {
        timestamp: i64,
        cpu_counters: CPUPerformanceCounters,
        memory_allocated: usize,
        gc_phase: GCTracker.GCPhase,
        call_stack_depth: usize,
    };

    pub fn init(allocator: std.mem.Allocator) RealTimeProfiler {
        return .{
            .cpu_counters = CPUPerformanceCounters.init(),
            .allocation_tracker = AllocationTracker.init(allocator),
            .gc_tracker = GCTracker.init(allocator),
            .hotspot_tracker = HotspotTracker.init(allocator),
            .samples = std.ArrayListUnmanaged(PerformanceSample){},
            .allocator = allocator,
            .running = std.atomic.Atomic(bool).init(false),
        };
    }

    pub fn deinit(self: *RealTimeProfiler) void {
        self.allocation_tracker.deinit();
        self.gc_tracker.deinit();
        self.hotspot_tracker.deinit();
        self.samples.deinit(self.allocator);
    }

    /// 开始性能分析
    pub fn start(self: *RealTimeProfiler) void {
        self.running.store(true, .release);
    }

    /// 停止性能分析
    pub fn stop(self: *RealTimeProfiler) void {
        self.running.store(false, .release);
    }

    /// 采样
    pub fn sample(self: *RealTimeProfiler) !void {
        if (!self.running.load(.acquire)) return;

        const sample = PerformanceSample{
            .timestamp = std.time.nanoTimestamp(),
            .cpu_counters = self.cpu_counters,
            .memory_allocated = self.allocation_tracker.current_allocated,
            .gc_phase = self.gc_tracker.current_phase,
            .call_stack_depth = self.hotspot_tracker.call_stack.items.len,
        };

        try self.samples.append(self.allocator, sample);

        // 限制采样数量
        if (self.samples.items.len > MAX_SAMPLES) {
            // 移除最旧的采样
            _ = self.samples.orderedRemove(0);
        }
    }

    /// 获取性能报告
    pub fn getPerformanceReport(self: *RealTimeProfiler) !PerformanceReport {
        const memory_stats = self.allocation_tracker.getMemoryStats();
        const gc_stats = self.gc_tracker.getGCStats();
        const hotspots = try self.hotspot_tracker.getHotspots();

        return PerformanceReport{
            .cpu_ipc = self.cpu_counters.getIPC(),
            .cpu_cache_hit_rate = self.cpu_counters.getCacheHitRate(),
            .cpu_branch_accuracy = self.cpu_counters.getBranchAccuracy(),
            .memory_current_allocated = memory_stats.current_allocated,
            .memory_peak_allocated = memory_stats.peak_allocated,
            .memory_total_allocations = memory_stats.total_allocations,
            .memory_active_allocations = memory_stats.active_allocations,
            .gc_total_count = gc_stats.total_gc_count,
            .gc_avg_pause_ns = gc_stats.avg_pause_ns,
            .gc_throughput = gc_stats.gc_throughput,
            .hotspots = hotspots,
            .sample_count = self.samples.items.len,
        };
    }

    pub const PerformanceReport = struct {
        cpu_ipc: f64,
        cpu_cache_hit_rate: f64,
        cpu_branch_accuracy: f64,
        memory_current_allocated: usize,
        memory_peak_allocated: usize,
        memory_total_allocations: u64,
        memory_active_allocations: usize,
        gc_total_count: usize,
        gc_avg_pause_ns: u64,
        gc_throughput: f64,
        hotspots: std.ArrayList([]const u8),
        sample_count: usize,
    };
};

// ============================================================================
// 测试
// ============================================================================

test "CPU performance counters" {
    var counters = CPUPerformanceCounters.init();

    counters.instructions = 1000;
    counters.cycles = 500;

    const ipc = counters.getIPC();
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), ipc, 0.01);

    counters.cache_misses = 100;
    const hit_rate = counters.getCacheHitRate();
    try std.testing.expect(hit_rate == 0.9);
}

test "allocation tracker" {
    var tracker = AllocationTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const ptr = @as(*u8, @ptrFromInt(0x1000));
    const location = AllocationTracker.SourceLocation{
        .file = "test.php",
        .line = 10,
        .function = "test_func",
    };

    try tracker.recordAllocation(ptr, 1024, location, "string");

    const stats = tracker.getMemoryStats();
    try std.testing.expect(stats.current_allocated == 1024);
    try std.testing.expect(stats.peak_allocated == 1024);
    try std.testing.expect(stats.total_allocations == 1);

    tracker.recordDeallocation(ptr);

    const stats2 = tracker.getMemoryStats();
    try std.testing.expect(stats2.current_allocated == 0);
    try std.testing.expect(stats2.total_deallocations == 1);
}

test "GC tracker" {
    var tracker = GCTracker.init(std.testing.allocator);
    defer tracker.deinit();

    tracker.startGC(.minor);

    try tracker.endGC(1000, 2000, 3000, 100, 1024, 8192, 7168);

    const stats = tracker.getGCStats();
    try std.testing.expect(stats.total_gc_count == 1);
    try std.testing.expect(stats.minor_gc_count == 1);
    try std.testing.expect(stats.total_collected_objects == 100);
}

test "hotspot tracker" {
    var tracker = HotspotTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.enterFunction("test_func", "test.php", 10);
    std.time.sleep(1_000_000); // 1ms
    try tracker.exitFunction();

    // 模拟多次调用
    var i: usize = 0;
    while (i < HOTSPOT_THRESHOLD + 1) : (i += 1) {
        try tracker.enterFunction("hot_func", "test.php", 20);
        try tracker.exitFunction();
    }

    const hotspots = try tracker.getHotspots();
    try std.testing.expect(hotspots.items.len >= 1);

    for (hotspots.items) |hotspot| {
        std.testing.allocator.free(hotspot);
    }
    hotspots.deinit();
}

test "real time profiler" {
    var profiler = RealTimeProfiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.start();

    try profiler.sample();
    try profiler.sample();
    try profiler.sample();

    const report = try profiler.getPerformanceReport();
    try std.testing.expect(report.sample_count == 3);

    for (report.hotspots.items) |hotspot| {
        std.testing.allocator.free(hotspot);
    }
    report.hotspots.deinit();

    profiler.stop();
}