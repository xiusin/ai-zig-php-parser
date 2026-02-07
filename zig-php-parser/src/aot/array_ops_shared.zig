const std = @import("std");

pub fn KV(comptime ArrayKey: type, comptime Value: type) type {
    return struct { key: ArrayKey, value: Value };
}

fn initMap(comptime Map: type, allocator: std.mem.Allocator) Map {
    if (@hasDecl(Map, "initContext")) {
        return Map.initContext(allocator, .{});
    }
    return Map.init(allocator);
}

pub fn unshift(
    comptime ArrayKey: type,
    comptime Value: type,
    comptime Map: type,
    allocator: std.mem.Allocator,
    elements: *Map,
    next_index: *i64,
    values: []const Value,
) !void {
    const old_count = elements.count();
    var items = try allocator.alloc(KV(ArrayKey, Value), old_count);
    defer allocator.free(items);

    var it = elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) {
        items[idx] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
    }

    var new_elements = initMap(Map, allocator);
    var next_int_key: i64 = 0;

    for (values) |v| {
        _ = v.retain();
        try new_elements.put(.{ .integer = next_int_key }, v);
        next_int_key += 1;
    }

    for (items) |kv| {
        switch (kv.key) {
            .integer => {
                try new_elements.put(.{ .integer = next_int_key }, kv.value);
                next_int_key += 1;
            },
            .string => {
                try new_elements.put(kv.key, kv.value);
            },
        }
    }

    elements.deinit();
    elements.* = new_elements;
    next_index.* = next_int_key;
}

pub fn shift(
    comptime ArrayKey: type,
    comptime Value: type,
    comptime Map: type,
    allocator: std.mem.Allocator,
    elements: *Map,
    next_index: *i64,
) ?Value {
    if (elements.count() == 0) return null;

    var it0 = elements.iterator();
    const first = it0.next() orelse return null;
    const first_key = first.key_ptr.*;
    const first_value = first.value_ptr.*;

    _ = elements.orderedRemove(first_key);
    if (first_key == .string) {
        first_key.string.release(allocator);
    }

    const remaining_count = elements.count();
    var items = allocator.alloc(KV(ArrayKey, Value), remaining_count) catch return first_value;
    defer allocator.free(items);

    var it = elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) {
        items[idx] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
    }

    var new_elements = initMap(Map, allocator);
    var next_int_key: i64 = 0;

    for (items) |kv| {
        switch (kv.key) {
            .integer => {
                new_elements.put(.{ .integer = next_int_key }, kv.value) catch {};
                next_int_key += 1;
            },
            .string => {
                new_elements.put(kv.key, kv.value) catch {};
            },
        }
    }

    elements.deinit();
    elements.* = new_elements;
    next_index.* = next_int_key;

    return first_value;
}

pub fn pop(
    comptime ArrayKey: type,
    comptime Value: type,
    comptime Map: type,
    allocator: std.mem.Allocator,
    elements: *Map,
    next_index: *i64,
) ?Value {
    if (elements.count() == 0) return null;

    var last_key: ?ArrayKey = null;
    var last_value: ?Value = null;
    var it = elements.iterator();
    while (it.next()) |entry| {
        last_key = entry.key_ptr.*;
        last_value = entry.value_ptr.*;
    }

    if (last_key == null or last_value == null) return null;
    const key = last_key.?;
    const val = last_value.?;

    _ = elements.orderedRemove(key);
    if (key == .string) {
        key.string.release(allocator);
    }

    var max_int: i64 = -1;
    it = elements.iterator();
    while (it.next()) |entry| {
        if (entry.key_ptr.* == .integer) {
            const i = entry.key_ptr.*.integer;
            if (i > max_int) max_int = i;
        }
    }
    next_index.* = max_int + 1;

    return val;
}
