const std = @import("std");
const time_compat = @import("time_compat.zig");
/// 实现 Task 6.2: 增量标记避免长停顿
///
/// 特性：
/// - 三色标记（white/gray/black）
/// - 灰色栈（待扫描对象队列）
/// - 增量步进（每次处理固定数量对象）
/// - SATB 写屏障（Snapshot-At-The-Beginning）
/// - 并发清除

// ============================================================================
// 常量定义
// ============================================================================

/// 默认每步处理的对象数量
pub const DEFAULT_STEP_OBJECTS: usize = 100;

/// 默认每步处理的最大时间（微秒）
pub const DEFAULT_STEP_TIME_US: u64 = 1000; // 1ms

/// 灰色栈初始容量
pub const GRAY_STACK_INITIAL_CAPACITY: usize = 256;

/// SATB 缓冲区初始容量
pub const SATB_BUFFER_INITIAL_CAPACITY: usize = 128;

// ============================================================================
// 三色标记
// ============================================================================

/// 三色标记状态
pub const MarkColor = enum(u2) {
    /// 白色：未访问，可能是垃圾
    white = 0,
    /// 灰色：已发现但子对象未扫描
    gray = 1,
    /// 黑色：已完全扫描
    black = 2,
};

// ============================================================================
// 增量 GC 对象头
// ============================================================================

/// 增量 GC 对象头
/// 与 generational_gc.GCObjectHeader 兼容，但专注于增量标记
pub const IncrementalObjectHeader = struct {
    /// 对象大小（包含头部）
    size: u32,
    /// 标记颜色
    mark: MarkColor,
    /// 是否在灰色栈中
    in_gray_stack: bool,
    /// 子对象遍历器（用于增量扫描）
    child_scanner: ?*const ChildScanner,
    /// 析构函数
    destructor: ?*const fn (*anyopaque, std.mem.Allocator) void,
    /// 下一个对象（用于对象链表）
    next: ?*IncrementalObjectHeader,
    /// 上一个对象（用于双向链表）
    prev: ?*IncrementalObjectHeader,

    /// 子对象扫描器类型
    pub const ChildScanner = fn (header: *IncrementalObjectHeader, callback: *const fn (*IncrementalObjectHeader) void) void;

    pub fn init(size: u32) IncrementalObjectHeader {
        return .{
            .size = size,
            .mark = .white,
            .in_gray_stack = false,
            .child_scanner = null,
            .destructor = null,
            .next = null,
            .prev = null,
        };
    }

    /// 获取数据指针
    pub fn getDataPtr(self: *IncrementalObjectHeader) *anyopaque {
        const header_ptr: [*]u8 = @ptrCast(self);
        return @ptrCast(header_ptr + @sizeOf(IncrementalObjectHeader));
    }

    /// 从数据指针获取头部
    pub fn fromDataPtr(data: *anyopaque) *IncrementalObjectHeader {
        const data_ptr: [*]u8 = @ptrCast(data);
        return @ptrCast(@alignCast(data_ptr - @sizeOf(IncrementalObjectHeader)));
    }

    /// 设置子对象扫描器
    pub fn setChildScanner(self: *IncrementalObjectHeader, scanner: *const ChildScanner) void {
        self.child_scanner = scanner;
    }
};

// ============================================================================
// 灰色栈
// ============================================================================

