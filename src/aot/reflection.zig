const std = @import("std");
const Allocator = std.mem.Allocator;
const call_graph = @import("call_graph.zig");
const CallGraph = call_graph.CallGraph;

/// 编译时反射分析器
pub const CompileTimeReflection = struct {
    allocator: Allocator,

    /// 类元数据表
    class_metadata: std.StringHashMap(ClassMetadata),
    /// 方法元数据表
    method_metadata: std.StringHashMap(MethodMetadata),
    /// 属性元数据表
    property_metadata: std.StringHashMap(PropertyMetadata),
    /// 类层次结构
    class_hierarchy: ClassHierarchy,

    pub fn init(allocator: Allocator) !CompileTimeReflection {
        return .{
            .allocator = allocator,
            .class_metadata = std.StringHashMap(ClassMetadata).init(allocator),
            .method_metadata = std.StringHashMap(MethodMetadata).init(allocator),
            .property_metadata = std.StringHashMap(PropertyMetadata).init(allocator),
            .class_hierarchy = try ClassHierarchy.init(allocator),
        };
    }

    pub fn deinit(self: *CompileTimeReflection) void {
        var class_it = self.class_metadata.valueIterator();
        while (class_it.next()) |metadata| {
            metadata.deinit(self.allocator);
        }
        self.class_metadata.deinit();

        // 释放方法元数据的 key
        var method_key_it = self.method_metadata.keyIterator();
        while (method_key_it.next()) |key| {
            self.allocator.free(key.*);
        }
        var method_it = self.method_metadata.valueIterator();
        while (method_it.next()) |metadata| {
            metadata.deinit(self.allocator);
        }
        self.method_metadata.deinit();

        // 释放属性元数据的 key
        var property_key_it = self.property_metadata.keyIterator();
        while (property_key_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.property_metadata.deinit();

        self.class_hierarchy.deinit();
    }

    /// 收集类元数据
    pub fn collectClassMetadata(self: *CompileTimeReflection, class_name: []const u8, parent: ?[]const u8) !void {
        const metadata = ClassMetadata{
            .name = class_name,
            .parent = parent,
            .interfaces = try std.ArrayList([]const u8).initCapacity(self.allocator, 0),
            .methods = try std.ArrayList(MethodInfo).initCapacity(self.allocator, 0),
            .properties = try std.ArrayList(PropertyInfo).initCapacity(self.allocator, 0),
            .is_final = false,
            .is_abstract = false,
        };

        try self.class_metadata.put(class_name, metadata);
        try self.class_hierarchy.addClass(class_name, parent);
    }

    /// 收集方法元数据
    pub fn collectMethodMetadata(self: *CompileTimeReflection, class_name: []const u8, method_name: []const u8) !void {
        const metadata = MethodMetadata{
            .class_name = class_name,
            .method_name = method_name,
            .parameters = try std.ArrayList(ParameterInfo).initCapacity(self.allocator, 0),
            .is_static = false,
            .is_final = false,
            .is_abstract = false,
        };

        const key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
        try self.method_metadata.put(key, metadata);
    }

    /// 收集属性元数据
    pub fn collectPropertyMetadata(self: *CompileTimeReflection, class_name: []const u8, property_name: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, property_name });
        try self.property_metadata.put(key, .{
            .class_name = class_name,
            .property_name = property_name,
            .is_static = false,
        });
    }

    /// 优化虚方法调用
    pub fn optimizeVirtualCalls(self: *CompileTimeReflection, graph: *CallGraph) !usize {
        var optimized: usize = 0;

        for (graph.edges.items) |edge| {
            if (edge.call_site.call_type == .virtual) {
                // 查找可能的调用目标
                const targets = try self.class_hierarchy.findPossibleTargets(
                    edge.callee.name,
                );

                if (targets.len == 1) {
                    // 只有一个目标 - 去虚化
                    optimized += 1;
                }
            }
        }

        return optimized;
    }

    /// 获取类元数据
    pub fn getClassMetadata(self: *const CompileTimeReflection, class_name: []const u8) ?ClassMetadata {
        return self.class_metadata.get(class_name);
    }
};

/// 类元数据
pub const ClassMetadata = struct {
    name: []const u8,
    parent: ?[]const u8,
    interfaces: std.ArrayList([]const u8),
    methods: std.ArrayList(MethodInfo),
    properties: std.ArrayList(PropertyInfo),
    is_final: bool,
    is_abstract: bool,

    pub fn deinit(self: *ClassMetadata, allocator: Allocator) void {
        self.interfaces.deinit(allocator);
        self.methods.deinit(allocator);
        self.properties.deinit(allocator);
    }
};

/// 方法信息
pub const MethodInfo = struct {
    name: []const u8,
    is_static: bool,
    is_final: bool,
    is_abstract: bool,
};

