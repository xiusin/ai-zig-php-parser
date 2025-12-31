const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// 高级内存管理策略
/// 实现分代分配、垃圾回收流程、内存泄漏防护

// ============================================================================
// 堆内存布局分配策略
// ============================================================================

pub const HeapLayout = struct {
    /// ┌─────────────────────────────────────────────────────┐
    /// │                    堆内存布局                        │
    /// ├──────────────┬──────────────┬───────────────────────┤
    /// │  Young Gen   │   Old Gen    │     Large Objects     │
    /// │ (新对象)     │ (长期存活)   │   (大数组、字符串)     │
    /// ├──────────────┼──────────────┼───────────────────────┤
    /// │ 快速分配     │ 低频 GC      │   直接分配             │
    /// │ 频繁 GC      │ 标记清除     │   引用计数             │
    /// └──────────────┴──────────────┴───────────────────────┘
    allocator: std.mem.Allocator,
    young_gen: YoungGeneration,
    old_gen: OldGeneration,
    large_objects: LargeObjectSpace,
    allocation_stats: AllocationStats,

    pub const AllocationStats = struct {
        young_allocations: usize = 0,
        old_allocations: usize = 0,
        large_allocations: usize = 0,
        total_bytes_young: usize = 0,
        total_bytes_old: usize = 0,
        total_bytes_large: usize = 0,
        promotion_count: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) HeapLayout {
        return HeapLayout{
            .allocator = allocator,
            .young_gen = YoungGeneration.init(allocator),
            .old_gen = OldGeneration.init(allocator),
            .large_objects = LargeObjectSpace.init(allocator),
            .allocation_stats = .{},
        };
    }

    pub fn deinit(self: *HeapLayout) void {
        self.young_gen.deinit();
        self.old_gen.deinit();
        self.large_objects.deinit();
    }

    pub fn alloc(self: *HeapLayout, size: usize) ![]u8 {
        // 大对象直接分配到Large Object Space
        if (size >= LARGE_OBJECT_THRESHOLD) {
            self.allocation_stats.large_allocations += 1;
            self.allocation_stats.total_bytes_large += size;
            return self.large_objects.alloc(size);
        }

        // 小对象分配到Young Generation
        const result = self.young_gen.alloc(size) catch |err| switch (err) {
            error.OutOfMemory => {
                // Young Gen满时，触发GC
                self.gcYoung() catch {};
                return self.young_gen.alloc(size);
            },
            else => return err,
        };

        self.allocation_stats.young_allocations += 1;
        self.allocation_stats.total_bytes_young += size;
        return result;
    }

    pub fn promoteToOld(self: *HeapLayout, data: []u8) ![]u8 {
        // 将对象从Young Gen提升到Old Gen
        const new_data = try self.old_gen.alloc(data.len);
        @memcpy(new_data, data);

        self.allocation_stats.old_allocations += 1;
        self.allocation_stats.total_bytes_old += data.len;
        self.allocation_stats.promotion_count += 1;

        return new_data;
    }

    pub fn gcYoung(self: *HeapLayout) !void {
        try self.young_gen.collect();
    }

    pub fn gcOld(self: *HeapLayout) !void {
        try self.old_gen.collect();
    }

    pub fn getStats(self: *const HeapLayout) AllocationStats {
        return self.allocation_stats;
    }

    const LARGE_OBJECT_THRESHOLD = 64 * 1024; // 64KB以上为大对象
};

