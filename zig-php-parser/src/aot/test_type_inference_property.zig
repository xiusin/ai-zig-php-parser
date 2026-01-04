//! Property-Based Tests for Type Inference System
//!
//! **Feature: php-aot-compiler, Property 3: Type Inference Correctness**
//! **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
//!
//! Property 3: Type Inference Correctness
//! *For any* PHP expression with explicit type declarations, the inferred type SHALL match
//! the declared type. *For any* expression without type declarations, the inferred type
//! SHALL be compatible with all possible runtime values.

const std = @import("std");
const testing = std.testing;
const SymbolTable = @import("symbol_table.zig");
const TypeInference = @import("type_inference.zig");
const Diagnostics = @import("diagnostics.zig");

const InferredType = SymbolTable.InferredType;
const ConcreteType = SymbolTable.ConcreteType;
const TypeInferencer = TypeInference.TypeInferencer;
const InferenceNode = TypeInference.InferenceNode;
const NodeTag = TypeInference.NodeTag;
const OperatorKind = TypeInference.OperatorKind;

/// Random number generator for property tests
const Rng = std.Random.DefaultPrng;

/// Test configuration
const TEST_ITERATIONS = 100;

/// Generate a random concrete type
fn randomConcreteType(rng: *Rng) ConcreteType {
    const types = [_]ConcreteType{
        .void,
        .null,
        .bool,
        .int,
        .float,
        .string,
        .array,
        .object,
        .callable,
    };
    return types[rng.random().intRangeAtMost(usize, 0, types.len - 1)];
}

/// Generate a random inferred type
fn randomInferredType(rng: *Rng) InferredType {
    const choice = rng.random().intRangeAtMost(u8, 0, 2);
    return switch (choice) {
        0 => .{ .concrete = randomConcreteType(rng) },
        1 => .dynamic,
        else => .unknown,
    };
}

/// Generate a random arithmetic operator
fn randomArithmeticOp(rng: *Rng) OperatorKind {
    const ops = [_]OperatorKind{
        .add,
        .subtract,
        .multiply,
        .divide,
        .modulo,
    };
    return ops[rng.random().intRangeAtMost(usize, 0, ops.len - 1)];
}

/// Generate a random comparison operator
fn randomComparisonOp(rng: *Rng) OperatorKind {
    const ops = [_]OperatorKind{
        .equal,
        .not_equal,
        .identical,
        .not_identical,
        .less_than,
        .greater_than,
        .less_equal,
        .greater_equal,
    };
    return ops[rng.random().intRangeAtMost(usize, 0, ops.len - 1)];
}

/// Generate a random logical operator
fn randomLogicalOp(rng: *Rng) OperatorKind {
    const ops = [_]OperatorKind{
        .logical_and,
        .logical_or,
        .logical_xor,
    };
    return ops[rng.random().intRangeAtMost(usize, 0, ops.len - 1)];
}

/// Generate a random literal node tag
fn randomLiteralTag(rng: *Rng) NodeTag {
    const tags = [_]NodeTag{
        .literal_int,
        .literal_float,
        .literal_string,
        .literal_bool,
        .literal_null,
    };
    return tags[rng.random().intRangeAtMost(usize, 0, tags.len - 1)];
}

/// Get the expected type for a literal tag
fn expectedTypeForLiteral(tag: NodeTag) ConcreteType {
    return switch (tag) {
        .literal_int => .int,
        .literal_float => .float,
        .literal_string => .string,
        .literal_bool => .bool,
        .literal_null => .null,
        else => unreachable,
    };
}

/// Check if two types are compatible
fn typesCompatible(inferred: InferredType, expected: ConcreteType) bool {
    return switch (inferred) {
        .concrete => |ct| ct == expected,
        .dynamic => true, // Dynamic is compatible with anything
        .unknown => true, // Unknown is compatible with anything
        .union_type => true, // Union types are compatible if they contain the expected type
    };
}

// ============================================================================
// Property Tests
// ============================================================================

// Property 3.1: Literal type inference correctness
// *For any* literal expression, the inferred type SHALL match the literal's type.
test "Property 3.1: Literal type inference correctness" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const tag = randomLiteralTag(&rng);
        const expected_type = expectedTypeForLiteral(tag);

        const node = InferenceNode{
            .tag = tag,
            .int_value = if (tag == .literal_int) rng.random().int(i64) else null,
            .float_value = if (tag == .literal_float) @as(f64, @floatFromInt(rng.random().int(i32))) else null,
        };

        const inferred = inferencer.inferNode(&node);

        // Property: inferred type must match expected type
        try testing.expect(inferred.isConcrete());
        try testing.expectEqual(expected_type, inferred.concrete);
    }
}

