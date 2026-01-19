// 对象池化系统
// 实现通用的对象池管理器，支持对象重用和自适应池大小
// 需求：4.4 - 对象池化技术，减少分配开销 50%

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

/// 对象池配置
pub const PoolConfig = struct {
    /// 初始池大小
    initial_capacity: usize = 32,
    
    /// 最大池大小
    max_capacity: usize = 1024,
    
    /// 最小池大小
    min_capacity: usize = 8,
    
    /// 自适应调整阈值（使用率）
    high_watermark: f32 = 0.8,
    low_watermark: f32 = 0.2,
    
    /// 调整步长
    resize_step: usize = 16,
    
    /// 统计窗口大小（用于计算平均使用率）
    stats_window_size: usize = 100,
};

/// 对象池统计信息
pub const PoolStats = struct {
    /// 总分配次数
    total_allocations: usize = 0,
    
    /// 池命中次数
    pool_hits: usize = 0,
    
    /// 池未命中次数
    pool_misses: usize = 0,
    
    /// 当前池大小
    current_capacity: usize = 0,
    
    /// 当前使用数量
    current_usage: usize = 0,
    
    /// 峰值使用数量
    peak_usage: usize = 0,
    
    /// 调整次数
    resize_count: usize = 0,
    
    /// 计算命中率
    pub fn hitRate(self: *const PoolStats) f32 {
        if (self.total_allocations == 0) return 0.0;
        return @as(f32, @floatFromInt(self.pool_hits)) / @as(f32, @floatFromInt(self.total_allocations));
    }
    
    /// 计算使用率
    pub fn usageRate(self: *const PoolStats) f32 {
        if (self.current_capacity == 0) return 0.0;
        return @as(f32, @floatFromInt(self.current_usage)) / @as(f32, @floatFromInt(self.current_capacity));
    }
};

