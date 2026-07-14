//! 字符串内置函数实现模块
//! 从 stdlib.zig 拆分而来 — 包含所有字符串操作、编码/解码、格式化函数

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const VM = @import("vm.zig").VM;
const builtin_random = @import("builtin_random.zig");
const time_compat = @import("time_compat.zig");

// 核心字符串函数模块
const core_string = @import("core/string_functions.zig");

// SIMD optimized string operations for performance
const simd_ops = @import("simd_ops.zig");
const SimdString = simd_ops.SimdString;

pub inline fn createStringReturn(allocator: std.mem.Allocator, str: *PHPString) !Value {
    const box = try allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = str,
    };
    return Value.fromBox(box, Value.TYPE_STRING);
}

// ============================================================================
// 辅助函数（供字符串函数内部使用）
// ============================================================================

/// 单次字符串替换辅助函数
pub fn stringReplaceOnce(allocator: std.mem.Allocator, subject_data: []const u8, search_data: []const u8, replace_data: []const u8, ignore_case: bool) ![]u8 {
    if (search_data.len == 0) return allocator.dupe(u8, subject_data);

    var found_count: usize = 0;
    var pos: usize = 0;
    while (pos < subject_data.len) {
        if (pos + search_data.len <= subject_data.len) {
            const matched = if (ignore_case)
                std.ascii.eqlIgnoreCase(subject_data[pos .. pos + search_data.len], search_data)
            else
                std.mem.eql(u8, subject_data[pos .. pos + search_data.len], search_data);
            if (matched) {
                found_count += 1;
                pos += search_data.len;
                continue;
            }
        }
        pos += 1;
    }

    if (found_count == 0) return allocator.dupe(u8, subject_data);

    const new_len = subject_data.len - (found_count * search_data.len) + (found_count * replace_data.len);
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    pos = 0;
    while (pos < subject_data.len) {
        if (pos + search_data.len <= subject_data.len) {
            const matched = if (ignore_case)
                std.ascii.eqlIgnoreCase(subject_data[pos .. pos + search_data.len], search_data)
            else
                std.mem.eql(u8, subject_data[pos .. pos + search_data.len], search_data);
            if (matched) {
                @memcpy(buffer[write_pos .. write_pos + replace_data.len], replace_data);
                write_pos += replace_data.len;
                pos += search_data.len;
                continue;
            }
        }
        buffer[write_pos] = subject_data[pos];
        write_pos += 1;
        pos += 1;
    }

    return buffer;
}

/// 十六进制字符转整数
pub fn hexCharToInt(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

pub fn strlenFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strlen() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    return Value.initInt(@intCast(str.getAsString().data.length));
}

pub fn substrFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const start = args[1];
    const length = if (args.len > 2) args[2] else Value.initNull();

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "substr() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (start.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "substr() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const start_int = start.asInt();
    const length_int = if (length.getTag() == .integer) length.asInt() else null;

    const result_str = try str.getAsString().data.substring(start_int, length_int, vm.allocator);
    return createStringReturn(vm.allocator, result_str);
}

pub fn valueToOwnedStringSlice(vm: *VM, val: Value) ![]u8 {
    if (val.getTag() == .string) return vm.allocator.dupe(u8, val.getAsString().data.data);
    const str = try val.toString(vm.allocator);
    defer str.release(vm.allocator);
    return vm.allocator.dupe(u8, str.data);
}

pub fn strReplaceCommon(vm: *VM, args: []const Value, ignore_case: bool) !Value {
    const search = args[0];
    const replace = args[1];
    const subject = args[2];

    if (subject.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, if (ignore_case) "str_ireplace() expects parameter 3 to be string" else "str_replace() expects parameter 3 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (search.getTag() == .array) {
        var current = try vm.allocator.dupe(u8, subject.getAsString().data.data);
        defer vm.allocator.free(current);

        const search_arr = search.getAsArray().data;
        const replace_is_array = replace.getTag() == .array;
        var i: usize = 0;
        while (i < search_arr.getElements().count()) : (i += 1) {
            const key = ArrayKey{ .integer = @intCast(i) };
            const search_val = search_arr.getElements().get(key) orelse continue;
            const search_slice = try valueToOwnedStringSlice(vm, search_val);
            defer vm.allocator.free(search_slice);

            const replace_slice = blk: {
                if (replace_is_array) {
                    const replace_arr = replace.getAsArray().data;
                    if (replace_arr.getElements().get(key)) |replace_val| {
                        break :blk try valueToOwnedStringSlice(vm, replace_val);
                    }
                    break :blk try vm.allocator.dupe(u8, "");
                }
                break :blk try valueToOwnedStringSlice(vm, replace);
            };
            defer vm.allocator.free(replace_slice);

            const next = try stringReplaceOnce(vm.allocator, current, search_slice, replace_slice, ignore_case);
            vm.allocator.free(current);
            current = next;
        }

        const result_str = try PHPString.init(vm.allocator, current);
        return createStringReturn(vm.allocator, result_str);
    }

    const search_slice = try valueToOwnedStringSlice(vm, search);
    defer vm.allocator.free(search_slice);
    const replace_slice = try valueToOwnedStringSlice(vm, replace);
    defer vm.allocator.free(replace_slice);
    const buffer = try stringReplaceOnce(vm.allocator, subject.getAsString().data.data, search_slice, replace_slice, ignore_case);
    defer vm.allocator.free(buffer);
    const result_str = try PHPString.init(vm.allocator, buffer);
    return createStringReturn(vm.allocator, result_str);
}

pub fn strReplaceFn(vm: *VM, args: []const Value) !Value {
    return strReplaceCommon(vm, args, false);
}

pub fn strIreplaceFn(vm: *VM, args: []const Value) !Value {
    return strReplaceCommon(vm, args, true);
}

pub fn strposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];
    const offset: usize = if (args.len > 2) @intCast(args[2].asInt()) else 0;

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strpos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    // Use SIMD-optimized search for better performance
    const search_slice = if (offset > 0 and offset < haystack_str.len) haystack_str[offset..] else haystack_str;
    if (SimdString.findSimd(search_slice, needle_str)) |pos| {
        return Value.initInt(@intCast(offset + pos));
    }
    return Value.initBool(false);
}

pub fn striposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];
    const offset: usize = if (args.len > 2) @intCast(args[2].asInt()) else 0;

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "stripos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    // Manual case-insensitive search (indexOfIgnoreCasePos was removed in Zig 0.17)
    if (needle_str.len == 0) {
        return Value.initInt(@intCast(offset));
    }
    if (needle_str.len > haystack_str.len or offset > haystack_str.len - needle_str.len) {
        return Value.initBool(false);
    }
    var search_idx: usize = offset;
    while (search_idx <= haystack_str.len - needle_str.len) : (search_idx += 1) {
        var match = true;
        for (needle_str, 0..) |nc, ni| {
            if (std.ascii.toLower(nc) != std.ascii.toLower(haystack_str[search_idx + ni])) {
                match = false;
                break;
            }
        }
        if (match) {
            return Value.initInt(@intCast(search_idx));
        }
    }
    return Value.initBool(false);
}

pub fn strrposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strrpos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    if (std.mem.lastIndexOf(u8, haystack_str, needle_str)) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

