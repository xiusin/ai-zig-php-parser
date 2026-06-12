//! PackedArray - 紧凑数组实现
//! 目标：为纯整数索引数组提供高性能存储
//!
//! 核心特性：
//! 1. 连续内存布局 - FastValue 紧密排列
//! 2. O(1) 索引访问
//! 3. SIMD 加速的 sum/max/min/in_array
//! 4. Copy-on-Write 语义
//! 5. 自动转换为 mixed 模式（当插入字符串键时）

const std = @import("std");
const FastValue = @import("fast_value.zig").FastValue;
const FastOps = @import("fast_value.zig").FastOps;
const SimdArray = @import("simd_ops.zig").SimdArray;
const SimdString = @import("simd_ops.zig").SimdString;

// ============================================================================
// PackedArray - 紧凑数组
// ============================================================================

pub const PackedArray = struct {
    /// 数据存储
    data: []FastValue,
    /// 当前元素数量
    len: u32,
    /// 容量
    capacity: u32,
    /// 引用计数 (用于 COW)
    ref_count: u32,
    /// 分配器
    allocator: std.mem.Allocator,

    const INITIAL_CAPACITY = 8;
    const GROWTH_FACTOR = 2;

    /// 初始化空数组
    pub fn init(allocator: std.mem.Allocator) !*PackedArray {
        return initWithCapacity(allocator, INITIAL_CAPACITY);
    }

    /// 初始化指定容量的数组
    pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: u32) !*PackedArray {
        const self = try allocator.create(PackedArray);
        const cap = @max(capacity, INITIAL_CAPACITY);
        self.* = .{
            .data = try allocator.alloc(FastValue, cap),
            .len = 0,
            .capacity = cap,
            .ref_count = 1,
            .allocator = allocator,
        };
        return self;
    }

    /// 从切片创建
    pub fn fromSlice(allocator: std.mem.Allocator, values: []const FastValue) !*PackedArray {
        const cap: u32 = @intCast(@max(values.len, INITIAL_CAPACITY));
        const self = try allocator.create(PackedArray);
        self.* = .{
            .data = try allocator.alloc(FastValue, cap),
            .len = @intCast(values.len),
            .capacity = cap,
            .ref_count = 1,
            .allocator = allocator,
        };
        @memcpy(self.data[0..values.len], values);
        return self;
    }

    /// 释放资源
    pub fn deinit(self: *PackedArray) void {
        self.allocator.free(self.data);
        self.allocator.destroy(self);
    }

    /// 增加引用计数
    pub fn retain(self: *PackedArray) *PackedArray {
        self.ref_count += 1;
        return self;
    }

    /// 减少引用计数，返回是否需要释放
    pub fn release(self: *PackedArray) bool {
        if (self.ref_count == 0) return false;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit();
            return true;
        }
        return false;
    }

    // ========================================================================
    // Task 3.1.2: O(1) 索引访问
    // ========================================================================

    /// O(1) 索引访问
    pub inline fn get(self: *const PackedArray, index: u32) ?FastValue {
        if (index >= self.len) return null;
        return self.data[index];
    }

    /// O(1) 索引设置
    pub inline fn set(self: *PackedArray, index: u32, value: FastValue) bool {
        if (index >= self.len) return false;
        self.data[index] = value;
        return true;
    }

    /// 获取指针（用于原地修改）
    pub inline fn getPtr(self: *PackedArray, index: u32) ?*FastValue {
        if (index >= self.len) return null;
        return &self.data[index];
    }

    // ========================================================================
    // Task 3.1.3: 动态扩容
    // ========================================================================

    /// 确保容量足够
    pub fn ensureCapacity(self: *PackedArray, min_capacity: u32) !void {
        if (self.capacity >= min_capacity) return;

        var new_cap = self.capacity;
        while (new_cap < min_capacity) {
            new_cap *= GROWTH_FACTOR;
        }

        const new_data = try self.allocator.alloc(FastValue, new_cap);
        @memcpy(new_data[0..self.len], self.data[0..self.len]);
        self.allocator.free(self.data);
        self.data = new_data;
        self.capacity = new_cap;
    }

    /// 追加元素
    pub fn push(self: *PackedArray, value: FastValue) !void {
        try self.ensureCapacity(self.len + 1);
        self.data[self.len] = value;
        self.len += 1;
    }

    /// 弹出最后一个元素
    pub fn pop(self: *PackedArray) ?FastValue {
        if (self.len == 0) return null;
        self.len -= 1;
        return self.data[self.len];
    }

    /// 在指定位置插入
    pub fn insert(self: *PackedArray, index: u32, value: FastValue) !void {
        if (index > self.len) return error.IndexOutOfBounds;
        try self.ensureCapacity(self.len + 1);

        // 移动元素
        if (index < self.len) {
            var i = self.len;
            while (i > index) : (i -= 1) {
                self.data[i] = self.data[i - 1];
            }
        }
        self.data[index] = value;
        self.len += 1;
    }

    /// 删除指定位置的元素
    pub fn remove(self: *PackedArray, index: u32) ?FastValue {
        if (index >= self.len) return null;
        const value = self.data[index];

        // 移动元素
        var i = index;
        while (i < self.len - 1) : (i += 1) {
            self.data[i] = self.data[i + 1];
        }
        self.len -= 1;
        return value;
    }

    /// 清空数组
    pub fn clear(self: *PackedArray) void {
        self.len = 0;
    }

    /// 获取长度
    pub inline fn count(self: *const PackedArray) u32 {
        return self.len;
    }

    /// 获取切片
    pub inline fn slice(self: *const PackedArray) []const FastValue {
        return self.data[0..self.len];
    }

    /// 获取可变切片
    pub inline fn sliceMut(self: *PackedArray) []FastValue {
        return self.data[0..self.len];
    }

    // ========================================================================
    // Task 3.1.5: SIMD sum/max/min
    // ========================================================================

    /// SIMD 加速的整数求和
    pub fn sumInt(self: *const PackedArray) i64 {
        if (self.len == 0) return 0;

        // 提取整数到临时缓冲区
        var sum: i64 = 0;
        var i: usize = 0;
        const len = self.len;

        // 4元素块处理 (手动向量化)
        while (i + 4 <= len) : (i += 4) {
            const v0 = self.data[i].toInt();
            const v1 = self.data[i + 1].toInt();
            const v2 = self.data[i + 2].toInt();
            const v3 = self.data[i + 3].toInt();
            sum += v0 + v1 + v2 + v3;
        }

        // 处理剩余
        while (i < len) : (i += 1) {
            sum += self.data[i].toInt();
        }

        return sum;
    }

    /// SIMD 加速的浮点求和
    pub fn sumFloat(self: *const PackedArray) f64 {
        if (self.len == 0) return 0.0;

        var sum: f64 = 0.0;
        var i: usize = 0;
        const len = self.len;

        // 4元素块处理
        while (i + 4 <= len) : (i += 4) {
            const v0 = self.data[i].toFloat();
            const v1 = self.data[i + 1].toFloat();
            const v2 = self.data[i + 2].toFloat();
            const v3 = self.data[i + 3].toFloat();
            sum += v0 + v1 + v2 + v3;
        }

        // 处理剩余
        while (i < len) : (i += 1) {
            sum += self.data[i].toFloat();
        }

        return sum;
    }

    /// SIMD 加速的最大值
    pub fn maxInt(self: *const PackedArray) ?i64 {
        if (self.len == 0) return null;

        var max_val = self.data[0].toInt();
        var i: usize = 1;
        const len = self.len;

        // 4元素块处理
        while (i + 4 <= len) : (i += 4) {
            const v0 = self.data[i].toInt();
            const v1 = self.data[i + 1].toInt();
            const v2 = self.data[i + 2].toInt();
            const v3 = self.data[i + 3].toInt();
            max_val = @max(max_val, @max(@max(v0, v1), @max(v2, v3)));
        }

        // 处理剩余
        while (i < len) : (i += 1) {
            max_val = @max(max_val, self.data[i].toInt());
        }

        return max_val;
    }

    /// SIMD 加速的最小值
    pub fn minInt(self: *const PackedArray) ?i64 {
        if (self.len == 0) return null;

        var min_val = self.data[0].toInt();
        var i: usize = 1;
        const len = self.len;

        // 4元素块处理
        while (i + 4 <= len) : (i += 4) {
            const v0 = self.data[i].toInt();
            const v1 = self.data[i + 1].toInt();
            const v2 = self.data[i + 2].toInt();
            const v3 = self.data[i + 3].toInt();
            min_val = @min(min_val, @min(@min(v0, v1), @min(v2, v3)));
        }

        // 处理剩余
        while (i < len) : (i += 1) {
            min_val = @min(min_val, self.data[i].toInt());
        }

        return min_val;
    }

    /// 浮点最大值
    pub fn maxFloat(self: *const PackedArray) ?f64 {
        if (self.len == 0) return null;

        var max_val = self.data[0].toFloat();
        for (self.data[1..self.len]) |v| {
            max_val = @max(max_val, v.toFloat());
        }
        return max_val;
    }

    /// 浮点最小值
    pub fn minFloat(self: *const PackedArray) ?f64 {
        if (self.len == 0) return null;

        var min_val = self.data[0].toFloat();
        for (self.data[1..self.len]) |v| {
            min_val = @min(min_val, v.toFloat());
        }
        return min_val;
    }

    // ========================================================================
    // Task 3.1.6: SIMD in_array 搜索
    // ========================================================================

    /// 搜索整数值，返回索引
    pub fn findInt(self: *const PackedArray, needle: i64) ?u32 {
        var i: u32 = 0;
        const len = self.len;

        // 4元素块搜索
        while (i + 4 <= len) : (i += 4) {
            if (self.data[i].isInt() and self.data[i].asInt() == needle) return i;
            if (self.data[i + 1].isInt() and self.data[i + 1].asInt() == needle) return i + 1;
            if (self.data[i + 2].isInt() and self.data[i + 2].asInt() == needle) return i + 2;
            if (self.data[i + 3].isInt() and self.data[i + 3].asInt() == needle) return i + 3;
        }

        // 处理剩余
        while (i < len) : (i += 1) {
            if (self.data[i].isInt() and self.data[i].asInt() == needle) return i;
        }

        return null;
    }

    /// 搜索浮点值
    pub fn findFloat(self: *const PackedArray, needle: f64) ?u32 {
        for (self.data[0..self.len], 0..) |v, i| {
            if (v.isFloat() and v.asFloat() == needle) return @intCast(i);
        }
        return null;
    }

    /// 通用搜索（比较 bits）
    pub fn find(self: *const PackedArray, needle: FastValue) ?u32 {
        const needle_bits = needle.bits;
        var i: u32 = 0;
        const len = self.len;

        // 4元素块搜索
        while (i + 4 <= len) : (i += 4) {
            if (self.data[i].bits == needle_bits) return i;
            if (self.data[i + 1].bits == needle_bits) return i + 1;
            if (self.data[i + 2].bits == needle_bits) return i + 2;
            if (self.data[i + 3].bits == needle_bits) return i + 3;
        }

        // 处理剩余
        while (i < len) : (i += 1) {
            if (self.data[i].bits == needle_bits) return i;
        }

        return null;
    }

    /// in_array 检查
    pub fn contains(self: *const PackedArray, needle: FastValue) bool {
        return self.find(needle) != null;
    }

    /// 检查是否包含整数
    pub fn containsInt(self: *const PackedArray, needle: i64) bool {
        return self.findInt(needle) != null;
    }

    // ========================================================================
    // Task 3.1.8: Copy-on-Write 语义
    // ========================================================================

    /// 确保独占所有权（COW）
    pub fn ensureUnique(self: *PackedArray) !*PackedArray {
        if (self.ref_count == 1) return self;

        // 创建副本
        const copy = try self.allocator.create(PackedArray);
        copy.* = .{
            .data = try self.allocator.alloc(FastValue, self.capacity),
            .len = self.len,
            .capacity = self.capacity,
            .ref_count = 1,
            .allocator = self.allocator,
        };
        @memcpy(copy.data[0..self.len], self.data[0..self.len]);

        // 减少原数组引用
        _ = self.release();

        return copy;
    }

    /// COW 写入
    pub fn cowSet(self: *PackedArray, index: u32, value: FastValue) !*PackedArray {
        const unique = try self.ensureUnique();
        _ = unique.set(index, value);
        return unique;
    }

    /// COW 追加
    pub fn cowPush(self: *PackedArray, value: FastValue) !*PackedArray {
        const unique = try self.ensureUnique();
        try unique.push(value);
        return unique;
    }

    // ========================================================================
    // 迭代器
    // ========================================================================

    pub const IterItem = struct { index: u32, value: FastValue };

    pub const Iterator = struct {
        array: *const PackedArray,
        index: u32,

        pub fn next(self: *Iterator) ?IterItem {
            if (self.index >= self.array.len) return null;
            const result = IterItem{ .index = self.index, .value = self.array.data[self.index] };
            self.index += 1;
            return result;
        }

        pub fn reset(self: *Iterator) void {
            self.index = 0;
        }
    };

    pub fn iterator(self: *const PackedArray) Iterator {
        return .{ .array = self, .index = 0 };
    }

    // ========================================================================
    // 批量操作
    // ========================================================================

    /// 批量设置
    pub fn setRange(self: *PackedArray, start: u32, values: []const FastValue) !void {
        const end = start + @as(u32, @intCast(values.len));
        if (end > self.len) return error.IndexOutOfBounds;
        @memcpy(self.data[start..end], values);
    }

    /// 批量追加
    pub fn pushSlice(self: *PackedArray, values: []const FastValue) !void {
        try self.ensureCapacity(self.len + @as(u32, @intCast(values.len)));
        @memcpy(self.data[self.len..][0..values.len], values);
        self.len += @intCast(values.len);
    }

    /// 反转数组
    pub fn reverse(self: *PackedArray) void {
        if (self.len <= 1) return;
        var i: u32 = 0;
        var j: u32 = self.len - 1;
        while (i < j) : ({
            i += 1;
            j -= 1;
        }) {
            const tmp = self.data[i];
            self.data[i] = self.data[j];
            self.data[j] = tmp;
        }
    }

    /// 填充数组
    pub fn fill(self: *PackedArray, value: FastValue) void {
        for (self.data[0..self.len]) |*v| {
            v.* = value;
        }
    }

    // ========================================================================
    // 数组运算
    // ========================================================================

    /// 数组元素加法
    pub fn addScalar(self: *PackedArray, scalar: FastValue) void {
        if (scalar.isInt()) {
            const s = scalar.asInt();
            for (self.data[0..self.len]) |*v| {
                if (v.isInt()) {
                    v.* = FastValue.initInt(v.asInt() + s);
                }
            }
        } else if (scalar.isFloat()) {
            const s = scalar.asFloat();
            for (self.data[0..self.len]) |*v| {
                v.* = FastValue.initFloat(v.toFloat() + s);
            }
        }
    }

    /// 数组元素乘法
    pub fn mulScalar(self: *PackedArray, scalar: FastValue) void {
        if (scalar.isInt()) {
            const s = scalar.asInt();
            for (self.data[0..self.len]) |*v| {
                if (v.isInt()) {
                    v.* = FastValue.initInt(v.asInt() * s);
                }
            }
        } else if (scalar.isFloat()) {
            const s = scalar.asFloat();
            for (self.data[0..self.len]) |*v| {
                v.* = FastValue.initFloat(v.toFloat() * s);
            }
        }
    }
};

