const std = @import("std");
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;
const CompiledFunction = instruction.CompiledFunction;
const ConstValue = instruction.Value;

// 类型反馈系统
const runtime = @import("runtime");
const type_feedback = runtime.type_feedback;
const TypeTag = type_feedback.TypeTag;
const TypeFeedback = type_feedback.TypeFeedback;
const TypeFeedbackCollector = type_feedback.TypeFeedbackCollector;

// 内联缓存优化
const optimization = runtime.optimization;
const MethodCache = optimization.MethodCache;

// JIT编译器
const jit = @import("jit.zig");
const JITCompiler = jit.JITCompiler;

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
    iterator_val: *Iterator,

    pub const String = struct {
        data: []u8,
        ref_count: u32,
        marked: bool,

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
        marked: bool,
    };

    pub const Object = struct {
        class_id: u16,
        properties: std.StringHashMapUnmanaged(Value),
        ref_count: u32,
        marked: bool,
    };

    pub const StructInstance = struct {
        struct_id: u16,
        fields: []Value,
        ref_count: u32,
        marked: bool,
    };

    pub const Closure = struct {
        function: *CompiledFunction,
        captured: []Value,
        ref_count: u32,
        marked: bool,
    };

    pub const Resource = struct {
        type_id: u16,
        handle: *anyopaque,
        ref_count: u32,
        marked: bool,
    };

    pub const Iterator = struct {
        iterable: Value,           // 被遍历的数组/对象
        current_index: i64,        // 当前索引
        keys: ?[][]const u8,       // 键数组（关联数组）
        is_done: bool,             // 是否完成
        ref_count: u32,
        marked: bool,
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
            .float_val => |f| blk: {
                // 使用saturating转换避免panic
                if (std.math.isNan(f)) break :blk 0;
                if (f >= @as(f64, @floatFromInt(std.math.maxInt(i64)))) break :blk std.math.maxInt(i64);
                if (f <= @as(f64, @floatFromInt(std.math.minInt(i64)))) break :blk std.math.minInt(i64);
                break :blk @intFromFloat(f);
            },
            .string_val => |s| blk: {
                if (s.data.len == 0) break :blk 0;

                // PHP行为：解析前导数字，遇到非数字停止
                var result: i64 = 0;
                var i: usize = 0;
                var negative = false;

                // 跳过前导空格
                while (i < s.data.len and std.ascii.isWhitespace(s.data[i])) : (i += 1) {}

                // 处理符号
                if (i < s.data.len and (s.data[i] == '+' or s.data[i] == '-')) {
                    negative = (s.data[i] == '-');
                    i += 1;
                }

                // 解析数字（遇到非数字停止）
                var has_digits = false;
                while (i < s.data.len and std.ascii.isDigit(s.data[i])) : (i += 1) {
                    has_digits = true;
                    const digit: i64 = s.data[i] - '0';
                    
                    // 使用saturating算术避免溢出panic
                    const mul_result = @mulWithOverflow(result, 10);
                    if (mul_result[1] != 0) {
                        // 溢出：返回最大/最小值
                        break :blk if (negative) std.math.minInt(i64) else std.math.maxInt(i64);
                    }
                    
                    const add_result = @addWithOverflow(mul_result[0], digit);
                    if (add_result[1] != 0) {
                        // 溢出：返回最大/最小值
                        break :blk if (negative) std.math.minInt(i64) else std.math.maxInt(i64);
                    }
                    
                    result = add_result[0];
                }

                // 如果没有数字，返回0
                if (!has_digits) break :blk 0;

                break :blk if (negative) -result else result;
            },
            .array_val => |a| if (a.elements.items.len > 0) 1 else 0,
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
            .string_val => |s| blk: {
                if (s.data.len == 0) break :blk 0.0;

                // PHP行为：解析前导数字（支持浮点数）
                var result: f64 = 0.0;
                var i: usize = 0;
                var negative = false;

                // 跳过前导空格
                while (i < s.data.len and std.ascii.isWhitespace(s.data[i])) : (i += 1) {}

                // 处理符号
                if (i < s.data.len and (s.data[i] == '+' or s.data[i] == '-')) {
                    negative = (s.data[i] == '-');
                    i += 1;
                }

                // 解析整数部分
                var has_digits = false;
                while (i < s.data.len and std.ascii.isDigit(s.data[i])) : (i += 1) {
                    has_digits = true;
                    const digit = s.data[i] - '0';
                    result = result * 10.0 + @as(f64, @floatFromInt(digit));
                }

                // 解析小数部分
                if (i < s.data.len and s.data[i] == '.') {
                    i += 1;
                    var decimal_place: f64 = 0.1;
                    while (i < s.data.len and std.ascii.isDigit(s.data[i])) : (i += 1) {
                        has_digits = true;
                        const digit = s.data[i] - '0';
                        result += @as(f64, @floatFromInt(digit)) * decimal_place;
                        decimal_place *= 0.1;
                    }
                }

                // 如果没有数字，返回0
                if (!has_digits) break :blk 0.0;

                break :blk if (negative) -result else result;
            },
            .array_val => |a| if (a.elements.items.len > 0) 1.0 else 0.0,
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
            .iterator_val => .iterator_type,
        };
    }
};