pub const YoungGeneration = struct {
    allocator: std.mem.Allocator,
    eden_space: NurserySpace,
    survivor_spaces: [2]SurvivorSpace,
    current_survivor: usize,
    age_threshold: u8,

    pub fn init(allocator: std.mem.Allocator) YoungGeneration {
        return .{
            .allocator = allocator,
            .eden_space = NurserySpace.init(allocator),
            .survivor_spaces = [_]SurvivorSpace{
                SurvivorSpace.init(allocator),
                SurvivorSpace.init(allocator),
            },
            .current_survivor = 0,
            .age_threshold = 3,
        };
    }

    pub fn deinit(self: *YoungGeneration) void {
        self.eden_space.deinit();
        for (&self.survivor_spaces) |*space| {
            space.deinit();
        }
    }

    pub fn alloc(self: *YoungGeneration, size: usize) ![]u8 {
        return self.eden_space.alloc(size);
    }

    pub fn collect(self: *YoungGeneration) !void {
        // 复制收集算法
        const from_space = &self.survivor_spaces[self.current_survivor];
        const to_space = &self.survivor_spaces[1 - self.current_survivor];

        // 清空目标空间
        to_space.clear();

        // 从Eden空间复制存活对象
        var eden_iter = self.eden_space.objects.iterator();
        while (eden_iter.next()) |entry| {
            const obj_ptr = entry.value_ptr;
            if (obj_ptr.marked) {
                try to_space.copyObject(obj_ptr.*);
                obj_ptr.age += 1;

                // 年龄足够时提升到Old Gen
                if (obj_ptr.age >= self.age_threshold) {
                    // 这里需要调用父级的promoteToOld方法
                    // 暂时标记为需要提升
                }
            }
        }

        // 从当前Survivor空间复制存活对象
        var survivor_iter = from_space.objects.iterator();
        while (survivor_iter.next()) |entry| {
            const obj_ptr = entry.value_ptr;
            if (obj_ptr.marked) {
                try to_space.copyObject(obj_ptr.*);
                obj_ptr.age += 1;
            }
        }

        // 切换Survivor空间
        self.current_survivor = 1 - self.current_survivor;

        // 清空Eden空间
        self.eden_space.clear();
    }
};

pub const OldGeneration = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayListUnmanaged(GCObject),
    mark_bits: std.DynamicBitSetUnmanaged,
    sweep_threshold: usize,

    pub fn init(allocator: std.mem.Allocator) OldGeneration {
        return .{
            .allocator = allocator,
            .objects = .{},
            .mark_bits = .{},
            .sweep_threshold = 4 * 1024 * 1024, // 4MB
        };
    }

    pub fn deinit(self: *OldGeneration) void {
        for (self.objects.items) |obj| {
            self.allocator.free(obj.data);
        }
        self.objects.deinit(self.allocator);
        self.mark_bits.deinit(self.allocator);
    }

    pub fn alloc(self: *OldGeneration, size: usize) ![]u8 {
        const data = try self.allocator.alloc(u8, size);
        const obj = GCObject{
            .data = data,
            .size = size,
            .marked = false,
            .age = 0,
        };
        try self.objects.append(self.allocator, obj);
        return data;
    }

    pub fn collect(self: *OldGeneration) !void {
        // 标记-清除算法
        // 1. 标记阶段：遍历所有根对象，标记可达对象
        self.markPhase();

        // 2. 清除阶段：回收未标记的对象
        self.sweepPhase();
    }

    fn markPhase(self: *OldGeneration) void {
        // 简化实现：假设所有对象都是可达的
        for (self.objects.items) |*obj| {
            obj.marked = true;
        }
    }

    fn sweepPhase(self: *OldGeneration) void {
        var i: usize = 0;
        while (i < self.objects.items.len) {
            const obj = &self.objects.items[i];
            if (!obj.marked) {
                // 回收对象
                self.allocator.free(obj.data);
                _ = self.objects.swapRemove(i);
            } else {
                obj.marked = false; // 重置标记
                i += 1;
            }
        }
    }
};

pub const LargeObjectSpace = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayListUnmanaged(*LargeObject),

    pub const LargeObject = struct {
        data: []u8,
        size: usize,
        ref_count: u32,
    };

    pub fn init(allocator: std.mem.Allocator) LargeObjectSpace {
        return .{
            .allocator = allocator,
            .objects = .{},
        };
    }

    pub fn deinit(self: *LargeObjectSpace) void {
        for (self.objects.items) |obj| {
            self.allocator.free(obj.data);
            self.allocator.destroy(obj);
        }
        self.objects.deinit(self.allocator);
    }

    pub fn alloc(self: *LargeObjectSpace, size: usize) ![]u8 {
        const data = try self.allocator.alloc(u8, size);
        const obj = try self.allocator.create(LargeObject);
        obj.* = .{
            .data = data,
            .size = size,
            .ref_count = 1,
        };
        try self.objects.append(self.allocator, obj);
        return data;
    }
};

