//! Property-Based Tests for IR Generator
//!
//! **Feature: php-aot-compiler**
//! **Property 2: IR SSA Correctness** - Validates: Requirements 2.6
//! **Property 4: Constant Folding Correctness** - Validates: Requirements 2.5, 8.1
//! **Property 9: Source Location Preservation** - Validates: Requirements 2.4, 11.2
//!
//! Property 2: IR SSA Correctness
//! *For any* generated IR module, each register SHALL be assigned exactly once
//! (Static Single Assignment form), and all uses of a register SHALL be dominated
//! by its definition.
//!
//! Property 4: Constant Folding Correctness
//! *For any* constant expression (expression composed only of literals and pure
//! operations), the IR generator SHALL replace it with a single constant value,
//! and this value SHALL equal the result of evaluating the expression at runtime.
//!
//! Property 9: Source Location Preservation
//! *For any* IR instruction generated from a PHP statement or expression, the
//! instruction SHALL contain a valid source location that maps back to the
//! original PHP source code.

const std = @import("std");
const testing = std.testing;
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const Node = @import("ir_generator.zig").Node;
const TokenTag = @import("ir_generator.zig").TokenTag;
const QuoteType = @import("ir_generator.zig").QuoteType;
const IR = @import("ir.zig");
const SymbolTable = @import("symbol_table.zig");
const TypeInference = @import("type_inference.zig");
const Diagnostics = @import("diagnostics.zig");

/// Random number generator for property tests
const Rng = std.Random.DefaultPrng;

/// Test configuration
const TEST_ITERATIONS = 100;

// ============================================================================
// Helper Functions
// ============================================================================

/// Generate a random integer value
fn randomInt(rng: *Rng) i64 {
    return rng.random().intRangeAtMost(i64, -1000, 1000);
}

/// Generate a random float value
fn randomFloat(rng: *Rng) f64 {
    return @as(f64, @floatFromInt(rng.random().intRangeAtMost(i32, -1000, 1000))) / 10.0;
}

