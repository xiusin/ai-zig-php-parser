const std = @import("std");
const Value = @import("types.zig").Value;
const PHPString = @import("types.zig").PHPString;
const PHPArray = @import("types.zig").PHPArray;
const PHPObject = @import("types.zig").PHPObject;
const PHPResource = @import("types.zig").PHPResource;
const UserFunction = @import("types.zig").UserFunction;
const Closure = @import("types.zig").Closure;
const ArrowFunction = @import("types.zig").ArrowFunction;
const StructInstance = @import("types.zig").StructInstance;
const fast_pool = @import("fast_pool.zig");
const generational_gc = @import("generational_gc.zig");
const incremental_gc = @import("incremental_gc.zig");

pub fn Box(comptime T: type) type {
    return struct {
        ref_count: u32,
        gc_info: GCInfo,
        data: T,

        pub const GCInfo = packed struct {
            color: Color = .white,
            buffered: bool = false,

            pub const Color = enum(u2) {
                white = 0,
                gray = 1,
                black = 2,
                purple = 3,
            };
        };

        pub fn retain(self: *@This()) *@This() {
            self.ref_count += 1;
            return self;
        }

        pub fn release(self: *@This(), allocator: std.mem.Allocator) void {
            // Safety check to prevent double-free
            if (self.ref_count == 0) {
                return; // Already freed
            }

            self.ref_count -= 1;
            if (self.ref_count == 0) {
                self.destroy(allocator);
            } else {
                // Mark as potential cycle root when ref count decreases
                self.gc_info.color = .purple;
            }
        }

        fn destroy(self: *@This(), allocator: std.mem.Allocator) void {
            // Additional safety check - if already destroyed, don't destroy again
            if (self.gc_info.color == .black) {
                return; // Already destroyed
            }

            // Call destructor if this is an object with __destruct method
            switch (T) {
                *PHPString => {
                    self.data.release(allocator);
                },
                *PHPArray => {
                    // Decrease reference count for all contained values
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *PHPObject => {
                    // Call destructor if defined
                    if (self.data.class.methods.get("__destruct")) |destruct_method| {
                        // 调用析构方法（需要VM实例，这里简化处理）
                        // 实际实现需要传入VM并调用destruct_method
                        _ = destruct_method;
                    }

                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *StructInstance => {
                    // Decrease reference count for all fields
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        decrementValueRefCount(entry.value_ptr.*, allocator);
                    }
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *PHPResource => {
                    self.data.destroy();
                    allocator.destroy(self.data);
                },
                *UserFunction => {
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *Closure => {
                    // Closure.deinit will handle releasing captured_vars
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *ArrowFunction => {
                    // ArrowFunction.deinit will handle releasing captured_vars
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                else => {},
            }

            // Mark as destroyed
            self.gc_info.color = .black;
            self.ref_count = 0;
            allocator.destroy(self);
        }

        pub fn markGray(self: *@This()) void {
            if (self.gc_info.color != .gray) {
                self.gc_info.color = .gray;
                // Mark children gray recursively
                self.markChildrenGray();
            }
        }

        pub fn markChildrenGray(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *StructInstance => {
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }

        pub fn scan(self: *@This()) void {
            if (self.gc_info.color == .gray) {
                if (self.ref_count > 0) {
                    self.markBlack();
                } else {
                    self.gc_info.color = .white;
                    self.scanChildren();
                }
            }
        }

        pub fn scanChildren(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *StructInstance => {
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }

        pub fn markBlack(self: *@This()) void {
            self.gc_info.color = .black;
            self.markChildrenBlack();
        }

        pub fn markChildrenBlack(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *StructInstance => {
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }

        pub fn collectWhite(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.gc_info.color == .white and !self.gc_info.buffered) {
                self.gc_info.color = .black; // Prevent double collection
                self.collectChildrenWhite(allocator);
                self.destroy(allocator);
            }
        }

        pub fn collectChildrenWhite(self: *@This(), allocator: std.mem.Allocator) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *StructInstance => {
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                else => {},
            }
        }
    };
}

// Helper functions for cycle detection algorithm
fn decrementValueRefCount(value: Value, allocator: std.mem.Allocator) void {
    switch (value.getTag()) {
        .string => value.getAsString().release(allocator),
        .array => value.getAsArray().release(allocator),
        .object => value.getAsObject().release(allocator),
        .struct_instance => value.getAsStruct().release(allocator),
        .resource => value.getAsResource().release(allocator),
        .user_function => value.getAsUserFunc().release(allocator),
        .closure => value.getAsClosure().release(allocator),
        .arrow_function => value.getAsArrowFunc().release(allocator),
        else => {},
    }
}

fn markValueGray(value: Value) void {
    switch (value.getTag()) {
        .string => value.getAsString().markGray(),
        .array => value.getAsArray().markGray(),
        .object => value.getAsObject().markGray(),
        .struct_instance => value.getAsStruct().markGray(),
        .resource => value.getAsResource().markGray(),
        .user_function => value.getAsUserFunc().markGray(),
        .closure => value.getAsClosure().markGray(),
        .arrow_function => value.getAsArrowFunc().markGray(),
        else => {},
    }
}

fn scanValue(value: Value) void {
    switch (value.getTag()) {
        .string => value.getAsString().scan(),
        .array => value.getAsArray().scan(),
        .object => value.getAsObject().scan(),
        .struct_instance => value.getAsStruct().scan(),
        .resource => value.getAsResource().scan(),
        .user_function => value.getAsUserFunc().scan(),
        .closure => value.getAsClosure().scan(),
        .arrow_function => value.getAsArrowFunc().scan(),
        else => {},
    }
}

fn markValueBlack(value: Value) void {
    switch (value.getTag()) {
        .string => value.getAsString().markBlack(),
        .array => value.getAsArray().markBlack(),
        .object => value.getAsObject().markBlack(),
        .struct_instance => value.getAsStruct().markBlack(),
        .resource => value.getAsResource().markBlack(),
        .user_function => value.getAsUserFunc().markBlack(),
        .closure => value.getAsClosure().markBlack(),
        .arrow_function => value.getAsArrowFunc().markBlack(),
        else => {},
    }
}

fn collectValueWhite(value: Value, allocator: std.mem.Allocator) void {
    switch (value.getTag()) {
        .string => value.getAsString().collectWhite(allocator),
        .array => value.getAsArray().collectWhite(allocator),
        .object => value.getAsObject().collectWhite(allocator),
        .struct_instance => value.getAsStruct().collectWhite(allocator),
        .resource => value.getAsResource().collectWhite(allocator),
        .user_function => value.getAsUserFunc().collectWhite(allocator),
        .closure => value.getAsClosure().collectWhite(allocator),
        .arrow_function => value.getAsArrowFunc().collectWhite(allocator),
        else => {},
    }
}

pub const GarbageCollector = struct {
    allocator: std.mem.Allocator,
    memory_threshold: usize,
    allocated_memory: usize,

    /// 增量标记状态
    incremental_state: IncrementalState = .idle,
    gray_list: std.ArrayList(*anyopaque),

    /// 分代GC配置
    nursery_size: usize = 256 * 1024, // 256KB年轻代
    nursery_used: usize = 0,
    promotion_threshold: u8 = 2, // 存活2次后晋升

    /// 写屏障缓冲区
    write_barrier_buffer: std.ArrayList(WriteBarrierEntry),

    /// GC统计
    stats: GCStats = .{},

    /// 时间戳记录 (用于增量GC时间统计)
    mark_start_time: i64 = 0,
    sweep_start_time: i64 = 0,

    pub const IncrementalState = enum {
        idle,
        marking,
        sweeping,
    };

    pub const WriteBarrierEntry = struct {
        source: *anyopaque,
        target: *anyopaque,
    };

    pub const GCStats = struct {
        total_collections: u64 = 0,
        incremental_steps: u64 = 0,
        objects_marked: u64 = 0,
        objects_swept: u64 = 0,
        nursery_promotions: u64 = 0,

        // 增强的时间统计 (Requirements 2.6, 9.2)
        timing: GCTiming = .{},

        // 内存统计
        memory: GCMemoryStats = .{},

        pub const GCTiming = struct {
            /// 最近一次标记阶段耗时 (纳秒)
            last_mark_time_ns: u64 = 0,
            /// 最近一次清除阶段耗时 (纳秒)
            last_sweep_time_ns: u64 = 0,
            /// 最近一次GC总停顿时间 (纳秒)
            last_pause_time_ns: u64 = 0,
            /// 累计标记时间 (纳秒)
            total_mark_time_ns: u64 = 0,
            /// 累计清除时间 (纳秒)
            total_sweep_time_ns: u64 = 0,
            /// 累计停顿时间 (纳秒)
            total_pause_time_ns: u64 = 0,
            /// 最大停顿时间 (纳秒)
            max_pause_time_ns: u64 = 0,
            /// 平均停顿时间 (纳秒)
            avg_pause_time_ns: u64 = 0,
        };

        pub const GCMemoryStats = struct {
            /// 回收前内存使用量
            memory_before_gc: usize = 0,
            /// 回收后内存使用量
            memory_after_gc: usize = 0,
            /// 本次回收释放的内存
            memory_freed: usize = 0,
            /// 累计回收的内存
            total_memory_freed: usize = 0,
            /// 峰值内存使用量
            peak_memory_usage: usize = 0,
        };

        /// 更新平均停顿时间
        pub fn updateAveragePauseTime(self: *GCStats) void {
            if (self.total_collections > 0) {
                self.timing.avg_pause_time_ns = self.timing.total_pause_time_ns / self.total_collections;
            }
        }

        /// 记录GC开始
        pub fn recordGCStart(self: *GCStats, current_memory: usize) void {
            self.memory.memory_before_gc = current_memory;
            if (current_memory > self.memory.peak_memory_usage) {
                self.memory.peak_memory_usage = current_memory;
            }
        }

        /// 记录GC结束
        pub fn recordGCEnd(self: *GCStats, current_memory: usize, pause_time_ns: u64) void {
            self.memory.memory_after_gc = current_memory;
            self.memory.memory_freed = if (self.memory.memory_before_gc > current_memory)
                self.memory.memory_before_gc - current_memory
            else
                0;
            self.memory.total_memory_freed += self.memory.memory_freed;

            self.timing.last_pause_time_ns = pause_time_ns;
            self.timing.total_pause_time_ns += pause_time_ns;
            if (pause_time_ns > self.timing.max_pause_time_ns) {
                self.timing.max_pause_time_ns = pause_time_ns;
            }
            self.updateAveragePauseTime();
        }

        /// 生成统计报告
        pub fn generateReport(self: *const GCStats) GCReport {
            return .{
                .total_collections = self.total_collections,
                .incremental_steps = self.incremental_steps,
                .objects_marked = self.objects_marked,
                .objects_swept = self.objects_swept,
                .nursery_promotions = self.nursery_promotions,
                .last_pause_ms = @as(f64, @floatFromInt(self.timing.last_pause_time_ns)) / 1_000_000.0,
                .avg_pause_ms = @as(f64, @floatFromInt(self.timing.avg_pause_time_ns)) / 1_000_000.0,
                .max_pause_ms = @as(f64, @floatFromInt(self.timing.max_pause_time_ns)) / 1_000_000.0,
                .total_memory_freed_mb = @as(f64, @floatFromInt(self.memory.total_memory_freed)) / (1024.0 * 1024.0),
                .peak_memory_mb = @as(f64, @floatFromInt(self.memory.peak_memory_usage)) / (1024.0 * 1024.0),
            };
        }
    };

    /// GC报告结构 - 用于外部消费
    pub const GCReport = struct {
        total_collections: u64,
        incremental_steps: u64,
        objects_marked: u64,
        objects_swept: u64,
        nursery_promotions: u64,
        last_pause_ms: f64,
        avg_pause_ms: f64,
        max_pause_ms: f64,
        total_memory_freed_mb: f64,
        peak_memory_mb: f64,
    };

    pub fn init(allocator: std.mem.Allocator, memory_threshold: usize) !GarbageCollector {
        return GarbageCollector{
            .allocator = allocator,
            .memory_threshold = memory_threshold,
            .allocated_memory = 0,
            .gray_list = .{},
            .write_barrier_buffer = .{},
        };
    }

    pub fn deinit(self: *GarbageCollector) void {
        self.gray_list.deinit(self.allocator);
        self.write_barrier_buffer.deinit(self.allocator);
    }

    /// 写屏障：在指针更新时调用，用于增量标记的正确性
    pub fn writeBarrier(self: *GarbageCollector, source: *anyopaque, target: *anyopaque) void {
        if (self.incremental_state == .marking) {
            self.write_barrier_buffer.append(self.allocator, .{
                .source = source,
                .target = target,
            }) catch {};
        }
    }

    /// 增量标记步进：每次执行少量标记工作
    pub fn incrementalStep(self: *GarbageCollector, max_work: usize) bool {
        var work_done: usize = 0;
        const step_start: i64 = @intCast(std.time.nanoTimestamp());

        switch (self.incremental_state) {
            .idle => {
                self.incremental_state = .marking;
                self.mark_start_time = step_start;
                self.stats.recordGCStart(self.allocated_memory);
                return false;
            },
            .marking => {
                while (work_done < max_work and self.gray_list.items.len > 0) {
                    _ = self.gray_list.pop();
                    work_done += 1;
                    self.stats.objects_marked += 1;
                }

                // 处理写屏障缓冲区
                while (self.write_barrier_buffer.items.len > 0 and work_done < max_work) {
                    _ = self.write_barrier_buffer.pop();
                    work_done += 1;
                }

                if (self.gray_list.items.len == 0 and self.write_barrier_buffer.items.len == 0) {
                    const mark_end: i64 = @intCast(std.time.nanoTimestamp());
                    self.stats.timing.last_mark_time_ns = @intCast(mark_end - self.mark_start_time);
                    self.stats.timing.total_mark_time_ns += self.stats.timing.last_mark_time_ns;
                    self.incremental_state = .sweeping;
                    self.sweep_start_time = mark_end;
                }
                self.stats.incremental_steps += 1;
                return false;
            },
            .sweeping => {
                const sweep_end: i64 = @intCast(std.time.nanoTimestamp());
                self.stats.timing.last_sweep_time_ns = @intCast(sweep_end - self.sweep_start_time);
                self.stats.timing.total_sweep_time_ns += self.stats.timing.last_sweep_time_ns;

                const total_pause = self.stats.timing.last_mark_time_ns + self.stats.timing.last_sweep_time_ns;
                self.stats.recordGCEnd(self.allocated_memory, total_pause);

                self.incremental_state = .idle;
                self.stats.total_collections += 1;
                return true;
            },
        }
    }

    /// 年轻代分配（Bump Allocation）
    pub fn nurseryAlloc(self: *GarbageCollector, size: usize) bool {
        if (self.nursery_used + size <= self.nursery_size) {
            self.nursery_used += size;
            return true;
        }
        return false;
    }

    /// 年轻代回收
    pub fn collectNursery(self: *GarbageCollector) void {
        self.nursery_used = 0;
    }

    /// 晋升对象到老年代
    pub fn promoteToOldGen(self: *GarbageCollector) void {
        self.stats.nursery_promotions += 1;
    }

    pub fn collect(self: *GarbageCollector) u32 {
        // 执行增量收集直到完成
        while (!self.incrementalStep(100)) {}
        return @intCast(self.stats.objects_swept);
    }

    pub fn addRoot(self: *GarbageCollector, root: *anyopaque) !void {
        try self.gray_list.append(self.allocator, root);
    }

    pub fn removeRoot(self: *GarbageCollector, root: *anyopaque) void {
        for (self.gray_list.items, 0..) |item, i| {
            if (item == root) {
                _ = self.gray_list.swapRemove(i);
                return;
            }
        }
    }

    pub fn shouldCollect(self: *GarbageCollector) bool {
        return self.allocated_memory >= self.memory_threshold;
    }

    pub fn trackAllocation(self: *GarbageCollector, size: usize) void {
        self.allocated_memory += size;
    }

    pub fn trackDeallocation(self: *GarbageCollector, size: usize) void {
        if (self.allocated_memory >= size) {
            self.allocated_memory -= size;
        } else {
            self.allocated_memory = 0;
        }
    }

    /// 获取GC统计信息
    pub fn getStats(self: *GarbageCollector) GCStats {
        return self.stats;
    }

    /// 获取GC报告 (用于外部消费的格式化报告)
    pub fn getReport(self: *GarbageCollector) GCReport {
        return self.stats.generateReport();
    }
};

pub const Header = struct {
    ref_count: u32,
};

pub fn incRef(comptime T: type) fn (ptr: T) void {
    return struct {
        fn anon(ptr: T) void {
            ptr.ref_count += 1;
        }
    }.anon;
}

pub fn decRef(mm: *MemoryManager, val: Value) void {
    switch (val.getTag()) {
        .string => {
            val.getAsString().release(mm.allocator);
        },
        .array => {
            val.getAsArray().release(mm.allocator);
        },
        .object => {
            val.getAsObject().release(mm.allocator);
        },
        .struct_instance => {
            val.getAsStruct().release(mm.allocator);
        },
        .resource => {
            val.getAsResource().release(mm.allocator);
        },
        .user_function => {
            val.getAsUserFunc().release(mm.allocator);
        },
        .closure => {
            val.getAsClosure().release(mm.allocator);
        },
        .arrow_function => {
            val.getAsClosure().release(mm.allocator);
        },
        else => {},
    }
}

pub const MemoryManager = struct {
    allocator: std.mem.Allocator,
    gc: GarbageCollector,
    /// 高性能对象池系统
    pools: fast_pool.ExtendedPoolManager,
    /// 是否启用池化分配
    use_pooling: bool,
    /// 分代 GC（可选，用于高性能场景）
    gen_gc: ?*generational_gc.EnhancedGenerationalGC,
    /// 增量标记 GC（可选，用于低延迟场景）
    inc_gc: ?*incremental_gc.IncrementalGC,
    /// GC 模式
    gc_mode: GCMode,
    /// 自适应 GC 配置
    adaptive_config: AdaptiveGCConfig,
    /// 自适应 GC 状态：分配计数
    allocation_count: usize,
    /// 自适应 GC 状态：上次检查时间
    last_check_time: i64,
    /// 自适应 GC 状态：上次检查内存
    last_check_memory: usize,

    /// GC 模式枚举
    pub const GCMode = enum {
        /// 引用计数 + 循环检测（默认，兼容模式）
        reference_counting,
        /// 分代 GC（高性能模式）
        generational,
        /// 增量标记 GC（低延迟模式）
        incremental,
        /// 自适应模式（根据负载自动切换）
        adaptive,
    };

    /// 自适应 GC 配置
    pub const AdaptiveGCConfig = struct {
        /// 切换到分代 GC 的内存阈值（字节）
        generational_threshold: usize = 10 * 1024 * 1024, // 10MB
        /// 切换到增量 GC 的分配速率阈值（字节/秒）
        incremental_alloc_rate_threshold: usize = 1024 * 1024, // 1MB/s
        /// 检查间隔（分配次数）
        check_interval: usize = 1000,
        /// 是否启用自动切换
        auto_switch_enabled: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator) !MemoryManager {
        const default_threshold = 1024 * 1024; // 1MB default threshold
        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, default_threshold),
            .pools = fast_pool.ExtendedPoolManager.init(allocator),
            .use_pooling = true,
            .gen_gc = null,
            .inc_gc = null,
            .gc_mode = .reference_counting,
            .adaptive_config = .{},
            .allocation_count = 0,
            .last_check_time = 0,
            .last_check_memory = 0,
        };
    }

    pub fn initWithThreshold(allocator: std.mem.Allocator, memory_threshold: usize) !MemoryManager {
        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, memory_threshold),
            .pools = fast_pool.ExtendedPoolManager.init(allocator),
            .use_pooling = true,
            .gen_gc = null,
            .inc_gc = null,
            .gc_mode = .reference_counting,
            .adaptive_config = .{},
            .allocation_count = 0,
            .last_check_time = 0,
            .last_check_memory = 0,
        };
    }

    /// 初始化并启用分代 GC
    pub fn initWithGenerationalGC(allocator: std.mem.Allocator) !MemoryManager {
        const gen_gc_ptr = try allocator.create(generational_gc.EnhancedGenerationalGC);
        gen_gc_ptr.* = try generational_gc.EnhancedGenerationalGC.init(allocator);

        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, 1024 * 1024),
            .pools = fast_pool.ExtendedPoolManager.init(allocator),
            .use_pooling = true,
            .gen_gc = gen_gc_ptr,
            .inc_gc = null,
            .gc_mode = .generational,
            .adaptive_config = .{},
            .allocation_count = 0,
            .last_check_time = 0,
            .last_check_memory = 0,
        };
    }

    /// 初始化分代 GC 并使用自定义配置
    pub fn initWithGenerationalGCConfig(
        allocator: std.mem.Allocator,
        config: generational_gc.EnhancedGenerationalGC.GCConfig,
    ) !MemoryManager {
        const gen_gc_ptr = try allocator.create(generational_gc.EnhancedGenerationalGC);
        gen_gc_ptr.* = try generational_gc.EnhancedGenerationalGC.initWithConfig(allocator, config);

        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, 1024 * 1024),
            .pools = fast_pool.ExtendedPoolManager.init(allocator),
            .use_pooling = true,
            .gen_gc = gen_gc_ptr,
            .inc_gc = null,
            .gc_mode = .generational,
            .adaptive_config = .{},
            .allocation_count = 0,
            .last_check_time = 0,
            .last_check_memory = 0,
        };
    }

    /// 初始化并启用增量标记 GC
    pub fn initWithIncrementalGC(allocator: std.mem.Allocator) !MemoryManager {
        const inc_gc_ptr = try allocator.create(incremental_gc.IncrementalGC);
        inc_gc_ptr.* = incremental_gc.IncrementalGC.init(allocator);

        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, 1024 * 1024),
            .pools = fast_pool.ExtendedPoolManager.init(allocator),
            .use_pooling = true,
            .gen_gc = null,
            .inc_gc = inc_gc_ptr,
            .gc_mode = .incremental,
            .adaptive_config = .{},
            .allocation_count = 0,
            .last_check_time = 0,
            .last_check_memory = 0,
        };
    }

    /// 初始化增量标记 GC 并使用自定义配置
    pub fn initWithIncrementalGCConfig(
        allocator: std.mem.Allocator,
        config: incremental_gc.IncrementalGC.GCConfig,
    ) !MemoryManager {
        const inc_gc_ptr = try allocator.create(incremental_gc.IncrementalGC);
        inc_gc_ptr.* = incremental_gc.IncrementalGC.initWithConfig(allocator, config);

        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, 1024 * 1024),
            .pools = fast_pool.ExtendedPoolManager.init(allocator),
            .use_pooling = true,
            .gen_gc = null,
            .inc_gc = inc_gc_ptr,
            .gc_mode = .incremental,
            .adaptive_config = .{},
            .allocation_count = 0,
            .last_check_time = 0,
            .last_check_memory = 0,
        };
    }

    /// 初始化自适应 GC 模式
    /// 根据内存使用和分配速率自动切换 GC 策略
    pub fn initWithAdaptiveGC(allocator: std.mem.Allocator) !MemoryManager {
        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, 1024 * 1024),
            .pools = fast_pool.ExtendedPoolManager.init(allocator),
            .use_pooling = true,
            .gen_gc = null,
            .inc_gc = null,
            .gc_mode = .adaptive,
            .adaptive_config = .{},
            .allocation_count = 0,
            .last_check_time = std.time.milliTimestamp(),
            .last_check_memory = 0,
        };
    }

    /// 初始化自适应 GC 模式并使用自定义配置
    pub fn initWithAdaptiveGCConfig(allocator: std.mem.Allocator, config: AdaptiveGCConfig) !MemoryManager {
        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, 1024 * 1024),
            .pools = fast_pool.ExtendedPoolManager.init(allocator),
            .use_pooling = true,
            .gen_gc = null,
            .inc_gc = null,
            .gc_mode = .adaptive,
            .adaptive_config = config,
            .allocation_count = 0,
            .last_check_time = std.time.milliTimestamp(),
            .last_check_memory = 0,
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        self.pools.deinit();
        self.gc.deinit();
        if (self.gen_gc) |gen_gc| {
            gen_gc.deinit();
            self.allocator.destroy(gen_gc);
        }
        if (self.inc_gc) |inc_gc| {
            inc_gc.deinit();
            self.allocator.destroy(inc_gc);
        }
    }

    /// 切换 GC 模式
    /// 注意：切换到分代 GC 或增量 GC 模式需要先初始化对应的 GC
    pub fn setGCMode(self: *MemoryManager, mode: GCMode) !void {
        if (mode == .generational and self.gen_gc == null) {
            // 延迟初始化分代 GC
            const gen_gc_ptr = try self.allocator.create(generational_gc.EnhancedGenerationalGC);
            gen_gc_ptr.* = try generational_gc.EnhancedGenerationalGC.init(self.allocator);
            self.gen_gc = gen_gc_ptr;
        }
        if (mode == .incremental and self.inc_gc == null) {
            // 延迟初始化增量 GC
            const inc_gc_ptr = try self.allocator.create(incremental_gc.IncrementalGC);
            inc_gc_ptr.* = incremental_gc.IncrementalGC.init(self.allocator);
            self.inc_gc = inc_gc_ptr;
        }
        self.gc_mode = mode;
    }

    /// 获取当前 GC 模式
    pub fn getGCMode(self: *const MemoryManager) GCMode {
        return self.gc_mode;
    }

    /// 启用/禁用池化分配
    pub fn setPoolingEnabled(self: *MemoryManager, enabled: bool) void {
        self.use_pooling = enabled;
    }

    /// 重置临时分配（每次请求后调用）
    pub fn resetTemp(self: *MemoryManager) void {
        self.pools.resetTemp();
    }

    /// 获取池统计信息
    pub fn getPoolStats(self: *const MemoryManager) struct {
        string: fast_pool.PHPStringPool.Stats,
        array: fast_pool.PHPArrayPool.Stats,
        frame: fast_pool.CallFramePool.Stats,
    } {
        return self.pools.getStats();
    }

    pub fn allocString(self: *MemoryManager, data: []const u8) !*Box(*PHPString) {
        const php_string = try PHPString.init(self.allocator, data);
        const box = try self.allocator.create(Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_string,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPString)) + data.len);
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocArray(self: *MemoryManager) !*Box(*PHPArray) {
        const php_array = try self.allocator.create(PHPArray);
        php_array.* = PHPArray.init(self.allocator);
        const box = try self.allocator.create(Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPArray)) + @sizeOf(PHPArray));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocObject(self: *MemoryManager, class: *@import("types.zig").PHPClass) !*Box(*PHPObject) {
        const php_object = try self.allocator.create(PHPObject);
        php_object.* = try PHPObject.init(self.allocator, class);
        return self.wrapObject(php_object);
    }

    pub fn wrapObject(self: *MemoryManager, php_object: *PHPObject) !*Box(*PHPObject) {
        const box = try self.allocator.create(Box(*PHPObject));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_object,
        };
        self.gc.trackAllocation(@sizeOf(Box(*PHPObject)) + @sizeOf(PHPObject));
        return box;
    }

    pub fn wrapArray(self: *MemoryManager, php_array: *PHPArray) !*Box(*PHPArray) {
        const box = try self.allocator.create(Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };
        self.gc.trackAllocation(@sizeOf(Box(*PHPArray)) + @sizeOf(PHPArray));
        return box;
    }

    pub fn allocResource(self: *MemoryManager, resource: PHPResource) !*Box(*PHPResource) {
        const php_resource = try self.allocator.create(PHPResource);
        php_resource.* = resource;
        const box = try self.allocator.create(Box(*PHPResource));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_resource,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPResource)) + @sizeOf(PHPResource));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocUserFunction(self: *MemoryManager, function: UserFunction) !*Box(*UserFunction) {
        const user_function = try self.allocator.create(UserFunction);
        user_function.* = function;
        const box = try self.allocator.create(Box(*UserFunction));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = user_function,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*UserFunction)) + @sizeOf(UserFunction));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocClosure(self: *MemoryManager, closure: Closure) !*Box(*Closure) {
        const closure_ptr = try self.allocator.create(Closure);
        closure_ptr.* = closure;
        const box = try self.allocator.create(Box(*Closure));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = closure_ptr,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*Closure)) + @sizeOf(Closure));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocArrowFunction(self: *MemoryManager, arrow_function: ArrowFunction) !*Box(*ArrowFunction) {
        const arrow_function_ptr = try self.allocator.create(ArrowFunction);
        arrow_function_ptr.* = arrow_function;
        const box = try self.allocator.create(Box(*ArrowFunction));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = arrow_function_ptr,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*ArrowFunction)) + @sizeOf(ArrowFunction));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    /// 自适应 GC：检查是否需要切换 GC 模式
    fn checkAdaptiveGC(self: *MemoryManager) void {
        if (self.gc_mode != .adaptive or !self.adaptive_config.auto_switch_enabled) {
            return;
        }

        self.allocation_count += 1;
        if (self.allocation_count < self.adaptive_config.check_interval) {
            return;
        }

        // 重置计数器
        self.allocation_count = 0;

        const current_memory = self.gc.allocated_memory;
        const current_time = std.time.milliTimestamp();

        // 检查是否应该切换到分代 GC（高内存使用）
        if (current_memory >= self.adaptive_config.generational_threshold) {
            if (self.gen_gc == null) {
                // 延迟初始化分代 GC
                const gen_gc_ptr = self.allocator.create(generational_gc.EnhancedGenerationalGC) catch return;
                gen_gc_ptr.* = generational_gc.EnhancedGenerationalGC.init(self.allocator) catch {
                    self.allocator.destroy(gen_gc_ptr);
                    return;
                };
                self.gen_gc = gen_gc_ptr;
            }
            // 内部切换到分代 GC（保持 adaptive 模式以继续监控）
        }

        // 计算分配速率
        if (self.last_check_time > 0) {
            const time_diff_ms = current_time - self.last_check_time;
            if (time_diff_ms > 0) {
                const memory_diff = if (current_memory > self.last_check_memory)
                    current_memory - self.last_check_memory
                else
                    0;
                const alloc_rate = (memory_diff * 1000) / @as(usize, @intCast(time_diff_ms));

                // 高分配速率时考虑使用增量 GC
                if (alloc_rate >= self.adaptive_config.incremental_alloc_rate_threshold) {
                    if (self.inc_gc == null) {
                        const inc_gc_ptr = self.allocator.create(incremental_gc.IncrementalGC) catch return;
                        inc_gc_ptr.* = incremental_gc.IncrementalGC.init(self.allocator);
                        self.inc_gc = inc_gc_ptr;
                    }
                }
            }
        }

        self.last_check_time = current_time;
        self.last_check_memory = current_memory;
    }

    pub fn collect(self: *MemoryManager) u32 {
        // 自适应模式下检查是否需要切换
        self.checkAdaptiveGC();

        return switch (self.gc_mode) {
            .reference_counting => self.gc.collect(),
            .generational => blk: {
                if (self.gen_gc) |gen_gc| {
                    gen_gc.collectMinor() catch {};
                    break :blk @intCast(gen_gc.stats.minor_gc_count);
                }
                break :blk self.gc.collect();
            },
            .incremental => blk: {
                if (self.inc_gc) |inc_gc| {
                    // 执行一步增量 GC
                    _ = inc_gc.step() catch {};
                    break :blk @intCast(inc_gc.stats.incremental_steps);
                }
                break :blk self.gc.collect();
            },
            .adaptive => blk: {
                // 自适应模式：根据当前状态选择最佳策略
                const current_memory = self.gc.allocated_memory;

                // 高内存使用时优先使用分代 GC
                if (current_memory >= self.adaptive_config.generational_threshold) {
                    if (self.gen_gc) |gen_gc| {
                        gen_gc.collectMinor() catch {};
                        break :blk @intCast(gen_gc.stats.minor_gc_count);
                    }
                }

                // 有增量 GC 时执行增量步进
                if (self.inc_gc) |inc_gc| {
                    _ = inc_gc.step() catch {};
                    break :blk @intCast(inc_gc.stats.incremental_steps);
                }

                // 回退到引用计数
                break :blk self.gc.collect();
            },
        };
    }

    pub fn addRoot(self: *MemoryManager, root: *anyopaque) !void {
        try self.gc.addRoot(root);
        // 分代 GC 也需要追踪根对象
        if (self.gen_gc) |gen_gc| {
            // 将 anyopaque 转换为 GCObjectHeader（如果适用）
            // 注意：这里简化处理，实际需要类型安全的转换
            _ = gen_gc;
        }
    }

    pub fn removeRoot(self: *MemoryManager, root: *anyopaque) void {
        self.gc.removeRoot(root);
    }

    pub fn forceCollect(self: *MemoryManager) u32 {
        return switch (self.gc_mode) {
            .reference_counting => self.gc.collect(),
            .generational => blk: {
                if (self.gen_gc) |gen_gc| {
                    gen_gc.collectMajor() catch {};
                    break :blk @intCast(gen_gc.stats.major_gc_count);
                }
                break :blk self.gc.collect();
            },
            .incremental => blk: {
                if (self.inc_gc) |inc_gc| {
                    // 执行完整 GC 周期
                    inc_gc.collectFull() catch {};
                    break :blk @intCast(inc_gc.stats.gc_cycles);
                }
                break :blk self.gc.collect();
            },
            .adaptive => blk: {
                // 自适应模式下执行完整收集
                if (self.gen_gc) |gen_gc| {
                    gen_gc.collectMajor() catch {};
                    break :blk @intCast(gen_gc.stats.major_gc_count);
                }
                if (self.inc_gc) |inc_gc| {
                    inc_gc.collectFull() catch {};
                    break :blk @intCast(inc_gc.stats.gc_cycles);
                }
                break :blk self.gc.collect();
            },
        };
    }

    /// 执行完整 GC（分代模式下执行 Full GC，增量模式下执行完整周期）
    pub fn fullCollect(self: *MemoryManager) u32 {
        return switch (self.gc_mode) {
            .reference_counting => self.gc.collect(),
            .generational => blk: {
                if (self.gen_gc) |gen_gc| {
                    gen_gc.collectFull() catch {};
                    break :blk @intCast(gen_gc.stats.full_gc_count);
                }
                break :blk self.gc.collect();
            },
            .incremental => blk: {
                if (self.inc_gc) |inc_gc| {
                    inc_gc.collectFull() catch {};
                    break :blk @intCast(inc_gc.stats.gc_cycles);
                }
                break :blk self.gc.collect();
            },
            .adaptive => blk: {
                // 自适应模式下执行完整收集
                if (self.gen_gc) |gen_gc| {
                    gen_gc.collectFull() catch {};
                    break :blk @intCast(gen_gc.stats.full_gc_count);
                }
                if (self.inc_gc) |inc_gc| {
                    inc_gc.collectFull() catch {};
                    break :blk @intCast(inc_gc.stats.gc_cycles);
                }
                break :blk self.gc.collect();
            },
        };
    }

    pub fn getMemoryUsage(self: *MemoryManager) usize {
        return switch (self.gc_mode) {
            .reference_counting => self.gc.allocated_memory,
            .generational => blk: {
                if (self.gen_gc) |gen_gc| {
                    const usage = gen_gc.getMemoryUsage();
                    break :blk usage.total_used;
                }
                break :blk self.gc.allocated_memory;
            },
            .incremental => blk: {
                if (self.inc_gc) |inc_gc| {
                    break :blk inc_gc.stats.total_allocated - inc_gc.stats.bytes_freed;
                }
                break :blk self.gc.allocated_memory;
            },
            .adaptive => blk: {
                // 自适应模式返回最准确的内存使用量
                if (self.gen_gc) |gen_gc| {
                    const usage = gen_gc.getMemoryUsage();
                    break :blk usage.total_used;
                }
                break :blk self.gc.allocated_memory;
            },
        };
    }

    pub fn setMemoryThreshold(self: *MemoryManager, threshold: usize) void {
        self.gc.memory_threshold = threshold;
    }

    /// 获取分代 GC 统计信息（仅在分代模式下有效）
    pub fn getGenerationalGCStats(self: *const MemoryManager) ?generational_gc.EnhancedGenerationalGC.GCStatistics {
        if (self.gen_gc) |gen_gc| {
            return gen_gc.getStats();
        }
        return null;
    }

    /// 获取分代 GC 内存使用详情（仅在分代模式下有效）
    pub fn getGenerationalMemoryUsage(self: *const MemoryManager) ?generational_gc.EnhancedGenerationalGC.MemoryUsage {
        if (self.gen_gc) |gen_gc| {
            return gen_gc.getMemoryUsage();
        }
        return null;
    }

    /// 获取增量 GC 统计信息（仅在增量模式下有效）
    pub fn getIncrementalGCStats(self: *const MemoryManager) ?incremental_gc.IncrementalGC.GCStatistics {
        if (self.inc_gc) |inc_gc| {
            return inc_gc.getStats();
        }
        return null;
    }

    /// 获取增量 GC 状态
    pub fn getIncrementalGCState(self: *const MemoryManager) ?incremental_gc.IncrementalGC.GCState {
        if (self.inc_gc) |inc_gc| {
            return inc_gc.getState();
        }
        return null;
    }

    /// 执行增量 GC 步进（仅在增量模式下有效）
    /// 返回：GC 周期是否完成
    pub fn incrementalStep(self: *MemoryManager) !bool {
        if (self.inc_gc) |inc_gc| {
            return try inc_gc.step();
        }
        return true;
    }

    /// 检查是否应该触发 GC
    pub fn shouldCollect(self: *MemoryManager) bool {
        return switch (self.gc_mode) {
            .reference_counting => self.gc.shouldCollect(),
            .generational => blk: {
                if (self.gen_gc) |gen_gc| {
                    break :blk gen_gc.shouldCollect();
                }
                break :blk self.gc.shouldCollect();
            },
            .incremental => blk: {
                if (self.inc_gc) |inc_gc| {
                    break :blk inc_gc.shouldCollect();
                }
                break :blk self.gc.shouldCollect();
            },
            .adaptive => blk: {
                // 自适应模式：检查所有可用的 GC
                if (self.gen_gc) |gen_gc| {
                    if (gen_gc.shouldCollect()) break :blk true;
                }
                if (self.inc_gc) |inc_gc| {
                    if (inc_gc.shouldCollect()) break :blk true;
                }
                break :blk self.gc.shouldCollect();
            },
        };
    }

    /// 写屏障 - 用于分代 GC 的跨代引用追踪
    pub fn writeBarrier(self: *MemoryManager, old_obj: *anyopaque, new_obj: *anyopaque) void {
        if (self.gc_mode == .generational or self.gc_mode == .adaptive) {
            if (self.gen_gc) |gen_gc| {
                // 转换为 GCObjectHeader 并调用写屏障
                const old_header: *generational_gc.GCObjectHeader = @ptrCast(@alignCast(old_obj));
                const new_header: *generational_gc.GCObjectHeader = @ptrCast(@alignCast(new_obj));
                gen_gc.writeBarrier(old_header, new_header) catch {};
            }
        }
        // 引用计数模式下也调用 GC 的写屏障
        self.gc.writeBarrier(old_obj, new_obj);
    }

    /// 获取自适应 GC 配置
    pub fn getAdaptiveConfig(self: *const MemoryManager) AdaptiveGCConfig {
        return self.adaptive_config;
    }

    /// 设置自适应 GC 配置
    pub fn setAdaptiveConfig(self: *MemoryManager, config: AdaptiveGCConfig) void {
        self.adaptive_config = config;
    }

    /// 获取自适应 GC 状态信息
    pub fn getAdaptiveStatus(self: *const MemoryManager) struct {
        mode: GCMode,
        has_generational: bool,
        has_incremental: bool,
        allocation_count: usize,
        current_memory: usize,
    } {
        return .{
            .mode = self.gc_mode,
            .has_generational = self.gen_gc != null,
            .has_incremental = self.inc_gc != null,
            .allocation_count = self.allocation_count,
            .current_memory = self.gc.allocated_memory,
        };
    }
};

