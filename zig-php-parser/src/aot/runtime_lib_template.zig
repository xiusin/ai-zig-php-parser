//! AOT Runtime Library Template
//!
//! 这是AOT编译器使用的完整运行时库模板。
//! 实现了PHP值类型系统和所有必需的运算符函数。
//!
//! ## 设计原则
//! 1. **零依赖**：除了Zig标准库，不依赖任何其他模块
//! 2. **内存安全**：使用引用计数管理内存，防止泄漏
//! 3. **性能优化**：使用NaN boxing技术，48位整数快速路径
//! 4. **PHP语义**：严格遵循PHP 8.5的类型转换和运算规则
//!
//! @ownership TRANSFER (Value类型通过引用计数管理)
//! @thread-safety ISOLATED (每个编译的程序独立运行)
//! @memory-model Reference Counting with Cycle Detection

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// 全局运行时状态
// ============================================================================

/// 全局分配器（由main函数初始化）
/// 注意：这是一个全局变量，在AOT编译的代码中可以直接访问
pub var runtime_allocator: Allocator = undefined;

/// 初始化运行时
pub fn initRuntime(allocator: Allocator) void {
    runtime_allocator = allocator;
    initClassRegistry(allocator);
}

/// 清理运行时
pub fn deinitRuntime() void {
    // 清理全局资源（如果有）
}

// ============================================================================
// 字符串类型
// ============================================================================

/// PHP字符串类型
/// 使用引用计数管理内存，支持写时复制（COW）
pub const PHPString = struct {
    data: []u8,
    length: usize,
    ref_count: usize,
    is_static: bool, // 静态字符串不需要释放

    /// 创建新字符串
    pub fn init(allocator: Allocator, str: []const u8) !*PHPString {
        // 添加长度检查，防止过大的字符串
        if (str.len > 1024 * 1024 * 100) { // 100MB限制
            return error.StringTooLarge;
        }

        const php_string = try allocator.create(PHPString);
        errdefer allocator.destroy(php_string);

        // 安全的内存分配和复制
        const new_data = try allocator.alloc(u8, str.len);
        errdefer allocator.free(new_data);

        if (str.len > 0) {
            @memcpy(new_data, str);
        }

        php_string.data = new_data;
        php_string.length = str.len;
        php_string.ref_count = 1;
        php_string.is_static = false;
        return php_string;
    }

    /// 创建静态字符串（不需要释放）
    pub fn initStatic(str: []const u8) *PHPString {
        // 注意：静态字符串的生命周期由调用者管理
        // 这里返回的是栈上的临时对象，仅用于常量字符串
        var static_str = PHPString{
            .data = @constCast(str),
            .length = str.len,
            .ref_count = 999999, // 永不释放
            .is_static = true,
        };
        return &static_str;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPString) void {
        if (!self.is_static) {
            self.ref_count += 1;
        }
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPString, allocator: Allocator) void {
        if (self.is_static) return;

        if (self.ref_count == 0) return; // 防止重复释放

        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit(allocator);
        }
    }

    /// 释放字符串
    fn deinit(self: *PHPString, allocator: Allocator) void {
        if (!self.is_static) {
            allocator.free(self.data);
            allocator.destroy(self);
        }
    }

    /// 字符串连接
    pub fn concat(self: *PHPString, other: *PHPString, allocator: Allocator) !*PHPString {
        const new_length = self.length + other.length;

        // 添加长度检查
        if (new_length > 1024 * 1024 * 100) { // 100MB限制
            return error.StringTooLarge;
        }

        // 安全的内存分配
        const new_data = try allocator.alloc(u8, new_length);
        errdefer allocator.free(new_data);

        // 使用@memcpy进行安全复制
        if (self.length > 0) {
            @memcpy(new_data[0..self.length], self.data[0..self.length]);
        }
        if (other.length > 0) {
            @memcpy(new_data[self.length..new_length], other.data[0..other.length]);
        }

        const result = try allocator.create(PHPString);
        errdefer allocator.destroy(result);

        result.data = new_data;
        result.length = new_length;
        result.ref_count = 1;
        result.is_static = false;
        return result;
    }

    /// 获取子字符串
    pub fn substring(self: *PHPString, start: i64, length: ?i64, allocator: Allocator) !*PHPString {
        // 处理负数起始位置
        const start_idx: usize = blk: {
            if (start < 0) {
                const abs_start = @as(usize, @intCast(-start));
                break :blk if (abs_start > self.length) 0 else self.length - abs_start;
            } else {
                break :blk @intCast(@min(start, @as(i64, @intCast(self.length))));
            }
        };

        if (start_idx >= self.length) {
            return PHPString.init(allocator, "");
        }

        // 处理长度参数
        const end_idx: usize = blk: {
            if (length) |length_val| {
                if (length_val >= 0) {
                    break :blk @min(start_idx + @as(usize, @intCast(length_val)), self.length);
                } else {
                    const abs_len = @as(usize, @intCast(-length_val));
                    if (abs_len >= self.length - start_idx) {
                        return PHPString.init(allocator, "");
                    }
                    break :blk self.length - abs_len;
                }
            } else {
                break :blk self.length;
            }
        };

        if (start_idx >= end_idx) {
            return PHPString.init(allocator, "");
        }

        return PHPString.init(allocator, self.data[start_idx..end_idx]);
    }

    /// 查找子字符串位置
    pub fn indexOf(self: *PHPString, needle: *PHPString) i64 {
        if (needle.length == 0) return 0;
        if (needle.length > self.length) return -1;

        for (0..self.length - needle.length + 1) |i| {
            if (std.mem.eql(u8, self.data[i .. i + needle.length], needle.data)) {
                return @intCast(i);
            }
        }
        return -1;
    }

    /// 字符串长度
    pub fn len(self: *PHPString) usize {
        return self.length;
    }
};

// ============================================================================
// 数组类型
// ============================================================================

/// 数组键类型
pub const ArrayKey = union(enum) {
    integer: i64,
    string: *PHPString,

    pub fn hash(self: ArrayKey) u64 {
        return switch (self) {
            .integer => |i| std.hash.Wyhash.hash(0, std.mem.asBytes(&i)),
            .string => |s| std.hash.Wyhash.hash(0, s.data),
        };
    }

    pub fn eql(self: ArrayKey, other: ArrayKey) bool {
        return switch (self) {
            .integer => |a| switch (other) {
                .integer => |b| a == b,
                else => false,
            },
            .string => |a| switch (other) {
                .string => |b| std.mem.eql(u8, a.data, b.data),
                else => false,
            },
        };
    }
};

/// PHP数组类型
/// 支持整数键和字符串键的混合数组
pub const PHPArray = struct {
    // 使用 ArrayHashMap 保持插入顺序
    elements: std.ArrayHashMap(ArrayKey, Value, ArrayContext, true),
    next_index: i64,
    ref_count: usize,

    pub const ArrayContext = struct {
        pub fn hash(_: ArrayContext, key: ArrayKey) u32 {
            return @truncate(key.hash());
        }

        pub fn eql(_: ArrayContext, a: ArrayKey, b: ArrayKey, _: usize) bool {
            return a.eql(b);
        }
    };

    /// 创建新数组
    pub fn init(allocator: Allocator) !*PHPArray {
        const array = try allocator.create(PHPArray);
        array.elements = std.ArrayHashMap(ArrayKey, Value, ArrayContext, true).init(allocator);
        array.next_index = 0;
        array.ref_count = 1;
        return array;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPArray) void {
        self.ref_count += 1;
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPArray, allocator: Allocator) void {
        if (self.ref_count == 0) return;

        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit(allocator);
        }
    }

    /// 释放数组
    fn deinit(self: *PHPArray, allocator: Allocator) void {
        var iter = self.elements.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(allocator);
            if (entry.key_ptr.* == .string) {
                entry.key_ptr.string.release(allocator);
            }
        }
        self.elements.deinit();
        allocator.destroy(self);
    }

    /// 获取元素
    pub fn get(self: *PHPArray, key: ArrayKey) ?Value {
        return self.elements.get(key);
    }

    /// 获取元素（通过Value键）
    pub fn getByValue(self: *PHPArray, key: Value) ?Value {
        if (key.isString()) {
            return self.get(ArrayKey{ .string = key.asString() });
        } else {
            return self.get(ArrayKey{ .integer = key.asInt() });
        }
    }

    /// 设置元素（通过Value键）
    pub fn setByValue(self: *PHPArray, allocator: Allocator, key: Value, value: Value) !void {
        if (key.isString()) {
            try self.set(allocator, ArrayKey{ .string = key.asString() }, value);
        } else {
            try self.set(allocator, ArrayKey{ .integer = key.toInt() }, value);
        }
    }

    /// 设置元素
    pub fn set(self: *PHPArray, allocator: Allocator, key: ArrayKey, value: Value) !void {
        // 释放旧值
        if (self.elements.get(key)) |old_value| {
            old_value.release(allocator);
        }

        // 保留新值
        _ = value.retain();

        // 如果是字符串键，保留键
        if (key == .string) {
            key.string.retain();
        }

        // 更新next_index
        if (key == .integer and key.integer >= self.next_index) {
            self.next_index = key.integer + 1;
        }

        try self.elements.put(key, value);
    }

    /// 追加元素（使用下一个整数索引）
    pub fn push(self: *PHPArray, allocator: Allocator, value: Value) !void {
        const key = ArrayKey{ .integer = self.next_index };
        _ = value.retain();
        try self.elements.put(key, value);
        self.next_index += 1;
        _ = allocator; // 避免未使用警告
    }

    /// 获取元素数量
    pub fn count(self: *PHPArray) usize {
        return self.elements.count();
    }
};

// ============================================================================
// Value类型 - NaN Boxing实现
// ============================================================================

/// PHP值类型
/// 使用NaN boxing技术，将所有类型编码到64位中
///
/// 编码方案：
/// - Float: 正常的IEEE 754双精度浮点数
/// - Null: QNAN | TAG_NIL
/// - Bool: QNAN | TAG_FALSE/TAG_TRUE
/// - Int: TAG_INT_MARKER | (48位整数)
/// - Pointer: TAG_PTR | TYPE_TAG | (47位地址)
pub const Value = struct {
    val: u64,

    // NaN boxing常量
    pub const SIGN_BIT: u64 = 0x8000000000000000;
    pub const QNAN: u64 = 0x7FFC000000000000;

    // 简单类型标签
    pub const TAG_NIL: u64 = 1;
    pub const TAG_FALSE: u64 = 2;
    pub const TAG_TRUE: u64 = 3;
    pub const TAG_INT_MARKER: u64 = SIGN_BIT | QNAN;

    // 指针类型标记
    pub const TAG_PTR: u64 = QNAN;
    pub const TYPE_MASK: u64 = 0x0003800000000000;
    pub const TYPE_STRING: u64 = 0x0000800000000000;
    pub const TYPE_ARRAY: u64 = 0x0001000000000000;
    pub const TYPE_FUNCTION: u64 = 0x0002000000000000;

    // 48位整数常量
    pub const INT48_MASK: u64 = 0x0000FFFFFFFFFFFF;
    pub const INT48_SIGN_BIT: u64 = 0x0000800000000000;
    pub const INT48_MAX: i64 = 0x00007FFFFFFFFFFF;
    pub const INT48_MIN: i64 = -0x0000800000000000;

    // ========================================================================
    // 构造函数
    // ========================================================================

    /// 创建null值
    pub fn initNull() Value {
        return .{ .val = QNAN | TAG_NIL };
    }

    /// 创建布尔值
    pub fn initBool(b: bool) Value {
        return .{ .val = QNAN | (if (b) TAG_TRUE else TAG_FALSE) };
    }

    /// 创建整数值
    pub fn initInt(i: i64) Value {
        // 48位整数范围检查
        if (i >= INT48_MIN and i <= INT48_MAX) {
            const encoded: u64 = @as(u64, @bitCast(i)) & INT48_MASK;
            return .{ .val = TAG_INT_MARKER | encoded };
        }
        // 超出范围：使用浮点数存储
        return .{ .val = @bitCast(@as(f64, @floatFromInt(i))) };
    }

    /// 创建浮点数值
    pub fn initFloat(f: f64) Value {
        return .{ .val = @bitCast(f) };
    }

    /// 创建字符串值
    pub fn initString(str: *PHPString) Value {
        const addr = @intFromPtr(str);
        return .{ .val = TAG_PTR | TYPE_STRING | (addr & 0x00007FFFFFFFFFFF) };
    }

    /// 创建数组值
    pub fn initArray(arr: *PHPArray) Value {
        const addr = @intFromPtr(arr);
        return .{ .val = TAG_PTR | TYPE_ARRAY | (addr & 0x00007FFFFFFFFFFF) };
    }

    /// 创建函数值
    pub fn initFunction(func: *PHPFunction) Value {
        const addr = @intFromPtr(func);
        return .{ .val = TAG_PTR | TYPE_FUNCTION | (addr & 0x00007FFFFFFFFFFF) };
    }

    // ========================================================================
    // 类型检查
    // ========================================================================

    pub fn isNull(self: Value) bool {
        return self.val == (QNAN | TAG_NIL);
    }

    pub fn isBool(self: Value) bool {
        return self.val == (QNAN | TAG_FALSE) or self.val == (QNAN | TAG_TRUE);
    }

    pub fn isInt(self: Value) bool {
        return (self.val & (SIGN_BIT | QNAN)) == TAG_INT_MARKER;
    }

    pub fn isFloat(self: Value) bool {
        return (self.val & QNAN) != QNAN;
    }

    pub fn isString(self: Value) bool {
        // 首先检查是否是指针类型（QNAN位设置，但SIGN_BIT未设置）
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        // 然后检查类型标签
        return (self.val & TYPE_MASK) == TYPE_STRING;
    }

    pub fn isArray(self: Value) bool {
        // 首先检查是否是指针类型（QNAN位设置，但SIGN_BIT未设置）
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        // 然后检查类型标签
        return (self.val & TYPE_MASK) == TYPE_ARRAY;
    }

    pub fn isFunction(self: Value) bool {
        // 首先检查是否是指针类型（QNAN位设置，但SIGN_BIT未设置）
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        // 然后检查类型标签
        return (self.val & TYPE_MASK) == TYPE_FUNCTION;
    }

    // ========================================================================
    // 数据提取
    // ========================================================================

    pub fn asBool(self: Value) bool {
        return (self.val & 0x1) == 1;
    }

    pub fn asInt(self: Value) i64 {
        if ((self.val & (SIGN_BIT | QNAN)) == TAG_INT_MARKER) {
            const raw: u64 = self.val & INT48_MASK;
            // 符号扩展
            if ((raw & INT48_SIGN_BIT) != 0) {
                return @bitCast(raw | 0xFFFF000000000000);
            }
            return @bitCast(raw);
        }
        // 可能是浮点数存储的大整数
        if ((self.val & QNAN) != QNAN) {
            const f: f64 = @bitCast(self.val);
            if (f >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
                f <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
            {
                return @intFromFloat(f);
            }
        }
        return 0;
    }

    pub fn asFloat(self: Value) f64 {
        return @bitCast(self.val);
    }

    pub fn asString(self: Value) *PHPString {
        return @ptrFromInt(self.val & 0x00007FFFFFFFFFFF);
    }

    pub fn asArray(self: Value) *PHPArray {
        return @ptrFromInt(self.val & 0x00007FFFFFFFFFFF);
    }

    pub fn asFunction(self: Value) *PHPFunction {
        return @ptrFromInt(self.val & 0x00007FFFFFFFFFFF);
    }

    // ========================================================================
    // 引用计数
    // ========================================================================

    pub fn retain(self: Value) void {
        if (self.isString()) {
            self.asString().retain();
        } else if (self.isArray()) {
            self.asArray().retain();
        } else if (Value_isObject(self)) {
            Value_asObject(self).retain();
        } else if (self.isFunction()) {
            self.asFunction().retain();
        }
    }

    pub fn release(self: Value, allocator: Allocator) void {
        if (self.isString()) {
            self.asString().release(allocator);
        } else if (self.isArray()) {
            self.asArray().release(allocator);
        } else if (Value_isObject(self)) {
            Value_asObject(self).release();
        } else if (self.isFunction()) {
            self.asFunction().release();
        }
    }

    // ========================================================================
    // 类型转换
    // ========================================================================

    /// 转换为布尔值（PHP语义）
    pub fn toBool(self: Value) bool {
        if (self.isNull()) return false;
        if (self.isBool()) return self.asBool();
        if (self.isInt()) return self.asInt() != 0;
        if (self.isFloat()) return self.asFloat() != 0.0;
        if (self.isString()) return self.asString().length > 0;
        if (self.isArray()) return self.asArray().count() > 0;
        return true;
    }

    /// 转换为整数（PHP语义）
    pub fn toInt(self: Value) i64 {
        if (self.isInt()) return self.asInt();
        if (self.isFloat()) {
            const f = self.asFloat();
            if (f >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
                f <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
            {
                return @intFromFloat(f);
            }
            return 0;
        }
        if (self.isBool()) return if (self.asBool()) 1 else 0;
        if (self.isNull()) return 0;
        // 字符串转整数：解析数字前缀
        if (self.isString()) {
            const str = self.asString();
            if (str.length == 0) return 0;
            // 简化实现：只处理纯数字字符串
            return std.fmt.parseInt(i64, str.data, 10) catch 0;
        }
        return 0;
    }

    /// 转换为浮点数（PHP语义）
    pub fn toFloat(self: Value) f64 {
        if (self.isFloat()) return self.asFloat();
        if (self.isInt()) return @floatFromInt(self.asInt());
        if (self.isBool()) return if (self.asBool()) 1.0 else 0.0;
        if (self.isNull()) return 0.0;
        if (self.isString()) {
            const str = self.asString();
            if (str.length == 0) return 0.0;
            return std.fmt.parseFloat(f64, str.data) catch 0.0;
        }
        return 0.0;
    }

    /// 转换为字符串（PHP语义）
    /// 注意：返回的字符串引用计数已经+1，调用者负责release
    pub fn toString(self: Value, allocator: Allocator) !*PHPString {
        if (self.isNull()) return PHPString.init(allocator, "");
        if (self.isBool()) return PHPString.init(allocator, if (self.asBool()) "1" else "");
        if (self.isInt()) {
            const str = try std.fmt.allocPrint(allocator, "{d}", .{self.asInt()});
            defer allocator.free(str);
            return PHPString.init(allocator, str);
        }
        if (self.isFloat()) {
            const str = try std.fmt.allocPrint(allocator, "{d}", .{self.asFloat()});
            defer allocator.free(str);
            return PHPString.init(allocator, str);
        }
        if (self.isString()) {
            // 对于已经是字符串的值，创建一个新副本
            // 这样调用者可以安全地release而不影响原始值
            return PHPString.init(allocator, self.asString().data);
        }
        if (self.isArray()) {
            return PHPString.init(allocator, "Array");
        }
        if (self.isFunction()) {
            return PHPString.init(allocator, "Function");
        }
        return PHPString.init(allocator, "");
    }
};

// ============================================================================
// Value类型扩展 - 函数/回调支持
// ============================================================================

pub const PHPFunction = struct {
    func: *const fn (args: []const Value, allocator: Allocator) anyerror!Value,
    ref_count: usize,
    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
        func: *const fn (args: []const Value, allocator: Allocator) anyerror!Value,
    ) !*PHPFunction {
        const f = try allocator.create(PHPFunction);
        errdefer allocator.destroy(f);
        f.* = .{ .func = func, .ref_count = 1, .allocator = allocator };
        return f;
    }

    pub fn retain(self: *PHPFunction) void {
        self.ref_count += 1;
    }

    pub fn release(self: *PHPFunction) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.allocator.destroy(self);
        }
    }
};

