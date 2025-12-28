const std = @import("std");
const main = @import("../main.zig");
const bytecode = @import("../compiler/bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = @import("types.zig").Value;

const STACK_MAX = 256;

pub const VM = struct {
    chunk: *const Chunk,
    ip: usize,
    stack: [STACK_MAX]Value,
    stack_top: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) VM {
        return VM{
            .chunk = undefined,
            .ip = 0,
            .stack = undefined,
            .stack_top = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VM) void {
        _ = self;
    }

    pub fn interpret(self: *VM, chunk: *const Chunk) !Value {
        self.chunk = chunk;
        self.ip = 0;
        return self.run();
    }

    fn run(self: *VM) !Value {
        while (self.ip < self.chunk.code.items.len) {
            const instruction = self.chunk.code.items[self.ip];
            self.ip += 1;

            switch (@as(OpCode, @enumFromInt(instruction))) {
                .OpConstant => {
                    const constant_index = self.chunk.code.items[self.ip];
                    self.ip += 1;
                    const constant = self.chunk.constants.items[constant_index];
                    try self.push(constant);
                },
                .OpAdd => try self.binaryOp(.Add),
                .OpSubtract => try self.binaryOp(.Subtract),
                .OpMultiply => try self.binaryOp(.Multiply),
                .OpDivide => try self.binaryOp(.Divide),
                .OpReturn => {
                    return self.pop();
                },
            }
        }
        return error.ExecutionFinishedUnexpectedly;
    }

    fn push(self: *VM, value: Value) !void {
        if (self.stack_top >= STACK_MAX) {
            return error.StackOverflow;
        }
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    fn pop(self: *VM) Value {
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    const BinaryOpType = enum { Add, Subtract, Multiply, Divide };

    fn binaryOp(self: *VM, op: BinaryOpType) !void {
        const b = self.pop();
        const a = self.pop();

        if (a.tag == .integer and b.tag == .integer) {
            const result = switch (op) {
                .Add => Value.initInt(a.data.integer + b.data.integer),
                .Subtract => Value.initInt(a.data.integer - b.data.integer),
                .Multiply => Value.initInt(a.data.integer * b.data.integer),
                .Divide => {
                    if (b.data.integer == 0) return error.DivisionByZero;
                    return Value.initFloat(@as(f64, @floatFromInt(a.data.integer)) / @as(f64, @floatFromInt(b.data.integer)));
                },
            };
            try self.push(result);
        } else {
            return error.InvalidTypesForBinaryOperation;
        }
    }
};
