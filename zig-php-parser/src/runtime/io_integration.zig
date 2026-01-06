//! ============================================================================
//! I/O集成 (I/O Integration)
//! ============================================================================
//!
//! 功能：协程感知的I/O操作集成，实现非阻塞I/O
//!
//! 架构：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                      I/O Integration                             │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────────────┐  │
//! │  │                   NetPoller                               │  │
//! │  │  (网络轮询器 - epoll/kqueue)                              │  │
//! │  │                                                           │  │
//! │  │  监听: socket fd1, fd2, fd3...                           │  │
//! │  │  事件: 可读/可写/错误                                     │  │
//! │  │  唤醒: 通知等待的协程                                     │  │
//! │  └──────────────────────────────────────────────────────────┘  │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────────────┐  │
//! │  │                 FileIOManager                             │  │
//! │  │  (文件I/O管理器)                                          │  │
//! │  │                                                           │  │
//! │  │  异步读写文件                                             │  │
//! │  │  协程挂起/恢复                                            │  │
//! │  └──────────────────────────────────────────────────────────┘  │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────────────┐  │
//! │  │                 IOWaitQueues                              │  │
//! │  │  (I/O等待队列)                                            │  │
//! │  │                                                           │  │
//! │  │  管理等待I/O完成的协程                                    │  │
//! │  └──────────────────────────────────────────────────────────┘  │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 工作流程：
//! 1. 协程发起I/O操作
//! 2. 如果会阻塞，协程挂起并加入等待队列
//! 3. NetPoller监听I/O事件
//! 4. I/O就绪时，唤醒等待的协程
//! 5. 协程继续执行
//!
//! 需求：5.6, 6.9
//! ============================================================================

const std = @import("std");
const Coroutine = @import("coroutine.zig").Coroutine;
const Scheduler = @import("scheduler.zig").Scheduler;