pub fn strriposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strripos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    const haystack_lower = try vm.allocator.alloc(u8, haystack_str.len);
    defer vm.allocator.free(haystack_lower);
    // Use SIMD-optimized toLower
    SimdString.toLowerSimd(haystack_lower, haystack_str);

    const needle_lower = try vm.allocator.alloc(u8, needle_str.len);
    defer vm.allocator.free(needle_lower);
    // Use SIMD-optimized toLower
    SimdString.toLowerSimd(needle_lower, needle_str);

    if (std.mem.lastIndexOf(u8, haystack_lower, needle_lower)) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

pub fn strtolowerFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtolower() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const lower_data = try vm.allocator.alloc(u8, original.length);

    // Use SIMD-optimized toLower for better performance on longer strings
    SimdString.toLowerSimd(lower_data, original.data);

    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = lower_data,
        .length = original.length,
        .encoding = original.encoding,
        .ref_count = 1,
    };

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn strtoupperFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtoupper() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const upper_data = try vm.allocator.alloc(u8, original.length);

    // Use SIMD-optimized toUpper for better performance on longer strings
    SimdString.toUpperSimd(upper_data, original.data);

    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = upper_data,
        .length = original.length,
        .encoding = original.encoding,
        .ref_count = 1,
    };

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn trimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "trim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const trim_chars = if (chars.getTag() == .string) chars.getAsString().data.data else " \t\n\r\x00\x0B";

    var start: usize = 0;
    var end: usize = original.length;

    // Trim from start
    while (start < original.length) {
        var found = false;
        for (trim_chars) |trim_char| {
            if (original.data[start] == trim_char) {
                found = true;
                break;
            }
        }
        if (!found) break;
        start += 1;
    }

    // Trim from end
    while (end > start) {
        var found = false;
        for (trim_chars) |trim_char| {
            if (original.data[end - 1] == trim_char) {
                found = true;
                break;
            }
        }
        if (!found) break;
        end -= 1;
    }

    const result_str = try PHPString.init(vm.allocator, original.data[start..end]);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn ltrimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ltrim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const trim_chars = if (chars.getTag() == .string) chars.getAsString().data.data else " \t\n\r\x00\x0B";

    var start: usize = 0;

    // Trim from start only
    while (start < original.length) {
        var found = false;
        for (trim_chars) |trim_char| {
            if (original.data[start] == trim_char) {
                found = true;
                break;
            }
        }
        if (!found) break;
        start += 1;
    }

    const result_str = try PHPString.init(vm.allocator, original.data[start..]);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn rtrimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "rtrim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const trim_chars = if (chars.getTag() == .string) chars.getAsString().data.data else " \t\n\r\x00\x0B";

    var end: usize = original.length;

    // Trim from end only
    while (end > 0) {
        var found = false;
        for (trim_chars) |trim_char| {
            if (original.data[end - 1] == trim_char) {
                found = true;
                break;
            }
        }
        if (!found) break;
        end -= 1;
    }

    const result_str = try PHPString.init(vm.allocator, original.data[0..end]);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn explodeFn(vm: *VM, args: []const Value) !Value {
    const delimiter = args[0];
    const string = args[1];
    const limit = if (args.len > 2) args[2] else Value.initNull();

    if (delimiter.getTag() != .string or string.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "explode() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    const delim = delimiter.getAsString().data;
    const str = string.getAsString().data;

    if (delim.length == 0) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "explode(): Empty delimiter", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var start: usize = 0;
    var count: i64 = 0;
    const max_splits = if (limit.getTag() == .integer) limit.asInt() else std.math.maxInt(i64);

    while (start < str.length and count < max_splits - 1) {
        const pos = std.mem.indexOf(u8, str.data[start..], delim.data);
        if (pos) |p| {
            const actual_pos = start + p;

            // Use Value.initString helper (optimized)
            const value = try Value.initString(vm.allocator, str.data[start..actual_pos]);
            try result_array.push(vm.allocator, value);
            vm.releaseValue(value);

            start = actual_pos + delim.length;
            count += 1;
        } else {
            break;
        }
    }

    // Add the remaining part
    if (start < str.length) {
        // Use Value.initString helper (optimized)
        const value = try Value.initString(vm.allocator, str.data[start..]);
        try result_array.push(vm.allocator, value);
        vm.releaseValue(value);
    }

    const array_box = try vm.allocator.create(types.gc.Box(*PHPArray));
    array_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(array_box, Value.TYPE_ARRAY);
}

pub fn implodeFn(vm: *VM, args: []const Value) !Value {
    const glue = args[0];
    const pieces = args[1];

    if (glue.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "implode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (pieces.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "implode() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Inline frequently accessed values (getAsString returns Box)
    const glue_box = glue.getAsString();
    const glue_data = glue_box.data.data;
    const glue_len = glue_data.len;
    const array_data = pieces.getAsArray().data;
    const count = array_data.getElements().count();

    if (count == 0) {
        const result_str = try PHPString.init(vm.allocator, "");
        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };
        return Value.fromBox(box, Value.TYPE_STRING);
    }

    // First pass: calculate total length
    var total_length: usize = 0;
    var iterator = array_data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        // Inline tag check
        if (value.getTag() == .string) {
            total_length += value.getAsString().data.data.len;
        } else {
            const value_str = try value.toString(vm.allocator);
            total_length += value_str.data.len;
            value_str.deinit(vm.allocator);
        }
    }

    if (count > 1) {
        total_length += (count - 1) * glue_len;
    }

    // Allocate exact size buffer
    const result_data = try vm.allocator.alloc(u8, total_length);

    // Second pass: copy strings directly to result buffer
    var pos: usize = 0;
    var first = true;
    iterator = array_data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        if (!first) {
            @memcpy(result_data[pos .. pos + glue_len], glue_data);
            pos += glue_len;
        }
        first = false;

        if (value.getTag() == .string) {
            const str_data = value.getAsString().data.data;
            const len = str_data.len;
            @memcpy(result_data[pos .. pos + len], str_data);
            pos += len;
        } else {
            const value_str = try value.toString(vm.allocator);
            const len = value_str.data.len;
            @memcpy(result_data[pos .. pos + len], value_str.data);
            pos += len;
            value_str.deinit(vm.allocator);
        }
    }

    const result_str = try PHPString.init(vm.allocator, result_data);
    vm.allocator.free(result_data);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn strRepeatFn(vm: *VM, args: []const Value) !Value {
    const input = args[0];
    const multiplier = args[1];

    if (input.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (multiplier.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const times = multiplier.asInt();
    if (times < 0) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat(): Second argument has to be greater than or equal to 0", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (times == 0) {
        return try Value.initString(vm.allocator, "");
    }

    const input_str = input.getAsString().data;
    const total_length = input_str.length * @as(usize, @intCast(times));
    const result_data = try vm.allocator.alloc(u8, total_length);

    for (0..@intCast(times)) |i| {
        const start = i * input_str.length;
        @memcpy(result_data[start .. start + input_str.length], input_str.data);
    }

    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = result_data,
        .length = total_length,
        .encoding = input_str.encoding,
        .ref_count = 1,
    };

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn sprintfFn(vm: *VM, args: []const Value) !Value {
    if (args.len == 0) return Value.initString(vm.allocator, "");
    const format = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    var result = try std.ArrayList(u8).initCapacity(vm.allocator, format.len);

    defer result.deinit(vm.allocator);

    var arg_idx: usize = 1;
    var i: usize = 0;
    while (i < format.len) : (i += 1) {
        if (format[i] == '%' and i + 1 < format.len) {
            const spec = format[i + 1];
            if (spec == '%') {
                try result.append(vm.allocator, '%');
                i += 1;
                continue;
            }

            if (arg_idx >= args.len) {
                try result.append(vm.allocator, '%');
                try result.append(vm.allocator, spec);
                i += 1;
                continue;
            }

            const arg = args[arg_idx];
            arg_idx += 1;

            switch (spec) {
                'd', 'i' => {
                    const val = if (arg.getTag() == .integer) arg.asInt() else 0;
                    try result.print(vm.allocator, "{d}", .{val});
                },
                's' => {
                    const val = if (arg.getTag() == .string) arg.getAsString().data.data else "";
                    try result.appendSlice(vm.allocator, val);
                },
                'f' => {
                    const val = if (arg.getTag() == .float) arg.asFloat() else 0.0;
                    try result.print(vm.allocator, "{d}", .{val});
                },
                else => {
                    try result.append(vm.allocator, '%');
                    try result.append(vm.allocator, spec);
                },
            }
            i += 1;
        } else {
            try result.append(vm.allocator, format[i]);
        }
    }

    return Value.initString(vm.allocator, result.items);
}

pub fn printfFn(vm: *VM, args: []const Value) !Value {
    const result = try sprintfFn(vm, args);
    if (result.getTag() == .string) {
        std.debug.print("{s}", .{result.getAsString().data.data});
    }
    return Value.initInt(@intCast(if (result.getTag() == .string) result.getAsString().data.length else 0));
}

pub fn strContainsFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const haystack = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const needle = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";
    return Value.initBool(std.mem.indexOf(u8, haystack, needle) != null);
}

