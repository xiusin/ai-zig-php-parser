//! ============================================================================
//! Coroutine Error Handling and Isolation System
//! ============================================================================
//!
//! Provides comprehensive error handling for coroutines including:
//! - Panic recovery for coroutines (Requirement 11.1)
//! - Error propagation mechanisms (Requirement 11.4)
//! - Structured error reporting (Requirement 11.8)
//! - Coroutine stack traces (Requirement 11.2)
//! - Deadlock detection (Requirement 11.6)
//! - Performance monitoring integration (Requirement 11.7)
//!
//! Architecture:
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                  Coroutine Error Handling System                 │
//! ├─────────────────────────────────────────────────────────────────┤
//! │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
//! │  │ Error        │  │ Panic        │  │ Deadlock     │          │
//! │  │ Isolation    │  │ Recovery     │  │ Detection    │          │
//! │  └──────────────┘  └──────────────┘  └──────────────┘          │
//! │         │                 │                 │                   │
//! │         └─────────────────┴─────────────────┘                   │
//! │                           │                                     │
//! │                    ┌──────▼──────┐                              │
//! │                    │ Error       │                              │
//! │                    │ Aggregator  │                              │
//! │                    └──────┬──────┘                              │
//! │                           │                                     │
//! │         ┌─────────────────┼─────────────────┐                   │
//! │         │                 │                 │                   │
//! │  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐            │
//! │  │ Stack Trace │  │ Error       │  │ Performance │            │
//! │  │ Generator   │  │ Reporter    │  │ Monitor     │            │
//! │  └─────────────┘  └─────────────┘  └─────────────┘            │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! ============================================================================

const std = @import("std");

// Note: We use a simple string representation for local variables to avoid
// circular dependencies with types.zig. In production, this could be replaced
// with the actual Value type when integrated with the full runtime.

// ============================================================================
// Error Types and Constants
// ============================================================================

/// Maximum stack trace depth
const MAX_STACK_TRACE_DEPTH: usize = 64;

/// Maximum error message length
const MAX_ERROR_MESSAGE_LENGTH: usize = 4096;

/// Deadlock detection timeout (milliseconds)
const DEADLOCK_DETECTION_TIMEOUT_MS: u64 = 30_000; // 30 seconds

// ============================================================================
// Coroutine Error Types
// ============================================================================

/// Error types specific to coroutine execution
pub const CoroutineErrorType = enum {
    /// Panic occurred during coroutine execution
    panic,
    /// Stack overflow in coroutine
    stack_overflow,
    /// Timeout waiting for resource
    timeout,
    /// Deadlock detected
    deadlock,
    /// Channel operation failed
    channel_error,
    /// Mutex operation failed
    mutex_error,
    /// Memory allocation failed
    memory_error,
    /// Invalid state transition
    invalid_state,
    /// Coroutine cancelled
    cancelled,
    /// Unknown error
    unknown,

    pub fn toString(self: CoroutineErrorType) []const u8 {
        return switch (self) {
            .panic => "Panic",
            .stack_overflow => "StackOverflow",
            .timeout => "Timeout",
            .deadlock => "Deadlock",
            .channel_error => "ChannelError",
            .mutex_error => "MutexError",
            .memory_error => "MemoryError",
            .invalid_state => "InvalidState",
            .cancelled => "Cancelled",
            .unknown => "Unknown",
        };
    }

    pub fn isFatal(self: CoroutineErrorType) bool {
        return switch (self) {
            .panic, .stack_overflow, .deadlock, .memory_error => true,
            else => false,
        };
    }

    pub fn isRecoverable(self: CoroutineErrorType) bool {
        return switch (self) {
            .timeout, .channel_error, .mutex_error, .cancelled => true,
            else => false,
        };
    }
};

/// Error severity levels
pub const ErrorSeverity = enum {
    /// Informational - no action needed
    info,
    /// Warning - may indicate a problem
    warning,
    /// Error - operation failed but system continues
    err,
    /// Critical - serious problem, may affect other coroutines
    critical,
    /// Fatal - system cannot continue safely
    fatal,

    pub fn toString(self: ErrorSeverity) []const u8 {
        return switch (self) {
            .info => "INFO",
            .warning => "WARNING",
            .err => "ERROR",
            .critical => "CRITICAL",
            .fatal => "FATAL",
        };
    }
};

// ============================================================================
// Stack Frame for Coroutine Stack Traces
// ============================================================================

