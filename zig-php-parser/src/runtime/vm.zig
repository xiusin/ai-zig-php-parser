const std = @import("std");
const bytecode = @import("../compiler/bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = @import("types.zig").Value;
const Function = @import("types.zig").UserFunction;

const FRAMES_MAX = 64;
const STACK_MAX = FRAMES_MAX * 256;

const CallFrame = struct {
    function: *Function,
    ip: usize,
    slots: [*]Value,
};

pub const VM = struct {
    frames: [FRAMES_MAX]CallFrame,
    frame_count: usize,
    stack: [STACK_MAX]Value,
    stack_top: *Value,
    globals: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) VM {
        var vm = VM{
            .frames = undefined,
            .frame_count = 0,
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

    pub fn interpret(self: *VM, function: *Function) !Value {
        try self.push(Value{ .user_function = function });
        try self.call(function, 0);
        return self.run();
    }

    fn run(self: *VM) !Value {
        var frame = &self.frames[self.frame_count - 1];

        while (frame.ip < frame.function.chunk.code.items.len) {
            const instruction = frame.function.chunk.code.items[frame.ip];
            frame.ip += 1;

            switch (@as(OpCode, @enumFromInt(instruction))) {
                .OpConstant => {
                    const constant_index = frame.function.chunk.code.items[frame.ip];
                    frame.ip += 1;
                    const constant = frame.function.chunk.constants.items[constant_index];
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
                    const offset = self.readShort(frame);
                    if (!self.peek(0).toBool()) {
                        frame.ip += offset;
                    }
                },
                .OpJump => {
                    const offset = self.readShort(frame);
                    frame.ip += offset;
                },
                .OpLoop => {
                    const offset = self.readShort(frame);
                    frame.ip -= offset;
                },
                .OpCall => {
                    const arg_count = frame.function.chunk.code.items[frame.ip];
                    frame.ip += 1;

                    const callee = self.peek(@intCast(arg_count));
                    if (callee.tag != .user_function) {
                        return error.InvalidCallee;
                    }
                    try self.call(callee.data.user_function, arg_count);
                    frame = &self.frames[self.frame_count - 1];
                },
                .OpReturn => {
                    const result = self.pop();
                    self.frame_count -= 1;
                    if (self.frame_count == 0) {
                        _ = self.pop();
                        return result;
                    }

                    self.stack_top = frame.slots;
                    try self.push(result);
                    frame = &self.frames[self.frame_count - 1];
                },
                else => {
                    std.debug.print("Unknown opcode: {}\n", .{instruction});
                    return error.UnknownOpcode;
                }
            }
        }
        return error.ExecutionFinishedUnexpectedly;
    }

    fn call(self: *VM, function: *Function, arg_count: u8) !void {
        if (arg_count != function.arity) {
            return error.ArgumentMismatch;
        }

        if (self.frame_count == FRAMES_MAX) {
            return error.StackOverflow;
        }

        var frame = &self.frames[self.frame_count];
        self.frame_count += 1;

        frame.function = function;
        frame.ip = 0;
        frame.slots = self.stack_top - arg_count - 1;
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

    fn readShort(_: *VM, frame: *CallFrame) u16 {
        frame.ip += 2;
        return (@as(u16, frame.function.chunk.code.items[frame.ip - 2]) << 8) | @as(u16, frame.function.chunk.code.items[frame.ip - 1]);
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
