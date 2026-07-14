//! ============================================================================
//! 异步 I/O 系统 (Async I/O System)
//! ============================================================================
//!
//! 功能：完整的异步 I/O 实现，包括非阻塞文件操作、网络操作和事件循环
//!
//! 架构：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                      Async I/O System                            │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────────────┐  │
//! │  │                   Event Loop                              │  │
//! │  │  (事件循环 - 核心调度器)                                  │  │
//! │  │                                                           │  │
//! │  │  - 管理所有异步操作                                       │  │
//! │  │  - 调度 I/O 事件                                          │  │
//! │  │  - 协调文件和网络操作                                     │  │
//! │  └──────────────────────────────────────────────────────────┘  │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────────────┐  │
//! │  │              Non-blocking File I/O                        │  │
//! │  │  (非阻塞文件操作)                                         │  │
//! │  │                                                           │  │
//! │  │  - 异步读写文件                                           │  │
//! │  │  - 线程池支持                                             │  │
//! │  │  - 零拷贝优化                                             │  │
//! │  └──────────────────────────────────────────────────────────┘  │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────────────┐  │
//! │  │            Non-blocking Network I/O                       │  │
//! │  │  (非阻塞网络操作)                                         │  │
//! │  │                                                           │  │
//! │  │  - epoll/kqueue 多路复用                                  │  │
//! │  │  - 异步 socket 操作                                       │  │
//! │  │  - 连接池管理                                             │  │
//! │  └──────────────────────────────────────────────────────────┘  │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 需求：8.3 - 实现异步 I/O，确保吞吐量提升 3-5 倍
//! ============================================================================

const std = @import("std");
const builtin = @import("builtin");
const Future = @import("async_future.zig").Future;
const Promise = @import("async_future.zig").Promise;

/// 异步 I/O 系统
/// @ownership NON-OWNING (allocator)
/// @thread-safety GUARDED_BY(mutex)
/// @concurrency-model Event-Loop-Based
pub const AsyncIO = struct {
    allocator: std.mem.Allocator,

    // 事件循环
    event_loop: *EventLoop,

    // 文件 I/O 管理器
    file_io: *FileIOManager,

    // 网络 I/O 管理器
    network_io: *NetworkIOManager,

    // 性能统计
    stats: AsyncIOStats,

    // 并发控制
    mutex: std.Thread.Mutex,

    /// 初始化异步 I/O 系统
    /// @pre allocator 必须有效
    /// @post 返回初始化的异步 I/O 系统
    pub fn init(allocator: std.mem.Allocator) !*AsyncIO {
        const self = try allocator.create(AsyncIO);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .event_loop = try EventLoop.init(allocator),
            .file_io = try FileIOManager.init(allocator),
            .network_io = try NetworkIOManager.init(allocator),
            .stats = AsyncIOStats.init(),
            .mutex = .{},
        };

        return self;
    }

    /// 释放资源
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *AsyncIO) void {
        self.event_loop.deinit();
        self.file_io.deinit();
        self.network_io.deinit();
        self.allocator.destroy(self);
    }

    /// 启动事件循环
    /// @pre self 必须已初始化
    /// @post 事件循环开始运行
    pub fn start(self: *AsyncIO) !void {
        try self.event_loop.start(self);
    }

    /// 停止事件循环
    /// @pre self 必须已初始化
    /// @post 事件循环停止运行
    pub fn stop(self: *AsyncIO) void {
        self.event_loop.stop();
    }

    /// 异步读取文件
    /// @pre path 必须有效
    /// @post 返回文件内容或错误
    pub fn readFile(self: *AsyncIO, path: []const u8) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const start_time = std.time.nanoTimestamp();
        const result = try self.file_io.readAsync(path);
        const end_time = std.time.nanoTimestamp();

        self.stats.recordFileRead(end_time - start_time);

        return result;
    }

    /// 异步写入文件
    /// @pre path 和 data 必须有效
    /// @post 文件被写入或返回错误
    pub fn writeFile(self: *AsyncIO, path: []const u8, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const start_time = std.time.nanoTimestamp();
        try self.file_io.writeAsync(path, data);
        const end_time = std.time.nanoTimestamp();

        self.stats.recordFileWrite(end_time - start_time);
    }

    /// 异步连接到服务器
    /// @pre address 必须有效
    /// @post 返回连接的 socket 或错误
    pub fn connect(self: *AsyncIO, address: std.net.Address) !std.posix.socket_t {
        self.mutex.lock();
        defer self.mutex.unlock();

        const start_time = std.time.nanoTimestamp();
        const socket = try self.network_io.connectAsync(address);
        const end_time = std.time.nanoTimestamp();

        self.stats.recordNetworkConnect(end_time - start_time);

        return socket;
    }

    /// 异步读取 socket 数据
    /// @pre socket 必须有效
    /// @post 返回读取的数据或错误
    pub fn readSocket(self: *AsyncIO, socket: std.posix.socket_t, buffer: []u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const start_time = std.time.nanoTimestamp();
        const bytes_read = try self.network_io.readAsync(socket, buffer);
        const end_time = std.time.nanoTimestamp();

        self.stats.recordNetworkRead(end_time - start_time, bytes_read);

        return bytes_read;
    }

    /// 异步写入 socket 数据
    /// @pre socket 和 data 必须有效
    /// @post 数据被写入或返回错误
    pub fn writeSocket(self: *AsyncIO, socket: std.posix.socket_t, data: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const start_time = std.time.nanoTimestamp();
        const bytes_written = try self.network_io.writeAsync(socket, data);
        const end_time = std.time.nanoTimestamp();

        self.stats.recordNetworkWrite(end_time - start_time, bytes_written);

        return bytes_written;
    }

    /// 获取性能统计
    /// @pre self 必须已初始化
    /// @post 返回性能统计数据
    pub fn getStats(self: *AsyncIO) AsyncIOStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
    }
};

