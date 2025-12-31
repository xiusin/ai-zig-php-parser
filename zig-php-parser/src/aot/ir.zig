//! Intermediate Representation (IR) for AOT Compiler
//!
//! This module defines the IR data structures used as an intermediate step
//! between the AST and LLVM code generation. The IR is in SSA (Static Single
//! Assignment) form to facilitate optimization and code generation.
//!
//! ## IR Structure
//!
//! - Module: Top-level container for a compilation unit
//! - Function: A PHP function or method
//! - BasicBlock: A sequence of instructions with a single entry and exit
//! - Instruction: A single operation in SSA form
//! - Register: An SSA value (assigned exactly once)
//! - Type: IR type system mapping PHP types

const std = @import("std");
const Allocator = std.mem.Allocator;
const Diagnostics = @import("diagnostics.zig");
const SourceLocation = Diagnostics.SourceLocation;

/// A compilation unit containing functions, globals, and type definitions
pub const Module = struct {
    allocator: Allocator,
    /// Module name (typically the source file name)
    name: []const u8,
    /// Source file path
    source_file: []const u8,
    /// All functions in this module
    functions: std.ArrayListUnmanaged(*Function),
    /// Global variables
    globals: std.ArrayListUnmanaged(*Global),
    /// Type definitions (classes, interfaces, etc.)
    types: std.ArrayListUnmanaged(*TypeDef),
    /// String table for interned strings
    string_table: std.ArrayListUnmanaged([]const u8),

    const Self = @This();

    /// Initialize a new module
    pub fn init(allocator: Allocator, name: []const u8, source_file: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .source_file = source_file,
            .functions = .{},
            .globals = .{},
            .types = .{},
            .string_table = .{},
        };
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self) void {
        // Free functions
        for (self.functions.items) |func| {
            func.deinit();
            self.allocator.destroy(func);
        }
        self.functions.deinit(self.allocator);

        // Free globals
        for (self.globals.items) |global| {
            self.allocator.destroy(global);
        }
        self.globals.deinit(self.allocator);

        // Free type definitions
        for (self.types.items) |type_def| {
            self.allocator.destroy(type_def);
        }
        self.types.deinit(self.allocator);

        // Free string table
        self.string_table.deinit(self.allocator);
    }

    /// Add a function to the module
    pub fn addFunction(self: *Self, func: *Function) !void {
        try self.functions.append(self.allocator, func);
    }

    /// Add a global variable to the module
    pub fn addGlobal(self: *Self, global: *Global) !void {
        try self.globals.append(self.allocator, global);
    }

    /// Add a type definition to the module
    pub fn addTypeDef(self: *Self, type_def: *TypeDef) !void {
        try self.types.append(self.allocator, type_def);
    }

    /// Intern a string and return its ID
    pub fn internString(self: *Self, str: []const u8) !u32 {
        // Check if string already exists
        for (self.string_table.items, 0..) |existing, i| {
            if (std.mem.eql(u8, existing, str)) {
                return @intCast(i);
            }
        }
        // Add new string
        try self.string_table.append(self.allocator, str);
        return @intCast(self.string_table.items.len - 1);
    }

    /// Get a string by its ID
    pub fn getString(self: *const Self, id: u32) ?[]const u8 {
        if (id < self.string_table.items.len) {
            return self.string_table.items[id];
        }
        return null;
    }

    /// Find a function by name
    pub fn findFunction(self: *const Self, name: []const u8) ?*Function {
        for (self.functions.items) |func| {
            if (std.mem.eql(u8, func.name, name)) {
                return func;
            }
        }
        return null;
    }
};

/// A global variable definition
pub const Global = struct {
    /// Variable name
    name: []const u8,
    /// Variable type
    type_: Type,
    /// Initial value (if any)
    initializer: ?*Instruction,
    /// Whether this is a constant
    is_constant: bool,
    /// Source location
    location: SourceLocation,
};

/// A type definition (class, interface, trait)
pub const TypeDef = struct {
    /// Type name
    name: []const u8,
    /// Kind of type
    kind: Kind,
    /// Parent type (for inheritance)
    parent: ?[]const u8,
    /// Implemented interfaces
    interfaces: []const []const u8,
    /// Properties
    properties: []const Property,
    /// Methods (references to functions)
    methods: []const []const u8,
    /// Source location
    location: SourceLocation,

    pub const Kind = enum {
        class,
        interface,
        trait,
        @"enum",
        @"struct",
    };

    pub const Property = struct {
        name: []const u8,
        type_: Type,
        default_value: ?*Instruction,
        is_static: bool,
        visibility: Visibility,
    };

    pub const Visibility = enum {
        public,
        protected,
        private,
    };
};

/// A function in the IR
pub const Function = struct {
    allocator: Allocator,
    /// Function name
    name: []const u8,
    /// Function parameters
    params: std.ArrayListUnmanaged(Parameter),
    /// Return type
    return_type: Type,
    /// Basic blocks (first block is entry)
    blocks: std.ArrayListUnmanaged(*BasicBlock),
    /// Whether this function is exported (callable from outside)
    is_exported: bool,
    /// Whether this is a method
    is_method: bool,
    /// Class name if this is a method
    class_name: ?[]const u8,
    /// Source location
    location: SourceLocation,
    /// Next register ID for SSA
    next_register_id: u32,

    const Self = @This();

    /// Initialize a new function
    pub fn init(allocator: Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .params = .{},
            .return_type = .void,
            .blocks = .{},
            .is_exported = false,
            .is_method = false,
            .class_name = null,
            .location = .{},
            .next_register_id = 0,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.params.deinit(self.allocator);
        for (self.blocks.items) |block| {
            block.deinit();
            self.allocator.destroy(block);
        }
        self.blocks.deinit(self.allocator);
    }

    /// Add a parameter
    pub fn addParam(self: *Self, param: Parameter) !void {
        try self.params.append(self.allocator, param);
    }

    /// Create a new basic block
    pub fn createBlock(self: *Self, label: []const u8) !*BasicBlock {
        const block = try self.allocator.create(BasicBlock);
        block.* = BasicBlock.init(self.allocator, label);
        try self.blocks.append(self.allocator, block);
        return block;
    }

    /// Get the entry block
    pub fn getEntryBlock(self: *const Self) ?*BasicBlock {
        if (self.blocks.items.len > 0) {
            return self.blocks.items[0];
        }
        return null;
    }

    /// Allocate a new register
    pub fn newRegister(self: *Self, type_: Type) Register {
        const reg = Register{
            .id = self.next_register_id,
            .type_ = type_,
        };
        self.next_register_id += 1;
        return reg;
    }
};

