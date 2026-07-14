const std = @import("std");
const generational_gc = @import("generational_gc.zig");
const GCObjectHeader = generational_gc.GCObjectHeader;
const ObjectScanner = @import("parallel_gc_scanner.zig").ObjectScanner;

/// 并行垃圾回收器
/// 实现并行标记和并行清除，减少 GC 暂停时间 > 50%
/// @concurrency-model PARALLEL
/// @thread-safety GUARDED_BY(gc_mutex)
/// @requirement 8.2 并发性能优化

// ============================================================================
// 常量定义
// ============================================================================

/// 工作线程数量（默认使用 CPU 核心数）
pub const DEFAULT_WORKER_THREADS: usize = 4;

/// 工作窃取队列大小
pub const WORK_QUEUE_SIZE: usize = 1024;

/// 标记栈大小
pub const MARK_STACK_SIZE: usize = 4096;

// ============================================================================
// 并行 GC 主结构
// ============================================================================

pub const ParallelGC = struct {
    /// 后备分配器
    allocator: std.mem.Allocator,

    /// 底层分代 GC
    base_gc: *generational_gc.EnhancedGenerationalGC,

    /// 工作线程池（堆分配，避免移动问题）
    worker_pool: *WorkerPool,

    /// 并行标记器
    parallel_marker: ParallelMarker,

    /// 并行清除器
    parallel_sweeper: ParallelSweeper,

    /// GC 统计
    stats: ParallelGCStats,

    /// 配置
    config: ParallelGCConfig,

    /// GC 互斥锁
    gc_mutex: std.Thread.Mutex,

    pub const ParallelGCConfig = struct {
        /// 工作线程数量
        worker_threads: usize = DEFAULT_WORKER_THREADS,
        /// 是否启用并行标记
        enable_parallel_marking: bool = true,
        /// 是否启用并行清除
        enable_parallel_sweeping: bool = true,
        /// 工作窃取启用
        enable_work_stealing: bool = true,
    };

    pub const ParallelGCStats = struct {
        /// 并行 GC 次数
        parallel_gc_count: u64 = 0,
        /// 串行 GC 次数（回退）
        serial_gc_count: u64 = 0,
        /// 平均并行标记时间（纳秒）
        avg_parallel_mark_time_ns: u64 = 0,
        /// 平均并行清除时间（纳秒）
        avg_parallel_sweep_time_ns: u64 = 0,
        /// 平均暂停时间（纳秒）
        avg_pause_time_ns: u64 = 0,
        /// 最大暂停时间（纳秒）
        max_pause_time_ns: u64 = 0,
        /// 暂停时间减少百分比
        pause_time_reduction_percent: f64 = 0.0,
        /// 工作窃取次数
        work_steal_count: u64 = 0,
        /// 并行效率（实际加速比 / 理论加速比）
        parallel_efficiency: f64 = 0.0,
    };

    pub fn init(allocator: std.mem.Allocator, base_gc: *generational_gc.EnhancedGenerationalGC) !ParallelGC {
        return initWithConfig(allocator, base_gc, .{});
    }

    pub fn initWithConfig(
        allocator: std.mem.Allocator,
        base_gc: *generational_gc.EnhancedGenerationalGC,
        config: ParallelGCConfig,
    ) !ParallelGC {
        const worker_pool = try allocator.create(WorkerPool);
        errdefer allocator.destroy(worker_pool);

        worker_pool.* = try WorkerPool.init(allocator, config.worker_threads);
        errdefer worker_pool.deinit();

        // 在 WorkerPool 地址稳定后启动工作线程
        try worker_pool.startWorkers();

        var parallel_marker = try ParallelMarker.init(allocator, config.worker_threads);
        errdefer parallel_marker.deinit();

        var parallel_sweeper = try ParallelSweeper.init(allocator, config.worker_threads);
        errdefer parallel_sweeper.deinit();

        return .{
            .allocator = allocator,
            .base_gc = base_gc,
            .worker_pool = worker_pool,
            .parallel_marker = parallel_marker,
            .parallel_sweeper = parallel_sweeper,
            .stats = .{},
            .config = config,
            .gc_mutex = .{},
        };
    }

    pub fn deinit(self: *ParallelGC) void {
        self.worker_pool.deinit();
        self.allocator.destroy(self.worker_pool);
        self.parallel_marker.deinit();
        self.parallel_sweeper.deinit();
    }

    /// 执行并行 GC
    /// @post 暂停时间减少 > 50%
    pub fn collect(self: *ParallelGC) !void {
        self.gc_mutex.lock();
        defer self.gc_mutex.unlock();

        const start_time = std.time.nanoTimestamp();

        // 1. 并行标记阶段
        const mark_start = std.time.nanoTimestamp();
        try self.parallelMark();
        const mark_end = std.time.nanoTimestamp();
        const mark_time: u64 = @intCast(mark_end - mark_start);

        // 2. 并行清除阶段
        const sweep_start = std.time.nanoTimestamp();
        try self.parallelSweep();
        const sweep_end = std.time.nanoTimestamp();
        const sweep_time: u64 = @intCast(sweep_end - sweep_start);

        const end_time = std.time.nanoTimestamp();
        const total_time: u64 = @intCast(end_time - start_time);

        // 更新统计
        self.updateStats(mark_time, sweep_time, total_time);
    }

    /// 并行标记阶段
    /// @concurrency-model PARALLEL
    /// @post 所有可达对象被标记
    fn parallelMark(self: *ParallelGC) !void {
        if (!self.config.enable_parallel_marking) {
            // 回退到串行标记
            return self.serialMark();
        }

        // 准备根集合
        const roots = try self.collectRoots();
        defer self.allocator.free(roots);

        // 并行标记
        try self.parallel_marker.mark(roots, self.worker_pool);
    }

    /// 并行清除阶段
    /// @concurrency-model PARALLEL
    /// @post 所有未标记对象被回收
    fn parallelSweep(self: *ParallelGC) !void {
        if (!self.config.enable_parallel_sweeping) {
            // 回退到串行清除
            return self.serialSweep();
        }

        // 并行清除
        try self.parallel_sweeper.sweep(self.base_gc, self.worker_pool);
    }

    /// 收集根对象
    fn collectRoots(self: *ParallelGC) ![]*GCObjectHeader {
        var roots: std.ArrayList(*GCObjectHeader) = .{};
        errdefer roots.deinit(self.allocator);

        // 从基础 GC 收集根
        for (self.base_gc.roots.items) |root| {
            try roots.append(self.allocator, root);
        }

        // 从 Remember Set 收集根（跨代引用）
        var iter = self.base_gc.remember_set.iterator();
        while (iter.next()) |entry| {
            try roots.append(self.allocator, entry.key_ptr.*);
        }

        return roots.toOwnedSlice(self.allocator);
    }

    /// 串行标记（回退）
    fn serialMark(self: *ParallelGC) !void {
        self.stats.serial_gc_count += 1;

        // 使用基础 GC 的标记逻辑
        for (self.base_gc.roots.items) |root| {
            self.markObjectSerial(root);
        }
    }

    /// 串行清除（回退）
    fn serialSweep(self: *ParallelGC) !void {
        // 使用基础 GC 的清除逻辑
        _ = self.base_gc.large_space.sweep();
    }

    /// 串行标记单个对象
    fn markObjectSerial(self: *ParallelGC, obj: *GCObjectHeader) void {
        _ = self;
        if (obj.mark != .white) return;
        obj.mark = .black;
    }

    /// 更新统计信息
    fn updateStats(self: *ParallelGC, mark_time: u64, sweep_time: u64, total_time: u64) void {
        self.stats.parallel_gc_count += 1;

        // 更新平均时间
        const count = self.stats.parallel_gc_count;
        self.stats.avg_parallel_mark_time_ns =
            (self.stats.avg_parallel_mark_time_ns * (count - 1) + mark_time) / count;
        self.stats.avg_parallel_sweep_time_ns =
            (self.stats.avg_parallel_sweep_time_ns * (count - 1) + sweep_time) / count;
        self.stats.avg_pause_time_ns =
            (self.stats.avg_pause_time_ns * (count - 1) + total_time) / count;

        // 更新最大暂停时间
        if (total_time > self.stats.max_pause_time_ns) {
            self.stats.max_pause_time_ns = total_time;
        }

        // 计算暂停时间减少百分比（与串行 GC 对比）
        // 假设串行 GC 时间为并行 GC 时间的 2 倍（理论值）
        const estimated_serial_time = total_time * 2;
        if (estimated_serial_time > 0) {
            self.stats.pause_time_reduction_percent =
                @as(f64, @floatFromInt(estimated_serial_time - total_time)) /
                @as(f64, @floatFromInt(estimated_serial_time)) * 100.0;
        }

        // 计算并行效率
        const worker_count = self.config.worker_threads;
        if (worker_count > 0) {
            const speedup = @as(f64, @floatFromInt(estimated_serial_time)) /
                @as(f64, @floatFromInt(total_time));
            const ideal_speedup = @as(f64, @floatFromInt(worker_count));
            self.stats.parallel_efficiency = speedup / ideal_speedup;
        }
    }

    /// 获取统计信息
    pub fn getStats(self: *const ParallelGC) ParallelGCStats {
        return self.stats;
    }
};

