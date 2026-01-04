const std = @import("std");
const ast = @import("ast.zig");
const root = @import("root.zig");
const PHPContext = root.PHPContext;

/// 逃逸状态枚举
/// 描述对象在程序执行过程中的逃逸程度
pub const EscapeState = enum(u8) {
    /// 不逃逸: 对象仅在当前函数内使用，可以栈分配
    NoEscape = 0,

    /// 参数逃逸: 对象通过参数传递但不被存储，调用者可决定分配位置
    ArgEscape = 1,

    /// 全局逃逸: 对象被存储到堆、全局变量或通过返回值逃逸，必须堆分配
    GlobalEscape = 2,

    /// 未知: 分析未完成或无法确定
    Unknown = 3,

    /// 合并两个逃逸状态，取更高的逃逸级别
    pub fn merge(self: EscapeState, other: EscapeState) EscapeState {
        return @enumFromInt(@max(@intFromEnum(self), @intFromEnum(other)));
    }

    /// 检查是否可以栈分配
    pub fn canStackAllocate(self: EscapeState) bool {
        return self == .NoEscape;
    }

    /// 检查是否可以标量替换
    pub fn canScalarReplace(self: EscapeState) bool {
        return self == .NoEscape;
    }
};

/// 逃逸原因
pub const EscapeReason = enum {
    /// 通过return返回
    returned,
    /// 存储到堆对象
    stored_to_heap,
    /// 存储到全局变量
    stored_to_global,
    /// 传递给未分析的函数
    passed_to_unknown,
    /// 被闭包捕获
    captured_by_closure,
    /// 作为异常抛出
    thrown_as_exception,
    /// 存储到数组
    stored_to_array,
    /// 通过引用传递
    passed_by_reference,
};

/// 源代码位置
pub const SourceLocation = struct {
    line: u32,
    column: u32,
    file: ?[]const u8 = null,
};

/// 逃逸点 - 记录对象逃逸的位置和原因
pub const EscapePoint = struct {
    location: SourceLocation,
    reason: EscapeReason,
    node_id: ?u32 = null,
};

/// 标量字段信息 - 用于标量替换优化
pub const ScalarField = struct {
    name: []const u8,
    type_tag: DFGNode.ValueType,
    local_slot: u16,
    offset: u32,
};

/// 逃逸信息 - 包含完整的逃逸分析结果
pub const EscapeInfo = struct {
    state: EscapeState,
    /// 逃逸路径（用于调试和优化报告）
    escape_points: std.ArrayListUnmanaged(EscapePoint),
    /// 是否可以执行标量替换
    can_scalar_replace: bool,
    /// 标量替换后的字段列表
    scalar_fields: std.ArrayListUnmanaged(ScalarField),
    /// 分配点节点ID
    allocation_node: ?u32,
    /// 对象类型（用于栈分配大小计算）
    object_type: ObjectType,
    /// 估算的对象大小（字节）
    estimated_size: u32,
    /// 是否可以栈分配
    can_stack_allocate: bool,
    /// 栈分配槽位（如果可以栈分配）
    stack_slot: ?u16,
    /// 字段访问计数
    field_access_count: u32,

    pub const ObjectType = enum {
        unknown,
        php_object,
        php_array,
        php_closure,
        php_string,
    };

    pub fn init() EscapeInfo {
        return EscapeInfo{
            .state = .Unknown,
            .escape_points = .{},
            .can_scalar_replace = false,
            .scalar_fields = .{},
            .allocation_node = null,
            .object_type = .unknown,
            .estimated_size = 0,
            .can_stack_allocate = false,
            .stack_slot = null,
            .field_access_count = 0,
        };
    }

    pub fn deinit(self: *EscapeInfo, allocator: std.mem.Allocator) void {
        self.escape_points.deinit(allocator);
        self.scalar_fields.deinit(allocator);
    }

    pub fn addEscapePoint(self: *EscapeInfo, allocator: std.mem.Allocator, point: EscapePoint) !void {
        try self.escape_points.append(allocator, point);
    }

    pub fn addScalarField(self: *EscapeInfo, allocator: std.mem.Allocator, field: ScalarField) !void {
        try self.scalar_fields.append(allocator, field);
    }

    /// 检查是否适合栈分配
    pub fn isStackAllocatable(self: *const EscapeInfo) bool {
        // 只有不逃逸且大小合适的对象才能栈分配
        return self.state == .NoEscape and
            self.estimated_size > 0 and
            self.estimated_size <= StackAllocationOptimizer.MAX_STACK_OBJECT_SIZE;
    }

    /// 检查是否适合标量替换
    pub fn isScalarReplaceable(self: *const EscapeInfo) bool {
        return self.can_scalar_replace and
            self.state == .NoEscape and
            self.scalar_fields.items.len > 0;
    }
};

/// 数据流图节点
pub const DFGNode = struct {
    id: u32,
    kind: NodeKind,
    escape_state: EscapeState,
    value_type: ValueType,
    /// 关联的AST节点索引
    ast_node: ?ast.Node.Index,
    /// 源代码位置
    location: SourceLocation,

    pub const NodeKind = enum {
        /// 对象分配: new Object(), []
        allocation,
        /// 函数参数
        parameter,
        /// 局部变量
        local_var,
        /// 字段加载: $obj->field
        field_load,
        /// 字段存储: $obj->field = $val
        field_store,
        /// 数组加载: $arr[$key]
        array_load,
        /// 数组存储: $arr[$key] = $val
        array_store,
        /// 函数调用参数
        call_arg,
        /// 函数调用返回值
        call_result,
        /// return语句
        return_value,
        /// SSA phi节点
        phi,
        /// 全局变量
        global_var,
        /// 闭包捕获
        closure_capture,
        /// 常量值
        constant,
    };

    pub const ValueType = enum {
        unknown,
        null_type,
        boolean,
        integer,
        float,
        string,
        array,
        object,
        closure,
        resource,
        mixed,
    };

    pub fn init(id: u32, kind: NodeKind) DFGNode {
        return DFGNode{
            .id = id,
            .kind = kind,
            .escape_state = .Unknown,
            .value_type = .unknown,
            .ast_node = null,
            .location = .{ .line = 0, .column = 0 },
        };
    }

    pub fn withAstNode(self: DFGNode, node_idx: ast.Node.Index) DFGNode {
        var result = self;
        result.ast_node = node_idx;
        return result;
    }

    pub fn withLocation(self: DFGNode, loc: SourceLocation) DFGNode {
        var result = self;
        result.location = loc;
        return result;
    }

    pub fn withValueType(self: DFGNode, vtype: ValueType) DFGNode {
        var result = self;
        result.value_type = vtype;
        return result;
    }
};

/// 数据流图边
pub const DFGEdge = struct {
    from: u32,
    to: u32,
    kind: EdgeKind,

    pub const EdgeKind = enum {
        /// 定义-使用关系
        def_use,
        /// 指向关系 (指针/引用)
        points_to,
        /// 字段关系
        field_of,
        /// 数组元素关系
        element_of,
        /// 控制流依赖
        control_dep,
        /// 数据流依赖
        data_dep,
    };

    pub fn init(from: u32, to: u32, kind: EdgeKind) DFGEdge {
        return DFGEdge{
            .from = from,
            .to = to,
            .kind = kind,
        };
    }
};

