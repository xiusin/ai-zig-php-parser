const std = @import("std");

/// 字节码指令 - 高性能PHP虚拟机核心
/// 设计原则：
/// 1. 紧凑编码 - 每条指令固定6字节，缓存友好
/// 2. 类型特化 - 避免运行时类型检查开销
/// 3. 直接跳转 - 使用计算跳转表替代switch
pub const Instruction = packed struct {
    opcode: OpCode,
    operand1: u16,
    operand2: u16,
    flags: InstructionFlags,

    pub const InstructionFlags = packed struct {
        type_hint: TypeHint = .unknown,
        is_tail_call: bool = false,
        needs_gc_check: bool = false,
        _padding: u2 = 0,
    };

    pub const TypeHint = enum(u3) {
        unknown = 0,
        integer = 1,
        float = 2,
        string = 3,
        array = 4,
        object = 5,
        boolean = 6,
        null_type = 7,
    };

    /// 创建指令
    pub fn init(opcode: OpCode, op1: u16, op2: u16) Instruction {
        return Instruction{
            .opcode = opcode,
            .operand1 = op1,
            .operand2 = op2,
            .flags = .{},
        };
    }

    /// 带类型提示的指令
    pub fn withTypeHint(opcode: OpCode, op1: u16, op2: u16, hint: TypeHint) Instruction {
        return Instruction{
            .opcode = opcode,
            .operand1 = op1,
            .operand2 = op2,
            .flags = .{ .type_hint = hint },
        };
    }

    /// 尾调用优化标记
    pub fn asTailCall(self: Instruction) Instruction {
        var inst = self;
        inst.flags.is_tail_call = true;
        return inst;
    }
};

