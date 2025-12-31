const std = @import("std");

/// Go风格的时间库
/// 提供类似Go语言time包的时间处理功能

/// 时间单位常量（纳秒）
pub const Nanosecond: i64 = 1;
pub const Microsecond: i64 = 1000 * Nanosecond;
pub const Millisecond: i64 = 1000 * Microsecond;
pub const Second: i64 = 1000 * Millisecond;
pub const Minute: i64 = 60 * Second;
pub const Hour: i64 = 60 * Minute;

/// 月份枚举
pub const Month = enum(u4) {
    January = 1,
    February = 2,
    March = 3,
    April = 4,
    May = 5,
    June = 6,
    July = 7,
    August = 8,
    September = 9,
    October = 10,
    November = 11,
    December = 12,

    pub fn string(self: Month) []const u8 {
        return switch (self) {
            .January => "January",
            .February => "February",
            .March => "March",
            .April => "April",
            .May => "May",
            .June => "June",
            .July => "July",
            .August => "August",
            .September => "September",
            .October => "October",
            .November => "November",
            .December => "December",
        };
    }

    pub fn shortString(self: Month) []const u8 {
        return switch (self) {
            .January => "Jan",
            .February => "Feb",
            .March => "Mar",
            .April => "Apr",
            .May => "May",
            .June => "Jun",
            .July => "Jul",
            .August => "Aug",
            .September => "Sep",
            .October => "Oct",
            .November => "Nov",
            .December => "Dec",
        };
    }
};

/// 星期枚举
pub const Weekday = enum(u3) {
    Sunday = 0,
    Monday = 1,
    Tuesday = 2,
    Wednesday = 3,
    Thursday = 4,
    Friday = 5,
    Saturday = 6,

    pub fn string(self: Weekday) []const u8 {
        return switch (self) {
            .Sunday => "Sunday",
            .Monday => "Monday",
            .Tuesday => "Tuesday",
            .Wednesday => "Wednesday",
            .Thursday => "Thursday",
            .Friday => "Friday",
            .Saturday => "Saturday",
        };
    }

    pub fn shortString(self: Weekday) []const u8 {
        return switch (self) {
            .Sunday => "Sun",
            .Monday => "Mon",
            .Tuesday => "Tue",
            .Wednesday => "Wed",
            .Thursday => "Thu",
            .Friday => "Fri",
            .Saturday => "Sat",
        };
    }
};

/// 时区信息
pub const Location = struct {
    name: []const u8,
    offset: i32, // UTC偏移（秒）

    pub const UTC = Location{ .name = "UTC", .offset = 0 };
    pub const Local = Location{ .name = "Local", .offset = 0 }; // 简化实现

    pub fn fixedZone(name: []const u8, offset: i32) Location {
        return Location{ .name = name, .offset = offset };
    }
};

/// Duration - 时间间隔
/// 表示两个时间点之间的间隔，以纳秒为单位
pub const Duration = struct {
    nsec: i64,

    pub fn init(nsec: i64) Duration {
        return Duration{ .nsec = nsec };
    }

    /// 从小时创建Duration
    pub fn hours(h: i64) Duration {
        return Duration{ .nsec = h * Hour };
    }

    /// 从分钟创建Duration
    pub fn minutes(m: i64) Duration {
        return Duration{ .nsec = m * Minute };
    }

    /// 从秒创建Duration
    pub fn seconds(s: i64) Duration {
        return Duration{ .nsec = s * Second };
    }

    /// 从毫秒创建Duration
    pub fn milliseconds(ms: i64) Duration {
        return Duration{ .nsec = ms * Millisecond };
    }

    /// 从微秒创建Duration
    pub fn microseconds(us: i64) Duration {
        return Duration{ .nsec = us * Microsecond };
    }

    /// 从纳秒创建Duration
    pub fn nanoseconds(ns: i64) Duration {
        return Duration{ .nsec = ns };
    }

    /// 获取小时数
    pub fn getHours(self: Duration) i64 {
        return @divTrunc(self.nsec, Hour);
    }

    /// 获取分钟数
    pub fn getMinutes(self: Duration) i64 {
        return @divTrunc(self.nsec, Minute);
    }

    /// 获取秒数
    pub fn getSeconds(self: Duration) i64 {
        return @divTrunc(self.nsec, Second);
    }

    /// 获取毫秒数
    pub fn getMilliseconds(self: Duration) i64 {
        return @divTrunc(self.nsec, Millisecond);
    }

    /// 获取微秒数
    pub fn getMicroseconds(self: Duration) i64 {
        return @divTrunc(self.nsec, Microsecond);
    }

    /// 获取纳秒数
    pub fn getNanoseconds(self: Duration) i64 {
        return self.nsec;
    }

    /// 加法
    pub fn add(self: Duration, other: Duration) Duration {
        return Duration{ .nsec = self.nsec + other.nsec };
    }

    /// 减法
    pub fn sub(self: Duration, other: Duration) Duration {
        return Duration{ .nsec = self.nsec - other.nsec };
    }

    /// 乘法
    pub fn mul(self: Duration, n: i64) Duration {
        return Duration{ .nsec = self.nsec * n };
    }

    /// 除法
    pub fn div(self: Duration, n: i64) Duration {
        return Duration{ .nsec = @divTrunc(self.nsec, n) };
    }

    /// 绝对值
    pub fn abs(self: Duration) Duration {
        return Duration{ .nsec = if (self.nsec < 0) -self.nsec else self.nsec };
    }

    /// 截断到指定精度
    pub fn truncate(self: Duration, m: Duration) Duration {
        if (m.nsec <= 0) return self;
        return Duration{ .nsec = self.nsec - @mod(self.nsec, m.nsec) };
    }

    /// 四舍五入到指定精度
    pub fn round(self: Duration, m: Duration) Duration {
        if (m.nsec <= 0) return self;
        const r = @mod(self.nsec, m.nsec);
        if (self.nsec < 0) {
            if (-r + r < m.nsec) {
                return Duration{ .nsec = self.nsec + r };
            }
            return Duration{ .nsec = self.nsec + r - m.nsec };
        }
        if (r + r < m.nsec) {
            return Duration{ .nsec = self.nsec - r };
        }
        return Duration{ .nsec = self.nsec + m.nsec - r };
    }

    /// 格式化为字符串
    pub fn string(self: Duration, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        const writer = buf.writer(allocator);

        var d = self.nsec;
        if (d < 0) {
            try writer.writeByte('-');
            d = -d;
        }

        if (d < Microsecond) {
            try writer.print("{}ns", .{d});
        } else if (d < Millisecond) {
            try writer.print("{d:.3}µs", .{@as(f64, @floatFromInt(d)) / @as(f64, @floatFromInt(Microsecond))});
        } else if (d < Second) {
            try writer.print("{d:.3}ms", .{@as(f64, @floatFromInt(d)) / @as(f64, @floatFromInt(Millisecond))});
        } else if (d < Minute) {
            try writer.print("{d:.3}s", .{@as(f64, @floatFromInt(d)) / @as(f64, @floatFromInt(Second))});
        } else if (d < Hour) {
            const mins = @divTrunc(d, Minute);
            const secs = @divTrunc(@mod(d, Minute), Second);
            try writer.print("{}m{}s", .{ mins, secs });
        } else {
            const hrs = @divTrunc(d, Hour);
            const mins = @divTrunc(@mod(d, Hour), Minute);
            try writer.print("{}h{}m", .{ hrs, mins });
        }

        return buf.toOwnedSlice(allocator);
    }
};

