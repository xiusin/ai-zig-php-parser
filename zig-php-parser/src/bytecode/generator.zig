const std = @import("std");
const compiler = @import("compiler");
const ast = compiler.ast;
const root = compiler;
const PHPContext = compiler.PHPContext;
const Token = compiler.Token;
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;
const CompiledFunction = instruction.CompiledFunction;
const Value = instruction.Value;
const escape_analysis = compiler.escape_analysis;
const EscapeAnalyzer = escape_analysis.EscapeAnalyzer;
const StackAllocationOptimizer = escape_analysis.StackAllocationOptimizer;
const ScalarReplacementOptimizer = escape_analysis.ScalarReplacementOptimizer;
const OptimizationResult = escape_analysis.OptimizationResult;

/// 字节码生成器 - 将AST编译为字节码
/// 真正实现AST遍历和字节码生成
///
/// ## Syntax Mode Independence (Requirements 5.1, 5.2, 5.3)
///
/// The BytecodeGenerator is designed to be completely syntax-mode agnostic.
/// It operates on normalized AST nodes where:
/// - Variable names are already normalized with `$` prefix (added by Parser for Go mode)
/// - Property access nodes are structurally identical regardless of original syntax
/// - All identifiers use internal normalized names from the string pool
///
/// This design ensures that semantically equivalent code written in different
/// syntax modes (PHP or Go) produces identical bytecode sequences.
///
/// The normalization happens at the Parser level:
/// - PHP mode: `$var` -> variable node with name "$var"
/// - Go mode: `var` -> variable node with name "$var" (prefix added internally)
///
/// Therefore, the BytecodeGenerator does not need to know about syntax modes
/// and will produce identical bytecode for equivalent programs.
pub const BytecodeGenerator = struct {
    allocator: std.mem.Allocator,
    context: *PHPContext,
    instructions: std.ArrayListUnmanaged(Instruction),
    constants: std.ArrayListUnmanaged(Value),
    locals: std.StringHashMapUnmanaged(u16),
    globals: std.StringHashMapUnmanaged(u16),
    local_count: u16,
    global_count: u16,
    max_stack: u16,
    current_stack: u16,
    label_counter: u32,
    labels: std.AutoHashMapUnmanaged(u32, u32),
    pending_jumps: std.ArrayListUnmanaged(PendingJump),
    loop_stack: std.ArrayListUnmanaged(LoopContext),
    current_line: u32,
    functions: std.StringHashMapUnmanaged(*CompiledFunction),
    anon_fn_counter: u32,
    /// 逃逸分析器
    escape_analyzer: ?*EscapeAnalyzer,
    /// 栈分配优化器
    stack_optimizer: ?*StackAllocationOptimizer,
    /// 标量替换优化器
    scalar_optimizer: ?*ScalarReplacementOptimizer,
    /// 是否启用逃逸分析优化
    enable_escape_optimization: bool,
    /// AST节点到分配ID的映射
    ast_to_alloc_id: std.AutoHashMapUnmanaged(ast.Node.Index, u32),
    /// 标量替换的字段槽位映射
    scalar_field_slots: std.StringHashMapUnmanaged(u16),
    /// 是否在 foreach 循环体中（禁用 visitBlock 的栈清理）
    in_foreach_body: bool,

    const PendingJump = struct {
        instruction_index: u32,
        label_id: u32,
    };

    const LoopContext = struct {
        continue_label: u32,
        break_label: u32,
    };

    pub fn init(allocator: std.mem.Allocator, context: *PHPContext) BytecodeGenerator {
        return BytecodeGenerator{
            .allocator = allocator,
            .context = context,
            .instructions = .{},
            .constants = .{},
            .locals = .{},
            .globals = .{},
            .local_count = 0,
            .global_count = 0,
            .max_stack = 0,
            .current_stack = 0,
            .label_counter = 0,
            .labels = .{},
            .pending_jumps = .{},
            .loop_stack = .{},
            .current_line = 1,
            .functions = .{},
            .anon_fn_counter = 0,
            .escape_analyzer = null,
            .stack_optimizer = null,
            .scalar_optimizer = null,
            .enable_escape_optimization = false,
            .ast_to_alloc_id = .{},
            .scalar_field_slots = .{},
            .in_foreach_body = false,
        };
    }

    pub fn deinit(self: *BytecodeGenerator) void {
        self.instructions.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.locals.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.labels.deinit(self.allocator);
        self.pending_jumps.deinit(self.allocator);
        self.loop_stack.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.ast_to_alloc_id.deinit(self.allocator);
        self.scalar_field_slots.deinit(self.allocator);
    }

    /// 启用逃逸分析优化
    pub fn enableEscapeOptimization(self: *BytecodeGenerator, analyzer: *EscapeAnalyzer, stack_opt: *StackAllocationOptimizer, scalar_opt: *ScalarReplacementOptimizer) void {
        self.escape_analyzer = analyzer;
        self.stack_optimizer = stack_opt;
        self.scalar_optimizer = scalar_opt;
        self.enable_escape_optimization = true;
    }

    /// 禁用逃逸分析优化
    pub fn disableEscapeOptimization(self: *BytecodeGenerator) void {
        self.escape_analyzer = null;
        self.stack_optimizer = null;
        self.scalar_optimizer = null;
        self.enable_escape_optimization = false;
    }

    /// 获取编译生成的用户函数表
    pub fn getUserFunctions(self: *BytecodeGenerator) *std.StringHashMapUnmanaged(*CompiledFunction) {
        return &self.functions;
    }

    /// 检查AST节点是否可以栈分配
    fn canStackAllocateNode(self: *BytecodeGenerator, index: ast.Node.Index) bool {
        if (!self.enable_escape_optimization) return false;
        if (self.stack_optimizer) |opt| {
            if (self.ast_to_alloc_id.get(index)) |alloc_id| {
                return opt.shouldStackAllocate(alloc_id);
            }
        }
        return false;
    }

    /// 检查AST节点是否可以标量替换
    fn canScalarReplaceNode(self: *BytecodeGenerator, index: ast.Node.Index) bool {
        if (!self.enable_escape_optimization) return false;
        if (self.scalar_optimizer) |opt| {
            if (self.ast_to_alloc_id.get(index)) |alloc_id| {
                return opt.hasReplacementPlan(alloc_id);
            }
        }
        return false;
    }

    /// 获取栈分配槽位
    fn getStackSlotForNode(self: *BytecodeGenerator, index: ast.Node.Index) ?u16 {
        if (self.stack_optimizer) |opt| {
            if (self.ast_to_alloc_id.get(index)) |alloc_id| {
                return opt.getStackSlot(alloc_id);
            }
        }
        return null;
    }

    /// 获取标量替换的字段槽位
    fn getScalarFieldSlot(self: *BytecodeGenerator, index: ast.Node.Index, field_name: []const u8) ?u16 {
        if (self.scalar_optimizer) |opt| {
            if (self.ast_to_alloc_id.get(index)) |alloc_id| {
                return opt.getFieldSlot(alloc_id, field_name);
            }
        }
        return null;
    }

    /// 通过索引获取AST节点
    fn getNode(self: *BytecodeGenerator, index: ast.Node.Index) ast.Node {
        return self.context.nodes.items[index];
    }

    /// 通过StringId获取字符串
    fn getString(self: *BytecodeGenerator, string_id: ast.Node.StringId) []const u8 {
        return self.context.string_pool.keys()[string_id];
    }

    /// 创建新标签
    fn newLabel(self: *BytecodeGenerator) u32 {
        const label = self.label_counter;
        self.label_counter += 1;
        return label;
    }

    /// 放置标签（记录当前指令位置）
    fn placeLabel(self: *BytecodeGenerator, label_id: u32) !void {
        const offset: u32 = @intCast(self.instructions.items.len);
        try self.labels.put(self.allocator, label_id, offset);
    }

    /// 发射跳转指令（目标稍后解析）
    fn emitJump(self: *BytecodeGenerator, opcode: OpCode, label_id: u32) !void {
        const idx: u32 = @intCast(self.instructions.items.len);
        try self.instructions.append(self.allocator, Instruction.init(opcode, 0, 0));
        try self.pending_jumps.append(self.allocator, .{
            .instruction_index = idx,
            .label_id = label_id,
        });
    }

    /// 解析所有跳转目标
    fn resolveJumps(self: *BytecodeGenerator) !void {
        for (self.pending_jumps.items) |jump| {
            if (self.labels.get(jump.label_id)) |target| {
                self.instructions.items[jump.instruction_index].operand1 = @truncate(target);
            }
        }
        self.pending_jumps.clearRetainingCapacity();
    }

    /// 发射指令
    fn emit(self: *BytecodeGenerator, opcode: OpCode, op1: u16, op2: u16) !void {
        try self.instructions.append(self.allocator, Instruction.init(opcode, op1, op2));
    }

    /// 添加常量到常量池
    fn addConstant(self: *BytecodeGenerator, value: Value) !u16 {
        const idx: u16 = @intCast(self.constants.items.len);
        try self.constants.append(self.allocator, value);
        return idx;
    }

    /// 获取或创建局部变量槽
    fn getOrCreateLocal(self: *BytecodeGenerator, name: []const u8) !u16 {
        if (self.locals.get(name)) |idx| {
            return idx;
        }
        const idx = self.local_count;
        self.local_count += 1;
        try self.locals.put(self.allocator, name, idx);
        return idx;
    }

    /// 获取或创建全局变量槽
    fn getOrCreateGlobal(self: *BytecodeGenerator, name: []const u8) !u16 {
        if (self.globals.get(name)) |idx| {
            return idx;
        }
        const idx = self.global_count;
        self.global_count += 1;
        try self.globals.put(self.allocator, name, idx);
        return idx;
    }

    /// 获取一个编译期临时局部槽位
    fn getTempLocalSlot(self: *BytecodeGenerator, prefix: []const u8) !u16 {
        const name = try std.fmt.allocPrint(self.allocator, "__tmp_{s}_{d}", .{ prefix, self.local_count });
        defer self.allocator.free(name);
        return self.getOrCreateLocal(name);
    }

    /// 压栈计数
    fn pushStack(self: *BytecodeGenerator) void {
        self.current_stack += 1;
        if (self.current_stack > self.max_stack) {
            self.max_stack = self.current_stack;
        }
    }

    /// 弹栈计数
    fn popStack(self: *BytecodeGenerator) void {
        if (self.current_stack > 0) {
            self.current_stack -= 1;
        }
    }

    /// 编译根节点
    pub fn compile(self: *BytecodeGenerator, root_index: ast.Node.Index) !*CompiledFunction {
        const node = self.getNode(root_index);
        try self.visitNode(root_index);
        try self.emit(.ret_void, 0, 0);
        try self.resolveJumps();

        const func = try self.allocator.create(CompiledFunction);
        func.* = CompiledFunction{
            .name = "main",
            .bytecode = try self.instructions.toOwnedSlice(self.allocator),
            .constants = try self.constants.toOwnedSlice(self.allocator),
            .local_count = self.local_count,
            .arg_count = 0,
            .max_stack = self.max_stack,
            .flags = .{},
            .line_table = &[_]CompiledFunction.LineInfo{},
            .exception_table = &[_]CompiledFunction.ExceptionEntry{},
        };

        _ = node;
        return func;
    }

    /// 编译错误类型
    pub const CompileError = error{
        OutOfMemory,
        Overflow,
    };

    /// 访问AST节点 - 核心分发函数
    fn visitNode(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        switch (node.tag) {
            .root => try self.visitRoot(index),
            .block => try self.visitBlock(index),
            .echo_stmt => try self.visitEcho(index),
            .expression_stmt => try self.visitExpressionStmt(index),
            .if_stmt => try self.visitIf(index),
            .while_stmt => try self.visitWhile(index),
            .for_stmt => try self.visitFor(index),
            .foreach_stmt => try self.visitForeach(index),
            .return_stmt => try self.visitReturn(index),
            .break_stmt => try self.visitBreak(index),
            .continue_stmt => try self.visitContinue(index),
            .assignment => try self.visitAssignment(index),
            .compound_assignment => try self.visitCompoundAssignment(index),
            .binary_expr => try self.visitBinaryExpr(index),
            .unary_expr => try self.visitUnaryExpr(index),
            .literal_int => try self.visitLiteralInt(index),
            .literal_float => try self.visitLiteralFloat(index),
            .literal_string => try self.visitLiteralString(index),
            .literal_bool => try self.visitLiteralBool(index),
            .literal_null => try self.visitLiteralNull(index),
            .variable => try self.visitVariable(index),
            .function_call => try self.visitFunctionCall(index),
            .method_call => try self.visitMethodCall(index),
            .array_init => try self.visitArrayInit(index),
            .array_access => try self.visitArrayAccess(index),
            .property_access => try self.visitPropertyAccess(index),
            .object_instantiation => try self.visitNewObject(index),
            .ternary_expr => try self.visitTernary(index),
            .try_stmt => try self.visitTry(index),
            .throw_stmt => try self.visitThrow(index),
            .closure => try self.visitClosure(index),
            .arrow_function => try self.visitArrowFunction(index),
            .function_decl => try self.visitFunctionDecl(index),
            .postfix_expr => try self.visitPostfixExpr(index),
            else => {},
        }
    }

    /// 访问复合赋值语句（+=, -=, *=, /=, %=, .=）
    fn visitCompoundAssignment(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const compound_data = node.data.compound_assignment;
        const target_node = self.getNode(compound_data.target);

        // 1) 执行运算
        const opcode: OpCode = switch (compound_data.op) {
            .plus_equal => .add_int,
            .minus_equal => .sub_int,
            .asterisk_equal => .mul_int,
            .slash_equal => .div_int,
            .percent_equal => .mod_int,
            .dot_equal => .concat,
            else => .nop,
        };

        if (opcode == .nop) {
            // 不支持的复合操作符，保持与现有字节码生成兼容
            return;
        }

        switch (target_node.tag) {
            .variable => {
                // 2) 读取左值
                const var_name = self.getString(target_node.data.variable.name);
                const slot = try self.getOrCreateLocal(var_name);
                try self.emit(.push_local, slot, 0);
                self.pushStack();

                // 3) 计算右值
                try self.visitNode(compound_data.value);

                // 4) 运算并写回（保留表达式值）
                try self.emit(opcode, 0, 0);
                self.popStack(); // 二元运算净 -1
                try self.emit(.dup, 0, 0);
                self.pushStack();
                try self.emit(.store_local, slot, 0);
                self.popStack();
            },
            .array_access => {
                const access_data = target_node.data.array_access;

                const arr_slot = try self.getTempLocalSlot("arr_compound");
                const idx_slot = try self.getTempLocalSlot("idx_compound");

                // 2) 准备 array/index，并保存副本用于回写
                try self.visitNode(access_data.target); // [arr]
                if (access_data.index) |idx| {
                    try self.visitNode(idx); // [arr, idx]
                } else {
                    try self.emit(.push_null, 0, 0); // [arr, null]
                    self.pushStack();
                }

                try self.emit(.dup, 0, 0); // [arr, idx, idx]
                self.pushStack();
                try self.emit(.store_local, idx_slot, 0); // [arr, idx]
                self.popStack();

                try self.emit(.swap, 0, 0); // [idx, arr]
                try self.emit(.dup, 0, 0); // [idx, arr, arr]
                self.pushStack();
                try self.emit(.store_local, arr_slot, 0); // [idx, arr]
                self.popStack();
                try self.emit(.swap, 0, 0); // [arr, idx]

                // 3) 读取当前元素值
                try self.emit(.array_get, 0, 0); // [cur]
                self.popStack(); // array_get: 净 -1

                // 4) 计算右值并执行运算
                try self.visitNode(compound_data.value); // [cur, rhs]
                try self.emit(opcode, 0, 0); // [new]
                self.popStack(); // 二元运算净 -1

                // 5) 回写数组元素，并保留表达式值
                try self.emit(.dup, 0, 0); // [new, new]
                self.pushStack();

                try self.emit(.push_local, arr_slot, 0); // [new, new, arr]
                self.pushStack();
                try self.emit(.swap, 0, 0); // [new, arr, new]
                try self.emit(.push_local, idx_slot, 0); // [new, arr, new, idx]
                self.pushStack();
                try self.emit(.swap, 0, 0); // [new, arr, idx, new]
                try self.emit(.array_set, 0, 0); // [new, arr]
                self.popStack();
                self.popStack(); // array_set 净 -2
                try self.emit(.pop, 0, 0); // [new]
                self.popStack();
            },
            .property_access => {
                const prop_data = target_node.data.property_access;

                // 标量替换路径：字段被替换为局部槽位
                const base_node = self.getNode(prop_data.target);
                if (base_node.tag == .variable) {
                    const prop_name = self.getString(prop_data.property_name);
                    if (self.getScalarFieldSlot(prop_data.target, prop_name)) |field_slot| {
                        try self.emit(.push_local, field_slot, 0);
                        self.pushStack();
                        try self.visitNode(compound_data.value);
                        try self.emit(opcode, 0, 0);
                        self.popStack();
                        try self.emit(.dup, 0, 0);
                        self.pushStack();
                        try self.emit(.store_local, field_slot, 0);
                        self.popStack();
                        return;
                    }
                }

                const obj_slot = try self.getTempLocalSlot("obj_compound");

                // 2) 获取对象并保存副本用于 set_prop
                try self.visitNode(prop_data.target); // [obj]
                try self.emit(.dup, 0, 0); // [obj, obj]
                self.pushStack();
                try self.emit(.store_local, obj_slot, 0); // [obj]
                self.popStack();

                // 3) 读取当前属性值
                const prop_name = self.getString(prop_data.property_name);
                const prop_name_const = try self.addConstant(.{ .string_val = prop_name });
                try self.emit(.get_prop, prop_name_const, 0); // [cur]

                // 4) 计算右值并执行运算
                try self.visitNode(compound_data.value); // [cur, rhs]
                try self.emit(opcode, 0, 0); // [new]
                self.popStack();

                // 5) 回写属性并保留表达式值
                try self.emit(.dup, 0, 0); // [new, new]
                self.pushStack();
                try self.emit(.push_local, obj_slot, 0); // [new, new, obj]
                self.pushStack();
                try self.emit(.swap, 0, 0); // [new, obj, new]
                try self.emit(.set_prop, prop_name_const, 0); // [new, obj]
                self.popStack();
                try self.emit(.pop, 0, 0); // [new]
                self.popStack();
            },
            else => {
                return;
            },
        }
    }

    /// 访问根节点 - 遍历所有顶层语句
    fn visitRoot(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const stmts = node.data.root.stmts;
        for (stmts) |stmt_idx| {
            const saved_stack = self.current_stack;
            try self.visitNode(stmt_idx);
            while (self.current_stack > saved_stack) {
                try self.emit(.pop, 0, 0);
                self.popStack();
            }
        }
    }

    /// 访问代码块
    fn visitBlock(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const stmts = node.data.block.stmts;
        
        // 在 foreach 循环体中，保存初始栈深度
        const initial_stack = if (self.in_foreach_body) self.current_stack else 0;
        
        for (stmts) |stmt_idx| {
            const saved_stack = self.current_stack;
            try self.visitNode(stmt_idx);
            
            // 清理栈上多余的值
            // 但在 foreach 中，不要清理到 initial_stack 以下（保护 iterator）
            const target_stack = if (self.in_foreach_body) 
                @max(saved_stack, initial_stack)
            else 
                saved_stack;
                
            while (self.current_stack > target_stack) {
                try self.emit(.pop, 0, 0);
                self.popStack();
            }
        }
    }

    /// 访问echo语句
    fn visitEcho(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const exprs = node.data.echo_stmt.exprs;
        for (exprs) |expr_idx| {
            try self.visitNode(expr_idx);
            try self.emit(.call_builtin, 0, 1); // echo = builtin #0
        }
    }

    /// 访问表达式语句（占位符节点，无需处理）
    fn visitExpressionStmt(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        _ = self;
        _ = index;
    }

    /// 访问if语句
    fn visitIf(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const if_data = node.data.if_stmt;

        const else_label = self.newLabel();
        const end_label = self.newLabel();

        // 计算条件表达式
        try self.visitNode(if_data.condition);
        self.popStack();

        // 条件为假跳转到else
        try self.emitJump(.jz, else_label);

        // then分支
        try self.visitNode(if_data.then_branch);

        // 跳转到结束
        try self.emitJump(.jmp, end_label);

        // else标签
        try self.placeLabel(else_label);

        // else分支
        if (if_data.else_branch) |else_idx| {
            try self.visitNode(else_idx);
        }

        // 结束标签
        try self.placeLabel(end_label);
    }

    /// 访问while语句
    fn visitWhile(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const while_data = node.data.while_stmt;

        const loop_start = self.newLabel();
        const loop_end = self.newLabel();

        try self.loop_stack.append(self.allocator, .{
            .continue_label = loop_start,
            .break_label = loop_end,
        });

        // 循环开始标记（确保每次迭代都会执行）
        try self.placeLabel(loop_start);
        try self.emit(.loop_start, 0, 0);

        // 条件检查
        try self.visitNode(while_data.condition);
        self.popStack();
        try self.emitJump(.jz, loop_end);

        // 循环体
        try self.visitNode(while_data.body);

        // 跳回循环开始
        try self.emitJump(.jmp, loop_start);

        // 循环结束（确保跳转到退出点时也会执行）
        try self.placeLabel(loop_end);
        try self.emit(.loop_end, 0, 0);

        _ = self.loop_stack.pop();
    }

    /// 访问for语句
    fn visitFor(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const for_data = node.data.for_stmt;

        const loop_start = self.newLabel();
        const loop_continue = self.newLabel();
        const loop_end = self.newLabel();

        try self.loop_stack.append(self.allocator, .{
            .continue_label = loop_continue,
            .break_label = loop_end,
        });

        // 初始化
        if (for_data.init) |init_idx| {
            const saved_stack = self.current_stack;
            try self.visitNode(init_idx);
            while (self.current_stack > saved_stack) {
                try self.emit(.pop, 0, 0);
                self.popStack();
            }
        }

        try self.placeLabel(loop_start);
        try self.emit(.loop_start, 0, 0);

        // 条件
        if (for_data.condition) |cond_idx| {
            try self.visitNode(cond_idx);
            self.popStack();
            try self.emitJump(.jz, loop_end);
        }

        // 循环体
        try self.visitNode(for_data.body);

        // continue点
        try self.placeLabel(loop_continue);

        // 更新
        if (for_data.loop) |loop_idx| {
            const saved_stack = self.current_stack;
            try self.visitNode(loop_idx);
            while (self.current_stack > saved_stack) {
                try self.emit(.pop, 0, 0);
                self.popStack();
            }
        }

        try self.emitJump(.jmp, loop_start);

        try self.placeLabel(loop_end);
        try self.emit(.loop_end, 0, 0);

        _ = self.loop_stack.pop();
    }

    /// 访问foreach语句
    fn visitForeach(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const foreach_data = node.data.foreach_stmt;

        const loop_start = self.newLabel();
        const loop_end = self.newLabel();

        try self.loop_stack.append(self.allocator, .{
            .continue_label = loop_start,
            .break_label = loop_end,
        });

        // 计算可迭代对象
        try self.visitNode(foreach_data.iterable);

        // 初始化迭代器
        // 栈：[iterable] -> [iterator]
        try self.emit(.foreach_init, 0, 0);

        try self.placeLabel(loop_start);
        try self.emit(.loop_start, 0, 0);

        // 获取下一个元素
        // foreach_next 将栈从 [iterator] 变成 [iterator, key, value]
        try self.emitJump(.foreach_next, loop_end);
        
        // 现在栈上有：[iterator, key, value]
        // current_stack 应该反映这个状态
        self.current_stack += 2; // 加上 key 和 value

        // 存储 value（栈顶）
        const value_node = self.getNode(foreach_data.value);
        if (value_node.tag == .variable) {
            const value_name = self.getString(value_node.data.variable.name);
            const value_slot = try self.getOrCreateLocal(value_name);
            try self.emit(.store_local, value_slot, 0);
            self.popStack(); // value 被存储，栈：[iterator, key]
        }

        // 存储 key（如果需要）
        if (foreach_data.key) |key_idx| {
            const key_node = self.getNode(key_idx);
            if (key_node.tag == .variable) {
                const key_name = self.getString(key_node.data.variable.name);
                const key_slot = try self.getOrCreateLocal(key_name);
                try self.emit(.store_local, key_slot, 0);
                self.popStack(); // key 被存储，栈：[iterator]
            }
        } else {
            // 不需要 key，弹出它
            try self.emit(.pop, 0, 0);
            self.popStack(); // key 被弹出，栈：[iterator]
        }

        // 现在 current_stack 应该等于 base_stack（只有 iterator 在栈上）
        // 设置标志并执行循环体
        const was_in_foreach = self.in_foreach_body;
        self.in_foreach_body = true;
        
        try self.visitNode(foreach_data.body);
        
        self.in_foreach_body = was_in_foreach;

        // 跳转回循环开始
        try self.emitJump(.jmp, loop_start);

        // 循环结束标签
        try self.emit(.loop_end, 0, 0);
        try self.placeLabel(loop_end);
        
        // foreach_next 在迭代完成时已经弹出了 iterator
        // 所以我们需要更新 current_stack
        self.popStack();

        _ = self.loop_stack.pop();
    }

    /// 访问return语句
    fn visitReturn(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const return_data = node.data.return_stmt;

        if (return_data.expr) |expr_idx| {
            try self.visitNode(expr_idx);
            try self.emit(.ret, 0, 0);
        } else {
            try self.emit(.ret_void, 0, 0);
        }
    }

    /// 访问break语句
    fn visitBreak(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        _ = index;
        if (self.loop_stack.items.len > 0) {
            const loop_ctx = self.loop_stack.items[self.loop_stack.items.len - 1];
            try self.emitJump(.jmp, loop_ctx.break_label);
        }
    }

    /// 访问continue语句
    fn visitContinue(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        _ = index;
        if (self.loop_stack.items.len > 0) {
            const loop_ctx = self.loop_stack.items[self.loop_stack.items.len - 1];
            try self.emitJump(.jmp, loop_ctx.continue_label);
        }
    }

    /// 访问赋值语句
    fn visitAssignment(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const assign_data = node.data.assignment;

        // 计算右值
        try self.visitNode(assign_data.value);

        // 存储到左值
        const target_node = self.getNode(assign_data.target);
        switch (target_node.tag) {
            .variable => {
                const var_name = self.getString(target_node.data.variable.name);
                const slot = try self.getOrCreateLocal(var_name);
                try self.emit(.store_local, slot, 0);
                self.popStack();
            },
            .array_access => {
                // 数组元素赋值
                const access_data = target_node.data.array_access;
                try self.visitNode(access_data.target);
                if (access_data.index) |idx| {
                    try self.visitNode(idx);
                }
                try self.emit(.array_set, 0, 0);
                self.popStack();
                self.popStack();
                self.popStack();
            },
            .property_access => {
                // 属性赋值
                const prop_data = target_node.data.property_access;

                // 检查目标对象是否被标量替换
                const obj_node = self.getNode(prop_data.target);
                if (obj_node.tag == .variable) {
                    const prop_name = self.getString(prop_data.property_name);
                    // 尝试获取标量替换的字段槽位
                    if (self.getScalarFieldSlot(prop_data.target, prop_name)) |field_slot| {
                        // 标量替换：直接存储到局部变量
                        try self.emit(.store_local, field_slot, 0);
                        self.popStack();
                        return;
                    }
                }

                // 标准属性赋值
                try self.visitNode(prop_data.target);
                const prop_name = self.getString(prop_data.property_name);
                const name_const = try self.addConstant(.{ .string_val = prop_name });
                try self.emit(.set_prop, name_const, 0);
                self.popStack();
                self.popStack();
            },
            else => {},
        }
    }

    /// 访问二元表达式
    fn visitBinaryExpr(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const binary_data = node.data.binary_expr;

        // 短路求值：&& 和 ||
        if (binary_data.op == .double_ampersand or binary_data.op == .k_and) {
            // a && b: 如果 a 为 false，直接返回 false，不计算 b
            const end_label = self.newLabel();
            
            try self.visitNode(binary_data.lhs);
            try self.emit(.dup, 0, 0); // 复制左操作数
            self.pushStack();
            try self.emitJump(.jz, end_label); // 如果为 false，跳到结束
            
            self.popStack(); // 弹出复制的值
            try self.emit(.pop, 0, 0);
            self.popStack(); // 弹出原值
            
            try self.visitNode(binary_data.rhs);
            
            try self.placeLabel(end_label);
            return;
        }
        
        if (binary_data.op == .double_pipe or binary_data.op == .k_or) {
            // a || b: 如果 a 为 true，直接返回 true，不计算 b
            const end_label = self.newLabel();
            
            try self.visitNode(binary_data.lhs);
            try self.emit(.dup, 0, 0); // 复制左操作数
            self.pushStack();
            try self.emitJump(.jnz, end_label); // 如果为 true，跳到结束
            
            self.popStack(); // 弹出复制的值
            try self.emit(.pop, 0, 0);
            self.popStack(); // 弹出原值
            
            try self.visitNode(binary_data.rhs);
            
            try self.placeLabel(end_label);
            return;
        }

        // 计算左操作数
        try self.visitNode(binary_data.lhs);
        // 计算右操作数
        try self.visitNode(binary_data.rhs);

        // 根据操作符生成指令
        // Note: Some operators like ^, <<, >> may not be implemented in the tokenizer
        const opcode: OpCode = switch (binary_data.op) {
            .plus => .add_int,
            .minus => .sub_int,
            .asterisk => .mul_int,
            .slash => .div_int,
            .percent => .mod_int,
            .equal_equal => .eq,
            .bang_equal => .neq,
            .equal_equal_equal => .identical,
            .bang_equal_equal => .not_identical,
            .less => .lt,
            .less_equal => .le,
            .greater => .gt,
            .greater_equal => .ge,
            .spaceship => .spaceship,
            .ampersand => .bit_and,
            .pipe => .bit_or,
            .double_ampersand, .k_and => .logic_and,
            .double_pipe, .k_or => .logic_or,
            .k_xor => .logic_xor,
            .dot => .concat,
            .double_question => .coalesce,
            else => .nop,
        };

        if (opcode != .nop) {
            try self.emit(opcode, 0, 0);
            self.popStack(); // 两个操作数弹出，一个结果压入
        }
    }

    /// 访问一元表达式
    fn visitUnaryExpr(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const unary_data = node.data.unary_expr;

        // 计算操作数
        try self.visitNode(unary_data.expr);

        // 根据操作符生成指令
        const opcode: OpCode = switch (unary_data.op) {
            .minus => .neg_int,
            .bang => .logic_not,
            .plus => .nop, // +x 无操作
            else => .nop,
        };

        if (opcode != .nop) {
            try self.emit(opcode, 0, 0);
        }
    }

    /// 访问后缀表达式 (++/--)
    fn visitPostfixExpr(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const postfix_data = node.data.postfix_expr;

        const expr_node = self.getNode(postfix_data.expr);
        if (expr_node.tag == .variable) {
            const var_name = self.getString(expr_node.data.variable.name);
            const slot = try self.getOrCreateLocal(var_name);

            // 先压入原值
            try self.emit(.push_local, slot, 0);
            self.pushStack();

            // 执行自增/自减
            switch (postfix_data.op) {
                .plus_plus => try self.emit(.inc_int, slot, 0),
                .minus_minus => try self.emit(.dec_int, slot, 0),
                else => {},
            }
        }
    }

    /// 访问整数字面量
    fn visitLiteralInt(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const value = node.data.literal_int.value;

        if (value == 0) {
            try self.emit(.push_int_0, 0, 0);
        } else if (value == 1) {
            try self.emit(.push_int_1, 0, 0);
        } else {
            const const_idx = try self.addConstant(.{ .int_val = value });
            try self.emit(.push_const, const_idx, 0);
        }
        self.pushStack();
    }

    /// 访问浮点数字面量
    fn visitLiteralFloat(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const value = node.data.literal_float.value;
        const const_idx = try self.addConstant(.{ .float_val = value });
        try self.emit(.push_const, const_idx, 0);
        self.pushStack();
    }

    /// 访问字符串字面量
    fn visitLiteralString(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const string_id = node.data.literal_string.value;
        const string_val = self.getString(string_id);
        const const_idx = try self.addConstant(.{ .string_val = string_val });
        try self.emit(.push_const, const_idx, 0);
        self.pushStack();
    }

    /// 访问布尔字面量
    fn visitLiteralBool(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        if (node.main_token.tag == .k_true) {
            try self.emit(.push_true, 0, 0);
        } else {
            try self.emit(.push_false, 0, 0);
        }
        self.pushStack();
    }

    /// 访问null字面量
    fn visitLiteralNull(self: *BytecodeGenerator, _: ast.Node.Index) CompileError!void {
        try self.emit(.push_null, 0, 0);
        self.pushStack();
    }

    /// 访问变量
    fn visitVariable(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const var_name = self.getString(node.data.variable.name);

        if (self.locals.get(var_name)) |slot| {
            try self.emit(.push_local, slot, 0);
        } else if (self.globals.get(var_name)) |slot| {
            try self.emit(.push_global, slot, 0);
        } else {
            // 首次访问，创建局部变量
            const slot = try self.getOrCreateLocal(var_name);
            try self.emit(.push_local, slot, 0);
        }
        self.pushStack();
    }

    /// 访问函数调用
    fn visitFunctionCall(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const call_data = node.data.function_call;

        const name_node = self.getNode(call_data.name);
        if (name_node.tag == .variable) {
            const raw_name = self.getString(name_node.data.variable.name);
            const is_runtime_callable = raw_name.len > 0 and raw_name[0] == '$';
            if (!is_runtime_callable) {
                // 直接函数名调用：foo(...)
                var actual_arg_count: u16 = 0;
                for (call_data.args) |arg_idx| {
                    const arg_node = self.getNode(arg_idx);
                    if (arg_node.tag == .unpacking_expr) {
                        const inner_idx = arg_node.data.unpacking_expr.expr;
                        const inner_node = self.getNode(inner_idx);
                        if (inner_node.tag == .array_init) {
                            const arr = inner_node.data.array_init;
                            for (arr.elements) |item_idx| {
                                const item_node = self.getNode(item_idx);
                                if (item_node.tag == .array_pair) {
                                    try self.visitNode(item_node.data.array_pair.value);
                                } else {
                                    try self.visitNode(item_idx);
                                }
                                actual_arg_count += 1;
                            }
                            continue;
                        }
                    }
                    try self.visitNode(arg_idx);
                    actual_arg_count += 1;
                }
                const name_const = try self.addConstant(.{ .string_val = raw_name });
                try self.emit(.call, name_const, actual_arg_count);

                var i: u16 = 0;
                while (i < actual_arg_count) : (i += 1) {
                    self.popStack();
                }
                self.pushStack();
                return;
            }
        }

        // 动态可调用：($expr)(...) / $f(...) / $obj->m(...)
        try self.visitNode(call_data.name);
        var actual_arg_count: u16 = 0;
        for (call_data.args) |arg_idx| {
            const arg_node = self.getNode(arg_idx);
            if (arg_node.tag == .unpacking_expr) {
                const inner_idx = arg_node.data.unpacking_expr.expr;
                const inner_node = self.getNode(inner_idx);
                if (inner_node.tag == .array_init) {
                    const arr = inner_node.data.array_init;
                    for (arr.elements) |item_idx| {
                        const item_node = self.getNode(item_idx);
                        if (item_node.tag == .array_pair) {
                            try self.visitNode(item_node.data.array_pair.value);
                        } else {
                            try self.visitNode(item_idx);
                        }
                        actual_arg_count += 1;
                    }
                    continue;
                }
            }
            try self.visitNode(arg_idx);
            actual_arg_count += 1;
        }
        try self.emit(.closure_call, 0, actual_arg_count);

        self.popStack(); // callee
        var i: u16 = 0;
        while (i < actual_arg_count) : (i += 1) {
            self.popStack();
        }
        self.pushStack();
    }

    /// 访问方法调用
    fn visitMethodCall(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const method_data = node.data.method_call;

        // 计算对象
        try self.visitNode(method_data.target);

        // 压入参数
        for (method_data.args) |arg_idx| {
            try self.visitNode(arg_idx);
        }

        // 调用方法
        const method_name = self.getString(method_data.method_name);
        const method_name_const = try self.addConstant(.{ .string_val = method_name });
        const arg_count: u16 = @intCast(method_data.args.len);
        try self.emit(.call_method, method_name_const, arg_count);

        // 对象和参数弹出，结果压入
        self.popStack();
        for (method_data.args) |_| {
            self.popStack();
        }
        self.pushStack();
    }

    /// 访问数组初始化
    fn visitArrayInit(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const array_data = node.data.array_init;

        // 创建数组
        try self.emit(.new_array, 0, 0);
        self.pushStack();

        // 添加元素
        for (array_data.elements) |elem_idx| {
            const elem_node = self.getNode(elem_idx);
            if (elem_node.tag == .array_pair) {
                // key => value
                try self.visitNode(elem_node.data.array_pair.key);
                try self.visitNode(elem_node.data.array_pair.value);
                try self.emit(.array_set, 0, 0);
                self.popStack();
                self.popStack();
            } else {
                // 只有value
                try self.visitNode(elem_idx);
                try self.emit(.array_push, 0, 0);
                self.popStack();
            }
        }
    }

    /// 访问数组访问
    fn visitArrayAccess(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const access_data = node.data.array_access;

        // 计算数组
        try self.visitNode(access_data.target);

        // 计算索引
        if (access_data.index) |idx| {
            try self.visitNode(idx);
        } else {
            try self.emit(.push_null, 0, 0);
            self.pushStack();
        }

        try self.emit(.array_get, 0, 0);
        self.popStack(); // 弹出索引，数组变为结果
    }

    /// 访问属性访问
    fn visitPropertyAccess(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const prop_data = node.data.property_access;

        // 检查目标对象是否被标量替换
        const target_node = self.getNode(prop_data.target);
        if (target_node.tag == .variable) {
            const prop_name = self.getString(prop_data.property_name);
            // 尝试获取标量替换的字段槽位
            if (self.getScalarFieldSlot(prop_data.target, prop_name)) |field_slot| {
                // 标量替换：直接从局部变量读取
                try self.emit(.push_local, field_slot, 0);
                self.pushStack();
                return;
            }
        }

        // 标准属性访问
        // 计算对象
        try self.visitNode(prop_data.target);

        // 获取属性
        const prop_name = self.getString(prop_data.property_name);
        const prop_name_const = try self.addConstant(.{ .string_val = prop_name });
        try self.emit(.get_prop, prop_name_const, 0);
        // 对象变为属性值
    }

    /// 访问new表达式
    fn visitNewObject(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const new_data = node.data.object_instantiation;

        // 检查是否可以标量替换（完全消除分配）
        if (self.canScalarReplaceNode(index)) {
            // 标量替换：不生成对象分配，而是为每个字段分配局部变量
            // 构造参数仍然需要处理，但对象本身被消除
            for (new_data.args) |arg_idx| {
                try self.visitNode(arg_idx);
                // 参数值存储到对应的标量字段槽位
                // 这里简化处理：假设构造函数参数按顺序对应字段
                try self.emit(.pop, 0, 0);
                self.popStack();
            }
            // 压入一个占位符值（标量替换后对象引用变为null）
            try self.emit(.push_null, 0, 0);
            self.pushStack();
            return;
        }

        // 检查是否可以栈分配
        const use_stack_alloc = self.canStackAllocateNode(index);
        const stack_slot = if (use_stack_alloc) self.getStackSlotForNode(index) else null;

        // 压入构造参数
        for (new_data.args) |arg_idx| {
            try self.visitNode(arg_idx);
        }

        // 获取类名
        const class_node = self.getNode(new_data.class_name);
        var class_name_id: u32 = 0;
        if (class_node.tag == .variable) {
            class_name_id = class_node.data.variable.name;
        }

        const class_name = if (class_name_id != 0) self.getString(class_name_id) else "";
        const class_const = try self.addConstant(.{ .string_val = class_name });
        const arg_count: u16 = @intCast(new_data.args.len);

        if (use_stack_alloc and stack_slot != null) {
            // 栈分配：使用特殊指令在栈上分配对象
            // new_struct 指令用于栈分配，operand1 = 类名常量索引，operand2 = 栈槽位
            try self.emit(.new_struct, class_const, stack_slot.?);
            // 调用构造函数初始化栈上的对象
            const init_const = try self.addConstant(.{ .string_val = "__construct" });
            try self.emit(.call_method, init_const, arg_count);
        } else {
            // 堆分配：使用标准的 new_object 指令
            try self.emit(.new_object, class_const, arg_count);
            // 调用构造函数
            const init_const = try self.addConstant(.{ .string_val = "__construct" });
            try self.emit(.call_method, init_const, arg_count);
        }

        // 参数弹出，对象压入
        for (new_data.args) |_| {
            self.popStack();
        }
        self.pushStack();
    }

    /// 访问三元表达式
    fn visitTernary(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const ternary_data = node.data.ternary_expr;

        const else_label = self.newLabel();
        const end_label = self.newLabel();

        // 条件
        try self.visitNode(ternary_data.cond);
        try self.emitJump(.jz, else_label);

        // true分支
        if (ternary_data.then_expr) |then_idx| {
            self.popStack(); // 弹出条件值
            try self.visitNode(then_idx);
        } else {
            // Elvis operator: ?: - 条件值本身就是结果，不需要弹出
        }
        try self.emitJump(.jmp, end_label);

        // false分支
        try self.placeLabel(else_label);
        self.popStack(); // 弹出条件值
        try self.visitNode(ternary_data.else_expr);

        try self.placeLabel(end_label);
    }

    /// 访问try语句
    fn visitTry(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const try_data = node.data.try_stmt;

        try self.emit(.try_begin, 0, 0);
        try self.visitNode(try_data.body);
        try self.emit(.try_end, 0, 0);

        for (try_data.catch_clauses) |catch_idx| {
            const catch_node = self.getNode(catch_idx);
            const catch_data = catch_node.data.catch_clause;

            try self.emit(.catch_begin, 0, 0);

            // 存储异常变量
            if (catch_data.variable) |var_idx| {
                const var_node = self.getNode(var_idx);
                if (var_node.tag == .variable) {
                    const var_name = self.getString(var_node.data.variable.name);
                    const slot = try self.getOrCreateLocal(var_name);
                    try self.emit(.store_local, slot, 0);
                }
            }

            try self.visitNode(catch_data.body);
            try self.emit(.catch_end, 0, 0);
        }

        if (try_data.finally_clause) |finally_idx| {
            const finally_node = self.getNode(finally_idx);
            try self.emit(.finally_begin, 0, 0);
            try self.visitNode(finally_node.data.finally_clause.body);
            try self.emit(.finally_end, 0, 0);
        }
    }

    /// 访问throw语句
    fn visitThrow(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const throw_data = node.data.throw_stmt;

        try self.visitNode(throw_data.expression);
        try self.emit(.throw, 0, 0);
        self.popStack();
    }

    /// 访问闭包
    fn visitClosure(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const closure_data = node.data.closure;

        const closure_name_buf = std.fmt.allocPrint(self.allocator, "__closure_{d}", .{self.anon_fn_counter}) catch return CompileError.OutOfMemory;
        defer self.allocator.free(closure_name_buf);
        self.anon_fn_counter += 1;
        const closure_name_id = self.context.intern(closure_name_buf) catch return CompileError.OutOfMemory;
        const closure_name = self.getString(closure_name_id);

        var capture_local_slots = std.ArrayListUnmanaged(u16){};
        defer capture_local_slots.deinit(self.allocator);

        // 保存并重置状态：编译闭包体为独立 CompiledFunction
        const saved_locals = self.locals;
        const saved_local_count = self.local_count;
        const saved_instructions = self.instructions;
        const saved_constants = self.constants;
        const saved_max_stack = self.max_stack;
        const saved_current_stack = self.current_stack;
        const saved_label_counter = self.label_counter;
        const saved_labels = self.labels;
        const saved_pending_jumps = self.pending_jumps;
        const saved_loop_stack = self.loop_stack;

        self.locals = .{};
        self.local_count = 0;
        self.instructions = .{};
        self.constants = .{};
        self.max_stack = 0;
        self.current_stack = 0;
        self.label_counter = 0;
        self.labels = .{};
        self.pending_jumps = .{};
        self.loop_stack = .{};

        for (closure_data.params) |param_idx| {
            const param_node = self.getNode(param_idx);
            const param_name = self.getString(param_node.data.parameter.name);
            _ = self.getOrCreateLocal(param_name) catch return CompileError.OutOfMemory;
        }

        for (closure_data.captures) |capture_idx| {
            const capture_node = self.getNode(capture_idx);
            if (capture_node.tag == .variable) {
                const var_name = self.getString(capture_node.data.variable.name);
                const slot = self.getOrCreateLocal(var_name) catch return CompileError.OutOfMemory;
                capture_local_slots.append(self.allocator, slot) catch return CompileError.OutOfMemory;
            } else if (capture_node.tag == .unary_expr and capture_node.data.unary_expr.op == .ampersand) {
                const inner = self.getNode(capture_node.data.unary_expr.expr);
                if (inner.tag == .variable) {
                    const var_name = self.getString(inner.data.variable.name);
                    const slot = self.getOrCreateLocal(var_name) catch return CompileError.OutOfMemory;
                    capture_local_slots.append(self.allocator, slot) catch return CompileError.OutOfMemory;
                }
            }
        }

        try self.visitNode(closure_data.body);
        try self.emit(.ret_void, 0, 0);
        try self.resolveJumps();

        const compiled = self.allocator.create(CompiledFunction) catch return CompileError.OutOfMemory;
        compiled.* = CompiledFunction{
            .name = closure_name,
            .bytecode = self.instructions.toOwnedSlice(self.allocator) catch return CompileError.OutOfMemory,
            .constants = self.constants.toOwnedSlice(self.allocator) catch return CompileError.OutOfMemory,
            .local_count = self.local_count,
            .arg_count = @intCast(closure_data.params.len),
            .max_stack = self.max_stack,
            .flags = .{ .is_closure = true },
            .line_table = &[_]CompiledFunction.LineInfo{},
            .exception_table = &[_]CompiledFunction.ExceptionEntry{},
            .capture_local_slots = capture_local_slots.toOwnedSlice(self.allocator) catch return CompileError.OutOfMemory,
        };
        self.functions.put(self.allocator, closure_name, compiled) catch return CompileError.OutOfMemory;

        // 恢复状态
        self.locals.deinit(self.allocator);
        self.locals = saved_locals;
        self.local_count = saved_local_count;
        self.instructions.deinit(self.allocator);
        self.instructions = saved_instructions;
        self.constants.deinit(self.allocator);
        self.constants = saved_constants;
        self.max_stack = saved_max_stack;
        self.current_stack = saved_current_stack;
        self.labels.deinit(self.allocator);
        self.labels = saved_labels;
        self.pending_jumps.deinit(self.allocator);
        self.pending_jumps = saved_pending_jumps;
        self.loop_stack.deinit(self.allocator);
        self.loop_stack = saved_loop_stack;
        self.label_counter = saved_label_counter;

        var effective_capture_count: u16 = 0;
        for (closure_data.captures) |capture_idx| {
            const capture_node = self.getNode(capture_idx);
            if (capture_node.tag == .variable) {
                const var_name = self.getString(capture_node.data.variable.name);
                if (self.locals.get(var_name)) |slot| {
                    try self.emit(.capture_var, slot, 0);
                } else {
                    try self.emit(.capture_var, 0, 1);
                }
                self.pushStack();
                effective_capture_count += 1;
            } else if (capture_node.tag == .unary_expr and capture_node.data.unary_expr.op == .ampersand) {
                const inner = self.getNode(capture_node.data.unary_expr.expr);
                if (inner.tag == .variable) {
                    const var_name = self.getString(inner.data.variable.name);
                    if (self.locals.get(var_name)) |slot| {
                        try self.emit(.capture_var, slot, 0);
                    } else {
                        try self.emit(.capture_var, 0, 1);
                    }
                    self.pushStack();
                    effective_capture_count += 1;
                }
            }
        }

        const name_const = try self.addConstant(.{ .string_val = closure_name });
        try self.emit(.make_closure, name_const, effective_capture_count);
        var i: u16 = 0;
        while (i < effective_capture_count) : (i += 1) {
            self.popStack();
        }
        self.pushStack();
    }

    /// 访问箭头函数
    fn visitArrowFunction(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const arrow_data = node.data.arrow_function;

        const arrow_name_buf = std.fmt.allocPrint(self.allocator, "__arrow_{d}", .{self.anon_fn_counter}) catch return CompileError.OutOfMemory;
        defer self.allocator.free(arrow_name_buf);
        self.anon_fn_counter += 1;
        const arrow_name_id = self.context.intern(arrow_name_buf) catch return CompileError.OutOfMemory;
        const arrow_name = self.getString(arrow_name_id);

        var param_set = std.StringHashMapUnmanaged(void){};
        defer param_set.deinit(self.allocator);
        for (arrow_data.params) |param_idx| {
            const param_node = self.getNode(param_idx);
            const param_name = self.getString(param_node.data.parameter.name);
            param_set.put(self.allocator, param_name, {}) catch return CompileError.OutOfMemory;
        }

        var capture_names = std.ArrayListUnmanaged([]const u8){};
        defer capture_names.deinit(self.allocator);
        var iter = self.locals.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            if (name.len == 0 or name[0] != '$') continue;
            if (param_set.contains(name)) continue;
            capture_names.append(self.allocator, name) catch return CompileError.OutOfMemory;
        }
        std.mem.sort([]const u8, capture_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        var capture_local_slots = std.ArrayListUnmanaged(u16){};
        defer capture_local_slots.deinit(self.allocator);

        const saved_locals = self.locals;
        const saved_local_count = self.local_count;
        const saved_instructions = self.instructions;
        const saved_constants = self.constants;
        const saved_max_stack = self.max_stack;
        const saved_current_stack = self.current_stack;
        const saved_label_counter = self.label_counter;
        const saved_labels = self.labels;
        const saved_pending_jumps = self.pending_jumps;
        const saved_loop_stack = self.loop_stack;

        self.locals = .{};
        self.local_count = 0;
        self.instructions = .{};
        self.constants = .{};
        self.max_stack = 0;
        self.current_stack = 0;
        self.label_counter = 0;
        self.labels = .{};
        self.pending_jumps = .{};
        self.loop_stack = .{};

        for (arrow_data.params) |param_idx| {
            const param_node = self.getNode(param_idx);
            const param_name = self.getString(param_node.data.parameter.name);
            _ = self.getOrCreateLocal(param_name) catch return CompileError.OutOfMemory;
        }

        for (capture_names.items) |cap_name| {
            const slot = self.getOrCreateLocal(cap_name) catch return CompileError.OutOfMemory;
            capture_local_slots.append(self.allocator, slot) catch return CompileError.OutOfMemory;
        }

        try self.visitNode(arrow_data.body);
        try self.emit(.ret, 0, 0);
        try self.resolveJumps();

        const compiled = self.allocator.create(CompiledFunction) catch return CompileError.OutOfMemory;
        compiled.* = CompiledFunction{
            .name = arrow_name,
            .bytecode = self.instructions.toOwnedSlice(self.allocator) catch return CompileError.OutOfMemory,
            .constants = self.constants.toOwnedSlice(self.allocator) catch return CompileError.OutOfMemory,
            .local_count = self.local_count,
            .arg_count = @intCast(arrow_data.params.len),
            .max_stack = self.max_stack,
            .flags = .{ .is_closure = true },
            .line_table = &[_]CompiledFunction.LineInfo{},
            .exception_table = &[_]CompiledFunction.ExceptionEntry{},
            .capture_local_slots = capture_local_slots.toOwnedSlice(self.allocator) catch return CompileError.OutOfMemory,
        };
        self.functions.put(self.allocator, arrow_name, compiled) catch return CompileError.OutOfMemory;

        self.locals.deinit(self.allocator);
        self.locals = saved_locals;
        self.local_count = saved_local_count;
        self.instructions.deinit(self.allocator);
        self.instructions = saved_instructions;
        self.constants.deinit(self.allocator);
        self.constants = saved_constants;
        self.max_stack = saved_max_stack;
        self.current_stack = saved_current_stack;
        self.labels.deinit(self.allocator);
        self.labels = saved_labels;
        self.pending_jumps.deinit(self.allocator);
        self.pending_jumps = saved_pending_jumps;
        self.loop_stack.deinit(self.allocator);
        self.loop_stack = saved_loop_stack;
        self.label_counter = saved_label_counter;

        for (capture_names.items) |cap_name| {
            if (self.locals.get(cap_name)) |slot| {
                try self.emit(.capture_var, slot, 0);
            } else {
                try self.emit(.capture_var, 0, 1);
            }
            self.pushStack();
        }

        const name_const = try self.addConstant(.{ .string_val = arrow_name });
        try self.emit(.make_closure, name_const, @intCast(capture_names.items.len));
        var i: usize = 0;
        while (i < capture_names.items.len) : (i += 1) {
            self.popStack();
        }
        self.pushStack();
    }

    /// 访问函数声明
    fn visitFunctionDecl(self: *BytecodeGenerator, index: ast.Node.Index) CompileError!void {
        const node = self.getNode(index);
        const func_data = node.data.function_decl;

        // 保存当前状态
        const saved_locals = self.locals;
        const saved_local_count = self.local_count;
        const saved_instructions = self.instructions;
        const saved_constants = self.constants;
        const saved_max_stack = self.max_stack;
        const saved_current_stack = self.current_stack;
        const saved_label_counter = self.label_counter;
        const saved_labels = self.labels;
        const saved_pending_jumps = self.pending_jumps;
        const saved_loop_stack = self.loop_stack;

        // 重置状态 - 使用 Unmanaged 版本
        self.locals = .{};
        self.local_count = 0;
        self.instructions = .{};
        self.constants = .{};
        self.max_stack = 0;
        self.current_stack = 0;
        self.label_counter = 0;
        self.labels = .{};
        self.pending_jumps = .{};
        self.loop_stack = .{};

        // 处理参数
        for (func_data.params) |param_idx| {
            const param_node = self.getNode(param_idx);
            const param_name = self.getString(param_node.data.parameter.name);
            _ = try self.getOrCreateLocal(param_name);
        }

        // 编译函数体
        try self.visitNode(func_data.body);
        try self.emit(.ret_void, 0, 0);
        try self.resolveJumps();

        // 创建编译后的函数
        const func_name = self.getString(func_data.name);
        const compiled = try self.allocator.create(CompiledFunction);
        compiled.* = CompiledFunction{
            .name = func_name,
            .bytecode = try self.instructions.toOwnedSlice(self.allocator),
            .constants = try self.constants.toOwnedSlice(self.allocator),
            .local_count = self.local_count,
            .arg_count = @intCast(func_data.params.len),
            .max_stack = self.max_stack,
            .flags = .{},
            .line_table = &[_]CompiledFunction.LineInfo{},
            .exception_table = &[_]CompiledFunction.ExceptionEntry{},
        };

        try self.functions.put(self.allocator, func_name, compiled);

        // 恢复状态
        self.locals.deinit(self.allocator);
        self.locals = saved_locals;
        self.local_count = saved_local_count;
        self.instructions.deinit(self.allocator);
        self.instructions = saved_instructions;
        self.constants.deinit(self.allocator);
        self.constants = saved_constants;
        self.max_stack = saved_max_stack;
        self.current_stack = saved_current_stack;
        self.labels.deinit(self.allocator);
        self.labels = saved_labels;
        self.pending_jumps.deinit(self.allocator);
        self.pending_jumps = saved_pending_jumps;
        self.loop_stack.deinit(self.allocator);
        self.loop_stack = saved_loop_stack;
        self.label_counter = saved_label_counter;
    }
};

