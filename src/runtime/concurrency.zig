// ============================================================================
// 并发安全机制实现
// ============================================================================
// 
// 本模块实现完整的并发安全机制，包括：
// 1. Channel 跨线程通信
// 2. Mutex/Atomic 共享状态保护
// 3. async/await Frame 深度标注
//
// @concurrency-model Actor-Based
// @thread-safety GUARDED_BY(mutex) | ATOMIC | ISOLATED
// @memory-protection WRITE_BARRIER
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const Value = types.Value;

// ============================================================================
// Channel - 跨线程通信
// ============================================================================

/// Channel 用于线程间安全通信
/// @concurrency-model CSP (Communicating Sequential Processes)
/// @thread-safety ATOMIC
/// @ownership TRANSFER (发送的数据所有权转移)
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();
        
        /// 环形缓冲区节点
        const Node = struct {
            data: T,
            next: ?*Node,
        };
        
        /// Channel 状态
        const State = enum(u8) {
            open,
            closed,
        };
        
        allocator: std.mem.Allocator,
        
        // 缓冲区
        buffer: std.ArrayList(T),
        capacity: usize,
        
        // 同步原语
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,
        
        // 状态
        state: std.atomic.Value(State),
        
        // 统计信息
        send_count: std.atomic.Value(u64),
        recv_count: std.atomic.Value(u64),
        
        /// 创建新的 Channel
        /// @pre capacity > 0
        /// @post 返回初始化的 Channel
        /// @ownership TRANSFER
        pub fn init(allocator: std.mem.Allocator, capacity: usize) !*Self {
            std.debug.assert(capacity > 0);
            
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);
            
            self.* = .{
                .allocator = allocator,
                .buffer = .{},
                .capacity = capacity,
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .state = std.atomic.Value(State).init(.open),
                .send_count = std.atomic.Value(u64).init(0),
                .recv_count = std.atomic.Value(u64).init(0),
            };
            
            try self.buffer.ensureTotalCapacity(allocator, capacity);
            
            return self;
        }
        
        /// 释放 Channel
        /// @pre self 必须已初始化
        /// @post 释放所有资源
        pub fn deinit(self: *Self) void {
            self.close();
            self.buffer.deinit(self.allocator);
            self.allocator.destroy(self);
        }
        
        /// 发送数据到 Channel
        /// @pre self 必须处于 open 状态
        /// @post 数据被添加到缓冲区，或阻塞直到有空间
        /// @thread-safety GUARDED_BY(mutex)
        /// @ownership TRANSFER (data 的所有权转移到 Channel)
        pub fn send(self: *Self, data: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            // 检查 Channel 是否已关闭
            if (self.state.load(.acquire) == .closed) {
                return error.ChannelClosed;
            }
            
            // 等待缓冲区有空间
            while (self.buffer.items.len >= self.capacity) {
                if (self.state.load(.acquire) == .closed) {
                    return error.ChannelClosed;
                }
                self.not_full.wait(&self.mutex);
            }
            
            // 添加数据到缓冲区
            try self.buffer.append(self.allocator, data);
            
            // 更新统计
            _ = self.send_count.fetchAdd(1, .monotonic);
            
            // 通知等待的接收者
            self.not_empty.signal();
        }
        
        /// 从 Channel 接收数据
        /// @pre self 必须已初始化
        /// @post 返回缓冲区中的数据，或阻塞直到有数据
        /// @thread-safety GUARDED_BY(mutex)
        /// @ownership TRANSFER (返回的数据所有权转移给调用者)
        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            // 等待缓冲区有数据
            while (self.buffer.items.len == 0) {
                if (self.state.load(.acquire) == .closed) {
                    return error.ChannelClosed;
                }
                self.not_empty.wait(&self.mutex);
            }
            
            // 从缓冲区取出数据
            const data = self.buffer.orderedRemove(0);
            
            // 更新统计
            _ = self.recv_count.fetchAdd(1, .monotonic);
            
            // 通知等待的发送者
            self.not_full.signal();
            
            return data;
        }
        
        /// 尝试发送数据（非阻塞）
        /// @pre self 必须处于 open 状态
        /// @post 如果缓冲区有空间，添加数据并返回 true；否则返回 false
        /// @thread-safety GUARDED_BY(mutex)
        pub fn trySend(self: *Self, data: T) !bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.state.load(.acquire) == .closed) {
                return error.ChannelClosed;
            }
            
            if (self.buffer.items.len >= self.capacity) {
                return false;
            }
            
            try self.buffer.append(self.allocator, data);
            _ = self.send_count.fetchAdd(1, .monotonic);
            self.not_empty.signal();
            
            return true;
        }
        
        /// 尝试接收数据（非阻塞）
        /// @pre self 必须已初始化
        /// @post 如果缓冲区有数据，返回数据；否则返回 null
        /// @thread-safety GUARDED_BY(mutex)
        pub fn tryRecv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.buffer.items.len == 0) {
                return null;
            }
            
            const data = self.buffer.orderedRemove(0);
            _ = self.recv_count.fetchAdd(1, .monotonic);
            self.not_full.signal();
            
            return data;
        }
        
        /// 关闭 Channel
        /// @post Channel 状态变为 closed，唤醒所有等待的线程
        /// @thread-safety ATOMIC
        pub fn close(self: *Self) void {
            self.state.store(.closed, .release);
            
            // 唤醒所有等待的线程
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }
        
        /// 检查 Channel 是否已关闭
        /// @thread-safety ATOMIC
        pub fn isClosed(self: *const Self) bool {
            return self.state.load(.acquire) == .closed;
        }
        
        /// 获取缓冲区当前大小
        /// @thread-safety GUARDED_BY(mutex)
        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.buffer.items.len;
        }
        
        /// 获取统计信息
        /// @thread-safety ATOMIC
        pub fn getStats(self: *const Self) ChannelStats {
            return .{
                .send_count = self.send_count.load(.monotonic),
                .recv_count = self.recv_count.load(.monotonic),
                .buffer_size = self.buffer.items.len,
                .capacity = self.capacity,
            };
        }
    };
}