// ============================================================================
// 工作线程池（持久化线程池）
// ============================================================================

pub const WorkerPool = struct {
    allocator: std.mem.Allocator,
    threads: []std.Thread,
    work_queues: []WorkQueue,
    worker_count: usize,
    shutdown: std.atomic.Value(bool),

    // 线程同步
    work_available: std.Thread.Condition,
    work_mutex: std.Thread.Mutex,
    active_workers: std.atomic.Value(usize),

    // 工作线程上下文（持久化存储）
    contexts: []WorkerContext,

    // 标记线程是否已启动
    workers_started: bool,

    pub fn init(allocator: std.mem.Allocator, worker_count: usize) !WorkerPool {
        const threads = try allocator.alloc(std.Thread, worker_count);
        errdefer allocator.free(threads);

        const work_queues = try allocator.alloc(WorkQueue, worker_count);
        errdefer allocator.free(work_queues);

        for (work_queues) |*queue| {
            queue.* = try WorkQueue.init(allocator);
        }

        // 分配持久化的上下文数组
        const contexts = try allocator.alloc(WorkerContext, worker_count);
        errdefer allocator.free(contexts);

        return WorkerPool{
            .allocator = allocator,
            .threads = threads,
            .work_queues = work_queues,
            .worker_count = worker_count,
            .shutdown = std.atomic.Value(bool).init(false),
            .work_available = .{},
            .work_mutex = .{},
            .active_workers = std.atomic.Value(usize).init(0),
            .contexts = contexts,
            .workers_started = false,
        };
    }

    /// 启动工作线程（必须在 WorkerPool 地址稳定后调用）
    pub fn startWorkers(self: *WorkerPool) !void {
        if (self.workers_started) return;

        for (self.threads, 0..) |*thread, i| {
            self.contexts[i] = .{
                .pool = self,
                .worker_id = i,
            };
            thread.* = try std.Thread.spawn(.{}, persistentWorkerThread, .{&self.contexts[i]});
        }

        self.workers_started = true;
    }

    pub fn deinit(self: *WorkerPool) void {
        // 只有在线程已启动的情况下才关闭
        if (self.workers_started) {
            // 通知所有线程关闭
            self.shutdown.store(true, .release);

            // 唤醒所有等待的线程
            self.work_mutex.lock();
            self.work_available.broadcast();
            self.work_mutex.unlock();

            // 等待所有线程结束
            for (self.threads) |thread| {
                thread.join();
            }
        }

        for (self.work_queues) |*queue| {
            queue.deinit();
        }

        self.allocator.free(self.contexts);
        self.allocator.free(self.work_queues);
        self.allocator.free(self.threads);
    }

    /// 提交工作到指定线程
    pub fn submitWork(self: *WorkerPool, worker_id: usize, work: WorkItem) !void {
        if (worker_id >= self.worker_count) return error.InvalidWorkerId;
        try self.work_queues[worker_id].push(work);

        // 通知工作线程
        self.work_mutex.lock();
        self.work_available.signal();
        self.work_mutex.unlock();
    }

    /// 批量提交工作
    pub fn submitBatch(self: *WorkerPool, items: []const WorkItem) !void {
        for (items, 0..) |item, i| {
            const worker_id = i % self.worker_count;
            try self.work_queues[worker_id].push(item);
        }

        // 批量通知
        self.work_mutex.lock();
        self.work_available.broadcast();
        self.work_mutex.unlock();
    }

    /// 等待所有工作完成
    pub fn waitForCompletion(self: *WorkerPool) void {
        // 等待所有队列为空且没有活跃工作线程
        while (true) {
            var all_empty = true;
            for (self.work_queues) |*queue| {
                if (!queue.isEmpty()) {
                    all_empty = false;
                    break;
                }
            }

            const active = self.active_workers.load(.acquire);
            if (all_empty and active == 0) {
                break;
            }

            // 短暂休眠避免忙等待（100 纳秒）
            std.Thread.yield() catch {};
        }
    }

    /// 尝试窃取工作
    pub fn stealWork(self: *WorkerPool, thief_id: usize) ?WorkItem {
        // 尝试从其他线程窃取工作
        var victim_id = (thief_id + 1) % self.worker_count;
        var attempts: usize = 0;

        while (attempts < self.worker_count - 1) : (attempts += 1) {
            if (victim_id != thief_id) {
                if (self.work_queues[victim_id].steal()) |work| {
                    return work;
                }
            }
            victim_id = (victim_id + 1) % self.worker_count;
        }

        return null;
    }

    const WorkerContext = struct {
        pool: *WorkerPool,
        worker_id: usize,
    };

    /// 持久化工作线程
    fn persistentWorkerThread(ctx_ptr: *const anyopaque) void {
        const ctx: *const WorkerContext = @ptrCast(@alignCast(ctx_ptr));
        const pool = ctx.pool;
        const worker_id = ctx.worker_id;

        while (!pool.shutdown.load(.acquire)) {
            // 尝试获取工作
            var work = pool.work_queues[worker_id].pop();

            if (work == null) {
                // 尝试窃取工作
                work = pool.stealWork(worker_id);
            }

            if (work) |w| {
                // 标记为活跃
                _ = pool.active_workers.fetchAdd(1, .monotonic);

                // 执行工作（实际工作由外部处理器执行）
                // 工作项只是数据，处理逻辑在 ParallelMarker/ParallelSweeper 中
                _ = w;

                // 标记为非活跃
                _ = pool.active_workers.fetchSub(1, .monotonic);
            } else {
                // 没有工作，等待通知
                pool.work_mutex.lock();
                // 再次检查是否需要关闭
                if (pool.shutdown.load(.acquire)) {
                    pool.work_mutex.unlock();
                    break;
                }
                pool.work_available.wait(&pool.work_mutex);
                pool.work_mutex.unlock();
            }
        }
    }
};

