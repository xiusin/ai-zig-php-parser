const std = @import("std");
const Value = @import("types.zig").Value;

pub fn Box(comptime T: type) type {
    return struct {
        ref_count: std.atomic.Value(u32),
        data: T,
    };
}

pub const MemoryManager = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MemoryManager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *MemoryManager) void {
        _ = self;
    }

    pub fn allocString(self: *MemoryManager, data: []const u8) !*Box([]const u8) {
        const data_copy = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(data_copy);
        const box = try self.allocator.create(Box([]const u8));
        box.* = .{
            .ref_count = std.atomic.Value(u32).init(1),
            .data = data_copy,
        };
        return box;
    }

    pub fn allocArray(self: *MemoryManager) !*Box(Value.Array) {
        const box = try self.allocator.create(Box(Value.Array));
        box.* = .{
            .ref_count = std.atomic.Value(u32).init(1),
            .data = Value.Array.init(self.allocator),
        };
        return box;
    }
};

pub fn incRef(val: Value) void {
    switch (val.tag) {
        .string => _ = val.data.string.ref_count.fetchAdd(1, .monotonic),
        .array => _ = val.data.array.ref_count.fetchAdd(1, .monotonic),
        .channel => _ = val.data.channel.ref_count.fetchAdd(1, .monotonic),
        else => {},
    }
}

pub fn decRef(mm: *MemoryManager, val: Value) void {
    switch (val.tag) {
        .string => {
            if (val.data.string.ref_count.fetchSub(1, .release) == 1) {
                @fence(.acquire);
                mm.allocator.free(val.data.string.data);
                mm.allocator.destroy(val.data.string);
            }
        },
        .array => {
            if (val.data.array.ref_count.fetchSub(1, .release) == 1) {
                @fence(.acquire);
                var it = val.data.array.data.iterator();
                while (it.next()) |entry| {
                    decRef(mm, entry.key_ptr.*);
                    decRef(mm, entry.value_ptr.*);
                }
                val.data.array.data.deinit();
                mm.allocator.destroy(val.data.array);
            }
        },
        .channel => {
            if (val.data.channel.ref_count.fetchSub(1, .release) == 1) {
                @fence(.acquire);
                val.data.channel.data.buffer.deinit(mm.allocator);
                val.data.channel.data.send_waiters.deinit(mm.allocator);
                val.data.channel.data.recv_waiters.deinit(mm.allocator);
                mm.allocator.destroy(val.data.channel);
            }
        },
        else => {},
    }
}
