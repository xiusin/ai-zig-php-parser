const std = @import("std");
const IR = @import("ir.zig");

/// 所有权追踪器
pub const OwnershipTracker = struct {
    allocator: std.mem.Allocator,
    /// 寄存器是否需要cleanup（持有所有权）
    needs_cleanup: std.AutoHashMap(usize, bool),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .needs_cleanup = std.AutoHashMap(usize, bool).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.needs_cleanup.deinit();
    }

    /// 分析函数的所有权
    pub fn analyze(self: *Self, func: *const IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                try self.analyzeInstruction(inst.*);
            }
        }
    }

    /// 分析单条指令
    fn analyzeInstruction(self: *Self, inst: IR.Instruction) !void {
        if (inst.result) |reg| {
            const needs = self.instructionCreatesOwnership(inst.op);
            try self.needs_cleanup.put(reg.id, needs);
        }

        // 检查是否有所有权转移
        self.checkOwnershipTransfer(inst.op);
    }

    /// 指令是否创建所有权
    fn instructionCreatesOwnership(_: *Self, op: anytype) bool {
        return switch (op) {
            // 创建新值
            .const_string, .concat, .array_new, .new_object => true,
            // 借用值（有retain，获得所有权）
            .global_get, .array_get, .property_get => true,
            // 函数调用（保守：假设返回新值）
            .call => true,
            // 不创建所有权
            .const_int, .const_float, .const_bool, .const_null => false,
            .add, .sub, .mul, .div, .mod => false,
            .eq, .ne, .lt, .le, .gt, .ge => false,
            .neg, .not => false,
            .alloca, .load, .store => false,
            else => false,
        };
    }

    /// 检查所有权转移
    fn checkOwnershipTransfer(_: *Self, op: anytype) void {
        switch (op) {
            .global_set => {},
            .array_set => {},
            else => {},
        }
    }

    /// 寄存器是否需要cleanup
    pub fn needsCleanup(self: *const Self, reg_id: usize) bool {
        return self.needs_cleanup.get(reg_id) orelse false;
    }
};
