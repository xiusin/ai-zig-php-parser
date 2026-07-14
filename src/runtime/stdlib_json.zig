//! JSON 内置函数实现模块
//! 从 stdlib.zig 拆分而来 — 包含 JSON 编解码、错误处理函数

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const VM = @import("vm.zig").VM;

// JSON Function Implementations
pub fn jsonEncodeFn(vm: *VM, args: []const Value) !Value {
    const value = args[0];

    // Simplified JSON encoding
    const json_str = try encodeValueAsJson(value, vm.allocator);

    const result_str = try PHPString.init(vm.allocator, json_str);
    vm.allocator.free(json_str);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn jsonDecodeFn(vm: *VM, args: []const Value) !Value {
    const json_str = args[0];
    const assoc = if (args.len > 1) args[1].asBool() else false;

    if (json_str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "json_decode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const json_data = json_str.getAsString().data.data;
    var parser = JsonParser{ .input = json_data, .pos = 0 };
    return try parser.parseValue(vm.allocator, vm, assoc);
}

pub const JsonParser = struct {
    input: []const u8,
    pos: usize,

    pub fn skipWhitespace(self: *JsonParser) void {
        while (self.pos < self.input.len) {
            switch (self.input[self.pos]) {
                ' ', '\n', '\r', '\t' => self.pos += 1,
                else => break,
            }
        }
    }

    const JsonParseError = error{OutOfMemory};

    pub fn parseValue(self: *JsonParser, allocator: std.mem.Allocator, vm: *VM, assoc: bool) JsonParseError!Value {
        self.skipWhitespace();
        if (self.pos >= self.input.len) {
            return Value.initNull();
        }

        return switch (self.input[self.pos]) {
            'n' => self.parseNull() catch Value.initNull(),
            't' => self.parseTrue() catch Value.initNull(),
            'f' => self.parseFalse() catch Value.initNull(),
            '"' => self.parseString(allocator),
            '[' => self.parseArray(allocator, vm, assoc),
            '{' => self.parseObject(allocator, vm, assoc),
            '-', '0'...'9' => self.parseNumber(),
            else => Value.initNull(),
        };
    }

    pub fn parseNull(self: *JsonParser) !Value {
        if (std.mem.startsWith(u8, self.input[self.pos..], "null")) {
            self.pos += 4;
            return Value.initNull();
        }
        return Value.initNull();
    }

    pub fn parseTrue(self: *JsonParser) !Value {
        if (std.mem.startsWith(u8, self.input[self.pos..], "true")) {
            self.pos += 4;
            return Value.initBool(true);
        }
        return Value.initNull();
    }

    pub fn parseFalse(self: *JsonParser) !Value {
        if (std.mem.startsWith(u8, self.input[self.pos..], "false")) {
            self.pos += 5;
            return Value.initBool(false);
        }
        return Value.initNull();
    }

    pub fn parseString(self: *JsonParser, allocator: std.mem.Allocator) !Value {
        self.pos += 1; // Skip opening quote
        var result = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
        defer result.deinit(allocator);

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == '"') {
                self.pos += 1;
                const slice = try result.toOwnedSlice(allocator);
                const val = try Value.initString(allocator, slice);
                allocator.free(slice);
                return val;
            }
            if (c == '\\' and self.pos + 1 < self.input.len) {
                self.pos += 1;
                const escaped = self.input[self.pos];
                switch (escaped) {
                    '"' => try result.append(allocator, '"'),
                    '\\' => try result.append(allocator, '\\'),
                    '/' => try result.append(allocator, '/'),
                    'b' => try result.append(allocator, '\x08'),
                    'f' => try result.append(allocator, '\x0C'),
                    'n' => try result.append(allocator, '\n'),
                    'r' => try result.append(allocator, '\r'),
                    't' => try result.append(allocator, '\t'),
                    'u' => {
                        // Unicode escape - skip for now
                        self.pos += 1;
                    },
                    else => try result.append(allocator, escaped),
                }
            } else {
                try result.append(allocator, c);
            }
            self.pos += 1;
        }

        return Value.initNull();
    }

    pub fn parseNumber(self: *JsonParser) !Value {
        const start = self.pos;
        if (self.input[self.pos] == '-') self.pos += 1;
        while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
            self.pos += 1;
        }
        if (self.pos < self.input.len and self.input[self.pos] == '.') {
            self.pos += 1;
            while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
                self.pos += 1;
            }
        }
        if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            self.pos += 1;
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) {
                self.pos += 1;
            }
            while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
                self.pos += 1;
            }
        }

        const num_str = self.input[start..self.pos];
        if (std.mem.indexOf(u8, num_str, ".") != null or
            std.mem.indexOf(u8, num_str, "e") != null or
            std.mem.indexOf(u8, num_str, "E") != null)
        {
            if (std.fmt.parseFloat(f64, num_str)) |f| {
                return Value.initFloat(f);
            } else |_| {}
        } else {
            if (std.fmt.parseInt(i64, num_str, 10)) |i| {
                return Value.initInt(i);
            } else |_| {}
        }

        return Value.initNull();
    }

    pub fn parseArray(self: *JsonParser, allocator: std.mem.Allocator, vm: *VM, assoc: bool) !Value {
        self.pos += 1; // Skip '['
        self.skipWhitespace();

        const array_box = try allocator.create(types.gc.Box(*types.PHPArray));
        const php_array = try allocator.create(types.PHPArray);
        php_array.* = types.PHPArray.init(allocator);
        array_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };

        var first = true;
        if (self.pos < self.input.len and self.input[self.pos] != ']') {
            while (true) {
                if (!first) {
                    self.skipWhitespace();
                    if (self.input[self.pos] == ',') {
                        self.pos += 1;
                    }
                }
                first = false;

                self.skipWhitespace();
                const value = self.parseValue(allocator, vm, assoc) catch Value.initNull();
                php_array.push(allocator, value) catch {};

                self.skipWhitespace();
                if (self.pos < self.input.len and self.input[self.pos] == ']') {
                    break;
                }
                if (self.pos >= self.input.len or self.input[self.pos] != ',') {
                    break;
                }
                self.pos += 1;
            }
        }

        if (self.pos < self.input.len and self.input[self.pos] == ']') {
            self.pos += 1;
        }

        return Value.fromBox(array_box, Value.TYPE_ARRAY);
    }

    pub fn parseObject(self: *JsonParser, allocator: std.mem.Allocator, vm: *VM, assoc: bool) !Value {
        _ = assoc; // Always use array for now
        self.pos += 1; // Skip '{'
        self.skipWhitespace();

        const array_box = try allocator.create(types.gc.Box(*types.PHPArray));
        const php_array = try allocator.create(types.PHPArray);
        php_array.* = types.PHPArray.init(allocator);
        array_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };

        var first = true;
        if (self.pos < self.input.len and self.input[self.pos] != '}') {
            while (true) {
                if (!first) {
                    self.skipWhitespace();
                    if (self.input[self.pos] == ',') {
                        self.pos += 1;
                    }
                }
                first = false;

                self.skipWhitespace();
                if (self.input[self.pos] != '"') break;

                // Parse key
                self.pos += 1;
                var key_builder = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
                defer key_builder.deinit(allocator);

                while (self.pos < self.input.len) {
                    const c = self.input[self.pos];
                    if (c == '"') {
                        self.pos += 1; // Skip closing quote
                        break;
                    }
                    if (c == '\\' and self.pos + 1 < self.input.len) {
                        self.pos += 1;
                        const escaped = self.input[self.pos];
                        switch (escaped) {
                            '"' => try key_builder.append(allocator, '"'),
                            '\\' => try key_builder.append(allocator, '\\'),
                            '/' => try key_builder.append(allocator, '/'),
                            'n' => try key_builder.append(allocator, '\n'),
                            'r' => try key_builder.append(allocator, '\r'),
                            't' => try key_builder.append(allocator, '\t'),
                            else => try key_builder.append(allocator, escaped),
                        }
                    } else {
                        try key_builder.append(allocator, c);
                    }
                    self.pos += 1;
                }

                self.skipWhitespace();
                if (self.pos >= self.input.len or self.input[self.pos] != ':') {
                    // Try parsing even without colon if we have valid key-value
                    if (self.pos < self.input.len and self.input[self.pos] != ',') {
                        // Still try to parse value
                    }
                }
                self.pos += 1; // Skip ':'

                // Parse value
                self.skipWhitespace();
                const value = try self.parseValue(allocator, vm, false);

                // Store in array with string key
                const key_slice = try key_builder.toOwnedSlice(allocator);
                const key_str = try types.PHPString.init(allocator, key_slice);
                const key = types.ArrayKey{ .string = key_str };
                try php_array.set(allocator, key, value);

                self.skipWhitespace();
                if (self.pos < self.input.len and self.input[self.pos] == '}') {
                    break;
                }
                if (self.pos >= self.input.len or self.input[self.pos] != ',') {
                    break;
                }
                self.pos += 1;
            }
        }

        if (self.pos < self.input.len and self.input[self.pos] == '}') {
            self.pos += 1;
        }

        return Value.fromBox(array_box, Value.TYPE_ARRAY);
    }
};

