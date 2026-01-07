//! ============================================================================
//! 同步原语 (Synchronization Primitives)
//! ============================================================================
//!
//! 功能：提供协程感知的同步原语，用于协程间同步
//!
//! 组件架构：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                    Synchronization Primitives                    │
//! │                                                                  │
//! │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
//! │  │    Mutex     │  │   RWMutex    │  │  WaitGroup   │          │
//! │  │  (互斥锁)    │  │  (读写锁)    │  │  (等待组)    │          │
//! │  │              │  │              │  │              │          │
//! │  │ lock()       │  │ readLock()   │  │ add(n)       │          │
//! │  │ unlock()     │  │ writeLock()  │  │ done()       │          │
//! │  │ tryLock()    │  │ readUnlock() │  │ wait()       │          │
//! │  │              │  │ writeUnlock()│  │              │          │
//! │  └──────────────┘  └──────────────┘  └──────────────┘          │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────┐          │
//! │  │                   WaitQueue                       │          │
//! │  │  (等待队列 - 管理阻塞的协程)                       │          │
//! │  │  add() -> wakeOne() / wakeAll()                  │          │
//! │  └──────────────────────────────────────────────────┘          │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! Mutex (互斥锁)：
//! - 协程感知：追踪持有锁的协程ID
//! - 支持tryLock非阻塞尝试
//! - 等待队列管理阻塞协程
//!
//! RWMutex (读写锁)：
//! - 多读单写：允许多个读者同时访问
//! - 写优先：有写者等待时，新读者阻塞
//! - 适用于读多写少的场景
//!
//! WaitGroup (等待组)：
//! - 等待一组协程完成
//! - add(n): 增加计数
//! - done(): 减少计数
//! - wait(): 阻塞直到计数为0
//!
//! 需求：8.1, 8.2, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9, 8.10, 8.11
//! ============================================================================

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// 阻塞协程的等待队列
/// 用于管理等待锁或条件的协程
pub const WaitQueue = struct {
    waiters: std.ArrayListUnmanaged(Waiter),
    allocator: std.mem.Allocator,
    
    pub const Waiter = struct {
        coroutine_id: u64,
        ready: std.atomic.Value(bool),
        next: ?*Waiter = null,
    };
    
    pub fn init(allocator: std.mem.Allocator) WaitQueue {
        return WaitQueue{
            .waiters = .{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *WaitQueue) void {
        self.waiters.deinit(self.allocator);
    }
    
    pub fn add(self: *WaitQueue, coroutine_id: u64) !void {
        try self.waiters.append(self.allocator, Waiter{
            .coroutine_id = coroutine_id,
            .ready = std.atomic.Value(bool).init(false),
        });
    }
    
    pub fn wakeOne(self: *WaitQueue) ?u64 {
        if (self.waiters.items.len > 0) {
            const waiter = self.waiters.orderedRemove(0);
            // Note: waiter.ready is a copy, but we don't need to update it
            // since the waiter is being removed from the queue
            return waiter.coroutine_id;
        }
        return null;
    }
    
    pub fn wakeAll(self: *WaitQueue) void {
        // Note: We don't need to update ready flags since waiters are being removed
        self.waiters.clearRetainingCapacity();
    }
    
    pub fn remove(self: *WaitQueue, coroutine_id: u64) bool {
        for (self.waiters.items, 0..) |waiter, i| {
            if (waiter.coroutine_id == coroutine_id) {
                _ = self.waiters.orderedRemove(i);
                return true;
            }
        }
        return false;
    }
    
    pub fn isEmpty(self: *WaitQueue) bool {
        return self.waiters.items.len == 0;
    }
    
    pub fn len(self: *WaitQueue) usize {
        return self.waiters.items.len;
    }
};

/// Coroutine-aware Mutex with atomic operations and wait queues
/// Requirements: 8.1, 8.2, 8.4
pub const Mutex = struct {
    locked: std.atomic.Value(bool),
    owner: std.atomic.Value(u64),
    wait_queue: WaitQueue,
    mutex: std.Thread.Mutex, // Protects wait_queue operations
    
    pub fn init(allocator: std.mem.Allocator) Mutex {
        return Mutex{
            .locked = std.atomic.Value(bool).init(false),
            .owner = std.atomic.Value(u64).init(0),
            .wait_queue = WaitQueue.init(allocator),
            .mutex = .{},
        };
    }
    
    pub fn deinit(self: *Mutex) void {
        self.wait_queue.deinit();
    }
    
    /// Acquire the lock, blocking the coroutine if necessary
    /// Requirements: 8.1, 8.2
    pub fn lock(self: *Mutex, coroutine_id: u64) void {
        // Fast path: try to acquire lock immediately
        if (self.locked.cmpxchgWeak(false, true, .acquire, .monotonic) == null) {
            self.owner.store(coroutine_id, .release);
            return;
        }
        
        // Slow path: add to wait queue and block
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Double-check after acquiring mutex
        if (self.locked.cmpxchgWeak(false, true, .acquire, .monotonic) == null) {
            self.owner.store(coroutine_id, .release);
            return;
        }
        
        // Add to wait queue
        self.wait_queue.add(coroutine_id) catch return; // If allocation fails, spin
        
        // Release mutex and yield coroutine
        self.mutex.unlock();
        
        // In a real implementation, this would yield to the scheduler
        // For now, we'll use a simple spin-wait with backoff
        var backoff: u32 = 1;
        while (self.locked.load(.acquire)) {
            std.Thread.sleep(backoff * 1000); // Microseconds
            backoff = @min(backoff * 2, 1000); // Exponential backoff up to 1ms
            
            // Try to acquire again
            if (self.locked.cmpxchgWeak(false, true, .acquire, .monotonic) == null) {
                self.owner.store(coroutine_id, .release);
                
                // Remove from wait queue
                self.mutex.lock();
                _ = self.wait_queue.remove(coroutine_id);
                self.mutex.unlock();
                return;
            }
        }
    }
    
    /// Release the lock and wake waiting coroutines
    /// Requirements: 8.2
    pub fn unlock(self: *Mutex, coroutine_id: u64) void {
        // Verify ownership
        if (self.owner.load(.acquire) != coroutine_id) {
            return; // Not the owner, ignore
        }
        
        self.owner.store(0, .release);
        self.locked.store(false, .release);
        
        // Wake one waiting coroutine
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.wait_queue.wakeOne()) |woken_id| {
            // In a real implementation, this would signal the scheduler
            // to wake the coroutine with woken_id
            _ = woken_id;
        }
    }
    
    /// Try to acquire the lock without blocking
    /// Requirements: 8.4
    pub fn tryLock(self: *Mutex, coroutine_id: u64) bool {
        if (self.locked.cmpxchgWeak(false, true, .acquire, .monotonic) == null) {
            self.owner.store(coroutine_id, .release);
            return true;
        }
        return false;
    }
    
    /// Check if the mutex is currently locked
    pub fn isLocked(self: *Mutex) bool {
        return self.locked.load(.acquire);
    }
    
    /// Get the current owner coroutine ID (0 if unlocked)
    pub fn getOwner(self: *Mutex) u64 {
        return self.owner.load(.acquire);
    }
    
    /// Get the number of waiting coroutines
    pub fn getWaitingCount(self: *Mutex) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.wait_queue.len();
    }
};

