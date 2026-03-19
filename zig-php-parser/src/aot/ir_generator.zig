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

/// ArrayList辅助结构
const VarRegisterEntry = struct {
    name: []const u8,
    register: Register,
};

const VarUsageEntry = struct {
    name: []const u8,
    is_used: bool,
    location: SourceLocation,
};

/// IR Generator - converts AST to SSA-form IR
pub const IRGenerator = struct {
    allocator: Allocator,
    /// Current IR module being generated
    module: ?*Module,
    /// Current function being generated
    current_function: ?*Function,
    /// Current class being generated (for resolving self/static/parent)
    current_class: ?[]const u8,
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
    /// Source code buffer for token text lookup
    source_buffer: ?[]const u8,
    /// Current source location
    current_location: SourceLocation,
    /// Variable to register mapping for current function
    var_registers: std.ArrayListUnmanaged(VarRegisterEntry),
    /// Track by-reference variables (foreach &$v)
    ref_vars: std.ArrayListUnmanaged([]const u8),
    /// Track variable usage for unused variable detection
    var_usage: std.ArrayListUnmanaged(VarUsageEntry),
    entry_allocas: std.ArrayListUnmanaged(*Instruction),
    /// Block counter for unique labels
    block_counter: u32,
    /// Loop context stack for break/continue
    loop_stack: std.ArrayListUnmanaged(LoopContext),
    /// Try-catch context stack
    try_stack: std.ArrayListUnmanaged(TryContext),
    /// 常量缓存：class_name::const_name -> ConstantValue
    constant_cache: std.StringHashMapUnmanaged(TypeDef.ConstantValue),
    /// 全局变量集合（在函数中通过 global 声明的变量）
    global_vars: std.StringHashMapUnmanaged(void),
    /// 静态变量集合（在函数中通过 static 声明的变量）
    static_vars: std.StringHashMapUnmanaged(void),
    /// 当前函数是否有 this 参数（用于方法）
    current_has_this_param: bool = false,
    /// 引用参数集合（参数名 -> void）
    reference_params: std.StringHashMapUnmanaged(void),

    // ✅ 命名空间支持
    /// 当前命名空间（如 "App\\Utils"）
    current_namespace: ?[]const u8 = null,
    /// 命名空间别名表：别名 -> 完整类名（use App\Service as S）
    namespace_aliases: std.StringHashMapUnmanaged([]const u8),
    /// 命名空间导入表：短名 -> 完整类名（use App\Service）
    namespace_imports: std.StringHashMapUnmanaged([]const u8),
    /// Trait 方法映射：trait_name::method_name -> 方法实现
    trait_methods: std.StringHashMapUnmanaged(*Function),

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
            .current_class = null,
            .current_block = null,
            .symbol_table = symbol_table,
            .type_inferencer = type_inferencer,
            .diagnostics = diagnostics,
            .nodes = null,
            .string_table = null,
            .source_buffer = null,
            .current_location = .{},
            .var_registers = .{},
            .ref_vars = .{},
            .var_usage = .{},
            .entry_allocas = .{},
            .block_counter = 0,
            .loop_stack = .{},
            .try_stack = .{},
            .constant_cache = .{},
            .global_vars = .{},
            .static_vars = .{},
            .reference_params = .{},
            .namespace_aliases = .{},
            .namespace_imports = .{},
            .trait_methods = .{},
        };
    }

    /// Deinitialize and free resources
    // ArrayList辅助函数
    fn getVarRegister(self: *Self, name: []const u8) ?Register {
        for (self.var_registers.items) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.register;
        }
        return null;
    }

    fn putVarRegister(self: *Self, name: []const u8, reg: Register) !void {
        // 检查是否已存在，更新
        for (self.var_registers.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                entry.register = reg;
                return;
            }
        }
        // 不存在，添加
        try self.var_registers.append(self.allocator, .{ .name = name, .register = reg });
    }

    fn removeVarRegister(self: *Self, name: []const u8) void {
        for (self.var_registers.items, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name)) {
                _ = self.var_registers.swapRemove(i);
                return;
            }
        }
    }

    fn isRefVar(self: *Self, name: []const u8) bool {
        for (self.ref_vars.items) |ref_name| {
            if (std.mem.eql(u8, ref_name, name)) return true;
        }
        return false;
    }

    fn putRefVar(self: *Self, name: []const u8) !void {
        if (!self.isRefVar(name)) {
            try self.ref_vars.append(self.allocator, name);
        }
    }

    fn getVarUsage(self: *Self, name: []const u8) ?*VarUsageEntry {
        for (self.var_usage.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }

    fn putVarUsage(self: *Self, name: []const u8, is_used: bool, location: SourceLocation) !void {
        if (self.getVarUsage(name)) |entry| {
            entry.is_used = is_used;
            entry.location = location;
        } else {
            try self.var_usage.append(self.allocator, .{ .name = name, .is_used = is_used, .location = location });
        }
    }

    pub fn deinit(self: *Self) void {
        self.var_registers.deinit(self.allocator);
        self.ref_vars.deinit(self.allocator);
        self.var_usage.deinit(self.allocator);
        self.entry_allocas.deinit(self.allocator);
        self.loop_stack.deinit(self.allocator);
        self.try_stack.deinit(self.allocator);
        self.reference_params.deinit(self.allocator);

        // 释放constant_cache的key
        var it = self.constant_cache.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.constant_cache.deinit(self.allocator);

        self.global_vars.deinit(self.allocator);
    }

    fn flushEntryAllocas(self: *Self, entry_block: *BasicBlock) !void {
        if (self.entry_allocas.items.len == 0) return;

        var new_insts: std.ArrayListUnmanaged(*Instruction) = .{};
        try new_insts.appendSlice(self.allocator, self.entry_allocas.items);
        try new_insts.appendSlice(self.allocator, entry_block.instructions.items);

        entry_block.instructions.deinit(self.allocator);
        entry_block.instructions = new_insts;

        self.entry_allocas.clearRetainingCapacity();
    }

    /// Generate IR module from AST (assumes root node at index 0)
    pub fn generate(
        self: *Self,
        nodes: []const Node,
        string_table: []const []const u8,
        source_buffer: []const u8,
        module_name: []const u8,
        source_file: []const u8,
    ) !*Module {
        return self.generateFromRoot(nodes, string_table, source_buffer, 0, module_name, source_file);
    }

    /// Generate IR module from AST with explicit root node index
    pub fn generateFromRoot(
        self: *Self,
        nodes: []const Node,
        string_table: []const []const u8,
        source_buffer: []const u8,
        root_index: u32,
        module_name: []const u8,
        source_file: []const u8,
    ) !*Module {
        self.nodes = nodes;
        self.string_table = string_table;
        self.source_buffer = source_buffer;

        // 预注册超全局变量，避免undefined warning
        const superglobal_names = [_][]const u8{ "$_GET", "$_POST", "$_REQUEST", "$_COOKIE", "$_SESSION", "$_SERVER", "$_ENV", "$_FILES", "$GLOBALS" };
        for (superglobal_names) |name| {
            try self.global_vars.put(self.allocator, name, {});
        }

        // Create module
        const module = try self.allocator.create(Module);
        module.* = Module.init(self.allocator, module_name, source_file);
        self.module = module;

        // Copy string table from Parser to Module
        // This ensures that StringId from AST nodes matches StringId in IR Module
        // 必须 dupe，因为 Module.deinit 会释放 string_table 条目，
        // 而原始 string_table 由 compiler.deinit 单独释放
        for (string_table) |str| {
            const duped = try self.allocator.dupe(u8, str);
            try module.string_table.append(self.allocator, duped);
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
                    stmt_node.tag == .interface_decl or stmt_node.tag == .trait_decl or
                    stmt_node.tag == .enum_decl or
                    stmt_node.tag == .namespace_stmt or stmt_node.tag == .use_stmt)
                {
                    // Process declarations and namespace/use statements directly
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

        const prev_function = self.current_function;
        const prev_block = self.current_block;
        const prev_var_registers = self.var_registers;
        const prev_var_usage = self.var_usage;
        const prev_entry_allocas = self.entry_allocas;

        self.current_function = func;
        self.current_block = null;
        self.var_registers = .{};
        self.var_usage = .{};
        self.entry_allocas = .{};
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

        try self.flushEntryAllocas(entry);
        try self.checkUnusedVariables();

        self.var_registers.deinit(self.allocator);
        self.var_usage.deinit(self.allocator);
        self.entry_allocas.deinit(self.allocator);
        self.var_registers = prev_var_registers;
        self.var_usage = prev_var_usage;
        self.entry_allocas = prev_entry_allocas;
        self.current_function = prev_function;
        self.current_block = prev_block;
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
        const block = self.current_block orelse {
            std.debug.print("\n=== NoCurrentBlock Error ===\n", .{});
            std.debug.print("Operation: {s}\n", .{@tagName(op)});
            std.debug.print("Current function: {s}\n", .{if (self.current_function) |f| f.name else "none"});
            std.debug.print("Last location: {any}\n", .{self.current_location});
            return error.NoCurrentBlock;
        };

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
        if (self.getVarRegister(name)) |reg| {
            return reg;
        }

        // Allocate stack space for the variable
        // 统一使用 php_value 类型，避免类型不匹配
        _ = type_; // 忽略传入的类型
        const alloca_type = Type{ .php_value = {} };

        // 必须在堆上分配Type，因为指针需要在函数返回后仍然有效
        const type_ptr = try self.allocator.create(Type);
        type_ptr.* = alloca_type;
        const ptr_type = Type{ .ptr = type_ptr };

        // Always create alloca in the entry block to ensure dominance
        const func = self.current_function orelse return error.NoCurrentFunction;

        const result = func.newRegister(ptr_type);
        const inst = try self.allocator.create(Instruction);
        inst.* = .{
            .result = result,
            .op = .{ .alloca = .{ .type_ = alloca_type, .count = 1, .var_name = name } },
            .location = self.current_location,
        };

        // Prepend to entry block to ensure it's before any potential use
        try self.entry_allocas.append(self.allocator, inst);

        // 记录变量名到 Function（在优化后仍可用）
        try func.var_names.put(func.allocator, result.id, name);

        try self.putVarRegister(name, result);
        // Mark variable as defined but not used yet, store definition location
        try self.putVarUsage(name, false, self.current_location);
        return result;
    }

    /// Generate IR for variable access
    fn generateVariable(self: *Self, node: *const Node) !Register {
        const var_name = self.getString(node.data.variable.name);

        // Mark variable as used
        if (self.getVarUsage(var_name)) |usage_info| {
            try self.putVarUsage(var_name, true, usage_info.location);
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

        // 检查是否是全局变量（通过 global 声明的）
        const is_global = self.global_vars.contains(var_name);

        if (is_global) {
            // 从全局表读取
            return self.emitWithResult(.{ .global_get = .{ .name = var_name } }, .php_value);
        }

        // 如果变量不在局部作用域，尝试从全局表读取
        // 这处理了在 __main__ 中直接使用未声明变量的情况
        return self.emitWithResult(.{ .global_get = .{ .name = var_name } }, .php_value);
    }

    /// Look up a variable's register
    fn lookupVarRegister(self: *Self, name: []const u8) ?Register {
        return self.getVarRegister(name);
    }

    fn generateVariableVariable(self: *Self, node: *const Node) !Register {
        // $$var: 先求值内层变量得到变量名，再查找该变量
        const inner_expr = node.data.variable_variable.expr;

        // 求值内层表达式得到变量名
        const name_reg = try self.generateExpression(inner_expr);

        // 调用运行时函数获取动态变量
        // 使用 global_get_dynamic 指令，传入变量名寄存器
        return self.emitWithResult(.{ .global_get_dynamic = .{ .name_reg = name_reg } }, .php_value);
    }

    /// Check for unused variables and report errors
    fn checkUnusedVariables(self: *Self) !void {
        for (self.var_usage.items) |entry| {
            if (!entry.is_used) {
                // 根据当前模式确定变量前缀
                const var_prefix = if (self.isGoMode()) "" else "$";

                // PHP 解释执行通常不会因为未使用变量而报错；这里降级为 warning 以便 AOT 与解释器行为更一致
                self.diagnostics.report(
                    .warning,
                    entry.location,
                    "未使用的变量: {s}{s}",
                    .{ var_prefix, entry.name },
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
            .enum_decl => try self.generateEnumDecl(node),
            .if_stmt => try self.generateIfStmt(node),
            .while_stmt => try self.generateWhileStmt(node),
            .do_while_stmt => try self.generateDoWhileStmt(node),
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
            // ✅ 处理 namespace 和 use 语句
            .namespace_stmt => try self.generateNamespaceStatement(node),
            .use_stmt => try self.generateUseStatement(node),
            .expression_stmt => {
                // Expression statement - just evaluate the expression
                _ = try self.generateExpression(index);
            },
            .assignment => { _ = try self.generateAssignment(node); },
            .compound_assignment => try self.generateCompoundAssignment(node),
            .list_assignment => try self.generateListAssignment(node),
            .list_empty => {},
            .block => try self.generateBlock(node),
            .const_decl => try self.generateConstDecl(node),
            .global_stmt => try self.generateGlobalStmt(node),
            .static_stmt => try self.generateStaticStmt(node),
            .expr_list => {
                // 表达式列表作为语句：顺序执行所有表达式
                const exprs = node.data.expr_list.exprs;
                for (exprs) |expr_idx| {
                    _ = try self.generateExpression(expr_idx);
                }
            },
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
        const runtime_decl = self.current_function != null;

        const params_info = try self.allocator.alloc(SymbolTableMod.Symbol.ParameterInfo, func_data.params.len);
        for (func_data.params, 0..) |param_idx, i| {
            params_info[i] = .{
                .name = "",
                .type_ = .dynamic,
                .has_default = false,
                .is_reference = false,
            };
            if (self.getNode(param_idx)) |pnode| {
                if (pnode.tag == .parameter) {
                    const pdata = pnode.data.parameter;
                    params_info[i] = .{
                        .name = self.getString(pdata.name),
                        .type_ = .dynamic,
                        .has_default = pdata.default_value != null,
                        .is_reference = pdata.is_reference,
                    };
                }
            }
        }
        try self.symbol_table.defineFunction(func_name, params_info, .dynamic, self.current_location);

        // Create function
        const func = try self.allocator.create(Function);
        func.* = Function.init(self.allocator, func_name);
        func.is_exported = true;
        func.register_at_startup = !runtime_decl;
        func.location = self.current_location;

        // Add to module
        if (self.module) |module| {
            try module.addFunction(func);
        }

        // Save previous context
        const prev_function = self.current_function;
        const prev_block = self.current_block;
        const prev_var_registers = self.var_registers;
        const prev_entry_allocas = self.entry_allocas;

        // Set up new context
        self.current_function = func;
        self.var_registers = .{};
        self.var_usage = .{}; // 初始化变量使用跟踪
        self.entry_allocas = .{};
        self.block_counter = 0;
        self.static_vars.clearRetainingCapacity(); // 清空静态变量集合

        // Create entry block
        const entry = try func.createBlock("entry");
        self.setCurrentBlock(entry);

        // Process parameters with unified control flow
        try self.generateParameters(func_data.params);

        // Generate function body
        try self.generateStatement(func_data.body);

        // Add implicit return if not terminated
        if (!self.isBlockTerminated()) {
            // 在隐式返回前同步静态变量
            try self.syncStaticVars();
            self.setTerminator(.{ .ret = null });
        }

        try self.flushEntryAllocas(entry);

        // Check for unused variables
        try self.checkUnusedVariables();

        // 将全局变量列表添加到函数
        var global_it = self.global_vars.keyIterator();
        while (global_it.next()) |var_name| {
            try func.global_vars.append(self.allocator, var_name.*);
        }
        // 清空全局变量集合，为下一个函数准备
        self.global_vars.clearRetainingCapacity();

        // Restore previous context
        self.var_registers.deinit(self.allocator);
        self.var_usage.deinit(self.allocator);
        self.entry_allocas.deinit(self.allocator);
        self.var_registers = prev_var_registers;
        self.var_usage = .{};
        self.entry_allocas = prev_entry_allocas;
        self.current_function = prev_function;
        self.current_block = prev_block;

        if (runtime_decl) {
            const declare_name = try std.fmt.allocPrint(self.allocator, "__declare_function__::{s}", .{func_name});
            const empty_args = try self.allocator.alloc(Register, 0);
            _ = try self.emit(.{ .call = .{
                .func_name = declare_name,
                .args = empty_args,
                .return_type = .void,
            } }, null);
        }
    }

    const ParamInfo = struct {
        name: []const u8,
        type_: Type,
        alloca_reg: Register,
        has_default: bool,
        default_expr: ?Node.Index,
    };

    /// Generate IR for all function parameters with unified control flow
    fn generateParameters(self: *Self, param_indices: []const Node.Index) !void {
        if (param_indices.len == 0) return;

        const func = self.current_function.?;

        // 收集参数信息
        var params = try std.ArrayList(ParamInfo).initCapacity(self.allocator, param_indices.len);
        defer params.deinit(self.allocator);

        for (param_indices) |param_idx| {
            const node = self.getNode(param_idx) orelse continue;
            if (node.tag != .parameter) continue;

            const param_data = node.data.parameter;
            const param_name = self.getString(param_data.name);

            var param_type: Type = .php_value;
            if (param_data.type) |type_idx| {
                param_type = try self.resolveTypeNode(type_idx);
            }
            if (param_data.is_variadic) {
                param_type = .php_value;
            }

            const param_index: u32 = @intCast(func.params.items.len);

            try func.addParam(.{
                .name = param_name,
                .type_ = param_type,
                .has_default = param_data.default_value != null,
                .is_variadic = param_data.is_variadic,
                .is_reference = param_data.is_reference,
            });

            // 记录引用参数索引
            if (param_data.is_reference) {
                try func.ref_params.append(self.allocator, param_index);
                try self.reference_params.put(self.allocator, param_name, {});
            }

            // 为引用参数创建no_optimize alloca
            const alloca_reg = if (param_data.is_reference) blk: {
                const alloca_type = param_type;
                const type_ptr = try self.allocator.create(Type);
                type_ptr.* = alloca_type;
                const ptr_type = Type{ .ptr = type_ptr };
                const reg = func.newRegister(ptr_type);

                const alloca_inst = try self.allocator.create(Instruction);
                alloca_inst.* = .{
                    .result = reg,
                    .op = .{
                        .alloca = .{
                            .type_ = alloca_type,
                            .count = 1,
                            .no_optimize = true, // 防止mem2reg优化
                        },
                    },
                    .location = self.current_location,
                };
                try self.entry_allocas.append(self.allocator, alloca_inst);
                try self.putVarRegister(param_name, reg);
                break :blk reg;
            } else try self.getOrCreateVarRegister(param_name, param_type);

            try params.append(self.allocator, .{
                .name = param_name,
                .type_ = param_type,
                .alloca_reg = alloca_reg,
                .has_default = param_data.default_value != null,
                .default_expr = param_data.default_value,
            });
        }

        // 检查是否有默认参数
        var has_defaults = false;
        for (params.items) |p| {
            if (p.has_default) {
                has_defaults = true;
                break;
            }
        }

        if (!has_defaults) {
            // 简单情况：无默认参数
            // 如果有 this 参数，其他参数索引从 1 开始
            const param_offset: usize = if (self.current_has_this_param) 1 else 0;
            for (params.items, 0..) |p, i| {
                const param_index = i + param_offset;
                // 检查是否是引用参数
                const param_node = self.getNode(param_indices[i]) orelse continue;
                const is_ref = param_node.tag == .parameter and param_node.data.parameter.is_reference;
                // 引用参数：param返回指针类型
                const param_type = if (is_ref) blk: {
                    const base_type = try self.allocator.create(Type);
                    base_type.* = p.type_;
                    break :blk Type{ .ptr = base_type };
                } else p.type_;
                const param_reg = try self.emitWithResult(.{ .param = .{ .index = @intCast(param_index), .name = p.name } }, param_type);
                _ = try self.emit(.{ .store = .{ .ptr = p.alloca_reg, .value = param_reg } }, null);
            }
            return;
        }

        // 复杂情况：有默认参数，需要统一控制流
        // 为每个参数创建 present/missing 值
        var present_regs = try std.ArrayList(Register).initCapacity(self.allocator, params.items.len);
        defer present_regs.deinit(self.allocator);
        var missing_regs = try std.ArrayList(Register).initCapacity(self.allocator, params.items.len);
        defer missing_regs.deinit(self.allocator);

        // 创建块
        const all_present_block = try func.createBlock("params_all_present");
        const has_missing_block = try func.createBlock("params_has_missing");
        const merge_block = try func.createBlock("params_merge");

        // 如果有 this 参数，其他参数索引从 1 开始
        const param_offset: usize = if (self.current_has_this_param) 1 else 0;

        // 检查是否所有参数都提供
        var all_present_cond: ?Register = null;
        for (params.items, 0..) |p, i| {
            if (!p.has_default) continue;

            const param_index = i + param_offset;
            const has_arg = try self.emitWithResult(.{ .has_arg = .{ .index = @intCast(param_index) } }, .bool);
            if (all_present_cond) |prev| {
                all_present_cond = try self.emitWithResult(.{ .and_ = .{ .lhs = prev, .rhs = has_arg } }, .bool);
            } else {
                all_present_cond = has_arg;
            }
        }

        if (all_present_cond) |cond| {
            self.current_block.?.setTerminator(.{ .cond_br = .{ .cond = cond, .then_block = all_present_block, .else_block = has_missing_block } });
        } else {
            self.current_block.?.setTerminator(.{ .br = all_present_block });
        }

        // all_present 块：所有参数都从 args 读取
        self.setCurrentBlock(all_present_block);
        for (params.items, 0..) |p, i| {
            const param_index = i + param_offset;
            // 检查是否是引用参数
            const param_node = self.getNode(param_indices[i]) orelse continue;
            const is_ref = param_node.tag == .parameter and param_node.data.parameter.is_reference;
            // 引用参数：param返回指针类型
            const param_type = if (is_ref) blk: {
                const base_type = try self.allocator.create(Type);
                base_type.* = p.type_;
                break :blk Type{ .ptr = base_type };
            } else p.type_;
            const param_reg = try self.emitWithResult(.{ .param = .{ .index = @intCast(param_index), .name = p.name } }, param_type);
            try present_regs.append(self.allocator, param_reg);
        }
        self.current_block.?.setTerminator(.{ .br = merge_block });

        // has_missing 块：使用默认值
        self.setCurrentBlock(has_missing_block);
        for (params.items, 0..) |p, i| {
            const param_index = i + param_offset;
            // 检查是否是引用参数
            const param_node = self.getNode(param_indices[i]) orelse continue;
            const is_ref = param_node.tag == .parameter and param_node.data.parameter.is_reference;
            
            if (p.default_expr) |default_idx| {
                // 有默认值：检查是否提供
                const has_arg = try self.emitWithResult(.{ .has_arg = .{ .index = @intCast(param_index) } }, .bool);
                
                if (is_ref) {
                    // 引用参数：param返回指针，默认值需要创建临时alloca
                    const param_type = blk: {
                        const base_type = try self.allocator.create(Type);
                        base_type.* = p.type_;
                        break :blk Type{ .ptr = base_type };
                    };
                    const param_reg = try self.emitWithResult(.{ .param = .{ .index = @intCast(param_index), .name = p.name } }, param_type);
                    
                    // 创建临时alloca存储默认值
                    const default_reg = try self.generateExpression(default_idx);
                    const temp_ptr_type = try self.allocator.create(Type);
                    temp_ptr_type.* = p.type_;
                    const temp_alloca = try self.emitWithResult(.{ .alloca = .{ .type_ = p.type_, .count = 1, .no_optimize = true } }, Type{ .ptr = temp_ptr_type });
                    _ = try self.emit(.{ .store = .{ .ptr = temp_alloca, .value = default_reg } }, null);
                    
                    // select在指针之间选择
                    const selected = try self.emitWithResult(.{ .select = .{ .cond = has_arg, .then_value = param_reg, .else_value = temp_alloca } }, param_type);
                    try missing_regs.append(self.allocator, selected);
                } else {
                    // 普通参数
                    const param_reg = try self.emitWithResult(.{ .param = .{ .index = @intCast(param_index), .name = p.name } }, p.type_);
                    const default_reg = try self.generateExpression(default_idx);
                    const selected = try self.emitWithResult(.{ .select = .{ .cond = has_arg, .then_value = param_reg, .else_value = default_reg } }, p.type_);
                    try missing_regs.append(self.allocator, selected);
                }
            } else {
                // 无默认值：直接读取
                const param_type = if (is_ref) blk: {
                    const base_type = try self.allocator.create(Type);
                    base_type.* = p.type_;
                    break :blk Type{ .ptr = base_type };
                } else p.type_;
                const param_reg = try self.emitWithResult(.{ .param = .{ .index = @intCast(param_index), .name = p.name } }, param_type);
                try missing_regs.append(self.allocator, param_reg);
            }
        }
        self.current_block.?.setTerminator(.{ .br = merge_block });

        // merge 块：使用 phi 合并
        self.setCurrentBlock(merge_block);
        for (params.items, 0..) |p, i| {
            const incoming = try self.allocator.alloc(Instruction.PhiIncoming, 2);
            incoming[0] = .{ .value = present_regs.items[i], .block = all_present_block };
            incoming[1] = .{ .value = missing_regs.items[i], .block = has_missing_block };
            // phi的类型应该与incoming值的类型一致
            const phi_type = present_regs.items[i].type_;
            const phi_reg = try self.emitWithResult(.{ .phi = .{ .incoming = incoming } }, phi_type);
            _ = try self.emit(.{ .store = .{ .ptr = p.alloca_reg, .value = phi_reg } }, null);
        }
    }

    /// Resolve a type node to IR Type
    fn resolveTypeNode(self: *Self, index: Node.Index) !Type {
        const node = self.getNode(index) orelse return .php_value;

        switch (node.tag) {
            .named_type => {
                const type_name = self.getString(node.data.named_type.name);
                // mixed类型应该使用php_value
                if (std.mem.eql(u8, type_name, "mixed")) {
                    return .php_value;
                }
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
            .array_init => {
                // 空数组可以作为编译时常量（在类注册时初始化）
                const array_data = expr_node.data.array_init;
                if (array_data.elements.len == 0) {
                    inst.op = .{ .array_new = .{ .capacity = 0 } };
                } else {
                    // 非空数组需要在运行时初始化
                    self.allocator.destroy(inst);
                    return null;
                }
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
        const short_class_name = self.getString(class_data.name);

        // ✅ 获取完整的类名（包含命名空间）
        const class_name = try self.getFullClassName(short_class_name);

        var methods = std.ArrayListUnmanaged(TypeDef.Method){};
        var properties = std.ArrayListUnmanaged(TypeDef.Property){};
        var constants = std.ArrayListUnmanaged(TypeDef.Constant){};
        var traits = std.ArrayListUnmanaged([]const u8){};
        var trait_adaptations = std.ArrayListUnmanaged(TypeDef.TraitAdaptation){};
        defer traits.deinit(self.allocator);

        // 收集接口名称
        var interfaces = try std.ArrayList([]const u8).initCapacity(self.allocator, class_data.implements.len);
        defer interfaces.deinit(self.allocator);
        for (class_data.implements) |impl_idx| {
            const impl_node = self.getNode(impl_idx) orelse continue;
            const iface_name = switch (impl_node.tag) {
                .named_type => self.getString(impl_node.data.named_type.name),
                .variable => self.getString(impl_node.data.variable.name),
                .literal_string => self.getString(impl_node.data.literal_string.value),
                else => continue,
            };
            // ✅ 解析接口名称（可能有命名空间）
            const full_iface_name = try self.resolveClassName(iface_name);
            try interfaces.append(self.allocator, full_iface_name);
        }

        const interfaces_slice = try interfaces.toOwnedSlice(self.allocator);

        // Create type definition
        const type_def = try self.allocator.create(TypeDef);

        // ✅ 解析父类名称（可能有命名空间）
        const parent_name = if (class_data.extends) |ext_idx| blk: {
            const ext_node = self.getNode(ext_idx) orelse break :blk null;
            const parent_short_name = switch (ext_node.tag) {
                .named_type => self.getString(ext_node.data.named_type.name),
                .variable => self.getString(ext_node.data.variable.name),
                .literal_string => self.getString(ext_node.data.literal_string.value),
                else => break :blk null,
            };
            break :blk try self.resolveClassName(parent_short_name);
        } else null;

        type_def.* = .{
            .name = class_name,
            .kind = .class,
            .parent = parent_name,
            .interfaces = interfaces_slice,
            .traits = &.{},
            .trait_adaptations = &.{},
            .properties = &.{},
            .methods = &.{},
            .constants = &.{},
            .location = self.current_location,
        };

        if (self.module) |module| {
            try module.addTypeDef(type_def);
        }

        // Register class in symbol table
        try self.symbol_table.defineClass(class_name, type_def.parent, type_def.interfaces, self.current_location);

        // Enter class scope
        _ = try self.symbol_table.enterScope(.class, class_name);

        // Process class members
        for (class_data.members) |member_idx| {
            const member = self.getNode(member_idx) orelse continue;
            switch (member.tag) {
                .method_decl => {
                    try methods.append(self.allocator, self.getMethodMeta(member));
                    // Constructor promotion: promoted params become properties
                    const md = member.data.method_decl;
                    if (std.mem.eql(u8, self.getString(md.name), "__construct")) {
                        for (md.params) |param_idx| {
                            const pnode = self.getNode(param_idx) orelse continue;
                            if (pnode.tag != .parameter) continue;
                            const pd = pnode.data.parameter;
                            if (!pd.is_promoted) continue;
                            const pname_raw = self.getString(pd.name);
                            // Strip '$' prefix: param "$x" -> property "x"
                            const pname = if (pname_raw.len > 0 and pname_raw[0] == '$')
                                pname_raw[1..]
                            else
                                pname_raw;
                            const ptype = if (pd.type) |t| try self.resolveTypeNode(t) else .php_value;
                            const vis: TypeDef.Visibility = if (pd.modifiers.is_private)
                                .private
                            else if (pd.modifiers.is_protected)
                                .protected
                            else
                                .public;
                            try properties.append(self.allocator, .{
                                .name = pname,
                                .type_ = ptype,
                                .default_value = null,
                                .is_static = false,
                                .visibility = vis,
                            });
                        }
                    }
                    try self.generateMethodDecl(member, class_name);
                },
                .expr_list => {
                    // Handle multiple property declarations (e.g., private $a, $b;)
                    const expr_list = member.data.expr_list;
                    for (expr_list.exprs) |prop_idx| {
                        const prop_node = self.getNode(prop_idx) orelse continue;
                        if (prop_node.tag == .property_decl) {
                            const prop_data = prop_node.data.property_decl;
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

                            try self.generatePropertyDecl(prop_node, class_name);
                        }
                    }
                },
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

                    // Generate hook methods for properties with hooks
                    for (prop_data.hooks) |hook_idx| {
                        const hook_node = self.getNode(hook_idx) orelse continue;
                        if (hook_node.tag != .property_hook) continue;
                        const hook_data = hook_node.data.property_hook;
                        const hook_name = self.getString(hook_data.name);
                        // Generate synthetic method: __prop_get_<name> or __prop_set_<name>
                        var method_buf: [256]u8 = undefined;
                        const method_name_str = std.fmt.bufPrint(&method_buf, "__prop_{s}_{s}", .{ hook_name, prop_name }) catch continue;
                        const method_full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name_str });
                        const hook_func = try self.allocator.create(Function);
                        hook_func.* = Function.init(self.allocator, method_full_name);
                        hook_func.name_owned = true;
                        hook_func.is_method = true;
                        hook_func.class_name = class_name;
                        hook_func.location = self.current_location;
                        if (self.module) |module| {
                            try module.addFunction(hook_func);
                        }
                        try methods.append(self.allocator, .{
                            .name = try self.allocator.dupe(u8, method_name_str),
                            .visibility = .public,
                            .is_static = false,
                        });
                        // Generate hook method body
                        const prev_function = self.current_function;
                        const prev_class = self.current_class;
                        const prev_block = self.current_block;
                        const prev_var_registers = self.var_registers;
                        self.current_function = hook_func;
                        self.current_class = class_name;
                        self.var_registers = .{};
                        self.block_counter = 0;
                        const entry = try hook_func.createBlock("entry");
                        self.setCurrentBlock(entry);
                        // Add $this param
                        try hook_func.addParam(.{ .name = "this", .type_ = Type{ .php_object = class_name }, .has_default = false, .is_variadic = false, .is_reference = false });
                        self.current_has_this_param = true;
                        const param_reg = try self.emitWithResult(.{ .param = .{ .index = 0, .name = "this" } }, Type{ .php_object = class_name });
                        const this_reg = try self.getOrCreateVarRegister("this", .php_value);
                        _ = try self.emit(.{ .store = .{ .ptr = this_reg, .value = param_reg } }, null);
                        try self.putVarRegister("$this", this_reg);
                        // For set hooks, add $value param
                        if (std.mem.eql(u8, hook_name, "set")) {
                            try hook_func.addParam(.{ .name = "$value", .type_ = .php_value, .has_default = false, .is_variadic = false, .is_reference = false });
                            const value_param = try self.emitWithResult(.{ .param = .{ .index = 1, .name = "$value" } }, .php_value);
                            const value_reg = try self.getOrCreateVarRegister("$value", .php_value);
                            _ = try self.emit(.{ .store = .{ .ptr = value_reg, .value = value_param } }, null);
                        }
                        // Generate hook body
                        const body_result = try self.generateExpression(hook_data.body);
                        if (!self.isBlockTerminated()) {
                            self.setTerminator(.{ .ret = body_result });
                        }
                        self.current_has_this_param = false;
                        self.var_registers.deinit(self.allocator);
                        self.var_registers = prev_var_registers;
                        self.current_function = prev_function;
                        self.current_class = prev_class;
                        self.current_block = prev_block;
                    }
                },
                .const_decl => {
                    // 收集常量信息
                    const const_data = member.data.const_decl;
                    const const_name = self.getString(const_data.name);

                    // 提取常量值（仅支持简单字面量）
                    const value_node = self.getNode(const_data.value) orelse continue;
                    const const_value: ?TypeDef.ConstantValue = switch (value_node.tag) {
                        .literal_int => .{ .int = value_node.data.literal_int.value },
                        .literal_float => .{ .float = value_node.data.literal_float.value },
                        .literal_string => .{ .string = self.getString(value_node.data.literal_string.value) },
                        .literal_bool => blk: {
                            // 从 main_token 判断是 true 还是 false
                            const is_true = value_node.main_token.tag == .k_true;
                            break :blk .{ .bool = is_true };
                        },
                        .literal_null => .{ .null = {} },
                        else => null, // 跳过复杂表达式
                    };

                    if (const_value) |cv| {
                        try constants.append(self.allocator, .{
                            .name = const_name,
                            .value = cv,
                            .visibility = .public,
                        });
                    }

                    try self.generateClassConstDecl(member, class_name);
                },
                .trait_use => {
                    const tu = member.data.trait_use;
                    for (tu.traits) |tidx| {
                        const tnode = self.getNode(tidx) orelse continue;
                        switch (tnode.tag) {
                            .named_type => try traits.append(
                                self.allocator,
                                try self.resolveClassName(
                                    self.getString(tnode.data.named_type.name),
                                ),
                            ),
                            .variable => try traits.append(
                                self.allocator,
                                try self.resolveClassName(
                                    self.getString(tnode.data.variable.name),
                                ),
                            ),
                            .literal_string => try traits.append(
                                self.allocator,
                                try self.resolveClassName(
                                    self.getString(
                                        tnode.data.literal_string.value,
                                    ),
                                ),
                            ),
                            else => {},
                        }
                    }
                    for (tu.adaptations) |adaptation| {
                        try trait_adaptations.append(
                            self.allocator,
                            try self.lowerTraitAdaptation(adaptation),
                        );
                    }
                },
                else => {},
            }
        }

        type_def.methods = try methods.toOwnedSlice(self.allocator);
        type_def.properties = try properties.toOwnedSlice(self.allocator);
        type_def.constants = try constants.toOwnedSlice(self.allocator);
        type_def.traits = try traits.toOwnedSlice(self.allocator);
        type_def.trait_adaptations = try trait_adaptations.toOwnedSlice(
            self.allocator,
        );

        // 收集类上的 PHP attributes (#[...])
        if (class_data.attributes.len > 0) {
            var attrs = std.ArrayListUnmanaged(TypeDef.Attribute){};
            for (class_data.attributes) |attr_idx| {
                const attr_node = self.getNode(attr_idx) orelse continue;
                if (attr_node.tag != .attribute) continue;
                const attr_data = attr_node.data.attribute;
                const attr_name = self.getString(attr_data.name);
                var arg_strs = std.ArrayListUnmanaged([]const u8){};
                for (attr_data.args) |arg_idx| {
                    const arg_node = self.getNode(arg_idx) orelse continue;
                    const val = self.getConstantValue(arg_node);
                    if (val) |cv| {
                        if (cv.string_val) |s| {
                            try arg_strs.append(self.allocator, s);
                        } else if (cv.int_val) |iv| {
                            const s = try std.fmt.allocPrint(
                                self.allocator,
                                "{d}",
                                .{iv},
                            );
                            try arg_strs.append(self.allocator, s);
                        }
                    }
                }
                try attrs.append(self.allocator, .{
                    .name = attr_name,
                    .args = try arg_strs.toOwnedSlice(
                        self.allocator,
                    ),
                });
            }
            type_def.attributes = try attrs.toOwnedSlice(
                self.allocator,
            );
        }

        // 构建常量缓存：O(1) 查找
        for (type_def.constants) |const_info| {
            var key_buf: [256]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "{s}::{s}", .{ class_name, const_info.name }) catch continue;
            const key_owned = try self.allocator.dupe(u8, key);
            try self.constant_cache.put(self.allocator, key_owned, const_info.value);
        }

        // Leave class scope
        self.symbol_table.leaveScope();
    }

    /// Generate IR for interface declaration
    fn generateInterfaceDecl(self: *Self, node: *const Node) !void {
        const iface_data = node.data.container_decl;
        const iface_name = self.getString(iface_data.name);

        // 检查是否与PHP内置接口冲突
        const builtin_interfaces = [_][]const u8{
            "Traversable",
            "Iterator",
            "IteratorAggregate",
            "Throwable",
            "ArrayAccess",
            "Serializable",
            "Closure",
            "Generator",
            "DateTimeInterface",
            "JsonSerializable",
            "Countable",
            "Stringable",
        };

        for (builtin_interfaces) |builtin| {
            if (std.mem.eql(u8, iface_name, builtin)) {
                self.diagnostics.reportWarning(
                    self.current_location,
                    "Skipping redeclaration of built-in interface '{s}'",
                    .{iface_name},
                );
                return;
            }
        }

        const type_def = try self.allocator.create(TypeDef);
        type_def.* = .{
            .name = iface_name,
            .kind = .interface,
            .parent = null,
            .interfaces = &.{},
            .traits = &.{},
            .trait_adaptations = &.{},
            .properties = &.{},
            .methods = &.{},
            .constants = &.{},
            .location = self.current_location,
        };

        if (self.module) |module| {
            try module.addTypeDef(type_def);
        }
    }

    /// Generate IR for enum declaration
    fn generateEnumDecl(self: *Self, node: *const Node) !void {
        if (node.tag != .enum_decl) return;
        const enum_data = node.data.container_decl;
        const short_name = self.getString(enum_data.name);
        const enum_name = try self.getFullClassName(short_name);

        var methods = std.ArrayListUnmanaged(TypeDef.Method){};
        var constants = std.ArrayListUnmanaged(TypeDef.Constant){};
        var enum_cases = std.ArrayListUnmanaged(TypeDef.EnumCase){};

        // Resolve backing type from extends field
        var backing_type: ?[]const u8 = null;
        if (enum_data.extends) |ext_idx| {
            const ext_node = self.getNode(ext_idx) orelse null;
            if (ext_node) |en| {
                backing_type = switch (en.tag) {
                    .named_type => self.getString(en.data.named_type.name),
                    else => null,
                };
            }
        }

        // Collect interfaces
        var interfaces = try std.ArrayList([]const u8).initCapacity(
            self.allocator,
            enum_data.implements.len,
        );
        defer interfaces.deinit(self.allocator);
        for (enum_data.implements) |impl_idx| {
            const impl_node = self.getNode(impl_idx) orelse continue;
            const iface_name = switch (impl_node.tag) {
                .named_type => self.getString(impl_node.data.named_type.name),
                .variable => self.getString(impl_node.data.variable.name),
                .literal_string => self.getString(impl_node.data.literal_string.value),
                else => continue,
            };
            const full_iface = try self.resolveClassName(iface_name);
            try interfaces.append(self.allocator, full_iface);
        }
        const interfaces_slice = try interfaces.toOwnedSlice(self.allocator);

        // Create type definition early so methods can reference it
        const type_def = try self.allocator.create(TypeDef);
        type_def.* = .{
            .name = enum_name,
            .kind = .@"enum",
            .parent = null,
            .interfaces = interfaces_slice,
            .traits = &.{},
            .trait_adaptations = &.{},
            .properties = &.{},
            .methods = &.{},
            .constants = &.{},
            .backing_type = backing_type,
            .location = self.current_location,
        };

        if (self.module) |module| {
            try module.addTypeDef(type_def);
        }

        // Register enum in symbol table as a class
        try self.symbol_table.defineClass(
            enum_name,
            null,
            interfaces_slice,
            self.current_location,
        );

        _ = try self.symbol_table.enterScope(.class, enum_name);

        // Process enum members
        for (enum_data.members) |member_idx| {
            const member = self.getNode(member_idx) orelse continue;
            switch (member.tag) {
                .enum_case => {
                    const case_data = member.data.enum_case;
                    const case_name = self.getString(case_data.name);
                    // Extract case value if present
                    var case_value: ?TypeDef.ConstantValue = null;
                    if (case_data.value) |val_idx| {
                        const vn = self.getNode(val_idx);
                        if (vn) |value_node| {
                            case_value = switch (value_node.tag) {
                                .literal_int => .{ .int = value_node.data.literal_int.value },
                                .literal_float => .{ .float = value_node.data.literal_float.value },
                                .literal_string => .{ .string = self.getString(value_node.data.literal_string.value) },
                                .literal_bool => blk: {
                                    const is_true = value_node.main_token.tag == .k_true;
                                    break :blk .{ .bool = is_true };
                                },
                                .literal_null => .{ .null = {} },
                                else => null,
                            };
                        }
                    }
                    try enum_cases.append(self.allocator, .{
                        .name = case_name,
                        .value = case_value,
                    });
                },
                .method_decl => {
                    try methods.append(self.allocator, self.getMethodMeta(member));
                    try self.generateMethodDecl(member, enum_name);
                },
                .const_decl => {
                    const const_data = member.data.const_decl;
                    const const_name = self.getString(const_data.name);
                    const value_node = self.getNode(const_data.value) orelse continue;
                    const const_value: ?TypeDef.ConstantValue = switch (value_node.tag) {
                        .literal_int => .{ .int = value_node.data.literal_int.value },
                        .literal_float => .{ .float = value_node.data.literal_float.value },
                        .literal_string => .{ .string = self.getString(value_node.data.literal_string.value) },
                        .literal_bool => blk: {
                            const is_true = value_node.main_token.tag == .k_true;
                            break :blk .{ .bool = is_true };
                        },
                        .literal_null => .{ .null = {} },
                        else => null,
                    };
                    if (const_value) |cv| {
                        try constants.append(self.allocator, .{
                            .name = const_name,
                            .value = cv,
                            .visibility = .public,
                        });
                    }
                    try self.generateClassConstDecl(member, enum_name);
                },
                else => {},
            }
        }

        self.symbol_table.leaveScope();

        // Finalize type_def with collected data
        type_def.enum_cases = try self.allocator.dupe(
            TypeDef.EnumCase,
            enum_cases.items,
        );
        type_def.methods = try self.allocator.dupe(
            TypeDef.Method,
            methods.items,
        );
        type_def.constants = try self.allocator.dupe(
            TypeDef.Constant,
            constants.items,
        );
    }

    /// Generate IR for trait declaration
    fn generateTraitDecl(self: *Self, node: *const Node) !void {
        const trait_data = node.data.container_decl;
        const short_trait_name = self.getString(trait_data.name);
        const trait_name = try self.getFullClassName(short_trait_name);

        var methods = std.ArrayListUnmanaged(TypeDef.Method){};
        var properties = std.ArrayListUnmanaged(TypeDef.Property){};
        var constants = std.ArrayListUnmanaged(TypeDef.Constant){};
        var traits = std.ArrayListUnmanaged([]const u8){};
        var trait_adaptations = std.ArrayListUnmanaged(TypeDef.TraitAdaptation){};

        const type_def = try self.allocator.create(TypeDef);
        type_def.* = .{
            .name = trait_name,
            .kind = .trait,
            .parent = null,
            .interfaces = &.{},
            .traits = &.{},
            .trait_adaptations = &.{},
            .properties = &.{},
            .methods = &.{},
            .constants = &.{},
            .location = self.current_location,
        };

        if (self.module) |module| {
            try module.addTypeDef(type_def);
        }

        _ = try self.symbol_table.enterScope(.class, trait_name);
        defer self.symbol_table.leaveScope();

        for (trait_data.members) |member_idx| {
            const member = self.getNode(member_idx) orelse continue;
            switch (member.tag) {
                .method_decl => {
                    try methods.append(self.allocator, self.getMethodMeta(member));
                    try self.generateMethodDecl(member, trait_name);
                },
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

                    try self.generatePropertyDecl(member, trait_name);
                },
                .const_decl => {
                    const const_data = member.data.const_decl;
                    const const_name = self.getString(const_data.name);
                    const value_node = self.getNode(const_data.value) orelse continue;
                    const const_value: ?TypeDef.ConstantValue = switch (value_node.tag) {
                        .literal_int => .{ .int = value_node.data.literal_int.value },
                        .literal_float => .{ .float = value_node.data.literal_float.value },
                        .literal_string => .{
                            .string = self.getString(
                                value_node.data.literal_string.value,
                            ),
                        },
                        .literal_bool => blk: {
                            const is_true = value_node.main_token.tag == .k_true;
                            break :blk .{ .bool = is_true };
                        },
                        .literal_null => .{ .null = {} },
                        else => null,
                    };

                    if (const_value) |cv| {
                        try constants.append(self.allocator, .{
                            .name = const_name,
                            .value = cv,
                            .visibility = .public,
                        });
                    }

                    try self.generateClassConstDecl(member, trait_name);
                },
                .trait_use => {
                    const tu = member.data.trait_use;
                    for (tu.traits) |tidx| {
                        const tnode = self.getNode(tidx) orelse continue;
                        switch (tnode.tag) {
                            .named_type => try traits.append(
                                self.allocator,
                                try self.resolveClassName(
                                    self.getString(tnode.data.named_type.name),
                                ),
                            ),
                            .variable => try traits.append(
                                self.allocator,
                                try self.resolveClassName(
                                    self.getString(tnode.data.variable.name),
                                ),
                            ),
                            .literal_string => try traits.append(
                                self.allocator,
                                try self.resolveClassName(
                                    self.getString(
                                        tnode.data.literal_string.value,
                                    ),
                                ),
                            ),
                            else => {},
                        }
                    }
                    for (tu.adaptations) |adaptation| {
                        try trait_adaptations.append(
                            self.allocator,
                            try self.lowerTraitAdaptation(adaptation),
                        );
                    }
                },
                else => {},
            }
        }

        type_def.methods = try methods.toOwnedSlice(self.allocator);
        type_def.properties = try properties.toOwnedSlice(self.allocator);
        type_def.constants = try constants.toOwnedSlice(self.allocator);
        type_def.traits = try traits.toOwnedSlice(self.allocator);
        type_def.trait_adaptations = try trait_adaptations.toOwnedSlice(
            self.allocator,
        );
    }

    fn getMethodMeta(self: *Self, node: *const Node) TypeDef.Method {
        const method_data = node.data.method_decl;
        return .{
            .name = self.getString(method_data.name),
            .visibility = self.getVisibility(method_data.modifiers),
            .is_static = method_data.modifiers.is_static,
        };
    }

    fn getVisibility(
        self: *Self,
        modifiers: Node.Modifier,
    ) TypeDef.Visibility {
        _ = self;
        if (modifiers.is_private) return .private;
        if (modifiers.is_protected) return .protected;
        return .public;
    }

    fn lowerTraitAdaptation(
        self: *Self,
        adaptation: ast.TraitAdaptation,
    ) !TypeDef.TraitAdaptation {
        return switch (adaptation) {
            .insteadof => |data| blk: {
                var excluded_traits = std.ArrayListUnmanaged([]const u8){};
                for (data.excluded_traits) |excluded_trait_id| {
                    try excluded_traits.append(
                        self.allocator,
                        try self.resolveClassName(
                            self.getString(excluded_trait_id),
                        ),
                    );
                }
                break :blk .{
                    .insteadof = .{
                        .preferred = try self.lowerTraitMethodRef(
                            data.preferred,
                        ),
                        .excluded_traits = try excluded_traits.toOwnedSlice(
                            self.allocator,
                        ),
                    },
                };
            },
            .alias => |data| .{
                .alias = .{
                    .original = try self.lowerTraitMethodRef(data.original),
                    .alias = if (data.alias) |alias_id|
                        self.getString(alias_id)
                    else
                        null,
                    .visibility = if (data.visibility) |visibility|
                        self.lowerTraitVisibility(visibility)
                    else
                        null,
                },
            },
        };
    }

    fn lowerTraitMethodRef(
        self: *Self,
        method_ref: ast.TraitMethodReference,
    ) !TypeDef.TraitMethodRef {
        return .{
            .trait_name = if (method_ref.trait_name) |trait_name|
                try self.resolveClassName(self.getString(trait_name))
            else
                null,
            .method_name = self.getString(method_ref.method_name),
        };
    }

    fn lowerTraitVisibility(
        self: *Self,
        visibility: ast.TraitVisibility,
    ) TypeDef.Visibility {
        _ = self;
        return switch (visibility) {
            .public => .public,
            .protected => .protected,
            .private => .private,
        };
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
        func.name_owned = true; // 标记name需要释放
        func.is_method = true;
        func.class_name = class_name;
        func.location = self.current_location;

        if (self.module) |module| {
            try module.addFunction(func);
        }

        // Generate method body if present
        if (method_data.body) |body_idx| {
            const prev_function = self.current_function;
            const prev_class = self.current_class;
            const prev_block = self.current_block;
            const prev_var_registers = self.var_registers;

            self.current_function = func;
            self.current_class = class_name;
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

                self.current_has_this_param = true; // 设置标志

                // Emit param instruction
                const param_reg = try self.emitWithResult(.{ .param = .{ .index = 0, .name = "this" } }, Type{ .php_object = class_name });

                // 同时注册$this变量，以便在方法体中通过$this访问
                const this_reg = try self.getOrCreateVarRegister("this", .php_value);
                _ = try self.emit(.{ .store = .{ .ptr = this_reg, .value = param_reg } }, null);

                try self.putVarRegister("$this", this_reg);
            }

            // Process parameters
            try self.generateParameters(method_data.params);

            // Constructor promotion: emit $this->prop = $param for promoted params
            if (std.mem.eql(u8, method_name, "__construct") and !method_data.modifiers.is_static) {
                for (method_data.params) |param_idx| {
                    const pn = self.getNode(param_idx) orelse continue;
                    if (pn.tag != .parameter) continue;
                    const pd = pn.data.parameter;
                    if (!pd.is_promoted) continue;
                    const pname_raw = self.getString(pd.name);
                    // Strip '$' prefix: param is "$x" but property is "x"
                    const prop_name = if (pname_raw.len > 0 and pname_raw[0] == '$')
                        pname_raw[1..]
                    else
                        pname_raw;
                    // Load parameter value (param register uses "$x" key)
                    const param_val = blk: {
                        if (self.getVarRegister(pname_raw)) |reg| {
                            break :blk try self.emitWithResult(.{ .load = .{ .ptr = reg, .type_ = .php_value } }, .php_value);
                        }
                        break :blk try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    };
                    // Load $this
                    const this_val = blk: {
                        if (self.getVarRegister("this")) |reg| {
                            break :blk try self.emitWithResult(.{ .load = .{ .ptr = reg, .type_ = .php_value } }, .php_value);
                        }
                        break :blk try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    };
                    // Set property on $this (without '$' prefix)
                    _ = try self.emit(.{ .property_set = .{ .object = this_val, .property_name = prop_name, .value = param_val } }, null);
                }
            }

            // Generate body
            try self.generateStatement(body_idx);

            if (!self.isBlockTerminated()) {
                self.setTerminator(.{ .ret = null });
            }

            self.current_has_this_param = false; // 重置标志
            self.var_registers.deinit(self.allocator);
            self.var_registers = prev_var_registers;
            self.current_function = prev_function;
            self.current_class = prev_class;
            self.current_block = prev_block;
        }
    }

    /// Generate IR for property declaration
    fn generatePropertyDecl(self: *Self, node: *const Node, class_name: []const u8) !void {
        const prop_data = node.data.property_decl;
        const prop_name = self.getString(prop_data.name);

        // Register property in symbol table
        var prop_type: InferredType = .dynamic;
        if (prop_data.type) |type_idx| {
            const ir_type = try self.resolveTypeNode(type_idx);
            prop_type = .{ .concrete = irTypeToConcreteType(ir_type) };
        }

        try self.symbol_table.defineVariable(prop_name, prop_type, self.current_location);

        // 添加到TypeDef
        if (self.module) |module| {
            for (module.types.items) |type_def_ptr| {
                if (std.mem.eql(u8, type_def_ptr.name, class_name)) {
                    const is_public = prop_data.modifiers.is_public;
                    const is_static = prop_data.modifiers.is_static;

                    const prop_def = TypeDef.Property{
                        .name = prop_name,
                        .visibility = if (is_public) .public else if (prop_data.modifiers.is_protected) .protected else .private,
                        .is_static = is_static,
                        .type_ = if (prop_data.type) |type_idx| try self.resolveTypeNode(type_idx) else .php_value,
                        .default_value = if (prop_data.default_value) |val_idx| blk: {
                            // 只处理编译时常量，运行时表达式在构造函数中初始化
                            break :blk try self.tryMakeConstInstruction(val_idx);
                        } else null,
                    };

                    const new_props = try self.allocator.alloc(TypeDef.Property, type_def_ptr.properties.len + 1);
                    @memcpy(new_props[0..type_def_ptr.properties.len], type_def_ptr.properties);
                    new_props[type_def_ptr.properties.len] = prop_def;
                    if (type_def_ptr.properties.len > 0) {
                        self.allocator.free(type_def_ptr.properties);
                    }
                    type_def_ptr.properties = new_props;
                    break;
                }
            }
        }
    }

    /// Generate IR for class constant declaration
    fn generateClassConstDecl(self: *Self, node: *const Node, class_name: []const u8) !void {
        _ = class_name;
        const const_data = node.data.const_decl;
        const const_name = self.getString(const_data.name);

        // 类常量在 AOT 模式下作为静态属性处理，不需要生成 IR
        // 值会在代码生成阶段直接内联
        _ = const_data.value;

        // Register constant in symbol table
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

    fn generateDoWhileStmt(self: *Self, node: *const Node) !void {
        const do_while_data = node.data.do_while_stmt;

        const body_block = try self.createBlock("do_while_body");
        const cond_block = try self.createBlock("do_while_cond");
        const exit_block = try self.createBlock("do_while_exit");

        // Jump to body first (do-while always executes once)
        self.setTerminator(.{ .br = body_block });

        try self.loop_stack.append(self.allocator, .{
            .break_block = exit_block,
            .continue_block = cond_block,
        });

        // Generate body
        self.setCurrentBlock(body_block);
        try self.generateStatement(do_while_data.body);
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = cond_block });
        }

        // Generate condition
        self.setCurrentBlock(cond_block);
        const cond_reg = try self.generateExpression(do_while_data.condition);
        self.setTerminator(.{ .cond_br = .{
            .cond = cond_reg,
            .then_block = body_block,
            .else_block = exit_block,
        } });

        _ = self.loop_stack.pop();
        self.setCurrentBlock(exit_block);
    }

    /// Generate IR for for statement
    fn generateForStmt(self: *Self, node: *const Node) !void {
        const for_data = node.data.for_stmt;

        // 如果当前块已有指令，创建新块用于 init
        const need_init_block = if (self.current_block) |block|
            block.instructions.items.len > 0
        else
            false;

        var init_block: ?*BasicBlock = null;
        if (need_init_block) {
            init_block = try self.createBlock("for_init");
            self.setTerminator(.{ .br = init_block.? });
            self.setCurrentBlock(init_block.?);
        }

        // Generate init in current block (or new init block)
        if (for_data.init) |init_idx| {
            try self.generateStatement(init_idx);
        }

        // Create blocks
        const cond_block = try self.createBlock("for_cond");
        const body_block = try self.createBlock("for_body");
        const loop_block = try self.createBlock("for_loop");
        const exit_block = try self.createBlock("for_exit");

        // Jump to condition from current block
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
            // 条件可能生成了新块（如短路逻辑），使用当前块设置终止符
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

        // 检查 body_block 是否已终止
        const body_terminated = body_block.terminator != null;

        if (!body_terminated) {
            self.setCurrentBlock(body_block);
            self.setTerminator(.{ .br = loop_block });
        } else {
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
        const cond_reg = try self.emitWithResult(.{ .lt = .{ .lhs = counter_reg, .rhs = count_reg } }, .php_value);
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

        // Create blocks - 添加cleanup块确保迭代器总是被释放
        const cond_block = try self.createBlock("foreach_cond");
        const body_block = try self.createBlock("foreach_body");
        const increment_block = try self.createBlock("foreach_increment");
        const cleanup_block = try self.createBlock("foreach_cleanup");
        const exit_block = try self.createBlock("foreach_exit");

        // Initialize iterator
        const iter_args = try self.allocator.alloc(Register, 1);
        iter_args[0] = iterable_reg;

        // 对于引用迭代器，额外retain数组确保生命周期
        var array_backup: ?Register = null;
        if (foreach_data.value_by_ref) {
            // 保存数组引用
            array_backup = iterable_reg;
        }

        // 根据是否引用选择不同的初始化函数
        const init_func = if (foreach_data.value_by_ref) "php_array_iter_init_ref" else "php_array_iter_init";
        const iter_addr = try self.emitWithResult(.{
            .call = .{
                .func_name = init_func,
                .args = iter_args,
                .return_type = .php_value,
            },
        }, .php_value);

        // Alloc iterator storage (to update it in increment)
        const php_value_type_ptr = try self.allocator.create(Type);
        php_value_type_ptr.* = Type{ .php_value = {} };
        const iter_ptr_type = Type{ .ptr = php_value_type_ptr };
        const iter_ptr = try self.emitWithResult(.{ .alloca = .{ .type_ = .php_value, .count = 1 } }, iter_ptr_type);

        _ = try self.emit(.{ .store = .{ .ptr = iter_ptr, .value = iter_addr } }, null);

        // Jump to condition check
        self.setTerminator(.{ .br = cond_block });

        // Push loop context for break/continue - break和continue都跳转到cleanup
        try self.loop_stack.append(self.allocator, .{
            .break_block = cleanup_block,
            .continue_block = increment_block,
        });

        // Condition check: php_array_iter_valid(iter)
        self.setCurrentBlock(cond_block);
        const curr_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .php_value } }, .php_value);

        const valid_args = try self.allocator.alloc(Register, 1);
        valid_args[0] = curr_iter;

        const valid_val = try self.emitWithResult(.{ .call = .{
            .func_name = "php_array_iter_valid",
            .args = valid_args,
            .return_type = .php_value,
        } }, .php_value);

        // 循环结束时跳转到cleanup，而不是直接跳转到exit
        self.setTerminator(.{ .cond_br = .{
            .cond = valid_val,
            .then_block = body_block,
            .else_block = cleanup_block,
        } });

        // Body
        self.setCurrentBlock(body_block);
        // Load iter again (SSA)
        const body_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .php_value } }, .php_value);

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

            // 根据是否是引用选择不同的函数
            const func_name = if (foreach_data.value_by_ref) "php_array_iter_value_ref" else "php_array_iter_value";

            const val_val = try self.emitWithResult(.{ .call = .{
                .func_name = func_name,
                .args = val_args,
                .return_type = .php_value,
            } }, .php_value);

            _ = try self.emit(.{ .store = .{ .ptr = value_var, .value = val_val } }, null);

            // 如果是引用，标记变量为引用变量
            if (foreach_data.value_by_ref) {
                try self.putRefVar(value_name);
            }
        } else if (value_node != null and (value_node.?.tag == .array_init or value_node.?.tag == .list_assignment)) {
            // List destructuring: foreach ($arr as [$x, $y])
            const val_args = try self.allocator.alloc(Register, 1);
            val_args[0] = body_iter;
            const val_val = try self.emitWithResult(.{ .call = .{
                .func_name = "php_array_iter_value",
                .args = val_args,
                .return_type = .php_value,
            } }, .php_value);
            // 解构赋值
            try self.generateForeachListDestructure(val_val, foreach_data.value);
        }

        // Generate loop body
        try self.generateStatement(foreach_data.body);

        // Jump to increment block if not terminated
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = increment_block });
        }

        // Increment block: increment iterator
        self.setCurrentBlock(increment_block);
        const inc_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .php_value } }, .php_value);

        const next_args = try self.allocator.alloc(Register, 1);
        next_args[0] = inc_iter;

        const next_iter = try self.emitWithResult(.{ .call = .{
            .func_name = "php_array_iter_next",
            .args = next_args,
            .return_type = .php_value,
        } }, .php_value);
        _ = try self.emit(.{ .store = .{ .ptr = iter_ptr, .value = next_iter } }, null);

        self.setTerminator(.{ .br = cond_block });

        // Cleanup block - 所有退出路径都经过这里
        _ = self.loop_stack.pop();
        self.setCurrentBlock(cleanup_block);

        // Cleanup iterator
        const cleanup_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .php_value } }, .php_value);

        const free_args = try self.allocator.alloc(Register, 1);
        free_args[0] = cleanup_iter;

        _ = try self.emit(.{ .call = .{
            .func_name = "php_array_iter_free",
            .args = free_args,
            .return_type = .void,
        } }, null);

        // 清理引用变量标记
        if (foreach_data.value_by_ref) {
            const val_node = self.getNode(foreach_data.value);
            if (val_node != null and val_node.?.tag == .variable) {
                const val_name = self.getString(val_node.?.data.variable.name);
                // 从引用变量集合中移除
                for (self.ref_vars.items, 0..) |ref_name, i| {
                    if (std.mem.eql(u8, ref_name, val_name)) {
                        _ = self.ref_vars.swapRemove(i);
                        break;
                    }
                }
            }
        }

        // 跳转到真正的exit
        self.setTerminator(.{ .br = exit_block });

        // Exit block - 清理完成后继续执行
        self.setCurrentBlock(exit_block);

        // 再次free迭代器，确保异常路径也能清理
        // 引用计数会防止真正的双重释放
        const exit_iter = try self.emitWithResult(.{ .load = .{ .ptr = iter_ptr, .type_ = .php_value } }, .php_value);
        const exit_free_args = try self.allocator.alloc(Register, 1);
        exit_free_args[0] = exit_iter;
        _ = try self.emit(.{ .call = .{
            .func_name = "php_array_iter_free",
            .args = exit_free_args,
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
        var use_compare_chain = false;

        for (switch_data.cases, 0..) |case_idx, i| {
            const case_node = self.getNode(case_idx).?;
            const case_data = case_node.data.case;

            // 计算case值（必须是常量）
            const case_value_node = self.getNode(case_data.condition).?;
            const case_const = self.getConstantValue(case_value_node);

            if (case_const == null or case_const.?.string_val != null or case_const.?.is_null) {
                use_compare_chain = true;
            }

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

            const case_loc = self.diagnostics.getLocation(case_value_node.main_token.loc.start);
            try ir_cases.append(self.allocator, .{
                .value = case_value,
                .block = case_blocks.items[i],
                .source_line = case_loc.line,
            });
        }

        if (use_compare_chain) {
            var check_blocks = std.ArrayListUnmanaged(*BasicBlock){};
            defer check_blocks.deinit(self.allocator);

            for (switch_data.cases, 0..) |_, i| {
                if (i == 0) {
                    try check_blocks.append(self.allocator, self.current_block.?);
                } else {
                    const label = try std.fmt.allocPrint(self.allocator, "switch.check.{d}", .{i});
                    defer self.allocator.free(label);
                    const block = try self.createBlock(label);
                    try check_blocks.append(self.allocator, block);
                }
            }

            for (switch_data.cases, 0..) |case_idx, i| {
                self.setCurrentBlock(check_blocks.items[i]);
                const case_node = self.getNode(case_idx).?;
                const case_data = case_node.data.case;
                const case_reg = try self.generateExpression(case_data.condition);
                const match_reg = try self.emitWithResult(.{ .eq = .{ .lhs = value_reg, .rhs = case_reg } }, .php_value);
                const else_block = if (i + 1 < check_blocks.items.len) check_blocks.items[i + 1] else default_block;
                self.setTerminator(.{ .cond_br = .{
                    .cond = match_reg,
                    .then_block = case_blocks.items[i],
                    .else_block = else_block,
                } });
            }
        } else {
            const cases_slice = try self.allocator.dupe(Terminator.SwitchCase, ir_cases.items);
            self.setTerminator(.{ .switch_ = .{
                .value = value_reg,
                .cases = cases_slice,
                .default = default_block,
            } });
        }

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

        // 检测嵌套try-catch（可能存在执行顺序差异）
        if (self.try_stack.items.len > 0) {
            self.diagnostics.reportWarning(
                self.current_location,
                "Nested try-catch detected: exception handling order may differ from PHP interpreter",
                .{},
            );
        }

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

        _ = self.try_stack.pop();

        // Generate catch clauses — 每个 catch 子句一个独立块，dispatcher 链式类型匹配
        const target_after_catch = finally_block orelse exit_block;
        if (try_data.catch_clauses.len == 1) {
            // 单个 catch：直接在 catch_block 中生成
            self.setCurrentBlock(catch_block);
            try self.generateCatchClause(try_data.catch_clauses[0], target_after_catch);
            if (!self.isBlockTerminated()) {
                self.setTerminator(.{ .br = target_after_catch });
            }
        } else if (try_data.catch_clauses.len > 1) {
            // 多个 catch：为每个创建独立块，dispatcher 用 exception_matches 分支
            var catch_blocks_list = std.ArrayListUnmanaged(*BasicBlock){};
            defer catch_blocks_list.deinit(self.allocator);
            for (try_data.catch_clauses, 0..) |_, ci| {
                var buf2: [64]u8 = undefined;
                const blk_name = std.fmt.bufPrint(&buf2, "catch_{d}", .{ci}) catch "catch_n";
                const blk = try self.createBlock(blk_name);
                try catch_blocks_list.append(self.allocator, blk);
            }
            // dispatcher：在 catch_block 中查看异常类型（不消费）并分支
            self.setCurrentBlock(catch_block);
            const exc_reg = try self.emitWithResult(.{ .peek_exception = {} }, .php_value);
            for (try_data.catch_clauses, 0..) |catch_idx, ci| {
                const cnode = self.getNode(catch_idx) orelse continue;
                if (cnode.tag != .catch_clause) continue;
                const cdata = cnode.data.catch_clause;
                var exc_type: ?[]const u8 = null;
                if (cdata.exception_type) |type_idx| {
                    const tnode = self.getNode(type_idx);
                    if (tnode != null and tnode.?.tag == .named_type) {
                        exc_type = self.getString(tnode.?.data.named_type.name);
                    }
                }
                if (exc_type) |etype| {
                    // 有类型限定：检查 instanceof
                    const class_name_id = try self.module.?.internString(etype);
                    const class_name_reg = try self.emitWithResult(.{ .const_string = class_name_id }, .php_value);
                    const match_reg = try self.emitWithResult(.{ .instanceof = .{ .object = exc_reg, .class_name = class_name_reg } }, .bool);
                    const next_check = if (ci + 1 < catch_blocks_list.items.len) catch_blocks_list.items[ci + 1] else target_after_catch;
                    self.setTerminator(.{ .cond_br = .{
                        .cond = match_reg,
                        .then_block = catch_blocks_list.items[ci],
                        .else_block = next_check,
                    } });
                    // 后续分支需要新块
                    if (ci + 1 < try_data.catch_clauses.len) {
                        const cont_blk = try self.createBlock("catch_dispatch");
                        // 实际不需要新块，else_block 直接指向下一个 catch 块或 next_check
                        _ = cont_blk;
                    }
                } else {
                    // 无类型（catch all）：直接跳转
                    self.setTerminator(.{ .br = catch_blocks_list.items[ci] });
                }
                // 如果已设置 terminator，后续 emit 会到新块
                // 在 else_block 是下一个 catch_block 的情况下，需要在那个块继续 dispatch
                // 但 cond_br 的 else_block 直接指向下一个 catch_blocks_list[ci+1]
                // 所以不需要额外的 dispatch 块
                break; // dispatcher 只处理第一个，后续由 cond_br 链式跳转
            }
            // 为后续 catch 生成 dispatcher 入口（每个 catch block 入口检查自己的类型）
            for (try_data.catch_clauses, 0..) |catch_idx, ci| {
                self.setCurrentBlock(catch_blocks_list.items[ci]);
                const cnode2 = self.getNode(catch_idx) orelse continue;
                if (cnode2.tag != .catch_clause) continue;
                const cdata2 = cnode2.data.catch_clause;
                // 如果不是最后一个 catch 且有类型，需要在块入口也检查类型
                // （因为可能从上一个 catch 的 else_block 直接跳过来）
                var exc_type2: ?[]const u8 = null;
                if (cdata2.exception_type) |type_idx2| {
                    const tnode2 = self.getNode(type_idx2);
                    if (tnode2 != null and tnode2.?.tag == .named_type) {
                        exc_type2 = self.getString(tnode2.?.data.named_type.name);
                    }
                }
                if (ci > 0 and exc_type2 != null) {
                    // 非第一个有类型的 catch：需要在入口检查类型（不消费异常）
                    const exc_reg2 = try self.emitWithResult(.{ .peek_exception = {} }, .php_value);
                    const class_name_id2 = try self.module.?.internString(exc_type2.?);
                    const class_name_reg2 = try self.emitWithResult(.{ .const_string = class_name_id2 }, .php_value);
                    const match_reg2 = try self.emitWithResult(.{ .instanceof = .{ .object = exc_reg2, .class_name = class_name_reg2 } }, .bool);
                    const next_target = if (ci + 1 < catch_blocks_list.items.len) catch_blocks_list.items[ci + 1] else target_after_catch;
                    const body_block = try self.createBlock("catch_body");
                    self.setTerminator(.{ .cond_br = .{
                        .cond = match_reg2,
                        .then_block = body_block,
                        .else_block = next_target,
                    } });
                    self.setCurrentBlock(body_block);
                }
                try self.generateCatchClause(catch_idx, target_after_catch);
                if (!self.isBlockTerminated()) {
                    self.setTerminator(.{ .br = target_after_catch });
                }
            }
        } else {
            // 无 catch 子句
            self.setCurrentBlock(catch_block);
            if (!self.isBlockTerminated()) {
                self.setTerminator(.{ .br = target_after_catch });
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

                // 保存旧的映射
                const old_mapping = self.getVarRegister(var_name);

                // 临时移除旧映射，确保创建新寄存器
                self.removeVarRegister(var_name);

                // 为每个 catch 块创建唯一的变量名，避免寄存器重用
                const unique_var_name = try std.fmt.allocPrint(self.allocator, "{s}_catch_{d}_{d}", .{ var_name, index, @intFromPtr(node) });
                defer self.allocator.free(unique_var_name);

                // 创建新的寄存器
                const var_reg = try self.getOrCreateVarRegister(unique_var_name, .php_value);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = catch_reg } }, null);

                // 在当前作用域中注册异常变量
                try self.putVarRegister(var_name, var_reg);

                // Generate catch body
                try self.generateStatement(catch_data.body);

                // 恢复旧的映射
                if (old_mapping) |old_reg| {
                    try self.putVarRegister(var_name, old_reg);
                } else {
                    self.removeVarRegister(var_name);
                }

                if (!self.isBlockTerminated()) {
                    self.setTerminator(.{ .br = next_block });
                }
                return;
            }
        }

        // Generate catch body (no exception variable)
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
            const name_node = self.getNode(call_data.name) orelse return;
            if (name_node.tag != .literal_string) {
                const expr_reg = try self.generateExpression(go_data.call);
                const args = try self.allocator.alloc(Register, 1);
                args[0] = expr_reg;
                _ = try self.emit(.{ .call = .{
                    .func_name = "php_go_builtin",
                    .args = args,
                    .return_type = .php_value,
                } }, null);
                return;
            }
            const func_name = self.getString(name_node.data.literal_string.value);

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
        } else {
            // Fallback: treat as expression and call php_go_builtin
            const expr_reg = try self.generateExpression(go_data.call);
            const args = try self.allocator.alloc(Register, 1);
            args[0] = expr_reg;
            _ = try self.emit(.{ .call = .{
                .func_name = "php_go_builtin",
                .args = args,
                .return_type = .php_value,
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

        // 在返回前同步所有静态变量
        try self.syncStaticVars();

        if (return_data.expr) |expr_idx| {
            const value_reg = try self.generateExpression(expr_idx);
            self.setTerminator(.{ .ret = value_reg });
        } else {
            self.setTerminator(.{ .ret = null });
        }
    }

    /// 同步所有静态变量到全局表
    fn syncStaticVars(self: *Self) !void {
        if (self.static_vars.count() == 0) return;

        const func_name = if (self.current_function) |f| f.name else "global";
        const func_name_id = try self.module.?.internString(func_name);
        const func_name_reg = try self.emitWithResult(.{ .const_string = func_name_id }, .php_value);

        var iter = self.static_vars.iterator();
        while (iter.next()) |entry| {
            const var_name = entry.key_ptr.*;
            const var_name_id = try self.module.?.internString(var_name);
            const var_name_reg = try self.emitWithResult(.{ .const_string = var_name_id }, .php_value);

            // 读取局部变量
            if (self.getVarRegister(var_name)) |var_reg| {
                const value_reg = try self.emitWithResult(.{ .load = .{ .ptr = var_reg, .type_ = .php_value } }, .php_value);

                // 保存到静态变量表
                const args = try self.allocator.alloc(Register, 3);
                args[0] = func_name_reg;
                args[1] = var_name_reg;
                args[2] = value_reg;
                _ = try self.emitWithResult(.{ .call = .{ .func_name = "setStaticVar", .args = args, .return_type = .php_value } }, .php_value);
            }
        }
    }

    /// Generate IR for break statement
    fn generateBreakStmt(self: *Self, node: *const Node) !void {
        const break_data = node.data.break_stmt;

        // 获取 break 层级（默认 1）
        var level: usize = 1;
        if (break_data.level) |level_node_idx| {
            const level_node = self.getNode(level_node_idx) orelse return error.InvalidNode;
            if (level_node.tag == .literal_int) {
                const lit_data = level_node.data.literal_int;
                level = @intCast(lit_data.value);
            }
        }

        // 标记函数有多层 break
        if (level > 1) {
            if (self.current_function) |func| {
                func.has_multi_level_break = true;
            }
        }

        // 从循环栈中获取目标循环
        if (self.loop_stack.items.len >= level) {
            const target_idx = self.loop_stack.items.len - level;
            const ctx = self.loop_stack.items[target_idx];
            self.setTerminator(.{ .br = ctx.break_block });
        }
    }

    /// Generate IR for continue statement
    fn generateContinueStmt(self: *Self, node: *const Node) !void {
        const continue_data = node.data.continue_stmt;

        // 获取 continue 层级（默认 1）
        var level: usize = 1;
        if (continue_data.level) |level_node_idx| {
            const level_node = self.getNode(level_node_idx) orelse return error.InvalidNode;
            if (level_node.tag == .literal_int) {
                const lit_data = level_node.data.literal_int;
                level = @intCast(lit_data.value);
            }
        }

        // 标记函数有多层 continue
        if (level > 1) {
            if (self.current_function) |func| {
                func.has_multi_level_break = true;
            }
        }

        // 从循环栈中获取目标循环
        if (self.loop_stack.items.len >= level) {
            const target_idx = self.loop_stack.items.len - level;
            const ctx = self.loop_stack.items[target_idx];
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
    fn generateAssignment(self: *Self, node: *const Node) !Register {
        const assign_data = node.data.assignment;

        // 引用赋值：$b = &$a
        if (assign_data.is_reference) {
            try self.generateRefAssignment(assign_data.target, assign_data.value);
            return self.emitWithResult(.{ .const_null = {} }, .php_value);
        }

        // Generate value
        const value_reg = try self.generateExpression(assign_data.value);
        const value_node = self.getNode(assign_data.value);
        const value_is_object_init = value_node != null and (value_node.?.tag == .object_instantiation or value_node.?.tag == .anonymous_class);

        // Generate target
        const target_node = self.getNode(assign_data.target) orelse return value_reg;

        switch (target_node.tag) {
            .variable => {
                const var_name = self.getString(target_node.data.variable.name);

                // 检查是否是引用变量（foreach引用）
                if (self.isRefVar(var_name)) {
                    // 引用变量：使用php_ref_assign_ptr
                    if (self.lookupVarRegister(var_name)) |ptr_reg| {
                        const assign_args = try self.allocator.alloc(Register, 2);
                        assign_args[0] = ptr_reg; // alloca指针
                        assign_args[1] = value_reg;
                        _ = try self.emit(.{ .call = .{
                            .func_name = "php_ref_assign_ptr",
                            .args = assign_args,
                            .return_type = .void,
                        } }, null);
                    }
                    return value_reg;
                }

                // 检查是否是引用参数
                const is_ref_param = self.reference_params.contains(var_name);

                if (is_ref_param) {
                    // 引用参数：写入引用
                    const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);
                    _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = value_reg } }, null);
                } else {
                    // 检查是否是全局变量或在 __main__ 函数中
                    const is_global = self.global_vars.contains(var_name);
                    const is_static = self.static_vars.contains(var_name);
                    const is_main = if (self.current_function) |func| std.mem.eql(u8, func.name, "__main__") else false;

                    if (is_static) {
                        // 静态变量：同时更新局部和全局静态表
                        const var_reg = try self.getOrCreateVarRegister(var_name, value_reg.type_);
                        _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = value_reg } }, null);

                        // 同步到静态变量表
                        const func_name = if (self.current_function) |f| f.name else "global";
                        const func_name_id = try self.module.?.internString(func_name);
                        const func_name_reg = try self.emitWithResult(.{ .const_string = func_name_id }, .php_value);
                        const var_name_id = try self.module.?.internString(var_name);
                        const var_name_reg = try self.emitWithResult(.{ .const_string = var_name_id }, .php_value);

                        const args = try self.allocator.alloc(Register, 3);
                        args[0] = func_name_reg;
                        args[1] = var_name_reg;
                        args[2] = value_reg;
                        _ = try self.emitWithResult(.{ .call = .{ .func_name = "setStaticVar", .args = args, .return_type = .php_value } }, .php_value);
                    } else if (is_global or is_main) {
                        // 写入全局表
                        _ = try self.emit(.{ .global_set = .{ .name = var_name, .value = value_reg } }, null);

                        // 如果变量有本地 alloca（闭包引用捕获预创建），
                        // 也 store 到 alloca 以更新引用槽
                        if (self.lookupVarRegister(var_name)) |ptr_reg| {
                            _ = try self.emit(.{ .store = .{ .ptr = ptr_reg, .value = value_reg } }, null);
                        }

                        // 如果在 __main__ 中，也标记为全局变量
                        if (is_main and !is_global) {
                            try self.global_vars.put(self.allocator, var_name, {});
                        }
                    } else {
                        // 普通局部变量
                        const var_reg = try self.getOrCreateVarRegister(var_name, value_reg.type_);
                        _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = value_reg } }, null);
                    }
                }

                // Update symbol table
                try self.symbol_table.defineVariable(var_name, .dynamic, self.current_location);
            },
            .variable_variable => {
                // $$var = value: 动态变量赋值
                const inner_expr = target_node.data.variable_variable.expr;
                const name_reg = try self.generateExpression(inner_expr);
                _ = try self.emit(.{ .global_set_dynamic = .{ .name_reg = name_reg, .value = value_reg } }, null);
            },
            .array_access => {
                // 递归收集所有嵌套的键
                var keys: std.ArrayList(Register) = .empty;
                defer keys.deinit(self.allocator);
                var is_push_assignment = false;

                var current = target_node;
                while (current.tag == .array_access) {
                    if (current.data.array_access.index) |idx| {
                        const key_reg = try self.generateExpression(idx);
                        try keys.insert(self.allocator, 0, key_reg); // 插入到开头，保持顺序
                    } else {
                        is_push_assignment = true;
                    }

                    const target_expr = self.getNode(current.data.array_access.target);
                    if (target_expr == null or target_expr.?.tag != .array_access) break;
                    current = target_expr.?;
                }

                // 生成基础数组
                const base_array = try self.generateExpression(current.data.array_access.target);

                if (is_push_assignment) {
                    var current_array = base_array;
                    var i: usize = 0;
                    while (i < keys.items.len) : (i += 1) {
                        current_array = try self.emitWithResult(.{ .array_ensure = .{
                            .array = current_array,
                            .key = keys.items[i],
                        } }, .php_value);
                    }
                    _ = try self.emit(.{ .array_push = .{
                        .array = current_array,
                        .value = value_reg,
                    } }, null);
                    return value_reg;
                }

                if (keys.items.len == 1) {
                    // 单层：$arr[$key] = value
                    _ = try self.emit(.{ .array_set = .{ .array = base_array, .key = keys.items[0], .value = value_reg } }, null);
                } else {
                    // 多层：逐层使用 array_ensure 获取子数组
                    // 对于 $arr[k0][k1][k2] = value:
                    // temp1 = array_ensure(arr, k0)
                    // temp2 = array_ensure(temp1, k1)
                    // array_set(temp2, k2, value)

                    var current_array = base_array;
                    var i: usize = 0;
                    while (i + 1 < keys.items.len) : (i += 1) {
                        // 获取或创建子数组
                        current_array = try self.emitWithResult(.{ .array_ensure = .{
                            .array = current_array,
                            .key = keys.items[i],
                        } }, .php_value);
                    }

                    // 最后一层：设置实际值
                    _ = try self.emit(.{ .array_set = .{
                        .array = current_array,
                        .key = keys.items[keys.items.len - 1],
                        .value = value_reg,
                    } }, null);
                }
            },
            .property_access => {
                const target_idx = target_node.data.property_access.target;
                const target_ptr = &(self.nodes.?[target_idx]);
                const obj_reg = try self.generateExpression(target_idx);
                const prop_name = self.getString(target_node.data.property_access.property_name);
                _ = try self.emit(.{ .property_set = .{
                    .object = obj_reg,
                    .property_name = prop_name,
                    .value = value_reg,
                } }, null);
                // 只在obj_reg不是变量时release（变量的生命周期由作用域管理）
                const target_is_variable = target_ptr.tag == .variable;
                if (!target_is_variable) {
                    _ = try self.emit(.{ .release = .{ .operand = obj_reg } }, null);
                }
                _ = try self.emit(.{ .release = .{ .operand = value_reg } }, null);
                return value_reg;
            },
            .variable_property_access => {
                const target_idx = target_node.data.variable_property_access.target;
                const target_ptr = &(self.nodes.?[target_idx]);
                const obj_reg = try self.generateExpression(target_idx);
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
                // 只在obj_reg不是变量时release
                const target_is_variable = target_ptr.tag == .variable;
                if (!target_is_variable) {
                    _ = try self.emit(.{ .release = .{ .operand = obj_reg } }, null);
                }
                _ = try self.emit(.{ .release = .{ .operand = value_reg } }, null);
                return value_reg;
            },
            .static_property_access => {
                var class_name = self.getString(target_node.data.static_property_access.class_name);
                const prop_name = self.getString(target_node.data.static_property_access.property_name);

                // 解析特殊类名 (self/static/parent)
                if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static")) {
                    if (self.current_class) |cls| {
                        class_name = cls;
                    }
                }

                _ = try self.emit(.{ .static_property_set = .{
                    .class_name = class_name,
                    .property_name = prop_name,
                    .value = value_reg,
                } }, null);
            },
            .array_init => {
                // 短语法解构: [$a, $b] = $arr 或嵌套 [[$a,$b],[$c,$d]] = $nested
                const inner_elements = target_node.data.array_init.elements;
                var inner_targets = std.ArrayListUnmanaged(Node.Index){};
                defer inner_targets.deinit(self.allocator);
                for (inner_elements) |elem_idx| {
                    const elem_node = self.getNode(elem_idx) orelse continue;
                    if (elem_node.tag == .array_pair) {
                        try inner_targets.append(self.allocator, elem_node.data.array_pair.value);
                    } else {
                        try inner_targets.append(self.allocator, elem_idx);
                    }
                }
                try self.generateListDestructure(inner_targets.items, value_reg);
            },
            else => {},
        }

        if (value_is_object_init) {
            _ = try self.emit(.{ .release = .{ .operand = value_reg } }, null);
        }
        return value_reg;
    }

    /// foreach list destructuring: foreach ($arr as [$x, $y])
    fn generateForeachListDestructure(self: *Self, arr_reg: Register, node_idx: u32) !void {
        const node = self.getNode(node_idx) orelse return;
        const elements = switch (node.tag) {
            .array_init => node.data.array_init.elements,
            .list_assignment => node.data.list_assignment.targets,
            else => return,
        };
        for (elements, 0..) |elem_idx, i| {
            const elem_node = self.getNode(elem_idx) orelse continue;
            // 处理array_pair（有key的情况）或直接variable
            const var_node = if (elem_node.tag == .array_pair) self.getNode(elem_node.data.array_pair.value) else elem_node;
            if (var_node == null or var_node.?.tag != .variable) continue;
            const var_name = self.getString(var_node.?.data.variable.name);
            // arr_reg[i]
            const key_reg = try self.emitWithResult(.{ .const_int = @intCast(i) }, .i64);
            const get_args = try self.allocator.alloc(Register, 2);
            get_args[0] = arr_reg;
            get_args[1] = key_reg;
            const elem_val = try self.emitWithResult(.{ .array_get = .{ .array = arr_reg, .key = key_reg } }, .php_value);
            const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);
            _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = elem_val } }, null);
        }
    }

    /// 引用赋值：$b = &$a（简化实现：全局变量退化为值拷贝，局部变量支持真引用）
    fn generateRefAssignment(self: *Self, target_idx: u32, source_idx: u32) !void {
        const target_node = self.getNode(target_idx) orelse return;
        const source_node = self.getNode(source_idx) orelse return;

        if (source_node.tag != .variable or target_node.tag != .variable) {
            const val = try self.generateExpression(source_idx);
            if (target_node.tag == .variable) {
                const var_name = self.getString(target_node.data.variable.name);
                const is_main = if (self.current_function) |func| std.mem.eql(u8, func.name, "__main__") else false;
                if (is_main or self.global_vars.contains(var_name)) {
                    _ = try self.emit(.{ .global_set = .{ .name = var_name, .value = val } }, null);
                }
            }
            return;
        }

        const src_name = self.getString(source_node.data.variable.name);
        const tgt_name = self.getString(target_node.data.variable.name);
        const is_main = if (self.current_function) |func| std.mem.eql(u8, func.name, "__main__") else false;

        if (is_main or self.global_vars.contains(src_name)) {
            // 全局变量：退化为值拷贝（TODO: 真引用需要更复杂实现）
            const src_val = try self.emitWithResult(.{ .global_get = .{ .name = src_name } }, .php_value);
            _ = try self.emit(.{ .global_set = .{ .name = tgt_name, .value = src_val } }, null);
        } else {
            // 局部变量：真引用
            const src_reg = try self.getOrCreateVarRegister(src_name, .php_value);
            const ref_reg = try self.emitWithResult(.{ .make_ref = .{ .ptr = src_reg } }, .php_value);
            const tgt_reg = try self.getOrCreateVarRegister(tgt_name, .php_value);
            _ = try self.emit(.{ .store = .{ .ptr = tgt_reg, .value = ref_reg } }, null);
            try self.ref_vars.append(self.allocator, tgt_name);
        }
    }

    /// Generate IR for compound assignment (+=, -=, *=, /=, %=, .=)
    /// Compound assignment: $a += $b is equivalent to $a = $a + $b
    fn generateCompoundAssignment(self: *Self, node: *const Node) !void {
        const compound_data = node.data.compound_assignment;
        const op_tag = compound_data.op;

        // Get target node
        const target_node = self.getNode(compound_data.target) orelse return;

        // 检查是否是引用变量
        var is_ref = false;
        var ref_ptr_reg: ?Register = null; // 指针寄存器
        var current_value: Register = undefined;

        if (target_node.tag == .variable) {
            const var_name = self.getString(target_node.data.variable.name);
            if (self.isRefVar(var_name)) {
                is_ref = true;
                // 保存指针寄存器
                if (self.lookupVarRegister(var_name)) |ptr_reg| {
                    ref_ptr_reg = ptr_reg;
                    // 解引用获取当前值
                    current_value = try self.generateExpression(compound_data.target);
                } else {
                    return error.UndefinedVariable;
                }
            } else {
                // 普通变量，正常生成
                current_value = try self.generateExpression(compound_data.target);
            }
        } else {
            // 非变量目标（如数组元素），正常生成
            current_value = try self.generateExpression(compound_data.target);
        }

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
            .double_question_equal => try self.generateNullCoalesce(current_value, rhs_value),
            else => return error.UnsupportedCompoundOperator,
        };

        // Store the result back to the target (write)
        switch (target_node.tag) {
            .variable => {
                const var_name = self.getString(target_node.data.variable.name);

                if (is_ref) {
                    // 如果是引用，直接传递指针寄存器（不load）
                    const assign_args = try self.allocator.alloc(Register, 2);
                    assign_args[0] = ref_ptr_reg.?; // 传递alloca指针
                    assign_args[1] = result_reg;
                    _ = try self.emit(.{ .call = .{
                        .func_name = "php_ref_assign_ptr",
                        .args = assign_args,
                        .return_type = .void,
                    } }, null);
                } else {
                    // 检查是否是全局变量或在 __main__ 函数中
                    const is_global = self.global_vars.contains(var_name);
                    const is_main = if (self.current_function) |func| std.mem.eql(u8, func.name, "__main__") else false;

                    if (is_global or is_main) {
                        // 写入全局表
                        _ = try self.emit(.{ .global_set = .{ .name = var_name, .value = result_reg } }, null);
                    } else {
                        // 普通变量，直接存储
                        const var_reg = try self.getOrCreateVarRegister(var_name, result_reg.type_);
                        _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = result_reg } }, null);
                    }
                }

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
                } else {
                    // $arr[] += value - not supported, would need to read last element
                    return error.UnsupportedCompoundOperator;
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
            .static_property_access => {
                var class_name = self.getString(target_node.data.static_property_access.class_name);
                const prop_name = self.getString(target_node.data.static_property_access.property_name);

                // 解析特殊类名 (self/static/parent)
                if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static")) {
                    if (self.current_class) |cls| {
                        class_name = cls;
                    }
                }

                _ = try self.emit(.{ .static_property_set = .{
                    .class_name = class_name,
                    .property_name = prop_name,
                    .value = result_reg,
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
        try self.generateListDestructure(list_data.targets, array_reg);
    }

    /// 递归处理 list/短数组解构赋值
    fn generateListDestructure(self: *Self, targets: []const Node.Index, array_reg: Register) !void {
        for (targets, 0..) |target_idx, i| {
            const target_node = self.getNode(target_idx) orelse continue;

            // 跳过空位（list(,$b) 中的逗号）
            if (target_node.tag == .list_empty) continue;

            // Extract element at index i
            const index_reg = try self.emitWithResult(.{ .const_int = @as(i64, @intCast(i)) }, .i64);
            const elem_reg = try self.emitWithResult(.{ .array_get = .{
                .array = array_reg,
                .key = index_reg,
            } }, .php_value);

            if (target_node.tag == .variable) {
                const var_name = self.getString(target_node.data.variable.name);
                const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = elem_reg } }, null);
                try self.symbol_table.defineVariable(var_name, .dynamic, self.current_location);
            } else if (target_node.tag == .array_init) {
                // 嵌套解构: [[$a, $b], [$c, $d]] = $nested
                const inner_elements = target_node.data.array_init.elements;
                // 收集内部目标索引
                var inner_targets = std.ArrayListUnmanaged(Node.Index){};
                defer inner_targets.deinit(self.allocator);
                for (inner_elements) |elem_idx| {
                    const elem_node = self.getNode(elem_idx) orelse continue;
                    if (elem_node.tag == .array_pair) {
                        try inner_targets.append(self.allocator, elem_node.data.array_pair.value);
                    } else {
                        try inner_targets.append(self.allocator, elem_idx);
                    }
                }
                try self.generateListDestructure(inner_targets.items, elem_reg);
            } else if (target_node.tag == .property_access) {
                const obj_reg = try self.generateExpression(target_node.data.property_access.target);
                const prop_name = self.getString(target_node.data.property_access.property_name);
                _ = try self.emit(.{ .property_set = .{
                    .object = obj_reg,
                    .property_name = prop_name,
                    .value = elem_reg,
                } }, null);
            } else if (target_node.tag == .array_access) {
                const arr_reg = try self.generateExpression(target_node.data.array_access.target);
                if (target_node.data.array_access.index) |key_idx| {
                    const key_reg = try self.generateExpression(key_idx);
                    _ = try self.emit(.{ .array_set = .{
                        .array = arr_reg,
                        .key = key_reg,
                        .value = elem_reg,
                    } }, null);
                }
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
                // 标记为全局变量
                try self.global_vars.put(self.allocator, var_name, {});
            }
        }
    }

    /// Generate IR for static statement
    fn generateStaticStmt(self: *Self, node: *const Node) !void {
        const static_data = node.data.static_stmt;

        for (static_data.vars) |var_idx| {
            const var_node = self.getNode(var_idx) orelse continue;

            // 处理 static $var = value 形式
            if (var_node.tag == .assignment) {
                const lhs_idx = var_node.data.assignment.target;
                const rhs_idx = var_node.data.assignment.value;

                const lhs_node = self.getNode(lhs_idx) orelse continue;
                if (lhs_node.tag != .variable) continue;

                const var_name = self.getString(lhs_node.data.variable.name);

                // 记录为静态变量
                try self.static_vars.put(self.allocator, var_name, {});

                // 生成静态变量访问：先检查是否已初始化
                const func_name = if (self.current_function) |f| f.name else "global";
                const func_name_id = try self.module.?.internString(func_name);
                const func_name_reg = try self.emitWithResult(.{ .const_string = func_name_id }, .php_value);
                const var_name_id = try self.module.?.internString(var_name);
                const var_name_reg = try self.emitWithResult(.{ .const_string = var_name_id }, .php_value);

                // 调用 getStaticVar
                const get_args = try self.allocator.alloc(Register, 2);
                get_args[0] = func_name_reg;
                get_args[1] = var_name_reg;
                const current_val = try self.emitWithResult(.{ .call = .{ .func_name = "getStaticVar", .args = get_args, .return_type = .php_value } }, .php_value);

                // 如果是null（未初始化），则初始化
                const null_reg = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                const is_null = try self.emitWithResult(.{ .identical = .{ .lhs = current_val, .rhs = null_reg } }, .php_value);
                const then_block = try self.createBlock("static_init");
                const end_block = try self.createBlock("static_end");

                self.setTerminator(.{ .cond_br = .{ .cond = is_null, .then_block = then_block, .else_block = end_block } });

                // then块：初始化静态变量
                self.current_block = then_block;
                const init_val = try self.generateExpression(rhs_idx);
                const set_args = try self.allocator.alloc(Register, 3);
                set_args[0] = func_name_reg;
                set_args[1] = var_name_reg;
                set_args[2] = init_val;
                _ = try self.emitWithResult(.{ .call = .{ .func_name = "setStaticVar", .args = set_args, .return_type = .php_value } }, .php_value);
                self.setTerminator(.{ .br = end_block });

                // 继续执行
                self.current_block = end_block;

                // 创建局部变量指向静态变量
                const get_args2 = try self.allocator.alloc(Register, 2);
                get_args2[0] = func_name_reg;
                get_args2[1] = var_name_reg;
                const final_val = try self.emitWithResult(.{ .call = .{ .func_name = "getStaticVar", .args = get_args2, .return_type = .php_value } }, .php_value);
                const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = final_val } }, null);
            } else if (var_node.tag == .variable) {
                // 处理 static $var 形式（无初始值，默认null）
                const var_name = self.getString(var_node.data.variable.name);

                // 记录为静态变量
                try self.static_vars.put(self.allocator, var_name, {});

                const func_name = if (self.current_function) |f| f.name else "global";
                const func_name_id = try self.module.?.internString(func_name);
                const func_name_reg = try self.emitWithResult(.{ .const_string = func_name_id }, .php_value);
                const var_name_id = try self.module.?.internString(var_name);
                const var_name_reg = try self.emitWithResult(.{ .const_string = var_name_id }, .php_value);

                const get_args = try self.allocator.alloc(Register, 2);
                get_args[0] = func_name_reg;
                get_args[1] = var_name_reg;
                const current_val = try self.emitWithResult(.{ .call = .{ .func_name = "getStaticVar", .args = get_args, .return_type = .php_value } }, .php_value);

                const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);
                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = current_val } }, null);
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
            .variable_variable => self.generateVariableVariable(node),

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
            .anonymous_class => self.generateAnonymousClass(node),
            .property_access => self.generatePropertyAccess(node),
            .safe_property_access => self.generateSafePropertyAccess(node),
            .variable_property_access => self.generateVariablePropertyAccess(node),
            .static_property_access => self.generateStaticPropertyAccess(node),
            .class_constant_access => self.generateClassConstantAccess(node),

            // Closures
            .closure => self.generateClosure(node),
            .arrow_function => self.generateArrowFunction(node),

            // Generator expressions
            .yield_expr => self.generateYieldExpr(node),
            .yield_from_expr => self.generateYieldFromExpr(node),

            // Special expressions
            .match_expr => self.generateMatchExpr(node),
            .clone_with_expr => self.generateCloneWithExpr(node),
            .named_arg => self.generateNamedArg(node),
            .cast_expr => self.generateCastExpr(node),
            .expr_list => blk: {
                // 表达式列表：顺序执行所有表达式，返回最后一个的值
                const exprs = node.data.expr_list.exprs;
                var last_reg: Register = try self.emitWithResult(.const_null, .php_value);
                for (exprs) |expr_idx| {
                    last_reg = try self.generateExpression(expr_idx);
                }
                break :blk last_reg;
            },

            // $this 表达式 - 返回this参数寄存器
            .self_expr => blk: {
                if (self.lookupVarRegister("this")) |ptr_reg| {
                    break :blk self.emitWithResult(.{ .load = .{ .ptr = ptr_reg, .type_ = .php_value } }, .php_value);
                }
                break :blk self.emitWithResult(.const_null, .php_value);
            },

            // Assignment as expression — 返回已赋值的寄存器，不重新求值
            .assignment => try self.generateAssignment(node),

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
                    .double_question_equal => try self.generateNullCoalesce(current_value, rhs_value),
                    else => try self.emitWithResult(.const_null, .php_value),
                };

                // Store the result back to the target (write)
                switch (target_node.tag) {
                    .variable => {
                        const var_name = self.getString(target_node.data.variable.name);

                        if (self.isRefVar(var_name)) {
                            if (self.lookupVarRegister(var_name)) |ptr_reg| {
                                const assign_args = try self.allocator.alloc(Register, 2);
                                assign_args[0] = ptr_reg;
                                assign_args[1] = result_reg;
                                _ = try self.emit(.{ .call = .{
                                    .func_name = "php_ref_assign_ptr",
                                    .args = assign_args,
                                    .return_type = .void,
                                } }, null);
                            }
                        } else {
                            const is_global = self.global_vars.contains(var_name);
                            const is_main = if (self.current_function) |func| std.mem.eql(u8, func.name, "__main__") else false;
                            if (is_global or is_main) {
                                _ = try self.emit(.{ .global_set = .{ .name = var_name, .value = result_reg } }, null);
                            } else {
                                const var_reg = try self.getOrCreateVarRegister(var_name, result_reg.type_);
                                _ = try self.emit(.{ .store = .{ .ptr = var_reg, .value = result_reg } }, null);
                            }
                        }
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
                        } else {
                            // $arr[] += value - not supported
                            return error.UnsupportedCompoundOperator;
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
                    .static_property_access => {
                        var class_name = self.getString(target_node.data.static_property_access.class_name);
                        const prop_name = self.getString(target_node.data.static_property_access.property_name);

                        // 解析特殊类名 (self/static/parent)
                        if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static")) {
                            if (self.current_class) |cls| {
                                class_name = cls;
                            }
                        }

                        _ = try self.emit(.{ .static_property_set = .{
                            .class_name = class_name,
                            .property_name = prop_name,
                            .value = result_reg,
                        } }, null);
                    },
                    else => {},
                }

                // Return the result value
                break :blk result_reg;
            },

            // PHP 8.0: throw as expression (e.g., $a ?: throw new Ex())
            .throw_stmt => blk: {
                const throw_data = node.data.throw_stmt;
                const exception_reg = try self.generateExpression(throw_data.expression);
                self.setTerminator(.{ .throw = exception_reg });
                // 创建不可达块，让后续代码生成继续（运行时永远不会执行到这里）
                const unreachable_block = try self.createBlock("throw_unreachable");
                self.setCurrentBlock(unreachable_block);
                break :blk try self.emitWithResult(.const_null, .php_value);
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

    /// 解析类名：处理命名空间、别名、导入
    /// @param class_name 原始类名（可能是短名、别名、完全限定名）
    /// @return 完整的类名（包含命名空间）
    fn resolveClassName(self: *Self, class_name: []const u8) ![]const u8 {
        // 1. 空类名
        if (class_name.len == 0) return class_name;

        // 1.5 特殊关键字
        // self → 编译时解析为定义类（不需要 LSB）
        // static → 保留，运行时通过 getCurrentCalledClass() 解析（LSB）
        // parent → 保留，运行时解析
        if (std.mem.eql(u8, class_name, "self")) {
            if (self.current_class) |cls| return cls;
            return class_name;
        }

        // 2. 完全限定名（以 \ 开头）
        if (class_name[0] == '\\') {
            return class_name[1..]; // 去掉前导 \
        }

        // 3. 检查是否包含命名空间分隔符（已经是完整名）
        if (std.mem.indexOf(u8, class_name, "\\")) |_| {
            return class_name;
        }

        // 4. 检查别名表（use App\Service as S）
        if (self.namespace_aliases.get(class_name)) |full_name| {
            return full_name;
        }

        // 5. 检查导入表（use App\Service）
        if (self.namespace_imports.get(class_name)) |full_name| {
            return full_name;
        }

        // 6. 加上当前命名空间
        if (self.current_namespace) |ns| {
            return try std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ ns, class_name });
        }

        return class_name;
    }

    /// 获取完整的类名（包含命名空间）
    /// @param class_name 类的短名
    /// @return 完整的类名
    fn getFullClassName(self: *Self, class_name: []const u8) ![]const u8 {
        if (std.mem.indexOfScalar(u8, class_name, '\\') != null) {
            return class_name;
        }
        if (self.current_namespace) |ns| {
            return try std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ ns, class_name });
        }
        return class_name;
    }

    /// 处理 use 语句
    /// @param use_node use 语句节点
    fn generateUseStatement(self: *Self, use_node: *const Node) !void {
        if (use_node.tag != .use_stmt) return;

        const use_data = use_node.data.use_stmt;
        const full_name = self.getString(use_data.namespace);

        if (use_data.alias) |alias_id| {
            // use App\Service as S
            const alias = self.getString(alias_id);
            try self.namespace_aliases.put(self.allocator, alias, full_name);
        } else {
            // use App\Service
            const short_name = getLastPart(full_name);
            try self.namespace_imports.put(self.allocator, short_name, full_name);
        }
    }

    /// 获取完整名称的最后一部分
    /// @param full_name 完整名称（如 "App\\Utils\\Helper"）
    /// @return 最后一部分（如 "Helper"）
    fn getLastPart(full_name: []const u8) []const u8 {
        var i: usize = full_name.len;
        while (i > 0) {
            i -= 1;
            if (full_name[i] == '\\') {
                return full_name[i + 1 ..];
            }
        }
        return full_name;
    }

    /// 处理 namespace 语句
    /// @param namespace_node namespace 语句节点
    fn generateNamespaceStatement(self: *Self, namespace_node: *const Node) !void {
        if (namespace_node.tag != .namespace_stmt) return;

        const ns_data = namespace_node.data.namespace_stmt;
        self.current_namespace = self.getString(ns_data.name);
    }

    /// Generate IR for binary expression
    fn generateBinaryExpr(self: *Self, node: *const Node) !Register {
        const bin_data = node.data.binary_expr;

        // 常量字符串折叠
        if (bin_data.op == .dot) {
            const lhs_node = self.getNode(bin_data.lhs);
            const rhs_node = self.getNode(bin_data.rhs);

            if (lhs_node != null and rhs_node != null and
                lhs_node.?.tag == .literal_string and rhs_node.?.tag == .literal_string)
            {
                const lhs_id = lhs_node.?.data.literal_string.value;
                const rhs_id = rhs_node.?.data.literal_string.value;
                const lhs_str = self.getString(lhs_id);
                const rhs_str = self.getString(rhs_id);
                const folded = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ lhs_str, rhs_str });
                const folded_id = try self.module.?.internString(folded);
                return try self.emitWithResult(.{ .const_string = folded_id }, .php_string);
            }
        }

        // Try constant folding first
        if (try self.tryConstantFold(node)) |folded_reg| {
            return folded_reg;
        }

        // 短路求值：&&, ||, ??
        if (bin_data.op == .k_and or bin_data.op == .double_ampersand or
            bin_data.op == .k_or or bin_data.op == .double_pipe or
            bin_data.op == .double_question)
        {
            if (bin_data.op == .double_question) {
                return try self.generateNullCoalesceShortCircuit(bin_data.lhs, bin_data.rhs);
            }
            return try self.generateShortCircuitLogical(bin_data.lhs, bin_data.rhs, bin_data.op);
        }

        // Generate operands
        var lhs_reg: Register = undefined;
        var rhs_reg: Register = undefined;
        lhs_reg = try self.generateExpression(bin_data.lhs);
        rhs_reg = try self.generateExpression(bin_data.rhs);

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

            // Comparison - 返回 php_value，不是 bool
            .equal_equal => self.emitWithResult(.{ .eq = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .bang_equal => self.emitWithResult(.{ .ne = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .equal_equal_equal => self.emitWithResult(.{ .identical = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .bang_equal_equal => self.emitWithResult(.{ .not_identical = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .less => self.emitWithResult(.{ .lt = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .less_equal => self.emitWithResult(.{ .le = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .greater => self.emitWithResult(.{ .gt = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .greater_equal => self.emitWithResult(.{ .ge = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .spaceship => self.emitWithResult(.{ .spaceship = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .i64),

            // Bitwise
            .ampersand => self.emitWithResult(.{ .bit_and = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .pipe => self.emitWithResult(.{ .bit_or = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .caret => self.emitWithResult(.{ .bit_xor = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .less_less => self.emitWithResult(.{ .shl = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
            .greater_greater => self.emitWithResult(.{ .shr = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),

            // String concatenation
            .dot => self.emitWithResult(.{ .concat = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_string),

            // Null coalescing (handled above as short-circuit)
            .double_question => unreachable,

            // instanceof operator
            .k_instanceof => try self.generateInstanceOf(lhs_reg, bin_data.rhs),

            // Comma operator: evaluate both, return right
            .comma => rhs_reg,

            else => self.emitWithResult(.{ .add = .{ .lhs = lhs_reg, .rhs = rhs_reg } }, .php_value),
        };
    }

    /// Generate instanceof operator
    fn generateInstanceOf(self: *Self, obj_reg: Register, class_name_idx: Node.Index) !Register {
        // Get class name from AST node
        const class_node = self.getNode(class_name_idx) orelse return error.InvalidNode;
        const class_name = switch (class_node.tag) {
            .variable => self.getString(class_node.data.variable.name),
            .named_type => self.getString(class_node.data.named_type.name),
            .literal_string => self.getString(class_node.data.literal_string.value),
            else => return error.InvalidInstanceOfOperand,
        };

        // Intern class name as string
        const class_name_id = try self.module.?.internString(class_name);
        const class_name_reg = try self.emitWithResult(.{ .const_string = class_name_id }, .php_string);

        // Generate instanceof check
        return self.emitWithResult(.{ .instanceof = .{ .object = obj_reg, .class_name = class_name_reg } }, .php_value);
    }

    /// Generate null coalescing operator with short-circuit evaluation
    fn generateNullCoalesceShortCircuit(self: *Self, lhs_idx: Node.Index, rhs_idx: Node.Index) !Register {
        // Generate left operand
        const lhs_reg = try self.generateExpression(lhs_idx);

        // Create blocks for null check
        const rhs_block = try self.createBlock("coalesce_rhs");
        const merge_block = try self.createBlock("coalesce_merge");

        // Check if lhs is null: lhs === null
        const null_reg = try self.emitWithResult(.{ .const_null = {} }, .php_value);
        const is_null = try self.emitWithResult(.{ .identical = .{ .lhs = lhs_reg, .rhs = null_reg } }, .php_value);

        // if (is_null) goto rhs_block else goto merge_block
        self.setTerminator(.{ .cond_br = .{
            .cond = is_null,
            .then_block = rhs_block,
            .else_block = merge_block,
        } });
        const lhs_end_block = self.current_block.?;

        // RHS block: evaluate rhs only if lhs is null
        self.setCurrentBlock(rhs_block);
        const rhs_reg = try self.generateExpression(rhs_idx);
        self.setTerminator(.{ .br = merge_block });
        const rhs_end_block = self.current_block.?;

        // Merge with phi
        self.setCurrentBlock(merge_block);
        const incoming = try self.allocator.alloc(Instruction.PhiIncoming, 2);
        incoming[0] = .{ .value = lhs_reg, .block = lhs_end_block }; // not null: use lhs
        incoming[1] = .{ .value = rhs_reg, .block = rhs_end_block }; // null: use rhs

        return self.emitWithResult(.{ .phi = .{ .incoming = incoming } }, .php_value);
    }

    /// Generate null coalescing operator (deprecated, use generateNullCoalesceShortCircuit)
    fn generateNullCoalesce(self: *Self, lhs_reg: Register, rhs_reg: Register) !Register {
        // Create blocks for null check
        const rhs_block = try self.createBlock("coalesce_rhs");
        const merge_block = try self.createBlock("coalesce_merge");

        // Check if lhs is null: lhs === null
        const null_reg = try self.emitWithResult(.{ .const_null = {} }, .php_value);
        const is_null = try self.emitWithResult(.{ .identical = .{ .lhs = lhs_reg, .rhs = null_reg } }, .php_value);

        // if (is_null) goto rhs_block else goto merge_block
        self.setTerminator(.{ .cond_br = .{
            .cond = is_null,
            .then_block = rhs_block,
            .else_block = merge_block,
        } });
        const lhs_end_block = self.current_block.?;

        // RHS block: use rhs value
        self.setCurrentBlock(rhs_block);
        self.setTerminator(.{ .br = merge_block });
        const rhs_end_block = self.current_block.?;

        // Merge with phi
        self.setCurrentBlock(merge_block);
        const incoming = try self.allocator.alloc(Instruction.PhiIncoming, 2);
        incoming[0] = .{ .value = lhs_reg, .block = lhs_end_block }; // not null: use lhs
        incoming[1] = .{ .value = rhs_reg, .block = rhs_end_block }; // null: use rhs

        return self.emitWithResult(.{ .phi = .{ .incoming = incoming } }, .php_value);
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

                // 检查是否是引用变量（foreach引用）
                if (self.isRefVar(var_name)) {
                    // 引用变量：使用php_ref_assign_ptr
                    if (self.lookupVarRegister(var_name)) |ptr_reg| {
                        const assign_args = try self.allocator.alloc(Register, 2);
                        assign_args[0] = ptr_reg;
                        assign_args[1] = new_value;
                        _ = try self.emit(.{ .call = .{
                            .func_name = "php_ref_assign_ptr",
                            .args = assign_args,
                            .return_type = .void,
                        } }, null);
                    }
                } else if (self.static_vars.contains(var_name)) {
                    // Static变量：使用setStaticVar
                    const func_name = if (self.current_function) |f| f.name else "global";
                    const func_name_id = try self.module.?.internString(func_name);
                    const func_name_reg = try self.emitWithResult(.{ .const_string = func_name_id }, .php_value);
                    const var_name_id = try self.module.?.internString(var_name);
                    const var_name_reg = try self.emitWithResult(.{ .const_string = var_name_id }, .php_value);

                    const set_args = try self.allocator.alloc(Register, 3);
                    set_args[0] = func_name_reg;
                    set_args[1] = var_name_reg;
                    set_args[2] = new_value;
                    _ = try self.emitWithResult(.{ .call = .{ .func_name = "setStaticVar", .args = set_args, .return_type = .php_value } }, .php_value);

                    // 同时更新局部变量指针
                    if (self.lookupVarRegister(var_name)) |ptr_reg| {
                        _ = try self.emit(.{ .store = .{ .ptr = ptr_reg, .value = new_value } }, null);
                    }
                } else {
                    // 检查是否是全局变量或在 __main__ 函数中
                    const is_global = self.global_vars.contains(var_name);
                    const is_main = if (self.current_function) |func| std.mem.eql(u8, func.name, "__main__") else false;

                    if (is_global or is_main) {
                        // 写入全局表
                        _ = try self.emit(.{ .global_set = .{ .name = var_name, .value = new_value } }, null);
                    } else if (self.lookupVarRegister(var_name)) |ptr_reg| {
                        _ = try self.emit(.{ .store = .{ .ptr = ptr_reg, .value = new_value } }, null);
                    }
                }
            } else if (expr_node) |en| {
                // 处理属性访问和数组访问
                switch (en.tag) {
                    .static_property_access => {
                        var class_name = self.getString(en.data.static_property_access.class_name);
                        const prop_name = self.getString(en.data.static_property_access.property_name);

                        // 解析特殊类名
                        if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static")) {
                            if (self.current_class) |cls| {
                                class_name = cls;
                            }
                        }

                        _ = try self.emit(.{ .static_property_set = .{
                            .class_name = class_name,
                            .property_name = prop_name,
                            .value = new_value,
                        } }, null);
                    },
                    .property_access => {
                        const obj_reg = try self.generateExpression(en.data.property_access.target);
                        const prop_name = self.getString(en.data.property_access.property_name);
                        _ = try self.emit(.{ .property_set = .{
                            .object = obj_reg,
                            .property_name = prop_name,
                            .value = new_value,
                        } }, null);
                    },
                    .array_access => {
                        const array_reg = try self.generateExpression(en.data.array_access.target);
                        if (en.data.array_access.index) |idx| {
                            const key_reg = try self.generateExpression(idx);
                            _ = try self.emit(.{ .array_set = .{
                                .array = array_reg,
                                .key = key_reg,
                                .value = new_value,
                            } }, null);
                        }
                    },
                    else => {},
                }
            }

            // 前置运算符返回新值
            return new_value;
        }

        // @ 错误抑制运算符：设置运行时标志，表达式求值后清除
        // 当标志置位时，php_object_get 等函数返回 null 而非抛错
        if (unary_data.op == .at_sign) {
            _ = try self.emit(.{ .call = .{
                .func_name = "php_error_suppress_push",
                .args = &.{},
                .return_type = .void,
            } }, null);
            const inner_reg = try self.generateExpression(unary_data.expr);
            _ = try self.emit(.{ .call = .{
                .func_name = "php_error_suppress_pop",
                .args = &.{},
                .return_type = .void,
            } }, null);
            return inner_reg;
        }

        const operand_reg = try self.generateExpression(unary_data.expr);

        return switch (unary_data.op) {
            .minus => self.emitWithResult(.{ .neg = .{ .operand = operand_reg } }, operand_reg.type_),
            .bang => self.emitWithResult(.{ .not = .{ .operand = operand_reg } }, .php_value), // 返回 Value，不是 bool
            .tilde => self.emitWithResult(.{ .bit_not = .{ .operand = operand_reg } }, .i64),
            .plus => operand_reg, // Unary plus is a no-op
            .k_clone => self.emitWithResult(.{ .clone = .{ .operand = operand_reg } }, .php_value),
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
        if (expr_node) |en| {
            switch (en.tag) {
                .variable => {
                    const var_name = self.getString(en.data.variable.name);

                    // 检查是否是引用变量（foreach引用）
                    if (self.isRefVar(var_name)) {
                        // 引用变量：使用php_ref_assign_ptr
                        if (self.lookupVarRegister(var_name)) |ptr_reg| {
                            const assign_args = try self.allocator.alloc(Register, 2);
                            assign_args[0] = ptr_reg;
                            assign_args[1] = new_value;
                            _ = try self.emit(.{ .call = .{
                                .func_name = "php_ref_assign_ptr",
                                .args = assign_args,
                                .return_type = .void,
                            } }, null);
                        }
                    } else {
                        // 检查是否是全局变量或在 __main__ 函数中
                        const is_global = self.global_vars.contains(var_name);
                        const is_main = if (self.current_function) |func| std.mem.eql(u8, func.name, "__main__") else false;

                        if (is_global or is_main) {
                            // 写入全局表
                            _ = try self.emit(.{ .global_set = .{ .name = var_name, .value = new_value } }, null);
                        } else if (self.lookupVarRegister(var_name)) |ptr_reg| {
                            _ = try self.emit(.{ .store = .{ .ptr = ptr_reg, .value = new_value } }, null);
                        }
                    }
                },
                .static_property_access => {
                    var class_name = self.getString(en.data.static_property_access.class_name);
                    const prop_name = self.getString(en.data.static_property_access.property_name);

                    // 解析特殊类名
                    if (std.mem.eql(u8, class_name, "self") or std.mem.eql(u8, class_name, "static")) {
                        if (self.current_class) |cls| {
                            class_name = cls;
                        }
                    }

                    _ = try self.emit(.{ .static_property_set = .{
                        .class_name = class_name,
                        .property_name = prop_name,
                        .value = new_value,
                    } }, null);
                },
                .property_access => {
                    const obj_reg = try self.generateExpression(en.data.property_access.target);
                    const prop_name = self.getString(en.data.property_access.property_name);
                    _ = try self.emit(.{ .property_set = .{
                        .object = obj_reg,
                        .property_name = prop_name,
                        .value = new_value,
                    } }, null);
                },
                .array_access => {
                    const array_reg = try self.generateExpression(en.data.array_access.target);
                    if (en.data.array_access.index) |idx| {
                        const key_reg = try self.generateExpression(idx);
                        _ = try self.emit(.{ .array_set = .{
                            .array = array_reg,
                            .key = key_reg,
                            .value = new_value,
                        } }, null);
                    }
                },
                else => {},
            }
        }

        // 后置运算符返回原始值（operand_reg在SSA中是不可变的）
        return operand_reg;
    }

    /// Generate IR for ternary expression
    /// Generate short-circuit logical operation (&& and ||)
    fn generateShortCircuitLogical(self: *Self, lhs_idx: Node.Index, rhs_idx: Node.Index, op: TokenTag) !Register {
        // Generate left operand
        const lhs_reg = try self.generateExpression(lhs_idx);

        const is_and = (op == .k_and or op == .double_ampersand);

        // &&: 需要在分支前创建 false 常量，确保 phi 节点的值在 lhs_end_block 可用
        // 使用 const_bool=false 而非 const_int=0，保证 (string)false === "" 而非 "0"
        const false_val = if (is_and) try self.emitWithResult(.{ .const_bool = false }, .php_value) else undefined;

        // Create blocks
        const rhs_block = try self.createBlock("logical_rhs");
        const merge_block = try self.createBlock("logical_merge");

        // For &&: if lhs is false, skip rhs and return false
        // For ||: if lhs is true, skip rhs and return true
        if (is_and) {
            // if (!lhs) goto merge else goto rhs
            self.setTerminator(.{ .cond_br = .{
                .cond = lhs_reg,
                .then_block = rhs_block,
                .else_block = merge_block,
            } });
        } else {
            // if (lhs) goto merge else goto rhs
            self.setTerminator(.{ .cond_br = .{
                .cond = lhs_reg,
                .then_block = merge_block,
                .else_block = rhs_block,
            } });
        }

        const lhs_end_block = self.current_block.?;

        // Generate right operand
        self.setCurrentBlock(rhs_block);
        const rhs_reg = try self.generateExpression(rhs_idx);
        const rhs_end_block = self.current_block.?;
        self.setTerminator(.{ .br = merge_block });

        // Merge with phi node
        self.setCurrentBlock(merge_block);

        const incoming = try self.allocator.alloc(Instruction.PhiIncoming, 2);
        if (is_and) {
            // &&: [false from lhs_end, rhs from rhs_end]
            incoming[0] = .{ .value = false_val, .block = lhs_end_block };
            incoming[1] = .{ .value = rhs_reg, .block = rhs_end_block };
        } else {
            // ||: [lhs from lhs_end, rhs from rhs_end]
            incoming[0] = .{ .value = lhs_reg, .block = lhs_end_block };
            incoming[1] = .{ .value = rhs_reg, .block = rhs_end_block };
        }

        return self.emitWithResult(.{ .phi = .{ .incoming = incoming } }, .php_value);
    }

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
        var then_reg = if (ternary_data.then_expr) |then_idx|
            try self.generateExpression(then_idx)
        else
            cond_reg; // Elvis operator: $a ?: $b

        // 转换为php_value以统一类型
        if (then_reg.type_ != .php_value) {
            then_reg = try self.emitWithResult(.{ .box = .{ .value = then_reg, .from_type = then_reg.type_ } }, .php_value);
        }

        const then_end_block = self.current_block.?;
        self.setTerminator(.{ .br = merge_block });

        // Generate else expression
        self.setCurrentBlock(else_block);
        var else_reg = try self.generateExpression(ternary_data.else_expr);

        // 转换为php_value以统一类型
        if (else_reg.type_ != .php_value) {
            else_reg = try self.emitWithResult(.{ .box = .{ .value = else_reg, .from_type = else_reg.type_ } }, .php_value);
        }

        const else_end_block = self.current_block.?;
        self.setTerminator(.{ .br = merge_block });

        // Merge with phi node
        self.setCurrentBlock(merge_block);

        const incoming = try self.allocator.alloc(Instruction.PhiIncoming, 2);
        incoming[0] = .{ .value = then_reg, .block = then_end_block };
        incoming[1] = .{ .value = else_reg, .block = else_end_block };

        return self.emitWithResult(.{ .phi = .{ .incoming = incoming } }, .php_value);
    }

    /// Generate IR for function call
    /// 生成函数调用的 IR（包含对部分语言结构/内建的最小特判）
    fn generateFunctionCall(self: *Self, node: *const Node) !Register {
        const call_data = node.data.function_call;

        // Get function name
        const name_node = self.getNode(call_data.name) orelse {
            return self.emitWithResult(.const_null, .php_value);
        };

        // If callee is not a direct identifier, treat it as a runtime callable and use call_indirect.
        // This covers patterns like: ($arr[$k])($x), ($obj->prop)($x), ("strlen")($x), etc.
        var func_name: []const u8 = "";
        var indirect_callee: ?Register = null;

        if (name_node.tag == .variable) {
            const is_variable_token = name_node.main_token.tag == .t_variable;
            if (is_variable_token) {
                const var_name = self.getString(name_node.data.variable.name);
                if (self.getVarRegister(var_name)) |reg| {
                    indirect_callee = try self.emitWithResult(.{ .load = .{ .ptr = reg, .type_ = .php_value } }, .php_value);
                } else {
                    // 从全局变量读取
                    indirect_callee = try self.emitWithResult(.{ .global_get = .{ .name = var_name } }, .php_value);
                }
            } else {
                func_name = self.getString(name_node.data.variable.name);
            }
        } else if (name_node.tag == .literal_string) {
            func_name = self.getString(name_node.data.literal_string.value);
        } else {
            indirect_callee = try self.generateExpression(call_data.name);
        }

        // PHP 8.1 first-class callable: Closure::fromCallable(func_name)
        // The parser rewrites strlen(...) to Closure::fromCallable(strlen)
        if (std.mem.eql(u8, func_name, "Closure::fromCallable") and call_data.args.len == 1) {
            const arg_node = self.getNode(call_data.args[0]) orelse {
                return self.emitWithResult(.{ .const_null = {} }, .php_value);
            };
            // Extract the function name from the argument node
            const callable_name = switch (arg_node.tag) {
                .variable => self.getString(arg_node.data.variable.name),
                .literal_string => self.getString(arg_node.data.literal_string.value),
                else => "",
            };
            if (callable_name.len > 0) {
                const sid = try self.module.?.internString(callable_name);
                return self.emitWithResult(.{ .const_string = sid }, .php_string);
            }
            return self.emitWithResult(.{ .const_null = {} }, .php_value);
        }

        if (name_node.tag == .safe_property_access) {
            const access = name_node.data.safe_property_access;
            const object_reg = try self.generateExpression(access.target);
            const method_name_reg = try self.emitPropertyNameValue(self.getString(access.property_name));
            const args_arr = try self.emitWithResult(.{ .array_new = .{ .capacity = @intCast(call_data.args.len) } }, .php_array);

            for (call_data.args) |arg_idx| {
                const arg_node = self.getNode(arg_idx) orelse continue;
                if (arg_node.tag == .unpacking_expr) {
                    const spread_reg = try self.generateExpression(arg_node.data.unpacking_expr.expr);
                    const spread_args = try self.allocator.alloc(Register, 2);
                    spread_args[0] = args_arr;
                    spread_args[1] = spread_reg;
                    _ = try self.emit(.{ .call = .{
                        .func_name = "php_args_append_spread",
                        .args = spread_args,
                        .return_type = .php_value,
                    } }, null);
                    continue;
                }

                const expr_idx = if (arg_node.tag == .named_arg) arg_node.data.named_arg.value else arg_idx;
                const val_reg = try self.generateExpression(expr_idx);
                _ = try self.emit(.{ .array_push = .{ .array = args_arr, .value = val_reg } }, null);
            }

            const safe_call_args = try self.allocator.alloc(Register, 3);
            safe_call_args[0] = object_reg;
            safe_call_args[1] = method_name_reg;
            safe_call_args[2] = args_arr;
            return self.emitWithResult(.{ .call = .{
                .func_name = "php_object_call_safe_args_array",
                .args = safe_call_args,
                .return_type = .php_value,
            } }, .php_value);
        }

        if (func_name.len != 0 and indirect_callee == null and std.mem.eql(u8, func_name, "compact")) {
            var can_lower_compact = true;
            for (call_data.args) |arg_idx| {
                const arg_node = self.getNode(arg_idx) orelse {
                    can_lower_compact = false;
                    break;
                };
                if (arg_node.tag != .literal_string) {
                    can_lower_compact = false;
                    break;
                }
            }

            if (can_lower_compact) {
                const result_arr = try self.emitWithResult(.{ .array_new = .{ .capacity = @intCast(call_data.args.len) } }, .php_array);
                const module = self.module orelse return result_arr;

                for (call_data.args) |arg_idx| {
                    const arg_node = self.getNode(arg_idx).?;
                    const compact_name = self.getString(arg_node.data.literal_string.value);
                    const key_id = try module.internString(compact_name);
                    const key_reg = try self.emitWithResult(.{ .const_string = key_id }, .php_string);

                    const lookup_name = if (compact_name.len > 0 and compact_name[0] == '$')
                        compact_name
                    else
                        try std.fmt.allocPrint(self.allocator, "${s}", .{compact_name});
                    defer if (lookup_name.ptr != compact_name.ptr) self.allocator.free(lookup_name);

                    const value_reg = if (self.lookupVarRegister(lookup_name)) |ptr_reg| blk: {
                        const ptr_type = ptr_reg.type_;
                        const pointed_type = if (ptr_type == .ptr) ptr_type.ptr.* else .php_value;
                        break :blk try self.emitWithResult(.{ .load = .{ .ptr = ptr_reg, .type_ = pointed_type } }, pointed_type);
                    } else blk: {
                        break :blk try self.emitWithResult(.{ .global_get = .{ .name = lookup_name } }, .php_value);
                    };

                    _ = try self.emit(.{ .array_set = .{
                        .array = result_arr,
                        .key = key_reg,
                        .value = value_reg,
                    } }, null);
                }

                return result_arr;
            }
        }

        var has_unpacking: bool = false;
        for (call_data.args) |arg_idx| {
            const arg_node = self.getNode(arg_idx) orelse continue;
            if (arg_node.tag == .unpacking_expr) {
                has_unpacking = true;
                break;
            }
        }
        if (has_unpacking) {
            const callback_reg = if (indirect_callee) |r| r else blk: {
                if (func_name.len == 0) {
                    break :blk try self.emitWithResult(.{ .const_null = {} }, .php_value);
                }
                const sid = try self.module.?.internString(func_name);
                break :blk try self.emitWithResult(.{ .const_string = sid }, .php_value);
            };

            const args_arr = try self.emitWithResult(.{ .array_new = .{ .capacity = @intCast(call_data.args.len) } }, .php_array);

            for (call_data.args) |arg_idx| {
                const arg_node = self.getNode(arg_idx) orelse continue;
                if (arg_node.tag == .unpacking_expr) {
                    const spread_reg = try self.generateExpression(arg_node.data.unpacking_expr.expr);
                    const spread_args = try self.allocator.alloc(Register, 2);
                    spread_args[0] = args_arr;
                    spread_args[1] = spread_reg;
                    _ = try self.emit(.{ .call = .{ .func_name = "php_args_append_spread", .args = spread_args, .return_type = .php_value } }, null);
                    continue;
                }

                const expr_idx = if (arg_node.tag == .named_arg) arg_node.data.named_arg.value else arg_idx;
                const val_reg = try self.generateExpression(expr_idx);
                _ = try self.emit(.{ .array_push = .{ .array = args_arr, .value = val_reg } }, null);
            }

            const invoke_args = try self.allocator.alloc(Register, 2);
            invoke_args[0] = callback_reg;
            invoke_args[1] = args_arr;
            return self.emitWithResult(.{ .call = .{ .func_name = "php_invoke_callable_args_array", .args = invoke_args, .return_type = .php_value } }, .php_value);
        }

        // isset($obj->prop)：需要调用 php_object_isset 以触发 __isset 魔法方法
        if (func_name.len != 0 and indirect_callee == null and std.mem.eql(u8, func_name, "isset")) {
            if (call_data.args.len >= 1) {
                const arg_idx = call_data.args[0];
                const arg_node = self.getNode(arg_idx);
                if (arg_node != null and arg_node.?.tag == .property_access) {
                    const object_reg = try self.generateExpression(arg_node.?.data.property_access.target);
                    const property_name_reg = try self.emitPropertyNameValue(self.getString(arg_node.?.data.property_access.property_name));
                    const isset_args = try self.allocator.alloc(Register, 2);
                    isset_args[0] = object_reg;
                    isset_args[1] = property_name_reg;
                    return self.emitWithResult(.{ .call = .{
                        .func_name = "php_object_isset",
                        .args = isset_args,
                        .return_type = .php_value,
                    } }, .php_value);
                }
            }
        }

        // unset($arr[$key])：这是语言结构而非真实函数，AOT 需要生成 array_unset 指令
        // 这里只做最小覆盖：单参数且为 array_access，并且带 index。
        if (func_name.len != 0 and indirect_callee == null and std.mem.eql(u8, func_name, "unset")) {
            var unset_handled = false;
            for (call_data.args) |arg_idx| {
                const arg_node = self.getNode(arg_idx);
                if (arg_node != null) {
                    if (arg_node.?.tag == .array_access) {
                        const access = arg_node.?.data.array_access;
                        if (access.index) |key_idx| {
                            const array_reg = try self.generateExpression(access.target);
                            const key_reg = try self.generateExpression(key_idx);
                            _ = try self.emit(.{ .array_unset = .{ .array = array_reg, .key = key_reg } }, null);
                            unset_handled = true;
                            continue;
                        }
                    } else if (arg_node.?.tag == .property_access) {
                        const object_reg = try self.generateExpression(arg_node.?.data.property_access.target);
                        const property_name_reg = try self.emitPropertyNameValue(self.getString(arg_node.?.data.property_access.property_name));
                        const unset_args = try self.allocator.alloc(Register, 2);
                        unset_args[0] = object_reg;
                        unset_args[1] = property_name_reg;
                        _ = try self.emit(.{ .call = .{
                            .func_name = "php_object_unset",
                            .args = unset_args,
                            .return_type = .php_value,
                        } }, null);
                        unset_handled = true;
                        continue;
                    } else if (arg_node.?.tag == .variable_property_access) {
                        const object_reg = try self.generateExpression(arg_node.?.data.variable_property_access.target);
                        const property_name_reg = try self.generateExpression(arg_node.?.data.variable_property_access.prop_variable);
                        const unset_args = try self.allocator.alloc(Register, 2);
                        unset_args[0] = object_reg;
                        unset_args[1] = property_name_reg;
                        _ = try self.emit(.{ .call = .{
                            .func_name = "php_object_unset",
                            .args = unset_args,
                            .return_type = .php_value,
                        } }, null);
                        unset_handled = true;
                        continue;
                    } else if (arg_node.?.tag == .variable) {
                        // unset($var)
                        const var_name = self.getString(arg_node.?.data.variable.name);

                        // 优先检查是否在var_registers中（局部变量）
                        if (self.getVarRegister(var_name)) |var_reg| {
                            if (self.isRefVar(var_name)) {
                                // 引用变量：移除引用
                                // 从ref_vars中移除
                                for (self.ref_vars.items, 0..) |ref_name, i| {
                                    if (std.mem.eql(u8, ref_name, var_name)) {
                                        _ = self.ref_vars.swapRemove(i);
                                        break;
                                    }
                                }
                                self.removeVarRegister(var_name);
                            } else {
                                // 局部变量：使用unset_var指令
                                // 生成unset_var指令，它会：
                                // 1. release变量两次（抵消store的retain + 真正的unset）
                                // 2. 设置变量为null
                                _ = try self.emit(.{ .unset_var = .{ .operand = var_reg } }, null);
                            }
                        } else {
                            // 不在var_registers中，是全局变量
                            const str_id = try self.module.?.internString(var_name);
                            const var_name_str = try self.emitWithResult(.{ .const_string = str_id }, .php_string);
                            _ = try self.emit(.{ .global_unset = .{ .name = var_name_str } }, null);
                        }

                        unset_handled = true;
                        continue;
                    }
                }
            }
            if (unset_handled) {
                return try self.emitWithResult(.{ .const_null = {} }, .php_value);
            }
        }

        // Generate arguments (positional + named)
        var has_named: bool = false;
        var positional_args = std.ArrayListUnmanaged(Node.Index){};
        defer positional_args.deinit(self.allocator);
        var named_args = std.StringHashMapUnmanaged(Node.Index){};
        defer named_args.deinit(self.allocator);

        for (call_data.args) |arg_idx| {
            const arg_node = self.getNode(arg_idx) orelse continue;
            if (arg_node.tag == .named_arg) {
                has_named = true;
                const arg_name = self.getString(arg_node.data.named_arg.name);
                try named_args.put(self.allocator, arg_name, arg_node.data.named_arg.value);
            } else {
                try positional_args.append(self.allocator, arg_idx);
            }
        }

        var args: []Register = &[_]Register{};

        // 记录需要写回的全局变量（用于引用参数）
        var ref_writebacks = std.ArrayListUnmanaged(struct { var_name: []const u8, temp_reg: Register }){};
        defer ref_writebacks.deinit(self.allocator);

        const func_symbol = if (func_name.len > 0) self.symbol_table.lookupFunction(func_name) else null;
        // 命名参数重排序：优先使用 symbol_table，回退到 IR module 中的函数参数信息
        const module_func_params: ?[]const IR.Parameter = blk: {
            if (func_symbol != null and func_symbol.?.metadata == .function) break :blk null; // symbol_table 已有
            if (self.module) |mod| {
                for (mod.functions.items) |f| {
                    if (std.mem.eql(u8, f.name, func_name)) {
                        break :blk f.params.items;
                    }
                }
            }
            break :blk null;
        };
        if (has_named and indirect_callee == null and
            ((func_symbol != null and func_symbol.?.metadata == .function) or module_func_params != null))
        {
            // 使用 symbol_table 或 module 中的参数信息
            const use_symbol = func_symbol != null and func_symbol.?.metadata == .function;
            const param_count = if (use_symbol) func_symbol.?.metadata.function.params.len else module_func_params.?.len;
            var final_args = std.ArrayListUnmanaged(Register){};
            defer final_args.deinit(self.allocator);
            try final_args.ensureTotalCapacity(self.allocator, param_count + positional_args.items.len);

            var pos_i: usize = 0;
            for (0..param_count) |pi| {
                // 从 symbol_table 或 module 获取参数名和引用标志
                const raw_name: []const u8 = if (use_symbol) func_symbol.?.metadata.function.params[pi].name else module_func_params.?[pi].name;
                const p_is_ref: bool = if (use_symbol) func_symbol.?.metadata.function.params[pi].is_reference else blk: {
                    if (self.module) |mod| {
                        for (mod.functions.items) |f| {
                            if (std.mem.eql(u8, f.name, func_name)) {
                                for (f.ref_params.items) |rp| {
                                    if (rp == pi) break :blk true;
                                }
                                break;
                            }
                        }
                    }
                    break :blk false;
                };

                // 检查是否是 variadic 参数（symbol_table 不跟踪 is_variadic，需要从 module 获取）
                const p_is_variadic: bool = blk: {
                    if (module_func_params) |mfp| {
                        if (pi < mfp.len) break :blk mfp[pi].is_variadic;
                    }
                    if (self.module) |mod| {
                        for (mod.functions.items) |f| {
                            if (std.mem.eql(u8, f.name, func_name) and pi < f.params.items.len) {
                                break :blk f.params.items[pi].is_variadic;
                            }
                        }
                    }
                    break :blk false;
                };

                var chosen: ?Node.Index = null;
                const p_name = if (raw_name.len > 0 and raw_name[0] == '$') raw_name[1..] else raw_name;
                if (named_args.get(p_name)) |named_idx| {
                    chosen = named_idx;
                } else if (pos_i < positional_args.items.len) {
                    chosen = positional_args.items[pos_i];
                    pos_i += 1;
                }

                // 对 variadic 参数的命名参数：构建完整的关联数组作为 variadic 数组
                // PHP: func(context: val) + ...$context → $context = ['context' => val]
                // 遍历所有未消耗的 named_args，用 string key 收集到一个数组
                if (chosen != null and p_is_variadic) {
                    const arr_reg = try self.emitWithResult(.{ .array_new = .{ .capacity = @intCast(named_args.count()) } }, .php_value);
                    // 先添加匹配到的参数
                    const val_reg = try self.generateExpression(chosen.?);
                    const key_id = try self.module.?.internString(p_name);
                    const key_reg = try self.emitWithResult(.{ .const_string = key_id }, .php_value);
                    _ = try self.emit(.{ .array_set = .{ .array = arr_reg, .key = key_reg, .value = val_reg } }, null);
                    // 添加其余未消耗的 named_args
                    var named_it = named_args.iterator();
                    while (named_it.next()) |entry| {
                        if (std.mem.eql(u8, entry.key_ptr.*, p_name)) continue; // 已添加
                        const other_val = try self.generateExpression(entry.value_ptr.*);
                        const other_key_id = try self.module.?.internString(entry.key_ptr.*);
                        const other_key_reg = try self.emitWithResult(.{ .const_string = other_key_id }, .php_value);
                        _ = try self.emit(.{ .array_set = .{ .array = arr_reg, .key = other_key_reg, .value = other_val } }, null);
                    }
                    // 传入预构建的关联数组作为 variadic 参数的值
                    // 使用 store 直接写入 variadic 参数的 alloca（跳过收集器）
                    try final_args.append(self.allocator, arr_reg);
                    // 标记此函数调用有命名 variadic 参数
                    break; // variadic 是最后一个参数，终止循环
                }

                if (chosen) |expr_idx| {
                    if (p_is_ref) {
                        const chosen_node = self.getNode(expr_idx);
                        if (chosen_node != null and chosen_node.?.tag == .variable) {
                            const var_name = self.getString(chosen_node.?.data.variable.name);

                            // 检查是否是全局变量或main函数中的变量
                            const is_global = self.global_vars.contains(var_name);
                            const is_main = if (self.current_function) |func|
                                std.mem.eql(u8, func.name, "__main__")
                            else
                                false;

                            if (is_global or is_main) {
                                // 创建临时volatile alloca
                                const temp_var_name = try std.fmt.allocPrint(self.allocator, "__ref_temp_{s}", .{var_name});

                                const func = self.current_function orelse return error.NoCurrentFunction;
                                const alloca_type = Type{ .php_value = {} };
                                const type_ptr = try self.allocator.create(Type);
                                type_ptr.* = alloca_type;
                                const ptr_type = Type{ .ptr = type_ptr };
                                const temp_reg = func.newRegister(ptr_type);

                                // 创建no_optimize alloca
                                const alloca_inst = try self.allocator.create(Instruction);
                                alloca_inst.* = .{
                                    .result = temp_reg,
                                    .op = .{ .alloca = .{ .type_ = alloca_type, .count = 1, .no_optimize = true } },
                                    .location = self.current_location,
                                };
                                try self.entry_allocas.append(self.allocator, alloca_inst);
                                try self.putVarRegister(temp_var_name, temp_reg);

                                // Load全局变量并store到临时变量
                                const load_reg = try self.emitWithResult(.{ .global_get = .{ .name = var_name } }, .php_value);
                                _ = try self.emit(.{ .store = .{ .ptr = temp_reg, .value = load_reg } }, null);

                                // 创建引用
                                const r = try self.emitWithResult(.{ .make_ref = .{ .ptr = temp_reg } }, .php_value);
                                try final_args.append(self.allocator, r);
                                continue;
                            } else {
                                // 局部变量：直接使用alloca
                                const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);
                                const r = try self.emitWithResult(.{ .make_ref = .{ .ptr = var_reg } }, .php_value);
                                try final_args.append(self.allocator, r);
                                continue;
                            }
                        }
                    }
                    const r = try self.generateExpression(expr_idx);
                    try final_args.append(self.allocator, r);
                } else {
                    const r = try self.emitWithResult(.{ .const_missing = {} }, .php_value);
                    try final_args.append(self.allocator, r);
                }
            }

            while (pos_i < positional_args.items.len) : (pos_i += 1) {
                const r = try self.generateExpression(positional_args.items[pos_i]);
                try final_args.append(self.allocator, r);
            }

            args = try final_args.toOwnedSlice(self.allocator);
        } else {
            // 查找函数的引用参数信息
            const target_func = if (func_name.len > 0 and self.module != null)
                self.module.?.findFunction(func_name)
            else
                null;

            args = try self.allocator.alloc(Register, call_data.args.len);
            for (call_data.args, 0..) |arg_idx, i| {
                const arg_node = self.getNode(arg_idx);
                const expr_idx = if (arg_node != null and arg_node.?.tag == .named_arg) arg_node.?.data.named_arg.value else arg_idx;

                // 检查是否是引用参数
                const is_ref_param = if (target_func) |func| blk: {
                    for (func.ref_params.items) |ref_idx| {
                        if (ref_idx == i) break :blk true;
                    }
                    break :blk false;
                } else false;

                if (is_ref_param) {
                    // 引用参数：需要传递变量的地址
                    const expr_node = self.getNode(expr_idx);
                    if (expr_node != null and expr_node.?.tag == .variable) {
                        const var_name = self.getString(expr_node.?.data.variable.name);

                        // 检查是否是全局变量
                        const is_global = self.global_vars.contains(var_name);
                        const is_main = if (self.current_function) |func|
                            std.mem.eql(u8, func.name, "__main__")
                        else
                            false;

                        if (is_global or is_main) {
                            // 全局变量：创建临时alloca
                            const func = self.current_function orelse return error.NoCurrentFunction;
                            const alloca_type = Type.php_value;
                            const type_ptr = try self.allocator.create(Type);
                            type_ptr.* = alloca_type;
                            const ptr_type = Type{ .ptr = type_ptr };
                            const temp_reg = func.newRegister(ptr_type);

                            // 创建no_optimize alloca
                            const alloca_inst = try self.allocator.create(Instruction);
                            alloca_inst.* = .{
                                .result = temp_reg,
                                .op = .{ .alloca = .{ .type_ = alloca_type, .count = 1, .no_optimize = true } },
                                .location = self.current_location,
                            };
                            try self.entry_allocas.append(self.allocator, alloca_inst);

                            // Store当前值到temp
                            const current_val = try self.generateExpression(expr_idx);
                            _ = try self.emit(.{ .store = .{ .ptr = temp_reg, .value = current_val } }, null);

                            // 传递make_ref
                            const ref_reg = try self.emitWithResult(.{ .make_ref = .{ .ptr = temp_reg } }, .php_value);
                            args[i] = ref_reg;

                            // 记录需要写回
                            try ref_writebacks.append(self.allocator, .{ .var_name = var_name, .temp_reg = temp_reg });
                            continue;
                        }

                        // 局部变量：检查是否是引用参数
                        if (self.getVarRegister(var_name)) |var_reg| {
                            // 如果变量本身是引用参数，直接传递（不创建临时alloca）
                            if (self.reference_params.contains(var_name)) {
                                // 直接透传引用参数对应的指针，避免二次 make_ref 嵌套引用
                                args[i] = var_reg;
                                // 不需要写回，因为修改会直接反映到原始引用
                                continue;
                            }

                            const func = self.current_function orelse return error.NoCurrentFunction;

                            // 普通局部变量：创建临时alloca
                            const alloca_type = Type{ .php_value = {} };
                            const type_ptr = try self.allocator.create(Type);
                            type_ptr.* = alloca_type;
                            const ptr_type = Type{ .ptr = type_ptr };
                            const temp_reg = func.newRegister(ptr_type);

                            const alloca_inst = try self.allocator.create(Instruction);
                            alloca_inst.* = .{
                                .result = temp_reg,
                                .op = .{ .alloca = .{ .type_ = alloca_type, .count = 1, .no_optimize = true } },
                                .location = self.current_location,
                            };
                            try self.entry_allocas.append(self.allocator, alloca_inst);

                            // Store当前值到temp
                            _ = try self.emit(.{ .store = .{ .ptr = temp_reg, .value = var_reg } }, null);

                            // 传递make_ref
                            const ref_reg = try self.emitWithResult(.{ .make_ref = .{ .ptr = temp_reg } }, .php_value);
                            args[i] = ref_reg;

                            // 记录需要写回
                            try ref_writebacks.append(self.allocator, .{ .var_name = var_name, .temp_reg = temp_reg });
                            continue;
                        }
                    }
                }

                // 特殊处理：preg_match/preg_match_all的第3个参数（引用参数）
                // 跳过生成，避免对未定义变量的global_get警告
                if (i == 2 and (std.mem.eql(u8, func_name, "preg_match") or std.mem.eql(u8, func_name, "preg_match_all"))) {
                    // 用null占位，后续特殊处理会替换
                    args[i] = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    continue;
                }

                args[i] = try self.generateExpression(expr_idx);
            }
        }

        // Builtins with optional boolean flag: print_r($v[, $return]) / var_export($v[, $return])
        if (func_name.len != 0 and (std.mem.eql(u8, func_name, "print_r") or std.mem.eql(u8, func_name, "var_export"))) {
            if (args.len == 1) {
                const padded = try self.allocator.alloc(Register, 2);
                padded[0] = args[0];
                padded[1] = try self.emitWithResult(.{ .const_bool = false }, .bool);
                args = padded;
            }
        }

        if (func_name.len != 0 and indirect_callee == null) {
            if (std.mem.eql(u8, func_name, "strpos") or std.mem.eql(u8, func_name, "stripos") or std.mem.eql(u8, func_name, "strrpos") or std.mem.eql(u8, func_name, "strripos")) {
                if (args.len == 2) {
                    const padded = try self.allocator.alloc(Register, 3);
                    padded[0] = args[0];
                    padded[1] = args[1];
                    padded[2] = try self.emitWithResult(.{ .const_int = 0 }, .i64);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "substr")) {
                if (args.len == 2) {
                    const padded = try self.allocator.alloc(Register, 3);
                    padded[0] = args[0];
                    padded[1] = args[1];
                    padded[2] = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "trim") or std.mem.eql(u8, func_name, "ltrim") or std.mem.eql(u8, func_name, "rtrim")) {
                if (args.len == 1) {
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = args[0];
                    padded[1] = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "preg_match")) {
                // preg_match有3个参数时，第3个是引用参数matches
                if (args.len == 3) {
                    // 第3个参数需要转换为引用
                    // 获取原始参数表达式
                    const matches_arg_idx = positional_args.items[2];
                    const matches_node = self.getNode(matches_arg_idx);

                    if (matches_node != null and matches_node.?.tag == .variable) {
                        const var_name = self.getString(matches_node.?.data.variable.name);

                        // 检查是否是局部变量（在var_registers中）
                        const is_local = self.getVarRegister(var_name) != null;

                        if (!is_local) {
                            // 全局变量或未声明变量：创建临时alloca
                            const func = self.current_function orelse return error.NoCurrentFunction;
                            const alloca_type = Type{ .php_value = {} };
                            const type_ptr = try self.allocator.create(Type);
                            type_ptr.* = alloca_type;
                            const ptr_type = Type{ .ptr = type_ptr };
                            const temp_reg = func.newRegister(ptr_type);

                            const alloca_inst = try self.allocator.create(Instruction);
                            alloca_inst.* = .{
                                .result = temp_reg,
                                .op = .{ .alloca = .{ .type_ = alloca_type, .count = 1, .no_optimize = true } },
                                .location = self.current_location,
                            };
                            try self.entry_allocas.append(self.allocator, alloca_inst);

                            // 初始化为null（不读取未定义的变量）
                            const null_val = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                            _ = try self.emit(.{ .store = .{ .ptr = temp_reg, .value = null_val } }, null);

                            // 直接使用alloca指针
                            args[2] = temp_reg;

                            // 记录需要写回
                            try ref_writebacks.append(self.allocator, .{ .var_name = var_name, .temp_reg = temp_reg });
                        } else {
                            // 局部变量：获取或创建alloca
                            const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);

                            // 直接使用alloca指针（preg_match_with_matches需要*Value）
                            args[2] = var_reg;
                        }
                    }

                    // 修改函数名
                    func_name = "preg_match_with_matches";
                }
            } else if (std.mem.eql(u8, func_name, "preg_match_all")) {
                // preg_match_all有3个参数时，第3个是引用参数matches
                if (args.len >= 3) {
                    // 第3个参数需要转换为引用（与preg_match相同逻辑）
                    const matches_arg_idx = positional_args.items[2];
                    const matches_node = self.getNode(matches_arg_idx);

                    if (matches_node != null and matches_node.?.tag == .variable) {
                        const var_name = self.getString(matches_node.?.data.variable.name);
                        const is_global = self.global_vars.contains(var_name);

                        if (is_global) {
                            // 全局变量：创建临时alloca
                            const func = self.current_function orelse return error.NoCurrentFunction;
                            const alloca_type = Type{ .php_value = {} };
                            const type_ptr = try self.allocator.create(Type);
                            type_ptr.* = alloca_type;
                            const ptr_type = Type{ .ptr = type_ptr };
                            const temp_reg = func.newRegister(ptr_type);

                            const alloca_inst = try self.allocator.create(Instruction);
                            alloca_inst.* = .{
                                .result = temp_reg,
                                .op = .{ .alloca = .{ .type_ = alloca_type, .count = 1, .no_optimize = true } },
                                .location = self.current_location,
                            };
                            try self.entry_allocas.append(self.allocator, alloca_inst);

                            // 初始化为null（不读取未定义的变量）
                            const null_val = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                            _ = try self.emit(.{ .store = .{ .ptr = temp_reg, .value = null_val } }, null);

                            // 直接使用alloca指针
                            args[2] = temp_reg;

                            // 记录需要写回
                            try ref_writebacks.append(self.allocator, .{ .var_name = var_name, .temp_reg = temp_reg });
                        } else {
                            // 局部变量：获取或创建alloca
                            const var_reg = try self.getOrCreateVarRegister(var_name, .php_value);

                            // 直接使用alloca指针
                            args[2] = var_reg;
                        }
                    }
                }
            } else if (std.mem.eql(u8, func_name, "preg_grep")) {
                // preg_grep($pattern, $array, $flags = 0)
                if (args.len == 2) {
                    const padded = try self.allocator.alloc(Register, 3);
                    padded[0] = args[0];
                    padded[1] = args[1];
                    padded[2] = try self.emitWithResult(.{ .const_int = 0 }, .i64);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "explode")) {
                if (args.len == 2) {
                    const padded = try self.allocator.alloc(Register, 3);
                    padded[0] = args[0];
                    padded[1] = args[1];
                    padded[2] = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "str_replace") or std.mem.eql(u8, func_name, "str_ireplace")) {
                if (args.len == 3) {
                    const padded = try self.allocator.alloc(Register, 4);
                    padded[0] = args[0];
                    padded[1] = args[1];
                    padded[2] = args[2];
                    padded[3] = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "ucwords")) {
                if (args.len == 1) {
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = args[0];
                    padded[1] = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "str_split")) {
                if (args.len == 1) {
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = args[0];
                    padded[1] = try self.emitWithResult(.{ .const_int = 1 }, .i64);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "str_pad")) {
                if (args.len == 2) {
                    const sid_space = try self.module.?.internString(" ");
                    const padded = try self.allocator.alloc(Register, 4);
                    padded[0] = args[0];
                    padded[1] = args[1];
                    padded[2] = try self.emitWithResult(.{ .const_string = sid_space }, .php_value);
                    padded[3] = try self.emitWithResult(.{ .const_int = 1 }, .i64);
                    args = padded;
                } else if (args.len == 3) {
                    const padded = try self.allocator.alloc(Register, 4);
                    padded[0] = args[0];
                    padded[1] = args[1];
                    padded[2] = args[2];
                    padded[3] = try self.emitWithResult(.{ .const_int = 1 }, .i64);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "chunk_split")) {
                if (args.len < 3) {
                    const sid_end = try self.module.?.internString("\r\n");
                    const padded = try self.allocator.alloc(Register, 3);
                    padded[0] = if (args.len >= 1) args[0] else try self.emitWithResult(.{ .const_string = try self.module.?.internString("") }, .php_value);
                    padded[1] = if (args.len >= 2) args[1] else try self.emitWithResult(.{ .const_int = 76 }, .i64);
                    padded[2] = if (args.len >= 3) args[2] else try self.emitWithResult(.{ .const_string = sid_end }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "wordwrap")) {
                if (args.len < 4) {
                    const sid_break = try self.module.?.internString("\n");
                    const padded = try self.allocator.alloc(Register, 4);
                    padded[0] = if (args.len >= 1) args[0] else try self.emitWithResult(.{ .const_string = try self.module.?.internString("") }, .php_value);
                    padded[1] = if (args.len >= 2) args[1] else try self.emitWithResult(.{ .const_int = 75 }, .i64);
                    padded[2] = if (args.len >= 3) args[2] else try self.emitWithResult(.{ .const_string = sid_break }, .php_value);
                    padded[3] = if (args.len >= 4) args[3] else try self.emitWithResult(.{ .const_bool = false }, .bool);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "nl2br")) {
                if (args.len == 1) {
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = args[0];
                    padded[1] = try self.emitWithResult(.{ .const_bool = true }, .bool);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "strip_tags")) {
                if (args.len == 1) {
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = args[0];
                    padded[1] = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "htmlspecialchars") or std.mem.eql(u8, func_name, "htmlentities")) {
                if (args.len < 4) {
                    const sid_utf8 = try self.module.?.internString("UTF-8");
                    const padded = try self.allocator.alloc(Register, 4);
                    padded[0] = if (args.len >= 1) args[0] else try self.emitWithResult(.{ .const_string = try self.module.?.internString("") }, .php_value);
                    padded[1] = if (args.len >= 2) args[1] else try self.emitWithResult(.{ .const_int = 0 }, .i64);
                    padded[2] = if (args.len >= 3) args[2] else try self.emitWithResult(.{ .const_string = sid_utf8 }, .php_value);
                    padded[3] = if (args.len >= 4) args[3] else try self.emitWithResult(.{ .const_bool = true }, .bool);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "htmlspecialchars_decode")) {
                if (args.len == 1) {
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = args[0];
                    padded[1] = try self.emitWithResult(.{ .const_int = 0 }, .i64);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "number_format")) {
                if (args.len < 4) {
                    const sid_dot = try self.module.?.internString(".");
                    const sid_comma = try self.module.?.internString(",");
                    const padded = try self.allocator.alloc(Register, 4);
                    padded[0] = if (args.len >= 1) args[0] else try self.emitWithResult(.{ .const_int = 0 }, .i64);
                    padded[1] = if (args.len >= 2) args[1] else try self.emitWithResult(.{ .const_int = 0 }, .i64);
                    padded[2] = if (args.len >= 3) args[2] else try self.emitWithResult(.{ .const_string = sid_dot }, .php_value);
                    padded[3] = if (args.len >= 4) args[3] else try self.emitWithResult(.{ .const_string = sid_comma }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "md5") or std.mem.eql(u8, func_name, "sha1") or std.mem.eql(u8, func_name, "base64_decode")) {
                if (args.len == 1) {
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = args[0];
                    padded[1] = try self.emitWithResult(.{ .const_bool = false }, .bool);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "uniqid")) {
                if (args.len < 2) {
                    const sid_empty = try self.module.?.internString("");
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = if (args.len >= 1) args[0] else try self.emitWithResult(.{ .const_string = sid_empty }, .php_value);
                    padded[1] = if (args.len >= 2) args[1] else try self.emitWithResult(.{ .const_bool = false }, .bool);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "json_decode")) {
                if (args.len == 1) {
                    const padded = try self.allocator.alloc(Register, 2);
                    padded[0] = args[0];
                    padded[1] = try self.emitWithResult(.{ .const_bool = false }, .bool);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "array_walk") or std.mem.eql(u8, func_name, "array_walk_recursive")) {
                if (args.len == 2) {
                    const padded = try self.allocator.alloc(Register, 3);
                    padded[0] = args[0];
                    padded[1] = args[1];
                    padded[2] = try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    args = padded;
                }
            } else if (std.mem.eql(u8, func_name, "array_splice")) {
                // array_splice(array &$array, int $offset, ?int $length = null, mixed $replacement = []): array
                if (args.len < 4) {
                    const padded = try self.allocator.alloc(Register, 4);
                    padded[0] = if (args.len >= 1) args[0] else try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    padded[1] = if (args.len >= 2) args[1] else try self.emitWithResult(.{ .const_int = 0 }, .i64);
                    padded[2] = if (args.len >= 3) args[2] else try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    padded[3] = if (args.len >= 4) args[3] else try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    args = padded;
                }
            }
        }

        if (indirect_callee) |callee_reg| {
            return self.emitWithResult(.{ .call_indirect = .{
                .func_ptr = callee_reg,
                .args = args,
                .return_type = .php_value,
            } }, .php_value);
        }

        const result = try self.emitWithResult(.{ .call = .{
            .func_name = func_name,
            .args = args,
            .return_type = .php_value,
        } }, .php_value);

        // 引用参数写回
        for (ref_writebacks.items) |wb| {
            const new_val = try self.emitWithResult(.{ .load = .{ .ptr = wb.temp_reg, .type_ = .php_value } }, .php_value);

            // 检查是否是局部变量
            if (self.getVarRegister(wb.var_name) != null) {
                // 局部变量：更新var_registers映射
                try self.putVarRegister(wb.var_name, new_val);
            } else {
                // 全局变量：global_set
                _ = try self.emit(.{ .global_set = .{ .name = wb.var_name, .value = new_val } }, null);
            }
        }

        return result;
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
        const short_class_name = self.getString(call_data.class_name);
        const method_name = self.getString(call_data.method_name);

        // ✅ 解析类名（处理命名空间、别名）
        const class_name = try self.resolveClassName(short_class_name);

        // Generate arguments
        const args = try self.allocator.alloc(Register, call_data.args.len);
        for (call_data.args, 0..) |arg_idx, i| {
            args[i] = try self.generateExpression(arg_idx);
        }

        return self.emitWithResult(.{ .static_method_call = .{
            .class_name = class_name,
            .method_name = method_name,
            .args = args,
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

            if (elem_node.tag == .unpacking_expr) {
                // Spread operator: [...$arr]
                const spread_arr_reg = try self.generateExpression(elem_node.data.unpacking_expr.expr);
                const args = try self.allocator.alloc(Register, 2);
                args[0] = arr_reg;
                args[1] = spread_arr_reg;
                _ = try self.emit(.{ .call = .{
                    .func_name = "php_array_merge_into",
                    .args = args,
                    .return_type = .php_value,
                } }, null);
            } else if (elem_node.tag == .array_pair) {
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

    /// Generate IR for anonymous class
    fn generateAnonymousClass(self: *Self, node: *const Node) !Register {
        const anon_data = node.data.anonymous_class;

        // 生成唯一类名
        const anon_class_name_temp = try std.fmt.allocPrint(self.allocator, "anonymous_class_{d}", .{self.module.?.next_anon_class_id});
        defer self.allocator.free(anon_class_name_temp);
        self.module.?.next_anon_class_id += 1;

        // Intern字符串以确保生命周期
        const anon_class_name_sid = try self.module.?.internString(anon_class_name_temp);
        const anon_class_name = self.module.?.getString(anon_class_name_sid) orelse return error.StringNotFound;

        // 收集成员元数据
        var methods = std.ArrayListUnmanaged(TypeDef.Method){};
        var properties = std.ArrayListUnmanaged(TypeDef.Property){};

        // 解析父类名称
        const parent_name: ?[]const u8 = if (anon_data.extends) |ext_idx| blk: {
            const ext_node = self.getNode(ext_idx) orelse break :blk null;
            const parent_short = switch (ext_node.tag) {
                .named_type => self.getString(ext_node.data.named_type.name),
                .variable => self.getString(ext_node.data.variable.name),
                else => break :blk null,
            };
            break :blk try self.resolveClassName(parent_short);
        } else null;

        // 解析接口名称
        var iface_list = std.ArrayListUnmanaged([]const u8){};
        defer iface_list.deinit(self.allocator);
        for (anon_data.implements) |impl_idx| {
            const impl_node = self.getNode(impl_idx) orelse continue;
            if (impl_node.tag == .named_type) {
                const iname = self.getString(impl_node.data.named_type.name);
                try iface_list.append(self.allocator, try self.resolveClassName(iname));
            }
        }
        const interfaces_slice = try iface_list.toOwnedSlice(self.allocator);

        // 创建类型定义
        const type_def = try self.allocator.create(TypeDef);
        type_def.* = .{
            .name = anon_class_name,
            .kind = .class,
            .parent = parent_name,
            .interfaces = interfaces_slice,
            .traits = &.{},
            .trait_adaptations = &.{},
            .properties = &.{},
            .methods = &.{},
            .constants = &.{},
            .location = self.current_location,
        };

        // 注册类
        if (self.module) |module| {
            try module.addTypeDef(type_def);
        }
        try self.symbol_table.defineClass(anon_class_name, type_def.parent, interfaces_slice, self.current_location);

        // 进入类作用域，设置 current_class 使 parent:: 可用
        const prev_class = self.current_class;
        self.current_class = anon_class_name;
        _ = try self.symbol_table.enterScope(.class, anon_class_name);
        defer {
            self.symbol_table.leaveScope();
            self.current_class = prev_class;
        }

        // 处理成员：收集元数据并生成IR
        for (anon_data.members) |member_idx| {
            const member = self.getNode(member_idx) orelse continue;
            switch (member.tag) {
                .method_decl => {
                    try methods.append(self.allocator, self.getMethodMeta(member));
                    try self.generateMethodDecl(member, anon_class_name);
                },
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
                    try self.generatePropertyDecl(member, anon_class_name);
                },
                else => {},
            }
        }

        // 更新TypeDef的方法和属性
        type_def.methods = try methods.toOwnedSlice(self.allocator);
        type_def.properties = try properties.toOwnedSlice(self.allocator);

        // 生成构造函数参数
        var ctor_args = std.ArrayListUnmanaged(Register){};
        defer ctor_args.deinit(self.allocator);

        for (anon_data.args) |arg_idx| {
            const arg_reg = try self.generateExpression(arg_idx);
            try ctor_args.append(self.allocator, arg_reg);
        }

        // 创建对象：使用new_object指令
        const args_slice = try self.allocator.dupe(Register, ctor_args.items);
        return self.emitWithResult(.{ .new_object = .{
            .class_name = anon_class_name,
            .args = args_slice,
        } }, .{ .php_object = anon_class_name });
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
        } else if (class_node.tag == .self_expr) {
            class_name = self.getString(class_node.data.variable.name);
        } else if (class_node.tag == .parent_expr) {
            class_name = self.getString(class_node.data.variable.name);
        } else if (class_node.tag == .static_expr) {
            class_name = self.getString(class_node.data.variable.name);
        }

        var has_named: bool = false;
        var positional_args = std.ArrayListUnmanaged(Node.Index){};
        defer positional_args.deinit(self.allocator);
        var named_args = std.StringHashMapUnmanaged(Node.Index){};
        defer named_args.deinit(self.allocator);

        for (inst_data.args) |arg_idx| {
            const arg_node = self.getNode(arg_idx) orelse continue;
            if (arg_node.tag == .named_arg) {
                has_named = true;
                const arg_name = self.getString(arg_node.data.named_arg.name);
                try named_args.put(self.allocator, arg_name, arg_node.data.named_arg.value);
            } else {
                try positional_args.append(self.allocator, arg_idx);
            }
        }

        var args: []Register = &[_]Register{};
        const ctor_name = if (class_name.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}::__construct", .{class_name})
        else
            "";
        defer if (ctor_name.len > 0) self.allocator.free(ctor_name);

        const ctor_func = if (has_named and self.module != null and ctor_name.len > 0)
            self.module.?.findFunction(ctor_name)
        else
            null;

        if (has_named and ctor_func != null) {
            var final_args = std.ArrayListUnmanaged(Register){};
            defer final_args.deinit(self.allocator);
            try final_args.ensureTotalCapacity(self.allocator, ctor_func.?.params.items.len + positional_args.items.len);

            var pos_i: usize = 0;
            for (ctor_func.?.params.items, 0..) |p, param_idx| {
                if (param_idx == 0 and std.mem.eql(u8, p.name, "this")) continue;

                var chosen: ?Node.Index = null;
                const p_name = if (p.name.len > 0 and p.name[0] == '$') p.name[1..] else p.name;
                if (named_args.get(p_name)) |named_idx| {
                    chosen = named_idx;
                } else if (pos_i < positional_args.items.len) {
                    chosen = positional_args.items[pos_i];
                    pos_i += 1;
                }

                if (chosen) |expr_idx| {
                    const r = try self.generateExpression(expr_idx);
                    try final_args.append(self.allocator, r);
                } else {
                    const r = try self.emitWithResult(.{ .const_missing = {} }, .php_value);
                    try final_args.append(self.allocator, r);
                }
            }

            while (pos_i < positional_args.items.len) : (pos_i += 1) {
                const r = try self.generateExpression(positional_args.items[pos_i]);
                try final_args.append(self.allocator, r);
            }

            args = try final_args.toOwnedSlice(self.allocator);
        } else {
            args = try self.allocator.alloc(Register, inst_data.args.len);
            for (inst_data.args, 0..) |arg_idx, i| {
                args[i] = try self.generateExpression(arg_idx);
            }
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

        const func_name = switch (cast_data.cast_type) {
            .cast_int => "php_cast_int",
            .cast_float => "php_cast_float",
            .cast_string => "php_cast_string",
            .cast_bool => "php_cast_bool",
            .k_array => "php_cast_array",
            .k_object => "php_cast_object",
            else => return value_reg,
        };

        const args = try self.allocator.alloc(Register, 1);
        args[0] = value_reg;
        return self.emitWithResult(.{ .call = .{
            .func_name = func_name,
            .args = args,
            .return_type = .php_value,
        } }, .php_value);
    }

    /// Generate IR for static property access
    fn generateStaticPropertyAccess(self: *Self, node: *const Node) !Register {
        const access_data = node.data.static_property_access;
        var class_name = self.getString(access_data.class_name);
        const prop_name = self.getString(access_data.property_name);

        // 解析特殊类名
        // self:: → 编译时解析为定义类（不需要 LSB）
        // static:: → 保留，运行时通过 getCurrentCalledClass() 解析（LSB）
        // parent:: → 保留，运行时解析
        if (std.mem.eql(u8, class_name, "self")) {
            if (self.current_class) |cls| {
                class_name = cls;
            }
        }

        return self.emitWithResult(.{ .static_property_get = .{
            .class_name = class_name,
            .property_name = prop_name,
        } }, .php_value);
    }

    /// Generate IR for class constant access
    fn generateClassConstantAccess(self: *Self, node: *const Node) !Register {
        const access_data = node.data.class_constant_access;
        const class_name_id = access_data.class_name;
        const const_name_id = access_data.constant_name;

        const class_name = self.getString(class_name_id);
        const const_name = self.getString(const_name_id);

        // 特殊处理 ClassName::class → 返回类名字符串
        if (std.mem.eql(u8, const_name, "class")) {
            // static::class → 运行时 LSB 解析
            if (std.mem.eql(u8, class_name, "static")) {
                return self.emitWithResult(.{ .call = .{
                    .func_name = "php_get_called_class_name",
                    .args = &.{},
                    .return_type = .php_value,
                } }, .php_value);
            }
            const resolved = try self.resolveClassName(class_name);
            const str_id = try self.module.?.internString(resolved);
            return self.emitWithResult(.{ .const_string = str_id }, .php_string);
        }

        // 优化：O(1) 哈希表查找 + 编译时内联
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}::{s}", .{ class_name, const_name }) catch {
            // 回退：运行时查找
            return self.emitWithResult(.{ .static_property_get = .{
                .class_name = class_name,
                .property_name = const_name,
            } }, .php_value);
        };

        if (self.constant_cache.get(key)) |const_value| {
            // 直接内联常量值，零运行时开销
            return switch (const_value) {
                .int => |v| self.emitWithResult(.{ .const_int = v }, .i64),
                .float => |v| self.emitWithResult(.{ .const_float = v }, .f64),
                .string => |s| blk: {
                    const str_id = try self.module.?.internString(s);
                    break :blk self.emitWithResult(.{ .const_string = str_id }, .php_string);
                },
                .bool => |b| self.emitWithResult(.{ .const_bool = b }, .bool),
                .null => self.emitWithResult(.{ .const_null = {} }, .php_value),
            };
        }

        // 回退：运行时查找（用于动态类或未找到的常量）
        return self.emitWithResult(.{ .static_property_get = .{
            .class_name = class_name,
            .property_name = const_name,
        } }, .php_value);
    }

    /// 递归展开 use() 中逗号分隔的捕获节点（binary_expr → 叶子节点）
    fn flattenCaptureNode(self: *Self, idx: Node.Index, out: *std.ArrayListUnmanaged(Node.Index)) !void {
        const n = self.getNode(idx) orelse return;
        if (n.tag == .binary_expr) {
            try self.flattenCaptureNode(n.data.binary_expr.lhs, out);
            try self.flattenCaptureNode(n.data.binary_expr.rhs, out);
        } else {
            try out.append(self.allocator, idx);
        }
    }

    /// Generate IR for closure
    fn generateClosure(self: *Self, node: *const Node) !Register {
        const closure_data = node.data.closure;

        // 1. Capture variables from parent scope (keep indices dense, handle &capture)
        var cap_names = std.ArrayListUnmanaged([]const u8){};
        defer cap_names.deinit(self.allocator);
        var captures = std.ArrayListUnmanaged(Register){};
        defer captures.deinit(self.allocator);
        var cap_by_ref = std.ArrayListUnmanaged(bool){};
        defer cap_by_ref.deinit(self.allocator);

        if (self.current_has_this_param) {
            if (self.getVarRegister("$this")) |this_ptr_reg| {
                const this_val = try self.emitWithResult(.{ .load = .{ .ptr = this_ptr_reg, .type_ = .php_value } }, .php_value);
                try captures.append(self.allocator, this_val);
                try cap_names.append(self.allocator, "$this");
                try cap_by_ref.append(self.allocator, false);
            }
        }

        // 收集所有捕获节点索引（展开逗号分隔的 binary_expr）
        var flat_cap_indices = std.ArrayListUnmanaged(Node.Index){};
        defer flat_cap_indices.deinit(self.allocator);
        for (closure_data.captures) |cap_idx| {
            try self.flattenCaptureNode(cap_idx, &flat_cap_indices);
        }

        for (flat_cap_indices.items) |cap_idx| {
            const cap_node = self.getNode(cap_idx) orelse continue;

            var var_name: []const u8 = undefined;
            var by_ref: bool = false;

            switch (cap_node.tag) {
                .variable => {
                    var_name = self.getString(cap_node.data.variable.name);
                },
                .unary_expr => {
                    if (cap_node.data.unary_expr.op == .ampersand) {
                        const inner = self.getNode(cap_node.data.unary_expr.expr) orelse continue;
                        if (inner.tag == .variable) {
                            var_name = self.getString(inner.data.variable.name);
                            by_ref = true;
                        } else {
                            continue;
                        }
                    } else {
                        continue;
                    }
                },
                else => continue,
            }

            // Get from parent scope
            if (by_ref) {
                if (self.getVarRegister(var_name)) |ptr_reg| {
                    const ref_reg = try self.emitWithResult(.{ .make_ref = .{ .ptr = ptr_reg } }, .php_value);
                    try captures.append(self.allocator, ref_reg);
                    try cap_names.append(self.allocator, var_name);
                    try cap_by_ref.append(self.allocator, true);
                } else {
                    // 局部作用域中变量尚不存在（如闭包自引用 use(&$factorial)）时，
                    // 预创建 alloca + null；若该名字已在 __main__/global 集合中，
                    // 则先从全局表读取当前值，确保 use(&$globalVar) 绑定到正确初值。
                    const pre_ptr = try self.getOrCreateVarRegister(var_name, .php_value);
                    const init_reg = if (self.global_vars.contains(var_name))
                        try self.emitWithResult(.{ .global_get = .{ .name = var_name } }, .php_value)
                    else
                        try self.emitWithResult(.{ .const_null = {} }, .php_value);
                    _ = try self.emit(.{ .store = .{ .ptr = pre_ptr, .value = init_reg } }, null);
                    const ref_reg = try self.emitWithResult(.{ .make_ref = .{ .ptr = pre_ptr } }, .php_value);
                    try captures.append(self.allocator, ref_reg);
                    try cap_names.append(self.allocator, var_name);
                    try cap_by_ref.append(self.allocator, true);
                }
            } else {
                var val_reg: Register = undefined;
                if (self.getVarRegister(var_name)) |ptr_reg| {
                    val_reg = try self.emitWithResult(.{ .load = .{ .ptr = ptr_reg, .type_ = .php_value } }, .php_value);
                } else {
                    // 变量可能是 __main__ 中的全局变量，从全局表读取
                    val_reg = try self.emitWithResult(.{ .global_get = .{ .name = var_name } }, .php_value);
                }
                try captures.append(self.allocator, val_reg);
                try cap_names.append(self.allocator, var_name);
                try cap_by_ref.append(self.allocator, false);
            }
        }

        // Create anonymous function (must be globally unique within the generated Zig compilation unit)
        const unique_id: usize = if (self.module) |m| m.functions.items.len else 0;
        var buf: [64]u8 = undefined;
        const func_name = std.fmt.bufPrint(&buf, "__closure_{d}", .{unique_id}) catch "__closure";
        const name_copy = try self.allocator.dupe(u8, func_name);

        const func = try self.allocator.create(Function);
        func.* = Function.init(self.allocator, name_copy);
        func.name_owned = true; // 标记name需要释放
        func.location = self.current_location;

        if (self.module) |module| {
            try module.addFunction(func);
        }

        // Generate closure body in new context
        const prev_function = self.current_function;
        const prev_block = self.current_block;
        const prev_var_registers = self.var_registers;
        const prev_global_vars = self.global_vars;
        const prev_has_this = self.current_has_this_param;

        self.current_function = func;
        self.var_registers = .{};
        self.global_vars = .{};
        self.current_has_this_param = false;

        const entry = try func.createBlock("entry");
        self.setCurrentBlock(entry);

        // Process parameters
        try self.generateParameters(closure_data.params);

        // Process captures (inject into local scope)
        for (cap_names.items, 0..) |var_name, i| {
            const is_ref = if (i < cap_by_ref.items.len) cap_by_ref.items[i] else false;
            const capture_val = try self.emitWithResult(.{ .capture_get = .{ .index = @intCast(i), .name = var_name, .by_ref = is_ref } }, .php_value);
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
        self.global_vars.deinit(self.allocator);
        self.global_vars = prev_global_vars;
        self.current_function = prev_function;
        self.current_block = prev_block;
        self.current_has_this_param = prev_has_this;

        // Return callable reference
        // Create array for captures
        const caps_arr_reg = try self.emitWithResult(.{ .array_new = .{ .capacity = @intCast(captures.items.len) } }, .php_array);

        for (captures.items) |cap_reg| {
            _ = try self.emit(.{ .array_push = .{ .array = caps_arr_reg, .value = cap_reg } }, null);
        }

        // Closure name
        const name_id = try self.module.?.internString(name_copy);
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

        // Arrow functions are similar to closures but with implicit return and auto-capture.
        // For parity with the interpreter implementation, capture all visible locals from the parent scope.
        var cap_names = std.ArrayListUnmanaged([]const u8){};
        defer cap_names.deinit(self.allocator);
        var captures = std.ArrayListUnmanaged(Register){};
        defer captures.deinit(self.allocator);

        for (self.var_registers.items) |entry| {
            const var_name = entry.name;
            const ptr_reg = entry.register;
            const val_reg = try self.emitWithResult(.{ .load = .{ .ptr = ptr_reg, .type_ = .php_value } }, .php_value);
            try captures.append(self.allocator, val_reg);
            try cap_names.append(self.allocator, var_name);
        }

        const unique_id: usize = if (self.module) |m| m.functions.items.len else 0;
        var buf: [64]u8 = undefined;
        const func_name = std.fmt.bufPrint(&buf, "__arrow_{d}", .{unique_id}) catch "__arrow";
        const name_copy = try self.allocator.dupe(u8, func_name);

        const func = try self.allocator.create(Function);
        func.* = Function.init(self.allocator, name_copy);
        func.name_owned = true; // 标记name需要释放
        func.location = self.current_location;

        if (self.module) |module| {
            try module.addFunction(func);
        }

        const prev_function = self.current_function;
        const prev_block = self.current_block;
        const prev_var_registers = self.var_registers;
        const prev_global_vars = self.global_vars;
        const prev_has_this = self.current_has_this_param;

        self.current_function = func;
        self.var_registers = .{};
        self.global_vars = .{};
        self.current_has_this_param = false;

        const entry = try func.createBlock("entry");
        self.setCurrentBlock(entry);

        for (arrow_data.params) |_| {}
        try self.generateParameters(arrow_data.params);

        // Inject captures into local scope
        for (cap_names.items, 0..) |cap_name, i| {
            const capture_val = try self.emitWithResult(.{ .capture_get = .{ .index = @intCast(i), .name = cap_name } }, .php_value);
            const local_ptr = try self.getOrCreateVarRegister(cap_name, .php_value);
            _ = try self.emit(.{ .store = .{ .ptr = local_ptr, .value = capture_val } }, null);
        }

        // Arrow function body is an expression that's implicitly returned
        const result_reg = try self.generateExpression(arrow_data.body);
        self.setTerminator(.{ .ret = result_reg });

        self.var_registers.deinit(self.allocator);
        self.var_registers = prev_var_registers;
        self.global_vars.deinit(self.allocator);
        self.global_vars = prev_global_vars;
        self.current_function = prev_function;
        self.current_block = prev_block;
        self.current_has_this_param = prev_has_this;

        // Create array for captures
        const caps_arr_reg = try self.emitWithResult(.{ .array_new = .{ .capacity = @intCast(captures.items.len) } }, .php_array);
        for (captures.items) |cap_reg| {
            _ = try self.emit(.{ .array_push = .{ .array = caps_arr_reg, .value = cap_reg } }, null);
        }

        // Closure name
        const name_id = try self.module.?.internString(name_copy);
        const name_reg = try self.emitWithResult(.{ .const_string = name_id }, .php_string);

        const args = try self.allocator.alloc(Register, 2);
        args[0] = name_reg;
        args[1] = caps_arr_reg;

        return self.emitWithResult(.{ .call = .{
            .func_name = "php_create_closure",
            .args = args,
            .return_type = .php_callable,
        } }, .php_callable);
    }

    /// Generate IR for yield expression
    fn generateYieldExpr(self: *Self, node: *const Node) !Register {
        const yield_data = node.data.yield_expr;

        // Mark current function as generator
        if (self.current_function) |func| {
            func.is_generator = true;
        }

        // Generate key and value registers
        var key_reg: ?Register = null;
        var value_reg: ?Register = null;

        if (yield_data.value) |val_idx| {
            value_reg = try self.generateExpression(val_idx);
        }
        if (yield_data.key) |key_idx| {
            key_reg = try self.generateExpression(key_idx);
        }

        // Emit yield instruction; result = sent value
        return self.emitWithResult(.{ .yield_val = .{
            .key = key_reg,
            .value = value_reg,
        } }, .php_value);
    }

    /// Generate IR for yield from expression
    fn generateYieldFromExpr(self: *Self, node: *const Node) !Register {
        const expr_idx = node.data.yield_from_expr.expr;

        // Mark current function as generator
        if (self.current_function) |func| {
            func.is_generator = true;
        }

        const iterable_reg = try self.generateExpression(expr_idx);
        return self.emitWithResult(.{ .yield_from = .{
            .operand = iterable_reg,
        } }, .php_value);
    }

    /// Generate IR for match expression
    fn generateMatchExpr(self: *Self, node: *const Node) !Register {
        const match_data = node.data.match_expr;

        const subject_reg = try self.generateExpression(match_data.expression);
        const merge_block = try self.createBlock("match_merge");

        var phi_incoming = std.ArrayListUnmanaged(Instruction.PhiIncoming){};
        defer phi_incoming.deinit(self.allocator);

        // 创建检查块和 arm 块
        var check_blocks = std.ArrayListUnmanaged(*BasicBlock){};
        defer check_blocks.deinit(self.allocator);
        var arm_blocks = std.ArrayListUnmanaged(*BasicBlock){};
        defer arm_blocks.deinit(self.allocator);

        for (0..match_data.arms.len) |_| {
            try check_blocks.append(self.allocator, try self.createBlock("match_check"));
            try arm_blocks.append(self.allocator, try self.createBlock("match_arm"));
        }

        // default arm 块
        var default_block: ?*BasicBlock = null;
        if (match_data.default) |_| {
            default_block = try self.createBlock("match_default");
        }

        // 跳转到第一个检查
        self.setTerminator(.{ .br = check_blocks.items[0] });

        // 生成条件检查链
        for (match_data.arms, 0..) |arm_idx, i| {
            const arm_node = self.getNode(arm_idx) orelse continue;
            if (arm_node.tag != .match_arm) continue;
            const arm_data = arm_node.data.match_arm;

            const check_block = check_blocks.items[i];
            const arm_block = arm_blocks.items[i];

            // 在检查块中生成条件（支持多值：1, 2, 3 => ...）
            self.setCurrentBlock(check_block);

            // 下一个检查或 default
            const next_block = if (i + 1 < check_blocks.items.len)
                check_blocks.items[i + 1]
            else if (default_block) |db|
                db
            else
                merge_block;

            if (arm_data.conditions.len == 1) {
                // 单值：直接比较
                const cond_reg = try self.generateExpression(arm_data.conditions[0]);
                const match_reg = try self.emitWithResult(.{ .identical = .{
                    .lhs = subject_reg,
                    .rhs = cond_reg,
                } }, .php_value);
                self.setTerminator(.{ .cond_br = .{
                    .cond = match_reg,
                    .then_block = arm_block,
                    .else_block = next_block,
                } });
            } else {
                // 多值：生成链式检查块
                var prev_fail_block = check_block;
                for (arm_data.conditions, 0..) |cond_idx, ci| {
                    if (ci > 0) {
                        // 创建新的检查块
                        const next_check = try self.createBlock("match_multi_check");
                        self.setCurrentBlock(prev_fail_block);
                        // 上一个检查失败时跳到这里（已在setTerminator中设置）
                        self.setCurrentBlock(next_check);
                        prev_fail_block = next_check;
                    }
                    const cond_reg = try self.generateExpression(cond_idx);
                    const match_reg = try self.emitWithResult(.{ .identical = .{
                        .lhs = subject_reg,
                        .rhs = cond_reg,
                    } }, .php_value);
                    const fail_block = if (ci + 1 < arm_data.conditions.len)
                        try self.createBlock("match_multi_check") // 临时，下次循环会用
                    else
                        next_block;
                    self.setTerminator(.{ .cond_br = .{
                        .cond = match_reg,
                        .then_block = arm_block,
                        .else_block = fail_block,
                    } });
                    if (ci + 1 < arm_data.conditions.len) {
                        prev_fail_block = fail_block;
                    }
                }
            }

            // 生成 arm 体
            self.setCurrentBlock(arm_block);
            const result_reg = try self.generateExpression(arm_data.body);
            try phi_incoming.append(self.allocator, .{ .value = result_reg, .block = arm_block });
            self.setTerminator(.{ .br = merge_block });
        }

        // 生成 default arm
        if (match_data.default) |default_idx| {
            const default_node = self.getNode(default_idx) orelse return error.InvalidNode;
            if (default_node.tag != .match_arm) return error.InvalidNode;
            const default_data = default_node.data.match_arm;

            self.setCurrentBlock(default_block.?);
            const result_reg = try self.generateExpression(default_data.body);
            try phi_incoming.append(self.allocator, .{ .value = result_reg, .block = default_block.? });
            self.setTerminator(.{ .br = merge_block });
        }

        // Merge
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
            .class_constant_access => blk: {
                // 支持类常量折叠
                const access_data = node.data.class_constant_access;
                const class_name = self.getString(access_data.class_name);
                const const_name = self.getString(access_data.constant_name);

                var key_buf: [256]u8 = undefined;
                const key = std.fmt.bufPrint(&key_buf, "{s}::{s}", .{ class_name, const_name }) catch break :blk null;

                if (self.constant_cache.get(key)) |const_value| {
                    break :blk switch (const_value) {
                        .int => |v| ConstantValue{ .int_val = v },
                        .float => |v| ConstantValue{ .float_val = v },
                        .string => |s| ConstantValue{ .string_val = s },
                        .bool => |b| ConstantValue{ .bool_val = b },
                        .null => ConstantValue{ .is_null = true },
                    };
                }
                break :blk null;
            },
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
    const source_buffer = "";

    const module = try generator.generate(&nodes, &string_table, source_buffer, "test_module", "test.php");
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
