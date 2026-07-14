const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

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
    pub const SIGN_BIT: u64 = nanbox_abi.SIGN_BIT;
    pub const QNAN: u64 = nanbox_abi.QNAN;

    // 简单类型标签
    pub const TAG_NIL: u64 = nanbox_abi.TAG_NIL;
    pub const TAG_FALSE: u64 = nanbox_abi.TAG_FALSE;
    pub const TAG_TRUE: u64 = nanbox_abi.TAG_TRUE;
    pub const TAG_MISSING: u64 = 4;
    pub const TAG_INT_MARKER: u64 = nanbox_abi.TAG_INT_MARKER;

    // 指针类型标记
    pub const TAG_PTR: u64 = nanbox_abi.TAG_PTR;
    pub const TYPE_MASK: u64 = nanbox_abi.TYPE_MASK;
    pub const TYPE_STRING: u64 = nanbox_abi.TYPE_STRING;
    pub const TYPE_ARRAY: u64 = nanbox_abi.TYPE_ARRAY;
    pub const TYPE_OBJECT: u64 = nanbox_abi.TYPE_OBJECT;
    pub const TYPE_FUNCTION: u64 = nanbox_abi.TYPE_FUNCTION;
    pub const TYPE_REF: u64 = nanbox_abi.TYPE_REF;
    pub const TYPE_BIGINT: u64 = nanbox_abi.TYPE_BIGINT;
    pub const TYPE_RESOURCE: u64 = nanbox_abi.TYPE_RESOURCE;

    // 堆装箱大整数（超出48位范围）
    pub const BoxedInt = struct {
        ref_count: u32,
        value: i64,
    };

    // PHP 资源类型（文件句柄等）
    pub const PHPResource = struct {
        ref_count: u32,
        file_handle: ?*std.Io.File, // 堆分配的文件句柄（null 表示虚拟句柄或已关闭）
        type_name: []const u8, // 资源类型名（如 "stream"）
        closed: bool = false, // 是否已关闭（fclose 后设为 true）

        pub fn retain(self: *PHPResource) void {
            self.ref_count += 1;
        }

        pub fn release(self: *PHPResource, allocator: Allocator) void {
            if (self.ref_count > 0) {
                self.ref_count -= 1;
                if (self.ref_count == 0) {
                    if (self.file_handle) |fh| {
                        allocator.destroy(fh);
                    }
                    allocator.destroy(self);
                }
            }
        }
    };

    // 48位整数常量
    pub const INT48_MASK: u64 = nanbox_abi.INT48_MASK;
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

    pub fn initMissing() Value {
        return .{ .val = QNAN | TAG_MISSING };
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
        // 超出48位范围：堆装箱存储，保留完整i64精度
        const boxed = runtime_allocator.create(BoxedInt) catch {
            // 分配失败：降级为浮点数（有精度损失）
            return .{ .val = @bitCast(@as(f64, @floatFromInt(i))) };
        };
        boxed.* = .{ .ref_count = 1, .value = i };
        const addr = @intFromPtr(boxed);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_BIGINT) };
    }

    /// 创建浮点数值
    pub fn initFloat(f: f64) Value {
        return .{ .val = @bitCast(f) };
    }

    /// 创建字符串值
    pub fn initString(str: *PHPString) Value {
        const addr = @intFromPtr(str);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_STRING) };
    }

    /// 创建数组值
    pub fn initArray(arr: *PHPArray) Value {
        const addr = @intFromPtr(arr);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_ARRAY) };
    }

    /// 创建函数值
    pub fn initFunction(func: *PHPClosure) Value {
        const addr = @intFromPtr(func);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_FUNCTION) };
    }

    /// 创建引用值（直接指针，不推荐用于数组元素）
    pub fn initRef(ptr: *Value) Value {
        const addr = @intFromPtr(ptr);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_REF) };
    }

    /// 创建引用值（使用RefWrapper，推荐用于数组元素）
    pub fn initRefWrapper(wrapper: *RefWrapper) Value {
        const addr = @intFromPtr(wrapper);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_REF) };
    }

    /// 创建资源值
    pub fn initResource(res: *PHPResource) Value {
        const addr = @intFromPtr(res);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_RESOURCE) };
    }

    // ========================================================================
    // 类型检查
    // ========================================================================

    pub fn isNull(self: Value) bool {
        return self.val == (QNAN | TAG_NIL);
    }

    pub fn isMissing(self: Value) bool {
        return self.val == (QNAN | TAG_MISSING);
    }

    pub fn isBool(self: Value) bool {
        return self.val == (QNAN | TAG_FALSE) or self.val == (QNAN | TAG_TRUE);
    }

    pub fn isInt(self: Value) bool {
        if ((self.val & (SIGN_BIT | QNAN)) == TAG_INT_MARKER) return true;
        // 检查堆装箱大整数
        if ((self.val & (SIGN_BIT | QNAN)) == QNAN) {
            return (self.val & TYPE_MASK) == TYPE_BIGINT;
        }
        return false;
    }

    pub fn isBigInt(self: Value) bool {
        return (self.val & (SIGN_BIT | QNAN)) == QNAN and (self.val & TYPE_MASK) == TYPE_BIGINT;
    }

    pub fn isFloat(self: Value) bool {
        if ((self.val & QNAN) != QNAN) return true;
        return false;
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

    pub fn isRef(self: Value) bool {
        // 首先检查是否是指针类型（QNAN位设置，但SIGN_BIT未设置）
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        // 然后检查类型标签
        return (self.val & TYPE_MASK) == TYPE_REF;
    }

    pub fn isResource(self: Value) bool {
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        if ((self.val & TYPE_MASK) != TYPE_RESOURCE) return false;
        // 已关闭的 resource 不再是有效 resource
        return !self.asResource().closed;
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
        // 堆装箱大整数
        if (self.isBigInt()) {
            const boxed: *BoxedInt = @ptrFromInt(nanbox_abi.decodePtr(self.val));
            return boxed.value;
        }
        // 可能是浮点数存储的大整数（降级路径）
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
        const ptr = nanbox_abi.decodePtr(self.val);
        const str: *PHPString = @ptrFromInt(ptr);

        // 检测内存破坏
        if (str.length > 1024 * 1024 * 100) {
            std.debug.print("ERROR: PHPString corrupted! length={d} (0x{x})\n", .{ str.length, str.length });
            // 返回空字符串避免崩溃
            return @constCast(&EMPTY_STRING);
        }

        return str;
    }

    pub fn asArray(self: Value) *PHPArray {
        // 如果是引用，先解引用
        if (self.isRef()) {
            const ref_ptr = self.asRef();
            return ref_ptr.asArray();
        }
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    pub fn asFunction(self: Value) *PHPClosure {
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    pub fn asResource(self: Value) *PHPResource {
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    pub fn asRef(self: Value) *Value {
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    pub fn asRefWrapper(self: Value) *RefWrapper {
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    /// 获取数组元素的引用（用于引用返回）
    pub fn getArrayElementRef(arr: *PHPArray, key: ArrayKey, allocator: Allocator) !*Value {
        const entry = arr.data.getPtr(key) orelse {
            // 如果元素不存在，创建一个 null 值
            try arr.data.put(allocator, key, Value.initNull());
            return arr.data.getPtr(key).?;
        };
        return entry;
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
        } else if (self.isFunction()) {
            self.asFunction().retain();
        } else if (self.isBigInt()) {
            const boxed: *BoxedInt = @ptrFromInt(nanbox_abi.decodePtr(self.val));
            boxed.ref_count += 1;
        } else if (self.isResource()) {
            self.asResource().retain();
        }
        return self;
    }

    pub fn release(self: Value, allocator: Allocator) void {
        // 引用不需要释放（只是指针）
        if (self.isRef()) {
            return;
        }
        if (self.isString()) {
            const str = self.asString();
            // 检测破坏
            if (str.length > 1024 * 1024 * 100) {
                std.debug.print("ERROR: Corrupted string in release! length={d}\n", .{str.length});
                return;
            }
            str.release(allocator);
        } else if (self.isArray()) {
            self.asArray().release(allocator);
        } else if (Value_isObject(self)) {
            Value_asObject(self).release();
        } else if (self.isFunction()) {
            self.asFunction().release(allocator);
        } else if (self.isBigInt()) {
            const boxed: *BoxedInt = @ptrFromInt(nanbox_abi.decodePtr(self.val));
            if (boxed.ref_count > 0) {
                boxed.ref_count -= 1;
                if (boxed.ref_count == 0) {
                    allocator.destroy(boxed);
                }
            }
        } else if (self.isResource()) {
            self.asResource().release(allocator);
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
        if (self.isString()) {
            const s = self.asString();
            return s.length > 0 and !std.mem.eql(u8, s.data, "0");
        }
        if (self.isArray()) return self.asArray().count() > 0;
        if (self.isResource()) return true;
        return true;
    }

    /// 转换为整数（PHP语义）
    pub fn toInt(self: Value) i64 {
        if (self.isInt()) return self.asInt();
        if (self.isFloat()) {
            const f = self.asFloat();
            // 使用saturating转换避免panic
            if (std.math.isNan(f)) return 0;
            if (f >= @as(f64, @floatFromInt(std.math.maxInt(i64)))) return std.math.maxInt(i64);
            if (f <= @as(f64, @floatFromInt(std.math.minInt(i64)))) return std.math.minInt(i64);
            return @intFromFloat(f);
        }
        if (self.isBool()) return if (self.asBool()) 1 else 0;
        if (self.isNull()) return 0;
        // 字符串转整数：PHP语义（解析数字前缀）
        if (self.isString()) {
            const str = self.asString();
            if (str.length == 0) return 0;

            // PHP行为：解析前导数字，遇到非数字停止
            var result: i64 = 0;
            var i: usize = 0;
            var negative = false;

            // 跳过前导空格
            while (i < str.length and std.ascii.isWhitespace(str.data[i])) : (i += 1) {}

            // 处理符号
            if (i < str.length and (str.data[i] == '+' or str.data[i] == '-')) {
                negative = (str.data[i] == '-');
                i += 1;
            }

            // 解析数字（遇到非数字停止）
            var has_digits = false;
            while (i < str.length and std.ascii.isDigit(str.data[i])) : (i += 1) {
                has_digits = true;
                const digit = str.data[i] - '0';
                result = result * 10 + digit;
            }

            // 如果没有数字，返回0
            if (!has_digits) return 0;

            return if (negative) -result else result;
        }
        // 数组转整数：非空数组返回1，空数组返回0
        if (self.isArray()) {
            const arr = self.asArray();
            return if (arr.count() > 0) 1 else 0;
        }
        return 0;
    }

    /// 转换为浮点数（PHP语义）
    pub fn toFloat(self: Value) f64 {
        if (self.isFloat()) return self.asFloat();
        if (self.isInt()) return @floatFromInt(self.asInt());
        if (self.isBool()) return if (self.asBool()) 1.0 else 0.0;
        if (self.isNull()) return 0.0;
        // 数组转浮点数：非空数组返回1.0，空数组返回0.0
        if (self.isArray()) {
            const arr = self.asArray();
            return if (arr.count() > 0) 1.0 else 0.0;
        }
        if (self.isString()) {
            const str = self.asString();
            if (str.length == 0) return 0.0;

            // PHP行为：解析前导数字（支持浮点数）
            var result: f64 = 0.0;
            var i: usize = 0;
            var negative = false;

            // 跳过前导空格
            while (i < str.length and std.ascii.isWhitespace(str.data[i])) : (i += 1) {}

            // 处理符号
            if (i < str.length and (str.data[i] == '+' or str.data[i] == '-')) {
                negative = (str.data[i] == '-');
                i += 1;
            }

            // 解析整数部分
            var has_digits = false;
            while (i < str.length and std.ascii.isDigit(str.data[i])) : (i += 1) {
                has_digits = true;
                const digit = str.data[i] - '0';
                result = result * 10.0 + @as(f64, @floatFromInt(digit));
            }

            // 解析小数部分
            if (i < str.length and str.data[i] == '.') {
                i += 1;
                var decimal_place: f64 = 0.1;
                while (i < str.length and std.ascii.isDigit(str.data[i])) : (i += 1) {
                    has_digits = true;
                    const digit = str.data[i] - '0';
                    result += @as(f64, @floatFromInt(digit)) * decimal_place;
                    decimal_place *= 0.1;
                }
            }

            // 如果没有数字，返回0
            if (!has_digits) return 0.0;

            return if (negative) -result else result;
        }
        return 0.0;
    }

    /// 转换为字符串（PHP语义）
    /// 注意：返回的字符串引用计数已经+1，调用者负责release
    /// 将Value转换为字符串
    /// PHP 8+行为：数组转字符串抛出异常
    pub fn toString(self: Value, allocator: Allocator) !*PHPString {
        if (self.isNull()) return PHPString.init(allocator, "");
        if (self.isBool()) return PHPString.init(allocator, if (self.asBool()) "1" else "");
        if (self.isInt()) {
            const str = try std.fmt.allocPrint(allocator, "{d}", .{self.asInt()});
            defer allocator.free(str);
            return PHPString.init(allocator, str);
        }
        if (self.isFloat()) {
            var buf: [64]u8 = undefined;
            const str = phpFormatFloat(&buf, self.asFloat());
            return PHPString.init(allocator, str);
        }
        if (self.isString()) {
            // 对于已经是字符串的值，创建一个新副本
            // 这样调用者可以安全地release而不影响原始值
            return PHPString.init(allocator, self.asString().data);
        }
        if (self.isArray()) {
            // PHP 行为：发出 Warning 并返回 "Array"
            emitWarning("Array to string conversion");
            return PHPString.init(allocator, "Array");
        }
        if (self.isFunction()) {
            // 函数转字符串也应该抛出异常（PHP 8+）
            _ = try throwException("Object of class Closure could not be converted to string", allocator);
            return PHPString.init(allocator, "");
        }
        if (Value_isObject(self)) {
            // 对象转字符串：尝试调用__toString()
            // 如果没有__toString()，PHP 8+抛出异常
            return Value_asObject(self).toString(allocator);
        }
        return PHPString.init(allocator, "");
    }
};

// ============================================================================
// Value类型扩展 - 函数/回调支持
// ============================================================================

pub const PHPClosure = struct {
    // 统一函数签名：ctx 可以是 this (Object) 或者 closure (Function) 或者 null
    func: *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value,
    captures: []Value,
    ref_count: usize,
    gc_info: GCInfo,
    allocator: Allocator,
    param_count: u16 = 0,
    required_params: u16 = 0,
    bound_this: Value = Value.initNull(), // Closure::bind/bindTo 绑定的 $this
    bound_scope: ?*const ClassMeta = null, // Closure::bind/bindTo 绑定的作用域类
    is_static: bool = false, // static closure 不能绑定 $this

    pub fn init(
        allocator: Allocator,
        func: *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value,
        captures: []const Value,
    ) !*PHPClosure {
        const f = try allocPHPClosure(allocator);
        errdefer destroyPHPClosure(f, allocator);

        const caps = try allocator.alloc(Value, captures.len);
        errdefer allocator.free(caps);
        @memcpy(caps, captures);

        // Retain captures
        for (caps) |c| {
            _ = c.retain();
        }

        alloc_counters.php_closure_objects += 1;
        alloc_counters.php_closure_live_objects += 1;
        alloc_counters.php_closure_peak_live_objects = @max(
            alloc_counters.php_closure_peak_live_objects,
            alloc_counters.php_closure_live_objects,
        );

        f.* = .{ .func = func, .captures = caps, .ref_count = 1, .gc_info = .{}, .allocator = allocator, .param_count = 0, .required_params = 0, .bound_this = Value.initNull(), .bound_scope = null, .is_static = false };
        return f;
    }

    pub fn retain(self: *PHPClosure) void {
        self.ref_count += 1;
    }

    pub fn release(self: *PHPClosure, allocator: Allocator) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            for (self.captures) |c| {
                c.release(allocator);
            }
            self.bound_this.release(allocator);
            allocator.free(self.captures);
            if (alloc_counters.php_closure_live_objects > 0) {
                alloc_counters.php_closure_live_objects -= 1;
            }
            destroyPHPClosure(self, allocator);
        } else if (!gc_in_progress) {
            gcBufferClosure(self);
        }
    }
};

/// 变量赋值
/// PHP 值语义：若赋值源为共享数组（非引用且 ref_count > 1），
/// 为目标制作一份深拷贝，避免两个变量通过同一底层数组互相影响。
/// 注意：调用者负责释放旧值和 retain 新值。若触发 clone，本函数会撤销调用者的 retain。
pub fn val_assign(target: *Value, value: Value) void {
    if (value.isArray() and !value.isRef()) {
        const arr = value.asArray();
        // 调用者已经执行一次 retain，因此当 ref_count > 1 时，除本次引用外仍有其他持有者，
        // 需要分离（COW）以维持值语义。
        if (arr.ref_count > 1) {
            const cloned = arr.cloneShallow(runtime_allocator) catch {
                target.* = value;
                return;
            };
            // 撤销调用者的 retain（原数组少一个引用）
            arr.release(runtime_allocator);
            target.* = Value.initArray(cloned);
            return;
        }
    }
    target.* = value;
}

/// 引用感知的赋值：如果目标含引用则写穿到堆单元，否则直接赋值
/// @pre  target 指向有效的 Value（可为 Ref 或普通值）
/// @post 新值写入实际存储位置，旧值已 release，新值已 retain
pub fn ref_aware_store(target: *Value, new_val: Value) void {
    const dest = val_deref(target);
    dest.*.release(runtime_allocator);
    _ = new_val.retain();
    dest.* = new_val;
}

/// 变量解引用（跟随完整引用链）
pub fn val_deref(val: *Value) *Value {
    var current = val;
    while (current.isRef()) {
        current = current.asRef();
    }
    return current;
}

pub fn make_ref(ptr: *Value, allocator: Allocator) !Value {
    // 如果变量已经是引用，直接复用同一引用单元（多闭包共享 use(&$var) 场景）
    if (ptr.isRef()) {
        _ = ptr.retain();
        return ptr.*;
    }
    const cell = try allocator.create(Value);
    cell.* = ptr.*;
    _ = cell.retain();
    // 重定向父作用域的存储，使后续 val_deref 读写均经过堆单元
    ptr.*.release(allocator);
    ptr.* = Value.initRef(cell);
    return Value.initRef(cell);
}

const BuiltinFn = *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value;

const builtin_function_map = std.StaticStringMap(BuiltinFn).initComptime(.{
    .{ "strlen", wrapBuiltin_strlen },
    .{ "strtoupper", wrapBuiltin_strtoupper },
    .{ "strtolower", wrapBuiltin_strtolower },
    .{ "str_ireplace", wrapBuiltin_str_ireplace },
    .{ "str_getcsv", wrapBuiltin_str_getcsv },
    .{ "func_get_args", wrapBuiltin_func_get_args },
    .{ "func_get_arg", wrapBuiltin_func_get_arg },
    .{ "func_num_args", wrapBuiltin_func_num_args },
    .{ "memory_get_usage", wrapBuiltin_memory_get_usage },
    .{ "memory_get_peak_usage", wrapBuiltin_memory_get_peak_usage },
    .{ "function_exists", wrapBuiltin_function_exists },
    .{ "gc_enable", wrapBuiltin_gc_enable },
    .{ "gc_collect_cycles", wrapBuiltin_gc_collect_cycles },
    .{ "ini_get", wrapBuiltin_ini_get },
    .{ "getrusage", wrapBuiltin_getrusage },
    .{ "json_decode", wrapBuiltin_json_decode },
    .{ "json_last_error_msg", wrapBuiltin_json_last_error_msg },
    .{ "trim", wrapBuiltin_trim },
    .{ "count", wrapBuiltin_count },
    .{ "sqrt", wrapBuiltin_sqrt },
    .{ "strval", wrapBuiltin_strval },
    .{ "array_map", wrapBuiltin_array_map },
    .{ "array_filter", wrapBuiltin_array_filter },
    .{ "array_reduce", wrapBuiltin_array_reduce },
    .{ "array_walk", wrapBuiltin_array_walk },
    .{ "array_walk_recursive", wrapBuiltin_array_walk_recursive },
    .{ "array_merge", wrapBuiltin_array_merge },
    .{ "array_sum", wrapBuiltin_array_sum },
    .{ "round", wrapBuiltin_round },
    .{ "ob_start", wrapBuiltin_ob_start },
    .{ "ob_gzhandler", wrapBuiltin_ob_gzhandler },
    .{ "usort", wrapBuiltin_usort },
    .{ "select", wrapBuiltin_select },
    .{ "get_class_methods", wrapBuiltin_get_class_methods },
    .{ "get_class_vars", wrapBuiltin_get_class_vars },
    .{ "get_object_vars", wrapBuiltin_get_object_vars },
    .{ "get_called_class", wrapBuiltin_get_called_class },
    .{ "forward_static_call", wrapBuiltin_forward_static_call },
    .{ "forward_static_call_array", wrapBuiltin_forward_static_call_array },
    // 文件系统函数
    .{ "filemtime", wrapBuiltin_filemtime },
    .{ "fileatime", wrapBuiltin_fileatime },
    .{ "filectime", wrapBuiltin_filectime },
    // 网络函数
    .{ "getenv", wrapBuiltin_getenv },
    .{ "gethostbyname", wrapBuiltin_gethostbyname },
    .{ "gethostname", wrapBuiltin_gethostname },
    .{ "ip2long", wrapBuiltin_ip2long },
    .{ "long2ip", wrapBuiltin_long2ip },
    .{ "parse_url", wrapBuiltin_parse_url },
    // 错误处理函数
    .{ "set_error_handler", wrapBuiltin_set_error_handler },
    .{ "restore_error_handler", wrapBuiltin_restore_error_handler },
    .{ "trigger_error", wrapBuiltin_trigger_error },
    .{ "error_reporting", wrapBuiltin_error_reporting },
    // Ctype 字符类型检测函数
    .{ "ctype_alnum", wrapBuiltin_ctype_alnum },
    .{ "ctype_alpha", wrapBuiltin_ctype_alpha },
    .{ "ctype_cntrl", wrapBuiltin_ctype_cntrl },
    .{ "ctype_digit", wrapBuiltin_ctype_digit },
    .{ "ctype_graph", wrapBuiltin_ctype_graph },
    .{ "ctype_lower", wrapBuiltin_ctype_lower },
    .{ "ctype_print", wrapBuiltin_ctype_print },
    .{ "ctype_punct", wrapBuiltin_ctype_punct },
    .{ "ctype_space", wrapBuiltin_ctype_space },
    .{ "ctype_upper", wrapBuiltin_ctype_upper },
    .{ "ctype_xdigit", wrapBuiltin_ctype_xdigit },
    // Mbstring 多字节字符串函数
    .{ "mb_strlen", wrapBuiltin_mb_strlen },
    .{ "mb_substr", wrapBuiltin_mb_substr },
    .{ "mb_strtoupper", wrapBuiltin_mb_strtoupper },
    .{ "mb_strtolower", wrapBuiltin_mb_strtolower },
    // 字符串函数
    .{ "substr_count", wrapBuiltin_substr_count },
    .{ "ucfirst", wrapBuiltin_ucfirst },
    .{ "lcfirst", wrapBuiltin_lcfirst },
    .{ "ucwords", wrapBuiltin_ucwords },
    .{ "strrpos", wrapBuiltin_strrpos },
    .{ "strripos", wrapBuiltin_strripos },
    .{ "str_word_count", wrapBuiltin_str_word_count },
    .{ "substr", wrapBuiltin_substr },
    .{ "strpos", wrapBuiltin_strpos },
    // 数学函数
    .{ "floor", wrapBuiltin_floor },
    .{ "ceil", wrapBuiltin_ceil },
    .{ "sin", wrapBuiltin_sin },
    .{ "cos", wrapBuiltin_cos },
    .{ "tan", wrapBuiltin_tan },
    .{ "log", wrapBuiltin_log },
    .{ "exp", wrapBuiltin_exp },
    .{ "hypot", wrapBuiltin_hypot },
    .{ "pow", wrapBuiltin_pow },
    .{ "min", wrapBuiltin_min },
    .{ "max", wrapBuiltin_max },
    // 字符串函数
    .{ "stripos", wrapBuiltin_stripos },
    .{ "strstr", wrapBuiltin_strstr },
    .{ "str_split", wrapBuiltin_str_split },
    .{ "implode", wrapBuiltin_implode },
    .{ "explode", wrapBuiltin_explode },
    // 回调函数
    .{ "is_callable", wrapBuiltin_is_callable },
    .{ "get_debug_type", wrapBuiltin_get_debug_type },
    .{ "call_user_func", wrapBuiltin_call_user_func },
    .{ "call_user_func_array", wrapBuiltin_call_user_func_array },
    .{ "compact", wrapBuiltin_compact },
    .{ "extract", wrapBuiltin_extract },
    // 字符操作函数
    .{ "ord", wrapBuiltin_ord },
    .{ "chr", wrapBuiltin_chr },
    .{ "md5", wrapBuiltin_md5 },
    .{ "sha1", wrapBuiltin_sha1 },
    .{ "crc32", wrapBuiltin_crc32 },
    .{ "strrev", wrapBuiltin_strrev },
    .{ "ltrim", wrapBuiltin_ltrim },
    .{ "rtrim", wrapBuiltin_rtrim },
    .{ "addslashes", wrapBuiltin_addslashes },
    .{ "stripslashes", wrapBuiltin_stripslashes },
});

fn lookupBuiltinFunction(name: []const u8) ?BuiltinFn {
    return builtin_function_map.get(name);
}

pub fn php_create_closure(name: Value, captures: Value, is_static_val: Value, allocator: Allocator) !Value {
    if (!name.isString()) return error.InvalidClosureName;
    if (!captures.isArray()) return error.InvalidCaptureList;

    const func_name = name.asString().data;
    const caps_arr = captures.asArray();
    const is_static = is_static_val.toBool();

    // Convert PHPArray to []Value slice
    // We need to iterate the array.
    var cap_list = std.ArrayListUnmanaged(Value){ .items = &.{}, .capacity = 0 };
    defer cap_list.deinit(allocator);

    // Assuming captures is a list (indexed 0..N)
    var i: usize = 0;
    while (i < caps_arr.elements.count()) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        if (caps_arr.elements.get(key)) |val| {
            try cap_list.append(allocator, val);
        } else {
            break;
        }
    }

    // Lookup function
    var func_ptr: ?BuiltinFn = null;

    if (user_function_registry) |registry| {
        func_ptr = registry.get(func_name);
    }

    if (func_ptr == null) {
        func_ptr = lookupBuiltinFunction(func_name);
    }

    if (func_ptr == null) return error.UnknownFunction;

    const closure = try PHPClosure.init(allocator, func_ptr.?, cap_list.items);
    // 从元数据注册表设置参数计数
    if (function_meta_registry) |meta_reg| {
        if (meta_reg.get(func_name)) |meta| {
            closure.param_count = meta.param_count;
            closure.required_params = meta.required_params;
        }
    }
    closure.is_static = is_static;
    return Value.initFunction(closure);
}

pub fn php_object_isset(obj_val: Value, property_name_val: Value) !Value {
    if (!Value_isObject(obj_val)) return Value.initBool(!obj_val.isNull());

    const obj = Value_asObject(obj_val);
    const prop_name = if (property_name_val.isString())
        property_name_val.asString().data
    else
        return Value.initBool(false);

    return Value.initBool(obj.hasProperty(prop_name));
}

pub fn php_object_unset(obj_val: Value, property_name_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) return Value.initNull();

    const obj = Value_asObject(obj_val);
    if (property_name_val.isString()) {
        _ = try obj.unsetProperty(property_name_val.asString().data);
        return Value.initNull();
    }

    const property_name = try property_name_val.toString(allocator);
    defer property_name.release(allocator);
    _ = try obj.unsetProperty(property_name.data);
    return Value.initNull();
}

fn wrapBuiltin_strlen(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strlen(args[0]);
}

fn wrapBuiltin_array_merge(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_array_merge(args, allocator);
}

fn wrapBuiltin_array_sum(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_array_sum(args[0]);
}

fn wrapBuiltin_round(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    const precision = if (args.len >= 2) args[1] else Value.initNull();
    const mode = if (args.len >= 3) args[2] else Value.initNull();
    return php_round(args[0], precision, mode);
}

fn wrapBuiltin_usort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_usort(args[0], args[1], allocator);
}