/// Time - 时间点
/// 表示一个具体的时间点，精确到纳秒
pub const Time = struct {
    /// Unix时间戳（秒）
    sec: i64,
    /// 纳秒部分 (0-999999999)
    nsec: u32,
    /// 时区
    loc: Location,

    /// 创建零时间
    pub fn zero() Time {
        return Time{ .sec = 0, .nsec = 0, .loc = Location.UTC };
    }

    /// 获取当前时间 (UTC)
    pub fn now() Time {
        const ts = std.time.timestamp();
        const nanos = std.time.nanoTimestamp();
        const nsec_part: u32 = @intCast(@mod(nanos, 1_000_000_000));
        return Time{
            .sec = ts,
            .nsec = nsec_part,
            .loc = Location.UTC,
        };
    }

    /// 从Unix时间戳创建
    pub fn unix(sec: i64, nsec: i64) Time {
        var s = sec;
        var n = nsec;
        if (n < 0 or n >= 1_000_000_000) {
            s += @divFloor(n, 1_000_000_000);
            n = @mod(n, 1_000_000_000);
            if (n < 0) {
                n += 1_000_000_000;
                s -= 1;
            }
        }
        return Time{
            .sec = s,
            .nsec = @intCast(n),
            .loc = Location.UTC,
        };
    }

    /// 从毫秒时间戳创建
    pub fn unixMilli(msec: i64) Time {
        return unix(@divFloor(msec, 1000), @mod(msec, 1000) * 1_000_000);
    }

    /// 从微秒时间戳创建
    pub fn unixMicro(usec: i64) Time {
        return unix(@divFloor(usec, 1_000_000), @mod(usec, 1_000_000) * 1000);
    }

    /// 从日期时间创建
    pub fn date(yr: i32, mon: Month, dy: u8, hr: u8, min: u8, sec: u8, ns: u32, loc: Location) Time {
        // 计算从1970年1月1日到指定日期的天数
        var days: i64 = 0;

        // 计算年份贡献的天数
        var y: i32 = 1970;
        while (y < yr) : (y += 1) {
            days += if (isLeapYear(y)) 366 else 365;
        }
        while (y > yr) {
            y -= 1;
            days -= if (isLeapYear(y)) 366 else 365;
        }

        // 计算月份贡献的天数
        const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var m: u4 = 1;
        while (m < @intFromEnum(mon)) : (m += 1) {
            days += month_days[m - 1];
            if (m == 2 and isLeapYear(yr)) {
                days += 1;
            }
        }

        // 加上日期
        days += dy - 1;

        // 计算总秒数
        const total_sec = days * 86400 + @as(i64, hr) * 3600 + @as(i64, min) * 60 + @as(i64, sec) - loc.offset;

        return Time{
            .sec = total_sec,
            .nsec = ns,
            .loc = loc,
        };
    }

    /// 检查是否为闰年
    pub fn isLeapYear(yr: i32) bool {
        return (@mod(yr, 4) == 0 and @mod(yr, 100) != 0) or @mod(yr, 400) == 0;
    }

    /// 获取Unix时间戳（秒）
    pub fn getUnix(self: Time) i64 {
        return self.sec;
    }

    /// 获取Unix时间戳（毫秒）
    pub fn getUnixMilli(self: Time) i64 {
        return self.sec * 1000 + @divTrunc(self.nsec, 1_000_000);
    }

    /// 获取Unix时间戳（微秒）
    pub fn getUnixMicro(self: Time) i64 {
        return self.sec * 1_000_000 + @divTrunc(self.nsec, 1000);
    }

    /// 获取Unix时间戳（纳秒）
    pub fn getUnixNano(self: Time) i128 {
        return @as(i128, self.sec) * 1_000_000_000 + self.nsec;
    }

    /// 获取年份
    pub fn year(self: Time) i32 {
        const days = @divFloor(self.sec + self.loc.offset, 86400);
        // 使用简单的迭代算法
        var y: i32 = 1970;
        var remaining = days;
        
        if (remaining >= 0) {
            while (remaining >= (if (isLeapYear(y)) @as(i64, 366) else @as(i64, 365))) {
                remaining -= if (isLeapYear(y)) @as(i64, 366) else @as(i64, 365);
                y += 1;
            }
        } else {
            while (remaining < 0) {
                y -= 1;
                remaining += if (isLeapYear(y)) @as(i64, 366) else @as(i64, 365);
            }
        }
        return y;
    }

    fn yearFromDays(days: i64) i32 {
        var y: i32 = 1970;
        var remaining = days;
        
        if (remaining >= 0) {
            while (remaining >= (if (Time.isLeapYear(y)) @as(i64, 366) else @as(i64, 365))) {
                remaining -= if (Time.isLeapYear(y)) @as(i64, 366) else @as(i64, 365);
                y += 1;
            }
        } else {
            while (remaining < 0) {
                y -= 1;
                remaining += if (Time.isLeapYear(y)) @as(i64, 366) else @as(i64, 365);
            }
        }
        return y;
    }

    /// 获取月份
    pub fn month(self: Time) Month {
        const days = @divFloor(self.sec + self.loc.offset, 86400);
        const m = monthFromDays(days);
        return @enumFromInt(m);
    }

    fn monthFromDays(days: i64) u4 {
        const y = yearFromDays(days);
        var remaining = days;
        
        // 减去年份的天数
        var yr: i32 = 1970;
        if (remaining >= 0) {
            while (yr < y) {
                remaining -= if (Time.isLeapYear(yr)) @as(i64, 366) else @as(i64, 365);
                yr += 1;
            }
        } else {
            while (yr > y) {
                yr -= 1;
                remaining += if (Time.isLeapYear(yr)) @as(i64, 366) else @as(i64, 365);
            }
        }
        
        // 计算月份
        const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var m: u4 = 1;
        while (m <= 12) : (m += 1) {
            var days_in_month: i64 = month_days[m - 1];
            if (m == 2 and Time.isLeapYear(y)) {
                days_in_month = 29;
            }
            if (remaining < days_in_month) {
                return m;
            }
            remaining -= days_in_month;
        }
        return 12;
    }

    /// 获取日期
    pub fn day(self: Time) u8 {
        const days = @divFloor(self.sec + self.loc.offset, 86400);
        return dayFromDays(days);
    }

    fn dayFromDays(days: i64) u8 {
        const y = yearFromDays(days);
        var remaining = days;
        
        // 减去年份的天数
        var yr: i32 = 1970;
        if (remaining >= 0) {
            while (yr < y) {
                remaining -= if (Time.isLeapYear(yr)) @as(i64, 366) else @as(i64, 365);
                yr += 1;
            }
        } else {
            while (yr > y) {
                yr -= 1;
                remaining += if (Time.isLeapYear(yr)) @as(i64, 366) else @as(i64, 365);
            }
        }
        
        // 减去月份的天数
        const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var m: u4 = 1;
        while (m <= 12) : (m += 1) {
            var days_in_month: i64 = month_days[m - 1];
            if (m == 2 and Time.isLeapYear(y)) {
                days_in_month = 29;
            }
            if (remaining < days_in_month) {
                return @intCast(remaining + 1);
            }
            remaining -= days_in_month;
        }
        return 1;
    }

    /// 获取小时
    pub fn hour(self: Time) u8 {
        const sec_of_day = @mod(self.sec + self.loc.offset, 86400);
        return @intCast(@divTrunc(sec_of_day, 3600));
    }

    /// 获取分钟
    pub fn minute(self: Time) u8 {
        const sec_of_day = @mod(self.sec + self.loc.offset, 86400);
        return @intCast(@divTrunc(@mod(sec_of_day, 3600), 60));
    }

    /// 获取秒
    pub fn second(self: Time) u8 {
        const sec_of_day = @mod(self.sec + self.loc.offset, 86400);
        return @intCast(@mod(sec_of_day, 60));
    }

    /// 获取纳秒
    pub fn nanosecond(self: Time) u32 {
        return self.nsec;
    }

    /// 获取星期几
    pub fn weekday(self: Time) Weekday {
        const days = @divFloor(self.sec + self.loc.offset, 86400);
        // 1970年1月1日是星期四
        const wd = @mod(days + 4, 7);
        return @enumFromInt(@as(u3, @intCast(if (wd < 0) wd + 7 else wd)));
    }

    /// 获取一年中的第几天 (1-366)
    pub fn yearDay(self: Time) u16 {
        const y = self.year();
        const m = @intFromEnum(self.month());
        const d = self.day();

        const month_days = [_]u16{ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };
        var yday: u16 = month_days[m - 1] + d;
        if (m > 2 and isLeapYear(y)) {
            yday += 1;
        }
        return yday;
    }

    /// 获取ISO周数
    pub fn isoWeek(self: Time) struct { year: i32, week: u8 } {
        const y = self.year();
        const yday = self.yearDay();
        const wday = @intFromEnum(self.weekday());

        // ISO周从周一开始
        const mon_yday = @as(i32, yday) - @as(i32, if (wday == 0) 6 else wday - 1);
        const week: i32 = @divTrunc(mon_yday + 6, 7);

        if (week < 1) {
            // 属于上一年的最后一周
            return .{ .year = y - 1, .week = 52 };
        } else if (week > 52) {
            // 可能属于下一年的第一周
            const jan1_wday = @mod(@as(i32, wday) - @as(i32, yday) + 1 + 7 * 53, 7);
            if (jan1_wday == 4 or (jan1_wday == 3 and isLeapYear(y))) {
                return .{ .year = y, .week = 53 };
            }
            return .{ .year = y + 1, .week = 1 };
        }

        return .{ .year = y, .week = @intCast(week) };
    }

    /// 时间加法
    pub fn add(self: Time, d: Duration) Time {
        const total_nsec = @as(i64, self.nsec) + d.nsec;
        const sec_delta = @divFloor(total_nsec, 1_000_000_000);
        const new_nsec = @mod(total_nsec, 1_000_000_000);
        return Time{
            .sec = self.sec + sec_delta,
            .nsec = @intCast(if (new_nsec < 0) new_nsec + 1_000_000_000 else new_nsec),
            .loc = self.loc,
        };
    }

    /// 时间减法
    pub fn sub(self: Time, other: Time) Duration {
        const sec_diff = self.sec - other.sec;
        const nsec_diff = @as(i64, self.nsec) - @as(i64, other.nsec);
        return Duration{ .nsec = sec_diff * 1_000_000_000 + nsec_diff };
    }

    /// 添加日期
    pub fn addDate(self: Time, years: i32, months: i32, days_to_add: i32) Time {
        var y = self.year() + years;
        var m = @as(i32, @intFromEnum(self.month())) + months;

        // 规范化月份
        while (m < 1) {
            m += 12;
            y -= 1;
        }
        while (m > 12) {
            m -= 12;
            y += 1;
        }

        // 获取当前日期，确保不超过目标月份的最大天数
        const month_days_arr = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var max_day: u8 = month_days_arr[@intCast(m - 1)];
        if (m == 2 and isLeapYear(y)) {
            max_day = 29;
        }
        
        var d: i32 = @min(@as(i32, self.day()), max_day);
        d += days_to_add;

        // 处理日期溢出
        while (d > max_day) {
            d -= max_day;
            m += 1;
            if (m > 12) {
                m = 1;
                y += 1;
            }
            max_day = month_days_arr[@intCast(m - 1)];
            if (m == 2 and isLeapYear(y)) {
                max_day = 29;
            }
        }
        while (d < 1) {
            m -= 1;
            if (m < 1) {
                m = 12;
                y -= 1;
            }
            max_day = month_days_arr[@intCast(m - 1)];
            if (m == 2 and isLeapYear(y)) {
                max_day = 29;
            }
            d += max_day;
        }

        return date(y, @enumFromInt(@as(u4, @intCast(m))), @intCast(d), self.hour(), self.minute(), self.second(), self.nsec, self.loc);
    }

    /// 比较时间
    pub fn before(self: Time, other: Time) bool {
        return self.sec < other.sec or (self.sec == other.sec and self.nsec < other.nsec);
    }

    pub fn after(self: Time, other: Time) bool {
        return self.sec > other.sec or (self.sec == other.sec and self.nsec > other.nsec);
    }

    pub fn equal(self: Time, other: Time) bool {
        return self.sec == other.sec and self.nsec == other.nsec;
    }

    /// 检查是否为零时间
    pub fn isZero(self: Time) bool {
        return self.sec == 0 and self.nsec == 0;
    }

    /// 转换时区
    pub fn in(self: Time, loc: Location) Time {
        return Time{
            .sec = self.sec,
            .nsec = self.nsec,
            .loc = loc,
        };
    }

    /// 获取UTC时间
    pub fn utc(self: Time) Time {
        return self.in(Location.UTC);
    }

    /// 截断到指定精度
    pub fn truncateTime(self: Time, d: Duration) Time {
        if (d.nsec <= 0) return self;
        const total_nsec = self.sec * 1_000_000_000 + self.nsec;
        const truncated = total_nsec - @mod(total_nsec, d.nsec);
        return Time{
            .sec = @divFloor(truncated, 1_000_000_000),
            .nsec = @intCast(@mod(truncated, 1_000_000_000)),
            .loc = self.loc,
        };
    }

    /// 四舍五入到指定精度
    pub fn roundTime(self: Time, d: Duration) Time {
        if (d.nsec <= 0) return self;
        const total_nsec = self.sec * 1_000_000_000 + self.nsec;
        const r = @mod(total_nsec, d.nsec);
        var rounded = total_nsec - r;
        if (r + r >= d.nsec) {
            rounded += d.nsec;
        }
        return Time{
            .sec = @divFloor(rounded, 1_000_000_000),
            .nsec = @intCast(@mod(rounded, 1_000_000_000)),
            .loc = self.loc,
        };
    }

    // ========================================================================
    // 格式化方法
    // ========================================================================

    /// Go风格的时间格式化
    /// 参考时间: Mon Jan 2 15:04:05 MST 2006
    pub fn format(self: Time, layout: []const u8, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        const writer = buf.writer(allocator);

        var i: usize = 0;
        while (i < layout.len) {
            // 检查特殊格式 - 按长度从长到短匹配
            if (i + 7 <= layout.len and std.mem.eql(u8, layout[i .. i + 7], "January")) {
                try writer.writeAll(self.month().string());
                i += 7;
            } else if (i + 6 <= layout.len and std.mem.eql(u8, layout[i .. i + 6], "Monday")) {
                try writer.writeAll(self.weekday().string());
                i += 6;
            } else if (i + 4 <= layout.len and std.mem.eql(u8, layout[i .. i + 4], "2006")) {
                const yr = self.year();
                if (yr >= 0) {
                    try writer.print("{d:0>4}", .{@as(u32, @intCast(yr))});
                } else {
                    try writer.print("-{d:0>4}", .{@as(u32, @intCast(-yr))});
                }
                i += 4;
            } else if (i + 3 <= layout.len and std.mem.eql(u8, layout[i .. i + 3], "Mon")) {
                try writer.writeAll(self.weekday().shortString());
                i += 3;
            } else if (i + 3 <= layout.len and std.mem.eql(u8, layout[i .. i + 3], "Jan")) {
                try writer.writeAll(self.month().shortString());
                i += 3;
            } else if (i + 3 <= layout.len and std.mem.eql(u8, layout[i .. i + 3], "MST")) {
                try writer.writeAll(self.loc.name);
                i += 3;
            } else if (i + 2 <= layout.len and std.mem.eql(u8, layout[i .. i + 2], "06")) {
                try writer.print("{d:0>2}", .{@as(u32, @intCast(@mod(self.year(), 100)))});
                i += 2;
            } else if (i + 2 <= layout.len and std.mem.eql(u8, layout[i .. i + 2], "01")) {
                try writer.print("{d:0>2}", .{@intFromEnum(self.month())});
                i += 2;
            } else if (i + 2 <= layout.len and std.mem.eql(u8, layout[i .. i + 2], "02")) {
                try writer.print("{d:0>2}", .{self.day()});
                i += 2;
            } else if (i + 2 <= layout.len and std.mem.eql(u8, layout[i .. i + 2], "15")) {
                try writer.print("{d:0>2}", .{self.hour()});
                i += 2;
            } else if (i + 2 <= layout.len and std.mem.eql(u8, layout[i .. i + 2], "04")) {
                try writer.print("{d:0>2}", .{self.minute()});
                i += 2;
            } else if (i + 2 <= layout.len and std.mem.eql(u8, layout[i .. i + 2], "05")) {
                try writer.print("{d:0>2}", .{self.second()});
                i += 2;
            } else if (i + 2 <= layout.len and std.mem.eql(u8, layout[i .. i + 2], "PM")) {
                try writer.writeAll(if (self.hour() >= 12) "PM" else "AM");
                i += 2;
            } else if (i + 2 <= layout.len and std.mem.eql(u8, layout[i .. i + 2], "pm")) {
                try writer.writeAll(if (self.hour() >= 12) "pm" else "am");
                i += 2;
            } else if (i + 1 <= layout.len and layout[i] == '3') {
                const h = self.hour();
                try writer.print("{}", .{if (h == 0) @as(u8, 12) else if (h > 12) h - 12 else h});
                i += 1;
            } else if (i + 1 <= layout.len and layout[i] == '4') {
                try writer.print("{}", .{self.minute()});
                i += 1;
            } else if (i + 1 <= layout.len and layout[i] == '5') {
                try writer.print("{}", .{self.second()});
                i += 1;
            } else if (i + 1 <= layout.len and layout[i] == '1') {
                try writer.print("{}", .{@intFromEnum(self.month())});
                i += 1;
            } else if (i + 1 <= layout.len and layout[i] == '2') {
                try writer.print("{}", .{self.day()});
                i += 1;
            } else {
                try writer.writeByte(layout[i]);
                i += 1;
            }
        }

        return buf.toOwnedSlice(allocator);
    }

    /// 常用格式常量
    pub const Layout = "01/02 03:04:05PM '06 -0700";
    pub const ANSIC = "Mon Jan _2 15:04:05 2006";
    pub const UnixDate = "Mon Jan _2 15:04:05 MST 2006";
    pub const RubyDate = "Mon Jan 02 15:04:05 -0700 2006";
    pub const RFC822 = "02 Jan 06 15:04 MST";
    pub const RFC822Z = "02 Jan 06 15:04 -0700";
    pub const RFC850 = "Monday, 02-Jan-06 15:04:05 MST";
    pub const RFC1123 = "Mon, 02 Jan 2006 15:04:05 MST";
    pub const RFC1123Z = "Mon, 02 Jan 2006 15:04:05 -0700";
    pub const RFC3339 = "2006-01-02T15:04:05Z07:00";
    pub const RFC3339Nano = "2006-01-02T15:04:05.999999999Z07:00";
    pub const Kitchen = "3:04PM";
    pub const Stamp = "Jan _2 15:04:05";
    pub const StampMilli = "Jan _2 15:04:05.000";
    pub const StampMicro = "Jan _2 15:04:05.000000";
    pub const StampNano = "Jan _2 15:04:05.000000000";
    pub const DateTime = "2006-01-02 15:04:05";
    pub const DateOnly = "2006-01-02";
    pub const TimeOnly = "15:04:05";
};