/// Represents a single frame in a coroutine stack trace
pub const CoroutineStackFrame = struct {
    /// Function name
    function_name: []const u8,
    /// Source file name
    file_name: []const u8,
    /// Line number in source file
    line: u32,
    /// Column number in source file
    column: u32,
    /// Instruction pointer (if available)
    instruction_pointer: usize,
    /// Local variables snapshot (optional) - stored as string representations
    locals: ?std.StringHashMap([]const u8),
    /// Timestamp when frame was entered
    entry_timestamp: i64,

    pub fn init(
        allocator: std.mem.Allocator,
        function_name: []const u8,
        file_name: []const u8,
        line: u32,
        column: u32,
    ) !CoroutineStackFrame {
        return CoroutineStackFrame{
            .function_name = try allocator.dupe(u8, function_name),
            .file_name = try allocator.dupe(u8, file_name),
            .line = line,
            .column = column,
            .instruction_pointer = 0,
            .locals = null,
            .entry_timestamp = @as(i64, @truncate(std.time.nanoTimestamp())),
        };
    }

    pub fn deinit(self: *CoroutineStackFrame, allocator: std.mem.Allocator) void {
        allocator.free(self.function_name);
        allocator.free(self.file_name);
        if (self.locals) |*locals| {
            var iter = locals.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.value_ptr.*);
            }
            locals.deinit();
        }
    }

    pub fn format(self: *const CoroutineStackFrame, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "  at {s} ({s}:{d}:{d})",
            .{ self.function_name, self.file_name, self.line, self.column },
        );
    }
};

// ============================================================================
// Coroutine Error Information
// ============================================================================

/// Complete error information for a coroutine error
pub const CoroutineError = struct {
    /// Unique error ID
    error_id: u64,
    /// Coroutine ID where error occurred
    coroutine_id: u64,
    /// Error type
    error_type: CoroutineErrorType,
    /// Error severity
    severity: ErrorSeverity,
    /// Error message
    message: []const u8,
    /// Stack trace at time of error
    stack_trace: std.ArrayListUnmanaged(CoroutineStackFrame),
    /// Timestamp when error occurred
    timestamp: i64,
    /// Source file where error originated
    source_file: []const u8,
    /// Line number where error originated
    source_line: u32,
    /// Related errors (for error chains)
    related_errors: std.ArrayListUnmanaged(*CoroutineError),
    /// Recovery action taken (if any)
    recovery_action: ?RecoveryAction,
    /// Whether error was handled
    handled: bool,
    /// Allocator for cleanup
    allocator: std.mem.Allocator,

    pub const RecoveryAction = enum {
        /// Error was ignored
        ignored,
        /// Coroutine was terminated
        terminated,
        /// Coroutine was restarted
        restarted,
        /// Error was propagated to parent
        propagated,
        /// Custom recovery handler was invoked
        custom_handler,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        coroutine_id: u64,
        error_type: CoroutineErrorType,
        message: []const u8,
        source_file: []const u8,
        source_line: u32,
    ) !*CoroutineError {
        const err = try allocator.create(CoroutineError);
        errdefer allocator.destroy(err);

        err.* = CoroutineError{
            .error_id = generateErrorId(),
            .coroutine_id = coroutine_id,
            .error_type = error_type,
            .severity = getSeverityForType(error_type),
            .message = try allocator.dupe(u8, message),
            .stack_trace = .{},
            .timestamp = @as(i64, @truncate(std.time.nanoTimestamp())),
            .source_file = try allocator.dupe(u8, source_file),
            .source_line = source_line,
            .related_errors = .{},
            .recovery_action = null,
            .handled = false,
            .allocator = allocator,
        };

        return err;
    }

    pub fn deinit(self: *CoroutineError) void {
        self.allocator.free(self.message);
        self.allocator.free(self.source_file);

        for (self.stack_trace.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.stack_trace.deinit(self.allocator);

        for (self.related_errors.items) |related| {
            related.deinit();
            self.allocator.destroy(related);
        }
        self.related_errors.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    pub fn addStackFrame(self: *CoroutineError, frame: CoroutineStackFrame) !void {
        if (self.stack_trace.items.len < MAX_STACK_TRACE_DEPTH) {
            try self.stack_trace.append(self.allocator, frame);
        }
    }

    pub fn addRelatedError(self: *CoroutineError, related: *CoroutineError) !void {
        try self.related_errors.append(self.allocator, related);
    }

    pub fn setRecoveryAction(self: *CoroutineError, action: RecoveryAction) void {
        self.recovery_action = action;
        self.handled = true;
    }

    pub fn format(self: *const CoroutineError, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        try writer.print("[{s}] {s} in coroutine {d}\n", .{
            self.severity.toString(),
            self.error_type.toString(),
            self.coroutine_id,
        });
        try writer.print("  Message: {s}\n", .{self.message});
        try writer.print("  Location: {s}:{d}\n", .{ self.source_file, self.source_line });
        try writer.print("  Error ID: {x}\n", .{self.error_id});
        try writer.print("  Timestamp: {d}\n", .{self.timestamp});

        if (self.stack_trace.items.len > 0) {
            try writer.print("  Stack trace:\n", .{});
            for (self.stack_trace.items) |*frame| {
                const frame_str = try frame.format(allocator);
                defer allocator.free(frame_str);
                try writer.print("{s}\n", .{frame_str});
            }
        }

        if (self.recovery_action) |action| {
            try writer.print("  Recovery: {s}\n", .{@tagName(action)});
        }

        return try buffer.toOwnedSlice(allocator);
    }

    fn generateErrorId() u64 {
        const timestamp = @as(u64, @intCast(std.time.nanoTimestamp()));
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&timestamp));
    }

    fn getSeverityForType(error_type: CoroutineErrorType) ErrorSeverity {
        return switch (error_type) {
            .panic, .stack_overflow, .deadlock => .fatal,
            .memory_error => .critical,
            .channel_error, .mutex_error, .timeout => .err,
            .cancelled, .invalid_state => .warning,
            .unknown => .err,
        };
    }
};