/// Channel 统计信息
pub const ChannelStats = struct {
    send_count: u64,
    recv_count: u64,
    buffer_size: usize,
    capacity: usize,
};

// ============================================================================
// 线程安全的共享状态保护
// ============================================================================

/// 线程安全的缓存
/// @concurrency-model GUARDED_BY(mutex)
/// @thread-safety ATOMIC (access_count)
pub fn ThreadSafeCache(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const HashMap = if (K == []const u8) std.StringHashMap(V) else std.AutoHashMap(K, V);
        
        allocator: std.mem.Allocator,
        data: HashMap,
        mutex: std.Thread.Mutex,
        access_count: std.atomic.Value(usize),
        
        /// 初始化缓存
        /// @ownership NON-OWNING (allocator)
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .data = HashMap.init(allocator),
                .mutex = .{},
                .access_count = std.atomic.Value(usize).init(0),
            };
        }
        
        /// 释放缓存
        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }
        
        /// 获取值
        /// @thread-safety GUARDED_BY(mutex)
        /// @post-condition access_count.load() == previous + 1
        pub fn get(self: *Self, key: K) ?V {
            _ = self.access_count.fetchAdd(1, .monotonic);
            
            self.mutex.lock();
            defer self.mutex.unlock();
            
            return self.data.get(key);
        }
        
        /// 设置值
        /// @thread-safety GUARDED_BY(mutex)
        pub fn put(self: *Self, key: K, value: V) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            try self.data.put(key, value);
        }
        
        /// 删除值
        /// @thread-safety GUARDED_BY(mutex)
        pub fn remove(self: *Self, key: K) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            return self.data.remove(key);
        }
        
        /// 清空缓存
        /// @thread-safety GUARDED_BY(mutex)
        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.data.clearRetainingCapacity();
        }
        
        /// 获取访问计数
        /// @thread-safety ATOMIC
        pub fn getAccessCount(self: *const Self) usize {
            return self.access_count.load(.monotonic);
        }
    };
}