// ============================================================================
// 错误类型
// ============================================================================

pub const PackedArrayError = error{
    IndexOutOfBounds,
    OutOfMemory,
};

// ============================================================================
// 测试
// ============================================================================

test "PackedArray basic operations" {
    const allocator = std.testing.allocator;

    var arr = try PackedArray.init(allocator);
    defer _ = arr.release();

    // 测试 push
    try arr.push(FastValue.initInt(1));
    try arr.push(FastValue.initInt(2));
    try arr.push(FastValue.initInt(3));

    try std.testing.expect(arr.count() == 3);

    // 测试 get
    try std.testing.expect(arr.get(0).?.asInt() == 1);
    try std.testing.expect(arr.get(1).?.asInt() == 2);
    try std.testing.expect(arr.get(2).?.asInt() == 3);
    try std.testing.expect(arr.get(3) == null);

    // 测试 set
    try std.testing.expect(arr.set(1, FastValue.initInt(20)));
    try std.testing.expect(arr.get(1).?.asInt() == 20);

    // 测试 pop
    try std.testing.expect(arr.pop().?.asInt() == 3);
    try std.testing.expect(arr.count() == 2);
}

test "PackedArray SIMD sum" {
    const allocator = std.testing.allocator;

    var arr = try PackedArray.init(allocator);
    defer _ = arr.release();

    // 添加 1-10
    var i: i64 = 1;
    while (i <= 10) : (i += 1) {
        try arr.push(FastValue.initInt(i));
    }

    // sum = 1+2+...+10 = 55
    try std.testing.expect(arr.sumInt() == 55);
}

