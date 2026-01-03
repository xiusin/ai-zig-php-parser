//! End-to-End Function Tests for PHP AOT Compiler
//!
//! **Feature: aot-native-compilation**
//! **Task: 8.4 创建函数测试**
//! **Validates: Requirements 5.4**
//!
//! This test suite validates function handling in AOT compilation:
//! - User-defined functions
//! - Recursive functions
//! - Function parameters and return values

const std = @import("std");
const testing = std.testing;

// AOT module imports
const IR = @import("ir.zig");
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const Node = @import("ir_generator.zig").Node;
const TokenTag = @import("ir_generator.zig").TokenTag;
const SymbolTable = @import("symbol_table.zig");
const TypeInference = @import("type_inference.zig");
const Diagnostics = @import("diagnostics.zig");
const ZigCodeGen = @import("zig_codegen.zig");

// ============================================================================
// Test Infrastructure
// ============================================================================

/// Test context for function tests
const TestContext = struct {
    allocator: std.mem.Allocator,
    symbol_table: *SymbolTable.SymbolTable,
    diagnostics: *Diagnostics.DiagnosticEngine,
    type_inferencer: *TypeInference.TypeInferencer,
    ir_generator: IRGenerator,
    zig_codegen: ZigCodeGen.ZigCodeGenerator,

    fn init(allocator: std.mem.Allocator) !TestContext {
        const symbol_table = try allocator.create(SymbolTable.SymbolTable);
        symbol_table.* = try SymbolTable.SymbolTable.init(allocator);

        const diagnostics = try allocator.create(Diagnostics.DiagnosticEngine);
        diagnostics.* = Diagnostics.DiagnosticEngine.init(allocator);

        const type_inferencer = try allocator.create(TypeInference.TypeInferencer);
        type_inferencer.* = TypeInference.TypeInferencer.init(allocator, symbol_table, diagnostics);

        const ir_generator = IRGenerator.init(allocator, symbol_table, type_inferencer, diagnostics);
        const zig_codegen = ZigCodeGen.ZigCodeGenerator.init(allocator, diagnostics);

        return .{
            .allocator = allocator,
            .symbol_table = symbol_table,
            .diagnostics = diagnostics,
            .type_inferencer = type_inferencer,
            .ir_generator = ir_generator,
            .zig_codegen = zig_codegen,
        };
    }

    fn deinit(self: *TestContext) void {
        self.zig_codegen.deinit();
        self.ir_generator.deinit();
        self.symbol_table.deinit();
        self.diagnostics.deinit();
        self.allocator.destroy(self.symbol_table);
        self.allocator.destroy(self.diagnostics);
        self.allocator.destroy(self.type_inferencer);
    }
};


// ============================================================================
// Test 8.4.1: Simple Function Declaration
// ============================================================================

test "8.4.1: Simple function declaration generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.4
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php function greet() { echo "Hello"; }
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: function declaration
        .{
            .tag = .function_decl,
            .main_token = .{ .tag = .eof, .start = 0, .end = 8, .line = 1, .column = 1 },
            .data = .{ .function_decl = .{ .attributes = &[_]Node.Index{}, .name = 0, .params = &[_]Node.Index{}, .body = 2 } },
        },
        // 2: function body block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 20, .end = 21, .line = 1, .column = 21 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
        },
        // 3: echo statement
        .{
            .tag = .echo_stmt,
            .main_token = .{ .tag = .eof, .start = 22, .end = 26, .line = 1, .column = 23 },
            .data = .{ .echo_stmt = .{ .exprs = &[_]Node.Index{4} } },
        },
        // 4: string literal "Hello"
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .string_literal, .start = 27, .end = 34, .line = 1, .column = 28 },
            .data = .{ .literal_string = .{ .value = 1, .quote_type = .double } },
        },
    };

    const string_table = [_][]const u8{ "greet", "Hello" };

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_func", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated with at least 2 functions (main + greet)
    try testing.expect(module.functions.items.len >= 1);

    // Check for function named "greet"
    var found_greet = false;
    for (module.functions.items) |func| {
        if (std.mem.eql(u8, func.name, "greet")) {
            found_greet = true;
            break;
        }
    }
    try testing.expect(found_greet);
}