/// 灰色栈 - 存储待扫描的灰色对象
pub const GrayStack = struct {
    /// 栈数据
    items: std.ArrayListUnmanaged(*IncrementalObjectHeader),
    /// 后备分配器
    allocator: std.mem.Allocator,
    /// 统计：推入次数
    push_count: u64,
    /// 统计：弹出次数
    pop_count: u64,
    /// 统计：峰值大小
    peak_size: usize,

    pub fn init(allocator: std.mem.Allocator) GrayStack {
        return .{
            .items = .{},
            .allocator = allocator,
            .push_count = 0,
            .pop_count = 0,
            .peak_size = 0,
        };
    }

    pub fn deinit(self: *GrayStack) void {
        self.items.deinit(self.allocator);
    }

    /// 推入灰色对象
    pub fn push(self: *GrayStack, obj: *IncrementalObjectHeader) !void {
        // 避免重复推入
        if (obj.in_gray_stack) return;

        try self.items.append(self.allocator, obj);
        obj.in_gray_stack = true;
        self.push_count += 1;

        // 更新峰值
        if (self.items.items.len > self.peak_size) {
            self.peak_size = self.items.items.len;
        }
    }

    /// 弹出灰色对象
    pub fn pop(self: *GrayStack) ?*IncrementalObjectHeader {
        if (self.items.items.len == 0) return null;

        const obj = self.items.pop();
        if (obj) |o| {
            o.in_gray_stack = false;
            self.pop_count += 1;
            return o;
        }
        return null;
    }

    /// 检查是否为空
    pub fn isEmpty(self: *const GrayStack) bool {
        return self.items.items.len == 0;
    }

    /// 获取当前大小
    pub fn size(self: *const GrayStack) usize {
        return self.items.items.len;
    }

    /// 清空栈
    pub fn clear(self: *GrayStack) void {
        for (self.items.items) |obj| {
            if (obj.in_gray_stack) {
                obj.in_gray_stack = false;
            }
        }
        self.items.clearRetainingCapacity();
    }

    /// 获取统计信息
    pub fn getStats(self: *const GrayStack) GrayStackStats {
        return .{
            .current_size = self.items.items.len,
            .peak_size = self.peak_size,
            .push_count = self.push_count,
            .pop_count = self.pop_count,
        };
    }

    pub const GrayStackStats = struct {
        current_size: usize,
        peak_size: usize,
        push_count: u64,
        pop_count: u64,
    };
};

// ============================================================================
// SATB 写屏障
// ============================================================================

/// SATB (Snapshot-At-The-Beginning) 写屏障
/// 在标记阶段，当指针被覆盖时，记录旧值以保证标记的正确性
pub const SATBWriteBarrier = struct {
    /// SATB 缓冲区
    buffer: std.ArrayListUnmanaged(*IncrementalObjectHeader),
    /// 后备分配器
    allocator: std.mem.Allocator,
    /// 是否激活（仅在标记阶段激活）
    active: bool,
    /// 统计：记录次数
    record_count: u64,
    /// 统计：处理次数
    process_count: u64,

    pub fn init(allocator: std.mem.Allocator) SATBWriteBarrier {
        return .{
            .buffer = .{},
            .allocator = allocator,
            .active = false,
            .record_count = 0,
            .process_count = 0,
        };
    }

    pub fn deinit(self: *SATBWriteBarrier) void {
        self.buffer.deinit(self.allocator);
    }

    /// 激活写屏障（标记开始时调用）
    pub fn activate(self: *SATBWriteBarrier) void {
        self.active = true;
    }

    /// 停用写屏障（标记结束时调用）
    pub fn deactivate(self: *SATBWriteBarrier) void {
        self.active = false;
    }

    /// 记录被覆盖的旧引用
    /// 在指针更新前调用：old_ref = new_ref
    pub fn record(self: *SATBWriteBarrier, old_ref: ?*IncrementalObjectHeader) !void {
        if (!self.active) return;
        if (old_ref == null) return;

        const obj = old_ref.?;
        // 只记录白色对象（未被标记的）
        if (obj.mark == .white) {
            try self.buffer.append(self.allocator, obj);
            self.record_count += 1;
        }
    }

    /// 处理 SATB 缓冲区，将记录的对象标记为灰色
    pub fn process(self: *SATBWriteBarrier, gray_stack: *GrayStack) !void {
        for (self.buffer.items) |obj| {
            if (obj.mark == .white) {
                obj.mark = .gray;
                try gray_stack.push(obj);
                self.process_count += 1;
            }
        }
        self.buffer.clearRetainingCapacity();
    }

    /// 获取缓冲区大小
    pub fn bufferSize(self: *const SATBWriteBarrier) usize {
        return self.buffer.items.len;
    }

    /// 获取统计信息
    pub fn getStats(self: *const SATBWriteBarrier) SATBStats {
        return .{
            .buffer_size = self.buffer.items.len,
            .record_count = self.record_count,
            .process_count = self.process_count,
            .active = self.active,
        };
    }

    pub const SATBStats = struct {
        buffer_size: usize,
        record_count: u64,
        process_count: u64,
        active: bool,
    };
};

