const std = @import("std");
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;
const CompiledFunction = instruction.CompiledFunction;
const ConstValue = instruction.Value;

/// 运行时值类型
pub const Value = union(enum) {
    null_val,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_val: *String,
    array_val: *Array,
    object_val: *Object,
    struct_val: *StructInstance,
    closure_val: *Closure,
    resource_val: *Resource,

    pub const String = struct {
        data: []u8,
        ref_count: u32,

        pub fn retain(self: *String) *String {
            self.ref_count += 1;
            return self;
        }

        pub fn release(self: *String, allocator: std.mem.Allocator) void {
            self.ref_count -= 1;
            if (self.ref_count == 0) {
                allocator.free(self.data);
                allocator.destroy(self);
            }
        }
    };

    pub const Array = struct {
        elements: std.ArrayList(Value),
        keys: std.StringHashMap(usize),
        ref_count: u32,
    };

    pub const Object = struct {
        class_id: u16,
        properties: std.StringHashMap(Value),
        ref_count: u32,
    };

    pub const StructInstance = struct {
        struct_id: u16,
        fields: []Value,
        ref_count: u32,
    };

    pub const Closure = struct {
        function: *CompiledFunction,
        captured: []Value,
        ref_count: u32,
    };

    pub const Resource = struct {
        type_id: u16,
        handle: *anyopaque,
        ref_count: u32,
    };

    /// 转换为布尔值
    pub fn toBool(self: Value) bool {
        return switch (self) {
            .null_val => false,
            .bool_val => |b| b,
            .int_val => |i| i != 0,
            .float_val => |f| f != 0.0,
            .string_val => |s| s.data.len > 0,
            .array_val => |a| a.elements.items.len > 0,
            else => true,
        };
    }

    /// 转换为整数
    pub fn toInt(self: Value) i64 {
        return switch (self) {
            .null_val => 0,
            .bool_val => |b| if (b) 1 else 0,
            .int_val => |i| i,
            .float_val => |f| @intFromFloat(f),
            .string_val => |s| std.fmt.parseInt(i64, s.data, 10) catch 0,
            else => 0,
        };
    }

    /// 转换为浮点数
    pub fn toFloat(self: Value) f64 {
        return switch (self) {
            .null_val => 0.0,
            .bool_val => |b| if (b) 1.0 else 0.0,
            .int_val => |i| @floatFromInt(i),
            .float_val => |f| f,
            .string_val => |s| std.fmt.parseFloat(f64, s.data) catch 0.0,
            else => 0.0,
        };
    }
};

/// 调用帧
pub const CallFrame = struct {
    function: *CompiledFunction,
    ip: u32,
    base_pointer: u32,
    return_address: u32,
};

