// JIT 模块的跨目录导入桥接文件
// 用于解决 Zig 0.15.2 不推荐使用 `../` 的问题

// 运行时模块
const runtime = @import("runtime");
pub const func = runtime.func;
pub const opcode = runtime.opcode;
pub const stack_trace = runtime.stack_trace;

// 类型别名
pub const CompiledFunc = func.CompiledFunc;
pub const OpCode = opcode.OpCode;
