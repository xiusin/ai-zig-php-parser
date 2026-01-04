const std = @import("std");

/// 类型反馈系统
/// 用于收集运行时类型信息，支持类型特化优化
/// 
/// 设计目标：
/// - 记录调用点观察到的类型
/// - 支持单态/多态/超多态判断
/// - 为JIT编译器提供类型特化依据

// ============================================================================
// 类型标签定义
// ============================================================================

/// 运行时类型标签
pub const TypeTag = enum(u8) {
    null_type = 0,
    bool_type = 1,
    int_type = 2,
    float_type = 3,
    string_type = 4,
    array_type = 5,
    object_type = 6,
    struct_type = 7,
    closure_type = 8,
    resource_type = 9,
    mixed_type = 255, // 未知或混合类型
};

// ============================================================================
// 类型反馈结构
// ============================================================================

/// 单个调用点的类型反馈信息
pub const TypeFeedback = struct {
    /// 调用点ID（字节码偏移或唯一标识）
    call_site_id: u32,
    /// 观察到的类型（最多记录4种）
    observed_types: [MAX_OBSERVED_TYPES]TypeTag,
    /// 已记录的类型数量
    type_count: u8,
    /// 调用次数
    call_count: u32,
    /// 最后一次调用的时间戳（用于热度判断）
    last_call_timestamp: i64,

    const MAX_OBSERVED_TYPES: usize = 4;
    /// 单态判断阈值：调用次数超过此值且只有一种类型
    const MONOMORPHIC_THRESHOLD: u32 = 100;
    /// 超多态阈值：类型数量超过此值
    const MEGAMORPHIC_THRESHOLD: u8 = 4;

    /// 初始化类型反馈
    pub fn init(call_site_id: u32) TypeFeedback {
        return TypeFeedback{
            .call_site_id = call_site_id,
            .observed_types = [_]TypeTag{.mixed_type} ** MAX_OBSERVED_TYPES,
            .type_count = 0,
            .call_count = 0,
            .last_call_timestamp = 0,
        };
    }

    /// 记录观察到的类型
    pub fn recordType(self: *TypeFeedback, tag: TypeTag) void {
        self.call_count +|= 1; // 饱和加法，防止溢出
        self.last_call_timestamp = std.time.timestamp();

        // 检查是否已记录此类型
        for (self.observed_types[0..self.type_count]) |t| {
            if (t == tag) return;
        }

        // 添加新类型（如果还有空间）
        if (self.type_count < MAX_OBSERVED_TYPES) {
            self.observed_types[self.type_count] = tag;
            self.type_count += 1;
        }
    }

    /// 记录多个参数的类型
    pub fn recordTypes(self: *TypeFeedback, tags: []const TypeTag) void {
        for (tags) |tag| {
            self.recordType(tag);
        }
    }

    /// 判断是否为单态（只观察到一种类型且调用次数足够）
    pub fn isMonomorphic(self: *const TypeFeedback) bool {
        return self.type_count == 1 and self.call_count >= MONOMORPHIC_THRESHOLD;
    }

    /// 判断是否为多态（观察到2-3种类型）
    pub fn isPolymorphic(self: *const TypeFeedback) bool {
        return self.type_count >= 2 and self.type_count < MEGAMORPHIC_THRESHOLD;
    }

    /// 判断是否为超多态（观察到4种或更多类型）
    pub fn isMegamorphic(self: *const TypeFeedback) bool {
        return self.type_count >= MEGAMORPHIC_THRESHOLD;
    }

    /// 获取主要类型（出现最多的类型）
    /// 对于单态情况，直接返回唯一类型
    pub fn getPrimaryType(self: *const TypeFeedback) ?TypeTag {
        if (self.type_count == 0) return null;
        return self.observed_types[0];
    }

    /// 获取所有观察到的类型
    pub fn getObservedTypes(self: *const TypeFeedback) []const TypeTag {
        return self.observed_types[0..self.type_count];
    }

    /// 重置类型反馈（去优化后使用）
    pub fn reset(self: *TypeFeedback) void {
        self.observed_types = [_]TypeTag{.mixed_type} ** MAX_OBSERVED_TYPES;
        self.type_count = 0;
        self.call_count = 0;
    }

    /// 判断是否为热点（调用频繁）
    pub fn isHot(self: *const TypeFeedback, threshold: u32) bool {
        return self.call_count >= threshold;
    }
};