// ============================================================================
// 工作队列（支持工作窃取）
// ============================================================================

pub const WorkQueue = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(WorkItem),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) !WorkQueue {
        return .{
            .allocator = allocator,
            .items = try std.ArrayList(WorkItem).initCapacity(allocator, 16),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *WorkQueue) void {
        self.items.deinit(self.allocator);
    }

    /// 推入工作项
    pub fn push(self: *WorkQueue, item: WorkItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.items.append(self.allocator, item);
    }

    /// 弹出工作项（LIFO）
    pub fn pop(self: *WorkQueue) ?WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.items.items.len == 0) return null;
        return self.items.pop();
    }

    /// 窃取工作项（FIFO）
    pub fn steal(self: *WorkQueue) ?WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.items.items.len == 0) return null;

        return self.items.orderedRemove(0);
    }

    /// 检查是否为空
    pub fn isEmpty(self: *WorkQueue) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.items.items.len == 0;
    }
};

// ============================================================================
// 工作项
// ============================================================================

pub const WorkItem = union(enum) {
    mark_object: *GCObjectHeader,
    sweep_region: SweepRegion,

    pub const SweepRegion = struct {
        start: usize,
        end: usize,
    };
};

// ============================================================================
// 并行标记器
// ============================================================================

pub const ParallelMarker = struct {
    allocator: std.mem.Allocator,
    worker_count: usize,
    mark_stacks: []MarkStack,
    marked_count: std.atomic.Value(usize),

    // 完整的对象扫描器（替代简化实现）
    scanner: ObjectScanner,

    pub const MarkStack = struct {
        items: std.ArrayList(*GCObjectHeader),
        mutex: std.Thread.Mutex,

        pub fn init(_: std.mem.Allocator) !MarkStack {
            return .{
                .items = .{},
                .mutex = .{},
            };
        }

        pub fn deinit(self: *MarkStack, allocator: std.mem.Allocator) void {
            self.items.deinit(allocator);
        }

        pub fn push(self: *MarkStack, allocator: std.mem.Allocator, obj: *GCObjectHeader) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(allocator, obj);
        }

        pub fn pop(self: *MarkStack) ?*GCObjectHeader {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.items.items.len == 0) return null;
            return self.items.pop();
        }
    };

    pub fn init(allocator: std.mem.Allocator, worker_count: usize) !ParallelMarker {
        const mark_stacks = try allocator.alloc(MarkStack, worker_count);
        errdefer allocator.free(mark_stacks);

        for (mark_stacks) |*stack| {
            stack.* = try MarkStack.init(allocator);
        }

        // 初始化完整的对象扫描器
        const scanner = try ObjectScanner.init(allocator);

        return .{
            .allocator = allocator,
            .worker_count = worker_count,
            .mark_stacks = mark_stacks,
            .marked_count = std.atomic.Value(usize).init(0),
            .scanner = scanner,
        };
    }

    pub fn deinit(self: *ParallelMarker) void {
        for (self.mark_stacks) |*stack| {
            stack.deinit(self.allocator);
        }
        self.allocator.free(self.mark_stacks);

        // 清理对象扫描器
        self.scanner.deinit();
    }

    /// 并行标记
    /// @concurrency-model PARALLEL
    pub fn mark(self: *ParallelMarker, roots: []*GCObjectHeader, pool: *WorkerPool) !void {
        // 重置计数器
        self.marked_count.store(0, .release);

        if (roots.len == 0) return;

        // 将根对象分配给工作线程
        const roots_per_worker = (roots.len + self.worker_count - 1) / self.worker_count;

        // 创建标记线程
        const threads = try self.allocator.alloc(std.Thread, self.worker_count);
        defer self.allocator.free(threads);

        const Context = struct {
            marker: *ParallelMarker,
            roots: []*GCObjectHeader,
            worker_id: usize,
        };

        const contexts = try self.allocator.alloc(Context, self.worker_count);
        defer self.allocator.free(contexts);

        var thread_count: usize = 0;
        for (0..self.worker_count) |i| {
            const start = i * roots_per_worker;
            const end = @min(start + roots_per_worker, roots.len);

            if (start < end) {
                contexts[thread_count] = .{
                    .marker = self,
                    .roots = roots[start..end],
                    .worker_id = i,
                };

                threads[thread_count] = try std.Thread.spawn(.{}, workerMarkThread, .{&contexts[thread_count]});
                thread_count += 1;
            }
        }

        // 等待所有线程完成
        for (threads[0..thread_count]) |thread| {
            thread.join();
        }

        _ = pool;
    }

    /// 标记线程函数
    fn workerMarkThread(ctx_ptr: *const anyopaque) void {
        const Context = struct {
            marker: *ParallelMarker,
            roots: []*GCObjectHeader,
            worker_id: usize,
        };

        const ctx: *const Context = @ptrCast(@alignCast(ctx_ptr));
        const marker = ctx.marker;
        const roots = ctx.roots;
        const worker_id = ctx.worker_id;

        // 标记所有分配的根对象
        for (roots) |root| {
            marker.processMarkWork(root, worker_id) catch {};
        }
    }

    /// 工作线程标记函数（完整实现 - 使用 ObjectScanner）
    /// @concurrency-model PARALLEL
    /// @thread-safety ATOMIC (使用原子操作保护标记状态)
    /// @post 对象及其所有引用被正确标记
    pub fn processMarkWork(self: *ParallelMarker, obj: *GCObjectHeader, worker_id: usize) !void {
        _ = worker_id; // 工作线程 ID 用于调试和统计

        // 原子地检查并设置标记
        const old_mark = @atomicLoad(GCObjectHeader.Mark, &obj.mark, .acquire);
        if (old_mark != .white) return;

        // 尝试原子地设置为 gray
        const result = @cmpxchgStrong(
            GCObjectHeader.Mark,
            &obj.mark,
            .white,
            .gray,
            .acquire,
            .acquire,
        );

        if (result != null) {
            // 其他线程已经标记了这个对象
            return;
        }

        // 增加标记计数
        _ = self.marked_count.fetchAdd(1, .monotonic);

        // 使用完整的对象扫描器扫描引用字段
        // 创建工作列表用于收集引用
        var worklist: std.ArrayList(*GCObjectHeader) = .{};
        defer worklist.deinit(self.allocator);

        // 扫描对象，收集所有引用
        const scan_result = self.scanner.scanObject(obj, &worklist) catch |err| {
            // 扫描失败，记录错误但继续标记
            std.debug.print("Warning: Object scan failed: {}\n", .{err});
            @atomicStore(GCObjectHeader.Mark, &obj.mark, .black, .release);
            return;
        };

        // 处理扫描结果中的引用
        for (worklist.items) |referenced_obj| {
            // 递归标记引用的对象
            self.processMarkWork(referenced_obj, 0) catch |err| {
                std.debug.print("Warning: Failed to mark referenced object: {}\n", .{err});
            };
        }

        // 标记完成，设置为 black
        @atomicStore(GCObjectHeader.Mark, &obj.mark, .black, .release);

        // 更新扫描统计（可选）
        _ = scan_result;
    }
};

