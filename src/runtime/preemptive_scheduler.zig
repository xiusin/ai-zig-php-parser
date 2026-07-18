//! ============================================================================
//! 抢占式调度器 (Preemptive Scheduler)
//! ============================================================================
//!
//! 功能：实现协程的抢占式调度，防止协程独占CPU
//!
//! 工作原理：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                   Preemptive Scheduling                          │
//! │                                                                  │
//! │  时间片 = 10ms (可配置)                                          │
//! │                                                                  │
//! │  ┌─────────────────────────────────────────────────────────┐   │
//! │  │ Coroutine A 执行                                        │   │
//! │  │ |<────────── 10ms ──────────>|                          │   │
//! │  │ ├─────────────────────────────┤                          │   │
//! │  │ 开始                      抢占点                          │   │
//! │  └─────────────────────────────────────────────────────────┘   │
//! │                              ↓                                   │
//! │  ┌─────────────────────────────────────────────────────────┐   │
//! │  │ Coroutine B 执行                                        │   │
//! │  │ |<────────── 10ms ──────────>|                          │   │
//! │  └─────────────────────────────────────────────────────────┘   │
//! │                                                                  │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 核心特性：
//! - 时间片管理：默认10ms，可配置
//! - 抢占信号：通知协程让出CPU
//! - 协作式让出点：在安全点检查是否需要让出
//! - 执行上下文：追踪协程执行时间
//!
//! 让出点类型：
//! - function_call: 函数调用时
//! - loop_iteration: 循环迭代时
//! - memory_allocation: 内存分配时
//! - io_operation: I/O操作时
//! - channel_operation: 通道操作时
//! - mutex_operation: 锁操作时
//!
//! 需求：5.8, 6.7
//! ============================================================================

const std = @import("std");
const Coroutine = @import("coroutine.zig").Coroutine;
const Processor = @import("processor.zig").Processor;
const Worker = @import("worker.zig").Worker;

