const std = @import("std");
const IR = @import("ir.zig");
const TypeConstraintSolver = @import("type_constraint_solver.zig").TypeConstraintSolver;
const Allocator = std.mem.Allocator;

/// 类型推断 Pass - 基于约束求解
pub const TypeInferencePass = struct {
    allocator: Allocator,
    solver: TypeConstraintSolver,
    
    pub fn init(allocator: Allocator) TypeInferencePass {
        return .{
            .allocator = allocator,
            .solver = TypeConstraintSolver.init(allocator),
        };
    }
    
    pub fn deinit(self: *TypeInferencePass) void {
        self.solver.deinit();
    }
    
    pub fn inferTypes(self: *TypeInferencePass, func: *IR.Function) !void {
        std.debug.print("type_inference: Analyzing function {s}\n", .{func.name});
        
        // 收集约束
        try self.collectConstraints(func);
        
        std.debug.print("type_inference: Collected {d} constraints\n", .{self.solver.constraints.items.len});
        
        // 求解
        try self.solver.solve();
        
        std.debug.print("type_inference: Inferred {d} register types\n", 
            .{self.solver.var_to_type.count()});
    }
    
    fn collectConstraints(self: *TypeInferencePass, func: *IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |*inst| {
                try self.collectInstConstraints(inst.*);
            }
        }
    }
    
    fn collectInstConstraints(self: *TypeInferencePass, inst: *IR.Instruction) !void {
        const result = inst.result orelse return;
        
        switch (inst.op) {
            .const_int => try self.solver.addConcrete(result.id, .{ .i64 = {} }),
            .const_float => try self.solver.addConcrete(result.id, .{ .f64 = {} }),
            .const_bool => try self.solver.addConcrete(result.id, .{ .bool = {} }),
            
            .phi => |phi_op| {
                // Phi 已特化的类型
                const tag = @as(std.meta.Tag(IR.Type), result.type_);
                if (tag != .php_value) {
                    try self.solver.addConcrete(result.id, result.type_);
                }
                
                // Phi 约束
                var incoming = try std.ArrayList(usize).initCapacity(self.allocator, phi_op.incoming.len);
                defer incoming.deinit(self.allocator);
                for (phi_op.incoming) |inc| {
                    try incoming.append(self.allocator, inc.value.id);
                }
                try self.solver.addPhi(incoming.items, result.id);
            },
            
            .add, .sub, .mul, .div, .mod => |op| {
                try self.solver.addBinaryOp(op.lhs.id, op.rhs.id, result.id);
            },
            
            .cast => |op| {
                const from_tag = @as(std.meta.Tag(IR.Type), op.from_type);
                if (from_tag != .php_value) {
                    try self.solver.addConcrete(op.value.id, op.from_type);
                }
                try self.solver.addConcrete(result.id, op.to_type);
            },
            
            .move => |op| {
                try self.solver.addEquality(result.id, op.operand.id);
            },
            
            else => {},
        }
    }
    
    pub fn getInferredType(self: *const TypeInferencePass, reg_id: usize) ?IR.Type {
        return self.solver.getInferredType(reg_id);
    }
};
