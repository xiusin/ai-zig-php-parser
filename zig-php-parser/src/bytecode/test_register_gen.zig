//! 测试寄存器字节码生成器

const std = @import("std");

// 由于 Zig 测试限制，我们在这里手动导入依赖
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;

// 注意：实际使用时需要通过 build.zig 配置模块路径
// 这里仅作为概念验证

test "register bytecode generation concept" {
    // 验证新的寄存器指令已添加到 OpCode
    try std.testing.expect(@intFromEnum(OpCode.load_reg) == 0xE4);
    try std.testing.expect(@intFromEnum(OpCode.store_reg) == 0xE5);
    try std.testing.expect(@intFromEnum(OpCode.add_reg) == 0xE7);
    try std.testing.expect(@intFromEnum(OpCode.clear_regs) == 0xEE);
    
    // 验证指令创建
    const load_inst = Instruction.init(.load_reg, 0, 1);
    try std.testing.expect(load_inst.opcode == .load_reg);
    try std.testing.expect(load_inst.operand1 == 0);
    try std.testing.expect(load_inst.operand2 == 1);
    
    const add_inst = Instruction.init(.add_reg, 0, 1);
    try std.testing.expect(add_inst.opcode == .add_reg);
}

test "register instruction operand counts" {
    // 验证寄存器指令的操作数数量
    try std.testing.expect(OpCode.load_reg.operandCount() == 2);
    try std.testing.expect(OpCode.store_reg.operandCount() == 2);
    try std.testing.expect(OpCode.add_reg.operandCount() == 2);
    try std.testing.expect(OpCode.clear_regs.operandCount() == 0);
}
