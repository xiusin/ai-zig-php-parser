//! Type Inference System for AOT Compiler
//!
//! This module provides static type inference for PHP code during AOT compilation.
//! It analyzes AST nodes to determine variable types at compile time, enabling
//! more efficient code generation.
//!
//! ## Features
//!
//! - Literal type inference (int, float, string, bool, null)
//! - Function parameter and return type inference from declarations
//! - Variable type inference from assignments
//! - Dynamic type fallback for unresolvable types
//! - Support for PHP 8.x union types

const std = @import("std");
const Allocator = std.mem.Allocator;
const SymbolTable = @import("symbol_table.zig");
const Symbol = SymbolTable.Symbol;
const InferredType = SymbolTable.InferredType;
const ConcreteType = SymbolTable.ConcreteType;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const SourceLocation = Diagnostics.SourceLocation;

/// AST Node tag enum (mirrors the compiler AST)
pub const NodeTag = enum {
    root,
    attribute,
    class_decl,
    interface_decl,
    trait_decl,
    enum_decl,
    struct_decl,
    property_decl,
    property_hook,
    method_decl,
    parameter,
    const_decl,
    global_stmt,
    static_stmt,
    go_stmt,
    closure,
    arrow_function,
    anonymous_class,
    if_stmt,
    while_stmt,
    for_stmt,
    for_range_stmt,
    foreach_stmt,
    match_expr,
    match_arm,
    try_stmt,
    catch_clause,
    finally_clause,
    throw_stmt,
    method_call,
    property_access,
    array_access,
    function_call,
    function_decl,
    static_method_call,
    static_property_access,
    use_stmt,
    namespace_stmt,
    include_stmt,
    require_stmt,
    block,
    expression_stmt,
    assignment,
    echo_stmt,
    return_stmt,
    break_stmt,
    continue_stmt,
    variable,
    literal_int,
    literal_float,
    literal_string,
    literal_bool,
    literal_null,
    array_init,
    array_pair,
    binary_expr,
    unary_expr,
    postfix_expr,
    ternary_expr,
    unpacking_expr,
    pipe_expr,
    clone_with_expr,
    struct_instantiation,
    object_instantiation,
    trait_use,
    named_type,
    union_type,
    intersection_type,
    class_constant_access,
    self_expr,
    parent_expr,
    static_expr,
};

/// Operator kind for expressions
pub const OperatorKind = enum {
    // Comparison operators
    equal,
    not_equal,
    identical,
    not_identical,
    less_than,
    greater_than,
    less_equal,
    greater_equal,
    spaceship,
    // Logical operators
    logical_and,
    logical_or,
    logical_xor,
    logical_not,
    // Arithmetic operators
    add,
    subtract,
    multiply,
    divide,
    modulo,
    power,
    negate,
    // Bitwise operators
    bitwise_and,
    bitwise_or,
    bitwise_xor,
    bitwise_not,
    shift_left,
    shift_right,
    // String operators
    concat,
    // Other operators
    null_coalesce,
    increment,
    decrement,
    // Unknown
    unknown,
};

/// Type inference context for tracking inference state
pub const TypeContext = struct {
    /// Expected return type for current function
    expected_return: ?InferredType = null,
    /// Whether we're in a loop context
    in_loop: bool = false,
    /// Whether we're in a try block
    in_try: bool = false,
    /// Current class name (if in a class)
    current_class: ?[]const u8 = null,
};

/// Simplified node structure for type inference
pub const InferenceNode = struct {
    tag: NodeTag,
    /// String ID for variable names, type names, etc.
    string_id: ?u32 = null,
    /// Integer value for literals
    int_value: ?i64 = null,
    /// Float value for literals
    float_value: ?f64 = null,
    /// Operator kind for expressions
    op: ?OperatorKind = null,
    /// Child node indices
    children: []const u32 = &.{},
};