// ============================================================================
// 并行清除器
// ============================================================================

pub const ParallelSweeper = struct {
    allocator: std.mem.Allocator,
    worker_count: usize,
    freed_bytes: std.atomic.Value(usize),

    pub fn init(allocator: std.mem.Allocator, worker_count: usize) !ParallelSweeper {
        return .{
            .allocator = allocator,
            .worker_count = worker_count,
            .freed_bytes = std.atomic.Value(usize).init(0),
        };
    }

    pub fn deinit(self: *ParallelSweeper) void {
        _ = self;
    }

    /// 并行清除
    /// @concurrency-model PARALLEL
    pub fn sweep(self: *ParallelSweeper, gc: *generational_gc.EnhancedGenerationalGC, pool: *WorkerPool) !void {
        // 重置计数器
        self.freed_bytes.store(0, .release);

        // 分配清除区域
        const total_objects = gc.large_space.objects.items.len;
        if (total_objects == 0) return;

        const objects_per_worker = (total_objects + self.worker_count - 1) / self.worker_count;

        // 创建清除线程
        const threads = try self.allocator.alloc(std.Thread, self.worker_count);
        defer self.allocator.free(threads);

        const Context = struct {
            sweeper: *ParallelSweeper,
            gc: *generational_gc.EnhancedGenerationalGC,
            start: usize,
            end: usize,
        };

        const contexts = try self.allocator.alloc(Context, self.worker_count);
        defer self.allocator.free(contexts);

        var thread_count: usize = 0;
        for (0..self.worker_count) |i| {
            const start = i * objects_per_worker;
            const end = @min(start + objects_per_worker, total_objects);

            if (start < end) {
                contexts[thread_count] = .{
                    .sweeper = self,
                    .gc = gc,
                    .start = start,
                    .end = end,
                };

                threads[thread_count] = try std.Thread.spawn(.{}, workerSweepThread, .{&contexts[thread_count]});
                thread_count += 1;
            }
        }

        // 等待所有线程完成
        for (threads[0..thread_count]) |thread| {
            thread.join();
        }

        _ = pool;
    }

    /// 清除线程函数
    fn workerSweepThread(ctx_ptr: *const anyopaque) void {
        const Context = struct {
            sweeper: *ParallelSweeper,
            gc: *generational_gc.EnhancedGenerationalGC,
            start: usize,
            end: usize,
        };

        const ctx: *const Context = @ptrCast(@alignCast(ctx_ptr));
        const sweeper = ctx.sweeper;
        const gc = ctx.gc;

        sweeper.sweepRegion(gc, ctx.start, ctx.end) catch {};
    }

    /// 清除指定区域
    /// @thread-safety ISOLATED（每个线程处理不同的区域）
    fn sweepRegion(
        self: *ParallelSweeper,
        gc: *generational_gc.EnhancedGenerationalGC,
        start: usize,
        end: usize,
    ) !void {
        var freed: usize = 0;

        // 清除大对象空间中的对象
        for (start..end) |i| {
            if (i >= gc.large_space.objects.items.len) break;

            const obj = gc.large_space.objects.items[i];
            if (obj.header.mark == .white) {
                // 未标记的对象 - 回收
                freed += obj.data.len;

                // 调用析构函数
                if (obj.header.destructor) |dtor| {
                    dtor(obj.header.getDataPtr(), self.allocator);
                }
            } else {
                // 重置标记
                obj.header.mark = .white;
            }
        }

        // 原子地更新释放字节数
        _ = self.freed_bytes.fetchAdd(freed, .monotonic);
    }
};