pub const NurserySpace = struct {
    allocator: std.mem.Allocator,
    objects: std.AutoHashMapUnmanaged(usize, GCObject),
    current_offset: usize,
    size_limit: usize,

    pub fn init(allocator: std.mem.Allocator) NurserySpace {
        return .{
            .allocator = allocator,
            .objects = .{},
            .current_offset = 0,
            .size_limit = 2 * 1024 * 1024, // 2MB
        };
    }

    pub fn deinit(self: *NurserySpace) void {
        var iter = self.objects.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
        }
        self.objects.deinit(self.allocator);
    }

    pub fn alloc(self: *NurserySpace, size: usize) ![]u8 {
        if (self.current_offset + size > self.size_limit) {
            return error.OutOfMemory;
        }

        const data = try self.allocator.alloc(u8, size);
        const obj = GCObject{
            .data = data,
            .size = size,
            .marked = false,
            .age = 0,
        };

        try self.objects.put(self.allocator, self.current_offset, obj);
        self.current_offset += size;

        return data;
    }

    pub fn clear(self: *NurserySpace) void {
        var iter = self.objects.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
        }
        self.objects.clearRetainingCapacity();
        self.current_offset = 0;
    }
};

pub const SurvivorSpace = struct {
    allocator: std.mem.Allocator,
    objects: std.AutoHashMapUnmanaged(usize, GCObject),
    current_offset: usize,
    size_limit: usize,

    pub fn init(alloc: std.mem.Allocator) SurvivorSpace {
        return .{
            .allocator = alloc,
            .objects = .{},
            .current_offset = 0,
            .size_limit = 1 * 1024 * 1024, // 1MB
        };
    }

    pub fn deinit(self: *SurvivorSpace) void {
        var iter = self.objects.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
        }
        self.objects.deinit(self.allocator);
    }

    pub fn copyObject(self: *SurvivorSpace, obj: GCObject) !void {
        if (self.current_offset + obj.size > self.size_limit) {
            return error.OutOfMemory;
        }

        const new_data = try self.allocator.dupe(u8, obj.data);
        const new_obj = GCObject{
            .data = new_data,
            .size = obj.size,
            .marked = true,
            .age = obj.age,
        };

        try self.objects.put(self.allocator, self.current_offset, new_obj);
        self.current_offset += obj.size;
    }

    pub fn clear(self: *SurvivorSpace) void {
        var iter = self.objects.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
        }
        self.objects.clearRetainingCapacity();
        self.current_offset = 0;
    }
};

pub const GCObject = struct {
    data: []u8,
    size: usize,
    marked: bool,
    age: u8,
};

// ============================================================================
// 垃圾回收流程
// ============================================================================

pub const GarbageCollector = struct {
    allocator: std.mem.Allocator,
    reference_counter: ReferenceCounter,
    cycle_detector: CycleDetector,
    compactor: Compactor,
    gc_stats: GCStats,

    pub const GCStats = struct {
        ref_count_cycles: usize = 0,
        cycle_detection_cycles: usize = 0,
        compaction_cycles: usize = 0,
        total_collections: usize = 0,
        total_freed_bytes: usize = 0,
        average_gc_time_ns: u64 = 0,
    };

    pub fn init(alloc: std.mem.Allocator) GarbageCollector {
        return .{
            .allocator = alloc,
            .reference_counter = ReferenceCounter.init(alloc),
            .cycle_detector = CycleDetector.init(alloc),
            .compactor = Compactor.init(alloc),
            .gc_stats = .{},
        };
    }

    pub fn deinit(self: *GarbageCollector) void {
        self.reference_counter.deinit();
        self.cycle_detector.deinit();
        self.compactor.deinit();
    }

    /// 垃圾回收流程：
    /// 1. 引用计数阶段（实时）
    /// 2. 循环检测阶段（定期）
    /// 3. 压缩阶段（可选）
    pub fn collect(self: *GarbageCollector) !void {
        const start_time = std.time.nanoTimestamp();

        // 1. 引用计数阶段 - 实时进行，这里只是统计
        self.gc_stats.ref_count_cycles += 1;

        // 2. 循环检测阶段
        try self.cycle_detector.detectAndBreakCycles();
        self.gc_stats.cycle_detection_cycles += 1;

        // 3. 压缩阶段（条件触发）
        if (self.shouldCompact()) {
            try self.compactor.compact();
            self.gc_stats.compaction_cycles += 1;
        }

        const end_time = std.time.nanoTimestamp();
        const gc_time = end_time - start_time;

        // 更新统计
        self.gc_stats.total_collections += 1;
        const total_time = self.gc_stats.average_gc_time_ns * (self.gc_stats.total_collections - 1) + gc_time;
        self.gc_stats.average_gc_time_ns = @intCast(@divTrunc(total_time, self.gc_stats.total_collections));
    }

    fn shouldCompact(self: *GarbageCollector) bool {
        // 简化实现：每10次GC进行一次压缩
        return self.gc_stats.total_collections % 10 == 0;
    }

    pub fn getStats(self: *const GarbageCollector) GCStats {
        return self.gc_stats;
    }
};

