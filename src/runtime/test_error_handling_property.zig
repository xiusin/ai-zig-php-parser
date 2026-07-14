//! Property-Based Tests for Coroutine Error Handling
//!
//! **Feature: php-builtin-functions-concurrency**
//! **Property 23: Error isolation**
//! **Property 24: Graceful error handling**
//! **Validates: Requirements 11.1, 11.8**
//!
//! Property 23: Error isolation
//! *For any* coroutine that panics or throws an exception, other coroutines
//! should continue executing normally.
//!
//! Property 24: Graceful error handling
//! *For any* invalid input to builtin functions, appropriate exceptions should
//! be thrown with meaningful error messages.

const std = @import("std");
const testing = std.testing;
const error_handling = @import("coroutine_error_handling.zig");
const debugging = @import("coroutine_debugging.zig");

const CoroutineErrorType = error_handling.CoroutineErrorType;
const ErrorSeverity = error_handling.ErrorSeverity;
const CoroutineError = error_handling.CoroutineError;
const CoroutineStackFrame = error_handling.CoroutineStackFrame;
const PanicRecovery = error_handling.PanicRecovery;
const ErrorPropagation = error_handling.ErrorPropagation;
const ErrorReporter = error_handling.ErrorReporter;
const CoroutineErrorManager = error_handling.CoroutineErrorManager;
const DeadlockDetector = debugging.DeadlockDetector;
const CoroutinePerformanceMonitor = debugging.CoroutinePerformanceMonitor;
const CoroutineDebugCoordinator = debugging.CoroutineDebugCoordinator;

/// Random number generator for property tests
const Rng = std.Random.DefaultPrng;

/// Test configuration - minimum 100 iterations per property test
const TEST_ITERATIONS: usize = 100;

/// Maximum coroutine ID for testing
const MAX_COROUTINE_ID: u64 = 10000;

/// Maximum message length for testing
const MAX_MESSAGE_LENGTH: usize = 256;

// ============================================================================
// Random Data Generators
// ============================================================================

/// Generate a random coroutine ID
fn randomCoroutineId(rng: *Rng) u64 {
    return rng.random().intRangeAtMost(u64, 1, MAX_COROUTINE_ID);
}

/// Generate a random error type
fn randomErrorType(rng: *Rng) CoroutineErrorType {
    const error_types = [_]CoroutineErrorType{
        .panic,
        .stack_overflow,
        .timeout,
        .deadlock,
        .channel_error,
        .mutex_error,
        .memory_error,
        .invalid_state,
        .cancelled,
        .unknown,
    };
    return error_types[rng.random().intRangeAtMost(usize, 0, error_types.len - 1)];
}

/// Generate a random recoverable error type
fn randomRecoverableErrorType(rng: *Rng) CoroutineErrorType {
    const error_types = [_]CoroutineErrorType{
        .timeout,
        .channel_error,
        .mutex_error,
        .cancelled,
    };
    return error_types[rng.random().intRangeAtMost(usize, 0, error_types.len - 1)];
}

/// Generate a random fatal error type
fn randomFatalErrorType(rng: *Rng) CoroutineErrorType {
    const error_types = [_]CoroutineErrorType{
        .panic,
        .stack_overflow,
        .deadlock,
        .memory_error,
    };
    return error_types[rng.random().intRangeAtMost(usize, 0, error_types.len - 1)];
}

/// Generate a random error message
fn randomErrorMessage(rng: *Rng, allocator: std.mem.Allocator) ![]u8 {
    const prefixes = [_][]const u8{
        "Error occurred: ",
        "Failed to execute: ",
        "Operation failed: ",
        "Exception in: ",
        "Panic at: ",
    };
    const suffixes = [_][]const u8{
        "function call",
        "memory allocation",
        "channel operation",
        "mutex lock",
        "coroutine execution",
    };

    const prefix = prefixes[rng.random().intRangeAtMost(usize, 0, prefixes.len - 1)];
    const suffix = suffixes[rng.random().intRangeAtMost(usize, 0, suffixes.len - 1)];

    return std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, suffix });
}

/// Generate a random file name
fn randomFileName(rng: *Rng, allocator: std.mem.Allocator) ![]u8 {
    const names = [_][]const u8{
        "main.php",
        "test.php",
        "handler.php",
        "service.php",
        "controller.php",
    };
    const name = names[rng.random().intRangeAtMost(usize, 0, names.len - 1)];
    return allocator.dupe(u8, name);
}

