//! ============================================================================
//! 时间内置函数 (Time Builtin Functions)
//! ============================================================================
//!
//! 功能：实现PHP时间相关的内置函数
//!
//! 支持的函数：
//! - time(): 返回当前Unix时间戳
//! - microtime(): 返回带微秒的当前时间
//! - date(): 格式化日期时间
//! - sleep(): 秒级休眠
//! - usleep(): 微秒级休眠
//!
//! 需求：1.1, 1.4, 1.5, 1.6, 1.7
//! ============================================================================

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const time_lib = @import("time.zig");
const Time = time_lib.Time;
const Duration = time_lib.Duration;
const builtin_registry = @import("builtin_registry.zig");
const BuiltinFunction = builtin_registry.BuiltinFunction;
const BuiltinError = builtin_registry.BuiltinError;
const Category = builtin_registry.Category;

/// 时间内置函数实现
/// Time builtin functions implementation
pub const TimeBuiltins = struct {
    /// PHP time() - Returns current Unix timestamp
    /// Requirements: 1.1
    pub fn time(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        _ = args;
        
        const timestamp = time_lib.phpTime();
        return Value.initInt(timestamp);
    }

    /// PHP microtime() - Returns current time with microseconds
    /// Requirements: 1.4, 1.5
    pub fn microtime(vm: *anyopaque, args: []const Value) !Value {
        if (args.len == 0) {
            // Return string format "msec sec"
            const t = Time.now();
            const sec = t.getUnix();
            const usec = @divTrunc(t.nanosecond(), 1000);
            
            // Format as "0.microseconds seconds"
            const vm_ptr = @as(*@import("vm.zig").VM, @ptrCast(@alignCast(vm)));
            const formatted = try std.fmt.allocPrint(vm_ptr.allocator, "0.{d:0>6} {d}", .{ usec, sec });
            return Value.initString(formatted);
        } else if (args.len == 1) {
            // Check if get_as_float is true
            const get_as_float = if (args[0].getTag() == .boolean) 
                args[0].asBool() 
            else if (args[0].getTag() == .integer)
                args[0].asInt() != 0
            else
                false;
                
            if (get_as_float) {
                // Return float timestamp
                const float_time = time_lib.phpMicrotime();
                return Value.initFloat(float_time);
            } else {
                // Return string format
                const t = Time.now();
                const sec = t.getUnix();
                const usec = @divTrunc(t.nanosecond(), 1000);
                
                const vm_ptr = @as(*@import("vm.zig").VM, @ptrCast(@alignCast(vm)));
                const formatted = try std.fmt.allocPrint(vm_ptr.allocator, "0.{d:0>6} {d}", .{ usec, sec });
                return Value.initString(formatted);
            }
        } else {
            return BuiltinError.ArgumentCountMismatch;
        }
    }

    /// PHP date() - Format a timestamp
    /// Requirements: 1.7, 1.8
    pub fn date(vm: *anyopaque, args: []const Value) !Value {
        if (args.len < 1 or args.len > 2) {
            return BuiltinError.ArgumentCountMismatch;
        }

        // Get format string
        if (args[0].getTag() != .string) {
            return BuiltinError.InvalidArgumentType;
        }
        const format = args[0].asString();

        // Get timestamp (optional)
        const timestamp: ?i64 = if (args.len >= 2) blk: {
            if (args[1].getTag() == .integer) {
                break :blk args[1].asInt();
            } else if (args[1].getTag() == .float) {
                break :blk @intFromFloat(args[1].asFloat());
            } else {
                return BuiltinError.InvalidArgumentType;
            }
        } else null;

        const vm_ptr = @as(*@import("vm.zig").VM, @ptrCast(@alignCast(vm)));
        const formatted = try time_lib.phpDate(format, timestamp, vm_ptr.allocator);
        return Value.initString(formatted);
    }

    /// PHP sleep() - Sleep for specified seconds (coroutine-aware)
    /// Requirements: 1.2, 1.6
    pub fn sleep(vm: *anyopaque, args: []const Value) !Value {
        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }

        // Get sleep duration in seconds
        const seconds = switch (args[0].getTag()) {
            .integer => @as(u64, @intCast(@max(0, args[0].asInt()))),
            .float => @as(u64, @intFromFloat(@max(0.0, args[0].asFloat()))),
            else => return BuiltinError.InvalidArgumentType,
        };

        const vm_ptr = @as(*@import("vm.zig").VM, @ptrCast(@alignCast(vm)));
        
        // If we have a coroutine manager, use coroutine-aware sleep
        if (vm_ptr.coroutine_manager) |manager| {
            manager.sleep(seconds * 1000); // Convert to milliseconds
        } else {
            // Fallback to regular sleep
            std.time.sleep(seconds * std.time.ns_per_s);
        }

        return Value.initInt(@intCast(seconds));
    }

    /// PHP usleep() - Sleep for specified microseconds (coroutine-aware)
    /// Requirements: 1.3, 1.6
    pub fn usleep(vm: *anyopaque, args: []const Value) !Value {
        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }

        // Get sleep duration in microseconds
        const microseconds = switch (args[0].getTag()) {
            .integer => @as(u64, @intCast(@max(0, args[0].asInt()))),
            .float => @as(u64, @intFromFloat(@max(0.0, args[0].asFloat()))),
            else => return BuiltinError.InvalidArgumentType,
        };

        const vm_ptr = @as(*@import("vm.zig").VM, @ptrCast(@alignCast(vm)));
        
        // If we have a coroutine manager, use coroutine-aware sleep
        if (vm_ptr.coroutine_manager) |manager| {
            const milliseconds = @divTrunc(microseconds, 1000);
            manager.sleep(if (milliseconds == 0) 1 else milliseconds); // Minimum 1ms
        } else {
            // Fallback to regular sleep
            std.time.sleep(microseconds * std.time.ns_per_us);
        }

        return Value.initNull();
    }

    /// Coroutine-aware sleep implementation for internal use
    /// This integrates with the scheduler's timer wheel for efficient sleeping
    /// Requirements: 1.2, 1.3, 1.6
    pub fn coSleep(vm: *anyopaque, duration_us: u64) !void {
        const vm_ptr = @as(*@import("vm.zig").VM, @ptrCast(@alignCast(vm)));
        
        if (vm_ptr.coroutine_manager) |manager| {
            const milliseconds = @divTrunc(duration_us, 1000);
            manager.sleep(if (milliseconds == 0) 1 else milliseconds);
        } else {
            // Fallback to regular sleep
            std.time.sleep(duration_us * std.time.ns_per_us);
        }
    }

    /// Get all time builtin functions
    pub fn getAllFunctions() [5]BuiltinFunction {
        return [_]BuiltinFunction{
            BuiltinFunction.init("time", .time, time, 0, 0, "Returns current Unix timestamp"),
            BuiltinFunction.init("microtime", .time, microtime, 0, 1, "Returns current time with microseconds"),
            BuiltinFunction.init("date", .time, date, 1, 2, "Format a timestamp"),
            BuiltinFunction.init("sleep", .time, sleep, 1, 1, "Sleep for specified seconds"),
            BuiltinFunction.init("usleep", .time, usleep, 1, 1, "Sleep for specified microseconds"),
        };
    }
};