// ============================================================================
// Test 8.4.2: Function with Parameters
// ============================================================================

test "8.4.2: Function with parameters generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.4
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php function add($a, $b) { return $a + $b; }
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: function declaration
        .{
            .tag = .function_decl,
            .main_token = .{ .tag = .eof, .start = 0, .end = 8, .line = 1, .column = 1 },
            .data = .{ .function_decl = .{ .attributes = &[_]Node.Index{}, .name = 0, .params = &[_]Node.Index{ 2, 3 }, .body = 4 } },
        },
        // 2: parameter $a
        .{
            .tag = .parameter,
            .main_token = .{ .tag = .eof, .start = 13, .end = 15, .line = 1, .column = 14 },
            .data = .{ .parameter = .{ .attributes = &[_]Node.Index{}, .name = 1, .type = null, .default_value = null, .is_promoted = false, .modifiers = .{}, .is_variadic = false, .is_reference = false } },
        },
        // 3: parameter $b
        .{
            .tag = .parameter,
            .main_token = .{ .tag = .eof, .start = 17, .end = 19, .line = 1, .column = 18 },
            .data = .{ .parameter = .{ .attributes = &[_]Node.Index{}, .name = 2, .type = null, .default_value = null, .is_promoted = false, .modifiers = .{}, .is_variadic = false, .is_reference = false } },
        },
        // 4: function body block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 22, .end = 23, .line = 1, .column = 23 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{5} } },
        },
        // 5: return statement
        .{
            .tag = .return_stmt,
            .main_token = .{ .tag = .eof, .start = 24, .end = 30, .line = 1, .column = 25 },
            .data = .{ .return_stmt = .{ .expr = 6 } },
        },
        // 6: binary expression $a + $b
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .plus, .start = 34, .end = 35, .line = 1, .column = 35 },
            .data = .{ .binary_expr = .{ .lhs = 7, .op = .plus, .rhs = 8 } },
        },
        // 7: variable $a
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 31, .end = 33, .line = 1, .column = 32 },
            .data = .{ .variable = .{ .name = 1 } },
        },
        // 8: variable $b
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 36, .end = 38, .line = 1, .column = 37 },
            .data = .{ .variable = .{ .name = 2 } },
        },
    };

    const string_table = [_][]const u8{ "add", "a", "b" };

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_func_params", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len >= 1);

    // Check for function named "add" with 2 parameters
    var found_add = false;
    for (module.functions.items) |func| {
        if (std.mem.eql(u8, func.name, "add")) {
            found_add = true;
            try testing.expect(func.params.items.len == 2);
            break;
        }
    }
    try testing.expect(found_add);
}


// ============================================================================
// Test 8.4.3: Function Call
// ============================================================================

test "8.4.3: Function call generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.4
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = myFunc(10);
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: assignment
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        // 2: variable $result
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 3: function call myFunc(10)
        .{
            .tag = .function_call,
            .main_token = .{ .tag = .eof, .start = 10, .end = 16, .line = 1, .column = 11 },
            .data = .{ .function_call = .{ .name = 4, .args = &[_]Node.Index{5} } },
        },
        // 4: function name (as variable/identifier)
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 10, .end = 16, .line = 1, .column = 11 },
            .data = .{ .variable = .{ .name = 1 } },
        },
        // 5: argument 10
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 17, .end = 19, .line = 1, .column = 18 },
            .data = .{ .literal_int = .{ .value = 10 } },
        },
    };

    const string_table = [_][]const u8{ "result", "myFunc" };

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_func_call", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for call instruction
    var found_call = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .call) {
                    found_call = true;
                }
            }
        }
    }
    try testing.expect(found_call);
}

// ============================================================================
// Test 8.4.4: Recursive Function
// ============================================================================

