//! 数组内置函数实现模块
//! 从 stdlib.zig 拆分而来 — 包含所有数组操作、排序、迭代器函数

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

// ============================================================================
// 回调辅助函数（供 array_map/array_filter/array_reduce/array_walk 使用）
// ============================================================================

/// 快速路径回调调用 — 1 个参数（array_map, array_filter）
pub inline fn invokeCallbackFast(vm: *VM, callback: Value, arg: Value) !Value {
    return switch (callback.getTag()) {
        .native_function => blk: {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            const args = [_]Value{arg};
            break :blk try function(vm, &args);
        },
        .closure => blk: {
            const closure = callback.getAsClosure().data;
            break :blk try vm.callClosureFast(closure, arg);
        },
        .arrow_function => blk: {
            const arrow_fn = callback.getAsArrowFunc().data;
            break :blk try vm.callArrowFunctionFast(arrow_fn, arg);
        },
        else => error.InvalidCallback,
    };
}

/// 快速路径回调调用 — 2 个参数（array_reduce）
pub inline fn invokeCallbackFast2(vm: *VM, callback: Value, arg1: Value, arg2: Value) !Value {
    return switch (callback.getTag()) {
        .native_function => blk: {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            const args = [_]Value{ arg1, arg2 };
            break :blk try function(vm, &args);
        },
        .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, &[_]Value{ arg1, arg2 }),
        .closure => blk: {
            const closure = callback.getAsClosure().data;
            break :blk try vm.callClosureFast2(closure, arg1, arg2);
        },
        .arrow_function => blk: {
            const arrow_fn = callback.getAsArrowFunc().data;
            break :blk try vm.callArrowFunction(arrow_fn, &[_]Value{ arg1, arg2 });
        },
        else => error.InvalidCallback,
    };
}

/// 通用回调调用 — 1-2 个参数
pub inline fn invokeCallback(vm: *VM, callback: Value, args: []const Value) !Value {
    return switch (callback.getTag()) {
        .native_function => blk: {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            break :blk try function(vm, args);
        },
        .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, args),
        .closure => try vm.callClosure(callback.getAsClosure().data, args),
        .arrow_function => try vm.callArrowFunction(callback.getAsArrowFunc().data, args),
        else => error.InvalidCallback,
    };
}

// ============================================================================
// 包装函数（委托给 builtin_random）
// ============================================================================

pub fn shuffleWrapper(vm: *VM, args: []const Value) !Value {
    return builtin_random.RandomBuiltins.shuffle(vm, args);
}

pub fn arrayRandWrapper(vm: *VM, args: []const Value) !Value {
    return builtin_random.RandomBuiltins.array_rand(vm, args);
}

// ============================================================================
// 排序辅助函数与类型
// ============================================================================

/// Value 比较辅助
pub fn compareValues(a: Value, b: Value) i8 {
    if (a.getTag() == .integer and b.getTag() == .integer) {
        if (a.asInt() < b.asInt()) return -1;
        if (a.asInt() > b.asInt()) return 1;
        return 0;
    } else if (a.getTag() == .float and b.getTag() == .float) {
        if (a.asFloat() < b.asFloat()) return -1;
        if (a.asFloat() > b.asFloat()) return 1;
        return 0;
    } else {
        const a_float = switch (a.getTag()) {
            .integer => @as(f64, @floatFromInt(a.asInt())),
            .float => a.asFloat(),
            else => 0.0,
        };
        const b_float = switch (b.getTag()) {
            .integer => @as(f64, @floatFromInt(b.asInt())),
            .float => b.asFloat(),
            else => 0.0,
        };

        if (a_float < b_float) return -1;
        if (a_float > b_float) return 1;
        return 0;
    }
}

pub const ArraySortItem = struct {
    key: ArrayKey,
    value: Value,
};

pub fn compareArrayKeys(a: ArrayKey, b: ArrayKey) i8 {
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

pub fn collectArraySortItems(vm: *VM, php_array: *types.PHPArray) !std.ArrayListUnmanaged(ArraySortItem) {
    var items = std.ArrayListUnmanaged(ArraySortItem){ .items = &.{}, .capacity = 0 };
    errdefer items.deinit(vm.allocator);

    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        try items.append(vm.allocator, .{
            .key = entry.key_ptr.*,
            .value = entry.value_ptr.*,
        });
    }

    return items;
}

pub fn rebuildArrayWithSortedItems(php_array: *types.PHPArray, items: []const ArraySortItem) void {
    const elements = php_array.getElements();
    elements.clearRetainingCapacity();
    php_array.next_index = 0;

    for (items) |item| {
        elements.put(php_array.allocator, item.key, item.value) catch {};
        if (item.key == .integer and item.key.integer >= php_array.next_index) {
            php_array.next_index = item.key.integer + 1;
        }
    }
}

// ============================================================================
// 数组函数实现
// ============================================================================

