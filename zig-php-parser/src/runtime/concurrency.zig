const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// PHP 互斥锁 - 用于协程间的同步
pub const PHPMutex = struct {
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    lock_count: std.atomic.Value(u32),
    owner_thread: std.atomic.Value(u64),

    pub fn init(allocator: std.mem.Allocator) PHPMutex {
        return PHPMutex{
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
            .lock_count = std.atomic.Value(u32).init(0),
            .owner_thread = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *PHPMutex) void {
        _ = self;
    }

    /// 加锁
    pub fn lock(self: *PHPMutex) void {
        self.mutex.lock();
        _ = self.lock_count.fetchAdd(1, .seq_cst);
        self.owner_thread.store(std.Thread.getCurrentId(), .seq_cst);
    }

    /// 解锁
    pub fn unlock(self: *PHPMutex) void {
        _ = self.lock_count.fetchSub(1, .seq_cst);
        self.owner_thread.store(0, .seq_cst);
        self.mutex.unlock();
    }

    /// 尝试加锁
    pub fn tryLock(self: *PHPMutex) bool {
        if (self.mutex.tryLock()) {
            _ = self.lock_count.fetchAdd(1, .seq_cst);
            self.owner_thread.store(std.Thread.getCurrentId(), .seq_cst);
            return true;
        }
        return false;
    }

    /// 获取锁计数
    pub fn getLockCount(self: *PHPMutex) u32 {
        return self.lock_count.load(.seq_cst);
    }

    /// 检查是否被当前线程持有
    pub fn isLockedByCurrentThread(self: *PHPMutex) bool {
        const current = std.Thread.getCurrentId();
        const owner = self.owner_thread.load(.seq_cst);
        return owner != 0 and owner == current;
    }
};

/// PHP 原子整数 - 用于无锁并发计数
pub const PHPAtomic = struct {
    value: std.atomic.Value(i64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, initial_value: i64) PHPAtomic {
        return PHPAtomic{
            .value = std.atomic.Value(i64).init(initial_value),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PHPAtomic) void {
        _ = self;
    }

    /// 获取当前值
    pub fn load(self: *PHPAtomic) i64 {
        return self.value.load(.seq_cst);
    }

    /// 设置值
    pub fn store(self: *PHPAtomic, new_value: i64) void {
        self.value.store(new_value, .seq_cst);
    }

    /// 原子加法
    pub fn add(self: *PHPAtomic, delta: i64) i64 {
        return self.value.fetchAdd(delta, .seq_cst);
    }

    /// 原子减法
    pub fn sub(self: *PHPAtomic, delta: i64) i64 {
        return self.value.fetchSub(delta, .seq_cst);
    }

    /// 原子递增
    pub fn increment(self: *PHPAtomic) i64 {
        return self.value.fetchAdd(1, .seq_cst) + 1;
    }

    /// 原子递减
    pub fn decrement(self: *PHPAtomic) i64 {
        return self.value.fetchSub(1, .seq_cst) - 1;
    }

    /// 比较并交换
    pub fn compareAndSwap(self: *PHPAtomic, expected: i64, new_value: i64) bool {
        const result = self.value.cmpxchgStrong(expected, new_value, .seq_cst, .seq_cst);
        return result == null;
    }

    /// 交换值
    pub fn swap(self: *PHPAtomic, new_value: i64) i64 {
        return self.value.swap(new_value, .seq_cst);
    }
};

/// PHP 读写锁 - 支持多读单写
pub const PHPRWLock = struct {
    rwlock: std.Thread.RwLock,
    allocator: std.mem.Allocator,
    reader_count: std.atomic.Value(u32),
    writer_count: std.atomic.Value(u32),

    pub fn init(allocator: std.mem.Allocator) PHPRWLock {
        return PHPRWLock{
            .rwlock = std.Thread.RwLock{},
            .allocator = allocator,
            .reader_count = std.atomic.Value(u32).init(0),
            .writer_count = std.atomic.Value(u32).init(0),
        };
    }

    pub fn deinit(self: *PHPRWLock) void {
        _ = self;
    }

    /// 读锁
    pub fn lockRead(self: *PHPRWLock) void {
        self.rwlock.lockShared();
        _ = self.reader_count.fetchAdd(1, .seq_cst);
    }

    /// 解读锁
    pub fn unlockRead(self: *PHPRWLock) void {
        _ = self.reader_count.fetchSub(1, .seq_cst);
        self.rwlock.unlockShared();
    }

    /// 写锁
    pub fn lockWrite(self: *PHPRWLock) void {
        self.rwlock.lock();
        _ = self.writer_count.fetchAdd(1, .seq_cst);
    }

    /// 解写锁
    pub fn unlockWrite(self: *PHPRWLock) void {
        _ = self.writer_count.fetchSub(1, .seq_cst);
        self.rwlock.unlock();
    }

    /// 获取读者数量
    pub fn getReaderCount(self: *PHPRWLock) u32 {
        return self.reader_count.load(.seq_cst);
    }

    /// 获取写者数量
    pub fn getWriterCount(self: *PHPRWLock) u32 {
        return self.writer_count.load(.seq_cst);
    }
};

/// 并发安全的共享数据容器
pub const PHPSharedData = struct {
    data: std.StringHashMap(Value),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    access_count: std.atomic.Value(u64),

    pub fn init(allocator: std.mem.Allocator) PHPSharedData {
        return PHPSharedData{
            .data = std.StringHashMap(Value).init(allocator),
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
            .access_count = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *PHPSharedData) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.data.deinit();
    }

    /// 设置值（线程安全）
    pub fn set(self: *PHPSharedData, key: []const u8, value: Value) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.access_count.fetchAdd(1, .seq_cst);

        if (self.data.getEntry(key)) |entry| {
            entry.value_ptr.release(self.allocator);
            entry.value_ptr.* = value.retain();
            return;
        }

        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = value.retain();
        try self.data.put(key_copy, value_copy);
    }

    /// 获取值（线程安全）
    pub fn get(self: *PHPSharedData, key: []const u8) ?Value {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.access_count.fetchAdd(1, .seq_cst);

        if (self.data.get(key)) |value| {
            return value.retain();
        }
        return null;
    }

    /// 删除值（线程安全）
    pub fn remove(self: *PHPSharedData, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.access_count.fetchAdd(1, .seq_cst);

        if (self.data.fetchRemove(key)) |kv| {
            kv.value.release(self.allocator);
            self.allocator.free(kv.key);
            return true;
        }
        return false;
    }

    /// 检查键是否存在
    pub fn has(self: *PHPSharedData, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.data.contains(key);
    }

    /// 获取访问计数
    pub fn getAccessCount(self: *PHPSharedData) u64 {
        return self.access_count.load(.seq_cst);
    }

    /// 获取数据大小
    pub fn size(self: *PHPSharedData) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.data.count();
    }

    /// 清空所有数据
    pub fn clear(self: *PHPSharedData) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.data.clearRetainingCapacity();
    }
};