/// I/O集成，协程感知的I/O操作
pub const IOIntegration = struct {
    allocator: std.mem.Allocator,
    scheduler: *Scheduler,
    
    // Network poller for efficient I/O multiplexing
    netpoller: NetPoller,
    
    // File I/O integration
    file_io: FileIOManager,
    
    // I/O wait queues
    io_wait_queues: IOWaitQueues,
    
    // Performance monitoring
    io_operations: std.atomic.Value(u64),
    blocked_operations: std.atomic.Value(u64),
    average_wait_time_ns: std.atomic.Value(u64),
    
    pub fn init(allocator: std.mem.Allocator, scheduler: *Scheduler) !IOIntegration {
        return IOIntegration{
            .allocator = allocator,
            .scheduler = scheduler,
            .netpoller = try NetPoller.init(allocator),
            .file_io = try FileIOManager.init(allocator),
            .io_wait_queues = IOWaitQueues.init(allocator),
            .io_operations = std.atomic.Value(u64).init(0),
            .blocked_operations = std.atomic.Value(u64).init(0),
            .average_wait_time_ns = std.atomic.Value(u64).init(0),
        };
    }
    
    pub fn deinit(self: *IOIntegration) void {
        self.netpoller.deinit();
        self.file_io.deinit();
        self.io_wait_queues.deinit();
    }
    
    /// Perform non-blocking network I/O operation
    /// Requirement 6.9 - use epoll/kqueue to efficiently wake waiting coroutines
    pub fn performNetworkIO(self: *IOIntegration, coroutine_id: u64, operation: NetworkOperation) !IOResult {
        _ = self.io_operations.fetchAdd(1, .monotonic);
        
        const start_time = std.time.nanoTimestamp();
        
        // Try non-blocking operation first
        const result = self.netpoller.tryOperation(operation);
        
        switch (result) {
            .completed => |data| {
                return IOResult{ .completed = data };
            },
            .would_block => {
                // Add to wait queue and park coroutine
                try self.io_wait_queues.addNetworkWaiter(coroutine_id, operation, start_time);
                try self.netpoller.addToEpoll(operation);
                
                _ = self.blocked_operations.fetchAdd(1, .monotonic);
                self.scheduler.park(coroutine_id, .io_wait);
                
                return IOResult{ .pending = coroutine_id };
            },
            .error_occurred => |err| {
                return IOResult{ .error_occurred = err };
            },
        }
    }
    
    /// Perform file I/O operation
    /// Requirement 5.6 - file I/O integration
    pub fn performFileIO(self: *IOIntegration, coroutine_id: u64, operation: FileOperation) !IOResult {
        _ = self.io_operations.fetchAdd(1, .monotonic);
        
        const start_time = std.time.nanoTimestamp();
        
        // File I/O operations are typically blocking, so we use thread pool
        const result = try self.file_io.submitOperation(operation);
        
        switch (result) {
            .completed => |data| {
                return IOResult{ .completed = data };
            },
            .queued => {
                // Add to wait queue and park coroutine
                try self.io_wait_queues.addFileWaiter(coroutine_id, operation, start_time);
                
                _ = self.blocked_operations.fetchAdd(1, .monotonic);
                self.scheduler.park(coroutine_id, .io_wait);
                
                return IOResult{ .pending = coroutine_id };
            },
            .error_occurred => |err| {
                return IOResult{ .error_occurred = err };
            },
        }
    }
    
    /// Poll for completed I/O operations
    /// Requirement 6.9 - efficiently wake waiting coroutines
    pub fn pollCompletedOperations(self: *IOIntegration) ![]u64 {
        var completed_coroutines = std.ArrayList(u64).init(self.allocator);
        defer completed_coroutines.deinit();
        
        // Poll network operations
        const network_ready = try self.netpoller.poll();
        defer self.allocator.free(network_ready);
        
        for (network_ready) |ready_op| {
            if (self.io_wait_queues.removeNetworkWaiter(ready_op)) |waiter| {
                try completed_coroutines.append(waiter.coroutine_id);
                self.updateWaitTime(waiter.start_time);
                self.scheduler.unpark(waiter.coroutine_id);
            }
        }
        
        // Poll file operations
        const file_ready = try self.file_io.pollCompleted();
        defer self.allocator.free(file_ready);
        
        for (file_ready) |ready_op| {
            if (self.io_wait_queues.removeFileWaiter(ready_op)) |waiter| {
                try completed_coroutines.append(waiter.coroutine_id);
                self.updateWaitTime(waiter.start_time);
                self.scheduler.unpark(waiter.coroutine_id);
            }
        }
        
        return completed_coroutines.toOwnedSlice();
    }
    
    /// Update average wait time statistics
    fn updateWaitTime(self: *IOIntegration, start_time: i64) void {
        const wait_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
        const current_avg = self.average_wait_time_ns.load(.monotonic);
        const new_avg = (current_avg + wait_time) / 2;
        self.average_wait_time_ns.store(new_avg, .monotonic);
    }
    
    /// Get I/O statistics
    pub fn getStats(self: *IOIntegration) IOStats {
        return IOStats{
            .total_operations = self.io_operations.load(.monotonic),
            .blocked_operations = self.blocked_operations.load(.monotonic),
            .average_wait_time_ns = self.average_wait_time_ns.load(.monotonic),
            .pending_network_operations = self.io_wait_queues.getNetworkWaiterCount(),
            .pending_file_operations = self.io_wait_queues.getFileWaiterCount(),
        };
    }
};