pub fn strStartsWithFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const haystack = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const needle = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";
    return Value.initBool(std.mem.startsWith(u8, haystack, needle));
}

pub fn strEndsWithFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const haystack = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const needle = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";
    return Value.initBool(std.mem.endsWith(u8, haystack, needle));
}

pub fn ucfirstFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    if (str.len == 0) return Value.initString(vm.allocator, "");
    var result = try vm.allocator.alloc(u8, str.len);
    @memcpy(result, str);
    result[0] = std.ascii.toUpper(result[0]);
    defer vm.allocator.free(result);
    return Value.initString(vm.allocator, result);
}

pub fn lcfirstFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    if (str.len == 0) return Value.initString(vm.allocator, "");
    var result = try vm.allocator.alloc(u8, str.len);
    @memcpy(result, str);
    result[0] = std.ascii.toLower(result[0]);
    defer vm.allocator.free(result);
    return Value.initString(vm.allocator, result);
}

pub fn ucwordsFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    if (str.len == 0) return Value.initString(vm.allocator, "");
    var result = try vm.allocator.alloc(u8, str.len);
    defer vm.allocator.free(result);
    var capitalize_next = true;
    for (str, 0..) |c, i| {
        if (c == ' ' or c == '\t' or c == '\n') {
            result[i] = c;
            capitalize_next = true;
        } else if (capitalize_next) {
            result[i] = std.ascii.toUpper(c);
            capitalize_next = false;
        } else {
            result[i] = c;
        }
    }
    return Value.initString(vm.allocator, result);
}

pub fn strPadFn(vm: *VM, args: []const Value) !Value {
    const input = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const length: usize = if (args[1].getTag() == .integer and args[1].asInt() > 0) @intCast(args[1].asInt()) else input.len;
    const pad_str = if (args.len > 2 and args[2].getTag() == .string) args[2].getAsString().data.data else " ";
    const pad_type: i64 = if (args.len > 3 and args[3].getTag() == .integer) args[3].asInt() else 1;

    if (input.len >= length or pad_str.len == 0) return Value.initString(vm.allocator, input);

    const pad_len = length - input.len;
    var result = try vm.allocator.alloc(u8, length);
    defer vm.allocator.free(result);

    if (pad_type == 0) { // STR_PAD_LEFT
        var i: usize = 0;
        while (i < pad_len) : (i += 1) result[i] = pad_str[i % pad_str.len];
        @memcpy(result[pad_len..], input);
    } else if (pad_type == 2) { // STR_PAD_BOTH
        const left_pad = pad_len / 2;
        const right_pad = pad_len - left_pad;
        var i: usize = 0;
        while (i < left_pad) : (i += 1) result[i] = pad_str[i % pad_str.len];
        @memcpy(result[left_pad .. left_pad + input.len], input);
        i = 0;
        while (i < right_pad) : (i += 1) result[left_pad + input.len + i] = pad_str[i % pad_str.len];
    } else { // STR_PAD_RIGHT (default)
        @memcpy(result[0..input.len], input);
        var i: usize = 0;
        while (i < pad_len) : (i += 1) result[input.len + i] = pad_str[i % pad_str.len];
    }
    return Value.initString(vm.allocator, result);
}

pub fn strrevFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    if (str.len == 0) return Value.initString(vm.allocator, "");
    const result = try core_string.strrev_raw(vm.allocator, str);
    defer vm.allocator.free(result);
    return Value.initString(vm.allocator, result);
}

pub fn strSplitFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const length: usize = if (args.len > 1 and args[1].getTag() == .integer and args[1].asInt() > 0) @intCast(args[1].asInt()) else 1;

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var i: usize = 0;
    while (i < str.len) {
        const end = @min(i + length, str.len);
        const chunk = try Value.initString(vm.allocator, str[i..end]);
        try result_array.push(vm.allocator, chunk);
        chunk.release(vm.allocator); // push retains, so release our ref
        i = end;
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn chunkSplitFn(vm: *VM, args: []const Value) !Value {
    const body = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const chunklen: usize = if (args.len > 1 and args[1].getTag() == .integer) @intCast(@max(1, args[1].asInt())) else 76;
    const end = if (args.len > 2 and args[2].getTag() == .string) args[2].getAsString().data.data else "\r\n";

    const num_chunks = (body.len + chunklen - 1) / chunklen;
    const result_len = body.len + num_chunks * end.len;
    var result = try vm.allocator.alloc(u8, result_len);
    defer vm.allocator.free(result);

    var src_i: usize = 0;
    var dst_i: usize = 0;
    while (src_i < body.len) {
        const chunk_end = @min(src_i + chunklen, body.len);
        @memcpy(result[dst_i .. dst_i + (chunk_end - src_i)], body[src_i..chunk_end]);
        dst_i += chunk_end - src_i;
        @memcpy(result[dst_i .. dst_i + end.len], end);
        dst_i += end.len;
        src_i = chunk_end;
    }
    return Value.initString(vm.allocator, result[0..dst_i]);
}

pub fn wordwrapFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    return Value.initString(vm.allocator, str);
}