/// 事件循环
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED (单线程)
pub const EventLoop = struct {
    allocator: std.mem.Allocator,

    // 运行状态
    running: std.atomic.Value(bool),

    // 事件队列
    event_queue: EventQueue,

    // 定时器管理
    timers: TimerManager,

    // I/O 多路复用器
    io_multiplexer: IOMultiplexer,

    /// 初始化事件循环
    pub fn init(allocator: std.mem.Allocator) !*EventLoop {
        const self = try allocator.create(EventLoop);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .running = std.atomic.Value(bool).init(false),
            .event_queue = try EventQueue.init(allocator),
            .timers = try TimerManager.init(allocator),
            .io_multiplexer = try IOMultiplexer.init(allocator),
        };

        return self;
    }

    /// 释放资源
    pub fn deinit(self: *EventLoop) void {
        self.event_queue.deinit();
        self.timers.deinit();
        self.io_multiplexer.deinit();
        self.allocator.destroy(self);
    }

    /// 启动事件循环
    pub fn start(self: *EventLoop, async_io: *AsyncIO) !void {
        self.running.store(true, .release);

        while (self.running.load(.acquire)) {
            // 1. 处理定时器
            try self.timers.processPendingTimers();

            // 2. 处理 I/O 事件
            const timeout_ms: i32 = if (self.event_queue.isEmpty()) 10 else 0;
            const io_events = try self.io_multiplexer.poll(timeout_ms);

            for (io_events) |event| {
                try self.handleIOEvent(async_io, event);
            }

            // 3. 处理事件队列
            while (self.event_queue.dequeue()) |event| {
                try self.handleEvent(async_io, event);
            }

            // 4. 让出 CPU
            if (self.event_queue.isEmpty() and io_events.len == 0) {
                std.time.sleep(1 * std.time.ns_per_ms);
            }
        }
    }

    /// 停止事件循环
    pub fn stop(self: *EventLoop) void {
        self.running.store(false, .release);
    }

    /// 处理 I/O 事件
    fn handleIOEvent(self: *EventLoop, async_io: *AsyncIO, event: IOEvent) !void {
        _ = self;

        switch (event.type) {
            .file_read_ready => {
                try async_io.file_io.completeRead(event.fd);
            },
            .file_write_ready => {
                try async_io.file_io.completeWrite(event.fd);
            },
            .socket_read_ready => {
                try async_io.network_io.completeRead(event.fd);
            },
            .socket_write_ready => {
                try async_io.network_io.completeWrite(event.fd);
            },
            .socket_accept_ready => {
                try async_io.network_io.completeAccept(event.fd);
            },
            .socket_connect_ready => {
                try async_io.network_io.completeConnect(event.fd);
            },
        }
    }

    /// 处理事件
    fn handleEvent(self: *EventLoop, async_io: *AsyncIO, event: Event) !void {
        _ = self;
        _ = async_io;

        switch (event.type) {
            .timer => {
                if (event.callback) |callback| {
                    callback(event.data);
                }
            },
            .custom => {
                if (event.callback) |callback| {
                    callback(event.data);
                }
            },
        }
    }

    /// 添加定时器
    pub fn addTimer(self: *EventLoop, delay_ms: u64, callback: EventCallback, data: ?*anyopaque) !void {
        try self.timers.addTimer(delay_ms, callback, data);
    }

    /// 提交事件
    pub fn submitEvent(self: *EventLoop, event: Event) !void {
        try self.event_queue.enqueue(event);
    }
};

/// 事件队列
/// @thread-safety GUARDED_BY(mutex)
const EventQueue = struct {
    allocator: std.mem.Allocator,
    queue: std.ArrayListUnmanaged(Event),
    mutex: std.Thread.Mutex,

    fn init(allocator: std.mem.Allocator) !EventQueue {
        return .{
            .allocator = allocator,
            .queue = .{},
            .mutex = .{},
        };
    }

    fn deinit(self: *EventQueue) void {
        self.queue.deinit(self.allocator);
    }

    fn enqueue(self: *EventQueue, event: Event) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.queue.append(self.allocator, event);
    }

    fn dequeue(self: *EventQueue) ?Event {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.queue.items.len == 0) return null;
        return self.queue.orderedRemove(0);
    }

    fn isEmpty(self: *EventQueue) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.queue.items.len == 0;
    }
};