/// 数据流图
pub const DataFlowGraph = struct {
    nodes: std.ArrayListUnmanaged(DFGNode),
    edges: std.ArrayListUnmanaged(DFGEdge),
    /// 节点ID到节点索引的映射
    node_map: std.AutoHashMapUnmanaged(u32, usize),
    /// 变量名到节点ID的映射
    var_to_node: std.StringHashMapUnmanaged(u32),
    /// 下一个节点ID
    next_id: u32,
    allocator: std.mem.Allocator,
    /// SSA变量版本映射 (变量名 -> 当前版本号)
    ssa_versions: std.StringHashMapUnmanaged(u32),
    /// SSA定义点映射 (变量名_版本 -> 节点ID)
    ssa_definitions: std.StringHashMapUnmanaged(u32),
    /// Phi节点列表
    phi_nodes: std.ArrayListUnmanaged(PhiNode),
    /// 基本块列表
    basic_blocks: std.ArrayListUnmanaged(BasicBlock),
    /// 是否已转换为SSA形式
    is_ssa_form: bool,

    /// Phi节点 - SSA形式中合并不同控制流路径的值
    pub const PhiNode = struct {
        /// Phi节点ID
        node_id: u32,
        /// 变量名
        variable: []const u8,
        /// 结果版本号
        result_version: u32,
        /// 来源列表 (基本块ID -> 版本号)
        sources: std.ArrayListUnmanaged(PhiSource),

        pub const PhiSource = struct {
            block_id: u32,
            version: u32,
            source_node: u32,
        };

        pub fn init(node_id: u32, variable: []const u8, result_version: u32) PhiNode {
            return PhiNode{
                .node_id = node_id,
                .variable = variable,
                .result_version = result_version,
                .sources = .{},
            };
        }

        pub fn deinit(self: *PhiNode, allocator: std.mem.Allocator) void {
            self.sources.deinit(allocator);
        }

        pub fn addSource(self: *PhiNode, allocator: std.mem.Allocator, block_id: u32, version: u32, source_node: u32) !void {
            try self.sources.append(allocator, .{
                .block_id = block_id,
                .version = version,
                .source_node = source_node,
            });
        }
    };

    /// 基本块 - 控制流图的基本单元
    pub const BasicBlock = struct {
        id: u32,
        /// 块内节点列表
        nodes: std.ArrayListUnmanaged(u32),
        /// 前驱块
        predecessors: std.ArrayListUnmanaged(u32),
        /// 后继块
        successors: std.ArrayListUnmanaged(u32),
        /// 块入口的变量版本
        entry_versions: std.StringHashMapUnmanaged(u32),
        /// 块出口的变量版本
        exit_versions: std.StringHashMapUnmanaged(u32),
        /// 支配边界
        dominance_frontier: std.ArrayListUnmanaged(u32),
        /// 直接支配者
        immediate_dominator: ?u32,

        pub fn init(id: u32) BasicBlock {
            return BasicBlock{
                .id = id,
                .nodes = .{},
                .predecessors = .{},
                .successors = .{},
                .entry_versions = .{},
                .exit_versions = .{},
                .dominance_frontier = .{},
                .immediate_dominator = null,
            };
        }

        pub fn deinit(self: *BasicBlock, allocator: std.mem.Allocator) void {
            self.nodes.deinit(allocator);
            self.predecessors.deinit(allocator);
            self.successors.deinit(allocator);
            self.entry_versions.deinit(allocator);
            self.exit_versions.deinit(allocator);
            self.dominance_frontier.deinit(allocator);
        }

        pub fn addNode(self: *BasicBlock, allocator: std.mem.Allocator, node_id: u32) !void {
            try self.nodes.append(allocator, node_id);
        }

        pub fn addPredecessor(self: *BasicBlock, allocator: std.mem.Allocator, block_id: u32) !void {
            try self.predecessors.append(allocator, block_id);
        }

        pub fn addSuccessor(self: *BasicBlock, allocator: std.mem.Allocator, block_id: u32) !void {
            try self.successors.append(allocator, block_id);
        }
    };

    pub fn init(allocator: std.mem.Allocator) DataFlowGraph {
        return DataFlowGraph{
            .nodes = .{},
            .edges = .{},
            .node_map = .{},
            .var_to_node = .{},
            .next_id = 0,
            .allocator = allocator,
            .ssa_versions = .{},
            .ssa_definitions = .{},
            .phi_nodes = .{},
            .basic_blocks = .{},
            .is_ssa_form = false,
        };
    }

    pub fn deinit(self: *DataFlowGraph) void {
        self.nodes.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.node_map.deinit(self.allocator);
        self.var_to_node.deinit(self.allocator);
        self.ssa_versions.deinit(self.allocator);
        // 清理 ssa_definitions 中分配的字符串键
        var def_iter = self.ssa_definitions.iterator();
        while (def_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.ssa_definitions.deinit(self.allocator);
        // 清理phi节点
        for (self.phi_nodes.items) |*phi| {
            phi.deinit(self.allocator);
        }
        self.phi_nodes.deinit(self.allocator);
        // 清理基本块
        for (self.basic_blocks.items) |*block| {
            block.deinit(self.allocator);
        }
        self.basic_blocks.deinit(self.allocator);
    }

    /// 添加节点
    pub fn addNode(self: *DataFlowGraph, kind: DFGNode.NodeKind) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        const node = DFGNode.init(id, kind);
        const index = self.nodes.items.len;
        try self.nodes.append(self.allocator, node);
        try self.node_map.put(self.allocator, id, index);

        return id;
    }

    /// 添加带AST节点的节点
    pub fn addNodeWithAst(self: *DataFlowGraph, kind: DFGNode.NodeKind, ast_node: ast.Node.Index) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        var node = DFGNode.init(id, kind);
        node.ast_node = ast_node;

        const index = self.nodes.items.len;
        try self.nodes.append(self.allocator, node);
        try self.node_map.put(self.allocator, id, index);

        return id;
    }

    /// 添加边
    pub fn addEdge(self: *DataFlowGraph, from: u32, to: u32, kind: DFGEdge.EdgeKind) !void {
        try self.edges.append(self.allocator, DFGEdge.init(from, to, kind));
    }

    /// 获取节点
    pub fn getNode(self: *DataFlowGraph, id: u32) ?*DFGNode {
        if (self.node_map.get(id)) |index| {
            return &self.nodes.items[index];
        }
        return null;
    }

    /// 获取节点（只读）
    pub fn getNodeConst(self: *const DataFlowGraph, id: u32) ?*const DFGNode {
        if (self.node_map.get(id)) |index| {
            return &self.nodes.items[index];
        }
        return null;
    }

    /// 设置节点的逃逸状态
    pub fn setEscapeState(self: *DataFlowGraph, id: u32, state: EscapeState) void {
        if (self.getNode(id)) |node| {
            node.escape_state = state;
        }
    }

    /// 获取指向某节点的所有边
    pub fn getIncomingEdges(self: *const DataFlowGraph, allocator: std.mem.Allocator, node_id: u32) ![]DFGEdge {
        var result = std.ArrayListUnmanaged(DFGEdge){};
        for (self.edges.items) |edge| {
            if (edge.to == node_id) {
                try result.append(allocator, edge);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    /// 获取从某节点出发的所有边
    pub fn getOutgoingEdges(self: *const DataFlowGraph, allocator: std.mem.Allocator, node_id: u32) ![]DFGEdge {
        var result = std.ArrayListUnmanaged(DFGEdge){};
        for (self.edges.items) |edge| {
            if (edge.from == node_id) {
                try result.append(allocator, edge);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    /// 绑定变量名到节点
    pub fn bindVariable(self: *DataFlowGraph, name: []const u8, node_id: u32) !void {
        try self.var_to_node.put(self.allocator, name, node_id);
    }

    /// 查找变量对应的节点
    pub fn lookupVariable(self: *const DataFlowGraph, name: []const u8) ?u32 {
        return self.var_to_node.get(name);
    }

    /// 获取所有分配节点
    pub fn getAllocationNodes(self: *const DataFlowGraph, allocator: std.mem.Allocator) ![]u32 {
        var result = std.ArrayListUnmanaged(u32){};
        for (self.nodes.items) |node| {
            if (node.kind == .allocation) {
                try result.append(allocator, node.id);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    /// 获取节点数量
    pub fn nodeCount(self: *const DataFlowGraph) usize {
        return self.nodes.items.len;
    }

    /// 获取边数量
    pub fn edgeCount(self: *const DataFlowGraph) usize {
        return self.edges.items.len;
    }

    // ========== SSA转换相关方法 ==========

    /// 创建新的基本块
    pub fn createBasicBlock(self: *DataFlowGraph) !u32 {
        const id: u32 = @intCast(self.basic_blocks.items.len);
        try self.basic_blocks.append(self.allocator, BasicBlock.init(id));
        return id;
    }

    /// 获取基本块
    pub fn getBasicBlock(self: *DataFlowGraph, id: u32) ?*BasicBlock {
        if (id < self.basic_blocks.items.len) {
            return &self.basic_blocks.items[id];
        }
        return null;
    }

    /// 添加控制流边
    pub fn addControlFlowEdge(self: *DataFlowGraph, from_block: u32, to_block: u32) !void {
        if (self.getBasicBlock(from_block)) |from| {
            try from.addSuccessor(self.allocator, to_block);
        }
        if (self.getBasicBlock(to_block)) |to| {
            try to.addPredecessor(self.allocator, from_block);
        }
    }

    /// 获取变量的当前SSA版本
    pub fn getSSAVersion(self: *DataFlowGraph, variable: []const u8) u32 {
        return self.ssa_versions.get(variable) orelse 0;
    }

    /// 创建变量的新SSA版本
    pub fn newSSAVersion(self: *DataFlowGraph, variable: []const u8) !u32 {
        const current = self.getSSAVersion(variable);
        const new_version = current + 1;
        try self.ssa_versions.put(self.allocator, variable, new_version);
        return new_version;
    }

    /// 记录SSA定义点
    pub fn recordSSADefinition(self: *DataFlowGraph, variable: []const u8, version: u32, node_id: u32) !void {
        // 创建版本化的变量名
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}_{d}", .{ variable, version }) catch return;
        // 复制key到堆上
        const key_copy = try self.allocator.dupe(u8, key);
        try self.ssa_definitions.put(self.allocator, key_copy, node_id);
    }

    /// 查找SSA定义点
    pub fn lookupSSADefinition(self: *const DataFlowGraph, variable: []const u8, version: u32) ?u32 {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}_{d}", .{ variable, version }) catch return null;
        return self.ssa_definitions.get(key);
    }

    /// 插入Phi节点
    pub fn insertPhiNode(self: *DataFlowGraph, block_id: u32, variable: []const u8) !u32 {
        // 创建phi节点
        const node_id = try self.addNode(.phi);
        const version = try self.newSSAVersion(variable);

        var phi = PhiNode.init(node_id, variable, version);

        // 为每个前驱块添加源
        if (self.getBasicBlock(block_id)) |block| {
            for (block.predecessors.items) |pred_id| {
                if (self.getBasicBlock(pred_id)) |pred_block| {
                    const pred_version = pred_block.exit_versions.get(variable) orelse 0;
                    const source_node = self.lookupSSADefinition(variable, pred_version) orelse 0;
                    try phi.addSource(self.allocator, pred_id, pred_version, source_node);
                }
            }
        }

        try self.phi_nodes.append(self.allocator, phi);
        try self.recordSSADefinition(variable, version, node_id);

        return node_id;
    }

    /// 转换为SSA形式
    pub fn convertToSSA(self: *DataFlowGraph) !void {
        if (self.is_ssa_form) return;

        // Phase 1: 计算支配边界
        try self.computeDominanceFrontiers();

        // Phase 2: 插入Phi节点
        try self.insertPhiNodes();

        // Phase 3: 重命名变量
        try self.renameVariables();

        self.is_ssa_form = true;
    }

    /// 计算支配边界
    fn computeDominanceFrontiers(self: *DataFlowGraph) !void {
        // 简化实现：使用迭代算法计算支配关系
        // 对于每个基本块，计算其支配边界

        const block_count = self.basic_blocks.items.len;
        if (block_count == 0) return;

        // 初始化：假设入口块(0)支配所有块
        for (self.basic_blocks.items) |*block| {
            if (block.id != 0) {
                block.immediate_dominator = 0;
            }
        }

        // 迭代计算支配边界
        var changed = true;
        while (changed) {
            changed = false;
            for (self.basic_blocks.items) |*block| {
                if (block.id == 0) continue;

                // 计算支配边界
                for (block.predecessors.items) |pred_id| {
                    var runner = pred_id;
                    const idom = block.immediate_dominator orelse continue;
                    while (runner != idom) {
                        if (self.getBasicBlock(runner)) |runner_block| {
                            // 检查是否已在支配边界中
                            var found = false;
                            for (runner_block.dominance_frontier.items) |df| {
                                if (df == block.id) {
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                try runner_block.dominance_frontier.append(self.allocator, block.id);
                                changed = true;
                            }
                            runner = runner_block.immediate_dominator orelse break;
                        } else break;
                    }
                }
            }
        }
    }

    /// 插入Phi节点（基于支配边界）
    fn insertPhiNodes(self: *DataFlowGraph) !void {
        // 收集所有变量定义点
        var var_defs = std.StringHashMapUnmanaged(std.ArrayListUnmanaged(u32)){};
        defer {
            var iter = var_defs.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            var_defs.deinit(self.allocator);
        }

        // 遍历所有节点，收集变量定义
        for (self.nodes.items) |node| {
            if (node.kind == .local_var or node.kind == .parameter) {
                // 查找变量名
                var var_iter = self.var_to_node.iterator();
                while (var_iter.next()) |entry| {
                    if (entry.value_ptr.* == node.id) {
                        // 找到变量名，记录定义块
                        // 简化：假设每个节点在块0中
                        const block_id: u32 = 0;
                        if (var_defs.getPtr(entry.key_ptr.*)) |list| {
                            try list.append(self.allocator, block_id);
                        } else {
                            var list = std.ArrayListUnmanaged(u32){};
                            try list.append(self.allocator, block_id);
                            try var_defs.put(self.allocator, entry.key_ptr.*, list);
                        }
                        break;
                    }
                }
            }
        }

        // 为每个变量在支配边界处插入Phi节点
        var var_iter = var_defs.iterator();
        while (var_iter.next()) |entry| {
            const variable = entry.key_ptr.*;
            var worklist = std.ArrayListUnmanaged(u32){};
            defer worklist.deinit(self.allocator);

            // 初始化工作列表
            for (entry.value_ptr.items) |def_block| {
                try worklist.append(self.allocator, def_block);
            }

            // 处理工作列表
            var processed = std.AutoHashMapUnmanaged(u32, void){};
            defer processed.deinit(self.allocator);

            while (worklist.items.len > 0) {
                const block_id = worklist.items[worklist.items.len - 1];
                worklist.items.len -= 1;
                if (self.getBasicBlock(block_id)) |block| {
                    for (block.dominance_frontier.items) |df_block| {
                        if (!processed.contains(df_block)) {
                            try processed.put(self.allocator, df_block, {});
                            _ = try self.insertPhiNode(df_block, variable);
                            try worklist.append(self.allocator, df_block);
                        }
                    }
                }
            }
        }
    }

    /// 重命名变量（SSA版本化）
    fn renameVariables(self: *DataFlowGraph) !void {
        // 重置版本计数器
        self.ssa_versions.clearRetainingCapacity();

        // 从入口块开始深度优先遍历
        if (self.basic_blocks.items.len == 0) return;

        var visited = std.AutoHashMapUnmanaged(u32, void){};
        defer visited.deinit(self.allocator);

        try self.renameBlock(0, &visited);
    }

    /// 重命名单个基本块中的变量
    fn renameBlock(self: *DataFlowGraph, block_id: u32, visited: *std.AutoHashMapUnmanaged(u32, void)) !void {
        if (visited.contains(block_id)) return;
        try visited.put(self.allocator, block_id, {});

        const block = self.getBasicBlock(block_id) orelse return;

        // 保存当前版本状态
        var saved_versions = std.StringHashMapUnmanaged(u32){};
        defer saved_versions.deinit(self.allocator);

        var ver_iter = self.ssa_versions.iterator();
        while (ver_iter.next()) |entry| {
            try saved_versions.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }

        // 处理Phi节点
        for (self.phi_nodes.items) |phi| {
            // 查找属于此块的phi节点
            for (self.basic_blocks.items) |*b| {
                if (b.id == block_id) {
                    for (b.nodes.items) |node_id| {
                        if (node_id == phi.node_id) {
                            try self.ssa_versions.put(self.allocator, phi.variable, phi.result_version);
                        }
                    }
                }
            }
        }

        // 处理块内的定义
        for (block.nodes.items) |node_id| {
            if (self.getNode(node_id)) |node| {
                if (node.kind == .local_var) {
                    // 查找变量名并创建新版本
                    var var_iter = self.var_to_node.iterator();
                    while (var_iter.next()) |entry| {
                        if (entry.value_ptr.* == node_id) {
                            const new_ver = try self.newSSAVersion(entry.key_ptr.*);
                            try self.recordSSADefinition(entry.key_ptr.*, new_ver, node_id);
                            break;
                        }
                    }
                }
            }
        }

        // 更新块的出口版本
        var exit_iter = self.ssa_versions.iterator();
        while (exit_iter.next()) |entry| {
            try block.exit_versions.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }

        // 递归处理后继块
        for (block.successors.items) |succ_id| {
            try self.renameBlock(succ_id, visited);
        }

        // 恢复版本状态
        self.ssa_versions.clearRetainingCapacity();
        var restore_iter = saved_versions.iterator();
        while (restore_iter.next()) |entry| {
            try self.ssa_versions.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    /// 检查是否为SSA形式
    pub fn isSSAForm(self: *const DataFlowGraph) bool {
        return self.is_ssa_form;
    }

    /// 获取Phi节点数量
    pub fn phiNodeCount(self: *const DataFlowGraph) usize {
        return self.phi_nodes.items.len;
    }

    /// 获取基本块数量
    pub fn basicBlockCount(self: *const DataFlowGraph) usize {
        return self.basic_blocks.items.len;
    }
};


/// 逃逸分析器
/// 分析函数中对象的逃逸状态，用于栈分配和标量替换优化
pub const EscapeAnalyzer = struct {
    dfg: DataFlowGraph,
    worklist: std.ArrayListUnmanaged(u32),
    /// 分配点到逃逸信息的映射
    escape_info_map: std.AutoHashMapUnmanaged(u32, EscapeInfo),
    /// PHP上下文
    context: ?*PHPContext,
    allocator: std.mem.Allocator,
    /// 分析统计
    stats: AnalysisStats,

    pub const AnalysisStats = struct {
        total_allocations: u32 = 0,
        no_escape_count: u32 = 0,
        arg_escape_count: u32 = 0,
        global_escape_count: u32 = 0,
        scalar_replaceable_count: u32 = 0,
        analysis_time_ns: i64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) EscapeAnalyzer {
        return EscapeAnalyzer{
            .dfg = DataFlowGraph.init(allocator),
            .worklist = .{},
            .escape_info_map = .{},
            .context = null,
            .allocator = allocator,
            .stats = .{},
        };
    }

    pub fn initWithContext(allocator: std.mem.Allocator, context: *PHPContext) EscapeAnalyzer {
        var analyzer = init(allocator);
        analyzer.context = context;
        return analyzer;
    }

    pub fn deinit(self: *EscapeAnalyzer) void {
        self.dfg.deinit();
        self.worklist.deinit(self.allocator);

        // 清理逃逸信息
        var iter = self.escape_info_map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.escape_info_map.deinit(self.allocator);
    }

    /// 分析函数的逃逸状态
    pub fn analyze(self: *EscapeAnalyzer, root_index: ast.Node.Index) !void {
        const start_time = std.time.nanoTimestamp();

        // Phase 1: 构建数据流图
        try self.buildDFG(root_index);

        // Phase 2: 初始化逃逸状态
        self.initializeEscapeStates();

        // Phase 3: 迭代传播逃逸状态
        try self.propagateEscapeStates();

        // Phase 4: 标量替换分析
        try self.analyzeScalarReplacement();

        // 更新统计
        self.stats.analysis_time_ns = std.time.nanoTimestamp() - start_time;
        self.updateStats();
    }

    /// 构建数据流图
    fn buildDFG(self: *EscapeAnalyzer, root_index: ast.Node.Index) !void {
        if (self.context) |ctx| {
            try self.visitAstNode(ctx, root_index);
        }
    }

    /// 访问AST节点，构建DFG
    fn visitAstNode(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];

        switch (node.tag) {
            .root => try self.visitRoot(ctx, index),
            .block => try self.visitBlock(ctx, index),
            .function_decl => try self.visitFunctionDecl(ctx, index),
            .assignment => try self.visitAssignment(ctx, index),
            .object_instantiation => try self.visitNewObject(ctx, index),
            .array_init => try self.visitArrayInit(ctx, index),
            .return_stmt => try self.visitReturn(ctx, index),
            .function_call => try self.visitFunctionCall(ctx, index),
            .method_call => try self.visitMethodCall(ctx, index),
            .property_access => try self.visitPropertyAccess(ctx, index),
            .array_access => try self.visitArrayAccess(ctx, index),
            .closure => try self.visitClosure(ctx, index),
            .variable => try self.visitVariable(ctx, index),
            .if_stmt => try self.visitIf(ctx, index),
            .while_stmt => try self.visitWhile(ctx, index),
            .for_stmt => try self.visitFor(ctx, index),
            .foreach_stmt => try self.visitForeach(ctx, index),
            .throw_stmt => try self.visitThrow(ctx, index),
            else => {},
        }
    }

    fn visitRoot(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const stmts = node.data.root.stmts;
        for (stmts) |stmt_idx| {
            try self.visitAstNode(ctx, stmt_idx);
        }
    }

    fn visitBlock(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const stmts = node.data.block.stmts;
        for (stmts) |stmt_idx| {
            try self.visitAstNode(ctx, stmt_idx);
        }
    }

    fn visitFunctionDecl(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const func_data = node.data.function_decl;

        // 为参数创建节点
        for (func_data.params) |param_idx| {
            const param_node = ctx.nodes.items[param_idx];
            const param_name = ctx.string_pool.keys()[param_node.data.parameter.name];

            const node_id = try self.dfg.addNodeWithAst(.parameter, param_idx);
            try self.dfg.bindVariable(param_name, node_id);

            // 参数初始为ArgEscape
            self.dfg.setEscapeState(node_id, .ArgEscape);
        }

        // 访问函数体
        try self.visitAstNode(ctx, func_data.body);
    }

    fn visitAssignment(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const assign_data = node.data.assignment;

        // 访问右值
        try self.visitAstNode(ctx, assign_data.value);

        // 处理左值
        const target_node = ctx.nodes.items[assign_data.target];
        switch (target_node.tag) {
            .variable => {
                const var_name = ctx.string_pool.keys()[target_node.data.variable.name];

                // 创建或更新变量节点
                const var_node_id = try self.dfg.addNodeWithAst(.local_var, assign_data.target);
                try self.dfg.bindVariable(var_name, var_node_id);

                // 如果右值是分配节点，建立指向关系
                if (self.findAllocationNode(assign_data.value)) |alloc_id| {
                    try self.dfg.addEdge(var_node_id, alloc_id, .points_to);
                }
            },
            .property_access => {
                // 属性赋值可能导致逃逸
                const prop_data = target_node.data.property_access;
                try self.visitAstNode(ctx, prop_data.target);

                // 字段存储节点
                const store_node_id = try self.dfg.addNodeWithAst(.field_store, index);

                // 如果右值是分配节点，标记为可能逃逸到堆
                if (self.findAllocationNode(assign_data.value)) |alloc_id| {
                    try self.dfg.addEdge(store_node_id, alloc_id, .field_of);
                    // 存储到对象字段导致逃逸
                    self.markEscape(alloc_id, .stored_to_heap, index);
                }
            },
            .array_access => {
                // 数组元素赋值
                const access_data = target_node.data.array_access;
                try self.visitAstNode(ctx, access_data.target);

                const store_node_id = try self.dfg.addNodeWithAst(.array_store, index);

                if (self.findAllocationNode(assign_data.value)) |alloc_id| {
                    try self.dfg.addEdge(store_node_id, alloc_id, .element_of);
                    // 存储到数组导致逃逸
                    self.markEscape(alloc_id, .stored_to_array, index);
                }
            },
            else => {},
        }
    }

    fn visitNewObject(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        _ = ctx;
        // 创建分配节点
        const alloc_id = try self.dfg.addNodeWithAst(.allocation, index);

        // 初始化逃逸信息
        var info = EscapeInfo.init();
        info.allocation_node = alloc_id;
        info.state = .NoEscape; // 初始假设不逃逸
        try self.escape_info_map.put(self.allocator, alloc_id, info);

        self.stats.total_allocations += 1;
    }

    fn visitArrayInit(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const array_data = node.data.array_init;

        // 数组也是分配
        const alloc_id = try self.dfg.addNodeWithAst(.allocation, index);

        var info = EscapeInfo.init();
        info.allocation_node = alloc_id;
        info.state = .NoEscape;
        try self.escape_info_map.put(self.allocator, alloc_id, info);

        self.stats.total_allocations += 1;

        // 访问数组元素
        for (array_data.elements) |elem_idx| {
            try self.visitAstNode(ctx, elem_idx);
        }
    }

    fn visitReturn(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const return_data = node.data.return_stmt;

        if (return_data.expr) |expr_idx| {
            try self.visitAstNode(ctx, expr_idx);

            // 返回值节点
            const ret_node_id = try self.dfg.addNodeWithAst(.return_value, index);
            self.dfg.setEscapeState(ret_node_id, .GlobalEscape);

            // 如果返回的是分配的对象，标记为全局逃逸
            if (self.findAllocationNode(expr_idx)) |alloc_id| {
                try self.dfg.addEdge(ret_node_id, alloc_id, .def_use);
                self.markEscape(alloc_id, .returned, index);
            }
        }
    }

    fn visitFunctionCall(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const call_data = node.data.function_call;

        // 调用结果节点
        _ = try self.dfg.addNodeWithAst(.call_result, index);

        // 分析参数
        for (call_data.args) |arg_idx| {
            try self.visitAstNode(ctx, arg_idx);

            // 参数节点
            const arg_node_id = try self.dfg.addNodeWithAst(.call_arg, arg_idx);

            // 如果参数是分配的对象，可能逃逸
            if (self.findAllocationNode(arg_idx)) |alloc_id| {
                try self.dfg.addEdge(arg_node_id, alloc_id, .def_use);
                // 传递给未知函数，保守地标记为全局逃逸
                self.markEscape(alloc_id, .passed_to_unknown, index);
            }
        }
    }

    fn visitMethodCall(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const method_data = node.data.method_call;

        // 访问目标对象
        try self.visitAstNode(ctx, method_data.target);

        // 调用结果节点
        _ = try self.dfg.addNodeWithAst(.call_result, index);

        // 分析参数
        for (method_data.args) |arg_idx| {
            try self.visitAstNode(ctx, arg_idx);

            const arg_node_id = try self.dfg.addNodeWithAst(.call_arg, arg_idx);

            if (self.findAllocationNode(arg_idx)) |alloc_id| {
                try self.dfg.addEdge(arg_node_id, alloc_id, .def_use);
                self.markEscape(alloc_id, .passed_to_unknown, index);
            }
        }
    }

    fn visitPropertyAccess(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const prop_data = node.data.property_access;

        try self.visitAstNode(ctx, prop_data.target);

        // 字段加载节点
        _ = try self.dfg.addNodeWithAst(.field_load, index);
    }

    fn visitArrayAccess(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const access_data = node.data.array_access;

        try self.visitAstNode(ctx, access_data.target);

        if (access_data.index) |idx| {
            try self.visitAstNode(ctx, idx);
        }

        // 数组加载节点
        _ = try self.dfg.addNodeWithAst(.array_load, index);
    }

    fn visitClosure(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const closure_data = node.data.closure;

        // 闭包本身是一个分配
        const closure_alloc_id = try self.dfg.addNodeWithAst(.allocation, index);

        var info = EscapeInfo.init();
        info.allocation_node = closure_alloc_id;
        info.state = .NoEscape;
        try self.escape_info_map.put(self.allocator, closure_alloc_id, info);

        self.stats.total_allocations += 1;

        // 分析捕获的变量
        for (closure_data.captures) |capture_idx| {
            const capture_node = ctx.nodes.items[capture_idx];
            if (capture_node.tag == .variable) {
                const var_name = ctx.string_pool.keys()[capture_node.data.variable.name];

                // 创建捕获节点
                const capture_node_id = try self.dfg.addNodeWithAst(.closure_capture, capture_idx);

                // 如果捕获的变量指向分配的对象，标记为被闭包捕获
                if (self.dfg.lookupVariable(var_name)) |var_node_id| {
                    try self.dfg.addEdge(capture_node_id, var_node_id, .def_use);

                    // 查找变量指向的分配
                    const outgoing = try self.dfg.getOutgoingEdges(self.allocator, var_node_id);
                    defer self.allocator.free(outgoing);

                    for (outgoing) |edge| {
                        if (edge.kind == .points_to) {
                            self.markEscape(edge.to, .captured_by_closure, index);
                        }
                    }
                }
            }
        }
    }

    fn visitVariable(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        _ = self;
        _ = ctx;
        _ = index;
        // 变量访问本身不创建新节点，只在赋值时处理
    }

    fn visitIf(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const if_data = node.data.if_stmt;

        try self.visitAstNode(ctx, if_data.condition);
        try self.visitAstNode(ctx, if_data.then_branch);

        if (if_data.else_branch) |else_idx| {
            try self.visitAstNode(ctx, else_idx);
        }
    }

    fn visitWhile(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const while_data = node.data.while_stmt;

        try self.visitAstNode(ctx, while_data.condition);
        try self.visitAstNode(ctx, while_data.body);
    }

    fn visitFor(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const for_data = node.data.for_stmt;

        if (for_data.init) |init_idx| {
            try self.visitAstNode(ctx, init_idx);
        }
        if (for_data.condition) |cond_idx| {
            try self.visitAstNode(ctx, cond_idx);
        }
        if (for_data.loop) |loop_idx| {
            try self.visitAstNode(ctx, loop_idx);
        }
        try self.visitAstNode(ctx, for_data.body);
    }

    fn visitForeach(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const foreach_data = node.data.foreach_stmt;

        try self.visitAstNode(ctx, foreach_data.iterable);
        try self.visitAstNode(ctx, foreach_data.body);
    }

    fn visitThrow(self: *EscapeAnalyzer, ctx: *PHPContext, index: ast.Node.Index) !void {
        const node = ctx.nodes.items[index];
        const throw_data = node.data.throw_stmt;

        try self.visitAstNode(ctx, throw_data.expression);

        // 抛出的对象全局逃逸
        if (self.findAllocationNode(throw_data.expression)) |alloc_id| {
            self.markEscape(alloc_id, .thrown_as_exception, index);
        }
    }

    /// 查找表达式对应的分配节点
    fn findAllocationNode(self: *EscapeAnalyzer, expr_index: ast.Node.Index) ?u32 {
        // 简单实现：检查是否有直接对应的分配节点
        for (self.dfg.nodes.items) |node| {
            if (node.ast_node == expr_index and node.kind == .allocation) {
                return node.id;
            }
        }

        // 检查变量是否指向分配
        if (self.context) |ctx| {
            const node = ctx.nodes.items[expr_index];
            if (node.tag == .variable) {
                const var_name = ctx.string_pool.keys()[node.data.variable.name];
                if (self.dfg.lookupVariable(var_name)) |var_node_id| {
                    // 查找变量指向的分配
                    for (self.dfg.edges.items) |edge| {
                        if (edge.from == var_node_id and edge.kind == .points_to) {
                            return edge.to;
                        }
                    }
                }
            }
        }

        return null;
    }

    /// 标记对象逃逸
    fn markEscape(self: *EscapeAnalyzer, alloc_id: u32, reason: EscapeReason, ast_node: ast.Node.Index) void {
        if (self.escape_info_map.getPtr(alloc_id)) |info| {
            // 根据原因确定逃逸级别
            const new_state: EscapeState = switch (reason) {
                .returned, .stored_to_heap, .stored_to_global, .passed_to_unknown, .thrown_as_exception => .GlobalEscape,
                .captured_by_closure, .stored_to_array, .passed_by_reference => .GlobalEscape,
            };

            info.state = info.state.merge(new_state);

            // 记录逃逸点
            info.addEscapePoint(self.allocator, .{
                .location = .{ .line = 0, .column = 0 },
                .reason = reason,
                .node_id = ast_node,
            }) catch {};
        }

        // 更新DFG节点状态
        self.dfg.setEscapeState(alloc_id, .GlobalEscape);
    }

    /// 初始化逃逸状态
    fn initializeEscapeStates(self: *EscapeAnalyzer) void {
        for (self.dfg.nodes.items) |*node| {
            node.escape_state = switch (node.kind) {
                .parameter => .ArgEscape,
                .allocation => .NoEscape,
                .return_value => .GlobalEscape,
                .global_var => .GlobalEscape,
                else => .Unknown,
            };
        }
    }

    /// 迭代传播逃逸状态
    fn propagateEscapeStates(self: *EscapeAnalyzer) !void {
        // 将所有节点加入工作列表
        for (self.dfg.nodes.items) |node| {
            try self.worklist.append(self.allocator, node.id);
        }

        // 迭代直到不动点
        while (self.worklist.items.len > 0) {
            const node_id = self.worklist.pop();

            if (self.dfg.getNode(node_id)) |node| {
                var new_state = node.escape_state;

                // 检查所有出边，传播逃逸状态
                for (self.dfg.edges.items) |edge| {
                    if (edge.from == node_id) {
                        if (self.dfg.getNodeConst(edge.to)) |target| {
                            new_state = new_state.merge(target.escape_state);
                        }
                    }
                }

                // 如果状态改变，更新并将相关节点加入工作列表
                if (@intFromEnum(new_state) > @intFromEnum(node.escape_state)) {
                    node.escape_state = new_state;

                    // 更新逃逸信息
                    if (self.escape_info_map.getPtr(node_id)) |info| {
                        info.state = new_state;
                    }

                    // 将所有指向此节点的节点加入工作列表
                    for (self.dfg.edges.items) |edge| {
                        if (edge.to == node_id) {
                            try self.worklist.append(self.allocator, edge.from);
                        }
                    }
                }
            }
        }
    }

    /// 分析标量替换可能性
    fn analyzeScalarReplacement(self: *EscapeAnalyzer) !void {
        var iter = self.escape_info_map.iterator();
        while (iter.next()) |entry| {
            const alloc_id = entry.key_ptr.*;
            const info = entry.value_ptr;

            // 只有不逃逸的对象才能标量替换
            if (info.state != .NoEscape) {
                continue;
            }

            // 检查是否所有字段访问都是独立的
            var can_replace = true;
            var field_count: u32 = 0;

            for (self.dfg.edges.items) |edge| {
                if (edge.from == alloc_id) {
                    if (self.dfg.getNodeConst(edge.to)) |target| {
                        switch (target.kind) {
                            .field_load, .field_store => {
                                field_count += 1;
                            },
                            .call_arg, .return_value => {
                                can_replace = false;
                                break;
                            },
                            else => {},
                        }
                    }
                }
            }

            if (can_replace and field_count > 0) {
                info.can_scalar_replace = true;
                self.stats.scalar_replaceable_count += 1;
            }
        }
    }

    /// 更新统计信息
    fn updateStats(self: *EscapeAnalyzer) void {
        var iter = self.escape_info_map.iterator();
        while (iter.next()) |entry| {
            const info = entry.value_ptr;
            switch (info.state) {
                .NoEscape => self.stats.no_escape_count += 1,
                .ArgEscape => self.stats.arg_escape_count += 1,
                .GlobalEscape => self.stats.global_escape_count += 1,
                .Unknown => {},
            }
        }
    }

    /// 获取分配点的逃逸信息
    pub fn getEscapeInfo(self: *const EscapeAnalyzer, alloc_id: u32) ?*const EscapeInfo {
        return self.escape_info_map.getPtr(alloc_id);
    }

    /// 检查对象是否可以栈分配
    pub fn canStackAllocate(self: *const EscapeAnalyzer, alloc_id: u32) bool {
        if (self.escape_info_map.get(alloc_id)) |info| {
            return info.state.canStackAllocate();
        }
        return false;
    }

    /// 检查对象是否可以标量替换
    pub fn canScalarReplace(self: *const EscapeAnalyzer, alloc_id: u32) bool {
        if (self.escape_info_map.get(alloc_id)) |info| {
            return info.can_scalar_replace;
        }
        return false;
    }

    /// 获取分析统计
    pub fn getStats(self: *const EscapeAnalyzer) AnalysisStats {
        return self.stats;
    }

    /// 生成分析报告
    pub fn generateReport(self: *const EscapeAnalyzer, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        const writer = buffer.writer(allocator);

        try writer.print("=== Escape Analysis Report ===\n", .{});
        try writer.print("Total allocations: {}\n", .{self.stats.total_allocations});
        try writer.print("No escape: {} ({d:.1}%)\n", .{
            self.stats.no_escape_count,
            if (self.stats.total_allocations > 0)
                @as(f64, @floatFromInt(self.stats.no_escape_count)) / @as(f64, @floatFromInt(self.stats.total_allocations)) * 100.0
            else
                0.0,
        });
        try writer.print("Arg escape: {}\n", .{self.stats.arg_escape_count});
        try writer.print("Global escape: {}\n", .{self.stats.global_escape_count});
        try writer.print("Scalar replaceable: {}\n", .{self.stats.scalar_replaceable_count});
        try writer.print("Analysis time: {}ns\n", .{self.stats.analysis_time_ns});
        try writer.print("DFG nodes: {}\n", .{self.dfg.nodeCount()});
        try writer.print("DFG edges: {}\n", .{self.dfg.edgeCount()});

        return buffer.toOwnedSlice(allocator);
    }

    /// 获取所有可栈分配的对象
    pub fn getStackAllocatableObjects(self: *const EscapeAnalyzer, allocator: std.mem.Allocator) ![]u32 {
        var result = std.ArrayListUnmanaged(u32){};
        var iter = self.escape_info_map.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isStackAllocatable()) {
                try result.append(allocator, entry.key_ptr.*);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    /// 获取所有可标量替换的对象
    pub fn getScalarReplaceableObjects(self: *const EscapeAnalyzer, allocator: std.mem.Allocator) ![]u32 {
        var result = std.ArrayListUnmanaged(u32){};
        var iter = self.escape_info_map.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isScalarReplaceable()) {
                try result.append(allocator, entry.key_ptr.*);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    /// 追踪逃逸路径
    pub fn traceEscapePath(self: *const EscapeAnalyzer, alloc_id: u32, allocator: std.mem.Allocator) ![]EscapePathStep {
        var path = std.ArrayListUnmanaged(EscapePathStep){};

        // 从分配点开始追踪
        var visited = std.AutoHashMapUnmanaged(u32, void){};
        defer visited.deinit(allocator);

        var queue = std.ArrayListUnmanaged(u32){};
        defer queue.deinit(allocator);

        try queue.append(allocator, alloc_id);
        try visited.put(allocator, alloc_id, {});

        while (queue.items.len > 0) {
            const current_id = queue.orderedRemove(0);

            if (self.dfg.getNodeConst(current_id)) |node| {
                try path.append(allocator, .{
                    .node_id = current_id,
                    .node_kind = node.kind,
                    .escape_state = node.escape_state,
                    .ast_node = node.ast_node,
                });

                // 如果已经是全局逃逸，停止追踪
                if (node.escape_state == .GlobalEscape) {
                    break;
                }

                // 追踪出边
                for (self.dfg.edges.items) |edge| {
                    if (edge.from == current_id and !visited.contains(edge.to)) {
                        try queue.append(allocator, edge.to);
                        try visited.put(allocator, edge.to, {});
                    }
                }
            }
        }

        return path.toOwnedSlice(allocator);
    }

    pub const EscapePathStep = struct {
        node_id: u32,
        node_kind: DFGNode.NodeKind,
        escape_state: EscapeState,
        ast_node: ?ast.Node.Index,
    };
};

// ============================================================================
// 栈分配优化器
// ============================================================================

/// 栈分配优化器
/// 根据逃逸分析结果决定对象的分配位置
pub const StackAllocationOptimizer = struct {
    allocator: std.mem.Allocator,
    /// 栈分配决策结果
    decisions: std.AutoHashMapUnmanaged(u32, AllocationDecision),
    /// 当前栈帧大小
    current_stack_size: u32,
    /// 下一个可用的栈槽位
    next_stack_slot: u16,
    /// 统计信息
    stats: OptimizationStats,

    /// 最大栈分配对象大小（字节）
    pub const MAX_STACK_OBJECT_SIZE: u32 = 256;
    /// 最大栈帧大小（字节）
    pub const MAX_STACK_FRAME_SIZE: u32 = 4096;
    /// 默认对象大小估算
    pub const DEFAULT_OBJECT_SIZE: u32 = 64;
    /// 默认数组大小估算
    pub const DEFAULT_ARRAY_SIZE: u32 = 128;

    pub const AllocationDecision = struct {
        /// 分配位置
        location: AllocationLocation,
        /// 栈槽位（如果是栈分配）
        stack_slot: ?u16,
        /// 估算大小
        estimated_size: u32,
        /// 原因
        reason: DecisionReason,
    };

    pub const AllocationLocation = enum {
        /// 堆分配
        heap,
        /// 栈分配
        stack,
        /// 标量替换（消除分配）
        scalar_replaced,
    };

    pub const DecisionReason = enum {
        /// 对象逃逸
        escapes,
        /// 对象太大
        too_large,
        /// 栈空间不足
        stack_overflow,
        /// 可以栈分配
        fits_on_stack,
        /// 可以标量替换
        can_scalar_replace,
        /// 未知类型
        unknown_type,
    };

    pub const OptimizationStats = struct {
        total_allocations: u32 = 0,
        stack_allocated: u32 = 0,
        heap_allocated: u32 = 0,
        scalar_replaced: u32 = 0,
        bytes_saved: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) StackAllocationOptimizer {
        return StackAllocationOptimizer{
            .allocator = allocator,
            .decisions = .{},
            .current_stack_size = 0,
            .next_stack_slot = 0,
            .stats = .{},
        };
    }

    pub fn deinit(self: *StackAllocationOptimizer) void {
        self.decisions.deinit(self.allocator);
    }

    /// 根据逃逸分析结果优化分配
    pub fn optimize(self: *StackAllocationOptimizer, analyzer: *const EscapeAnalyzer) !void {
        var iter = analyzer.escape_info_map.iterator();
        while (iter.next()) |entry| {
            const alloc_id = entry.key_ptr.*;
            const info = entry.value_ptr;

            const decision = self.makeDecision(info);
            try self.decisions.put(self.allocator, alloc_id, decision);

            self.stats.total_allocations += 1;
            switch (decision.location) {
                .stack => {
                    self.stats.stack_allocated += 1;
                    self.stats.bytes_saved += decision.estimated_size;
                },
                .scalar_replaced => {
                    self.stats.scalar_replaced += 1;
                    self.stats.bytes_saved += decision.estimated_size;
                },
                .heap => {
                    self.stats.heap_allocated += 1;
                },
            }
        }
    }

    /// 为单个分配做出决策
    fn makeDecision(self: *StackAllocationOptimizer, info: *const EscapeInfo) AllocationDecision {
        // 1. 检查是否逃逸
        if (info.state != .NoEscape) {
            return .{
                .location = .heap,
                .stack_slot = null,
                .estimated_size = info.estimated_size,
                .reason = .escapes,
            };
        }

        // 2. 检查是否可以标量替换
        if (info.isScalarReplaceable()) {
            return .{
                .location = .scalar_replaced,
                .stack_slot = null,
                .estimated_size = info.estimated_size,
                .reason = .can_scalar_replace,
            };
        }

        // 3. 估算对象大小
        const size = if (info.estimated_size > 0)
            info.estimated_size
        else switch (info.object_type) {
            .php_object => DEFAULT_OBJECT_SIZE,
            .php_array => DEFAULT_ARRAY_SIZE,
            .php_closure => DEFAULT_OBJECT_SIZE,
            .php_string => 32,
            .unknown => DEFAULT_OBJECT_SIZE,
        };

        // 4. 检查大小限制
        if (size > MAX_STACK_OBJECT_SIZE) {
            return .{
                .location = .heap,
                .stack_slot = null,
                .estimated_size = size,
                .reason = .too_large,
            };
        }

        // 5. 检查栈空间
        if (self.current_stack_size + size > MAX_STACK_FRAME_SIZE) {
            return .{
                .location = .heap,
                .stack_slot = null,
                .estimated_size = size,
                .reason = .stack_overflow,
            };
        }

        // 6. 分配栈槽位
        const slot = self.next_stack_slot;
        self.next_stack_slot += 1;
        self.current_stack_size += size;

        return .{
            .location = .stack,
            .stack_slot = slot,
            .estimated_size = size,
            .reason = .fits_on_stack,
        };
    }

    /// 获取分配决策
    pub fn getDecision(self: *const StackAllocationOptimizer, alloc_id: u32) ?AllocationDecision {
        return self.decisions.get(alloc_id);
    }

    /// 检查是否应该栈分配
    pub fn shouldStackAllocate(self: *const StackAllocationOptimizer, alloc_id: u32) bool {
        if (self.decisions.get(alloc_id)) |decision| {
            return decision.location == .stack;
        }
        return false;
    }

    /// 获取栈槽位
    pub fn getStackSlot(self: *const StackAllocationOptimizer, alloc_id: u32) ?u16 {
        if (self.decisions.get(alloc_id)) |decision| {
            return decision.stack_slot;
        }
        return null;
    }

    /// 获取统计信息
    pub fn getStats(self: *const StackAllocationOptimizer) OptimizationStats {
        return self.stats;
    }

    /// 重置优化器状态
    pub fn reset(self: *StackAllocationOptimizer) void {
        self.decisions.clearRetainingCapacity();
        self.current_stack_size = 0;
        self.next_stack_slot = 0;
        self.stats = .{};
    }
};

// ============================================================================
// 标量替换优化器
// ============================================================================

/// 标量替换优化器
/// 将不逃逸的对象分解为独立的标量变量
pub const ScalarReplacementOptimizer = struct {
    allocator: std.mem.Allocator,
    /// 替换计划
    replacement_plans: std.AutoHashMapUnmanaged(u32, ReplacementPlan),
    /// 下一个可用的局部变量槽位
    next_local_slot: u16,
    /// 统计信息
    stats: ReplacementStats,

    pub const ReplacementPlan = struct {
        /// 原始分配节点ID
        allocation_id: u32,
        /// 字段到局部变量的映射
        field_mappings: std.ArrayListUnmanaged(FieldMapping),
        /// 是否完全替换（消除分配）
        fully_replaced: bool,
        /// 替换后节省的内存
        bytes_saved: u32,
    };

    pub const FieldMapping = struct {
        /// 字段名
        field_name: []const u8,
        /// 字段类型
        field_type: DFGNode.ValueType,
        /// 分配的局部变量槽位
        local_slot: u16,
        /// 字段偏移
        offset: u32,
    };

    pub const ReplacementStats = struct {
        total_candidates: u32 = 0,
        fully_replaced: u32 = 0,
        partially_replaced: u32 = 0,
        fields_replaced: u32 = 0,
        bytes_saved: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) ScalarReplacementOptimizer {
        return ScalarReplacementOptimizer{
            .allocator = allocator,
            .replacement_plans = .{},
            .next_local_slot = 0,
            .stats = .{},
        };
    }

    pub fn deinit(self: *ScalarReplacementOptimizer) void {
        var iter = self.replacement_plans.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.field_mappings.deinit(self.allocator);
        }
        self.replacement_plans.deinit(self.allocator);
    }

    /// 分析并生成替换计划
    pub fn analyze(self: *ScalarReplacementOptimizer, analyzer: *const EscapeAnalyzer) !void {
        var iter = analyzer.escape_info_map.iterator();
        while (iter.next()) |entry| {
            const alloc_id = entry.key_ptr.*;
            const info = entry.value_ptr;

            // 只处理可标量替换的对象
            if (!info.isScalarReplaceable()) {
                continue;
            }

            self.stats.total_candidates += 1;

            // 创建替换计划
            var plan = ReplacementPlan{
                .allocation_id = alloc_id,
                .field_mappings = .{},
                .fully_replaced = true,
                .bytes_saved = info.estimated_size,
            };

            // 为每个字段分配局部变量
            for (info.scalar_fields.items) |field| {
                const slot = self.next_local_slot;
                self.next_local_slot += 1;

                try plan.field_mappings.append(self.allocator, .{
                    .field_name = field.name,
                    .field_type = field.type_tag,
                    .local_slot = slot,
                    .offset = field.offset,
                });

                self.stats.fields_replaced += 1;
            }

            if (plan.fully_replaced) {
                self.stats.fully_replaced += 1;
                self.stats.bytes_saved += info.estimated_size;
            } else {
                self.stats.partially_replaced += 1;
            }

            try self.replacement_plans.put(self.allocator, alloc_id, plan);
        }
    }

    /// 获取替换计划
    pub fn getPlan(self: *const ScalarReplacementOptimizer, alloc_id: u32) ?*const ReplacementPlan {
        return self.replacement_plans.getPtr(alloc_id);
    }

    /// 检查是否有替换计划
    pub fn hasReplacementPlan(self: *const ScalarReplacementOptimizer, alloc_id: u32) bool {
        return self.replacement_plans.contains(alloc_id);
    }

    /// 获取字段对应的局部变量槽位
    pub fn getFieldSlot(self: *const ScalarReplacementOptimizer, alloc_id: u32, field_name: []const u8) ?u16 {
        if (self.replacement_plans.getPtr(alloc_id)) |plan| {
            for (plan.field_mappings.items) |mapping| {
                if (std.mem.eql(u8, mapping.field_name, field_name)) {
                    return mapping.local_slot;
                }
            }
        }
        return null;
    }

    /// 获取统计信息
    pub fn getStats(self: *const ScalarReplacementOptimizer) ReplacementStats {
        return self.stats;
    }

    /// 重置优化器状态
    pub fn reset(self: *ScalarReplacementOptimizer) void {
        var iter = self.replacement_plans.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.field_mappings.deinit(self.allocator);
        }
        self.replacement_plans.clearRetainingCapacity();
        self.next_local_slot = 0;
        self.stats = .{};
    }
};

// ============================================================================
// 优化结果
// ============================================================================

/// 逃逸分析和优化的综合结果
pub const OptimizationResult = struct {
    /// 逃逸分析器
    escape_analyzer: *EscapeAnalyzer,
    /// 栈分配优化器
    stack_optimizer: StackAllocationOptimizer,
    /// 标量替换优化器
    scalar_optimizer: ScalarReplacementOptimizer,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, analyzer: *EscapeAnalyzer) OptimizationResult {
        return OptimizationResult{
            .escape_analyzer = analyzer,
            .stack_optimizer = StackAllocationOptimizer.init(allocator),
            .scalar_optimizer = ScalarReplacementOptimizer.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OptimizationResult) void {
        self.stack_optimizer.deinit();
        self.scalar_optimizer.deinit();
    }

    /// 执行所有优化
    pub fn optimize(self: *OptimizationResult) !void {
        // 1. 栈分配优化
        try self.stack_optimizer.optimize(self.escape_analyzer);

        // 2. 标量替换优化
        try self.scalar_optimizer.analyze(self.escape_analyzer);
    }

    /// 获取分配的最佳位置
    pub fn getAllocationLocation(self: *const OptimizationResult, alloc_id: u32) StackAllocationOptimizer.AllocationLocation {
        if (self.stack_optimizer.getDecision(alloc_id)) |decision| {
            return decision.location;
        }
        return .heap;
    }

    /// 生成综合报告
    pub fn generateReport(self: *const OptimizationResult, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        const writer = buffer.writer(allocator);

        const escape_stats = self.escape_analyzer.getStats();
        const stack_stats = self.stack_optimizer.getStats();
        const scalar_stats = self.scalar_optimizer.getStats();

        try writer.print("=== Optimization Report ===\n\n", .{});

        try writer.print("Escape Analysis:\n", .{});
        try writer.print("  Total allocations: {}\n", .{escape_stats.total_allocations});
        try writer.print("  No escape: {}\n", .{escape_stats.no_escape_count});
        try writer.print("  Arg escape: {}\n", .{escape_stats.arg_escape_count});
        try writer.print("  Global escape: {}\n", .{escape_stats.global_escape_count});

        try writer.print("\nStack Allocation:\n", .{});
        try writer.print("  Stack allocated: {}\n", .{stack_stats.stack_allocated});
        try writer.print("  Heap allocated: {}\n", .{stack_stats.heap_allocated});
        try writer.print("  Bytes saved: {}\n", .{stack_stats.bytes_saved});

        try writer.print("\nScalar Replacement:\n", .{});
        try writer.print("  Candidates: {}\n", .{scalar_stats.total_candidates});
        try writer.print("  Fully replaced: {}\n", .{scalar_stats.fully_replaced});
        try writer.print("  Fields replaced: {}\n", .{scalar_stats.fields_replaced});
        try writer.print("  Bytes saved: {}\n", .{scalar_stats.bytes_saved});

        const total_saved = stack_stats.bytes_saved + scalar_stats.bytes_saved;
        try writer.print("\nTotal memory saved: {} bytes\n", .{total_saved});

        return buffer.toOwnedSlice(allocator);
    }
};


// ============================================================================
// 单元测试
// ============================================================================

test "EscapeState merge" {
    const testing = std.testing;

    // NoEscape合并任何状态都取更高级别
    try testing.expectEqual(EscapeState.NoEscape, EscapeState.NoEscape.merge(.NoEscape));
    try testing.expectEqual(EscapeState.ArgEscape, EscapeState.NoEscape.merge(.ArgEscape));
    try testing.expectEqual(EscapeState.GlobalEscape, EscapeState.NoEscape.merge(.GlobalEscape));

    // ArgEscape合并
    try testing.expectEqual(EscapeState.ArgEscape, EscapeState.ArgEscape.merge(.NoEscape));
    try testing.expectEqual(EscapeState.ArgEscape, EscapeState.ArgEscape.merge(.ArgEscape));
    try testing.expectEqual(EscapeState.GlobalEscape, EscapeState.ArgEscape.merge(.GlobalEscape));

    // GlobalEscape是最高级别
    try testing.expectEqual(EscapeState.GlobalEscape, EscapeState.GlobalEscape.merge(.NoEscape));
    try testing.expectEqual(EscapeState.GlobalEscape, EscapeState.GlobalEscape.merge(.ArgEscape));
    try testing.expectEqual(EscapeState.GlobalEscape, EscapeState.GlobalEscape.merge(.GlobalEscape));
}

test "EscapeState canStackAllocate" {
    const testing = std.testing;

    try testing.expect(EscapeState.NoEscape.canStackAllocate());
    try testing.expect(!EscapeState.ArgEscape.canStackAllocate());
    try testing.expect(!EscapeState.GlobalEscape.canStackAllocate());
    try testing.expect(!EscapeState.Unknown.canStackAllocate());
}

test "DataFlowGraph basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var dfg = DataFlowGraph.init(allocator);
    defer dfg.deinit();

    // 添加节点
    const node1 = try dfg.addNode(.allocation);
    const node2 = try dfg.addNode(.local_var);
    const node3 = try dfg.addNode(.return_value);

    try testing.expectEqual(@as(u32, 0), node1);
    try testing.expectEqual(@as(u32, 1), node2);
    try testing.expectEqual(@as(u32, 2), node3);
    try testing.expectEqual(@as(usize, 3), dfg.nodeCount());

    // 添加边
    try dfg.addEdge(node2, node1, .points_to);
    try dfg.addEdge(node3, node2, .def_use);

    try testing.expectEqual(@as(usize, 2), dfg.edgeCount());

    // 获取节点
    const n1 = dfg.getNode(node1);
    try testing.expect(n1 != null);
    try testing.expectEqual(DFGNode.NodeKind.allocation, n1.?.kind);

    // 设置逃逸状态
    dfg.setEscapeState(node1, .NoEscape);
    try testing.expectEqual(EscapeState.NoEscape, dfg.getNode(node1).?.escape_state);

    // 变量绑定
    try dfg.bindVariable("test_var", node2);
    try testing.expectEqual(node2, dfg.lookupVariable("test_var").?);
}

test "DataFlowGraph edge queries" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var dfg = DataFlowGraph.init(allocator);
    defer dfg.deinit();

    const node1 = try dfg.addNode(.allocation);
    const node2 = try dfg.addNode(.local_var);
    const node3 = try dfg.addNode(.field_load);

    try dfg.addEdge(node2, node1, .points_to);
    try dfg.addEdge(node3, node1, .field_of);

    // 获取入边
    const incoming = try dfg.getIncomingEdges(allocator, node1);
    defer allocator.free(incoming);
    try testing.expectEqual(@as(usize, 2), incoming.len);

    // 获取出边
    const outgoing = try dfg.getOutgoingEdges(allocator, node2);
    defer allocator.free(outgoing);
    try testing.expectEqual(@as(usize, 1), outgoing.len);
    try testing.expectEqual(node1, outgoing[0].to);
}

test "DataFlowGraph getAllocationNodes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var dfg = DataFlowGraph.init(allocator);
    defer dfg.deinit();

    _ = try dfg.addNode(.allocation);
    _ = try dfg.addNode(.local_var);
    _ = try dfg.addNode(.allocation);
    _ = try dfg.addNode(.parameter);

    const allocs = try dfg.getAllocationNodes(allocator);
    defer allocator.free(allocs);

    try testing.expectEqual(@as(usize, 2), allocs.len);
}

test "EscapeInfo basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var info = EscapeInfo.init();
    defer info.deinit(allocator);

    try testing.expectEqual(EscapeState.Unknown, info.state);
    try testing.expect(!info.can_scalar_replace);

    // 添加逃逸点
    try info.addEscapePoint(allocator, .{
        .location = .{ .line = 10, .column = 5 },
        .reason = .returned,
        .node_id = 42,
    });

    try testing.expectEqual(@as(usize, 1), info.escape_points.items.len);
    try testing.expectEqual(EscapeReason.returned, info.escape_points.items[0].reason);
}

test "EscapeAnalyzer initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    try testing.expectEqual(@as(usize, 0), analyzer.dfg.nodeCount());
    try testing.expectEqual(@as(u32, 0), analyzer.stats.total_allocations);
}

test "EscapeAnalyzer stats" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    // 手动添加一些节点来测试统计
    const alloc1 = try analyzer.dfg.addNode(.allocation);
    const alloc2 = try analyzer.dfg.addNode(.allocation);

    var info1 = EscapeInfo.init();
    info1.state = .NoEscape;
    try analyzer.escape_info_map.put(allocator, alloc1, info1);

    var info2 = EscapeInfo.init();
    info2.state = .GlobalEscape;
    try analyzer.escape_info_map.put(allocator, alloc2, info2);

    analyzer.stats.total_allocations = 2;
    analyzer.updateStats();

    try testing.expectEqual(@as(u32, 1), analyzer.stats.no_escape_count);
    try testing.expectEqual(@as(u32, 1), analyzer.stats.global_escape_count);
}

test "EscapeAnalyzer canStackAllocate" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    const alloc1 = try analyzer.dfg.addNode(.allocation);
    const alloc2 = try analyzer.dfg.addNode(.allocation);

    var info1 = EscapeInfo.init();
    info1.state = .NoEscape;
    try analyzer.escape_info_map.put(allocator, alloc1, info1);

    var info2 = EscapeInfo.init();
    info2.state = .GlobalEscape;
    try analyzer.escape_info_map.put(allocator, alloc2, info2);

    try testing.expect(analyzer.canStackAllocate(alloc1));
    try testing.expect(!analyzer.canStackAllocate(alloc2));
    try testing.expect(!analyzer.canStackAllocate(999)); // 不存在的节点
}

test "EscapeAnalyzer generateReport" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    analyzer.stats.total_allocations = 10;
    analyzer.stats.no_escape_count = 5;
    analyzer.stats.arg_escape_count = 2;
    analyzer.stats.global_escape_count = 3;
    analyzer.stats.scalar_replaceable_count = 3;
    analyzer.stats.analysis_time_ns = 1000;

    const report = try analyzer.generateReport(allocator);
    defer allocator.free(report);

    // 验证报告包含关键信息
    try testing.expect(std.mem.indexOf(u8, report, "Total allocations: 10") != null);
    try testing.expect(std.mem.indexOf(u8, report, "No escape: 5") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Scalar replaceable: 3") != null);
}

// ============================================================================
// 栈分配优化器测试
// ============================================================================

test "StackAllocationOptimizer initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var optimizer = StackAllocationOptimizer.init(allocator);
    defer optimizer.deinit();

    try testing.expectEqual(@as(u32, 0), optimizer.current_stack_size);
    try testing.expectEqual(@as(u16, 0), optimizer.next_stack_slot);
    try testing.expectEqual(@as(u32, 0), optimizer.stats.total_allocations);
}

