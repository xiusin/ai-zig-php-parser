//! IR Generator for AOT Compiler
//!
//! This module converts PHP AST nodes into SSA-form Intermediate Representation (IR).
//! The generated IR is suitable for optimization passes and LLVM code generation.
//!
//! ## Features
//!
//! - SSA (Static Single Assignment) form generation
//! - Basic block management with control flow
//! - Source location preservation for debugging
//! - Constant folding during IR generation
//! - Support for all PHP language constructs
//!
//! ## Usage
//!
//! ```zig
//! var generator = try IRGenerator.init(allocator, diagnostics);
//! defer generator.deinit();
//!
//! const module = try generator.generate(ast_nodes, string_table, "module_name", "source.php");
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const Module = IR.Module;
const Function = IR.Function;
const BasicBlock = IR.BasicBlock;
const Instruction = IR.Instruction;
const Register = IR.Register;
const Type = IR.Type;
const Terminator = IR.Terminator;
const Parameter = IR.Parameter;
const Global = IR.Global;
const TypeDef = IR.TypeDef;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const SourceLocation = Diagnostics.SourceLocation;
const SymbolTableMod = @import("symbol_table.zig");
const SymbolTable = SymbolTableMod.SymbolTable;
const InferredType = SymbolTableMod.InferredType;
const ConcreteType = SymbolTableMod.ConcreteType;
const TypeInferenceMod = @import("type_inference.zig");
const TypeInferencer = TypeInferenceMod.TypeInferencer;
const compiler = @import("compiler");
const ast = compiler.ast;
pub const Node = ast.Node;
pub const Token = compiler.token.Token;
pub const TokenTag = compiler.token.Token.Tag;
const QuoteType = ast.QuoteType;
const MagicConstantKind = ast.MagicConstantKind;
// CastType in ast.zig is Token.Tag, so we alias it here for compatibility,
// but we will need to update usages to use Token.Tag values.
const CastType = TokenTag;


