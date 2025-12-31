//! Symbol Table for AOT Compiler
//!
//! This module provides symbol table functionality for the type inference
//! and code generation phases. It manages scopes, symbol registration,
//! and symbol lookup.
//!
//! ## Features
//!
//! - Hierarchical scope management (global, function, block)
//! - Symbol registration with type information
//! - Symbol lookup with scope chain traversal
//! - Support for PHP symbol kinds (variables, functions, classes, constants)

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const Type = IR.Type;
const Diagnostics = @import("diagnostics.zig");
const SourceLocation = Diagnostics.SourceLocation;

/// Inferred type for a symbol
pub const InferredType = union(enum) {
    /// Precise type known at compile time
    concrete: ConcreteType,
    /// Union of multiple possible types
    union_type: []const ConcreteType,
    /// Dynamic type requiring runtime checks
    dynamic: void,
    /// Unknown type (not yet inferred)
    unknown: void,

    /// Check if this type is dynamic
    pub fn isDynamic(self: InferredType) bool {
        return self == .dynamic;
    }

    /// Check if this type is concrete (known at compile time)
    pub fn isConcrete(self: InferredType) bool {
        return self == .concrete;
    }

    /// Check if this type is unknown
    pub fn isUnknown(self: InferredType) bool {
        return self == .unknown;
    }

    /// Convert to IR type
    pub fn toIRType(self: InferredType) Type {
        return switch (self) {
            .concrete => |ct| ct.toIRType(),
            .union_type => .php_value, // Union types use dynamic PHP value
            .dynamic => .php_value,
            .unknown => .php_value,
        };
    }

    /// Format for display
    pub fn format(
        self: InferredType,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .concrete => |ct| try writer.print("{s}", .{ct.toString()}),
            .union_type => |types| {
                for (types, 0..) |t, i| {
                    if (i > 0) try writer.writeAll("|");
                    try writer.print("{s}", .{t.toString()});
                }
            },
            .dynamic => try writer.writeAll("mixed"),
            .unknown => try writer.writeAll("unknown"),
        }
    }
};

/// Concrete PHP types
pub const ConcreteType = enum {
    void,
    null,
    bool,
    int,
    float,
    string,
    array,
    object,
    callable,
    resource,
    iterable,
    never,

    /// Convert to IR type
    pub fn toIRType(self: ConcreteType) Type {
        return switch (self) {
            .void => .void,
            .null => .php_value,
            .bool => .bool,
            .int => .i64,
            .float => .f64,
            .string => .php_string,
            .array => .php_array,
            .object => .{ .php_object = "" },
            .callable => .php_callable,
            .resource => .php_resource,
            .iterable => .php_value,
            .never => .void,
        };
    }

    /// Get string representation
    pub fn toString(self: ConcreteType) []const u8 {
        return switch (self) {
            .void => "void",
            .null => "null",
            .bool => "bool",
            .int => "int",
            .float => "float",
            .string => "string",
            .array => "array",
            .object => "object",
            .callable => "callable",
            .resource => "resource",
            .iterable => "iterable",
            .never => "never",
        };
    }

    /// Parse from PHP type string
    pub fn fromString(str: []const u8) ?ConcreteType {
        if (std.mem.eql(u8, str, "void")) return .void;
        if (std.mem.eql(u8, str, "null")) return .null;
        if (std.mem.eql(u8, str, "bool") or std.mem.eql(u8, str, "boolean")) return .bool;
        if (std.mem.eql(u8, str, "int") or std.mem.eql(u8, str, "integer")) return .int;
        if (std.mem.eql(u8, str, "float") or std.mem.eql(u8, str, "double")) return .float;
        if (std.mem.eql(u8, str, "string")) return .string;
        if (std.mem.eql(u8, str, "array")) return .array;
        if (std.mem.eql(u8, str, "object")) return .object;
        if (std.mem.eql(u8, str, "callable")) return .callable;
        if (std.mem.eql(u8, str, "resource")) return .resource;
        if (std.mem.eql(u8, str, "iterable")) return .iterable;
        if (std.mem.eql(u8, str, "never")) return .never;
        if (std.mem.eql(u8, str, "mixed")) return null; // mixed is dynamic
        return null;
    }
};