test "StackAllocationOptimizer decision making" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    // 添加一个不逃逸的小对象
    const alloc1 = try analyzer.dfg.addNode(.allocation);
    var info1 = EscapeInfo.init();
    info1.state = .NoEscape;
    info1.estimated_size = 64;
    info1.object_type = .php_object;
    try analyzer.escape_info_map.put(allocator, alloc1, info1);

    // 添加一个逃逸的对象
    const alloc2 = try analyzer.dfg.addNode(.allocation);
    var info2 = EscapeInfo.init();
    info2.state = .GlobalEscape;
    info2.estimated_size = 64;
    try analyzer.escape_info_map.put(allocator, alloc2, info2);

    // 添加一个太大的对象
    const alloc3 = try analyzer.dfg.addNode(.allocation);
    var info3 = EscapeInfo.init();
    info3.state = .NoEscape;
    info3.estimated_size = 512; // 超过MAX_STACK_OBJECT_SIZE
    try analyzer.escape_info_map.put(allocator, alloc3, info3);

    var optimizer = StackAllocationOptimizer.init(allocator);
    defer optimizer.deinit();

    try optimizer.optimize(&analyzer);

    // 验证决策
    const decision1 = optimizer.getDecision(alloc1);
    try testing.expect(decision1 != null);
    try testing.expectEqual(StackAllocationOptimizer.AllocationLocation.stack, decision1.?.location);
    try testing.expectEqual(StackAllocationOptimizer.DecisionReason.fits_on_stack, decision1.?.reason);

    const decision2 = optimizer.getDecision(alloc2);
    try testing.expect(decision2 != null);
    try testing.expectEqual(StackAllocationOptimizer.AllocationLocation.heap, decision2.?.location);
    try testing.expectEqual(StackAllocationOptimizer.DecisionReason.escapes, decision2.?.reason);

    const decision3 = optimizer.getDecision(alloc3);
    try testing.expect(decision3 != null);
    try testing.expectEqual(StackAllocationOptimizer.AllocationLocation.heap, decision3.?.location);
    try testing.expectEqual(StackAllocationOptimizer.DecisionReason.too_large, decision3.?.reason);

    // 验证统计
    try testing.expectEqual(@as(u32, 3), optimizer.stats.total_allocations);
    try testing.expectEqual(@as(u32, 1), optimizer.stats.stack_allocated);
    try testing.expectEqual(@as(u32, 2), optimizer.stats.heap_allocated);
}

