const std = @import("std");
const gc = @import("gc.zig");
const Scheduler = @import("scheduler.zig").Scheduler;
const Coroutine = @import("coroutine.zig").Coroutine;

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
        send_waiters: std.ArrayListUnmanaged(*Coroutine),
        recv_waiters: std.ArrayListUnmanaged(*Coroutine),

        pub fn send(self: *Channel, sched: *Scheduler, value: Value) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.recv_waiters.items.len > 0) {
                const waiter = self.recv_waiters.orderedRemove(0);
                // This is a simplified handoff. A real implementation would need to
                // handle the value transfer more robustly.
                // For now, we assume the waiter will find the value in the buffer.
                try self.buffer.append(sched.allocator, value);
                try sched.wakeUp(waiter);
                return;
            }

            if (self.buffer.items.len < self.capacity) {
                try self.buffer.append(sched.allocator, value);
                return;
            }

            const current_co = sched.current_coroutine orelse @panic("no active coroutine to block");
            try self.send_waiters.append(sched.allocator, current_co);
            sched.block();
        }

        pub fn receive(self: *Channel, sched: *Scheduler) !Value {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.buffer.items.len > 0) {
                const value = self.buffer.orderedRemove(0);
                if (self.send_waiters.items.len > 0) {
                    const waiter = self.send_waiters.orderedRemove(0);
                    // Again, simplified value transfer.
                    try sched.wakeUp(waiter);
                }
                return value;
            }

            if (self.send_waiters.items.len > 0) {
                const waiter = self.send_waiters.orderedRemove(0);
                try sched.wakeUp(waiter);
                // This assumes the woken sender places its value in the buffer.
                // A more robust implementation would be needed here.
                return self.buffer.orderedRemove(0);
            }

            const current_co = sched.current_coroutine orelse @panic("no active coroutine to block");
            try self.recv_waiters.append(sched.allocator, current_co);
            sched.block();

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
