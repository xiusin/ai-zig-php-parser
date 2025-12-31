const std = @import("std");

/// 增强型分代垃圾回收器
/// 实现 Phase 7 的内存区域管理：Nursery、Survivor Space、Old Generation、Large Object Space

// ============================================================================
// 常量定义
// ============================================================================

pub const NURSERY_SIZE: usize = 2 * 1024 * 1024; // 2MB Nursery
pub const SURVIVOR_SIZE: usize = 512 * 1024; // 512KB per survivor space
pub const LARGE_OBJECT_THRESHOLD: usize = 8 * 1024; // 8KB 以上为大对象
pub const MAX_PROMOTION_AGE: u8 = 3; // 存活3次后晋升到老年代
pub const OLD_GEN_INITIAL_SIZE: usize = 8 * 1024 * 1024; // 8MB 初始老年代

// ============================================================================
// GC 对象头
// ============================================================================

pub const GCObjectHeader = struct {
    /// 对象大小（包含头部）
    size: u32,
    /// 对象年龄（用于晋升决策）
    age: u8,
    /// 标记状态
    mark: Mark,
    /// 所在代
    generation: Generation,
    /// 是否已转发（复制GC用）
    forwarded: bool,
    /// 转发地址（复制GC用）
    forward_addr: ?*anyopaque,
    /// 析构函数指针
    destructor: ?*const fn (*anyopaque, std.mem.Allocator) void,

    pub const Mark = enum(u2) {
        white = 0, // 未标记
        gray = 1, // 已发现但未扫描子对象
        black = 2, // 已完全扫描
    };

    pub const Generation = enum(u2) {
        nursery = 0,
        survivor = 1,
        old = 2,
        large = 3, // 大对象空间
    };

    pub fn init(size: u32) GCObjectHeader {
        return .{
            .size = size,
            .age = 0,
            .mark = .white,
            .generation = .nursery,
            .forwarded = false,
            .forward_addr = null,
            .destructor = null,
        };
    }

    pub fn getDataPtr(self: *GCObjectHeader) *anyopaque {
        const header_ptr: [*]u8 = @ptrCast(self);
        return @ptrCast(header_ptr + @sizeOf(GCObjectHeader));
    }

    pub fn fromDataPtr(data: *anyopaque) *GCObjectHeader {
        const data_ptr: [*]u8 = @ptrCast(data);
        return @ptrCast(@alignCast(data_ptr - @sizeOf(GCObjectHeader)));
    }
};

// ============================================================================
// Nursery 区 - Bump Pointer 分配器
// ============================================================================

pub const NurseryRegion = struct {
    /// 内存块起始地址
    base: [*]u8,
    /// 当前分配指针
    bump_ptr: [*]u8,
    /// 内存块结束地址
    end: [*]u8,
    /// 总大小
    size: usize,
    /// 已使用大小
    used: usize,
    /// 分配次数统计
    allocation_count: u64,
    /// 后备分配器
    backing_allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize) !NurseryRegion {
        const memory = try allocator.alloc(u8, size);
        return .{
            .base = memory.ptr,
            .bump_ptr = memory.ptr,
            .end = memory.ptr + size,
            .size = size,
            .used = 0,
            .allocation_count = 0,
            .backing_allocator = allocator,
        };
    }

    pub fn deinit(self: *NurseryRegion) void {
        self.backing_allocator.free(self.base[0..self.size]);
    }

    /// O(1) 快速分配 - Bump Pointer
    pub fn alloc(self: *NurseryRegion, size: usize) ?*GCObjectHeader {
        const total_size = @sizeOf(GCObjectHeader) + size;
        const aligned_size = std.mem.alignForward(usize, total_size, @alignOf(GCObjectHeader));

        // 检查是否有足够空间
        const current: usize = @intFromPtr(self.bump_ptr);
        const end_addr: usize = @intFromPtr(self.end);

        if (current + aligned_size > end_addr) {
            return null; // 需要触发 Minor GC
        }

        // Bump pointer 分配
        const header: *GCObjectHeader = @ptrCast(@alignCast(self.bump_ptr));
        header.* = GCObjectHeader.init(@intCast(aligned_size));

        self.bump_ptr += aligned_size;
        self.used += aligned_size;
        self.allocation_count += 1;

        return header;
    }

    /// 重置 Nursery（Minor GC 后调用）
    pub fn reset(self: *NurseryRegion) void {
        self.bump_ptr = self.base;
        self.used = 0;
    }

    /// 获取使用率
    pub fn getUtilization(self: *NurseryRegion) f64 {
        if (self.size == 0) return 0.0;
        return @as(f64, @floatFromInt(self.used)) / @as(f64, @floatFromInt(self.size));
    }

    /// 检查是否需要 GC
    pub fn needsCollection(self: *NurseryRegion, threshold: f64) bool {
        return self.getUtilization() >= threshold;
    }
};