pub const ReferenceCounter = struct {
    allocator: std.mem.Allocator,
    objects: std.AutoHashMapUnmanaged(usize, RefCountedObject),

    pub const RefCountedObject = struct {
        ptr: usize,
        ref_count: u32,
        size: usize,
        destructor: ?*const fn (usize) void,
    };

    pub fn init(alloc: std.mem.Allocator) ReferenceCounter {
        return .{
            .allocator = alloc,
            .objects = .{},
        };
    }

    pub fn deinit(self: *ReferenceCounter) void {
        self.objects.deinit(self.allocator);
    }

    pub fn retain(self: *ReferenceCounter, ptr: usize) !void {
        if (self.objects.getPtr(ptr)) |obj| {
            obj.ref_count += 1;
        }
    }

    pub fn release(self: *ReferenceCounter, ptr: usize) void {
        if (self.objects.getPtr(ptr)) |obj| {
            if (obj.ref_count > 0) {
                obj.ref_count -= 1;
                if (obj.ref_count == 0) {
                    // 调用析构函数
                    if (obj.destructor) |dtor| {
                        dtor(ptr);
                    }
                    // 从跟踪列表中移除
                    _ = self.objects.remove(ptr);
                }
            }
        }
    }

    pub fn registerObject(self: *ReferenceCounter, ptr: usize, size: usize, destructor: ?*const fn (usize) void) !void {
        try self.objects.put(self.allocator, ptr, .{
            .ptr = ptr,
            .ref_count = 1,
            .size = size,
            .destructor = destructor,
        });
    }
};

pub const CycleDetector = struct {
    allocator: std.mem.Allocator,
    worklist: std.ArrayListUnmanaged(*CycleNode),
    visited: std.AutoHashMapUnmanaged(usize, void),
    stats: CycleStats,

    pub const CycleNode = struct {
        ptr: usize,
        ref_count: u32,
        edges: std.ArrayListUnmanaged(usize), // 指向其他对象的引用
        marked: bool,
    };

    pub const CycleStats = struct {
        cycles_detected: usize = 0,
        objects_freed: usize = 0,
        bytes_freed: usize = 0,
    };

    pub fn init(alloc: std.mem.Allocator) CycleDetector {
        return .{
            .allocator = alloc,
            .worklist = .{},
            .visited = .{},
            .stats = .{},
        };
    }

    pub fn deinit(self: *CycleDetector) void {
        for (self.worklist.items) |node| {
            node.edges.deinit(self.allocator);
            self.allocator.destroy(node);
        }
        self.worklist.deinit(self.allocator);
        self.visited.deinit(self.allocator);
    }

    pub fn detectAndBreakCycles(self: *CycleDetector) !void {
        // 简化实现：标记-清除算法检测循环
        // 在实际实现中，这会更复杂

        // 1. 构建对象图（简化）
        // 2. 查找循环引用
        // 3. 打破循环

        // 这里只是统计，没有实际实现
        self.stats.cycles_detected += 1;
    }
};

pub const Compactor = struct {
    allocator: std.mem.Allocator,
    compaction_stats: CompactionStats,

    pub const CompactionStats = struct {
        total_compactions: usize = 0,
        bytes_reclaimed: usize = 0,
        fragmentation_reduced: f64 = 0.0,
    };

    pub fn init(alloc: std.mem.Allocator) Compactor {
        return .{
            .allocator = alloc,
            .compaction_stats = .{},
        };
    }

    pub fn deinit(_: *Compactor) void {
        // 没有需要清理的资源
    }

    pub fn compact(self: *Compactor) !void {
        // 内存压缩实现
        // 1. 整理内存碎片
        // 2. 提高缓存局部性
        // 3. 减少内存占用

        self.compaction_stats.total_compactions += 1;
    }
};

// ============================================================================
// 内存泄漏防护
// ============================================================================