// Global function to manually trigger garbage collection (gc_collect_cycles equivalent)
pub fn collectCycles(mm: *MemoryManager) u32 {
    return mm.forceCollect();
}


// ============================================================================
// 分代 GC 集成测试
// ============================================================================

test "MemoryManager with reference counting mode" {
    var mm = try MemoryManager.init(std.testing.allocator);
    defer mm.deinit();

    try std.testing.expect(mm.getGCMode() == .reference_counting);
    try std.testing.expect(mm.gen_gc == null);

    // 基本分配测试
    const str = try mm.allocString("hello");
    try std.testing.expect(str.ref_count == 1);
    str.release(mm.allocator);
}

test "MemoryManager with generational GC mode" {
    var mm = try MemoryManager.initWithGenerationalGC(std.testing.allocator);
    defer mm.deinit();

    try std.testing.expect(mm.getGCMode() == .generational);
    try std.testing.expect(mm.gen_gc != null);

    // 检查分代 GC 统计
    const stats = mm.getGenerationalGCStats();
    try std.testing.expect(stats != null);
    try std.testing.expect(stats.?.minor_gc_count == 0);
}

test "MemoryManager mode switching" {
    var mm = try MemoryManager.init(std.testing.allocator);
    defer mm.deinit();

    // 初始为引用计数模式
    try std.testing.expect(mm.getGCMode() == .reference_counting);

    // 切换到分代 GC 模式（会延迟初始化）
    try mm.setGCMode(.generational);
    try std.testing.expect(mm.getGCMode() == .generational);
    try std.testing.expect(mm.gen_gc != null);

    // 切换回引用计数模式
    try mm.setGCMode(.reference_counting);
    try std.testing.expect(mm.getGCMode() == .reference_counting);
}