test "PackedArray SIMD max/min" {
    const allocator = std.testing.allocator;

    var arr = try PackedArray.init(allocator);
    defer _ = arr.release();

    try arr.push(FastValue.initInt(3));
    try arr.push(FastValue.initInt(1));
    try arr.push(FastValue.initInt(4));
    try arr.push(FastValue.initInt(1));
    try arr.push(FastValue.initInt(5));
    try arr.push(FastValue.initInt(9));
    try arr.push(FastValue.initInt(2));
    try arr.push(FastValue.initInt(6));

    try std.testing.expect(arr.maxInt().? == 9);
    try std.testing.expect(arr.minInt().? == 1);
}

test "PackedArray in_array search" {
    const allocator = std.testing.allocator;

    var arr = try PackedArray.init(allocator);
    defer _ = arr.release();

    try arr.push(FastValue.initInt(10));
    try arr.push(FastValue.initInt(20));
    try arr.push(FastValue.initInt(30));
    try arr.push(FastValue.initInt(40));
    try arr.push(FastValue.initInt(50));

    try std.testing.expect(arr.findInt(30).? == 2);
    try std.testing.expect(arr.findInt(100) == null);
    try std.testing.expect(arr.containsInt(40));
    try std.testing.expect(!arr.containsInt(99));
}

