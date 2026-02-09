const std = @import("std");
const Allocator = std.mem.Allocator;

/// Robin Hood 哈希表实现
pub fn RobinHoodHashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        pub const Entry = struct {
            key: K,
            value: V,
            psl: u32, // Probe Sequence Length
        };

        entries: []?Entry,
        len: usize,
        capacity: usize,
        allocator: Allocator,
        load_factor: f32 = 0.75,

        pub fn init(allocator: Allocator, capacity: usize) !Self {
            const entries = try allocator.alloc(?Entry, capacity);
            @memset(entries, null);

            return Self{
                .entries = entries,
                .len = 0,
                .capacity = capacity,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.entries);
        }

        fn hash(self: *Self, key: K) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            
            // 处理字符串切片
            if (K == []const u8) {
                hasher.update(key);
            } else {
                std.hash.autoHash(&hasher, key);
            }
            
            return hasher.final();
        }

        pub fn put(self: *Self, key: K, value: V) Allocator.Error!void {
            if (@as(f32, @floatFromInt(self.len)) / @as(f32, @floatFromInt(self.capacity)) > self.load_factor) {
                try self.resize();
            }

            var entry = Entry{ .key = key, .value = value, .psl = 0 };
            var idx = self.hash(key) % self.capacity;

            while (true) {
                if (self.entries[idx]) |*existing| {
                    if (std.meta.eql(existing.key, key)) {
                        // 更新现有键
                        existing.value = value;
                        return;
                    }

                    // Robin Hood: 如果当前条目的 PSL 更小，交换
                    if (existing.psl < entry.psl) {
                        const temp = existing.*;
                        existing.* = entry;
                        entry = temp;
                    }

                    entry.psl += 1;
                    idx = (idx + 1) % self.capacity;
                } else {
                    // 找到空槽
                    self.entries[idx] = entry;
                    self.len += 1;
                    return;
                }
            }
        }

        pub fn get(self: *Self, key: K) ?V {
            var idx = self.hash(key) % self.capacity;
            var psl: u32 = 0;

            while (self.entries[idx]) |entry| {
                if (std.meta.eql(entry.key, key)) {
                    return entry.value;
                }

                // 如果 PSL 超过了条目的 PSL，键不存在
                if (psl > entry.psl) {
                    return null;
                }

                psl += 1;
                idx = (idx + 1) % self.capacity;
            }

            return null;
        }

        pub fn remove(self: *Self, key: K) bool {
            var idx = self.hash(key) % self.capacity;
            var psl: u32 = 0;

            while (self.entries[idx]) |entry| {
                if (std.meta.eql(entry.key, key)) {
                    // 找到键，删除并后移
                    self.entries[idx] = null;
                    self.len -= 1;

                    // 后移元素
                    var next_idx = (idx + 1) % self.capacity;
                    while (self.entries[next_idx]) |next_entry| {
                        if (next_entry.psl == 0) break;

                        var moved = next_entry;
                        moved.psl -= 1;
                        self.entries[idx] = moved;
                        self.entries[next_idx] = null;

                        idx = next_idx;
                        next_idx = (next_idx + 1) % self.capacity;
                    }

                    return true;
                }

                if (psl > entry.psl) {
                    return false;
                }

                psl += 1;
                idx = (idx + 1) % self.capacity;
            }

            return false;
        }

        fn resize(self: *Self) Allocator.Error!void {
            const new_capacity = self.capacity * 2;
            const new_entries = try self.allocator.alloc(?Entry, new_capacity);
            @memset(new_entries, null);

            const old_entries = self.entries;

            self.entries = new_entries;
            self.capacity = new_capacity;
            self.len = 0;

            // 重新插入所有条目
            for (old_entries) |maybe_entry| {
                if (maybe_entry) |entry| {
                    try self.put(entry.key, entry.value);
                }
            }

            self.allocator.free(old_entries);
        }
    };
}
