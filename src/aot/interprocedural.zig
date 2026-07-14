const std = @import("std");
const Allocator = std.mem.Allocator;
const CallGraph = @import("call_graph.zig").CallGraph;
const FunctionNode = @import("call_graph.zig").FunctionNode;
const ControlFlowGraph = @import("data_flow.zig").ControlFlowGraph;

/// 跨过程优化器
pub const InterproceduralOptimizer = struct {
    allocator: Allocator,
    call_graph: *CallGraph,
    /// 常量传播结果
    constant_values: std.StringHashMap(ConstantValue),
    /// 函数特化映射
    specializations: std.AutoHashMap(*FunctionNode, std.ArrayList(*SpecializedFunction)),

    pub fn init(allocator: Allocator, call_graph: *CallGraph) !InterproceduralOptimizer {
        return .{
            .allocator = allocator,
            .call_graph = call_graph,
            .constant_values = std.StringHashMap(ConstantValue).init(allocator),
            .specializations = std.AutoHashMap(*FunctionNode, std.ArrayList(*SpecializedFunction)).init(allocator),
        };
    }

    pub fn deinit(self: *InterproceduralOptimizer) void {
        self.constant_values.deinit();

        var it = self.specializations.valueIterator();
        while (it.next()) |list| {
            for (list.items) |spec| {
                spec.deinit();
                self.allocator.destroy(spec);
            }
            list.deinit(self.allocator);
        }
        self.specializations.deinit();
    }

    /// 执行跨过程常量传播
    pub fn constantPropagation(self: *InterproceduralOptimizer) !void {
        // 初始化工作列表
        var worklist = try std.ArrayList(*FunctionNode).initCapacity(self.allocator, 0);
        defer worklist.deinit(self.allocator);

        // 添加所有函数到工作列表
        var node_it = self.call_graph.nodes.valueIterator();
        while (node_it.next()) |node| {
            try worklist.append(self.allocator, node.*);
        }

        // 迭代传播常量
        while (worklist.items.len > 0) {
            const func = worklist.pop() orelse break;

            // 分析函数的常量参数
            const changed = try self.analyzeFunction(func);

            if (changed) {
                // 如果有变化，将调用者加入工作列表
                for (func.callers.items) |caller| {
                    try worklist.append(self.allocator, caller);
                }
            }
        }
    }

    /// 分析单个函数的常量传播
    fn analyzeFunction(self: *InterproceduralOptimizer, func: *FunctionNode) !bool {
        var changed = false;

        // 分析每个调用点
        for (func.callees.items) |callee| {
            // 检查参数是否为常量
            const args = try self.getCallArguments(func, callee);

            for (args, 0..) |arg, i| {
                if (arg.isConstant()) {
                    const param_name = try std.fmt.allocPrint(
                        self.allocator,
                        "{s}.param{d}",
                        .{ callee.name, i },
                    );
                    defer self.allocator.free(param_name);

                    const old_value = self.constant_values.get(param_name);
                    if (old_value == null or !old_value.?.equals(arg)) {
                        try self.constant_values.put(param_name, arg);
                        changed = true;
                    }
                }
            }
        }

        return changed;
    }

    /// 获取调用参数
    fn getCallArguments(self: *InterproceduralOptimizer, caller: *FunctionNode, callee: *FunctionNode) ![]ConstantValue {
        _ = self;
        _ = caller;
        _ = callee;
        // 简化实现：返回空数组
        return &[_]ConstantValue{};
    }

    /// 执行跨过程死代码消除
    pub fn deadCodeElimination(self: *InterproceduralOptimizer) !void {
        // 标记所有可达函数
        var reachable = std.AutoHashMap(*FunctionNode, void).init(self.allocator);
        defer reachable.deinit();

        // 从入口函数开始标记
        var node_it = self.call_graph.nodes.valueIterator();
        while (node_it.next()) |node| {
            if (node.*.callers.items.len == 0) {
                try self.markReachable(node.*, &reachable);
            }
        }

        // 移除不可达函数
        var to_remove = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer to_remove.deinit(self.allocator);

        var name_it = self.call_graph.nodes.keyIterator();
        while (name_it.next()) |name| {
            const node = self.call_graph.nodes.get(name.*).?;
            if (!reachable.contains(node)) {
                try to_remove.append(self.allocator, name.*);
            }
        }

        for (to_remove.items) |name| {
            const node = self.call_graph.nodes.get(name).?;
            node.deinit();
            self.allocator.destroy(node);
            _ = self.call_graph.nodes.remove(name);
        }
    }

    /// 标记可达函数
    fn markReachable(self: *InterproceduralOptimizer, func: *FunctionNode, reachable: *std.AutoHashMap(*FunctionNode, void)) !void {
        if (reachable.contains(func)) return;
        try reachable.put(func, {});

        for (func.callees.items) |callee| {
            try self.markReachable(callee, reachable);
        }
    }

    /// 执行函数特化
    pub fn functionSpecialization(self: *InterproceduralOptimizer) !void {
        var node_it = self.call_graph.nodes.valueIterator();
        while (node_it.next()) |node| {
            const func = node.*;

            // 收集此函数的所有调用点
            const call_sites = try self.collectCallSites(func);
            defer {
                for (call_sites) |site| {
                    self.allocator.destroy(site);
                }
                self.allocator.free(call_sites);
            }

            // 按参数模式分组
            var patterns = std.HashMap(ArgumentPattern, std.ArrayList(*CallSiteInfo), ArgumentPatternContext, std.hash_map.default_max_load_percentage).init(self.allocator);
            defer {
                var it = patterns.valueIterator();
                while (it.next()) |list| {
                    list.deinit(self.allocator);
                }
                patterns.deinit();
            }

            for (call_sites) |site| {
                const pattern = try self.extractPattern(site);
                const entry = try patterns.getOrPut(pattern);
                if (!entry.found_existing) {
                    entry.value_ptr.* = try std.ArrayList(*CallSiteInfo).initCapacity(self.allocator, 0);
                }
                try entry.value_ptr.append(self.allocator, site);
            }

            // 为频繁的模式创建特化版本
            var pattern_it = patterns.iterator();
            while (pattern_it.next()) |entry| {
                const pattern = entry.key_ptr.*;
                const sites = entry.value_ptr.*;

                // 如果调用次数 >= 10，创建特化版本
                if (sites.items.len >= 10) {
                    const specialized = try self.createSpecialization(func, pattern);

                    const spec_entry = try self.specializations.getOrPut(func);
                    if (!spec_entry.found_existing) {
                        spec_entry.value_ptr.* = try std.ArrayList(*SpecializedFunction).initCapacity(self.allocator, 0);
                    }
                    try spec_entry.value_ptr.append(self.allocator, specialized);
                }
            }
        }
    }

    /// 收集函数的所有调用点
    fn collectCallSites(self: *InterproceduralOptimizer, func: *FunctionNode) ![]const *CallSiteInfo {
        var sites = try std.ArrayList(*CallSiteInfo).initCapacity(self.allocator, 0);

        for (func.callers.items) |caller| {
            const site = try self.allocator.create(CallSiteInfo);
            site.* = .{
                .caller = caller,
                .callee = func,
                .arguments = &[_]ConstantValue{},
            };
            try sites.append(self.allocator, site);
        }

        return sites.toOwnedSlice(self.allocator);
    }

    /// 提取参数模式
    fn extractPattern(self: *InterproceduralOptimizer, site: *const CallSiteInfo) !ArgumentPattern {
        _ = self;
        _ = site;
        return ArgumentPattern{
            .constant_args = &[_]bool{},
            .type_args = &[_]TypePattern{},
        };
    }

    /// 创建函数特化版本
    fn createSpecialization(self: *InterproceduralOptimizer, func: *FunctionNode, pattern: ArgumentPattern) !*SpecializedFunction {
        const specialized = try self.allocator.create(SpecializedFunction);
        specialized.* = .{
            .allocator = self.allocator,
            .original = func,
            .pattern = pattern,
            .name = try std.fmt.allocPrint(
                self.allocator,
                "{s}_specialized_{d}",
                .{ func.name, @intFromPtr(specialized) },
            ),
        };
        return specialized;
    }

    /// 消除未使用的参数
    pub fn eliminateUnusedParameters(self: *InterproceduralOptimizer) !void {
        var node_it = self.call_graph.nodes.valueIterator();
        while (node_it.next()) |node| {
            const func = node.*;

            // 分析每个参数的使用情况
            const param_usage = try self.analyzeParameterUsage(func);
            defer self.allocator.free(param_usage);

            // 标记未使用的参数
            for (param_usage, 0..) |used, i| {
                if (!used) {
                    // 记录未使用的参数
                    _ = i;
                }
            }
        }
    }

    /// 分析参数使用情况
    fn analyzeParameterUsage(self: *InterproceduralOptimizer, func: *FunctionNode) ![]bool {
        // 简化实现：假设所有参数都被使用
        const param_count = func.signature.param_types.len;
        const usage = try self.allocator.alloc(bool, param_count);
        @memset(usage, true);
        return usage;
    }
};

