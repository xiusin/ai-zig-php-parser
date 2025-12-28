const std = @import("std");
const ast = @import("../compiler/ast.zig");
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;
const CompiledFunction = instruction.CompiledFunction;
const BytecodeModule = instruction.BytecodeModule;
const Value = instruction.Value;

/// 字节码生成器 - 将AST编译为字节码
pub const BytecodeGenerator = struct {
    allocator: std.mem.Allocator,
    instructions: std.ArrayList(Instruction),
    constants: std.ArrayList(Value),
    locals: std.StringHashMap(u16),
    local_count: u16,
    max_stack: u16,
    current_stack: u16,
    labels: std.StringHashMap(u32),
    pending_jumps: std.ArrayList(PendingJump),
    loop_stack: std.ArrayList(LoopContext),
    line_info: std.ArrayList(LineInfo),
    current_line: u32,

    const PendingJump = struct {
        instruction_index: u32,
        label: []const u8,
    };

    const LoopContext = struct {
        continue_label: []const u8,
        break_label: []const u8,
    };

    const LineInfo = struct {
        offset: u32,
        line: u32,
    };

    pub fn init(allocator: std.mem.Allocator) BytecodeGenerator {
        return BytecodeGenerator{
            .allocator = allocator,
            .instructions = std.ArrayListUnmanaged(Instruction){},
            .constants = std.ArrayListUnmanaged(Value){},
            .locals = std.StringHashMap(u16).init(allocator),
            .local_count = 0,
            .max_stack = 0,
            .current_stack = 0,
            .labels = std.StringHashMap(u32).init(allocator),
            .pending_jumps = std.ArrayListUnmanaged(PendingJump){},
            .loop_stack = std.ArrayListUnmanaged(LoopContext){},
            .line_info = std.ArrayListUnmanaged(LineInfo){},
            .current_line = 1,
        };
    }

    pub fn deinit(self: *BytecodeGenerator) void {
        self.instructions.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.locals.deinit();
        self.labels.deinit();
        self.pending_jumps.deinit(self.allocator);
        self.loop_stack.deinit(self.allocator);
        self.line_info.deinit(self.allocator);
    }

    pub fn reset(self: *BytecodeGenerator) void {
        self.instructions.clearRetainingCapacity();
        self.constants.clearRetainingCapacity();
        self.locals.clearRetainingCapacity();
        self.local_count = 0;
        self.max_stack = 0;
        self.current_stack = 0;
        self.labels.clearRetainingCapacity();
        self.pending_jumps.clearRetainingCapacity();
        self.loop_stack.clearRetainingCapacity();
        self.line_info.clearRetainingCapacity();
        self.current_line = 1;
    }

    /// 编译AST节点为字节码函数
    pub fn compile(self: *BytecodeGenerator, node: ast.Node, name: []const u8) !*CompiledFunction {
        self.reset();
        try self.visitNode(node);
        try self.emit(.ret_void, 0, 0);
        try self.resolveLabels();

        const func = try CompiledFunction.init(self.allocator, name);
        func.bytecode = try self.instructions.toOwnedSlice();
        func.constants = try self.constants.toOwnedSlice();
        func.local_count = self.local_count;
        func.max_stack = self.max_stack;
        return func;
    }

    /// 访问AST节点
    fn visitNode(self: *BytecodeGenerator, node: ast.Node) !void {
        switch (node.tag) {
            .root => try self.visitRoot(node),
            .expression_stmt => try self.visitExpressionStmt(node),
            .echo_stmt => try self.visitEcho(node),
            .if_stmt => try self.visitIf(node),
            .while_stmt => try self.visitWhile(node),
            .for_stmt => try self.visitFor(node),
            .foreach_stmt => try self.visitForeach(node),
            .function_decl => try self.visitFunctionDecl(node),
            .return_stmt => try self.visitReturn(node),
            .assign => try self.visitAssign(node),
            .binary_op => try self.visitBinaryOp(node),
            .unary_op => try self.visitUnaryOp(node),
            .literal => try self.visitLiteral(node),
            .variable => try self.visitVariable(node),
            .function_call => try self.visitFunctionCall(node),
            .method_call => try self.visitMethodCall(node),
            .array_literal => try self.visitArrayLiteral(node),
            .array_access => try self.visitArrayAccess(node),
            .property_access => try self.visitPropertyAccess(node),
            .new_expr => try self.visitNewExpr(node),
            .ternary => try self.visitTernary(node),
            .try_catch => try self.visitTryCatch(node),
            .throw_stmt => try self.visitThrow(node),
            .class_decl => try self.visitClassDecl(node),
            .struct_decl => try self.visitStructDecl(node),
            .closure => try self.visitClosure(node),
            .arrow_function => try self.visitArrowFunction(node),
            else => {},
        }
    }

    fn visitRoot(_: *BytecodeGenerator, node: ast.Node) !void {
        for (node.data.root.stmts) |stmt_idx| {
            _ = stmt_idx;
            // TODO: 获取实际的语句节点并访问
        }
    }

    fn visitExpressionStmt(self: *BytecodeGenerator, node: ast.Node) !void {
        // 表达式语句：计算表达式后弹出结果
        // TODO: 访问表达式节点
        _ = node;
        try self.emit(.pop, 0, 0);
    }

    fn visitEcho(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // echo语句：先计算表达式，然后调用内置echo
        try self.emit(.call_builtin, 0, 1); // echo函数ID=0
    }

    fn visitIf(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        const else_label = try self.createLabel("else");
        const end_label = try self.createLabel("end_if");

        // 条件跳转到else
        try self.emitJump(.jz, else_label);

        // then分支
        // TODO: visitNode(then_branch)

        // 跳转到结束
        try self.emitJump(.jmp, end_label);

        // else标签
        try self.placeLabel(else_label);

        // else分支（如果存在）
        // TODO: if (else_branch) visitNode(else_branch)

        // 结束标签
        try self.placeLabel(end_label);
    }

    fn visitWhile(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        const loop_start = try self.createLabel("while_start");
        const loop_end = try self.createLabel("while_end");

        try self.loop_stack.append(.{
            .continue_label = loop_start,
            .break_label = loop_end,
        });

        // 循环开始标记（JIT热点检测）
        try self.emit(.loop_start, 0, 0);
        try self.placeLabel(loop_start);

        // 条件检查
        // TODO: visitNode(condition)
        try self.emitJump(.jz, loop_end);

        // 循环体
        // TODO: visitNode(body)

        // 跳回循环开始
        try self.emitJump(.jmp, loop_start);

        // 循环结束
        try self.emit(.loop_end, 0, 0);
        try self.placeLabel(loop_end);

        _ = self.loop_stack.pop();
    }

    fn visitFor(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        const loop_start = try self.createLabel("for_start");
        const loop_continue = try self.createLabel("for_continue");
        const loop_end = try self.createLabel("for_end");

        try self.loop_stack.append(.{
            .continue_label = loop_continue,
            .break_label = loop_end,
        });

        // 初始化
        // TODO: visitNode(init)
        try self.emit(.pop, 0, 0);

        try self.emit(.loop_start, 0, 0);
        try self.placeLabel(loop_start);

        // 条件
        // TODO: visitNode(condition)
        try self.emitJump(.jz, loop_end);

        // 循环体
        // TODO: visitNode(body)

        // continue点
        try self.placeLabel(loop_continue);

        // 更新
        // TODO: visitNode(update)
        try self.emit(.pop, 0, 0);

        try self.emitJump(.jmp, loop_start);

        try self.emit(.loop_end, 0, 0);
        try self.placeLabel(loop_end);

        _ = self.loop_stack.pop();
    }

    fn visitForeach(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        const loop_start = try self.createLabel("foreach_start");
        const loop_end = try self.createLabel("foreach_end");

        try self.loop_stack.append(.{
            .continue_label = loop_start,
            .break_label = loop_end,
        });

        // 初始化迭代器
        try self.emit(.foreach_init, 0, 0);

        try self.emit(.loop_start, 0, 0);
        try self.placeLabel(loop_start);

        // 获取下一个元素，如果没有则跳转到结束
        try self.emitJump(.foreach_next, loop_end);

        // 循环体
        // TODO: visitNode(body)

        try self.emitJump(.jmp, loop_start);

        try self.emit(.loop_end, 0, 0);
        try self.placeLabel(loop_end);

        _ = self.loop_stack.pop();
    }

    fn visitFunctionDecl(_: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 函数声明在顶层处理，这里只是占位
    }

    fn visitReturn(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 如果有返回值，先计算
        // TODO: if (return_value) visitNode(return_value)
        try self.emit(.ret, 0, 0);
    }

    fn visitAssign(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 计算右值
        // TODO: visitNode(rhs)

        // 存储到左值
        // TODO: 根据左值类型选择store_local/store_global/array_set/set_prop
        try self.emit(.store_local, 0, 0);
    }

    fn visitBinaryOp(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 计算左操作数
        // TODO: visitNode(lhs)

        // 计算右操作数
        // TODO: visitNode(rhs)

        // 根据操作符发射对应指令
        // TODO: 根据node.data.binary_op.op选择指令
        try self.emit(.add_int, 0, 0);
    }

    fn visitUnaryOp(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 计算操作数
        // TODO: visitNode(operand)

        // 发射一元操作指令
        try self.emit(.neg_int, 0, 0);
    }

    fn visitLiteral(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 根据字面量类型优化
        // TODO: 解析node.data.literal
        const const_idx = try self.addConstant(.{ .int_val = 0 });
        try self.emit(.push_const, const_idx, 0);
        self.pushStack();
    }

    fn visitVariable(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 查找变量
        // TODO: 从locals或globals获取
        try self.emit(.push_local, 0, 0);
        self.pushStack();
    }

    fn visitFunctionCall(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 压入参数
        // TODO: for (args) visitNode(arg)

        // 调用函数
        try self.emit(.call, 0, 0); // 函数ID, 参数数量
    }

    fn visitMethodCall(self: *BytecodeGenerator, node: ast.Node) !void {
        // 计算对象
        // TODO: visitNode(object)
        // 压入参数
        // TODO: for (args) visitNode(arg)
        // 调用方法
        _ = node;
        try self.emit(.call_method, 0, 0); // 方法名ID, 参数数量
    }

    fn visitArrayLiteral(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 创建数组
        try self.emit(.new_array, 0, 0);
        self.pushStack();

        // 添加元素
        // TODO: for (elements) { visitNode(key); visitNode(value); emit(.array_set) }
    }

    fn visitArrayAccess(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 计算数组
        // TODO: visitNode(array)

        // 计算索引
        // TODO: visitNode(index)

        try self.emit(.array_get, 0, 0);
        self.popStack(); // 弹出索引，结果替换数组位置
    }

    fn visitPropertyAccess(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 计算对象
        // TODO: visitNode(object)

        // 获取属性
        try self.emit(.get_prop, 0, 0); // 属性名ID
    }

    fn visitNewExpr(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 压入构造参数
        // TODO: for (args) visitNode(arg)

        // 创建对象
        try self.emit(.new_object, 0, 0); // 类ID, 参数数量
        self.pushStack();
    }

    fn visitTernary(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        const else_label = try self.createLabel("ternary_else");
        const end_label = try self.createLabel("ternary_end");

        // 条件
        // TODO: visitNode(condition)
        try self.emitJump(.jz, else_label);

        // true分支
        // TODO: visitNode(true_expr)
        try self.emitJump(.jmp, end_label);

        // false分支
        try self.placeLabel(else_label);
        // TODO: visitNode(false_expr)

        try self.placeLabel(end_label);
    }

    fn visitTryCatch(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        try self.emit(.try_begin, 0, 0);
        // TODO: visitNode(try_block)
        try self.emit(.try_end, 0, 0);

        try self.emit(.catch_begin, 0, 0);
        // TODO: visitNode(catch_block)
        try self.emit(.catch_end, 0, 0);
    }

    fn visitThrow(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 计算异常对象
        // TODO: visitNode(exception)
        try self.emit(.throw, 0, 0);
    }

    fn visitClassDecl(_: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 类声明在模块级处理
    }

    fn visitStructDecl(_: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 结构体声明在模块级处理
    }

    fn visitClosure(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        // 捕获变量
        // TODO: for (captured) emit(.capture_var)

        // 创建闭包
        try self.emit(.make_closure, 0, 0);
        self.pushStack();
    }

    fn visitArrowFunction(self: *BytecodeGenerator, node: ast.Node) !void {
        _ = node;
        try self.emit(.arrow_fn, 0, 0);
        self.pushStack();
    }

    // ========== 辅助方法 ==========

    fn emit(self: *BytecodeGenerator, opcode: OpCode, op1: u16, op2: u16) !void {
        try self.instructions.append(Instruction.init(opcode, op1, op2));
    }

    fn emitJump(self: *BytecodeGenerator, opcode: OpCode, label: []const u8) !void {
        const idx: u32 = @intCast(self.instructions.items.len);
        try self.instructions.append(Instruction.init(opcode, 0, 0));
        try self.pending_jumps.append(.{
            .instruction_index = idx,
            .label = label,
        });
    }

    var label_counter: u32 = 0;

    fn createLabel(_: *BytecodeGenerator, prefix: []const u8) ![]const u8 {
        label_counter += 1;
        var buf: [64]u8 = undefined;
        const len = std.fmt.bufPrint(&buf, "{s}_{d}", .{ prefix, label_counter }) catch return error.LabelTooLong;
        return len;
    }

    fn placeLabel(self: *BytecodeGenerator, label: []const u8) !void {
        const offset: u32 = @intCast(self.instructions.items.len);
        try self.labels.put(label, offset);
    }

    fn resolveLabels(self: *BytecodeGenerator) !void {
        for (self.pending_jumps.items) |jump| {
            if (self.labels.get(jump.label)) |target| {
                self.instructions.items[jump.instruction_index].operand1 = @truncate(target);
            }
        }
    }

    pub fn addConstant(self: *BytecodeGenerator, value: Value) !u16 {
        const idx: u16 = @intCast(self.constants.items.len);
        try self.constants.append(self.allocator, value);
        return idx;
    }

    pub fn getOrAddLocal(self: *BytecodeGenerator, name: []const u8) !u16 {
        if (self.locals.get(name)) |idx| {
            return idx;
        }
        const idx = self.local_count;
        self.local_count += 1;
        try self.locals.put(name, idx);
        return idx;
    }

    fn pushStack(self: *BytecodeGenerator) void {
        self.current_stack += 1;
        if (self.current_stack > self.max_stack) {
            self.max_stack = self.current_stack;
        }
    }

    fn popStack(self: *BytecodeGenerator) void {
        if (self.current_stack > 0) {
            self.current_stack -= 1;
        }
    }
};

test "generator init" {
    const allocator = std.testing.allocator;
    var gen = BytecodeGenerator.init(allocator);
    defer gen.deinit();

    try std.testing.expect(gen.instructions.items.len == 0);
    try std.testing.expect(gen.local_count == 0);
}
