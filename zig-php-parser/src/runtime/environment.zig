const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

pub const Environment = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) Environment {
        return .{
            .allocator = allocator,
            .values = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Environment) void {
        self.values.deinit();
    }

    pub fn set(self: *Environment, name: []const u8, value: Value) !void {
        try self.values.put(name, value);
    }

    pub fn get(self: *Environment, name: []const u8) ?Value {
        return self.values.get(name);
    }
};