/// A function parameter
pub const Parameter = struct {
    /// Parameter name
    name: []const u8,
    /// Parameter type
    type_: Type,
    /// Whether this parameter has a default value
    has_default: bool,
    /// Whether this is a variadic parameter
    is_variadic: bool,
    /// Whether this is passed by reference
    is_reference: bool,
};

/// A basic block - a sequence of instructions with single entry/exit
pub const BasicBlock = struct {
    allocator: Allocator,
    /// Block label (for jumps)
    label: []const u8,
    /// Instructions in this block
    instructions: std.ArrayListUnmanaged(*Instruction),
    /// Block terminator (branch, return, etc.)
    terminator: ?Terminator,
    /// Predecessor blocks (for phi nodes)
    predecessors: std.ArrayListUnmanaged(*BasicBlock),
    /// Successor blocks
    successors: std.ArrayListUnmanaged(*BasicBlock),

    const Self = @This();

    /// Initialize a new basic block
    pub fn init(allocator: Allocator, label: []const u8) Self {
        return .{
            .allocator = allocator,
            .label = label,
            .instructions = .{},
            .terminator = null,
            .predecessors = .{},
            .successors = .{},
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        for (self.instructions.items) |inst| {
            self.allocator.destroy(inst);
        }
        self.instructions.deinit(self.allocator);
        self.predecessors.deinit(self.allocator);
        self.successors.deinit(self.allocator);
    }

    /// Append an instruction to this block
    pub fn appendInstruction(self: *Self, inst: *Instruction) !void {
        try self.instructions.append(self.allocator, inst);
    }

    /// Set the terminator for this block
    pub fn setTerminator(self: *Self, term: Terminator) void {
        self.terminator = term;
    }

    /// Check if this block is terminated
    pub fn isTerminated(self: *const Self) bool {
        return self.terminator != null;
    }

    /// Add a predecessor block
    pub fn addPredecessor(self: *Self, pred: *BasicBlock) !void {
        try self.predecessors.append(self.allocator, pred);
    }

    /// Add a successor block
    pub fn addSuccessor(self: *Self, succ: *BasicBlock) !void {
        try self.successors.append(self.allocator, succ);
    }
};


/// An SSA register (value)
pub const Register = struct {
    /// Unique register ID within a function
    id: u32,
    /// Type of the value in this register
    type_: Type,

    /// Format register for display
    pub fn format(
        self: Register,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("%{d}", .{self.id});
    }

    /// Check if two registers are equal
    pub fn eql(self: Register, other: Register) bool {
        return self.id == other.id;
    }
};

/// Block terminator - how control flow leaves a basic block
pub const Terminator = union(enum) {
    /// Return from function
    ret: ?Register,
    /// Unconditional branch
    br: *BasicBlock,
    /// Conditional branch
    cond_br: struct {
        cond: Register,
        then_block: *BasicBlock,
        else_block: *BasicBlock,
    },
    /// Switch statement
    switch_: struct {
        value: Register,
        cases: []const SwitchCase,
        default: *BasicBlock,
    },
    /// Unreachable (for dead code)
    unreachable_: void,
    /// Throw exception
    throw: Register,

    pub const SwitchCase = struct {
        value: i64,
        block: *BasicBlock,
    };
};

/// IR Type system
pub const Type = union(enum) {
    /// Void type (no value)
    void: void,
    /// Boolean type
    bool: void,
    /// 64-bit signed integer
    i64: void,
    /// 64-bit floating point
    f64: void,
    /// Pointer to another type
    ptr: *const Type,
    /// Dynamic PHP value (tagged union)
    php_value: void,
    /// PHP string
    php_string: void,
    /// PHP array
    php_array: void,
    /// PHP object with class name
    php_object: []const u8,
    /// PHP resource
    php_resource: void,
    /// PHP callable
    php_callable: void,
    /// Function type
    function: FunctionType,
    /// Nullable type
    nullable: *const Type,

    pub const FunctionType = struct {
        params: []const Type,
        return_type: *const Type,
    };

    /// Check if this type is a PHP dynamic type
    pub fn isDynamic(self: Type) bool {
        return switch (self) {
            .php_value, .php_string, .php_array, .php_object, .php_resource, .php_callable => true,
            else => false,
        };
    }

    /// Check if this type is a primitive type
    pub fn isPrimitive(self: Type) bool {
        return switch (self) {
            .void, .bool, .i64, .f64 => true,
            else => false,
        };
    }

    /// Get the size of this type in bytes (for code generation)
    pub fn sizeOf(self: Type) usize {
        return switch (self) {
            .void => 0,
            .bool => 1,
            .i64 => 8,
            .f64 => 8,
            .ptr => 8, // 64-bit pointers
            .php_value => 24, // tag + data + refcount
            .php_string => 8, // pointer
            .php_array => 8, // pointer
            .php_object => 8, // pointer
            .php_resource => 8, // pointer
            .php_callable => 8, // pointer
            .function => 8, // function pointer
            .nullable => |inner| inner.sizeOf(),
        };
    }

    /// Format type for display
    pub fn format(
        self: Type,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .void => try writer.writeAll("void"),
            .bool => try writer.writeAll("bool"),
            .i64 => try writer.writeAll("i64"),
            .f64 => try writer.writeAll("f64"),
            .ptr => |inner| {
                try writer.writeAll("*");
                try inner.format("", .{}, writer);
            },
            .php_value => try writer.writeAll("PHPValue"),
            .php_string => try writer.writeAll("PHPString"),
            .php_array => try writer.writeAll("PHPArray"),
            .php_object => |name| try writer.print("PHPObject<{s}>", .{name}),
            .php_resource => try writer.writeAll("PHPResource"),
            .php_callable => try writer.writeAll("PHPCallable"),
            .function => try writer.writeAll("fn(...)"),
            .nullable => |inner| {
                try writer.writeAll("?");
                try inner.format("", .{}, writer);
            },
        }
    }
};

