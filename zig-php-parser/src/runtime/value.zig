const std = @import("std");
const gc = @import("gc.zig");

pub const Value = struct {
    tag: Tag,
    data: Data,

    const Self = @This();

    pub const Array = std.ArrayHashMap(Self, Self, Context, false);

    pub const Context = struct {
        pub fn hash(_: Context, key: Value) u32 {
            return switch (key.tag) {
                .integer => @truncate(std.hash.Wyhash.hash(0, std.mem.asBytes(&key.data.integer))),
                .string => @truncate(std.hash.Wyhash.hash(0, key.data.string.data)),
                else => @panic("Invalid key type for array"),
            };
        }

        pub fn eql(_: Context, a: Value, b: Value, _: usize) bool {
            if (a.tag != b.tag) return false;
            return switch (a.tag) {
                .integer => a.data.integer == b.data.integer,
                .string => std.mem.eql(u8, a.data.string.data, b.data.string.data),
                else => false,
            };
        }
    };

    pub const Tag = enum {
        null,
        boolean,
        integer,
        float,
        string,
        array,
    };

    pub const Data = union {
        boolean: bool,
        integer: i64,
        float: f64,
        string: *gc.Box([]const u8),
        array: *gc.Box(Array),
    };
};
