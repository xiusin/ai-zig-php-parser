const std = @import("std");
const Allocator = std.mem.Allocator;

/// 调用图 - 表示程序中所有函数的调用关系
pub const CallGraph = struct {
    allocator: Allocator,
    /// 函数节点映射表 (函数名 -> 节点)
    nodes: std.StringHashMap(*FunctionNode),
    /// 所有调用边
    edges: std.ArrayList(*CallEdge),
    /// 递归调用集合
    recursive_calls: std.AutoHashMap(*FunctionNode, void),
    
    pub fn init(allocator: Allocator) !CallGraph {
        return .{
            .allocator = allocator,
            .nodes = std.StringHashMap(*FunctionNode).init(allocator),
            .edges = try std.ArrayList(*CallEdge).initCapacity(allocator, 0),
            .recursive_calls = std.AutoHashMap(*FunctionNode, void).init(allocator),
        };
    }
    
    pub fn deinit(self: *CallGraph) void {
        var node_it = self.nodes.valueIterator();
        while (node_it.next()) |node| {
            node.*.deinit();
            self.allocator.destroy(node.*);
        }
        self.nodes.deinit();
        
        for (self.edges.items) |edge| {
            self.allocator.destroy(edge);
        }
        self.edges.deinit(self.allocator);
        self.recursive_calls.deinit();
    }
    
    /// 添加函数节点
    pub fn addFunction(self: *CallGraph, name: []const u8, signature: FunctionSignature) !*FunctionNode {
        const node = try self.allocator.create(FunctionNode);
        node.* = try FunctionNode.init(self.allocator, name, signature);
        try self.nodes.put(name, node);
        return node;
    }
    
    /// 添加调用边
    pub fn addCallEdge(self: *CallGraph, caller: *FunctionNode, callee: *FunctionNode, call_site: CallSite) !void {
        const edge = try self.allocator.create(CallEdge);
        edge.* = .{
            .caller = caller,
            .callee = callee,
            .call_site = call_site,
            .frequency = 0,
        };
        try self.edges.append(self.allocator, edge);
        try caller.callees.append(self.allocator, callee);
        try callee.callers.append(self.allocator, caller);
    }
    
    /// 检测递归调用
    pub fn detectRecursion(self: *CallGraph) !void {
        var visited = std.AutoHashMap(*FunctionNode, void).init(self.allocator);
        defer visited.deinit();
        
        var stack = std.AutoHashMap(*FunctionNode, void).init(self.allocator);
        defer stack.deinit();
        
        var node_it = self.nodes.valueIterator();
        while (node_it.next()) |node| {
            try self.dfsRecursion(node.*, &visited, &stack);
        }
    }
    
    fn dfsRecursion(
        self: *CallGraph,
        node: *FunctionNode,
        visited: *std.AutoHashMap(*FunctionNode, void),
        stack: *std.AutoHashMap(*FunctionNode, void),
    ) !void {
        if (visited.contains(node)) return;
        
        try visited.put(node, {});
        try stack.put(node, {});
        
        for (node.callees.items) |callee| {
            if (stack.contains(callee)) {
                // 检测到递归
                try self.recursive_calls.put(node, {});
                node.is_recursive = true;
            } else {
                try self.dfsRecursion(callee, visited, stack);
            }
        }
        
        _ = stack.remove(node);
    }
    
    /// 计算调用频率（基于 profile 数据）
    pub fn updateFrequencies(self: *CallGraph, profile: *const ProfileData) void {
        for (self.edges.items) |edge| {
            if (profile.call_counts.get(edge.call_site.location)) |count| {
                edge.frequency = count;
            }
        }
    }
    
    /// 识别关键路径（最频繁的调用链）
    pub fn findCriticalPaths(self: *CallGraph, allocator: Allocator) ![]CallPath {
        var paths = try std.ArrayList(CallPath).initCapacity(allocator, 0);
        
        // 找到所有入口函数（没有调用者的函数）
        var node_it = self.nodes.valueIterator();
        while (node_it.next()) |node| {
            if (node.*.callers.items.len == 0) {
                var path = try CallPath.init(allocator);
                try self.dfsPath(node.*, &path, &paths);
            }
        }
        
        // 按总频率排序
        std.mem.sort(CallPath, paths.items, {}, struct {
            fn lessThan(_: void, a: CallPath, b: CallPath) bool {
                return a.total_frequency > b.total_frequency;
            }
        }.lessThan);
        
        return paths.toOwnedSlice(allocator);
    }
    
    fn dfsPath(
        self: *CallGraph,
        node: *FunctionNode,
        current_path: *CallPath,
        all_paths: *std.ArrayList(CallPath),
    ) !void {
        try current_path.nodes.append(current_path.nodes.allocator, node);
        
        if (node.callees.items.len == 0) {
            // 叶子节点，保存路径
            try all_paths.append(all_paths.allocator, try current_path.clone());
        } else {
            for (node.callees.items) |callee| {
                try self.dfsPath(callee, current_path, all_paths);
            }
        }
        
        _ = current_path.nodes.pop();
    }
    
    /// 剪枝不可达函数
    /// 注意：需要显式指定入口函数，否则所有没有调用者的函数都会被视为入口
    pub fn pruneUnreachable(self: *CallGraph, entry_functions: []const []const u8) !void {
        var reachable = std.AutoHashMap(*FunctionNode, void).init(self.allocator);
        defer reachable.deinit();
        
        // 从指定的入口函数开始标记可达节点
        for (entry_functions) |entry_name| {
            if (self.nodes.get(entry_name)) |entry_node| {
                try self.markReachable(entry_node, &reachable);
            }
        }
        
        // 移除不可达节点
        var to_remove = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer to_remove.deinit(self.allocator);
        
        var name_it = self.nodes.keyIterator();
        while (name_it.next()) |name| {
            const node = self.nodes.get(name.*).?;
            if (!reachable.contains(node)) {
                try to_remove.append(self.allocator, name.*);
            }
        }
        
        for (to_remove.items) |name| {
            const node = self.nodes.get(name).?;
            node.deinit();
            self.allocator.destroy(node);
            _ = self.nodes.remove(name);
        }
    }
    
    fn markReachable(self: *CallGraph, node: *FunctionNode, reachable: *std.AutoHashMap(*FunctionNode, void)) !void {
        if (reachable.contains(node)) return;
        try reachable.put(node, {});
        
        for (node.callees.items) |callee| {
            try self.markReachable(callee, reachable);
        }
    }
};