fn wrapBuiltin_strtoupper(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strtoupper(args[0], allocator);
}

fn wrapBuiltin_strtolower(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strtolower(args[0], allocator);
}

fn wrapBuiltin_str_ireplace(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 3) return error.InvalidArgumentCount;
    const count_out = if (args.len >= 4) args[3] else Value.initNull();
    return php_str_ireplace(args[0], args[1], args[2], count_out, allocator);
}

fn wrapBuiltin_str_getcsv(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    if (args.len < 4) emitDeprecatedStrGetcsvEscape();
    const separator = if (args.len >= 2) args[1] else Value.initString(PHPString.initStatic(","));
    const enclosure = if (args.len >= 3) args[2] else Value.initString(PHPString.initStatic("\""));
    const escape = if (args.len >= 4) args[3] else Value.initString(PHPString.initStatic("\\"));
    return php_str_getcsv(args[0], separator, enclosure, escape, allocator);
}

fn wrapBuiltin_func_get_args(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_func_get_args(args, allocator);
}

fn wrapBuiltin_func_get_arg(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_func_get_arg(args[0]);
}

fn wrapBuiltin_func_num_args(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_func_num_args();
}

fn wrapBuiltin_memory_get_usage(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_memory_get_usage(args, allocator);
}

fn wrapBuiltin_memory_get_peak_usage(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_memory_get_peak_usage(args, allocator);
}