test "MemoryManager generational GC collection" {
    var mm = try MemoryManager.initWithGenerationalGC(std.testing.allocator);
    defer mm.deinit();

    // 执行 Minor GC
    _ = mm.collect();
    const stats1 = mm.getGenerationalGCStats().?;
    try std.testing.expect(stats1.minor_gc_count >= 1);

    // 执行 Major GC
    _ = mm.forceCollect();
    const stats2 = mm.getGenerationalGCStats().?;
    try std.testing.expect(stats2.major_gc_count >= 1);

    // 执行 Full GC
    _ = mm.fullCollect();
    const stats3 = mm.getGenerationalGCStats().?;
    try std.testing.expect(stats3.full_gc_count >= 1);
}

test "MemoryManager generational GC memory usage" {
    var mm = try MemoryManager.initWithGenerationalGC(std.testing.allocator);
    defer mm.deinit();

    const usage = mm.getGenerationalMemoryUsage();
    try std.testing.expect(usage != null);
    try std.testing.expect(usage.?.nursery_total > 0);
    try std.testing.expect(usage.?.survivor_total > 0);
}

test "MemoryManager custom generational GC config" {
    const config = generational_gc.EnhancedGenerationalGC.GCConfig{
        .nursery_size = 1024 * 1024, // 1MB
        .survivor_size = 256 * 1024, // 256KB
        .promotion_age = 2,
        .nursery_gc_threshold = 0.9,
    };

    var mm = try MemoryManager.initWithGenerationalGCConfig(std.testing.allocator, config);
    defer mm.deinit();

    try std.testing.expect(mm.getGCMode() == .generational);

    const usage = mm.getGenerationalMemoryUsage().?;
    try std.testing.expect(usage.nursery_total == 1024 * 1024);
    try std.testing.expect(usage.survivor_total == 256 * 1024);
}