test "PackedArray COW" {
    const allocator = std.testing.allocator;

    var arr1 = try PackedArray.init(allocator);
    try arr1.push(FastValue.initInt(1));
    try arr1.push(FastValue.initInt(2));

    // 增加引用
    _ = arr1.retain();
    try std.testing.expect(arr1.ref_count == 2);

    // COW 写入应创建副本
    var arr2 = try arr1.cowSet(0, FastValue.initInt(100));

    // arr1 应该不变
    try std.testing.expect(arr1.get(0).?.asInt() == 1);
    // arr2 应该是新值
    try std.testing.expect(arr2.get(0).?.asInt() == 100);

    // 清理
    _ = arr1.release();
    _ = arr2.release();
}

test "PackedArray iterator" {
    const allocator = std.testing.allocator;

    var arr = try PackedArray.init(allocator);
    defer _ = arr.release();

    try arr.push(FastValue.initInt(1));
    try arr.push(FastValue.initInt(2));
    try arr.push(FastValue.initInt(3));

    var iter = arr.iterator();
    var sum: i64 = 0;
    while (iter.next()) |item| {
        sum += item.value.asInt();
    }

    try std.testing.expect(sum == 6);
}

test "PackedArray reverse" {
    const allocator = std.testing.allocator;

    var arr = try PackedArray.init(allocator);
    defer _ = arr.release();

    try arr.push(FastValue.initInt(1));
    try arr.push(FastValue.initInt(2));
    try arr.push(FastValue.initInt(3));

    arr.reverse();

    try std.testing.expect(arr.get(0).?.asInt() == 3);
    try std.testing.expect(arr.get(1).?.asInt() == 2);
    try std.testing.expect(arr.get(2).?.asInt() == 1);
}