fn wrapBuiltin_function_exists(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_function_exists(args, allocator);
}

fn wrapBuiltin_gc_enable(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_gc_enable(args, allocator);
}

fn wrapBuiltin_gc_collect_cycles(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_gc_collect_cycles(args, allocator);
}

fn wrapBuiltin_ini_get(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_ini_get(args, allocator);
}

fn wrapBuiltin_getrusage(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_getrusage(args, allocator);
}

pub fn php_func_get_args(args: []const Value, allocator: Allocator) !Value {
    if (args.len != 0) return error.InvalidArgumentCount;
    const arr = try PHPArray.init(allocator);
    if (current_call_args) |call_args| {
        for (call_args, 0..) |arg, i| {
            try arr.set(allocator, ArrayKey{ .integer = @intCast(i) }, arg);
        }
    }
    return Value.initArray(arr);
}

pub fn php_func_get_arg(index_val: Value) !Value {
    if (!index_val.isInt()) return error.InvalidArgument;
    const call_args = current_call_args orelse return Value.initBool(false);
    const index = index_val.asInt();
    if (index < 0) return Value.initBool(false);
    const idx: usize = @intCast(index);
    if (idx >= call_args.len) return Value.initBool(false);
    return call_args[idx];
}

pub fn php_func_num_args() !Value {
    const call_args = current_call_args orelse return Value.initInt(0);
    return Value.initInt(@intCast(call_args.len));
}