test "StackAllocationOptimizer stack slot allocation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    // 添加多个可栈分配的对象
    for (0..3) |i| {
        const alloc_id = try analyzer.dfg.addNode(.allocation);
        var info = EscapeInfo.init();
        info.state = .NoEscape;
        info.estimated_size = 32;
        try analyzer.escape_info_map.put(allocator, @intCast(alloc_id), info);
        _ = i;
    }

    var optimizer = StackAllocationOptimizer.init(allocator);
    defer optimizer.deinit();

    try optimizer.optimize(&analyzer);

    // 验证栈槽位分配
    try testing.expectEqual(@as(u16, 3), optimizer.next_stack_slot);
    try testing.expectEqual(@as(u32, 96), optimizer.current_stack_size); // 3 * 32
}

// ============================================================================
// 标量替换优化器测试
// ============================================================================

test "ScalarReplacementOptimizer initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var optimizer = ScalarReplacementOptimizer.init(allocator);
    defer optimizer.deinit();

    try testing.expectEqual(@as(u16, 0), optimizer.next_local_slot);
    try testing.expectEqual(@as(u32, 0), optimizer.stats.total_candidates);
}

test "ScalarReplacementOptimizer analysis" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    // 添加一个可标量替换的对象
    const alloc1 = try analyzer.dfg.addNode(.allocation);
    var info1 = EscapeInfo.init();
    info1.state = .NoEscape;
    info1.can_scalar_replace = true;
    info1.estimated_size = 64;

    // 添加字段
    try info1.addScalarField(allocator, .{
        .name = "x",
        .type_tag = .integer,
        .local_slot = 0,
        .offset = 0,
    });
    try info1.addScalarField(allocator, .{
        .name = "y",
        .type_tag = .integer,
        .local_slot = 0,
        .offset = 8,
    });

    try analyzer.escape_info_map.put(allocator, alloc1, info1);

    var optimizer = ScalarReplacementOptimizer.init(allocator);
    defer optimizer.deinit();

    try optimizer.analyze(&analyzer);

    // 验证替换计划
    const plan = optimizer.getPlan(alloc1);
    try testing.expect(plan != null);
    try testing.expect(plan.?.fully_replaced);
    try testing.expectEqual(@as(usize, 2), plan.?.field_mappings.items.len);

    // 验证统计
    try testing.expectEqual(@as(u32, 1), optimizer.stats.total_candidates);
    try testing.expectEqual(@as(u32, 1), optimizer.stats.fully_replaced);
    try testing.expectEqual(@as(u32, 2), optimizer.stats.fields_replaced);
}

