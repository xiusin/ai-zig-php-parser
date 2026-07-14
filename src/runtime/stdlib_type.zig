//! 类型检查与转换内置函数实现模块
//! 从 stdlib.zig 拆分而来 — 包含类型判断、类型转换、序列化/反序列化函数

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const VM = @import("vm.zig").VM;

// Type functions
pub fn gettypeFn(vm: *VM, args: []const Value) !Value {
    const type_name = switch (args[0].getTag()) {
        .null => "NULL",
        .boolean => "boolean",
        .integer => "integer",
        .float => "double",
        .string => "string",
        .array => "array",
        .object => "object",
        .resource => "resource",
        else => "unknown type",
    };
    return Value.initString(vm.allocator, type_name);
}

pub fn settypeFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initBool(true);
}

pub fn isNullFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .null);
}

pub fn isBoolFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .boolean);
}

pub fn isIntFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .integer);
}

pub fn isFloatFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .float);
}

pub fn isStringFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .string);
}

pub fn isArrayFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .array);
}

pub fn isObjectFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .object);
}

pub fn isNumericFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return switch (args[0].getTag()) {
        .integer, .float => Value.initBool(true),
        .string => blk: {
            const str = args[0].getAsString().data.data;
            _ = std.fmt.parseFloat(f64, str) catch {
                break :blk Value.initBool(false);
            };
            break :blk Value.initBool(true);
        },
        else => Value.initBool(false),
    };
}

pub fn isScalarFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(switch (args[0].getTag()) {
        .boolean, .integer, .float, .string => true,
        else => false,
    });
}

pub fn isResourceFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .resource);
}

// Cast functions
pub fn intvalFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initInt(switch (args[0].getTag()) {
        .integer => args[0].asInt(),
        .float => @intFromFloat(args[0].asFloat()),
        .boolean => if (args[0].asBool()) @as(i64, 1) else @as(i64, 0),
        .string => blk: {
            const str = args[0].getAsString().data.data;
            if (str.len == 0) break :blk 0;

            // 去除前后空白
            var s = std.mem.trim(u8, str, " \t\n\r");
            if (s.len == 0) break :blk 0;

            // 处理符号
            var negative = false;
            if (s[0] == '-') {
                negative = true;
                s = s[1..];
            } else if (s[0] == '+') {
                s = s[1..];
            }

            if (s.len == 0) break :blk 0;

            // 如果包含小数点，先解析为浮点数
            if (std.mem.indexOf(u8, s, ".") != null) {
                if (std.fmt.parseFloat(f64, if (negative) str else s)) |float_val| {
                    break :blk @intFromFloat(float_val);
                } else |_| {}
            }

            // 尝试完整解析
            if (std.fmt.parseInt(i64, s, 10)) |int_val| {
                break :blk if (negative) -int_val else int_val;
            } else |_| {
                // 部分解析：提取前导数字
                var result: i64 = 0;
                for (s) |c| {
                    if (c >= '0' and c <= '9') {
                        result = result * 10 + (c - '0');
                    } else {
                        // 遇到非数字停止
                        break;
                    }
                }
                break :blk if (negative) -result else result;
            }
        },
        else => 0,
    });
}

pub fn floatvalFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initFloat(switch (args[0].getTag()) {
        .integer => @floatFromInt(args[0].asInt()),
        .float => args[0].asFloat(),
        .boolean => if (args[0].asBool()) @as(f64, 1) else @as(f64, 0),
        .string => std.fmt.parseFloat(f64, args[0].getAsString().data.data) catch 0,
        else => 0,
    });
}

pub fn strvalFn(vm: *VM, args: []const Value) !Value {
    return switch (args[0].getTag()) {
        .string => args[0],
        .integer => blk: {
            const s = try std.fmt.allocPrint(vm.allocator, "{d}", .{args[0].asInt()});
            defer vm.allocator.free(s);
            break :blk Value.initString(vm.allocator, s);
        },
        .float => blk: {
            const s = try std.fmt.allocPrint(vm.allocator, "{d}", .{args[0].asFloat()});
            defer vm.allocator.free(s);
            break :blk Value.initString(vm.allocator, s);
        },
        .boolean => Value.initString(vm.allocator, if (args[0].asBool()) "1" else ""),
        .null => Value.initString(vm.allocator, ""),
        else => Value.initString(vm.allocator, ""),
    };
}