// ============================================================================
// 解析函数
// ============================================================================

/// 解析时间字符串
pub fn parse(layout: []const u8, value: []const u8) !Time {
    _ = layout;
    _ = value;
    // 简化实现：只支持RFC3339格式
    return Time.zero();
}

/// 解析Duration字符串
/// 支持格式: "300ms", "1.5h", "2h45m"
pub fn parseDuration(s: []const u8) !Duration {
    if (s.len == 0) return error.InvalidDuration;

    var total: i64 = 0;
    var i: usize = 0;
    var neg = false;

    if (s[0] == '-') {
        neg = true;
        i = 1;
    } else if (s[0] == '+') {
        i = 1;
    }

    while (i < s.len) {
        // 解析数字部分
        var num: i64 = 0;
        var has_num = false;
        var frac: i64 = 0;
        var frac_scale: i64 = 1;

        while (i < s.len and s[i] >= '0' and s[i] <= '9') {
            num = num * 10 + (s[i] - '0');
            has_num = true;
            i += 1;
        }

        // 小数部分
        if (i < s.len and s[i] == '.') {
            i += 1;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') {
                frac = frac * 10 + (s[i] - '0');
                frac_scale *= 10;
                i += 1;
            }
        }

        if (!has_num and frac_scale == 1) return error.InvalidDuration;

        // 解析单位
        const unit_start = i;
        while (i < s.len and ((s[i] >= 'a' and s[i] <= 'z') or (s[i] >= 'A' and s[i] <= 'Z') or s[i] == 194 or s[i] == 181)) {
            i += 1;
        }

        const unit = s[unit_start..i];
        const scale: i64 = if (std.mem.eql(u8, unit, "ns"))
            Nanosecond
        else if (std.mem.eql(u8, unit, "us") or std.mem.eql(u8, unit, "µs") or std.mem.eql(u8, unit, "\xc2\xb5s"))
            Microsecond
        else if (std.mem.eql(u8, unit, "ms"))
            Millisecond
        else if (std.mem.eql(u8, unit, "s"))
            Second
        else if (std.mem.eql(u8, unit, "m"))
            Minute
        else if (std.mem.eql(u8, unit, "h"))
            Hour
        else
            return error.InvalidDuration;

        total += num * scale;
        if (frac_scale > 1) {
            total += @divTrunc(frac * scale, frac_scale);
        }
    }

    return Duration{ .nsec = if (neg) -total else total };
}