/// Generate a random line number
fn randomLineNumber(rng: *Rng) u32 {
    return rng.random().intRangeAtMost(u32, 1, 1000);
}

/// Generate a random resource type for deadlock detection
fn randomResourceType(rng: *Rng) DeadlockDetector.ResourceType {
    const types = [_]DeadlockDetector.ResourceType{
        .mutex,
        .rwmutex_read,
        .rwmutex_write,
        .channel_send,
        .channel_recv,
        .waitgroup,
        .other,
    };
    return types[rng.random().intRangeAtMost(usize, 0, types.len - 1)];
}

// ============================================================================
// Property 23: Error Isolation Tests
// ============================================================================

// Property 23.1: Error in one coroutine does not affect others
// *For any* coroutine that experiences an error, other registered coroutines
// should remain unaffected and continue to function normally.
test "Property 23.1: Error isolation - errors don't affect other coroutines" {
    // Feature: php-builtin-functions-concurrency, Property 23: Error isolation
    // Validates: Requirements 11.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var manager = CoroutineErrorManager.init(allocator, .{
        .enable_console = false,
        .min_severity = .info,
    });
    defer manager.deinit();

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        // Register multiple coroutines
        const num_coroutines = rng.random().intRangeAtMost(usize, 3, 10);
        var coroutine_ids = std.ArrayListUnmanaged(u64){ .items = &.{}, .capacity = 0 };
        defer coroutine_ids.deinit(allocator);

        for (0..num_coroutines) |j| {
            const coro_id = @as(u64, @intCast(i * 100 + j + 1));
            try manager.registerCoroutine(coro_id, null);
            try coroutine_ids.append(allocator, coro_id);
        }

        // Pick a random coroutine to have an error
        const error_coro_idx = rng.random().intRangeAtMost(usize, 0, num_coroutines - 1);
        const error_coro_id = coroutine_ids.items[error_coro_idx];

        // Generate random error
        const error_type = randomErrorType(&rng);
        const message = try randomErrorMessage(&rng, allocator);
        defer allocator.free(message);
        const file_name = try randomFileName(&rng, allocator);
        defer allocator.free(file_name);
        const line = randomLineNumber(&rng);

        // Handle error in one coroutine
        _ = try manager.handleError(error_coro_id, error_type, message, file_name, line);

        // Verify other coroutines are not affected
        for (coroutine_ids.items) |coro_id| {
            if (coro_id != error_coro_id) {
                // Other coroutines should not have active errors
                const active_error = manager.getActiveError(coro_id);
                try testing.expect(active_error == null);
            }
        }

        // Cleanup
        for (coroutine_ids.items) |coro_id| {
            manager.unregisterCoroutine(coro_id);
        }
    }
}

// Property 23.2: Recoverable errors allow coroutine to continue
// *For any* recoverable error type, the error handling system should
// return true indicating the coroutine can continue.
test "Property 23.2: Recoverable errors return true" {
    // Feature: php-builtin-functions-concurrency, Property 23: Error isolation
    // Validates: Requirements 11.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var manager = CoroutineErrorManager.init(allocator, .{
        .enable_console = false,
        .min_severity = .info,
    });
    defer manager.deinit();

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const coro_id = @as(u64, @intCast(i + 1));
        try manager.registerCoroutine(coro_id, null);

        // Generate recoverable error
        const error_type = randomRecoverableErrorType(&rng);
        const message = try randomErrorMessage(&rng, allocator);
        defer allocator.free(message);
        const file_name = try randomFileName(&rng, allocator);
        defer allocator.free(file_name);
        const line = randomLineNumber(&rng);

        // Handle error
        const recovered = try manager.handleError(coro_id, error_type, message, file_name, line);

        // Recoverable errors should return true
        try testing.expect(recovered);
        try testing.expect(error_type.isRecoverable());

        manager.unregisterCoroutine(coro_id);
    }
}

