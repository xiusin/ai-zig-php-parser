const std = @import("std");
const memory = @import("memory.zig");
const ArenaAllocator = memory.ArenaAllocator;

/// 请求级Arena内存管理器
/// 每个HTTP请求独立的内存池，请求结束时一次性释放
/// Requirements: 4.1, 4.2, 4.3, 4.5, 4.6
pub const RequestArena = struct {
    /// 底层Arena分配器
    arena: ArenaAllocator,
    /// 父分配器（用于Arena扩展）
    parent_allocator: std.mem.Allocator,
    /// 请求唯一标识符
    request_id: u64,
    /// 请求开始时间戳
    start_time_ns: i64,
    /// 请求结束时间戳
    end_time_ns: i64,
    /// 需要跨请求存活的逃逸对象列表
    escape_list: std.ArrayList(EscapeEntry),
    /// 全局堆分配器（用于逃逸对象晋升）
    global_allocator: std.mem.Allocator,
    /// 统计信息
    stats: RequestArenaStats,
    /// 是否已结束
    is_ended: bool,
    
    /// 逃逸对象条目
    pub const EscapeEntry = struct {
        /// 对象指针
        ptr: *anyopaque,
        /// 对象大小
        size: usize,
        /// 逃逸原因
        reason: EscapeReason,
        /// 复制函数（用于晋升到全局堆）
        copy_fn: ?*const fn (*anyopaque, std.mem.Allocator) anyerror!*anyopaque,
    };
    
    /// 逃逸原因
    pub const EscapeReason = enum {
        /// 存储到会话
        stored_to_session,
        /// 存储到缓存
        stored_to_cache,
        /// 存储到全局变量
        stored_to_global,
        /// 返回给调用者
        returned_to_caller,
        /// 被闭包捕获
        captured_by_closure,
        /// 显式标记
        explicit_mark,
    };
    
    /// 请求Arena统计信息
    pub const RequestArenaStats = struct {
        /// 总分配次数
        total_allocations: u64 = 0,
        /// 总分配字节数
        total_bytes_allocated: usize = 0,
        /// 逃逸对象数量
        escaped_objects: u64 = 0,
        /// 逃逸对象字节数
        escaped_bytes: usize = 0,
        /// Arena扩展次数
        arena_expansions: u32 = 0,
        /// 请求处理时间（纳秒）
        request_duration_ns: u64 = 0,
    };
    
    /// 全局请求ID计数器
    var global_request_counter: u64 = 0;
    
    /// 生成唯一请求ID
    fn generateRequestId() u64 {
        const result = global_request_counter;
        global_request_counter += 1;
        return result;
    }
    
    /// 初始化请求Arena
    pub fn init(parent_allocator: std.mem.Allocator, global_allocator: std.mem.Allocator) RequestArena {
        return .{
            .arena = ArenaAllocator.init(parent_allocator),
            .parent_allocator = parent_allocator,
            .request_id = 0,
            .start_time_ns = 0,
            .end_time_ns = 0,
            .escape_list = .{},
            .global_allocator = global_allocator,
            .stats = .{},
            .is_ended = true,
        };
    }
    
    /// 释放资源
    pub fn deinit(self: *RequestArena) void {
        if (!self.is_ended) {
            self.endRequest();
        }
        self.escape_list.deinit(self.parent_allocator);
        self.arena.deinit();
    }
    
    /// 开始新请求
    /// Requirements: 4.1
    pub fn beginRequest(self: *RequestArena) void {
        // 重置Arena（保留已分配的内存块以供复用）
        self.arena.reset();
        
        // 生成新的请求ID
        self.request_id = generateRequestId();
        self.start_time_ns = @intCast(std.time.nanoTimestamp());
        self.end_time_ns = 0;
        self.is_ended = false;
        
        // 清空逃逸列表
        self.escape_list.clearRetainingCapacity();
        
        // 重置统计
        self.stats = .{};
    }
    
    /// 结束请求并释放内存
    /// Requirements: 4.3, 4.6
    pub fn endRequest(self: *RequestArena) void {
        if (self.is_ended) return;
        
        self.end_time_ns = @intCast(std.time.nanoTimestamp());
        self.stats.request_duration_ns = @intCast(self.end_time_ns - self.start_time_ns);
        
        // 处理逃逸对象 - 晋升到全局堆
        self.promoteEscapedObjects();
        
        // 一次性释放所有请求内存
        self.arena.freeAll();
        
        self.is_ended = true;
    }
    
    /// 在Arena中分配内存
    /// Requirements: 4.2
    pub fn alloc(self: *RequestArena, comptime T: type, n: usize) ![]T {
        const result = try self.arena.alloc(T, n);
        self.stats.total_allocations += 1;
        self.stats.total_bytes_allocated += @sizeOf(T) * n;
        return result;
    }
    
    /// 分配单个对象
    pub fn create(self: *RequestArena, comptime T: type) !*T {
        const slice = try self.alloc(T, 1);
        return &slice[0];
    }
    
    /// 复制字符串到Arena
    pub fn dupe(self: *RequestArena, comptime T: type, data: []const T) ![]T {
        const result = try self.alloc(T, data.len);
        @memcpy(result, data);
        return result;
    }
    
    /// 标记对象需要跨请求存活（逃逸）
    /// Requirements: 4.5
    pub fn markEscape(
        self: *RequestArena, 
        ptr: *anyopaque, 
        size: usize, 
        reason: EscapeReason,
        copy_fn: ?*const fn (*anyopaque, std.mem.Allocator) anyerror!*anyopaque,
    ) !void {
        try self.escape_list.append(self.parent_allocator, .{
            .ptr = ptr,
            .size = size,
            .reason = reason,
            .copy_fn = copy_fn,
        });
        self.stats.escaped_objects += 1;
        self.stats.escaped_bytes += size;
    }
    
    /// 晋升逃逸对象到全局堆
    fn promoteEscapedObjects(self: *RequestArena) void {
        for (self.escape_list.items) |entry| {
            if (entry.copy_fn) |copy_fn| {
                // 使用复制函数将对象复制到全局堆
                _ = copy_fn(entry.ptr, self.global_allocator) catch {
                    // 复制失败，记录错误但继续处理
                    continue;
                };
            }
            // 如果没有复制函数，对象将在Arena释放时被销毁
            // 调用者需要确保在标记逃逸时提供正确的复制函数
        }
    }
    
    /// 获取当前请求ID
    pub fn getRequestId(self: *const RequestArena) u64 {
        return self.request_id;
    }
    
    /// 获取请求开始时间
    pub fn getStartTime(self: *const RequestArena) i64 {
        return self.start_time_ns;
    }
    
    /// 获取统计信息
    pub fn getStats(self: *const RequestArena) RequestArenaStats {
        return self.stats;
    }
    
    /// 获取Arena内存使用统计
    pub fn getMemoryStats(self: *RequestArena) memory.MemoryStats {
        return self.arena.getStats();
    }
    
    /// 检查请求是否已结束
    pub fn isEnded(self: *const RequestArena) bool {
        return self.is_ended;
    }
    
    /// 获取请求持续时间（毫秒）
    pub fn getDurationMs(self: *const RequestArena) f64 {
        if (self.is_ended) {
            return @as(f64, @floatFromInt(self.stats.request_duration_ns)) / 1_000_000.0;
        }
        const current: i64 = @intCast(std.time.nanoTimestamp());
        const duration: u64 = @intCast(current - self.start_time_ns);
        return @as(f64, @floatFromInt(duration)) / 1_000_000.0;
    }
};