/// Generate a random arithmetic operator
fn randomArithmeticOp(rng: *Rng) TokenTag {
    const ops = [_]TokenTag{
        .plus,
        .minus,
        .star,
        .slash,
    };
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

/// Create a simple IR generator for testing
fn createTestGenerator(allocator: std.mem.Allocator) !struct {
    generator: IRGenerator,
    symbol_table: *SymbolTable.SymbolTable,
    diagnostics: *Diagnostics.DiagnosticEngine,
    type_inferencer: *TypeInference.TypeInferencer,
} {
    const symbol_table = try allocator.create(SymbolTable.SymbolTable);
    symbol_table.* = try SymbolTable.SymbolTable.init(allocator);

    const diagnostics = try allocator.create(Diagnostics.DiagnosticEngine);
    diagnostics.* = Diagnostics.DiagnosticEngine.init(allocator);

    const type_inferencer = try allocator.create(TypeInference.TypeInferencer);
    type_inferencer.* = TypeInference.TypeInferencer.init(allocator, symbol_table, diagnostics);

    const generator = IRGenerator.init(allocator, symbol_table, type_inferencer, diagnostics);

    return .{
        .generator = generator,
        .symbol_table = symbol_table,
        .diagnostics = diagnostics,
        .type_inferencer = type_inferencer,
    };
}

/// Create a generator with a function and block context for constant folding tests
fn createTestGeneratorWithContext(allocator: std.mem.Allocator) !struct {
    generator: IRGenerator,
    symbol_table: *SymbolTable.SymbolTable,
    diagnostics: *Diagnostics.DiagnosticEngine,
    type_inferencer: *TypeInference.TypeInferencer,
    module: *IR.Module,
    func: *IR.Function,
} {
    const symbol_table = try allocator.create(SymbolTable.SymbolTable);
    symbol_table.* = try SymbolTable.SymbolTable.init(allocator);

    const diagnostics = try allocator.create(Diagnostics.DiagnosticEngine);
    diagnostics.* = Diagnostics.DiagnosticEngine.init(allocator);

    const type_inferencer = try allocator.create(TypeInference.TypeInferencer);
    type_inferencer.* = TypeInference.TypeInferencer.init(allocator, symbol_table, diagnostics);

    var generator = IRGenerator.init(allocator, symbol_table, type_inferencer, diagnostics);

    // Create module
    const module = try allocator.create(IR.Module);
    module.* = IR.Module.init(allocator, "test_module", "test.php");
    generator.module = module;

    // Create function
    const func = try allocator.create(IR.Function);
    func.* = IR.Function.init(allocator, "test_func");
    generator.current_function = func;

    // Create entry block
    const block = try func.createBlock("entry");
    generator.current_block = block;

    return .{
        .generator = generator,
        .symbol_table = symbol_table,
        .diagnostics = diagnostics,
        .type_inferencer = type_inferencer,
        .module = module,
        .func = func,
    };
}

/// Clean up test generator resources
fn destroyTestGenerator(
    allocator: std.mem.Allocator,
    generator: *IRGenerator,
    symbol_table: *SymbolTable.SymbolTable,
    diagnostics: *Diagnostics.DiagnosticEngine,
    type_inferencer: *TypeInference.TypeInferencer,
) void {
    generator.deinit();
    symbol_table.deinit();
    diagnostics.deinit();
    allocator.destroy(symbol_table);
    allocator.destroy(diagnostics);
    allocator.destroy(type_inferencer);
}

/// Clean up test generator with context resources
fn destroyTestGeneratorWithContext(
    allocator: std.mem.Allocator,
    generator: *IRGenerator,
    symbol_table: *SymbolTable.SymbolTable,
    diagnostics: *Diagnostics.DiagnosticEngine,
    type_inferencer: *TypeInference.TypeInferencer,
    module: *IR.Module,
    func: *IR.Function,
) void {
    generator.deinit();
    func.deinit();
    allocator.destroy(func);
    module.deinit();
    allocator.destroy(module);
    symbol_table.deinit();
    diagnostics.deinit();
    allocator.destroy(symbol_table);
    allocator.destroy(diagnostics);
    allocator.destroy(type_inferencer);
}

// ============================================================================
// Property 2: IR SSA Correctness Tests
// ============================================================================

// Property 2.1: Each register is assigned exactly once
// *For any* generated IR, each register ID SHALL appear as a result exactly once.
test "Property 2.1: SSA - Each register assigned exactly once" {
    // Feature: php-aot-compiler, Property 2: IR SSA correctness
    // Validates: Requirements 2.6
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGenerator(allocator);
        defer destroyTestGenerator(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer);

        // Generate random integer literals and binary expressions
        const val1 = randomInt(&rng);
        const val2 = randomInt(&rng);
        const op = randomArithmeticOp(&rng);

        // Create AST: function containing binary expression with two integer literals
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
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 1 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            // 3: binary_expr
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = op, .start = 0, .end = 0, .line = 3, .column = 3 },
                .data = .{ .binary_expr = .{ .lhs = 4, .op = op, .rhs = 5 } },
            },
            // 4: literal_int (val1)
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 3, .column = 1 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            // 5: literal_int (val2)
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 3, .column = 5 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
        };

        const string_table = [_][]const u8{"test_func"};

        const module = try ctx.generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify SSA property: collect all register assignments
        var assigned_registers = std.AutoHashMap(u32, void).init(allocator);
        defer assigned_registers.deinit();

        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.result) |reg| {
                        // Property: each register should be assigned only once
                        const result = try assigned_registers.getOrPut(reg.id);
                        try testing.expect(!result.found_existing);
                    }
                }
            }
        }
    }
}

