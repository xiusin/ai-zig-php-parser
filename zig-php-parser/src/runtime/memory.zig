const std = @import("std");

/// 极致内存管理系统
/// 设计目标：零内存泄漏、60%内存占用降低、亚毫秒级GC停顿

// ============================================================================
// Arena分配器 - 批量分配，一次释放
// ============================================================================

pub const ArenaAllocator = struct {
    child_allocator: std.mem.Allocator,
    chunks: ChunkList,
    current_chunk: ?*Chunk,
    total_allocated: usize,
    total_used: usize,

    const DEFAULT_CHUNK_SIZE: usize = 64 * 1024;
    const ChunkList = std.ArrayListUnmanaged(*Chunk);

    const Chunk = struct {
        data: []u8,
        offset: usize,

        fn create(backing: std.mem.Allocator, size: usize) !*Chunk {
            const chunk = try backing.create(Chunk);
            chunk.data = try backing.alloc(u8, size);
            chunk.offset = 0;
            return chunk;
        }

        fn destroy(self: *Chunk, backing: std.mem.Allocator) void {
            backing.free(self.data);
            backing.destroy(self);
        }

        fn tryAlloc(self: *Chunk, size: usize, alignment: usize) ?[]u8 {
            const aligned = std.mem.alignForward(usize, self.offset, alignment);
            if (aligned + size > self.data.len) return null;
            const result = self.data[aligned .. aligned + size];
            self.offset = aligned + size;
            return result;
        }
    };

    pub fn init(child: std.mem.Allocator) ArenaAllocator {
        return .{
            .child_allocator = child,
            .chunks = .{},
            .current_chunk = null,
            .total_allocated = 0,
            .total_used = 0,
        };
    }

    pub fn deinit(self: *ArenaAllocator) void {
        self.freeAll();
        self.chunks.deinit(self.child_allocator);
    }

    pub fn freeAll(self: *ArenaAllocator) void {
        for (self.chunks.items) |chunk| {
            chunk.destroy(self.child_allocator);
        }
        self.chunks.clearRetainingCapacity();
        self.current_chunk = null;
        self.total_allocated = 0;
        self.total_used = 0;
    }

    pub fn reset(self: *ArenaAllocator) void {
        for (self.chunks.items) |chunk| {
            chunk.offset = 0;
        }
        self.current_chunk = if (self.chunks.items.len > 0) self.chunks.items[0] else null;
        self.total_used = 0;
    }

    pub fn alloc(self: *ArenaAllocator, comptime T: type, n: usize) ![]T {
        const size = @sizeOf(T) * n;
        const alignment = @alignOf(T);

        if (self.current_chunk) |chunk| {
            if (chunk.tryAlloc(size, alignment)) |bytes| {
                self.total_used += size;
                return @as([*]T, @ptrCast(@alignCast(bytes.ptr)))[0..n];
            }
        }

        const chunk_size = @max(DEFAULT_CHUNK_SIZE, size + alignment);
        const new_chunk = try Chunk.create(self.child_allocator, chunk_size);
        try self.chunks.append(self.child_allocator, new_chunk);
        self.current_chunk = new_chunk;
        self.total_allocated += chunk_size;

        if (new_chunk.tryAlloc(size, alignment)) |bytes| {
            self.total_used += size;
            return @as([*]T, @ptrCast(@alignCast(bytes.ptr)))[0..n];
        }
        return error.OutOfMemory;
    }

    pub fn getStats(self: *ArenaAllocator) MemoryStats {
        return .{
            .total_allocated = self.total_allocated,
            .total_used = self.total_used,
            .chunk_count = self.chunks.items.len,
            .utilization = if (self.total_allocated > 0)
                @as(f64, @floatFromInt(self.total_used)) / @as(f64, @floatFromInt(self.total_allocated))
            else
                0.0,
        };
    }
};

// ============================================================================
// 对象池 - 固定大小对象的高效复用
// ============================================================================

pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();
        const CHUNK_SIZE: usize = 256;

        allocator: std.mem.Allocator,
        free_list: ?*Node,
        chunks: std.ArrayListUnmanaged(*[CHUNK_SIZE]Node),
        allocated_count: usize,
        recycled_count: usize,
        active_count: usize,

        const Node = struct {
            data: T,
            next: ?*Node,
            in_use: bool,
        };

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .allocator = alloc,
                .free_list = null,
                .chunks = .{},
                .allocated_count = 0,
                .recycled_count = 0,
                .active_count = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.chunks.items) |chunk| {
                self.allocator.destroy(chunk);
            }
            self.chunks.deinit(self.allocator);
        }

        pub fn acquire(self: *Self) !*T {
            if (self.free_list) |node| {
                self.free_list = node.next;
                node.in_use = true;
                node.next = null;
                self.active_count += 1;
                self.recycled_count += 1;
                return &node.data;
            }

            const chunk = try self.allocator.create([CHUNK_SIZE]Node);
            try self.chunks.append(self.allocator, chunk);

            for (chunk[1..]) |*node| {
                node.next = self.free_list;
                node.in_use = false;
                self.free_list = node;
            }

            chunk[0].in_use = true;
            chunk[0].next = null;
            self.allocated_count += CHUNK_SIZE;
            self.active_count += 1;
            return &chunk[0].data;
        }

        pub fn release(self: *Self, ptr: *T) void {
            const node: *Node = @fieldParentPtr("data", ptr);
            if (!node.in_use) return;
            node.in_use = false;
            node.next = self.free_list;
            self.free_list = node;
            self.active_count -= 1;
        }

        pub fn getStats(self: *Self) PoolStats {
            const total = self.allocated_count + self.recycled_count;
            return .{
                .allocated_count = self.allocated_count,
                .active_count = self.active_count,
                .recycled_count = self.recycled_count,
                .pool_efficiency = if (total > 0)
                    @as(f64, @floatFromInt(self.recycled_count)) / @as(f64, @floatFromInt(total))
                else
                    0.0,
            };
        }
    };
}

// ============================================================================
// 字符串驻留池 - 相同字符串共享存储
// ============================================================================

pub const StringInterner = struct {
    allocator: std.mem.Allocator,
    strings: std.StringHashMapUnmanaged(InternedString),
    total_strings: usize,
    total_bytes: usize,
    bytes_saved: usize,
    hit_count: usize,
    miss_count: usize,

    const InternedString = struct {
        data: []const u8,
        ref_count: u32,
    };

    pub fn init(alloc: std.mem.Allocator) StringInterner {
        return .{
            .allocator = alloc,
            .strings = .{},
            .total_strings = 0,
            .total_bytes = 0,
            .bytes_saved = 0,
            .hit_count = 0,
            .miss_count = 0,
        };
    }

    pub fn deinit(self: *StringInterner) void {
        var iter = self.strings.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(@constCast(entry.value_ptr.data));
        }
        self.strings.deinit(self.allocator);
    }

    pub fn intern(self: *StringInterner, str: []const u8) ![]const u8 {
        if (self.strings.getPtr(str)) |entry| {
            entry.ref_count += 1;
            self.hit_count += 1;
            self.bytes_saved += str.len;
            return entry.data;
        }

        const owned = try self.allocator.dupe(u8, str);
        try self.strings.put(self.allocator, owned, .{
            .data = owned,
            .ref_count = 1,
        });

        self.miss_count += 1;
        self.total_strings += 1;
        self.total_bytes += str.len;
        return owned;
    }

    pub fn release(self: *StringInterner, str: []const u8) void {
        if (self.strings.getPtr(str)) |entry| {
            if (entry.ref_count > 0) entry.ref_count -= 1;
            if (entry.ref_count == 0) {
                self.allocator.free(@constCast(entry.data));
                _ = self.strings.remove(str);
                self.total_strings -= 1;
                self.total_bytes -= str.len;
            }
        }
    }

    pub fn getStats(self: *StringInterner) InternStats {
        const total = self.hit_count + self.miss_count;
        return .{
            .total_strings = self.total_strings,
            .total_bytes = self.total_bytes,
            .bytes_saved = self.bytes_saved,
            .hit_rate = if (total > 0)
                @as(f64, @floatFromInt(self.hit_count)) / @as(f64, @floatFromInt(total))
            else
                0.0,
        };
    }
};