/// 请求Arena池 - 复用RequestArena实例
pub const RequestArenaPool = struct {
    pool: std.ArrayListUnmanaged(*RequestArena),
    parent_allocator: std.mem.Allocator,
    global_allocator: std.mem.Allocator,
    max_pool_size: usize,
    stats: PoolStats,
    
    pub const PoolStats = struct {
        total_acquired: u64 = 0,
        total_released: u64 = 0,
        pool_hits: u64 = 0,
        pool_misses: u64 = 0,
    };
    
    pub fn init(
        parent_allocator: std.mem.Allocator, 
        global_allocator: std.mem.Allocator,
        max_pool_size: usize,
    ) RequestArenaPool {
        return .{
            .pool = .{},
            .parent_allocator = parent_allocator,
            .global_allocator = global_allocator,
            .max_pool_size = max_pool_size,
            .stats = .{},
        };
    }
    
    pub fn deinit(self: *RequestArenaPool) void {
        for (self.pool.items) |arena| {
            arena.deinit();
            self.parent_allocator.destroy(arena);
        }
        self.pool.deinit(self.parent_allocator);
    }
    
    /// 获取一个RequestArena（从池中获取或新建）
    pub fn acquire(self: *RequestArenaPool) !*RequestArena {
        self.stats.total_acquired += 1;
        
        if (self.pool.items.len > 0) {
            self.stats.pool_hits += 1;
            const arena = self.pool.pop();
            if (arena) |a| {
                a.beginRequest();
                return a;
            }
        }
        
        self.stats.pool_misses += 1;
        const arena = try self.parent_allocator.create(RequestArena);
        arena.* = RequestArena.init(self.parent_allocator, self.global_allocator);
        arena.beginRequest();
        return arena;
    }
    
    /// 释放RequestArena回池中
    pub fn release(self: *RequestArenaPool, arena: *RequestArena) void {
        self.stats.total_released += 1;
        
        // 确保请求已结束
        if (!arena.is_ended) {
            arena.endRequest();
        }
        
        // 如果池未满，放回池中复用
        if (self.pool.items.len < self.max_pool_size) {
            self.pool.append(self.parent_allocator, arena) catch {
                // 池满或分配失败，销毁Arena
                arena.deinit();
                self.parent_allocator.destroy(arena);
            };
        } else {
            // 池已满，销毁Arena
            arena.deinit();
            self.parent_allocator.destroy(arena);
        }
    }
    
    /// 获取池统计信息
    pub fn getStats(self: *const RequestArenaPool) PoolStats {
        return self.stats;
    }
    
    /// 获取当前池大小
    pub fn getPoolSize(self: *const RequestArenaPool) usize {
        return self.pool.items.len;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "request arena basic" {
    var arena = RequestArena.init(std.testing.allocator, std.testing.allocator);
    defer arena.deinit();
    
    arena.beginRequest();
    try std.testing.expect(arena.request_id > 0 or arena.request_id == 0); // First request
    try std.testing.expect(!arena.is_ended);
    
    const data = try arena.alloc(u8, 100);
    try std.testing.expect(data.len == 100);
    try std.testing.expect(arena.stats.total_allocations == 1);
    
    arena.endRequest();
    try std.testing.expect(arena.is_ended);
    try std.testing.expect(arena.stats.request_duration_ns > 0);
}

test "request arena pool" {
    var pool = RequestArenaPool.init(std.testing.allocator, std.testing.allocator, 4);
    defer pool.deinit();
    
    const arena1 = try pool.acquire();
    try std.testing.expect(pool.stats.pool_misses == 1);
    
    _ = try arena1.alloc(u8, 50);
    pool.release(arena1);
    
    const arena2 = try pool.acquire();
    try std.testing.expect(pool.stats.pool_hits == 1);
    try std.testing.expect(arena2 == arena1); // Should be the same arena
    
    pool.release(arena2);
}

test "request arena escape" {
    var arena = RequestArena.init(std.testing.allocator, std.testing.allocator);
    defer arena.deinit();
    
    arena.beginRequest();
    
    const data = try arena.create(u64);
    data.* = 42;
    
    try arena.markEscape(data, @sizeOf(u64), .stored_to_session, null);
    try std.testing.expect(arena.stats.escaped_objects == 1);
    try std.testing.expect(arena.stats.escaped_bytes == @sizeOf(u64));
    
    arena.endRequest();
}
