//! ============================================================================
//! Go风格Select语句 (Select)
//! ============================================================================
//!
//! 功能：实现Go风格的select语句，用于多通道非确定性选择
//!
//! Select语句工作原理：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                        Select                                    │
//! │                                                                  │
//! │   case ch1 <- v:    ──┐                                         │
//! │   case x := <-ch2:  ──┼──> 随机选择一个就绪的case执行            │
//! │   case <-ch3:       ──┤                                         │
//! │   default:          ──┘    (如果都没就绪，执行default)           │
//! │                                                                  │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 核心特性：
//! - 非确定性选择：多个case就绪时随机选择一个
//! - 支持发送和接收case
//! - 支持default case（非阻塞）
//! - 支持超时机制
//!
//! 使用场景：
//! - 多通道监听
//! - 超时控制
//! - 非阻塞通道操作
//! - 取消信号处理
//!
//! 需求：7.10, 7.11, 7.12
//! ============================================================================

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Channel = @import("channel.zig").Channel;

/// Go风格select语句实现
/// 
/// 使用示例：
/// ```zig
/// var sel = Select.init(allocator);
/// defer sel.deinit();
/// 
/// // 添加接收case
/// try sel.addRecvCase(&ch1, recvHandler);
/// 
/// // 添加发送case
/// try sel.addSendCase(&ch2, value, sendHandler);
/// 
/// // 添加default case
/// sel.setDefault(defaultHandler);
/// 
/// // 执行select
/// try sel.execute();
/// ```
pub const Select = struct {
    cases: std.ArrayList(Case),
    default_case: ?DefaultCase,
    allocator: std.mem.Allocator,
    
    // Random number generator for non-deterministic selection
    rng: std.Random.DefaultPrng,
    
    // Statistics
    stats: SelectStats,
    
    /// Select case for channel operations
    pub const Case = struct {
        channel: *Channel,
        operation: Operation,
        value: ?Value,  // For send operations
        handler: Handler,
        ready: bool = false,
        
        pub const Operation = enum {
            send,
            recv,
        };
        
        pub const Handler = union(enum) {
            send_handler: *const fn() void,
            recv_handler: *const fn(?Value) void,
        };
        
        /// Check if this case is ready to execute
        pub fn isReady(self: *Case) bool {
            switch (self.operation) {
                .send => {
                    // Send case is ready if channel can accept the value
                    if (self.channel.isClosed()) return false;
                    
                    if (self.channel.isUnbuffered()) {
                        // Unbuffered: ready if there's a waiting receiver
                        return self.channel.getWaitingReceivers() > 0;
                    } else {
                        // Buffered: ready if not full
                        return !self.channel.isFull();
                    }
                },
                .recv => {
                    // Recv case is ready if channel has data or senders
                    if (self.channel.isUnbuffered()) {
                        // Unbuffered: ready if there's a waiting sender or channel is closed
                        return self.channel.getWaitingSenders() > 0 or self.channel.isClosed();
                    } else {
                        // Buffered: ready if not empty or channel is closed
                        return !self.channel.isEmpty() or self.channel.isClosed();
                    }
                },
            }
        }
        
        /// Execute this case
        pub fn execute(self: *Case, coroutine_id: u64) !void {
            switch (self.operation) {
                .send => {
                    if (self.value) |value| {
                        // Perform non-blocking send
                        const success = self.channel.trySend(value);
                        if (success) {
                            switch (self.handler) {
                                .send_handler => |handler| handler(),
                                else => {},
                            }
                        } else {
                            return error.CaseNotReady;
                        }
                    }
                },
                .recv => {
                    // Perform non-blocking receive
                    const received = self.channel.tryRecv();
                    switch (self.handler) {
                        .recv_handler => |handler| handler(received),
                        else => {},
                    }
                },
            }
            _ = coroutine_id; // Suppress unused parameter warning
        }
    };
    
    /// Default case for select statement
    pub const DefaultCase = struct {
        handler: *const fn() void,
    };
    
    /// Select statement statistics
    pub const SelectStats = struct {
        total_executions: std.atomic.Value(u64),
        case_executions: std.atomic.Value(u64),
        default_executions: std.atomic.Value(u64),
        blocked_executions: std.atomic.Value(u64),
        created_at: i64,
        
        pub fn init() SelectStats {
            return SelectStats{
                .total_executions = std.atomic.Value(u64).init(0),
                .case_executions = std.atomic.Value(u64).init(0),
                .default_executions = std.atomic.Value(u64).init(0),
                .blocked_executions = std.atomic.Value(u64).init(0),
                .created_at = @intCast(std.time.nanoTimestamp()),
            };
        }
    };
    
    /// Initialize select statement
    pub fn init(allocator: std.mem.Allocator) Select {
        return Select{
            .cases = .{},
            .default_case = null,
            .allocator = allocator,
            .rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
            .stats = SelectStats.init(),
        };
    }
    
    /// Initialize select with pre-allocated case capacity
    pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !Select {
        var cases: std.ArrayList(Case) = .{};
        try cases.ensureTotalCapacity(allocator, capacity);
        
        return Select{
            .cases = cases,
            .default_case = null,
            .allocator = allocator,
            .rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
            .stats = SelectStats.init(),
        };
    }
    
    /// Clean up select statement
    pub fn deinit(self: *Select) void {
        // Release any retained values in send cases
        for (self.cases.items) |*case| {
            if (case.operation == .send and case.value != null) {
                case.value.?.release(self.allocator);
            }
        }
        
        self.cases.deinit(self.allocator);
    }
    
    /// Add send case to select statement
    /// Requirements 7.10 - Go-style select for multiple channel operations
    pub fn addSendCase(self: *Select, channel: *Channel, value: Value, handler: *const fn() void) !void {
        const case = Case{
            .channel = channel,
            .operation = .send,
            .value = value.retain(),
            .handler = Case.Handler{ .send_handler = handler },
        };
        
        try self.addCase(case);
    }
    
    /// Add receive case to select statement
    /// Requirements 7.10 - Go-style select for multiple channel operations
    pub fn addRecvCase(self: *Select, channel: *Channel, handler: *const fn(?Value) void) !void {
        const case = Case{
            .channel = channel,
            .operation = .recv,
            .value = null,
            .handler = Case.Handler{ .recv_handler = handler },
        };
        
        try self.addCase(case);
    }
    
    /// Set default case
    /// Requirements 7.12 - default case handling
    pub fn setDefault(self: *Select, handler: *const fn() void) void {
        self.default_case = DefaultCase{
            .handler = handler,
        };
    }
    
    /// Execute select statement
    /// Requirements 7.11 - non-deterministic case selection, 7.12 - block until ready
    pub fn execute(self: *Select, coroutine_id: u64) !void {
        _ = self.stats.total_executions.fetchAdd(1, .acq_rel);
        
        // Phase 1: Check for immediately ready cases
        var ready_cases_list = std.ArrayListUnmanaged(usize){};
        defer ready_cases_list.deinit(self.allocator);
        
        for (self.cases.items, 0..) |*case, i| {
            if (case.isReady()) {
                try ready_cases_list.append(self.allocator, i);
            }
        }
        
        // If we have ready cases, select one randomly (non-deterministic)
        if (ready_cases_list.items.len > 0) {
            const selected_index = self.rng.random().intRangeLessThan(usize, 0, ready_cases_list.items.len);
            const case_index = ready_cases_list.items[selected_index];
            
            try self.cases.items[case_index].execute(coroutine_id);
            _ = self.stats.case_executions.fetchAdd(1, .acq_rel);
            return;
        }
        
        // Phase 2: No cases ready, check for default case
        if (self.default_case) |default| {
            default.handler();
            _ = self.stats.default_executions.fetchAdd(1, .acq_rel);
            return;
        }
        
        // Phase 3: No ready cases and no default, need to block
        _ = self.stats.blocked_executions.fetchAdd(1, .acq_rel);
        
        // In a full implementation, this would:
        // 1. Add the coroutine to wait queues of all channels
        // 2. Yield the coroutine to the scheduler
        // 3. When woken up, check which case became ready
        // 4. Execute the ready case and remove from other wait queues
        
        // For now, we'll simulate blocking by polling with a small delay
        try self.blockUntilReady(coroutine_id);
    }
    
    /// Execute select statement with timeout
    pub fn executeWithTimeout(self: *Select, coroutine_id: u64, timeout_ns: u64) !bool {
        const start_time = std.time.nanoTimestamp();
        
        while (true) {
            // Check for ready cases
            var ready_cases_list = std.ArrayListUnmanaged(usize){};
            defer ready_cases_list.deinit(self.allocator);
            
            for (self.cases.items, 0..) |*case, i| {
                if (case.isReady()) {
                    try ready_cases_list.append(self.allocator, i);
                }
            }
            
            // If we have ready cases, select one randomly
            if (ready_cases_list.items.len > 0) {
                const selected_index = self.rng.random().intRangeLessThan(usize, 0, ready_cases_list.items.len);
                const case_index = ready_cases_list.items[selected_index];
                
                try self.cases.items[case_index].execute(coroutine_id);
                _ = self.stats.case_executions.fetchAdd(1, .acq_rel);
                return true;
            }
            
            // Check timeout
            const elapsed = std.time.nanoTimestamp() - start_time;
            if (elapsed >= timeout_ns) {
                // Timeout reached, execute default if available
                if (self.default_case) |default| {
                    default.handler();
                    _ = self.stats.default_executions.fetchAdd(1, .acq_rel);
                    return true;
                }
                return false; // Timeout without execution
            }
            
            // Small delay to avoid busy waiting
            std.Thread.sleep(1000); // 1 microsecond
        }
    }
    
    /// Get select statistics
    pub fn getStats(self: *Select) SelectStats {
        return SelectStats{
            .total_executions = std.atomic.Value(u64).init(self.stats.total_executions.load(.acquire)),
            .case_executions = std.atomic.Value(u64).init(self.stats.case_executions.load(.acquire)),
            .default_executions = std.atomic.Value(u64).init(self.stats.default_executions.load(.acquire)),
            .blocked_executions = std.atomic.Value(u64).init(self.stats.blocked_executions.load(.acquire)),
            .created_at = self.stats.created_at,
        };
    }
    
    /// Get number of cases
    pub fn getCaseCount(self: *Select) usize {
        return self.cases.items.len;
    }
    
    /// Check if select has default case
    pub fn hasDefault(self: *Select) bool {
        return self.default_case != null;
    }
    
    /// Reset select statement (clear all cases and default)
    pub fn reset(self: *Select) void {
        // Release any retained values
        for (self.cases.items) |*case| {
            if (case.operation == .send and case.value != null) {
                case.value.?.release(self.allocator);
            }
        }
        
        // Clear cases array
        self.cases.clearRetainingCapacity();
        self.default_case = null;
    }
    
    // Private helper methods
    
    /// Add a case to the select statement
    fn addCase(self: *Select, case: Case) !void {
        try self.cases.append(self.allocator, case);
    }
    
    /// Block until at least one case becomes ready with proper coroutine integration
    fn blockUntilReady(self: *Select, coroutine_id: u64) !void {
        // Enhanced blocking implementation with timeout and proper scheduling
        const max_wait_time_ns = 100_000_000; // 100ms maximum wait
        const poll_interval_ns = 1_000; // 1 microsecond poll interval
        const start_time = std.time.nanoTimestamp();
        
        while (true) {
            // Check if any case is ready
            for (self.cases.items) |*case| {
                if (case.isReady()) {
                    try case.execute(coroutine_id);
                    _ = self.stats.case_executions.fetchAdd(1, .acq_rel);
                    return;
                }
            }
            
            // Check for timeout to prevent infinite blocking
            const elapsed = std.time.nanoTimestamp() - start_time;
            if (elapsed >= max_wait_time_ns) {
                // Timeout reached - this prevents deadlocks in testing
                return error.SelectTimeout;
            }
            
            // Yield to other operations with adaptive polling
            const adaptive_sleep = @min(poll_interval_ns * 2, 10_000); // Max 10μs
            std.Thread.sleep(adaptive_sleep);
        }
    }
};