pub fn php_memory_get_usage(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len > 1) return error.InvalidArgumentCount;
    return Value.initInt(@intCast(alloc_counters.live_bytes));
}

pub fn php_memory_get_peak_usage(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len > 1) return error.InvalidArgumentCount;
    return Value.initInt(@intCast(alloc_counters.peak_live_bytes));
}

/// shell_exec - 执行shell命令并返回完整输出
pub fn php_shell_exec(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return Value.initNull();

    const cmd_val = args[0];
    if (!cmd_val.isString()) return Value.initNull();

    const cmd_str = cmd_val.asString().data;

    // 执行命令
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd_str },
        .max_output_bytes = 1024 * 1024,
    }) catch return Value.initNull();

    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    const output = try PHPString.init(allocator, result.stdout);
    return Value.initString(output);
}

/// exec - 执行命令并返回输出数组
/// PHP签名: exec(string $command, array &$output = null, int &$result_code = null): string|false
pub fn php_exec(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return Value.initNull();

    const cmd_val = args[0];
    if (!cmd_val.isString()) return Value.initNull();

    const cmd_str = cmd_val.asString().data;

    // 执行命令
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd_str },
        .max_output_bytes = 1024 * 1024,
    }) catch return Value.initBool(false);

    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    // 将输出按行分割成数组
    const arr = try PHPArray.init(allocator);
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    var idx: i64 = 0;
    var last_line: []const u8 = "";
    while (lines.next()) |line| {
        if (line.len == 0 and lines.peek() == null) break; // 跳过最后的空行
        last_line = line;
        const line_str = try PHPString.init(allocator, line);
        try arr.set(allocator, ArrayKey{ .integer = idx }, Value.initString(line_str));
        idx += 1;
    }

    // 如果有第二个参数（&$output引用），写回输出数组
    if (args.len >= 2) {
        const output_ref = args[1];
        if (output_ref.isRef()) {
            const ptr = output_ref.asRef();
            // 如果引用指向的是数组，追加到现有数组；否则替换为新数组
            if (ptr.isArray()) {
                const existing_arr = ptr.asArray();
                // 追加新行到现有数组
                var new_lines = std.mem.splitScalar(u8, result.stdout, '\n');
                while (new_lines.next()) |line| {
                    if (line.len == 0 and new_lines.peek() == null) break;
                    const line_str = try PHPString.init(allocator, line);
                    try existing_arr.push(allocator, Value.initString(line_str));
                }
            } else {
                // 替换为新数组
                ptr.release(allocator);
                _ = Value.initArray(arr).retain();
                ptr.* = Value.initArray(arr);
            }
        }
    }

    // 如果有第三个参数（&$return_code引用），写回返回码
    if (args.len >= 3) {
        const return_code_ref = args[2];
        if (return_code_ref.isRef()) {
            const ptr = return_code_ref.asRef();
            ptr.release(allocator);
            const exit_code: i64 = @intCast(result.term.Exited);
            ptr.* = Value.initInt(exit_code);
        }
    }

    // 返回最后一行输出
    if (last_line.len > 0) {
        const last_str = try PHPString.init(allocator, last_line);
        return Value.initString(last_str);
    }
    return Value.initString(try PHPString.init(allocator, ""));
}

