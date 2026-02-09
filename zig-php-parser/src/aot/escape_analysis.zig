//! 逃逸分析 - 将不逃逸的对象分配到栈上
//!
//! 核心思路：
//! 1. 分析对象的生命周期
//! 2. 如果对象不逃逸出函数，分配到栈上
//! 3. 减少堆分配和GC压力

const std = @import("std");
const IR = @import("ir.zig");
const Module = IR.Module;
const Function = IR.Function;
const Instruction = IR.Instruction;
const Register = IR.Register;

pub const EscapeAnalyzer = struct {
    allocator: std.mem.Allocator,
    /// 逃逸的寄存器集合
    escaped: std.AutoHashMapUnmanaged(u32, void),
    
    pub fn init(allocator: std.mem.Allocator) EscapeAnalyzer {
        return .{
            .allocator = allocator,
            .escaped = .{},
        };
    }
    
    pub fn deinit(self: *EscapeAnalyzer) void {
        self.escaped.deinit(self.allocator);
    }
    
    /// 分析函数中的逃逸情况
    pub fn analyze(self: *EscapeAnalyzer, func: *Function) !void {
        self.escaped.clearRetainingCapacity();
        
        // 遍历所有指令，标记逃逸的寄存器
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                try self.analyzeInstruction(inst);
            }
        }
    }
    
    fn analyzeInstruction(self: *EscapeAnalyzer, inst: *Instruction) !void {
        switch (inst.op) {
            // 返回值逃逸
            .ret => |ret_op| {
                if (ret_op.value) |val| {
                    try self.markEscaped(val);
                }
            },
            // 存储到全局/静态属性逃逸
            .static_property_set => |op| {
                try self.markEscaped(op.value);
            },
            // 函数调用参数逃逸
            .call => |call_op| {
                for (call_op.args) |arg| {
                    try self.markEscaped(arg);
                }
            },
            // 数组元素可能逃逸
            .array_set => |op| {
                try self.markEscaped(op.value);
            },
            else => {},
        }
    }
    
    fn markEscaped(self: *EscapeAnalyzer, reg: Register) !void {
        try self.escaped.put(self.allocator, reg.id, {});
    }
    
    /// 检查寄存器是否逃逸
    pub fn isEscaped(self: *const EscapeAnalyzer, reg: Register) bool {
        return self.escaped.contains(reg.id);
    }
};
