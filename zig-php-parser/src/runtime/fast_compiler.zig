//! FastVM 字节码编译器
//! 将 AST 编译为 FastVM 字节码
//!
//! 功能:
//! 1. AST 到 FastVM OpCode 的转换
//! 2. 常量池管理
//! 3. 局部变量分配
//! 4. 跳转地址计算
//! 5. 超级指令优化

const std = @import("std");
const compiler_mod = @import("compiler");
const ast = compiler_mod.ast;
const parser_mod = compiler_mod.parser;
const Token = compiler_mod.Token;
const fast_vm = @import("fast_vm.zig");
const fast_value = @import("fast_value.zig");

const FastValue = fast_value.FastValue;
const OpCode = fast_vm.OpCode;
const PHPContext = parser_mod.PHPContext;
const CompiledFunc = fast_vm.CompiledFunc;

/// 编译错误
pub const CompileError = error{
    OutOfMemory,
    TooManyConstants,
    TooManyLocals,
    UndefinedVariable,
    InvalidExpression,
    UnsupportedFeature,
    JumpTooLarge,
};

/// 局部变量信息
const Local = struct {
    name: []const u8,
    depth: u32,
    is_captured: bool,
};

/// 跳转补丁信息
const JumpPatch = struct {
    offset: u32,
    target_label: u32,
};

