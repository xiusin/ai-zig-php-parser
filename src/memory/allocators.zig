const std = @import("std");
const Allocator = std.mem.Allocator;

/// 内存池分配器（小对象）
pub const PoolAllocator = struct {
    pools: [6]Pool,
    allocator: Allocator,

    const size_classes = [_]usize{ 8, 16, 32, 64, 128, 256 };

    pub fn init(allocator: Allocator) PoolAllocator {
        var pools: [6]Pool = undefined;
        for (&pools, 0..) |*pool, i| {
            pool.* = Pool.init(size_classes[i]);
        }
        return PoolAllocator{
            .pools = pools,
            .allocator = allocator,
        };
    }

    pub fn alloc(self: *PoolAllocator, size: usize) ![]u8 {
        for (self.pools, 0..) |*pool, i| {
            if (size <= size_classes[i]) {
                return try pool.alloc(self.allocator);
            }
        }
        return try self.allocator.alloc(u8, size);
    }

    pub fn free(self: *PoolAllocator, ptr: []u8) void {
        for (&self.pools) |*pool| {
            if (pool.owns(ptr)) {
                pool.free(ptr);
                return;
            }
        }
        self.allocator.free(ptr);
    }
};

const Pool = struct {
    size: usize,
    free_list: std.ArrayList([]u8),

    fn init(size: usize) Pool {
        return Pool{
            .size = size,
            .free_list = std.ArrayList([]u8).init(std.heap.page_allocator),
        };
    }

    fn alloc(self: *Pool, allocator: Allocator) ![]u8 {
        if (self.free_list.items.len > 0) {
            return self.free_list.pop();
        }
        return try allocator.alloc(u8, self.size);
    }

    fn free(self: *Pool, ptr: []u8) void {
        self.free_list.append(ptr) catch {};
    }

    fn owns(self: *Pool, ptr: []u8) bool {
        return ptr.len == self.size;
    }
};

/// Arena 分配器（临时对象）
pub const ArenaAllocator = struct {
    buffer: []u8,
    offset: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, size: usize) !ArenaAllocator {
        return ArenaAllocator{
            .buffer = try allocator.alloc(u8, size),
            .offset = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ArenaAllocator) void {
        self.allocator.free(self.buffer);
    }

    pub fn alloc(self: *ArenaAllocator, size: usize) ![]u8 {
        if (self.offset + size > self.buffer.len) {
            return error.OutOfMemory;
        }
        const ptr = self.buffer[self.offset .. self.offset + size];
        self.offset += size;
        return ptr;
    }

    pub fn reset(self: *ArenaAllocator) void {
        self.offset = 0;
    }
};

/// Slab 分配器（固定大小）
pub const SlabAllocator = struct {
    slabs: std.ArrayList(Slab),
    object_size: usize,
    allocator: Allocator,

    const slab_size = 64;

    pub fn init(allocator: Allocator, object_size: usize) !SlabAllocator {
        return SlabAllocator{
            .slabs = try std.ArrayList(Slab).initCapacity(allocator, 0),
            .object_size = object_size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SlabAllocator) void {
        for (self.slabs.items) |slab| {
            self.allocator.free(slab.memory);
        }
        self.slabs.deinit(self.allocator);
    }

    pub fn alloc(self: *SlabAllocator) ![]u8 {
        for (self.slabs.items) |*slab| {
            if (slab.free_bitmap != 0) {
                const idx = @ctz(slab.free_bitmap);
                slab.free_bitmap &= ~(@as(u64, 1) << @intCast(idx));
                const offset = idx * self.object_size;
                return slab.memory[offset .. offset + self.object_size];
            }
        }

        // 分配新 slab
        const memory = try self.allocator.alloc(u8, slab_size * self.object_size);
        const slab = Slab{
            .memory = memory,
            .free_bitmap = ~@as(u64, 1), // 第一个已分配
        };
        try self.slabs.append(self.allocator, slab);
        return memory[0..self.object_size];
    }
};

const Slab = struct {
    memory: []u8,
    free_bitmap: u64,
};

/// Bump 分配器（短生命周期）
pub const BumpAllocator = struct {
    buffer: []u8,
    offset: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, size: usize) !BumpAllocator {
        return BumpAllocator{
            .buffer = try allocator.alloc(u8, size),
            .offset = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BumpAllocator) void {
        self.allocator.free(self.buffer);
    }

    pub fn alloc(self: *BumpAllocator, size: usize) ![]u8 {
        if (self.offset + size > self.buffer.len) {
            return error.OutOfMemory;
        }
        const ptr = self.buffer[self.offset .. self.offset + size];
        self.offset += size;
        return ptr;
    }

    pub fn reset(self: *BumpAllocator) void {
        self.offset = 0;
    }
};