pub fn nl2brFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    var count: usize = 0;
    for (str) |c| if (c == '\n') {
        count += 1;
    };

    var result = try vm.allocator.alloc(u8, str.len + count * 5);
    defer vm.allocator.free(result);
    var j: usize = 0;
    for (str) |c| {
        if (c == '\n') {
            @memcpy(result[j .. j + 5], "<br>\n");
            j += 5;
        } else {
            result[j] = c;
            j += 1;
        }
    }
    return Value.initString(vm.allocator, result[0..j]);
}

pub fn stripTagsFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    var result = try vm.allocator.alloc(u8, str.len);
    defer vm.allocator.free(result);
    var j: usize = 0;
    var in_tag = false;
    for (str) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            result[j] = c;
            j += 1;
        }
    }
    return Value.initString(vm.allocator, result[0..j]);
}

pub fn htmlspecialcharsFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    var result = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer result.deinit(vm.allocator);
    for (str) |c| {
        switch (c) {
            '&' => try result.appendSlice(vm.allocator, "&amp;"),
            '"' => try result.appendSlice(vm.allocator, "&quot;"),
            '\'' => try result.appendSlice(vm.allocator, "&#039;"),
            '<' => try result.appendSlice(vm.allocator, "&lt;"),
            '>' => try result.appendSlice(vm.allocator, "&gt;"),
            else => try result.append(vm.allocator, c),
        }
    }
    return Value.initString(vm.allocator, result.items);
}

pub fn htmlentitiesFn(vm: *VM, args: []const Value) !Value {
    return htmlspecialcharsFn(vm, args);
}

pub fn numberFormatFn(vm: *VM, args: []const Value) !Value {
    const num: f64 = switch (args[0].getTag()) {
        .integer => @floatFromInt(args[0].asInt()),
        .float => args[0].asFloat(),
        else => 0,
    };
    const decimals: u32 = if (args.len > 1 and args[1].getTag() == .integer) @intCast(@max(0, args[1].asInt())) else 0;
    const dec_point = if (args.len > 2 and args[2].getTag() == .string) args[2].getAsString().data.data else ".";
    const thousands_sep = if (args.len > 3 and args[3].getTag() == .string) args[3].getAsString().data.data else ",";

    // Format with decimals
    const formatted = try std.fmt.allocPrint(vm.allocator, "{d:.2}", .{num});
    defer vm.allocator.free(formatted);

    // Split into integer and decimal parts
    var parts = std.mem.splitScalar(u8, formatted, '.');
    const int_part = parts.next() orelse formatted;
    const dec_part = parts.next();

    // Add thousands separator
    var result = try std.ArrayList(u8).initCapacity(vm.allocator, formatted.len + 10);
    defer result.deinit(vm.allocator);

    const int_len = int_part.len;
    var i: usize = 0;
    while (i < int_len) : (i += 1) {
        if (i > 0 and (int_len - i) % 3 == 0) {
            try result.appendSlice(vm.allocator, thousands_sep);
        }
        try result.append(vm.allocator, int_part[i]);
    }

    if (decimals > 0) {
        try result.appendSlice(vm.allocator, dec_point);
        if (dec_part) |dp| {
            const len = @min(dp.len, decimals);
            try result.appendSlice(vm.allocator, dp[0..len]);
            for (len..decimals) |_| {
                try result.append(vm.allocator, '0');
            }
        } else {
            for (0..decimals) |_| {
                try result.append(vm.allocator, '0');
            }
        }
    }

    return Value.initString(vm.allocator, result.items);
}

