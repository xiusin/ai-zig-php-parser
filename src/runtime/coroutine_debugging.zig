//! ============================================================================
//! Coroutine Debugging and Monitoring System
//! ============================================================================
//!
//! Provides comprehensive debugging and monitoring for coroutines including:
//! - Coroutine stack traces (Requirement 11.2)
//! - Performance monitoring (Requirement 11.7)
//! - Deadlock detection (Requirement 11.6)
//!
//! Architecture:
//! ┌─────────────────────────────────────────────────────────────────┐
//! │              Coroutine Debugging & Monitoring System             │
//! ├─────────────────────────────────────────────────────────────────┤
//! │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
//! │  │ Stack Trace  │  │ Performance  │  │ Deadlock     │          │
//! │  │ Manager      │  │ Monitor      │  │ Detector     │          │
//! │  └──────────────┘  └──────────────┘  └──────────────┘          │
//! │         │                 │                 │                   │
//! │         └─────────────────┴─────────────────┘                   │
//! │                           │                                     │
//! │                    ┌──────▼──────┐                              │
//! │                    │ Debug       │                              │
//! │                    │ Coordinator │                              │
//! │                    └──────┬──────┘                              │
//! │                           │                                     │
//! │         ┌─────────────────┼─────────────────┐                   │
//! │         │                 │                 │                   │
//! │  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐            │
//! │  │ Trace       │  │ Metrics     │  │ Alert       │            │
//! │  │ Formatter   │  │ Collector   │  │ System      │            │
//! │  └─────────────┘  └─────────────┘  └─────────────┘            │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! ============================================================================

const std = @import("std");
const error_handling = @import("coroutine_error_handling.zig");
const CoroutineStackFrame = error_handling.CoroutineStackFrame;
const CoroutineErrorType = error_handling.CoroutineErrorType;

// ============================================================================
// Constants
// ============================================================================

/// Maximum stack trace depth
const MAX_STACK_DEPTH: usize = 128;

/// Deadlock detection interval (milliseconds)
const DEADLOCK_CHECK_INTERVAL_MS: u64 = 5_000;

/// Default deadlock timeout (milliseconds)
const DEFAULT_DEADLOCK_TIMEOUT_MS: u64 = 30_000;

// ============================================================================
// Coroutine Stack Trace Manager
// ============================================================================

/// Manages stack traces for coroutines
/// Implements Requirement 11.2 - coroutine stack traces
pub const StackTraceManager = struct {
    allocator: std.mem.Allocator,
    /// Stack traces per coroutine
    traces: std.AutoHashMap(u64, *CoroutineStackTrace),
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,

    pub const CoroutineStackTrace = struct {
        coroutine_id: u64,
        frames: std.ArrayListUnmanaged(StackFrame),
        max_depth: usize,
        allocator: std.mem.Allocator,

        pub const StackFrame = struct {
            function_name: []const u8,
            file_name: []const u8,
            line: u32,
            column: u32,
            entry_time: i64,
            local_vars: ?std.StringHashMap([]const u8),

            pub fn deinit(self: *StackFrame, allocator: std.mem.Allocator) void {
                allocator.free(self.function_name);
                allocator.free(self.file_name);
                if (self.local_vars) |*vars| {
                    var iter = vars.iterator();
                    while (iter.next()) |entry| {
                        allocator.free(entry.value_ptr.*);
                    }
                    vars.deinit();
                }
            }
        };

        pub fn init(allocator: std.mem.Allocator, coroutine_id: u64) !*CoroutineStackTrace {
            const trace = try allocator.create(CoroutineStackTrace);
            trace.* = CoroutineStackTrace{
                .coroutine_id = coroutine_id,
                .frames = .{},
                .max_depth = MAX_STACK_DEPTH,
                .allocator = allocator,
            };
            return trace;
        }

        pub fn deinit(self: *CoroutineStackTrace) void {
            for (self.frames.items) |*frame| {
                frame.deinit(self.allocator);
            }
            self.frames.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        pub fn pushFrame(
            self: *CoroutineStackTrace,
            function_name: []const u8,
            file_name: []const u8,
            line: u32,
            column: u32,
        ) !void {
            if (self.frames.items.len >= self.max_depth) {
                return error.StackOverflow;
            }

            const frame = StackFrame{
                .function_name = try self.allocator.dupe(u8, function_name),
                .file_name = try self.allocator.dupe(u8, file_name),
                .line = line,
                .column = column,
                .entry_time = @as(i64, @truncate(std.time.nanoTimestamp())),
                .local_vars = null,
            };

            try self.frames.append(self.allocator, frame);
        }

        pub fn popFrame(self: *CoroutineStackTrace) void {
            if (self.frames.items.len > 0) {
                var frame = self.frames.pop().?;
                frame.deinit(self.allocator);
            }
        }

        pub fn getCurrentFrame(self: *CoroutineStackTrace) ?*StackFrame {
            if (self.frames.items.len > 0) {
                return &self.frames.items[self.frames.items.len - 1];
            }
            return null;
        }

        pub fn getDepth(self: *const CoroutineStackTrace) usize {
            return self.frames.items.len;
        }

        pub fn format(self: *const CoroutineStackTrace, allocator: std.mem.Allocator) ![]u8 {
            var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
            defer buffer.deinit(allocator);
            const writer = buffer.writer(allocator);

            try writer.print("Stack trace for coroutine {d}:\n", .{self.coroutine_id});

            var i: usize = self.frames.items.len;
            while (i > 0) {
                i -= 1;
                const frame = &self.frames.items[i];
                try writer.print("  #{d} {s} at {s}:{d}:{d}\n", .{
                    self.frames.items.len - 1 - i,
                    frame.function_name,
                    frame.file_name,
                    frame.line,
                    frame.column,
                });
            }

            return try buffer.toOwnedSlice(allocator);
        }
    };

    pub fn init(allocator: std.mem.Allocator) StackTraceManager {
        return StackTraceManager{
            .allocator = allocator,
            .traces = std.AutoHashMap(u64, *CoroutineStackTrace).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *StackTraceManager) void {
        var iter = self.traces.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.traces.deinit();
    }

    /// Register a coroutine for stack tracing
    pub fn registerCoroutine(self: *StackTraceManager, coroutine_id: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const trace = try CoroutineStackTrace.init(self.allocator, coroutine_id);
        try self.traces.put(coroutine_id, trace);
    }

    /// Unregister a coroutine
    pub fn unregisterCoroutine(self: *StackTraceManager, coroutine_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.traces.fetchRemove(coroutine_id)) |entry| {
            entry.value.deinit();
        }
    }

    /// Push a stack frame
    pub fn pushFrame(
        self: *StackTraceManager,
        coroutine_id: u64,
        function_name: []const u8,
        file_name: []const u8,
        line: u32,
        column: u32,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.traces.get(coroutine_id)) |trace| {
            try trace.pushFrame(function_name, file_name, line, column);
        }
    }

    /// Pop a stack frame
    pub fn popFrame(self: *StackTraceManager, coroutine_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.traces.get(coroutine_id)) |trace| {
            trace.popFrame();
        }
    }

    /// Get stack trace for a coroutine
    pub fn getStackTrace(self: *StackTraceManager, coroutine_id: u64) ?*CoroutineStackTrace {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.traces.get(coroutine_id);
    }

    /// Format stack trace as string
    pub fn formatStackTrace(self: *StackTraceManager, coroutine_id: u64) !?[]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.traces.get(coroutine_id)) |trace| {
            return try trace.format(self.allocator);
        }
        return null;
    }
};