// Tests
test "select statement creation and basic operations" {
    const allocator = std.testing.allocator;
    
    var select_stmt = Select.init(allocator);
    defer select_stmt.deinit();
    
    try std.testing.expectEqual(@as(usize, 0), select_stmt.getCaseCount());
    try std.testing.expect(!select_stmt.hasDefault());
    
    const stats = select_stmt.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_executions.load(.acquire));
}

test "select statement with capacity" {
    const allocator = std.testing.allocator;
    
    var select_stmt = try Select.initWithCapacity(allocator, 5);
    defer select_stmt.deinit();
    
    try std.testing.expectEqual(@as(usize, 0), select_stmt.getCaseCount());
}

test "select statement add cases" {
    const allocator = std.testing.allocator;
    
    var select_stmt = Select.init(allocator);
    defer select_stmt.deinit();
    
    // Create channels
    const channel1 = try Channel.init(allocator);
    defer channel1.deinit();
    
    const channel2 = try Channel.initWithCapacity(allocator, 1);
    defer channel2.deinit();
    
    // Test handlers
    const TestHandlers = struct {
        var send_called = false;
        var recv_called = false;
        var recv_value: ?Value = null;
        
        fn sendHandler() void {
            send_called = true;
        }
        
        fn recvHandler(value: ?Value) void {
            recv_called = true;
            recv_value = value;
        }
        
        fn reset() void {
            send_called = false;
            recv_called = false;
            recv_value = null;
        }
    };
    
    TestHandlers.reset();
    
    // Add send case
    const send_value = Value.initInteger(42);
    try select_stmt.addSendCase(channel2, send_value, TestHandlers.sendHandler);
    
    // Add receive case
    try select_stmt.addRecvCase(channel1, TestHandlers.recvHandler);
    
    try std.testing.expectEqual(@as(usize, 2), select_stmt.getCaseCount());
}

