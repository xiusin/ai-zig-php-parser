const std = @import("std");
const testing = std.testing;
const types = @import("runtime/types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;

test "enhanced type system - basic types" {
    // Test basic type creation
    const null_val = Value.initNull();
    const bool_val = Value.initBool(true);
    const int_val = Value.initInt(42);
    const float_val = Value.initFloat(3.14);
    
    // Test type checking
    try testing.expect(null_val.isNull());
    try testing.expect(bool_val.isBool());
    try testing.expect(int_val.isInt());
    try testing.expect(float_val.isFloat());
    
    // Test type conversions
    try testing.expect(int_val.toBool() == true);
    try testing.expect(Value.initInt(0).toBool() == false);
    try testing.expectEqual(@as(i64, 1), try bool_val.toInt());
    try testing.expectEqual(@as(i64, 3), try float_val.toInt());
}

test "enhanced type system - string operations" {
    const allocator = testing.allocator;
    
    // Test string creation
    const str_val = try Value.initString(allocator, "Hello, World!");
    defer str_val.data.string.release(allocator);
    
    try testing.expect(str_val.isString());
    
    // Test PHPString operations
    const str1 = try PHPString.init(allocator, "Hello");
    defer str1.deinit(allocator);
    const str2 = try PHPString.init(allocator, " World");
    defer str2.deinit(allocator);
    
    const concat_result = try str1.concat(str2, allocator);
    defer concat_result.deinit(allocator);
    
    try testing.expectEqualStrings("Hello World", concat_result.data);
    
    const substr_result = try str1.substring(1, 3, allocator);
    defer substr_result.deinit(allocator);
    
    try testing.expectEqualStrings("ell", substr_result.data);
    
    const needle = try PHPString.init(allocator, "ell");
    defer needle.deinit(allocator);
    const index = str1.indexOf(needle);
    try testing.expectEqual(@as(i64, 1), index);
}

test "enhanced type system - array operations" {
    const allocator = testing.allocator;
    
    // Test array creation
    const array_val = try Value.initArray(allocator);
    defer array_val.data.array.release(allocator);
    
    try testing.expect(array_val.isArray());
    
    // Add elements
    try array_val.data.array.data.push(Value.initInt(1));
    try array_val.data.array.data.push(Value.initInt(2));
    try array_val.data.array.data.push(Value.initInt(3));
    
    try testing.expectEqual(@as(usize, 3), array_val.data.array.data.count());
    
    // Test associative array
    const key_str = try PHPString.init(allocator, "name");
    defer key_str.deinit(allocator);
    const key = ArrayKey{ .string = key_str };
    const value = try Value.initString(allocator, "John");
    defer value.data.string.release(allocator);
    
    try array_val.data.array.data.set(key, value);
    
    if (array_val.data.array.data.get(key)) |retrieved| {
        try testing.expect(retrieved.isString());
        try testing.expectEqualStrings("John", retrieved.data.string.data.data);
    } else {
        try testing.expect(false); // Should have found the value
    }
}

test "enhanced type system - type conversions" {
    const allocator = testing.allocator;
    
    const int_val = Value.initInt(42);
    const float_val = Value.initFloat(3.14);
    const bool_val = Value.initBool(true);
    
    // Test toString conversions
    const int_str = try int_val.toString(allocator);
    defer int_str.deinit(allocator);
    try testing.expectEqualStrings("42", int_str.data);
    
    const float_str = try float_val.toString(allocator);
    defer float_str.deinit(allocator);
    try testing.expectEqualStrings("3.14", float_str.data);
    
    const bool_str = try bool_val.toString(allocator);
    defer bool_str.deinit(allocator);
    try testing.expectEqualStrings("1", bool_str.data);
    
    // Test numeric conversions
    try testing.expectEqual(@as(f64, 42.0), try int_val.toFloat());
    try testing.expectEqual(@as(i64, 3), try float_val.toInt());
}