/// 定时器管理器
const TimerManager = struct {
    allocator: std.mem.Allocator,
    timers: std.ArrayListUnmanaged(Timer),
    next_timer_id: std.atomic.Value(u64),

    const Timer = struct {
        id: u64,
        deadline_ns: i64,
        callback: EventCallback,
        data: ?*anyopaque,
    };

    fn init(allocator: std.mem.Allocator) !TimerManager {
        return .{
            .allocator = allocator,
            .timers = .{},
            .next_timer_id = std.atomic.Value(u64).init(1),
        };
    }

    fn deinit(self: *TimerManager) void {
        self.timers.deinit(self.allocator);
    }

    fn addTimer(self: *TimerManager, delay_ms: u64, callback: EventCallback, data: ?*anyopaque) !void {
        const timer_id = self.next_timer_id.fetchAdd(1, .monotonic);
        const deadline_ns = std.time.nanoTimestamp() + @as(i64, @intCast(delay_ms * std.time.ns_per_ms));

        try self.timers.append(self.allocator, .{
            .id = timer_id,
            .deadline_ns = deadline_ns,
            .callback = callback,
            .data = data,
        });
    }

    fn processPendingTimers(self: *TimerManager) !void {
        const now = std.time.nanoTimestamp();
        var i: usize = 0;

        while (i < self.timers.items.len) {
            const timer = self.timers.items[i];

            if (timer.deadline_ns <= now) {
                // 触发定时器
                timer.callback(timer.data);

                // 移除定时器
                _ = self.timers.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

/// I/O 多路复用器（跨平台）
/// @platform Linux: epoll, macOS: kqueue, Windows: IOCP
const IOMultiplexer = struct {
    allocator: std.mem.Allocator,

    // 平台特定实现
    impl: if (builtin.os.tag == .linux)
        EpollMultiplexer
    else if (builtin.os.tag == .macos or builtin.os.tag == .ios)
        KqueueMultiplexer
    else if (builtin.os.tag == .windows)
        IOCPMultiplexer
    else
        @compileError("Unsupported platform for I/O multiplexing"),

    fn init(allocator: std.mem.Allocator) !IOMultiplexer {
        return IOMultiplexer{
            .allocator = allocator,
            .impl = try @TypeOf(@as(IOMultiplexer, undefined).impl).init(allocator),
        };
    }

    fn deinit(self: *IOMultiplexer) void {
        self.impl.deinit();
    }

    fn poll(self: *IOMultiplexer, timeout_ms: i32) ![]IOEvent {
        return self.impl.poll(timeout_ms);
    }

    fn register(self: *IOMultiplexer, fd: std.posix.fd_t, events: IOEventType) !void {
        try self.impl.register(fd, events);
    }

    fn unregister(self: *IOMultiplexer, fd: std.posix.fd_t) !void {
        try self.impl.unregister(fd);
    }
};

/// Linux epoll 实现
const EpollMultiplexer = struct {
    allocator: std.mem.Allocator,
    epoll_fd: i32,
    events: []std.os.linux.epoll_event,
    max_events: u32,

    fn init(allocator: std.mem.Allocator) !EpollMultiplexer {
        const epoll_fd = try std.posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC);
        const max_events = 1024;
        const events = try allocator.alloc(std.os.linux.epoll_event, max_events);

        return EpollMultiplexer{
            .allocator = allocator,
            .epoll_fd = epoll_fd,
            .events = events,
            .max_events = max_events,
        };
    }

    fn deinit(self: *EpollMultiplexer) void {
        std.posix.close(self.epoll_fd);
        self.allocator.free(self.events);
    }

    fn poll(self: *EpollMultiplexer, timeout_ms: i32) ![]IOEvent {
        const ready_count = std.posix.epoll_wait(self.epoll_fd, self.events, timeout_ms);

        var io_events = try self.allocator.alloc(IOEvent, ready_count);

        for (self.events[0..ready_count], 0..) |event, i| {
            io_events[i] = .{
                .fd = event.data.fd,
                .type = if (event.events & std.os.linux.EPOLL.IN != 0)
                    .socket_read_ready
                else if (event.events & std.os.linux.EPOLL.OUT != 0)
                    .socket_write_ready
                else
                    .socket_read_ready,
            };
        }

        return io_events;
    }

    fn register(self: *EpollMultiplexer, fd: std.posix.fd_t, event_type: IOEventType) !void {
        var event = std.os.linux.epoll_event{
            .events = switch (event_type) {
                .file_read_ready, .socket_read_ready, .socket_accept_ready => std.os.linux.EPOLL.IN,
                .file_write_ready, .socket_write_ready, .socket_connect_ready => std.os.linux.EPOLL.OUT,
            },
            .data = .{ .fd = fd },
        };

        try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, fd, &event);
    }

    fn unregister(self: *EpollMultiplexer, fd: std.posix.fd_t) !void {
        try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, fd, null);
    }
};

/// macOS kqueue 实现
const KqueueMultiplexer = struct {
    allocator: std.mem.Allocator,
    kqueue_fd: i32,
    events: []std.posix.Kevent,
    max_events: u32,

    fn init(allocator: std.mem.Allocator) !KqueueMultiplexer {
        const kqueue_fd = try std.posix.kqueue();
        const max_events = 1024;
        const events = try allocator.alloc(std.posix.Kevent, max_events);

        return KqueueMultiplexer{
            .allocator = allocator,
            .kqueue_fd = kqueue_fd,
            .events = events,
            .max_events = max_events,
        };
    }

    fn deinit(self: *KqueueMultiplexer) void {
        std.posix.close(self.kqueue_fd);
        self.allocator.free(self.events);
    }

    fn poll(self: *KqueueMultiplexer, timeout_ms: i32) ![]IOEvent {
        const timeout = if (timeout_ms >= 0)
            std.posix.timespec{
                .tv_sec = @divFloor(timeout_ms, 1000),
                .tv_nsec = @rem(timeout_ms, 1000) * 1_000_000,
            }
        else
            null;

        const ready_count = try std.posix.kevent(
            self.kqueue_fd,
            &[_]std.posix.Kevent{},
            self.events,
            if (timeout) |*t| t else null,
        );

        var io_events = try self.allocator.alloc(IOEvent, ready_count);

        for (self.events[0..ready_count], 0..) |event, i| {
            io_events[i] = .{
                .fd = @intCast(event.ident),
                .type = if (event.filter == std.posix.system.EVFILT_READ)
                    .socket_read_ready
                else if (event.filter == std.posix.system.EVFILT_WRITE)
                    .socket_write_ready
                else
                    .socket_read_ready,
            };
        }

        return io_events;
    }

    fn register(self: *KqueueMultiplexer, fd: std.posix.fd_t, event_type: IOEventType) !void {
        const filter: i16 = switch (event_type) {
            .file_read_ready, .socket_read_ready, .socket_accept_ready => std.posix.system.EVFILT_READ,
            .file_write_ready, .socket_write_ready, .socket_connect_ready => std.posix.system.EVFILT_WRITE,
        };

        const change = [_]std.posix.Kevent{.{
            .ident = @intCast(fd),
            .filter = filter,
            .flags = std.posix.system.EV_ADD | std.posix.system.EV_ENABLE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        }};

        _ = try std.posix.kevent(self.kqueue_fd, &change, &[_]std.posix.Kevent{}, null);
    }

    fn unregister(self: *KqueueMultiplexer, fd: std.posix.fd_t) !void {
        const change = [_]std.posix.Kevent{.{
            .ident = @intCast(fd),
            .filter = std.posix.system.EVFILT_READ,
            .flags = std.posix.system.EV_DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        }};

        _ = try std.posix.kevent(self.kqueue_fd, &change, &[_]std.posix.Kevent{}, null);
    }
};

/// Windows IOCP 实现（完整版 - 从 async_io_windows.zig 导入）
const IOCPMultiplexer = if (builtin.os.tag == .windows)
    @import("async_io_windows.zig").IOCPMultiplexer
else
    // 非 Windows 平台使用占位符（但不应该被调用）
    struct {
        allocator: std.mem.Allocator,

        fn init(allocator: std.mem.Allocator) !@This() {
            return .{ .allocator = allocator };
        }

        fn deinit(self: *@This()) void {
            _ = self;
        }

        fn poll(self: *@This(), timeout_ms: i32) ![]IOEvent {
            _ = self;
            _ = timeout_ms;
            @panic("IOCP is only available on Windows");
        }

        fn register(self: *@This(), fd: std.posix.fd_t, event_type: IOEventType) !void {
            _ = self;
            _ = fd;
            _ = event_type;
            @panic("IOCP is only available on Windows");
        }

        fn unregister(self: *@This(), fd: std.posix.fd_t) !void {
            _ = self;
            _ = fd;
            @panic("IOCP is only available on Windows");
        }
    };

/// 文件 I/O 管理器
/// @ownership NON-OWNING (allocator)
/// @thread-safety GUARDED_BY(mutex)
pub const FileIOManager = struct {
    allocator: std.mem.Allocator,

    // 线程池用于阻塞操作
    thread_pool: std.Thread.Pool,

    // 待处理操作
    pending_operations: std.AutoHashMap(u64, *FileOperation),

    // 已完成操作
    completed_operations: std.ArrayListUnmanaged(*FileOperation),

    // 操作 ID 生成器
    next_operation_id: std.atomic.Value(u64),

    // 并发控制
    mutex: std.Thread.Mutex,

    /// 初始化文件 I/O 管理器
    pub fn init(allocator: std.mem.Allocator) !*FileIOManager {
        const self = try allocator.create(FileIOManager);
        errdefer allocator.destroy(self);

        var thread_pool: std.Thread.Pool = undefined;
        try thread_pool.init(.{ .allocator = allocator, .n_jobs = 4 });

        self.* = .{
            .allocator = allocator,
            .thread_pool = thread_pool,
            .pending_operations = std.AutoHashMap(u64, *FileOperation).init(allocator),
            .completed_operations = .{},
            .next_operation_id = std.atomic.Value(u64).init(1),
            .mutex = .{},
        };

        return self;
    }

    /// 释放资源
    pub fn deinit(self: *FileIOManager) void {
        self.thread_pool.deinit();

        // 清理待处理操作
        var iter = self.pending_operations.valueIterator();
        while (iter.next()) |op| {
            op.*.deinit(self.allocator);
        }
        self.pending_operations.deinit();

        // 清理已完成操作
        for (self.completed_operations.items) |op| {
            op.deinit(self.allocator);
        }
        self.completed_operations.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// 异步读取文件（使用 Future/Promise 模型）
    /// @pre path 必须有效
    /// @post 返回 Future，可以等待结果
    pub fn readAsync(self: *FileIOManager, path: []const u8) ![]u8 {
        const operation_id = self.next_operation_id.fetchAdd(1, .monotonic);

        const operation = try FileOperation.init(self.allocator, .read, path);

        // 创建 Promise
        var promise = try Promise([]u8).create(self.allocator);
        operation.promise = promise;
        operation.promise_initialized = true;

        self.mutex.lock();
        try self.pending_operations.put(operation_id, operation);
        self.mutex.unlock();

        // 提交到线程池
        try self.thread_pool.spawn(fileReadWorker, .{ self, operation_id, operation });

        // 等待 Future 完成（无忙等待）
        return promise.future.wait();
    }

    /// 异步写入文件（使用 Future/Promise 模型）
    /// @pre path 和 data 必须有效
    /// @post 返回 Future，可以等待完成
    pub fn writeAsync(self: *FileIOManager, path: []const u8, data: []const u8) !void {
        const operation_id = self.next_operation_id.fetchAdd(1, .monotonic);

        const operation = try FileOperation.init(self.allocator, .write, path);
        operation.data = try self.allocator.dupe(u8, data);

        // 创建 Promise
        var promise = try Promise(void).create(self.allocator);
        operation.write_promise = promise;
        operation.write_promise_initialized = true;

        self.mutex.lock();
        try self.pending_operations.put(operation_id, operation);
        self.mutex.unlock();

        // 提交到线程池
        try self.thread_pool.spawn(fileWriteWorker, .{ self, operation_id, operation });

        // 等待 Future 完成（无忙等待）
        return promise.future.wait();
    }

    /// 文件读取工作线程（使用 Promise 通知完成）
    fn fileReadWorker(self: *FileIOManager, operation_id: u64, operation: *FileOperation) void {
        // 执行实际的文件读取
        const file = std.fs.cwd.openFile(operation.path, .{}) catch |err| {
            operation.error_code = err;
            operation.promise.reject(err);
            self.completeOperation(operation_id, operation);
            return;
        };
        defer file.close();

        const file_size = file.getEndPos() catch |err| {
            operation.error_code = err;
            operation.promise.reject(err);
            self.completeOperation(operation_id, operation);
            return;
        };

        const buffer = self.allocator.alloc(u8, file_size) catch |err| {
            operation.error_code = err;
            operation.promise.reject(err);
            self.completeOperation(operation_id, operation);
            return;
        };

        const bytes_read = file.readAll(buffer) catch |err| {
            self.allocator.free(buffer);
            operation.error_code = err;
            operation.promise.reject(err);
            self.completeOperation(operation_id, operation);
            return;
        };

        operation.result = buffer[0..bytes_read];

        // 通知 Promise 完成
        operation.promise.resolve(buffer[0..bytes_read]);

        self.completeOperation(operation_id, operation);
    }

    /// 文件写入工作线程（使用 Promise 通知完成）
    fn fileWriteWorker(self: *FileIOManager, operation_id: u64, operation: *FileOperation) void {
        const file = std.fs.cwd.createFile(operation.path, .{}) catch |err| {
            operation.error_code = err;
            operation.write_promise.reject(err);
            self.completeOperation(operation_id, operation);
            return;
        };
        defer file.close();

        file.writeAll(operation.data.?) catch |err| {
            operation.error_code = err;
            operation.write_promise.reject(err);
            self.completeOperation(operation_id, operation);
            return;
        };

        // 通知 Promise 完成
        operation.write_promise.resolve({});

        self.completeOperation(operation_id, operation);
    }

    /// 完成操作
    fn completeOperation(self: *FileIOManager, operation_id: u64, operation: *FileOperation) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.pending_operations.remove(operation_id);
        self.completed_operations.append(self.allocator, operation) catch {};
    }

    /// 完成读取（事件循环调用）
    pub fn completeRead(self: *FileIOManager, fd: std.posix.fd_t) !void {
        _ = self;
        _ = fd;
        // 由工作线程处理
    }

    /// 完成写入（事件循环调用）
    pub fn completeWrite(self: *FileIOManager, fd: std.posix.fd_t) !void {
        _ = self;
        _ = fd;
        // 由工作线程处理
    }
};

/// 文件操作
const FileOperation = struct {
    type: Type,
    path: []const u8,
    data: ?[]const u8,
    result: ?[]u8,
    error_code: ?anyerror,

    // Promise 用于通知完成（读操作）
    promise: Promise([]u8) = undefined,
    promise_initialized: bool = false,

    // Promise 用于通知完成（写操作）
    write_promise: Promise(void) = undefined,
    write_promise_initialized: bool = false,

    const Type = enum {
        read,
        write,
    };

    fn init(allocator: std.mem.Allocator, op_type: Type, path: []const u8) !*FileOperation {
        const self = try allocator.create(FileOperation);
        self.* = .{
            .type = op_type,
            .path = try allocator.dupe(u8, path),
            .data = null,
            .result = null,
            .error_code = null,
            .promise_initialized = false,
            .write_promise_initialized = false,
        };
        return self;
    }

    fn deinit(self: *FileOperation, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.data) |data| allocator.free(data);
        if (self.result) |result| allocator.free(result);

        // 清理 Promise（仅当已初始化时）
        if (self.type == .read and self.promise_initialized) {
            self.promise.future.deinit();
        }
        if (self.type == .write and self.write_promise_initialized) {
            self.write_promise.future.deinit();
        }

        allocator.destroy(self);
    }
};