// ============================================================================
// 分代垃圾回收器
// ============================================================================

pub const GenerationalGC = struct {
    allocator: std.mem.Allocator,
    young_objects: std.ArrayListUnmanaged(*GCObject),
    old_objects: std.ArrayListUnmanaged(*GCObject),
    roots: std.ArrayListUnmanaged(*GCObject),
    remember_set: std.AutoHashMapUnmanaged(*GCObject, void),
    write_barrier_enabled: bool,
    stats: GCStats,
    young_threshold: usize,
    promotion_age: u8,

    pub const GCObject = struct {
        mark: Mark,
        age: u8,
        size: usize,
        gen: Gen,
        destructor: ?*const fn (*GCObject, std.mem.Allocator) void,

        pub const Mark = enum(u2) { white = 0, gray = 1, black = 2 };
        pub const Gen = enum(u1) { young = 0, old = 1 };
    };

    pub fn init(alloc: std.mem.Allocator) GenerationalGC {
        return .{
            .allocator = alloc,
            .young_objects = .{},
            .old_objects = .{},
            .roots = .{},
            .remember_set = .{},
            .write_barrier_enabled = true,
            .stats = .{},
            .young_threshold = 4 * 1024 * 1024,
            .promotion_age = 3,
        };
    }

    pub fn deinit(self: *GenerationalGC) void {
        for (self.young_objects.items) |obj| self.allocator.destroy(obj);
        for (self.old_objects.items) |obj| self.allocator.destroy(obj);
        self.young_objects.deinit(self.allocator);
        self.old_objects.deinit(self.allocator);
        self.roots.deinit(self.allocator);
        self.remember_set.deinit(self.allocator);
    }

    pub fn create(self: *GenerationalGC, size: usize) !*GCObject {
        const obj = try self.allocator.create(GCObject);
        obj.* = .{
            .mark = .white,
            .age = 0,
            .size = size,
            .gen = .young,
            .destructor = null,
        };
        try self.young_objects.append(self.allocator, obj);
        self.stats.total_allocated += size;
        return obj;
    }

    pub fn writeBarrier(self: *GenerationalGC, old_obj: *GCObject, new_obj: *GCObject) !void {
        if (!self.write_barrier_enabled) return;
        if (old_obj.gen == .old and new_obj.gen == .young) {
            try self.remember_set.put(self.allocator, old_obj, {});
            self.stats.write_barrier_triggers += 1;
        }
    }

    pub fn collectYoung(self: *GenerationalGC) !void {
        const start = std.time.nanoTimestamp();
        self.stats.young_gc_count += 1;

        for (self.roots.items) |root| self.markObject(root);

        var iter = self.remember_set.iterator();
        while (iter.next()) |entry| self.markObject(entry.key_ptr.*);

        var survivors: std.ArrayListUnmanaged(*GCObject) = .{};
        defer survivors.deinit(self.allocator);

        for (self.young_objects.items) |obj| {
            if (obj.mark == .black) {
                obj.age += 1;
                obj.mark = .white;
                if (obj.age >= self.promotion_age) {
                    obj.gen = .old;
                    try self.old_objects.append(self.allocator, obj);
                    self.stats.promoted_objects += 1;
                } else {
                    try survivors.append(self.allocator, obj);
                }
            } else {
                if (obj.destructor) |dtor| dtor(obj, self.allocator);
                self.stats.total_freed += obj.size;
                self.allocator.destroy(obj);
            }
        }

        self.young_objects.clearRetainingCapacity();
        for (survivors.items) |obj| {
            try self.young_objects.append(self.allocator, obj);
        }
        self.remember_set.clearRetainingCapacity();

        const end = std.time.nanoTimestamp();
        self.stats.total_gc_time_ns += @intCast(end - start);
    }

    fn markObject(_: *GenerationalGC, obj: *GCObject) void {
        if (obj.mark != .white) return;
        obj.mark = .black;
    }

    pub fn addRoot(self: *GenerationalGC, obj: *GCObject) !void {
        try self.roots.append(self.allocator, obj);
    }

    pub fn removeRoot(self: *GenerationalGC, obj: *GCObject) void {
        for (self.roots.items, 0..) |root, i| {
            if (root == obj) {
                _ = self.roots.swapRemove(i);
                break;
            }
        }
    }

    pub fn getStats(self: *GenerationalGC) GCStats {
        return self.stats;
    }
};