/// Readers-Writer Mutex with reader counting and writer priority
/// Requirements: 8.5, 8.6, 8.7
pub const RWMutex = struct {
    readers: std.atomic.Value(u32),
    writer: std.atomic.Value(u64), // 0 if no writer, coroutine_id if writer active
    writer_waiting: std.atomic.Value(bool),
    read_wait_queue: WaitQueue,
    write_wait_queue: WaitQueue,
    mutex: std.Thread.Mutex, // Protects wait queue operations
    
    pub fn init(allocator: std.mem.Allocator) RWMutex {
        return RWMutex{
            .readers = std.atomic.Value(u32).init(0),
            .writer = std.atomic.Value(u64).init(0),
            .writer_waiting = std.atomic.Value(bool).init(false),
            .read_wait_queue = WaitQueue.init(allocator),
            .write_wait_queue = WaitQueue.init(allocator),
            .mutex = .{},
        };
    }
    
    pub fn deinit(self: *RWMutex) void {
        self.read_wait_queue.deinit();
        self.write_wait_queue.deinit();
    }
    
    /// Acquire a read lock
    /// Requirements: 8.5, 8.6
    pub fn readLock(self: *RWMutex, coroutine_id: u64) void {
        while (true) {
            // Check if writer is active or waiting (writer priority)
            if (self.writer.load(.acquire) != 0 or self.writer_waiting.load(.acquire)) {
                // Add to read wait queue
                self.mutex.lock();
                self.read_wait_queue.add(coroutine_id) catch {};
                self.mutex.unlock();
                
                // Wait for writer to finish
                var backoff: u32 = 1;
                while (self.writer.load(.acquire) != 0 or self.writer_waiting.load(.acquire)) {
                    std.Thread.sleep(backoff * 1000);
                    backoff = @min(backoff * 2, 1000);
                }
                
                // Remove from wait queue
                self.mutex.lock();
                _ = self.read_wait_queue.remove(coroutine_id);
                self.mutex.unlock();
                continue;
            }
            
            // Try to increment reader count
            const current_readers = self.readers.load(.acquire);
            if (self.readers.cmpxchgWeak(current_readers, current_readers + 1, .acquire, .monotonic) == null) {
                return; // Successfully acquired read lock
            }
        }
    }
    
    /// Release a read lock
    /// Requirements: 8.6
    pub fn readUnlock(self: *RWMutex, coroutine_id: u64) void {
        _ = coroutine_id; // Reader identity not tracked
        
        const prev_readers = self.readers.fetchSub(1, .release);
        
        // If this was the last reader, wake waiting writers
        if (prev_readers == 1) {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.write_wait_queue.wakeOne()) |woken_id| {
                // In a real implementation, signal scheduler to wake writer
                _ = woken_id;
            }
        }
    }
    
    /// Acquire a write lock (exclusive)
    /// Requirements: 8.5, 8.7
    pub fn writeLock(self: *RWMutex, coroutine_id: u64) void {
        // Signal that a writer is waiting (for writer priority)
        self.writer_waiting.store(true, .release);
        
        while (true) {
            // Wait for all readers to finish
            if (self.readers.load(.acquire) > 0) {
                // Add to write wait queue
                self.mutex.lock();
                self.write_wait_queue.add(coroutine_id) catch {};
                self.mutex.unlock();
                
                // Wait for readers to finish
                var backoff: u32 = 1;
                while (self.readers.load(.acquire) > 0) {
                    std.Thread.sleep(backoff * 1000);
                    backoff = @min(backoff * 2, 1000);
                }
                
                // Remove from wait queue
                self.mutex.lock();
                _ = self.write_wait_queue.remove(coroutine_id);
                self.mutex.unlock();
                continue;
            }
            
            // Try to acquire write lock
            if (self.writer.cmpxchgWeak(0, coroutine_id, .acquire, .monotonic) == null) {
                self.writer_waiting.store(false, .release);
                return; // Successfully acquired write lock
            }
        }
    }
    
    /// Release a write lock
    /// Requirements: 8.7
    pub fn writeUnlock(self: *RWMutex, coroutine_id: u64) void {
        // Verify ownership
        if (self.writer.load(.acquire) != coroutine_id) {
            return; // Not the owner, ignore
        }
        
        self.writer.store(0, .release);
        
        // Wake all waiting readers first (readers can run concurrently)
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.read_wait_queue.wakeAll();
        
        // If no readers were waiting, wake one writer
        if (self.read_wait_queue.isEmpty()) {
            if (self.write_wait_queue.wakeOne()) |woken_id| {
                // In a real implementation, signal scheduler to wake writer
                _ = woken_id;
            }
        }
    }
    
    /// Try to acquire a read lock without blocking
    pub fn tryReadLock(self: *RWMutex, coroutine_id: u64) bool {
        _ = coroutine_id;
        
        // Don't allow read lock if writer is waiting (writer priority)
        if (self.writer.load(.acquire) != 0 or self.writer_waiting.load(.acquire)) {
            return false;
        }
        
        const current_readers = self.readers.load(.acquire);
        return self.readers.cmpxchgWeak(current_readers, current_readers + 1, .acquire, .monotonic) == null;
    }
    
    /// Try to acquire a write lock without blocking
    pub fn tryWriteLock(self: *RWMutex, coroutine_id: u64) bool {
        // Can only acquire write lock if no readers and no other writer
        if (self.readers.load(.acquire) > 0) {
            return false;
        }
        
        return self.writer.cmpxchgWeak(0, coroutine_id, .acquire, .monotonic) == null;
    }
    
    /// Get the number of active readers
    pub fn getReaderCount(self: *RWMutex) u32 {
        return self.readers.load(.acquire);
    }
    
    /// Get the current writer coroutine ID (0 if no writer)
    pub fn getWriter(self: *RWMutex) u64 {
        return self.writer.load(.acquire);
    }
    
    /// Check if a writer is waiting
    pub fn isWriterWaiting(self: *RWMutex) bool {
        return self.writer_waiting.load(.acquire);
    }
    
    /// Get the number of waiting readers
    pub fn getWaitingReaderCount(self: *RWMutex) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.read_wait_queue.len();
    }
    
    /// Get the number of waiting writers
    pub fn getWaitingWriterCount(self: *RWMutex) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.write_wait_queue.len();
    }
};

