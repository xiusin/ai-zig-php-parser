const std = @import("std");
const IR = @import("ir.zig");

/// 活跃性分析：计算每个程序点的活跃变量集合
pub const LivenessAnalysis = struct {
    allocator: std.mem.Allocator,
    
    /// 每个基本块的活跃信息
    live_in: std.AutoHashMap(usize, RegSet),   // 块入口活跃变量
    live_out: std.AutoHashMap(usize, RegSet),  // 块出口活跃变量
    
    /// 每条指令后的活跃变量
    inst_live_out: std.AutoHashMap(InstId, RegSet),
    
    const Self = @This();
    const RegSet = std.AutoHashMap(usize, void);
    const InstId = struct { block: usize, inst: usize };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .live_in = std.AutoHashMap(usize, RegSet).init(allocator),
            .live_out = std.AutoHashMap(usize, RegSet).init(allocator),
            .inst_live_out = std.AutoHashMap(InstId, RegSet).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var live_in_iter = self.live_in.valueIterator();
        while (live_in_iter.next()) |set| set.deinit();
        self.live_in.deinit();
        
        var live_out_iter = self.live_out.valueIterator();
        while (live_out_iter.next()) |set| set.deinit();
        self.live_out.deinit();
        
        var inst_iter = self.inst_live_out.valueIterator();
        while (inst_iter.next()) |set| set.deinit();
        self.inst_live_out.deinit();
    }
    
    /// 分析函数的活跃性
    pub fn analyze(self: *Self, func: *const IR.Function) !void {
        // 初始化每个块的活跃集合
        for (func.blocks.items, 0..) |_, block_idx| {
            try self.live_in.put(block_idx, RegSet.init(self.allocator));
            try self.live_out.put(block_idx, RegSet.init(self.allocator));
        }
        
        // 反向数据流分析，迭代直到不动点
        var changed = true;
        var iterations: usize = 0;
        while (changed) : (iterations += 1) {
            changed = false;
            
            // 反向遍历基本块
            var block_idx: usize = func.blocks.items.len;
            while (block_idx > 0) {
                block_idx -= 1;
                // live_out[B] = ∪ live_in[S] for S in successors(B)
                var new_live_out = RegSet.init(self.allocator);
                errdefer new_live_out.deinit();
                
                try self.computeLiveOut(func, block_idx, &new_live_out);
                
                // live_in[B] = use[B] ∪ (live_out[B] - def[B])
                var new_live_in = RegSet.init(self.allocator);
                errdefer new_live_in.deinit();
                
                try self.computeLiveIn(func, block_idx, &new_live_out, &new_live_in);
                
                // 检查是否改变
                const old_live_in = self.live_in.getPtr(block_idx).?;
                const old_live_out = self.live_out.getPtr(block_idx).?;
                
                if (!self.setsEqual(old_live_in, &new_live_in) or 
                    !self.setsEqual(old_live_out, &new_live_out)) {
                    changed = true;
                    
                    old_live_in.deinit();
                    old_live_out.deinit();
                    
                    try self.live_in.put(block_idx, new_live_in);
                    try self.live_out.put(block_idx, new_live_out);
                } else {
                    new_live_in.deinit();
                    new_live_out.deinit();
                }
            }
            
            if (iterations > 100) {
                std.debug.print("WARNING: Liveness analysis did not converge after 100 iterations\n", .{});
                break;
            }
        }
        
        // 计算每条指令后的活跃变量
        try self.computeInstLiveness(func);
    }
    
    /// 计算块出口的活跃变量
    fn computeLiveOut(self: *Self, func: *const IR.Function, block_idx: usize, out: *RegSet) !void {
        const block = func.blocks.items[block_idx];
        
        // 获取后继块索引
        var successors = try std.ArrayList(usize).initCapacity(self.allocator, 0);
        defer successors.deinit(self.allocator);
        
        if (block.terminator) |term| {
            switch (term) {
                .br => |target| {
                    try successors.append(self.allocator, target.index);
                },
                .cond_br => |br| {
                    try successors.append(self.allocator, br.then_block.index);
                    try successors.append(self.allocator, br.else_block.index);
                },
                .ret, .unreachable_, .throw => {},
                .switch_ => |sw| {
                    for (sw.cases) |case| {
                        try successors.append(self.allocator, case.block.index);
                    }
                    try successors.append(self.allocator, sw.default.index);
                },
            }
        } else if (block_idx + 1 < func.blocks.items.len) {
            try successors.append(self.allocator, block_idx + 1);
        }
        
        // 合并后继块的live_in
        for (successors.items) |succ_idx| {
            const succ_live_in = self.live_in.get(succ_idx) orelse continue;
            try self.unionSets(out, &succ_live_in);
        }
    }
    
    /// 计算块入口的活跃变量
    fn computeLiveIn(self: *Self, func: *const IR.Function, block_idx: usize, live_out: *const RegSet, live_in: *RegSet) !void {
        const block = func.blocks.items[block_idx];
        
        // live_in = use ∪ (live_out - def)
        var current = RegSet.init(self.allocator);
        defer current.deinit();
        
        try self.copySets(&current, live_out);
        
        // 反向遍历指令
        var inst_idx: usize = block.instructions.items.len;
        while (inst_idx > 0) {
            inst_idx -= 1;
            const inst = block.instructions.items[inst_idx].*;
            
            // 移除定义的寄存器
            if (inst.result) |reg| {
                _ = current.remove(reg.id);
            }
            
            // 添加使用的寄存器
            try self.addUsedRegs(&current, inst);
        }
        
        try self.copySets(live_in, &current);
    }
    
    /// 计算每条指令后的活跃变量
    fn computeInstLiveness(self: *Self, func: *const IR.Function) !void {
        for (func.blocks.items, 0..) |block, block_idx| {
            const block_live_out = self.live_out.get(block_idx) orelse continue;
            
            var current = RegSet.init(self.allocator);
            try self.copySets(&current, &block_live_out);
            
            // 反向遍历指令
            var inst_idx: usize = block.instructions.items.len;
            while (inst_idx > 0) {
                inst_idx -= 1;
                const inst = block.instructions.items[inst_idx].*;
                
                // 保存当前活跃集合
                var inst_live = RegSet.init(self.allocator);
                try self.copySets(&inst_live, &current);
                try self.inst_live_out.put(.{ .block = block_idx, .inst = inst_idx }, inst_live);
                
                // 更新活跃集合
                if (inst.result) |reg| {
                    _ = current.remove(reg.id);
                }
                try self.addUsedRegs(&current, inst);
            }
            
            current.deinit();
        }
    }
    
    /// 添加指令使用的寄存器
    fn addUsedRegs(_: *Self, set: *RegSet, inst: IR.Instruction) !void {
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod, .pow, .concat,
            .eq, .ne, .lt, .le, .gt, .ge,
            .bit_and, .bit_or, .bit_xor, .shl, .shr => |bin| {
                try set.put(bin.lhs.id, {});
                try set.put(bin.rhs.id, {});
            },
            .neg, .not, .bit_not => |un| {
                try set.put(un.operand.id, {});
            },
            .cast => |op| {
                try set.put(op.value.id, {});
            },
            .release => |op| {
                try set.put(op.operand.id, {});
            },
            .call => |call| {
                for (call.args) |arg| {
                    try set.put(arg.id, {});
                }
            },
            .call_indirect => |call| {
                try set.put(call.func_ptr.id, {});
                for (call.args) |arg| {
                    try set.put(arg.id, {});
                }
            },
            .load => |op| {
                try set.put(op.ptr.id, {});
            },
            .store => |op| {
                try set.put(op.ptr.id, {});
                try set.put(op.value.id, {});
            },
            .array_get => |op| {
                try set.put(op.array.id, {});
                try set.put(op.key.id, {});
            },
            .array_set => |op| {
                try set.put(op.array.id, {});
                try set.put(op.key.id, {});
                try set.put(op.value.id, {});
            },
            .property_get => |op| {
                try set.put(op.object.id, {});
            },
            .property_set => |op| {
                try set.put(op.object.id, {});
                try set.put(op.value.id, {});
            },
            .phi => |phi| {
                for (phi.incoming) |inc| {
                    try set.put(inc.value.id, {});
                }
            },
            else => {},
        }
    }
    
    /// 判断寄存器在指令后是否活跃
    pub fn isLiveAfter(self: *const Self, block_idx: usize, inst_idx: usize, reg_id: usize) bool {
        const inst_id = InstId{ .block = block_idx, .inst = inst_idx };
        const live_set = self.inst_live_out.get(inst_id) orelse return false;
        return live_set.contains(reg_id);
    }
    
    /// 集合操作辅助函数
    fn unionSets(self: *Self, dest: *RegSet, src: *const RegSet) !void {
        _ = self;
        var iter = src.keyIterator();
        while (iter.next()) |key| {
            try dest.put(key.*, {});
        }
    }
    
    fn copySets(self: *Self, dest: *RegSet, src: *const RegSet) !void {
        _ = self;
        dest.clearRetainingCapacity();
        var iter = src.keyIterator();
        while (iter.next()) |key| {
            try dest.put(key.*, {});
        }
    }
    
    fn setsEqual(self: *Self, a: *const RegSet, b: *const RegSet) bool {
        _ = self;
        if (a.count() != b.count()) return false;
        var iter = a.keyIterator();
        while (iter.next()) |key| {
            if (!b.contains(key.*)) return false;
        }
        return true;
    }
};
