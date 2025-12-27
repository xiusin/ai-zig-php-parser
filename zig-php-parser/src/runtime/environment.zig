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
    
    fn retainValue(self: *Environment, value: Value) void {
        _ = self;
        switch (value.tag) {
            .string => _ = value.data.string.retain(),
            .array => _ = value.data.array.retain(),
            .object => _ = value.data.object.retain(),
            .resource => _ = value.data.resource.retain(),
            .user_function => _ = value.data.user_function.retain(),
            .closure => _ = value.data.closure.retain(),
            .arrow_function => _ = value.data.arrow_function.retain(),
            else => {},
        }
    }
    
    fn releaseValue(self: *Environment, value: Value) void {
        switch (value.tag) {
            .string => value.data.string.release(self.allocator),
            .array => value.data.array.release(self.allocator),
            .object => value.data.object.release(self.allocator),
            .resource => value.data.resource.release(self.allocator),
            .user_function => value.data.user_function.release(self.allocator),
            .closure => value.data.closure.release(self.allocator),
            .arrow_function => value.data.arrow_function.release(self.allocator),
            else => {},
        }
    }
};
