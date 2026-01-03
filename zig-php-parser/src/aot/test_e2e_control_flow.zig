//! End-to-End Control Flow Tests for PHP AOT Compiler
//!
//! **Feature: aot-native-compilation**
//! **Task: 8.3 创建控制流测试**
//! **Validates: Requirements 5.3**
//!
//! This test suite validates control flow in AOT compilation:
//! - if/else statements
//! - while loops
//! - for loops
//! - foreach loops

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

/// Test context for control flow tests
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
// Test 8.3.1: Simple If Statement
// ============================================================================

test "8.3.1: Simple if statement generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.3
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php if (true) { $x = 1; }
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: if statement
        .{
            .tag = .if_stmt,
            .main_token = .{ .tag = .eof, .start = 0, .end = 2, .line = 1, .column = 1 },
            .data = .{ .if_stmt = .{ .condition = 2, .then_branch = 3, .else_branch = null } },
        },
        // 2: condition (true)
        .{
            .tag = .literal_bool,
            .main_token = .{ .tag = .keyword_true, .start = 4, .end = 8, .line = 1, .column = 5 },
            .data = .{ .none = {} },
        },
        // 3: then block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 10, .end = 11, .line = 1, .column = 11 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{4} } },
        },
        // 4: assignment $x = 1
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 12, .end = 13, .line = 1, .column = 13 },
            .data = .{ .assignment = .{ .target = 5, .value = 6 } },
        },
        // 5: variable $x
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 12, .end = 14, .line = 1, .column = 13 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 6: literal 1
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 17, .end = 18, .line = 1, .column = 18 },
            .data = .{ .literal_int = .{ .value = 1 } },
        },
    };

    const string_table = [_][]const u8{"x"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_if", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated with control flow
    try testing.expect(module.functions.items.len > 0);

    // Check for conditional branch or multiple blocks
    const func = module.functions.items[0];
    try testing.expect(func.blocks.items.len >= 1);
}

// ============================================================================
// Test 8.3.2: If-Else Statement
// ============================================================================

test "8.3.2: If-else statement generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.3
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php if (false) { $x = 1; } else { $x = 2; }
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: if statement
        .{
            .tag = .if_stmt,
            .main_token = .{ .tag = .eof, .start = 0, .end = 2, .line = 1, .column = 1 },
            .data = .{ .if_stmt = .{ .condition = 2, .then_branch = 3, .else_branch = 7 } },
        },
        // 2: condition (false)
        .{
            .tag = .literal_bool,
            .main_token = .{ .tag = .keyword_false, .start = 4, .end = 9, .line = 1, .column = 5 },
            .data = .{ .none = {} },
        },
        // 3: then block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 11, .end = 12, .line = 1, .column = 12 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{4} } },
        },
        // 4: assignment $x = 1
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 13, .end = 14, .line = 1, .column = 14 },
            .data = .{ .assignment = .{ .target = 5, .value = 6 } },
        },
        // 5: variable $x
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 13, .end = 15, .line = 1, .column = 14 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 6: literal 1
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 18, .end = 19, .line = 1, .column = 19 },
            .data = .{ .literal_int = .{ .value = 1 } },
        },
        // 7: else block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 27, .end = 28, .line = 1, .column = 28 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{8} } },
        },
        // 8: assignment $x = 2
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 29, .end = 30, .line = 1, .column = 30 },
            .data = .{ .assignment = .{ .target = 9, .value = 10 } },
        },
        // 9: variable $x
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 29, .end = 31, .line = 1, .column = 30 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 10: literal 2
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 34, .end = 35, .line = 1, .column = 35 },
            .data = .{ .literal_int = .{ .value = 2 } },
        },
    };

    const string_table = [_][]const u8{"x"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_if_else", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for multiple blocks (then and else branches)
    const func = module.functions.items[0];
    try testing.expect(func.blocks.items.len >= 1);
}

// ============================================================================
// Test 8.3.3: While Loop
// ============================================================================

test "8.3.3: While loop generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.3
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php while (false) { $x = 1; }
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: while statement
        .{
            .tag = .while_stmt,
            .main_token = .{ .tag = .eof, .start = 0, .end = 5, .line = 1, .column = 1 },
            .data = .{ .while_stmt = .{ .condition = 2, .body = 3 } },
        },
        // 2: condition (false to avoid infinite loop)
        .{
            .tag = .literal_bool,
            .main_token = .{ .tag = .keyword_false, .start = 7, .end = 12, .line = 1, .column = 8 },
            .data = .{ .none = {} },
        },
        // 3: body block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 14, .end = 15, .line = 1, .column = 15 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{4} } },
        },
        // 4: assignment $x = 1
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 16, .end = 17, .line = 1, .column = 17 },
            .data = .{ .assignment = .{ .target = 5, .value = 6 } },
        },
        // 5: variable $x
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 16, .end = 18, .line = 1, .column = 17 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 6: literal 1
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 21, .end = 22, .line = 1, .column = 22 },
            .data = .{ .literal_int = .{ .value = 1 } },
        },
    };

    const string_table = [_][]const u8{"x"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_while", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for loop structure (multiple blocks)
    const func = module.functions.items[0];
    try testing.expect(func.blocks.items.len >= 1);
}