/// Kind of symbol
pub const SymbolKind = enum {
    variable,
    function,
    class,
    interface,
    trait,
    constant,
    parameter,
    property,
    method,

    pub fn toString(self: SymbolKind) []const u8 {
        return switch (self) {
            .variable => "variable",
            .function => "function",
            .class => "class",
            .interface => "interface",
            .trait => "trait",
            .constant => "constant",
            .parameter => "parameter",
            .property => "property",
            .method => "method",
        };
    }
};

/// A symbol in the symbol table
pub const Symbol = struct {
    /// Symbol name
    name: []const u8,
    /// Kind of symbol
    kind: SymbolKind,
    /// Inferred type
    inferred_type: InferredType,
    /// Whether this symbol is mutable
    is_mutable: bool,
    /// Whether this symbol has been initialized
    is_initialized: bool,
    /// Source location where the symbol was defined
    location: SourceLocation,
    /// Class name for methods/properties
    class_name: ?[]const u8,
    /// Additional metadata
    metadata: Metadata,

    pub const Metadata = union(enum) {
        none: void,
        function: FunctionMetadata,
        class: ClassMetadata,
        property: PropertyMetadata,
    };

    pub const FunctionMetadata = struct {
        params: []const ParameterInfo,
        return_type: InferredType,
        is_variadic: bool,
    };

    pub const ParameterInfo = struct {
        name: []const u8,
        type_: InferredType,
        has_default: bool,
        is_reference: bool,
    };

    pub const ClassMetadata = struct {
        parent: ?[]const u8,
        interfaces: []const []const u8,
        is_abstract: bool,
        is_final: bool,
    };

    pub const PropertyMetadata = struct {
        visibility: Visibility,
        is_static: bool,
        is_readonly: bool,
    };

    pub const Visibility = enum {
        public,
        protected,
        private,
    };
};

