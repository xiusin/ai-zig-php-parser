//! 字符串核心函数实现
//!
//! 提供与执行模式无关的字符串操作核心逻辑。
//! 所有函数都是纯函数，不依赖全局状态。
//!
//! @ownership TRANSFER (返回的字符串由调用者负责释放)
//! @thread-safety ISOLATED

const std = @import("std");
const Allocator = std.mem.Allocator;
pub const common = @import("common.zig");
const CoreContext = common.CoreContext;
const CoreError = common.CoreError;

/// strlen - 获取字符串字节长度
/// @param str 输入字符串
/// @return 字节长度
pub fn strlen(str: []const u8) i64 {
    return @intCast(str.len);
}

/// substr - 获取子字符串
/// @param ctx 上下文
/// @param str 源字符串
/// @param start 起始位置（支持负数）
/// @param length 长度（可选，支持负数）
/// @return 子字符串（调用者负责释放）
pub fn substr(
    ctx: *CoreContext,
    str: []const u8,
    start: i64,
    length: ?i64,
) ![]u8 {
    const len = str.len;
    if (len == 0) {
        return try ctx.allocator.alloc(u8, 0);
    }

    const start_idx: usize = calcStartIndex(start, len);
    if (start_idx >= len) {
        return try ctx.allocator.alloc(u8, 0);
    }

    const end_idx: usize = calcEndIndex(start_idx, length, len);
    if (start_idx >= end_idx) {
        return try ctx.allocator.alloc(u8, 0);
    }

    const result_len = end_idx - start_idx;
    const result = try ctx.allocator.alloc(u8, result_len);
    @memcpy(result, str[start_idx..end_idx]);
    return result;
}

/// 计算起始索引（处理负数）
fn calcStartIndex(start: i64, len: usize) usize {
    if (start < 0) {
        const abs_start: usize = @intCast(-start);
        return if (abs_start > len) 0 else len - abs_start;
    }
    return @intCast(@min(start, @as(i64, @intCast(len))));
}

/// 计算结束索引
fn calcEndIndex(start_idx: usize, length: ?i64, len: usize) usize {
    if (length) |length_val| {
        if (length_val >= 0) {
            const l: usize = @intCast(length_val);
            return @min(start_idx + l, len);
        } else {
            const abs_len: usize = @intCast(-length_val);
            if (abs_len >= len - start_idx) return start_idx;
            return len - abs_len;
        }
    }
    return len;
}

/// strtoupper_raw - 转换为大写（纯函数版本）
/// @ownership TRANSFER
pub fn strtoupper_raw(allocator: Allocator, str: []const u8) ![]u8 {
    if (str.len == 0) return try allocator.alloc(u8, 0);
    const result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| result[i] = std.ascii.toUpper(c);
    return result;
}

/// strtoupper - 转换为大写（上下文版本）
pub fn strtoupper(ctx: *CoreContext, str: []const u8) ![]u8 {
    return strtoupper_raw(ctx.allocator, str);
}

/// strtolower_raw - 转换为小写（纯函数版本）
/// @ownership TRANSFER
pub fn strtolower_raw(allocator: Allocator, str: []const u8) ![]u8 {
    if (str.len == 0) return try allocator.alloc(u8, 0);
    const result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| result[i] = std.ascii.toLower(c);
    return result;
}

/// strtolower - 转换为小写（上下文版本）
pub fn strtolower(ctx: *CoreContext, str: []const u8) ![]u8 {
    return strtolower_raw(ctx.allocator, str);
}

/// strpos - 查找子字符串位置
/// @param haystack 被搜索字符串
/// @param needle 要查找的子字符串
/// @param offset 起始偏移量
/// @return 位置索引，未找到返回 -1
pub fn strpos(haystack: []const u8, needle: []const u8, offset: usize) i64 {
    if (needle.len == 0) return @intCast(offset);
    if (offset >= haystack.len) return -1;
    if (needle.len > haystack.len - offset) return -1;

    const search_area = haystack[offset..];
    if (std.mem.indexOf(u8, search_area, needle)) |pos| {
        return @intCast(offset + pos);
    }
    return -1;
}

/// str_contains - 检查字符串是否包含子字符串
/// @param haystack 被搜索字符串
/// @param needle 要查找的子字符串
/// @return 是否包含
pub fn str_contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    return std.mem.indexOf(u8, haystack, needle) != null;
}

/// str_starts_with - 检查字符串是否以指定前缀开始
/// @param haystack 被检查字符串
/// @param needle 前缀
/// @return 是否以指定前缀开始
pub fn str_starts_with(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    return std.mem.eql(u8, haystack[0..needle.len], needle);
}

/// str_ends_with - 检查字符串是否以指定后缀结束
/// @param haystack 被检查字符串
/// @param needle 后缀
/// @return 是否以指定后缀结束
pub fn str_ends_with(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    return std.mem.eql(u8, haystack[haystack.len - needle.len ..], needle);
}

/// trim - 去除首尾空白字符
/// @param str 源字符串
/// @return 去除空白后的切片（不分配内存）
pub fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \t\n\r\x0b\x0c");
}

/// ltrim - 去除左侧空白字符
/// @param str 源字符串
/// @return 去除空白后的切片（不分配内存）
pub fn ltrim(str: []const u8) []const u8 {
    return std.mem.trimLeft(u8, str, " \t\n\r\x0b\x0c");
}

/// rtrim - 去除右侧空白字符
/// @param str 源字符串
/// @return 去除空白后的切片（不分配内存）
pub fn rtrim(str: []const u8) []const u8 {
    return std.mem.trimRight(u8, str, " \t\n\r\x0b\x0c");
}

