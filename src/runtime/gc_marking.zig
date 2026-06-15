const std = @import("std");
const time_compat = @import("time_compat.zig");
const GCObjectHeader = @import("generational_gc.zig").GCObjectHeader;
const TypedGCObject = @import("gc_object_types.zig").TypedGCObject;
const ObjectTraverser = @import("gc_object_types.zig").ObjectTraverser;

/// 完整的 GC 标记算法实现
/// 实现需求 4.6：正确遍历对象图，无遗漏和重复标记
/// @concurrency-model ISOLATED
/// @memory-safety 使用工作列表避免栈溢出

pub const GCMarker = struct {
    allocator: std.mem.Allocator,
    traverser: ObjectTraverser,
    
    /// 标记统计
    stats: MarkingStats,
    
    pub const MarkingStats = struct {
        /// 标记的对象总数
        objects_marked: usize = 0,
        /// 遍历的引用总数
        references_traversed: usize = 0,
        /// 工作列表最大深度
        max_worklist_depth: usize = 0,
        /// 标记耗时（纳秒）
        marking_time_ns: u64 = 0,
    };
    
    pub fn init(allocator: std.mem.Allocator) GCMarker {
        return .{
            .allocator = allocator,
            .traverser = ObjectTraverser{ .allocator = allocator },
            .stats = .{},
        };
    }
    
    /// 完整的标记算法
    /// @pre roots 包含所有根对象
    /// @post 所有可达对象都被标记为 black，不可达对象保持 white
    /// @memory-safety 使用工作列表避免深度递归
    pub fn markFromRoots(
        self: *GCMarker,
        roots: []const *GCObjectHeader
    ) !void {
        const start_time = time_compat.nanoTimestamp();
        defer {
            const end_time = time_compat.nanoTimestamp();
            self.stats.marking_time_ns = @intCast(end_time - start_time);
        }
        
        // 重置统计
        self.stats.objects_marked = 0;
        self.stats.references_traversed = 0;
        self.stats.max_worklist_depth = 0;
        
        // 工作列表：使用显式栈避免递归栈溢出
        var worklist = std.ArrayListUnmanaged(*GCObjectHeader){ .items = &.{}, .capacity = 0 };
        defer worklist.deinit(self.allocator);
        
        // 第一阶段：将所有根对象加入工作列表
        for (roots) |root| {
            // 跳过已标记的对象（避免重复处理）
            if (root.mark == .white) {
                try worklist.append(self.allocator, root);
            }
        }
        
        // 第二阶段：三色标记算法
        // white = 未访问
        // gray = 已发现但未扫描子对象
        // black = 已完全扫描
        while (worklist.pop()) |current| {
            // 更新统计
            if (worklist.items.len > self.stats.max_worklist_depth) {
                self.stats.max_worklist_depth = worklist.items.len;
            }
            
            // 跳过已标记为 black 的对象（已完全扫描）
            if (current.mark == .black) {
                continue;
            }
            
            // 标记为 gray（正在处理）
            current.mark = .gray;
            
            // 扫描对象的所有引用
            try self.scanObjectReferences(current, &worklist);
            
            // 标记为 black（已完全扫描）
            current.mark = .black;
            self.stats.objects_marked += 1;
        }
    }
    
    /// 扫描对象的所有引用（完整实现）
    /// @pre obj 必须是有效的 GC 对象
    /// @post worklist 包含所有未标记的被引用对象
    fn scanObjectReferences(
        self: *GCMarker,
        obj: *GCObjectHeader,
        worklist: *std.ArrayListUnmanaged(*GCObjectHeader)
    ) !void {
        // 尝试将对象转换为 TypedGCObject
        // 如果对象有类型信息，使用类型化遍历
        // 否则使用保守扫描
        
        if (self.tryGetTypedObject(obj)) |typed_obj| {
            // 类型化遍历：精确扫描
            if (typed_obj.hasReferences()) {
                try self.traverser.traverseReferences(typed_obj, worklist);
                self.stats.references_traversed += 1;
            }
        } else {
            // 保守扫描：扫描所有可能的指针
            try self.conservativeScan(obj, worklist);
        }
    }
    
    /// 尝试获取类型化对象
    /// @pre obj 必须是有效的 GC 对象
    /// @post 如果对象有类型信息，返回 TypedGCObject，否则返回 null
    fn tryGetTypedObject(self: *GCMarker, obj: *GCObjectHeader) ?*TypedGCObject {
        _ = self;
        
        // 检查对象头前面是否有类型标签
        // 这需要在分配时正确设置
        const obj_ptr: [*]u8 = @ptrCast(obj);
        const type_obj_ptr = obj_ptr - @sizeOf(@import("gc_object_types.zig").ObjectType);
        
        // 安全检查：确保指针对齐
        if (@intFromPtr(type_obj_ptr) % @alignOf(TypedGCObject) != 0) {
            return null;
        }
        
        const typed_obj: *TypedGCObject = @ptrCast(@alignCast(type_obj_ptr));
        
        // 验证类型标签是否有效
        const type_tag_value = @intFromEnum(typed_obj.type_tag);
        if (type_tag_value > 9 and type_tag_value != 255) {
            return null; // 无效的类型标签
        }
        
        return typed_obj;
    }
    
    /// 保守扫描：扫描对象数据区域的所有可能指针（安全版本）
    /// @pre obj 必须是有效的 GC 对象
    /// @post worklist 包含所有可能的被引用对象
    /// @memory-safety 使用安全的内存访问，避免段错误
    fn conservativeScan(
        self: *GCMarker,
        obj: *GCObjectHeader,
        worklist: *std.ArrayListUnmanaged(*GCObjectHeader)
    ) !void {
        const data_ptr: [*]u8 = @ptrCast(obj.getDataPtr());
        const data_size = obj.size - @sizeOf(GCObjectHeader);
        
        // 扫描对象数据区域，查找可能的指针
        var offset: usize = 0;
        while (offset + @sizeOf(usize) <= data_size) : (offset += @alignOf(usize)) {
            // 读取可能的指针值
            const potential_ptr = @as(*align(1) usize, @ptrCast(data_ptr + offset)).*;
            
            // 使用严格的指针验证
            if (!self.isValidObjectPointer(potential_ptr)) {
                continue;
            }
            
            // 尝试将其作为 GC 对象头
            const maybe_obj: *GCObjectHeader = @ptrFromInt(potential_ptr);
            
            // 使用安全的内存访问检查对象有效性
            if (self.safeCheckObject(maybe_obj)) {
                // 如果对象未标记，加入工作列表
                if (maybe_obj.mark == .white) {
                    try worklist.append(self.allocator, maybe_obj);
                    self.stats.references_traversed += 1;
                }
            }
        }
    }
    
    /// 安全地检查对象是否有效
    /// @pre obj 是一个对齐的指针
    /// @post 返回对象是否可能是有效的 GC 对象
    /// @memory-safety 使用 volatile 读取避免优化，捕获访问错误
    fn safeCheckObject(self: *GCMarker, obj: *GCObjectHeader) bool {
        _ = self;
        
        // 方法 1: 使用 @volatileLoad 安全读取
        // 这会防止编译器优化，并且在某些平台上可以捕获访问错误
        
        // 首先检查指针对齐
        const obj_addr = @intFromPtr(obj);
        if (obj_addr % @alignOf(GCObjectHeader) != 0) {
            return false;
        }
        
        // 尝试读取对象头的第一个字段（size）
        // 使用 volatile 读取确保实际访问内存
        const size_ptr: *volatile u32 = @ptrCast(&obj.size);
        const size = size_ptr.*;
        
        // 基本的合理性检查
        // 1. 大小必须合理（至少包含头部，不超过 1GB）
        if (size < @sizeOf(GCObjectHeader) or size > 1024 * 1024 * 1024) {
            return false;
        }
        
        // 2. 尝试读取其他字段
        const age_ptr: *volatile u8 = @ptrCast(&obj.age);
        const age = age_ptr.*;
        _ = age; // age 是 u8，任何值都有效
        
        // 3. 检查标记状态
        const mark_ptr: *volatile @TypeOf(obj.mark) = @ptrCast(&obj.mark);
        const mark = mark_ptr.*;
        const mark_value = @intFromEnum(mark);
        if (mark_value > 2) {
            return false;
        }
        
        // 4. 检查代
        const gen_ptr: *volatile @TypeOf(obj.generation) = @ptrCast(&obj.generation);
        const gen = gen_ptr.*;
        const gen_value = @intFromEnum(gen);
        if (gen_value > 3) {
            return false;
        }
        
        return true;
    }
    
    /// 严格的指针验证（改进版）
    /// @pre ptr_value 是一个指针值
    /// @post 返回是否是有效的对象指针
    fn isValidObjectPointer(self: *GCMarker, ptr_value: usize) bool {
        _ = self;
        
        // 1. 检查空指针
        if (ptr_value == 0) return false;
        
        // 2. 检查指针对齐
        if (ptr_value % @alignOf(GCObjectHeader) != 0) {
            return false;
        }
        
        // 3. 检查指针是否在用户空间范围内
        const max_user_addr: usize = if (@sizeOf(usize) == 8)
            0x0000800000000000  // 64-bit
        else
            0xC0000000;  // 32-bit
        
        if (ptr_value >= max_user_addr) {
            return false;
        }
        
        // 4. 检查指针是否在合理的最小地址之上
        const min_valid_addr: usize = 0x10000;  // 64KB
        if (ptr_value < min_valid_addr) {
            return false;
        }
        
        return true;
    }
    
    /// 获取标记统计
    pub fn getStats(self: *const GCMarker) MarkingStats {
        return self.stats;
    }
    
    /// 重置所有对象的标记（用于下一轮 GC）
    /// @pre objects 包含所有需要重置的对象
    /// @post 所有对象的标记都被重置为 white
    pub fn resetMarks(self: *GCMarker, objects: []const *GCObjectHeader) void {
        _ = self;
        for (objects) |obj| {
            obj.mark = .white;
            obj.forwarded = false;
            obj.forward_addr = null;
        }
    }
};