// Property 23.3: Error propagation to parent coroutine
// *For any* child coroutine with an error, if it has a parent, the error
// should be propagated to the parent's error channel.
test "Property 23.3: Error propagation to parent" {
    // Feature: php-builtin-functions-concurrency, Property 23: Error isolation
    // Validates: Requirements 11.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var propagation = ErrorPropagation.init(allocator);
    defer propagation.deinit();

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const parent_id = @as(u64, @intCast(i * 2 + 1));
        const child_id = @as(u64, @intCast(i * 2 + 2));

        // Register parent and child
        try propagation.registerCoroutine(parent_id, null);
        try propagation.registerCoroutine(child_id, parent_id);

        // Create error in child
        const error_type = randomErrorType(&rng);
        const message = try randomErrorMessage(&rng, allocator);
        defer allocator.free(message);
        const file_name = try randomFileName(&rng, allocator);
        defer allocator.free(file_name);
        const line = randomLineNumber(&rng);

        const err = try CoroutineError.init(allocator, child_id, error_type, message, file_name, line);
        // Note: err ownership transfers to propagation system

        // Propagate to parent
        try propagation.propagateToParent(child_id, err);

        // Parent should receive error
        const received = propagation.checkErrors(parent_id);
        try testing.expect(received != null);
        try testing.expectEqual(child_id, received.?.coroutine_id);
        try testing.expectEqual(error_type, received.?.error_type);

        // Clean up the received error
        received.?.deinit();

        // Cleanup
        propagation.unregisterCoroutine(child_id);
        propagation.unregisterCoroutine(parent_id);
    }
}

// ============================================================================
// Property 24: Graceful Error Handling Tests
// ============================================================================

// Property 24.1: All error types produce meaningful messages
// *For any* error type, the error handling system should produce
// a formatted message that contains the error type name.
test "Property 24.1: Error messages contain error type information" {
    // Feature: php-builtin-functions-concurrency, Property 24: Graceful error handling
    // Validates: Requirements 11.8
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const coro_id = randomCoroutineId(&rng);
        const error_type = randomErrorType(&rng);
        const message = try randomErrorMessage(&rng, allocator);
        defer allocator.free(message);
        const file_name = try randomFileName(&rng, allocator);
        defer allocator.free(file_name);
        const line = randomLineNumber(&rng);

        const err = try CoroutineError.init(allocator, coro_id, error_type, message, file_name, line);
        defer err.deinit();

        // Format the error
        const formatted = try err.format(allocator);
        defer allocator.free(formatted);

        // Verify formatted message contains error type
        const type_name = error_type.toString();
        try testing.expect(std.mem.indexOf(u8, formatted, type_name) != null);

        // Verify formatted message contains coroutine ID
        const coro_id_str = try std.fmt.allocPrint(allocator, "{d}", .{coro_id});
        defer allocator.free(coro_id_str);
        try testing.expect(std.mem.indexOf(u8, formatted, coro_id_str) != null);

        // Verify formatted message contains file name
        try testing.expect(std.mem.indexOf(u8, formatted, file_name) != null);
    }
}

// Property 24.2: Error severity is correctly assigned based on type
// *For any* error type, the severity should be correctly assigned
// (fatal errors get fatal severity, recoverable get lower severity).
test "Property 24.2: Error severity matches error type" {
    // Feature: php-builtin-functions-concurrency, Property 24: Graceful error handling
    // Validates: Requirements 11.8
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const coro_id = randomCoroutineId(&rng);
        const error_type = randomErrorType(&rng);
        const message = try randomErrorMessage(&rng, allocator);
        defer allocator.free(message);

        const err = try CoroutineError.init(allocator, coro_id, error_type, message, "test.php", 1);
        defer err.deinit();

        // Verify severity matches error type characteristics
        if (error_type.isFatal()) {
            try testing.expect(err.severity == .fatal or err.severity == .critical);
        }

        // Verify error type properties are consistent
        if (error_type.isRecoverable()) {
            try testing.expect(!error_type.isFatal());
        }
    }
}

// Property 24.3: Stack traces are correctly maintained
// *For any* sequence of function entries and exits, the stack trace
// should accurately reflect the current call stack.
test "Property 24.3: Stack trace accuracy" {
    // Feature: php-builtin-functions-concurrency, Property 24: Graceful error handling
    // Validates: Requirements 11.8
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var stack_manager = debugging.StackTraceManager.init(allocator);
    defer stack_manager.deinit();

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const coro_id = @as(u64, @intCast(i + 1));
        try stack_manager.registerCoroutine(coro_id);

        // Generate random stack depth
        const stack_depth = rng.random().intRangeAtMost(usize, 1, 10);

        // Push frames
        for (0..stack_depth) |j| {
            const func_name = try std.fmt.allocPrint(allocator, "func_{d}", .{j});
            defer allocator.free(func_name);
            const file_name = try randomFileName(&rng, allocator);
            defer allocator.free(file_name);
            const line = randomLineNumber(&rng);

            try stack_manager.pushFrame(coro_id, func_name, file_name, line, 1);
        }

        // Verify stack depth
        const trace = stack_manager.getStackTrace(coro_id);
        try testing.expect(trace != null);
        try testing.expectEqual(stack_depth, trace.?.getDepth());

        // Pop some frames
        const frames_to_pop = rng.random().intRangeAtMost(usize, 0, stack_depth);
        for (0..frames_to_pop) |_| {
            stack_manager.popFrame(coro_id);
        }

        // Verify new depth
        try testing.expectEqual(stack_depth - frames_to_pop, trace.?.getDepth());

        stack_manager.unregisterCoroutine(coro_id);
    }
}