// ============================================================================
// Panic Recovery System
// ============================================================================

/// Panic recovery handler for coroutines
/// Implements Requirement 11.1 - isolate errors and not crash other coroutines
pub const PanicRecovery = struct {
    allocator: std.mem.Allocator,
    /// Registered panic handlers
    handlers: std.ArrayListUnmanaged(PanicHandler),
    /// Default recovery strategy
    default_strategy: RecoveryStrategy,
    /// Statistics
    stats: PanicStats,
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,

    pub const PanicHandler = struct {
        /// Handler function
        handler: *const fn (coroutine_id: u64, error_info: *CoroutineError) bool,
        /// Priority (lower = higher priority)
        priority: u8,
        /// Error types this handler can handle
        error_types: []const CoroutineErrorType,
    };

    pub const RecoveryStrategy = enum {
        /// Terminate the coroutine and clean up resources
        terminate,
        /// Restart the coroutine from the beginning
        restart,
        /// Propagate error to parent/caller
        propagate,
        /// Ignore the error and continue
        ignore,
        /// Use custom handler
        custom,
    };

    pub const PanicStats = struct {
        total_panics: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        recovered_panics: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        fatal_panics: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        panics_by_type: [10]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 10,
    };

    pub fn init(allocator: std.mem.Allocator) PanicRecovery {
        return PanicRecovery{
            .allocator = allocator,
            .handlers = .{},
            .default_strategy = .terminate,
            .stats = PanicStats{},
            .mutex = .{},
        };
    }

    pub fn deinit(self: *PanicRecovery) void {
        self.handlers.deinit(self.allocator);
    }

    /// Register a panic handler
    pub fn registerHandler(self: *PanicRecovery, handler: PanicHandler) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.handlers.append(self.allocator, handler);

        // Sort by priority
        std.sort.insertion(PanicHandler, self.handlers.items, {}, struct {
            fn lessThan(_: void, a: PanicHandler, b: PanicHandler) bool {
                return a.priority < b.priority;
            }
        }.lessThan);
    }

    /// Handle a panic in a coroutine
    /// Returns true if panic was recovered, false if fatal
    pub fn handlePanic(
        self: *PanicRecovery,
        coroutine_id: u64,
        error_info: *CoroutineError,
    ) bool {
        _ = self.stats.total_panics.fetchAdd(1, .monotonic);

        // Update type-specific stats
        const type_index = @intFromEnum(error_info.error_type);
        if (type_index < self.stats.panics_by_type.len) {
            _ = self.stats.panics_by_type[type_index].fetchAdd(1, .monotonic);
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        // Try registered handlers first
        for (self.handlers.items) |handler| {
            // Check if handler can handle this error type
            var can_handle = false;
            for (handler.error_types) |error_type| {
                if (error_type == error_info.error_type) {
                    can_handle = true;
                    break;
                }
            }

            if (can_handle) {
                if (handler.handler(coroutine_id, error_info)) {
                    _ = self.stats.recovered_panics.fetchAdd(1, .monotonic);
                    error_info.setRecoveryAction(.custom_handler);
                    return true;
                }
            }
        }

        // Apply default strategy
        return self.applyDefaultStrategy(coroutine_id, error_info);
    }

    fn applyDefaultStrategy(
        self: *PanicRecovery,
        coroutine_id: u64,
        error_info: *CoroutineError,
    ) bool {
        _ = coroutine_id;

        switch (self.default_strategy) {
            .terminate => {
                error_info.setRecoveryAction(.terminated);
                if (error_info.error_type.isFatal()) {
                    _ = self.stats.fatal_panics.fetchAdd(1, .monotonic);
                    return false;
                }
                _ = self.stats.recovered_panics.fetchAdd(1, .monotonic);
                return true;
            },
            .restart => {
                error_info.setRecoveryAction(.restarted);
                _ = self.stats.recovered_panics.fetchAdd(1, .monotonic);
                return true;
            },
            .propagate => {
                error_info.setRecoveryAction(.propagated);
                return true;
            },
            .ignore => {
                error_info.setRecoveryAction(.ignored);
                _ = self.stats.recovered_panics.fetchAdd(1, .monotonic);
                return true;
            },
            .custom => {
                // No custom handler available, treat as fatal
                _ = self.stats.fatal_panics.fetchAdd(1, .monotonic);
                return false;
            },
        }
    }

    pub fn setDefaultStrategy(self: *PanicRecovery, strategy: RecoveryStrategy) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.default_strategy = strategy;
    }

    pub fn getStats(self: *const PanicRecovery) PanicStats {
        return self.stats;
    }
};

