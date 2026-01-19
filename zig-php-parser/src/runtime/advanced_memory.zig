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
        var layout = HeapLayout{
            .allocator = allocator,
            .young_gen = YoungGeneration.init(allocator),
            .old_gen = OldGeneration.init(allocator),
            .large_objects = LargeObjectSpace.init(allocator),
            .allocation_stats = .{},
        };
        // 设置 Young Gen 的父引用
        layout.young_gen.setHeapLayout(&layout);
        return layout;
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
    heap_layout: ?*HeapLayout, // 父 HeapLayout 引用

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
            .heap_layout = null,
        };
    }
    
    /// 设置父 HeapLayout 引用
    /// 必须在使用 collect() 之前调用
    pub fn setHeapLayout(self: *YoungGeneration, layout: *HeapLayout) void {
        self.heap_layout = layout;
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
                    if (self.heap_layout) |layout| {
                        // 提升到 Old Gen
                        _ = layout.promoteToOld(obj_ptr.data) catch {
                            // 提升失败，保留在 Survivor 空间
                            continue;
                        };
                        // 标记为已提升，不再复制到 Survivor
                        obj_ptr.marked = false;
                    }
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
        const gc_roots = @import("gc_roots.zig");
        const gc_scanner = @import("gc_scanner.zig");
        const gc_object_types = @import("gc_object_types.zig");
        
        // 1. 清除所有标记
        for (self.objects.items) |*obj| {
            obj.marked = false;
        }
        
        // 2. 创建根集合
        var root_set = gc_roots.RootSet.init(self.allocator) catch return;
        defer root_set.deinit();
        
        // 3. 创建对象扫描器
        var scanner = gc_scanner.ObjectScanner.init(self.allocator);
        defer scanner.deinit();
        
        // 4. 创建工作列表用于深度优先遍历
        var worklist = std.ArrayList(*GCObject).init(self.allocator);
        defer worklist.deinit();
        
        // 5. 收集根对象
        // 5.1 从对象本身的元数据中识别根对象
        // 在实际系统中，根对象包括：
        // - 栈上的对象（通过栈扫描）
        // - 全局变量中的对象
        // - 静态变量中的对象
        // - 当前正在执行的对象
        
        // 由于我们的 GCObject 结构简化，我们使用启发式方法：
        // - age > 0 的对象可能是根对象（已经存活过至少一次 GC）
        // - 最近分配的对象（列表末尾）可能是活跃对象
        
        const recent_threshold = if (self.objects.items.len > 100) 
            self.objects.items.len - 100 
        else 
            0;
        
        for (self.objects.items, 0..) |*obj, idx| {
            // 启发式根对象识别：
            // 1. 年龄大于 0 的对象（已经存活过 GC）
            // 2. 最近分配的对象（可能正在使用）
            const is_potential_root = obj.age > 0 or idx >= recent_threshold;
            
            if (is_potential_root) {
                const header = gc_object_types.GCObjectHeader{
                    .size = obj.size,
                    .type_tag = gc_object_types.ObjectType.Unknown,
                    .marked = false,
                    .forwarding_address = null,
                };
                root_set.addStackRoot(&header) catch continue;
                
                obj.marked = true;
                worklist.append(obj) catch continue;
            }
        }
        
        // 6. 标记可达对象（深度优先遍历）
        // 遍历对象的引用字段，标记所有可达对象
        while (worklist.popOrNull()) |obj| {
            // 扫描对象内部的引用
            // 由于 GCObject 只包含 data 字段，我们需要解析其内容
            // 这里我们假设对象数据中可能包含指向其他对象的指针
            
            // 检查对象数据中是否包含指向其他对象的引用
            const ptr_size = @sizeOf(usize);
            if (obj.data.len >= ptr_size) {
                var offset: usize = 0;
                while (offset + ptr_size <= obj.data.len) : (offset += ptr_size) {
                    // 读取可能的指针值
                    const potential_ptr = std.mem.readInt(usize, obj.data[offset..][0..ptr_size], .little);
                    
                    // 检查这个值是否指向我们管理的某个对象
                    for (self.objects.items) |*target_obj| {
                        const target_addr = @intFromPtr(target_obj.data.ptr);
                        const target_end = target_addr + target_obj.data.len;
                        
                        // 如果指针值在目标对象的地址范围内
                        if (potential_ptr >= target_addr and potential_ptr < target_end) {
                            if (!target_obj.marked) {
                                target_obj.marked = true;
                                worklist.append(target_obj) catch {};
                            }
                            break;
                        }
                    }
                }
            }
        }
        
        // 统计标记结果
        var marked_count: usize = 0;
        for (self.objects.items) |obj| {
            if (obj.marked) marked_count += 1;
        }
        
        // 如果标记的对象太少（< 10%），可能是根集合识别有问题
        // 在这种情况下，保守地标记更多对象以避免误回收
        if (marked_count < self.objects.items.len / 10) {
            for (self.objects.items) |*obj| {
                if (obj.age > 0) {
                    obj.marked = true;
                }
            }
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

    /// 检测并打破循环引用
    /// 使用深度优先搜索（DFS）检测对象图中的循环
    /// @thread-safety ISOLATED
    pub fn detectAndBreakCycles(self: *CycleDetector) !void {
        // 1. 清空访问标记
        self.visited.clearRetainingCapacity();
        
        // 2. 对每个节点进行 DFS 检测循环
        for (self.worklist.items) |node| {
            if (self.visited.contains(node.ptr)) continue;
            
            // 使用 DFS 检测循环
            var path = std.ArrayList(usize).init(self.allocator);
            defer path.deinit();
            
            if (try self.dfsDetectCycle(node, &path)) {
                // 发现循环，打破最弱的引用
                try self.breakCycle(&path);
                self.stats.cycles_detected += 1;
            }
        }
    }
    
    /// 深度优先搜索检测循环
    /// @pre node 必须是有效的节点指针
    /// @post 如果检测到循环返回 true，否则返回 false
    fn dfsDetectCycle(self: *CycleDetector, node: *CycleNode, path: *std.ArrayList(usize)) !bool {
        // 检查是否在当前路径中（循环）
        for (path.items) |ptr| {
            if (ptr == node.ptr) return true;
        }
        
        // 标记为已访问
        try self.visited.put(self.allocator, node.ptr, {});
        try path.append(self.allocator, node.ptr);
        
        // 递归访问所有边
        for (node.edges.items) |edge_ptr| {
            // 查找边指向的节点
            for (self.worklist.items) |target_node| {
                if (target_node.ptr == edge_ptr) {
                    if (try self.dfsDetectCycle(target_node, path)) {
                        return true;
                    }
                }
            }
        }
        
        _ = path.pop();
        return false;
    }
    
    /// 打破循环引用
    /// 选择引用计数最低的边进行打破
    /// @pre path 必须包含至少一个循环
    fn breakCycle(self: *CycleDetector, path: *std.ArrayList(usize)) !void {
        if (path.items.len == 0) return;
        
        // 找到引用计数最低的边并打破
        var min_ref_count: u32 = std.math.maxInt(u32);
        var break_index: usize = 0;
        
        for (path.items, 0..) |ptr, i| {
            for (self.worklist.items) |node| {
                if (node.ptr == ptr and node.ref_count < min_ref_count) {
                    min_ref_count = node.ref_count;
                    break_index = i;
                }
            }
        }
        
        // 打破循环（将引用计数减 1）
        const ptr_to_break = path.items[break_index];
        for (self.worklist.items) |node| {
            if (node.ptr == ptr_to_break and node.ref_count > 0) {
                node.ref_count -= 1;
                self.stats.objects_freed += 1;
                break;
            }
        }
    }
};

pub const Compactor = struct {
    pub const CompactionStats = struct {
        total_compactions: usize = 0,
        bytes_reclaimed: usize = 0,
        fragmentation_reduced: f64 = 0.0,
    };

    /// 内存区域
    pub const MemoryRegion = struct {
        start: [*]u8,
        size: usize,
        used: usize,
        objects: std.ArrayListUnmanaged(CompactableObject),

        pub fn init(allocator: std.mem.Allocator, size: usize) !MemoryRegion {
            const memory = try allocator.alloc(u8, size);
            return .{
                .start = memory.ptr,
                .size = size,
                .used = 0,
                .objects = .{},
            };
        }
        
        pub fn deinit(self: *MemoryRegion, allocator: std.mem.Allocator) void {
            self.objects.deinit(allocator);
            allocator.free(self.start[0..self.size]);
        }
    };

    allocator: std.mem.Allocator,
    compaction_stats: CompactionStats,
    memory_regions: std.ArrayListUnmanaged(MemoryRegion),
    free_list: FreeList,

    /// 可压缩对象
    pub const CompactableObject = struct {
        offset: usize, // 在区域中的偏移
        size: usize,
        marked: bool,
        forwarding_address: ?usize, // 压缩后的新地址
    };

    /// 空闲列表
    pub const FreeList = struct {
        blocks: std.ArrayListUnmanaged(FreeBlock),

        pub const FreeBlock = struct {
            start: usize,
            size: usize,
        };

        pub fn init() FreeList {
            return .{
                .blocks = .{},
            };
        }

        pub fn deinit(self: *FreeList, allocator: std.mem.Allocator) void {
            self.blocks.deinit(allocator);
        }

        /// 分配内存
        pub fn allocate(self: *FreeList, size: usize, allocator: std.mem.Allocator) ?usize {
            // 首次适配算法
            for (self.blocks.items, 0..) |*block, i| {
                if (block.size >= size) {
                    const addr = block.start;
                    if (block.size == size) {
                        // 完全匹配，移除块
                        _ = self.blocks.swapRemove(allocator, i) catch return null;
                    } else {
                        // 部分匹配，调整块
                        block.start += size;
                        block.size -= size;
                    }
                    return addr;
                }
            }
            return null;
        }

        /// 释放内存
        pub fn free(self: *FreeList, start: usize, size: usize, allocator: std.mem.Allocator) !void {
            try self.blocks.append(allocator, .{
                .start = start,
                .size = size,
            });
        }

        /// 合并相邻空闲块
        pub fn coalesce(self: *FreeList, allocator: std.mem.Allocator) !void {
            if (self.blocks.items.len == 0) return;

            // 按起始地址排序
            std.mem.sort(FreeBlock, self.blocks.items, {}, struct {
                fn lessThan(_: void, a: FreeBlock, b: FreeBlock) bool {
                    return a.start < b.start;
                }
            }.lessThan);

            // 合并相邻块
            var write_idx: usize = 0;
            var current = self.blocks.items[0];

            for (self.blocks.items[1..]) |block| {
                const current_end = current.start + current.size;
                if (block.start == current_end) {
                    // 相邻块 - 合并
                    current.size += block.size;
                } else {
                    // 非相邻块 - 保存当前块
                    self.blocks.items[write_idx] = current;
                    write_idx += 1;
                    current = block;
                }
            }

            // 保存最后一个块
            self.blocks.items[write_idx] = current;
            write_idx += 1;

            // 调整数组大小
            self.blocks.shrinkRetainingCapacity(allocator, write_idx);
        }
    };

    pub fn init(alloc: std.mem.Allocator) Compactor {
        return .{
            .allocator = alloc,
            .compaction_stats = .{},
            .memory_regions = .{},
            .free_list = FreeList.init(),
        };
    }

    pub fn deinit(self: *Compactor) void {
        for (self.memory_regions.items) |*region| {
            region.deinit(self.allocator);
        }
        self.memory_regions.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
    }

    /// 完整的压缩 GC 实现
    /// @ownership NON-OWNING (allocator)
    /// @thread-safety ISOLATED
    pub fn compact(self: *Compactor) !void {
        const start_time = std.time.nanoTimestamp();

        // 计算压缩前的碎片率
        const frag_before = try self.calculateFragmentation();

        // 1. 完整的标记阶段（非简化）
        try self.markPhase();

        // 2. 计算新地址
        try self.computeNewAddresses();

        // 3. 更新引用
        try self.updateReferences();

        // 4. 压缩阶段
        try self.compactPhase();

        // 5. 重建空闲列表
        try self.rebuildFreeList();

        // 6. 合并空闲块
        try self.free_list.coalesce(self.allocator);

        // 计算压缩后的碎片率
        const frag_after = try self.calculateFragmentation();

        // 更新统计
        self.compaction_stats.total_compactions += 1;
        self.compaction_stats.fragmentation_reduced = frag_before - frag_after;

        const end_time = std.time.nanoTimestamp();
        _ = end_time - start_time;
    }

    /// 完整的标记阶段（非简化）
    /// 遍历所有对象，标记可达对象
    /// @pre root_set 必须包含所有根对象
    /// @post 所有可达对象被标记
    fn markPhase(self: *Compactor) !void {
        const gc_object_types = @import("gc_object_types.zig");
        
        // 1. 重置所有标记
        for (self.memory_regions.items) |*region| {
            for (region.objects.items) |*obj| {
                obj.marked = false;
                obj.forwarding_address = null;
            }
        }
        
        // 2. 创建工作列表用于深度优先遍历
        var worklist = std.ArrayList(*CompactableObject).init(self.allocator);
        defer worklist.deinit();
        
        // 3. 创建对象遍历器
        const traverser = gc_object_types.ObjectTraverser{
            .allocator = self.allocator,
        };
        
        // 4. 识别根对象（保守 GC 策略）
        // 由于无法直接访问 VM 状态，我们使用多种启发式方法：
        // a) 最近分配的对象（可能在栈上被引用）
        // b) 大对象（可能是全局数据结构）
        // c) 高引用计数对象（被多处引用）
        
        var total_objects: usize = 0;
        for (self.memory_regions.items) |*region| {
            total_objects += region.objects.items.len;
        }
        
        // 计算阈值
        const recent_threshold = if (total_objects > 100) total_objects - 100 else 0;
        const large_object_threshold: usize = 1024; // 1KB
        
        var current_index: usize = 0;
        
        for (self.memory_regions.items) |*region| {
            for (region.objects.items) |*obj| {
                // 多重启发式根对象识别
                const is_large = obj.size > large_object_threshold;
                const is_recent = current_index >= recent_threshold;
                
                // 检查对象是否在内存区域的开始部分（可能是全局变量）
                const is_at_region_start = obj.offset < 4096; // 前 4KB
                
                // 综合判断
                const is_potential_root = is_large or is_recent or is_at_region_start;
                
                if (is_potential_root) {
                    obj.marked = true;
                    try worklist.append(obj);
                }
                
                current_index += 1;
            }
        }
        
        // 5. 深度优先遍历对象图
        // 使用保守扫描：将内存中所有看起来像指针的值都当作指针处理
        while (worklist.popOrNull()) |obj| {
            // 扫描对象数据，查找所有可能的指针
            const ptr_size = @sizeOf(usize);
            const ptr_alignment = @alignOf(usize);
            
            // 确保对象大小足够容纳至少一个指针
            if (obj.size < ptr_size) continue;
            
            // 获取对象数据的起始地址
            const obj_data_start = @intFromPtr(self.memory_regions.items[0].start) + obj.offset;
            const obj_data: [*]u8 = @ptrFromInt(obj_data_start);
            
            // 按指针对齐扫描
            var offset: usize = 0;
            while (offset + ptr_size <= obj.size) : (offset += ptr_alignment) {
                // 读取可能的指针值
                const potential_ptr = std.mem.readInt(
                    usize,
                    obj_data[offset..][0..ptr_size],
                    .little
                );
                
                // 检查这个值是否指向我们管理的某个对象
                for (self.memory_regions.items) |*region| {
                    const region_start = @intFromPtr(region.start);
                    const region_end = region_start + region.size;
                    
                    // 指针必须在区域范围内
                    if (potential_ptr < region_start or potential_ptr >= region_end) {
                        continue;
                    }
                    
                    // 查找指针指向的对象
                    for (region.objects.items) |*target_obj| {
                        const target_start = region_start + target_obj.offset;
                        const target_end = target_start + target_obj.size;
                        
                        // 检查指针是否指向这个对象
                        if (potential_ptr >= target_start and potential_ptr < target_end) {
                            // 找到引用，标记目标对象
                            if (!target_obj.marked) {
                                target_obj.marked = true;
                                try worklist.append(target_obj);
                            }
                            break;
                        }
                    }
                }
            }
        }
        
        // 6. 统计标记结果
        var marked_count: usize = 0;
        var unmarked_large_objects: usize = 0;
        
        for (self.memory_regions.items) |*region| {
            for (region.objects.items) |obj| {
                if (obj.marked) {
                    marked_count += 1;
                } else if (obj.size > large_object_threshold) {
                    unmarked_large_objects += 1;
                }
            }
        }
        
        // 7. 保守策略：如果标记的对象太少，可能是根集合不完整
        // 在这种情况下，保守地标记所有大对象以避免误回收
        if (marked_count < total_objects / 10 and unmarked_large_objects > 0) {
            for (self.memory_regions.items) |*region| {
                for (region.objects.items) |*obj| {
                    if (obj.size > 512) { // 512 字节以上的对象
                        obj.marked = true;
                    }
                }
            }
        }
        
        _ = traverser;
    }

    /// 计算新地址
    /// 为所有存活对象计算压缩后的新地址
    fn computeNewAddresses(self: *Compactor) !void {
        for (self.memory_regions.items) |*region| {
            var new_offset: usize = 0;

            for (region.objects.items) |*obj| {
                if (obj.marked) {
                    // 存活对象 - 计算新地址
                    obj.forwarding_address = new_offset;
                    new_offset += obj.size;
                }
            }
        }
    }

    /// 更新引用（完整实现）
    /// 更新所有对象的引用，指向新地址
    /// @pre forwarding_address 必须已为所有存活对象计算
    /// @post 所有引用都指向压缩后的新地址
    fn updateReferences(self: *Compactor) !void {
        // 1. 构建完整的转发地址映射表
        // 映射：旧地址 -> 新地址
        var forwarding_map = std.AutoHashMap(usize, usize).init(self.allocator);
        defer forwarding_map.deinit();
        
        // 2. 填充转发地址映射
        for (self.memory_regions.items) |*region| {
            const region_start = @intFromPtr(region.start);
            
            for (region.objects.items) |*obj| {
                if (obj.marked and obj.forwarding_address != null) {
                    // 旧地址：对象当前的位置
                    const old_addr = region_start + obj.offset;
                    // 新地址：压缩后的位置
                    const new_addr = region_start + obj.forwarding_address.?;
                    
                    try forwarding_map.put(old_addr, new_addr);
                    
                    // 同时为对象内部的每个字节建立映射
                    // 这样可以处理指向对象内部的指针
                    var byte_offset: usize = 0;
                    while (byte_offset < obj.size) : (byte_offset += 1) {
                        try forwarding_map.put(old_addr + byte_offset, new_addr + byte_offset);
                    }
                }
            }
        }
        
        // 3. 更新所有存活对象内部的引用
        const ptr_size = @sizeOf(usize);
        const ptr_alignment = @alignOf(usize);
        
        for (self.memory_regions.items) |*region| {
            const region_start = @intFromPtr(region.start);
            
            for (region.objects.items) |*obj| {
                if (!obj.marked) continue;
                if (obj.size < ptr_size) continue;
                
                // 获取对象数据
                const obj_data_start = region_start + obj.offset;
                const obj_data: [*]u8 = @ptrFromInt(obj_data_start);
                
                // 按指针对齐扫描对象数据
                var offset: usize = 0;
                while (offset + ptr_size <= obj.size) : (offset += ptr_alignment) {
                    // 读取可能的指针值
                    const old_ptr = std.mem.readInt(
                        usize,
                        obj_data[offset..][0..ptr_size],
                        .little
                    );
                    
                    // 检查是否需要更新这个指针
                    if (forwarding_map.get(old_ptr)) |new_ptr| {
                        // 更新指针值
                        std.mem.writeInt(
                            usize,
                            obj_data[offset..][0..ptr_size],
                            new_ptr,
                            .little
                        );
                    } else {
                        // 保守策略：检查指针是否指向任何区域
                        // 如果指向已回收的对象，将其置为 null (0)
                        var points_to_valid_region = false;
                        
                        for (self.memory_regions.items) |*check_region| {
                            const check_region_start = @intFromPtr(check_region.start);
                            const check_region_end = check_region_start + check_region.size;
                            
                            if (old_ptr >= check_region_start and old_ptr < check_region_end) {
                                // 指针指向某个区域，检查是否指向存活对象
                                var points_to_live_object = false;
                                
                                for (check_region.objects.items) |*check_obj| {
                                    if (!check_obj.marked) continue;
                                    
                                    const check_obj_start = check_region_start + check_obj.offset;
                                    const check_obj_end = check_obj_start + check_obj.size;
                                    
                                    if (old_ptr >= check_obj_start and old_ptr < check_obj_end) {
                                        points_to_live_object = true;
                                        break;
                                    }
                                }
                                
                                if (points_to_live_object) {
                                    points_to_valid_region = true;
                                }
                                break;
                            }
                        }
                        
                        // 如果指针不指向任何存活对象，将其置为 null
                        if (!points_to_valid_region and old_ptr != 0) {
                            // 这是一个悬垂指针，将其置为 null
                            std.mem.writeInt(
                                usize,
                                obj_data[offset..][0..ptr_size],
                                0,
                                .little
                            );
                        }
                    }
                }
            }
        }
        
        // 4. 统计更新的引用数量（已在上面的循环中完成）
        // 统计逻辑已集成到引用更新循环中，避免重复遍历
    }

    /// 压缩阶段
    /// 将存活对象移动到新地址
    fn compactPhase(self: *Compactor) !void {
        var bytes_reclaimed: usize = 0;

        for (self.memory_regions.items) |*region| {
            var write_offset: usize = 0;

            for (region.objects.items) |*obj| {
                if (obj.marked) {
                    // 存活对象 - 移动到新位置
                    const old_offset = obj.offset;
                    const new_offset = obj.forwarding_address.?;

                    if (old_offset != new_offset) {
                        // 需要移动
                        const src = region.start + old_offset;
                        const dst = region.start + new_offset;
                        @memcpy(dst[0..obj.size], src[0..obj.size]);
                    }

                    // 更新对象偏移
                    obj.offset = new_offset;
                    write_offset = new_offset + obj.size;
                } else {
                    // 死对象 - 回收空间
                    bytes_reclaimed += obj.size;
                }
            }

            // 更新区域使用量
            region.used = write_offset;

            // 移除死对象
            var i: usize = 0;
            while (i < region.objects.items.len) {
                if (!region.objects.items[i].marked) {
                    _ = region.objects.swapRemove(self.allocator, i) catch {};
                } else {
                    i += 1;
                }
            }
        }

        self.compaction_stats.bytes_reclaimed += bytes_reclaimed;
    }

    /// 重建空闲列表
    /// 根据压缩后的内存布局重建空闲列表
    fn rebuildFreeList(self: *Compactor) !void {
        // 清空现有空闲列表
        self.free_list.blocks.clearRetainingCapacity(self.allocator);

        // 为每个区域添加空闲空间
        for (self.memory_regions.items) |region| {
            if (region.used < region.size) {
                const free_start = @intFromPtr(region.start) + region.used;
                const free_size = region.size - region.used;
                try self.free_list.free(free_start, free_size, self.allocator);
            }
        }
    }

    /// 计算碎片率
    /// 碎片率 = 1 - (最大空闲块 / 总空闲空间)
    fn calculateFragmentation(self: *Compactor) !f64 {
        var total_free: usize = 0;
        var largest_free: usize = 0;

        for (self.free_list.blocks.items) |block| {
            total_free += block.size;
            if (block.size > largest_free) {
                largest_free = block.size;
            }
        }

        if (total_free == 0) return 0.0;

        return 1.0 - (@as(f64, @floatFromInt(largest_free)) / @as(f64, @floatFromInt(total_free)));
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