// ============================================================================
// 增量 GC 集成测试
// ============================================================================

test "MemoryManager with incremental GC mode" {
    var mm = try MemoryManager.initWithIncrementalGC(std.testing.allocator);
    defer mm.deinit();

    try std.testing.expect(mm.getGCMode() == .incremental);
    try std.testing.expect(mm.inc_gc != null);

    // 检查增量 GC 统计
    const stats = mm.getIncrementalGCStats();
    try std.testing.expect(stats != null);
    try std.testing.expect(stats.?.gc_cycles == 0);
}

test "MemoryManager incremental GC mode switching" {
    var mm = try MemoryManager.init(std.testing.allocator);
    defer mm.deinit();

    // 初始为引用计数模式
    try std.testing.expect(mm.getGCMode() == .reference_counting);
    try std.testing.expect(mm.inc_gc == null);

    // 切换到增量 GC 模式（会延迟初始化）
    try mm.setGCMode(.incremental);
    try std.testing.expect(mm.getGCMode() == .incremental);
    try std.testing.expect(mm.inc_gc != null);

    // 切换回引用计数模式
    try mm.setGCMode(.reference_counting);
    try std.testing.expect(mm.getGCMode() == .reference_counting);
}

test "MemoryManager incremental GC collection" {
    var mm = try MemoryManager.initWithIncrementalGC(std.testing.allocator);
    defer mm.deinit();

    // 执行增量步进
    _ = mm.collect();
    const stats1 = mm.getIncrementalGCStats().?;
    try std.testing.expect(stats1.incremental_steps >= 1);

    // 执行完整 GC 周期
    _ = mm.forceCollect();
    const stats2 = mm.getIncrementalGCStats().?;
    try std.testing.expect(stats2.gc_cycles >= 1);
}