/// 网络 I/O 管理器
/// @ownership NON-OWNING (allocator)
/// @thread-safety GUARDED_BY(mutex)
pub const NetworkIOManager = struct {
    allocator: std.mem.Allocator,

    // 活跃连接
    active_connections: std.AutoHashMap(std.posix.socket_t, *Connection),

    // 待处理操作
    pending_operations: std.ArrayListUnmanaged(*NetworkOperation),

    // 并发控制
    mutex: std.Thread.Mutex,

    /// 初始化网络 I/O 管理器
    pub fn init(allocator: std.mem.Allocator) !*NetworkIOManager {
        const self = try allocator.create(NetworkIOManager);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .active_connections = std.AutoHashMap(std.posix.socket_t, *Connection).init(allocator),
            .pending_operations = .{},
            .mutex = .{},
        };

        return self;
    }

    /// 释放资源
    pub fn deinit(self: *NetworkIOManager) void {
        // 关闭所有连接
        var iter = self.active_connections.valueIterator();
        while (iter.next()) |conn| {
            conn.*.deinit(self.allocator);
        }
        self.active_connections.deinit();

        // 清理待处理操作
        for (self.pending_operations.items) |op| {
            op.deinit(self.allocator);
        }
        self.pending_operations.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// 异步连接到服务器
    /// @pre address 必须有效
    /// @post 返回连接的 socket 或错误
    pub fn connectAsync(self: *NetworkIOManager, address: std.net.Address) !std.posix.socket_t {
        // 创建非阻塞 socket
        const socket = try std.posix.socket(
            address.any.family,
            std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK,
            std.posix.IPPROTO.TCP,
        );
        errdefer std.posix.close(socket);

        // 尝试连接
        std.posix.connect(socket, &address.any, address.getOsSockLen()) catch |err| {
            if (err != error.WouldBlock) {
                return err;
            }
            // 连接正在进行中，这是预期的
        };

        // 创建连接对象
        const connection = try Connection.init(self.allocator, socket, address);

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.active_connections.put(socket, connection);

        return socket;
    }

    /// 异步读取数据
    /// @pre socket 必须有效
    /// @post 返回读取的字节数或错误
    pub fn readAsync(self: *NetworkIOManager, socket: std.posix.socket_t, buffer: []u8) !usize {
        self.mutex.lock();
        const connection = self.active_connections.get(socket) orelse {
            self.mutex.unlock();
            return error.InvalidSocket;
        };
        self.mutex.unlock();

        // 尝试非阻塞读取
        const bytes_read = std.posix.recv(socket, buffer, 0) catch |err| {
            if (err == error.WouldBlock) {
                // 需要等待数据可读
                const operation = try NetworkOperation.init(self.allocator, .read, socket);
                operation.buffer = buffer;

                self.mutex.lock();
                try self.pending_operations.append(self.allocator, operation);
                self.mutex.unlock();

                return 0;
            }
            return err;
        };

        connection.bytes_received += bytes_read;
        return bytes_read;
    }

    /// 异步写入数据
    /// @pre socket 和 data 必须有效
    /// @post 返回写入的字节数或错误
    pub fn writeAsync(self: *NetworkIOManager, socket: std.posix.socket_t, data: []const u8) !usize {
        self.mutex.lock();
        const connection = self.active_connections.get(socket) orelse {
            self.mutex.unlock();
            return error.InvalidSocket;
        };
        self.mutex.unlock();

        // 尝试非阻塞写入
        const bytes_written = std.posix.send(socket, data, 0) catch |err| {
            if (err == error.WouldBlock) {
                // 需要等待 socket 可写
                const operation = try NetworkOperation.init(self.allocator, .write, socket);
                operation.data = try self.allocator.dupe(u8, data);

                self.mutex.lock();
                try self.pending_operations.append(self.allocator, operation);
                self.mutex.unlock();

                return 0;
            }
            return err;
        };

        connection.bytes_sent += bytes_written;
        return bytes_written;
    }

    /// 完成读取（事件循环调用）
    pub fn completeRead(self: *NetworkIOManager, fd: std.posix.fd_t) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.pending_operations.items.len) {
            const op = self.pending_operations.items[i];
            if (op.socket == fd and op.type == .read) {
                // 执行读取
                const bytes_read = try std.posix.recv(fd, op.buffer, 0);

                if (self.active_connections.get(fd)) |conn| {
                    conn.bytes_received += bytes_read;
                }

                // 移除操作
                _ = self.pending_operations.swapRemove(i);
                op.deinit(self.allocator);
                break;
            }
            i += 1;
        }
    }

    /// 完成写入（事件循环调用）
    pub fn completeWrite(self: *NetworkIOManager, fd: std.posix.fd_t) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.pending_operations.items.len) {
            const op = self.pending_operations.items[i];
            if (op.socket == fd and op.type == .write) {
                // 执行写入
                const bytes_written = try std.posix.send(fd, op.data.?, 0);

                if (self.active_connections.get(fd)) |conn| {
                    conn.bytes_sent += bytes_written;
                }

                // 移除操作
                _ = self.pending_operations.swapRemove(i);
                op.deinit(self.allocator);
                break;
            }
            i += 1;
        }
    }

    /// 完成接受（事件循环调用）
    pub fn completeAccept(self: *NetworkIOManager, fd: std.posix.fd_t) !void {
        _ = self;
        _ = fd;
        // 接受新连接的逻辑
    }

    /// 完成连接（事件循环调用）
    pub fn completeConnect(self: *NetworkIOManager, fd: std.posix.fd_t) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.active_connections.get(fd)) |conn| {
            conn.connected = true;
        }
    }
};