/// Type inferencer for PHP AST
pub const TypeInferencer = struct {
    allocator: Allocator,
    symbol_table: *SymbolTable.SymbolTable,
    diagnostics: *DiagnosticEngine,
    /// String table for looking up string IDs
    string_table: ?[]const []const u8,
    /// Inference nodes for looking up node indices
    nodes: ?[]const InferenceNode,
    /// Current inference context
    context: TypeContext,

    const Self = @This();

    /// Initialize a new type inferencer
    pub fn init(
        allocator: Allocator,
        symbol_table: *SymbolTable.SymbolTable,
        diagnostics: *DiagnosticEngine,
    ) Self {
        return .{
            .allocator = allocator,
            .symbol_table = symbol_table,
            .diagnostics = diagnostics,
            .string_table = null,
            .nodes = null,
            .context = .{},
        };
    }

    /// Set the string table for string ID lookups
    pub fn setStringTable(self: *Self, table: []const []const u8) void {
        self.string_table = table;
    }

    /// Set the inference nodes for node index lookups
    pub fn setNodes(self: *Self, nodes: []const InferenceNode) void {
        self.nodes = nodes;
    }

    /// Get a string from the string table
    fn getString(self: *const Self, id: u32) ?[]const u8 {
        if (self.string_table) |table| {
            if (id < table.len) {
                return table[id];
            }
        }
        return null;
    }

    /// Get a node from the nodes array
    fn getNode(self: *const Self, index: u32) ?*const InferenceNode {
        if (self.nodes) |nodes| {
            if (index < nodes.len) {
                return &nodes[index];
            }
        }
        return null;
    }

    /// Infer the type of an AST node
    pub fn inferNode(self: *Self, node: *const InferenceNode) InferredType {
        return switch (node.tag) {
            // Literals
            .literal_int => .{ .concrete = .int },
            .literal_float => .{ .concrete = .float },
            .literal_string => .{ .concrete = .string },
            .literal_bool => .{ .concrete = .bool },
            .literal_null => .{ .concrete = .null },

            // Variables
            .variable => self.inferVariable(node),

            // Expressions
            .binary_expr => self.inferBinaryExpr(node),
            .unary_expr => self.inferUnaryExpr(node),
            .postfix_expr => self.inferPostfixExpr(node),
            .ternary_expr => self.inferTernaryExpr(node),

            // Function calls
            .function_call => self.inferFunctionCall(node),
            .method_call, .static_method_call => .dynamic,

            // Array operations
            .array_init => .{ .concrete = .array },
            .array_access => .dynamic,

            // Object operations
            .object_instantiation => .{ .concrete = .object },
            .property_access, .static_property_access => .dynamic,

            // Closures
            .closure, .arrow_function => .{ .concrete = .callable },

            // Type expressions
            .named_type => self.inferNamedType(node),
            .union_type => self.inferUnionType(node),

            // Special expressions
            .clone_with_expr => .{ .concrete = .object },
            .match_expr => self.inferMatchExpr(node),

            // Default to dynamic for complex/unknown nodes
            else => .dynamic,
        };
    }

    /// Infer type from a variable reference
    fn inferVariable(self: *Self, node: *const InferenceNode) InferredType {
        if (node.string_id) |name_id| {
            if (self.getString(name_id)) |name| {
                if (self.symbol_table.lookup(name)) |sym| {
                    return sym.inferred_type;
                }
            }
        }
        return .dynamic;
    }

    /// Infer type from a binary expression
    fn inferBinaryExpr(self: *Self, node: *const InferenceNode) InferredType {
        const op = node.op orelse return .dynamic;

        // Get operand types
        var lhs_type: InferredType = .dynamic;
        var rhs_type: InferredType = .dynamic;

        if (node.children.len >= 2) {
            if (self.getNode(node.children[0])) |lhs| {
                lhs_type = self.inferNode(lhs);
            }
            if (self.getNode(node.children[1])) |rhs| {
                rhs_type = self.inferNode(rhs);
            }
        }

        // Comparison operators always return bool
        if (isComparisonOp(op)) {
            return .{ .concrete = .bool };
        }

        // Logical operators always return bool
        if (isLogicalOp(op)) {
            return .{ .concrete = .bool };
        }

        // String concatenation
        if (op == .concat) {
            return .{ .concrete = .string };
        }

        // Arithmetic operators
        if (isArithmeticOp(op)) {
            return inferArithmeticResult(lhs_type, rhs_type);
        }

        // Bitwise operators return int
        if (isBitwiseOp(op)) {
            return .{ .concrete = .int };
        }

        // Null coalescing returns the type of the non-null operand
        if (op == .null_coalesce) {
            return inferNullCoalesceResult(lhs_type, rhs_type);
        }

        return .dynamic;
    }

    /// Infer type from a unary expression
    fn inferUnaryExpr(self: *Self, node: *const InferenceNode) InferredType {
        const op = node.op orelse return .dynamic;

        // Logical not returns bool
        if (op == .logical_not) {
            return .{ .concrete = .bool };
        }

        // Bitwise not returns int
        if (op == .bitwise_not) {
            return .{ .concrete = .int };
        }

        // Negation preserves numeric type
        if (op == .negate) {
            if (node.children.len >= 1) {
                if (self.getNode(node.children[0])) |expr| {
                    const expr_type = self.inferNode(expr);
                    if (expr_type == .concrete) {
                        const ct = expr_type.concrete;
                        if (ct == .int or ct == .float) {
                            return expr_type;
                        }
                    }
                }
            }
            return .dynamic;
        }

        return .dynamic;
    }

    /// Infer type from a postfix expression (++, --)
    fn inferPostfixExpr(self: *Self, node: *const InferenceNode) InferredType {
        if (node.children.len >= 1) {
            if (self.getNode(node.children[0])) |expr| {
                const expr_type = self.inferNode(expr);
                // Increment/decrement preserves numeric type
                if (expr_type == .concrete) {
                    const ct = expr_type.concrete;
                    if (ct == .int or ct == .float) {
                        return expr_type;
                    }
                }
            }
        }
        return .dynamic;
    }

    /// Infer type from a ternary expression
    fn inferTernaryExpr(self: *Self, node: *const InferenceNode) InferredType {
        // Children: [condition, then_expr, else_expr]
        if (node.children.len < 3) return .dynamic;

        var then_type: InferredType = .dynamic;
        var else_type: InferredType = .dynamic;

        if (self.getNode(node.children[1])) |then_node| {
            then_type = self.inferNode(then_node);
        }
        if (self.getNode(node.children[2])) |else_node| {
            else_type = self.inferNode(else_node);
        }

        // If both branches have the same concrete type, return that
        if (then_type == .concrete and else_type == .concrete) {
            if (then_type.concrete == else_type.concrete) {
                return then_type;
            }
        }

        return .dynamic;
    }

    /// Infer type from a function call
    fn inferFunctionCall(self: *Self, node: *const InferenceNode) InferredType {
        // Get function name from string_id
        if (node.string_id) |name_id| {
            if (self.getString(name_id)) |name| {
                // Check for built-in functions with known return types
                if (getBuiltinReturnType(name)) |ret_type| {
                    return ret_type;
                }

                // Look up user-defined function
                if (self.symbol_table.lookupFunction(name)) |func_sym| {
                    if (func_sym.metadata == .function) {
                        return func_sym.metadata.function.return_type;
                    }
                    return func_sym.inferred_type;
                }
            }
        }

        return .dynamic;
    }

    /// Infer type from a named type declaration
    fn inferNamedType(self: *Self, node: *const InferenceNode) InferredType {
        if (node.string_id) |name_id| {
            if (self.getString(name_id)) |name| {
                if (ConcreteType.fromString(name)) |ct| {
                    return .{ .concrete = ct };
                }
                // Class type
                return .{ .concrete = .object };
            }
        }
        return .dynamic;
    }

    /// Infer type from a union type declaration
    fn inferUnionType(self: *Self, node: *const InferenceNode) InferredType {
        var concrete_types = std.ArrayListUnmanaged(ConcreteType){};
        errdefer concrete_types.deinit(self.allocator);

        for (node.children) |type_idx| {
            if (self.getNode(type_idx)) |type_node| {
                const inferred = self.inferNode(type_node);
                if (inferred == .concrete) {
                    concrete_types.append(self.allocator, inferred.concrete) catch continue;
                }
            }
        }

        if (concrete_types.items.len == 0) {
            concrete_types.deinit(self.allocator);
            return .dynamic;
        }

        if (concrete_types.items.len == 1) {
            const result = concrete_types.items[0];
            concrete_types.deinit(self.allocator);
            return .{ .concrete = result };
        }

        // Allocate persistent storage for union types
        // Note: This memory is owned by the allocator and should be freed
        // when the type inference context is cleaned up
        const types_slice = self.allocator.dupe(ConcreteType, concrete_types.items) catch {
            concrete_types.deinit(self.allocator);
            return .dynamic;
        };
        concrete_types.deinit(self.allocator);
        return .{ .union_type = types_slice };
    }

    /// Infer type from a match expression
    fn inferMatchExpr(self: *Self, node: *const InferenceNode) InferredType {
        // Try to find a common type among all arms
        var common_type: ?InferredType = null;

        for (node.children) |arm_idx| {
            if (self.getNode(arm_idx)) |arm_node| {
                if (arm_node.tag == .match_arm) {
                    // Match arm body is the last child
                    if (arm_node.children.len > 0) {
                        const body_idx = arm_node.children[arm_node.children.len - 1];
                        if (self.getNode(body_idx)) |body| {
                            const arm_type = self.inferNode(body);
                            if (common_type == null) {
                                common_type = arm_type;
                            } else if (!std.meta.eql(common_type.?, arm_type)) {
                                return .dynamic;
                            }
                        }
                    }
                }
            }
        }

        return common_type orelse .dynamic;
    }

    /// Infer type directly from a tag (for simple cases)
    pub fn inferFromTag(self: *Self, tag: NodeTag) InferredType {
        _ = self;
        return switch (tag) {
            .literal_int => .{ .concrete = .int },
            .literal_float => .{ .concrete = .float },
            .literal_string => .{ .concrete = .string },
            .literal_bool => .{ .concrete = .bool },
            .literal_null => .{ .concrete = .null },
            .array_init => .{ .concrete = .array },
            .closure, .arrow_function => .{ .concrete = .callable },
            .object_instantiation, .clone_with_expr => .{ .concrete = .object },
            else => .dynamic,
        };
    }
};


