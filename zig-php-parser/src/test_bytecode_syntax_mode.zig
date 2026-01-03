/// Property-Based Tests for Bytecode Generation Syntax Mode Independence
/// 
/// Property 7: Bytecode generation equivalence
/// *For any* semantically equivalent AST nodes (regardless of original syntax mode),
/// the Bytecode Generator SHALL produce identical bytecode sequences.
/// **Validates: Requirements 5.1, 5.2, 5.3**
const std = @import("std");
const testing = std.testing;

// Import compiler modules
const Parser = @import("compiler/parser.zig").Parser;
const PHPContext = @import("compiler/root.zig").PHPContext;
const SyntaxMode = @import("compiler/syntax_mode.zig").SyntaxMode;
const ast = @import("compiler/ast.zig");

// Import bytecode modules
const BytecodeGenerator = @import("bytecode/generator.zig").BytecodeGenerator;
const instruction = @import("bytecode/instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;
const CompiledFunction = instruction.CompiledFunction;

// ============================================================================
// Helper Functions
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

/// Parse source code with the specified syntax mode and return the AST root
fn parseSource(allocator: std.mem.Allocator, context: *PHPContext, source: [:0]const u8, mode: SyntaxMode) !ast.Node.Index {
    var parser = try Parser.initWithMode(allocator, context, source, mode);
    defer parser.deinit();
    return try parser.parse();
}

/// Generate bytecode from AST and return the compiled function
fn generateBytecode(allocator: std.mem.Allocator, context: *PHPContext, root_index: ast.Node.Index) !*CompiledFunction {
    var gen = BytecodeGenerator.init(allocator, context);
    defer gen.deinit();
    return try gen.compile(root_index);
}

/// Compare two bytecode sequences for equality
fn bytecodeEqual(bc1: []const Instruction, bc2: []const Instruction) bool {
    if (bc1.len != bc2.len) return false;
    
    for (bc1, bc2) |inst1, inst2| {
        if (inst1.opcode != inst2.opcode) return false;
        if (inst1.operand1 != inst2.operand1) return false;
        if (inst1.operand2 != inst2.operand2) return false;
    }
    
    return true;
}

/// Compare two constant pools for equality
fn constantsEqual(c1: []const instruction.Value, c2: []const instruction.Value) bool {
    if (c1.len != c2.len) return false;
    
    for (c1, c2) |val1, val2| {
        if (!valueEqual(val1, val2)) return false;
    }
    
    return true;
}

/// Compare two constant values for equality
fn valueEqual(v1: instruction.Value, v2: instruction.Value) bool {
    return switch (v1) {
        .int_val => |int1| switch (v2) {
            .int_val => |int2| int1 == int2,
            else => false,
        },
        .float_val => |flt1| switch (v2) {
            .float_val => |flt2| flt1 == flt2,
            else => false,
        },
        .string_val => |str1| switch (v2) {
            .string_val => |str2| std.mem.eql(u8, str1, str2),
            else => false,
        },
        .bool_val => |bool1| switch (v2) {
            .bool_val => |bool2| bool1 == bool2,
            else => false,
        },
        .null_val => switch (v2) {
            .null_val => true,
            else => false,
        },
        .array_val => |arr1| switch (v2) {
            .array_val => |arr2| arr1 == arr2, // Pointer comparison
            else => false,
        },
        .class_ref => |ref1| switch (v2) {
            .class_ref => |ref2| ref1 == ref2,
            else => false,
        },
        .func_ref => |ref1| switch (v2) {
            .func_ref => |ref2| ref1 == ref2,
            else => false,
        },
    };
}

/// Free a compiled function
fn freeCompiledFunction(allocator: std.mem.Allocator, func: *CompiledFunction) void {
    allocator.free(func.bytecode);
    allocator.free(func.constants);
    allocator.destroy(func);
}

// ============================================================================
// Property 7: Bytecode Generation Equivalence
// *For any* semantically equivalent AST nodes (regardless of original syntax mode),
// the Bytecode Generator SHALL produce identical bytecode sequences.
// **Validates: Requirements 5.1, 5.2, 5.3**
// ============================================================================

test "Feature: multi-syntax-extension-system, Property 7: Bytecode generation equivalence" {
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();
    
    var php_source_buf: [512]u8 = undefined;
    var go_source_buf: [512]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // Test case 1: Integer literals produce identical bytecode
        {
            const val = random.intRangeAtMost(i32, -1000, 1000);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d};", .{val}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d};", .{val}) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            // Bytecode should be identical
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
            try testing.expect(constantsEqual(php_bytecode.constants, go_bytecode.constants));
        }
        
        // Test case 2: Float literals produce identical bytecode
        {
            const val = @as(f64, @floatFromInt(random.intRangeAtMost(i32, -1000, 1000))) / 10.0;
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d:.1};", .{val}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d:.1};", .{val}) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
        
        // Test case 3: Boolean literals produce identical bytecode
        {
            const val = random.boolean();
            const val_str = if (val) "true" else "false";
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {s};", .{val_str}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {s};", .{val_str}) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
        
        // Test case 4: Null literal produces identical bytecode
        {
            const php_source: [:0]const u8 = "<?php null;";
            const go_source: [:0]const u8 = "<?php null;";
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
        
        // Test case 5: Arithmetic expressions produce identical bytecode
        {
            const a = random.intRangeAtMost(i32, 1, 100);
            const b = random.intRangeAtMost(i32, 1, 100);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d} + {d};", .{ a, b }) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d} + {d};", .{ a, b }) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
        
        // Test case 6: Multiplication expressions produce identical bytecode
        {
            const a = random.intRangeAtMost(i32, 1, 50);
            const b = random.intRangeAtMost(i32, 1, 50);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d} * {d};", .{ a, b }) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d} * {d};", .{ a, b }) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
        
        // Test case 7: Comparison expressions produce identical bytecode
        {
            const a = random.intRangeAtMost(i32, 1, 100);
            const b = random.intRangeAtMost(i32, 1, 100);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d} < {d};", .{ a, b }) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d} < {d};", .{ a, b }) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
        
        // Test case 8: Logical expressions produce identical bytecode
        {
            const a = random.boolean();
            const b = random.boolean();
            const a_str = if (a) "true" else "false";
            const b_str = if (b) "true" else "false";
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {s} && {s};", .{ a_str, b_str }) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {s} && {s};", .{ a_str, b_str }) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
        
        // Test case 9: Complex arithmetic expressions produce identical bytecode
        {
            const a = random.intRangeAtMost(i32, 1, 50);
            const b = random.intRangeAtMost(i32, 1, 50);
            const c = random.intRangeAtMost(i32, 1, 50);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php ({d} + {d}) * {d};", .{ a, b, c }) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php ({d} + {d}) * {d};", .{ a, b, c }) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
        
        // Test case 10: Subtraction expressions produce identical bytecode
        {
            const a = random.intRangeAtMost(i32, 50, 100);
            const b = random.intRangeAtMost(i32, 1, 50);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d} - {d};", .{ a, b }) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d} - {d};", .{ a, b }) catch continue;
            
            const php_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, php_context);
            
            const go_context = try createTestContext(allocator);
            defer destroyTestContext(allocator, go_context);
            
            const php_ast = parseSource(allocator, php_context, php_source, .php) catch continue;
            const go_ast = parseSource(allocator, go_context, go_source, .go) catch continue;
            
            const php_bytecode = generateBytecode(allocator, php_context, php_ast) catch continue;
            defer freeCompiledFunction(allocator, php_bytecode);
            
            const go_bytecode = generateBytecode(allocator, go_context, go_ast) catch continue;
            defer freeCompiledFunction(allocator, go_bytecode);
            
            try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
        }
    }
}