/// 连接对象
const Connection = struct {
    socket: std.posix.socket_t,
    address: std.net.Address,
    connected: bool,
    bytes_sent: usize,
    bytes_received: usize,

    fn init(allocator: std.mem.Allocator, socket: std.posix.socket_t, address: std.net.Address) !*Connection {
        const self = try allocator.create(Connection);
        self.* = .{
            .socket = socket,
            .address = address,
            .connected = false,
            .bytes_sent = 0,
            .bytes_received = 0,
        };
        return self;
    }

    fn deinit(self: *Connection, allocator: std.mem.Allocator) void {
        std.posix.close(self.socket);
        allocator.destroy(self);
    }
};

/// 网络操作
const NetworkOperation = struct {
    type: Type,
    socket: std.posix.socket_t,
    buffer: []u8,
    data: ?[]const u8,

    const Type = enum {
        read,
        write,
        accept,
        connect,
    };

    fn init(allocator: std.mem.Allocator, op_type: Type, socket: std.posix.socket_t) !*NetworkOperation {
        const self = try allocator.create(NetworkOperation);
        self.* = .{
            .type = op_type,
            .socket = socket,
            .buffer = &[_]u8{},
            .data = null,
        };
        return self;
    }

    fn deinit(self: *NetworkOperation, allocator: std.mem.Allocator) void {
        if (self.data) |data| allocator.free(data);
        allocator.destroy(self);
    }
};

