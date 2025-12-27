const std = @import("std");
const Value = @import("../runtime/types.zig").Value;

pub const OpCode = enum(u8) {
    OpConstant,
    OpNull,
    OpPop,
    OpAdd,
    OpSubtract,
    OpMultiply,
    OpDivide,
    OpSetGlobal,
    OpGetGlobal,
    OpReturn,
};

pub const Chunk = struct {
    code: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    lines: std.ArrayList(usize),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = std.ArrayList(u8).init(allocator),
            .constants = std.ArrayList(Value).init(allocator),
            .lines = std.ArrayList(usize).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
    }

    pub fn write(self: *Chunk, byte: u8, line: usize) !void {
        try self.code.append(byte);
        try self.lines.append(line);
    }

    pub fn addConstant(self: *Chunk, value: Value) !u8 {
        // TODO: for performance, check if constant already exists
        try self.constants.append(value);
        return @intCast(self.constants.items.len - 1);
    }
};