test "generator init" {
    const allocator = std.testing.allocator;
    var context = PHPContext.init(allocator);
    defer context.deinit();

    var gen = BytecodeGenerator.init(allocator, &context);
    defer gen.deinit();

    try std.testing.expect(gen.instructions.items.len == 0);
    try std.testing.expect(gen.local_count == 0);
}

// ============================================================================
// Syntax Mode Independence Tests (Requirements 5.1, 5.2)
// ============================================================================

test "generator uses normalized variable names" {
    // This test verifies that the BytecodeGenerator uses normalized variable names
    // from the AST, which already have the $ prefix regardless of syntax mode.
    const allocator = std.testing.allocator;
    var context = PHPContext.init(allocator);
    defer context.deinit();

    var gen = BytecodeGenerator.init(allocator, &context);
    defer gen.deinit();

    // Test that getOrCreateLocal works with normalized names (with $ prefix)
    const slot1 = try gen.getOrCreateLocal("$myVar");
    const slot2 = try gen.getOrCreateLocal("$myVar"); // Same name should return same slot
    const slot3 = try gen.getOrCreateLocal("$otherVar"); // Different name should get new slot

    try std.testing.expectEqual(slot1, slot2);
    try std.testing.expect(slot1 != slot3);
    try std.testing.expectEqual(@as(u16, 0), slot1);
    try std.testing.expectEqual(@as(u16, 1), slot3);
}

test "generator local count increments correctly" {
    const allocator = std.testing.allocator;
    var context = PHPContext.init(allocator);
    defer context.deinit();

    var gen = BytecodeGenerator.init(allocator, &context);
    defer gen.deinit();

    try std.testing.expectEqual(@as(u16, 0), gen.local_count);

    _ = try gen.getOrCreateLocal("$a");
    try std.testing.expectEqual(@as(u16, 1), gen.local_count);

    _ = try gen.getOrCreateLocal("$b");
    try std.testing.expectEqual(@as(u16, 2), gen.local_count);

    // Accessing existing variable should not increment count
    _ = try gen.getOrCreateLocal("$a");
    try std.testing.expectEqual(@as(u16, 2), gen.local_count);
}
