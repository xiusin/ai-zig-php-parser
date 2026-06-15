//! 并发垃圾回收器
//!
//! 实现并发标记-清除GC，减少GC停顿时间
//! 采用SATB（Snapshot-at-the-Beginning）写屏障
//!
//! ## 架构
//!
//! Concurrent GC Architecture:
//! - Mutator Thread: Application Code
//! - GC Thread: Marking, Scanning, Sweeping
//! - Write Barrier: SATB enqueue
//! - Safepoint: pause for sync
//! - Marking Queue: Concurrent marking
//! - Sweeping: Concurrent collection

const std = @import("std");
const gc = @import("gc.zig");
const Value = @import("types.zig").Value;
const PHPString = @import("types.zig").PHPString;
const PHPArray = @import("types.zig").PHPArray;
const PHPObject = @import("types.zig").PHPObject;
const StructInstance = @import("types.zig").StructInstance;
const Closure = @import("types.zig").Closure;
const ArrowFunction = @import("types.zig").ArrowFunction;

// ============================================================================
// 常量配置
// ============================================================================

/// 并发标记队列大小
const MARKING_QUEUE_SIZE: usize = 4096;

/// GC线程优先级
const GC_THREAD_PRIORITY: std.Thread.CpuSet = undefined;

/// 标记步进大小（每次标记的对象数）
const MARK_STEP_SIZE: usize = 100;

/// 扫描步进大小（每次扫描的字节数）
const SCAN_STEP_SIZE: usize = 4096;

// ============================================================================
// SATB写屏障
// ============================================================================

/// SATB (Snapshot-at-the-Beginning) 写屏障
/// 在并发标记阶段记录所有引用更新
pub const SATBBarrier = struct {
    /// SATB队列
    queue: SATBQueue,
    /// 是否启用
    enabled: std.atomic.Atomic(bool),
    /// 分配器
    allocator: std.mem.Allocator,

    const SATBQueue = struct {
        /// 环形缓冲区
        buffer: [MARKING_QUEUE_SIZE]SATBEntry,
        /// 头指针（生产者）
        head: std.atomic.Atomic(usize),
        /// 尾指针（消费者）
        tail: std.atomic.Atomic(usize),
        /// 是否已满
        full: std.atomic.Atomic(bool),

        const SATBEntry = struct {
            /// 源对象
            source: *anyopaque,
            /// 字段偏移
            field_offset: usize,
            /// 旧值
            old_value: *anyopaque,
        };
    };

    pub fn init(allocator: std.mem.Allocator) SATBBarrier {
        return .{
            .queue = .{
                .buffer = undefined,
                .head = std.atomic.Atomic(usize).init(0),
                .tail = std.atomic.Atomic(usize).init(0),
                .full = std.atomic.Atomic(bool).init(false),
            },
            .enabled = std.atomic.Atomic(bool).init(false),
            .allocator = allocator,
        };
    }

    /// 启用写屏障
    pub fn enable(self: *SATBBarrier) void {
        self.enabled.store(true, .release);
    }

    /// 禁用写屏障
    pub fn disable(self: *SATBBarrier) void {
        self.enabled.store(false, .release);
    }

    /// 记录引用更新（写屏障）
    pub fn record(self: *SATBBarrier, source: *anyopaque, field_offset: usize, old_value: *anyopaque) void {
        if (!self.enabled.load(.acquire)) return;

        const head = self.queue.head.load(.acquire);
        const next_head = (head + 1) % MARKING_QUEUE_SIZE;

        // 检查队列是否已满
        if (self.queue.full.load(.acquire)) {
            // 队列满，强制触发同步
            std.debug.warn("SATB queue full, forcing sync\n", .{});
            return;
        }

        // 记录条目
        self.queue.buffer[head] = .{
            .source = source,
            .field_offset = field_offset,
            .old_value = old_value,
        };

        // 更新头指针
        self.queue.head.store(next_head, .release);

        // 检查是否已满
        const tail = self.queue.tail.load(.acquire);
        if (next_head == tail) {
            self.queue.full.store(true, .release);
        }
    }

    /// 获取下一个条目（GC线程消费）
    pub fn dequeue(self: *SATBBarrier) ?SATBQueue.SATBEntry {
        const tail = self.queue.tail.load(.acquire);
        const head = self.queue.head.load(.acquire);

        if (tail == head and !self.queue.full.load(.acquire)) {
            return null; // 队列空
        }

        const entry = self.queue.buffer[tail];
        const next_tail = (tail + 1) % MARKING_QUEUE_SIZE;

        self.queue.tail.store(next_tail, .release);
        self.queue.full.store(false, .release);

        return entry;
    }

    /// 清空队列
    pub fn clear(self: *SATBBarrier) void {
        self.queue.head.store(0, .release);
        self.queue.tail.store(0, .release);
        self.queue.full.store(false, .release);
    }
};