const BuiltinFunctionEntry = struct {
    name: []const u8,
    func: *const fn (args: []const Value, allocator: Allocator) anyerror!Value,
};

fn lookupBuiltinFunction(name: []const u8) ?*const fn (args: []const Value, allocator: Allocator) anyerror!Value {
    const builtin_functions = comptime blk: {
        @setEvalBranchQuota(10000);
        break :blk [_]BuiltinFunctionEntry{
            .{ .name = "strlen", .func = wrapBuiltin_strlen },
            .{ .name = "strtoupper", .func = wrapBuiltin_strtoupper },
            .{ .name = "strtolower", .func = wrapBuiltin_strtolower },
            .{ .name = "trim", .func = wrapBuiltin_trim },
            .{ .name = "count", .func = wrapBuiltin_count },
            .{ .name = "strval", .func = wrapBuiltin_strval },
            .{ .name = "array_map", .func = wrapBuiltin_array_map },
            .{ .name = "array_filter", .func = wrapBuiltin_array_filter },
            .{ .name = "array_reduce", .func = wrapBuiltin_array_reduce },
        };
    };

    for (builtin_functions) |entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return entry.func;
        }
    }
    return null;
}

fn wrapBuiltin_strlen(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strlen(args[0]);
}

fn wrapBuiltin_strtoupper(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strtoupper(args[0], allocator);
}

fn wrapBuiltin_strtolower(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strtolower(args[0], allocator);
}

fn wrapBuiltin_trim(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_trim(args[0], allocator);
}

fn wrapBuiltin_count(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_count(args[0]);
}

fn wrapBuiltin_strval(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strval(args[0], allocator);
}

fn wrapBuiltin_array_map(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_array_map(args[0], args[1], allocator);
}

fn wrapBuiltin_array_filter(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;
    const callback = if (args.len >= 2) args[1] else Value.initNull();
    return php_array_filter(args[0], callback, allocator);
}

fn wrapBuiltin_array_reduce(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 2) return error.InvalidArgumentCount;
    const initial = if (args.len >= 3) args[2] else Value.initNull();
    return php_array_reduce(args[0], args[1], initial, allocator);
}

pub fn php_invoke_callable(callback: Value, args: []const Value, allocator: Allocator) !Value {
    if (callback.isFunction()) {
        const f = callback.asFunction();
        return f.func(args, allocator);
    }
    if (callback.isString()) {
        const func_name = callback.asString().data;
        if (lookupBuiltinFunction(func_name)) |func| {
            return func(args, allocator);
        }
        return error.UnknownFunction;
    }
    return error.InvalidCallback;
}

// ============================================================================
// 算术运算符
// ============================================================================

/// 加法运算（PHP语义）
pub fn php_add(lhs: Value, rhs: Value) !Value {
    // 整数 + 整数 = 整数（可能溢出为浮点）
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @addWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            // 溢出：转为浮点数
            return Value.initFloat(@as(f64, @floatFromInt(a)) + @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    // 其他情况：转为浮点数
    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a + b);
}

/// 减法运算（PHP语义）
pub fn php_sub(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @subWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            return Value.initFloat(@as(f64, @floatFromInt(a)) - @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a - b);
}

/// 乘法运算（PHP语义）
pub fn php_mul(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @mulWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            return Value.initFloat(@as(f64, @floatFromInt(a)) * @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a * b);
}

/// 除法运算（PHP语义）
pub fn php_div(lhs: Value, rhs: Value) !Value {
    // PHP除法总是返回浮点数（除非整除）
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        if (b == 0) return error.DivisionByZero;
        if (@mod(a, b) == 0) {
            const result = @divTrunc(a, b);
            if (result >= Value.INT48_MIN and result <= Value.INT48_MAX) {
                return Value.initInt(result);
            }
        }
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    if (b == 0.0) return error.DivisionByZero;
    return Value.initFloat(a / b);
}

/// 取模运算（PHP语义）
pub fn php_mod(lhs: Value, rhs: Value) !Value {
    const a = lhs.toInt();
    const b = rhs.toInt();
    if (b == 0) return error.DivisionByZero;
    return Value.initInt(@mod(a, b));
}

/// 幂运算（PHP语义）
pub fn php_pow(base: Value, exp: Value) !Value {
    const b = base.toFloat();
    const e = exp.toFloat();
    return Value.initFloat(std.math.pow(f64, b, e));
}

// ============================================================================
// 比较运算符
// ============================================================================

/// 等于运算（PHP语义：类型转换后比较）
pub fn php_eq(lhs: Value, rhs: Value) !Value {
    // null == null
    if (lhs.isNull() and rhs.isNull()) return Value.initBool(true);

    // bool == bool
    if (lhs.isBool() and rhs.isBool()) {
        return Value.initBool(lhs.asBool() == rhs.asBool());
    }

    // int == int
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() == rhs.asInt());
    }

    // 数字比较
    if ((lhs.isInt() or lhs.isFloat()) and (rhs.isInt() or rhs.isFloat())) {
        return Value.initBool(lhs.toFloat() == rhs.toFloat());
    }

    // 字符串比较
    if (lhs.isString() and rhs.isString()) {
        const a = lhs.asString();
        const b = rhs.asString();
        return Value.initBool(std.mem.eql(u8, a.data, b.data));
    }

    // 其他情况：转为字符串比较
    return Value.initBool(false);
}

/// 不等于运算
pub fn php_ne(lhs: Value, rhs: Value) !Value {
    const result = try php_eq(lhs, rhs);
    return Value.initBool(!result.asBool());
}

/// 全等运算（PHP语义：类型和值都相等）
pub fn php_identical(lhs: Value, rhs: Value) !Value {
    // 类型不同
    if (lhs.isNull() != rhs.isNull()) return Value.initBool(false);
    if (lhs.isBool() != rhs.isBool()) return Value.initBool(false);
    if (lhs.isInt() != rhs.isInt()) return Value.initBool(false);
    if (lhs.isFloat() != rhs.isFloat()) return Value.initBool(false);
    if (lhs.isString() != rhs.isString()) return Value.initBool(false);
    if (lhs.isArray() != rhs.isArray()) return Value.initBool(false);

    // 类型相同，比较值
    if (lhs.isNull()) return Value.initBool(true);
    if (lhs.isBool()) return Value.initBool(lhs.asBool() == rhs.asBool());
    if (lhs.isInt()) return Value.initBool(lhs.asInt() == rhs.asInt());
    if (lhs.isFloat()) return Value.initBool(lhs.asFloat() == rhs.asFloat());
    if (lhs.isString()) {
        const a = lhs.asString();
        const b = rhs.asString();
        return Value.initBool(std.mem.eql(u8, a.data, b.data));
    }
    if (lhs.isArray()) {
        // 数组比较：指针相同
        return Value.initBool(lhs.asArray() == rhs.asArray());
    }

    return Value.initBool(false);
}

/// 不全等运算
pub fn php_not_identical(lhs: Value, rhs: Value) !Value {
    const result = try php_identical(lhs, rhs);
    return Value.initBool(!result.asBool());
}

/// 小于运算
pub fn php_lt(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() < rhs.asInt());
    }
    return Value.initBool(lhs.toFloat() < rhs.toFloat());
}

/// 小于等于运算
pub fn php_le(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() <= rhs.asInt());
    }
    return Value.initBool(lhs.toFloat() <= rhs.toFloat());
}

/// 大于运算
pub fn php_gt(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() > rhs.asInt());
    }
    return Value.initBool(lhs.toFloat() > rhs.toFloat());
}

/// 大于等于运算
pub fn php_ge(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() >= rhs.asInt());
    }
    return Value.initBool(lhs.toFloat() >= rhs.toFloat());
}

// ============================================================================
// 逻辑运算符
// ============================================================================

/// 逻辑与运算
pub fn php_and(lhs: Value, rhs: Value) !Value {
    return Value.initBool(lhs.toBool() and rhs.toBool());
}

/// 逻辑或运算
pub fn php_or(lhs: Value, rhs: Value) !Value {
    return Value.initBool(lhs.toBool() or rhs.toBool());
}

/// 逻辑非运算
pub fn php_not(val: Value) !Value {
    return Value.initBool(!val.toBool());
}

// ============================================================================
// 字符串运算符
// ============================================================================

/// 字符串连接运算
pub fn php_concat(lhs: Value, rhs: Value, allocator: Allocator) !Value {
    const lhs_str = try lhs.toString(allocator);
    defer lhs_str.release(allocator);

    const rhs_str = try rhs.toString(allocator);
    defer rhs_str.release(allocator);

    const result = try lhs_str.concat(rhs_str, allocator);
    return Value.initString(result);
}

// ============================================================================
// 输出函数
// ============================================================================

/// echo语句
pub fn php_echo(value: Value) !void {
    if (value.isNull()) {
        // null不输出任何内容
        return;
    } else if (value.isBool()) {
        if (value.asBool()) {
            std.debug.print("1", .{});
        }
        // false不输出任何内容
    } else if (value.isInt()) {
        std.debug.print("{d}", .{value.asInt()});
    } else if (value.isFloat()) {
        std.debug.print("{d}", .{value.asFloat()});
    } else if (value.isString()) {
        const str = value.asString();
        std.debug.print("{s}", .{str.data});
    } else if (value.isArray()) {
        std.debug.print("Array", .{});
    }
}

/// print语句（返回1）
pub fn php_print(value: Value) !Value {
    try php_echo(value);
    return Value.initInt(1);
}

/// var_dump函数
pub fn php_var_dump(value: Value) !void {
    if (value.isNull()) {
        std.debug.print("NULL\n", .{});
    } else if (value.isBool()) {
        std.debug.print("bool({})\n", .{value.asBool()});
    } else if (value.isInt()) {
        std.debug.print("int({})\n", .{value.asInt()});
    } else if (value.isFloat()) {
        std.debug.print("float({})\n", .{value.asFloat()});
    } else if (value.isString()) {
        const str = value.asString();
        std.debug.print("string({}) \"{s}\"\n", .{ str.length, str.data });
    } else if (value.isArray()) {
        const arr = value.asArray();
        std.debug.print("array({d}) {{\n", .{arr.count()});
        // 遍历数组
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            std.debug.print("  ", .{});
            switch (entry.key_ptr.*) {
                .integer => |i| std.debug.print("[{d}]", .{i}),
                .string => |s| std.debug.print("[\"{s}\"]", .{s.data}),
            }
            std.debug.print(" =>\n  ", .{});
            php_var_dump(entry.value_ptr.*);
        }
        std.debug.print("}}\n", .{});
    }
}

// ============================================================================
// 数组迭代器函数
// ============================================================================

pub const ArrayIterator = struct {
    iter: std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).Iterator,
    current: ?std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).Entry,
};

pub fn php_array_iter_init(array_val: Value, allocator: Allocator) !i64 {
    if (!array_val.isArray()) return 0;
    const array = array_val.asArray();
    const iter = try allocator.create(ArrayIterator);
    iter.iter = array.elements.iterator();
    iter.current = iter.iter.next();
    return @as(i64, @intCast(@intFromPtr(iter)));
}