// ============================================================================
// Unit Tests for Bytecode Equivalence
// ============================================================================

test "bytecode equivalence - integer literal" {
    const allocator = testing.allocator;
    
    const php_source: [:0]const u8 = "<?php 42;";
    const go_source: [:0]const u8 = "<?php 42;";
    
    const php_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, php_context);
    
    const go_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, go_context);
    
    const php_ast = try parseSource(allocator, php_context, php_source, .php);
    const go_ast = try parseSource(allocator, go_context, go_source, .go);
    
    const php_bytecode = try generateBytecode(allocator, php_context, php_ast);
    defer freeCompiledFunction(allocator, php_bytecode);
    
    const go_bytecode = try generateBytecode(allocator, go_context, go_ast);
    defer freeCompiledFunction(allocator, go_bytecode);
    
    try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
    try testing.expectEqual(php_bytecode.local_count, go_bytecode.local_count);
}

test "bytecode equivalence - boolean literal" {
    const allocator = testing.allocator;
    
    const php_source: [:0]const u8 = "<?php true;";
    const go_source: [:0]const u8 = "<?php true;";
    
    const php_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, php_context);
    
    const go_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, go_context);
    
    const php_ast = try parseSource(allocator, php_context, php_source, .php);
    const go_ast = try parseSource(allocator, go_context, go_source, .go);
    
    const php_bytecode = try generateBytecode(allocator, php_context, php_ast);
    defer freeCompiledFunction(allocator, php_bytecode);
    
    const go_bytecode = try generateBytecode(allocator, go_context, go_ast);
    defer freeCompiledFunction(allocator, go_bytecode);
    
    try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
}