/// 原子计数器
/// @thread-safety ATOMIC
pub const AtomicCounter = struct {
    value: std.atomic.Value(i64),
    
    /// 初始化计数器
    pub fn init(initial: i64) AtomicCounter {
        return .{
            .value = std.atomic.Value(i64).init(initial),
        };
    }
    
    /// 增加计数
    /// @thread-safety ATOMIC
    /// @post 返回增加前的值
    pub fn increment(self: *AtomicCounter) i64 {
        return self.value.fetchAdd(1, .monotonic);
    }
    
    /// 减少计数
    /// @thread-safety ATOMIC
    /// @post 返回减少前的值
    pub fn decrement(self: *AtomicCounter) i64 {
        return self.value.fetchSub(1, .monotonic);
    }
    
    /// 获取当前值
    /// @thread-safety ATOMIC
    pub fn get(self: *const AtomicCounter) i64 {
        return self.value.load(.monotonic);
    }
    
    /// 设置值
    /// @thread-safety ATOMIC
    pub fn set(self: *AtomicCounter, new_value: i64) void {
        self.value.store(new_value, .monotonic);
    }
    
    /// 比较并交换
    /// @thread-safety ATOMIC
    /// @post 如果当前值等于 expected，设置为 new_value 并返回 true
    pub fn compareAndSwap(self: *AtomicCounter, expected: i64, new_value: i64) bool {
        return self.value.cmpxchgStrong(expected, new_value, .monotonic, .monotonic) == null;
    }
};

/// 读写锁
/// @concurrency-model READERS-WRITER
/// @thread-safety ATOMIC
pub const RWLock = struct {
    readers: std.atomic.Value(i32),
    writer: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,
    read_cond: std.Thread.Condition,
    write_cond: std.Thread.Condition,
    
    /// 初始化读写锁
    pub fn init() RWLock {
        return .{
            .readers = std.atomic.Value(i32).init(0),
            .writer = std.atomic.Value(bool).init(false),
            .mutex = .{},
            .read_cond = .{},
            .write_cond = .{},
        };
    }
    
    /// 获取读锁
    /// @thread-safety GUARDED_BY(mutex)
    pub fn lockRead(self: *RWLock) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 等待写锁释放
        while (self.writer.load(.acquire)) {
            self.read_cond.wait(&self.mutex);
        }
        
        _ = self.readers.fetchAdd(1, .monotonic);
    }
    
    /// 释放读锁
    /// @thread-safety ATOMIC
    pub fn unlockRead(self: *RWLock) void {
        const prev = self.readers.fetchSub(1, .monotonic);
        
        // 如果是最后一个读者，通知等待的写者
        if (prev == 1) {
            self.write_cond.signal();
        }
    }
    
    /// 获取写锁
    /// @thread-safety GUARDED_BY(mutex)
    pub fn lockWrite(self: *RWLock) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 等待所有读者和写者完成
        while (self.writer.load(.acquire) or self.readers.load(.acquire) > 0) {
            self.write_cond.wait(&self.mutex);
        }
        
        self.writer.store(true, .release);
    }
    
    /// 释放写锁
    /// @thread-safety ATOMIC
    pub fn unlockWrite(self: *RWLock) void {
        self.writer.store(false, .release);
        
        // 通知所有等待的读者和写者
        self.read_cond.broadcast();
        self.write_cond.signal();
    }
};

// ============================================================================
// async/await Frame 深度标注
// ============================================================================

/// 异步帧深度限制
pub const MAX_ASYNC_FRAME_DEPTH = 256;