/// FastVM 字节码编译器
pub const FastCompiler = struct {
    allocator: std.mem.Allocator,
    context: *PHPContext,
    
    // 字节码输出
    code: std.ArrayListUnmanaged(u8),
    constants: std.ArrayListUnmanaged(FastValue),
    
    // 局部变量
    locals: std.ArrayListUnmanaged(Local),
    scope_depth: u32,
    
    // 跳转补丁
    jump_patches: std.ArrayListUnmanaged(JumpPatch),
    label_positions: std.AutoHashMapUnmanaged(u32, u32),
    next_label: u32,
    
    // 统计
    max_stack: u16,
    current_stack: u16,

    pub fn init(allocator: std.mem.Allocator, context: *PHPContext) FastCompiler {
        return .{
            .allocator = allocator,
            .context = context,
            .code = .{},
            .constants = .{},
            .locals = .{},
            .scope_depth = 0,
            .jump_patches = .{},
            .label_positions = .{},
            .next_label = 0,
            .max_stack = 0,
            .current_stack = 0,
        };
    }

    pub fn deinit(self: *FastCompiler) void {
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.locals.deinit(self.allocator);
        self.jump_patches.deinit(self.allocator);
        self.label_positions.deinit(self.allocator);
    }

    /// 编译 AST 节点为 FastVM 字节码
    pub fn compile(self: *FastCompiler, root: ast.Node.Index) CompileError!CompiledFunc {
        // 编译根节点
        try self.compileNode(root);
        
        // 确保栈上有返回值（如果栈为空，推入 nil）
        // 这是因为 halt 指令会 pop 栈顶作为返回值
        try self.emitOp(.push_nil);
        
        // 添加 halt 指令
        try self.emitOp(.halt);
        
        // 解析跳转补丁
        try self.resolveJumps();
        
        // 创建编译后的函数
        const code_copy = self.allocator.dupe(u8, self.code.items) catch return CompileError.OutOfMemory;
        const constants_copy = self.allocator.dupe(FastValue, self.constants.items) catch return CompileError.OutOfMemory;
        
        return CompiledFunc{
            .name = "main",
            .code = code_copy,
            .constants = constants_copy,
            .locals_count = @intCast(self.locals.items.len),
            .params_count = 0,
            .max_stack = self.max_stack,
        };
    }

    /// 获取字符串标识符
    fn getString(self: *FastCompiler, string_id: u32) []const u8 {
        const keys = self.context.string_pool.keys();
        if (string_id < keys.len) {
            return keys[string_id];
        }
        return "";
    }

    /// 编译单个节点
    fn compileNode(self: *FastCompiler, node_idx: ast.Node.Index) CompileError!void {
        if (node_idx >= self.context.nodes.items.len) return;
        
        const node = self.context.nodes.items[node_idx];
        
        switch (node.tag) {
            .root => try self.compileRoot(node),
            .block => try self.compileBlock(node),
            .echo_stmt => try self.compileEcho(node),
            .expression_stmt => {}, // 空语句，不生成代码
            .assignment => try self.compileAssignment(node),
            .binary_expr => try self.compileBinaryExpr(node),
            .unary_expr => try self.compileUnaryExpr(node),
            .literal_int => try self.compileLiteralInt(node),
            .literal_float => try self.compileLiteralFloat(node),
            .literal_null => {
                try self.emitOp(.push_nil);
                self.pushStack();
            },
            .variable => try self.compileVariable(node),
            .if_stmt => try self.compileIf(node),
            .while_stmt => try self.compileWhile(node),
            .for_stmt => try self.compileFor(node),
            .return_stmt => try self.compileReturn(node),
            else => {
                // 不支持的节点类型，跳过
            },
        }
    }

    fn compileRoot(self: *FastCompiler, node: ast.Node) CompileError!void {
        const stmts = node.data.root.stmts;
        for (stmts) |stmt_idx| {
            try self.compileNode(stmt_idx);
        }
    }

    fn compileBlock(self: *FastCompiler, node: ast.Node) CompileError!void {
        self.scope_depth += 1;
        const stmts = node.data.block.stmts;
        for (stmts) |stmt_idx| {
            try self.compileNode(stmt_idx);
        }
        self.scope_depth -= 1;
        // 清理局部变量
        while (self.locals.items.len > 0 and 
               self.locals.items[self.locals.items.len - 1].depth > self.scope_depth) {
            _ = self.locals.pop();
        }
    }

    fn compileEcho(self: *FastCompiler, node: ast.Node) CompileError!void {
        const exprs = node.data.echo_stmt.exprs;
        for (exprs) |expr_idx| {
            try self.compileNode(expr_idx);
            try self.emitOp(.echo);
        }
    }

    fn compileAssignment(self: *FastCompiler, node: ast.Node) CompileError!void {
        const target_idx = node.data.assignment.target;
        const value_idx = node.data.assignment.value;
        
        // 编译值
        try self.compileNode(value_idx);
        
        // 获取目标变量
        if (target_idx >= self.context.nodes.items.len) return;
        const target_node = self.context.nodes.items[target_idx];
        if (target_node.tag == .variable) {
            const name = self.getString(target_node.data.variable.name);
            const local_idx = self.resolveLocal(name) orelse try self.addLocal(name);
            // 赋值表达式应该返回赋值后的值
            try self.emitOp(.dup);
            try self.emitOp(.store_local);
            try self.emitByte(@intCast(local_idx));
            // self.popStack(); // store_local 消耗一个，dup 增加一个，净增 1
        }
    }

    fn compileBinaryExpr(self: *FastCompiler, node: ast.Node) CompileError!void {
        const lhs_idx = node.data.binary_expr.lhs;
        const rhs_idx = node.data.binary_expr.rhs;
        const op = node.data.binary_expr.op;
        
        // 编译左操作数
        try self.compileNode(lhs_idx);
        // 编译右操作数
        try self.compileNode(rhs_idx);
        
        // 发出操作指令
        const opcode: OpCode = switch (op) {
            .plus => .add,
            .minus => .sub,
            .asterisk => .mul,
            .slash => .div,
            .percent => .mod,
            .equal_equal => .eq,
            .bang_equal => .ne,
            .less => .lt,
            .less_equal => .le,
            .greater => .gt,
            .greater_equal => .ge,
            .double_ampersand, .k_and => .land,
            .double_pipe, .k_or => .lor,
            .ampersand => .band,
            .pipe => .bor,
            .dot => .concat,
            else => return CompileError.UnsupportedFeature,
        };
        try self.emitOp(opcode);
    }

    fn compileUnaryExpr(self: *FastCompiler, node: ast.Node) CompileError!void {
        const expr_idx = node.data.unary_expr.expr;
        const op = node.data.unary_expr.op;
        
        try self.compileNode(expr_idx);
        
        const opcode: OpCode = switch (op) {
            .minus => .neg,
            .bang => .lnot,
            .plus_plus => .inc_i,
            .minus_minus => .dec_i,
            else => return CompileError.UnsupportedFeature,
        };
        try self.emitOp(opcode);
    }

    fn compileLiteralInt(self: *FastCompiler, node: ast.Node) CompileError!void {
        const value = node.data.literal_int.value;
        
        // 优化：使用超级指令处理常见值
        if (value == 0) {
            try self.emitOp(.push_0);
        } else if (value == 1) {
            try self.emitOp(.push_1);
        } else if (value == -1) {
            try self.emitOp(.push_m1);
        } else if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) {
            try self.emitOp(.push_int);
            try self.emitInt32(@intCast(value));
        } else {
            // 大整数使用常量池
            const idx = try self.addConstant(FastValue.initInt(value));
            try self.emitOp(.push_const);
            try self.emitU16(idx);
        }
        self.pushStack();
    }

    fn compileLiteralFloat(self: *FastCompiler, node: ast.Node) CompileError!void {
        const value = node.data.literal_float.value;
        try self.emitOp(.push_float);
        try self.emitFloat(value);
        self.pushStack();
    }

    fn compileVariable(self: *FastCompiler, node: ast.Node) CompileError!void {
        const name = self.getString(node.data.variable.name);
        const local_idx = self.resolveLocal(name) orelse {
            // 未定义变量，创建并初始化为 null
            const idx = try self.addLocal(name);
            try self.emitOp(.push_nil);
            try self.emitOp(.store_local);
            try self.emitByte(@intCast(idx));
            try self.emitOp(.push_local);
            try self.emitByte(@intCast(idx));
            return;
        };
        try self.emitOp(.push_local);
        try self.emitByte(@intCast(local_idx));
        self.pushStack();
    }

    fn compileIf(self: *FastCompiler, node: ast.Node) CompileError!void {
        const condition_idx = node.data.if_stmt.condition;
        const then_idx = node.data.if_stmt.then_branch;
        const else_idx = node.data.if_stmt.else_branch;
        
        // 编译条件
        try self.compileNode(condition_idx);
        
        // 条件为假时跳转到 else 或结束
        const else_label = self.newLabel();
        try self.emitJump(.jz, else_label);
        
        // 编译 then 分支
        try self.compileNode(then_idx);
        
        if (else_idx) |else_branch| {
            // 有 else 分支
            const end_label = self.newLabel();
            try self.emitJump(.jmp, end_label);
            
            self.markLabel(else_label);
            try self.compileNode(else_branch);
            self.markLabel(end_label);
        } else {
            self.markLabel(else_label);
        }
    }

    fn compileWhile(self: *FastCompiler, node: ast.Node) CompileError!void {
        const condition_idx = node.data.while_stmt.condition;
        const body_idx = node.data.while_stmt.body;
        
        const loop_start = self.newLabel();
        const loop_end = self.newLabel();
        
        self.markLabel(loop_start);
        
        // 编译条件
        try self.compileNode(condition_idx);
        try self.emitJump(.jz, loop_end);
        
        // 编译循环体
        try self.compileNode(body_idx);
        
        // 跳回循环开始
        try self.emitJump(.jmp, loop_start);
        
        self.markLabel(loop_end);
    }

    fn compileFor(self: *FastCompiler, node: ast.Node) CompileError!void {
        const init_idx = node.data.for_stmt.init;
        const cond_idx = node.data.for_stmt.condition;
        const loop_idx = node.data.for_stmt.loop;
        const body_idx = node.data.for_stmt.body;
        
        // 编译初始化表达式
        if (init_idx) |init_expr| {
            try self.compileNode(init_expr);
            try self.emitOp(.pop);
        }
        
        const loop_start = self.newLabel();
        const loop_end = self.newLabel();
        
        self.markLabel(loop_start);
        
        // 编译条件
        if (cond_idx) |cond| {
            try self.compileNode(cond);
            try self.emitJump(.jz, loop_end);
        }
        
        // 编译循环体
        try self.compileNode(body_idx);
        
        // 编译循环表达式
        if (loop_idx) |loop_expr| {
            try self.compileNode(loop_expr);
            try self.emitOp(.pop);
        }
        
        try self.emitJump(.jmp, loop_start);
        self.markLabel(loop_end);
    }

    fn compileReturn(self: *FastCompiler, node: ast.Node) CompileError!void {
        if (node.data.return_stmt.expr) |expr_idx| {
            try self.compileNode(expr_idx);
            try self.emitOp(.ret);
        } else {
            try self.emitOp(.ret_nil);
        }
    }

    // ========== 辅助函数 ==========

    fn emitOp(self: *FastCompiler, op: OpCode) CompileError!void {
        self.code.append(self.allocator, @intFromEnum(op)) catch return CompileError.OutOfMemory;
    }

    fn emitByte(self: *FastCompiler, byte: u8) CompileError!void {
        self.code.append(self.allocator, byte) catch return CompileError.OutOfMemory;
    }

    fn emitInt32(self: *FastCompiler, value: i32) CompileError!void {
        const bytes = std.mem.asBytes(&value);
        self.code.appendSlice(self.allocator, bytes) catch return CompileError.OutOfMemory;
    }

    fn emitU16(self: *FastCompiler, value: u16) CompileError!void {
        const bytes = std.mem.asBytes(&value);
        self.code.appendSlice(self.allocator, bytes) catch return CompileError.OutOfMemory;
    }

    fn emitFloat(self: *FastCompiler, value: f64) CompileError!void {
        const bits: u64 = @bitCast(value);
        const bytes = std.mem.asBytes(&bits);
        self.code.appendSlice(self.allocator, bytes) catch return CompileError.OutOfMemory;
    }

    fn emitJump(self: *FastCompiler, op: OpCode, label: u32) CompileError!void {
        try self.emitOp(op);
        const offset: u32 = @intCast(self.code.items.len);
        self.jump_patches.append(self.allocator, .{
            .offset = offset,
            .target_label = label,
        }) catch return CompileError.OutOfMemory;
        // 占位符
        try self.emitU16(0);
    }

    fn newLabel(self: *FastCompiler) u32 {
        const label = self.next_label;
        self.next_label += 1;
        return label;
    }

    fn markLabel(self: *FastCompiler, label: u32) void {
        self.label_positions.put(self.allocator, label, @intCast(self.code.items.len)) catch {};
    }

    fn resolveJumps(self: *FastCompiler) CompileError!void {
        for (self.jump_patches.items) |patch| {
            const target_pos = self.label_positions.get(patch.target_label) orelse continue;
            const current_pos = patch.offset + 2; // 跳过 offset 本身
            const relative: i16 = @intCast(@as(i32, @intCast(target_pos)) - @as(i32, @intCast(current_pos)));
            
            // 写入相对偏移
            const bytes = std.mem.asBytes(&relative);
            self.code.items[patch.offset] = bytes[0];
            self.code.items[patch.offset + 1] = bytes[1];
        }
    }

    fn addConstant(self: *FastCompiler, value: FastValue) CompileError!u16 {
        if (self.constants.items.len >= 65535) {
            return CompileError.TooManyConstants;
        }
        self.constants.append(self.allocator, value) catch return CompileError.OutOfMemory;
        return @intCast(self.constants.items.len - 1);
    }

    fn addLocal(self: *FastCompiler, name: []const u8) CompileError!usize {
        if (self.locals.items.len >= 255) {
            return CompileError.TooManyLocals;
        }
        self.locals.append(self.allocator, .{
            .name = name,
            .depth = self.scope_depth,
            .is_captured = false,
        }) catch return CompileError.OutOfMemory;
        return self.locals.items.len - 1;
    }

    fn resolveLocal(self: *FastCompiler, name: []const u8) ?usize {
        var i = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return i;
            }
        }
        return null;
    }

    fn pushStack(self: *FastCompiler) void {
        self.current_stack += 1;
        if (self.current_stack > self.max_stack) {
            self.max_stack = self.current_stack;
        }
    }

    fn popStack(self: *FastCompiler) void {
        if (self.current_stack > 0) {
            self.current_stack -= 1;
        }
    }
};