/// 属性信息
pub const PropertyInfo = struct {
    name: []const u8,
    is_static: bool,
};

/// 方法元数据
pub const MethodMetadata = struct {
    class_name: []const u8,
    method_name: []const u8,
    parameters: std.ArrayList(ParameterInfo),
    is_static: bool,
    is_final: bool,
    is_abstract: bool,

    pub fn deinit(self: *MethodMetadata, allocator: Allocator) void {
        self.parameters.deinit(allocator);
    }
};

/// 参数信息
pub const ParameterInfo = struct {
    name: []const u8,
    is_optional: bool,
};

/// 属性元数据
pub const PropertyMetadata = struct {
    class_name: []const u8,
    property_name: []const u8,
    is_static: bool,
};

/// 类层次结构
pub const ClassHierarchy = struct {
    allocator: Allocator,
    /// 类继承关系（子类 -> 父类）
    inheritance: std.StringHashMap([]const u8),
    /// 类的所有子类
    children: std.StringHashMap(std.ArrayList([]const u8)),

    pub fn init(allocator: Allocator) !ClassHierarchy {
        return .{
            .allocator = allocator,
            .inheritance = std.StringHashMap([]const u8).init(allocator),
            .children = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
        };
    }

    pub fn deinit(self: *ClassHierarchy) void {
        self.inheritance.deinit();

        var it = self.children.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }
        self.children.deinit();
    }

    /// 添加类
    pub fn addClass(self: *ClassHierarchy, class_name: []const u8, parent: ?[]const u8) !void {
        if (parent) |p| {
            try self.inheritance.put(class_name, p);

            const entry = try self.children.getOrPut(p);
            if (!entry.found_existing) {
                entry.value_ptr.* = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
            }
            try entry.value_ptr.append(self.allocator, class_name);
        }
    }

    /// 查找可能的调用目标
    pub fn findPossibleTargets(self: *ClassHierarchy, method_name: []const u8) ![][]const u8 {
        _ = method_name;
        // 简化：返回空列表
        const targets = try self.allocator.alloc([]const u8, 0);
        return targets;
    }

    /// 获取父类
    pub fn getParent(self: *const ClassHierarchy, class_name: []const u8) ?[]const u8 {
        return self.inheritance.get(class_name);
    }

    /// 获取所有子类
    pub fn getChildren(self: *const ClassHierarchy, class_name: []const u8) ?std.ArrayList([]const u8) {
        return self.children.get(class_name);
    }
};

/// 运行时反射缓存
pub const ReflectionCache = struct {
    allocator: Allocator,
    /// 类缓存
    class_cache: std.StringHashMap(*ReflectionClass),
    /// 缓存命中统计
    hit_count: std.atomic.Value(u64),
    miss_count: std.atomic.Value(u64),

    pub fn init(allocator: Allocator) ReflectionCache {
        return .{
            .allocator = allocator,
            .class_cache = std.StringHashMap(*ReflectionClass).init(allocator),
            .hit_count = std.atomic.Value(u64).init(0),
            .miss_count = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *ReflectionCache) void {
        var it = self.class_cache.valueIterator();
        while (it.next()) |class| {
            self.allocator.destroy(class.*);
        }
        self.class_cache.deinit();
    }

    /// 获取类反射对象
    pub fn getClass(self: *ReflectionCache, name: []const u8, metadata: *const ClassMetadata) !*ReflectionClass {
        if (self.class_cache.get(name)) |cached| {
            _ = self.hit_count.fetchAdd(1, .monotonic);
            return cached;
        }

        _ = self.miss_count.fetchAdd(1, .monotonic);

        const class = try self.allocator.create(ReflectionClass);
        class.* = .{
            .name = name,
            .metadata = metadata,
        };

        try self.class_cache.put(name, class);
        return class;
    }

    /// 获取缓存命中率
    pub fn hitRate(self: *const ReflectionCache) f64 {
        const hits = self.hit_count.load(.monotonic);
        const misses = self.miss_count.load(.monotonic);
        const total = hits + misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(total));
    }
};

/// 运行时反射类
pub const ReflectionClass = struct {
    name: []const u8,
    metadata: *const ClassMetadata,

    /// 获取类名
    pub fn getName(self: *const ReflectionClass) []const u8 {
        return self.name;
    }

    /// 获取父类名
    pub fn getParentName(self: *const ReflectionClass) ?[]const u8 {
        return self.metadata.parent;
    }

    /// 获取方法数量
    pub fn getMethodCount(self: *const ReflectionClass) usize {
        return self.metadata.methods.items.len;
    }

    /// 获取属性数量
    pub fn getPropertyCount(self: *const ReflectionClass) usize {
        return self.metadata.properties.items.len;
    }
};
