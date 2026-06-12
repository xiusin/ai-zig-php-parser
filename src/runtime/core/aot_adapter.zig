//! AOT 适配器层
//!
//! 将核心函数适配到 AOT 编译模式。
//! 提供 C ABI 兼容的函数导出，供 AOT 编译的代码调用。
//!
//! @ownership TRANSFER (返回的内存由调用者负责释放)
//! @thread-safety ISOLATED

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("root.zig");
const CoreContext = core.CoreContext;

/// 全局 allocator（AOT 运行时初始化）
var global_allocator: ?Allocator = null;

/// 初始化 AOT 运行时
pub export fn aot_runtime_init() void {
    if (global_allocator == null) {
        global_allocator = std.heap.page_allocator;
    }
}

/// 清理 AOT 运行时
pub export fn aot_runtime_deinit() void {
    global_allocator = null;
}

/// 获取 allocator
fn getAllocator() Allocator {
    return global_allocator orelse std.heap.page_allocator;
}

/// 创建核心上下文
fn createContext() CoreContext {
    return CoreContext.init(getAllocator());
}

// ============================================================================
// 字符串函数导出
// ============================================================================

/// strlen - 导出版本
pub export fn aot_strlen(str_ptr: [*]const u8, str_len: usize) i64 {
    const str = str_ptr[0..str_len];
    return core.string.strlen(str);
}

/// strtoupper - 导出版本
pub export fn aot_strtoupper(
    str_ptr: [*]const u8,
    str_len: usize,
    out_len: *usize,
) ?[*]u8 {
    const str = str_ptr[0..str_len];
    var ctx = createContext();
    
    const result = core.string.strtoupper(&ctx, str) catch return null;
    out_len.* = result.len;
    return result.ptr;
}

/// strtolower - 导出版本
pub export fn aot_strtolower(
    str_ptr: [*]const u8,
    str_len: usize,
    out_len: *usize,
) ?[*]u8 {
    const str = str_ptr[0..str_len];
    var ctx = createContext();
    
    const result = core.string.strtolower(&ctx, str) catch return null;
    out_len.* = result.len;
    return result.ptr;
}

/// strpos - 导出版本
pub export fn aot_strpos(
    haystack_ptr: [*]const u8,
    haystack_len: usize,
    needle_ptr: [*]const u8,
    needle_len: usize,
    offset: usize,
) i64 {
    const haystack = haystack_ptr[0..haystack_len];
    const needle = needle_ptr[0..needle_len];
    return core.string.strpos(haystack, needle, offset);
}

/// str_contains - 导出版本
pub export fn aot_str_contains(
    haystack_ptr: [*]const u8,
    haystack_len: usize,
    needle_ptr: [*]const u8,
    needle_len: usize,
) bool {
    const haystack = haystack_ptr[0..haystack_len];
    const needle = needle_ptr[0..needle_len];
    return core.string.str_contains(haystack, needle);
}

/// substr - 导出版本
pub export fn aot_substr(
    str_ptr: [*]const u8,
    str_len: usize,
    start: i64,
    length: i64,
    has_length: bool,
    out_len: *usize,
) ?[*]u8 {
    const str = str_ptr[0..str_len];
    var ctx = createContext();
    
    const len_param: ?i64 = if (has_length) length else null;
    const result = core.string.substr(&ctx, str, start, len_param) catch return null;
    out_len.* = result.len;
    return result.ptr;
}

/// trim - 导出版本
pub export fn aot_trim(
    str_ptr: [*]const u8,
    str_len: usize,
    out_start: *usize,
    out_len: *usize,
) void {
    const str = str_ptr[0..str_len];
    const trimmed = core.string.trim(str);
    
    out_start.* = @intFromPtr(trimmed.ptr) - @intFromPtr(str_ptr);
    out_len.* = trimmed.len;
}

// ============================================================================
// 数学函数导出
// ============================================================================

/// abs_int - 导出版本
pub export fn aot_abs_int(value: i64) i64 {
    const result = core.math.abs(.{ .int = value });
    return result.int;
}

/// abs_float - 导出版本
pub export fn aot_abs_float(value: f64) f64 {
    const result = core.math.abs(.{ .float = value });
    return result.float;
}