/// An SSA instruction
pub const Instruction = struct {
    /// Result register (null for void operations)
    result: ?Register,
    /// Operation
    op: Op,
    /// Source location for debugging
    location: SourceLocation,

    /// Instruction operations
    pub const Op = union(enum) {
        // ============ Arithmetic Operations ============
        /// Integer/float addition
        add: BinaryOp,
        /// Integer/float subtraction
        sub: BinaryOp,
        /// Integer/float multiplication
        mul: BinaryOp,
        /// Integer/float division
        div: BinaryOp,
        /// Integer modulo
        mod: BinaryOp,
        /// Negation
        neg: UnaryOp,
        /// Power (exponentiation)
        pow: BinaryOp,

        // ============ Bitwise Operations ============
        /// Bitwise AND
        bit_and: BinaryOp,
        /// Bitwise OR
        bit_or: BinaryOp,
        /// Bitwise XOR
        bit_xor: BinaryOp,
        /// Bitwise NOT
        bit_not: UnaryOp,
        /// Left shift
        shl: BinaryOp,
        /// Right shift
        shr: BinaryOp,

        // ============ Comparison Operations ============
        /// Equal
        eq: BinaryOp,
        /// Not equal
        ne: BinaryOp,
        /// Less than
        lt: BinaryOp,
        /// Less than or equal
        le: BinaryOp,
        /// Greater than
        gt: BinaryOp,
        /// Greater than or equal
        ge: BinaryOp,
        /// Identical (===)
        identical: BinaryOp,
        /// Not identical (!==)
        not_identical: BinaryOp,
        /// Spaceship operator (<=>)
        spaceship: BinaryOp,

        // ============ Logical Operations ============
        /// Logical AND
        and_: BinaryOp,
        /// Logical OR
        or_: BinaryOp,
        /// Logical NOT
        not: UnaryOp,

        // ============ Memory Operations ============
        /// Allocate stack space
        alloca: AllocaOp,
        /// Load from memory
        load: LoadOp,
        /// Store to memory
        store: StoreOp,

        // ============ Constants ============
        /// Integer constant
        const_int: i64,
        /// Float constant
        const_float: f64,
        /// Boolean constant
        const_bool: bool,
        /// String constant (string table ID)
        const_string: u32,
        /// Null constant
        const_null: void,

        // ============ Function Operations ============
        /// Function call
        call: CallOp,
        /// Indirect call (through function pointer)
        call_indirect: CallIndirectOp,

        // ============ Type Operations ============
        /// Type cast
        cast: CastOp,
        /// Runtime type check
        type_check: TypeCheckOp,
        /// Get type tag of PHP value
        get_type: UnaryOp,

        // ============ PHP Array Operations ============
        /// Create new array
        array_new: ArrayNewOp,
        /// Get array element
        array_get: ArrayGetOp,
        /// Set array element
        array_set: ArraySetOp,
        /// Push to array
        array_push: ArrayPushOp,
        /// Get array count
        array_count: UnaryOp,
        /// Check if key exists
        array_key_exists: ArrayKeyExistsOp,
        /// Unset array element
        array_unset: ArrayUnsetOp,

        // ============ PHP String Operations ============
        /// String concatenation
        concat: BinaryOp,
        /// Get string length
        strlen: UnaryOp,
        /// String interpolation
        interpolate: InterpolateOp,

        // ============ PHP Object Operations ============
        /// Create new object
        new_object: NewObjectOp,
        /// Get object property
        property_get: PropertyGetOp,
        /// Set object property
        property_set: PropertySetOp,
        /// Call object method
        method_call: MethodCallOp,
        /// Clone object
        clone: UnaryOp,
        /// Check instanceof
        instanceof: InstanceofOp,

        // ============ PHP Value Operations ============
        /// Create PHP value from primitive
        box: BoxOp,
        /// Extract primitive from PHP value
        unbox: UnboxOp,
        /// Increment reference count
        retain: UnaryOp,
        /// Decrement reference count
        release: UnaryOp,

        // ============ Control Flow ============
        /// Phi node (SSA)
        phi: PhiOp,
        /// Select (conditional move)
        select: SelectOp,

        // ============ Exception Handling ============
        /// Begin try block
        try_begin: void,
        /// End try block
        try_end: void,
        /// Catch exception
        catch_: CatchOp,
        /// Get current exception
        get_exception: void,
        /// Clear current exception
        clear_exception: void,

        // ============ Debugging ============
        /// Debug print
        debug_print: UnaryOp,
    };

    /// Binary operation operands
    pub const BinaryOp = struct {
        lhs: Register,
        rhs: Register,
    };

    /// Unary operation operand
    pub const UnaryOp = struct {
        operand: Register,
    };

    /// Stack allocation
    pub const AllocaOp = struct {
        type_: Type,
        count: u32, // Number of elements (for arrays)
    };

    /// Load from memory
    pub const LoadOp = struct {
        ptr: Register,
        type_: Type,
    };

    /// Store to memory
    pub const StoreOp = struct {
        ptr: Register,
        value: Register,
    };

    /// Function call
    pub const CallOp = struct {
        /// Function name
        func_name: []const u8,
        /// Arguments
        args: []const Register,
        /// Return type
        return_type: Type,
    };

    /// Indirect function call
    pub const CallIndirectOp = struct {
        /// Function pointer
        func_ptr: Register,
        /// Arguments
        args: []const Register,
        /// Return type
        return_type: Type,
    };

    /// Type cast
    pub const CastOp = struct {
        value: Register,
        from_type: Type,
        to_type: Type,
    };

    /// Runtime type check
    pub const TypeCheckOp = struct {
        value: Register,
        expected_type: Type,
    };

    /// Create new array
    pub const ArrayNewOp = struct {
        /// Initial capacity
        capacity: u32,
    };

    /// Array get operation
    pub const ArrayGetOp = struct {
        array: Register,
        key: Register,
    };

    /// Array set operation
    pub const ArraySetOp = struct {
        array: Register,
        key: Register,
        value: Register,
    };

    /// Array push operation
    pub const ArrayPushOp = struct {
        array: Register,
        value: Register,
    };

    /// Array key exists check
    pub const ArrayKeyExistsOp = struct {
        array: Register,
        key: Register,
    };

    /// Array unset operation
    pub const ArrayUnsetOp = struct {
        array: Register,
        key: Register,
    };

    /// String interpolation
    pub const InterpolateOp = struct {
        parts: []const Register,
    };

    /// Create new object
    pub const NewObjectOp = struct {
        class_name: []const u8,
        args: []const Register,
    };

    /// Property get operation
    pub const PropertyGetOp = struct {
        object: Register,
        property_name: []const u8,
    };

    /// Property set operation
    pub const PropertySetOp = struct {
        object: Register,
        property_name: []const u8,
        value: Register,
    };

    /// Method call operation
    pub const MethodCallOp = struct {
        object: Register,
        method_name: []const u8,
        args: []const Register,
    };

    /// Instanceof check
    pub const InstanceofOp = struct {
        object: Register,
        class_name: []const u8,
    };

    /// Box primitive to PHP value
    pub const BoxOp = struct {
        value: Register,
        from_type: Type,
    };

    /// Unbox PHP value to primitive
    pub const UnboxOp = struct {
        value: Register,
        to_type: Type,
    };

    /// Phi node for SSA
    pub const PhiOp = struct {
        /// Incoming values from predecessor blocks
        incoming: []const PhiIncoming,
    };

    pub const PhiIncoming = struct {
        value: Register,
        block: *BasicBlock,
    };

    /// Select operation (conditional move)
    pub const SelectOp = struct {
        cond: Register,
        then_value: Register,
        else_value: Register,
    };

    /// Catch exception
    pub const CatchOp = struct {
        exception_type: ?[]const u8,
    };
};