/// Channel - Go 风格的通道实现，用于协程间通信
/// 支持有缓冲和无缓冲两种模式
pub const PHPChannel = struct {
    buffer: std.ArrayList(Value),
    capacity: usize,
    mutex: std.Thread.Mutex,
    not_empty: std.Thread.Condition,
    not_full: std.Thread.Condition,
    closed: std.atomic.Value(bool),
    allocator: std.mem.Allocator,
    send_count: std.atomic.Value(u64),
    recv_count: std.atomic.Value(u64),

    /// 创建 Channel
    /// capacity = 0 表示无缓冲 Channel（同步模式）
    /// capacity > 0 表示有缓冲 Channel（异步模式）
    pub fn init(allocator: std.mem.Allocator, capacity: usize) PHPChannel {
        return PHPChannel{
            .buffer = std.ArrayList(Value){},
            .capacity = if (capacity == 0) 1 else capacity,
            .mutex = std.Thread.Mutex{},
            .not_empty = std.Thread.Condition{},
            .not_full = std.Thread.Condition{},
            .closed = std.atomic.Value(bool).init(false),
            .allocator = allocator,
            .send_count = std.atomic.Value(u64).init(0),
            .recv_count = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *PHPChannel) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.buffer.items) |item| {
            item.release(self.allocator);
        }
        self.buffer.deinit(self.allocator);
    }

    /// 发送数据到 Channel（阻塞）
    pub fn send(self: *PHPChannel, value: Value) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed.load(.seq_cst)) {
            return error.ChannelClosed;
        }

        while (self.buffer.items.len >= self.capacity) {
            if (self.closed.load(.seq_cst)) {
                return error.ChannelClosed;
            }
            self.not_full.wait(&self.mutex);
        }

        try self.buffer.append(self.allocator, value.retain());
        _ = self.send_count.fetchAdd(1, .seq_cst);
        self.not_empty.signal();
    }

    /// 尝试发送数据（非阻塞）
    pub fn trySend(self: *PHPChannel, value: Value) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed.load(.seq_cst)) {
            return false;
        }

        if (self.buffer.items.len >= self.capacity) {
            return false;
        }

        self.buffer.append(self.allocator, value.retain()) catch return false;
        _ = self.send_count.fetchAdd(1, .seq_cst);
        self.not_empty.signal();
        return true;
    }

    /// 从 Channel 接收数据（阻塞）
    pub fn recv(self: *PHPChannel) ?Value {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.buffer.items.len == 0) {
            if (self.closed.load(.seq_cst)) {
                return null;
            }
            self.not_empty.wait(&self.mutex);
        }

        const value = self.buffer.orderedRemove(0);
        _ = self.recv_count.fetchAdd(1, .seq_cst);
        self.not_full.signal();
        return value;
    }

    /// 尝试接收数据（非阻塞）
    pub fn tryRecv(self: *PHPChannel) ?Value {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.buffer.items.len == 0) {
            return null;
        }

        const value = self.buffer.orderedRemove(0);
        _ = self.recv_count.fetchAdd(1, .seq_cst);
        self.not_full.signal();
        return value;
    }

    /// 关闭 Channel
    pub fn close(self: *PHPChannel) void {
        self.closed.store(true, .seq_cst);
        self.mutex.lock();
        defer self.mutex.unlock();
        self.not_empty.broadcast();
        self.not_full.broadcast();
    }

    /// 检查是否已关闭
    pub fn isClosed(self: *PHPChannel) bool {
        return self.closed.load(.seq_cst);
    }

    /// 获取当前缓冲区大小
    pub fn len(self: *PHPChannel) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.buffer.items.len;
    }

    /// 获取容量
    pub fn getCapacity(self: *PHPChannel) usize {
        return self.capacity;
    }

    /// 获取发送计数
    pub fn getSendCount(self: *PHPChannel) u64 {
        return self.send_count.load(.seq_cst);
    }

    /// 获取接收计数
    pub fn getRecvCount(self: *PHPChannel) u64 {
        return self.recv_count.load(.seq_cst);
    }
};

