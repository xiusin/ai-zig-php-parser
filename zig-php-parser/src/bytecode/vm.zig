const std = @import("std");
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;
const CompiledFunction = instruction.CompiledFunction;
const ConstValue = instruction.Value;

// 类型反馈系统
const type_feedback = @import("../runtime/type_feedback.zig");
const TypeTag = type_feedback.TypeTag;
const TypeFeedback = type_feedback.TypeFeedback;
const TypeFeedbackCollector = type_feedback.TypeFeedbackCollector;

// 内联缓存优化
const optimization = @import("../runtime/optimization.zig");
const MethodCache = optimization.MethodCache;

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
        elements: std.ArrayListUnmanaged(Value),
        keys: std.StringHashMapUnmanaged(usize),
        ref_count: u32,
    };

    pub const Object = struct {
        class_id: u16,
        properties: std.StringHashMapUnmanaged(Value),
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

    /// 获取类型标签（用于类型反馈系统）
    pub fn getTypeTag(self: Value) TypeTag {
        return switch (self) {
            .null_val => .null_type,
            .bool_val => .bool_type,
            .int_val => .int_type,
            .float_val => .float_type,
            .string_val => .string_type,
            .array_val => .array_type,
            .object_val => .object_type,
            .struct_val => .struct_type,
            .closure_val => .closure_type,
            .resource_val => .resource_type,
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

/// 指令分发结果 - 用于计算跳转表优化
pub const DispatchResult = union(enum) {
    /// 继续执行下一条指令
    continue_execution,
    /// 返回值（函数返回）
    return_value: Value,
    /// 调用帧已改变（call/ret指令）
    frame_changed,
    /// 跳转到指定地址
    jump_to: u32,
};

/// 指令处理函数类型
pub const DispatchFn = *const fn (*BytecodeVM, *CallFrame, Instruction) BytecodeVM.VMError!DispatchResult;

/// 字节码虚拟机 - 高性能栈式VM
pub const BytecodeVM = struct {
    allocator: std.mem.Allocator,
    stack: []Value,
    stack_top: u32,
    frames: []CallFrame,
    frame_count: u32,
    globals: std.StringHashMapUnmanaged(Value),
    global_names: std.ArrayListUnmanaged([]const u8),
    functions: std.StringHashMapUnmanaged(*CompiledFunction),
    /// 函数表 - 按索引查找函数（用于func_ref）
    function_table: std.ArrayListUnmanaged(*CompiledFunction),
    builtins: std.StringHashMapUnmanaged(BuiltinFn),
    string_pool: std.ArrayListUnmanaged(*Value.String),
    array_pool: std.ArrayListUnmanaged(*Value.Array),
    object_pool: std.ArrayListUnmanaged(*Value.Object),
    /// 临时字符串池 - 用于跟踪valueToString分配的临时字符串
    temp_strings: std.ArrayListUnmanaged([]u8),
    gc_threshold: usize,
    bytes_allocated: usize,
    output_buffer: std.ArrayListUnmanaged(u8),

    // 类型反馈系统
    type_feedback_collector: TypeFeedbackCollector,
    /// 是否启用类型反馈收集
    enable_type_feedback: bool,
    /// 去优化计数器（用于统计）
    deopt_count: u32,

    // 内联缓存系统
    method_cache: MethodCache,
    /// 是否启用内联缓存
    enable_inline_cache: bool,

    const STACK_MAX: u32 = 65536;
    const FRAMES_MAX: u32 = 1024;

    pub const BuiltinFn = *const fn (*BytecodeVM, []Value) VMError!Value;

    /// 计算跳转表 - 256个函数指针，按OpCode索引
    const dispatch_table: [256]DispatchFn = initDispatchTable();

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
            .globals = .{},
            .global_names = .{},
            .functions = .{},
            .function_table = .{},
            .builtins = .{},
            .string_pool = .{},
            .array_pool = .{},
            .object_pool = .{},
            .temp_strings = .{},
            .gc_threshold = 1024 * 1024,
            .bytes_allocated = 0,
            .output_buffer = .{},
            // 类型反馈系统
            .type_feedback_collector = TypeFeedbackCollector.init(allocator),
            .enable_type_feedback = true,
            .deopt_count = 0,
            // 内联缓存系统
            .method_cache = MethodCache.init(allocator),
            .enable_inline_cache = true,
        };

        // 注册内置函数
        try vm.registerBuiltins();

        return vm;
    }

    /// 注册内置函数
    fn registerBuiltins(self: *BytecodeVM) !void {
        try self.builtins.put(self.allocator, "echo", builtinEcho);
        try self.builtins.put(self.allocator, "print", builtinPrint);
        try self.builtins.put(self.allocator, "var_dump", builtinVarDump);
        try self.builtins.put(self.allocator, "strlen", builtinStrlen);
        try self.builtins.put(self.allocator, "count", builtinCount);
        try self.builtins.put(self.allocator, "array_push", builtinArrayPush);
        try self.builtins.put(self.allocator, "array_pop", builtinArrayPop);
        try self.builtins.put(self.allocator, "isset", builtinIsset);
        try self.builtins.put(self.allocator, "is_null", builtinIsNull);
        try self.builtins.put(self.allocator, "is_int", builtinIsInt);
        try self.builtins.put(self.allocator, "is_string", builtinIsString);
        try self.builtins.put(self.allocator, "is_array", builtinIsArray);
    }

    pub fn deinit(self: *BytecodeVM) void {
        // 释放临时字符串池
        for (self.temp_strings.items) |str| {
            self.allocator.free(str);
        }
        self.temp_strings.deinit(self.allocator);

        // 释放字符串池
        for (self.string_pool.items) |str| {
            self.allocator.free(str.data);
            self.allocator.destroy(str);
        }
        self.string_pool.deinit(self.allocator);

        // 释放数组池
        for (self.array_pool.items) |arr| {
            arr.elements.deinit(self.allocator);
            arr.keys.deinit(self.allocator);
            self.allocator.destroy(arr);
        }
        self.array_pool.deinit(self.allocator);

        // 释放对象池
        for (self.object_pool.items) |obj| {
            obj.properties.deinit(self.allocator);
            self.allocator.destroy(obj);
        }
        self.object_pool.deinit(self.allocator);

        // 释放类型反馈收集器
        self.type_feedback_collector.deinit();

        // 释放内联缓存
        self.method_cache.deinit();

        self.allocator.free(self.stack);
        self.allocator.free(self.frames);
        self.globals.deinit(self.allocator);
        self.global_names.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.function_table.deinit(self.allocator);
        self.builtins.deinit(self.allocator);
        self.output_buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// 注册编译后的函数
    pub fn registerFunction(self: *BytecodeVM, name: []const u8, func: *CompiledFunction) !void {
        try self.functions.put(self.allocator, name, func);
        // 同时添加到函数表，返回索引
        try self.function_table.append(self.allocator, func);
    }

    /// 通过索引获取函数
    pub fn getFunctionByIndex(self: *BytecodeVM, index: u16) ?*CompiledFunction {
        if (index < self.function_table.items.len) {
            return self.function_table.items[index];
        }
        return null;
    }

    /// 通过名称获取函数索引
    pub fn getFunctionIndex(self: *BytecodeVM, name: []const u8) ?u16 {
        if (self.functions.get(name)) |func| {
            for (self.function_table.items, 0..) |f, i| {
                if (f == func) {
                    return @intCast(i);
                }
            }
        }
        return null;
    }

    /// 通过名称调用函数
    pub fn call(self: *BytecodeVM, name: []const u8, args: []const Value) VMError!Value {
        _ = args; // TODO: 处理参数
        if (self.functions.get(name)) |func| {
            return self.execute(func);
        }
        return VMError.UndefinedFunction;
    }

    /// 设置全局变量
    pub fn setGlobal(self: *BytecodeVM, name: []const u8, value: Value) !void {
        try self.globals.put(self.allocator, name, value);
    }

    /// 获取全局变量
    pub fn getGlobal(self: *BytecodeVM, name: []const u8) ?Value {
        return self.globals.get(name);
    }

    /// 创建字符串
    pub fn createString(self: *BytecodeVM, data: []const u8) !*Value.String {
        const str = try self.allocator.create(Value.String);
        str.* = .{
            .data = try self.allocator.dupe(u8, data),
            .ref_count = 1,
        };
        try self.string_pool.append(self.allocator, str);
        self.bytes_allocated += data.len + @sizeOf(Value.String);
        return str;
    }

    /// 创建数组
    pub fn createArray(self: *BytecodeVM) !*Value.Array {
        const arr = try self.allocator.create(Value.Array);
        arr.* = .{
            .elements = .{},
            .keys = .{},
            .ref_count = 1,
        };
        try self.array_pool.append(self.allocator, arr);
        self.bytes_allocated += @sizeOf(Value.Array);
        return arr;
    }

    /// 创建对象
    pub fn createObject(self: *BytecodeVM, class_id: u16) !*Value.Object {
        const obj = try self.allocator.create(Value.Object);
        obj.* = .{
            .class_id = class_id,
            .properties = .{},
            .ref_count = 1,
        };
        try self.object_pool.append(self.allocator, obj);
        self.bytes_allocated += @sizeOf(Value.Object);
        return obj;
    }

    /// 获取输出缓冲区
    pub fn getOutput(self: *BytecodeVM) []const u8 {
        return self.output_buffer.items;
    }

    /// 清空输出缓冲区
    pub fn clearOutput(self: *BytecodeVM) void {
        self.output_buffer.clearRetainingCapacity();
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

        return self.runOptimized();
    }

    /// 主执行循环 - 使用计算跳转表优化
    /// 通过函数指针数组替代switch语句，减少分支预测失败
    fn runOptimized(self: *BytecodeVM) VMError!Value {
        var frame = &self.frames[self.frame_count - 1];

        while (true) {
            const inst = frame.function.bytecode[frame.ip];
            frame.ip += 1;

            // 使用计算跳转表分发指令
            const handler = dispatch_table[@intFromEnum(inst.opcode)];
            const result = try handler(self, frame, inst);

            switch (result) {
                .continue_execution => {},
                .return_value => |val| return val,
                .frame_changed => {
                    frame = &self.frames[self.frame_count - 1];
                },
                .jump_to => |addr| {
                    frame.ip = addr;
                },
            }
        }
    }

    /// 原始执行循环 - 保留作为回退路径
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
                    // 从全局变量表获取
                    const name_idx = inst.operand1;
                    if (name_idx < frame.function.constants.len) {
                        const name_val = frame.function.constants[name_idx];
                        if (name_val == .string_val) {
                            // 根据字符串名称查找全局变量
                            // 简化实现：返回null
                        }
                    }
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
                    // 存储到全局变量表
                    const value = try self.pop();
                    const name_idx = inst.operand1;
                    if (name_idx < frame.function.constants.len) {
                        const name_val = frame.function.constants[name_idx];
                        if (name_val == .string_val) {
                            // 根据字符串名称存储全局变量
                            _ = value;
                        }
                    }
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
                    if (b == 0) return BytecodeVM.VMError.DivisionByZero;
                    try self.push(.{ .int_val = @divTrunc(a, b) });
                },

                .mod_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    if (b == 0) return BytecodeVM.VMError.DivisionByZero;
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
                    if (b == 0.0) return BytecodeVM.VMError.DivisionByZero;
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

                // ========== 数组操作 ==========
                .new_array => {
                    // operand1 = 初始元素数量
                    const count = inst.operand1;
                    const arr = self.createArray() catch return BytecodeVM.VMError.OutOfMemory;

                    // 从栈上弹出元素并添加到数组（逆序）
                    if (count > 0) {
                        var i: u16 = 0;
                        while (i < count) : (i += 1) {
                            const val = try self.pop();
                            arr.elements.insert(self.allocator, 0, val) catch return BytecodeVM.VMError.OutOfMemory;
                        }
                    }
                    try self.push(.{ .array_val = arr });
                },

                .array_get => {
                    // 栈: [array, index] -> [value]
                    const index = try self.pop();
                    const arr_val = try self.pop();

                    switch (arr_val) {
                        .array_val => |arr| {
                            // 支持整数索引和字符串键
                            switch (index) {
                                .int_val => |idx| {
                                    const i: usize = if (idx >= 0) @intCast(idx) else 0;
                                    if (i < arr.elements.items.len) {
                                        try self.push(arr.elements.items[i]);
                                    } else {
                                        try self.push(.null_val);
                                    }
                                },
                                .string_val => |key| {
                                    if (arr.keys.get(key.data)) |i| {
                                        try self.push(arr.elements.items[i]);
                                    } else {
                                        try self.push(.null_val);
                                    }
                                },
                                else => try self.push(.null_val),
                            }
                        },
                        else => try self.push(.null_val),
                    }
                },

                .array_set => {
                    // 栈: [array, index, value] -> [array]
                    const value = try self.pop();
                    const index = try self.pop();
                    const arr_val = try self.pop();

                    switch (arr_val) {
                        .array_val => |arr| {
                            switch (index) {
                                .int_val => |idx| {
                                    const i: usize = if (idx >= 0) @intCast(idx) else 0;
                                    if (i < arr.elements.items.len) {
                                        arr.elements.items[i] = value;
                                    } else {
                                        // 扩展数组
                                        while (arr.elements.items.len < i) {
                                            arr.elements.append(self.allocator, .null_val) catch return BytecodeVM.VMError.OutOfMemory;
                                        }
                                        arr.elements.append(self.allocator, value) catch return BytecodeVM.VMError.OutOfMemory;
                                    }
                                },
                                .string_val => |key| {
                                    const key_copy = self.allocator.dupe(u8, key.data) catch return BytecodeVM.VMError.OutOfMemory;
                                    if (arr.keys.get(key.data)) |i| {
                                        arr.elements.items[i] = value;
                                    } else {
                                        const new_idx = arr.elements.items.len;
                                        arr.elements.append(self.allocator, value) catch return BytecodeVM.VMError.OutOfMemory;
                                        arr.keys.put(self.allocator, key_copy, new_idx) catch return BytecodeVM.VMError.OutOfMemory;
                                    }
                                },
                                else => {},
                            }
                            try self.push(.{ .array_val = arr });
                        },
                        else => try self.push(.null_val),
                    }
                },

                .array_push => {
                    // 栈: [array, value] -> [array]
                    const value = try self.pop();
                    const arr_val = try self.pop();

                    switch (arr_val) {
                        .array_val => |arr| {
                            arr.elements.append(self.allocator, value) catch return BytecodeVM.VMError.OutOfMemory;
                            try self.push(.{ .array_val = arr });
                        },
                        else => try self.push(.null_val),
                    }
                },

                .array_pop => {
                    // 栈: [array] -> [value]
                    const arr_val = try self.pop();

                    switch (arr_val) {
                        .array_val => |arr| {
                            if (arr.elements.items.len > 0) {
                                const val = arr.elements.pop() orelse .null_val;
                                try self.push(val);
                            } else {
                                try self.push(.null_val);
                            }
                        },
                        else => try self.push(.null_val),
                    }
                },

                .array_len => {
                    // 栈: [array] -> [int]
                    const arr_val = try self.pop();

                    switch (arr_val) {
                        .array_val => |arr| {
                            try self.push(.{ .int_val = @intCast(arr.elements.items.len) });
                        },
                        else => try self.push(.{ .int_val = 0 }),
                    }
                },

                .array_exists => {
                    // 栈: [array, key] -> [bool]
                    const key = try self.pop();
                    const arr_val = try self.pop();

                    switch (arr_val) {
                        .array_val => |arr| {
                            const exists = switch (key) {
                                .int_val => |idx| blk: {
                                    const i: usize = if (idx >= 0) @intCast(idx) else 0;
                                    break :blk i < arr.elements.items.len;
                                },
                                .string_val => |k| arr.keys.contains(k.data),
                                else => false,
                            };
                            try self.push(.{ .bool_val = exists });
                        },
                        else => try self.push(.{ .bool_val = false }),
                    }
                },

                .array_unset => {
                    // 栈: [array, key] -> [array]
                    const key = try self.pop();
                    const arr_val = try self.pop();

                    switch (arr_val) {
                        .array_val => |arr| {
                            switch (key) {
                                .int_val => |idx| {
                                    const i: usize = if (idx >= 0) @intCast(idx) else 0;
                                    if (i < arr.elements.items.len) {
                                        _ = arr.elements.orderedRemove(i);
                                    }
                                },
                                .string_val => |k| {
                                    if (arr.keys.get(k.data)) |i| {
                                        _ = arr.elements.orderedRemove(i);
                                        _ = arr.keys.remove(k.data);
                                        // 更新后续键的索引
                                        var iter = arr.keys.iterator();
                                        while (iter.next()) |entry| {
                                            if (entry.value_ptr.* > i) {
                                                entry.value_ptr.* -= 1;
                                            }
                                        }
                                    }
                                },
                                else => {},
                            }
                            try self.push(.{ .array_val = arr });
                        },
                        else => try self.push(.null_val),
                    }
                },

                // ========== 对象操作 ==========
                .new_object => {
                    // operand1 = class_id
                    const class_id = inst.operand1;
                    const obj = self.createObject(class_id) catch return BytecodeVM.VMError.OutOfMemory;
                    try self.push(.{ .object_val = obj });
                },

                .get_prop => {
                    // 栈: [object] -> [value]
                    // operand1 = 属性名在常量池中的索引
                    const obj_val = try self.pop();
                    const prop_idx = inst.operand1;

                    switch (obj_val) {
                        .object_val => |obj| {
                            // 从常量池获取属性名
                            if (prop_idx < frame.function.constants.len) {
                                const prop_const = frame.function.constants[prop_idx];
                                if (prop_const == .string_val) {
                                    const prop_name = prop_const.string_val;
                                    if (obj.properties.get(prop_name)) |val| {
                                        try self.push(val);
                                    } else {
                                        try self.push(.null_val);
                                    }
                                } else {
                                    try self.push(.null_val);
                                }
                            } else {
                                try self.push(.null_val);
                            }
                        },
                        else => try self.push(.null_val),
                    }
                },

                .set_prop => {
                    // 栈: [object, value] -> [object]
                    // operand1 = 属性名在常量池中的索引
                    const value = try self.pop();
                    const obj_val = try self.pop();
                    const prop_idx = inst.operand1;

                    switch (obj_val) {
                        .object_val => |obj| {
                            if (prop_idx < frame.function.constants.len) {
                                const prop_const = frame.function.constants[prop_idx];
                                if (prop_const == .string_val) {
                                    const prop_name = prop_const.string_val;
                                    obj.properties.put(self.allocator, prop_name, value) catch return BytecodeVM.VMError.OutOfMemory;
                                }
                            }
                            try self.push(.{ .object_val = obj });
                        },
                        else => try self.push(.null_val),
                    }
                },

                .instanceof => {
                    // 栈: [object] -> [bool]
                    // operand1 = class_id
                    const obj_val = try self.pop();
                    const class_id = inst.operand1;

                    switch (obj_val) {
                        .object_val => |obj| {
                            try self.push(.{ .bool_val = obj.class_id == class_id });
                        },
                        else => try self.push(.{ .bool_val = false }),
                    }
                },

                .clone => {
                    // 栈: [object] -> [cloned_object]
                    const obj_val = try self.pop();

                    switch (obj_val) {
                        .object_val => |obj| {
                            const cloned = self.createObject(obj.class_id) catch return BytecodeVM.VMError.OutOfMemory;
                            // 复制所有属性
                            var iter = obj.properties.iterator();
                            while (iter.next()) |entry| {
                                cloned.properties.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*) catch return BytecodeVM.VMError.OutOfMemory;
                            }
                            try self.push(.{ .object_val = cloned });
                        },
                        .array_val => |arr| {
                            const cloned = self.createArray() catch return BytecodeVM.VMError.OutOfMemory;
                            // 复制所有元素
                            for (arr.elements.items) |elem| {
                                cloned.elements.append(self.allocator, elem) catch return BytecodeVM.VMError.OutOfMemory;
                            }
                            // 复制键映射
                            var iter = arr.keys.iterator();
                            while (iter.next()) |entry| {
                                cloned.keys.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*) catch return BytecodeVM.VMError.OutOfMemory;
                            }
                            try self.push(.{ .array_val = cloned });
                        },
                        else => try self.push(obj_val),
                    }
                },

                // ========== 结构体操作 ==========
                .new_struct => {
                    // operand1 = struct_id, operand2 = field_count
                    const struct_id = inst.operand1;
                    const field_count = inst.operand2;

                    const instance = self.allocator.create(Value.StructInstance) catch return BytecodeVM.VMError.OutOfMemory;
                    instance.* = .{
                        .struct_id = struct_id,
                        .fields = self.allocator.alloc(Value, field_count) catch return BytecodeVM.VMError.OutOfMemory,
                        .ref_count = 1,
                    };

                    // 从栈上弹出字段值（逆序）
                    var i: usize = field_count;
                    while (i > 0) {
                        i -= 1;
                        instance.fields[i] = try self.pop();
                    }

                    try self.push(.{ .struct_val = instance });
                },

                .struct_get => {
                    // 栈: [struct] -> [value]
                    // operand1 = field_index
                    const struct_val = try self.pop();
                    const field_idx = inst.operand1;

                    switch (struct_val) {
                        .struct_val => |s| {
                            if (field_idx < s.fields.len) {
                                try self.push(s.fields[field_idx]);
                            } else {
                                try self.push(.null_val);
                            }
                        },
                        else => try self.push(.null_val),
                    }
                },

                .struct_set => {
                    // 栈: [struct, value] -> [struct]
                    // operand1 = field_index
                    const value = try self.pop();
                    const struct_val = try self.pop();
                    const field_idx = inst.operand1;

                    switch (struct_val) {
                        .struct_val => |s| {
                            if (field_idx < s.fields.len) {
                                s.fields[field_idx] = value;
                            }
                            try self.push(.{ .struct_val = s });
                        },
                        else => try self.push(.null_val),
                    }
                },

                // ========== 类型转换 ==========
                .to_int => {
                    const val = try self.pop();
                    try self.push(.{ .int_val = val.toInt() });
                },

                .to_float => {
                    const val = try self.pop();
                    try self.push(.{ .float_val = val.toFloat() });
                },

                .to_bool => {
                    const val = try self.pop();
                    try self.push(.{ .bool_val = val.toBool() });
                },

                .to_string => {
                    const val = try self.pop();
                    const str_data = valueToString(self, val) catch return BytecodeVM.VMError.OutOfMemory;
                    const str = self.createString(str_data) catch return BytecodeVM.VMError.OutOfMemory;
                    try self.push(.{ .string_val = str });
                },

                .is_null => {
                    const val = try self.pop();
                    try self.push(.{ .bool_val = val == .null_val });
                },

                .is_int => {
                    const val = try self.pop();
                    try self.push(.{ .bool_val = val == .int_val });
                },

                .is_float => {
                    const val = try self.pop();
                    try self.push(.{ .bool_val = val == .float_val });
                },

                .is_string => {
                    const val = try self.pop();
                    try self.push(.{ .bool_val = val == .string_val });
                },

                .is_array => {
                    const val = try self.pop();
                    try self.push(.{ .bool_val = val == .array_val });
                },

                .is_object => {
                    const val = try self.pop();
                    try self.push(.{ .bool_val = val == .object_val });
                },

                // ========== 字符串操作 ==========
                .concat => {
                    // 栈: [str1, str2] -> [result]
                    const b = try self.pop();
                    const a = try self.pop();

                    const str_a = valueToString(self, a) catch return BytecodeVM.VMError.OutOfMemory;
                    const str_b = valueToString(self, b) catch return BytecodeVM.VMError.OutOfMemory;

                    const result_len = str_a.len + str_b.len;
                    const result_data = self.allocator.alloc(u8, result_len) catch return BytecodeVM.VMError.OutOfMemory;
                    @memcpy(result_data[0..str_a.len], str_a);
                    @memcpy(result_data[str_a.len..], str_b);

                    const result_str = self.allocator.create(Value.String) catch return BytecodeVM.VMError.OutOfMemory;
                    result_str.* = .{
                        .data = result_data,
                        .ref_count = 1,
                    };
                    self.string_pool.append(self.allocator, result_str) catch return BytecodeVM.VMError.OutOfMemory;

                    try self.push(.{ .string_val = result_str });
                },

                .strlen => {
                    const val = try self.pop();
                    switch (val) {
                        .string_val => |s| try self.push(.{ .int_val = @intCast(s.data.len) }),
                        else => try self.push(.{ .int_val = 0 }),
                    }
                },

                else => {
                    // 未实现的指令
                    return BytecodeVM.VMError.InvalidOpcode;
                },
            }
        }
    }

    // ========== 栈操作 ==========

    fn push(self: *BytecodeVM, value: Value) VMError!void {
        if (self.stack_top >= STACK_MAX) {
            return BytecodeVM.VMError.StackOverflow;
        }
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    fn pop(self: *BytecodeVM) VMError!Value {
        if (self.stack_top == 0) {
            return BytecodeVM.VMError.StackUnderflow;
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
        if (self.frame_count >= FRAMES_MAX) {
            return BytecodeVM.VMError.StackOverflow;
        }

        // 首先尝试从函数表中直接查找
        if (self.getFunctionByIndex(func_id)) |func| {
            // 设置新的调用帧
            const new_frame = &self.frames[self.frame_count];
            new_frame.* = CallFrame{
                .function = func,
                .ip = 0,
                .base_pointer = self.stack_top - arg_count,
                .return_address = self.frames[self.frame_count - 1].ip,
            };
            self.frame_count += 1;
            return;
        }

        // 如果函数表中没有，尝试从常量池中获取函数名并查找
        const current_frame = &self.frames[self.frame_count - 1];
        if (func_id < current_frame.function.constants.len) {
            const func_const = current_frame.function.constants[func_id];
            switch (func_const) {
                .func_ref => |ref_idx| {
                    // func_ref 是函数表索引
                    if (self.getFunctionByIndex(ref_idx)) |func| {
                        const new_frame = &self.frames[self.frame_count];
                        new_frame.* = CallFrame{
                            .function = func,
                            .ip = 0,
                            .base_pointer = self.stack_top - arg_count,
                            .return_address = current_frame.ip,
                        };
                        self.frame_count += 1;
                        return;
                    }
                },
                .string_val => |name| {
                    // 通过函数名查找
                    if (self.functions.get(name)) |func| {
                        const new_frame = &self.frames[self.frame_count];
                        new_frame.* = CallFrame{
                            .function = func,
                            .ip = 0,
                            .base_pointer = self.stack_top - arg_count,
                            .return_address = current_frame.ip,
                        };
                        self.frame_count += 1;
                        return;
                    }
                },
                else => {},
            }
        }
        return BytecodeVM.VMError.UndefinedFunction;
    }

    fn callBuiltin(self: *BytecodeVM, builtin_id: u16, arg_count: u16) VMError!void {
        if (builtin_id >= self.builtins.count()) {
            return BytecodeVM.VMError.UndefinedFunction;
        }

        // 收集参数
        var args = std.ArrayListUnmanaged(Value){};
        defer args.deinit(self.allocator);

        var i: u16 = 0;
        while (i < arg_count) : (i += 1) {
            args.append(self.allocator, try self.pop()) catch return BytecodeVM.VMError.OutOfMemory;
        }

        // 调用内置函数 - 通过迭代器获取函数
        var iter = self.builtins.valueIterator();
        var idx: u16 = 0;
        while (iter.next()) |func_ptr| {
            if (idx == builtin_id) {
                const result = try func_ptr.*(self, args.items);
                try self.push(result);
                return;
            }
            idx += 1;
        }
        return BytecodeVM.VMError.UndefinedFunction;
    }

    fn collectGarbage(self: *BytecodeVM) void {
        // 简化GC实现：标记-清除
        // 1. 标记阶段：遍历栈和全局变量，标记所有可达对象
        // 2. 清除阶段：释放未标记的对象

        // 标记栈上的对象
        for (self.stack[0..self.stack_top]) |value| {
            self.markValue(value);
        }

        // 标记全局变量
        var iter = self.globals.iterator();
        while (iter.next()) |entry| {
            self.markValue(entry.value_ptr.*);
        }

        // 清理临时字符串池
        for (self.temp_strings.items) |str| {
            self.allocator.free(str);
        }
        self.temp_strings.clearRetainingCapacity();

        // 重置分配计数
        self.bytes_allocated = 0;
    }

    fn markValue(self: *BytecodeVM, value: Value) void {
        _ = self;
        switch (value) {
            .string_val => |s| s.ref_count += 1,
            .array_val => |a| a.ref_count += 1,
            .object_val => |o| o.ref_count += 1,
            .struct_val => |s| s.ref_count += 1,
            .closure_val => |c| c.ref_count += 1,
            .resource_val => |r| r.ref_count += 1,
            else => {},
        }
    }

    // ========== 类型反馈方法 ==========

    /// 记录调用点的参数类型
    pub fn recordCallSiteTypes(self: *BytecodeVM, call_site_id: u32, args: []const Value) void {
        if (!self.enable_type_feedback) return;

        for (args) |arg| {
            self.type_feedback_collector.record(call_site_id, arg.getTypeTag()) catch {};
        }
    }

    /// 记录单个值的类型
    pub fn recordValueType(self: *BytecodeVM, call_site_id: u32, value: Value) void {
        if (!self.enable_type_feedback) return;

        self.type_feedback_collector.record(call_site_id, value.getTypeTag()) catch {};
    }

    /// 获取调用点的类型反馈
    pub fn getTypeFeedback(self: *BytecodeVM, call_site_id: u32) ?*TypeFeedback {
        return self.type_feedback_collector.getFeedback(call_site_id);
    }

    /// 检查类型守卫是否通过
    /// 返回 true 表示类型匹配，false 表示需要去优化
    pub fn checkTypeGuard(self: *BytecodeVM, value: Value, expected_tag: TypeTag) bool {
        const actual_tag = value.getTypeTag();
        if (actual_tag != expected_tag) {
            self.deopt_count += 1;
            return false;
        }
        return true;
    }

    /// 执行去优化
    /// 清除特定调用点的类型反馈，回退到通用执行路径
    pub fn deoptimize(self: *BytecodeVM, call_site_id: u32) void {
        self.deopt_count += 1;
        self.type_feedback_collector.clearSite(call_site_id);
    }

    /// 获取类型反馈统计信息
    pub fn getTypeFeedbackStats(self: *BytecodeVM) TypeFeedbackCollector.CollectorStats {
        self.type_feedback_collector.updateStats();
        return self.type_feedback_collector.getStats();
    }

    /// 启用/禁用类型反馈收集
    pub fn setTypeFeedbackEnabled(self: *BytecodeVM, enabled: bool) void {
        self.enable_type_feedback = enabled;
    }

    /// 清除所有类型反馈（全局去优化）
    pub fn clearAllTypeFeedback(self: *BytecodeVM) void {
        self.type_feedback_collector.clearAll();
        self.deopt_count = 0;
    }

    // ========== 内联缓存方法 ==========

    /// 获取内联缓存统计信息
    pub fn getMethodCacheStats(self: *const BytecodeVM) MethodCache.GlobalCacheStats {
        return self.method_cache.getStats();
    }

    /// 启用/禁用内联缓存
    pub fn setInlineCacheEnabled(self: *BytecodeVM, enabled: bool) void {
        self.enable_inline_cache = enabled;
    }

    /// 使指定类的所有缓存失效（类定义变化时调用）
    pub fn invalidateClassCache(self: *BytecodeVM, class_id: u64) void {
        self.method_cache.invalidateClass(class_id);
    }

    /// 清除所有内联缓存
    pub fn clearAllMethodCache(self: *BytecodeVM) void {
        // 重新初始化缓存
        self.method_cache.deinit();
        self.method_cache = MethodCache.init(self.allocator);
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

// ============================================================
// 内置函数实现
// ============================================================

/// echo - 输出值到缓冲区
fn builtinEcho(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    for (args) |arg| {
        const str = valueToString(vm, arg) catch return BytecodeVM.VMError.OutOfMemory;
        vm.output_buffer.appendSlice(vm.allocator, str) catch return BytecodeVM.VMError.OutOfMemory;
    }
    return .null_val;
}

/// print - 输出值并返回1
fn builtinPrint(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len > 0) {
        const str = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
        vm.output_buffer.appendSlice(vm.allocator, str) catch return BytecodeVM.VMError.OutOfMemory;
    }
    return .{ .int_val = 1 };
}

/// var_dump - 调试输出
fn builtinVarDump(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    for (args) |arg| {
        const dump = valueDump(vm, arg) catch return BytecodeVM.VMError.OutOfMemory;
        vm.output_buffer.appendSlice(vm.allocator, dump) catch return BytecodeVM.VMError.OutOfMemory;
        vm.output_buffer.append(vm.allocator, '\n') catch return BytecodeVM.VMError.OutOfMemory;
    }
    return .null_val;
}

/// strlen - 字符串长度
fn builtinStrlen(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .int_val = 0 };
    return switch (args[0]) {
        .string_val => |s| .{ .int_val = @intCast(s.data.len) },
        else => .{ .int_val = 0 },
    };
}

/// count - 数组长度
fn builtinCount(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .int_val = 0 };
    return switch (args[0]) {
        .array_val => |a| .{ .int_val = @intCast(a.elements.items.len) },
        else => .{ .int_val = 1 },
    };
}

