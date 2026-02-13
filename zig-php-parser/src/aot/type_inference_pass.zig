/// 类型推断 Pass
/// 
/// 通过数据流分析推断所有寄存器的实际类型，为后续优化提供基础。
/// 
/// 设计原则：
/// 1. 前向传播：从常量和 phi 节点开始
/// 2. 约束求解：处理类型冲突
/// 3. 保守估计：不确定时使用 php_value
/// 4. 可扩展：支持未来的类型系统扩展

const std = @import("std");
const IR = @import("ir.zig");
const Analysis = @import("analysis.zig");

pub const TypeInferencePass = struct {
    allocator: std.mem.Allocator,
    
    /// 推断结果：寄存器 ID -> 推断类型
    inferred_types: std.AutoHashMap(usize, IR.Type),
    
    /// 类型约束：寄存器必须满足的类型要求
    constraints: std.AutoHashMap(usize, TypeConstraint),
    
    pub const TypeConstraint = struct {
        /// 必须是这些类型之一
        allowed: std.ArrayList(std.meta.Tag(IR.Type)),
        /// 来源：用于调试
        source: []const u8,
    };
    
    pub fn init(allocator: std.mem.Allocator) TypeInferencePass {
        return .{
            .allocator = allocator,
            .inferred_types = std.AutoHashMap(usize, IR.Type).init(allocator),
            .constraints = std.AutoHashMap(usize, TypeConstraint).init(allocator),
        };
    }
    
    pub fn deinit(self: *TypeInferencePass) void {
        self.inferred_types.deinit();
        
        var it = self.constraints.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.allowed.deinit();
        }
        self.constraints.deinit();
    }
    
    /// 对函数执行类型推断
    pub fn inferTypes(self: *TypeInferencePass, func: *IR.Function) !void {
        std.debug.print("type_inference: Analyzing function {s}\n", .{func.name});
        
        // 1. 收集初始类型信息（常量、phi 节点）
        try self.collectInitialTypes(func);
        
        // 2. 前向传播类型信息
        try self.propagateTypes(func);
        
        // 3. 解决类型约束
        try self.resolveConstraints();
        
        std.debug.print("type_inference: Inferred {d} register types\n", .{self.inferred_types.count()});
    }
    
    /// 收集初始类型信息
    fn collectInitialTypes(self: *TypeInferencePass, func: *IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |*inst| {
                if (inst.*.result) |result| {
                    switch (inst.*.op) {
                        .const_int => {
                            try self.inferred_types.put(result.id, .{ .i64 = {} });
                        },
                        .const_float => {
                            try self.inferred_types.put(result.id, .{ .f64 = {} });
                        },
                        .const_bool => {
                            try self.inferred_types.put(result.id, .{ .bool = {} });
                        },
                        .phi => {
                            // phi 节点的类型已经被 mem2reg 特化
                            const result_tag = @as(std.meta.Tag(IR.Type), result.type_);
                            if (result_tag != .php_value) {
                                try self.inferred_types.put(result.id, result.type_);
                            }
                        },
                        else => {},
                    }
                }
            }
        }
    }
    
    /// 前向传播类型信息
    fn propagateTypes(self: *TypeInferencePass, func: *IR.Function) !void {
        var changed = true;
        var iterations: usize = 0;
        const max_iterations = 100;
        
        while (changed and iterations < max_iterations) {
            changed = false;
            iterations += 1;
            
            for (func.blocks.items) |block| {
                for (block.instructions.items) |*inst| {
                    const propagated = try self.propagateInstruction(inst.*);
                    if (propagated) changed = true;
                }
            }
        }
        
        if (iterations >= max_iterations) {
            std.debug.print("type_inference: WARNING - reached max iterations\n", .{});
        }
    }
    
    /// 传播单个指令的类型信息
    fn propagateInstruction(self: *TypeInferencePass, inst: *IR.Instruction) !bool {
        if (inst.result == null) return false;
        const result = inst.result.?;
        
        // 如果已经推断过，跳过
        if (self.inferred_types.contains(result.id)) return false;
        
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod => |op| {
                // 算术操作：如果两个操作数类型相同且为原生类型，结果也是该类型
                const lhs_type = self.inferred_types.get(op.lhs.id);
                const rhs_type = self.inferred_types.get(op.rhs.id);
                
                if (lhs_type != null and rhs_type != null) {
                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type.?);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type.?);
                    
                    if (lhs_tag == rhs_tag and (lhs_tag == .i64 or lhs_tag == .f64)) {
                        try self.inferred_types.put(result.id, lhs_type.?);
                        return true;
                    }
                }
            },
            .cast => |op| {
                // cast 指令：目标类型就是结果类型
                // 但如果源类型已知且与目标类型相同，标记为冗余
                const src_type = self.inferred_types.get(op.value.id);
                if (src_type != null) {
                    const src_tag = @as(std.meta.Tag(IR.Type), src_type.?);
                    const to_tag = @as(std.meta.Tag(IR.Type), op.to_type);
                    
                    if (src_tag == to_tag) {
                        // 冗余 cast，直接使用源类型
                        try self.inferred_types.put(result.id, src_type.?);
                    } else {
                        try self.inferred_types.put(result.id, op.to_type);
                    }
                    return true;
                }
            },
            .lt, .le, .gt, .ge, .eq, .ne => {
                // 比较操作：结果总是 bool
                try self.inferred_types.put(result.id, .{ .bool = {} });
                return true;
            },
            else => {},
        }
        
        return false;
    }
    
    /// 解决类型约束
    fn resolveConstraints(self: *TypeInferencePass) !void {
        // TODO: 实现约束求解
        // 当前版本：简单传播，未来可扩展为完整的约束求解器
        _ = self;
    }
    
    /// 获取寄存器的推断类型
    pub fn getInferredType(self: *const TypeInferencePass, reg_id: usize) ?IR.Type {
        return self.inferred_types.get(reg_id);
    }
};
