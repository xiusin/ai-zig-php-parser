//! 类型检查和转换核心函数实现
//!
//! 提供与执行模式无关的类型操作核心逻辑。
//!
//! @ownership NON-OWNING
//! @thread-safety ISOLATED

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const CoreContext = common.CoreContext;

/// PHP 值类型枚举
pub const PHPType = enum {
    null,
    boolean,
    integer,
    float,
    string,
    array,
    object,
    resource,
    callable,

    /// 转换为 PHP 类型名称字符串
    pub fn toName(self: PHPType) []const u8 {
        return switch (self) {
            .null => "NULL",
            .boolean => "boolean",
            .integer => "integer",
            .float => "double",
            .string => "string",
            .array => "array",
            .object => "object",
            .resource => "resource",
            .callable => "callable",
        };
    }
};

/// intval - 转换为整数
/// @param str 字符串
/// @param base 进制（默认10）
/// @return 整数值
pub fn intval(str: []const u8, base: u8) i64 {
    if (str.len == 0) return 0;
    
    var s = std.mem.trim(u8, str, " \t\n\r");
    if (s.len == 0) return 0;

    var negative = false;
    if (s[0] == '-') {
        negative = true;
        s = s[1..];
    } else if (s[0] == '+') {
        s = s[1..];
    }

    if (s.len == 0) return 0;

    // 如果包含小数点，先尝试解析为浮点数
    if (std.mem.indexOf(u8, s, ".") != null) {
        if (std.fmt.parseFloat(f64, if (negative) str else s)) |float_val| {
            return @intFromFloat(float_val);
        } else |_| {
            // 浮点数解析失败，尝试部分解析
            const result = parsePartialInt(s, 10);
            return if (negative) -result else result;
        }
    }

    const actual_base: u8 = determineBase(s, base);
    const parse_str = skipBasePrefix(s, actual_base);

    const result = std.fmt.parseInt(i64, parse_str, actual_base) catch {
        return parsePartialInt(parse_str, actual_base);
    };

    return if (negative) -result else result;
}

fn determineBase(s: []const u8, base: u8) u8 {
    if (base != 0) return base;
    if (s.len < 2) return 10;
    if (s[0] == '0') {
        if (s[1] == 'x' or s[1] == 'X') return 16;
        if (s[1] == 'b' or s[1] == 'B') return 2;
        if (s[1] == 'o' or s[1] == 'O') return 8;
        return 8;
    }
    return 10;
}

fn skipBasePrefix(s: []const u8, base: u8) []const u8 {
    if (s.len < 2) return s;
    if (s[0] == '0') {
        if ((base == 16 and (s[1] == 'x' or s[1] == 'X')) or
            (base == 2 and (s[1] == 'b' or s[1] == 'B')) or
            (base == 8 and (s[1] == 'o' or s[1] == 'O')))
        {
            return s[2..];
        }
    }
    return s;
}

fn parsePartialInt(s: []const u8, base: u8) i64 {
    var result: i64 = 0;
    for (s) |c| {
        const digit = charToDigit(c, base) orelse break;
        result = result * @as(i64, base) + digit;
    }
    return result;
}

fn charToDigit(c: u8, base: u8) ?i64 {
    const digit: i64 = if (c >= '0' and c <= '9')
        c - '0'
    else if (c >= 'a' and c <= 'f')
        c - 'a' + 10
    else if (c >= 'A' and c <= 'F')
        c - 'A' + 10
    else
        return null;
    
    return if (digit < base) digit else null;
}

/// floatval - 转换为浮点数
/// @param str 字符串
/// @return 浮点数值
pub fn floatval(str: []const u8) f64 {
    if (str.len == 0) return 0.0;
    
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    if (trimmed.len == 0) return 0.0;

    return std.fmt.parseFloat(f64, trimmed) catch {
        return parsePartialFloat(trimmed);
    };
}

fn parsePartialFloat(s: []const u8) f64 {
    var result: f64 = 0.0;
    var decimal_place: f64 = 0.0;
    var negative = false;
    var i: usize = 0;

    if (s.len > 0 and s[0] == '-') {
        negative = true;
        i = 1;
    } else if (s.len > 0 and s[0] == '+') {
        i = 1;
    }

    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c >= '0' and c <= '9') {
            if (decimal_place == 0.0) {
                result = result * 10.0 + @as(f64, @floatFromInt(c - '0'));
            } else {
                result += @as(f64, @floatFromInt(c - '0')) * decimal_place;
                decimal_place /= 10.0;
            }
        } else if (c == '.' and decimal_place == 0.0) {
            decimal_place = 0.1;
        } else {
            break;
        }
    }

    return if (negative) -result else result;
}