// ============================================================================
// 测试
// ============================================================================

test "FastCompiler simple arithmetic" {
    const allocator = std.testing.allocator;
    
    // 创建简单的 AST 上下文
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    var context = PHPContext.init(arena.allocator());
    defer context.deinit();
    
    var fast_compiler = FastCompiler.init(allocator, &context);
    defer fast_compiler.deinit();
    
    // 手动构建简单测试
    try fast_compiler.emitOp(.push_1);
    try fast_compiler.emitOp(.push_int);
    try fast_compiler.emitInt32(2);
    try fast_compiler.emitOp(.add_i);
    try fast_compiler.emitOp(.halt);
    
    try std.testing.expect(fast_compiler.code.items.len > 0);
}

test "FastCompiler loop compilation" {
    const allocator = std.testing.allocator;
    
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    var context = PHPContext.init(arena.allocator());
    defer context.deinit();
    
    var fast_compiler = FastCompiler.init(allocator, &context);
    defer fast_compiler.deinit();
    
    // 模拟循环: while (i < 10) { i++ }
    const loop_start = fast_compiler.newLabel();
    const loop_end = fast_compiler.newLabel();
    
    fast_compiler.markLabel(loop_start);
    try fast_compiler.emitOp(.push_local);
    try fast_compiler.emitByte(0);
    try fast_compiler.emitOp(.push_int);
    try fast_compiler.emitInt32(10);
    try fast_compiler.emitOp(.lt);
    try fast_compiler.emitJump(.jz, loop_end);
    try fast_compiler.emitOp(.load_inc_store);
    try fast_compiler.emitByte(0);
    try fast_compiler.emitJump(.jmp, loop_start);
    fast_compiler.markLabel(loop_end);
    try fast_compiler.emitOp(.halt);
    
    try fast_compiler.resolveJumps();
    
    try std.testing.expect(fast_compiler.code.items.len > 0);
}
