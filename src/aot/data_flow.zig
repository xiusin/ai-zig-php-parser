const std = @import("std");
const Allocator = std.mem.Allocator;

/// 控制流图（CFG）
pub const ControlFlowGraph = struct {
    allocator: Allocator,
    /// 所有基本块
    basic_blocks: std.ArrayList(*BasicBlock),
    /// 入口基本块
    entry: ?*BasicBlock,
    /// 出口基本块
    exit: ?*BasicBlock,
    /// 支配树
    dominator_tree: ?DominatorTree,

    pub fn init(allocator: Allocator) !ControlFlowGraph {
        return .{
            .allocator = allocator,
            .basic_blocks = try std.ArrayList(*BasicBlock).initCapacity(allocator, 0),
            .entry = null,
            .exit = null,
            .dominator_tree = null,
        };
    }

    pub fn deinit(self: *ControlFlowGraph) void {
        for (self.basic_blocks.items) |bb| {
            bb.deinit();
            self.allocator.destroy(bb);
        }
        self.basic_blocks.deinit(self.allocator);

        if (self.dominator_tree) |*dt| {
            dt.deinit();
        }
    }

    /// 创建新的基本块
    pub fn createBasicBlock(self: *ControlFlowGraph, name: []const u8) !*BasicBlock {
        const bb = try self.allocator.create(BasicBlock);
        bb.* = try BasicBlock.init(self.allocator, name, self.basic_blocks.items.len);
        try self.basic_blocks.append(self.allocator, bb);
        return bb;
    }

    /// 添加控制流边
    pub fn addEdge(self: *ControlFlowGraph, from: *BasicBlock, to: *BasicBlock) !void {
        _ = self;
        try from.successors.append(from.allocator, to);
        try to.predecessors.append(to.allocator, from);
    }

    /// 构建支配树
    pub fn buildDominatorTree(self: *ControlFlowGraph) !void {
        if (self.entry == null) return error.NoEntryBlock;

        var dt = try DominatorTree.init(self.allocator, self);
        try dt.compute();
        self.dominator_tree = dt;
    }

    /// 执行数据流分析
    pub fn analyzeDataFlow(self: *ControlFlowGraph, analysis: DataFlowAnalysis) !void {
        switch (analysis) {
            .reaching_definitions => try self.reachingDefinitions(),
            .liveness => try self.livenessAnalysis(),
            .available_expressions => try self.availableExpressions(),
        }
    }

    /// 到达定义分析
    fn reachingDefinitions(self: *ControlFlowGraph) !void {
        // 初始化 Gen/Kill 集合
        for (self.basic_blocks.items) |bb| {
            try bb.computeGenKillForReachingDefs();
        }

        // 迭代求解数据流方程
        var changed = true;
        while (changed) {
            changed = false;

            for (self.basic_blocks.items) |bb| {
                // IN[B] = ∪ OUT[P] for all predecessors P
                var new_in = std.AutoHashMap(*Definition, void).init(self.allocator);
                defer new_in.deinit();

                for (bb.predecessors.items) |pred| {
                    var it = pred.out_defs.keyIterator();
                    while (it.next()) |def| {
                        try new_in.put(def.*, {});
                    }
                }

                // OUT[B] = Gen[B] ∪ (IN[B] - Kill[B])
                var new_out = std.AutoHashMap(*Definition, void).init(self.allocator);
                defer new_out.deinit();

                // 添加 Gen[B]
                var gen_it = bb.gen_defs.keyIterator();
                while (gen_it.next()) |def| {
                    try new_out.put(def.*, {});
                }

                // 添加 IN[B] - Kill[B]
                var in_it = new_in.keyIterator();
                while (in_it.next()) |def| {
                    if (!bb.kill_defs.contains(def.*)) {
                        try new_out.put(def.*, {});
                    }
                }

                // 检查是否改变
                if (new_out.count() != bb.out_defs.count()) {
                    changed = true;
                }

                // 更新 IN/OUT
                bb.in_defs.deinit();
                bb.in_defs = new_in.move();
                bb.out_defs.deinit();
                bb.out_defs = new_out.move();
            }
        }
    }

    /// 活跃变量分析（反向数据流）
    fn livenessAnalysis(self: *ControlFlowGraph) !void {
        // 初始化 Use/Def 集合
        for (self.basic_blocks.items) |bb| {
            try bb.computeUseDefForLiveness();
        }

        // 反向迭代求解
        var changed = true;
        while (changed) {
            changed = false;

            // 反向遍历基本块
            var i: usize = self.basic_blocks.items.len;
            while (i > 0) {
                i -= 1;
                const bb = self.basic_blocks.items[i];

                // OUT[B] = ∪ IN[S] for all successors S
                var new_out = std.AutoHashMap(*Variable, void).init(self.allocator);
                defer new_out.deinit();

                for (bb.successors.items) |succ| {
                    var it = succ.in_vars.keyIterator();
                    while (it.next()) |var_ptr| {
                        try new_out.put(var_ptr.*, {});
                    }
                }

                // IN[B] = Use[B] ∪ (OUT[B] - Def[B])
                var new_in = std.AutoHashMap(*Variable, void).init(self.allocator);
                defer new_in.deinit();

                // 添加 Use[B]
                var use_it = bb.use_vars.keyIterator();
                while (use_it.next()) |var_ptr| {
                    try new_in.put(var_ptr.*, {});
                }

                // 添加 OUT[B] - Def[B]
                var out_it = new_out.keyIterator();
                while (out_it.next()) |var_ptr| {
                    if (!bb.def_vars.contains(var_ptr.*)) {
                        try new_in.put(var_ptr.*, {});
                    }
                }

                // 检查是否改变
                if (new_in.count() != bb.in_vars.count()) {
                    changed = true;
                }

                // 更新 IN/OUT
                bb.in_vars.deinit();
                bb.in_vars = new_in.move();
                bb.out_vars.deinit();
                bb.out_vars = new_out.move();
            }
        }
    }

    /// 可用表达式分析
    fn availableExpressions(self: *ControlFlowGraph) !void {
        // 初始化 Gen/Kill 集合
        for (self.basic_blocks.items) |bb| {
            try bb.computeGenKillForAvailableExprs();
        }

        // 初始化：entry 的 IN 为空，其他为全集
        const entry = self.entry orelse return error.NoEntryBlock;

        // 收集所有表达式
        var all_exprs = std.AutoHashMap(*Expression, void).init(self.allocator);
        defer all_exprs.deinit();

        for (self.basic_blocks.items) |bb| {
            var it = bb.gen_exprs.keyIterator();
            while (it.next()) |expr| {
                try all_exprs.put(expr.*, {});
            }
        }

        // 初始化所有块（除 entry）为全集
        for (self.basic_blocks.items) |bb| {
            if (bb != entry) {
                var it = all_exprs.keyIterator();
                while (it.next()) |expr| {
                    try bb.in_exprs.put(expr.*, {});
                }
            }
        }

        // 迭代求解
        var changed = true;
        while (changed) {
            changed = false;

            for (self.basic_blocks.items) |bb| {
                if (bb == entry) continue;

                // IN[B] = ∩ OUT[P] for all predecessors P
                var new_in = std.AutoHashMap(*Expression, void).init(self.allocator);
                defer new_in.deinit();

                if (bb.predecessors.items.len > 0) {
                    // 从第一个前驱开始
                    const first_pred = bb.predecessors.items[0];
                    var it = first_pred.out_exprs.keyIterator();
                    while (it.next()) |expr| {
                        try new_in.put(expr.*, {});
                    }

                    // 与其他前驱求交集
                    for (bb.predecessors.items[1..]) |pred| {
                        var to_remove = try std.ArrayList(*Expression).initCapacity(self.allocator, 0);
                        defer to_remove.deinit(self.allocator);

                        var in_it = new_in.keyIterator();
                        while (in_it.next()) |expr| {
                            if (!pred.out_exprs.contains(expr.*)) {
                                try to_remove.append(self.allocator, expr.*);
                            }
                        }

                        for (to_remove.items) |expr| {
                            _ = new_in.remove(expr);
                        }
                    }
                }

                // OUT[B] = Gen[B] ∪ (IN[B] - Kill[B])
                var new_out = std.AutoHashMap(*Expression, void).init(self.allocator);
                defer new_out.deinit();

                // 添加 Gen[B]
                var gen_it = bb.gen_exprs.keyIterator();
                while (gen_it.next()) |expr| {
                    try new_out.put(expr.*, {});
                }

                // 添加 IN[B] - Kill[B]
                var in_it = new_in.keyIterator();
                while (in_it.next()) |expr| {
                    if (!bb.kill_exprs.contains(expr.*)) {
                        try new_out.put(expr.*, {});
                    }
                }

                // 检查是否改变
                if (new_in.count() != bb.in_exprs.count()) {
                    changed = true;
                }

                // 更新 IN/OUT
                bb.in_exprs.deinit();
                bb.in_exprs = new_in.move();
                bb.out_exprs.deinit();
                bb.out_exprs = new_out.move();
            }
        }
    }
};