// ============================================================================
// Helper Functions
// ============================================================================

/// Check if an operator is a comparison operator
fn isComparisonOp(op: OperatorKind) bool {
    return switch (op) {
        .equal,
        .not_equal,
        .identical,
        .not_identical,
        .less_than,
        .greater_than,
        .less_equal,
        .greater_equal,
        .spaceship,
        => true,
        else => false,
    };
}

/// Check if an operator is a logical operator
fn isLogicalOp(op: OperatorKind) bool {
    return switch (op) {
        .logical_and,
        .logical_or,
        .logical_xor,
        => true,
        else => false,
    };
}

/// Check if an operator is an arithmetic operator
fn isArithmeticOp(op: OperatorKind) bool {
    return switch (op) {
        .add,
        .subtract,
        .multiply,
        .divide,
        .modulo,
        .power,
        => true,
        else => false,
    };
}

/// Check if an operator is a bitwise operator
fn isBitwiseOp(op: OperatorKind) bool {
    return switch (op) {
        .bitwise_and,
        .bitwise_or,
        .bitwise_xor,
        .shift_left,
        .shift_right,
        => true,
        else => false,
    };
}

/// Infer the result type of an arithmetic operation
fn inferArithmeticResult(lhs: InferredType, rhs: InferredType) InferredType {
    // If either is dynamic, result is dynamic
    if (lhs.isDynamic() or rhs.isDynamic()) {
        return .dynamic;
    }

    // If either is unknown, result is dynamic
    if (lhs.isUnknown() or rhs.isUnknown()) {
        return .dynamic;
    }

    // Both are concrete
    if (lhs == .concrete and rhs == .concrete) {
        const lhs_ct = lhs.concrete;
        const rhs_ct = rhs.concrete;

        // Float + anything numeric = float
        if (lhs_ct == .float or rhs_ct == .float) {
            return .{ .concrete = .float };
        }

        // Int + int = int
        if (lhs_ct == .int and rhs_ct == .int) {
            return .{ .concrete = .int };
        }

        // String concatenation handled separately
        if (lhs_ct == .string and rhs_ct == .string) {
            return .{ .concrete = .string };
        }
    }

    return .dynamic;
}