/// 抢占式调度系统
pub const PreemptiveScheduler = struct {
    allocator: std.mem.Allocator,

    // Time slice management
    time_slice_ns: u64,
    preemption_enabled: bool,

    // Preemption signals
    preemption_signal: std.atomic.Value(bool),
    signal_handlers: std.ArrayList(PreemptionHandler),

    // Cooperative yield points
    yield_points: std.ArrayList(YieldPoint),
    yield_check_interval: u32,

    // Performance monitoring
    preemption_count: std.atomic.Value(u64),
    yield_count: std.atomic.Value(u64),
    time_slice_violations: std.atomic.Value(u64),

    // Thread-local storage for current execution context
    current_execution_context: std.Thread.LocalStorage(ExecutionContext),

    pub const PreemptionHandler = struct {
        callback: *const fn (*Coroutine) void,
        priority: u8,
    };

    pub const YieldPoint = struct {
        location: YieldLocation,
        check_frequency: u32,
        last_check: std.atomic.Value(u64),

        pub const YieldLocation = enum {
            function_call,
            loop_iteration,
            memory_allocation,
            io_operation,
            channel_operation,
            mutex_operation,
        };
    };

    pub const ExecutionContext = struct {
        coroutine: ?*Coroutine,
        start_time: i64,
        last_yield_time: i64,
        yield_check_counter: u32,
        preemption_disabled: bool,

        pub fn init() ExecutionContext {
            const now = std.time.nanoTimestamp();
            return ExecutionContext{
                .coroutine = null,
                .start_time = now,
                .last_yield_time = now,
                .yield_check_counter = 0,
                .preemption_disabled = false,
            };
        }

        pub fn shouldYield(self: *ExecutionContext, time_slice_ns: u64) bool {
            const now = std.time.nanoTimestamp();
            return (now - self.start_time) >= @as(i64, @intCast(time_slice_ns));
        }

        pub fn updateYieldTime(self: *ExecutionContext) void {
            self.last_yield_time = std.time.nanoTimestamp();
            self.yield_check_counter = 0;
        }
    };

    pub fn init(allocator: std.mem.Allocator, time_slice_us: u32) PreemptiveScheduler {
        return PreemptiveScheduler{
            .allocator = allocator,
            .time_slice_ns = @as(u64, time_slice_us) * 1000,
            .preemption_enabled = true,
            .preemption_signal = std.atomic.Value(bool).init(false),
            .signal_handlers = std.ArrayList(PreemptionHandler).init(allocator),
            .yield_points = std.ArrayList(YieldPoint).init(allocator),
            .yield_check_interval = 100, // Check every 100 operations
            .preemption_count = std.atomic.Value(u64).init(0),
            .yield_count = std.atomic.Value(u64).init(0),
            .time_slice_violations = std.atomic.Value(u64).init(0),
            .current_execution_context = std.Thread.LocalStorage(ExecutionContext){},
        };
    }

    pub fn deinit(self: *PreemptiveScheduler) void {
        self.signal_handlers.deinit();
        self.yield_points.deinit();
    }

    /// Initialize execution context for current thread
    /// Requirement 5.8 - time slice management
    pub fn initExecutionContext(self: *PreemptiveScheduler, coroutine: *Coroutine) void {
        var context = ExecutionContext.init();
        context.coroutine = coroutine;
        self.current_execution_context.set(context);
    }

    /// Check if current coroutine should be preempted
    /// Requirement 5.8 - preemptive yield when coroutine runs for more than 10ms
    pub fn shouldPreempt(self: *PreemptiveScheduler) bool {
        if (!self.preemption_enabled) {
            return false;
        }

        if (self.current_execution_context.get()) |*context| {
            if (context.preemption_disabled) {
                return false;
            }

            if (context.shouldYield(self.time_slice_ns)) {
                _ = self.time_slice_violations.fetchAdd(1, .monotonic);
                return true;
            }
        }

        return self.preemption_signal.load(.acquire);
    }

    /// Perform preemptive yield
    /// Requirement 6.7 - preemptive scheduling to prevent starvation
    pub fn preemptCurrentCoroutine(self: *PreemptiveScheduler, processor: *Processor) !void {
        if (self.current_execution_context.get()) |*context| {
            if (context.coroutine) |coroutine| {
                // Save coroutine state
                try self.saveCoroutineState(coroutine);

                // Add back to processor queue with lower priority
                try processor.addCoroutine(coroutine);

                // Update statistics
                _ = self.preemption_count.fetchAdd(1, .monotonic);

                // Signal preemption handlers
                for (self.signal_handlers.items) |handler| {
                    handler.callback(coroutine);
                }

                // Clear current context
                context.coroutine = null;
                context.updateYieldTime();
            }
        }

        // Clear preemption signal
        self.preemption_signal.store(false, .release);
    }

    /// Add cooperative yield point
    /// Requirement 5.8 - implement cooperative yield points
    pub fn addYieldPoint(self: *PreemptiveScheduler, location: YieldPoint.YieldLocation, frequency: u32) !void {
        const yield_point = YieldPoint{
            .location = location,
            .check_frequency = frequency,
            .last_check = std.atomic.Value(u64).init(0),
        };

        try self.yield_points.append(yield_point);
    }

    /// Check yield point and potentially yield
    /// Requirement 5.8 - cooperative yield points
    pub fn checkYieldPoint(self: *PreemptiveScheduler, location: YieldPoint.YieldLocation, processor: *Processor) !bool {
        if (!self.preemption_enabled) {
            return false;
        }

        if (self.current_execution_context.get()) |*context| {
            context.yield_check_counter += 1;

            // Check if we should yield based on frequency
            if (context.yield_check_counter >= self.yield_check_interval) {
                context.yield_check_counter = 0;

                // Find matching yield point
                for (self.yield_points.items) |*yield_point| {
                    if (yield_point.location == location) {
                        const last_check = yield_point.last_check.load(.monotonic);
                        const current_time = @as(u64, @intCast(std.time.nanoTimestamp()));

                        if (current_time - last_check >= yield_point.check_frequency * 1000) {
                            yield_point.last_check.store(current_time, .monotonic);

                            if (context.shouldYield(self.time_slice_ns)) {
                                try self.cooperativeYield(processor);
                                return true;
                            }
                        }
                        break;
                    }
                }
            }
        }

        return false;
    }

    /// Perform cooperative yield
    fn cooperativeYield(self: *PreemptiveScheduler, processor: *Processor) !void {
        if (self.current_execution_context.get()) |*context| {
            if (context.coroutine) |coroutine| {
                // Save coroutine state
                try self.saveCoroutineState(coroutine);

                // Add back to processor queue
                try processor.addCoroutine(coroutine);

                // Update statistics
                _ = self.yield_count.fetchAdd(1, .monotonic);

                // Update context
                context.updateYieldTime();
            }
        }
    }

    /// Save coroutine execution state
    fn saveCoroutineState(self: *PreemptiveScheduler, coroutine: *Coroutine) !void {
        _ = self;

        // Save CPU registers and stack pointer
        // This is a simplified version - real implementation would save actual CPU state
        coroutine.context.save_timestamp = std.time.nanoTimestamp();

        // Mark coroutine as yielded
        coroutine.state = .yielded;
    }

    /// Register preemption signal handler
    pub fn registerPreemptionHandler(self: *PreemptiveScheduler, callback: *const fn (*Coroutine) void, priority: u8) !void {
        const handler = PreemptionHandler{
            .callback = callback,
            .priority = priority,
        };

        try self.signal_handlers.append(handler);

        // Sort handlers by priority
        std.sort.insertion(PreemptionHandler, self.signal_handlers.items, {}, compareHandlerPriority);
    }

    /// Compare handler priorities for sorting
    fn compareHandlerPriority(context: void, a: PreemptionHandler, b: PreemptionHandler) bool {
        _ = context;
        return a.priority > b.priority; // Higher priority first
    }

    /// Send preemption signal
    pub fn sendPreemptionSignal(self: *PreemptiveScheduler) void {
        self.preemption_signal.store(true, .release);
    }

    /// Disable preemption for critical sections
    pub fn disablePreemption(self: *PreemptiveScheduler) void {
        if (self.current_execution_context.get()) |*context| {
            context.preemption_disabled = true;
        }
    }

    /// Enable preemption after critical section
    pub fn enablePreemption(self: *PreemptiveScheduler) void {
        if (self.current_execution_context.get()) |*context| {
            context.preemption_disabled = false;
        }
    }

    /// Get preemption statistics
    pub fn getStats(self: *PreemptiveScheduler) PreemptionStats {
        return PreemptionStats{
            .preemption_count = self.preemption_count.load(.monotonic),
            .yield_count = self.yield_count.load(.monotonic),
            .time_slice_violations = self.time_slice_violations.load(.monotonic),
            .yield_points_count = self.yield_points.items.len,
            .signal_handlers_count = self.signal_handlers.items.len,
        };
    }

    /// Set time slice duration
    pub fn setTimeSlice(self: *PreemptiveScheduler, time_slice_us: u32) void {
        self.time_slice_ns = @as(u64, time_slice_us) * 1000;
    }

    /// Enable or disable preemption
    pub fn setPreemptionEnabled(self: *PreemptiveScheduler, enabled: bool) void {
        self.preemption_enabled = enabled;
    }
};