/// 操作码定义 - 按功能分组，便于扩展
pub const OpCode = enum(u8) {
    // ========== 栈操作 (0x00-0x0F) ==========
    nop = 0x00,
    push_const = 0x01, // 压入常量池中的值
    push_local = 0x02, // 压入局部变量
    push_global = 0x03, // 压入全局变量
    pop = 0x04, // 弹出栈顶
    dup = 0x05, // 复制栈顶
    swap = 0x06, // 交换栈顶两个元素
    push_null = 0x07, // 压入null
    push_true = 0x08, // 压入true
    push_false = 0x09, // 压入false
    push_int_0 = 0x0A, // 压入整数0（常用优化）
    push_int_1 = 0x0B, // 压入整数1
    store_local = 0x0C, // 存储到局部变量
    store_global = 0x0D, // 存储到全局变量

    // ========== 整数算术 (0x10-0x1F) ==========
    add_int = 0x10,
    sub_int = 0x11,
    mul_int = 0x12,
    div_int = 0x13,
    mod_int = 0x14,
    neg_int = 0x15, // 取负
    inc_int = 0x16, // 自增
    dec_int = 0x17, // 自减
    pow_int = 0x18, // 幂运算
    bit_and = 0x19,
    bit_or = 0x1A,
    bit_xor = 0x1B,
    bit_not = 0x1C,
    shl = 0x1D, // 左移
    shr = 0x1E, // 右移

    // ========== 浮点算术 (0x20-0x2F) ==========
    add_float = 0x20,
    sub_float = 0x21,
    mul_float = 0x22,
    div_float = 0x23,
    mod_float = 0x24,
    neg_float = 0x25,
    floor = 0x26,
    ceil = 0x27,
    round = 0x28,
    sqrt = 0x29,
    sin = 0x2A,
    cos = 0x2B,
    tan = 0x2C,
    log = 0x2D,
    exp = 0x2E,

    // ========== 字符串操作 (0x30-0x3F) ==========
    concat = 0x30, // 字符串连接
    strlen = 0x31, // 字符串长度
    substr = 0x32, // 子字符串
    str_cmp = 0x33, // 字符串比较
    str_lower = 0x34, // 转小写
    str_upper = 0x35, // 转大写
    str_trim = 0x36, // 去空白
    str_index = 0x37, // 查找子串
    str_replace = 0x38, // 替换
    str_split = 0x39, // 分割
    str_join = 0x3A, // 连接数组为字符串
    interpolate = 0x3B, // 字符串插值

    // ========== 比较操作 (0x40-0x4F) ==========
    eq = 0x40, // ==
    neq = 0x41, // !=
    identical = 0x42, // ===
    not_identical = 0x43, // !==
    lt = 0x44, // <
    le = 0x45, // <=
    gt = 0x46, // >
    ge = 0x47, // >=
    spaceship = 0x48, // <=>
    eq_int = 0x49, // 整数快速比较
    lt_int = 0x4A,
    gt_int = 0x4B,
    eq_float = 0x4C,
    lt_float = 0x4D,
    gt_float = 0x4E,

    // ========== 逻辑操作 (0x50-0x57) ==========
    logic_and = 0x50,
    logic_or = 0x51,
    logic_not = 0x52,
    logic_xor = 0x53,
    coalesce = 0x54, // ??

    // ========== 控制流 (0x58-0x6F) ==========
    jmp = 0x58, // 无条件跳转
    jz = 0x59, // 为零/假跳转
    jnz = 0x5A, // 非零/真跳转
    jlt = 0x5B, // 小于跳转
    jle = 0x5C, // 小于等于跳转
    jgt = 0x5D, // 大于跳转
    jge = 0x5E, // 大于等于跳转
    call = 0x5F, // 函数调用
    call_method = 0x60, // 方法调用
    call_static = 0x61, // 静态方法调用
    call_builtin = 0x62, // 内置函数调用
    ret = 0x63, // 返回
    ret_void = 0x64, // 返回void
    switch_int = 0x65, // 整数switch
    switch_str = 0x66, // 字符串switch
    loop_start = 0x67, // 循环开始标记（JIT热点检测）
    loop_end = 0x68, // 循环结束标记

    // ========== 数组操作 (0x70-0x7F) ==========
    new_array = 0x70, // 创建数组
    array_get = 0x71, // 获取元素
    array_set = 0x72, // 设置元素
    array_push = 0x73, // 追加元素
    array_pop = 0x74, // 弹出元素
    array_shift = 0x75, // 移除第一个
    array_unshift = 0x76, // 在开头插入
    array_len = 0x77, // 数组长度
    array_keys = 0x78, // 获取所有键
    array_values = 0x79, // 获取所有值
    array_merge = 0x7A, // 合并数组
    array_slice = 0x7B, // 数组切片
    array_exists = 0x7C, // 键是否存在
    array_unset = 0x7D, // 删除元素
    foreach_init = 0x7E, // foreach初始化
    foreach_next = 0x7F, // foreach下一个

    // ========== 对象操作 (0x80-0x8F) ==========
    new_object = 0x80, // 创建对象
    get_prop = 0x81, // 获取属性
    set_prop = 0x82, // 设置属性
    get_static = 0x83, // 获取静态属性
    set_static = 0x84, // 设置静态属性
    instanceof = 0x85, // instanceof检查
    clone = 0x86, // 克隆对象
    get_class = 0x87, // 获取类名
    get_parent = 0x88, // 获取父类
    init_prop = 0x89, // 初始化属性（构造函数用）
    nullsafe_get = 0x8A, // ?->属性访问
    nullsafe_call = 0x8B, // ?->方法调用

    // ========== 结构体操作 (0x90-0x9F) - Go风格 ==========
    new_struct = 0x90, // 创建结构体实例
    struct_get = 0x91, // 获取结构体字段
    struct_set = 0x92, // 设置结构体字段
    struct_method = 0x93, // 调用结构体方法
    interface_call = 0x94, // 接口方法调用（鸭子类型）
    type_assert = 0x95, // 类型断言
    embed_access = 0x96, // 嵌入结构体访问

    // ========== 异常处理 (0xA0-0xAF) ==========
    try_begin = 0xA0, // try块开始
    try_end = 0xA1, // try块结束
    catch_begin = 0xA2, // catch块开始
    catch_end = 0xA3, // catch块结束
    finally_begin = 0xA4, // finally块开始
    finally_end = 0xA5, // finally块结束
    throw = 0xA6, // 抛出异常
    rethrow = 0xA7, // 重新抛出

    // ========== 协程操作 (0xB0-0xBF) ==========
    yield_val = 0xB0, // yield值
    yield_from = 0xB1, // yield from
    await_val = 0xB2, // await
    async_call = 0xB3, // 异步调用
    coroutine_create = 0xB4, // 创建协程
    coroutine_resume = 0xB5, // 恢复协程
    coroutine_suspend = 0xB6, // 挂起协程
    channel_send = 0xB7, // 通道发送
    channel_recv = 0xB8, // 通道接收

    // ========== 类型操作 (0xC0-0xCF) ==========
    type_check = 0xC0, // 类型检查
    type_cast = 0xC1, // 类型转换
    to_int = 0xC2, // 转整数
    to_float = 0xC3, // 转浮点
    to_string = 0xC4, // 转字符串
    to_bool = 0xC5, // 转布尔
    to_array = 0xC6, // 转数组
    to_object = 0xC7, // 转对象
    is_null = 0xC8, // 是否null
    is_int = 0xC9, // 是否整数
    is_float = 0xCA, // 是否浮点
    is_string = 0xCB, // 是否字符串
    is_array = 0xCC, // 是否数组
    is_object = 0xCD, // 是否对象
    is_callable = 0xCE, // 是否可调用

    // ========== 类型守卫 - JIT优化 (0xD0-0xDF) ==========
    guard_int = 0xD0, // 整数类型守卫
    guard_float = 0xD1, // 浮点类型守卫
    guard_string = 0xD2, // 字符串类型守卫
    guard_array = 0xD3, // 数组类型守卫
    guard_object = 0xD4, // 对象类型守卫
    guard_class = 0xD5, // 特定类守卫
    guard_shape = 0xD6, // 对象形状守卫（内联缓存）
    deoptimize = 0xD7, // 去优化回退

    // ========== 闭包操作 (0xE0-0xEF) ==========
    make_closure = 0xE0, // 创建闭包
    closure_call = 0xE1, // 调用闭包
    capture_var = 0xE2, // 捕获变量
    arrow_fn = 0xE3, // 箭头函数

    // ========== 调试与元操作 (0xF0-0xFF) ==========
    debug_break = 0xF0, // 调试断点
    line_number = 0xF1, // 行号标记
    profile_enter = 0xF2, // 性能分析入口
    profile_exit = 0xF3, // 性能分析出口
    gc_safepoint = 0xF4, // GC安全点
    assert = 0xF5, // 断言
    print_debug = 0xF6, // 调试输出
    halt = 0xFF, // 停止执行

    /// 获取指令名称
    pub fn name(self: OpCode) []const u8 {
        return @tagName(self);
    }

    /// 获取操作数数量
    pub fn operandCount(self: OpCode) u8 {
        return switch (self) {
            .nop, .pop, .dup, .swap, .push_null, .push_true, .push_false, .push_int_0, .push_int_1, .ret_void, .halt => 0,

            .push_const, .push_local, .push_global, .store_local, .store_global, .jmp, .jz, .jnz, .call, .new_array, .new_object, .new_struct, .throw, .guard_int, .guard_float, .guard_string => 1,

            else => 2,
        };
    }

    /// 是否为跳转指令
    pub fn isJump(self: OpCode) bool {
        return switch (self) {
            .jmp, .jz, .jnz, .jlt, .jle, .jgt, .jge, .switch_int, .switch_str, .foreach_next => true,
            else => false,
        };
    }

    /// 是否为调用指令
    pub fn isCall(self: OpCode) bool {
        return switch (self) {
            .call, .call_method, .call_static, .call_builtin, .closure_call, .async_call, .interface_call => true,
            else => false,
        };
    }

    /// 是否会改变控制流
    pub fn isTerminator(self: OpCode) bool {
        return switch (self) {
            .ret, .ret_void, .throw, .rethrow, .halt => true,
            else => self.isJump(),
        };
    }
};