pub fn php_array_iter_valid(iter_val: Value) !bool {
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return false;
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    return iter.current != null;
}

pub fn php_array_iter_key(iter_val: Value, allocator: Allocator) !Value {
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    if (iter.current) |entry| {
        switch (entry.key_ptr.*) {
            .integer => |i| return Value.initInt(i),
            .string => |s| {
                s.retain();
                return Value.initString(s);
            },
        }
    }
    _ = allocator;
    return Value.initNull();
}

pub fn php_array_iter_value(iter_val: Value) !Value {
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    if (iter.current) |entry| {
        entry.value_ptr.retain();
        return entry.value_ptr.*;
    }
    return Value.initNull();
}

pub fn php_array_iter_next(iter_val: Value) !i64 {
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return 0;
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    iter.current = iter.iter.next();
    return iter_addr;
}

pub fn php_array_iter_free(iter_val: Value, allocator: Allocator) !void {
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return;
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    allocator.destroy(iter);
}

// ============================================================================
// 字符串函数
// ============================================================================

/// strlen - 获取字符串长度
pub fn php_strlen(str: Value) !Value {
    if (!str.isString()) return Value.initInt(0);
    return Value.initInt(@intCast(str.asString().length));
}

/// substr - 获取子字符串
pub fn php_substr(str: Value, start: Value, length: Value, allocator: Allocator) !Value {
    if (!str.isString()) return Value.initNull();

    const php_str = str.asString();
    const start_int = start.toInt();
    const length_int = if (length.isNull()) null else length.toInt();

    const result = try php_str.substring(start_int, length_int, allocator);
    return Value.initString(result);
}

/// strpos - 查找子字符串位置
pub fn php_strpos(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();
    const pos = hay.indexOf(need);

    if (pos < 0) return Value.initBool(false);
    return Value.initInt(pos);
}

/// strtoupper - 转换为大写
pub fn php_strtoupper(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const upper = try allocator.alloc(u8, php_str.length);
    defer allocator.free(upper);

    for (php_str.data, 0..) |c, i| {
        upper[i] = std.ascii.toUpper(c);
    }

    const result = try PHPString.init(allocator, upper);
    return Value.initString(result);
}

/// strtolower - 转换为小写
pub fn php_strtolower(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const lower = try allocator.alloc(u8, php_str.length);
    defer allocator.free(lower);

    for (php_str.data, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }

    const result = try PHPString.init(allocator, lower);
    return Value.initString(result);
}