/// A scope in the symbol table
pub const Scope = struct {
    allocator: Allocator,
    /// Symbols in this scope
    symbols: std.StringHashMapUnmanaged(Symbol),
    /// Parent scope (null for global scope)
    parent: ?*Scope,
    /// Scope depth (0 for global)
    depth: u32,
    /// Scope kind
    kind: Kind,
    /// Associated name (function name, class name, etc.)
    name: ?[]const u8,

    pub const Kind = enum {
        global,
        function,
        class,
        block,
        loop,
        conditional,
    };

    const Self = @This();

    /// Initialize a new scope
    pub fn init(allocator: Allocator, parent: ?*Scope, kind: Kind, name: ?[]const u8) Self {
        return .{
            .allocator = allocator,
            .symbols = .{},
            .parent = parent,
            .depth = if (parent) |p| p.depth + 1 else 0,
            .kind = kind,
            .name = name,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.symbols.deinit(self.allocator);
    }

    /// Define a symbol in this scope
    pub fn define(self: *Self, symbol: Symbol) !void {
        try self.symbols.put(self.allocator, symbol.name, symbol);
    }

    /// Look up a symbol in this scope only (not parent scopes)
    pub fn lookupLocal(self: *const Self, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }

    /// Look up a symbol in this scope and parent scopes
    pub fn lookup(self: *const Self, name: []const u8) ?Symbol {
        if (self.symbols.get(name)) |sym| {
            return sym;
        }
        if (self.parent) |parent| {
            return parent.lookup(name);
        }
        return null;
    }

    /// Check if a symbol is defined in this scope only
    pub fn isDefinedLocally(self: *const Self, name: []const u8) bool {
        return self.symbols.contains(name);
    }

    /// Check if a symbol is defined in this scope or parent scopes
    pub fn isDefined(self: *const Self, name: []const u8) bool {
        return self.lookup(name) != null;
    }

    /// Update a symbol's type
    pub fn updateType(self: *Self, name: []const u8, new_type: InferredType) bool {
        if (self.symbols.getPtr(name)) |sym| {
            sym.inferred_type = new_type;
            return true;
        }
        if (self.parent) |parent| {
            return parent.updateType(name, new_type);
        }
        return false;
    }
};


/// Symbol table managing all scopes
pub const SymbolTable = struct {
    allocator: Allocator,
    /// Global scope
    global_scope: *Scope,
    /// Stack of active scopes (current scope is last)
    scope_stack: std.ArrayListUnmanaged(*Scope),
    /// All allocated scopes (for cleanup)
    all_scopes: std.ArrayListUnmanaged(*Scope),
    /// Function symbols (for quick lookup)
    functions: std.StringHashMapUnmanaged(*Symbol),
    /// Class symbols (for quick lookup)
    classes: std.StringHashMapUnmanaged(*Symbol),
    /// Constant symbols (for quick lookup)
    constants: std.StringHashMapUnmanaged(*Symbol),

    const Self = @This();

    /// Initialize a new symbol table
    pub fn init(allocator: Allocator) !Self {
        var self = Self{
            .allocator = allocator,
            .global_scope = undefined,
            .scope_stack = .{},
            .all_scopes = .{},
            .functions = .{},
            .classes = .{},
            .constants = .{},
        };

        // Create global scope
        self.global_scope = try allocator.create(Scope);
        self.global_scope.* = Scope.init(allocator, null, .global, null);
        try self.all_scopes.append(allocator, self.global_scope);
        try self.scope_stack.append(allocator, self.global_scope);

        return self;
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self) void {
        // Free all scopes
        for (self.all_scopes.items) |scope| {
            scope.deinit();
            self.allocator.destroy(scope);
        }
        self.all_scopes.deinit(self.allocator);
        self.scope_stack.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.classes.deinit(self.allocator);
        self.constants.deinit(self.allocator);
    }

    /// Get the current scope
    pub fn currentScope(self: *const Self) *Scope {
        return self.scope_stack.items[self.scope_stack.items.len - 1];
    }

    /// Enter a new scope
    pub fn enterScope(self: *Self, kind: Scope.Kind, name: ?[]const u8) !*Scope {
        const parent = self.currentScope();
        const scope = try self.allocator.create(Scope);
        scope.* = Scope.init(self.allocator, parent, kind, name);
        try self.all_scopes.append(self.allocator, scope);
        try self.scope_stack.append(self.allocator, scope);
        return scope;
    }

    /// Leave the current scope
    pub fn leaveScope(self: *Self) void {
        if (self.scope_stack.items.len > 1) {
            _ = self.scope_stack.pop();
        }
    }

    /// Define a symbol in the current scope
    pub fn define(self: *Self, symbol: Symbol) !void {
        const scope = self.currentScope();
        try scope.define(symbol);

        // Also add to quick lookup tables
        switch (symbol.kind) {
            .function, .method => {
                // Store pointer to the symbol in the scope
                if (scope.symbols.getPtr(symbol.name)) |sym_ptr| {
                    try self.functions.put(self.allocator, symbol.name, sym_ptr);
                }
            },
            .class, .interface, .trait => {
                if (scope.symbols.getPtr(symbol.name)) |sym_ptr| {
                    try self.classes.put(self.allocator, symbol.name, sym_ptr);
                }
            },
            .constant => {
                if (scope.symbols.getPtr(symbol.name)) |sym_ptr| {
                    try self.constants.put(self.allocator, symbol.name, sym_ptr);
                }
            },
            else => {},
        }
    }

    /// Define a variable in the current scope
    pub fn defineVariable(
        self: *Self,
        name: []const u8,
        inferred_type: InferredType,
        location: SourceLocation,
    ) !void {
        try self.define(.{
            .name = name,
            .kind = .variable,
            .inferred_type = inferred_type,
            .is_mutable = true,
            .is_initialized = true,
            .location = location,
            .class_name = null,
            .metadata = .none,
        });
    }

    /// Define a function in the global scope
    pub fn defineFunction(
        self: *Self,
        name: []const u8,
        params: []const Symbol.ParameterInfo,
        return_type: InferredType,
        location: SourceLocation,
    ) !void {
        const symbol = Symbol{
            .name = name,
            .kind = .function,
            .inferred_type = return_type,
            .is_mutable = false,
            .is_initialized = true,
            .location = location,
            .class_name = null,
            .metadata = .{ .function = .{
                .params = params,
                .return_type = return_type,
                .is_variadic = false,
            } },
        };
        try self.global_scope.define(symbol);
        if (self.global_scope.symbols.getPtr(name)) |sym_ptr| {
            try self.functions.put(self.allocator, name, sym_ptr);
        }
    }

    /// Define a class in the global scope
    pub fn defineClass(
        self: *Self,
        name: []const u8,
        parent: ?[]const u8,
        interfaces: []const []const u8,
        location: SourceLocation,
    ) !void {
        const symbol = Symbol{
            .name = name,
            .kind = .class,
            .inferred_type = .{ .concrete = .object },
            .is_mutable = false,
            .is_initialized = true,
            .location = location,
            .class_name = null,
            .metadata = .{ .class = .{
                .parent = parent,
                .interfaces = interfaces,
                .is_abstract = false,
                .is_final = false,
            } },
        };
        try self.global_scope.define(symbol);
        if (self.global_scope.symbols.getPtr(name)) |sym_ptr| {
            try self.classes.put(self.allocator, name, sym_ptr);
        }
    }

    /// Define a constant
    pub fn defineConstant(
        self: *Self,
        name: []const u8,
        inferred_type: InferredType,
        location: SourceLocation,
    ) !void {
        const symbol = Symbol{
            .name = name,
            .kind = .constant,
            .inferred_type = inferred_type,
            .is_mutable = false,
            .is_initialized = true,
            .location = location,
            .class_name = null,
            .metadata = .none,
        };
        try self.global_scope.define(symbol);
        if (self.global_scope.symbols.getPtr(name)) |sym_ptr| {
            try self.constants.put(self.allocator, name, sym_ptr);
        }
    }

    /// Look up a symbol by name (searches all scopes)
    pub fn lookup(self: *const Self, name: []const u8) ?Symbol {
        return self.currentScope().lookup(name);
    }

    /// Look up a symbol in the current scope only
    pub fn lookupLocal(self: *const Self, name: []const u8) ?Symbol {
        return self.currentScope().lookupLocal(name);
    }

    /// Look up a function by name
    pub fn lookupFunction(self: *const Self, name: []const u8) ?*Symbol {
        return self.functions.get(name);
    }

    /// Look up a class by name
    pub fn lookupClass(self: *const Self, name: []const u8) ?*Symbol {
        return self.classes.get(name);
    }

    /// Look up a constant by name
    pub fn lookupConstant(self: *const Self, name: []const u8) ?*Symbol {
        return self.constants.get(name);
    }

    /// Check if a symbol is defined
    pub fn isDefined(self: *const Self, name: []const u8) bool {
        return self.currentScope().isDefined(name);
    }

    /// Check if a symbol is defined in the current scope only
    pub fn isDefinedLocally(self: *const Self, name: []const u8) bool {
        return self.currentScope().isDefinedLocally(name);
    }

    /// Update a symbol's type
    pub fn updateType(self: *Self, name: []const u8, new_type: InferredType) bool {
        return self.currentScope().updateType(name, new_type);
    }

    /// Get the current scope depth
    pub fn depth(self: *const Self) u32 {
        return self.currentScope().depth;
    }

    /// Check if we're in global scope
    pub fn isGlobalScope(self: *const Self) bool {
        return self.currentScope().depth == 0;
    }

    /// Check if we're in a function scope
    pub fn isInFunction(self: *const Self) bool {
        var scope: ?*Scope = self.currentScope();
        while (scope) |s| {
            if (s.kind == .function) return true;
            scope = s.parent;
        }
        return false;
    }

    /// Get the enclosing function scope
    pub fn getEnclosingFunction(self: *const Self) ?*Scope {
        var scope: ?*Scope = self.currentScope();
        while (scope) |s| {
            if (s.kind == .function) return s;
            scope = s.parent;
        }
        return null;
    }

    /// Get the enclosing class scope
    pub fn getEnclosingClass(self: *const Self) ?*Scope {
        var scope: ?*Scope = self.currentScope();
        while (scope) |s| {
            if (s.kind == .class) return s;
            scope = s.parent;
        }
        return null;
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "SymbolTable basic operations" {
    const allocator = std.testing.allocator;

    var table = try SymbolTable.init(allocator);
    defer table.deinit();

    // Define a variable
    try table.defineVariable("x", .{ .concrete = .int }, .{});

    // Look up the variable
    const sym = table.lookup("x");
    try std.testing.expect(sym != null);
    try std.testing.expectEqualStrings("x", sym.?.name);
    try std.testing.expectEqual(SymbolKind.variable, sym.?.kind);
}

test "SymbolTable scope management" {
    const allocator = std.testing.allocator;

    var table = try SymbolTable.init(allocator);
    defer table.deinit();

    // Define in global scope
    try table.defineVariable("global_var", .{ .concrete = .int }, .{});

    // Enter function scope
    _ = try table.enterScope(.function, "test_func");

    // Define in function scope
    try table.defineVariable("local_var", .{ .concrete = .string }, .{});

    // Both should be visible
    try std.testing.expect(table.lookup("global_var") != null);
    try std.testing.expect(table.lookup("local_var") != null);

    // Only local_var should be in current scope
    try std.testing.expect(!table.isDefinedLocally("global_var"));
    try std.testing.expect(table.isDefinedLocally("local_var"));

    // Leave function scope
    table.leaveScope();

    // Only global_var should be visible now
    try std.testing.expect(table.lookup("global_var") != null);
    try std.testing.expect(table.lookup("local_var") == null);
}

test "SymbolTable function definition" {
    const allocator = std.testing.allocator;

    var table = try SymbolTable.init(allocator);
    defer table.deinit();

    // Define a function
    try table.defineFunction(
        "add",
        &[_]Symbol.ParameterInfo{
            .{ .name = "a", .type_ = .{ .concrete = .int }, .has_default = false, .is_reference = false },
            .{ .name = "b", .type_ = .{ .concrete = .int }, .has_default = false, .is_reference = false },
        },
        .{ .concrete = .int },
        .{},
    );

    // Look up the function
    const func = table.lookupFunction("add");
    try std.testing.expect(func != null);
    try std.testing.expectEqual(SymbolKind.function, func.?.kind);
}

test "SymbolTable class definition" {
    const allocator = std.testing.allocator;

    var table = try SymbolTable.init(allocator);
    defer table.deinit();

    // Define a class
    try table.defineClass("MyClass", null, &.{}, .{});

    // Look up the class
    const class = table.lookupClass("MyClass");
    try std.testing.expect(class != null);
    try std.testing.expectEqual(SymbolKind.class, class.?.kind);
}

test "SymbolTable nested scopes" {
    const allocator = std.testing.allocator;

    var table = try SymbolTable.init(allocator);
    defer table.deinit();

    try std.testing.expectEqual(@as(u32, 0), table.depth());
    try std.testing.expect(table.isGlobalScope());

    _ = try table.enterScope(.function, "func");
    try std.testing.expectEqual(@as(u32, 1), table.depth());
    try std.testing.expect(!table.isGlobalScope());
    try std.testing.expect(table.isInFunction());

    _ = try table.enterScope(.block, null);
    try std.testing.expectEqual(@as(u32, 2), table.depth());

    table.leaveScope();
    try std.testing.expectEqual(@as(u32, 1), table.depth());

    table.leaveScope();
    try std.testing.expectEqual(@as(u32, 0), table.depth());
}

test "InferredType conversion" {
    const int_type = InferredType{ .concrete = .int };
    try std.testing.expect(int_type.isConcrete());
    try std.testing.expect(!int_type.isDynamic());

    const ir_type = int_type.toIRType();
    try std.testing.expectEqual(Type.i64, ir_type);

    const dynamic_type = InferredType{ .dynamic = {} };
    try std.testing.expect(dynamic_type.isDynamic());
    try std.testing.expect(!dynamic_type.isConcrete());
}

test "ConcreteType fromString" {
    try std.testing.expectEqual(ConcreteType.int, ConcreteType.fromString("int").?);
    try std.testing.expectEqual(ConcreteType.int, ConcreteType.fromString("integer").?);
    try std.testing.expectEqual(ConcreteType.float, ConcreteType.fromString("float").?);
    try std.testing.expectEqual(ConcreteType.float, ConcreteType.fromString("double").?);
    try std.testing.expectEqual(ConcreteType.string, ConcreteType.fromString("string").?);
    try std.testing.expectEqual(ConcreteType.bool, ConcreteType.fromString("bool").?);
    try std.testing.expectEqual(ConcreteType.bool, ConcreteType.fromString("boolean").?);
    try std.testing.expect(ConcreteType.fromString("mixed") == null);
    try std.testing.expect(ConcreteType.fromString("unknown_type") == null);
}

test "Symbol type update" {
    const allocator = std.testing.allocator;

    var table = try SymbolTable.init(allocator);
    defer table.deinit();

    // Define a variable with unknown type
    try table.defineVariable("x", .unknown, .{});

    // Update the type
    const updated = table.updateType("x", .{ .concrete = .int });
    try std.testing.expect(updated);

    // Verify the update
    const sym = table.lookup("x");
    try std.testing.expect(sym != null);
    try std.testing.expect(sym.?.inferred_type.isConcrete());
}