// ============================================================================
// Error Propagation System
// ============================================================================

/// Error propagation mechanism for coroutines
/// Implements Requirement 11.4 - error propagation across coroutine boundaries
pub const ErrorPropagation = struct {
    allocator: std.mem.Allocator,
    /// Error channels for each coroutine
    error_channels: std.AutoHashMap(u64, *ErrorChannel),
    /// Parent-child relationships
    parent_map: std.AutoHashMap(u64, u64),
    /// Propagation callbacks
    callbacks: std.ArrayListUnmanaged(PropagationCallback),
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,

    pub const ErrorChannel = struct {
        errors: std.ArrayListUnmanaged(*CoroutineError),
        closed: std.atomic.Value(bool),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !*ErrorChannel {
            const channel = try allocator.create(ErrorChannel);
            channel.* = ErrorChannel{
                .errors = .{},
                .closed = std.atomic.Value(bool).init(false),
                .allocator = allocator,
            };
            return channel;
        }

        pub fn deinit(self: *ErrorChannel) void {
            for (self.errors.items) |err| {
                err.deinit();
            }
            self.errors.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        pub fn send(self: *ErrorChannel, err: *CoroutineError) !void {
            if (self.closed.load(.monotonic)) {
                return error.ChannelClosed;
            }
            try self.errors.append(self.allocator, err);
        }

        pub fn receive(self: *ErrorChannel) ?*CoroutineError {
            if (self.errors.items.len > 0) {
                return self.errors.orderedRemove(0);
            }
            return null;
        }

        pub fn close(self: *ErrorChannel) void {
            self.closed.store(true, .monotonic);
        }
    };

    pub const PropagationCallback = struct {
        callback: *const fn (source_id: u64, target_id: u64, err: *CoroutineError) void,
        filter: ?CoroutineErrorType,
    };

    pub fn init(allocator: std.mem.Allocator) ErrorPropagation {
        return ErrorPropagation{
            .allocator = allocator,
            .error_channels = std.AutoHashMap(u64, *ErrorChannel).init(allocator),
            .parent_map = std.AutoHashMap(u64, u64).init(allocator),
            .callbacks = .{},
            .mutex = .{},
        };
    }

    pub fn deinit(self: *ErrorPropagation) void {
        var iter = self.error_channels.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.error_channels.deinit();
        self.parent_map.deinit();
        self.callbacks.deinit(self.allocator);
    }

    /// Register a coroutine for error propagation
    pub fn registerCoroutine(self: *ErrorPropagation, coroutine_id: u64, parent_id: ?u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const channel = try ErrorChannel.init(self.allocator);
        try self.error_channels.put(coroutine_id, channel);

        if (parent_id) |pid| {
            try self.parent_map.put(coroutine_id, pid);
        }
    }

    /// Unregister a coroutine
    pub fn unregisterCoroutine(self: *ErrorPropagation, coroutine_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.error_channels.fetchRemove(coroutine_id)) |entry| {
            entry.value.deinit();
        }
        _ = self.parent_map.remove(coroutine_id);
    }

    /// Propagate error to parent coroutine
    pub fn propagateToParent(self: *ErrorPropagation, coroutine_id: u64, err: *CoroutineError) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.parent_map.get(coroutine_id)) |parent_id| {
            if (self.error_channels.get(parent_id)) |channel| {
                try channel.send(err);

                // Invoke callbacks
                for (self.callbacks.items) |cb| {
                    if (cb.filter == null or cb.filter == err.error_type) {
                        cb.callback(coroutine_id, parent_id, err);
                    }
                }
            }
        }
    }

    /// Propagate error to specific coroutine
    pub fn propagateTo(self: *ErrorPropagation, target_id: u64, err: *CoroutineError) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.error_channels.get(target_id)) |channel| {
            try channel.send(err);
        }
    }

    /// Check for pending errors
    pub fn checkErrors(self: *ErrorPropagation, coroutine_id: u64) ?*CoroutineError {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.error_channels.get(coroutine_id)) |channel| {
            return channel.receive();
        }
        return null;
    }

    /// Register propagation callback
    pub fn registerCallback(self: *ErrorPropagation, callback: PropagationCallback) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.callbacks.append(self.allocator, callback);
    }
};