// ============================================================================
// IR Serialization / Pretty Printing (for --dump-ir)
// ============================================================================

/// IR Printer for debugging and --dump-ir output
pub const IRPrinter = struct {
    list: *std.ArrayListUnmanaged(u8),
    allocator: Allocator,
    indent_level: u32,

    const Self = @This();

    /// Initialize printer with an ArrayListUnmanaged and allocator
    pub fn initUnmanaged(list: *std.ArrayListUnmanaged(u8), allocator: Allocator) Self {
        return .{
            .list = list,
            .allocator = allocator,
            .indent_level = 0,
        };
    }

    /// Write bytes to the list
    fn write(self: *Self, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    /// Write a formatted string
    fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        var buf: [1024]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, fmt, args) catch |err| switch (err) {
            error.NoSpaceLeft => {
                // For larger strings, allocate
                const str = try std.fmt.allocPrint(self.allocator, fmt, args);
                defer self.allocator.free(str);
                try self.list.appendSlice(self.allocator, str);
                return;
            },
        };
        try self.list.appendSlice(self.allocator, result);
    }

    /// Print entire module
    pub fn printModule(self: *Self, module: *const Module) !void {
        try self.print("; Module: {s}\n", .{module.name});
        try self.print("; Source: {s}\n\n", .{module.source_file});

        // Print type definitions
        if (module.types.items.len > 0) {
            try self.write("; Type Definitions\n");
            for (module.types.items) |type_def| {
                try self.printTypeDef(type_def);
            }
            try self.write("\n");
        }

        // Print globals
        if (module.globals.items.len > 0) {
            try self.write("; Global Variables\n");
            for (module.globals.items) |global| {
                try self.printGlobal(global);
            }
            try self.write("\n");
        }

        // Print functions
        for (module.functions.items) |func| {
            try self.printFunction(func);
            try self.write("\n");
        }
    }

    /// Print a type definition
    fn printTypeDef(self: *Self, type_def: *const TypeDef) !void {
        const kind_str = switch (type_def.kind) {
            .class => "class",
            .interface => "interface",
            .trait => "trait",
            .@"enum" => "enum",
            .@"struct" => "struct",
        };
        try self.print("{s} {s}", .{ kind_str, type_def.name });

        if (type_def.parent) |parent| {
            try self.print(" extends {s}", .{parent});
        }

        if (type_def.interfaces.len > 0) {
            try self.write(" implements ");
            for (type_def.interfaces, 0..) |iface, i| {
                if (i > 0) try self.write(", ");
                try self.print("{s}", .{iface});
            }
        }

        try self.write(" {\n");

        for (type_def.properties) |prop| {
            const vis_str = switch (prop.visibility) {
                .public => "public",
                .protected => "protected",
                .private => "private",
            };
            try self.print("  {s} ", .{vis_str});
            if (prop.is_static) try self.write("static ");
            try self.print("{s}: {any}\n", .{ prop.name, prop.type_ });
        }

        for (type_def.methods) |method| {
            try self.print("  method {s}\n", .{method});
        }

        try self.write("}\n");
    }

    /// Print a global variable
    fn printGlobal(self: *Self, global: *const Global) !void {
        if (global.is_constant) {
            try self.write("const ");
        } else {
            try self.write("global ");
        }
        try self.print("@{s}: {any}\n", .{ global.name, global.type_ });
    }

    /// Print a function
    fn printFunction(self: *Self, func: *const Function) !void {
        // Function signature
        try self.write("define ");
        if (func.is_exported) try self.write("export ");
        try self.print("{any} @{s}(", .{ func.return_type, func.name });

        // Parameters
        for (func.params.items, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            try self.print("{any} %{s}", .{ param.type_, param.name });
            if (param.is_variadic) try self.write("...");
            if (param.is_reference) try self.write("&");
        }

        try self.write(") {\n");

        // Basic blocks
        for (func.blocks.items) |block| {
            try self.printBasicBlock(block);
        }

        try self.write("}\n");
    }

    /// Print a basic block
    fn printBasicBlock(self: *Self, block: *const BasicBlock) !void {
        try self.print("{s}:\n", .{block.label});

        // Instructions
        for (block.instructions.items) |inst| {
            try self.write("  ");
            try self.printInstruction(inst);
            try self.write("\n");
        }

        // Terminator
        if (block.terminator) |term| {
            try self.write("  ");
            try self.printTerminator(term);
            try self.write("\n");
        }
    }

    /// Print an instruction
    fn printInstruction(self: *Self, inst: *const Instruction) !void {
        // Print result register if present
        if (inst.result) |result| {
            try self.print("{any} = ", .{result});
        }

        // Print operation
        switch (inst.op) {
            // Arithmetic
            .add => |op| try self.print("add {any}, {any}", .{ op.lhs, op.rhs }),
            .sub => |op| try self.print("sub {any}, {any}", .{ op.lhs, op.rhs }),
            .mul => |op| try self.print("mul {any}, {any}", .{ op.lhs, op.rhs }),
            .div => |op| try self.print("div {any}, {any}", .{ op.lhs, op.rhs }),
            .mod => |op| try self.print("mod {any}, {any}", .{ op.lhs, op.rhs }),
            .neg => |op| try self.print("neg {any}", .{op.operand}),
            .pow => |op| try self.print("pow {any}, {any}", .{ op.lhs, op.rhs }),

            // Bitwise
            .bit_and => |op| try self.print("and {any}, {any}", .{ op.lhs, op.rhs }),
            .bit_or => |op| try self.print("or {any}, {any}", .{ op.lhs, op.rhs }),
            .bit_xor => |op| try self.print("xor {any}, {any}", .{ op.lhs, op.rhs }),
            .bit_not => |op| try self.print("not {any}", .{op.operand}),
            .shl => |op| try self.print("shl {any}, {any}", .{ op.lhs, op.rhs }),
            .shr => |op| try self.print("shr {any}, {any}", .{ op.lhs, op.rhs }),

            // Comparison
            .eq => |op| try self.print("eq {any}, {any}", .{ op.lhs, op.rhs }),
            .ne => |op| try self.print("ne {any}, {any}", .{ op.lhs, op.rhs }),
            .lt => |op| try self.print("lt {any}, {any}", .{ op.lhs, op.rhs }),
            .le => |op| try self.print("le {any}, {any}", .{ op.lhs, op.rhs }),
            .gt => |op| try self.print("gt {any}, {any}", .{ op.lhs, op.rhs }),
            .ge => |op| try self.print("ge {any}, {any}", .{ op.lhs, op.rhs }),
            .identical => |op| try self.print("identical {any}, {any}", .{ op.lhs, op.rhs }),
            .not_identical => |op| try self.print("not_identical {any}, {any}", .{ op.lhs, op.rhs }),
            .spaceship => |op| try self.print("spaceship {any}, {any}", .{ op.lhs, op.rhs }),

            // Logical
            .and_ => |op| try self.print("and {any}, {any}", .{ op.lhs, op.rhs }),
            .or_ => |op| try self.print("or {any}, {any}", .{ op.lhs, op.rhs }),
            .not => |op| try self.print("not {any}", .{op.operand}),

            // Memory
            .alloca => |op| try self.print("alloca {any} x {d}", .{ op.type_, op.count }),
            .load => |op| try self.print("load {any} from {any}", .{ op.type_, op.ptr }),
            .store => |op| try self.print("store {any} to {any}", .{ op.value, op.ptr }),

            // Constants
            .const_int => |val| try self.print("const.i64 {d}", .{val}),
            .const_float => |val| try self.print("const.f64 {d}", .{val}),
            .const_bool => |val| try self.print("const.bool {any}", .{val}),
            .const_string => |id| try self.print("const.string ${d}", .{id}),
            .const_null => try self.write("const.null"),

            // Function calls
            .call => |op| {
                try self.print("call @{s}(", .{op.func_name});
                for (op.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("{any}", .{arg});
                }
                try self.write(")");
            },
            .call_indirect => |op| {
                try self.print("call_indirect {any}(", .{op.func_ptr});
                for (op.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("{any}", .{arg});
                }
                try self.write(")");
            },

            // Type operations
            .cast => |op| try self.print("cast {any} from {any} to {any}", .{ op.value, op.from_type, op.to_type }),
            .type_check => |op| try self.print("type_check {any} is {any}", .{ op.value, op.expected_type }),
            .get_type => |op| try self.print("get_type {any}", .{op.operand}),

            // Array operations
            .array_new => |op| try self.print("array.new capacity={d}", .{op.capacity}),
            .array_get => |op| try self.print("array.get {any}[{any}]", .{ op.array, op.key }),
            .array_set => |op| try self.print("array.set {any}[{any}] = {any}", .{ op.array, op.key, op.value }),
            .array_push => |op| try self.print("array.push {any} <- {any}", .{ op.array, op.value }),
            .array_count => |op| try self.print("array.count {any}", .{op.operand}),
            .array_key_exists => |op| try self.print("array.key_exists {any}[{any}]", .{ op.array, op.key }),
            .array_unset => |op| try self.print("array.unset {any}[{any}]", .{ op.array, op.key }),

            // String operations
            .concat => |op| try self.print("concat {any}, {any}", .{ op.lhs, op.rhs }),
            .strlen => |op| try self.print("strlen {any}", .{op.operand}),
            .interpolate => |op| {
                try self.write("interpolate ");
                for (op.parts, 0..) |part, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("{any}", .{part});
                }
            },

            // Object operations
            .new_object => |op| {
                try self.print("new {s}(", .{op.class_name});
                for (op.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("{any}", .{arg});
                }
                try self.write(")");
            },
            .property_get => |op| try self.print("property.get {any}.{s}", .{ op.object, op.property_name }),
            .property_set => |op| try self.print("property.set {any}.{s} = {any}", .{ op.object, op.property_name, op.value }),
            .method_call => |op| {
                try self.print("method.call {any}.{s}(", .{ op.object, op.method_name });
                for (op.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("{any}", .{arg});
                }
                try self.write(")");
            },
            .clone => |op| try self.print("clone {any}", .{op.operand}),
            .instanceof => |op| try self.print("instanceof {any} is {s}", .{ op.object, op.class_name }),

            // PHP value operations
            .box => |op| try self.print("box {any} from {any}", .{ op.value, op.from_type }),
            .unbox => |op| try self.print("unbox {any} to {any}", .{ op.value, op.to_type }),
            .retain => |op| try self.print("retain {any}", .{op.operand}),
            .release => |op| try self.print("release {any}", .{op.operand}),

            // Control flow
            .phi => |op| {
                try self.write("phi ");
                for (op.incoming, 0..) |inc, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("[{any}, {s}]", .{ inc.value, inc.block.label });
                }
            },
            .select => |op| try self.print("select {any}, {any}, {any}", .{ op.cond, op.then_value, op.else_value }),

            // Exception handling
            .try_begin => try self.write("try.begin"),
            .try_end => try self.write("try.end"),
            .catch_ => |op| {
                try self.write("catch");
                if (op.exception_type) |et| {
                    try self.print(" {s}", .{et});
                }
            },
            .get_exception => try self.write("get_exception"),
            .clear_exception => try self.write("clear_exception"),

            // Debug
            .debug_print => |op| try self.print("debug.print {any}", .{op.operand}),
        }
    }

    /// Print a terminator
    fn printTerminator(self: *Self, term: Terminator) !void {
        switch (term) {
            .ret => |val| {
                try self.write("ret");
                if (val) |v| {
                    try self.print(" {any}", .{v});
                }
            },
            .br => |block| try self.print("br {s}", .{block.label}),
            .cond_br => |cb| try self.print("br {any}, {s}, {s}", .{ cb.cond, cb.then_block.label, cb.else_block.label }),
            .switch_ => |sw| {
                try self.print("switch {any} [", .{sw.value});
                for (sw.cases, 0..) |case, i| {
                    if (i > 0) try self.write(", ");
                    try self.print("{d}: {s}", .{ case.value, case.block.label });
                }
                try self.print("], default: {s}", .{sw.default.label});
            },
            .unreachable_ => try self.write("unreachable"),
            .throw => |val| try self.print("throw {any}", .{val}),
        }
    }
};

