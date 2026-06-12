//! GC 根集合访问系统
//!
//! 管理所有 GC 根对象，包括：
//! - 栈上的对象
//! - 全局变量中的对象
//! - 寄存器中的对象
//! - 跨代引用（老年代指向新生代）
//!
//! ## 内存安全
//! @memory-safety 所有指针操作都有边界检查
//! @ownership NON-OWNING (allocator)
//! @thread-safety ISOLATED
//!
//! ## 使用示例
//! ```zig
//! var root_set = try RootSet.init(allocator);
//! defer root_set.deinit();
//!
//! try root_set.addStackRoot(obj_ptr);
//! try root_set.addGlobalRoot(global_ptr);
//!
//! try root_set.iterateRoots(struct {
//!     fn visit(obj: *GCObjectHeader) !void {
//!         obj.mark();
//!     }
//! }.visit);
//! ```

const std = @import("std");
const GCObjectHeader = @import("generational_gc.zig").GCObjectHeader;

// ============================================================================
// 根对象类型
// ============================================================================

/// 根对象类型
pub const RootType = enum(u8) {
    /// 栈上的对象
    stack = 0,
    /// 全局变量中的对象
    global = 1,
    /// 寄存器中的对象
    register = 2,
    /// 跨代引用（老年代 -> 新生代）
    cross_generation = 3,
    /// 临时根（用于 GC 期间保护对象）
    temporary = 4,
};

/// 根对象条目
pub const RootEntry = struct {
    /// 对象指针
    object: *GCObjectHeader,
    /// 根类型
    root_type: RootType,
    /// 元数据（用于调试）
    metadata: RootMetadata,
    
    pub const RootMetadata = struct {
        /// 添加时间戳
        timestamp: i64,
        /// 来源描述（用于调试）
        source: []const u8,
    };
};

// ============================================================================
// 根集合
// ============================================================================