/// array_push - 追加元素到数组
fn builtinArrayPush(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    switch (args[0]) {
        .array_val => |arr| {
            for (args[1..]) |val| {
                arr.elements.append(vm.allocator, val) catch return BytecodeVM.VMError.OutOfMemory;
            }
            return .{ .int_val = @intCast(arr.elements.items.len) };
        },
        else => return .null_val,
    }
}

/// array_pop - 弹出数组最后一个元素
fn builtinArrayPop(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    return switch (args[0]) {
        .array_val => |arr| {
            if (arr.elements.items.len > 0) {
                return arr.elements.pop() orelse .null_val;
            }
            return .null_val;
        },
        else => .null_val,
    };
}

/// isset - 检查变量是否已设置且非null
fn builtinIsset(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = false };
    return .{ .bool_val = args[0] != .null_val };
}

/// is_null - 检查是否为null
fn builtinIsNull(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = true };
    return .{ .bool_val = args[0] == .null_val };
}

/// is_int - 检查是否为整数
fn builtinIsInt(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = false };
    return .{ .bool_val = args[0] == .int_val };
}

/// is_string - 检查是否为字符串
fn builtinIsString(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = false };
    return .{ .bool_val = args[0] == .string_val };
}

/// is_array - 检查是否为数组
fn builtinIsArray(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = false };
    return .{ .bool_val = args[0] == .array_val };
}