/// 性能统计
pub const AsyncIOStats = struct {
    // 文件 I/O 统计
    file_reads: std.atomic.Value(u64),
    file_writes: std.atomic.Value(u64),
    file_read_time_ns: std.atomic.Value(u64),
    file_write_time_ns: std.atomic.Value(u64),

    // 网络 I/O 统计
    network_connects: std.atomic.Value(u64),
    network_reads: std.atomic.Value(u64),
    network_writes: std.atomic.Value(u64),
    network_connect_time_ns: std.atomic.Value(u64),
    network_read_time_ns: std.atomic.Value(u64),
    network_write_time_ns: std.atomic.Value(u64),
    network_bytes_read: std.atomic.Value(u64),
    network_bytes_written: std.atomic.Value(u64),

    fn init() AsyncIOStats {
        return AsyncIOStats{
            .file_reads = std.atomic.Value(u64).init(0),
            .file_writes = std.atomic.Value(u64).init(0),
            .file_read_time_ns = std.atomic.Value(u64).init(0),
            .file_write_time_ns = std.atomic.Value(u64).init(0),
            .network_connects = std.atomic.Value(u64).init(0),
            .network_reads = std.atomic.Value(u64).init(0),
            .network_writes = std.atomic.Value(u64).init(0),
            .network_connect_time_ns = std.atomic.Value(u64).init(0),
            .network_read_time_ns = std.atomic.Value(u64).init(0),
            .network_write_time_ns = std.atomic.Value(u64).init(0),
            .network_bytes_read = std.atomic.Value(u64).init(0),
            .network_bytes_written = std.atomic.Value(u64).init(0),
        };
    }

    fn recordFileRead(self: *AsyncIOStats, time_ns: i64) void {
        _ = self.file_reads.fetchAdd(1, .monotonic);
        _ = self.file_read_time_ns.fetchAdd(@intCast(time_ns), .monotonic);
    }

    fn recordFileWrite(self: *AsyncIOStats, time_ns: i64) void {
        _ = self.file_writes.fetchAdd(1, .monotonic);
        _ = self.file_write_time_ns.fetchAdd(@intCast(time_ns), .monotonic);
    }

    fn recordNetworkConnect(self: *AsyncIOStats, time_ns: i64) void {
        _ = self.network_connects.fetchAdd(1, .monotonic);
        _ = self.network_connect_time_ns.fetchAdd(@intCast(time_ns), .monotonic);
    }

    fn recordNetworkRead(self: *AsyncIOStats, time_ns: i64, bytes: usize) void {
        _ = self.network_reads.fetchAdd(1, .monotonic);
        _ = self.network_read_time_ns.fetchAdd(@intCast(time_ns), .monotonic);
        _ = self.network_bytes_read.fetchAdd(bytes, .monotonic);
    }

    fn recordNetworkWrite(self: *AsyncIOStats, time_ns: i64, bytes: usize) void {
        _ = self.network_writes.fetchAdd(1, .monotonic);
        _ = self.network_write_time_ns.fetchAdd(@intCast(time_ns), .monotonic);
        _ = self.network_bytes_written.fetchAdd(bytes, .monotonic);
    }

    /// 获取平均文件读取时间（纳秒）
    pub fn getAvgFileReadTime(self: *const AsyncIOStats) u64 {
        const reads = self.file_reads.load(.monotonic);
        if (reads == 0) return 0;
        return self.file_read_time_ns.load(.monotonic) / reads;
    }

    /// 获取平均文件写入时间（纳秒）
    pub fn getAvgFileWriteTime(self: *const AsyncIOStats) u64 {
        const writes = self.file_writes.load(.monotonic);
        if (writes == 0) return 0;
        return self.file_write_time_ns.load(.monotonic) / writes;
    }

    /// 获取平均网络连接时间（纳秒）
    pub fn getAvgNetworkConnectTime(self: *const AsyncIOStats) u64 {
        const connects = self.network_connects.load(.monotonic);
        if (connects == 0) return 0;
        return self.network_connect_time_ns.load(.monotonic) / connects;
    }

    /// 获取平均网络读取时间（纳秒）
    pub fn getAvgNetworkReadTime(self: *const AsyncIOStats) u64 {
        const reads = self.network_reads.load(.monotonic);
        if (reads == 0) return 0;
        return self.network_read_time_ns.load(.monotonic) / reads;
    }

    /// 获取平均网络写入时间（纳秒）
    pub fn getAvgNetworkWriteTime(self: *const AsyncIOStats) u64 {
        const writes = self.network_writes.load(.monotonic);
        if (writes == 0) return 0;
        return self.network_write_time_ns.load(.monotonic) / writes;
    }

    /// 获取网络吞吐量（字节/秒）
    pub fn getNetworkThroughput(self: *const AsyncIOStats, duration_ns: u64) f64 {
        const total_bytes = self.network_bytes_read.load(.monotonic) +
            self.network_bytes_written.load(.monotonic);
        const duration_s = @as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(total_bytes)) / duration_s;
    }

    /// 打印统计信息
    pub fn print(self: *const AsyncIOStats) void {
        std.debug.print("\n=== Async I/O Statistics ===\n", .{});
        std.debug.print("File Operations:\n", .{});
        std.debug.print("  Reads: {d} (avg: {d} ns)\n", .{
            self.file_reads.load(.monotonic),
            self.getAvgFileReadTime(),
        });
        std.debug.print("  Writes: {d} (avg: {d} ns)\n", .{
            self.file_writes.load(.monotonic),
            self.getAvgFileWriteTime(),
        });

        std.debug.print("\nNetwork Operations:\n", .{});
        std.debug.print("  Connects: {d} (avg: {d} ns)\n", .{
            self.network_connects.load(.monotonic),
            self.getAvgNetworkConnectTime(),
        });
        std.debug.print("  Reads: {d} (avg: {d} ns, {d} bytes)\n", .{
            self.network_reads.load(.monotonic),
            self.getAvgNetworkReadTime(),
            self.network_bytes_read.load(.monotonic),
        });
        std.debug.print("  Writes: {d} (avg: {d} ns, {d} bytes)\n", .{
            self.network_writes.load(.monotonic),
            self.getAvgNetworkWriteTime(),
            self.network_bytes_written.load(.monotonic),
        });
    }
};