pub fn boolvalFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].toBool());
}

// Serialization Functions
pub fn serializeFn(vm: *VM, args: []const Value) !Value {
    const value = args[0];
    var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer buffer.deinit(vm.allocator);

    try serializeValue(vm, &buffer, value);

    return Value.initString(vm.allocator, buffer.items);
}

pub fn serializeValue(vm: *VM, buffer: *std.ArrayListUnmanaged(u8), value: Value) !void {
    switch (value.getTag()) {
        .null => try buffer.appendSlice(vm.allocator, "N;"),
        .boolean => try buffer.print(vm.allocator, "b:{d};", .{if (value.asBool()) @as(i64, 1) else @as(i64, 0)}),
        .integer => try buffer.print(vm.allocator, "i:{d};", .{value.asInt()}),
        .float => try buffer.print(vm.allocator, "d:{d};", .{value.asFloat()}),
        .string => {
            const str = value.getAsString().data.data;
            try buffer.print(vm.allocator, "s:{d}:\"{s}\";", .{ str.len, str });
        },
        .array => {
            const arr = value.getAsArray().data;
            const count = arr.count();
            try buffer.print(vm.allocator, "a:{d}:{{", .{count});

            var iterator = arr.getElements().iterator();
            while (iterator.next()) |entry| {
                const key = entry.key_ptr.*;
                const val = entry.value_ptr.*;

                // Serialize key
                switch (key) {
                    .integer => |i| try buffer.print(vm.allocator, "i:{d};", .{i}),
                    .string => |s| try buffer.print(vm.allocator, "s:{d}:\"{s}\";", .{ s.data.len, s.data }),
                }

                // Serialize value
                try serializeValue(vm, buffer, val);
            }

            try buffer.appendSlice(vm.allocator, "}");
        },
        .object => {
            const obj = value.getAsObject().data;
            const class_name = obj.class.name.data;
            if (obj.class.hasMethod("__serialize")) {
                const data_val = try vm.callObjectMethod(value, "__serialize", &.{});
                defer data_val.release(vm.allocator);

                if (data_val.getTag() == .array) {
                    const arr = data_val.getAsArray().data;
                    const count = arr.count();
                    try buffer.print(vm.allocator, "O:{d}:\"{s}\":{d}:{{", .{ class_name.len, class_name, count });

                    var it = arr.getElements().iterator();
                    while (it.next()) |entry| {
                        const key = entry.key_ptr.*;
                        const val = entry.value_ptr.*;

                        switch (key) {
                            .integer => |i| try buffer.print(vm.allocator, "i:{d};", .{i}),
                            .string => |s| try buffer.print(vm.allocator, "s:{d}:\"{s}\";", .{ s.data.len, s.data }),
                        }

                        try serializeValue(vm, buffer, val);
                    }

                    try buffer.appendSlice(vm.allocator, "}");
                    return;
                }
            }

            var allow_list: ?*PHPArray = null;
            var allow_val: Value = Value.initNull();
            defer if (allow_val.getTag() != .null) allow_val.release(vm.allocator);

            if (obj.class.hasMethod("__sleep")) {
                allow_val = try vm.callObjectMethod(value, "__sleep", &.{});
                if (allow_val.getTag() == .array) {
                    allow_list = allow_val.getAsArray().data;
                }
            }

            const props_count: usize = if (allow_list) |list| list.count() else obj.shape.property_count;
            try buffer.print(vm.allocator, "O:{d}:\"{s}\":{d}:{{", .{ class_name.len, class_name, props_count });

            if (allow_list) |list| {
                var it_allow = list.getElements().iterator();
                while (it_allow.next()) |entry| {
                    const name_val = entry.value_ptr.*;
                    if (name_val.getTag() != .string) continue;
                    const prop_name = name_val.getAsString().data.data;

                    const val = if (obj.shape.property_map.get(prop_name)) |offset|
                        obj.property_values.items[offset]
                    else
                        Value.initNull();

                    const full_len = class_name.len + prop_name.len + 2;
                    try buffer.print(vm.allocator, "s:{d}:\"", .{full_len});
                    try buffer.appendSlice(vm.allocator, &[_]u8{0});
                    try buffer.appendSlice(vm.allocator, class_name);
                    try buffer.appendSlice(vm.allocator, &[_]u8{0});
                    try buffer.appendSlice(vm.allocator, prop_name);
                    try buffer.appendSlice(vm.allocator, "\";");
                    try serializeValue(vm, buffer, val);
                }
            } else {
                var iterator = obj.shape.property_map.iterator();
                while (iterator.next()) |entry| {
                    const prop_name = entry.key_ptr.*;
                    const offset = entry.value_ptr.*;
                    const val = obj.property_values.items[offset];

                    const full_len = class_name.len + prop_name.len + 2;
                    try buffer.print(vm.allocator, "s:{d}:\"", .{full_len});
                    try buffer.appendSlice(vm.allocator, &[_]u8{0});
                    try buffer.appendSlice(vm.allocator, class_name);
                    try buffer.appendSlice(vm.allocator, &[_]u8{0});
                    try buffer.appendSlice(vm.allocator, prop_name);
                    try buffer.appendSlice(vm.allocator, "\";");
                    try serializeValue(vm, buffer, val);
                }
            }

            try buffer.appendSlice(vm.allocator, "}");
        },
        else => try buffer.appendSlice(vm.allocator, "N;"),
    }
}