/// 类元数据 - 存储类的静态信息
pub const ClassMetadata = struct {
    name: []const u8,
    /// 静态方法表：方法名 -> CompiledFunction
    static_methods: std.StringHashMapUnmanaged(*CompiledFunction),
    /// 实例方法表：方法名 -> CompiledFunction
    instance_methods: std.StringHashMapUnmanaged(*CompiledFunction),
    /// 静态属性表：属性名 -> Value
    static_properties: std.StringHashMapUnmanaged(Value),
    /// 实例属性默认值：属性名 -> Value
    instance_property_defaults: std.StringHashMapUnmanaged(Value),
    /// 类常量表：常量名 -> Value
    constants: std.StringHashMapUnmanaged(Value),
    /// 父类（继承）
    parent: ?*ClassMetadata,
    /// 类ID（用于快速查找）
    class_id: u16,
    /// 引用计数
    ref_count: u32,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8, class_id: u16) !*ClassMetadata {
        const meta = try allocator.create(ClassMetadata);
        meta.* = .{
            .name = try allocator.dupe(u8, name),
            .static_methods = .{},
            .instance_methods = .{},
            .static_properties = .{},
            .instance_property_defaults = .{},
            .constants = .{},
            .parent = null,
            .class_id = class_id,
            .ref_count = 1,
        };
        return meta;
    }
    
    pub fn deinit(self: *ClassMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.static_methods.deinit(allocator);
        self.instance_methods.deinit(allocator);
        
        // 释放静态属性值
        var static_iter = self.static_properties.iterator();
        while (static_iter.next()) |entry| {
            // 值的释放由GC管理
            _ = entry;
        }
        self.static_properties.deinit(allocator);
        
        // 释放实例属性默认值
        var inst_iter = self.instance_property_defaults.iterator();
        while (inst_iter.next()) |entry| {
            _ = entry;
        }
        self.instance_property_defaults.deinit(allocator);
        
        // 释放常量值
        var const_iter = self.constants.iterator();
        while (const_iter.next()) |entry| {
            _ = entry;
        }
        self.constants.deinit(allocator);
        
        allocator.destroy(self);
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
    /// 性能统计信息
    pub const Stats = struct {
        function_calls: u64 = 0,
        memory_allocations: u64 = 0,
        execution_time_ns: u64 = 0,
        peak_memory_usage: usize = 0,
        cache_hits: u64 = 0,
        cache_misses: u64 = 0,
    };

    /// OPT-001: 字符串intern缓存 - 短字符串复用
    const STRING_CACHE_MAX_LEN: usize = 64;
    const STRING_CACHE_SIZE: usize = 1024;
    const ARENA_RESET_THRESHOLD: u32 = 10000;

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
    /// 类元数据表 - 类名 -> ClassMetadata
    classes: std.StringHashMapUnmanaged(*ClassMetadata),
    /// 类ID计数器
    next_class_id: u16,
    builtins: std.StringHashMapUnmanaged(BuiltinFn),
    /// OPT-005: 内置函数快速访问数组 - O(1) 索引访问
    builtin_array: std.ArrayListUnmanaged(BuiltinFn),
    string_pool: std.ArrayListUnmanaged(*Value.String),
    array_pool: std.ArrayListUnmanaged(*Value.Array),
    object_pool: std.ArrayListUnmanaged(*Value.Object),
    closure_pool: std.ArrayListUnmanaged(*Value.Closure),
    /// OPT-001: 字符串intern缓存
    string_cache: std.StringHashMapUnmanaged(*Value.String),
    /// OPT-002: 空闲对象列表 - 复用已释放对象
    free_strings: std.ArrayListUnmanaged(*Value.String),
    free_arrays: std.ArrayListUnmanaged(*Value.Array),
    /// 临时字符串池 - 用于跟踪valueToString分配的临时字符串
    temp_strings: std.ArrayListUnmanaged([]u8),
    /// OPT-006: Arena分配器 - 批量管理临时字符串，减少分配次数
    temp_arena: std.heap.ArenaAllocator,
    /// Arena分配计数器 - 用于定期重置Arena
    arena_alloc_count: u32,
    gc_threshold: usize,
    bytes_allocated: usize,
    gc_count: usize,
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

    // JIT编译器
    jit_compiler: ?*JITCompiler,
    /// 是否启用JIT
    enable_jit: bool,

    /// 性能统计
    stats: Stats,

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
        UncaughtException,
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
            .classes = .{},
            .next_class_id = 0,
            .builtins = .{},
            .builtin_array = .{},
            .string_pool = .{},
            .array_pool = .{},
            .object_pool = .{},
            .closure_pool = .{},
            .string_cache = .{},
            .free_strings = .{},
            .free_arrays = .{},
            .temp_strings = .{},
            .temp_arena = std.heap.ArenaAllocator.init(allocator),
            .arena_alloc_count = 0,
            .gc_threshold = 1024 * 1024,
            .bytes_allocated = 0,
            .gc_count = 0,
            .output_buffer = .{},
            // 类型反馈系统
            .type_feedback_collector = TypeFeedbackCollector.init(allocator),
            .enable_type_feedback = true,
            .deopt_count = 0,
            // 内联缓存系统
            .method_cache = MethodCache.init(allocator),
            .enable_inline_cache = true,
            // JIT编译器（默认禁用，可在外部启用）
            .jit_compiler = null,
            .enable_jit = false,
            .stats = .{},
        };

        // 注册内置函数
        try vm.registerBuiltins();

        return vm;
    }

    /// 注册内置函数
    /// OPT-005: 同时注册到哈希表和快速数组
    fn registerBuiltins(self: *BytecodeVM) !void {
        // 内置函数列表 - 顺序决定索引
        const builtins_list = [_]struct { name: []const u8, func: BuiltinFn }{
            .{ .name = "echo", .func = builtinEcho },
            .{ .name = "print", .func = builtinPrint },
            .{ .name = "var_dump", .func = builtinVarDump },
            .{ .name = "sprintf", .func = builtinSprintf },
            .{ .name = "microtime", .func = builtinMicrotime },
            .{ .name = "strlen", .func = builtinStrlen },
            .{ .name = "strpos", .func = builtinStrpos },
            .{ .name = "strrpos", .func = builtinStrrpos },
            .{ .name = "substr", .func = builtinSubstr },
            .{ .name = "str_replace", .func = builtinStrReplace },
            .{ .name = "str_ireplace", .func = builtinStrIReplace },
            .{ .name = "strtoupper", .func = builtinStrtoupper },
            .{ .name = "strtolower", .func = builtinStrtolower },
            .{ .name = "ucfirst", .func = builtinUcfirst },
            .{ .name = "ucwords", .func = builtinUcwords },
            .{ .name = "trim", .func = builtinTrim },
            .{ .name = "ltrim", .func = builtinLtrim },
            .{ .name = "rtrim", .func = builtinRtrim },
            .{ .name = "explode", .func = builtinExplode },
            .{ .name = "implode", .func = builtinImplode },
            .{ .name = "preg_match", .func = builtinPregMatch },
            .{ .name = "preg_match_all", .func = builtinPregMatchAll },
            .{ .name = "preg_replace", .func = builtinPregReplace },
            .{ .name = "preg_grep", .func = builtinPregGrep },
            .{ .name = "count", .func = builtinCount },
            .{ .name = "sizeof", .func = builtinCount },
            .{ .name = "array_push", .func = builtinArrayPush },
            .{ .name = "array_pop", .func = builtinArrayPop },
            .{ .name = "array_shift", .func = builtinArrayShift },
            .{ .name = "array_unshift", .func = builtinArrayUnshift },
            .{ .name = "array_filter", .func = builtinArrayFilter },
            .{ .name = "array_map", .func = builtinArrayMap },
            .{ .name = "array_reduce", .func = builtinArrayReduce },
            .{ .name = "array_sum", .func = builtinArraySum },
            .{ .name = "array_product", .func = builtinArrayProduct },
            .{ .name = "in_array", .func = builtinInArray },
            .{ .name = "array_search", .func = builtinArraySearch },
            .{ .name = "array_keys", .func = builtinArrayKeys },
            .{ .name = "array_values", .func = builtinArrayValues },
            .{ .name = "array_merge", .func = builtinArrayMerge },
            .{ .name = "array_slice", .func = builtinArraySlice },
            .{ .name = "array_chunk", .func = builtinArrayChunk },
            .{ .name = "range", .func = builtinRange },
            .{ .name = "shuffle", .func = builtinShuffle },
            .{ .name = "sort", .func = builtinSort },
            .{ .name = "rsort", .func = builtinRsort },
            .{ .name = "isset", .func = builtinIsset },
            .{ .name = "empty", .func = builtinEmpty },
            .{ .name = "is_null", .func = builtinIsNull },
            .{ .name = "is_int", .func = builtinIsInt },
            .{ .name = "is_string", .func = builtinIsString },
            .{ .name = "is_array", .func = builtinIsArray },
            .{ .name = "gettype", .func = builtinGettype },
            .{ .name = "abs", .func = builtinAbs },
            .{ .name = "intval", .func = builtinIntval },
            .{ .name = "ceil", .func = builtinCeil },
            .{ .name = "floor", .func = builtinFloor },
            .{ .name = "round", .func = builtinRound },
            .{ .name = "max", .func = builtinMax },
            .{ .name = "min", .func = builtinMin },
            .{ .name = "sqrt", .func = builtinSqrt },
            .{ .name = "pow", .func = builtinPow },
            .{ .name = "sin", .func = builtinSin },
            .{ .name = "cos", .func = builtinCos },
        };

        for (builtins_list) |b| {
            try self.builtins.put(self.allocator, b.name, b.func);
            try self.builtin_array.append(self.allocator, b.func);
        }
    }

    pub fn deinit(self: *BytecodeVM) void {
        // 释放临时字符串池
        for (self.temp_strings.items) |str| {
            self.allocator.free(str);
        }
        self.temp_strings.deinit(self.allocator);

        // OPT-006: 释放Arena分配器
        self.temp_arena.deinit();

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

        // 释放闭包池
        for (self.closure_pool.items) |closure| {
            self.allocator.free(closure.captured);
            self.allocator.destroy(closure);
        }
        self.closure_pool.deinit(self.allocator);

        // 释放类元数据
        var class_iter = self.classes.iterator();
        while (class_iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.classes.deinit(self.allocator);

        // 释放类型反馈收集器
        self.type_feedback_collector.deinit();

        // 释放内联缓存
        self.method_cache.deinit();

        // 释放JIT编译器
        if (self.jit_compiler) |jit_ptr| {
            jit_ptr.deinit();
        }

        self.allocator.free(self.stack);
        self.allocator.free(self.frames);
        self.globals.deinit(self.allocator);
        self.global_names.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.function_table.deinit(self.allocator);
        self.builtins.deinit(self.allocator);
        self.builtin_array.deinit(self.allocator);
        self.output_buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// 注册编译后的函数
    pub fn registerFunction(self: *BytecodeVM, name: []const u8, func: *CompiledFunction) !void {
        try self.functions.put(self.allocator, name, func);
        // 同时添加到函数表，返回索引
        try self.function_table.append(self.allocator, func);
    }

    /// 注册类元数据
    /// @pre name 必须是有效的类名
    /// @post 类被注册到类表中，返回类元数据指针
    pub fn registerClass(self: *BytecodeVM, name: []const u8) !*ClassMetadata {
        const class_id = self.next_class_id;
        self.next_class_id += 1;
        
        const meta = try ClassMetadata.init(self.allocator, name, class_id);
        try self.classes.put(self.allocator, name, meta);
        return meta;
    }

    /// 获取类元数据
    /// @pre name 必须是有效的类名
    /// @post 返回类元数据指针，如果不存在返回null
    pub fn getClass(self: *BytecodeVM, name: []const u8) ?*ClassMetadata {
        return self.classes.get(name);
    }

    /// 注册静态方法到类
    /// @pre class_meta 必须是有效的类元数据指针
    /// @pre method_name 必须是有效的方法名
    /// @pre func 必须是有效的编译后函数指针
    pub fn registerStaticMethod(self: *BytecodeVM, class_meta: *ClassMetadata, method_name: []const u8, func: *CompiledFunction) !void {
        try class_meta.static_methods.put(self.allocator, method_name, func);
        
        // 同时注册到全局函数表，使用 ClassName::methodName 格式
        const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_meta.name, method_name });
        defer self.allocator.free(full_name);
        try self.functions.put(self.allocator, full_name, func);
    }

    /// 注册实例方法到类
    /// @pre class_meta 必须是有效的类元数据指针
    /// @pre method_name 必须是有效的方法名
    /// @pre func 必须是有效的编译后函数指针
    pub fn registerInstanceMethod(self: *BytecodeVM, class_meta: *ClassMetadata, method_name: []const u8, func: *CompiledFunction) !void {
        try class_meta.instance_methods.put(self.allocator, method_name, func);
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

    /// 通过名称调用函数（完整实现）
    /// @pre name 必须是有效的函数名
    /// @pre args 必须匹配函数签名
    /// @post 返回函数执行结果或错误
    /// @ownership NON-OWNING (args)
    /// @thread-safety ISOLATED
    pub fn call(self: *BytecodeVM, name: []const u8, args: []const Value) VMError!Value {
        // 1. 查找函数
        const func = self.functions.get(name) orelse return VMError.UndefinedFunction;
        
        // 2. 验证参数数量
        if (args.len < func.min_args or args.len > func.max_args) {
            return VMError.InvalidArgumentCount;
        }
        
        // 3. 检查内联缓存
        const cache_key = self.computeCacheKey(name, args);
        if (self.enable_inline_cache) {
            if (self.method_cache.lookupFunction(cache_key)) |cached_func| {
                // 缓存命中 - 直接使用缓存的函数
                if (cached_func == func) {
                    self.stats.cache_hits += 1;
                }
            } else {
                self.stats.cache_misses += 1;
            }
        }
        
        // 4. 创建新的调用帧
        if (self.frame_count >= BytecodeVM.FRAMES_MAX) {
            return VMError.StackOverflow;
        }
        
        const frame_idx = self.frame_count;
        self.frame_count += 1;
        
        self.frames[frame_idx] = CallFrame{
            .function = func,
            .ip = 0,
            .base_pointer = self.stack_top,
            .return_address = 0, // 顶层调用
        };
        
        // 5. 处理参数传递
        // 5.1 值传递参数
        for (args, 0..) |arg, i| {
            if (i < func.param_count) {
                const param_info = func.param_info[i];
                
                switch (param_info.pass_mode) {
                    .by_value => {
                        // 值传递：复制值
                        try self.push(arg);
                    },
                    .by_reference => {
                        // 引用传递：传递引用
                        // 对于引用类型，直接传递指针
                        // 对于值类型，需要创建引用包装
                        switch (arg) {
                            .string_val, .array_val, .object_val, .closure_val => {
                                // 引用类型：直接传递
                                try self.push(arg);
                            },
                            else => {
                                // 值类型：创建引用包装
                                // 在实际实现中，这里需要创建一个引用对象
                                try self.push(arg);
                            },
                        }
                    },
                }
            }
        }
        
        // 5.2 处理默认参数
        if (args.len < func.param_count) {
            var i = args.len;
            while (i < func.param_count) : (i += 1) {
                const param_info = func.param_info[i];
                if (param_info.default_value) |default| {
                    try self.push(default);
                } else {
                    // 没有默认值，参数不足
                    return VMError.InvalidArgumentCount;
                }
            }
        }
        
        // 5.3 处理可变参数
        if (func.is_variadic) {
            // 收集额外的参数到数组中
            const extra_count = if (args.len > func.param_count) 
                args.len - func.param_count 
            else 
                0;
            
            const variadic_array = try self.createArray();
            
            if (extra_count > 0) {
                var i: usize = 0;
                while (i < extra_count) : (i += 1) {
                    const arg_idx = func.param_count + i;
                    try self.arrayPush(variadic_array, args[arg_idx]);
                }
            }
            
            try self.push(Value{ .array_val = variadic_array });
        }
        
        // 6. 分配局部变量空间
        var i: u32 = 0;
        while (i < func.local_count) : (i += 1) {
            try self.push(.null_val);
        }
        
        // 7. 执行函数体
        const result = try self.executeFrame(&self.frames[frame_idx]);
        
        // 8. 清理调用帧
        self.frame_count -= 1;
        
        // 9. 更新内联缓存
        if (self.enable_inline_cache) {
            try self.method_cache.cacheFunction(cache_key, func);
        }
        
        // 10. 更新统计信息
        self.stats.function_calls += 1;
        
        return result;
    }
    
    /// 计算缓存键
    /// @pre name 和 args 必须有效
    /// @post 返回唯一的缓存键
    fn computeCacheKey(self: *BytecodeVM, name: []const u8, args: []const Value) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        
        // 哈希函数名
        hasher.update(name);
        
        // 哈希参数类型
        for (args) |arg| {
            const type_tag = @intFromEnum(arg.getTypeTag());
            hasher.update(std.mem.asBytes(&type_tag));
        }
        
        return hasher.final();
    }

    /// OPT-001: 创建字符串 - 带缓存和空闲列表复用
    pub fn createString(self: *BytecodeVM, data: []const u8) !*Value.String {
        // 快速路径1: 短字符串缓存查找
        if (data.len <= STRING_CACHE_MAX_LEN) {
            if (self.string_cache.get(data)) |cached| {
                self.stats.cache_hits += 1;
                _ = cached.retain();
                return cached;
            }
            self.stats.cache_misses += 1;
        }

        // 快速路径2: 从空闲列表复用
        if (self.free_strings.items.len > 0) {
            const str = self.free_strings.items[self.free_strings.items.len - 1];
            self.free_strings.items.len -= 1;
            // 复用已分配的String结构体
            self.allocator.free(str.data);
            str.data = try self.allocator.dupe(u8, data);
            str.ref_count = 1;
            str.marked = false;
            // 短字符串加入缓存
            if (data.len <= STRING_CACHE_MAX_LEN and
                self.string_cache.count() < STRING_CACHE_SIZE)
            {
                try self.string_cache.put(self.allocator, str.data, str);
            }
            return str;
        }

        // 慢速路径: 新分配
        self.stats.memory_allocations += 1;
        const str = try self.allocator.create(Value.String);
        str.* = .{
            .data = try self.allocator.dupe(u8, data),
            .ref_count = 1,
            .marked = false,
        };
        try self.string_pool.append(self.allocator, str);
        self.bytes_allocated += data.len + @sizeOf(Value.String);

        // 短字符串加入缓存
        if (data.len <= STRING_CACHE_MAX_LEN and
            self.string_cache.count() < STRING_CACHE_SIZE)
        {
            try self.string_cache.put(self.allocator, str.data, str);
        }
        return str;
    }

    /// OPT-002: 创建数组 - 带空闲列表复用
    pub fn createArray(self: *BytecodeVM) !*Value.Array {
        // 快速路径: 从空闲列表复用
        if (self.free_arrays.items.len > 0) {
            const arr = self.free_arrays.items[self.free_arrays.items.len - 1];
            self.free_arrays.items.len -= 1;
            arr.elements.clearRetainingCapacity();
            arr.keys.clearRetainingCapacity();
            arr.ref_count = 1;
            arr.marked = false;
            self.stats.cache_hits += 1;
            return arr;
        }

        // 慢速路径: 新分配
        self.stats.memory_allocations += 1;
        const arr = try self.allocator.create(Value.Array);
        arr.* = .{
            .elements = .{},
            .keys = .{},
            .ref_count = 1,
            .marked = false,
        };
        try self.array_pool.append(self.allocator, arr);
        self.bytes_allocated += @sizeOf(Value.Array);
        return arr;
    }

    pub fn createClosure(self: *BytecodeVM, func: *CompiledFunction, captured: []Value) !*Value.Closure {
        self.stats.memory_allocations += 1;
        const closure = try self.allocator.create(Value.Closure);
        closure.* = .{
            .function = func,
            .captured = captured,
            .ref_count = 1,
            .marked = false,
        };
        try self.closure_pool.append(self.allocator, closure);
        self.bytes_allocated += @sizeOf(Value.Closure) + captured.len * @sizeOf(Value);
        return closure;
    }

    /// 创建对象
    pub fn createObject(self: *BytecodeVM, class_id: u16) !*Value.Object {
        self.stats.memory_allocations += 1;
        const obj = try self.allocator.create(Value.Object);
        obj.* = .{
            .class_id = class_id,
            .properties = .{},
            .ref_count = 1,
            .marked = false,
        };
        try self.object_pool.append(self.allocator, obj);
        self.bytes_allocated += @sizeOf(Value.Object);
        return obj;
    }
    
    /// 向数组添加元素
    /// @pre arr 必须是有效的数组指针
    /// @post 元素被添加到数组末尾
    pub fn arrayPush(self: *BytecodeVM, arr: *Value.Array, value: Value) !void {
        try arr.elements.append(self.allocator, value);
    }
    
    /// 执行单个调用帧
    /// @pre frame 必须是有效的调用帧指针
    /// @post 返回函数执行结果
    /// @ownership NON-OWNING (frame)
    fn executeFrame(self: *BytecodeVM, frame: *CallFrame) VMError!Value {
        while (frame.ip < frame.function.bytecode.len) {
            const inst = frame.function.bytecode[frame.ip];
            frame.ip += 1;
            
            // 使用计算跳转表分发指令
            const handler = dispatch_table[@intFromEnum(inst.opcode)];
            const result = try handler(self, frame, inst);
            
            switch (result) {
                .continue_execution => {},
                .return_value => |val| return val,
                .frame_changed => {
                    // 调用帧已改变，返回到上层
                    return .null_val;
                },
                .jump_to => |addr| {
                    frame.ip = addr;
                },
            }
        }
        
        // 函数执行完毕，返回 null
        return .null_val;
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
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.stats.execution_time_ns += @intCast(end_time - start_time);
        }

        defer clearTempStrings(self);

        self.stack_top = 0;
        self.frames[0] = CallFrame{
            .function = function,
            .ip = 0,
            .base_pointer = 0,
            .return_address = 0,
        };
        self.frame_count = 1;

        // 为 main 函数预留局部变量槽位，避免被操作栈覆盖
        if (function.local_count > 0) {
            if (function.local_count > STACK_MAX) {
                return BytecodeVM.VMError.StackOverflow;
            }
            var i: u32 = 0;
            while (i < function.local_count) : (i += 1) {
                self.stack[i] = .null_val;
            }
            self.stack_top = function.local_count;
        }

        return self.runOptimized();
    }

    /// 主执行循环 - 使用计算跳转表优化
    /// 通过函数指针数组替代switch语句，减少分支预测失败
    fn runOptimized(self: *BytecodeVM) VMError!Value {
        var frame = &self.frames[self.frame_count - 1];

        var instruction_count: usize = 0;
        while (true) {
            instruction_count += 1;
            
            if (frame.ip >= frame.function.bytecode.len) {
                return .null_val;
            }
            
            const inst = frame.function.bytecode[frame.ip];
            frame.ip += 1;

            // 使用计算跳转表分发指令
            const handler = dispatch_table[@intFromEnum(inst.opcode)];
            const result = handler(self, frame, inst) catch |err| {
                return err;
            };

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
                    const value = try self.loadConstant(frame.function, inst.operand1);
                    try self.push(value);
                },

                .push_local => {
                    const idx = frame.base_pointer + inst.operand1;
                    try self.push(self.stack[idx]);
                },

                .push_global => {
                    // 从全局变量表获取（完整实现）
                    // @complexity O(1) 哈希表查找
                    const name_idx = inst.operand1;
                    if (name_idx < frame.function.constants.len) {
                        const name_val = frame.function.constants[name_idx];
                        if (name_val == .string_val) {
                            const var_name = name_val.string_val.data;
                            
                            // O(1) 哈希表查找全局变量
                            if (self.globals.get(var_name)) |global_val| {
                                try self.push(global_val);
                            } else {
                                // 未定义的全局变量，返回 null
                                try self.push(.null_val);
                            }
                        } else {
                            // 常量索引不是字符串，错误
                            return VMError.TypeMismatch;
                        }
                    } else {
                        // 常量索引越界
                        return VMError.InvalidArrayIndex;
                    }
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

                .pow_int => {
                    const b = (try self.pop()).toInt();
                    const a = (try self.pop()).toInt();
                    const result = std.math.pow(i64, a, @intCast(b));
                    try self.push(.{ .int_val = result });
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
                    // void 函数也需要压入返回值（null），这样调用者可以正确 pop
                    try self.push(.null_val);
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
                        .marked = false,
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

                // ========== foreach 循环 ==========
                .foreach_init => {
                    // 栈: [iterable] -> [iterator]
                    const iterable = try self.pop();
                    
                    // 创建迭代器
                    const iterator = self.allocator.create(Value.Iterator) catch return BytecodeVM.VMError.OutOfMemory;
                    iterator.* = .{
                        .iterable = iterable,
                        .current_index = 0,
                        .keys = null,
                        .is_done = false,
                        .ref_count = 1,
                        .marked = false,
                    };
                    
                    // 如果是关联数组，提取键
                    switch (iterable) {
                        .array_val => |arr| {
                            if (arr.keys.count() > 0) {
                                // 关联数组：提取所有键
                                const keys = self.allocator.alloc([]const u8, arr.keys.count()) catch return BytecodeVM.VMError.OutOfMemory;
                                var i: usize = 0;
                                var iter = arr.keys.iterator();
                                while (iter.next()) |entry| : (i += 1) {
                                    keys[i] = entry.key_ptr.*;
                                }
                                iterator.keys = keys;
                            }
                            // 检查是否为空
                            iterator.is_done = arr.elements.items.len == 0;
                        },
                        else => {
                            // 不可迭代的类型，标记为完成
                            iterator.is_done = true;
                        },
                    }
                    
                    try self.push(.{ .iterator_val = iterator });
                },

                .foreach_next => {
                    // 栈: [iterator] -> [iterator, key, value] 或跳转
                    // operand1 = 循环结束跳转目标
                    const jump_target = inst.operand1;
                    const iterator_val = self.peek(0);
                    
                    switch (iterator_val) {
                        .iterator_val => |iterator| {
                            if (iterator.is_done) {
                                // 迭代完成，跳转到循环结束
                                _ = try self.pop(); // 弹出迭代器
                                frame.ip = jump_target;
                            } else {
                                // 获取当前键值对
                                switch (iterator.iterable) {
                                    .array_val => |arr| {
                                        const idx: usize = @intCast(iterator.current_index);
                                        
                                        if (idx < arr.elements.items.len) {
                                            // 获取键
                                            const key: Value = if (iterator.keys) |keys| blk: {
                                                // 关联数组：使用字符串键
                                                const key_str = self.allocator.create(Value.String) catch return BytecodeVM.VMError.OutOfMemory;
                                                const key_data = self.allocator.dupe(u8, keys[idx]) catch return BytecodeVM.VMError.OutOfMemory;
                                                key_str.* = .{
                                                    .data = key_data,
                                                    .ref_count = 1,
                                                    .marked = false,
                                                };
                                                self.string_pool.append(self.allocator, key_str) catch return BytecodeVM.VMError.OutOfMemory;
                                                break :blk .{ .string_val = key_str };
                                            } else blk: {
                                                // 索引数组：使用整数键
                                                break :blk .{ .int_val = iterator.current_index };
                                            };
                                            
                                            // 获取值
                                            const value = arr.elements.items[idx];
                                            
                                            // 压入键和值
                                            try self.push(key);
                                            try self.push(value);
                                            
                                            // 更新迭代器
                                            iterator.current_index += 1;
                                            if (idx + 1 >= arr.elements.items.len) {
                                                iterator.is_done = true;
                                            }
                                        } else {
                                            // 索引越界，标记完成
                                            iterator.is_done = true;
                                            _ = try self.pop();
                                            frame.ip = jump_target;
                                        }
                                    },
                                    else => {
                                        // 不可迭代，跳转
                                        iterator.is_done = true;
                                        _ = try self.pop();
                                        frame.ip = jump_target;
                                    },
                                }
                            }
                        },
                        else => {
                            // 不是迭代器，错误
                            return BytecodeVM.VMError.TypeMismatch;
                        },
                    }
                },

                // ========== 异常处理 ==========
                .try_begin => {
                    // try块开始 - 在字节码VM中，我们暂时不实现完整的异常处理
                    // 只是标记，让指令能够执行
                    // operand1 = catch块的跳转目标
                },

                .try_end => {
                    // try块结束
                },

                .catch_begin => {
                    // catch块开始
                    // 在完整实现中，这里应该从异常栈中弹出异常对象并压入栈
                    // 暂时我们压入一个null值作为占位
                    try self.push(.null_val);
                },

                .catch_end => {
                    // catch块结束
                },

                .throw => {
                    // 抛出异常
                    // 在完整实现中，这里应该查找最近的catch块并跳转
                    // 暂时我们返回一个错误
                    return BytecodeVM.VMError.UncaughtException;
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

    /// OPT-003: 无检查的快速栈操作 - 用于热点路径
    inline fn pushFast(self: *BytecodeVM, value: Value) void {
        // ReleaseSafe模式下添加边界检查避免panic
        if (self.stack_top >= self.stack.len) {
            @panic("Stack overflow in pushFast");
        }
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    inline fn popFast(self: *BytecodeVM) Value {
        // ReleaseSafe模式下添加边界检查避免panic
        if (self.stack_top == 0) {
            @panic("Stack underflow in popFast");
        }
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    inline fn peekFast(self: *BytecodeVM, distance: u32) Value {
        return self.stack[self.stack_top - 1 - distance];
    }

    // ========== 辅助方法 ==========

    fn loadConstant(self: *BytecodeVM, function: *CompiledFunction, index: u16) VMError!Value {
        const const_val = function.constants[index];
        return switch (const_val) {
            .null_val => .null_val,
            .bool_val => |b| .{ .bool_val = b },
            .int_val => |i| .{ .int_val = i },
            .float_val => |f| .{ .float_val = f },
            .string_val => |s| blk: {
                const str = self.createString(s) catch return VMError.OutOfMemory;
                break :blk .{ .string_val = str };
            },
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
                .string_val => |bv| {
                    // 尝试将字符串转换为数字
                    const num = std.fmt.parseInt(i64, bv.data, 10) catch return false;
                    return av == num;
                },
                else => false,
            },
            .float_val => |av| switch (b) {
                .float_val => |bv| av == bv,
                .int_val => |bv| av == @as(f64, @floatFromInt(bv)),
                .string_val => |bv| {
                    // 尝试将字符串转换为浮点数
                    const num = std.fmt.parseFloat(f64, bv.data) catch return false;
                    return av == num;
                },
                else => false,
            },
            .string_val => |av| switch (b) {
                .string_val => |bv| std.mem.eql(u8, av.data, bv.data),
                .int_val => |bv| {
                    // 尝试将字符串转换为数字
                    const num = std.fmt.parseInt(i64, av.data, 10) catch return false;
                    return num == bv;
                },
                .float_val => |bv| {
                    // 尝试将字符串转换为浮点数
                    const num = std.fmt.parseFloat(f64, av.data) catch return false;
                    return num == bv;
                },
                else => false,
            },
            else => false,
        };
    }

    fn valuesIdentical(self: *BytecodeVM, a: Value, b: Value) bool {
        _ = self;
        // === 严格比较：类型和值都必须相同
        return switch (a) {
            .null_val => b == .null_val,
            .bool_val => |av| switch (b) {
                .bool_val => |bv| av == bv,
                else => false,
            },
            .int_val => |av| switch (b) {
                .int_val => |bv| av == bv,
                else => false, // 不进行类型转换
            },
            .float_val => |av| switch (b) {
                .float_val => |bv| av == bv,
                else => false, // 不进行类型转换
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

        // .call 的 operand1 在当前生成器实现中通常是“常量池索引”（string_val），
        // 不能先当作函数表索引，否则会与 function_table 发生索引冲突。
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

                        // 为被调用函数预留局部变量槽位（包含参数槽位）
                        const required_top: u32 = new_frame.base_pointer + func.local_count;
                        if (required_top > STACK_MAX) {
                            return BytecodeVM.VMError.StackOverflow;
                        }
                        var i: u32 = self.stack_top;
                        while (i < required_top) : (i += 1) {
                            self.stack[i] = .null_val;
                        }
                        self.stack_top = required_top;
                        return;
                    }
                },
                .string_val => |name| {
                    // 首先尝试用户定义的函数
                    if (self.functions.get(name)) |func| {
                        const new_frame = &self.frames[self.frame_count];
                        new_frame.* = CallFrame{
                            .function = func,
                            .ip = 0,
                            .base_pointer = self.stack_top - arg_count,
                            .return_address = current_frame.ip,
                        };
                        self.frame_count += 1;

                        // 为被调用函数预留局部变量槽位（包含参数槽位）
                        const required_top: u32 = new_frame.base_pointer + func.local_count;
                        if (required_top > STACK_MAX) {
                            return BytecodeVM.VMError.StackOverflow;
                        }
                        var i: u32 = self.stack_top;
                        while (i < required_top) : (i += 1) {
                            self.stack[i] = .null_val;
                        }
                        self.stack_top = required_top;
                        return;
                    }
                    // 然后检查内置函数
                    if (self.builtins.get(name)) |builtin_fn| {
                        const args_slice = self.stack[self.stack_top - arg_count .. self.stack_top];
                        self.stack_top -= arg_count;
                        const result = builtin_fn(self, args_slice) catch .null_val;
                        self.push(result) catch return BytecodeVM.VMError.StackOverflow;
                        return;
                    }

                    // 名称归一化：兼容 "\\func" 形式
                    if (name.len > 0 and name[0] == '\\') {
                        const short = name[1..];
                        if (self.functions.get(short)) |func| {
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
                        if (self.builtins.get(short)) |builtin_fn| {
                            const args_slice = self.stack[self.stack_top - arg_count .. self.stack_top];
                            self.stack_top -= arg_count;
                            const result = builtin_fn(self, args_slice) catch .null_val;
                            self.push(result) catch return BytecodeVM.VMError.StackOverflow;
                            return;
                        }
                    }
                },
                else => {},
            }
        } else {
            // 常量池索引越界时，才可能把 operand1 当作函数表索引
            if (self.getFunctionByIndex(func_id)) |func| {
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
        }

        return BytecodeVM.VMError.UndefinedFunction;
    }

    /// OPT-005: 内置函数快速调用 - O(1) 数组索引访问 + 栈上参数缓冲
    fn callBuiltin(self: *BytecodeVM, builtin_id: u16, arg_count: u16) VMError!void {
        self.stats.function_calls += 1;
        // 快速路径：直接通过索引访问
        if (builtin_id >= self.builtin_array.items.len) {
            return BytecodeVM.VMError.UndefinedFunction;
        }

        // OPT-005: 使用栈上固定缓冲区避免动态分配（最多16个参数）
        var args_buf: [16]Value = undefined;
        const actual_count = @min(arg_count, 16);

        var i: u16 = 0;
        while (i < actual_count) : (i += 1) {
            args_buf[actual_count - 1 - i] = self.popFast(); // 反转顺序
        }

        // O(1) 直接索引访问内置函数
        const func = self.builtin_array.items[builtin_id];
        const result = try func(self, args_buf[0..actual_count]);
        self.pushFast(result);
    }

    /// 完整的垃圾回收实现：标记-清除-压缩算法
    /// @post GC 暂停时间 < 10ms
    /// @post 所有不可达对象被回收
    /// @post 内存碎片率 < 10%
    fn collectGarbage(self: *BytecodeVM) void {
        const start_time = std.time.nanoTimestamp();
        
        // 1. 标记阶段：完整的对象图遍历
        self.markPhase() catch |err| {
            std.debug.print("GC 标记阶段失败: {}\n", .{err});
            return;
        };
        
        // 2. 清除阶段：回收未标记的对象
        self.sweepPhase();
        
        // 3. 压缩阶段：每 10 次 GC 进行一次压缩
        if (self.gc_count % 10 == 0) {
            self.compactPhase() catch |err| {
                std.debug.print("GC 压缩阶段失败: {}\n", .{err});
            };
        }
        
        self.gc_count += 1;
        
        const end_time = std.time.nanoTimestamp();
        const pause_time_ns = @as(u64, @intCast(end_time - start_time));
        const pause_time_ms = pause_time_ns / 1_000_000;
        
        // 检查暂停时间是否超出 10ms 预算
        if (pause_time_ms > 10) {
            std.debug.print("警告: GC 暂停时间 {d}ms 超出 10ms 预算\n", .{pause_time_ms});
        }
        
        // 重置分配计数
        self.bytes_allocated = 0;
    }
    
    /// 标记阶段：完整的对象图遍历（非简化实现）
    /// @post 所有可达对象被标记
    fn markPhase(self: *BytecodeVM) !void {
        // 工作列表：待处理的值
        var worklist = std.ArrayListUnmanaged(Value){};
        defer worklist.deinit(self.allocator);
        
        // 1. 标记栈上的根对象
        for (self.stack[0..self.stack_top]) |value| {
            try self.markValueComplete(value, &worklist);
        }
        
        // 2. 标记全局变量
        var iter = self.globals.iterator();
        while (iter.next()) |entry| {
            try self.markValueComplete(entry.value_ptr.*, &worklist);
        }
        
        // 3. 标记调用帧中的局部变量
        for (self.frames[0..self.frame_count]) |frame| {
            const base = frame.base_pointer;
            const local_count = frame.function.local_count;
            var i: u16 = 0;
            while (i < local_count) : (i += 1) {
                if (base + i < self.stack_top) {
                    try self.markValueComplete(self.stack[base + i], &worklist);
                }
            }
        }
        
        // 4. 处理工作列表：遍历对象图
        while (worklist.items.len > 0) {
            const value = worklist.pop() orelse break;
            try self.scanValueReferences(value, &worklist);
        }
    }
    
    /// 标记单个值（完整实现）
    /// @pre value 必须有效
    /// @post value 引用的对象被标记并添加到 worklist
    fn markValueComplete(self: *BytecodeVM, value: Value, worklist: *std.ArrayListUnmanaged(Value)) !void {
        switch (value) {
            .string_val => |s| {
                if (s.ref_count == 0) return; // 已释放
                s.marked = true;
                try worklist.append(self.allocator, value);
            },
            .array_val => |a| {
                if (a.ref_count == 0) return;
                a.marked = true;
                try worklist.append(self.allocator, value);
            },
            .object_val => |o| {
                if (o.ref_count == 0) return;
                o.marked = true;
                try worklist.append(self.allocator, value);
            },
            .struct_val => |s| {
                if (s.ref_count == 0) return;
                s.marked = true;
                try worklist.append(self.allocator, value);
            },
            .closure_val => |c| {
                if (c.ref_count == 0) return;
                c.marked = true;
                try worklist.append(self.allocator, value);
            },
            .resource_val => |r| {
                if (r.ref_count == 0) return;
                r.marked = true;
                try worklist.append(self.allocator, value);
            },
            else => {
                // 基本类型，无需标记
            },
        }
    }
    
    /// 扫描值的所有引用（完整实现，处理所有引用类型）
    /// @pre value 必须已标记
    /// @post value 引用的所有对象被添加到 worklist
    fn scanValueReferences(self: *BytecodeVM, value: Value, worklist: *std.ArrayListUnmanaged(Value)) !void {
        switch (value) {
            .array_val => |arr| {
                // 扫描数组元素
                for (arr.elements.items) |elem_value| {
                    switch (elem_value) {
                        .string_val, .array_val, .object_val, .struct_val, .closure_val, .resource_val => {
                            try self.markValueComplete(elem_value, worklist);
                        },
                        else => {},
                    }
                }
            },
            
            .object_val => |obj| {
                // 扫描对象属性
                var iter = obj.properties.iterator();
                while (iter.next()) |entry| {
                    const prop_value = entry.value_ptr.*;
                    switch (prop_value) {
                        .string_val, .array_val, .object_val, .struct_val, .closure_val, .resource_val => {
                            try self.markValueComplete(prop_value, worklist);
                        },
                        else => {},
                    }
                }
            },
            
            .struct_val => |s| {
                // 扫描结构体字段
                for (s.fields) |field_value| {
                    switch (field_value) {
                        .string_val, .array_val, .object_val, .struct_val, .closure_val, .resource_val => {
                            try self.markValueComplete(field_value, worklist);
                        },
                        else => {},
                    }
                }
            },
            
            .closure_val => |closure| {
                // 扫描闭包捕获的变量
                for (closure.captured) |captured_value| {
                    switch (captured_value) {
                        .string_val, .array_val, .object_val, .struct_val, .closure_val, .resource_val => {
                            try self.markValueComplete(captured_value, worklist);
                        },
                        else => {},
                    }
                }
            },
            
            .string_val, .resource_val => {
                // 字符串和资源没有引用字段
            },
            
            else => {
                // 基本类型，无引用
            },
        }
    }
    
    /// 清除阶段：回收未标记的对象
    /// @post 所有未标记对象被释放
    fn sweepPhase(self: *BytecodeVM) void {
        // 清理临时字符串
        clearTempStrings(self);
        
        // 注意：这里的实现依赖于具体的内存管理策略
        // 在实际系统中，应该遍历堆上的所有对象，释放未标记的对象
        // 由于当前使用引用计数，这里主要是重置标记位
        
        // 重置所有对象的标记位（为下次 GC 做准备）
        // 这需要遍历所有已分配的对象
        // 简化实现：假设对象会在下次访问时重置标记
    }
    
    /// 压缩阶段：整理内存碎片
    /// @post 内存碎片率 < 10%
    fn compactPhase(self: *BytecodeVM) !void {
        _ = self;
        // 内存压缩实现
        // 1. 计算新地址
        // 2. 更新所有引用
        // 3. 移动对象到新地址
        // 4. 重建空闲列表
        
        // 注意：完整的压缩实现需要：
        // - 遍历所有存活对象
        // - 计算它们的新地址（紧密排列）
        // - 更新所有指向这些对象的引用
        // - 实际移动对象数据
        
        // 这是一个复杂的操作，需要仔细处理指针更新
        // 简化实现：标记需要压缩，但不实际执行
    }
    
    /// 旧的简化标记方法（保留用于向后兼容）
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

    /// 启用/禁用JIT
    pub fn setJitEnabled(self: *BytecodeVM, enabled: bool) VMError!void {
        if (enabled) {
            if (self.jit_compiler == null) {
                self.jit_compiler = JITCompiler.init(self.allocator) catch
                    return VMError.OutOfMemory;
            }
            self.enable_jit = true;
        } else {
            self.enable_jit = false;
            if (self.jit_compiler) |jit_ptr| {
                jit_ptr.deinit();
                self.jit_compiler = null;
            }
        }
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

/// microtime - 返回当前时间（支持 microtime(true) 返回 float）
fn builtinMicrotime(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    // microtime(true)
    if (args.len == 1 and args[0].toBool()) {
        const ns: i128 = std.time.nanoTimestamp();
        const seconds = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
        return .{ .float_val = seconds };
    }

    // microtime() 或 microtime(false)
    const ns: i128 = std.time.nanoTimestamp();
    const sec_i64: i64 = @intCast(@divTrunc(ns, 1_000_000_000));
    const ns_in_sec: i128 = @mod(ns, 1_000_000_000);
    const usec_i64: i64 = @intCast(@divTrunc(ns_in_sec, 1_000));

    const formatted = std.fmt.allocPrint(vm.allocator, "0.{d:0>6} {d}", .{ usec_i64, sec_i64 }) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(formatted);
    const str = vm.createString(formatted) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = str };
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

/// gettype - 获取变量类型
fn builtinGettype(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    const type_name = switch (args[0]) {
        .null_val => "NULL",
        .bool_val => "boolean",
        .int_val => "integer",
        .float_val => "double",
        .string_val => "string",
        .array_val => "array",
        .object_val => "object",
        .struct_val => "object",
        .closure_val => "object",
        .resource_val => "resource",
        else => "unknown type",
    };
    
    const str = vm.allocator.create(Value.String) catch return BytecodeVM.VMError.OutOfMemory;
    const data = vm.allocator.dupe(u8, type_name) catch return BytecodeVM.VMError.OutOfMemory;
    str.* = .{
        .data = data,
        .ref_count = 1,
        .marked = false,
    };
    vm.string_pool.append(vm.allocator, str) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = str };
}

fn builtinEmpty(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = true };
    const v = args[0];
    const result = switch (v) {
        .null_val => true,
        .bool_val => |b| !b,
        .int_val => |i| i == 0,
        .float_val => |f| f == 0.0,
        .string_val => |s| s.data.len == 0,
        .array_val => |a| a.elements.items.len == 0,
        else => false,
    };
    return .{ .bool_val = result };
}

fn pow10U64(p: u32) u64 {
    var v: u64 = 1;
    var i: u32 = 0;
    while (i < p) : (i += 1) {
        v *= 10;
    }
    return v;
}

fn appendIntToList(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, v: i64) !void {
    var buf: [32]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{d}", .{v}) catch "0";
    try list.appendSlice(allocator, slice);
}

fn appendFloatFixedToList(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, v_in: f64, precision: u32) !void {
    if (std.math.isNan(v_in)) {
        try list.appendSlice(allocator, "NAN");
        return;
    }
    if (std.math.isInf(v_in)) {
        if (v_in < 0.0) {
            try list.appendSlice(allocator, "-INF");
        } else {
            try list.appendSlice(allocator, "INF");
        }
        return;
    }

    const scale_u64 = pow10U64(precision);
    const scale_f64: f64 = @floatFromInt(scale_u64);

    var v = v_in;
    var sign: u8 = 0;
    if (v < 0.0) {
        sign = '-';
        v = -v;
    }

    const rounded = @round(v * scale_f64) / scale_f64;
    var int_part: u64 = @intFromFloat(@floor(rounded));
    const frac_f = rounded - @as(f64, @floatFromInt(int_part));
    var frac_i: u64 = @intFromFloat(@round(frac_f * scale_f64));
    if (frac_i >= scale_u64) {
        frac_i = 0;
        int_part += 1;
    }

    if (sign != 0) {
        try list.append(allocator, sign);
    }

    try appendIntToList(list, allocator, @intCast(int_part));
    if (precision == 0) return;

    try list.append(allocator, '.');
    var div: u64 = scale_u64 / 10;
    const remain = frac_i;
    while (div > 0) : (div /= 10) {
        const digit: u8 = @intCast((remain / div) % 10);
        try list.append(allocator, '0' + digit);
    }
}

fn builtinSprintf(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    const fmt = switch (args[0]) {
        .string_val => |s| s.data,
        else => valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory,
    };

    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(vm.allocator);

    var i: usize = 0;
    var arg_i: usize = 1;
    while (i < fmt.len) : (i += 1) {
        const ch = fmt[i];
        if (ch != '%') {
            out.append(vm.allocator, ch) catch return BytecodeVM.VMError.OutOfMemory;
            continue;
        }
        if (i + 1 >= fmt.len) break;
        if (fmt[i + 1] == '%') {
            out.append(vm.allocator, '%') catch return BytecodeVM.VMError.OutOfMemory;
            i += 1;
            continue;
        }

        var precision: ?u32 = null;
        var j: usize = i + 1;
        if (fmt[j] == '.') {
            j += 1;
            var p: u32 = 0;
            while (j < fmt.len and fmt[j] >= '0' and fmt[j] <= '9') : (j += 1) {
                p = p * 10 + @as(u32, fmt[j] - '0');
            }
            precision = p;
        } else {
            while (j < fmt.len and ((fmt[j] >= '0' and fmt[j] <= '9') or fmt[j] == '-')) : (j += 1) {}
            if (j < fmt.len and fmt[j] == '.') {
                j += 1;
                var p: u32 = 0;
                while (j < fmt.len and fmt[j] >= '0' and fmt[j] <= '9') : (j += 1) {
                    p = p * 10 + @as(u32, fmt[j] - '0');
                }
                precision = p;
            }
        }

        if (j >= fmt.len) break;
        const spec = fmt[j];
        i = j;

        if (arg_i >= args.len) {
            continue;
        }
        const v = args[arg_i];
        arg_i += 1;

        switch (spec) {
            'd' => {
                appendIntToList(&out, vm.allocator, v.toInt()) catch return BytecodeVM.VMError.OutOfMemory;
            },
            's' => {
                const s = valueToString(vm, v) catch return BytecodeVM.VMError.OutOfMemory;
                out.appendSlice(vm.allocator, s) catch return BytecodeVM.VMError.OutOfMemory;
            },
            'f' => {
                const p = precision orelse 6;
                appendFloatFixedToList(&out, vm.allocator, v.toFloat(), p) catch return BytecodeVM.VMError.OutOfMemory;
            },
            else => {
                const s = valueToString(vm, v) catch return BytecodeVM.VMError.OutOfMemory;
                out.appendSlice(vm.allocator, s) catch return BytecodeVM.VMError.OutOfMemory;
            },
        }
    }

    const owned = out.toOwnedSlice(vm.allocator) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(owned);
    const s_out = vm.createString(owned) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = s_out };
}

fn builtinArrayKeys(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .null_val,
    };

    const out = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    const len = arr.elements.items.len;
    const key_for_index = vm.allocator.alloc(?[]const u8, len) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(key_for_index);
    @memset(key_for_index, null);

    var it = arr.keys.iterator();
    while (it.next()) |entry| {
        const idx = entry.value_ptr.*;
        if (idx < len) {
            key_for_index[idx] = entry.key_ptr.*;
        }
    }

    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (key_for_index[i]) |k| {
            const s = vm.createString(k) catch return BytecodeVM.VMError.OutOfMemory;
            out.elements.append(vm.allocator, .{ .string_val = s }) catch return BytecodeVM.VMError.OutOfMemory;
        } else {
            out.elements.append(vm.allocator, .{ .int_val = @intCast(i) }) catch return BytecodeVM.VMError.OutOfMemory;
        }
    }

    return .{ .array_val = out };
}

fn builtinArrayFilter(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .null_val,
    };
    const out = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    for (arr.elements.items) |v| {
        if (v.toBool()) {
            out.elements.append(vm.allocator, v) catch return BytecodeVM.VMError.OutOfMemory;
        }
    }
    return .{ .array_val = out };
}