test "ScalarReplacementOptimizer field slot lookup" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    const alloc1 = try analyzer.dfg.addNode(.allocation);
    var info1 = EscapeInfo.init();
    info1.state = .NoEscape;
    info1.can_scalar_replace = true;
    info1.estimated_size = 32;

    try info1.addScalarField(allocator, .{
        .name = "field1",
        .type_tag = .integer,
        .local_slot = 0,
        .offset = 0,
    });

    try analyzer.escape_info_map.put(allocator, alloc1, info1);

    var optimizer = ScalarReplacementOptimizer.init(allocator);
    defer optimizer.deinit();

    try optimizer.analyze(&analyzer);

    // 查找字段槽位
    const slot = optimizer.getFieldSlot(alloc1, "field1");
    try testing.expect(slot != null);
    try testing.expectEqual(@as(u16, 0), slot.?);

    // 查找不存在的字段
    const no_slot = optimizer.getFieldSlot(alloc1, "nonexistent");
    try testing.expect(no_slot == null);
}

// ============================================================================
// 优化结果测试
// ============================================================================

test "OptimizationResult comprehensive" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    // 添加测试数据
    const alloc1 = try analyzer.dfg.addNode(.allocation);
    var info1 = EscapeInfo.init();
    info1.state = .NoEscape;
    info1.estimated_size = 64;
    try analyzer.escape_info_map.put(allocator, alloc1, info1);

    analyzer.stats.total_allocations = 1;
    analyzer.stats.no_escape_count = 1;

    var result = OptimizationResult.init(allocator, &analyzer);
    defer result.deinit();

    try result.optimize();

    // 验证分配位置
    const location = result.getAllocationLocation(alloc1);
    try testing.expectEqual(StackAllocationOptimizer.AllocationLocation.stack, location);

    // 生成报告
    const report = try result.generateReport(allocator);
    defer allocator.free(report);

    try testing.expect(std.mem.indexOf(u8, report, "Optimization Report") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Stack allocated:") != null);
}

