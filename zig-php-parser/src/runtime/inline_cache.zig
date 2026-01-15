//! Inline Cache System - 内联缓存系统
//! 
//! 内联缓存用于优化属性访问和方法调用，通过缓存对象的 Shape ID
//! 和属性偏移来实现 O(1) 的属性访问。
//!
//! 支持三种缓存模式：
//! 1. Monomorphic IC: 单态缓存（只缓存一个 Shape）
//! 2. Polymorphic IC: 多态缓存（缓存 2-4 个 Shape）
//! 3. Megamorphic: 超多态（退化为哈希表查找）
//!
//! 性能特征：
//! - Monomorphic: ~1ns (单次比较)
//! - Polymorphic: ~2-4ns (线性搜索 2-4 项)
//! - Megamorphic: ~20ns (哈希表查找)

const std = @import("std");
const shape_mod = @import("shape.zig");
const Shape = shape_mod.Shape;

/// 单态内联缓存 - 最快的缓存模式
/// 
/// 适用于大多数属性访问（>90%），因为大多数调用点只看到一种 Shape。
pub const MonomorphicIC = struct {
    /// 缓存的 Shape ID
    shape_id: u32,
    /// 属性偏移
    offset: u16,
    /// 命中计数
    hits: u32,
    /// 未命中计数
    misses: u32,
    
    pub const INVALID: MonomorphicIC = .{
        .shape_id = 0,
        .offset = 0,
        .hits = 0,
        .misses = 0,
    };
    
    /// 尝试快速属性访问
    /// 
    /// 如果 Shape ID 匹配，返回属性偏移。
    /// 否则返回 null，调用者需要进行慢速查找并更新缓存。
    pub inline fn tryLookup(self: *MonomorphicIC, shape_id: u32) ?u16 {
        if (self.shape_id == shape_id) {
            self.hits +|= 1; // 饱和加法，防止溢出
            return self.offset;
        }
        self.misses +|= 1;
        return null;
    }
    
    /// 更新缓存
    pub fn update(self: *MonomorphicIC, shape_id: u32, offset: u16) void {
        self.shape_id = shape_id;
        self.offset = offset;
        // 重置计数器
        self.hits = 0;
        self.misses = 0;
    }
    
    /// 失效缓存
    pub fn invalidate(self: *MonomorphicIC) void {
        self.* = INVALID;
    }
    
    /// 获取命中率
    pub fn getHitRate(self: *const MonomorphicIC) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }
};

/// 多态内联缓存 - 支持 2-4 个 Shape
/// 
/// 当一个调用点看到多个 Shape 时使用。
/// 使用线性搜索，因为项数很少（2-4），缓存友好。
pub const PolymorphicIC = struct {
    /// 缓存条目
    entries: [MAX_ENTRIES]Entry,
    /// 当前条目数
    count: u8,
    /// 命中计数
    hits: u32,
    /// 未命中计数
    misses: u32,
    
    pub const MAX_ENTRIES = 4;
    
    pub const Entry = struct {
        shape_id: u32,
        offset: u16,
    };
    
    pub const INVALID: PolymorphicIC = .{
        .entries = [_]Entry{.{ .shape_id = 0, .offset = 0 }} ** MAX_ENTRIES,
        .count = 0,
        .hits = 0,
        .misses = 0,
    };
    
    /// 查找属性偏移
    pub fn lookup(self: *PolymorphicIC, shape_id: u32) ?u16 {
        // 线性搜索（4 项足够小，缓存友好）
        for (self.entries[0..self.count]) |entry| {
            if (entry.shape_id == shape_id) {
                self.hits +|= 1;
                return entry.offset;
            }
        }
        self.misses +|= 1;
        return null;
    }
    
    /// 添加新条目
    /// 
    /// 如果缓存已满，返回 false（需要升级为 Megamorphic）。
    pub fn add(self: *PolymorphicIC, shape_id: u32, offset: u16) bool {
        // 检查是否已存在
        for (self.entries[0..self.count]) |*entry| {
            if (entry.shape_id == shape_id) {
                entry.offset = offset; // 更新偏移
                return true;
            }
        }
        
        // 添加新条目
        if (self.count < MAX_ENTRIES) {
            self.entries[self.count] = .{
                .shape_id = shape_id,
                .offset = offset,
            };
            self.count += 1;
            return true;
        }
        
        // 缓存已满
        return false;
    }
    
    /// 失效缓存
    pub fn invalidate(self: *PolymorphicIC) void {
        self.* = INVALID;
    }
    
    /// 获取命中率
    pub fn getHitRate(self: *const PolymorphicIC) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }
};

/// 内联缓存状态
pub const ICState = enum {
    uninitialized,  // 未初始化
    monomorphic,    // 单态
    polymorphic,    // 多态
    megamorphic,    // 超多态
};