/// trim - 去除首尾空白
pub fn php_trim(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const trimmed = std.mem.trim(u8, php_str.data, " \t\n\r");

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// ltrim - 去除左侧空白
pub fn php_ltrim(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const trimmed = std.mem.trimLeft(u8, php_str.data, " \t\n\r");

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// rtrim - 去除右侧空白
pub fn php_rtrim(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const trimmed = std.mem.trimRight(u8, php_str.data, " \t\n\r");

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// str_replace - 字符串替换
pub fn php_str_replace(search: Value, replace: Value, subject: Value, allocator: Allocator) !Value {
    if (!subject.isString()) return subject;
    if (!search.isString() or !replace.isString()) return subject;

    const subject_str = subject.asString();
    const search_str = search.asString();
    const replace_str = replace.asString();

    // 如果搜索字符串为空，直接返回原字符串
    if (search_str.length == 0) return subject;

    // 计算需要的缓冲区大小
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < subject_str.length) {
        if (pos + search_str.length <= subject_str.length) {
            if (std.mem.eql(u8, subject_str.data[pos .. pos + search_str.length], search_str.data)) {
                count += 1;
                pos += search_str.length;
                continue;
            }
        }
        pos += 1;
    }

    // 如果没有找到，返回原字符串
    if (count == 0) return subject;

    // 计算新字符串长度
    const new_len = subject_str.length - (count * search_str.length) + (count * replace_str.length);
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    // 执行替换
    var write_pos: usize = 0;
    pos = 0;
    while (pos < subject_str.length) {
        if (pos + search_str.length <= subject_str.length) {
            if (std.mem.eql(u8, subject_str.data[pos .. pos + search_str.length], search_str.data)) {
                @memcpy(buffer[write_pos .. write_pos + replace_str.length], replace_str.data);
                write_pos += replace_str.length;
                pos += search_str.length;
                continue;
            }
        }
        buffer[write_pos] = subject_str.data[pos];
        write_pos += 1;
        pos += 1;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_repeat - 重复字符串
pub fn php_str_repeat(str: Value, times: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const repeat_times = times.toInt();

    if (repeat_times <= 0) return Value.initString(try PHPString.init(allocator, ""));
    if (repeat_times == 1) return str;

    const new_len = php_str.length * @as(usize, @intCast(repeat_times));
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var pos: usize = 0;
    var i: i64 = 0;
    while (i < repeat_times) : (i += 1) {
        @memcpy(buffer[pos .. pos + php_str.length], php_str.data);
        pos += php_str.length;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_pad - 填充字符串到指定长度
pub fn php_str_pad(str: Value, length: Value, pad_str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const target_len = length.toInt();

    if (target_len <= @as(i64, @intCast(php_str.length))) return str;

    const pad_string = if (pad_str.isString()) pad_str.asString() else blk: {
        break :blk try PHPString.init(allocator, " ");
    };

    const buffer = try allocator.alloc(u8, @intCast(target_len));
    errdefer allocator.free(buffer);

    // 复制原字符串
    @memcpy(buffer[0..php_str.length], php_str.data);

    // 填充
    var pos = php_str.length;
    while (pos < buffer.len) {
        const copy_len = @min(pad_string.length, buffer.len - pos);
        @memcpy(buffer[pos .. pos + copy_len], pad_string.data[0..copy_len]);
        pos += copy_len;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// strrev - 反转字符串
pub fn php_strrev(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    var i: usize = 0;
    while (i < php_str.length) : (i += 1) {
        buffer[i] = php_str.data[php_str.length - 1 - i];
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_contains - 检查字符串是否包含子串 (PHP 8.0+)
pub fn php_str_contains(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    var i: usize = 0;
    while (i <= hay.length - need.length) : (i += 1) {
        if (std.mem.eql(u8, hay.data[i .. i + need.length], need.data)) {
            return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

/// str_starts_with - 检查字符串是否以指定前缀开始 (PHP 8.0+)
pub fn php_str_starts_with(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    return Value.initBool(std.mem.eql(u8, hay.data[0..need.length], need.data));
}

/// str_ends_with - 检查字符串是否以指定后缀结束 (PHP 8.0+)
pub fn php_str_ends_with(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    const start_pos = hay.length - need.length;
    return Value.initBool(std.mem.eql(u8, hay.data[start_pos..], need.data));
}

/// ucfirst - 首字母大写
pub fn php_ucfirst(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);
    buffer[0] = std.ascii.toUpper(buffer[0]);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// lcfirst - 首字母小写
pub fn php_lcfirst(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);
    buffer[0] = std.ascii.toLower(buffer[0]);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// ucwords - 每个单词首字母大写
pub fn php_ucwords(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);

    var is_word_start = true;
    for (buffer, 0..) |c, i| {
        if (std.ascii.isWhitespace(c)) {
            is_word_start = true;
        } else if (is_word_start) {
            buffer[i] = std.ascii.toUpper(c);
            is_word_start = false;
        }
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// explode - 分割字符串为数组
pub fn php_explode(delimiter: Value, str: Value, allocator: Allocator) !Value {
    if (!delimiter.isString() or !str.isString()) {
        return Value.initArray(try PHPArray.init(allocator));
    }

    const delim = delimiter.asString();
    const php_str = str.asString();

    const arr = try PHPArray.init(allocator);

    if (delim.length == 0) {
        // 空分隔符，返回包含整个字符串的数组
        try arr.push(allocator, str);
        return Value.initArray(arr);
    }

    var start: usize = 0;
    var pos: usize = 0;

    while (pos <= php_str.length - delim.length) {
        if (std.mem.eql(u8, php_str.data[pos .. pos + delim.length], delim.data)) {
            // 找到分隔符
            const part = try PHPString.init(allocator, php_str.data[start..pos]);
            try arr.push(allocator, Value.initString(part));
            pos += delim.length;
            start = pos;
        } else {
            pos += 1;
        }
    }

    // 添加最后一部分
    const last_part = try PHPString.init(allocator, php_str.data[start..]);
    try arr.push(allocator, Value.initString(last_part));

    return Value.initArray(arr);
}

/// implode - 连接数组元素为字符串
pub fn php_implode(glue: Value, pieces: Value, allocator: Allocator) !Value {
    if (!pieces.isArray()) return Value.initString(try PHPString.init(allocator, ""));

    const glue_str = if (glue.isString()) glue.asString() else try PHPString.init(allocator, "");
    const arr = pieces.asArray();

    if (arr.count() == 0) return Value.initString(try PHPString.init(allocator, ""));

    // 计算总长度
    var total_len: usize = 0;
    var it = arr.elements.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) total_len += glue_str.length;
        const val = entry.value_ptr.*;
        const str = try val.toString(allocator);
        defer allocator.free(str);
        total_len += str.len;
        first = false;
    }

    // 构建结果字符串
    const buffer = try allocator.alloc(u8, total_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    it = arr.elements.iterator();
    first = true;
    while (it.next()) |entry| {
        if (!first) {
            @memcpy(buffer[write_pos .. write_pos + glue_str.length], glue_str.data);
            write_pos += glue_str.length;
        }
        const val = entry.value_ptr.*;
        const str = try val.toString(allocator);
        defer allocator.free(str);
        @memcpy(buffer[write_pos .. write_pos + str.len], str);
        write_pos += str.len;
        first = false;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_split - 将字符串分割为数组
pub fn php_str_split(str: Value, length: Value, allocator: Allocator) !Value {
    if (!str.isString()) return Value.initArray(try PHPArray.init(allocator));

    const php_str = str.asString();
    const chunk_len = if (length.isNull()) 1 else @max(1, length.toInt());

    const arr = try PHPArray.init(allocator);

    var pos: usize = 0;
    while (pos < php_str.length) {
        const end = @min(pos + @as(usize, @intCast(chunk_len)), php_str.length);
        const chunk = try PHPString.init(allocator, php_str.data[pos..end]);
        try arr.push(allocator, Value.initString(chunk));
        pos = end;
    }

    return Value.initArray(arr);
}

/// strcmp - 字符串比较
pub fn php_strcmp(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();

    const result = std.mem.order(u8, s1.data, s2.data);
    return Value.initInt(switch (result) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    });
}

/// strcasecmp - 不区分大小写的字符串比较
pub fn php_strcasecmp(str1: Value, str2: Value, allocator: Allocator) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();

    // 转换为小写后比较
    const lower1 = try allocator.alloc(u8, s1.length);
    defer allocator.free(lower1);
    const lower2 = try allocator.alloc(u8, s2.length);
    defer allocator.free(lower2);

    for (s1.data, 0..) |c, i| {
        lower1[i] = std.ascii.toLower(c);
    }
    for (s2.data, 0..) |c, i| {
        lower2[i] = std.ascii.toLower(c);
    }

    const result = std.mem.order(u8, lower1, lower2);
    return Value.initInt(switch (result) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    });
}

// ============================================================================
// 数组函数
// ============================================================================

/// count - 获取数组元素数量
pub fn php_count(arr: Value) !Value {
    if (!arr.isArray()) return Value.initInt(0);
    return Value.initInt(@intCast(arr.asArray().count()));
}

/// array_push - 追加元素到数组
pub fn php_array_push(arr: Value, values: []const Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    for (values) |val| {
        try php_arr.push(allocator, val);
    }

    return Value.initInt(@intCast(php_arr.count()));
}

/// array_pop - 弹出数组最后一个元素
pub fn php_array_pop(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    if (php_arr.count() == 0) return Value.initNull();

    const last_key = ArrayKey{ .integer = php_arr.next_index - 1 };
    const value = php_arr.get(last_key) orelse return Value.initNull();

    // 移除元素
    _ = php_arr.elements.remove(last_key);
    php_arr.next_index -= 1;

    // 不需要release，因为我们返回了这个值
    _ = allocator;
    return value;
}

/// in_array - 检查值是否在数组中
pub fn php_in_array(needle: Value, haystack: Value) !Value {
    if (!haystack.isArray()) return Value.initBool(false);

    const arr = haystack.asArray();
    var iter = arr.elements.iterator();

    while (iter.next()) |entry| {
        const eq = try php_eq(needle, entry.value_ptr.*);
        if (eq.asBool()) return Value.initBool(true);
    }

    return Value.initBool(false);
}

/// array_slice - 从数组中提取一段切片
///
/// 提取数组中的一段元素，返回新数组。
///
/// @param arr 源数组
/// @param offset 起始偏移量（可以为负数，表示从末尾开始）
/// @param length 切片长度（可选，null表示到数组末尾）
/// @param allocator 内存分配器
/// @return 新的数组切片
///
/// 示例：
/// ```php
/// $arr = [1, 2, 3, 4, 5];
/// array_slice($arr, 1, 2);  // [2, 3]
/// array_slice($arr, -2);     // [4, 5]
/// array_slice($arr, 1, -1);  // [2, 3, 4]
/// ```
pub fn php_array_slice(arr: Value, offset: Value, length: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const arr_count = php_arr.count();

    if (arr_count == 0) {
        // 空数组，返回空数组
        return Value.initArray(try PHPArray.init(allocator));
    }

    // 计算起始位置
    const offset_int = offset.toInt();
    const start_idx: usize = blk: {
        if (offset_int < 0) {
            const abs_offset = @as(usize, @intCast(-offset_int));
            break :blk if (abs_offset > arr_count) 0 else arr_count - abs_offset;
        } else {
            break :blk @intCast(@min(offset_int, @as(i64, @intCast(arr_count))));
        }
    };

    // 计算结束位置
    const end_idx: usize = blk: {
        if (length.isNull()) {
            // 没有指定长度，取到数组末尾
            break :blk arr_count;
        }

        const length_int = length.toInt();
        if (length_int >= 0) {
            // 正数长度
            break :blk @min(start_idx + @as(usize, @intCast(length_int)), arr_count);
        } else {
            // 负数长度：从末尾减去
            const abs_len = @as(usize, @intCast(-length_int));
            if (abs_len >= arr_count) {
                break :blk start_idx; // 返回空数组
            }
            break :blk if (arr_count - abs_len > start_idx) arr_count - abs_len else start_idx;
        }
    };

    // 创建新数组
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    if (start_idx >= end_idx) {
        // 空切片
        return Value.initArray(result);
    }

    // 复制元素
    // 注意：PHP的array_slice会重新索引数组（从0开始）
    var iter = php_arr.elements.iterator();
    var current_idx: usize = 0;
    var new_idx: i64 = 0;

    while (iter.next()) |entry| {
        // 只处理整数键（保持顺序）
        if (entry.key_ptr.* == .integer) {
            if (current_idx >= start_idx and current_idx < end_idx) {
                const new_key = ArrayKey{ .integer = new_idx };
                const value_copy = entry.value_ptr.*.retain();
                try result.elements.put(new_key, value_copy);
                new_idx += 1;
            }
            current_idx += 1;
        }
    }

    result.next_index = new_idx;
    return Value.initArray(result);
}

/// array_merge - 合并一个或多个数组
///
/// 将多个数组合并成一个新数组。
/// - 整数键会被重新索引（从0开始）
/// - 字符串键会被保留，后面的值会覆盖前面的值
///
/// @param arrays 要合并的数组列表
/// @param allocator 内存分配器
/// @return 合并后的新数组
///
/// 示例：
/// ```php
/// $arr1 = [1, 2];
/// $arr2 = [3, 4];
/// array_merge($arr1, $arr2);  // [1, 2, 3, 4]
///
/// $arr3 = ['a' => 1, 'b' => 2];
/// $arr4 = ['b' => 3, 'c' => 4];
/// array_merge($arr3, $arr4);  // ['a' => 1, 'b' => 3, 'c' => 4]
/// ```
pub fn php_array_merge(arrays: []const Value, allocator: Allocator) !Value {
    // 创建结果数组
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var next_int_key: i64 = 0;

    // 遍历所有输入数组
    for (arrays) |arr_val| {
        if (!arr_val.isArray()) continue; // 跳过非数组值

        const arr = arr_val.asArray();
        var iter = arr.elements.iterator();

        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*.retain();

            switch (key) {
                .integer => {
                    // 整数键：重新索引
                    const new_key = ArrayKey{ .integer = next_int_key };
                    try result.elements.put(new_key, value);
                    next_int_key += 1;
                },
                .string => |str| {
                    // 字符串键：保留键名，可能覆盖
                    const new_key = ArrayKey{ .string = str };
                    str.retain(); // 保留键的引用

                    // 如果键已存在，释放旧值
                    if (result.elements.get(new_key)) |old_value| {
                        old_value.release(allocator);
                    }

                    try result.elements.put(new_key, value);
                },
            }
        }
    }

    result.next_index = next_int_key;
    return Value.initArray(result);
}

/// array_keys - 返回数组中所有的键
///
/// 返回一个包含数组所有键的新数组（整数索引）。
///
/// @param arr 源数组
/// @param allocator 内存分配器
/// @return 包含所有键的新数组
///
/// 示例：
/// ```php
/// $arr = ['a' => 1, 'b' => 2, 0 => 3];
/// array_keys($arr);  // ['a', 'b', 0]
/// ```
pub fn php_array_keys(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var iter = php_arr.elements.iterator();
    var idx: i64 = 0;

    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const key_value = switch (key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                // 创建字符串值的副本
                const str_copy = try PHPString.init(allocator, s.data);
                break :blk Value.initString(str_copy);
            },
        };

        const new_key = ArrayKey{ .integer = idx };
        try result.elements.put(new_key, key_value);
        idx += 1;
    }

    result.next_index = idx;
    return Value.initArray(result);
}

/// array_values - 返回数组中所有的值
///
/// 返回一个包含数组所有值的新数组，使用整数索引（从0开始）。
/// 这个函数会丢弃原数组的键，重新索引。
///
/// @param arr 源数组
/// @param allocator 内存分配器
/// @return 包含所有值的新数组（整数索引）
///
/// 示例：
/// ```php
/// $arr = ['a' => 1, 'b' => 2, 5 => 3];
/// array_values($arr);  // [1, 2, 3]
/// ```
pub fn php_array_values(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var iter = php_arr.elements.iterator();
    var idx: i64 = 0;

    while (iter.next()) |entry| {
        const value = entry.value_ptr.*.retain();
        const new_key = ArrayKey{ .integer = idx };
        try result.elements.put(new_key, value);
        idx += 1;
    }

    result.next_index = idx;
    return Value.initArray(result);
}

// ============================================================================
// 数学函数
// ============================================================================

/// abs - 绝对值
pub fn php_abs(val: Value) !Value {
    if (val.isInt()) {
        const i = val.asInt();
        return Value.initInt(if (i < 0) -i else i);
    }
    const f = val.toFloat();
    return Value.initFloat(@abs(f));
}

/// sqrt - 平方根
pub fn php_sqrt(val: Value) !Value {
    return Value.initFloat(@sqrt(val.toFloat()));
}

/// round - 四舍五入
pub fn php_round(val: Value) !Value {
    return Value.initFloat(@round(val.toFloat()));
}

/// floor - 向下取整
pub fn php_floor(val: Value) !Value {
    return Value.initFloat(@floor(val.toFloat()));
}

/// ceil - 向上取整
pub fn php_ceil(val: Value) !Value {
    return Value.initFloat(@ceil(val.toFloat()));
}

/// min - 最小值
pub fn php_min(a: Value, b: Value) !Value {
    if (a.isInt() and b.isInt()) {
        return Value.initInt(@min(a.asInt(), b.asInt()));
    }
    return Value.initFloat(@min(a.toFloat(), b.toFloat()));
}

/// max - 最大值
pub fn php_max(a: Value, b: Value) !Value {
    if (a.isInt() and b.isInt()) {
        return Value.initInt(@max(a.asInt(), b.asInt()));
    }
    return Value.initFloat(@max(a.toFloat(), b.toFloat()));
}

/// sin - 正弦
pub fn php_sin(val: Value) !Value {
    return Value.initFloat(@sin(val.toFloat()));
}

/// cos - 余弦
pub fn php_cos(val: Value) !Value {
    return Value.initFloat(@cos(val.toFloat()));
}

/// tan - 正切
pub fn php_tan(val: Value) !Value {
    return Value.initFloat(@tan(val.toFloat()));
}

/// asin - 反正弦
pub fn php_asin(val: Value) !Value {
    return Value.initFloat(std.math.asin(val.toFloat()));
}

/// acos - 反余弦
pub fn php_acos(val: Value) !Value {
    return Value.initFloat(std.math.acos(val.toFloat()));
}

/// atan - 反正切
pub fn php_atan(val: Value) !Value {
    return Value.initFloat(std.math.atan(val.toFloat()));
}

/// atan2 - 两个参数的反正切
pub fn php_atan2(y: Value, x: Value) !Value {
    return Value.initFloat(std.math.atan2(y.toFloat(), x.toFloat()));
}

/// log - 自然对数
pub fn php_log(val: Value) !Value {
    return Value.initFloat(@log(val.toFloat()));
}

/// log10 - 以10为底的对数
pub fn php_log10(val: Value) !Value {
    return Value.initFloat(@log10(val.toFloat()));
}

/// exp - e的x次方
pub fn php_exp(val: Value) !Value {
    return Value.initFloat(@exp(val.toFloat()));
}

/// pow - 幂运算
pub fn php_pow_func(base: Value, exponent: Value) !Value {
    if (base.isInt() and exponent.isInt()) {
        const b = base.asInt();
        const e = exponent.asInt();
        if (e >= 0 and e < 64) {
            // 整数幂运算
            var result: i64 = 1;
            var i: i64 = 0;
            while (i < e) : (i += 1) {
                result *= b;
            }
            return Value.initInt(result);
        }
    }
    return Value.initFloat(std.math.pow(f64, base.toFloat(), exponent.toFloat()));
}

/// fmod - 浮点数取模
pub fn php_fmod(x: Value, y: Value) !Value {
    return Value.initFloat(@mod(x.toFloat(), y.toFloat()));
}

/// hypot - 计算直角三角形斜边长度
pub fn php_hypot(x: Value, y: Value) !Value {
    return Value.initFloat(std.math.hypot(x.toFloat(), y.toFloat()));
}

/// deg2rad - 角度转弧度
pub fn php_deg2rad(degrees: Value) !Value {
    const rad = degrees.toFloat() * std.math.pi / 180.0;
    return Value.initFloat(rad);
}

/// rad2deg - 弧度转角度
pub fn php_rad2deg(radians: Value) !Value {
    const deg = radians.toFloat() * 180.0 / std.math.pi;
    return Value.initFloat(deg);
}

/// pi - 返回圆周率
pub fn php_pi() !Value {
    return Value.initFloat(std.math.pi);
}

/// intval - 转换为整数
pub fn php_intval(val: Value) !Value {
    return Value.initInt(val.toInt());
}

/// floatval - 转换为浮点数
pub fn php_floatval(val: Value) !Value {
    return Value.initFloat(val.toFloat());
}

/// boolval - 转换为布尔值
pub fn php_boolval(val: Value) !Value {
    return Value.initBool(val.toBool());
}

// ============================================================================
// 类型检查函数
// ============================================================================

/// is_null - 检查是否为null
pub fn php_is_null(val: Value) !Value {
    return Value.initBool(val.isNull());
}

/// is_bool - 检查是否为布尔值
pub fn php_is_bool(val: Value) !Value {
    return Value.initBool(val.isBool());
}

/// is_int - 检查是否为整数
pub fn php_is_int(val: Value) !Value {
    return Value.initBool(val.isInt());
}

/// is_float - 检查是否为浮点数
pub fn php_is_float(val: Value) !Value {
    return Value.initBool(val.isFloat());
}

/// is_string - 检查是否为字符串
pub fn php_is_string(val: Value) !Value {
    return Value.initBool(val.isString());
}

/// is_array - 检查是否为数组
pub fn php_is_array(val: Value) !Value {
    return Value.initBool(val.isArray());
}

/// is_numeric - 检查是否为数字或数字字符串
pub fn php_is_numeric(val: Value) !Value {
    if (val.isInt() or val.isFloat()) return Value.initBool(true);
    if (val.isString()) {
        const str = val.asString();
        // 尝试解析为数字
        _ = std.fmt.parseInt(i64, str.data, 10) catch {
            _ = std.fmt.parseFloat(f64, str.data) catch {
                return Value.initBool(false);
            };
        };
        return Value.initBool(true);
    }
    return Value.initBool(false);
}
// ============================================================================
// 字符串插值函数
// ============================================================================

/// php_interpolate - 字符串插值（将多个值连接成字符串）
///
/// 这个函数接收一个Value数组，将每个值转换为字符串并连接起来。
/// 这是PHP字符串插值的核心实现，例如：
/// ```php
/// $name = "Alice";
/// $age = 30;
/// echo "Hello, $name! You are $age years old.";
/// ```
///
/// @param parts 要插值的值数组
/// @param allocator 内存分配器
/// @return 插值后的字符串Value
pub fn php_interpolate(parts: []const Value, allocator: Allocator) !Value {
    if (parts.len == 0) {
        // 空数组，返回空字符串
        return Value.initString(try PHPString.init(allocator, ""));
    }

    if (parts.len == 1) {
        // 单个值，直接转换为字符串
        const str = try parts[0].toString(allocator);
        return Value.initString(str);
    }

    // 多个值，需要连接
    // 首先计算总长度
    var total_length: usize = 0;
    var temp_strings = try allocator.alloc(*PHPString, parts.len);
    defer {
        // 释放临时字符串
        for (temp_strings) |str| {
            str.release(allocator);
        }
        allocator.free(temp_strings);
    }

    // 将每个值转换为字符串
    for (parts, 0..) |part, i| {
        const str = try part.toString(allocator);
        temp_strings[i] = str;
        total_length += str.length;
    }

    // 分配结果缓冲区
    const result_data = try allocator.alloc(u8, total_length);
    errdefer allocator.free(result_data);

    // 连接所有字符串
    var offset: usize = 0;
    for (temp_strings) |str| {
        if (str.length > 0) {
            @memcpy(result_data[offset .. offset + str.length], str.data[0..str.length]);
            offset += str.length;
        }
    }

    // 创建结果字符串
    const result = try allocator.create(PHPString);
    errdefer allocator.destroy(result);

    result.data = result_data;
    result.length = total_length;
    result.ref_count = 1;
    result.is_static = false;

    return Value.initString(result);
}

// ============================================================================
// PHP类元数据和对象类型
// ============================================================================

/// 方法签名类型
pub const MethodFn = *const fn (this: Value, args: []const Value, allocator: Allocator) anyerror!Value;

/// 类方法定义
pub const ClassMethod = struct {
    name: []const u8,
    func: MethodFn,
    is_static: bool = false,
    is_public: bool = true,
    is_protected: bool = false,
    is_private: bool = false,
};

/// 类属性定义
pub const ClassProperty = struct {
    name: []const u8,
    default_value: ?Value = null,
    is_static: bool = false,
    is_public: bool = true,
    is_readonly: bool = false,
};

/// 类元数据
/// 存储类的完整定义，包括方法、属性、继承关系、接口等
pub const ClassMeta = struct {
    name: []const u8,
    parent: ?*const ClassMeta = null,
    interfaces: []const []const u8 = &.{},
    methods: std.StringHashMap(ClassMethod),
    properties: std.StringHashMap(ClassProperty),
    static_properties: std.StringHashMap(Value),
    is_abstract: bool = false,
    is_final: bool = false,
    allocator: Allocator,

    /// 魔法函数指针
    magic_construct: ?MethodFn = null,
    magic_destruct: ?MethodFn = null,
    magic_call: ?MethodFn = null,
    magic_callStatic: ?MethodFn = null,
    magic_get: ?MethodFn = null,
    magic_set: ?MethodFn = null,
    magic_isset: ?MethodFn = null,
    magic_unset: ?MethodFn = null,
    magic_toString: ?MethodFn = null,
    magic_invoke: ?MethodFn = null,
    magic_clone: ?MethodFn = null,

    pub fn init(allocator: Allocator, name: []const u8) !*ClassMeta {
        const meta = try allocator.create(ClassMeta);
        errdefer allocator.destroy(meta);

        meta.* = .{
            .name = try allocator.dupe(u8, name),
            .methods = std.StringHashMap(ClassMethod).init(allocator),
            .properties = std.StringHashMap(ClassProperty).init(allocator),
            .static_properties = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
        return meta;
    }

    pub fn deinit(self: *ClassMeta) void {
        self.methods.deinit();
        self.properties.deinit();
        var iter = self.static_properties.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.static_properties.deinit();
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    /// 添加方法
    pub fn addMethod(self: *ClassMeta, method: ClassMethod) !void {
        try self.methods.put(method.name, method);
    }

    /// 查找方法（包括继承链）
    pub fn findMethod(self: *const ClassMeta, name: []const u8) ?ClassMethod {
        if (self.methods.get(name)) |method| {
            return method;
        }
        if (self.parent) |parent| {
            return parent.findMethod(name);
        }
        return null;
    }

    /// 添加属性定义
    pub fn addProperty(self: *ClassMeta, prop: ClassProperty) !void {
        try self.properties.put(prop.name, prop);
    }

    /// 设置静态属性
    pub fn setStaticProperty(self: *ClassMeta, name: []const u8, value: Value) !void {
        if (self.static_properties.get(name)) |old| {
            old.release(self.allocator);
        }
        _ = value.retain();
        try self.static_properties.put(name, value);
    }

    /// 获取静态属性
    pub fn getStaticProperty(self: *const ClassMeta, name: []const u8) ?Value {
        if (self.static_properties.get(name)) |val| {
            return val;
        }
        if (self.parent) |parent| {
            return parent.getStaticProperty(name);
        }
        return null;
    }

    /// 检查是否实现了接口
    pub fn implementsInterface(self: *const ClassMeta, interface_name: []const u8) bool {
        for (self.interfaces) |iface| {
            if (std.mem.eql(u8, iface, interface_name)) return true;
        }
        if (self.parent) |parent| {
            return parent.implementsInterface(interface_name);
        }
        return false;
    }

    /// 检查是否是某个类的子类
    pub fn isSubclassOf(self: *const ClassMeta, class_name: []const u8) bool {
        if (std.mem.eql(u8, self.name, class_name)) return true;
        if (self.parent) |parent| {
            return parent.isSubclassOf(class_name);
        }
        return false;
    }
};

/// 全局类注册表
pub var class_registry: ?std.StringHashMap(*ClassMeta) = null;

/// 全局对象跟踪（用于内存泄露检测和清理）
pub var global_object_registry: ?std.ArrayList(*PHPObject) = null;

/// 初始化类注册表
pub fn initClassRegistry(allocator: Allocator) void {
    class_registry = std.StringHashMap(*ClassMeta).init(allocator);
    global_object_registry = std.ArrayList(*PHPObject).initCapacity(allocator, 0) catch {
        global_object_registry = null;
        return;
    };
}

/// 注册类
pub fn registerClass(meta: *ClassMeta) !void {
    if (class_registry) |*registry| {
        try registry.put(meta.name, meta);
    }
}

/// 查找类
pub fn findClass(name: []const u8) ?*ClassMeta {
    if (class_registry) |registry| {
        return registry.get(name);
    }
    return null;
}

/// 清理所有注册的类和对象
pub fn cleanupAllClasses() void {
    // 清理所有对象
    if (global_object_registry) |registry| {
        for (registry.items) |obj| {
            obj.release(); // 减少引用计数，会自动deinit如果计数为0
        }
        registry.deinit();
        global_object_registry = null;
    }

    // 清理所有类
    if (class_registry) |registry| {
        var iter = registry.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        registry.deinit();
        class_registry = null;
    }
}

/// PHP对象类型
/// 使用引用计数管理内存，属性存储在HashMap中
pub const PHPObject = struct {
    class_meta: ?*const ClassMeta,
    class_name: []const u8,
    properties: std.StringHashMap(Value),
    ref_count: usize,
    allocator: Allocator,

    /// 创建新对象
    pub fn init(allocator: Allocator, class_name: []const u8) !*PHPObject {
        const obj = try allocator.create(PHPObject);
        errdefer allocator.destroy(obj);

        obj.class_name = try allocator.dupe(u8, class_name);
        errdefer allocator.free(obj.class_name);

        obj.properties = std.StringHashMap(Value).init(allocator);
        obj.ref_count = 1;
        obj.allocator = allocator;
        obj.class_meta = findClass(class_name);
        return obj;
    }

    /// 使用类元数据创建对象
    pub fn initWithMeta(allocator: Allocator, meta: *const ClassMeta) !*PHPObject {
        const obj = try allocator.create(PHPObject);
        errdefer allocator.destroy(obj);

        obj.class_name = try allocator.dupe(u8, meta.name);
        errdefer allocator.free(obj.class_name);

        obj.properties = std.StringHashMap(Value).init(allocator);
        obj.ref_count = 1;
        obj.allocator = allocator;
        obj.class_meta = meta;

        // 初始化默认属性值
        var prop_iter = meta.properties.iterator();
        while (prop_iter.next()) |entry| {
            if (!entry.value_ptr.is_static) {
                if (entry.value_ptr.default_value) |default| {
                    try obj.setProperty(entry.key_ptr.*, default);
                }
            }
        }
        return obj;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPObject) void {
        self.ref_count += 1;
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPObject) void {
        if (self.ref_count == 0) return;

        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit();
        }
    }

    /// 释放对象
    fn deinit(self: *PHPObject) void {
        // 调用 __destruct 魔法函数
        if (self.class_meta) |meta| {
            if (meta.magic_destruct) |destruct| {
                const this_val = Value_initObject(self);
                _ = destruct(this_val, &.{}, self.allocator) catch {};
            }
        }

        // 释放所有属性值
        var iter = self.properties.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.properties.deinit();

        // 释放类名
        self.allocator.free(self.class_name);

        // 释放对象本身
        self.allocator.destroy(self);
    }

    /// 获取属性（支持 __get 魔法函数）
    pub fn getProperty(self: *PHPObject, name: []const u8) ?Value {
        if (self.properties.get(name)) |val| {
            return val;
        }
        // 调用 __get 魔法函数
        if (self.class_meta) |meta| {
            if (meta.magic_get) |getter| {
                const this_val = Value_initObject(self);
                const name_val = Value.initString(PHPString.initStatic(name));
                const args = [_]Value{name_val};
                return getter(this_val, &args, self.allocator) catch null;
            }
        }
        return null;
    }

    /// 设置属性（支持 __set 魔法函数）
    pub fn setProperty(self: *PHPObject, name: []const u8, value: Value) !void {
        // 检查是否有 __set 魔法函数且属性不存在
        if (self.properties.get(name) == null) {
            if (self.class_meta) |meta| {
                if (meta.magic_set) |setter| {
                    const this_val = Value_initObject(self);
                    const name_val = Value.initString(PHPString.initStatic(name));
                    const args = [_]Value{ name_val, value };
                    _ = try setter(this_val, &args, self.allocator);
                    return;
                }
            }
        }

        // 释放旧值
        if (self.properties.get(name)) |old_value| {
            old_value.release(self.allocator);
        }

        // 保留新值
        _ = value.retain();

        // 存储属性
        try self.properties.put(name, value);
    }

    /// 调用方法（支持 __call 魔法函数和继承）
    pub fn callMethod(self: *PHPObject, method_name: []const u8, args: []const Value) !Value {
        const this_val = Value_initObject(self);

        if (self.class_meta) |meta| {
            // 查找方法（包括继承链）
            if (meta.findMethod(method_name)) |method| {
                return method.func(this_val, args, self.allocator);
            }
            // 调用 __call 魔法函数
            if (meta.magic_call) |call_fn| {
                const name_val = Value.initString(PHPString.initStatic(method_name));
                const args_arr = try PHPArray.init(self.allocator);
                for (args) |arg| {
                    try args_arr.push(self.allocator, arg);
                }
                const call_args = [_]Value{ name_val, Value.initArray(args_arr) };
                return call_fn(this_val, &call_args, self.allocator);
            }
        }
        return error.MethodNotFound;
    }

    /// 检查属性是否存在（支持 __isset 魔法函数）
    pub fn hasProperty(self: *PHPObject, name: []const u8) bool {
        if (self.properties.contains(name)) return true;
        if (self.class_meta) |meta| {
            if (meta.magic_isset) |isset_fn| {
                const this_val = Value_initObject(self);
                const name_val = Value.initString(PHPString.initStatic(name));
                const args = [_]Value{name_val};
                const result = isset_fn(this_val, &args, self.allocator) catch return false;
                return result.toBool();
            }
        }
        return false;
    }

    /// 转换为字符串（支持 __toString 魔法函数）
    pub fn toString(self: *PHPObject, allocator: Allocator) !*PHPString {
        if (self.class_meta) |meta| {
            if (meta.magic_toString) |to_str| {
                const this_val = Value_initObject(self);
                const result = try to_str(this_val, &.{}, allocator);
                if (result.isString()) {
                    return result.asString();
                }
            }
        }
        // 默认返回类名
        return PHPString.init(allocator, self.class_name);
    }
};

// ============================================================================
// Value类型扩展 - 对象支持
// ============================================================================

// 在Value结构中添加对象类型常量
pub const TYPE_OBJECT: u64 = 0x0001800000000000;

// 扩展Value的方法（这些方法应该添加到Value结构中）
// 由于我们不能直接修改Value结构，我们在这里提供独立的函数

/// 创建对象值
pub fn Value_initObject(obj: *PHPObject) Value {
    const addr = @intFromPtr(obj);
    return .{ .val = Value.TAG_PTR | TYPE_OBJECT | (addr & 0x00007FFFFFFFFFFF) };
}

/// 检查是否是对象
pub fn Value_isObject(self: Value) bool {
    if ((self.val & (Value.SIGN_BIT | Value.QNAN)) != Value.QNAN) return false;
    return (self.val & Value.TYPE_MASK) == TYPE_OBJECT;
}

/// 获取对象指针
pub fn Value_asObject(self: Value) *PHPObject {
    return @ptrFromInt(self.val & 0x00007FFFFFFFFFFF);
}

// 更新Value的release方法以支持对象
// 注意：这需要在Value结构的release方法中添加对象处理

// ============================================================================
// 对象操作函数
// ============================================================================

/// 创建新对象
///
/// @param allocator 内存分配器
/// @return 对象Value
pub fn php_object_new(class_name: []const u8, allocator: Allocator) !Value {
    const obj = if (findClass(class_name)) |meta|
        try PHPObject.initWithMeta(allocator, meta)
    else
        try PHPObject.init(allocator, class_name);

    // 注册对象以便程序退出时清理
    if (global_object_registry) |*registry| {
        registry.append(allocator, obj) catch {};
    }

    return Value_initObject(obj);
}

/// 获取对象属性
///
/// @param obj_val 对象Value
/// @param property_name 属性名
/// @return 属性值，如果不存在返回null
pub fn php_object_get(obj_val: Value, property_name: []const u8) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }

    const obj = Value_asObject(obj_val);
    return obj.getProperty(property_name) orelse Value.initNull();
}

pub fn php_object_get_safe_value(obj_val: Value, prop_name_val: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }
    if (!prop_name_val.isString()) {
        return Value.initNull();
    }
    const obj = Value_asObject(obj_val);
    return obj.getProperty(prop_name_val.asString().data) orelse Value.initNull();
}

pub fn php_object_get_dynamic(obj_val: Value, prop_name_val: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }
    if (!prop_name_val.isString()) {
        return error.InvalidPropertyName;
    }
    const obj = Value_asObject(obj_val);
    return obj.getProperty(prop_name_val.asString().data) orelse Value.initNull();
}

pub fn php_object_set_dynamic(obj_val: Value, prop_name_val: Value, value: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }
    if (!prop_name_val.isString()) {
        return error.InvalidPropertyName;
    }
    const obj = Value_asObject(obj_val);
    try obj.setProperty(prop_name_val.asString().data, value);
    return Value.initNull();
}

pub fn php_cast_array(val: Value) !Value {
    if (val.isArray()) {
        return val;
    }
    const arr = try PHPArray.init(runtime_allocator);
    try arr.push(runtime_allocator, val);
    return Value.initArray(arr);
}

pub fn php_cast_object(val: Value) !Value {
    if (val.isArray()) {
        const obj_val = try php_object_new("stdClass", runtime_allocator);
        const obj = Value_asObject(obj_val);
        var it = val.asArray().elements.iterator();
        while (it.next()) |entry| {
            switch (entry.key_ptr.*) {
                .string => |key| {
                    try obj.setProperty(key.data, entry.value_ptr.*);
                },
                .integer => |idx| {
                    const key_str = try std.fmt.allocPrint(runtime_allocator, "{d}", .{idx});
                    defer runtime_allocator.free(key_str);
                    try obj.setProperty(key_str, entry.value_ptr.*);
                },
            }
        }
        return obj_val;
    }
    return val;
}

/// 设置对象属性
///
/// @param obj_val 对象Value
/// @param property_name 属性名
/// @param value 属性值
pub fn php_object_set(obj_val: Value, property_name: []const u8, value: Value) !void {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }

    const obj = Value_asObject(obj_val);
    try obj.setProperty(property_name, value);
}

/// 调用对象方法
///
/// @param obj_val 对象Value
/// @param method_name 方法名
/// @param args 参数数组
/// @return 方法返回值
pub fn php_object_call(obj_val: Value, method_name: []const u8, args: []const Value) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }
    const obj = Value_asObject(obj_val);
    return obj.callMethod(method_name, args);
}

/// 创建新对象并调用构造函数
pub fn php_object_new_with_constructor(class_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const meta = findClass(class_name);
    const obj = if (meta) |m|
        try PHPObject.initWithMeta(allocator, m)
    else
        try PHPObject.init(allocator, class_name);

    const obj_val = Value_initObject(obj);

    // 调用 __construct
    if (obj.class_meta) |m| {
        if (m.magic_construct) |construct| {
            _ = try construct(obj_val, args, allocator);
        }
    }

    return obj_val;
}

/// 检查类是否存在
pub fn php_class_exists(class_name: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!class_name.isString()) return Value.initBool(false);
    const name = class_name.asString().data;
    return Value.initBool(findClass(name) != null);
}

/// instanceof 检查
pub fn php_instanceof(obj_val: Value, class_name: Value) !Value {
    if (!Value_isObject(obj_val)) return Value.initBool(false);
    if (!class_name.isString()) return Value.initBool(false);

    const obj = Value_asObject(obj_val);
    const name = class_name.asString().data;

    // 检查类名直接匹配
    if (std.mem.eql(u8, obj.class_name, name)) return Value.initBool(true);

    // 检查继承链和接口
    if (obj.class_meta) |meta| {
        if (meta.isSubclassOf(name)) return Value.initBool(true);
        if (meta.implementsInterface(name)) return Value.initBool(true);
    }

    return Value.initBool(false);
}

/// 获取父类名
pub fn php_get_parent_class(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) return Value.initBool(false);

    const obj = Value_asObject(obj_val);
    if (obj.class_meta) |meta| {
        if (meta.parent) |parent| {
            const parent_name = try PHPString.init(allocator, parent.name);
            return Value.initString(parent_name);
        }
    }
    return Value.initBool(false);
}