// ============================================================================
// Survivor Space - 双缓冲复制算法
// ============================================================================

pub const SurvivorSpace = struct {
    /// From 空间
    from_space: []u8,
    /// To 空间
    to_space: []u8,
    /// From 空间分配指针
    from_ptr: [*]u8,
    /// To 空间分配指针
    to_ptr: [*]u8,
    /// 单个空间大小
    space_size: usize,
    /// From 空间已使用
    from_used: usize,
    /// To 空间已使用
    to_used: usize,
    /// 后备分配器
    backing_allocator: std.mem.Allocator,
    /// 存活对象列表（用于遍历）
    live_objects: std.ArrayListUnmanaged(*GCObjectHeader),

    pub fn init(allocator: std.mem.Allocator, size: usize) !SurvivorSpace {
        const from = try allocator.alloc(u8, size);
        const to = try allocator.alloc(u8, size);

        return .{
            .from_space = from,
            .to_space = to,
            .from_ptr = from.ptr,
            .to_ptr = to.ptr,
            .space_size = size,
            .from_used = 0,
            .to_used = 0,
            .backing_allocator = allocator,
            .live_objects = .{},
        };
    }

    pub fn deinit(self: *SurvivorSpace) void {
        self.live_objects.deinit(self.backing_allocator);
        self.backing_allocator.free(self.from_space);
        self.backing_allocator.free(self.to_space);
    }

    /// 复制对象到 To 空间
    pub fn copyObject(self: *SurvivorSpace, header: *GCObjectHeader) ?*GCObjectHeader {
        const size = header.size;

        // 检查 To 空间是否有足够空间
        const current: usize = @intFromPtr(self.to_ptr);
        const end_addr: usize = @intFromPtr(self.to_space.ptr) + self.space_size;

        if (current + size > end_addr) {
            return null; // To 空间已满，需要晋升到老年代
        }

        // 复制对象
        const new_header: *GCObjectHeader = @ptrCast(@alignCast(self.to_ptr));
        const src_bytes: [*]u8 = @ptrCast(header);
        const dst_bytes: [*]u8 = @ptrCast(new_header);
        @memcpy(dst_bytes[0..size], src_bytes[0..size]);

        // 更新新对象的元数据
        new_header.generation = .survivor;
        new_header.age += 1;
        new_header.mark = .white;
        new_header.forwarded = false;
        new_header.forward_addr = null;

        // 设置转发指针
        header.forwarded = true;
        header.forward_addr = new_header;

        self.to_ptr += size;
        self.to_used += size;

        return new_header;
    }

    /// 交换 From 和 To 空间
    pub fn flip(self: *SurvivorSpace) void {
        // 交换空间
        const temp_space = self.from_space;
        self.from_space = self.to_space;
        self.to_space = temp_space;

        // 重置指针
        self.from_ptr = self.from_space.ptr;
        self.from_used = self.to_used;
        self.to_ptr = self.to_space.ptr;
        self.to_used = 0;

        // 清空 live_objects 列表
        self.live_objects.clearRetainingCapacity();
    }

    /// 添加存活对象到追踪列表
    pub fn trackObject(self: *SurvivorSpace, header: *GCObjectHeader) !void {
        try self.live_objects.append(self.backing_allocator, header);
    }

    /// 获取使用率
    pub fn getUtilization(self: *SurvivorSpace) f64 {
        if (self.space_size == 0) return 0.0;
        return @as(f64, @floatFromInt(self.from_used)) / @as(f64, @floatFromInt(self.space_size));
    }
};

// ============================================================================
// Old Generation - Segregated Fits Free List
// ============================================================================