/// WaitGroup for synchronizing multiple coroutines
/// Requirements: 8.8, 8.9, 8.10, 8.11
pub const WaitGroup = struct {
    counter: std.atomic.Value(i32),
    wait_queue: WaitQueue,
    mutex: std.Thread.Mutex, // Protects wait_queue operations
    
    pub fn init(allocator: std.mem.Allocator) WaitGroup {
        return WaitGroup{
            .counter = std.atomic.Value(i32).init(0),
            .wait_queue = WaitQueue.init(allocator),
            .mutex = .{},
        };
    }
    
    pub fn deinit(self: *WaitGroup) void {
        self.wait_queue.deinit();
    }
    
    /// Add delta to the WaitGroup counter
    /// Requirements: 8.9
    pub fn add(self: *WaitGroup, delta: i32) !void {
        const prev = self.counter.fetchAdd(delta, .seq_cst);
        const new_value = prev + delta;
        
        // If counter reaches zero, wake all waiting coroutines
        if (new_value == 0 and prev > 0) {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.wait_queue.wakeAll();
        }
        
        // Return error if counter goes negative
        if (new_value < 0) {
            // Restore the counter to prevent inconsistent state
            _ = self.counter.fetchSub(delta, .seq_cst);
            return error.WaitGroupCounterNegative;
        }
    }
    
    /// Decrement the WaitGroup counter by 1
    /// Requirements: 8.10
    pub fn done(self: *WaitGroup) !void {
        try self.add(-1);
    }
    
    /// Block until the WaitGroup counter is zero
    /// Requirements: 8.11
    pub fn wait(self: *WaitGroup, coroutine_id: u64) void {
        // Fast path: if counter is already zero, return immediately
        if (self.counter.load(.acquire) == 0) {
            return;
        }
        
        // Add to wait queue
        self.mutex.lock();
        
        // Double-check after acquiring mutex
        if (self.counter.load(.acquire) == 0) {
            self.mutex.unlock();
            return;
        }
        
        self.wait_queue.add(coroutine_id) catch {
            self.mutex.unlock();
            return; // If allocation fails, fall back to spinning
        };
        self.mutex.unlock();
        
        // Wait for counter to reach zero
        var backoff: u32 = 1;
        while (self.counter.load(.acquire) > 0) {
            std.Thread.sleep(backoff * 1000);
            backoff = @min(backoff * 2, 1000);
        }
        
        // Remove from wait queue (cleanup)
        self.mutex.lock();
        _ = self.wait_queue.remove(coroutine_id);
        self.mutex.unlock();
    }
    
    /// Get the current counter value
    pub fn getCount(self: *WaitGroup) i32 {
        return self.counter.load(.acquire);
    }
    
    /// Get the number of coroutines waiting
    pub fn getWaitingCount(self: *WaitGroup) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.wait_queue.len();
    }
    
    /// Check if the WaitGroup is done (counter is zero)
    pub fn isDone(self: *WaitGroup) bool {
        return self.counter.load(.acquire) == 0;
    }
};

