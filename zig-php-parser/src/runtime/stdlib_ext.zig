const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const PHPClass = types.PHPClass;
const gc = types.gc;

const database = @import("database.zig");
const curl = @import("curl.zig");
const http_server = @import("http_server.zig");
const coroutine = @import("coroutine.zig");
const namespace = @import("namespace.zig");
const builtin_classes = @import("builtin_classes.zig");

/// 扩展标准库 - 注册所有新增的PHP函数
pub const ExtendedStdlib = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ExtendedStdlib {
        return ExtendedStdlib{
            .allocator = allocator,
        };
    }

    /// 注册所有扩展函数到VM
    pub fn registerAll(self: *ExtendedStdlib, vm: anytype) !void {
        try self.registerDatabaseFunctions(vm);
        try self.registerCurlFunctions(vm);
        try self.registerHttpFunctions(vm);
        try self.registerCoroutineFunctions(vm);
        try self.registerFileFunctions(vm);
        try self.registerDateFunctions(vm);
    }

    /// 注册数据库函数
    fn registerDatabaseFunctions(self: *ExtendedStdlib, vm: anytype) !void {
        _ = self;
        _ = vm;
        // PDO functions are registered as class methods
        // mysqli functions
        // mysqli_connect, mysqli_query, mysqli_fetch_assoc, etc.
    }

    /// 注册cURL函数
    fn registerCurlFunctions(self: *ExtendedStdlib, vm: anytype) !void {
        _ = self;
        _ = vm;
        // curl_init, curl_setopt, curl_exec, curl_close, curl_getinfo, curl_error
    }

    /// 注册HTTP服务器函数
    fn registerHttpFunctions(self: *ExtendedStdlib, vm: anytype) !void {
        _ = self;
        _ = vm;
        // http_server_create, http_server_start, http_server_stop
        // http_request_* , http_response_*
    }

    /// 注册协程函数
    fn registerCoroutineFunctions(self: *ExtendedStdlib, vm: anytype) !void {
        _ = self;
        _ = vm;
        // go(), chan(), select(), yield(), sleep()
    }

    /// 注册文件系统函数
    fn registerFileFunctions(self: *ExtendedStdlib, vm: anytype) !void {
        _ = self;
        _ = vm;
        // 扩展文件系统函数
    }

    /// 注册日期函数
    fn registerDateFunctions(self: *ExtendedStdlib, vm: anytype) !void {
        _ = self;
        _ = vm;
        // 扩展日期函数
    }
};