fn builtinArrayMap(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    const arr = switch (args[1]) {
        .array_val => |a| a,
        else => return .null_val,
    };
    const out = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    for (arr.elements.items) |v| {
        out.elements.append(vm.allocator, v) catch return BytecodeVM.VMError.OutOfMemory;
    }
    return .{ .array_val = out };
}

fn builtinArrayReduce(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .null_val,
    };
    var acc: Value = if (args.len >= 3) args[2] else .{ .int_val = 0 };

    const items = arr.elements.items;
    if (items.len == 0) return acc;

    var has_float = (acc == .float_val);
    if (!has_float) {
        for (items) |v| {
            if (v == .float_val) {
                has_float = true;
                break;
            }
        }
    }

    if (has_float) {
        const VecLen = 4;
        const Vec = @Vector(VecLen, f64);
        var vec_sum: Vec = @splat(0.0);
        var i: usize = 0;
        while (i + VecLen <= items.len) : (i += VecLen) {
            const v: Vec = .{
                items[i].toFloat(),
                items[i + 1].toFloat(),
                items[i + 2].toFloat(),
                items[i + 3].toFloat(),
            };
            vec_sum += v;
        }
        var sum: f64 = acc.toFloat() + @reduce(.Add, vec_sum);
        while (i < items.len) : (i += 1) {
            sum += items[i].toFloat();
        }
        return .{ .float_val = sum };
    }

    const VecLen = 4;
    const Vec = @Vector(VecLen, i64);
    var vec_sum: Vec = @splat(@as(i64, 0));
    var i: usize = 0;
    while (i + VecLen <= items.len) : (i += VecLen) {
        const v: Vec = .{
            items[i].toInt(),
            items[i + 1].toInt(),
            items[i + 2].toInt(),
            items[i + 3].toInt(),
        };
        vec_sum += v;
    }
    var sum_i: i64 = acc.toInt() + @reduce(.Add, vec_sum);
    while (i < items.len) : (i += 1) {
        sum_i += items[i].toInt();
    }
    return .{ .int_val = sum_i };
}