pub fn bin2hexFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "bin2hex() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    const hex_len = data.len * 2;
    const hex_str = try vm.allocator.alloc(u8, hex_len);

    const hex_chars = "0123456789abcdef";
    for (data, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const result_str = try PHPString.init(vm.allocator, hex_str);
    defer vm.allocator.free(hex_str);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn hex2binFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "hex2bin() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const hex_data = str.getAsString().data.data;
    if (hex_data.len % 2 != 0) {
        return Value.initBool(false);
    }

    const bin_len = hex_data.len / 2;
    const bin_str = try vm.allocator.alloc(u8, bin_len);

    for (0..bin_len) |i| {
        const high = hexCharToInt(hex_data[i * 2]) orelse {
            vm.allocator.free(bin_str);
            return Value.initBool(false);
        };
        const low = hexCharToInt(hex_data[i * 2 + 1]) orelse {
            vm.allocator.free(bin_str);
            return Value.initBool(false);
        };
        bin_str[i] = (high << 4) | low;
    }

    const result_str = try PHPString.init(vm.allocator, bin_str);
    defer vm.allocator.free(bin_str);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn base64EncodeFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "base64_encode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    const encoded = std.base64.standard.Encoder.calcSize(data.len);
    const result = try vm.allocator.alloc(u8, encoded);
    _ = std.base64.standard.Encoder.encode(result, data);

    const result_str = try PHPString.init(vm.allocator, result);
    defer vm.allocator.free(result);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn base64DecodeFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "base64_decode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(data) catch return Value.initBool(false);
    const result = try vm.allocator.alloc(u8, decoded_size);
    _ = std.base64.standard.Decoder.decode(result, data) catch {
        vm.allocator.free(result);
        return Value.initBool(false);
    };

    const result_str = try PHPString.init(vm.allocator, result);
    defer vm.allocator.free(result);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn md5Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "md5() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;
    var hasher = std.crypto.hash.Md5.init(.{});
    hasher.update(input);
    var hash: [16]u8 = undefined;
    hasher.final(&hash);

    if (raw_output) {
        const result_str = try PHPString.init(vm.allocator, &hash);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    } else {
        var hex_buffer: [32]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        const result_str = try PHPString.init(vm.allocator, &hex_buffer);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

pub fn sha1Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sha1() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(input);
    var hash: [20]u8 = undefined;
    hasher.final(&hash);

    if (raw_output) {
        const result_str = try PHPString.init(vm.allocator, &hash);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    } else {
        var hex_buffer: [40]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        const result_str = try PHPString.init(vm.allocator, &hex_buffer);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

pub fn uniqidFn(vm: *VM, args: []const Value) !Value {
    const prefix = if (args.len > 0 and args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const more_entropy = if (args.len > 1) args[1].toBool() else false;

    // Get current time in microseconds
    const timestamp = time_compat.nanoTimestamp();
    const now = @divTrunc(timestamp, 1000); // Convert to microseconds
    const seconds = @as(u64, @intCast(@divTrunc(now, 1_000_000)));
    const microseconds = @as(u64, @intCast(@rem(now, 1_000_000)));

    // Build result string
    var result_str: *PHPString = undefined;
    if (more_entropy) {
        var result_buf: [64]u8 = undefined;
        // Format: prefix + seconds (13 hex) + microseconds (6 hex) + random (4 hex)
        var rand_bytes: [2]u8 = undefined;
        {
            var prng = std.Random.DefaultPrng.init(@intCast(time_compat.timestamp()));
            prng.random().bytes(&rand_bytes);
        }
        const rand_val = @as(u16, rand_bytes[0]) * 256 + rand_bytes[1];
        const formatted = try std.fmt.bufPrint(&result_buf, "{s}{x:0>13}{x:0>6}{x:0>4}", .{ prefix, seconds, microseconds, rand_val });
        result_str = try PHPString.init(vm.allocator, formatted);
    } else {
        var result_buf: [64]u8 = undefined;
        // Format: prefix + seconds (13 hex)
        const formatted = try std.fmt.bufPrint(&result_buf, "{s}{x:0>13}", .{ prefix, seconds });
        result_str = try PHPString.init(vm.allocator, formatted);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn ordFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ord() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    if (data.len == 0) {
        return Value.initInt(0);
    }
    return Value.initInt(@intCast(data[0]));
}

pub fn chrFn(vm: *VM, args: []const Value) !Value {
    const code = args[0];
    if (code.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "chr() expects parameter 1 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const byte_val = code.asInt();
    const char_buf = try vm.allocator.alloc(u8, 1);
    char_buf[0] = @truncate(@as(u64, @bitCast(byte_val)));

    const result_str = try PHPString.init(vm.allocator, char_buf);
    defer vm.allocator.free(char_buf);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

pub fn echoFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    for (args) |arg| {
        arg.print();
    }
    return Value.initNull();
}

pub fn printFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    for (args) |arg| {
        arg.print();
    }
    return Value.initInt(1);
}

/// join() — implode 的别名
pub fn joinFn(vm: *VM, args: []const Value) !Value {
    return implodeFn(vm, args);
}

/// strcmp() — 二进制安全字符串比较，返回 -1/0/1
pub fn strcmpFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const str1 = args[0];
    const str2 = args[1];

    const s1 = if (str1.getTag() == .string) str1.getAsString().data.data else "";
    const s2 = if (str2.getTag() == .string) str2.getAsString().data.data else "";

    const min_len = @min(s1.len, s2.len);
    for (s1[0..min_len], s2[0..min_len]) |c1, c2| {
        if (c1 < c2) return Value.initInt(-1);
        if (c1 > c2) return Value.initInt(1);
    }
    if (s1.len < s2.len) return Value.initInt(-1);
    if (s1.len > s2.len) return Value.initInt(1);
    return Value.initInt(0);
}

/// strcasecmp() — 不区分大小写的 strcmp
pub fn strcasecmpFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const str1 = args[0];
    const str2 = args[1];

    const s1 = if (str1.getTag() == .string) str1.getAsString().data.data else "";
    const s2 = if (str2.getTag() == .string) str2.getAsString().data.data else "";

    const min_len = @min(s1.len, s2.len);
    for (s1[0..min_len], s2[0..min_len]) |c1, c2| {
        const lc1 = std.ascii.toLower(c1);
        const lc2 = std.ascii.toLower(c2);
        if (lc1 < lc2) return Value.initInt(-1);
        if (lc1 > lc2) return Value.initInt(1);
    }
    if (s1.len < s2.len) return Value.initInt(-1);
    if (s1.len > s2.len) return Value.initInt(1);
    return Value.initInt(0);
}

/// strncmp() — 比较前 n 个字符
pub fn strncmpFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const str1 = args[0];
    const str2 = args[1];
    const n: usize = if (args[2].getTag() == .integer) @intCast(@max(0, args[2].asInt())) else 0;

    const s1 = if (str1.getTag() == .string) str1.getAsString().data.data else "";
    const s2 = if (str2.getTag() == .string) str2.getAsString().data.data else "";

    const cmp_len = @min(n, s1.len, s2.len);
    for (s1[0..cmp_len], s2[0..cmp_len]) |c1, c2| {
        if (c1 < c2) return Value.initInt(-1);
        if (c1 > c2) return Value.initInt(1);
    }
    if (cmp_len < n) {
        if (s1.len < s2.len) return Value.initInt(-1);
        if (s1.len > s2.len) return Value.initInt(1);
    }
    return Value.initInt(0);
}

/// strncasecmp() — 不区分大小写的 strncmp
pub fn strncasecmpFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const str1 = args[0];
    const str2 = args[1];
    const n: usize = if (args[2].getTag() == .integer) @intCast(@max(0, args[2].asInt())) else 0;

    const s1 = if (str1.getTag() == .string) str1.getAsString().data.data else "";
    const s2 = if (str2.getTag() == .string) str2.getAsString().data.data else "";

    const cmp_len = @min(n, s1.len, s2.len);
    for (s1[0..cmp_len], s2[0..cmp_len]) |c1, c2| {
        const lc1 = std.ascii.toLower(c1);
        const lc2 = std.ascii.toLower(c2);
        if (lc1 < lc2) return Value.initInt(-1);
        if (lc1 > lc2) return Value.initInt(1);
    }
    if (cmp_len < n) {
        if (s1.len < s2.len) return Value.initInt(-1);
        if (s1.len > s2.len) return Value.initInt(1);
    }
    return Value.initInt(0);
}

/// substr_count() — 计算子串出现次数
pub fn substrCountFn(vm: *VM, args: []const Value) !Value {
    const haystack = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const needle = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";

    if (needle.len == 0) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "substr_count(): Empty needle", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const offset: usize = if (args.len > 2 and args[2].getTag() == .integer) @intCast(@max(0, args[2].asInt())) else 0;
    const length: ?usize = if (args.len > 3 and args[3].getTag() == .integer) @intCast(@max(0, args[3].asInt())) else null;

    const search_start = @min(offset, haystack.len);
    const search_end = if (length) |l| @min(search_start + l, haystack.len) else haystack.len;
    const search_str = haystack[search_start..search_end];

    var count: i64 = 0;
    var pos: usize = 0;
    while (pos + needle.len <= search_str.len) {
        if (std.mem.eql(u8, search_str[pos .. pos + needle.len], needle)) {
            count += 1;
            pos += needle.len;
        } else {
            pos += 1;
        }
    }

    return Value.initInt(count);
}

/// substr_replace() — 替换子串
pub fn substrReplaceFn(vm: *VM, args: []const Value) !Value {
    const string = args[0];
    const replacement = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";
    const start_val = if (args[2].getTag() == .integer) args[2].asInt() else 0;
    const length_val: ?i64 = if (args.len > 3 and args[3].getTag() == .integer) args[3].asInt() else null;

    if (string.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "substr_replace() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const str = string.getAsString().data.data;
    const str_len: i64 = @intCast(str.len);

    // Normalize start: negative values count from end
    const start: usize = if (start_val < 0)
        @intCast(@max(0, str_len + start_val))
    else
        @intCast(@min(start_val, str_len));

    // Determine length of portion to replace
    const repl_len: usize = if (length_val) |lv| blk: {
        if (lv < 0) {
            const from_end: i64 = @max(0, str_len + lv);
            if (from_end < @as(i64, @intCast(start))) break :blk 0;
            break :blk @intCast(from_end - @as(i64, @intCast(start)));
        } else {
            break :blk @min(@as(usize, @intCast(lv)), @as(usize, @intCast(str_len)) - start);
        }
    } else @intCast(str_len - @as(i64, @intCast(start)));

    // Build result: prefix + replacement + suffix
    const suffix_start = @min(start + repl_len, str.len);
    const result_len = start + replacement.len + (str.len - suffix_start);
    const result = try vm.allocator.alloc(u8, result_len);
    defer vm.allocator.free(result);

    var pos: usize = 0;
    @memcpy(result[pos .. pos + start], str[0..start]);
    pos += start;
    @memcpy(result[pos .. pos + replacement.len], replacement);
    pos += replacement.len;
    @memcpy(result[pos .. pos + (str.len - suffix_start)], str[suffix_start..]);

    return Value.initString(vm.allocator, result);
}

/// addslashes() — 转义单引号、双引号、反斜杠、NUL
pub fn addslashesFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    // First pass: count characters that need escaping
    var escape_count: usize = 0;
    for (str) |c| {
        switch (c) {
            '\'', '"', '\\', 0 => escape_count += 1,
            else => {},
        }
    }

    if (escape_count == 0) return Value.initString(vm.allocator, str);

    // Second pass: build escaped string
    const result = try vm.allocator.alloc(u8, str.len + escape_count);
    defer vm.allocator.free(result);
    var pos: usize = 0;
    for (str) |c| {
        switch (c) {
            '\'', '"', '\\', 0 => {
                result[pos] = '\\';
                pos += 1;
                result[pos] = if (c == 0) '0' else c;
                pos += 1;
            },
            else => {
                result[pos] = c;
                pos += 1;
            },
        }
    }

    return Value.initString(vm.allocator, result[0..pos]);
}

/// stripslashes() — 反转义
pub fn stripslashesFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    const result = try vm.allocator.alloc(u8, str.len);
    defer vm.allocator.free(result);
    var pos: usize = 0;
    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '\\' and i + 1 < str.len) {
            const next = str[i + 1];
            switch (next) {
                '\'', '"', '\\' => {
                    result[pos] = next;
                    pos += 1;
                    i += 2;
                },
                '0' => {
                    result[pos] = 0;
                    pos += 1;
                    i += 2;
                },
                'n' => {
                    result[pos] = '\n';
                    pos += 1;
                    i += 2;
                },
                'r' => {
                    result[pos] = '\r';
                    pos += 1;
                    i += 2;
                },
                't' => {
                    result[pos] = '\t';
                    pos += 1;
                    i += 2;
                },
                else => {
                    result[pos] = str[i];
                    pos += 1;
                    i += 1;
                },
            }
        } else {
            result[pos] = str[i];
            pos += 1;
            i += 1;
        }
    }

    return Value.initString(vm.allocator, result[0..pos]);
}