/// Serialize a module to a string
pub fn serializeModule(allocator: Allocator, module: *const Module) ![]const u8 {
    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);

    var printer = IRPrinter.initUnmanaged(&list, allocator);
    try printer.printModule(module);

    return list.toOwnedSlice(allocator);
}

// ============================================================================
// Unit Tests
// ============================================================================

test "Module creation and basic operations" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "test_module", "test.php");
    defer module.deinit();

    // Test string interning
    const id1 = try module.internString("hello");
    const id2 = try module.internString("world");
    const id3 = try module.internString("hello"); // Should return same ID

    try std.testing.expectEqual(@as(u32, 0), id1);
    try std.testing.expectEqual(@as(u32, 1), id2);
    try std.testing.expectEqual(@as(u32, 0), id3); // Same as id1

    try std.testing.expectEqualStrings("hello", module.getString(id1).?);
    try std.testing.expectEqualStrings("world", module.getString(id2).?);
}

test "Function creation with parameters" {
    const allocator = std.testing.allocator;

    var func = Function.init(allocator, "test_func");
    defer func.deinit();

    try func.addParam(.{
        .name = "arg1",
        .type_ = .i64,
        .has_default = false,
        .is_variadic = false,
        .is_reference = false,
    });

    try func.addParam(.{
        .name = "arg2",
        .type_ = .php_string,
        .has_default = true,
        .is_variadic = false,
        .is_reference = false,
    });

    try std.testing.expectEqual(@as(usize, 2), func.params.items.len);
    try std.testing.expectEqualStrings("arg1", func.params.items[0].name);
    try std.testing.expectEqualStrings("arg2", func.params.items[1].name);
}

