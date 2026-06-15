//! AOT并发运行时 - 存根实现（不支持Fiber/协程）
//!
//! 按照项目约束：代码实现/脚本测试不考虑Fiber和生成器

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ExecutionContext = struct {
    called_class: ?usize = null,
    scope_class: ?usize = null,
};

threadlocal var execution_context: ExecutionContext = .{};

pub fn getExecutionContext() *ExecutionContext {
    return &execution_context;
}

pub const CoroutineState = enum { ready, running, blocked, finished };

pub const Coroutine = struct {
    id: u64,
    state: CoroutineState,
    func_ptr: *const fn (?*anyopaque) anyerror!void,
    context: ?*anyopaque,
    result: ?*anyopaque,
    err: ?anyerror,
    allocator: Allocator,

    pub fn init(allocator: Allocator, id: u64, func: *const fn (?*anyopaque) anyerror!void, ctx: ?*anyopaque) !*Coroutine {
        const coro = try allocator.create(Coroutine);
        coro.* = .{
            .id = id,
            .state = .ready,
            .func_ptr = func,
            .context = ctx,
            .result = null,
            .err = null,
            .allocator = allocator,
        };
        return coro;
    }

    pub fn deinit(self: *Coroutine) void {
        self.allocator.destroy(self);
    }
};

pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: std.ArrayList(T),
        capacity: usize,
        closed: bool,
        allocator: Allocator,

        pub fn init(allocator: Allocator, cap: usize) !*Self {
            const ch = try allocator.create(Self);
            ch.* = .{
                .buffer = std.ArrayList(T).empty,
                .capacity = if (cap == 0) 1 else cap,
                .closed = false,
                .allocator = allocator,
            };
            return ch;
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        pub fn send(self: *Self, value: T) !void {
            if (self.closed) return error.ChannelClosed;
            try self.buffer.append(self.allocator, value);
        }

        pub fn trySend(self: *Self, value: T) !bool {
            if (self.closed) return error.ChannelClosed;
            if (self.buffer.items.len >= self.capacity) return false;
            try self.buffer.append(self.allocator, value);
            return true;
        }

        pub fn recv(self: *Self) !T {
            if (self.buffer.items.len == 0) return error.ChannelClosed;
            const value = self.buffer.orderedRemove(0);
            return value;
        }

        pub fn close(self: *Self) void {
            self.closed = true;
        }

        pub fn tryRecv(self: *Self) ?T {
            if (self.buffer.items.len == 0) return null;
            return self.buffer.orderedRemove(0);
        }

        pub fn isClosed(self: *Self) bool {
            return self.closed;
        }

        pub fn len(self: *Self) usize {
            return self.buffer.items.len;
        }

        pub fn getCapacity(self: *Self) usize {
            return self.capacity;
        }
    };
}

pub const Scheduler = struct {
    ready_queue: std.ArrayList(*Coroutine),
    allocator: Allocator,
    next_id: std.atomic.Value(u64),
    active_count: std.atomic.Value(u64),
    running: std.atomic.Value(bool),

    pub fn init(allocator: Allocator) !*Scheduler {
        const sched = try allocator.create(Scheduler);
        sched.* = .{
            .ready_queue = std.ArrayList(*Coroutine).empty,
            .allocator = allocator,
            .next_id = std.atomic.Value(u64).init(1),
            .active_count = std.atomic.Value(u64).init(0),
            .running = std.atomic.Value(bool).init(true),
        };
        return sched;
    }

    pub fn deinit(self: *Scheduler) void {
        self.running.store(false, .seq_cst);
        for (self.ready_queue.items) |coro| coro.deinit();
        self.ready_queue.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn drain(self: *Scheduler, timeout_ms: ?u64) bool {
        _ = timeout_ms;
        return self.ready_queue.items.len == 0 and self.active_count.load(.acquire) == 0;
    }

    pub fn start(self: *Scheduler, num_workers: usize) !void {
        _ = self;
        _ = num_workers;
    }

    pub fn ensureStarted(self: *Scheduler) !void {
        _ = self;
    }

    pub fn spawn(self: *Scheduler, func: *const fn (?*anyopaque) anyerror!void, ctx: ?*anyopaque) !u64 {
        const id = self.next_id.fetchAdd(1, .seq_cst);
        const coro = try Coroutine.init(self.allocator, id, func, ctx);
        try self.ready_queue.append(self.allocator, coro);
        return id;
    }

    pub fn join(self: *Scheduler, id: u64) anyerror!void {
        _ = self;
        _ = id;
    }

    pub fn waitAll(self: *Scheduler) void {
        _ = self.drain(null);
    }
};

var global_scheduler: ?*Scheduler = null;
var scheduler_mutex: std.atomic.Mutex = .unlocked;

pub fn getScheduler(allocator: Allocator) !*Scheduler {
    while (!scheduler_mutex.tryLock()) std.atomic.spinLoopHint();
    defer scheduler_mutex.unlock();

    if (global_scheduler == null) {
        global_scheduler = try Scheduler.init(allocator);
    }
    return global_scheduler.?;
}

pub fn shutdownScheduler() void {
    while (!scheduler_mutex.tryLock()) std.atomic.spinLoopHint();
    defer scheduler_mutex.unlock();

    if (global_scheduler) |sched| {
        _ = sched.drain(null);
        sched.deinit();
        global_scheduler = null;
    }
}

pub fn drainScheduler(timeout_ms: ?u64) bool {
    while (!scheduler_mutex.tryLock()) std.atomic.spinLoopHint();
    defer scheduler_mutex.unlock();
    if (global_scheduler) |s| {
        return s.drain(timeout_ms);
    }
    return true;
}

pub const SelectOp = enum { send, recv };

pub const SelectCase = struct {
    channel_ptr: usize,
    op: SelectOp,
    value: ?anyopaque,
};

pub fn selectChannels(cases: []const SelectCase, timeout_ms: ?u64) !usize {
    _ = timeout_ms;
    if (cases.len == 0) return error.NoCases;
    return 0;
}