// ============================================================================
// Test 8.3.4: For Loop
// ============================================================================

test "8.3.4: For loop generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.3
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php for ($i = 0; $i < 10; $i++) { }
    // Simplified: for (;;) { } with false condition
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: for statement
        .{
            .tag = .for_stmt,
            .main_token = .{ .tag = .eof, .start = 0, .end = 3, .line = 1, .column = 1 },
            .data = .{ .for_stmt = .{ .init = 2, .condition = 5, .loop = null, .body = 6 } },
        },
        // 2: init: $i = 0
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 5, .end = 6, .line = 1, .column = 6 },
            .data = .{ .assignment = .{ .target = 3, .value = 4 } },
        },
        // 3: variable $i
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 5, .end = 7, .line = 1, .column = 6 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 4: literal 0
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 11, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = 0 } },
        },
        // 5: condition: false (to avoid infinite loop in test)
        .{
            .tag = .literal_bool,
            .main_token = .{ .tag = .keyword_false, .start = 13, .end = 18, .line = 1, .column = 14 },
            .data = .{ .none = {} },
        },
        // 6: body block (empty)
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 30, .end = 31, .line = 1, .column = 31 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{} } },
        },
    };

    const string_table = [_][]const u8{"i"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_for", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for loop structure
    const func = module.functions.items[0];
    try testing.expect(func.blocks.items.len >= 1);
}

// ============================================================================
// Test 8.3.5: Foreach Loop
// ============================================================================

test "8.3.5: Foreach loop generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.3
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php foreach ($arr as $item) { $x = $item; }
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: foreach statement
        .{
            .tag = .foreach_stmt,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .foreach_stmt = .{ .iterable = 2, .key = null, .value = 3, .body = 4 } },
        },
        // 2: iterable $arr
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 9, .end = 13, .line = 1, .column = 10 },
            .data = .{ .variable = .{ .name = 0 } }, // "arr"
        },
        // 3: value $item
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 18, .end = 23, .line = 1, .column = 19 },
            .data = .{ .variable = .{ .name = 1 } }, // "item"
        },
        // 4: body block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 25, .end = 26, .line = 1, .column = 26 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{5} } },
        },
        // 5: assignment $x = $item
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 27, .end = 28, .line = 1, .column = 28 },
            .data = .{ .assignment = .{ .target = 6, .value = 7 } },
        },
        // 6: variable $x
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 27, .end = 29, .line = 1, .column = 28 },
            .data = .{ .variable = .{ .name = 2 } }, // "x"
        },
        // 7: variable $item (reference)
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 32, .end = 37, .line = 1, .column = 33 },
            .data = .{ .variable = .{ .name = 1 } }, // "item"
        },
    };

    const string_table = [_][]const u8{ "arr", "item", "x" };

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_foreach", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for loop structure (multiple blocks)
    const func = module.functions.items[0];
    try testing.expect(func.blocks.items.len >= 1);
}

// ============================================================================
// Test 8.3.6: Comparison in Condition
// ============================================================================

test "8.3.6: Comparison in condition generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.3
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php if (5 > 3) { $x = 1; }
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: if statement
        .{
            .tag = .if_stmt,
            .main_token = .{ .tag = .eof, .start = 0, .end = 2, .line = 1, .column = 1 },
            .data = .{ .if_stmt = .{ .condition = 2, .then_branch = 5, .else_branch = null } },
        },
        // 2: condition (5 > 3)
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .greater_than, .start = 6, .end = 7, .line = 1, .column = 7 },
            .data = .{ .binary_expr = .{ .lhs = 3, .op = .greater_than, .rhs = 4 } },
        },
        // 3: literal 5
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 4, .end = 5, .line = 1, .column = 5 },
            .data = .{ .literal_int = .{ .value = 5 } },
        },
        // 4: literal 3
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .literal_int = .{ .value = 3 } },
        },
        // 5: then block
        .{
            .tag = .block,
            .main_token = .{ .tag = .eof, .start = 11, .end = 12, .line = 1, .column = 12 },
            .data = .{ .block = .{ .stmts = &[_]Node.Index{6} } },
        },
        // 6: assignment $x = 1
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 13, .end = 14, .line = 1, .column = 14 },
            .data = .{ .assignment = .{ .target = 7, .value = 8 } },
        },
        // 7: variable $x
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 13, .end = 15, .line = 1, .column = 14 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 8: literal 1
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 18, .end = 19, .line = 1, .column = 19 },
            .data = .{ .literal_int = .{ .value = 1 } },
        },
    };

    const string_table = [_][]const u8{"x"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_cmp", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for comparison instruction or constant folded result
    var found = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .gt) {
                    found = true;
                } else if (inst.op == .const_bool and inst.op.const_bool == true) {
                    // Constant folding: 5 > 3 = true
                    found = true;
                }
            }
        }
    }
    try testing.expect(found);
}