pub fn arrayMapFn(vm: *VM, args: []const Value) !Value {
    const callback = args[0];
    const array = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_map() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(vm.allocator, count);

    var iterator = source_array.getElements().iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        // Use fast callback for native functions, closures, arrow functions
        const result_value = invokeCallbackFast(vm, callback, value) catch {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_map() expects parameter 1 to be a valid callback", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        };

        result_array.getElements().putAssumeCapacity(key, result_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayFilterFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_filter() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(vm.allocator, count);

    const callback = if (args.len > 1) args[1] else null;

    var iterator = source_array.getElements().iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        var should_include = false;

        if (callback) |cb| {
            const result_value = invokeCallbackFast(vm, cb, value) catch {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_filter() expects parameter 2 to be a valid callback", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidArgumentType;
            };
            should_include = result_value.toBool();
        } else {
            should_include = value.toBool();
        }

        if (should_include) {
            result_array.getElements().putAssumeCapacity(key, value);
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayReduceFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];
    const initial = if (args.len > 2) args[2] else Value.initNull();

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_reduce() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var accumulator = initial;

    var iterator = array.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        accumulator = invokeCallbackFast2(vm, callback, accumulator, value) catch {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_reduce() expects parameter 2 to be a valid callback", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        };
    }

    return accumulator;
}

pub fn arrayMergeFn(vm: *VM, args: []const Value) !Value {
    // First pass: calculate total element count for pre-allocation
    var total_count: usize = 0;
    for (args) |arg| {
        if (arg.getTag() != .array) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_merge() expects all parameters to be arrays", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }
        total_count += arg.getAsArray().data.count();
    }

    if (total_count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_array,
        };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(vm.allocator, total_count);

    // Second pass: merge all arrays with direct insertion
    for (args) |arg| {
        var iterator = arg.getAsArray().data.getElements().iterator();
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Direct insertion - retain value and put
            _ = value.retain();
            switch (key) {
                .integer => {
                    const dest_key = ArrayKey{ .integer = result_array.next_index };
                    result_array.next_index += 1;
                    result_array.getElements().putAssumeCapacity(dest_key, value);
                },
                .string => |s| {
                    // Retain string key
                    const new_key = ArrayKey{ .string = s };
                    new_key.string.retain();
                    result_array.getElements().putAssumeCapacity(new_key, value);
                },
            }
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayKeysFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_keys() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    if (count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_array,
        };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    // Pre-allocate result array
    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(vm.allocator, count);

    var iterator = source_array.getElements().iterator();
    var idx: i64 = 0;
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;

        const key_value = switch (key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                const str = try PHPString.init(vm.allocator, s.data);
                const box = try vm.allocator.create(types.gc.Box(*PHPString));
                box.* = .{
                    .ref_count = 1,
                    .gc_info = .{},
                    .data = str,
                };
                break :blk Value.fromBox(box, Value.TYPE_STRING);
            },
        };

        // Direct insert with integer key
        const dest_key = ArrayKey{ .integer = idx };
        idx += 1;
        _ = key_value.retain();
        result_array.getElements().putAssumeCapacity(dest_key, key_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayValuesFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_values() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    if (count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_array,
        };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(vm.allocator, count);

    // Direct insertion - avoid push overhead
    var iterator = source_array.getElements().iterator();
    var idx: i64 = 0;
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        _ = value.retain();
        const key = ArrayKey{ .integer = idx };
        idx += 1;
        result_array.getElements().putAssumeCapacity(key, value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayPushFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_push() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    // Push all additional arguments
    for (args[1..]) |value| {
        try php_array.push(vm.allocator, value);
    }

    return Value.initInt(@intCast(php_array.count()));
}

pub fn arrayPopFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_pop() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    if (php_array.count() == 0) {
        return Value.initNull();
    }

    // Find the last element (simplified implementation)
    var last_key: ?ArrayKey = null;
    var last_value: ?Value = null;

    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        last_key = entry.key_ptr.*;
        last_value = entry.value_ptr.*;
    }

    if (last_key) |key| {
        const result = last_value.?;
        _ = php_array.getElements().swapRemove(key);
        return result;
    }

    return Value.initNull();
}

pub fn arrayShiftFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_shift() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    if (php_array.count() == 0) {
        return Value.initNull();
    }

    // Find the first element (simplified implementation)
    var first_key: ?ArrayKey = null;
    var first_value: ?Value = null;

    var iterator = php_array.getElements().iterator();
    if (iterator.next()) |entry| {
        first_key = entry.key_ptr.*;
        first_value = entry.value_ptr.*;
    }

    if (first_key) |key| {
        const result = first_value.?;
        _ = php_array.getElements().swapRemove(key);
        return result;
    }

    return Value.initNull();
}

pub fn arrayUnshiftFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_unshift() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    // Create new array with unshifted elements
    var new_array = PHPArray.init(vm.allocator);

    // Add new elements first
    for (args[1..]) |value| {
        try new_array.push(vm.allocator, value);
    }

    // Add existing elements
    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        try new_array.push(vm.allocator, value);
    }

    // Replace the original array's contents by copying from new_array
    // First clear the old array
    php_array.getElements().clearRetainingCapacity();

    // Copy elements from new_array
    var new_iter = new_array.getElements().iterator();
    while (new_iter.next()) |entry| {
        try php_array.set(vm.allocator, entry.key_ptr.*, entry.value_ptr.*);
    }
    php_array.next_index = new_array.next_index;

    return Value.initInt(@intCast(php_array.count()));
}

pub fn inArrayFn(vm: *VM, args: []const Value) !Value {
    const needle = args[0];
    const haystack = args[1];
    const strict = if (args.len > 2) args[2].toBool() else false;

    if (haystack.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "in_array() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Fast path: if needle is already a string and we're not in strict mode,
    // we can avoid repeated conversions
    const needle_is_string = needle.getTag() == .string;
    var needle_str: ?*types.PHPString = null;
    defer if (needle_str) |s| s.release(vm.allocator);

    if (!strict and needle_is_string) {
        needle_str = needle.getAsString().data;
        needle_str.?.retain();
    }

    var iterator = haystack.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        if (strict) {
            // Strict comparison (type and value)
            if (needle.getTag() == value.getTag()) {
                const is_equal = switch (needle.getTag()) {
                    .null => true,
                    .boolean => needle.asBool() == value.asBool(),
                    .integer => needle.asInt() == value.asInt(),
                    .float => needle.asFloat() == value.asFloat(),
                    .string => std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data),
                    else => false, // Simplified for other types
                };
                if (is_equal) return Value.initBool(true);
            }
        } else {
            // Loose comparison - optimized path
            if (value.getTag() == needle.getTag()) {
                // Same type - can compare directly without conversion
                const is_equal = switch (needle.getTag()) {
                    .null => true,
                    .boolean => needle.asBool() == value.asBool(),
                    .integer => needle.asInt() == value.asInt(),
                    .float => needle.asFloat() == value.asFloat(),
                    .string => std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data),
                    else => false,
                };
                if (is_equal) return Value.initBool(true);
            } else if (needle_is_string and value.getTag() == .string) {
                // Both are strings - direct comparison
                if (std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data)) {
                    return Value.initBool(true);
                }
            } else {
                // Type mismatch - need conversion for comparison
                const needle_str_val = needle_str orelse needle: {
                    const s = try needle.toString(vm.allocator);
                    needle_str = s;
                    break :needle s;
                };
                const value_str = try value.toString(vm.allocator);
                defer value_str.deinit(vm.allocator);

                if (std.mem.eql(u8, needle_str_val.data, value_str.data)) {
                    return Value.initBool(true);
                }
            }
        }
    }

    return Value.initBool(false);
}

pub fn arraySearchFn(vm: *VM, args: []const Value) !Value {
    const needle = args[0];
    const haystack = args[1];
    const strict = if (args.len > 2) args[2].toBool() else false;

    if (haystack.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_search() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Fast path: if needle is already a string and we're not in strict mode,
    // we can avoid repeated conversions
    const needle_is_string = needle.getTag() == .string;
    var needle_str: ?*types.PHPString = null;
    defer if (needle_str) |s| s.release(vm.allocator);

    if (!strict and needle_is_string) {
        needle_str = needle.getAsString().data;
        needle_str.?.retain();
    }

    var iterator = haystack.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        var is_match = false;

        if (strict) {
            // Strict comparison
            if (needle.getTag() == value.getTag()) {
                is_match = switch (needle.getTag()) {
                    .null => true,
                    .boolean => needle.asBool() == value.asBool(),
                    .integer => needle.asInt() == value.asInt(),
                    .float => needle.asFloat() == value.asFloat(),
                    .string => std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data),
                    else => false,
                };
            }
        } else {
            // Loose comparison - optimized path
            if (value.getTag() == needle.getTag()) {
                // Same type - can compare directly without conversion
                is_match = switch (needle.getTag()) {
                    .null => true,
                    .boolean => needle.asBool() == value.asBool(),
                    .integer => needle.asInt() == value.asInt(),
                    .float => needle.asFloat() == value.asFloat(),
                    .string => std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data),
                    else => false,
                };
            } else if (needle_is_string and value.getTag() == .string) {
                // Both are strings - direct comparison
                is_match = std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data);
            } else {
                // Type mismatch - need conversion for comparison
                const needle_str_val = needle_str orelse needle: {
                    const s = try needle.toString(vm.allocator);
                    needle_str = s;
                    break :needle s;
                };
                const value_str = try value.toString(vm.allocator);
                defer value_str.deinit(vm.allocator);

                is_match = std.mem.eql(u8, needle_str_val.data, value_str.data);
            }
        }

        if (is_match) {
            return switch (key) {
                .integer => |i| Value.initInt(i),
                .string => |s| blk: {
                    const box = try vm.allocator.create(types.gc.Box(*PHPString));
                    box.* = .{
                        .ref_count = 1,
                        .gc_info = .{},
                        .data = try PHPString.init(vm.allocator, s.data),
                    };
                    break :blk Value.fromBox(box, Value.TYPE_STRING);
                },
            };
        }
    }

    return Value.initBool(false); // PHP returns false when not found
}