pub const OldGeneration = struct {
    /// 后备分配器
    backing_allocator: std.mem.Allocator,
    /// 大小类别的空闲链表（按2的幂次分类）
    free_lists: [SIZE_CLASSES]?*FreeBlock,
    /// 已分配的内存块
    allocated_chunks: std.ArrayListUnmanaged(*MemoryChunk),
    /// 存活对象列表
    live_objects: std.ArrayListUnmanaged(*GCObjectHeader),
    /// 总分配大小
    total_size: usize,
    /// 已使用大小
    used_size: usize,
    /// 碎片化程度
    fragmentation: f64,

    const SIZE_CLASSES: usize = 16; // 16字节到512KB
    const MIN_SIZE_CLASS: usize = 4; // 2^4 = 16 字节最小
    const CHUNK_SIZE: usize = 1024 * 1024; // 1MB 块

    const FreeBlock = struct {
        size: usize,
        next: ?*FreeBlock,
    };

    const MemoryChunk = struct {
        data: []u8,
        used: usize,
    };

    pub fn init(allocator: std.mem.Allocator) OldGeneration {
        return .{
            .backing_allocator = allocator,
            .free_lists = [_]?*FreeBlock{null} ** SIZE_CLASSES,
            .allocated_chunks = .{},
            .live_objects = .{},
            .total_size = 0,
            .used_size = 0,
            .fragmentation = 0.0,
        };
    }

    pub fn deinit(self: *OldGeneration) void {
        for (self.allocated_chunks.items) |chunk| {
            self.backing_allocator.free(chunk.data);
            self.backing_allocator.destroy(chunk);
        }
        self.allocated_chunks.deinit(self.backing_allocator);
        self.live_objects.deinit(self.backing_allocator);
    }

    /// 获取大小类别索引
    fn getSizeClass(size: usize) usize {
        if (size == 0) return 0;
        const log2_size = std.math.log2_int(usize, size);
        if (log2_size < MIN_SIZE_CLASS) return 0;
        const class = log2_size - MIN_SIZE_CLASS;
        return @min(class, SIZE_CLASSES - 1);
    }

    /// 分配内存
    pub fn alloc(self: *OldGeneration, size: usize) !*GCObjectHeader {
        const total_size = @sizeOf(GCObjectHeader) + size;
        const aligned_size = std.mem.alignForward(usize, total_size, @alignOf(GCObjectHeader));

        // 尝试从空闲链表分配
        const size_class = getSizeClass(aligned_size);
        var class_idx = size_class;

        while (class_idx < SIZE_CLASSES) : (class_idx += 1) {
            if (self.free_lists[class_idx]) |block| {
                if (block.size >= aligned_size) {
                    // 从空闲链表移除
                    self.free_lists[class_idx] = block.next;

                    // 如果块太大，分割并返回剩余部分到空闲链表
                    const remaining = block.size - aligned_size;
                    if (remaining >= @sizeOf(FreeBlock) + 16) {
                        const new_block_ptr: [*]u8 = @ptrCast(block);
                        const new_block: *FreeBlock = @ptrCast(@alignCast(new_block_ptr + aligned_size));
                        new_block.size = remaining;
                        const new_class = getSizeClass(remaining);
                        new_block.next = self.free_lists[new_class];
                        self.free_lists[new_class] = new_block;
                    }

                    const header: *GCObjectHeader = @ptrCast(@alignCast(block));
                    header.* = GCObjectHeader.init(@intCast(aligned_size));
                    header.generation = .old;

                    self.used_size += aligned_size;
                    try self.live_objects.append(self.backing_allocator, header);

                    return header;
                }
            }
        }

        // 空闲链表没有合适的块，分配新的内存块
        const chunk_size = @max(CHUNK_SIZE, aligned_size);
        const chunk = try self.backing_allocator.create(MemoryChunk);
        chunk.data = try self.backing_allocator.alloc(u8, chunk_size);
        chunk.used = aligned_size;
        try self.allocated_chunks.append(self.backing_allocator, chunk);

        self.total_size += chunk_size;
        self.used_size += aligned_size;

        const header: *GCObjectHeader = @ptrCast(@alignCast(chunk.data.ptr));
        header.* = GCObjectHeader.init(@intCast(aligned_size));
        header.generation = .old;

        try self.live_objects.append(self.backing_allocator, header);

        // 将剩余空间加入空闲链表
        const remaining = chunk_size - aligned_size;
        if (remaining >= @sizeOf(FreeBlock) + 16) {
            const free_block: *FreeBlock = @ptrCast(@alignCast(chunk.data.ptr + aligned_size));
            free_block.size = remaining;
            const free_class = getSizeClass(remaining);
            free_block.next = self.free_lists[free_class];
            self.free_lists[free_class] = free_block;
        }

        return header;
    }

    /// 释放内存（加入空闲链表）
    pub fn free(self: *OldGeneration, header: *GCObjectHeader) void {
        const size = header.size;
        const block: *FreeBlock = @ptrCast(@alignCast(header));
        block.size = size;

        const size_class = getSizeClass(size);
        block.next = self.free_lists[size_class];
        self.free_lists[size_class] = block;

        self.used_size -= size;

        // 从存活对象列表移除
        for (self.live_objects.items, 0..) |obj, i| {
            if (obj == header) {
                _ = self.live_objects.swapRemove(i);
                break;
            }
        }
    }

    /// 合并相邻空闲块（碎片整理）
    pub fn coalesce(self: *OldGeneration) void {
        // 简化实现：重新计算碎片化程度
        var total_free: usize = 0;
        var free_block_count: usize = 0;

        for (self.free_lists) |maybe_block| {
            var block = maybe_block;
            while (block) |b| {
                total_free += b.size;
                free_block_count += 1;
                block = b.next;
            }
        }

        if (self.total_size > 0 and free_block_count > 0) {
            const avg_free_size = total_free / free_block_count;
            const ideal_free_size = total_free; // 理想情况下只有一个大块
            self.fragmentation = 1.0 - (@as(f64, @floatFromInt(avg_free_size)) / @as(f64, @floatFromInt(ideal_free_size)));
        } else {
            self.fragmentation = 0.0;
        }
    }

    /// 获取使用率
    pub fn getUtilization(self: *OldGeneration) f64 {
        if (self.total_size == 0) return 0.0;
        return @as(f64, @floatFromInt(self.used_size)) / @as(f64, @floatFromInt(self.total_size));
    }
};