pub fn jsonLastErrorFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    // Simplified - would track actual JSON errors
    return Value.initInt(0); // JSON_ERROR_NONE
}

pub fn jsonLastErrorMsgFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    return try Value.initString(vm.allocator, "No error");
}

// Static constants to avoid allocations
pub const JSON_NULL_STR = "null";
pub const JSON_TRUE_STR = "true";
pub const JSON_FALSE_STR = "false";
pub const JSON_OPEN_BRACE = "{";
pub const JSON_CLOSE_BRACE = "}";
pub const JSON_OPEN_BRACKET = "[";
pub const JSON_CLOSE_BRACKET = "]";
pub const JSON_COMMA = ",";
pub const JSON_COLON = ":";
pub const JSON_QUOTE = "\"";

// Helper function for JSON encoding (optimized with pre-allocation)
pub fn encodeValueAsJson(value: Value, allocator: std.mem.Allocator) ![]u8 {
    return switch (value.getTag()) {
        .null => try allocator.dupe(u8, JSON_NULL_STR),
        .boolean => try allocator.dupe(u8, if (value.asBool()) JSON_TRUE_STR else JSON_FALSE_STR),
        .integer => try std.fmt.allocPrint(allocator, "{d}", .{value.asInt()}),
        .float => try std.fmt.allocPrint(allocator, "{d}", .{value.asFloat()}),
        .string => try std.fmt.allocPrint(allocator, "\"{s}\"", .{value.getAsString().data.data}),
        .array => {
            const arr = value.getAsArray().data;
            const len = arr.getElements().count();

            // Check if it's an associative array (has string keys)
            var is_object = false;
            var iter = arr.getElements().iterator();
            while (iter.next()) |entry| {
                if (entry.key_ptr.* == .string) {
                    is_object = true;
                    break;
                }
            }

            // Pre-allocate with estimated capacity (avg 10 chars per element + overhead)
            const estimated_cap = if (len == 0) 2 else len * 12 + 4;
            var result = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
            try result.ensureTotalCapacity(allocator, estimated_cap);
            defer result.deinit(allocator);

            if (is_object) {
                // Output as JSON object
                result.appendAssumeCapacity('{');
                var first = true;
                var obj_iter = arr.getElements().iterator();
                while (obj_iter.next()) |entry| {
                    if (!first) result.appendAssumeCapacity(',');
                    first = false;

                    // Output key
                    switch (entry.key_ptr.*) {
                        .string => |s| {
                            result.appendAssumeCapacity('"');
                            result.appendSliceAssumeCapacity(s.data);
                            result.appendAssumeCapacity('"');
                        },
                        .integer => |i| {
                            const buf = try std.fmt.allocPrint(allocator, "{d}", .{i});
                            defer allocator.free(buf);
                            result.appendSliceAssumeCapacity(buf);
                        },
                    }
                    result.appendAssumeCapacity(':');

                    // Output value
                    const element_json = try encodeValueAsJson(entry.value_ptr.*, allocator);
                    defer allocator.free(element_json);
                    result.appendSliceAssumeCapacity(element_json);
                }
                result.appendAssumeCapacity('}');
            } else {
                // Output as JSON array
                result.appendAssumeCapacity('[');
                var first = true;
                var arr_iter = arr.getElements().iterator();
                while (arr_iter.next()) |entry| {
                    if (!first) result.appendAssumeCapacity(',');
                    first = false;

                    const element_json = try encodeValueAsJson(entry.value_ptr.*, allocator);
                    defer allocator.free(element_json);
                    result.appendSliceAssumeCapacity(element_json);
                }
                result.appendAssumeCapacity(']');
            }

            return try allocator.dupe(u8, result.items);
        },
        .object => try std.fmt.allocPrint(allocator, "{{\"class\":\"{s}\"}}", .{value.getAsObject().data.class.name.data}),
        .struct_instance => try std.fmt.allocPrint(allocator, "{{\"struct\":\"{s}\"}}", .{value.getAsStruct().data.struct_type.name.data}),
        else => try allocator.dupe(u8, JSON_NULL_STR),
    };
}

