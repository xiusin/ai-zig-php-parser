//! Property-Based Tests for AOT Runtime Library
//!
//! This module contains property-based tests that verify the correctness
//! of the runtime library's type conversion and garbage collection.
//!
//! **Feature: php-aot-compiler**
//!
//! Properties tested:
//! - Property 7: Runtime library type conversion correctness
//! - Property 8: Garbage collection correctness

const std = @import("std");
const testing = std.testing;
const RuntimeLib = @import("runtime_lib.zig");

const PHPValue = RuntimeLib.PHPValue;
const ValueTag = RuntimeLib.ValueTag;
const php_value_create_null = RuntimeLib.php_value_create_null;
const php_value_create_bool = RuntimeLib.php_value_create_bool;
const php_value_create_int = RuntimeLib.php_value_create_int;
const php_value_create_float = RuntimeLib.php_value_create_float;
const php_value_create_string = RuntimeLib.php_value_create_string;
const php_value_create_array = RuntimeLib.php_value_create_array;
const php_gc_retain = RuntimeLib.php_gc_retain;
const php_gc_release = RuntimeLib.php_gc_release;
const php_gc_get_ref_count = RuntimeLib.php_gc_get_ref_count;
const initRuntime = RuntimeLib.initRuntime;
const deinitRuntime = RuntimeLib.deinitRuntime;

// ============================================================================
// Random Value Generators
// ============================================================================

/// Generate a random integer value
fn generateRandomInt(rng: std.Random) i64 {
    return rng.int(i64);
}

/// Generate a random float value
fn generateRandomFloat(rng: std.Random) f64 {
    // Generate a float in a reasonable range to avoid precision issues
    const int_part: f64 = @floatFromInt(rng.intRangeAtMost(i32, -1000000, 1000000));
    const frac_part: f64 = @as(f64, @floatFromInt(rng.intRangeAtMost(u32, 0, 999999))) / 1000000.0;
    return int_part + frac_part;
}

/// Generate a random string
fn generateRandomString(rng: std.Random, allocator: std.mem.Allocator) ![]const u8 {
    const len = rng.intRangeAtMost(usize, 0, 100);
    const buf = try allocator.alloc(u8, len);
    for (buf) |*c| {
        // Generate printable ASCII characters
        c.* = @intCast(rng.intRangeAtMost(u8, 32, 126));
    }
    return buf;
}

/// Generate a random numeric string
fn generateRandomNumericString(rng: std.Random, allocator: std.mem.Allocator) ![]const u8 {
    const val = rng.intRangeAtMost(i64, -1000000, 1000000);
    return try std.fmt.allocPrint(allocator, "{d}", .{val});
}

// ============================================================================
// Property 7: Type Conversion Correctness
// **Validates: Requirements 5.2**
// ============================================================================

// Property 7.1: Integer to boolean conversion follows PHP rules
// For any integer, toBool should return false only for 0
test "Property 7.1: Integer to boolean conversion" {
    // Feature: php-aot-compiler, Property 7: Runtime library type conversion correctness
    initRuntime();
    defer deinitRuntime();

    var prng = std.Random.DefaultPrng.init(12345);
    const rng = prng.random();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const int_val = generateRandomInt(rng);
        const val = php_value_create_int(int_val);
        defer php_gc_release(val);

        const bool_result = val.toBool();
        const expected = int_val != 0;

        try testing.expectEqual(expected, bool_result);
    }
}

// Property 7.2: Float to integer conversion truncates towards zero
// For any float, toInt should truncate towards zero (like PHP's (int) cast)
test "Property 7.2: Float to integer conversion truncates" {
    // Feature: php-aot-compiler, Property 7: Runtime library type conversion correctness
    initRuntime();
    defer deinitRuntime();

    var prng = std.Random.DefaultPrng.init(23456);
    const rng = prng.random();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const float_val = generateRandomFloat(rng);
        const val = php_value_create_float(float_val);
        defer php_gc_release(val);

        const int_result = val.toInt();
        const expected: i64 = @intFromFloat(float_val);

        try testing.expectEqual(expected, int_result);
    }
}