/// 通用对象池
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED (单线程)
/// @memory-layout 缓存友好的连续存储
pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();
        
        /// 池中的对象槽位
        const Slot = struct {
            object: T,
            in_use: bool,
        };
        
        /// 对象句柄（用于安全地引用池中的对象）
        pub const Handle = struct {
            index: usize,
            pool: *Self,
            
            /// 获取对象指针
            pub fn get(self: Handle) *T {
                return &self.pool.slots.items[self.index].object;
            }
            
            /// 释放对象
            pub fn release(self: Handle) void {
                self.pool.releaseByIndex(self.index);
            }
        };
        
        allocator: Allocator,
        slots: std.ArrayList(Slot),
        config: PoolConfig,
        stats: PoolStats,
        
        /// 使用率历史（用于自适应调整）
        usage_history: std.ArrayList(f32),
        
        /// 初始化对象池
        /// @pre allocator 必须有效
        /// @post 返回初始化的对象池
        pub fn init(allocator: Allocator, config: PoolConfig) !Self {
            var slots = try std.ArrayList(Slot).initCapacity(allocator, config.initial_capacity);
            
            // 预分配对象
            var i: usize = 0;
            while (i < config.initial_capacity) : (i += 1) {
                try slots.append(allocator, .{
                    .object = undefined,
                    .in_use = false,
                });
            }
            
            return Self{
                .allocator = allocator,
                .slots = slots,
                .config = config,
                .stats = .{
                    .current_capacity = config.initial_capacity,
                },
                .usage_history = try std.ArrayList(f32).initCapacity(allocator, config.stats_window_size),
            };
        }
        
        /// 释放对象池
        /// @pre self 必须已初始化
        /// @post 释放所有资源
        pub fn deinit(self: *Self) void {
            self.slots.deinit(self.allocator);
            self.usage_history.deinit(self.allocator);
        }
        
        /// 从池中获取对象
        /// @pre self 必须已初始化
        /// @post 返回对象句柄或错误
        pub fn acquire(self: *Self) !Handle {
            self.stats.total_allocations += 1;
            
            // 查找空闲槽位
            for (self.slots.items, 0..) |*slot, index| {
                if (!slot.in_use) {
                    slot.in_use = true;
                    self.stats.pool_hits += 1;
                    self.stats.current_usage += 1;
                    
                    if (self.stats.current_usage > self.stats.peak_usage) {
                        self.stats.peak_usage = self.stats.current_usage;
                    }
                    
                    // 记录使用率
                    try self.recordUsage();
                    
                    // 检查是否需要扩容
                    try self.maybeResize();
                    
                    return Handle{
                        .index = index,
                        .pool = self,
                    };
                }
            }
            
            // 池已满，尝试扩容
            self.stats.pool_misses += 1;
            
            if (self.slots.items.len < self.config.max_capacity) {
                try self.expand();
                return self.acquire();
            }
            
            return error.PoolExhausted;
        }
        
        /// 通过索引归还对象
        fn releaseByIndex(self: *Self, index: usize) void {
            std.debug.assert(index < self.slots.items.len);
            std.debug.assert(self.slots.items[index].in_use);
            
            self.slots.items[index].in_use = false;
            self.stats.current_usage -= 1;
        }
        
        /// 扩容池
        fn expand(self: *Self) !void {
            const new_capacity = @min(
                self.slots.items.len + self.config.resize_step,
                self.config.max_capacity
            );
            
            const old_capacity = self.slots.items.len;
            try self.slots.ensureTotalCapacity(self.allocator, new_capacity);
            
            var i: usize = old_capacity;
            while (i < new_capacity) : (i += 1) {
                try self.slots.append(self.allocator, .{
                    .object = undefined,
                    .in_use = false,
                });
            }
            
            self.stats.current_capacity = new_capacity;
            self.stats.resize_count += 1;
        }
        
        /// 缩容池
        fn shrink(self: *Self) !void {
            const new_capacity = @max(
                self.slots.items.len -| self.config.resize_step,
                self.config.min_capacity
            );
            
            if (new_capacity >= self.slots.items.len) return;
            
            // 只能移除未使用的槽位
            var remove_count: usize = 0;
            var i: usize = self.slots.items.len;
            while (i > new_capacity and remove_count < self.config.resize_step) {
                i -= 1;
                if (!self.slots.items[i].in_use) {
                    _ = self.slots.pop();
                    remove_count += 1;
                }
            }
            
            if (remove_count > 0) {
                self.stats.current_capacity = self.slots.items.len;
                self.stats.resize_count += 1;
            }
        }
        
        /// 记录使用率
        fn recordUsage(self: *Self) !void {
            const usage_rate = self.stats.usageRate();
            
            if (self.usage_history.items.len >= self.config.stats_window_size) {
                _ = self.usage_history.orderedRemove(0);
            }
            
            try self.usage_history.append(self.allocator, usage_rate);
        }
        
        /// 计算平均使用率
        fn averageUsage(self: *const Self) f32 {
            if (self.usage_history.items.len == 0) return 0.0;
            
            var sum: f32 = 0.0;
            for (self.usage_history.items) |rate| {
                sum += rate;
            }
            
            return sum / @as(f32, @floatFromInt(self.usage_history.items.len));
        }
        
        /// 自适应调整池大小
        fn maybeResize(self: *Self) !void {
            // 需要足够的历史数据
            if (self.usage_history.items.len < self.config.stats_window_size / 2) {
                return;
            }
            
            const avg_usage = self.averageUsage();
            
            // 高使用率 - 扩容
            if (avg_usage > self.config.high_watermark) {
                if (self.slots.items.len < self.config.max_capacity) {
                    try self.expand();
                }
            }
            // 低使用率 - 缩容
            else if (avg_usage < self.config.low_watermark) {
                if (self.slots.items.len > self.config.min_capacity) {
                    try self.shrink();
                }
            }
        }
        
        /// 获取统计信息
        pub fn getStats(self: *const Self) PoolStats {
            return self.stats;
        }
        
        /// 重置统计信息
        pub fn resetStats(self: *Self) void {
            self.stats = .{
                .current_capacity = self.stats.current_capacity,
                .current_usage = self.stats.current_usage,
            };
            self.usage_history.clearRetainingCapacity();
        }
    };
}