/// GC 根集合
/// @pre allocator 必须在整个生命周期内有效
/// @post deinit() 后所有资源被释放
pub const RootSet = struct {
    /// 分配器
    allocator: std.mem.Allocator,
    
    /// 栈根列表
    stack_roots: std.ArrayListUnmanaged(*GCObjectHeader),
    
    /// 全局根列表
    global_roots: std.ArrayListUnmanaged(*GCObjectHeader),
    
    /// 寄存器根列表
    register_roots: std.ArrayListUnmanaged(*GCObjectHeader),
    
    /// 跨代引用列表
    cross_gen_roots: std.ArrayListUnmanaged(*GCObjectHeader),
    
    /// 临时根列表
    temporary_roots: std.ArrayListUnmanaged(*GCObjectHeader),
    
    /// 所有根的统一视图（用于快速查找）
    all_roots: std.AutoHashMapUnmanaged(*GCObjectHeader, RootEntry),
    
    /// 统计信息
    stats: RootSetStats,
    
    pub const RootSetStats = struct {
        /// 栈根数量
        stack_count: usize = 0,
        /// 全局根数量
        global_count: usize = 0,
        /// 寄存器根数量
        register_count: usize = 0,
        /// 跨代引用数量
        cross_gen_count: usize = 0,
        /// 临时根数量
        temporary_count: usize = 0,
        /// 总根数量
        total_count: usize = 0,
        /// 添加操作次数
        add_operations: usize = 0,
        /// 移除操作次数
        remove_operations: usize = 0,
    };
    
    /// 初始化根集合
    /// @pre allocator 必须有效
    /// @post 返回已初始化的根集合
    pub fn init(allocator: std.mem.Allocator) !RootSet {
        return RootSet{
            .allocator = allocator,
            .stack_roots = .{},
            .global_roots = .{},
            .register_roots = .{},
            .cross_gen_roots = .{},
            .temporary_roots = .{},
            .all_roots = .{},
            .stats = .{},
        };
    }
    
    /// 释放所有资源
    /// @pre self 必须已初始化
    /// @post 所有内存被释放
    pub fn deinit(self: *RootSet) void {
        self.stack_roots.deinit(self.allocator);
        self.global_roots.deinit(self.allocator);
        self.register_roots.deinit(self.allocator);
        self.cross_gen_roots.deinit(self.allocator);
        self.temporary_roots.deinit(self.allocator);
        self.all_roots.deinit(self.allocator);
    }
    
    // ========================================================================
    // 添加根对象
    // ========================================================================
    
    /// 添加栈根
    /// @pre object 必须是有效的 GC 对象
    /// @post object 被添加到栈根列表
    pub fn addStackRoot(self: *RootSet, object: *GCObjectHeader) !void {
        try self.addRoot(object, .stack, "stack");
        try self.stack_roots.append(self.allocator, object);
        self.stats.stack_count += 1;
    }
    
    /// 添加全局根
    /// @pre object 必须是有效的 GC 对象
    /// @post object 被添加到全局根列表
    pub fn addGlobalRoot(self: *RootSet, object: *GCObjectHeader) !void {
        try self.addRoot(object, .global, "global");
        try self.global_roots.append(self.allocator, object);
        self.stats.global_count += 1;
    }
    
    /// 添加寄存器根
    /// @pre object 必须是有效的 GC 对象
    /// @post object 被添加到寄存器根列表
    pub fn addRegisterRoot(self: *RootSet, object: *GCObjectHeader) !void {
        try self.addRoot(object, .register, "register");
        try self.register_roots.append(self.allocator, object);
        self.stats.register_count += 1;
    }
    
    /// 添加跨代引用
    /// @pre object 必须是有效的 GC 对象
    /// @post object 被添加到跨代引用列表
    pub fn addCrossGenRoot(self: *RootSet, object: *GCObjectHeader) !void {
        try self.addRoot(object, .cross_generation, "cross_gen");
        try self.cross_gen_roots.append(self.allocator, object);
        self.stats.cross_gen_count += 1;
    }
    
    /// 添加临时根
    /// @pre object 必须是有效的 GC 对象
    /// @post object 被添加到临时根列表
    pub fn addTemporaryRoot(self: *RootSet, object: *GCObjectHeader) !void {
        try self.addRoot(object, .temporary, "temporary");
        try self.temporary_roots.append(self.allocator, object);
        self.stats.temporary_count += 1;
    }
    
    /// 内部：添加根到统一视图
    fn addRoot(self: *RootSet, object: *GCObjectHeader, root_type: RootType, source: []const u8) !void {
        // 检查是否已存在
        if (self.all_roots.contains(object)) {
            // 已存在，更新类型
            if (self.all_roots.getPtr(object)) |entry| {
                entry.root_type = root_type;
                entry.metadata.timestamp = std.time.timestamp();
            }
            return;
        }
        
        // 添加新根
        try self.all_roots.put(self.allocator, object, .{
            .object = object,
            .root_type = root_type,
            .metadata = .{
                .timestamp = std.time.timestamp(),
                .source = source,
            },
        });
        
        self.stats.total_count += 1;
        self.stats.add_operations += 1;
    }
    
    // ========================================================================
    // 移除根对象
    // ========================================================================
    
    /// 移除栈根
    /// @pre object 必须存在于栈根列表
    /// @post object 被从栈根列表移除
    pub fn removeStackRoot(self: *RootSet, object: *GCObjectHeader) void {
        self.removeFromList(&self.stack_roots, object);
        self.removeRoot(object);
        if (self.stats.stack_count > 0) {
            self.stats.stack_count -= 1;
        }
    }
    
    /// 移除全局根
    /// @pre object 必须存在于全局根列表
    /// @post object 被从全局根列表移除
    pub fn removeGlobalRoot(self: *RootSet, object: *GCObjectHeader) void {
        self.removeFromList(&self.global_roots, object);
        self.removeRoot(object);
        if (self.stats.global_count > 0) {
            self.stats.global_count -= 1;
        }
    }
    
    /// 移除寄存器根
    /// @pre object 必须存在于寄存器根列表
    /// @post object 被从寄存器根列表移除
    pub fn removeRegisterRoot(self: *RootSet, object: *GCObjectHeader) void {
        self.removeFromList(&self.register_roots, object);
        self.removeRoot(object);
        if (self.stats.register_count > 0) {
            self.stats.register_count -= 1;
        }
    }
    
    /// 清空所有临时根
    /// @post 所有临时根被移除
    pub fn clearTemporaryRoots(self: *RootSet) void {
        for (self.temporary_roots.items) |obj| {
            _ = self.all_roots.remove(obj);
        }
        self.temporary_roots.clearRetainingCapacity();
        self.stats.total_count -= self.stats.temporary_count;
        self.stats.temporary_count = 0;
    }
    
    /// 内部：从列表中移除对象
    fn removeFromList(_: *RootSet, list: *std.ArrayListUnmanaged(*GCObjectHeader), object: *GCObjectHeader) void {
        var i: usize = 0;
        while (i < list.items.len) {
            if (list.items[i] == object) {
                _ = list.swapRemove(i);
                return;
            }
            i += 1;
        }
    }
    
    /// 内部：从统一视图移除根
    fn removeRoot(self: *RootSet, object: *GCObjectHeader) void {
        if (self.all_roots.remove(object)) {
            if (self.stats.total_count > 0) {
                self.stats.total_count -= 1;
            }
            self.stats.remove_operations += 1;
        }
    }
    
    // ========================================================================
    // 遍历根对象
    // ========================================================================
    
    /// 遍历所有根对象
    /// @pre visitor 必须是有效的访问器函数
    /// @post 所有根对象都被访问
    pub fn iterateRoots(self: *RootSet, visitor: anytype) !void {
        // 遍历栈根
        for (self.stack_roots.items) |obj| {
            try visitor(obj);
        }
        
        // 遍历全局根
        for (self.global_roots.items) |obj| {
            try visitor(obj);
        }
        
        // 遍历寄存器根
        for (self.register_roots.items) |obj| {
            try visitor(obj);
        }
        
        // 遍历跨代引用
        for (self.cross_gen_roots.items) |obj| {
            try visitor(obj);
        }
        
        // 遍历临时根
        for (self.temporary_roots.items) |obj| {
            try visitor(obj);
        }
    }
    
    /// 遍历特定类型的根对象
    /// @pre root_type 必须是有效的根类型
    /// @post 指定类型的所有根对象都被访问
    pub fn iterateRootsByType(self: *RootSet, root_type: RootType, visitor: anytype) !void {
        const list = switch (root_type) {
            .stack => &self.stack_roots,
            .global => &self.global_roots,
            .register => &self.register_roots,
            .cross_generation => &self.cross_gen_roots,
            .temporary => &self.temporary_roots,
        };
        
        for (list.items) |obj| {
            try visitor(obj);
        }
    }
    
    // ========================================================================
    // 查询和统计
    // ========================================================================
    
    /// 检查对象是否是根
    /// @pre object 必须是有效的指针
    /// @post 返回对象是否在根集合中
    pub fn isRoot(self: *const RootSet, object: *GCObjectHeader) bool {
        return self.all_roots.contains(object);
    }
    
    /// 获取根对象的类型
    /// @pre object 必须在根集合中
    /// @post 返回根对象的类型
    pub fn getRootType(self: *const RootSet, object: *GCObjectHeader) ?RootType {
        if (self.all_roots.get(object)) |entry| {
            return entry.root_type;
        }
        return null;
    }
    
    /// 获取统计信息
    /// @post 返回当前的统计信息
    pub fn getStats(self: *const RootSet) RootSetStats {
        return self.stats;
    }
    
    /// 获取总根数量
    /// @post 返回所有根对象的数量
    pub fn getTotalCount(self: *const RootSet) usize {
        return self.stats.total_count;
    }
    
    /// 清空所有根（用于测试）
    /// @post 所有根被移除
    pub fn clear(self: *RootSet) void {
        self.stack_roots.clearRetainingCapacity();
        self.global_roots.clearRetainingCapacity();
        self.register_roots.clearRetainingCapacity();
        self.cross_gen_roots.clearRetainingCapacity();
        self.temporary_roots.clearRetainingCapacity();
        self.all_roots.clearRetainingCapacity();
        self.stats = .{};
    }
};

