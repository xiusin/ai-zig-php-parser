const std = @import("std");
const gc = @import("gc.zig");

pub const Value = struct {
    tag: Tag,
    data: Data,

    const Self = @This();

    pub fn initNull() Self {
        return .{ .tag = .null, .data = .{} };
    }

    pub fn print(self: Self) !void {
        switch (self.tag) {
            .null => std.debug.print("null", .{}),
            .boolean => std.debug.print("{any}", .{self.data.boolean}),
            .integer => std.debug.print("{any}", .{self.data.integer}),
            .float => std.debug.print("{any}", .{self.data.float}),
            .string => std.debug.print("{s}", .{self.data.string.data}),
            .array => std.debug.print("array", .{}),
            .channel => std.debug.print("channel", .{}),
            .builtin_function => std.debug.print("builtin_function", .{}),
        }
    }

    pub const Array = std.ArrayHashMap(Self, Self, Context, false);

    pub const Channel = struct {
        buffer: std.ArrayListUnmanaged(Value),
        capacity: usize,
        mutex: std.Thread.Mutex,
        // Opaque pointers to Coroutine structs
        send_waiters: std.ArrayListUnmanaged(*anyopaque),
        recv_waiters: std.ArrayListUnmanaged(*anyopaque),

        pub fn send(self: *Channel, scheduler: *anyopaque, value: Value) !void {
            const S = @import("scheduler.zig").Scheduler;
            const sched: *S = @ptrCast(@alignCast(scheduler));

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.buffer.items.len < self.capacity) {
                // Buffer has space, enqueue the value
                try self.buffer.append(sched.allocator, value);

                // If there's a coroutine waiting to receive, wake it up
                if (self.recv_waiters.items.len > 0) {
                    const waiter: *anyopaque = self.recv_waiters.orderedRemove(0);
                    try sched.spawn(@ptrCast(@alignCast(waiter)));
                }
                return;
            }

            // Buffer is full, block the current coroutine
            const current_co = sched.current_coroutine orelse @panic("no active coroutine to block");
            try self.send_waiters.append(sched.allocator, current_co);

            // This is a simplified yield. A real implementation would switch context.
            sched.yield();
        }

        pub fn receive(self: *Channel, scheduler: *anyopaque) !Value {
            const S = @import("scheduler.zig").Scheduler;
            const sched: *S = @ptrCast(@alignCast(scheduler));

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.buffer.items.len > 0) {
                // Buffer has data, dequeue and return it
                const value = self.buffer.orderedRemove(0);

                // If there's a coroutine waiting to send, wake it up
                if (self.send_waiters.items.len > 0) {
                    const waiter: *anyopaque = self.send_waiters.orderedRemove(0);
                    try sched.spawn(@ptrCast(@alignCast(waiter)));
                }
                return value;
            }

            // Buffer is empty, block the current coroutine
            const current_co = sched.current_coroutine orelse @panic("no active coroutine to block");
            try self.recv_waiters.append(sched.allocator, current_co);

            // Simplified yield.
            sched.yield();

            // When woken up, we assume the value is now in the buffer
            return self.buffer.orderedRemove(0);
        }
    };

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
        channel,
        builtin_function,
    };

    pub const BuiltinFn = fn (*anyopaque, []const Value) anyerror!Value;

    pub const Data = union {
        boolean: bool,
        integer: i64,
        float: f64,
        string: *gc.Box([]const u8),
        array: *gc.Box(Array),
        channel: *gc.Box(Channel),
        builtin_function: BuiltinFn,
    };
};