// Tests
test "Mutex basic operations" {
    const allocator = std.testing.allocator;
    var mutex = Mutex.init(allocator);
    defer mutex.deinit();
    
    // Initially unlocked
    try std.testing.expect(!mutex.isLocked());
    try std.testing.expectEqual(@as(u64, 0), mutex.getOwner());
    
    // Lock with coroutine 1
    mutex.lock(1);
    try std.testing.expect(mutex.isLocked());
    try std.testing.expectEqual(@as(u64, 1), mutex.getOwner());
    
    // Try lock should fail
    try std.testing.expect(!mutex.tryLock(2));
    
    // Unlock
    mutex.unlock(1);
    try std.testing.expect(!mutex.isLocked());
    try std.testing.expectEqual(@as(u64, 0), mutex.getOwner());
    
    // Try lock should succeed now
    try std.testing.expect(mutex.tryLock(2));
    try std.testing.expectEqual(@as(u64, 2), mutex.getOwner());
    
    mutex.unlock(2);
}

test "RWMutex basic operations" {
    const allocator = std.testing.allocator;
    var rwmutex = RWMutex.init(allocator);
    defer rwmutex.deinit();
    
    // Initially no readers or writers
    try std.testing.expectEqual(@as(u32, 0), rwmutex.getReaderCount());
    try std.testing.expectEqual(@as(u64, 0), rwmutex.getWriter());
    
    // Acquire read locks
    rwmutex.readLock(1);
    rwmutex.readLock(2);
    try std.testing.expectEqual(@as(u32, 2), rwmutex.getReaderCount());
    
    // Try write lock should fail
    try std.testing.expect(!rwmutex.tryWriteLock(3));
    
    // Release read locks
    rwmutex.readUnlock(1);
    try std.testing.expectEqual(@as(u32, 1), rwmutex.getReaderCount());
    
    rwmutex.readUnlock(2);
    try std.testing.expectEqual(@as(u32, 0), rwmutex.getReaderCount());
    
    // Now write lock should succeed
    try std.testing.expect(rwmutex.tryWriteLock(3));
    try std.testing.expectEqual(@as(u64, 3), rwmutex.getWriter());
    
    // Try read lock should fail
    try std.testing.expect(!rwmutex.tryReadLock(4));
    
    // Release write lock
    rwmutex.writeUnlock(3);
    try std.testing.expectEqual(@as(u64, 0), rwmutex.getWriter());
    
    // Now read lock should succeed
    try std.testing.expect(rwmutex.tryReadLock(4));
    try std.testing.expectEqual(@as(u32, 1), rwmutex.getReaderCount());
    
    rwmutex.readUnlock(4);
}

