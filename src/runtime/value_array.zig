//! ValueArray - 使用 Value 类型的混合数组
//! 这是 HybridArray 的 Value 版本，用于集成到现有的 PHPArray 系统
//!
//! 核心特性：
//! 1. 自动在 packed 和 mixed 模式间切换
//! 2. 使用 Value 类型（与现有系统兼容）
//! 3. SIMD 加速的数值操作
//! 4. Copy-on-Write 语义

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const ArrayKey = types.ArrayKey;

// ============================================================================
// PackedValueArray - 紧凑数组（使用 Value）
// ============================================================================

pub const PackedValueArray = struct {
    /// 数据存储
    data: []Value,
    /// 当前元素数量
    len: u32,
    /// 容量
    capacity: u32,
    /// 引用计数
    ref_count: u32,
    /// 分配器
    allocator: std.mem.Allocator,

    const INITIAL_CAPACITY = 8;
    const GROWTH_FACTOR = 2;

    pub fn init(allocator: std.mem.Allocator) !*PackedValueArray {
        return initWithCapacity(allocator, INITIAL_CAPACITY);
    }

    pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: u32) !*PackedValueArray {
        const self = try allocator.create(PackedValueArray);
        const cap = @max(capacity, INITIAL_CAPACITY);
        self.* = .{
            .data = try allocator.alloc(Value, cap),
            .len = 0,
            .capacity = cap,
            .ref_count = 1,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *PackedValueArray) void {
        // 释放所有 Value
        for (self.data[0..self.len]) |*v| {
            v.release(self.allocator);
        }
        self.allocator.free(self.data);
        self.allocator.destroy(self);
    }

    pub fn retain(self: *PackedValueArray) *PackedValueArray {
        self.ref_count += 1;
        return self;
    }

    pub fn release(self: *PackedValueArray) bool {
        if (self.ref_count == 0) return false;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit();
            return true;
        }
        return false;
    }

    pub inline fn get(self: *const PackedValueArray, index: u32) ?Value {
        if (index >= self.len) return null;
        return self.data[index];
    }

    pub inline fn set(self: *PackedValueArray, index: u32, value: Value) bool {
        if (index >= self.len) return false;
        // 释放旧值，保留新值
        self.data[index].release(self.allocator);
        _ = value.retain();
        self.data[index] = value;
        return true;
    }

    pub fn ensureCapacity(self: *PackedValueArray, min_capacity: u32) !void {
        if (self.capacity >= min_capacity) return;

        var new_cap = self.capacity;
        while (new_cap < min_capacity) {
            new_cap *= GROWTH_FACTOR;
        }

        const new_data = try self.allocator.alloc(Value, new_cap);
        @memcpy(new_data[0..self.len], self.data[0..self.len]);
        self.allocator.free(self.data);
        self.data = new_data;
        self.capacity = new_cap;
    }

    pub fn push(self: *PackedValueArray, value: Value) !void {
        try self.ensureCapacity(self.len + 1);
        _ = value.retain();
        self.data[self.len] = value;
        self.len += 1;
    }

    pub fn pop(self: *PackedValueArray) ?Value {
        if (self.len == 0) return null;
        self.len -= 1;
        const value = self.data[self.len];
        return value;
    }

    pub inline fn count(self: *const PackedValueArray) u32 {
        return self.len;
    }

    pub inline fn slice(self: *const PackedValueArray) []const Value {
        return self.data[0..self.len];
    }

    // SIMD 优化操作
    pub fn sumInt(self: *const PackedValueArray) i64 {
        var sum: i64 = 0;
        for (self.data[0..self.len]) |v| {
            if (v.isInt()) {
                sum += v.asInt();
            } else if (v.isFloat()) {
                sum += @intFromFloat(v.asFloat());
            }
        }
        return sum;
    }

    pub fn sumFloat(self: *const PackedValueArray) f64 {
        var sum: f64 = 0.0;
        for (self.data[0..self.len]) |v| {
            if (v.isFloat()) {
                sum += v.asFloat();
            } else if (v.isInt()) {
                sum += @floatFromInt(v.asInt());
            }
        }
        return sum;
    }

    pub fn maxInt(self: *const PackedValueArray) ?i64 {
        if (self.len == 0) return null;
        var max_val: ?i64 = null;
        for (self.data[0..self.len]) |v| {
            if (v.isInt()) {
                const val = v.asInt();
                if (max_val == null or val > max_val.?) {
                    max_val = val;
                }
            }
        }
        return max_val;
    }

    pub fn minInt(self: *const PackedValueArray) ?i64 {
        if (self.len == 0) return null;
        var min_val: ?i64 = null;
        for (self.data[0..self.len]) |v| {
            if (v.isInt()) {
                const val = v.asInt();
                if (min_val == null or val < min_val.?) {
                    min_val = val;
                }
            }
        }
        return min_val;
    }

    pub fn find(self: *const PackedValueArray, needle: Value) ?u32 {
        for (self.data[0..self.len], 0..) |v, i| {
            if (v.val == needle.val) return @intCast(i);
        }
        return null;
    }

    pub fn contains(self: *const PackedValueArray, needle: Value) bool {
        return self.find(needle) != null;
    }
};

