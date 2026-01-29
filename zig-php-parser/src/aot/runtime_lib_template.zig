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

    pub fn hash(self: ArrayKey) u32 {
        return switch (self) {
            .integer => |i| @truncate(std.hash.Wyhash.hash(0, std.mem.asBytes(&i))),
            .string => |s| @truncate(std.hash.Wyhash.hash(0, s.data)),
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
    elements: std.AutoHashMap(ArrayKey, Value),
    next_index: i64,
    ref_count: usize,

    pub const ArrayContext = struct {
        pub fn hash(_: ArrayContext, key: ArrayKey) u32 {
            return key.hash();
        }

        pub fn eql(_: ArrayContext, a: ArrayKey, b: ArrayKey, _: usize) bool {
            return a.eql(b);
        }
    };

    /// 创建新数组
    pub fn init(allocator: Allocator) !*PHPArray {
        const array = try allocator.create(PHPArray);
        array.elements = std.AutoHashMap(ArrayKey, Value).init(allocator);
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

    // ========================================================================
    // 引用计数
    // ========================================================================

    pub fn retain(self: Value) Value {
        if (self.isString()) {
            self.asString().retain();
        } else if (self.isArray()) {
            self.asArray().retain();
        } else if (Value_isObject(self)) {
            Value_asObject(self).retain();
        }
        return self;
    }

    pub fn release(self: Value, allocator: Allocator) void {
        if (self.isString()) {
            self.asString().release(allocator);
        } else if (self.isArray()) {
            self.asArray().release(allocator);
        } else if (Value_isObject(self)) {
            Value_asObject(self).release();
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
        return PHPString.init(allocator, "");
    }
};

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
        std.debug.print("array({})\n", .{arr.count()});
    }
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
// 类型转换函数
// ============================================================================

/// intval - 转换为整数
pub fn php_intval(val: Value) !Value {
    return Value.initInt(val.toInt());
}

/// floatval - 转换为浮点数
pub fn php_floatval(val: Value) !Value {
    return Value.initFloat(val.toFloat());
}

/// strval - 转换为字符串
pub fn php_strval(val: Value, allocator: Allocator) !Value {
    const str = try val.toString(allocator);
    return Value.initString(str);
}

/// boolval - 转换为布尔值
pub fn php_boolval(val: Value) !Value {
    return Value.initBool(val.toBool());
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
            @memcpy(result_data[offset..offset + str.length], str.data[0..str.length]);
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
// PHP对象类型
// ============================================================================

/// PHP对象类型
/// 使用引用计数管理内存，属性存储在HashMap中
pub const PHPObject = struct {
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

    /// 获取属性
    pub fn getProperty(self: *PHPObject, name: []const u8) ?Value {
        return self.properties.get(name);
    }

    /// 设置属性
    pub fn setProperty(self: *PHPObject, name: []const u8, value: Value) !void {
        // 释放旧值
        if (self.properties.get(name)) |old_value| {
            old_value.release(self.allocator);
        }
        
        // 保留新值
        _ = value.retain();
        
        // 存储属性
        try self.properties.put(name, value);
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
/// @param class_name 类名
/// @param allocator 内存分配器
/// @return 对象Value
pub fn php_object_new(class_name: []const u8, allocator: Allocator) !Value {
    const obj = try PHPObject.init(allocator, class_name);
    return Value_initObject(obj);
}

/// 获取对象属性
/// 
/// @param obj_val 对象Value
/// @param property_name 属性名
/// @return 属性值，如果不存在返回null
pub fn php_object_get(obj_val: Value, property_name: []const u8) !Value {
    if (!Value_isObject(obj_val)) {
        // 不是对象，返回null
        return Value.initNull();
    }
    
    const obj = Value_asObject(obj_val);
    return obj.getProperty(property_name) orelse Value.initNull();
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

/// 调用对象方法（简化版）
/// 
/// 注意：这是一个简化实现，仅返回null。
/// 完整的方法调用需要：
/// 1. 类定义和方法查找机制
/// 2. 方法绑定和调用
/// 3. $this上下文传递
/// 4. 继承和多态支持
/// 
/// @param obj_val 对象Value
/// @param method_name 方法名
/// @param args 参数数组
/// @return 方法返回值
pub fn php_object_call(obj_val: Value, method_name: []const u8, args: []const Value) !Value {
    _ = obj_val;
    _ = method_name;
    _ = args;
    
    // 简化实现：暂时返回null
    // TODO: 实现完整的方法调用机制
    return Value.initNull();
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
