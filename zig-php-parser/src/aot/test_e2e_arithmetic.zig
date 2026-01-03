//! End-to-End Arithmetic Operation Tests for PHP AOT Compiler
//!
//! **Feature: aot-native-compilation**
//! **Task: 8.2 创建算术运算测试**
//! **Validates: Requirements 5.2**
//!
//! This test suite validates arithmetic operations in AOT compilation:
//! - Addition, subtraction, multiplication, division, modulo
//! - Type conversion in arithmetic operations
//! - Operator precedence

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
const RuntimeLib = @import("runtime_lib.zig");

// ============================================================================
// Test Infrastructure
// ============================================================================

/// Test context for arithmetic tests
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
// Test 8.2.1: Integer Addition
// ============================================================================

test "8.2.1: Integer addition generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.2
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = 10 + 20;
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
        // 3: binary expression 10 + 20
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .plus, .start = 13, .end = 14, .line = 1, .column = 14 },
            .data = .{ .binary_expr = .{ .lhs = 4, .op = .plus, .rhs = 5 } },
        },
        // 4: literal 10
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 12, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = 10 } },
        },
        // 5: literal 20
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 15, .end = 17, .line = 1, .column = 16 },
            .data = .{ .literal_int = .{ .value = 20 } },
        },
    };

    const string_table = [_][]const u8{"result"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_add", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for add instruction or constant folded result (30)
    var found_add_or_result = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .add) {
                    found_add_or_result = true;
                } else if (inst.op == .const_int and inst.op.const_int == 30) {
                    // Constant folding occurred
                    found_add_or_result = true;
                }
            }
        }
    }
    try testing.expect(found_add_or_result);
}

// ============================================================================
// Test 8.2.2: Integer Subtraction
// ============================================================================

test "8.2.2: Integer subtraction generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.2
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = 50 - 30;
    const nodes = [_]Node{
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .minus, .start = 13, .end = 14, .line = 1, .column = 14 },
            .data = .{ .binary_expr = .{ .lhs = 4, .op = .minus, .rhs = 5 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 12, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = 50 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 15, .end = 17, .line = 1, .column = 16 },
            .data = .{ .literal_int = .{ .value = 30 } },
        },
    };

    const string_table = [_][]const u8{"result"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_sub", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    try testing.expect(module.functions.items.len > 0);

    // Check for sub instruction or constant folded result (20)
    var found = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .sub) {
                    found = true;
                } else if (inst.op == .const_int and inst.op.const_int == 20) {
                    found = true;
                }
            }
        }
    }
    try testing.expect(found);
}

// ============================================================================
// Test 8.2.3: Integer Multiplication
// ============================================================================

test "8.2.3: Integer multiplication generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.2
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = 6 * 7;
    const nodes = [_]Node{
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .star, .start = 10, .end = 11, .line = 1, .column = 11 },
            .data = .{ .binary_expr = .{ .lhs = 4, .op = .star, .rhs = 5 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .literal_int = .{ .value = 6 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 12, .end = 13, .line = 1, .column = 13 },
            .data = .{ .literal_int = .{ .value = 7 } },
        },
    };

    const string_table = [_][]const u8{"result"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_mul", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    try testing.expect(module.functions.items.len > 0);

    // Check for mul instruction or constant folded result (42)
    var found = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .mul) {
                    found = true;
                } else if (inst.op == .const_int and inst.op.const_int == 42) {
                    found = true;
                }
            }
        }
    }
    try testing.expect(found);
}

// ============================================================================
// Test 8.2.4: Integer Division
// ============================================================================

test "8.2.4: Integer division generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.2
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = 100 / 5;
    const nodes = [_]Node{
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .slash, .start = 14, .end = 15, .line = 1, .column = 15 },
            .data = .{ .binary_expr = .{ .lhs = 4, .op = .slash, .rhs = 5 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 13, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = 100 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 16, .end = 17, .line = 1, .column = 17 },
            .data = .{ .literal_int = .{ .value = 5 } },
        },
    };

    const string_table = [_][]const u8{"result"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_div", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    try testing.expect(module.functions.items.len > 0);

    // Check for div instruction or constant folded result (20)
    var found = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .div) {
                    found = true;
                } else if (inst.op == .const_int and inst.op.const_int == 20) {
                    found = true;
                }
            }
        }
    }
    try testing.expect(found);
}

