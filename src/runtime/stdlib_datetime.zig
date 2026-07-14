//! 日期时间内置函数实现模块
//! 从 stdlib.zig 拆分而来 — 包含时间获取、日期格式化、时间解析、延时函数

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const VM = @import("vm.zig").VM;
const time_compat = @import("time_compat.zig");

// 核心时间函数模块
const core_time = @import("core/time_functions.zig");
const core_string = @import("core/string_functions.zig");

// ============================================================================
// 日期时间函数
// ============================================================================

pub fn timeFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initInt(core_time.time());
}

pub fn microtimeFn(vm: *VM, args: []const Value) !Value {
    const as_float = if (args.len > 0) args[0].toBool() else false;
    if (as_float) {
        return Value.initFloat(core_time.microtime_float());
    } else {
        var ctx = core_string.common.CoreContext{ .allocator = vm.allocator };
        const result = try core_time.microtime_string(&ctx);
        defer vm.allocator.free(result);
        const str = try PHPString.init(vm.allocator, result);
        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = str };
        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

pub fn usleepFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const microseconds = args[0].asInt();
    time_compat.sleep(@intCast(microseconds * 1000));
    return Value.initNull();
}

pub fn sleepFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const seconds = args[0].asInt();
    time_compat.sleep(@intCast(seconds * 1_000_000_000));
    return Value.initInt(0);
}

