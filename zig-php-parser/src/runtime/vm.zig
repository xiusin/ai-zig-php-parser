const std = @import("std");
const bytecode = @import("../compiler/bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = @import("types.zig").Value;

const STACK_MAX = 256;

pub const VM = struct {
    chunk: *Chunk,
    ip: usize,
    stack: [STACK_MAX]Value,
    stack_top: *Value,
    globals: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) VM {
        var vm = VM{
            .chunk = undefined,
            .ip = 0,
            .stack = undefined,
            .stack_top = undefined,
            .globals = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
        vm.stack_top = &vm.stack[0];
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.globals.deinit();
    }

    pub fn interpret(self: *VM, chunk: *Chunk) !Value {
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
                .OpNull => try self.push(Value.initNull()),
                .OpTrue => try self.push(Value.initBool(true)),
                .OpFalse => try self.push(Value.initBool(false)),
                .OpPop => _ = self.pop(),
                .OpEqual => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(Value.initBool(a.isEqual(b)));
                },
                .OpGreater => try self.binaryOp(.Greater),
                .OpLess => try self.binaryOp(.Less),
                .OpAdd => try self.binaryOp(.Add),
                .OpSubtract => try self.binaryOp(.Subtract),
                .OpMultiply => try self.binaryOp(.Multiply),
                .OpDivide => try self.binaryOp(.Divide),
                .OpJumpIfFalse => {
                    const offset = self.readShort();
                    if (!self.peek(0).toBool()) {
                        self.ip += offset;
                    }
                },
                .OpJump => {
                    const offset = self.readShort();
                    self.ip += offset;
                },
                .OpReturn => {
                    return self.pop();
                },
                else => {
                    std.debug.print("Unknown opcode: {}\n", .{instruction});
                    return error.UnknownOpcode;
                }
            }
        }
        return error.ExecutionFinishedUnexpectedly;
    }

    fn push(self: *VM, value: Value) !void {
        if (((@intFromPtr(self.stack_top) - @intFromPtr(&self.stack[0])) / @sizeOf(Value)) >= STACK_MAX) {
            return error.StackOverflow;
        }
        self.stack_top.* = value;
        self.stack_top = @ptrFromInt(@intFromPtr(self.stack_top) + @sizeOf(Value));
    }

    fn pop(self: *VM) Value {
        self.stack_top = @ptrFromInt(@intFromPtr(self.stack_top) - @sizeOf(Value));
        return self.stack_top.*;
    }

    fn peek(self: *VM, distance: usize) Value {
        const index = (@intFromPtr(self.stack_top) - @intFromPtr(&self.stack[0])) / @sizeOf(Value) - 1 - distance;
        return self.stack[index];
    }

    fn readShort(self: *VM) u16 {
        self.ip += 2;
        return (@as(u16, self.chunk.code.items[self.ip - 2]) << 8) | @as(u16, self.chunk.code.items[self.ip - 1]);
    }

    const BinaryOpType = enum { Add, Subtract, Multiply, Divide, Greater, Less };

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
                .Greater => Value.initBool(a.data.integer > b.data.integer),
                .Less => Value.initBool(a.data.integer < b.data.integer),
            };
            try self.push(result);
        } else {
            return error.InvalidTypesForBinaryOperation;
        }
    }
};
