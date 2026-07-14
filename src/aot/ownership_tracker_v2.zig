const std = @import("std");
const IR = @import("ir.zig");

/// 所有权状态
pub const OwnershipState = enum {
    /// 未初始化
    uninitialized,
    /// 持有所有权（需要cleanup）
    owned,
    /// 已转移所有权（不需要cleanup）
    transferred,
    /// 已消费（不需要cleanup）
    consumed,
};

/// 所有权追踪器
pub const OwnershipTracker = struct {
    allocator: std.mem.Allocator,
    /// 每个寄存器的所有权状态
    ownership_state: std.AutoHashMap(usize, OwnershipState),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .ownership_state = std.AutoHashMap(usize, OwnershipState).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.ownership_state.deinit();
    }

    /// 分析函数的所有权
    pub fn analyze(self: *Self, func: *const IR.Function) !void {
        // 初始化所有寄存器为uninitialized
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |reg| {
                    try self.ownership_state.put(reg.id, .uninitialized);
                }
            }
        }

        // 分析每条指令
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                try self.analyzeInstruction(inst.*);
            }
        }
    }

    /// 分析单条指令
    fn analyzeInstruction(self: *Self, inst: IR.Instruction) !void {
        // 1. 处理result寄存器
        if (inst.result) |reg| {
            const state = self.getOwnershipFromOp(inst.op);
            try self.ownership_state.put(reg.id, state);
        }

        // 2. 处理操作数（检查是否被消费）
        try self.checkOperandConsumption(inst.op);
    }

    /// 从指令操作获取所有权状态
    fn getOwnershipFromOp(self: *Self, op: anytype) OwnershipState {
        _ = self;
        return switch (op) {
            // 创建新值 → owned
            .const_string, .concat, .array_new, .new_object => .owned,

            // 借用值（有retain）→ owned
            .global_get, .array_get, .property_get => .owned,

            // 函数调用 → owned（保守）
            .call => .owned,

            // 不创建所有权 → uninitialized
            .const_int, .const_float, .const_bool, .const_null => .uninitialized,
            .add, .sub, .mul, .div, .mod => .uninitialized,
            .eq, .ne, .lt, .le, .gt, .ge => .uninitialized,
            .neg, .not => .uninitialized,

            // alloca → owned（需要cleanup）
            .alloca => .owned,

            // load → uninitialized（只是读取）
            .load => .uninitialized,

            else => .uninitialized,
        };
    }

    /// 检查操作数是否被消费
    fn checkOperandConsumption(self: *Self, op: anytype) !void {
        switch (op) {
            // 目前没有真正消费操作数的指令
            // global_set, array_set 都会retain，不消费
            else => {},
        }
        _ = self;
    }

    /// 寄存器是否需要cleanup
    pub fn needsCleanup(self: *const Self, reg_id: usize) bool {
        const state = self.ownership_state.get(reg_id) orelse .uninitialized;
        return state == .owned;
    }

    /// 获取寄存器的所有权状态（调试用）
    pub fn getState(self: *const Self, reg_id: usize) OwnershipState {
        return self.ownership_state.get(reg_id) orelse .uninitialized;
    }
};
