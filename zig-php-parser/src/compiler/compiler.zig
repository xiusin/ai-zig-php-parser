const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = @import("../runtime/types.zig").Value;
const PHPContext = @import("parser.zig").PHPContext;
const Function = @import("../runtime/types.zig").UserFunction;
const PHPString = @import("../runtime/types.zig").PHPString;

const Local = struct {
    name: []const u8,
    depth: i32,
};

const CompilerScope = struct {
    locals: std.ArrayList(Local),
    scope_depth: i32,
};

pub const Compiler = struct {
    context: *PHPContext,
    chunk: *Chunk,
    allocator: std.mem.Allocator,
    scope: *CompilerScope,
    parent: ?*Compiler,

    pub fn init(allocator: std.mem.Allocator, context: *PHPContext, parent_compiler: ?*Compiler) Compiler {
        var new_scope = allocator.create(CompilerScope) catch @panic("oom");
        new_scope.* = .{
            .locals = std.ArrayList(Local).init(allocator),
            .scope_depth = if (parent_compiler) |p| p.scope.scope_depth + 1 else 0,
        };

        return Compiler{
            .allocator = allocator,
            .context = context,
            .chunk = undefined,
            .scope = new_scope,
            .parent = parent_compiler,
        };
    }

    pub fn compile(self: *Compiler, root_node_index: ast.Node.Index) !*Function {
        var func_name = try PHPString.init(self.allocator, "<script>");
        var main_function = self.allocator.create(Function) catch return error.OutOfMemory;
        main_function.* = Function.init(func_name);

        var new_chunk = self.allocator.create(Chunk) catch return error.OutOfMemory;
        new_chunk.* = Chunk.init(self.allocator);
        self.chunk = new_chunk;
        main_function.chunk = self.chunk;

        try self.compileNode(root_node_index);

        try self.emitReturn();

        return main_function;
    }

    fn compileNode(self: *Compiler, node_index: ast.Node.Index) !void {
        const node = self.context.nodes.items[node_index];
        switch (node.tag) {
            .root => {
                for (node.data.root.stmts) |stmt| {
                    try self.compileNode(stmt);
                }
            },
            .expression_stmt => {
                try self.compileNode(node.data.expression_stmt.expr);
                try self.emitByte(@intFromEnum(OpCode.OpPop), node.main_token.loc.start);
            },
            .assignment => {
                const target_node = self.context.nodes.items[node.data.assignment.target];
                if (target_node.tag == .variable) {
                    const var_name_id = target_node.data.variable.name;
                    const var_name = self.context.string_pool.keys()[var_name_id];

                    try self.compileNode(node.data.assignment.value);

                    if (self.scope.scope_depth > 0) {
                        if (self.resolveLocal(var_name)) |local_index| {
                            try self.emitBytes(@intFromEnum(OpCode.OpSetLocal), @intCast(local_index), node.main_token.loc.start);
                        } else {
                            return error.VariableNotFound;
                        }
                    } else {
                        const name_const_idx = try self.identifierConstant(var_name);
                        try self.emitBytes(@intFromEnum(OpCode.OpSetGlobal), name_const_idx, node.main_token.loc.start);
                    }
                } else {
                    return error.InvalidAssignmentTarget;
                }
            },
            .variable => {
                const var_name_id = node.data.variable.name;
                const var_name = self.context.string_pool.keys()[var_name_id];

                if (self.scope.scope_depth > 0) {
                     if (self.resolveLocal(var_name)) |local_index| {
                        try self.emitBytes(@intFromEnum(OpCode.OpGetLocal), @intCast(local_index), node.main_token.loc.start);
                    } else {
                        return error.VariableNotFound;
                    }
                } else {
                    const name_const_idx = try self.identifierConstant(var_name);
                    try self.emitBytes(@intFromEnum(OpCode.OpGetGlobal), name_const_idx, node.main_token.loc.start);
                }
            },
            .function_decl => try self.functionDeclaration(node.data.function_decl, node.main_token.loc.start),
            .function_call => try self.compileFunctionCall(node.data.function_call, node.main_token.loc.start),
            .return_stmt => {
                if (node.data.return_stmt.expr) |expr| {
                    try self.compileNode(expr);
                    try self.emitByte(@intFromEnum(OpCode.OpReturn), node.main_token.loc.start);
                } else {
                    try self.emitReturn();
                }
            },
            .literal_int => {
                const value = Value.initInt(node.data.literal_int.value);
                try self.emitConstant(value, node.main_token.loc.start);
            },
            .binary_expr => {
                try self.compileNode(node.data.binary_expr.lhs);
                try self.compileNode(node.data.binary_expr.rhs);

                switch (node.data.binary_expr.op) {
                    .plus => try self.emitByte(@intFromEnum(OpCode.OpAdd), node.main_token.loc.start),
                    .minus => try self.emitByte(@intFromEnum(OpCode.OpSubtract), node.main_token.loc.start),
                    .asterisk => try self.emitByte(@intFromEnum(OpCode.OpMultiply), node.main_token.loc.start),
                    .slash => try self.emitByte(@intFromEnum(OpCode.OpDivide), node.main_token.loc.start),
                    else => return error.UnsupportedOperator,
                }
            },
            else => {
                std.debug.print("Unsupported AST node type in compiler: {s}\n", .{@tagName(node.tag)});
            },
        }
    }

    fn emitByte(self: *Compiler, byte: u8, line: usize) !void {
        try self.chunk.write(byte, line);
    }

    fn emitBytes(self: *Compiler, byte1: u8, byte2: u8, line: usize) !void {
        try self.emitByte(byte1, line);
        try self.emitByte(byte2, line);
    }

    fn emitConstant(self: *Compiler, value: Value, line: usize) !void {
        const constant_index = try self.chunk.addConstant(value);
        try self.emitBytes(@intFromEnum(OpCode.OpConstant), constant_index, line);
    }

    fn emitReturn(self: *Compiler) !void {
        try self.emitByte(@intFromEnum(OpCode.OpNull), 0);
        try self.emitByte(@intFromEnum(OpCode.OpReturn), 0);
    }

    fn identifierConstant(self: *Compiler, name: []const u8) !u8 {
        const string_val = Value.initString(self.allocator, name) catch return error.OutOfMemory;
        return self.chunk.addConstant(string_val);
    }

    fn functionDeclaration(self: *Compiler, func_data: ast.Node.Data.function_decl, line: usize) !void {
        const func_name = self.context.string_pool.keys()[func_data.name];
        const func_name_const_idx = try self.identifierConstant(func_name);

        var function_compiler = Compiler.init(self.allocator, self.context, self);

        const function = try function_compiler.compileFunction(func_data, func_name);

        const func_const_idx = try self.chunk.addConstant(Value{.user_function = function});
        try self.emitBytes(@intFromEnum(OpCode.OpConstant), func_const_idx, line);
        try self.emitBytes(@intFromEnum(OpCode.OpDefineGlobal), func_name_const_idx, line);
    }

    fn compileFunction(self: *Compiler, func_data: ast.Node.Data.function_decl, name: []const u8) !*Function {
        var func_name = try PHPString.init(self.allocator, name);
        var function = self.allocator.create(Function) catch return error.OutOfMemory;
        function.* = Function.init(func_name);
        function.arity = @intCast(func_data.params.len);

        // Handle parameters
        for (func_data.params) |param_index| {
            const param_node = self.context.nodes.items[param_index];
            const param_name = self.context.string_pool.keys()[param_node.data.parameter.name];
            try self.addLocal(param_name);
        }

        var new_chunk = self.allocator.create(Chunk) catch return error.OutOfMemory;
        new_chunk.* = Chunk.init(self.allocator);
        self.chunk = new_chunk;
        function.chunk = self.chunk;

        try self.compileNode(func_data.body);
        try self.emitReturn();

        return function;
    }

    fn addLocal(self: *Compiler, name: []const u8) !void {
        const local = Local {
            .name = name,
            .depth = self.scope.scope_depth,
        };
        try self.scope.locals.append(local);
    }

    fn compileFunctionCall(self: *Compiler, call_data: ast.Node.Data.function_call, line: usize) !void {
        try self.compileNode(call_data.name);

        for (call_data.args) |arg| {
            try self.compileNode(arg);
        }

        try self.emitBytes(@intFromEnum(OpCode.OpCall), @intCast(call_data.args.len), line);
    }

    fn resolveLocal(self: *Compiler, name: []const u8) ?usize {
        var i = self.scope.locals.items.len;
        while (i > 0) {
            i -= 1;
            const local = self.scope.locals.items[i];
            if (std.mem.eql(u8, name, local.name)) {
                return i;
            }
        }
        return null;
    }
};
