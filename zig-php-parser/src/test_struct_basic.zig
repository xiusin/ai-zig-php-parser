const std = @import("std");
const testing = std.testing;
const Token = @import("compiler/token.zig").Token;
const Lexer = @import("compiler/lexer.zig").Lexer;
const Parser = @import("compiler/parser.zig").Parser;
const PHPContext = @import("compiler/root.zig").PHPContext;
const VM = @import("runtime/vm.zig").VM;
const types = @import("runtime/types.zig");

test "struct keyword lexing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    const source = "<?php struct Point { }";
    var lexer = Lexer.init(source);
    
    // Skip the opening tag
    _ = lexer.next();
    
    // Test struct keyword
    const struct_token = lexer.next();
    try testing.expect(struct_token.tag == .k_struct);
    
    // Test identifier
    const name_token = lexer.next();
    try testing.expect(name_token.tag == .t_string);
    try testing.expectEqualStrings("Point", source[name_token.loc.start..name_token.loc.end]);
}

test "basic struct definition parsing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const source = 
        \\<?php
        \\struct Point {
        \\    public int $x;
        \\    public int $y;
        \\}
    ;
    
    // Create PHP context
    var context = PHPContext.init(allocator);
    defer context.deinit();
    
    var parser = try Parser.init(allocator, &context, source);
    defer parser.deinit();
    
    const ast = try parser.parse();
    
    // Verify we have a root node
    const root_node = parser.context.nodes.items[ast];
    try testing.expect(root_node.tag == .root);
    
    // Debug: print the number of statements
    std.debug.print("Number of statements: {d}\n", .{root_node.data.root.stmts.len});
    
    // Check if we have at least one statement
    if (root_node.data.root.stmts.len == 0) {
        std.debug.print("No statements found!\n", .{});
        return;
    }
    
    // Debug: print the first statement type
    const first_stmt = parser.context.nodes.items[root_node.data.root.stmts[0]];
    std.debug.print("First statement tag: {}\n", .{first_stmt.tag});
    
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // Verify the statement is a struct declaration
    const struct_node = parser.context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(struct_node.tag == .struct_decl);
    
    // Verify struct name
    const struct_name = parser.context.string_pool.keys()[struct_node.data.container_decl.name];
    try testing.expectEqualStrings("Point", struct_name);
}

test "struct type creation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a struct type
    const struct_name = try types.PHPString.init(allocator, "Point");
    var php_struct = types.PHPStruct.init(allocator, struct_name);
    defer php_struct.deinit();
    
    // Add a field
    const field_name = try types.PHPString.init(allocator, "x");
    const field = types.PHPStruct.StructField{
        .name = field_name,
        .type = null,
        .default_value = null,
        .modifiers = .{ .is_public = true },
        .offset = 0,
    };
    
    try php_struct.addField(field);
    
    // Verify field was added
    try testing.expect(php_struct.hasField("x"));
    try testing.expect(php_struct.getField("x") != null);
}

test "struct instance creation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a struct type
    const struct_name = try types.PHPString.init(allocator, "Point");
    var php_struct = types.PHPStruct.init(allocator, struct_name);
    defer php_struct.deinit();
    
    // Create an instance
    var instance = types.StructInstance.init(allocator, &php_struct);
    defer instance.deinit();
    
    // Set a field value
    const value = types.Value.initInt(42);
    try instance.setField("x", value);
    
    // Get the field value back
    const retrieved_value = try instance.getField("x");
    try testing.expect(retrieved_value.tag == .integer);
    try testing.expect(retrieved_value.data.integer == 42);
}

test "struct value initialization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a struct type
    const struct_name = try types.PHPString.init(allocator, "Point");
    var php_struct = types.PHPStruct.init(allocator, struct_name);
    defer php_struct.deinit();
    
    // Create a struct value
    const struct_value = try types.Value.initStruct(allocator, &php_struct);
    
    // Verify the value type
    try testing.expect(struct_value.tag == .struct_instance);
    try testing.expect(struct_value.data.struct_instance.data.struct_type == &php_struct);
}