// ============================================================================
// 内存泄漏检测器
// ============================================================================

pub const LeakDetector = struct {
    allocator: std.mem.Allocator,
    allocations: std.AutoHashMapUnmanaged(usize, AllocationInfo),
    total_allocations: usize,
    total_frees: usize,
    peak_memory: usize,
    current_memory: usize,
    enabled: bool,

    const AllocationInfo = struct {
        size: usize,
        timestamp: i64,
    };

    pub fn init(alloc: std.mem.Allocator) LeakDetector {
        return .{
            .allocator = alloc,
            .allocations = .{},
            .total_allocations = 0,
            .total_frees = 0,
            .peak_memory = 0,
            .current_memory = 0,
            .enabled = true,
        };
    }

    pub fn deinit(self: *LeakDetector) void {
        self.allocations.deinit(self.allocator);
    }

    pub fn recordAlloc(self: *LeakDetector, ptr: usize, size: usize) !void {
        if (!self.enabled) return;
        try self.allocations.put(self.allocator, ptr, .{
            .size = size,
            .timestamp = std.time.timestamp(),
        });
        self.total_allocations += 1;
        self.current_memory += size;
        if (self.current_memory > self.peak_memory) {
            self.peak_memory = self.current_memory;
        }
    }

    pub fn recordFree(self: *LeakDetector, ptr: usize) void {
        if (!self.enabled) return;
        if (self.allocations.get(ptr)) |info| {
            self.current_memory -= info.size;
            self.total_frees += 1;
            _ = self.allocations.remove(ptr);
        }
    }

    pub fn checkLeaks(self: *LeakDetector) LeakReport {
        var leaked_bytes: usize = 0;
        var leaked_count: usize = 0;
        var iter = self.allocations.iterator();
        while (iter.next()) |entry| {
            leaked_bytes += entry.value_ptr.size;
            leaked_count += 1;
        }
        return .{
            .leaked_allocations = leaked_count,
            .leaked_bytes = leaked_bytes,
            .total_allocations = self.total_allocations,
            .total_frees = self.total_frees,
            .peak_memory = self.peak_memory,
            .has_leaks = leaked_count > 0,
        };
    }

    pub fn printReport(self: *LeakDetector) void {
        const report = self.checkLeaks();
        std.log.info("=== Memory Leak Report ===", .{});
        std.log.info("Allocations: {}, Frees: {}, Peak: {} bytes", .{
            report.total_allocations,
            report.total_frees,
            report.peak_memory,
        });
        if (report.has_leaks) {
            std.log.warn("LEAKS: {} allocations, {} bytes", .{
                report.leaked_allocations,
                report.leaked_bytes,
            });
        } else {
            std.log.info("No memory leaks detected!", .{});
        }
    }
};

// ============================================================================
// 统一内存管理器
// ============================================================================

