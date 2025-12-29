const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Thread = std.Thread;

/// PHP协程管理系统
/// 提供轻量级协程支持，类似Go的goroutine
pub const CoroutineManager = struct {
    allocator: std.mem.Allocator,
    coroutines: std.AutoHashMap(u64, *Coroutine),
    ready_queue: std.ArrayList(*Coroutine),
    sleeping_queue: std.ArrayList(*Coroutine),
    next_id: std.atomic.Value(u64),
    current_coroutine: ?*Coroutine,
    scheduler_running: std.atomic.Value(bool),
    mutex: Thread.Mutex,
    cond: Thread.Condition,

    // 协程池用于重用
    pool: std.ArrayList(*Coroutine),
    pool_max_size: usize,

    pub fn init(allocator: std.mem.Allocator) CoroutineManager {
        return CoroutineManager{
            .allocator = allocator,
            .coroutines = std.AutoHashMap(u64, *Coroutine).init(allocator),
            .ready_queue = std.ArrayList(*Coroutine).init(allocator),
            .sleeping_queue = std.ArrayList(*Coroutine).init(allocator),
            .next_id = std.atomic.Value(u64).init(1),
            .current_coroutine = null,
            .scheduler_running = std.atomic.Value(bool).init(false),
            .mutex = .{},
            .cond = .{},
            .pool = std.ArrayList(*Coroutine).init(allocator),
            .pool_max_size = 1000,
        };
    }

    pub fn deinit(self: *CoroutineManager) void {
        // 停止所有协程
        self.stopAll();

        // 清理协程
        var iter = self.coroutines.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.coroutines.deinit();

        // 清理队列
        self.ready_queue.deinit(self.allocator);
        self.sleeping_queue.deinit(self.allocator);

        // 清理池
        for (self.pool.items) |co| {
            co.deinit();
            self.allocator.destroy(co);
        }
        self.pool.deinit(self.allocator);
    }

    /// 创建新协程
    pub fn spawn(self: *CoroutineManager, callback: Value, args: []const Value) !u64 {
        const id = self.next_id.fetchAdd(1, .seq_cst);

        // 尝试从池中获取协程
        var coroutine: *Coroutine = undefined;
        if (self.pool.items.len > 0) {
            coroutine = self.pool.pop();
            coroutine.reset(id, callback, args);
        } else {
            coroutine = try self.allocator.create(Coroutine);
            coroutine.* = try Coroutine.init(self.allocator, id, callback, args);
        }

        try self.coroutines.put(id, coroutine);

        // 加入就绪队列
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.ready_queue.append(coroutine);
        self.cond.signal();

        return id;
    }

    /// 运行调度器
    pub fn run(self: *CoroutineManager, vm: *anyopaque) !void {
        self.scheduler_running.store(true, .seq_cst);

        while (self.scheduler_running.load(.seq_cst)) {
            // 检查睡眠协程
            try self.wakeUpSleeping();

            // 获取下一个就绪协程
            const next_coroutine = self.getNextReady();

            if (next_coroutine) |co| {
                self.current_coroutine = co;

                // 执行协程
                const result = co.resumeExecution(vm);

                switch (co.state) {
                    .completed => {
                        // 协程完成，存储结果
                        co.result = result catch Value.initNull();
                        self.recycleCoroutine(co);
                    },
                    .yielded => {
                        // 协程让出，重新加入就绪队列
                        self.mutex.lock();
                        self.ready_queue.append(co) catch {};
                        self.mutex.unlock();
                    },
                    .sleeping => {
                        // 协程休眠，加入睡眠队列
                        self.mutex.lock();
                        self.sleeping_queue.append(co) catch {};
                        self.mutex.unlock();
                    },
                    .waiting => {
                        // 等待IO或其他事件
                    },
                    else => {},
                }

                self.current_coroutine = null;
            } else {
                // 没有就绪协程，等待
                self.mutex.lock();
                if (self.ready_queue.items.len == 0 and self.sleeping_queue.items.len == 0) {
                    self.scheduler_running.store(false, .seq_cst);
                    self.mutex.unlock();
                    break;
                }
                self.cond.timedWait(&self.mutex, 1_000_000) catch {}; // 1ms
                self.mutex.unlock();
            }
        }
    }

    /// 让出当前协程
    pub fn yield(self: *CoroutineManager) void {
        if (self.current_coroutine) |co| {
            co.state = .yielded;
        }
    }

    /// 休眠当前协程
    pub fn sleep(self: *CoroutineManager, duration_ms: u64) void {
        if (self.current_coroutine) |co| {
            co.state = .sleeping;
            co.wake_time = std.time.milliTimestamp() + @as(i64, @intCast(duration_ms));
        }
    }

    /// 等待协程完成
    pub fn wait(self: *CoroutineManager, id: u64) ?Value {
        if (self.coroutines.get(id)) |co| {
            while (co.state != .completed) {
                std.time.sleep(1_000_000); // 1ms
            }
            return co.result;
        }
        return null;
    }

    /// 取消协程
    pub fn cancel(self: *CoroutineManager, id: u64) bool {
        if (self.coroutines.get(id)) |co| {
            co.state = .cancelled;
            return true;
        }
        return false;
    }

    /// 获取当前协程ID
    pub fn currentId(self: *CoroutineManager) ?u64 {
        if (self.current_coroutine) |co| {
            return co.id;
        }
        return null;
    }

    /// 停止所有协程
    pub fn stopAll(self: *CoroutineManager) void {
        self.scheduler_running.store(false, .seq_cst);

        var iter = self.coroutines.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.state = .cancelled;
        }
    }

    fn getNextReady(self: *CoroutineManager) ?*Coroutine {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.ready_queue.items.len > 0) {
            return self.ready_queue.orderedRemove(0);
        }
        return null;
    }

    fn wakeUpSleeping(self: *CoroutineManager) !void {
        const now = std.time.milliTimestamp();

        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.sleeping_queue.items.len) {
            const co = self.sleeping_queue.items[i];
            if (co.wake_time <= now) {
                co.state = .ready;
                try self.ready_queue.append(co);
                _ = self.sleeping_queue.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    fn recycleCoroutine(self: *CoroutineManager, co: *Coroutine) void {
        _ = self.coroutines.remove(co.id);

        if (self.pool.items.len < self.pool_max_size) {
            self.pool.append(co) catch {
                co.deinit();
                self.allocator.destroy(co);
            };
        } else {
            co.deinit();
            self.allocator.destroy(co);
        }
    }
};

/// 协程
pub const Coroutine = struct {
    id: u64,
    state: State,
    callback: Value,
    args: []Value,
    result: ?Value,
    wake_time: i64,
    stack: CoroutineStack,
    allocator: std.mem.Allocator,

    pub const State = enum {
        created,
        ready,
        running,
        yielded,
        sleeping,
        waiting,
        completed,
        cancelled,
    };

    pub fn init(allocator: std.mem.Allocator, id: u64, callback: Value, args: []const Value) !Coroutine {
        // 复制参数
        var args_copy = try allocator.alloc(Value, args.len);
        for (args, 0..) |arg, i| {
            args_copy[i] = arg.retain();
        }

        return Coroutine{
            .id = id,
            .state = .ready,
            .callback = callback.retain(),
            .args = args_copy,
            .result = null,
            .wake_time = 0,
            .stack = CoroutineStack.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Coroutine) void {
        self.callback.release(self.allocator);
        for (self.args) |*arg| {
            arg.release(self.allocator);
        }
        self.allocator.free(self.args);
        if (self.result) |*r| {
            r.release(self.allocator);
        }
        self.stack.deinit();
    }

    pub fn reset(self: *Coroutine, id: u64, callback: Value, args: []const Value) void {
        // 清理旧数据
        self.callback.release(self.allocator);
        for (self.args) |*arg| {
            arg.release(self.allocator);
        }
        if (self.result) |*r| {
            r.release(self.allocator);
        }

        // 设置新数据
        self.id = id;
        self.state = .ready;
        self.callback = callback.retain();

        // 重新分配参数
        if (self.args.len != args.len) {
            self.allocator.free(self.args);
            self.args = self.allocator.alloc(Value, args.len) catch &[_]Value{};
        }
        for (args, 0..) |arg, i| {
            self.args[i] = arg.retain();
        }

        self.result = null;
        self.wake_time = 0;
        self.stack.reset();
    }

    /// 恢复协程执行
    pub fn resumeExecution(self: *Coroutine, vm: *anyopaque) !Value {
        if (self.state == .cancelled) {
            return Value.initNull();
        }

        self.state = .running;

        // 调用回调函数
        const result = try self.invokeCallback(vm);

        if (self.state == .running) {
            self.state = .completed;
        }

        return result;
    }

    fn invokeCallback(self: *Coroutine, vm: *anyopaque) !Value {
        // 这里需要调用VM来执行回调
        _ = vm;
        return switch (self.callback.tag) {
            .closure => {
                // TODO: 调用closure
                return Value.initNull();
            },
            .user_function => {
                // TODO: 调用user function
                return Value.initNull();
            },
            .arrow_function => {
                // TODO: 调用arrow function
                return Value.initNull();
            },
            else => Value.initNull(),
        };
    }
};

/// 协程栈
pub const CoroutineStack = struct {
    allocator: std.mem.Allocator,
    frames: std.ArrayList(StackFrame),

    pub const StackFrame = struct {
        locals: std.StringHashMap(Value),
        return_address: usize,

        pub fn init(allocator: std.mem.Allocator) StackFrame {
            return StackFrame{
                .locals = std.StringHashMap(Value).init(allocator),
                .return_address = 0,
            };
        }

        pub fn deinit(self: *StackFrame, allocator: std.mem.Allocator) void {
            var iter = self.locals.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.release(allocator);
            }
            self.locals.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator) CoroutineStack {
        return CoroutineStack{
            .allocator = allocator,
            .frames = std.ArrayList(StackFrame).init(allocator),
        };
    }

    pub fn deinit(self: *CoroutineStack) void {
        for (self.frames.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.frames.deinit(self.allocator);
    }

    pub fn reset(self: *CoroutineStack) void {
        for (self.frames.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.frames.clearRetainingCapacity();
    }

    pub fn push(self: *CoroutineStack) !*StackFrame {
        try self.frames.append(StackFrame.init(self.allocator));
        return &self.frames.items[self.frames.items.len - 1];
    }

    pub fn pop(self: *CoroutineStack) void {
        if (self.frames.items.len > 0) {
            var frame = self.frames.pop();
            frame.deinit(self.allocator);
        }
    }

    pub fn current(self: *CoroutineStack) ?*StackFrame {
        if (self.frames.items.len > 0) {
            return &self.frames.items[self.frames.items.len - 1];
        }
        return null;
    }
};

/// Channel - 协程间通信
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        buffer: std.ArrayList(T),
        capacity: usize,
        closed: std.atomic.Value(bool),
        mutex: Thread.Mutex,
        send_cond: Thread.Condition,
        recv_cond: Thread.Condition,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) Self {
            return Self{
                .allocator = allocator,
                .buffer = std.ArrayList(T).init(allocator),
                .capacity = capacity,
                .closed = std.atomic.Value(bool).init(false),
                .mutex = .{},
                .send_cond = .{},
                .recv_cond = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        /// 发送数据到channel
        pub fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed.load(.seq_cst)) {
                return error.ChannelClosed;
            }

            // 等待有空间
            while (self.buffer.items.len >= self.capacity) {
                if (self.closed.load(.seq_cst)) {
                    return error.ChannelClosed;
                }
                self.send_cond.wait(&self.mutex);
            }

            try self.buffer.append(value);
            self.recv_cond.signal();
        }

        /// 从channel接收数据
        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // 等待有数据
            while (self.buffer.items.len == 0) {
                if (self.closed.load(.seq_cst)) {
                    return error.ChannelClosed;
                }
                self.recv_cond.wait(&self.mutex);
            }

            const value = self.buffer.orderedRemove(0);
            self.send_cond.signal();
            return value;
        }

        /// 尝试发送（非阻塞）
        pub fn trySend(self: *Self, value: T) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed.load(.seq_cst)) {
                return false;
            }

            if (self.buffer.items.len >= self.capacity) {
                return false;
            }

            self.buffer.append(value) catch return false;
            self.recv_cond.signal();
            return true;
        }

        /// 尝试接收（非阻塞）
        pub fn tryRecv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.buffer.items.len == 0) {
                return null;
            }

            const value = self.buffer.orderedRemove(0);
            self.send_cond.signal();
            return value;
        }

        /// 关闭channel
        pub fn close(self: *Self) void {
            self.closed.store(true, .seq_cst);
            self.send_cond.broadcast();
            self.recv_cond.broadcast();
        }

        /// 检查是否已关闭
        pub fn isClosed(self: *Self) bool {
            return self.closed.load(.seq_cst);
        }

        /// 获取当前缓冲区长度
        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.buffer.items.len;
        }
    };
}