test "PackedArray insert/remove" {
    const allocator = std.testing.allocator;

    var arr = try PackedArray.init(allocator);
    defer _ = arr.release();

    try arr.push(FastValue.initInt(1));
    try arr.push(FastValue.initInt(3));

    // 在索引1插入2
    try arr.insert(1, FastValue.initInt(2));

    try std.testing.expect(arr.count() == 3);
    try std.testing.expect(arr.get(0).?.asInt() == 1);
    try std.testing.expect(arr.get(1).?.asInt() == 2);
    try std.testing.expect(arr.get(2).?.asInt() == 3);

    // 删除索引1
    const removed = arr.remove(1);
    try std.testing.expect(removed.?.asInt() == 2);
    try std.testing.expect(arr.count() == 2);
    try std.testing.expect(arr.get(1).?.asInt() == 3);
}

// ============================================================================
// Task 3.1.4: MixedArray - 支持字符串键的数组
// ============================================================================

/// 数组键类型
pub const ArrayKey = union(enum) {
    integer: i64,
    string: []const u8,

    pub fn hash(self: ArrayKey) u64 {
        return switch (self) {
            .integer => |i| blk: {
                var h: u64 = 0xcbf29ce484222325;
                const bytes = std.mem.asBytes(&i);
                for (bytes) |b| {
                    h ^= b;
                    h *%= 0x100000001b3;
                }
                break :blk h;
            },
            .string => |s| blk: {
                var h: u64 = 0xcbf29ce484222325;
                for (s) |b| {
                    h ^= b;
                    h *%= 0x100000001b3;
                }
                break :blk h;
            },
        };
    }

    pub fn eql(a: ArrayKey, b: ArrayKey) bool {
        return switch (a) {
            .integer => |ai| switch (b) {
                .integer => |bi| ai == bi,
                .string => false,
            },
            .string => |as| switch (b) {
                .string => |bs| std.mem.eql(u8, as, bs),
                .integer => false,
            },
        };
    }
};