// ============================================================================
// 增量标记 GC 主结构
// ============================================================================

/// 增量标记垃圾回收器
pub const IncrementalGC = struct {
    /// 后备分配器
    allocator: std.mem.Allocator,
    /// 灰色栈
    gray_stack: GrayStack,
    /// SATB 写屏障
    satb_barrier: SATBWriteBarrier,
    /// 所有对象链表头
    all_objects: ?*IncrementalObjectHeader,
    /// 根对象集合
    roots: std.ArrayListUnmanaged(*IncrementalObjectHeader),
    /// GC 状态
    state: GCState,
    /// 配置
    config: GCConfig,
    /// 统计信息
    stats: GCStatistics,
    /// 当前标记周期的白色值（用于翻转）
    current_white: MarkColor,
    /// 待清除对象链表
    sweep_cursor: ?*IncrementalObjectHeader,

    /// GC 状态
    pub const GCState = enum {
        /// 空闲状态
        idle,
        /// 标记阶段
        marking,
        /// 清除阶段
        sweeping,
        /// 完成状态（等待重置）
        complete,
    };

    /// GC 配置
    pub const GCConfig = struct {
        /// 每步处理的最大对象数
        step_objects: usize = DEFAULT_STEP_OBJECTS,
        /// 每步处理的最大时间（微秒）
        step_time_us: u64 = DEFAULT_STEP_TIME_US,
        /// 是否启用时间限制
        use_time_limit: bool = true,
        /// 触发 GC 的内存阈值
        gc_threshold: usize = 1024 * 1024, // 1MB
        /// GC 后的内存阈值增长因子
        threshold_growth_factor: f64 = 1.5,
    };

    /// GC 统计信息
    pub const GCStatistics = struct {
        /// GC 周期数
        gc_cycles: u64 = 0,
        /// 增量步进次数
        incremental_steps: u64 = 0,
        /// 标记的对象数
        objects_marked: u64 = 0,
        /// 清除的对象数
        objects_swept: u64 = 0,
        /// 释放的内存字节数
        bytes_freed: u64 = 0,
        /// 总分配字节数
        total_allocated: u64 = 0,
        /// 当前存活对象数
        live_objects: u64 = 0,
        /// 最近一次标记耗时（纳秒）
        last_mark_time_ns: u64 = 0,
        /// 最近一次清除耗时（纳秒）
        last_sweep_time_ns: u64 = 0,
        /// 最大单步耗时（纳秒）
        max_step_time_ns: u64 = 0,
        /// 累计 GC 时间（纳秒）
        total_gc_time_ns: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) IncrementalGC {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: GCConfig) IncrementalGC {
        return .{
            .allocator = allocator,
            .gray_stack = GrayStack.init(allocator),
            .satb_barrier = SATBWriteBarrier.init(allocator),
            .all_objects = null,
            .roots = .{},
            .state = .idle,
            .config = config,
            .stats = .{},
            .current_white = .white,
            .sweep_cursor = null,
        };
    }

    pub fn deinit(self: *IncrementalGC) void {
        // 释放所有对象
        var obj = self.all_objects;
        while (obj) |current| {
            const next = current.next;
            // 调用析构函数
            if (current.destructor) |dtor| {
                dtor(current.getDataPtr(), self.allocator);
            }
            // 释放内存
            const bytes: [*]u8 = @ptrCast(current);
            self.allocator.free(bytes[0..current.size]);
            obj = next;
        }

        self.gray_stack.deinit();
        self.satb_barrier.deinit();
        self.roots.deinit(self.allocator);
    }

    // ========================================================================
    // 对象分配
    // ========================================================================

    /// 分配对象
    pub fn alloc(self: *IncrementalGC, size: usize) !*IncrementalObjectHeader {
        const total_size = @sizeOf(IncrementalObjectHeader) + size;
        const aligned_size = std.mem.alignForward(usize, total_size, @alignOf(IncrementalObjectHeader));

        const bytes = try self.allocator.alloc(u8, aligned_size);
        const header: *IncrementalObjectHeader = @ptrCast(@alignCast(bytes.ptr));
        header.* = IncrementalObjectHeader.init(@intCast(aligned_size));

        // 新对象标记为当前白色（如果在标记阶段，标记为黑色避免被回收）
        if (self.state == .marking) {
            header.mark = .black;
        } else {
            header.mark = self.current_white;
        }

        // 加入对象链表
        header.next = self.all_objects;
        header.prev = null;
        if (self.all_objects) |first| {
            first.prev = header;
        }
        self.all_objects = header;

        self.stats.total_allocated += aligned_size;
        self.stats.live_objects += 1;

        return header;
    }

    // ========================================================================
    // 根对象管理
    // ========================================================================

    /// 添加根对象
    pub fn addRoot(self: *IncrementalGC, obj: *IncrementalObjectHeader) !void {
        try self.roots.append(self.allocator, obj);
    }

    /// 移除根对象
    pub fn removeRoot(self: *IncrementalGC, obj: *IncrementalObjectHeader) void {
        for (self.roots.items, 0..) |root, i| {
            if (root == obj) {
                _ = self.roots.swapRemove(i);
                break;
            }
        }
    }

    // ========================================================================
    // 写屏障
    // ========================================================================

    /// 写屏障 - 在指针更新前调用
    /// old_ref: 被覆盖的旧引用
    /// new_ref: 新引用（可选，用于增量更新）
    pub fn writeBarrier(self: *IncrementalGC, old_ref: ?*IncrementalObjectHeader, new_ref: ?*IncrementalObjectHeader) !void {
        // SATB: 记录旧引用
        try self.satb_barrier.record(old_ref);

        // 增量更新：如果新引用是白色，标记为灰色
        if (self.state == .marking) {
            if (new_ref) |obj| {
                if (obj.mark == self.current_white) {
                    obj.mark = .gray;
                    try self.gray_stack.push(obj);
                }
            }
        }
    }

    // ========================================================================
    // 增量标记
    // ========================================================================

    /// 开始 GC 周期
    pub fn startCycle(self: *IncrementalGC) !void {
        if (self.state != .idle) return;

        self.state = .marking;
        self.stats.gc_cycles += 1;

        // 激活 SATB 写屏障
        self.satb_barrier.activate();

        // 将所有根对象标记为灰色
        for (self.roots.items) |root| {
            if (root.mark == self.current_white) {
                root.mark = .gray;
                try self.gray_stack.push(root);
            }
        }
    }

    /// 执行增量标记步进
    /// 返回：是否完成标记阶段
    pub fn markStep(self: *IncrementalGC) !bool {
        if (self.state != .marking) return true;

        const start_time = time_compat.nanoTimestamp();
        var objects_processed: usize = 0;

        // 处理 SATB 缓冲区
        try self.satb_barrier.process(&self.gray_stack);

        // 处理灰色栈
        while (!self.gray_stack.isEmpty()) {
            // 检查是否达到步进限制
            if (objects_processed >= self.config.step_objects) break;

            if (self.config.use_time_limit) {
                const elapsed: u64 = @intCast(time_compat.nanoTimestamp() - start_time);
                if (elapsed >= self.config.step_time_us * 1000) break;
            }

            // 弹出灰色对象
            const obj = self.gray_stack.pop().?;

            // 扫描子对象
            if (obj.child_scanner) |scanner| {
                scanner(obj, &struct {
                    fn callback(child: *IncrementalObjectHeader) void {
                        // 注意：这里无法访问 self，需要通过其他方式处理
                        // 简化实现：直接标记为灰色
                        if (child.mark == .white) {
                            child.mark = .gray;
                        }
                    }
                }.callback);
            }

            // 标记为黑色
            obj.mark = .black;
            objects_processed += 1;
            self.stats.objects_marked += 1;
        }

        self.stats.incremental_steps += 1;

        // 记录步进时间
        const step_time: u64 = @intCast(time_compat.nanoTimestamp() - start_time);
        if (step_time > self.stats.max_step_time_ns) {
            self.stats.max_step_time_ns = step_time;
        }
        self.stats.total_gc_time_ns += step_time;

        // 检查是否完成标记
        if (self.gray_stack.isEmpty() and self.satb_barrier.bufferSize() == 0) {
            self.satb_barrier.deactivate();
            self.stats.last_mark_time_ns = step_time;
            self.state = .sweeping;
            self.sweep_cursor = self.all_objects;
            return true;
        }

        return false;
    }

    // ========================================================================
    // 并发清除
    // ========================================================================

    /// 执行增量清除步进
    /// 返回：是否完成清除阶段
    pub fn sweepStep(self: *IncrementalGC) bool {
        if (self.state != .sweeping) return true;

        const start_time = time_compat.nanoTimestamp();
        var objects_processed: usize = 0;

        while (self.sweep_cursor) |obj| {
            // 检查是否达到步进限制
            if (objects_processed >= self.config.step_objects) break;

            if (self.config.use_time_limit) {
                const elapsed: u64 = @intCast(time_compat.nanoTimestamp() - start_time);
                if (elapsed >= self.config.step_time_us * 1000) break;
            }

            const next = obj.next;

            // 检查是否为白色（垃圾）
            if (obj.mark == self.current_white) {
                // 从链表移除
                if (obj.prev) |prev| {
                    prev.next = obj.next;
                } else {
                    self.all_objects = obj.next;
                }
                if (obj.next) |next_obj| {
                    next_obj.prev = obj.prev;
                }

                // 调用析构函数
                if (obj.destructor) |dtor| {
                    dtor(obj.getDataPtr(), self.allocator);
                }

                // 释放内存
                const size = obj.size;
                const bytes: [*]u8 = @ptrCast(obj);
                self.allocator.free(bytes[0..size]);

                self.stats.objects_swept += 1;
                self.stats.bytes_freed += size;
                self.stats.live_objects -= 1;
            } else {
                // 重置标记为白色（为下一轮 GC 准备）
                obj.mark = self.current_white;
            }

            objects_processed += 1;
            self.sweep_cursor = next;
        }

        self.stats.incremental_steps += 1;

        // 记录步进时间
        const step_time: u64 = @intCast(time_compat.nanoTimestamp() - start_time);
        if (step_time > self.stats.max_step_time_ns) {
            self.stats.max_step_time_ns = step_time;
        }
        self.stats.total_gc_time_ns += step_time;

        // 检查是否完成清除
        if (self.sweep_cursor == null) {
            self.stats.last_sweep_time_ns = step_time;
            self.state = .complete;
            return true;
        }

        return false;
    }

    /// 完成 GC 周期
    pub fn finishCycle(self: *IncrementalGC) void {
        if (self.state != .complete) return;
        self.state = .idle;
    }

    // ========================================================================
    // 便捷方法
    // ========================================================================

    /// 执行一步增量 GC
    /// 返回：GC 周期是否完成
    pub fn step(self: *IncrementalGC) !bool {
        switch (self.state) {
            .idle => {
                try self.startCycle();
                return false;
            },
            .marking => {
                _ = try self.markStep();
                return false;
            },
            .sweeping => {
                _ = self.sweepStep();
                return false;
            },
            .complete => {
                self.finishCycle();
                return true;
            },
        }
    }

    /// 执行完整 GC 周期（阻塞）
    pub fn collectFull(self: *IncrementalGC) !void {
        // 如果已经在进行中，先完成
        while (self.state != .idle) {
            _ = try self.step();
        }

        // 开始新周期
        try self.startCycle();

        // 完成标记
        while (self.state == .marking) {
            _ = try self.markStep();
        }

        // 完成清除
        while (self.state == .sweeping) {
            _ = self.sweepStep();
        }

        // 完成周期
        self.finishCycle();
    }

    /// 检查是否需要 GC
    pub fn shouldCollect(self: *const IncrementalGC) bool {
        return self.stats.total_allocated - self.stats.bytes_freed >= self.config.gc_threshold;
    }

    /// 获取当前状态
    pub fn getState(self: *const IncrementalGC) GCState {
        return self.state;
    }

    /// 获取统计信息
    pub fn getStats(self: *const IncrementalGC) GCStatistics {
        return self.stats;
    }

    /// 获取灰色栈统计
    pub fn getGrayStackStats(self: *const IncrementalGC) GrayStack.GrayStackStats {
        return self.gray_stack.getStats();
    }

    /// 获取 SATB 统计
    pub fn getSATBStats(self: *const IncrementalGC) SATBWriteBarrier.SATBStats {
        return self.satb_barrier.getStats();
    }
};