test "BasicBlock creation and instructions" {
    const allocator = std.testing.allocator;

    var func = Function.init(allocator, "test_func");
    defer func.deinit();

    const entry = try func.createBlock("entry");

    // Create an instruction
    const inst = try allocator.create(Instruction);
    inst.* = .{
        .result = func.newRegister(.i64),
        .op = .{ .const_int = 42 },
        .location = .{},
    };
    try entry.appendInstruction(inst);

    // Set terminator
    entry.setTerminator(.{ .ret = inst.result });

    try std.testing.expectEqual(@as(usize, 1), entry.instructions.items.len);
    try std.testing.expect(entry.isTerminated());
}

test "Register allocation" {
    const allocator = std.testing.allocator;

    var func = Function.init(allocator, "test_func");
    defer func.deinit();

    const r0 = func.newRegister(.i64);
    const r1 = func.newRegister(.f64);
    const r2 = func.newRegister(.php_value);

    try std.testing.expectEqual(@as(u32, 0), r0.id);
    try std.testing.expectEqual(@as(u32, 1), r1.id);
    try std.testing.expectEqual(@as(u32, 2), r2.id);
}

test "Type properties" {
    // Test isDynamic
    const php_val: Type = .php_value;
    const php_str: Type = .php_string;
    const php_arr: Type = .php_array;
    const int_type: Type = .i64;
    const bool_type: Type = .bool;
    const float_type: Type = .f64;
    const void_type: Type = .void;

    try std.testing.expect(php_val.isDynamic());
    try std.testing.expect(php_str.isDynamic());
    try std.testing.expect(php_arr.isDynamic());
    try std.testing.expect(!int_type.isDynamic());
    try std.testing.expect(!bool_type.isDynamic());

    // Test isPrimitive
    try std.testing.expect(int_type.isPrimitive());
    try std.testing.expect(float_type.isPrimitive());
    try std.testing.expect(bool_type.isPrimitive());
    try std.testing.expect(!php_val.isPrimitive());

    // Test sizeOf
    try std.testing.expectEqual(@as(usize, 8), int_type.sizeOf());
    try std.testing.expectEqual(@as(usize, 8), float_type.sizeOf());
    try std.testing.expectEqual(@as(usize, 1), bool_type.sizeOf());
    try std.testing.expectEqual(@as(usize, 0), void_type.sizeOf());
    try std.testing.expectEqual(@as(usize, 24), php_val.sizeOf());
}

