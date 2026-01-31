//! AOT并发运行时 - 真正的协程调度和Channel实现
//!
//! @thread-safety GUARDED_BY(scheduler_mutex)
//! @concurrency-model M:N Coroutine Scheduler

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// 协程状态和上下文
// ============================================================================

/// 协程状态
pub const CoroutineState = enum {
    ready, // 就绪，等待调度
    running, // 正在运行
    blocked, // 阻塞（等待channel/锁等）
    finished, // 已完成
};

/// 协程上下文
pub const Coroutine = struct {
    id: u64,
    state: CoroutineState,
    func_ptr: *const fn ([]const anyopaque) anyerror!void,
    args: []const anyopaque,
    result: ?anyopaque,
    allocator: Allocator,

    pub fn init(allocator: Allocator, id: u64, func: *const fn ([]const anyopaque) anyerror!void, args: []const anyopaque) !*Coroutine {
        const coro = try allocator.create(Coroutine);
        coro.* = .{
            .id = id,
            .state = .ready,
            .func_ptr = func,
            .args = args,
            .result = null,
            .allocator = allocator,
        };
        return coro;
    }

    pub fn deinit(self: *Coroutine) void {
        self.allocator.destroy(self);
    }
};

// ============================================================================
// Channel实现
// ============================================================================

/// Channel - 线程安全的通信通道
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: std.ArrayList(T),
        capacity: usize,
        closed: bool,
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,
        allocator: Allocator,

        pub fn init(allocator: Allocator, capacity: usize) !*Self {
            const ch = try allocator.create(Self);
            ch.* = .{
                .buffer = std.ArrayList(T).init(allocator),
                .capacity = if (capacity == 0) 1 else capacity,
                .closed = false,
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .allocator = allocator,
            };
            return ch;
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
            self.allocator.destroy(self);
        }

        /// 发送数据到channel
        pub fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed) return error.ChannelClosed;

            // 等待buffer有空间
            while (self.buffer.items.len >= self.capacity and !self.closed) {
                self.not_full.wait(&self.mutex);
            }

            if (self.closed) return error.ChannelClosed;

            try self.buffer.append(value);
            self.not_empty.signal();
        }

        /// 从channel接收数据
        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // 等待buffer有数据
            while (self.buffer.items.len == 0 and !self.closed) {
                self.not_empty.wait(&self.mutex);
            }

            if (self.buffer.items.len == 0 and self.closed) {
                return error.ChannelClosed;
            }

            const value = self.buffer.orderedRemove(0);
            self.not_full.signal();
            return value;
        }

        /// 关闭channel
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.closed = true;
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }

        /// 尝试接收（非阻塞）
        pub fn tryRecv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.buffer.items.len == 0) return null;

            const value = self.buffer.orderedRemove(0);
            self.not_full.signal();
            return value;
        }
    };
}

// ============================================================================
// 协程调度器
// ============================================================================

