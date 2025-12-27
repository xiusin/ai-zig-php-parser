const std = @import("std");
const main = @import("../main.zig");
const bytecode = main.compiler.bytecode;
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = main.runtime.types.Value;

const STACK_MAX = 256;

pub const VM = struct {
    chunk: *Chunk,
    ip: usize, // instruction pointer
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
        // Free any remaining objects on the stack
        while (self.stack_top > 0) {
            self.pop();
        }
    }

    pub fn interpret(self: *VM, chunk: *Chunk) !Value {
        self.chunk = chunk;
        self.ip = 0;
        self.stack_top = 0;
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
                .OpNull => try self.push(Value.initNull()),
                .OpPop => {
                    _ = self.pop();
                },
                .OpAdd => try self.binaryOp(.Add),
                .OpSubtract => try self.binaryOp(.Subtract),
                .OpMultiply => try self.binaryOp(.Multiply),
                .OpDivide => try self.binaryOp(.Divide),
                .OpReturn => {
                    const result = self.pop();
                    return result;
                },
                else => {
                    std.debug.print("Unknown opcode: {any}\n", .{instruction});
                    return error.UnknownOpCode;
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

    fn peek(self: *VM, distance: usize) Value {
        return self.stack[self.stack_top - 1 - distance];
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
                    // PHP division always results in a float
                    return Value.initFloat(@as(f64, @floatFromInt(a.data.integer)) / @as(f64, @floatFromInt(b.data.integer)));
                },
            };
            try self.push(result);
        } else {
            // Handle other types (float, etc.)
            return error.InvalidTypesForBinaryOperation;
        }
    }
};