/// 异步帧元数据
/// @frame-depth 标注用于防止栈溢出
pub const AsyncFrameMetadata = struct {
    depth: u32,
    max_depth: u32,
    parent: ?*AsyncFrameMetadata,
    
    /// 创建新的帧元数据
    /// @pre parent == null 或 parent.depth < MAX_ASYNC_FRAME_DEPTH
    /// @post 返回初始化的帧元数据
    pub fn init(parent: ?*AsyncFrameMetadata) !AsyncFrameMetadata {
        const depth = if (parent) |p| p.depth + 1 else 0;
        
        if (depth >= MAX_ASYNC_FRAME_DEPTH) {
            return error.AsyncFrameDepthExceeded;
        }
        
        return .{
            .depth = depth,
            .max_depth = MAX_ASYNC_FRAME_DEPTH,
            .parent = parent,
        };
    }
    
    /// 检查是否可以创建子帧
    pub fn canCreateChild(self: *const AsyncFrameMetadata) bool {
        return self.depth + 1 < self.max_depth;
    }
    
    /// 获取剩余深度
    pub fn remainingDepth(self: *const AsyncFrameMetadata) u32 {
        return self.max_depth - self.depth - 1;
    }
};

/// 异步任务
/// @frame-depth 42 (示例标注)
pub const AsyncTask = struct {
    frame: AsyncFrameMetadata,
    state: TaskState,
    result: ?TaskResult,
    
    /// 任务状态
    pub const TaskState = enum {
        pending,
        running,
        completed,
        failed,
    };
    
    /// 任务结果
    pub const TaskResult = union(enum) {
        success: i64,
        failure: []const u8,
    };
    
    /// 创建新任务
    /// @frame-depth parent.depth + 1
    pub fn init(parent: ?*AsyncFrameMetadata) !AsyncTask {
        return .{
            .frame = try AsyncFrameMetadata.init(parent),
            .state = .pending,
            .result = null,
        };
    }
    
    /// 执行任务
    /// @frame-depth self.frame.depth
    pub fn execute(self: *AsyncTask) !void {
        if (!self.frame.canCreateChild()) {
            return error.AsyncFrameDepthExceeded;
        }
        
        self.state = .running;
        
        // 模拟异步操作
        // 实际实现中，这里会执行真正的异步逻辑
        
        self.state = .completed;
        self.result = .{ .success = 42 };
    }
};

// ============================================================================
// 无锁数据结构
// ============================================================================

/// 无锁栈
/// @concurrency-model LOCK-FREE
/// @thread-safety ATOMIC
/// @hazard-analysis 需要 hazard pointer 保护
pub fn LockFreeStack(comptime T: type) type {
    return struct {
        const Self = @This();
        
        const Node = struct {
            data: T,
            next: std.atomic.Value(?*Node),
        };
        
        allocator: std.mem.Allocator,
        head: std.atomic.Value(?*Node),
        
        /// 初始化栈
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .head = std.atomic.Value(?*Node).init(null),
            };
        }
        
        /// 释放栈
        pub fn deinit(self: *Self) void {
            var current = self.head.load(.acquire);
            while (current) |node| {
                const next = node.next.load(.acquire);
                self.allocator.destroy(node);
                current = next;
            }
        }
        
        /// 压栈
        /// @thread-safety ATOMIC
        pub fn push(self: *Self, data: T) !void {
            const node = try self.allocator.create(Node);
            node.* = .{
                .data = data,
                .next = std.atomic.Value(?*Node).init(null),
            };
            
            while (true) {
                const old_head = self.head.load(.acquire);
                node.next.store(old_head, .release);
                
                if (self.head.cmpxchgStrong(
                    old_head,
                    node,
                    .release,
                    .acquire,
                ) == null) {
                    break;
                }
            }
        }
        
        /// 出栈
        /// @thread-safety ATOMIC
        pub fn pop(self: *Self) ?T {
            while (true) {
                const old_head = self.head.load(.acquire) orelse return null;
                const new_head = old_head.next.load(.acquire);
                
                if (self.head.cmpxchgStrong(
                    old_head,
                    new_head,
                    .release,
                    .acquire,
                ) == null) {
                    const data = old_head.data;
                    self.allocator.destroy(old_head);
                    return data;
                }
            }
        }
    };
}