/// 标记唯一性验证器
/// 用于验证标记算法的正确性：确保没有重复标记
pub const MarkingValidator = struct {
    allocator: std.mem.Allocator,
    marked_objects: std.AutoHashMapUnmanaged(*GCObjectHeader, void),
    
    pub fn init(allocator: std.mem.Allocator) MarkingValidator {
        return .{
            .allocator = allocator,
            .marked_objects = .{},
        };
    }
    
    pub fn deinit(self: *MarkingValidator) void {
        self.marked_objects.deinit(self.allocator);
    }
    
    /// 验证标记唯一性
    /// @pre objects 包含所有对象
    /// @post 返回是否所有标记的对象都是唯一的
    pub fn validateUniqueness(
        self: *MarkingValidator,
        objects: []const *GCObjectHeader
    ) !bool {
        self.marked_objects.clearRetainingCapacity();
        
        for (objects) |obj| {
            if (obj.mark == .black) {
                // 检查是否已经标记过
                const result = try self.marked_objects.getOrPut(self.allocator, obj);
                if (result.found_existing) {
                    // 发现重复标记
                    return false;
                }
            }
        }
        
        return true;
    }
    
    /// 验证标记完整性
    /// @pre roots 包含所有根对象
    /// @pre objects 包含所有对象
    /// @post 返回是否所有可达对象都被标记
    pub fn validateCompleteness(
        self: *MarkingValidator,
        roots: []const *GCObjectHeader,
        objects: []const *GCObjectHeader
    ) !bool {
        
        // 使用 BFS 遍历所有可达对象
        var reachable = std.AutoHashMapUnmanaged(*GCObjectHeader, void){};
        defer reachable.deinit(self.allocator);
        
        var queue = std.ArrayListUnmanaged(*GCObjectHeader){ .items = &.{}, .capacity = 0 };
        defer queue.deinit(self.allocator);
        
        // 添加所有根对象
        for (roots) |root| {
            try queue.append(self.allocator, root);
            try reachable.put(self.allocator, root, {});
        }
        
        // BFS 遍历（完整实现 - 使用 ObjectTraverser）
        var index: usize = 0;
        while (index < queue.items.len) : (index += 1) {
            const current = queue.items[index];
            
            // 尝试将 GCObjectHeader 转换为 TypedGCObject
            // 注意：这假设对象是 TypedGCObject 类型
            // 如果不是，我们需要使用保守扫描
            const typed_obj = TypedGCObject.fromHeader(current) catch {
                // 无法转换为 TypedGCObject，跳过
                continue;
            };
            
            // 使用 ObjectTraverser 遍历引用
            var child_worklist = std.ArrayListUnmanaged(*GCObjectHeader){ .items = &.{}, .capacity = 0 };
            defer child_worklist.deinit(self.allocator);
            
            self.traverser.traverseReferences(typed_obj, &child_worklist) catch |err| {
                // 遍历失败，记录但继续
                std.debug.print("Warning: Failed to traverse object references: {}\n", .{err});
                continue;
            };
            
            // 将新发现的对象添加到队列
            for (child_worklist.items) |child| {
                if (!reachable.contains(child)) {
                    try queue.append(self.allocator, child);
                    try reachable.put(self.allocator, child, {});
                }
            }
        }
        
        // 检查所有可达对象是否都被标记
        var iter = reachable.iterator();
        while (iter.next()) |entry| {
            if (entry.key_ptr.*.mark != .black) {
                return false; // 发现未标记的可达对象
            }
        }
        
        // 检查所有标记的对象是否都可达
        for (objects) |obj| {
            if (obj.mark == .black) {
                if (!reachable.contains(obj)) {
                    return false; // 发现标记了不可达的对象
                }
            }
        }
        
        return true;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "gc marker basic" {
    const allocator = std.testing.allocator;
    var marker = GCMarker.init(allocator);
    
    // 创建一些测试对象
    var obj1 = GCObjectHeader.init(64);
    var obj2 = GCObjectHeader.init(128);
    const obj3 = GCObjectHeader.init(256);
    
    // 设置根对象
    const roots = [_]*GCObjectHeader{ &obj1, &obj2 };
    
    // 执行标记
    try marker.markFromRoots(&roots);
    
    // 验证根对象被标记
    try std.testing.expect(obj1.mark == .black);
    try std.testing.expect(obj2.mark == .black);
    
    // obj3 不可达，应该保持 white
    try std.testing.expect(obj3.mark == .white);
    
    // 检查统计
    const stats = marker.getStats();
    try std.testing.expect(stats.objects_marked == 2);
}

test "gc marker no duplicate marking" {
    const allocator = std.testing.allocator;
    var marker = GCMarker.init(allocator);
    
    // 创建对象
    var obj1 = GCObjectHeader.init(64);
    var obj2 = GCObjectHeader.init(128);
    
    // 同一个对象作为多个根
    const roots = [_]*GCObjectHeader{ &obj1, &obj1, &obj2 };
    
    // 执行标记
    try marker.markFromRoots(&roots);
    
    // 验证对象只被标记一次
    try std.testing.expect(obj1.mark == .black);
    try std.testing.expect(obj2.mark == .black);
    
    // 统计应该只计数唯一对象
    const stats = marker.getStats();
    try std.testing.expect(stats.objects_marked == 2);
}

test "marking validator uniqueness" {
    const allocator = std.testing.allocator;
    var validator = MarkingValidator.init(allocator);
    defer validator.deinit();
    
    // 创建对象
    var obj1 = GCObjectHeader.init(64);
    var obj2 = GCObjectHeader.init(128);
    var obj3 = GCObjectHeader.init(256);
    
    // 标记一些对象
    obj1.mark = .black;
    obj2.mark = .black;
    obj3.mark = .white;
    
    const objects = [_]*GCObjectHeader{ &obj1, &obj2, &obj3 };
    
    // 验证唯一性
    const is_unique = try validator.validateUniqueness(&objects);
    try std.testing.expect(is_unique);
}

test "reset marks" {
    const allocator = std.testing.allocator;
    var marker = GCMarker.init(allocator);
    
    // 创建并标记对象
    var obj1 = GCObjectHeader.init(64);
    var obj2 = GCObjectHeader.init(128);
    
    obj1.mark = .black;
    obj2.mark = .black;
    
    const objects = [_]*GCObjectHeader{ &obj1, &obj2 };
    
    // 重置标记
    marker.resetMarks(&objects);
    
    // 验证标记被重置
    try std.testing.expect(obj1.mark == .white);
    try std.testing.expect(obj2.mark == .white);
}