// Property 3.2: Comparison operators always return bool
// *For any* comparison expression, the inferred type SHALL be bool.
test "Property 3.2: Comparison operators return bool" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.1, 3.2
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Create nodes array for binary expressions
    var nodes_storage: [3]InferenceNode = undefined;

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const op = randomComparisonOp(&rng);
        const lhs_tag = randomLiteralTag(&rng);
        const rhs_tag = randomLiteralTag(&rng);

        // Set up nodes: [binary_expr, lhs, rhs]
        nodes_storage[0] = InferenceNode{
            .tag = .binary_expr,
            .op = op,
            .children = &[_]u32{ 1, 2 },
        };
        nodes_storage[1] = InferenceNode{ .tag = lhs_tag };
        nodes_storage[2] = InferenceNode{ .tag = rhs_tag };

        inferencer.setNodes(&nodes_storage);

        const inferred = inferencer.inferNode(&nodes_storage[0]);

        // Property: comparison operators always return bool
        try testing.expect(inferred.isConcrete());
        try testing.expectEqual(ConcreteType.bool, inferred.concrete);
    }
}

// Property 3.3: Logical operators always return bool
// *For any* logical expression, the inferred type SHALL be bool.
test "Property 3.3: Logical operators return bool" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.1, 3.2
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var nodes_storage: [3]InferenceNode = undefined;

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const op = randomLogicalOp(&rng);

        nodes_storage[0] = InferenceNode{
            .tag = .binary_expr,
            .op = op,
            .children = &[_]u32{ 1, 2 },
        };
        nodes_storage[1] = InferenceNode{ .tag = .literal_bool };
        nodes_storage[2] = InferenceNode{ .tag = .literal_bool };

        inferencer.setNodes(&nodes_storage);

        const inferred = inferencer.inferNode(&nodes_storage[0]);

        // Property: logical operators always return bool
        try testing.expect(inferred.isConcrete());
        try testing.expectEqual(ConcreteType.bool, inferred.concrete);
    }
}

// Property 3.4: Arithmetic on integers returns int
// *For any* arithmetic expression with two integer operands, the result SHALL be int.
test "Property 3.4: Integer arithmetic returns int" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.1, 3.2, 3.3
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var nodes_storage: [3]InferenceNode = undefined;

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const op = randomArithmeticOp(&rng);

        nodes_storage[0] = InferenceNode{
            .tag = .binary_expr,
            .op = op,
            .children = &[_]u32{ 1, 2 },
        };
        nodes_storage[1] = InferenceNode{ .tag = .literal_int, .int_value = rng.random().int(i64) };
        nodes_storage[2] = InferenceNode{ .tag = .literal_int, .int_value = rng.random().int(i64) };

        inferencer.setNodes(&nodes_storage);

        const inferred = inferencer.inferNode(&nodes_storage[0]);

        // Property: int + int = int
        try testing.expect(inferred.isConcrete());
        try testing.expectEqual(ConcreteType.int, inferred.concrete);
    }
}

// Property 3.5: Arithmetic with float returns float
// *For any* arithmetic expression with at least one float operand, the result SHALL be float.
test "Property 3.5: Float arithmetic returns float" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.1, 3.2, 3.3
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var nodes_storage: [3]InferenceNode = undefined;

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const op = randomArithmeticOp(&rng);
        const use_float_lhs = rng.random().boolean();

        nodes_storage[0] = InferenceNode{
            .tag = .binary_expr,
            .op = op,
            .children = &[_]u32{ 1, 2 },
        };

        // At least one operand is float
        if (use_float_lhs) {
            nodes_storage[1] = InferenceNode{ .tag = .literal_float };
            nodes_storage[2] = InferenceNode{ .tag = if (rng.random().boolean()) .literal_float else .literal_int };
        } else {
            nodes_storage[1] = InferenceNode{ .tag = .literal_int };
            nodes_storage[2] = InferenceNode{ .tag = .literal_float };
        }

        inferencer.setNodes(&nodes_storage);

        const inferred = inferencer.inferNode(&nodes_storage[0]);

        // Property: float + anything = float
        try testing.expect(inferred.isConcrete());
        try testing.expectEqual(ConcreteType.float, inferred.concrete);
    }
}

// Property 3.6: Variable lookup returns declared type
// *For any* variable with a declared type, looking it up SHALL return that type.
test "Property 3.6: Variable lookup returns declared type" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.2, 3.4
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    // Generate random variable names - use separate buffers for each name
    var name_buffers: [TEST_ITERATIONS][16]u8 = undefined;
    var var_names: [TEST_ITERATIONS][]const u8 = undefined;
    var var_types: [TEST_ITERATIONS]ConcreteType = undefined;

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        // Create unique variable name in its own buffer
        const name_slice = std.fmt.bufPrint(&name_buffers[i], "var_{d}", .{i}) catch unreachable;
        var_names[i] = name_slice;

        // Random type
        var_types[i] = randomConcreteType(&rng);

        // Define variable
        try symbol_table.defineVariable(var_names[i], .{ .concrete = var_types[i] }, .{});
    }

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);
    inferencer.setStringTable(&var_names);

    // Verify each variable lookup
    i = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const node = InferenceNode{
            .tag = .variable,
            .string_id = @intCast(i),
        };

        const inferred = inferencer.inferNode(&node);

        // Property: variable lookup returns declared type
        try testing.expect(inferred.isConcrete());
        try testing.expectEqual(var_types[i], inferred.concrete);
    }
}