/// 基本块
pub const BasicBlock = struct {
    allocator: Allocator,
    /// 基本块名称
    name: []const u8,
    /// 基本块 ID
    id: usize,
    /// 指令列表
    instructions: std.ArrayList(*Instruction),
    /// 前驱基本块
    predecessors: std.ArrayList(*BasicBlock),
    /// 后继基本块
    successors: std.ArrayList(*BasicBlock),
    /// 支配者
    dominator: ?*BasicBlock,

    // 到达定义分析
    gen_defs: std.AutoHashMap(*Definition, void),
    kill_defs: std.AutoHashMap(*Definition, void),
    in_defs: std.AutoHashMap(*Definition, void),
    out_defs: std.AutoHashMap(*Definition, void),

    // 活跃变量分析
    use_vars: std.AutoHashMap(*Variable, void),
    def_vars: std.AutoHashMap(*Variable, void),
    in_vars: std.AutoHashMap(*Variable, void),
    out_vars: std.AutoHashMap(*Variable, void),

    // 可用表达式分析
    gen_exprs: std.AutoHashMap(*Expression, void),
    kill_exprs: std.AutoHashMap(*Expression, void),
    in_exprs: std.AutoHashMap(*Expression, void),
    out_exprs: std.AutoHashMap(*Expression, void),

    pub fn init(allocator: Allocator, name: []const u8, id: usize) !BasicBlock {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .id = id,
            .instructions = try std.ArrayList(*Instruction).initCapacity(allocator, 0),
            .predecessors = try std.ArrayList(*BasicBlock).initCapacity(allocator, 0),
            .successors = try std.ArrayList(*BasicBlock).initCapacity(allocator, 0),
            .dominator = null,
            .gen_defs = std.AutoHashMap(*Definition, void).init(allocator),
            .kill_defs = std.AutoHashMap(*Definition, void).init(allocator),
            .in_defs = std.AutoHashMap(*Definition, void).init(allocator),
            .out_defs = std.AutoHashMap(*Definition, void).init(allocator),
            .use_vars = std.AutoHashMap(*Variable, void).init(allocator),
            .def_vars = std.AutoHashMap(*Variable, void).init(allocator),
            .in_vars = std.AutoHashMap(*Variable, void).init(allocator),
            .out_vars = std.AutoHashMap(*Variable, void).init(allocator),
            .gen_exprs = std.AutoHashMap(*Expression, void).init(allocator),
            .kill_exprs = std.AutoHashMap(*Expression, void).init(allocator),
            .in_exprs = std.AutoHashMap(*Expression, void).init(allocator),
            .out_exprs = std.AutoHashMap(*Expression, void).init(allocator),
        };
    }

    pub fn deinit(self: *BasicBlock) void {
        self.allocator.free(self.name);

        for (self.instructions.items) |inst| {
            inst.deinit();
            self.allocator.destroy(inst);
        }
        self.instructions.deinit(self.allocator);

        self.predecessors.deinit(self.allocator);
        self.successors.deinit(self.allocator);

        self.gen_defs.deinit();
        self.kill_defs.deinit();
        self.in_defs.deinit();
        self.out_defs.deinit();

        self.use_vars.deinit();
        self.def_vars.deinit();
        self.in_vars.deinit();
        self.out_vars.deinit();

        self.gen_exprs.deinit();
        self.kill_exprs.deinit();
        self.in_exprs.deinit();
        self.out_exprs.deinit();
    }

    /// 添加指令
    pub fn addInstruction(self: *BasicBlock, inst: *Instruction) !void {
        try self.instructions.append(self.allocator, inst);
    }

    /// 计算到达定义的 Gen/Kill 集合
    fn computeGenKillForReachingDefs(self: *BasicBlock) !void {
        for (self.instructions.items) |inst| {
            if (inst.def) |def| {
                // Gen: 此基本块生成的定义
                try self.gen_defs.put(def, {});

                // Kill: 此定义杀死的其他定义（同一变量的其他定义）
                // 这里简化处理，实际需要全局变量信息
            }
        }
    }

    /// 计算活跃变量的 Use/Def 集合
    fn computeUseDefForLiveness(self: *BasicBlock) !void {
        // 反向遍历指令
        var i: usize = self.instructions.items.len;
        while (i > 0) {
            i -= 1;
            const inst = self.instructions.items[i];

            // Use: 在定义之前使用的变量
            for (inst.uses) |use_var| {
                if (!self.def_vars.contains(use_var)) {
                    try self.use_vars.put(use_var, {});
                }
            }

            // Def: 此基本块定义的变量
            if (inst.def) |def| {
                if (def.variable) |var_ptr| {
                    try self.def_vars.put(var_ptr, {});
                }
            }
        }
    }

    /// 计算可用表达式的 Gen/Kill 集合
    fn computeGenKillForAvailableExprs(self: *BasicBlock) !void {
        for (self.instructions.items) |inst| {
            if (inst.expression) |expr| {
                // Gen: 此基本块计算的表达式
                try self.gen_exprs.put(expr, {});
            }

            // Kill: 此指令杀死的表达式（修改了表达式中的变量）
            if (inst.def) |def| {
                if (def.variable) |var_ptr| {
                    // 杀死所有包含此变量的表达式
                    // 这里简化处理
                    _ = var_ptr;
                }
            }
        }
    }
};

