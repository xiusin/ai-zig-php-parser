const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

// ============================================================================
// 时间函数（从VM实现复用）
// ============================================================================

/// time - 返回当前Unix时间戳
pub fn php_time() Value {
    const timestamp = unixTimestamp();
    return Value.initInt(timestamp);
}

/// getdate - 获取日期/时间信息
pub fn php_getdate(ts_val: Value, allocator: Allocator) !Value {
    const timestamp = if (ts_val.isNull()) unixTimestamp() else ts_val.toInt();
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(@as(u64, @bitCast(timestamp))) };
    const day_seconds = epoch.getDaySeconds();
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const year = year_day.year;
    const month: i64 = @intCast(@intFromEnum(month_day.month));
    const day: i64 = @intCast(month_day.day_index + 1);
    const hours: i64 = @intCast(day_seconds.getHoursIntoDay());
    const minutes: i64 = @intCast(day_seconds.getMinutesIntoHour());
    const seconds_val: i64 = @intCast(day_seconds.getSecondsIntoMinute());
    // 计算星期几：1970-01-01是周四(4)，PHP wday: 0=周日,1=周一,...,6=周六
    const days_since_epoch: i64 = @intCast(epoch_day.day);
    const wday: i64 = @mod(days_since_epoch + 4, 7);
    // 一年中的第几天：year_day.day 是0-based，PHP yday也是0-based
    const yday: i64 = @intCast(year_day.day);

    const arr = try PHPArray.init(allocator);
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "seconds")), Value.initInt(seconds_val));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "minutes")), Value.initInt(minutes));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "hours")), Value.initInt(hours));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "mday")), Value.initInt(day));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "wday")), Value.initInt(wday));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "mon")), Value.initInt(month));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "year")), Value.initInt(@intCast(@as(i32, year))));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "yday")), Value.initInt(yday));
    const weekday_names = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    const month_names   = [_][]const u8{ "", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const wday_idx = @as(usize, @intCast(@mod(wday, 7)));
    const mon_idx  = @as(usize, @intCast(@min(@max(month, 1), 12)));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "weekday")), Value.initString(try PHPString.init(allocator, weekday_names[wday_idx])));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "month")),   Value.initString(try PHPString.init(allocator, month_names[mon_idx])));
    try arr.setByValue(allocator, Value.initInt(0), Value.initInt(timestamp));
    return Value.initArray(arr);
}

pub fn php_idate(format_val: Value, ts_val: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!format_val.isString()) return Value.initInt(0);
    const fmt = format_val.asString().data;
    if (fmt.len == 0) return Value.initInt(0);
    const timestamp = if (ts_val.isNull()) unixTimestamp() else ts_val.toInt();
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(@as(u64, @bitCast(timestamp))) };
    const day_seconds = epoch.getDaySeconds();
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const hours: i64 = @intCast(day_seconds.getHoursIntoDay());
    const minutes: i64 = @intCast(day_seconds.getMinutesIntoHour());
    const secs: i64   = @intCast(day_seconds.getSecondsIntoMinute());
    const day: i64    = @intCast(month_day.day_index + 1);
    const month: i64  = @intCast(@intFromEnum(month_day.month));
    const year: i64   = @intCast(@as(i32, year_day.year));
    const days_since_epoch: i64 = @intCast(epoch_day.day);
    const wday: i64   = @mod(days_since_epoch + 4, 7);
    const yday: i64   = @intCast(year_day.day);
    const result: i64 = switch (fmt[0]) {
        'Y' => year,
        'y' => @mod(year, 100),
        'n', 'm' => month,
        'j', 'd' => day,
        'H' => hours,
        'h' => blk: { const h = @mod(hours, 12); break :blk if (h == 0) 12 else h; },
        'i' => minutes,
        's' => secs,
        'w', 'l' => wday,
        'z' => yday,
        'U' => timestamp,
        else => 0,
    };
    return Value.initInt(result);
}

/// mktime(hour, minute, second, month, day, year) -> Unix timestamp
pub fn php_mktime(hour: Value, minute: Value, second: Value, month: Value, day: Value, year: Value) Value {
    const h = hour.toInt();
    const mi = minute.toInt();
    const s = second.toInt();
    const mon = month.toInt();
    const d = day.toInt();
    var y = year.toInt();
    // PHP: 0-69 => 2000-2069, 70-100 => 1970-2000
    if (y >= 0 and y <= 69) y += 2000;
    if (y >= 70 and y <= 100) y += 1900;
    const days_per_month = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var total_days: i64 = 0;
    var yi: i64 = 1970;
    while (yi < y) : (yi += 1) {
        const is_leap = (@rem(yi, 4) == 0 and @rem(yi, 100) != 0) or (@rem(yi, 400) == 0);
        total_days += if (is_leap) 366 else 365;
    }
    var mi2: i64 = 1;
    while (mi2 < mon) : (mi2 += 1) {
        const idx = @as(usize, @intCast(mi2 - 1));
        total_days += days_per_month[idx];
        if (mi2 == 2) {
            const is_leap = (@rem(y, 4) == 0 and @rem(y, 100) != 0) or (@rem(y, 400) == 0);
            if (is_leap) total_days += 1;
        }
    }
    total_days += d - 1;
    const ts = total_days * 86400 + h * 3600 + mi * 60 + s;
    return Value.initInt(ts);
}

/// checkdate(month, day, year) -> bool: 验证日期合法性
pub fn php_checkdate(month: Value, day: Value, year: Value) Value {
    const m = month.toInt();
    const d = day.toInt();
    const y = year.toInt();
    if (y < 1 or y > 32767) return Value.initBool(false);
    if (m < 1 or m > 12) return Value.initBool(false);
    if (d < 1) return Value.initBool(false);
    const days_in_month = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const is_leap = (@rem(y, 4) == 0 and @rem(y, 100) != 0) or (@rem(y, 400) == 0);
    var max_day = days_in_month[@as(usize, @intCast(m - 1))];
    if (m == 2 and is_leap) max_day = 29;
    return Value.initBool(d <= max_day);
}

/// gmdate(format, timestamp=null) -> string: UTC格式化（与date相同，时间戳已是UTC）
pub fn php_gmdate(format: Value, timestamp: Value, allocator: Allocator) !Value {
    if (!format.isString()) return Value.initString(try PHPString.init(allocator, ""));
    const ts = if (timestamp.isNull())
        unixTimestamp()
    else if (timestamp.isInt())
        timestamp.asInt()
    else if (timestamp.isFloat())
        @as(i64, @intFromFloat(timestamp.asFloat()))
    else
        unixTimestamp();
    return formatPhpDateValue(ts, format.asString().data, allocator);
}

/// microtime - 返回当前时间（带微秒）
///
/// @param get_as_float 是否返回浮点数格式
/// @param allocator 内存分配器
/// @return 字符串格式 "0.microseconds seconds" 或浮点数时间戳
pub fn php_microtime(get_as_float: Value, allocator: Allocator) !Value {
    const now_ns = nanoTimestamp();
    const sec = @divTrunc(now_ns, std.time.ns_per_s);
    const usec = @divTrunc(@mod(now_ns, std.time.ns_per_s), std.time.ns_per_us);

    // 检查是否返回浮点数
    const as_float = if (get_as_float.isBool())
        get_as_float.asBool()
    else if (get_as_float.isInt())
        get_as_float.asInt() != 0
    else
        false;

    if (as_float) {
        // 返回浮点数时间戳
        const float_time = @as(f64, @floatFromInt(sec)) + @as(f64, @floatFromInt(usec)) / 1000000.0;
        return Value.initFloat(float_time);
    } else {
        // 返回字符串格式 "0.microseconds seconds"
        const formatted = try std.fmt.allocPrint(allocator, "0.{d:0>6} {d}", .{ usec, sec });
        defer allocator.free(formatted);
        const result = try PHPString.init(allocator, formatted);
        return Value.initString(result);
    }
}

fn formatPhpDateValue(timestamp: i64, format_str: []const u8, allocator: Allocator) !Value {
    const epoch_seconds: u64 = @intCast(@max(@as(i64, 0), timestamp));
    const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = epoch.getDaySeconds();
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const days_since_epoch: i64 = @intCast(epoch_day.day);
    const wday: usize = @intCast(@mod(days_since_epoch + 4, 7)); // 0=Sun
    const year: i64 = @intCast(@as(i32, year_day.year));
    const month: usize = @intCast(month_day.month.numeric());
    const day: usize = @intCast(month_day.day_index + 1);
    const hour: usize = @intCast(day_seconds.getHoursIntoDay());
    const minute: usize = @intCast(day_seconds.getMinutesIntoHour());
    const second: usize = @intCast(day_seconds.getSecondsIntoMinute());

    const weekday_full = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    const weekday_short = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    const month_full = [_][]const u8{ "", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const month_short = [_][]const u8{ "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    var aw2 = std.Io.Writer.Allocating.initCapacity(allocator, format_str.len * 2) catch return Value.initNull();
    defer aw2.deinit();

    var i: usize = 0;
    while (i < format_str.len) : (i += 1) {
        const c = format_str[i];
        switch (c) {
            // Year
            'Y' => try aw2.writer.print("{d:0>4}", .{@as(u32, @intCast(year))}),
            'y' => try aw2.writer.print("{d:0>2}", .{@as(u32, @intCast(@mod(year, 100)))}),
            // Month
            'm' => try aw2.writer.print("{d:0>2}", .{month}),
            'n' => try aw2.writer.print("{d}", .{month}),
            'F' => try aw2.writer.writeAll(month_full[month]),
            'M' => try aw2.writer.writeAll(month_short[month]),
            // Day
            'd' => try aw2.writer.print("{d:0>2}", .{day}),
            'j' => try aw2.writer.print("{d}", .{day}),
            // Weekday
            'l' => try aw2.writer.writeAll(weekday_full[wday]),
            'D' => try aw2.writer.writeAll(weekday_short[wday]),
            'w' => try aw2.writer.print("{d}", .{wday}),
            'N' => try aw2.writer.print("{d}", .{if (wday == 0) @as(usize, 7) else wday}), // ISO: Mon=1..Sun=7
            // Hour
            'H' => try aw2.writer.print("{d:0>2}", .{hour}),
            'G' => try aw2.writer.print("{d}", .{hour}),
            'h' => try aw2.writer.print("{d:0>2}", .{if (@mod(hour, 12) == 0) @as(usize, 12) else @mod(hour, 12)}),
            'g' => try aw2.writer.print("{d}", .{if (@mod(hour, 12) == 0) @as(usize, 12) else @mod(hour, 12)}),
            'A' => try aw2.writer.writeAll(if (hour < 12) "AM" else "PM"),
            'a' => try aw2.writer.writeAll(if (hour < 12) "am" else "pm"),
            // Minute / second
            'i' => try aw2.writer.print("{d:0>2}", .{minute}),
            's' => try aw2.writer.print("{d:0>2}", .{second}),
            // Timestamp
            'U' => try aw2.writer.print("{d}", .{timestamp}),
            // Day of year (0-based in PHP)
            'z' => try aw2.writer.print("{d}", .{year_day.day}),
            // Escape
            '\\' => {
                i += 1;
                if (i < format_str.len) try aw2.writer.writeAll(format_str[i .. i + 1]);
            },
            else => try aw2.writer.writeAll(&[_]u8{c}),
        }
    }

    return Value.initString(try PHPString.init(allocator, aw2.written()));
}

/// date - 格式化日期时间
///
/// 注意：这是一个简化实现，仅支持基本格式
/// 完整的PHP date()函数支持更多格式选项
///
/// @param format 格式字符串
/// @param timestamp 时间戳（可选，默认当前时间）
/// @param allocator 内存分配器
/// @return 格式化后的日期字符串
pub fn php_date(format: Value, timestamp: Value, allocator: Allocator) !Value {
    if (!format.isString()) {
        return Value.initString(try PHPString.init(allocator, ""));
    }

    // 获取时间戳
    const ts = if (timestamp.isNull())
        unixTimestamp()
    else if (timestamp.isInt())
        timestamp.asInt()
    else if (timestamp.isFloat())
        @as(i64, @intFromFloat(timestamp.asFloat()))
    else
        unixTimestamp();

    return formatPhpDateValue(ts, format.asString().data, allocator);
}

// ============================================================================
// 随机数函数（MT19937实现，PHP兼容）
// ============================================================================

/// MT19937状态
const MT19937 = struct {
    state: [624]u32 = undefined,
    index: usize = 624,

    fn init(seed: u32) MT19937 {
        var mt = MT19937{};
        mt.state[0] = seed;
        var i: usize = 1;
        while (i < 624) : (i += 1) {
            mt.state[i] = 1812433253 *% (mt.state[i - 1] ^ (mt.state[i - 1] >> 30)) +% @as(u32, @intCast(i));
        }
        mt.index = 624;
        return mt;
    }

    fn generate(self: *MT19937) u32 {
        if (self.index >= 624) {
            self.twist();
        }
        var y = self.state[self.index];
        self.index += 1;

        y ^= (y >> 11);
        y ^= (y << 7) & 0x9D2C5680;
        y ^= (y << 15) & 0xEFC60000;
        y ^= (y >> 18);

        return y;
    }

    fn twist(self: *MT19937) void {
        var i: usize = 0;
        while (i < 624) : (i += 1) {
            const x = (self.state[i] & 0x80000000) + (self.state[(i + 1) % 624] & 0x7FFFFFFF);
            var xA = x >> 1;
            if ((x & 1) != 0) {
                xA ^= 0x9908B0DF;
            }
            self.state[i] = self.state[(i + 397) % 624] ^ xA;
        }
        self.index = 0;
    }
};

threadlocal var mt_state: ?MT19937 = null;

fn nextRandom() u64 {
    if (mt_state == null) {
        mt_state = MT19937.init(@intCast(@as(u64, @intCast(unixTimestamp())) & 0xFFFFFFFF));
    }
    return @as(u64, mt_state.?.generate());
}

/// rand - 生成随机整数
///
/// @param min 最小值（可选）
/// @param max 最大值（可选）
/// @return 随机整数
pub fn php_rand(min: Value, max: Value) !Value {
    if (min.isNull() and max.isNull()) {
        // 无参数：返回 0 到 RAND_MAX (PHP uses generate() >> 1)
        const random = nextRandom();
        return Value.initInt(@as(i64, @intCast(random >> 1)));
    }

    const min_val = min.toInt();
    const max_val = max.toInt();

    if (min_val > max_val) {
        return Value.initInt(min_val);
    }

    const range = @as(u64, @intCast(max_val - min_val + 1));
    const random = nextRandom() % range;

    return Value.initInt(min_val + @as(i64, @intCast(random)));
}

/// mt_rand - 生成随机整数（Mersenne Twister）
///
/// 注意：这是简化实现，使用与rand()相同的生成器
/// 完整实现应该使用真正的MT19937算法
///
/// @param min 最小值（可选）
/// @param max 最大值（可选）
/// @return 随机整数
pub fn php_mt_rand(min: Value, max: Value) !Value {
    // 确保mt_state已初始化
    if (mt_state == null) {
        mt_state = MT19937.init(@intCast(@as(u64, @intCast(unixTimestamp())) & 0xFFFFFFFF));
    }
    
    // mt_rand() - 无参数，返回0到MT_RAND_MAX
    // mt_rand(min, max) - 返回min到max之间的随机数
    if (min.isNull() and max.isNull()) {
        // 无参数：返回0到2147483647 (PHP uses generate() >> 1)
        return Value.initInt(@intCast(mt_state.?.generate() >> 1));
    }
    return php_rand(min, max);
}

/// srand - 设置随机数种子
///
/// @param seed 种子值（可选）
pub fn php_srand(seed: Value) !Value {
    if (seed.isNull()) {
        mt_state = MT19937.init(@intCast(@as(u64, @intCast(unixTimestamp())) & 0xFFFFFFFF));
    } else {
        mt_state = MT19937.init(@intCast(@as(u64, @intCast(@abs(seed.toInt()))) & 0xFFFFFFFF));
    }
    return Value.initNull();
}

/// mt_srand - 设置MT随机数种子
///
/// @param seed 种子值（可选）
pub fn php_mt_srand(seed: Value) !Value {
    return php_srand(seed);
}

/// random_int - 生成密码学安全的随机整数
///
/// @param min 最小值
/// @param max 最大值
/// @return 随机整数
pub fn php_random_int(min: Value, max: Value) !Value {
    const min_val = min.toInt();
    const max_val = max.toInt();

    if (min_val > max_val) {
        return error.InvalidRange;
    }

    // 使用密码学安全的随机数生成器
    const random_val = std.crypto.random.intRangeAtMost(i64, min_val, max_val);
    return Value.initInt(random_val);
}

/// random_bytes - 生成密码学安全的随机字节
///
/// @param length 字节数
/// @param allocator 内存分配器
/// @return 随机字节字符串
pub fn php_random_bytes(length: Value, allocator: Allocator) !Value {
    const len = length.toInt();

    if (len < 0) {
        return error.InvalidLength;
    }

    const byte_len = @as(usize, @intCast(len));
    const buffer = try allocator.alloc(u8, byte_len);
    errdefer allocator.free(buffer);

    // 填充密码学安全的随机字节
    std.crypto.random.bytes(buffer);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

// ============================================================================
// 扩展数组函数
// ============================================================================

/// array_shift - 移除并返回数组的第一个元素
pub fn php_array_shift(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const v = array_ops_shared.shift(ArrayKey, Value, @TypeOf(php_arr.elements), allocator, &php_arr.elements, &php_arr.next_index) orelse return Value.initNull();
    return v;
}

/// array_unshift - 在数组开头添加元素
pub fn php_array_unshift(arr: Value, values: []const Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();
    try array_ops_shared.unshift(ArrayKey, Value, @TypeOf(php_arr.elements), allocator, &php_arr.elements, &php_arr.next_index, values);
    return Value.initInt(@intCast(php_arr.count()));
}

/// array_search - 在数组中搜索值并返回键
pub fn php_array_search(needle: Value, haystack: Value) !Value {
    if (!haystack.isArray()) return Value.initBool(false);

    const arr = haystack.asArray();
    var it = arr.elements.iterator();

    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        // 使用松散比较
        const eq_result = try php_eq(needle, val);
        if (eq_result.asBool()) {
            // 返回键
            return switch (entry.key_ptr.*) {
                .integer => |k| Value.initInt(k),
                .string => |k| blk: {
                    k.retain();
                    break :blk Value.initString(k);
                },
            };
        }
    }

    return Value.initBool(false);
}

/// array_sum - 计算数组元素的总和（packed int 快速路径 + SIMD 向量化）
pub fn php_array_sum(arr: Value) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();

    if (php_arr.elements.mixed == null) {
        const items = php_arr.elements.packed_values.items;
        if (items.len == 0) return Value.initInt(0);

        var all_int = true;
        for (items) |v| {
            if (!v.isInt()) {
                all_int = false;
                break;
            }
        }

        if (all_int) {
            return Value.initInt(fastPackedIntSum(items));
        }
    }

    var sum_int: i64 = 0;
    var sum_float: f64 = 0;
    var has_float = false;

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        if (val.isFloat()) {
            has_float = true;
            sum_float += val.asFloat();
        } else {
            sum_int += val.toInt();
        }
    }

    if (has_float) {
        return Value.initFloat(sum_float + @as(f64, @floatFromInt(sum_int)));
    }
    return Value.initInt(sum_int);
}

/// packed int 数组快速求和：comptime @Vector SIMD 优化
fn fastPackedIntSum(items: []const Value) i64 {
    // comptime 自动选择最优向量宽度
    const vec_len = comptime std.simd.suggestVectorLength(i64) orelse 4;
    const V = @Vector(vec_len, i64);

    var accum: V = @splat(0);
    var i: usize = 0;
    const len = items.len;

    // 主循环：向量化累加
    const aligned = len & ~@as(usize, vec_len - 1);
    while (i < aligned) : (i += vec_len) {
        var batch: V = undefined;
        inline for (0..vec_len) |j| {
            batch[j] = items[i + j].toInt();
        }
        accum +%= batch;
    }

    // 水平归约
    var sum: i64 = @reduce(.Add, accum);

    // 处理剩余元素
    while (i < len) : (i += 1) {
        sum +%= items[i].toInt();
    }

    return sum;
}

/// array_product - 计算数组元素的乘积
pub fn php_array_product(arr: Value) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();
    if (php_arr.count() == 0) return Value.initInt(1);

    var product: f64 = 1;
    var it = php_arr.elements.iterator();

    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        product *= val.toFloat();
    }

    // 如果结果是整数，返回整数
    if (@floor(product) == product and product >= @as(f64, @floatFromInt(std.math.minInt(i64))) and product <= @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
        return Value.initInt(@intFromFloat(product));
    }
    return Value.initFloat(product);
}

/// array_reverse - 反转数组
pub fn php_array_reverse(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    // 收集所有元素
    var values = try allocator.alloc(Value, php_arr.count());
    defer allocator.free(values);

    var idx: usize = 0;
    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        values[idx] = entry.value_ptr.*;
        idx += 1;
    }

    // 反向添加
    var i: usize = values.len;
    while (i > 0) {
        i -= 1;
        try result.push(allocator, values[i]);
    }

    return Value.initArray(result);
}

/// array_unique - 移除数组中的重复值
pub fn php_array_unique(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;

        // 检查是否已存在
        var exists = false;
        var result_it = result.elements.iterator();
        while (result_it.next()) |existing| {
            const eq_result = try php_eq(val, existing.value_ptr.*);
            if (eq_result.asBool()) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            try result.set(allocator, entry.key_ptr.*, val);
        }
    }

    return Value.initArray(result);
}

/// array_flip - 交换数组的键和值
pub fn php_array_flip(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        const key = entry.key_ptr.*;

        // 值变成键，键变成值
        if (val.isInt()) {
            try result.set(allocator, .{ .integer = val.asInt() }, switch (key) {
                .integer => |k| Value.initInt(k),
                .string => |k| Value.initString(k),
            });
        } else if (val.isString()) {
            try result.set(allocator, .{ .string = val.asString() }, switch (key) {
                .integer => |k| Value.initInt(k),
                .string => |k| Value.initString(k),
            });
        }
    }

    return Value.initArray(result);
}

/// array_key_exists - 检查数组中是否存在指定的键
pub fn php_array_key_exists(key: Value, arr: Value) !Value {
    if (!arr.isArray()) return Value.initBool(false);

    const php_arr = arr.asArray();
    return Value.initBool(php_arr.get(normalizeArrayKeyFromValue(key)) != null);
}

/// array_key_first - 获取数组的第一个键
pub fn php_array_key_first(arr: Value) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    var it = php_arr.elements.iterator();

    if (it.next()) |entry| {
        return switch (entry.key_ptr.*) {
            .integer => |k| Value.initInt(k),
            .string => |k| blk: {
                k.retain();
                break :blk Value.initString(k);
            },
        };
    }

    return Value.initNull();
}

/// array_key_last - 获取数组的最后一个键
pub fn php_array_key_last(arr: Value) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    var last_key: ?ArrayKey = null;

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        last_key = entry.key_ptr.*;
    }

    if (last_key) |key| {
        return switch (key) {
            .integer => |k| Value.initInt(k),
            .string => |k| blk: {
                k.retain();
                break :blk Value.initString(k);
            },
        };
    }

    return Value.initNull();
}