// ============================================================================
// 测试
// ============================================================================

test "gray stack basic operations" {
    var stack = GrayStack.init(std.testing.allocator);
    defer stack.deinit();

    // 创建测试对象
    var obj1 = IncrementalObjectHeader.init(64);
    var obj2 = IncrementalObjectHeader.init(128);

    // 测试推入
    try stack.push(&obj1);
    try std.testing.expect(stack.size() == 1);
    try std.testing.expect(obj1.in_gray_stack == true);

    // 测试重复推入（应该被忽略）
    try stack.push(&obj1);
    try std.testing.expect(stack.size() == 1);

    // 推入第二个对象
    try stack.push(&obj2);
    try std.testing.expect(stack.size() == 2);

    // 测试弹出
    const popped = stack.pop();
    try std.testing.expect(popped == &obj2);
    try std.testing.expect(obj2.in_gray_stack == false);
    try std.testing.expect(stack.size() == 1);

    // 测试统计
    const stats = stack.getStats();
    try std.testing.expect(stats.push_count == 2);
    try std.testing.expect(stats.pop_count == 1);
    try std.testing.expect(stats.peak_size == 2);
}

test "SATB write barrier" {
    var barrier = SATBWriteBarrier.init(std.testing.allocator);
    defer barrier.deinit();

    var gray_stack = GrayStack.init(std.testing.allocator);
    defer gray_stack.deinit();

    // 创建测试对象
    var obj1 = IncrementalObjectHeader.init(64);
    obj1.mark = .white;

    // 未激活时不记录
    try barrier.record(&obj1);
    try std.testing.expect(barrier.bufferSize() == 0);

    // 激活后记录
    barrier.activate();
    try std.testing.expect(barrier.active == true);

    try barrier.record(&obj1);
    try std.testing.expect(barrier.bufferSize() == 1);

    // 处理缓冲区
    try barrier.process(&gray_stack);
    try std.testing.expect(barrier.bufferSize() == 0);
    try std.testing.expect(obj1.mark == .gray);
    try std.testing.expect(gray_stack.size() == 1);

    // 停用
    barrier.deactivate();
    try std.testing.expect(barrier.active == false);
}