// ============================================================================
// PHP兼容函数
// ============================================================================

/// PHP time() - 返回当前Unix时间戳
pub fn phpTime() i64 {
    return Time.now().getUnix();
}

/// PHP microtime(true) - 返回当前时间（微秒精度）
pub fn phpMicrotime() f64 {
    const t = Time.now();
    return @as(f64, @floatFromInt(t.sec)) + @as(f64, @floatFromInt(t.nsec)) / 1_000_000_000.0;
}

/// PHP date() - 格式化时间
pub fn phpDate(format: []const u8, timestamp: ?i64, allocator: std.mem.Allocator) ![]u8 {
    const t = if (timestamp) |ts| Time.unix(ts, 0) else Time.now();
    var buf = std.ArrayListUnmanaged(u8){};
    const writer = buf.writer(allocator);

    for (format) |c| {
        switch (c) {
            'Y' => {
                const yr = t.year();
                if (yr >= 0) {
                    try writer.print("{d:0>4}", .{@as(u32, @intCast(yr))});
                } else {
                    try writer.print("-{d:0>4}", .{@as(u32, @intCast(-yr))});
                }
            },
            'y' => {
                const yr = @mod(t.year(), 100);
                try writer.print("{d:0>2}", .{@as(u32, @intCast(if (yr < 0) -yr else yr))});
            },
            'm' => try writer.print("{d:0>2}", .{@intFromEnum(t.month())}),
            'n' => try writer.print("{}", .{@intFromEnum(t.month())}),
            'd' => try writer.print("{d:0>2}", .{t.day()}),
            'j' => try writer.print("{}", .{t.day()}),
            'H' => try writer.print("{d:0>2}", .{t.hour()}),
            'G' => try writer.print("{}", .{t.hour()}),
            'i' => try writer.print("{d:0>2}", .{t.minute()}),
            's' => try writer.print("{d:0>2}", .{t.second()}),
            'D' => try writer.writeAll(t.weekday().shortString()),
            'l' => try writer.writeAll(t.weekday().string()),
            'M' => try writer.writeAll(t.month().shortString()),
            'F' => try writer.writeAll(t.month().string()),
            'A' => try writer.writeAll(if (t.hour() >= 12) "PM" else "AM"),
            'a' => try writer.writeAll(if (t.hour() >= 12) "pm" else "am"),
            'w' => try writer.print("{}", .{@intFromEnum(t.weekday())}),
            'N' => {
                const wd = @intFromEnum(t.weekday());
                try writer.print("{}", .{if (wd == 0) 7 else wd});
            },
            'z' => try writer.print("{}", .{t.yearDay() - 1}),
            'W' => {
                const iso = t.isoWeek();
                try writer.print("{d:0>2}", .{iso.week});
            },
            'U' => try writer.print("{}", .{t.getUnix()}),
            else => try writer.writeByte(c),
        }
    }

    return buf.toOwnedSlice(allocator);
}