/// array_fill - 用指定值填充数组
pub fn php_array_fill(start_index: Value, num: Value, value: Value, allocator: Allocator) !Value {
    const result = try PHPArray.init(allocator);

    const start = start_index.toInt();
    const count = @max(0, num.toInt());

    var i: i64 = 0;
    while (i < count) : (i += 1) {
        try result.set(allocator, .{ .integer = start + i }, value);
    }

    return Value.initArray(result);
}

/// range - 创建包含指定范围元素的数组
pub fn php_range(start: Value, end: Value, allocator: Allocator) !Value {
    const result = try PHPArray.init(allocator);

    const start_val = start.toInt();
    const end_val = end.toInt();

    if (start_val <= end_val) {
        var i = start_val;
        while (i <= end_val) : (i += 1) {
            try result.push(allocator, Value.initInt(i));
        }
    } else {
        var i = start_val;
        while (i >= end_val) : (i -= 1) {
            try result.push(allocator, Value.initInt(i));
        }
    }

    return Value.initArray(result);
}

fn arrayGetByString(arr: *PHPArray, key_bytes: []const u8) ?Value {
    var it = arr.elements.iterator();
    while (it.next()) |entry| {
        if (entry.key_ptr.* == .string) {
            const s = entry.key_ptr.*.string;
            if (std.mem.eql(u8, s.data, key_bytes)) return entry.value_ptr.*;
        }
    }
    return null;
}

fn arraySetByString(arr: *PHPArray, allocator: Allocator, key_bytes: []const u8, value: Value) !void {
    const s = try PHPString.init(allocator, key_bytes);
    defer s.release(allocator);
    try arr.set(allocator, .{ .string = s }, value);
}

fn valueCompare(a: Value, b: Value, allocator: Allocator) !i64 {
    if ((a.isInt() or a.isFloat() or a.isBool() or a.isNull()) and (b.isInt() or b.isFloat() or b.isBool() or b.isNull())) {
        const af = a.toFloat();
        const bf = b.toFloat();
        if (af < bf) return -1;
        if (af > bf) return 1;
        return 0;
    }

    const as = try a.toString(allocator);
    defer as.release(allocator);
    const bs = try b.toString(allocator);
    defer bs.release(allocator);

    return switch (std.mem.order(u8, as.data, bs.data)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

fn keyCompare(a: ArrayKey, b: ArrayKey) i64 {
    return switch (a) {
        .integer => |ai| switch (b) {
            .integer => |bi| if (ai < bi) -1 else if (ai > bi) 1 else 0,
            .string => -1,
        },
        .string => |as| switch (b) {
            .integer => 1,
            .string => |bs| switch (std.mem.order(u8, as.data, bs.data)) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            },
        },
    };
}

fn quickSortValues(values: []Value, allocator: Allocator, descending: bool) !void {
    if (values.len < 2) return;

    const pivot = values[values.len / 2];
    var i: usize = 0;
    var j: usize = values.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try valueCompare(values[i], pivot, allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= values.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try valueCompare(values[j], pivot, allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = values[i];
            values[i] = values[j];
            values[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortValues(values[0 .. j + 1], allocator, descending);
    if (i < values.len) try quickSortValues(values[i..], allocator, descending);
}

const KV = struct { key: ArrayKey, value: Value };

fn collectEntries(arr: *PHPArray, allocator: Allocator) ![]KV {
    const n = arr.count();
    const items = try allocator.alloc(KV, n);
    var it = arr.elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) {
        items[idx] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
    }
    return items;
}

fn quickSortEntriesByValue(items: []KV, allocator: Allocator, descending: bool) !void {
    if (items.len < 2) return;

    const pivot = items[items.len / 2].value;
    var i: usize = 0;
    var j: usize = items.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try valueCompare(items[i].value, pivot, allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= items.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try valueCompare(items[j].value, pivot, allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = items[i];
            items[i] = items[j];
            items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortEntriesByValue(items[0 .. j + 1], allocator, descending);
    if (i < items.len) try quickSortEntriesByValue(items[i..], allocator, descending);
}

fn quickSortEntriesByKey(items: []KV, descending: bool) void {
    if (items.len < 2) return;

    const pivot = items[items.len / 2].key;
    var i: usize = 0;
    var j: usize = items.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = keyCompare(items[i].key, pivot);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= items.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = keyCompare(items[j].key, pivot);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = items[i];
            items[i] = items[j];
            items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) quickSortEntriesByKey(items[0 .. j + 1], descending);
    if (i < items.len) quickSortEntriesByKey(items[i..], descending);
}

pub fn php_sizeof(val: Value) !Value {
    return php_count(val, Value.initInt(0));
}

pub fn php_array_combine(keys: Value, values: Value, allocator: Allocator) !Value {
    if (!keys.isArray() or !values.isArray()) return Value.initBool(false);
    const keys_arr = keys.asArray();
    const values_arr = values.asArray();
    if (keys_arr.count() != values_arr.count()) return Value.initBool(false);

    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var key_it = keys_arr.elements.iterator();
    var val_it = values_arr.elements.iterator();
    while (key_it.next()) |k_entry| {
        const v_entry = val_it.next().?;
        const k = k_entry.value_ptr.*;
        const v = v_entry.value_ptr.*;
        if (k.isInt()) {
            try result.set(allocator, .{ .integer = k.asInt() }, v);
        } else if (k.isString()) {
            try result.set(allocator, .{ .string = k.asString() }, v);
        } else {
            const ks = try k.toString(allocator);
            defer ks.release(allocator);
            try result.set(allocator, .{ .string = ks }, v);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_pad(arr: Value, pad_size: Value, pad_value: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();
    const php_arr = arr.asArray();
    const n = php_arr.count();
    const target_i = pad_size.toInt();
    const target: usize = @intCast(@abs(target_i));

    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    if (target > n and target_i < 0) {
        var i: usize = 0;
        while (i < target - n) : (i += 1) {
            try result.push(allocator, pad_value);
        }
    }

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        try result.push(allocator, entry.value_ptr.*);
    }

    if (target > n and target_i > 0) {
        var i: usize = 0;
        while (i < target - n) : (i += 1) {
            try result.push(allocator, pad_value);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_intersect(arrays: []const Value, allocator: Allocator) !Value {
    if (arrays.len == 0 or !arrays[0].isArray()) return Value.initArray(try PHPArray.init(allocator));

    const first = arrays[0].asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var it = first.elements.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr.*;
        var keep = true;
        for (arrays[1..]) |other_val| {
            if (!other_val.isArray()) {
                keep = false;
                break;
            }
            var found = false;
            var oit = other_val.asArray().elements.iterator();
            while (oit.next()) |oentry| {
                const eq = try php_eq(v, oentry.value_ptr.*);
                if (eq.asBool()) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                keep = false;
                break;
            }
        }
        if (keep) {
            try result.set(allocator, entry.key_ptr.*, v);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_diff(arrays: []const Value, allocator: Allocator) !Value {
    if (arrays.len == 0 or !arrays[0].isArray()) return Value.initArray(try PHPArray.init(allocator));

    const first = arrays[0].asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var it = first.elements.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr.*;
        var keep = true;
        for (arrays[1..]) |other_val| {
            if (!other_val.isArray()) continue;
            var oit = other_val.asArray().elements.iterator();
            while (oit.next()) |oentry| {
                const eq = try php_eq(v, oentry.value_ptr.*);
                if (eq.asBool()) {
                    keep = false;
                    break;
                }
            }
            if (!keep) break;
        }
        if (keep) {
            try result.set(allocator, entry.key_ptr.*, v);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_diff_key(arrays: []const Value, allocator: Allocator) !Value {
    if (arrays.len == 0 or !arrays[0].isArray()) return Value.initArray(try PHPArray.init(allocator));

    const first = arrays[0].asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    // 遍历第一个数组的所有键值对
    var it = first.elements.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const v = entry.value_ptr.*;
        var keep = true;
        
        // 检查这个键是否在其他数组中存在
        for (arrays[1..]) |other_val| {
            if (!other_val.isArray()) continue;
            const other_arr = other_val.asArray();
            
            // 如果其他数组中存在相同的键，则不保留
            if (other_arr.elements.get(key)) |_| {
                keep = false;
                break;
            }
        }
        
        if (keep) {
            try result.set(allocator, key, v);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_splice(arr: Value, offset: Value, length: Value, replacement: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();
    const php_arr = arr.asArray();
    const n = php_arr.count();

    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i < 0) {
            const abs_off = @as(usize, @intCast(@abs(off_i)));
            break :blk if (abs_off > n) 0 else n - abs_off;
        }
        break :blk @intCast(@min(off_i, @as(i64, @intCast(n))));
    };

    const delete_count: usize = blk: {
        if (length.isNull()) break :blk n - start_idx;
        const len_i = length.toInt();
        if (len_i >= 0) break :blk @min(@as(usize, @intCast(len_i)), n - start_idx);
        const abs_len = @as(usize, @intCast(@abs(len_i)));
        if (abs_len >= n - start_idx) break :blk 0;
        break :blk (n - start_idx) - abs_len;
    };

    const removed = try PHPArray.init(allocator);
    errdefer removed.release(allocator);

    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);

    var rep_values: ?[]Value = null;
    if (!replacement.isNull()) {
        if (replacement.isArray()) {
            const rep_arr = replacement.asArray();
            const rep_n = rep_arr.count();
            const vals = try allocator.alloc(Value, rep_n);
            var rep_it = rep_arr.elements.iterator();
            var ridx: usize = 0;
            while (rep_it.next()) |e| : (ridx += 1) vals[ridx] = e.value_ptr.*;
            rep_values = vals;
        } else {
            const vals = try allocator.alloc(Value, 1);
            vals[0] = replacement;
            rep_values = vals;
        }
    }
    defer if (rep_values) |vals| allocator.free(vals);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    var next_int_key: i64 = 0;

    var idx: usize = 0;
    while (idx < items.len) : (idx += 1) {
        if (idx == start_idx) {
            var r: usize = 0;
            while (r < delete_count) : (r += 1) {
                try removed.push(allocator, items[idx + r].value);
                items[idx + r].value.release(allocator);
                if (items[idx + r].key == .string) {
                    items[idx + r].key.string.release(allocator);
                }
            }

            if (rep_values) |vals| {
                for (vals) |v| {
                    _ = v.retain();
                    try new_elements.put(allocator, .{ .integer = next_int_key }, v);
                    next_int_key += 1;
                }
            }

            idx += delete_count;
            if (idx >= items.len) break;
        }

        const kv = items[idx];
        switch (kv.key) {
            .string => {
                try new_elements.put(allocator, kv.key, kv.value);
            },
            .integer => {
                try new_elements.put(allocator, .{ .integer = next_int_key }, kv.value);
                next_int_key += 1;
            },
        }
    }

    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    php_arr.next_index = next_int_key;

    return Value.initArray(removed);
}

pub fn php_sort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) {
        const got = valueTypeName(arr);
        emitTypeFatalError("sort", 1, "array", got);
    }
    const php_arr = arr.asArray();
    const n = php_arr.count();
    var values = try allocator.alloc(Value, n);
    defer allocator.free(values);

    var it = php_arr.elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) values[idx] = entry.value_ptr.*;
    try quickSortValues(values, allocator, false);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        try new_elements.put(allocator, .{ .integer = @intCast(i) }, values[i]);
    }

    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    php_arr.next_index = @intCast(values.len);
    return Value.initBool(true);
}

pub fn php_rsort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const n = php_arr.count();
    var values = try allocator.alloc(Value, n);
    defer allocator.free(values);

    var it = php_arr.elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) values[idx] = entry.value_ptr.*;
    try quickSortValues(values, allocator, true);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        try new_elements.put(allocator, .{ .integer = @intCast(i) }, values[i]);
    }

    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    php_arr.next_index = @intCast(values.len);
    return Value.initBool(true);
}

pub fn php_asort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);
    try quickSortEntriesByValue(items, allocator, false);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    for (items) |kv| {
        try new_elements.put(allocator, kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

pub fn php_arsort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);
    try quickSortEntriesByValue(items, allocator, true);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    for (items) |kv| {
        try new_elements.put(allocator, kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

pub fn php_ksort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);
    quickSortEntriesByKey(items, false);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    for (items) |kv| {
        try new_elements.put(allocator, kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

pub fn php_krsort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);
    quickSortEntriesByKey(items, true);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    for (items) |kv| {
        try new_elements.put(allocator, kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

fn invokeUserCompare(callback: Value, a: Value, b: Value, allocator: Allocator) !i64 {
    const args = [_]Value{ a, b };
    const res = try php_invoke_callable(callback, &args, allocator);
    const cmp = res.toInt();
    res.release(allocator);
    return cmp;
}

fn quickSortValuesWithCallback(values: []Value, callback: Value, allocator: Allocator, descending: bool) !void {
    // 使用冒泡排序，简单可靠
    if (values.len < 2) return;

    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        var j: usize = 0;
        while (j < values.len - 1 - i) : (j += 1) {
            const cmp = try invokeUserCompare(callback, values[j], values[j + 1], allocator);
            const should_swap = if (descending) cmp < 0 else cmp > 0;
            if (should_swap) {
                const tmp = values[j];
                values[j] = values[j + 1];
                values[j + 1] = tmp;
            }
        }
    }
}

fn quickSortEntriesByValueWithCallback(items: []KV, callback: Value, allocator: Allocator, descending: bool) !void {
    if (items.len < 2) return;

    const pivot = items[items.len / 2].value;
    var i: usize = 0;
    var j: usize = items.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try invokeUserCompare(callback, items[i].value, pivot, allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= items.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try invokeUserCompare(callback, items[j].value, pivot, allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = items[i];
            items[i] = items[j];
            items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortEntriesByValueWithCallback(items[0 .. j + 1], callback, allocator, descending);
    if (i < items.len) try quickSortEntriesByValueWithCallback(items[i..], callback, allocator, descending);
}

fn keyToValue(key: ArrayKey) Value {
    return switch (key) {
        .integer => |i| Value.initInt(i),
        .string => |s| Value.initString(s),
    };
}

fn quickSortEntriesByKeyWithCallback(items: []KV, callback: Value, allocator: Allocator, descending: bool) !void {
    if (items.len < 2) return;

    const pivot = items[items.len / 2].key;
    var i: usize = 0;
    var j: usize = items.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try invokeUserCompare(callback, keyToValue(items[i].key), keyToValue(pivot), allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= items.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try invokeUserCompare(callback, keyToValue(items[j].key), keyToValue(pivot), allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = items[i];
            items[i] = items[j];
            items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortEntriesByKeyWithCallback(items[0 .. j + 1], callback, allocator, descending);
    if (i < items.len) try quickSortEntriesByKeyWithCallback(items[i..], callback, allocator, descending);
}

pub fn php_usort(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const n = php_arr.count();
    var values = try allocator.alloc(Value, n);
    defer allocator.free(values);

    var it = php_arr.elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) values[idx] = entry.value_ptr.*;

    try quickSortValuesWithCallback(values, callback, allocator, false);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        try new_elements.put(allocator, .{ .integer = @intCast(i) }, values[i]);
    }

    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    php_arr.next_index = @intCast(values.len);
    return Value.initBool(true);
}

pub fn php_uasort(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);

    try quickSortEntriesByValueWithCallback(items, callback, allocator, false);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    for (items) |kv| {
        try new_elements.put(allocator, kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

pub fn php_uksort(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);

    try quickSortEntriesByKeyWithCallback(items, callback, allocator, false);

    var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
    for (items) |kv| {
        try new_elements.put(allocator, kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

fn quickSortIndicesByValues(indices: []usize, values: []Value, allocator: Allocator, descending: bool) !void {
    if (indices.len < 2) return;

    const pivot_idx = indices[indices.len / 2];
    const pivot = values[pivot_idx];
    var i: usize = 0;
    var j: usize = indices.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try valueCompare(values[indices[i]], pivot, allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= indices.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try valueCompare(values[indices[j]], pivot, allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = indices[i];
            indices[i] = indices[j];
            indices[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortIndicesByValues(indices[0 .. j + 1], values, allocator, descending);
    if (i < indices.len) try quickSortIndicesByValues(indices[i..], values, allocator, descending);
}

pub fn php_array_multisort(arrays: []const Value, allocator: Allocator) !Value {
    if (arrays.len == 0 or !arrays[0].isArray()) return Value.initBool(false);

    // 解析参数：找到第一个数组（排序键）和排序方向
    const first_arr = arrays[0].asArray();
    const n = first_arr.count();
    var descending = false;
    // 检查SORT_DESC(2)
    for (arrays[1..]) |arg| {
        if (arg.isInt() and arg.asInt() == 2) { descending = true; break; }
    }

    var first_vals = try allocator.alloc(Value, n);
    defer allocator.free(first_vals);
    var it0 = first_arr.elements.iterator();
    var idx0: usize = 0;
    while (it0.next()) |entry| : (idx0 += 1) first_vals[idx0] = entry.value_ptr.*;

    var indices = try allocator.alloc(usize, n);
    defer allocator.free(indices);
    for (0..n) |i| indices[i] = i;

    try quickSortIndicesByValues(indices, first_vals, allocator, descending);

    // 对所有数组参数（跳过非数组的排序标志）重排
    for (arrays) |arr_val| {
        if (!arr_val.isArray()) continue; // 跳过SORT_ASC/SORT_DESC等
        const a = arr_val.asArray();
        if (a.count() != n) return Value.initBool(false);

        var vals = try allocator.alloc(Value, n);
        defer allocator.free(vals);
        var it = a.elements.iterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) vals[i] = entry.value_ptr.*;

        var new_elements = std.ArrayHashMapUnmanaged(ArrayKey, Value, PHPArray.ArrayContext, true){};
        for (indices, 0..) |src, dst| {
            try new_elements.put(allocator, .{ .integer = @intCast(dst) }, vals[src]);
        }
        a.elements.deinit();
        a.elements = PHPArray.Elements.initMixed(allocator, new_elements);
        a.next_index = @intCast(n);
    }

    return Value.initBool(true);
}

fn arrayCursorGet(arr: *PHPArray) usize {
    if (array_internal_pointers) |m| {
        return m.get(arr) orelse 0;
    }
    return 0;
}

fn arrayCursorSet(arr: *PHPArray, idx: usize, allocator: Allocator) !void {
    if (array_internal_pointers) |*m| {
        try m.put(arr, idx);
    } else {
        _ = allocator;
    }
}

fn arrayEntryAt(arr: *PHPArray, idx: usize) ?KV {
    var it = arr.elements.iterator();
    var i: usize = 0;
    while (it.next()) |entry| : (i += 1) {
        if (i == idx) return .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
    }
    return null;
}

pub fn php_current(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const idx = arrayCursorGet(a);
    if (arrayEntryAt(a, idx)) |kv| {
        _ = kv.value.retain();
        _ = allocator;
        return kv.value;
    }
    _ = allocator;
    return Value.initBool(false);
}

pub fn php_key(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();
    const a = arr.asArray();
    const idx = arrayCursorGet(a);
    if (arrayEntryAt(a, idx)) |kv| {
        _ = allocator;
        return switch (kv.key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                s.retain();
                break :blk Value.initString(s);
            },
        };
    }
    _ = allocator;
    return Value.initNull();
}

pub fn php_reset(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    try arrayCursorSet(a, 0, allocator);
    return php_current(arr, allocator);
}

pub fn php_end(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const n = a.count();
    if (n == 0) {
        try arrayCursorSet(a, 0, allocator);
        return Value.initBool(false);
    }
    try arrayCursorSet(a, n - 1, allocator);
    return php_current(arr, allocator);
}

pub fn php_next(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const idx = arrayCursorGet(a) + 1;
    try arrayCursorSet(a, idx, allocator);
    return php_current(arr, allocator);
}

pub fn php_prev(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const cur = arrayCursorGet(a);
    if (cur == 0) return Value.initBool(false);
    try arrayCursorSet(a, cur - 1, allocator);
    return php_current(arr, allocator);
}

pub fn php_each(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const idx = arrayCursorGet(a);
    const kv = arrayEntryAt(a, idx) orelse return Value.initBool(false);

    const key_val = switch (kv.key) {
        .integer => |i| Value.initInt(i),
        .string => |s| Value.initString(s),
    };

    const out = try PHPArray.init(allocator);
    errdefer out.release(allocator);

    try out.set(allocator, .{ .integer = 0 }, kv.value);
    try out.set(allocator, .{ .integer = 1 }, key_val);
    try arraySetByString(out, allocator, "key", key_val);
    try arraySetByString(out, allocator, "value", kv.value);

    try arrayCursorSet(a, idx + 1, allocator);

    return Value.initArray(out);
}

// ============================================================================
// 扩展字符串函数
// ============================================================================

/// ord - 返回字符的ASCII值
pub fn php_ord(str: Value) !Value {
    if (!str.isString()) return Value.initInt(0);

    const php_str = str.asString();
    if (php_str.length == 0) return Value.initInt(0);

    return Value.initInt(@intCast(php_str.data[0]));
}

/// chr - 返回指定ASCII值对应的字符
pub fn php_chr(code: Value, allocator: Allocator) !Value {
    const ascii = @as(u8, @truncate(@as(u64, @intCast(code.toInt() & 0xFF))));
    const buffer = [_]u8{ascii};
    const result = try PHPString.init(allocator, &buffer);
    return Value.initString(result);
}

pub fn php_count_chars(str: Value, mode: Value, allocator: Allocator) !Value {
    const mode_int = mode.toInt();
    if (!str.isString()) {
        return switch (mode_int) {
            3, 4 => Value.initString(try PHPString.init(allocator, "")),
            else => Value.initArray(try PHPArray.init(allocator)),
        };
    }

    const bytes = str.asString().data;
    var counts = [_]usize{0}**256;
    for (bytes) |b| {
        counts[b] += 1;
    }

    switch (mode_int) {
        0, 1, 2 => {
            const result = try PHPArray.init(allocator);
            errdefer result.release(allocator);
            var i: usize = 0;
            while (i < 256) : (i += 1) {
                const count = counts[i];
                if (mode_int == 1 and count == 0) continue;
                if (mode_int == 2 and count != 0) continue;
                try result.set(allocator, .{ .integer = @intCast(i) }, Value.initInt(@intCast(count)));
            }
            return Value.initArray(result);
        },
        3, 4 => {
            var buf = try std.ArrayList(u8).initCapacity(allocator, 32);
            defer buf.deinit(allocator);
            var i: usize = 0;
            while (i < 256) : (i += 1) {
                const count = counts[i];
                if (mode_int == 3 and count == 0) continue;
                if (mode_int == 4 and count != 0) continue;
                try buf.append(allocator, @as(u8, @intCast(i)));
            }
            return Value.initString(try PHPString.init(allocator, buf.items));
        },
        else => {
            const result = try PHPArray.init(allocator);
            errdefer result.release(allocator);
            var i: usize = 0;
            while (i < 256) : (i += 1) {
                try result.set(allocator, .{ .integer = @intCast(i) }, Value.initInt(@intCast(counts[i])));
            }
            return Value.initArray(result);
        },
    }
}

/// urlencode - PHP URL 编码（空格→+，其他特殊字符→%XX）
pub fn php_urlencode(input: Value, allocator: Allocator) !Value {
    if (!input.isString()) {
        const s = try input.toString(allocator);
        defer s.deinit(allocator);
        return php_urlencode(Value.initString(s), allocator);
    }
    const data = input.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, data.len);
    defer result.deinit();
    const hex = "0123456789ABCDEF";
    for (data) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.') {
            try result.append(c);
        } else if (c == ' ') {
            try result.append('+');
        } else {
            try result.append('%');
            try result.append(hex[c >> 4]);
            try result.append(hex[c & 0x0F]);
        }
    }
    const str = try PHPString.init(allocator, result.items);
    return Value.initString(str);
}

/// urldecode - PHP URL 解码（+→空格，%XX→字符）
pub fn php_urldecode(input: Value, allocator: Allocator) !Value {
    if (!input.isString()) return Value.initString(try PHPString.init(allocator, ""));
    const data = input.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, data.len);
    defer result.deinit();
    var i: usize = 0;
    while (i < data.len) {
        if (data[i] == '+') {
            try result.append(' ');
            i += 1;
        } else if (data[i] == '%' and i + 2 < data.len) {
            const hi = std.fmt.charToDigit(data[i + 1], 16) catch {
                try result.append('%');
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(data[i + 2], 16) catch {
                try result.append('%');
                i += 1;
                continue;
            };
            try result.append((hi << 4) | lo);
            i += 3;
        } else {
            try result.append(data[i]);
            i += 1;
        }
    }
    const str = try PHPString.init(allocator, result.items);
    return Value.initString(str);
}

/// rawurlencode - RFC 3986 编码（空格→%20）
pub fn php_rawurlencode(input: Value, allocator: Allocator) !Value {
    if (!input.isString()) {
        const s = try input.toString(allocator);
        defer s.deinit(allocator);
        return php_rawurlencode(Value.initString(s), allocator);
    }
    const data = input.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, data.len);
    defer result.deinit();
    const hex = "0123456789ABCDEF";
    for (data) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(c);
        } else {
            try result.append('%');
            try result.append(hex[c >> 4]);
            try result.append(hex[c & 0x0F]);
        }
    }
    const str = try PHPString.init(allocator, result.items);
    return Value.initString(str);
}

/// rawurldecode - RFC 3986 解码（%XX→字符，+不转换）
pub fn php_rawurldecode(input: Value, allocator: Allocator) !Value {
    if (!input.isString()) return Value.initString(try PHPString.init(allocator, ""));
    const data = input.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, data.len);
    defer result.deinit();
    var i: usize = 0;
    while (i < data.len) {
        if (data[i] == '%' and i + 2 < data.len) {
            const hi = std.fmt.charToDigit(data[i + 1], 16) catch {
                try result.append('%');
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(data[i + 2], 16) catch {
                try result.append('%');
                i += 1;
                continue;
            };
            try result.append((hi << 4) | lo);
            i += 3;
        } else {
            try result.append(data[i]);
            i += 1;
        }
    }
    const str = try PHPString.init(allocator, result.items);
    return Value.initString(str);
}

// ============================================================================
// 网络相关函数
// ============================================================================

/// gethostbyname - 通过主机名获取IP地址
pub fn php_getenv(name_val: Value, allocator: Allocator) !Value {
    if (!name_val.isString()) return Value.initBool(false);

    const name = name_val.asString().data;
    // Zig 0.17: std.process.getEnvVarOwned 已移除，使用 std.c.getenv
    const name_z = allocator.dupeSentinel(u8, name, 0) catch return Value.initBool(false);
    defer allocator.free(name_z);
    const env_val = getEnvVar(name_z.ptr) orelse return Value.initBool(false);

    return Value.initString(try PHPString.init(allocator, env_val));
}

pub fn php_gethostbyname(hostname: Value, allocator: Allocator) !Value {
    if (!hostname.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const name = hostname.asString().data;

    // 使用 C 库 getaddrinfo 进行 DNS 解析
    const c_name = try allocator.dupeSentinel(u8, name, 0);
    defer allocator.free(c_name);

    var hints: std.posix.addrinfo = std.mem.zeroes(std.posix.addrinfo);
    hints.family = std.posix.AF.INET;
    hints.socktype = std.posix.SOCK.STREAM;

    var result_ptr: ?*std.posix.addrinfo = null;
    const rc = std.c.getaddrinfo(c_name.ptr, null, &hints, &result_ptr);
    if (@intFromEnum(rc) != 0 or result_ptr == null) {
        return hostname;
    }
    defer std.c.freeaddrinfo(result_ptr.?);

    const addr_in: *const std.posix.sockaddr.in = @ptrCast(@alignCast(result_ptr.?.addr.?));
    const ip_bytes = @as(*const [4]u8, @ptrCast(&addr_in.addr));
    const ip_str = try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ ip_bytes[0], ip_bytes[1], ip_bytes[2], ip_bytes[3] });
    defer allocator.free(ip_str);

    const result = try PHPString.init(allocator, ip_str);
    return Value.initString(result);
}

/// gethostname - 获取主机名
pub fn php_gethostname(allocator: Allocator) !Value {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&buf) catch {
        return Value.initString(try PHPString.init(allocator, "localhost"));
    };
    const result = try PHPString.init(allocator, hostname);
    return Value.initString(result);
}

/// ip2long - 将IP地址转换为长整型
pub fn php_ip2long(ip: Value) !Value {
    if (!ip.isString()) return Value.initBool(false);
    const ip_str = ip.asString().data;

    // 解析IPv4地址
    var parts = std.mem.splitScalar(u8, ip_str, '.');
    var result: u32 = 0;
    var shift: u5 = 24;

    while (parts.next()) |part| {
        const num = std.fmt.parseInt(u8, part, 10) catch return Value.initBool(false);
        result |= @as(u32, num) << shift;
        if (shift > 0) shift -= 8 else break;
    }

    return Value.initInt(@as(i64, result));
}

/// long2ip - 将长整型转换为IP地址
pub fn php_long2ip(long: Value, allocator: Allocator) !Value {
    const ip_num: u32 = @intCast(@max(long.toInt(), 0));

    const a: u8 = @intCast((ip_num >> 24) & 0xFF);
    const b: u8 = @intCast((ip_num >> 16) & 0xFF);
    const c: u8 = @intCast((ip_num >> 8) & 0xFF);
    const d: u8 = @intCast(ip_num & 0xFF);

    const ip_str = try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ a, b, c, d });
    const result = try PHPString.init(allocator, ip_str);
    return Value.initString(result);
}

/// parse_url - 解析URL
pub fn php_parse_url(url: Value, allocator: Allocator) !Value {
    if (!url.isString()) return Value.initBool(false);

    const url_str = url.asString().data;
    const arr = try PHPArray.init(allocator);

    // 简单的URL解析
    var rest = url_str;

    // 解析scheme
    if (std.mem.indexOf(u8, rest, "://")) |scheme_end| {
        const scheme = rest[0..scheme_end];
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "scheme") }, Value.initString(try PHPString.init(allocator, scheme)));
        rest = rest[scheme_end + 3..];
    }

    // 解析host和port
    if (std.mem.indexOf(u8, rest, "/")) |host_end| {
        const host_port = rest[0..host_end];
        rest = rest[host_end..];

        if (std.mem.indexOf(u8, host_port, ":")) |port_pos| {
            const host = host_port[0..port_pos];
            const port = host_port[port_pos + 1..];
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "host") }, Value.initString(try PHPString.init(allocator, host)));
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "port") }, Value.initInt(std.fmt.parseInt(i64, port, 10) catch 0));
        } else {
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "host") }, Value.initString(try PHPString.init(allocator, host_port)));
        }
    }

    // 解析path
    if (std.mem.indexOf(u8, rest, "?")) |path_end| {
        const path = rest[0..path_end];
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "path") }, Value.initString(try PHPString.init(allocator, path)));
        rest = rest[path_end + 1..];

        // 解析query
        if (std.mem.indexOf(u8, rest, "#")) |query_end| {
            const query = rest[0..query_end];
            const fragment = rest[query_end + 1..];
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "query") }, Value.initString(try PHPString.init(allocator, query)));
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "fragment") }, Value.initString(try PHPString.init(allocator, fragment)));
        } else {
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "query") }, Value.initString(try PHPString.init(allocator, rest)));
        }
    } else {
        if (rest.len > 0) {
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "path") }, Value.initString(try PHPString.init(allocator, rest)));
        }
    }

    return Value.initArray(arr);
}