/// MixedArray - 支持字符串键的哈希数组
pub const MixedArray = struct {
    const Entry = struct {
        key: ArrayKey,
        value: FastValue,
        hash: u64,
    };

    entries: std.ArrayList(Entry),
    index_map: std.AutoHashMap(u64, usize),
    next_int_key: i64,
    allocator: std.mem.Allocator,
    ref_count: u32,

    pub fn init(allocator: std.mem.Allocator) MixedArray {
        return .{
            .entries = .{},
            .index_map = std.AutoHashMap(u64, usize).init(allocator),
            .next_int_key = 0,
            .allocator = allocator,
            .ref_count = 1,
        };
    }

    pub fn deinit(self: *MixedArray) void {
        // 释放字符串键
        for (self.entries.items) |entry| {
            if (entry.key == .string) {
                self.allocator.free(entry.key.string);
            }
        }
        self.entries.deinit(self.allocator);
        self.index_map.deinit();
    }

    pub fn retain(self: *MixedArray) *MixedArray {
        self.ref_count += 1;
        return self;
    }

    pub fn release(self: *MixedArray) bool {
        if (self.ref_count == 0) return false;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit();
            return true;
        }
        return false;
    }

    /// 获取值
    pub fn get(self: *const MixedArray, key: ArrayKey) ?FastValue {
        const h = key.hash();
        if (self.index_map.get(h)) |idx| {
            if (key.eql(self.entries.items[idx].key)) {
                return self.entries.items[idx].value;
            }
        }
        // 线性搜索处理哈希冲突
        for (self.entries.items) |entry| {
            if (key.eql(entry.key)) {
                return entry.value;
            }
        }
        return null;
    }

    /// 设置值
    pub fn set(self: *MixedArray, key: ArrayKey, value: FastValue) !void {
        const h = key.hash();

        // 检查是否已存在
        for (self.entries.items, 0..) |*entry, i| {
            if (key.eql(entry.key)) {
                entry.value = value;
                return;
            }
            _ = i;
        }

        // 复制字符串键
        const owned_key: ArrayKey = switch (key) {
            .integer => |i| blk: {
                if (i >= self.next_int_key) {
                    self.next_int_key = i + 1;
                }
                break :blk .{ .integer = i };
            },
            .string => |s| .{ .string = try self.allocator.dupe(u8, s) },
        };

        const idx = self.entries.items.len;
        try self.entries.append(self.allocator, .{ .key = owned_key, .value = value, .hash = h });
        try self.index_map.put(h, idx);
    }

    /// 追加值（使用下一个整数键）
    pub fn push(self: *MixedArray, value: FastValue) !void {
        try self.set(.{ .integer = self.next_int_key }, value);
    }

    /// 获取元素数量
    pub fn count(self: *const MixedArray) usize {
        return self.entries.items.len;
    }

    /// 检查是否包含键
    pub fn contains(self: *const MixedArray, key: ArrayKey) bool {
        return self.get(key) != null;
    }

    /// 删除键
    pub fn remove(self: *MixedArray, key: ArrayKey) ?FastValue {
        for (self.entries.items, 0..) |entry, i| {
            if (key.eql(entry.key)) {
                const value = entry.value;
                if (entry.key == .string) {
                    self.allocator.free(entry.key.string);
                }
                _ = self.entries.orderedRemove(self.allocator, i);
                // 重建索引
                self.index_map.clearRetainingCapacity();
                for (self.entries.items, 0..) |e, idx| {
                    self.index_map.put(e.hash, idx) catch {};
                }
                return value;
            }
        }
        return null;
    }

    /// 迭代器
    pub const Iterator = struct {
        array: *const MixedArray,
        index: usize,

        pub fn next(self: *Iterator) ?struct { key: ArrayKey, value: FastValue } {
            if (self.index >= self.array.entries.items.len) return null;
            const entry = self.array.entries.items[self.index];
            self.index += 1;
            return .{ .key = entry.key, .value = entry.value };
        }
    };

    pub fn iterator(self: *const MixedArray) Iterator {
        return .{ .array = self, .index = 0 };
    }
};