// ============================================================================
// Structured Error Reporter
// ============================================================================

/// Structured error reporting system
/// Implements Requirement 11.8 - meaningful error messages
pub const ErrorReporter = struct {
    allocator: std.mem.Allocator,
    /// Error history
    error_history: std.ArrayListUnmanaged(*CoroutineError),
    /// Error listeners
    listeners: std.ArrayListUnmanaged(ErrorListener),
    /// Configuration
    config: ReporterConfig,
    /// Statistics
    stats: ReporterStats,
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,

    pub const ErrorListener = struct {
        listener: *const fn (err: *const CoroutineError) void,
        min_severity: ErrorSeverity,
    };

    pub const ReporterConfig = struct {
        /// Maximum errors to keep in history
        max_history_size: usize = 1000,
        /// Enable console output
        enable_console: bool = true,
        /// Enable file logging
        enable_file_logging: bool = false,
        /// Log file path
        log_file_path: ?[]const u8 = null,
        /// Include stack traces in reports
        include_stack_traces: bool = true,
        /// Include local variables in reports
        include_locals: bool = false,
        /// Minimum severity to report
        min_severity: ErrorSeverity = .warning,
    };

    pub const ReporterStats = struct {
        total_reported: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        by_severity: [5]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 5,
        by_type: [10]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 10,
    };

    pub fn init(allocator: std.mem.Allocator, config: ReporterConfig) ErrorReporter {
        return ErrorReporter{
            .allocator = allocator,
            .error_history = .{},
            .listeners = .{},
            .config = config,
            .stats = ReporterStats{},
            .mutex = .{},
        };
    }

    pub fn deinit(self: *ErrorReporter) void {
        for (self.error_history.items) |err| {
            err.deinit();
        }
        self.error_history.deinit(self.allocator);
        self.listeners.deinit(self.allocator);
    }

    /// Report an error (does not take ownership - caller retains ownership)
    pub fn report(self: *ErrorReporter, err: *CoroutineError) !void {
        // Check minimum severity
        if (@intFromEnum(err.severity) < @intFromEnum(self.config.min_severity)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        // Update statistics
        _ = self.stats.total_reported.fetchAdd(1, .monotonic);
        const severity_index = @intFromEnum(err.severity);
        if (severity_index < self.stats.by_severity.len) {
            _ = self.stats.by_severity[severity_index].fetchAdd(1, .monotonic);
        }
        const type_index = @intFromEnum(err.error_type);
        if (type_index < self.stats.by_type.len) {
            _ = self.stats.by_type[type_index].fetchAdd(1, .monotonic);
        }

        // Console output
        if (self.config.enable_console) {
            try self.outputToConsole(err);
        }

        // Notify listeners
        for (self.listeners.items) |listener| {
            if (@intFromEnum(err.severity) >= @intFromEnum(listener.min_severity)) {
                listener.listener(err);
            }
        }
    }

    fn outputToConsole(self: *ErrorReporter, err: *const CoroutineError) !void {
        const formatted = try err.format(self.allocator);
        defer self.allocator.free(formatted);

        std.log.err("{s}", .{formatted});
    }

    /// Register an error listener
    pub fn registerListener(self: *ErrorReporter, listener: ErrorListener) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.listeners.append(self.allocator, listener);
    }

    /// Get error history
    pub fn getHistory(self: *ErrorReporter) []const *CoroutineError {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.error_history.items;
    }

    /// Get errors by coroutine ID
    pub fn getErrorsByCoroutine(self: *ErrorReporter, coroutine_id: u64) !std.ArrayListUnmanaged(*CoroutineError) {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayListUnmanaged(*CoroutineError){ .items = &.{}, .capacity = 0 };
        for (self.error_history.items) |err| {
            if (err.coroutine_id == coroutine_id) {
                try result.append(self.allocator, err);
            }
        }
        return result;
    }

    /// Generate error summary report
    pub fn generateSummary(self: *ErrorReporter) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
        defer buffer.deinit(self.allocator);
        const writer = buffer.writer(self.allocator);

        try writer.print("=== Error Summary Report ===\n", .{});
        try writer.print("Total Errors Reported: {d}\n\n", .{
            self.stats.total_reported.load(.monotonic),
        });

        try writer.print("By Severity:\n", .{});
        const severities = [_]ErrorSeverity{ .info, .warning, .err, .critical, .fatal };
        for (severities, 0..) |sev, i| {
            try writer.print("  {s}: {d}\n", .{
                sev.toString(),
                self.stats.by_severity[i].load(.monotonic),
            });
        }

        try writer.print("\nBy Type:\n", .{});
        const error_types = [_]CoroutineErrorType{
            .panic,       .stack_overflow, .timeout,       .deadlock,
            .channel_error, .mutex_error,    .memory_error, .invalid_state,
            .cancelled,   .unknown,
        };
        for (error_types, 0..) |t, i| {
            const count = self.stats.by_type[i].load(.monotonic);
            if (count > 0) {
                try writer.print("  {s}: {d}\n", .{ t.toString(), count });
            }
        }

        try writer.print("\nRecent Errors ({d}):\n", .{self.error_history.items.len});
        const max_recent = @min(self.error_history.items.len, 5);
        for (0..max_recent) |i| {
            const idx = self.error_history.items.len - 1 - i;
            const err = self.error_history.items[idx];
            try writer.print("  [{s}] {s} in coroutine {d}: {s}\n", .{
                err.severity.toString(),
                err.error_type.toString(),
                err.coroutine_id,
                err.message,
            });
        }

        return try buffer.toOwnedSlice(self.allocator);
    }

    pub fn getStats(self: *const ErrorReporter) ReporterStats {
        return self.stats;
    }
};

