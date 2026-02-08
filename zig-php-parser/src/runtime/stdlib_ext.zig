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
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED
pub const JsonFunctions = struct {
    /// JSON 编码选项
    pub const EncodeOptions = struct {
        pretty_print: bool = false,
        unescaped_unicode: bool = false,
        unescaped_slashes: bool = false,
        numeric_check: bool = false,
        force_object: bool = false,
        indent_level: usize = 0,
    };

    /// JSON 解码选项
    pub const DecodeOptions = struct {
        assoc: bool = false, // 是否将对象解码为关联数组
        depth: usize = 512, // 最大递归深度
        bigint_as_string: bool = false,
    };

    /// JSON 解析器状态
    const JsonParser = struct {
        input: []const u8,
        pos: usize,
        depth: usize,
        max_depth: usize,
        allocator: std.mem.Allocator,

        fn init(allocator: std.mem.Allocator, input: []const u8, max_depth: usize) JsonParser {
            return .{
                .input = input,
                .pos = 0,
                .depth = 0,
                .max_depth = max_depth,
                .allocator = allocator,
            };
        }

        fn skipWhitespace(self: *JsonParser) void {
            while (self.pos < self.input.len) {
                switch (self.input[self.pos]) {
                    ' ', '\t', '\n', '\r' => self.pos += 1,
                    else => break,
                }
            }
        }

        fn peek(self: *JsonParser) ?u8 {
            if (self.pos >= self.input.len) return null;
            return self.input[self.pos];
        }

        fn consume(self: *JsonParser) ?u8 {
            if (self.pos >= self.input.len) return null;
            const c = self.input[self.pos];
            self.pos += 1;
            return c;
        }

        fn expect(self: *JsonParser, expected: u8) !void {
            const c = self.consume() orelse return error.UnexpectedEndOfInput;
            if (c != expected) return error.UnexpectedCharacter;
        }

        fn parseValue(self: *JsonParser, vm: anytype) error{ OutOfMemory, InvalidJson, MaxDepthExceeded, UnexpectedEndOfInput, UnexpectedCharacter }!Value {
            if (self.depth >= self.max_depth) return error.MaxDepthExceeded;

            self.skipWhitespace();
            const c = self.peek() orelse return error.UnexpectedEndOfInput;

            return switch (c) {
                'n' => try self.parseNull(),
                't', 'f' => try self.parseBool(),
                '"' => try self.parseString(vm),
                '[' => try self.parseArray(vm),
                '{' => try self.parseObject(vm),
                '-', '0'...'9' => try self.parseNumber(),
                else => error.UnexpectedCharacter,
            };
        }

        fn parseNull(self: *JsonParser) !Value {
            if (self.pos + 4 > self.input.len) return error.InvalidJson;
            if (!std.mem.eql(u8, self.input[self.pos .. self.pos + 4], "null")) return error.InvalidJson;
            self.pos += 4;
            return Value.initNull();
        }

        fn parseBool(self: *JsonParser) !Value {
            if (self.peek() == 't') {
                if (self.pos + 4 > self.input.len) return error.InvalidJson;
                if (!std.mem.eql(u8, self.input[self.pos .. self.pos + 4], "true")) return error.InvalidJson;
                self.pos += 4;
                return Value.initBool(true);
            } else {
                if (self.pos + 5 > self.input.len) return error.InvalidJson;
                if (!std.mem.eql(u8, self.input[self.pos .. self.pos + 5], "false")) return error.InvalidJson;
                self.pos += 5;
                return Value.initBool(false);
            }
        }

        fn parseString(self: *JsonParser, vm: anytype) !Value {
            try self.expect('"');
            var result = std.ArrayList(u8){ .allocator = self.allocator };
            defer result.deinit();

            while (true) {
                const c = self.consume() orelse return error.UnexpectedEndOfInput;
                if (c == '"') break;

                if (c == '\\') {
                    const escaped = self.consume() orelse return error.UnexpectedEndOfInput;
                    switch (escaped) {
                        '"' => try result.append('"'),
                        '\\' => try result.append('\\'),
                        '/' => try result.append('/'),
                        'b' => try result.append('\x08'),
                        'f' => try result.append('\x0C'),
                        'n' => try result.append('\n'),
                        'r' => try result.append('\r'),
                        't' => try result.append('\t'),
                        'u' => {
                            // Unicode escape sequence
                            if (self.pos + 4 > self.input.len) return error.InvalidJson;
                            const hex = self.input[self.pos .. self.pos + 4];
                            const codepoint = std.fmt.parseInt(u16, hex, 16) catch return error.InvalidJson;
                            self.pos += 4;

                            // Convert codepoint to UTF-8
                            var buf: [4]u8 = undefined;
                            const len = std.unicode.utf8Encode(codepoint, &buf) catch return error.InvalidJson;
                            try result.appendSlice(buf[0..len]);
                        },
                        else => return error.InvalidJson,
                    }
                } else {
                    try result.append(c);
                }
            }

            const str = try result.toOwnedSlice();
            defer self.allocator.free(str);
            return Value.initStringWithManager(&vm.memory_manager, str);
        }

        fn parseNumber(self: *JsonParser) !Value {
            const start = self.pos;
            var has_decimal = false;
            var has_exponent = false;

            // Optional minus
            if (self.peek() == '-') _ = self.consume();

            // Integer part
            if (self.peek() == '0') {
                _ = self.consume();
            } else {
                if (self.peek()) |c| {
                    if (c < '1' or c > '9') return error.InvalidJson;
                } else return error.UnexpectedEndOfInput;
                _ = self.consume();

                while (self.peek()) |c| {
                    if (c >= '0' and c <= '9') {
                        _ = self.consume();
                    } else break;
                }
            }

            // Decimal part
            if (self.peek() == '.') {
                has_decimal = true;
                _ = self.consume();
                var digit_count: usize = 0;
                while (self.peek()) |c| {
                    if (c >= '0' and c <= '9') {
                        _ = self.consume();
                        digit_count += 1;
                    } else break;
                }
                if (digit_count == 0) return error.InvalidJson;
            }

            // Exponent part
            if (self.peek()) |c| {
                if (c == 'e' or c == 'E') {
                    has_exponent = true;
                    _ = self.consume();
                    if (self.peek()) |sign| {
                        if (sign == '+' or sign == '-') _ = self.consume();
                    }
                    var digit_count: usize = 0;
                    while (self.peek()) |d| {
                        if (d >= '0' and d <= '9') {
                            _ = self.consume();
                            digit_count += 1;
                        } else break;
                    }
                    if (digit_count == 0) return error.InvalidJson;
                }
            }

            const num_str = self.input[start..self.pos];

            if (has_decimal or has_exponent) {
                const num = std.fmt.parseFloat(f64, num_str) catch return error.InvalidJson;
                return Value.initFloat(num);
            } else {
                const num = std.fmt.parseInt(i64, num_str, 10) catch return error.InvalidJson;
                return Value.initInt(num);
            }
        }

        fn parseArray(self: *JsonParser, vm: anytype) !Value {
            try self.expect('[');
            self.depth += 1;
            defer self.depth -= 1;

            var elements = std.ArrayList(Value){ .allocator = self.allocator };
            defer elements.deinit();

            self.skipWhitespace();
            if (self.peek() == ']') {
                _ = self.consume();
                // Create empty array
                const arr = try vm.memory_manager.createArray();
                return Value.initArray(arr);
            }

            while (true) {
                const value = try self.parseValue(vm);
                try elements.append(value);

                self.skipWhitespace();
                const c = self.consume() orelse return error.UnexpectedEndOfInput;
                if (c == ']') break;
                if (c != ',') return error.UnexpectedCharacter;
                self.skipWhitespace();
            }

            // Create array and populate
            const arr = try vm.memory_manager.createArray();
            for (elements.items, 0..) |elem, i| {
                try arr.data.set(Value.initInt(@intCast(i)), elem);
            }

            return Value.initArray(arr);
        }

        fn parseObject(self: *JsonParser, vm: anytype) !Value {
            try self.expect('{');
            self.depth += 1;
            defer self.depth -= 1;

            const arr = try vm.memory_manager.createArray();

            self.skipWhitespace();
            if (self.peek() == '}') {
                _ = self.consume();
                return Value.initArray(arr);
            }

            while (true) {
                self.skipWhitespace();

                // Parse key (must be string)
                if (self.peek() != '"') return error.UnexpectedCharacter;
                const key_value = try self.parseString(vm);
                const key_str = key_value.getAsString().data.data;

                self.skipWhitespace();
                try self.expect(':');

                // Parse value
                const value = try self.parseValue(vm);

                // Store in array as associative
                const key = try vm.memory_manager.createString(key_str);
                try arr.data.set(Value.initString(key), value);

                self.skipWhitespace();
                const c = self.consume() orelse return error.UnexpectedEndOfInput;
                if (c == '}') break;
                if (c != ',') return error.UnexpectedCharacter;
            }

            return Value.initArray(arr);
        }
    };

    /// json_encode - 将PHP值编码为JSON
    /// @pre args.len >= 1
    /// @post 返回 JSON 字符串或 false
    pub fn jsonEncode(vm: anytype, args: []const Value) !Value {
        if (args.len < 1) {
            return Value.initBool(false);
        }

        // 解析选项
        var options = EncodeOptions{};
        if (args.len >= 2) {
            if (args[1].getTag() == .integer) {
                const flags = args[1].asInt();
                // JSON_PRETTY_PRINT = 128
                if (flags & 128 != 0) options.pretty_print = true;
                // JSON_UNESCAPED_UNICODE = 256
                if (flags & 256 != 0) options.unescaped_unicode = true;
                // JSON_UNESCAPED_SLASHES = 64
                if (flags & 64 != 0) options.unescaped_slashes = true;
                // JSON_NUMERIC_CHECK = 32
                if (flags & 32 != 0) options.numeric_check = true;
                // JSON_FORCE_OBJECT = 16
                if (flags & 16 != 0) options.force_object = true;
            }
        }

        var result = std.ArrayList(u8){ .allocator = vm.allocator };
        defer result.deinit();

        try encodeValue(&result, args[0], options);

        const json_str = try result.toOwnedSlice();
        defer vm.allocator.free(json_str);
        return Value.initStringWithManager(&vm.memory_manager, json_str);
    }

    fn encodeValue(result: *std.ArrayList(u8), value: Value, options: EncodeOptions) error{ OutOfMemory, Overflow }!void {
        switch (value.getTag()) {
            .null => try result.appendSlice("null"),
            .boolean => try result.appendSlice(if (value.asBool()) "true" else "false"),
            .integer => try result.writer().print("{d}", .{value.asInt()}),
            .float => {
                const f = value.asFloat();
                if (std.math.isNan(f) or std.math.isInf(f)) {
                    try result.appendSlice("null");
                } else {
                    try result.writer().print("{d}", .{f});
                }
            },
            .string => {
                try result.append('"');
                const str_data = value.getAsString().data.data;
                for (str_data) |c| {
                    switch (c) {
                        '"' => try result.appendSlice("\\\""),
                        '\\' => try result.appendSlice("\\\\"),
                        '/' => {
                            if (options.unescaped_slashes) {
                                try result.append('/');
                            } else {
                                try result.appendSlice("\\/");
                            }
                        },
                        '\n' => try result.appendSlice("\\n"),
                        '\r' => try result.appendSlice("\\r"),
                        '\t' => try result.appendSlice("\\t"),
                        '\x08' => try result.appendSlice("\\b"),
                        '\x0C' => try result.appendSlice("\\f"),
                        0x00...0x1F => try result.writer().print("\\u{x:0>4}", .{c}),
                        else => {
                            if (options.unescaped_unicode or (c >= 0x20 and c <= 0x7E)) {
                                try result.append(c);
                            } else {
                                try result.writer().print("\\u{x:0>4}", .{c});
                            }
                        },
                    }
                }
                try result.append('"');
            },
            .array => {
                const arr = value.getAsArray().data;
                var is_object = false;
                var max_index: i64 = -1;
                var has_string_keys = false;

                // 检查是否是关联数组或对象
                var iter = arr.elements.iterator();
                while (iter.next()) |entry| {
                    switch (entry.key_ptr.*) {
                        .string => {
                            has_string_keys = true;
                            is_object = true;
                        },
                        .integer => |i| {
                            if (i > max_index) max_index = i;
                        },
                    }
                }

                // 如果有字符串键或强制对象，编码为对象
                if (is_object or options.force_object) {
                    try result.append('{');
                    if (options.pretty_print) try result.append('\n');

                    var first = true;
                    var obj_iter = arr.elements.iterator();
                    while (obj_iter.next()) |entry| {
                        if (!first) {
                            try result.append(',');
                            if (options.pretty_print) try result.append('\n');
                        }
                        first = false;

                        if (options.pretty_print) {
                            try result.appendNTimes(' ', (options.indent_level + 1) * 2);
                        }

                        switch (entry.key_ptr.*) {
                            .string => |s| {
                                try result.append('"');
                                try result.appendSlice(s.data);
                                try result.append('"');
                            },
                            .integer => |i| try result.writer().print("\"{d}\"", .{i}),
                        }
                        try result.append(':');
                        if (options.pretty_print) try result.append(' ');

                        var nested_options = options;
                        nested_options.indent_level += 1;
                        try encodeValue(result, entry.value_ptr.*, nested_options);
                    }

                    if (options.pretty_print) {
                        try result.append('\n');
                        try result.appendNTimes(' ', options.indent_level * 2);
                    }
                    try result.append('}');
                } else {
                    // 编码为数组
                    try result.append('[');
                    if (options.pretty_print) try result.append('\n');

                    var first = true;
                    var i: i64 = 0;
                    while (i <= max_index) : (i += 1) {
                        if (!first) {
                            try result.append(',');
                            if (options.pretty_print) try result.append('\n');
                        }
                        first = false;

                        if (options.pretty_print) {
                            try result.appendNTimes(' ', (options.indent_level + 1) * 2);
                        }

                        const key = Value.initInt(i);
                        if (arr.elements.get(key)) |val| {
                            var nested_options = options;
                            nested_options.indent_level += 1;
                            try encodeValue(result, val, nested_options);
                        } else {
                            try result.appendSlice("null");
                        }
                    }

                    if (options.pretty_print) {
                        try result.append('\n');
                        try result.appendNTimes(' ', options.indent_level * 2);
                    }
                    try result.append(']');
                }
            },
            else => try result.appendSlice("null"),
        }
    }

    /// json_decode - 解码JSON字符串
    /// @pre args.len >= 1
    /// @post 返回解析后的 PHP 值或 null
    pub fn jsonDecode(vm: anytype, args: []const Value) !Value {
        if (args.len < 1) {
            return Value.initNull();
        }

        const json_str = switch (args[0].getTag()) {
            .string => args[0].getAsString().data.data,
            else => return Value.initNull(),
        };

        // 解析选项
        var options = DecodeOptions{};
        if (args.len >= 2) {
            if (args[1].getTag() == .boolean) {
                options.assoc = args[1].asBool();
            }
        }
        if (args.len >= 3) {
            if (args[2].getTag() == .integer) {
                const depth = args[2].asInt();
                if (depth > 0) options.depth = @intCast(depth);
            }
        }

        var parser = JsonParser.init(vm.allocator, json_str, options.depth);
        return parser.parseValue(vm) catch |err| {
            // 解析失败返回 null
            _ = err;
            return Value.initNull();
        };
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