/// 编译后的函数
pub const CompiledFunction = struct {
    name: []const u8,
    bytecode: []Instruction,
    constants: []Value,
    local_count: u16,
    arg_count: u16,
    max_stack: u16,
    flags: FunctionFlags,
    line_table: []LineInfo,
    exception_table: []ExceptionEntry,

    pub const FunctionFlags = packed struct {
        is_generator: bool = false,
        is_async: bool = false,
        is_variadic: bool = false,
        has_return_type: bool = false,
        is_method: bool = false,
        is_static: bool = false,
        is_closure: bool = false,
        _padding: u1 = 0,
    };

    pub const LineInfo = struct {
        bytecode_offset: u32,
        line_number: u32,
    };

    pub const ExceptionEntry = struct {
        try_start: u32,
        try_end: u32,
        handler_offset: u32,
        catch_type: ?u16,
        finally_offset: ?u32,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*CompiledFunction {
        const func = try allocator.create(CompiledFunction);
        func.* = CompiledFunction{
            .name = name,
            .bytecode = &[_]Instruction{},
            .constants = &[_]Value{},
            .local_count = 0,
            .arg_count = 0,
            .max_stack = 0,
            .flags = .{},
            .line_table = &[_]LineInfo{},
            .exception_table = &[_]ExceptionEntry{},
        };
        return func;
    }

    pub fn deinit(self: *CompiledFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.bytecode);
        for (self.constants) |*constant| {
            constant.release(allocator);
        }
        allocator.free(self.constants);
        allocator.free(self.line_table);
        allocator.free(self.exception_table);
        allocator.destroy(self);
    }
};