test "EscapeInfo isStackAllocatable" {
    var info = EscapeInfo.init();

    // 不逃逸且大小合适
    info.state = .NoEscape;
    info.estimated_size = 64;
    try std.testing.expect(info.isStackAllocatable());

    // 逃逸
    info.state = .GlobalEscape;
    try std.testing.expect(!info.isStackAllocatable());

    // 太大
    info.state = .NoEscape;
    info.estimated_size = 1024;
    try std.testing.expect(!info.isStackAllocatable());

    // 大小为0
    info.estimated_size = 0;
    try std.testing.expect(!info.isStackAllocatable());
}

// ============================================================================
// SSA转换测试
// ============================================================================

test "DataFlowGraph SSA version management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var dfg = DataFlowGraph.init(allocator);
    defer dfg.deinit();

    // 测试版本获取和创建
    try testing.expectEqual(@as(u32, 0), dfg.getSSAVersion("x"));

    const v1 = try dfg.newSSAVersion("x");
    try testing.expectEqual(@as(u32, 1), v1);
    try testing.expectEqual(@as(u32, 1), dfg.getSSAVersion("x"));

    const v2 = try dfg.newSSAVersion("x");
    try testing.expectEqual(@as(u32, 2), v2);
    try testing.expectEqual(@as(u32, 2), dfg.getSSAVersion("x"));

    // 不同变量独立版本
    const y1 = try dfg.newSSAVersion("y");
    try testing.expectEqual(@as(u32, 1), y1);
}