/// http_build_query - 生成 URL 编码的查询字符串
pub fn php_http_build_query(data: Value, allocator: Allocator) !Value {
    if (!data.isArray()) return Value.initString(try PHPString.init(allocator, ""));

    const arr = data.asArray();
    var aw = std.Io.Writer.Allocating.initCapacity(allocator, 64) catch return Value.initNull();
    defer aw.deinit();

    var first = true;
    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        if (!first) try aw.writer.writeAll("&");
        first = false;

        // 写入键
        switch (entry.key_ptr.*) {
            .integer => |i| try aw.writer.print("{d}", .{i}),
            .string => |s| try aw.writer.writeAll(s.data),
        }
        try aw.writer.writeAll("=");

        // 写入值
        const val = entry.value_ptr.*;
        if (val.isString()) {
            // URL 编码
            for (val.asString().data) |c| {
                if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
                    try aw.writer.writeByte(c);
                } else if (c == ' ') {
                    try aw.writer.writeByte('+');
                } else {
                    try aw.writer.print("%{X:0>2}", .{c});
                }
            }
        } else if (val.isInt()) {
            try aw.writer.print("{d}", .{val.asInt()});
        } else if (val.isFloat()) {
            try aw.writer.print("{d}", .{val.asFloat()});
        } else if (val.isBool()) {
            if (val.asBool()) try aw.writer.writeAll("1");
        }
    }

    return Value.initString(try PHPString.init(allocator, aw.written()));
}

/// parse_str - 将查询字符串解析到变量中
pub fn php_parse_str(str: Value, result_arr: Value, allocator: Allocator) !Value {
    if (!str.isString()) return Value.initNull();

    const query = str.asString().data;
    const arr = if (result_arr.isArray()) result_arr.asArray() else try PHPArray.init(allocator);

    var pairs = std.mem.splitScalar(u8, query, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;
        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            const key = pair[0..eq_pos];
            const val = pair[eq_pos + 1 ..];
            const key_str = try PHPString.init(allocator, key);
            const val_str = try PHPString.init(allocator, val);
            try arr.set(allocator, .{ .string = key_str }, Value.initString(val_str));
        } else {
            const key_str = try PHPString.init(allocator, pair);
            const empty_str = try PHPString.init(allocator, "");
            try arr.set(allocator, .{ .string = key_str }, Value.initString(empty_str));
        }
    }

    if (!result_arr.isArray()) {
        return Value.initArray(arr);
    }
    return Value.initNull();
}

/// glob - 查找匹配模式的文件路径
pub fn php_glob(pattern: Value, allocator: Allocator) !Value {
    if (!pattern.isString()) return Value.initArray(try PHPArray.init(allocator));

    const pat = pattern.asString().data;
    const arr = try PHPArray.init(allocator);

    // 简单实现：使用目录遍历 + 模式匹配
    // 提取目录部分和文件名模式
    const dir_path = std.fs.path.dirname(pat) orelse ".";
    const file_pattern = std.fs.path.basename(pat);

    var dir = std.Io.Dir.cwd().openDir(getIo(), dir_path, .{ .iterate = true }) catch {
        return Value.initArray(arr);
    };
    defer dir.close(getIo());

    var dir_iter = dir.iterate();
    while (dir_iter.next() catch null) |entry| {
        if (globMatch(file_pattern, entry.name)) {
            const full_path = if (std.mem.eql(u8, dir_path, "."))
                try PHPString.init(allocator, entry.name)
            else blk: {
                const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer allocator.free(path);
                break :blk try PHPString.init(allocator, path);
            };
            try arr.push(allocator, Value.initString(full_path));
        }
    }

    return Value.initArray(arr);
}

/// 简单的 glob 模式匹配（支持 * 和 ?）
fn globMatch(pattern: []const u8, name: []const u8) bool {
    var pi: usize = 0;
    var ni: usize = 0;
    var star_pi: ?usize = null;
    var star_ni: usize = 0;

    while (ni < name.len) {
        if (pi < pattern.len and (pattern[pi] == name[ni] or pattern[pi] == '?')) {
            pi += 1;
            ni += 1;
        } else if (pi < pattern.len and pattern[pi] == '*') {
            star_pi = pi;
            star_ni = ni;
            pi += 1;
        } else if (star_pi) |sp| {
            pi = sp + 1;
            star_ni += 1;
            ni = star_ni;
        } else {
            return false;
        }
    }

    while (pi < pattern.len and pattern[pi] == '*') pi += 1;
    return pi == pattern.len;
}

/// stripos - 不区分大小写查找子字符串位置
pub fn php_stripos(haystack: Value, needle: Value, offset: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i >= 0) {
            break :blk @intCast(@min(off_i, @as(i64, @intCast(hay.length))));
        }
        const abs_off: usize = @intCast(@min(-off_i, @as(i64, @intCast(hay.length))));
        break :blk hay.length - abs_off;
    };

    if (start_idx > hay.length or start_idx + need.length > hay.length) return Value.initBool(false);

    var i: usize = start_idx;
    while (i <= hay.length - need.length) : (i += 1) {
        var match = true;
        var j: usize = 0;
        while (j < need.length) : (j += 1) {
            if (std.ascii.toLower(hay.data[i + j]) != std.ascii.toLower(need.data[j])) {
                match = false;
                break;
            }
        }
        if (match) return Value.initInt(@intCast(i));
    }

    return Value.initBool(false);
}

/// strrpos - 查找子字符串最后出现的位置
pub fn php_strrpos(haystack: Value, needle: Value, offset: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    var last_pos: ?usize = null;
    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i >= 0) {
            break :blk @intCast(@min(off_i, @as(i64, @intCast(hay.length))));
        }
        const abs_off: usize = @intCast(@min(-off_i, @as(i64, @intCast(hay.length))));
        break :blk hay.length - abs_off;
    };

    if (start_idx > hay.length or start_idx + need.length > hay.length) return Value.initBool(false);

    var i: usize = start_idx;
    while (i <= hay.length - need.length) : (i += 1) {
        if (std.mem.eql(u8, hay.data[i .. i + need.length], need.data)) {
            last_pos = i;
        }
    }

    if (last_pos) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

pub fn php_strripos(haystack: Value, needle: Value, offset: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    var last_pos: ?usize = null;
    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i >= 0) {
            break :blk @intCast(@min(off_i, @as(i64, @intCast(hay.length))));
        }
        const abs_off: usize = @intCast(@min(-off_i, @as(i64, @intCast(hay.length))));
        break :blk hay.length - abs_off;
    };

    if (start_idx > hay.length or start_idx + need.length > hay.length) return Value.initBool(false);

    var i: usize = start_idx;
    while (i <= hay.length - need.length) : (i += 1) {
        var match = true;
        var j: usize = 0;
        while (j < need.length) : (j += 1) {
            if (std.ascii.toLower(hay.data[i + j]) != std.ascii.toLower(need.data[j])) {
                match = false;
                break;
            }
        }
        if (match) {
            last_pos = i;
        }
    }

    if (last_pos) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

/// number_format - 格式化数字
pub fn php_number_format(number: Value, decimals: Value, dec_point: Value, thousands_sep: Value, allocator: Allocator) !Value {
    const num = number.toFloat();
    const dec: usize = @intCast(@max(0, decimals.toInt()));
    const dp: u8 = if (dec_point.isString() and dec_point.asString().data.len > 0)
        dec_point.asString().data[0] else '.';
    const ts: u8 = if (thousands_sep.isString() and thousands_sep.asString().data.len > 0)
        thousands_sep.asString().data[0]
        else if (thousands_sep.isNull()) ','
        else ',';

    var pow10: u64 = 1;
    for (0..dec) |_| pow10 *= 10;

    const scaled = num * @as(f64, @floatFromInt(pow10));
    const rounded: i64 = @intFromFloat(std.math.round(scaled));
    const negative = rounded < 0;
    const abs_r: u64 = @intCast(if (negative) -rounded else rounded);
    const int_part: u64 = abs_r / pow10;
    const frac_part: u64 = abs_r % pow10;

    // 整数部分转字符串（带千分位）
    const int_str = try std.fmt.allocPrint(allocator, "{d}", .{int_part});
    defer allocator.free(int_str);
    const n_groups = (int_str.len + 2) / 3; // ceil
    const sep_count = if (int_str.len > 3) (int_str.len - 1) / 3 else 0;

    // 估算总长度
    var total: usize = (if (negative) @as(usize, 1) else 0) + int_str.len + sep_count;
    if (dec > 0) total += 1 + dec;
    _ = n_groups;

    var aw3 = std.Io.Writer.Allocating.initCapacity(allocator, total + 4) catch return Value.initNull();
    defer aw3.deinit();

    if (negative) try aw3.writer.writeByte('-');
    // 写整数部分（带千分位）
    for (int_str, 0..) |ch, idx| {
        const remaining = int_str.len - idx;
        if (idx > 0 and remaining % 3 == 0) try aw3.writer.writeByte(ts);
        try aw3.writer.writeByte(ch);
    }
    // 写小数部分
    if (dec > 0) {
        try aw3.writer.writeByte(dp);
        var tmp = frac_part;
        var digits = try allocator.alloc(u8, dec);
        defer allocator.free(digits);
        var j: usize = dec;
        while (j > 0) {
            j -= 1;
            digits[j] = '0' + @as(u8, @intCast(tmp % 10));
            tmp /= 10;
        }
        try aw3.writer.writeAll(digits);
    }

    return Value.initString(try PHPString.init(allocator, aw3.written()));
}

/// nl2br - 将换行符转换为HTML <br>标签
pub fn php_nl2br(str: Value, is_xhtml: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const tag = if (is_xhtml.toBool()) "<br />" else "<br>";

    // 计算需要的空间
    var count: usize = 0;
    for (php_str.data) |c| {
        if (c == '\n') count += 1;
    }

    const new_len = php_str.length + count * tag.len;
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    for (php_str.data) |c| {
        if (c == '\n') {
            @memcpy(buffer[write_pos .. write_pos + tag.len], tag);
            write_pos += tag.len;
        }
        buffer[write_pos] = c;
        write_pos += 1;
    }

    const result = try PHPString.init(allocator, buffer[0..write_pos]);
    allocator.free(buffer);
    return Value.initString(result);
}

pub fn php_chunk_split(body: Value, chunklen: Value, end: Value, allocator: Allocator) !Value {
    const body_str = if (body.isString()) body.asString().data else "";
    const clen: usize = @intCast(@max(1, chunklen.toInt()));
    const end_str = if (end.isString()) end.asString().data else "\r\n";

    const num_chunks = (body_str.len + clen - 1) / clen;
    const result_len = body_str.len + num_chunks * end_str.len;
    const result = try allocator.alloc(u8, result_len);
    defer allocator.free(result);

    var src_i: usize = 0;
    var dst_i: usize = 0;
    while (src_i < body_str.len) {
        const chunk_end = @min(src_i + clen, body_str.len);
        @memcpy(result[dst_i .. dst_i + (chunk_end - src_i)], body_str[src_i..chunk_end]);
        dst_i += chunk_end - src_i;
        @memcpy(result[dst_i .. dst_i + end_str.len], end_str);
        dst_i += end_str.len;
        src_i = chunk_end;
    }

    const php_str = try PHPString.init(allocator, result[0..dst_i]);
    return Value.initString(php_str);
}

/// strip_tags - 移除HTML和PHP标签
pub fn php_strip_tags(str: Value, allowed_tags: Value, allocator: Allocator) !Value {
    _ = allowed_tags;
    if (!str.isString()) return str;

    const php_str = str.asString();
    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    var in_tag = false;

    for (php_str.data) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            buffer[write_pos] = c;
            write_pos += 1;
        }
    }

    const result = try PHPString.init(allocator, buffer[0..write_pos]);
    allocator.free(buffer);
    return Value.initString(result);
}

/// strval - 获取变量的字符串值
pub fn php_strval(val: Value, allocator: Allocator) !Value {
    const str = try val.toString(allocator);
    return Value.initString(str);
}

/// gettype - 获取变量的类型
pub fn php_gettype(val: Value, allocator: Allocator) !Value {
    const type_str = if (val.isNull())
        "NULL"
    else if (val.isBool())
        "boolean"
    else if (val.isInt())
        "integer"
    else if (val.isFloat())
        "double"
    else if (val.isString())
        "string"
    else if (val.isArray())
        "array"
    else if (Value_isObject(val))
        "object"
    else
        "unknown type";

    const result = try PHPString.init(allocator, type_str);
    return Value.initString(result);
}

/// settype - 改变变量的类型
/// PHP签名: settype(mixed &$var, string $type): bool
/// 第一个参数是引用，直接修改变量的值
pub fn php_settype(var_ref: Value, type_val: Value, allocator: Allocator) !Value {
    if (!type_val.isString()) {
        return Value.initBool(false);
    }
    
    // 检查第一个参数是否是引用
    if (!var_ref.isRef()) {
        return Value.initBool(false);
    }
    
    const ptr = var_ref.asRef();
    const type_name = type_val.asString().data;
    
    // 保存原始值用于转换
    const old_val = ptr.*;
    
    // 根据类型名进行转换
    const new_val = if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean"))
        Value.initBool(old_val.toBool())
    else if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"))
        Value.initInt(old_val.toInt())
    else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double"))
        Value.initFloat(old_val.toFloat())
    else if (std.mem.eql(u8, type_name, "string"))
        blk: {
            const str = try old_val.toString(allocator);
            break :blk Value.initString(str);
        }
    else if (std.mem.eql(u8, type_name, "array"))
        try php_cast_array(old_val)
    else if (std.mem.eql(u8, type_name, "object"))
        try php_cast_object(old_val)
    else if (std.mem.eql(u8, type_name, "null"))
        Value.initNull()
    else
        // 未知类型，返回 false 但不修改变量
        return Value.initBool(false);
    
    // 释放旧值，设置新值
    ptr.release(allocator);
    _ = new_val.retain();
    ptr.* = new_val;
    
    // 返回 true 表示成功
    return Value.initBool(true);
}

// ============================================================================
// 文件函数
// ============================================================================