/// 常量值
pub const ConstantValue = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    bool_val: bool,
    null_val,

    pub fn isConstant(self: ConstantValue) bool {
        _ = self;
        return true;
    }

    pub fn equals(self: ConstantValue, other: ConstantValue) bool {
        if (@as(std.meta.Tag(ConstantValue), self) != @as(std.meta.Tag(ConstantValue), other)) {
            return false;
        }

        return switch (self) {
            .int => |v| v == other.int,
            .float => |v| v == other.float,
            .string => |v| std.mem.eql(u8, v, other.string),
            .bool_val => |v| v == other.bool_val,
            .null_val => true,
        };
    }
};

/// 调用点信息
pub const CallSiteInfo = struct {
    caller: *FunctionNode,
    callee: *FunctionNode,
    arguments: []const ConstantValue,
};

/// 参数模式
pub const ArgumentPattern = struct {
    constant_args: []const bool,
    type_args: []const TypePattern,

    pub fn hash(self: ArgumentPattern) u64 {
        var hasher = std.hash.Wyhash.init(0);
        for (self.constant_args) |is_const| {
            hasher.update(std.mem.asBytes(&is_const));
        }
        for (self.type_args) |type_pat| {
            hasher.update(std.mem.asBytes(&type_pat));
        }
        return hasher.final();
    }

    pub fn eql(a: ArgumentPattern, b: ArgumentPattern) bool {
        if (a.constant_args.len != b.constant_args.len) return false;
        if (a.type_args.len != b.type_args.len) return false;

        for (a.constant_args, b.constant_args) |a_const, b_const| {
            if (a_const != b_const) return false;
        }

        for (a.type_args, b.type_args) |a_type, b_type| {
            if (a_type != b_type) return false;
        }

        return true;
    }
};

/// 类型模式
pub const TypePattern = enum {
    int,
    float,
    string,
    bool_type,
    array,
    object,
    mixed,
};

/// 特化函数
pub const SpecializedFunction = struct {
    allocator: Allocator,
    original: *FunctionNode,
    pattern: ArgumentPattern,
    name: []const u8,

    pub fn deinit(self: *SpecializedFunction) void {
        self.allocator.free(self.name);
    }
};

/// 参数信息
pub const ParameterInfo = struct {
    index: usize,
    is_used: bool,
    is_constant: bool,
    constant_value: ?ConstantValue,
};

/// ArgumentPattern 哈希上下文
const ArgumentPatternContext = struct {
    pub fn hash(_: ArgumentPatternContext, key: ArgumentPattern) u64 {
        return key.hash();
    }

    pub fn eql(_: ArgumentPatternContext, a: ArgumentPattern, b: ArgumentPattern) bool {
        return a.eql(b);
    }
};
