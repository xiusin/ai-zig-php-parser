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
        self.max_reg_id = 0;
        var total_insts: usize = 0;
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |reg| {
                    if (reg.id + 1 > self.max_reg_id) self.max_reg_id = reg.id + 1;
                }
            }
            // 终止指令操作数
            if (block.terminator) |term| {
                switch (term) {
                    .ret => |r| if (r) |reg| { if (reg.id + 1 > self.max_reg_id) self.max_reg_id = reg.id + 1; },
                    .cond_br => |br| { if (br.cond.id + 1 > self.max_reg_id) self.max_reg_id = br.cond.id + 1; },
                    .switch_ => |sw| { if (sw.value.id + 1 > self.max_reg_id) self.max_reg_id = sw.value.id + 1; },
                    .throw => |val| { if (val.id + 1 > self.max_reg_id) self.max_reg_id = val.id + 1; },
                    .br, .unreachable_ => {},
                }
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
        const inst_live = self.getInstLiveOut(block_idx, inst_idx);
        if (inst_live.len == 0) return false;
        return bitIsSet(inst_live, reg_id);
    }

    /// 判断寄存器在块出口是否活跃（双重保护：防止 inst_live_out bug 导致误释放）
    pub fn isLiveAtBlockExit(self: *const Self, block_idx: usize, reg_id: usize) bool {
        if (self.live_out_storage == null) return false;
        if (block_idx >= self.num_blocks) return false;
        const start = block_idx * self.words_per_set;
        const block_live_out = self.live_out_storage.?[start .. start + self.words_per_set];
        return bitIsSet(block_live_out, reg_id);
    }

    // === 寄存器使用收集 ===

    /// 添加终止指令使用的寄存器
    fn addTerminatorUsedRegs(self: *const Self, set: []u64, term: IR.Terminator) void {
        _ = self;
        switch (term) {
            .ret => |ret_val| {
                if (ret_val) |reg| bitSet(set, reg.id);
            },
            .cond_br => |br| {
                bitSet(set, br.cond.id);
            },
            .switch_ => |sw| {
                bitSet(set, sw.value.id);
            },
            .throw => |val| {
                bitSet(set, val.id);
            },
            .br, .unreachable_ => {},
        }
    }

    /// 添加指令使用的寄存器（完整覆盖所有含寄存器操作数的指令类型）
    fn addUsedRegs(self: *const Self, set: []u64, inst: IR.Instruction) void {
        _ = self;
        switch (inst.op) {
            // === BinaryOp (lhs, rhs) ===
            .add, .sub, .mul, .div, .mod, .pow, .concat, .eq, .ne, .lt, .le, .gt, .ge,
            .bit_and, .bit_or, .bit_xor, .shl, .shr,
            .identical, .not_identical, .spaceship, .and_, .or_ => |bin| {
                bitSet(set, bin.lhs.id);
                bitSet(set, bin.rhs.id);
            },
            // === UnaryOp (operand) ===
            .neg, .not, .bit_not, .move, .get_type, .clone, .retain, .release,
            .unset_var, .strlen, .array_count, .channel_close, .await_, .debug_print, .yield_from => |un| {
                bitSet(set, un.operand.id);
            },
            // === CastOp (value) ===
            .cast => |op| bitSet(set, op.value.id),
            // === TypeCheckOp (value) ===
            .type_check => |op| bitSet(set, op.value.id),
            // === CallOp (args) ===
            .call => |call| {
                for (call.args) |arg| bitSet(set, arg.id);
            },
            // === CallIndirectOp (func_ptr, args) ===
            .call_indirect => |call| {
                bitSet(set, call.func_ptr.id);
                for (call.args) |arg| bitSet(set, arg.id);
            },
            // === LoadOp (ptr) ===
            .load => |op| bitSet(set, op.ptr.id),
            // === StoreOp (ptr, value) ===
            .store => |op| {
                bitSet(set, op.ptr.id);
                bitSet(set, op.value.id);
            },
            // === MakeRefOp (ptr) ===
            .make_ref => |op| bitSet(set, op.ptr.id),
            // === global_set (value) ===
            .global_set => |op| {
                if (op.value) |val| bitSet(set, val.id);
            },
            // === global_unset (name) ===
            .global_unset => |op| bitSet(set, op.name.id),
            // === global_get_dynamic (name_reg) ===
            .global_get_dynamic => |op| bitSet(set, op.name_reg.id),
            // === global_set_dynamic (name_reg, value) ===
            .global_set_dynamic => |op| {
                bitSet(set, op.name_reg.id);
                bitSet(set, op.value.id);
            },
            // === ArrayGetOp (array, key) — array_get, array_ensure ===
            .array_get, .array_ensure => |op| {
                bitSet(set, op.array.id);
                bitSet(set, op.key.id);
            },
            // === ArraySetOp (array, key, value) ===
            .array_set => |op| {
                bitSet(set, op.array.id);
                bitSet(set, op.key.id);
                bitSet(set, op.value.id);
            },
            // === ArraySetNestedOp ===
            .array_set_nested => |op| {
                bitSet(set, op.outer_array.id);
                bitSet(set, op.outer_key.id);
                bitSet(set, op.inner_key.id);
                bitSet(set, op.value.id);
            },
            // === ArrayPushOp (array, value) ===
            .array_push => |op| {
                bitSet(set, op.array.id);
                bitSet(set, op.value.id);
            },
            // === ArrayKeyExistsOp (array, key) ===
            .array_key_exists => |op| {
                bitSet(set, op.array.id);
                bitSet(set, op.key.id);
            },
            // === ArrayUnsetOp (array, key) ===
            .array_unset => |op| {
                bitSet(set, op.array.id);
                bitSet(set, op.key.id);
            },
            // === InterpolateOp (parts) ===
            .interpolate => |op| {
                for (op.parts) |part| bitSet(set, part.id);
            },
            // === NewObjectOp (args) ===
            .new_object => |op| {
                for (op.args) |arg| bitSet(set, arg.id);
            },
            // === PropertyGetOp (object) ===
            .property_get => |op| bitSet(set, op.object.id),
            // === PropertySetOp (object, value) ===
            .property_set => |op| {
                bitSet(set, op.object.id);
                bitSet(set, op.value.id);
            },
            // === MethodCallOp (object, args) ===
            .method_call => |op| {
                bitSet(set, op.object.id);
                for (op.args) |arg| bitSet(set, arg.id);
            },
            // === StaticMethodCallOp (args) ===
            .static_method_call => |op| {
                for (op.args) |arg| bitSet(set, arg.id);
            },
            // === StaticPropertySetOp (value) ===
            .static_property_set => |op| bitSet(set, op.value.id),
            // === ClosureNewOp (func_ptr, captures) ===
            .closure_new => |op| {
                bitSet(set, op.func_ptr.id);
                for (op.captures) |cap| bitSet(set, cap.id);
            },
            // === ClosureBindOp (closure, object) ===
            .closure_bind => |op| {
                bitSet(set, op.closure.id);
                bitSet(set, op.object.id);
            },
            // === ImplementsInterfaceOp (object) ===
            .implements_interface => |op| bitSet(set, op.object.id),
            // === ParentCallOp (object, args) ===
            .parent_call => |op| {
                bitSet(set, op.object.id);
                for (op.args) |arg| bitSet(set, arg.id);
            },
            // === BoxOp / UnboxOp (value) ===
            .box => |op| bitSet(set, op.value.id),
            .unbox => |op| bitSet(set, op.value.id),
            // === InstanceOfOp (object, class_name) ===
            .instanceof => |op| {
                bitSet(set, op.object.id);
                bitSet(set, op.class_name.id);
            },
            // === PhiOp ===
            // PHI incoming values are NOT used in the PHI block itself.
            // They are "used" at the end of the corresponding predecessor block.
            // This is handled in computeLiveOut (standard SSA liveness semantics).
            .phi => {},
            // === SelectOp (cond, then_value, else_value) ===
            .select => |op| {
                bitSet(set, op.cond.id);
                bitSet(set, op.then_value.id);
                bitSet(set, op.else_value.id);
            },
            // === GoSpawnOp (args) ===
            .go_spawn => |op| {
                for (op.args) |arg| bitSet(set, arg.id);
            },
            // === ChannelSendOp (channel, value) ===
            .channel_send => |op| {
                bitSet(set, op.channel.id);
                bitSet(set, op.value.id);
            },
            // === ChannelRecvOp (channel) ===
            .channel_recv => |op| bitSet(set, op.channel.id),
            // === SelectChannelOp (cases) ===
            .select_ => |op| {
                for (op.cases) |case| {
                    bitSet(set, case.channel.id);
                    if (case.value) |val| bitSet(set, val.id);
                }
            },
            // === YieldOp (key, value) ===
            .yield_val => |op| {
                if (op.key) |key| bitSet(set, key.id);
                if (op.value) |val| bitSet(set, val.id);
            },
            // === Instructions with no register operands ===
            else => {},
        }
    }
};
