//! End-to-End Array Tests for PHP AOT Compiler
//!
//! **Feature: aot-native-compilation**
//! **Task: 8.5 创建数组测试**
//! **Validates: Requirements 5.6**
//!
//! This test suite validates array handling in AOT compilation:
//! - Array creation
//! - Array access
//! - Associative arrays

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

/// Test context for array tests
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
// Test 8.5.1: Empty Array Creation
// ============================================================================

test "8.5.1: Empty array creation generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.6
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $arr = [];
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
            .main_token = .{ .tag = .eof, .start = 5, .end = 6, .line = 1, .column = 6 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        // 2: variable $arr
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 4, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 3: empty array
        .{
            .tag = .array_init,
            .main_token = .{ .tag = .eof, .start = 7, .end = 9, .line = 1, .column = 8 },
            .data = .{ .array_init = .{ .elements = &[_]Node.Index{} } },
        },
    };

    const string_table = [_][]const u8{"arr"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_empty_array", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for array_new instruction
    var found_array_new = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .array_new) {
                    found_array_new = true;
                }
            }
        }
    }
    try testing.expect(found_array_new);
}

// ============================================================================
// Test 8.5.2: Array with Integer Elements
// ============================================================================

test "8.5.2: Array with integer elements generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.6
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $arr = [1, 2, 3];
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
            .main_token = .{ .tag = .eof, .start = 5, .end = 6, .line = 1, .column = 6 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        // 2: variable $arr
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 4, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 3: array with elements
        .{
            .tag = .array_init,
            .main_token = .{ .tag = .eof, .start = 7, .end = 8, .line = 1, .column = 8 },
            .data = .{ .array_init = .{ .elements = &[_]Node.Index{ 4, 5, 6 } } },
        },
        // 4: literal 1
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 8, .end = 9, .line = 1, .column = 9 },
            .data = .{ .literal_int = .{ .value = 1 } },
        },
        // 5: literal 2
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 11, .end = 12, .line = 1, .column = 12 },
            .data = .{ .literal_int = .{ .value = 2 } },
        },
        // 6: literal 3
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 14, .end = 15, .line = 1, .column = 15 },
            .data = .{ .literal_int = .{ .value = 3 } },
        },
    };

    const string_table = [_][]const u8{"arr"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_int_array", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for array_new and array_push instructions
    var found_array_new = false;
    var push_count: u32 = 0;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .array_new) {
                    found_array_new = true;
                } else if (inst.op == .array_push) {
                    push_count += 1;
                }
            }
        }
    }
    try testing.expect(found_array_new);
    try testing.expect(push_count >= 3);
}

// ============================================================================
// Test 8.5.3: Array Access by Index
// ============================================================================

test "8.5.3: Array access by index generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.6
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $x = $arr[0];
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
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 3: array access $arr[0]
        .{
            .tag = .array_access,
            .main_token = .{ .tag = .eof, .start = 5, .end = 12, .line = 1, .column = 6 },
            .data = .{ .array_access = .{ .target = 4, .index = 5 } },
        },
        // 4: variable $arr
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 5, .end = 9, .line = 1, .column = 6 },
            .data = .{ .variable = .{ .name = 1 } },
        },
        // 5: index 0
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 11, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = 0 } },
        },
    };

    const string_table = [_][]const u8{ "x", "arr" };

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_array_access", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for array_get instruction
    var found_array_get = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .array_get) {
                    found_array_get = true;
                }
            }
        }
    }
    try testing.expect(found_array_get);
}


// ============================================================================
// Test 8.5.4: Array Assignment by Index
// ============================================================================

