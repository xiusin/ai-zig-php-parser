/// 字节码系统根模块
/// 提供高性能PHP字节码编译与执行
pub const instruction = @import("instruction.zig");
pub const generator = @import("generator.zig");
pub const vm = @import("vm.zig");

pub const Instruction = instruction.Instruction;
pub const OpCode = instruction.OpCode;
pub const CompiledFunction = instruction.CompiledFunction;
pub const BytecodeModule = instruction.BytecodeModule;
pub const Value = instruction.Value;

pub const BytecodeGenerator = generator.BytecodeGenerator;
pub const BytecodeVM = vm.BytecodeVM;

test {
    @import("std").testing.refAllDecls(@This());
}