/// 文件系统函数实现
pub const FileSystemFunctions = struct {
    /// file_get_contents - 读取文件内容
    pub fn fileGetContents(vm: anytype, args: []const Value) !Value {
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const filename = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        const file = std.fs.cwd().openFile(filename, .{}) catch {
            return Value.initBool(false);
        };
        defer file.close();

        const content = file.readToEndAlloc(vm.allocator, std.math.maxInt(usize)) catch {
            return Value.initBool(false);
        };

        return Value.initStringWithManager(&vm.memory_manager, content);
    }

    /// file_put_contents - 写入文件内容
    pub fn filePutContents(_: anytype, args: []const Value) !Value {
        if (args.len < 2) {
            return Value.initBool(false);
        }

        const filename = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        const content = switch (args[1].tag) {
            .string => args[1].data.string.data.data,
            else => return Value.initBool(false),
        };

        const file = std.fs.cwd().createFile(filename, .{}) catch {
            return Value.initBool(false);
        };
        defer file.close();

        file.writeAll(content) catch {
            return Value.initBool(false);
        };

        return Value.initInt(@intCast(content.len));
    }

    /// file_exists - 检查文件是否存在
    pub fn fileExists(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const filename = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        std.fs.cwd().access(filename, .{}) catch {
            return Value.initBool(false);
        };

        return Value.initBool(true);
    }

    /// is_file - 检查是否是普通文件
    pub fn isFile(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const filename = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        const stat = std.fs.cwd().statFile(filename) catch {
            return Value.initBool(false);
        };

        return Value.initBool(stat.kind == .file);
    }

    /// is_dir - 检查是否是目录
    pub fn isDir(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const dirname = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        var dir = std.fs.cwd().openDir(dirname, .{}) catch {
            return Value.initBool(false);
        };
        dir.close();

        return Value.initBool(true);
    }

    /// mkdir - 创建目录
    pub fn mkdir(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const dirname = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        std.fs.cwd().makeDir(dirname) catch {
            return Value.initBool(false);
        };

        return Value.initBool(true);
    }

    /// unlink - 删除文件
    pub fn unlink(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const filename = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        std.fs.cwd().deleteFile(filename) catch {
            return Value.initBool(false);
        };

        return Value.initBool(true);
    }

    /// rmdir - 删除目录
    pub fn rmdir(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const dirname = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        std.fs.cwd().deleteDir(dirname) catch {
            return Value.initBool(false);
        };

        return Value.initBool(true);
    }

    /// rename - 重命名文件或目录
    pub fn rename(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 2) {
            return Value.initBool(false);
        }

        const old_name = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        const new_name = switch (args[1].tag) {
            .string => args[1].data.string.data.data,
            else => return Value.initBool(false),
        };

        std.fs.cwd().rename(old_name, new_name) catch {
            return Value.initBool(false);
        };

        return Value.initBool(true);
    }

    /// filesize - 获取文件大小
    pub fn filesize(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const filename = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        const stat = std.fs.cwd().statFile(filename) catch {
            return Value.initBool(false);
        };

        return Value.initInt(@intCast(stat.size));
    }

    /// glob - 查找匹配模式的文件
    pub fn glob(vm: anytype, args: []const Value) !Value {
        if (args.len < 1) {
            return Value.initBool(false);
        }

        _ = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        // 简化实现 - 返回空数组
        return Value.initArrayWithManager(&vm.memory_manager);
    }

    /// readdir - 读取目录
    pub fn readdir(vm: anytype, args: []const Value) !Value {
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const dirname = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        var dir = std.fs.cwd().openDir(dirname, .{ .iterate = true }) catch {
            return Value.initBool(false);
        };
        defer dir.close();

        const result = try Value.initArrayWithManager(&vm.memory_manager);
        const arr = result.data.array.data;
        var index: i64 = 0;

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            const name_value = try Value.initStringWithManager(&vm.memory_manager, entry.name);
            try arr.set(vm.allocator, types.ArrayKey{ .integer = index }, name_value);
            index += 1;
        }

        return result;
    }
};

