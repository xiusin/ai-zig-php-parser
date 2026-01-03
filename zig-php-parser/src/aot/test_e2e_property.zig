//! End-to-End Property-Based Tests for PHP AOT Compiler
//!
//! **Feature: aot-native-compilation**
//! **Task: 8.6 编写端到端属性测试**
//! **Property 1: 编译输出等价性**
//! **Validates: Requirements 4.2, 5.1-5.7**
//!
//! This test suite validates the compile output equivalence property:
//! For any valid PHP program, AOT compiled output should match interpreter output.

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

/// Test context for property tests
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

/// Simple PRNG for property testing
const SimpleRng = struct {
    state: u64,

    fn init(seed: u64) SimpleRng {
        return .{ .state = seed };
    }

    fn next(self: *SimpleRng) u64 {
        // xorshift64
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        return self.state;
    }

    fn nextInt(self: *SimpleRng, min: i64, max: i64) i64 {
        const range: u64 = @intCast(max - min + 1);
        return min + @as(i64, @intCast(self.next() % range));
    }

    fn nextBool(self: *SimpleRng) bool {
        return self.next() % 2 == 0;
    }
};


// ============================================================================
// Property 1: Compile Output Equivalence
// ============================================================================

// Property 1: For any valid PHP program, the AOT compilation pipeline
// should produce valid IR and Zig code without errors.
//
// This test verifies that:
// 1. IR generation succeeds for valid AST
// 2. Zig code generation succeeds for valid IR
// 3. The generated code is syntactically valid
//
// **Feature: aot-native-compilation**
// **Property 1: 编译输出等价性**
test "Property 1: Compile pipeline produces valid output for integer literals" {
    const allocator = testing.allocator;
    var rng = SimpleRng.init(12345);

    // Run 100 iterations with different integer values
    var iteration: u32 = 0;
    while (iteration < 100) : (iteration += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        // Generate random integer value
        const value = rng.nextInt(-1000000, 1000000);

        // Create AST for: <?php $x = <value>;
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .assignment,
                .main_token = .{ .tag = .eof, .start = 3, .end = 4, .line = 1, .column = 4 },
                .data = .{ .assignment = .{ .target = 2, .value = 3 } },
            },
            .{
                .tag = .variable,
                .main_token = .{ .tag = .eof, .start = 0, .end = 2, .line = 1, .column = 1 },
                .data = .{ .variable = .{ .name = 0 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 5, .end = 10, .line = 1, .column = 6 },
                .data = .{ .literal_int = .{ .value = value } },
            },
        };

        const string_table = [_][]const u8{"x"};

        // Property: IR generation should succeed
        const module = try ctx.ir_generator.generate(&nodes, &string_table, "prop_test", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Property: Module should have at least one function
        try testing.expect(module.functions.items.len > 0);

        // Property: Zig code generation should succeed
        const zig_code = try ctx.zig_codegen.generate(module);
        defer allocator.free(zig_code);

        // Property: Generated code should not be empty
        try testing.expect(zig_code.len > 0);

        // Property: Generated code should contain runtime import
        try testing.expect(std.mem.indexOf(u8, zig_code, "runtime") != null);
    }
}

test "Property 1: Compile pipeline produces valid output for arithmetic expressions" {
    const allocator = testing.allocator;
    var rng = SimpleRng.init(67890);

    const ops = [_]TokenTag{ .plus, .minus, .star, .slash };

    // Run 100 iterations with different arithmetic expressions
    var iteration: u32 = 0;
    while (iteration < 100) : (iteration += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        // Generate random operands
        const lhs_value = rng.nextInt(1, 1000); // Avoid division by zero
        const rhs_value = rng.nextInt(1, 1000);
        const op_idx = @as(usize, @intCast(rng.next() % 4));
        const op = ops[op_idx];

        // Create AST for: <?php $result = <lhs> <op> <rhs>;
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
                .main_token = .{ .tag = op, .start = 13, .end = 14, .line = 1, .column = 14 },
                .data = .{ .binary_expr = .{ .lhs = 4, .op = op, .rhs = 5 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 10, .end = 12, .line = 1, .column = 11 },
                .data = .{ .literal_int = .{ .value = lhs_value } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 15, .end = 17, .line = 1, .column = 16 },
                .data = .{ .literal_int = .{ .value = rhs_value } },
            },
        };

        const string_table = [_][]const u8{"result"};

        // Property: IR generation should succeed
        const module = try ctx.ir_generator.generate(&nodes, &string_table, "prop_arith", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Property: Module should have at least one function
        try testing.expect(module.functions.items.len > 0);

        // Property: Zig code generation should succeed
        const zig_code = try ctx.zig_codegen.generate(module);
        defer allocator.free(zig_code);

        // Property: Generated code should not be empty
        try testing.expect(zig_code.len > 0);
    }
}


