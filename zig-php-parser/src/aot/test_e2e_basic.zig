//! End-to-End Basic Compilation Tests for PHP AOT Compiler
//!
//! **Feature: aot-native-compilation**
//! **Task: 8.1 创建基本编译测试**
//! **Validates: Requirements 4.1, 5.1, 5.5**
//!
//! This test suite validates basic AOT compilation functionality:
//! - Simple echo statements
//! - Variable assignment and output
//! - Basic string operations

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

/// Test context for basic compilation tests
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
// Test 8.1.1: Simple Echo Statement
// ============================================================================

test "8.1.1: Simple echo statement generates valid IR and Zig code" {
    // Feature: aot-native-compilation
    // Validates: Requirements 4.1, 5.5
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php echo "Hello World";
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: echo statement
        .{
            .tag = .echo_stmt,
            .main_token = .{ .tag = .eof, .start = 0, .end = 4, .line = 1, .column = 1 },
            .data = .{ .echo_stmt = .{ .exprs = &[_]Node.Index{2} } },
        },
        // 2: string literal "Hello World"
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .string_literal, .start = 5, .end = 18, .line = 1, .column = 6 },
            .data = .{ .literal_string = .{ .value = 0, .quote_type = .double } }, // Index 0 in string table
        },
    };

    const string_table = [_][]const u8{"Hello World"};

    // Generate IR
    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_echo", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Generate Zig code from IR
    const zig_code = try ctx.zig_codegen.generate(module);
    defer allocator.free(zig_code);

    // Verify Zig code contains expected elements
    try testing.expect(zig_code.len > 0);
    try testing.expect(std.mem.indexOf(u8, zig_code, "runtime") != null);
}

// ============================================================================
// Test 8.1.2: Variable Assignment
// ============================================================================

test "8.1.2: Variable assignment generates valid IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 4.1, 5.1
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $x = 42;
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
            .main_token = .{ .tag = .eof, .start = 3, .end = 4, .line = 1, .column = 4 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        // 2: variable $x
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 2, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } }, // Index 0 in string table = "x"
        },
        // 3: literal 42
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 5, .end = 7, .line = 1, .column = 6 },
            .data = .{ .literal_int = .{ .value = 42 } },
        },
    };

    const string_table = [_][]const u8{"x"};

    // Generate IR
    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_assign", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for const_int instruction with value 42
    var found_const = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .const_int) {
                    if (inst.op.const_int == 42) {
                        found_const = true;
                    }
                }
            }
        }
    }
    try testing.expect(found_const);
}

// ============================================================================
// Test 8.1.3: Variable Assignment and Echo
// ============================================================================

test "8.1.3: Variable assignment and echo generates valid IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 4.1, 5.1, 5.5
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $msg = "Hello"; echo $msg;
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{ 1, 4 } } },
        },
        // 1: assignment $msg = "Hello"
        .{
            .tag = .assignment,
            .main_token = .{ .tag = .eof, .start = 5, .end = 6, .line = 1, .column = 6 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        // 2: variable $msg
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 4, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } }, // "msg"
        },
        // 3: string literal "Hello"
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .string_literal, .start = 7, .end = 14, .line = 1, .column = 8 },
            .data = .{ .literal_string = .{ .value = 1, .quote_type = .double } }, // "Hello"
        },
        // 4: echo statement
        .{
            .tag = .echo_stmt,
            .main_token = .{ .tag = .eof, .start = 15, .end = 19, .line = 1, .column = 16 },
            .data = .{ .echo_stmt = .{ .exprs = &[_]Node.Index{5} } },
        },
        // 5: variable $msg (for echo)
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 20, .end = 24, .line = 1, .column = 21 },
            .data = .{ .variable = .{ .name = 0 } }, // "msg"
        },
    };

    const string_table = [_][]const u8{ "msg", "Hello" };

    // Generate IR
    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_var_echo", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Generate Zig code
    const zig_code = try ctx.zig_codegen.generate(module);
    defer allocator.free(zig_code);

    // Verify Zig code was generated
    try testing.expect(zig_code.len > 0);
}

// ============================================================================
// Test 8.1.4: Multiple Echo Statements
// ============================================================================

test "8.1.4: Multiple echo statements generate valid IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 4.1, 5.5
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php echo "Line 1"; echo "Line 2";
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .start = 0, .end = 0, .line = 1, .column = 1 },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{ 1, 3 } } },
        },
        // 1: echo "Line 1"
        .{
            .tag = .echo_stmt,
            .main_token = .{ .tag = .eof, .start = 0, .end = 4, .line = 1, .column = 1 },
            .data = .{ .echo_stmt = .{ .exprs = &[_]Node.Index{2} } },
        },
        // 2: string "Line 1"
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .string_literal, .start = 5, .end = 13, .line = 1, .column = 6 },
            .data = .{ .literal_string = .{ .value = 0, .quote_type = .double } },
        },
        // 3: echo "Line 2"
        .{
            .tag = .echo_stmt,
            .main_token = .{ .tag = .eof, .start = 14, .end = 18, .line = 1, .column = 15 },
            .data = .{ .echo_stmt = .{ .exprs = &[_]Node.Index{4} } },
        },
        // 4: string "Line 2"
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .string_literal, .start = 19, .end = 27, .line = 1, .column = 20 },
            .data = .{ .literal_string = .{ .value = 1, .quote_type = .double } },
        },
    };

    const string_table = [_][]const u8{ "Line 1", "Line 2" };

    // Generate IR
    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_multi_echo", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);
}

// ============================================================================
// Test 8.1.5: Integer Variable Types
// ============================================================================

test "8.1.5: Integer variable assignment preserves value" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.1
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Test various integer values
    const test_values = [_]i64{ 0, 1, -1, 100, -100, 2147483647, -2147483648 };

    for (test_values) |expected_value| {
        // Create AST for: <?php $n = <value>;
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
                .data = .{ .literal_int = .{ .value = expected_value } },
            },
        };

        const string_table = [_][]const u8{"n"};

        const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_int", "test.php");
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Find the const_int instruction and verify value
        var found = false;
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.op == .const_int) {
                        if (inst.op.const_int == expected_value) {
                            found = true;
                        }
                    }
                }
            }
        }
        try testing.expect(found);
    }
}
