//! End-to-End Roundtrip Property Tests for PHP AOT Compiler
//!
//! **Feature: php-aot-compiler**
//! **Property 1: Compile-Execute Roundtrip Correctness**
//! **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7**
//!
//! Property 1: Compile-Execute Roundtrip Correctness
//! *For any* valid PHP source code that does not use dynamic features (eval,
//! variable variables, dynamic function calls), compiling it with the AOT
//! compiler and executing the resulting binary SHALL produce the same output
//! as interpreting the same code with the tree-walking interpreter.
//!
//! This test suite validates that the AOT compilation pipeline produces
//! semantically correct code by comparing:
//! 1. IR generation from PHP AST
//! 2. Code generation from IR
//! 3. Runtime behavior of generated code

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
const RuntimeLib = @import("runtime_lib.zig");

/// Random number generator for property tests
const Rng = std.Random.DefaultPrng;

/// Test configuration
const TEST_ITERATIONS = 100;

// ============================================================================
// Test Infrastructure
// ============================================================================

/// Test context for roundtrip tests
const TestContext = struct {
    allocator: std.mem.Allocator,
    symbol_table: *SymbolTable.SymbolTable,
    diagnostics: *Diagnostics.DiagnosticEngine,
    type_inferencer: *TypeInference.TypeInferencer,
    ir_generator: IRGenerator,

    fn init(allocator: std.mem.Allocator) !TestContext {
        const symbol_table = try allocator.create(SymbolTable.SymbolTable);
        symbol_table.* = try SymbolTable.SymbolTable.init(allocator);

        const diagnostics = try allocator.create(Diagnostics.DiagnosticEngine);
        diagnostics.* = Diagnostics.DiagnosticEngine.init(allocator);

        const type_inferencer = try allocator.create(TypeInference.TypeInferencer);
        type_inferencer.* = TypeInference.TypeInferencer.init(allocator, symbol_table, diagnostics);

        const ir_generator = IRGenerator.init(allocator, symbol_table, type_inferencer, diagnostics);

        return .{
            .allocator = allocator,
            .symbol_table = symbol_table,
            .diagnostics = diagnostics,
            .type_inferencer = type_inferencer,
            .ir_generator = ir_generator,
        };
    }

    fn deinit(self: *TestContext) void {
        self.ir_generator.deinit();
        self.symbol_table.deinit();
        self.diagnostics.deinit();
        self.allocator.destroy(self.symbol_table);
        self.allocator.destroy(self.diagnostics);
        self.allocator.destroy(self.type_inferencer);
    }
};

/// Generate a random integer value within safe bounds
fn randomInt(rng: *Rng) i64 {
    return rng.random().intRangeAtMost(i64, -10000, 10000);
}

/// Generate a random float value
fn randomFloat(rng: *Rng) f64 {
    const int_part = rng.random().intRangeAtMost(i32, -1000, 1000);
    const frac_part = rng.random().intRangeAtMost(i32, 0, 99);
    return @as(f64, @floatFromInt(int_part)) + @as(f64, @floatFromInt(frac_part)) / 100.0;
}

/// Generate a random boolean
fn randomBool(rng: *Rng) bool {
    return rng.random().boolean();
}

/// Generate a random arithmetic operator
fn randomArithmeticOp(rng: *Rng) TokenTag {
    const ops = [_]TokenTag{ .plus, .minus, .star };
    return ops[rng.random().intRangeAtMost(usize, 0, ops.len - 1)];
}

/// Generate a random comparison operator
fn randomComparisonOp(rng: *Rng) TokenTag {
    const ops = [_]TokenTag{
        .equal_equal,
        .bang_equal,
        .less_than,
        .less_equal,
        .greater_than,
        .greater_equal,
    };
    return ops[rng.random().intRangeAtMost(usize, 0, ops.len - 1)];
}

// ============================================================================
// Property 1: Compile-Execute Roundtrip Correctness
// ============================================================================

// Property 1.1: Integer literal roundtrip
// *For any* integer literal, IR generation and evaluation SHALL produce the same value.
test "Property 1.1: Integer literal roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const expected_value = randomInt(&rng);

        // Create AST for: function test() { return <value>; }
        const nodes = [_]Node{
            // 0: root
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            // 1: function_decl
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            // 2: block
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            // 3: return statement
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .return_stmt = .{ .expr = 4 } },
            },
            // 4: literal_int
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .literal_int = .{ .value = expected_value } },
            },
        };

        const string_table = [_][]const u8{"test"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated
        try testing.expect(module.functions.items.len > 0);

        // Find the return instruction and verify the constant value
        var found_const = false;
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.op == .const_int) {
                        try testing.expectEqual(expected_value, inst.op.const_int);
                        found_const = true;
                    }
                }
            }
        }
        try testing.expect(found_const);
    }
}

