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
