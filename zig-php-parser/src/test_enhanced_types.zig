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
    try testing.expect(bool_val.asBool() == true);
    try testing.expectEqual(@as(i64, 42), int_val.asInt());
}

test "enhanced type system - string operations" {
    const allocator = testing.allocator;
    
    // Test string creation
    const str_val = try Value.initString(allocator, "Hello, World!");
    defer str_val.release(allocator);
    
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
    
    // Test array creation using PHPArray directly
    var array = PHPArray.init(allocator);
    defer array.deinit(allocator);
    
    // Add elements
    try array.push(allocator, Value.initInt(1));
    try array.push(allocator, Value.initInt(2));
    try array.push(allocator, Value.initInt(3));
    
    try testing.expectEqual(@as(usize, 3), array.count());
    
    // Test associative array
    const key_str = try PHPString.init(allocator, "name");
    const key = ArrayKey{ .string = key_str };
    const value = try Value.initString(allocator, "John");
    
    try array.set(allocator, key, value);
    
    // Test retrieval
    const retrieved = array.get(key);
    try testing.expect(retrieved != null);
    if (retrieved) |v| {
        try testing.expect(v.isString());
    }
}

test "enhanced type system - type conversions" {
    // Test integer to bool conversion
    const int_val = Value.initInt(42);
    try testing.expect(int_val.toBool() == true);
    
    const zero_val = Value.initInt(0);
    try testing.expect(zero_val.toBool() == false);
    
    // Test float to bool conversion
    const float_val = Value.initFloat(3.14);
    try testing.expect(float_val.toBool() == true);
    
    const zero_float = Value.initFloat(0.0);
    try testing.expect(zero_float.toBool() == false);
    
    // Test null to bool conversion
    const null_val = Value.initNull();
    try testing.expect(null_val.toBool() == false);
    
    // Test bool values
    const true_val = Value.initBool(true);
    const false_val = Value.initBool(false);
    try testing.expect(true_val.toBool() == true);
    try testing.expect(false_val.toBool() == false);
}

test "enhanced type system - value extraction" {
    // Test integer extraction
    const int_val = Value.initInt(42);
    try testing.expectEqual(@as(i64, 42), int_val.asInt());
    
    // Test float extraction
    const float_val = Value.initFloat(3.14);
    try testing.expectApproxEqAbs(@as(f64, 3.14), float_val.asFloat(), 0.001);
    
    // Test bool extraction
    const bool_val = Value.initBool(true);
    try testing.expect(bool_val.asBool() == true);
}
