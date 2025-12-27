const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = @import("../runtime/types.zig").Value;
const PHPContext = @import("parser.zig").PHPContext;

pub const Compiler = struct {
    context: *PHPContext,
    chunk: *Chunk,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, context: *PHPContext) Compiler {
        return Compiler{
            .allocator = allocator,
            .context = context,
            .chunk = undefined, // Will be set before compilation
        };
    }

    pub fn compile(self: *Compiler, root_node_index: ast.Node.Index) !*Chunk {
        var new_chunk = self.allocator.create(Chunk) catch return error.OutOfMemory;
        new_chunk.* = Chunk.init(self.allocator);
        self.chunk = new_chunk;

        try self.compileNode(root_node_index);

        // Always end with a return
        try self.emitReturn();

        return self.chunk;
    }

    fn compileNode(self: *Compiler, node_index: ast.Node.Index) !void {
        const node = self.context.nodes.items[node_index];
        switch (node.tag) {
            .root => {
                for (node.data.root.stmts) |stmt| {
                    try self.compileNode(stmt);
                }
            },
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
                // For now, ignore unsupported nodes
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
};
