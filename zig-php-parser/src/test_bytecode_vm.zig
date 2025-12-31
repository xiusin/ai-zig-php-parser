/// 字节码VM单元测试
/// 测试每条指令的正确性和边界条件
const std = @import("std");
const testing = std.testing;

// 导入字节码模块
const instruction = @import("bytecode/instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;
const CompiledFunction = instruction.CompiledFunction;
const ConstValue = instruction.Value;

const vm_module = @import("bytecode/vm.zig");
const BytecodeVM = vm_module.BytecodeVM;
const Value = vm_module.Value;

// ============================================================================
// 辅助函数
// ============================================================================

/// 创建测试用的编译函数
fn createTestFunction(allocator: std.mem.Allocator, bytecode: []const Instruction, constants: []const ConstValue) !*CompiledFunction {
    const func = try allocator.create(CompiledFunction);
    func.* = CompiledFunction{
        .name = "test_func",
        .bytecode = try allocator.dupe(Instruction, bytecode),
        .constants = try allocator.dupe(ConstValue, constants),
        .local_count = 10,
        .arg_count = 0,
        .max_stack = 16,
        .flags = .{},
        .line_table = &[_]CompiledFunction.LineInfo{},
        .exception_table = &[_]CompiledFunction.ExceptionEntry{},
    };
    return func;
}

/// 清理测试函数
fn destroyTestFunction(allocator: std.mem.Allocator, func: *CompiledFunction) void {
    allocator.free(func.bytecode);
    allocator.free(func.constants);
    allocator.destroy(func);
}

// ============================================================================
// 栈操作测试
// ============================================================================

test "bytecode vm - push_null instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_null, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test", func);
    const result = try vm.call("test", &[_]Value{});
    
    try testing.expectEqual(Value.null_val, result);
}

test "bytecode vm - push_true and push_false instructions" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // Test push_true
    const bytecode_true = [_]Instruction{
        Instruction.init(.push_true, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func_true = try createTestFunction(allocator, &bytecode_true, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func_true);
    
    try vm.registerFunction("test_true", func_true);
    const result_true = try vm.call("test_true", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = true }, result_true);
    
    // Test push_false
    const bytecode_false = [_]Instruction{
        Instruction.init(.push_false, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func_false = try createTestFunction(allocator, &bytecode_false, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func_false);
    
    try vm.registerFunction("test_false", func_false);
    const result_false = try vm.call("test_false", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = false }, result_false);
}


test "bytecode vm - push_int_0 and push_int_1 instructions" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // Test push_int_0
    const bytecode_0 = [_]Instruction{
        Instruction.init(.push_int_0, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func_0 = try createTestFunction(allocator, &bytecode_0, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func_0);
    
    try vm.registerFunction("test_0", func_0);
    const result_0 = try vm.call("test_0", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 0 }, result_0);
    
    // Test push_int_1
    const bytecode_1 = [_]Instruction{
        Instruction.init(.push_int_1, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func_1 = try createTestFunction(allocator, &bytecode_1, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func_1);
    
    try vm.registerFunction("test_1", func_1);
    const result_1 = try vm.call("test_1", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 1 }, result_1);
}

// ============================================================================
// 整数算术测试
// ============================================================================

test "bytecode vm - add_int instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // 5 + 3 = 8
    const constants = [_]ConstValue{
        .{ .int_val = 5 },
        .{ .int_val = 3 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0), // push 5
        Instruction.init(.push_const, 1, 0), // push 3
        Instruction.init(.add_int, 0, 0),    // add
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_add", func);
    const result = try vm.call("test_add", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 8 }, result);
}

test "bytecode vm - sub_int instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // 10 - 4 = 6
    const constants = [_]ConstValue{
        .{ .int_val = 10 },
        .{ .int_val = 4 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0),
        Instruction.init(.push_const, 1, 0),
        Instruction.init(.sub_int, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_sub", func);
    const result = try vm.call("test_sub", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 6 }, result);
}

test "bytecode vm - mul_int instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // 7 * 6 = 42
    const constants = [_]ConstValue{
        .{ .int_val = 7 },
        .{ .int_val = 6 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0),
        Instruction.init(.push_const, 1, 0),
        Instruction.init(.mul_int, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_mul", func);
    const result = try vm.call("test_mul", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 42 }, result);
}

test "bytecode vm - div_int instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // 20 / 4 = 5
    const constants = [_]ConstValue{
        .{ .int_val = 20 },
        .{ .int_val = 4 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0),
        Instruction.init(.push_const, 1, 0),
        Instruction.init(.div_int, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_div", func);
    const result = try vm.call("test_div", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 5 }, result);
}

// ============================================================================
// 比较操作测试
// ============================================================================


test "bytecode vm - eq instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // 5 == 5 -> true
    const constants = [_]ConstValue{
        .{ .int_val = 5 },
        .{ .int_val = 5 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0),
        Instruction.init(.push_const, 1, 0),
        Instruction.init(.eq, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_eq", func);
    const result = try vm.call("test_eq", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = true }, result);
}

test "bytecode vm - lt_int instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // 3 < 5 -> true
    const constants = [_]ConstValue{
        .{ .int_val = 3 },
        .{ .int_val = 5 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0),
        Instruction.init(.push_const, 1, 0),
        Instruction.init(.lt_int, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_lt", func);
    const result = try vm.call("test_lt", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = true }, result);
}


// ============================================================================
// 控制流测试
// ============================================================================

test "bytecode vm - jmp instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // Jump over push_int_0, return 1
    const bytecode = [_]Instruction{
        Instruction.init(.jmp, 2, 0),        // jump to index 2
        Instruction.init(.push_int_0, 0, 0), // skipped
        Instruction.init(.push_int_1, 0, 0), // target
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_jmp", func);
    const result = try vm.call("test_jmp", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 1 }, result);
}