/// 指令
pub const Instruction = struct {
    allocator: Allocator,
    /// 操作码
    opcode: Opcode,
    /// 定义的变量
    def: ?*Definition,
    /// 使用的变量
    uses: []*Variable,
    /// 表达式（用于可用表达式分析）
    expression: ?*Expression,

    pub fn init(allocator: Allocator, opcode: Opcode) !Instruction {
        return .{
            .allocator = allocator,
            .opcode = opcode,
            .def = null,
            .uses = &[_]*Variable{},
            .expression = null,
        };
    }

    pub fn deinit(self: *Instruction) void {
        _ = self;
    }
};

/// 操作码
pub const Opcode = enum {
    add,
    sub,
    mul,
    div,
    load,
    store,
    branch,
    jump,
    ret,
    call,
    phi,
};

/// 定义
pub const Definition = struct {
    variable: ?*Variable,
    instruction: *Instruction,
    basic_block: *BasicBlock,
};

/// 变量
pub const Variable = struct {
    name: []const u8,
    id: usize,

    pub fn hash(self: Variable) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(self.name);
        hasher.update(std.mem.asBytes(&self.id));
        return hasher.final();
    }

    pub fn eql(a: Variable, b: Variable) bool {
        return std.mem.eql(u8, a.name, b.name) and a.id == b.id;
    }
};