test "DataFlowGraph basic block creation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var dfg = DataFlowGraph.init(allocator);
    defer dfg.deinit();

    // 创建基本块
    const block0 = try dfg.createBasicBlock();
    const block1 = try dfg.createBasicBlock();
    const block2 = try dfg.createBasicBlock();

    try testing.expectEqual(@as(u32, 0), block0);
    try testing.expectEqual(@as(u32, 1), block1);
    try testing.expectEqual(@as(u32, 2), block2);
    try testing.expectEqual(@as(usize, 3), dfg.basicBlockCount());

    // 添加控制流边
    try dfg.addControlFlowEdge(block0, block1);
    try dfg.addControlFlowEdge(block0, block2);
    try dfg.addControlFlowEdge(block1, block2);

    // 验证前驱和后继
    const b0 = dfg.getBasicBlock(block0);
    try testing.expect(b0 != null);
    try testing.expectEqual(@as(usize, 2), b0.?.successors.items.len);

    const b2 = dfg.getBasicBlock(block2);
    try testing.expect(b2 != null);
    try testing.expectEqual(@as(usize, 2), b2.?.predecessors.items.len);
}

test "DataFlowGraph phi node insertion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var dfg = DataFlowGraph.init(allocator);
    defer dfg.deinit();

    // 创建基本块
    const block0 = try dfg.createBasicBlock();
    const block1 = try dfg.createBasicBlock();
    const block2 = try dfg.createBasicBlock();

    // 添加控制流边 (block0 -> block1, block0 -> block2, block1 -> block2, block2 -> block2)
    try dfg.addControlFlowEdge(block0, block1);
    try dfg.addControlFlowEdge(block0, block2);
    try dfg.addControlFlowEdge(block1, block2);

    // 设置块的出口版本
    if (dfg.getBasicBlock(block0)) |b| {
        try b.exit_versions.put(allocator, "x", 1);
    }
    if (dfg.getBasicBlock(block1)) |b| {
        try b.exit_versions.put(allocator, "x", 2);
    }

    // 插入phi节点
    const phi_node = try dfg.insertPhiNode(block2, "x");
    // phi_node 可以是 0（第一个节点），所以只检查它是有效的
    try testing.expectEqual(@as(usize, 1), dfg.phiNodeCount());

    // 验证phi节点
    const phi = dfg.phi_nodes.items[0];
    try testing.expectEqual(phi_node, phi.node_id);
    try testing.expect(std.mem.eql(u8, "x", phi.variable));
}

