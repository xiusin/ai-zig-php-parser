const std = @import("std");
const Coroutine = @import("coroutine.zig").Coroutine;
const context = @import("context.zig");

/// The M:N scheduler responsible for managing and executing coroutines.
pub const Scheduler = struct {
    allocator: std.mem.Allocator,

    run_queue: std.ArrayListUnmanaged(*Coroutine),
    wait_queue: std.ArrayListUnmanaged(*Coroutine),

    current_coroutine: ?*Coroutine,

    main_context: context.Context,

    php_ctx: *const @import("../compiler/parser.zig").PHPContext,
    function_table: std.StringHashMap(u32),

    /// Initializes a new Scheduler.
    pub fn init(allocator: std.mem.Allocator, php_ctx: *const @import("../compiler/parser.zig").PHPContext) Scheduler {
        var scheduler = Scheduler{
            .allocator = allocator,
            .run_queue = .{},
            .wait_queue = .{},
            .current_coroutine = null,
            .main_context = undefined,
            .php_ctx = php_ctx,
            .function_table = std.StringHashMap(u32).init(allocator),
        };

        // Pre-populate the function table
        const root_node = scheduler.php_ctx.nodes.items[scheduler.php_ctx.root_node];
        const stmts = root_node.data.root.stmts;
        for (stmts) |stmt_idx| {
            const node = scheduler.php_ctx.nodes.items[stmt_idx];
            if (node.tag == .function_decl) {
                const name_node = scheduler.php_ctx.nodes.items[node.data.function_decl.name];
                const name_id = name_node.data.variable.name;
                const name = scheduler.php_ctx.string_pool.keys()[name_id];
                scheduler.function_table.put(name, stmt_idx) catch @panic("Failed to populate function table");
            }
        }

        return scheduler;
    }

    /// Deinitializes the scheduler, freeing any remaining coroutines.
    pub fn deinit(self: *Scheduler) void {
        for (self.run_queue.items) |co| {
            co.deinit();
        }
        self.run_queue.deinit(self.allocator);

        for (self.wait_queue.items) |co| {
            co.deinit();
        }
        self.wait_queue.deinit(self.allocator);
        self.function_table.deinit();
    }

    pub fn schedule(self: *Scheduler, co: *Coroutine) !void {
        try self.run_queue.append(self.allocator, co);
    }

    /// The main execution loop of the scheduler.
    pub fn run(self: *Scheduler, root_node_idx: u32) !void {
        const main_co = try Coroutine.create(self.allocator, "main", &.{});
        main_co.entry_node = root_node_idx;
        try self.schedule(main_co);

        context.get(&self.main_context);

        while (self.run_queue.items.len > 0) {
            const co = self.run_queue.orderedRemove(0);
            self.current_coroutine = co;

            switch (co.state) {
                .Ready => {
                    context.make(
                        &co.context,
                        co.stack,
                        coroutine_entry_trampoline,
                        coroutine_entry,
                        self,
                        co,
                    );
                    co.state = .Running;
                    context.swap(&self.main_context, &co.context);
                },
                .Suspended => {
                    co.state = .Running;
                    context.swap(&self.main_context, &co.context);
                },
                else => @panic("Coroutine in invalid state"),
            }

            if (co.state == .Done) {
                self.current_coroutine = null;
                co.deinit();
            }
        }
    }

    /// Stops the current coroutine and switches to the scheduler's context.
    pub fn yield(self: *Scheduler) void {
        const current = self.current_coroutine orelse return;
        current.state = .Suspended;
        self.run_queue.append(self.allocator, current) catch @panic("Failed to re-queue coroutine");
        context.swap(&current.context, &self.main_context);
    }

    pub fn block(self: *Scheduler) void {
        const current = self.current_coroutine orelse return;
        current.state = .Waiting;
        self.wait_queue.append(self.allocator, current) catch @panic("Failed to add coroutine to wait queue");
        context.swap(&current.context, &self.main_context);
    }

    pub fn wakeUp(self: *Scheduler, co: *Coroutine) !void {
        for (self.wait_queue.items) |c, i| {
            if (c.id == co.id) {
                _ = self.wait_queue.orderedRemove(i);
                co.state = .Ready;
                try self.run_queue.append(self.allocator, co);
                return;
            }
        }
    }
};
extern fn coroutine_entry_trampoline(
    func_hi: c_int,
    func_lo: c_int,
    arg1_hi: c_int,
    arg1_lo: c_int,
    arg2_hi: c_int,
    arg2_lo: c_int,
) void {
    const func_addr = (@as(u64, @intCast(func_hi)) << 32) | @as(u64, @intCast(func_lo));
    const arg1_addr = (@as(u64, @intCast(arg1_hi)) << 32) | @as(u64, @intCast(arg1_lo));
    const arg2_addr = (@as(u64, @intCast(arg2_hi)) << 32) | @as(u64, @intCast(arg2_lo));

    const func: fn(*Scheduler, *Coroutine) void = @ptrFromInt(func_addr);
    const arg1: *Scheduler = @ptrFromInt(arg1_addr);
    const arg2: *Coroutine = @ptrFromInt(arg2_addr);

    func(arg1, arg2);
}

fn coroutine_entry(scheduler: *Scheduler, co: *Coroutine) void {
    const Vm = @import("vm.zig").Vm;
    var vm = Vm.init(scheduler.allocator, scheduler.php_ctx, scheduler, co);
    defer vm.deinit();

    if (std.mem.eql(u8, co.func_name, "main")) {
        // This is the main script coroutine.
        if (co.entry_node) |node_idx| {
            _ = vm.eval(node_idx) catch |err| {
                std.debug.print("uncaught error in main coroutine: {any}\n", .{err});
            };
        }
    } else {
        // This is a coroutine for a specific function.
        if (scheduler.function_table.get(co.func_name)) |idx| {
            _ = vm.eval(idx) catch |err| {
                std.debug.print("uncaught error in coroutine {d}: {any}\n", .{co.id, err});
            };
        } else {
            std.debug.print("function '{s}' not found for coroutine {d}\n", .{co.func_name, co.id});
        }
    }

    co.state = .Done;

    context.swap(&co.context, &scheduler.main_context);
}
