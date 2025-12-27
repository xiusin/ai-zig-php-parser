const std = @import("std");
const testing = std.testing;
const main = @import("main");
const Lexer = main.compiler.lexer.Lexer;
const Parser = main.compiler.parser.Parser;
const Token = main.compiler.token.Token;
const PHPContext = main.compiler.parser.PHPContext;

test "enhanced lexer - PHP 8.5 features" {
    // Test pipe operator
    {
        var lexer = Lexer.init("<?php $x |> fn($y) => $y * 2;");
        _ = lexer.next(); // skip open tag
        
        const var_token = lexer.next();
        try testing.expect(var_token.tag == .t_variable);
        
        const pipe_token = lexer.next();
        try testing.expect(pipe_token.tag == .pipe_greater);
        
        const fn_token = lexer.next();
        try testing.expect(fn_token.tag == .k_fn);
    }
    
    // Test arrow function
    {
        var lexer = Lexer.init("<?php fn($x) => $x * 2");
        _ = lexer.next(); // skip open tag
        
        const fn_token = lexer.next();
        try testing.expect(fn_token.tag == .k_fn);
        
        const lparen = lexer.next();
        try testing.expect(lparen.tag == .l_paren);
        
        const param = lexer.next();
        try testing.expect(param.tag == .t_variable);
        
        const rparen = lexer.next();
        try testing.expect(rparen.tag == .r_paren);
        
        const arrow = lexer.next();
        try testing.expect(arrow.tag == .fat_arrow);
    }
    
    // Test clone with
    {
        var lexer = Lexer.init("<?php clone $obj with { prop: 'value' }");
        _ = lexer.next(); // skip open tag
        
        const clone_token = lexer.next();
        try testing.expect(clone_token.tag == .k_clone);
        
        const var_token = lexer.next();
        try testing.expect(var_token.tag == .t_variable);
        
        const with_token = lexer.next();
        try testing.expect(with_token.tag == .k_with);
    }
    
    // Test floating point numbers
    {
        var lexer = Lexer.init("<?php 3.14159 1.5e10 2.0E-5");
        _ = lexer.next(); // skip open tag
        
        const float1 = lexer.next();
        try testing.expect(float1.tag == .t_dnumber);
        
        const float2 = lexer.next();
        try testing.expect(float2.tag == .t_dnumber);
        
        const float3 = lexer.next();
        try testing.expect(float3.tag == .t_dnumber);
    }
    
    // Test boolean and null literals
    {
        var lexer = Lexer.init("<?php true false null");
        _ = lexer.next(); // skip open tag
        
        const true_token = lexer.next();
        try testing.expect(true_token.tag == .k_true);
        
        const false_token = lexer.next();
        try testing.expect(false_token.tag == .k_false);
        
        const null_token = lexer.next();
        try testing.expect(null_token.tag == .k_null);
    }
}

test "enhanced parser - arrow functions" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    var context = PHPContext.init(arena.allocator());
    defer context.deinit();
    
    var parser = try Parser.init(allocator, &context, "<?php fn($x) => $x * 2;");
    defer parser.deinit();
    
    const ast = try parser.parse();
    try testing.expect(ast != 0);
}

test "enhanced parser - try-catch-finally" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    var context = PHPContext.init(arena.allocator());
    defer context.deinit();
    
    const source = 
        \\<?php
        \\try {
        \\    throw new Exception("test");
        \\} catch (Exception $e) {
        \\    echo $e->getMessage();
        \\} finally {
        \\    echo "cleanup";
        \\}
    ;
    
    var parser = try Parser.init(allocator, &context, source);
    defer parser.deinit();
    
    const ast = try parser.parse();
    try testing.expect(ast != 0);
}

test "enhanced parser - array literals" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    var context = PHPContext.init(arena.allocator());
    defer context.deinit();
    
    var parser = try Parser.init(allocator, &context, "<?php [1, 2, 3, 'hello'];");
    defer parser.deinit();
    
    const ast = try parser.parse();
    try testing.expect(ast != 0);
}

test "enhanced parser - pipe operator" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    var context = PHPContext.init(arena.allocator());
    defer context.deinit();
    
    var parser = try Parser.init(allocator, &context, "<?php $value |> strtoupper |> trim;");
    defer parser.deinit();
    
    const ast = try parser.parse();
    try testing.expect(ast != 0);
}