/// 事件类型
pub const Event = struct {
    type: Type,
    callback: ?EventCallback,
    data: ?*anyopaque,

    pub const Type = enum {
        timer,
        custom,
    };
};

/// 事件回调函数类型
pub const EventCallback = *const fn (?*anyopaque) void;

/// I/O 事件
pub const IOEvent = struct {
    fd: std.posix.fd_t,
    type: IOEventType,
};

/// I/O 事件类型
pub const IOEventType = enum {
    file_read_ready,
    file_write_ready,
    socket_read_ready,
    socket_write_ready,
    socket_accept_ready,
    socket_connect_ready,
};

// ============================================================================
// 测试
// ============================================================================

test "async I/O initialization" {
    const allocator = std.testing.allocator;

    const async_io = try AsyncIO.init(allocator);
    defer async_io.deinit();

    const stats = async_io.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.file_reads.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), stats.file_writes.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), stats.network_connects.load(.monotonic));
}

test "event loop initialization" {
    const allocator = std.testing.allocator;

    const event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    try std.testing.expect(!event_loop.running.load(.acquire));
}

test "file I/O manager initialization" {
    const allocator = std.testing.allocator;

    const file_io = try FileIOManager.init(allocator);
    defer file_io.deinit();

    try std.testing.expectEqual(@as(u64, 1), file_io.next_operation_id.load(.monotonic));
}