// ============================================================
// 辅助函数
// ============================================================

/// 将Value转换为字符串
/// 注意：对于int_val和float_val，会分配新内存并添加到temp_strings池中
/// 这些临时字符串会在VM销毁时统一释放
fn valueToString(vm: *BytecodeVM, value: Value) ![]const u8 {
    return switch (value) {
        .null_val => "",
        .bool_val => |b| if (b) "1" else "",
        .int_val => |i| blk: {
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
            const result = try vm.allocator.dupe(u8, slice);
            // 跟踪分配的临时字符串
            try vm.temp_strings.append(vm.allocator, result);
            break :blk result;
        },
        .float_val => |f| blk: {
            var buf: [64]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch "0";
            const result = try vm.allocator.dupe(u8, slice);
            // 跟踪分配的临时字符串
            try vm.temp_strings.append(vm.allocator, result);
            break :blk result;
        },
        .string_val => |s| s.data,
        .array_val => "Array",
        .object_val => "Object",
        else => "",
    };
}

/// 清理临时字符串池 - 可在适当时机调用以释放内存
pub fn clearTempStrings(vm: *BytecodeVM) void {
    for (vm.temp_strings.items) |str| {
        vm.allocator.free(str);
    }
    vm.temp_strings.clearRetainingCapacity();
}

