const std = @import("std");
const IR = @import("ir.zig");

/// 活跃性分析：使用 bitset 高性能实现
/// 寄存器集合用 bitset 表示，操作复杂度 O(N/64)，比 HashMap 快 10-100x
pub const LivenessAnalysis = struct {
    allocator: std.mem.Allocator,
    max_reg_id: usize = 0, // 最大寄存器 ID + 1
    words_per_set: usize = 0, // 每个 bitset 需要多少个 u64

    // 块级 live_in/live_out（扁平存储，预分配一次大块）
    live_in_storage: ?[]u64 = null,
    live_out_storage: ?[]u64 = null,
    num_blocks: usize = 0,

    // 指令级 live_out（扁平存储）
    inst_live_out_storage: ?[]u64 = null,
    inst_offsets: ?[]usize = null, // 每个块的第一条指令在扁平数组中的偏移
    inst_counts: ?[]usize = null, // 每个块的指令数

    const Self = @This();
    const WORD_BITS: usize = 64;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.live_in_storage) |s| self.allocator.free(s);
        if (self.live_out_storage) |s| self.allocator.free(s);
        if (self.inst_live_out_storage) |s| self.allocator.free(s);
        if (self.inst_offsets) |s| self.allocator.free(s);
        if (self.inst_counts) |s| self.allocator.free(s);
    }

    // === Bitset 原语 ===

    inline fn bitSet(set: []u64, idx: usize) void {
        const word_idx = idx / WORD_BITS;
        if (word_idx >= set.len) return;
        const bit_idx: u6 = @intCast(idx % WORD_BITS);
        set[word_idx] |= (@as(u64, 1) << bit_idx);
    }

    inline fn bitUnset(set: []u64, idx: usize) void {
        const word_idx = idx / WORD_BITS;
        const bit_idx: u6 = @intCast(idx % WORD_BITS);
        set[word_idx] &= ~(@as(u64, 1) << bit_idx);
    }

    inline fn bitIsSet(set: []const u64, idx: usize) bool {
        const word_idx = idx / WORD_BITS;
        const bit_idx: u6 = @intCast(idx % WORD_BITS);
        return (set[word_idx] & (@as(u64, 1) << bit_idx)) != 0;
    }

    inline fn bitCopy(dst: []u64, src: []const u64) void {
        @memcpy(dst, src);
    }

    inline fn bitClearAll(set: []u64) void {
        @memset(set, 0);
    }

    inline fn bitUnion(dst: []u64, src: []const u64) void {
        for (dst, src) |*d, s| d.* |= s;
    }

    inline fn bitEquals(a: []const u64, b: []const u64) bool {
        for (a, b) |x, y| {
            if (x != y) return false;
        }
        return true;
    }

    // === 存储访问 ===

    fn getLiveIn(self: *Self, block_idx: usize) []u64 {
        const start = block_idx * self.words_per_set;
        return self.live_in_storage.?[start .. start + self.words_per_set];
    }

    fn getLiveOut(self: *Self, block_idx: usize) []u64 {
        const start = block_idx * self.words_per_set;
        return self.live_out_storage.?[start .. start + self.words_per_set];
    }

    fn getInstLiveOut(self: *const Self, block_idx: usize, inst_idx: usize) []const u64 {
        if (self.inst_live_out_storage == null) return &[_]u64{};
        if (self.inst_offsets == null) return &[_]u64{};
        const base = self.inst_offsets.?[block_idx] + inst_idx;
        const start = base * self.words_per_set;
        return self.inst_live_out_storage.?[start .. start + self.words_per_set];
    }

    // === 分析入口 ===

    /// 分析函数的活跃性（bitset 高性能实现）
    pub fn analyze(self: *Self, func: *const IR.Function) !void {
        self.num_blocks = func.blocks.items.len;
        if (self.num_blocks == 0) return;

        // 1. 预计算最大寄存器 ID + 指令数
        // 根本性修复：遍历指令 result + 所有操作数 + PHI incoming + 终止指令操作数
        // 之前仅遍历 result + 终止指令操作数，遗漏 PHI incoming 和部分指令操作数，
        // 导致 bitSet 越界（c047/c050 崩溃）
        self.max_reg_id = 0;
        var total_insts: usize = 0;
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |reg| {
                    self.updateMaxReg(reg.id);
                }
                self.updateMaxRegIdFromInst(inst.*);
            }
            // 终止指令操作数
            if (block.terminator) |term| {
                self.updateMaxRegIdFromTerminator(term);
            }
            total_insts += block.instructions.items.len;
        }

        if (self.max_reg_id == 0) return;
        self.words_per_set = (self.max_reg_id + WORD_BITS - 1) / WORD_BITS;
        if (self.words_per_set == 0) self.words_per_set = 1;

        // 2. 预分配所有存储（一次大分配，避免反复 alloc）
        const block_set_size = self.num_blocks * self.words_per_set;
        self.live_in_storage = try self.allocator.alloc(u64, block_set_size);
        self.live_out_storage = try self.allocator.alloc(u64, block_set_size);
        bitClearAll(self.live_in_storage.?);
        bitClearAll(self.live_out_storage.?);

        // 指令级存储
        if (total_insts > 0) {
            const inst_set_size = total_insts * self.words_per_set;
            self.inst_live_out_storage = try self.allocator.alloc(u64, inst_set_size);
            bitClearAll(self.inst_live_out_storage.?);

            self.inst_offsets = try self.allocator.alloc(usize, self.num_blocks);
            self.inst_counts = try self.allocator.alloc(usize, self.num_blocks);
            var offset: usize = 0;
            for (func.blocks.items, 0..) |block, i| {
                self.inst_offsets.?[i] = offset;
                self.inst_counts.?[i] = block.instructions.items.len;
                offset += block.instructions.items.len;
            }
        }

        // 3. 预分配工作 bitset（迭代中复用，零分配）
        const work_live_out = try self.allocator.alloc(u64, self.words_per_set);
        defer self.allocator.free(work_live_out);
        const work_live_in = try self.allocator.alloc(u64, self.words_per_set);
        defer self.allocator.free(work_live_in);

        // 4. 反向数据流分析，迭代到不动点
        var changed = true;
        var iterations: usize = 0;
        while (changed and iterations < 100) : (iterations += 1) {
            changed = false;

            var block_idx: usize = self.num_blocks;
            while (block_idx > 0) {
                block_idx -= 1;
                const block = func.blocks.items[block_idx];

                // 计算 live_out[B] = ∪ live_in[S] for S in successors(B)
                bitClearAll(work_live_out);
                self.computeLiveOut(func, block_idx, work_live_out);

                // 计算 live_in[B] = use ∪ (live_out - def)
                bitCopy(work_live_in, work_live_out);

                // 添加终止指令使用的寄存器
                if (block.terminator) |term| {
                    self.addTerminatorUsedRegs(work_live_in, term);
                }

                // 反向遍历指令
                var inst_idx: usize = block.instructions.items.len;
                while (inst_idx > 0) {
                    inst_idx -= 1;
                    const inst = block.instructions.items[inst_idx].*;

                    // 移除定义的寄存器
                    if (inst.result) |reg| {
                        bitUnset(work_live_in, reg.id);
                    }
                    // 添加使用的寄存器
                    self.addUsedRegs(work_live_in, inst);
                }

                // 检查是否改变
                const old_live_in = self.getLiveIn(block_idx);
                const old_live_out = self.getLiveOut(block_idx);

                if (!bitEquals(work_live_in, old_live_in) or
                    !bitEquals(work_live_out, old_live_out))
                {
                    changed = true;
                    bitCopy(old_live_in, work_live_in);
                    bitCopy(old_live_out, work_live_out);
                }
            }
        }

        // 5. 计算每条指令后的活跃变量
        self.computeInstLiveness(func);
    }

    /// 计算块出口的活跃变量
    fn computeLiveOut(self: *Self, func: *const IR.Function, block_idx: usize, out: []u64) void {
        const block = func.blocks.items[block_idx];

        // 收集后继块索引（静态缓冲区，支持 switch 多 case + exception_handler）
        var successors_buf: [32]usize = undefined;
        var num_succs: usize = 0;

        if (block.terminator) |term| {
            switch (term) {
                .br => |target| {
                    successors_buf[num_succs] = target.index;
                    num_succs += 1;
                },
                .cond_br => |br| {
                    successors_buf[num_succs] = br.then_block.index;
                    num_succs += 1;
                    successors_buf[num_succs] = br.else_block.index;
                    num_succs += 1;
                },
                .ret, .unreachable_, .throw => {},
                .switch_ => |sw| {
                    for (sw.cases) |case| {
                        successors_buf[num_succs] = case.block.index;
                        num_succs += 1;
                    }
                    successors_buf[num_succs] = sw.default.index;
                    num_succs += 1;
                },
            }
        } else if (block_idx + 1 < func.blocks.items.len) {
            successors_buf[num_succs] = block_idx + 1;
            num_succs += 1;
        }

        // 异常处理器也是后继块
        if (block.exception_handler) |handler| {
            successors_buf[num_succs] = handler.index;
            num_succs += 1;
        }

        // 合并后继块的 live_in + PHI incoming（标准 SSA liveness 语义）
        // PHI incoming 不在后继块的 live_in 中（addUsedRegs 不添加），
        // 而是对应前驱块末尾活跃。此处按前驱-后继对应关系精确添加。
        for (successors_buf[0..num_succs]) |succ_idx| {
            if (succ_idx < self.num_blocks) {
                const succ_live_in = self.getLiveIn(succ_idx);
                bitUnion(out, succ_live_in);

                // 添加后继块中 PHI 节点的 incoming（仅对应当前前驱块的）
                const succ_block = func.blocks.items[succ_idx];
                for (succ_block.instructions.items) |inst| {
                    switch (inst.op) {
                        .phi => |phi| {
                            for (phi.incoming) |inc| {
                                if (@as(usize, inc.block.index) == block_idx) {
                                    bitSet(out, inc.value.id);
                                }
                            }
                        },
                        else => break, // PHI 节点总是在块首，遇到非 PHI 即止
                    }
                }
            }
        }
    }

    /// 计算每条指令后的活跃变量
    fn computeInstLiveness(self: *Self, func: *const IR.Function) void {
        if (self.inst_live_out_storage == null) return;

        const current = self.allocator.alloc(u64, self.words_per_set) catch return;
        defer self.allocator.free(current);

        for (func.blocks.items, 0..) |block, block_idx| {
            const block_live_out = self.getLiveOut(block_idx);
            bitCopy(current, block_live_out);

            // 添加终止指令使用的寄存器
            if (block.terminator) |term| {
                self.addTerminatorUsedRegs(current, term);
            }

            // 反向遍历指令
            var inst_idx: usize = block.instructions.items.len;
            while (inst_idx > 0) {
                inst_idx -= 1;
                const inst = block.instructions.items[inst_idx].*;

                // 保存当前活跃集合（指令后）
                const base = self.inst_offsets.?[block_idx] + inst_idx;
                const start = base * self.words_per_set;
                const inst_live = self.inst_live_out_storage.?[start .. start + self.words_per_set];
                bitCopy(inst_live, current);

                // 更新活跃集合（指令前）
                if (inst.result) |reg| {
                    bitUnset(current, reg.id);
                }
                self.addUsedRegs(current, inst);
            }
        }
    }

    /// 判断寄存器在指令后是否活跃
    pub fn isLiveAfter(self: *const Self, block_idx: usize, inst_idx: usize, reg_id: usize) bool {
        if (self.inst_live_out_storage == null) return false;
        if (block_idx >= self.num_blocks) return false;
        if (self.inst_offsets == null or self.inst_counts == null) return false;
        if (inst_idx >= self.inst_counts.?[block_idx]) return false;
        if (reg_id >= self.max_reg_id) return false;
        const inst_live = self.getInstLiveOut(block_idx, inst_idx);
        if (inst_live.len == 0) return false;
        return bitIsSet(inst_live, reg_id);
    }

    /// 判断寄存器在块出口是否活跃（双重保护：防止 inst_live_out bug 导致误释放）
    pub fn isLiveAtBlockExit(self: *const Self, block_idx: usize, reg_id: usize) bool {
        if (self.live_out_storage == null) return false;
        if (block_idx >= self.num_blocks) return false;
        if (reg_id >= self.max_reg_id) return false;
        const start = block_idx * self.words_per_set;
        const block_live_out = self.live_out_storage.?[start .. start + self.words_per_set];
        return bitIsSet(block_live_out, reg_id);
    }

    // === max_reg_id 计算辅助函数 ===

    /// 更新 max_reg_id 以覆盖给定寄存器 ID
    inline fn updateMaxReg(self: *Self, reg_id: usize) void {
        if (reg_id + 1 > self.max_reg_id) self.max_reg_id = reg_id + 1;
    }

    // === 统一寄存器遍历（comptime 回调，消除 addUsedRegs/updateMaxRegIdFromInst 重复） ===

    /// bitSet 回调：对 set 中的 reg_id 位设置为 1
    fn bitSetCb(set: []u64, reg_id: usize) void {
        Self.bitSet(set, reg_id);
    }

    /// updateMaxReg 回调：更新 max_reg_id 覆盖 reg_id
    fn updateMaxRegCb(self: *Self, reg_id: usize) void {
        self.updateMaxReg(reg_id);
    }

    /// 遍历指令引用的所有寄存器操作数，对每个寄存器调用回调
    /// 统一 addUsedRegs（bitSet）和 updateMaxRegIdFromInst（updateMaxReg）的 switch 逻辑
    /// include_phi_incoming: 是否遍历 PHI incoming 值
    ///   - false: addUsedRegs 语义（PHI incoming 不在 PHI 块本身使用，由 computeLiveOut 处理）
    ///   - true: updateMaxRegIdFromInst 语义（max_reg_id 必须覆盖 PHI incoming 引用的寄存器 ID）
    fn forEachOperandReg(
        inst: IR.Instruction,
        ctx: anytype,
        comptime callback: anytype,
        comptime include_phi_incoming: bool,
    ) void {
        switch (inst.op) {
            // === BinaryOp (lhs, rhs) ===
            .add, .sub, .mul, .div, .mod, .pow, .concat, .eq, .ne, .lt, .le, .gt, .ge,
            .bit_and, .bit_or, .bit_xor, .shl, .shr,
            .identical, .not_identical, .spaceship, .and_, .or_ => |bin| {
                callback(ctx, bin.lhs.id);
                callback(ctx, bin.rhs.id);
            },
            // === UnaryOp (operand) ===
            .neg, .not, .bit_not, .move, .get_type, .clone, .retain, .release,
            .unset_var, .strlen, .array_count, .channel_close, .await_, .debug_print, .yield_from => |un| {
                callback(ctx, un.operand.id);
            },
            // === CastOp (value) ===
            .cast => |op| callback(ctx, op.value.id),
            // === TypeCheckOp (value) ===
            .type_check => |op| callback(ctx, op.value.id),
            // === CallOp (args) ===
            .call => |call| {
                for (call.args) |arg| callback(ctx, arg.id);
            },
            // === CallIndirectOp (func_ptr, args) ===
            .call_indirect => |call| {
                callback(ctx, call.func_ptr.id);
                for (call.args) |arg| callback(ctx, arg.id);
            },
            // === LoadOp (ptr) ===
            .load => |op| callback(ctx, op.ptr.id),
            // === StoreOp (ptr, value) ===
            .store => |op| {
                callback(ctx, op.ptr.id);
                callback(ctx, op.value.id);
            },
            // === MakeRefOp (ptr) ===
            .make_ref => |op| callback(ctx, op.ptr.id),
            // === global_set (value) ===
            .global_set => |op| {
                if (op.value) |val| callback(ctx, val.id);
            },
            // === global_unset (name) ===
            .global_unset => |op| callback(ctx, op.name.id),
            // === global_get_dynamic (name_reg) ===
            .global_get_dynamic => |op| callback(ctx, op.name_reg.id),
            // === global_set_dynamic (name_reg, value) ===
            .global_set_dynamic => |op| {
                callback(ctx, op.name_reg.id);
                callback(ctx, op.value.id);
            },
            // === ArrayGetOp (array, key) — array_get, array_ensure ===
            .array_get, .array_ensure => |op| {
                callback(ctx, op.array.id);
                callback(ctx, op.key.id);
            },
            // === ArraySetOp (array, key, value) ===
            .array_set => |op| {
                callback(ctx, op.array.id);
                callback(ctx, op.key.id);
                callback(ctx, op.value.id);
            },
            // === ArraySetNestedOp ===
            .array_set_nested => |op| {
                callback(ctx, op.outer_array.id);
                callback(ctx, op.outer_key.id);
                callback(ctx, op.inner_key.id);
                callback(ctx, op.value.id);
            },
            // === ArrayPushOp (array, value) ===
            .array_push => |op| {
                callback(ctx, op.array.id);
                callback(ctx, op.value.id);
            },
            // === ArrayKeyExistsOp (array, key) ===
            .array_key_exists => |op| {
                callback(ctx, op.array.id);
                callback(ctx, op.key.id);
            },
            // === ArrayUnsetOp (array, key) ===
            .array_unset => |op| {
                callback(ctx, op.array.id);
                callback(ctx, op.key.id);
            },
            // === InterpolateOp (parts) ===
            .interpolate => |op| {
                for (op.parts) |part| callback(ctx, part.id);
            },
            // === NewObjectOp (args) ===
            .new_object => |op| {
                for (op.args) |arg| callback(ctx, arg.id);
            },
            // === PropertyGetOp (object) ===
            .property_get => |op| callback(ctx, op.object.id),
            // === PropertySetOp (object, value) ===
            .property_set => |op| {
                callback(ctx, op.object.id);
                callback(ctx, op.value.id);
            },
            // === MethodCallOp (object, args) ===
            .method_call => |op| {
                callback(ctx, op.object.id);
                for (op.args) |arg| callback(ctx, arg.id);
            },
            // === StaticMethodCallOp (args) ===
            .static_method_call => |op| {
                for (op.args) |arg| callback(ctx, arg.id);
            },
            // === StaticPropertySetOp (value) ===
            .static_property_set => |op| callback(ctx, op.value.id),
            // === ClosureNewOp (func_ptr, captures) ===
            .closure_new => |op| {
                callback(ctx, op.func_ptr.id);
                for (op.captures) |cap| callback(ctx, cap.id);
            },
            // === ClosureBindOp (closure, object) ===
            .closure_bind => |op| {
                callback(ctx, op.closure.id);
                callback(ctx, op.object.id);
            },
            // === ImplementsInterfaceOp (object) ===
            .implements_interface => |op| callback(ctx, op.object.id),
            // === ParentCallOp (object, args) ===
            .parent_call => |op| {
                callback(ctx, op.object.id);
                for (op.args) |arg| callback(ctx, arg.id);
            },
            // === BoxOp / UnboxOp (value) ===
            .box => |op| callback(ctx, op.value.id),
            .unbox => |op| callback(ctx, op.value.id),
            // === InstanceOfOp (object, class_name) ===
            .instanceof => |op| {
                callback(ctx, op.object.id);
                callback(ctx, op.class_name.id);
            },
            // === PhiOp ===
            // PHI incoming 值：addUsedRegs 中不遍历（incoming 不在 PHI 块本身使用），
            // updateMaxRegIdFromInst 中遍历（max_reg_id 必须覆盖 PHI incoming 引用的寄存器 ID）
            .phi => |phi| {
                if (include_phi_incoming) {
                    for (phi.incoming) |inc| callback(ctx, inc.value.id);
                }
            },
            // === SelectOp (cond, then_value, else_value) ===
            .select => |op| {
                callback(ctx, op.cond.id);
                callback(ctx, op.then_value.id);
                callback(ctx, op.else_value.id);
            },
            // === GoSpawnOp (args) ===
            .go_spawn => |op| {
                for (op.args) |arg| callback(ctx, arg.id);
            },
            // === ChannelSendOp (channel, value) ===
            .channel_send => |op| {
                callback(ctx, op.channel.id);
                callback(ctx, op.value.id);
            },
            // === ChannelRecvOp (channel) ===
            .channel_recv => |op| callback(ctx, op.channel.id),
            // === SelectChannelOp (cases) ===
            .select_ => |op| {
                for (op.cases) |case| {
                    callback(ctx, case.channel.id);
                    if (case.value) |val| callback(ctx, val.id);
                }
            },
            // === YieldOp (key, value) ===
            .yield_val => |op| {
                if (op.key) |key| callback(ctx, key.id);
                if (op.value) |val| callback(ctx, val.id);
            },
            // === Instructions with no register operands ===
            else => {},
        }
    }

    /// 遍历终止指令引用的所有寄存器，对每个寄存器调用回调
    fn forEachTerminatorReg(
        term: IR.Terminator,
        ctx: anytype,
        comptime callback: anytype,
    ) void {
        switch (term) {
            .ret => |ret_val| {
                if (ret_val) |reg| callback(ctx, reg.id);
            },
            .cond_br => |br| {
                callback(ctx, br.cond.id);
            },
            .switch_ => |sw| {
                callback(ctx, sw.value.id);
            },
            .throw => |val| {
                callback(ctx, val.id);
            },
            .br, .unreachable_ => {},
        }
    }

    // === 寄存器使用收集（委托给 forEachOperandReg / forEachTerminatorReg） ===

    /// 遍历指令引用的所有寄存器（操作数 + PHI incoming），更新 max_reg_id
    /// 根本性修复：确保 max_reg_id 覆盖所有 bitSet 可能设置的寄存器 ID
    fn updateMaxRegIdFromInst(self: *Self, inst: IR.Instruction) void {
        forEachOperandReg(inst, self, Self.updateMaxRegCb, true);
    }

    /// 遍历终止指令引用的所有寄存器，更新 max_reg_id
    fn updateMaxRegIdFromTerminator(self: *Self, term: IR.Terminator) void {
        forEachTerminatorReg(term, self, Self.updateMaxRegCb);
    }

    /// 添加终止指令使用的寄存器
    fn addTerminatorUsedRegs(self: *const Self, set: []u64, term: IR.Terminator) void {
        _ = self;
        forEachTerminatorReg(term, set, Self.bitSetCb);
    }

    /// 添加指令使用的寄存器（完整覆盖所有含寄存器操作数的指令类型）
    fn addUsedRegs(self: *const Self, set: []u64, inst: IR.Instruction) void {
        _ = self;
        forEachOperandReg(inst, set, Self.bitSetCb, false);
    }
};