// ============================================================================
// PHP 8.5 数组函数
// ============================================================================

pub fn arrayFirstFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = if (args.len > 1) args[1] else null;

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_first() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var iterator = array.getAsArray().data.getElements().iterator();

    if (callback) |cb| {
        // Find first element that matches callback
        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;

            const callback_args = [_]Value{value};
            const result_value = switch (cb.getTag()) {
                .native_function => blk: {
                    const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(cb.getAsNativeFunc()));
                    break :blk try function(vm, &callback_args);
                },
                .user_function => try vm.callUserFunction(cb.getAsUserFunc().data, &callback_args),
                .closure => try vm.callClosure(cb.getAsClosure().data, &callback_args),
                .arrow_function => try vm.callArrowFunction(cb.getAsArrowFunc().data, &callback_args),
                else => {
                    const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_first() expects parameter 2 to be a valid callback", "builtin", 0);
                    _ = try vm.throwException(exception);
                    return error.InvalidArgumentType;
                },
            };

            if (result_value.toBool()) {
                return value;
            }
        }
        return Value.initNull();
    } else {
        // Return first element
        if (iterator.next()) |entry| {
            return entry.value_ptr.*;
        }
        return Value.initNull();
    }
}

pub fn arrayLastFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = if (args.len > 1) args[1] else null;

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_last() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (callback) |cb| {
        // Find last element that matches callback
        var last_match: ?Value = null;
        var iterator = array.getAsArray().data.getElements().iterator();

        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;

            const callback_args = [_]Value{value};
            const result_value = switch (cb.getTag()) {
                .native_function => blk: {
                    const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(cb.getAsNativeFunc()));
                    break :blk try function(vm, &callback_args);
                },
                .user_function => try vm.callUserFunction(cb.getAsUserFunc().data, &callback_args),
                .closure => try vm.callClosure(cb.getAsClosure().data, &callback_args),
                .arrow_function => try vm.callArrowFunction(cb.getAsArrowFunc().data, &callback_args),
                else => {
                    const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_last() expects parameter 2 to be a valid callback", "builtin", 0);
                    _ = try vm.throwException(exception);
                    return error.InvalidArgumentType;
                },
            };

            if (result_value.toBool()) {
                last_match = value;
            }
        }
        return last_match orelse Value.initNull();
    } else {
        // Return last element
        var last_value: ?Value = null;
        var iterator = array.getAsArray().data.getElements().iterator();

        while (iterator.next()) |entry| {
            last_value = entry.value_ptr.*;
        }

        return last_value orelse Value.initNull();
    }
}

// ============================================================================
// 额外数组函数
// ============================================================================

pub fn arraySumFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_sum() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // 使用PHPArray的SoA优化求和方法
    const php_array = array.getAsArray().data;
    const sum = php_array.sumFloats();

    // Return int if sum is a whole number
    if (@floor(sum) == sum and sum >= @as(f64, @floatFromInt(std.math.minInt(i64))) and sum <= @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
        return Value.initInt(@intFromFloat(sum));
    }
    return Value.initFloat(sum);
}

pub fn arrayProductFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_product() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var product: f64 = 1;
    var iterator = array.getAsArray().data.getElements().iterator();

    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        product *= switch (value.getTag()) {
            .integer => @floatFromInt(value.asInt()),
            .float => value.asFloat(),
            .string => std.fmt.parseFloat(f64, value.getAsString().data.data) catch 0,
            else => 0,
        };
    }

    if (@floor(product) == product and product >= @as(f64, @floatFromInt(std.math.minInt(i64))) and product <= @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
        return Value.initInt(@intFromFloat(product));
    }
    return Value.initFloat(product);
}