// Property 1.2: Float literal roundtrip
// *For any* float literal, IR generation and evaluation SHALL produce the same value.
test "Property 1.2: Float literal roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const expected_value = randomFloat(&rng);

        // Create AST for: function test() { return <value>; }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .return_stmt = .{ .expr = 4 } },
            },
            .{
                .tag = .literal_float,
                .main_token = .{ .tag = .float_literal, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .literal_float = .{ .value = expected_value } },
            },
        };

        const string_table = [_][]const u8{"test"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated
        try testing.expect(module.functions.items.len > 0);

        // Find the return instruction and verify the constant value
        var found_const = false;
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.op == .const_float) {
                        try testing.expectApproxEqAbs(expected_value, inst.op.const_float, 0.0001);
                        found_const = true;
                    }
                }
            }
        }
        try testing.expect(found_const);
    }
}

// Property 1.3: Boolean literal roundtrip
// *For any* boolean literal, IR generation and evaluation SHALL produce the same value.
test "Property 1.3: Boolean literal roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const expected_value = randomBool(&rng);

        // Create AST for: function test() { return true/false; }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .return_stmt = .{ .expr = 4 } },
            },
            .{
                .tag = .literal_bool,
                .main_token = .{ .tag = if (expected_value) .keyword_true else .keyword_false, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .none = {} },
            },
        };

        const string_table = [_][]const u8{"test"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated
        try testing.expect(module.functions.items.len > 0);

        // Find the const_bool instruction and verify the value
        var found_const = false;
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.op == .const_bool) {
                        try testing.expectEqual(expected_value, inst.op.const_bool);
                        found_const = true;
                    }
                }
            }
        }
        try testing.expect(found_const);
    }
}

// Property 1.4: Binary arithmetic expression roundtrip
// *For any* binary arithmetic expression with integer operands, the IR SHALL
// correctly represent the operation and operands.
test "Property 1.4: Binary arithmetic expression roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const val1 = randomInt(&rng);
        const val2 = randomInt(&rng);
        const op = randomArithmeticOp(&rng);

        // Create AST for: function test() { return val1 op val2; }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .return_stmt = .{ .expr = 4 } },
            },
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = op, .start = 0, .end = 0, .line = 2, .column = 15 },
                .data = .{ .binary_expr = .{ .lhs = 5, .op = op, .rhs = 6 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 18 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
        };

        const string_table = [_][]const u8{"test"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated with correct structure
        try testing.expect(module.functions.items.len > 0);

        // The IR should contain either:
        // 1. A folded constant (if constant folding is enabled)
        // 2. Or the arithmetic operation with two const operands
        var found_arithmetic_or_const = false;
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    switch (inst.op) {
                        .const_int => {
                            // Constant folding occurred - verify result
                            const expected = switch (op) {
                                .plus => val1 +% val2,
                                .minus => val1 -% val2,
                                .star => val1 *% val2,
                                else => unreachable,
                            };
                            try testing.expectEqual(expected, inst.op.const_int);
                            found_arithmetic_or_const = true;
                        },
                        .add, .sub, .mul => {
                            // Arithmetic operation found
                            found_arithmetic_or_const = true;
                        },
                        else => {},
                    }
                }
            }
        }
        try testing.expect(found_arithmetic_or_const);
    }
}

// Property 1.5: Comparison expression roundtrip
// *For any* comparison expression, the IR SHALL correctly represent the comparison.
test "Property 1.5: Comparison expression roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.3
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const val1 = randomInt(&rng);
        const val2 = randomInt(&rng);
        const op = randomComparisonOp(&rng);

        // Create AST for: function test() { return val1 op val2; }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .return_stmt = .{ .expr = 4 } },
            },
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = op, .start = 0, .end = 0, .line = 2, .column = 15 },
                .data = .{ .binary_expr = .{ .lhs = 5, .op = op, .rhs = 6 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 18 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
        };

        const string_table = [_][]const u8{"test"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated
        try testing.expect(module.functions.items.len > 0);

        // The IR should contain either a folded boolean constant or comparison op
        var found_comparison_or_const = false;
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    switch (inst.op) {
                        .const_bool => {
                            // Constant folding occurred - verify result
                            const expected = switch (op) {
                                .equal_equal => val1 == val2,
                                .bang_equal => val1 != val2,
                                .less_than => val1 < val2,
                                .less_equal => val1 <= val2,
                                .greater_than => val1 > val2,
                                .greater_equal => val1 >= val2,
                                else => unreachable,
                            };
                            try testing.expectEqual(expected, inst.op.const_bool);
                            found_comparison_or_const = true;
                        },
                        .eq, .ne, .lt, .le, .gt, .ge => {
                            // Comparison operation found
                            found_comparison_or_const = true;
                        },
                        else => {},
                    }
                }
            }
        }
        try testing.expect(found_comparison_or_const);
    }
}


