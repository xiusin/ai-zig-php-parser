const std = @import("std");
const Coroutine = @import("coroutine.zig").Coroutine;

pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    run_queue: std.ArrayListUnmanaged(*Coroutine),
    main_context: *anyopaque,
    current_coroutine: ?*Coroutine,

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .allocator = allocator,
            .run_queue = .{},
            .main_context = undefined,
            .current_coroutine = null,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        // Deallocate any remaining coroutines in the run queue
        for (self.run_queue.items) |co| {
            co.deinit(self.allocator);
        }
        self.run_queue.deinit(self.allocator);
    }

    /// Adds a new coroutine to the scheduler's run queue.
    pub fn spawn(self: *Scheduler, coroutine: *Coroutine) !void {
        try self.run_queue.append(self.allocator, coroutine);
    }

    /// The main scheduling loop.
    pub fn run(self: *Scheduler) !void {
        while (self.run_queue.items.len > 0) {
            const co = self.run_queue.orderedRemove(0);
            self.current_coroutine = co;

            switch (co.state) {
                .Ready, .Waiting => {
                    co.state = .Running;
                    // This is where the context switch would happen.
                    // For now, we'll just placeholder the logic.
                    // switchTo(co.context);
                },
                else => {},
            }
        }
    }

    /// Yields control from the current coroutine back to the scheduler.
    pub fn yield(self: *Scheduler) void {
        if (self.current_coroutine) |co| {
            co.state = .Ready;
            self.run_queue.append(self.allocator, co) catch unreachable;
            // switchTo(self.main_context);
        }
    }
};
