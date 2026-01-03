const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

pub const Environment = struct {
    allocator: std.mem.Allocator,
    vars: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) Environment {
        return .{
            .allocator = allocator,
            .vars = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Environment) void {
        // Release all stored values before deiniting the hashmap
        var iterator = self.vars.iterator();
        while (iterator.next()) |entry| {
            self.releaseValue(entry.value_ptr.*);
        }
        self.vars.deinit();
    }

    pub fn set(self: *Environment, name: []const u8, value: Value) !void {
        // If variable already exists, release its reference
        if (self.vars.get(name)) |old_value| {
            self.releaseValue(old_value);
        }

        // Retain the new value and store it
        self.retainValue(value);
        try self.vars.put(name, value);
    }

    pub fn get(self: *Environment, name: []const u8) ?Value {
        return self.vars.get(name);
    }

    pub fn remove(self: *Environment, name: []const u8) bool {
        if (self.vars.fetchRemove(name)) |entry| {
            // Release the value's reference
            self.releaseValue(entry.value);
            return true;
        }
        return false;
    }

    fn retainValue(self: *Environment, value: Value) void {
        _ = self;
        _ = value.retain();
    }

    fn releaseValue(self: *Environment, value: Value) void {
        value.release(self.allocator);
    }
};
