const std = @import("std");

/// Copy-on-Write (COW) 实现
/// 
/// 设计目标：
/// 1. 引用计数管理 - 追踪共享状态
/// 2. 延迟复制 - 只在写入时复制
/// 3. 线程安全 - 原子操作保证并发安全
/// 4. 内存效率 - 减少不必要的复制

/// COW状态
pub const COWState = enum(u8) {
    /// 独占所有权 - 可以直接修改
    exclusive,
    /// 共享状态 - 需要复制后才能修改
    shared,
    /// 不可变 - 永远不能修改
    immutable,
};

/// COW包装器 - 通用COW容器
pub fn COWWrapper(comptime T: type) type {
    return struct {
        const Self = @This();

        /// 内部数据
        data: *T,
        /// 引用计数（原子操作）
        ref_count: *std.atomic.Value(u32),
        /// COW状态
        state: COWState,
        /// 分配器
        allocator: std.mem.Allocator,

        /// 创建新的COW包装器
        pub fn init(allocator: std.mem.Allocator, value: T) !Self {
            const data = try allocator.create(T);
            data.* = value;

            const ref_count = try allocator.create(std.atomic.Value(u32));
            ref_count.* = std.atomic.Value(u32).init(1);

            return Self{
                .data = data,
                .ref_count = ref_count,
                .state = .exclusive,
                .allocator = allocator,
            };
        }


        /// 从现有数据创建（共享）
        pub fn share(self: *Self) Self {
            // 增加引用计数
            _ = self.ref_count.fetchAdd(1, .seq_cst);
            // 标记为共享状态
            self.state = .shared;

            return Self{
                .data = self.data,
                .ref_count = self.ref_count,
                .state = .shared,
                .allocator = self.allocator,
            };
        }

        /// 获取只读访问
        pub fn get(self: *const Self) *const T {
            return self.data;
        }

        /// 获取可写访问（如果需要会触发复制）
        pub fn getMutable(self: *Self) !*T {
            if (self.state == .immutable) {
                return error.ImmutableValue;
            }

            // 检查是否需要复制
            const count = self.ref_count.load(.seq_cst);
            if (count > 1) {
                // 需要复制
                try self.copyOnWrite();
            }

            return self.data;
        }

        /// 执行写时复制
        fn copyOnWrite(self: *Self) !void {
            // 分配新数据
            const new_data = try self.allocator.create(T);
            new_data.* = self.data.*;

            // 分配新引用计数
            const new_ref_count = try self.allocator.create(std.atomic.Value(u32));
            new_ref_count.* = std.atomic.Value(u32).init(1);

            // 减少旧引用计数
            const old_count = self.ref_count.fetchSub(1, .seq_cst);
            if (old_count == 1) {
                // 我们是最后一个引用，释放旧数据
                self.allocator.destroy(self.data);
                self.allocator.destroy(self.ref_count);
            }

            // 更新到新数据
            self.data = new_data;
            self.ref_count = new_ref_count;
            self.state = .exclusive;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            const old_count = self.ref_count.fetchSub(1, .seq_cst);
            if (old_count == 1) {
                // 最后一个引用，释放数据
                self.allocator.destroy(self.data);
                self.allocator.destroy(self.ref_count);
            }
        }

        /// 获取当前引用计数
        pub fn getRefCount(self: *const Self) u32 {
            return self.ref_count.load(.seq_cst);
        }

        /// 检查是否为独占所有权
        pub fn isExclusive(self: *const Self) bool {
            return self.state == .exclusive or self.ref_count.load(.seq_cst) == 1;
        }

        /// 标记为不可变
        pub fn makeImmutable(self: *Self) void {
            self.state = .immutable;
        }
    };
}