/// str_shuffle() — 随机打乱字符串
pub fn strShuffleFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    if (str.len <= 1) return Value.initString(vm.allocator, str);

    const result = try vm.allocator.alloc(u8, str.len);
    defer vm.allocator.free(result);
    @memcpy(result, str);

    // Fisher-Yates shuffle
    var prng = std.Random.DefaultPrng.init(@intCast(time_compat.nanoTimestamp()));
    const random = prng.random();
    var i: usize = str.len - 1;
    while (i > 0) : (i -= 1) {
        const j = random.uintLessThan(usize, i + 1);
        const tmp = result[i];
        result[i] = result[j];
        result[j] = tmp;
    }

    return Value.initString(vm.allocator, result);
}

/// html_entity_decode() — HTML 实体解码
pub fn htmlEntityDecodeFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    var result = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer result.deinit(vm.allocator);

    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '&') {
            // Try to find semicolon
            var end_idx: usize = i + 1;
            while (end_idx < str.len and end_idx < i + 12 and str[end_idx] != ';') : (end_idx += 1) {}

            if (end_idx < str.len and str[end_idx] == ';') {
                const entity = str[i + 1 .. end_idx];
                const decoded = decodeHtmlEntity(entity);
                if (decoded) |ch| {
                    if (ch <= 0x7F) {
                        try result.append(vm.allocator, @intCast(ch));
                    } else {
                        // Multi-byte UTF-8 encoding
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(@intCast(ch), &buf) catch 0;
                        try result.appendSlice(vm.allocator, buf[0..len]);
                    }
                    i = end_idx + 1;
                    continue;
                }
            }
        }
        try result.append(vm.allocator, str[i]);
        i += 1;
    }

    return Value.initString(vm.allocator, result.items);
}

/// HTML 实体解码辅助函数
fn decodeHtmlEntity(entity: []const u8) ?u21 {
    if (entity.len == 0) return null;

    // Numeric entities: #123 or #x1A
    if (entity[0] == '#') {
        if (entity.len < 2) return null;
        if (entity[1] == 'x' or entity[1] == 'X') {
            // Hexadecimal
            if (entity.len < 3) return null;
            const code = std.fmt.parseInt(u21, entity[2..], 16) catch return null;
            return code;
        } else {
            // Decimal
            const code = std.fmt.parseInt(u21, entity[1..], 10) catch return null;
            return code;
        }
    }

    // Named entities - using StaticStringMap for comptime lookup
    const named = std.StaticStringMap(u21).initComptime(.{
        .{ "amp", '&' },
        .{ "lt", '<' },
        .{ "gt", '>' },
        .{ "quot", '"' },
        .{ "apos", '\'' },
        .{ "nbsp", 0xA0 },
        .{ "copy", 0xA9 },
        .{ "reg", 0xAE },
        .{ "trade", 0x2122 },
        .{ "euro", 0x20AC },
        .{ "pound", 0xA3 },
        .{ "yen", 0xA5 },
        .{ "cent", 0xA2 },
        .{ "sect", 0xA7 },
        .{ "laquo", 0xAB },
        .{ "raquo", 0xBB },
        .{ "mdash", 0x2014 },
        .{ "ndash", 0x2013 },
        .{ "hellip", 0x2026 },
        .{ "bull", 0x2022 },
        .{ "middot", 0xB7 },
        .{ "lsquo", 0x2018 },
        .{ "rsquo", 0x2019 },
        .{ "ldquo", 0x201C },
        .{ "rdquo", 0x201D },
    });

    return named.get(entity);
}

/// parse_str() — 解析查询字符串到变量
pub fn parseStrFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    // If second argument is provided, parse into that array
    if (args.len > 1 and args[1].getTag() == .array) {
        const arr = args[1].getAsArray().data;
        var pairs = std.mem.splitScalar(u8, str, '&');
        while (pairs.next()) |pair| {
            if (pair.len == 0) continue;
            const eq_pos = std.mem.indexOfScalar(u8, pair, '=');
            const key_str = if (eq_pos) |pos| pair[0..pos] else pair;
            const val_str = if (eq_pos) |pos| pair[pos + 1 ..] else "";

            const decoded_key = try urldecodeRaw(vm.allocator, key_str);
            defer vm.allocator.free(decoded_key);
            const decoded_val = try urldecodeRaw(vm.allocator, val_str);
            defer vm.allocator.free(decoded_val);

            const key_val = try Value.initString(vm.allocator, decoded_key);
            const val_val = try Value.initString(vm.allocator, decoded_val);
            try arr.set(vm.allocator, .{ .string = key_val.getAsString().data }, val_val);
            vm.releaseValue(key_val);
            vm.releaseValue(val_val);
        }
        return Value.initBool(true);
    }

    // Without second argument, set as global variables (not supported in AOT context)
    return Value.initBool(true);
}