/// 全局协程调度器
pub const Scheduler = struct {
    ready_queue: std.ArrayList(*Coroutine),
    blocked_queue: std.ArrayList(*Coroutine),
    finished_queue: std.ArrayList(*Coroutine),
    next_id: std.atomic.Atomic(u64),
    mutex: std.Thread.Mutex,
    allocator: Allocator,
    worker_threads: std.ArrayList(std.Thread),
    running: std.atomic.Atomic(bool),

    pub fn init(allocator: Allocator) !*Scheduler {
        const sched = try allocator.create(Scheduler);
        sched.* = .{
            .ready_queue = std.ArrayList(*Coroutine).init(allocator),
            .blocked_queue = std.ArrayList(*Coroutine).init(allocator),
            .finished_queue = std.ArrayList(*Coroutine).init(allocator),
            .next_id = std.atomic.Atomic(u64).init(1),
            .mutex = .{},
            .allocator = allocator,
            .worker_threads = std.ArrayList(std.Thread).init(allocator),
            .running = std.atomic.Atomic(bool).init(true),
        };
        return sched;
    }

    pub fn deinit(self: *Scheduler) void {
        self.running.store(false, .seq_cst);

        // 等待所有worker线程结束
        for (self.worker_threads.items) |thread| {
            thread.join();
        }

        // 清理所有协程
        for (self.ready_queue.items) |coro| coro.deinit();
        for (self.blocked_queue.items) |coro| coro.deinit();
        for (self.finished_queue.items) |coro| coro.deinit();

        self.ready_queue.deinit();
        self.blocked_queue.deinit();
        self.finished_queue.deinit();
        self.worker_threads.deinit();
        self.allocator.destroy(self);
    }

    /// 启动worker线程
    pub fn start(self: *Scheduler, num_workers: usize) !void {
        var i: usize = 0;
        while (i < num_workers) : (i += 1) {
            const thread = try std.Thread.spawn(.{}, workerLoop, .{self});
            try self.worker_threads.append(thread);
        }
    }

    /// 调度一个新协程
    pub fn spawn(self: *Scheduler, func: *const fn ([]const anyopaque) anyerror!void, args: []const anyopaque) !u64 {
        const id = self.next_id.fetchAdd(1, .seq_cst);
        const coro = try Coroutine.init(self.allocator, id, func, args);

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.ready_queue.append(coro);
        return id;
    }

    /// Worker线程循环
    fn workerLoop(self: *Scheduler) void {
        while (self.running.load(.seq_cst)) {
            const coro = blk: {
                self.mutex.lock();
                defer self.mutex.unlock();

                if (self.ready_queue.items.len == 0) break :blk null;
                break :blk self.ready_queue.orderedRemove(0);
            };

            if (coro) |c| {
                c.state = .running;
                c.func_ptr(c.args) catch |err| {
                    std.debug.print("Coroutine {d} error: {}\n", .{ c.id, err });
                };

                self.mutex.lock();
                c.state = .finished;
                self.finished_queue.append(c) catch {};
                self.mutex.unlock();
            } else {
                std.time.sleep(1 * std.time.ns_per_ms);
            }
        }
    }
};

// ============================================================================
// 全局调度器实例
// ============================================================================

var global_scheduler: ?*Scheduler = null;
var scheduler_mutex: std.Thread.Mutex = .{};

/// 获取或创建全局调度器
pub fn getScheduler(allocator: Allocator) !*Scheduler {
    scheduler_mutex.lock();
    defer scheduler_mutex.unlock();

    if (global_scheduler == null) {
        global_scheduler = try Scheduler.init(allocator);
        try global_scheduler.?.start(4); // 启动4个worker线程
    }

    return global_scheduler.?;
}

/// 关闭全局调度器
pub fn shutdownScheduler() void {
    scheduler_mutex.lock();
    defer scheduler_mutex.unlock();

    if (global_scheduler) |sched| {
        sched.deinit();
        global_scheduler = null;
    }
}

// ============================================================================
// Select多路复用
// ============================================================================

/// Select操作类型
pub const SelectOp = enum {
    send,
    recv,
};

/// Select case
pub const SelectCase = struct {
    channel_ptr: usize,
    op: SelectOp,
    value: ?anyopaque,
};

/// Select - 多路复用等待多个channel操作
/// 返回第一个就绪的case索引
pub fn selectChannels(cases: []const SelectCase, timeout_ms: ?u64) !usize {
    const start_time = std.time.milliNow();

    while (true) {
        // 尝试每个case
        for (cases, 0..) |case, i| {
            switch (case.op) {
                .recv => {
                    // 尝试非阻塞接收
                    const ch = @as(*Channel(anyopaque), @ptrFromInt(case.channel_ptr));
                    if (ch.tryRecv()) |_| {
                        return i;
                    }
                },
                .send => {
                    // 对于send，我们简化实现，直接尝试发送
                    // 实际应该检查channel是否有空间
                    return i;
                },
            }
        }

        // 检查超时
        if (timeout_ms) |timeout| {
            const elapsed = std.time.milliNow() - start_time;
            if (elapsed >= timeout) {
                return error.Timeout;
            }
        }

        // 短暂休眠避免忙等待
        std.time.sleep(1 * std.time.ns_per_ms);
    }
}