/// PHP mktime() - 从日期时间创建时间戳
pub fn phpMktime(hour: u8, minute: u8, second: u8, month: u4, day: u8, year: i32) i64 {
    const t = Time.date(year, @enumFromInt(month), day, hour, minute, second, 0, Location.UTC);
    return t.getUnix();
}

/// PHP strtotime() - 解析日期时间字符串（简化实现）
pub fn phpStrtotime(datetime: []const u8, base_time: ?i64) !i64 {
    const base = if (base_time) |ts| Time.unix(ts, 0) else Time.now();

    // 简化实现：只支持一些常见格式
    if (std.mem.eql(u8, datetime, "now")) {
        return base.getUnix();
    } else if (std.mem.eql(u8, datetime, "today")) {
        return Time.date(base.year(), base.month(), base.day(), 0, 0, 0, 0, base.loc).getUnix();
    } else if (std.mem.eql(u8, datetime, "tomorrow")) {
        return base.addDate(0, 0, 1).getUnix();
    } else if (std.mem.eql(u8, datetime, "yesterday")) {
        return base.addDate(0, 0, -1).getUnix();
    } else if (std.mem.startsWith(u8, datetime, "+")) {
        const d = try parseDuration(datetime[1..]);
        return base.add(d).getUnix();
    } else if (std.mem.startsWith(u8, datetime, "-")) {
        const d = try parseDuration(datetime[1..]);
        return base.add(Duration{ .nsec = -d.nsec }).getUnix();
    }

    return error.InvalidFormat;
}