/// urlencode() — URL 编码
pub fn urlencodeFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    // application/x-www-form-urlencoded encoding
    // Encodes everything except: A-Z a-z 0-9 - _ .
    // Space becomes +
    var result = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer result.deinit(vm.allocator);

    for (str) |c| {
        switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.' => {
                try result.append(vm.allocator, c);
            },
            ' ' => {
                try result.append(vm.allocator, '+');
            },
            else => {
                try result.print(vm.allocator, "%{X:0>2}", .{c});
            },
        }
    }

    return Value.initString(vm.allocator, result.items);
}

/// urldecode() — URL 解码
pub fn urldecodeFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    const result = try urldecodeRaw(vm.allocator, str);
    defer vm.allocator.free(result);

    return Value.initString(vm.allocator, result);
}

/// URL 解码辅助函数
fn urldecodeRaw(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, str.len);
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '%' and i + 2 < str.len) {
            const high = hexCharToInt(str[i + 1]);
            const low = hexCharToInt(str[i + 2]);
            if (high != null and low != null) {
                try result.append(allocator, (high.? << 4) | low.?);
                i += 3;
                continue;
            }
        } else if (str[i] == '+') {
            try result.append(allocator, ' ');
            i += 1;
            continue;
        }
        try result.append(allocator, str[i]);
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

/// rawurlencode() — RFC 3986 URL 编码
pub fn rawurlencodeFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    // RFC 3986 encoding: encodes everything except A-Z a-z 0-9 - _ . ~
    var result = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer result.deinit(vm.allocator);

    for (str) |c| {
        switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => {
                try result.append(vm.allocator, c);
            },
            else => {
                try result.print(vm.allocator, "%{X:0>2}", .{c});
            },
        }
    }

    return Value.initString(vm.allocator, result.items);
}

/// rawurldecode() — RFC 3986 URL 解码
pub fn rawurldecodeFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    const result = try rawurldecodeRaw(vm.allocator, str);
    defer vm.allocator.free(result);

    return Value.initString(vm.allocator, result);
}

/// RFC 3986 URL 解码辅助函数
fn rawurldecodeRaw(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, str.len);
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '%' and i + 2 < str.len) {
            const high = hexCharToInt(str[i + 1]);
            const low = hexCharToInt(str[i + 2]);
            if (high != null and low != null) {
                try result.append(allocator, (high.? << 4) | low.?);
                i += 3;
                continue;
            }
        }
        try result.append(allocator, str[i]);
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

/// str_word_count() — 统计单词数
pub fn strWordCountFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const format: i64 = if (args.len > 1 and args[1].getTag() == .integer) args[1].asInt() else 0;

    var count: i64 = 0;
    var in_word = false;
    var word_start: usize = 0;

    // Collect word positions for format 1 and 2
    var word_list = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
    defer word_list.deinit(vm.allocator);

    for (str, 0..) |c, idx| {
        const is_word_char = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '\'' or c == '-';
        if (is_word_char and !in_word) {
            in_word = true;
            word_start = idx;
        } else if (!is_word_char and in_word) {
            in_word = false;
            count += 1;
            if (format == 1 or format == 2) {
                try word_list.append(vm.allocator, str[word_start..idx]);
            }
        }
    }
    if (in_word) {
        count += 1;
        if (format == 1 or format == 2) {
            try word_list.append(vm.allocator, str[word_start..]);
        }
    }

    if (format == 0) {
        return Value.initInt(count);
    }

    // Format 1: return array of words (numeric keys)
    // Format 2: return array of words (position => word)
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    for (word_list.items, 0..) |word, idx| {
        const word_val = try Value.initString(vm.allocator, word);
        if (format == 1) {
            try result_array.push(vm.allocator, word_val);
        } else {
            // format == 2: key is the position in the string
            const key = ArrayKey{ .integer = @intCast(idx) };
            try result_array.set(vm.allocator, key, word_val);
        }
        vm.releaseValue(word_val);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

/// levenshtein() — 计算编辑距离
pub fn levenshteinFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const str1 = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const str2 = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";

    // Cost parameters (optional)
    const cost_ins: i64 = if (args.len > 2 and args[2].getTag() == .integer) args[2].asInt() else 1;
    const cost_rep: i64 = if (args.len > 3 and args[3].getTag() == .integer) args[3].asInt() else 1;
    const cost_del: i64 = if (args.len > 4 and args[4].getTag() == .integer) args[4].asInt() else 1;

    const m = str1.len;
    const n = str2.len;

    // Optimization: if one string is empty, distance is the other's length * cost
    if (m == 0) return Value.initInt(@as(i64, @intCast(n)) * cost_ins);
    if (n == 0) return Value.initInt(@as(i64, @intCast(m)) * cost_del);

    // Use two-row DP for O(min(m,n)) space
    // Ensure str2 is the shorter one for space optimization
    if (m < n) {
        // Swap and recurse — but we need to swap costs too
        // insert on str1 = delete on str2 and vice versa
        const result = levenshteinDistance(str2, str1, cost_ins, cost_rep, cost_del);
        return Value.initInt(@intCast(result));
    }

    const result = levenshteinDistance(str1, str2, cost_del, cost_rep, cost_ins);
    return Value.initInt(@intCast(result));
}

/// Levenshtein distance computation using two-row DP
fn levenshteinDistance(s1: []const u8, s2: []const u8, cost_del: i64, cost_rep: i64, cost_ins: i64) i64 {
    const m = s1.len;
    const n = s2.len;

    // If n is too large for our buffer, fall back to a simpler algorithm
    if (n > 1024) {
        // Simple approximation for very long strings
        var dist: i64 = 0;
        var i: usize = 0;
        var j: usize = 0;
        while (i < m and j < n) {
            if (s1[i] != s2[j]) dist += cost_rep;
            i += 1;
            j += 1;
        }
        dist += @as(i64, @intCast(m - i)) * cost_del;
        dist += @as(i64, @intCast(n - j)) * cost_ins;
        return dist;
    }

    // Previous and current rows - stack allocated
    var prev_buf: [1025]i64 = undefined;
    var curr_buf: [1025]i64 = undefined;

    // Initialize first row
    var j: usize = 0;
    while (j <= n) : (j += 1) {
        prev_buf[j] = @as(i64, @intCast(j)) * cost_ins;
    }

    // Fill DP table
    var i: usize = 1;
    while (i <= m) : (i += 1) {
        curr_buf[0] = @as(i64, @intCast(i)) * cost_del;
        j = 1;
        while (j <= n) : (j += 1) {
            const cost: i64 = if (s1[i - 1] == s2[j - 1]) 0 else cost_rep;
            curr_buf[j] = @min(
                prev_buf[j] + cost_del,
                @min(
                    curr_buf[j - 1] + cost_ins,
                    prev_buf[j - 1] + cost,
                ),
            );
        }
        // Swap rows by copying
        for (0..n + 1) |k| {
            prev_buf[k] = curr_buf[k];
        }
    }

    return prev_buf[n];
}