test "PHPMutex basic operations" {
    const allocator = std.testing.allocator;
    var mutex = PHPMutex.init(allocator);
    defer mutex.deinit();

    try std.testing.expect(mutex.getLockCount() == 0);

    mutex.lock();
    try std.testing.expect(mutex.getLockCount() == 1);
    try std.testing.expect(mutex.isLockedByCurrentThread());

    mutex.unlock();
    try std.testing.expect(mutex.getLockCount() == 0);
}

test "PHPAtomic operations" {
    const allocator = std.testing.allocator;
    var atomic = PHPAtomic.init(allocator, 0);
    defer atomic.deinit();

    try std.testing.expect(atomic.load() == 0);

    _ = atomic.increment();
    try std.testing.expect(atomic.load() == 1);

    _ = atomic.add(5);
    try std.testing.expect(atomic.load() == 6);

    _ = atomic.decrement();
    try std.testing.expect(atomic.load() == 5);

    const old = atomic.swap(100);
    try std.testing.expect(old == 5);
    try std.testing.expect(atomic.load() == 100);
}

test "PHPSharedData concurrent access" {
    const allocator = std.testing.allocator;
    var shared = PHPSharedData.init(allocator);
    defer shared.deinit();

    const value1 = Value.initInteger(42);
    try shared.set("key1", value1);

    if (shared.get("key1")) |val| {
        defer val.release(allocator);
        try std.testing.expect(val.tag == .integer);
        try std.testing.expect(val.data.integer == 42);
    }

    try std.testing.expect(shared.has("key1"));
    try std.testing.expect(shared.size() == 1);
    try std.testing.expect(shared.getAccessCount() >= 3);
}