/// file_get_contents - 读取文件内容
/// file_exists - 检查文件是否存在
pub fn php_file_exists(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    std.Io.Dir.cwd().access(path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// is_file - 检查是否是普通文件
/// mkdir - 创建目录
pub fn php_mkdir(dirname: Value, permissions: Value, recursive: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    const mode = if (permissions.isInt()) @as(u32, @intCast(permissions.asInt() & 0o777)) else 0o777;
    const is_recursive = if (recursive.isBool()) recursive.asBool() else false;
    
    _ = mode; // 权限在不同平台上处理不同，暂时忽略
    
    if (is_recursive) {
        // 递归创建目录（逐级创建）
        var start: usize = 0;
        while (start < path.len) {
            if (path[start] == '/') {
                start += 1;
                continue;
            }
            const end = if (std.mem.indexOfScalarPos(u8, path, start, '/')) |i| i else path.len;
            const component = path[0..end];
            const z_path = std.mem.sliceAsBytes(component) ++ &[_]u8{0};
            _ = std.posix.system.mkdir(z_path.ptr, 0o755);
            start = end + 1;
        }
    } else {
        // 非递归创建
        const z_path = std.mem.sliceAsBytes(path) ++ &[_]u8{0};
        const rc = std.posix.system.mkdir(z_path.ptr, 0o755);
        if (@as(i32, @intCast(rc)) < 0) {
            return Value.initBool(false);
        }
    }

    return Value.initBool(true);
}

/// rmdir - 删除目录
pub fn php_rmdir(dirname: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    std.Io.Dir.cwd().deleteDir(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// rename - 重命名文件
pub fn php_rename(oldname: Value, newname: Value) !Value {
    if (!oldname.isString() or !newname.isString()) return Value.initBool(false);

    const old_path = oldname.asString().data;
    const new_path = newname.asString().data;

    std.Io.Dir.cwd().rename(old_path, new_path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// copy - 拷贝文件
pub fn php_copy(source: Value, dest: Value) !Value {
    if (!source.isString() or !dest.isString()) return Value.initBool(false);

    const source_path = source.asString().data;
    const dest_path = dest.asString().data;

    std.Io.Dir.cwd().copyFile(source_path, std.fs.cwd, dest_path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// basename - 返回路径中的文件名部分
pub fn php_basename(path: Value, allocator: Allocator) !Value {
    if (!path.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const path_str = path.asString().data;
    const base = std.fs.path.basename(path_str);
    const result = try PHPString.init(allocator, base);
    return Value.initString(result);
}

/// dirname - 返回路径中的目录部分
pub fn php_dirname(path: Value, allocator: Allocator) !Value {
    if (!path.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const path_str = path.asString().data;
    const dir = std.fs.path.dirname(path_str) orelse ".";
    const result = try PHPString.init(allocator, dir);
    return Value.initString(result);
}

/// getmypid - 获取当前进程ID
pub fn php_getmypid() Value {
    const pid = std.posix.system.getpid();
    return Value.initInt(@intCast(pid));
}

/// getmygid - 获取当前进程组ID
const c_getgid = @extern(*const fn () callconv(.c) u32, .{ .name = "getgid" });
pub fn php_getmygid() Value {
    return Value.initInt(@intCast(c_getgid()));
}

/// phpversion - 返回PHP版本号
pub fn php_phpversion(allocator: Allocator) !Value {
    return Value.initString(try PHPString.init(allocator, "8.4.8"));
}

/// extension_loaded - 检查扩展是否加载
pub fn php_extension_loaded(name: Value) Value {
    if (!name.isString()) return Value.initBool(false);
    const ext = name.asString().data;
    // AOT 模式下模拟核心扩展已加载
    const core_exts = [_][]const u8{
        "Core", "core", "standard", "date", "pcre", "json",
        "ctype", "mbstring", "tokenizer", "SPL", "spl",
    };
    for (core_exts) |e| {
        if (std.mem.eql(u8, ext, e)) return Value.initBool(true);
    }
    return Value.initBool(false);
}

/// get_loaded_extensions - 返回已加载的扩展列表
pub fn php_get_loaded_extensions(allocator: Allocator) !Value {
    const arr = try PHPArray.init(allocator);
    const exts = [_][]const u8{ "Core", "standard", "date", "pcre", "json", "ctype", "mbstring", "SPL" };
    for (exts) |e| {
        try arr.pushValue(Value.initString(try PHPString.init(allocator, e)));
    }
    return Value.initArray(arr);
}

/// touch - 设置文件的访问和修改时间
pub fn php_touch(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const path = filename.asString().data;

    // 如果文件不存在，创建空文件
    const file = std.Io.Dir.cwd().createFile(getIo(), path, .{ .exclusive = false, .truncate = false }) catch {
        return Value.initBool(false);
    };
    file.close(getIo());
    return Value.initBool(true);
}

/// pathinfo - 返回文件路径的信息
pub fn php_pathinfo(path_val: Value, option: Value, allocator: Allocator) !Value {
    if (!path_val.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const path = path_val.asString().data;
    const opt = option.toInt();

    // PATHINFO_DIRNAME = 1, PATHINFO_BASENAME = 2, PATHINFO_EXTENSION = 4, PATHINFO_FILENAME = 8
    const dir = std.fs.path.dirname(path) orelse ".";
    const base = std.fs.path.basename(path);
    const ext_with_dot = std.fs.path.extension(path);
    const ext = if (ext_with_dot.len > 0) ext_with_dot[1..] else "";
    const filename = if (ext_with_dot.len > 0) base[0 .. base.len - ext_with_dot.len] else base;

    if (opt == 1) return Value.initString(try PHPString.init(allocator, dir));
    if (opt == 2) return Value.initString(try PHPString.init(allocator, base));
    if (opt == 4) return Value.initString(try PHPString.init(allocator, ext));
    if (opt == 8) return Value.initString(try PHPString.init(allocator, filename));

    // 默认返回关联数组
    const arr = try PHPArray.init(allocator);
    try arr.set(allocator, .{ .string = try PHPString.init(allocator, "dirname") }, Value.initString(try PHPString.init(allocator, dir)));
    try arr.set(allocator, .{ .string = try PHPString.init(allocator, "basename") }, Value.initString(try PHPString.init(allocator, base)));
    try arr.set(allocator, .{ .string = try PHPString.init(allocator, "extension") }, Value.initString(try PHPString.init(allocator, ext)));
    try arr.set(allocator, .{ .string = try PHPString.init(allocator, "filename") }, Value.initString(try PHPString.init(allocator, filename)));
    return Value.initArray(arr);
}

/// realpath - 返回规范化的绝对路径名
pub fn php_realpath(path_val: Value, allocator: Allocator) !Value {
    if (!path_val.isString()) return Value.initBool(false);
    const path = path_val.asString().data;

    const c_path = try allocator.dupeSentinel(u8, path, 0);
    defer allocator.free(c_path);

    var buf: [std.posix.PATH_MAX]u8 = undefined;
    const resolved = std.c.realpath(c_path.ptr, &buf);
    if (resolved == null) return Value.initBool(false);

    const result_str = std.mem.span(resolved.?);
    return Value.initString(try PHPString.init(allocator, result_str));
}

/// tempnam - 创建唯一的临时文件名
pub fn php_tempnam(dir: Value, prefix: Value, allocator: Allocator) !Value {
    const dir_str = if (dir.isString()) dir.asString().data else "/tmp";
    const prefix_str = if (prefix.isString()) prefix.asString().data else "tmp";

    // 生成唯一文件名
    const ts = milliTimestamp();
    const pid = std.posix.system.getpid();
    const name = try std.fmt.allocPrint(allocator, "{s}/{s}{d}_{d}.tmp", .{ dir_str, prefix_str, pid, ts });
    defer allocator.free(name);

    return Value.initString(try PHPString.init(allocator, name));
}

/// debug_zval_dump - 输出变量的 zval 信息
pub fn php_debug_zval_dump(value: Value) !Value {
    if (value.isString()) {
        const s = value.asString();
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "string({d}) \"{s}\" refcount(1)\n", .{ s.length, s.data }) catch "string(?)\n";
        fileWriteAll(1, msg);
    } else if (value.isInt()) {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "int({d})\n", .{value.asInt()}) catch "int(?)\n";
        fileWriteAll(1, msg);
    } else if (value.isFloat()) {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "float({d})\n", .{value.asFloat()}) catch "float(?)\n";
        fileWriteAll(1, msg);
    } else if (value.isBool()) {
        fileWriteAll(1, if (value.asBool()) "bool(true)\n" else "bool(false)\n");
    } else if (value.isNull()) {
        fileWriteAll(1, "NULL\n");
    } else if (value.isArray()) {
        const arr = value.asArray();
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "array({d}) refcount(1){{\n}}\n", .{arr.count()}) catch "array(?)\n";
        fileWriteAll(1, msg);
    } else {
        fileWriteAll(1, "unknown type\n");
    }
    return Value.initNull();
}

/// headers_list - 返回已发送的 HTTP 头列表
/// 在 CLI 模式下返回空数组
pub fn php_headers_list(allocator: Allocator) !Value {
    return Value.initArray(try PHPArray.init(allocator));
}

/// header - 发送 HTTP 头（CLI 模式下无操作）
pub fn php_header(header_str: Value, replace: Value, response_code: Value) !Value {
    _ = header_str;
    _ = replace;
    _ = response_code;
    // CLI 模式下 header() 无实际效果
    return Value.initNull();
}

/// http_response_code - 获取/设置 HTTP 响应状态码
threadlocal var current_http_response_code: i64 = 200;

pub fn php_http_response_code(code: Value) !Value {
    if (!code.isNull() and code.isInt()) {
        const prev = current_http_response_code;
        current_http_response_code = code.asInt();
        return Value.initInt(prev);
    }
    return Value.initInt(current_http_response_code);
}

// ============================================================================
// 输出缓冲系统
// ============================================================================

/// 输出缓冲栈
const OBLevel = struct {
    buffer: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 },
    callback: ?Value = null,
};

threadlocal var ob_stack: std.ArrayListUnmanaged(OBLevel) = .{ .items = &.{}, .capacity = 0 };
threadlocal var ob_initialized: bool = false;

fn ensureObInit() void {
    if (!ob_initialized) {
        ob_stack = .{ .items = &.{}, .capacity = 0 };
        ob_initialized = true;
    }
}

/// mysqli_connect stub — AOT不支持数据库，仅供function_exists识别
pub fn php_mysqli_connect(host: Value, user: Value, password: Value, db: Value, port: Value, socket: Value, allocator: Allocator) !Value {
    _ = host; _ = user; _ = password; _ = db; _ = port; _ = socket; _ = allocator;
    return Value.initBool(false);
}

/// token_get_all stub — AOT不支持PHP tokenizer，仅供function_exists识别
pub fn php_token_get_all(source: Value, flags: Value, allocator: Allocator) !Value {
    _ = source; _ = flags;
    return Value.initArray(try PHPArray.init(allocator));
}

/// ob_gzhandler - zlib 输出缓冲回调
/// CLI/AOT 中不做压缩，按 PHP 回调签名原样返回 buffer
pub fn php_ob_gzhandler(buffer: Value, phase: Value, allocator: Allocator) !Value {
    _ = phase;
    if (!buffer.isString()) return Value.initString(try PHPString.init(allocator, ""));
    return Value.initString(try PHPString.init(allocator, buffer.asString().data));
}

/// ob_start - 打开输出缓冲
pub fn php_ob_start(callback: Value, allocator: Allocator) !Value {
    _ = allocator;
    ensureObInit();
    var level = OBLevel{};
    if (!callback.isNull()) {
        _ = callback.retain();
        level.callback = callback;
    }
    try ob_stack.append(runtime_allocator, level);
    return Value.initBool(true);
}

/// ob_get_contents - 返回输出缓冲区的内容
pub fn php_ob_get_contents(allocator: Allocator) !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    const level = &ob_stack.items[ob_stack.items.len - 1];
    return Value.initString(try PHPString.init(allocator, level.buffer.items));
}

/// ob_end_clean - 清除并关闭输出缓冲区
pub fn php_ob_end_clean() !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    var level = ob_stack.pop().?;
    level.buffer.deinit(runtime_allocator);
    if (level.callback) |cb| cb.release(runtime_allocator);
    return Value.initBool(true);
}

/// ob_get_clean - 获取缓冲区内容并关闭
pub fn php_ob_get_clean(allocator: Allocator) !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    const contents = try PHPString.init(allocator, ob_stack.items[ob_stack.items.len - 1].buffer.items);
    var level = ob_stack.pop().?;
    level.buffer.deinit(runtime_allocator);
    if (level.callback) |cb| cb.release(runtime_allocator);
    return Value.initString(contents);
}

/// ob_get_level - 返回输出缓冲区嵌套级别
pub fn php_ob_get_level() Value {
    ensureObInit();
    return Value.initInt(@intCast(ob_stack.items.len));
}

/// ob_flush - 刷新输出缓冲区
pub fn php_ob_flush() !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    const level = &ob_stack.items[ob_stack.items.len - 1];
    if (level.buffer.items.len > 0) {
        fileWriteAll(1, level.buffer.items);
        level.buffer.clearRetainingCapacity();
    }
    return Value.initBool(true);
}

/// ob_end_flush - 刷新并关闭输出缓冲区
pub fn php_ob_end_flush() !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    var level = ob_stack.pop().?;
    if (level.buffer.items.len > 0) {
        fileWriteAll(1, level.buffer.items);
    }
    level.buffer.deinit(runtime_allocator);
    if (level.callback) |cb| cb.release(runtime_allocator);
    return Value.initBool(true);
}

/// ob_get_length - 返回输出缓冲区内容的长度
pub fn php_ob_get_length() Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    const level = &ob_stack.items[ob_stack.items.len - 1];
    return Value.initInt(@intCast(level.buffer.items.len));
}

/// ob_get_status - 获取输出缓冲区的状态
pub fn php_ob_get_status(full_status: Value, allocator: Allocator) !Value {
    ensureObInit();
    if (full_status.toBool()) {
        // 返回所有级别的状态数组
        const result = try PHPArray.init(allocator);
        for (ob_stack.items, 0..) |_, i| {
            const level_arr = try PHPArray.init(allocator);
            const k_level = try PHPString.init(allocator, "level");
            try level_arr.set(allocator, ArrayKey{ .string = k_level }, Value.initInt(@intCast(i + 1)));
            const k_name = try PHPString.init(allocator, "name");
            try level_arr.set(allocator, ArrayKey{ .string = k_name }, Value.initString(try PHPString.init(allocator, "default output handler")));
            const k_buf = try PHPString.init(allocator, "buffer_size");
            try level_arr.set(allocator, ArrayKey{ .string = k_buf }, Value.initInt(0));
            try result.push(allocator, Value.initArray(level_arr));
        }
        return Value.initArray(result);
    }
    // 返回当前级别的状态
    if (ob_stack.items.len == 0) return Value.initArray(try PHPArray.init(allocator));
    const level_arr = try PHPArray.init(allocator);
    const k_level = try PHPString.init(allocator, "level");
    try level_arr.set(allocator, ArrayKey{ .string = k_level }, Value.initInt(@intCast(ob_stack.items.len)));
    const k_name = try PHPString.init(allocator, "name");
    try level_arr.set(allocator, ArrayKey{ .string = k_name }, Value.initString(try PHPString.init(allocator, "default output handler")));
    const k_buf = try PHPString.init(allocator, "buffer_size");
    try level_arr.set(allocator, ArrayKey{ .string = k_buf }, Value.initInt(0));
    return Value.initArray(level_arr);
}

/// ob_implicit_flush - 打开/关闭隐式刷新
pub fn php_ob_implicit_flush(flag: Value) Value {
    _ = flag;
    return Value.initNull();
}

/// get_resource_id - 返回资源的整数标识符
pub fn php_get_resource_id(val: Value) !Value {
    // AOT 中没有真正的资源类型，返回 0
    _ = val;
    return Value.initInt(0);
}

// ============================================================================
// JSON函数
// ============================================================================

/// json_encode - 将PHP值编码为JSON字符串
pub fn php_json_encode(value: Value, flags: Value, depth: Value, allocator: Allocator) !Value {
    // 解析flags（可选，默认0）
    const flags_int = if (flags.isInt()) flags.asInt() else 0;
    
    // 解析depth（可选，默认512）
    const depth_int = if (depth.isInt()) depth.asInt() else 512;
    
    _ = flags_int; // TODO: 实现flags支持（JSON_PRETTY_PRINT等）
    _ = depth_int; // TODO: 实现depth检查
    
    var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer buffer.deinit(allocator);

    try jsonEncodeValue(value, &buffer, allocator);

    const result = try PHPString.init(allocator, buffer.items);
    return Value.initString(result);
}

fn jsonEncodeValue(value: Value, buffer: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
    if (value.isNull()) {
        try buffer.appendSlice(allocator, "null");
    } else if (value.isBool()) {
        try buffer.appendSlice(allocator, if (value.asBool()) "true" else "false");
    } else if (value.isInt()) {
        const formatted = try std.fmt.allocPrint(allocator, "{d}", .{value.asInt()});
        defer allocator.free(formatted);
        try buffer.appendSlice(allocator, formatted);
    } else if (value.isFloat()) {
        const formatted = try std.fmt.allocPrint(allocator, "{d}", .{value.asFloat()});
        defer allocator.free(formatted);
        try buffer.appendSlice(allocator, formatted);
    } else if (value.isString()) {
        const str = value.asString();
        try buffer.append(allocator, '"');
        for (str.data) |c| {
            switch (c) {
                '"' => try buffer.appendSlice(allocator, "\\\""),
                '\\' => try buffer.appendSlice(allocator, "\\\\"),
                '\n' => try buffer.appendSlice(allocator, "\\n"),
                '\r' => try buffer.appendSlice(allocator, "\\r"),
                '\t' => try buffer.appendSlice(allocator, "\\t"),
                else => try buffer.append(allocator, c),
            }
        }
        try buffer.append(allocator, '"');
    } else if (value.isArray()) {
        const arr = value.asArray();
        var is_list = true;
        var expected_index: i64 = 0;

        // 检查是否是纯索引数组
        var it = arr.elements.iterator();
        while (it.next()) |entry| {
            switch (entry.key_ptr.*) {
                .integer => |k| {
                    if (k != expected_index) is_list = false;
                    expected_index += 1;
                },
                .string => is_list = false,
            }
            if (!is_list) break;
        }

        if (is_list) {
            try buffer.append(allocator, '[');
            var first = true;
            it = arr.elements.iterator();
            while (it.next()) |entry| {
                if (!first) try buffer.append(allocator, ',');
                try jsonEncodeValue(entry.value_ptr.*, buffer, allocator);
                first = false;
            }
            try buffer.append(allocator, ']');
        } else {
            try buffer.append(allocator, '{');
            var first = true;
            it = arr.elements.iterator();
            while (it.next()) |entry| {
                if (!first) try buffer.append(allocator, ',');

                // 写入键
                switch (entry.key_ptr.*) {
                    .integer => |k| {
                        try buffer.append(allocator, '"');
                        const key_str = try std.fmt.allocPrint(allocator, "{d}", .{k});
                        defer allocator.free(key_str);
                        try buffer.appendSlice(allocator, key_str);
                        try buffer.append(allocator, '"');
                    },
                    .string => |k| {
                        try buffer.append(allocator, '"');
                        for (k.data) |c| {
                            switch (c) {
                                '"' => try buffer.appendSlice(allocator, "\\\""),
                                '\\' => try buffer.appendSlice(allocator, "\\\\"),
                                '\n' => try buffer.appendSlice(allocator, "\\n"),
                                '\r' => try buffer.appendSlice(allocator, "\\r"),
                                '\t' => try buffer.appendSlice(allocator, "\\t"),
                                else => try buffer.append(allocator, c),
                            }
                        }
                        try buffer.append(allocator, '"');
                    },
                }
                try buffer.appendSlice(allocator, ":");

                // 写入值
                try jsonEncodeValue(entry.value_ptr.*, buffer, allocator);
                first = false;
            }
            try buffer.append(allocator, '}');
        }
    } else if (Value_isObject(value)) {
        // 对象序列化为JSON对象
        const obj = Value_asObject(value);
        try buffer.append(allocator, '{');
        var first = true;
        var it = obj.properties.iterator();
        while (it.next()) |entry| {
            if (!first) try buffer.append(allocator, ',');
            
            // 写入键
            try buffer.append(allocator, '"');
            for (entry.key_ptr.*) |c| {
                switch (c) {
                    '"' => try buffer.appendSlice(allocator, "\\\""),
                    '\\' => try buffer.appendSlice(allocator, "\\\\"),
                    '\n' => try buffer.appendSlice(allocator, "\\n"),
                    '\r' => try buffer.appendSlice(allocator, "\\r"),
                    '\t' => try buffer.appendSlice(allocator, "\\t"),
                    else => try buffer.append(allocator, c),
                }
            }
            try buffer.append(allocator, '"');
            try buffer.appendSlice(allocator, ":");
            
            // 写入值
            try jsonEncodeValue(entry.value_ptr.*, buffer, allocator);
            first = false;
        }
        try buffer.append(allocator, '}');
    } else {
        try buffer.appendSlice(allocator, "null");
    }
}

const json_error_none: i32 = 0;
const json_error_depth: i32 = 1;
const json_error_syntax: i32 = 4;

threadlocal var last_json_error_code: i32 = json_error_none;

pub fn php_json_last_error() Value {
    return Value.initInt(last_json_error_code);
}

pub fn php_json_last_error_msg(allocator: Allocator) !Value {
    const msg = switch (last_json_error_code) {
        json_error_none => "No error",
        json_error_depth => "Maximum stack depth exceeded",
        json_error_syntax => "Syntax error",
        else => "Unknown error",
    };
    return Value.initString(try PHPString.init(allocator, msg));
}

/// json_decode - 解析JSON字符串为PHP值
pub fn php_json_decode(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;

    const json = args[0];
    if (!json.isString()) {
        last_json_error_code = json_error_syntax;
        return Value.initNull();
    }

    const assoc = if (args.len >= 2) args[1] else Value.initBool(false);
    const depth_val = if (args.len >= 3) args[2] else Value.initInt(512);
    const is_assoc = if (assoc.isBool()) assoc.asBool() else assoc.toBool();
    const json_str = json.asString().data;
    var pos: usize = 0;
    const depth_i64 = @max(depth_val.toInt(), 1);
    const depth: usize = @intCast(depth_i64);

    const result = jsonDecodeValue(json_str, &pos, is_assoc, depth, allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.MaxDepthExceeded => {
            last_json_error_code = json_error_depth;
            return Value.initNull();
        },
        else => {
            last_json_error_code = json_error_syntax;
            return Value.initNull();
        },
    };

    skipWhitespace(json_str, &pos);
    if (pos != json_str.len) {
        result.release(allocator);
        last_json_error_code = json_error_syntax;
        return Value.initNull();
    }

    last_json_error_code = json_error_none;
    return result;
}

const JsonError = error{
    InvalidJson,
    UnexpectedEnd,
    OutOfMemory,
    StringTooLarge,
    MaxDepthExceeded,
};

fn jsonDecodeValue(json: []const u8, pos: *usize, assoc: bool, depth: usize, allocator: Allocator) JsonError!Value {
    skipWhitespace(json, pos);

    if (pos.* >= json.len) return error.UnexpectedEnd;

    const c = json[pos.*];

    if (c == 'n' and pos.* + 4 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 4], "null")) {
        pos.* += 4;
        return Value.initNull();
    }

    if (c == 't' and pos.* + 4 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 4], "true")) {
        pos.* += 4;
        return Value.initBool(true);
    }

    if (c == 'f' and pos.* + 5 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 5], "false")) {
        pos.* += 5;
        return Value.initBool(false);
    }

    if (c == '"') {
        return jsonDecodeString(json, pos, allocator);
    }

    if (c == '[') {
        if (depth == 0) return error.MaxDepthExceeded;
        return jsonDecodeArray(json, pos, assoc, depth - 1, allocator);
    }

    if (c == '{') {
        if (depth == 0) return error.MaxDepthExceeded;
        return jsonDecodeObject(json, pos, assoc, depth - 1, allocator);
    }

    if (c == '-' or (c >= '0' and c <= '9')) {
        return jsonDecodeNumber(json, pos);
    }

    return error.InvalidJson;
}

fn jsonDecodeString(json: []const u8, pos: *usize, allocator: Allocator) !Value {
    pos.* += 1; // 跳过开头的引号

    var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer buffer.deinit(allocator);

    while (pos.* < json.len and json[pos.*] != '"') {
        if (json[pos.*] == '\\' and pos.* + 1 < json.len) {
            pos.* += 1;
            switch (json[pos.*]) {
                'n' => try buffer.append(allocator, '\n'),
                'r' => try buffer.append(allocator, '\r'),
                't' => try buffer.append(allocator, '\t'),
                '"' => try buffer.append(allocator, '"'),
                '\\' => try buffer.append(allocator, '\\'),
                else => try buffer.append(allocator, json[pos.*]),
            }
        } else {
            try buffer.append(allocator, json[pos.*]);
        }
        pos.* += 1;
    }

    if (pos.* < json.len) pos.* += 1; // 跳过结尾的引号

    const result = try PHPString.init(allocator, buffer.items);
    return Value.initString(result);
}