// ============================================================================
// Large Object Space - 大对象空间
// ============================================================================

pub const LargeObjectSpace = struct {
    /// 后备分配器
    backing_allocator: std.mem.Allocator,
    /// 大对象链表
    objects: std.ArrayListUnmanaged(*LargeObject),
    /// 总大小
    total_size: usize,
    /// 对象数量
    object_count: usize,

    const LargeObject = struct {
        header: GCObjectHeader,
        data: []u8,
    };

    pub fn init(allocator: std.mem.Allocator) LargeObjectSpace {
        return .{
            .backing_allocator = allocator,
            .objects = .{},
            .total_size = 0,
            .object_count = 0,
        };
    }

    pub fn deinit(self: *LargeObjectSpace) void {
        for (self.objects.items) |obj| {
            self.backing_allocator.free(obj.data);
            self.backing_allocator.destroy(obj);
        }
        self.objects.deinit(self.backing_allocator);
    }

    /// 分配大对象
    pub fn alloc(self: *LargeObjectSpace, size: usize) !*GCObjectHeader {
        const obj = try self.backing_allocator.create(LargeObject);
        obj.data = try self.backing_allocator.alloc(u8, size);
        obj.header = GCObjectHeader.init(@intCast(size));
        obj.header.generation = .large;

        try self.objects.append(self.backing_allocator, obj);
        self.total_size += size;
        self.object_count += 1;

        return &obj.header;
    }

    /// 释放大对象
    pub fn free(self: *LargeObjectSpace, header: *GCObjectHeader) void {
        for (self.objects.items, 0..) |obj, i| {
            if (&obj.header == header) {
                self.total_size -= obj.data.len;
                self.object_count -= 1;
                self.backing_allocator.free(obj.data);
                self.backing_allocator.destroy(obj);
                _ = self.objects.swapRemove(i);
                break;
            }
        }
    }

    /// 标记所有存活对象
    pub fn markAll(self: *LargeObjectSpace) void {
        for (self.objects.items) |obj| {
            obj.header.mark = .white;
        }
    }

    /// 清除未标记对象
    pub fn sweep(self: *LargeObjectSpace) usize {
        var freed: usize = 0;
        var i: usize = 0;

        while (i < self.objects.items.len) {
            const obj = self.objects.items[i];
            if (obj.header.mark == .white) {
                freed += obj.data.len;
                self.total_size -= obj.data.len;
                self.object_count -= 1;

                // 调用析构函数
                if (obj.header.destructor) |dtor| {
                    dtor(obj.header.getDataPtr(), self.backing_allocator);
                }

                self.backing_allocator.free(obj.data);
                self.backing_allocator.destroy(obj);
                _ = self.objects.swapRemove(i);
            } else {
                obj.header.mark = .white; // 重置标记
                i += 1;
            }
        }

        return freed;
    }
};


