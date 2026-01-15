//! Shape System (Hidden Classes) - 对象形状系统
//! 
//! Shape 系统用于优化对象属性访问，通过跟踪对象的"形状"（属性布局）
//! 来实现高效的内联缓存。
//!
//! 核心概念：
//! 1. Shape: 描述对象的属性布局（属性名 -> 槽位偏移）
//! 2. Shape Transition: 添加属性时创建新的 Shape
//! 3. Shape Tree: 共享相同属性序列的对象共享 Shape
//!
//! 性能优势：
//! - O(1) 属性访问（通过槽位偏移）
//! - 内联缓存友好（Shape ID 比较）
//! - 内存高效（Shape 共享）

const std = @import("std");

/// 全局 Shape ID 计数器
var next_shape_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

/// 获取下一个 Shape ID
pub fn nextShapeId() u32 {
    return next_shape_id.fetchAdd(1, .monotonic);
}

/// 属性槽位信息
pub const PropertySlot = struct {
    /// 槽位偏移（在对象的 slots 数组中的索引）
    offset: u16,
    /// 属性标志
    flags: Flags = .{},
    
    pub const Flags = packed struct {
        writable: bool = true,
        enumerable: bool = true,
        configurable: bool = true,
        _padding: u5 = 0,
    };
};

/// 对象形状 - 描述属性布局
/// 
/// Shape 是不可变的，添加属性时会创建新的 Shape。
/// 这确保了 Shape 可以安全地被多个对象共享。
pub const Shape = struct {
    /// 唯一 ID（用于内联缓存）
    id: u32,
    /// 父 Shape（用于构建 Shape 树）
    parent: ?*Shape,
    /// 属性名到槽位的映射
    property_map: PropertyMap,
    /// 转换映射（属性名 -> 子 Shape）
    transition_map: TransitionMap,
    /// 引用计数（用于内存管理）
    ref_count: std.atomic.Value(u32),
    /// 分配器
    allocator: std.mem.Allocator,
    
    pub const PropertyMap = std.StringHashMapUnmanaged(PropertySlot);
    pub const TransitionMap = std.StringHashMapUnmanaged(*Shape);
    
    /// 创建根 Shape（空对象）
    pub fn createRoot(allocator: std.mem.Allocator) !*Shape {
        const shape = try allocator.create(Shape);
        shape.* = .{
            .id = nextShapeId(),
            .parent = null,
            .property_map = .{},
            .transition_map = .{},
            .ref_count = std.atomic.Value(u32).init(1),
            .allocator = allocator,
        };
        return shape;
    }
    
    /// 添加属性转换 - 返回新 Shape
    /// 
    /// 如果已经存在相同属性的转换，返回现有的 Shape。
    /// 否则创建新的 Shape 并记录转换。
    pub fn transition(self: *Shape, name: []const u8) !*Shape {
        // 检查是否已有转换
        if (self.transition_map.get(name)) |existing| {
            existing.retain();
            return existing;
        }
        
        // 创建新 Shape
        const new_shape = try self.allocator.create(Shape);
        errdefer self.allocator.destroy(new_shape);
        
        new_shape.* = .{
            .id = nextShapeId(),
            .parent = self,
            .property_map = try self.property_map.clone(self.allocator),
            .transition_map = .{},
            .ref_count = std.atomic.Value(u32).init(1),
            .allocator = self.allocator,
        };
        
        // 添加新属性槽
        const offset: u16 = @intCast(new_shape.property_map.count());
        try new_shape.property_map.put(self.allocator, name, .{ .offset = offset });
        
        // 记录转换
        try self.transition_map.put(self.allocator, name, new_shape);
        new_shape.retain(); // 转换映射持有引用
        
        return new_shape;
    }
    
    /// 查找属性槽位
    pub fn getPropertySlot(self: *const Shape, name: []const u8) ?PropertySlot {
        return self.property_map.get(name);
    }
    
    /// 获取属性数量
    pub fn propertyCount(self: *const Shape) usize {
        return self.property_map.count();
    }
    
    /// 增加引用计数
    pub fn retain(self: *Shape) void {
        _ = self.ref_count.fetchAdd(1, .monotonic);
    }
    
    /// 减少引用计数，如果为 0 则释放
    pub fn release(self: *Shape) void {
        const old_count = self.ref_count.fetchSub(1, .release);
        if (old_count == 1) {
            // 最后一个引用，释放资源
            std.atomic.fence(.acquire);
            self.deinit();
        }
    }
    
    fn deinit(self: *Shape) void {
        // 释放转换映射中的 Shape
        var trans_iter = self.transition_map.valueIterator();
        while (trans_iter.next()) |child_shape| {
            child_shape.*.release();
        }
        self.transition_map.deinit(self.allocator);
        
        // 释放属性映射
        self.property_map.deinit(self.allocator);
        
        // 释放自身
        self.allocator.destroy(self);
    }
    
    /// 获取统计信息
    pub fn getStats(self: *const Shape) Stats {
        return .{
            .id = self.id,
            .property_count = self.property_map.count(),
            .transition_count = self.transition_map.count(),
            .ref_count = self.ref_count.load(.monotonic),
        };
    }
    
    pub const Stats = struct {
        id: u32,
        property_count: usize,
        transition_count: usize,
        ref_count: u32,
    };
};