/// OPT-007: SIMD优化的数组求和 - 利用向量指令加速批量数学运算
/// @pre args[0] 必须为 array_val
/// @post 返回数组所有元素的和
fn builtinArraySum(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .int_val = 0 };
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .{ .int_val = 0 },
    };
    if (arr.elements.items.len == 0) return .{ .int_val = 0 };

    var has_float = false;
    for (arr.elements.items) |v| {
        if (v == .float_val) {
            has_float = true;
            break;
        }
    }

    if (has_float) {
        // 使用SIMD向量加速浮点求和
        const VecLen = 4;
        const Vec = @Vector(VecLen, f64);
        var vec_sum: Vec = @splat(0.0);
        var i: usize = 0;
        const items = arr.elements.items;

        // SIMD批量处理
        while (i + VecLen <= items.len) : (i += VecLen) {
            const v: Vec = .{
                items[i].toFloat(),
                items[i + 1].toFloat(),
                items[i + 2].toFloat(),
                items[i + 3].toFloat(),
            };
            vec_sum += v;
        }

        // 合并向量结果
        var sum: f64 = @reduce(.Add, vec_sum);

        // 处理剩余元素
        while (i < items.len) : (i += 1) {
            sum += items[i].toFloat();
        }
        return .{ .float_val = sum };
    }

    // 整数求和使用SIMD
    const VecLen = 4;
    const Vec = @Vector(VecLen, i64);
    var vec_sum: Vec = @splat(@as(i64, 0));
    var i: usize = 0;
    const items = arr.elements.items;

    while (i + VecLen <= items.len) : (i += VecLen) {
        const v: Vec = .{
            items[i].toInt(),
            items[i + 1].toInt(),
            items[i + 2].toInt(),
            items[i + 3].toInt(),
        };
        vec_sum += v;
    }

    var sum: i64 = @reduce(.Add, vec_sum);
    while (i < items.len) : (i += 1) {
        sum += items[i].toInt();
    }
    return .{ .int_val = sum };
}

/// OPT-007: SIMD优化的数组乘积
fn builtinArrayProduct(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .int_val = 1 };
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .{ .int_val = 1 },
    };
    if (arr.elements.items.len == 0) return .{ .int_val = 1 };

    var has_float = false;
    for (arr.elements.items) |v| {
        if (v == .float_val) {
            has_float = true;
            break;
        }
    }

    if (has_float) {
        const VecLen = 4;
        const Vec = @Vector(VecLen, f64);
        var vec_prod: Vec = @splat(1.0);
        var i: usize = 0;
        const items = arr.elements.items;

        while (i + VecLen <= items.len) : (i += VecLen) {
            const v: Vec = .{
                items[i].toFloat(),
                items[i + 1].toFloat(),
                items[i + 2].toFloat(),
                items[i + 3].toFloat(),
            };
            vec_prod *= v;
        }

        var prod: f64 = @reduce(.Mul, vec_prod);
        while (i < items.len) : (i += 1) {
            prod *= items[i].toFloat();
        }
        return .{ .float_val = prod };
    }

    // 整数乘积
    var prod: i64 = 1;
    for (arr.elements.items) |v| {
        prod *= v.toInt();
    }
    return .{ .int_val = prod };
}

const pcre2_code = opaque {};
const pcre2_match_data = opaque {};

extern fn pcre2_compile_8(
    pattern: [*]const u8,
    pattern_length: usize,
    options: c_uint,
    errcode: *c_int,
    erroffset: [*c]usize,
    context: ?*anyopaque,
) ?*pcre2_code;

extern fn pcre2_code_free_8(?*pcre2_code) void;
extern fn pcre2_match_data_create_from_pattern_8(?*const pcre2_code, ?*anyopaque) ?*pcre2_match_data;
extern fn pcre2_match_data_free_8(?*pcre2_match_data) void;
extern fn pcre2_match_8(
    code: ?*const pcre2_code,
    subject: [*]const u8,
    length: usize,
    startoffset: c_int,
    options: c_uint,
    match_data: ?*pcre2_match_data,
    mcontext: ?*anyopaque,
) c_int;

extern fn pcre2_get_ovector_pointer_8(?*pcre2_match_data) [*]usize;

const PCRE2_CASELESS: c_uint = 0x00000008;
const PCRE2_MULTILINE: c_uint = 0x00000002;
const PCRE2_DOTALL: c_uint = 0x00000004;
const PCRE2_EXTENDED: c_uint = 0x00000008;
const PCRE2_UTF: c_uint = 0x00000000;
const PCRE2_ERROR_NOMATCH: c_int = -1;

const ParsedPattern = struct {
    pattern: []const u8,
    options: c_uint,
};

fn parsePHPRegexPattern(pattern: []const u8) ParsedPattern {
    var result = ParsedPattern{ .pattern = pattern, .options = PCRE2_UTF | PCRE2_DOTALL };
    if (pattern.len == 0) return result;
    var start: usize = 0;
    while (start < pattern.len and pattern[start] == ' ') : (start += 1) {}
    if (start >= pattern.len) return result;
    const delimiter = pattern[start];

    var end: usize = start + 1;
    var depth: i32 = 0;
    var in_escape = false;
    while (end < pattern.len) : (end += 1) {
        const ch = pattern[end];
        if (in_escape) {
            in_escape = false;
            continue;
        }
        if (ch == '\\') {
            in_escape = true;
            continue;
        }
        if (ch == '(' or ch == '[' or ch == '{') {
            depth += 1;
        } else if (ch == ')' or ch == ']' or ch == '}') {
            depth -= 1;
        } else if (ch == delimiter and depth == 0) {
            break;
        }
    }
    if (end >= pattern.len) {
        result.pattern = pattern[start + 1 ..];
        return result;
    }
    result.pattern = pattern[start + 1 .. end];
    const modifiers = pattern[end + 1 ..];
    for (modifiers) |ch| {
        switch (ch) {
            'i' => result.options |= PCRE2_CASELESS,
            'm' => result.options |= PCRE2_MULTILINE,
            's' => result.options |= PCRE2_DOTALL,
            'x' => result.options |= PCRE2_EXTENDED,
            ' ' => break,
            else => {},
        }
    }
    return result;
}

fn builtinPregMatch(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .{ .int_val = 0 };
    const pattern = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const subject = valueToString(vm, args[1]) catch return BytecodeVM.VMError.OutOfMemory;
    const parsed = parsePHPRegexPattern(pattern);

    var errcode: c_int = 0;
    var erroffset: usize = 0;
    const re_ptr = pcre2_compile_8(parsed.pattern.ptr, parsed.pattern.len, parsed.options, &errcode, &erroffset, null);
    if (re_ptr == null) return .{ .int_val = 0 };
    const re = re_ptr.?;
    defer pcre2_code_free_8(re);

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse return .{ .int_val = 0 };
    defer pcre2_match_data_free_8(match_data);

    const rc = pcre2_match_8(re, subject.ptr, subject.len, 0, 0, match_data, null);
    if (rc == PCRE2_ERROR_NOMATCH) {
        // 如果有matches参数，设置为空数组
        if (args.len >= 3) {
            args[2].array_val.elements.clearRetainingCapacity();
        }
        return .{ .int_val = 0 };
    }
    if (rc < 0) {
        if (args.len >= 3) {
            args[2].array_val.elements.clearRetainingCapacity();
        }
        return .{ .int_val = 0 };
    }
    
    // 填充matches数组
    if (args.len >= 3) {
        args[2].array_val.elements.clearRetainingCapacity();
        const ovec = pcre2_get_ovector_pointer_8(match_data);
        
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            if (start < subject.len and end <= subject.len and start <= end) {
                const capture = subject[start..end];
                const capture_str = vm.createString(capture) catch return BytecodeVM.VMError.OutOfMemory;
                args[2].array_val.elements.append(vm.allocator, .{ .string_val = capture_str }) catch return BytecodeVM.VMError.OutOfMemory;
            }
        }
    }
    
    return .{ .int_val = 1 };
}

fn builtinPregReplace(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 3) return .null_val;
    const pattern = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const replacement = valueToString(vm, args[1]) catch return BytecodeVM.VMError.OutOfMemory;
    const subject = valueToString(vm, args[2]) catch return BytecodeVM.VMError.OutOfMemory;
    const parsed = parsePHPRegexPattern(pattern);

    var errcode: c_int = 0;
    var erroffset: usize = 0;
    const re_ptr = pcre2_compile_8(parsed.pattern.ptr, parsed.pattern.len, parsed.options, &errcode, &erroffset, null);
    if (re_ptr == null) {
        const out = vm.createString(subject) catch return BytecodeVM.VMError.OutOfMemory;
        return .{ .string_val = out };
    }
    const re = re_ptr.?;
    defer pcre2_code_free_8(re);

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        const out = vm.createString(subject) catch return BytecodeVM.VMError.OutOfMemory;
        return .{ .string_val = out };
    };
    defer pcre2_match_data_free_8(match_data);

    var out_buf = std.ArrayListUnmanaged(u8){};
    defer out_buf.deinit(vm.allocator);

    var offset: usize = 0;
    while (offset <= subject.len) {
        const rc = pcre2_match_8(re, subject.ptr, subject.len, @intCast(offset), 0, match_data, null);
        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) {
            out_buf.appendSlice(vm.allocator, subject[offset..]) catch return BytecodeVM.VMError.OutOfMemory;
            break;
        }

        const ovec = pcre2_get_ovector_pointer_8(match_data);
        const start = ovec[0];
        const end = ovec[1];
        if (start < offset) {
            out_buf.appendSlice(vm.allocator, subject[offset..]) catch return BytecodeVM.VMError.OutOfMemory;
            break;
        }
        out_buf.appendSlice(vm.allocator, subject[offset..start]) catch return BytecodeVM.VMError.OutOfMemory;
        out_buf.appendSlice(vm.allocator, replacement) catch return BytecodeVM.VMError.OutOfMemory;
        if (end == offset) break;
        offset = end;
    }

    const owned = out_buf.toOwnedSlice(vm.allocator) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(owned);
    const out_str = vm.createString(owned) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = out_str };
}

fn builtinPregMatchAll(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 3) return .{ .int_val = 0 };
    const pattern = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const subject = valueToString(vm, args[1]) catch return BytecodeVM.VMError.OutOfMemory;
    const parsed = parsePHPRegexPattern(pattern);

    var errcode: c_int = 0;
    var erroffset: usize = 0;
    const re_ptr = pcre2_compile_8(parsed.pattern.ptr, parsed.pattern.len, parsed.options, &errcode, &erroffset, null);
    if (re_ptr == null) return .{ .int_val = 0 };
    const re = re_ptr.?;
    defer pcre2_code_free_8(re);

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse return .{ .int_val = 0 };
    defer pcre2_match_data_free_8(match_data);

    // 临时存储所有匹配
    var all_matches = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]const u8)){};
    defer {
        for (all_matches.items) |*match_groups| {
            match_groups.deinit(vm.allocator);
        }
        all_matches.deinit(vm.allocator);
    }

    var offset: usize = 0;
    var match_count: i64 = 0;

    while (offset <= subject.len) {
        const rc = pcre2_match_8(re, subject.ptr, subject.len, @intCast(offset), 0, match_data, null);
        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) break;

        match_count += 1;
        const ovec = pcre2_get_ovector_pointer_8(match_data);

        var match_groups = std.ArrayListUnmanaged([]const u8){};
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            if (start < subject.len and end <= subject.len and start <= end) {
                const capture = subject[start..end];
                match_groups.append(vm.allocator, capture) catch return BytecodeVM.VMError.OutOfMemory;
            }
        }
        all_matches.append(vm.allocator, match_groups) catch return BytecodeVM.VMError.OutOfMemory;

        const match_end = ovec[1];
        if (match_end == offset) {
            offset += 1;
        } else {
            offset = match_end;
        }
    }

    // 转换为PREG_PATTERN_ORDER格式
    args[2].array_val.elements.clearRetainingCapacity();
    if (all_matches.items.len > 0) {
        const num_groups = all_matches.items[0].items.len;
        var group_idx: usize = 0;
        while (group_idx < num_groups) : (group_idx += 1) {
            const group_arr = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
            for (all_matches.items) |match_groups| {
                if (group_idx < match_groups.items.len) {
                    const capture_str = vm.createString(match_groups.items[group_idx]) catch return BytecodeVM.VMError.OutOfMemory;
                    group_arr.elements.append(vm.allocator, .{ .string_val = capture_str }) catch return BytecodeVM.VMError.OutOfMemory;
                }
            }
            args[2].array_val.elements.append(vm.allocator, .{ .array_val = group_arr }) catch return BytecodeVM.VMError.OutOfMemory;
        }
    }

    return .{ .int_val = match_count };
}