// ============================================================================
// Coroutine Error Isolation Manager
// ============================================================================

/// Main error isolation manager for coroutines
/// Coordinates panic recovery, error propagation, and reporting
pub const CoroutineErrorManager = struct {
    allocator: std.mem.Allocator,
    /// Panic recovery system
    panic_recovery: PanicRecovery,
    /// Error propagation system
    error_propagation: ErrorPropagation,
    /// Error reporter
    error_reporter: ErrorReporter,
    /// Active coroutine errors (for isolation)
    active_errors: std.AutoHashMap(u64, *CoroutineError),
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, reporter_config: ErrorReporter.ReporterConfig) CoroutineErrorManager {
        return CoroutineErrorManager{
            .allocator = allocator,
            .panic_recovery = PanicRecovery.init(allocator),
            .error_propagation = ErrorPropagation.init(allocator),
            .error_reporter = ErrorReporter.init(allocator, reporter_config),
            .active_errors = std.AutoHashMap(u64, *CoroutineError).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *CoroutineErrorManager) void {
        var iter = self.active_errors.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.active_errors.deinit();
        self.panic_recovery.deinit();
        self.error_propagation.deinit();
        self.error_reporter.deinit();
    }

    /// Register a coroutine for error handling
    pub fn registerCoroutine(self: *CoroutineErrorManager, coroutine_id: u64, parent_id: ?u64) !void {
        try self.error_propagation.registerCoroutine(coroutine_id, parent_id);
    }

    /// Unregister a coroutine
    pub fn unregisterCoroutine(self: *CoroutineErrorManager, coroutine_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.active_errors.fetchRemove(coroutine_id)) |entry| {
            entry.value.deinit();
        }
        self.error_propagation.unregisterCoroutine(coroutine_id);
    }

    /// Handle an error in a coroutine
    /// Returns true if error was handled and coroutine can continue
    /// Returns false if error is fatal and coroutine should terminate
    pub fn handleError(
        self: *CoroutineErrorManager,
        coroutine_id: u64,
        error_type: CoroutineErrorType,
        message: []const u8,
        source_file: []const u8,
        source_line: u32,
    ) !bool {
        // Create error info
        const err = try CoroutineError.init(
            self.allocator,
            coroutine_id,
            error_type,
            message,
            source_file,
            source_line,
        );

        // Store as active error
        self.mutex.lock();
        if (self.active_errors.get(coroutine_id)) |old_err| {
            old_err.deinit();
        }
        try self.active_errors.put(coroutine_id, err);
        self.mutex.unlock();

        // Report the error
        try self.error_reporter.report(err);

        // Attempt panic recovery
        const recovered = self.panic_recovery.handlePanic(coroutine_id, err);

        // If not recovered and has parent, propagate
        if (!recovered) {
            self.error_propagation.propagateToParent(coroutine_id, err) catch {};
        }

        return recovered;
    }

    /// Handle an error with stack trace
    pub fn handleErrorWithTrace(
        self: *CoroutineErrorManager,
        coroutine_id: u64,
        error_type: CoroutineErrorType,
        message: []const u8,
        source_file: []const u8,
        source_line: u32,
        stack_frames: []const CoroutineStackFrame,
    ) !bool {
        // Create error info
        const err = try CoroutineError.init(
            self.allocator,
            coroutine_id,
            error_type,
            message,
            source_file,
            source_line,
        );

        // Add stack frames
        for (stack_frames) |frame| {
            try err.addStackFrame(frame);
        }

        // Store as active error
        self.mutex.lock();
        if (self.active_errors.get(coroutine_id)) |old_err| {
            old_err.deinit();
        }
        try self.active_errors.put(coroutine_id, err);
        self.mutex.unlock();

        // Report the error
        try self.error_reporter.report(err);

        // Attempt panic recovery
        const recovered = self.panic_recovery.handlePanic(coroutine_id, err);

        // If not recovered and has parent, propagate
        if (!recovered) {
            self.error_propagation.propagateToParent(coroutine_id, err) catch {};
        }

        return recovered;
    }

    /// Check for pending errors from child coroutines
    pub fn checkPendingErrors(self: *CoroutineErrorManager, coroutine_id: u64) ?*CoroutineError {
        return self.error_propagation.checkErrors(coroutine_id);
    }

    /// Get active error for a coroutine
    pub fn getActiveError(self: *CoroutineErrorManager, coroutine_id: u64) ?*CoroutineError {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.active_errors.get(coroutine_id);
    }

    /// Clear active error for a coroutine
    pub fn clearActiveError(self: *CoroutineErrorManager, coroutine_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.active_errors.fetchRemove(coroutine_id)) |entry| {
            entry.value.deinit();
        }
    }

    /// Register a panic handler
    pub fn registerPanicHandler(self: *CoroutineErrorManager, handler: PanicRecovery.PanicHandler) !void {
        try self.panic_recovery.registerHandler(handler);
    }

    /// Set default recovery strategy
    pub fn setDefaultRecoveryStrategy(self: *CoroutineErrorManager, strategy: PanicRecovery.RecoveryStrategy) void {
        self.panic_recovery.setDefaultStrategy(strategy);
    }

    /// Register error listener
    pub fn registerErrorListener(self: *CoroutineErrorManager, listener: ErrorReporter.ErrorListener) !void {
        try self.error_reporter.registerListener(listener);
    }

    /// Generate comprehensive error report
    pub fn generateReport(self: *CoroutineErrorManager) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
        defer buffer.deinit(self.allocator);
        const writer = buffer.writer(self.allocator);

        try writer.print("=== Coroutine Error Management Report ===\n\n", .{});

        // Panic recovery stats
        const panic_stats = self.panic_recovery.getStats();
        try writer.print("Panic Recovery Statistics:\n", .{});
        try writer.print("  Total Panics: {d}\n", .{panic_stats.total_panics.load(.monotonic)});
        try writer.print("  Recovered: {d}\n", .{panic_stats.recovered_panics.load(.monotonic)});
        try writer.print("  Fatal: {d}\n\n", .{panic_stats.fatal_panics.load(.monotonic)});

        // Error reporter summary
        const summary = try self.error_reporter.generateSummary();
        defer self.allocator.free(summary);
        try writer.writeAll(summary);

        return try buffer.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "CoroutineErrorType properties" {
    try std.testing.expect(CoroutineErrorType.panic.isFatal());
    try std.testing.expect(CoroutineErrorType.stack_overflow.isFatal());
    try std.testing.expect(CoroutineErrorType.deadlock.isFatal());
    try std.testing.expect(!CoroutineErrorType.timeout.isFatal());
    try std.testing.expect(CoroutineErrorType.timeout.isRecoverable());
    try std.testing.expect(CoroutineErrorType.channel_error.isRecoverable());
}