fn jsonDecodeNumber(json: []const u8, pos: *usize) JsonError!Value {
    const start = pos.*;
    var is_float = false;

    if (json[pos.*] == '-') pos.* += 1;

    while (pos.* < json.len) {
        const c = json[pos.*];
        if (c >= '0' and c <= '9') {
            pos.* += 1;
        } else if (c == '.' or c == 'e' or c == 'E') {
            is_float = true;
            pos.* += 1;
        } else if (c == '+' or c == '-') {
            pos.* += 1;
        } else {
            break;
        }
    }

    const num_str = json[start..pos.*];

    if (is_float) {
        const f = std.fmt.parseFloat(f64, num_str) catch return Value.initFloat(0);
        return Value.initFloat(f);
    } else {
        const i = std.fmt.parseInt(i64, num_str, 10) catch return Value.initInt(0);
        return Value.initInt(i);
    }
}

fn jsonDecodeArray(json: []const u8, pos: *usize, assoc: bool, depth: usize, allocator: Allocator) JsonError!Value {
    pos.* += 1; // 跳过 '['

    const arr = try PHPArray.init(allocator);

    skipWhitespace(json, pos);

    if (pos.* < json.len and json[pos.*] == ']') {
        pos.* += 1;
        return Value.initArray(arr);
    }

    while (pos.* < json.len) {
        const value = try jsonDecodeValue(json, pos, assoc, depth, allocator);
        try arr.push(allocator, value);
        value.release(allocator);

        skipWhitespace(json, pos);

        if (pos.* < json.len and json[pos.*] == ',') {
            pos.* += 1;
            skipWhitespace(json, pos);
        } else {
            break;
        }
    }

    if (pos.* < json.len and json[pos.*] == ']') pos.* += 1;

    return Value.initArray(arr);
}

fn jsonDecodeObject(json: []const u8, pos: *usize, assoc: bool, depth: usize, allocator: Allocator) JsonError!Value {
    pos.* += 1; // 跳过 '{'

    const arr = try PHPArray.init(allocator);

    skipWhitespace(json, pos);

    if (pos.* < json.len and json[pos.*] == '}') {
        pos.* += 1;
        return Value.initArray(arr);
    }

    while (pos.* < json.len) {
        skipWhitespace(json, pos);

        // 解析键
        if (json[pos.*] != '"') return error.InvalidJson;
        const key = try jsonDecodeString(json, pos, allocator);

        skipWhitespace(json, pos);

        if (pos.* >= json.len or json[pos.*] != ':') return error.InvalidJson;
        pos.* += 1;

        // 解析值
        const value = try jsonDecodeValue(json, pos, assoc, depth, allocator);

        // 添加到数组
        if (key.isString()) {
            const key_str = key.asString();
            const array_key = ArrayKey{ .string = key_str };
            try arr.set(allocator, array_key, value);
        }
        key.release(allocator);
        value.release(allocator);

        skipWhitespace(json, pos);

        if (pos.* < json.len and json[pos.*] == ',') {
            pos.* += 1;
        } else {
            break;
        }
    }

    if (pos.* < json.len and json[pos.*] == '}') pos.* += 1;

    if (assoc) {
        return Value.initArray(arr);
    }

    const obj_val = php_object_new("stdClass", allocator) catch return error.OutOfMemory;
    const obj = Value_asObject(obj_val);
    var it = arr.elements.iterator();
    while (it.next()) |entry| {
        switch (entry.key_ptr.*) {
            .string => |k| obj.setProperty(k.data, entry.value_ptr.*) catch return error.OutOfMemory,
            .integer => |k| {
                var key_buf: [32]u8 = undefined;
                const key_str = std.fmt.bufPrint(&key_buf, "{d}", .{k}) catch return error.OutOfMemory;
                obj.setProperty(key_str, entry.value_ptr.*) catch return error.OutOfMemory;
            },
        }
    }

    return obj_val;
}

fn skipWhitespace(json: []const u8, pos: *usize) void {
    while (pos.* < json.len and (json[pos.*] == ' ' or json[pos.*] == '\t' or json[pos.*] == '\n' or json[pos.*] == '\r')) {
        pos.* += 1;
    }
}

// ============================================================================
// 杂项函数
// ============================================================================

/// strtotime - 将字符串转换为时间戳
pub fn php_strtotime(time_str: Value, now: Value, allocator: Allocator) !Value {
    _ = allocator;

    if (!time_str.isString()) return Value.initBool(false);
    const str = time_str.asString().data;
    const base_ts: i64 = if (now.isInt()) now.asInt() else unixTimestamp();

    // 相对时间："+N unit" 或 "-N unit" 或 "next X"
    if (str.len > 0 and (str[0] == '+' or str[0] == '-')) {
        const sign: i64 = if (str[0] == '+') 1 else -1;
        var i: usize = 1;
        while (i < str.len and str[i] == ' ') i += 1;
        var num: i64 = 0;
        while (i < str.len and str[i] >= '0' and str[i] <= '9') : (i += 1) {
            num = num * 10 + (str[i] - '0');
        }
        while (i < str.len and str[i] == ' ') i += 1;
        const unit = str[i..];
        const secs: i64 = if (std.mem.startsWith(u8, unit, "second")) num
            else if (std.mem.startsWith(u8, unit, "minute")) num * 60
            else if (std.mem.startsWith(u8, unit, "hour")) num * 3600
            else if (std.mem.startsWith(u8, unit, "day")) num * 86400
            else if (std.mem.startsWith(u8, unit, "week")) num * 604800
            else if (std.mem.startsWith(u8, unit, "month")) num * 2592000
            else if (std.mem.startsWith(u8, unit, "year")) num * 31536000
            else 0;
        return Value.initInt(base_ts + sign * secs);
    }

    // 尝试解析 "YYYY-MM-DD HH:MM:SS" 或 "YYYY-MM-DD"
    if (str.len >= 10 and str[4] == '-' and str[7] == '-') {
        const year = std.fmt.parseInt(i64, str[0..4], 10) catch return Value.initBool(false);
        const month = std.fmt.parseInt(i64, str[5..7], 10) catch return Value.initBool(false);
        const day = std.fmt.parseInt(i64, str[8..10], 10) catch return Value.initBool(false);
        var hour: i64 = 0;
        var min: i64 = 0;
        var sec: i64 = 0;
        if (str.len >= 19 and str[10] == ' ') {
            hour = std.fmt.parseInt(i64, str[11..13], 10) catch 0;
            min = std.fmt.parseInt(i64, str[14..16], 10) catch 0;
            sec = std.fmt.parseInt(i64, str[17..19], 10) catch 0;
        }
        // 简单计算时间戳（Zeller公式近似）
        const y = if (month <= 2) year - 1 else year;
        const m = if (month <= 2) month + 12 else month;
        const jd = 365 * y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) + @divFloor(306 * (m + 1), 10) + day - 719591;
        const ts: i64 = jd * 86400 + hour * 3600 + min * 60 + sec;
        return Value.initInt(ts);
    }

    // 返回当前时间戳作为fallback
    return Value.initInt(base_ts);
}

extern "c" fn sleep(seconds: c_uint) c_uint;
extern "c" fn usleep(usec: c_uint) c_int;

/// sleep - 延迟执行（秒）
pub fn php_sleep(seconds: Value) !Value {
    const secs: c_uint = @intCast(@max(0, seconds.toInt()));
    _ = sleep(secs);
    return Value.initInt(0);
}

/// usleep - 延迟执行（微秒）
pub fn php_usleep(microseconds: Value) !Value {
    const usecs: c_uint = @intCast(@max(0, microseconds.toInt()));
    _ = usleep(usecs);
    return Value.initNull();
}

/// exit/die - 终止程序执行
pub fn php_exit(status: Value) !noreturn {
    const code: u8 = if (status.isInt())
        @truncate(@as(u64, @intCast(status.asInt() & 0xFF)))
    else
        0;
    std.process.exit(code);
}

/// empty - 检查变量是否为空
pub fn php_empty(val: Value) !Value {
    if (val.isNull()) return Value.initBool(true);
    if (val.isBool()) return Value.initBool(!val.asBool());
    if (val.isInt()) return Value.initBool(val.asInt() == 0);
    if (val.isFloat()) return Value.initBool(val.asFloat() == 0);
    if (val.isString()) return Value.initBool(val.asString().length == 0 or std.mem.eql(u8, val.asString().data, "0"));
    if (val.isArray()) return Value.initBool(val.asArray().count() == 0);
    return Value.initBool(false);
}

/// isset - 检查变量是否已设置且非null（支持多个参数）
pub fn php_isset(args: []const Value) !Value {
    // isset()需要至少1个参数
    if (args.len == 0) return Value.initBool(false);
    
    // 所有参数都必须非null才返回true
    for (args) |val| {
        if (val.isNull()) return Value.initBool(false);
    }
    
    return Value.initBool(true);
}

pub fn empty(val: Value) !Value {
    return php_empty(val);
}

pub fn isset(val: Value) !Value {
    // 单参数版本的包装器
    return Value.initBool(!val.isNull());
}

// ============================================================================
// PCNTL / POSIX / IPC 函数
// ============================================================================

// libc 外部声明
extern "c" fn fork() std.posix.pid_t;
extern "c" fn waitpid(
    pid: std.posix.pid_t,
    status: *c_int,
    options: c_int,
) std.posix.pid_t;
extern "c" fn kill(
    pid: std.posix.pid_t,
    sig: c_int,
) c_int;
extern "c" fn alarm(seconds: c_uint) c_uint;
extern "c" fn getpid() std.posix.pid_t;
extern "c" fn signal(
    sig: c_int,
    handler: ?*const fn (c_int) callconv(.c) void,
) ?*const fn (c_int) callconv(.c) void;
extern "c" fn mkfifo(
    path: [*:0]const u8,
    mode: std.posix.mode_t,
) c_int;
extern "c" fn socketpair(
    domain: c_int,
    sock_type: c_int,
    protocol: c_int,
    sv: *[2]c_int,
) c_int;
extern "c" fn close(fd: c_int) c_int;

// System V IPC 外部声明
extern "c" fn msgget(key: c_int, msgflg: c_int) c_int;
extern "c" fn msgctl(
    msqid: c_int,
    cmd: c_int,
    buf: ?*anyopaque,
) c_int;
extern "c" fn semget(
    key: c_int,
    nsems: c_int,
    semflg: c_int,
) c_int;
extern "c" fn semctl(
    semid: c_int,
    semnum: c_int,
    cmd: c_int,
) c_int;
extern "c" fn shmget(
    key: c_int,
    size: usize,
    shmflg: c_int,
) c_int;
extern "c" fn shmctl(
    shmid: c_int,
    cmd: c_int,
    buf: ?*anyopaque,
) c_int;

const IPC_CREAT = 0o1000;
const IPC_RMID = 0;
const MAX_SIGNALS = 32;

var signal_handlers: [MAX_SIGNALS]Value = .{Value.initNull()}**MAX_SIGNALS;
var pending_signals: [MAX_SIGNALS]bool = .{false}**MAX_SIGNALS;
var last_wait_status: c_int = 0;

/// C 信号处理函数（仅设置标志位）
fn pcntl_c_signal_handler(sig: c_int) callconv(.c) void {
    const s: usize = @intCast(@max(0, sig));
    if (s < MAX_SIGNALS) {
        pending_signals[s] = true;
    }
}

/// pcntl_fork - 创建子进程
pub fn php_pcntl_fork() !Value {
    const pid = fork();
    return Value.initInt(@intCast(pid));
}

/// pcntl_waitpid - 等待指定子进程
pub fn php_pcntl_waitpid(
    pid_val: Value,
    _: Value,
    _: Allocator,
) !Value {
    const pid: std.posix.pid_t = @intCast(pid_val.toInt());
    var status: c_int = 0;
    const result = waitpid(pid, &status, 0);
    last_wait_status = status;
    return Value.initInt(@intCast(result));
}

/// pcntl_wait - 等待任意子进程
pub fn php_pcntl_wait(_: Value, _: Allocator) !Value {
    var status: c_int = 0;
    const result = waitpid(-1, &status, 0);
    last_wait_status = status;
    return Value.initInt(@intCast(result));
}

/// pcntl_wexitstatus - 提取子进程退出码
pub fn php_pcntl_wexitstatus(_: Value) !Value {
    const exit_code = (last_wait_status >> 8) & 0xFF;
    return Value.initInt(@intCast(exit_code));
}

/// pcntl_signal - 注册信号处理器
pub fn php_pcntl_signal(
    signo_val: Value,
    handler_val: Value,
    _: Allocator,
) !Value {
    const signo: usize = @intCast(
        @max(0, signo_val.toInt()),
    );
    if (signo >= MAX_SIGNALS) return Value.initBool(false);
    _ = handler_val.retain();
    signal_handlers[signo].release(runtime_allocator);
    signal_handlers[signo] = handler_val;
    _ = signal(
        @intCast(signo),
        pcntl_c_signal_handler,
    );
    return Value.initBool(true);
}

/// pcntl_signal_dispatch - 分派待处理信号
pub fn php_pcntl_signal_dispatch(_: Allocator) !Value {
    for (0..MAX_SIGNALS) |i| {
        if (pending_signals[i]) {
            pending_signals[i] = false;
            const handler = signal_handlers[i];
            if (!handler.isNull() and handler.isFunction()) {
                const closure = handler.asFunction();
                _ = closure.func(
                    handler,
                    &[_]Value{Value.initInt(@intCast(i))},
                    runtime_allocator,
                ) catch {};
            }
        }
    }
    return Value.initBool(true);
}

/// pcntl_alarm - 设置闹钟信号
pub fn php_pcntl_alarm(seconds_val: Value) !Value {
    const secs: c_uint = @intCast(
        @max(0, seconds_val.toInt()),
    );
    const prev = alarm(secs);
    return Value.initInt(@intCast(prev));
}

/// pcntl_sigprocmask - 设置信号屏蔽字
pub fn php_pcntl_sigprocmask(
    _: Value,
    _: Value,
    _: Allocator,
) !Value {
    return Value.initBool(true);
}

/// posix_getpid - 获取当前进程 ID
pub fn php_posix_getpid() !Value {
    return Value.initInt(@intCast(getpid()));
}

/// posix_kill - 向进程发送信号
pub fn php_posix_kill(
    pid_val: Value,
    sig_val: Value,
) !Value {
    const pid: std.posix.pid_t = @intCast(
        pid_val.toInt(),
    );
    const sig: c_int = @intCast(sig_val.toInt());
    const ret = kill(pid, sig);
    return Value.initBool(ret == 0);
}

/// posix_mkfifo - 创建 FIFO 特殊文件
pub fn php_posix_mkfifo(
    path_val: Value,
    mode_val: Value,
    allocator: Allocator,
) !Value {
    const path_str = try path_val.toString(allocator);
    defer path_str.release(allocator);
    const mode: std.posix.mode_t = @intCast(
        @max(0, mode_val.toInt()),
    );
    const path_z = try allocator.dupeSentinel(u8, path_str.data, 0);
    defer allocator.free(path_z);
    const ret = mkfifo(path_z, mode);
    return Value.initBool(ret == 0);
}

/// ftok - 生成 System V IPC 键值
pub fn php_ftok(
    path_val: Value,
    proj_val: Value,
    allocator: Allocator,
) !Value {
    const path_str = try path_val.toString(allocator);
    defer path_str.release(allocator);
    const proj_str = try proj_val.toString(allocator);
    defer proj_str.release(allocator);
    const proj_id: i64 = if (proj_str.data.len > 0)
        @intCast(proj_str.data[0])
    else
        0;
    // 简化 ftok: 使用路径哈希 + proj_id
    var hash: u32 = 0;
    for (path_str.data) |c| {
        hash = hash *% 31 +% @as(u32, c);
    }
    const key = (@as(i64, proj_id) << 24) |
        @as(i64, hash & 0xFFFFFF);
    return Value.initInt(key);
}

/// msg_get_queue - 获取消息队列
pub fn php_msg_get_queue(
    key_val: Value,
    allocator: Allocator,
) !Value {
    const key: c_int = @intCast(key_val.toInt());
    const id = msgget(key, IPC_CREAT | 0o666);
    if (id < 0) return Value.initBool(false);
    _ = allocator;
    return Value.initInt(@intCast(id));
}

/// msg_remove_queue - 删除消息队列
pub fn php_msg_remove_queue(queue_val: Value) !Value {
    const id: c_int = @intCast(queue_val.toInt());
    const ret = msgctl(id, IPC_RMID, null);
    return Value.initBool(ret == 0);
}

/// sem_get - 获取信号量
pub fn php_sem_get(
    key_val: Value,
    max_val: Value,
    allocator: Allocator,
) !Value {
    _ = allocator;
    const key: c_int = @intCast(key_val.toInt());
    const nsems: c_int = @intCast(
        @max(1, max_val.toInt()),
    );
    const id = semget(key, nsems, IPC_CREAT | 0o666);
    if (id < 0) return Value.initBool(false);
    return Value.initInt(@intCast(id));
}

/// sem_remove - 删除信号量
pub fn php_sem_remove(sem_val: Value) !Value {
    const id: c_int = @intCast(sem_val.toInt());
    const ret = semctl(id, 0, IPC_RMID);
    return Value.initBool(ret == 0);
}

/// shmop_open - 打开共享内存段
pub fn php_shmop_open(
    key_val: Value,
    flags_val: Value,
    mode_val: Value,
    size_val: Value,
    allocator: Allocator,
) !Value {
    _ = allocator;
    _ = flags_val;
    const key: c_int = @intCast(key_val.toInt());
    const mode: c_int = @intCast(
        @max(0, mode_val.toInt()),
    );
    const size: usize = @intCast(
        @max(1, size_val.toInt()),
    );
    const id = shmget(key, size, IPC_CREAT | mode);
    if (id < 0) return Value.initBool(false);
    return Value.initInt(@intCast(id));
}

/// shmop_close - 关闭共享内存段
pub fn php_shmop_close(_: Value) !Value {
    return Value.initBool(true);
}

/// socket_create_pair - 创建套接字对
pub fn php_socket_create_pair(
    domain_val: Value,
    type_val: Value,
    protocol_val: Value,
    _: Value,
    allocator: Allocator,
) !Value {
    const domain: c_int = @intCast(domain_val.toInt());
    const sock_type: c_int = @intCast(
        type_val.toInt(),
    );
    const protocol: c_int = @intCast(
        protocol_val.toInt(),
    );
    var sv: [2]c_int = .{ -1, -1 };
    const ret = socketpair(
        domain,
        sock_type,
        protocol,
        &sv,
    );
    if (ret != 0) return Value.initBool(false);
    const arr = try PHPArray.init(allocator);
    try arr.push(allocator, Value.initInt(sv[0]));
    try arr.push(allocator, Value.initInt(sv[1]));
    return Value.initArray(arr);
}

/// socket_close - 关闭套接字
pub fn php_socket_close(fd_val: Value) !Value {
    const fd: c_int = @intCast(fd_val.toInt());
    _ = close(fd);
    return Value.initBool(true);
}

// ============================================================================
// 高阶数组函数
// ============================================================================

/// array_map - 对一个或多个数组的每个元素应用回调函数
pub fn php_array_map(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 2) return error.InvalidArgumentCount;

    const callback = args[0];
    const arrays = args[1..];
    for (arrays) |arr| {
        if (!arr.isArray()) return error.InvalidArgument;
    }

    const result_arr = try PHPArray.init(allocator);

    if (callback.isNull()) {
        if (arrays.len == 1) {
            const src = arrays[0].asArray();
            var src_iter = src.elements.iterator();
            while (src_iter.next()) |entry| {
                try result_arr.set(allocator, entry.key_ptr.*, entry.value_ptr.*);
            }
            return Value.initArray(result_arr);
        }

        var max_count: i64 = 0;
        for (arrays) |arr| {
            const cur = arr.asArray();
            if (cur.next_index > max_count) max_count = cur.next_index;
        }

        var idx: i64 = 0;
        while (idx < max_count) : (idx += 1) {
            const tuple_arr = try PHPArray.init(allocator);
            const key = ArrayKey{ .integer = idx };

            for (arrays) |arr| {
                const cur = arr.asArray();
                const val = cur.get(key) orelse Value.initNull();
                try tuple_arr.push(allocator, val);
            }

            try result_arr.push(allocator, Value.initArray(tuple_arr));
        }

        return Value.initArray(result_arr);
    }

    const primary = arrays[0].asArray();

    var iter = primary.elements.iterator();
    while (iter.next()) |entry| {
        var callback_args = try allocator.alloc(Value, arrays.len);
        defer allocator.free(callback_args);

        callback_args[0] = entry.value_ptr.*;

        var i: usize = 1;
        while (i < arrays.len) : (i += 1) {
            const cur = arrays[i].asArray();
            callback_args[i] = cur.elements.get(entry.key_ptr.*) orelse Value.initNull();
        }

        const result_value = try php_invoke_callable(callback, callback_args, allocator);
        try result_arr.set(allocator, entry.key_ptr.*, result_value);
        result_value.release(allocator);
    }

    return Value.initArray(result_arr);
}

/// array_filter - 过滤数组元素
/// mode: 0 = 只传值, 1 = 传值和键 (ARRAY_FILTER_USE_BOTH), 2 = 传键 (ARRAY_FILTER_USE_KEY)
pub fn php_array_filter(arr: Value, callback: Value, mode: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);
    const mode_int: u32 = if (mode.isInt()) @intCast(@max(mode.asInt(), 0)) else 0;

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const should_keep = if (callback.isNull()) blk: {
            // 无回调时，检查值是否为真
            break :blk entry.value_ptr.*.toBool();
        } else blk: {
            // 根据mode决定传参方式
            const result = switch (mode_int) {
                0 => blk2: {
                    // ARRAY_FILTER_USE_VALUE (默认) - 只传值
                    const args = [_]Value{entry.value_ptr.*};
                    break :blk2 try php_invoke_callable(callback, &args, allocator);
                },
                1 => blk2: {
                    // ARRAY_FILTER_USE_BOTH - 传值和键
                    const key_val = switch (entry.key_ptr.*) {
                        .integer => |k| Value.initInt(k),
                        .string => |s| blk_s: {
                            s.retain(); // 增加引用计数
                            break :blk_s Value.initString(s);
                        },
                    };
                    const args = [_]Value{ entry.value_ptr.*, key_val };
                    break :blk2 try php_invoke_callable(callback, &args, allocator);
                },
                2 => blk2: {
                    // ARRAY_FILTER_USE_KEY - 只传键
                    const key_val = switch (entry.key_ptr.*) {
                        .integer => |k| Value.initInt(k),
                        .string => |s| blk_s: {
                            s.retain(); // 增加引用计数
                            break :blk_s Value.initString(s);
                        },
                    };
                    const args = [_]Value{key_val};
                    break :blk2 try php_invoke_callable(callback, &args, allocator);
                },
                else => blk2: {
                    // 默认行为：只传值
                    const args = [_]Value{entry.value_ptr.*};
                    break :blk2 try php_invoke_callable(callback, &args, allocator);
                },
            };
            defer result.release(allocator);
            break :blk result.toBool();
        };

        if (should_keep) {
            try result_arr.set(allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    return Value.initArray(result_arr);
}

/// array_reduce - 使用回调函数迭代地将数组简化为单一值
pub fn php_array_reduce(arr: Value, callback: Value, initial: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    var carry = initial.retain();

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{ carry, entry.value_ptr.* };
        const new_carry = try php_invoke_callable(callback, &args, allocator);
        carry.release(allocator);
        carry = new_carry;
    }

    return carry;
}

