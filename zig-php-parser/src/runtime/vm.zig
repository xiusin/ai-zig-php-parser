const std = @import("std");
const main = @import("../main.zig");
const bytecode = main.compiler.bytecode;
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = main.runtime.types.Value;

const STACK_MAX = 256;
const FRAMES_MAX = 64;

const CallFrame = struct {
    function: *main.runtime.types.UserFunction,
    ip: usize,
    slots: usize,
};

pub const VM = struct {
    frames: [FRAMES_MAX]CallFrame,
    frame_count: usize,

    stack: [STACK_MAX]Value,
    stack_top: usize,
    globals: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) VM {
        return VM{
            .frames = undefined,
            .frame_count = 0,
            .stack = undefined,
            .stack_top = 0,
            .globals = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VM) void {
        // Free any remaining objects on the stack
        while (self.stack_top > 0) {
            const val = self.pop();
            self.releaseValue(val);
        }

        var it = self.globals.iterator();
        while (it.next()) |entry| {
            self.releaseValue(entry.value_ptr.*);
        }
        self.globals.deinit();
    }

    fn releaseValue(self: *VM, value: Value) void {
        switch (value.tag) {
            .string => {
                // This is simplistic. With a proper GC or RC, this would be a decrement.
                self.allocator.destroy(value.data.string.data);
                self.allocator.destroy(value.data.string);
            },
            .user_function => {
                // Also simplistic. Assumes function is heap allocated.
                value.data.user_function.deinit(self.allocator);
                self.allocator.destroy(value.data.user_function);
            },
            else => {},
        }
    }

    pub fn interpret(self: *VM, main_function: *main.runtime.types.UserFunction) !Value {
        if (self.frame_count >= FRAMES_MAX) return error.StackOverflow;

        self.frames[self.frame_count] = CallFrame{
            .function = main_function,
            .ip = 0,
            .slots = 0,
        };
        self.frame_count += 1;

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
                .OpPop => {
                    _ = self.pop();
                },
                .OpAdd => try self.binaryOp(.Add),
                .OpSubtract => try self.binaryOp(.Subtract),
                .OpMultiply => try self.binaryOp(.Multiply),
                .OpDivide => try self.binaryOp(.Divide),
                .OpSetGlobal => {
                    const constant_index = frame.function.chunk.code.items[frame.ip];
                    frame.ip += 1;
                    const var_name = frame.function.chunk.constants.items[constant_index].data.string.data.data;
                    try self.globals.put(var_name, self.peek(0));
                },
                .OpGetGlobal => {
                    const constant_index = frame.function.chunk.code.items[frame.ip];
                    frame.ip += 1;
                    const var_name = frame.function.chunk.constants.items[constant_index].data.string.data.data;
                    if (self.globals.get(var_name)) |value| {
                        try self.push(value);
                    } else {
                        return error.UndefinedVariable;
                    }
                },
                .OpGetLocal => {
                    const slot = frame.function.chunk.code.items[frame.ip];
                    frame.ip += 1;
                    try self.push(self.stack[frame.slots + slot]);
                },
                .OpSetLocal => {
                    const slot = frame.function.chunk.code.items[frame.ip];
                    frame.ip += 1;
                    self.stack[frame.slots + slot] = self.peek(0);
                },
                .OpCall => {
                    const arg_count = frame.function.chunk.code.items[frame.ip];
                    frame.ip += 1;

                    const callee_value = self.peek(arg_count);
                    if (callee_value.tag != .user_function) {
                        return error.NotAFunction;
                    }
                    const function: *main.runtime.types.UserFunction = @ptrCast(callee_value.data.user_function);

                    if (arg_count != function.arity) {
                        // TODO: more specific error
                        return error.ArgumentCountMismatch;
                    }

                    if (self.frame_count == FRAMES_MAX) {
                        return error.StackOverflow;
                    }

                    self.frame_count += 1;
                    frame = &self.frames[self.frame_count - 1];
                    frame.* = CallFrame {
                        .function = function,
                        .ip = 0,
                        .slots = self.stack_top - arg_count - 1,
                    };
                },
                .OpReturn => {
                    const result = self.pop();
                    self.frame_count -= 1;

                    if (self.frame_count == 0) {
                        _ = self.pop(); // Pop the main script function
                        return result;
                    }

                    // Discard the function's stack frame
                    self.stack_top = frame.slots;
                    try self.push(result);

                    // Update the local `frame` variable to the new top frame
                    frame = &self.frames[self.frame_count - 1];
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

        switch (a.tag) {
            .integer => switch (b.tag) {
                .integer => {
                    const result = switch (op) {
                        .Add => Value.initInt(a.data.integer + b.data.integer),
                        .Subtract => Value.initInt(a.data.integer - b.data.integer),
                        .Multiply => Value.initInt(a.data.integer * b.data.integer),
                        .Divide => {
                            if (b.data.integer == 0) return error.DivisionByZero;
                            return Value.initFloat(@as(f64, @floatFromInt(a.data.integer)) / @as(f64, @floatFromInt(b.data.integer)));
                        },
                    };
                    return self.push(result);
                },
                .float => {
                    const a_float = @as(f64, @floatFromInt(a.data.integer));
                    const result = switch (op) {
                        .Add => Value.initFloat(a_float + b.data.float),
                        .Subtract => Value.initFloat(a_float - b.data.float),
                        .Multiply => Value.initFloat(a_float * b.data.float),
                        .Divide => {
                            if (b.data.float == 0.0) return error.DivisionByZero;
                            return Value.initFloat(a_float / b.data.float);
                        },
                    };
                    return self.push(result);
                },
                else => return error.InvalidTypesForBinaryOperation,
            },
            .float => switch (b.tag) {
                .integer => {
                    const b_float = @as(f64, @floatFromInt(b.data.integer));
                    const result = switch (op) {
                        .Add => Value.initFloat(a.data.float + b_float),
                        .Subtract => Value.initFloat(a.data.float - b_float),
                        .Multiply => Value.initFloat(a.data.float * b_float),
                        .Divide => {
                            if (b_float == 0.0) return error.DivisionByZero;
                            return Value.initFloat(a.data.float / b_float);
                        },
                    };
                    return self.push(result);
                },
                .float => {
                    const result = switch (op) {
                        .Add => Value.initFloat(a.data.float + b.data.float),
                        .Subtract => Value.initFloat(a.data.float - b.data.float),
                        .Multiply => Value.initFloat(a.data.float * b.data.float),
                        .Divide => {
                            if (b.data.float == 0.0) return error.DivisionByZero;
                            return Value.initFloat(a.data.float / b.data.float);
                        },
                    };
                    return self.push(result);
                },
                else => return error.InvalidTypesForBinaryOperation,
            },
            else => return error.InvalidTypesForBinaryOperation,
        }
    }
};