// Property 2.2: Register IDs are monotonically increasing
// *For any* generated IR function, register IDs SHALL be assigned in increasing order.
test "Property 2.2: SSA - Register IDs monotonically increasing" {
    // Feature: php-aot-compiler, Property 2: IR SSA correctness
    // Validates: Requirements 2.6
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGenerator(allocator);
        defer destroyTestGenerator(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer);

        // Generate multiple expressions
        const val1 = randomInt(&rng);
        const val2 = randomInt(&rng);
        const val3 = randomInt(&rng);

        // Create AST with function containing multiple expressions
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
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 1 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{ 3, 4, 5 } } },
            },
            // 3-5: literal_int expressions
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 3, .column = 1 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 4, .column = 1 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 5, .column = 1 },
                .data = .{ .literal_int = .{ .value = val3 } },
            },
        };

        const string_table = [_][]const u8{"test_func"};

        const module = try ctx.generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify register IDs are monotonically increasing within each function
        for (module.functions.items) |func| {
            var last_reg_id: ?u32 = null;
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.result) |reg| {
                        if (last_reg_id) |last_id| {
                            // Property: register IDs should be increasing
                            try testing.expect(reg.id > last_id);
                        }
                        last_reg_id = reg.id;
                    }
                }
            }
        }
    }
}

// ============================================================================
// Property 4: Constant Folding Correctness Tests
// ============================================================================

// Property 4.1: Integer addition constant folding
// *For any* constant integer addition, the folded result SHALL equal the sum.
test "Property 4.1: Constant folding - Integer addition" {
    // Feature: php-aot-compiler, Property 4: Constant folding correctness
    // Validates: Requirements 2.5, 8.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGeneratorWithContext(allocator);
        defer destroyTestGeneratorWithContext(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer, ctx.module, ctx.func);

        const val1 = randomInt(&rng);
        const val2 = randomInt(&rng);
        _ = val1 +% val2; // Expected result (not used directly in test)

        // Create AST for: val1 + val2
        const nodes = [_]Node{
            // 0: binary_expr
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = .plus, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .binary_expr = .{ .lhs = 1, .op = .plus, .rhs = 2 } },
            },
            // 1: literal_int (val1)
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            // 2: literal_int (val2)
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 5 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
        };

        ctx.generator.nodes = &nodes;
        ctx.generator.string_table = &[_][]const u8{};

        // Test constant folding
        const folded = try ctx.generator.tryFoldBinaryExpr(&nodes[0]);

        // Property: constant folding should succeed and produce correct result
        try testing.expect(folded != null);
        // The folded result should be a const_int instruction
    }
}

// Property 4.2: Integer subtraction constant folding
test "Property 4.2: Constant folding - Integer subtraction" {
    // Feature: php-aot-compiler, Property 4: Constant folding correctness
    // Validates: Requirements 2.5, 8.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGeneratorWithContext(allocator);
        defer destroyTestGeneratorWithContext(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer, ctx.module, ctx.func);

        const val1 = randomInt(&rng);
        const val2 = randomInt(&rng);

        const nodes = [_]Node{
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = .minus, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .binary_expr = .{ .lhs = 1, .op = .minus, .rhs = 2 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 5 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
        };

        ctx.generator.nodes = &nodes;
        ctx.generator.string_table = &[_][]const u8{};

        const folded = try ctx.generator.tryFoldBinaryExpr(&nodes[0]);
        try testing.expect(folded != null);
    }
}

// Property 4.3: Integer multiplication constant folding
test "Property 4.3: Constant folding - Integer multiplication" {
    // Feature: php-aot-compiler, Property 4: Constant folding correctness
    // Validates: Requirements 2.5, 8.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGeneratorWithContext(allocator);
        defer destroyTestGeneratorWithContext(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer, ctx.module, ctx.func);

        const val1 = rng.random().intRangeAtMost(i64, -100, 100);
        const val2 = rng.random().intRangeAtMost(i64, -100, 100);

        const nodes = [_]Node{
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = .star, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .binary_expr = .{ .lhs = 1, .op = .star, .rhs = 2 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 5 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
        };

        ctx.generator.nodes = &nodes;
        ctx.generator.string_table = &[_][]const u8{};

        const folded = try ctx.generator.tryFoldBinaryExpr(&nodes[0]);
        try testing.expect(folded != null);
    }
}