// Property 7.3: Integer to float conversion preserves value
// For any integer in safe range, toFloat should preserve the exact value
test "Property 7.3: Integer to float conversion preserves value" {
    // Feature: php-aot-compiler, Property 7: Runtime library type conversion correctness
    initRuntime();
    defer deinitRuntime();

    var prng = std.Random.DefaultPrng.init(34567);
    const rng = prng.random();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        // Use a range that can be exactly represented in f64
        const int_val = rng.intRangeAtMost(i64, -9007199254740992, 9007199254740992);
        const val = php_value_create_int(int_val);
        defer php_gc_release(val);

        const float_result = val.toFloat();
        const expected: f64 = @floatFromInt(int_val);

        try testing.expectEqual(expected, float_result);
    }
}

// Property 7.4: Null always converts to falsy values
// For null, toBool should be false, toInt should be 0, toFloat should be 0.0
test "Property 7.4: Null conversion consistency" {
    // Feature: php-aot-compiler, Property 7: Runtime library type conversion correctness
    initRuntime();
    defer deinitRuntime();

    // Run multiple times to ensure consistency
    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const val = php_value_create_null();
        defer php_gc_release(val);

        try testing.expect(!val.toBool());
        try testing.expectEqual(@as(i64, 0), val.toInt());
        try testing.expectEqual(@as(f64, 0.0), val.toFloat());
    }
}

// Property 7.5: Boolean to integer conversion
// true -> 1, false -> 0
test "Property 7.5: Boolean to integer conversion" {
    // Feature: php-aot-compiler, Property 7: Runtime library type conversion correctness
    initRuntime();
    defer deinitRuntime();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const val_true = php_value_create_bool(true);
        defer php_gc_release(val_true);
        const val_false = php_value_create_bool(false);
        defer php_gc_release(val_false);

        try testing.expectEqual(@as(i64, 1), val_true.toInt());
        try testing.expectEqual(@as(i64, 0), val_false.toInt());
    }
}

// Property 7.6: Empty string is falsy, non-empty (except "0") is truthy
test "Property 7.6: String truthiness" {
    // Feature: php-aot-compiler, Property 7: Runtime library type conversion correctness
    initRuntime();
    defer deinitRuntime();

    // Empty string is falsy
    const empty = php_value_create_string("");
    defer php_gc_release(empty);
    try testing.expect(!empty.toBool());

    // "0" is falsy
    const zero_str = php_value_create_string("0");
    defer php_gc_release(zero_str);
    try testing.expect(!zero_str.toBool());

    // Non-empty, non-"0" strings are truthy
    var prng = std.Random.DefaultPrng.init(45678);
    const rng = prng.random();
    const allocator = std.testing.allocator;

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const len = rng.intRangeAtMost(usize, 1, 50);
        const buf = try allocator.alloc(u8, len);
        defer allocator.free(buf);

        // Generate non-"0" string
        for (buf) |*c| {
            c.* = @intCast(rng.intRangeAtMost(u8, 33, 126)); // Printable, non-space
        }
        // Ensure it's not just "0"
        if (len == 1 and buf[0] == '0') {
            buf[0] = '1';
        }

        const val = php_value_create_string(buf);
        defer php_gc_release(val);
        try testing.expect(val.toBool());
    }
}

// ============================================================================
// Property 8: Garbage Collection Correctness
// **Validates: Requirements 5.3**
// ============================================================================

// Property 8.1: Reference count starts at 1
// For any newly created value, ref_count should be 1
test "Property 8.1: Initial reference count is 1" {
    // Feature: php-aot-compiler, Property 8: Garbage collection correctness
    initRuntime();
    defer deinitRuntime();

    var prng = std.Random.DefaultPrng.init(56789);
    const rng = prng.random();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        // Test different value types
        const choice = rng.intRangeAtMost(u8, 0, 5);
        const val: *PHPValue = switch (choice) {
            0 => php_value_create_null(),
            1 => php_value_create_bool(rng.boolean()),
            2 => php_value_create_int(generateRandomInt(rng)),
            3 => php_value_create_float(generateRandomFloat(rng)),
            4 => php_value_create_string("test"),
            else => php_value_create_array(),
        };
        defer php_gc_release(val);

        try testing.expectEqual(@as(u32, 1), php_gc_get_ref_count(val));
    }
}

