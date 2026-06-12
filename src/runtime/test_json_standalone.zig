const std = @import("std");
const testing = std.testing;

/// 简化的 Value 类型用于测试
const ValueTag = enum {
    null,
    boolean,
    integer,
    float,
    string,
    array,
};

const StringData = struct {
    data: []const u8,
};

const ArrayData = struct {
    elements: std.StringHashMap(TestValue),
};

const TestValue = union(ValueTag) {
    null: void,
    boolean: bool,
    integer: i64,
    float: f64,
    string: StringData,
    array: ArrayData,

    fn initNull() TestValue {
        return .{ .null = {} };
    }

    fn initBool(b: bool) TestValue {
        return .{ .boolean = b };
    }

    fn initInt(i: i64) TestValue {
        return .{ .integer = i };
    }

    fn initFloat(f: f64) TestValue {
        return .{ .float = f };
    }

    fn initString(s: []const u8) TestValue {
        return .{ .string = .{ .data = s } };
    }

    fn getTag(self: TestValue) ValueTag {
        return @as(ValueTag, self);
    }
};

/// JSON 编码选项
const EncodeOptions = struct {
    pretty_print: bool = false,
    unescaped_unicode: bool = false,
    unescaped_slashes: bool = false,
    indent_level: usize = 0,
};

/// JSON 编码函数
fn encodeValue(result: *std.ArrayList(u8), value: TestValue, options: EncodeOptions) !void {
    switch (value) {
        .null => try result.appendSlice("null"),
        .boolean => |b| try result.appendSlice(if (b) "true" else "false"),
        .integer => |i| try result.writer().print("{d}", .{i}),
        .float => |f| {
            if (std.math.isNan(f) or std.math.isInf(f)) {
                try result.appendSlice("null");
            } else {
                try result.writer().print("{d}", .{f});
            }
        },
        .string => |s| {
            try result.append('"');
            for (s.data) |c| {
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
                    else => try result.append(c),
                }
            }
            try result.append('"');
        },
        .array => {
            try result.append('[');
            try result.append(']');
        },
    }
}

/// JSON 解析器
const JsonParser = struct {
    input: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, input: []const u8) JsonParser {
        return .{
            .input = input,
            .pos = 0,
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

    fn parseValue(self: *JsonParser) !TestValue {
        self.skipWhitespace();
        const c = self.peek() orelse return error.UnexpectedEndOfInput;

        return switch (c) {
            'n' => try self.parseNull(),
            't', 'f' => try self.parseBool(),
            '"' => try self.parseString(),
            '[' => try self.parseArray(),
            '{' => try self.parseObject(),
            '-', '0'...'9' => try self.parseNumber(),
            else => error.UnexpectedCharacter,
        };
    }

    fn parseNull(self: *JsonParser) !TestValue {
        if (self.pos + 4 > self.input.len) return error.InvalidJson;
        if (!std.mem.eql(u8, self.input[self.pos .. self.pos + 4], "null")) return error.InvalidJson;
        self.pos += 4;
        return TestValue.initNull();
    }

    fn parseBool(self: *JsonParser) !TestValue {
        if (self.peek() == 't') {
            if (self.pos + 4 > self.input.len) return error.InvalidJson;
            if (!std.mem.eql(u8, self.input[self.pos .. self.pos + 4], "true")) return error.InvalidJson;
            self.pos += 4;
            return TestValue.initBool(true);
        } else {
            if (self.pos + 5 > self.input.len) return error.InvalidJson;
            if (!std.mem.eql(u8, self.input[self.pos .. self.pos + 5], "false")) return error.InvalidJson;
            self.pos += 5;
            return TestValue.initBool(false);
        }
    }

    fn parseString(self: *JsonParser) !TestValue {
        try self.expect('"');
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

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
                        if (self.pos + 4 > self.input.len) return error.InvalidJson;
                        const hex = self.input[self.pos .. self.pos + 4];
                        const codepoint = std.fmt.parseInt(u16, hex, 16) catch return error.InvalidJson;
                        self.pos += 4;

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
        return TestValue.initString(str);
    }

    fn parseNumber(self: *JsonParser) !TestValue {
        const start = self.pos;
        var has_decimal = false;
        var has_exponent = false;

        if (self.peek() == '-') _ = self.consume();

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
            return TestValue.initFloat(num);
        } else {
            const num = std.fmt.parseInt(i64, num_str, 10) catch return error.InvalidJson;
            return TestValue.initInt(num);
        }
    }

    fn parseArray(self: *JsonParser) !TestValue {
        try self.expect('[');
        self.skipWhitespace();
        if (self.peek() == ']') {
            _ = self.consume();
            return TestValue{ .array = .{ .elements = std.StringHashMap(TestValue).init(self.allocator) } };
        }

        // 简化：暂不实现完整数组解析
        return error.NotImplemented;
    }

    fn parseObject(self: *JsonParser) !TestValue {
        try self.expect('{');
        self.skipWhitespace();
        if (self.peek() == '}') {
            _ = self.consume();
            return TestValue{ .array = .{ .elements = std.StringHashMap(TestValue).init(self.allocator) } };
        }

        // 简化：暂不实现完整对象解析
        return error.NotImplemented;
    }
};