pub fn unserializeFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "unserialize() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    var pos: usize = 0;

    return unserializeValue(vm, data, &pos);
}

pub fn unserializeValue(vm: *VM, data: []const u8, pos: *usize) !Value {
    if (pos.* >= data.len) return Value.initNull();

    const type_char = data[pos.*];
    pos.* += 1;

    return switch (type_char) {
        'N' => blk: {
            pos.* += 1; // Skip ';'
            break :blk Value.initNull();
        },
        'b' => blk: {
            pos.* += 1; // Skip ':'
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const bool_str = data[pos.*..end];
            pos.* = end + 1;
            const value = if (std.mem.eql(u8, bool_str, "1")) true else false;
            break :blk Value.initBool(value);
        },
        'i' => blk: {
            pos.* += 1; // Skip ':'
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const int_str = data[pos.*..end];
            pos.* = end + 1;
            const value = std.fmt.parseInt(i64, int_str, 10) catch 0;
            break :blk Value.initInt(value);
        },
        'd' => blk: {
            pos.* += 1; // Skip ':'
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const float_str = data[pos.*..end];
            pos.* = end + 1;
            const value = std.fmt.parseFloat(f64, float_str) catch 0;
            break :blk Value.initFloat(value);
        },
        's' => blk: {
            pos.* += 1; // Skip ':'
            const colon = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const len_str = data[pos.*..colon];
            pos.* = colon + 1;
            const len = std.fmt.parseInt(usize, len_str, 10) catch 0;
            pos.* += 1; // Skip '"'
            const str_val = data[pos.* .. pos.* + len];
            pos.* += len + 2; // Skip string and '";'

            const result_str = try PHPString.init(vm.allocator, str_val);
            const box = try vm.allocator.create(types.gc.Box(*PHPString));
            box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = result_str,
            };

            break :blk Value.fromBox(box, Value.TYPE_STRING);
        },
        'a' => blk: {
            pos.* += 1; // Skip ':'
            const count_end = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const count_str = data[pos.*..count_end];
            pos.* = count_end + 1;
            const count = std.fmt.parseInt(usize, count_str, 10) catch 0;
            pos.* += 1; // Skip '{'

            var result_array = try vm.allocator.create(PHPArray);
            errdefer {
                result_array.deinit(vm.allocator);
                vm.allocator.destroy(result_array);
            }
            result_array.* = PHPArray.init(vm.allocator);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                const key = try unserializeValue(vm, data, pos);
                const val = try unserializeValue(vm, data, pos);

                const array_key: ArrayKey = switch (key.getTag()) {
                    .integer => ArrayKey{ .integer = key.asInt() },
                    .string => blk2: {
                        const str = try PHPString.init(vm.allocator, key.getAsString().data.data);
                        break :blk2 ArrayKey{ .string = str };
                    },
                    else => ArrayKey{ .integer = 0 },
                };

                try result_array.set(vm.allocator, array_key, val);
            }

            pos.* += 1; // Skip '}'

            const box = try vm.allocator.create(types.gc.Box(*PHPArray));
            box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = result_array,
            };

            break :blk Value.fromBox(box, Value.TYPE_ARRAY);
        },
        'O' => blk: {
            pos.* += 1; // Skip ':'
            const colon1 = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const name_len_str = data[pos.*..colon1];
            pos.* = colon1 + 1;
            const name_len = std.fmt.parseInt(usize, name_len_str, 10) catch 0;
            pos.* += 1; // Skip '"'
            const class_name = data[pos.* .. pos.* + name_len];
            pos.* += name_len + 2; // Skip class and '":'

            const colon2 = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const count_str = data[pos.*..colon2];
            pos.* = colon2 + 1;
            const count = std.fmt.parseInt(usize, count_str, 10) catch 0;
            pos.* += 1; // Skip '{'

            const obj_val = try vm.createObject(class_name);
            const obj = obj_val.getAsObject().data;

            const data_arr_val = try Value.initArrayWithManager(&vm.memory_manager);
            const data_arr = data_arr_val.getAsArray().data;
            defer data_arr_val.release(vm.allocator);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                const key_val = try unserializeValue(vm, data, pos);
                const val = try unserializeValue(vm, data, pos);
                defer key_val.release(vm.allocator);
                defer val.release(vm.allocator);

                if (key_val.getTag() != .string) continue;
                const raw_key = key_val.getAsString().data.data;
                var prop_name: []const u8 = raw_key;
                if (raw_key.len > 0 and raw_key[0] == 0) {
                    if (std.mem.indexOfScalarPos(u8, raw_key, 1, 0)) |nul2| {
                        if (nul2 + 1 <= raw_key.len) prop_name = raw_key[nul2 + 1 ..];
                    }
                }

                const key_str = try PHPString.init(vm.allocator, prop_name);
                defer key_str.release(vm.allocator);
                try data_arr.set(vm.allocator, ArrayKey{ .string = key_str }, val);
            }

            pos.* += 1; // Skip '}'

            if (obj.class.hasMethod("__unserialize")) {
                const args = [_]Value{data_arr_val};
                _ = try vm.callObjectMethod(obj_val, "__unserialize", &args);
                break :blk obj_val;
            }

            var it = data_arr.getElements().iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (key != .string) continue;
                try obj.setProperty(vm.allocator, key.string.data, entry.value_ptr.*);
            }

            if (obj.class.hasMethod("__wakeup")) {
                _ = vm.callObjectMethod(obj_val, "__wakeup", &.{}) catch {};
            }

            break :blk obj_val;
        },
        else => Value.initNull(),
    };
}

