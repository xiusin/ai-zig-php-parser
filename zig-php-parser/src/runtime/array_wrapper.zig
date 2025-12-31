const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;

/// ArrayWrapper - 数组方法封装
/// 提供完整的数组操作方法，通过 -> 语法调用
pub const ArrayWrapper = struct {
    allocator: std.mem.Allocator,
    array: *PHPArray,

    pub fn init(allocator: std.mem.Allocator) !ArrayWrapper {
        const array = try allocator.create(PHPArray);
        array.* = PHPArray.init(allocator);
        return ArrayWrapper{
            .allocator = allocator,
            .array = array,
        };
    }

    pub fn initFromPHPArray(allocator: std.mem.Allocator, array: *PHPArray) ArrayWrapper {
        return ArrayWrapper{
            .allocator = allocator,
            .array = array,
        };
    }

    pub fn deinit(self: *ArrayWrapper) void {
        self.array.deinit(self.allocator);
        self.allocator.destroy(self.array);
    }

    pub fn length(self: *const ArrayWrapper) usize {
        return self.array.count();
    }

    pub fn get(self: *ArrayWrapper, index: i64) ?Value {
        return self.array.get(ArrayKey{ .integer = index });
    }

    pub fn set(self: *ArrayWrapper, index: i64, value: Value) !void {
        try self.array.set(self.allocator, ArrayKey{ .integer = index }, value);
    }

    pub fn push(self: *ArrayWrapper, value: Value) !*ArrayWrapper {
        try self.array.push(self.allocator, value);
        return self;
    }

    pub fn pop(self: *ArrayWrapper) ?Value {
        const count = self.array.count();
        if (count == 0) return null;

        const last_key = ArrayKey{ .integer = @as(i64, @intCast(count - 1)) };
        const value = self.array.get(last_key);
        if (value != null) {
            _ = self.array.elements.orderedRemove(last_key);
        }
        return value;
    }

    pub fn unshift(self: *ArrayWrapper, value: Value) !*ArrayWrapper {
        var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, false).initContext(self.allocator, .{});

        try new_elements.put(ArrayKey{ .integer = 0 }, value);
        _ = value.retain();

        var iter = self.array.elements.iterator();
        var new_index: i64 = 1;
        while (iter.next()) |entry| {
            try new_elements.put(ArrayKey{ .integer = new_index }, entry.value_ptr.*);
            new_index += 1;
        }

        self.array.elements.deinit();
        self.array.elements = new_elements;
        self.array.next_index = new_index;

        return self;
    }

    pub fn shift(self: *ArrayWrapper) ?Value {
        if (self.array.count() == 0) return null;

        // 找到最小的整数键
        var min_key: ?i64 = null;
        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            if (entry.key_ptr.* == .integer) {
                const key = entry.key_ptr.*.integer;
                if (min_key == null or key < min_key.?) {
                    min_key = key;
                }
            }
        }

        if (min_key == null) return null;

        const first_key = ArrayKey{ .integer = min_key.? };
        const value = self.array.get(first_key);

        if (value != null) {
            // 创建新的数组，所有键都向前移动一位
            var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, false).initContext(self.allocator, .{});

            iter = self.array.elements.iterator();
            while (iter.next()) |entry| {
                if (entry.key_ptr.* == .integer) {
                    const key = entry.key_ptr.*.integer;
                    if (key > min_key.?) {
                        // 键大于最小键时，向前移动一位
                        const new_key = ArrayKey{ .integer = key - 1 };
                        try new_elements.put(new_key, entry.value_ptr.*);
                    }
                    // 跳过最小键（被移除）
                } else {
                    // 字符串键保持不变
                    try new_elements.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }

            self.array.elements.deinit();
            self.array.elements = new_elements;
            // 更新 next_index（如果是数字索引的数组）
            if (min_key.? == 0) {
                self.array.next_index = self.array.count();
            }
        }

        return value;
    }

    pub fn merge(self: *ArrayWrapper, other: *PHPArray) !*ArrayWrapper {
        var iter = other.elements.iterator();
        while (iter.next()) |entry| {
            try self.array.push(self.allocator, entry.value_ptr.*);
        }
        return self;
    }

    pub fn reverse(self: *ArrayWrapper) !*ArrayWrapper {
        const element_count = self.array.count();
        if (element_count <= 1) return self;

        var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, false).initContext(self.allocator, .{});

        var temp_values = try self.allocator.alloc(Value, element_count);
        defer self.allocator.free(temp_values);

        var iter = self.array.elements.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            temp_values[i] = entry.value_ptr.*;
        }

        i = 0;
        while (i < element_count) : (i += 1) {
            const new_key = ArrayKey{ .integer = @as(i64, @intCast(i)) };
            try new_elements.put(new_key, temp_values[element_count - 1 - i]);
        }

        self.array.elements.deinit();
        self.array.elements = new_elements;

        return self;
    }

    pub fn keys(self: *ArrayWrapper) !*PHPArray {
        const result = try self.allocator.create(PHPArray);
        result.* = PHPArray.init(self.allocator);

        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            const key_value = switch (entry.key_ptr.*) {
                .integer => |i| Value.initInt(i),
                .string => |s| blk: {
                    const str_copy = try types.PHPString.init(self.allocator, s.data);
                    break :blk try Value.initString(self.allocator, str_copy);
                },
            };
            try result.push(self.allocator, key_value);
        }

        return result;
    }

    pub fn values(self: *ArrayWrapper) !*PHPArray {
        const result = try self.allocator.create(PHPArray);
        result.* = PHPArray.init(self.allocator);

        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            try result.push(self.allocator, entry.value_ptr.*);
        }

        return result;
    }

    pub fn filter(self: *ArrayWrapper, callback: Value) !*PHPArray {
        const result = try self.allocator.create(PHPArray);
        result.* = PHPArray.init(self.allocator);

        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            _ = callback;
            const keep = entry.value_ptr.*.toBool();
            if (keep) {
                try result.push(self.allocator, entry.value_ptr.*);
            }
        }

        return result;
    }

    pub fn map(self: *ArrayWrapper, callback: Value) !*PHPArray {
        const result = try self.allocator.create(PHPArray);
        result.* = PHPArray.init(self.allocator);

        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            _ = callback;
            try result.push(self.allocator, entry.value_ptr.*);
        }

        return result;
    }

    pub fn count(self: *const ArrayWrapper) usize {
        return self.array.count();
    }

    pub fn isEmpty(self: *const ArrayWrapper) bool {
        return self.array.count() == 0;
    }

    pub fn toValue(self: *ArrayWrapper) !Value {
        const box = try self.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = self.array,
        };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }
};