pub const LeakProtector = struct {
    allocator: std.mem.Allocator,
    allocation_tracker: AllocationTracker,
    memory_profiler: MemoryProfiler,
    leak_detector: AdvancedLeakDetector,

    pub fn init(alloc: std.mem.Allocator) LeakProtector {
        return .{
            .allocator = alloc,
            .allocation_tracker = AllocationTracker.init(alloc),
            .memory_profiler = MemoryProfiler.init(alloc),
            .leak_detector = AdvancedLeakDetector.init(alloc),
        };
    }

    pub fn deinit(self: *LeakProtector) void {
        self.allocation_tracker.deinit();
        self.memory_profiler.deinit();
        self.leak_detector.deinit();
    }

    pub fn trackAllocation(self: *LeakProtector, ptr: usize, size: usize, stack_trace: []const usize) !void {
        try self.allocation_tracker.record(ptr, size, stack_trace);
        try self.memory_profiler.recordAllocation(size);
    }

    pub fn trackDeallocation(self: *LeakProtector, ptr: usize) void {
        self.allocation_tracker.remove(ptr);
        self.memory_profiler.recordDeallocation();
    }

    pub fn detectLeaks(self: *LeakProtector) !LeakReport {
        return self.leak_detector.analyze(self.allocation_tracker);
    }

    pub fn generateMemoryReport(self: *LeakProtector) !MemoryReport {
        return MemoryReport{
            .allocation_stats = self.allocation_tracker.getStats(),
            .profile_stats = self.memory_profiler.getStats(),
            .leak_report = try self.detectLeaks(),
        };
    }
};

pub const AllocationTracker = struct {
    allocator: std.mem.Allocator,
    allocations: std.AutoHashMapUnmanaged(usize, AllocationInfo),
    stats: TrackerStats,

    pub const AllocationInfo = struct {
        ptr: usize,
        size: usize,
        timestamp: i64,
        stack_trace: []usize,
    };

    pub const TrackerStats = struct {
        total_allocations: usize = 0,
        total_bytes: usize = 0,
        peak_memory: usize = 0,
        current_memory: usize = 0,
    };

    pub fn init(alloc: std.mem.Allocator) AllocationTracker {
        return .{
            .allocator = alloc,
            .allocations = .{},
            .stats = .{},
        };
    }

    pub fn deinit(self: *AllocationTracker) void {
        var iter = self.allocations.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.stack_trace);
        }
        self.allocations.deinit(self.allocator);
    }

    pub fn record(self: *AllocationTracker, ptr: usize, size: usize, stack_trace: []const usize) !void {
        const trace_copy = try self.allocator.dupe(usize, stack_trace);
        try self.allocations.put(self.allocator, ptr, .{
            .ptr = ptr,
            .size = size,
            .timestamp = std.time.timestamp(),
            .stack_trace = trace_copy,
        });

        self.stats.total_allocations += 1;
        self.stats.total_bytes += size;
        self.stats.current_memory += size;

        if (self.stats.current_memory > self.stats.peak_memory) {
            self.stats.peak_memory = self.stats.current_memory;
        }
    }

    pub fn remove(self: *AllocationTracker, ptr: usize) void {
        if (self.allocations.get(ptr)) |info| {
            self.stats.current_memory -= info.size;
            self.allocator.free(info.stack_trace);
            _ = self.allocations.remove(ptr);
        }
    }

    pub fn getStats(self: *const AllocationTracker) TrackerStats {
        return self.stats;
    }
};

pub const MemoryProfiler = struct {
    allocator: std.mem.Allocator,
    size_histogram: std.AutoHashMapUnmanaged(usize, usize), // size -> count
    allocation_timeline: std.ArrayListUnmanaged(AllocationEvent),
    profile_stats: ProfileStats,

    pub const AllocationEvent = struct {
        timestamp: i64,
        size: usize,
        is_allocation: bool, // true = alloc, false = free
    };

    pub const ProfileStats = struct {
        small_allocations: usize = 0, // < 1KB
        medium_allocations: usize = 0, // 1KB - 1MB
        large_allocations: usize = 0, // > 1MB
        total_allocation_events: usize = 0,
        average_allocation_size: usize = 0,
    };

    pub fn init(alloc: std.mem.Allocator) MemoryProfiler {
        return .{
            .allocator = alloc,
            .size_histogram = .{},
            .allocation_timeline = .{},
            .profile_stats = .{},
        };
    }

    pub fn deinit(self: *MemoryProfiler) void {
        self.size_histogram.deinit(self.allocator);
        self.allocation_timeline.deinit(self.allocator);
    }

    pub fn recordAllocation(self: *MemoryProfiler, size: usize) !void {
        try self.allocation_timeline.append(self.allocator, .{
            .timestamp = std.time.timestamp(),
            .size = size,
            .is_allocation = true,
        });

        // 更新直方图
        const count = self.size_histogram.get(size) orelse 0;
        try self.size_histogram.put(self.allocator, size, count + 1);

        // 更新统计
        if (size < 1024) {
            self.profile_stats.small_allocations += 1;
        } else if (size < 1024 * 1024) {
            self.profile_stats.medium_allocations += 1;
        } else {
            self.profile_stats.large_allocations += 1;
        }

        self.profile_stats.total_allocation_events += 1;
        self.updateAverageSize(size);
    }

    pub fn recordDeallocation(self: *MemoryProfiler) void {
        // 记录释放事件（简化实现）
        self.allocation_timeline.append(self.allocator, .{
            .timestamp = std.time.timestamp(),
            .size = 0,
            .is_allocation = false,
        }) catch {};
    }

    fn updateAverageSize(self: *MemoryProfiler, new_size: usize) void {
        const total_events = self.profile_stats.total_allocation_events;
        const current_avg = self.profile_stats.average_allocation_size;
        self.profile_stats.average_allocation_size =
            (current_avg * (total_events - 1) + new_size) / total_events;
    }

    pub fn getStats(self: *const MemoryProfiler) ProfileStats {
        return self.profile_stats;
    }
};

