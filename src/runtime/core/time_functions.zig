//! 时间核心函数实现
//!
//! 提供与执行模式无关的时间操作核心逻辑。
//!
//! @ownership TRANSFER (返回的字符串由调用者负责释放)
//! @thread-safety ISOLATED

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const CoreContext = common.CoreContext;

/// time - 返回当前 Unix 时间戳（秒）
/// @return Unix 时间戳
pub fn time() i64 {
    return std.time.timestamp();
}

/// microtime - 返回当前时间（带微秒）
/// @return 浮点数形式的时间戳
pub fn microtime_float() f64 {
    const now_ns = std.time.nanoTimestamp();
    const sec: f64 = @floatFromInt(@divTrunc(now_ns, std.time.ns_per_s));
    const nsec: f64 = @floatFromInt(@mod(now_ns, std.time.ns_per_s));
    return sec + nsec / @as(f64, std.time.ns_per_s);
}

/// microtime_string - 返回格式化的微秒时间字符串
/// @param ctx 上下文
/// @return "msec sec" 格式的字符串（调用者负责释放）
pub fn microtime_string(ctx: *CoreContext) ![]u8 {
    const now_ns = std.time.nanoTimestamp();
    const sec = @divTrunc(now_ns, std.time.ns_per_s);
    const usec = @divTrunc(@mod(now_ns, std.time.ns_per_s), std.time.ns_per_us);

    return try std.fmt.allocPrint(
        ctx.allocator,
        "0.{d:0>6} {d}",
        .{ usec, sec },
    );
}

/// 时间组件结构
pub const TimeComponents = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    weekday: u8,
    yearday: u16,
};

/// 从时间戳获取时间组件
/// @param timestamp Unix 时间戳
/// @return 时间组件
pub fn getTimeComponents(timestamp: i64) TimeComponents {
    const epoch_seconds = std.time.epoch.EpochSeconds{
        .secs = @intCast(@max(0, timestamp)),
    };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    return .{
        .year = year_day.year,
        .month = @intFromEnum(month_day.month),
        .day = month_day.day_index + 1,
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
        .weekday = @intCast(epoch_day.day % 7),
        .yearday = year_day.day,
    };
}

/// date - 格式化日期时间
/// @param ctx 上下文
/// @param format 格式字符串
/// @param timestamp 时间戳（可选，默认当前时间）
/// @return 格式化后的字符串（调用者负责释放）
pub fn date(ctx: *CoreContext, format: []const u8, timestamp: ?i64) ![]u8 {
    const ts = timestamp orelse time();
    const tc = getTimeComponents(ts);

    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(ctx.allocator);

    var i: usize = 0;
    while (i < format.len) : (i += 1) {
        const c = format[i];
        switch (c) {
            'Y' => try appendNumber(ctx.allocator, &result, @intCast(tc.year), 4),
            'y' => try appendNumber(ctx.allocator, &result, @intCast(@mod(tc.year, 100)), 2),
            'm' => try appendNumber(ctx.allocator, &result, tc.month, 2),
            'n' => try appendNumber(ctx.allocator, &result, tc.month, 1),
            'd' => try appendNumber(ctx.allocator, &result, tc.day, 2),
            'j' => try appendNumber(ctx.allocator, &result, tc.day, 1),
            'H' => try appendNumber(ctx.allocator, &result, tc.hour, 2),
            'G' => try appendNumber(ctx.allocator, &result, tc.hour, 1),
            'i' => try appendNumber(ctx.allocator, &result, tc.minute, 2),
            's' => try appendNumber(ctx.allocator, &result, tc.second, 2),
            'w' => try appendNumber(ctx.allocator, &result, tc.weekday, 1),
            'z' => try appendNumber(ctx.allocator, &result, tc.yearday, 1),
            'U' => {
                const buf = try std.fmt.allocPrint(ctx.allocator, "{d}", .{ts});
                defer ctx.allocator.free(buf);
                try result.appendSlice(ctx.allocator, buf);
            },
            'D' => try result.appendSlice(ctx.allocator, getShortWeekday(tc.weekday)),
            'l' => try result.appendSlice(ctx.allocator, getFullWeekday(tc.weekday)),
            'M' => try result.appendSlice(ctx.allocator, getShortMonth(tc.month)),
            'F' => try result.appendSlice(ctx.allocator, getFullMonth(tc.month)),
            '\\' => {
                if (i + 1 < format.len) {
                    i += 1;
                    try result.append(ctx.allocator, format[i]);
                }
            },
            else => try result.append(ctx.allocator, c),
        }
    }

    return result.toOwnedSlice(ctx.allocator);
}

