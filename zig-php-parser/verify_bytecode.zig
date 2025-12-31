const std = @import("std");
const bytecode = @import("src/bytecode/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== 字节码系统功能验证 ===", .{});

    // 1. 验证指令集
    std.log.info("1. 测试字节码指令集", .{});

    const inst1 = bytecode.Instruction.init(.push_const, 42, 0);
    const inst2 = bytecode.Instruction.withTypeHint(.add_int, 0, 0, .integer);

    std.log.info("   - 指令创建: opcode={}, operand1={}", .{ inst1.opcode, inst1.operand1 });
    std.log.info("   - 类型提示: {}", .{inst2.flags.type_hint});

    // 2. 验证字节码生成器
    std.log.info("2. 测试字节码生成器", .{});
    var generator = bytecode.BytecodeGenerator.init(allocator);
    defer generator.deinit();

    generator.reset();
    std.log.info("   - 生成器初始化成功", .{});

    // 3. 验证字节码虚拟机
    std.log.info("3. 测试字节码虚拟机", .{});
    var vm = try bytecode.BytecodeVM.init(allocator);
    defer vm.deinit();

    std.log.info("   - 虚拟机初始化成功", .{});

    // 4. 验证OpCode属性
    std.log.info("4. 测试OpCode属性", .{});
    std.log.info("   - JMP是跳转指令: {}", .{bytecode.OpCode.jmp.isJump()});
    std.log.info("   - CALL是调用指令: {}", .{bytecode.OpCode.call.isCall()});
    std.log.info("   - RET是终止指令: {}", .{bytecode.OpCode.ret.isTerminator()});
    std.log.info("   - NOP的操作数数量: {}", .{bytecode.OpCode.nop.operandCount()});

    // 5. 验证编译后的函数结构
    std.log.info("5. 测试编译函数结构", .{});
    const compiled_func = try bytecode.CompiledFunction.init(allocator, "test_function");
    defer _ = {};

    // 添加一些常量
    const const_idx1 = try generator.addConstant(.{ .int_val = 42 });
    const const_idx2 = try generator.addConstant(.{ .int_val = 58 });

    std.log.info("   - 添加常量索引: {}, {}", .{ const_idx1, const_idx2 });

    // 6. 验证字节码模块
    std.log.info("6. 测试字节码模块", .{});
    var module = bytecode.BytecodeModule.init(allocator, "test_module");
    defer module.deinit(allocator);

    try module.addFunction(compiled_func);
    const retrieved_func = module.getFunction("test_function");
    std.log.info("   - 函数存储和检索: {}", .{retrieved_func != null});

    std.log.info("=== 字节码系统验证完成 ===", .{});
}