/// boolval - 转换为布尔值
/// @param str 字符串
/// @return 布尔值（空字符串和 "0" 为 false）
pub fn boolval_str(str: []const u8) bool {
    if (str.len == 0) return false;
    if (str.len == 1 and str[0] == '0') return false;
    return true;
}

/// boolval_int - 整数转布尔
/// @param value 整数
/// @return 布尔值（0 为 false）
pub fn boolval_int(value: i64) bool {
    return value != 0;
}

/// boolval_float - 浮点数转布尔
/// @param value 浮点数
/// @return 布尔值（0.0 和 NaN 为 false）
pub fn boolval_float(value: f64) bool {
    return value != 0.0 and !std.math.isNan(value);
}

/// strval_int - 整数转字符串
/// @param ctx 上下文
/// @param value 整数
/// @return 字符串（调用者负责释放）
pub fn strval_int(ctx: *CoreContext, value: i64) ![]u8 {
    return try std.fmt.allocPrint(ctx.allocator, "{d}", .{value});
}

/// strval_float - 浮点数转字符串
/// @param ctx 上下文
/// @param value 浮点数
/// @return 字符串（调用者负责释放）
pub fn strval_float(ctx: *CoreContext, value: f64) ![]u8 {
    if (std.math.isNan(value)) {
        return try ctx.allocator.dupe(u8, "NAN");
    }
    if (std.math.isInf(value)) {
        return try ctx.allocator.dupe(u8, if (value > 0) "INF" else "-INF");
    }
    return try std.fmt.allocPrint(ctx.allocator, "{d}", .{value});
}

/// strval_bool - 布尔值转字符串
/// @param ctx 上下文
/// @param value 布尔值
/// @return 字符串（调用者负责释放）
pub fn strval_bool(ctx: *CoreContext, value: bool) ![]u8 {
    return try ctx.allocator.dupe(u8, if (value) "1" else "");
}

/// is_numeric - 检查字符串是否为数字
/// @param str 字符串
/// @return 是否为有效数字
pub fn is_numeric(str: []const u8) bool {
    if (str.len == 0) return false;
    
    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    if (trimmed.len == 0) return false;

    _ = std.fmt.parseInt(i64, trimmed, 10) catch {
        _ = std.fmt.parseFloat(f64, trimmed) catch {
            return false;
        };
        return true;
    };
    return true;
}

// ============================================================================
// 测试
// ============================================================================

test "intval basic" {
    try std.testing.expectEqual(@as(i64, 42), intval("42", 10));
    try std.testing.expectEqual(@as(i64, -42), intval("-42", 10));
    try std.testing.expectEqual(@as(i64, 0), intval("", 10));
    try std.testing.expectEqual(@as(i64, 123), intval("  123  ", 10));
}

test "intval with base" {
    try std.testing.expectEqual(@as(i64, 255), intval("0xff", 0));
    try std.testing.expectEqual(@as(i64, 7), intval("0b111", 0));
    try std.testing.expectEqual(@as(i64, 8), intval("010", 0));
}

test "intval partial" {
    try std.testing.expectEqual(@as(i64, 123), intval("123abc", 10));
    try std.testing.expectEqual(@as(i64, 0), intval("abc123", 10));
}

test "floatval" {
    try std.testing.expectEqual(@as(f64, 3.14), floatval("3.14"));
    try std.testing.expectEqual(@as(f64, -3.14), floatval("-3.14"));
    try std.testing.expectEqual(@as(f64, 0.0), floatval(""));
    try std.testing.expectEqual(@as(f64, 3.0), floatval("3abc"));
}

test "boolval_str" {
    try std.testing.expect(!boolval_str(""));
    try std.testing.expect(!boolval_str("0"));
    try std.testing.expect(boolval_str("1"));
    try std.testing.expect(boolval_str("hello"));
}

test "strval_int" {
    var ctx = CoreContext.init(std.testing.allocator);
    
    const result = try strval_int(&ctx, 42);
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "strval_float" {
    var ctx = CoreContext.init(std.testing.allocator);
    
    const result = try strval_float(&ctx, 3.14);
    defer ctx.allocator.free(result);
    try std.testing.expect(std.mem.startsWith(u8, result, "3.14"));
}

test "is_numeric" {
    try std.testing.expect(is_numeric("42"));
    try std.testing.expect(is_numeric("3.14"));
    try std.testing.expect(is_numeric("-123"));
    try std.testing.expect(!is_numeric("abc"));
    try std.testing.expect(!is_numeric(""));
}