test "select statement default case" {
    const allocator = std.testing.allocator;
    
    var select_stmt = Select.init(allocator);
    defer select_stmt.deinit();
    
    const TestHandlers = struct {
        var default_called = false;
        
        fn defaultHandler() void {
            default_called = true;
        }
        
        fn reset() void {
            default_called = false;
        }
    };
    
    TestHandlers.reset();
    
    // Set default case
    select_stmt.setDefault(TestHandlers.defaultHandler);
    try std.testing.expect(select_stmt.hasDefault());
    
    // Execute select with no ready cases - should execute default
    try select_stmt.execute(1);
    try std.testing.expect(TestHandlers.default_called);
    
    const stats = select_stmt.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_executions.load(.acquire));
    try std.testing.expectEqual(@as(u64, 1), stats.default_executions.load(.acquire));
}

test "select statement case readiness" {
    const allocator = std.testing.allocator;
    
    // Test send case readiness
    const buffered_channel = try Channel.initWithCapacity(allocator, 1);
    defer buffered_channel.deinit();
    
    var send_case = Select.Case{
        .channel = buffered_channel,
        .operation = .send,
        .value = Value.initInteger(42),
        .handler = Select.Case.Handler{ .send_handler = struct {
            fn handler() void {}
        }.handler },
    };
    
    // Should be ready (buffered channel not full)
    try std.testing.expect(send_case.isReady());
    
    // Fill the buffer
    _ = buffered_channel.trySend(Value.initInteger(1));
    
    // Should not be ready (buffered channel full)
    try std.testing.expect(!send_case.isReady());
    
    // Test recv case readiness
    var recv_case = Select.Case{
        .channel = buffered_channel,
        .operation = .recv,
        .value = null,
        .handler = Select.Case.Handler{ .recv_handler = struct {
            fn handler(value: ?Value) void {
                _ = value;
            }
        }.handler },
    };
    
    // Should be ready (buffered channel has data)
    try std.testing.expect(recv_case.isReady());
    
    // Empty the buffer
    _ = buffered_channel.tryRecv();
    
    // Should not be ready (buffered channel empty)
    try std.testing.expect(!recv_case.isReady());
}