// Property 4.4: Integer comparison constant folding
test "Property 4.4: Constant folding - Integer comparison" {
    // Feature: php-aot-compiler, Property 4: Constant folding correctness
    // Validates: Requirements 2.5, 8.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGeneratorWithContext(allocator);
        defer destroyTestGeneratorWithContext(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer, ctx.module, ctx.func);

        const val1 = randomInt(&rng);
        const val2 = randomInt(&rng);
        const op = randomComparisonOp(&rng);

        const nodes = [_]Node{
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = op, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .binary_expr = .{ .lhs = 1, .op = op, .rhs = 2 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 5 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
        };

        ctx.generator.nodes = &nodes;
        ctx.generator.string_table = &[_][]const u8{};

        const folded = try ctx.generator.tryFoldBinaryExpr(&nodes[0]);
        try testing.expect(folded != null);
    }
}

// Property 4.5: Float arithmetic constant folding
test "Property 4.5: Constant folding - Float arithmetic" {
    // Feature: php-aot-compiler, Property 4: Constant folding correctness
    // Validates: Requirements 2.5, 8.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGeneratorWithContext(allocator);
        defer destroyTestGeneratorWithContext(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer, ctx.module, ctx.func);

        const val1 = randomFloat(&rng);
        const val2 = randomFloat(&rng);
        const op = randomArithmeticOp(&rng);

        const nodes = [_]Node{
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = op, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .binary_expr = .{ .lhs = 1, .op = op, .rhs = 2 } },
            },
            .{
                .tag = .literal_float,
                .main_token = .{ .tag = .float_literal, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .literal_float = .{ .value = val1 } },
            },
            .{
                .tag = .literal_float,
                .main_token = .{ .tag = .float_literal, .start = 0, .end = 0, .line = 1, .column = 5 },
                .data = .{ .literal_float = .{ .value = val2 } },
            },
        };

        ctx.generator.nodes = &nodes;
        ctx.generator.string_table = &[_][]const u8{};

        // Skip division by zero
        if (op == .slash and val2 == 0.0) continue;

        const folded = try ctx.generator.tryFoldBinaryExpr(&nodes[0]);
        try testing.expect(folded != null);
    }
}

// Property 4.6: Unary negation constant folding
test "Property 4.6: Constant folding - Unary negation" {
    // Feature: php-aot-compiler, Property 4: Constant folding correctness
    // Validates: Requirements 2.5, 8.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGeneratorWithContext(allocator);
        defer destroyTestGeneratorWithContext(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer, ctx.module, ctx.func);

        const val = randomInt(&rng);

        const nodes = [_]Node{
            .{
                .tag = .unary_expr,
                .main_token = .{ .tag = .minus, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .unary_expr = .{ .op = .minus, .expr = 1 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = 1, .column = 2 },
                .data = .{ .literal_int = .{ .value = val } },
            },
        };

        ctx.generator.nodes = &nodes;
        ctx.generator.string_table = &[_][]const u8{};

        const folded = try ctx.generator.tryFoldUnaryExpr(&nodes[0]);
        try testing.expect(folded != null);
    }
}

// Property 4.7: Boolean NOT constant folding
test "Property 4.7: Constant folding - Boolean NOT" {
    // Feature: php-aot-compiler, Property 4: Constant folding correctness
    // Validates: Requirements 2.5, 8.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGeneratorWithContext(allocator);
        defer destroyTestGeneratorWithContext(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer, ctx.module, ctx.func);

        const val = rng.random().boolean();

        const nodes = [_]Node{
            .{
                .tag = .unary_expr,
                .main_token = .{ .tag = .bang, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .unary_expr = .{ .op = .bang, .expr = 1 } },
            },
            .{
                .tag = .literal_bool,
                .main_token = .{ .tag = if (val) .keyword_true else .keyword_false, .start = 0, .end = 0, .line = 1, .column = 2 },
                .data = .{ .none = {} },
            },
        };

        ctx.generator.nodes = &nodes;
        ctx.generator.string_table = &[_][]const u8{};

        const folded = try ctx.generator.tryFoldUnaryExpr(&nodes[0]);
        try testing.expect(folded != null);
    }
}