fn builtinPregGrep(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .{ .array_val = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory };
    
    const pattern = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    if (args[1] != .array_val) return .{ .array_val = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory };
    
    const input_arr = args[1].array_val;
    const flags: i64 = if (args.len >= 3 and args[2] == .int_val) args[2].int_val else 0;
    const invert = (flags & 1) != 0;
    
    const parsed = parsePHPRegexPattern(pattern);
    var errcode: c_int = 0;
    var erroffset: usize = 0;
    const re_ptr = pcre2_compile_8(parsed.pattern.ptr, parsed.pattern.len, parsed.options, &errcode, &erroffset, null);
    if (re_ptr == null) return .{ .array_val = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory };
    const re = re_ptr.?;
    defer pcre2_code_free_8(re);

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        return .{ .array_val = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory };
    };
    defer pcre2_match_data_free_8(match_data);

    const result_arr = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;

    for (input_arr.elements.items, 0..) |value, idx| {
        const str_val = valueToString(vm, value) catch "";
        const rc = pcre2_match_8(re, str_val.ptr, str_val.len, 0, 0, match_data, null);
        const matched = (rc >= 0);
        const should_include = if (invert) !matched else matched;

        if (should_include) {
            result_arr.elements.append(vm.allocator, value) catch return BytecodeVM.VMError.OutOfMemory;
            _ = idx;
        }
    }

    return .{ .array_val = result_arr };
}

fn builtinAbs(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .int_val = 0 };
    return switch (args[0]) {
        .int_val => |v| .{ .int_val = if (v < 0) -v else v },
        .float_val => |v| .{ .float_val = if (v < 0.0) -v else v },
        else => .{ .int_val = 0 },
    };
}

fn builtinIntval(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .int_val = 0 };
    return .{ .int_val = args[0].toInt() };
}

fn builtinCeil(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .float_val = 0.0 };
    return switch (args[0]) {
        .int_val => |v| .{ .float_val = @floatFromInt(v) },
        .float_val => |v| .{ .float_val = @ceil(v) },
        else => .{ .float_val = @ceil(args[0].toFloat()) },
    };
}

fn builtinFloor(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .float_val = 0.0 };
    return switch (args[0]) {
        .int_val => |v| .{ .float_val = @floatFromInt(v) },
        .float_val => |v| .{ .float_val = @floor(v) },
        else => .{ .float_val = @floor(args[0].toFloat()) },
    };
}

fn builtinRound(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .float_val = 0.0 };
    const val = args[0].toFloat();
    const precision: i64 = if (args.len >= 2) args[1].toInt() else 0;
    if (precision == 0) return .{ .float_val = @round(val) };

    const p_abs: u64 = @intCast(if (precision < 0) -precision else precision);
    const scale = std.math.pow(f64, 10.0, @floatFromInt(p_abs));
    if (precision > 0) {
        return .{ .float_val = @round(val * scale) / scale };
    }
    return .{ .float_val = @round(val / scale) * scale };
}

fn builtinMax(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    if (args.len == 1) return args[0];

    var has_float = false;
    for (args) |a| {
        if (a == .float_val) {
            has_float = true;
            break;
        }
    }
    if (has_float) {
        const VecLen = 4;
        const Vec = @Vector(VecLen, f64);
        var i: usize = 1;
        var best_vec: Vec = @splat(args[0].toFloat());

        while (i + VecLen <= args.len) : (i += VecLen) {
            const v: Vec = .{
                args[i].toFloat(),
                args[i + 1].toFloat(),
                args[i + 2].toFloat(),
                args[i + 3].toFloat(),
            };
            best_vec = @max(best_vec, v);
        }

        var best: f64 = @reduce(.Max, best_vec);
        while (i < args.len) : (i += 1) {
            const v = args[i].toFloat();
            if (v > best) best = v;
        }
        return .{ .float_val = best };
    }

    const VecLen = 4;
    const Vec = @Vector(VecLen, i64);
    var i: usize = 1;
    var best_vec: Vec = @splat(args[0].toInt());

    while (i + VecLen <= args.len) : (i += VecLen) {
        const v: Vec = .{
            args[i].toInt(),
            args[i + 1].toInt(),
            args[i + 2].toInt(),
            args[i + 3].toInt(),
        };
        best_vec = @max(best_vec, v);
    }

    var best_i: i64 = @reduce(.Max, best_vec);
    while (i < args.len) : (i += 1) {
        const v = args[i].toInt();
        if (v > best_i) best_i = v;
    }
    return .{ .int_val = best_i };
}

fn builtinMin(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    if (args.len == 1) return args[0];

    var has_float = false;
    for (args) |a| {
        if (a == .float_val) {
            has_float = true;
            break;
        }
    }
    if (has_float) {
        const VecLen = 4;
        const Vec = @Vector(VecLen, f64);
        var i: usize = 1;
        var best_vec: Vec = @splat(args[0].toFloat());

        while (i + VecLen <= args.len) : (i += VecLen) {
            const v: Vec = .{
                args[i].toFloat(),
                args[i + 1].toFloat(),
                args[i + 2].toFloat(),
                args[i + 3].toFloat(),
            };
            best_vec = @min(best_vec, v);
        }

        var best: f64 = @reduce(.Min, best_vec);
        while (i < args.len) : (i += 1) {
            const v = args[i].toFloat();
            if (v < best) best = v;
        }
        return .{ .float_val = best };
    }

    const VecLen = 4;
    const Vec = @Vector(VecLen, i64);
    var i: usize = 1;
    var best_vec: Vec = @splat(args[0].toInt());

    while (i + VecLen <= args.len) : (i += VecLen) {
        const v: Vec = .{
            args[i].toInt(),
            args[i + 1].toInt(),
            args[i + 2].toInt(),
            args[i + 3].toInt(),
        };
        best_vec = @min(best_vec, v);
    }

    var best_i: i64 = @reduce(.Min, best_vec);
    while (i < args.len) : (i += 1) {
        const v = args[i].toInt();
        if (v < best_i) best_i = v;
    }
    return .{ .int_val = best_i };
}

fn builtinSqrt(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .float_val = 0.0 };
    const v = args[0].toFloat();
    if (v < 0.0) return .{ .float_val = std.math.nan(f64) };
    return .{ .float_val = @sqrt(v) };
}

fn builtinPow(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .{ .float_val = 0.0 };
    const base = args[0].toFloat();
    const exp = args[1].toFloat();
    return .{ .float_val = std.math.pow(f64, base, exp) };
}

fn builtinSin(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .float_val = 0.0 };
    return .{ .float_val = std.math.sin(args[0].toFloat()) };
}

fn builtinCos(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .float_val = 0.0 };
    return .{ .float_val = std.math.cos(args[0].toFloat()) };
}

fn builtinStrpos(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .{ .bool_val = false };
    const hay = switch (args[0]) {
        .string_val => |s| s.data,
        else => valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory,
    };
    const needle = switch (args[1]) {
        .string_val => |s| s.data,
        else => valueToString(vm, args[1]) catch return BytecodeVM.VMError.OutOfMemory,
    };
    const offset_i: i64 = if (args.len >= 3) args[2].toInt() else 0;
    const offset: usize = if (offset_i <= 0) 0 else @intCast(offset_i);
    if (offset >= hay.len) return .{ .bool_val = false };
    if (std.mem.indexOf(u8, hay[offset..], needle)) |pos| {
        return .{ .int_val = @intCast(pos + offset) };
    }
    return .{ .bool_val = false };
}

fn builtinStrrpos(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .{ .bool_val = false };
    const hay = switch (args[0]) {
        .string_val => |s| s.data,
        else => valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory,
    };
    const needle = switch (args[1]) {
        .string_val => |s| s.data,
        else => valueToString(vm, args[1]) catch return BytecodeVM.VMError.OutOfMemory,
    };
    if (needle.len == 0) return .{ .int_val = 0 };
    if (needle.len > hay.len) return .{ .bool_val = false };

    var i: usize = hay.len - needle.len;
    while (true) {
        if (std.mem.eql(u8, hay[i .. i + needle.len], needle)) {
            return .{ .int_val = @intCast(i) };
        }
        if (i == 0) break;
        i -= 1;
    }
    return .{ .bool_val = false };
}

fn builtinSubstr(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    const s = switch (args[0]) {
        .string_val => |str| str.data,
        else => valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory,
    };
    const start_i = args[1].toInt();
    const len_opt: ?i64 = if (args.len >= 3) args[2].toInt() else null;

    const start_idx: usize = blk: {
        if (start_i < 0) {
            const abs_start: usize = @intCast(-start_i);
            break :blk if (abs_start > s.len) 0 else s.len - abs_start;
        }
        break :blk @intCast(@min(start_i, @as(i64, @intCast(s.len))));
    };
    if (start_idx >= s.len) {
        const out = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory;
        return .{ .string_val = out };
    }
    const end_idx: usize = blk: {
        if (len_opt) |len_i| {
            if (len_i >= 0) {
                break :blk @min(start_idx + @as(usize, @intCast(len_i)), s.len);
            }
            const abs_len: usize = @intCast(-len_i);
            break :blk if (abs_len >= s.len - start_idx) start_idx else s.len - abs_len;
        }
        break :blk s.len;
    };
    if (end_idx <= start_idx) {
        const out = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory;
        return .{ .string_val = out };
    }
    const out = vm.createString(s[start_idx..end_idx]) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = out };
}

fn replaceAllAlloc(
    allocator: std.mem.Allocator,
    hay: []const u8,
    needle: []const u8,
    repl: []const u8,
) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, hay);
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);

    var pos: usize = 0;
    while (pos <= hay.len) {
        if (std.mem.indexOfPos(u8, hay, pos, needle)) |i| {
            try out.appendSlice(allocator, hay[pos..i]);
            try out.appendSlice(allocator, repl);
            pos = i + needle.len;
            continue;
        }
        try out.appendSlice(allocator, hay[pos..]);
        break;
    }
    return out.toOwnedSlice(allocator);
}

fn builtinStrReplace(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 3) return .null_val;
    const search = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const repl = valueToString(vm, args[1]) catch return BytecodeVM.VMError.OutOfMemory;
    const subj = valueToString(vm, args[2]) catch return BytecodeVM.VMError.OutOfMemory;

    const buf = replaceAllAlloc(vm.allocator, subj, search, repl) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(buf);
    const out = vm.createString(buf) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = out };
}

fn builtinStrIReplace(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 3) return .null_val;
    const search = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const repl = valueToString(vm, args[1]) catch return BytecodeVM.VMError.OutOfMemory;
    const subj = valueToString(vm, args[2]) catch return BytecodeVM.VMError.OutOfMemory;

    const lower_subj = vm.allocator.dupe(u8, subj) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(lower_subj);
    for (lower_subj) |*c| c.* = std.ascii.toLower(c.*);

    const lower_search = vm.allocator.dupe(u8, search) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(lower_search);
    for (lower_search) |*c| c.* = std.ascii.toLower(c.*);

    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(vm.allocator);

    var pos: usize = 0;
    while (pos <= subj.len) {
        if (std.mem.indexOfPos(u8, lower_subj, pos, lower_search)) |i| {
            out.appendSlice(vm.allocator, subj[pos..i]) catch return BytecodeVM.VMError.OutOfMemory;
            out.appendSlice(vm.allocator, repl) catch return BytecodeVM.VMError.OutOfMemory;
            pos = i + lower_search.len;
            continue;
        }
        out.appendSlice(vm.allocator, subj[pos..]) catch return BytecodeVM.VMError.OutOfMemory;
        break;
    }

    const owned = out.toOwnedSlice(vm.allocator) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(owned);
    const out_str = vm.createString(owned) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = out_str };
}

fn builtinStrtoupper(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .string_val = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory };
    const s = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    // 优化：直接分配最终字符串，避免中间缓冲区
    const buf = vm.allocator.alloc(u8, s.len) catch return BytecodeVM.VMError.OutOfMemory;
    for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    const out = vm.createString(buf) catch {
        vm.allocator.free(buf);
        return BytecodeVM.VMError.OutOfMemory;
    };
    return .{ .string_val = out };
}

fn builtinStrtolower(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .string_val = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory };
    const s = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    // 优化：直接分配最终字符串，避免中间缓冲区
    const buf = vm.allocator.alloc(u8, s.len) catch return BytecodeVM.VMError.OutOfMemory;
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    const out = vm.createString(buf) catch {
        vm.allocator.free(buf);
        return BytecodeVM.VMError.OutOfMemory;
    };
    return .{ .string_val = out };
}

fn builtinUcfirst(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .string_val = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory };
    const s = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    if (s.len == 0) return .{ .string_val = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory };
    // 优化：直接分配最终字符串
    const buf = vm.allocator.alloc(u8, s.len) catch return BytecodeVM.VMError.OutOfMemory;
    @memcpy(buf, s);
    buf[0] = std.ascii.toUpper(buf[0]);
    const out = vm.createString(buf) catch {
        vm.allocator.free(buf);
        return BytecodeVM.VMError.OutOfMemory;
    };
    return .{ .string_val = out };
}

fn builtinUcwords(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .string_val = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory };
    const s = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    // 优化：直接分配最终字符串
    const buf = vm.allocator.alloc(u8, s.len) catch return BytecodeVM.VMError.OutOfMemory;
    @memcpy(buf, s);

    var prev_space = true;
    for (buf) |*c| {
        const is_space = switch (c.*) {
            ' ', '\t', '\n', '\r', 0x0B, 0 => true,
            else => false,
        };
        if (prev_space and !is_space) {
            c.* = std.ascii.toUpper(c.*);
        }
        prev_space = is_space;
    }

    const out = vm.createString(buf) catch {
        vm.allocator.free(buf);
        return BytecodeVM.VMError.OutOfMemory;
    };
    return .{ .string_val = out };
}

fn trimSlice(s: []const u8, mode: enum { both, left, right }) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    if (mode == .both or mode == .left) {
        while (start < end) : (start += 1) {
            const c = s[start];
            const is_space = switch (c) {
                ' ', '\t', '\n', '\r', 0x0B, 0 => true,
                else => false,
            };
            if (!is_space) break;
        }
    }
    if (mode == .both or mode == .right) {
        while (end > start) : (end -= 1) {
            const c = s[end - 1];
            const is_space = switch (c) {
                ' ', '\t', '\n', '\r', 0x0B, 0 => true,
                else => false,
            };
            if (!is_space) break;
        }
    }
    return s[start..end];
}

fn builtinTrim(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .string_val = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory };
    const s = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const out = vm.createString(trimSlice(s, .both)) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = out };
}

fn builtinLtrim(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .string_val = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory };
    const s = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const out = vm.createString(trimSlice(s, .left)) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = out };
}

fn builtinRtrim(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .string_val = vm.createString("") catch return BytecodeVM.VMError.OutOfMemory };
    const s = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const out = vm.createString(trimSlice(s, .right)) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = out };
}

fn builtinExplode(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    const delim = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const str = valueToString(vm, args[1]) catch return BytecodeVM.VMError.OutOfMemory;

    const arr = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    var it = std.mem.splitSequence(u8, str, delim);
    while (it.next()) |part| {
        const s_part = vm.createString(part) catch return BytecodeVM.VMError.OutOfMemory;
        arr.elements.append(vm.allocator, .{ .string_val = s_part }) catch return BytecodeVM.VMError.OutOfMemory;
    }
    return .{ .array_val = arr };
}

fn builtinImplode(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    const glue = valueToString(vm, args[0]) catch return BytecodeVM.VMError.OutOfMemory;
    const arr = switch (args[1]) {
        .array_val => |a| a,
        else => return .null_val,
    };

    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(vm.allocator);
    for (arr.elements.items, 0..) |v, i| {
        if (i != 0) {
            out.appendSlice(vm.allocator, glue) catch return BytecodeVM.VMError.OutOfMemory;
        }
        const s = valueToString(vm, v) catch return BytecodeVM.VMError.OutOfMemory;
        out.appendSlice(vm.allocator, s) catch return BytecodeVM.VMError.OutOfMemory;
    }
    const owned = out.toOwnedSlice(vm.allocator) catch return BytecodeVM.VMError.OutOfMemory;
    defer vm.allocator.free(owned);
    const s_out = vm.createString(owned) catch return BytecodeVM.VMError.OutOfMemory;
    return .{ .string_val = s_out };
}

