const std = @import("std");
const testing = std.testing;
const main = @import("main");
const Parser = main.compiler.parser.Parser;
const PHPContext = main.compiler.parser.PHPContext;
const Compiler = main.compiler.compiler.Compiler;
const VM = main.runtime.vm.VM;

test "end-to-end execution: return 1 + 2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php return 1 + 2;";

    // 1. Parsing
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    // 2. Compiling
    var compiler = Compiler.init(allocator, &context);
    const chunk = try compiler.compile(root_node_index);
    defer chunk.deinit();

    // 3. Execution
    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(chunk);

    // 4. Verification
    try testing.expectEqual(result.tag, .integer);
    try testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "end-to-end execution: global variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php $a = 42; return $a;";

    // 1. Parsing
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    // 2. Compiling
    var compiler = Compiler.init(allocator, &context);
    const chunk = try compiler.compile(root_node_index);
    defer chunk.deinit();

    // 3. Execution
    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(chunk);

    // 4. Verification
    try testing.expectEqual(result.tag, .integer);
    try testing.expectEqual(@as(i64, 42), result.data.integer);
}

test "end-to-end execution: mixed-type arithmetic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php return (10 / 2) + 1;";

    // 1. Parsing
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    // 2. Compiling
    var compiler = Compiler.init(allocator, &context);
    const chunk = try compiler.compile(root_node_index);
    defer chunk.deinit();

    // 3. Execution
    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(chunk);

    // 4. Verification
    try testing.expectEqual(result.tag, .float);
    try testing.expectEqual(@as(f64, 6.0), result.data.float);
}

test "end-to-end execution: simple function call" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Manually build a function and its bytecode for testing
    // Equivalent to: function add($a, $b) { return $a + $b; } return add(3, 4);

    // 1. Create the 'add' function object
    var add_func_name = try main.runtime.types.PHPString.init(allocator, "add");
    var add_function = main.runtime.types.UserFunction.init(add_func_name);
    var add_chunk = main.compiler.bytecode.Chunk.init(allocator);
    add_function.chunk = &add_chunk;

    // Bytecode for 'add' function: get local a, get local b, add, return
    try add_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpGetLocal), 1);
    try add_chunk.write(0, 1); // slot 0 for $a
    try add_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpGetLocal), 1);
    try add_chunk.write(1, 1); // slot 1 for $b
    try add_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpAdd), 1);
    try add_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpReturn), 1);

    // 2. Create the main script function
    var main_func_name = try main.runtime.types.PHPString.init(allocator, "<script>");
    var main_function = main.runtime.types.UserFunction.init(main_func_name);
    var main_chunk = main.compiler.bytecode.Chunk.init(allocator);
    main_function.chunk = &main_chunk;

    // Bytecode for main script: push 'add' func, push 3, push 4, call, return
    const add_func_ptr_for_value = &add_function;
    const add_func_const_idx = try main_chunk.addConstant(main.runtime.types.Value{ .user_function = @ptrCast(add_func_ptr_for_value) });
    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpConstant), 1);
    try main_chunk.write(add_func_const_idx, 1);

    const const_3_idx = try main_chunk.addConstant(main.runtime.types.Value.initInt(3));
    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpConstant), 1);
    try main_chunk.write(const_3_idx, 1);

    const const_4_idx = try main_chunk.addConstant(main.runtime.types.Value.initInt(4));
    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpConstant), 1);
    try main_chunk.write(const_4_idx, 1);

    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpCall), 1);
    try main_chunk.write(2, 1); // 2 arguments

    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpReturn), 1);

    // 3. Execution
    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(&main_function);

    // 4. Verification
    try testing.expectEqual(result.tag, .integer);
    try testing.expectEqual(@as(i64, 7), result.data.integer);

    // Manual deinit for this test
    add_chunk.deinit();
    main_chunk.deinit();
    add_func_name.deinit(allocator);
    main_func_name.deinit(allocator);
}

