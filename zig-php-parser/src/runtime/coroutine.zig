const std = @import("std");

pub const Coroutine = struct {
    stack: []u8,
    state: State,
    // Opaque pointer to the VM execution context (registers, etc.)
    context: *anyopaque,

    pub const State = enum {
        Ready,
        Running,
        Waiting,
        Done,
    };

    pub fn init(allocator: std.mem.Allocator, stack_size: usize) !*Coroutine {
        var self = try allocator.create(Coroutine);
        errdefer allocator.destroy(self);

        self.* = .{
            .stack = try allocator.alloc(u8, stack_size),
            .state = .Ready,
            .context = undefined,
        };
        return self;
    }

    pub fn deinit(self: *Coroutine, allocator: std.mem.Allocator) void {
        allocator.free(self.stack);
        allocator.destroy(self);
    }
};
