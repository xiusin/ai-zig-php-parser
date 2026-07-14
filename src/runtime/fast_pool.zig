//! 高性能内存池系统
//! 目标：减少90%动态分配，O(1)分配/释放，缓存友好
//!
//! 核心技术：
//! 1. Slab Allocator - 固定大小对象高效分配
//! 2. Free List - O(1) 分配释放
//! 3. Cache Line 对齐 - 64字节对齐避免伪共享
//! 4. 批量预分配 - 减少系统调用

const std = @import("std");
const types = @import("types.zig");

/// Cache line 大小
pub const CACHE_LINE = 64;

// ============================================================================
// Slab 分配器 - 固定大小对象的极速分配
// ============================================================================

pub fn SlabAllocator(comptime T: type) type {
    return struct {
        const Self = @This();
        const SLAB_SIZE: usize = @max(4096 / @max(@sizeOf(T), 8), 32);

        const Node = struct {
            next: ?*Node,
        };

        alloc: std.mem.Allocator,
        free_head: ?*Node,
        chunks: std.ArrayListUnmanaged([]u8),
        stats: Stats,

        pub const Stats = struct {
            allocated: usize = 0,
            in_use: usize = 0,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .alloc = allocator,
                .free_head = null,
                .chunks = .{ .items = &.{}, .capacity = 0 },
                .stats = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.chunks.items) |chunk| {
                self.alloc.free(chunk);
            }
            self.chunks.deinit(self.alloc);
        }

        /// O(1) 分配
        pub fn create(self: *Self) !*T {
            if (self.free_head) |node| {
                self.free_head = node.next;
                self.stats.in_use += 1;
                return @ptrCast(@alignCast(node));
            }
            return self.allocChunk();
        }

        /// O(1) 释放
        pub fn destroy(self: *Self, ptr: *T) void {
            const node: *Node = @ptrCast(@alignCast(ptr));
            node.next = self.free_head;
            self.free_head = node;
            self.stats.in_use -= 1;
        }

        fn allocChunk(self: *Self) !*T {
            const chunk = try self.alloc.alloc(u8, SLAB_SIZE * @sizeOf(T));
            try self.chunks.append(self.alloc, chunk);
            self.stats.allocated += SLAB_SIZE;

            // 链接空闲节点（跳过第一个）
            var i: usize = SLAB_SIZE - 1;
            while (i > 0) : (i -= 1) {
                const node: *Node = @ptrCast(@alignCast(chunk.ptr + i * @sizeOf(T)));
                node.next = self.free_head;
                self.free_head = node;
            }

            self.stats.in_use += 1;
            return @ptrCast(@alignCast(chunk.ptr));
        }

        pub fn getStats(self: *const Self) Stats {
            return self.stats;
        }
    };
}

// ============================================================================
// Bump 分配器 - 超快临时分配（只增不减，批量释放）
// ============================================================================

pub const BumpAllocator = struct {
    const CHUNK_SIZE = 64 * 1024;

    const Chunk = struct {
        data: []u8,
        next: ?*Chunk,
    };

    backing: std.mem.Allocator,
    chunk: ?*Chunk,
    offset: usize,
    head: ?*Chunk,
    total: usize,

    pub fn init(backing: std.mem.Allocator) BumpAllocator {
        return .{
            .backing = backing,
            .chunk = null,
            .offset = 0,
            .head = null,
            .total = 0,
        };
    }

    pub fn deinit(self: *BumpAllocator) void {
        self.freeAll();
    }

    /// 超快分配 - 仅指针加法
    pub fn alloc(self: *BumpAllocator, comptime T: type, n: usize) ![]T {
        const size = @sizeOf(T) * n;
        const alignment = @alignOf(T);
        const aligned = std.mem.alignForward(usize, self.offset, alignment);

        if (self.chunk) |c| {
            if (aligned + size <= c.data.len) {
                const ptr: [*]T = @ptrCast(@alignCast(c.data.ptr + aligned));
                self.offset = aligned + size;
                return ptr[0..n];
            }
        }

        // 分配新 chunk
        const chunk_size = @max(CHUNK_SIZE, size + alignment);
        const new = try self.backing.create(Chunk);
        new.data = try self.backing.alloc(u8, chunk_size);
        new.next = self.head;
        self.head = new;
        self.chunk = new;
        self.offset = size;
        self.total += chunk_size;

        const ptr: [*]T = @ptrCast(@alignCast(new.data.ptr));
        return ptr[0..n];
    }

    pub fn create(self: *BumpAllocator, comptime T: type) !*T {
        const slice = try self.alloc(T, 1);
        return &slice[0];
    }

    /// 重置（保留内存）
    pub fn reset(self: *BumpAllocator) void {
        self.chunk = self.head;
        self.offset = 0;
    }

    /// 释放所有
    pub fn freeAll(self: *BumpAllocator) void {
        var c = self.head;
        while (c) |chunk| {
            const next = chunk.next;
            self.backing.free(chunk.data);
            self.backing.destroy(chunk);
            c = next;
        }
        self.head = null;
        self.chunk = null;
        self.offset = 0;
        self.total = 0;
    }
};