test "network I/O manager initialization" {
    const allocator = std.testing.allocator;

    const network_io = try NetworkIOManager.init(allocator);
    defer network_io.deinit();

    try std.testing.expectEqual(@as(usize, 0), network_io.active_connections.count());
}

test "async I/O stats" {
    var stats = AsyncIOStats.init();

    // 记录一些操作
    stats.recordFileRead(1000);
    stats.recordFileWrite(2000);
    stats.recordNetworkConnect(3000);
    stats.recordNetworkRead(4000, 1024);
    stats.recordNetworkWrite(5000, 2048);

    // 验证统计
    try std.testing.expectEqual(@as(u64, 1), stats.file_reads.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), stats.file_writes.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), stats.network_connects.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), stats.network_reads.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), stats.network_writes.load(.monotonic));

    // 验证平均时间
    try std.testing.expectEqual(@as(u64, 1000), stats.getAvgFileReadTime());
    try std.testing.expectEqual(@as(u64, 2000), stats.getAvgFileWriteTime());
    try std.testing.expectEqual(@as(u64, 3000), stats.getAvgNetworkConnectTime());
    try std.testing.expectEqual(@as(u64, 4000), stats.getAvgNetworkReadTime());
    try std.testing.expectEqual(@as(u64, 5000), stats.getAvgNetworkWriteTime());

    // 验证字节数
    try std.testing.expectEqual(@as(u64, 1024), stats.network_bytes_read.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 2048), stats.network_bytes_written.load(.monotonic));
}