// Property 3.7: String concatenation returns string
// *For any* concatenation expression, the result SHALL be string.
test "Property 3.7: String concatenation returns string" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var nodes_storage: [3]InferenceNode = undefined;

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        // Concatenation with any operand types
        const lhs_tag = randomLiteralTag(&rng);
        const rhs_tag = randomLiteralTag(&rng);

        nodes_storage[0] = InferenceNode{
            .tag = .binary_expr,
            .op = .concat,
            .children = &[_]u32{ 1, 2 },
        };
        nodes_storage[1] = InferenceNode{ .tag = lhs_tag };
        nodes_storage[2] = InferenceNode{ .tag = rhs_tag };

        inferencer.setNodes(&nodes_storage);

        const inferred = inferencer.inferNode(&nodes_storage[0]);

        // Property: concatenation always returns string
        try testing.expect(inferred.isConcrete());
        try testing.expectEqual(ConcreteType.string, inferred.concrete);
    }
}

// Property 3.8: Built-in function return types
// *For any* call to a built-in function with known return type, the inferred type SHALL match.
test "Property 3.8: Built-in function return types" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.3
    const allocator = testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    // Test known built-in functions
    const test_cases = [_]struct { name: []const u8, expected: ConcreteType }{
        .{ .name = "strlen", .expected = .int },
        .{ .name = "count", .expected = .int },
        .{ .name = "substr", .expected = .string },
        .{ .name = "array_keys", .expected = .array },
        .{ .name = "is_int", .expected = .bool },
        .{ .name = "intval", .expected = .int },
        .{ .name = "floatval", .expected = .float },
        .{ .name = "strval", .expected = .string },
        .{ .name = "boolval", .expected = .bool },
        .{ .name = "time", .expected = .int },
        .{ .name = "date", .expected = .string },
        .{ .name = "file_exists", .expected = .bool },
        .{ .name = "json_encode", .expected = .string },
        .{ .name = "ceil", .expected = .float },
        .{ .name = "floor", .expected = .float },
        .{ .name = "sqrt", .expected = .float },
        .{ .name = "rand", .expected = .int },
    };

    for (test_cases) |tc| {
        const ret_type = TypeInference.getBuiltinReturnType(tc.name);

        // Property: built-in function return type matches expected
        try testing.expect(ret_type != null);
        try testing.expect(ret_type.?.isConcrete());
        try testing.expectEqual(tc.expected, ret_type.?.concrete);
    }
}

// Property 3.9: Dynamic type fallback
// *For any* expression that cannot be statically typed, the inferred type SHALL be dynamic.
test "Property 3.9: Dynamic type fallback" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.4
    const allocator = testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Test nodes that should return dynamic type
    const dynamic_tags = [_]NodeTag{
        .method_call,
        .static_method_call,
        .array_access,
        .property_access,
        .static_property_access,
        .if_stmt,
        .while_stmt,
        .for_stmt,
    };

    for (dynamic_tags) |tag| {
        const node = InferenceNode{ .tag = tag };
        const inferred = inferencer.inferNode(&node);

        // Property: these nodes should return dynamic type
        try testing.expect(inferred.isDynamic());
    }
}

// Property 3.10: Undefined variable returns dynamic
// *For any* variable not in the symbol table, the inferred type SHALL be dynamic.
test "Property 3.10: Undefined variable returns dynamic" {
    // Feature: php-aot-compiler, Property 3: Type inference correctness
    // Validates: Requirements 3.4
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Generate random undefined variable names - use separate buffers
    var name_buffers: [TEST_ITERATIONS][16]u8 = undefined;
    var var_names: [TEST_ITERATIONS][]const u8 = undefined;
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const rand_val = rng.random().int(u32);
        const name_slice = std.fmt.bufPrint(&name_buffers[i], "undef_{d}", .{rand_val}) catch unreachable;
        var_names[i] = name_slice;
    }

    inferencer.setStringTable(&var_names);

    i = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const node = InferenceNode{
            .tag = .variable,
            .string_id = @intCast(i),
        };

        const inferred = inferencer.inferNode(&node);

        // Property: undefined variable returns dynamic
        try testing.expect(inferred.isDynamic());
    }
}