// ============================================================================
// 多大小池 - 支持多种固定大小
// ============================================================================

pub const MultiPool = struct {
    const SIZES = [_]usize{ 16, 32, 64, 128, 256, 512, 1024 };

    const FreeNode = struct { next: ?*FreeNode };

    backing: std.mem.Allocator,
    lists: [SIZES.len]?*FreeNode,
    chunks: std.ArrayListUnmanaged([]u8),

    pub fn init(backing: std.mem.Allocator) MultiPool {
        return .{
            .backing = backing,
            .lists = @splat(null),
            .chunks = .{ .items = &.{}, .capacity = 0 },
        };
    }

    pub fn deinit(self: *MultiPool) void {
        for (self.chunks.items) |c| self.backing.free(c);
        self.chunks.deinit(self.backing);
    }

    fn sizeClass(size: usize) ?usize {
        for (SIZES, 0..) |s, i| if (size <= s) return i;
        return null;
    }

    pub fn alloc(self: *MultiPool, size: usize) ![]u8 {
        const idx = sizeClass(size) orelse return error.SizeTooLarge;
        const class_size = SIZES[idx];

        if (self.lists[idx]) |node| {
            self.lists[idx] = node.next;
            return @as([*]u8, @ptrCast(node))[0..size];
        }

        // 分配新块
        const count = 4096 / class_size;
        const chunk = try self.backing.alloc(u8, class_size * count);
        try self.chunks.append(self.backing, chunk);

        // 初始化 free list
        var i: usize = count - 1;
        while (i > 0) : (i -= 1) {
            const node: *FreeNode = @ptrCast(@alignCast(chunk.ptr + i * class_size));
            node.next = self.lists[idx];
            self.lists[idx] = node;
        }

        return chunk[0..size];
    }

    pub fn free(self: *MultiPool, ptr: []u8) void {
        const idx = sizeClass(ptr.len) orelse return;
        const node: *FreeNode = @ptrCast(@alignCast(ptr.ptr));
        node.next = self.lists[idx];
        self.lists[idx] = node;
    }
};

// ============================================================================
// 小整数缓存
// ============================================================================

pub fn IntCache(comptime T: type, comptime min: T, comptime max: T) type {
    return struct {
        const Self = @This();
        const SIZE = @as(usize, @intCast(max - min + 1));

        values: [SIZE]T = blk: {
            var arr: [SIZE]T = undefined;
            var v: T = min;
            for (&arr) |*p| {
                p.* = v;
                v += 1;
            }
            break :blk arr;
        },

        pub fn get(self: *const Self, v: T) ?*const T {
            if (v >= min and v <= max) {
                return &self.values[@intCast(v - min)];
            }
            return null;
        }

        pub fn contains(v: T) bool {
            return v >= min and v <= max;
        }
    };
}

// ============================================================================
// 全局池管理器
// ============================================================================

pub const PoolManager = struct {
    bump: BumpAllocator,
    multi: MultiPool,
    small_ints: IntCache(i64, -128, 127),

    pub fn init(backing: std.mem.Allocator) PoolManager {
        return .{
            .bump = BumpAllocator.init(backing),
            .multi = MultiPool.init(backing),
            .small_ints = .{},
        };
    }

    pub fn deinit(self: *PoolManager) void {
        self.bump.deinit();
        self.multi.deinit();
    }

    pub fn resetTemp(self: *PoolManager) void {
        self.bump.reset();
    }
};