// ============================================================================
// 类型反馈收集器
// ============================================================================

/// 类型反馈收集器 - 管理多个调用点的类型反馈
pub const TypeFeedbackCollector = struct {
    allocator: std.mem.Allocator,
    /// 调用点ID -> 类型反馈映射
    feedbacks: std.AutoHashMapUnmanaged(u32, TypeFeedback),
    /// 统计信息
    stats: CollectorStats,

    pub const CollectorStats = struct {
        total_sites: usize = 0,
        monomorphic_sites: usize = 0,
        polymorphic_sites: usize = 0,
        megamorphic_sites: usize = 0,
        total_recordings: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) TypeFeedbackCollector {
        return TypeFeedbackCollector{
            .allocator = allocator,
            .feedbacks = .{},
            .stats = .{},
        };
    }

    pub fn deinit(self: *TypeFeedbackCollector) void {
        self.feedbacks.deinit(self.allocator);
    }

    /// 记录调用点的类型
    pub fn record(self: *TypeFeedbackCollector, call_site_id: u32, tag: TypeTag) !void {
        self.stats.total_recordings += 1;

        const result = self.feedbacks.getOrPut(self.allocator, call_site_id) catch |err| {
            return err;
        };

        if (!result.found_existing) {
            result.value_ptr.* = TypeFeedback.init(call_site_id);
            self.stats.total_sites += 1;
        }

        result.value_ptr.recordType(tag);
    }

    /// 获取调用点的类型反馈
    pub fn getFeedback(self: *TypeFeedbackCollector, call_site_id: u32) ?*TypeFeedback {
        return self.feedbacks.getPtr(call_site_id);
    }

    /// 获取或创建调用点的类型反馈
    pub fn getOrCreateFeedback(self: *TypeFeedbackCollector, call_site_id: u32) !*TypeFeedback {
        const result = try self.feedbacks.getOrPut(self.allocator, call_site_id);
        if (!result.found_existing) {
            result.value_ptr.* = TypeFeedback.init(call_site_id);
            self.stats.total_sites += 1;
        }
        return result.value_ptr;
    }

    /// 更新统计信息
    pub fn updateStats(self: *TypeFeedbackCollector) void {
        self.stats.monomorphic_sites = 0;
        self.stats.polymorphic_sites = 0;
        self.stats.megamorphic_sites = 0;

        var iter = self.feedbacks.iterator();
        while (iter.next()) |entry| {
            const feedback = entry.value_ptr;
            if (feedback.isMonomorphic()) {
                self.stats.monomorphic_sites += 1;
            } else if (feedback.isPolymorphic()) {
                self.stats.polymorphic_sites += 1;
            } else if (feedback.isMegamorphic()) {
                self.stats.megamorphic_sites += 1;
            }
        }
    }

    /// 获取统计信息
    pub fn getStats(self: *const TypeFeedbackCollector) CollectorStats {
        return self.stats;
    }

    /// 获取所有热点调用点
    pub fn getHotSites(self: *TypeFeedbackCollector, threshold: u32, allocator: std.mem.Allocator) ![]u32 {
        var hot_sites = std.ArrayListUnmanaged(u32){};
        errdefer hot_sites.deinit(allocator);

        var iter = self.feedbacks.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isHot(threshold)) {
                try hot_sites.append(allocator, entry.key_ptr.*);
            }
        }

        return hot_sites.toOwnedSlice(allocator);
    }

    /// 清除所有类型反馈（全局去优化）
    pub fn clearAll(self: *TypeFeedbackCollector) void {
        var iter = self.feedbacks.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.reset();
        }
        self.stats = .{};
    }

    /// 清除特定调用点的类型反馈
    pub fn clearSite(self: *TypeFeedbackCollector, call_site_id: u32) void {
        if (self.feedbacks.getPtr(call_site_id)) |feedback| {
            feedback.reset();
        }
    }
};

// ============================================================================
// 属性访问类型反馈
// ============================================================================