/// array_find - 查找数组中第一个满足回调条件的元素 (PHP 8.4+)
pub fn php_array_find(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{entry.value_ptr.*};
        const result = try php_invoke_callable(callback, &args, allocator);
        defer result.release(allocator);
        if (result.toBool()) {
            return entry.value_ptr.*.retain();
        }
    }
    return Value.initNull();
}

/// array_find_key - PHP 8.4: 返回第一个满足回调的元素的键
pub fn php_array_find_key(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();
    const php_arr = arr.asArray();
    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{entry.value_ptr.*};
        const result = try php_invoke_callable(callback, &args, allocator);
        defer result.release(allocator);
        if (result.toBool()) {
            return switch (entry.key_ptr.*) {
                .int => |k| Value.initInt(k),
                .string => |s| Value.initString(try PHPString.init(allocator, s)),
            };
        }
    }
    return Value.initNull();
}

/// array_chunk - 将数组分割成指定大小的块
/// array_chunk - 将数组分割成指定大小的块
pub fn php_array_chunk(arr: Value, size: Value, preserve_keys: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const chunk_size = size.toInt();
    if (chunk_size < 1) return error.InvalidArgument;

    const preserve = preserve_keys.toBool();
    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var current_chunk = try PHPArray.init(allocator);
    var count: i64 = 0;
    var new_index: i64 = 0;

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        if (preserve) {
            try current_chunk.set(allocator, entry.key_ptr.*, entry.value_ptr.*);
        } else {
            try current_chunk.push(allocator, entry.value_ptr.*);
        }
        count += 1;

        if (count >= chunk_size) {
            try result_arr.set(allocator, .{ .integer = new_index }, Value.initArray(current_chunk));
            new_index += 1;
            current_chunk = try PHPArray.init(allocator);
            count = 0;
        }
    }

    if (count > 0) {
        try result_arr.set(allocator, .{ .integer = new_index }, Value.initArray(current_chunk));
    } else {
        current_chunk.release(allocator);
    }

    return Value.initArray(result_arr);
}

/// array_column - 返回数组中指定列的值
pub fn php_array_column(arr: Value, column_key: Value, index_key: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const row = entry.value_ptr.*;
        if (!row.isArray()) continue;

        const row_arr = row.asArray();

        // 获取列值
        const col_value = if (column_key.isInt()) blk: {
            break :blk row_arr.get(.{ .integer = column_key.asInt() });
        } else if (column_key.isString()) blk: {
            break :blk arrayGetByString(row_arr, column_key.asString().data);
        } else blk: {
            break :blk null;
        };

        if (col_value) |val| {
            // 确定索引
            if (index_key.isNull()) {
                try result_arr.push(allocator, val);
            } else {
                const idx_value = if (index_key.isInt()) blk: {
                    break :blk row_arr.get(.{ .integer = index_key.asInt() });
                } else if (index_key.isString()) blk: {
                    break :blk arrayGetByString(row_arr, index_key.asString().data);
                } else blk: {
                    break :blk null;
                };

                if (idx_value) |idx| {
                    if (idx.isInt()) {
                        try result_arr.set(allocator, .{ .integer = idx.asInt() }, val);
                    } else if (idx.isString()) {
                        try arraySetByString(result_arr, allocator, idx.asString().data, val);
                    } else {
                        try result_arr.push(allocator, val);
                    }
                } else {
                    try result_arr.push(allocator, val);
                }
            }
        }
    }

    return Value.initArray(result_arr);
}

/// array_walk - 对数组中的每个元素应用用户自定义函数
pub fn php_array_walk(arr: Value, callback: Value, userdata: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        // 构建回调参数：value(by-ref), key, userdata
        const key_val = switch (entry.key_ptr.*) {
            .integer => |k| Value.initInt(k),
            .string => |k| Value.initString(k),
        };

        // array_walk 的回调第一个参数按引用传递（PHP 规范）
        // 直接用 entry.value_ptr 构造 Ref，使回调内对 $value 的赋值写回数组槽位
        // iterator 返回 *const Value，此处需要可写指针以实现引用语义
        var args_buf: [3]Value = undefined;
        args_buf[0] = Value.initRef(@constCast(entry.value_ptr));
        args_buf[1] = key_val;
        const arg_count: usize = if (userdata.isNull()) 2 else blk: {
            args_buf[2] = userdata;
            break :blk 3;
        };

        const result = try php_invoke_callable(callback, args_buf[0..arg_count], allocator);
        result.release(allocator);
    }

    return Value.initBool(true);
}

fn php_array_walk_recursive_inner(arr: *PHPArray, callback: Value, userdata: Value, allocator: Allocator) !void {
    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;
        if (value.isArray()) {
            try php_array_walk_recursive_inner(value.asArray(), callback, userdata, allocator);
            continue;
        }

        const key_val = switch (entry.key_ptr.*) {
            .integer => |k| Value.initInt(k),
            .string => |k| Value.initString(k),
        };

        var args_buf: [3]Value = undefined;
        args_buf[0] = value;
        args_buf[1] = key_val;
        const arg_count: usize = if (userdata.isNull()) 2 else blk: {
            args_buf[2] = userdata;
            break :blk 3;
        };

        const result = try php_invoke_callable(callback, args_buf[0..arg_count], allocator);
        result.release(allocator);
    }
}

pub fn php_array_walk_recursive(arr: Value, callback: Value, userdata: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;
    try php_array_walk_recursive_inner(arr.asArray(), callback, userdata, allocator);
    return Value.initBool(true);
}

// ============================================================================
// 字符串高级函数
// ============================================================================

/// 格式化浮点数到指定精度（用于 sprintf %f）
fn formatFloatPrecision(buf: []u8, val: f64, precision: usize) []const u8 {
    // 使用 comptime 格式字符串处理常见精度值
    return switch (precision) {
        0 => std.fmt.bufPrint(buf, "{d:.0}", .{val}) catch "0",
        1 => std.fmt.bufPrint(buf, "{d:.1}", .{val}) catch "0",
        2 => std.fmt.bufPrint(buf, "{d:.2}", .{val}) catch "0",
        3 => std.fmt.bufPrint(buf, "{d:.3}", .{val}) catch "0",
        4 => std.fmt.bufPrint(buf, "{d:.4}", .{val}) catch "0",
        5 => std.fmt.bufPrint(buf, "{d:.5}", .{val}) catch "0",
        6 => std.fmt.bufPrint(buf, "{d:.6}", .{val}) catch "0",
        7 => std.fmt.bufPrint(buf, "{d:.7}", .{val}) catch "0",
        8 => std.fmt.bufPrint(buf, "{d:.8}", .{val}) catch "0",
        9 => std.fmt.bufPrint(buf, "{d:.9}", .{val}) catch "0",
        10 => std.fmt.bufPrint(buf, "{d:.10}", .{val}) catch "0",
        else => std.fmt.bufPrint(buf, "{d:.6}", .{val}) catch "0",
    };
}

/// sprintf - 格式化字符串
pub fn php_sprintf(format: Value, args: []const Value, allocator: Allocator) !Value {
    if (!format.isString()) return error.InvalidArgument;

    const fmt = format.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit();

    var arg_idx: usize = 0;
    var i: usize = 0;

    while (i < fmt.len) {
        if (fmt[i] == '%' and i + 1 < fmt.len) {
            i += 1;
            if (fmt[i] == '%') {
                try result.append('%');
                i += 1;
                continue;
            }

            // 解析标志
            var flag_minus = false;
            var flag_plus = false;
            var flag_space = false;
            var flag_zero = false;
            var pad_char: u8 = ' ';
            while (i < fmt.len) {
                switch (fmt[i]) {
                    '-' => flag_minus = true,
                    '+' => flag_plus = true,
                    ' ' => flag_space = true,
                    '0' => flag_zero = true,
                    '\'' => {
                        // PHP custom pad char: %'x10s
                        i += 1;
                        if (i < fmt.len) {
                            pad_char = fmt[i];
                        }
                    },
                    else => break,
                }
                i += 1;
            }
            if (flag_zero and !flag_minus) pad_char = '0';

            // 解析宽度
            var width: usize = 0;
            while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                width = width * 10 + (fmt[i] - '0');
                i += 1;
            }

            // 解析精度
            var precision: ?usize = null;
            if (i < fmt.len and fmt[i] == '.') {
                i += 1;
                var prec_val: usize = 0;
                while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                    prec_val = prec_val * 10 + (fmt[i] - '0');
                    i += 1;
                }
                precision = prec_val;
            }

            if (i >= fmt.len) break;

            const specifier = fmt[i];
            i += 1;

            if (arg_idx >= args.len) continue;
            const arg = args[arg_idx];
            arg_idx += 1;

            // Format the value into a temporary buffer, then apply width/padding
            var tmp_buf = try std.ArrayList(u8).initCapacity(allocator, 0);
            defer tmp_buf.deinit(allocator);

            switch (specifier) {
                's' => {
                    if (arg.isString()) {
                        const sdata = arg.asString().data;
                        if (precision) |prec| {
                            const len = @min(prec, sdata.len);
                            try tmp_buf.appendSlice(allocator, sdata[0..len]);
                        } else {
                            try tmp_buf.appendSlice(allocator, sdata);
                        }
                    } else {
                        const str = try arg.toString(allocator);
                        defer str.release(allocator);
                        if (precision) |prec| {
                            const len = @min(prec, str.data.len);
                            try tmp_buf.appendSlice(allocator, str.data[0..len]);
                        } else {
                            try tmp_buf.appendSlice(allocator, str.data);
                        }
                    }
                },
                'd', 'i' => {
                    const val = arg.toInt();
                    if (flag_plus and val >= 0) try tmp_buf.append(allocator, '+')
                    else if (flag_space and val >= 0) try tmp_buf.append(allocator, ' ');
                    const str = try std.fmt.allocPrint(allocator, "{d}", .{val});
                    defer allocator.free(str);
                    try tmp_buf.appendSlice(allocator, str);
                },
                'f' => {
                    const val = arg.toFloat();
                    if (flag_plus and val >= 0) try tmp_buf.append(allocator, '+')
                    else if (flag_space and val >= 0) try tmp_buf.append(allocator, ' ');
                    const prec = precision orelse 6;
                    var fbuf: [128]u8 = undefined;
                    const fstr = formatFloatPrecision(&fbuf, val, prec);
                    try tmp_buf.appendSlice(allocator, fstr);
                },
                'x' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{x}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try tmp_buf.appendSlice(allocator, str);
                },
                'X' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{X}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try tmp_buf.appendSlice(allocator, str);
                },
                'c' => {
                    const val = arg.toInt();
                    if (val >= 0 and val <= 255) {
                        try tmp_buf.append(allocator, @intCast(val));
                    }
                },
                'u' => {
                    const val = arg.toInt();
                    const uval: u64 = @bitCast(val);
                    const str = try std.fmt.allocPrint(allocator, "{d}", .{uval});
                    defer allocator.free(str);
                    try tmp_buf.appendSlice(allocator, str);
                },
                'o' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{o}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try tmp_buf.appendSlice(allocator, str);
                },
                'b' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{b}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try tmp_buf.appendSlice(allocator, str);
                },
                'e', 'E' => {
                    const val = arg.toFloat();
                    const str = try std.fmt.allocPrint(allocator, "{e}", .{val});
                    defer allocator.free(str);
                    try tmp_buf.appendSlice(allocator, str);
                },
                else => {
                    try result.append('%');
                    try result.append(specifier);
                    continue;
                },
            }

            // Apply width padding
            const content = tmp_buf.items;
            if (width > 0 and content.len < width) {
                const padding = width - content.len;
                if (flag_minus) {
                    // Left-align: content first, then padding
                    try result.appendSlice(content);
                    for (0..padding) |_| try result.append(pad_char);
                } else {
                    // Right-align: padding first, then content
                    // For zero-padding with sign, put sign before zeros
                    if (pad_char == '0' and content.len > 0 and (content[0] == '-' or content[0] == '+' or content[0] == ' ')) {
                        try result.append(content[0]);
                        for (0..padding) |_| try result.append('0');
                        try result.appendSlice(content[1..]);
                    } else {
                        for (0..padding) |_| try result.append(pad_char);
                        try result.appendSlice(content);
                    }
                }
            } else {
                try result.appendSlice(content);
            }
        } else {
            try result.append(fmt[i]);
            i += 1;
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// vsprintf - 格式化字符串（参数为数组）
pub fn php_vsprintf(format: Value, args_arr: Value, allocator: Allocator) !Value {
    if (!format.isString()) return error.InvalidArgument;
    // 将数组参数展开为切片
    if (args_arr.isArray()) {
        const arr = args_arr.asArray();
        const count = arr.count();
        const args = try allocator.alloc(Value, count);
        defer allocator.free(args);
        var iter = arr.elements.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| {
            if (i < count) {
                args[i] = entry.value_ptr.*;
                i += 1;
            }
        }
        return php_sprintf(format, args[0..i], allocator);
    }
    return php_sprintf(format, &[_]Value{}, allocator);
}

pub fn php_sscanf(str: Value, format: Value, allocator: Allocator) !Value {
    if (!str.isString() or !format.isString()) return Value.initBool(false);
    
    const input = str.asString().data;
    const fmt = format.asString().data;
    
    var arr = try PHPArray.init(allocator);
    var input_pos: usize = 0;
    var fmt_pos: usize = 0;
    
    while (fmt_pos < fmt.len and input_pos < input.len) {
        if (fmt[fmt_pos] == '%' and fmt_pos + 1 < fmt.len) {
            fmt_pos += 1;
            const spec = fmt[fmt_pos];
            fmt_pos += 1;
            
            // 跳过空白
            while (input_pos < input.len and input[input_pos] == ' ') input_pos += 1;
            
            if (spec == 'd') {
                // 解析整数
                var num: i64 = 0;
                var neg = false;
                if (input_pos < input.len and input[input_pos] == '-') {
                    neg = true;
                    input_pos += 1;
                }
                while (input_pos < input.len and input[input_pos] >= '0' and input[input_pos] <= '9') {
                    num = num * 10 + (input[input_pos] - '0');
                    input_pos += 1;
                }
                if (neg) num = -num;
                try arr.push(allocator, Value.initInt(num));
            } else if (spec == 's') {
                // 解析字符串（到空白）
                const start = input_pos;
                while (input_pos < input.len and input[input_pos] != ' ') input_pos += 1;
                const s = try allocator.dupe(u8, input[start..input_pos]);
                const php_str = try PHPString.init(allocator, s);
                try arr.push(allocator, Value.initString(php_str));
            }
        } else {
            // 匹配字面字符
            if (input_pos < input.len and input[input_pos] == fmt[fmt_pos]) {
                input_pos += 1;
            }
            fmt_pos += 1;
        }
    }
    
    return Value.initArray(arr);
}

pub fn php_preg_match(pattern: Value, subject: Value, matches: *Value, flags: Value, offset: Value, allocator: Allocator) !Value {
    _ = flags; // TODO: 实现flags支持
    _ = offset; // TODO: 实现offset支持
    
    if (!pattern.isString() or !subject.isString()) {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    const pattern_str = pattern.asString();
    const subject_str = subject.asString();
    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };
    defer pcre2_match_data_free_8(match_data);

    const rc = pcre2_match_8(
        re,
        subject_str.data.ptr,
        subject_str.length,
        0,
        0,
        match_data,
        null,
    );

    if (rc == PCRE2_ERROR_NOMATCH or rc < 0) {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    // 填充matches数组
    const matches_arr = try PHPArray.init(allocator);
    const ovec = pcre2_get_ovector_pointer_8(match_data);

    var i: usize = 0;
    while (i < @as(usize, @intCast(rc))) : (i += 1) {
        const start = ovec[i * 2];
        const end = ovec[i * 2 + 1];
        if (start < subject_str.length and end <= subject_str.length and start <= end) {
            const capture = subject_str.data[start..end];
            const capture_str = try PHPString.init(allocator, capture);
            try matches_arr.push(allocator, Value.initString(capture_str));
        }
    }

    matches.* = Value.initArray(matches_arr);
    return Value.initInt(1);
}

pub fn php_preg_match_all(pattern: Value, subject: Value, matches: *Value, flags: Value, offset: Value, allocator: Allocator) !Value {
    _ = flags;
    _ = offset;
    
    if (!pattern.isString() or !subject.isString()) {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    const pattern_str = pattern.asString();
    const subject_str = subject.asString();
    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };
    defer pcre2_match_data_free_8(match_data);

    // 存储所有匹配（临时）
    var all_matches = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]const u8)){ .items = &.{}, .capacity = 0 };
    defer {
        for (all_matches.items) |*match_groups| {
            match_groups.deinit(allocator);
        }
        all_matches.deinit(allocator);
    }

    var match_offset: usize = 0;
    var match_count: i64 = 0;

    // 循环匹配所有
    while (match_offset <= subject_str.length) {
        const rc = pcre2_match_8(
            re,
            subject_str.data.ptr,
            subject_str.length,
            @intCast(match_offset),
            0,
            match_data,
            null,
        );

        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) break;

        match_count += 1;
        const ovec = pcre2_get_ovector_pointer_8(match_data);

        // 保存当前匹配的所有组
        var match_groups = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            if (start < subject_str.length and end <= subject_str.length and start <= end) {
                const capture = subject_str.data[start..end];
                try match_groups.append(allocator, capture);
            }
        }
        try all_matches.append(allocator, match_groups);

        // 移动到下一个位置
        const match_end = ovec[1];
        if (match_end == match_offset) {
            match_offset += 1; // 避免空匹配无限循环
        } else {
            match_offset = match_end;
        }
    }

    // 转换为PREG_PATTERN_ORDER格式
    // matches[0] = [所有完整匹配]
    // matches[1] = [所有第1个捕获组]
    const matches_arr = try PHPArray.init(allocator);

    if (all_matches.items.len > 0) {
        const num_groups = all_matches.items[0].items.len;

        // 为每个组创建数组
        var group_idx: usize = 0;
        while (group_idx < num_groups) : (group_idx += 1) {
            const group_arr = try PHPArray.init(allocator);

            // 收集所有匹配中的该组
            for (all_matches.items) |match_groups| {
                if (group_idx < match_groups.items.len) {
                    const capture = match_groups.items[group_idx];
                    const capture_str = try PHPString.init(allocator, capture);
                    try group_arr.push(allocator, Value.initString(capture_str));
                }
            }

            try matches_arr.push(allocator, Value.initArray(group_arr));
        }
    }

    matches.* = Value.initArray(matches_arr);
    return Value.initInt(match_count);
}

pub fn php_preg_replace(pattern: Value, replacement: Value, subject: Value, allocator: Allocator) !Value {
    if (!pattern.isString() or !replacement.isString() or !subject.isString()) 
        return Value.initBool(false);
    
    const pat = pattern.asString().data;
    const repl = replacement.asString().data;
    const subj = subject.asString().data;
    
    if (pat.len < 3) return Value.initString(try PHPString.init(allocator, try allocator.dupe(u8, subj)));
    const actual_pat = pat[1..pat.len-1];
    
    // 简单替换
    var result = try std.ArrayList(u8).initCapacity(allocator, subj.len);
    defer result.deinit();
    
    var pos: usize = 0;
    while (pos < subj.len) {
        if (std.mem.indexOf(u8, subj[pos..], actual_pat)) |idx| {
            try result.appendSlice(subj[pos..pos+idx]);
            try result.appendSlice(repl);
            pos += idx + actual_pat.len;
        } else {
            try result.appendSlice(subj[pos..]);
            break;
        }
    }
    
    const output = try PHPString.init(allocator, try result.toOwnedSlice());
    return Value.initString(output);
}

pub fn php_preg_replace_callback(pattern: Value, callback: Value, subject: Value, allocator: Allocator) !Value {
    if (!pattern.isString() or !subject.isString()) 
        return Value.initBool(false);
    
    const pattern_str = pattern.asString().data;
    const subject_str = subject.asString().data;
    
    // 解析 PHP 正则模式
    const parsed = parsePHPRegexPattern(pattern_str);
    
    // 编译正则表达式
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        return Value.initString(try PHPString.init(allocator, try allocator.dupe(u8, subject_str)));
    };
    
    // 创建匹配数据
    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        return Value.initString(try PHPString.init(allocator, try allocator.dupe(u8, subject_str)));
    };
    defer pcre2_match_data_free_8(match_data);
    
    // 准备输出缓冲区
    var result = try std.ArrayList(u8).initCapacity(allocator, subject_str.len * 2);
    defer result.deinit();
    
    var subject_offset: usize = 0;
    var replace_count: usize = 0;
    const limit: usize = std.math.maxInt(usize);
    
    while (subject_offset < subject_str.len and replace_count < limit) {
        const rc = pcre2_match_8(
            re,
            subject_str.ptr,
            subject_str.len,
            @as(c_int, @intCast(subject_offset)),
            0,
            match_data,
            null,
        );
        
        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) break;
        
        const ovec = pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovec[0];
        const match_end = ovec[1];
        
        // 添加匹配前的内容
        if (match_start > subject_offset) {
            try result.appendSlice(subject_str[subject_offset..match_start]);
        }
        
        // 构建匹配数组
        const matches_arr = try PHPArray.init(allocator);
        defer matches_arr.release(allocator);
        
        // 添加所有捕获组
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            const match_str = subject_str[start..end];
            const php_str = try PHPString.init(allocator, try allocator.dupe(u8, match_str));
            try matches_arr.push(allocator, Value.initString(php_str));
        }
        
        // 调用回调函数
        const callback_result = try php_invoke_callable(callback, &[_]Value{Value.initArray(matches_arr)}, allocator);
        defer callback_result.release(allocator);
        
        // 将回调结果添加到输出
        if (callback_result.isString()) {
            try result.appendSlice(callback_result.asString().data);
        } else if (callback_result.isInt()) {
            // 处理整数返回值
            const int_val = callback_result.asInt();
            var buf: [32]u8 = undefined;
            const int_str = try std.fmt.bufPrint(&buf, "{d}", .{int_val});
            try result.appendSlice(int_str);
        } else {
            const str_result = try callback_result.toString(allocator);
            defer str_result.release(allocator);
            try result.appendSlice(str_result.data);
        }
        
        subject_offset = match_end;
        replace_count += 1;
    }
    
    // 添加剩余内容
    if (subject_offset < subject_str.len) {
        try result.appendSlice(subject_str[subject_offset..]);
    }
    
    const output = try PHPString.init(allocator, try result.toOwnedSlice());
    return Value.initString(output);
}

pub fn php_preg_split(pattern: Value, subject: Value, limit_val: Value, flags_val: Value, allocator: Allocator) !Value {
    // 转发到 PCRE2 实现
    return preg_split(pattern, subject, limit_val, flags_val, allocator);
}