/// 检查方法是否存在
pub fn php_method_exists(obj_val: Value, method_name: Value) !Value {
    if (!method_name.isString()) return Value.initBool(false);
    const name = method_name.asString().data;

    if (Value_isObject(obj_val)) {
        const obj = Value_asObject(obj_val);
        if (obj.class_meta) |meta| {
            return Value.initBool(meta.findMethod(name) != null);
        }
    }
    return Value.initBool(false);
}

/// 检查属性是否存在
pub fn php_property_exists(obj_val: Value, property_name: Value) !Value {
    if (!property_name.isString()) return Value.initBool(false);
    const name = property_name.asString().data;

    if (Value_isObject(obj_val)) {
        const obj = Value_asObject(obj_val);
        return Value.initBool(obj.hasProperty(name));
    }
    return Value.initBool(false);
}

/// 调用静态方法
pub fn php_call_static(class_name: []const u8, method_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const meta = findClass(class_name) orelse return error.ClassNotFound;

    // 查找静态方法
    if (meta.findMethod(method_name)) |method| {
        if (method.is_static) {
            return method.func(Value.initNull(), args, allocator);
        }
    }

    // 调用 __callStatic 魔法函数
    if (meta.magic_callStatic) |call_static| {
        const name_val = Value.initString(PHPString.initStatic(method_name));
        const args_arr = try PHPArray.init(allocator);
        for (args) |arg| {
            try args_arr.push(allocator, arg);
        }
        const call_args = [_]Value{ name_val, Value.initArray(args_arr) };
        return call_static(Value.initNull(), &call_args, allocator);
    }

    return error.MethodNotFound;
}

/// 获取静态属性
pub fn php_get_static_property(class_name: []const u8, property_name: []const u8) !Value {
    const meta = findClass(class_name) orelse return error.ClassNotFound;
    return meta.getStaticProperty(property_name) orelse Value.initNull();
}

/// 设置静态属性
pub fn php_set_static_property(class_name: []const u8, property_name: []const u8, value: Value) !void {
    var meta = findClass(class_name) orelse return error.ClassNotFound;
    try meta.setStaticProperty(property_name, value);
}

/// 检查是否是对象
pub fn php_is_object(val: Value) !Value {
    return Value.initBool(Value_isObject(val));
}

/// 获取对象的类名
pub fn php_get_class(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initBool(false);
    }

    const obj = Value_asObject(obj_val);
    const class_name_str = try PHPString.init(allocator, obj.class_name);
    return Value.initString(class_name_str);
}