/// 调试输出Value
fn valueDump(vm: *BytecodeVM, value: Value) ![]const u8 {
    _ = vm;
    return switch (value) {
        .null_val => "NULL",
        .bool_val => |b| if (b) "bool(true)" else "bool(false)",
        .int_val => "int(...)",
        .float_val => "float(...)",
        .string_val => |s| blk: {
            _ = s;
            break :blk "string(...)";
        },
        .array_val => |a| blk: {
            _ = a;
            break :blk "array(...)";
        },
        .object_val => "object(...)",
        else => "unknown",
    };
}

// ============================================================
// 计算跳转表优化 - 指令处理函数
// ============================================================

/// 初始化分发表
fn initDispatchTable() [256]DispatchFn {
    var table: [256]DispatchFn = undefined;
    // 默认所有指令使用无效处理函数
    for (&table) |*entry| {
        entry.* = handleInvalidOpcode;
    }

    // 栈操作
    table[@intFromEnum(OpCode.nop)] = handleNop;
    table[@intFromEnum(OpCode.push_const)] = handlePushConst;
    table[@intFromEnum(OpCode.push_local)] = handlePushLocal;
    table[@intFromEnum(OpCode.push_global)] = handlePushGlobal;
    table[@intFromEnum(OpCode.pop)] = handlePop;
    table[@intFromEnum(OpCode.dup)] = handleDup;
    table[@intFromEnum(OpCode.swap)] = handleSwap;
    table[@intFromEnum(OpCode.push_null)] = handlePushNull;
    table[@intFromEnum(OpCode.push_true)] = handlePushTrue;
    table[@intFromEnum(OpCode.push_false)] = handlePushFalse;
    table[@intFromEnum(OpCode.push_int_0)] = handlePushInt0;
    table[@intFromEnum(OpCode.push_int_1)] = handlePushInt1;
    table[@intFromEnum(OpCode.store_local)] = handleStoreLocal;
    table[@intFromEnum(OpCode.store_global)] = handleStoreGlobal;

    // 整数算术
    table[@intFromEnum(OpCode.add_int)] = handleAddInt;
    table[@intFromEnum(OpCode.sub_int)] = handleSubInt;
    table[@intFromEnum(OpCode.mul_int)] = handleMulInt;
    table[@intFromEnum(OpCode.div_int)] = handleDivInt;
    table[@intFromEnum(OpCode.mod_int)] = handleModInt;
    table[@intFromEnum(OpCode.neg_int)] = handleNegInt;
    table[@intFromEnum(OpCode.inc_int)] = handleIncInt;
    table[@intFromEnum(OpCode.dec_int)] = handleDecInt;
    table[@intFromEnum(OpCode.bit_and)] = handleBitAnd;
    table[@intFromEnum(OpCode.bit_or)] = handleBitOr;
    table[@intFromEnum(OpCode.bit_xor)] = handleBitXor;
    table[@intFromEnum(OpCode.bit_not)] = handleBitNot;
    table[@intFromEnum(OpCode.shl)] = handleShl;
    table[@intFromEnum(OpCode.shr)] = handleShr;

    // 浮点算术
    table[@intFromEnum(OpCode.add_float)] = handleAddFloat;
    table[@intFromEnum(OpCode.sub_float)] = handleSubFloat;
    table[@intFromEnum(OpCode.mul_float)] = handleMulFloat;
    table[@intFromEnum(OpCode.div_float)] = handleDivFloat;
    table[@intFromEnum(OpCode.neg_float)] = handleNegFloat;
    table[@intFromEnum(OpCode.sqrt)] = handleSqrt;

    // 比较操作
    table[@intFromEnum(OpCode.eq)] = handleEq;
    table[@intFromEnum(OpCode.neq)] = handleNeq;
    table[@intFromEnum(OpCode.lt_int)] = handleLtInt;
    table[@intFromEnum(OpCode.gt_int)] = handleGtInt;
    table[@intFromEnum(OpCode.lt_float)] = handleLtFloat;
    table[@intFromEnum(OpCode.gt_float)] = handleGtFloat;

    // 逻辑操作
    table[@intFromEnum(OpCode.logic_and)] = handleLogicAnd;
    table[@intFromEnum(OpCode.logic_or)] = handleLogicOr;
    table[@intFromEnum(OpCode.logic_not)] = handleLogicNot;

    // 控制流
    table[@intFromEnum(OpCode.jmp)] = handleJmp;
    table[@intFromEnum(OpCode.jz)] = handleJz;
    table[@intFromEnum(OpCode.jnz)] = handleJnz;
    table[@intFromEnum(OpCode.call)] = handleCall;
    table[@intFromEnum(OpCode.call_method)] = handleCallMethod;
    table[@intFromEnum(OpCode.call_builtin)] = handleCallBuiltin;
    table[@intFromEnum(OpCode.ret)] = handleRet;
    table[@intFromEnum(OpCode.ret_void)] = handleRetVoid;
    table[@intFromEnum(OpCode.loop_start)] = handleLoopStart;
    table[@intFromEnum(OpCode.loop_end)] = handleLoopEnd;
    table[@intFromEnum(OpCode.halt)] = handleHalt;

    // 类型守卫
    table[@intFromEnum(OpCode.guard_int)] = handleGuardInt;
    table[@intFromEnum(OpCode.guard_float)] = handleGuardFloat;
    table[@intFromEnum(OpCode.guard_string)] = handleGuardString;
    table[@intFromEnum(OpCode.guard_array)] = handleGuardArray;
    table[@intFromEnum(OpCode.guard_object)] = handleGuardObject;
    table[@intFromEnum(OpCode.deoptimize)] = handleDeoptimize;

    // 调试
    table[@intFromEnum(OpCode.debug_break)] = handleDebugBreak;
    table[@intFromEnum(OpCode.line_number)] = handleLineNumber;
    table[@intFromEnum(OpCode.gc_safepoint)] = handleGcSafepoint;

    // 数组操作
    table[@intFromEnum(OpCode.new_array)] = handleNewArray;
    table[@intFromEnum(OpCode.array_get)] = handleArrayGet;
    table[@intFromEnum(OpCode.array_set)] = handleArraySet;
    table[@intFromEnum(OpCode.array_push)] = handleArrayPush;
    table[@intFromEnum(OpCode.array_pop)] = handleArrayPop;
    table[@intFromEnum(OpCode.array_len)] = handleArrayLen;
    table[@intFromEnum(OpCode.array_exists)] = handleArrayExists;
    table[@intFromEnum(OpCode.array_unset)] = handleArrayUnset;

    // 对象操作
    table[@intFromEnum(OpCode.new_object)] = handleNewObject;
    table[@intFromEnum(OpCode.get_prop)] = handleGetProp;
    table[@intFromEnum(OpCode.set_prop)] = handleSetProp;
    table[@intFromEnum(OpCode.instanceof)] = handleInstanceof;
    table[@intFromEnum(OpCode.clone)] = handleClone;

    // 结构体操作
    table[@intFromEnum(OpCode.new_struct)] = handleNewStruct;
    table[@intFromEnum(OpCode.struct_get)] = handleStructGet;
    table[@intFromEnum(OpCode.struct_set)] = handleStructSet;

    // 参数传递优化
    table[@intFromEnum(OpCode.pass_by_value)] = handlePassByValue;
    table[@intFromEnum(OpCode.pass_by_ref)] = handlePassByRef;
    table[@intFromEnum(OpCode.pass_by_cow)] = handlePassByCow;
    table[@intFromEnum(OpCode.pass_by_move)] = handlePassByMove;
    table[@intFromEnum(OpCode.cow_check)] = handleCowCheck;
    table[@intFromEnum(OpCode.cow_copy)] = handleCowCopy;
    table[@intFromEnum(OpCode.ret_move)] = handleRetMove;
    table[@intFromEnum(OpCode.ret_cow)] = handleRetCow;

    // 类型转换
    table[@intFromEnum(OpCode.to_int)] = handleToInt;
    table[@intFromEnum(OpCode.to_float)] = handleToFloat;
    table[@intFromEnum(OpCode.to_bool)] = handleToBool;
    table[@intFromEnum(OpCode.to_string)] = handleToString;

    // 类型检查
    table[@intFromEnum(OpCode.is_null)] = handleIsNull;
    table[@intFromEnum(OpCode.is_int)] = handleIsInt;
    table[@intFromEnum(OpCode.is_float)] = handleIsFloat;
    table[@intFromEnum(OpCode.is_string)] = handleIsString;
    table[@intFromEnum(OpCode.is_array)] = handleIsArray;
    table[@intFromEnum(OpCode.is_object)] = handleIsObject;

    // 字符串操作
    table[@intFromEnum(OpCode.concat)] = handleConcat;
    table[@intFromEnum(OpCode.strlen)] = handleStrlen;

    return table;
}

