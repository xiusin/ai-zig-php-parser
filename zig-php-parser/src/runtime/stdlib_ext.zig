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

/// 日期时间函数实现 - 使用完整实现
/// 详细实现见 datetime_complete.zig
pub const DateTimeFunctions = @import("datetime_complete.zig").DateTimeFunctions;

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
        switch (value.getTag()) {
            .null => try result.appendSlice("null"),
            .boolean => try result.appendSlice(if (value.asBool()) "true" else "false"),
            .integer => try result.writer().print("{d}", .{value.asInt()}),
            .float => try result.writer().print("{d}", .{value.asFloat()}),
            .string => {
                try result.append('"');
                const str_data = value.getAsString().data.data;
                for (str_data) |c| {
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
                const arr = value.getAsArray().data;
                var is_object = false;
                var key_count: usize = 0;
                var string_key_count: usize = 0;

                // 检查是否是关联数组
                var iter = arr.elements.iterator();
                while (iter.next()) |entry| {
                    key_count += 1;
                    std.debug.print("DEBUG: key {} is {s}\n", .{ key_count, @tagName(entry.key_ptr.*) });
                    if (entry.key_ptr.* == .string) {
                        string_key_count += 1;
                        std.debug.print("DEBUG: string key = {s}\n", .{entry.key_ptr.string.data});
                        is_object = true;
                    }
                }
                std.debug.print("DEBUG: total keys={}, string keys={}, is_object={}\n", .{ key_count, string_key_count, is_object });

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

        const json_str = switch (args[0].getTag()) {
            .string => args[0].getAsString().data.data,
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