/// system - 执行命令，输出到stdout，返回最后一行
/// PHP签名: system(string $command, int &$result_code = null): string|false
pub fn php_system(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return Value.initNull();

    const cmd_val = args[0];
    if (!cmd_val.isString()) return Value.initNull();

    const cmd_str = cmd_val.asString().data;

    // 执行命令
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd_str },
        .max_output_bytes = 1024 * 1024,
    }) catch return Value.initBool(false);

    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    // 输出到stdout（模拟PHP的system行为）
    if (result.stdout.len > 0) {
        fileWriteAll(1, result.stdout);
    }

    // 如果有第二个参数（&$return_var引用），写回返回码
    if (args.len >= 2) {
        const return_var_ref = args[1];
        if (return_var_ref.isRef()) {
            const ptr = return_var_ref.asRef();
            ptr.release(allocator);
            const exit_code: i64 = @intCast(result.term.Exited);
            ptr.* = Value.initInt(exit_code);
        }
    }

    // 返回最后一行
    if (result.stdout.len == 0) return Value.initBool(false);

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    var last_line: []const u8 = "";
    while (lines.next()) |line| {
        if (line.len > 0) last_line = line;
    }

    const last_str = try PHPString.init(allocator, last_line);
    return Value.initString(last_str);
}

/// escapeshellarg - 转义shell参数
/// PHP签名: escapeshellarg(string $arg): string
pub fn php_escapeshellarg(arg_val: Value, allocator: Allocator) !Value {
    if (!arg_val.isString()) {
        const str = try arg_val.toString(allocator);
        defer str.release(allocator);
        return php_escapeshellarg(Value.initString(str), allocator);
    }

    const arg = arg_val.asString().data;

    // 计算结果长度：每个单引号需要转义为 '\''，加上首尾的单引号
    var result_len: usize = 2; // 首尾单引号
    for (arg) |c| {
        if (c == '\'') {
            result_len += 4; // '\''
        } else {
            result_len += 1;
        }
    }

    const result = try allocator.alloc(u8, result_len);
    var pos: usize = 0;
    result[pos] = '\'';
    pos += 1;

    for (arg) |c| {
        if (c == '\'') {
            // 替换 ' 为 '\''
            result[pos] = '\'';
            result[pos + 1] = '\\';
            result[pos + 2] = '\'';
            result[pos + 3] = '\'';
            pos += 4;
        } else {
            result[pos] = c;
            pos += 1;
        }
    }

    result[pos] = '\'';

    const php_str = try PHPString.init(allocator, result);
    allocator.free(result);
    return Value.initString(php_str);
}

