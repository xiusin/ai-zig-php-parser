const std = @import("std");
const IR = @import("ir.zig");
const Module = IR.Module;
const Function = IR.Function;
const Register = IR.Register;
const Instruction = IR.Instruction;
const BasicBlock = IR.BasicBlock;

/// 逃逸分析结果：描述每个寄存器的逃逸状态
pub const EscapeResult = struct {
    /// 寄存器是否逃逸出函数作用域
    escaped: bool,
    /// 寄存器是否逃逸出定义它的基本块（跨块使用）
    cross_block: bool,
    /// 是否可以栈分配（既不逃逸函数，也不跨块）
    can_stack_allocate: bool,
    /// 是否是返回值且可以跳过 retain/release（所有权转移）
    return_ownership_transfer: bool,
    /// 定义该寄存器的基本块索引（如果已知）
    defining_block: ?usize,
};

/// 增强的逃逸分析：追踪跨基本块逃逸、栈分配候选、返回值所有权转移
pub const EscapeAnalysis = struct {
    allocator: std.mem.Allocator,
    /// 每个寄存器 → 逃逸结果
    results: std.AutoHashMap(usize, EscapeResult),
    /// 工作列表（需要传播逃逸信息的寄存器）
    worklist: std.ArrayList(usize),
    /// 函数的基本块数量
    block_count: usize,

    pub fn init(allocator: std.mem.Allocator) !EscapeAnalysis {
        return .{
            .allocator = allocator,
            .results = std.AutoHashMap(usize, EscapeResult).init(allocator),
            .worklist = try std.ArrayList(usize).initCapacity(allocator, 64),
            .block_count = 0,
        };
    }

    pub fn deinit(self: *EscapeAnalysis) void {
        self.results.deinit();
        self.worklist.deinit();
    }

    /// 获取寄存器的逃逸分析结果
    pub fn getResult(self: *EscapeAnalysis, reg_id: usize) ?EscapeResult {
        return self.results.get(reg_id);
    }

    /// 检查寄存器是否逃逸
    pub fn isEscaped(self: *EscapeAnalysis, reg_id: usize) bool {
        if (self.results.get(reg_id)) |r| return r.escaped;
        return true; // 未知的寄存器保守地视为逃逸
    }

    /// 检查寄存器是否可以栈分配
    pub fn canStackAllocate(self: *EscapeAnalysis, reg_id: usize) bool {
        if (self.results.get(reg_id)) |r| return r.can_stack_allocate;
        return false;
    }

    /// 检查返回值是否可以跳过 retain/release（所有权转移）
    pub fn isReturnOwnershipTransfer(self: *EscapeAnalysis, reg_id: usize) bool {
        if (self.results.get(reg_id)) |r| return r.return_ownership_transfer;
        return false;
    }

    /// 运行完整的逃逸分析
    pub fn analyze(self: *EscapeAnalysis, func: *Function) !void {
        self.results.clearRetainingCapacity();
        self.worklist.clearRetainingCapacity();
        self.block_count = func.blocks.items.len;

        // Step 1: 初始化所有寄存器状态（默认为不逃逸）
        try self.initRegisters(func);

        // Step 2: 第一遍标记明显逃逸的情况
        try self.markEscapingInstructions(func);

        // Step 3: 标记跨基本块使用的寄存器
        try self.markCrossBlockUsage(func);

        // Step 4: 传播逃逸信息（不动点迭代）
        try self.propagateEscape(func);

        // Step 5: 标记返回值所有权转移候选
        try self.markReturnOwnershipTransfer(func);

        // Step 6: 计算最终的栈分配候选
        try self.computeStackAllocationCandidates(func);
    }

    /// 初始化所有寄存器：默认不逃逸，记录定义块
    fn initRegisters(self: *EscapeAnalysis, func: *Function) !void {
        for (func.blocks.items, 0..) |block, block_idx| {
            // 检查指令的输出寄存器
            for (block.instructions.items) |inst| {
                if (inst.result) |reg| {
                    const existing = try self.results.getOrPut(reg.id);
                    if (!existing.found_existing) {
                        existing.value_ptr.* = .{
                            .escaped = false,
                            .cross_block = false,
                            .can_stack_allocate = false,
                            .return_ownership_transfer = false,
                            .defining_block = block_idx,
                        };
                    }
                }
            }
        }
        // 参数寄存器初始化为跨块（可能从外部逃逸）
        for (func.params.items) |param| {
            if (self.results.getPtr(param.register.id)) |r| {
                r.escaped = true;
                r.cross_block = true;
            } else {
                try self.results.put(param.register.id, .{
                    .escaped = true,
                    .cross_block = true,
                    .can_stack_allocate = false,
                    .return_ownership_transfer = false,
                    .defining_block = 0,
                });
            }
        }
    }

    /// 第一遍：标记明显逃逸的指令
    fn markEscapingInstructions(self: *EscapeAnalysis, func: *Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                switch (inst.op) {
                    // 函数调用：参数逃逸
                    .call => |op| {
                        for (op.args) |arg| {
                            try self.markEscaped(arg.id);
                        }
                    },
                    .method_call, .static_method_call, .parent_call => |op| {
                        for (op.args) |arg| {
                            try self.markEscaped(arg.id);
                        }
                    },
                    .call_indirect => |op| {
                        for (op.args) |arg| {
                            try self.markEscaped(arg.id);
                        }
                    },
                    // 数组操作逃逸
                    .array_set => |op| {
                        try self.markEscaped(op.array.id);
                        try self.markEscaped(op.value.id);
                    },
                    .array_set_nested => |op| {
                        try self.markEscaped(op.outer_array.id);
                        try self.markEscaped(op.value.id);
                    },
                    .array_push => |op| {
                        try self.markEscaped(op.array.id);
                        try self.markEscaped(op.value.id);
                    },
                    // 对象属性写逃逸
                    .object_set => |op| {
                        try self.markEscaped(op.object.id);
                        try self.markEscaped(op.value.id);
                    },
                    // 捕获变量写入逃逸
                    .capture_set => {
                        if (inst.op.capture_set.value) |val| {
                            try self.markEscaped(val.id);
                        }
                    },
                    // 全局变量写入逃逸
                    .global_set => {
                        if (inst.op.global_set.value) |val| {
                            try self.markEscaped(val.id);
                        }
                        if (inst.op.global_set.target) |tgt| {
                            try self.markEscaped(tgt.id);
                        }
                    },
                    .global_set_dynamic => {
                        try self.markEscaped(inst.op.global_set_dynamic.value.id);
                    },
                    .global_ref_bind => {
                        if (inst.op.global_ref_bind.value) |val| {
                            try self.markEscaped(val.id);
                        }
                    },
                    // goroutine 启动逃逸
                    .go_spawn => |op| {
                        for (op.args) |arg| {
                            try self.markEscaped(arg.id);
                        }
                    },
                    // channel 发送逃逸
                    .channel_send => |op| {
                        try self.markEscaped(op.value.id);
                    },
                    // store 到 alloca 视为逃逸边界
                    .store => |op| {
                        try self.markEscaped(op.operand.id);
                    },
                    else => {},
                }
            }

            // 块终止符：返回值不标记为逃逸（所有权转移）
            switch (block.terminator) {
                .ret => |ret_val| {
                    if (self.results.getPtr(ret_val.id)) |r| {
                        r.return_ownership_transfer = true;
                    }
                },
                .br_cond => {},
                .br => {},
                .switch_ => {},
                .unreachable => {},
            }
        }
    }

    /// 标记跨基本块使用的寄存器
    fn markCrossBlockUsage(self: *EscapeAnalysis, func: *Function) !void {
        for (func.blocks.items, 0..) |block, block_idx| {
            for (block.instructions.items) |inst| {
                const used_regs = self.getUsedRegsSlice(inst);
                for (used_regs) |reg_id| {
                    if (self.results.getPtr(reg_id)) |r| {
                        if (r.defining_block) |def_block| {
                            if (def_block != block_idx) {
                                r.cross_block = true;
                            }
                        }
                    }
                }
            }

            // 检查终止符中对寄存器的使用
            switch (block.terminator) {
                .ret => |ret_val| {
                    if (self.results.getPtr(ret_val.id)) |r| {
                        if (r.defining_block) |def_block| {
                            if (def_block != block_idx) {
                                r.cross_block = true;
                            }
                        }
                    }
                },
                .br_cond => |br| {
                    if (self.results.getPtr(br.cond.id)) |r| {
                        if (r.defining_block) |def_block| {
                            if (def_block != block_idx) {
                                r.cross_block = true;
                            }
                        }
                    }
                },
                else => {},
            }

            // PHI 指令的输入也跨块
            for (block.instructions.items) |inst| {
                if (inst.op == .phi) {
                    const phi = inst.op.phi;
                    for (phi.incoming) |incoming| {
                        if (self.results.getPtr(incoming.value.id)) |r| {
                            if (r.defining_block) |def_block| {
                                r.cross_block = true;
                            }
                        }
                    }
                }
            }
        }
    }

    /// 获取指令使用的寄存器——对于多参数操作使用堆分配的切片
    /// 调用者负责释放返回的切片（对于 len > 2 的情况）
    fn getUsedRegsSlice(self: *EscapeAnalysis, inst: *const Instruction) []const usize {
        _ = self;
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod, .concat, .and, .or, .xor, .eq, .ne, .lt, .le, .gt, .ge,
            .identical, .not_identical, .spaceship, .pow, .bool_or, .logical_xor => |op| {
                return &[_]usize{ op.lhs.id, op.rhs.id };
            },
            .neg, .not, .cast, .is_null, .is_bool, .is_int, .is_float, .is_string,
            .is_array, .is_object, .is_callable, .is_resource, .strlen,
            .type_check, .get_type, .array_count => |op| {
                return &[_]usize{op.operand.id};
            },
            .array_get => |op| {
                return &[_]usize{ op.array.id, op.key.id };
            },
            .array_set => |op| {
                return &[_]usize{ op.array.id, op.key.id, op.value.id };
            },
            .array_set_nested => |op| {
                return &[_]usize{ op.outer_array.id, op.outer_key.id, op.inner_key.id, op.value.id };
            },
            .array_push => |op| {
                return &[_]usize{ op.array.id, op.value.id };
            },
            .array_key_exists => |op| {
                return &[_]usize{ op.array.id, op.key.id };
            },
            .array_unset => |op| {
                return &[_]usize{ op.array.id, op.key.id };
            },
            .property_get => |op| {
                return &[_]usize{ op.object.id, op.name.id };
            },
            .object_set => |op| {
                return &[_]usize{ op.object.id, op.name.id, op.value.id };
            },
            .move, .store, .load, .box, .unbox => |op| {
                return &[_]usize{op.operand.id};
            },
            .select => |op| {
                return &[_]usize{ op.cond.id, op.true_value.id, op.false_value.id };
            },
            // 可变长度操作：返回空切片，由调用方单独处理
            .call, .phi, .method_call, .static_method_call, .parent_call, .call_indirect => {
                return &[_]usize{};
            },
            .capture_get, .capture_set, .global_get, .global_set,
            .global_set_dynamic, .global_ref_bind,
            .array_ensure, .new_object, .closure_new,
            .make_ref, .make_ref_ptr, .val_deref,
            .go_spawn, .channel_new, .channel_send, .channel_recv, .await_,
            .clone, .interpolate, .include_, .require_, .param,
            .alloca, .const_int, .const_float, .const_bool, .const_string,
            .const_null, .const_missing, .ret => {
                return &[_]usize{};
            },
        }
    }

    /// 传播逃逸信息（不动点迭代）
    fn propagateEscape(self: *EscapeAnalysis, func: *Function) !void {
        // 使用 worklist 传播：如果一个寄存器逃逸，所有使用它的指令的结果也逃逸
        while (self.worklist.items.len > 0) {
            const reg_id = self.worklist.pop();

            // 查找所有使用此寄存器的指令，标记其结果也逃逸
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.result) |result| {
                        if (self.instructionUsesRegister(inst, reg_id)) {
                            try self.markEscaped(result.id);
                        }
                    }
                }
            }
        }
    }

    /// 检查指令是否使用指定寄存器
    fn instructionUsesRegister(self: *EscapeAnalysis, inst: *const Instruction, reg_id: usize) bool {
        _ = self;
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod, .concat, .and, .or, .xor, .eq, .ne, .lt, .le, .gt, .ge,
            .identical, .not_identical, .spaceship, .pow, .bool_or, .logical_xor => |op| {
                return op.lhs.id == reg_id or op.rhs.id == reg_id;
            },
            .neg, .not, .cast, .is_null, .is_bool, .is_int, .is_float, .is_string,
            .is_array, .is_object, .is_callable, .is_resource, .strlen,
            .type_check, .get_type, .array_count => |op| {
                return op.operand.id == reg_id;
            },
            .call => |op| {
                for (op.args) |arg| {
                    if (arg.id == reg_id) return true;
                }
                return false;
            },
            .array_get => |op| {
                return op.array.id == reg_id or op.key.id == reg_id;
            },
            .array_set => |op| {
                return op.array.id == reg_id or op.key.id == reg_id or op.value.id == reg_id;
            },
            .array_push => |op| {
                return op.array.id == reg_id or op.value.id == reg_id;
            },
            .move, .store, .load, .box, .unbox => |op| {
                return op.operand.id == reg_id;
            },
            .select => |op| {
                return op.cond.id == reg_id or op.true_value.id == reg_id or op.false_value.id == reg_id;
            },
            .method_call, .static_method_call => |op| {
                if (op.object.id == reg_id) return true;
                for (op.args) |arg| {
                    if (arg.id == reg_id) return true;
                }
                return false;
            },
            else => return false,
        }
    }

    /// 标记寄存器为逃逸
    fn markEscaped(self: *EscapeAnalysis, reg_id: usize) !void {
        const result = try self.results.getOrPut(reg_id);
        if (!result.found_existing) {
            result.value_ptr.* = .{
                .escaped = true,
                .cross_block = true,
                .can_stack_allocate = false,
                .return_ownership_transfer = false,
                .defining_block = null,
            };
            try self.worklist.append(reg_id);
        } else if (!result.value_ptr.escaped) {
            result.value_ptr.escaped = true;
            try self.worklist.append(reg_id);
        }
    }

    /// 标记返回值所有权转移
    fn markReturnOwnershipTransfer(self: *EscapeAnalysis, func: *Function) !void {
        // 遍历所有基本块的终止符，找到所有的 .ret
        for (func.blocks.items) |block| {
            if (block.terminator == .ret) {
                const reg_id = block.terminator.ret.id;
                if (self.results.getPtr(reg_id)) |r| {
                    // 只有堆类型才能做所有权转移
                    // 如果返回值不逃逸且不跨块，可以跳过 retain/release
                    if (!r.escaped and !r.cross_block) {
                        r.return_ownership_transfer = true;
                    }
                }
            }
        }
    }

    /// 计算栈分配候选
    fn computeStackAllocationCandidates(self: *EscapeAnalysis, func: *Function) !void {
        _ = func;
        var it = self.results.iterator();
        while (it.next()) |entry| {
            const reg_id = entry.key_ptr.*;
            const result = entry.value_ptr;

            // 栈分配条件：
            // 1. 不逃逸出函数
            // 2. 不跨基本块使用
            // 3. 不是参数（参数总是栈分配的）
            if (!result.escaped and !result.cross_block and result.defining_block != null) {
                result.can_stack_allocate = true;
            }
        }
    }
};