test "bytecode equivalence - null literal" {
    const allocator = testing.allocator;
    
    const php_source: [:0]const u8 = "<?php null;";
    const go_source: [:0]const u8 = "<?php null;";
    
    const php_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, php_context);
    
    const go_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, go_context);
    
    const php_ast = try parseSource(allocator, php_context, php_source, .php);
    const go_ast = try parseSource(allocator, go_context, go_source, .go);
    
    const php_bytecode = try generateBytecode(allocator, php_context, php_ast);
    defer freeCompiledFunction(allocator, php_bytecode);
    
    const go_bytecode = try generateBytecode(allocator, go_context, go_ast);
    defer freeCompiledFunction(allocator, go_bytecode);
    
    try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
}

test "bytecode equivalence - arithmetic expression" {
    const allocator = testing.allocator;
    
    const php_source: [:0]const u8 = "<?php 5 + 3;";
    const go_source: [:0]const u8 = "<?php 5 + 3;";
    
    const php_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, php_context);
    
    const go_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, go_context);
    
    const php_ast = try parseSource(allocator, php_context, php_source, .php);
    const go_ast = try parseSource(allocator, go_context, go_source, .go);
    
    const php_bytecode = try generateBytecode(allocator, php_context, php_ast);
    defer freeCompiledFunction(allocator, php_bytecode);
    
    const go_bytecode = try generateBytecode(allocator, go_context, go_ast);
    defer freeCompiledFunction(allocator, go_bytecode);
    
    try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
}

test "bytecode equivalence - comparison expression" {
    const allocator = testing.allocator;
    
    const php_source: [:0]const u8 = "<?php 5 < 10;";
    const go_source: [:0]const u8 = "<?php 5 < 10;";
    
    const php_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, php_context);
    
    const go_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, go_context);
    
    const php_ast = try parseSource(allocator, php_context, php_source, .php);
    const go_ast = try parseSource(allocator, go_context, go_source, .go);
    
    const php_bytecode = try generateBytecode(allocator, php_context, php_ast);
    defer freeCompiledFunction(allocator, php_bytecode);
    
    const go_bytecode = try generateBytecode(allocator, go_context, go_ast);
    defer freeCompiledFunction(allocator, go_bytecode);
    
    try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
}

test "bytecode equivalence - logical expression" {
    const allocator = testing.allocator;
    
    const php_source: [:0]const u8 = "<?php true && false;";
    const go_source: [:0]const u8 = "<?php true && false;";
    
    const php_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, php_context);
    
    const go_context = try createTestContext(allocator);
    defer destroyTestContext(allocator, go_context);
    
    const php_ast = try parseSource(allocator, php_context, php_source, .php);
    const go_ast = try parseSource(allocator, go_context, go_source, .go);
    
    const php_bytecode = try generateBytecode(allocator, php_context, php_ast);
    defer freeCompiledFunction(allocator, php_bytecode);
    
    const go_bytecode = try generateBytecode(allocator, go_context, go_ast);
    defer freeCompiledFunction(allocator, go_bytecode);
    
    try testing.expect(bytecodeEqual(php_bytecode.bytecode, go_bytecode.bytecode));
}