/// 无效操作码处理
fn handleInvalidOpcode(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return BytecodeVM.VMError.InvalidOpcode;
}

/// NOP - 空操作
fn handleNop(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return .continue_execution;
}

/// PUSH_CONST - 压入常量
fn handlePushConst(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = vm.loadConstant(frame.function, inst.operand1);
    try vm.push(value);
    return .continue_execution;
}

/// PUSH_LOCAL - 压入局部变量
fn handlePushLocal(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const idx = frame.base_pointer + inst.operand1;
    try vm.push(vm.stack[idx]);
    return .continue_execution;
}

/// PUSH_GLOBAL - 压入全局变量
fn handlePushGlobal(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const name_idx = inst.operand1;
    if (name_idx < frame.function.constants.len) {
        const name_val = frame.function.constants[name_idx];
        if (name_val == .string_val) {
            if (vm.globals.get(name_val.string_val)) |val| {
                try vm.push(val);
                return .continue_execution;
            }
        }
    }
    try vm.push(.null_val);
    return .continue_execution;
}

/// POP - 弹出栈顶
fn handlePop(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    _ = try vm.pop();
    return .continue_execution;
}

/// DUP - 复制栈顶
fn handleDup(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = vm.peek(0);
    try vm.push(value);
    return .continue_execution;
}

/// SWAP - 交换栈顶两元素
fn handleSwap(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const a = try vm.pop();
    const b = try vm.pop();
    try vm.push(a);
    try vm.push(b);
    return .continue_execution;
}

/// PUSH_NULL - 压入null
fn handlePushNull(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    try vm.push(.null_val);
    return .continue_execution;
}

/// PUSH_TRUE - 压入true
fn handlePushTrue(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    try vm.push(.{ .bool_val = true });
    return .continue_execution;
}

/// PUSH_FALSE - 压入false
fn handlePushFalse(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    try vm.push(.{ .bool_val = false });
    return .continue_execution;
}

/// PUSH_INT_0 - 压入整数0
fn handlePushInt0(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    try vm.push(.{ .int_val = 0 });
    return .continue_execution;
}

/// PUSH_INT_1 - 压入整数1
fn handlePushInt1(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    try vm.push(.{ .int_val = 1 });
    return .continue_execution;
}

/// STORE_LOCAL - 存储到局部变量
fn handleStoreLocal(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = try vm.pop();
    const idx = frame.base_pointer + inst.operand1;
    vm.stack[idx] = value;
    return .continue_execution;
}

/// STORE_GLOBAL - 存储到全局变量
fn handleStoreGlobal(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = try vm.pop();
    const name_idx = inst.operand1;
    if (name_idx < frame.function.constants.len) {
        const name_val = frame.function.constants[name_idx];
        if (name_val == .string_val) {
            vm.globals.put(vm.allocator, name_val.string_val, value) catch return BytecodeVM.VMError.OutOfMemory;
        }
    }
    return .continue_execution;
}

// ========== 整数算术处理函数 ==========

fn handleAddInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = a +% b });
    return .continue_execution;
}

fn handleSubInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = a -% b });
    return .continue_execution;
}

fn handleMulInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = a *% b });
    return .continue_execution;
}

fn handleDivInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    if (b == 0) return BytecodeVM.VMError.DivisionByZero;
    try vm.push(.{ .int_val = @divTrunc(a, b) });
    return .continue_execution;
}

fn handleModInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    if (b == 0) return BytecodeVM.VMError.DivisionByZero;
    try vm.push(.{ .int_val = @mod(a, b) });
    return .continue_execution;
}

fn handleNegInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = -a });
    return .continue_execution;
}

fn handleIncInt(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const idx = frame.base_pointer + inst.operand1;
    const val = vm.stack[idx].toInt();
    vm.stack[idx] = .{ .int_val = val + 1 };
    return .continue_execution;
}

fn handleDecInt(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const idx = frame.base_pointer + inst.operand1;
    const val = vm.stack[idx].toInt();
    vm.stack[idx] = .{ .int_val = val - 1 };
    return .continue_execution;
}

// ========== 位运算处理函数 ==========

fn handleBitAnd(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = a & b });
    return .continue_execution;
}

fn handleBitOr(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = a | b });
    return .continue_execution;
}

fn handleBitXor(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = a ^ b });
    return .continue_execution;
}

fn handleBitNot(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .int_val = ~a });
    return .continue_execution;
}

fn handleShl(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    const shift: u6 = @intCast(@min(63, @max(0, b)));
    try vm.push(.{ .int_val = a << shift });
    return .continue_execution;
}

fn handleShr(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    const shift: u6 = @intCast(@min(63, @max(0, b)));
    try vm.push(.{ .int_val = a >> shift });
    return .continue_execution;
}

// ========== 浮点算术处理函数 ==========

fn handleAddFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toFloat();
    const a = (try vm.pop()).toFloat();
    try vm.push(.{ .float_val = a + b });
    return .continue_execution;
}

fn handleSubFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toFloat();
    const a = (try vm.pop()).toFloat();
    try vm.push(.{ .float_val = a - b });
    return .continue_execution;
}

fn handleMulFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toFloat();
    const a = (try vm.pop()).toFloat();
    try vm.push(.{ .float_val = a * b });
    return .continue_execution;
}

fn handleDivFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toFloat();
    const a = (try vm.pop()).toFloat();
    if (b == 0.0) return BytecodeVM.VMError.DivisionByZero;
    try vm.push(.{ .float_val = a / b });
    return .continue_execution;
}

fn handleNegFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const a = (try vm.pop()).toFloat();
    try vm.push(.{ .float_val = -a });
    return .continue_execution;
}

fn handleSqrt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const a = (try vm.pop()).toFloat();
    try vm.push(.{ .float_val = @sqrt(a) });
    return .continue_execution;
}

// ========== 比较操作处理函数 ==========

fn handleEq(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = try vm.pop();
    const a = try vm.pop();
    try vm.push(.{ .bool_val = vm.valuesEqual(a, b) });
    return .continue_execution;
}

fn handleNeq(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = try vm.pop();
    const a = try vm.pop();
    try vm.push(.{ .bool_val = !vm.valuesEqual(a, b) });
    return .continue_execution;
}

fn handleLtInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .bool_val = a < b });
    return .continue_execution;
}

fn handleGtInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    try vm.push(.{ .bool_val = a > b });
    return .continue_execution;
}

