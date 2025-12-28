const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const gc = types.gc;

/// ArrayWrapper - 包装数组变量，提供链式方法调用
/// 类似JavaScript的Array对象，支持流畅的API设计
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

    /// 获取数组长度
    pub fn length(self: *const ArrayWrapper) usize {
        return self.array.count();
    }

    /// 获取指定索引的元素
    pub fn get(self: *ArrayWrapper, index: i64) ?Value {
        return self.array.get(ArrayKey{ .integer = index });
    }

    /// 设置指定索引的元素
    pub fn set(self: *ArrayWrapper, index: i64, value: Value) !void {
        try self.array.set(self.allocator, ArrayKey{ .integer = index }, value);
    }

    /// 追加元素
    pub fn push(self: *ArrayWrapper, value: Value) !*ArrayWrapper {
        try self.array.push(self.allocator, value);
        return self;
    }

    /// 弹出最后一个元素
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

    /// 在开头插入元素
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

    /// 移除第一个元素
    pub fn shift(self: *ArrayWrapper) ?Value {
        if (self.array.count() == 0) return null;

        const first_key = ArrayKey{ .integer = 0 };
        const value = self.array.get(first_key);

        if (value != null) {
            var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, false).initContext(self.allocator, .{});

            var iter = self.array.elements.iterator();
            var new_index: i64 = 0;
            var skip_first = true;
            while (iter.next()) |entry| {
                if (skip_first) {
                    skip_first = false;
                    continue;
                }
                new_elements.put(ArrayKey{ .integer = new_index }, entry.value_ptr.*) catch {};
                new_index += 1;
            }

            self.array.elements.deinit();
            self.array.elements = new_elements;
            self.array.next_index = new_index;
        }

        return value;
    }

    /// 过滤数组（使用回调函数）
    pub fn filter(self: *ArrayWrapper, predicate: *const fn (Value) bool) !ArrayWrapper {
        var result = try ArrayWrapper.init(self.allocator);

        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            if (predicate(entry.value_ptr.*)) {
                try result.array.push(self.allocator, entry.value_ptr.*);
            }
        }

        return result;
    }

    /// 映射数组（使用回调函数）
    pub fn map(self: *ArrayWrapper, transform: *const fn (Value) Value) !ArrayWrapper {
        var result = try ArrayWrapper.init(self.allocator);

        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            const new_value = transform(entry.value_ptr.*);
            try result.array.push(self.allocator, new_value);
        }

        return result;
    }

    /// 合并数组
    pub fn merge(self: *ArrayWrapper, other: *ArrayWrapper) !*ArrayWrapper {
        var iter = other.array.elements.iterator();
        while (iter.next()) |entry| {
            try self.array.push(self.allocator, entry.value_ptr.*);
        }
        return self;
    }

    /// 反转数组
    pub fn reverse(self: *ArrayWrapper) !ArrayWrapper {
        var result = try ArrayWrapper.init(self.allocator);

        const count = self.array.count();
        if (count == 0) return result;

        var i: i64 = @as(i64, @intCast(count)) - 1;
        while (i >= 0) : (i -= 1) {
            if (self.array.get(ArrayKey{ .integer = i })) |value| {
                try result.array.push(self.allocator, value);
            }
        }

        return result;
    }

    /// 切片
    pub fn slice(self: *ArrayWrapper, start: i64, end: ?i64) !ArrayWrapper {
        var result = try ArrayWrapper.init(self.allocator);

        const count: i64 = @intCast(self.array.count());
        const actual_start: i64 = if (start < 0) @max(0, count + start) else @min(start, count);
        const actual_end: i64 = if (end) |e| blk: {
            if (e < 0) break :blk @max(0, count + e);
            break :blk @min(e, count);
        } else count;

        var i = actual_start;
        while (i < actual_end) : (i += 1) {
            if (self.array.get(ArrayKey{ .integer = i })) |value| {
                try result.array.push(self.allocator, value);
            }
        }

        return result;
    }

    /// 查找元素索引
    pub fn indexOf(self: *ArrayWrapper, value: Value) i64 {
        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            if (valuesEqual(entry.value_ptr.*, value)) {
                switch (entry.key_ptr.*) {
                    .integer => |idx| return idx,
                    else => {},
                }
            }
        }
        return -1;
    }

    /// 是否包含元素
    pub fn contains(self: *ArrayWrapper, value: Value) bool {
        return self.indexOf(value) >= 0;
    }

    /// 连接为字符串
    pub fn join(self: *ArrayWrapper, separator: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var first = true;
        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            if (!first) {
                try result.appendSlice(separator);
            }
            first = false;

            switch (entry.value_ptr.*.tag) {
                .string => {
                    try result.appendSlice(entry.value_ptr.*.data.string.data.data);
                },
                .integer => {
                    const str = try std.fmt.allocPrint(self.allocator, "{d}", .{entry.value_ptr.*.data.integer});
                    defer self.allocator.free(str);
                    try result.appendSlice(str);
                },
                .float => {
                    const str = try std.fmt.allocPrint(self.allocator, "{d}", .{entry.value_ptr.*.data.float});
                    defer self.allocator.free(str);
                    try result.appendSlice(str);
                },
                else => {},
            }
        }

        return result.toOwnedSlice();
    }

    /// 获取所有键
    pub fn keys(self: *ArrayWrapper) ![]ArrayKey {
        return self.array.keys(self.allocator);
    }

    /// 获取所有值
    pub fn values(self: *ArrayWrapper) ![]Value {
        return self.array.values(self.allocator);
    }

    /// 是否为空
    pub fn isEmpty(self: *const ArrayWrapper) bool {
        return self.array.count() == 0;
    }

    /// 清空数组
    pub fn clear(self: *ArrayWrapper) void {
        var iter = self.array.elements.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.release(self.allocator);
        }
        self.array.elements.clearRetainingCapacity();
        self.array.next_index = 0;
    }

    /// 转换为Value
    pub fn toValue(self: *ArrayWrapper, memory_manager: *gc.MemoryManager) !Value {
        _ = memory_manager;
        const box = try self.allocator.create(gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = self.array,
        };
        return Value{ .tag = .array, .data = .{ .array = box } };
    }
};

