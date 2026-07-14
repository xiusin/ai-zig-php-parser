const std = @import("std");
const Allocator = std.mem.Allocator;
const CallGraph = @import("call_graph.zig").CallGraph;
const FunctionNode = @import("call_graph.zig").FunctionNode;

/// 去虚化优化器
pub const DevirtualizationOptimizer = struct {
    allocator: Allocator,
    call_graph: *CallGraph,
    /// 类层次结构
    class_hierarchy: ClassHierarchy,
    /// 虚方法表
    vtables: std.StringHashMap(VTable),
    /// 去虚化统计
    stats: DevirtualizationStats,

    pub fn init(allocator: Allocator, call_graph: *CallGraph) !DevirtualizationOptimizer {
        return .{
            .allocator = allocator,
            .call_graph = call_graph,
            .class_hierarchy = try ClassHierarchy.init(allocator),
            .vtables = std.StringHashMap(VTable).init(allocator),
            .stats = DevirtualizationStats{},
        };
    }

    pub fn deinit(self: *DevirtualizationOptimizer) void {
        self.class_hierarchy.deinit();

        var it = self.vtables.valueIterator();
        while (it.next()) |vtable| {
            vtable.deinit();
        }
        self.vtables.deinit();
    }

    /// 执行类层次分析（CHA）
    pub fn classHierarchyAnalysis(self: *DevirtualizationOptimizer) !void {
        // 构建类层次结构
        try self.buildClassHierarchy();

        // 构建虚方法表
        try self.buildVTables();

        // 分析虚方法调用
        try self.analyzeVirtualCalls();
    }

    /// 构建类层次结构
    fn buildClassHierarchy(self: *DevirtualizationOptimizer) !void {
        // 遍历所有函数，识别类方法
        var node_it = self.call_graph.nodes.valueIterator();
        while (node_it.next()) |node| {
            const func = node.*;

            // 解析函数名，提取类名和方法名
            if (self.parseMethodName(func.name)) |method_info| {
                // 添加类到层次结构
                try self.class_hierarchy.addClass(method_info.class_name);

                // 添加方法到类
                try self.class_hierarchy.addMethod(
                    method_info.class_name,
                    method_info.method_name,
                    func,
                );
            }
        }
    }

    /// 解析方法名
    fn parseMethodName(self: *DevirtualizationOptimizer, name: []const u8) ?MethodInfo {
        _ = self;
        // 简化实现：假设格式为 "ClassName::methodName"
        const sep_idx = std.mem.indexOf(u8, name, "::") orelse return null;

        return MethodInfo{
            .class_name = name[0..sep_idx],
            .method_name = name[sep_idx + 2 ..],
        };
    }

    /// 构建虚方法表
    fn buildVTables(self: *DevirtualizationOptimizer) !void {
        var class_it = self.class_hierarchy.classes.keyIterator();
        while (class_it.next()) |class_name| {
            const class_info = self.class_hierarchy.classes.get(class_name.*).?;

            var vtable = VTable.init(self.allocator);

            // 添加类的所有方法到 vtable
            var method_it = class_info.methods.keyIterator();
            while (method_it.next()) |method_name| {
                const func = class_info.methods.get(method_name.*).?;
                try vtable.entries.put(method_name.*, func);
            }

            // 如果有父类，继承父类的方法
            if (class_info.parent) |parent_name| {
                if (self.vtables.get(parent_name)) |parent_vtable| {
                    var parent_it = parent_vtable.entries.keyIterator();
                    while (parent_it.next()) |method_name| {
                        // 如果子类没有重写，使用父类方法
                        if (!vtable.entries.contains(method_name.*)) {
                            const parent_func = parent_vtable.entries.get(method_name.*).?;
                            try vtable.entries.put(method_name.*, parent_func);
                        }
                    }
                }
            }

            try self.vtables.put(class_name.*, vtable);
        }
    }

    /// 分析虚方法调用
    fn analyzeVirtualCalls(self: *DevirtualizationOptimizer) !void {
        // 遍历所有调用边，识别虚方法调用
        for (self.call_graph.edges.items) |edge| {
            if (edge.call_site.call_type == .virtual) {
                self.stats.total_virtual_calls += 1;

                // 尝试去虚化
                const targets = try self.findPossibleTargets(edge);

                if (targets.len == 1) {
                    // 只有一个目标，可以去虚化
                    edge.devirtualized_target = targets[0];
                    self.stats.devirtualized_calls += 1;
                } else if (targets.len <= 3) {
                    // 少量目标，可以生成类型检查
                    self.stats.polymorphic_calls += 1;
                }

                self.allocator.free(targets);
            }
        }
    }

    /// 查找可能的调用目标
    fn findPossibleTargets(self: *DevirtualizationOptimizer, edge: *@import("call_graph.zig").CallEdge) ![]const *FunctionNode {
        var targets = try std.ArrayList(*FunctionNode).initCapacity(self.allocator, 0);

        // 解析被调用的方法名
        if (self.parseMethodName(edge.callee.name)) |method_info| {
            // 查找所有可能实现此方法的类
            var class_it = self.class_hierarchy.classes.keyIterator();
            while (class_it.next()) |class_name| {
                const class_info = self.class_hierarchy.classes.get(class_name.*).?;

                // 检查是否是目标类或其子类
                if (std.mem.eql(u8, class_name.*, method_info.class_name) or
                    try self.class_hierarchy.isSubclass(class_name.*, method_info.class_name))
                {
                    if (class_info.methods.get(method_info.method_name)) |func| {
                        try targets.append(self.allocator, func);
                    }
                }
            }
        }

        return targets.toOwnedSlice(self.allocator);
    }

    /// 执行快速类型分析（RTA）
    pub fn rapidTypeAnalysis(self: *DevirtualizationOptimizer) !void {
        // 收集所有实例化的类
        var instantiated = std.StringHashMap(void).init(self.allocator);
        defer instantiated.deinit();

        // 遍历所有函数，查找对象创建
        var node_it = self.call_graph.nodes.valueIterator();
        while (node_it.next()) |node| {
            const func = node.*;

            // 简化实现：假设构造函数名为 "ClassName::__construct"
            if (std.mem.endsWith(u8, func.name, "::__construct")) {
                if (self.parseMethodName(func.name)) |method_info| {
                    try instantiated.put(method_info.class_name, {});
                }
            }
        }

        // 精确化虚方法调用目标
        for (self.call_graph.edges.items) |edge| {
            if (edge.call_site.call_type == .virtual and edge.devirtualized_target == null) {
                // 只考虑实例化的类
                const targets = try self.findPossibleTargetsRTA(edge, &instantiated);

                if (targets.len == 1) {
                    edge.devirtualized_target = targets[0];
                    self.stats.devirtualized_calls += 1;
                }

                self.allocator.free(targets);
            }
        }
    }

    /// 查找可能的调用目标（RTA）
    fn findPossibleTargetsRTA(
        self: *DevirtualizationOptimizer,
        edge: *@import("call_graph.zig").CallEdge,
        instantiated: *const std.StringHashMap(void),
    ) ![]const *FunctionNode {
        var targets = try std.ArrayList(*FunctionNode).initCapacity(self.allocator, 0);

        if (self.parseMethodName(edge.callee.name)) |method_info| {
            var class_it = instantiated.keyIterator();
            while (class_it.next()) |class_name| {
                // 只考虑实例化的类
                if (std.mem.eql(u8, class_name.*, method_info.class_name) or
                    try self.class_hierarchy.isSubclass(class_name.*, method_info.class_name))
                {
                    if (self.class_hierarchy.classes.get(class_name.*)) |class_info| {
                        if (class_info.methods.get(method_info.method_name)) |func| {
                            try targets.append(self.allocator, func);
                        }
                    }
                }
            }
        }

        return targets.toOwnedSlice(self.allocator);
    }

    /// 生成去虚化代码
    pub fn generateDevirtualizedCode(self: *DevirtualizationOptimizer) !void {
        for (self.call_graph.edges.items) |edge| {
            if (edge.devirtualized_target) |target| {
                // 替换虚调用为直接调用
                edge.callee = target;
                edge.call_site.call_type = .direct;
            }
        }
    }

    /// 获取去虚化率
    pub fn getDevirtualizationRate(self: *const DevirtualizationOptimizer) f64 {
        if (self.stats.total_virtual_calls == 0) return 0.0;
        return @as(f64, @floatFromInt(self.stats.devirtualized_calls)) /
            @as(f64, @floatFromInt(self.stats.total_virtual_calls));
    }
};