// ============================================================================
// 单元测试
// ============================================================================

test "stdlib_json: JsonParser skipWhitespace" {
    var parser = JsonParser{ .input = "  \t\n  hello", .pos = 0 };
    parser.skipWhitespace();
    try std.testing.expectEqual(@as(usize, 6), parser.pos);
}

test "stdlib_json: JsonParser parseNull" {
    var parser = JsonParser{ .input = "null", .pos = 0 };
    const result = try parser.parseNull();
    try std.testing.expect(result.getTag() == .null);
    try std.testing.expectEqual(@as(usize, 4), parser.pos);
}

test "stdlib_json: JsonParser parseTrue" {
    var parser = JsonParser{ .input = "true", .pos = 0 };
    const result = try parser.parseTrue();
    try std.testing.expect(result.getTag() == .boolean);
    try std.testing.expect(result.asBool());
    try std.testing.expectEqual(@as(usize, 4), parser.pos);
}

test "stdlib_json: JsonParser parseFalse" {
    var parser = JsonParser{ .input = "false", .pos = 0 };
    const result = try parser.parseFalse();
    try std.testing.expect(result.getTag() == .boolean);
    try std.testing.expect(!result.asBool());
    try std.testing.expectEqual(@as(usize, 5), parser.pos);
}

test "stdlib_json: JsonParser parseNumber integer" {
    var parser = JsonParser{ .input = "42", .pos = 0 };
    const result = try parser.parseNumber();
    try std.testing.expect(result.getTag() == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.asInt());
}