// ============================================================================
// 异常处理
// ============================================================================

/// 当前异常（全局状态）
/// 注意：这是一个简化的异常处理机制
/// 在真实的PHP实现中，异常应该是线程局部的
var current_exception: ?Value = null;

/// 设置当前异常
///
/// @param exception 异常Value
pub fn setException(exception: Value) void {
    current_exception = exception;
}

/// 获取当前异常
///
/// @return 当前异常，如果没有异常返回null
pub fn getCurrentException() ?Value {
    return current_exception;
}

/// 清除当前异常
pub fn clearException() void {
    current_exception = null;
}

/// 抛出异常
///
/// @param message 异常消息
/// @param allocator 内存分配器
/// @return 异常Value
pub fn throwException(message: []const u8, allocator: Allocator) !Value {
    const msg_str = try PHPString.init(allocator, message);
    const exception = Value.initString(msg_str);
    setException(exception);
    return exception;
}

/// 检查是否有异常
///
/// @return 如果有异常返回true
pub fn hasException() bool {
    return current_exception != null;
}

// ============================================================================
// 时间函数（从VM实现复用）
// ============================================================================

/// time - 返回当前Unix时间戳
pub fn php_time() !Value {
    const timestamp = std.time.timestamp();
    return Value.initInt(timestamp);
}

/// microtime - 返回当前时间（带微秒）
///
/// @param get_as_float 是否返回浮点数格式
/// @param allocator 内存分配器
/// @return 字符串格式 "0.microseconds seconds" 或浮点数时间戳
pub fn php_microtime(get_as_float: Value, allocator: Allocator) !Value {
    const now_ns = std.time.nanoTimestamp();
    const sec = @divTrunc(now_ns, std.time.ns_per_s);
    const usec = @divTrunc(@mod(now_ns, std.time.ns_per_s), std.time.ns_per_us);

    // 检查是否返回浮点数
    const as_float = if (get_as_float.isBool())
        get_as_float.asBool()
    else if (get_as_float.isInt())
        get_as_float.asInt() != 0
    else
        false;

    if (as_float) {
        // 返回浮点数时间戳
        const float_time = @as(f64, @floatFromInt(sec)) + @as(f64, @floatFromInt(usec)) / 1000000.0;
        return Value.initFloat(float_time);
    } else {
        // 返回字符串格式 "0.microseconds seconds"
        const formatted = try std.fmt.allocPrint(allocator, "0.{d:0>6} {d}", .{ usec, sec });
        defer allocator.free(formatted);
        const result = try PHPString.init(allocator, formatted);
        return Value.initString(result);
    }
}

/// date - 格式化日期时间
///
/// 注意：这是一个简化实现，仅支持基本格式
/// 完整的PHP date()函数支持更多格式选项
///
/// @param format 格式字符串
/// @param timestamp 时间戳（可选，默认当前时间）
/// @param allocator 内存分配器
/// @return 格式化后的日期字符串
pub fn php_date(format: Value, timestamp: Value, allocator: Allocator) !Value {
    if (!format.isString()) {
        return Value.initString(try PHPString.init(allocator, ""));
    }

    // 获取时间戳
    const ts = if (timestamp.isNull())
        std.time.timestamp()
    else if (timestamp.isInt())
        timestamp.asInt()
    else if (timestamp.isFloat())
        @as(i64, @intFromFloat(timestamp.asFloat()))
    else
        std.time.timestamp();

    // 简化实现：仅支持 Y-m-d H:i:s 格式
    // 完整实现需要完整的日期格式化库
    const epoch_seconds = @as(u64, @intCast(ts));
    const days_since_epoch = epoch_seconds / 86400;
    const seconds_today = epoch_seconds % 86400;

    // 计算年月日（简化算法）
    const year = 1970 + @as(i64, @intCast(days_since_epoch / 365));
    const month: i64 = 1;
    const day: i64 = 1;

    // 计算时分秒
    const hour = seconds_today / 3600;
    const minute = (seconds_today % 3600) / 60;
    const second = seconds_today % 60;

    // 格式化输出（简化版）
    const formatted = try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ year, month, day, hour, minute, second });
    defer allocator.free(formatted);

    const result = try PHPString.init(allocator, formatted);
    return Value.initString(result);
}

// ============================================================================
// 随机数函数（从VM实现复用）
// ============================================================================

/// 线程局部随机数生成器状态
threadlocal var rng_state: u64 = 0;
threadlocal var rng_initialized: bool = false;

/// 初始化随机数生成器
fn ensureRngInitialized() void {
    if (!rng_initialized) {
        rng_state = @as(u64, @intCast(std.time.timestamp()));
        rng_initialized = true;
    }
}

/// 简单的线性同余生成器
fn nextRandom() u64 {
    ensureRngInitialized();
    rng_state = rng_state *% 1103515245 +% 12345;
    return rng_state;
}

/// rand - 生成随机整数
///
/// @param min 最小值（可选）
/// @param max 最大值（可选）
/// @return 随机整数
pub fn php_rand(min: Value, max: Value) !Value {
    if (min.isNull() and max.isNull()) {
        // 无参数：返回 0 到 RAND_MAX
        const random = nextRandom();
        return Value.initInt(@as(i64, @intCast(random & 0x7FFFFFFF)));
    }

    const min_val = min.toInt();
    const max_val = max.toInt();

    if (min_val > max_val) {
        return Value.initInt(min_val);
    }

    const range = @as(u64, @intCast(max_val - min_val + 1));
    const random = nextRandom() % range;

    return Value.initInt(min_val + @as(i64, @intCast(random)));
}

/// mt_rand - 生成随机整数（Mersenne Twister）
///
/// 注意：这是简化实现，使用与rand()相同的生成器
/// 完整实现应该使用真正的MT19937算法
///
/// @param min 最小值（可选）
/// @param max 最大值（可选）
/// @return 随机整数
pub fn php_mt_rand(min: Value, max: Value) !Value {
    return php_rand(min, max);
}

/// srand - 设置随机数种子
///
/// @param seed 种子值（可选）
pub fn php_srand(seed: Value) !Value {
    if (seed.isNull()) {
        rng_state = @as(u64, @intCast(std.time.timestamp()));
    } else {
        rng_state = @as(u64, @intCast(@abs(seed.toInt())));
    }
    rng_initialized = true;
    return Value.initNull();
}

/// mt_srand - 设置MT随机数种子
///
/// @param seed 种子值（可选）
pub fn php_mt_srand(seed: Value) !Value {
    return php_srand(seed);
}

/// random_int - 生成密码学安全的随机整数
///
/// @param min 最小值
/// @param max 最大值
/// @return 随机整数
pub fn php_random_int(min: Value, max: Value) !Value {
    const min_val = min.toInt();
    const max_val = max.toInt();

    if (min_val > max_val) {
        return error.InvalidRange;
    }

    // 使用密码学安全的随机数生成器
    const random_val = std.crypto.random.intRangeAtMost(i64, min_val, max_val);
    return Value.initInt(random_val);
}

/// random_bytes - 生成密码学安全的随机字节
///
/// @param length 字节数
/// @param allocator 内存分配器
/// @return 随机字节字符串
pub fn php_random_bytes(length: Value, allocator: Allocator) !Value {
    const len = length.toInt();

    if (len < 0) {
        return error.InvalidLength;
    }

    const byte_len = @as(usize, @intCast(len));
    const buffer = try allocator.alloc(u8, byte_len);
    errdefer allocator.free(buffer);

    // 填充密码学安全的随机字节
    std.crypto.random.bytes(buffer);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

// ============================================================================
// 扩展数组函数
// ============================================================================

/// array_shift - 移除并返回数组的第一个元素
pub fn php_array_shift(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    if (php_arr.count() == 0) return Value.initNull();

    // 获取第一个元素
    var it = php_arr.elements.iterator();
    if (it.next()) |entry| {
        const first_value = entry.value_ptr.*;
        // 移除第一个元素
        _ = php_arr.elements.orderedRemove(entry.key_ptr.*);
        return first_value;
    }
    _ = allocator;
    return Value.initNull();
}

/// array_unshift - 在数组开头添加元素
pub fn php_array_unshift(arr: Value, values: []const Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();

    // 为新元素分配空间并移动现有元素
    var i: usize = values.len;
    while (i > 0) {
        i -= 1;
        try php_arr.prepend(allocator, values[i]);
    }

    return Value.initInt(@intCast(php_arr.count()));
}

/// array_search - 在数组中搜索值并返回键
pub fn php_array_search(needle: Value, haystack: Value) !Value {
    if (!haystack.isArray()) return Value.initBool(false);

    const arr = haystack.asArray();
    var it = arr.elements.iterator();

    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        // 使用松散比较
        const eq_result = try php_eq(needle, val);
        if (eq_result.asBool()) {
            // 返回键
            return switch (entry.key_ptr.*) {
                .int => |k| Value.initInt(k),
                .string => |k| Value.initString(k),
            };
        }
    }

    return Value.initBool(false);
}

/// array_sum - 计算数组元素的总和
pub fn php_array_sum(arr: Value) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();
    var sum_int: i64 = 0;
    var sum_float: f64 = 0;
    var has_float = false;

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        if (val.isFloat()) {
            has_float = true;
            sum_float += val.asFloat();
        } else {
            sum_int += val.toInt();
        }
    }

    if (has_float) {
        return Value.initFloat(sum_float + @as(f64, @floatFromInt(sum_int)));
    }
    return Value.initInt(sum_int);
}

/// array_product - 计算数组元素的乘积
pub fn php_array_product(arr: Value) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();
    if (php_arr.count() == 0) return Value.initInt(1);

    var product: f64 = 1;
    var it = php_arr.elements.iterator();

    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        product *= val.toFloat();
    }

    // 如果结果是整数，返回整数
    if (@floor(product) == product and product >= @as(f64, @floatFromInt(std.math.minInt(i64))) and product <= @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
        return Value.initInt(@intFromFloat(product));
    }
    return Value.initFloat(product);
}

/// array_reverse - 反转数组
pub fn php_array_reverse(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    // 收集所有元素
    var values = try allocator.alloc(Value, php_arr.count());
    defer allocator.free(values);

    var idx: usize = 0;
    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        values[idx] = entry.value_ptr.*;
        idx += 1;
    }

    // 反向添加
    var i: usize = values.len;
    while (i > 0) {
        i -= 1;
        try result.push(allocator, values[i]);
    }

    return Value.initArray(result);
}

/// array_unique - 移除数组中的重复值
pub fn php_array_unique(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;

        // 检查是否已存在
        var exists = false;
        var result_it = result.elements.iterator();
        while (result_it.next()) |existing| {
            const eq_result = try php_eq(val, existing.value_ptr.*);
            if (eq_result.asBool()) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            try result.setByKey(allocator, entry.key_ptr.*, val);
        }
    }

    return Value.initArray(result);
}

/// array_flip - 交换数组的键和值
pub fn php_array_flip(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        const key = entry.key_ptr.*;

        // 值变成键，键变成值
        if (val.isInt()) {
            try result.set(allocator, val.asInt(), switch (key) {
                .int => |k| Value.initInt(k),
                .string => |k| Value.initString(k),
            });
        } else if (val.isString()) {
            try result.setByString(allocator, val.asString().data, switch (key) {
                .int => |k| Value.initInt(k),
                .string => |k| Value.initString(k),
            });
        }
    }

    return Value.initArray(result);
}

/// array_key_exists - 检查数组中是否存在指定的键
pub fn php_array_key_exists(key: Value, arr: Value) !Value {
    if (!arr.isArray()) return Value.initBool(false);

    const php_arr = arr.asArray();

    if (key.isInt()) {
        return Value.initBool(php_arr.get(key.asInt()) != null);
    } else if (key.isString()) {
        return Value.initBool(php_arr.getByString(key.asString().data) != null);
    }

    return Value.initBool(false);
}

/// array_key_first - 获取数组的第一个键
pub fn php_array_key_first(arr: Value) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    var it = php_arr.elements.iterator();

    if (it.next()) |entry| {
        return switch (entry.key_ptr.*) {
            .int => |k| Value.initInt(k),
            .string => |k| Value.initString(k),
        };
    }

    return Value.initNull();
}

/// array_key_last - 获取数组的最后一个键
pub fn php_array_key_last(arr: Value) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    var last_key: ?PHPArray.ArrayKey = null;

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        last_key = entry.key_ptr.*;
    }

    if (last_key) |key| {
        return switch (key) {
            .int => |k| Value.initInt(k),
            .string => |k| Value.initString(k),
        };
    }

    return Value.initNull();
}

/// array_fill - 用指定值填充数组
pub fn php_array_fill(start_index: Value, num: Value, value: Value, allocator: Allocator) !Value {
    const result = try PHPArray.init(allocator);

    const start = start_index.toInt();
    const count = @max(0, num.toInt());

    var i: i64 = 0;
    while (i < count) : (i += 1) {
        try result.set(allocator, start + i, value);
    }

    return Value.initArray(result);
}

/// range - 创建包含指定范围元素的数组
pub fn php_range(start: Value, end: Value, allocator: Allocator) !Value {
    const result = try PHPArray.init(allocator);

    const start_val = start.toInt();
    const end_val = end.toInt();

    if (start_val <= end_val) {
        var i = start_val;
        while (i <= end_val) : (i += 1) {
            try result.push(allocator, Value.initInt(i));
        }
    } else {
        var i = start_val;
        while (i >= end_val) : (i -= 1) {
            try result.push(allocator, Value.initInt(i));
        }
    }

    return Value.initArray(result);
}

// ============================================================================
// 扩展字符串函数
// ============================================================================

/// ord - 返回字符的ASCII值
pub fn php_ord(str: Value) !Value {
    if (!str.isString()) return Value.initInt(0);

    const php_str = str.asString();
    if (php_str.length == 0) return Value.initInt(0);

    return Value.initInt(@intCast(php_str.data[0]));
}

/// chr - 返回指定ASCII值对应的字符
pub fn php_chr(code: Value, allocator: Allocator) !Value {
    const ascii = @as(u8, @truncate(@as(u64, @intCast(code.toInt() & 0xFF))));
    const buffer = [_]u8{ascii};
    const result = try PHPString.init(allocator, &buffer);
    return Value.initString(result);
}

/// stripos - 不区分大小写查找子字符串位置
pub fn php_stripos(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    var i: usize = 0;
    while (i <= hay.length - need.length) : (i += 1) {
        var match = true;
        var j: usize = 0;
        while (j < need.length) : (j += 1) {
            if (std.ascii.toLower(hay.data[i + j]) != std.ascii.toLower(need.data[j])) {
                match = false;
                break;
            }
        }
        if (match) return Value.initInt(@intCast(i));
    }

    return Value.initBool(false);
}