// ============================================================================
// 增强型分代 GC 主结构
// ============================================================================

pub const EnhancedGenerationalGC = struct {
    /// 后备分配器
    allocator: std.mem.Allocator,
    /// Nursery 区
    nursery: NurseryRegion,
    /// Survivor 空间
    survivor: SurvivorSpace,
    /// 老年代
    old_gen: OldGeneration,
    /// 大对象空间
    large_space: LargeObjectSpace,
    /// Card Table（跨代引用追踪）
    card_table: ?*@import("card_table.zig").CardTable,
    /// GC 策略
    policy: ?*@import("gc_policy.zig").GCPolicy,
    /// 根集合
    roots: std.ArrayListUnmanaged(*GCObjectHeader),
    /// Remember Set（跨代引用）
    remember_set: std.AutoHashMapUnmanaged(*GCObjectHeader, void),
    /// 统计信息
    stats: GCStatistics,
    /// 配置
    config: GCConfig,

    pub const GCConfig = struct {
        nursery_size: usize = NURSERY_SIZE,
        survivor_size: usize = SURVIVOR_SIZE,
        large_object_threshold: usize = LARGE_OBJECT_THRESHOLD,
        promotion_age: u8 = MAX_PROMOTION_AGE,
        nursery_gc_threshold: f64 = 0.8, // 80% 触发 Minor GC
        old_gen_gc_threshold: f64 = 0.7, // 70% 触发 Major GC
    };

    pub const GCStatistics = struct {
        /// Minor GC 次数
        minor_gc_count: u64 = 0,
        /// Major GC 次数
        major_gc_count: u64 = 0,
        /// Full GC 次数
        full_gc_count: u64 = 0,
        /// 总分配字节数
        total_allocated: usize = 0,
        /// 总释放字节数
        total_freed: usize = 0,
        /// 晋升到 Survivor 的对象数
        promoted_to_survivor: u64 = 0,
        /// 晋升到老年代的对象数
        promoted_to_old: u64 = 0,
        /// 最近一次 Minor GC 耗时（纳秒）
        last_minor_gc_time_ns: u64 = 0,
        /// 最近一次 Major GC 耗时（纳秒）
        last_major_gc_time_ns: u64 = 0,
        /// 累计 GC 时间（纳秒）
        total_gc_time_ns: u64 = 0,
        /// 最大停顿时间（纳秒）
        max_pause_time_ns: u64 = 0,
        /// 写屏障触发次数
        write_barrier_count: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) !EnhancedGenerationalGC {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: GCConfig) !EnhancedGenerationalGC {
        return .{
            .allocator = allocator,
            .nursery = try NurseryRegion.init(allocator, config.nursery_size),
            .survivor = try SurvivorSpace.init(allocator, config.survivor_size),
            .old_gen = OldGeneration.init(allocator),
            .large_space = LargeObjectSpace.init(allocator),
            .card_table = null,
            .policy = null,
            .roots = .{},
            .remember_set = .{},
            .stats = .{},
            .config = config,
        };
    }

    pub fn deinit(self: *EnhancedGenerationalGC) void {
        self.nursery.deinit();
        self.survivor.deinit();
        self.old_gen.deinit();
        self.large_space.deinit();
        self.roots.deinit(self.allocator);
        self.remember_set.deinit(self.allocator);
    }

    /// 设置 Card Table
    pub fn setCardTable(self: *EnhancedGenerationalGC, card_table: *@import("card_table.zig").CardTable) void {
        self.card_table = card_table;
    }

    /// 设置 GC 策略
    pub fn setPolicy(self: *EnhancedGenerationalGC, policy_ptr: *@import("gc_policy.zig").GCPolicy) void {
        self.policy = policy_ptr;
    }

    /// 分配内存
    pub fn alloc(self: *EnhancedGenerationalGC, size: usize) !*GCObjectHeader {
        self.stats.total_allocated += size;

        // 大对象直接分配到大对象空间
        if (size >= self.config.large_object_threshold) {
            return try self.large_space.alloc(size);
        }

        // 尝试在 Nursery 分配
        if (self.nursery.alloc(size)) |header| {
            return header;
        }

        // Nursery 已满，触发 Minor GC
        try self.collectMinor();

        // 再次尝试分配
        if (self.nursery.alloc(size)) |header| {
            return header;
        }

        // 如果还是失败，直接分配到老年代
        return try self.old_gen.alloc(size);
    }

    /// 写屏障 - 检测跨代引用
    pub fn writeBarrier(self: *EnhancedGenerationalGC, old_obj: *GCObjectHeader, new_obj: *GCObjectHeader) !void {
        self.stats.write_barrier_count += 1;

        // 老年代对象引用年轻代对象
        if (old_obj.generation == .old and
            (new_obj.generation == .nursery or new_obj.generation == .survivor))
        {
            try self.remember_set.put(self.allocator, old_obj, {});

            // 更新 Card Table
            if (self.card_table) |ct| {
                ct.markDirty(@intFromPtr(old_obj));
            }
        }
    }

    /// 添加根对象
    pub fn addRoot(self: *EnhancedGenerationalGC, obj: *GCObjectHeader) !void {
        try self.roots.append(self.allocator, obj);
    }

    /// 移除根对象
    pub fn removeRoot(self: *EnhancedGenerationalGC, obj: *GCObjectHeader) void {
        for (self.roots.items, 0..) |root, i| {
            if (root == obj) {
                _ = self.roots.swapRemove(i);
                break;
            }
        }
    }

    /// Minor GC - 收集 Nursery 和 Survivor
    pub fn collectMinor(self: *EnhancedGenerationalGC) !void {
        const start_time = std.time.nanoTimestamp();
        self.stats.minor_gc_count += 1;

        // 1. 标记阶段 - 从根集合开始
        for (self.roots.items) |root| {
            self.markObject(root);
        }

        // 2. 处理 Remember Set（老年代到年轻代的引用）
        var iter = self.remember_set.iterator();
        while (iter.next()) |entry| {
            self.markObject(entry.key_ptr.*);
        }

        // 3. 复制存活对象到 Survivor 或晋升到老年代
        try self.copyLiveObjects();

        // 4. 重置 Nursery
        self.nursery.reset();

        // 5. 交换 Survivor 空间
        self.survivor.flip();

        // 6. 清理 Remember Set
        self.remember_set.clearRetainingCapacity();

        // 7. 清理 Card Table
        if (self.card_table) |ct| {
            ct.clearAll();
        }

        const end_time = std.time.nanoTimestamp();
        const gc_time: u64 = @intCast(end_time - start_time);
        self.stats.last_minor_gc_time_ns = gc_time;
        self.stats.total_gc_time_ns += gc_time;
        if (gc_time > self.stats.max_pause_time_ns) {
            self.stats.max_pause_time_ns = gc_time;
        }
    }

    /// Major GC - 收集老年代
    pub fn collectMajor(self: *EnhancedGenerationalGC) !void {
        const start_time = std.time.nanoTimestamp();
        self.stats.major_gc_count += 1;

        // 先执行 Minor GC
        try self.collectMinor();

        // 标记老年代对象
        for (self.old_gen.live_objects.items) |obj| {
            obj.mark = .white;
        }

        // 从根集合标记
        for (self.roots.items) |root| {
            self.markObjectDeep(root);
        }

        // 清除未标记的老年代对象
        var freed: usize = 0;
        var i: usize = 0;
        while (i < self.old_gen.live_objects.items.len) {
            const obj = self.old_gen.live_objects.items[i];
            if (obj.mark == .white) {
                // 调用析构函数
                if (obj.destructor) |dtor| {
                    dtor(obj.getDataPtr(), self.allocator);
                }
                self.old_gen.free(obj);
                freed += obj.size;
            } else {
                obj.mark = .white; // 重置标记
                i += 1;
            }
        }

        // 清除大对象空间
        freed += self.large_space.sweep();

        // 合并空闲块
        self.old_gen.coalesce();

        self.stats.total_freed += freed;

        const end_time = std.time.nanoTimestamp();
        const gc_time: u64 = @intCast(end_time - start_time);
        self.stats.last_major_gc_time_ns = gc_time;
        self.stats.total_gc_time_ns += gc_time;
        if (gc_time > self.stats.max_pause_time_ns) {
            self.stats.max_pause_time_ns = gc_time;
        }
    }

    /// Full GC - 完整收集
    pub fn collectFull(self: *EnhancedGenerationalGC) !void {
        self.stats.full_gc_count += 1;
        try self.collectMajor();
    }

    /// 标记对象（浅标记）
    fn markObject(self: *EnhancedGenerationalGC, obj: *GCObjectHeader) void {
        _ = self;
        if (obj.mark != .white) return;
        obj.mark = .black;
    }

    /// 深度标记对象（递归标记子对象）
    fn markObjectDeep(self: *EnhancedGenerationalGC, obj: *GCObjectHeader) void {
        if (obj.mark != .white) return;
        obj.mark = .black;

        // 这里需要根据对象类型遍历子对象
        // 简化实现：假设对象没有子引用
        _ = self;
    }

    /// 复制存活对象
    fn copyLiveObjects(self: *EnhancedGenerationalGC) !void {
        // 遍历 Nursery 中的对象（通过扫描内存）
        var ptr = self.nursery.base;
        const end = self.nursery.bump_ptr;

        while (@intFromPtr(ptr) < @intFromPtr(end)) {
            const header: *GCObjectHeader = @ptrCast(@alignCast(ptr));

            if (header.mark == .black) {
                // 对象存活
                if (header.age >= self.config.promotion_age) {
                    // 晋升到老年代
                    const new_header = try self.old_gen.alloc(header.size - @sizeOf(GCObjectHeader));
                    const src: [*]u8 = @ptrCast(header);
                    const dst: [*]u8 = @ptrCast(new_header);
                    @memcpy(dst[0..header.size], src[0..header.size]);
                    new_header.generation = .old;
                    new_header.mark = .white;

                    header.forwarded = true;
                    header.forward_addr = new_header;

                    self.stats.promoted_to_old += 1;
                } else {
                    // 复制到 Survivor
                    if (self.survivor.copyObject(header)) |new_header| {
                        try self.survivor.trackObject(new_header);
                        self.stats.promoted_to_survivor += 1;
                    } else {
                        // Survivor 已满，晋升到老年代
                        const new_header = try self.old_gen.alloc(header.size - @sizeOf(GCObjectHeader));
                        const src: [*]u8 = @ptrCast(header);
                        const dst: [*]u8 = @ptrCast(new_header);
                        @memcpy(dst[0..header.size], src[0..header.size]);
                        new_header.generation = .old;
                        new_header.mark = .white;

                        header.forwarded = true;
                        header.forward_addr = new_header;

                        self.stats.promoted_to_old += 1;
                    }
                }
            } else {
                // 对象死亡，调用析构函数
                if (header.destructor) |dtor| {
                    dtor(header.getDataPtr(), self.allocator);
                }
                self.stats.total_freed += header.size;
            }

            // 移动到下一个对象
            ptr += header.size;
        }

        // 处理 Survivor 中的对象
        for (self.survivor.live_objects.items) |header| {
            if (header.mark == .black) {
                if (header.age >= self.config.promotion_age) {
                    // 晋升到老年代
                    const new_header = try self.old_gen.alloc(header.size - @sizeOf(GCObjectHeader));
                    const src: [*]u8 = @ptrCast(header);
                    const dst: [*]u8 = @ptrCast(new_header);
                    @memcpy(dst[0..header.size], src[0..header.size]);
                    new_header.generation = .old;
                    new_header.mark = .white;

                    header.forwarded = true;
                    header.forward_addr = new_header;

                    self.stats.promoted_to_old += 1;
                } else {
                    // 保留在 Survivor
                    _ = self.survivor.copyObject(header);
                }
            } else {
                // 对象死亡
                if (header.destructor) |dtor| {
                    dtor(header.getDataPtr(), self.allocator);
                }
                self.stats.total_freed += header.size;
            }
        }
    }

    /// 检查是否需要 GC
    pub fn shouldCollect(self: *EnhancedGenerationalGC) bool {
        // 检查 Nursery 使用率
        if (self.nursery.needsCollection(self.config.nursery_gc_threshold)) {
            return true;
        }

        // 检查老年代使用率
        if (self.old_gen.getUtilization() >= self.config.old_gen_gc_threshold) {
            return true;
        }

        return false;
    }

    /// 获取统计信息
    pub fn getStats(self: *EnhancedGenerationalGC) GCStatistics {
        return self.stats;
    }

    /// 获取内存使用情况
    pub fn getMemoryUsage(self: *EnhancedGenerationalGC) MemoryUsage {
        return .{
            .nursery_used = self.nursery.used,
            .nursery_total = self.nursery.size,
            .survivor_used = self.survivor.from_used,
            .survivor_total = self.survivor.space_size,
            .old_gen_used = self.old_gen.used_size,
            .old_gen_total = self.old_gen.total_size,
            .large_space_used = self.large_space.total_size,
            .total_used = self.nursery.used + self.survivor.from_used + self.old_gen.used_size + self.large_space.total_size,
        };
    }

    pub const MemoryUsage = struct {
        nursery_used: usize,
        nursery_total: usize,
        survivor_used: usize,
        survivor_total: usize,
        old_gen_used: usize,
        old_gen_total: usize,
        large_space_used: usize,
        total_used: usize,
    };
};