// ============================================================================
// Test 8.2.5: Integer Modulo
// ============================================================================

test "8.2.5: Integer modulo generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.2
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = 17 % 5;
    const nodes = [_]Node{
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .percent, .start = 13, .end = 14, .line = 1, .column = 14 },
            .data = .{ .binary_expr = .{ .lhs = 4, .op = .percent, .rhs = 5 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 12, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = 17 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 15, .end = 16, .line = 1, .column = 16 },
            .data = .{ .literal_int = .{ .value = 5 } },
        },
    };

    const string_table = [_][]const u8{"result"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_mod", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    try testing.expect(module.functions.items.len > 0);

    // Check for mod instruction or constant folded result (2)
    var found = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .mod) {
                    found = true;
                } else if (inst.op == .const_int and inst.op.const_int == 2) {
                    found = true;
                }
            }
        }
    }
    try testing.expect(found);
}

// ============================================================================
// Test 8.2.6: Float Arithmetic
// ============================================================================

test "8.2.6: Float arithmetic generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.2
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = 3.14 + 2.86;
    const nodes = [_]Node{
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .plus, .start = 15, .end = 16, .line = 1, .column = 16 },
            .data = .{ .binary_expr = .{ .lhs = 4, .op = .plus, .rhs = 5 } },
        },
        .{
            .tag = .literal_float,
            .main_token = .{ .tag = .float_literal, .start = 10, .end = 14, .line = 1, .column = 11 },
            .data = .{ .literal_float = .{ .value = 3.14 } },
        },
        .{
            .tag = .literal_float,
            .main_token = .{ .tag = .float_literal, .start = 17, .end = 21, .line = 1, .column = 18 },
            .data = .{ .literal_float = .{ .value = 2.86 } },
        },
    };

    const string_table = [_][]const u8{"result"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_float", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    try testing.expect(module.functions.items.len > 0);

    // Check for add instruction or constant folded result (~6.0)
    var found = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .add) {
                    found = true;
                } else if (inst.op == .const_float) {
                    // Check if result is approximately 6.0
                    if (@abs(inst.op.const_float - 6.0) < 0.01) {
                        found = true;
                    }
                }
            }
        }
    }
    try testing.expect(found);
}

// ============================================================================
// Test 8.2.7: Mixed Type Arithmetic (Int + Float)
// ============================================================================

test "8.2.7: Mixed type arithmetic generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.2
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = 10 + 2.5;
    const nodes = [_]Node{
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .plus, .start = 13, .end = 14, .line = 1, .column = 14 },
            .data = .{ .binary_expr = .{ .lhs = 4, .op = .plus, .rhs = 5 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 12, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = 10 } },
        },
        .{
            .tag = .literal_float,
            .main_token = .{ .tag = .float_literal, .start = 15, .end = 18, .line = 1, .column = 16 },
            .data = .{ .literal_float = .{ .value = 2.5 } },
        },
    };

    const string_table = [_][]const u8{"result"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_mixed", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    try testing.expect(module.functions.items.len > 0);

    // Check for add instruction or constant folded result (~12.5)
    var found = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .add) {
                    found = true;
                } else if (inst.op == .const_float) {
                    if (@abs(inst.op.const_float - 12.5) < 0.01) {
                        found = true;
                    }
                }
            }
        }
    }
    try testing.expect(found);
}

// ============================================================================
// Test 8.2.8: Negative Numbers
// ============================================================================

test "8.2.8: Negative number arithmetic generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.2
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $result = -10 + 5;
    const nodes = [_]Node{
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .plus, .start = 14, .end = 15, .line = 1, .column = 15 },
            .data = .{ .binary_expr = .{ .lhs = 4, .op = .plus, .rhs = 5 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 13, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = -10 } },
        },
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 16, .end = 17, .line = 1, .column = 17 },
            .data = .{ .literal_int = .{ .value = 5 } },
        },
    };

    const string_table = [_][]const u8{"result"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_neg", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    try testing.expect(module.functions.items.len > 0);

    // Check for add instruction or constant folded result (-5)
    var found = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .add) {
                    found = true;
                } else if (inst.op == .const_int and inst.op.const_int == -5) {
                    found = true;
                }
            }
        }
    }
    try testing.expect(found);
}