/// Infer the result type of null coalescing operator
fn inferNullCoalesceResult(lhs: InferredType, rhs: InferredType) InferredType {
    // If lhs is null, return rhs type
    if (lhs == .concrete and lhs.concrete == .null) {
        return rhs;
    }

    // If both are the same concrete type, return that
    if (lhs == .concrete and rhs == .concrete) {
        if (lhs.concrete == rhs.concrete) {
            return lhs;
        }
    }

    return .dynamic;
}

/// Get the return type of a built-in PHP function
pub fn getBuiltinReturnType(name: []const u8) ?InferredType {
    // String functions
    if (std.mem.eql(u8, name, "strlen")) return .{ .concrete = .int };
    if (std.mem.eql(u8, name, "substr")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "str_replace")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "strtolower")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "strtoupper")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "trim")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "ltrim")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "rtrim")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "sprintf")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "implode")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "join")) return .{ .concrete = .string };

    // Array functions
    if (std.mem.eql(u8, name, "count")) return .{ .concrete = .int };
    if (std.mem.eql(u8, name, "sizeof")) return .{ .concrete = .int };
    if (std.mem.eql(u8, name, "array_keys")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "array_values")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "array_merge")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "array_map")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "array_filter")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "array_slice")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "array_reverse")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "array_unique")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "explode")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "range")) return .{ .concrete = .array };
    if (std.mem.eql(u8, name, "in_array")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "array_key_exists")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "array_search")) return .dynamic; // Can return int, string, or false

    // Math functions
    if (std.mem.eql(u8, name, "abs")) return .dynamic; // int or float
    if (std.mem.eql(u8, name, "ceil")) return .{ .concrete = .float };
    if (std.mem.eql(u8, name, "floor")) return .{ .concrete = .float };
    if (std.mem.eql(u8, name, "round")) return .{ .concrete = .float };
    if (std.mem.eql(u8, name, "max")) return .dynamic;
    if (std.mem.eql(u8, name, "min")) return .dynamic;
    if (std.mem.eql(u8, name, "pow")) return .dynamic;
    if (std.mem.eql(u8, name, "sqrt")) return .{ .concrete = .float };
    if (std.mem.eql(u8, name, "rand")) return .{ .concrete = .int };
    if (std.mem.eql(u8, name, "mt_rand")) return .{ .concrete = .int };

    // Type functions
    if (std.mem.eql(u8, name, "gettype")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "is_int")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_integer")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_float")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_double")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_string")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_bool")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_array")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_object")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_null")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_numeric")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_callable")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "isset")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "empty")) return .{ .concrete = .bool };

    // Conversion functions
    if (std.mem.eql(u8, name, "intval")) return .{ .concrete = .int };
    if (std.mem.eql(u8, name, "floatval")) return .{ .concrete = .float };
    if (std.mem.eql(u8, name, "strval")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "boolval")) return .{ .concrete = .bool };

    // JSON functions
    if (std.mem.eql(u8, name, "json_encode")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "json_decode")) return .dynamic;

    // Date/time functions
    if (std.mem.eql(u8, name, "time")) return .{ .concrete = .int };
    if (std.mem.eql(u8, name, "date")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "strtotime")) return .dynamic; // int or false

    // File functions
    if (std.mem.eql(u8, name, "file_exists")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_file")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "is_dir")) return .{ .concrete = .bool };
    if (std.mem.eql(u8, name, "file_get_contents")) return .{ .concrete = .string };
    if (std.mem.eql(u8, name, "file_put_contents")) return .dynamic; // int or false

    // Output functions
    if (std.mem.eql(u8, name, "print")) return .{ .concrete = .int };
    if (std.mem.eql(u8, name, "printf")) return .{ .concrete = .int };

    return null;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "TypeInferencer literal inference" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Test integer literal
    const int_node = InferenceNode{ .tag = .literal_int, .int_value = 42 };
    const int_type = inferencer.inferNode(&int_node);
    try std.testing.expect(int_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.int, int_type.concrete);

    // Test float literal
    const float_node = InferenceNode{ .tag = .literal_float, .float_value = 3.14 };
    const float_type = inferencer.inferNode(&float_node);
    try std.testing.expect(float_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.float, float_type.concrete);

    // Test string literal
    const string_node = InferenceNode{ .tag = .literal_string, .string_id = 0 };
    const string_type = inferencer.inferNode(&string_node);
    try std.testing.expect(string_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.string, string_type.concrete);

    // Test bool literal
    const bool_node = InferenceNode{ .tag = .literal_bool };
    const bool_type = inferencer.inferNode(&bool_node);
    try std.testing.expect(bool_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.bool, bool_type.concrete);

    // Test null literal
    const null_node = InferenceNode{ .tag = .literal_null };
    const null_type = inferencer.inferNode(&null_node);
    try std.testing.expect(null_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.null, null_type.concrete);
}