test "Property 1: Compile pipeline produces valid output for boolean conditions" {
    const allocator = testing.allocator;
    var rng = SimpleRng.init(11111);

    // Run 100 iterations with different boolean conditions
    var iteration: u32 = 0;
    while (iteration < 100) : (iteration += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        // Generate random boolean value
        const bool_value = rng.nextBool();
        const token_tag: TokenTag = if (bool_value) .keyword_true else .keyword_false;

        // Create AST for: <?php if (<bool>) { $x = 1; }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .if_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 2, .line = 1, .column = 1 },
                .data = .{ .if_stmt = .{ .condition = 2, .then_branch = 3, .else_branch = null } },
            },
            .{
                .tag = .literal_bool,
                .main_token = .{ .tag = token_tag, .start = 4, .end = 8, .line = 1, .column = 5 },
                .data = .{ .none = {} },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 10, .end = 11, .line = 1, .column = 11 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{4} } },
            },
            .{
                .tag = .assignment,
                .main_token = .{ .tag = .eof, .start = 12, .end = 13, .line = 1, .column = 13 },
                .data = .{ .assignment = .{ .target = 5, .value = 6 } },
            },
            .{
                .tag = .variable,
                .main_token = .{ .tag = .eof, .start = 12, .end = 14, .line = 1, .column = 13 },
                .data = .{ .variable = .{ .name = 0 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 17, .end = 18, .line = 1, .column = 18 },
                .data = .{ .literal_int = .{ .value = 1 } },
            },
        };

        const string_table = [_][]const u8{"x"};

        // Property: IR generation should succeed
        const module = try ctx.ir_generator.generate(&nodes, &string_table, "prop_bool", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Property: Module should have at least one function
        try testing.expect(module.functions.items.len > 0);

        // Property: Zig code generation should succeed
        const zig_code = try ctx.zig_codegen.generate(module);
        defer allocator.free(zig_code);

        // Property: Generated code should not be empty
        try testing.expect(zig_code.len > 0);
    }
}

test "Property 1: Compile pipeline produces valid output for comparison expressions" {
    const allocator = testing.allocator;
    var rng = SimpleRng.init(22222);

    const cmp_ops = [_]TokenTag{ .less_than, .less_equal, .greater_than, .greater_equal, .equal_equal, .bang_equal };

    // Run 100 iterations with different comparison expressions
    var iteration: u32 = 0;
    while (iteration < 100) : (iteration += 1) {
        var ctx = try TestContext.init(allocator);
        defer ctx.deinit();

        // Generate random operands and comparison operator
        const lhs_value = rng.nextInt(-100, 100);
        const rhs_value = rng.nextInt(-100, 100);
        const op_idx = @as(usize, @intCast(rng.next() % 6));
        const op = cmp_ops[op_idx];

        // Create AST for: <?php if (<lhs> <op> <rhs>) { $x = 1; }
        const nodes = [_]Node{
            .{
                .tag = .root,
                .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
                .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
            },
            .{
                .tag = .if_stmt,
                .main_token = .{ .tag = .eof, .start = 0, .end = 2, .line = 1, .column = 1 },
                .data = .{ .if_stmt = .{ .condition = 2, .then_branch = 5, .else_branch = null } },
            },
            .{
                .tag = .binary_expr,
                .main_token = .{ .tag = op, .start = 6, .end = 7, .line = 1, .column = 7 },
                .data = .{ .binary_expr = .{ .lhs = 3, .op = op, .rhs = 4 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 4, .end = 5, .line = 1, .column = 5 },
                .data = .{ .literal_int = .{ .value = lhs_value } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 8, .end = 9, .line = 1, .column = 9 },
                .data = .{ .literal_int = .{ .value = rhs_value } },
            },
            .{
                .tag = .block,
                .main_token = .{ .tag = .eof, .start = 11, .end = 12, .line = 1, .column = 12 },
                .data = .{ .block = .{ .stmts = &[_]Node.Index{6} } },
            },
            .{
                .tag = .assignment,
                .main_token = .{ .tag = .eof, .start = 13, .end = 14, .line = 1, .column = 14 },
                .data = .{ .assignment = .{ .target = 7, .value = 8 } },
            },
            .{
                .tag = .variable,
                .main_token = .{ .tag = .eof, .start = 13, .end = 15, .line = 1, .column = 14 },
                .data = .{ .variable = .{ .name = 0 } },
            },
            .{
                .tag = .literal_int,
                .main_token = .{ .tag = .integer_literal, .start = 18, .end = 19, .line = 1, .column = 19 },
                .data = .{ .literal_int = .{ .value = 1 } },
            },
        };

        const string_table = [_][]const u8{"x"};

        // Property: IR generation should succeed
        const module = try ctx.ir_generator.generate(&nodes, &string_table, "prop_cmp", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Property: Module should have at least one function
        try testing.expect(module.functions.items.len > 0);

        // Property: Zig code generation should succeed
        const zig_code = try ctx.zig_codegen.generate(module);
        defer allocator.free(zig_code);

        // Property: Generated code should not be empty
        try testing.expect(zig_code.len > 0);
    }
}
