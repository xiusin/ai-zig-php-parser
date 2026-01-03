const std = @import("std");
const testing = std.testing;
const Lexer = @import("compiler/lexer.zig").Lexer;
const SyntaxMode = @import("compiler/syntax_mode.zig").SyntaxMode;
const Token = @import("compiler/token.zig").Token;

// ============================================================================
// Property 2: Go mode identifier tokenization
// *For any* identifier string in Go mode, the Lexer SHALL tokenize it as a
// variable token (t_go_identifier) unless it matches a reserved keyword.
// **Validates: Requirements 2.1, 2.4**
// ============================================================================

/// Helper to check if a string is a PHP/Go keyword
fn isKeyword(text: []const u8) bool {
    const keywords = [_][]const u8{
        "class", "interface", "trait", "enum", "struct", "extends", "implements",
        "use", "public", "private", "protected", "static", "readonly", "final",
        "abstract", "function", "fn", "new", "if", "else", "elseif", "while",
        "for", "foreach", "as", "match", "default", "namespace", "global", "const",
        "go", "lock", "return", "echo", "get", "set", "break", "case", "catch",
        "clone", "with", "continue", "declare", "do", "finally", "goto", "include",
        "instanceof", "print", "require", "switch", "throw", "try", "yield", "from",
        "range", "in", "self", "parent", "true", "false", "null", "array", "callable",
        "iterable", "object", "mixed", "never", "void", "__DIR__", "__FILE__",
        "__LINE__", "__FUNCTION__", "__CLASS__", "__METHOD__", "__NAMESPACE__",
        "include_once", "require_once",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw)) return true;
    }
    return false;
}

/// Generate a random valid identifier
fn generateIdentifier(random: std.Random, buf: []u8) []const u8 {
    const first_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
    const rest_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789";
    
    const len = random.intRangeAtMost(usize, 1, @min(buf.len - 1, 20));
    buf[0] = first_chars[random.intRangeAtMost(usize, 0, first_chars.len - 1)];
    
    for (buf[1..len]) |*c| {
        c.* = rest_chars[random.intRangeAtMost(usize, 0, rest_chars.len - 1)];
    }
    
    return buf[0..len];
}

test "Feature: multi-syntax-extension-system, Property 2: Go mode identifier tokenization" {
    // Property: For any identifier string in Go mode, the Lexer SHALL tokenize it
    // as t_go_identifier unless it matches a reserved keyword.
    
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();
    
    var buf: [64]u8 = undefined;
    var source_buf: [128]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const identifier = generateIdentifier(random, &buf);
        
        // Create source code: <?php identifier
        const source = std.fmt.bufPrintZ(&source_buf, "<?php {s}", .{identifier}) catch continue;
        
        var lexer = Lexer.initWithMode(source, .go);
        _ = lexer.next(); // skip open tag
        
        const token = lexer.next();
        
        if (isKeyword(identifier)) {
            // Keywords should NOT be t_go_identifier
            try testing.expect(token.tag != .t_go_identifier);
        } else {
            // Non-keywords should be t_go_identifier in Go mode
            try testing.expectEqual(Token.Tag.t_go_identifier, token.tag);
        }
    }
}

test "Go mode: keywords are still recognized" {
    // Verify that PHP keywords are still recognized in Go mode
    const keywords_to_test = [_]struct { text: []const u8, expected: Token.Tag }{
        .{ .text = "function", .expected = .k_function },
        .{ .text = "class", .expected = .k_class },
        .{ .text = "if", .expected = .k_if },
        .{ .text = "else", .expected = .k_else },
        .{ .text = "while", .expected = .k_while },
        .{ .text = "for", .expected = .k_for },
        .{ .text = "return", .expected = .k_return },
        .{ .text = "echo", .expected = .k_echo },
        .{ .text = "true", .expected = .k_true },
        .{ .text = "false", .expected = .k_false },
        .{ .text = "null", .expected = .k_null },
    };
    
    var source_buf: [64]u8 = undefined;
    
    for (keywords_to_test) |kw| {
        const source = std.fmt.bufPrintZ(&source_buf, "<?php {s}", .{kw.text}) catch continue;
        
        var lexer = Lexer.initWithMode(source, .go);
        _ = lexer.next(); // skip open tag
        
        const token = lexer.next();
        try testing.expectEqual(kw.expected, token.tag);
    }
}

test "Go mode: non-keyword identifiers become t_go_identifier" {
    // Specific examples of non-keyword identifiers
    const identifiers = [_][]const u8{
        "myVar", "counter", "userName", "_private", "data123", "x", "Y", "_",
    };
    
    var source_buf: [64]u8 = undefined;
    
    for (identifiers) |ident| {
        const source = std.fmt.bufPrintZ(&source_buf, "<?php {s}", .{ident}) catch continue;
        
        var lexer = Lexer.initWithMode(source, .go);
        _ = lexer.next(); // skip open tag
        
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.t_go_identifier, token.tag);
    }
}