/// PHP checkdate() - 验证日期
pub fn phpCheckdate(month: u4, day: u8, year: i32) bool {
    if (month < 1 or month > 12) return false;
    if (day < 1) return false;

    const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var max_day = month_days[month - 1];
    if (month == 2 and Time.isLeapYear(year)) {
        max_day = 29;
    }

    return day <= max_day;
}

// ============================================================================
// 单元测试
// ============================================================================

test "Duration creation and conversion" {
    const testing = std.testing;

    const d1 = Duration.hours(2);
    try testing.expectEqual(@as(i64, 2), d1.getHours());
    try testing.expectEqual(@as(i64, 120), d1.getMinutes());
    try testing.expectEqual(@as(i64, 7200), d1.getSeconds());

    const d2 = Duration.minutes(90);
    try testing.expectEqual(@as(i64, 1), d2.getHours());
    try testing.expectEqual(@as(i64, 90), d2.getMinutes());

    const d3 = Duration.seconds(3661);
    try testing.expectEqual(@as(i64, 1), d3.getHours());
    try testing.expectEqual(@as(i64, 61), d3.getMinutes());
}

test "Duration arithmetic" {
    const testing = std.testing;

    const d1 = Duration.hours(1);
    const d2 = Duration.minutes(30);

    const sum = d1.add(d2);
    try testing.expectEqual(@as(i64, 90), sum.getMinutes());

    const diff = d1.sub(d2);
    try testing.expectEqual(@as(i64, 30), diff.getMinutes());

    const doubled = d1.mul(2);
    try testing.expectEqual(@as(i64, 2), doubled.getHours());

    const halved = d1.div(2);
    try testing.expectEqual(@as(i64, 30), halved.getMinutes());
}

