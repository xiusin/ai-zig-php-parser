const std = @import("std");
const testing = std.testing;

/// 独立测试 - 不依赖完整的types模块
/// 仅测试核心日期时间计算函数

/// 判断是否是闰年
fn isLeapYear(year: i32) bool {
    return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
}

/// 获取月份天数
fn getDaysInMonth(year: i32, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

/// 计算精确的Unix时间戳
fn calculateTimestamp(year: i32, month: i32, day: i32, hour: i32, minute: i32, second: i32) !i64 {
    // 规范化月份
    var norm_year = year;
    var norm_month = month;
    
    while (norm_month > 12) {
        norm_month -= 12;
        norm_year += 1;
    }
    while (norm_month < 1) {
        norm_month += 12;
        norm_year -= 1;
    }

    // 计算从1970年到目标年份的天数
    var days: i64 = 0;
    
    // 计算完整年份的天数
    var y: i32 = 1970;
    while (y < norm_year) : (y += 1) {
        days += if (isLeapYear(y)) 366 else 365;
    }
    
    // 计算当年已过月份的天数
    var m: u8 = 1;
    while (m < norm_month) : (m += 1) {
        days += getDaysInMonth(norm_year, m);
    }
    
    // 加上当月天数
    days += day - 1;
    
    // 计算总秒数
    const total_seconds = days * 86400 + 
                         @as(i64, hour) * 3600 + 
                         @as(i64, minute) * 60 + 
                         @as(i64, second);
    
    return total_seconds;
}

test "isLeapYear - 基本测试" {
    try testing.expect(isLeapYear(2024)); // 闰年
    try testing.expect(!isLeapYear(2023)); // 平年
    try testing.expect(isLeapYear(2000)); // 400的倍数
    try testing.expect(!isLeapYear(1900)); // 100的倍数但不是400的倍数
    try testing.expect(isLeapYear(2020));
    try testing.expect(!isLeapYear(2021));
}

test "getDaysInMonth - 所有月份" {
    // 平年
    try testing.expectEqual(31, getDaysInMonth(2023, 1));  // 1月
    try testing.expectEqual(28, getDaysInMonth(2023, 2));  // 2月（平年）
    try testing.expectEqual(31, getDaysInMonth(2023, 3));  // 3月
    try testing.expectEqual(30, getDaysInMonth(2023, 4));  // 4月
    try testing.expectEqual(31, getDaysInMonth(2023, 5));  // 5月
    try testing.expectEqual(30, getDaysInMonth(2023, 6));  // 6月
    try testing.expectEqual(31, getDaysInMonth(2023, 7));  // 7月
    try testing.expectEqual(31, getDaysInMonth(2023, 8));  // 8月
    try testing.expectEqual(30, getDaysInMonth(2023, 9));  // 9月
    try testing.expectEqual(31, getDaysInMonth(2023, 10)); // 10月
    try testing.expectEqual(30, getDaysInMonth(2023, 11)); // 11月
    try testing.expectEqual(31, getDaysInMonth(2023, 12)); // 12月
    
    // 闰年2月
    try testing.expectEqual(29, getDaysInMonth(2024, 2));
}

test "calculateTimestamp - Unix纪元" {
    // 1970-01-01 00:00:00 应该是 0
    const ts = try calculateTimestamp(1970, 1, 1, 0, 0, 0);
    try testing.expectEqual(0, ts);
}

test "calculateTimestamp - 基本日期" {
    // 1970-01-02 00:00:00 应该是 86400 (1天)
    {
        const ts = try calculateTimestamp(1970, 1, 2, 0, 0, 0);
        try testing.expectEqual(86400, ts);
    }
    
    // 1970-01-01 01:00:00 应该是 3600 (1小时)
    {
        const ts = try calculateTimestamp(1970, 1, 1, 1, 0, 0);
        try testing.expectEqual(3600, ts);
    }
    
    // 1970-01-01 00:01:00 应该是 60 (1分钟)
    {
        const ts = try calculateTimestamp(1970, 1, 1, 0, 1, 0);
        try testing.expectEqual(60, ts);
    }
    
    // 1970-01-01 00:00:01 应该是 1 (1秒)
    {
        const ts = try calculateTimestamp(1970, 1, 1, 0, 0, 1);
        try testing.expectEqual(1, ts);
    }
}

test "calculateTimestamp - 2024年测试" {
    // 2024-01-19 12:00:00 UTC
    const ts = try calculateTimestamp(2024, 1, 19, 12, 0, 0);
    try testing.expectEqual(1705665600, ts);
}

test "calculateTimestamp - 闰年测试" {
    // 2024-02-29 (闰年)
    const ts1 = try calculateTimestamp(2024, 2, 29, 0, 0, 0);
    try testing.expect(ts1 > 0);
    
    // 2024-03-01 应该比 2024-02-29 多一天
    const ts2 = try calculateTimestamp(2024, 3, 1, 0, 0, 0);
    try testing.expectEqual(ts1 + 86400, ts2);
}

test "calculateTimestamp - 月份规范化" {
    // 2024-13-01 应该等于 2025-01-01
    const ts1 = try calculateTimestamp(2024, 13, 1, 0, 0, 0);
    const ts2 = try calculateTimestamp(2025, 1, 1, 0, 0, 0);
    try testing.expectEqual(ts2, ts1);
    
    // 2024-14-01 应该等于 2025-02-01
    const ts3 = try calculateTimestamp(2024, 14, 1, 0, 0, 0);
    const ts4 = try calculateTimestamp(2025, 2, 1, 0, 0, 0);
    try testing.expectEqual(ts4, ts3);
}

test "calculateTimestamp - 负月份规范化" {
    // 2024-0-01 应该等于 2023-12-01
    const ts1 = try calculateTimestamp(2024, 0, 1, 0, 0, 0);
    const ts2 = try calculateTimestamp(2023, 12, 1, 0, 0, 0);
    try testing.expectEqual(ts2, ts1);
}

test "calculateTimestamp - 完整日期时间" {
    // 2024-06-15 14:30:45
    const ts = try calculateTimestamp(2024, 6, 15, 14, 30, 45);
    
    // 验证：应该是正数且合理
    try testing.expect(ts > 1700000000); // 大于2023年
    try testing.expect(ts < 1800000000); // 小于2027年
}

test "calculateTimestamp - 年份跨度" {
    // 测试多个年份
    const years = [_]i32{ 1970, 1980, 1990, 2000, 2010, 2020, 2024 };
    
    for (years) |year| {
        const ts = try calculateTimestamp(year, 1, 1, 0, 0, 0);
        try testing.expect(ts >= 0);
        
        // 验证年份递增时间戳也递增
        if (year > 1970) {
            const prev_ts = try calculateTimestamp(year - 1, 1, 1, 0, 0, 0);
            try testing.expect(ts > prev_ts);
        }
    }
}

test "calculateTimestamp - 边界条件" {
    // 测试每月最后一天
    const months = [_]struct { month: i32, days: i32 }{
        .{ .month = 1, .days = 31 },
        .{ .month = 2, .days = 28 }, // 平年
        .{ .month = 3, .days = 31 },
        .{ .month = 4, .days = 30 },
        .{ .month = 5, .days = 31 },
        .{ .month = 6, .days = 30 },
        .{ .month = 7, .days = 31 },
        .{ .month = 8, .days = 31 },
        .{ .month = 9, .days = 30 },
        .{ .month = 10, .days = 31 },
        .{ .month = 11, .days = 30 },
        .{ .month = 12, .days = 31 },
    };
    
    for (months) |m| {
        const ts = try calculateTimestamp(2023, m.month, m.days, 23, 59, 59);
        try testing.expect(ts > 0);
    }
}

test "calculateTimestamp - 一致性检查" {
    // 验证相同日期总是产生相同时间戳
    const ts1 = try calculateTimestamp(2024, 1, 19, 12, 0, 0);
    const ts2 = try calculateTimestamp(2024, 1, 19, 12, 0, 0);
    try testing.expectEqual(ts1, ts2);
    
    // 验证不同日期产生不同时间戳
    const ts3 = try calculateTimestamp(2024, 1, 20, 12, 0, 0);
    try testing.expect(ts1 != ts3);
}