// Property 24.4: Error reporter statistics are accurate
// *For any* sequence of reported errors, the statistics should
// accurately reflect the number and types of errors reported.
test "Property 24.4: Error reporter statistics accuracy" {
    // Feature: php-builtin-functions-concurrency, Property 24: Graceful error handling
    // Validates: Requirements 11.8
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var reporter = ErrorReporter.init(allocator, .{
        .enable_console = false,
        .min_severity = .info,
    });
    defer reporter.deinit();

    var expected_count: u64 = 0;
    var severity_counts = [_]u64{0} ** 5;

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const coro_id = randomCoroutineId(&rng);
        const error_type = randomErrorType(&rng);
        const message = try randomErrorMessage(&rng, allocator);
        defer allocator.free(message);

        const err = try CoroutineError.init(allocator, coro_id, error_type, message, "test.php", 1);
        defer err.deinit(); // Caller retains ownership

        try reporter.report(err);
        expected_count += 1;
        severity_counts[@intFromEnum(err.severity)] += 1;
    }

    // Verify statistics
    const stats = reporter.getStats();
    try testing.expectEqual(expected_count, stats.total_reported.load(.monotonic));

    // Verify severity counts
    for (0..5) |j| {
        try testing.expectEqual(severity_counts[j], stats.by_severity[j].load(.monotonic));
    }
}

// ============================================================================
// Additional Property Tests for Comprehensive Coverage
// ============================================================================

// Property 23.4: Panic recovery handles all error types
// *For any* error type, the panic recovery system should attempt
// to handle it according to the configured strategy.
test "Property 23.4: Panic recovery handles all error types" {
    // Feature: php-builtin-functions-concurrency, Property 23: Error isolation
    // Validates: Requirements 11.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var recovery = PanicRecovery.init(allocator);
    defer recovery.deinit();

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const coro_id = randomCoroutineId(&rng);
        const error_type = randomErrorType(&rng);
        const message = try randomErrorMessage(&rng, allocator);
        defer allocator.free(message);

        const err = try CoroutineError.init(allocator, coro_id, error_type, message, "test.php", 1);
        defer err.deinit();

        // Handle panic
        const recovered = recovery.handlePanic(coro_id, err);

        // Verify recovery action was set
        try testing.expect(err.recovery_action != null);

        // Verify statistics were updated
        const stats = recovery.getStats();
        try testing.expect(stats.total_panics.load(.monotonic) > 0);

        // If recovered, verify it's marked as handled
        if (recovered) {
            try testing.expect(err.handled);
        }
    }
}

// Property 24.5: Deadlock detection identifies cycles
// *For any* circular wait pattern, the deadlock detector should
// identify it as a potential deadlock.
test "Property 24.5: Deadlock detection identifies cycles" {
    // Feature: php-builtin-functions-concurrency, Property 24: Graceful error handling
    // Validates: Requirements 11.8
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var detector = DeadlockDetector.init(allocator, .{});
        defer detector.deinit();

        // Create a cycle of random size (2-5 coroutines)
        const cycle_size = rng.random().intRangeAtMost(usize, 2, 5);

        // Each coroutine owns a resource and waits for the next one's resource
        for (0..cycle_size) |j| {
            const coro_id = @as(u64, @intCast(j + 1));
            const owned_resource = @as(u64, @intCast(j + 100));
            const waited_resource = @as(u64, @intCast(((j + 1) % cycle_size) + 100));

            try detector.recordAcquire(coro_id, owned_resource);
            try detector.recordWait(coro_id, waited_resource, randomResourceType(&rng));
        }

        // Detect deadlock
        const result = try detector.detectDeadlock();

        // Should detect a deadlock
        try testing.expect(result != null);

        if (result) |result_val| {
            var info = result_val;
            defer info.deinit();
            // Cycle should involve at least 2 coroutines
            try testing.expect(info.coroutines.items.len >= 2);
        }
    }
}