test "TypeInferencer array and closure inference" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Test array init
    const array_node = InferenceNode{ .tag = .array_init };
    const array_type = inferencer.inferNode(&array_node);
    try std.testing.expect(array_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.array, array_type.concrete);

    // Test closure
    const closure_node = InferenceNode{ .tag = .closure };
    const closure_type = inferencer.inferNode(&closure_node);
    try std.testing.expect(closure_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.callable, closure_type.concrete);

    // Test arrow function
    const arrow_node = InferenceNode{ .tag = .arrow_function };
    const arrow_type = inferencer.inferNode(&arrow_node);
    try std.testing.expect(arrow_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.callable, arrow_type.concrete);
}

test "TypeInferencer variable lookup" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    // Define a variable
    try symbol_table.defineVariable("x", .{ .concrete = .int }, .{});

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Set up string table
    const strings = [_][]const u8{"x"};
    inferencer.setStringTable(&strings);

    // Test variable lookup
    const var_node = InferenceNode{ .tag = .variable, .string_id = 0 };
    const var_type = inferencer.inferNode(&var_node);
    try std.testing.expect(var_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.int, var_type.concrete);
}

test "TypeInferencer binary expression inference" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Set up nodes for binary expression: 1 + 2
    const nodes = [_]InferenceNode{
        .{ .tag = .binary_expr, .op = .add, .children = &[_]u32{ 1, 2 } },
        .{ .tag = .literal_int, .int_value = 1 },
        .{ .tag = .literal_int, .int_value = 2 },
    };
    inferencer.setNodes(&nodes);

    // Test addition of two ints
    const add_type = inferencer.inferNode(&nodes[0]);
    try std.testing.expect(add_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.int, add_type.concrete);

    // Test comparison operator
    const cmp_nodes = [_]InferenceNode{
        .{ .tag = .binary_expr, .op = .equal, .children = &[_]u32{ 1, 2 } },
        .{ .tag = .literal_int, .int_value = 1 },
        .{ .tag = .literal_int, .int_value = 2 },
    };
    inferencer.setNodes(&cmp_nodes);

    const cmp_type = inferencer.inferNode(&cmp_nodes[0]);
    try std.testing.expect(cmp_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.bool, cmp_type.concrete);
}