/// COW字符串 - PHP字符串的COW实现
/// 
/// 特性：
/// 1. 短字符串优化 (SSO) - 小于等于23字节的字符串内联存储
/// 2. 引用计数共享 - 多个引用共享同一数据
/// 3. 写时复制 - 修改时才复制数据
pub const COWString = struct {
    const Self = @This();

    /// 短字符串优化阈值
    pub const SSO_CAPACITY: usize = 23;

    /// 存储类型
    const Storage = union(enum) {
        /// 短字符串 - 内联存储
        short: ShortString,
        /// 长字符串 - 堆分配
        long: LongString,
    };

    const ShortString = struct {
        data: [SSO_CAPACITY]u8,
        len: u8,
    };

    const LongString = struct {
        data: [*]u8,
        len: usize,
        capacity: usize,
        ref_count: *std.atomic.Value(u32),
    };

    storage: Storage,
    state: COWState,
    allocator: std.mem.Allocator,

    /// 创建空字符串
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .storage = .{ .short = .{ .data = undefined, .len = 0 } },
            .state = .exclusive,
            .allocator = allocator,
        };
    }

    /// 从切片创建
    pub fn fromSlice(allocator: std.mem.Allocator, str_data: []const u8) !Self {
        if (str_data.len <= SSO_CAPACITY) {
            // 使用短字符串优化
            var short = ShortString{ .data = undefined, .len = @intCast(str_data.len) };
            @memcpy(short.data[0..str_data.len], str_data);
            return Self{
                .storage = .{ .short = short },
                .state = .exclusive,
                .allocator = allocator,
            };
        } else {
            // 堆分配
            const data = try allocator.alloc(u8, str_data.len);
            @memcpy(data, str_data);

            const ref_count = try allocator.create(std.atomic.Value(u32));
            ref_count.* = std.atomic.Value(u32).init(1);

            return Self{
                .storage = .{ .long = .{
                    .data = data.ptr,
                    .len = str_data.len,
                    .capacity = str_data.len,
                    .ref_count = ref_count,
                } },
                .state = .exclusive,
                .allocator = allocator,
            };
        }
    }

    /// 获取只读切片
    pub fn slice(self: *const Self) []const u8 {
        return switch (self.storage) {
            .short => |s| s.data[0..s.len],
            .long => |l| l.data[0..l.len],
        };
    }

    /// 获取长度
    pub fn len(self: *const Self) usize {
        return switch (self.storage) {
            .short => |s| s.len,
            .long => |l| l.len,
        };
    }

    /// 共享（增加引用计数）
    pub fn share(self: *Self) Self {
        switch (self.storage) {
            .short => {
                // 短字符串直接复制
                return self.*;
            },
            .long => |*l| {
                _ = l.ref_count.fetchAdd(1, .seq_cst);
                self.state = .shared;
                return Self{
                    .storage = self.storage,
                    .state = .shared,
                    .allocator = self.allocator,
                };
            },
        }
    }

    /// 获取可变切片（触发COW）
    pub fn getMutableSlice(self: *Self) ![]u8 {
        if (self.state == .immutable) {
            return error.ImmutableValue;
        }

        switch (self.storage) {
            .short => |*s| {
                return s.data[0..s.len];
            },
            .long => |*l| {
                const count = l.ref_count.load(.seq_cst);
                if (count > 1) {
                    // 需要复制
                    try self.copyOnWrite();
                }
                return self.storage.long.data[0..self.storage.long.len];
            },
        }
    }

    /// 追加字符串
    pub fn append(self: *Self, other: []const u8) !void {
        if (self.state == .immutable) {
            return error.ImmutableValue;
        }

        const new_len = self.len() + other.len;

        switch (self.storage) {
            .short => |*s| {
                if (new_len <= SSO_CAPACITY) {
                    // 仍然可以使用短字符串
                    @memcpy(s.data[s.len..][0..other.len], other);
                    s.len = @intCast(new_len);
                } else {
                    // 需要转换为长字符串
                    const data = try self.allocator.alloc(u8, new_len);
                    @memcpy(data[0..s.len], s.data[0..s.len]);
                    @memcpy(data[s.len..], other);

                    const ref_count = try self.allocator.create(std.atomic.Value(u32));
                    ref_count.* = std.atomic.Value(u32).init(1);

                    self.storage = .{ .long = .{
                        .data = data.ptr,
                        .len = new_len,
                        .capacity = new_len,
                        .ref_count = ref_count,
                    } };
                }
            },
            .long => |*l| {
                const count = l.ref_count.load(.seq_cst);
                if (count > 1) {
                    // 需要复制
                    try self.copyOnWrite();
                }

                // 检查容量
                if (new_len > self.storage.long.capacity) {
                    const new_capacity = @max(new_len, self.storage.long.capacity * 2);
                    const new_data = try self.allocator.realloc(
                        self.storage.long.data[0..self.storage.long.capacity],
                        new_capacity,
                    );
                    self.storage.long.data = new_data.ptr;
                    self.storage.long.capacity = new_capacity;
                }

                @memcpy(self.storage.long.data[self.storage.long.len..][0..other.len], other);
                self.storage.long.len = new_len;
            },
        }
    }

    /// 执行写时复制
    fn copyOnWrite(self: *Self) !void {
        switch (self.storage) {
            .short => {
                // 短字符串不需要COW
            },
            .long => |*l| {
                // 分配新数据
                const new_data = try self.allocator.alloc(u8, l.len);
                @memcpy(new_data, l.data[0..l.len]);

                // 分配新引用计数
                const new_ref_count = try self.allocator.create(std.atomic.Value(u32));
                new_ref_count.* = std.atomic.Value(u32).init(1);

                // 减少旧引用计数
                const old_count = l.ref_count.fetchSub(1, .seq_cst);
                if (old_count == 1) {
                    self.allocator.free(l.data[0..l.capacity]);
                    self.allocator.destroy(l.ref_count);
                }

                // 更新到新数据
                self.storage = .{ .long = .{
                    .data = new_data.ptr,
                    .len = new_data.len,
                    .capacity = new_data.len,
                    .ref_count = new_ref_count,
                } };
                self.state = .exclusive;
            },
        }
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        switch (self.storage) {
            .short => {
                // 短字符串无需释放
            },
            .long => |*l| {
                const old_count = l.ref_count.fetchSub(1, .seq_cst);
                if (old_count == 1) {
                    self.allocator.free(l.data[0..l.capacity]);
                    self.allocator.destroy(l.ref_count);
                }
            },
        }
    }

    /// 获取引用计数
    pub fn getRefCount(self: *const Self) u32 {
        return switch (self.storage) {
            .short => 1,
            .long => |l| l.ref_count.load(.seq_cst),
        };
    }

    /// 是否为独占所有权
    pub fn isExclusive(self: *const Self) bool {
        return self.state == .exclusive or self.getRefCount() == 1;
    }

    /// 标记为不可变
    pub fn makeImmutable(self: *Self) void {
        self.state = .immutable;
    }

    /// 是否使用短字符串优化
    pub fn isShort(self: *const Self) bool {
        return self.storage == .short;
    }
};