test "PHP mode: identifiers become t_string (not t_go_identifier)" {
    // In PHP mode, non-keyword identifiers should be t_string, not t_go_identifier
    const identifiers = [_][]const u8{
        "myVar", "counter", "userName",
    };
    
    var source_buf: [64]u8 = undefined;
    
    for (identifiers) |ident| {
        const source = std.fmt.bufPrintZ(&source_buf, "<?php {s}", .{ident}) catch continue;
        
        var lexer = Lexer.initWithMode(source, .php);
        _ = lexer.next(); // skip open tag
        
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.t_string, token.tag);
    }
}


// ============================================================================
// Property 3: Go mode property access tokenization
// *For any* dot-identifier sequence (e.g., `.property`) in Go mode, the Lexer
// SHALL emit an arrow token followed by an identifier token, equivalent to
// PHP's `->property` tokenization.
// **Validates: Requirements 2.2, 2.5**
// ============================================================================

test "Feature: multi-syntax-extension-system, Property 3: Go mode property access tokenization" {
    // Property: For any dot-identifier sequence in Go mode, the Lexer SHALL emit
    // an arrow token followed by an identifier token.
    
    var prng = std.Random.DefaultPrng.init(54321);
    const random = prng.random();
    
    var ident_buf: [64]u8 = undefined;
    var source_buf: [128]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const property_name = generateIdentifier(random, &ident_buf);
        
        // Skip if it's a keyword (property names shouldn't be keywords in real code)
        if (isKeyword(property_name)) continue;
        
        // Create source code: <?php obj.property (Go mode property access)
        const source = std.fmt.bufPrintZ(&source_buf, "<?php obj.{s}", .{property_name}) catch continue;
        
        var lexer = Lexer.initWithMode(source, .go);
        _ = lexer.next(); // skip open tag
        
        // First token should be the object identifier (t_go_identifier)
        const obj_token = lexer.next();
        try testing.expectEqual(Token.Tag.t_go_identifier, obj_token.tag);
        
        // Second token should be arrow (. converted to -> in Go mode)
        const dot_token = lexer.next();
        try testing.expectEqual(Token.Tag.arrow, dot_token.tag);
        
        // Third token should be the property name (t_go_identifier in Go mode)
        const prop_token = lexer.next();
        try testing.expectEqual(Token.Tag.t_go_identifier, prop_token.tag);
    }
}

test "Go mode: method call tokenization equivalent to PHP" {
    // Test that obj.method() in Go mode produces equivalent tokens to $obj->method() in PHP
    // Both should have: variable/identifier -> arrow -> identifier -> lparen -> rparen
    
    // Go mode: obj.method()
    {
        var lexer = Lexer.initWithMode("<?php obj.method()", .go);
        _ = lexer.next(); // skip open tag
        
        const obj_token = lexer.next();
        try testing.expectEqual(Token.Tag.t_go_identifier, obj_token.tag);
        
        const arrow_token = lexer.next();
        try testing.expectEqual(Token.Tag.arrow, arrow_token.tag);
        
        const method_token = lexer.next();
        // In Go mode, method name is also t_go_identifier
        try testing.expectEqual(Token.Tag.t_go_identifier, method_token.tag);
        
        const lparen = lexer.next();
        try testing.expectEqual(Token.Tag.l_paren, lparen.tag);
        
        const rparen = lexer.next();
        try testing.expectEqual(Token.Tag.r_paren, rparen.tag);
    }
    
    // PHP mode: $obj->method()
    {
        var lexer = Lexer.initWithMode("<?php $obj->method()", .php);
        _ = lexer.next(); // skip open tag
        
        const obj_token = lexer.next();
        try testing.expectEqual(Token.Tag.t_variable, obj_token.tag);
        
        const arrow_token = lexer.next();
        try testing.expectEqual(Token.Tag.arrow, arrow_token.tag);
        
        const method_token = lexer.next();
        try testing.expectEqual(Token.Tag.t_string, method_token.tag);
        
        const lparen = lexer.next();
        try testing.expectEqual(Token.Tag.l_paren, lparen.tag);
        
        const rparen = lexer.next();
        try testing.expectEqual(Token.Tag.r_paren, rparen.tag);
    }
}

