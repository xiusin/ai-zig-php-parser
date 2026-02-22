//! 嵌套循环代码生成 V3 - 基于显式栈的迭代式生成器
//!
//! 设计原则：
//! 1. 零递归：使用显式工作栈替代递归调用，支持任意嵌套深度
//! 2. 结构化输出：通过 ZigCodeBuilder 管理动态缩进
//! 3. LoopMetadata 驱动：基于 IR 块元数据识别循环角色，消除魔法字符串
//! 4. 类型安全：PHI 节点更新自动注入类型转换
//!
//! @ownership NON-OWNING (allocator)
//! @thread-safety ISOLATED

const std = @import("std");
const IR = @import("ir.zig");
const ZigCodeBuilder = @import("zig_code_builder.zig").ZigCodeBuilder;
const Allocator = std.mem.Allocator;

/// 累加器信息
pub const AccumulatorInfo = struct {
    reg_id: usize,
    type_: IR.Type,
    init_reg: ?usize,
    from_outer: bool = false,
};

/// 循环工作栈帧——每个帧代表一个待生成的循环层
const LoopFrame = struct {
    /// 循环 header 块索引
    header_idx: usize,
    /// 循环 body 起始块索引
    body_start_idx: usize,
    /// increment 块索引
    increment_idx: ?usize,
    /// exit 块索引
    exit_idx: ?usize,
    /// 是否是 for 循环
    is_for: bool,
    /// 子循环的 header 索引列表
    children: []const usize,
    /// 当前处理阶段
    phase: Phase,
    /// 嵌套深度（0 = 最外层）
    depth: u32,

    const Phase = enum {
        /// 生成循环头和条件检查
        emit_header,
        /// 生成循环体（header 之后、子循环之前的指令）
        emit_body_pre,
        /// 子循环已入栈，等待子循环完成后继续
        children_pending,
        /// 生成循环体（子循环之后的指令）
        emit_body_post,
        /// 生成 increment 和 PHI 更新
        emit_increment,
        /// 生成闭合括号
        emit_close,
    };
};