test "MemoryManager incremental GC state" {
    var mm = try MemoryManager.initWithIncrementalGC(std.testing.allocator);
    defer mm.deinit();

    // 初始状态应该是 idle
    const state = mm.getIncrementalGCState();
    try std.testing.expect(state != null);
    try std.testing.expect(state.? == .idle);
}

test "MemoryManager incremental step" {
    var mm = try MemoryManager.initWithIncrementalGC(std.testing.allocator);
    defer mm.deinit();

    // 执行增量步进直到完成一个周期
    var steps: usize = 0;
    while (!try mm.incrementalStep()) {
        steps += 1;
        if (steps > 100) break; // 防止无限循环
    }

    // 应该完成了一个周期
    const stats = mm.getIncrementalGCStats().?;
    try std.testing.expect(stats.gc_cycles >= 1);
}

test "MemoryManager custom incremental GC config" {
    const config = incremental_gc.IncrementalGC.GCConfig{
        .step_objects = 50,
        .step_time_us = 500,
        .use_time_limit = false,
        .gc_threshold = 512 * 1024, // 512KB
    };

    var mm = try MemoryManager.initWithIncrementalGCConfig(std.testing.allocator, config);
    defer mm.deinit();

    try std.testing.expect(mm.getGCMode() == .incremental);
    try std.testing.expect(mm.inc_gc != null);
}