/// Network poller using epoll/kqueue for efficient I/O multiplexing
/// Requirement 6.9 - implement netpoller for network I/O
pub const NetPoller = struct {
    allocator: std.mem.Allocator,
    
    // Platform-specific I/O multiplexing
    epoll_fd: i32,
    events: []std.os.linux.epoll_event,
    max_events: u32,
    
    // Operation tracking
    pending_operations: std.HashMap(i32, NetworkOperation, std.hash_map.DefaultContext(i32), std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: std.mem.Allocator) !NetPoller {
        const epoll_fd = try std.os.epoll_create1(std.os.linux.EPOLL.CLOEXEC);
        const max_events = 1024;
        const events = try allocator.alloc(std.os.linux.epoll_event, max_events);
        
        return NetPoller{
            .allocator = allocator,
            .epoll_fd = epoll_fd,
            .events = events,
            .max_events = max_events,
            .pending_operations = std.HashMap(i32, NetworkOperation, std.hash_map.DefaultContext(i32), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *NetPoller) void {
        std.os.close(self.epoll_fd);
        self.allocator.free(self.events);
        self.pending_operations.deinit();
    }
    
    /// Try non-blocking network operation
    pub fn tryOperation(self: *NetPoller, operation: NetworkOperation) OperationResult {
        _ = self;
        
        switch (operation.type) {
            .read => {
                const bytes_read = std.os.read(operation.fd, operation.buffer) catch |err| {
                    if (err == error.WouldBlock) {
                        return OperationResult{ .would_block = {} };
                    }
                    return OperationResult{ .error_occurred = err };
                };
                
                return OperationResult{ .completed = IOData{ .bytes_read = bytes_read } };
            },
            .write => {
                const bytes_written = std.os.write(operation.fd, operation.data) catch |err| {
                    if (err == error.WouldBlock) {
                        return OperationResult{ .would_block = {} };
                    }
                    return OperationResult{ .error_occurred = err };
                };
                
                return OperationResult{ .completed = IOData{ .bytes_written = bytes_written } };
            },
            .accept => {
                const client_fd = std.os.accept(operation.fd, null, null, std.os.SOCK.CLOEXEC | std.os.SOCK.NONBLOCK) catch |err| {
                    if (err == error.WouldBlock) {
                        return OperationResult{ .would_block = {} };
                    }
                    return OperationResult{ .error_occurred = err };
                };
                
                return OperationResult{ .completed = IOData{ .accepted_fd = client_fd } };
            },
            .connect => {
                std.os.connect(operation.fd, &operation.address.any, operation.address.getOsSockLen()) catch |err| {
                    if (err == error.WouldBlock or err == error.ConnectionPending) {
                        return OperationResult{ .would_block = {} };
                    }
                    return OperationResult{ .error_occurred = err };
                };
                
                return OperationResult{ .completed = IOData{ .connected = true } };
            },
        }
    }
    
    /// Add operation to epoll for monitoring
    pub fn addToEpoll(self: *NetPoller, operation: NetworkOperation) !void {
        var event = std.os.linux.epoll_event{
            .events = switch (operation.type) {
                .read, .accept => std.os.linux.EPOLL.IN,
                .write, .connect => std.os.linux.EPOLL.OUT,
            },
            .data = .{ .fd = operation.fd },
        };
        
        try std.os.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, operation.fd, &event);
        try self.pending_operations.put(operation.fd, operation);
    }
    
    /// Poll for ready operations
    pub fn poll(self: *NetPoller) ![]NetworkOperation {
        const ready_count = std.os.epoll_wait(self.epoll_fd, self.events, 0) catch |err| {
            if (err == error.Interrupted) {
                return &[_]NetworkOperation{};
            }
            return err;
        };
        
        var ready_operations = try self.allocator.alloc(NetworkOperation, ready_count);
        var count: usize = 0;
        
        for (self.events[0..ready_count]) |event| {
            const fd = event.data.fd;
            if (self.pending_operations.get(fd)) |operation| {
                ready_operations[count] = operation;
                count += 1;
                
                // Remove from epoll and pending operations
                std.os.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, fd, null) catch {};
                _ = self.pending_operations.remove(fd);
            }
        }
        
        return ready_operations[0..count];
    }
};

/// File I/O manager using thread pool for blocking operations
/// Requirement 5.6 - add file I/O integration
pub const FileIOManager = struct {
    allocator: std.mem.Allocator,
    thread_pool: std.Thread.Pool,
    pending_operations: std.HashMap(u64, FileOperation, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage),
    completed_operations: std.ArrayList(FileOperationResult),
    next_operation_id: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator) !FileIOManager {
        var thread_pool: std.Thread.Pool = undefined;
        try thread_pool.init(.{ .allocator = allocator, .n_jobs = 4 });
        
        return FileIOManager{
            .allocator = allocator,
            .thread_pool = thread_pool,
            .pending_operations = std.HashMap(u64, FileOperation, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .completed_operations = std.ArrayList(FileOperationResult).init(allocator),
            .next_operation_id = std.atomic.Value(u64).init(1),
            .mutex = .{},
        };
    }
    
    pub fn deinit(self: *FileIOManager) void {
        self.thread_pool.deinit();
        self.pending_operations.deinit();
        self.completed_operations.deinit();
    }
    
    /// Submit file operation to thread pool
    pub fn submitOperation(self: *FileIOManager, operation: FileOperation) !OperationResult {
        const operation_id = self.next_operation_id.fetchAdd(1, .monotonic);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.pending_operations.put(operation_id, operation);
        
        // Submit to thread pool
        try self.thread_pool.spawn(fileOperationWorker, .{ self, operation_id, operation });
        
        return OperationResult{ .queued = {} };
    }
    
    /// Worker function for file operations
    fn fileOperationWorker(self: *FileIOManager, operation_id: u64, operation: FileOperation) void {
        const result = self.performFileOperation(operation);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.completed_operations.append(FileOperationResult{
            .operation_id = operation_id,
            .result = result,
        }) catch {};
        
        _ = self.pending_operations.remove(operation_id);
    }
    
    /// Perform actual file operation
    fn performFileOperation(self: *FileIOManager, operation: FileOperation) IOData {
        _ = self;
        
        switch (operation.type) {
            .read => {
                const file = std.fs.cwd().openFile(operation.path, .{}) catch |err| {
                    return IOData{ .error_occurred = err };
                };
                defer file.close();
                
                const bytes_read = file.read(operation.buffer) catch |err| {
                    return IOData{ .error_occurred = err };
                };
                
                return IOData{ .bytes_read = bytes_read };
            },
            .write => {
                const file = std.fs.cwd().createFile(operation.path, .{}) catch |err| {
                    return IOData{ .error_occurred = err };
                };
                defer file.close();
                
                const bytes_written = file.write(operation.data) catch |err| {
                    return IOData{ .error_occurred = err };
                };
                
                return IOData{ .bytes_written = bytes_written };
            },
            .stat => {
                const stat = std.fs.cwd().statFile(operation.path) catch |err| {
                    return IOData{ .error_occurred = err };
                };
                
                return IOData{ .file_stat = stat };
            },
        }
    }
    
    /// Poll for completed operations
    pub fn pollCompleted(self: *FileIOManager) ![]FileOperationResult {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const completed = try self.completed_operations.toOwnedSlice();
        self.completed_operations = std.ArrayList(FileOperationResult).init(self.allocator);
        
        return completed;
    }
};