/// 嵌套循环代码生成器 V3
pub const NestedLoopCodegenV3 = struct {
    allocator: Allocator,
    builder: *ZigCodeBuilder,
    /// 工作栈
    stack: std.ArrayList(LoopFrame),
    /// 类型推断表（可选）
    inferred_types: ?*const std.AutoHashMap(usize, IR.Type),
    /// alloca 寄存器集合（可选）
    alloca_regs: ?*const std.AutoHashMap(usize, void),

    /// 初始化生成器
    pub fn init(
        allocator: Allocator,
        builder: *ZigCodeBuilder,
        inferred_types: ?*const std.AutoHashMap(usize, IR.Type),
        alloca_regs: ?*const std.AutoHashMap(usize, void),
    ) NestedLoopCodegenV3 {
        return .{
            .allocator = allocator,
            .builder = builder,
            .stack = std.ArrayList(LoopFrame).initCapacity(
                allocator,
                0,
            ) catch unreachable,
            .inferred_types = inferred_types,
            .alloca_regs = alloca_regs,
        };
    }

    /// 释放资源
    pub fn deinit(self: *NestedLoopCodegenV3) void {
        self.stack.deinit(self.allocator);
    }

    /// 获取寄存器的推断类型
    fn getRegType(self: *const NestedLoopCodegenV3, reg_id: usize, fallback: IR.Type) IR.Type {
        if (self.inferred_types) |types| {
            if (types.get(reg_id)) |t| return t;
        }
        return fallback;
    }

    /// 获取操作数引用（处理 alloca 寄存器）
    fn getOperandRef(self: *const NestedLoopCodegenV3, buf: []u8, reg_id: usize) ![]const u8 {
        const is_alloca = if (self.alloca_regs) |regs|
            regs.contains(reg_id)
        else
            false;
        
        return if (is_alloca) 
            try std.fmt.bufPrint(buf, "reg_{d}.*", .{reg_id})
        else 
            try std.fmt.bufPrint(buf, "reg_{d}", .{reg_id});
    }

    /// 判断块是否在循环外（用于 PHI init 值识别）
    fn isOutsideLoop(
        incoming_block: *const IR.BasicBlock,
        header_idx: usize,
        func: *const IR.Function,
        body_start: usize,
        increment_idx: ?usize,
    ) bool {
        _ = func;
        const idx = incoming_block.index;
        // 循环外 = 不是 header / body / increment
        if (idx == header_idx) return false;
        if (idx == body_start) return false;
        if (increment_idx) |inc| {
            if (idx == inc) return false;
        }
        // 使用 LoopMetadata（如果有）
        const role = incoming_block.loop_metadata.role;
        if (role == .init or role == .none or role == .exit) return true;
        // 块索引小于 header 通常是 init 块
        return idx < header_idx;
    }

    /// 查找寄存器的定义指令
    fn findRegDef(func: *const IR.Function, reg_id: usize) ?*const IR.Instruction {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |r| {
                    if (r.id == reg_id) return inst;
                }
            }
        }
        return null;
    }

    /// 检查是否为归纳变量（常量步长递增）
    fn isInductionVar(func: *const IR.Function, loop_value_reg: usize) bool {
        const def = findRegDef(func, loop_value_reg) orelse return false;
        if (def.op != .add) return false;
        const rhs_def = findRegDef(func, def.op.add.rhs.id) orelse return false;
        return rhs_def.op == .const_int;
    }

    /// 分析循环累加器（基于 PHI 模式，无魔法字符串）
    pub fn analyzeAccumulators(
        self: *NestedLoopCodegenV3,
        func: *const IR.Function,
        header_idx: usize,
        body_start: usize,
        increment_idx: ?usize,
    ) !std.ArrayList(AccumulatorInfo) {
        var result = try std.ArrayList(AccumulatorInfo)
            .initCapacity(self.allocator, 0);

        const header = func.blocks.items[header_idx];
        for (header.instructions.items) |inst| {
            if (inst.op != .phi) continue;
            const phi_op = inst.op.phi;
            const res = inst.result orelse continue;
            if (phi_op.incoming.len < 2) continue;

            var init_val: ?usize = null;
            var loop_val: ?usize = null;
            for (phi_op.incoming) |inc| {
                if (isOutsideLoop(inc.block, header_idx, func, body_start, increment_idx)) {
                    init_val = inc.value.id;
                } else {
                    loop_val = inc.value.id;
                }
            }
            // 回退
            if (init_val == null and loop_val == null and phi_op.incoming.len >= 2) {
                init_val = phi_op.incoming[0].value.id;
                loop_val = phi_op.incoming[1].value.id;
            }
            if (loop_val) |lv| {
                if (!isInductionVar(func, lv)) {
                    try result.append(self.allocator, .{
                        .reg_id = res.id,
                        .type_ = res.type_,
                        .init_reg = init_val,
                    });
                }
            }
        }
        return result;
    }

    /// 将一个循环及其子循环推入工作栈
    /// 注意：子循环先入栈（后处理），当前循环后入栈（先处理）
    pub fn pushLoop(
        self: *NestedLoopCodegenV3,
        header_idx: usize,
        body_start: usize,
        increment_idx: ?usize,
        exit_idx: ?usize,
        is_for: bool,
        children: []const usize,
        depth: u32,
    ) !void {
        try self.stack.append(self.allocator, .{
            .header_idx = header_idx,
            .body_start_idx = body_start,
            .increment_idx = increment_idx,
            .exit_idx = exit_idx,
            .is_for = is_for,
            .children = children,
            .phase = .emit_header,
            .depth = depth,
        });
    }

    /// 主生成循环：迭代式处理工作栈
    /// 每次调用处理栈顶帧的当前 phase，然后推进到下一个 phase
    pub fn generate(
        self: *NestedLoopCodegenV3,
        func: *const IR.Function,
        all_loops: []const LoopFrameInfo,
    ) !void {
        while (self.stack.items.len > 0) {
            const frame = &self.stack.items[self.stack.items.len - 1];
            switch (frame.phase) {
                .emit_header => {
                    try self.emitLoopHeader(func, frame.*);
                    frame.phase = .emit_body_pre;
                },
                .emit_body_pre => {
                    try self.emitBodyPre(func, frame.*);
                    if (frame.children.len > 0) {
                        frame.phase = .children_pending;
                        // 子循环逆序入栈（保证正序处理）
                        var i = frame.children.len;
                        while (i > 0) {
                            i -= 1;
                            const child_idx = frame.children[i];
                            const child = all_loops[child_idx];
                            try self.pushLoop(
                                child.header_idx,
                                child.body_start_idx,
                                child.increment_idx,
                                child.exit_idx,
                                child.is_for,
                                child.children,
                                frame.depth + 1,
                            );
                        }
                    } else {
                        frame.phase = .emit_increment;
                    }
                },
                .children_pending => {
                    // 子循环已经全部处理完（它们从栈中弹出了）
                    frame.phase = .emit_body_post;
                },
                .emit_body_post => {
                    // 子循环结束后的额外 body 指令
                    frame.phase = .emit_increment;
                },
                .emit_increment => {
                    try self.emitIncrement(func, frame.*);
                    try self.emitPhiUpdate(func, frame.*);
                    frame.phase = .emit_close;
                },
                .emit_close => {
                    try self.builder.endScope();
                    _ = self.stack.pop();
                },
            }
        }
    }

    /// 生成循环头：while(true) + 条件检查
    fn emitLoopHeader(
        self: *NestedLoopCodegenV3,
        func: *const IR.Function,
        frame: LoopFrame,
    ) !void {
        const header = func.blocks.items[frame.header_idx];

        // 初始化 PHI 节点（从循环外来源获取初始值）
        for (header.instructions.items) |inst| {
            if (inst.op != .phi) continue;
            const phi_op = inst.op.phi;
            const res = inst.result orelse continue;
            for (phi_op.incoming) |inc| {
                if (isOutsideLoop(inc.block, frame.header_idx, func, frame.body_start_idx, frame.increment_idx)) {
                    try self.builder.writeLineFmt(
                        "reg_{d} = reg_{d};",
                        .{ res.id, inc.value.id },
                    );
                    break;
                }
            }
        }

        try self.builder.beginScope("while (true)");
        try self.builder.writeComment(header.label);
    }

    /// 生成循环体前段（子循环之前的指令）
    fn emitBodyPre(
        self: *NestedLoopCodegenV3,
        func: *const IR.Function,
        frame: LoopFrame,
    ) !void {
        // 生成 header 块中非 PHI 的条件检查
        const header = func.blocks.items[frame.header_idx];
        if (header.terminator) |term| {
            if (term == .cond_br) {
                // 查找条件寄存器对应的比较指令
                for (header.instructions.items) |inst| {
                    if (inst.result) |res| {
                        if (res.id == term.cond_br.cond.id) {
                            try self.emitCondBreak(inst);
                            break;
                        }
                    }
                }
            }
        }

        // 生成 body 块指令
        const body = func.blocks.items[frame.body_start_idx];
        try self.builder.writeComment(body.label);
        for (body.instructions.items) |inst| {
            if (inst.op == .phi) continue;
            try self.emitSimpleInstruction(inst);
        }
    }

    /// 生成条件 break
    fn emitCondBreak(self: *NestedLoopCodegenV3, cond_inst: *const IR.Instruction) !void {
        // 简化：根据比较指令类型生成 break 条件
        switch (cond_inst.op) {
            .lt => |op| {
                try self.builder.writeLineFmt(
                    "if (!(reg_{d} < reg_{d})) break;",
                    .{ op.lhs.id, op.rhs.id },
                );
            },
            .le => |op| {
                try self.builder.writeLineFmt(
                    "if (!(reg_{d} <= reg_{d})) break;",
                    .{ op.lhs.id, op.rhs.id },
                );
            },
            .gt => |op| {
                try self.builder.writeLineFmt(
                    "if (!(reg_{d} > reg_{d})) break;",
                    .{ op.lhs.id, op.rhs.id },
                );
            },
            .ge => |op| {
                try self.builder.writeLineFmt(
                    "if (!(reg_{d} >= reg_{d})) break;",
                    .{ op.lhs.id, op.rhs.id },
                );
            },
            .eq => |op| {
                try self.builder.writeLineFmt(
                    "if (!(reg_{d} == reg_{d})) break;",
                    .{ op.lhs.id, op.rhs.id },
                );
            },
            .ne => |op| {
                try self.builder.writeLineFmt(
                    "if (!(reg_{d} != reg_{d})) break;",
                    .{ op.lhs.id, op.rhs.id },
                );
            },
            else => {
                // 泛化：使用寄存器值作为布尔判断
                if (cond_inst.result) |res| {
                    try self.builder.writeLineFmt(
                        "if (!reg_{d}) break;",
                        .{res.id},
                    );
                }
            },
        }
    }

    /// 生成简单指令（占位，由 native_linker 的 generateInstructionSimple 委托）
    fn emitSimpleInstruction(self: *NestedLoopCodegenV3, inst: *const IR.Instruction) !void {
        // 生成源码位置注释
        if (inst.location.line > 0) {
            try self.builder.writeLineFmt(
                "// {s}:{d}",
                .{ inst.location.file, inst.location.line },
            );
        }
        // 指令体由外部委托处理，这里仅作占位标记
        switch (inst.op) {
            .add => |op| {
                if (inst.result) |res| {
                    try self.builder.writeLineFmt(
                        "reg_{d} = reg_{d} + reg_{d};",
                        .{ res.id, op.lhs.id, op.rhs.id },
                    );
                }
            },
            .sub => |op| {
                if (inst.result) |res| {
                    try self.builder.writeLineFmt(
                        "reg_{d} = reg_{d} - reg_{d};",
                        .{ res.id, op.lhs.id, op.rhs.id },
                    );
                }
            },
            .mul => |op| {
                if (inst.result) |res| {
                    try self.builder.writeLineFmt(
                        "reg_{d} = reg_{d} * reg_{d};",
                        .{ res.id, op.lhs.id, op.rhs.id },
                    );
                }
            },
            .const_int => |val| {
                if (inst.result) |res| {
                    try self.builder.writeLineFmt(
                        "reg_{d} = {d};",
                        .{ res.id, val },
                    );
                }
            },
            .phi => {},
            else => {
                // 其他指令由外部 native_linker 处理
            },
        }
    }

    /// 生成 increment 块
    fn emitIncrement(
        self: *NestedLoopCodegenV3,
        func: *const IR.Function,
        frame: LoopFrame,
    ) !void {
        if (frame.increment_idx) |inc_idx| {
            const inc_block = func.blocks.items[inc_idx];
            try self.builder.writeComment(inc_block.label);
            for (inc_block.instructions.items) |inst| {
                if (inst.op == .phi) continue;
                try self.emitSimpleInstruction(inst);
            }
        }
    }

    /// 生成 PHI 节点更新（循环变量回边赋值）
    fn emitPhiUpdate(
        self: *NestedLoopCodegenV3,
        func: *const IR.Function,
        frame: LoopFrame,
    ) !void {
        const header = func.blocks.items[frame.header_idx];
        for (header.instructions.items) |inst| {
            if (inst.op != .phi) continue;
            const phi_op = inst.op.phi;
            const res = inst.result orelse continue;

            // 查找来自 increment 或 body 的 incoming 值
            var update_val: ?usize = null;
            if (frame.increment_idx) |inc_idx| {
                const inc_block = func.blocks.items[inc_idx];
                for (phi_op.incoming) |inc| {
                    if (inc.block == inc_block) {
                        update_val = inc.value.id;
                        break;
                    }
                }
            }
            if (update_val == null) {
                const body = func.blocks.items[frame.body_start_idx];
                for (phi_op.incoming) |inc| {
                    if (inc.block == body) {
                        update_val = inc.value.id;
                        break;
                    }
                }
            }
            // 回退：取非 init 的 incoming
            if (update_val == null) {
                for (phi_op.incoming) |inc| {
                    if (!isOutsideLoop(inc.block, frame.header_idx, func, frame.body_start_idx, frame.increment_idx)) {
                        update_val = inc.value.id;
                        break;
                    }
                }
            }

            if (update_val) |val_reg| {
                const phi_type = self.getRegType(res.id, res.type_);
                const val_type = self.getRegType(val_reg, IR.Type.php_value);
                const phi_tag = @as(std.meta.Tag(IR.Type), phi_type);
                const val_tag = @as(std.meta.Tag(IR.Type), val_type);

                var src_buf: [32]u8 = undefined;
                const src_ref = try self.getOperandRef(&src_buf, val_reg);

                if (phi_tag == val_tag) {
                    try self.builder.writeLineFmt(
                        "reg_{d} = {s};",
                        .{ res.id, src_ref },
                    );
                } else if (phi_tag == .i64 and val_tag == .php_value) {
                    try self.builder.writeLineFmt(
                        "reg_{d} = {s}.asInt();",
                        .{ res.id, src_ref },
                    );
                } else if (phi_tag == .f64 and val_tag == .php_value) {
                    try self.builder.writeLineFmt(
                        "reg_{d} = {s}.asFloat();",
                        .{ res.id, src_ref },
                    );
                } else {
                    try self.builder.writeLineFmt(
                        "reg_{d} = {s};",
                        .{ res.id, src_ref },
                    );
                }
            }
        }
    }
};

/// 循环帧信息（供外部传入的简化版 LoopInfo）
pub const LoopFrameInfo = struct {
    header_idx: usize,
    body_start_idx: usize,
    increment_idx: ?usize,
    exit_idx: ?usize,
    is_for: bool,
    children: []const usize,
};