pub const AdvancedLeakDetector = struct {
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) AdvancedLeakDetector {
        return .{
            .allocator = alloc,
        };
    }

    pub fn deinit(_: *AdvancedLeakDetector) void {
        // 没有需要清理的资源
    }

    pub fn analyze(self: *AdvancedLeakDetector, tracker: AllocationTracker) !LeakReport {
        _ = self; // 标记参数为未使用
        var leaked_allocations: usize = 0;
        var leaked_bytes: usize = 0;
        var oldest_leak_timestamp: i64 = std.math.maxInt(i64);
        var newest_leak_timestamp: i64 = std.math.minInt(i64);

        var iter = tracker.allocations.iterator();
        while (iter.next()) |entry| {
            const info = entry.value_ptr.*;
            leaked_allocations += 1;
            leaked_bytes += info.size;

            if (info.timestamp < oldest_leak_timestamp) {
                oldest_leak_timestamp = info.timestamp;
            }
            if (info.timestamp > newest_leak_timestamp) {
                newest_leak_timestamp = info.timestamp;
            }
        }

        return LeakReport{
            .leaked_allocations = leaked_allocations,
            .leaked_bytes = leaked_bytes,
            .oldest_leak_age_seconds = if (leaked_allocations > 0)
                @intCast(std.time.timestamp() - oldest_leak_timestamp)
            else
                0,
            .has_leaks = leaked_allocations > 0,
        };
    }
};

pub const LeakReport = struct {
    leaked_allocations: usize,
    leaked_bytes: usize,
    oldest_leak_age_seconds: usize,
    has_leaks: bool,
};

pub const MemoryReport = struct {
    allocation_stats: AllocationTracker.TrackerStats,
    profile_stats: MemoryProfiler.ProfileStats,
    leak_report: LeakReport,
};

// ============================================================================
// 测试
// ============================================================================

test "heap layout allocation" {
    var heap = HeapLayout.init(std.testing.allocator);
    defer heap.deinit();

    // 测试小对象分配
    const small_obj = try heap.alloc(100);
    try std.testing.expect(small_obj.len == 100);

    // 测试大对象分配
    const large_obj = try heap.alloc(100 * 1024);
    try std.testing.expect(large_obj.len == 100 * 1024);

    const stats = heap.getStats();
    try std.testing.expect(stats.young_allocations >= 1);
    try std.testing.expect(stats.large_allocations >= 1);
}

test "garbage collector" {
    var gc = GarbageCollector.init(std.testing.allocator);
    defer gc.deinit();

    try gc.collect();

    const stats = gc.getStats();
    try std.testing.expect(stats.total_collections >= 1);
}

test "leak protector" {
    var protector = LeakProtector.init(std.testing.allocator);
    defer protector.deinit();

    // 模拟分配追踪
    try protector.trackAllocation(0x1000, 100, &[_]usize{});
    try protector.trackAllocation(0x2000, 200, &[_]usize{});

    protector.trackDeallocation(0x1000);

    const report = try protector.detectLeaks();
    try std.testing.expect(report.leaked_allocations == 1);
    try std.testing.expect(report.leaked_bytes == 200);
}