/// 属性访问的类型反馈（用于内联缓存）
pub const PropertyFeedback = struct {
    /// 属性名哈希
    property_hash: u64,
    /// 观察到的对象Shape ID
    observed_shapes: [MAX_SHAPES]u64,
    /// 已记录的Shape数量
    shape_count: u8,
    /// 访问次数
    access_count: u32,

    const MAX_SHAPES: usize = 4;

    pub fn init(property_hash: u64) PropertyFeedback {
        return PropertyFeedback{
            .property_hash = property_hash,
            .observed_shapes = [_]u64{0} ** MAX_SHAPES,
            .shape_count = 0,
            .access_count = 0,
        };
    }

    /// 记录观察到的Shape
    pub fn recordShape(self: *PropertyFeedback, shape_id: u64) void {
        self.access_count +|= 1;

        // 检查是否已记录此Shape
        for (self.observed_shapes[0..self.shape_count]) |s| {
            if (s == shape_id) return;
        }

        // 添加新Shape
        if (self.shape_count < MAX_SHAPES) {
            self.observed_shapes[self.shape_count] = shape_id;
            self.shape_count += 1;
        }
    }

    /// 判断是否为单态属性访问
    pub fn isMonomorphic(self: *const PropertyFeedback) bool {
        return self.shape_count == 1 and self.access_count >= 50;
    }

    /// 判断是否为多态属性访问
    pub fn isPolymorphic(self: *const PropertyFeedback) bool {
        return self.shape_count >= 2 and self.shape_count < MAX_SHAPES;
    }

    /// 判断是否为超多态属性访问
    pub fn isMegamorphic(self: *const PropertyFeedback) bool {
        return self.shape_count >= MAX_SHAPES;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "type feedback basic" {
    var feedback = TypeFeedback.init(0);

    // 记录类型
    feedback.recordType(.int_type);
    try std.testing.expect(feedback.type_count == 1);
    try std.testing.expect(feedback.call_count == 1);

    // 重复记录相同类型
    feedback.recordType(.int_type);
    try std.testing.expect(feedback.type_count == 1);
    try std.testing.expect(feedback.call_count == 2);

    // 记录不同类型
    feedback.recordType(.float_type);
    try std.testing.expect(feedback.type_count == 2);
}

test "type feedback monomorphic detection" {
    var feedback = TypeFeedback.init(0);

    // 初始不是单态
    try std.testing.expect(!feedback.isMonomorphic());

    // 记录足够多的相同类型调用
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        feedback.recordType(.int_type);
    }

    // 现在应该是单态
    try std.testing.expect(feedback.isMonomorphic());
    try std.testing.expect(!feedback.isPolymorphic());
    try std.testing.expect(!feedback.isMegamorphic());
}

test "type feedback polymorphic detection" {
    var feedback = TypeFeedback.init(0);

    feedback.recordType(.int_type);
    feedback.recordType(.float_type);
    feedback.recordType(.string_type);

    try std.testing.expect(!feedback.isMonomorphic());
    try std.testing.expect(feedback.isPolymorphic());
    try std.testing.expect(!feedback.isMegamorphic());
}

test "type feedback megamorphic detection" {
    var feedback = TypeFeedback.init(0);

    feedback.recordType(.int_type);
    feedback.recordType(.float_type);
    feedback.recordType(.string_type);
    feedback.recordType(.array_type);

    try std.testing.expect(!feedback.isMonomorphic());
    try std.testing.expect(!feedback.isPolymorphic());
    try std.testing.expect(feedback.isMegamorphic());
}

test "type feedback collector" {
    const allocator = std.testing.allocator;
    var collector = TypeFeedbackCollector.init(allocator);
    defer collector.deinit();

    // 记录类型
    try collector.record(0, .int_type);
    try collector.record(0, .int_type);
    try collector.record(1, .string_type);

    // 获取反馈
    const feedback0 = collector.getFeedback(0);
    try std.testing.expect(feedback0 != null);
    try std.testing.expect(feedback0.?.call_count == 2);

    const feedback1 = collector.getFeedback(1);
    try std.testing.expect(feedback1 != null);
    try std.testing.expect(feedback1.?.type_count == 1);

    // 统计
    try std.testing.expect(collector.stats.total_sites == 2);
    try std.testing.expect(collector.stats.total_recordings == 3);
}

test "property feedback" {
    var feedback = PropertyFeedback.init(12345);

    feedback.recordShape(100);
    try std.testing.expect(feedback.shape_count == 1);

    feedback.recordShape(100); // 重复
    try std.testing.expect(feedback.shape_count == 1);

    feedback.recordShape(200);
    try std.testing.expect(feedback.shape_count == 2);
    try std.testing.expect(feedback.isPolymorphic());
}