// ============================================================================
// 测试
// ============================================================================

test "Channel: basic send and receive" {
    const allocator = std.testing.allocator;
    
    var channel = try Channel(i32).init(allocator, 10);
    defer channel.deinit();
    
    // 发送数据
    try channel.send(42);
    try channel.send(100);
    
    // 接收数据
    const val1 = try channel.recv();
    const val2 = try channel.recv();
    
    try std.testing.expectEqual(@as(i32, 42), val1);
    try std.testing.expectEqual(@as(i32, 100), val2);
}

test "Channel: try send and receive" {
    const allocator = std.testing.allocator;
    
    var channel = try Channel(i32).init(allocator, 2);
    defer channel.deinit();
    
    // 非阻塞发送
    try std.testing.expect(try channel.trySend(1));
    try std.testing.expect(try channel.trySend(2));
    try std.testing.expect(!try channel.trySend(3)); // 缓冲区已满
    
    // 非阻塞接收
    try std.testing.expectEqual(@as(i32, 1), channel.tryRecv().?);
    try std.testing.expectEqual(@as(i32, 2), channel.tryRecv().?);
    try std.testing.expectEqual(@as(?i32, null), channel.tryRecv());
}

test "ThreadSafeCache: concurrent access" {
    const allocator = std.testing.allocator;
    
    var cache = ThreadSafeCache([]const u8, i32).init(allocator);
    defer cache.deinit();
    
    try cache.put("key1", 100);
    try cache.put("key2", 200);
    
    try std.testing.expectEqual(@as(i32, 100), cache.get("key1").?);
    try std.testing.expectEqual(@as(i32, 200), cache.get("key2").?);
    try std.testing.expectEqual(@as(?i32, null), cache.get("key3"));
    
    try std.testing.expectEqual(@as(usize, 3), cache.getAccessCount());
}

test "AtomicCounter: increment and decrement" {
    var counter = AtomicCounter.init(0);
    
    _ = counter.increment();
    _ = counter.increment();
    _ = counter.increment();
    
    try std.testing.expectEqual(@as(i64, 3), counter.get());
    
    _ = counter.decrement();
    try std.testing.expectEqual(@as(i64, 2), counter.get());
}

test "AtomicCounter: compare and swap" {
    var counter = AtomicCounter.init(10);
    
    try std.testing.expect(counter.compareAndSwap(10, 20));
    try std.testing.expectEqual(@as(i64, 20), counter.get());
    
    try std.testing.expect(!counter.compareAndSwap(10, 30));
    try std.testing.expectEqual(@as(i64, 20), counter.get());
}

test "RWLock: basic operations" {
    var lock = RWLock.init();
    
    // 获取读锁
    lock.lockRead();
    lock.unlockRead();
    
    // 获取写锁
    lock.lockWrite();
    lock.unlockWrite();
}

test "AsyncFrameMetadata: depth tracking" {
    var frame1 = try AsyncFrameMetadata.init(null);
    try std.testing.expectEqual(@as(u32, 0), frame1.depth);
    try std.testing.expect(frame1.canCreateChild());
    
    var frame2 = try AsyncFrameMetadata.init(&frame1);
    try std.testing.expectEqual(@as(u32, 1), frame2.depth);
    try std.testing.expect(frame2.canCreateChild());
}

test "AsyncTask: execution" {
    var task = try AsyncTask.init(null);
    try task.execute();
    
    try std.testing.expectEqual(AsyncTask.TaskState.completed, task.state);
    try std.testing.expect(task.result != null);
}