/// escapeshellcmd - 转义shell命令中的特殊字符
/// PHP签名: escapeshellcmd(string $command): string
pub fn php_escapeshellcmd(cmd_val: Value, allocator: Allocator) !Value {
    if (!cmd_val.isString()) {
        const str = try cmd_val.toString(allocator);
        defer str.release(allocator);
        return php_escapeshellcmd(Value.initString(str), allocator);
    }

    const cmd = cmd_val.asString().data;

    // 需要转义的字符: &#;`|*?~<>^()[]{}$\, \x0A, \xFF, 以及未配对的引号
    const special_chars = "&#;`|*?~<>^()[]{}$\\";

    // 计算结果长度
    var result_len: usize = 0;
    var single_quote_count: usize = 0;
    var double_quote_count: usize = 0;

    for (cmd) |c| {
        if (c == '\'') single_quote_count += 1;
        if (c == '"') double_quote_count += 1;

        var is_special = false;
        for (special_chars) |sc| {
            if (c == sc) {
                is_special = true;
                break;
            }
        }
        if (is_special or c == '\n' or c == 0xFF) {
            result_len += 2; // 添加反斜杠
        } else {
            result_len += 1;
        }
    }

    // 处理未配对的引号
    const escape_single = (single_quote_count % 2) == 1;
    const escape_double = (double_quote_count % 2) == 1;
    if (escape_single) result_len += single_quote_count;
    if (escape_double) result_len += double_quote_count;

    const result = try allocator.alloc(u8, result_len);
    var pos: usize = 0;

    for (cmd) |c| {
        // 检查是否是特殊字符
        var is_special = false;
        for (special_chars) |sc| {
            if (c == sc) {
                is_special = true;
                break;
            }
        }

        if (c == '\'' and escape_single) {
            result[pos] = '\\';
            result[pos + 1] = '\'';
            pos += 2;
        } else if (c == '"' and escape_double) {
            result[pos] = '\\';
            result[pos + 1] = '"';
            pos += 2;
        } else if (is_special or c == '\n' or c == 0xFF) {
            result[pos] = '\\';
            result[pos + 1] = c;
            pos += 2;
        } else {
            result[pos] = c;
            pos += 1;
        }
    }

    const php_str = try PHPString.init(allocator, result[0..pos]);
    allocator.free(result);
    return Value.initString(php_str);
}