// ============================================================================
// 测试用例
// ============================================================================

test "json_encode - null" {
    var result = std.ArrayList(u8).init(testing.allocator);
    defer result.deinit();

    try encodeValue(&result, TestValue.initNull(), .{});
    try testing.expectEqualStrings("null", result.items);
}

test "json_encode - boolean" {
    {
        var result = std.ArrayList(u8).init(testing.allocator);
        defer result.deinit();
        try encodeValue(&result, TestValue.initBool(true), .{});
        try testing.expectEqualStrings("true", result.items);
    }

    {
        var result = std.ArrayList(u8).init(testing.allocator);
        defer result.deinit();
        try encodeValue(&result, TestValue.initBool(false), .{});
        try testing.expectEqualStrings("false", result.items);
    }
}

test "json_encode - integer" {
    var result = std.ArrayList(u8).init(testing.allocator);
    defer result.deinit();

    try encodeValue(&result, TestValue.initInt(42), .{});
    try testing.expectEqualStrings("42", result.items);
}

test "json_encode - float" {
    var result = std.ArrayList(u8).init(testing.allocator);
    defer result.deinit();

    try encodeValue(&result, TestValue.initFloat(3.14), .{});
    try testing.expect(std.mem.startsWith(u8, result.items, "3.14"));
}

test "json_encode - string" {
    var result = std.ArrayList(u8).init(testing.allocator);
    defer result.deinit();

    try encodeValue(&result, TestValue.initString("Hello World"), .{});
    try testing.expectEqualStrings("\"Hello World\"", result.items);
}

test "json_encode - string with escapes" {
    var result = std.ArrayList(u8).init(testing.allocator);
    defer result.deinit();

    try encodeValue(&result, TestValue.initString("Hello\n\"World\"\t\\"), .{});
    try testing.expectEqualStrings("\"Hello\\n\\\"World\\\"\\t\\\\\"", result.items);
}

test "json_decode - null" {
    var parser = JsonParser.init(testing.allocator, "null");
    const result = try parser.parseValue();
    try testing.expect(result.getTag() == .null);
}

test "json_decode - boolean" {
    {
        var parser = JsonParser.init(testing.allocator, "true");
        const result = try parser.parseValue();
        try testing.expect(result.getTag() == .boolean);
        try testing.expect(result.boolean == true);
    }

    {
        var parser = JsonParser.init(testing.allocator, "false");
        const result = try parser.parseValue();
        try testing.expect(result.getTag() == .boolean);
        try testing.expect(result.boolean == false);
    }
}

test "json_decode - integer" {
    var parser = JsonParser.init(testing.allocator, "42");
    const result = try parser.parseValue();
    try testing.expect(result.getTag() == .integer);
    try testing.expectEqual(@as(i64, 42), result.integer);
}

test "json_decode - negative integer" {
    var parser = JsonParser.init(testing.allocator, "-42");
    const result = try parser.parseValue();
    try testing.expect(result.getTag() == .integer);
    try testing.expectEqual(@as(i64, -42), result.integer);
}

test "json_decode - float" {
    var parser = JsonParser.init(testing.allocator, "3.14");
    const result = try parser.parseValue();
    try testing.expect(result.getTag() == .float);
    try testing.expectApproxEqAbs(@as(f64, 3.14), result.float, 0.001);
}

test "json_decode - scientific notation" {
    var parser = JsonParser.init(testing.allocator, "1.23e10");
    const result = try parser.parseValue();
    try testing.expect(result.getTag() == .float);
    try testing.expectApproxEqAbs(@as(f64, 1.23e10), result.float, 1.0);
}

test "json_decode - string" {
    var parser = JsonParser.init(testing.allocator, "\"Hello World\"");
    const result = try parser.parseValue();
    defer testing.allocator.free(result.string.data);

    try testing.expect(result.getTag() == .string);
    try testing.expectEqualStrings("Hello World", result.string.data);
}

test "json_decode - string with escapes" {
    var parser = JsonParser.init(testing.allocator, "\"Hello\\n\\\"World\\\"\\t\\\\\"");
    const result = try parser.parseValue();
    defer testing.allocator.free(result.string.data);

    try testing.expect(result.getTag() == .string);
    try testing.expectEqualStrings("Hello\n\"World\"\t\\", result.string.data);
}

test "json_decode - unicode escape" {
    var parser = JsonParser.init(testing.allocator, "\"\\u4F60\\u597D\"");
    const result = try parser.parseValue();
    defer testing.allocator.free(result.string.data);

    try testing.expect(result.getTag() == .string);
    try testing.expectEqualStrings("你好", result.string.data);
}

test "json_decode - whitespace handling" {
    var parser = JsonParser.init(testing.allocator, "  42  ");
    const result = try parser.parseValue();
    try testing.expectEqual(@as(i64, 42), result.integer);
}

test "json_decode - empty array" {
    var parser = JsonParser.init(testing.allocator, "[]");
    const result = try parser.parseValue();
    try testing.expect(result.getTag() == .array);
}

test "json_decode - empty object" {
    var parser = JsonParser.init(testing.allocator, "{}");
    const result = try parser.parseValue();
    try testing.expect(result.getTag() == .array);
}