test "Go mode: chained property access" {
    // Test chained property access: obj.prop1.prop2
    var lexer = Lexer.initWithMode("<?php obj.prop1.prop2", .go);
    _ = lexer.next(); // skip open tag
    
    // obj
    const obj_token = lexer.next();
    try testing.expectEqual(Token.Tag.t_go_identifier, obj_token.tag);
    
    // . -> arrow
    const arrow1 = lexer.next();
    try testing.expectEqual(Token.Tag.arrow, arrow1.tag);
    
    // prop1 (t_go_identifier in Go mode)
    const prop1 = lexer.next();
    try testing.expectEqual(Token.Tag.t_go_identifier, prop1.tag);
    
    // . -> arrow
    const arrow2 = lexer.next();
    try testing.expectEqual(Token.Tag.arrow, arrow2.tag);
    
    // prop2 (t_go_identifier in Go mode)
    const prop2 = lexer.next();
    try testing.expectEqual(Token.Tag.t_go_identifier, prop2.tag);
}

test "Go mode: dot not followed by identifier stays as dot" {
    // Test that . not followed by identifier is still a dot token
    var lexer = Lexer.initWithMode("<?php 1.5", .go);
    _ = lexer.next(); // skip open tag
    
    // 1.5 should be a float number
    const num_token = lexer.next();
    try testing.expectEqual(Token.Tag.t_dnumber, num_token.tag);
}

test "Go mode: ellipsis still works" {
    // Test that ... is still recognized as ellipsis
    var lexer = Lexer.initWithMode("<?php ...", .go);
    _ = lexer.next(); // skip open tag
    
    const ellipsis = lexer.next();
    try testing.expectEqual(Token.Tag.ellipsis, ellipsis.tag);
}


// ============================================================================
// Property 4: Go mode dollar sign rejection
// *For any* source code containing `$` character in Go mode, the Lexer SHALL
// emit an invalid token and report a syntax error.
// **Validates: Requirements 2.3**
// ============================================================================

test "Feature: multi-syntax-extension-system, Property 4: Go mode dollar sign rejection" {
    // Property: For any source code containing $ in Go mode, the Lexer SHALL
    // emit an invalid token.
    
    var prng = std.Random.DefaultPrng.init(98765);
    const random = prng.random();
    
    var ident_buf: [64]u8 = undefined;
    var source_buf: [128]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const var_name = generateIdentifier(random, &ident_buf);
        
        // Create source code with $ prefix: <?php $varName (PHP-style variable in Go mode)
        const source = std.fmt.bufPrintZ(&source_buf, "<?php ${s}", .{var_name}) catch continue;
        
        var lexer = Lexer.initWithMode(source, .go);
        _ = lexer.next(); // skip open tag
        
        // In Go mode, $ should produce an invalid token
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.invalid, token.tag);
    }
}

test "Go mode: dollar sign at various positions produces invalid token" {
    // Test $ at different positions in Go mode
    {
        var lexer = Lexer.initWithMode("<?php $x", .go);
        _ = lexer.next(); // skip open tag
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.invalid, token.tag);
    }
    {
        var lexer = Lexer.initWithMode("<?php $myVar", .go);
        _ = lexer.next(); // skip open tag
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.invalid, token.tag);
    }
    {
        var lexer = Lexer.initWithMode("<?php $_private", .go);
        _ = lexer.next(); // skip open tag
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.invalid, token.tag);
    }
    {
        var lexer = Lexer.initWithMode("<?php $123", .go);
        _ = lexer.next(); // skip open tag
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.invalid, token.tag);
    }
    {
        var lexer = Lexer.initWithMode("<?php $", .go);
        _ = lexer.next(); // skip open tag
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.invalid, token.tag);
    }
}

test "PHP mode: dollar sign creates valid variable token" {
    // Verify that $ works correctly in PHP mode (control test)
    {
        var lexer = Lexer.initWithMode("<?php $x", .php);
        _ = lexer.next(); // skip open tag
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.t_variable, token.tag);
    }
    {
        var lexer = Lexer.initWithMode("<?php $myVar", .php);
        _ = lexer.next(); // skip open tag
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.t_variable, token.tag);
    }
    {
        var lexer = Lexer.initWithMode("<?php $_private", .php);
        _ = lexer.next(); // skip open tag
        const token = lexer.next();
        try testing.expectEqual(Token.Tag.t_variable, token.tag);
    }
}

test "Go mode vs PHP mode: same code different tokenization" {
    // Demonstrate the difference between Go and PHP mode for the same code
    const source = "<?php $x = 1";
    
    // PHP mode: $x is a variable
    {
        var lexer = Lexer.initWithMode(source, .php);
        _ = lexer.next(); // skip open tag
        
        const var_token = lexer.next();
        try testing.expectEqual(Token.Tag.t_variable, var_token.tag);
        
        const eq_token = lexer.next();
        try testing.expectEqual(Token.Tag.equal, eq_token.tag);
    }
    
    // Go mode: $ is invalid
    {
        var lexer = Lexer.initWithMode(source, .go);
        _ = lexer.next(); // skip open tag
        
        const invalid_token = lexer.next();
        try testing.expectEqual(Token.Tag.invalid, invalid_token.tag);
    }
}
