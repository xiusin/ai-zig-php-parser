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
        
        // 2. 特化算术操作
        try self.specializeArithmeticOps(func);
        
        // 3. 更新指令类型
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
                    
                    // 获取源和目标的推断类型
                    const src_inferred = self.type_inference.getInferredType(cast_op.value.id);
                    const dst_inferred = self.type_inference.getInferredType(result.id);
                    
                    if (src_inferred != null and dst_inferred != null) {
                        const src_tag = @as(std.meta.Tag(IR.Type), src_inferred.?);
                        const dst_tag = @as(std.meta.Tag(IR.Type), dst_inferred.?);
                        
                        // 如果源和目标类型相同，消除 cast
                        if (src_tag == dst_tag) {
                            // 替换为 move（或直接使用源寄存器）
                            inst.*.op = .{ .move = .{ .operand = cast_op.value } };
                            self.stats.casts_eliminated += 1;
                            std.debug.print("  Eliminated redundant cast: reg_{d}\n", .{result.id});
                        }
                    }
                }
            }
        }
    }
    
    /// 特化算术操作
    fn specializeArithmeticOps(self: *TypeSpecializationPass, func: *IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |*inst| {
                switch (inst.*.op) {
                    .add, .sub, .mul, .div, .mod => |*op| {
                        if (inst.*.result) |*result| {
                            // 获取操作数的推断类型
                            const lhs_type = self.type_inference.getInferredType(op.lhs.id);
                            const rhs_type = self.type_inference.getInferredType(op.rhs.id);
                            const result_type = self.type_inference.getInferredType(result.id);
                            
                            if (lhs_type != null and rhs_type != null and result_type != null) {
                                const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type.?);
                                const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type.?);
                                const result_tag = @as(std.meta.Tag(IR.Type), result_type.?);
                                
                                // 如果所有类型都是 i64 或 f64，更新操作数类型
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
