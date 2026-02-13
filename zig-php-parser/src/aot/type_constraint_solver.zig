const std = @import("std");
const IR = @import("ir.zig");
const Allocator = std.mem.Allocator;

/// 类型变量 - 代表一个待推断的类型
pub const TypeVar = struct {
    id: usize,
};

/// 约束类型
pub const ConstraintKind = enum {
    concrete,    // T = i64
    equality,    // T1 = T2
    binary_op,   // T_result = T_lhs op T_rhs
    phi,         // T_result = phi(T1, T2, ...)
};

/// 约束数据
pub const Constraint = union(ConstraintKind) {
    concrete: struct { var_: TypeVar, type_: IR.Type },
    equality: struct { lhs: TypeVar, rhs: TypeVar },
    binary_op: struct { lhs: TypeVar, rhs: TypeVar, result: TypeVar },
    phi: struct { incoming: []TypeVar, result: TypeVar },
};

/// 类型约束求解器
pub const TypeConstraintSolver = struct {
    allocator: Allocator,
    reg_to_var: std.AutoHashMap(usize, TypeVar),
    var_to_type: std.AutoHashMap(usize, IR.Type),
    constraints: std.ArrayList(Constraint),
    next_var_id: usize,
    
    pub fn init(allocator: Allocator) TypeConstraintSolver {
        return .{
            .allocator = allocator,
            .reg_to_var = std.AutoHashMap(usize, TypeVar).init(allocator),
            .var_to_type = std.AutoHashMap(usize, IR.Type).init(allocator),
            .constraints = std.ArrayList(Constraint).initCapacity(allocator, 0) catch unreachable,
            .next_var_id = 0,
        };
    }
    
    pub fn deinit(self: *TypeConstraintSolver) void {
        // 释放 phi 约束中的数组
        for (self.constraints.items) |constraint| {
            if (constraint == .phi) {
                self.allocator.free(constraint.phi.incoming);
            }
        }
        self.constraints.deinit(self.allocator);
        self.reg_to_var.deinit();
        self.var_to_type.deinit();
    }
    
    pub fn getOrCreateVar(self: *TypeConstraintSolver, reg_id: usize) !TypeVar {
        if (self.reg_to_var.get(reg_id)) |var_| return var_;
        const var_ = TypeVar{ .id = self.next_var_id };
        self.next_var_id += 1;
        try self.reg_to_var.put(reg_id, var_);
        return var_;
    }
    
    pub fn addConcrete(self: *TypeConstraintSolver, reg_id: usize, type_: IR.Type) !void {
        const var_ = try self.getOrCreateVar(reg_id);
        try self.constraints.append(self.allocator, .{ .concrete = .{ .var_ = var_, .type_ = type_ } });
    }
    
    pub fn addEquality(self: *TypeConstraintSolver, reg1: usize, reg2: usize) !void {
        const v1 = try self.getOrCreateVar(reg1);
        const v2 = try self.getOrCreateVar(reg2);
        try self.constraints.append(self.allocator, .{ .equality = .{ .lhs = v1, .rhs = v2 } });
    }
    
    pub fn addBinaryOp(self: *TypeConstraintSolver, lhs: usize, rhs: usize, result: usize) !void {
        const v_lhs = try self.getOrCreateVar(lhs);
        const v_rhs = try self.getOrCreateVar(rhs);
        const v_result = try self.getOrCreateVar(result);
        try self.constraints.append(self.allocator, .{ .binary_op = .{ .lhs = v_lhs, .rhs = v_rhs, .result = v_result } });
    }
    
    pub fn addPhi(self: *TypeConstraintSolver, incoming: []const usize, result: usize) !void {
        const v_result = try self.getOrCreateVar(result);
        var vars = try self.allocator.alloc(TypeVar, incoming.len);
        for (incoming, 0..) |reg, i| {
            vars[i] = try self.getOrCreateVar(reg);
        }
        try self.constraints.append(self.allocator, .{ .phi = .{ .incoming = vars, .result = v_result } });
    }
    
    /// 求解所有约束
    pub fn solve(self: *TypeConstraintSolver) !void {
        std.debug.print("type_constraint: Solving {d} constraints for {d} variables\n",
            .{ self.constraints.items.len, self.reg_to_var.count() });
        
        var changed = true;
        var iter: usize = 0;
        
        while (changed and iter < 100) : (iter += 1) {
            changed = false;
            for (self.constraints.items) |constraint| {
                if (try self.propagate(constraint)) changed = true;
            }
        }
        
        std.debug.print("type_constraint: Solved in {d} iterations, {d}/{d} types inferred\n",
            .{ iter, self.var_to_type.count(), self.reg_to_var.count() });
    }
    
    fn propagate(self: *TypeConstraintSolver, constraint: Constraint) !bool {
        switch (constraint) {
            .concrete => |c| {
                if (!self.var_to_type.contains(c.var_.id)) {
                    try self.var_to_type.put(c.var_.id, c.type_);
                    return true;
                }
            },
            
            .equality => |c| {
                const t1 = self.var_to_type.get(c.lhs.id);
                const t2 = self.var_to_type.get(c.rhs.id);
                if (t1 != null and t2 == null) {
                    try self.var_to_type.put(c.rhs.id, t1.?);
                    return true;
                } else if (t2 != null and t1 == null) {
                    try self.var_to_type.put(c.lhs.id, t2.?);
                    return true;
                }
            },
            
            .binary_op => |c| {
                const t_lhs = self.var_to_type.get(c.lhs.id);
                const t_rhs = self.var_to_type.get(c.rhs.id);
                const t_result = self.var_to_type.get(c.result.id);
                
                // 前向：lhs 和 rhs 类型相同 → result
                if (t_lhs != null and t_rhs != null and t_result == null) {
                    const lhs_tag = @as(std.meta.Tag(IR.Type), t_lhs.?);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), t_rhs.?);
                    if (lhs_tag == rhs_tag and (lhs_tag == .i64 or lhs_tag == .f64)) {
                        try self.var_to_type.put(c.result.id, t_lhs.?);
                        return true;
                    }
                }
                
                // 反向：result 是 i64，lhs 是 i64 → rhs 也是 i64
                if (t_result != null) {
                    const result_tag = @as(std.meta.Tag(IR.Type), t_result.?);
                    if (result_tag == .i64 or result_tag == .f64) {
                        var changed = false;
                        if (t_lhs != null and t_rhs == null) {
                            const lhs_tag = @as(std.meta.Tag(IR.Type), t_lhs.?);
                            if (lhs_tag == result_tag) {
                                try self.var_to_type.put(c.rhs.id, t_result.?);
                                changed = true;
                            }
                        }
                        if (t_rhs != null and t_lhs == null) {
                            const rhs_tag = @as(std.meta.Tag(IR.Type), t_rhs.?);
                            if (rhs_tag == result_tag) {
                                try self.var_to_type.put(c.lhs.id, t_result.?);
                                changed = true;
                            }
                        }
                        if (changed) return true;
                    }
                }
            },
            
            .phi => |c| {
                const t_result = self.var_to_type.get(c.result.id);
                
                // 前向：所有 incoming 类型相同 → result
                if (t_result == null and c.incoming.len > 0) {
                    var common: ?IR.Type = null;
                    var all_same = true;
                    for (c.incoming) |var_| {
                        const t = self.var_to_type.get(var_.id);
                        if (t == null) {
                            all_same = false;
                            break;
                        }
                        if (common == null) {
                            common = t;
                        } else {
                            const c_tag = @as(std.meta.Tag(IR.Type), common.?);
                            const t_tag = @as(std.meta.Tag(IR.Type), t.?);
                            if (c_tag != t_tag) {
                                all_same = false;
                                break;
                            }
                        }
                    }
                    if (all_same and common != null) {
                        try self.var_to_type.put(c.result.id, common.?);
                        return true;
                    }
                }
                
                // 反向：result 类型已知 → 传播到 incoming
                if (t_result != null) {
                    const result_tag = @as(std.meta.Tag(IR.Type), t_result.?);
                    if (result_tag == .i64 or result_tag == .f64) {
                        var changed = false;
                        for (c.incoming) |var_| {
                            if (!self.var_to_type.contains(var_.id)) {
                                try self.var_to_type.put(var_.id, t_result.?);
                                changed = true;
                            }
                        }
                        if (changed) return true;
                    }
                }
            },
        }
        return false;
    }
    
    pub fn getInferredType(self: *const TypeConstraintSolver, reg_id: usize) ?IR.Type {
        const var_ = self.reg_to_var.get(reg_id) orelse return null;
        return self.var_to_type.get(var_.id);
    }
};