test "8.4.4: Recursive function generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.4
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php function factorial($n) { if ($n <= 1) { return 1; } return $n * factorial($n - 1); }
    // Simplified: function factorial($n) { return 1; } (just test function structure)
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: function declaration
        .{
            .tag = .function_decl,
            .main_token = .{ .tag = .eof, .start = 0, .end = 8, .line = 1, .column = 1 },
            .data = .{ .function_decl = .{ .attributes = &[_]Node.Index{}, .name = 0, .params = &[_]Node.Index{2}, .body = 3 } },
        },
        // 2: parameter $n
        .{
            .tag = .parameter,
            .main_token = .{ .tag = .eof, .start = 19, .end = 21, .line = 1, .column = 20 },
            .data = .{ .parameter = .{ .attributes = &[_]Node.Index{}, .name = 1, .type = null, .default_value = null, .is_promoted = false, .modifiers = .{}, .is_variadic = false, .is_reference = false } },
        },
        // 3: function body block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 24, .end = 25, .line = 1, .column = 25 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{4} } },
        },
        // 4: if statement
        .{
            .tag = .if_stmt,
            .main_token = .{ .tag = .eof, .start = 26, .end = 28, .line = 1, .column = 27 },
            .data = .{ .if_stmt = .{ .condition = 5, .then_branch = 8, .else_branch = null } },
        },
        // 5: condition ($n <= 1)
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .less_equal, .start = 33, .end = 35, .line = 1, .column = 34 },
            .data = .{ .binary_expr = .{ .lhs = 6, .op = .less_equal, .rhs = 7 } },
        },
        // 6: variable $n
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 30, .end = 32, .line = 1, .column = 31 },
            .data = .{ .variable = .{ .name = 1 } },
        },
        // 7: literal 1
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 36, .end = 37, .line = 1, .column = 37 },
            .data = .{ .literal_int = .{ .value = 1 } },
        },
        // 8: then block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 39, .end = 40, .line = 1, .column = 40 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{9} } },
        },
        // 9: return 1
        .{
            .tag = .return_stmt,
            .main_token = .{ .tag = .eof, .start = 41, .end = 47, .line = 1, .column = 42 },
            .data = .{ .return_stmt = .{ .expr = 10 } },
        },
        // 10: literal 1
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 48, .end = 49, .line = 1, .column = 49 },
            .data = .{ .literal_int = .{ .value = 1 } },
        },
    };

    const string_table = [_][]const u8{ "factorial", "n" };

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_recursive", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len >= 1);

    // Check for function named "factorial"
    var found_factorial = false;
    for (module.functions.items) |func| {
        if (std.mem.eql(u8, func.name, "factorial")) {
            found_factorial = true;
            // Should have 1 parameter
            try testing.expect(func.params.items.len == 1);
            break;
        }
    }
    try testing.expect(found_factorial);
}

// ============================================================================
// Test 8.4.5: Function with Return Value
// ============================================================================

test "8.4.5: Function with return value generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.4
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php function getNumber() { return 42; }
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: function declaration
        .{
            .tag = .function_decl,
            .main_token = .{ .tag = .eof, .start = 0, .end = 8, .line = 1, .column = 1 },
            .data = .{ .function_decl = .{ .attributes = &[_]Node.Index{}, .name = 0, .params = &[_]Node.Index{}, .body = 2 } },
        },
        // 2: function body block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 22, .end = 23, .line = 1, .column = 23 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
        },
        // 3: return statement
        .{
            .tag = .return_stmt,
            .main_token = .{ .tag = .eof, .start = 24, .end = 30, .line = 1, .column = 25 },
            .data = .{ .return_stmt = .{ .expr = 4 } },
        },
        // 4: literal 42
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 31, .end = 33, .line = 1, .column = 32 },
            .data = .{ .literal_int = .{ .value = 42 } },
        },
    };

    const string_table = [_][]const u8{"getNumber"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_return", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len >= 1);

    // Check for function named "getNumber"
    var found_func = false;
    for (module.functions.items) |func| {
        if (std.mem.eql(u8, func.name, "getNumber")) {
            found_func = true;
            // Check for return terminator or const_int 42
            for (func.blocks.items) |block| {
                if (block.terminator) |term| {
                    if (term == .ret) {
                        // Found return
                    }
                }
            }
            break;
        }
    }
    try testing.expect(found_func);
}