/// 比较两个Value是否相等
fn valuesEqual(a: Value, b: Value) bool {
    if (a.tag != b.tag) return false;

    return switch (a.tag) {
        .null => true,
        .boolean => a.data.boolean == b.data.boolean,
        .integer => a.data.integer == b.data.integer,
        .float => a.data.float == b.data.float,
        .string => std.mem.eql(u8, a.data.string.data.data, b.data.string.data.data),
        else => false,
    };
}

test "ArrayWrapper basic operations" {
    const allocator = std.testing.allocator;

    var wrapper = try ArrayWrapper.init(allocator);
    defer wrapper.deinit();

    try std.testing.expectEqual(@as(usize, 0), wrapper.length());
    try std.testing.expect(wrapper.isEmpty());

    _ = try wrapper.push(Value.initInt(1));
    _ = try wrapper.push(Value.initInt(2));
    _ = try wrapper.push(Value.initInt(3));

    try std.testing.expectEqual(@as(usize, 3), wrapper.length());
    try std.testing.expect(!wrapper.isEmpty());
}

test "ArrayWrapper slice" {
    const allocator = std.testing.allocator;

    var wrapper = try ArrayWrapper.init(allocator);
    defer wrapper.deinit();

    _ = try wrapper.push(Value.initInt(1));
    _ = try wrapper.push(Value.initInt(2));
    _ = try wrapper.push(Value.initInt(3));
    _ = try wrapper.push(Value.initInt(4));
    _ = try wrapper.push(Value.initInt(5));

    var sliced = try wrapper.slice(1, 4);
    defer sliced.deinit();

    try std.testing.expectEqual(@as(usize, 3), sliced.length());
}