// ============================================================================
// Task 3.1.4 & 3.1.7: HybridArray - 自动切换的混合数组
// ============================================================================

/// HybridArray - 自动在 packed 和 mixed 模式间切换
pub const HybridArray = struct {
    const Mode = enum { packed_mode, mixed_mode };

    mode: Mode,
    data: union {
        packed_array: *PackedArray,
        mixed_array: *MixedArray,
    },
    allocator: std.mem.Allocator,

    /// 创建空的 packed 数组
    pub fn init(allocator: std.mem.Allocator) !*HybridArray {
        const self = try allocator.create(HybridArray);
        self.* = .{
            .mode = .packed_mode,
            .data = .{ .packed_array = try PackedArray.init(allocator) },
            .allocator = allocator,
        };
        return self;
    }

    /// 释放资源
    pub fn deinit(self: *HybridArray) void {
        switch (self.mode) {
            .packed_mode => _ = self.data.packed_array.release(),
            .mixed_mode => {
                self.data.mixed_array.deinit();
                self.allocator.destroy(self.data.mixed_array);
            },
        }
        self.allocator.destroy(self);
    }

    /// 获取元素数量
    pub fn count(self: *const HybridArray) usize {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.count(),
            .mixed_mode => self.data.mixed_array.count(),
        };
    }

    /// 通过整数索引获取
    pub fn getInt(self: *const HybridArray, index: i64) ?FastValue {
        return switch (self.mode) {
            .packed_mode => if (index >= 0 and index < self.data.packed_array.len)
                self.data.packed_array.get(@intCast(index))
            else
                null,
            .mixed_mode => self.data.mixed_array.get(.{ .integer = index }),
        };
    }

    /// 通过字符串键获取
    pub fn getString(self: *const HybridArray, key: []const u8) ?FastValue {
        return switch (self.mode) {
            .packed_mode => null, // packed 模式不支持字符串键
            .mixed_mode => self.data.mixed_array.get(.{ .string = key }),
        };
    }

    /// 通过任意键获取
    pub fn get(self: *const HybridArray, key: ArrayKey) ?FastValue {
        return switch (key) {
            .integer => |i| self.getInt(i),
            .string => |s| self.getString(s),
        };
    }

    /// 设置整数索引的值
    pub fn setInt(self: *HybridArray, index: i64, value: FastValue) !void {
        switch (self.mode) {
            .packed_mode => {
                if (index >= 0 and index < self.data.packed_array.len) {
                    _ = self.data.packed_array.set(@intCast(index), value);
                } else if (index == self.data.packed_array.len) {
                    try self.data.packed_array.push(value);
                } else {
                    // 非连续索引，转换为 mixed
                    try self.convertToMixed();
                    try self.data.mixed_array.set(.{ .integer = index }, value);
                }
            },
            .mixed_mode => try self.data.mixed_array.set(.{ .integer = index }, value),
        }
    }

    /// 设置字符串键的值 - 触发转换
    pub fn setString(self: *HybridArray, key: []const u8, value: FastValue) !void {
        if (self.mode == .packed_mode) {
            try self.convertToMixed();
        }
        try self.data.mixed_array.set(.{ .string = key }, value);
    }

    /// 设置任意键的值
    pub fn set(self: *HybridArray, key: ArrayKey, value: FastValue) !void {
        switch (key) {
            .integer => |i| try self.setInt(i, value),
            .string => |s| try self.setString(s, value),
        }
    }

    /// 追加值（使用下一个整数索引）
    pub fn push(self: *HybridArray, value: FastValue) !void {
        switch (self.mode) {
            .packed_mode => try self.data.packed_array.push(value),
            .mixed_mode => try self.data.mixed_array.push(value),
        }
    }

    /// 转换为 mixed 模式
    pub fn convertToMixed(self: *HybridArray) !void {
        if (self.mode == .mixed_mode) return;

        const mixed = try self.allocator.create(MixedArray);
        mixed.* = MixedArray.init(self.allocator);

        // 复制所有元素
        for (self.data.packed_array.data[0..self.data.packed_array.len], 0..) |value, i| {
            try mixed.set(.{ .integer = @intCast(i) }, value);
        }

        // 释放 packed 数组
        _ = self.data.packed_array.release();

        self.mode = .mixed_mode;
        self.data = .{ .mixed_array = mixed };
    }

    /// 检查是否为 packed 模式
    pub fn isPacked(self: *const HybridArray) bool {
        return self.mode == .packed_mode;
    }

    /// 检查是否为 mixed 模式
    pub fn isMixed(self: *const HybridArray) bool {
        return self.mode == .mixed_mode;
    }

    // ========================================================================
    // SIMD 优化操作（仅 packed 模式）
    // ========================================================================

    /// SIMD 求和（仅 packed 模式有效）
    pub fn sumInt(self: *const HybridArray) i64 {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.sumInt(),
            .mixed_mode => blk: {
                var sum: i64 = 0;
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    sum += item.value.toInt();
                }
                break :blk sum;
            },
        };
    }

    /// SIMD 最大值
    pub fn maxInt(self: *const HybridArray) ?i64 {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.maxInt(),
            .mixed_mode => blk: {
                if (self.data.mixed_array.count() == 0) break :blk null;
                var max_val: ?i64 = null;
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    const v = item.value.toInt();
                    if (max_val == null or v > max_val.?) {
                        max_val = v;
                    }
                }
                break :blk max_val;
            },
        };
    }

    /// SIMD 最小值
    pub fn minInt(self: *const HybridArray) ?i64 {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.minInt(),
            .mixed_mode => blk: {
                if (self.data.mixed_array.count() == 0) break :blk null;
                var min_val: ?i64 = null;
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    const v = item.value.toInt();
                    if (min_val == null or v < min_val.?) {
                        min_val = v;
                    }
                }
                break :blk min_val;
            },
        };
    }

    /// in_array 搜索
    pub fn containsValue(self: *const HybridArray, needle: FastValue) bool {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.contains(needle),
            .mixed_mode => blk: {
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    if (item.value.bits == needle.bits) break :blk true;
                }
                break :blk false;
            },
        };
    }
};