pub const MemoryManager = struct {
    allocator: std.mem.Allocator,
    arena: ArenaAllocator,
    string_pool: StringInterner,
    gc: GenerationalGC,
    leak_detector: LeakDetector,

    pub fn init(alloc: std.mem.Allocator) MemoryManager {
        return .{
            .allocator = alloc,
            .arena = ArenaAllocator.init(alloc),
            .string_pool = StringInterner.init(alloc),
            .gc = GenerationalGC.init(alloc),
            .leak_detector = LeakDetector.init(alloc),
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        self.leak_detector.printReport();
        self.gc.deinit();
        self.string_pool.deinit();
        self.arena.deinit();
        self.leak_detector.deinit();
    }

    pub fn getStats(self: *MemoryManager) MemoryManagerStats {
        return .{
            .arena_stats = self.arena.getStats(),
            .string_stats = self.string_pool.getStats(),
            .gc_stats = self.gc.getStats(),
            .leak_report = self.leak_detector.checkLeaks(),
        };
    }

    pub fn minorGC(self: *MemoryManager) !void {
        try self.gc.collectYoung();
    }
};

// ============================================================================
// 统计结构体
// ============================================================================

pub const MemoryStats = struct {
    total_allocated: usize,
    total_used: usize,
    chunk_count: usize,
    utilization: f64,
};

pub const PoolStats = struct {
    allocated_count: usize,
    active_count: usize,
    recycled_count: usize,
    pool_efficiency: f64,
};

pub const InternStats = struct {
    total_strings: usize,
    total_bytes: usize,
    bytes_saved: usize,
    hit_rate: f64,
};

pub const GCStats = struct {
    young_gc_count: u32 = 0,
    old_gc_count: u32 = 0,
    total_allocated: usize = 0,
    total_freed: usize = 0,
    promoted_objects: usize = 0,
    write_barrier_triggers: usize = 0,
    total_gc_time_ns: u64 = 0,
};

pub const LeakReport = struct {
    leaked_allocations: usize,
    leaked_bytes: usize,
    total_allocations: usize,
    total_frees: usize,
    peak_memory: usize,
    has_leaks: bool,
};

pub const MemoryManagerStats = struct {
    arena_stats: MemoryStats,
    string_stats: InternStats,
    gc_stats: GCStats,
    leak_report: LeakReport,
};

// ============================================================================
// 测试
// ============================================================================

test "arena allocator" {
    var arena = ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = try arena.alloc(u8, 100);
    try std.testing.expect(data.len == 100);
    try std.testing.expect(arena.total_used >= 100);
}

test "object pool" {
    var pool = ObjectPool(u64).init(std.testing.allocator);
    defer pool.deinit();

    const obj1 = try pool.acquire();
    obj1.* = 42;
    pool.release(obj1);

    const obj2 = try pool.acquire();
    try std.testing.expect(obj2 == obj1);
    try std.testing.expect(pool.getStats().recycled_count == 1);
}

test "string interner" {
    var interner = StringInterner.init(std.testing.allocator);
    defer interner.deinit();

    const s1 = try interner.intern("hello");
    const s2 = try interner.intern("hello");
    try std.testing.expect(s1.ptr == s2.ptr);
    try std.testing.expect(interner.getStats().hit_rate > 0.0);
}

test "leak detector" {
    var detector = LeakDetector.init(std.testing.allocator);
    defer detector.deinit();

    try detector.recordAlloc(0x1000, 100);
    try detector.recordAlloc(0x2000, 200);
    detector.recordFree(0x1000);

    const report = detector.checkLeaks();
    try std.testing.expect(report.leaked_allocations == 1);
    try std.testing.expect(report.leaked_bytes == 200);
}

test "generational gc" {
    var gc_instance = GenerationalGC.init(std.testing.allocator);
    defer gc_instance.deinit();

    const obj = try gc_instance.create(100);
    try std.testing.expect(obj.gen == .young);
    try gc_instance.addRoot(obj);
    try gc_instance.collectYoung();
    try std.testing.expect(obj.age == 1);
}