pub fn arrayReverseFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const preserve_keys = if (args.len > 1) args[1].toBool() else false;

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_reverse() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    if (count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(vm.allocator, count);

    // Pre-allocate temp array with exact size
    const temp = try vm.allocator.alloc(struct { key: ArrayKey, value: Value }, count);
    defer vm.allocator.free(temp);

    // Copy elements to temp (backwards order)
    var idx: usize = 0;
    var iterator = source_array.getElements().iterator();
    while (iterator.next()) |entry| {
        temp[idx] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
        idx += 1;
    }

    // Reverse insert directly
    var new_index: i64 = 0;
    var i: usize = count;
    while (i > 0) {
        i -= 1;
        const item = temp[i];
        _ = item.value.retain();
        if (preserve_keys) {
            // For string keys, need to retain
            if (item.key == .string) {
                item.key.string.retain();
            }
            result_array.getElements().putAssumeCapacity(item.key, item.value);
        } else {
            const dest_key = ArrayKey{ .integer = new_index };
            new_index += 1;
            result_array.getElements().putAssumeCapacity(dest_key, item.value);
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayUniqueFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_unique() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    var seen = std.StringHashMap(void).init(vm.allocator);
    defer seen.deinit();

    var iterator = array.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        const str_val = switch (value.getTag()) {
            .string => value.getAsString().data.data,
            .integer => blk: {
                const buf = try std.fmt.allocPrint(vm.allocator, "{d}", .{value.asInt()});
                break :blk buf;
            },
            else => "",
        };

        if (!seen.contains(str_val)) {
            try seen.put(str_val, {});
            try result_array.set(vm.allocator, entry.key_ptr.*, value);
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayFlipFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_flip() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const count = arr.getElements().count();

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    // Pre-allocate capacity
    try result_array.getElements().ensureTotalCapacity(vm.allocator, count);

    var iterator = arr.getElements().iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const new_key: ArrayKey = switch (value.getTag()) {
            .integer => ArrayKey{ .integer = value.asInt() },
            .string => blk: {
                const str = try PHPString.init(vm.allocator, value.getAsString().data.data);
                break :blk ArrayKey{ .string = str };
            },
            else => continue,
        };

        const new_value = switch (key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                const box = try vm.allocator.create(types.gc.Box(*PHPString));
                box.* = .{ .ref_count = 1, .gc_info = .{}, .data = try PHPString.init(vm.allocator, s.data) };
                break :blk Value.fromBox(box, Value.TYPE_STRING);
            },
        };

        result_array.getElements().putAssumeCapacity(new_key, new_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arraySliceFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const offset_val = args[1];
    const length_val = if (args.len > 2) args[2] else Value.initNull();

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_slice() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();
    const offset: i64 = if (offset_val.getTag() == .integer) offset_val.asInt() else 0;
    const length: i64 = if (length_val.getTag() == .integer) length_val.asInt() else @intCast(count);

    if (count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    // Calculate slice range
    const start: usize = if (offset < 0)
        @intCast(@max(0, @as(i64, @intCast(count)) + offset))
    else
        @intCast(@min(@as(i64, @intCast(count)), offset));

    const end: usize = if (length < 0)
        @intCast(@max(0, @as(i64, @intCast(count)) + length))
    else
        @intCast(@min(@as(i64, @intCast(count)), @as(i64, @intCast(start)) + length));

    const slice_count = if (end > start) end - start else 0;
    if (slice_count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(vm.allocator, slice_count);

    // Direct insertion - collect and copy values
    var iterator = source_array.getElements().iterator();
    var idx: usize = 0;
    var result_idx: i64 = 0;
    while (iterator.next()) |entry| {
        if (idx >= start and idx < end) {
            const value = entry.value_ptr.*;
            _ = value.retain();
            const key = ArrayKey{ .integer = result_idx };
            result_idx += 1;
            result_array.getElements().putAssumeCapacity(key, value);
        }
        idx += 1;
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayColumnFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const column_key = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_column() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    const col_key: ArrayKey = switch (column_key.getTag()) {
        .string => blk: {
            const str = try PHPString.init(vm.allocator, column_key.getAsString().data.data);
            break :blk ArrayKey{ .string = str };
        },
        .integer => ArrayKey{ .integer = column_key.asInt() },
        else => ArrayKey{ .integer = 0 },
    };

    var iterator = array.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const row = entry.value_ptr.*;
        if (row.getTag() == .array) {
            if (row.getAsArray().data.get(col_key)) |col_value| {
                try result_array.push(vm.allocator, col_value);
            }
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn rangeFunction(vm: *VM, args: []const Value) !Value {
    const start_val = args[0];
    const end_val = args[1];
    const step_val = if (args.len > 2) args[2] else Value.initInt(1);

    const start: i64 = switch (start_val.getTag()) {
        .integer => start_val.asInt(),
        else => 0,
    };
    const end: i64 = switch (end_val.getTag()) {
        .integer => end_val.asInt(),
        else => 0,
    };
    const step: i64 = switch (step_val.getTag()) {
        .integer => @max(1, step_val.asInt()),
        else => 1,
    };

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    if (start <= end) {
        var i = start;
        while (i <= end) : (i += step) {
            try result_array.push(vm.allocator, Value.initInt(i));
        }
    } else {
        var i = start;
        while (i >= end) : (i -= step) {
            try result_array.push(vm.allocator, Value.initInt(i));
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayFillFn(vm: *VM, args: []const Value) !Value {
    const start_index: i64 = if (args[0].getTag() == .integer) args[0].asInt() else 0;
    const num: i64 = if (args[1].getTag() == .integer) args[1].asInt() else 0;
    const value = args[2];

    if (num <= 0) {
        var empty_array = try vm.allocator.create(PHPArray);
        errdefer {
            empty_array.deinit(vm.allocator);
            vm.allocator.destroy(empty_array);
        }
        empty_array.* = PHPArray.init(vm.allocator);

        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = empty_array };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    // Retain value once for all uses
    _ = value.retain();

    var i: i64 = 0;
    while (i < num) : (i += 1) {
        try result_array.set(vm.allocator, ArrayKey{ .integer = start_index + i }, value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn compactFn(vm: *VM, args: []const Value) !Value {
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    for (args) |arg| {
        if (arg.getTag() == .string) {
            const var_name = arg.getAsString().data.data;
            const prefixed_name = try std.fmt.allocPrint(vm.allocator, "${s}", .{var_name});
            defer vm.allocator.free(prefixed_name);

            if (vm.getVariable(prefixed_name)) |value| {
                const key = try PHPString.init(vm.allocator, var_name);
                try result_array.set(vm.allocator, ArrayKey{ .string = key }, value);
            }
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// ============================================================================
// 排序函数
// ============================================================================

pub fn sortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    // flags parameter (args[1]) ignored for now - uses default SORT_REGULAR

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    // Collect values into a temporary list for sorting
    var values = std.ArrayListUnmanaged(Value){ .items = &.{}, .capacity = 0 };
    defer values.deinit(vm.allocator);

    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        try values.append(vm.allocator, entry.value_ptr.*);
    }

    // Sort values using comparison
    std.mem.sort(Value, values.items, {}, struct {
        fn lessThan(_: void, a: Value, b: Value) bool {
            return compareValues(a, b) < 0;
        }
    }.lessThan);

    // Clear and rebuild array with numeric keys
    php_array.getElements().clearRetainingCapacity();
    php_array.next_index = 0;

    for (values.items) |value| {
        const key = ArrayKey{ .integer = @intCast(php_array.next_index) };
        php_array.getElements().put(vm.allocator, key, value) catch {};
        php_array.next_index += 1;
    }

    return Value.initBool(true);
}

pub fn rsortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "rsort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    var values = std.ArrayListUnmanaged(Value){ .items = &.{}, .capacity = 0 };
    defer values.deinit(vm.allocator);

    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        try values.append(vm.allocator, entry.value_ptr.*);
    }

    // Sort in descending order
    std.mem.sort(Value, values.items, {}, struct {
        fn lessThan(_: void, a: Value, b: Value) bool {
            return compareValues(a, b) > 0;
        }
    }.lessThan);

    php_array.getElements().clearRetainingCapacity();
    php_array.next_index = 0;

    for (values.items) |value| {
        const key = ArrayKey{ .integer = @intCast(php_array.next_index) };
        php_array.getElements().put(vm.allocator, key, value) catch {};
        php_array.next_index += 1;
    }

    return Value.initBool(true);
}

pub fn asortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "asort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;
    var items = try collectArraySortItems(vm, php_array);
    defer items.deinit(vm.allocator);

    std.mem.sort(ArraySortItem, items.items, {}, struct {
        fn lessThan(_: void, a: ArraySortItem, b: ArraySortItem) bool {
            return compareValues(a.value, b.value) < 0;
        }
    }.lessThan);

    rebuildArrayWithSortedItems(php_array, items.items);
    return Value.initBool(true);
}

pub fn arsortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "arsort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;
    var items = try collectArraySortItems(vm, php_array);
    defer items.deinit(vm.allocator);

    std.mem.sort(ArraySortItem, items.items, {}, struct {
        fn lessThan(_: void, a: ArraySortItem, b: ArraySortItem) bool {
            return compareValues(a.value, b.value) > 0;
        }
    }.lessThan);

    rebuildArrayWithSortedItems(php_array, items.items);
    return Value.initBool(true);
}

pub fn ksortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ksort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;
    var items = try collectArraySortItems(vm, php_array);
    defer items.deinit(vm.allocator);

    std.mem.sort(ArraySortItem, items.items, {}, struct {
        fn lessThan(_: void, a: ArraySortItem, b: ArraySortItem) bool {
            return compareArrayKeys(a.key, b.key) < 0;
        }
    }.lessThan);

    rebuildArrayWithSortedItems(php_array, items.items);
    return Value.initBool(true);
}

pub fn krsortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "krsort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;
    var items = try collectArraySortItems(vm, php_array);
    defer items.deinit(vm.allocator);

    std.mem.sort(ArraySortItem, items.items, {}, struct {
        fn lessThan(_: void, a: ArraySortItem, b: ArraySortItem) bool {
            return compareArrayKeys(a.key, b.key) > 0;
        }
    }.lessThan);

    rebuildArrayWithSortedItems(php_array, items.items);
    return Value.initBool(true);
}

pub fn usortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "usort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    _ = callback;
    _ = array.getAsArray().data;
    return Value.initBool(true);
}

/// uasort() — 用回调函数排序并保持索引关联
pub fn uasortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "uasort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // TODO: Full callback-based sorting with key preservation
    _ = callback;
    _ = array.getAsArray().data;
    return Value.initBool(true);
}

/// uksort() — 用回调函数对键名排序
pub fn uksortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "uksort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // TODO: Full callback-based key sorting
    _ = callback;
    _ = array.getAsArray().data;
    return Value.initBool(true);
}

// ============================================================================
// 计数/存在性检查函数
// ============================================================================

pub fn countFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const value = args[0];

    return switch (value.getTag()) {
        .array => Value.initInt(@intCast(value.getAsArray().data.count())),
        .string => Value.initInt(@intCast(value.getAsString().data.length)),
        .null => Value.initInt(0),
        else => Value.initInt(1),
    };
}

pub fn arrayKeyExistsFn(vm: *VM, args: []const Value) !Value {
    const key = args[0];
    const array = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_key_exists() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    const exists = switch (key.getTag()) {
        .integer => php_array.getElements().contains(ArrayKey{ .integer = key.asInt() }),
        .string => php_array.getElements().contains(ArrayKey{ .string = key.getAsString().data }),
        else => false,
    };

    return Value.initBool(exists);
}

// ============================================================================
// 数组组合/交集/差集
// ============================================================================

pub fn arrayCombineFn(vm: *VM, args: []const Value) !Value {
    const keys = args[0];
    const values = args[1];

    if (keys.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_combine() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (values.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_combine() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const keys_array = keys.getAsArray().data;
    const values_array = values.getAsArray().data;

    if (keys_array.count() != values_array.count()) {
        // array_combine(): Number of elements in key and value arrays don't match
        // Note: This is a warning in PHP, continuing with result
    }

    const result = try Value.initArrayWithManager(&vm.memory_manager);
    errdefer result.release(vm.allocator);

    const result_arr = result.getAsArray().data;

    var key_idx: i64 = 0;
    var value_idx: i64 = 0;

    while (true) {
        const key_opt = keys_array.get(ArrayKey{ .integer = key_idx });
        const value_opt = values_array.get(ArrayKey{ .integer = value_idx });

        if (key_opt == null or value_opt == null) break;

        const key_copy = key_opt.?.retain();
        const value_copy = value_opt.?.retain();

        const array_key = switch (key_copy.getTag()) {
            .integer => ArrayKey{ .integer = key_copy.asInt() },
            .string => ArrayKey{ .string = key_copy.getAsString().data },
            else => ArrayKey{ .integer = key_idx },
        };

        result_arr.set(vm.allocator, array_key, value_copy) catch {};
        key_idx += 1;
        value_idx += 1;
    }

    return result;
}

pub fn arrayIntersectFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        // array_intersect(): At least two parameters are required
        // Return empty array for now
        return Value.initArrayWithManager(&vm.memory_manager);
    }

    const array1 = args[0];
    if (array1.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_intersect() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr1 = array1.getAsArray().data;

    // Collect all values from all other arrays into a set
    // Using a simple approach: for each value in arr1, check if it exists in all other arrays
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    errdefer result.release(vm.allocator);

    const result_arr = result.getAsArray().data;

    // For each value in arr1, check if it exists in all other arrays
    var iter1 = arr1.getElements().iterator();
    while (iter1.next()) |entry1| {
        const value1 = entry1.value_ptr.*;

        // Check if this value exists in all other arrays
        var found_in_all = true;
        for (args[1..]) |arg| {
            if (arg.getTag() != .array) {
                found_in_all = false;
                break;
            }

            const arr = arg.getAsArray().data;
            var found = false;
            var iter = arr.getElements().iterator();
            while (iter.next()) |entry| {
                const value = entry.value_ptr.*;

                // Compare values
                const equal = blk: {
                    // Both integers
                    if (value1.getTag() == .integer and value.getTag() == .integer) {
                        break :blk value1.asInt() == value.asInt();
                    }
                    // Both floats
                    if (value1.getTag() == .float and value.getTag() == .float) {
                        break :blk value1.asFloat() == value.asFloat();
                    }
                    // Both strings
                    if (value1.getTag() == .string and value.getTag() == .string) {
                        const str1 = value1.getAsString().data.data;
                        const str2 = value.getAsString().data.data;
                        break :blk std.mem.eql(u8, str1, str2);
                    }
                    // Integer and float comparison
                    if (value1.getTag() == .integer and value.getTag() == .float) {
                        break :blk @as(f64, @floatFromInt(value1.asInt())) == value.asFloat();
                    }
                    if (value1.getTag() == .float and value.getTag() == .integer) {
                        break :blk value1.asFloat() == @as(f64, @floatFromInt(value.asInt()));
                    }
                    break :blk false;
                };

                if (equal) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                found_in_all = false;
                break;
            }
        }

        if (found_in_all) {
            const value_copy = value1.retain();
            result_arr.set(vm.allocator, ArrayKey{ .integer = @as(i64, @intCast(result_arr.count())) }, value_copy) catch {};
        }
    }

    return result;
}

pub fn arrayDiffFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        // array_diff(): At least two parameters are required
        return Value.initArrayWithManager(&vm.memory_manager);
    }

    const array1 = args[0];
    if (array1.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_diff() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr1 = array1.getAsArray().data;

    // Collect all values from all other arrays into a set
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    errdefer result.release(vm.allocator);

    const result_arr = result.getAsArray().data;

    // For each value in arr1, check if it exists in any other array
    var iter1 = arr1.getElements().iterator();
    while (iter1.next()) |entry1| {
        const value1 = entry1.value_ptr.*;

        // Check if this value exists in any other array
        var found = false;
        for (args[1..]) |arg| {
            if (arg.getTag() != .array) continue;

            const arr = arg.getAsArray().data;
            var iter = arr.getElements().iterator();
            while (iter.next()) |entry| {
                const value = entry.value_ptr.*;

                // Compare values
                const equal = blk: {
                    // Both integers
                    if (value1.getTag() == .integer and value.getTag() == .integer) {
                        break :blk value1.asInt() == value.asInt();
                    }
                    // Both floats
                    if (value1.getTag() == .float and value.getTag() == .float) {
                        break :blk value1.asFloat() == value.asFloat();
                    }
                    // Both strings
                    if (value1.getTag() == .string and value.getTag() == .string) {
                        const str1 = value1.getAsString().data.data;
                        const str2 = value.getAsString().data.data;
                        break :blk std.mem.eql(u8, str1, str2);
                    }
                    // Integer and float comparison
                    if (value1.getTag() == .integer and value.getTag() == .float) {
                        break :blk @as(f64, @floatFromInt(value1.asInt())) == value.asFloat();
                    }
                    if (value1.getTag() == .float and value.getTag() == .integer) {
                        break :blk value1.asFloat() == @as(f64, @floatFromInt(value.asInt()));
                    }
                    break :blk false;
                };

                if (equal) {
                    found = true;
                    break;
                }
            }

            if (found) break;
        }

        if (!found) {
            const value_copy = value1.retain();
            result_arr.set(vm.allocator, ArrayKey{ .integer = @as(i64, @intCast(result_arr.count())) }, value_copy) catch {};
        }
    }

    return result;
}

// ============================================================================
// 数组指针/随机函数
// ============================================================================

pub fn arrayRandFn(vm: *VM, args: []const Value) !Value {
    const arr_val = args[0];
    if (arr_val.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_rand() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = arr_val.getAsArray().data;
    const count = arr.count();
    if (count == 0) return Value.initNull();

    const num = if (args.len > 1) @as(usize, @intCast(@max(1, args[1].asInt()))) else 1;

    var prng = std.Random.DefaultPrng.init(@intCast(time_compat.timestamp()));
    const random = prng.random();

    if (num == 1) {
        // Return single key
        const idx = random.intRangeAtMost(usize, 0, count - 1);
        var iter = arr.getElements().iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            if (i == idx) {
                return switch (entry.key_ptr.*) {
                    .integer => |int| Value.initInt(int),
                    .string => |str| Value.initString(vm.allocator, str.data),
                };
            }
        }
    }

    // Return array of keys
    const result = try vm.allocator.create(PHPArray);
    result.* = PHPArray.init(vm.allocator);

    var selected = try std.ArrayList(usize).initCapacity(vm.allocator, num);
    defer selected.deinit(vm.allocator);

    while (selected.items.len < @min(num, count)) {
        const idx = random.intRangeAtMost(usize, 0, count - 1);
        var found = false;
        for (selected.items) |s| {
            if (s == idx) {
                found = true;
                break;
            }
        }
        if (!found) {
            try selected.append(vm.allocator, idx);
        }
    }

    var iter = arr.getElements().iterator();
    var i: usize = 0;
    var result_idx: i64 = 0;
    while (iter.next()) |entry| : (i += 1) {
        for (selected.items) |s| {
            if (s == i) {
                const key_val = switch (entry.key_ptr.*) {
                    .integer => |int| Value.initInt(int),
                    .string => |str| try Value.initString(vm.allocator, str.data),
                };
                try result.set(vm.allocator, .{ .integer = result_idx }, key_val);
                result_idx += 1;
                break;
            }
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// ============================================================================
// 数组指针函数
// ============================================================================

pub fn endFn(_: *VM, args: []const Value) !Value {
    const arr_val = args[0];
    if (arr_val.getTag() != .array) return Value.initBool(false);

    const arr = arr_val.getAsArray().data;
    if (arr.count() == 0) return Value.initBool(false);

    var iter = arr.getElements().iterator();
    var last: ?Value = null;
    while (iter.next()) |entry| {
        last = entry.value_ptr.*;
    }

    return if (last) |v| v else Value.initBool(false);
}

pub fn resetFn(_: *VM, args: []const Value) !Value {
    const arr_val = args[0];
    if (arr_val.getTag() != .array) return Value.initBool(false);

    const arr = arr_val.getAsArray().data;
    if (arr.count() == 0) return Value.initBool(false);

    var iter = arr.getElements().iterator();
    if (iter.next()) |entry| {
        return entry.value_ptr.*;
    }

    return Value.initBool(false);
}

pub fn currentFn(vm: *VM, args: []const Value) !Value {
    return resetFn(vm, args);
}

pub fn keyFn(vm: *VM, args: []const Value) !Value {
    const arr_val = args[0];
    if (arr_val.getTag() != .array) return Value.initNull();

    const arr = arr_val.getAsArray().data;
    if (arr.count() == 0) return Value.initNull();

    var iter = arr.getElements().iterator();
    if (iter.next()) |entry| {
        return switch (entry.key_ptr.*) {
            .integer => |i| Value.initInt(i),
            .string => |s| Value.initString(vm.allocator, s.data),
        };
    }

    return Value.initNull();
}

pub fn nextFn(vm: *VM, args: []const Value) !Value {
    return resetFn(vm, args);
}

pub fn prevFn(vm: *VM, args: []const Value) !Value {
    return resetFn(vm, args);
}

// ============================================================================
// 数组操作函数
// ============================================================================

pub fn arraySpliceFn(vm: *VM, args: []const Value) !Value {
    const input_array = args[0];
    const offset = args[1].asInt();

    if (input_array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_splice() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const length = if (args.len > 2) args[2].asInt() else null;
    const replacement = if (args.len > 3) args[3] else null;

    const arr = input_array.getAsArray().data;
    const arr_count = @as(i64, @intCast(arr.count()));

    // Create result array (removed elements)
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    errdefer result.release(vm.allocator);

    const result_arr = result.getAsArray().data;

    // Calculate actual start and end
    const start = if (offset < 0) arr_count + offset else offset;
    const end = if (length) |l| start + l else arr_count;

    // Copy removed elements to result
    var idx: i64 = 0;
    var result_idx: i64 = 0;
    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;
        if (idx >= start and idx < end) {
            const value_copy = value.retain();
            result_arr.set(vm.allocator, ArrayKey{ .integer = result_idx }, value_copy) catch {};
            result_idx += 1;
        }
        idx += 1;
    }

    // Now actually modify the original array
    // Remove the elements in the specified range
    if (start >= 0 and start < arr_count) {
        const actual_end = if (end > arr_count) arr_count else end;
        _ = arr.removeRange(vm.allocator, start, actual_end);

        // Insert replacement elements if provided
        if (replacement) |rep| {
            if (rep.getTag() == .array) {
                const rep_arr = rep.getAsArray().data;
                var rep_iter = rep_arr.getElements().iterator();
                var insert_idx = start;
                while (rep_iter.next()) |entry| {
                    const rep_value = entry.value_ptr.*;
                    try arr.insertAt(vm.allocator, insert_idx, rep_value.retain());
                    insert_idx += 1;
                }
            }
        }
    }

    return result;
}

pub fn arrayWalkFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_walk() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const userdata = if (args.len > 2) args[2] else null;

    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const key_value = switch (key) {
            .integer => Value.initInt(key.integer),
            .string => Value.initStringWithManager(&vm.memory_manager, key.string.data) catch Value.initNull(),
        };

        // Build callback arguments
        var callback_args = try std.ArrayList(Value).initCapacity(vm.allocator, 3);
        defer callback_args.deinit(vm.allocator);
        try callback_args.append(vm.allocator, value.retain());
        try callback_args.append(vm.allocator, key_value);
        if (userdata) |ud| {
            try callback_args.append(vm.allocator, ud.retain());
        }

        const result_value = switch (callback.getTag()) {
            .native_function => blk: {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
                break :blk try function(vm, callback_args.items);
            },
            .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, callback_args.items),
            .closure => try vm.callClosure(callback.getAsClosure().data, callback_args.items),
            .arrow_function => try vm.callArrowFunction(callback.getAsArrowFunc().data, callback_args.items),
            else => {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_walk() expects parameter 2 to be a valid callback", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidArgumentType;
            },
        };
        _ = result_value; // Ignore callback return value
    }

    return Value.initBool(true);
}

pub fn arrayChunkFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const size = args[1];
    const preserve_keys = if (args.len > 2) args[2].asBool() else false;

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_chunk() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const chunk_size = @as(usize, @intCast(size.asInt()));
    if (chunk_size < 1) {
        const exception = try ExceptionFactory.createValueError(vm.allocator, "array_chunk() size parameter must be positive", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const count = arr.count();

    // Pre-allocate temp ArrayList with exact size
    var temp = std.ArrayListUnmanaged(struct { key: ArrayKey, value: Value }){ .items = &.{}, .capacity = 0 };
    try temp.ensureTotalCapacity(vm.allocator, count);
    defer temp.deinit(vm.allocator);

    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        temp.appendAssumeCapacity(.{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    var chunk_idx: i64 = 0;
    var chunk_array: ?*PHPArray = null;
    var element_idx: usize = 0;

    for (temp.items) |item| {
        if (chunk_array == null or element_idx >= chunk_size) {
            // Create a new chunk array
            const new_chunk = try vm.allocator.create(PHPArray);
            errdefer vm.allocator.destroy(new_chunk);
            new_chunk.* = PHPArray.init(vm.allocator);

            // If there's a previous chunk, add it to result
            if (chunk_array) |prev_chunk| {
                const chunk_str = try std.fmt.allocPrint(vm.allocator, "{d}", .{chunk_idx});
                const chunk_key = try PHPString.init(vm.allocator, chunk_str);

                const chunk_box = try vm.allocator.create(types.gc.Box(*PHPArray));
                chunk_box.* = .{ .ref_count = 1, .gc_info = .{}, .data = prev_chunk };

                try result_array.set(vm.allocator, .{ .string = chunk_key }, Value.fromBox(chunk_box, Value.TYPE_ARRAY));
                chunk_idx += 1;
            }

            chunk_array = new_chunk;
            element_idx = 0;
        }

        const current_chunk = chunk_array orelse continue;

        if (preserve_keys) {
            try current_chunk.set(vm.allocator, item.key, item.value);
        } else {
            const int_key: i64 = @as(i64, @intCast(element_idx));
            try current_chunk.set(vm.allocator, .{ .integer = int_key }, item.value);
        }
        element_idx += 1;
    }

    // Add the last chunk
    if (chunk_array) |last_chunk| {
        const chunk_str = try std.fmt.allocPrint(vm.allocator, "{d}", .{chunk_idx});
        const chunk_key = try PHPString.init(vm.allocator, chunk_str);

        const chunk_box = try vm.allocator.create(types.gc.Box(*PHPArray));
        chunk_box.* = .{ .ref_count = 1, .gc_info = .{}, .data = last_chunk };

        try result_array.set(vm.allocator, .{ .string = chunk_key }, Value.fromBox(chunk_box, Value.TYPE_ARRAY));
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayPadFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const pad_size = args[1];
    const pad_value = args[2];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_pad() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const count = arr.getElements().count();
    const target_size = @as(usize, @intCast(pad_size.asInt()));

    if (target_size < count) {
        // No padding needed, just return a copy of the array
        const result = try vm.allocator.create(PHPArray);
        errdefer vm.allocator.destroy(result);
        result.* = PHPArray.init(vm.allocator);

        // Pre-allocate capacity
        try result.getElements().ensureTotalCapacity(vm.allocator, count);

        var iter = arr.getElements().iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            switch (key) {
                .integer => {
                    result.getElements().putAssumeCapacity(.{ .integer = key.integer }, value.retain());
                },
                .string => {
                    const str_key = try PHPString.init(vm.allocator, key.string.data);
                    result.getElements().putAssumeCapacity(.{ .string = str_key }, value.retain());
                },
            }
        }

        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    const pad_needed = target_size - count;
    const before_pad = if (pad_size.asInt() < 0) @as(usize, @intCast(-pad_size.asInt())) else 0;
    const after_pad = pad_needed - before_pad;

    // Pre-allocate capacity for all elements
    try result.getElements().ensureTotalCapacity(vm.allocator, target_size);

    // Add before padding
    var i: usize = 0;
    while (i < before_pad) : (i += 1) {
        const int_key: i64 = @as(i64, @intCast(-@as(i64, @intCast(i + 1))));
        result.getElements().putAssumeCapacity(.{ .integer = int_key }, pad_value.retain());
    }

    // Copy original array
    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        switch (key) {
            .integer => {
                result.getElements().putAssumeCapacity(.{ .integer = key.integer }, value);
            },
            .string => {
                const str_key = try PHPString.init(vm.allocator, key.string.data);
                result.getElements().putAssumeCapacity(.{ .string = str_key }, value);
            },
        }
    }

    // Add after padding
    i = 0;
    while (i < after_pad) : (i += 1) {
        const int_key: i64 = @as(i64, @intCast(count + i));
        result.getElements().putAssumeCapacity(.{ .integer = int_key }, pad_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayKeyFirstFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_key_first() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    if (arr.getElements().count() == 0) {
        return Value.initBool(false);
    }

    if (arr.getElements().count() == 0) {
        return Value.initBool(false);
    }

    var iter = arr.getElements().iterator();
    const first_entry = iter.next() orelse return Value.initBool(false);
    const first_key = first_entry.key_ptr.*;

    return switch (first_key) {
        .integer => Value.initInt(first_key.integer),
        .string => Value.initStringWithManager(&vm.memory_manager, first_key.string.data) catch Value.initNull(),
    };
}

pub fn arrayKeyLastFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_key_last() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    if (arr.getElements().count() == 0) {
        return Value.initBool(false);
    }

    var last_key: ArrayKey = undefined;
    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        last_key = entry.key_ptr.*;
    }

    return switch (last_key) {
        .integer => Value.initInt(last_key.integer),
        .string => Value.initStringWithManager(&vm.memory_manager, last_key.string.data) catch Value.initNull(),
    };
}

pub fn arrayFillKeysFn(vm: *VM, args: []const Value) !Value {
    const keys = args[0];
    const value = args[1];

    if (keys.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_fill_keys() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const keys_arr = keys.getAsArray().data;
    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    var iter = keys_arr.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const key_copy = switch (key) {
            .integer => ArrayKey{ .integer = key.integer },
            .string => blk: {
                const str_key = try PHPString.init(vm.allocator, key.string.data);
                break :blk ArrayKey{ .string = str_key };
            },
        };
        try result.set(vm.allocator, key_copy, value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayChangeKeyCaseFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const case_type = if (args.len > 1) args[1].asInt() else 0; // 0 = CASE_LOWER, 1 = CASE_UPPER

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_change_key_case() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const new_key = switch (key) {
            .integer => key, // Integers stay the same
            .string => blk: {
                const new_data = try vm.allocator.alloc(u8, key.string.data.len);
                @memcpy(new_data, key.string.data);
                for (new_data) |*c| {
                    if (case_type == 0) {
                        c.* = std.ascii.toLower(c.*);
                    } else {
                        c.* = std.ascii.toUpper(c.*);
                    }
                }
                const str_key = try PHPString.init(vm.allocator, new_data);
                break :blk ArrayKey{ .string = str_key };
            },
        };
        try result.set(vm.allocator, new_key, value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

pub fn arrayCountValuesFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_count_values() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;

        // Use value as key (integers and strings only)
        const key: ArrayKey = switch (value.getTag()) {
            .integer => .{ .integer = value.asInt() },
            .string => .{ .string = value.getAsString().data },
            else => continue,
        };

        // Check if key already exists and increment count
        const existing = result.getElements().get(key);
        if (existing) |count_val| {
            try result.set(vm.allocator, key, Value.initInt(count_val.asInt() + 1));
        } else {
            try result.set(vm.allocator, key, Value.initInt(1));
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// ============================================================================
// isset 函数
// ============================================================================

pub fn issetFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    for (args) |arg| {
        if (arg.getTag() == .null) return Value.initBool(false);
    }
    return Value.initBool(true);
}

// ============================================================================
// 单元测试
// ============================================================================

test "stdlib_array: compareValues integer comparison" {
    const a = Value.initInt(1);
    const b = Value.initInt(2);
    const c = Value.initInt(1);
    try std.testing.expectEqual(@as(i8, -1), compareValues(a, b));
    try std.testing.expectEqual(@as(i8, 1), compareValues(b, a));
    try std.testing.expectEqual(@as(i8, 0), compareValues(a, c));
}

test "stdlib_array: compareValues float comparison" {
    const a = Value.initFloat(1.5);
    const b = Value.initFloat(2.5);
    const c = Value.initFloat(1.5);
    try std.testing.expectEqual(@as(i8, -1), compareValues(a, b));
    try std.testing.expectEqual(@as(i8, 1), compareValues(b, a));
    try std.testing.expectEqual(@as(i8, 0), compareValues(a, c));
}

test "stdlib_array: compareValues mixed int/float" {
    const a = Value.initInt(1);
    const b = Value.initFloat(2.0);
    try std.testing.expectEqual(@as(i8, -1), compareValues(a, b));
    try std.testing.expectEqual(@as(i8, 1), compareValues(b, a));
}

test "stdlib_array: compareValues non-numeric types default to 0" {
    const a = Value.initNull();
    const b = Value.initNull();
    try std.testing.expectEqual(@as(i8, 0), compareValues(a, b));
}

test "stdlib_array: compareArrayKeys integer keys" {
    const a = ArrayKey{ .integer = 1 };
    const b = ArrayKey{ .integer = 2 };
    const c = ArrayKey{ .integer = 1 };
    try std.testing.expectEqual(@as(i8, -1), compareArrayKeys(a, b));
    try std.testing.expectEqual(@as(i8, 1), compareArrayKeys(b, a));
    try std.testing.expectEqual(@as(i8, 0), compareArrayKeys(a, c));
}

test "stdlib_array: compareArrayKeys integer vs string" {
    const int_key = ArrayKey{ .integer = 1 };
    const allocator = std.testing.allocator;
    const str = try PHPString.init(allocator, "abc");
    defer str.release(allocator);
    const str_key = ArrayKey{ .string = str };
    // Integer keys always sort before string keys
    try std.testing.expectEqual(@as(i8, -1), compareArrayKeys(int_key, str_key));
    try std.testing.expectEqual(@as(i8, 1), compareArrayKeys(str_key, int_key));
}

test "stdlib_array: compareArrayKeys string keys" {
    const allocator = std.testing.allocator;
    const str_a = try PHPString.init(allocator, "abc");
    defer str_a.release(allocator);
    const str_b = try PHPString.init(allocator, "def");
    defer str_b.release(allocator);
    const str_c = try PHPString.init(allocator, "abc");
    defer str_c.release(allocator);

    const a = ArrayKey{ .string = str_a };
    const b = ArrayKey{ .string = str_b };
    const c = ArrayKey{ .string = str_c };
    try std.testing.expectEqual(@as(i8, -1), compareArrayKeys(a, b));
    try std.testing.expectEqual(@as(i8, 1), compareArrayKeys(b, a));
    try std.testing.expectEqual(@as(i8, 0), compareArrayKeys(a, c));
}

test "stdlib_array: ArraySortItem struct" {
    const item = ArraySortItem{
        .key = ArrayKey{ .integer = 42 },
        .value = Value.initInt(100),
    };
    try std.testing.expectEqual(@as(i64, 42), item.key.integer);
}

test "stdlib_array: handler functions exist" {
    _ = &arrayMapFn;
    _ = &arrayFilterFn;
    _ = &arrayReduceFn;
    _ = &arrayMergeFn;
    _ = &arrayKeysFn;
    _ = &arrayValuesFn;
    _ = &arrayPushFn;
    _ = &arrayPopFn;
    _ = &arrayShiftFn;
    _ = &arrayUnshiftFn;
    _ = &inArrayFn;
    _ = &arraySearchFn;
    _ = &countFn;
    _ = &sortFn;
    _ = &rsortFn;
    _ = &asortFn;
    _ = &arsortFn;
    _ = &ksortFn;
    _ = &krsortFn;
    _ = &arraySumFn;
    _ = &arrayProductFn;
    _ = &arrayReverseFn;
    _ = &arrayUniqueFn;
    _ = &arrayFlipFn;
    _ = &arraySliceFn;
    _ = &arrayColumnFn;
    _ = &rangeFunction;
    _ = &arrayFillFn;
    _ = &arrayKeyExistsFn;
    _ = &issetFn;
}
