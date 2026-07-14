//! 类型特化优化 - 为已知类型生成特化代码
//!
//! 核心思路：
//! 1. 类型推断确定变量类型
//! 2. 为纯整数/浮点操作生成特化代码
//! 3. 消除 Value 装箱/拆箱开销

const std = @import("std");
const IR = @import("ir.zig");
const Module = IR.Module;
const Function = IR.Function;
const Instruction = IR.Instruction;
const Register = IR.Register;
const Type = IR.Type;

pub const TypeSpecializer = struct {
    allocator: std.mem.Allocator,
    /// 寄存器的具体类型
    concrete_types: std.AutoHashMapUnmanaged(u32, ConcreteType),

    pub const ConcreteType = enum {
        int, // 纯整数
        float, // 纯浮点
        bool, // 纯布尔
        string, // 纯字符串
        mixed, // 混合类型
    };

    pub fn init(allocator: std.mem.Allocator) TypeSpecializer {
        return .{
            .allocator = allocator,
            .concrete_types = .{},
        };
    }

    pub fn deinit(self: *TypeSpecializer) void {
        self.concrete_types.deinit(self.allocator);
    }

    /// 分析并特化函数
    pub fn specialize(self: *TypeSpecializer, func: *Function) !bool {
        var changed = false;

        // 1. 类型推断
        try self.inferTypes(func);

        // 2. 生成特化指令
        for (func.blocks.items) |block| {
            var i: usize = 0;
            while (i < block.instructions.items.len) {
                const inst = block.instructions.items[i];
                if (try self.specializeInstruction(inst, block, i)) {
                    changed = true;
                }
                i += 1;
            }
        }

        return changed;
    }

    fn inferTypes(self: *TypeSpecializer, func: *Function) !void {
        self.concrete_types.clearRetainingCapacity();

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |result| {
                    const concrete_type = self.inferInstructionType(inst);
                    try self.concrete_types.put(self.allocator, result.id, concrete_type);
                }
            }
        }
    }

    fn inferInstructionType(self: *const TypeSpecializer, inst: *Instruction) ConcreteType {
        return switch (inst.op) {
            .const_int => .int,
            .const_float => .float,
            .const_bool => .bool,
            .const_string => .string,
            .add, .sub, .mul, .div, .mod => |bin_op| blk: {
                const lhs_type = self.concrete_types.get(bin_op.lhs.id) orelse .mixed;
                const rhs_type = self.concrete_types.get(bin_op.rhs.id) orelse .mixed;
                if (lhs_type == .int and rhs_type == .int) break :blk .int;
                if (lhs_type == .float or rhs_type == .float) break :blk .float;
                break :blk .mixed;
            },
            else => .mixed,
        };
    }

    fn specializeInstruction(
        self: *TypeSpecializer,
        inst: *Instruction,
        block: *IR.BasicBlock,
        index: usize,
    ) !bool {
        _ = self;
        _ = inst;
        _ = block;
        _ = index;

        // 特化逻辑将在 native_linker 中实现
        // 这里只做类型分析
        return false;
    }
};