/// Shape 管理器 - 管理全局 Shape 树
pub const ShapeManager = struct {
    /// 根 Shape（空对象）
    root_shape: *Shape,
    /// 分配器
    allocator: std.mem.Allocator,
    /// 统计信息
    stats: Stats,
    
    pub const Stats = struct {
        total_shapes: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        cache_hits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        cache_misses: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    };
    
    pub fn init(allocator: std.mem.Allocator) !ShapeManager {
        const root = try Shape.createRoot(allocator);
        return .{
            .root_shape = root,
            .allocator = allocator,
            .stats = .{},
        };
    }
    
    pub fn deinit(self: *ShapeManager) void {
        self.root_shape.release();
    }
    
    /// 获取根 Shape
    pub fn getRootShape(self: *ShapeManager) *Shape {
        self.root_shape.retain();
        return self.root_shape;
    }
    
    /// 记录缓存命中
    pub fn recordCacheHit(self: *ShapeManager) void {
        _ = self.stats.cache_hits.fetchAdd(1, .monotonic);
    }
    
    /// 记录缓存未命中
    pub fn recordCacheMiss(self: *ShapeManager) void {
        _ = self.stats.cache_misses.fetchAdd(1, .monotonic);
    }
    
    /// 获取统计信息
    pub fn getStats(self: *const ShapeManager) Stats {
        return self.stats;
    }
    
    /// 计算缓存命中率
    pub fn getCacheHitRate(self: *const ShapeManager) f64 {
        const hits = self.stats.cache_hits.load(.monotonic);
        const misses = self.stats.cache_misses.load(.monotonic);
        const total = hits + misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(total));
    }
};

// ============================================================================
// 测试
// ============================================================================

test "Shape - basic creation and transition" {
    var manager = try ShapeManager.init(std.testing.allocator);
    defer manager.deinit();
    
    // 获取根 Shape
    const root = manager.getRootShape();
    defer root.release();
    
    try std.testing.expect(root.propertyCount() == 0);
    try std.testing.expect(root.parent == null);
    
    // 添加第一个属性
    const shape1 = try root.transition("x");
    defer shape1.release();
    
    try std.testing.expect(shape1.propertyCount() == 1);
    try std.testing.expect(shape1.parent == root);
    
    const slot_x = shape1.getPropertySlot("x");
    try std.testing.expect(slot_x != null);
    try std.testing.expect(slot_x.?.offset == 0);
    
    // 添加第二个属性
    const shape2 = try shape1.transition("y");
    defer shape2.release();
    
    try std.testing.expect(shape2.propertyCount() == 2);
    try std.testing.expect(shape2.parent == shape1);
    
    const slot_y = shape2.getPropertySlot("y");
    try std.testing.expect(slot_y != null);
    try std.testing.expect(slot_y.?.offset == 1);
}

test "Shape - transition caching" {
    var manager = try ShapeManager.init(std.testing.allocator);
    defer manager.deinit();
    
    const root = manager.getRootShape();
    defer root.release();
    
    // 第一次转换
    const shape1a = try root.transition("x");
    defer shape1a.release();
    
    // 第二次相同转换应该返回同一个 Shape
    const shape1b = try root.transition("x");
    defer shape1b.release();
    
    try std.testing.expect(shape1a == shape1b);
    try std.testing.expect(shape1a.id == shape1b.id);
}

test "Shape - property slot lookup" {
    var manager = try ShapeManager.init(std.testing.allocator);
    defer manager.deinit();
    
    const root = manager.getRootShape();
    defer root.release();
    
    const shape1 = try root.transition("a");
    defer shape1.release();
    
    const shape2 = try shape1.transition("b");
    defer shape2.release();
    
    const shape3 = try shape2.transition("c");
    defer shape3.release();
    
    // 验证所有属性都能找到
    const slot_a = shape3.getPropertySlot("a");
    const slot_b = shape3.getPropertySlot("b");
    const slot_c = shape3.getPropertySlot("c");
    
    try std.testing.expect(slot_a != null);
    try std.testing.expect(slot_b != null);
    try std.testing.expect(slot_c != null);
    
    try std.testing.expect(slot_a.?.offset == 0);
    try std.testing.expect(slot_b.?.offset == 1);
    try std.testing.expect(slot_c.?.offset == 2);
}

test "Shape - reference counting" {
    var manager = try ShapeManager.init(std.testing.allocator);
    defer manager.deinit();
    
    const root = manager.getRootShape();
    
    // 初始引用计数应该是 2（manager 持有 1，我们持有 1）
    const initial_count = root.ref_count.load(.monotonic);
    try std.testing.expect(initial_count >= 2);
    
    // 增加引用
    root.retain();
    const after_retain = root.ref_count.load(.monotonic);
    try std.testing.expect(after_retain == initial_count + 1);
    
    // 减少引用
    root.release();
    const after_release = root.ref_count.load(.monotonic);
    try std.testing.expect(after_release == initial_count);
    
    // 最后释放我们的引用
    root.release();
}

test "ShapeManager - cache hit rate" {
    var manager = try ShapeManager.init(std.testing.allocator);
    defer manager.deinit();
    
    // 初始命中率应该是 0
    try std.testing.expect(manager.getCacheHitRate() == 0.0);
    
    // 记录一些命中和未命中
    manager.recordCacheHit();
    manager.recordCacheHit();
    manager.recordCacheHit();
    manager.recordCacheMiss();
    
    // 命中率应该是 75%
    const hit_rate = manager.getCacheHitRate();
    try std.testing.expect(hit_rate == 0.75);
}