fn appendNumber(allocator: Allocator, list: *std.ArrayListUnmanaged(u8), value: u32, width: u8) !void {
    var buf: [16]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{d:0>[1]}", .{ value, width }) catch {
        return error.OutOfMemory;
    };
    try list.appendSlice(allocator, slice);
}

fn getShortWeekday(day: u8) []const u8 {
    const days = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    return if (day < 7) days[day] else "???";
}

fn getFullWeekday(day: u8) []const u8 {
    const days = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    return if (day < 7) days[day] else "Unknown";
}

fn getShortMonth(month: u8) []const u8 {
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    return if (month >= 1 and month <= 12) months[month - 1] else "???";
}

fn getFullMonth(month: u8) []const u8 {
    const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    return if (month >= 1 and month <= 12) months[month - 1] else "Unknown";
}

/// mktime - 创建时间戳
/// @param hour 小时
/// @param minute 分钟
/// @param second 秒
/// @param month 月份
/// @param day 日期
/// @param year 年份
/// @return Unix 时间戳
pub fn mktime(hour: i32, minute: i32, second: i32, month: i32, day: i32, year: i32) i64 {
    const m: u8 = @intCast(@mod(@max(1, @min(12, month)) - 1, 12) + 1);
    const y: i32 = if (year < 70) year + 2000 else if (year < 100) year + 1900 else year;

    const month_enum: std.time.epoch.Month = @enumFromInt(m);
    const year_day = std.time.epoch.YearAndDay{
        .year = y,
        .day = @intCast(@max(0, @min(365, day - 1))),
    };

    const epoch_day = year_day.toEpochDay();
    const day_seconds: u64 = @intCast(@max(0, hour) * 3600 + @max(0, minute) * 60 + @max(0, second));

    _ = month_enum;
    return @as(i64, @intCast(epoch_day.day)) * 86400 + @as(i64, @intCast(day_seconds));
}

/// usleep - 微秒级休眠
/// @param microseconds 微秒数
pub fn usleep(microseconds: u64) void {
    std.Thread.sleep(microseconds * std.time.ns_per_us);
}

/// sleep - 秒级休眠
/// @param seconds 秒数
pub fn sleep(seconds: u64) void {
    std.Thread.sleep(seconds * std.time.ns_per_s);
}

// ============================================================================
// 测试
// ============================================================================

test "time returns positive value" {
    const ts = time();
    try std.testing.expect(ts > 0);
}

test "microtime_float" {
    const t1 = microtime_float();
    std.Thread.sleep(1_000_000);
    const t2 = microtime_float();
    try std.testing.expect(t2 > t1);
}

test "getTimeComponents" {
    const tc = getTimeComponents(0);
    try std.testing.expectEqual(@as(i32, 1970), tc.year);
    try std.testing.expectEqual(@as(u8, 1), tc.month);
    try std.testing.expectEqual(@as(u8, 1), tc.day);
}

test "date format Y-m-d" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try date(&ctx, "Y-m-d", 0);
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("1970-01-01", result);
}

test "date format H:i:s" {
    var ctx = CoreContext.init(std.testing.allocator);

    const result = try date(&ctx, "H:i:s", 3661);
    defer ctx.allocator.free(result);
    try std.testing.expectEqualStrings("01:01:01", result);
}