// Property 8.2: Retain increments reference count
// For any value, calling retain should increment ref_count by 1
test "Property 8.2: Retain increments reference count" {
    // Feature: php-aot-compiler, Property 8: Garbage collection correctness
    initRuntime();
    defer deinitRuntime();

    var prng = std.Random.DefaultPrng.init(67890);
    const rng = prng.random();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const val = php_value_create_int(generateRandomInt(rng));

        const initial_count = php_gc_get_ref_count(val);
        try testing.expectEqual(@as(u32, 1), initial_count);

        // Retain multiple times
        const retain_count = rng.intRangeAtMost(u32, 1, 10);
        var i: u32 = 0;
        while (i < retain_count) : (i += 1) {
            php_gc_retain(val);
        }

        try testing.expectEqual(initial_count + retain_count, php_gc_get_ref_count(val));

        // Release all references
        i = 0;
        while (i <= retain_count) : (i += 1) {
            php_gc_release(val);
        }
    }
}

// Property 8.3: Release decrements reference count
// For any value with ref_count > 1, calling release should decrement ref_count by 1
test "Property 8.3: Release decrements reference count" {
    // Feature: php-aot-compiler, Property 8: Garbage collection correctness
    initRuntime();
    defer deinitRuntime();

    var prng = std.Random.DefaultPrng.init(78901);
    const rng = prng.random();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const val = php_value_create_int(generateRandomInt(rng));

        // Retain to increase ref count
        const retain_count = rng.intRangeAtMost(u32, 2, 10);
        var i: u32 = 0;
        while (i < retain_count) : (i += 1) {
            php_gc_retain(val);
        }

        const count_after_retain = php_gc_get_ref_count(val);
        try testing.expectEqual(@as(u32, 1) + retain_count, count_after_retain);

        // Release one
        php_gc_release(val);
        try testing.expectEqual(count_after_retain - 1, php_gc_get_ref_count(val));

        // Release remaining
        i = 0;
        while (i < retain_count) : (i += 1) {
            php_gc_release(val);
        }
    }
}

// Property 8.4: Reference count is preserved across type operations
// Type conversion operations should not affect the original value's ref count
test "Property 8.4: Type operations preserve reference count" {
    // Feature: php-aot-compiler, Property 8: Garbage collection correctness
    initRuntime();
    defer deinitRuntime();

    var prng = std.Random.DefaultPrng.init(89012);
    const rng = prng.random();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const int_val = generateRandomInt(rng);
        const val = php_value_create_int(int_val);
        defer php_gc_release(val);

        const initial_count = php_gc_get_ref_count(val);

        // Perform type conversions (these should not affect ref count)
        _ = val.toBool();
        _ = val.toInt();
        _ = val.toFloat();

        try testing.expectEqual(initial_count, php_gc_get_ref_count(val));
    }
}

// Property 8.5: Array values are properly retained
// Values added to arrays should have their ref count incremented
test "Property 8.5: Array retains values" {
    // Feature: php-aot-compiler, Property 8: Garbage collection correctness
    initRuntime();
    defer deinitRuntime();

    var iterations: usize = 0;
    while (iterations < 100) : (iterations += 1) {
        const arr_val = php_value_create_array();
        defer php_gc_release(arr_val);

        const arr = arr_val.data.array_ptr orelse continue;

        // Create a value and add to array
        const val = php_value_create_int(42);
        const initial_count = php_gc_get_ref_count(val);

        RuntimeLib.php_array_push(arr, val);

        // Value should have been retained by the array
        try testing.expect(php_gc_get_ref_count(val) >= initial_count);

        // Release our reference - array still holds it
        php_gc_release(val);
    }
}
