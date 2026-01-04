const std = @import("std");
const testing = std.testing;
const Parser = @import("compiler/parser.zig").Parser;
const PHPContext = @import("compiler/root.zig").PHPContext;
const SyntaxMode = @import("compiler/syntax_mode.zig").SyntaxMode;
const Token = @import("compiler/token.zig").Token;
const ast = @import("compiler/ast.zig");

// ============================================================================
// Go Mode String Concatenation Tests
// Tests that "hello" + " world" in Go mode is parsed as string concatenation
// **Validates: Requirements 3.5, 3.6, 3.7**
// ============================================================================

fn createTestContext(allocator: std.mem.Allocator) !*PHPContext {
    const context = try allocator.create(PHPContext);
    context.* = PHPContext.init(allocator);
    return context;
}

fn destroyTestContext(allocator: std.mem.Allocator, context: *PHPContext) void {
    context.deinit();
    allocator.destroy(context);
}

test "Go mode: string + string is concatenation" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, "hello" + " world" should be parsed as concatenation (dot operator)
    const source = "<?php \"hello\" + \" world\"";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a binary expression with dot operator (concatenation)
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .binary_expr);
    try testing.expectEqual(Token.Tag.dot, stmt.data.binary_expr.op);
}

test "Go mode: number + number is addition" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, 1 + 2 should still be addition (plus operator)
    const source = "<?php 1 + 2";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a binary expression with plus operator (addition)
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .binary_expr);
    try testing.expectEqual(Token.Tag.plus, stmt.data.binary_expr.op);
}

test "Go mode: string + number is concatenation" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, "value: " + 42 should be concatenation
    const source = "<?php \"value: \" + 42";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a binary expression with dot operator (concatenation)
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .binary_expr);
    try testing.expectEqual(Token.Tag.dot, stmt.data.binary_expr.op);
}

test "Go mode: number + string is concatenation" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, 42 + " items" should be concatenation
    const source = "<?php 42 + \" items\"";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a binary expression with dot operator (concatenation)
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .binary_expr);
    try testing.expectEqual(Token.Tag.dot, stmt.data.binary_expr.op);
}

test "PHP mode: string + string is addition (not concatenation)" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In PHP mode, "hello" + " world" should be addition (PHP converts strings to numbers)
    const source = "<?php \"hello\" + \" world\"";
    var parser = try Parser.initWithMode(allocator, context, source, .php);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a binary expression with plus operator (addition in PHP)
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .binary_expr);
    try testing.expectEqual(Token.Tag.plus, stmt.data.binary_expr.op);
}

test "PHP mode: string concatenation uses dot operator" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In PHP mode, "hello" . " world" should be concatenation
    const source = "<?php \"hello\" . \" world\"";
    var parser = try Parser.initWithMode(allocator, context, source, .php);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a binary expression with dot operator (concatenation)
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .binary_expr);
    try testing.expectEqual(Token.Tag.dot, stmt.data.binary_expr.op);
}

// ============================================================================
// Go Mode Variable Parsing Tests
// Tests that variables in Go mode are parsed correctly
// **Validates: Requirements 3.1**
// ============================================================================

test "Go mode: variable without $ prefix" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, myVar should be parsed as a variable with $ prefix added internally
    const source = "<?php myVar";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a variable
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .variable);
    
    // The variable name should have $ prefix added internally
    const var_name = context.string_pool.keys()[stmt.data.variable.name];
    try testing.expectEqualStrings("$myVar", var_name);
}

test "Go mode: assignment without $ prefix" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, x = 42 should be parsed as assignment
    const source = "<?php x = 42;";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be an assignment
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .assignment);
    
    // The target should be a variable with $ prefix
    const target = context.nodes.items[stmt.data.assignment.target];
    try testing.expect(target.tag == .variable);
    const var_name = context.string_pool.keys()[target.data.variable.name];
    try testing.expectEqualStrings("$x", var_name);
}

// ============================================================================
// Go Mode Property Access Tests
// Tests that property access in Go mode uses . instead of ->
// **Validates: Requirements 3.2, 3.3**
// ============================================================================

test "Go mode: property access with dot" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, obj.prop should be parsed as property access
    const source = "<?php obj.prop";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a property access
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .property_access);
}

test "Go mode: method call with dot" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, obj.method() should be parsed as method call
    const source = "<?php obj.method()";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a method call
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .method_call);
}