/// I/O wait queues for managing blocked coroutines
/// Requirement 5.6 - create I/O wait queues
pub const IOWaitQueues = struct {
    allocator: std.mem.Allocator,
    network_waiters: std.HashMap(i32, IOWaiter, std.hash_map.DefaultContext(i32), std.hash_map.default_max_load_percentage),
    file_waiters: std.HashMap(u64, IOWaiter, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage),
    mutex: std.Thread.Mutex,
    
    pub const IOWaiter = struct {
        coroutine_id: u64,
        start_time: i64,
        operation_type: IOOperationType,
        
        pub const IOOperationType = enum {
            network_read,
            network_write,
            network_accept,
            network_connect,
            file_read,
            file_write,
            file_stat,
        };
    };
    
    pub fn init(allocator: std.mem.Allocator) IOWaitQueues {
        return IOWaitQueues{
            .allocator = allocator,
            .network_waiters = std.HashMap(i32, IOWaiter, std.hash_map.DefaultContext(i32), std.hash_map.default_max_load_percentage).init(allocator),
            .file_waiters = std.HashMap(u64, IOWaiter, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = .{},
        };
    }
    
    pub fn deinit(self: *IOWaitQueues) void {
        self.network_waiters.deinit();
        self.file_waiters.deinit();
    }
    
    /// Add network operation waiter
    pub fn addNetworkWaiter(self: *IOWaitQueues, coroutine_id: u64, operation: NetworkOperation, start_time: i64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const waiter = IOWaiter{
            .coroutine_id = coroutine_id,
            .start_time = start_time,
            .operation_type = switch (operation.type) {
                .read => .network_read,
                .write => .network_write,
                .accept => .network_accept,
                .connect => .network_connect,
            },
        };
        
        try self.network_waiters.put(operation.fd, waiter);
    }
    
    /// Remove network operation waiter
    pub fn removeNetworkWaiter(self: *IOWaitQueues, operation: NetworkOperation) ?IOWaiter {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.network_waiters.fetchRemove(operation.fd);
    }
    
    /// Add file operation waiter
    pub fn addFileWaiter(self: *IOWaitQueues, coroutine_id: u64, operation: FileOperation, start_time: i64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const waiter = IOWaiter{
            .coroutine_id = coroutine_id,
            .start_time = start_time,
            .operation_type = switch (operation.type) {
                .read => .file_read,
                .write => .file_write,
                .stat => .file_stat,
            },
        };
        
        // Use a hash of the operation as the key
        const key = std.hash_map.hashString(operation.path);
        try self.file_waiters.put(key, waiter);
    }
    
    /// Remove file operation waiter
    pub fn removeFileWaiter(self: *IOWaitQueues, result: FileOperationResult) ?IOWaiter {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.file_waiters.fetchRemove(result.operation_id);
    }
    
    /// Get network waiter count
    pub fn getNetworkWaiterCount(self: *IOWaitQueues) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.network_waiters.count();
    }
    
    /// Get file waiter count
    pub fn getFileWaiterCount(self: *IOWaitQueues) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.file_waiters.count();
    }
};