/// 对象池管理器
/// 管理多个不同类型的对象池
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED (单线程)
pub const PoolManager = struct {
    allocator: Allocator,
    
    /// 初始化池管理器
    pub fn init(allocator: Allocator) PoolManager {
        return .{
            .allocator = allocator,
        };
    }
    
    /// 释放池管理器
    pub fn deinit(self: *PoolManager) void {
        _ = self;
        // 池由各自的所有者管理
    }
};

// ============================================================================
// 单元测试
// ============================================================================

test "ObjectPool: basic allocation and release" {
    const TestObject = struct {
        value: i32,
    };
    
    var pool = try ObjectPool(TestObject).init(testing.allocator, .{
        .initial_capacity = 4,
    });
    defer pool.deinit();
    
    // 分配对象
    const handle1 = try pool.acquire();
    handle1.get().value = 42;
    
    const handle2 = try pool.acquire();
    handle2.get().value = 100;
    
    try testing.expectEqual(@as(usize, 2), pool.stats.current_usage);
    try testing.expectEqual(@as(usize, 2), pool.stats.pool_hits);
    
    // 归还对象
    handle1.release();
    try testing.expectEqual(@as(usize, 1), pool.stats.current_usage);
    
    // 重新分配应该重用
    const handle3 = try pool.acquire();
    try testing.expectEqual(@as(usize, 2), pool.stats.current_usage);
    try testing.expectEqual(@as(usize, 3), pool.stats.pool_hits);
    
    handle2.release();
    handle3.release();
}

test "ObjectPool: pool expansion" {
    const TestObject = struct {
        id: usize,
    };
    
    var pool = try ObjectPool(TestObject).init(testing.allocator, .{
        .initial_capacity = 2,
        .max_capacity = 10,
        .resize_step = 2,
    });
    defer pool.deinit();
    
    // 分配超过初始容量
    const Handle = ObjectPool(TestObject).Handle;
    var handles: [5]Handle = undefined;
    for (&handles, 0..) |*handle, i| {
        handle.* = try pool.acquire();
        handle.get().id = i;
    }
    
    try testing.expect(pool.stats.current_capacity >= 5);
    try testing.expectEqual(@as(usize, 5), pool.stats.current_usage);
    
    // 归还所有对象
    for (handles) |handle| {
        handle.release();
    }
    
    try testing.expectEqual(@as(usize, 0), pool.stats.current_usage);
}

test "ObjectPool: statistics" {
    const TestObject = struct {
        data: [64]u8,
    };
    
    var pool = try ObjectPool(TestObject).init(testing.allocator, .{
        .initial_capacity = 4,
    });
    defer pool.deinit();
    
    // 执行一些操作
    const handle1 = try pool.acquire();
    const handle2 = try pool.acquire();
    handle1.release();
    const handle3 = try pool.acquire();
    
    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 3), stats.total_allocations);
    try testing.expectEqual(@as(usize, 3), stats.pool_hits);
    try testing.expectEqual(@as(usize, 2), stats.current_usage);
    try testing.expectEqual(@as(usize, 2), stats.peak_usage);
    
    // 命中率应该是 100%
    try testing.expectEqual(@as(f32, 1.0), stats.hitRate());
    
    handle2.release();
    handle3.release();
}

test "ObjectPool: adaptive resizing" {
    const TestObject = struct {
        value: u64,
    };
    
    var pool = try ObjectPool(TestObject).init(testing.allocator, .{
        .initial_capacity = 8,
        .max_capacity = 64,
        .min_capacity = 4,
        .high_watermark = 0.8,
        .low_watermark = 0.2,
        .resize_step = 4,
        .stats_window_size = 10,
    });
    defer pool.deinit();
    
    const Handle = ObjectPool(TestObject).Handle;
    
    // 模拟高使用率场景
    var handles: [20]Handle = undefined;
    for (&handles) |*handle| {
        handle.* = try pool.acquire();
    }
    
    // 池应该已经扩容
    try testing.expect(pool.stats.current_capacity > 8);
    
    // 归还大部分对象，模拟低使用率
    for (handles[0..15]) |handle| {
        handle.release();
    }
    
    // 继续分配和释放以触发自适应调整
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const handle = try pool.acquire();
        handle.release();
    }
    
    // 清理剩余对象
    for (handles[15..]) |handle| {
        handle.release();
    }
}
