const std = @import("std");

/// 内联缓存，用于优化动态调用
pub const InlineCache = struct {
    /// 缓存条目
    pub const Entry = struct {
        type_id: u32,
        target: usize,
        hit_count: u32,
    };

    /// 单态缓存（1 个条目）
    pub const Monomorphic = struct {
        entry: ?Entry = null,

        pub fn lookup(self: *Monomorphic, type_id: u32) ?Entry {
            if (self.entry) |e| {
                if (e.type_id == type_id) {
                    return e;
                }
            }
            return null;
        }

        pub fn update(self: *Monomorphic, type_id: u32, target: usize) void {
            self.entry = .{ .type_id = type_id, .target = target, .hit_count = 1 };
        }

        pub fn incrementHit(self: *Monomorphic) void {
            if (self.entry) |*e| {
                e.hit_count += 1;
            }
        }
    };

    /// 多态缓存（4 个条目）
    pub const Polymorphic = struct {
        entries: [4]?Entry = @splat(null),

        pub fn lookup(self: *Polymorphic, type_id: u32) ?Entry {
            for (self.entries) |maybe_entry| {
                if (maybe_entry) |e| {
                    if (e.type_id == type_id) {
                        return e;
                    }
                }
            }
            return null;
        }

        pub fn update(self: *Polymorphic, type_id: u32, target: usize) void {
            // 查找空槽或最少使用的槽
            var min_idx: usize = 0;
            var min_hits: u32 = std.math.maxInt(u32);

            for (self.entries, 0..) |maybe_entry, i| {
                if (maybe_entry == null) {
                    min_idx = i;
                    break;
                }
                if (maybe_entry.?.hit_count < min_hits) {
                    min_hits = maybe_entry.?.hit_count;
                    min_idx = i;
                }
            }

            self.entries[min_idx] = .{ .type_id = type_id, .target = target, .hit_count = 1 };
        }

        pub fn incrementHit(self: *Polymorphic, type_id: u32) void {
            for (&self.entries) |*maybe_entry| {
                if (maybe_entry.*) |*e| {
                    if (e.type_id == type_id) {
                        e.hit_count += 1;
                        return;
                    }
                }
            }
        }
    };
};