test "8.5.4: Array assignment by index generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.6
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $arr[0] = 42;
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
            .data = .{ .assignment = .{ .target = 2, .value = 5 } },
        },
        // 2: array access $arr[0]
        .{
            .tag = .array_access,
            .main_token = .{ .tag = .eof, .start = 0, .end = 7, .line = 1, .column = 1 },
            .data = .{ .array_access = .{ .target = 3, .index = 4 } },
        },
        // 3: variable $arr
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 4, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 4: index 0
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 5, .end = 6, .line = 1, .column = 6 },
            .data = .{ .literal_int = .{ .value = 0 } },
        },
        // 5: value 42
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .integer_literal, .start = 10, .end = 12, .line = 1, .column = 11 },
            .data = .{ .literal_int = .{ .value = 42 } },
        },
    };

    const string_table = [_][]const u8{"arr"};

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_array_set", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for array_set instruction
    var found_array_set = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .array_set) {
                    found_array_set = true;
                }
            }
        }
    }
    try testing.expect(found_array_set);
}

// ============================================================================
// Test 8.5.5: Associative Array with String Keys
// ============================================================================

test "8.5.5: Associative array with string keys generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.6
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $arr = ["name" => "John"];
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
            .main_token = .{ .tag = .eof, .start = 5, .end = 6, .line = 1, .column = 6 },
            .data = .{ .assignment = .{ .target = 2, .value = 3 } },
        },
        // 2: variable $arr
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 0, .end = 4, .line = 1, .column = 1 },
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 3: array with key-value pair
        .{
            .tag = .array_init,
            .main_token = .{ .tag = .eof, .start = 7, .end = 8, .line = 1, .column = 8 },
            .data = .{ .array_init = .{ .elements = &[_]Node.Index{4} } },
        },
        // 4: array pair "name" => "John"
        .{
            .tag = .array_pair,
            .main_token = .{ .tag = .eof, .start = 8, .end = 22, .line = 1, .column = 9 },
            .data = .{ .array_pair = .{ .key = 5, .value = 6 } },
        },
        // 5: key "name"
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .string_literal, .start = 8, .end = 14, .line = 1, .column = 9 },
            .data = .{ .literal_string = .{ .value = 1, .quote_type = .double } },
        },
        // 6: value "John"
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .string_literal, .start = 18, .end = 24, .line = 1, .column = 19 },
            .data = .{ .literal_string = .{ .value = 2, .quote_type = .double } },
        },
    };

    const string_table = [_][]const u8{ "arr", "name", "John" };

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_assoc_array", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for array_new and array_set instructions
    var found_array_new = false;
    var found_array_set = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .array_new) {
                    found_array_new = true;
                } else if (inst.op == .array_set) {
                    found_array_set = true;
                }
            }
        }
    }
    try testing.expect(found_array_new);
    try testing.expect(found_array_set);
}

// ============================================================================
// Test 8.5.6: Array Access with String Key
// ============================================================================

test "8.5.6: Array access with string key generates correct IR" {
    // Feature: aot-native-compilation
    // Validates: Requirements 5.6
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    // Create AST for: <?php $x = $arr["key"];
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
            .data = .{ .variable = .{ .name = 0 } },
        },
        // 3: array access $arr["key"]
        .{
            .tag = .array_access,
            .main_token = .{ .tag = .eof, .start = 5, .end = 16, .line = 1, .column = 6 },
            .data = .{ .array_access = .{ .target = 4, .index = 5 } },
        },
        // 4: variable $arr
        .{
            .tag = .variable,
            .main_token = .{ .tag = .eof, .start = 5, .end = 9, .line = 1, .column = 6 },
            .data = .{ .variable = .{ .name = 1 } },
        },
        // 5: key "key"
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .string_literal, .start = 10, .end = 15, .line = 1, .column = 11 },
            .data = .{ .literal_string = .{ .value = 2, .quote_type = .double } },
        },
    };

    const string_table = [_][]const u8{ "x", "arr", "key" };

    const module = try ctx.ir_generator.generate(&nodes, &string_table, "test_string_key_access", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    // Verify IR was generated
    try testing.expect(module.functions.items.len > 0);

    // Check for array_get instruction
    var found_array_get = false;
    for (module.functions.items) |func| {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .array_get) {
                    found_array_get = true;
                }
            }
        }
    }
    try testing.expect(found_array_get);
}