fn handleLtFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toFloat();
    const a = (try vm.pop()).toFloat();
    try vm.push(.{ .bool_val = a < b });
    return .continue_execution;
}

fn handleGtFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toFloat();
    const a = (try vm.pop()).toFloat();
    try vm.push(.{ .bool_val = a > b });
    return .continue_execution;
}

// ========== 逻辑操作处理函数 ==========

fn handleLogicAnd(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toBool();
    const a = (try vm.pop()).toBool();
    try vm.push(.{ .bool_val = a and b });
    return .continue_execution;
}

fn handleLogicOr(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toBool();
    const a = (try vm.pop()).toBool();
    try vm.push(.{ .bool_val = a or b });
    return .continue_execution;
}

fn handleLogicNot(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const a = (try vm.pop()).toBool();
    try vm.push(.{ .bool_val = !a });
    return .continue_execution;
}

// ========== 控制流处理函数 ==========

fn handleJmp(_: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    return .{ .jump_to = inst.operand1 };
}

fn handleJz(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const cond = (try vm.pop()).toBool();
    if (!cond) {
        return .{ .jump_to = inst.operand1 };
    }
    return .continue_execution;
}

fn handleJnz(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const cond = (try vm.pop()).toBool();
    if (cond) {
        return .{ .jump_to = inst.operand1 };
    }
    return .continue_execution;
}

fn handleCall(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const func_id = inst.operand1;
    const arg_count = inst.operand2;

    // 类型反馈：记录调用点的参数类型
    if (vm.enable_type_feedback and arg_count > 0) {
        const call_site_id = @as(u32, frame.ip - 1); // 当前指令位置作为调用点ID
        var i: u16 = 0;
        while (i < arg_count) : (i += 1) {
            const arg = vm.stack[vm.stack_top - arg_count + i];
            vm.type_feedback_collector.record(call_site_id, arg.getTypeTag()) catch {};
        }
    }

    try vm.callFunction(func_id, arg_count);
    return .frame_changed;
}

fn handleCallBuiltin(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const builtin_id = inst.operand1;
    const arg_count = inst.operand2;

    // 类型反馈：记录内置函数调用点的参数类型
    if (vm.enable_type_feedback and arg_count > 0) {
        const call_site_id = @as(u32, frame.ip - 1) | 0x80000000; // 高位标记为内置函数调用
        var i: u16 = 0;
        while (i < arg_count) : (i += 1) {
            const arg = vm.stack[vm.stack_top - arg_count + i];
            vm.type_feedback_collector.record(call_site_id, arg.getTypeTag()) catch {};
        }
    }

    try vm.callBuiltin(builtin_id, arg_count);
    return .continue_execution;
}

/// 方法调用处理函数 - 使用内联缓存优化
/// operand1 = 方法名在常量池中的索引
/// operand2 = 参数数量
/// 栈布局: [object, arg1, arg2, ...] -> [result]
fn handleCallMethod(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const method_name_idx = inst.operand1;
    const arg_count = inst.operand2;

    // 获取方法名
    if (method_name_idx >= frame.function.constants.len) {
        return BytecodeVM.VMError.UndefinedFunction;
    }
    const method_name_const = frame.function.constants[method_name_idx];
    if (method_name_const != .string_val) {
        return BytecodeVM.VMError.UndefinedFunction;
    }
    const method_name = method_name_const.string_val;

    // 获取对象（在参数之下）
    const obj_idx = vm.stack_top - arg_count - 1;
    if (obj_idx >= vm.stack_top) {
        return BytecodeVM.VMError.StackUnderflow;
    }
    const obj_val = vm.stack[obj_idx];

    // 类型反馈：记录方法调用的对象类型
    if (vm.enable_type_feedback) {
        const call_site_id = @as(u32, frame.ip - 1) | 0x20000000; // 高位标记为方法调用
        vm.type_feedback_collector.record(call_site_id, obj_val.getTypeTag()) catch {};
    }

    // 检查对象类型
    switch (obj_val) {
        .object_val => |obj| {
            const class_id = @as(u64, obj.class_id);

            // 尝试从内联缓存中查找方法
            var method_ptr: ?*anyopaque = null;
            if (vm.enable_inline_cache) {
                method_ptr = vm.method_cache.lookupMethod(method_name, class_id);
            }

            if (method_ptr) |_| {
                // 缓存命中 - 直接调用缓存的方法
                // 注意：在完整实现中，这里会直接调用缓存的函数指针
                // 当前简化实现：仍然通过常规路径查找
            }

            // 缓存未命中或未启用缓存 - 查找方法
            // 在完整实现中，这里会从类定义中查找方法
            // 当前简化实现：返回null作为结果

            // 如果找到方法，缓存它
            if (vm.enable_inline_cache and method_ptr == null) {
                // 在完整实现中，这里会缓存找到的方法
                // vm.method_cache.cacheMethod(method_name, class_id, found_method) catch {};
            }

            // 弹出参数和对象
            var i: u16 = 0;
            while (i < arg_count + 1) : (i += 1) {
                _ = try vm.pop();
            }

            // 压入结果（当前简化实现返回null）
            try vm.push(.null_val);
            return .continue_execution;
        },
        .struct_val => |s| {
            // 结构体方法调用
            const struct_id = @as(u64, s.struct_id) | 0x10000; // 区分结构体和类

            // 尝试从内联缓存中查找方法
            if (vm.enable_inline_cache) {
                _ = vm.method_cache.lookupMethod(method_name, struct_id);
            }

            // 弹出参数和结构体
            var i: u16 = 0;
            while (i < arg_count + 1) : (i += 1) {
                _ = try vm.pop();
            }

            // 压入结果
            try vm.push(.null_val);
            return .continue_execution;
        },
        else => {
            // 非对象类型调用方法 - 错误
            return BytecodeVM.VMError.TypeMismatch;
        },
    }
}

fn handleRet(vm: *BytecodeVM, frame: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const result = try vm.pop();
    vm.frame_count -= 1;
    if (vm.frame_count == 0) {
        return .{ .return_value = result };
    }
    vm.stack_top = frame.base_pointer;
    try vm.push(result);
    return .frame_changed;
}

fn handleRetVoid(vm: *BytecodeVM, frame: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    vm.frame_count -= 1;
    if (vm.frame_count == 0) {
        return .{ .return_value = .null_val };
    }
    vm.stack_top = frame.base_pointer;
    return .frame_changed;
}

fn handleLoopStart(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return .continue_execution;
}

fn handleLoopEnd(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return .continue_execution;
}

fn handleHalt(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return .{ .return_value = .null_val };
}

// ========== 类型守卫处理函数 ==========

/// 整数类型守卫 - 检查栈顶值是否为整数
/// 如果类型不匹配，触发去优化并记录统计信息
fn handleGuardInt(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = vm.peek(0);
    const guard_site_id = @as(u32, frame.ip - 1) | 0xC0000000; // 高位标记为类型守卫

    if (!vm.checkTypeGuard(value, .int_type)) {
        // 类型不匹配，执行去优化
        vm.deoptimize(guard_site_id);

        // 如果operand1指定了去优化跳转目标，跳转到通用执行路径
        if (inst.operand1 != 0) {
            return .{ .jump_to = inst.operand1 };
        }
        // 否则继续执行（解释器模式下的回退行为）
    }
    return .continue_execution;
}

/// 浮点类型守卫 - 检查栈顶值是否为浮点数
/// 如果类型不匹配，触发去优化并记录统计信息
fn handleGuardFloat(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = vm.peek(0);
    const guard_site_id = @as(u32, frame.ip - 1) | 0xC0000000; // 高位标记为类型守卫

    if (!vm.checkTypeGuard(value, .float_type)) {
        // 类型不匹配，执行去优化
        vm.deoptimize(guard_site_id);

        // 如果operand1指定了去优化跳转目标，跳转到通用执行路径
        if (inst.operand1 != 0) {
            return .{ .jump_to = inst.operand1 };
        }
        // 否则继续执行（解释器模式下的回退行为）
    }
    return .continue_execution;
}

/// 字符串类型守卫 - 检查栈顶值是否为字符串
fn handleGuardString(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = vm.peek(0);
    const guard_site_id = @as(u32, frame.ip - 1) | 0xC0000000;

    if (!vm.checkTypeGuard(value, .string_type)) {
        vm.deoptimize(guard_site_id);
        if (inst.operand1 != 0) {
            return .{ .jump_to = inst.operand1 };
        }
    }
    return .continue_execution;
}

/// 数组类型守卫 - 检查栈顶值是否为数组
fn handleGuardArray(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = vm.peek(0);
    const guard_site_id = @as(u32, frame.ip - 1) | 0xC0000000;

    if (!vm.checkTypeGuard(value, .array_type)) {
        vm.deoptimize(guard_site_id);
        if (inst.operand1 != 0) {
            return .{ .jump_to = inst.operand1 };
        }
    }
    return .continue_execution;
}

/// 对象类型守卫 - 检查栈顶值是否为对象
fn handleGuardObject(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = vm.peek(0);
    const guard_site_id = @as(u32, frame.ip - 1) | 0xC0000000;

    if (!vm.checkTypeGuard(value, .object_type)) {
        vm.deoptimize(guard_site_id);
        if (inst.operand1 != 0) {
            return .{ .jump_to = inst.operand1 };
        }
    }
    return .continue_execution;
}

/// 去优化指令 - 强制回退到通用执行路径
fn handleDeoptimize(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const deopt_site_id = @as(u32, frame.ip - 1) | 0xC0000000;
    vm.deoptimize(deopt_site_id);

    // operand1 指定回退目标地址
    if (inst.operand1 != 0) {
        return .{ .jump_to = inst.operand1 };
    }
    return .continue_execution;
}

// ========== 调试处理函数 ==========

fn handleDebugBreak(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return .continue_execution;
}

fn handleLineNumber(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return .continue_execution;
}

fn handleGcSafepoint(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    if (vm.bytes_allocated > vm.gc_threshold) {
        vm.collectGarbage();
    }
    return .continue_execution;
}

// ========== 数组操作处理函数 ==========

fn handleNewArray(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const count = inst.operand1;
    const arr = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    if (count > 0) {
        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const val = try vm.pop();
            arr.elements.insert(vm.allocator, 0, val) catch return BytecodeVM.VMError.OutOfMemory;
        }
    }
    try vm.push(.{ .array_val = arr });
    return .continue_execution;
}