/// 统一的内联缓存接口
/// 
/// 自动在 Monomorphic、Polymorphic 和 Megamorphic 之间切换。
pub const InlineCache = struct {
    /// 当前状态
    state: ICState,
    /// 缓存数据
    data: union {
        mono: MonomorphicIC,
        poly: PolymorphicIC,
        mega: void, // Megamorphic 退化为普通查找
    },
    /// 属性名（用于 Megamorphic 查找）
    property_name: ?[]const u8,
    
    pub fn init() InlineCache {
        return .{
            .state = .uninitialized,
            .data = .{ .mono = MonomorphicIC.INVALID },
            .property_name = null,
        };
    }
    
    /// 查找属性偏移
    pub fn lookup(self: *InlineCache, shape: *const Shape, property_name: []const u8) ?u16 {
        switch (self.state) {
            .uninitialized => {
                // 第一次访问，初始化为 Monomorphic
                if (shape.getPropertySlot(property_name)) |slot| {
                    self.state = .monomorphic;
                    self.data = .{ .mono = .{
                        .shape_id = shape.id,
                        .offset = slot.offset,
                        .hits = 1,
                        .misses = 0,
                    } };
                    self.property_name = property_name;
                    return slot.offset;
                }
                return null;
            },
            
            .monomorphic => {
                if (self.data.mono.tryLookup(shape.id)) |offset| {
                    return offset;
                }
                
                // 未命中，尝试升级为 Polymorphic
                if (shape.getPropertySlot(property_name)) |slot| {
                    self.state = .polymorphic;
                    var poly = PolymorphicIC.INVALID;
                    _ = poly.add(self.data.mono.shape_id, self.data.mono.offset);
                    _ = poly.add(shape.id, slot.offset);
                    self.data = .{ .poly = poly };
                    return slot.offset;
                }
                return null;
            },
            
            .polymorphic => {
                if (self.data.poly.lookup(shape.id)) |offset| {
                    return offset;
                }
                
                // 未命中，尝试添加
                if (shape.getPropertySlot(property_name)) |slot| {
                    if (!self.data.poly.add(shape.id, slot.offset)) {
                        // 缓存已满，升级为 Megamorphic
                        self.state = .megamorphic;
                        self.data = .{ .mega = {} };
                    }
                    return slot.offset;
                }
                return null;
            },
            
            .megamorphic => {
                // 退化为普通查找
                if (shape.getPropertySlot(property_name)) |slot| {
                    return slot.offset;
                }
                return null;
            },
        }
    }
    
    /// 失效缓存
    pub fn invalidate(self: *InlineCache) void {
        self.state = .uninitialized;
        self.data = .{ .mono = MonomorphicIC.INVALID };
        self.property_name = null;
    }
    
    /// 获取统计信息
    pub fn getStats(self: *const InlineCache) Stats {
        return switch (self.state) {
            .uninitialized => .{
                .state = .uninitialized,
                .hit_rate = 0.0,
                .entry_count = 0,
            },
            .monomorphic => .{
                .state = .monomorphic,
                .hit_rate = self.data.mono.getHitRate(),
                .entry_count = 1,
            },
            .polymorphic => .{
                .state = .polymorphic,
                .hit_rate = self.data.poly.getHitRate(),
                .entry_count = self.data.poly.count,
            },
            .megamorphic => .{
                .state = .megamorphic,
                .hit_rate = 0.0,
                .entry_count = 0,
            },
        };
    }
    
    pub const Stats = struct {
        state: ICState,
        hit_rate: f64,
        entry_count: u8,
    };
};

