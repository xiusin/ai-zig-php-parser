const std = @import("std");
const Allocator = std.mem.Allocator;

/// 对象池，复用频繁创建的对象
pub const ObjectPool = struct {
    free_list: std.ArrayList(usize),
    max_size: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, max_size: usize) !ObjectPool {
        return ObjectPool{
            .free_list = try std.ArrayList(usize).initCapacity(allocator, 0),
            .max_size = max_size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ObjectPool) void {
        self.free_list.deinit(self.allocator);
    }

    pub fn acquire(self: *ObjectPool) ?usize {
        if (self.free_list.items.len > 0) {
            return self.free_list.pop();
        }
        return null;
    }

    pub fn release(self: *ObjectPool, obj: usize) !void {
        if (self.free_list.items.len < self.max_size) {
            try self.free_list.append(self.allocator, obj);
        }
    }

    pub fn size(self: *ObjectPool) usize {
        return self.free_list.items.len;
    }
};

/// 字符串驻留表
pub const StringInterner = struct {
    strings: std.StringHashMap([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) StringInterner {
        return StringInterner{
            .strings = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StringInterner) void {
        var it = self.strings.valueIterator();
        while (it.next()) |str| {
            self.allocator.free(str.*);
        }
        self.strings.deinit();
    }

    pub fn intern(self: *StringInterner, str: []const u8) ![]const u8 {
        if (self.strings.get(str)) |interned| {
            return interned;
        }

        const owned = try self.allocator.dupe(u8, str);
        try self.strings.put(owned, owned);
        return owned;
    }

    pub fn contains(self: *StringInterner, str: []const u8) bool {
        return self.strings.contains(str);
    }

    pub fn count(self: *StringInterner) usize {
        return self.strings.count();
    }
};