test "end-to-end execution: return value handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Equivalent to: `function identity($a) { return $a; } return identity(5) + 1;`

    // For this test, we have to manually compile because the compiler doesn't fully support functions yet.
    // Let's build the functions and chunks by hand.

    // 1. Create 'identity' function
    var identity_func_name = try main.runtime.types.PHPString.init(allocator, "identity");
    var identity_function = main.runtime.types.UserFunction.init(identity_func_name);
    var identity_chunk = main.compiler.bytecode.Chunk.init(allocator);
    identity_function.chunk = &identity_chunk;
    try identity_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpGetLocal), 1);
    try identity_chunk.write(0, 1); // Get local at slot 0 ($a)
    try identity_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpReturn), 1);

    // 2. Create the main script function
    var main_func_name = try main.runtime.types.PHPString.init(allocator, "<script>");
    var main_function = main.runtime.types.UserFunction.init(main_func_name);
    var main_chunk = main.compiler.bytecode.Chunk.init(allocator);
    main_function.chunk = &main_chunk;

    // Bytecode for main: get global 'identity', push 5, call, push 1, add, return
    const identity_func_ptr = &identity_function;
    const identity_val = main.runtime.types.Value{.user_function = @ptrCast(identity_func_ptr)};
    const identity_const_idx = try main_chunk.addConstant(identity_val);
    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpConstant), 1);
    try main_chunk.write(identity_const_idx, 1);

    const const_5_idx = try main_chunk.addConstant(main.runtime.types.Value.initInt(5));
    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpConstant), 1);
    try main_chunk.write(const_5_idx, 1);

    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpCall), 1);
    try main_chunk.write(1, 1); // 1 argument

    const const_1_idx = try main_chunk.addConstant(main.runtime.types.Value.initInt(1));
    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpConstant), 1);
    try main_chunk.write(const_1_idx, 1);

    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpAdd), 1);
    try main_chunk.write(@intFromEnum(main.compiler.bytecode.OpCode.OpReturn), 1);

    // 3. Execution
    var vm = VM.init(allocator);
    defer vm.deinit();

    // Manually put 'identity' function into globals
    try vm.globals.put("identity", identity_val);

    const result = try vm.interpret(&main_function);

    // 4. Verification
    try testing.expectEqual(result.tag, .integer);
    try testing.expectEqual(@as(i64, 6), result.data.integer);

    // Manual deinit
    identity_chunk.deinit();
    main_chunk.deinit();
    identity_func_name.deinit(allocator);
    main_func_name.deinit(allocator);
}

test "end-to-end execution: function with parameters via compiler" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php function identity($a) { return $a; } return identity(99);";

    // 1. Parsing
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    // 2. Compiling
    var compiler = Compiler.init(allocator, &context, null);
    const main_func = try compiler.compile(root_node_index);
    defer main_func.deinit(allocator);

    // 3. Execution
    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(main_func);

    // 4. Verification
    try testing.expectEqual(result.tag, .integer);
    try testing.expectEqual(@as(i64, 99), result.data.integer);
}

test "end-to-end: if statement (true condition)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php if (1) { return 3; } else { return 4; }";

    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    var compiler = Compiler.init(allocator, &context, null);
    const main_func = try compiler.compile(root_node_index);
    defer main_func.deinit(allocator);

    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(main_func);

    try testing.expectEqual(result.tag, .integer);
    try testing.expectEqual(@as(i64, 3), result.data.integer);
}

test "end-to-end: if statement (false condition)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php if (0) { return 3; } else { return 4; }";

    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    var compiler = Compiler.init(allocator, &context, null);
    const main_func = try compiler.compile(root_node_index);
    defer main_func.deinit(allocator);

    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(main_func);

    try testing.expectEqual(result.tag, .integer);
    try testing.expectEqual(@as(i64, 4), result.data.integer);
}