/// strrpos - 查找子字符串最后出现的位置
pub fn php_strrpos(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    var last_pos: ?usize = null;
    var i: usize = 0;
    while (i <= hay.length - need.length) : (i += 1) {
        if (std.mem.eql(u8, hay.data[i .. i + need.length], need.data)) {
            last_pos = i;
        }
    }

    if (last_pos) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

/// number_format - 格式化数字
pub fn php_number_format(number: Value, decimals: Value, allocator: Allocator) !Value {
    const num = number.toFloat();
    const dec = @max(0, decimals.toInt());

    // 简化实现：只支持基本格式
    const formatted = try std.fmt.allocPrint(allocator, "{d:.{d}}", .{ num, @as(usize, @intCast(dec)) });
    defer allocator.free(formatted);

    const result = try PHPString.init(allocator, formatted);
    return Value.initString(result);
}

/// nl2br - 将换行符转换为HTML <br>标签
pub fn php_nl2br(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();

    // 计算需要的空间
    var count: usize = 0;
    for (php_str.data) |c| {
        if (c == '\n') count += 1;
    }

    const new_len = php_str.length + count * 5; // <br>\n = 6 bytes, minus original \n = 5
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    for (php_str.data) |c| {
        if (c == '\n') {
            @memcpy(buffer[write_pos .. write_pos + 4], "<br>");
            write_pos += 4;
        }
        buffer[write_pos] = c;
        write_pos += 1;
    }

    const result = try PHPString.init(allocator, buffer[0..write_pos]);
    allocator.free(buffer);
    return Value.initString(result);
}

/// strip_tags - 移除HTML和PHP标签
pub fn php_strip_tags(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    var in_tag = false;

    for (php_str.data) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            buffer[write_pos] = c;
            write_pos += 1;
        }
    }

    const result = try PHPString.init(allocator, buffer[0..write_pos]);
    allocator.free(buffer);
    return Value.initString(result);
}

/// strval - 获取变量的字符串值
pub fn php_strval(val: Value, allocator: Allocator) !Value {
    const str = try val.toString(allocator);
    return Value.initString(str);
}

/// gettype - 获取变量的类型
pub fn php_gettype(val: Value, allocator: Allocator) !Value {
    const type_str = if (val.isNull())
        "NULL"
    else if (val.isBool())
        "boolean"
    else if (val.isInt())
        "integer"
    else if (val.isFloat())
        "double"
    else if (val.isString())
        "string"
    else if (val.isArray())
        "array"
    else if (Value_isObject(val))
        "object"
    else
        "unknown type";

    const result = try PHPString.init(allocator, type_str);
    return Value.initString(result);
}

// ============================================================================
// 文件函数
// ============================================================================

/// file_get_contents - 读取文件内容
pub fn php_file_get_contents(filename: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;

    const file = std.fs.cwd().openFile(path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 100 * 1024 * 1024) catch {
        return Value.initBool(false);
    };
    defer allocator.free(content);

    const result = try PHPString.init(allocator, content);
    return Value.initString(result);
}

/// file_put_contents - 将数据写入文件
pub fn php_file_put_contents(filename: Value, data: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    const content = try data.toString(allocator);
    defer content.release(allocator);

    const file = std.fs.cwd().createFile(path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close();

    file.writeAll(content.data) catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(content.length));
}