test "TimeBuiltins.time" {
    const testing = std.testing;
    
    // Mock VM for testing
    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    const result = try TimeBuiltins.time(vm_ptr, &[_]Value{});
    try testing.expect(result.getTag() == .integer);
    
    // Should return a reasonable timestamp (after 2020)
    const timestamp = result.asInt();
    try testing.expect(timestamp > 1577836800); // 2020-01-01
}

test "TimeBuiltins.microtime" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Create a minimal VM structure for testing
    const MockVM = struct {
        allocator: std.mem.Allocator,
    };
    
    var mock_vm = MockVM{ .allocator = allocator };
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test microtime() with no arguments (string format)
    const result1 = try TimeBuiltins.microtime(vm_ptr, &[_]Value{});
    try testing.expect(result1.getTag() == .string);
    const str_result = result1.asString();
    defer allocator.free(str_result);
    
    // Should contain a space separating microseconds and seconds
    try testing.expect(std.mem.indexOf(u8, str_result, " ") != null);
    
    // Test microtime(true) (float format)
    const true_arg = Value.initBool(true);
    const result2 = try TimeBuiltins.microtime(vm_ptr, &[_]Value{true_arg});
    try testing.expect(result2.getTag() == .float);
    
    // Should be a reasonable timestamp
    const float_time = result2.asFloat();
    try testing.expect(float_time > 1577836800.0); // After 2020-01-01
}

test "TimeBuiltins.date" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Create a minimal VM structure for testing
    const MockVM = struct {
        allocator: std.mem.Allocator,
    };
    
    var mock_vm = MockVM{ .allocator = allocator };
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test date formatting with specific timestamp
    const format_arg = Value.initString("Y-m-d H:i:s");
    const timestamp_arg = Value.initInt(1718461845); // 2024-06-15 14:30:45 UTC
    
    const result = try TimeBuiltins.date(vm_ptr, &[_]Value{ format_arg, timestamp_arg });
    try testing.expect(result.getTag() == .integer);
    
    const formatted = result.asString();
    defer allocator.free(formatted);
    try testing.expectEqualStrings("2024-06-15 14:30:45", formatted);
}

test "TimeBuiltins.sleep" {
    const testing = std.testing;
    
    // Create a minimal VM structure for testing
    const MockVM = struct {
        allocator: std.mem.Allocator,
        coroutine_manager: ?*anyopaque = null,
    };
    
    var mock_vm = MockVM{ .allocator = testing.allocator };
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test sleep with integer seconds
    const seconds_arg = Value.initInt(1);
    const start_time = std.time.milliTimestamp();
    
    const result = try TimeBuiltins.sleep(vm_ptr, &[_]Value{seconds_arg});
    const end_time = std.time.milliTimestamp();
    
    try testing.expect(result.getTag() == .integer);
    try testing.expect(result.asInt() == 1);
    
    // Should have slept for approximately 1 second (allow some tolerance)
    const elapsed = end_time - start_time;
    try testing.expect(elapsed >= 900 and elapsed <= 1100); // 900ms to 1100ms tolerance
}

test "TimeBuiltins.usleep" {
    const testing = std.testing;
    
    // Create a minimal VM structure for testing
    const MockVM = struct {
        allocator: std.mem.Allocator,
        coroutine_manager: ?*anyopaque = null,
    };
    
    var mock_vm = MockVM{ .allocator = testing.allocator };
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test usleep with microseconds (use a small value for testing)
    const microseconds_arg = Value.initInt(10000); // 10ms
    const start_time = std.time.milliTimestamp();
    
    const result = try TimeBuiltins.usleep(vm_ptr, &[_]Value{microseconds_arg});
    const end_time = std.time.milliTimestamp();
    
    try testing.expect(result.getTag() == .null);
    
    // Should have slept for approximately 10ms (allow some tolerance)
    const elapsed = end_time - start_time;
    try testing.expect(elapsed >= 5 and elapsed <= 50); // 5ms to 50ms tolerance
}