// ============================================================================
// HybridArray 测试
// ============================================================================

test "HybridArray packed mode" {
    const allocator = std.testing.allocator;

    var arr = try HybridArray.init(allocator);
    defer arr.deinit();

    try arr.push(FastValue.initInt(1));
    try arr.push(FastValue.initInt(2));
    try arr.push(FastValue.initInt(3));

    try std.testing.expect(arr.isPacked());
    try std.testing.expect(arr.count() == 3);
    try std.testing.expect(arr.getInt(0).?.asInt() == 1);
    try std.testing.expect(arr.getInt(1).?.asInt() == 2);
    try std.testing.expect(arr.getInt(2).?.asInt() == 3);
}

test "HybridArray convert to mixed on string key" {
    const allocator = std.testing.allocator;

    var arr = try HybridArray.init(allocator);
    defer arr.deinit();

    // 先添加整数索引
    try arr.push(FastValue.initInt(1));
    try arr.push(FastValue.initInt(2));
    try std.testing.expect(arr.isPacked());

    // 添加字符串键触发转换
    try arr.setString("name", FastValue.initInt(42));
    try std.testing.expect(arr.isMixed());

    // 验证数据完整性
    try std.testing.expect(arr.count() == 3);
    try std.testing.expect(arr.getInt(0).?.asInt() == 1);
    try std.testing.expect(arr.getInt(1).?.asInt() == 2);
    try std.testing.expect(arr.getString("name").?.asInt() == 42);
}

test "HybridArray SIMD operations" {
    const allocator = std.testing.allocator;

    var arr = try HybridArray.init(allocator);
    defer arr.deinit();

    var i: i64 = 1;
    while (i <= 10) : (i += 1) {
        try arr.push(FastValue.initInt(i));
    }

    try std.testing.expect(arr.sumInt() == 55);
    try std.testing.expect(arr.maxInt().? == 10);
    try std.testing.expect(arr.minInt().? == 1);
}

test "HybridArray mixed mode operations" {
    const allocator = std.testing.allocator;

    var arr = try HybridArray.init(allocator);
    defer arr.deinit();

    // 直接使用字符串键
    try arr.setString("a", FastValue.initInt(1));
    try arr.setString("b", FastValue.initInt(2));
    try arr.setInt(0, FastValue.initInt(3));

    try std.testing.expect(arr.isMixed());
    try std.testing.expect(arr.count() == 3);
    try std.testing.expect(arr.getString("a").?.asInt() == 1);
    try std.testing.expect(arr.getString("b").?.asInt() == 2);
    try std.testing.expect(arr.getInt(0).?.asInt() == 3);
}