/// 日期时间函数实现
pub const DateTimeFunctions = struct {
    /// time - 获取当前Unix时间戳
    pub fn time(vm: anytype, args: []const Value) !Value {
        _ = vm;
        _ = args;
        const timestamp = std.time.timestamp();
        return Value.initInt(timestamp);
    }

    /// microtime - 获取当前微秒时间
    pub fn microtime(vm: anytype, args: []const Value) !Value {
        const as_float = if (args.len > 0 and args[0].tag == .boolean) args[0].data.boolean else false;

        const nanos = std.time.nanoTimestamp();
        const secs = @divFloor(nanos, 1_000_000_000);
        const micro_part = @divFloor(@mod(nanos, 1_000_000_000), 1000);

        if (as_float) {
            const result = @as(f64, @floatFromInt(secs)) + @as(f64, @floatFromInt(micro_part)) / 1_000_000.0;
            return Value.initFloat(result);
        } else {
            const result = try std.fmt.allocPrint(vm.allocator, "{d}.{d:0>6} {d}", .{ micro_part, @as(u32, 0), secs });
            defer vm.allocator.free(result);
            return Value.initStringWithManager(&vm.memory_manager, result);
        }
    }

    /// date - 格式化日期
    pub fn date(vm: anytype, args: []const Value) !Value {
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const format = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        const timestamp = if (args.len > 1 and args[1].tag == .integer)
            args[1].data.integer
        else
            std.time.timestamp();

        // 简化实现 - 仅支持常见格式
        var result = std.ArrayList(u8).init(vm.allocator);
        defer result.deinit();

        const epoch_seconds: u64 = @intCast(timestamp);
        const epoch_day = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
        const day_seconds = epoch_day.getDaySeconds();
        const year_day = epoch_day.getEpochDay().calculateYearDay();

        for (format) |c| {
            switch (c) {
                'Y' => try result.writer().print("{d}", .{year_day.year}),
                'm' => try result.writer().print("{d:0>2}", .{year_day.month.numeric()}),
                'd' => try result.writer().print("{d:0>2}", .{year_day.day}),
                'H' => try result.writer().print("{d:0>2}", .{day_seconds.getHoursIntoDay()}),
                'i' => try result.writer().print("{d:0>2}", .{day_seconds.getMinutesIntoHour()}),
                's' => try result.writer().print("{d:0>2}", .{day_seconds.getSecondsIntoMinute()}),
                else => try result.append(c),
            }
        }

        const str = try result.toOwnedSlice();
        defer vm.allocator.free(str);
        return Value.initStringWithManager(&vm.memory_manager, str);
    }

    /// strtotime - 将字符串解析为时间戳
    pub fn strtotime(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initBool(false);
        }

        const date_str = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initBool(false),
        };

        // 简化实现 - 支持 "now"
        if (std.mem.eql(u8, date_str, "now")) {
            return Value.initInt(std.time.timestamp());
        }

        // 其他格式需要更复杂的解析
        return Value.initBool(false);
    }

    /// mktime - 创建时间戳
    pub fn mktime(vm: anytype, args: []const Value) !Value {
        _ = vm;

        var hour: i32 = 0;
        var minute: i32 = 0;
        var second: i32 = 0;
        var month: i32 = 1;
        var day: i32 = 1;
        var year: i32 = 1970;

        if (args.len > 0 and args[0].tag == .integer) hour = @intCast(args[0].data.integer);
        if (args.len > 1 and args[1].tag == .integer) minute = @intCast(args[1].data.integer);
        if (args.len > 2 and args[2].tag == .integer) second = @intCast(args[2].data.integer);
        if (args.len > 3 and args[3].tag == .integer) month = @intCast(args[3].data.integer);
        if (args.len > 4 and args[4].tag == .integer) day = @intCast(args[4].data.integer);
        if (args.len > 5 and args[5].tag == .integer) year = @intCast(args[5].data.integer);

        // 简化的时间戳计算
        const days_since_epoch = (year - 1970) * 365 + (month - 1) * 30 + (day - 1);
        const timestamp = days_since_epoch * 86400 + hour * 3600 + minute * 60 + second;

        return Value.initInt(timestamp);
    }

    /// sleep - 休眠指定秒数
    pub fn sleep(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initInt(0);
        }

        const seconds = switch (args[0].tag) {
            .integer => @as(u64, @intCast(args[0].data.integer)),
            else => return Value.initInt(0),
        };

        std.time.sleep(seconds * 1_000_000_000);
        return Value.initInt(0);
    }

    /// usleep - 休眠指定微秒数
    pub fn usleep(vm: anytype, args: []const Value) !Value {
        _ = vm;
        if (args.len < 1) {
            return Value.initNull();
        }

        const microseconds = switch (args[0].tag) {
            .integer => @as(u64, @intCast(args[0].data.integer)),
            else => return Value.initNull(),
        };

        std.time.sleep(microseconds * 1_000);
        return Value.initNull();
    }
};