// ============================================================================
// PHPString 专用池 - 优化字符串对象分配
// ============================================================================

/// PHPString 池化结构（与 types.PHPString 布局兼容）
pub const PooledString = struct {
    data: []u8,
    length: usize,
    encoding: Encoding,
    ref_count: usize,
    pool_managed: bool, // 标记是否由池管理

    pub const Encoding = enum {
        utf8,
        ascii,
        binary,
    };
};

pub const PHPStringPool = struct {
    const Self = @This();

    /// 字符串头部池（固定大小）
    header_pool: SlabAllocator(PooledString),
    /// 字符串数据池（多大小）
    data_pool: MultiPool,
    /// 后备分配器（大字符串）
    backing: std.mem.Allocator,
    /// 统计
    stats: Stats,

    pub const Stats = struct {
        pooled_allocs: usize = 0,
        backing_allocs: usize = 0,
        reused: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .header_pool = SlabAllocator(PooledString).init(allocator),
            .data_pool = MultiPool.init(allocator),
            .backing = allocator,
            .stats = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.header_pool.deinit();
        self.data_pool.deinit();
    }

    /// 创建池化字符串
    pub fn create(self: *Self, str: []const u8) !*PooledString {
        const header = try self.header_pool.create();
        errdefer self.header_pool.destroy(header);

        // 尝试从池分配数据
        if (str.len <= 1024) {
            const data = try self.data_pool.alloc(str.len);
            @memcpy(data, str);
            header.* = .{
                .data = data,
                .length = str.len,
                .encoding = .utf8,
                .ref_count = 1,
                .pool_managed = true,
            };
            self.stats.pooled_allocs += 1;
        } else {
            // 大字符串使用后备分配器
            const data = try self.backing.dupe(u8, str);
            header.* = .{
                .data = data,
                .length = str.len,
                .encoding = .utf8,
                .ref_count = 1,
                .pool_managed = false,
            };
            self.stats.backing_allocs += 1;
        }

        return header;
    }

    /// 释放池化字符串
    pub fn destroy(self: *Self, str: *PooledString) void {
        if (str.pool_managed) {
            self.data_pool.free(str.data);
            self.stats.reused += 1;
        } else {
            self.backing.free(str.data);
        }
        self.header_pool.destroy(str);
    }

    pub fn getStats(self: *const Self) Stats {
        return self.stats;
    }
};

// ============================================================================
// PHPArray 专用池 - 优化数组对象分配
// ============================================================================

/// PHPArray 池化结构
pub const PooledArray = struct {
    /// 元素存储（使用紧凑表示）
    elements: ?*anyopaque, // 指向实际的 ArrayHashMap
    next_index: i64,
    capacity: usize,
    ref_count: usize,
    pool_managed: bool,
};

pub const PHPArrayPool = struct {
    const Self = @This();

    /// 数组头部池
    header_pool: SlabAllocator(PooledArray),
    /// 后备分配器
    backing: std.mem.Allocator,
    /// 统计
    stats: Stats,

    pub const Stats = struct {
        pooled_allocs: usize = 0,
        reused: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .header_pool = SlabAllocator(PooledArray).init(allocator),
            .backing = allocator,
            .stats = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.header_pool.deinit();
    }

    /// 创建池化数组
    pub fn create(self: *Self) !*PooledArray {
        const header = try self.header_pool.create();
        header.* = .{
            .elements = null,
            .next_index = 0,
            .capacity = 0,
            .ref_count = 1,
            .pool_managed = true,
        };
        self.stats.pooled_allocs += 1;
        return header;
    }

    /// 释放池化数组
    pub fn destroy(self: *Self, arr: *PooledArray) void {
        self.header_pool.destroy(arr);
        self.stats.reused += 1;
    }

    pub fn getStats(self: *const Self) Stats {
        return self.stats;
    }
};

// ============================================================================
// CallFrame 专用池 - 优化调用帧分配
// ============================================================================

/// 内联局部变量条目
pub const InlineLocal = struct {
    name: []u8, // 拥有字符串的所有权
    value: types.Value,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, value: types.Value) !InlineLocal {
        const owned_name = try allocator.dupe(u8, name);
        return .{
            .name = owned_name,
            .value = value,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InlineLocal) void {
        self.allocator.free(self.name);
    }
};