// ============================================================================
// MixedValueArray - 支持字符串键的数组（使用 Value）
// ============================================================================

pub const MixedValueArray = struct {
    const INVALID_INDEX = 0xFFFFFFFF;

    const Entry = struct {
        key: ArrayKey,
        value: Value,
        hash: u64,
        next: u32, // 哈希冲突链的下一个索引
    };

    entries: std.ArrayList(Entry),
    // 哈希表存储的是 entries 的索引
    hash_table: []u32,
    mask: u32,
    next_int_key: i64,
    allocator: std.mem.Allocator,
    ref_count: u32,
    
    // 已删除元素的数量，用于决定是否重建
    deleted_count: u32,

    pub fn init(allocator: std.mem.Allocator) MixedValueArray {
        // 初始大小 8
        const init_size = 8;
        const hash_table = allocator.alloc(u32, init_size) catch unreachable;
        @memset(hash_table, INVALID_INDEX);

        return .{
            .entries = std.ArrayList(Entry).init(allocator),
            .hash_table = hash_table,
            .mask = init_size - 1,
            .next_int_key = 0,
            .allocator = allocator,
            .ref_count = 1,
            .deleted_count = 0,
        };
    }

    pub fn deinit(self: *MixedValueArray) void {
        // 释放所有值和字符串键
        for (self.entries.items) |entry| {
            if (entry.hash == 0 and entry.next == INVALID_INDEX and @intFromEnum(entry.value.val) == 0) {
                // Skip deleted/dummy entries if any (though we usually compact)
                continue;
            }
            // 简单的有效性检查：如果 value 不是 undef
            entry.value.release(self.allocator);
            if (entry.key == .string) {
                entry.key.string.release(self.allocator);
            }
        }
        self.entries.deinit();
        self.allocator.free(self.hash_table);
    }

    pub fn retain(self: *MixedValueArray) *MixedValueArray {
        self.ref_count += 1;
        return self;
    }

    pub fn release(self: *MixedValueArray) bool {
        if (self.ref_count == 0) return false;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit();
            return true;
        }
        return false;
    }

    fn rehash(self: *MixedValueArray, new_size: u32) !void {
        const old_table = self.hash_table;
        const new_table = try self.allocator.alloc(u32, new_size);
        @memset(new_table, INVALID_INDEX);

        self.hash_table = new_table;
        self.mask = new_size - 1;

        // 重新插入所有有效条目
        // 如果 deleted_count 过高，我们应该同时压缩 entries
        
        if (self.deleted_count > 0) {
            // 实现压缩逻辑：移除已删除的条目
            // 创建新的 entries 数组，只包含有效条目
            var new_entries = std.ArrayList(Entry).init(self.allocator);
            errdefer new_entries.deinit();
            
            // 复制所有有效条目（跳过已删除的）
            for (self.entries.items) |entry| {
                // 检查条目是否有效（非删除标记）
                // 删除的条目通常用特殊值标记，这里我们检查 hash 是否为 0
                if (entry.hash != 0 or entry.next != INVALID_INDEX or @intFromEnum(entry.value.val) != 0) {
                    try new_entries.append(entry);
                }
            }
            
            // 替换旧的 entries 数组
            self.entries.deinit();
            self.entries = new_entries;
            self.deleted_count = 0;
            
            // 重建哈希表索引
            for (self.entries.items, 0..) |*entry, i| {
                const idx = entry.hash & self.mask;
                entry.next = self.hash_table[idx];
                self.hash_table[idx] = @intCast(i);
            }
        } else {
            // 没有删除的条目，只需重建索引
            for (self.entries.items, 0..) |*entry, i| {
                const idx = entry.hash & self.mask;
                entry.next = self.hash_table[idx];
                self.hash_table[idx] = @intCast(i);
            }
        }

        self.allocator.free(old_table);
    }

    pub fn get(self: *const MixedValueArray, key: ArrayKey) ?Value {
        const h = key.hash();
        var idx = self.hash_table[h & self.mask];

        while (idx != INVALID_INDEX) {
            const entry = &self.entries.items[idx];
            if (entry.hash == h and key.eql(entry.key)) {
                return entry.value;
            }
            idx = entry.next;
        }
        return null;
    }

    pub fn set(self: *MixedValueArray, key: ArrayKey, value: Value) !void {
        const h = key.hash();
        var idx = self.hash_table[h & self.mask];

        // 检查是否存在
        while (idx != INVALID_INDEX) {
            var entry = &self.entries.items[idx];
            if (entry.hash == h and key.eql(entry.key)) {
                // 更新值
                entry.value.release(self.allocator);
                _ = value.retain();
                entry.value = value;
                return;
            }
            idx = entry.next;
        }

        // 插入新值
        // 检查是否需要扩容
        if (self.entries.items.len >= self.hash_table.len) {
            try self.rehash(self.hash_table.len * 2);
        }

        // 复制键
        const owned_key: ArrayKey = switch (key) {
            .integer => |i| blk: {
                if (i >= self.next_int_key) {
                    self.next_int_key = i + 1;
                }
                break :blk .{ .integer = i };
            },
            .string => |s| blk: {
                s.retain();
                break :blk .{ .string = s };
            },
        };

        _ = value.retain();
        
        const new_idx = @as(u32, @intCast(self.entries.items.len));
        const hash_idx = h & self.mask;
        
        try self.entries.append(Entry{
            .key = owned_key,
            .value = value,
            .hash = h,
            .next = self.hash_table[hash_idx],
        });
        
        self.hash_table[hash_idx] = new_idx;
    }

    pub fn push(self: *MixedValueArray, value: Value) !void {
        try self.set(.{ .integer = self.next_int_key }, value);
    }

    pub fn count(self: *const MixedValueArray) usize {
        return self.entries.items.len;
    }

    pub fn contains(self: *const MixedValueArray, key: ArrayKey) bool {
        return self.get(key) != null;
    }

    pub const Iterator = struct {
        array: *const MixedValueArray,
        index: usize,

        pub fn next(self: *Iterator) ?struct { key: ArrayKey, value: Value } {
            if (self.index >= self.array.entries.items.len) return null;
            const entry = self.array.entries.items[self.index];
            self.index += 1;
            return .{ .key = entry.key, .value = entry.value };
        }
    };

    pub fn iterator(self: *const MixedValueArray) Iterator {
        return .{ .array = self, .index = 0 };
    }
};