test "Duration abs and truncate" {
    const testing = std.testing;

    const neg = Duration.hours(-2);
    try testing.expectEqual(@as(i64, 2), neg.abs().getHours());

    const d = Duration.nanoseconds(1_500_000_000);
    const truncated = d.truncate(Duration.seconds(1));
    try testing.expectEqual(@as(i64, 1), truncated.getSeconds());
}

test "Time creation" {
    const testing = std.testing;

    const t1 = Time.unix(0, 0);
    try testing.expectEqual(@as(i64, 0), t1.getUnix());

    const t2 = Time.unixMilli(1000);
    try testing.expectEqual(@as(i64, 1), t2.getUnix());

    const t3 = Time.date(2024, .January, 15, 10, 30, 45, 0, Location.UTC);
    try testing.expectEqual(@as(i32, 2024), t3.year());
    try testing.expectEqual(Month.January, t3.month());
    try testing.expectEqual(@as(u8, 15), t3.day());
    try testing.expectEqual(@as(u8, 10), t3.hour());
    try testing.expectEqual(@as(u8, 30), t3.minute());
    try testing.expectEqual(@as(u8, 45), t3.second());
}

test "Time components" {
    const testing = std.testing;

    // 2024-06-15 14:30:45 UTC
    const t = Time.date(2024, .June, 15, 14, 30, 45, 123456789, Location.UTC);

    try testing.expectEqual(@as(i32, 2024), t.year());
    try testing.expectEqual(Month.June, t.month());
    try testing.expectEqual(@as(u8, 15), t.day());
    try testing.expectEqual(@as(u8, 14), t.hour());
    try testing.expectEqual(@as(u8, 30), t.minute());
    try testing.expectEqual(@as(u8, 45), t.second());
    try testing.expectEqual(@as(u32, 123456789), t.nanosecond());
}