// ============================================================================
// 并发标记队列
// ============================================================================

pub const ConcurrentMarkingQueue = struct {
    /// 待标记对象队列
    objects: std.ArrayListUnmanaged(*anyopaque),
    /// 互斥锁
    mutex: std.Thread.Mutex,
    /// 条件变量
    cond: std.Thread.Condition,
    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConcurrentMarkingQueue {
        return .{
            .objects = std.ArrayListUnmanaged(*anyopaque){ .items = &.{}, .capacity = 0 },
            .mutex = std.Thread.Mutex{},
            .cond = std.Thread.Condition{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConcurrentMarkingQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.objects.deinit(self.allocator);
    }

    /// 添加对象到队列（线程安全）
    pub fn enqueue(self: *ConcurrentMarkingQueue, obj: *anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.objects.append(self.allocator, obj);
        self.cond.signal(); // 通知GC线程
    }

    /// 从队列获取对象（线程安全）
    pub fn dequeue(self: *ConcurrentMarkingQueue) ?*anyopaque {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.objects.items.len == 0) {
            return null;
        }

        return self.objects.orderedRemove(0);
    }

    /// 批量获取对象
    pub fn dequeueBatch(self: *ConcurrentMarkingQueue, max_count: usize) std.ArrayListUnmanaged(*anyopaque) {
        self.mutex.lock();
        defer self.mutex.unlock();

        var batch = std.ArrayListUnmanaged(*anyopaque){ .items = &.{}, .capacity = 0 };
        const count = @min(max_count, self.objects.items.len);

        for (0..count) |_| {
            batch.append(self.allocator, self.objects.orderedRemove(0)) catch break;
        }

        return batch;
    }

    /// 等待队列非空
    pub fn waitForWork(self: *ConcurrentMarkingQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.objects.items.len == 0) {
            self.cond.wait(&self.mutex);
        }
    }

    /// 获取队列大小
    pub fn size(self: *ConcurrentMarkingQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.objects.items.len;
    }
};

// ============================================================================
// 安全点机制
// ============================================================================

pub const Safepoint = struct {
    /// 是否需要暂停
    should_stop: std.atomic.Atomic(bool),
    /// 已暂停的线程数
    stopped_count: std.atomic.Atomic(u32),
    /// 总线程数
    total_threads: u32,
    /// 条件变量
    cond: std.Thread.Condition,
    /// 互斥锁
    mutex: std.Thread.Mutex,

    pub fn init(total_threads: u32) Safepoint {
        return .{
            .should_stop = std.atomic.Atomic(bool).init(false),
            .stopped_count = std.atomic.Atomic(u32).init(0),
            .total_threads = total_threads,
            .cond = std.Thread.Condition{},
            .mutex = std.Thread.Mutex{},
        };
    }

    /// 触发安全点
    pub fn arm(self: *Safepoint) void {
        self.should_stop.store(true, .release);
    }

    /// 解除安全点
    pub fn disarm(self: *Safepoint) void {
        self.should_stop.store(false, .release);
    }

    /// 检查是否需要暂停（由Mutator线程调用）
    pub fn check(self: *Safepoint) void {
        if (!self.should_stop.load(.acquire)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.stopped_count.fetchAdd(1, .acq_rel);

        // 通知GC线程
        self.cond.signal();

        // 等待继续信号
        while (self.should_stop.load(.acquire)) {
            self.cond.wait(&self.mutex);
        }

        // 恢复执行
        _ = self.stopped_count.fetchSub(1, .acq_rel);
    }

    /// 等待所有线程到达安全点（由GC线程调用）
    pub fn sync(self: *Safepoint) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.stopped_count.load(.acquire) < self.total_threads) {
            self.cond.wait(&self.mutex);
        }
    }

    /// 唤醒所有线程
    pub fn resumeAll(self: *Safepoint) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.disarm();
        self.cond.broadcast();
    }
};

// ============================================================================
// 并发GC
// ============================================================================

