const std = @import("std");

const std = @import("std");
const context = @import("context.zig");
const Value = @import("types.zig").Value;

var next_coroutine_id: u64 = 1;

/// Represents a single green thread of execution.
pub const Coroutine = struct {
    id: u64,
    stack: []u8,
    state: State,
    context: context.Context,
    allocator: std.mem.Allocator,

    func_name: []const u8,
    args: []const Value,

    // The entry point for the 'main' coroutine.
    entry_node: ?u32 = null,

    pub const State = enum {
        Ready,
        Running,
        Suspended,
        Waiting,
        Done,
    };

    pub fn create(allocator: std.mem.Allocator, func_name: []const u8, args: []const Value) !*Coroutine {
        const stack_size = 1024 * 1024;
        var self = try allocator.create(Coroutine);
        errdefer allocator.destroy(self);

        self.* = .{
            .id = next_coroutine_id,
            .stack = try allocator.alloc(u8, stack_size),
            .state = .Ready,
            .context = undefined,
            .allocator = allocator,
            .func_name = func_name,
            .args = args,
        };
        next_coroutine_id += 1;
        return self;
    }

    /// Deallocates the resources used by the Coroutine.
    pub fn deinit(self: *Coroutine) void {
        self.allocator.free(self.stack);
        self.allocator.destroy(self);
    }
};
