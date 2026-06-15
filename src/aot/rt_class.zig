const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

// ============================================================================
// 字符串插值函数
// ============================================================================

/// php_interpolate - 字符串插值（将多个值连接成字符串）
///
/// 这个函数接收一个Value数组，将每个值转换为字符串并连接起来。
/// 这是PHP字符串插值的核心实现，例如：
/// ```php
/// $name = "Alice";
/// $age = 30;
/// echo "Hello, $name! You are $age years old.";
/// ```
///
/// @param parts 要插值的值数组
/// @param allocator 内存分配器
/// @return 插值后的字符串Value
pub fn php_interpolate(parts: []const Value, allocator: Allocator) !Value {
    if (parts.len == 0) {
        // 空数组，返回空字符串
        return Value.initString(try PHPString.init(allocator, ""));
    }

    if (parts.len == 1) {
        // 单个值，直接转换为字符串
        const str = try parts[0].toString(allocator);
        return Value.initString(str);
    }

    // 多个值，需要连接
    // 首先计算总长度
    var total_length: usize = 0;
    var temp_strings = try allocator.alloc(*PHPString, parts.len);
    defer {
        // 释放临时字符串
        for (temp_strings) |str| {
            str.release(allocator);
        }
        allocator.free(temp_strings);
    }

    // 将每个值转换为字符串
    for (parts, 0..) |part, i| {
        const str = try part.toString(allocator);
        temp_strings[i] = str;
        total_length += str.length;
    }

    // 分配结果缓冲区
    const result_data = try allocator.alloc(u8, total_length);
    errdefer allocator.free(result_data);

    // 连接所有字符串
    var offset: usize = 0;
    for (temp_strings) |str| {
        if (str.length > 0) {
            @memcpy(result_data[offset .. offset + str.length], str.data[0..str.length]);
            offset += str.length;
        }
    }

    // 创建结果字符串
    const result = try allocator.create(PHPString);
    errdefer allocator.destroy(result);

    result.data = result_data;
    result.length = total_length;
    result.ref_count = 1;
    result.is_static = false;

    return Value.initString(result);
}

// ============================================================================
// PHP类元数据和对象类型
// ============================================================================

/// 方法签名类型
pub const MethodFn = *const fn (this: Value, args: []const Value, allocator: Allocator) anyerror!Value;

/// 类方法定义
pub const ClassMethod = struct {
    name: []const u8,
    func: MethodFn,
    is_static: bool = false,
    is_public: bool = true,
    is_protected: bool = false,
    is_private: bool = false,
    is_abstract: bool = false,
    is_final: bool = false,
    param_count: u16 = 0,
    required_params: u16 = 0,
    param_names: []const []const u8 = &.{},
    /// 参数类型字符串列表，与 param_names 一一对应（无类型声明时为空字符串）
    param_types: []const []const u8 = &.{},
    /// 参数是否允许 null（nullable 类型或无类型声明）
    param_nullable: []const bool = &.{},
    /// 返回类型字符串（无返回类型声明时为 null）
    return_type: ?[]const u8 = null,
    /// 返回类型是否 nullable
    return_nullable: bool = false,
};

/// 类属性定义
pub const ClassProperty = struct {
    name: []const u8,
    default_value: ?Value = null,
    is_static: bool = false,
    is_public: bool = true,
    is_protected: bool = false,
    is_private: bool = false,
    is_readonly: bool = false,
    /// 属性类型字符串（无类型声明时为 null）
    type_name: ?[]const u8 = null,
    /// 属性类型是否 nullable
    type_nullable: bool = false,
    /// 是否有默认值（class body 中声明了默认值）
    has_default: bool = false,
};

