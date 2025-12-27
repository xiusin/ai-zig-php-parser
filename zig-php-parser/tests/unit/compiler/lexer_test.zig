const std = @import("std");
const testing = std.testing;
const Lexer = @import("main").compiler.lexer.Lexer;
const Token = @import("main").compiler.token.Token;
const Allocator = std.mem.Allocator;

fn expectToken(lexer: *Lexer, expected_tag: Token.Tag) !void {
    const token = try lexer.next();
    try testing.expectEqual(token.tag, expected_tag);
}

test "tokenize keywords" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "class function if struct";
    var lexer = Lexer.init(allocator, source);

    try expectToken(&lexer, .k_class);
    try expectToken(&lexer, .k_function);
    try expectToken(&lexer, .k_if);
    try expectToken(&lexer, .k_struct);
    try expectToken(&lexer, .eof);
}

test "tokenize literals" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "123 \"hello\"";
    var lexer = Lexer.init(allocator, source);

    try expectToken(&lexer, .t_lnumber);
    try expectToken(&lexer, .t_constant_encapsed_string);
    try expectToken(&lexer, .eof);
}

test "tokenize operators" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "+ -> ==";
    var lexer = Lexer.init(allocator, source);

    try expectToken(&lexer, .plus);
    try expectToken(&lexer, .arrow);
    try expectToken(&lexer, .equal_equal);
    try expectToken(&lexer, .eof);
}