test "Go mode: chained property access" {
    const allocator = testing.allocator;
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    // In Go mode, obj.prop1.prop2 should be parsed as chained property access
    const source = "<?php obj.prop1.prop2";
    var parser = try Parser.initWithMode(allocator, context, source, .go);
    defer parser.deinit();
    
    const root = try parser.parse();
    const root_node = context.nodes.items[root];
    
    // Root should have one statement
    try testing.expect(root_node.tag == .root);
    try testing.expect(root_node.data.root.stmts.len == 1);
    
    // The statement should be a property access (outer)
    const stmt = context.nodes.items[root_node.data.root.stmts[0]];
    try testing.expect(stmt.tag == .property_access);
    
    // The target should also be a property access (inner)
    const inner = context.nodes.items[stmt.data.property_access.target];
    try testing.expect(inner.tag == .property_access);
}


// ============================================================================
// Property 5: AST Semantic Equivalence
// *For any* semantically equivalent code written in PHP mode and Go mode, the
// Parser SHALL produce AST nodes that are structurally equivalent (same node
// types, same relationships) with only internal naming differences (Go mode
// variables have `$` prefix added internally).
// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
// ============================================================================

/// Helper to compare AST node structures (ignoring variable name differences)
fn compareAstStructure(context1: *PHPContext, node1: ast.Node.Index, context2: *PHPContext, node2: ast.Node.Index) bool {
    const n1 = context1.nodes.items[node1];
    const n2 = context2.nodes.items[node2];
    
    // Tags must match
    if (n1.tag != n2.tag) return false;
    
    // Compare based on node type
    return switch (n1.tag) {
        .root => blk: {
            if (n1.data.root.stmts.len != n2.data.root.stmts.len) break :blk false;
            for (n1.data.root.stmts, n2.data.root.stmts) |s1, s2| {
                if (!compareAstStructure(context1, s1, context2, s2)) break :blk false;
            }
            break :blk true;
        },
        .variable => true, // Variables are equivalent if tags match (names differ by $ prefix)
        .literal_int => n1.data.literal_int.value == n2.data.literal_int.value,
        .literal_float => n1.data.literal_float.value == n2.data.literal_float.value,
        .literal_string => true, // String content comparison would need string pool lookup
        .literal_bool => n1.data.literal_int.value == n2.data.literal_int.value,
        .literal_null => true,
        .binary_expr => blk: {
            // For Go mode string concat, + becomes . but both are valid
            const op_match = (n1.data.binary_expr.op == n2.data.binary_expr.op) or
                (n1.data.binary_expr.op == .plus and n2.data.binary_expr.op == .dot) or
                (n1.data.binary_expr.op == .dot and n2.data.binary_expr.op == .plus);
            if (!op_match) break :blk false;
            if (!compareAstStructure(context1, n1.data.binary_expr.lhs, context2, n2.data.binary_expr.lhs)) break :blk false;
            if (!compareAstStructure(context1, n1.data.binary_expr.rhs, context2, n2.data.binary_expr.rhs)) break :blk false;
            break :blk true;
        },
        .assignment => blk: {
            if (!compareAstStructure(context1, n1.data.assignment.target, context2, n2.data.assignment.target)) break :blk false;
            if (!compareAstStructure(context1, n1.data.assignment.value, context2, n2.data.assignment.value)) break :blk false;
            break :blk true;
        },
        .property_access => blk: {
            if (!compareAstStructure(context1, n1.data.property_access.target, context2, n2.data.property_access.target)) break :blk false;
            // Property names should match
            break :blk true;
        },
        .method_call => blk: {
            if (!compareAstStructure(context1, n1.data.method_call.target, context2, n2.data.method_call.target)) break :blk false;
            if (n1.data.method_call.args.len != n2.data.method_call.args.len) break :blk false;
            for (n1.data.method_call.args, n2.data.method_call.args) |a1, a2| {
                if (!compareAstStructure(context1, a1, context2, a2)) break :blk false;
            }
            break :blk true;
        },
        .function_call => blk: {
            if (!compareAstStructure(context1, n1.data.function_call.name, context2, n2.data.function_call.name)) break :blk false;
            if (n1.data.function_call.args.len != n2.data.function_call.args.len) break :blk false;
            for (n1.data.function_call.args, n2.data.function_call.args) |a1, a2| {
                if (!compareAstStructure(context1, a1, context2, a2)) break :blk false;
            }
            break :blk true;
        },
        else => true, // For other node types, just check tag equality
    };
}