/// IR Generator - converts AST to SSA-form IR
pub const IRGenerator = struct {
    allocator: Allocator,
    /// Current IR module being generated
    module: ?*Module,
    /// Current function being generated
    current_function: ?*Function,
    /// Current basic block being generated
    current_block: ?*BasicBlock,
    /// Symbol table for variable tracking
    symbol_table: *SymbolTable,
    /// Type inferencer for type information
    type_inferencer: *TypeInferencer,
    /// Diagnostic engine for error reporting
    diagnostics: *DiagnosticEngine,
    /// AST nodes array
    nodes: ?[]const Node,
    /// String table for string lookups
    string_table: ?[]const []const u8,
    /// Current source location
    current_location: SourceLocation,
    /// Variable to register mapping for current function
    var_registers: std.StringHashMapUnmanaged(Register),
    /// Track variable usage for unused variable detection
    var_usage: std.StringHashMapUnmanaged(struct {
        is_used: bool,
        location: SourceLocation,
    }),
    /// Block counter for unique labels
    block_counter: u32,
    /// Loop context stack for break/continue
    loop_stack: std.ArrayListUnmanaged(LoopContext),
    /// Try-catch context stack
    try_stack: std.ArrayListUnmanaged(TryContext),

    const Self = @This();

    /// Context for loop statements (for break/continue)
    pub const LoopContext = struct {
        /// Block to jump to on break
        break_block: *BasicBlock,
        /// Block to jump to on continue
        continue_block: *BasicBlock,
    };

    /// Context for try-catch statements
    pub const TryContext = struct {
        /// Catch block
        catch_block: *BasicBlock,
        /// Finally block (if any)
        finally_block: ?*BasicBlock,
    };

    /// Initialize a new IR generator
    pub fn init(
        allocator: Allocator,
        symbol_table: *SymbolTable,
        type_inferencer: *TypeInferencer,
        diagnostics: *DiagnosticEngine,
    ) Self {
        return .{
            .allocator = allocator,
            .module = null,
            .current_function = null,
            .current_block = null,
            .symbol_table = symbol_table,
            .type_inferencer = type_inferencer,
            .diagnostics = diagnostics,
            .nodes = null,
            .string_table = null,
            .current_location = .{},
            .var_registers = .{},
            .var_usage = .{},
            .block_counter = 0,
            .loop_stack = .{},
            .try_stack = .{},
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.var_registers.deinit(self.allocator);
        self.var_usage.deinit(self.allocator);
        self.loop_stack.deinit(self.allocator);
        self.try_stack.deinit(self.allocator);
    }

    /// Generate IR module from AST (assumes root node at index 0)
    pub fn generate(
        self: *Self,
        nodes: []const Node,
        string_table: []const []const u8,
        module_name: []const u8,
        source_file: []const u8,
    ) !*Module {
        return self.generateFromRoot(nodes, string_table, 0, module_name, source_file);
    }

    /// Generate IR module from AST with explicit root node index
    pub fn generateFromRoot(
        self: *Self,
        nodes: []const Node,
        string_table: []const []const u8,
        root_index: u32,
        module_name: []const u8,
        source_file: []const u8,
    ) !*Module {
        self.nodes = nodes;
        self.string_table = string_table;

        // Create module
        const module = try self.allocator.create(Module);
        module.* = Module.init(self.allocator, module_name, source_file);
        self.module = module;

        // Copy string table from Parser to Module
        // This ensures that StringId from AST nodes matches StringId in IR Module
        for (string_table) |str| {
            try module.string_table.append(self.allocator, str);
        }

        // Process root node at the specified index
        if (root_index < nodes.len and nodes[root_index].tag == .root) {
            const root_data = nodes[root_index].data.root;

            // Separate function declarations from top-level statements
            var top_level_stmts = std.ArrayListUnmanaged(Node.Index){};
            defer top_level_stmts.deinit(self.allocator);

            for (root_data.stmts) |stmt_idx| {
                const stmt_node = self.getNode(stmt_idx) orelse continue;

                if (stmt_node.tag == .function_decl or stmt_node.tag == .class_decl or
                    stmt_node.tag == .interface_decl or stmt_node.tag == .trait_decl)
                {
                    // Process declarations directly (they create their own functions)
                    try self.generateStatement(stmt_idx);
                } else {
                    // Collect top-level statements for __main__
                    try top_level_stmts.append(self.allocator, stmt_idx);
                }
            }

            // Create __main__ function for top-level statements if any
            if (top_level_stmts.items.len > 0) {
                try self.generateMainFunction(top_level_stmts.items);
            }
        } else {
            // Root node not found or invalid tag
        }

        return module;
    }

    /// Generate the __main__ function for top-level statements
    fn generateMainFunction(self: *Self, stmts: []const Node.Index) !void {
        // Create __main__ function
        const func = try self.allocator.create(Function);
        func.* = Function.init(self.allocator, "__main__");
        func.is_exported = true;
        func.location = self.current_location;

        // Add to module
        if (self.module) |module| {
            try module.addFunction(func);
        }

        // Set up context
        self.current_function = func;
        self.block_counter = 0;

        // Create entry block
        const entry = try func.createBlock("entry");
        self.setCurrentBlock(entry);

        // Generate all top-level statements
        for (stmts) |stmt_idx| {
            try self.generateStatement(stmt_idx);
            if (self.isBlockTerminated()) break;
        }

        // Add implicit return if not terminated
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .ret = null });
        }

        // Clear context
        self.current_function = null;
        self.current_block = null;
    }

    // ========================================================================
    // Core IR Generation Helpers
    // ========================================================================

    /// Get a node by index
    fn getNode(self: *const Self, index: Node.Index) ?*const Node {
        if (self.nodes) |nodes| {
            if (index < nodes.len) {
                return &nodes[index];
            }
        }
        return null;
    }

    /// Get a string from the string table
    fn getString(self: *const Self, id: Node.StringId) []const u8 {
        if (self.string_table) |table| {
            if (id < table.len) {
                return table[id];
            }
        }
        return "";
    }

    /// Create a new basic block with a unique label
    fn createBlock(self: *Self, prefix: []const u8) !*BasicBlock {
        const func = self.current_function orelse return error.NoCurrentFunction;
        var buf: [64]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{s}_{d}", .{ prefix, self.block_counter }) catch prefix;
        self.block_counter += 1;

        const block = try func.createBlock(label);

        // 设置异常处理器
        if (self.try_stack.items.len > 0) {
            const context = self.try_stack.items[self.try_stack.items.len - 1];
            block.exception_handler = context.catch_block;
        }

        return block;
    }

    /// Set the current block
    fn setCurrentBlock(self: *Self, block: *BasicBlock) void {
        self.current_block = block;
    }

    /// Allocate a new SSA register
    fn newRegister(self: *Self, type_: Type) !Register {
        const func = self.current_function orelse return error.NoCurrentFunction;
        return func.newRegister(type_);
    }

    /// Emit an instruction to the current block
    fn emit(self: *Self, op: Instruction.Op, result_type: ?Type) !?Register {
        const block = self.current_block orelse return error.NoCurrentBlock;

        const result = if (result_type) |t| try self.newRegister(t) else null;

        const inst = try self.allocator.create(Instruction);
        inst.* = .{
            .result = result,
            .op = op,
            .location = self.current_location,
        };
        try block.appendInstruction(inst);

        return result;
    }

    /// Emit an instruction and return the result register (asserts result exists)
    fn emitWithResult(self: *Self, op: Instruction.Op, result_type: Type) !Register {
        const result = try self.emit(op, result_type);
        return result orelse error.ExpectedResult;
    }

    /// Set the terminator for the current block
    fn setTerminator(self: *Self, term: Terminator) void {
        if (self.current_block) |block| {
            if (!block.isTerminated()) {
                block.setTerminator(term);
            }
        }
    }

    /// Check if current block is terminated
    fn isBlockTerminated(self: *const Self) bool {
        if (self.current_block) |block| {
            return block.isTerminated();
        }
        return true;
    }

    /// Update source location from a token
    fn updateLocation(self: *Self, token: Token) void {
        const loc = self.diagnostics.getLocation(token.loc.start);
        self.current_location = .{
            .file = if (self.module) |m| m.source_file else "<unknown>",
            .line = loc.line,
            .column = loc.column,
        };
    }

    /// Get or create a register for a variable
    fn getOrCreateVarRegister(self: *Self, name: []const u8, type_: Type) !Register {
        if (self.var_registers.get(name)) |reg| {
            return reg;
        }

        // Allocate stack space for the variable
        // 必须在堆上分配Type，因为指针需要在函数返回后仍然有效
        const type_ptr = try self.allocator.create(Type);
        type_ptr.* = type_;
        const ptr_type = Type{ .ptr = type_ptr };
        
        // Always create alloca in the entry block to ensure dominance
        const func = self.current_function orelse return error.NoCurrentFunction;
        // Function always has at least one block (entry) created during init
        const entry_block = if (func.blocks.items.len > 0) func.blocks.items[0] else return error.NoEntryBlock;
        
        const result = func.newRegister(ptr_type);
        const inst = try self.allocator.create(Instruction);
        inst.* = .{
            .result = result,
            .op = .{ .alloca = .{ .type_ = type_, .count = 1 } },
            .location = self.current_location,
        };
        
        // Prepend to entry block to ensure it's before any potential use
        try entry_block.instructions.insert(self.allocator, 0, inst);

        try self.var_registers.put(self.allocator, name, result);
        // Mark variable as defined but not used yet, store definition location
        try self.var_usage.put(self.allocator, name, .{
            .is_used = false,
            .location = self.current_location,
        });
        return result;
    }

    /// Look up a variable's register
    fn lookupVarRegister(self: *const Self, name: []const u8) ?Register {
        return self.var_registers.get(name);
    }

    /// Generate IR for variable access
    fn generateVariable(self: *Self, node: *const Node) !Register {
        const var_name = self.getString(node.data.variable.name);

        // Mark variable as used
        if (self.var_usage.get(var_name)) |usage_info| {
            try self.var_usage.put(self.allocator, var_name, .{
                .is_used = true,
                .location = usage_info.location,
            });
        }

        // Look up variable register
        if (self.lookupVarRegister(var_name)) |ptr_reg| {
            // 从指针类型中提取指向的类型
            // Extract the pointed-to type from the pointer type
            const ptr_type = ptr_reg.type_;
            const pointed_type = if (ptr_type == .ptr) ptr_type.ptr.* else .php_value;

            // Load the value from the variable
            return self.emitWithResult(.{ .load = .{ .ptr = ptr_reg, .type_ = pointed_type } }, pointed_type);
        }

        // Variable not found
        
        // Check if it's a variable (starts with $)
        if (var_name.len > 0 and var_name[0] == '$') {
            // Undefined variable - create a null value
            // TODO: Emit warning
            return self.emitWithResult(.const_null, .php_value);
        } else {
            // It's a constant (identifier)
            // Generate call to php_constant_get(name)
            
            // Create string literal for name
            const name_id = node.data.variable.name;
            const name_reg = try self.emitWithResult(.{ .const_string = name_id }, .php_value);
            
            // Emit call
            const args = try self.allocator.alloc(Register, 1);
            args[0] = name_reg;
            
            return self.emitWithResult(.{ .call = .{
                .func_name = "php_constant_get",
                .args = args,
                .return_type = .php_value,
            } }, .php_value);
        }
    }

    /// Check for unused variables and report errors
    fn checkUnusedVariables(self: *Self) !void {
        var iter = self.var_usage.iterator();
        while (iter.next()) |entry| {
            const var_name = entry.key_ptr.*;
            const usage_info = entry.value_ptr.*;

            if (!usage_info.is_used) {
                // 根据当前模式确定变量前缀
                const var_prefix = if (self.isGoMode()) "" else "$";

                // 报告未使用变量错误，使用变量定义时的位置信息
                self.diagnostics.report(
                    .@"error",
                    usage_info.location,
                    "未使用的变量: {s}{s}",
                    .{ var_prefix, var_name },
                );
            }
        }
    }

    /// 检查当前是否为Go模式
    fn isGoMode(self: *const Self) bool {
        // 通过检查当前函数名或模块名判断是否为Go模式
        if (self.current_function) |func| {
            // Go模式通常包含go关键字或特定命名模式
            return std.mem.indexOf(u8, func.name, "go") != null or
                std.mem.indexOf(u8, func.name, "Go") != null;
        }
        return false;
    }

    // ========================================================================
    // Statement Generation
    // ========================================================================

    /// Generate IR for a statement
    fn generateStatement(self: *Self, index: Node.Index) anyerror!void {
        const node = self.getNode(index) orelse return;
        self.updateLocation(node.main_token);

        switch (node.tag) {
            .function_decl => try self.generateFunctionDecl(node),
            .class_decl => try self.generateClassDecl(node),
            .interface_decl => try self.generateInterfaceDecl(node),
            .trait_decl => try self.generateTraitDecl(node),
            .if_stmt => try self.generateIfStmt(node),
            .while_stmt => try self.generateWhileStmt(node),
            .for_stmt => try self.generateForStmt(node),
            .for_range_stmt => try self.generateForRangeStmt(node),
            .foreach_stmt => try self.generateForeachStmt(node),
            .switch_stmt => try self.generateSwitchStmt(node),
            .try_stmt => try self.generateTryStmt(node),
            .throw_stmt => try self.generateThrowStmt(node),
            .return_stmt => try self.generateReturnStmt(node),
            .break_stmt => try self.generateBreakStmt(node),
            .continue_stmt => try self.generateContinueStmt(node),
            .echo_stmt => try self.generateEchoStmt(node),
            .lock_stmt => try self.generateLockStmt(node),
            .go_stmt => try self.generateGoStmt(node),
            .expression_stmt => {
                // Expression statement - just evaluate the expression
                _ = try self.generateExpression(index);
            },
            .assignment => try self.generateAssignment(node),
            .compound_assignment => try self.generateCompoundAssignment(node),
            .list_assignment => try self.generateListAssignment(node),
            .list_empty => {},
            .block => try self.generateBlock(node),
            .const_decl => try self.generateConstDecl(node),
            // global_stmt和static_stmt暂时跳过，因为AST可能未正确初始化data
            .global_stmt => {},
            .static_stmt => {},
            else => {
                _ = try self.generateExpression(index);
            },
        }
    }

    /// Generate IR for a block of statements
    fn generateBlock(self: *Self, node: *const Node) !void {
        const block_data = node.data.block;
        for (block_data.stmts) |stmt_idx| {
            try self.generateStatement(stmt_idx);
            // Stop if block is terminated (return, break, etc.)
            if (self.isBlockTerminated()) break;
        }
    }

    /// Generate IR for function declaration
    fn generateFunctionDecl(self: *Self, node: *const Node) !void {
        const func_data = node.data.function_decl;
        const func_name = self.getString(func_data.name);

        // Create function
        const func = try self.allocator.create(Function);
        func.* = Function.init(self.allocator, func_name);
        func.is_exported = true;
        func.location = self.current_location;

        // Add to module
        if (self.module) |module| {
            try module.addFunction(func);
        }

        // Save previous context
        const prev_function = self.current_function;
        const prev_block = self.current_block;
        const prev_var_registers = self.var_registers;

        // Set up new context
        self.current_function = func;
        self.var_registers = .{};
        self.var_usage = .{}; // 初始化变量使用跟踪
        self.block_counter = 0;

        // Create entry block
        const entry = try func.createBlock("entry");
        self.setCurrentBlock(entry);

        // Process parameters
        for (func_data.params) |param_idx| {
            try self.generateParameter(param_idx);
        }

        // Generate function body
        try self.generateStatement(func_data.body);

        // Add implicit return if not terminated
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .ret = null });
        }

        // Check for unused variables
        try self.checkUnusedVariables();

        // Restore previous context
        self.var_registers.deinit(self.allocator);
        self.var_usage.deinit(self.allocator);
        self.var_registers = prev_var_registers;
        self.var_usage = .{};
        self.current_function = prev_function;
        self.current_block = prev_block;
    }

    /// Generate IR for a function parameter
    fn generateParameter(self: *Self, index: Node.Index) !void {
        const node = self.getNode(index) orelse return;
        if (node.tag != .parameter) return;

        const param_data = node.data.parameter;
        const param_name = self.getString(param_data.name);

        // Determine parameter type
        var param_type: Type = .php_value;
        if (param_data.type) |type_idx| {
            param_type = try self.resolveTypeNode(type_idx);
        }

        // Add parameter to function
        var param_idx: u32 = 0;
        if (self.current_function) |func| {
            param_idx = @intCast(func.params.items.len);
            try func.addParam(.{
                .name = param_name,
                .type_ = param_type,
                .has_default = param_data.default_value != null,
                .is_variadic = param_data.is_variadic,
                .is_reference = param_data.is_reference,
            });
        }

        // Create register for parameter (alloca)
        const alloca_reg = try self.getOrCreateVarRegister(param_name, param_type);

        if (param_data.default_value) |default_expr_idx| {
            // Has default value - generate conditional logic
            const func = self.current_function.?;
            
            // 1. Get argument count
            const argc_reg = try self.emitWithResult(.{ .arg_count = {} }, .i64);
            
            // 2. Compare argc > param_idx
            // Create constant for param index
            const idx_reg = func.newRegister(.i64);
            const idx_inst = try self.allocator.create(Instruction);
            idx_inst.* = .{
                .result = idx_reg,
                .op = .{ .const_int = @intCast(param_idx) },
                .location = self.current_location,
            };
            try self.current_block.?.appendInstruction(idx_inst);

            const cond_reg = try self.emitWithResult(.{ 
                .gt = .{ .lhs = argc_reg, .rhs = idx_reg } 
            }, .bool);

            // 3. Create blocks
            const present_block = try func.createBlock("param_present");
            const missing_block = try func.createBlock("param_missing");
            const merge_block = try func.createBlock("param_merge");

            // 4. Branch
            self.current_block.?.setTerminator(.{ .cond_br = .{ 
                .cond = cond_reg, 
                .then_block = present_block, 
                .else_block = missing_block 
            } });

            // 5. Present Block
            self.current_block = present_block;
            const param_val = try self.emitWithResult(.{ .param = .{ .index = param_idx, .name = param_name } }, param_type);
            _ = try self.emit(.{ .store = .{ .ptr = alloca_reg, .value = param_val } }, null);
            self.current_block.?.setTerminator(.{ .br = merge_block });

            // 6. Missing Block
            self.current_block = missing_block;
            const default_val = try self.generateExpression(default_expr_idx);
            _ = try self.emit(.{ .store = .{ .ptr = alloca_reg, .value = default_val } }, null);
            self.current_block.?.setTerminator(.{ .br = merge_block });

            // 7. Merge Block
            self.current_block = merge_block;
        } else {
            // Emit param instruction
            const param_reg = try self.emitWithResult(.{ .param = .{ .index = param_idx, .name = param_name } }, param_type);
            // Store param value to alloca
            _ = try self.emit(.{ .store = .{ .ptr = alloca_reg, .value = param_reg } }, null);
        }
    }

    /// Resolve a type node to IR Type
    fn resolveTypeNode(self: *Self, index: Node.Index) !Type {
        const node = self.getNode(index) orelse return .php_value;

        switch (node.tag) {
            .named_type => {
                const type_name = self.getString(node.data.named_type.name);
                if (ConcreteType.fromString(type_name)) |ct| {
                    return ct.toIRType();
                }
                // Class type
                return Type{ .php_object = type_name };
            },
            .union_type => return .php_value, // Union types use dynamic value
            .intersection_type => return .php_value,
            else => return .php_value,
        }
    }

    fn tryMakeConstInstruction(self: *Self, expr_idx: Node.Index) !?*Instruction {
        const expr_node = self.getNode(expr_idx) orelse return null;
        const module = self.module orelse return null;

        const inst = try self.allocator.create(Instruction);
        errdefer self.allocator.destroy(inst);
        inst.* = .{
            .op = .const_null,
            .result = null,
            .location = self.current_location,
        };

        switch (expr_node.tag) {
            .literal_int => inst.op = .{ .const_int = expr_node.data.literal_int.value },
            .literal_float => inst.op = .{ .const_float = expr_node.data.literal_float.value },
            .literal_null => inst.op = .const_null,
            .literal_bool => inst.op = .{ .const_bool = expr_node.main_token.tag == .k_true },
            .literal_string => {
                const s = self.getString(expr_node.data.literal_string.value);
                const id = try module.internString(s);
                inst.op = .{ .const_string = id };
            },
            else => {
                self.allocator.destroy(inst);
                return null;
            },
        }

        return inst;
    }

    /// Generate IR for class declaration
    fn generateClassDecl(self: *Self, node: *const Node) !void {
        // 安全检查：class_decl应该使用container_decl数据
        if (node.tag != .class_decl) return;

        // 使用@field安全获取，如果失败则返回
        const class_data = node.data.container_decl;
        const class_name = self.getString(class_data.name);

        var properties = std.ArrayListUnmanaged(TypeDef.Property){};

        // Create type definition
        const type_def = try self.allocator.create(TypeDef);
        type_def.* = .{
            .name = class_name,
            .kind = .class,
            .parent = if (class_data.extends) |ext_idx| blk: {
                const ext_node = self.getNode(ext_idx) orelse break :blk null;
                if (ext_node.tag == .named_type) {
                    break :blk self.getString(ext_node.data.named_type.name);
                }
                break :blk null;
            } else null,
            .interfaces = &.{},
            .properties = &.{},
            .methods = &.{},
            .location = self.current_location,
        };

        if (self.module) |module| {
            try module.addTypeDef(type_def);
        }

        // Register class in symbol table
        try self.symbol_table.defineClass(class_name, type_def.parent, &.{}, self.current_location);

        // Enter class scope
        _ = try self.symbol_table.enterScope(.class, class_name);

        // Process class members
        for (class_data.members) |member_idx| {
            const member = self.getNode(member_idx) orelse continue;
            switch (member.tag) {
                .method_decl => try self.generateMethodDecl(member, class_name),
                .property_decl => {
                    const prop_data = member.data.property_decl;
                    const prop_name = self.getString(prop_data.name);
                    const prop_type = if (prop_data.type) |t| try self.resolveTypeNode(t) else .php_value;
                    const default_inst = if (prop_data.default_value) |dv| try self.tryMakeConstInstruction(dv) else null;

                    const visibility: TypeDef.Visibility = if (prop_data.modifiers.is_private)
                        .private
                    else if (prop_data.modifiers.is_protected)
                        .protected
                    else
                        .public;

                    try properties.append(self.allocator, .{
                        .name = prop_name,
                        .type_ = prop_type,
                        .default_value = default_inst,
                        .is_static = prop_data.modifiers.is_static,
                        .visibility = visibility,
                    });

                    try self.generatePropertyDecl(member, class_name);
                },
                .const_decl => try self.generateClassConstDecl(member, class_name),
                else => {},
            }
        }

        type_def.properties = try properties.toOwnedSlice(self.allocator);

        // Leave class scope
        self.symbol_table.leaveScope();
    }

    /// Generate IR for interface declaration
    fn generateInterfaceDecl(self: *Self, node: *const Node) !void {
        const iface_data = node.data.container_decl;
        const iface_name = self.getString(iface_data.name);

        const type_def = try self.allocator.create(TypeDef);
        type_def.* = .{
            .name = iface_name,
            .kind = .interface,
            .parent = null,
            .interfaces = &.{},
            .properties = &.{},
            .methods = &.{},
            .location = self.current_location,
        };

        if (self.module) |module| {
            try module.addTypeDef(type_def);
        }
    }

    /// Generate IR for trait declaration
    fn generateTraitDecl(self: *Self, node: *const Node) !void {
        const trait_data = node.data.container_decl;
        const trait_name = self.getString(trait_data.name);

        const type_def = try self.allocator.create(TypeDef);
        type_def.* = .{
            .name = trait_name,
            .kind = .trait,
            .parent = null,
            .interfaces = &.{},
            .properties = &.{},
            .methods = &.{},
            .location = self.current_location,
        };

        if (self.module) |module| {
            try module.addTypeDef(type_def);
        }
    }

    /// Generate IR for method declaration
    fn generateMethodDecl(self: *Self, node: *const Node, class_name: []const u8) !void {
        const method_data = node.data.method_decl;
        const method_name = self.getString(method_data.name);

        // Create function with mangled name
        var buf: [256]u8 = undefined;
        const full_name = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_name, method_name }) catch method_name;
        const name_copy = try self.allocator.dupe(u8, full_name);

        const func = try self.allocator.create(Function);
        func.* = Function.init(self.allocator, name_copy);
        func.is_method = true;
        func.class_name = class_name;
        func.location = self.current_location;

        if (self.module) |module| {
            try module.addFunction(func);
        }

        // Generate method body if present
        if (method_data.body) |body_idx| {
            const prev_function = self.current_function;
            const prev_block = self.current_block;
            const prev_var_registers = self.var_registers;

            self.current_function = func;
            self.var_registers = .{};
            self.block_counter = 0;

            const entry = try func.createBlock("entry");
            self.setCurrentBlock(entry);

            // Add $this parameter for non-static methods
            if (!method_data.modifiers.is_static) {
                try func.addParam(.{
                    .name = "this",
                    .type_ = Type{ .php_object = class_name },
                    .has_default = false,
                    .is_variadic = false,
                    .is_reference = false,
                });
                
                // Emit param instruction
                const param_reg = try self.emitWithResult(.{ .param = .{ .index = 0, .name = "this" } }, Type{ .php_object = class_name });

                // 同时注册$this变量，以便在方法体中通过$this访问
                const this_reg = try self.getOrCreateVarRegister("this", .php_value);
                _ = try self.emit(.{ .store = .{ .ptr = this_reg, .value = param_reg } }, null);
                
                try self.var_registers.put(self.allocator, "$this", this_reg);
            }

            // Process parameters
            for (method_data.params) |param_idx| {
                try self.generateParameter(param_idx);
            }

            // Generate body
            try self.generateStatement(body_idx);

            if (!self.isBlockTerminated()) {
                self.setTerminator(.{ .ret = null });
            }

            self.var_registers.deinit(self.allocator);
            self.var_registers = prev_var_registers;
            self.current_function = prev_function;
            self.current_block = prev_block;
        }
    }

    /// Generate IR for property declaration
    fn generatePropertyDecl(self: *Self, node: *const Node, class_name: []const u8) !void {
        _ = class_name;
        const prop_data = node.data.property_decl;
        const prop_name = self.getString(prop_data.name);

        // Register property in symbol table
        var prop_type: InferredType = .dynamic;
        if (prop_data.type) |type_idx| {
            const ir_type = try self.resolveTypeNode(type_idx);
            prop_type = .{ .concrete = irTypeToConcreteType(ir_type) };
        }

        try self.symbol_table.defineVariable(prop_name, prop_type, self.current_location);
    }

    /// Generate IR for class constant declaration
    fn generateClassConstDecl(self: *Self, node: *const Node, class_name: []const u8) !void {
        _ = class_name;
        const const_data = node.data.const_decl;
        const const_name = self.getString(const_data.name);

        // Evaluate constant value
        const value_reg = try self.generateExpression(const_data.value);
        _ = value_reg;

        // Register constant
        try self.symbol_table.defineConstant(const_name, .dynamic, self.current_location);
    }

    /// Generate IR for if statement
    fn generateIfStmt(self: *Self, node: *const Node) !void {
        const if_data = node.data.if_stmt;

        // Generate condition
        const cond_reg = try self.generateExpression(if_data.condition);

        // Create blocks
        const then_block = try self.createBlock("if_then");
        const else_block = if (if_data.else_branch != null)
            try self.createBlock("if_else")
        else
            null;
        const merge_block = try self.createBlock("if_merge");

        // Conditional branch
        self.setTerminator(.{ .cond_br = .{
            .cond = cond_reg,
            .then_block = then_block,
            .else_block = else_block orelse merge_block,
        } });

        // Generate then branch
        self.setCurrentBlock(then_block);
        try self.generateStatement(if_data.then_branch);
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = merge_block });
        }

        // Generate else branch if present
        if (if_data.else_branch) |else_idx| {
            self.setCurrentBlock(else_block.?);
            try self.generateStatement(else_idx);
            if (!self.isBlockTerminated()) {
                self.setTerminator(.{ .br = merge_block });
            }
        }

        // Continue in merge block
        self.setCurrentBlock(merge_block);
    }

    /// Generate IR for while statement
    fn generateWhileStmt(self: *Self, node: *const Node) !void {
        const while_data = node.data.while_stmt;

        // Create blocks
        const cond_block = try self.createBlock("while_cond");
        const body_block = try self.createBlock("while_body");
        const exit_block = try self.createBlock("while_exit");

        // Jump to condition
        self.setTerminator(.{ .br = cond_block });

        // Push loop context
        try self.loop_stack.append(self.allocator, .{
            .break_block = exit_block,
            .continue_block = cond_block,
        });

        // Generate condition
        self.setCurrentBlock(cond_block);
        const cond_reg = try self.generateExpression(while_data.condition);
        self.setTerminator(.{ .cond_br = .{
            .cond = cond_reg,
            .then_block = body_block,
            .else_block = exit_block,
        } });

        // Generate body
        self.setCurrentBlock(body_block);
        try self.generateStatement(while_data.body);
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = cond_block });
        }

        // Pop loop context
        _ = self.loop_stack.pop();

        // Continue in exit block
        self.setCurrentBlock(exit_block);
    }

    /// Generate IR for for statement
    fn generateForStmt(self: *Self, node: *const Node) !void {
        const for_data = node.data.for_stmt;

        // Generate init
        if (for_data.init) |init_idx| {
            try self.generateStatement(init_idx);
        }

        // Create blocks
        const cond_block = try self.createBlock("for_cond");
        const body_block = try self.createBlock("for_body");
        const loop_block = try self.createBlock("for_loop");
        const exit_block = try self.createBlock("for_exit");

        // Jump to condition
        self.setTerminator(.{ .br = cond_block });

        // Push loop context
        try self.loop_stack.append(self.allocator, .{
            .break_block = exit_block,
            .continue_block = loop_block,
        });

        // Generate condition
        self.setCurrentBlock(cond_block);
        if (for_data.condition) |cond_idx| {
            const cond_reg = try self.generateExpression(cond_idx);
            self.setTerminator(.{ .cond_br = .{
                .cond = cond_reg,
                .then_block = body_block,
                .else_block = exit_block,
            } });
        } else {
            // Infinite loop if no condition
            self.setTerminator(.{ .br = body_block });
        }

        // Generate body
        self.setCurrentBlock(body_block);
        try self.generateStatement(for_data.body);
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = loop_block });
        }

        // Generate loop expression
        self.setCurrentBlock(loop_block);
        if (for_data.loop) |loop_idx| {
            _ = try self.generateExpression(loop_idx);
        }
        self.setTerminator(.{ .br = cond_block });

        // Pop loop context
        _ = self.loop_stack.pop();

        // Continue in exit block
        self.setCurrentBlock(exit_block);
    }

    /// Generate IR for for-range statement
    fn generateForRangeStmt(self: *Self, node: *const Node) !void {
        const range_data = node.data.for_range_stmt;

        // Get count
        const count_reg = try self.generateExpression(range_data.count);

        // Create counter variable
        const counter_reg = try self.emitWithResult(.{ .const_int = 0 }, .i64);

        // Create blocks
        const cond_block = try self.createBlock("range_cond");
        const body_block = try self.createBlock("range_body");
        const exit_block = try self.createBlock("range_exit");

        self.setTerminator(.{ .br = cond_block });

        try self.loop_stack.append(self.allocator, .{
            .break_block = exit_block,
            .continue_block = cond_block,
        });

        // Condition: counter < count
        self.setCurrentBlock(cond_block);
        const cond_reg = try self.emitWithResult(.{ .lt = .{ .lhs = counter_reg, .rhs = count_reg } }, .bool);
        self.setTerminator(.{ .cond_br = .{
            .cond = cond_reg,
            .then_block = body_block,
            .else_block = exit_block,
        } });

        // Body
        self.setCurrentBlock(body_block);
        if (range_data.variable) |var_idx| {
            const var_node = self.getNode(var_idx);
            if (var_node != null and var_node.?.tag == .variable) {
                const var_name = self.getString(var_node.?.data.variable.name);
                const var_reg = try self.getOrCreateVarRegister(var_name, .i64);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = counter_reg } }, null);
            }
        }
        try self.generateStatement(range_data.body);
        if (!self.isBlockTerminated()) {
            // Increment counter
            const one_reg = try self.emitWithResult(.{ .const_int = 1 }, .i64);
            _ = try self.emitWithResult(.{ .add = .{ .lhs = counter_reg, .rhs = one_reg } }, .i64);
            self.setTerminator(.{ .br = cond_block });
        }

        _ = self.loop_stack.pop();
        self.setCurrentBlock(exit_block);
    }

    /// Generate IR for foreach statement
    fn generateForeachStmt(self: *Self, node: *const Node) !void {
        const foreach_data = node.data.foreach_stmt;

        // Get iterable
        const iterable_reg = try self.generateExpression(foreach_data.iterable);

        // Create blocks
        const cond_block = try self.createBlock("foreach_cond");
        const body_block = try self.createBlock("foreach_body");
        const increment_block = try self.createBlock("foreach_increment");
        const exit_block = try self.createBlock("foreach_exit");

        // Initialize iterator
        const iter_args = try self.allocator.alloc(Register, 1);
        iter_args[0] = iterable_reg;
        
        // iter_addr = php_array_iter_init(iterable)
        const iter_addr = try self.emitWithResult(.{ .call = .{
            .func_name = "php_array_iter_init",
            .args = iter_args,
            .return_type = .i64, // Using i64 for pointer address
        } }, .i64);

        // Alloc iterator storage (to update it in increment)
        const i64_type_ptr = try self.allocator.create(Type);
        i64_type_ptr.* = Type{ .i64 = {} };
        const iter_ptr_type = Type{ .ptr = i64_type_ptr };
        const iter_ptr = try self.emitWithResult(.{ .alloca = .{ .type_ = .i64, .count = 1 } }, iter_ptr_type);
        
        _ = try self.emit(.{ .store = .{ .ptr = iter_ptr, .value = iter_addr } }, null);

        // Jump to condition check
        self.setTerminator(.{ .br = cond_block });

        // Push loop context for break/continue
        try self.loop_stack.append(self.allocator, .{
            .break_block = exit_block,
            .continue_block = increment_block,
        });

        // Condition check: php_array_iter_valid(iter)
        self.setCurrentBlock(cond_block);
        const curr_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .i64 } }, .i64);
        
        const valid_args = try self.allocator.alloc(Register, 1);
        valid_args[0] = curr_iter;
        
        const cond_reg = try self.emitWithResult(.{ .call = .{
            .func_name = "php_array_iter_valid",
            .args = valid_args,
            .return_type = .bool,
        } }, .bool);
        
        self.setTerminator(.{ .cond_br = .{
            .cond = cond_reg,
            .then_block = body_block,
            .else_block = exit_block,
        } });

        // Body
        self.setCurrentBlock(body_block);
        // Load iter again (SSA)
        const body_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .i64 } }, .i64);

        // Get key if needed
        if (foreach_data.key) |key_idx| {
            const key_node = self.getNode(key_idx);
            if (key_node != null and key_node.?.tag == .variable) {
                const key_name = self.getString(key_node.?.data.variable.name);
                const key_var = try self.getOrCreateVarRegister(key_name, .php_value);
                
                const key_args = try self.allocator.alloc(Register, 1);
                key_args[0] = body_iter;
                
                const key_val = try self.emitWithResult(.{ .call = .{
                    .func_name = "php_array_iter_key",
                    .args = key_args,
                    .return_type = .php_value,
                } }, .php_value);
                
                _ = try self.emit(.{ .store = .{ .ptr = key_var, .value = key_val } }, null);
            }
        }

        // Get value
        const value_node = self.getNode(foreach_data.value);
        if (value_node != null and value_node.?.tag == .variable) {
            const value_name = self.getString(value_node.?.data.variable.name);
            const value_var = try self.getOrCreateVarRegister(value_name, .php_value);
            
            const val_args = try self.allocator.alloc(Register, 1);
            val_args[0] = body_iter;
            
            const val_val = try self.emitWithResult(.{ .call = .{
                .func_name = "php_array_iter_value",
                .args = val_args,
                .return_type = .php_value,
            } }, .php_value);
            
            _ = try self.emit(.{ .store = .{ .ptr = value_var, .value = val_val } }, null);
        }

        // Generate loop body
        try self.generateStatement(foreach_data.body);

        // Jump to increment block if not terminated
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = increment_block });
        }

        // Increment block: increment iterator
        self.setCurrentBlock(increment_block);
        const inc_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .i64 } }, .i64);
        
        const next_args = try self.allocator.alloc(Register, 1);
        next_args[0] = inc_iter;
        
        const next_iter = try self.emitWithResult(.{ .call = .{
            .func_name = "php_array_iter_next",
            .args = next_args,
            .return_type = .i64,
        } }, .i64);
        _ = try self.emit(.{ .store = .{ .ptr = iter_ptr, .value = next_iter } }, null);
        
        self.setTerminator(.{ .br = cond_block });

        // Exit block
        _ = self.loop_stack.pop();
        self.setCurrentBlock(exit_block);
        
        // Cleanup iterator
        const exit_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .i64 } }, .i64);
        
        const free_args = try self.allocator.alloc(Register, 1);
        free_args[0] = exit_iter;
        
        _ = try self.emit(.{ .call = .{
            .func_name = "php_array_iter_free",
            .args = free_args,
            .return_type = .void,
        } }, null);
    }

    /// Generate IR for switch statement
    fn generateSwitchStmt(self: *Self, node: *const Node) !void {
        const switch_data = node.data.switch_stmt;

        // 生成switch表达式
        const value_reg = try self.generateExpression(switch_data.expression);

        // 创建merge块（switch之后继续执行的地方）
        const merge_block = try self.createBlock("switch.merge");

        // 创建default块（如果有default case）
        const default_block = if (switch_data.default) |_|
            try self.createBlock("switch.default")
        else
            merge_block;

        // 为每个case创建基本块
        var case_blocks = std.ArrayListUnmanaged(*BasicBlock){};
        defer case_blocks.deinit(self.allocator);

        for (switch_data.cases, 0..) |_, i| {
            const label = try std.fmt.allocPrint(self.allocator, "switch.case.{d}", .{i});
            defer self.allocator.free(label);
            const block = try self.createBlock(label);
            try case_blocks.append(self.allocator, block);
        }

        // 构建switch cases数组
        var ir_cases = std.ArrayListUnmanaged(Terminator.SwitchCase){};
        defer ir_cases.deinit(self.allocator);

        for (switch_data.cases, 0..) |case_idx, i| {
            const case_node = self.getNode(case_idx).?;
            const case_data = case_node.data.case;

            // 计算case值（必须是常量）
            const case_value_node = self.getNode(case_data.condition).?;
            const case_const = self.getConstantValue(case_value_node);

            const case_value: i64 = if (case_const) |c| blk: {
                if (c.int_val) |val| {
                    break :blk val;
                } else if (c.float_val) |val| {
                    break :blk @intFromFloat(val);
                } else if (c.bool_val) |val| {
                    break :blk if (val) 1 else 0;
                } else {
                    break :blk 0;
                }
            } else 0;

            try ir_cases.append(self.allocator, .{
                .value = case_value,
                .block = case_blocks.items[i],
            });
        }

        // 生成switch终止指令
        const cases_slice = try self.allocator.dupe(Terminator.SwitchCase, ir_cases.items);
        self.setTerminator(.{ .switch_ = .{
            .value = value_reg,
            .cases = cases_slice,
            .default = default_block,
        } });

        // Push loop context for break (switch可以使用break)
        try self.loop_stack.append(self.allocator, .{
            .break_block = merge_block,
            .continue_block = merge_block, // switch中的continue无意义，指向merge
        });

        // 生成每个case的代码
        for (switch_data.cases, 0..) |case_idx, i| {
            self.current_block = case_blocks.items[i];
            const case_node = self.getNode(case_idx).?;
            const case_data = case_node.data.case;

            for (case_data.body) |stmt_idx| {
                try self.generateStatement(stmt_idx);
                if (self.isBlockTerminated()) break;
            }

            // 如果没有break，fall through到下一个case或merge
            if (!self.isBlockTerminated()) {
                if (i + 1 < case_blocks.items.len) {
                    // Fall through到下一个case
                    self.setTerminator(.{ .br = case_blocks.items[i + 1] });
                } else if (switch_data.default != null) {
                    // Fall through到default
                    self.setTerminator(.{ .br = default_block });
                } else {
                    // 跳转到merge
                    self.setTerminator(.{ .br = merge_block });
                }
            }
        }

        // 生成default块
        if (switch_data.default) |default_idx| {
            self.current_block = default_block;
            const default_node = self.getNode(default_idx).?;
            const default_data = default_node.data.default;

            for (default_data.body) |stmt_idx| {
                try self.generateStatement(stmt_idx);
                if (self.isBlockTerminated()) break;
            }

            if (!self.isBlockTerminated()) {
                self.setTerminator(.{ .br = merge_block });
            }
        }

        // Pop loop context
        _ = self.loop_stack.pop();

        // 继续在merge块
        self.current_block = merge_block;
    }

    /// Generate IR for try-catch-finally statement
    fn generateTryStmt(self: *Self, node: *const Node) !void {
        const try_data = node.data.try_stmt;

        // Create blocks
        const try_block = try self.createBlock("try_body");
        const catch_block = try self.createBlock("catch");
        const finally_block = if (try_data.finally_clause != null)
            try self.createBlock("finally")
        else
            null;
        const exit_block = try self.createBlock("try_exit");

        // Push try context
        try self.try_stack.append(self.allocator, .{
            .catch_block = catch_block,
            .finally_block = finally_block,
        });

        // Fix up try_block handler (it was created before push)
        try_block.exception_handler = catch_block;

        // Jump to try block
        self.setTerminator(.{ .br = try_block });

        // Generate try body
        self.setCurrentBlock(try_block);
        _ = try self.emit(.try_begin, null);
        try self.generateStatement(try_data.body);
        _ = try self.emit(.try_end, null);
        if (!self.isBlockTerminated()) {
            if (finally_block) |fb| {
                self.setTerminator(.{ .br = fb });
            } else {
                self.setTerminator(.{ .br = exit_block });
            }
        }

        // Generate catch clauses
        self.setCurrentBlock(catch_block);
        for (try_data.catch_clauses) |catch_idx| {
            try self.generateCatchClause(catch_idx, finally_block orelse exit_block);
        }
        if (!self.isBlockTerminated()) {
            if (finally_block) |fb| {
                self.setTerminator(.{ .br = fb });
            } else {
                self.setTerminator(.{ .br = exit_block });
            }
        }

        // Generate finally clause if present
        if (try_data.finally_clause) |finally_idx| {
            self.setCurrentBlock(finally_block.?);
            const finally_node = self.getNode(finally_idx);
            if (finally_node != null and finally_node.?.tag == .finally_clause) {
                try self.generateStatement(finally_node.?.data.finally_clause.body);
            }
            if (!self.isBlockTerminated()) {
                self.setTerminator(.{ .br = exit_block });
            }
        }

        // Pop try context
        _ = self.try_stack.pop();

        // Continue in exit block
        self.setCurrentBlock(exit_block);
    }

    /// Generate IR for catch clause
    fn generateCatchClause(self: *Self, index: Node.Index, next_block: *BasicBlock) !void {
        const node = self.getNode(index) orelse return;
        if (node.tag != .catch_clause) return;

        const catch_data = node.data.catch_clause;

        // Get exception type
        var exception_type: ?[]const u8 = null;
        if (catch_data.exception_type) |type_idx| {
            const type_node = self.getNode(type_idx);
            if (type_node != null and type_node.?.tag == .named_type) {
                exception_type = self.getString(type_node.?.data.named_type.name);
            }
        }

        // Emit catch instruction (returns exception object)
        const catch_reg = try self.emitWithResult(.{ .catch_ = .{ .exception_type = exception_type } }, .php_value);

        // Set up exception variable if present
        if (catch_data.variable) |var_idx| {
            const var_node = self.getNode(var_idx);
            if (var_node != null and var_node.?.tag == .variable) {
                const var_name = self.getString(var_node.?.data.variable.name);
                // Use catch_reg directly
                const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = catch_reg } }, null);
            }
        }

        // Generate catch body
        try self.generateStatement(catch_data.body);
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = next_block });
        }
    }

    /// Generate IR for lock statement (mutex syntax sugar)
    /// lock { ... } is equivalent to:
    ///   mutex_lock();
    ///   try { ... } finally { mutex_unlock(); }
    fn generateLockStmt(self: *Self, node: *const Node) !void {
        const lock_data = node.data.lock_stmt;

        // Create blocks for lock structure
        const lock_body_block = try self.createBlock("lock_body");
        const unlock_block = try self.createBlock("lock_unlock");
        const exit_block = try self.createBlock("lock_exit");

        // Emit mutex_lock instruction
        _ = try self.emit(.mutex_lock, null);

        // Jump to lock body
        self.setTerminator(.{ .br = lock_body_block });

        // Generate lock body
        self.setCurrentBlock(lock_body_block);
        try self.generateStatement(lock_data.body);

        // After body, jump to unlock block
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = unlock_block });
        }

        // Generate unlock block (always executed, like finally)
        self.setCurrentBlock(unlock_block);
        _ = try self.emit(.mutex_unlock, null);
        self.setTerminator(.{ .br = exit_block });

        // Continue in exit block
        self.setCurrentBlock(exit_block);
    }

    /// Generate IR for go statement (goroutine/coroutine spawn)
    fn generateGoStmt(self: *Self, node: *const Node) !void {
        const go_data = node.data.go_stmt;

        // go语句的调用表达式
        const call_node = self.getNode(go_data.call) orelse return;

        if (call_node.tag == .function_call) {
            const call_data = call_node.data.function_call;
            const func_name = self.getString(call_data.name);

            // 生成参数
            const args = try self.allocator.alloc(Register, call_data.args.len);
            for (call_data.args, 0..) |arg_idx, i| {
                args[i] = try self.generateExpression(arg_idx);
            }

            // 发出go_spawn指令
            _ = try self.emit(.{ .go_spawn = .{
                .func_name = func_name,
                .args = args,
            } }, null);
        }
    }

    /// Generate IR for throw statement
    fn generateThrowStmt(self: *Self, node: *const Node) !void {
        const throw_data = node.data.throw_stmt;
        const exception_reg = try self.generateExpression(throw_data.expression);
        self.setTerminator(.{ .throw = exception_reg });
    }

    /// Generate IR for return statement
    fn generateReturnStmt(self: *Self, node: *const Node) !void {
        const return_data = node.data.return_stmt;

        if (return_data.expr) |expr_idx| {
            const value_reg = try self.generateExpression(expr_idx);
            self.setTerminator(.{ .ret = value_reg });
        } else {
            self.setTerminator(.{ .ret = null });
        }
    }

    /// Generate IR for break statement
    fn generateBreakStmt(self: *Self, node: *const Node) !void {
        _ = node;
        if (self.loop_stack.items.len > 0) {
            const ctx = self.loop_stack.items[self.loop_stack.items.len - 1];
            self.setTerminator(.{ .br = ctx.break_block });
        }
    }

    /// Generate IR for continue statement
    fn generateContinueStmt(self: *Self, node: *const Node) !void {
        _ = node;
        if (self.loop_stack.items.len > 0) {
            const ctx = self.loop_stack.items[self.loop_stack.items.len - 1];
            self.setTerminator(.{ .br = ctx.continue_block });
        }
    }

    /// Generate IR for echo statement
    fn generateEchoStmt(self: *Self, node: *const Node) !void {
        const echo_data = node.data.echo_stmt;

        for (echo_data.exprs) |expr_idx| {
            const value_reg = try self.generateExpression(expr_idx);
            // Call runtime echo function
            const args = try self.allocator.alloc(Register, 1);
            args[0] = value_reg;
            _ = try self.emit(.{ .call = .{
                .func_name = "php_echo",
                .args = args,
                .return_type = .void,
            } }, null);
        }
    }

    /// Generate IR for assignment
    fn generateAssignment(self: *Self, node: *const Node) !void {
        const assign_data = node.data.assignment;

        // Generate value
        const value_reg = try self.generateExpression(assign_data.value);

        // Generate target
        const target_node = self.getNode(assign_data.target) orelse return;

        switch (target_node.tag) {
            .variable => {
                const var_name = self.getString(target_node.data.variable.name);
                const var_reg = try self.getOrCreateVarRegister(var_name, value_reg.type_);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = value_reg } }, null);

                // Update symbol table
                try self.symbol_table.defineVariable(var_name, .dynamic, self.current_location);
            },
            .array_access => {
                const array_reg = try self.generateExpression(target_node.data.array_access.target);
                if (target_node.data.array_access.index) |idx| {
                    const key_reg = try self.generateExpression(idx);
                    _ = try self.emit(.{ .array_set = .{
                        .array = array_reg,
                        .key = key_reg,
                        .value = value_reg,
                    } }, null);
                }
            },
            .property_access => {
                const obj_reg = try self.generateExpression(target_node.data.property_access.target);
                const prop_name = self.getString(target_node.data.property_access.property_name);
                _ = try self.emit(.{ .property_set = .{
                    .object = obj_reg,
                    .property_name = prop_name,
                    .value = value_reg,
                } }, null);
            },
            .variable_property_access => {
                const obj_reg = try self.generateExpression(target_node.data.variable_property_access.target);
                const prop_reg = try self.generateExpression(target_node.data.variable_property_access.prop_variable);
                const args = try self.allocator.alloc(Register, 3);
                args[0] = obj_reg;
                args[1] = prop_reg;
                args[2] = value_reg;
                _ = try self.emit(.{ .call = .{
                    .func_name = "php_object_set_dynamic",
                    .args = args,
                    .return_type = .php_value,
                } }, null);
            },
            else => {},
        }
    }

    /// Generate IR for compound assignment (+=, -=, *=, /=, %=, .=)
    /// Compound assignment: $a += $b is equivalent to $a = $a + $b
    fn generateCompoundAssignment(self: *Self, node: *const Node) !void {
        const compound_data = node.data.compound_assignment;
        const op_tag = compound_data.op;

        // Get target node
        const target_node = self.getNode(compound_data.target) orelse return;

        // Generate current value of target (read)
        const current_value = try self.generateExpression(compound_data.target);

        // Generate right-hand side value
        const rhs_value = try self.generateExpression(compound_data.value);

        // Perform the operation based on the operator
        const result_reg = switch (op_tag) {
            .plus_equal => try self.emitWithResult(.{ .add = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
            .minus_equal => try self.emitWithResult(.{ .sub = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
            .asterisk_equal => try self.emitWithResult(.{ .mul = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
            .slash_equal => try self.emitWithResult(.{ .div = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
            .percent_equal => try self.emitWithResult(.{ .mod = .{ .lhs = current_value, .rhs = rhs_value } }, .i64),
            .dot_equal => try self.emitWithResult(.{ .concat = .{ .lhs = current_value, .rhs = rhs_value } }, .php_string),
            .star_star_equal => try self.emitWithResult(.{ .pow = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
            .caret_equal => try self.emitWithResult(.{ .bit_xor = .{ .lhs = current_value, .rhs = rhs_value } }, .i64),
            .and_equal => try self.emitWithResult(.{ .bit_and = .{ .lhs = current_value, .rhs = rhs_value } }, .i64),
            .or_equal => try self.emitWithResult(.{ .bit_or = .{ .lhs = current_value, .rhs = rhs_value } }, .i64),
            .less_less_equal => try self.emitWithResult(.{ .shl = .{ .lhs = current_value, .rhs = rhs_value } }, .i64),
            .greater_greater_equal => try self.emitWithResult(.{ .shr = .{ .lhs = current_value, .rhs = rhs_value } }, .i64),
            else => return error.UnsupportedCompoundOperator,
        };

        // Store the result back to the target (write)
        switch (target_node.tag) {
            .variable => {
                const var_name = self.getString(target_node.data.variable.name);
                const var_reg = try self.getOrCreateVarRegister(var_name, result_reg.type_);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = result_reg } }, null);

                // Update symbol table
                try self.symbol_table.defineVariable(var_name, .dynamic, self.current_location);
            },
            .array_access => {
                const array_reg = try self.generateExpression(target_node.data.array_access.target);
                if (target_node.data.array_access.index) |idx| {
                    const key_reg = try self.generateExpression(idx);
                    _ = try self.emit(.{ .array_set = .{
                        .array = array_reg,
                        .key = key_reg,
                        .value = result_reg,
                    } }, null);
                }
            },
            .property_access => {
                const obj_reg = try self.generateExpression(target_node.data.property_access.target);
                const prop_name = self.getString(target_node.data.property_access.property_name);
                _ = try self.emit(.{ .property_set = .{
                    .object = obj_reg,
                    .property_name = prop_name,
                    .value = result_reg,
                } }, null);
            },
            .variable_property_access => {
                const obj_reg = try self.generateExpression(target_node.data.variable_property_access.target);
                const prop_reg = try self.generateExpression(target_node.data.variable_property_access.prop_variable);
                const args = try self.allocator.alloc(Register, 3);
                args[0] = obj_reg;
                args[1] = prop_reg;
                args[2] = result_reg;
                _ = try self.emit(.{ .call = .{
                    .func_name = "php_object_set_dynamic",
                    .args = args,
                    .return_type = .php_value,
                } }, null);
            },
            else => {},
        }
    }

    /// Generate IR for list() destructuring assignment
    fn generateListAssignment(self: *Self, node: *const Node) !void {
        const list_data = node.data.list_assignment;

        // Generate the array value
        const array_reg = try self.generateExpression(list_data.value);

        // Generate assignment for each target
        for (list_data.targets, 0..) |target_idx, i| {
            // Extract element at index i
            const index_reg = try self.emitWithResult(.{ .const_int = @as(i64, @intCast(i)) }, .i64);
            const elem_reg = try self.emitWithResult(.{ .array_get = .{
                .array = array_reg,
                .key = index_reg,
            } }, .php_value);

            // Assign to variable if target is a variable
            const target_node = self.getNode(target_idx) orelse continue;
            if (target_node.tag == .variable) {
                const var_name = self.getString(target_node.data.variable.name);
                const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = elem_reg } }, null);
                try self.symbol_table.defineVariable(var_name, .dynamic, self.current_location);
            }
        }
    }

    /// Generate IR for constant declaration
    fn generateConstDecl(self: *Self, node: *const Node) !void {
        const const_data = node.data.const_decl;
        const const_name = self.getString(const_data.name);

        // Evaluate constant value (with constant folding)
        const value_reg = try self.generateExpression(const_data.value);

        // Emit call to php_define(name, value)
        const name_id = const_data.name;
        const name_reg = try self.emitWithResult(.{ .const_string = name_id }, .php_value);
        
        const args = try self.allocator.alloc(Register, 2);
        args[0] = name_reg;
        args[1] = value_reg;
        
        _ = try self.emitWithResult(.{ .call = .{
            .func_name = "php_define",
            .args = args,
            .return_type = .php_value,
        } }, .php_value);

        try self.symbol_table.defineConstant(const_name, .dynamic, self.current_location);
    }

    /// Generate IR for global statement
    fn generateGlobalStmt(self: *Self, node: *const Node) !void {
        // 安全检查：确保data字段有效
        if (node.tag != .global_stmt) return;

        const global_data = node.data.global_stmt;
        if (global_data.vars.len == 0) return;

        for (global_data.vars) |var_idx| {
            const var_node = self.getNode(var_idx) orelse continue;
            if (var_node.tag == .variable) {
                const var_name = self.getString(var_node.data.variable.name);
                // Mark variable as global reference
                _ = try self.getOrCreateVarRegister(var_name, .php_value);
            }
        }
    }

    /// Generate IR for static statement
    fn generateStaticStmt(self: *Self, node: *const Node) !void {
        const static_data = node.data.static_stmt;

        for (static_data.vars) |var_idx| {
            const var_node = self.getNode(var_idx) orelse continue;
            if (var_node.tag == .variable) {
                const var_name = self.getString(var_node.data.variable.name);
                // Static variables persist across function calls
                _ = try self.getOrCreateVarRegister(var_name, .php_value);
            }
        }
    }

    // ========================================================================
    // Expression Generation
    // ========================================================================

    /// Generate IR for an expression, returning the result register
    pub fn generateExpression(self: *Self, index: Node.Index) anyerror!Register {
        const node = self.getNode(index) orelse {
            return self.emitWithResult(.const_null, .php_value);
        };
        self.updateLocation(node.main_token);

        return switch (node.tag) {
            // Literals
            .literal_int => self.generateLiteralInt(node),
            .literal_float => self.generateLiteralFloat(node),
            .literal_string => self.generateLiteralString(node),
            .literal_bool => self.generateLiteralBool(node),
            .literal_null => self.emitWithResult(.const_null, .php_value),
            .magic_constant => self.generateMagicConstant(node),

            // Variables
            .variable => self.generateVariable(node),

            // Expressions
            .binary_expr => self.generateBinaryExpr(node),
            .unary_expr => self.generateUnaryExpr(node),
            .postfix_expr => self.generatePostfixExpr(node),
            .ternary_expr => self.generateTernaryExpr(node),

            // Function calls
            .function_call => self.generateFunctionCall(node),
            .method_call => self.generateMethodCall(node),
            .static_method_call => self.generateStaticMethodCall(node),

            // Array operations
            .array_init => self.generateArrayInit(node),
            .array_access => self.generateArrayAccess(node),

            // Object operations
            .object_instantiation => self.generateObjectInstantiation(node),
            .property_access => self.generatePropertyAccess(node),
            .safe_property_access => self.generateSafePropertyAccess(node),
            .variable_property_access => self.generateVariablePropertyAccess(node),
            .static_property_access => self.generateStaticPropertyAccess(node),
            .class_constant_access => self.generateClassConstantAccess(node),

            // Closures
            .closure => self.generateClosure(node),
            .arrow_function => self.generateArrowFunction(node),

            // Special expressions
            .match_expr => self.generateMatchExpr(node),
            .clone_with_expr => self.generateCloneWithExpr(node),
            .named_arg => self.generateNamedArg(node),
            .cast_expr => self.generateCastExpr(node),

            // $this 表达式 - 返回this参数寄存器
            .self_expr => blk: {
                if (self.lookupVarRegister("this")) |ptr_reg| {
                    break :blk self.emitWithResult(.{ .load = .{ .ptr = ptr_reg, .type_ = .php_value } }, .php_value);
                }
                break :blk self.emitWithResult(.const_null, .php_value);
            },

            // Assignment as expression
            .assignment => blk: {
                try self.generateAssignment(node);
                // Return the assigned value
                const assign_data = node.data.assignment;
                break :blk self.generateExpression(assign_data.value);
            },

            // Compound assignment as expression
            .compound_assignment => blk: {
                const compound_data = node.data.compound_assignment;

                // Get target node
                const target_node = self.getNode(compound_data.target) orelse {
                    break :blk try self.emitWithResult(.const_null, .php_value);
                };

                // Generate current value of target (read)
                const current_value = try self.generateExpression(compound_data.target);

                // Generate right-hand side value
                const rhs_value = try self.generateExpression(compound_data.value);

                // Perform the operation based on the operator
                const result_reg = switch (compound_data.op) {
                    .plus_equal => try self.emitWithResult(.{ .add = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
                    .minus_equal => try self.emitWithResult(.{ .sub = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
                    .asterisk_equal => try self.emitWithResult(.{ .mul = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
                    .slash_equal => try self.emitWithResult(.{ .div = .{ .lhs = current_value, .rhs = rhs_value } }, current_value.type_),
                    .percent_equal => try self.emitWithResult(.{ .mod = .{ .lhs = current_value, .rhs = rhs_value } }, .i64),
                    .dot_equal => try self.emitWithResult(.{ .concat = .{ .lhs = current_value, .rhs = rhs_value } }, .php_string),
                    else => try self.emitWithResult(.const_null, .php_value),
                };

                // Store the result back to the target (write)
                switch (target_node.tag) {
                    .variable => {
                        const var_name = self.getString(target_node.data.variable.name);
                        const var_reg = try self.getOrCreateVarRegister(var_name, result_reg.type_);
                        _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = result_reg } }, null);
                        try self.symbol_table.defineVariable(var_name, .dynamic, self.current_location);
                    },
                    .array_access => {
                        const array_reg = try self.generateExpression(target_node.data.array_access.target);
                        if (target_node.data.array_access.index) |idx| {
                            const key_reg = try self.generateExpression(idx);
                            _ = try self.emit(.{ .array_set = .{
                                .array = array_reg,
                                .key = key_reg,
                                .value = result_reg,
                            } }, null);
                        }
                    },
                    .property_access => {
                        const obj_reg = try self.generateExpression(target_node.data.property_access.target);
                        const prop_name = self.getString(target_node.data.property_access.property_name);
                        _ = try self.emit(.{ .property_set = .{
                            .object = obj_reg,
                            .property_name = prop_name,
                            .value = result_reg,
                        } }, null);
                    },
                    .variable_property_access => {
                        const obj_reg = try self.generateExpression(target_node.data.variable_property_access.target);
                        const prop_reg = try self.generateExpression(target_node.data.variable_property_access.prop_variable);
                        const args = try self.allocator.alloc(Register, 3);
                        args[0] = obj_reg;
                        args[1] = prop_reg;
                        args[2] = result_reg;
                        _ = try self.emit(.{ .call = .{
                            .func_name = "php_object_set_dynamic",
                            .args = args,
                            .return_type = .php_value,
                        } }, null);
                    },
                    else => {},
                }

                // Return the result value
                break :blk result_reg;
            },

            else => self.emitWithResult(.const_null, .php_value),
        };
    }

    /// Generate IR for integer literal
    fn generateLiteralInt(self: *Self, node: *const Node) !Register {
        const value = node.data.literal_int.value;

        // Constant folding: just emit the constant
        return self.emitWithResult(.{ .const_int = value }, .i64);
    }

    /// Generate IR for float literal
    fn generateLiteralFloat(self: *Self, node: *const Node) !Register {
        const value = node.data.literal_float.value;
        return self.emitWithResult(.{ .const_float = value }, .f64);
    }

    /// Generate IR for string literal
    fn generateLiteralString(self: *Self, node: *const Node) !Register {
        const string_id = node.data.literal_string.value;

        // Intern string in module
        if (self.module) |module| {
            const str = self.getString(string_id);
            const interned_id = try module.internString(str);
            return self.emitWithResult(.{ .const_string = interned_id }, .php_string);
        }

        return self.emitWithResult(.{ .const_string = string_id }, .php_string);
    }

    /// Generate IR for boolean literal
    fn generateLiteralBool(self: *Self, node: *const Node) !Register {
        // Boolean value is determined by the token
        const is_true = node.main_token.tag == .k_true;
        return self.emitWithResult(.{ .const_bool = is_true }, .bool);
    }

    fn generateMagicConstant(self: *Self, node: *const Node) !Register {
        const kind = node.data.magic_constant.kind;
        const module = self.module orelse return self.emitWithResult(.const_null, .php_value);

        return switch (kind) {
            .line => self.emitWithResult(.{ .const_int = @as(i64, @intCast(self.current_location.line)) }, .php_value),
            .file => blk: {
                const s = module.source_file;
                const id = try module.internString(s);
                break :blk self.emitWithResult(.{ .const_string = id }, .php_value);
            },
            .dir => blk: {
                const dir = std.fs.path.dirname(module.source_file) orelse "";
                const id = try module.internString(dir);
                break :blk self.emitWithResult(.{ .const_string = id }, .php_value);
            },
            .function => blk: {
                const name = if (self.current_function) |f| f.name else "";
                const id = try module.internString(name);
                break :blk self.emitWithResult(.{ .const_string = id }, .php_value);
            },
            .class => blk: {
                const name = self.lookupCurrentClassName() orelse "";
                const id = try module.internString(name);
                break :blk self.emitWithResult(.{ .const_string = id }, .php_value);
            },
            .method => blk: {
                const class_name = self.lookupCurrentClassName() orelse "";
                const func_name = if (self.current_function) |f| f.name else "";
                var buf: [256]u8 = undefined;
                const full = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_name, func_name }) catch func_name;
                const id = try module.internString(full);
                break :blk self.emitWithResult(.{ .const_string = id }, .php_value);
            },
            .namespace => blk: {
                const id = try module.internString("");
                break :blk self.emitWithResult(.{ .const_string = id }, .php_value);
            },
        };
    }

    fn lookupCurrentClassName(self: *Self) ?[]const u8 {
        var i: usize = self.symbol_table.scope_stack.items.len;
        while (i > 0) {
            i -= 1;
            const scope = self.symbol_table.scope_stack.items[i];
            if (scope.kind == .class) {
                return scope.name;
            }
        }
        return null;
    }

    /// Generate IR for binary expression
    fn generateBinaryExpr(self: *Self, node: *const Node) !Register {
        const bin_data = node.data.binary_expr;

        // Try constant folding first
        if (try self.tryConstantFold(node)) |folded_reg| {
            return folded_reg;
        }

        // Generate operands
        const lhs_reg = try self.generateExpression(bin_data.lhs);
        const rhs_reg = try self.generateExpression(bin_data.rhs);

        // 推断算术运算的结果类型
        // 如果任一操作数是php_value，结果就是php_value
        // 否则使用左操作数的类型
        const arith_result_type = blk: {
            const lhs_tag = @as(std.meta.Tag(Type), lhs_reg.type_);
            const rhs_tag = @as(std.meta.Tag(Type), rhs_reg.type_);
            if (lhs_tag == .php_value or rhs_tag == .php_value) {
                break :blk Type{ .php_value = {} };
            }
            break :blk lhs_reg.type_;
        };

        // Map operator to IR operation
        const op = bin_data.op;
        return switch (op) {
            // Arithmetic
            .plus => self.emitWithResult(.{ .add = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, arith_result_type),
            .minus => self.emitWithResult(.{ .sub = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, arith_result_type),
            .asterisk => self.emitWithResult(.{ .mul = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, arith_result_type),
            .slash => self.emitWithResult(.{ .div = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, arith_result_type),
            .percent => self.emitWithResult(.{ .mod = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .i64),
            .star_star => self.emitWithResult(.{ .pow = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, arith_result_type),

            // Comparison
            .equal_equal => self.emitWithResult(.{ .eq = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .bang_equal => self.emitWithResult(.{ .ne = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .equal_equal_equal => self.emitWithResult(.{ .identical = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .bang_equal_equal => self.emitWithResult(.{ .not_identical = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .less => self.emitWithResult(.{ .lt = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .less_equal => self.emitWithResult(.{ .le = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .greater => self.emitWithResult(.{ .gt = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .greater_equal => self.emitWithResult(.{ .ge = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .spaceship => self.emitWithResult(.{ .spaceship = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .i64),

            // Logical
            .k_and, .double_ampersand => self.emitWithResult(.{ .and_ = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),
            .k_or, .double_pipe => self.emitWithResult(.{ .or_ = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .bool),

            // Bitwise
            .ampersand => self.emitWithResult(.{ .bit_and = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .i64),
            .pipe => self.emitWithResult(.{ .bit_or = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .i64),
            .caret => self.emitWithResult(.{ .bit_xor = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .i64),
            .less_less => self.emitWithResult(.{ .shl = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .i64),
            .greater_greater => self.emitWithResult(.{ .shr = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .i64),

            // String concatenation
            .dot => self.emitWithResult(.{ .concat = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_string),

            // Null coalescing
            .double_question => self.generateNullCoalesce(lhs_reg, rhs_reg),
            // .question_question => self.generateNullCoalesce(lhs_reg, rhs_reg),

            else => self.emitWithResult(.{ .add = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
        };
    }

    /// Generate null coalescing operator
    fn generateNullCoalesce(self: *Self, lhs_reg: Register, rhs_reg: Register) !Register {
        // Check if lhs is null
        const is_null = try self.emitWithResult(.{ .type_check = .{
            .value = lhs_reg,
            .expected_type = .php_value,
        } }, .bool);

        // Select based on null check
        return self.emitWithResult(.{ .select = .{
            .cond = is_null,
            .then_value = rhs_reg,
            .else_value = lhs_reg,
        } }, .php_value);
    }

    /// Generate IR for unary expression
    fn generateUnaryExpr(self: *Self, node: *const Node) !Register {
        const unary_data = node.data.unary_expr;

        // Try constant folding
        if (try self.tryConstantFold(node)) |folded_reg| {
            return folded_reg;
        }

        // 处理前置递增递减运算符
        if (unary_data.op == .plus_plus or unary_data.op == .minus_minus) {
            // 生成表达式（获取变量的值）
            const operand_reg = try self.generateExpression(unary_data.expr);

            // 生成递增/递减操作
            const one_reg = try self.emitWithResult(.{ .const_int = 1 }, .i64);
            const new_value = switch (unary_data.op) {
                .plus_plus => try self.emitWithResult(.{ .add = .{ .lhs = operand_reg, .rhs = one_reg } }, operand_reg.type_),
                .minus_minus => try self.emitWithResult(.{ .sub = .{ .lhs = operand_reg, .rhs = one_reg } }, operand_reg.type_),
                else => unreachable,
            };

            // 存储回变量
            const expr_node = self.getNode(unary_data.expr);
            if (expr_node != null and expr_node.?.tag == .variable) {
                const var_name = self.getString(expr_node.?.data.variable.name);
                if (self.lookupVarRegister(var_name)) |ptr_reg| {
                    _ = try self.emit(.{ .store = .{ .ptr = ptr_reg, .value = new_value } }, null);
                }
            }

            // 前置运算符返回新值
            return new_value;
        }

        const operand_reg = try self.generateExpression(unary_data.expr);

        return switch (unary_data.op) {
            .minus => self.emitWithResult(.{ .neg = .{ .operand = operand_reg } }, operand_reg.type_),
            .bang => self.emitWithResult(.{ .not = .{ .operand = operand_reg } }, .bool),
            .tilde => self.emitWithResult(.{ .bit_not = .{ .operand = operand_reg } }, .i64),
            .plus => operand_reg, // Unary plus is a no-op
            else => operand_reg,
        };
    }

    /// Generate IR for postfix expression (++, --)
    fn generatePostfixExpr(self: *Self, node: *const Node) !Register {
        const postfix_data = node.data.postfix_expr;

        // 生成表达式（获取变量的值）
        const operand_reg = try self.generateExpression(postfix_data.expr);

        // 在SSA形式中，operand_reg是不可变的，所以它就是原始值
        // 我们可以直接使用它作为返回值

        // 生成递增/递减操作（创建新的寄存器）
        const one_reg = try self.emitWithResult(.{ .const_int = 1 }, .i64);
        const new_value = switch (postfix_data.op) {
            .plus_plus => try self.emitWithResult(.{ .add = .{ .lhs = operand_reg, .rhs = one_reg } }, operand_reg.type_),
            .minus_minus => try self.emitWithResult(.{ .sub = .{ .lhs = operand_reg, .rhs = one_reg } }, operand_reg.type_),
            else => operand_reg,
        };

        // 存储回变量
        const expr_node = self.getNode(postfix_data.expr);
        if (expr_node != null and expr_node.?.tag == .variable) {
            const var_name = self.getString(expr_node.?.data.variable.name);
            if (self.lookupVarRegister(var_name)) |ptr_reg| {
                _ = try self.emit(.{ .store = .{ .ptr = ptr_reg, .value = new_value } }, null);
            }
        }

        // 后置运算符返回原始值（operand_reg在SSA中是不可变的）
        return operand_reg;
    }

    /// Generate IR for ternary expression
    fn generateTernaryExpr(self: *Self, node: *const Node) !Register {
        const ternary_data = node.data.ternary_expr;

        // Generate condition
        const cond_reg = try self.generateExpression(ternary_data.cond);

        // Create blocks
        const then_block = try self.createBlock("ternary_then");
        const else_block = try self.createBlock("ternary_else");
        const merge_block = try self.createBlock("ternary_merge");

        // Conditional branch
        self.setTerminator(.{ .cond_br = .{
            .cond = cond_reg,
            .then_block = then_block,
            .else_block = else_block,
        } });

        // Generate then expression
        self.setCurrentBlock(then_block);
        const then_reg = if (ternary_data.then_expr) |then_idx|
            try self.generateExpression(then_idx)
        else
            cond_reg; // Elvis operator: $a ?: $b
        self.setTerminator(.{ .br = merge_block });

        // Generate else expression
        self.setCurrentBlock(else_block);
        const else_reg = try self.generateExpression(ternary_data.else_expr);
        self.setTerminator(.{ .br = merge_block });

        // Merge with phi node
        self.setCurrentBlock(merge_block);

        const incoming = try self.allocator.alloc(Instruction.PhiIncoming, 2);
        incoming[0] = .{ .value = then_reg, .block = then_block };
        incoming[1] = .{ .value = else_reg, .block = else_block };

        return self.emitWithResult(.{ .phi = .{ .incoming = incoming } }, .php_value);
    }

    /// Generate IR for function call
    fn generateFunctionCall(self: *Self, node: *const Node) !Register {
        const call_data = node.data.function_call;

        // Get function name
        const name_node = self.getNode(call_data.name) orelse {
            return self.emitWithResult(.const_null, .php_value);
        };

        var func_name: []const u8 = "";
        if (name_node.tag == .variable) {
            const is_variable_token = name_node.main_token.tag == .t_variable;
            if (is_variable_token) {
                const var_name = self.getString(name_node.data.variable.name);
                // Get variable register
                var func_reg: Register = undefined;
                if (self.var_registers.get(var_name)) |reg| {
                    func_reg = try self.emitWithResult(.{ .load = .{ .ptr = reg, .type_ = .php_value } }, .php_value);
                } else {
                    func_reg = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                }
                
                // Generate arguments
                const args = try self.allocator.alloc(Register, call_data.args.len);
                for (call_data.args, 0..) |arg_idx, i| {
                    args[i] = try self.generateExpression(arg_idx);
                }

                return self.emitWithResult(.{ .call_indirect = .{
                    .func_ptr = func_reg,
                    .args = args,
                    .return_type = .php_value,
                } }, .php_value);
            } else {
                // Static function call (identifier)
                func_name = self.getString(name_node.data.variable.name);
            }
        } else if (name_node.tag == .literal_string) {
            func_name = self.getString(name_node.data.literal_string.value);
        }

        // Generate arguments
        const args = try self.allocator.alloc(Register, call_data.args.len);
        for (call_data.args, 0..) |arg_idx, i| {
            args[i] = try self.generateExpression(arg_idx);
        }

        return self.emitWithResult(.{ .call = .{
            .func_name = func_name,
            .args = args,
            .return_type = .php_value,
        } }, .php_value);
    }

    /// Generate IR for method call
    fn generateMethodCall(self: *Self, node: *const Node) !Register {
        const call_data = node.data.method_call;

        // Generate target object
        const obj_reg = try self.generateExpression(call_data.target);
        const method_name = self.getString(call_data.method_name);

        // Generate arguments
        const args = try self.allocator.alloc(Register, call_data.args.len);
        for (call_data.args, 0..) |arg_idx, i| {
            args[i] = try self.generateExpression(arg_idx);
        }

        return self.emitWithResult(.{ .method_call = .{
            .object = obj_reg,
            .method_name = method_name,
            .args = args,
        } }, .php_value);
    }

    /// Generate IR for static method call
    fn generateStaticMethodCall(self: *Self, node: *const Node) !Register {
        const call_data = node.data.static_method_call;
        const class_name = self.getString(call_data.class_name);
        const method_name = self.getString(call_data.method_name);

        // Generate arguments
        const args = try self.allocator.alloc(Register, call_data.args.len);
        for (call_data.args, 0..) |arg_idx, i| {
            args[i] = try self.generateExpression(arg_idx);
        }

        // Mangle name for static call
        var buf: [256]u8 = undefined;
        const full_name = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_name, method_name }) catch method_name;
        const name_copy = try self.allocator.dupe(u8, full_name);

        return self.emitWithResult(.{ .call = .{
            .func_name = name_copy,
            .args = args,
            .return_type = .php_value,
        } }, .php_value);
    }

    /// Generate IR for array initialization
    fn generateArrayInit(self: *Self, node: *const Node) !Register {
        const array_data = node.data.array_init;

        // Create new array
        const capacity: u32 = @intCast(array_data.elements.len);
        const arr_reg = try self.emitWithResult(.{ .array_new = .{ .capacity = capacity } }, .php_array);

        // Add elements
        for (array_data.elements) |elem_idx| {
            const elem_node = self.getNode(elem_idx) orelse continue;

            if (elem_node.tag == .array_pair) {
                // Key-value pair
                const key_reg = try self.generateExpression(elem_node.data.array_pair.key);
                const val_reg = try self.generateExpression(elem_node.data.array_pair.value);
                _ = try self.emit(.{ .array_set = .{
                    .array = arr_reg,
                    .key = key_reg,
                    .value = val_reg,
                } }, null);
            } else {
                // Value only - push to array
                const val_reg = try self.generateExpression(elem_idx);
                _ = try self.emit(.{ .array_push = .{
                    .array = arr_reg,
                    .value = val_reg,
                } }, null);
            }
        }

        return arr_reg;
    }

    /// Generate IR for array access
    fn generateArrayAccess(self: *Self, node: *const Node) !Register {
        const access_data = node.data.array_access;

        const arr_reg = try self.generateExpression(access_data.target);

        if (access_data.index) |idx| {
            const key_reg = try self.generateExpression(idx);
            return self.emitWithResult(.{ .array_get = .{
                .array = arr_reg,
                .key = key_reg,
            } }, .php_value);
        }

        // No index - return array itself (for $arr[] = value)
        return arr_reg;
    }

    /// Generate IR for object instantiation
    fn generateObjectInstantiation(self: *Self, node: *const Node) !Register {
        const inst_data = node.data.object_instantiation;

        // Get class name
        const class_node = self.getNode(inst_data.class_name) orelse {
            return self.emitWithResult(.const_null, .php_value);
        };

        var class_name: []const u8 = "";
        if (class_node.tag == .named_type) {
            class_name = self.getString(class_node.data.named_type.name);
        } else if (class_node.tag == .variable) {
            class_name = self.getString(class_node.data.variable.name);
        }

        // Generate constructor arguments
        const args = try self.allocator.alloc(Register, inst_data.args.len);
        for (inst_data.args, 0..) |arg_idx, i| {
            args[i] = try self.generateExpression(arg_idx);
        }

        return self.emitWithResult(.{ .new_object = .{
            .class_name = class_name,
            .args = args,
        } }, Type{ .php_object = class_name });
    }

    /// Generate IR for property access
    fn generatePropertyAccess(self: *Self, node: *const Node) !Register {
        const access_data = node.data.property_access;

        const obj_reg = try self.generateExpression(access_data.target);
        const prop_name = self.getString(access_data.property_name);

        return self.emitWithResult(.{ .property_get = .{
            .object = obj_reg,
            .property_name = prop_name,
        } }, .php_value);
    }

    fn emitPropertyNameValue(self: *Self, property_name: []const u8) !Register {
        const module = self.module orelse return self.emitWithResult(.const_null, .php_value);
        const id = try module.internString(property_name);
        return self.emitWithResult(.{ .const_string = id }, .php_string);
    }

    fn generateSafePropertyAccess(self: *Self, node: *const Node) !Register {
        const access_data = node.data.safe_property_access;
        const obj_reg = try self.generateExpression(access_data.target);
        const prop_val_reg = try self.emitPropertyNameValue(self.getString(access_data.property_name));
        const args = try self.allocator.alloc(Register, 2);
        args[0] = obj_reg;
        args[1] = prop_val_reg;
        return self.emitWithResult(.{ .call = .{
            .func_name = "php_object_get_safe_value",
            .args = args,
            .return_type = .php_value,
        } }, .php_value);
    }

    fn generateVariablePropertyAccess(self: *Self, node: *const Node) !Register {
        const access_data = node.data.variable_property_access;
        const obj_reg = try self.generateExpression(access_data.target);
        const prop_reg = try self.generateExpression(access_data.prop_variable);
        const args = try self.allocator.alloc(Register, 2);
        args[0] = obj_reg;
        args[1] = prop_reg;
        return self.emitWithResult(.{ .call = .{
            .func_name = "php_object_get_dynamic",
            .args = args,
            .return_type = .php_value,
        } }, .php_value);
    }

    fn generateNamedArg(self: *Self, node: *const Node) !Register {
        return self.generateExpression(node.data.named_arg.value);
    }

    fn generateCastExpr(self: *Self, node: *const Node) !Register {
        const cast_data = node.data.cast_expr;
        const value_reg = try self.generateExpression(cast_data.expr);
        return switch (cast_data.cast_type) {
            .k_array => blk: {
                const args = try self.allocator.alloc(Register, 1);
                args[0] = value_reg;
                break :blk self.emitWithResult(.{ .call = .{
                    .func_name = "php_cast_array",
                    .args = args,
                    .return_type = .php_value,
                } }, .php_value);
            },
            .k_object => blk: {
                const args = try self.allocator.alloc(Register, 1);
                args[0] = value_reg;
                break :blk self.emitWithResult(.{ .call = .{
                    .func_name = "php_cast_object",
                    .args = args,
                    .return_type = .php_value,
                } }, .php_value);
            },
            else => value_reg,
        };
    }

    /// Generate IR for static property access
    fn generateStaticPropertyAccess(self: *Self, node: *const Node) !Register {
        const access_data = node.data.static_property_access;
        const class_name = self.getString(access_data.class_name);
        const prop_name = self.getString(access_data.property_name);

        // Static properties are accessed via runtime call
        var buf: [256]u8 = undefined;
        const full_name = std.fmt.bufPrint(&buf, "{s}::${s}", .{ class_name, prop_name }) catch prop_name;
        const name_copy = try self.allocator.dupe(u8, full_name);

        return self.emitWithResult(.{ .call = .{
            .func_name = name_copy,
            .args = try self.allocator.alloc(Register, 0),
            .return_type = .php_value,
        } }, .php_value);
    }

    /// Generate IR for class constant access
    fn generateClassConstantAccess(self: *Self, node: *const Node) !Register {
        const access_data = node.data.class_constant_access;
        const class_name = self.getString(access_data.class_name);
        const const_name = self.getString(access_data.constant_name);

        // Class constants are accessed via runtime call
        var buf: [256]u8 = undefined;
        const full_name = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_name, const_name }) catch const_name;
        const name_copy = try self.allocator.dupe(u8, full_name);

        return self.emitWithResult(.{ .call = .{
            .func_name = name_copy,
            .args = try self.allocator.alloc(Register, 0),
            .return_type = .php_value,
        } }, .php_value);
    }

    /// Generate IR for closure
    fn generateClosure(self: *Self, node: *const Node) !Register {
        const closure_data = node.data.closure;

        // 1. Capture variables from parent scope
        var captures = std.ArrayListUnmanaged(Register){};
        defer captures.deinit(self.allocator);

        for (closure_data.captures) |cap_idx| {
            const cap_node = self.getNode(cap_idx) orelse continue;
            // Assuming capture node is a variable
            var var_name: []const u8 = undefined;
            if (cap_node.tag == .variable) {
                var_name = self.getString(cap_node.data.variable.name);
            } else {
                continue;
            }
            
            // Get from parent scope
            var val_reg: Register = undefined;
            if (self.var_registers.get(var_name)) |ptr_reg| {
                val_reg = try self.emitWithResult(.{ .load = .{ .ptr = ptr_reg, .type_ = .php_value } }, .php_value);
            } else {
                val_reg = try self.emitWithResult(.{ .const_null = {} }, .php_value);
            }
            try captures.append(self.allocator, val_reg);
        }

        // Create anonymous function
        var buf: [64]u8 = undefined;
        const func_name = std.fmt.bufPrint(&buf, "__closure_{d}", .{self.block_counter}) catch "__closure";
        self.block_counter += 1;
        const name_copy = try self.allocator.dupe(u8, func_name);

        const func = try self.allocator.create(Function);
        func.* = Function.init(self.allocator, name_copy);
        func.location = self.current_location;

        if (self.module) |module| {
            try module.addFunction(func);
        }

        // Generate closure body in new context
        const prev_function = self.current_function;
        const prev_block = self.current_block;
        const prev_var_registers = self.var_registers;

        self.current_function = func;
        self.var_registers = .{};

        const entry = try func.createBlock("entry");
        self.setCurrentBlock(entry);

        // Process parameters
        for (closure_data.params) |param_idx| {
            try self.generateParameter(param_idx);
        }

        // Process captures (inject into local scope)
        for (closure_data.captures, 0..) |cap_idx, i| {
            const cap_node = self.getNode(cap_idx) orelse continue;
            var var_name: []const u8 = undefined;
            if (cap_node.tag == .variable) {
                var_name = self.getString(cap_node.data.variable.name);
            } else {
                continue;
            }

            // Generate capture_get
            const capture_val = try self.emitWithResult(.{ .capture_get = .{ .index = @intCast(i), .name = var_name } }, .php_value);
            
            // Create local variable and store
            const local_ptr = try self.getOrCreateVarRegister(var_name, .php_value);
            _ = try self.emit(.{ .store = .{ .ptr = local_ptr, .value = capture_val } }, null);
        }

        // Generate body
        try self.generateStatement(closure_data.body);

        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .ret = null });
        }

        self.var_registers.deinit(self.allocator);
        self.var_registers = prev_var_registers;
        self.current_function = prev_function;
        self.current_block = prev_block;

        // Return callable reference
        // Create array for captures
        const caps_arr_reg = try self.emitWithResult(.{ .array_new = .{ .capacity = @intCast(captures.items.len) } }, .php_array);
        
        for (captures.items) |cap_reg| {
             _ = try self.emit(.{ .array_push = .{ .array = caps_arr_reg, .value = cap_reg } }, null);
        }

        // Closure name
        const name_id = try self.module.?.internString(func_name);
        const name_reg = try self.emitWithResult(.{ .const_string = name_id }, .php_string);

        // Call php_create_closure
        const args = try self.allocator.alloc(Register, 2);
        args[0] = name_reg;
        args[1] = caps_arr_reg;
        
        return self.emitWithResult(.{ .call = .{
            .func_name = "php_create_closure",
            .args = args,
            .return_type = .php_callable,
        } }, .php_callable);
    }

    /// Generate IR for arrow function
    fn generateArrowFunction(self: *Self, node: *const Node) !Register {
        const arrow_data = node.data.arrow_function;

        // Arrow functions are similar to closures but with implicit return
        var buf: [64]u8 = undefined;
        const func_name = std.fmt.bufPrint(&buf, "__arrow_{d}", .{self.block_counter}) catch "__arrow";
        self.block_counter += 1;
        const name_copy = try self.allocator.dupe(u8, func_name);

        const func = try self.allocator.create(Function);
        func.* = Function.init(self.allocator, name_copy);
        func.location = self.current_location;

        if (self.module) |module| {
            try module.addFunction(func);
        }

        const prev_function = self.current_function;
        const prev_block = self.current_block;
        const prev_var_registers = self.var_registers;

        self.current_function = func;
        self.var_registers = .{};

        const entry = try func.createBlock("entry");
        self.setCurrentBlock(entry);

        for (arrow_data.params) |param_idx| {
            try self.generateParameter(param_idx);
        }

        // Arrow function body is an expression that's implicitly returned
        const result_reg = try self.generateExpression(arrow_data.body);
        self.setTerminator(.{ .ret = result_reg });

        self.var_registers.deinit(self.allocator);
        self.var_registers = prev_var_registers;
        self.current_function = prev_function;
        self.current_block = prev_block;

        return self.emitWithResult(.{ .call = .{
            .func_name = "php_create_closure",
            .args = try self.allocator.alloc(Register, 0),
            .return_type = .php_callable,
        } }, .php_callable);
    }

    /// Generate IR for match expression
    fn generateMatchExpr(self: *Self, node: *const Node) !Register {
        const match_data = node.data.match_expr;

        // Generate subject expression
        const subject_reg = try self.generateExpression(match_data.expression);

        // Create blocks for each arm and merge
        const merge_block = try self.createBlock("match_merge");
        var arm_blocks = std.ArrayListUnmanaged(*BasicBlock){};
        defer arm_blocks.deinit(self.allocator);

        for (match_data.arms) |_| {
            const arm_block = try self.createBlock("match_arm");
            try arm_blocks.append(self.allocator, arm_block);
        }

        // Generate arms
        var phi_incoming = std.ArrayListUnmanaged(Instruction.PhiIncoming){};
        defer phi_incoming.deinit(self.allocator);

        for (match_data.arms, 0..) |arm_idx, i| {
            const arm_node = self.getNode(arm_idx) orelse continue;
            if (arm_node.tag != .match_arm) continue;

            const arm_data = arm_node.data.match_arm;
            const arm_block = arm_blocks.items[i];
            const next_block = if (i + 1 < arm_blocks.items.len) arm_blocks.items[i + 1] else merge_block;

            // Check conditions
            if (arm_data.conditions.len > 0) {
                for (arm_data.conditions) |cond_idx| {
                    const cond_reg = try self.generateExpression(cond_idx);
                    const match_reg = try self.emitWithResult(.{ .identical = .{
                        .lhs = subject_reg,
                        .rhs = cond_reg,
                    } }, .bool);

                    self.setTerminator(.{ .cond_br = .{
                        .cond = match_reg,
                        .then_block = arm_block,
                        .else_block = next_block,
                    } });
                }
            } else {
                // Default arm
                self.setTerminator(.{ .br = arm_block });
            }

            // Generate arm body
            self.setCurrentBlock(arm_block);
            const result_reg = try self.generateExpression(arm_data.body);
            try phi_incoming.append(self.allocator, .{ .value = result_reg, .block = arm_block });
            self.setTerminator(.{ .br = merge_block });
        }

        // Merge with phi
        self.setCurrentBlock(merge_block);
        if (phi_incoming.items.len > 0) {
            const incoming = try self.allocator.dupe(Instruction.PhiIncoming, phi_incoming.items);
            return self.emitWithResult(.{ .phi = .{ .incoming = incoming } }, .php_value);
        }

        return self.emitWithResult(.const_null, .php_value);
    }

    /// Generate IR for clone with expression
    fn generateCloneWithExpr(self: *Self, node: *const Node) !Register {
        const clone_data = node.data.clone_with_expr;

        // Clone the object
        const obj_reg = try self.generateExpression(clone_data.object);
        const cloned_reg = try self.emitWithResult(.{ .clone = .{ .operand = obj_reg } }, .php_value);

        // Apply property modifications
        const props_node = self.getNode(clone_data.properties);
        if (props_node != null and props_node.?.tag == .array_init) {
            for (props_node.?.data.array_init.elements) |elem_idx| {
                const elem = self.getNode(elem_idx) orelse continue;
                if (elem.tag == .array_pair) {
                    const key_node = self.getNode(elem.data.array_pair.key);
                    if (key_node != null and key_node.?.tag == .literal_string) {
                        const prop_name = self.getString(key_node.?.data.literal_string.value);
                        const val_reg = try self.generateExpression(elem.data.array_pair.value);
                        _ = try self.emit(.{ .property_set = .{
                            .object = cloned_reg,
                            .property_name = prop_name,
                            .value = val_reg,
                        } }, null);
                    }
                }
            }
        }

        return cloned_reg;
    }

    // ========================================================================
    // Constant Folding
    // ========================================================================

    /// Try to constant fold an expression
    /// Returns the folded constant register if successful, null otherwise
    fn tryConstantFold(self: *Self, node: *const Node) !?Register {
        switch (node.tag) {
            .binary_expr => return self.tryFoldBinaryExpr(node),
            .unary_expr => return self.tryFoldUnaryExpr(node),
            else => return null,
        }
    }

    /// Try to fold a binary expression
    pub fn tryFoldBinaryExpr(self: *Self, node: *const Node) !?Register {
        const bin_data = node.data.binary_expr;

        // Get operand nodes
        const lhs_node = self.getNode(bin_data.lhs) orelse return null;
        const rhs_node = self.getNode(bin_data.rhs) orelse return null;

        // Check if both operands are constants
        const lhs_const = self.getConstantValue(lhs_node);
        const rhs_const = self.getConstantValue(rhs_node);

        if (lhs_const == null or rhs_const == null) return null;

        // Perform constant folding based on operator
        const op = bin_data.op;

        // Integer operations
        if (lhs_const.?.int_val != null and rhs_const.?.int_val != null) {
            const lhs_val = lhs_const.?.int_val.?;
            const rhs_val = rhs_const.?.int_val.?;

            const result: ?i64 = switch (op) {
                .plus => lhs_val +% rhs_val,
                .minus => lhs_val -% rhs_val,
                .asterisk => lhs_val *% rhs_val,
                .slash => if (rhs_val != 0) @divTrunc(lhs_val, rhs_val) else null,
                .percent => if (rhs_val != 0) @mod(lhs_val, rhs_val) else null,
                .ampersand => lhs_val & rhs_val,
                .pipe => lhs_val | rhs_val,
                .caret => lhs_val ^ rhs_val,
                .less_less => lhs_val << @intCast(@mod(rhs_val, 64)),
                .greater_greater => lhs_val >> @intCast(@mod(rhs_val, 64)),
            else => null,
            };

            if (result) |val| {
                const reg = try self.emitWithResult(.{ .const_int = val }, .i64);
                return reg;
            }

            // Boolean results
            const bool_result: ?bool = switch (op) {
                .equal_equal, .equal_equal_equal => lhs_val == rhs_val,
                .bang_equal, .bang_equal_equal => lhs_val != rhs_val,
                .less => lhs_val < rhs_val,
                .less_equal => lhs_val <= rhs_val,
                .greater => lhs_val > rhs_val,
                .greater_equal => lhs_val >= rhs_val,
                else => null,
            };

            if (bool_result) |val| {
                const reg = try self.emitWithResult(.{ .const_bool = val }, .bool);
                return reg;
            }
        }

        // Float operations
        if (lhs_const.?.float_val != null and rhs_const.?.float_val != null) {
            const lhs_val = lhs_const.?.float_val.?;
            const rhs_val = rhs_const.?.float_val.?;

            const result: ?f64 = switch (op) {
                .plus => lhs_val + rhs_val,
                .minus => lhs_val - rhs_val,
                .asterisk => lhs_val * rhs_val,
                .slash => if (rhs_val != 0) lhs_val / rhs_val else null,
                else => null,
            };

            if (result) |val| {
                const reg = try self.emitWithResult(.{ .const_float = val }, .f64);
                return reg;
            }

            // Boolean results
            const bool_result: ?bool = switch (op) {
                .equal_equal => lhs_val == rhs_val,
                .bang_equal => lhs_val != rhs_val,
                .less => lhs_val < rhs_val,
                .less_equal => lhs_val <= rhs_val,
                .greater => lhs_val > rhs_val,
                .greater_equal => lhs_val >= rhs_val,
                else => null,
            };

            if (bool_result) |val| {
                const reg = try self.emitWithResult(.{ .const_bool = val }, .bool);
                return reg;
            }
        }

        // Mixed int/float operations
        if ((lhs_const.?.int_val != null and rhs_const.?.float_val != null) or
            (lhs_const.?.float_val != null and rhs_const.?.int_val != null))
        {
            const lhs_val: f64 = if (lhs_const.?.float_val) |f| f else @floatFromInt(lhs_const.?.int_val.?);
            const rhs_val: f64 = if (rhs_const.?.float_val) |f| f else @floatFromInt(rhs_const.?.int_val.?);

            const result: ?f64 = switch (op) {
                .plus => lhs_val + rhs_val,
                .minus => lhs_val - rhs_val,
                .asterisk => lhs_val * rhs_val,
                .slash => if (rhs_val != 0) lhs_val / rhs_val else null,
                else => null,
            };

            if (result) |val| {
                const reg = try self.emitWithResult(.{ .const_float = val }, .f64);
                return reg;
            }
        }

        // Boolean operations
        if (lhs_const.?.bool_val != null and rhs_const.?.bool_val != null) {
            const lhs_val = lhs_const.?.bool_val.?;
            const rhs_val = rhs_const.?.bool_val.?;

            const result: ?bool = switch (op) {
                .k_and, .double_ampersand => lhs_val and rhs_val,
                .k_or, .double_pipe => lhs_val or rhs_val,
                .equal_equal, .equal_equal_equal => lhs_val == rhs_val,
                .bang_equal, .bang_equal_equal => lhs_val != rhs_val,
                else => null,
            };

            if (result) |val| {
                const reg = try self.emitWithResult(.{ .const_bool = val }, .bool);
                return reg;
            }
        }

        // String concatenation
        if (lhs_const.?.string_val != null and rhs_const.?.string_val != null and op == .dot) {
            // String concatenation at compile time
            const lhs_str = lhs_const.?.string_val.?;
            const rhs_str = rhs_const.?.string_val.?;
            const concat_str = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ lhs_str, rhs_str });
            defer self.allocator.free(concat_str);

            if (self.module) |module| {
                const str_id = try module.internString(concat_str);
                const reg = try self.emitWithResult(.{ .const_string = str_id }, .php_string);
                return reg;
            }
        }

        return null;
    }

    /// Try to fold a unary expression
    pub fn tryFoldUnaryExpr(self: *Self, node: *const Node) !?Register {
        const unary_data = node.data.unary_expr;

        const operand_node = self.getNode(unary_data.expr) orelse return null;
        const operand_const = self.getConstantValue(operand_node) orelse return null;

        switch (unary_data.op) {
            .minus => {
                if (operand_const.int_val) |val| {
                    const reg = try self.emitWithResult(.{ .const_int = -val }, .i64);
                    return reg;
                }
                if (operand_const.float_val) |val| {
                    const reg = try self.emitWithResult(.{ .const_float = -val }, .f64);
                    return reg;
                }
            },
            .bang => {
                if (operand_const.bool_val) |val| {
                    const reg = try self.emitWithResult(.{ .const_bool = !val }, .bool);
                    return reg;
                }
            },
            .tilde => {
                if (operand_const.int_val) |val| {
                    const reg = try self.emitWithResult(.{ .const_int = ~val }, .i64);
                    return reg;
                }
            },
            .plus => {
                // Unary plus - return the same constant
                if (operand_const.int_val) |val| {
                    const reg = try self.emitWithResult(.{ .const_int = val }, .i64);
                    return reg;
                }
                if (operand_const.float_val) |val| {
                    const reg = try self.emitWithResult(.{ .const_float = val }, .f64);
                    return reg;
                }
            },
            else => {},
        }

        return null;
    }

    /// Constant value representation for folding
    const ConstantValue = struct {
        int_val: ?i64 = null,
        float_val: ?f64 = null,
        bool_val: ?bool = null,
        string_val: ?[]const u8 = null,
        is_null: bool = false,
    };

    /// Extract constant value from a node
    fn getConstantValue(self: *const Self, node: *const Node) ?ConstantValue {
        return switch (node.tag) {
            .literal_int => .{ .int_val = node.data.literal_int.value },
            .literal_float => .{ .float_val = node.data.literal_float.value },
            .literal_bool => .{ .bool_val = node.main_token.tag == .k_true },
            .literal_null => .{ .is_null = true },
            .literal_string => .{ .string_val = self.getString(node.data.literal_string.value) },
            else => null,
        };
    }

    // ========================================================================
    // Helper Functions
    // ========================================================================

    /// Convert IR Type to ConcreteType
    fn irTypeToConcreteType(ir_type: Type) ConcreteType {
        return switch (ir_type) {
            .void => .void,
            .bool => .bool,
            .i64 => .int,
            .f64 => .float,
            .php_string => .string,
            .php_array => .array,
            .php_object => .object,
            .php_callable => .callable,
            .php_resource => .resource,
            else => .object,
        };
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "IRGenerator initialization" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var type_inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var generator = IRGenerator.init(allocator, &symbol_table, &type_inferencer, &diagnostics);
    defer generator.deinit();

    try std.testing.expect(generator.module == null);
    try std.testing.expect(generator.current_function == null);
    try std.testing.expect(generator.current_block == null);
}

test "IRGenerator simple module generation" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var type_inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var generator = IRGenerator.init(allocator, &symbol_table, &type_inferencer, &diagnostics);
    defer generator.deinit();

    // Create a simple AST with just a root node
    const nodes = [_]Node{
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .root = .{ .stmts = &.{} } },
        },
    };

    const string_table = [_][]const u8{};

    const module = try generator.generate(&nodes, &string_table, "test_module", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }

    try std.testing.expectEqualStrings("test_module", module.name);
    try std.testing.expectEqualStrings("test.php", module.source_file);
}

test "IRGenerator constant folding - integer addition" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var type_inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var generator = IRGenerator.init(allocator, &symbol_table, &type_inferencer, &diagnostics);
    defer generator.deinit();

    // Create module for emitting instructions
    const module = try allocator.create(Module);
    module.* = Module.init(allocator, "test", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }
    generator.module = module;

    // Create a dummy function and block for emitting instructions
    const func = try allocator.create(Function);
    func.* = Function.init(allocator, "test_func");
    defer {
        func.deinit();
        allocator.destroy(func);
    }
    generator.current_function = func;

    const block = try func.createBlock("entry");
    generator.current_block = block;

    // Create AST for: 2 + 3
    const nodes = [_]Node{
        // 0: root
        .{
            .tag = .root,
            .main_token = .{ .tag = .eof, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .root = .{ .stmts = &[_]Node.Index{1} } },
        },
        // 1: binary_expr (2 + 3)
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .plus, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .binary_expr = .{ .lhs = 2, .op = .plus, .rhs = 3 } },
        },
        // 2: literal_int (2)
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .t_lnumber, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .literal_int = .{ .value = 2 } },
        },
        // 3: literal_int (3)
        .{
            .tag = .literal_int,
            .main_token = .{ .tag = .t_lnumber, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .literal_int = .{ .value = 3 } },
        },
    };

    const string_table = [_][]const u8{};

    // Set up generator with nodes
    generator.nodes = &nodes;
    generator.string_table = &string_table;

    // Test constant folding
    const folded = try generator.tryFoldBinaryExpr(&nodes[1]);
    try std.testing.expect(folded != null);
}

test "IRGenerator constant folding - string concatenation" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var type_inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var generator = IRGenerator.init(allocator, &symbol_table, &type_inferencer, &diagnostics);
    defer generator.deinit();

    // Create module for string interning
    const module = try allocator.create(Module);
    module.* = Module.init(allocator, "test", "test.php");
    defer {
        module.deinit();
        allocator.destroy(module);
    }
    generator.module = module;

    // Create a dummy function and block for emitting instructions
    const func = try allocator.create(Function);
    func.* = Function.init(allocator, "test_func");
    defer {
        func.deinit();
        allocator.destroy(func);
    }
    generator.current_function = func;

    const block = try func.createBlock("entry");
    generator.current_block = block;

    // Create AST for: "hello" . " world"
    const string_table = [_][]const u8{ "hello", " world" };

    const nodes = [_]Node{
        // 0: binary_expr ("hello" . " world")
        .{
            .tag = .binary_expr,
            .main_token = .{ .tag = .dot, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .binary_expr = .{ .lhs = 1, .op = .dot, .rhs = 2 } },
        },
        // 1: literal_string ("hello")
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .t_string, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .literal_string = .{ .value = 0, .quote_type = .double } },
        },
        // 2: literal_string (" world")
        .{
            .tag = .literal_string,
            .main_token = .{ .tag = .t_string, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .literal_string = .{ .value = 1, .quote_type = .double } },
        },
    };

    generator.nodes = &nodes;
    generator.string_table = &string_table;

    // Test constant folding
    const folded = try generator.tryFoldBinaryExpr(&nodes[0]);
    try std.testing.expect(folded != null);
}

test "IRGenerator getConstantValue" {
    const allocator = std.testing.allocator;

    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var type_inferencer = TypeInferencer.init(allocator, &symbol_table, &diagnostics);

    var generator = IRGenerator.init(allocator, &symbol_table, &type_inferencer, &diagnostics);
    defer generator.deinit();

    const string_table = [_][]const u8{"test"};
    generator.string_table = &string_table;

    // Test integer constant
    const int_node = Node{
        .tag = .literal_int,
        .main_token = .{ .tag = .t_lnumber, .loc = .{ .start = 0, .end = 0 } },
        .data = .{ .literal_int = .{ .value = 42 } },
    };
    const int_const = generator.getConstantValue(&int_node);
    try std.testing.expect(int_const != null);
    try std.testing.expectEqual(@as(i64, 42), int_const.?.int_val.?);

    // Test float constant
    const float_node = Node{
        .tag = .literal_float,
        .main_token = .{ .tag = .t_dnumber, .loc = .{ .start = 0, .end = 0 } },
        .data = .{ .literal_float = .{ .value = 3.14 } },
    };
    const float_const = generator.getConstantValue(&float_node);
    try std.testing.expect(float_const != null);
    try std.testing.expectEqual(@as(f64, 3.14), float_const.?.float_val.?);

    // Test null constant
    const null_node = Node{
        .tag = .literal_null,
        .main_token = .{ .tag = .k_null, .loc = .{ .start = 0, .end = 0 } },
        .data = .{ .none = {} },
    };
    const null_const = generator.getConstantValue(&null_node);
    try std.testing.expect(null_const != null);
    try std.testing.expect(null_const.?.is_null);
}
