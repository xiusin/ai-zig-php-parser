// Bytecode 模块统一入口
// 用于解决 Zig 0.15.2 模块系统的导入问题

pub const vm = @import("vm.zig");
pub const generator = @import("generator.zig");
pub const instruction = @import("instruction.zig");
pub const optimizer = @import("optimizer.zig");

// 导出常用类型
pub const BytecodeVM = vm.BytecodeVM;
pub const BytecodeGenerator = generator.BytecodeGenerator;
pub const Value = vm.Value;
pub const Instruction = instruction.Instruction;
pub const OpCode = instruction.OpCode;