test "MemoryManager incremental GC memory usage" {
    var mm = try MemoryManager.initWithIncrementalGC(std.testing.allocator);
    defer mm.deinit();

    // 初始内存使用应该为 0
    const usage = mm.getMemoryUsage();
    try std.testing.expect(usage == 0);
}

// ============================================================================
// 自适应 GC 集成测试
// ============================================================================

test "MemoryManager with adaptive GC mode" {
    var mm = try MemoryManager.initWithAdaptiveGC(std.testing.allocator);
    defer mm.deinit();

    try std.testing.expect(mm.getGCMode() == .adaptive);
    try std.testing.expect(mm.gen_gc == null); // 初始时未初始化
    try std.testing.expect(mm.inc_gc == null);

    // 检查自适应状态
    const status = mm.getAdaptiveStatus();
    try std.testing.expect(status.mode == .adaptive);
    try std.testing.expect(!status.has_generational);
    try std.testing.expect(!status.has_incremental);
}

test "MemoryManager adaptive GC config" {
    const config = MemoryManager.AdaptiveGCConfig{
        .generational_threshold = 5 * 1024 * 1024, // 5MB
        .incremental_alloc_rate_threshold = 512 * 1024, // 512KB/s
        .check_interval = 500,
        .auto_switch_enabled = true,
    };

    var mm = try MemoryManager.initWithAdaptiveGCConfig(std.testing.allocator, config);
    defer mm.deinit();

    try std.testing.expect(mm.getGCMode() == .adaptive);
    try std.testing.expect(mm.adaptive_config.generational_threshold == 5 * 1024 * 1024);
    try std.testing.expect(mm.adaptive_config.check_interval == 500);
}

test "MemoryManager adaptive GC collection" {
    var mm = try MemoryManager.initWithAdaptiveGC(std.testing.allocator);
    defer mm.deinit();

    // 执行收集（应该使用引用计数模式）
    _ = mm.collect();

    // 执行强制收集
    _ = mm.forceCollect();

    // 执行完整收集
    _ = mm.fullCollect();
}

test "MemoryManager adaptive GC shouldCollect" {
    var mm = try MemoryManager.initWithAdaptiveGC(std.testing.allocator);
    defer mm.deinit();

    // 初始时不应该需要收集
    const should = mm.shouldCollect();
    try std.testing.expect(!should);
}

test "MemoryManager adaptive GC memory usage" {
    var mm = try MemoryManager.initWithAdaptiveGC(std.testing.allocator);
    defer mm.deinit();

    // 初始内存使用应该为 0
    const usage = mm.getMemoryUsage();
    try std.testing.expect(usage == 0);
}