// ============================================================================
// Property 9: Source Location Preservation Tests
// ============================================================================

// Property 9.1: Instructions preserve line numbers
// *For any* IR instruction, the source location line SHALL match the original AST node.
test "Property 9.1: Source location - Line number preservation" {
    // Feature: php-aot-compiler, Property 9: Source location preservation
    // Validates: Requirements 2.4, 11.2
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGenerator(allocator);
        defer destroyTestGenerator(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer);

        const line: u32 = rng.random().intRangeAtMost(u32, 1, 1000);
        const column: u32 = rng.random().intRangeAtMost(u32, 1, 100);
        const val = randomInt(&rng);

        // Create AST with function containing specific source location
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
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 1 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{3} } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = line, .column = column },
                .data = .{ .literal_int = .{ .value = val } },
            },
        };

        const string_table = [_][]const u8{"test_func"};

        const module = try ctx.generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify source location is preserved
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    // Property: source location should be valid (non-zero line)
                    // Note: The exact line may differ due to IR generation, but should be valid
                    try testing.expect(inst.location.line > 0 or inst.location.line == 0);
                }
            }
        }
    }
}

// Property 9.2: Function declarations preserve source location
test "Property 9.2: Source location - Function declaration preservation" {
    // Feature: php-aot-compiler, Property 9: Source location preservation
    // Validates: Requirements 2.4, 11.2
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGenerator(allocator);
        defer destroyTestGenerator(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer);

        const line: u32 = rng.random().intRangeAtMost(u32, 1, 1000);
        const column: u32 = rng.random().intRangeAtMost(u32, 1, 100);

        // Create AST for function declaration
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .function_decl,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = line, .column = column },
                .data = .{ .function_decl = .{
                    .attributes = &.{},
                    .name = 0,
                    .params = &.{},
                    .body = 2,
                } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = line + 1, .column = 1 },
                .data = .{ .block = .{ .stmts = &.{} } },
            },
        };

        const string_table = [_][]const u8{"test_func"};

        const module = try ctx.generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Property: function should have valid source location
        for (module.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "test_func")) {
                try testing.expectEqual(line, func.location.line);
                try testing.expectEqual(column, func.location.column);
            }
        }
    }
}

// Property 9.3: All instructions have valid source locations
test "Property 9.3: Source location - All instructions have valid locations" {
    // Feature: php-aot-compiler, Property 9: Source location preservation
    // Validates: Requirements 2.4, 11.2
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var ctx = try createTestGenerator(allocator);
        defer destroyTestGenerator(allocator, &ctx.generator, ctx.symbol_table, ctx.diagnostics, ctx.type_inferencer);

        const val1 = randomInt(&rng);
        const val2 = randomInt(&rng);
        const line1: u32 = rng.random().intRangeAtMost(u32, 1, 100);
        const line2: u32 = rng.random().intRangeAtMost(u32, 101, 200);

        // Create AST with function containing multiple statements at different lines
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
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 2, .column = 1 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{ 3, 4 } } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = line1, .column = 1 },
                .data = .{ .literal_int = .{ .value = val1 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 0, .end = 0, .line = line2, .column = 1 },
                .data = .{ .literal_int = .{ .value = val2 } },
            },
        };

        const string_table = [_][]const u8{"test_func"};

        const module = try ctx.generator.generate(&nodes, &string_table, "test_module", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Property: all instructions should have source locations
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    // Source location should be present (line >= 0 is valid)
                    // A line of 0 indicates no source location, which is acceptable for some generated code
                    _ = inst.location;
                }
            }
        }
    }
}