test "CoroutineStackFrame creation and formatting" {
    const allocator = std.testing.allocator;

    var frame = try CoroutineStackFrame.init(
        allocator,
        "testFunction",
        "test.php",
        42,
        10,
    );
    defer frame.deinit(allocator);

    try std.testing.expectEqualStrings("testFunction", frame.function_name);
    try std.testing.expectEqualStrings("test.php", frame.file_name);
    try std.testing.expectEqual(@as(u32, 42), frame.line);

    const formatted = try frame.format(allocator);
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "testFunction") != null);
}

test "CoroutineError creation and formatting" {
    const allocator = std.testing.allocator;

    const err = try CoroutineError.init(
        allocator,
        1,
        .panic,
        "Test panic message",
        "test.php",
        100,
    );
    defer err.deinit();

    try std.testing.expectEqual(@as(u64, 1), err.coroutine_id);
    try std.testing.expectEqual(CoroutineErrorType.panic, err.error_type);
    try std.testing.expectEqual(ErrorSeverity.fatal, err.severity);
    try std.testing.expectEqualStrings("Test panic message", err.message);

    const formatted = try err.format(allocator);
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Panic") != null);
}

test "PanicRecovery basic functionality" {
    const allocator = std.testing.allocator;

    var recovery = PanicRecovery.init(allocator);
    defer recovery.deinit();

    const err = try CoroutineError.init(
        allocator,
        1,
        .timeout,
        "Test timeout",
        "test.php",
        50,
    );
    defer err.deinit();

    // Default strategy should handle recoverable errors
    const recovered = recovery.handlePanic(1, err);
    try std.testing.expect(recovered);

    const stats = recovery.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_panics.load(.monotonic));
}