/// similar_text() — 计算相似度
pub fn similarTextFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const str1 = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const str2 = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";

    const m = str1.len;
    const n = str2.len;

    if (m == 0 and n == 0) return Value.initInt(0);
    if (m == 0 or n == 0) return Value.initInt(0);

    // Use LCS (Longest Common Subsequence) to compute similarity
    const lcs_len = lcsLength(str1, str2);
    const max_len = @max(m, n);
    const similarity = @as(f64, @floatFromInt(lcs_len)) / @as(f64, @floatFromInt(max_len)) * 100.0;

    // If third argument is provided, store the percentage
    if (args.len > 2) {
        // In PHP, the third argument is passed by reference
        // In our AOT context, we can't modify variables by reference
        // Just return the number of matching chars
    }

    return Value.initFloat(similarity);
}

/// LCS length computation using two-row DP
fn lcsLength(s1: []const u8, s2: []const u8) usize {
    const m = s1.len;
    const n = s2.len;

    if (m > 1024 or n > 1024) {
        // Fallback for very long strings: count matching chars at same positions
        var count: usize = 0;
        const min_len = @min(m, n);
        for (s1[0..min_len], s2[0..min_len]) |c1, c2| {
            if (c1 == c2) count += 1;
        }
        return count;
    }

    var prev: [1025]usize = .{0} ** 1025;
    var curr: [1025]usize = .{0} ** 1025;

    var i: usize = 1;
    while (i <= m) : (i += 1) {
        curr[0] = 0;
        var j: usize = 1;
        while (j <= n) : (j += 1) {
            if (s1[i - 1] == s2[j - 1]) {
                curr[j] = prev[j - 1] + 1;
            } else {
                curr[j] = @max(prev[j], curr[j - 1]);
            }
        }
        // Swap by copying
        for (0..n + 1) |k| {
            prev[k] = curr[k];
        }
    }

    return prev[n];
}

// ============================================================================
// 字符串查找函数（strstr / stristr / strrchr）
// ============================================================================

/// strstr() — 查找字符串首次出现，返回从该位置到末尾的子串
pub fn strstrFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strstr() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    // PHP 行为：空 needle 返回整个 haystack
    if (needle_str.len == 0) return Value.initString(vm.allocator, haystack_str);

    // 使用 SIMD 优化搜索
    if (SimdString.findSimd(haystack_str, needle_str)) |idx| {
        return Value.initString(vm.allocator, haystack_str[idx..]);
    }
    return Value.initBool(false);
}

/// stristr() — 不区分大小写的 strstr
pub fn stristrFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "stristr() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    // PHP 行为：空 needle 返回整个 haystack
    if (needle_str.len == 0) return Value.initString(vm.allocator, haystack_str);

    // 不区分大小写搜索
    if (needle_str.len > haystack_str.len) return Value.initBool(false);
    var search_idx: usize = 0;
    while (search_idx <= haystack_str.len - needle_str.len) : (search_idx += 1) {
        var match = true;
        for (needle_str, 0..) |nc, ni| {
            if (std.ascii.toLower(nc) != std.ascii.toLower(haystack_str[search_idx + ni])) {
                match = false;
                break;
            }
        }
        if (match) {
            return Value.initString(vm.allocator, haystack_str[search_idx..]);
        }
    }
    return Value.initBool(false);
}

/// strrchr() — 查找字符/字符串最后一次出现，返回从该位置到末尾的子串
pub fn strrchrFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];

    if (haystack.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strrchr() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;

    // strrchr 的 needle 可以是字符串或整数（ASCII 码值）
    if (needle.getTag() == .integer) {
        // 整数模式：查找该 ASCII 字符最后一次出现
        const char_val: u8 = @truncate(@as(u64, @bitCast(needle.asInt())));
        if (std.mem.lastIndexOfScalar(u8, haystack_str, char_val)) |idx| {
            return Value.initString(vm.allocator, haystack_str[idx..]);
        }
        return Value.initBool(false);
    }

    if (needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strrchr() expects parameter 2 to be string or integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const needle_str = needle.getAsString().data.data;
    if (needle_str.len == 0) return Value.initBool(false);

    // PHP strrchr 行为：只使用 needle 的第一个字符
    const char_val = needle_str[0];
    if (std.mem.lastIndexOfScalar(u8, haystack_str, char_val)) |idx| {
        return Value.initString(vm.allocator, haystack_str[idx..]);
    }
    return Value.initBool(false);
}

// ============================================================================
// 单元测试
// ============================================================================

test "stdlib_string: hexCharToInt converts decimal digits" {
    try std.testing.expectEqual(@as(u8, 0), hexCharToInt('0').?);
    try std.testing.expectEqual(@as(u8, 5), hexCharToInt('5').?);
    try std.testing.expectEqual(@as(u8, 9), hexCharToInt('9').?);
}

test "stdlib_string: hexCharToInt converts lowercase hex" {
    try std.testing.expectEqual(@as(u8, 10), hexCharToInt('a').?);
    try std.testing.expectEqual(@as(u8, 15), hexCharToInt('f').?);
}

test "stdlib_string: hexCharToInt converts uppercase hex" {
    try std.testing.expectEqual(@as(u8, 10), hexCharToInt('A').?);
    try std.testing.expectEqual(@as(u8, 15), hexCharToInt('F').?);
}

test "stdlib_string: hexCharToInt returns null for invalid" {
    try std.testing.expect(hexCharToInt('g') == null);
    try std.testing.expect(hexCharToInt('Z') == null);
    try std.testing.expect(hexCharToInt('@') == null);
    try std.testing.expect(hexCharToInt('/') == null);
}

test "stdlib_string: stringReplaceOnce basic replacement" {
    const allocator = std.testing.allocator;
    const result = try stringReplaceOnce(allocator, "hello world", "world", "zig", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello zig", result);
}

test "stdlib_string: stringReplaceOnce multiple occurrences" {
    const allocator = std.testing.allocator;
    const result = try stringReplaceOnce(allocator, "aaa", "a", "bb", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("bbbbbb", result);
}

test "stdlib_string: stringReplaceOnce no match returns original" {
    const allocator = std.testing.allocator;
    const result = try stringReplaceOnce(allocator, "hello", "xyz", "abc", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "stdlib_string: stringReplaceOnce empty search returns original" {
    const allocator = std.testing.allocator;
    const result = try stringReplaceOnce(allocator, "hello", "", "abc", false);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "stdlib_string: stringReplaceOnce case insensitive" {
    const allocator = std.testing.allocator;
    const result = try stringReplaceOnce(allocator, "Hello WORLD", "world", "zig", true);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello zig", result);
}

test "stdlib_string: handler functions exist" {
    _ = &strlenFn;
    _ = &substrFn;
    _ = &strReplaceFn;
    _ = &strIreplaceFn;
    _ = &strposFn;
    _ = &striposFn;
    _ = &strrposFn;
    _ = &strriposFn;
    _ = &strtolowerFn;
    _ = &strtoupperFn;
    _ = &trimFn;
    _ = &ltrimFn;
    _ = &rtrimFn;
    _ = &explodeFn;
    _ = &implodeFn;
    _ = &strRepeatFn;
    _ = &sprintfFn;
    _ = &md5Fn;
    _ = &sha1Fn;
    _ = &base64EncodeFn;
    _ = &base64DecodeFn;
    _ = &bin2hexFn;
    _ = &hex2binFn;
    _ = &ordFn;
    _ = &chrFn;
    _ = &echoFn;
}