// ============================================================================
// Coroutine Performance Monitor
// ============================================================================

/// Performance monitoring for coroutines
/// Implements Requirement 11.7 - performance metrics
pub const CoroutinePerformanceMonitor = struct {
    allocator: std.mem.Allocator,
    /// Per-coroutine metrics
    metrics: std.AutoHashMap(u64, *CoroutineMetrics),
    /// Global metrics
    global_metrics: GlobalMetrics,
    /// Sampling configuration
    config: MonitorConfig,
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,

    pub const CoroutineMetrics = struct {
        coroutine_id: u64,
        /// Creation timestamp
        created_at: i64,
        /// Total execution time (nanoseconds)
        total_execution_time_ns: u64,
        /// Number of times scheduled
        schedule_count: u64,
        /// Number of yields
        yield_count: u64,
        /// Time spent waiting (nanoseconds)
        wait_time_ns: u64,
        /// Memory allocated by this coroutine
        memory_allocated: usize,
        /// Peak memory usage
        peak_memory: usize,
        /// Last activity timestamp
        last_activity: i64,
        /// Current state
        state: CoroutineState,
        /// Blocking resource (if any)
        blocking_resource: ?BlockingResource,

        pub const CoroutineState = enum {
            created,
            running,
            waiting,
            yielded,
            completed,
            error_state,
        };

        pub const BlockingResource = struct {
            resource_type: ResourceType,
            resource_id: u64,
            blocked_since: i64,

            pub const ResourceType = enum {
                mutex,
                rwmutex,
                channel,
                io,
                timer,
                other,
            };
        };

        pub fn init(allocator: std.mem.Allocator, coroutine_id: u64) !*CoroutineMetrics {
            const metrics = try allocator.create(CoroutineMetrics);
            metrics.* = CoroutineMetrics{
                .coroutine_id = coroutine_id,
                .created_at = @as(i64, @truncate(std.time.nanoTimestamp())),
                .total_execution_time_ns = 0,
                .schedule_count = 0,
                .yield_count = 0,
                .wait_time_ns = 0,
                .memory_allocated = 0,
                .peak_memory = 0,
                .last_activity = @as(i64, @truncate(std.time.nanoTimestamp())),
                .state = .created,
                .blocking_resource = null,
            };
            return metrics;
        }

        pub fn deinit(self: *CoroutineMetrics, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }

        pub fn recordExecution(self: *CoroutineMetrics, duration_ns: u64) void {
            self.total_execution_time_ns += duration_ns;
            self.schedule_count += 1;
            self.last_activity = @as(i64, @truncate(std.time.nanoTimestamp()));
        }

        pub fn recordYield(self: *CoroutineMetrics) void {
            self.yield_count += 1;
            self.state = .yielded;
            self.last_activity = @as(i64, @truncate(std.time.nanoTimestamp()));
        }

        pub fn recordWait(self: *CoroutineMetrics, resource_type: BlockingResource.ResourceType, resource_id: u64) void {
            self.state = .waiting;
            self.blocking_resource = BlockingResource{
                .resource_type = resource_type,
                .resource_id = resource_id,
                .blocked_since = @as(i64, @truncate(std.time.nanoTimestamp())),
            };
        }

        pub fn recordUnblock(self: *CoroutineMetrics) void {
            if (self.blocking_resource) |br| {
                const now = @as(i64, @truncate(std.time.nanoTimestamp()));
                const wait_duration = @as(u64, @intCast(now - br.blocked_since));
                self.wait_time_ns += wait_duration;
            }
            self.blocking_resource = null;
            self.state = .running;
            self.last_activity = @as(i64, @truncate(std.time.nanoTimestamp()));
        }

        pub fn recordMemory(self: *CoroutineMetrics, allocated: usize) void {
            self.memory_allocated = allocated;
            if (allocated > self.peak_memory) {
                self.peak_memory = allocated;
            }
        }

        pub fn getAverageExecutionTime(self: *const CoroutineMetrics) u64 {
            if (self.schedule_count == 0) return 0;
            return self.total_execution_time_ns / self.schedule_count;
        }

        pub fn getLifetime(self: *const CoroutineMetrics) i64 {
            return @as(i64, @truncate(std.time.nanoTimestamp())) - self.created_at;
        }

        pub fn isBlocked(self: *const CoroutineMetrics) bool {
            return self.blocking_resource != null;
        }

        pub fn getBlockedDuration(self: *const CoroutineMetrics) ?u64 {
            if (self.blocking_resource) |br| {
                const now = @as(i64, @truncate(std.time.nanoTimestamp()));
                return @intCast(now - br.blocked_since);
            }
            return null;
        }
    };

    pub const GlobalMetrics = struct {
        total_coroutines_created: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_coroutines_completed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        active_coroutines: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_execution_time_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_wait_time_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_yields: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_schedules: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        peak_active_coroutines: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_memory_allocated: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    };

    pub const MonitorConfig = struct {
        /// Enable detailed per-coroutine metrics
        enable_detailed_metrics: bool = true,
        /// Enable memory tracking
        enable_memory_tracking: bool = true,
        /// Sampling interval (nanoseconds)
        sampling_interval_ns: u64 = 1_000_000, // 1ms
        /// Maximum coroutines to track
        max_tracked_coroutines: usize = 10_000,
    };

    pub fn init(allocator: std.mem.Allocator, config: MonitorConfig) CoroutinePerformanceMonitor {
        return CoroutinePerformanceMonitor{
            .allocator = allocator,
            .metrics = std.AutoHashMap(u64, *CoroutineMetrics).init(allocator),
            .global_metrics = GlobalMetrics{},
            .config = config,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *CoroutinePerformanceMonitor) void {
        var iter = self.metrics.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.metrics.deinit();
    }

    /// Register a coroutine for monitoring
    pub fn registerCoroutine(self: *CoroutinePerformanceMonitor, coroutine_id: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.count() >= self.config.max_tracked_coroutines) {
            return error.TooManyCoroutines;
        }

        const metrics = try CoroutineMetrics.init(self.allocator, coroutine_id);
        try self.metrics.put(coroutine_id, metrics);

        _ = self.global_metrics.total_coroutines_created.fetchAdd(1, .monotonic);
        const active = self.global_metrics.active_coroutines.fetchAdd(1, .monotonic) + 1;

        // Update peak
        var peak = self.global_metrics.peak_active_coroutines.load(.monotonic);
        while (active > peak) {
            const result = self.global_metrics.peak_active_coroutines.cmpxchgWeak(
                peak,
                active,
                .monotonic,
                .monotonic,
            );
            if (result) |new_peak| {
                peak = new_peak;
            } else {
                break;
            }
        }
    }

    /// Unregister a coroutine
    pub fn unregisterCoroutine(self: *CoroutinePerformanceMonitor, coroutine_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.fetchRemove(coroutine_id)) |entry| {
            // Update global metrics before removing
            _ = self.global_metrics.total_execution_time_ns.fetchAdd(
                entry.value.total_execution_time_ns,
                .monotonic,
            );
            _ = self.global_metrics.total_wait_time_ns.fetchAdd(
                entry.value.wait_time_ns,
                .monotonic,
            );
            _ = self.global_metrics.total_yields.fetchAdd(
                entry.value.yield_count,
                .monotonic,
            );
            _ = self.global_metrics.total_schedules.fetchAdd(
                entry.value.schedule_count,
                .monotonic,
            );

            entry.value.deinit(self.allocator);
            _ = self.global_metrics.total_coroutines_completed.fetchAdd(1, .monotonic);
            _ = self.global_metrics.active_coroutines.fetchSub(1, .monotonic);
        }
    }

    /// Record execution time
    pub fn recordExecution(self: *CoroutinePerformanceMonitor, coroutine_id: u64, duration_ns: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.get(coroutine_id)) |metrics| {
            metrics.recordExecution(duration_ns);
        }
    }

    /// Record yield
    pub fn recordYield(self: *CoroutinePerformanceMonitor, coroutine_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.get(coroutine_id)) |metrics| {
            metrics.recordYield();
        }
    }

    /// Record wait on resource
    pub fn recordWait(
        self: *CoroutinePerformanceMonitor,
        coroutine_id: u64,
        resource_type: CoroutineMetrics.BlockingResource.ResourceType,
        resource_id: u64,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.get(coroutine_id)) |metrics| {
            metrics.recordWait(resource_type, resource_id);
        }
    }

    /// Record unblock
    pub fn recordUnblock(self: *CoroutinePerformanceMonitor, coroutine_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.get(coroutine_id)) |metrics| {
            metrics.recordUnblock();
        }
    }

    /// Get metrics for a coroutine
    pub fn getMetrics(self: *CoroutinePerformanceMonitor, coroutine_id: u64) ?*CoroutineMetrics {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.metrics.get(coroutine_id);
    }

    /// Get global metrics
    pub fn getGlobalMetrics(self: *const CoroutinePerformanceMonitor) GlobalMetrics {
        return self.global_metrics;
    }

    /// Get all blocked coroutines
    pub fn getBlockedCoroutines(self: *CoroutinePerformanceMonitor) !std.ArrayListUnmanaged(u64) {
        self.mutex.lock();
        defer self.mutex.unlock();

        var blocked = std.ArrayListUnmanaged(u64){ .items = &.{}, .capacity = 0 };
        var iter = self.metrics.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.isBlocked()) {
                try blocked.append(self.allocator, entry.key_ptr.*);
            }
        }
        return blocked;
    }

    /// Generate performance report
    pub fn generateReport(self: *CoroutinePerformanceMonitor) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
        defer buffer.deinit(self.allocator);
        const writer = buffer.writer(self.allocator);

        try writer.print("=== Coroutine Performance Report ===\n\n", .{});

        // Global metrics
        try writer.print("Global Metrics:\n", .{});
        try writer.print("  Total Created: {d}\n", .{self.global_metrics.total_coroutines_created.load(.monotonic)});
        try writer.print("  Total Completed: {d}\n", .{self.global_metrics.total_coroutines_completed.load(.monotonic)});
        try writer.print("  Active: {d}\n", .{self.global_metrics.active_coroutines.load(.monotonic)});
        try writer.print("  Peak Active: {d}\n", .{self.global_metrics.peak_active_coroutines.load(.monotonic)});
        try writer.print("  Total Execution Time: {d}ms\n", .{self.global_metrics.total_execution_time_ns.load(.monotonic) / 1_000_000});
        try writer.print("  Total Wait Time: {d}ms\n", .{self.global_metrics.total_wait_time_ns.load(.monotonic) / 1_000_000});
        try writer.print("  Total Yields: {d}\n", .{self.global_metrics.total_yields.load(.monotonic)});
        try writer.print("  Total Schedules: {d}\n\n", .{self.global_metrics.total_schedules.load(.monotonic)});

        // Per-coroutine metrics (top 10 by execution time)
        try writer.print("Top Coroutines by Execution Time:\n", .{});
        var iter = self.metrics.iterator();
        var count: usize = 0;
        while (iter.next()) |entry| {
            if (count >= 10) break;
            const m = entry.value_ptr.*;
            try writer.print("  Coroutine {d}: exec={d}ms, waits={d}ms, yields={d}, schedules={d}\n", .{
                m.coroutine_id,
                m.total_execution_time_ns / 1_000_000,
                m.wait_time_ns / 1_000_000,
                m.yield_count,
                m.schedule_count,
            });
            count += 1;
        }

        return try buffer.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Deadlock Detection System