// ============================================================================
// 测试
// ============================================================================

test "nursery bump pointer allocation" {
    var nursery = try NurseryRegion.init(std.testing.allocator, 4096);
    defer nursery.deinit();

    // 分配几个对象
    const obj1 = nursery.alloc(64);
    try std.testing.expect(obj1 != null);
    try std.testing.expect(obj1.?.generation == .nursery);

    const obj2 = nursery.alloc(128);
    try std.testing.expect(obj2 != null);

    // 检查使用量
    try std.testing.expect(nursery.used > 0);
    try std.testing.expect(nursery.allocation_count == 2);

    // 重置
    nursery.reset();
    try std.testing.expect(nursery.used == 0);
}

test "survivor space copy" {
    var survivor = try SurvivorSpace.init(std.testing.allocator, 4096);
    defer survivor.deinit();

    // 创建一个模拟对象头
    var header = GCObjectHeader.init(64);
    header.generation = .nursery;

    // 复制到 survivor
    const new_header = survivor.copyObject(&header);
    try std.testing.expect(new_header != null);
    try std.testing.expect(new_header.?.generation == .survivor);
    try std.testing.expect(new_header.?.age == 1);
    try std.testing.expect(header.forwarded == true);
}

test "old generation segregated fits" {
    var old_gen = OldGeneration.init(std.testing.allocator);
    defer old_gen.deinit();

    // 分配不同大小的对象
    const obj1 = try old_gen.alloc(32);
    try std.testing.expect(obj1.generation == .old);

    const obj2 = try old_gen.alloc(256);
    try std.testing.expect(obj2.generation == .old);

    // 释放第一个对象
    old_gen.free(obj1);

    // 再次分配相同大小，应该复用空闲块
    const obj3 = try old_gen.alloc(32);
    try std.testing.expect(obj3.generation == .old);
}