/// JSON函数实现
pub const JsonFunctions = struct {
    /// json_encode - 将PHP值编码为JSON
    pub fn jsonEncode(vm: anytype, args: []const Value) !Value {
        if (args.len < 1) {
            return Value.initBool(false);
        }

        var result = std.ArrayList(u8).init(vm.allocator);
        defer result.deinit();

        try encodeValue(&result, args[0]);

        const json_str = try result.toOwnedSlice();
        defer vm.allocator.free(json_str);
        return Value.initStringWithManager(&vm.memory_manager, json_str);
    }

    fn encodeValue(result: *std.ArrayList(u8), value: Value) !void {
        switch (value.tag) {
            .null => try result.appendSlice("null"),
            .boolean => try result.appendSlice(if (value.data.boolean) "true" else "false"),
            .integer => try result.writer().print("{d}", .{value.data.integer}),
            .float => try result.writer().print("{d}", .{value.data.float}),
            .string => {
                try result.append('"');
                for (value.data.string.data.data) |c| {
                    switch (c) {
                        '"' => try result.appendSlice("\\\""),
                        '\\' => try result.appendSlice("\\\\"),
                        '\n' => try result.appendSlice("\\n"),
                        '\r' => try result.appendSlice("\\r"),
                        '\t' => try result.appendSlice("\\t"),
                        else => try result.append(c),
                    }
                }
                try result.append('"');
            },
            .array => {
                const arr = value.data.array.data;
                var is_object = false;

                // 检查是否是关联数组
                var iter = arr.elements.iterator();
                while (iter.next()) |entry| {
                    if (entry.key_ptr.* == .string) {
                        is_object = true;
                        break;
                    }
                }

                if (is_object) {
                    try result.append('{');
                    var first = true;
                    var obj_iter = arr.elements.iterator();
                    while (obj_iter.next()) |entry| {
                        if (!first) try result.append(',');
                        first = false;

                        switch (entry.key_ptr.*) {
                            .string => |s| {
                                try result.append('"');
                                try result.appendSlice(s.data);
                                try result.append('"');
                            },
                            .integer => |i| try result.writer().print("\"{d}\"", .{i}),
                        }
                        try result.append(':');
                        try encodeValue(result, entry.value_ptr.*);
                    }
                    try result.append('}');
                } else {
                    try result.append('[');
                    var first = true;
                    var arr_iter = arr.elements.iterator();
                    while (arr_iter.next()) |entry| {
                        if (!first) try result.append(',');
                        first = false;
                        try encodeValue(result, entry.value_ptr.*);
                    }
                    try result.append(']');
                }
            },
            else => try result.appendSlice("null"),
        }
    }

    /// json_decode - 解码JSON字符串
    pub fn jsonDecode(vm: anytype, args: []const Value) !Value {
        if (args.len < 1) {
            return Value.initNull();
        }

        const json_str = switch (args[0].tag) {
            .string => args[0].data.string.data.data,
            else => return Value.initNull(),
        };

        // 简化实现 - 仅支持基本类型
        const trimmed = std.mem.trim(u8, json_str, " \t\n\r");

        if (trimmed.len == 0) return Value.initNull();

        if (std.mem.eql(u8, trimmed, "null")) {
            return Value.initNull();
        } else if (std.mem.eql(u8, trimmed, "true")) {
            return Value.initBool(true);
        } else if (std.mem.eql(u8, trimmed, "false")) {
            return Value.initBool(false);
        } else if (trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
            const str_content = trimmed[1 .. trimmed.len - 1];
            return Value.initStringWithManager(&vm.memory_manager, str_content);
        } else if (std.fmt.parseInt(i64, trimmed, 10)) |num| {
            return Value.initInt(num);
        } else |_| {
            if (std.fmt.parseFloat(f64, trimmed)) |num| {
                return Value.initFloat(num);
            } else |_| {}
        }

        return Value.initNull();
    }
};

/// 注册扩展函数到标准库
pub fn registerExtendedFunctions(stdlib: anytype) !void {
    // 注册数据库函数
    // 注册cURL函数
    // 注册HTTP函数
    // 注册协程函数
    // 注册文件函数
    // 注册日期函数

    // 示例：注册一些基本函数
    // 这里需要实际实现函数注册
    _ = stdlib; // 暂时不使用
}