// Data structures for I/O operations

pub const NetworkOperation = struct {
    type: Type,
    fd: i32,
    buffer: []u8 = &[_]u8{},
    data: []const u8 = &[_]u8{},
    address: std.net.Address = undefined,
    
    pub const Type = enum {
        read,
        write,
        accept,
        connect,
    };
};

pub const FileOperation = struct {
    type: Type,
    path: []const u8,
    buffer: []u8 = &[_]u8{},
    data: []const u8 = &[_]u8{},
    
    pub const Type = enum {
        read,
        write,
        stat,
    };
};

pub const IOData = union(enum) {
    bytes_read: usize,
    bytes_written: usize,
    accepted_fd: i32,
    connected: bool,
    file_stat: std.fs.File.Stat,
    error_occurred: anyerror,
};

pub const OperationResult = union(enum) {
    completed: IOData,
    would_block: void,
    queued: void,
    error_occurred: anyerror,
};

pub const IOResult = union(enum) {
    completed: IOData,
    pending: u64, // coroutine_id
    error_occurred: anyerror,
};

pub const FileOperationResult = struct {
    operation_id: u64,
    result: IOData,
};

pub const IOStats = struct {
    total_operations: u64,
    blocked_operations: u64,
    average_wait_time_ns: u64,
    pending_network_operations: usize,
    pending_file_operations: usize,
    
    pub fn getBlockingRatio(self: IOStats) f64 {
        return if (self.total_operations > 0) 
            @as(f64, @floatFromInt(self.blocked_operations)) / @as(f64, @floatFromInt(self.total_operations))
        else 
            0.0;
    }
};

// Tests
test "I/O integration initialization" {
    const allocator = std.testing.allocator;
    
    // Create mock scheduler
    const config = Scheduler.SchedulerConfig{
        .num_processors = 1,
        .num_workers = 1,
    };
    const mock_vm = @as(*anyopaque, @ptrFromInt(0x1000));
    var scheduler = try Scheduler.init(allocator, config, mock_vm);
    defer scheduler.deinit();
    
    var io_integration = try IOIntegration.init(allocator, &scheduler);
    defer io_integration.deinit();
    
    const stats = io_integration.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_operations);
    try std.testing.expectEqual(@as(u64, 0), stats.blocked_operations);
    try std.testing.expectEqual(@as(usize, 0), stats.pending_network_operations);
    try std.testing.expectEqual(@as(usize, 0), stats.pending_file_operations);
}

test "network poller initialization" {
    const allocator = std.testing.allocator;
    
    var netpoller = try NetPoller.init(allocator);
    defer netpoller.deinit();
    
    try std.testing.expect(netpoller.epoll_fd >= 0);
    try std.testing.expectEqual(@as(u32, 1024), netpoller.max_events);
    try std.testing.expectEqual(@as(usize, 0), netpoller.pending_operations.count());
}

test "file I/O manager initialization" {
    const allocator = std.testing.allocator;
    
    var file_io = try FileIOManager.init(allocator);
    defer file_io.deinit();
    
    try std.testing.expectEqual(@as(u64, 1), file_io.next_operation_id.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), file_io.pending_operations.count());
    try std.testing.expectEqual(@as(usize, 0), file_io.completed_operations.items.len);
}

test "I/O wait queues management" {
    const allocator = std.testing.allocator;
    
    var wait_queues = IOWaitQueues.init(allocator);
    defer wait_queues.deinit();
    
    try std.testing.expectEqual(@as(usize, 0), wait_queues.getNetworkWaiterCount());
    try std.testing.expectEqual(@as(usize, 0), wait_queues.getFileWaiterCount());
    
    const network_op = NetworkOperation{
        .type = .read,
        .fd = 1,
    };
    
    try wait_queues.addNetworkWaiter(123, network_op, std.time.nanoTimestamp());
    try std.testing.expectEqual(@as(usize, 1), wait_queues.getNetworkWaiterCount());
    
    const waiter = wait_queues.removeNetworkWaiter(network_op);
    try std.testing.expect(waiter != null);
    try std.testing.expectEqual(@as(u64, 123), waiter.?.coroutine_id);
    try std.testing.expectEqual(@as(usize, 0), wait_queues.getNetworkWaiterCount());
}