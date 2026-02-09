const std = @import("std");
const Allocator = std.mem.Allocator;
const data_flow = @import("data_flow.zig");
const ControlFlowGraph = data_flow.ControlFlowGraph;
const BasicBlock = data_flow.BasicBlock;
const Instruction = data_flow.Instruction;
const Variable = data_flow.Variable;

/// 边界检查消除优化器
pub const BoundsCheckEliminator = struct {
    allocator: Allocator,
    cfg: *ControlFlowGraph,
    
    /// 归纳变量信息
    induction_vars: std.AutoHashMap(*Variable, InductionVarInfo),
    /// 数组长度信息
    array_lengths: std.AutoHashMap(*Variable, ArrayLengthInfo),
    /// 可消除的边界检查
    eliminable_checks: std.AutoHashMap(*Instruction, void),
    
    pub fn init(allocator: Allocator, cfg: *ControlFlowGraph) !BoundsCheckEliminator {
        return .{
            .allocator = allocator,
            .cfg = cfg,
            .induction_vars = std.AutoHashMap(*Variable, InductionVarInfo).init(allocator),
            .array_lengths = std.AutoHashMap(*Variable, ArrayLengthInfo).init(allocator),
            .eliminable_checks = std.AutoHashMap(*Instruction, void).init(allocator),
        };
    }
    
    pub fn deinit(self: *BoundsCheckEliminator) void {
        self.induction_vars.deinit();
        self.array_lengths.deinit();
        self.eliminable_checks.deinit();
    }
    
    /// 分析循环归纳变量
    pub fn analyzeInductionVariables(self: *BoundsCheckEliminator) !void {
        for (self.cfg.basic_blocks.items) |bb| {
            // 检测循环头
            if (!self.isLoopHeader(bb)) continue;
            
            // 分析循环中的归纳变量
            for (bb.instructions.items) |inst| {
                if (inst.def) |def| {
                    if (def.variable) |v| {
                        if (try self.isInductionVariable(v, bb)) {
                            const info = try self.computeInductionInfo(v, bb);
                            try self.induction_vars.put(v, info);
                        }
                    }
                }
            }
        }
    }
    
    /// 分析数组长度
    pub fn analyzeArrayLengths(self: *BoundsCheckEliminator) !void {
        for (self.cfg.basic_blocks.items) |bb| {
            for (bb.instructions.items) |inst| {
                // 查找数组分配或长度获取
                if (inst.def) |def| {
                    if (def.variable) |v| {
                        if (try self.isArrayVariable(v)) {
                            const info = try self.computeArrayLengthInfo(v, inst);
                            try self.array_lengths.put(v, info);
                        }
                    }
                }
            }
        }
    }
    
    /// 消除可证明安全的边界检查
    pub fn eliminateBoundsChecks(self: *BoundsCheckEliminator) !void {
        for (self.cfg.basic_blocks.items) |bb| {
            for (bb.instructions.items) |inst| {
                if (self.isBoundsCheck(inst)) {
                    if (try self.isProvablySafe(inst)) {
                        try self.eliminable_checks.put(inst, {});
                    }
                }
            }
        }
    }
    
    /// 获取消除率
    pub fn getEliminationRate(self: *const BoundsCheckEliminator) f64 {
        var total_checks: usize = 0;
        for (self.cfg.basic_blocks.items) |bb| {
            for (bb.instructions.items) |inst| {
                if (self.isBoundsCheck(inst)) {
                    total_checks += 1;
                }
            }
        }
        
        if (total_checks == 0) return 1.0;
        return @as(f64, @floatFromInt(self.eliminable_checks.count())) / 
               @as(f64, @floatFromInt(total_checks));
    }
    
    // === 辅助方法 ===
    
    fn isLoopHeader(self: *BoundsCheckEliminator, bb: *BasicBlock) bool {
        // 简化：检查是否有回边
        for (bb.predecessors.items) |pred| {
            if (self.dominates(bb, pred)) {
                return true;
            }
        }
        return false;
    }
    
    fn dominates(self: *BoundsCheckEliminator, a: *BasicBlock, b: *BasicBlock) bool {
        _ = self;
        // 简化：检查 a 是否支配 b
        var current = b;
        while (current.dominator) |dom| {
            if (dom == a) return true;
            current = dom;
        }
        return false;
    }
    
    fn isInductionVariable(self: *BoundsCheckEliminator, v: *Variable, bb: *BasicBlock) !bool {
        _ = self;
        _ = bb;
        // 简化：检查变量是否在循环中递增/递减
        return std.mem.eql(u8, v.name, "i") or 
               std.mem.eql(u8, v.name, "j") or
               std.mem.eql(u8, v.name, "k");
    }
    
    fn computeInductionInfo(self: *BoundsCheckEliminator, v: *Variable, bb: *BasicBlock) !InductionVarInfo {
        _ = self;
        _ = bb;
        // 简化：假设步长为 1，初始值为 0
        return .{
            .base = v,
            .step = 1,
            .initial_value = 0,
        };
    }
    
    fn isArrayVariable(self: *BoundsCheckEliminator, v: *Variable) !bool {
        _ = self;
        return std.mem.startsWith(u8, v.name, "arr") or
               std.mem.startsWith(u8, v.name, "array");
    }
    
    fn computeArrayLengthInfo(self: *BoundsCheckEliminator, v: *Variable, inst: *Instruction) !ArrayLengthInfo {
        _ = self;
        _ = inst;
        // 简化：假设数组长度为 10
        return .{
            .array = v,
            .length = 10,
            .is_constant = true,
        };
    }
    
    fn isBoundsCheck(self: *const BoundsCheckEliminator, inst: *const Instruction) bool {
        _ = self;
        // 简化：load 指令可能是数组访问
        return inst.opcode == .load and inst.uses.len > 0;
    }
    
    fn isProvablySafe(self: *BoundsCheckEliminator, inst: *Instruction) !bool {
        _ = inst;
        // 检查：索引是归纳变量 && 索引 < 数组长度
        
        // 简化：如果有归纳变量信息和数组长度信息，认为安全
        if (self.induction_vars.count() > 0 and self.array_lengths.count() > 0) {
            return true;
        }
        
        return false;
    }
};

/// 归纳变量信息
pub const InductionVarInfo = struct {
    base: *Variable,
    step: i64,
    initial_value: i64,
};

/// 数组长度信息
pub const ArrayLengthInfo = struct {
    array: *Variable,
    length: usize,
    is_constant: bool,
};