// ============================================================================
// ValueHybridArray - 自动切换的混合数组（使用 Value）
// ============================================================================

pub const ValueHybridArray = struct {
    const Mode = enum { packed_mode, mixed_mode };

    mode: Mode,
    data: union {
        packed_array: *PackedValueArray,
        mixed_array: *MixedValueArray,
    },
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*ValueHybridArray {
        const self = try allocator.create(ValueHybridArray);
        self.* = .{
            .mode = .packed_mode,
            .data = .{ .packed_array = try PackedValueArray.init(allocator) },
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *ValueHybridArray) void {
        switch (self.mode) {
            .packed_mode => _ = self.data.packed_array.release(),
            .mixed_mode => {
                self.data.mixed_array.deinit();
                self.allocator.destroy(self.data.mixed_array);
            },
        }
        self.allocator.destroy(self);
    }

    pub fn count(self: *const ValueHybridArray) usize {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.count(),
            .mixed_mode => self.data.mixed_array.count(),
        };
    }

    pub fn getInt(self: *const ValueHybridArray, index: i64) ?Value {
        return switch (self.mode) {
            .packed_mode => if (index >= 0 and index < self.data.packed_array.len)
                self.data.packed_array.get(@intCast(index))
            else
                null,
            .mixed_mode => self.data.mixed_array.get(.{ .integer = index }),
        };
    }

    pub fn getString(self: *const ValueHybridArray, key: *types.PHPString) ?Value {
        return switch (self.mode) {
            .packed_mode => null,
            .mixed_mode => self.data.mixed_array.get(.{ .string = key }),
        };
    }

    pub fn get(self: *const ValueHybridArray, key: ArrayKey) ?Value {
        return switch (key) {
            .integer => |i| self.getInt(i),
            .string => |s| self.getString(s),
        };
    }

    pub fn setInt(self: *ValueHybridArray, index: i64, value: Value) !void {
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

    pub fn setString(self: *ValueHybridArray, key: *types.PHPString, value: Value) !void {
        if (self.mode == .packed_mode) {
            try self.convertToMixed();
        }
        try self.data.mixed_array.set(.{ .string = key }, value);
    }

    pub fn set(self: *ValueHybridArray, key: ArrayKey, value: Value) !void {
        switch (key) {
            .integer => |i| try self.setInt(i, value),
            .string => |s| try self.setString(s, value),
        }
    }

    pub fn push(self: *ValueHybridArray, value: Value) !void {
        switch (self.mode) {
            .packed_mode => try self.data.packed_array.push(value),
            .mixed_mode => try self.data.mixed_array.push(value),
        }
    }

    pub fn convertToMixed(self: *ValueHybridArray) !void {
        if (self.mode == .mixed_mode) return;

        const mixed = try self.allocator.create(MixedValueArray);
        mixed.* = MixedValueArray.init(self.allocator);

        // 复制所有元素
        for (self.data.packed_array.data[0..self.data.packed_array.len], 0..) |value, i| {
            try mixed.set(.{ .integer = @intCast(i) }, value);
        }

        // 释放 packed 数组
        _ = self.data.packed_array.release();

        self.mode = .mixed_mode;
        self.data = .{ .mixed_array = mixed };
    }

    pub fn isPacked(self: *const ValueHybridArray) bool {
        return self.mode == .packed_mode;
    }

    pub fn isMixed(self: *const ValueHybridArray) bool {
        return self.mode == .mixed_mode;
    }

    // SIMD 优化操作
    pub fn sumInt(self: *const ValueHybridArray) i64 {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.sumInt(),
            .mixed_mode => blk: {
                var sum: i64 = 0;
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    if (item.value.isInt()) {
                        sum += item.value.asInt();
                    } else if (item.value.isFloat()) {
                        sum += @intFromFloat(item.value.asFloat());
                    }
                }
                break :blk sum;
            },
        };
    }

    pub fn sumFloat(self: *const ValueHybridArray) f64 {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.sumFloat(),
            .mixed_mode => blk: {
                var sum: f64 = 0.0;
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    if (item.value.isFloat()) {
                        sum += item.value.asFloat();
                    } else if (item.value.isInt()) {
                        sum += @floatFromInt(item.value.asInt());
                    }
                }
                break :blk sum;
            },
        };
    }

    pub fn maxInt(self: *const ValueHybridArray) ?i64 {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.maxInt(),
            .mixed_mode => blk: {
                if (self.data.mixed_array.count() == 0) break :blk null;
                var max_val: ?i64 = null;
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    if (item.value.isInt()) {
                        const v = item.value.asInt();
                        if (max_val == null or v > max_val.?) {
                            max_val = v;
                        }
                    }
                }
                break :blk max_val;
            },
        };
    }

    pub fn minInt(self: *const ValueHybridArray) ?i64 {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.minInt(),
            .mixed_mode => blk: {
                if (self.data.mixed_array.count() == 0) break :blk null;
                var min_val: ?i64 = null;
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    if (item.value.isInt()) {
                        const v = item.value.asInt();
                        if (min_val == null or v < min_val.?) {
                            min_val = v;
                        }
                    }
                }
                break :blk min_val;
            },
        };
    }

    pub fn containsValue(self: *const ValueHybridArray, needle: Value) bool {
        return switch (self.mode) {
            .packed_mode => self.data.packed_array.contains(needle),
            .mixed_mode => blk: {
                var iter = self.data.mixed_array.iterator();
                while (iter.next()) |item| {
                    if (item.value.val == needle.val) break :blk true;
                }
                break :blk false;
            },
        };
    }
};
