const std = @import("std");
const Lexer = @import("src/compiler/lexer.zig").Lexer;
const Parser = @import("src/compiler/parser.zig").Parser;
const PHPContext = @import("src/compiler/root.zig").PHPContext;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const source = 
        \\<?php
        \\struct Point {
        \\    public int $x;
        \\    public int $y;
        \\}
    ;
    
    std.debug.print("Source: {s}\n", .{source});
    
    // Test lexer
    var lexer = Lexer.init(source);
    std.debug.print("Lexer tokens:\n", .{});
    
    var token_count: u32 = 0;
    while (token_count < 10) {
        const token = lexer.next();
        std.debug.print("  Token {d}: {s} at {d}-{d}\n", .{ token_count, @tagName(token.tag), token.loc.start, token.loc.end });
        if (token.tag == .eof) break;
        token_count += 1;
    }
    
    // Test parser
    var context = PHPContext.init(allocator);
    defer context.deinit();
    
    var parser = try Parser.init(allocator, &context, source);
    defer parser.deinit();
    
    std.debug.print("\nParsing...\n", .{});
    const ast = try parser.parse();
    
    const root_node = parser.context.nodes.items[ast];
    std.debug.print("Root node tag: {s}\n", .{@tagName(root_node.tag)});
    std.debug.print("Number of statements: {d}\n", .{root_node.data.root.stmts.len});
}