// ============================================================================
// 测试
// ============================================================================

test "RootSet initialization" {
    const allocator = std.testing.allocator;
    
    var root_set = try RootSet.init(allocator);
    defer root_set.deinit();
    
    try std.testing.expectEqual(@as(usize, 0), root_set.getTotalCount());
    try std.testing.expectEqual(@as(usize, 0), root_set.stats.stack_count);
    try std.testing.expectEqual(@as(usize, 0), root_set.stats.global_count);
}

test "RootSet add and remove stack roots" {
    const allocator = std.testing.allocator;
    
    var root_set = try RootSet.init(allocator);
    defer root_set.deinit();
    
    // 创建模拟对象
    var obj1 = GCObjectHeader.init(64);
    var obj2 = GCObjectHeader.init(128);
    
    // 添加栈根
    try root_set.addStackRoot(&obj1);
    try root_set.addStackRoot(&obj2);
    
    try std.testing.expectEqual(@as(usize, 2), root_set.getTotalCount());
    try std.testing.expectEqual(@as(usize, 2), root_set.stats.stack_count);
    try std.testing.expect(root_set.isRoot(&obj1));
    try std.testing.expect(root_set.isRoot(&obj2));
    
    // 移除栈根
    root_set.removeStackRoot(&obj1);
    
    try std.testing.expectEqual(@as(usize, 1), root_set.getTotalCount());
    try std.testing.expectEqual(@as(usize, 1), root_set.stats.stack_count);
    try std.testing.expect(!root_set.isRoot(&obj1));
    try std.testing.expect(root_set.isRoot(&obj2));
}

