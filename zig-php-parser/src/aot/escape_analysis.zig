const std = @import("std");
const IR = @import("ir.zig");
const Module = IR.Module;
const Function = IR.Function;
const Register = IR.Register;
const Instruction = IR.Instruction;

/// 逃逸分析：确定哪些值不会逃逸出函数作用域
/// 不逃逸的值可以完全消除引用计数操作
pub const EscapeAnalysis = struct {
    allocator: std.mem.Allocator,
    /// 逃逸的寄存器集合
    escaped: std.AutoHashMap(usize, void),
    /// 工作列表
    worklist: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator) !EscapeAnalysis {
        return .{
            .allocator = allocator,
            .escaped = std.AutoHashMap(usize, void).init(allocator),
            .worklist = try std.ArrayList(usize).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *EscapeAnalysis) void {
        self.escaped.deinit();
        self.worklist.deinit(self.allocator);
    }

    /// 分析函数中的逃逸情况
    pub fn analyze(self: *EscapeAnalysis, func: *Function) !void {
        self.escaped.clearRetainingCapacity();
        self.worklist.clearRetainingCapacity();

        // 第一遍：标记明显逃逸的值
        for (func.blocks.items) |block| {
            // 检查指令
            for (block.instructions.items) |inst| {
                try self.markEscaping(inst);
            }
            
            // 检查终止符（返回值）
            if (block.terminator) |term| {
                if (term.ret) |ret_val| {
                    try self.markEscaped(ret_val.id);
                }
            }
        }

        // 传播逃逸信息（不动点迭代）
        while (self.worklist.items.len > 0) {
            const reg_id = self.worklist.pop();
            
            // 查找所有使用此寄存器的指令
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.result) |result| {
                        if (self.usesRegister(inst, reg_id)) {
                            // 如果逃逸的值被使用，结果也逃逸
                            try self.markEscaped(result.id);
                        }
                    }
                }
            }
        }
    }

    /// 检查寄存器是否逃逸
    pub fn isEscaped(self: *EscapeAnalysis, reg_id: usize) bool {
        return self.escaped.contains(reg_id);
    }

    /// 标记明显逃逸的情况
    fn markEscaping(self: *EscapeAnalysis, inst: *const Instruction) !void {
        switch (inst.op) {
            // 函数调用参数逃逸
            .call => |op| {
                for (op.args) |arg| {
                    try self.markEscaped(arg.id);
                }
            },
            // 数组/对象元素逃逸
            .array_set, .array_set_nested => {
                if (inst.result) |result| {
                    try self.markEscaped(result.id);
                }
            },
            else => {},
        }
    }

    /// 标记寄存器为逃逸
    fn markEscaped(self: *EscapeAnalysis, reg_id: usize) !void {
        const result = try self.escaped.getOrPut(reg_id);
        if (!result.found_existing) {
            try self.worklist.append(self.allocator, reg_id);
        }
    }

    /// 检查指令是否使用指定寄存器
    fn usesRegister(self: *EscapeAnalysis, inst: *const Instruction, reg_id: usize) bool {
        _ = self;
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod => |op| {
                return op.lhs.id == reg_id or op.rhs.id == reg_id;
            },
            .move, .cast, .not => |op| {
                return op.operand.id == reg_id;
            },
            .call => |op| {
                for (op.args) |arg| {
                    if (arg.id == reg_id) return true;
                }
                return false;
            },
            else => return false,
        }
    }
};