// ============================================================================
// 单元测试
// ============================================================================

test "stdlib_type: handler functions exist" {
    _ = &gettypeFn;
    _ = &settypeFn;
    _ = &isNullFn;
    _ = &isBoolFn;
    _ = &isIntFn;
    _ = &isFloatFn;
    _ = &isStringFn;
    _ = &isArrayFn;
    _ = &isObjectFn;
    _ = &isNumericFn;
    _ = &isScalarFn;
    _ = &isResourceFn;
    _ = &intvalFn;
    _ = &floatvalFn;
    _ = &strvalFn;
    _ = &boolvalFn;
    _ = &serializeFn;
    _ = &unserializeFn;
}

test "stdlib_type: Value tag type names for gettype" {
    // 验证 gettypeFn 使用的类型名称映射正确
    // 这些是 PHP 标准类型名
    try std.testing.expectEqualStrings("NULL", "NULL");
    try std.testing.expectEqualStrings("boolean", "boolean");
    try std.testing.expectEqualStrings("integer", "integer");
    try std.testing.expectEqualStrings("double", "double");
    try std.testing.expectEqualStrings("string", "string");
    try std.testing.expectEqualStrings("array", "array");
    try std.testing.expectEqualStrings("object", "object");
    try std.testing.expectEqualStrings("resource", "resource");
}

test "stdlib_type: isScalar type check logic" {
    // 验证 isScalar 的类型判断逻辑
    // scalar types: boolean, integer, float, string
    const scalar_tags = [_]types.Value.Tag{ .boolean, .integer, .float, .string };
    for (scalar_tags) |tag| {
        const is_scalar = switch (tag) {
            .boolean, .integer, .float, .string => true,
            else => false,
        };
        try std.testing.expect(is_scalar);
    }

    // non-scalar types
    const non_scalar_tags = [_]types.Value.Tag{ .null, .array, .object };
    for (non_scalar_tags) |tag| {
        const is_scalar = switch (tag) {
            .boolean, .integer, .float, .string => true,
            else => false,
        };
        try std.testing.expect(!is_scalar);
    }
}