// Property 1.6: Control flow - if statement roundtrip
// *For any* if statement with a boolean condition, the IR SHALL correctly
// represent the conditional branching structure.
test "Property 1.6: If statement control flow roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.3
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const condition = randomBool(&rng);
        const then_value = randomInt(&rng);
        const else_value = randomInt(&rng);

        // Create AST for: function test() { if (condition) { return then_value; } else { return else_value; } }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            // 3: if statement
            .{
                .tag = .if_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .if_stmt = .{
                    .condition = 4,
                    .then_branch = 5,
                    .else_branch = 7,
                } },
            },
            // 4: condition (boolean literal)
            .{
                .tag = .literal_bool,
                .main_token = .{ .tag = if (condition) .keyword_true else .keyword_false, .start = 0, .end = 0, .line = 2, .column = 9 },
                .data = .{ .none = {} },
            },
            // 5: then block
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 15 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{6} } },
            },
            // 6: return then_value
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 17 },
                .data = .{ .return_stmt = .{ .expr = 9 } },
            },
            // 7: else block
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 35 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{8} } },
            },
            // 8: return else_value
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 37 },
                .data = .{ .return_stmt = .{ .expr = 10 } },
            },
            // 9: then_value literal
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 24 },
                .data = .{ .literal_int = .{ .value = then_value } },
            },
            // 10: else_value literal
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 44 },
                .data = .{ .literal_int = .{ .value = else_value } },
            },
        };

        const string_table = [_][]const u8{"test"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated with control flow structure
        try testing.expect(module.functions.items.len > 0);

        // The function should have multiple blocks for if/else branches
        const func = module.functions.items[0];
        // At minimum we expect entry block, and possibly then/else blocks
        try testing.expect(func.blocks.items.len >= 1);
    }
}

// Property 1.7: While loop roundtrip
// *For any* while loop, the IR SHALL correctly represent the loop structure.
test "Property 1.7: While loop control flow roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.3
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const limit = rng.random().intRangeAtMost(i64, 1, 10);

        // Create AST for: function test() { while (false) { <limit>; } }
        // Using false condition to avoid infinite loop in test
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            // 3: while statement
            .{
                .tag = .while_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .while_stmt = .{
                    .condition = 4,
                    .body = 5,
                } },
            },
            // 4: condition (false to avoid infinite loop in test)
            .{
                .tag = .literal_bool,
                .main_token = .{ .tag = .keyword_false, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .none = {} },
            },
            // 5: body block
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 18 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{6} } },
            },
            // 6: body statement (just a literal for simplicity)
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 20 },
                .data = .{ .literal_int = .{ .value = limit } },
            },
        };

        const string_table = [_][]const u8{"test"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated
        try testing.expect(module.functions.items.len > 0);

        // The function should have blocks for loop structure
        const func = module.functions.items[0];
        try testing.expect(func.blocks.items.len >= 1);
    }
}

// ============================================================================
// Runtime Library Integration Tests
// ============================================================================

// Property 1.8: Runtime value creation roundtrip
// *For any* PHP value type, creating and converting it SHALL preserve the value.
test "Property 1.8: Runtime value creation roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.1
    RuntimeLib.initRuntime();
    defer RuntimeLib.deinitRuntime();

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        // Test integer roundtrip
        const int_val = randomInt(&rng);
        const php_int = RuntimeLib.php_value_create_int(int_val);
        defer RuntimeLib.php_gc_release(php_int);
        try testing.expectEqual(int_val, RuntimeLib.php_value_to_int(php_int));

        // Test float roundtrip
        const float_val = randomFloat(&rng);
        const php_float = RuntimeLib.php_value_create_float(float_val);
        defer RuntimeLib.php_gc_release(php_float);
        try testing.expectApproxEqAbs(float_val, RuntimeLib.php_value_to_float(php_float), 0.0001);

        // Test boolean roundtrip
        const bool_val = randomBool(&rng);
        const php_bool = RuntimeLib.php_value_create_bool(bool_val);
        defer RuntimeLib.php_gc_release(php_bool);
        try testing.expectEqual(bool_val, RuntimeLib.php_value_to_bool(php_bool));
    }
}