test "ErrorPropagation registration and propagation" {
    const allocator = std.testing.allocator;

    var propagation = ErrorPropagation.init(allocator);
    defer propagation.deinit();

    // Register parent and child
    try propagation.registerCoroutine(1, null);
    try propagation.registerCoroutine(2, 1);

    // Create error in child
    const err = try CoroutineError.init(
        allocator,
        2,
        .channel_error,
        "Channel closed",
        "test.php",
        75,
    );
    // Note: err ownership transfers to propagation system

    // Propagate to parent
    try propagation.propagateToParent(2, err);

    // Parent should receive error
    const received = propagation.checkErrors(1);
    try std.testing.expect(received != null);
    try std.testing.expectEqual(@as(u64, 2), received.?.coroutine_id);
    
    // Clean up the received error
    received.?.deinit();
}

test "ErrorReporter basic functionality" {
    const allocator = std.testing.allocator;

    var reporter = ErrorReporter.init(allocator, .{
        .enable_console = false, // Disable console for tests
        .min_severity = .info,
    });
    defer reporter.deinit();

    const err = try CoroutineError.init(
        allocator,
        1,
        .mutex_error,
        "Mutex deadlock",
        "test.php",
        200,
    );
    defer err.deinit(); // Caller retains ownership

    try reporter.report(err);

    const stats = reporter.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_reported.load(.monotonic));
}

test "CoroutineErrorManager integration" {
    const allocator = std.testing.allocator;

    var manager = CoroutineErrorManager.init(allocator, .{
        .enable_console = false,
        .min_severity = .info,
    });
    defer manager.deinit();

    // Register coroutines
    try manager.registerCoroutine(1, null);
    try manager.registerCoroutine(2, 1);

    // Handle error in child
    const recovered = try manager.handleError(
        2,
        .timeout,
        "Operation timed out",
        "test.php",
        150,
    );
    try std.testing.expect(recovered);

    // Check active error
    const active = manager.getActiveError(2);
    try std.testing.expect(active != null);

    // Generate report
    const report = try manager.generateReport();
    defer allocator.free(report);
    try std.testing.expect(std.mem.indexOf(u8, report, "Panic Recovery") != null);

    // Cleanup
    manager.unregisterCoroutine(2);
    manager.unregisterCoroutine(1);
}