/// substr_replace - 替换字符串的子串
pub fn php_substr_replace(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 2) return Value.initNull();

    const str_val = args[0];
    if (!str_val.isString()) return Value.initNull();
    const str = str_val.asString().data;

    const replacement_val = args[1];
    if (!replacement_val.isString()) return Value.initNull();
    const replacement = replacement_val.asString().data;

    const start = if (args.len >= 3) args[2].toInt() else 0;
    const length = if (args.len >= 4) args[3].toInt() else @as(i64, @intCast(str.len));

    // 处理负数索引
    const actual_start = if (start < 0)
        @max(0, @as(i64, @intCast(str.len)) + start)
    else
        @min(start, @as(i64, @intCast(str.len)));

    const actual_length = if (length < 0)
        @max(0, @as(i64, @intCast(str.len)) - actual_start + length)
    else
        @min(length, @as(i64, @intCast(str.len)) - actual_start);

    const start_idx = @as(usize, @intCast(actual_start));
    const end_idx = @as(usize, @intCast(actual_start + actual_length));

    // 构建结果字符串
    var result = try std.ArrayList(u8).initCapacity(allocator, str.len + replacement.len);
    errdefer result.deinit();

    try result.appendSlice(str[0..start_idx]);
    try result.appendSlice(replacement);
    if (end_idx < str.len) {
        try result.appendSlice(str[end_idx..]);
    }

    const output = try PHPString.init(allocator, try result.toOwnedSlice());
    return Value.initString(output);
}