// ============================================================================

/// Deadlock detection for coroutines
/// Implements Requirement 11.6 - deadlock detection with stack traces
pub const DeadlockDetector = struct {
    allocator: std.mem.Allocator,
    /// Resource wait graph (coroutine -> resource it's waiting for)
    wait_graph: std.AutoHashMap(u64, WaitInfo),
    /// Resource ownership (resource -> coroutine that owns it)
    ownership: std.AutoHashMap(u64, u64),
    /// Configuration
    config: DetectorConfig,
    /// Statistics
    stats: DetectorStats,
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,

    pub const WaitInfo = struct {
        coroutine_id: u64,
        resource_id: u64,
        resource_type: ResourceType,
        wait_start: i64,
    };

    pub const ResourceType = enum {
        mutex,
        rwmutex_read,
        rwmutex_write,
        channel_send,
        channel_recv,
        waitgroup,
        other,

        pub fn toString(self: ResourceType) []const u8 {
            return switch (self) {
                .mutex => "Mutex",
                .rwmutex_read => "RWMutex(Read)",
                .rwmutex_write => "RWMutex(Write)",
                .channel_send => "Channel(Send)",
                .channel_recv => "Channel(Recv)",
                .waitgroup => "WaitGroup",
                .other => "Other",
            };
        }
    };

    pub const DetectorConfig = struct {
        /// Timeout before considering a wait as potential deadlock (ms)
        deadlock_timeout_ms: u64 = DEFAULT_DEADLOCK_TIMEOUT_MS,
        /// Enable automatic detection
        enable_auto_detection: bool = true,
        /// Detection interval (ms)
        detection_interval_ms: u64 = DEADLOCK_CHECK_INTERVAL_MS,
        /// Maximum cycle length to detect
        max_cycle_length: usize = 100,
    };

    pub const DetectorStats = struct {
        total_checks: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        deadlocks_detected: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        potential_deadlocks: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        false_positives: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    };

    pub const DeadlockInfo = struct {
        /// Coroutines involved in the deadlock
        coroutines: std.ArrayListUnmanaged(u64),
        /// Resources involved
        resources: std.ArrayListUnmanaged(u64),
        /// Resource types
        resource_types: std.ArrayListUnmanaged(ResourceType),
        /// Detection timestamp
        detected_at: i64,
        /// Cycle description
        cycle_description: []const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) DeadlockInfo {
            return DeadlockInfo{
                .coroutines = .{},
                .resources = .{},
                .resource_types = .{},
                .detected_at = @as(i64, @truncate(std.time.nanoTimestamp())),
                .cycle_description = "",
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *DeadlockInfo) void {
            self.coroutines.deinit(self.allocator);
            self.resources.deinit(self.allocator);
            self.resource_types.deinit(self.allocator);
            if (self.cycle_description.len > 0) {
                self.allocator.free(self.cycle_description);
            }
        }

        pub fn format(self: *const DeadlockInfo, allocator: std.mem.Allocator) ![]u8 {
            var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
            defer buffer.deinit(allocator);
            const writer = buffer.writer(allocator);

            try writer.print("DEADLOCK DETECTED!\n", .{});
            try writer.print("Timestamp: {d}\n", .{self.detected_at});
            try writer.print("Coroutines involved: ", .{});
            for (self.coroutines.items, 0..) |coro_id, i| {
                if (i > 0) try writer.print(" -> ", .{});
                try writer.print("{d}", .{coro_id});
            }
            try writer.print("\n", .{});

            try writer.print("Resources involved:\n", .{});
            for (self.resources.items, 0..) |res_id, i| {
                const res_type = if (i < self.resource_types.items.len)
                    self.resource_types.items[i]
                else
                    ResourceType.other;
                try writer.print("  - {s} (id: {d})\n", .{ res_type.toString(), res_id });
            }

            if (self.cycle_description.len > 0) {
                try writer.print("Cycle: {s}\n", .{self.cycle_description});
            }

            return try buffer.toOwnedSlice(allocator);
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: DetectorConfig) DeadlockDetector {
        return DeadlockDetector{
            .allocator = allocator,
            .wait_graph = std.AutoHashMap(u64, WaitInfo).init(allocator),
            .ownership = std.AutoHashMap(u64, u64).init(allocator),
            .config = config,
            .stats = DetectorStats{},
            .mutex = .{},
        };
    }

    pub fn deinit(self: *DeadlockDetector) void {
        self.wait_graph.deinit();
        self.ownership.deinit();
    }

    /// Record that a coroutine is waiting for a resource
    pub fn recordWait(
        self: *DeadlockDetector,
        coroutine_id: u64,
        resource_id: u64,
        resource_type: ResourceType,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.wait_graph.put(coroutine_id, WaitInfo{
            .coroutine_id = coroutine_id,
            .resource_id = resource_id,
            .resource_type = resource_type,
            .wait_start = @as(i64, @truncate(std.time.nanoTimestamp())),
        });
    }

    /// Record that a coroutine acquired a resource
    pub fn recordAcquire(self: *DeadlockDetector, coroutine_id: u64, resource_id: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove from wait graph
        _ = self.wait_graph.remove(coroutine_id);

        // Add to ownership
        try self.ownership.put(resource_id, coroutine_id);
    }

    /// Record that a coroutine released a resource
    pub fn recordRelease(self: *DeadlockDetector, resource_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.ownership.remove(resource_id);
    }

    /// Check for deadlocks
    pub fn detectDeadlock(self: *DeadlockDetector) !?DeadlockInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        _ = self.stats.total_checks.fetchAdd(1, .monotonic);

        // Build adjacency list for cycle detection
        // coroutine A -> coroutine B if A waits for resource owned by B
        var adj = std.AutoHashMap(u64, u64).init(self.allocator);
        defer adj.deinit();

        var wait_iter = self.wait_graph.iterator();
        while (wait_iter.next()) |entry| {
            const wait_info = entry.value_ptr.*;
            if (self.ownership.get(wait_info.resource_id)) |owner| {
                if (owner != wait_info.coroutine_id) {
                    try adj.put(wait_info.coroutine_id, owner);
                }
            }
        }

        // Detect cycle using DFS
        var visited = std.AutoHashMap(u64, bool).init(self.allocator);
        defer visited.deinit();
        var rec_stack = std.AutoHashMap(u64, bool).init(self.allocator);
        defer rec_stack.deinit();
        var cycle_path = std.ArrayListUnmanaged(u64){ .items = &.{}, .capacity = 0 };
        defer cycle_path.deinit(self.allocator);

        var adj_iter = adj.iterator();
        while (adj_iter.next()) |entry| {
            const start = entry.key_ptr.*;
            if (!visited.contains(start)) {
                if (try self.detectCycleDFS(start, &adj, &visited, &rec_stack, &cycle_path)) {
                    // Deadlock found!
                    _ = self.stats.deadlocks_detected.fetchAdd(1, .monotonic);

                    var info = DeadlockInfo.init(self.allocator);
                    for (cycle_path.items) |coro_id| {
                        try info.coroutines.append(self.allocator, coro_id);
                        if (self.wait_graph.get(coro_id)) |wait_info| {
                            try info.resources.append(self.allocator, wait_info.resource_id);
                            try info.resource_types.append(self.allocator, wait_info.resource_type);
                        }
                    }

                    return info;
                }
            }
        }

        return null;
    }

    fn detectCycleDFS(
        self: *DeadlockDetector,
        node: u64,
        adj: *std.AutoHashMap(u64, u64),
        visited: *std.AutoHashMap(u64, bool),
        rec_stack: *std.AutoHashMap(u64, bool),
        path: *std.ArrayListUnmanaged(u64),
    ) !bool {
        try visited.put(node, true);
        try rec_stack.put(node, true);
        try path.append(self.allocator, node);

        if (adj.get(node)) |next| {
            if (!visited.contains(next)) {
                if (try self.detectCycleDFS(next, adj, visited, rec_stack, path)) {
                    return true;
                }
            } else if (rec_stack.contains(next)) {
                // Cycle found
                try path.append(self.allocator, next);
                return true;
            }
        }

        _ = rec_stack.remove(node);
        _ = path.pop();
        return false;
    }

    /// Check for potential deadlocks (long waits)
    pub fn checkPotentialDeadlocks(self: *DeadlockDetector) !std.ArrayListUnmanaged(WaitInfo) {
        self.mutex.lock();
        defer self.mutex.unlock();

        var potential = std.ArrayListUnmanaged(WaitInfo){ .items = &.{}, .capacity = 0 };
        const now = @as(i64, @truncate(std.time.nanoTimestamp()));
        const timeout_ns = @as(i64, @intCast(self.config.deadlock_timeout_ms * 1_000_000));

        var iter = self.wait_graph.iterator();
        while (iter.next()) |entry| {
            const wait_info = entry.value_ptr.*;
            if (now - wait_info.wait_start > timeout_ns) {
                try potential.append(self.allocator, wait_info);
                _ = self.stats.potential_deadlocks.fetchAdd(1, .monotonic);
            }
        }

        return potential;
    }

    pub fn getStats(self: *const DeadlockDetector) DetectorStats {
        return self.stats;
    }
};