// Property 24.6: Performance monitor tracks all coroutine states
// *For any* coroutine state transition, the performance monitor
// should accurately track the state change.
test "Property 24.6: Performance monitor state tracking" {
    // Feature: php-builtin-functions-concurrency, Property 24: Graceful error handling
    // Validates: Requirements 11.8
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var monitor = CoroutinePerformanceMonitor.init(allocator, .{});
    defer monitor.deinit();

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const coro_id = @as(u64, @intCast(i + 1));
        try monitor.registerCoroutine(coro_id);

        // Random execution time
        const exec_time = rng.random().intRangeAtMost(u64, 1000, 1_000_000);
        monitor.recordExecution(coro_id, exec_time);

        // Random number of yields
        const num_yields = rng.random().intRangeAtMost(usize, 0, 5);
        for (0..num_yields) |_| {
            monitor.recordYield(coro_id);
        }

        // Verify metrics
        const metrics = monitor.getMetrics(coro_id);
        try testing.expect(metrics != null);
        try testing.expectEqual(@as(u64, 1), metrics.?.schedule_count);
        try testing.expectEqual(@as(u64, @intCast(num_yields)), metrics.?.yield_count);
        try testing.expectEqual(exec_time, metrics.?.total_execution_time_ns);

        monitor.unregisterCoroutine(coro_id);
    }
}

// Property 24.7: Debug coordinator integrates all components
// *For any* debugging operation, the coordinator should correctly
// delegate to the appropriate subsystem.
test "Property 24.7: Debug coordinator integration" {
    // Feature: php-builtin-functions-concurrency, Property 24: Graceful error handling
    // Validates: Requirements 11.8
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var coordinator = CoroutineDebugCoordinator.init(allocator, .{});
    defer coordinator.deinit();

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const coro_id = @as(u64, @intCast(i + 1));
        try coordinator.registerCoroutine(coro_id);

        // Enter some functions
        const num_functions = rng.random().intRangeAtMost(usize, 1, 5);
        for (0..num_functions) |j| {
            const func_name = try std.fmt.allocPrint(allocator, "func_{d}", .{j});
            defer allocator.free(func_name);
            try coordinator.enterFunction(coro_id, func_name, "test.php", @intCast(j + 1), 1);
        }

        // Record execution
        const exec_time = rng.random().intRangeAtMost(u64, 1000, 100_000);
        coordinator.recordExecution(coro_id, exec_time);

        // Get stack trace
        const trace = try coordinator.getStackTrace(coro_id);
        try testing.expect(trace != null);
        defer allocator.free(trace.?);

        // Get metrics
        const metrics = coordinator.getMetrics(coro_id);
        try testing.expect(metrics != null);

        // Exit functions
        for (0..num_functions) |_| {
            coordinator.exitFunction(coro_id);
        }

        coordinator.unregisterCoroutine(coro_id);
    }
}

// Property 23.5: Error manager handles concurrent registrations
// *For any* number of coroutine registrations and unregistrations,
// the error manager should maintain consistent state.
test "Property 23.5: Error manager concurrent registration consistency" {
    // Feature: php-builtin-functions-concurrency, Property 23: Error isolation
    // Validates: Requirements 11.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var manager = CoroutineErrorManager.init(allocator, .{
        .enable_console = false,
        .min_severity = .info,
    });
    defer manager.deinit();

    // Run TEST_ITERATIONS random tests
    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        // Register random number of coroutines
        const num_coroutines = rng.random().intRangeAtMost(usize, 5, 20);
        var registered = std.ArrayListUnmanaged(u64){ .items = &.{}, .capacity = 0 };
        defer registered.deinit(allocator);

        for (0..num_coroutines) |j| {
            const coro_id = @as(u64, @intCast(i * 100 + j + 1));
            try manager.registerCoroutine(coro_id, null);
            try registered.append(allocator, coro_id);
        }

        // Unregister some randomly
        const num_to_unregister = rng.random().intRangeAtMost(usize, 0, num_coroutines / 2);
        for (0..num_to_unregister) |_| {
            if (registered.items.len > 0) {
                const idx = rng.random().intRangeAtMost(usize, 0, registered.items.len - 1);
                const coro_id = registered.orderedRemove(idx);
                manager.unregisterCoroutine(coro_id);
            }
        }

        // Remaining coroutines should still be functional
        for (registered.items) |coro_id| {
            // Should be able to handle errors for remaining coroutines
            const recovered = try manager.handleError(
                coro_id,
                .timeout,
                "test error",
                "test.php",
                1,
            );
            try testing.expect(recovered);
        }

        // Cleanup remaining
        for (registered.items) |coro_id| {
            manager.unregisterCoroutine(coro_id);
        }
    }
}