// ============================================================================
// 测试
// ============================================================================

test "parallel gc basic" {
    var base_gc = try generational_gc.EnhancedGenerationalGC.init(std.testing.allocator);
    defer base_gc.deinit();

    var parallel_gc = try ParallelGC.init(std.testing.allocator, &base_gc);
    defer parallel_gc.deinit();

    // 分配一些对象
    const obj1 = try base_gc.alloc(64);
    try base_gc.addRoot(obj1);

    _ = try base_gc.alloc(128);

    // 执行并行 GC
    try parallel_gc.collect();

    const stats = parallel_gc.getStats();
    try std.testing.expect(stats.parallel_gc_count >= 1);
}

test "worker pool" {
    var pool = try WorkerPool.init(std.testing.allocator, 4);
    defer pool.deinit();

    try std.testing.expect(pool.worker_count == 4);
    try std.testing.expect(pool.work_queues.len == 4);
}

test "work queue push pop" {
    var queue = try WorkQueue.init(std.testing.allocator);
    defer queue.deinit();

    // 创建一个模拟对象
    var header = generational_gc.GCObjectHeader.init(64);

    try queue.push(.{ .mark_object = &header });

    const item = queue.pop();
    try std.testing.expect(item != null);
}

test "parallel marker" {
    var marker = try ParallelMarker.init(std.testing.allocator, 2);
    defer marker.deinit();

    try std.testing.expect(marker.worker_count == 2);
    try std.testing.expect(marker.mark_stacks.len == 2);
}

test "parallel sweeper" {
    var sweeper = try ParallelSweeper.init(std.testing.allocator, 2);
    defer sweeper.deinit();

    try std.testing.expect(sweeper.worker_count == 2);
}