/// 堆存储的局部变量映射
/// @ownership TRANSFER (allocator 负责释放)
/// @memory-layout 使用 StringHashMap 实现动态扩展
pub const HeapLocals = struct {
    map: std.StringHashMap(types.Value),

    pub fn init(allocator: std.mem.Allocator) HeapLocals {
        return .{
            .map = std.StringHashMap(types.Value).init(allocator),
        };
    }

    pub fn deinit(self: *HeapLocals, allocator: std.mem.Allocator) void {
        // 释放所有值的引用和键字符串
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(allocator);
            // 释放键字符串（我们拥有所有权）
            allocator.free(entry.key_ptr.*);
        }
        self.map.deinit();
    }

    /// 设置变量
    /// @pre name 和 value 必须有效
    /// @post 变量被存储，旧值被释放
    pub fn set(self: *HeapLocals, allocator: std.mem.Allocator, name: []const u8, value: types.Value) !void {
        // StringHashMap 需要拥有键的所有权
        // 先检查是否已存在
        if (self.map.contains(name)) {
            // 键已存在，获取并更新值
            const old_value_ptr = self.map.getPtr(name).?;
            old_value_ptr.release(allocator);
            old_value_ptr.* = value;
            _ = value.retain();
        } else {
            // 新键，需要复制键字符串
            const owned_key = try allocator.dupe(u8, name);
            errdefer allocator.free(owned_key);
            try self.map.put(owned_key, value);
            _ = value.retain();
        }
    }

    /// 获取变量
    /// @pre name 必须有效
    /// @post 返回变量值或 null
    pub fn get(self: *const HeapLocals, name: []const u8) ?types.Value {
        return self.map.get(name);
    }

    /// 清空所有变量
    /// @post 所有变量被释放，映射被清空
    pub fn clear(self: *HeapLocals, allocator: std.mem.Allocator) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(allocator);
            // 释放键字符串
            allocator.free(entry.key_ptr.*);
        }
        self.map.clearRetainingCapacity();
    }

    /// 获取变量数量
    pub fn count(self: *const HeapLocals) usize {
        return self.map.count();
    }
};

/// 池化调用帧（轻量级版本）
/// Task 25: 实现完整的堆存储支持
/// @ownership NON-OWNING (allocator)
/// @memory-layout 内联存储 + 堆存储混合模式
/// @concurrency-model ISOLATED (单线程)
pub const PooledCallFrame = struct {
    // Task 4.2.4: 内联存储小函数的局部变量（避免堆分配）
    // 对于 ≤8 个局部变量的函数，直接存储在帧中
    pub const INLINE_LOCALS_CAPACITY = 8;

    function_name: []const u8,
    file: []const u8,
    line: u32,
    inline_locals: [INLINE_LOCALS_CAPACITY]InlineLocal,
    inline_locals_count: u8,
    heap_locals: ?*HeapLocals, // 堆存储（动态分配）
    imported_globals_ptr: ?*anyopaque,
    imported_count: u16,
    pool_managed: bool,

    /// 设置局部变量（自动选择内联或堆存储）
    /// @pre name 和 value 必须有效
    /// @post 变量被存储，无容量限制
    /// @memory-safety 自动从内联切换到堆存储
    pub fn setLocal(self: *PooledCallFrame, allocator: std.mem.Allocator, name: []const u8, value: types.Value) !void {
        // 先尝试在内联存储中查找（只在已初始化的范围内）
        var i: usize = 0;
        while (i < self.inline_locals_count) : (i += 1) {
            if (std.mem.eql(u8, self.inline_locals[i].name, name)) {
                // 释放旧值
                self.inline_locals[i].value.release(allocator);
                // 设置新值
                self.inline_locals[i].value = value;
                _ = value.retain();
                return;
            }
        }

        // 如果内联存储未满，添加到内联存储
        if (self.inline_locals_count < INLINE_LOCALS_CAPACITY) {
            self.inline_locals[self.inline_locals_count] = try InlineLocal.init(allocator, name, value);
            _ = value.retain();
            self.inline_locals_count += 1;
            return;
        }

        // Task 25: 内联存储已满，切换到堆存储（无容量限制）
        // 如果堆存储尚未初始化，创建它
        if (self.heap_locals == null) {
            const heap = try allocator.create(HeapLocals);
            errdefer allocator.destroy(heap);
            heap.* = HeapLocals.init(allocator);
            self.heap_locals = heap;
        }

        // 在堆存储中设置变量
        try self.heap_locals.?.set(allocator, name, value);
    }

    /// 获取局部变量
    /// @pre name 必须有效
    /// @post 返回变量值或 null
    pub fn getLocal(self: *const PooledCallFrame, name: []const u8) ?types.Value {
        // 先在内联存储中查找（只在已初始化的范围内）
        var i: usize = 0;
        while (i < self.inline_locals_count) : (i += 1) {
            if (std.mem.eql(u8, self.inline_locals[i].name, name)) {
                return self.inline_locals[i].value;
            }
        }

        // 如果有堆存储，在堆中查找
        if (self.heap_locals) |heap| {
            return heap.get(name);
        }

        return null;
    }

    /// 清理所有局部变量
    /// @post 所有变量被释放，内存被回收
    /// @memory-safety 正确释放内联和堆存储
    pub fn clearLocals(self: *PooledCallFrame, allocator: std.mem.Allocator) void {
        // 释放内联存储的值（只在已初始化的范围内）
        var i: usize = 0;
        while (i < self.inline_locals_count) : (i += 1) {
            self.inline_locals[i].value.release(allocator);
            self.inline_locals[i].deinit(); // 释放名称字符串
        }
        self.inline_locals_count = 0;

        // 释放堆存储（如果有）
        if (self.heap_locals) |heap| {
            heap.deinit(allocator);
            allocator.destroy(heap);
            self.heap_locals = null;
        }
    }

    /// 获取局部变量总数
    /// @post 返回内联 + 堆存储的变量总数
    pub fn getLocalCount(self: *const PooledCallFrame) usize {
        var count: usize = self.inline_locals_count;
        if (self.heap_locals) |heap| {
            count += heap.count();
        }
        return count;
    }

    /// 检查是否使用了堆存储
    /// @post 返回是否已切换到堆存储
    pub fn isUsingHeapStorage(self: *const PooledCallFrame) bool {
        return self.heap_locals != null;
    }
};

