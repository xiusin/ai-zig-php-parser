const std = @import("std");
const testing = std.testing;
const Value = @import("runtime/nan_boxing.zig").Value;

// Feature: advanced-compiler-optimization, Property 17: NaN-Boxing 往返一致性
test "nan-boxing round trip - preserves values" {
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // 测试整数
        const int_val = Value.makeInt(42);
        try testing.expect(int_val.isInt());
        try testing.expect(int_val.asInt() == 42);

        // 测试浮点数
        const float_val = Value.makeFloat(3.14);
        try testing.expect(float_val.isFloat());
        try testing.expect(float_val.asFloat() == 3.14);

        // 测试布尔值
        const bool_val = Value.makeBool(true);
        try testing.expect(bool_val.isBool());
        try testing.expect(bool_val.asBool() == true);

        // 测试 null
        const null_val = Value.makeNull();
        try testing.expect(null_val.isNull());

        // 测试对象
        const obj_val = Value.makeObject(0x1234);
        try testing.expect(obj_val.isObject());
        try testing.expect(obj_val.asObject() == 0x1234);
    }
}

// 测试类型判断
test "type checking - correctly identifies types" {
    const int_val = Value.makeInt(42);
    try testing.expect(int_val.isInt());
    try testing.expect(!int_val.isFloat());
    try testing.expect(!int_val.isBool());
    try testing.expect(!int_val.isNull());
    try testing.expect(!int_val.isObject());

    const float_val = Value.makeFloat(3.14);
    try testing.expect(!float_val.isInt());
    try testing.expect(float_val.isFloat());
    try testing.expect(!float_val.isBool());
    try testing.expect(!float_val.isNull());
    try testing.expect(!float_val.isObject());
}

// 测试值相等性
test "value equality - correctly compares values" {
    const int1 = Value.makeInt(42);
    const int2 = Value.makeInt(42);
    const int3 = Value.makeInt(43);

    try testing.expect(int1.equals(int2));
    try testing.expect(!int1.equals(int3));

    const float1 = Value.makeFloat(3.14);
    const float2 = Value.makeFloat(3.14);
    try testing.expect(float1.equals(float2));

    const bool1 = Value.makeBool(true);
    const bool2 = Value.makeBool(true);
    const bool3 = Value.makeBool(false);
    try testing.expect(bool1.equals(bool2));
    try testing.expect(!bool1.equals(bool3));

    const null1 = Value.makeNull();
    const null2 = Value.makeNull();
    try testing.expect(null1.equals(null2));
}

// 测试负数
test "negative integers - correctly handled" {
    const neg_val = Value.makeInt(-42);
    try testing.expect(neg_val.isInt());
    try testing.expect(neg_val.asInt() == -42);
}

// 测试零值
test "zero values - correctly handled" {
    const zero_int = Value.makeInt(0);
    try testing.expect(zero_int.isInt());
    try testing.expect(zero_int.asInt() == 0);

    const zero_float = Value.makeFloat(0.0);
    try testing.expect(zero_float.isFloat());
    try testing.expect(zero_float.asFloat() == 0.0);

    const false_bool = Value.makeBool(false);
    try testing.expect(false_bool.isBool());
    try testing.expect(false_bool.asBool() == false);
}