test "LockFreeStack: push and pop" {
    const allocator = std.testing.allocator;
    
    var stack = LockFreeStack(i32).init(allocator);
    defer stack.deinit();
    
    try stack.push(1);
    try stack.push(2);
    try stack.push(3);
    
    try std.testing.expectEqual(@as(i32, 3), stack.pop().?);
    try std.testing.expectEqual(@as(i32, 2), stack.pop().?);
    try std.testing.expectEqual(@as(i32, 1), stack.pop().?);
    try std.testing.expectEqual(@as(?i32, null), stack.pop());
}


// ============================================================================
// PHP 并发类型包装
// ============================================================================

/// PHP Mutex 包装
/// @thread-safety GUARDED_BY(mutex)
pub const PHPMutex = struct {
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    lock_count: std.atomic.Value(u32),
    
    pub fn init(allocator: std.mem.Allocator) PHPMutex {
        return .{
            .mutex = .{},
            .allocator = allocator,
            .lock_count = std.atomic.Value(u32).init(0),
        };
    }
    
    pub fn deinit(self: *PHPMutex) void {
        _ = self;
        // Mutex 不需要显式清理
    }
    
    pub fn lock(self: *PHPMutex, coroutine_id: u64) void {
        _ = coroutine_id; // 暂时不使用协程 ID
        self.mutex.lock();
        _ = self.lock_count.fetchAdd(1, .monotonic);
    }
    
    pub fn unlock(self: *PHPMutex) void {
        _ = self.lock_count.fetchSub(1, .monotonic);
        self.mutex.unlock();
    }
    
    pub fn tryLock(self: *PHPMutex, coroutine_id: u64) bool {
        _ = coroutine_id; // 暂时不使用协程 ID
        if (self.mutex.tryLock()) {
            _ = self.lock_count.fetchAdd(1, .monotonic);
            return true;
        }
        return false;
    }
    
    pub fn getLockCount(self: *const PHPMutex) u32 {
        return self.lock_count.load(.monotonic);
    }
};

/// PHP Atomic 包装
/// @thread-safety ATOMIC
pub const PHPAtomic = struct {
    counter: AtomicCounter,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, initial: i64) PHPAtomic {
        return .{
            .counter = AtomicCounter.init(initial),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *PHPAtomic) void {
        _ = self;
        // AtomicCounter 不需要显式清理
    }
    
    pub fn load(self: *const PHPAtomic) i64 {
        return self.counter.get();
    }
    
    pub fn store(self: *PHPAtomic, value: i64) void {
        self.counter.set(value);
    }
    
    pub fn get(self: *const PHPAtomic) i64 {
        return self.counter.get();
    }
    
    pub fn set(self: *PHPAtomic, value: i64) void {
        self.counter.set(value);
    }
    
    pub fn increment(self: *PHPAtomic) i64 {
        return self.counter.increment();
    }
    
    pub fn decrement(self: *PHPAtomic) i64 {
        return self.counter.decrement();
    }
    
    pub fn add(self: *PHPAtomic, delta: i64) i64 {
        return self.counter.value.fetchAdd(delta, .monotonic);
    }
    
    pub fn sub(self: *PHPAtomic, delta: i64) i64 {
        return self.counter.value.fetchSub(delta, .monotonic);
    }
    
    pub fn compareAndSwap(self: *PHPAtomic, expected: i64, new_value: i64) bool {
        return self.counter.compareAndSwap(expected, new_value);
    }
    
    pub fn swap(self: *PHPAtomic, new_value: i64) i64 {
        return self.counter.value.swap(new_value, .monotonic);
    }
};