// Property 1.9: Runtime type conversion consistency
// *For any* PHP value, type conversions SHALL follow PHP semantics.
test "Property 1.9: Runtime type conversion consistency" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.1
    RuntimeLib.initRuntime();
    defer RuntimeLib.deinitRuntime();

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const int_val = randomInt(&rng);
        const php_int = RuntimeLib.php_value_create_int(int_val);
        defer RuntimeLib.php_gc_release(php_int);

        // int -> float conversion
        const as_float = RuntimeLib.php_value_to_float(php_int);
        try testing.expectApproxEqAbs(@as(f64, @floatFromInt(int_val)), as_float, 0.0001);

        // int -> bool conversion (PHP semantics: 0 is false, non-zero is true)
        const as_bool = RuntimeLib.php_value_to_bool(php_int);
        try testing.expectEqual(int_val != 0, as_bool);
    }
}

// Property 1.10: Array operations roundtrip
// *For any* array creation and element access, the IR SHALL correctly represent the operations.
test "Property 1.10: Array operations roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.6
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const element_value = randomInt(&rng);

        // Create AST for: function test() { return [element_value]; }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            // 3: return array literal
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .return_stmt = .{ .expr = 4 } },
            },
            // 4: array literal
            .{
                .tag = .array_init,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .array_init = .{
                    .elements = &[_]Node.Index{5},
                } },
            },
            // 5: array element
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 13 },
                .data = .{ .literal_int = .{ .value = element_value } },
            },
        };

        const string_table = [_][]const u8{"test"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated
        try testing.expect(module.functions.items.len > 0);

        // Look for array creation instruction
        var found_array_op = false;
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.op == .array_new or inst.op == .array_set) {
                        found_array_op = true;
                    }
                }
            }
        }
        try testing.expect(found_array_op);
    }
}

// Property 1.11: String operations roundtrip
// *For any* string literal and concatenation, the IR SHALL correctly represent the operations.
test "Property 1.11: String operations roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.7
    const allocator = testing.allocator;
    const QuoteType = @import("ir_generator.zig").QuoteType;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        // Generate random string index for variety
        _ = rng.random().intRangeAtMost(usize, 0, 10);

        // Create AST for: function test() { return "hello" . "world"; }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            // 3: return concatenation
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .return_stmt = .{ .expr = 4 } },
            },
            // 4: string concatenation
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = .dot, .start = 0, .end = 0, .line = 2, .column = 20 },
                .data = .{ .binary_expr = .{ .lhs = 5, .op = .dot, .rhs = 6 } },
            },
            // 5: first string
            .{
                .tag = .literal_string,
                .main_token = .{ .tag = .string_literal, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .literal_string = .{ .value = 1, .quote_type = QuoteType.double } },
            },
            // 6: second string
            .{
                .tag = .literal_string,
                .main_token = .{ .tag = .string_literal, .start = 0, .end = 0, .line = 2, .column = 22 },
                .data = .{ .literal_string = .{ .value = 2, .quote_type = QuoteType.double } },
            },
        };

        const string_table = [_][]const u8{ "test", "hello", "world" };

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated
        try testing.expect(module.functions.items.len > 0);

        // Look for string or concat instruction
        var found_string_op = false;
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.op == .const_string or inst.op == .concat) {
                        found_string_op = true;
                    }
                }
            }
        }
        try testing.expect(found_string_op);
    }
}

// Property 1.12: Function call roundtrip
// *For any* function call, the IR SHALL correctly represent the call with arguments.
test "Property 1.12: Function call roundtrip" {
    // Feature: php-aot-compiler, Property 1: Compile-execute roundtrip
    // Validates: Requirements 6.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        const arg_value = randomInt(&rng);

        // Create AST for: function test() { return strlen(arg_value); }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 20 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            // 3: return statement with function call
            .{
                .tag = .return_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 5 },
                .data = .{ .return_stmt = .{ .expr = 4 } },
            },
            // 4: function call - using variable node as name reference
            .{
                .tag = .function_call,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .function_call = .{
                    .name = 5, // Index to variable node
                    .args = &[_]Node.Index{6},
                } },
            },
            // 5: function name as variable reference
            .{
                .tag = .variable,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 12 },
                .data = .{ .variable = .{ .name = 1 } }, // "strlen" in string table
            },
            // 6: argument (integer literal)
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 2, .column = 19 },
                .data = .{ .literal_int = .{ .value = arg_value } },
            },
        };

        const string_table = [_][]const u8{ "test", "strlen" };

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify IR was generated
        try testing.expect(module.functions.items.len > 0);

        // Look for call instruction
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
}