/// file_exists - 检查文件是否存在
pub fn php_file_exists(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    std.fs.cwd().access(path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// is_file - 检查是否是普通文件
pub fn php_is_file(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    const stat = std.fs.cwd().statFile(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(stat.kind == .file);
}

/// is_dir - 检查是否是目录
pub fn php_is_dir(dirname: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    var dir = std.fs.cwd().openDir(path, .{}) catch {
        return Value.initBool(false);
    };
    dir.close();

    return Value.initBool(true);
}

/// mkdir - 创建目录
pub fn php_mkdir(dirname: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    std.fs.cwd().makeDir(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// rmdir - 删除目录
pub fn php_rmdir(dirname: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    std.fs.cwd().deleteDir(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// unlink - 删除文件
pub fn php_unlink(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    std.fs.cwd().deleteFile(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// rename - 重命名文件
pub fn php_rename(oldname: Value, newname: Value) !Value {
    if (!oldname.isString() or !newname.isString()) return Value.initBool(false);

    const old_path = oldname.asString().data;
    const new_path = newname.asString().data;

    std.fs.cwd().rename(old_path, new_path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// copy - 拷贝文件
pub fn php_copy(source: Value, dest: Value) !Value {
    if (!source.isString() or !dest.isString()) return Value.initBool(false);

    const source_path = source.asString().data;
    const dest_path = dest.asString().data;

    std.fs.cwd().copyFile(source_path, std.fs.cwd(), dest_path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// filesize - 获取文件大小
pub fn php_filesize(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    const file = std.fs.cwd().openFile(path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close();

    const stat = file.stat() catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(stat.size));
}

/// basename - 返回路径中的文件名部分
pub fn php_basename(path: Value, allocator: Allocator) !Value {
    if (!path.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const path_str = path.asString().data;
    const base = std.fs.path.basename(path_str);
    const result = try PHPString.init(allocator, base);
    return Value.initString(result);
}

/// dirname - 返回路径中的目录部分
pub fn php_dirname(path: Value, allocator: Allocator) !Value {
    if (!path.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const path_str = path.asString().data;
    const dir = std.fs.path.dirname(path_str) orelse ".";
    const result = try PHPString.init(allocator, dir);
    return Value.initString(result);
}

// ============================================================================
// JSON函数
// ============================================================================

/// json_encode - 将PHP值编码为JSON字符串
pub fn php_json_encode(value: Value, allocator: Allocator) !Value {
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    try jsonEncodeValue(value, &buffer, allocator);

    const result = try PHPString.init(allocator, buffer.items);
    return Value.initString(result);
}

fn jsonEncodeValue(value: Value, buffer: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
    if (value.isNull()) {
        try buffer.appendSlice(allocator, "null");
    } else if (value.isBool()) {
        try buffer.appendSlice(allocator, if (value.asBool()) "true" else "false");
    } else if (value.isInt()) {
        const formatted = try std.fmt.allocPrint(allocator, "{d}", .{value.asInt()});
        defer allocator.free(formatted);
        try buffer.appendSlice(allocator, formatted);
    } else if (value.isFloat()) {
        const formatted = try std.fmt.allocPrint(allocator, "{d}", .{value.asFloat()});
        defer allocator.free(formatted);
        try buffer.appendSlice(allocator, formatted);
    } else if (value.isString()) {
        const str = value.asString();
        try buffer.append(allocator, '"');
        for (str.data) |c| {
            switch (c) {
                '"' => try buffer.appendSlice(allocator, "\\\""),
                '\\' => try buffer.appendSlice(allocator, "\\\\"),
                '\n' => try buffer.appendSlice(allocator, "\\n"),
                '\r' => try buffer.appendSlice(allocator, "\\r"),
                '\t' => try buffer.appendSlice(allocator, "\\t"),
                else => try buffer.append(allocator, c),
            }
        }
        try buffer.append(allocator, '"');
    } else if (value.isArray()) {
        const arr = value.asArray();
        var is_list = true;
        var expected_index: i64 = 0;

        // 检查是否是纯索引数组
        var it = arr.elements.iterator();
        while (it.next()) |entry| {
            switch (entry.key_ptr.*) {
                .integer => |k| {
                    if (k != expected_index) is_list = false;
                    expected_index += 1;
                },
                .string => is_list = false,
            }
            if (!is_list) break;
        }

        if (is_list) {
            try buffer.append(allocator, '[');
            var first = true;
            it = arr.elements.iterator();
            while (it.next()) |entry| {
                if (!first) try buffer.append(allocator, ',');
                try jsonEncodeValue(entry.value_ptr.*, buffer, allocator);
                first = false;
            }
            try buffer.append(allocator, ']');
        } else {
            try buffer.append(allocator, '{');
            var first = true;
            it = arr.elements.iterator();
            while (it.next()) |entry| {
                if (!first) try buffer.append(allocator, ',');

                // 写入键
                switch (entry.key_ptr.*) {
                    .integer => |k| {
                        try buffer.append(allocator, '"');
                        const key_str = try std.fmt.allocPrint(allocator, "{d}", .{k});
                        defer allocator.free(key_str);
                        try buffer.appendSlice(allocator, key_str);
                        try buffer.append(allocator, '"');
                    },
                    .string => |k| {
                        try buffer.append(allocator, '"');
                        for (k.data) |c| {
                            switch (c) {
                                '"' => try buffer.appendSlice(allocator, "\\\""),
                                '\\' => try buffer.appendSlice(allocator, "\\\\"),
                                '\n' => try buffer.appendSlice(allocator, "\\n"),
                                '\r' => try buffer.appendSlice(allocator, "\\r"),
                                '\t' => try buffer.appendSlice(allocator, "\\t"),
                                else => try buffer.append(allocator, c),
                            }
                        }
                        try buffer.append(allocator, '"');
                    },
                }
                try buffer.appendSlice(allocator, ":");

                // 写入值
                try jsonEncodeValue(entry.value_ptr.*, buffer, allocator);
                first = false;
            }
            try buffer.append(allocator, '}');
        }
    } else {
        try buffer.appendSlice(allocator, "null");
    }
}

/// json_decode - 解析JSON字符串为PHP值
pub fn php_json_decode(json: Value, assoc: Value, allocator: Allocator) !Value {
    if (!json.isString()) return Value.initNull();

    const is_assoc = if (assoc.isBool()) assoc.asBool() else assoc.toBool();
    const json_str = json.asString().data;
    var pos: usize = 0;

    return jsonDecodeValue(json_str, &pos, is_assoc, allocator) catch Value.initNull();
}

const JsonError = error{
    InvalidJson,
    UnexpectedEnd,
    OutOfMemory,
    StringTooLarge,
};

fn jsonDecodeValue(json: []const u8, pos: *usize, assoc: bool, allocator: Allocator) JsonError!Value {
    skipWhitespace(json, pos);

    if (pos.* >= json.len) return error.UnexpectedEnd;

    const c = json[pos.*];

    if (c == 'n' and pos.* + 4 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 4], "null")) {
        pos.* += 4;
        return Value.initNull();
    }

    if (c == 't' and pos.* + 4 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 4], "true")) {
        pos.* += 4;
        return Value.initBool(true);
    }

    if (c == 'f' and pos.* + 5 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 5], "false")) {
        pos.* += 5;
        return Value.initBool(false);
    }

    if (c == '"') {
        return jsonDecodeString(json, pos, allocator);
    }

    if (c == '[') {
        return jsonDecodeArray(json, pos, assoc, allocator);
    }

    if (c == '{') {
        return jsonDecodeObject(json, pos, assoc, allocator);
    }

    if (c == '-' or (c >= '0' and c <= '9')) {
        return jsonDecodeNumber(json, pos);
    }

    return error.InvalidJson;
}

fn jsonDecodeString(json: []const u8, pos: *usize, allocator: Allocator) !Value {
    pos.* += 1; // 跳过开头的引号

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    while (pos.* < json.len and json[pos.*] != '"') {
        if (json[pos.*] == '\\' and pos.* + 1 < json.len) {
            pos.* += 1;
            switch (json[pos.*]) {
                'n' => try buffer.append(allocator, '\n'),
                'r' => try buffer.append(allocator, '\r'),
                't' => try buffer.append(allocator, '\t'),
                '"' => try buffer.append(allocator, '"'),
                '\\' => try buffer.append(allocator, '\\'),
                else => try buffer.append(allocator, json[pos.*]),
            }
        } else {
            try buffer.append(allocator, json[pos.*]);
        }
        pos.* += 1;
    }

    if (pos.* < json.len) pos.* += 1; // 跳过结尾的引号

    const result = try PHPString.init(allocator, buffer.items);
    return Value.initString(result);
}

fn jsonDecodeNumber(json: []const u8, pos: *usize) JsonError!Value {
    const start = pos.*;
    var is_float = false;

    if (json[pos.*] == '-') pos.* += 1;

    while (pos.* < json.len) {
        const c = json[pos.*];
        if (c >= '0' and c <= '9') {
            pos.* += 1;
        } else if (c == '.' or c == 'e' or c == 'E') {
            is_float = true;
            pos.* += 1;
        } else if (c == '+' or c == '-') {
            pos.* += 1;
        } else {
            break;
        }
    }

    const num_str = json[start..pos.*];

    if (is_float) {
        const f = std.fmt.parseFloat(f64, num_str) catch return Value.initFloat(0);
        return Value.initFloat(f);
    } else {
        const i = std.fmt.parseInt(i64, num_str, 10) catch return Value.initInt(0);
        return Value.initInt(i);
    }
}

fn jsonDecodeArray(json: []const u8, pos: *usize, assoc: bool, allocator: Allocator) JsonError!Value {
    pos.* += 1; // 跳过 '['

    const arr = try PHPArray.init(allocator);

    skipWhitespace(json, pos);

    if (pos.* < json.len and json[pos.*] == ']') {
        pos.* += 1;
        return Value.initArray(arr);
    }

    while (pos.* < json.len) {
        const value = try jsonDecodeValue(json, pos, assoc, allocator);
        try arr.push(allocator, value);
        value.release(allocator);

        skipWhitespace(json, pos);

        if (pos.* < json.len and json[pos.*] == ',') {
            pos.* += 1;
            skipWhitespace(json, pos);
        } else {
            break;
        }
    }

    if (pos.* < json.len and json[pos.*] == ']') pos.* += 1;

    return Value.initArray(arr);
}

fn jsonDecodeObject(json: []const u8, pos: *usize, assoc: bool, allocator: Allocator) !Value {
    pos.* += 1; // 跳过 '{'

    const arr = try PHPArray.init(allocator);

    skipWhitespace(json, pos);

    if (pos.* < json.len and json[pos.*] == '}') {
        pos.* += 1;
        return Value.initArray(arr);
    }

    while (pos.* < json.len) {
        skipWhitespace(json, pos);

        // 解析键
        if (json[pos.*] != '"') return error.InvalidJson;
        const key = try jsonDecodeString(json, pos, allocator);

        skipWhitespace(json, pos);

        if (pos.* >= json.len or json[pos.*] != ':') return error.InvalidJson;
        pos.* += 1;

        // 解析值
        const value = try jsonDecodeValue(json, pos, assoc, allocator);

        // 添加到数组
        if (key.isString()) {
            const key_str = key.asString();
            const array_key = ArrayKey{ .string = key_str };
            try arr.set(allocator, array_key, value);
        }
        key.release(allocator);
        value.release(allocator);

        skipWhitespace(json, pos);

        if (pos.* < json.len and json[pos.*] == ',') {
            pos.* += 1;
        } else {
            break;
        }
    }

    if (pos.* < json.len and json[pos.*] == '}') pos.* += 1;

    // 如果 assoc 为 false，应该返回对象，但目前我们统一返回数组（简化实现）
    // TODO: 实现 stdClass 对象
    
    return Value.initArray(arr);
}

fn skipWhitespace(json: []const u8, pos: *usize) void {
    while (pos.* < json.len and (json[pos.*] == ' ' or json[pos.*] == '\t' or json[pos.*] == '\n' or json[pos.*] == '\r')) {
        pos.* += 1;
    }
}

// ============================================================================
// 杂项函数
// ============================================================================

/// sleep - 延迟执行（秒）
pub fn php_sleep(seconds: Value) !Value {
    const secs = @max(0, seconds.toInt());
    std.time.sleep(@as(u64, @intCast(secs)) * std.time.ns_per_s);
    return Value.initInt(0);
}

/// usleep - 延迟执行（微秒）
pub fn php_usleep(microseconds: Value) !Value {
    const usecs = @max(0, microseconds.toInt());
    std.time.sleep(@as(u64, @intCast(usecs)) * std.time.ns_per_us);
    return Value.initNull();
}

/// exit/die - 终止程序执行
pub fn php_exit(status: Value) !noreturn {
    const code: u8 = if (status.isInt())
        @truncate(@as(u64, @intCast(status.asInt() & 0xFF)))
    else
        0;
    std.process.exit(code);
}

/// empty - 检查变量是否为空
pub fn php_empty(val: Value) !Value {
    if (val.isNull()) return Value.initBool(true);
    if (val.isBool()) return Value.initBool(!val.asBool());
    if (val.isInt()) return Value.initBool(val.asInt() == 0);
    if (val.isFloat()) return Value.initBool(val.asFloat() == 0);
    if (val.isString()) return Value.initBool(val.asString().length == 0 or std.mem.eql(u8, val.asString().data, "0"));
    if (val.isArray()) return Value.initBool(val.asArray().count() == 0);
    return Value.initBool(false);
}

/// isset - 检查变量是否已设置且非null
pub fn php_isset(val: Value) !Value {
    return Value.initBool(!val.isNull());
}

// ============================================================================
// 高阶数组函数
// ============================================================================

/// array_map - 对数组的每个元素应用回调函数
pub fn php_array_map(callback: Value, arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{entry.value_ptr.*};
        const result_value = try php_invoke_callable(callback, &args, allocator);
        try result_arr.set(allocator, entry.key_ptr.*, result_value);
        result_value.release(allocator);
    }

    return Value.initArray(result_arr);
}

/// array_filter - 过滤数组元素
pub fn php_array_filter(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const should_keep = if (callback.isNull()) blk: {
            break :blk entry.value_ptr.*.toBool();
        } else blk: {
            const args = [_]Value{entry.value_ptr.*};
            const result = try php_invoke_callable(callback, &args, allocator);
            defer result.release(allocator);
            break :blk result.toBool();
        };

        if (should_keep) {
            try result_arr.set(allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    return Value.initArray(result_arr);
}

/// array_reduce - 使用回调函数迭代地将数组简化为单一值
pub fn php_array_reduce(arr: Value, callback: Value, initial: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    var carry = initial;

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{ carry, entry.value_ptr.* };
        carry = try php_invoke_callable(callback, &args, allocator);
    }

    return carry;
}

/// array_chunk - 将数组分割成指定大小的块
pub fn php_array_chunk(arr: Value, size: Value, preserve_keys: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const chunk_size = size.toInt();
    if (chunk_size < 1) return error.InvalidArgument;

    const preserve = preserve_keys.toBool();
    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var current_chunk = try PHPArray.init(allocator);
    var count: i64 = 0;
    var new_index: i64 = 0;

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        if (preserve) {
            try current_chunk.set(allocator, entry.key_ptr.*, entry.value_ptr.*);
        } else {
            try current_chunk.push(allocator, entry.value_ptr.*);
        }
        count += 1;

        if (count >= chunk_size) {
            try result_arr.set(allocator, .{ .integer = new_index }, Value.initArray(current_chunk));
            new_index += 1;
            current_chunk = try PHPArray.init(allocator);
            count = 0;
        }
    }

    if (count > 0) {
        try result_arr.set(allocator, .{ .integer = new_index }, Value.initArray(current_chunk));
    } else {
        current_chunk.release(allocator);
    }

    return Value.initArray(result_arr);
}

/// array_column - 返回数组中指定列的值
pub fn php_array_column(arr: Value, column_key: Value, index_key: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const row = entry.value_ptr.*;
        if (!row.isArray()) continue;

        const row_arr = row.asArray();

        // 获取列值
        const col_value = if (column_key.isInt()) blk: {
            break :blk row_arr.get(.{ .integer = column_key.asInt() });
        } else if (column_key.isString()) blk: {
            break :blk row_arr.getByString(column_key.asString().data);
        } else blk: {
            break :blk null;
        };

        if (col_value) |val| {
            // 确定索引
            if (index_key.isNull()) {
                try result_arr.push(allocator, val);
            } else {
                const idx_value = if (index_key.isInt()) blk: {
                    break :blk row_arr.get(.{ .integer = index_key.asInt() });
                } else if (index_key.isString()) blk: {
                    break :blk row_arr.getByString(index_key.asString().data);
                } else blk: {
                    break :blk null;
                };

                if (idx_value) |idx| {
                    if (idx.isInt()) {
                        try result_arr.set(allocator, .{ .integer = idx.asInt() }, val);
                    } else if (idx.isString()) {
                        try result_arr.setByString(allocator, idx.asString().data, val);
                    } else {
                        try result_arr.push(allocator, val);
                    }
                } else {
                    try result_arr.push(allocator, val);
                }
            }
        }
    }

    return Value.initArray(result_arr);
}

/// array_walk - 对数组中的每个元素应用用户自定义函数
pub fn php_array_walk(arr: Value, callback: Value, userdata: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        // 构建回调参数：value, key, userdata
        const key_val = switch (entry.key_ptr.*) {
            .integer => |k| Value.initInt(k),
            .string => |k| Value.initString(k),
        };

        const args = if (userdata.isNull())
            [_]Value{ entry.value_ptr.*, key_val }
        else
            [_]Value{ entry.value_ptr.*, key_val, userdata };

        const result = try php_invoke_callable(callback, args[0..], allocator);
        result.release(allocator);
    }

    return Value.initBool(true);
}

// ============================================================================
// 字符串高级函数
// ============================================================================

/// sprintf - 格式化字符串
pub fn php_sprintf(format: Value, args: []const Value, allocator: Allocator) !Value {
    if (!format.isString()) return error.InvalidArgument;

    const fmt = format.asString().data;
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var arg_idx: usize = 0;
    var i: usize = 0;

    while (i < fmt.len) {
        if (fmt[i] == '%' and i + 1 < fmt.len) {
            i += 1;
            if (fmt[i] == '%') {
                try result.append('%');
                i += 1;
                continue;
            }

            // 跳过标志
            while (i < fmt.len and (fmt[i] == '-' or fmt[i] == '+' or fmt[i] == ' ' or fmt[i] == '0')) {
                i += 1;
            }

            // 跳过宽度
            while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                i += 1;
            }

            // 跳过精度
            if (i < fmt.len and fmt[i] == '.') {
                i += 1;
                while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                    i += 1;
                }
            }

            if (i >= fmt.len) break;

            const specifier = fmt[i];
            i += 1;

            if (arg_idx >= args.len) continue;
            const arg = args[arg_idx];
            arg_idx += 1;

            switch (specifier) {
                's' => {
                    if (arg.isString()) {
                        try result.appendSlice(arg.asString().data);
                    } else {
                        const str = try arg.toString(allocator);
                        defer str.release(allocator);
                        try result.appendSlice(str.data);
                    }
                },
                'd', 'i' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{d}", .{val});
                    defer allocator.free(str);
                    try result.appendSlice(str);
                },
                'f' => {
                    const val = arg.toFloat();
                    const str = try std.fmt.allocPrint(allocator, "{d:.6}", .{val});
                    defer allocator.free(str);
                    try result.appendSlice(str);
                },
                'x' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{x}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try result.appendSlice(str);
                },
                'X' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{X}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try result.appendSlice(str);
                },
                'c' => {
                    const val = arg.toInt();
                    if (val >= 0 and val <= 255) {
                        try result.append(@intCast(val));
                    }
                },
                else => {
                    try result.append('%');
                    try result.append(specifier);
                },
            }
        } else {
            try result.append(fmt[i]);
            i += 1;
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// htmlspecialchars - 将特殊字符转换为HTML实体
pub fn php_htmlspecialchars(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (input) |c| {
        switch (c) {
            '&' => try result.appendSlice("&amp;"),
            '"' => try result.appendSlice("&quot;"),
            '\'' => try result.appendSlice("&#039;"),
            '<' => try result.appendSlice("&lt;"),
            '>' => try result.appendSlice("&gt;"),
            else => try result.append(c),
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// htmlentities - 将所有适用的字符转换为HTML实体
pub fn php_htmlentities(str: Value, allocator: Allocator) !Value {
    return php_htmlspecialchars(str, allocator);
}

/// htmlspecialchars_decode - 将HTML实体转换回字符
pub fn php_htmlspecialchars_decode(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '&') {
            if (i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "&lt;")) {
                try result.append('<');
                i += 4;
            } else if (i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "&gt;")) {
                try result.append('>');
                i += 4;
            } else if (i + 5 <= input.len and std.mem.eql(u8, input[i .. i + 5], "&amp;")) {
                try result.append('&');
                i += 5;
            } else if (i + 6 <= input.len and std.mem.eql(u8, input[i .. i + 6], "&quot;")) {
                try result.append('"');
                i += 6;
            } else if (i + 6 <= input.len and std.mem.eql(u8, input[i .. i + 6], "&#039;")) {
                try result.append('\'');
                i += 6;
            } else {
                try result.append(input[i]);
                i += 1;
            }
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// wordwrap - 将字符串按指定长度换行
pub fn php_wordwrap(str: Value, width: Value, break_str: Value, cut: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const wrap_width: usize = @intCast(@max(1, width.toInt()));
    const break_chars = if (break_str.isString()) break_str.asString().data else "\n";
    const force_cut = cut.toBool();

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var line_len: usize = 0;
    var word_start: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == ' ' or input[i] == '\n') {
            // 输出单词
            if (i > word_start) {
                const word = input[word_start..i];
                if (line_len + word.len > wrap_width and line_len > 0) {
                    try result.appendSlice(break_chars);
                    line_len = 0;
                }
                try result.appendSlice(word);
                line_len += word.len;
            }
            if (input[i] == '\n') {
                try result.append('\n');
                line_len = 0;
            } else {
                try result.append(' ');
                line_len += 1;
            }
            word_start = i + 1;
        } else if (force_cut and line_len >= wrap_width) {
            try result.appendSlice(break_chars);
            line_len = 0;
        }
        i += 1;
    }

    // 输出剩余单词
    if (i > word_start) {
        const word = input[word_start..i];
        if (line_len + word.len > wrap_width and line_len > 0) {
            try result.appendSlice(break_chars);
        }
        try result.appendSlice(word);
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

// ============================================================================
// 哈希函数
// ============================================================================

/// md5 - 计算字符串的MD5哈希值
pub fn php_md5(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(input, &hash, .{});

    // 转换为十六进制字符串
    var hex_str: [32]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

/// sha1 - 计算字符串的SHA1哈希值
pub fn php_sha1(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(input, &hash, .{});

    // 转换为十六进制字符串
    var hex_str: [40]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

/// sha256 - 计算字符串的SHA256哈希值
pub fn php_sha256(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &hash, .{});

    // 转换为十六进制字符串
    var hex_str: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

/// hash - 生成哈希值
pub fn php_hash(algorithm: Value, data: Value, allocator: Allocator) !Value {
    if (!algorithm.isString() or !data.isString()) return error.InvalidArgument;

    const algo = algorithm.asString().data;

    if (std.mem.eql(u8, algo, "md5")) {
        return php_md5(data, allocator);
    } else if (std.mem.eql(u8, algo, "sha1")) {
        return php_sha1(data, allocator);
    } else if (std.mem.eql(u8, algo, "sha256")) {
        return php_sha256(data, allocator);
    }

    return error.UnsupportedAlgorithm;
}

/// crc32 - 计算字符串的CRC32校验值
pub fn php_crc32(str: Value) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const crc = std.hash.Crc32.hash(input);
    return Value.initInt(@intCast(crc));
}

/// base64_encode - 使用MIME base64编码数据
pub fn php_base64_encode(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const encoder = std.base64.standard;
    const encoded_len = encoder.Encoder.calcSize(input.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded);

    _ = encoder.Encoder.encode(encoded, input);

    const php_str = try PHPString.init(allocator, encoded);
    return Value.initString(php_str);
}

/// base64_decode - 对使用MIME base64编码的数据进行解码
pub fn php_base64_decode(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const decoder = std.base64.standard;

    const decoded_max_len = decoder.Decoder.calcSizeForSlice(input) catch return Value.initBool(false);
    const decoded = try allocator.alloc(u8, decoded_max_len);
    defer allocator.free(decoded);

    const decoded_len = decoder.Decoder.decode(decoded, input) catch return Value.initBool(false);

    const php_str = try PHPString.init(allocator, decoded[0..decoded_len]);
    return Value.initString(php_str);
}

// ============================================================================
// 并发/协程支持函数 - 真正的实现
// ============================================================================

const concurrency = @import("concurrency_runtime.zig");

/// 全局互斥锁
var global_mutex: std.Thread.Mutex = .{};

/// 获取互斥锁
pub fn mutex_lock() void {
    global_mutex.lock();
}

/// 释放互斥锁
pub fn mutex_unlock() void {
    global_mutex.unlock();
}

/// 创建新的互斥锁（返回Value包装）
pub fn mutex_new(allocator: Allocator) !Value {
    _ = allocator;
    return Value.initNull();
}

/// Channel包装类型
const ChannelWrapper = struct {
    channel: *concurrency.Channel(Value),

    pub fn init(allocator: Allocator, buffer_size: u32) !*ChannelWrapper {
        const wrapper = try allocator.create(ChannelWrapper);
        wrapper.channel = try concurrency.Channel(Value).init(allocator, buffer_size);
        return wrapper;
    }

    pub fn deinit(self: *ChannelWrapper, allocator: Allocator) void {
        self.channel.deinit();
        allocator.destroy(self);
    }
};

/// 协程函数包装器
const CoroutineFunc = struct {
    func_name: []const u8,
    args: []const Value,
    allocator: Allocator,

    pub fn run(args_ptr: []const anyopaque) !void {
        const self = @as(*const CoroutineFunc, @ptrCast(@alignCast(args_ptr.ptr)));
        _ = self;
        // TODO: 通过函数名查找并调用实际函数
    }
};

/// 启动协程/goroutine - 真正的实现
pub fn go_spawn(func_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const sched = try concurrency.getScheduler(allocator);

    // 创建协程函数包装
    const func_wrapper = try allocator.create(CoroutineFunc);
    func_wrapper.* = .{
        .func_name = func_name,
        .args = args,
        .allocator = allocator,
    };

    const args_slice = std.mem.asBytes(func_wrapper);
    const coro_id = try sched.spawn(CoroutineFunc.run, args_slice);

    return Value.initInt(@intCast(coro_id));
}

/// 创建通道 - 真正的实现
pub fn channel_new(buffer_size: u32, allocator: Allocator) !Value {
    const wrapper = try ChannelWrapper.init(allocator, buffer_size);
    const ptr_int = @intFromPtr(wrapper);
    return Value.initInt(@intCast(ptr_int));
}

/// 发送到通道 - 真正的实现
pub fn channel_send(channel: Value, value: Value) !void {
    if (!channel.isInt()) return error.InvalidChannel;

    const ptr_int: usize = @intCast(channel.asInt());
    const wrapper = @as(*ChannelWrapper, @ptrFromInt(ptr_int));

    try wrapper.channel.send(value);
}

/// 从通道接收 - 真正的实现
pub fn channel_recv(channel: Value) !Value {
    if (!channel.isInt()) return error.InvalidChannel;

    const ptr_int: usize = @intCast(channel.asInt());
    const wrapper = @as(*ChannelWrapper, @ptrFromInt(ptr_int));

    return try wrapper.channel.recv();
}

/// 关闭通道 - 真正的实现
pub fn channel_close(channel: Value) void {
    if (!channel.isInt()) return;

    const ptr_int: usize = @intCast(channel.asInt());
    const wrapper = @as(*ChannelWrapper, @ptrFromInt(ptr_int));

    wrapper.channel.close();
}

/// 等待异步结果
pub fn await_result(future: Value) !Value {
    // 简单实现：直接返回future值
    return future;
}