/// 类层次结构
pub const ClassHierarchy = struct {
    allocator: Allocator,
    /// 所有类
    classes: std.StringHashMap(ClassInfo),

    pub fn init(allocator: Allocator) !ClassHierarchy {
        return .{
            .allocator = allocator,
            .classes = std.StringHashMap(ClassInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ClassHierarchy) void {
        var it = self.classes.valueIterator();
        while (it.next()) |class_info| {
            class_info.deinit();
        }
        self.classes.deinit();
    }

    /// 添加类
    pub fn addClass(self: *ClassHierarchy, name: []const u8) !void {
        if (self.classes.contains(name)) return;

        const class_info = try ClassInfo.init(self.allocator, name);
        try self.classes.put(name, class_info);
    }

    /// 添加方法到类
    pub fn addMethod(self: *ClassHierarchy, class_name: []const u8, method_name: []const u8, func: *FunctionNode) !void {
        const entry = try self.classes.getOrPut(class_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = try ClassInfo.init(self.allocator, class_name);
        }

        try entry.value_ptr.methods.put(method_name, func);
    }

    /// 设置父类
    pub fn setParent(self: *ClassHierarchy, class_name: []const u8, parent_name: []const u8) !void {
        if (self.classes.getPtr(class_name)) |class_info| {
            class_info.parent = parent_name;
        }
    }

    /// 检查是否为子类
    pub fn isSubclass(self: *const ClassHierarchy, class_name: []const u8, parent_name: []const u8) !bool {
        var current = class_name;

        while (self.classes.get(current)) |class_info| {
            if (class_info.parent) |p| {
                if (std.mem.eql(u8, p, parent_name)) return true;
                current = p;
            } else {
                break;
            }
        }

        return false;
    }
};

/// 类信息
pub const ClassInfo = struct {
    allocator: Allocator,
    name: []const u8,
    parent: ?[]const u8,
    methods: std.StringHashMap(*FunctionNode),

    pub fn init(allocator: Allocator, name: []const u8) !ClassInfo {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .parent = null,
            .methods = std.StringHashMap(*FunctionNode).init(allocator),
        };
    }

    pub fn deinit(self: *ClassInfo) void {
        self.allocator.free(self.name);
        self.methods.deinit();
    }
};

/// 虚方法表
pub const VTable = struct {
    allocator: Allocator,
    entries: std.StringHashMap(*FunctionNode),

    pub fn init(allocator: Allocator) VTable {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(*FunctionNode).init(allocator),
        };
    }

    pub fn deinit(self: *VTable) void {
        self.entries.deinit();
    }
};

/// 方法信息
pub const MethodInfo = struct {
    class_name: []const u8,
    method_name: []const u8,
};

/// 去虚化统计
pub const DevirtualizationStats = struct {
    total_virtual_calls: usize = 0,
    devirtualized_calls: usize = 0,
    polymorphic_calls: usize = 0,
};