test "getBuiltinReturnType" {
    // String functions
    try std.testing.expectEqual(ConcreteType.int, getBuiltinReturnType("strlen").?.concrete);
    try std.testing.expectEqual(ConcreteType.string, getBuiltinReturnType("substr").?.concrete);

    // Array functions
    try std.testing.expectEqual(ConcreteType.int, getBuiltinReturnType("count").?.concrete);
    try std.testing.expectEqual(ConcreteType.array, getBuiltinReturnType("array_keys").?.concrete);
    try std.testing.expectEqual(ConcreteType.bool, getBuiltinReturnType("in_array").?.concrete);

    // Type functions
    try std.testing.expectEqual(ConcreteType.bool, getBuiltinReturnType("is_int").?.concrete);
    try std.testing.expectEqual(ConcreteType.string, getBuiltinReturnType("gettype").?.concrete);

    // Unknown function
    try std.testing.expect(getBuiltinReturnType("unknown_function") == null);
}

test "inferArithmeticResult" {
    // int + int = int
    const int_int = inferArithmeticResult(.{ .concrete = .int }, .{ .concrete = .int });
    try std.testing.expectEqual(ConcreteType.int, int_int.concrete);

    // int + float = float
    const int_float = inferArithmeticResult(.{ .concrete = .int }, .{ .concrete = .float });
    try std.testing.expectEqual(ConcreteType.float, int_float.concrete);

    // float + float = float
    const float_float = inferArithmeticResult(.{ .concrete = .float }, .{ .concrete = .float });
    try std.testing.expectEqual(ConcreteType.float, float_float.concrete);

    // dynamic + anything = dynamic
    const dyn_int = inferArithmeticResult(.dynamic, .{ .concrete = .int });
    try std.testing.expect(dyn_int.isDynamic());
}