/// Preemption statistics
pub const PreemptionStats = struct {
    preemption_count: u64,
    yield_count: u64,
    time_slice_violations: u64,
    yield_points_count: usize,
    signal_handlers_count: usize,

    pub fn getTotalYields(self: PreemptionStats) u64 {
        return self.preemption_count + self.yield_count;
    }

    pub fn getPreemptionRatio(self: PreemptionStats) f64 {
        const total = self.getTotalYields();
        return if (total > 0) @as(f64, @floatFromInt(self.preemption_count)) / @as(f64, @floatFromInt(total)) else 0.0;
    }
};

/// Preemption-aware execution wrapper
pub fn withPreemptionCheck(
    scheduler: *PreemptiveScheduler,
    processor: *Processor,
    location: YieldPoint.YieldLocation,
    comptime func: anytype,
    args: anytype,
) !@TypeOf(@call(.auto, func, args)) {
    // Check yield point before execution
    _ = try scheduler.checkYieldPoint(location, processor);

    // Execute function
    const result = try @call(.auto, func, args);

    // Check for preemption after execution
    if (scheduler.shouldPreempt()) {
        try scheduler.preemptCurrentCoroutine(processor);
    }

    return result;
}

// Tests
test "preemptive scheduler initialization" {
    const allocator = std.testing.allocator;

    var scheduler = PreemptiveScheduler.init(allocator, 10_000); // 10ms
    defer scheduler.deinit();

    try std.testing.expect(scheduler.preemption_enabled);
    try std.testing.expectEqual(@as(u64, 10_000_000), scheduler.time_slice_ns); // 10ms in nanoseconds
    try std.testing.expectEqual(@as(usize, 0), scheduler.signal_handlers.items.len);
    try std.testing.expectEqual(@as(usize, 0), scheduler.yield_points.items.len);
}