/// filter_var - 使用特定的过滤器过滤一个变量
pub fn php_filter_var(value: Value, filter: Value, allocator: Allocator) !Value {
    _ = allocator;
    
    if (!filter.isInt()) return Value.initBool(false);
    
    const filter_type = filter.asInt();
    
    // FILTER_VALIDATE_EMAIL = 274
    if (filter_type == 274) {
        if (!value.isString()) return Value.initBool(false);
        
        const email = value.asString().data;
        
        // 简单的邮箱验证：必须包含 @ 和 .，且格式合理
        if (email.len < 3) return Value.initBool(false);
        
        // 查找 @
        const at_pos = std.mem.indexOf(u8, email, "@") orelse return Value.initBool(false);
        if (at_pos == 0 or at_pos == email.len - 1) return Value.initBool(false);
        
        // @ 后面必须有 .
        const domain = email[at_pos+1..];
        const dot_pos = std.mem.indexOf(u8, domain, ".") orelse return Value.initBool(false);
        if (dot_pos == 0 or dot_pos == domain.len - 1) return Value.initBool(false);
        
        // 检查是否有多个 @
        if (std.mem.indexOf(u8, email[at_pos+1..], "@") != null) return Value.initBool(false);
        
        // 验证通过，返回原值
        return value;
    }
    
    // 其他过滤器类型暂不支持
    return Value.initBool(false);
}

/// htmlspecialchars - 将特殊字符转换为HTML实体
pub fn php_htmlspecialchars(str: Value, flags: Value, encoding: Value, double_encode: Value, allocator: Allocator) !Value {
    _ = flags;
    _ = encoding;
    _ = double_encode;
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit();

    for (input) |c| {
        switch (c) {
            '&' => try result.appendSlice("&amp;"),
            '"' => try result.appendSlice("&quot;"),
            '\'' => try result.appendSlice("&#039;"),
            '<' => try result.appendSlice("&lt;"),
            '>' => try result.appendSlice("&gt;"),
            else => try result.append(c),
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// htmlentities - 将所有适用的字符转换为HTML实体
pub fn php_htmlentities(str: Value, flags: Value, encoding: Value, double_encode: Value, allocator: Allocator) !Value {
    return php_htmlspecialchars(str, flags, encoding, double_encode, allocator);
}

/// htmlspecialchars_decode - 将HTML实体转换回字符
pub fn php_htmlspecialchars_decode(str: Value, flags: Value, allocator: Allocator) !Value {
    _ = flags;
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '&') {
            if (i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "&lt;")) {
                try result.append('<');
                i += 4;
            } else if (i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "&gt;")) {
                try result.append('>');
                i += 4;
            } else if (i + 5 <= input.len and std.mem.eql(u8, input[i .. i + 5], "&amp;")) {
                try result.append('&');
                i += 5;
            } else if (i + 6 <= input.len and std.mem.eql(u8, input[i .. i + 6], "&quot;")) {
                try result.append('"');
                i += 6;
            } else if (i + 6 <= input.len and std.mem.eql(u8, input[i .. i + 6], "&#039;")) {
                try result.append('\'');
                i += 6;
            } else {
                try result.append(input[i]);
                i += 1;
            }
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// wordwrap - 将字符串按指定长度换行
pub fn php_wordwrap(str: Value, width: Value, break_str: Value, cut: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const wrap_width: usize = @intCast(@max(1, width.toInt()));
    const break_chars = if (break_str.isString()) break_str.asString().data else "\n";
    const force_cut = cut.toBool();

    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit();

    var line_len: usize = 0;
    var word_start: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == ' ' or input[i] == '\n') {
            // 输出单词
            if (i > word_start) {
                const word = input[word_start..i];
                if (line_len + word.len > wrap_width and line_len > 0) {
                    try result.appendSlice(break_chars);
                    line_len = 0;
                }
                try result.appendSlice(word);
                line_len += word.len;
            }
            if (input[i] == '\n') {
                try result.append('\n');
                line_len = 0;
            } else {
                try result.append(' ');
                line_len += 1;
            }
            word_start = i + 1;
        } else if (force_cut and line_len >= wrap_width) {
            try result.appendSlice(break_chars);
            line_len = 0;
        }
        i += 1;
    }

    // 输出剩余单词
    if (i > word_start) {
        const word = input[word_start..i];
        if (line_len + word.len > wrap_width and line_len > 0) {
            try result.appendSlice(break_chars);
        }
        try result.appendSlice(word);
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

pub fn php_printf(format: Value, args: []const Value, allocator: Allocator) !Value {
    const out = try php_sprintf(format, args, allocator);
    defer out.release(allocator);
    try php_echo(out);
    if (out.isString()) return Value.initInt(@intCast(out.asString().length));
    return Value.initInt(0);
}

pub fn php_bin2hex(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;
    const input = str.asString().data;
    const hex_len = input.len * 2;
    const hex_str = try allocator.alloc(u8, hex_len);
    defer allocator.free(hex_str);

    const hex_chars = "0123456789abcdef";
    for (input, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, hex_str);
    return Value.initString(php_str);
}

/// decbin - 十进制转二进制
pub fn php_decbin(num: Value, allocator: Allocator) !Value {
    const n = if (num.isInt()) num.asInt() else @as(i64, @intFromFloat(num.asFloat()));
    if (n == 0) {
        const php_str = try PHPString.init(allocator, "0");
        return Value.initString(php_str);
    }

    var abs_n: u64 = if (n < 0) @intCast(-n) else @intCast(n);
    var buf: [64]u8 = undefined;
    var len: usize = 0;

    while (abs_n > 0) : (abs_n >>= 1) {
        buf[63 - len] = if (abs_n & 1 == 1) '1' else '0';
        len += 1;
    }

    const result = buf[64 - len ..];
    const php_str = try PHPString.init(allocator, result);
    return Value.initString(php_str);
}

fn hexCharToInt(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

pub fn php_hex2bin(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;
    const input = str.asString().data;
    if (input.len % 2 != 0) return Value.initBool(false);

    const bin_len = input.len / 2;
    const bin_str = try allocator.alloc(u8, bin_len);
    defer allocator.free(bin_str);

    for (0..bin_len) |i| {
        const high = hexCharToInt(input[i * 2]) orelse return Value.initBool(false);
        const low = hexCharToInt(input[i * 2 + 1]) orelse return Value.initBool(false);
        bin_str[i] = (high << 4) | low;
    }

    const php_str = try PHPString.init(allocator, bin_str);
    return Value.initString(php_str);
}

// ============================================================================
// 哈希函数
// ============================================================================

/// md5 - 计算字符串的MD5哈希值
pub fn php_md5(str: Value, raw_output: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(input, &hash, .{});

    if (raw_output.toBool()) {
        const php_str = try PHPString.init(allocator, &hash);
        return Value.initString(php_str);
    }

    // 转换为十六进制字符串
    var hex_str: [32]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

/// sha1 - 计算字符串的SHA1哈希值
pub fn php_sha1(str: Value, raw_output: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(input, &hash, .{});

    if (raw_output.toBool()) {
        const php_str = try PHPString.init(allocator, &hash);
        return Value.initString(php_str);
    }

    // 转换为十六进制字符串
    var hex_str: [40]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

/// password_hash - 创建密码哈希
/// 使用bcrypt算法 (PASSWORD_DEFAULT = PASSWORD_BCRYPT = 1)
/// 签名: password_hash(password, algo, options = []) — options忽略，使用默认cost
pub fn php_password_hash(password: Value, algo: Value, allocator: Allocator) !Value {
    if (!password.isString()) return error.InvalidArgument;
    
    const pwd = password.asString().data;
    const algo_val = algo.toInt();
    
    // 使用默认cost=12
    const cost: u6 = 12;
    
    // 使用bcrypt (algo=1 是 PASSWORD_BCRYPT)
    if (algo_val == 1 or algo_val == 0) { // 0 = PASSWORD_DEFAULT
        var hash_buf: [128]u8 = undefined;
        const hash_result = try std.crypto.pwhash.bcrypt.strHash(pwd, .{
            .allocator = allocator,
            .params = .{ .rounds_log = cost, .silently_truncate_password = true },
            .encoding = .crypt,
        }, &hash_buf);
        
        // Zig生成$2b$前缀，PHP使用$2y$前缀，替换以保持兼容
        var result_buf: [128]u8 = undefined;
        const result_str = blk: {
            if (hash_result.len >= 4 and hash_result[0] == '$' and hash_result[1] == '2' and hash_result[2] == 'b' and hash_result[3] == '$') {
                result_buf[0] = '$';
                result_buf[1] = '2';
                result_buf[2] = 'y';
                @memcpy(result_buf[3..hash_result.len], hash_result[3..]);
                break :blk result_buf[0..hash_result.len];
            }
            break :blk hash_result;
        };
        
        const php_str = try PHPString.init(allocator, result_str);
        return Value.initString(php_str);
    }
    
    return error.InvalidArgument;
}

/// password_verify - 验证密码是否匹配哈希
pub fn php_password_verify(password: Value, hash: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!password.isString() or !hash.isString()) {
        return Value.initBool(false);
    }
    
    const pwd = password.asString().data;
    const hash_str = hash.asString().data;
    
    // PHP使用$2y$前缀，Zig期望$2b$前缀，需要转换
    var converted_buf: [128]u8 = undefined;
    const verify_str = blk: {
        if (hash_str.len >= 4 and hash_str[0] == '$' and hash_str[1] == '2' and hash_str[2] == 'y' and hash_str[3] == '$') {
            converted_buf[0] = '$';
            converted_buf[1] = '2';
            converted_buf[2] = 'b';
            if (hash_str.len <= converted_buf.len) {
                @memcpy(converted_buf[3..hash_str.len], hash_str[3..]);
                break :blk converted_buf[0..hash_str.len];
            }
        }
        break :blk hash_str;
    };
    
    // 使用bcrypt验证
    std.crypto.pwhash.bcrypt.strVerify(verify_str, pwd, .{
        .silently_truncate_password = true,
    }) catch {
        return Value.initBool(false);
    };
    
    return Value.initBool(true);
}

/// password_get_info - 返回密码哈希的相关信息
pub fn php_password_get_info(hash_val: Value, allocator: Allocator) !Value {
    if (!hash_val.isString()) {
        // 返回未知算法的空info
        const arr = try PHPArray.init(allocator);
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algo")), Value.initNull());
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algoName")), Value.initString(try PHPString.init(allocator, "unknown")));
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "options")), Value.initArray(try PHPArray.init(allocator)));
        return Value.initArray(arr);
    }

    const hash_str = hash_val.asString().data;

    // 检测bcrypt格式: $2y$XX$ 或 $2b$XX$ 或 $2a$XX$
    if (hash_str.len >= 7 and hash_str[0] == '$' and hash_str[1] == '2' and
        (hash_str[2] == 'y' or hash_str[2] == 'b' or hash_str[2] == 'a') and hash_str[3] == '$')
    {
        // 提取cost值: $2y$XX$...
        const cost_str = hash_str[4..6];
        var cost: i64 = 0;
        for (cost_str) |c| {
            if (c >= '0' and c <= '9') {
                cost = cost * 10 + @as(i64, c - '0');
            }
        }

        const options_arr = try PHPArray.init(allocator);
        try options_arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "cost")), Value.initInt(cost));

        const arr = try PHPArray.init(allocator);
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algo")), Value.initString(try PHPString.init(allocator, "2y")));
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algoName")), Value.initString(try PHPString.init(allocator, "bcrypt")));
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "options")), Value.initArray(options_arr));
        return Value.initArray(arr);
    }

    // 未知算法
    const arr = try PHPArray.init(allocator);
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algo")), Value.initNull());
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algoName")), Value.initString(try PHPString.init(allocator, "unknown")));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "options")), Value.initArray(try PHPArray.init(allocator)));
    return Value.initArray(arr);
}

/// password_needs_rehash - 检查哈希是否需要重新生成
/// password_needs_rehash(hash, algo, options=[])
pub fn php_password_needs_rehash(hash_val: Value, algo: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!hash_val.isString()) return Value.initBool(true);

    const hash_str = hash_val.asString().data;
    const algo_val = algo.toInt();

    // PASSWORD_DEFAULT(0) 和 PASSWORD_BCRYPT(1) 都使用bcrypt
    if (algo_val == 0 or algo_val == 1) {
        // 检查是否是bcrypt格式
        if (hash_str.len >= 7 and hash_str[0] == '$' and hash_str[1] == '2' and
            (hash_str[2] == 'y' or hash_str[2] == 'b' or hash_str[2] == 'a') and hash_str[3] == '$')
        {
            // 提取cost值
            var cost: i64 = 0;
            if (hash_str[4] >= '0' and hash_str[4] <= '9') cost = cost * 10 + @as(i64, hash_str[4] - '0');
            if (hash_str[5] >= '0' and hash_str[5] <= '9') cost = cost * 10 + @as(i64, hash_str[5] - '0');
            // 默认cost=12，如果匹配则不需要rehash
            return Value.initBool(cost != 12);
        }
        // 不是bcrypt格式，需要rehash
        return Value.initBool(true);
    }

    return Value.initBool(true);
}

pub fn php_uniqid(prefix: Value, more_entropy: Value, allocator: Allocator) !Value {
    const prefix_str = if (prefix.isString()) prefix.asString().data else "";
    const ent = more_entropy.toBool();

    // PHP uniqid format: prefix + 8 hex chars (seconds) + 5 hex chars (microseconds/100)
    const timestamp = nanoTimestamp();
    const now_us = @divTrunc(timestamp, 1000); // nanoseconds to microseconds
    const seconds = @as(u64, @intCast(@divTrunc(now_us, 1_000_000)));
    const microseconds = @as(u64, @intCast(@rem(now_us, 1_000_000)));
    // PHP uses microseconds/100 for the last 5 hex chars
    const usec_part = @divTrunc(microseconds, 10);

    var result_buf: [64]u8 = undefined;
    const formatted = if (ent) blk: {
        // With more_entropy: add .XXXXXXXX (8 random decimal digits)
        var rand_bytes: [4]u8 = undefined;
        std.crypto.random.bytes(&rand_bytes);
        const rand_val = @as(u32, rand_bytes[0]) * 16777216 + @as(u32, rand_bytes[1]) * 65536 + @as(u32, rand_bytes[2]) * 256 + rand_bytes[3];
        break :blk try std.fmt.bufPrint(&result_buf, "{s}{x}{x:0>5}.{d:0>8}", .{ prefix_str, seconds, usec_part, rand_val % 100000000 });
    } else try std.fmt.bufPrint(&result_buf, "{s}{x}{x:0>5}", .{ prefix_str, seconds, usec_part });

    const php_str = try PHPString.init(allocator, formatted);
    return Value.initString(php_str);
}

/// sha256 - 计算字符串的SHA256哈希值
pub fn php_sha256(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &hash, .{});

    // 转换为十六进制字符串
    var hex_str: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

/// hash - 生成哈希值
pub fn php_hash(algorithm: Value, data: Value, allocator: Allocator) !Value {
    if (!algorithm.isString() or !data.isString()) return Value.initBool(false);

    const algo = algorithm.asString().data;

    const input = data.asString().data;

    if (std.mem.eql(u8, algo, "md5")) {
        return php_md5(data, Value.initBool(false), allocator);
    } else if (std.mem.eql(u8, algo, "sha1")) {
        return php_sha1(data, Value.initBool(false), allocator);
    } else if (std.mem.eql(u8, algo, "sha256")) {
        return php_sha256(data, allocator);
    } else if (std.mem.eql(u8, algo, "sha224")) {
        var hash: [28]u8 = undefined;
        std.crypto.hash.sha2.Sha224.hash(input, &hash, .{});
        var hex_str: [56]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha384")) {
        var hash: [48]u8 = undefined;
        std.crypto.hash.sha2.Sha384.hash(input, &hash, .{});
        var hex_str: [96]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha512")) {
        var hash: [64]u8 = undefined;
        std.crypto.hash.sha2.Sha512.hash(input, &hash, .{});
        var hex_str: [128]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha512/256") or std.mem.eql(u8, algo, "sha512256")) {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha512_256.hash(input, &hash, .{});
        var hex_str: [64]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "crc32") or std.mem.eql(u8, algo, "crc32b")) {
        const crc = std.hash.crc.Crc32.hash(input);
        var hex_buf: [8]u8 = undefined;
        _ = std.fmt.bufPrint(&hex_buf, "{x:0>8}", .{crc}) catch return Value.initBool(false);
        return Value.initString(try PHPString.init(allocator, &hex_buf));
    } else if (std.mem.eql(u8, algo, "adler32")) {
        const adler = std.hash.Adler32.hash(input);
        var hex_buf: [8]u8 = undefined;
        _ = std.fmt.bufPrint(&hex_buf, "{x:0>8}", .{adler}) catch return Value.initBool(false);
        return Value.initString(try PHPString.init(allocator, &hex_buf));
    } else if (std.mem.eql(u8, algo, "ripemd128")) {
        // RIPEMD-128: 使用 MD5 作为基础（简化实现）
        var hash: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(input, &hash, .{});
        var hex_str: [32]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    }

    // PHP hash() 对不支持的算法发出警告并返回 false
    return Value.initBool(false);
}

/// hash_hmac - 生成HMAC哈希
pub fn php_hash_hmac(algorithm: Value, data: Value, key: Value, allocator: Allocator) !Value {
    if (!algorithm.isString() or !data.isString() or !key.isString()) return Value.initBool(false);

    const algo = algorithm.asString().data;
    const input = data.asString().data;
    const key_str = key.asString().data;

    if (std.mem.eql(u8, algo, "sha256")) {
        var hmac = std.crypto.auth.hmac.Hmac(std.crypto.hash.sha2.Sha256).init(key_str);
        hmac.update(input);
        var hash: [32]u8 = undefined;
        hmac.final(&hash);
        var hex_str: [64]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha1")) {
        var hmac = std.crypto.auth.hmac.Hmac(std.crypto.hash.Sha1).init(key_str);
        hmac.update(input);
        var hash: [20]u8 = undefined;
        hmac.final(&hash);
        var hex_str: [40]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "md5")) {
        var hmac = std.crypto.auth.hmac.Hmac(std.crypto.hash.Md5).init(key_str);
        hmac.update(input);
        var hash: [16]u8 = undefined;
        hmac.final(&hash);
        var hex_str: [32]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha512")) {
        var hmac = std.crypto.auth.hmac.Hmac(std.crypto.hash.sha2.Sha512).init(key_str);
        hmac.update(input);
        var hash: [64]u8 = undefined;
        hmac.final(&hash);
        var hex_str: [128]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    }

    return Value.initBool(false);
}

/// hash_equals - 安全比较两个字符串是否相等（防止时序攻击）
pub fn php_hash_equals(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initBool(false);
    
    const s1 = str1.asString().data;
    const s2 = str2.asString().data;
    
    if (s1.len != s2.len) return Value.initBool(false);
    
    // 使用时序安全比较
    var result: u8 = 0;
    for (s1, s2) |c1, c2| {
        result |= c1 ^ c2;
    }
    
    return Value.initBool(result == 0);
}

/// crc32 - 计算字符串的CRC32校验值
pub fn php_crc32(str: Value) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const crc = std.hash.Crc32.hash(input);
    // PHP crc32() 返回有符号32位整数（与C的crc32行为一致）
    const signed: i32 = @bitCast(crc);
    return Value.initInt(@intCast(signed));
}

/// hash_algos - 返回支持的哈希算法列表
pub fn php_hash_algos(allocator: Allocator) !Value {
    const algos = [_][]const u8{
        "md5", "sha1", "sha224", "sha256", "sha384", "sha512",
        "sha512/256", "crc32", "crc32b", "adler32",
    };
    const arr = try PHPArray.init(allocator);
    for (algos) |algo| {
        try arr.push(allocator, Value.initString(try PHPString.init(allocator, algo)));
    }
    return Value.initArray(arr);
}

/// base64_encode - 使用MIME base64编码数据
pub fn php_base64_encode(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const encoder = std.base64.standard;
    const encoded_len = encoder.Encoder.calcSize(input.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded);

    _ = encoder.Encoder.encode(encoded, input);

    const php_str = try PHPString.init(allocator, encoded);
    return Value.initString(php_str);
}

/// base64_decode - 对使用MIME base64编码的数据进行解码
pub fn php_base64_decode(str: Value, strict: Value, allocator: Allocator) !Value {
    _ = strict;
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const decoder = std.base64.standard;

    const decoded_max_len = decoder.Decoder.calcSizeForSlice(input) catch return Value.initBool(false);
    const decoded = try allocator.alloc(u8, decoded_max_len);
    defer allocator.free(decoded);

    decoder.Decoder.decode(decoded, input) catch return Value.initBool(false);

    const php_str = try PHPString.init(allocator, decoded[0..decoded_max_len]);
    return Value.initString(php_str);
}

// ============================================================================
// Concurrency Support
// ============================================================================

const CoroutineContext = struct {
    callable: Value,
    args: []Value,
    allocator: Allocator,
};

fn php_coroutine_entry(context: ?*anyopaque) anyerror!void {
    if (context) |ptr| {
        const ctx = @as(*CoroutineContext, @ptrCast(@alignCast(ptr)));
        defer ctx.allocator.destroy(ctx);
        defer ctx.allocator.free(ctx.args);

        // Ensure values are released when we are done
        defer {
            ctx.callable.release(ctx.allocator);
            for (ctx.args) |arg| {
                arg.release(ctx.allocator);
            }
        }

        // Execute the callable
        if (ctx.callable.isString()) {
            const func_name = ctx.callable.asString().data;
            if (user_function_registry) |registry| {
                if (registry.get(func_name)) |func| {
                    _ = func(Value.initNull(), ctx.args, ctx.allocator) catch |err| {
                        if (has_exception) {
                            php_handle_uncaught_exception();
                        }
                        return err;
                    };
                } else {}
            }
        } else if (ctx.callable.isFunction()) {
            const closure = ctx.callable.asFunction();
            _ = closure.func(Value.initFunction(closure), ctx.args, ctx.allocator) catch |err| {
                if (has_exception) {
                    php_handle_uncaught_exception();
                }
                return err;
            };
        }
    }
}

pub fn php_go(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;

    const callable = args[0];

    const coro_args = try allocator.alloc(Value, args.len - 1);
    for (args[1..], 0..) |arg, i| {
        coro_args[i] = arg;
        _ = arg.retain();
    }

    const context = try allocator.create(CoroutineContext);
    context.* = .{
        .callable = callable,
        .args = coro_args,
        .allocator = allocator,
    };
    _ = callable.retain();

    const scheduler = try concurrency.getScheduler(allocator);
    const coro_id = try scheduler.spawn(php_coroutine_entry, context);

    return Value.initInt(@intCast(coro_id));
}

pub fn php_go_wait_all(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    _ = concurrency.drainScheduler(null);
    return Value.initNull();
}

pub fn php_go_join(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len == 0 or args[0].isNull()) {
        _ = concurrency.drainScheduler(null);
        return Value.initNull();
    }
    const id = @as(u64, @intCast(args[0].toInt()));
    const scheduler = try concurrency.getScheduler(runtime_allocator);
    try scheduler.join(id);
    return Value.initNull();
}

pub fn go_spawn(func_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const callable = Value.initString(try PHPString.init(allocator, func_name));
    const full_args = try allocator.alloc(Value, args.len + 1);
    full_args[0] = callable;
    @memcpy(full_args[1..], args);
    defer allocator.free(full_args);

    return php_go(Value.initNull(), full_args, allocator);
}

