/// 类型特化 Pass
/// 
/// 根据类型推断结果，特化指令以生成更高效的代码。
/// 
/// 优化策略：
/// 1. 消除冗余类型转换
/// 2. 特化算术操作为原生操作
/// 3. 特化比较操作
/// 4. 内联简单操作
/// 
/// 可扩展性：
/// - 支持自定义特化规则
/// - 支持多种目标平台
/// - 保持 IR 语义不变

const std = @import("std");
const IR = @import("ir.zig");
const TypeInferencePass = @import("type_inference_pass.zig").TypeInferencePass;

pub const TypeSpecializationPass = struct {
    allocator: std.mem.Allocator,
    type_inference: *const TypeInferencePass,
    
    /// 统计信息
    stats: Stats,
    
    pub const Stats = struct {
        casts_eliminated: usize = 0,
        ops_specialized: usize = 0,
        instructions_modified: usize = 0,
    };
    
    pub fn init(allocator: std.mem.Allocator, type_inference: *const TypeInferencePass) TypeSpecializationPass {
        return .{
            .allocator = allocator,
            .type_inference = type_inference,
            .stats = .{},
        };
    }
    
    /// 对函数执行类型特化
    pub fn specialize(self: *TypeSpecializationPass, func: *IR.Function) !void {
        std.debug.print("type_specialization: Specializing function {s}\n", .{func.name});
        
        // 1. 消除冗余 cast
        try self.eliminateRedundantCasts(func);
        
        // 2. 绕过比较操作前的不必要 cast
        try self.bypassCastsInComparisons(func);
        
        // 3. 特化算术操作
        try self.specializeArithmeticOps(func);
        
        // 4. 更新指令类型
        try self.updateInstructionTypes(func);
        
        std.debug.print("type_specialization: Stats - casts_eliminated={d}, ops_specialized={d}\n", 
            .{self.stats.casts_eliminated, self.stats.ops_specialized});
    }
    
    /// 消除冗余的类型转换
    fn eliminateRedundantCasts(self: *TypeSpecializationPass, func: *IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |*inst| {
                if (inst.*.op == .cast) {
                    const cast_op = inst.*.op.cast;
                    const result = inst.*.result orelse continue;
                    
                    const src_inferred = self.type_inference.getInferredType(cast_op.value.id);
                    const dst_inferred = self.type_inference.getInferredType(result.id);
                    
                    if (src_inferred != null and dst_inferred != null) {
                        const src_tag = @as(std.meta.Tag(IR.Type), src_inferred.?);
                        const dst_tag = @as(std.meta.Tag(IR.Type), dst_inferred.?);
                        
                        if (src_tag == dst_tag) {
                            inst.*.op = .{ .move = .{ .operand = cast_op.value } };
                            self.stats.casts_eliminated += 1;
                        }
                    }
                }
            }
        }
    }
    
    /// 绕过比较和算术操作前的不必要 cast
    fn bypassCastsInComparisons(self: *TypeSpecializationPass, func: *IR.Function) !void {
        var cast_sources = std.AutoHashMap(usize, IR.Register).init(self.allocator);
        defer cast_sources.deinit();
        
        // 收集所有 i64 → php_value 的 cast
        for (func.blocks.items) |block| {
            for (block.instructions.items) |*inst| {
                if (inst.*.op == .cast) {
                    const cast_op = inst.*.op.cast;
                    if (inst.*.result) |result| {
                        const from_tag = @as(std.meta.Tag(IR.Type), cast_op.from_type);
                        const to_tag = @as(std.meta.Tag(IR.Type), cast_op.to_type);
                        
                        if (from_tag == .i64 and to_tag == .php_value) {
                            try cast_sources.put(result.id, cast_op.value);
                        }
                    }
                }
            }
        }
        
        // 在比较和算术操作中绕过 cast
        for (func.blocks.items) |block| {
            for (block.instructions.items) |*inst| {
                switch (inst.*.op) {
                    .lt, .le, .gt, .ge, .eq, .ne => |*op| {
                        if (try self.bypassOperand(&op.lhs, &cast_sources)) {
                            self.stats.casts_eliminated += 1;
                        }
                        if (try self.bypassOperand(&op.rhs, &cast_sources)) {
                            self.stats.casts_eliminated += 1;
                        }
                    },
                    
                    .add, .sub, .mul, .div, .mod => |*op| {
                        // 检查结果类型：必须是 i64 才安全穿透
                        const result = inst.*.result orelse continue;
                        const result_tag = @as(std.meta.Tag(IR.Type), result.type_);
                        
                        std.debug.print("  Arithmetic op: result reg_{d} type={s}\n", 
                            .{result.id, @tagName(result_tag)});
                        
                        if (result_tag == .i64) {
                            // 结果是 i64，可以安全穿透
                            if (try self.bypassOperand(&op.lhs, &cast_sources)) {
                                std.debug.print("    Bypassed lhs cast\n", .{});
                                self.stats.casts_eliminated += 1;
                            }
                            if (try self.bypassOperand(&op.rhs, &cast_sources)) {
                                std.debug.print("    Bypassed rhs cast\n", .{});
                                self.stats.casts_eliminated += 1;
                            }
                        }
                    },
                    
                    else => {},
                }
            }
        }
    }
    
    /// 尝试绕过操作数的 cast
    fn bypassOperand(
        self: *TypeSpecializationPass,
        operand: *IR.Register,
        cast_sources: *const std.AutoHashMap(usize, IR.Register),
    ) !bool {
        _ = self;
        const tag = @as(std.meta.Tag(IR.Type), operand.type_);
        if (tag == .php_value) {
            if (cast_sources.get(operand.id)) |source| {
                operand.* = source;
                return true;
            }
        }
        return false;
    }
    
    /// 特化算术操作
    fn specializeArithmeticOps(self: *TypeSpecializationPass, func: *IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |*inst| {
                switch (inst.*.op) {
                    .add, .sub, .mul, .div, .mod => |*op| {
                        if (inst.*.result) |*result| {
                            const lhs_type = self.type_inference.getInferredType(op.lhs.id);
                            const rhs_type = self.type_inference.getInferredType(op.rhs.id);
                            const result_type = self.type_inference.getInferredType(result.id);
                            
                            if (lhs_type != null and rhs_type != null and result_type != null) {
                                const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type.?);
                                const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type.?);
                                const result_tag = @as(std.meta.Tag(IR.Type), result_type.?);
                                
                                if (lhs_tag == rhs_tag and lhs_tag == result_tag and 
                                    (lhs_tag == .i64 or lhs_tag == .f64)) {
                                    op.lhs.type_ = lhs_type.?;
                                    op.rhs.type_ = rhs_type.?;
                                    result.type_ = result_type.?;
                                    self.stats.ops_specialized += 1;
                                }
                            }
                        }
                    },
                    .lt, .le, .gt, .ge, .eq, .ne => |*op| {
                        const lhs_type = self.type_inference.getInferredType(op.lhs.id);
                        const rhs_type = self.type_inference.getInferredType(op.rhs.id);
                        
                        if (lhs_type != null and rhs_type != null) {
                            const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type.?);
                            const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type.?);
                            
                            if (lhs_tag == rhs_tag and (lhs_tag == .i64 or lhs_tag == .f64)) {
                                op.lhs.type_ = lhs_type.?;
                                op.rhs.type_ = rhs_type.?;
                                self.stats.ops_specialized += 1;
                            }
                        }
                    },
                    else => {},
                }
            }
        }
    }
    
    /// 更新指令类型以匹配推断结果
    fn updateInstructionTypes(self: *TypeSpecializationPass, func: *IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |*inst| {
                if (inst.*.result) |*result| {
                    if (self.type_inference.getInferredType(result.id)) |inferred| {
                        const old_tag = @as(std.meta.Tag(IR.Type), result.type_);
                        const new_tag = @as(std.meta.Tag(IR.Type), inferred);
                        
                        if (old_tag != new_tag) {
                            result.type_ = inferred;
                            self.stats.instructions_modified += 1;
                        }
                    }
                }
            }
        }
    }
};