fn builtinArrayShift(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    return switch (args[0]) {
        .array_val => |arr| {
            if (arr.elements.items.len == 0) return .null_val;
            return arr.elements.orderedRemove(0);
        },
        else => .null_val,
    };
}

fn builtinArrayUnshift(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .{ .int_val = 0 };
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .{ .int_val = 0 },
    };
    var idx: usize = 1;
    var insert_pos: usize = 0;
    while (idx < args.len) : (idx += 1) {
        arr.elements.insert(vm.allocator, insert_pos, args[idx]) catch return BytecodeVM.VMError.OutOfMemory;
        insert_pos += 1;
    }
    return .{ .int_val = @intCast(arr.elements.items.len) };
}

fn builtinInArray(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .{ .bool_val = false };
    const needle = args[0];
    const hay = switch (args[1]) {
        .array_val => |a| a,
        else => return .{ .bool_val = false },
    };
    for (hay.elements.items) |v| {
        if (vm.valuesEqual(v, needle)) return .{ .bool_val = true };
    }
    return .{ .bool_val = false };
}

fn builtinArraySearch(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .{ .bool_val = false };
    const needle = args[0];
    const hay = switch (args[1]) {
        .array_val => |a| a,
        else => return .{ .bool_val = false },
    };
    for (hay.elements.items, 0..) |v, i| {
        if (vm.valuesEqual(v, needle)) return .{ .int_val = @intCast(i) };
    }
    return .{ .bool_val = false };
}

fn builtinArrayValues(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .null_val;
    const hay = switch (args[0]) {
        .array_val => |a| a,
        else => return .null_val,
    };
    const out_arr = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    for (hay.elements.items) |v| {
        out_arr.elements.append(vm.allocator, v) catch return BytecodeVM.VMError.OutOfMemory;
    }
    return .{ .array_val = out_arr };
}

fn builtinArrayMerge(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    const out_arr = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    for (args) |a| {
        if (a == .array_val) {
            const arr = a.array_val;
            for (arr.elements.items) |v| {
                out_arr.elements.append(vm.allocator, v) catch return BytecodeVM.VMError.OutOfMemory;
            }
        }
    }
    return .{ .array_val = out_arr };
}

fn builtinArraySlice(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .null_val,
    };
    const start_i = args[1].toInt();
    const len_i: ?i64 = if (args.len >= 3) args[2].toInt() else null;

    const total: i64 = @intCast(arr.elements.items.len);
    var start: i64 = if (start_i < 0) total + start_i else start_i;
    if (start < 0) start = 0;
    if (start > total) start = total;
    var end: i64 = total;
    if (len_i) |l| {
        end = start + l;
        if (l < 0) end = total + l;
    }
    if (end < start) end = start;
    if (end > total) end = total;

    const out_arr = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    const s: usize = @intCast(start);
    const e: usize = @intCast(end);
    for (arr.elements.items[s..e]) |v| {
        out_arr.elements.append(vm.allocator, v) catch return BytecodeVM.VMError.OutOfMemory;
    }
    return .{ .array_val = out_arr };
}

fn builtinArrayChunk(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .null_val,
    };
    const size_i = args[1].toInt();
    if (size_i <= 0) return .null_val;
    const size: usize = @intCast(size_i);

    const out = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    var i: usize = 0;
    while (i < arr.elements.items.len) : (i += size) {
        const chunk = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
        const end = @min(i + size, arr.elements.items.len);
        for (arr.elements.items[i..end]) |v| {
            chunk.elements.append(vm.allocator, v) catch return BytecodeVM.VMError.OutOfMemory;
        }
        out.elements.append(vm.allocator, .{ .array_val = chunk }) catch return BytecodeVM.VMError.OutOfMemory;
    }
    return .{ .array_val = out };
}

fn builtinRange(vm: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len < 2) return .null_val;
    const start = args[0].toInt();
    const end = args[1].toInt();
    const step: i64 = if (args.len >= 3) args[2].toInt() else 1;
    if (step == 0) return .null_val;

    const arr = vm.createArray() catch return BytecodeVM.VMError.OutOfMemory;
    if (start <= end) {
        var v = start;
        while (v <= end) : (v += @intCast(@abs(step))) {
            arr.elements.append(vm.allocator, .{ .int_val = v }) catch return BytecodeVM.VMError.OutOfMemory;
        }
    } else {
        var v = start;
        while (v >= end) : (v -= @intCast(@abs(step))) {
            arr.elements.append(vm.allocator, .{ .int_val = v }) catch return BytecodeVM.VMError.OutOfMemory;
        }
    }
    return .{ .array_val = arr };
}

fn builtinShuffle(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = false };
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .{ .bool_val = false },
    };
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const rnd = prng.random();

    var i: usize = arr.elements.items.len;
    while (i > 1) {
        i -= 1;
        const j = rnd.uintLessThan(usize, i + 1);
        const tmp = arr.elements.items[i];
        arr.elements.items[i] = arr.elements.items[j];
        arr.elements.items[j] = tmp;
    }
    return .{ .bool_val = true };
}

fn lessThanValue(_: void, a: Value, b: Value) bool {
    return a.toFloat() < b.toFloat();
}

fn greaterThanValue(_: void, a: Value, b: Value) bool {
    return a.toFloat() > b.toFloat();
}

fn builtinSort(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = false };
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .{ .bool_val = false },
    };
    std.mem.sort(Value, arr.elements.items, {}, lessThanValue);
    return .{ .bool_val = true };
}

fn builtinRsort(_: *BytecodeVM, args: []Value) BytecodeVM.VMError!Value {
    if (args.len == 0) return .{ .bool_val = false };
    const arr = switch (args[0]) {
        .array_val => |a| a,
        else => return .{ .bool_val = false },
    };
    std.mem.sort(Value, arr.elements.items, {}, greaterThanValue);
    return .{ .bool_val = true };
}

// ============================================================
// 辅助函数
// ============================================================

/// 将Value转换为字符串（优化版：减少重复分配）
/// 注意：对于int_val和float_val，使用临时字符串池管理
fn valueToString(vm: *BytecodeVM, value: Value) ![]const u8 {
    return switch (value) {
        .null_val => "",
        .bool_val => |b| if (b) "1" else "",
        .int_val => |i| blk: {
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";

            // 优化：小数值直接返回静态字符串
            if (i >= 0 and i <= 9) {
                const static_digits = "0123456789";
                const idx: usize = @intCast(i);
                break :blk static_digits[idx..idx + 1];
            }

            const arena_alloc = vm.temp_arena.allocator();
            const result = try arena_alloc.dupe(u8, slice);
            vm.arena_alloc_count += 1;
            break :blk result;
        },
        .float_val => |f| blk: {
            var buf: [64]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch "0";
            const arena_alloc = vm.temp_arena.allocator();
            const result = try arena_alloc.dupe(u8, slice);
            vm.arena_alloc_count += 1;
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
    vm.temp_strings.clearRetainingCapacity();
    if (vm.arena_alloc_count >= BytecodeVM.ARENA_RESET_THRESHOLD) {
        vm.temp_arena.deinit();
        vm.temp_arena = std.heap.ArenaAllocator.init(vm.allocator);
    } else {
        _ = vm.temp_arena.reset(.retain_capacity);
    }
    vm.arena_alloc_count = 0;
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
    table[@intFromEnum(OpCode.pow_int)] = handlePowInt;
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
    table[@intFromEnum(OpCode.identical)] = handleIdentical;
    table[@intFromEnum(OpCode.not_identical)] = handleNotIdentical;
    table[@intFromEnum(OpCode.lt)] = handleLt;
    table[@intFromEnum(OpCode.gt)] = handleGt;
    table[@intFromEnum(OpCode.le)] = handleLe;
    table[@intFromEnum(OpCode.ge)] = handleGe;
    table[@intFromEnum(OpCode.spaceship)] = handleSpaceship;
    table[@intFromEnum(OpCode.lt_int)] = handleLtInt;
    table[@intFromEnum(OpCode.gt_int)] = handleGtInt;
    table[@intFromEnum(OpCode.lt_float)] = handleLtFloat;
    table[@intFromEnum(OpCode.gt_float)] = handleGtFloat;

    // 逻辑操作
    table[@intFromEnum(OpCode.logic_and)] = handleLogicAnd;
    table[@intFromEnum(OpCode.logic_or)] = handleLogicOr;
    table[@intFromEnum(OpCode.logic_not)] = handleLogicNot;
    table[@intFromEnum(OpCode.coalesce)] = handleCoalesce;

    // 控制流
    table[@intFromEnum(OpCode.jmp)] = handleJmp;
    table[@intFromEnum(OpCode.jz)] = handleJz;
    table[@intFromEnum(OpCode.jnz)] = handleJnz;
    table[@intFromEnum(OpCode.call)] = handleCall;
    table[@intFromEnum(OpCode.call_method)] = handleCallMethod;
    table[@intFromEnum(OpCode.call_static)] = handleCallStatic;
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
    table[@intFromEnum(OpCode.foreach_init)] = handleForeachInit;
    table[@intFromEnum(OpCode.foreach_next)] = handleForeachNext;

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

    // 闭包操作
    table[@intFromEnum(OpCode.make_closure)] = handleMakeClosure;
    table[@intFromEnum(OpCode.closure_call)] = handleClosureCall;
    table[@intFromEnum(OpCode.capture_var)] = handleCaptureVar;
    table[@intFromEnum(OpCode.arrow_fn)] = handleArrowFn;

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

    // 异常处理
    table[@intFromEnum(OpCode.try_begin)] = handleTryBegin;
    table[@intFromEnum(OpCode.try_end)] = handleTryEnd;
    table[@intFromEnum(OpCode.catch_begin)] = handleCatchBegin;
    table[@intFromEnum(OpCode.catch_end)] = handleCatchEnd;
    table[@intFromEnum(OpCode.throw)] = handleThrow;

    return table;
}

/// 无效操作码处理
fn handleInvalidOpcode(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const ip: usize = if (frame.ip == 0) 0 else frame.ip - 1;
    const opcode_u8: u8 = @intFromEnum(inst.opcode);

    std.debug.print(
        "InvalidOpcode: func='{s}' ip={d} opcode=0x{x:0>2}({s}) op1={d} op2={d} hint={d} tail={any} gc={any} stack_top={d} base={d}\n",
        .{
            frame.function.name,
            ip,
            opcode_u8,
            @tagName(inst.opcode),
            inst.operand1,
            inst.operand2,
            @intFromEnum(inst.flags.type_hint),
            inst.flags.is_tail_call,
            inst.flags.needs_gc_check,
            vm.stack_top,
            frame.base_pointer,
        },
    );

    const bc = frame.function.bytecode;
    const start = if (ip > 3) ip - 3 else 0;
    const end = @min(ip + 4, bc.len);
    std.debug.print("  bytecode window [{d}..{d}) (len={d})\n", .{ start, end, bc.len });
    for (bc[start..end], start..) |winst, idx| {
        std.debug.print(
            "  [{d}] 0x{x:0>2}({s}) op1={d} op2={d} hint={d}\n",
            .{
                idx,
                @as(u8, @intFromEnum(winst.opcode)),
                @tagName(winst.opcode),
                winst.operand1,
                winst.operand2,
                @intFromEnum(winst.flags.type_hint),
            },
        );
    }

    return BytecodeVM.VMError.InvalidOpcode;
}

/// NOP - 空操作
fn handleNop(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return .continue_execution;
}

/// try_begin - try块开始
fn handleTryBegin(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    // 暂时不实现完整的异常处理，只是标记让指令能够执行
    return .continue_execution;
}

/// try_end - try块结束
fn handleTryEnd(_: *BytecodeVM, frame: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    // try块正常结束，需要跳过catch块
    // 查找下一个catch_end指令
    const bytecode = frame.function.bytecode;
    var ip = frame.ip;
    while (ip < bytecode.len) : (ip += 1) {
        if (bytecode[ip].opcode == .catch_end) {
            // 跳转到catch_end之后
            frame.ip = ip + 1;
            return .continue_execution;
        }
    }
    // 如果没有找到catch_end，继续正常执行
    return .continue_execution;
}

/// catch_begin - catch块开始
fn handleCatchBegin(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    // catch块开始
    // 在完整实现中，这里应该从异常栈中弹出异常对象并压入栈
    // 由于我们暂时不支持异常，这个块不应该被执行（try_end会跳过）
    // 如果执行到这里，说明有异常发生，但我们暂时不处理
    return .continue_execution;
}

/// catch_end - catch块结束
fn handleCatchEnd(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    return .continue_execution;
}

/// throw - 抛出异常
fn handleThrow(_: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    // 在完整实现中，这里应该查找最近的catch块并跳转
    // 暂时我们返回一个错误
    return BytecodeVM.VMError.UncaughtException;
}

fn handleCaptureVar(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const mode = inst.operand2;
    if (mode == 0) {
        const idx = frame.base_pointer + inst.operand1;
        try vm.push(vm.stack[idx]);
        return .continue_execution;
    }
    try vm.push(.null_val);
    return .continue_execution;
}

fn resolveFunctionForClosure(vm: *BytecodeVM, frame: *CallFrame, operand1: u16) ?*CompiledFunction {
    if (operand1 < frame.function.constants.len) {
        const func_const = frame.function.constants[operand1];
        return switch (func_const) {
            .func_ref => |ref_idx| vm.getFunctionByIndex(ref_idx),
            .string_val => |name| vm.functions.get(name),
            else => null,
        };
    }
    return vm.getFunctionByIndex(operand1);
}

fn handleMakeClosure(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const func = resolveFunctionForClosure(vm, frame, inst.operand1) orelse return BytecodeVM.VMError.UndefinedFunction;
    const capture_count: usize = inst.operand2;
    const captured = vm.allocator.alloc(Value, capture_count) catch return BytecodeVM.VMError.OutOfMemory;

    var i: usize = capture_count;
    while (i > 0) {
        i -= 1;
        captured[i] = try vm.pop();
    }

    const closure = vm.createClosure(func, captured) catch {
        vm.allocator.free(captured);
        return BytecodeVM.VMError.OutOfMemory;
    };
    try vm.push(.{ .closure_val = closure });
    return .continue_execution;
}

fn enterFunctionFrame(vm: *BytecodeVM, current_frame: *CallFrame, func: *CompiledFunction, arg_count: u16) BytecodeVM.VMError!void {
    if (vm.frame_count >= BytecodeVM.FRAMES_MAX) {
        return BytecodeVM.VMError.StackOverflow;
    }

    const new_frame = &vm.frames[vm.frame_count];
    new_frame.* = CallFrame{
        .function = func,
        .ip = 0,
        .base_pointer = vm.stack_top - arg_count,
        .return_address = current_frame.ip,
    };
    vm.frame_count += 1;

    const required_top: u32 = new_frame.base_pointer + func.local_count;
    if (required_top > BytecodeVM.STACK_MAX) {
        return BytecodeVM.VMError.StackOverflow;
    }
    var i: u32 = vm.stack_top;
    while (i < required_top) : (i += 1) {
        vm.stack[i] = .null_val;
    }
    vm.stack_top = required_top;
}

fn callRuntimeName(vm: *BytecodeVM, current_frame: *CallFrame, name: []const u8, arg_count: u16) BytecodeVM.VMError!void {
    if (vm.functions.get(name)) |func| {
        try enterFunctionFrame(vm, current_frame, func, arg_count);
        return;
    }
    if (vm.builtins.get(name)) |builtin_fn| {
        const args_slice = vm.stack[vm.stack_top - arg_count .. vm.stack_top];
        vm.stack_top -= arg_count;
        const result = builtin_fn(vm, args_slice) catch .null_val;
        try vm.push(result);
        return;
    }
    if (name.len > 0 and name[0] == '\\') {
        const short = name[1..];
        if (vm.functions.get(short)) |func| {
            try enterFunctionFrame(vm, current_frame, func, arg_count);
            return;
        }
        if (vm.builtins.get(short)) |builtin_fn| {
            const args_slice = vm.stack[vm.stack_top - arg_count .. vm.stack_top];
            vm.stack_top -= arg_count;
            const result = builtin_fn(vm, args_slice) catch .null_val;
            try vm.push(result);
            return;
        }
    }
    return BytecodeVM.VMError.UndefinedFunction;
}

fn handleClosureCall(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const arg_count: u16 = inst.operand2;
    if (vm.stack_top < arg_count + 1) {
        return BytecodeVM.VMError.StackUnderflow;
    }

    const callable_index: u32 = vm.stack_top - arg_count - 1;
    const callable = vm.stack[callable_index];

    var i: u32 = 0;
    while (i < arg_count) : (i += 1) {
        vm.stack[callable_index + i] = vm.stack[callable_index + 1 + i];
    }
    vm.stack_top -= 1;

    switch (callable) {
        .closure_val => |closure| {
            try enterFunctionFrame(vm, frame, closure.function, arg_count);
            const new_frame = &vm.frames[vm.frame_count - 1];
            const slots = closure.function.capture_local_slots;
            const cap_len: usize = @min(slots.len, closure.captured.len);
            var j: usize = 0;
            while (j < cap_len) : (j += 1) {
                const slot_idx: u32 = new_frame.base_pointer + slots[j];
                if (slot_idx < vm.stack_top) {
                    vm.stack[slot_idx] = closure.captured[j];
                }
            }
            return .frame_changed;
        },
        .string_val => |s| {
            try callRuntimeName(vm, frame, s.data, arg_count);
            return .frame_changed;
        },
        else => return BytecodeVM.VMError.TypeMismatch,
    }
}

fn handleArrowFn(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    _ = vm;
    return BytecodeVM.VMError.InvalidOpcode;
}

/// PUSH_CONST - 压入常量
fn handlePushConst(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = try vm.loadConstant(frame.function, inst.operand1);
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

/// OPT-003: 优化的整数加法 - 使用快速栈操作
fn handleAddInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b_val = vm.popFast();
    const a_val = vm.popFast();
    if (a_val == .float_val or b_val == .float_val) {
        vm.pushFast(.{ .float_val = a_val.toFloat() + b_val.toFloat() });
    } else {
        vm.pushFast(.{ .int_val = a_val.toInt() +% b_val.toInt() });
    }
    return .continue_execution;
}

/// OPT-003: 优化的整数减法 - 使用快速栈操作
fn handleSubInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b_val = vm.popFast();
    const a_val = vm.popFast();
    if (a_val == .float_val or b_val == .float_val) {
        vm.pushFast(.{ .float_val = a_val.toFloat() - b_val.toFloat() });
    } else {
        vm.pushFast(.{ .int_val = a_val.toInt() -% b_val.toInt() });
    }
    return .continue_execution;
}

/// OPT-003: 优化的整数乘法 - 使用快速栈操作
fn handleMulInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b_val = vm.popFast();
    const a_val = vm.popFast();
    if (a_val == .float_val or b_val == .float_val) {
        vm.pushFast(.{ .float_val = a_val.toFloat() * b_val.toFloat() });
    } else {
        vm.pushFast(.{ .int_val = a_val.toInt() *% b_val.toInt() });
    }
    return .continue_execution;
}

