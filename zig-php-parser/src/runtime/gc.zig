const std = @import("std");
const Value = @import("types.zig").Value;

pub fn Box(comptime T: type) type {
    return struct {
        ref_count: u32,
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
        const box = try self.allocator.create(Box([]const u8));
        box.* = .{
            .ref_count = 1,
            .data = data_copy,
        };
        return box;
    }

    pub fn allocArray(self: *MemoryManager) !*Box(Value.Array) {
        const box = try self.allocator.create(Box(Value.Array));
        box.* = .{
            .ref_count = 1,
            .data = Value.Array.init(self.allocator),
        };
        return box;
    }
};

pub const Header = struct {
    ref_count: u32,
};

pub fn incRef(comptime T: type) fn (ptr: T) void {
    return struct {
        fn anon(ptr: T) void {
            ptr.ref_count += 1;
        }
    }.anon;
}

pub fn decRef(mm: *MemoryManager, val: Value) void {
    switch (val.tag) {
        .string => {
            val.data.string.ref_count -= 1;
            if (val.data.string.ref_count == 0) {
                std.debug.print("String freed at address: {any}\n", .{val.data.string});
                mm.allocator.free(val.data.string.data);
                mm.allocator.destroy(val.data.string);
            }
        },
        .array => {
            val.data.array.ref_count -= 1;
            if (val.data.array.ref_count == 0) {
                std.debug.print("Array freed at address: {any}\n", .{val.data.array});
                var it = val.data.array.data.iterator();
                while (it.next()) |entry| {
                    decRef(mm, entry.key_ptr.*);
                    decRef(mm, entry.value_ptr.*);
                }
                val.data.array.data.deinit();
                mm.allocator.destroy(val.data.array);
            }
        },
        else => {},
    }
}