test "IR serialization" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "test_module", "test.php");
    defer module.deinit();

    // Create a simple function
    const func = try allocator.create(Function);
    func.* = Function.init(allocator, "main");
    try module.addFunction(func);

    // Add entry block
    const entry = try func.createBlock("entry");

    // Add constant instruction
    const const_inst = try allocator.create(Instruction);
    const_inst.* = .{
        .result = func.newRegister(.i64),
        .op = .{ .const_int = 42 },
        .location = .{},
    };
    try entry.appendInstruction(const_inst);

    // Add return
    entry.setTerminator(.{ .ret = const_inst.result });

    // Serialize
    const ir_text = try serializeModule(allocator, &module);
    defer allocator.free(ir_text);

    // Verify output contains expected elements
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "Module: test_module") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "@main") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "entry:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "const.i64 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "ret") != null);
}

test "Register equality" {
    const r1 = Register{ .id = 0, .type_ = .i64 };
    const r2 = Register{ .id = 0, .type_ = .f64 };
    const r3 = Register{ .id = 1, .type_ = .i64 };

    try std.testing.expect(r1.eql(r2)); // Same ID, different type
    try std.testing.expect(!r1.eql(r3)); // Different ID
}

test "IR serialization with binary operations" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "binary_ops", "test.php");
    defer module.deinit();

    // Create a function that adds two numbers
    const func = try allocator.create(Function);
    func.* = Function.init(allocator, "add_numbers");
    func.return_type = .i64;
    try func.addParam(.{
        .name = "a",
        .type_ = .i64,
        .has_default = false,
        .is_variadic = false,
        .is_reference = false,
    });
    try func.addParam(.{
        .name = "b",
        .type_ = .i64,
        .has_default = false,
        .is_variadic = false,
        .is_reference = false,
    });
    try module.addFunction(func);

    // Create entry block
    const entry = try func.createBlock("entry");

    // Load parameters (simulated as constants for this test)
    const r0 = func.newRegister(.i64);
    const inst0 = try allocator.create(Instruction);
    inst0.* = .{
        .result = r0,
        .op = .{ .const_int = 10 },
        .location = .{},
    };
    try entry.appendInstruction(inst0);

    const r1 = func.newRegister(.i64);
    const inst1 = try allocator.create(Instruction);
    inst1.* = .{
        .result = r1,
        .op = .{ .const_int = 20 },
        .location = .{},
    };
    try entry.appendInstruction(inst1);

    // Add operation
    const r2 = func.newRegister(.i64);
    const add_inst = try allocator.create(Instruction);
    add_inst.* = .{
        .result = r2,
        .op = .{ .add = .{ .lhs = r0, .rhs = r1 } },
        .location = .{},
    };
    try entry.appendInstruction(add_inst);

    // Return result
    entry.setTerminator(.{ .ret = r2 });

    // Serialize
    const ir_text = try serializeModule(allocator, &module);
    defer allocator.free(ir_text);

    // Verify output
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "@add_numbers") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "const.i64 10") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "const.i64 20") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "add") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "ret") != null);
}