/// 常量池中的值类型
pub const Value = union(enum) {
    null_val,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_val: []const u8,
    array_val: *ArrayConstant,
    class_ref: u16,
    func_ref: u16,

    pub const ArrayConstant = struct {
        keys: []Value,
        values: []Value,
    };

    pub fn release(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array_val => |arr| {
                allocator.free(arr.keys);
                allocator.free(arr.values);
                allocator.destroy(arr);
            },
            else => {},
        }
    }
};

/// 字节码模块 - 包含多个函数
pub const BytecodeModule = struct {
    name: []const u8,
    functions: std.StringHashMap(*CompiledFunction),
    classes: std.StringHashMap(*CompiledClass),
    structs: std.StringHashMap(*CompiledStruct),
    global_constants: std.StringHashMap(Value),
    main_function: ?*CompiledFunction,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) BytecodeModule {
        return BytecodeModule{
            .name = name,
            .functions = std.StringHashMap(*CompiledFunction).init(allocator),
            .classes = std.StringHashMap(*CompiledClass).init(allocator),
            .structs = std.StringHashMap(*CompiledStruct).init(allocator),
            .global_constants = std.StringHashMap(Value).init(allocator),
            .main_function = null,
        };
    }

    pub fn deinit(self: *BytecodeModule, allocator: std.mem.Allocator) void {
        var func_iter = self.functions.iterator();
        while (func_iter.next()) |entry| {
            entry.value_ptr.*.deinit(allocator);
        }
        self.functions.deinit();

        var class_iter = self.classes.iterator();
        while (class_iter.next()) |entry| {
            entry.value_ptr.*.deinit(allocator);
        }
        self.classes.deinit();

        self.structs.deinit();
        self.global_constants.deinit();
    }

    pub fn addFunction(self: *BytecodeModule, func: *CompiledFunction) !void {
        try self.functions.put(func.name, func);
    }

    pub fn getFunction(self: *BytecodeModule, name: []const u8) ?*CompiledFunction {
        return self.functions.get(name);
    }
};

/// 编译后的类
pub const CompiledClass = struct {
    name: []const u8,
    parent: ?[]const u8,
    interfaces: [][]const u8,
    properties: std.StringHashMap(PropertyInfo),
    methods: std.StringHashMap(*CompiledFunction),
    constants: std.StringHashMap(Value),
    flags: ClassFlags,

    pub const PropertyInfo = struct {
        type_hint: ?[]const u8,
        default_value: ?Value,
        visibility: Visibility,
        is_static: bool,
        is_readonly: bool,
    };

    pub const Visibility = enum(u2) {
        public = 0,
        protected = 1,
        private = 2,
    };

    pub const ClassFlags = packed struct {
        is_abstract: bool = false,
        is_final: bool = false,
        is_interface: bool = false,
        is_trait: bool = false,
        is_enum: bool = false,
        _padding: u3 = 0,
    };

    pub fn deinit(self: *CompiledClass, allocator: std.mem.Allocator) void {
        var method_iter = self.methods.iterator();
        while (method_iter.next()) |entry| {
            entry.value_ptr.*.deinit(allocator);
        }
        self.methods.deinit();
        self.properties.deinit();
        self.constants.deinit();
        allocator.destroy(self);
    }
};

/// 编译后的结构体（Go风格）
pub const CompiledStruct = struct {
    name: []const u8,
    fields: []FieldInfo,
    methods: std.StringHashMap(*CompiledFunction),
    embedded: [][]const u8,
    interfaces: [][]const u8,
    type_params: []TypeParam,
    size: usize,
    alignment: usize,

    pub const FieldInfo = struct {
        name: []const u8,
        type_hint: ?[]const u8,
        offset: usize,
        tags: ?[]const u8,
        is_public: bool,
    };

    pub const TypeParam = struct {
        name: []const u8,
        constraint: ?[]const u8,
    };
};

test "instruction creation" {
    const inst = Instruction.init(.push_const, 42, 0);
    try std.testing.expect(inst.opcode == .push_const);
    try std.testing.expect(inst.operand1 == 42);
}

test "opcode properties" {
    try std.testing.expect(OpCode.jmp.isJump());
    try std.testing.expect(!OpCode.add_int.isJump());
    try std.testing.expect(OpCode.call.isCall());
    try std.testing.expect(OpCode.ret.isTerminator());
}
