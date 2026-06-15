const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

// ============================================================================
// 数组类型
// ============================================================================

/// 数组键类型
pub const ArrayKey = union(enum) {
    integer: i64,
    string: *PHPString,

    pub fn hash(self: ArrayKey) u64 {
        return switch (self) {
            .integer => |i| std.hash.Wyhash.hash(0, std.mem.asBytes(&i)),
            .string => |s| std.hash.Wyhash.hash(0, s.data),
        };
    }

    pub fn eql(self: ArrayKey, other: ArrayKey) bool {
        return switch (self) {
            .integer => |a| switch (other) {
                .integer => |b| a == b,
                else => false,
            },
            .string => |a| switch (other) {
                .string => |b| std.mem.eql(u8, a.data, b.data),
                else => false,
            },
        };
    }
};

fn parsePhpArrayIntKey(str: []const u8) ?i64 {
    if (str.len == 0) return null;
    if (str[0] == '+') return null;

    var start: usize = 0;
    var negative = false;
    if (str[0] == '-') {
        negative = true;
        start = 1;
        if (str.len == 1) return null;
    }

    const digits = str[start..];
    if (digits.len == 0) return null;
    if (digits[0] == '0' and digits.len > 1) return null;

    for (digits) |c| {
        if (!std.ascii.isDigit(c)) return null;
    }

    const parsed = std.fmt.parseInt(i64, digits, 10) catch return null;
    return if (negative) -parsed else parsed;
}

fn normalizeArrayKeyFromValue(key: Value) ArrayKey {
    if (key.isString()) {
        if (parsePhpArrayIntKey(key.asString().data)) |i| {
            return ArrayKey{ .integer = i };
        }
        return ArrayKey{ .string = key.asString() };
    }
    return ArrayKey{ .integer = key.toInt() };
}