test "isComparisonOp" {
    try std.testing.expect(isComparisonOp(.equal));
    try std.testing.expect(isComparisonOp(.not_equal));
    try std.testing.expect(isComparisonOp(.less_than));
    try std.testing.expect(!isComparisonOp(.add));
}

test "isArithmeticOp" {
    try std.testing.expect(isArithmeticOp(.add));
    try std.testing.expect(isArithmeticOp(.subtract));
    try std.testing.expect(isArithmeticOp(.multiply));
    try std.testing.expect(!isArithmeticOp(.equal));
}

test "TypeInferencer inferFromTag" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    try std.testing.expectEqual(ConcreteType.int, inferencer.inferFromTag(.literal_int).concrete);
    try std.testing.expectEqual(ConcreteType.float, inferencer.inferFromTag(.literal_float).concrete);
    try std.testing.expectEqual(ConcreteType.string, inferencer.inferFromTag(.literal_string).concrete);
    try std.testing.expectEqual(ConcreteType.bool, inferencer.inferFromTag(.literal_bool).concrete);
    try std.testing.expectEqual(ConcreteType.null, inferencer.inferFromTag(.literal_null).concrete);
    try std.testing.expectEqual(ConcreteType.array, inferencer.inferFromTag(.array_init).concrete);
    try std.testing.expectEqual(ConcreteType.callable, inferencer.inferFromTag(.closure).concrete);
    try std.testing.expect(inferencer.inferFromTag(.if_stmt).isDynamic());
}


test "TypeInferencer union type inference" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Set up nodes for union type: int|string
    const nodes = [_]InferenceNode{
        .{ .tag = .union_type, .children = &[_]u32{ 1, 2 } },
        .{ .tag = .literal_int },
        .{ .tag = .literal_string },
    };
    inferencer.setNodes(&nodes);

    // Test union type inference
    const union_type = inferencer.inferNode(&nodes[0]);
    try std.testing.expect(union_type == .union_type);
    try std.testing.expectEqual(@as(usize, 2), union_type.union_type.len);
    try std.testing.expectEqual(ConcreteType.int, union_type.union_type[0]);
    try std.testing.expectEqual(ConcreteType.string, union_type.union_type[1]);

    // Clean up allocated union type slice
    allocator.free(union_type.union_type);
}

test "TypeInferencer single type union simplifies to concrete" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    // Set up nodes for single-type union: int (should simplify to concrete int)
    const nodes = [_]InferenceNode{
        .{ .tag = .union_type, .children = &[_]u32{1} },
        .{ .tag = .literal_int },
    };
    inferencer.setNodes(&nodes);

    // Test single type union simplifies to concrete
    const single_type = inferencer.inferNode(&nodes[0]);
    try std.testing.expect(single_type.isConcrete());
    try std.testing.expectEqual(ConcreteType.int, single_type.concrete);
}