test "DataFlowGraph SSA form conversion" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var dfg = DataFlowGraph.init(allocator);
    defer dfg.deinit();

    // 创建简单的控制流图
    const block0 = try dfg.createBasicBlock();
    _ = block0;

    // 添加一些节点
    const node1 = try dfg.addNode(.local_var);
    try dfg.bindVariable("x", node1);

    // 转换为SSA形式
    try dfg.convertToSSA();

    try testing.expect(dfg.isSSAForm());
}

test "BasicBlock operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var block = DataFlowGraph.BasicBlock.init(0);
    defer block.deinit(allocator);

    // 添加节点
    try block.addNode(allocator, 1);
    try block.addNode(allocator, 2);
    try testing.expectEqual(@as(usize, 2), block.nodes.items.len);

    // 添加前驱和后继
    try block.addPredecessor(allocator, 10);
    try block.addSuccessor(allocator, 20);
    try testing.expectEqual(@as(usize, 1), block.predecessors.items.len);
    try testing.expectEqual(@as(usize, 1), block.successors.items.len);
}

test "PhiNode operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var phi = DataFlowGraph.PhiNode.init(1, "x", 3);
    defer phi.deinit(allocator);

    try phi.addSource(allocator, 0, 1, 10);
    try phi.addSource(allocator, 1, 2, 20);

    try testing.expectEqual(@as(usize, 2), phi.sources.items.len);
    try testing.expectEqual(@as(u32, 0), phi.sources.items[0].block_id);
    try testing.expectEqual(@as(u32, 1), phi.sources.items[0].version);
}