test "bytecode vm - jz instruction (jump when zero)" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // if (false) skip, return 1
    const bytecode = [_]Instruction{
        Instruction.init(.push_false, 0, 0), // push false (0)
        Instruction.init(.jz, 3, 0),         // jump to index 3 if zero
        Instruction.init(.push_int_0, 0, 0), // skipped
        Instruction.init(.push_int_1, 0, 0), // target
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_jz", func);
    const result = try vm.call("test_jz", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 1 }, result);
}

// ============================================================================
// 逻辑操作测试
// ============================================================================


test "bytecode vm - logic_and instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // true && true -> true
    const bytecode = [_]Instruction{
        Instruction.init(.push_true, 0, 0),
        Instruction.init(.push_true, 0, 0),
        Instruction.init(.logic_and, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_and", func);
    const result = try vm.call("test_and", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = true }, result);
}

test "bytecode vm - logic_or instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // false || true -> true
    const bytecode = [_]Instruction{
        Instruction.init(.push_false, 0, 0),
        Instruction.init(.push_true, 0, 0),
        Instruction.init(.logic_or, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_or", func);
    const result = try vm.call("test_or", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = true }, result);
}

test "bytecode vm - logic_not instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // !true -> false
    const bytecode = [_]Instruction{
        Instruction.init(.push_true, 0, 0),
        Instruction.init(.logic_not, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_not", func);
    const result = try vm.call("test_not", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = false }, result);
}

// ============================================================================
// 类型转换测试
// ============================================================================

test "bytecode vm - to_int instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // (int)3.14 -> 3
    const constants = [_]ConstValue{
        .{ .float_val = 3.14 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0),
        Instruction.init(.to_int, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_to_int", func);
    const result = try vm.call("test_to_int", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 3 }, result);
}

// ============================================================================
// 类型检查测试
// ============================================================================

test "bytecode vm - is_null instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // is_null(null) -> true
    const bytecode = [_]Instruction{
        Instruction.init(.push_null, 0, 0),
        Instruction.init(.is_null, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &[_]ConstValue{});
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_is_null", func);
    const result = try vm.call("test_is_null", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = true }, result);
}

test "bytecode vm - is_int instruction" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // is_int(42) -> true
    const constants = [_]ConstValue{
        .{ .int_val = 42 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0),
        Instruction.init(.is_int, 0, 0),
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_is_int", func);
    const result = try vm.call("test_is_int", &[_]Value{});
    
    try testing.expectEqual(Value{ .bool_val = true }, result);
}

// ============================================================================
// Value类型方法测试
// ============================================================================

