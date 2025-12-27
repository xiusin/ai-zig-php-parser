const std = @import("std");
const testing = std.testing;
const Parser = @import("main").compiler.parser.Parser;
const PHPContext = @import("main").compiler.parser.PHPContext;
const ast = @import("main").compiler.ast;
const Allocator = std.mem.Allocator;

test "parse assignment statement" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php $a = 1;";
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);

    const root_node_index = try parser.parse();
    const root_node = context.nodes.items[root_node_index];

    // Expect root node to contain one statement
    try testing.expectEqual(root_node.data.root.stmts.len, 1);

    const assignment_node_index = root_node.data.root.stmts[0];
    const assignment_node = context.nodes.items[assignment_node_index];

    // Expect the statement to be an assignment
    try testing.expectEqual(assignment_node.tag, ast.Node.Tag.assignment);

    // Check target variable
    const target_node = context.nodes.items[assignment_node.data.assignment.target];
    try testing.expectEqual(target_node.tag, ast.Node.Tag.variable);
    const var_name = context.string_pool.keys()[target_node.data.variable.name];
    try testing.expectEqualStrings(var_name, "$a");

    // Check assigned value
    const value_node = context.nodes.items[assignment_node.data.assignment.value];
    try testing.expectEqual(value_node.tag, ast.Node.Tag.literal_int);
    try testing.expectEqual(value_node.data.literal_int.value, 1);
}