pub const CallFramePool = struct {
    const Self = @This();
    const POOL_SIZE = 256; // 预分配帧数量

    /// 帧池
    frame_pool: SlabAllocator(PooledCallFrame),
    /// 后备分配器
    backing: std.mem.Allocator,
    /// 统计
    stats: Stats,

    pub const Stats = struct {
        pooled_allocs: usize = 0,
        reused: usize = 0,
        peak_depth: usize = 0,
        current_depth: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .frame_pool = SlabAllocator(PooledCallFrame).init(allocator),
            .backing = allocator,
            .stats = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.frame_pool.deinit();
    }

    /// 获取调用帧
    /// @pre function_name, file 必须有效
    /// @post 返回初始化的调用帧
    pub fn acquire(self: *Self, function_name: []const u8, file: []const u8, line: u32) !*PooledCallFrame {
        const frame = try self.frame_pool.create();
        frame.* = .{
            .function_name = function_name,
            .file = file,
            .line = line,
            .inline_locals = undefined, // Will be initialized as needed
            .inline_locals_count = 0,
            .heap_locals = null, // 堆存储初始为空
            .imported_globals_ptr = null,
            .imported_count = 0,
            .pool_managed = true,
        };
        self.stats.pooled_allocs += 1;
        self.stats.current_depth += 1;
        if (self.stats.current_depth > self.stats.peak_depth) {
            self.stats.peak_depth = self.stats.current_depth;
        }
        return frame;
    }

    /// 释放调用帧
    pub fn release(self: *Self, frame: *PooledCallFrame, allocator: std.mem.Allocator) void {
        // 清理局部变量
        frame.clearLocals(allocator);
        // 归还到池中
        self.frame_pool.destroy(frame);
        self.stats.reused += 1;
        if (self.stats.current_depth > 0) {
            self.stats.current_depth -= 1;
        }
    }

    /// 重置帧（保留内存，清除数据）
    pub fn reset(frame: *PooledCallFrame, allocator: std.mem.Allocator) void {
        frame.clearLocals(allocator);
        frame.imported_globals_ptr = null;
        frame.imported_count = 0;
    }

    pub fn getStats(self: *const Self) Stats {
        return self.stats;
    }
};

