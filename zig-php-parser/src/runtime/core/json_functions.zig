//! JSON 核心函数实现
//!
//! 提供与执行模式无关的 JSON 编解码核心逻辑。
//!
//! @ownership TRANSFER (返回的字符串由调用者负责释放)
//! @thread-safety ISOLATED

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const CoreContext = common.CoreContext;
const CoreError = common.CoreError;

/// JSON 编码选项
pub const JsonEncodeOptions = struct {
    pretty_print: bool = false,
    escape_unicode: bool = false,
    escape_slashes: bool = false,
    numeric_check: bool = false,
};

/// JSON 解码选项
pub const JsonDecodeOptions = struct {
    depth: u32 = 512,
    associative: bool = true,
};

/// JSON 错误码
pub const JsonError = enum(i32) {
    none = 0,
    depth = 1,
    state_mismatch = 2,
    ctrl_char = 3,
    syntax = 4,
    utf8 = 5,
    recursion = 6,
    inf_or_nan = 7,
    unsupported_type = 8,
};

/// json_encode_string - 编码字符串为 JSON 字符串
/// @param ctx 上下文
/// @param str 源字符串
/// @param options 编码选项
/// @return JSON 字符串（调用者负责释放）
pub fn json_encode_string(
    ctx: *CoreContext,
    str: []const u8,
    options: JsonEncodeOptions,
) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(ctx.allocator);

    try result.append(ctx.allocator, '"');

    for (str) |c| {
        switch (c) {
            '"' => try result.appendSlice(ctx.allocator, "\\\""),
            '\\' => try result.appendSlice(ctx.allocator, "\\\\"),
            '\n' => try result.appendSlice(ctx.allocator, "\\n"),
            '\r' => try result.appendSlice(ctx.allocator, "\\r"),
            '\t' => try result.appendSlice(ctx.allocator, "\\t"),
            '/' => {
                if (options.escape_slashes) {
                    try result.appendSlice(ctx.allocator, "\\/");
                } else {
                    try result.append(ctx.allocator, '/');
                }
            },
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch {
                        return error.OutOfMemory;
                    };
                    try result.appendSlice(ctx.allocator, slice);
                } else if (options.escape_unicode and c >= 0x80) {
                    var buf: [6]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch {
                        return error.OutOfMemory;
                    };
                    try result.appendSlice(ctx.allocator, slice);
                } else {
                    try result.append(ctx.allocator, c);
                }
            },
        }
    }

    try result.append(ctx.allocator, '"');
    return result.toOwnedSlice(ctx.allocator);
}

/// json_encode_int - 编码整数为 JSON
/// @param ctx 上下文
/// @param value 整数值
/// @return JSON 字符串（调用者负责释放）
pub fn json_encode_int(ctx: *CoreContext, value: i64) ![]u8 {
    return try std.fmt.allocPrint(ctx.allocator, "{d}", .{value});
}

/// json_encode_float - 编码浮点数为 JSON
/// @param ctx 上下文
/// @param value 浮点值
/// @return JSON 字符串（调用者负责释放）
pub fn json_encode_float(ctx: *CoreContext, value: f64) ![]u8 {
    if (std.math.isNan(value) or std.math.isInf(value)) {
        return try ctx.allocator.dupe(u8, "null");
    }
    return try std.fmt.allocPrint(ctx.allocator, "{d}", .{value});
}

/// json_encode_bool - 编码布尔值为 JSON
/// @param ctx 上下文
/// @param value 布尔值
/// @return JSON 字符串（调用者负责释放）
pub fn json_encode_bool(ctx: *CoreContext, value: bool) ![]u8 {
    return try ctx.allocator.dupe(u8, if (value) "true" else "false");
}

/// json_encode_null - 编码 null 为 JSON
/// @param ctx 上下文
/// @return JSON 字符串（调用者负责释放）
pub fn json_encode_null(ctx: *CoreContext) ![]u8 {
    return try ctx.allocator.dupe(u8, "null");
}

/// json_decode_string - 解析 JSON 字符串
/// @param json_str JSON 字符串
/// @return 解码后的字符串切片（指向原始数据）
pub fn json_decode_string(json_str: []const u8) ![]const u8 {
    if (json_str.len < 2) return CoreError.InvalidArgument;
    if (json_str[0] != '"' or json_str[json_str.len - 1] != '"') {
        return CoreError.InvalidArgument;
    }
    return json_str[1 .. json_str.len - 1];
}

/// json_decode_int - 解析 JSON 整数
/// @param json_str JSON 字符串
/// @return 整数值
pub fn json_decode_int(json_str: []const u8) !i64 {
    return std.fmt.parseInt(i64, json_str, 10) catch {
        return CoreError.InvalidArgument;
    };
}

/// json_decode_float - 解析 JSON 浮点数
/// @param json_str JSON 字符串
/// @return 浮点值
pub fn json_decode_float(json_str: []const u8) !f64 {
    return std.fmt.parseFloat(f64, json_str) catch {
        return CoreError.InvalidArgument;
    };
}

/// json_decode_bool - 解析 JSON 布尔值
/// @param json_str JSON 字符串
/// @return 布尔值
pub fn json_decode_bool(json_str: []const u8) !bool {
    if (std.mem.eql(u8, json_str, "true")) return true;
    if (std.mem.eql(u8, json_str, "false")) return false;
    return CoreError.InvalidArgument;
}

/// json_decode_null - 检查是否为 JSON null
/// @param json_str JSON 字符串
/// @return 是否为 null
pub fn json_decode_null(json_str: []const u8) bool {
    return std.mem.eql(u8, json_str, "null");
}

/// json_last_error - 获取最后的 JSON 错误
/// 注意：实际实现需要线程局部存储错误状态
/// @return 错误码
pub fn json_last_error() JsonError {
    return .none;
}

/// json_last_error_msg - 获取最后的 JSON 错误消息
/// @return 错误消息
pub fn json_last_error_msg() []const u8 {
    return "No error";
}

// ============================================================================
// 测试
// ============================================================================

test "json_encode_string basic" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try json_encode_string(&ctx, "hello", .{});
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("\"hello\"", result);
}

test "json_encode_string with escapes" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try json_encode_string(&ctx, "hello\nworld", .{});
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("\"hello\\nworld\"", result);
}

test "json_encode_int" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try json_encode_int(&ctx, 42);
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "json_encode_float" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try json_encode_float(&ctx, 3.14);
    defer ctx.allocator.free(result);
    try std.testing.expect(std.mem.startsWith(u8, result, "3.14"));
}

test "json_encode_bool" {
    var ctx = CoreContext.init(std.testing.allocator);

    const true_result = try json_encode_bool(&ctx, true);
    defer ctx.allocator.free(true_result);
    try std.testing.expectEqualStrings("true", true_result);

    const false_result = try json_encode_bool(&ctx, false);
    defer ctx.allocator.free(false_result);
    try std.testing.expectEqualStrings("false", false_result);
}

test "json_decode_int" {
    try std.testing.expectEqual(@as(i64, 42), try json_decode_int("42"));
    try std.testing.expectEqual(@as(i64, -123), try json_decode_int("-123"));
}

test "json_decode_float" {
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.14),
        try json_decode_float("3.14"),
        0.001,
    );
}

test "json_decode_bool" {
    try std.testing.expect(try json_decode_bool("true"));
    try std.testing.expect(!try json_decode_bool("false"));
}

test "json_decode_null" {
    try std.testing.expect(json_decode_null("null"));
    try std.testing.expect(!json_decode_null("false"));
}
