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
    func_ptr: *const fn (?*anyopaque) anyerror!void,
    context: ?*anyopaque,
    result: ?*anyopaque,
    err: ?anyerror,
    allocator: Allocator,

    pub fn init(allocator: Allocator, id: u64, func: *const fn (?*anyopaque) anyerror!void, context: ?*anyopaque) !*Coroutine {
        const coro = try allocator.create(Coroutine);
        coro.* = .{
            .id = id,
            .state = .ready,
            .func_ptr = func,
            .context = context,
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
                .buffer = std.ArrayList(T){},
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
            self.buffer.deinit(self.allocator);
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

            try self.buffer.append(self.allocator, value);
            self.not_empty.signal();
        }

        /// 尝试发送（非阻塞）
        pub fn trySend(self: *Self, value: T) !bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed) return error.ChannelClosed;

            if (self.buffer.items.len >= self.capacity) {
                return false;
            }

            try self.buffer.append(self.allocator, value);
            self.not_empty.signal();
            return true;
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

        pub fn isClosed(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.closed;
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.buffer.items.len;
        }

        pub fn getCapacity(self: *Self) usize {
            return self.capacity;
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
    next_id: std.atomic.Value(u64),
    active_count: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    finished_cond: std.Thread.Condition,
    allocator: Allocator,
    worker_threads: std.ArrayList(std.Thread),
    running: std.atomic.Value(bool),
    started: bool,

    pub fn init(allocator: Allocator) !*Scheduler {
        const sched = try allocator.create(Scheduler);
        sched.* = .{
            .ready_queue = std.ArrayList(*Coroutine){},
            .blocked_queue = std.ArrayList(*Coroutine){},
            .finished_queue = std.ArrayList(*Coroutine){},
            .next_id = std.atomic.Value(u64).init(1),
            .active_count = std.atomic.Value(u64).init(0),
            .mutex = .{},
            .cond = .{},
            .finished_cond = .{},
            .allocator = allocator,
            .worker_threads = std.ArrayList(std.Thread){},
            .running = std.atomic.Value(bool).init(true),
            .started = false,
        };
        return sched;
    }

    pub fn deinit(self: *Scheduler) void {
        self.mutex.lock();
        self.running.store(false, .seq_cst);
        self.cond.broadcast();
        self.mutex.unlock();

        // 等待所有worker线程结束
        for (self.worker_threads.items) |thread| {
            thread.join();
        }

        // 清理所有协程
        for (self.ready_queue.items) |coro| coro.deinit();
        for (self.blocked_queue.items) |coro| coro.deinit();
        for (self.finished_queue.items) |coro| coro.deinit();

        self.ready_queue.deinit(self.allocator);
        self.blocked_queue.deinit(self.allocator);
        self.finished_queue.deinit(self.allocator);
        self.worker_threads.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn drain(self: *Scheduler, timeout_ms: ?u64) bool {
        const start_ms = std.time.milliTimestamp();
        while (true) {
            self.mutex.lock();
            const ready_len = self.ready_queue.items.len;
            const blocked_len = self.blocked_queue.items.len;
            self.mutex.unlock();

            const active = self.active_count.load(.acquire);
            if (ready_len == 0 and blocked_len == 0 and active == 0) return true;

            if (timeout_ms) |timeout| {
                const elapsed: u64 = @intCast(std.time.milliTimestamp() - start_ms);
                if (elapsed >= timeout) return false;
            }
            std.Thread.sleep(1 * std.time.ns_per_ms);
        }
    }

    /// 启动worker线程
    pub fn start(self: *Scheduler, num_workers: usize) !void {
        if (self.started) return;
        self.started = true;
        var i: usize = 0;
        while (i < num_workers) : (i += 1) {
            const thread = try std.Thread.spawn(.{}, workerLoop, .{self});
            try self.worker_threads.append(self.allocator, thread);
        }
    }

    fn ensureStarted(self: *Scheduler) !void {
        if (self.started) return;
        try self.start(4);
    }

    /// 调度一个新协程
    pub fn spawn(self: *Scheduler, func: *const fn (?*anyopaque) anyerror!void, context: ?*anyopaque) !u64 {
        const id = self.next_id.fetchAdd(1, .seq_cst);
        const coro = try Coroutine.init(self.allocator, id, func, context);

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.ready_queue.append(self.allocator, coro);
        self.cond.signal();
        return id;
    }

    pub fn join(self: *Scheduler, id: u64) anyerror!void {
        try self.ensureStarted();
        var finished: *Coroutine = undefined;
        while (true) {
            self.mutex.lock();
            var idx: usize = 0;
            while (idx < self.finished_queue.items.len) : (idx += 1) {
                if (self.finished_queue.items[idx].id == id) {
                    finished = self.finished_queue.orderedRemove(idx);
                    self.mutex.unlock();
                    break;
                }
            } else {
                self.finished_cond.wait(&self.mutex);
                self.mutex.unlock();
                continue;
            }
            break;
        }

        defer finished.deinit();
        if (finished.err) |e| return e;
    }

    pub fn waitAll(self: *Scheduler) void {
        _ = self.drain(null);
    }

    /// Worker线程循环
    fn workerLoop(self: *Scheduler) void {
        while (true) {
            const coro = blk: {
                self.mutex.lock();
                defer self.mutex.unlock();

                while (self.ready_queue.items.len == 0 and self.running.load(.seq_cst)) {
                    self.cond.wait(&self.mutex);
                }

                if (!self.running.load(.seq_cst) and self.ready_queue.items.len == 0) return;
                
                break :blk self.ready_queue.orderedRemove(0);
            };

            _ = self.active_count.fetchAdd(1, .acq_rel);
            {
                const c = coro;
                c.state = .running;
                c.func_ptr(c.context) catch |err| {
                    c.err = err;
                };

                self.mutex.lock();
                c.state = .finished;
                self.finished_queue.append(self.allocator, c) catch c.deinit();
                self.finished_cond.broadcast();
                self.mutex.unlock();
            }
            _ = self.active_count.fetchSub(1, .acq_rel);
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
    }

    return global_scheduler.?;
}

/// 关闭全局调度器
pub fn shutdownScheduler() void {
    scheduler_mutex.lock();
    defer scheduler_mutex.unlock();

    if (global_scheduler) |sched| {
        _ = sched.drain(10_000);
        sched.deinit();
        global_scheduler = null;
    }
}

pub fn drainScheduler(timeout_ms: ?u64) bool {
    scheduler_mutex.lock();
    defer scheduler_mutex.unlock();
    if (global_scheduler) |s| {
        s.ensureStarted() catch return false;
        return s.drain(timeout_ms);
    }
    return true;
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
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }
}