/// round - 导出版本
pub export fn aot_round(value: f64, precision: i32) f64 {
    return core.math.round(value, precision);
}

/// floor - 导出版本
pub export fn aot_floor(value: f64) f64 {
    return core.math.floor(value);
}

/// ceil - 导出版本
pub export fn aot_ceil(value: f64) f64 {
    return core.math.ceil(value);
}

/// sqrt - 导出版本
pub export fn aot_sqrt(value: f64) f64 {
    return core.math.sqrt(value);
}

/// pow - 导出版本
pub export fn aot_pow(base: f64, exponent: f64) f64 {
    return core.math.pow(base, exponent);
}

/// min - 导出版本
pub export fn aot_min(a: f64, b: f64) f64 {
    return core.math.min(a, b);
}

/// max - 导出版本
pub export fn aot_max(a: f64, b: f64) f64 {
    return core.math.max(a, b);
}

/// sin - 导出版本
pub export fn aot_sin(value: f64) f64 {
    return core.math.sin(value);
}

/// cos - 导出版本
pub export fn aot_cos(value: f64) f64 {
    return core.math.cos(value);
}

/// tan - 导出版本
pub export fn aot_tan(value: f64) f64 {
    return core.math.tan(value);
}

/// log - 导出版本
pub export fn aot_log(value: f64) f64 {
    return core.math.log(value);
}

/// exp - 导出版本
pub export fn aot_exp(value: f64) f64 {
    return core.math.exp(value);
}

// ============================================================================
// 时间函数导出
// ============================================================================

/// time - 导出版本
pub export fn aot_time() i64 {
    return core.time.time();
}

/// microtime_float - 导出版本
pub export fn aot_microtime_float() f64 {
    return core.time.microtime_float();
}

/// date - 导出版本
pub export fn aot_date(
    format_ptr: [*]const u8,
    format_len: usize,
    timestamp: i64,
    has_timestamp: bool,
    out_len: *usize,
) ?[*]u8 {
    const format = format_ptr[0..format_len];
    var ctx = createContext();
    
    const ts: ?i64 = if (has_timestamp) timestamp else null;
    const result = core.time.date(&ctx, format, ts) catch return null;
    out_len.* = result.len;
    return result.ptr;
}

// ============================================================================
// 类型函数导出
// ============================================================================

/// intval - 导出版本
pub export fn aot_intval(
    str_ptr: [*]const u8,
    str_len: usize,
    base: u8,
) i64 {
    const str = str_ptr[0..str_len];
    return core.types.intval(str, base);
}

/// floatval - 导出版本
pub export fn aot_floatval(str_ptr: [*]const u8, str_len: usize) f64 {
    const str = str_ptr[0..str_len];
    return core.types.floatval(str);
}

/// is_numeric - 导出版本
pub export fn aot_is_numeric(str_ptr: [*]const u8, str_len: usize) bool {
    const str = str_ptr[0..str_len];
    return core.types.is_numeric(str);
}

// ============================================================================
// 随机数函数导出
// ============================================================================

/// srand - 导出版本
pub export fn aot_srand(seed: u64) void {
    core.random.srand(seed);
}

/// rand - 导出版本
pub export fn aot_rand(min_val: i64, max_val: i64, has_range: bool) i64 {
    if (has_range) {
        return core.random.rand(min_val, max_val);
    } else {
        return core.random.rand(null, null);
    }
}

/// random_int - 导出版本
pub export fn aot_random_int(min_val: i64, max_val: i64) i64 {
    return core.random.random_int(min_val, max_val) catch 0;
}

/// random_bytes - 导出版本
pub export fn aot_random_bytes(length: usize, out_len: *usize) ?[*]u8 {
    var ctx = createContext();
    const result = core.random.random_bytes(&ctx, length) catch return null;
    out_len.* = result.len;
    return result.ptr;
}

// ============================================================================
// 内存管理导出
// ============================================================================

/// 释放分配的内存
pub export fn aot_free(ptr: [*]u8, len: usize) void {
    const allocator = getAllocator();
    allocator.free(ptr[0..len]);
}

/// 分配内存
pub export fn aot_alloc(len: usize) ?[*]u8 {
    const allocator = getAllocator();
    const result = allocator.alloc(u8, len) catch return null;
    return result.ptr;
}