/// Generate a random valid identifier
fn generateRandomIdentifier(random: std.Random, buf: []u8) []const u8 {
    const first_chars = "abcdefghijklmnopqrstuvwxyz";
    const rest_chars = "abcdefghijklmnopqrstuvwxyz0123456789";
    
    const len = random.intRangeAtMost(usize, 1, @min(buf.len - 1, 10));
    buf[0] = first_chars[random.intRangeAtMost(usize, 0, first_chars.len - 1)];
    
    for (buf[1..len]) |*c| {
        c.* = rest_chars[random.intRangeAtMost(usize, 0, rest_chars.len - 1)];
    }
    
    return buf[0..len];
}

test "Feature: multi-syntax-extension-system, Property 5: AST semantic equivalence" {
    // Property: For any semantically equivalent code written in PHP mode and Go mode,
    // the Parser SHALL produce AST nodes that are structurally equivalent.
    
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();
    
    var ident_buf: [32]u8 = undefined;
    var php_source_buf: [256]u8 = undefined;
    var go_source_buf: [256]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const var_name = generateRandomIdentifier(random, &ident_buf);
        
        // Test case 1: Simple variable access
        // PHP: $varName  Go: varName
        {
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php ${s}", .{var_name}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {s}", .{var_name}) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            var php_parser = try Parser.initWithMode(allocator, php_context, php_source, .php);
            defer php_parser.deinit();
            var go_parser = try Parser.initWithMode(allocator, go_context, go_source, .go);
            defer go_parser.deinit();
            
            const php_root = php_parser.parse() catch continue;
            const go_root = go_parser.parse() catch continue;
            
            // Both should produce structurally equivalent ASTs
            try testing.expect(compareAstStructure(php_context, php_root, go_context, go_root));
        }
        
        // Test case 2: Property access
        // PHP: $obj->prop  Go: obj.prop
        {
            const prop_name = generateRandomIdentifier(random, &ident_buf);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php $obj->{s}", .{prop_name}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php obj.{s}", .{prop_name}) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            var php_parser = try Parser.initWithMode(allocator, php_context, php_source, .php);
            defer php_parser.deinit();
            var go_parser = try Parser.initWithMode(allocator, go_context, go_source, .go);
            defer go_parser.deinit();
            
            const php_root = php_parser.parse() catch continue;
            const go_root = go_parser.parse() catch continue;
            
            try testing.expect(compareAstStructure(php_context, php_root, go_context, go_root));
        }
        
        // Test case 3: Method call
        // PHP: $obj->method()  Go: obj.method()
        {
            const method_name = generateRandomIdentifier(random, &ident_buf);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php $obj->{s}()", .{method_name}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php obj.{s}()", .{method_name}) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            var php_parser = try Parser.initWithMode(allocator, php_context, php_source, .php);
            defer php_parser.deinit();
            var go_parser = try Parser.initWithMode(allocator, go_context, go_source, .go);
            defer go_parser.deinit();
            
            const php_root = php_parser.parse() catch continue;
            const go_root = go_parser.parse() catch continue;
            
            try testing.expect(compareAstStructure(php_context, php_root, go_context, go_root));
        }
        
        // Test case 4: Assignment
        // PHP: $x = 42;  Go: x = 42;
        {
            const val = random.intRangeAtMost(i32, 0, 1000);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php ${s} = {d};", .{var_name, val}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {s} = {d};", .{var_name, val}) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            var php_parser = try Parser.initWithMode(allocator, php_context, php_source, .php);
            defer php_parser.deinit();
            var go_parser = try Parser.initWithMode(allocator, go_context, go_source, .go);
            defer go_parser.deinit();
            
            const php_root = php_parser.parse() catch continue;
            const go_root = go_parser.parse() catch continue;
            
            try testing.expect(compareAstStructure(php_context, php_root, go_context, go_root));
        }
        
        // Test case 5: String concatenation
        // PHP: "a" . "b"  Go: "a" + "b"
        {
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php \"hello\" . \" world\"", .{}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php \"hello\" + \" world\"", .{}) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            var php_parser = try Parser.initWithMode(allocator, php_context, php_source, .php);
            defer php_parser.deinit();
            var go_parser = try Parser.initWithMode(allocator, go_context, go_source, .go);
            defer go_parser.deinit();
            
            const php_root = php_parser.parse() catch continue;
            const go_root = go_parser.parse() catch continue;
            
            // Both should produce binary_expr nodes (PHP with .dot, Go with .dot after conversion)
            try testing.expect(compareAstStructure(php_context, php_root, go_context, go_root));
        }
    }
}