pub const ConcurrentGC = struct {
    /// GC线程
    gc_thread: ?std.Thread,
    /// 运行标志
    running: std.atomic.Atomic(bool),
    /// 标记队列
    marking_queue: ConcurrentMarkingQueue,
    /// SATB写屏障
    satb_barrier: SATBBarrier,
    /// 安全点
    safepoint: Safepoint,
    /// GC阶段
    phase: std.atomic.Atomic(Phase),
    /// 根集合
    roots: std.ArrayListUnmanaged(Value),
    /// 分配器
    allocator: std.mem.Allocator,
    /// 统计信息
    stats: GCStats,

    pub const Phase = enum(u8) {
        idle = 0,
        marking = 1,
        remarking = 2,
        sweeping = 3,
        complete = 4,
    };

    pub const GCStats = struct {
        /// 标记的对象数
        marked_objects: u64 = 0,
        /// 扫描的对象数
        scanned_objects: u64 = 0,
        /// 回收的对象数
        collected_objects: u64 = 0,
        /// 标记时间（纳秒）
        marking_time_ns: u64 = 0,
        /// 扫描时间（纳秒）
        scanning_time_ns: u64 = 0,
        /// 清扫时间（纳秒）
        sweeping_time_ns: u64 = 0,
        /// 总停顿时间（纳秒）
        total_pause_ns: u64 = 0,
        /// GC次数
        gc_count: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, thread_count: u32) ConcurrentGC {
        return .{
            .gc_thread = null,
            .running = std.atomic.Atomic(bool).init(false),
            .marking_queue = ConcurrentMarkingQueue.init(allocator),
            .satb_barrier = SATBBarrier.init(allocator),
            .safepoint = Safepoint.init(thread_count),
            .phase = std.atomic.Atomic(Phase).init(.idle),
            .roots = std.ArrayListUnmanaged(Value){ .items = &.{}, .capacity = 0 },
            .allocator = allocator,
            .stats = .{},
        };
    }

    pub fn deinit(self: *ConcurrentGC) void {
        self.stop();
        self.marking_queue.deinit();
        self.roots.deinit(self.allocator);
    }

    /// 启动GC线程
    pub fn start(self: *ConcurrentGC) !void {
        if (self.gc_thread != null) return;

        self.running.store(true, .release);
        self.gc_thread = try std.Thread.spawn(.{}, gcThreadMain, .{self});
    }

    /// 停止GC线程
    pub fn stop(self: *ConcurrentGC) void {
        if (self.gc_thread == null) return;

        self.running.store(false, .release);

        // 唤醒GC线程
        self.marking_queue.mutex.lock();
        self.marking_queue.cond.signal();
        self.marking_queue.mutex.unlock();

        // 等待线程结束
        if (self.gc_thread) |thread| {
            thread.join();
            self.gc_thread = null;
        }
    }

    /// 触发GC
    pub fn triggerGC(self: *ConcurrentGC) void {
        // 唤醒GC线程
        self.marking_queue.mutex.lock();
        self.marking_queue.cond.signal();
        self.marking_queue.mutex.unlock();
    }

    /// 添加根对象
    pub fn addRoot(self: *ConcurrentGC, value: Value) !void {
        try self.roots.append(self.allocator, value);
    }

    /// 清除根对象
    pub fn clearRoots(self: *ConcurrentGC) void {
        self.roots.clearRetainingCapacity();
    }

    /// GC线程主函数
    fn gcThreadMain(self: *ConcurrentGC) void {
        while (self.running.load(.acquire)) {
            // 等待工作
            if (self.marking_queue.size() == 0) {
                self.marking_queue.mutex.lock();
                self.marking_queue.cond.wait(&self.marking_queue.mutex);
                self.marking_queue.mutex.unlock();
            }

            if (!self.running.load(.acquire)) break;

            // 执行GC周期
            self.gcCycle() catch |err| {
                std.debug.warn("GC cycle failed: {}\n", .{err});
            };
        }
    }

    /// 执行完整的GC周期
    fn gcCycle(self: *ConcurrentGC) !void {
        const start_time = std.time.nanoTimestamp();

        // 阶段1: 并发标记
        try self.concurrentMark();

        // 阶段2: 同步重标记
        try self.remark();

        // 阶段3: 并发清扫
        try self.concurrentSweep();

        const end_time = std.time.nanoTimestamp();
        self.stats.total_pause_ns += @intCast(end_time - start_time);
        self.stats.gc_count += 1;
    }

    /// 并发标记阶段
    fn concurrentMark(self: *ConcurrentGC) !void {
        self.phase.store(.marking, .release);

        const start_time = std.time.nanoTimestamp();

        // 启用SATB写屏障
        self.satb_barrier.enable();

        // 标记根对象
        try self.markRoots();

        // 并发标记
        while (self.marking_queue.size() > 0) {
            // 获取一批对象
            const batch = self.marking_queue.dequeueBatch(MARK_STEP_SIZE);

            // 标记这些对象
            for (batch.items) |obj| {
                self.markObject(obj);
                self.stats.marked_objects += 1;
            }

            batch.deinit(self.allocator);

            // 让出CPU
            std.time.sleep(1);
        }

        // 处理SATB队列
        while (true) {
            const entry = self.satb_barrier.dequeue() orelse break;
            self.markObject(entry.old_value);
        }

        const end_time = std.time.nanoTimestamp();
        self.stats.marking_time_ns += @intCast(end_time - start_time);

        // 禁用SATB写屏障
        self.satb_barrier.disable();
    }

    /// 重标记阶段（需要暂停Mutator）
    fn remark(self: *ConcurrentGC) !void {
        self.phase.store(.remarking, .release);

        const start_time = std.time.nanoTimestamp();

        // 触发安全点
        self.safepoint.arm();
        self.safepoint.sync();

        // 处理剩余的SATB条目
        while (true) {
            const entry = self.satb_barrier.dequeue() orelse break;
            self.markObject(entry.old_value);
        }

        // 重新标记根对象
        try self.markRoots();

        // 处理标记队列
        while (self.marking_queue.size() > 0) {
            const obj = self.marking_queue.dequeue() orelse break;
            self.markObject(obj);
        }

        // 唤醒所有线程
        self.safepoint.resumeAll();

        const end_time = std.time.nanoTimestamp();
        self.stats.scanning_time_ns += @intCast(end_time - start_time);
    }

    /// 并发清扫阶段
    fn concurrentSweep(self: *ConcurrentGC) !void {
        self.phase.store(.sweeping, .release);

        const start_time = std.time.nanoTimestamp();

        // 扫描所有对象，回收白色对象
        // 这里需要遍历所有已分配的对象
        // 实际实现需要与内存管理器集成

        const end_time = std.time.nanoTimestamp();
        self.stats.sweeping_time_ns += @intCast(end_time - start_time);

        self.phase.store(.complete, .release);
    }

    /// 标记根对象
    fn markRoots(self: *ConcurrentGC) !void {
        for (self.roots.items) |value| {
            try self.markValue(value);
        }
    }

    /// 标记值
    fn markValue(self: *ConcurrentGC, value: Value) !void {
        switch (value.getTag()) {
            .string => try self.marking_queue.enqueue(value.getAsString()),
            .array => try self.marking_queue.enqueue(value.getAsArray()),
            .object => try self.marking_queue.enqueue(value.getAsObject()),
            .struct_instance => try self.marking_queue.enqueue(value.getAsStruct()),
            .closure => try self.marking_queue.enqueue(value.getAsClosure()),
            .arrow_function => try self.marking_queue.enqueue(value.getAsArrowFunc()),
            else => {},
        }
    }

    /// 标记对象
    fn markObject(self: *ConcurrentGC, obj: *anyopaque) void {
        // 这里需要根据对象类型进行标记
        // 实际实现需要与Box系统集成
        _ = obj;
    }

    /// 获取统计信息
    pub fn getStats(self: *ConcurrentGC) GCStats {
        return self.stats;
    }

    /// 获取当前阶段
    pub fn getPhase(self: *ConcurrentGC) Phase {
        return self.phase.load(.acquire);
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SATB barrier basic" {
    var barrier = SATBBarrier.init(std.testing.allocator);
    defer _ = barrier; // 不需要deinit

    barrier.enable();

    // 记录一些引用更新
    var dummy_obj: u8 = 0;
    barrier.record(&dummy_obj, 0, &dummy_obj);

    // 验证条目被记录
    const entry = barrier.dequeue();
    try std.testing.expect(entry != null);
}

test "concurrent marking queue" {
    var queue = ConcurrentMarkingQueue.init(std.testing.allocator);
    defer queue.deinit();

    var dummy_obj: u8 = 0;

    // 添加对象
    try queue.enqueue(&dummy_obj);
    try queue.enqueue(&dummy_obj);

    // 获取对象
    const obj1 = queue.dequeue();
    const obj2 = queue.dequeue();

    try std.testing.expect(obj1 != null);
    try std.testing.expect(obj2 != null);
    try std.testing.expect(queue.dequeue() == null);
}

test "safepoint basic" {
    var safepoint = Safepoint.init(2);
    defer _ = safepoint;

    safepoint.arm();

    // 模拟线程到达安全点
    const thread1 = try std.Thread.spawn(.{}, struct {
        fn run(sp: *Safepoint) void {
            sp.check();
        }
    }.run, .{&safepoint});

    const thread2 = try std.Thread.spawn(.{}, struct {
        fn run(sp: *Safepoint) void {
            sp.check();
        }
    }.run, .{&safepoint});

    // 等待所有线程到达安全点
    safepoint.sync();

    // 唤醒所有线程
    safepoint.resumeAll();

    thread1.join();
    thread2.join();
}

test "concurrent GC init" {
    var concurrent_gc = ConcurrentGC.init(std.testing.allocator, 2);
    defer concurrent_gc.deinit();

    // 验证初始状态
    try std.testing.expect(concurrent_gc.getPhase() == .idle);

    // 添加根对象
    try concurrent_gc.addRoot(Value.initNull());

    // 获取统计信息
    const stats = concurrent_gc.getStats();
    try std.testing.expect(stats.gc_count == 0);
}