/// WaitGroup - 等待一组协程完成
pub const WaitGroup = struct {
    counter: std.atomic.Value(i32),
    mutex: Thread.Mutex,
    cond: Thread.Condition,

    pub fn init() WaitGroup {
        return WaitGroup{
            .counter = std.atomic.Value(i32).init(0),
            .mutex = .{},
            .cond = .{},
        };
    }

    /// 增加计数
    pub fn add(self: *WaitGroup, delta: i32) void {
        _ = self.counter.fetchAdd(delta, .seq_cst);
    }

    /// 完成一个
    pub fn done(self: *WaitGroup) void {
        const prev = self.counter.fetchSub(1, .seq_cst);
        if (prev == 1) {
            self.cond.broadcast();
        }
    }

    /// 等待所有完成
    pub fn wait(self: *WaitGroup) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.counter.load(.seq_cst) > 0) {
            self.cond.wait(&self.mutex);
        }
    }
};

/// Mutex - PHP协程互斥锁
pub const CoMutex = struct {
    locked: std.atomic.Value(bool),
    owner: ?u64,
    waiting: std.ArrayList(u64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CoMutex {
        return CoMutex{
            .locked = std.atomic.Value(bool).init(false),
            .owner = null,
            .waiting = std.ArrayList(u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CoMutex) void {
        self.waiting.deinit();
    }

    pub fn lock(self: *CoMutex, coroutine_id: u64) void {
        while (true) {
            if (self.locked.cmpxchgWeak(false, true, .seq_cst, .seq_cst)) |_| {
                // 获取失败，加入等待队列
                self.waiting.append(coroutine_id) catch {};
                // 让出协程
                std.time.sleep(1_000); // 1μs
            } else {
                // 获取成功
                self.owner = coroutine_id;
                return;
            }
        }
    }

    pub fn unlock(self: *CoMutex) void {
        self.owner = null;
        self.locked.store(false, .seq_cst);
    }

    pub fn tryLock(self: *CoMutex, coroutine_id: u64) bool {
        if (self.locked.cmpxchgWeak(false, true, .seq_cst, .seq_cst)) |_| {
            return false;
        }
        self.owner = coroutine_id;
        return true;
    }
};

test "channel basic operations" {
    const allocator = std.testing.allocator;
    var channel = Channel(i32).init(allocator, 10);
    defer channel.deinit();

    try channel.send(42);
    try std.testing.expectEqual(@as(i32, 42), try channel.recv());
}

test "waitgroup basic operations" {
    var wg = WaitGroup.init();

    wg.add(2);
    wg.done();
    wg.done();
    wg.wait();
}