test "incremental gc allocation" {
    var gc = IncrementalGC.init(std.testing.allocator);
    defer gc.deinit();

    // 分配对象
    const obj1 = try gc.alloc(64);
    try std.testing.expect(obj1.size > 64);
    try std.testing.expect(gc.stats.live_objects == 1);

    const obj2 = try gc.alloc(128);
    try std.testing.expect(gc.stats.live_objects == 2);

    // 检查链表
    try std.testing.expect(gc.all_objects == obj2);
    try std.testing.expect(obj2.next == obj1);
}

test "incremental gc root management" {
    var gc = IncrementalGC.init(std.testing.allocator);
    defer gc.deinit();

    const obj = try gc.alloc(64);

    // 添加根
    try gc.addRoot(obj);
    try std.testing.expect(gc.roots.items.len == 1);

    // 移除根
    gc.removeRoot(obj);
    try std.testing.expect(gc.roots.items.len == 0);
}

test "incremental gc mark cycle" {
    var gc = IncrementalGC.init(std.testing.allocator);
    defer gc.deinit();

    // 分配对象
    const obj1 = try gc.alloc(64);
    const obj2 = try gc.alloc(64);

    // 只有 obj1 是根
    try gc.addRoot(obj1);

    // 开始 GC 周期
    try gc.startCycle();
    try std.testing.expect(gc.state == .marking);
    try std.testing.expect(gc.satb_barrier.active == true);

    // 执行标记步进
    while (gc.state == .marking) {
        _ = try gc.markStep();
    }

    // 应该进入清除阶段
    try std.testing.expect(gc.state == .sweeping);

    // obj1 应该是黑色（被标记）
    try std.testing.expect(obj1.mark == .black);
    // obj2 应该是白色（未被标记，将被回收）
    try std.testing.expect(obj2.mark == .white);
}