/// PHP数组类型
/// 支持整数键和字符串键的混合数组
pub const PHPArray = struct {
    elements: Elements,
    next_index: i64,
    ref_count: usize,
    gc_info: GCInfo,
    has_active_refs: bool = false, // 是否有活跃的引用
    ref_lock_count: u32 = 0, // 引用锁计数

    pub const ArrayContext = struct {
        pub fn hash(_: ArrayContext, key: ArrayKey) u32 {
            return @truncate(key.hash());
        }

        pub fn eql(_: ArrayContext, a: ArrayKey, b: ArrayKey, _: usize) bool {
            return a.eql(b);
        }
    };

    pub const Elements = struct {
        allocator: Allocator,
        parent: ?*PHPArray = null, // 父数组引用
        packed_values: std.ArrayListUnmanaged(Value) = .{ .items = &.{}, .capacity = 0 },
        mixed: ?std.ArrayHashMapUnmanaged(ArrayKey, Value, ArrayContext, true) = null,

        pub const Entry = struct { key_ptr: *const ArrayKey, value_ptr: *const Value };

        pub const Iterator = struct {
            elements: *const Elements,
            index: usize = 0,
            key: ArrayKey = .{ .integer = 0 },
            value: Value = Value.initNull(),
            mixed_it: ?std.ArrayHashMapUnmanaged(ArrayKey, Value, ArrayContext, true).Iterator = null,

            pub fn next(self: *Iterator) ?Entry {
                if (self.mixed_it) |*it| {
                    const e = it.next() orelse return null;
                    return .{ .key_ptr = e.key_ptr, .value_ptr = e.value_ptr };
                }
                if (self.index >= self.elements.packed_values.items.len) return null;
                self.key = .{ .integer = @intCast(self.index) };
                // 返回指向数组中实际元素的指针，而不是临时字段
                const elem_ptr = &self.elements.packed_values.items[self.index];
                self.index += 1;
                return .{ .key_ptr = &self.key, .value_ptr = elem_ptr };
            }
        };

        pub fn init(allocator: Allocator) Elements {
            return .{ .allocator = allocator };
        }

        pub fn initMixed(allocator: Allocator, map: std.ArrayHashMapUnmanaged(ArrayKey, Value, ArrayContext, true)) Elements {
            return .{ .allocator = allocator, .packed_values = .{ .items = &.{}, .capacity = 0 }, .mixed = map };
        }

        pub fn count(self: *const Elements) usize {
            if (self.mixed) |*m| return m.count();
            return self.packed_values.items.len;
        }

        /// 检查是否包含字符串键（关联数组）
        pub fn hasStringKeys(self: *const Elements) bool {
            const m = self.mixed orelse return false;
            const keys = m.entries.items(.key);
            for (keys) |k| {
                if (k == .string) return true;
            }
            return false;
        }

        pub fn iterator(self: *const Elements) Iterator {
            if (self.mixed) |*m| {
                // 安全检查：检查entries的capacity
                if (m.entries.capacity > 10_000_000) {
                    // HashMap被破坏，返回空迭代器
                    return .{ .elements = self };
                }

                const mut_m = @constCast(m);
                return .{ .elements = self, .mixed_it = mut_m.iterator() };
            }
            return .{ .elements = self };
        }

        pub fn get(self: *const Elements, key: ArrayKey) ?Value {
            if (self.mixed) |*m| return m.get(key);
            if (key != .integer) return null;
            const i = key.integer;
            if (i < 0) return null;
            const idx: usize = @intCast(i);
            if (idx >= self.packed_values.items.len) return null;
            return self.packed_values.items[idx];
        }

        fn convertToMixed(self: *Elements) !void {
            if (self.mixed != null) return;
            var map = std.ArrayHashMapUnmanaged(ArrayKey, Value, ArrayContext, true){};
            for (self.packed_values.items, 0..) |v, idx| {
                const retained = v.retain();
                _ = retained;
                try map.put(self.allocator, .{ .integer = @intCast(idx) }, v);
            }
            self.packed_values.deinit(self.allocator);
            self.packed_values = .{ .items = &.{}, .capacity = 0 };
            self.mixed = map;
        }

        pub fn put(self: *Elements, key: ArrayKey, value: Value) !void {
            // 如果父数组有活跃引用，强制使用mixed模式避免重新分配
            if (self.parent) |parent| {
                if (parent.has_active_refs and self.mixed == null) {
                    try self.convertToMixed();
                }
            }

            if (self.mixed) |*m| {
                try m.put(self.allocator, key, value);
                return;
            }
            if (key == .integer) {
                const i = key.integer;
                if (i >= 0) {
                    const idx: usize = @intCast(i);
                    if (idx == self.packed_values.items.len) {
                        try self.packed_values.append(self.allocator, value);
                        return;
                    }
                    if (idx < self.packed_values.items.len) {
                        self.packed_values.items[idx] = value;
                        return;
                    }
                }
            }
            try self.convertToMixed();
            try self.mixed.?.put(self.allocator, key, value);
        }

        pub fn orderedRemove(self: *Elements, key: ArrayKey) bool {
            if (self.mixed) |*m| return m.orderedRemove(key);
            if (key != .integer) return false;
            const i = key.integer;
            if (i < 0) return false;
            const idx: usize = @intCast(i);
            if (idx >= self.packed_values.items.len) return false;
            _ = self.packed_values.orderedRemove(idx);
            return true;
        }

        pub fn remove(self: *Elements, key: ArrayKey) bool {
            return self.orderedRemove(key);
        }

        pub fn getPtr(self: *Elements, key: ArrayKey) ?*Value {
            if (self.mixed) |*m| return m.getPtr(key);
            if (key != .integer) return null;
            const i = key.integer;
            if (i < 0) return null;
            const idx: usize = @intCast(i);
            if (idx >= self.packed_values.items.len) return null;
            return &self.packed_values.items[idx];
        }

        pub fn deinit(self: *Elements) void {
            if (self.mixed) |*m| {
                m.deinit(self.allocator);
                self.mixed = null;
            }
            self.packed_values.deinit(self.allocator);
            self.packed_values = .{ .items = &.{}, .capacity = 0 };
        }
    };

    /// 创建新数组
    pub fn init(allocator: Allocator) !*PHPArray {
        const array = try allocPHPArray(allocator);
        array.elements = Elements.init(allocator);
        array.elements.parent = array; // 设置父引用
        array.next_index = 0;
        array.ref_count = 1;
        array.gc_info = .{};
        array.has_active_refs = false;
        array.ref_lock_count = 0;
        alloc_counters.php_array_objects += 1;
        alloc_counters.php_array_live_objects += 1;
        alloc_counters.php_array_peak_live_objects = @max(
            alloc_counters.php_array_peak_live_objects,
            alloc_counters.php_array_live_objects,
        );
        return array;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPArray) void {
        self.ref_count += 1;
    }

    /// 深拷贝数组（PHP 值语义：数组赋值时复制）
    /// 对嵌套数组递归复制；对象/字符串仅增加引用计数（PHP 中对象仍然按引用共享）
    pub fn cloneDeep(self: *PHPArray, allocator: Allocator) !*PHPArray {
        const new_arr = try PHPArray.init(allocator);
        new_arr.next_index = self.next_index;
        var iter = self.elements.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            // 递归克隆子数组；其他类型（字符串/对象/标量）仅 retain
            var new_val: Value = undefined;
            if (val.isArray() and !val.isRef()) {
                const sub = try val.asArray().cloneDeep(allocator);
                new_val = Value.initArray(sub);
            } else {
                new_val = val.retain();
            }
            // 若 key 为字符串，需要增加字符串的引用计数
            const new_key: ArrayKey = switch (key) {
                .string => |s| blk: {
                    s.retain();
                    break :blk .{ .string = s };
                },
                .integer => key,
            };
            try new_arr.elements.put(new_key, new_val);
        }
        return new_arr;
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPArray, allocator: Allocator) void {
        // 检测内存破坏
        if (self.ref_count > 1000000) {
            std.debug.print("ERROR: PHPArray corrupted! ref_count={d} (0x{x})\n", .{ self.ref_count, self.ref_count });
            return;
        }

        if (self.ref_count == 0) {
            std.debug.print("WARNING: PHPArray double free detected!\n", .{});
            return;
        }

        // 如果有活跃的迭代器引用，不允许释放
        if (self.ref_lock_count > 0) {
            // 迭代器还在使用，延迟释放
            return;
        }

        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit(allocator);
        } else if (!gc_in_progress) {
            gcBufferArray(self);
        }
    }

    /// 释放数组
    fn deinit(self: *PHPArray, allocator: Allocator) void {
        if (array_internal_pointers) |*m| {
            _ = m.remove(self);
        }
        var iter = self.elements.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.release(allocator);
            if (entry.key_ptr.* == .string) {
                entry.key_ptr.*.string.release(allocator);
            }
        }
        self.elements.deinit();
        if (alloc_counters.php_array_live_objects > 0) {
            alloc_counters.php_array_live_objects -= 1;
        }
        destroyPHPArray(self, allocator);
    }

    /// 获取元素
    pub fn get(self: *PHPArray, key: ArrayKey) ?Value {
        if (self.elements.get(key)) |v| {
            _ = v.retain();
            return v;
        }
        return null;
    }

    /// 获取元素指针（用于引用）
    pub fn getPtr(self: *PHPArray, key: ArrayKey) ?*Value {
        return self.elements.getPtr(key);
    }

    /// 获取元素（通过Value键）
    pub fn getByValue(self: *PHPArray, key: Value) ?Value {
        return self.get(normalizeArrayKeyFromValue(key));
    }

    /// 设置元素（通过Value键）
    pub fn setByValue(self: *PHPArray, allocator: Allocator, key: Value, value: Value) !void {
        try self.set(allocator, normalizeArrayKeyFromValue(key), value);
    }

    /// 设置元素
    pub fn set(self: *PHPArray, allocator: Allocator, key: ArrayKey, value: Value) !void {
        // 释放旧值
        if (self.elements.get(key)) |old_value| {
            old_value.release(allocator);
        }

        // 保留新值
        _ = value.retain();

        // 如果是字符串键，保留键
        if (key == .string) {
            key.string.retain();
        }

        // 更新next_index
        if (key == .integer and key.integer >= self.next_index) {
            self.next_index = key.integer + 1;
        }

        try self.elements.put(key, value);
    }

    /// 追加元素（使用下一个整数索引）
    pub fn push(self: *PHPArray, allocator: Allocator, value: Value) !void {
        const key = ArrayKey{ .integer = self.next_index };
        _ = value.retain();
        try self.elements.put(key, value);
        self.next_index += 1;
        _ = allocator; // 避免未使用警告
    }

    /// 检查是否包含字符串键（关联数组）
    pub fn hasStringKeys(self: *PHPArray) bool {
        return self.elements.hasStringKeys();
    }

    /// 获取元素数量
    pub fn count(self: *PHPArray) usize {
        return self.elements.count();
    }

    /// 删除元素（通过 ArrayKey）
    pub fn unset(self: *PHPArray, allocator: Allocator, key: ArrayKey) bool {
        if (self.elements.get(key)) |old_value| {
            if (self.elements.remove(key)) {
                old_value.release(allocator);
                if (key == .string) {
                    key.string.release(allocator);
                }
                return true;
            }
        }
        return false;
    }

    /// 删除元素（通过 Value 键，兼容 int/string）
    pub fn unsetByValue(self: *PHPArray, allocator: Allocator, key: Value) bool {
        return self.unset(allocator, normalizeArrayKeyFromValue(key));
    }

    /// 通过整数索引获取元素（用于数组遍历）
    /// 参数: index - 整数索引 (usize)
    /// 返回: 对应位置的元素，如果不存在返回 null
    pub fn getByIndex(self: *PHPArray, index: usize) ?Value {
        return self.elements.get(.{ .integer = @intCast(index) });
    }

    /// 通过整数索引获取元素指针（用于引用修改）
    /// 参数: index - 整数索引 (usize)
    /// 返回: 对应位置的元素指针，如果不存在返回 null
    pub fn getPtrByIndex(self: *PHPArray, index: usize) ?*Value {
        return self.elements.getPtr(.{ .integer = @intCast(index) });
    }

    /// 设置元素（通过整数索引）
    pub fn setByIndex(self: *PHPArray, allocator: Allocator, index: usize, value: Value) !void {
        try self.set(allocator, .{ .integer = @intCast(index) }, value);
    }
};