test "stdlib_json: JsonParser parseNumber negative integer" {
    var parser = JsonParser{ .input = "-7", .pos = 0 };
    const result = try parser.parseNumber();
    try std.testing.expect(result.getTag() == .integer);
    try std.testing.expectEqual(@as(i64, -7), result.asInt());
}

test "stdlib_json: JsonParser parseNumber float" {
    var parser = JsonParser{ .input = "3.14", .pos = 0 };
    const result = try parser.parseNumber();
    try std.testing.expect(result.getTag() == .float);
    try std.testing.expect(std.math.approxEqAbs(f64, result.asFloat(), 3.14, 0.001));
}

test "stdlib_json: JsonParser parseNumber scientific notation" {
    var parser = JsonParser{ .input = "1e5", .pos = 0 };
    const result = try parser.parseNumber();
    try std.testing.expect(result.getTag() == .float);
    try std.testing.expect(std.math.approxEqAbs(f64, result.asFloat(), 100000.0, 0.1));
}

test "stdlib_json: JsonParser parseString" {
    const allocator = std.testing.allocator;
    var parser = JsonParser{ .input = "\"hello\"", .pos = 0 };
    const result = try parser.parseString(allocator);
    // parseString returns a Value with string tag
    try std.testing.expect(result.getTag() == .string);
    try std.testing.expectEqualStrings("hello", result.getAsString().data.data);
}

test "stdlib_json: JsonParser parseString with escape sequences" {
    const allocator = std.testing.allocator;
    var parser = JsonParser{ .input = "\"hello\\nworld\"", .pos = 0 };
    const result = try parser.parseString(allocator);
    try std.testing.expect(result.getTag() == .string);
    try std.testing.expectEqualStrings("hello\nworld", result.getAsString().data.data);
}

test "stdlib_json: encodeValueAsJson null" {
    const allocator = std.testing.allocator;
    const result = try encodeValueAsJson(Value.initNull(), allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("null", result);
}

test "stdlib_json: encodeValueAsJson boolean" {
    const allocator = std.testing.allocator;
    const result_true = try encodeValueAsJson(Value.initBool(true), allocator);
    defer allocator.free(result_true);
    try std.testing.expectEqualStrings("true", result_true);

    const result_false = try encodeValueAsJson(Value.initBool(false), allocator);
    defer allocator.free(result_false);
    try std.testing.expectEqualStrings("false", result_false);
}

test "stdlib_json: encodeValueAsJson integer" {
    const allocator = std.testing.allocator;
    const result = try encodeValueAsJson(Value.initInt(42), allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "stdlib_json: encodeValueAsJson float" {
    const allocator = std.testing.allocator;
    const result = try encodeValueAsJson(Value.initFloat(3.14), allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("3.14", result);
}

test "stdlib_json: handler functions exist" {
    _ = &jsonEncodeFn;
    _ = &jsonDecodeFn;
    _ = &jsonLastErrorFn;
    _ = &jsonLastErrorMsgFn;
}

test "stdlib_json: JSON constants" {
    try std.testing.expectEqualStrings("null", JSON_NULL_STR);
    try std.testing.expectEqualStrings("true", JSON_TRUE_STR);
    try std.testing.expectEqualStrings("false", JSON_FALSE_STR);
    try std.testing.expectEqualStrings("{", JSON_OPEN_BRACE);
    try std.testing.expectEqualStrings("}", JSON_CLOSE_BRACE);
    try std.testing.expectEqualStrings("[", JSON_OPEN_BRACKET);
    try std.testing.expectEqualStrings("]", JSON_CLOSE_BRACKET);
    try std.testing.expectEqualStrings(",", JSON_COMMA);
    try std.testing.expectEqualStrings(":", JSON_COLON);
    try std.testing.expectEqualStrings("\"", JSON_QUOTE);
}