test "IR serialization with control flow" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "control_flow", "test.php");
    defer module.deinit();

    // Create a function with conditional branch
    const func = try allocator.create(Function);
    func.* = Function.init(allocator, "conditional");
    func.return_type = .i64;
    try module.addFunction(func);

    // Create blocks
    const entry = try func.createBlock("entry");
    const then_block = try func.createBlock("then");
    const else_block = try func.createBlock("else");
    const merge_block = try func.createBlock("merge");

    // Entry: condition check
    const cond_reg = func.newRegister(.bool);
    const cond_inst = try allocator.create(Instruction);
    cond_inst.* = .{
        .result = cond_reg,
        .op = .{ .const_bool = true },
        .location = .{},
    };
    try entry.appendInstruction(cond_inst);
    entry.setTerminator(.{ .cond_br = .{
        .cond = cond_reg,
        .then_block = then_block,
        .else_block = else_block,
    } });

    // Then block
    const then_val = func.newRegister(.i64);
    const then_inst = try allocator.create(Instruction);
    then_inst.* = .{
        .result = then_val,
        .op = .{ .const_int = 1 },
        .location = .{},
    };
    try then_block.appendInstruction(then_inst);
    then_block.setTerminator(.{ .br = merge_block });

    // Else block
    const else_val = func.newRegister(.i64);
    const else_inst = try allocator.create(Instruction);
    else_inst.* = .{
        .result = else_val,
        .op = .{ .const_int = 0 },
        .location = .{},
    };
    try else_block.appendInstruction(else_inst);
    else_block.setTerminator(.{ .br = merge_block });

    // Merge block with return
    merge_block.setTerminator(.{ .ret = then_val });

    // Serialize
    const ir_text = try serializeModule(allocator, &module);
    defer allocator.free(ir_text);

    // Verify output contains all blocks
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "entry:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "then:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "else:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "merge:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "br") != null);
}

test "IR serialization with function calls" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "func_calls", "test.php");
    defer module.deinit();

    // Create a function that calls another function
    const func = try allocator.create(Function);
    func.* = Function.init(allocator, "caller");
    func.return_type = .php_value;
    try module.addFunction(func);

    const entry = try func.createBlock("entry");

    // Create arguments
    const arg1 = func.newRegister(.i64);
    const arg1_inst = try allocator.create(Instruction);
    arg1_inst.* = .{
        .result = arg1,
        .op = .{ .const_int = 42 },
        .location = .{},
    };
    try entry.appendInstruction(arg1_inst);

    // Call instruction
    const args = try allocator.alloc(Register, 1);
    defer allocator.free(args);
    args[0] = arg1;

    const call_result = func.newRegister(.php_value);
    const call_inst = try allocator.create(Instruction);
    call_inst.* = .{
        .result = call_result,
        .op = .{ .call = .{
            .func_name = "callee",
            .args = args,
            .return_type = .php_value,
        } },
        .location = .{},
    };
    try entry.appendInstruction(call_inst);

    // Return
    entry.setTerminator(.{ .ret = call_result });

    // Serialize
    const ir_text = try serializeModule(allocator, &module);
    defer allocator.free(ir_text);

    // Verify output
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "call @callee") != null);
}

test "IR serialization with array operations" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "array_ops", "test.php");
    defer module.deinit();

    const func = try allocator.create(Function);
    func.* = Function.init(allocator, "array_test");
    func.return_type = .php_value;
    try module.addFunction(func);

    const entry = try func.createBlock("entry");

    // Create array
    const arr = func.newRegister(.php_array);
    const arr_inst = try allocator.create(Instruction);
    arr_inst.* = .{
        .result = arr,
        .op = .{ .array_new = .{ .capacity = 10 } },
        .location = .{},
    };
    try entry.appendInstruction(arr_inst);

    // Create key and value
    const key = func.newRegister(.i64);
    const key_inst = try allocator.create(Instruction);
    key_inst.* = .{
        .result = key,
        .op = .{ .const_int = 0 },
        .location = .{},
    };
    try entry.appendInstruction(key_inst);

    const val = func.newRegister(.i64);
    const val_inst = try allocator.create(Instruction);
    val_inst.* = .{
        .result = val,
        .op = .{ .const_int = 100 },
        .location = .{},
    };
    try entry.appendInstruction(val_inst);

    // Array set
    const set_inst = try allocator.create(Instruction);
    set_inst.* = .{
        .result = null,
        .op = .{ .array_set = .{ .array = arr, .key = key, .value = val } },
        .location = .{},
    };
    try entry.appendInstruction(set_inst);

    // Array get
    const get_result = func.newRegister(.php_value);
    const get_inst = try allocator.create(Instruction);
    get_inst.* = .{
        .result = get_result,
        .op = .{ .array_get = .{ .array = arr, .key = key } },
        .location = .{},
    };
    try entry.appendInstruction(get_inst);

    entry.setTerminator(.{ .ret = get_result });

    // Serialize
    const ir_text = try serializeModule(allocator, &module);
    defer allocator.free(ir_text);

    // Verify output
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "array.new") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "array.set") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "array.get") != null);
}

test "Module findFunction" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "test", "test.php");
    defer module.deinit();

    const func1 = try allocator.create(Function);
    func1.* = Function.init(allocator, "func1");
    try module.addFunction(func1);

    const func2 = try allocator.create(Function);
    func2.* = Function.init(allocator, "func2");
    try module.addFunction(func2);

    // Test findFunction
    const found1 = module.findFunction("func1");
    try std.testing.expect(found1 != null);
    try std.testing.expectEqualStrings("func1", found1.?.name);

    const found2 = module.findFunction("func2");
    try std.testing.expect(found2 != null);
    try std.testing.expectEqualStrings("func2", found2.?.name);

    const not_found = module.findFunction("nonexistent");
    try std.testing.expect(not_found == null);
}

test "BasicBlock predecessors and successors" {
    const allocator = std.testing.allocator;

    var func = Function.init(allocator, "test_func");
    defer func.deinit();

    const block1 = try func.createBlock("block1");
    const block2 = try func.createBlock("block2");

    try block1.addSuccessor(block2);
    try block2.addPredecessor(block1);

    try std.testing.expectEqual(@as(usize, 1), block1.successors.items.len);
    try std.testing.expectEqual(@as(usize, 1), block2.predecessors.items.len);
    try std.testing.expectEqualStrings("block2", block1.successors.items[0].label);
    try std.testing.expectEqualStrings("block1", block2.predecessors.items[0].label);
}