pub const PHPMutex = struct {
    mutex: std.atomic.Mutex,
    lock_count: std.atomic.Value(u32),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*PHPMutex {
        const self = try allocator.create(PHPMutex);
        self.* = .{
            .mutex = .unlocked,
            .lock_count = std.atomic.Value(u32).init(0),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *PHPMutex) void {
        self.allocator.destroy(self);
    }

    pub fn lock(self: *PHPMutex) void {
        spinLock(&self.mutex);
        _ = self.lock_count.fetchAdd(1, .monotonic);
    }

    pub fn unlock(self: *PHPMutex) void {
        _ = self.lock_count.fetchSub(1, .monotonic);
        self.mutex.unlock();
    }

    pub fn tryLock(self: *PHPMutex) bool {
        if (self.mutex.tryLock()) {
            _ = self.lock_count.fetchAdd(1, .monotonic);
            return true;
        }
        return false;
    }

    pub fn getLockCount(self: *const PHPMutex) u32 {
        return self.lock_count.load(.monotonic);
    }
};

pub const PHPAtomic = struct {
    value: std.atomic.Value(i64),
    allocator: Allocator,

    pub fn init(allocator: Allocator, initial: i64) !*PHPAtomic {
        const self = try allocator.create(PHPAtomic);
        self.* = .{
            .value = std.atomic.Value(i64).init(initial),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *PHPAtomic) void {
        self.allocator.destroy(self);
    }

    pub fn load(self: *const PHPAtomic) i64 {
        return self.value.load(.monotonic);
    }

    pub fn store(self: *PHPAtomic, v: i64) void {
        self.value.store(v, .monotonic);
    }

    pub fn increment(self: *PHPAtomic) i64 {
        return self.value.fetchAdd(1, .monotonic) + 1;
    }

    pub fn decrement(self: *PHPAtomic) i64 {
        return self.value.fetchSub(1, .monotonic) - 1;
    }

    pub fn add(self: *PHPAtomic, delta: i64) i64 {
        return self.value.fetchAdd(delta, .monotonic);
    }

    pub fn sub(self: *PHPAtomic, delta: i64) i64 {
        return self.value.fetchSub(delta, .monotonic);
    }

    pub fn swap(self: *PHPAtomic, new_value: i64) i64 {
        return self.value.swap(new_value, .monotonic);
    }

    pub fn compareAndSwap(self: *PHPAtomic, expected: i64, new_value: i64) bool {
        return self.value.cmpxchgStrong(expected, new_value, .monotonic, .monotonic) == null;
    }
};

pub const PHPRWLock = struct {
    mutex: std.atomic.Mutex,
    readers: std.atomic.Value(i32),
    writer: std.atomic.Value(bool),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*PHPRWLock {
        const self = try allocator.create(PHPRWLock);
        self.* = .{
            .mutex = .unlocked,
            .readers = std.atomic.Value(i32).init(0),
            .writer = std.atomic.Value(bool).init(false),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *PHPRWLock) void {
        self.allocator.destroy(self);
    }

    pub fn lockRead(self: *PHPRWLock) void {
        spinLock(&self.mutex);
        _ = self.readers.fetchAdd(1, .monotonic);
        self.mutex.unlock();
    }

    pub fn unlockRead(self: *PHPRWLock) void {
        spinLock(&self.mutex);
        _ = self.readers.fetchSub(1, .monotonic);
        self.mutex.unlock();
    }

    pub fn lockWrite(self: *PHPRWLock) void {
        spinLock(&self.mutex);
        self.writer.store(true, .monotonic);
    }

    pub fn unlockWrite(self: *PHPRWLock) void {
        self.writer.store(false, .monotonic);
        self.mutex.unlock();
    }

    pub fn getReaderCount(self: *const PHPRWLock) i32 {
        return self.readers.load(.monotonic);
    }

    pub fn getWriterCount(self: *const PHPRWLock) i32 {
        return if (self.writer.load(.monotonic)) 1 else 0;
    }
};

pub const PHPSharedData = struct {
    data: std.StringHashMap([]const u8),
    mutex: std.atomic.Mutex,
    allocator: Allocator,
    access_count: std.atomic.Value(u64),

    pub fn init(allocator: Allocator) !*PHPSharedData {
        const self = try allocator.create(PHPSharedData);
        self.* = .{
            .data = std.StringHashMap([]const u8).init(allocator),
            .mutex = .unlocked,
            .allocator = allocator,
            .access_count = std.atomic.Value(u64).init(0),
        };
        return self;
    }

    pub fn deinit(self: *PHPSharedData) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
        self.allocator.destroy(self);
    }

    pub fn get(self: *PHPSharedData, key: []const u8) ?[]const u8 {
        _ = self.access_count.fetchAdd(1, .monotonic);
        spinLock(&self.mutex);
        defer self.mutex.unlock();
        return self.data.get(key);
    }

    pub fn set(self: *PHPSharedData, key: []const u8, value: []const u8) !void {
        spinLock(&self.mutex);
        defer self.mutex.unlock();

        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }

        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        try self.data.put(key_copy, value_copy);
    }

    pub fn remove(self: *PHPSharedData, key: []const u8) bool {
        spinLock(&self.mutex);
        defer self.mutex.unlock();

        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
            return true;
        }
        return false;
    }

    pub fn has(self: *PHPSharedData, key: []const u8) bool {
        spinLock(&self.mutex);
        defer self.mutex.unlock();
        return self.data.contains(key);
    }

    pub fn size(self: *PHPSharedData) usize {
        spinLock(&self.mutex);
        defer self.mutex.unlock();
        return self.data.count();
    }

    pub fn clear(self: *PHPSharedData) void {
        spinLock(&self.mutex);
        defer self.mutex.unlock();

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.clearRetainingCapacity();
    }

    pub fn getAccessCount(self: *const PHPSharedData) u64 {
        return self.access_count.load(.monotonic);
    }
};

pub fn channel_new(capacity: i64, allocator: Allocator) !Value {
    const obj = try php_object_new("Channel", allocator);
    const channel = try concurrency.Channel(Value).init(allocator, @intCast(capacity));
    const ptr_val = Value.initInt(@intCast(@intFromPtr(channel)));
    try Value_asObject(obj).setProperty("_ptr", ptr_val);
    return obj;
}

pub fn channel_send(ch: Value, val: Value) !void {
    if (!Value_isObject(ch)) return error.InvalidChannel;
    const obj = Value_asObject(ch);
    if (obj.getProperty("_ptr")) |ptr_val| {
        const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        _ = val.retain();
        try channel.send(val);
    }
}

pub fn channel_recv(ch: Value) !Value {
    if (!Value_isObject(ch)) return error.InvalidChannel;
    const obj = Value_asObject(ch);
    if (obj.getProperty("_ptr")) |ptr_val| {
        const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        return channel.recv() catch |err| {
            if (err == error.ChannelClosed) return Value.initNull();
            return err;
        };
    }
    return Value.initNull();
}

pub fn channel_close(ch: Value) void {
    if (!Value_isObject(ch)) return;
    const obj = Value_asObject(ch);
    if (obj.getProperty("_ptr")) |ptr_val| {
        const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        channel.close();
    }
}

fn registerChannelClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                var capacity: usize = 0;
                if (args.len > 0) {
                    capacity = @intCast(args[0].toInt());
                }
                const channel = try concurrency.Channel(Value).init(runtime_alloc, capacity);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(channel)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "send",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (args.len < 1) return error.MissingArgument;

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                const val = args[0];
                _ = val.retain();
                try channel.send(val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "recv",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                return channel.recv() catch |err| {
                    if (err == error.ChannelClosed) return Value.initNull();
                    return err;
                };
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "trySend",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len < 1) return error.MissingArgument;

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                const val = args[0];
                _ = val.retain();
                const ok = channel.trySend(val) catch {
                    val.release(runtime_alloc);
                    return Value.initBool(false);
                };
                if (!ok) {
                    val.release(runtime_alloc);
                }
                return Value.initBool(ok);
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "tryRecv",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                if (channel.tryRecv()) |val| {
                    return val;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "close",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                channel.close();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "isClosed",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initBool(channel.isClosed());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "len",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initInt(@intCast(channel.len()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "capacity",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initInt(@intCast(channel.getCapacity()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                const this = Value_asObject(ctx);

                if (this.getProperty("_ptr")) |ptr_val| {
                    const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    while (channel.tryRecv()) |val| {
                        val.release(runtime_alloc);
                    }
                    channel.deinit();
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerMutexClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                const this = Value_asObject(ctx);
                const m = try PHPMutex.init(runtime_alloc);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(m)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "lock",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
                const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                m.lock();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "unlock",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
                const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                m.unlock();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "tryLock",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
                const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initBool(m.tryLock());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "getLockCount",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
                const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initInt(@intCast(m.getLockCount()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (this.getProperty("_ptr")) |ptr_val| {
                    const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    m.deinit();
                    try this.setProperty("_ptr", Value.initNull());
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerAtomicClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                const initial: i64 = if (args.len > 0) args[0].toInt() else 0;
                const a = try PHPAtomic.init(runtime_alloc, initial);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(a)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    const get_ptr = struct {
        fn ptr(ctx: Value) !*PHPAtomic {
            const this = Value_asObject(ctx);
            const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
            return @as(*PHPAtomic, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        }
    }.ptr;

    try meta.addMethod(.{
        .name = "load",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const a = try get_ptr(ctx);
                return Value.initInt(a.load());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "store",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                const a = try get_ptr(ctx);
                a.store(args[0].toInt());
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "increment",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const a = try get_ptr(ctx);
                return Value.initInt(a.increment());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "decrement",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const a = try get_ptr(ctx);
                return Value.initInt(a.decrement());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "add",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                const a = try get_ptr(ctx);
                return Value.initInt(a.add(args[0].toInt()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "sub",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                const a = try get_ptr(ctx);
                return Value.initInt(a.sub(args[0].toInt()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "swap",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                const a = try get_ptr(ctx);
                return Value.initInt(a.swap(args[0].toInt()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "compareAndSwap",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 2) return error.MissingArgument;
                const a = try get_ptr(ctx);
                return Value.initBool(a.compareAndSwap(args[0].toInt(), args[1].toInt()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (this.getProperty("_ptr")) |ptr_val| {
                    const a = @as(*PHPAtomic, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    a.deinit();
                    try this.setProperty("_ptr", Value.initNull());
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerRWLockClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                const this = Value_asObject(ctx);
                const l = try PHPRWLock.init(runtime_alloc);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(l)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    const get_ptr = struct {
        fn ptr(ctx: Value) !*PHPRWLock {
            const this = Value_asObject(ctx);
            const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
            return @as(*PHPRWLock, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        }
    }.ptr;

    try meta.addMethod(.{
        .name = "lockRead",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                l.lockRead();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "unlockRead",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                l.unlockRead();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "lockWrite",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                l.lockWrite();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "unlockWrite",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                l.unlockWrite();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "getReaderCount",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                return Value.initInt(@intCast(l.getReaderCount()));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "getWriterCount",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                return Value.initInt(@intCast(l.getWriterCount()));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (this.getProperty("_ptr")) |ptr_val| {
                    const l = @as(*PHPRWLock, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    l.deinit();
                    try this.setProperty("_ptr", Value.initNull());
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerSharedDataClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                const this = Value_asObject(ctx);
                const s = try PHPSharedData.init(runtime_alloc);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(s)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    const get_ptr = struct {
        fn ptr(ctx: Value) !*PHPSharedData {
            const this = Value_asObject(ctx);
            const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
            return @as(*PHPSharedData, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        }
    }.ptr;

    try meta.addMethod(.{
        .name = "set",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                if (args.len < 2) return error.MissingArgument;
                if (!args[0].isString()) return error.InvalidArgument;
                const s = try get_ptr(ctx);
                const key = args[0].asString().data;
                const val_str = if (args[1].isString()) args[1] else try php_strval(args[1], runtime_alloc);
                defer if (!args[1].isString()) val_str.release(runtime_alloc);
                try s.set(key, val_str.asString().data);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "get",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                if (args.len < 1) return error.MissingArgument;
                if (!args[0].isString()) return error.InvalidArgument;
                const s = try get_ptr(ctx);
                const key = args[0].asString().data;
                if (s.get(key)) |val| {
                    return Value.initString(try PHPString.init(runtime_alloc, val));
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "remove",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                if (!args[0].isString()) return error.InvalidArgument;
                const s = try get_ptr(ctx);
                const key = args[0].asString().data;
                return Value.initBool(s.remove(key));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "has",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                if (!args[0].isString()) return error.InvalidArgument;
                const s = try get_ptr(ctx);
                const key = args[0].asString().data;
                return Value.initBool(s.has(key));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "size",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const s = try get_ptr(ctx);
                return Value.initInt(@intCast(s.size()));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "clear",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const s = try get_ptr(ctx);
                s.clear();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "getAccessCount",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const s = try get_ptr(ctx);
                return Value.initInt(@intCast(s.getAccessCount()));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (this.getProperty("_ptr")) |ptr_val| {
                    const s = @as(*PHPSharedData, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    s.deinit();
                    try this.setProperty("_ptr", Value.initNull());
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerZigChannel(allocator: Allocator) !void {
    try registerChannelClassNamed(allocator, "Channel");
    try registerChannelClassNamed(allocator, "Zig\\Channel");
    try registerMutexClassNamed(allocator, "Mutex");
    try registerMutexClassNamed(allocator, "Zig\\Mutex");
    try registerAtomicClassNamed(allocator, "Atomic");
    try registerAtomicClassNamed(allocator, "Zig\\Atomic");
    try registerRWLockClassNamed(allocator, "RWLock");
    try registerRWLockClassNamed(allocator, "Zig\\RWLock");
    try registerSharedDataClassNamed(allocator, "SharedData");
    try registerSharedDataClassNamed(allocator, "Zig\\SharedData");
    try registerUserFunction("go", php_go);
    try registerUserFunction("go_wait_all", php_go_wait_all);
    try registerUserFunction("go_join", php_go_join);
}

fn registerZigSelect(allocator: Allocator) !void {
    const meta = try ClassMeta.init(allocator, "Zig\\Select");

    try meta.addMethod(.{
        .name = "select",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = ctx;
                if (args.len < 1) return error.MissingArgument;
                const cases_arg = args[0];
                if (!cases_arg.isArray()) return error.InvalidArgument;

                var timeout: ?i64 = null;
                if (args.len > 1 and !args[1].isNull()) {
                    timeout = args[1].toInt();
                }

                const array = cases_arg.asArray();
                const start_time = milliTimestamp();

                while (true) {
                    var iter = array.elements.iterator();
                    var index: usize = 0;
                    while (iter.next()) |entry| : (index += 1) {
                        const case_val = entry.value_ptr.*;
                        if (!case_val.isArray()) continue;

                        const case_arr = case_val.asArray();

                        // [channel, op, ?value]
                        const ch_val = case_arr.get(ArrayKey{ .integer = 0 }) orelse continue;
                        const op_val = case_arr.get(ArrayKey{ .integer = 1 }) orelse continue;

                        if (!Value_isObject(ch_val)) continue;
                        const ch_obj = Value_asObject(ch_val);
                        if (ch_obj.getProperty("_ptr")) |ptr_val| {
                            const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                            const op = op_val.toInt(); // 0=recv, 1=send

                            if (op == 0) { // recv
                                if (channel.tryRecv()) |val| {
                                    // Return array [index, value]
                                    const res_arr = try PHPArray.init(runtime_alloc);
                                    try res_arr.push(runtime_alloc, Value.initInt(@intCast(index)));
                                    try res_arr.push(runtime_alloc, val);
                                    return Value.initArray(res_arr);
                                }
                            } else if (op == 1) { // send
                                const send_val = case_arr.get(ArrayKey{ .integer = 2 }) orelse Value.initNull();
                                _ = send_val.retain();
                                const ok = channel.trySend(send_val) catch {
                                    send_val.release(runtime_alloc);
                                    continue;
                                };
                                if (ok) {
                                    return Value.initInt(@intCast(index));
                                }
                                send_val.release(runtime_alloc);
                            }
                        }
                    }

                    if (timeout) |t| {
                        if (milliTimestamp() - start_time >= t) {
                            return Value.initNull();
                        }
                    }

                    std.Thread.yield() catch {};
                }
            }
        }.call,
        .is_static = true,
    });

    try registerClass(meta);
}

pub fn php_go_builtin(callable: Value, allocator: Allocator) !Value {
    const args = [_]Value{callable};
    return php_go(Value.initNull(), &args, allocator);
}

/// array_count_values() - 统计数组中所有值出现的次数
pub fn php_array_count_values(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const val = entry.value_ptr.*;

        // 只支持整数和字符串作为键
        const key: ArrayKey = if (val.isInt())
            .{ .integer = val.asInt() }
        else if (val.isString())
            .{ .string = val.asString() }
        else
            continue;

        // 获取或初始化计数
        if (result.elements.get(key)) |count_val| {
            try result.set(allocator, key, Value.initInt(count_val.asInt() + 1));
        } else {
            try result.set(allocator, key, Value.initInt(1));
        }
    }

    return Value.initArray(result);
}

/// array_rand() - 从数组中随机选择一个或多个键
pub fn php_array_rand(arr: Value, num: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const count = php_arr.elements.count();
    if (count == 0) return Value.initNull();

    const n = if (num.isInt()) @as(usize, @intCast(@max(1, num.asInt()))) else 1;

    if (n == 1) {
        // 返回单个键
        const idx = @as(usize, @intCast(std.crypto.random.intRangeAtMost(i64, 0, @as(i64, @intCast(count - 1)))));
        var iter = php_arr.elements.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            if (i == idx) {
                return switch (entry.key_ptr.*) {
                    .integer => |int| Value.initInt(int),
                    .string => |str| Value.initString(str),
                };
            }
        }
        return Value.initNull();
    }

    // 返回多个键（简化实现）
    return Value.initNull();
}

/// shuffle() - 随机打乱数组
pub fn php_shuffle(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const count = php_arr.elements.count();
    if (count <= 1) return Value.initBool(true);

    // Fisher-Yates shuffle
    var values = try allocator.alloc(Value, count);
    defer allocator.free(values);

    var iter = php_arr.elements.iterator();
    var i: usize = 0;
    while (iter.next()) |entry| : (i += 1) {
        values[i] = entry.value_ptr.*;
    }

    i = count;
    while (i > 1) {
        i -= 1;
        const j = @as(usize, @intCast(std.crypto.random.intRangeAtMost(i64, 0, @as(i64, @intCast(i)))));
        const temp = values[i];
        values[i] = values[j];
        values[j] = temp;
    }

    // 重建数组
    php_arr.elements.packed_values.clearRetainingCapacity();
    if (php_arr.elements.mixed) |*mixed| {
        mixed.clearRetainingCapacity();
    }

    for (values, 0..) |val, idx| {
        try php_arr.push(allocator, val);
        _ = idx;
    }

    return Value.initBool(true);
}

/// compact() - 创建包含变量及其值的数组
pub fn php_compact(varnames: []const Value, allocator: Allocator) !Value {
    _ = varnames;
    // 简化实现：返回空数组
    const result = try PHPArray.init(allocator);
    return Value.initArray(result);
}

/// extract() - 从数组中将变量导入到当前符号表
/// 注意：AOT模式下extract()的实现受限，因为变量名在编译时未知
/// 完整实现需要运行时符号表支持
pub fn php_extract(arr: Value, flags: Value, prefix: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initInt(0);
    
    const extract_flags = if (flags.isInt()) flags.asInt() else 0;
    const prefix_str = if (prefix.isString()) prefix.asString().data else "";
    
    _ = extract_flags;
    _ = prefix_str;
    _ = allocator;
    
    // AOT模式限制：
    // extract()需要动态创建变量，但AOT编译时变量名已固定
    // 完整实现需要：
    // 1. 运行时符号表（symbol table）
    // 2. 动态变量创建机制
    // 3. 作用域管理
    //
    // 当前返回数组元素数量，表示"提取"的变量数
    // 实际变量创建由编译器在IR层面处理
    const arr_obj = arr.asArray();
    return Value.initInt(@intCast(arr_obj.elements.count()));
}

/// array_fill_keys() - 使用指定的键和值填充数组
pub fn php_array_fill_keys(keys: Value, value: Value, allocator: Allocator) !Value {
    if (!keys.isArray()) return error.InvalidArgument;

    const keys_arr = keys.asArray();
    const result = try PHPArray.init(allocator);

    var iter = keys_arr.elements.iterator();
    while (iter.next()) |entry| {
        const key_val = entry.value_ptr.*;
        const key: ArrayKey = if (key_val.isInt())
            .{ .integer = key_val.asInt() }
        else if (key_val.isString())
            .{ .string = key_val.asString() }
        else
            continue;

        try result.set(allocator, key, value);
    }

    return Value.initArray(result);
}

/// natsort() - 用自然排序算法对数组排序
pub fn php_natsort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;
    const php_arr = arr.asArray();

    const Entry = struct { key: ArrayKey, val: Value };
    var entries = std.ArrayListUnmanaged(Entry){ .items = &.{}, .capacity = 0 };
    defer entries.deinit(allocator);
    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        try entries.append(allocator, .{ .key = entry.key_ptr.*, .val = entry.value_ptr.* });
    }

    const Ctx = struct {
        fn natcmp(a: []const u8, b: []const u8) bool {
            var i: usize = 0;
            var j: usize = 0;
            while (i < a.len and j < b.len) {
                const ac = a[i];
                const bc = b[j];
                if (std.ascii.isDigit(ac) and std.ascii.isDigit(bc)) {
                    var an: u64 = 0;
                    var bn: u64 = 0;
                    while (i < a.len and std.ascii.isDigit(a[i])) : (i += 1) an = an * 10 + (a[i] - '0');
                    while (j < b.len and std.ascii.isDigit(b[j])) : (j += 1) bn = bn * 10 + (b[j] - '0');
                    if (an != bn) return an < bn;
                } else {
                    if (ac != bc) return ac < bc;
                    i += 1;
                    j += 1;
                }
            }
            return a.len < b.len;
        }
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            const as = if (a.val.isString()) a.val.asString().data else "";
            const bs = if (b.val.isString()) b.val.asString().data else "";
            return natcmp(as, bs);
        }
    };
    std.sort.pdq(Entry, entries.items, {}, Ctx.lessThan);

    // 强制转为mixed map并重排
    try php_arr.elements.convertToMixed();
    if (php_arr.elements.mixed) |*m| {
        m.clearRetainingCapacity();
        for (entries.items) |entry| {
            try m.put(entry.key, entry.val);
        }
    }
    return Value.initBool(true);
}

/// 静态变量访问函数
pub fn getStaticVar(func_name_val: Value, var_name_val: Value) !Value {
    const func_name = if (func_name_val.isString()) func_name_val.asString().data else "global";
    const var_name = if (var_name_val.isString()) var_name_val.asString().data else "";

    static_vars_mutex.lock();
    defer static_vars_mutex.unlock();

    if (static_vars == null) return Value.initNull();

    // 构造键：函数名::变量名
    const key = try std.fmt.allocPrint(runtime_allocator, "{s}::{s}", .{ func_name, var_name });
    defer runtime_allocator.free(key);

    return static_vars.?.get(key) orelse Value.initNull();
}

pub fn setStaticVar(func_name_val: Value, var_name_val: Value, value: Value) !Value {
    const func_name = if (func_name_val.isString()) func_name_val.asString().data else "global";
    const var_name = if (var_name_val.isString()) var_name_val.asString().data else "";

    static_vars_mutex.lock();
    defer static_vars_mutex.unlock();

    if (static_vars == null) return Value.initNull();

    // 构造键：函数名::变量名
    const key = try runtime_allocator.dupe(u8, try std.fmt.allocPrint(runtime_allocator, "{s}::{s}", .{ func_name, var_name }));

    try static_vars.?.put(key, value);
    return value;
}