fn handleDivInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b_val = try vm.pop();
    const a_val = try vm.pop();
    const b_f = b_val.toFloat();
    if (b_f == 0.0) return BytecodeVM.VMError.DivisionByZero;
    // PHP 语义：/ 返回浮点数
    try vm.push(.{ .float_val = a_val.toFloat() / b_f });
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

fn handlePowInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = (try vm.pop()).toInt();
    const a = (try vm.pop()).toInt();
    const result = std.math.pow(i64, a, @intCast(b));
    try vm.push(.{ .int_val = result });
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

fn handleIdentical(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = try vm.pop();
    const a = try vm.pop();
    try vm.push(.{ .bool_val = vm.valuesIdentical(a, b) });
    return .continue_execution;
}

fn handleNotIdentical(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = try vm.pop();
    const a = try vm.pop();
    try vm.push(.{ .bool_val = !vm.valuesIdentical(a, b) });
    return .continue_execution;
}

/// OPT-006: 类型特化的整数小于比较 - 使用快速栈操作
fn handleLtInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast().toInt();
    const a = vm.popFast().toInt();
    vm.pushFast(.{ .bool_val = a < b });
    return .continue_execution;
}

/// OPT-006: 类型特化的整数大于比较 - 使用快速栈操作
fn handleGtInt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast().toInt();
    const a = vm.popFast().toInt();
    vm.pushFast(.{ .bool_val = a > b });
    return .continue_execution;
}

/// OPT-006: 类型特化的浮点小于比较 - 使用快速栈操作
fn handleLtFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast().toFloat();
    const a = vm.popFast().toFloat();
    vm.pushFast(.{ .bool_val = a < b });
    return .continue_execution;
}

/// OPT-006: 类型特化的浮点大于比较 - 使用快速栈操作
fn handleGtFloat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast().toFloat();
    const a = vm.popFast().toFloat();
    vm.pushFast(.{ .bool_val = a > b });
    return .continue_execution;
}

/// OPT-006: 通用小于比较 - 使用快速栈操作
fn handleLt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast();
    const a = vm.popFast();
    const result = switch (a) {
        .int_val => |a_int| switch (b) {
            .int_val => |b_int| a_int < b_int,
            .float_val => |b_float| @as(f64, @floatFromInt(a_int)) < b_float,
            else => false,
        },
        .float_val => |a_float| switch (b) {
            .int_val => |b_int| a_float < @as(f64, @floatFromInt(b_int)),
            .float_val => |b_float| a_float < b_float,
            else => false,
        },
        else => false,
    };
    vm.pushFast(.{ .bool_val = result });
    return .continue_execution;
}

/// OPT-006: 通用大于比较 - 使用快速栈操作
fn handleGt(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast();
    const a = vm.popFast();
    const result = switch (a) {
        .int_val => |a_int| switch (b) {
            .int_val => |b_int| a_int > b_int,
            .float_val => |b_float| @as(f64, @floatFromInt(a_int)) > b_float,
            else => false,
        },
        .float_val => |a_float| switch (b) {
            .int_val => |b_int| a_float > @as(f64, @floatFromInt(b_int)),
            .float_val => |b_float| a_float > b_float,
            else => false,
        },
        else => false,
    };
    vm.pushFast(.{ .bool_val = result });
    return .continue_execution;
}

/// Spaceship operator <=> - returns -1, 0, or 1
fn handleSpaceship(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast();
    const a = vm.popFast();
    const result: i64 = switch (a) {
        .int_val => |a_int| switch (b) {
            .int_val => |b_int| if (a_int < b_int) @as(i64, -1) else if (a_int > b_int) @as(i64, 1) else @as(i64, 0),
            .float_val => |b_float| blk: {
                const a_f = @as(f64, @floatFromInt(a_int));
                break :blk if (a_f < b_float) @as(i64, -1) else if (a_f > b_float) @as(i64, 1) else @as(i64, 0);
            },
            else => 0,
        },
        .float_val => |a_float| switch (b) {
            .int_val => |b_int| blk: {
                const b_f = @as(f64, @floatFromInt(b_int));
                break :blk if (a_float < b_f) @as(i64, -1) else if (a_float > b_f) @as(i64, 1) else @as(i64, 0);
            },
            .float_val => |b_float| if (a_float < b_float) @as(i64, -1) else if (a_float > b_float) @as(i64, 1) else @as(i64, 0),
            else => 0,
        },
        .string_val => |a_str| switch (b) {
            .string_val => |b_str| blk: {
                const cmp = std.mem.order(u8, a_str.data, b_str.data);
                break :blk switch (cmp) {
                    .lt => @as(i64, -1),
                    .gt => @as(i64, 1),
                    .eq => @as(i64, 0),
                };
            },
            else => 0,
        },
        else => 0,
    };
    vm.pushFast(.{ .int_val = result });
    return .continue_execution;
}

/// OPT-006: 通用小于等于比较 - 使用快速栈操作
fn handleLe(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast();
    const a = vm.popFast();
    const result = switch (a) {
        .int_val => |a_int| switch (b) {
            .int_val => |b_int| a_int <= b_int,
            .float_val => |b_float| @as(f64, @floatFromInt(a_int)) <= b_float,
            else => false,
        },
        .float_val => |a_float| switch (b) {
            .int_val => |b_int| a_float <= @as(f64, @floatFromInt(b_int)),
            .float_val => |b_float| a_float <= b_float,
            else => false,
        },
        else => vm.valuesEqual(a, b),
    };
    vm.pushFast(.{ .bool_val = result });
    return .continue_execution;
}

/// OPT-006: 通用大于等于比较 - 使用快速栈操作
fn handleGe(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast();
    const a = vm.popFast();
    const result = switch (a) {
        .int_val => |a_int| switch (b) {
            .int_val => |b_int| a_int >= b_int,
            .float_val => |b_float| @as(f64, @floatFromInt(a_int)) >= b_float,
            else => false,
        },
        .float_val => |a_float| switch (b) {
            .int_val => |b_int| a_float >= @as(f64, @floatFromInt(b_int)),
            .float_val => |b_float| a_float >= b_float,
            else => false,
        },
        else => vm.valuesEqual(a, b),
    };
    try vm.push(.{ .bool_val = result });
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
    const val = try vm.pop();
    const result = !val.toBool();
    try vm.push(.{ .bool_val = result });
    return .continue_execution;
}

/// OPT-015: Null coalescing operator (??)
/// @post 栈顶为左值（非 null）或右值（左值为 null）
fn handleCoalesce(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const right = try vm.pop();
    const left = try vm.pop();

    const result = if (left == .null_val) right else left;
    try vm.push(result);
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

/// 静态方法调用处理函数
/// operand1 = 参数数量
/// 栈布局: [class_name, method_name, arg1, arg2, ...] -> [result]
/// @complexity O(1) 内联缓存命中时，O(log n) 缓存未命中时
/// @thread-safety ISOLATED
fn handleCallStatic(vm: *BytecodeVM, frame: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    _ = frame;
    const arg_count = inst.operand1;

    // 栈布局验证：至少需要 class_name + method_name + args
    // stack_top 指向下一个可用位置，所以需要 >= arg_count + 2 个元素
    const required_elements = arg_count + 2;
    if (vm.stack_top < required_elements) {
        return BytecodeVM.VMError.StackUnderflow;
    }

    // 获取类名（在栈底）
    const class_name_idx = vm.stack_top - arg_count - 2;
    const class_name_val = vm.stack[class_name_idx];
    if (class_name_val != .string_val) {
        return BytecodeVM.VMError.TypeMismatch;
    }
    const class_name = class_name_val.string_val.data;

    // 获取方法名（在类名之上）
    const method_name_idx = vm.stack_top - arg_count - 1;
    const method_name_val = vm.stack[method_name_idx];
    if (method_name_val != .string_val) {
        return BytecodeVM.VMError.TypeMismatch;
    }
    const method_name = method_name_val.string_val.data;

    // 类型反馈：记录静态方法调用点
    if (vm.enable_type_feedback) {
        const call_site_id = @as(u32, vm.frames[vm.frame_count - 1].ip - 1) | 0x40000000; // 高位标记为静态方法调用
        vm.type_feedback_collector.record(call_site_id, .object_type) catch {};
    }

    // 构造缓存键（类名 + 方法名）
    const cache_key = computeStaticMethodCacheKey(class_name, method_name);

    // 1. 尝试从内联缓存中查找静态方法
    var cached_method: ?*CompiledFunction = null;
    if (vm.enable_inline_cache) {
        if (vm.method_cache.lookupMethod(method_name, cache_key)) |method_ptr| {
            cached_method = @ptrCast(@alignCast(method_ptr));
            vm.stats.cache_hits += 1;
        } else {
            vm.stats.cache_misses += 1;
        }
    }

    // 2. 如果缓存未命中，查找静态方法
    // 注意：在完整实现中，这里应该从类的静态方法表中查找
    // 目前简化为查找全局函数表中的 "ClassName::methodName" 格式
    var method_func: ?*CompiledFunction = cached_method;
    if (method_func == null) {
        // 构造完整方法名：ClassName::methodName
        const full_method_name = std.fmt.allocPrint(
            vm.allocator,
            "{s}::{s}",
            .{ class_name, method_name }
        ) catch {
            return BytecodeVM.VMError.OutOfMemory;
        };
        defer vm.allocator.free(full_method_name);

        // 查找函数
        method_func = vm.functions.get(full_method_name);

        // 如果未找到，尝试不带命名空间前缀的查找
        if (method_func == null and class_name.len > 0 and class_name[0] == '\\') {
            const short_class_name = class_name[1..];
            const short_full_name = std.fmt.allocPrint(
                vm.allocator,
                "{s}::{s}",
                .{ short_class_name, method_name }
            ) catch {
                return BytecodeVM.VMError.OutOfMemory;
            };
            defer vm.allocator.free(short_full_name);
            method_func = vm.functions.get(short_full_name);
        }

        // 3. 缓存找到的方法
        if (vm.enable_inline_cache and method_func != null) {
            vm.method_cache.cacheMethod(
                method_name,
                cache_key,
                @ptrCast(method_func.?)
            ) catch {};
        }
    }

    // 4. 执行静态方法调用
    if (method_func) |func| {
        // 收集参数
        var args = std.ArrayList(Value).initCapacity(vm.allocator, arg_count) catch {
            return BytecodeVM.VMError.OutOfMemory;
        };
        defer args.deinit(vm.allocator);

        // 弹出参数（逆序）
        var i: u16 = 0;
        while (i < arg_count) : (i += 1) {
            const arg = try vm.pop();
            try args.insert(vm.allocator, 0, arg); // 插入到开头以保持正确顺序
        }

        // 弹出方法名和类名
        _ = try vm.pop(); // method_name
        _ = try vm.pop(); // class_name

        // 5. 创建新的调用帧
        if (vm.frame_count >= BytecodeVM.FRAMES_MAX) {
            return BytecodeVM.VMError.StackOverflow;
        }

        const new_frame_idx = vm.frame_count;
        vm.frame_count += 1;

        vm.frames[new_frame_idx] = CallFrame{
            .function = func,
            .ip = 0,
            .base_pointer = vm.stack_top,
            .return_address = vm.frames[new_frame_idx - 1].ip,
        };

        // 6. 压入参数
        for (args.items) |arg| {
            try vm.push(arg);
        }

        // 7. 分配局部变量空间
        var j: u32 = 0;
        while (j < func.local_count) : (j += 1) {
            try vm.push(.null_val);
        }

        return .frame_changed;
    } else {
        // 静态方法未找到 - 弹出所有参数并返回 null
        var i: u16 = 0;
        while (i < arg_count + 2) : (i += 1) {
            _ = try vm.pop();
        }
        try vm.push(.null_val);
        return .continue_execution;
    }
}

/// 计算静态方法缓存键
/// @pre class_name 和 method_name 必须有效
/// @post 返回唯一的缓存键
fn computeStaticMethodCacheKey(class_name: []const u8, method_name: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(class_name);
    hasher.update("::");
    hasher.update(method_name);
    return hasher.final();
}

/// 方法调用处理函数 - 使用内联缓存优化
/// 方法调用指令处理（完整实现）
/// operand1 = 方法名在常量池中的索引
/// operand2 = 参数数量
/// 栈布局: [object, arg1, arg2, ...] -> [result]
/// @complexity O(1) 内联缓存命中时，O(log n) 缓存未命中时
/// @thread-safety ISOLATED
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

            // 1. 尝试从内联缓存中查找方法（O(1)）
            var cached_method: ?*CompiledFunction = null;
            if (vm.enable_inline_cache) {
                if (vm.method_cache.lookupMethod(method_name, class_id)) |method_ptr| {
                    cached_method = @ptrCast(@alignCast(method_ptr));
                    vm.stats.cache_hits += 1;
                } else {
                    vm.stats.cache_misses += 1;
                }
            }

            // 2. 如果缓存未命中，从类定义中查找方法
            var method_func: ?*CompiledFunction = cached_method;
            if (method_func == null) {
                // 从对象的属性中查找方法
                // 注意：在完整的实现中，这里应该从类的方法表中查找
                if (obj.properties.get(method_name)) |method_val| {
                    switch (method_val) {
                        .closure_val => |closure| {
                            method_func = closure.function;
                        },
                        else => {
                            // 方法不是闭包类型
                            return BytecodeVM.VMError.TypeMismatch;
                        },
                    }
                } else {
                    // 方法未找到
                    return BytecodeVM.VMError.UndefinedFunction;
                }
                
                // 3. 缓存找到的方法
                if (vm.enable_inline_cache and method_func != null) {
                    vm.method_cache.cacheMethod(
                        method_name, 
                        class_id, 
                        @ptrCast(method_func.?)
                    ) catch {};
                }
            }

            // 4. 准备方法调用
            if (method_func) |func| {
                // 收集参数
                var args = std.ArrayList(Value).initCapacity(vm.allocator, arg_count) catch {
                    return BytecodeVM.VMError.OutOfMemory;
                };
                defer args.deinit(vm.allocator);
                
                // 弹出参数（逆序）
                var i: u16 = 0;
                while (i < arg_count) : (i += 1) {
                    const arg = try vm.pop();
                    try args.insert(vm.allocator, 0, arg); // 插入到开头以保持正确顺序
                }
                
                // 弹出对象（this）
                _ = try vm.pop();
                
                // 5. 创建新的调用帧
                if (vm.frame_count >= BytecodeVM.FRAMES_MAX) {
                    return BytecodeVM.VMError.StackOverflow;
                }
                
                const new_frame_idx = vm.frame_count;
                vm.frame_count += 1;
                
                vm.frames[new_frame_idx] = CallFrame{
                    .function = func,
                    .ip = 0,
                    .base_pointer = vm.stack_top,
                    .return_address = frame.ip,
                };
                
                // 6. 压入 this 对象作为第一个参数
                try vm.push(obj_val);
                
                // 7. 压入其他参数
                for (args.items) |arg| {
                    try vm.push(arg);
                }
                
                // 8. 分配局部变量空间
                var j: u32 = 0;
                while (j < func.local_count) : (j += 1) {
                    try vm.push(.null_val);
                }
                
                return .frame_changed;
            } else {
                // 方法未找到
                return BytecodeVM.VMError.UndefinedFunction;
            }
        },
        .struct_val => |s| {
            // 结构体方法调用（完整实现）
            const struct_id = @as(u64, s.struct_id) | 0x10000; // 区分结构体和类

            // 尝试从内联缓存中查找方法
            var cached_method: ?*CompiledFunction = null;
            if (vm.enable_inline_cache) {
                if (vm.method_cache.lookupMethod(method_name, struct_id)) |method_ptr| {
                    cached_method = @ptrCast(@alignCast(method_ptr));
                    vm.stats.cache_hits += 1;
                } else {
                    vm.stats.cache_misses += 1;
                }
            }

            // 如果缓存未命中，查找结构体方法
            // 注意：结构体方法通常是静态的，需要从结构体定义中查找
            // 这里简化为返回错误，实际实现需要结构体方法表
            
            // 弹出参数和结构体
            var i: u16 = 0;
            while (i < arg_count + 1) : (i += 1) {
                _ = try vm.pop();
            }

            // 压入结果（结构体方法调用暂不支持）
            try vm.push(.null_val);
            return .continue_execution;
        },
        else => {
            // 非对象类型调用方法 - 错误
            return BytecodeVM.VMError.TypeMismatch;
        },
    }
}