/// 内联缓存管理器 - 管理多个内联缓存
pub const InlineCacheManager = struct {
    /// 缓存池
    caches: std.ArrayListUnmanaged(InlineCache),
    /// 分配器
    allocator: std.mem.Allocator,
    /// 统计信息
    stats: Stats,
    
    pub const Stats = struct {
        total_caches: usize = 0,
        monomorphic_count: usize = 0,
        polymorphic_count: usize = 0,
        megamorphic_count: usize = 0,
        average_hit_rate: f64 = 0.0,
    };
    
    pub fn init(allocator: std.mem.Allocator) InlineCacheManager {
        return .{
            .caches = .{},
            .allocator = allocator,
            .stats = .{},
        };
    }
    
    pub fn deinit(self: *InlineCacheManager) void {
        self.caches.deinit(self.allocator);
    }
    
    /// 创建新的内联缓存
    pub fn createCache(self: *InlineCacheManager) !u32 {
        const id: u32 = @intCast(self.caches.items.len);
        try self.caches.append(self.allocator, InlineCache.init());
        return id;
    }
    
    /// 获取内联缓存
    pub fn getCache(self: *InlineCacheManager, id: u32) ?*InlineCache {
        if (id >= self.caches.items.len) return null;
        return &self.caches.items[id];
    }
    
    /// 失效所有缓存
    pub fn invalidateAll(self: *InlineCacheManager) void {
        for (self.caches.items) |*cache| {
            cache.invalidate();
        }
    }
    
    /// 更新统计信息
    pub fn updateStats(self: *InlineCacheManager) void {
        var mono_count: usize = 0;
        var poly_count: usize = 0;
        var mega_count: usize = 0;
        var total_hit_rate: f64 = 0.0;
        var valid_caches: usize = 0;
        
        for (self.caches.items) |*cache| {
            const cache_stats = cache.getStats();
            switch (cache_stats.state) {
                .uninitialized => {},
                .monomorphic => {
                    mono_count += 1;
                    total_hit_rate += cache_stats.hit_rate;
                    valid_caches += 1;
                },
                .polymorphic => {
                    poly_count += 1;
                    total_hit_rate += cache_stats.hit_rate;
                    valid_caches += 1;
                },
                .megamorphic => {
                    mega_count += 1;
                },
            }
        }
        
        self.stats = .{
            .total_caches = self.caches.items.len,
            .monomorphic_count = mono_count,
            .polymorphic_count = poly_count,
            .megamorphic_count = mega_count,
            .average_hit_rate = if (valid_caches > 0) total_hit_rate / @as(f64, @floatFromInt(valid_caches)) else 0.0,
        };
    }
    
    /// 获取统计信息
    pub fn getStats(self: *InlineCacheManager) Stats {
        return self.stats;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "MonomorphicIC - basic lookup" {
    var ic = MonomorphicIC.INVALID;
    
    // 更新缓存
    ic.update(42, 5);
    
    // 命中
    const offset1 = ic.tryLookup(42);
    try std.testing.expect(offset1 != null);
    try std.testing.expect(offset1.? == 5);
    try std.testing.expect(ic.hits == 1);
    
    // 未命中
    const offset2 = ic.tryLookup(43);
    try std.testing.expect(offset2 == null);
    try std.testing.expect(ic.misses == 1);
}

test "PolymorphicIC - multiple shapes" {
    var ic = PolymorphicIC.INVALID;
    
    // 添加多个 Shape
    try std.testing.expect(ic.add(10, 0));
    try std.testing.expect(ic.add(20, 1));
    try std.testing.expect(ic.add(30, 2));
    try std.testing.expect(ic.count == 3);
    
    // 查找
    try std.testing.expect(ic.lookup(10).? == 0);
    try std.testing.expect(ic.lookup(20).? == 1);
    try std.testing.expect(ic.lookup(30).? == 2);
    try std.testing.expect(ic.lookup(40) == null);
}

test "PolymorphicIC - overflow" {
    var ic = PolymorphicIC.INVALID;
    
    // 填满缓存
    try std.testing.expect(ic.add(1, 0));
    try std.testing.expect(ic.add(2, 1));
    try std.testing.expect(ic.add(3, 2));
    try std.testing.expect(ic.add(4, 3));
    try std.testing.expect(ic.count == 4);
    
    // 尝试添加第 5 个应该失败
    try std.testing.expect(!ic.add(5, 4));
}

test "InlineCache - state transitions" {
    const shape_mod_test = @import("shape.zig");
    
    var manager = try shape_mod_test.ShapeManager.init(std.testing.allocator);
    defer manager.deinit();
    
    const root = manager.getRootShape();
    defer root.release();
    
    const shape1 = try root.transition("x");
    defer shape1.release();
    
    const shape2 = try root.transition("y");
    defer shape2.release();
    
    var ic = InlineCache.init();
    
    // 初始状态
    try std.testing.expect(ic.state == .uninitialized);
    
    // 第一次访问 -> Monomorphic
    _ = ic.lookup(shape1, "x");
    try std.testing.expect(ic.state == .monomorphic);
    
    // 第二个 Shape -> Polymorphic
    _ = ic.lookup(shape2, "y");
    try std.testing.expect(ic.state == .polymorphic);
}

test "InlineCacheManager - basic operations" {
    var manager = InlineCacheManager.init(std.testing.allocator);
    defer manager.deinit();
    
    // 创建缓存
    const id1 = try manager.createCache();
    const id2 = try manager.createCache();
    
    try std.testing.expect(id1 == 0);
    try std.testing.expect(id2 == 1);
    
    // 获取缓存
    const cache1 = manager.getCache(id1);
    try std.testing.expect(cache1 != null);
    try std.testing.expect(cache1.?.state == .uninitialized);
    
    // 失效所有缓存
    manager.invalidateAll();
    
    // 更新统计
    manager.updateStats();
    const stats = manager.getStats();
    try std.testing.expect(stats.total_caches == 2);
}