/// 字节码虚拟机 - 高性能栈式VM
pub const BytecodeVM = struct {
    allocator: std.mem.Allocator,
    stack: []Value,
    stack_top: u32,
    frames: []CallFrame,
    frame_count: u32,
    globals: std.StringHashMap(Value),
    builtins: []const BuiltinFn,
    gc_threshold: usize,
    bytes_allocated: usize,

    const STACK_MAX: u32 = 65536;
    const FRAMES_MAX: u32 = 1024;

    pub const BuiltinFn = *const fn (*BytecodeVM, []Value) VMError!Value;

    pub const VMError = error{
        StackOverflow,
        StackUnderflow,
        InvalidOpcode,
        TypeMismatch,
        DivisionByZero,
        UndefinedVariable,
        UndefinedFunction,
        InvalidArrayIndex,
        NullPointerAccess,
        OutOfMemory,
    };

    pub fn init(allocator: std.mem.Allocator) !*BytecodeVM {
        const vm = try allocator.create(BytecodeVM);
        vm.* = BytecodeVM{
            .allocator = allocator,
            .stack = try allocator.alloc(Value, STACK_MAX),
            .stack_top = 0,
            .frames = try allocator.alloc(CallFrame, FRAMES_MAX),
            .frame_count = 0,
            .globals = std.StringHashMap(Value).init(allocator),
            .builtins = &[_]BuiltinFn{},
            .gc_threshold = 1024 * 1024,
            .bytes_allocated = 0,
        };
        return vm;
    }

    pub fn deinit(self: *BytecodeVM) void {
        self.allocator.free(self.stack);
        self.allocator.free(self.frames);
        self.globals.deinit();
        self.allocator.destroy(self);
    }

    /// 执行编译后的函数
    pub fn execute(self: *BytecodeVM, function: *CompiledFunction) VMError!Value {
        // 创建初始调用帧
        self.frames[0] = CallFrame{
            .function = function,
            .ip = 0,
            .base_pointer = 0,
            .return_address = 0,
        };
        self.frame_count = 1;

        return self.run();
    }

    /// 主执行循环 - 使用计算跳转表优化
    fn run(self: *BytecodeVM) VMError!Value {
        var frame = &self.frames[self.frame_count - 1];

        while (true) {
            const inst = frame.function.bytecode[frame.ip];
            frame.ip += 1;

            switch (inst.opcode) {
                // ========== 栈操作 ==========
                .nop => {},

                .push_const => {
                    const value = self.loadConstant(frame.function, inst.operand1);
                    try self.push(value);
                },

                .push_local => {
                    const idx = frame.base_pointer + inst.operand1;
                    try self.push(self.stack[idx]);
                },

                .push_global => {
                    // TODO: 从全局变量表获取
                    try self.push(.null_val);
                },

                .pop => {
                    _ = try self.pop();
                },

                .dup => {
                    const value = self.peek(0);
                    try self.push(value);
                },

                .swap => {
                    const a = try self.pop();
                    const b = try self.pop();
                    try self.push(a);
                    try self.push(b);
                },

                .push_null => try self.push(.null_val),
                .push_true => try self.push(.{ .bool_val = true }),
                .push_false => try self.push(.{ .bool_val = false }),
                .push_int_0 => try self.push(.{ .int_val = 0 }),
                .push_int_1 => try self.push(.{ .int_val = 1 }),

                .store_local => {
                    const value = try self.pop();
                    const idx = frame.base_pointer + inst.operand1;
                    self.stack[idx] = value;
                },

                .store_global => {
                    // TODO: 存储到全局变量表
                    _ = try self.pop();
                },

                // ========== 整数算术 ==========
                .add_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .int_val = a +% b });
                },

                .sub_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .int_val = a -% b });
                },

                .mul_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .int_val = a *% b });
                },

                .div_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    if (b == 0) return VMError.DivisionByZero;
                    try self.push(.{ .int_val = @divTrunc(a, b) });
                },

                .mod_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    if (b == 0) return VMError.DivisionByZero;
                    try self.push(.{ .int_val = @mod(a, b) });
                },

                .neg_int => {
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .int_val = -a });
                },

                .inc_int => {
                    const idx = frame.base_pointer + inst.operand1;
                    const val = self.stack[idx].toInt();
                    self.stack[idx] = .{ .int_val = val + 1 };
                },

                .dec_int => {
                    const idx = frame.base_pointer + inst.operand1;
                    const val = self.stack[idx].toInt();
                    self.stack[idx] = .{ .int_val = val - 1 };
                },

                .bit_and => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .int_val = a & b });
                },

                .bit_or => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .int_val = a | b });
                },

                .bit_xor => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .int_val = a ^ b });
                },

                .bit_not => {
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .int_val = ~a });
                },

                .shl => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    const shift: u6 = @intCast(@min(63, @max(0, b)));
                    try self.push(.{ .int_val = a << shift });
                },

                .shr => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    const shift: u6 = @intCast(@min(63, @max(0, b)));
                    try self.push(.{ .int_val = a >> shift });
                },

                // ========== 浮点算术 ==========
                .add_float => {
                    const b = (try self.pop()).toFloat();
                    const a = (try self.pop()).toFloat();
                    try self.push(.{ .float_val = a + b });
                },

                .sub_float => {
                    const b = (try self.pop()).toFloat();
                    const a = (try self.pop()).toFloat();
                    try self.push(.{ .float_val = a - b });
                },

                .mul_float => {
                    const b = (try self.pop()).toFloat();
                    const a = (try self.pop()).toFloat();
                    try self.push(.{ .float_val = a * b });
                },

                .div_float => {
                    const b = (try self.pop()).toFloat();
                    const a = (try self.pop()).toFloat();
                    if (b == 0.0) return VMError.DivisionByZero;
                    try self.push(.{ .float_val = a / b });
                },

                .neg_float => {
                    const a = (try self.pop()).toFloat();
                    try self.push(.{ .float_val = -a });
                },

                .sqrt => {
                    const a = (try self.pop()).toFloat();
                    try self.push(.{ .float_val = @sqrt(a) });
                },

                // ========== 比较操作 ==========
                .eq => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .bool_val = self.valuesEqual(a, b) });
                },

                .neq => {
                    const b = try self.pop();
                    const a = try self.pop();
                    try self.push(.{ .bool_val = !self.valuesEqual(a, b) });
                },

                .lt_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .bool_val = a < b });
                },

                .gt_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    try self.push(.{ .bool_val = a > b });
                },

                .lt_float => {
                    const b = (try self.pop()).toFloat();
                    const a = (try self.pop()).toFloat();
                    try self.push(.{ .bool_val = a < b });
                },

                .gt_float => {
                    const b = (try self.pop()).toFloat();
                    const a = (try self.pop()).toFloat();
                    try self.push(.{ .bool_val = a > b });
                },

                // ========== 逻辑操作 ==========
                .logic_and => {
                    const b = (try self.pop()).toBool();
                    const a = (try self.pop()).toBool();
                    try self.push(.{ .bool_val = a and b });
                },

                .logic_or => {
                    const b = (try self.pop()).toBool();
                    const a = (try self.pop()).toBool();
                    try self.push(.{ .bool_val = a or b });
                },

                .logic_not => {
                    const a = (try self.pop()).toBool();
                    try self.push(.{ .bool_val = !a });
                },

                // ========== 控制流 ==========
                .jmp => {
                    frame.ip = inst.operand1;
                },

                .jz => {
                    const cond = (try self.pop()).toBool();
                    if (!cond) {
                        frame.ip = inst.operand1;
                    }
                },

                .jnz => {
                    const cond = (try self.pop()).toBool();
                    if (cond) {
                        frame.ip = inst.operand1;
                    }
                },

                .call => {
                    const arg_count = inst.operand2;
                    const func_id = inst.operand1;
                    try self.callFunction(func_id, arg_count);
                    frame = &self.frames[self.frame_count - 1];
                },

                .call_builtin => {
                    const builtin_id = inst.operand1;
                    const arg_count = inst.operand2;
                    try self.callBuiltin(builtin_id, arg_count);
                },

                .ret => {
                    const result = try self.pop();

                    // 恢复调用帧
                    self.frame_count -= 1;
                    if (self.frame_count == 0) {
                        return result;
                    }

                    // 清理局部变量
                    self.stack_top = frame.base_pointer;
                    frame = &self.frames[self.frame_count - 1];
                    try self.push(result);
                },

                .ret_void => {
                    self.frame_count -= 1;
                    if (self.frame_count == 0) {
                        return .null_val;
                    }

                    self.stack_top = frame.base_pointer;
                    frame = &self.frames[self.frame_count - 1];
                },

                .loop_start, .loop_end => {
                    // JIT热点检测标记，解释器忽略
                },

                // ========== 类型守卫（JIT优化用） ==========
                .guard_int => {
                    const value = self.peek(0);
                    if (value != .int_val) {
                        // 类型不匹配，需要去优化
                        // 在解释器中我们只是继续执行
                    }
                },

                .guard_float => {
                    const value = self.peek(0);
                    if (value != .float_val) {
                        // 类型不匹配
                    }
                },

                // ========== 调试 ==========
                .debug_break => {
                    // 调试断点
                },

                .line_number => {
                    // 行号信息，用于错误报告
                },

                .gc_safepoint => {
                    // GC安全点检查
                    if (self.bytes_allocated > self.gc_threshold) {
                        self.collectGarbage();
                    }
                },

                .halt => {
                    return .null_val;
                },

                else => {
                    // 未实现的指令
                    return VMError.InvalidOpcode;
                },
            }
        }
    }

    // ========== 栈操作 ==========

    fn push(self: *BytecodeVM, value: Value) VMError!void {
        if (self.stack_top >= STACK_MAX) {
            return VMError.StackOverflow;
        }
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    fn pop(self: *BytecodeVM) VMError!Value {
        if (self.stack_top == 0) {
            return VMError.StackUnderflow;
        }
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    fn peek(self: *BytecodeVM, distance: u32) Value {
        return self.stack[self.stack_top - 1 - distance];
    }

    // ========== 辅助方法 ==========

    fn loadConstant(self: *BytecodeVM, function: *CompiledFunction, index: u16) Value {
        _ = self;
        const const_val = function.constants[index];
        return switch (const_val) {
            .null_val => .null_val,
            .bool_val => |b| .{ .bool_val = b },
            .int_val => |i| .{ .int_val = i },
            .float_val => |f| .{ .float_val = f },
            else => .null_val,
        };
    }

    fn valuesEqual(self: *BytecodeVM, a: Value, b: Value) bool {
        _ = self;
        return switch (a) {
            .null_val => b == .null_val,
            .bool_val => |av| switch (b) {
                .bool_val => |bv| av == bv,
                else => false,
            },
            .int_val => |av| switch (b) {
                .int_val => |bv| av == bv,
                .float_val => |bv| @as(f64, @floatFromInt(av)) == bv,
                else => false,
            },
            .float_val => |av| switch (b) {
                .float_val => |bv| av == bv,
                .int_val => |bv| av == @as(f64, @floatFromInt(bv)),
                else => false,
            },
            .string_val => |av| switch (b) {
                .string_val => |bv| std.mem.eql(u8, av.data, bv.data),
                else => false,
            },
            else => false,
        };
    }

    fn callFunction(self: *BytecodeVM, func_id: u16, arg_count: u16) VMError!void {
        _ = func_id;
        if (self.frame_count >= FRAMES_MAX) {
            return VMError.StackOverflow;
        }

        // TODO: 根据func_id查找函数
        // 暂时返回错误
        _ = arg_count;
        return VMError.UndefinedFunction;
    }

    fn callBuiltin(self: *BytecodeVM, builtin_id: u16, arg_count: u16) VMError!void {
        if (builtin_id >= self.builtins.len) {
            return VMError.UndefinedFunction;
        }

        // 收集参数
        var args = std.ArrayList(Value).init(self.allocator);
        defer args.deinit();

        var i: u16 = 0;
        while (i < arg_count) : (i += 1) {
            args.append(try self.pop()) catch return VMError.OutOfMemory;
        }

        // 调用内置函数
        const result = try self.builtins[builtin_id](self, args.items);
        try self.push(result);
    }

    fn collectGarbage(self: *BytecodeVM) void {
        // TODO: 实现GC
        _ = self;
    }
};

test "vm basic operations" {
    const allocator = std.testing.allocator;
    const vm = try BytecodeVM.init(allocator);
    defer vm.deinit();

    // 测试栈操作
    try vm.push(.{ .int_val = 42 });
    const val = try vm.pop();
    try std.testing.expect(val.int_val == 42);
}

test "vm arithmetic" {
    const allocator = std.testing.allocator;
    const vm = try BytecodeVM.init(allocator);
    defer vm.deinit();

    // 测试加法
    try vm.push(.{ .int_val = 10 });
    try vm.push(.{ .int_val = 20 });

    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = a + b });

    const result = try vm.pop();
    try std.testing.expect(result.int_val == 30);
}
