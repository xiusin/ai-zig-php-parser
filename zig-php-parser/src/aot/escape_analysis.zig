const std = @import("std");
const IR = @import("ir.zig");
const Module = IR.Module;
const Function = IR.Function;
const Register = IR.Register;
const Instruction = IR.Instruction;

pub const EscapeAnalysis = struct {
    allocator: std.mem.Allocator,
    escaped: std.AutoHashMap(usize, void),
    worklist: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator) !EscapeAnalysis {
        return .{
            .allocator = allocator,
            .escaped = std.AutoHashMap(usize, void).init(allocator),
            .worklist = try std.ArrayList(usize).initCapacity(allocator, 64),
        };
    }

    pub fn deinit(self: *EscapeAnalysis) void {
        self.escaped.deinit();
        self.worklist.deinit(self.allocator);
    }

    pub fn analyze(self: *EscapeAnalysis, func: *Function) !void {
        self.escaped.clearRetainingCapacity();
        self.worklist.clearRetainingCapacity();

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                try self.markRootEscapes(inst);
            }

            if (block.terminator) |term| {
                switch (term) {
                    .ret => |ret_val| {
                        if (ret_val) |rv| {
                            try self.markEscaped(rv.id);
                        }
                    },
                    else => {},
                }
            }
        }

        while (self.worklist.items.len > 0) {
            const escaped_id = self.worklist.pop() orelse break;
            try self.propagateEscape(func, escaped_id);
        }
    }

    pub fn isEscaped(self: *EscapeAnalysis, reg_id: usize) bool {
        return self.escaped.contains(reg_id);
    }

    fn markRootEscapes(self: *EscapeAnalysis, inst: *const Instruction) !void {
        switch (inst.op) {
            .call => |op| {
                for (op.args) |arg| {
                    try self.markEscaped(arg.id);
                }
            },
            .call_indirect => |op| {
                try self.markEscaped(op.func_ptr.id);
                for (op.args) |arg| {
                    try self.markEscaped(arg.id);
                }
            },
            .method_call => |op| {
                try self.markEscaped(op.object.id);
                for (op.args) |arg| {
                    try self.markEscaped(arg.id);
                }
            },
            .static_method_call => |op| {
                for (op.args) |arg| {
                    try self.markEscaped(arg.id);
                }
            },
            .parent_call => |op| {
                try self.markEscaped(op.object.id);
                for (op.args) |arg| {
                    try self.markEscaped(arg.id);
                }
            },
            .global_set => |op| {
                if (op.value) |val| {
                    try self.markEscaped(val.id);
                }
            },
            .array_set => |op| {
                try self.markEscaped(op.value.id);
                try self.markEscaped(op.key.id);
            },
            .array_set_nested => |op| {
                try self.markEscaped(op.value.id);
                try self.markEscaped(op.inner_key.id);
                try self.markEscaped(op.outer_key.id);
            },
            .array_push => |op| {
                try self.markEscaped(op.value.id);
            },
            .property_set => |op| {
                try self.markEscaped(op.object.id);
                try self.markEscaped(op.value.id);
            },
            .store => |op| {
                try self.markEscaped(op.value.id);
            },
            .new_object => |op| {
                for (op.args) |arg| {
                    try self.markEscaped(arg.id);
                }
            },
            .closure_new => |op| {
                try self.markEscaped(op.func_ptr.id);
                for (op.captures) |cap| {
                    try self.markEscaped(cap.id);
                }
            },
            .closure_bind => |op| {
                try self.markEscaped(op.closure.id);
                try self.markEscaped(op.object.id);
            },
            else => {},
        }
    }

    fn markEscaped(self: *EscapeAnalysis, reg_id: usize) !void {
        const result = try self.escaped.getOrPut(reg_id);
        if (!result.found_existing) {
            try self.worklist.append(self.allocator, reg_id);
        }
    }

    fn propagateEscape(self: *EscapeAnalysis, func: *Function, escaped_id: usize) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |result| {
                    if (result.id == escaped_id) continue;
                    if (self.producesFrom(inst, escaped_id)) {
                        try self.markEscaped(result.id);
                    }
                }
            }
        }
    }

    fn producesFrom(self: *EscapeAnalysis, inst: *const Instruction, reg_id: usize) bool {
        _ = self;
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod, .pow,
            .bit_and, .bit_or, .bit_xor, .shl, .shr,
            .eq, .ne, .lt, .le, .gt, .ge,
            .identical, .not_identical, .spaceship,
            .and_, .or_, .xor_,
            .concat => |op| {
                return op.lhs.id == reg_id or op.rhs.id == reg_id;
            },
            .move, .not, .bit_not, .neg, .strlen, .array_count, .clone,
            .retain, .release, .unset_var, .debug_print => |op| {
                return op.operand.id == reg_id;
            },
            .cast => |op| {
                return op.value.id == reg_id;
            },
            .box => |op| {
                return op.value.id == reg_id;
            },
            .unbox => |op| {
                return op.value.id == reg_id;
            },
            .type_check => |op| {
                return op.value.id == reg_id;
            },
            .instanceof => |op| {
                return op.object.id == reg_id or op.class_name.id == reg_id;
            },
            .get_type => |op| {
                return op.operand.id == reg_id;
            },
            .load => |op| {
                return op.ptr.id == reg_id;
            },
            .array_get, .array_ensure => |op| {
                return op.array.id == reg_id or op.key.id == reg_id;
            },
            .array_key_exists => |op| {
                return op.array.id == reg_id or op.key.id == reg_id;
            },
            .phi => |op| {
                for (op.incoming) |incoming| {
                    if (incoming.value.id == reg_id) return true;
                }
                return false;
            },
            .select => |op| {
                if (op.cond.id == reg_id or op.then_value.id == reg_id or op.else_value.id == reg_id) return true;
                return false;
            },
            else => return false,
        }
    }
};