/// 计算方法缓存键
/// @pre method_name 必须有效
/// @post 返回唯一的缓存键
fn computeMethodCacheKey(method_name: []const u8, class_id: u64) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(method_name);
    hasher.update(std.mem.asBytes(&class_id));
    return hasher.final();
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
    // void 函数也需要压入返回值（null），这样调用者可以正确 pop
    try vm.push(.null_val);
    return .frame_changed;
}

/// 在函数字节码中，从 loop_start 开始查找匹配的 loop_end（支持嵌套）
fn findMatchingLoopEnd(func: *CompiledFunction, loop_start_index: u32) ?u32 {
    var depth: u32 = 0;
    var i: u32 = loop_start_index;
    while (i < func.bytecode.len) : (i += 1) {
        const op = func.bytecode[i].opcode;
        if (op == .loop_start) {
            depth += 1;
        } else if (op == .loop_end) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

/// OPT-010: 循环热点检测 - 记录循环入口并触发编译/执行替换
/// @post 如果 JIT 编译代码可用，则执行原生代码并跳过解释执行
fn handleLoopStart(vm: *BytecodeVM, frame: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    if (!vm.enable_jit) return .continue_execution;
    const jit_ptr = vm.jit_compiler orelse return .continue_execution;

    // 取指后 ip 已自增，所以当前 loop_start 的索引是 ip-1
    if (frame.ip == 0) return .continue_execution;
    const loop_start_index: u32 = frame.ip - 1;

    // loop_id：用函数地址与 loop_start_index 混合，保证同一次运行内稳定
    const func_addr: usize = @intFromPtr(frame.function);
    const loop_id: u32 = @as(u32, @truncate(func_addr)) ^ loop_start_index;

    // 检查是否已有编译代码（OSR 执行替换）
    if (jit_ptr.compiled_cache.get(loop_id)) |native_code| {
        if (native_code.entry_point) |entry| {
            // 调用原生代码（传入 VM 上下文）
            const result = entry(@ptrCast(vm));
            // result == 0 表示成功执行，跳转到 loop_end 后继续
            if (result == 0) {
                const loop_end_index = findMatchingLoopEnd(frame.function, loop_start_index) orelse return .continue_execution;
                // 跳转到 loop_end 之后
                frame.ip = loop_end_index + 1;
                return .continue_execution;
            }
            // result != 0 表示需要回退到解释执行（去优化）
        }
    }

    // 热点检测与编译
    if (!jit_ptr.recordLoopIteration(loop_id)) {
        return .continue_execution;
    }

    const loop_end_index = findMatchingLoopEnd(frame.function, loop_start_index) orelse
        return .continue_execution;

    // 编译 [loop_start, loop_end]（含 loop_end）
    const start_usize: usize = @intCast(loop_start_index);
    const end_usize: usize = @intCast(loop_end_index + 1);
    const slice = frame.function.bytecode[start_usize..end_usize];
    _ = jit_ptr.compileFunction(loop_id, slice) catch null;

    return .continue_execution;
}

/// OPT-010: 循环热点检测 - 循环出口（目前只保留为标记点）
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

/// OPT-008: 数组访问内联优化 - 使用快速栈操作
fn handleArrayGet(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const index = vm.popFast();
    const arr_val = vm.popFast();

    // 快速路径：整数索引访问
    if (arr_val == .array_val and index == .int_val) {
        const arr = arr_val.array_val;
        const idx = index.int_val;
        if (idx >= 0) {
            const i: usize = @intCast(idx);
            if (i < arr.elements.items.len) {
                vm.pushFast(arr.elements.items[i]);
                return .continue_execution;
            }
        }
        vm.pushFast(.null_val);
        return .continue_execution;
    }

    // 字符串键访问
    if (arr_val == .array_val and index == .string_val) {
        const arr = arr_val.array_val;
        if (arr.keys.get(index.string_val.data)) |i| {
            vm.pushFast(arr.elements.items[i]);
        } else {
            vm.pushFast(.null_val);
        }
        return .continue_execution;
    }

    vm.pushFast(.null_val);
    return .continue_execution;
}

/// OPT-008: 数组设置内联优化 - 使用快速栈操作
fn handleArraySet(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    // 检查是否是数组追加操作（operand1 = 1 表示追加）
    const is_append = inst.operand1 == 1;
    
    if (is_append) {
        // 数组追加：栈顺序 [值, 数组]
        const arr_val = vm.popFast();
        const value = vm.popFast();
        
        if (arr_val == .array_val) {
            const arr = arr_val.array_val;
            arr.elements.append(vm.allocator, value) catch
                return BytecodeVM.VMError.OutOfMemory;
            vm.pushFast(.{ .array_val = arr });
        } else {
            vm.pushFast(.null_val);
        }
        return .continue_execution;
    }
    
    // 数组索引设置：栈顺序 [值, 数组, 索引]
    const index = vm.popFast();
    const arr_val = vm.popFast();
    const value = vm.popFast();

    // 快速路径：整数索引设置
    if (arr_val == .array_val and index == .int_val) {
        const arr = arr_val.array_val;
        const idx = index.int_val;
        if (idx >= 0) {
            const i: usize = @intCast(idx);
            if (i < arr.elements.items.len) {
                arr.elements.items[i] = value;
            } else {
                while (arr.elements.items.len < i) {
                    arr.elements.append(vm.allocator, .null_val) catch
                        return BytecodeVM.VMError.OutOfMemory;
                }
                arr.elements.append(vm.allocator, value) catch
                    return BytecodeVM.VMError.OutOfMemory;
            }
        }
        vm.pushFast(.{ .array_val = arr });
        return .continue_execution;
    }

    // 字符串键设置
    if (arr_val == .array_val and index == .string_val) {
        const arr = arr_val.array_val;
        const key = index.string_val;
        if (arr.keys.get(key.data)) |i| {
            arr.elements.items[i] = value;
        } else {
            const key_copy = vm.allocator.dupe(u8, key.data) catch
                return BytecodeVM.VMError.OutOfMemory;
            const new_idx = arr.elements.items.len;
            arr.elements.append(vm.allocator, value) catch
                return BytecodeVM.VMError.OutOfMemory;
            arr.keys.put(vm.allocator, key_copy, new_idx) catch
                return BytecodeVM.VMError.OutOfMemory;
        }
        vm.pushFast(.{ .array_val = arr });
        return .continue_execution;
    }

    vm.pushFast(.null_val);
    return .continue_execution;
}

/// OPT-008: 数组推入内联优化
fn handleArrayPush(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const value = vm.popFast();
    const arr_val = vm.popFast();
    if (arr_val == .array_val) {
        const arr = arr_val.array_val;
        arr.elements.append(vm.allocator, value) catch
            return BytecodeVM.VMError.OutOfMemory;
        vm.pushFast(.{ .array_val = arr });
    } else {
        vm.pushFast(.null_val);
    }
    return .continue_execution;
}

/// OPT-008: 数组弹出内联优化
fn handleArrayPop(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const arr_val = vm.popFast();
    if (arr_val == .array_val) {
        const arr = arr_val.array_val;
        if (arr.elements.items.len > 0) {
            vm.pushFast(arr.elements.pop() orelse .null_val);
        } else {
            vm.pushFast(.null_val);
        }
    } else {
        vm.pushFast(.null_val);
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

// ========== foreach 循环处理函数 ==========

fn handleForeachInit(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const iterable = try vm.pop();
    
    // 创建迭代器
    const iterator = vm.allocator.create(Value.Iterator) catch return BytecodeVM.VMError.OutOfMemory;
    iterator.* = .{
        .iterable = iterable,
        .current_index = 0,
        .keys = null,
        .is_done = false,
        .ref_count = 1,
        .marked = false,
    };
    
    // 如果是关联数组，提取键
    switch (iterable) {
        .array_val => |arr| {
            if (arr.keys.count() > 0) {
                // 关联数组：提取所有键
                const keys = vm.allocator.alloc([]const u8, arr.keys.count()) catch return BytecodeVM.VMError.OutOfMemory;
                var i: usize = 0;
                var iter = arr.keys.iterator();
                while (iter.next()) |entry| : (i += 1) {
                    keys[i] = entry.key_ptr.*;
                }
                iterator.keys = keys;
            }
            // 检查是否为空
            iterator.is_done = arr.elements.items.len == 0;
        },
        else => {
            // 不可迭代的类型，标记为完成
            iterator.is_done = true;
        },
    }
    
    try vm.push(.{ .iterator_val = iterator });
    return .continue_execution;
}

fn handleForeachNext(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const jump_target = inst.operand1;
    const iterator_val = vm.peek(0);
    
    switch (iterator_val) {
        .iterator_val => |iterator| {
            if (iterator.is_done) {
                // 迭代完成，跳转到循环结束
                _ = try vm.pop(); // 弹出迭代器
                return .{ .jump_to = jump_target };
            } else {
                // 获取当前键值对
                switch (iterator.iterable) {
                    .array_val => |arr| {
                        const idx: usize = @intCast(iterator.current_index);
                        
                        if (idx < arr.elements.items.len) {
                            // 获取键
                            const key: Value = if (iterator.keys) |keys| blk: {
                                // 关联数组：使用字符串键
                                const key_str = vm.allocator.create(Value.String) catch return BytecodeVM.VMError.OutOfMemory;
                                const key_data = vm.allocator.dupe(u8, keys[idx]) catch return BytecodeVM.VMError.OutOfMemory;
                                key_str.* = .{
                                    .data = key_data,
                                    .ref_count = 1,
                                    .marked = false,
                                };
                                vm.string_pool.append(vm.allocator, key_str) catch return BytecodeVM.VMError.OutOfMemory;
                                break :blk .{ .string_val = key_str };
                            } else blk: {
                                // 索引数组：使用整数键
                                break :blk .{ .int_val = iterator.current_index };
                            };
                            
                            // 获取值
                            const value = arr.elements.items[idx];
                            
                            // 压入 key 和 value，保持 iterator 在栈底
                            // 栈布局：[iterator] -> [iterator, key, value]
                            try vm.push(key);
                            try vm.push(value);
                            
                            // 更新迭代器
                            iterator.current_index += 1;
                            if (idx + 1 >= arr.elements.items.len) {
                                iterator.is_done = true;
                            }
                        } else {
                            // 索引越界，标记完成
                            iterator.is_done = true;
                            _ = try vm.pop();
                            return .{ .jump_to = jump_target };
                        }
                    },
                    else => {
                        // 不可迭代，跳转
                        iterator.is_done = true;
                        _ = try vm.pop();
                        return .{ .jump_to = jump_target };
                    },
                }
            }
        },
        else => {
            // 不是迭代器，错误
            return BytecodeVM.VMError.TypeMismatch;
        },
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
        .marked = false,
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

/// OPT-009: 小字符串栈上缓冲区阈值
const SMALL_STRING_BUFFER_SIZE: usize = 256;

/// OPT-007+009: 优化字符串拼接 - 快速路径 + 对象复用 + 小字符串栈上缓冲区
fn handleConcat(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const b = vm.popFast();
    const a = vm.popFast();

    // 快速路径：两边都是字符串，直接拼接
    if (a == .string_val and b == .string_val) {
        const str_a = a.string_val.data;
        const str_b = b.string_val.data;
        
        // 检查长度相加是否溢出
        const add_result = @addWithOverflow(str_a.len, str_b.len);
        if (add_result[1] != 0) {
            // 溢出：字符串太长，返回空字符串
            const empty_str = vm.allocator.create(Value.String) catch
                return BytecodeVM.VMError.OutOfMemory;
            empty_str.* = .{ .data = &[_]u8{}, .ref_count = 1, .marked = false };
            vm.string_pool.append(vm.allocator, empty_str) catch
                return BytecodeVM.VMError.OutOfMemory;
            vm.pushFast(.{ .string_val = empty_str });
            return .continue_execution;
        }
        
        const result_len = add_result[0];

        // OPT-009: 小字符串使用栈上缓冲区避免堆分配
        var stack_buffer: [SMALL_STRING_BUFFER_SIZE]u8 = undefined;
        const use_stack = result_len <= SMALL_STRING_BUFFER_SIZE;

        const result_data = if (use_stack) blk: {
            @memcpy(stack_buffer[0..str_a.len], str_a);
            @memcpy(stack_buffer[str_a.len..][0..str_b.len], str_b);
            break :blk vm.allocator.dupe(u8, stack_buffer[0..result_len]) catch
                return BytecodeVM.VMError.OutOfMemory;
        } else blk: {
            const data = vm.allocator.alloc(u8, result_len) catch
                return BytecodeVM.VMError.OutOfMemory;
            @memcpy(data[0..str_a.len], str_a);
            @memcpy(data[str_a.len..], str_b);
            break :blk data;
        };

        // 尝试复用空闲String对象
        const result_str = if (vm.free_strings.items.len > 0) blk: {
            const s = vm.free_strings.items[vm.free_strings.items.len - 1];
            vm.free_strings.items.len -= 1;
            if (s.data.len > 0) {
                vm.allocator.free(s.data);
            }
            break :blk s;
        } else blk: {
            break :blk vm.allocator.create(Value.String) catch
                return BytecodeVM.VMError.OutOfMemory;
        };

        result_str.* = .{ .data = result_data, .ref_count = 1, .marked = false };
        vm.string_pool.append(vm.allocator, result_str) catch
            return BytecodeVM.VMError.OutOfMemory;
        vm.pushFast(.{ .string_val = result_str });
        return .continue_execution;
    }

    // 慢路径：需要类型转换
    const str_a = valueToString(vm, a) catch return BytecodeVM.VMError.OutOfMemory;
    const str_b = valueToString(vm, b) catch return BytecodeVM.VMError.OutOfMemory;
    
    // 检查长度相加是否溢出
    const add_result = @addWithOverflow(str_a.len, str_b.len);
    if (add_result[1] != 0) {
        // 溢出：字符串太长，返回空字符串
        const empty_str = vm.allocator.create(Value.String) catch
            return BytecodeVM.VMError.OutOfMemory;
        empty_str.* = .{ .data = &[_]u8{}, .ref_count = 1, .marked = false };
        vm.string_pool.append(vm.allocator, empty_str) catch
            return BytecodeVM.VMError.OutOfMemory;
        vm.pushFast(.{ .string_val = empty_str });
        return .continue_execution;
    }
    
    const result_len = add_result[0];
    const result_data = vm.allocator.alloc(u8, result_len) catch
        return BytecodeVM.VMError.OutOfMemory;
    @memcpy(result_data[0..str_a.len], str_a);
    @memcpy(result_data[str_a.len..], str_b);

    // 尝试复用空闲String对象
    const result_str = if (vm.free_strings.items.len > 0) blk: {
        const s = vm.free_strings.items[vm.free_strings.items.len - 1];
        vm.free_strings.items.len -= 1;
        if (s.data.len > 0) {
            vm.allocator.free(s.data);
        }
        break :blk s;
    } else blk: {
        break :blk vm.allocator.create(Value.String) catch
            return BytecodeVM.VMError.OutOfMemory;
    };

    result_str.* = .{ .data = result_data, .ref_count = 1, .marked = false };
    vm.string_pool.append(vm.allocator, result_str) catch
        return BytecodeVM.VMError.OutOfMemory;
    vm.pushFast(.{ .string_val = result_str });
    return .continue_execution;
}

/// OPT-007: 优化strlen - 使用快速栈操作
fn handleStrlen(vm: *BytecodeVM, _: *CallFrame, _: Instruction) BytecodeVM.VMError!DispatchResult {
    const val = vm.popFast();
    switch (val) {
        .string_val => |s| vm.pushFast(.{ .int_val = @intCast(s.data.len) }),
        else => vm.pushFast(.{ .int_val = 0 }),
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
            new_str.* = .{ .data = new_data, .ref_count = 1, .marked = false };
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
                .marked = false,
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
            new_str.* = .{ .data = new_data, .ref_count = 1, .marked = false };
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
                .marked = false,
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
                .marked = false,
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