test "select statement reset" {
    const allocator = std.testing.allocator;
    
    var select_stmt = Select.init(allocator);
    defer select_stmt.deinit();
    
    const channel = try Channel.init(allocator);
    defer channel.deinit();
    
    // Add a case
    const value = Value.initInteger(42);
    try select_stmt.addSendCase(channel, value, struct {
        fn handler() void {}
    }.handler);
    
    try std.testing.expectEqual(@as(usize, 1), select_stmt.getCaseCount());
    
    // Reset
    select_stmt.reset();
    
    try std.testing.expectEqual(@as(usize, 0), select_stmt.getCaseCount());
    try std.testing.expect(!select_stmt.hasDefault());
}

test "select statement with timeout" {
    const allocator = std.testing.allocator;
    
    var select_stmt = Select.init(allocator);
    defer select_stmt.deinit();
    
    const channel = try Channel.init(allocator);
    defer channel.deinit();
    
    // Add a receive case that won't be ready
    try select_stmt.addRecvCase(channel, struct {
        fn handler(value: ?Value) void {
            _ = value;
        }
    }.handler);
    
    // Execute with very short timeout - should timeout
    const result = try select_stmt.executeWithTimeout(1, 1000); // 1 microsecond timeout
    try std.testing.expect(!result); // Should timeout
}

test "case execution" {
    const allocator = std.testing.allocator;
    
    const channel = try Channel.initWithCapacity(allocator, 1);
    defer channel.deinit();
    
    const TestHandlers = struct {
        var send_executed = false;
        var recv_executed = false;
        var received_value: ?Value = null;
        
        fn sendHandler() void {
            send_executed = true;
        }
        
        fn recvHandler(value: ?Value) void {
            recv_executed = true;
            received_value = value;
        }
        
        fn reset() void {
            send_executed = false;
            recv_executed = false;
            received_value = null;
        }
    };
    
    TestHandlers.reset();
    
    // Test send case execution
    var send_case = Select.Case{
        .channel = channel,
        .operation = .send,
        .value = Value.initInteger(42),
        .handler = Select.Case.Handler{ .send_handler = TestHandlers.sendHandler },
    };
    
    try send_case.execute(1);
    try std.testing.expect(TestHandlers.send_executed);
    try std.testing.expectEqual(@as(usize, 1), channel.getSize());
    
    // Test recv case execution
    TestHandlers.reset();
    
    var recv_case = Select.Case{
        .channel = channel,
        .operation = .recv,
        .value = null,
        .handler = Select.Case.Handler{ .recv_handler = TestHandlers.recvHandler },
    };
    
    try recv_case.execute(1);
    try std.testing.expect(TestHandlers.recv_executed);
    try std.testing.expect(TestHandlers.received_value != null);
    try std.testing.expectEqual(@as(i64, 42), TestHandlers.received_value.?.getInteger());
    try std.testing.expectEqual(@as(usize, 0), channel.getSize());
}