fn handleArrayGet(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const index = try vm.pop();
    const arr_val = try vm.pop();
    switch (arr_val) {
        .array_val => |arr| {
            switch (index) {
                .int_val => |idx| {
                    const i: usize = if (idx >= 0) @intCast(idx) else 0;
                    if (i < arr.elements.items.len) {
                        try vm.push(arr.elements.items[i]);
                    } else {
                        try vm.push(.null_val);
                    }
                },
                .string_val => |key| {
                    if (arr.keys.get(key.data)) |i| {
                        try vm.push(arr.elements.items[i]);
                    } else {
                        try vm.push(.null_val);
                    }
                },
                else => try vm.push(.null_val),
            }
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

fn handleArraySet(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = try vm.pop();
    const index = try vm.pop();
    const arr_val = try vm.pop();
    switch (arr_val) {
        .array_val => |arr| {
            switch (index) {
                .int_val => |idx| {
                    const i: usize = if (idx >= 0) @intCast(idx) else 0;
                    if (i < arr.elements.items.len) {
                        arr.elements.items[i] = value;
                    } else {
                        while (arr.elements.items.len < i) {
                            arr.elements.append(vm.allocator, .null_val) catch return BytecodeVM.VMError.OutOfMemory;
                        }
                        arr.elements.append(vm.allocator, value) catch return BytecodeVM.VMError.OutOfMemory;
                    }
                },
                .string_val => |key| {
                    const key_copy = vm.allocator.dupe(u8, key.data) catch return BytecodeVM.VMError.OutOfMemory;
                    if (arr.keys.get(key.data)) |i| {
                        arr.elements.items[i] = value;
                    } else {
                        const new_idx = arr.elements.items.len;
                        arr.elements.append(vm.allocator, value) catch return BytecodeVM.VMError.OutOfMemory;
                        arr.keys.put(vm.allocator, key_copy, new_idx) catch return BytecodeVM.VMError.OutOfMemory;
                    }
                },
                else => {},
            }
            try vm.push(.{ .array_val = arr });
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

fn handleArrayPush(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = try vm.pop();
    const arr_val = try vm.pop();
    switch (arr_val) {
        .array_val => |arr| {
            arr.elements.append(vm.allocator, value) catch return BytecodeVM.VMError.OutOfMemory;
            try vm.push(.{ .array_val = arr });
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

fn handleArrayPop(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const arr_val = try vm.pop();
    switch (arr_val) {
        .array_val => |arr| {
            if (arr.elements.items.len > 0) {
                const val = arr.elements.pop() orelse .null_val;
                try vm.push(val);
            } else {
                try vm.push(.null_val);
            }
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

fn handleArrayLen(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const arr_val = try vm.pop();
    switch (arr_val) {
        .array_val => |arr| {
            try vm.push(.{ .int_val = @intCast(arr.elements.items.len) });
        },
        else => try vm.push(.{ .int_val = 0 }),
    }
    return .continue_execution;
}

fn handleArrayExists(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const key = try vm.pop();
    const arr_val = try vm.pop();
    switch (arr_val) {
        .array_val => |arr| {
            const exists = switch (key) {
                .int_val => |idx| blk: {
                    const i: usize = if (idx >= 0) @intCast(idx) else 0;
                    break :blk i < arr.elements.items.len;
                },
                .string_val => |k| arr.keys.contains(k.data),
                else => false,
            };
            try vm.push(.{ .bool_val = exists });
        },
        else => try vm.push(.{ .bool_val = false }),
    }
    return .continue_execution;
}

fn handleArrayUnset(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const key = try vm.pop();
    const arr_val = try vm.pop();
    switch (arr_val) {
        .array_val => |arr| {
            switch (key) {
                .int_val => |idx| {
                    const i: usize = if (idx >= 0) @intCast(idx) else 0;
                    if (i < arr.elements.items.len) {
                        _ = arr.elements.orderedRemove(i);
                    }
                },
                .string_val => |k| {
                    if (arr.keys.get(k.data)) |i| {
                        _ = arr.elements.orderedRemove(i);
                        _ = arr.keys.remove(k.data);
                        var iter = arr.keys.iterator();
                        while (iter.next()) |entry| {
                            if (entry.value_ptr.* > i) {
                                entry.value_ptr.* -= 1;
                            }
                        }
                    }
                },
                else => {},
            }
            try vm.push(.{ .array_val = arr });
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

// ========== 对象操作处理函数 ==========

fn handleNewObject(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const class_id = inst.operand1;
    const obj = vm.createObject(class_id) catch return BytecodeVM.VMError.OutOfMemory;
    try vm.push(.{ .object_val = obj });
    return .continue_execution;
}

fn handleGetProp(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const obj_val = try vm.pop();
    const prop_idx = inst.operand1;

    // 类型反馈：记录属性访问的对象类型
    if (vm.enable_type_feedback) {
        const access_site_id = @as(u32, frame.ip - 1) | 0x40000000; // 高位标记为属性访问
        vm.type_feedback_collector.record(access_site_id, obj_val.getTypeTag()) catch {};
    }

    switch (obj_val) {
        .object_val => |obj| {
            if (prop_idx < frame.function.constants.len) {
                const prop_const = frame.function.constants[prop_idx];
                if (prop_const == .string_val) {
                    const prop_name = prop_const.string_val;
                    if (obj.properties.get(prop_name)) |val| {
                        try vm.push(val);
                    } else {
                        try vm.push(.null_val);
                    }
                } else {
                    try vm.push(.null_val);
                }
            } else {
                try vm.push(.null_val);
            }
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

fn handleSetProp(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = try vm.pop();
    const obj_val = try vm.pop();
    const prop_idx = inst.operand1;

    // 类型反馈：记录属性设置的对象类型和值类型
    if (vm.enable_type_feedback) {
        const access_site_id = @as(u32, frame.ip - 1) | 0x40000000; // 高位标记为属性访问
        vm.type_feedback_collector.record(access_site_id, obj_val.getTypeTag()) catch {};
        vm.type_feedback_collector.record(access_site_id, value.getTypeTag()) catch {};
    }

    switch (obj_val) {
        .object_val => |obj| {
            if (prop_idx < frame.function.constants.len) {
                const prop_const = frame.function.constants[prop_idx];
                if (prop_const == .string_val) {
                    const prop_name = prop_const.string_val;
                    obj.properties.put(vm.allocator, prop_name, value) catch return BytecodeVM.VMError.OutOfMemory;
                }
            }
            try vm.push(.{ .object_val = obj });
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

fn handleInstanceof(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const obj_val = try vm.pop();
    const class_id = inst.operand1;
    switch (obj_val) {
        .object_val => |obj| {
            try vm.push(.{ .bool_val = obj.class_id == class_id });
        },
        else => try vm.push(.{ .bool_val = false }),
    }
    return .continue_execution;
}

fn handleClone(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const obj_val = try vm.pop();
    switch (obj_val) {
        .object_val => |obj| {
            const cloned = vm.createObject(obj.class_id) catch return BytecodeVM.VMError.OutOfMemory;
            var iter = obj.properties.iterator();
            while (iter.next()) |entry| {
                cloned.properties.put(vm.allocator, entry.key_ptr.*, entry.value_ptr.*) catch return BytecodeVM.VMError.OutOfMemory;
            }
            try vm.push(.{ .object_val = cloned });
        },
        .array_val => |arr| {
            const cloned = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
            for (arr.elements.items) |elem| {
                cloned.elements.append(vm.allocator, elem) catch return BytecodeVM.VMError.OutOfMemory;
            }
            var iter = arr.keys.iterator();
            while (iter.next()) |entry| {
                cloned.keys.put(vm.allocator, entry.key_ptr.*, entry.value_ptr.*) catch return BytecodeVM.VMError.OutOfMemory;
            }
            try vm.push(.{ .array_val = cloned });
        },
        else => try vm.push(obj_val),
    }
    return .continue_execution;
}

// ========== 结构体操作处理函数 ==========

fn handleNewStruct(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const struct_id = inst.operand1;
    const field_count = inst.operand2;
    const instance = vm.allocator.create(Value.StructInstance) catch return BytecodeVM.VMError.OutOfMemory;
    instance.* = .{
        .struct_id = struct_id,
        .fields = vm.allocator.alloc(Value, field_count) catch return BytecodeVM.VMError.OutOfMemory,
        .ref_count = 1,
    };
    var i: usize = field_count;
    while (i > 0) {
        i -= 1;
        instance.fields[i] = try vm.pop();
    }
    try vm.push(.{ .struct_val = instance });
    return .continue_execution;
}

fn handleStructGet(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const struct_val = try vm.pop();
    const field_idx = inst.operand1;
    switch (struct_val) {
        .struct_val => |s| {
            if (field_idx < s.fields.len) {
                try vm.push(s.fields[field_idx]);
            } else {
                try vm.push(.null_val);
            }
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

fn handleStructSet(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = try vm.pop();
    const struct_val = try vm.pop();
    const field_idx = inst.operand1;
    switch (struct_val) {
        .struct_val => |s| {
            if (field_idx < s.fields.len) {
                s.fields[field_idx] = value;
            }
            try vm.push(.{ .struct_val = s });
        },
        else => try vm.push(.null_val),
    }
    return .continue_execution;
}

// ========== 类型转换处理函数 ==========

fn handleToInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .int_val = val.toInt() });
    return .continue_execution;
}

fn handleToFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .float_val = val.toFloat() });
    return .continue_execution;
}

fn handleToBool(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .bool_val = val.toBool() });
    return .continue_execution;
}

fn handleToString(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    const str_data = valueToString(vm, val) catch return BytecodeVM.VMError.OutOfMemory;
    const str = vm.createString(str_data) catch return BytecodeVM.VMError.OutOfMemory;
    try vm.push(.{ .string_val = str });
    return .continue_execution;
}

fn handleIsNull(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .bool_val = val == .null_val });
    return .continue_execution;
}

fn handleIsInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .bool_val = val == .int_val });
    return .continue_execution;
}

fn handleIsFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .bool_val = val == .float_val });
    return .continue_execution;
}

fn handleIsString(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .bool_val = val == .string_val });
    return .continue_execution;
}

fn handleIsArray(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .bool_val = val == .array_val });
    return .continue_execution;
}

fn handleIsObject(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    try vm.push(.{ .bool_val = val == .object_val });
    return .continue_execution;
}

// ========== 字符串操作处理函数 ==========

fn handleConcat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = try vm.pop();
    const a = try vm.pop();
    const str_a = valueToString(vm, a) catch return BytecodeVM.VMError.OutOfMemory;
    const str_b = valueToString(vm, b) catch return BytecodeVM.VMError.OutOfMemory;
    const result_len = str_a.len + str_b.len;
    const result_data = vm.allocator.alloc(u8, result_len) catch return BytecodeVM.VMError.OutOfMemory;
    @memcpy(result_data[0..str_a.len], str_a);
    @memcpy(result_data[str_a.len..], str_b);
    const result_str = vm.allocator.create(Value.String) catch return BytecodeVM.VMError.OutOfMemory;
    result_str.* = .{ .data = result_data, .ref_count = 1 };
    vm.string_pool.append(vm.allocator, result_str) catch return BytecodeVM.VMError.OutOfMemory;
    try vm.push(.{ .string_val = result_str });
    return .continue_execution;
}

fn handleStrlen(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = try vm.pop();
    switch (val) {
        .string_val => |s| try vm.push(.{ .int_val = @intCast(s.data.len) }),
        else => try vm.push(.{ .int_val = 0 }),
    }
    return .continue_execution;
}

// ========== 参数传递优化处理函数 ==========

/// PASS_BY_VALUE - 值传递
/// operand1 = 参数索引
/// 复制栈顶值到参数位置
fn handlePassByValue(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    _ = frame;
    const param_idx = inst.operand1;
    
    // 获取栈顶值
    const value = try vm.pop();
    
    // 对于复杂类型，需要深拷贝
    const copied_value = switch (value) {
        .string_val => |s| blk: {
            // 复制字符串
            const new_data = vm.allocator.dupe(u8, s.data) catch return BytecodeVM.VMError.OutOfMemory;
            const new_str = vm.allocator.create(Value.String) catch return BytecodeVM.VMError.OutOfMemory;
            new_str.* = .{ .data = new_data, .ref_count = 1 };
            vm.string_pool.append(vm.allocator, new_str) catch return BytecodeVM.VMError.OutOfMemory;
            break :blk Value{ .string_val = new_str };
        },
        .array_val => |a| blk: {
            // 复制数组
            const new_arr = vm.allocator.create(Value.Array) catch return BytecodeVM.VMError.OutOfMemory;
            new_arr.* = .{
                .elements = .{},
                .keys = .{},
                .ref_count = 1,
            };
            // 复制元素
            new_arr.elements.ensureTotalCapacity(vm.allocator, a.elements.items.len) catch return BytecodeVM.VMError.OutOfMemory;
            for (a.elements.items) |elem| {
                new_arr.elements.append(vm.allocator, elem) catch return BytecodeVM.VMError.OutOfMemory;
            }
            vm.array_pool.append(vm.allocator, new_arr) catch return BytecodeVM.VMError.OutOfMemory;
            break :blk Value{ .array_val = new_arr };
        },
        else => value, // 基本类型直接复制
    };
    
    // 存储到参数位置
    const base = if (vm.frame_count > 0) vm.frames[vm.frame_count - 1].base_pointer else 0;
    vm.stack[base + param_idx] = copied_value;
    
    return .continue_execution;
}

/// PASS_BY_REF - 引用传递
/// operand1 = 参数索引
/// 直接传递引用，不复制
fn handlePassByRef(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    _ = frame;
    const param_idx = inst.operand1;
    
    // 获取栈顶值（不复制）
    const value = try vm.pop();
    
    // 增加引用计数
    switch (value) {
        .string_val => |s| {
            s.ref_count += 1;
        },
        .array_val => |a| {
            a.ref_count += 1;
        },
        .object_val => |o| {
            o.ref_count += 1;
        },
        else => {},
    }
    
    // 存储到参数位置
    const base = if (vm.frame_count > 0) vm.frames[vm.frame_count - 1].base_pointer else 0;
    vm.stack[base + param_idx] = value;
    
    return .continue_execution;
}

/// PASS_BY_COW - Copy-on-Write传递
/// operand1 = 参数索引
/// 共享数据直到修改时才复制
fn handlePassByCow(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    _ = frame;
    const param_idx = inst.operand1;
    
    // 获取栈顶值
    const value = try vm.pop();
    
    // COW语义：增加引用计数，标记为共享
    // 实际的复制会在写入时发生（由cow_check/cow_copy处理）
    switch (value) {
        .string_val => |s| {
            s.ref_count += 1;
        },
        .array_val => |a| {
            a.ref_count += 1;
        },
        .object_val => |o| {
            o.ref_count += 1;
        },
        else => {},
    }
    
    // 存储到参数位置
    const base = if (vm.frame_count > 0) vm.frames[vm.frame_count - 1].base_pointer else 0;
    vm.stack[base + param_idx] = value;
    
    return .continue_execution;
}

/// PASS_BY_MOVE - 移动传递
/// operand1 = 参数索引
/// 转移所有权，原位置变为null
fn handlePassByMove(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    _ = frame;
    const param_idx = inst.operand1;
    
    // 获取栈顶值
    const value = try vm.pop();
    
    // 移动语义：直接转移，不增加引用计数
    // 原位置会被设置为null（由调用者处理）
    
    // 存储到参数位置
    const base = if (vm.frame_count > 0) vm.frames[vm.frame_count - 1].base_pointer else 0;
    vm.stack[base + param_idx] = value;
    
    return .continue_execution;
}

/// COW_CHECK - 检查是否需要复制
/// operand1 = 局部变量索引
/// 如果引用计数>1，压入true；否则压入false
fn handleCowCheck(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const local_idx = inst.operand1;
    const base = frame.base_pointer;
    const value = vm.stack[base + local_idx];
    
    const needs_copy = switch (value) {
        .string_val => |s| s.ref_count > 1,
        .array_val => |a| a.ref_count > 1,
        .object_val => |o| o.ref_count > 1,
        else => false,
    };
    
    try vm.push(.{ .bool_val = needs_copy });
    return .continue_execution;
}

/// COW_COPY - 执行写时复制
/// 复制栈顶的共享值，使其成为独占
fn handleCowCopy(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = try vm.pop();
    
    const copied_value = switch (value) {
        .string_val => |s| blk: {
            if (s.ref_count <= 1) {
                // 已经是独占，不需要复制
                break :blk value;
            }
            // 减少原引用计数
            s.ref_count -= 1;
            // 创建新副本
            const new_data = vm.allocator.dupe(u8, s.data) catch return BytecodeVM.VMError.OutOfMemory;
            const new_str = vm.allocator.create(Value.String) catch return BytecodeVM.VMError.OutOfMemory;
            new_str.* = .{ .data = new_data, .ref_count = 1 };
            vm.string_pool.append(vm.allocator, new_str) catch return BytecodeVM.VMError.OutOfMemory;
            break :blk Value{ .string_val = new_str };
        },
        .array_val => |a| blk: {
            if (a.ref_count <= 1) {
                // 已经是独占，不需要复制
                break :blk value;
            }
            // 减少原引用计数
            a.ref_count -= 1;
            // 创建新副本
            const new_arr = vm.allocator.create(Value.Array) catch return BytecodeVM.VMError.OutOfMemory;
            new_arr.* = .{
                .elements = .{},
                .keys = .{},
                .ref_count = 1,
            };
            new_arr.elements.ensureTotalCapacity(vm.allocator, a.elements.items.len) catch return BytecodeVM.VMError.OutOfMemory;
            for (a.elements.items) |elem| {
                new_arr.elements.append(vm.allocator, elem) catch return BytecodeVM.VMError.OutOfMemory;
            }
            vm.array_pool.append(vm.allocator, new_arr) catch return BytecodeVM.VMError.OutOfMemory;
            break :blk Value{ .array_val = new_arr };
        },
        .object_val => |o| blk: {
            if (o.ref_count <= 1) {
                break :blk value;
            }
            o.ref_count -= 1;
            // 创建新对象副本
            const new_obj = vm.allocator.create(Value.Object) catch return BytecodeVM.VMError.OutOfMemory;
            new_obj.* = .{
                .class_id = o.class_id,
                .properties = .{},
                .ref_count = 1,
            };
            // 复制属性
            var iter = o.properties.iterator();
            while (iter.next()) |entry| {
                new_obj.properties.put(vm.allocator, entry.key_ptr.*, entry.value_ptr.*) catch return BytecodeVM.VMError.OutOfMemory;
            }
            vm.object_pool.append(vm.allocator, new_obj) catch return BytecodeVM.VMError.OutOfMemory;
            break :blk Value{ .object_val = new_obj };
        },
        else => value,
    };
    
    try vm.push(copied_value);
    return .continue_execution;
}

/// RET_MOVE - 移动返回
/// operand1 = 返回值的局部变量索引
/// 使用移动语义返回大对象，避免复制
fn handleRetMove(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const local_idx = inst.operand1;
    const base = frame.base_pointer;
    const return_value = vm.stack[base + local_idx];
    
    // 移动语义：直接返回，不增加引用计数
    // 原位置会被清理（由函数返回逻辑处理）
    
    // 恢复调用帧
    if (vm.frame_count > 1) {
        vm.frame_count -= 1;
        vm.stack_top = frame.base_pointer;
        try vm.push(return_value);
        return .frame_changed;
    } else {
        return .{ .return_value = return_value };
    }
}

/// RET_COW - COW返回
/// operand1 = 返回值的局部变量索引
/// 返回共享值，调用者可以继续共享或触发COW
fn handleRetCow(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const local_idx = inst.operand1;
    const base = frame.base_pointer;
    const return_value = vm.stack[base + local_idx];
    
    // COW返回：增加引用计数，允许调用者共享
    switch (return_value) {
        .string_val => |s| {
            s.ref_count += 1;
        },
        .array_val => |a| {
            a.ref_count += 1;
        },
        .object_val => |o| {
            o.ref_count += 1;
        },
        else => {},
    }
    
    // 恢复调用帧
    if (vm.frame_count > 1) {
        vm.frame_count -= 1;
        vm.stack_top = frame.base_pointer;
        try vm.push(return_value);
        return .frame_changed;
    } else {
        return .{ .return_value = return_value };
    }
}
