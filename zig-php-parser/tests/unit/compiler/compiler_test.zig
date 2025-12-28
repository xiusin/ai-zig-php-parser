const std = @import("std");
const testing = std.testing;
const main = @import("main");
const Compiler = main.compiler.compiler.Compiler;
const Parser = main.compiler.parser.Parser;
const PHPContext = main.compiler.parser.PHPContext;
const OpCode = main.compiler.bytecode.OpCode;

test "compile return 1 + 2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php return 1 + 2;";
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    var compiler = Compiler.init(allocator, &context);
    const chunk = try compiler.compile(root_node_index);
    defer chunk.deinit();

    // Expected bytecode sequence:
    // OpConstant (index of 1)
    // OpConstant (index of 2)
    // OpAdd
    // OpReturn

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpConstant)), chunk.code.items[0]);
    const const_index_1 = chunk.code.items[1];
    try testing.expectEqual(@as(i64, 1), chunk.constants.items[const_index_1].data.integer);

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpConstant)), chunk.code.items[2]);
    const const_index_2 = chunk.code.items[3];
    try testing.expectEqual(@as(i64, 2), chunk.constants.items[const_index_2].data.integer);

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpAdd)), chunk.code.items[4]);
    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpReturn)), chunk.code.items[5]);
}

test "compile global variable declaration and access" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php $a = 10; return $a;";
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    var compiler = Compiler.init(allocator, &context);
    const chunk = try compiler.compile(root_node_index);
    defer chunk.deinit();

    // Expected bytecode:
    // OpConstant (10)
    // OpSetGlobal ("$a")
    // OpPop
    // OpGetGlobal ("$a")
    // OpReturn

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpConstant)), chunk.code.items[0]);
    const const_10_idx = chunk.code.items[1];
    try testing.expectEqual(@as(i64, 10), chunk.constants.items[const_10_idx].data.integer);

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpSetGlobal)), chunk.code.items[2]);
    const var_a_idx = chunk.code.items[3];
    try testing.expectEqualStrings("$a", chunk.constants.items[var_a_idx].data.string.data.data);

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpPop)), chunk.code.items[4]);

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpGetGlobal)), chunk.code.items[5]);
    const var_a_idx_2 = chunk.code.items[6];
    try testing.expectEqualStrings("$a", chunk.constants.items[var_a_idx_2].data.string.data.data);

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpReturn)), chunk.code.items[7]);
}

test "compile function call" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php my_func(1, 2);";
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    var compiler = Compiler.init(allocator, &context);
    const main_func = try compiler.compile(root_node_index);
    defer main_func.deinit(allocator);
    const chunk = main_func.chunk;

    // Expected bytecode:
    // OpGetGlobal ("my_func")
    // OpConstant (1)
    // OpConstant (2)
    // OpCall (2 args)
    // OpPop

    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpGetGlobal)), chunk.code.items[0]);
    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpConstant)), chunk.code.items[2]);
    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpConstant)), chunk.code.items[4]);
    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpCall)), chunk.code.items[6]);
    try testing.expectEqual(@as(u8, 2), chunk.code.items[7]); // Arg count
    try testing.expectEqual(@as(u8, @intFromEnum(OpCode.OpPop)), chunk.code.items[8]);
}