/// COW数组 - PHP数组的COW实现
/// 
/// 特性：
/// 1. 引用计数共享 - 多个引用共享同一数据
/// 2. 写时复制 - 修改时才复制数据
/// 3. 嵌套数组处理 - 递归COW
pub const COWArray = struct {
    const Self = @This();

    /// 数组元素
    pub const Element = struct {
        key: ArrayKey,
        value: ArrayValue,
    };

    /// 数组键类型
    pub const ArrayKey = union(enum) {
        integer: i64,
        string: []const u8,

        pub fn eql(self: ArrayKey, other: ArrayKey) bool {
            return switch (self) {
                .integer => |a| switch (other) {
                    .integer => |b| a == b,
                    .string => false,
                },
                .string => |a| switch (other) {
                    .string => |b| std.mem.eql(u8, a, b),
                    .integer => false,
                },
            };
        }

        pub fn hash(self: ArrayKey) u64 {
            return switch (self) {
                .integer => |i| @bitCast(i),
                .string => |s| std.hash.Wyhash.hash(0, s),
            };
        }
    };

    /// 数组值类型
    pub const ArrayValue = union(enum) {
        null_val,
        bool_val: bool,
        int_val: i64,
        float_val: f64,
        string_val: *COWString,
        array_val: *COWArray,
        /// 其他类型的占位符
        other: *anyopaque,
    };

    /// 内部数据结构
    const ArrayData = struct {
        elements: std.ArrayListUnmanaged(Element),
        next_index: i64,
        ref_count: std.atomic.Value(u32),
    };

    data: *ArrayData,
    state: COWState,
    allocator: std.mem.Allocator,

    /// 创建空数组
    pub fn init(allocator: std.mem.Allocator) !Self {
        const data = try allocator.create(ArrayData);
        data.* = ArrayData{
            .elements = .{},
            .next_index = 0,
            .ref_count = std.atomic.Value(u32).init(1),
        };

        return Self{
            .data = data,
            .state = .exclusive,
            .allocator = allocator,
        };
    }

    /// 获取元素数量
    pub fn count(self: *const Self) usize {
        return self.data.elements.items.len;
    }

    /// 获取元素（只读）
    pub fn get(self: *const Self, key: ArrayKey) ?ArrayValue {
        for (self.data.elements.items) |elem| {
            if (elem.key.eql(key)) {
                return elem.value;
            }
        }
        return null;
    }

    /// 设置元素（触发COW）
    pub fn set(self: *Self, key: ArrayKey, value: ArrayValue) !void {
        if (self.state == .immutable) {
            return error.ImmutableValue;
        }

        // 检查是否需要COW
        const count_val = self.data.ref_count.load(.seq_cst);
        if (count_val > 1) {
            try self.copyOnWrite();
        }

        // 查找现有键
        for (self.data.elements.items) |*elem| {
            if (elem.key.eql(key)) {
                elem.value = value;
                return;
            }
        }

        // 添加新元素
        try self.data.elements.append(self.allocator, Element{
            .key = key,
            .value = value,
        });

        // 更新next_index
        if (key == .integer) {
            if (key.integer >= self.data.next_index) {
                self.data.next_index = key.integer + 1;
            }
        }
    }

    /// 追加元素（使用自动索引）
    pub fn push(self: *Self, value: ArrayValue) !void {
        const key = ArrayKey{ .integer = self.data.next_index };
        try self.set(key, value);
    }

    /// 删除元素
    pub fn remove(self: *Self, key: ArrayKey) !bool {
        if (self.state == .immutable) {
            return error.ImmutableValue;
        }

        // 检查是否需要COW
        const count_val = self.data.ref_count.load(.seq_cst);
        if (count_val > 1) {
            try self.copyOnWrite();
        }

        // 查找并删除
        for (self.data.elements.items, 0..) |elem, i| {
            if (elem.key.eql(key)) {
                _ = self.data.elements.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// 共享（增加引用计数）
    pub fn share(self: *Self) Self {
        _ = self.data.ref_count.fetchAdd(1, .seq_cst);
        self.state = .shared;

        return Self{
            .data = self.data,
            .state = .shared,
            .allocator = self.allocator,
        };
    }

    /// 执行写时复制
    fn copyOnWrite(self: *Self) !void {
        // 分配新数据
        const new_data = try self.allocator.create(ArrayData);
        new_data.* = ArrayData{
            .elements = .{},
            .next_index = self.data.next_index,
            .ref_count = std.atomic.Value(u32).init(1),
        };

        // 复制元素
        try new_data.elements.ensureTotalCapacity(self.allocator, self.data.elements.items.len);
        for (self.data.elements.items) |elem| {
            try new_data.elements.append(self.allocator, elem);
        }

        // 减少旧引用计数
        const old_count = self.data.ref_count.fetchSub(1, .seq_cst);
        if (old_count == 1) {
            self.data.elements.deinit(self.allocator);
            self.allocator.destroy(self.data);
        }

        // 更新到新数据
        self.data = new_data;
        self.state = .exclusive;
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        const old_count = self.data.ref_count.fetchSub(1, .seq_cst);
        if (old_count == 1) {
            // 释放嵌套的COW对象
            for (self.data.elements.items) |elem| {
                switch (elem.value) {
                    .string_val => |s| {
                        var str = s;
                        str.deinit();
                        self.allocator.destroy(s);
                    },
                    .array_val => |a| {
                        var arr = a;
                        arr.deinit();
                        self.allocator.destroy(a);
                    },
                    else => {},
                }
            }
            self.data.elements.deinit(self.allocator);
            self.allocator.destroy(self.data);
        }
    }

    /// 获取引用计数
    pub fn getRefCount(self: *const Self) u32 {
        return self.data.ref_count.load(.seq_cst);
    }

    /// 是否为独占所有权
    pub fn isExclusive(self: *const Self) bool {
        return self.state == .exclusive or self.getRefCount() == 1;
    }

    /// 标记为不可变
    pub fn makeImmutable(self: *Self) void {
        self.state = .immutable;
    }

    /// 估算内存大小
    pub fn estimateSize(self: *const Self) usize {
        var size: usize = @sizeOf(ArrayData);
        size += self.data.elements.items.len * @sizeOf(Element);

        // 估算嵌套对象大小
        for (self.data.elements.items) |elem| {
            switch (elem.value) {
                .string_val => |s| {
                    size += @sizeOf(COWString) + s.len();
                },
                .array_val => |a| {
                    size += a.estimateSize();
                },
                else => {},
            }
        }

        return size;
    }

    /// 获取迭代器
    pub fn iterator(self: *const Self) []const Element {
        return self.data.elements.items;
    }
};

// ============================================================
// 单元测试
// ============================================================

test "COWWrapper basic operations" {
    const allocator = std.testing.allocator;

    var wrapper = try COWWrapper(i64).init(allocator, 42);
    defer wrapper.deinit();

    // 测试只读访问
    try std.testing.expectEqual(@as(i64, 42), wrapper.get().*);

    // 测试可写访问
    const ptr = try wrapper.getMutable();
    ptr.* = 100;
    try std.testing.expectEqual(@as(i64, 100), wrapper.get().*);
}

test "COWWrapper sharing" {
    const allocator = std.testing.allocator;

    var wrapper1 = try COWWrapper(i64).init(allocator, 42);
    defer wrapper1.deinit();

    var wrapper2 = wrapper1.share();
    defer wrapper2.deinit();

    // 两个wrapper共享同一数据
    try std.testing.expectEqual(@as(u32, 2), wrapper1.getRefCount());
    try std.testing.expectEqual(@as(u32, 2), wrapper2.getRefCount());

    // 修改wrapper2应该触发COW
    const ptr = try wrapper2.getMutable();
    ptr.* = 100;

    // 现在应该是独立的
    try std.testing.expectEqual(@as(i64, 42), wrapper1.get().*);
    try std.testing.expectEqual(@as(i64, 100), wrapper2.get().*);
}

test "COWString short string optimization" {
    const allocator = std.testing.allocator;

    // 短字符串
    var short = try COWString.fromSlice(allocator, "hello");
    defer short.deinit();

    try std.testing.expect(short.isShort());
    try std.testing.expectEqualStrings("hello", short.slice());
}

test "COWString long string" {
    const allocator = std.testing.allocator;

    // 长字符串（超过SSO阈值）
    const long_str = "This is a very long string that exceeds the SSO capacity limit";
    var long = try COWString.fromSlice(allocator, long_str);
    defer long.deinit();

    try std.testing.expect(!long.isShort());
    try std.testing.expectEqualStrings(long_str, long.slice());
}

test "COWString sharing and COW" {
    const allocator = std.testing.allocator;

    const long_str = "This is a very long string that exceeds the SSO capacity limit";
    var str1 = try COWString.fromSlice(allocator, long_str);
    defer str1.deinit();

    var str2 = str1.share();
    defer str2.deinit();

    // 共享状态
    try std.testing.expectEqual(@as(u32, 2), str1.getRefCount());

    // 修改str2触发COW
    const slice = try str2.getMutableSlice();
    slice[0] = 'X';

    // 验证独立
    try std.testing.expectEqual(@as(u8, 'T'), str1.slice()[0]);
    try std.testing.expectEqual(@as(u8, 'X'), str2.slice()[0]);
}

test "COWString append" {
    const allocator = std.testing.allocator;

    var str = try COWString.fromSlice(allocator, "hello");
    defer str.deinit();

    try str.append(" world");
    try std.testing.expectEqualStrings("hello world", str.slice());
}

test "COWArray basic operations" {
    const allocator = std.testing.allocator;

    var arr = try COWArray.init(allocator);
    defer arr.deinit();

    // 添加元素
    try arr.push(.{ .int_val = 1 });
    try arr.push(.{ .int_val = 2 });
    try arr.push(.{ .int_val = 3 });

    try std.testing.expectEqual(@as(usize, 3), arr.count());

    // 获取元素
    const val = arr.get(.{ .integer = 1 });
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 2), val.?.int_val);
}

test "COWArray sharing and COW" {
    const allocator = std.testing.allocator;

    var arr1 = try COWArray.init(allocator);
    defer arr1.deinit();

    try arr1.push(.{ .int_val = 1 });
    try arr1.push(.{ .int_val = 2 });

    var arr2 = arr1.share();
    defer arr2.deinit();

    // 共享状态
    try std.testing.expectEqual(@as(u32, 2), arr1.getRefCount());

    // 修改arr2触发COW
    try arr2.set(.{ .integer = 0 }, .{ .int_val = 100 });

    // 验证独立
    try std.testing.expectEqual(@as(i64, 1), arr1.get(.{ .integer = 0 }).?.int_val);
    try std.testing.expectEqual(@as(i64, 100), arr2.get(.{ .integer = 0 }).?.int_val);
}

test "COWArray string keys" {
    const allocator = std.testing.allocator;

    var arr = try COWArray.init(allocator);
    defer arr.deinit();

    try arr.set(.{ .string = "name" }, .{ .int_val = 42 });
    try arr.set(.{ .string = "value" }, .{ .float_val = 3.14 });

    try std.testing.expectEqual(@as(usize, 2), arr.count());

    const name_val = arr.get(.{ .string = "name" });
    try std.testing.expect(name_val != null);
    try std.testing.expectEqual(@as(i64, 42), name_val.?.int_val);
}

test "COWArray remove" {
    const allocator = std.testing.allocator;

    var arr = try COWArray.init(allocator);
    defer arr.deinit();

    try arr.push(.{ .int_val = 1 });
    try arr.push(.{ .int_val = 2 });
    try arr.push(.{ .int_val = 3 });

    const removed = try arr.remove(.{ .integer = 1 });
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 2), arr.count());
}

test "COWArray estimate size" {
    const allocator = std.testing.allocator;

    var arr = try COWArray.init(allocator);
    defer arr.deinit();

    try arr.push(.{ .int_val = 1 });
    try arr.push(.{ .int_val = 2 });

    const size = arr.estimateSize();
    try std.testing.expect(size > 0);
}