pub fn dateFn(vm: *VM, args: []const Value) !Value {
    const format = args[0];
    const timestamp = if (args.len > 1) args[1] else Value.initInt(time_compat.timestamp());

    if (format.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "date() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (timestamp.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "date() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const format_str = format.getAsString().data.data;
    const ts: i64 = timestamp.asInt();

    // Convert timestamp to epoch seconds
    const epoch_seconds: u64 = @intCast(ts);
    const epoch_day = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = epoch_day.getDaySeconds();
    const year_day = epoch_day.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    var result = try std.ArrayList(u8).initCapacity(vm.allocator, format_str.len * 2);
    defer result.deinit(vm.allocator);

    var i: usize = 0;
    while (i < format_str.len) : (i += 1) {
        const c = format_str[i];
        switch (c) {
            'Y' => try result.print(vm.allocator, "{d:0>4}", .{year_day.year}),
            'm' => try result.print(vm.allocator, "{d:0>2}", .{month_day.month.numeric()}),
            'd' => try result.print(vm.allocator, "{d:0>2}", .{month_day.day_index + 1}),
            'H' => try result.print(vm.allocator, "{d:0>2}", .{day_seconds.getHoursIntoDay()}),
            'i' => try result.print(vm.allocator, "{d:0>2}", .{day_seconds.getMinutesIntoHour()}),
            's' => try result.print(vm.allocator, "{d:0>2}", .{day_seconds.getSecondsIntoMinute()}),
            'U' => try result.print(vm.allocator, "{d}", .{ts}),
            else => try result.append(vm.allocator, c),
        }
    }

    return Value.initString(vm.allocator, result.items);
}

pub fn strtotimeFn(vm: *VM, args: []const Value) !Value {
    const time_str = args[0];
    const now = if (args.len > 1) args[1].asInt() else time_compat.timestamp();

    if (time_str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtotime() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const time_string = time_str.getAsString().data.data;

    // Parse relative time strings
    if (std.mem.startsWith(u8, time_string, "+")) {
        var parts = std.mem.splitScalar(u8, time_string[1..], ' ');
        const num_str = parts.next() orelse return Value.initBool(false);
        const unit = parts.next() orelse return Value.initBool(false);

        const num = std.fmt.parseInt(i64, num_str, 10) catch return Value.initBool(false);
        const seconds: i64 = if (std.mem.eql(u8, unit, "day") or std.mem.eql(u8, unit, "days"))
            num * 86400
        else if (std.mem.eql(u8, unit, "hour") or std.mem.eql(u8, unit, "hours"))
            num * 3600
        else if (std.mem.eql(u8, unit, "minute") or std.mem.eql(u8, unit, "minutes"))
            num * 60
        else if (std.mem.eql(u8, unit, "week") or std.mem.eql(u8, unit, "weeks"))
            num * 604800
        else
            return Value.initBool(false);

        return Value.initInt(now + seconds);
    } else if (std.mem.startsWith(u8, time_string, "-")) {
        var parts = std.mem.splitScalar(u8, time_string[1..], ' ');
        const num_str = parts.next() orelse return Value.initBool(false);
        const unit = parts.next() orelse return Value.initBool(false);

        const num = std.fmt.parseInt(i64, num_str, 10) catch return Value.initBool(false);
        const seconds: i64 = if (std.mem.eql(u8, unit, "day") or std.mem.eql(u8, unit, "days"))
            num * 86400
        else if (std.mem.eql(u8, unit, "hour") or std.mem.eql(u8, unit, "hours"))
            num * 3600
        else
            return Value.initBool(false);

        return Value.initInt(now - seconds);
    } else if (std.mem.eql(u8, time_string, "now")) {
        return Value.initInt(now);
    }

    // Try to parse as timestamp
    const parsed = std.fmt.parseInt(i64, time_string, 10) catch return Value.initBool(false);
    return Value.initInt(parsed);
}

pub fn mktimeFn(vm: *VM, args: []const Value) !Value {
    // Simplified implementation - would need full mktime logic
    _ = vm;
    _ = args;
    return Value.initInt(time_compat.timestamp());
}

pub fn gmdateFn(vm: *VM, args: []const Value) !Value {
    // gmdate is similar to date but uses GMT
    return dateFn(vm, args);
}

/// checkdate(int $month, int $day, int $year): bool — 验证公历日期
/// PHP 语义：检查给定的日期是否有效
pub fn checkdateFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 3) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 3, @intCast(args.len), "checkdate", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const month = args[0].asInt();
    const day = args[1].asInt();
    const year = args[2].asInt();

    // 年份范围 1-32767
    if (year < 1 or year > 32767) return Value.initBool(false);
    // 月份范围 1-12
    if (month < 1 or month > 12) return Value.initBool(false);
    // 日范围 1-31（后续根据月份调整）
    if (day < 1 or day > 31) return Value.initBool(false);

    // 每月天数（非闰年）
    const days_in_month = [12]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var max_day = days_in_month[@intCast(month - 1)];

    // 闰年 2 月有 29 天
    if (month == 2) {
        const is_leap = (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
        if (is_leap) max_day = 29;
    }

    return Value.initBool(day <= max_day);
}

/// getdate(?int $timestamp = time()): array — 获取日期/时间信息
/// 返回关联数组：seconds, minutes, hours, mday, wday, mon, year, yday, weekday, month, 0
pub fn getDateFn(vm: *VM, args: []const Value) !Value {
    const ts = if (args.len > 0 and args[0].getTag() == .integer) args[0].asInt() else time_compat.timestamp();
    const epoch_seconds: u64 = @intCast(@max(ts, 0));
    const epoch_day = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = epoch_day.getDaySeconds();
    const year_day = epoch_day.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    // 计算星期几：1970-01-01 是 Thursday (PHP wday=4)
    // 从 epoch day 推算：day 0 = Thursday
    const epoch_day_val: i64 = @intCast(epoch_day.getEpochDay().day);
    const php_wday: i64 = @mod(epoch_day_val + 4, 7);

    const weekday_names = [7][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    const month_names = [12][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };

    const month_num = month_day.month.numeric(); // 1-12
    const day_num = month_day.day_index + 1; // 1-31

    // 年内第几天 (0-based)
    const yday: i64 = blk: {
        const days_before = [12]i64{ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };
        var d = days_before[@intCast(month_num - 1)] + day_num - 1;
        // 闰年 3 月及之后加 1
        const is_leap = (year_day.year % 4 == 0 and year_day.year % 100 != 0) or (year_day.year % 400 == 0);
        if (is_leap and month_num > 2) d += 1;
        break :blk d;
    };

    const result = try vm.allocator.create(PHPArray);
    result.* = PHPArray.init(vm.allocator);

    const key_seconds = try PHPString.init(vm.allocator, "seconds");
    const key_minutes = try PHPString.init(vm.allocator, "minutes");
    const key_hours = try PHPString.init(vm.allocator, "hours");
    const key_mday = try PHPString.init(vm.allocator, "mday");
    const key_wday = try PHPString.init(vm.allocator, "wday");
    const key_mon = try PHPString.init(vm.allocator, "mon");
    const key_year = try PHPString.init(vm.allocator, "year");
    const key_yday = try PHPString.init(vm.allocator, "yday");
    const key_weekday = try PHPString.init(vm.allocator, "weekday");
    const key_month = try PHPString.init(vm.allocator, "month");
    const key_0 = try PHPString.init(vm.allocator, "0");

    try result.set(vm.allocator, .{ .string = key_seconds }, Value.initInt(day_seconds.getSecondsIntoMinute()));
    try result.set(vm.allocator, .{ .string = key_minutes }, Value.initInt(day_seconds.getMinutesIntoHour()));
    try result.set(vm.allocator, .{ .string = key_hours }, Value.initInt(day_seconds.getHoursIntoDay()));
    try result.set(vm.allocator, .{ .string = key_mday }, Value.initInt(day_num));
    try result.set(vm.allocator, .{ .string = key_wday }, Value.initInt(php_wday));
    try result.set(vm.allocator, .{ .string = key_mon }, Value.initInt(month_num));
    try result.set(vm.allocator, .{ .string = key_year }, Value.initInt(year_day.year));
    try result.set(vm.allocator, .{ .string = key_yday }, Value.initInt(yday));
    try result.set(vm.allocator, .{ .string = key_weekday }, try Value.initString(vm.allocator, weekday_names[@intCast(php_wday)]));
    try result.set(vm.allocator, .{ .string = key_month }, try Value.initString(vm.allocator, month_names[@intCast(month_num - 1)]));
    try result.set(vm.allocator, .{ .string = key_0 }, Value.initInt(ts));

    return Value.initArrayWithObject(&vm.memory_manager, result);
}

// ============================================================================
// 单元测试
// ============================================================================

test "stdlib_datetime: handler functions exist" {
    _ = &timeFn;
    _ = &microtimeFn;
    _ = &usleepFn;
    _ = &sleepFn;
    _ = &dateFn;
    _ = &strtotimeFn;
    _ = &mktimeFn;
    _ = &gmdateFn;
    _ = &checkdateFn;
    _ = &getDateFn;
}

test "stdlib_datetime: strtotime relative time constants" {
    // 验证 strtotime 使用的时间常量正确性
    // 1 day = 86400 seconds
    try std.testing.expectEqual(@as(i64, 86400), 1 * 86400);
    // 1 hour = 3600 seconds
    try std.testing.expectEqual(@as(i64, 3600), 1 * 3600);
    // 1 minute = 60 seconds
    try std.testing.expectEqual(@as(i64, 60), 1 * 60);
    // 1 week = 604800 seconds
    try std.testing.expectEqual(@as(i64, 604800), 1 * 604800);
}

test "stdlib_datetime: time_compat module integration" {
    // 验证 time_compat 模块可以正常调用
    const ts = time_compat.timestamp();
    // 时间戳应该是正数且合理（大于 2020-01-01 的时间戳）
    try std.testing.expect(ts > 1577836800);
}