/// 类元数据
/// 存储类的完整定义，包括方法、属性、继承关系、接口等
pub const ClassMeta = struct {
    name: []const u8,
    parent: ?*const ClassMeta = null,
    interfaces: []const []const u8 = &.{},
    methods: std.StringHashMap(ClassMethod),
    properties: std.StringHashMap(ClassProperty),
    static_properties: std.StringHashMap(Value),
    is_abstract: bool = false,
    is_final: bool = false,
    is_interface: bool = false,  // 是否为接口
    is_trait: bool = false,      // 是否为trait
    is_enum: bool = false,       // 是否为enum
    allocator: Allocator,

    /// 魔法函数指针
    magic_construct: ?MethodFn = null,
    magic_destruct: ?MethodFn = null,
    magic_call: ?MethodFn = null,
    magic_callStatic: ?MethodFn = null,
    magic_get: ?MethodFn = null,
    magic_set: ?MethodFn = null,
    magic_isset: ?MethodFn = null,
    magic_unset: ?MethodFn = null,
    magic_toString: ?MethodFn = null,
    magic_invoke: ?MethodFn = null,
    magic_clone: ?MethodFn = null,
    magic_sleep: ?MethodFn = null,
    magic_wakeup: ?MethodFn = null,
    magic_serialize: ?MethodFn = null,
    magic_unserialize: ?MethodFn = null,

    pub fn init(allocator: Allocator, name: []const u8) !*ClassMeta {
        const meta = try allocator.create(ClassMeta);
        errdefer allocator.destroy(meta);

        meta.* = .{
            .name = try allocator.dupe(u8, name),
            .methods = std.StringHashMap(ClassMethod).init(allocator),
            .properties = std.StringHashMap(ClassProperty).init(allocator),
            .static_properties = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
        return meta;
    }

    pub fn deinit(self: *ClassMeta) void {
        // 先释放静态属性（可能包含对象引用）
        var iter = self.static_properties.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.static_properties.deinit();

        // 再释放其他资源
        self.methods.deinit();
        self.properties.deinit();
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    /// 添加方法
    pub fn addMethod(self: *ClassMeta, method: ClassMethod) !void {
        try self.methods.put(method.name, method);
        if (std.mem.eql(u8, method.name, "__construct")) self.magic_construct = method.func;
        if (std.mem.eql(u8, method.name, "__destruct")) self.magic_destruct = method.func;
        if (std.mem.eql(u8, method.name, "__get")) self.magic_get = method.func;
        if (std.mem.eql(u8, method.name, "__set")) self.magic_set = method.func;
        if (std.mem.eql(u8, method.name, "__isset")) self.magic_isset = method.func;
        if (std.mem.eql(u8, method.name, "__unset")) self.magic_unset = method.func;
        if (std.mem.eql(u8, method.name, "__call")) self.magic_call = method.func;
        if (std.mem.eql(u8, method.name, "__callStatic")) self.magic_callStatic = method.func;
        if (std.mem.eql(u8, method.name, "__toString")) self.magic_toString = method.func;
        if (std.mem.eql(u8, method.name, "__invoke")) self.magic_invoke = method.func;
        if (std.mem.eql(u8, method.name, "__clone")) self.magic_clone = method.func;
        if (std.mem.eql(u8, method.name, "__sleep")) self.magic_sleep = method.func;
        if (std.mem.eql(u8, method.name, "__wakeup")) self.magic_wakeup = method.func;
        if (std.mem.eql(u8, method.name, "__serialize")) self.magic_serialize = method.func;
        if (std.mem.eql(u8, method.name, "__unserialize")) self.magic_unserialize = method.func;
    }

    pub const MethodLookup = struct {
        owner: *const ClassMeta,
        method: *const ClassMethod,
    };

    pub fn findMethodLookup(self: *const ClassMeta, name: []const u8) ?MethodLookup {
        if (self.methods.getPtr(name)) |method| {
            return .{ .owner = self, .method = method };
        }
        if (self.parent) |parent| {
            return parent.findMethodLookup(name);
        }
        return null;
    }

    /// 查找方法（包括继承链）
    pub fn findMethod(self: *const ClassMeta, name: []const u8) ?ClassMethod {
        if (self.methods.get(name)) |method| {
            return method;
        }
        if (self.parent) |parent| {
            return parent.findMethod(name);
        }
        return null;
    }

    // ========================================================================
    // DateTime 扩展格式化函数 - 支持完整的 PHP date() 格式
    // ========================================================================

    /// 完整的DateTime格式化器，支持时区偏移
    const DateTimeFormatter = struct {
        timestamp: i64,
        microseconds: i64,
        timezone_offset: i32,
        timezone_name: []const u8,

        fn isLeapYear(year: i64) bool {
            return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
        }

        fn getDaysInMonth(year: i64, month: u32) u32 {
            return switch (month) {
                1, 3, 5, 7, 8, 10, 12 => 31,
                4, 6, 9, 11 => 30,
                2 => if (isLeapYear(year)) 29 else 28,
                else => 31,
            };
        }

        fn getDayOfYear(year: i64, month: u32, day: u32) u32 {
            var doy: u32 = 0;
            var m: u32 = 1;
            while (m < month) : (m += 1) doy += getDaysInMonth(year, m);
            return doy + day;
        }

        fn getDayOfWeek(year: i64, month: u32, day: u32) u32 {
            const y = if (month < 3) year - 1 else year;
            const m = if (month < 3) month + 12 else month;
            const w = @mod(day + @divFloor(13 * (m + 1), 5) + y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400), 7);
            return @intCast(w);
        }

        fn getIsoWeek(year: i64, month: u32, day: u32) u32 {
            const doy = getDayOfYear(year, month, day);
            const wday = getDayOfWeek(year, month, day);
            const iso_wday = if (wday == 0) @as(i64, 7) else @as(i64, wday);
            var week = @divFloor(@as(i64, doy) - iso_wday + 10, 7);
            if (week < 1) week = if (isLeapYear(year - 1)) 53 else 52
            else if (week > 52 and doy - iso_wday > 365 - (if (isLeapYear(year)) @as(i64, 1) else @as(i64, 0))) week = 1;
            return @intCast(week);
        }

        pub fn format(self: *const DateTimeFormatter, format_str: []const u8, allocator: Allocator) !Value {
            const epoch_seconds: u64 = @intCast(@max(@as(i64, 0), self.timestamp));
            const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
            const day_seconds = epoch.getDaySeconds();
            const year_day = epoch.getEpochDay().calculateYearDay();
            const month_day = year_day.calculateMonthDay();

            const year = year_day.year;
            const month = month_day.month.numeric();
            const day = month_day.day_index + 1;
            const hour = day_seconds.getHoursIntoDay();
            const minute = day_seconds.getMinutesIntoHour();
            const second = day_seconds.getSecondsIntoMinute();

            var aw = std.Io.Writer.Allocating.initCapacity(allocator, format_str.len * 3) catch return Value.initNull();
            defer aw.deinit();

            var i: usize = 0;
            while (i < format_str.len) : (i += 1) {
                const c = format_str[i];
                switch (c) {
                    'Y' => try aw.writer.print("{d:0>4}", .{year}),
                    'y' => try aw.writer.print("{d:0>2}", .{year % 100}),
                    'L' => try aw.writer.print("{d}", .{if (isLeapYear(year)) @as(u32, 1) else @as(u32, 0)}),
                    'm' => try aw.writer.print("{d:0>2}", .{month}),
                    'n' => try aw.writer.print("{d}", .{month}),
                    'F' => try aw.writer.writeAll(switch (month) { 1=>"January", 2=>"February", 3=>"March", 4=>"April", 5=>"May", 6=>"June", 7=>"July", 8=>"August", 9=>"September", 10=>"October", 11=>"November", 12=>"December", else=>"Unknown" }),
                    'M' => try aw.writer.writeAll(switch (month) { 1=>"Jan", 2=>"Feb", 3=>"Mar", 4=>"Apr", 5=>"May", 6=>"Jun", 7=>"Jul", 8=>"Aug", 9=>"Sep", 10=>"Oct", 11=>"Nov", 12=>"Dec", else=>"???" }),
                    't' => try aw.writer.print("{d}", .{getDaysInMonth(year, month)}),
                    'd' => try aw.writer.print("{d:0>2}", .{day}),
                    'j' => try aw.writer.print("{d}", .{day}),
                    'S' => try aw.writer.writeAll(if (day >= 11 and day <= 13) "th" else switch (day % 10) { 1=>"st", 2=>"nd", 3=>"rd", else=>"th" }),
                    'z' => try aw.writer.print("{d}", .{getDayOfYear(year, month, day) - 1}),
                    'l' => try aw.writer.writeAll(switch (getDayOfWeek(year, month, day)) { 0=>"Sunday", 1=>"Monday", 2=>"Tuesday", 3=>"Wednesday", 4=>"Thursday", 5=>"Friday", 6=>"Saturday", else=>"Unknown" }),
                    'D' => try aw.writer.writeAll(switch (getDayOfWeek(year, month, day)) { 0=>"Sun", 1=>"Mon", 2=>"Tue", 3=>"Wed", 4=>"Thu", 5=>"Fri", 6=>"Sat", else=>"???" }),
                    'w' => try aw.writer.print("{d}", .{getDayOfWeek(year, month, day)}),
                    'N' => { const n = getDayOfWeek(year, month, day); try aw.writer.print("{d}", .{if (n == 0) @as(u32, 7) else n}); },
                    'W' => try aw.writer.print("{d:0>2}", .{getIsoWeek(year, month, day)}),
                    'H' => try aw.writer.print("{d:0>2}", .{hour}),
                    'G' => try aw.writer.print("{d}", .{hour}),
                    'h' => { const h12 = if (hour == 0) @as(u32, 12) else if (hour > 12) hour - 12 else hour; try aw.writer.print("{d:0>2}", .{h12}); },
                    'g' => { const h12 = if (hour == 0) @as(u32, 12) else if (hour > 12) hour - 12 else hour; try aw.writer.print("{d}", .{h12}); },
                    'a' => try aw.writer.writeAll(if (hour < 12) "am" else "pm"),
                    'A' => try aw.writer.writeAll(if (hour < 12) "AM" else "PM"),
                    'i' => try aw.writer.print("{d:0>2}", .{minute}),
                    's' => try aw.writer.print("{d:0>2}", .{second}),
                    'u' => try aw.writer.print("{d:0>6}", .{self.microseconds}),
                    'v' => try aw.writer.print("{d:0>3}", .{@divFloor(self.microseconds, 1000)}),
                    'T' => try aw.writer.writeAll(self.timezone_name),
                    'O' => { const oh = @divFloor(self.timezone_offset, 3600); const om = @divFloor(@rem(self.timezone_offset, 3600), 60); if (oh >= 0) try aw.writer.print("+{d:0>2}{d:0>2}", .{oh, @abs(om)}) else try aw.writer.print("{d:0>3}{d:0>2}", .{oh, @abs(om)}); },
                    'P' => { const oh = @divFloor(self.timezone_offset, 3600); const om = @divFloor(@rem(self.timezone_offset, 3600), 60); if (oh >= 0) try aw.writer.print("+{d:0>2}:{d:0>2}", .{oh, @abs(om)}) else try aw.writer.print("{d:0>3}:{d:0>2}", .{oh, @abs(om)}); },
                    'Z' => try aw.writer.print("{d}", .{self.timezone_offset}),
                    'U' => try aw.writer.print("{d}", .{self.timestamp}),
                    'c' => { try aw.writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{year, month, day, hour, minute, second}); const oh = @divFloor(self.timezone_offset, 3600); const om = @divFloor(@rem(self.timezone_offset, 3600), 60); if (oh >= 0) try aw.writer.print("+{d:0>2}:{d:0>2}", .{oh, @abs(om)}) else try aw.writer.print("{d:0>3}:{d:0>2}", .{oh, @abs(om)}); },
                    'r' => { const wd = switch (getDayOfWeek(year, month, day)) { 0=>"Sun", 1=>"Mon", 2=>"Tue", 3=>"Wed", 4=>"Thu", 5=>"Fri", 6=>"Sat", else=>"???" }; const mon = switch (month) { 1=>"Jan", 2=>"Feb", 3=>"Mar", 4=>"Apr", 5=>"May", 6=>"Jun", 7=>"Jul", 8=>"Aug", 9=>"Sep", 10=>"Oct", 11=>"Nov", 12=>"Dec", else=>"???" }; const oh = @divFloor(self.timezone_offset, 3600); const om = @divFloor(@rem(self.timezone_offset, 3600), 60); if (oh >= 0) try aw.writer.print("{s}, {d} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} +{d:0>2}{d:0>2}", .{wd, day, mon, year, hour, minute, second, oh, @abs(om)}) else try aw.writer.print("{s}, {d} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} -{d:0>2}{d:0>2}", .{wd, day, mon, year, hour, minute, second, @abs(oh), @abs(om)}); },
                    '\\' => { i += 1; if (i < format_str.len) try aw.writer.writeAll(format_str[i .. i + 1]); },
                    else => try aw.writer.writeAll(&[_]u8{c}),
                }
            }
            return Value.initString(try PHPString.init(allocator, aw.written()));
        }
    };

    fn formatDateTimeWithFormat(timestamp: i64, format_str: []const u8, allocator: Allocator) !Value {
        const formatter = DateTimeFormatter{ .timestamp = timestamp, .microseconds = 0, .timezone_offset = 0, .timezone_name = "UTC" };
        return formatter.format(format_str, allocator);
    }

    fn formatDateTimeYmd(timestamp: i64, allocator: Allocator) !Value {
        return formatDateTimeWithFormat(timestamp, "Y-m-d", allocator);
    }

    fn registerStdClass(allocator: Allocator) !void {
        if (findClass("stdClass") != null) return;
        const meta = try ClassMeta.init(allocator, "stdClass");
        try registerClass(meta);
    }

    // ========================================================================
    // 时区数据库 (简化版)
    // ========================================================================
    
    const TimezoneInfo = struct { name: []const u8, offset_seconds: i32, abbreviation: []const u8 };
    const TIMEZONE_DATABASE: []const TimezoneInfo = &[_]TimezoneInfo{
        .{ .name = "UTC", .offset_seconds = 0, .abbreviation = "UTC" },
        .{ .name = "GMT", .offset_seconds = 0, .abbreviation = "GMT" },
        .{ .name = "America/New_York", .offset_seconds = -18000, .abbreviation = "EST" },
        .{ .name = "America/Chicago", .offset_seconds = -21600, .abbreviation = "CST" },
        .{ .name = "America/Denver", .offset_seconds = -25200, .abbreviation = "MST" },
        .{ .name = "America/Los_Angeles", .offset_seconds = -28800, .abbreviation = "PST" },
        .{ .name = "Europe/London", .offset_seconds = 0, .abbreviation = "GMT" },
        .{ .name = "Europe/Paris", .offset_seconds = 3600, .abbreviation = "CET" },
        .{ .name = "Europe/Berlin", .offset_seconds = 3600, .abbreviation = "CET" },
        .{ .name = "Europe/Moscow", .offset_seconds = 10800, .abbreviation = "MSK" },
        .{ .name = "Asia/Shanghai", .offset_seconds = 28800, .abbreviation = "CST" },
        .{ .name = "Asia/Beijing", .offset_seconds = 28800, .abbreviation = "CST" },
        .{ .name = "Asia/Hong_Kong", .offset_seconds = 28800, .abbreviation = "HKT" },
        .{ .name = "Asia/Tokyo", .offset_seconds = 32400, .abbreviation = "JST" },
        .{ .name = "Asia/Seoul", .offset_seconds = 32400, .abbreviation = "KST" },
        .{ .name = "Asia/Singapore", .offset_seconds = 28800, .abbreviation = "SGT" },
        .{ .name = "Australia/Sydney", .offset_seconds = 36000, .abbreviation = "AEST" },
    };

    fn findTimezone(name: []const u8) ?TimezoneInfo {
        for (TIMEZONE_DATABASE) |tz| if (std.mem.eql(u8, tz.name, name)) return tz;
        return null;
    }

    fn parseTimezoneOffset(tz_str: []const u8) ?i32 {
        if (findTimezone(tz_str)) |tz| return tz.offset_seconds;
        if (tz_str.len >= 3 and (tz_str[0] == '+' or tz_str[0] == '-')) {
            const sign: i32 = if (tz_str[0] == '+') 1 else -1;
            const rest = tz_str[1..];
            var hours: i32 = 0; var minutes: i32 = 0;
            if (rest.len == 2) hours = std.fmt.parseInt(i32, rest, 10) catch return null
            else if (rest.len == 4) { hours = std.fmt.parseInt(i32, rest[0..2], 10) catch return null; minutes = std.fmt.parseInt(i32, rest[2..4], 10) catch return null; }
            else if (rest.len == 5 and rest[2] == ':') { hours = std.fmt.parseInt(i32, rest[0..2], 10) catch return null; minutes = std.fmt.parseInt(i32, rest[3..5], 10) catch return null; }
            return sign * (hours * 3600 + minutes * 60);
        }
        return null;
    }

    // ========================================================================
    // DateTimeZone 类注册
    // ========================================================================

    fn registerDateTimeZoneClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "DateTimeZone");
        try meta.addProperty(.{ .name = "timezone", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "__offset", .default_value = Value.initInt(0), .is_public = false });

        try meta.addMethod(.{ .name = "__construct", .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len > 0 and args[0].isString()) {
                    const tz_name = args[0].asString().data;
                    try this.setProperty("timezone", args[0]);
                    if (parseTimezoneOffset(tz_name)) |offset| try this.setProperty("__offset", Value.initInt(offset));
                } else {
                    try this.setProperty("timezone", Value.initString(try PHPString.init(runtime_alloc, "UTC")));
                }
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getName", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("timezone")) |tz| { _ = tz.retain(); return tz; }
                return Value.initString(try PHPString.init(runtime_allocator, "UTC"));
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getOffset", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("__offset")) |offset| return offset;
                return Value.initInt(0);
            }
        }.call, .is_static = false });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
    }

    // ========================================================================
    // DateInterval 类注册
    // ========================================================================

    fn registerDateIntervalClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "DateInterval");
        try meta.addProperty(.{ .name = "y", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "m", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "d", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "h", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "i", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "s", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "f", .default_value = Value.initFloat(0.0), .is_public = true });
        try meta.addProperty(.{ .name = "invert", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "days", .default_value = Value.initBool(false), .is_public = true });

        // __construct(string $duration) - 解析 ISO 8601 duration
        try meta.addMethod(.{ .name = "__construct", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !args[0].isString()) return Value.initNull();
                const spec = args[0].asString().data;
                if (spec.len < 1 or spec[0] != 'P') return error.InvalidDateIntervalSpecification;

                var y: i64 = 0; var m: i64 = 0; var d: i64 = 0;
                var h: i64 = 0; var i: i64 = 0; var s: i64 = 0;
                var in_time = false; var pos: usize = 1;
                var num_buf: [32]u8 = undefined; var num_len: usize = 0;

                while (pos < spec.len) {
                    const c = spec[pos];
                    if (c >= '0' and c <= '9' or c == '.') { if (num_len < 32) { num_buf[num_len] = c; num_len += 1; } pos += 1; }
                    else if (c == 'T') { in_time = true; pos += 1; num_len = 0; }
                    else {
                        const num_str = num_buf[0..num_len];
                        const num_val = std.fmt.parseFloat(f64, num_str) catch 0;
                        switch (c) {
                            'Y' => { y = @intFromFloat(num_val); },
                            'M' => { if (in_time) i = @intFromFloat(num_val) else m = @intFromFloat(num_val); },
                            'D' => { d = @intFromFloat(num_val); },
                            'H' => { h = @intFromFloat(num_val); },
                            'S' => { s = @intFromFloat(@floor(num_val)); },
                            else => {},
                        }
                        pos += 1; num_len = 0;
                    }
                }
                try this.setProperty("y", Value.initInt(y));
                try this.setProperty("m", Value.initInt(m));
                try this.setProperty("d", Value.initInt(d));
                try this.setProperty("h", Value.initInt(h));
                try this.setProperty("i", Value.initInt(i));
                try this.setProperty("s", Value.initInt(s));
                return Value.initNull();
            }
        }.call, .is_static = false });

        // format(string $format)
        try meta.addMethod(.{ .name = "format", .func = struct {
            fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !args[0].isString()) return Value.initString(try PHPString.init(alloc, ""));
                const format_str = args[0].asString().data;
                var result = try std.ArrayList(u8).initCapacity(alloc, format_str.len * 2);
                defer result.deinit(alloc);
                var aw = std.Io.Writer.Allocating.fromArrayList(alloc, &result);

                const y = if (this.getProperty("y")) |v| v.toInt() else 0;
                const m = if (this.getProperty("m")) |v| v.toInt() else 0;
                const d = if (this.getProperty("d")) |v| v.toInt() else 0;
                const h = if (this.getProperty("h")) |v| v.toInt() else 0;
                const i = if (this.getProperty("i")) |v| v.toInt() else 0;
                const s = if (this.getProperty("s")) |v| v.toInt() else 0;
                const invert = if (this.getProperty("invert")) |v| v.toInt() else 0;

                var fi: usize = 0;
                while (fi < format_str.len) : (fi += 1) {
                    if (format_str[fi] == '%' and fi + 1 < format_str.len) {
                        fi += 1;
                        switch (format_str[fi]) {
                            'Y' => try aw.writer.print("{d:0>2}", .{y}),
                            'y' => try aw.writer.print("{d}", .{y}),
                            'M' => try aw.writer.print("{d:0>2}", .{m}),
                            'm' => try aw.writer.print("{d}", .{m}),
                            'D' => try aw.writer.print("{d:0>2}", .{d}),
                            'd' => try aw.writer.print("{d}", .{d}),
                            'H' => try aw.writer.print("{d:0>2}", .{h}),
                            'h' => try aw.writer.print("{d}", .{h}),
                            'I' => try aw.writer.print("{d:0>2}", .{i}),
                            'i' => try aw.writer.print("{d}", .{i}),
                            'S' => try aw.writer.print("{d:0>2}", .{s}),
                            's' => try aw.writer.print("{d}", .{s}),
                            'R' => try aw.writer.writeAll(if (invert == 1) "-" else "+"),
                            'r' => try aw.writer.writeAll(if (invert == 1) "-" else ""),
                            '%' => try result.append(alloc, '%'),
                            'a' => {
                                const days_val = if (this.getProperty("days")) |v| v.toInt() else 0;
                                try aw.writer.print("{d}", .{days_val});
                            },
                            else => {
                                try result.append(alloc, '%');
                                try result.append(alloc, format_str[fi]);
                            },
                        }
                    } else {
                        try result.append(alloc, format_str[fi]);
                    }
                }
                return Value.initString(try PHPString.init(alloc, result.items));
            }
        }.call, .is_static = false });

        // createFromDateString(string $datetime)
        try meta.addMethod(.{ .name = "createFromDateString", .func = struct {
            fn call(_: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                if (args.len == 0 or !args[0].isString()) return Value.initNull();
                const spec = args[0].asString().data;
                var y: i64 = 0; var m: i64 = 0; var d: i64 = 0;
                var h: i64 = 0; var i: i64 = 0; var s: i64 = 0;
                var pos: usize = 0;

                while (pos < spec.len) {
                    while (pos < spec.len and spec[pos] == ' ') pos += 1;
                    if (pos >= spec.len) break;
                    var num: i64 = 0;
                    while (pos < spec.len and spec[pos] >= '0' and spec[pos] <= '9') { num = num * 10 + (spec[pos] - '0'); pos += 1; }
                    while (pos < spec.len and spec[pos] == ' ') pos += 1;
                    const start = pos;
                    while (pos < spec.len and spec[pos] >= 'a' and spec[pos] <= 'z') pos += 1;
                    const unit = spec[start..pos];

                    if (std.mem.startsWith(u8, unit, "year")) y += num
                    else if (std.mem.startsWith(u8, unit, "month")) m += num
                    else if (std.mem.startsWith(u8, unit, "day")) d += num
                    else if (std.mem.startsWith(u8, unit, "hour")) h += num
                    else if (std.mem.startsWith(u8, unit, "minute")) i += num
                    else if (std.mem.startsWith(u8, unit, "second")) s += num
                    else if (std.mem.startsWith(u8, unit, "week")) d += num * 7;
                }

                const meta_ptr = findClass("DateInterval") orelse return Value.initNull();
                const obj = try PHPObject.initWithMeta(alloc, meta_ptr);
                try obj.setProperty("y", Value.initInt(y));
                try obj.setProperty("m", Value.initInt(m));
                try obj.setProperty("d", Value.initInt(d));
                try obj.setProperty("h", Value.initInt(h));
                try obj.setProperty("i", Value.initInt(i));
                try obj.setProperty("s", Value.initInt(s));
                return Value_initObject(obj);
            }
        }.call, .is_static = true });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
    }

    // ========================================================================
    // DatePeriod 类注册
    // ========================================================================

    fn registerDatePeriodClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "DatePeriod");
        try meta.addProperty(.{ .name = "start", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "interval", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "end", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "recurrences", .default_value = Value.initInt(0), .is_public = false });
        try meta.addProperty(.{ .name = "_current", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "_key", .default_value = Value.initInt(0), .is_public = false });

        try meta.addMethod(.{ .name = "__construct", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len < 3) return Value.initNull();
                try this.setProperty("start", args[0]);
                try this.setProperty("interval", args[1]);
                if (args[2].isInt()) try this.setProperty("recurrences", args[2]) else try this.setProperty("end", args[2]);
                try this.setProperty("_current", args[0]);
                try this.setProperty("_key", Value.initInt(0));
                return Value.initNull();
            }
        }.call, .is_static = false });

        // Iterator interface
        try meta.addMethod(.{ .name = "current", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("_current")) |current| { _ = current.retain(); return current; }
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "key", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("_key")) |key| return key;
                return Value.initInt(0);
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "next", .func = struct {
            fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                var current_ts: i64 = 0;
                if (this.getProperty("_current")) |current| {
                    if (Value_isObject(current)) {
                        if (Value_asObject(current).getProperty("timestamp")) |ts| current_ts = ts.toInt();
                    }
                }
                var add_secs: i64 = 0;
                if (this.getProperty("interval")) |interval| {
                    if (Value_isObject(interval)) {
                        const intv = Value_asObject(interval);
                        const d = if (intv.getProperty("d")) |v| v.toInt() else 0;
                        const h = if (intv.getProperty("h")) |v| v.toInt() else 0;
                        const i = if (intv.getProperty("i")) |v| v.toInt() else 0;
                        const s = if (intv.getProperty("s")) |v| v.toInt() else 0;
                        add_secs = d * 86400 + h * 3600 + i * 60 + s;
                    }
                }
                current_ts += add_secs;
                if (findClass("DateTime")) |dt_meta| {
                    const new_dt = try PHPObject.initWithMeta(alloc, dt_meta);
                    try new_dt.setProperty("timestamp", Value.initInt(current_ts));
                    try new_dt.setProperty("microseconds", Value.initInt(0));
                    try this.setProperty("_current", Value_initObject(new_dt));
                }
                if (this.getProperty("_key")) |key| try this.setProperty("_key", Value.initInt(key.toInt() + 1));
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "rewind", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("start")) |start| try this.setProperty("_current", start);
                try this.setProperty("_key", Value.initInt(0));
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "valid", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("end")) |end| {
                    if (!end.isNull()) {
                        var current_ts: i64 = 0; var end_ts: i64 = 0;
                        if (this.getProperty("_current")) |current| {
                            if (Value_isObject(current)) {
                                if (Value_asObject(current).getProperty("timestamp")) |ts| current_ts = ts.toInt();
                            }
                        }
                        if (Value_isObject(end)) {
                            if (Value_asObject(end).getProperty("timestamp")) |ts| end_ts = ts.toInt();
                        }
                        return Value.initBool(current_ts < end_ts);
                    }
                }
                if (this.getProperty("recurrences")) |recurrences| {
                    if (this.getProperty("_key")) |key| return Value.initBool(key.toInt() < recurrences.toInt());
                }
                return Value.initBool(false);
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getStartDate", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("start")) |start| { _ = start.retain(); return start; }
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getEndDate", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("end")) |end| { _ = end.retain(); return end; }
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getDateInterval", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("interval")) |interval| { _ = interval.retain(); return interval; }
                return Value.initNull();
            }
        }.call, .is_static = false });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
    }

    // ========================================================================
    // DateTime 主类注册
    // ========================================================================

    fn registerDateTimeClasses(allocator: Allocator) !void {
        // DateTimeInterface
        const iface = try ClassMeta.init(allocator, "DateTimeInterface");
        iface.is_abstract = true;
        iface.is_interface = true;
        try registerClass(iface);

        // DateTimeInterface 常量
        const dt_consts = [_]struct { key: []const u8, val: []const u8 }{
            .{ .key = "DateTimeInterface::ATOM", .val = "Y-m-d\\TH:i:sP" },
            .{ .key = "DateTimeInterface::COOKIE", .val = "l, d-M-Y H:i:s T" },
            .{ .key = "DateTimeInterface::ISO8601", .val = "Y-m-d\\TH:i:sO" },
            .{ .key = "DateTimeInterface::RFC822", .val = "D, d M y H:i:s O" },
            .{ .key = "DateTimeInterface::RFC850", .val = "l, d-M-y H:i:s T" },
            .{ .key = "DateTimeInterface::RFC1123", .val = "D, d M Y H:i:s O" },
            .{ .key = "DateTimeInterface::RFC2822", .val = "D, d M Y H:i:s O" },
            .{ .key = "DateTimeInterface::RFC3339", .val = "Y-m-d\\TH:i:sP" },
            .{ .key = "DateTimeInterface::RSS", .val = "D, d M Y H:i:s O" },
            .{ .key = "DateTimeInterface::W3C", .val = "Y-m-d\\TH:i:sP" },
        };
        for (dt_consts) |c| {
            const k = try allocator.dupe(u8, c.key);
            try constants.put(k, Value.initString(try PHPString.init(allocator, c.val)));
        }

        // 注册辅助类
        try registerDateTimeZoneClass(allocator);
        try registerDateIntervalClass(allocator);
        try registerDatePeriodClass(allocator);

        // DateTime 类
        const meta = try ClassMeta.init(allocator, "DateTime");
        try meta.addProperty(.{ .name = "timestamp", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "microseconds", .default_value = Value.initInt(0), .is_public = false });
        try meta.addProperty(.{ .name = "timezone", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "__offset", .default_value = Value.initInt(0), .is_public = false });

        // __construct(?string $datetime = "now", ?DateTimeZone $timezone = null)
        try meta.addMethod(.{ .name = "__construct", .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                var tz_offset: i32 = 0; var tz_name: []const u8 = "UTC";

                if (args.len > 1 and Value_isObject(args[1])) {
                    const tz_obj = Value_asObject(args[1]);
                    if (tz_obj.getProperty("__offset")) |offset| { tz_offset = @intCast(offset.toInt()); }
                    if (tz_obj.getProperty("timezone")) |tz| { if (tz.isString()) { tz_name = tz.asString().data; } }
                    try this.setProperty("timezone", args[1]);
                } else try this.setProperty("timezone", Value.initString(try PHPString.init(runtime_alloc, "UTC")));
                try this.setProperty("__offset", Value.initInt(tz_offset));

                if (args.len > 0 and !args[0].isNull()) {
                    const datetime_str = args[0].asString().data;
                    if (std.mem.eql(u8, datetime_str, "now")) {
                        const now_ns = nanoTimestamp();
                        const now_us = @divTrunc(now_ns, 1000);
                        try this.setProperty("timestamp", Value.initInt(@intCast(@divTrunc(now_us, 1_000_000))));
                        try this.setProperty("microseconds", Value.initInt(@intCast(@rem(now_us, 1_000_000))));
                    } else if (datetime_str.len > 0 and datetime_str[0] == '@') {
                        const ts = std.fmt.parseInt(i64, datetime_str[1..], 10) catch unixTimestamp();
                        try this.setProperty("timestamp", Value.initInt(ts));
                        try this.setProperty("microseconds", Value.initInt(0));
                    } else {
                        const parsed = try php_strtotime(args[0], Value.initInt(unixTimestamp()), runtime_alloc);
                        if (parsed.isInt()) {
                            try this.setProperty("timestamp", Value.initInt(parsed.toInt() - tz_offset));
                            try this.setProperty("microseconds", Value.initInt(0));
                        } else {
                            try this.setProperty("timestamp", Value.initInt(unixTimestamp()));
                            try this.setProperty("microseconds", Value.initInt(0));
                        }
                    }
                } else {
                    const now_ns = nanoTimestamp();
                    const now_us = @divTrunc(now_ns, 1000);
                    try this.setProperty("timestamp", Value.initInt(@intCast(@divTrunc(now_us, 1_000_000))));
                    try this.setProperty("microseconds", Value.initInt(@intCast(@rem(now_us, 1_000_000))));
                }
                return Value.initNull();
            }
        }.call, .is_static = false });

        // format(string $format): string
        try meta.addMethod(.{ .name = "format", .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                const ts = if (this.getProperty("timestamp")) |ts_val| ts_val.toInt() else unixTimestamp();
                const us = if (this.getProperty("microseconds")) |us_val| us_val.toInt() else 0;
                const tz_offset = if (this.getProperty("__offset")) |off| @as(i32, @intCast(off.toInt())) else 0;

                var tz_name: []const u8 = "UTC";
                if (this.getProperty("timezone")) |tz| {
                    if (tz.isString()) { tz_name = tz.asString().data; }
                    else if (Value_isObject(tz)) {
                        if (Value_asObject(tz).getProperty("timezone")) |tz_str| { if (tz_str.isString()) { tz_name = tz_str.asString().data; } }
                    }
                }

                const formatter = DateTimeFormatter{ .timestamp = ts, .microseconds = us, .timezone_offset = tz_offset, .timezone_name = tz_name };
                if (args.len > 0 and args[0].isString()) return formatter.format(args[0].asString().data, runtime_alloc);
                return formatter.format("Y-m-d H:i:s", runtime_alloc);
            }
        }.call, .is_static = false });

        // getTimestamp(): int
        try meta.addMethod(.{ .name = "getTimestamp", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("timestamp")) |ts| return ts;
                return Value.initInt(unixTimestamp());
            }
        }.call, .is_static = false });

        // setTimestamp(int $timestamp): DateTime
        try meta.addMethod(.{ .name = "setTimestamp", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len > 0) try this.setProperty("timestamp", Value.initInt(args[0].toInt()));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // setTimezone(DateTimeZone $timezone): DateTime
        try meta.addMethod(.{ .name = "setTimezone", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len > 0 and Value_isObject(args[0])) {
                    try this.setProperty("timezone", args[0]);
                    if (Value_asObject(args[0]).getProperty("__offset")) |offset| try this.setProperty("__offset", offset);
                }
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // getTimezone(): DateTimeZone|false
        try meta.addMethod(.{ .name = "getTimezone", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("timezone")) |tz| { _ = tz.retain(); return tz; }
                return Value.initBool(false);
            }
        }.call, .is_static = false });

        // add(DateInterval $interval): DateTime
        try meta.addMethod(.{ .name = "add", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !Value_isObject(args[0])) { _ = ctx.retain(); return ctx; }
                const interval = Value_asObject(args[0]);
                var ts = if (this.getProperty("timestamp")) |t| t.toInt() else 0;
                const y = if (interval.getProperty("y")) |v| v.toInt() else 0;
                const m = if (interval.getProperty("m")) |v| v.toInt() else 0;
                const d = if (interval.getProperty("d")) |v| v.toInt() else 0;
                const h = if (interval.getProperty("h")) |v| v.toInt() else 0;
                const i = if (interval.getProperty("i")) |v| v.toInt() else 0;
                const s = if (interval.getProperty("s")) |v| v.toInt() else 0;
                ts += y * 31536000 + m * 2592000 + d * 86400 + h * 3600 + i * 60 + s;
                try this.setProperty("timestamp", Value.initInt(ts));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // sub(DateInterval $interval): DateTime
        try meta.addMethod(.{ .name = "sub", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !Value_isObject(args[0])) { _ = ctx.retain(); return ctx; }
                const interval = Value_asObject(args[0]);
                var ts = if (this.getProperty("timestamp")) |t| t.toInt() else 0;
                const y = if (interval.getProperty("y")) |v| v.toInt() else 0;
                const m = if (interval.getProperty("m")) |v| v.toInt() else 0;
                const d = if (interval.getProperty("d")) |v| v.toInt() else 0;
                const h = if (interval.getProperty("h")) |v| v.toInt() else 0;
                const i = if (interval.getProperty("i")) |v| v.toInt() else 0;
                const s = if (interval.getProperty("s")) |v| v.toInt() else 0;
                ts -= y * 31536000 + m * 2592000 + d * 86400 + h * 3600 + i * 60 + s;
                try this.setProperty("timestamp", Value.initInt(ts));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // diff(DateTimeInterface $targetObject, bool $absolute = false): DateInterval
        try meta.addMethod(.{ .name = "diff", .func = struct {
            fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !Value_isObject(args[0])) return Value.initNull();
                const this_ts = if (this.getProperty("timestamp")) |t| t.toInt() else 0;
                const target_ts = if (Value_asObject(args[0]).getProperty("timestamp")) |t| t.toInt() else 0;
                const diff_seconds: i64 = @intCast(@abs(this_ts - target_ts));
                const interval_meta = findClass("DateInterval") orelse return Value.initNull();
                const interval = try PHPObject.initWithMeta(alloc, interval_meta);
                try interval.setProperty("y", Value.initInt(0));
                try interval.setProperty("m", Value.initInt(0));
                try interval.setProperty("d", Value.initInt(@divFloor(diff_seconds, 86400)));
                try interval.setProperty("h", Value.initInt(@divFloor(@rem(diff_seconds, 86400), 3600)));
                try interval.setProperty("i", Value.initInt(@divFloor(@rem(diff_seconds, 3600), 60)));
                try interval.setProperty("s", Value.initInt(@rem(diff_seconds, 60)));
                try interval.setProperty("invert", Value.initInt(if (this_ts < target_ts) @as(i64, 0) else @as(i64, 1)));
                try interval.setProperty("days", Value.initInt(@divFloor(diff_seconds, 86400)));
                return Value_initObject(interval);
            }
        }.call, .is_static = false });

        // modify(string $modifier): DateTime|false
        try meta.addMethod(.{ .name = "modify", .func = struct {
            fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !args[0].isString()) return Value.initBool(false);
                const ts = if (this.getProperty("timestamp")) |t| t.toInt() else unixTimestamp();
                const new_ts = try php_strtotime(args[0], Value.initInt(ts), alloc);
                if (new_ts.isInt()) {
                    try this.setProperty("timestamp", new_ts);
                    _ = ctx.retain(); return ctx;
                }
                return Value.initBool(false);
            }
        }.call, .is_static = false });

        // setDate(int $year, int $month, int $day): DateTime
        try meta.addMethod(.{ .name = "setDate", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len < 3) { _ = ctx.retain(); return ctx; }
                const year = args[0].toInt(); const month = args[1].toInt(); const day = args[2].toInt();
                const y = if (month <= 2) year - 1 else year;
                const m = if (month <= 2) month + 12 else month;
                const jd = 365 * y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) + @divFloor(306 * (m + 1), 10) + day - 719591;
                try this.setProperty("timestamp", Value.initInt(jd * 86400));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // setTime(int $hour, int $minute, int $second = 0): DateTime
        try meta.addMethod(.{ .name = "setTime", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len < 2) { _ = ctx.retain(); return ctx; }
                const hour = args[0].toInt(); const minute = args[1].toInt();
                const second = if (args.len > 2) args[2].toInt() else 0;
                var ts = if (this.getProperty("timestamp")) |t| t.toInt() else 0;
                const day_ts = @divFloor(ts, 86400) * 86400;
                ts = day_ts + hour * 3600 + minute * 60 + second;
                try this.setProperty("timestamp", Value.initInt(ts));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // createFromFormat(string $format, string $datetime, ?DateTimeZone $timezone = null): DateTime|false
        try meta.addMethod(.{ .name = "createFromFormat", .func = struct {
            fn call(_: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                if (args.len < 2) return Value.initBool(false);
                if (!args[0].isString() or !args[1].isString()) return Value.initBool(false);

                const format_str = args[0].asString().data;
                const datetime_str = args[1].asString().data;

                // 简单解析: Y-m-d H:i:s
                var year: i64 = 1970; var month: i64 = 1; var day: i64 = 1;
                var hour: i64 = 0; var minute: i64 = 0; var second: i64 = 0;
                var fmt_pos: usize = 0; var dt_pos: usize = 0;

                while (fmt_pos < format_str.len and dt_pos < datetime_str.len) {
                    const fc = format_str[fmt_pos];
                    switch (fc) {
                        'Y' => { if (dt_pos + 4 <= datetime_str.len) { year = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+4], 10) catch 1970; dt_pos += 4; } fmt_pos += 1; },
                        'm' => { if (dt_pos + 2 <= datetime_str.len) { month = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 1; dt_pos += 2; } fmt_pos += 1; },
                        'd' => { if (dt_pos + 2 <= datetime_str.len) { day = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 1; dt_pos += 2; } fmt_pos += 1; },
                        'H' => { if (dt_pos + 2 <= datetime_str.len) { hour = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 0; dt_pos += 2; } fmt_pos += 1; },
                        'i' => { if (dt_pos + 2 <= datetime_str.len) { minute = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 0; dt_pos += 2; } fmt_pos += 1; },
                        's' => { if (dt_pos + 2 <= datetime_str.len) { second = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 0; dt_pos += 2; } fmt_pos += 1; },
                        else => { if (dt_pos < datetime_str.len and datetime_str[dt_pos] == fc) dt_pos += 1; fmt_pos += 1; },
                    }
                }

                const y = if (month <= 2) year - 1 else year;
                const m = if (month <= 2) month + 12 else month;
                const jd = 365 * y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) + @divFloor(306 * (m + 1), 10) + day - 719591;
                const ts: i64 = jd * 86400 + hour * 3600 + minute * 60 + second;

                const meta_ptr = findClass("DateTime") orelse return Value.initBool(false);
                const obj = try PHPObject.initWithMeta(alloc, meta_ptr);
                try obj.setProperty("timestamp", Value.initInt(ts));
                try obj.setProperty("microseconds", Value.initInt(0));
                if (args.len > 2) try obj.setProperty("timezone", args[2])
                else try obj.setProperty("timezone", Value.initString(try PHPString.init(alloc, "UTC")));
                return Value_initObject(obj);
            }
        }.call, .is_static = true });

        // __clone()
        try meta.addMethod(.{ .name = "__clone", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                _ = ctx; // 克隆已由运行时处理
                return Value.initNull();
            }
        }.call, .is_static = false });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);

        // DateTimeImmutable 类（复用 DateTime 方法，行为与 DateTime 一致）
        const imm_meta = try ClassMeta.init(allocator, "DateTimeImmutable");
        // 复制 DateTime 所有属性定义
        try imm_meta.addProperty(.{ .name = "timestamp", .default_value = Value.initNull(), .is_public = false });
        try imm_meta.addProperty(.{ .name = "microseconds", .default_value = Value.initInt(0), .is_public = false });
        try imm_meta.addProperty(.{ .name = "timezone", .default_value = Value.initNull(), .is_public = false });
        try imm_meta.addProperty(.{ .name = "__offset", .default_value = Value.initInt(0), .is_public = false });

        // 复用 DateTime 的所有方法
        var meth_iter = meta.methods.iterator();
        while (meth_iter.next()) |entry| {
            try imm_meta.addMethod(.{
                .name = entry.key_ptr.*,
                .func = entry.value_ptr.func,
                .is_static = entry.value_ptr.is_static,
            });
        }
        imm_meta.magic_construct = meta.magic_construct;
        try registerClass(imm_meta);
    }

    /// 注册内置 Exception 类
    pub fn registerExceptionClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "Exception");

        // __construct($message = "", $code = 0, $previous = null)
        try meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    const this = Value_asObject(ctx);
                    if (args.len > 0) {
                        try this.setProperty("message", args[0]);
                    } else {
                        try this.setProperty("message", Value.initString(try PHPString.init(runtime_alloc, "")));
                    }
                    if (args.len > 1) {
                        try this.setProperty("code", args[1]);
                    } else {
                        try this.setProperty("code", Value.initInt(0));
                    }
                    if (args.len > 2) {
                        try this.setProperty("previous", args[2]);
                    } else {
                        try this.setProperty("previous", Value.initNull());
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // getMessage()
        try meta.addMethod(.{
            .name = "getMessage",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("message")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initString(try PHPString.init(runtime_alloc, ""));
                }
            }.call,
            .is_static = false,
        });

        try meta.addMethod(.{
            .name = "getCode",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    _ = runtime_alloc;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("code")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });

        try meta.addMethod(.{
            .name = "getFile",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("file")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initString(try PHPString.init(runtime_alloc, ""));
                }
            }.call,
            .is_static = false,
        });

        try meta.addMethod(.{
            .name = "getLine",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    _ = runtime_alloc;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("line")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });

        try meta.addMethod(.{
            .name = "getPrevious",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    _ = runtime_alloc;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("previous")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        try meta.addMethod(.{
            .name = "__toString",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    const this = Value_asObject(ctx);
                    var msg = try PHPString.init(runtime_alloc, "Exception: ");

                    if (this.getProperty("message")) |val| {
                        if (val.isString()) {
                            const new_str = try std.fmt.allocPrint(runtime_alloc, "{s}{s}", .{ msg.data, val.asString().data });
                            defer runtime_alloc.free(new_str);
                            msg.release(runtime_alloc);
                            return Value.initString(try PHPString.init(runtime_alloc, new_str));
                        }
                    }
                    return Value.initString(msg);
                }
            }.call,
            .is_static = false,
        });

        meta.magic_toString = meta.methods.get("__toString").?.func;

        try registerClass(meta);

        // Register standard PHP exception subclasses (flat: extends Exception)
        const exception_subclasses = [_][]const u8{
            "RuntimeException",
            "LogicException",
            "BadMethodCallException",
            "BadFunctionCallException",
            "DomainException",
            "InvalidArgumentException",
            "LengthException",
            "OutOfRangeException",
            "OverflowException",
            "RangeException",
            "UnderflowException",
            "UnexpectedValueException",
        };
        for (exception_subclasses) |name| {
            const child = try ClassMeta.init(allocator, name);
            child.parent = meta;
            child.magic_construct = meta.magic_construct;
            child.magic_toString = meta.magic_toString;
            try registerClass(child);
        }

        // Register Error hierarchy (separate from Exception in PHP)
        // Error extends Exception in our implementation for simplicity
        const error_meta = try ClassMeta.init(allocator, "Error");
        error_meta.parent = meta;
        error_meta.magic_construct = meta.magic_construct;
        error_meta.magic_toString = meta.magic_toString;
        try registerClass(error_meta);

        // ErrorException extends Exception
        const errorexception_meta = try ClassMeta.init(allocator, "ErrorException");
        errorexception_meta.parent = meta;
        errorexception_meta.magic_construct = meta.magic_construct;
        errorexception_meta.magic_toString = meta.magic_toString;
        try registerClass(errorexception_meta);

        // JsonException extends Exception
        const jsonexception_meta = try ClassMeta.init(allocator, "JsonException");
        jsonexception_meta.parent = meta;
        jsonexception_meta.magic_construct = meta.magic_construct;
        jsonexception_meta.magic_toString = meta.magic_toString;
        try registerClass(jsonexception_meta);

        // OutOfBoundsException extends RuntimeException
        const oob_meta = try ClassMeta.init(allocator, "OutOfBoundsException");
        oob_meta.parent = meta; // simplified: parent = Exception
        oob_meta.magic_construct = meta.magic_construct;
        oob_meta.magic_toString = meta.magic_toString;
        try registerClass(oob_meta);

        // TypeError, ValueError extend Error
        const error_subclasses = [_][]const u8{ "TypeError", "ValueError", "UnhandledMatchError" };
        for (error_subclasses) |name| {
            const child = try ClassMeta.init(allocator, name);
            child.parent = error_meta;
            child.magic_construct = meta.magic_construct;
            child.magic_toString = meta.magic_toString;
            try registerClass(child);
        }

        // ArithmeticError extends Error
        const arith_meta = try ClassMeta.init(allocator, "ArithmeticError");
        arith_meta.parent = error_meta;
        arith_meta.magic_construct = meta.magic_construct;
        arith_meta.magic_toString = meta.magic_toString;
        try registerClass(arith_meta);

        // DivisionByZeroError extends ArithmeticError
        const divzero_meta = try ClassMeta.init(allocator, "DivisionByZeroError");
        divzero_meta.parent = arith_meta;
        divzero_meta.magic_construct = meta.magic_construct;
        divzero_meta.magic_toString = meta.magic_toString;
        try registerClass(divzero_meta);

        // Register Closure class (Closure::bind, Closure::fromCallable)
        try registerClosureClass(allocator);
        // Register WeakReference class
        try registerWeakReferenceClass(allocator);
        // Register WeakMap class
        try registerWeakMapClass(allocator);
        // Register Generator class
        try registerGeneratorClass(allocator);
        // Register Reflection classes
        try registerReflectionClasses(allocator);
    }

    /// ============================================================================
    /// Closure Class Implementation
    /// ============================================================================
    /// PHP Closure class: Closure::bind(), Closure::fromCallable(), bindTo()

    fn registerClosureClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "Closure");

        // Closure::bind($closure, $newThis, $newScope = "static") — static method
        try meta.addMethod(.{
            .name = "bind",
            .func = struct {
                fn call(_: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    // args[0] = closure, args[1] = newThis, args[2] = newScope (optional)
                    if (args.len < 2) return Value.initNull();
                    const closure_val = args[0];
                    const new_this = args[1];

                    if (!closure_val.isFunction()) return Value.initNull();
                    const orig_closure = closure_val.asFunction();

                    // static closure 不能绑定 $this
                    if (orig_closure.is_static and !new_this.isNull()) {
                        emitWarning("Cannot bind an instance to a static closure");
                        return Value.initNull();
                    }

                    // 创建新闭包，复制原闭包的函数指针和捕获列表
                    const new_captures = try alloc.alloc(Value, orig_closure.captures.len);
                    for (orig_closure.captures, 0..) |cap, i| {
                        _ = cap.retain();
                        new_captures[i] = cap;
                    }

                    const new_closure = try allocPHPClosure(alloc);
                    // 绑定 $this 到 bound_this 字段（static closure 不绑定）
                    const bound_this = if (orig_closure.is_static) Value.initNull() else brk: {
                        _ = new_this.retain();
                        break :brk new_this;
                    };
                    new_closure.* = .{
                        .func = orig_closure.func,
                        .captures = new_captures,
                        .ref_count = 1,
                        .gc_info = .{},
                        .allocator = alloc,
                        .param_count = orig_closure.param_count,
                        .required_params = orig_closure.required_params,
                        .bound_this = bound_this,
                        .is_static = orig_closure.is_static,
                    };

                    alloc_counters.php_closure_objects += 1;
                    alloc_counters.php_closure_live_objects += 1;
                    if (alloc_counters.php_closure_live_objects > alloc_counters.php_closure_peak_live_objects) {
                        alloc_counters.php_closure_peak_live_objects = alloc_counters.php_closure_live_objects;
                    }

                    return Value.initFunction(new_closure);
                }
            }.call,
            .is_static = true,
        });

        // Closure::fromCallable($callback) — static method
        try meta.addMethod(.{
            .name = "fromCallable",
            .func = struct {
                fn call(_: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    // 如果已经是闭包，直接返回
                    if (args[0].isFunction()) {
                        _ = args[0].retain();
                        return args[0];
                    }
                    // 其他 callable 类型暂时原样返回
                    _ = args[0].retain();
                    return args[0];
                }
            }.call,
            .is_static = true,
        });

        // bindTo($newThis, $newScope = "static") — instance method
        try meta.addMethod(.{
            .name = "bindTo",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    // 将 bindTo 转为 bind(self, newThis, newScope)
                    if (args.len == 0) return Value.initNull();
                    const bind_args = [_]Value{ ctx, args[0], if (args.len > 1) args[1] else Value.initNull() };
                    // 直接调用 Closure 类的 bind 静态方法逻辑
                    if (findClass("Closure")) |closure_meta| {
                        if (closure_meta.findMethod("bind")) |bind_method| {
                            return bind_method.func(ctx, &bind_args, alloc);
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // call($newThis, ...$args) — instance method
        try meta.addMethod(.{
            .name = "call",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!ctx.isFunction()) return Value.initNull();
                    if (args.len == 0) return Value.initNull();
                    // args[0] = newThis, args[1..] = call args
                    const new_this = args[0];
                    const closure = ctx.asFunction();
                    // 临时绑定 $this
                    const prev_this = closure_bound_this_stack;
                    closure_bound_this_stack = new_this;
                    defer closure_bound_this_stack = prev_this;
                    return closure.func(ctx, args[1..], alloc);
                }
            }.call,
            .is_static = false,
        });

        try registerClass(meta);
    }

    /// ============================================================================
    /// WeakReference Implementation
    /// ============================================================================
    /// WeakReference 允许创建对对象的弱引用，不会阻止对象被垃圾回收。
    /// 当对象被销毁时，WeakReference::get() 返回 null。
    ///
    /// PHP API:
    ///   WeakReference::create(object $object): WeakReference
    ///   WeakReference->get(): ?object

    fn registerWeakReferenceClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "WeakReference");

        // WeakReference::create($object) - static factory method
        // 创建一个新的 WeakReference 实例，引用给定的对象
        try meta.addMethod(.{
            .name = "create",
            .func = struct {
                fn call(_: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    // 参数验证：必须提供一个对象
                    if (args.len == 0) {
                        return error.InvalidArgumentCount;
                    }
                    const target = args[0];

                    // 只能对对象创建弱引用
                    if (!Value_isObject(target)) {
                        return error.InvalidArgument;
                    }

                    const target_obj = Value_asObject(target);
                    const target_addr = @intFromPtr(target_obj);

                    // 创建 WeakReference 对象
                    const weakref_obj = if (findClass("WeakReference")) |m|
                        try PHPObject.initWithMeta(alloc, m)
                    else
                        try PHPObject.init(alloc, "WeakReference");

                    // 存储弱引用信息：
                    // __target_addr: 目标对象的内存地址（用于死亡检测）
                    // 注意：我们不应该 retain 目标对象，这是弱引用的核心特性
                    // 但由于当前的内存管理模型，我们需要一种方式来追踪对象是否存活
                    try weakref_obj.setProperty("__target_addr", Value.initInt(@as(i64, @intCast(target_addr))));

                    // 存储目标对象的类名（用于调试和反射）
                    const target_class_name = if (target_obj.class_meta) |m| m.name else "stdClass";
                    const class_name_str = try PHPString.init(alloc, target_class_name);
                    try weakref_obj.setProperty("__target_class", Value.initString(class_name_str));

                    // 存储一个轻量级的引用，用于在对象未被销毁时获取它
                    // 这里我们不增加引用计数（真正弱引用语义），但需要能追踪对象
                    // 在当前实现中，我们使用全局弱引用表来追踪
                    try weakref_register(target_addr, target, alloc);

                    alloc_counters.php_object_live_objects += 1;
                    return Value_initObject(weakref_obj);
                }
            }.call,
            .is_static = true,
        });

        // WeakReference->get() - 获取引用的对象
        // 如果对象已被销毁，返回 null
        try meta.addMethod(.{
            .name = "get",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    // 获取目标对象地址
                    const addr_val = this.getPropertyDirect("__target_addr") orelse return Value.initNull();
                    const addr: usize = @intCast(addr_val.toInt());

                    // 检查对象是否仍然存活
                    if (!php_weak_is_alive(addr)) {
                        return Value.initNull();
                    }

                    // 从弱引用表中获取目标对象
                    return weakref_get(addr);
                }
            }.call,
            .is_static = false,
        });

        // __debugInfo - 用于 var_dump 等调试输出
        try meta.addMethod(.{
            .name = "__debugInfo",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    const arr = try PHPArray.init(alloc);

                    // 获取目标对象地址
                    if (this.getPropertyDirect("__target_addr")) |addr_val| {
                        try arr.push(alloc, addr_val);
                    }

                    // 检查对象是否仍然存活
                    const is_alive = blk: {
                        if (this.getPropertyDirect("__target_addr")) |addr_val| {
                            const addr: usize = @intCast(addr_val.toInt());
                            break :blk php_weak_is_alive(addr);
                        }
                        break :blk false;
                    };
                    try arr.push(alloc, Value.initBool(is_alive));

                    // 添加目标类名
                    if (this.getPropertyDirect("__target_class")) |class_val| {
                        try arr.push(alloc, class_val);
                    }

                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });

        try registerClass(meta);
    }

    /// ============================================================================
    /// WeakMap Implementation
    /// ============================================================================
    /// WeakMap 是一个将对象作为键的映射（字典）。
    /// 与 SplObjectStorage 不同，WeakMap 中的键不会阻止对象被垃圾回收。
    /// 当键对象被销毁时，对应的条目会自动从 WeakMap 中移除。
    ///
    /// PHP API:
    ///   WeakMap implements Countable, ArrayAccess, IteratorAggregate
    ///   - __construct()
    ///   - count(): int
    ///   - offsetGet(object $object): mixed
    ///   - offsetSet(object $object, mixed $value): void
    ///   - offsetExists(object $object): bool
    ///   - offsetUnset(object $object): void
    ///   - getIterator(): Iterator

    fn registerWeakMapClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "WeakMap");

        // 实现接口标记
        const ifaces = try allocator.alloc([]const u8, 4);
        ifaces[0] = "Countable";
        ifaces[1] = "ArrayAccess";
        ifaces[2] = "IteratorAggregate";
        ifaces[3] = "Traversable";
        meta.interfaces = ifaces;

        // __construct() - 构造函数
        try meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    const this = Value_asObject(ctx);
                    // 使用关联数组存储条目：键是对象地址（转为字符串），值是 {key: object, value: value}
                    const entries = try PHPArray.init(alloc);
                    try this.setProperty("_entries", Value.initArray(entries));
                    // 存储条目数量（缓存，避免每次都遍历计算）
                    try this.setProperty("_size", Value.initInt(0));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // count() - 返回存活的条目数 (Countable interface)
        try meta.addMethod(.{
            .name = "count",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);

                    // 清理死亡的条目并重新计算数量
                    var alive_count: i64 = 0;

                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();

                        // 收集需要移除的键
                        var dead_keys = try std.ArrayList([]const u8).initCapacity(alloc, 0);
                        defer {
                            for (dead_keys.items) |key| alloc.free(key);
                            dead_keys.deinit(alloc);
                        }

                        var iter = entries.elements.iterator();
                        while (iter.next()) |entry| {
                            switch (entry.key_ptr.*) {
                                .string => |key_str| {
                                    // 从键字符串解析对象地址
                                    const addr = std.fmt.parseInt(usize, key_str.data, 10) catch 0;
                                    if (addr == 0 or !php_weak_is_alive(addr)) {
                                        try dead_keys.append(alloc, try alloc.dupe(u8, key_str.data));
                                    } else {
                                        alive_count += 1;
                                    }
                                },
                                .integer => {
                                    // 跳过非字符串键
                                },
                            }
                        }

                        // 移除死亡的条目
                        for (dead_keys.items) |key| {
                            // 遍历查找匹配的键并移除
                            var found: ?ArrayKey = null;
                            var rm_iter = entries.elements.iterator();
                            while (rm_iter.next()) |rm_entry| {
                                if (rm_entry.key_ptr.* == .string) {
                                    if (std.mem.eql(u8, rm_entry.key_ptr.*.string.data, key)) {
                                        found = rm_entry.key_ptr.*;
                                        break;
                                    }
                                }
                            }
                            if (found) |fk| _ = entries.elements.remove(fk);
                        }
                    }

                    // 更新缓存的计数
                    try this.setProperty("_size", Value.initInt(alive_count));

                    return Value.initInt(alive_count);
                }
            }.call,
            .is_static = false,
        });

        // offsetExists($object) - 检查键是否存在 (ArrayAccess interface)
        try meta.addMethod(.{
            .name = "offsetExists",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);

                    if (args.len == 0) return Value.initBool(false);

                    // 只接受对象作为键
                    if (!Value_isObject(args[0])) {
                        return error.InvalidArgument;
                    }

                    const key_obj = Value_asObject(args[0]);
                    const addr = @intFromPtr(key_obj);

                    // 检查对象是否存活
                    if (!php_weak_is_alive(addr)) {
                        return Value.initBool(false);
                    }

                    // 查找条目
                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var buf: [32]u8 = undefined;
                        const key_str = std.fmt.bufPrint(&buf, "{}", .{addr}) catch "";
                        // 遍历查找匹配的键
                        var it = entries.elements.iterator();
                        while (it.next()) |entry| {
                            if (entry.key_ptr.* == .string) {
                                if (std.mem.eql(u8, entry.key_ptr.*.string.data, key_str)) {
                                    return Value.initBool(true);
                                }
                            }
                        }
                        return Value.initBool(false);
                    }

                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });

        // offsetGet($object) - 获取值 (ArrayAccess interface)
        try meta.addMethod(.{
            .name = "offsetGet",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (args.len == 0) return Value.initNull();

                    // 只接受对象作为键
                    if (!Value_isObject(args[0])) {
                        return error.InvalidArgument;
                    }

                    const key_obj = Value_asObject(args[0]);
                    const addr = @intFromPtr(key_obj);

                    // 检查对象是否存活
                    if (!php_weak_is_alive(addr)) {
                        return Value.initNull();
                    }

                    // 查找条目
                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var buf: [32]u8 = undefined;
                        const key_str = std.fmt.bufPrint(&buf, "{}", .{addr}) catch "";

                        // 遍历查找匹配的键
                        var it = entries.elements.iterator();
                        while (it.next()) |entry| {
                            if (entry.key_ptr.* == .string) {
                                if (std.mem.eql(u8, entry.key_ptr.*.string.data, key_str)) {
                                    const entry_val = entry.value_ptr.*;
                                    if (entry_val.isArray()) {
                                        const entry_arr = entry_val.asArray();
                                        if (entry_arr.elements.get(.{ .integer = 1 })) |value| {
                                            _ = value.retain();
                                            return value;
                                        }
                                    }
                                    break;
                                }
                            }
                        }
                    }

                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // offsetSet($object, $value) - 设置值 (ArrayAccess interface)
        try meta.addMethod(.{
            .name = "offsetSet",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (args.len < 2) {
                        return error.InvalidArgumentCount;
                    }

                    // 只接受对象作为键
                    if (!Value_isObject(args[0])) {
                        return error.InvalidArgument;
                    }

                    const key_obj = Value_asObject(args[0]);
                    const value = args[1];
                    const addr = @intFromPtr(key_obj);

                    // 检查对象是否存活
                    if (!php_weak_is_alive(addr)) {
                        // 对象已死，不能设置值
                        return Value.initNull();
                    }

                    // 获取或创建条目数组
                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var buf: [32]u8 = undefined;
                        const key_str = std.fmt.bufPrint(&buf, "{}", .{addr}) catch "";

                        // 创建条目：[key_object, value]
                        const entry_arr = try PHPArray.init(alloc);
                        _ = key_obj.retain(); // 保留键对象的引用
                        try entry_arr.push(alloc, args[0]);
                        _ = value.retain();
                        try entry_arr.push(alloc, value);

                        // 检查是否是新条目（遍历查找）
                        var is_new = true;
                        var it = entries.elements.iterator();
                        while (it.next()) |entry| {
                            if (entry.key_ptr.* == .string) {
                                if (std.mem.eql(u8, entry.key_ptr.*.string.data, key_str)) {
                                    is_new = false;
                                    break;
                                }
                            }
                        }

                        // 存储条目
                        const entry_key = try PHPString.init(alloc, key_str);
                        try entries.elements.put(.{ .string = entry_key }, Value.initArray(entry_arr));

                        // 更新计数
                        if (is_new) {
                            if (this.getPropertyDirect("_size")) |size_val| {
                                try this.setProperty("_size", Value.initInt(size_val.toInt() + 1));
                            }
                        }
                    }

                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // offsetUnset($object) - 移除条目 (ArrayAccess interface)
        try meta.addMethod(.{
            .name = "offsetUnset",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (args.len == 0) return Value.initNull();

                    // 只接受对象作为键
                    if (!Value_isObject(args[0])) {
                        return Value.initNull();
                    }

                    const key_obj = Value_asObject(args[0]);
                    const addr = @intFromPtr(key_obj);

                    // 移除条目
                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var buf: [32]u8 = undefined;
                        const key_str = std.fmt.bufPrint(&buf, "{}", .{addr}) catch "";

                        // 遍历查找匹配的键并移除
                        var found_key: ?ArrayKey = null;
                        var it = entries.elements.iterator();
                        while (it.next()) |entry| {
                            if (entry.key_ptr.* == .string) {
                                if (std.mem.eql(u8, entry.key_ptr.*.string.data, key_str)) {
                                    // 释放条目中的值
                                    if (entry.value_ptr.*.isArray()) {
                                        const entry_arr = entry.value_ptr.*.asArray();
                                        if (entry_arr.elements.get(.{ .integer = 0 })) |key_val| {
                                            key_val.release(runtime_allocator);
                                        }
                                        if (entry_arr.elements.get(.{ .integer = 1 })) |value_val| {
                                            value_val.release(runtime_allocator);
                                        }
                                    }
                                    found_key = entry.key_ptr.*;
                                    break;
                                }
                            }
                        }

                        if (found_key) |fk| {
                            _ = entries.elements.remove(fk);

                            // 更新计数
                            if (this.getPropertyDirect("_size")) |size_val| {
                                const current_size = size_val.toInt();
                                if (current_size > 0) {
                                    try this.setProperty("_size", Value.initInt(current_size - 1));
                                }
                            }
                        }
                    }

                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // getIterator() - 返回迭代器 (IteratorAggregate interface)
        try meta.addMethod(.{
            .name = "getIterator",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    // 创建一个 WeakMapIterator 对象
                    const iter_meta = findClass("WeakMapIterator") orelse blk: {
                        // 如果没有 WeakMapIterator 类，使用 ArrayIterator 作为后备
                        break :blk findClass("ArrayIterator");
                    } orelse return Value.initNull();

                    const iter_obj = try PHPObject.initWithMeta(alloc, iter_meta);

                    // 收集存活的条目
                    const result_arr = try PHPArray.init(alloc);

                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var arr_iter = entries.elements.iterator();

                        while (arr_iter.next()) |entry| {
                            switch (entry.key_ptr.*) {
                                .string => |key_str| {
                                    // 从键字符串解析对象地址
                                    const addr = std.fmt.parseInt(usize, key_str.data, 10) catch 0;
                                    if (addr != 0 and php_weak_is_alive(addr)) {
                                        // 条目存活，添加到结果数组
                                        if (entry.value_ptr.*.isArray()) {
                                            const entry_arr = entry.value_ptr.*.asArray();
                                            if (entry_arr.elements.get(.{ .integer = 0 })) |key_obj| {
                                                if (entry_arr.elements.get(.{ .integer = 1 })) |value| {
                                                    // 创建 [key, value] 对
                                                    const pair = try PHPArray.init(alloc);
                                                    _ = key_obj.retain();
                                                    try pair.push(alloc, key_obj);
                                                    _ = value.retain();
                                                    try pair.push(alloc, value);
                                                    try result_arr.push(alloc, Value.initArray(pair));
                                                }
                                            }
                                        }
                                    }
                                },
                                .integer => {},
                            }
                        }
                    }

                    try iter_obj.setProperty("_array", Value.initArray(result_arr));
                    try iter_obj.setProperty("_position", Value.initInt(0));

                    return Value_initObject(iter_obj);
                }
            }.call,
            .is_static = false,
        });

        // __debugInfo - 用于 var_dump 等调试输出
        try meta.addMethod(.{
            .name = "__debugInfo",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    const result = try PHPArray.init(alloc);

                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var arr_iter = entries.elements.iterator();
                        var idx: i64 = 0;

                        while (arr_iter.next()) |entry| {
                            switch (entry.key_ptr.*) {
                                .string => |key_str| {
                                    const addr = std.fmt.parseInt(usize, key_str.data, 10) catch 0;
                                    if (addr != 0 and php_weak_is_alive(addr)) {
                                        if (entry.value_ptr.*.isArray()) {
                                            const entry_arr = entry.value_ptr.*.asArray();
                                            if (entry_arr.elements.get(.{ .integer = 1 })) |value| {
                                                _ = value.retain();
                                                try result.elements.put(.{ .integer = idx }, value);
                                                idx += 1;
                                            }
                                        }
                                    }
                                },
                                .integer => {},
                            }
                        }
                    }

                    return Value.initArray(result);
                }
            }.call,
            .is_static = false,
        });

        try registerClass(meta);

        // 注册 WeakMapIterator 类（内部迭代器）
        try registerWeakMapIteratorClass(allocator);
    }

    /// WeakMapIterator - WeakMap 的内部迭代器
    fn registerWeakMapIteratorClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "WeakMapIterator");

        // 实现迭代器接口
        const ifaces = try allocator.alloc([]const u8, 1);
        ifaces[0] = "Iterator";
        meta.interfaces = ifaces;

        // current() - 返回当前元素
        try meta.addMethod(.{
            .name = "current",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (this.getPropertyDirect("_array")) |arr_val| {
                        if (this.getPropertyDirect("_position")) |pos_val| {
                            const arr = arr_val.asArray();
                            const pos = pos_val.toInt();
                            if (arr.elements.get(.{ .integer = pos })) |pair| {
                                if (pair.isArray()) {
                                    const pair_arr = pair.asArray();
                                    if (pair_arr.elements.get(.{ .integer = 1 })) |value| {
                                        _ = value.retain();
                                        return value;
                                    }
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // key() - 返回当前键
        try meta.addMethod(.{
            .name = "key",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (this.getPropertyDirect("_array")) |arr_val| {
                        if (this.getPropertyDirect("_position")) |pos_val| {
                            const arr = arr_val.asArray();
                            const pos = pos_val.toInt();
                            if (arr.elements.get(.{ .integer = pos })) |pair| {
                                if (pair.isArray()) {
                                    const pair_arr = pair.asArray();
                                    if (pair_arr.elements.get(.{ .integer = 0 })) |key_obj| {
                                        _ = key_obj.retain();
                                        return key_obj;
                                    }
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // next() - 移动到下一个元素
        try meta.addMethod(.{
            .name = "next",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (this.getPropertyDirect("_position")) |pos_val| {
                        try this.setProperty("_position", Value.initInt(pos_val.toInt() + 1));
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // rewind() - 重置迭代器
        try meta.addMethod(.{
            .name = "rewind",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    try this.setProperty("_position", Value.initInt(0));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // valid() - 检查当前位置是否有效
        try meta.addMethod(.{
            .name = "valid",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);

                    if (this.getPropertyDirect("_array")) |arr_val| {
                        if (this.getPropertyDirect("_position")) |pos_val| {
                            const arr = arr_val.asArray();
                            const pos = pos_val.toInt();
                            const exists = arr.elements.get(.{ .integer = pos }) != null;
                            return Value.initBool(exists);
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });

        try registerClass(meta);
    }

    /// 判断 PHP 类型名是否是内置类型（用于 ReflectionNamedType::isBuiltin()）
    /// 注意：self/static/parent 在 PHP 中不是 builtin type，isBuiltin() 返回 false
    fn isBuiltinType(type_name: []const u8) bool {
        const builtins = [_][]const u8{
            "int", "float", "string", "bool", "array", "object", "callable",
            "iterable", "void", "never", "null", "mixed", "true", "false",
        };
        for (builtins) |b| {
            if (std.mem.eql(u8, type_name, b)) return true;
        }
        return false;
    }

    /// Register Reflection classes for PHP reflection API
    fn registerReflectionClasses(allocator: Allocator) !void {
        // ReflectionAttribute
        const attr_meta = try ClassMeta.init(allocator, "ReflectionAttribute");
        try attr_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try attr_meta.addMethod(.{
            .name = "getArguments",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__args")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initArray(try PHPArray.init(alloc));
                }
            }.call,
            .is_static = false,
        });
        // newInstance() - returns an object with attribute name and args as properties
        try attr_meta.addMethod(.{
            .name = "newInstance",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // Create a simple stdClass-like object with attribute properties
                    const name_val = this.getPropertyDirect("__name") orelse return Value.initNull();
                    const args_val = this.getPropertyDirect("__args");
                    if (findClass(if (name_val.isString()) name_val.asString().data else "stdClass")) |cmeta| {
                        const obj = try PHPObject.initWithMeta(alloc, cmeta);
                        // If class has constructor, call it with args
                        if (cmeta.magic_construct) |ctor| {
                            if (args_val) |av| {
                                if (av.isArray()) {
                                    const arr = av.asArray();
                                    const count = arr.elements.count();
                                    const real_args = try alloc.alloc(Value, count);
                                    defer alloc.free(real_args);
                                    var idx: usize = 0;
                                    while (idx < count) : (idx += 1) {
                                        real_args[idx] = arr.elements.get(ArrayKey{ .integer = @intCast(idx) }) orelse Value.initNull();
                                    }
                                    _ = try ctor(Value_initObject(obj), real_args, alloc);
                                } else {
                                    _ = try ctor(Value_initObject(obj), &.{}, alloc);
                                }
                            } else {
                                _ = try ctor(Value_initObject(obj), &.{}, alloc);
                            }
                        }
                        return Value_initObject(obj);
                    }
                    // Fallback: return stdClass with properties
                    const obj = try PHPObject.init(alloc, "stdClass");
                    if (name_val.isString()) try obj.setProperty("name", name_val.retain());
                    if (args_val) |av| try obj.setProperty("args", av.retain());
                    return Value_initObject(obj);
                }
            }.call,
            .is_static = false,
        });
        // getTarget() - read from stored __target property
        try attr_meta.addMethod(.{
            .name = "getTarget",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__target")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        // isRepeated() - read from stored __is_repeated property (defaults to false)
        try attr_meta.addMethod(.{
            .name = "isRepeated",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__is_repeated")) |v| {
                        return Value.initBool(v.toBool());
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try registerClass(attr_meta);

        // ReflectionClass
        const rc_meta = try ClassMeta.init(allocator, "ReflectionClass");
        try rc_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // 参数是类名字符串
                    const name_str = try args[0].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(name_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rc_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rc_meta.addMethod(.{
            .name = "getAttributes",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // 查找类元数据中的属性
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            const cname = name_val.asString().data;
                            if (findClass(cname)) |cmeta| {
                                // 从类元数据的 __attributes 读取
                                if (cmeta.static_properties.get("__attributes")) |attrs_val| {
                                    _ = attrs_val.retain();
                                    return attrs_val;
                                }
                            }
                        }
                    }
                    return Value.initArray(try PHPArray.init(alloc));
                }
            }.call,
            .is_static = false,
        });
        // isAbstract()
        try rc_meta.addMethod(.{
            .name = "isAbstract",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_abstract);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isFinal()
        try rc_meta.addMethod(.{
            .name = "isFinal",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_final);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isInstantiable()
        try rc_meta.addMethod(.{
            .name = "isInstantiable",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(!cmeta.is_abstract);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // hasMethod()
        try rc_meta.addMethod(.{
            .name = "hasMethod",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                if (args[0].isString()) {
                                    return Value.initBool(cmeta.methods.contains(args[0].asString().data));
                                }
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getMethod() - 返回 ReflectionMethod 对象
        try rc_meta.addMethod(.{
            .name = "getMethod",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString() or !args[0].isString()) return Value.initNull();
                    const cname = cname_val.asString().data;
                    const mname = args[0].asString().data;
                    if (findClass(cname)) |cmeta| {
                        if (cmeta.methods.contains(mname)) {
                            if (findClass("ReflectionMethod")) |rm_class| {
                                const rm_obj = try PHPObject.initWithMeta(alloc, rm_class);
                                try rm_obj.setProperty("__class_name", Value.initString(try PHPString.init(alloc, cname)));
                                try rm_obj.setProperty("__method_name", Value.initString(try PHPString.init(alloc, mname)));
                                return Value_initObject(rm_obj);
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getMethods() - 返回 ReflectionMethod 数组
        try rc_meta.addMethod(.{
            .name = "getMethods",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const cname = cname_val.asString().data;
                    const arr = try PHPArray.init(alloc);
                    if (findClass(cname)) |cmeta| {
                        var iter = cmeta.methods.iterator();
                        while (iter.next()) |entry| {
                            if (findClass("ReflectionMethod")) |rm_class| {
                                const rm_obj = try PHPObject.initWithMeta(alloc, rm_class);
                                try rm_obj.setProperty("__class_name", Value.initString(try PHPString.init(alloc, cname)));
                                try rm_obj.setProperty("__method_name", Value.initString(try PHPString.init(alloc, entry.key_ptr.*)));
                                try arr.push(alloc, Value_initObject(rm_obj));
                            }
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // hasProperty()
        try rc_meta.addMethod(.{
            .name = "hasProperty",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                if (args[0].isString()) {
                                    return Value.initBool(cmeta.properties.contains(args[0].asString().data));
                                }
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getProperties() - 返回 ReflectionProperty 对象数组
        try rc_meta.addMethod(.{
            .name = "getProperties",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const arr = try PHPArray.init(alloc);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        var iter = cmeta.properties.iterator();
                        while (iter.next()) |entry| {
                            if (findClass("ReflectionProperty")) |rp_cls| {
                                const rp_obj = try PHPObject.initWithMeta(alloc, rp_cls);
                                try rp_obj.setProperty("__class_name", cname_val);
                                _ = cname_val.retain();
                                try rp_obj.setProperty("__prop_name", Value.initString(try PHPString.init(alloc, entry.key_ptr.*)));
                                try arr.push(alloc, Value_initObject(rp_obj));
                            }
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // getProperty($name) - 返回单个 ReflectionProperty 对象
        try rc_meta.addMethod(.{
            .name = "getProperty",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString()) return Value.initNull();
                    const pname_str = try args[0].toString(alloc);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.properties.get(pname_str.data)) |_| {
                            if (findClass("ReflectionProperty")) |rp_cls| {
                                const rp_obj = try PHPObject.initWithMeta(alloc, rp_cls);
                                try rp_obj.setProperty("__class_name", cname_val);
                                _ = cname_val.retain();
                                try rp_obj.setProperty("__prop_name", Value.initString(pname_str));
                                return Value_initObject(rp_obj);
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // newInstance() - 创建类实例
        try rc_meta.addMethod(.{
            .name = "newInstance",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString()) return Value.initNull();
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.is_abstract) return Value.initNull();
                        const new_obj = try PHPObject.initWithMeta(alloc, cmeta);
                        if (cmeta.magic_construct) |ctor| {
                            _ = try ctor(Value_initObject(new_obj), args, alloc);
                        }
                        return Value_initObject(new_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // newInstanceArgs() - alias for newInstance
        try rc_meta.addMethod(.{
            .name = "newInstanceArgs",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString()) return Value.initNull();
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.is_abstract) return Value.initNull();
                        const new_obj = try PHPObject.initWithMeta(alloc, cmeta);
                        // 从数组参数中提取
                        if (args[0].isArray()) {
                            const arr = args[0].asArray();
                            const count = arr.elements.count();
                            const real_args = try alloc.alloc(Value, count);
                            defer alloc.free(real_args);
                            var idx: usize = 0;
                            while (idx < count) : (idx += 1) {
                                real_args[idx] = arr.elements.get(ArrayKey{ .integer = @intCast(idx) }) orelse Value.initNull();
                            }
                            if (cmeta.magic_construct) |ctor| {
                                _ = try ctor(Value_initObject(new_obj), real_args, alloc);
                            }
                        }
                        return Value_initObject(new_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getParentClass()
        try rc_meta.addMethod(.{
            .name = "getParentClass",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                if (cmeta.parent) |parent| {
                                    if (findClass("ReflectionClass")) |rc_class_meta| {
                                        const rc_obj = try PHPObject.initWithMeta(alloc, rc_class_meta);
                                        try rc_obj.setProperty("__class_name", Value.initString(try PHPString.init(alloc, parent.name)));
                                        return Value_initObject(rc_obj);
                                    }
                                }
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isClass() - returns true if not interface and not enum
        try rc_meta.addMethod(.{
            .name = "isClass",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(!cmeta.is_interface and !cmeta.is_enum);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isTrait()
        try rc_meta.addMethod(.{
            .name = "isTrait",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_trait);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isInterface()
        try rc_meta.addMethod(.{
            .name = "isInterface",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_interface);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getInterfaceNames()
        try rc_meta.addMethod(.{
            .name = "getInterfaceNames",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const arr = try PHPArray.init(alloc);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        for (cmeta.interfaces) |iface| {
                            try arr.push(alloc, Value.initString(try PHPString.init(alloc, iface)));
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // isEnum()
        try rc_meta.addMethod(.{
            .name = "isEnum",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_enum);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isSubclassOf()
        try rc_meta.addMethod(.{
            .name = "isSubclassOf",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    if (!cname_val.isString()) return Value.initBool(false);
                    const parent_name = if (args[0].isString()) args[0].asString().data else if (Value_isObject(args[0])) blk: {
                        const arg_obj = Value_asObject(args[0]);
                        const pn = arg_obj.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                        if (pn.isString()) break :blk pn.asString().data else return Value.initBool(false);
                    } else return Value.initBool(false);
                    _ = alloc;
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        var cur = cmeta.parent;
                        while (cur) |p| {
                            if (std.mem.eql(u8, p.name, parent_name)) return Value.initBool(true);
                            cur = p.parent;
                        }
                        for (cmeta.interfaces) |iface| {
                            if (std.mem.eql(u8, iface, parent_name)) return Value.initBool(true);
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // implementsInterface()
        try rc_meta.addMethod(.{
            .name = "implementsInterface",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    if (!cname_val.isString()) return Value.initBool(false);
                    const iface_name = if (args[0].isString()) args[0].asString().data else return Value.initBool(false);
                    _ = alloc;
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        for (cmeta.interfaces) |iface| {
                            if (std.mem.eql(u8, iface, iface_name)) return Value.initBool(true);
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getConstant()
        try rc_meta.addMethod(.{
            .name = "getConstant",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    if (!cname_val.isString() or !args[0].isString()) return Value.initBool(false);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.static_properties.get(args[0].asString().data)) |val| {
                            return val.retain();
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // hasConstant()
        try rc_meta.addMethod(.{
            .name = "hasConstant",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    if (!cname_val.isString() or !args[0].isString()) return Value.initBool(false);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        return Value.initBool(cmeta.static_properties.contains(args[0].asString().data));
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getConstants()
        try rc_meta.addMethod(.{
            .name = "getConstants",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const arr = try PHPArray.init(alloc);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        var iter = cmeta.static_properties.iterator();
                        while (iter.next()) |entry| {
                            const key = entry.key_ptr.*;
                            if (key.len > 0 and key[0] != '_') {
                                try arr.set(alloc, ArrayKey{ .string = try PHPString.init(alloc, key) }, entry.value_ptr.*.retain());
                            }
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // getConstructor() - 返回 __construct 的 ReflectionMethod 或 null
        try rc_meta.addMethod(.{
            .name = "getConstructor",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString()) return Value.initNull();
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.methods.get("__construct") != null) {
                            if (findClass("ReflectionMethod")) |rm_cls| {
                                const rm_obj = try PHPObject.initWithMeta(alloc, rm_cls);
                                try rm_obj.setProperty("__class_name", Value.initString(try PHPString.init(alloc, cname_val.asString().data)));
                                try rm_obj.setProperty("__method_name", Value.initString(try PHPString.init(alloc, "__construct")));
                                return Value_initObject(rm_obj);
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        rc_meta.magic_construct = rc_meta.methods.get("__construct").?.func;
        try registerClass(rc_meta);

        // ReflectionEnum (extends ReflectionClass behavior)
        const re_meta = try ClassMeta.init(allocator, "ReflectionEnum");
        try re_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const name_str = try args[0].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(name_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try re_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        re_meta.magic_construct = re_meta.methods.get("__construct").?.func;
        try registerClass(re_meta);

        // ReflectionClassConstant
        const rcc_meta = try ClassMeta.init(allocator, "ReflectionClassConstant");
        try rcc_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len < 2) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const class_str = try args[0].toString(alloc);
                    const const_str = try args[1].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(class_str));
                    try this.setProperty("__const_name", Value.initString(const_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rcc_meta.addMethod(.{
            .name = "getValue",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const kname_val = this.getPropertyDirect("__const_name") orelse return Value.initNull();
                    if (!cname_val.isString() or !kname_val.isString()) return Value.initNull();
                    const cname = cname_val.asString().data;
                    const kname = kname_val.asString().data;
                    // 查找类常量: "ClassName::CONST"
                    var buf: [512]u8 = undefined;
                    const full_key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ cname, kname }) catch return Value.initNull();
                    if (constants.get(full_key)) |val| {
                        _ = val.retain();
                        return val;
                    }
                    // 尝试从类元数据的静态属性获取
                    if (findClass(cname)) |cmeta| {
                        if (cmeta.static_properties.get(kname)) |val| {
                            _ = val.retain();
                            return val;
                        }
                    }
                    _ = alloc;
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rcc_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__const_name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        rcc_meta.magic_construct = rcc_meta.methods.get("__construct").?.func;
        try registerClass(rcc_meta);

        // ReflectionNamedType - PHP ReflectionNamedType 类
        const rnt_meta = try ClassMeta.init(allocator, "ReflectionNamedType");
        // getName() - 返回类型名称字符串
        try rnt_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__type_name")) |v| { _ = v.retain(); return v; }
                    return Value.initString(try PHPString.init(alloc, ""));
                }
            }.call,
            .is_static = false,
        });
        // allowsNull() - 类型是否允许 null
        try rnt_meta.addMethod(.{
            .name = "allowsNull",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__allows_null")) |v| return Value.initBool(v.toBool());
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isBuiltin() - 是否是内置类型
        try rnt_meta.addMethod(.{
            .name = "isBuiltin",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__is_builtin")) |v| return Value.initBool(v.toBool());
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // __toString() - 返回类型名称
        try rnt_meta.addMethod(.{
            .name = "__toString",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__type_name")) |v| { _ = v.retain(); return v; }
                    return Value.initString(try PHPString.init(alloc, ""));
                }
            }.call,
            .is_static = false,
        });
        try registerClass(rnt_meta);

        // ReflectionUnionType - PHP ReflectionUnionType 类
        const rut_meta = try ClassMeta.init(allocator, "ReflectionUnionType");
        // getTypes() - 返回 ReflectionNamedType 对象数组
        try rut_meta.addMethod(.{
            .name = "getTypes",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__types")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // allowsNull()
        try rut_meta.addMethod(.{
            .name = "allowsNull",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__allows_null")) |v| return v;
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // __toString() - 拼接子类型名 "int|string"
        try rut_meta.addMethod(.{
            .name = "__toString",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    const types_val = this.getPropertyDirect("__types") orelse return Value.initString(try PHPString.init(alloc, ""));
                    if (!types_val.isArray()) return Value.initString(try PHPString.init(alloc, ""));
                    const arr = types_val.asArray();
                    var buf: [1024]u8 = undefined;
                    var pos: usize = 0;
                    var idx: usize = 0;
                    const count = arr.count();
                    while (idx < count) : (idx += 1) {
                        const sub = arr.getByIndex(idx) orelse continue;
                        if (Value_isObject(sub)) {
                            const sub_obj = Value_asObject(sub);
                            if (sub_obj.getPropertyDirect("__type_name")) |tn| {
                                if (tn.isString()) {
                                    const tname = tn.asString().data;
                                    if (idx > 0 and pos < buf.len) {
                                        buf[pos] = '|';
                                        pos += 1;
                                    }
                                    const end = @min(pos + tname.len, buf.len);
                                    @memcpy(buf[pos..end], tname[0..end - pos]);
                                    pos = end;
                                }
                            }
                        }
                    }
                    return Value.initString(try PHPString.init(alloc, buf[0..pos]));
                }
            }.call,
            .is_static = false,
        });
        try registerClass(rut_meta);

        // ReflectionIntersectionType - PHP ReflectionIntersectionType 类
        const rit_meta = try ClassMeta.init(allocator, "ReflectionIntersectionType");
        // getTypes()
        try rit_meta.addMethod(.{
            .name = "getTypes",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__types")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // allowsNull() - intersection types 永远不允许 null
        try rit_meta.addMethod(.{
            .name = "allowsNull",
            .func = struct {
                fn call(_: Value, _: []const Value, _: Allocator) anyerror!Value {
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // __toString() - 拼接 "A&B"
        try rit_meta.addMethod(.{
            .name = "__toString",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    const types_val = this.getPropertyDirect("__types") orelse return Value.initString(try PHPString.init(alloc, ""));
                    if (!types_val.isArray()) return Value.initString(try PHPString.init(alloc, ""));
                    const arr = types_val.asArray();
                    var buf: [1024]u8 = undefined;
                    var pos: usize = 0;
                    var idx: usize = 0;
                    const count = arr.count();
                    while (idx < count) : (idx += 1) {
                        const sub = arr.getByIndex(idx) orelse continue;
                        if (Value_isObject(sub)) {
                            const sub_obj = Value_asObject(sub);
                            if (sub_obj.getPropertyDirect("__type_name")) |tn| {
                                if (tn.isString()) {
                                    const tname = tn.asString().data;
                                    if (idx > 0 and pos < buf.len) {
                                        buf[pos] = '&';
                                        pos += 1;
                                    }
                                    const end = @min(pos + tname.len, buf.len);
                                    @memcpy(buf[pos..end], tname[0..end - pos]);
                                    pos = end;
                                }
                            }
                        }
                    }
                    return Value.initString(try PHPString.init(alloc, buf[0..pos]));
                }
            }.call,
            .is_static = false,
        });
        try registerClass(rit_meta);

        // ReflectionMethod
        const rm_meta = try ClassMeta.init(allocator, "ReflectionMethod");
        try rm_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len < 2) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const class_str = try args[0].toString(alloc);
                    const method_str = try args[1].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(class_str));
                    try this.setProperty("__method_name", Value.initString(method_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__method_name")) |v| { _ = v.retain(); return v; }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "getDeclaringClass",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (findClass("ReflectionClass")) |rc_cls| {
                        const rc_obj = try PHPObject.initWithMeta(alloc, rc_cls);
                        try rc_obj.setProperty("__class_name", cname_val);
                        _ = cname_val.retain();
                        return Value_initObject(rc_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "isPublic",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(true);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(true);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_public);
                            }
                        }
                    }
                    return Value.initBool(true);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "isStatic",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_static);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "isConstructor",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__method_name")) |v| {
                        if (v.isString()) return Value.initBool(std.mem.eql(u8, v.asString().data, "__construct"));
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "getNumberOfParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initInt(0);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initInt(0);
                    if (cname_val.isString() and mname_val.isString()) {
                        // 优先从 ClassMethod 元数据读取
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initInt(@intCast(m.param_count));
                            }
                        }
                        // 回退到 function_meta_registry
                        const full_name_buf = std.fmt.allocPrint(std.heap.page_allocator, "{s}::{s}", .{ cname_val.asString().data, mname_val.asString().data }) catch return Value.initInt(0);
                        defer std.heap.page_allocator.free(full_name_buf);
                        if (function_meta_registry) |meta_reg| {
                            if (meta_reg.get(full_name_buf)) |meta| {
                                return Value.initInt(@intCast(meta.param_count));
                            }
                        }
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "getNumberOfRequiredParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initInt(0);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initInt(0);
                    if (cname_val.isString() and mname_val.isString()) {
                        // 优先从 ClassMethod 元数据读取
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initInt(@intCast(m.required_params));
                            }
                        }
                        // 回退到 function_meta_registry
                        const full_name_buf = std.fmt.allocPrint(std.heap.page_allocator, "{s}::{s}", .{ cname_val.asString().data, mname_val.asString().data }) catch return Value.initInt(0);
                        defer std.heap.page_allocator.free(full_name_buf);
                        if (function_meta_registry) |meta_reg| {
                            if (meta_reg.get(full_name_buf)) |meta| {
                                return Value.initInt(@intCast(meta.required_params));
                            }
                        }
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "invoke",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initNull();
                    if (!cname_val.isString() or !mname_val.isString()) return Value.initNull();
                    // args[0] = object, args[1..] = method args
                    if (Value_isObject(args[0])) {
                        const obj = Value_asObject(args[0]);
                        return obj.callMethod(mname_val.asString().data, args[1..]) catch Value.initNull();
                    }
                    _ = alloc;
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getParameters() - return array of ReflectionParameter from real ClassMethod metadata
        try rm_meta.addMethod(.{
            .name = "getParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString() or !mname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const arr = try PHPArray.init(alloc);
                    // 优先从 ClassMethod 元数据获取参数信息
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.methods.get(mname_val.asString().data)) |m| {
                            var i: usize = 0;
                            while (i < m.param_count) : (i += 1) {
                                if (findClass("ReflectionParameter")) |rp_cls| {
                                    const rp_obj = try PHPObject.initWithMeta(alloc, rp_cls);
                                    try rp_obj.setProperty("__position", Value.initInt(@intCast(i)));
                                    if (i < m.param_names.len) {
                                        try rp_obj.setProperty("__name", Value.initString(try PHPString.init(alloc, m.param_names[i])));
                                    }
                                    // 设置参数类型信息
                                    if (i < m.param_types.len and m.param_types[i].len > 0) {
                                        try rp_obj.setProperty("__type_name", Value.initString(try PHPString.init(alloc, m.param_types[i])));
                                        try rp_obj.setProperty("__has_type", Value.initBool(true));
                                    } else {
                                        try rp_obj.setProperty("__has_type", Value.initBool(false));
                                    }
                                    // 设置 nullable 信息
                                    if (i < m.param_nullable.len) {
                                        try rp_obj.setProperty("__allows_null", Value.initBool(m.param_nullable[i]));
                                    }
                                    try arr.push(alloc, Value_initObject(rp_obj));
                                }
                            }
                            return Value.initArray(arr);
                        }
                    }
                    // 回退到 function_meta_registry
                    const full_name_buf = std.fmt.allocPrint(std.heap.page_allocator, "{s}::{s}", .{ cname_val.asString().data, mname_val.asString().data }) catch return Value.initArray(arr);
                    defer std.heap.page_allocator.free(full_name_buf);
                    if (function_meta_registry) |meta_reg| {
                        if (meta_reg.get(full_name_buf)) |meta| {
                            var i: usize = 0;
                            while (i < meta.param_count) : (i += 1) {
                                if (findClass("ReflectionParameter")) |rp_cls| {
                                    const rp_obj = try PHPObject.initWithMeta(alloc, rp_cls);
                                    try rp_obj.setProperty("__position", Value.initInt(@intCast(i)));
                                    if (i < meta.param_names.len) {
                                        try rp_obj.setProperty("__name", Value.initString(try PHPString.init(alloc, meta.param_names[i])));
                                    }
                                    try arr.push(alloc, Value_initObject(rp_obj));
                                }
                            }
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // getReturnType() - 从 ClassMethod.return_type 读取真实类型声明
        try rm_meta.addMethod(.{
            .name = "getReturnType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initNull();
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                if (m.return_type) |rt| {
                                    // 创建 ReflectionNamedType 对象
                                    if (findClass("ReflectionNamedType")) |rt_cls| {
                                        const rt_obj = try PHPObject.initWithMeta(alloc, rt_cls);
                                        try rt_obj.setProperty("__type_name", Value.initString(try PHPString.init(alloc, rt)));
                                        try rt_obj.setProperty("__allows_null", Value.initBool(m.return_nullable));
                                        try rt_obj.setProperty("__is_builtin", Value.initBool(isBuiltinType(rt)));
                                        return Value_initObject(rt_obj);
                                    }
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // hasReturnType() - 从 ClassMethod.return_type 读取
        try rm_meta.addMethod(.{
            .name = "hasReturnType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.return_type != null);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isAbstract() - read from real ClassMethod.is_abstract
        try rm_meta.addMethod(.{
            .name = "isAbstract",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_abstract);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isFinal() - read from real ClassMethod.is_final
        try rm_meta.addMethod(.{
            .name = "isFinal",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_final);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isPrivate() - read from real ClassMethod.is_private
        try rm_meta.addMethod(.{
            .name = "isPrivate",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_private);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isProtected() - read from real ClassMethod.is_protected
        try rm_meta.addMethod(.{
            .name = "isProtected",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_protected);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getModifiers() - 返回 PHP 标准修饰符位掩码
        try rm_meta.addMethod(.{
            .name = "getModifiers",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(1); // IS_PUBLIC
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initInt(1);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initInt(1);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                var flags: i64 = 0;
                                if (m.is_public) flags |= 1; // IS_PUBLIC
                                if (m.is_protected) flags |= 2; // IS_PROTECTED
                                if (m.is_private) flags |= 4; // IS_PRIVATE
                                if (m.is_static) flags |= 16; // IS_STATIC
                                if (m.is_final) flags |= 32; // IS_FINAL
                                if (m.is_abstract) flags |= 64; // IS_ABSTRACT
                                return Value.initInt(flags);
                            }
                        }
                    }
                    return Value.initInt(1); // default: IS_PUBLIC
                }
            }.call,
            .is_static = false,
        });
        rm_meta.magic_construct = rm_meta.methods.get("__construct").?.func;
        try registerClass(rm_meta);

        // ReflectionParameter
        const rp_meta = try ClassMeta.init(allocator, "ReflectionParameter");
        try rp_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len < 2) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const func_str = try args[0].toString(alloc);
                    try this.setProperty("__func_name", Value.initString(func_str));
                    if (args[1].isInt()) {
                        try this.setProperty("__position", args[1]);
                    } else {
                        const pname = try args[1].toString(alloc);
                        try this.setProperty("__name", Value.initString(pname));
                        try this.setProperty("__position", Value.initInt(0));
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__name")) |v| { _ = v.retain(); return v; }
                    // Fallback: generate name from position
                    const pos_val = this.getPropertyDirect("__position") orelse return Value.initString(try PHPString.init(alloc, "param0"));
                    const pos = pos_val.toInt();
                    const name = try std.fmt.allocPrint(alloc, "param{d}", .{pos});
                    return Value.initString(try PHPString.init(alloc, name));
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "getPosition",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__position")) |v| return v;
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "isOptional",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__is_optional")) |v| return v;
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "hasDefaultValue",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__has_default")) |v| return v;
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "isVariadic",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__is_variadic")) |v| return v;
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "allowsNull",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(true);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__allows_null")) |v| return Value.initBool(v.toBool());
                    // 无类型约束时默认允许null（与PHP行为一致）
                    return Value.initBool(true);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "hasType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__has_type")) |v| return Value.initBool(v.toBool());
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getType() - 返回 ReflectionNamedType 对象或 null
        try rp_meta.addMethod(.{
            .name = "getType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const has_type_val = this.getPropertyDirect("__has_type") orelse return Value.initNull();
                    if (!has_type_val.toBool()) return Value.initNull();
                    const type_name_val = this.getPropertyDirect("__type_name") orelse return Value.initNull();
                    if (!type_name_val.isString()) return Value.initNull();
                    const allows_null_val = this.getPropertyDirect("__allows_null");
                    const allows_null = if (allows_null_val) |v| v.toBool() else true;
                    // 创建 ReflectionNamedType 对象
                    if (findClass("ReflectionNamedType")) |rt_cls| {
                        const rt_obj = try PHPObject.initWithMeta(alloc, rt_cls);
                        try rt_obj.setProperty("__type_name", type_name_val);
                        _ = type_name_val.retain();
                        try rt_obj.setProperty("__allows_null", Value.initBool(allows_null));
                        try rt_obj.setProperty("__is_builtin", Value.initBool(isBuiltinType(type_name_val.asString().data)));
                        return Value_initObject(rt_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        rp_meta.magic_construct = rp_meta.methods.get("__construct").?.func;
        try registerClass(rp_meta);

        // ReflectionProperty - PHP ReflectionProperty 类
        const rprop_meta = try ClassMeta.init(allocator, "ReflectionProperty");
        try rprop_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len < 2) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const class_str = try args[0].toString(alloc);
                    const prop_str = try args[1].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(class_str));
                    try this.setProperty("__prop_name", Value.initString(prop_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getName()
        try rprop_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__prop_name")) |v| { _ = v.retain(); return v; }
                    return Value.initString(try PHPString.init(alloc, ""));
                }
            }.call,
            .is_static = false,
        });
        // getDeclaringClass()
        try rprop_meta.addMethod(.{
            .name = "getDeclaringClass",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname.isString()) return Value.initNull();
                    if (findClass("ReflectionClass")) |rc_cls| {
                        const rc_obj = try PHPObject.initWithMeta(alloc, rc_cls);
                        try rc_obj.setProperty("__class_name", cname);
                        _ = cname.retain();
                        return Value_initObject(rc_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getValue($object) - 支持实例属性和 static 属性
        try rprop_meta.addMethod(.{
            .name = "getValue",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initNull();
                    if (!pname_val.isString()) return Value.initNull();
                    const pname = pname_val.asString().data;
                    // 先检查是否是 static 属性
                    if (cname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname)) |p| {
                                if (p.is_static) {
                                    if (cmeta.static_properties.get(pname)) |sv| {
                                        _ = sv.retain();
                                        return sv;
                                    }
                                    return Value.initNull();
                                }
                            }
                        }
                    }
                    // 实例属性
                    if (args.len > 0 and Value_isObject(args[0])) {
                        const target = Value_asObject(args[0]);
                        if (target.getPropertyDirect(pname)) |v| {
                            _ = v.retain();
                            return v;
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // setValue($object, $value) - 支持实例属性和 static 属性
        try rprop_meta.addMethod(.{
            .name = "setValue",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initNull();
                    if (!pname_val.isString()) return Value.initNull();
                    const pname = pname_val.asString().data;
                    // static 属性：setValue($value) 只需1个参数
                    if (cname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname)) |p| {
                                if (p.is_static) {
                                    const val = if (args.len >= 1) args[0] else Value.initNull();
                                    _ = val.retain();
                                    cmeta.static_properties.getPtr(pname).?.* = val;
                                    return Value.initNull();
                                }
                            }
                        }
                    }
                    // 实例属性：setValue($object, $value) 需2个参数
                    if (args.len >= 2 and Value_isObject(args[0])) {
                        const target = Value_asObject(args[0]);
                        _ = args[1].retain();
                        try target.setProperty(pname, args[1]);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // isPublic/isProtected/isPrivate/isStatic/isReadOnly/isDefault
        inline for (.{
            .{ "isPublic", "is_public" },
            .{ "isProtected", "is_protected" },
            .{ "isPrivate", "is_private" },
            .{ "isStatic", "is_static" },
            .{ "isReadOnly", "is_readonly" },
            .{ "isDefault", "has_default" },
        }) |pair| {
            try rprop_meta.addMethod(.{
                .name = pair[0],
                .func = struct {
                    fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                        if (!Value_isObject(ctx)) return Value.initBool(false);
                        const this = Value_asObject(ctx);
                        const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                        const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initBool(false);
                        if (cname_val.isString() and pname_val.isString()) {
                            if (findClass(cname_val.asString().data)) |cmeta| {
                                if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                    return Value.initBool(@field(p, pair[1]));
                                }
                            }
                        }
                        return Value.initBool(false);
                    }
                }.call,
                .is_static = false,
            });
        }
        // hasType()
        try rprop_meta.addMethod(.{
            .name = "hasType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                return Value.initBool(p.type_name != null);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getType() - 返回 ReflectionNamedType 或 null
        try rprop_meta.addMethod(.{
            .name = "getType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initNull();
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                if (p.type_name) |tn| {
                                    if (findClass("ReflectionNamedType")) |rt_cls| {
                                        const rt_obj = try PHPObject.initWithMeta(alloc, rt_cls);
                                        try rt_obj.setProperty("__type_name", Value.initString(try PHPString.init(alloc, tn)));
                                        try rt_obj.setProperty("__allows_null", Value.initBool(p.type_nullable));
                                        try rt_obj.setProperty("__is_builtin", Value.initBool(isBuiltinType(tn)));
                                        return Value_initObject(rt_obj);
                                    }
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // hasDefaultValue()
        try rprop_meta.addMethod(.{
            .name = "hasDefaultValue",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                return Value.initBool(p.has_default);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getDefaultValue()
        try rprop_meta.addMethod(.{
            .name = "getDefaultValue",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initNull();
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                if (p.default_value) |dv| {
                                    _ = dv.retain();
                                    return dv;
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getModifiers() - 返回 PHP 标准属性修饰符位掩码
        try rprop_meta.addMethod(.{
            .name = "getModifiers",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(1); // IS_PUBLIC
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initInt(1);
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initInt(1);
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                var flags: i64 = 0;
                                if (p.is_public) flags |= 1; // IS_PUBLIC
                                if (p.is_protected) flags |= 2; // IS_PROTECTED
                                if (p.is_private) flags |= 4; // IS_PRIVATE
                                if (p.is_static) flags |= 16; // IS_STATIC
                                if (p.is_readonly) flags |= 128; // IS_READONLY
                                return Value.initInt(flags);
                            }
                        }
                    }
                    return Value.initInt(1); // default: IS_PUBLIC
                }
            }.call,
            .is_static = false,
        });
        // isDefault() - 通过 Reflection 获取的属性都是在类定义中声明的
        try rprop_meta.addMethod(.{
            .name = "isDefault",
            .func = struct {
                fn call(_: Value, _: []const Value, _: Allocator) anyerror!Value {
                    return Value.initBool(true);
                }
            }.call,
            .is_static = false,
        });
        rprop_meta.magic_construct = rprop_meta.methods.get("__construct").?.func;
        try registerClass(rprop_meta);

        // ReflectionFunction
        const rf_meta = try ClassMeta.init(allocator, "ReflectionFunction");
        try rf_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    var pc: i64 = 0;
                    var rp: i64 = 0;
                    if (args[0].isFunction()) {
                        // 闭包/callable 对象
                        const closure = args[0].asFunction();
                        pc = @intCast(closure.param_count);
                        rp = @intCast(closure.required_params);
                        try this.setProperty("__func_name", Value.initString(try PHPString.init(alloc, "{closure}")));
                        try this.setProperty("__closure", args[0]);
                        _ = args[0].retain();
                    } else {
                        // 函数名字符串
                        const name_str = try args[0].toString(alloc);
                        try this.setProperty("__func_name", Value.initString(name_str));
                        // 从元数据注册表查询参数信息
                        if (function_meta_registry) |meta_reg| {
                            const name_data = args[0].asString().data;
                            if (meta_reg.get(name_data)) |meta| {
                                pc = @intCast(meta.param_count);
                                rp = @intCast(meta.required_params);
                            }
                        }
                    }
                    try this.setProperty("__param_count", Value.initInt(pc));
                    try this.setProperty("__required_params", Value.initInt(rp));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rf_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__func_name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rf_meta.addMethod(.{
            .name = "getNumberOfParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__param_count")) |v| {
                        return v;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        try rf_meta.addMethod(.{
            .name = "getNumberOfRequiredParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__required_params")) |v| {
                        return v;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        // invoke() - 调用反射的函数
        try rf_meta.addMethod(.{
            .name = "invoke",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // 优先使用存储的闭包
                    if (this.getPropertyDirect("__closure")) |closure_val| {
                        if (closure_val.isFunction()) {
                            const closure = closure_val.asFunction();
                            return closure.func(closure_val, args, alloc);
                        }
                    }
                    // 通过函数名查找
                    if (this.getPropertyDirect("__func_name")) |name_val| {
                        if (name_val.isString()) {
                            const func_name = name_val.asString().data;
                            if (user_function_registry) |reg| {
                                if (reg.get(func_name)) |func| {
                                    return func(Value.initNull(), args, alloc);
                                }
                            }
                            if (aot_callable_hook) |hook| {
                                return hook(func_name, args, alloc);
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // invokeArgs() - 以数组方式传参调用
        try rf_meta.addMethod(.{
            .name = "invokeArgs",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // 从数组参数中提取实际参数
                    if (args[0].isArray()) {
                        const arr = args[0].asArray();
                        const count = arr.elements.count();
                        const real_args = try alloc.alloc(Value, count);
                        defer alloc.free(real_args);
                        var idx: usize = 0;
                        while (idx < count) : (idx += 1) {
                            const key = ArrayKey{ .integer = @intCast(idx) };
                            real_args[idx] = arr.elements.get(key) orelse Value.initNull();
                        }
                        // 复用 invoke 逻辑
                        if (this.getPropertyDirect("__closure")) |closure_val| {
                            if (closure_val.isFunction()) {
                                const closure = closure_val.asFunction();
                                return closure.func(closure_val, real_args, alloc);
                            }
                        }
                        if (this.getPropertyDirect("__func_name")) |name_val| {
                            if (name_val.isString()) {
                                const func_name = name_val.asString().data;
                                if (user_function_registry) |reg| {
                                    if (reg.get(func_name)) |func| {
                                        return func(Value.initNull(), real_args, alloc);
                                    }
                                }
                                if (aot_callable_hook) |hook| {
                                    return hook(func_name, real_args, alloc);
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // isClosure()
        try rf_meta.addMethod(.{
            .name = "isClosure",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__closure")) |v| {
                        return Value.initBool(v.isFunction());
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isUserDefined() - check if function is user-defined (not a builtin)
        try rf_meta.addMethod(.{
            .name = "isUserDefined",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(true);
                    const this = Value_asObject(ctx);
                    // 闭包始终是用户定义的
                    if (this.getPropertyDirect("__closure")) |v| {
                        if (v.isFunction()) return Value.initBool(true);
                    }
                    // 从函数名判断：如果存在于用户函数注册表中则为用户定义
                    if (this.getPropertyDirect("__func_name")) |name_val| {
                        if (name_val.isString()) {
                            if (user_function_registry) |reg| {
                                if (reg.get(name_val.asString().data) != null) return Value.initBool(true);
                            }
                        }
                    }
                    // AOT编译的函数都是用户定义的
                    return Value.initBool(true);
                }
            }.call,
            .is_static = false,
        });
        // isInternal() - opposite of isUserDefined
        try rf_meta.addMethod(.{
            .name = "isInternal",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__closure")) |v| {
                        if (v.isFunction()) return Value.initBool(false);
                    }
                    if (this.getPropertyDirect("__func_name")) |name_val| {
                        if (name_val.isString()) {
                            if (user_function_registry) |reg| {
                                if (reg.get(name_val.asString().data) != null) return Value.initBool(false);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getParameters() - 返回 ReflectionParameter 数组
        try rf_meta.addMethod(.{
            .name = "getParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const pc_val = this.getPropertyDirect("__param_count") orelse return Value.initArray(try PHPArray.init(alloc));
                    const pc = pc_val.toInt();
                    const arr = try PHPArray.init(alloc);
                    var i: i64 = 0;
                    while (i < pc) : (i += 1) {
                        // 创建 ReflectionParameter 对象
                        if (findClass("ReflectionParameter")) |_| {
                            const param_obj = try PHPObject.init(alloc, "ReflectionParameter");
                            try param_obj.setProperty("__position", Value.initInt(i));
                            const param_name = try std.fmt.allocPrint(alloc, "param{d}", .{i});
                            try param_obj.setProperty("__name", Value.initString(try PHPString.init(alloc, param_name)));
                            try arr.push(alloc, Value_initObject(param_obj));
                        } else {
                            // 没注册 ReflectionParameter，返回 position 整数
                            try arr.push(alloc, Value.initInt(i));
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // getReturnType() - 简化实现，返回 null
        try rf_meta.addMethod(.{
            .name = "getReturnType",
            .func = struct {
                fn call(_: Value, _: []const Value, _: Allocator) anyerror!Value {
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // hasReturnType()
        try rf_meta.addMethod(.{
            .name = "hasReturnType",
            .func = struct {
                fn call(_: Value, _: []const Value, _: Allocator) anyerror!Value {
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        rf_meta.magic_construct = rf_meta.methods.get("__construct").?.func;
        try registerClass(rf_meta);

        // Register Fiber class
        try registerFiberClass(allocator);
    }

    /// Fiber 协程状态
    const FiberState = enum(u8) {
        created,
        running,
        suspended,
        terminated,
    };

    /// Fiber 协程上下文 (线程 + 条件变量实现)
    const FiberContext = struct {
        mutex: std.Io.Mutex = .init,
        caller_cond: std.Io.Condition = .init,
        fiber_cond: std.Io.Condition = .init,
        state: FiberState = .created,
        callback: Value = Value.initNull(),
        fiber_obj: Value = Value.initNull(),
        suspend_value: Value = Value.initNull(),
        resume_value: Value = Value.initNull(),
        return_value: Value = Value.initNull(),
        throw_exception: Value = Value.initNull(),
        thread: ?std.Thread = null,
        alloc: Allocator,

        fn init(alloc: Allocator) !*FiberContext {
            const ctx = try alloc.create(FiberContext);
            ctx.* = .{ .alloc = alloc };
            return ctx;
        }
    };

    /// 当前正在执行的 Fiber 对象（线程局部）
    threadlocal var current_fiber_obj: ?Value = null;

    fn fiberThreadMain(fctx: *FiberContext) void {
        // 在 fiber 线程中设置 threadlocal
        current_fiber_obj = fctx.fiber_obj;

        while (!fctx.mutex.tryLock()) std.atomic.spinLoopHint();
        while (fctx.state != .running) {
            fctx.fiber_cond.wait(getIo(), &fctx.mutex) catch {};
        }
        fctx.mutex.unlock();

        // 通过闭包函数指针调用 fiber 回调
        const cb = fctx.callback;
        var result = Value.initNull();
        if (cb.isFunction()) {
            const closure = cb.asFunction();
            result = closure.func(
                cb,
                &[_]Value{},
                fctx.alloc,
            ) catch Value.initNull();
        }

        while (!fctx.mutex.tryLock()) std.atomic.spinLoopHint();
        fctx.return_value = result;
        fctx.state = .terminated;
        fctx.caller_cond.signal(getIo());
        fctx.mutex.unlock();
    }

    /// Register built-in Fiber class
    fn registerFiberClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "Fiber");

        // __construct(callable $callback)
        try meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(
                    ctx: Value,
                    args: []const Value,
                    alloc: Allocator,
                ) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    _ = args[0].retain();
                    try this.setProperty("__callback", args[0]);
                    try this.setProperty(
                        "__state",
                        Value.initInt(
                            @intFromEnum(FiberState.created),
                        ),
                    );
                    // 创建 FiberContext
                    const fctx = try FiberContext.init(alloc);
                    fctx.callback = args[0];
                    try this.setProperty(
                        "__fctx_addr",
                        Value.initInt(
                            @as(i64, @intCast(@intFromPtr(fctx))),
                        ),
                    );
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // start(...$args): mixed
        try meta.addMethod(.{
            .name = "start",
            .func = struct {
                fn call(
                    ctx: Value,
                    args: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    const this = Value_asObject(ctx);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    while (!fctx.mutex.tryLock()) std.atomic.spinLoopHint();
                    if (fctx.state != .created) {
                        fctx.mutex.unlock();
                        return Value.initNull();
                    }
                    if (args.len > 0) {
                        fctx.resume_value = args[0];
                    }
                    // fiber 线程通过 threadlocal 获取
                    fctx.fiber_obj = ctx;
                    fctx.state = .running;
                    // 启动线程
                    fctx.thread = std.Thread.spawn(
                        .{},
                        fiberThreadMain,
                        .{fctx},
                    ) catch {
                        fctx.mutex.unlock();
                        return Value.initNull();
                    };
                    // 信号唤醒 fiber 线程
                    fctx.fiber_cond.signal(getIo());
                    // 等待 fiber suspend 或 terminate
                    while (fctx.state == .running) {
                        fctx.caller_cond.wait(getIo(), &fctx.mutex) catch {};
                    }
                    const result = fctx.suspend_value;
                    fctx.suspend_value = Value.initNull();
                    setFiberState(this, fctx.state);
                    fctx.mutex.unlock();
                    if (fctx.state == .terminated) {
                        if (fctx.thread) |t| t.join();
                        fctx.thread = null;
                    }
                    return result;
                }
            }.call,
            .is_static = false,
        });

        // resume($value = null): mixed
        try meta.addMethod(.{
            .name = "resume",
            .func = struct {
                fn call(
                    ctx: Value,
                    args: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    const this = Value_asObject(ctx);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    while (!fctx.mutex.tryLock()) std.atomic.spinLoopHint();
                    if (fctx.state != .suspended) {
                        fctx.mutex.unlock();
                        return Value.initNull();
                    }
                    if (args.len > 0) {
                        fctx.resume_value = args[0];
                    } else {
                        fctx.resume_value = Value.initNull();
                    }
                    fctx.state = .running;
                    fctx.fiber_cond.signal(getIo());
                    while (fctx.state == .running) {
                        fctx.caller_cond.wait(getIo(), &fctx.mutex) catch {};
                    }
                    const result = fctx.suspend_value;
                    fctx.suspend_value = Value.initNull();
                    setFiberState(this, fctx.state);
                    fctx.mutex.unlock();
                    if (fctx.state == .terminated) {
                        if (fctx.thread) |t| t.join();
                        fctx.thread = null;
                    }
                    return result;
                }
            }.call,
            .is_static = false,
        });

        // Fiber::suspend($value = null): mixed (static)
        try meta.addMethod(.{
            .name = "suspend",
            .func = struct {
                fn call(
                    _: Value,
                    args: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    // 获取当前 fiber 上下文
                    const fiber_val = current_fiber_obj orelse
                        return Value.initNull();
                    if (!Value_isObject(fiber_val))
                        return Value.initNull();
                    const this = Value_asObject(fiber_val);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    while (!fctx.mutex.tryLock()) std.atomic.spinLoopHint();
                    if (args.len > 0) {
                        fctx.suspend_value = args[0];
                    }
                    fctx.state = .suspended;
                    fctx.caller_cond.signal(getIo());
                    // 等待 resume 或 throw
                    while (fctx.state == .suspended) {
                        fctx.fiber_cond.wait(getIo(), &fctx.mutex) catch {};
                    }
                    const result = fctx.resume_value;
                    fctx.resume_value = Value.initNull();
                    // 检查是否有 throw 传入的异常
                    const thrown = fctx.throw_exception;
                    fctx.throw_exception = Value.initNull();
                    fctx.mutex.unlock();
                    // 在 fiber 线程设置异常（不返回 Zig 错误，
                    // 由生成代码的 hasException() 路由到 catch）
                    if (!thrown.isNull()) {
                        setException(thrown);
                        return Value.initNull();
                    }
                    return result;
                }
            }.call,
            .is_static = true,
        });

        // isStarted(): bool
        try meta.addMethod(.{
            .name = "isStarted",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    const s = getFiberState(ctx);
                    return Value.initBool(s != .created);
                }
            }.call,
            .is_static = false,
        });

        // isSuspended(): bool
        try meta.addMethod(.{
            .name = "isSuspended",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    return Value.initBool(
                        getFiberState(ctx) == .suspended,
                    );
                }
            }.call,
            .is_static = false,
        });

        // isRunning(): bool
        try meta.addMethod(.{
            .name = "isRunning",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    return Value.initBool(
                        getFiberState(ctx) == .running,
                    );
                }
            }.call,
            .is_static = false,
        });

        // isTerminated(): bool
        try meta.addMethod(.{
            .name = "isTerminated",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    return Value.initBool(
                        getFiberState(ctx) == .terminated,
                    );
                }
            }.call,
            .is_static = false,
        });

        // getReturn(): mixed
        try meta.addMethod(.{
            .name = "getReturn",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    if (!Value_isObject(ctx))
                        return Value.initNull();
                    const this = Value_asObject(ctx);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    return fctx.return_value;
                }
            }.call,
            .is_static = false,
        });

        // Fiber::getCurrent(): ?Fiber (static)
        try meta.addMethod(.{
            .name = "getCurrent",
            .func = struct {
                fn call(
                    _: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    if (current_fiber_obj) |f| return f;
                    return Value.initNull();
                }
            }.call,
            .is_static = true,
        });

        // throw(Throwable $exception): mixed
        try meta.addMethod(.{
            .name = "throw",
            .func = struct {
                fn call(
                    ctx: Value,
                    args: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    const this = Value_asObject(ctx);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    while (!fctx.mutex.tryLock()) std.atomic.spinLoopHint();
                    if (fctx.state != .suspended) {
                        fctx.mutex.unlock();
                        return Value.initNull();
                    }
                    if (args.len > 0) {
                        fctx.throw_exception = args[0];
                    }
                    // 通过 FiberContext 传递异常
                    fctx.resume_value = Value.initNull();
                    fctx.state = .running;
                    fctx.fiber_cond.signal(getIo());
                    while (fctx.state == .running) {
                        fctx.caller_cond.wait(getIo(), &fctx.mutex) catch {};
                    }
                    const result = fctx.suspend_value;
                    fctx.suspend_value = Value.initNull();
                    setFiberState(this, fctx.state);
                    fctx.mutex.unlock();
                    if (fctx.state == .terminated) {
                        if (fctx.thread) |t| t.join();
                        fctx.thread = null;
                    }
                    return result;
                }
            }.call,
            .is_static = false,
        });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
    }

    fn getFiberCtx(obj: *PHPObject) ?*FiberContext {
        const addr_val = obj.getPropertyDirect("__fctx_addr") orelse
            return null;
        const addr: usize = @intCast(addr_val.toInt());
        if (addr == 0) return null;
        return @ptrFromInt(addr);
    }

    fn getFiberState(ctx: Value) FiberState {
        if (!Value_isObject(ctx)) return .created;
        const this = Value_asObject(ctx);
        const sv = this.getPropertyDirect("__state") orelse
            return .created;
        return @enumFromInt(@as(u8, @intCast(sv.toInt())));
    }

    fn setFiberState(obj: *PHPObject, state: FiberState) void {
        obj.setProperty(
            "__state",
            Value.initInt(@intFromEnum(state)),
        ) catch {};
    }

    /// 添加属性定义
    pub fn addProperty(self: *ClassMeta, prop: ClassProperty) !void {
        try self.properties.put(prop.name, prop);
    }

    /// 设置静态属性
    pub fn setStaticProperty(self: *ClassMeta, name: []const u8, value: Value) !void {
        if (self.static_properties.get(name)) |old| {
            old.release(self.allocator);
        }
        _ = value.retain();
        try self.static_properties.put(name, value);
    }

    /// 获取静态属性
    pub fn getStaticProperty(self: *const ClassMeta, name: []const u8) ?Value {
        if (self.static_properties.get(name)) |val| {
            return val;
        }
        if (self.parent) |parent| {
            if (parent.getStaticProperty(name)) |val| return val;
        }
        // 查找实现的接口中的常量
        for (self.interfaces) |iface| {
            if (class_registry) |reg| {
                if (reg.get(iface)) |iface_meta| {
                    if (iface_meta.getStaticProperty(name)) |val| return val;
                }
            }
        }
        return null;
    }

    /// 检查是否实现了接口
    pub fn implementsInterface(self: *const ClassMeta, interface_name: []const u8) bool {
        for (self.interfaces) |iface| {
            if (std.mem.eql(u8, iface, interface_name)) return true;
            // 递归检查接口的父接口（interface C extends A, B）
            if (class_registry) |reg| {
                if (reg.get(iface)) |iface_meta| {
                    if (iface_meta.implementsInterface(interface_name)) return true;
                }
            }
        }
        if (self.parent) |parent| {
            return parent.implementsInterface(interface_name);
        }
        return false;
    }

    /// 检查是否是某个类的子类
    pub fn isSubclassOf(self: *const ClassMeta, class_name: []const u8) bool {
        if (std.mem.eql(u8, self.name, class_name)) return true;
        if (self.parent) |parent| {
            return parent.isSubclassOf(class_name);
        }
        return false;
    }
};

/// 全局类注册表
pub var class_registry: ?std.StringHashMap(*ClassMeta) = null;

/// 全局对象跟踪（用于内存泄露检测和清理）
pub var global_object_registry: ?std.ArrayList(*PHPObject) = null;

/// 弱引用死亡追踪：存储已被 unset 的对象指针地址
var weak_dead_objects: ?std.AutoHashMap(usize, void) = null;

/// 标记对象为"逻辑死亡"（unset 时调用）
pub fn php_weak_mark_dead(val: Value) void {
    if (!Value_isObject(val)) return;
    const obj = Value_asObject(val);
    const addr = @intFromPtr(obj);
    if (weak_dead_objects == null) {
        weak_dead_objects = std.AutoHashMap(usize, void).init(runtime_allocator);
    }
    if (weak_dead_objects) |*set| {
        set.put(addr, {}) catch {};
    }
}

/// 已触发 __destruct 的对象集合（防止重复触发）
var destructed_objects: ?std.AutoHashMap(usize, void) = null;

/// 对象是否已经执行过 __destruct
pub fn php_is_destructed(obj: *PHPObject) bool {
    if (destructed_objects) |*set| {
        return set.contains(@intFromPtr(obj));
    }
    return false;
}

/// 标记对象已执行 __destruct
fn markDestructed(obj: *PHPObject) void {
    if (destructed_objects == null) {
        destructed_objects = std.AutoHashMap(usize, void).init(runtime_allocator);
    }
    if (destructed_objects) |*set| {
        set.put(@intFromPtr(obj), {}) catch {};
    }
}

/// 立即对对象触发 __destruct（若尚未触发），用于 unset 时 PHP 语义。
/// 不释放内存，等待真正的 refcount 归零时 deinit 再释放。
pub fn php_force_destruct_if_object(val: Value) void {
    if (!Value_isObject(val)) return;
    const obj = Value_asObject(val);
    if (php_is_destructed(obj)) return;
    if (obj.class_meta) |meta| {
        if (class_registry == null) return;
        if (meta.findMethodLookup("__destruct")) |lookup| {
            markDestructed(obj);
            const this_val = Value_initObject(obj);
            const guard = ClassContext.init(meta, lookup.owner);
            defer guard.deinit();
            _ = lookup.method.func(this_val, &.{}, obj.allocator) catch {};
        } else {
            markDestructed(obj);
        }
    }
}

/// 检查对象是否仍然存活（未被 unset 标记为死亡）
fn php_weak_is_alive(addr: usize) bool {
    if (weak_dead_objects) |*set| {
        return !set.contains(addr);
    }
    return true;
}

/// ============================================================================
/// 弱引用表（WeakReference Table）
/// ============================================================================
/// 用于存储弱引用的目标对象。当创建 WeakReference 时，目标对象会被注册到这里。
/// 注意：这是一个简化实现，真正的弱引用应该在 GC 层面实现。

/// 弱引用表：地址 -> Value（目标对象的引用）
var weakref_table: ?std.AutoHashMap(usize, Value) = null;

/// 注册弱引用目标对象
/// 不增加引用计数，仅存储对象引用
fn weakref_register(addr: usize, target: Value, allocator: Allocator) !void {
    if (weakref_table == null) {
        weakref_table = std.AutoHashMap(usize, Value).init(allocator);
    }
    if (weakref_table) |*table| {
        // 存储目标对象的引用（不增加引用计数，实现弱引用语义）
        // 但我们需要能够在对象存活时获取它，所以保留一个原始指针引用
        // 注意：这是一个妥协的实现，真正的弱引用需要 GC 支持
        try table.put(addr, target);
    }
}

/// 获取弱引用目标对象
/// 如果对象已被销毁，返回 null
fn weakref_get(addr: usize) Value {
    // 首先检查对象是否仍然存活
    if (!php_weak_is_alive(addr)) {
        return Value.initNull();
    }

    // 从弱引用表获取目标对象
    if (weakref_table) |*table| {
        if (table.get(addr)) |target| {
            // 检查目标对象是否有效
            if (Value_isObject(target)) {
                _ = target.retain();
                return target;
            }
        }
    }

    return Value.initNull();
}

/// 清理弱引用表中已死亡对象的条目
fn weakref_cleanup() void {
    if (weakref_table) |*table| {
        var iter = table.iterator();
        var to_remove = try std.ArrayList(usize).initCapacity(runtime_allocator, 0);
        defer to_remove.deinit();

        while (iter.next()) |entry| {
            if (!php_weak_is_alive(entry.key_ptr.*)) {
                to_remove.append(entry.key_ptr.*) catch {};
            }
        }

        for (to_remove.items) |addr| {
            _ = table.remove(addr);
        }
    }
}

/// @ 错误抑制运算符支持
/// 使用嵌套计数器支持 @@expr 等场景
threadlocal var error_suppress_depth: u32 = 0;

pub fn php_error_suppress_push() void {
    error_suppress_depth += 1;
}

pub fn php_error_suppress_pop() void {
    if (error_suppress_depth > 0) error_suppress_depth -= 1;
}

pub fn isErrorSuppressed() bool {
    return error_suppress_depth > 0;
}

pub fn getCurrentCalledClass() ?*const ClassMeta {
    const ptr = concurrency.getExecutionContext().called_class orelse return null;
    return @ptrFromInt(ptr);
}

pub fn setCurrentCalledClass(meta: ?*const ClassMeta) void {
    concurrency.getExecutionContext().called_class = if (meta) |m| @intFromPtr(m) else null;
}

pub fn getCurrentScopeClass() ?*const ClassMeta {
    const ptr = concurrency.getExecutionContext().scope_class orelse return null;
    return @ptrFromInt(ptr);
}

pub fn setCurrentScopeClass(meta: ?*const ClassMeta) void {
    concurrency.getExecutionContext().scope_class = if (meta) |m| @intFromPtr(m) else null;
}

pub const ClassContext = struct {
    prev_called: ?*const ClassMeta,
    prev_scope: ?*const ClassMeta,

    pub fn init(called: ?*const ClassMeta, scope: ?*const ClassMeta) ClassContext {
        const prev = ClassContext{
            .prev_called = getCurrentCalledClass(),
            .prev_scope = getCurrentScopeClass(),
        };
        setCurrentCalledClass(called);
        setCurrentScopeClass(scope);
        return prev;
    }

    pub fn deinit(self: *const ClassContext) void {
        setCurrentCalledClass(self.prev_called);
        setCurrentScopeClass(self.prev_scope);
    }
};

fn resolveSpecialClassName(class_name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, class_name, "static")) {
        const meta = getCurrentCalledClass() orelse return error.ClassNotFound;
        return meta.name;
    }
    if (std.mem.eql(u8, class_name, "self")) {
        const meta = getCurrentScopeClass() orelse return error.ClassNotFound;
        return meta.name;
    }
    if (std.mem.eql(u8, class_name, "parent")) {
        const meta = getCurrentScopeClass() orelse return error.ClassNotFound;
        const parent = meta.parent orelse return error.ClassNotFound;
        return parent.name;
    }
    return class_name;
}

/// 初始化类注册表
pub fn initClassRegistry(allocator: Allocator) void {
    class_registry = std.StringHashMap(*ClassMeta).init(allocator);
    global_object_registry = std.ArrayList(*PHPObject).initCapacity(allocator, 0) catch {
        global_object_registry = null;
        return;
    };
}

/// 注册类
pub fn registerClass(meta: *ClassMeta) !void {
    if (class_registry) |*registry| {
        try registry.put(meta.name, meta);
    }
}

/// 查找类
pub fn findClass(name: []const u8) ?*ClassMeta {
    if (class_registry) |registry| {
        return registry.get(name);
    }
    return null;
}

/// 清理所有注册的类和对象
pub fn cleanupAllClasses() void {
    // 清空对象注册表（对象由global_vars cleanup处理）
    if (global_object_registry) |*registry| {
        registry.deinit(runtime_allocator);
        global_object_registry = null;
    }

    // 清理所有类
    if (class_registry) |*registry| {
        var iter = registry.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        registry.deinit();
        class_registry = null;
    }
}

/// PHP对象类型
/// 使用引用计数管理内存，属性存储在HashMap中
pub const PHPObject = struct {
    class_meta: ?*const ClassMeta,
    class_name: []const u8,
    properties: std.StringHashMap(Value),
    ref_count: usize,
    gc_info: GCInfo,
    allocator: Allocator,

    /// 创建新对象
    pub fn init(allocator: Allocator, class_name: []const u8) !*PHPObject {
        const obj = try allocator.create(PHPObject);
        errdefer allocator.destroy(obj);

        obj.class_name = try allocator.dupe(u8, class_name);
        errdefer allocator.free(obj.class_name);

        obj.properties = std.StringHashMap(Value).init(allocator);
        obj.ref_count = 1;
        obj.gc_info = .{};
        obj.allocator = allocator;
        obj.class_meta = findClass(class_name);

        alloc_counters.php_object_objects += 1;
        alloc_counters.php_object_live_objects += 1;
        if (alloc_counters.php_object_live_objects > alloc_counters.php_object_peak_live_objects) {
            alloc_counters.php_object_peak_live_objects = alloc_counters.php_object_live_objects;
        }

        return obj;
    }

    /// 使用类元数据创建对象
    pub fn initWithMeta(allocator: Allocator, meta: *const ClassMeta) !*PHPObject {
        const obj = try allocator.create(PHPObject);
        errdefer allocator.destroy(obj);

        obj.class_name = try allocator.dupe(u8, meta.name);
        errdefer allocator.free(obj.class_name);

        obj.properties = std.StringHashMap(Value).init(allocator);
        obj.ref_count = 1;
        obj.gc_info = .{};
        obj.allocator = allocator;
        obj.class_meta = meta;

        alloc_counters.php_object_objects += 1;
        alloc_counters.php_object_live_objects += 1;
        if (alloc_counters.php_object_live_objects > alloc_counters.php_object_peak_live_objects) {
            alloc_counters.php_object_peak_live_objects = alloc_counters.php_object_live_objects;
        }

        // 初始化默认属性值（包括父类）
        var current_meta: ?*const ClassMeta = meta;
        while (current_meta) |m| {
            var prop_iter = m.properties.iterator();
            while (prop_iter.next()) |entry| {
                if (!entry.value_ptr.is_static) {
                    // 只初始化还不存在的属性（避免覆盖子类的属性）
                    if (obj.properties.get(entry.key_ptr.*) == null) {
                        if (entry.value_ptr.default_value) |default| {
                            // 检查是否是数组标记（initInt(-1)）
                            if (default.isInt() and default.asInt() == -1) {
                                const new_array = try PHPArray.init(allocator);
                                try obj.properties.put(entry.key_ptr.*, Value.initArray(new_array));
                            } else if (default.isArray()) {
                                // 旧代码路径：如果是数组，创建新实例
                                const new_array = try PHPArray.init(allocator);
                                try obj.properties.put(entry.key_ptr.*, Value.initArray(new_array));
                            } else {
                                // 其他类型可以共享（int/float/bool/string是不可变的）
                                _ = default.retain();
                                try obj.properties.put(entry.key_ptr.*, default);
                            }
                        }
                    }
                }
            }
            current_meta = m.parent;
        }
        return obj;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPObject) void {
        self.ref_count += 1;
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPObject) void {
        if (self.ref_count > 1000000) {
            std.debug.print("ERROR: PHPObject corrupted! class={s} ref_count={d}\n", .{ self.class_name, self.ref_count });
            return;
        }
        if (self.ref_count == 0) {
            std.debug.print("WARNING: PHPObject double free! class={s}\n", .{self.class_name});
            return;
        }
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit();
        } else if (!gc_in_progress) {
            gcBufferObject(self);
        }
    }

    /// 释放对象
    fn deinit(self: *PHPObject) void {
        if (alloc_counters.php_object_live_objects > 0) {
            alloc_counters.php_object_live_objects -= 1;
        }

        // 调用 __destruct 魔法函数
        // 注意：在程序清理阶段，class_meta可能已被释放，需要检查
        if (self.class_meta) |meta| {
            // 简单检查：如果class_registry已被清理，跳过__destruct
            if (class_registry != null) {
                // 若已被 php_force_destruct_if_object 显式触发过，跳过
                if (!php_is_destructed(self)) {
                    if (meta.findMethodLookup("__destruct")) |lookup| {
                        // 临时增加引用计数，防止析构函数内部的retain/release导致无限递归
                        // 析构函数执行期间，对象的refcount应该保持为1
                        self.ref_count = 1;
                        const this_val = Value_initObject(self);
                        const guard = ClassContext.init(meta, lookup.owner);
                        defer guard.deinit();
                        _ = lookup.method.func(this_val, &.{}, self.allocator) catch {};
                        // 析构函数执行完毕，恢复refcount为0以继续销毁流程
                        self.ref_count = 0;
                    }
                }
                // 清理 destructed 记录
                if (destructed_objects) |*set| {
                    _ = set.remove(@intFromPtr(self));
                }
            }
        }

        if (global_object_registry) |*registry| {
            var i: usize = 0;
            while (i < registry.items.len) : (i += 1) {
                if (registry.items[i] == self) {
                    registry.items[i] = registry.items[registry.items.len - 1];
                    _ = registry.pop();
                    break;
                }
            }
        }

        // 释放所有属性值
        var iter = self.properties.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.properties.deinit();

        // 释放类名
        self.allocator.free(self.class_name);

        // 释放对象本身
        self.allocator.destroy(self);
    }

    /// 获取属性（支持 __get 魔法函数）
    // 防止magic method递归调用的标志
    threadlocal var in_magic_method: bool = false;

    pub fn getProperty(self: *PHPObject, name: []const u8) ?Value {
        if (self.properties.get(name)) |val| {
            _ = val.retain();
            return val;
        }
        // 防止递归调用__get
        if (in_magic_method) return null;

        // 调用 __get 魔法函数
        if (self.class_meta) |meta| {
            if (meta.findMethodLookup("__get")) |lookup| {
                in_magic_method = true;
                defer in_magic_method = false;

                const this_val = Value_initObject(self);
                const name_str = PHPString.init(self.allocator, name) catch return null;
                const name_val = Value.initString(name_str);
                defer name_val.release(self.allocator);
                const args = [_]Value{name_val};
                const guard = ClassContext.init(meta, lookup.owner);
                defer guard.deinit();
                const result = lookup.method.func(this_val, &args, self.allocator) catch return null;
                return result;
            }
        }
        return null;
    }

    /// 直接获取属性（不触发__get）
    pub fn getPropertyDirect(self: *PHPObject, name: []const u8) ?Value {
        if (self.properties.get(name)) |val| {
            _ = val.retain();
            return val;
        }
        return null;
    }

    /// 设置属性（支持 __set 魔法函数）
    pub fn setProperty(self: *PHPObject, name: []const u8, value: Value) !void {
        // 防止递归调用__set
        if (!in_magic_method) {
            // 检查是否有 __set 魔法函数且属性不存在
            if (self.properties.get(name) == null) {
                if (self.class_meta) |meta| {
                    if (meta.findMethodLookup("__set")) |lookup| {
                        in_magic_method = true;
                        defer in_magic_method = false;

                        const this_val = Value_initObject(self);
                        const name_str = try PHPString.init(self.allocator, name);
                        const name_val = Value.initString(name_str);
                        defer name_val.release(self.allocator);
                        const args = [_]Value{ name_val, value };
                        const guard = ClassContext.init(meta, lookup.owner);
                        defer guard.deinit();
                        _ = try lookup.method.func(this_val, &args, self.allocator);
                        return;
                    }
                }
            }
        }

        // 释放旧值
        if (self.properties.get(name)) |old_value| {
            old_value.release(self.allocator);
        }

        // 保留新值
        _ = value.retain();

        // 存储属性
        try self.properties.put(name, value);
    }

    /// 调用方法（支持 __call 魔法函数和继承）
    pub fn callMethod(self: *PHPObject, method_name: []const u8, args: []const Value) !Value {
        const this_val = Value_initObject(self);

        if (self.class_meta) |meta| {
            // 查找方法（包括继承链）
            if (meta.findMethodLookup(method_name)) |lookup| {
                const guard = ClassContext.init(meta, lookup.owner);
                defer guard.deinit();
                return lookup.method.func(this_val, args, self.allocator);
            }
            // 调用 __call 魔法函数
            if (meta.findMethodLookup("__call")) |lookup| {
                const name_val = Value.initString(try PHPString.init(self.allocator, method_name));
                const args_arr = try PHPArray.init(self.allocator);
                for (args) |arg| {
                    try args_arr.push(self.allocator, arg);
                }
                const call_args = [_]Value{ name_val, Value.initArray(args_arr) };
                const guard = ClassContext.init(meta, lookup.owner);
                defer guard.deinit();
                return lookup.method.func(this_val, &call_args, self.allocator);
            }
        }
        return error.MethodNotFound;
    }

    /// 检查属性是否存在（支持 __isset 魔法函数）
    pub fn hasProperty(self: *PHPObject, name: []const u8) bool {
        if (self.properties.contains(name)) return true;
        if (self.class_meta) |meta| {
            if (meta.findMethodLookup("__isset")) |lookup| {
                const this_val = Value_initObject(self);
                const name_val = Value.initString(PHPString.initStatic(name));
                const args = [_]Value{name_val};
                const guard = ClassContext.init(meta, lookup.owner);
                defer guard.deinit();
                const result = lookup.method.func(this_val, &args, self.allocator) catch return false;
                return result.toBool();
            }
        }
        return false;
    }

    pub fn unsetProperty(self: *PHPObject, name: []const u8) !bool {
        if (self.properties.get(name)) |old_value| {
            if (self.properties.remove(name)) {
                old_value.release(self.allocator);
                return true;
            }
        }

        if (!in_magic_method) {
            if (self.class_meta) |meta| {
                if (meta.findMethodLookup("__unset")) |lookup| {
                    in_magic_method = true;
                    defer in_magic_method = false;

                    const this_val = Value_initObject(self);
                    const name_str = try PHPString.init(self.allocator, name);
                    const name_val = Value.initString(name_str);
                    defer name_val.release(self.allocator);
                    const args = [_]Value{name_val};
                    const guard = ClassContext.init(meta, lookup.owner);
                    defer guard.deinit();
                    _ = try lookup.method.func(this_val, &args, self.allocator);
                    return true;
                }
            }
        }

        return false;
    }

    /// 转换为字符串（支持 __toString 魔法函数）
    pub fn toString(self: *PHPObject, allocator: Allocator) !*PHPString {
        if (self.class_meta) |meta| {
            if (meta.magic_toString) |to_str| {
                const this_val = Value_initObject(self);
                const result = try to_str(this_val, &.{}, allocator);
                if (result.isString()) {
                    return result.asString();
                }
            }
        }
        // 默认返回类名
        return PHPString.init(allocator, self.class_name);
    }
};

// ============================================================================
// Value类型扩展 - 对象支持
// ============================================================================

// 扩展Value的方法（这些方法应该添加到Value结构中）
// 由于我们不能直接修改Value结构，我们在这里提供独立的函数

/// 创建对象值
pub fn Value_initObject(obj: *PHPObject) Value {
    const addr = @intFromPtr(obj);
    return .{ .val = nanbox_abi.encodePtr(addr, Value.TYPE_OBJECT) };
}

/// 检查是否是对象
pub fn Value_isObject(self: Value) bool {
    if ((self.val & (Value.SIGN_BIT | Value.QNAN)) != Value.QNAN) return false;
    return (self.val & Value.TYPE_MASK) == Value.TYPE_OBJECT;
}

/// 获取对象指针
pub fn Value_asObject(self: Value) *PHPObject {
    return @ptrFromInt(nanbox_abi.decodePtr(self.val));
}

// 更新Value的release方法以支持对象
// 注意：这需要在Value结构的release方法中添加对象处理

// ============================================================================
// 对象操作函数
// ============================================================================

/// 创建新对象
///
/// @param allocator 内存分配器
/// @return 对象Value
pub fn php_object_new(class_name: []const u8, allocator: Allocator) !Value {
    const resolved = try resolveSpecialClassName(class_name);
    const obj = if (findClass(resolved)) |meta|
        try PHPObject.initWithMeta(allocator, meta)
    else
        try PHPObject.init(allocator, resolved);

    // 注册对象以便程序退出时清理
    if (global_object_registry) |*registry| {
        registry.append(allocator, obj) catch {};
    }

    return Value_initObject(obj);
}

/// 获取对象属性
///
/// @param obj_val 对象Value
/// @param property_name 属性名
/// @return 属性值，如果不存在返回null
pub fn php_object_get(obj_val: Value, property_name: []const u8) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }

    const obj = Value_asObject(obj_val);
    return obj.getProperty(property_name) orelse Value.initNull();
}

pub fn php_object_get_direct(obj_val: Value, property_name: []const u8) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }

    const obj = Value_asObject(obj_val);
    return obj.getPropertyDirect(property_name) orelse Value.initNull();
}

pub fn php_object_get_safe_value(obj_val: Value, prop_name_val: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }
    if (!prop_name_val.isString()) {
        return Value.initNull();
    }
    const obj = Value_asObject(obj_val);
    return obj.getProperty(prop_name_val.asString().data) orelse Value.initNull();
}

pub fn php_object_get_dynamic(obj_val: Value, prop_name_val: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }
    if (!prop_name_val.isString()) {
        return Value.initNull();
    }
    const obj = Value_asObject(obj_val);
    const prop_str = prop_name_val.asString();
    return obj.getProperty(prop_str.data) orelse Value.initNull();
}

pub fn php_object_set_dynamic(obj_val: Value, prop_name_val: Value, value: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }
    if (!prop_name_val.isString()) {
        return Value.initNull();
    }
    const obj = Value_asObject(obj_val);
    const prop_str = prop_name_val.asString();
    try obj.setProperty(prop_str.data, value);
    return Value.initNull();
}

/// 类型转换函数
pub fn php_cast_int(val: Value) !Value {
    return Value.initInt(val.toInt());
}

pub fn php_cast_float(val: Value) !Value {
    return Value.initFloat(val.toFloat());
}

pub fn php_cast_string(val: Value) !Value {
    const str = try val.toString(runtime_allocator);
    return Value.initString(str);
}

pub fn php_cast_bool(val: Value) !Value {
    return Value.initBool(val.toBool());
}

pub fn php_cast_array(val: Value) !Value {
    const actual_val = if (val.isRef()) val.asRef().* else val;
    if (actual_val.isArray()) {
        return actual_val;
    }
    const arr = try PHPArray.init(runtime_allocator);
    if (!actual_val.isNull()) {
        try arr.push(runtime_allocator, actual_val);
    }
    return Value.initArray(arr);
}

pub fn php_cast_object(val: Value) !Value {
    // 如果已经是对象，直接返回
    if (Value_isObject(val)) {
        return val;
    }
    
    // 数组转对象：将数组元素作为对象属性
    if (val.isArray()) {
        const obj_val = try php_object_new("stdClass", runtime_allocator);
        const obj = Value_asObject(obj_val);
        var it = val.asArray().elements.iterator();
        while (it.next()) |entry| {
            switch (entry.key_ptr.*) {
                .string => |key| {
                    try obj.setProperty(key.data, entry.value_ptr.*);
                },
                .integer => |idx| {
                    const key_str = try std.fmt.allocPrint(runtime_allocator, "{d}", .{idx});
                    errdefer runtime_allocator.free(key_str);
                    const key_copy = try runtime_allocator.dupe(u8, key_str);
                    runtime_allocator.free(key_str);
                    try obj.properties.put(key_copy, entry.value_ptr.*.retain());
                },
            }
        }
        return obj_val;
    }
    
    // 标量类型转对象：创建 stdClass 对象，值存储在 "scalar" 属性中
    // PHP 行为：(object)"test" 创建 stdClass { scalar: "test" }
    const obj_val = try php_object_new("stdClass", runtime_allocator);
    const obj = Value_asObject(obj_val);
    try obj.setProperty("scalar", val);
    return obj_val;
}

/// 设置对象属性
///
/// @param obj_val 对象Value
/// @param property_name 属性名
/// @param value 属性值
pub fn php_object_set(obj_val: Value, property_name: []const u8, value: Value) !Value {
    if (!Value_isObject(obj_val)) {
        // PHP: 对非对象设置属性发出警告但不终止
        return Value.initNull();
    }

    const obj = Value_asObject(obj_val);
    try obj.setProperty(property_name, value);
    return Value.initNull();
}

/// $obj->prop[] = value — 向对象属性数组追加元素
pub fn php_property_array_push_with_obj(obj_val: Value, prop_name: Value, value: Value, _: Value) !void {
    if (!Value_isObject(obj_val)) return;
    const obj = Value_asObject(obj_val);
    const name = if (prop_name.isString()) prop_name.asString().data else return;

    // 获取属性值
    var prop_val = obj.getPropertyDirect(name) orelse Value.initNull();

    // 如果属性不是数组，创建一个新数组
    if (!prop_val.isArray()) {
        const arr = try PHPArray.init(runtime_allocator);
        prop_val = Value.initArray(arr);
        try obj.setProperty(name, prop_val);
    }

    const arr = prop_val.asArray();
    _ = value.retain();
    try arr.push(runtime_allocator, value);
}

/// $obj->prop[key] = value — 向对象属性数组设置元素
pub fn php_property_array_set_with_obj(obj_val: Value, prop_name: Value, key: Value, value: Value, _: Value) !void {
    if (!Value_isObject(obj_val)) return;
    const obj = Value_asObject(obj_val);
    const name = if (prop_name.isString()) prop_name.asString().data else return;

    // 获取属性值
    var prop_val = obj.getPropertyDirect(name) orelse Value.initNull();

    // 如果属性不是数组，创建一个新数组
    if (!prop_val.isArray()) {
        const arr = try PHPArray.init(runtime_allocator);
        prop_val = Value.initArray(arr);
        try obj.setProperty(name, prop_val);
    }

    const arr = prop_val.asArray();
    const arr_key = normalizeArrayKeyFromValue(key);
    try arr.set(runtime_allocator, arr_key, value);
}

/// 调用对象方法
///
/// @param obj_val 对象Value
/// @param method_name 方法名
/// @param args 参数数组
/// @return 方法返回值
pub fn php_object_call(obj_val: Value, method_name: []const u8, args: []const Value) !Value {
    if (obj_val.isString()) {
        if (std.mem.eql(u8, method_name, "toUpper")) return php_strtoupper(obj_val, runtime_allocator);
        if (std.mem.eql(u8, method_name, "toLower")) return php_strtolower(obj_val, runtime_allocator);
        if (std.mem.eql(u8, method_name, "trim")) return php_trim(obj_val, Value.initNull(), runtime_allocator);
        if (std.mem.eql(u8, method_name, "length")) return php_strlen(obj_val);
        if (std.mem.eql(u8, method_name, "replace")) {
            if (args.len < 2) return error.MissingArgument;
            return php_str_replace(args[0], args[1], obj_val, Value.initNull(), runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "substring")) {
            if (args.len < 2) return error.MissingArgument;
            return php_substr(obj_val, args[0], args[1], runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "indexOf")) {
            if (args.len < 1) return error.MissingArgument;
            return php_strpos(obj_val, args[0], Value.initInt(0));
        }
        if (std.mem.eql(u8, method_name, "lastIndexOf")) {
            if (args.len < 1) return error.MissingArgument;
            return php_strrpos(obj_val, args[0], Value.initInt(0));
        }
        if (std.mem.eql(u8, method_name, "contains")) {
            if (args.len < 1) return error.MissingArgument;
            return php_str_contains(obj_val, args[0]);
        }
        if (std.mem.eql(u8, method_name, "startsWith")) {
            if (args.len < 1) return error.MissingArgument;
            return php_str_starts_with(obj_val, args[0]);
        }
        if (std.mem.eql(u8, method_name, "endsWith")) {
            if (args.len < 1) return error.MissingArgument;
            return php_str_ends_with(obj_val, args[0]);
        }
        if (std.mem.eql(u8, method_name, "repeat")) {
            if (args.len < 1) return error.MissingArgument;
            return php_str_repeat(obj_val, args[0], runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "pad")) {
            if (args.len < 1) return error.MissingArgument;
            var created_pad_str = false;
            const pad_str = if (args.len >= 2) args[1] else blk: {
                created_pad_str = true;
                break :blk Value.initString(try PHPString.init(runtime_allocator, " "));
            };
            defer if (created_pad_str) pad_str.release(runtime_allocator);
            const pad_type = if (args.len >= 3) args[2] else Value.initInt(0);
            return php_str_pad(obj_val, args[0], pad_str, pad_type, runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "reverse")) return php_strrev(obj_val, runtime_allocator);
        if (std.mem.eql(u8, method_name, "split")) {
            if (args.len < 1) return error.MissingArgument;
            return php_explode(args[0], obj_val, Value.initNull(), runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "concat")) {
            if (args.len < 1) return error.MissingArgument;
            return php_concat(obj_val, args[0], runtime_allocator);
        }
        return error.UnknownMethod;
    }

    // Closure 方法调用：bindTo/call/bind 等
    if (obj_val.isFunction()) {
        if (findClass("Closure")) |closure_meta| {
            if (closure_meta.findMethod(method_name)) |method| {
                return method.func(obj_val, args, runtime_allocator);
            }
        }
        // 未知闭包方法
        fileWriteAll(2, "PHP Fatal error:  Call to undefined method Closure::");
        fileWriteAll(2, method_name);
        fileWriteAll(2, "()\n");
        return Value.initNull();
    }

    if (!Value_isObject(obj_val)) {
        // PHP: 对非对象调用方法时发出 Fatal error
        fileWriteAll(2, "PHP Fatal error:  Call to a member function on a non-object\n");
        fileWriteAll(1, "\nFatal error: Call to a member function on a non-object\n");
        return Value.initNull();
    }
    const obj = Value_asObject(obj_val);
    return obj.callMethod(method_name, args) catch |err| {
        if (err == error.MethodNotFound) {
            const class_name = if (obj.class_meta) |m| m.name else "unknown";
            var buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "PHP Fatal error:  Uncaught Error: Call to undefined method {s}::{s}()\n", .{ class_name, method_name }) catch "PHP Fatal error: MethodNotFound\n";
            fileWriteAll(2, msg);
            const msg2 = std.fmt.bufPrint(&buf, "\nFatal error: Uncaught Error: Call to undefined method {s}::{s}()\n", .{ class_name, method_name }) catch "";
            fileWriteAll(1, msg2);
            return Value.initNull();
        }
        return err;
    };
}

/// 创建新对象并调用构造函数
pub fn php_object_new_with_constructor(class_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const resolved = try resolveSpecialClassName(class_name);
    var meta = findClass(resolved);

    // 如果找不到，尝试使用短名称（命名空间支持）
    if (meta == null) {
        if (std.mem.lastIndexOf(u8, resolved, "\\")) |last_sep| {
            const short_name = resolved[last_sep + 1 ..];
            meta = findClass(short_name);
        }
    }

    if (meta == null) {
        // PHP Fatal error: Class "X" not found
        // PHP 输出顺序：先 stderr，再 stdout
        var ebuf: [1024]u8 = undefined;
        const stderr_msg = std.fmt.bufPrint(
            &ebuf,
            "PHP Fatal error:  Uncaught Error: Class \"{s}\"" ++
                " not found in {s}:{d}\nStack trace:\n" ++
                "#0 {{main}}\n  thrown in {s} on line {d}\n",
            .{ resolved, src_file, src_line, src_file, src_line },
        ) catch {
            std.process.exit(255);
        };
        fileWriteAll(2, stderr_msg);
        var buf: [1024]u8 = undefined;
        const stdout_msg = std.fmt.bufPrint(
            &buf,
            "\nFatal error: Uncaught Error: Class \"{s}\"" ++
                " not found in {s}:{d}\nStack trace:\n" ++
                "#0 {{main}}\n  thrown in {s} on line {d}\n",
            .{ resolved, src_file, src_line, src_file, src_line },
        ) catch {
            fileWriteAll(1, "\nFatal error: Class not found\n");
            std.process.exit(255);
        };
        fileWriteAll(1, stdout_msg);
        std.process.exit(255);
    }

    const obj = try PHPObject.initWithMeta(allocator, meta.?);

    const obj_val = Value_initObject(obj);

    // 调用 __construct
    if (obj.class_meta) |m| {
        if (m.findMethodLookup("__construct")) |lookup| {
            const guard = ClassContext.init(m, lookup.owner);
            defer guard.deinit();
            _ = try lookup.method.func(obj_val, args, allocator);
            // 注意：构造函数中的 store $this 会 retain，函数结束时会 release
            // 这是正确的引用计数行为，不需要补偿
        }
    }

    return obj_val;
}

/// 检查类是否存在
pub fn php_class_exists(class_name: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!class_name.isString()) return Value.initBool(false);
    const name = class_name.asString().data;
    return Value.initBool(findClass(name) != null);
}

pub fn class_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;
    return php_class_exists(args[0], allocator);
}

/// 检查接口是否存在
pub fn php_interface_exists(interface_name: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!interface_name.isString()) return Value.initBool(false);
    const name = interface_name.asString().data;
    // 在class_registry中查找，检查是否为接口
    if (findClass(name)) |meta| {
        return Value.initBool(meta.is_interface);
    }
    return Value.initBool(false);
}

pub fn interface_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;
    return php_interface_exists(args[0], allocator);
}

/// 检查trait是否存在
pub fn php_trait_exists(trait_name: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!trait_name.isString()) return Value.initBool(false);
    const name = trait_name.asString().data;
    // 在class_registry中查找，检查是否为trait
    if (findClass(name)) |meta| {
        return Value.initBool(meta.is_trait);
    }
    return Value.initBool(false);
}

pub fn trait_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;
    return php_trait_exists(args[0], allocator);
}

/// enum_exists(name) -> bool
pub fn php_enum_exists(name_val: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!name_val.isString()) return Value.initBool(false);
    const name = name_val.asString().data;
    if (findClass(name)) |meta| {
        return Value.initBool(meta.is_enum);
    }
    return Value.initBool(false);
}

/// 检查是否是某个类的子类
pub fn php_is_subclass_of(child: Value, parent: Value) !Value {
    // 第一个参数可以是对象或类名字符串
    var child_class_name: []const u8 = undefined;
    var child_meta: ?*const ClassMeta = null;
    
    if (Value_isObject(child)) {
        const obj = Value_asObject(child);
        child_class_name = obj.class_name;
        child_meta = obj.class_meta;
    } else if (child.isString()) {
        child_class_name = child.asString().data;
        child_meta = findClass(child_class_name);
    } else {
        return Value.initBool(false);
    }
    
    // 第二个参数必须是类名字符串
    if (!parent.isString()) return Value.initBool(false);
    const parent_class_name = parent.asString().data;
    
    // 如果子类元数据不存在，返回 false
    if (child_meta == null) return Value.initBool(false);
    
    // 检查是否相同（PHP 的 is_subclass_of 不包括自身）
    if (std.mem.eql(u8, child_class_name, parent_class_name)) {
        return Value.initBool(false);
    }
    
    // 检查继承链
    if (child_meta.?.parent) |parent_meta| {
        if (parent_meta.isSubclassOf(parent_class_name)) {
            return Value.initBool(true);
        }
    }
    
    // 检查接口实现
    if (child_meta.?.implementsInterface(parent_class_name)) {
        return Value.initBool(true);
    }
    
    return Value.initBool(false);
}

pub fn is_subclass_of(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 2) return error.MissingArgument;
    return php_is_subclass_of(args[0], args[1]);
}

/// instanceof 检查
pub fn php_instanceof(obj_val: Value, class_name: Value) !Value {
    if (!Value_isObject(obj_val)) return Value.initBool(false);
    if (!class_name.isString()) return Value.initBool(false);

    const obj = Value_asObject(obj_val);
    const name = class_name.asString().data;

    // 检查类名直接匹配
    if (std.mem.eql(u8, obj.class_name, name)) return Value.initBool(true);

    // 检查继承链和接口
    if (obj.class_meta) |meta| {
        if (meta.isSubclassOf(name)) return Value.initBool(true);
        if (meta.implementsInterface(name)) return Value.initBool(true);
    }

    // PHP: Throwable 是所有 Exception 和 Error 的基接口
    if (std.mem.eql(u8, name, "Throwable")) {
        if (obj.class_meta) |meta| {
            // 检查是否是Exception或Error的子类
            if (meta.isSubclassOf("Exception") or std.mem.eql(u8, obj.class_name, "Exception")) return Value.initBool(true);
            if (meta.isSubclassOf("Error") or std.mem.eql(u8, obj.class_name, "Error")) return Value.initBool(true);
        }
    }

    // PHP 8.0+: 实现了 __toString() 的类自动实现 Stringable 接口
    if (std.mem.eql(u8, name, "Stringable")) {
        if (obj.class_meta) |meta| {
            if (meta.magic_toString != null) return Value.initBool(true);
            if (meta.methods.get("__toString") != null) return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

/// 获取父类名
pub fn php_get_parent_class(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) return Value.initBool(false);

    const obj = Value_asObject(obj_val);
    if (obj.class_meta) |meta| {
        if (meta.parent) |parent| {
            const parent_name = try PHPString.init(allocator, parent.name);
            return Value.initString(parent_name);
        }
    }
    return Value.initBool(false);
}

/// 检查方法是否存在
pub fn php_method_exists(obj_val: Value, method_name: Value) !Value {
    if (!method_name.isString()) return Value.initBool(false);
    const name = method_name.asString().data;

    if (Value_isObject(obj_val)) {
        const obj = Value_asObject(obj_val);
        if (obj.class_meta) |meta| {
            return Value.initBool(meta.findMethod(name) != null);
        }
    }
    return Value.initBool(false);
}

pub fn method_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 2) return error.MissingArgument;
    return php_method_exists(args[0], args[1]);
}

/// 检查属性是否存在
pub fn php_property_exists(obj_val: Value, property_name: Value) !Value {
    if (!property_name.isString()) return Value.initBool(false);
    const name = property_name.asString().data;

    if (Value_isObject(obj_val)) {
        const obj = Value_asObject(obj_val);
        return Value.initBool(obj.hasProperty(name));
    }

    // 支持字符串类名: property_exists('ClassName', 'prop')
    if (obj_val.isString()) {
        const class_name = obj_val.asString().data;
        if (findClass(class_name)) |meta| {
            // 检查类元数据中是否有该属性
            if (meta.properties.get(name) != null) return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

pub fn property_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 2) return error.MissingArgument;
    return php_property_exists(args[0], args[1]);
}

/// Enum::cases() - 返回所有 case 的数组（保持声明顺序）
fn enumCases(meta: *const ClassMeta, allocator: Allocator) !Value {
    const arr = try PHPArray.init(allocator);
    // 使用 __enum_cases 有序列表
    if (meta.static_properties.get("__enum_cases")) |cases_val| {
        if (cases_val.isArray()) {
            const cases_arr = cases_val.asArray();
            var it = cases_arr.elements.iterator();
            while (it.next()) |entry| {
                const name_val = entry.value_ptr.*;
                if (name_val.isString()) {
                    const name = name_val.asString().data;
                    if (meta.static_properties.get(name)) |case_val| {
                        _ = case_val.retain();
                        try arr.push(allocator, case_val);
                    }
                }
            }
        }
    }
    return Value.initArray(arr);
}

/// Enum::from(value) - 根据 backing value 查找 case，找不到抛 ValueError
fn enumFrom(meta: *const ClassMeta, needle: Value, allocator: Allocator) !Value {
    var it = meta.static_properties.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        if (Value_isObject(val)) {
            const obj = Value_asObject(val);
            if (obj.getPropertyDirect("value")) |backing| {
                const eq = try php_eq(backing, needle);
                if (eq.asBool()) {
                    _ = val.retain();
                    return val;
                }
            }
        }
    }
    // 抛出 ValueError
    const needle_str = try needle.toString(allocator);
    defer needle_str.release(allocator);
    const msg = try std.fmt.allocPrint(allocator, "{s} is not a valid backing value for enum {s}", .{ needle_str.data, meta.name });
    defer allocator.free(msg);
    _ = try throwThrowable("ValueError", msg, allocator);
    return Value.initNull();
}

/// Enum::tryFrom(value) - 根据 backing value 查找 case，找不到返回 null
fn enumTryFrom(meta: *const ClassMeta, needle: Value) !Value {
    var it = meta.static_properties.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        if (Value_isObject(val)) {
            const obj = Value_asObject(val);
            if (obj.getPropertyDirect("value")) |backing| {
                const eq = try php_eq(backing, needle);
                if (eq.asBool()) {
                    _ = val.retain();
                    return val;
                }
            }
        }
    }
    return Value.initNull();
}

/// 调用静态方法
pub fn php_call_static(class_name: []const u8, method_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    return php_call_static_with_ctx(Value.initNull(), class_name, method_name, args, allocator);
}

pub fn php_call_static_with_ctx(ctx: Value, class_name: []const u8, method_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const lookup_meta = blk: {
        if (std.mem.eql(u8, class_name, "self")) {
            break :blk getCurrentScopeClass() orelse {
                return throwException("Cannot access self:: when no class scope is active", allocator);
            };
        }
        if (std.mem.eql(u8, class_name, "parent")) {
            const scope = getCurrentScopeClass() orelse {
                return throwException("Cannot access parent:: when no class scope is active", allocator);
            };
            break :blk scope.parent orelse {
                return throwException("Cannot access parent:: when current class has no parent", allocator);
            };
        }
        if (std.mem.eql(u8, class_name, "static")) {
            // static:: 回退：先查 called class，再查 scope class
            break :blk getCurrentCalledClass() orelse getCurrentScopeClass() orelse {
                return throwException("Cannot access static:: when no class scope is active", allocator);
            };
        }
        break :blk findClass(class_name) orelse {
            const msg = std.fmt.allocPrint(allocator, "Class \"{s}\" not found", .{class_name}) catch return Value.initNull();
            defer allocator.free(msg);
            return throwException(msg, allocator);
        };
    };

    const called_meta = blk: {
        if (std.mem.eql(u8, class_name, "self") or
            std.mem.eql(u8, class_name, "parent") or
            std.mem.eql(u8, class_name, "static"))
        {
            // 与 lookup_meta 同步回退逻辑
            break :blk getCurrentCalledClass() orelse getCurrentScopeClass() orelse lookup_meta;
        }
        break :blk lookup_meta;
    };

    // 查找方法（静态或实例方法）
    if (lookup_meta.findMethodLookup(method_name)) |lookup| {
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(ctx, args, allocator);
    }

    // Enum 内置静态方法: cases(), from(), tryFrom()
    if (std.mem.eql(u8, method_name, "cases")) {
        return enumCases(lookup_meta, allocator);
    }
    if (std.mem.eql(u8, method_name, "from")) {
        if (args.len == 0) return error.InvalidArgumentCount;
        return enumFrom(lookup_meta, args[0], allocator);
    }
    if (std.mem.eql(u8, method_name, "tryFrom")) {
        if (args.len == 0) return error.InvalidArgumentCount;
        return enumTryFrom(lookup_meta, args[0]);
    }

    // 调用 __callStatic 魔法函数
    if (lookup_meta.findMethodLookup("__callStatic")) |lookup| {
        const name_str = try PHPString.init(allocator, method_name);
        const name_val = Value.initString(name_str);
        defer name_val.release(allocator);
        const args_arr = try PHPArray.init(allocator);
        for (args) |arg| {
            try args_arr.push(allocator, arg);
        }
        const call_args = [_]Value{ name_val, Value.initArray(args_arr) };
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(Value.initNull(), &call_args, allocator);
    }

    return error.MethodNotFound;
}

/// 获取静态属性
pub fn php_get_static_property(class_name: []const u8, property_name: []const u8) !Value {
    const meta = blk: {
        if (std.mem.eql(u8, class_name, "self")) {
            // 尝试从当前作用域获取
            if (getCurrentScopeClass()) |scope| {
                break :blk scope;
            }
            // 如果没有作用域，尝试从调用类获取
            if (getCurrentCalledClass()) |called| {
                break :blk called;
            }
            std.debug.print("ERROR: getCurrentScopeClass() returned null for 'self'\n", .{});
            return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_name, "parent")) {
            const scope = getCurrentScopeClass() orelse return error.ClassNotFound;
            break :blk scope.parent orelse return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_name, "static")) {
            break :blk getCurrentCalledClass() orelse return error.ClassNotFound;
        }
        break :blk findClass(class_name) orelse return error.ClassNotFound;
    };
    const val = meta.getStaticProperty(property_name);
    if (val == null) {
        std.debug.print("ERROR: Property {s}.{s} not found\n", .{ meta.name, property_name });
    }
    return val orelse Value.initNull();
}

/// 设置静态属性
pub fn php_set_static_property(class_name: []const u8, property_name: []const u8, value: Value) !Value {
    var meta = blk: {
        if (std.mem.eql(u8, class_name, "self")) {
            break :blk @constCast(getCurrentScopeClass() orelse return error.ClassNotFound);
        }
        if (std.mem.eql(u8, class_name, "parent")) {
            const scope = getCurrentScopeClass() orelse return error.ClassNotFound;
            break :blk @constCast(scope.parent orelse return error.ClassNotFound);
        }
        if (std.mem.eql(u8, class_name, "static")) {
            break :blk @constCast(getCurrentCalledClass() orelse return error.ClassNotFound);
        }
        break :blk findClass(class_name) orelse return error.ClassNotFound;
    };
    try meta.setStaticProperty(property_name, value);
    return Value.initNull();
}

fn serializeValue(buffer: *std.ArrayListUnmanaged(u8), value: Value, allocator: Allocator) !void {
    if (value.isNull()) {
        try buffer.appendSlice(allocator, "N;");
        return;
    }
    if (value.isBool()) {
        try buffer.print("b:{d};", .{if (value.toBool()) @as(i64, 1) else @as(i64, 0)});
        return;
    }
    if (value.isInt()) {
        try buffer.print("i:{d};", .{value.toInt()});
        return;
    }
    if (value.isFloat()) {
        try buffer.print("d:{d};", .{value.toFloat()});
        return;
    }
    if (value.isString()) {
        const str = value.asString().data;
        try buffer.print("s:{d}:\"", .{str.len});
        try buffer.appendSlice(allocator, str);
        try buffer.appendSlice(allocator, "\";");
        return;
    }
    if (value.isArray()) {
        const arr = value.asArray();
        const count = arr.elements.count();
        try buffer.print("a:{d}:{{", .{count});
        var it = arr.elements.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            switch (key) {
                .integer => |i| try buffer.print("i:{d};", .{i}),
                .string => |s| {
                    const k = s.data;
                    try buffer.print("s:{d}:\"", .{k.len});
                    try buffer.appendSlice(allocator, k);
                    try buffer.appendSlice(allocator, "\";");
                },
            }
            try serializeValue(buffer, entry.value_ptr.*, allocator);
        }
        try buffer.appendSlice(allocator, "}");
        return;
    }
    if (Value_isObject(value)) {
        const obj = Value_asObject(value);
        const class_name = obj.class_name;

        if (obj.class_meta) |meta| {
            if (meta.magic_serialize) |serializer| {
                const arr_val = try serializer(value, &.{}, allocator);
                defer arr_val.release(allocator);

                if (arr_val.isArray()) {
                    const arr = arr_val.asArray();
                    const count = arr.elements.count();
                    try buffer.print("O:{d}:\"", .{class_name.len});
                    try buffer.appendSlice(allocator, class_name);
                    try buffer.print("\":{d}:{{", .{count});

                    var it = arr.elements.iterator();
                    while (it.next()) |entry| {
                        const key = entry.key_ptr.*;
                        switch (key) {
                            .integer => |i| try buffer.print("i:{d};", .{i}),
                            .string => |s| {
                                const k = s.data;
                                try buffer.print("s:{d}:\"", .{k.len});
                                try buffer.appendSlice(allocator, k);
                                try buffer.appendSlice(allocator, "\";");
                            },
                        }
                        try serializeValue(buffer, entry.value_ptr.*, allocator);
                    }
                    try buffer.appendSlice(allocator, "}");
                    return;
                }
            }
        }

        var allow_list: ?*PHPArray = null;
        var allow_val: Value = Value.initNull();
        defer if (!allow_val.isNull()) allow_val.release(allocator);

        if (obj.class_meta) |meta| {
            if (meta.magic_sleep) |sleeper| {
                allow_val = sleeper(value, &.{}, allocator) catch Value.initNull();
                if (allow_val.isArray()) {
                    allow_list = allow_val.asArray();
                }
            }
        }

        const count: usize = if (allow_list) |list| list.elements.count() else obj.properties.count();

        try buffer.print("O:{d}:\"", .{class_name.len});
        try buffer.appendSlice(allocator, class_name);
        try buffer.print("\":{d}:{{", .{count});

        if (allow_list) |list| {
            var it_allow = list.elements.iterator();
            while (it_allow.next()) |entry| {
                const v = entry.value_ptr.*;
                if (!v.isString()) continue;
                const prop_name = v.asString().data;
                const prop_val = obj.properties.get(prop_name) orelse Value.initNull();

                const full_len: usize = class_name.len + prop_name.len + 2;
                try buffer.print("s:{d}:\"", .{full_len});
                try buffer.appendSlice(allocator, &[_]u8{0});
                try buffer.appendSlice(allocator, class_name);
                try buffer.appendSlice(allocator, &[_]u8{0});
                try buffer.appendSlice(allocator, prop_name);
                try buffer.appendSlice(allocator, "\";");

                try serializeValue(buffer, prop_val, allocator);
            }
        } else {
            var it_props = obj.properties.iterator();
            while (it_props.next()) |entry| {
                const prop_name = entry.key_ptr.*;
                const prop_val = entry.value_ptr.*;

                const full_len: usize = class_name.len + prop_name.len + 2;
                try buffer.print("s:{d}:\"", .{full_len});
                try buffer.appendSlice(allocator, &[_]u8{0});
                try buffer.appendSlice(allocator, class_name);
                try buffer.appendSlice(allocator, &[_]u8{0});
                try buffer.appendSlice(allocator, prop_name);
                try buffer.appendSlice(allocator, "\";");

                try serializeValue(buffer, prop_val, allocator);
            }
        }

        try buffer.appendSlice(allocator, "}");
        return;
    }

    try buffer.appendSlice(allocator, "N;");
}

pub fn php_serialize(value: Value, allocator: Allocator) !Value {
    var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer buffer.deinit(allocator);
    try serializeValue(&buffer, value, allocator);
    const s = try PHPString.init(allocator, buffer.items);
    return Value.initString(s);
}

fn unserializeValue(data: []const u8, pos: *usize, allocator: Allocator) !Value {
    if (pos.* >= data.len) return Value.initNull();
    const type_char = data[pos.*];
    pos.* += 1;

    switch (type_char) {
        'N' => {
            pos.* += 1;
            return Value.initNull();
        },
        'b' => {
            pos.* += 1;
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const bool_str = data[pos.*..end];
            pos.* = end + 1;
            return Value.initBool(std.mem.eql(u8, bool_str, "1"));
        },
        'i' => {
            pos.* += 1;
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const int_str = data[pos.*..end];
            pos.* = end + 1;
            const v = std.fmt.parseInt(i64, int_str, 10) catch 0;
            return Value.initInt(v);
        },
        'd' => {
            pos.* += 1;
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const float_str = data[pos.*..end];
            pos.* = end + 1;
            const v = std.fmt.parseFloat(f64, float_str) catch 0;
            return Value.initFloat(v);
        },
        's' => {
            pos.* += 1;
            const colon = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const len_str = data[pos.*..colon];
            pos.* = colon + 1;
            const len = std.fmt.parseInt(usize, len_str, 10) catch 0;
            pos.* += 1;
            const str_val = data[pos.* .. pos.* + len];
            pos.* += len + 2;
            const ps = try PHPString.init(allocator, str_val);
            return Value.initString(ps);
        },
        'a' => {
            pos.* += 1;
            const count_end = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const count_str = data[pos.*..count_end];
            pos.* = count_end + 1;
            const count = std.fmt.parseInt(usize, count_str, 10) catch 0;
            pos.* += 1;

            const arr = try PHPArray.init(allocator);
            const arr_val = Value.initArray(arr);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                const key_val = try unserializeValue(data, pos, allocator);
                const val = try unserializeValue(data, pos, allocator);
                defer key_val.release(allocator);
                defer val.release(allocator);

                const key: ArrayKey = if (key_val.isString())
                    ArrayKey{ .string = key_val.asString() }
                else
                    ArrayKey{ .integer = key_val.toInt() };

                try arr.set(allocator, key, val);
            }

            pos.* += 1;
            return arr_val;
        },
        'O' => {
            pos.* += 1; // skip ':'
            const colon1 = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const len_str = data[pos.*..colon1];
            pos.* = colon1 + 1; // skip ':'
            const name_len = std.fmt.parseInt(usize, len_str, 10) catch 0;
            pos.* += 1; // skip '"'
            const class_name = data[pos.* .. pos.* + name_len];
            pos.* += name_len + 1; // skip class_name and '"'
            pos.* += 1; // skip ':'
            const colon2 = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const count_str = data[pos.*..colon2];
            pos.* = colon2 + 1; // skip ':'
            const count = std.fmt.parseInt(usize, count_str, 10) catch 0;
            pos.* += 1; // skip '{'

            const class_name_copy = try allocator.dupe(u8, class_name);
            defer allocator.free(class_name_copy);
            const obj_val = try php_object_new(class_name_copy, allocator);
            const obj = Value_asObject(obj_val);

            const data_arr = try PHPArray.init(allocator);
            const data_arr_val = Value.initArray(data_arr);
            defer data_arr_val.release(allocator);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                const key_val = try unserializeValue(data, pos, allocator);
                const val = try unserializeValue(data, pos, allocator);

                if (!key_val.isString()) {
                    key_val.release(allocator);
                    val.release(allocator);
                    continue;
                }
                const raw_key = key_val.asString().data;
                var prop_name: []const u8 = raw_key;
                if (raw_key.len > 0 and raw_key[0] == 0) {
                    if (std.mem.indexOfScalarPos(u8, raw_key, 1, 0)) |nul2| {
                        if (nul2 + 1 <= raw_key.len) {
                            prop_name = raw_key[nul2 + 1 ..];
                        }
                    }
                }

                const prop_str = try PHPString.init(allocator, prop_name);
                const prop_key = ArrayKey{ .string = prop_str };
                try data_arr.set(allocator, prop_key, val);

                // 释放key_val，val已经被data_arr持有
                key_val.release(allocator);
            }

            pos.* += 1; // skip '}'

            if (obj.class_meta) |meta| {
                if (meta.magic_unserialize) |unser_fn| {
                    const args = [_]Value{data_arr_val};
                    _ = try unser_fn(obj_val, &args, allocator);
                    return obj_val;
                }
            }

            var it = data_arr.elements.iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.* == .string) {
                    const k = entry.key_ptr.string.data;
                    try obj.setProperty(k, entry.value_ptr.*);
                }
            }

            if (obj.class_meta) |meta| {
                if (meta.magic_wakeup) |wake| {
                    _ = wake(obj_val, &.{}, allocator) catch {};
                }
            }

            return obj_val;
        },
        else => return Value.initNull(),
    }
}

pub fn php_unserialize(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgumentType;
    const data = str.asString().data;
    var pos: usize = 0;
    return unserializeValue(data, &pos, allocator);
}

/// 检查是否是对象
pub fn php_is_object(val: Value) !Value {
    return Value.initBool(Value_isObject(val));
}

/// 获取对象的类名
pub fn php_get_class(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initBool(false);
    }

    const obj = Value_asObject(obj_val);
    const class_name_str = try PHPString.init(allocator, obj.class_name);
    return Value.initString(class_name_str);
}

pub fn get_class(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;
    return php_get_class(args[0], allocator);
}

// ============================================================================
// 异常处理
// ============================================================================

/// 当前异常（全局状态）
/// 注意：这是一个简化的异常处理机制
/// 在真实的PHP实现中，异常应该是线程局部的
// var current_exception: ?Value = null; // 已在文件顶部定义为 threadlocal

/// 设置当前异常
///
/// @param exception 异常Value
// pub fn setException(exception: Value) void { // 已在文件顶部定义
//     current_exception = exception;
// }

/// 获取当前异常
///
/// @return 当前异常，如果没有异常返回null
pub fn getCurrentException() ?Value {
    if (has_exception) return current_exception;
    return null;
}

/// 清除当前异常
pub fn clearException() void {
    if (has_exception) {
        current_exception.release(runtime_allocator);
        current_exception = Value.initNull();
        has_exception = false;
    }
}

/// 抛出异常
///
/// @param message 异常消息
/// @param allocator 内存分配器
/// @return 异常Value
pub fn throwException(message: []const u8, allocator: Allocator) !Value {
    const msg_str = try PHPString.init(allocator, message);
    const exception = Value.initString(msg_str);
    setException(exception);
    return exception;
}

pub fn throwThrowable(class_name: []const u8, message: []const u8, allocator: Allocator) !Value {
    const obj = if (findClass(class_name)) |meta|
        try PHPObject.initWithMeta(allocator, meta)
    else
        try PHPObject.init(allocator, class_name);
    const exception = Value_initObject(obj);
    const msg_str = try PHPString.init(allocator, message);
    const msg_val = Value.initString(msg_str);
    defer msg_val.release(allocator);
    try obj.setProperty("message", msg_val);
    setException(exception);
    return exception;
}

/// 检查是否有异常
///
/// @return 如果有异常返回true
pub fn hasException() bool {
    return has_exception;
}