/// 表达式
pub const Expression = struct {
    op: ExprOp,
    operands: []const *Variable,

    pub fn hash(self: Expression) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.op));
        for (self.operands) |operand| {
            hasher.update(std.mem.asBytes(&operand.id));
        }
        return hasher.final();
    }

    pub fn eql(a: Expression, b: Expression) bool {
        if (a.op != b.op) return false;
        if (a.operands.len != b.operands.len) return false;
        for (a.operands, b.operands) |a_op, b_op| {
            if (a_op.id != b_op.id) return false;
        }
        return true;
    }
};

/// 表达式操作符
pub const ExprOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
    and_op,
    or_op,
    xor,
    shl,
    shr,
};

/// 支配树
pub const DominatorTree = struct {
    allocator: Allocator,
    cfg: *ControlFlowGraph,
    /// 每个基本块的直接支配者
    idom: std.AutoHashMap(*BasicBlock, *BasicBlock),
    /// 支配边界
    dominance_frontier: std.AutoHashMap(*BasicBlock, std.ArrayList(*BasicBlock)),

    pub fn init(allocator: Allocator, cfg: *ControlFlowGraph) !DominatorTree {
        return .{
            .allocator = allocator,
            .cfg = cfg,
            .idom = std.AutoHashMap(*BasicBlock, *BasicBlock).init(allocator),
            .dominance_frontier = std.AutoHashMap(*BasicBlock, std.ArrayList(*BasicBlock)).init(allocator),
        };
    }

    pub fn deinit(self: *DominatorTree) void {
        self.idom.deinit();

        var it = self.dominance_frontier.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }
        self.dominance_frontier.deinit();
    }

    /// 计算支配树（使用 Lengauer-Tarjan 算法）
    pub fn compute(self: *DominatorTree) !void {
        const entry = self.cfg.entry orelse return error.NoEntryBlock;

        // 简化实现：使用迭代算法
        // 初始化：entry 支配自己
        try self.idom.put(entry, entry);

        // 迭代计算
        var changed = true;
        while (changed) {
            changed = false;

            for (self.cfg.basic_blocks.items) |bb| {
                if (bb == entry) continue;

                // 找到第一个已处理的前驱
                var new_idom: ?*BasicBlock = null;
                for (bb.predecessors.items) |pred| {
                    if (self.idom.contains(pred)) {
                        new_idom = pred;
                        break;
                    }
                }

                if (new_idom == null) continue;

                // 与其他前驱求交集
                for (bb.predecessors.items) |pred| {
                    if (pred == new_idom.?) continue;
                    if (self.idom.contains(pred)) {
                        new_idom = try self.intersect(pred, new_idom.?);
                    }
                }

                // 更新 idom
                const old_idom = self.idom.get(bb);
                if (old_idom == null or old_idom.? != new_idom.?) {
                    try self.idom.put(bb, new_idom.?);
                    changed = true;
                }
            }
        }

        // 计算支配边界
        try self.computeDominanceFrontier();
    }

    /// 求两个基本块的最近公共支配者
    fn intersect(self: *DominatorTree, b1: *BasicBlock, b2: *BasicBlock) !*BasicBlock {
        var finger1 = b1;
        var finger2 = b2;

        while (finger1 != finger2) {
            while (finger1.id > finger2.id) {
                finger1 = self.idom.get(finger1) orelse return error.InvalidDominatorTree;
            }
            while (finger2.id > finger1.id) {
                finger2 = self.idom.get(finger2) orelse return error.InvalidDominatorTree;
            }
        }

        return finger1;
    }

    /// 计算支配边界
    fn computeDominanceFrontier(self: *DominatorTree) !void {
        for (self.cfg.basic_blocks.items) |bb| {
            if (bb.predecessors.items.len >= 2) {
                for (bb.predecessors.items) |pred| {
                    var runner = pred;

                    while (runner != self.idom.get(bb)) {
                        const entry = try self.dominance_frontier.getOrPut(runner);
                        if (!entry.found_existing) {
                            entry.value_ptr.* = try std.ArrayList(*BasicBlock).initCapacity(self.allocator, 0);
                        }

                        // 检查是否已存在
                        var exists = false;
                        for (entry.value_ptr.items) |existing| {
                            if (existing == bb) {
                                exists = true;
                                break;
                            }
                        }

                        if (!exists) {
                            try entry.value_ptr.append(self.allocator, bb);
                        }

                        runner = self.idom.get(runner) orelse break;
                    }
                }
            }
        }
    }

    /// 检查 a 是否支配 b
    pub fn dominates(self: *const DominatorTree, a: *BasicBlock, b: *BasicBlock) bool {
        if (a == b) return true;

        var current = b;
        while (self.idom.get(current)) |dom| {
            if (dom == current) break; // 到达 entry
            if (dom == a) return true;
            current = dom;
        }

        return false;
    }
};

/// 数据流分析类型
pub const DataFlowAnalysis = enum {
    reaching_definitions,
    liveness,
    available_expressions,
};
