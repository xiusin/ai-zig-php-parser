const std = @import("std");
const testing = std.testing;
const types = @import("runtime/types.zig");
const Value = types.Value;
const VM = @import("runtime/vm.zig").VM;
const PHPContext = @import("compiler/parser.zig").PHPContext;
const Environment = @import("runtime/environment.zig").Environment;

test "is_null function" {
    const allocator = testing.allocator;
    
    // Initialize VM
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    // Test is_null with null value
    const null_value = Value.initNull();
    const is_null_result = vm.global.get("is_null").?.data.builtin_function;
    const is_null_fn: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(is_null_result));
    
    const result1 = try is_null_fn(vm, &[_]Value{null_value});
    try testing.expect(result1.toBool() == true);
    
    // Test is_null with non-null value
    const int_value = Value.initInt(42);
    const result2 = try is_null_fn(vm, &[_]Value{int_value});
    try testing.expect(result2.toBool() == false);
    
    // Test is_null with string value
    const string_value = try Value.initString(allocator, "hello");
    defer string_value.release(allocator);
    const result3 = try is_null_fn(vm, &[_]Value{string_value});
    try testing.expect(result3.toBool() == false);
}

test "empty function" {
    const allocator = testing.allocator;
    
    // Initialize VM
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    const empty_fn_ptr = vm.global.get("empty").?.data.builtin_function;
    const empty_fn: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(empty_fn_ptr));
    
    // Test empty with null
    const null_value = Value.initNull();
    const result1 = try empty_fn(vm, &[_]Value{null_value});
    try testing.expect(result1.toBool() == true);
    
    // Test empty with false
    const false_value = Value.initBool(false);
    const result2 = try empty_fn(vm, &[_]Value{false_value});
    try testing.expect(result2.toBool() == true);
    
    // Test empty with true
    const true_value = Value.initBool(true);
    const result3 = try empty_fn(vm, &[_]Value{true_value});
    try testing.expect(result3.toBool() == false);
    
    // Test empty with zero integer
    const zero_int = Value.initInt(0);
    const result4 = try empty_fn(vm, &[_]Value{zero_int});
    try testing.expect(result4.toBool() == true);
    
    // Test empty with non-zero integer
    const nonzero_int = Value.initInt(42);
    const result5 = try empty_fn(vm, &[_]Value{nonzero_int});
    try testing.expect(result5.toBool() == false);
    
    // Test empty with zero float
    const zero_float = Value.initFloat(0.0);
    const result6 = try empty_fn(vm, &[_]Value{zero_float});
    try testing.expect(result6.toBool() == true);
    
    // Test empty with non-zero float
    const nonzero_float = Value.initFloat(3.14);
    const result7 = try empty_fn(vm, &[_]Value{nonzero_float});
    try testing.expect(result7.toBool() == false);
    
    // Test empty with empty string
    const empty_string = try Value.initString(allocator, "");
    defer empty_string.release(allocator);
    const result8 = try empty_fn(vm, &[_]Value{empty_string});
    try testing.expect(result8.toBool() == true);
    
    // Test empty with "0" string
    const zero_string = try Value.initString(allocator, "0");
    defer zero_string.release(allocator);
    const result9 = try empty_fn(vm, &[_]Value{zero_string});
    try testing.expect(result9.toBool() == true);
    
    // Test empty with non-empty string
    const nonempty_string = try Value.initString(allocator, "hello");
    defer nonempty_string.release(allocator);
    const result10 = try empty_fn(vm, &[_]Value{nonempty_string});
    try testing.expect(result10.toBool() == false);
    
    // Test empty with empty array
    const empty_array = try Value.initArray(allocator);
    defer empty_array.release(allocator);
    const result11 = try empty_fn(vm, &[_]Value{empty_array});
    try testing.expect(result11.toBool() == true);
    
    // Test empty with non-empty array
    const nonempty_array = try Value.initArray(allocator);
    defer nonempty_array.release(allocator);
    try nonempty_array.data.array.data.push(allocator, Value.initInt(1));
    const result12 = try empty_fn(vm, &[_]Value{nonempty_array});
    try testing.expect(result12.toBool() == false);
}

test "unset function" {
    const allocator = testing.allocator;
    
    // Initialize VM
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    const unset_fn_ptr = vm.global.get("unset").?.data.builtin_function;
    const unset_fn: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(unset_fn_ptr));
    
    // Test unset with a value (simplified implementation)
    const test_value = Value.initInt(42);
    const result = try unset_fn(vm, &[_]Value{test_value});
    try testing.expect(result.isNull());
    
    // Test unset with multiple values
    const value1 = Value.initInt(1);
    const value2 = Value.initInt(2);
    const result2 = try unset_fn(vm, &[_]Value{ value1, value2 });
    try testing.expect(result2.isNull());
}

test "variable functions error handling" {
    const allocator = testing.allocator;
    
    // Initialize VM
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    // Test is_null with wrong argument count
    const is_null_fn_ptr = vm.global.get("is_null").?.data.builtin_function;
    const is_null_fn: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(is_null_fn_ptr));
    
    // The function should throw an exception, which gets converted to an error
    const result1 = is_null_fn(vm, &[_]Value{}) catch |err| {
        // The error could be UncaughtException due to exception handling
        try testing.expect(err == error.ArgumentCountMismatch or err == error.UncaughtException);
        return;
    };
    _ = result1;
    try testing.expect(false); // Should not reach here
}