/// 函数节点
pub const FunctionNode = struct {
    allocator: Allocator,
    name: []const u8,
    signature: FunctionSignature,
    /// 调用此函数的函数列表
    callers: std.ArrayList(*FunctionNode),
    /// 此函数调用的函数列表
    callees: std.ArrayList(*FunctionNode),
    /// 是否为递归函数
    is_recursive: bool,
    /// 函数大小（字节码数量）
    bytecode_size: usize,
    
    pub fn init(allocator: Allocator, name: []const u8, signature: FunctionSignature) !FunctionNode {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .signature = signature,
            .callers = try std.ArrayList(*FunctionNode).initCapacity(allocator, 0),
            .callees = try std.ArrayList(*FunctionNode).initCapacity(allocator, 0),
            .is_recursive = false,
            .bytecode_size = 0,
        };
    }
    
    pub fn deinit(self: *FunctionNode) void {
        self.allocator.free(self.name);
        self.callers.deinit(self.allocator);
        self.callees.deinit(self.allocator);
    }
};

/// 函数签名
pub const FunctionSignature = struct {
    param_types: []const TypeInfo,
    return_type: TypeInfo,
    is_variadic: bool,
};

/// 类型信息
pub const TypeInfo = union(enum) {
    int,
    float,
    string,
    bool,
    array: *const TypeInfo,
    object: []const u8, // 类名
    mixed,
    void,
};

/// 调用边
pub const CallEdge = struct {
    caller: *FunctionNode,
    callee: *FunctionNode,
    call_site: CallSite,
    frequency: u64,
    /// 去虚化后的目标（如果适用）
    devirtualized_target: ?*FunctionNode = null,
};

/// 调用点
pub const CallSite = struct {
    location: SourceLocation,
    call_type: CallType,
};

/// 调用类型
pub const CallType = enum {
    direct,      // 直接调用
    indirect,    // 间接调用（函数指针）
    virtual,     // 虚方法调用
    closure,     // 闭包调用
};

/// 源码位置
pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,
    
    pub fn hash(self: SourceLocation) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(self.file);
        hasher.update(std.mem.asBytes(&self.line));
        hasher.update(std.mem.asBytes(&self.column));
        return hasher.final();
    }
    
    pub fn eql(a: SourceLocation, b: SourceLocation) bool {
        return std.mem.eql(u8, a.file, b.file) and 
               a.line == b.line and 
               a.column == b.column;
    }
};

/// 调用路径
pub const CallPath = struct {
    nodes: std.ArrayList(*FunctionNode),
    total_frequency: u64,
    
    pub fn init(allocator: Allocator) !CallPath {
        return .{
            .nodes = try std.ArrayList(*FunctionNode).initCapacity(allocator, 0),
            .total_frequency = 0,
        };
    }
    
    pub fn deinit(self: *CallPath) void {
        self.nodes.deinit(self.nodes.allocator);
    }
    
    pub fn clone(self: *const CallPath) !CallPath {
        var new_path = try CallPath.init(self.nodes.allocator);
        try new_path.nodes.appendSlice(self.nodes.allocator, self.nodes.items);
        new_path.total_frequency = self.total_frequency;
        return new_path;
    }
};

/// Profile 数据
pub const ProfileData = struct {
    call_counts: std.HashMap(SourceLocation, u64, SourceLocationContext, std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: Allocator) ProfileData {
        return .{
            .call_counts = std.HashMap(SourceLocation, u64, SourceLocationContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *ProfileData) void {
        self.call_counts.deinit();
    }
};

const SourceLocationContext = struct {
    pub fn hash(_: SourceLocationContext, key: SourceLocation) u64 {
        return key.hash();
    }
    
    pub fn eql(_: SourceLocationContext, a: SourceLocation, b: SourceLocation) bool {
        return a.eql(b);
    }
};