test "Value.toBool - various types" {
    // null -> false
    const null_val: Value = .null_val;
    try testing.expectEqual(false, null_val.toBool());
    
    // bool -> same value
    try testing.expectEqual(true, (Value{ .bool_val = true }).toBool());
    try testing.expectEqual(false, (Value{ .bool_val = false }).toBool());
    
    // int -> 0 is false, others true
    try testing.expectEqual(false, (Value{ .int_val = 0 }).toBool());
    try testing.expectEqual(true, (Value{ .int_val = 1 }).toBool());
    try testing.expectEqual(true, (Value{ .int_val = -1 }).toBool());
    
    // float -> 0.0 is false, others true
    try testing.expectEqual(false, (Value{ .float_val = 0.0 }).toBool());
    try testing.expectEqual(true, (Value{ .float_val = 1.0 }).toBool());
    try testing.expectEqual(true, (Value{ .float_val = -0.5 }).toBool());
}

test "Value.toInt - various types" {
    // null -> 0
    const null_val: Value = .null_val;
    try testing.expectEqual(@as(i64, 0), null_val.toInt());
    
    // bool -> 0 or 1
    try testing.expectEqual(@as(i64, 1), (Value{ .bool_val = true }).toInt());
    try testing.expectEqual(@as(i64, 0), (Value{ .bool_val = false }).toInt());
    
    // int -> same value
    try testing.expectEqual(@as(i64, 42), (Value{ .int_val = 42 }).toInt());
    
    // float -> truncated
    try testing.expectEqual(@as(i64, 3), (Value{ .float_val = 3.14 }).toInt());
    try testing.expectEqual(@as(i64, -3), (Value{ .float_val = -3.14 }).toInt());
}

test "Value.toFloat - various types" {
    // null -> 0.0
    const null_val: Value = .null_val;
    try testing.expectEqual(@as(f64, 0.0), null_val.toFloat());
    
    // bool -> 0.0 or 1.0
    try testing.expectEqual(@as(f64, 1.0), (Value{ .bool_val = true }).toFloat());
    try testing.expectEqual(@as(f64, 0.0), (Value{ .bool_val = false }).toFloat());
    
    // int -> converted
    try testing.expectEqual(@as(f64, 42.0), (Value{ .int_val = 42 }).toFloat());
    
    // float -> same value
    try testing.expectEqual(@as(f64, 3.14), (Value{ .float_val = 3.14 }).toFloat());
}

// ============================================================================
// VM初始化和清理测试
// ============================================================================

test "bytecode vm - init and deinit" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    
    // Verify initial state
    try testing.expectEqual(@as(u32, 0), vm.stack_top);
    try testing.expectEqual(@as(u32, 0), vm.frame_count);
    try testing.expect(vm.enable_type_feedback);
    try testing.expect(vm.enable_inline_cache);
    
    vm.deinit();
}


test "bytecode vm - builtin functions registered" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // Check that builtin functions are registered
    try testing.expect(vm.builtins.contains("echo"));
    try testing.expect(vm.builtins.contains("print"));
    try testing.expect(vm.builtins.contains("strlen"));
    try testing.expect(vm.builtins.contains("count"));
    try testing.expect(vm.builtins.contains("isset"));
    try testing.expect(vm.builtins.contains("is_null"));
    try testing.expect(vm.builtins.contains("is_int"));
    try testing.expect(vm.builtins.contains("is_string"));
    try testing.expect(vm.builtins.contains("is_array"));
}

// ============================================================================
// 复合操作测试
// ============================================================================

test "bytecode vm - complex arithmetic expression" {
    const allocator = testing.allocator;
    
    var vm = try BytecodeVM.init(allocator);
    defer vm.deinit();
    
    // (5 + 3) * 2 - 4 = 12
    const constants = [_]ConstValue{
        .{ .int_val = 5 },
        .{ .int_val = 3 },
        .{ .int_val = 2 },
        .{ .int_val = 4 },
    };
    
    const bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0), // push 5
        Instruction.init(.push_const, 1, 0), // push 3
        Instruction.init(.add_int, 0, 0),    // 5 + 3 = 8
        Instruction.init(.push_const, 2, 0), // push 2
        Instruction.init(.mul_int, 0, 0),    // 8 * 2 = 16
        Instruction.init(.push_const, 3, 0), // push 4
        Instruction.init(.sub_int, 0, 0),    // 16 - 4 = 12
        Instruction.init(.ret, 0, 0),
    };
    
    const func = try createTestFunction(allocator, &bytecode, &constants);
    defer destroyTestFunction(allocator, func);
    
    try vm.registerFunction("test_complex", func);
    const result = try vm.call("test_complex", &[_]Value{});
    
    try testing.expectEqual(Value{ .int_val = 12 }, result);
}