// ============================================================================
// Coroutine Debug Coordinator
// ============================================================================

/// Main coordinator for coroutine debugging and monitoring
pub const CoroutineDebugCoordinator = struct {
    allocator: std.mem.Allocator,
    /// Stack trace manager
    stack_trace_manager: StackTraceManager,
    /// Performance monitor
    performance_monitor: CoroutinePerformanceMonitor,
    /// Deadlock detector
    deadlock_detector: DeadlockDetector,
    /// Debug enabled flag
    debug_enabled: std.atomic.Value(bool),
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,

    pub const DebugConfig = struct {
        enable_stack_traces: bool = true,
        enable_performance_monitoring: bool = true,
        enable_deadlock_detection: bool = true,
        performance_config: CoroutinePerformanceMonitor.MonitorConfig = .{},
        deadlock_config: DeadlockDetector.DetectorConfig = .{},
    };

    pub fn init(allocator: std.mem.Allocator, config: DebugConfig) CoroutineDebugCoordinator {
        return CoroutineDebugCoordinator{
            .allocator = allocator,
            .stack_trace_manager = StackTraceManager.init(allocator),
            .performance_monitor = CoroutinePerformanceMonitor.init(allocator, config.performance_config),
            .deadlock_detector = DeadlockDetector.init(allocator, config.deadlock_config),
            .debug_enabled = std.atomic.Value(bool).init(true),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *CoroutineDebugCoordinator) void {
        self.stack_trace_manager.deinit();
        self.performance_monitor.deinit();
        self.deadlock_detector.deinit();
    }

    /// Enable/disable debugging
    pub fn setDebugEnabled(self: *CoroutineDebugCoordinator, enabled: bool) void {
        self.debug_enabled.store(enabled, .monotonic);
    }

    /// Register a coroutine for debugging
    pub fn registerCoroutine(self: *CoroutineDebugCoordinator, coroutine_id: u64) !void {
        if (!self.debug_enabled.load(.monotonic)) return;

        try self.stack_trace_manager.registerCoroutine(coroutine_id);
        try self.performance_monitor.registerCoroutine(coroutine_id);
    }

    /// Unregister a coroutine
    pub fn unregisterCoroutine(self: *CoroutineDebugCoordinator, coroutine_id: u64) void {
        self.stack_trace_manager.unregisterCoroutine(coroutine_id);
        self.performance_monitor.unregisterCoroutine(coroutine_id);
    }

    /// Record function entry
    pub fn enterFunction(
        self: *CoroutineDebugCoordinator,
        coroutine_id: u64,
        function_name: []const u8,
        file_name: []const u8,
        line: u32,
        column: u32,
    ) !void {
        if (!self.debug_enabled.load(.monotonic)) return;

        try self.stack_trace_manager.pushFrame(coroutine_id, function_name, file_name, line, column);
    }

    /// Record function exit
    pub fn exitFunction(self: *CoroutineDebugCoordinator, coroutine_id: u64) void {
        if (!self.debug_enabled.load(.monotonic)) return;

        self.stack_trace_manager.popFrame(coroutine_id);
    }

    /// Record execution time
    pub fn recordExecution(self: *CoroutineDebugCoordinator, coroutine_id: u64, duration_ns: u64) void {
        if (!self.debug_enabled.load(.monotonic)) return;

        self.performance_monitor.recordExecution(coroutine_id, duration_ns);
    }

    /// Record yield
    pub fn recordYield(self: *CoroutineDebugCoordinator, coroutine_id: u64) void {
        if (!self.debug_enabled.load(.monotonic)) return;

        self.performance_monitor.recordYield(coroutine_id);
    }

    /// Record wait on resource
    pub fn recordWait(
        self: *CoroutineDebugCoordinator,
        coroutine_id: u64,
        resource_type: DeadlockDetector.ResourceType,
        resource_id: u64,
    ) !void {
        if (!self.debug_enabled.load(.monotonic)) return;

        // Map deadlock resource type to performance monitor resource type
        const perf_resource_type: CoroutinePerformanceMonitor.CoroutineMetrics.BlockingResource.ResourceType = switch (resource_type) {
            .mutex => .mutex,
            .rwmutex_read, .rwmutex_write => .rwmutex,
            .channel_send, .channel_recv => .channel,
            .waitgroup => .other,
            .other => .other,
        };

        self.performance_monitor.recordWait(coroutine_id, perf_resource_type, resource_id);
        try self.deadlock_detector.recordWait(coroutine_id, resource_id, resource_type);
    }

    /// Record resource acquisition
    pub fn recordAcquire(self: *CoroutineDebugCoordinator, coroutine_id: u64, resource_id: u64) !void {
        if (!self.debug_enabled.load(.monotonic)) return;

        self.performance_monitor.recordUnblock(coroutine_id);
        try self.deadlock_detector.recordAcquire(coroutine_id, resource_id);
    }

    /// Record resource release
    pub fn recordRelease(self: *CoroutineDebugCoordinator, resource_id: u64) void {
        if (!self.debug_enabled.load(.monotonic)) return;

        self.deadlock_detector.recordRelease(resource_id);
    }

    /// Check for deadlocks
    pub fn checkDeadlocks(self: *CoroutineDebugCoordinator) !?DeadlockDetector.DeadlockInfo {
        if (!self.debug_enabled.load(.monotonic)) return null;

        return try self.deadlock_detector.detectDeadlock();
    }

    /// Get stack trace for a coroutine
    pub fn getStackTrace(self: *CoroutineDebugCoordinator, coroutine_id: u64) !?[]u8 {
        return try self.stack_trace_manager.formatStackTrace(coroutine_id);
    }

    /// Get performance metrics for a coroutine
    pub fn getMetrics(self: *CoroutineDebugCoordinator, coroutine_id: u64) ?*CoroutinePerformanceMonitor.CoroutineMetrics {
        return self.performance_monitor.getMetrics(coroutine_id);
    }

    /// Generate comprehensive debug report
    pub fn generateReport(self: *CoroutineDebugCoordinator) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
        defer buffer.deinit(self.allocator);
        const writer = buffer.writer(self.allocator);

        try writer.print("=== Coroutine Debug Report ===\n\n", .{});

        // Performance report
        const perf_report = try self.performance_monitor.generateReport();
        defer self.allocator.free(perf_report);
        try writer.writeAll(perf_report);

        // Deadlock detection stats
        const deadlock_stats = self.deadlock_detector.getStats();
        try writer.print("\nDeadlock Detection Statistics:\n", .{});
        try writer.print("  Total Checks: {d}\n", .{deadlock_stats.total_checks.load(.monotonic)});
        try writer.print("  Deadlocks Detected: {d}\n", .{deadlock_stats.deadlocks_detected.load(.monotonic)});
        try writer.print("  Potential Deadlocks: {d}\n", .{deadlock_stats.potential_deadlocks.load(.monotonic)});

        // Check for current deadlocks
        if (try self.deadlock_detector.detectDeadlock()) |deadlock_val| {
            var deadlock = deadlock_val;
            defer deadlock.deinit();
            const deadlock_report = try deadlock.format(self.allocator);
            defer self.allocator.free(deadlock_report);
            try writer.print("\n{s}", .{deadlock_report});
        }

        return try buffer.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "StackTraceManager basic operations" {
    const allocator = std.testing.allocator;

    var manager = StackTraceManager.init(allocator);
    defer manager.deinit();

    // Register coroutine
    try manager.registerCoroutine(1);

    // Push frames
    try manager.pushFrame(1, "main", "test.php", 10, 1);
    try manager.pushFrame(1, "foo", "test.php", 20, 5);
    try manager.pushFrame(1, "bar", "test.php", 30, 10);

    // Check trace
    const trace = manager.getStackTrace(1);
    try std.testing.expect(trace != null);
    try std.testing.expectEqual(@as(usize, 3), trace.?.getDepth());

    // Pop frame
    manager.popFrame(1);
    try std.testing.expectEqual(@as(usize, 2), trace.?.getDepth());

    // Format trace
    const formatted = try manager.formatStackTrace(1);
    try std.testing.expect(formatted != null);
    defer allocator.free(formatted.?);
    try std.testing.expect(std.mem.indexOf(u8, formatted.?, "foo") != null);

    // Unregister
    manager.unregisterCoroutine(1);
}

test "CoroutinePerformanceMonitor basic operations" {
    const allocator = std.testing.allocator;

    var monitor = CoroutinePerformanceMonitor.init(allocator, .{});
    defer monitor.deinit();

    // Register coroutine
    try monitor.registerCoroutine(1);

    // Record execution
    monitor.recordExecution(1, 1_000_000); // 1ms
    monitor.recordExecution(1, 2_000_000); // 2ms

    // Record yield
    monitor.recordYield(1);

    // Check metrics
    const metrics = monitor.getMetrics(1);
    try std.testing.expect(metrics != null);
    try std.testing.expectEqual(@as(u64, 2), metrics.?.schedule_count);
    try std.testing.expectEqual(@as(u64, 1), metrics.?.yield_count);
    try std.testing.expectEqual(@as(u64, 3_000_000), metrics.?.total_execution_time_ns);

    // Check global metrics
    const global = monitor.getGlobalMetrics();
    try std.testing.expectEqual(@as(u64, 1), global.total_coroutines_created.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), global.active_coroutines.load(.monotonic));

    // Unregister
    monitor.unregisterCoroutine(1);
    try std.testing.expectEqual(@as(u64, 0), monitor.getGlobalMetrics().active_coroutines.load(.monotonic));
}

test "DeadlockDetector basic operations" {
    const allocator = std.testing.allocator;

    var detector = DeadlockDetector.init(allocator, .{});
    defer detector.deinit();

    // No deadlock scenario
    try detector.recordWait(1, 100, .mutex);
    try detector.recordAcquire(1, 100);
    detector.recordRelease(100);

    const result = try detector.detectDeadlock();
    try std.testing.expect(result == null);
}

test "DeadlockDetector cycle detection" {
    const allocator = std.testing.allocator;

    var detector = DeadlockDetector.init(allocator, .{});
    defer detector.deinit();

    // Create a deadlock scenario:
    // Coroutine 1 owns resource 100, waits for resource 200
    // Coroutine 2 owns resource 200, waits for resource 100
    try detector.recordAcquire(1, 100);
    try detector.recordAcquire(2, 200);
    try detector.recordWait(1, 200, .mutex);
    try detector.recordWait(2, 100, .mutex);

    const result = try detector.detectDeadlock();
    try std.testing.expect(result != null);

    if (result) |result_val| {
        var info = result_val;
        defer info.deinit();
        try std.testing.expect(info.coroutines.items.len >= 2);
    }
}

test "CoroutineDebugCoordinator integration" {
    const allocator = std.testing.allocator;

    var coordinator = CoroutineDebugCoordinator.init(allocator, .{});
    defer coordinator.deinit();

    // Register coroutine
    try coordinator.registerCoroutine(1);

    // Enter functions
    try coordinator.enterFunction(1, "main", "test.php", 10, 1);
    try coordinator.enterFunction(1, "process", "test.php", 50, 5);

    // Record execution
    coordinator.recordExecution(1, 5_000_000);

    // Record yield
    coordinator.recordYield(1);

    // Get stack trace
    const trace = try coordinator.getStackTrace(1);
    try std.testing.expect(trace != null);
    defer allocator.free(trace.?);

    // Get metrics
    const metrics = coordinator.getMetrics(1);
    try std.testing.expect(metrics != null);

    // Generate report
    const report = try coordinator.generateReport();
    defer allocator.free(report);
    try std.testing.expect(std.mem.indexOf(u8, report, "Performance") != null);

    // Exit functions
    coordinator.exitFunction(1);
    coordinator.exitFunction(1);

    // Unregister
    coordinator.unregisterCoroutine(1);
}

test "Performance monitor wait tracking" {
    const allocator = std.testing.allocator;

    var monitor = CoroutinePerformanceMonitor.init(allocator, .{});
    defer monitor.deinit();

    try monitor.registerCoroutine(1);

    // Record wait
    monitor.recordWait(1, .mutex, 100);

    const metrics = monitor.getMetrics(1);
    try std.testing.expect(metrics != null);
    try std.testing.expect(metrics.?.isBlocked());
    try std.testing.expectEqual(CoroutinePerformanceMonitor.CoroutineMetrics.CoroutineState.waiting, metrics.?.state);

    // Simulate some wait time
    std.Thread.sleep(1_000_000); // 1ms

    // Record unblock
    monitor.recordUnblock(1);

    try std.testing.expect(!metrics.?.isBlocked());
    try std.testing.expect(metrics.?.wait_time_ns > 0);

    monitor.unregisterCoroutine(1);
}