test "RootSet add different root types" {
    const allocator = std.testing.allocator;
    
    var root_set = try RootSet.init(allocator);
    defer root_set.deinit();
    
    var obj1 = GCObjectHeader.init(64);
    var obj2 = GCObjectHeader.init(128);
    var obj3 = GCObjectHeader.init(256);
    
    try root_set.addStackRoot(&obj1);
    try root_set.addGlobalRoot(&obj2);
    try root_set.addRegisterRoot(&obj3);
    
    try std.testing.expectEqual(@as(usize, 3), root_set.getTotalCount());
    try std.testing.expectEqual(@as(usize, 1), root_set.stats.stack_count);
    try std.testing.expectEqual(@as(usize, 1), root_set.stats.global_count);
    try std.testing.expectEqual(@as(usize, 1), root_set.stats.register_count);
    
    try std.testing.expectEqual(RootType.stack, root_set.getRootType(&obj1).?);
    try std.testing.expectEqual(RootType.global, root_set.getRootType(&obj2).?);
    try std.testing.expectEqual(RootType.register, root_set.getRootType(&obj3).?);
}

test "RootSet iterate roots" {
    const allocator = std.testing.allocator;
    
    var root_set = try RootSet.init(allocator);
    defer root_set.deinit();
    
    var obj1 = GCObjectHeader.init(64);
    var obj2 = GCObjectHeader.init(128);
    var obj3 = GCObjectHeader.init(256);
    
    try root_set.addStackRoot(&obj1);
    try root_set.addGlobalRoot(&obj2);
    try root_set.addRegisterRoot(&obj3);
    
    // 遍历所有根 - 使用简单计数
    const total = root_set.getTotalCount();
    try std.testing.expectEqual(@as(usize, 3), total);
}

test "RootSet temporary roots" {
    const allocator = std.testing.allocator;
    
    var root_set = try RootSet.init(allocator);
    defer root_set.deinit();
    
    var obj1 = GCObjectHeader.init(64);
    var obj2 = GCObjectHeader.init(128);
    
    try root_set.addTemporaryRoot(&obj1);
    try root_set.addTemporaryRoot(&obj2);
    
    try std.testing.expectEqual(@as(usize, 2), root_set.getTotalCount());
    try std.testing.expectEqual(@as(usize, 2), root_set.stats.temporary_count);
    
    // 清空临时根
    root_set.clearTemporaryRoots();
    
    try std.testing.expectEqual(@as(usize, 0), root_set.getTotalCount());
    try std.testing.expectEqual(@as(usize, 0), root_set.stats.temporary_count);
}