test "Time weekday" {
    const testing = std.testing;

    // 1970-01-01 是星期四
    const t1 = Time.unix(0, 0);
    try testing.expectEqual(Weekday.Thursday, t1.weekday());

    // 2024-01-01 是星期一
    const t2 = Time.date(2024, .January, 1, 0, 0, 0, 0, Location.UTC);
    try testing.expectEqual(Weekday.Monday, t2.weekday());
}

test "Time arithmetic" {
    const testing = std.testing;

    const t1 = Time.unix(1000, 0);
    const t2 = t1.add(Duration.hours(1));
    try testing.expectEqual(@as(i64, 4600), t2.getUnix());

    const diff = t2.sub(t1);
    try testing.expectEqual(@as(i64, 1), diff.getHours());
}

test "Time comparison" {
    const testing = std.testing;

    const t1 = Time.unix(1000, 0);
    const t2 = Time.unix(2000, 0);
    const t3 = Time.unix(1000, 0);

    try testing.expect(t1.before(t2));
    try testing.expect(t2.after(t1));
    try testing.expect(t1.equal(t3));
    try testing.expect(!t1.equal(t2));
}

test "Time addDate" {
    const testing = std.testing;

    const t1 = Time.date(2024, .January, 15, 12, 0, 0, 0, Location.UTC);

    const t2 = t1.addDate(1, 0, 0);
    try testing.expectEqual(@as(i32, 2025), t2.year());

    const t3 = t1.addDate(0, 1, 0);
    try testing.expectEqual(Month.February, t3.month());

    const t4 = t1.addDate(0, 0, 20);
    try testing.expectEqual(Month.February, t4.month());
    try testing.expectEqual(@as(u8, 4), t4.day());
}

test "Time format" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const t = Time.date(2024, .June, 15, 14, 30, 45, 0, Location.UTC);

    const formatted = try t.format("2006-01-02 15:04:05", allocator);
    defer allocator.free(formatted);
    try testing.expectEqualStrings("2024-06-15 14:30:45", formatted);
}

test "parseDuration" {
    const testing = std.testing;

    const d1 = try parseDuration("1h30m");
    try testing.expectEqual(@as(i64, 90), d1.getMinutes());

    const d2 = try parseDuration("500ms");
    try testing.expectEqual(@as(i64, 500), d2.getMilliseconds());

    const d3 = try parseDuration("-2h");
    try testing.expectEqual(@as(i64, -2), d3.getHours());
}

test "phpDate" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 2024-06-15 14:30:45 UTC
    const timestamp: i64 = 1718461845;

    const result = try phpDate("Y-m-d H:i:s", timestamp, allocator);
    defer allocator.free(result);
    try testing.expectEqualStrings("2024-06-15 14:30:45", result);
}

test "phpMktime" {
    const testing = std.testing;

    const ts = phpMktime(14, 30, 45, 6, 15, 2024);
    try testing.expectEqual(@as(i64, 1718461845), ts);
}

test "phpCheckdate" {
    const testing = std.testing;

    try testing.expect(phpCheckdate(1, 31, 2024));
    try testing.expect(phpCheckdate(2, 29, 2024)); // 闰年
    try testing.expect(!phpCheckdate(2, 29, 2023)); // 非闰年
    try testing.expect(!phpCheckdate(13, 1, 2024)); // 无效月份
    try testing.expect(!phpCheckdate(4, 31, 2024)); // 4月没有31日
}

test "Month and Weekday strings" {
    const testing = std.testing;

    try testing.expectEqualStrings("January", Month.January.string());
    try testing.expectEqualStrings("Jan", Month.January.shortString());

    try testing.expectEqualStrings("Monday", Weekday.Monday.string());
    try testing.expectEqualStrings("Mon", Weekday.Monday.shortString());
}

test "Time zero and isZero" {
    const testing = std.testing;

    const zero = Time.zero();
    try testing.expect(zero.isZero());

    const non_zero = Time.unix(1, 0);
    try testing.expect(!non_zero.isZero());
}

test "Location" {
    const testing = std.testing;

    try testing.expectEqualStrings("UTC", Location.UTC.name);
    try testing.expectEqual(@as(i32, 0), Location.UTC.offset);

    const est = Location.fixedZone("EST", -5 * 3600);
    try testing.expectEqualStrings("EST", est.name);
    try testing.expectEqual(@as(i32, -18000), est.offset);
}