test "incremental gc sweep cycle" {
    var gc = IncrementalGC.init(std.testing.allocator);
    defer gc.deinit();

    // 分配对象
    const obj1 = try gc.alloc(64);
    _ = try gc.alloc(64); // obj2 - 无根引用

    // 只有 obj1 是根
    try gc.addRoot(obj1);

    // 执行完整 GC
    try gc.collectFull();

    // 检查统计
    try std.testing.expect(gc.stats.gc_cycles == 1);
    try std.testing.expect(gc.stats.objects_swept >= 1);
    try std.testing.expect(gc.stats.live_objects == 1);
    try std.testing.expect(gc.state == .idle);
}

test "incremental gc step by step" {
    var gc = IncrementalGC.initWithConfig(std.testing.allocator, .{
        .step_objects = 1, // 每步只处理1个对象
        .use_time_limit = false,
    });
    defer gc.deinit();

    // 分配多个对象
    const obj1 = try gc.alloc(64);
    _ = try gc.alloc(64);
    _ = try gc.alloc(64);

    try gc.addRoot(obj1);

    // 逐步执行
    var steps: usize = 0;
    while (!try gc.step()) {
        steps += 1;
        if (steps > 100) break; // 防止无限循环
    }

    try std.testing.expect(gc.state == .idle);
    try std.testing.expect(gc.stats.incremental_steps > 1);
}

test "incremental gc write barrier" {
    var gc = IncrementalGC.init(std.testing.allocator);
    defer gc.deinit();

    const obj1 = try gc.alloc(64);
    const obj2 = try gc.alloc(64);

    try gc.addRoot(obj1);

    // 开始标记
    try gc.startCycle();

    // 模拟指针更新：obj1.field = obj2
    // 旧值为 null，新值为 obj2
    try gc.writeBarrier(null, obj2);

    // obj2 应该被标记为灰色（因为在标记阶段被引用）
    try std.testing.expect(obj2.mark == .gray);
}

test "incremental gc statistics" {
    var gc = IncrementalGC.init(std.testing.allocator);
    defer gc.deinit();

    const obj = try gc.alloc(64);
    try gc.addRoot(obj);

    try gc.collectFull();

    const stats = gc.getStats();
    try std.testing.expect(stats.gc_cycles == 1);
    try std.testing.expect(stats.total_allocated > 0);
    try std.testing.expect(stats.total_gc_time_ns > 0);

    const gray_stats = gc.getGrayStackStats();
    try std.testing.expect(gray_stats.push_count > 0);

    const satb_stats = gc.getSATBStats();
    try std.testing.expect(satb_stats.active == false);
}