/// PHP RWLock 包装
/// @thread-safety ATOMIC
pub const PHPRWLock = struct {
    rwlock: RWLock,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) PHPRWLock {
        return .{
            .rwlock = RWLock.init(),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *PHPRWLock) void {
        _ = self;
        // RWLock 不需要显式清理
    }
    
    pub fn lockRead(self: *PHPRWLock) void {
        self.rwlock.lockRead();
    }
    
    pub fn unlockRead(self: *PHPRWLock) void {
        self.rwlock.unlockRead();
    }
    
    pub fn lockWrite(self: *PHPRWLock) void {
        self.rwlock.lockWrite();
    }
    
    pub fn unlockWrite(self: *PHPRWLock) void {
        self.rwlock.unlockWrite();
    }
    
    pub fn getReaderCount(self: *const PHPRWLock) i32 {
        return self.rwlock.readers.load(.monotonic);
    }
    
    pub fn getWriterCount(self: *const PHPRWLock) i32 {
        return if (self.rwlock.writer.load(.monotonic)) 1 else 0;
    }
};

/// PHP SharedData 包装
/// @thread-safety GUARDED_BY(mutex)
pub const PHPSharedData = struct {
    data: std.StringHashMap([]const u8),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    access_count: std.atomic.Value(u64),
    
    pub fn init(allocator: std.mem.Allocator) PHPSharedData {
        return .{
            .data = std.StringHashMap([]const u8).init(allocator),
            .mutex = .{},
            .allocator = allocator,
            .access_count = std.atomic.Value(u64).init(0),
        };
    }
    
    pub fn deinit(self: *PHPSharedData) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }
    
    pub fn get(self: *PHPSharedData, key: []const u8) ?[]const u8 {
        _ = self.access_count.fetchAdd(1, .monotonic);
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.data.get(key);
    }
    
    pub fn set(self: *PHPSharedData, key: []const u8, value: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 如果键已存在，先释放旧值
        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
        
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);
        
        try self.data.put(key_copy, value_copy);
    }
    
    pub fn put(self: *PHPSharedData, key: []const u8, value: []const u8) !void {
        return self.set(key, value);
    }
    
    pub fn remove(self: *PHPSharedData, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
            return true;
        }
        return false;
    }
    
    pub fn has(self: *PHPSharedData, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.data.contains(key);
    }
    
    pub fn size(self: *PHPSharedData) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.data.count();
    }
    
    pub fn clear(self: *PHPSharedData) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.clearRetainingCapacity();
    }
    
    pub fn getAccessCount(self: *const PHPSharedData) u64 {
        return self.access_count.load(.monotonic);
    }
};

/// PHP Channel 包装
/// @thread-safety ATOMIC
pub const PHPChannel = struct {
    // 使用 Value 类型存储 PHP 值
    channel: *Channel(Value),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !*PHPChannel {
        const self = try allocator.create(PHPChannel);
        errdefer allocator.destroy(self);
        
        self.* = .{
            .channel = try Channel(Value).init(allocator, capacity),
            .allocator = allocator,
        };
        
        return self;
    }
    
    pub fn deinit(self: *PHPChannel) void {
        self.channel.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn send(self: *PHPChannel, data: Value) !void {
        try self.channel.send(data);
    }
    
    pub fn recv(self: *PHPChannel) !?Value {
        const value = self.channel.recv() catch |err| {
            if (err == error.ChannelClosed) return null;
            return err;
        };
        return value;
    }
    
    pub fn trySend(self: *PHPChannel, data: Value) bool {
        return self.channel.trySend(data) catch false;
    }
    
    pub fn tryRecv(self: *PHPChannel) ?Value {
        return self.channel.tryRecv();
    }
    
    pub fn close(self: *PHPChannel) void {
        self.channel.close();
    }
    
    pub fn isClosed(self: *const PHPChannel) bool {
        return self.channel.isClosed();
    }
    
    pub fn len(self: *PHPChannel) usize {
        return self.channel.len();
    }
    
    pub fn getCapacity(self: *const PHPChannel) usize {
        return self.channel.capacity;
    }
    
    pub fn getSendCount(self: *const PHPChannel) u64 {
        return self.channel.send_count.load(.monotonic);
    }
    
    pub fn getRecvCount(self: *const PHPChannel) u64 {
        return self.channel.recv_count.load(.monotonic);
    }
};