test "WaitGroup basic operations" {
    const allocator = std.testing.allocator;
    var wg = WaitGroup.init(allocator);
    defer wg.deinit();
    
    // Initially done
    try std.testing.expect(wg.isDone());
    try std.testing.expectEqual(@as(i32, 0), wg.getCount());
    
    // Add some work
    try wg.add(3);
    try std.testing.expect(!wg.isDone());
    try std.testing.expectEqual(@as(i32, 3), wg.getCount());
    
    // Mark work as done
    try wg.done();
    try std.testing.expectEqual(@as(i32, 2), wg.getCount());
    
    try wg.done();
    try std.testing.expectEqual(@as(i32, 1), wg.getCount());
    
    try wg.done();
    try std.testing.expect(wg.isDone());
    try std.testing.expectEqual(@as(i32, 0), wg.getCount());
}

test "WaitQueue operations" {
    const allocator = std.testing.allocator;
    var queue = WaitQueue.init(allocator);
    defer queue.deinit();
    
    // Initially empty
    try std.testing.expect(queue.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), queue.len());
    
    // Add waiters
    try queue.add(1);
    try queue.add(2);
    try queue.add(3);
    
    try std.testing.expect(!queue.isEmpty());
    try std.testing.expectEqual(@as(usize, 3), queue.len());
    
    // Wake one
    const woken = queue.wakeOne();
    try std.testing.expect(woken != null);
    try std.testing.expectEqual(@as(u64, 1), woken.?);
    try std.testing.expectEqual(@as(usize, 2), queue.len());
    
    // Remove specific waiter
    try std.testing.expect(queue.remove(2));
    try std.testing.expectEqual(@as(usize, 1), queue.len());
    
    // Wake all remaining
    queue.wakeAll();
    try std.testing.expect(queue.isEmpty());
}