/// strrev_raw - 反转字符串（纯函数版本）
/// @param allocator 分配器
/// @param str 源字符串
/// @return 反转后的字符串（调用者负责释放）
/// @ownership TRANSFER
pub fn strrev_raw(allocator: Allocator, str: []const u8) ![]u8 {
    if (str.len == 0) {
        return try allocator.alloc(u8, 0);
    }
    const result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[str.len - 1 - i] = c;
    }
    return result;
}

/// strrev - 反转字符串（上下文版本）
/// @param ctx 上下文
/// @param str 源字符串
/// @return 反转后的字符串（调用者负责释放）
pub fn strrev(ctx: *CoreContext, str: []const u8) ![]u8 {
    return strrev_raw(ctx.allocator, str);
}

/// str_repeat - 重复字符串
/// @param ctx 上下文
/// @param str 源字符串
/// @param times 重复次数
/// @return 重复后的字符串（调用者负责释放）
pub fn str_repeat(ctx: *CoreContext, str: []const u8, times: usize) ![]u8 {
    if (times == 0 or str.len == 0) {
        return try ctx.allocator.alloc(u8, 0);
    }

    const total_len = str.len * times;
    if (total_len > 100 * 1024 * 1024) {
        return CoreError.StringTooLarge;
    }

    const result = try ctx.allocator.alloc(u8, total_len);
    var offset: usize = 0;
    for (0..times) |_| {
        @memcpy(result[offset .. offset + str.len], str);
        offset += str.len;
    }
    return result;
}

/// ucfirst - 首字母大写
/// @param ctx 上下文
/// @param str 源字符串
/// @return 处理后的字符串（调用者负责释放）
pub fn ucfirst(ctx: *CoreContext, str: []const u8) ![]u8 {
    if (str.len == 0) {
        return try ctx.allocator.alloc(u8, 0);
    }

    const result = try ctx.allocator.alloc(u8, str.len);
    result[0] = std.ascii.toUpper(str[0]);
    if (str.len > 1) {
        @memcpy(result[1..], str[1..]);
    }
    return result;
}

/// lcfirst - 首字母小写
/// @param ctx 上下文
/// @param str 源字符串
/// @return 处理后的字符串（调用者负责释放）
pub fn lcfirst(ctx: *CoreContext, str: []const u8) ![]u8 {
    if (str.len == 0) {
        return try ctx.allocator.alloc(u8, 0);
    }

    const result = try ctx.allocator.alloc(u8, str.len);
    result[0] = std.ascii.toLower(str[0]);
    if (str.len > 1) {
        @memcpy(result[1..], str[1..]);
    }
    return result;
}

/// ord - 获取字符的 ASCII 值
/// @param str 字符串（取第一个字符）
/// @return ASCII 值
pub fn ord(str: []const u8) i64 {
    if (str.len == 0) return 0;
    return @intCast(str[0]);
}

/// chr - 根据 ASCII 值生成字符
/// @param ctx 上下文
/// @param code ASCII 值
/// @return 单字符字符串（调用者负责释放）
pub fn chr(ctx: *CoreContext, code: i64) ![]u8 {
    const result = try ctx.allocator.alloc(u8, 1);
    result[0] = @truncate(@as(u64, @bitCast(code)));
    return result;
}

// ============================================================================
// 测试
// ============================================================================

test "strlen" {
    try std.testing.expectEqual(@as(i64, 5), strlen("hello"));
    try std.testing.expectEqual(@as(i64, 0), strlen(""));
}

test "substr basic" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result1 = try substr(&ctx, "hello world", 0, 5);
    defer ctx.allocator.free(result1);
    try std.testing.expectEqualStrings("hello", result1);

    const result2 = try substr(&ctx, "hello world", 6, null);
    defer ctx.allocator.free(result2);
    try std.testing.expectEqualStrings("world", result2);
}

test "substr negative" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try substr(&ctx, "hello", -2, null);
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("lo", result);
}

test "strtoupper" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try strtoupper(&ctx, "Hello World");
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("HELLO WORLD", result);
}

test "strtolower" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try strtolower(&ctx, "Hello World");
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "strpos" {
    try std.testing.expectEqual(@as(i64, 6), strpos("hello world", "world", 0));
    try std.testing.expectEqual(@as(i64, -1), strpos("hello", "world", 0));
    try std.testing.expectEqual(@as(i64, 0), strpos("hello", "", 0));
}

test "str_contains" {
    try std.testing.expect(str_contains("hello world", "world"));
    try std.testing.expect(!str_contains("hello", "world"));
    try std.testing.expect(str_contains("hello", ""));
}

test "str_starts_with" {
    try std.testing.expect(str_starts_with("hello world", "hello"));
    try std.testing.expect(!str_starts_with("hello", "world"));
}

test "str_ends_with" {
    try std.testing.expect(str_ends_with("hello world", "world"));
    try std.testing.expect(!str_ends_with("hello", "world"));
}

test "trim" {
    try std.testing.expectEqualStrings("hello", trim("  hello  "));
    try std.testing.expectEqualStrings("hello", trim("\t\nhello\r\n"));
}

test "strrev" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try strrev(&ctx, "hello");
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("olleh", result);
}

test "str_repeat" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try str_repeat(&ctx, "ab", 3);
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("ababab", result);
}

test "ucfirst" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try ucfirst(&ctx, "hello");
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("Hello", result);
}

test "ord and chr" {
    var ctx = CoreContext.init(std.testing.allocator);

    try std.testing.expectEqual(@as(i64, 65), ord("A"));

    const result = try chr(&ctx, 65);
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("A", result);
}