// ============================================================================
// 扩展的池管理器 - 包含所有专用池
// ============================================================================

pub const ExtendedPoolManager = struct {
    /// 基础池管理器
    base: PoolManager,
    /// PHPString 专用池
    string_pool: PHPStringPool,
    /// PHPArray 专用池
    array_pool: PHPArrayPool,
    /// CallFrame 专用池
    frame_pool: CallFramePool,

    pub fn init(backing: std.mem.Allocator) ExtendedPoolManager {
        return .{
            .base = PoolManager.init(backing),
            .string_pool = PHPStringPool.init(backing),
            .array_pool = PHPArrayPool.init(backing),
            .frame_pool = CallFramePool.init(backing),
        };
    }

    pub fn deinit(self: *ExtendedPoolManager) void {
        self.frame_pool.deinit();
        self.array_pool.deinit();
        self.string_pool.deinit();
        self.base.deinit();
    }

    pub fn resetTemp(self: *ExtendedPoolManager) void {
        self.base.resetTemp();
    }

    /// 获取综合统计
    pub fn getStats(self: *const ExtendedPoolManager) struct {
        string: PHPStringPool.Stats,
        array: PHPArrayPool.Stats,
        frame: CallFramePool.Stats,
    } {
        return .{
            .string = self.string_pool.getStats(),
            .array = self.array_pool.getStats(),
            .frame = self.frame_pool.getStats(),
        };
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SlabAllocator" {
    const TestT = struct { a: u64, b: u64 };
    var pool = SlabAllocator(TestT).init(std.testing.allocator);
    defer pool.deinit();

    const p1 = try pool.create();
    p1.a = 42;
    const p2 = try pool.create();
    p2.a = 100;

    pool.destroy(p1);
    const p3 = try pool.create();
    try std.testing.expect(p3 == p1);
}

test "BumpAllocator" {
    var bump = BumpAllocator.init(std.testing.allocator);
    defer bump.deinit();

    const a1 = try bump.alloc(u64, 10);
    a1[0] = 42;
    const a2 = try bump.alloc(u32, 5);
    a2[0] = 100;

    bump.reset();
    const a3 = try bump.alloc(u64, 10);
    _ = a3;
}

test "MultiPool" {
    var pool = MultiPool.init(std.testing.allocator);
    defer pool.deinit();

    const m1 = try pool.alloc(32);
    m1[0] = 42;
    pool.free(m1);

    const m2 = try pool.alloc(32);
    try std.testing.expect(m2.ptr == m1.ptr);
}

test "IntCache" {
    const cache = IntCache(i64, -128, 127){};
    try std.testing.expect(cache.get(0).?.* == 0);
    try std.testing.expect(cache.get(127).?.* == 127);
    try std.testing.expect(cache.get(128) == null);
}

test "PHPStringPool" {
    var pool = PHPStringPool.init(std.testing.allocator);
    defer pool.deinit();

    // 创建短字符串（池化）
    const s1 = try pool.create("hello");
    try std.testing.expectEqualStrings("hello", s1.data);
    try std.testing.expect(s1.pool_managed);

    // 创建另一个字符串
    const s2 = try pool.create("world");
    try std.testing.expectEqualStrings("world", s2.data);

    // 释放并重用
    pool.destroy(s1);
    const s3 = try pool.create("test!");
    try std.testing.expectEqualStrings("test!", s3.data);

    pool.destroy(s2);
    pool.destroy(s3);

    // 检查统计
    const stats = pool.getStats();
    try std.testing.expect(stats.pooled_allocs == 3);
    try std.testing.expect(stats.reused == 3);
}

test "PHPArrayPool" {
    var pool = PHPArrayPool.init(std.testing.allocator);
    defer pool.deinit();

    const arr1 = try pool.create();
    try std.testing.expect(arr1.pool_managed);
    try std.testing.expect(arr1.next_index == 0);

    const arr2 = try pool.create();
    pool.destroy(arr1);

    const arr3 = try pool.create();
    try std.testing.expect(arr3 == arr1); // 重用

    pool.destroy(arr2);
    pool.destroy(arr3);

    const stats = pool.getStats();
    try std.testing.expect(stats.pooled_allocs == 3);
}

test "CallFramePool" {
    var pool = CallFramePool.init(std.testing.allocator);
    defer pool.deinit();

    const f1 = try pool.acquire("main", "test.php", 1);
    try std.testing.expectEqualStrings("main", f1.function_name);
    try std.testing.expect(pool.stats.current_depth == 1);

    // Task 4.2.4: 测试内联局部变量存储
    try std.testing.expect(f1.inline_locals_count == 0);
    try std.testing.expect(!f1.isUsingHeapStorage());

    // 添加局部变量（应该使用内联存储）
    try f1.setLocal(std.testing.allocator, "x", types.Value.initInt(42));
    try std.testing.expect(f1.inline_locals_count == 1);
    try std.testing.expect(!f1.isUsingHeapStorage());

    // 获取局部变量
    const x_val = f1.getLocal("x");
    try std.testing.expect(x_val != null);
    try std.testing.expect(x_val.?.asInt() == 42);

    // Task 25: 测试堆存储切换（添加超过 8 个变量）
    try f1.setLocal(std.testing.allocator, "a", types.Value.initInt(1));
    try f1.setLocal(std.testing.allocator, "b", types.Value.initInt(2));
    try f1.setLocal(std.testing.allocator, "c", types.Value.initInt(3));
    try f1.setLocal(std.testing.allocator, "d", types.Value.initInt(4));
    try f1.setLocal(std.testing.allocator, "e", types.Value.initInt(5));
    try f1.setLocal(std.testing.allocator, "f", types.Value.initInt(6));
    try f1.setLocal(std.testing.allocator, "g", types.Value.initInt(7));

    // 此时应该有 8 个内联变量
    try std.testing.expect(f1.inline_locals_count == 8);
    try std.testing.expect(!f1.isUsingHeapStorage());

    // 添加第 9 个变量，应该触发堆存储
    try f1.setLocal(std.testing.allocator, "h", types.Value.initInt(8));
    try std.testing.expect(f1.isUsingHeapStorage());
    try std.testing.expect(f1.getLocalCount() == 9);

    // 验证所有变量都能正确获取
    try std.testing.expect(f1.getLocal("x").?.asInt() == 42);
    try std.testing.expect(f1.getLocal("a").?.asInt() == 1);
    try std.testing.expect(f1.getLocal("h").?.asInt() == 8);

    // 添加更多变量到堆存储（无容量限制）
    try f1.setLocal(std.testing.allocator, "i", types.Value.initInt(9));
    try f1.setLocal(std.testing.allocator, "j", types.Value.initInt(10));
    try std.testing.expect(f1.getLocalCount() == 11);

    // 更新堆存储中的变量
    try f1.setLocal(std.testing.allocator, "h", types.Value.initInt(88));
    try std.testing.expect(f1.getLocal("h").?.asInt() == 88);

    const f2 = try pool.acquire("foo", "test.php", 10);
    try std.testing.expect(pool.stats.current_depth == 2);
    try std.testing.expect(pool.stats.peak_depth == 2);

    pool.release(f2, std.testing.allocator);
    try std.testing.expect(pool.stats.current_depth == 1);

    pool.release(f1, std.testing.allocator);
    try std.testing.expect(pool.stats.current_depth == 0);

    // 重用测试
    const f3 = try pool.acquire("bar", "test.php", 20);
    try std.testing.expect(f3 == f2 or f3 == f1); // 应该重用之前的帧
    try std.testing.expect(!f3.isUsingHeapStorage()); // 重用的帧应该已清理

    pool.release(f3, std.testing.allocator);
}

test "ExtendedPoolManager" {
    var manager = ExtendedPoolManager.init(std.testing.allocator);
    defer manager.deinit();

    // 测试字符串池
    const s = try manager.string_pool.create("test");
    manager.string_pool.destroy(s);

    // 测试数组池
    const a = try manager.array_pool.create();
    manager.array_pool.destroy(a);

    // 测试帧池
    const f = try manager.frame_pool.acquire("test", "file.php", 1);
    manager.frame_pool.release(f);

    // 测试临时分配重置
    _ = try manager.base.bump.alloc(u8, 100);
    manager.resetTemp();

    // 获取统计
    const stats = manager.getStats();
    try std.testing.expect(stats.string.pooled_allocs == 1);
    try std.testing.expect(stats.array.pooled_allocs == 1);
    try std.testing.expect(stats.frame.pooled_allocs == 1);
}