test "large object space" {
    var los = LargeObjectSpace.init(std.testing.allocator);
    defer los.deinit();

    // 分配大对象
    const obj = try los.alloc(16 * 1024); // 16KB
    try std.testing.expect(obj.generation == .large);
    try std.testing.expect(los.object_count == 1);
    try std.testing.expect(los.total_size == 16 * 1024);

    // 标记并清除
    los.markAll();
    const freed = los.sweep();
    try std.testing.expect(freed == 16 * 1024);
    try std.testing.expect(los.object_count == 0);
}

test "enhanced generational gc basic" {
    var gc = try EnhancedGenerationalGC.init(std.testing.allocator);
    defer gc.deinit();

    // 分配小对象
    const obj1 = try gc.alloc(64);
    try std.testing.expect(obj1.generation == .nursery);

    // 分配大对象
    const obj2 = try gc.alloc(16 * 1024);
    try std.testing.expect(obj2.generation == .large);

    // 检查统计
    try std.testing.expect(gc.stats.total_allocated > 0);
}

test "minor gc collection" {
    var gc = try EnhancedGenerationalGC.initWithConfig(std.testing.allocator, .{
        .nursery_size = 4096,
        .survivor_size = 2048,
        .promotion_age = 2,
    });
    defer gc.deinit();

    // 分配一些对象
    const obj1 = try gc.alloc(64);
    try gc.addRoot(obj1);

    _ = try gc.alloc(64); // 这个没有根引用，会被回收

    // 触发 Minor GC
    try gc.collectMinor();

    try std.testing.expect(gc.stats.minor_gc_count == 1);
}