test "execution context management" {
    const allocator = std.testing.allocator;

    var scheduler = PreemptiveScheduler.init(allocator, 1); // 1us for quick testing
    defer scheduler.deinit();

    // Create mock coroutine
    const types = @import("types.zig");
    const callback = types.Value.initNull();
    const args = [_]types.Value{};
    const coroutine = try Coroutine.init(allocator, 1, callback, &args);
    defer {
        coroutine.deinit();
    }

    scheduler.initExecutionContext(coroutine);

    // Wait a bit to exceed time slice
    std.Thread.sleep(2_000); // 2us

    try std.testing.expect(scheduler.shouldPreempt());

    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.time_slice_violations);
}

test "yield point management" {
    const allocator = std.testing.allocator;

    var scheduler = PreemptiveScheduler.init(allocator, 10_000);
    defer scheduler.deinit();

    try scheduler.addYieldPoint(.function_call, 1000);
    try scheduler.addYieldPoint(.loop_iteration, 500);

    try std.testing.expectEqual(@as(usize, 2), scheduler.yield_points.items.len);

    const stats = scheduler.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.yield_points_count);
}

test "preemption signal handling" {
    const allocator = std.testing.allocator;

    var scheduler = PreemptiveScheduler.init(allocator, 10_000);
    defer scheduler.deinit();

    try std.testing.expect(!scheduler.shouldPreempt());

    scheduler.sendPreemptionSignal();
    try std.testing.expect(scheduler.shouldPreempt());

    // Disable preemption
    scheduler.disablePreemption();
    try std.testing.expect(!scheduler.shouldPreempt());

    // Enable preemption
    scheduler.enablePreemption();
    try std.testing.expect(scheduler.shouldPreempt());
}

test "preemption handler registration" {
    const allocator = std.testing.allocator;

    var scheduler = PreemptiveScheduler.init(allocator, 10_000);
    defer scheduler.deinit();

    const TestHandler = struct {
        fn handler(coro: *Coroutine) void {
            _ = coro;
            // Test handler
        }
    };

    try scheduler.registerPreemptionHandler(TestHandler.handler, 10);
    try scheduler.registerPreemptionHandler(TestHandler.handler, 5);

    try std.testing.expectEqual(@as(usize, 2), scheduler.signal_handlers.items.len);

    // Check priority ordering (higher priority first)
    try std.testing.expectEqual(@as(u8, 10), scheduler.signal_handlers.items[0].priority);
    try std.testing.expectEqual(@as(u8, 5), scheduler.signal_handlers.items[1].priority);
}
