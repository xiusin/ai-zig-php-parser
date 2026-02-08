//! AOT运行时综合测试
//!
//! 验证AOT运行时库的所有核心功能，包括：
//! - 算术运算
//! - 比较运算
//! - 逻辑运算
//! - 字符串操作
//! - 数组操作
//! - 数学函数
//! - 类型检查
//! - 类型转换

const std = @import("std");
const testing = std.testing;
const runtime = @import("runtime_lib_template.zig");
const Value = runtime.Value;
const PHPString = runtime.PHPString;
const PHPArray = runtime.PHPArray;

// 测试算术运算
test "算术运算 - 加法" {
    const a = Value.initInt(10);
    const b = Value.initInt(20);
    const result = try runtime.php_add(a, b);
    try testing.expect(result.isInt());
    try testing.expectEqual(@as(i64, 30), result.asInt());
}

test "算术运算 - 减法" {
    const a = Value.initInt(30);
    const b = Value.initInt(20);
    const result = try runtime.php_sub(a, b);
    try testing.expect(result.isInt());
    try testing.expectEqual(@as(i64, 10), result.asInt());
}

test "算术运算 - 乘法" {
    const a = Value.initInt(5);
    const b = Value.initInt(6);
    const result = try runtime.php_mul(a, b);
    try testing.expect(result.isInt());
    try testing.expectEqual(@as(i64, 30), result.asInt());
}

test "算术运算 - 除法" {
    const a = Value.initInt(30);
    const b = Value.initInt(5);
    const result = try runtime.php_div(a, b);
    try testing.expect(result.isInt());
    try testing.expectEqual(@as(i64, 6), result.asInt());
}

test "算术运算 - 取模" {
    const a = Value.initInt(17);
    const b = Value.initInt(5);
    const result = try runtime.php_mod(a, b);
    try testing.expect(result.isInt());
    try testing.expectEqual(@as(i64, 2), result.asInt());
}

test "算术运算 - 幂运算" {
    const base = Value.initInt(2);
    const exp = Value.initInt(10);
    const result = try runtime.php_pow(base, exp);
    try testing.expectApproxEqAbs(@as(f64, 1024.0), result.toFloat(), 0.001);
}

test "算术运算 - 浮点加法" {
    const a = Value.initFloat(3.14);
    const b = Value.initFloat(2.86);
    const result = try runtime.php_add(a, b);
    try testing.expect(result.isFloat());
    try testing.expectApproxEqAbs(@as(f64, 6.0), result.asFloat(), 0.001);
}

// 测试比较运算
test "比较运算 - 等于" {
    const a = Value.initInt(10);
    const b = Value.initInt(10);
    const result = try runtime.php_eq(a, b);
    try testing.expect(result.asBool());
}

test "比较运算 - 不等于" {
    const a = Value.initInt(10);
    const b = Value.initInt(20);
    const result = try runtime.php_ne(a, b);
    try testing.expect(result.asBool());
}

test "比较运算 - 小于" {
    const a = Value.initInt(5);
    const b = Value.initInt(10);
    const result = try runtime.php_lt(a, b);
    try testing.expect(result.asBool());
}

test "比较运算 - 大于" {
    const a = Value.initInt(15);
    const b = Value.initInt(10);
    const result = try runtime.php_gt(a, b);
    try testing.expect(result.asBool());
}

test "比较运算 - 全等" {
    const a = Value.initInt(10);
    const b = Value.initInt(10);
    const result = try runtime.php_identical(a, b);
    try testing.expect(result.asBool());
}

test "比较运算 - 类型不同不全等" {
    const a = Value.initInt(10);
    const b = Value.initFloat(10.0);
    const result = try runtime.php_identical(a, b);
    try testing.expect(!result.asBool());
}

// 测试逻辑运算
test "逻辑运算 - 与" {
    const t = Value.initBool(true);
    const f = Value.initBool(false);

    const result1 = try runtime.php_and(t, t);
    try testing.expect(result1.asBool());

    const result2 = try runtime.php_and(t, f);
    try testing.expect(!result2.asBool());
}

test "逻辑运算 - 或" {
    const t = Value.initBool(true);
    const f = Value.initBool(false);

    const result1 = try runtime.php_or(t, f);
    try testing.expect(result1.asBool());

    const result2 = try runtime.php_or(f, f);
    try testing.expect(!result2.asBool());
}

test "逻辑运算 - 非" {
    const t = Value.initBool(true);
    const result = try runtime.php_not(t);
    try testing.expect(!result.asBool());
}

// 测试字符串操作
test "字符串 - 长度" {
    const allocator = testing.allocator;
    const str = try PHPString.init(allocator, "Hello");
    defer str.release(allocator);

    const val = Value.initString(str);
    const len = try runtime.php_strlen(val);
    try testing.expectEqual(@as(i64, 5), len.asInt());
}

test "字符串 - 连接" {
    const allocator = testing.allocator;

    const s1 = try PHPString.init(allocator, "Hello");
    defer s1.release(allocator);
    const s2 = try PHPString.init(allocator, " World");
    defer s2.release(allocator);

    const v1 = Value.initString(s1);
    const v2 = Value.initString(s2);

    const result = try runtime.php_concat(v1, v2, allocator);
    defer result.asString().release(allocator);

    try testing.expectEqualStrings("Hello World", result.asString().data);
}

test "字符串 - 大写转换" {
    const allocator = testing.allocator;

    const str = try PHPString.init(allocator, "hello");
    defer str.release(allocator);

    const val = Value.initString(str);
    const result = try runtime.php_strtoupper(val, allocator);
    defer result.asString().release(allocator);

    try testing.expectEqualStrings("HELLO", result.asString().data);
}

test "字符串 - 小写转换" {
    const allocator = testing.allocator;

    const str = try PHPString.init(allocator, "HELLO");
    defer str.release(allocator);

    const val = Value.initString(str);
    const result = try runtime.php_strtolower(val, allocator);
    defer result.asString().release(allocator);

    try testing.expectEqualStrings("hello", result.asString().data);
}

test "字符串 - trim" {
    const allocator = testing.allocator;

    const str = try PHPString.init(allocator, "  hello  ");
    defer str.release(allocator);

    const val = Value.initString(str);
    const result = try runtime.php_trim(val, Value.initNull(), allocator);
    defer result.asString().release(allocator);

    try testing.expectEqualStrings("hello", result.asString().data);
}

test "字符串 - strrev" {
    const allocator = testing.allocator;

    const str = try PHPString.init(allocator, "hello");
    defer str.release(allocator);

    const val = Value.initString(str);
    const result = try runtime.php_strrev(val, allocator);
    defer result.asString().release(allocator);

    try testing.expectEqualStrings("olleh", result.asString().data);
}

test "字符串 - str_contains" {
    const allocator = testing.allocator;

    const haystack = try PHPString.init(allocator, "Hello World");
    defer haystack.release(allocator);
    const needle = try PHPString.init(allocator, "World");
    defer needle.release(allocator);

    const h = Value.initString(haystack);
    const n = Value.initString(needle);

    const result = try runtime.php_str_contains(h, n);
    try testing.expect(result.asBool());
}

test "字符串 - str_starts_with" {
    const allocator = testing.allocator;

    const str = try PHPString.init(allocator, "Hello World");
    defer str.release(allocator);
    const prefix = try PHPString.init(allocator, "Hello");
    defer prefix.release(allocator);

    const s = Value.initString(str);
    const p = Value.initString(prefix);

    const result = try runtime.php_str_starts_with(s, p);
    try testing.expect(result.asBool());
}

test "字符串 - str_ends_with" {
    const allocator = testing.allocator;

    const str = try PHPString.init(allocator, "Hello World");
    defer str.release(allocator);
    const suffix = try PHPString.init(allocator, "World");
    defer suffix.release(allocator);

    const s = Value.initString(str);
    const su = Value.initString(suffix);

    const result = try runtime.php_str_ends_with(s, su);
    try testing.expect(result.asBool());
}

// 测试数学函数
test "数学 - abs" {
    const neg = Value.initInt(-42);
    const result = try runtime.php_abs(neg);
    try testing.expectEqual(@as(i64, 42), result.asInt());
}

test "数学 - sqrt" {
    const val = Value.initInt(16);
    const result = try runtime.php_sqrt(val);
    try testing.expectApproxEqAbs(@as(f64, 4.0), result.asFloat(), 0.001);
}

test "数学 - round" {
    const val = Value.initFloat(3.7);
    const result = try runtime.php_round(val);
    try testing.expectApproxEqAbs(@as(f64, 4.0), result.asFloat(), 0.001);
}

test "数学 - floor" {
    const val = Value.initFloat(3.7);
    const result = try runtime.php_floor(val);
    try testing.expectApproxEqAbs(@as(f64, 3.0), result.asFloat(), 0.001);
}

test "数学 - ceil" {
    const val = Value.initFloat(3.2);
    const result = try runtime.php_ceil(val);
    try testing.expectApproxEqAbs(@as(f64, 4.0), result.asFloat(), 0.001);
}

test "数学 - min/max" {
    const a = Value.initInt(10);
    const b = Value.initInt(20);

    const min_result = try runtime.php_min(a, b);
    try testing.expectEqual(@as(i64, 10), min_result.asInt());

    const max_result = try runtime.php_max(a, b);
    try testing.expectEqual(@as(i64, 20), max_result.asInt());
}

test "数学 - sin/cos" {
    const pi = try runtime.php_pi();

    const sin_result = try runtime.php_sin(pi);
    try testing.expectApproxEqAbs(@as(f64, 0.0), sin_result.asFloat(), 0.0001);

    const cos_result = try runtime.php_cos(pi);
    try testing.expectApproxEqAbs(@as(f64, -1.0), cos_result.asFloat(), 0.0001);
}

test "数学 - log/exp" {
    const e = Value.initFloat(std.math.e);
    const log_result = try runtime.php_log(e);
    try testing.expectApproxEqAbs(@as(f64, 1.0), log_result.asFloat(), 0.0001);

    const one = Value.initInt(1);
    const exp_result = try runtime.php_exp(one);
    try testing.expectApproxEqAbs(std.math.e, exp_result.asFloat(), 0.0001);
}

test "数学 - pow函数" {
    const base = Value.initInt(2);
    const exp = Value.initInt(8);
    const result = try runtime.php_pow_func(base, exp);
    try testing.expectEqual(@as(i64, 256), result.asInt());
}

test "数学 - deg2rad/rad2deg" {
    const degrees = Value.initInt(180);
    const rad = try runtime.php_deg2rad(degrees);
    try testing.expectApproxEqAbs(std.math.pi, rad.asFloat(), 0.0001);

    const deg = try runtime.php_rad2deg(rad);
    try testing.expectApproxEqAbs(@as(f64, 180.0), deg.asFloat(), 0.0001);
}

// 测试类型检查
test "类型检查 - is_null" {
    const null_val = Value.initNull();
    const int_val = Value.initInt(42);

    const r1 = try runtime.php_is_null(null_val);
    try testing.expect(r1.asBool());

    const r2 = try runtime.php_is_null(int_val);
    try testing.expect(!r2.asBool());
}

test "类型检查 - is_bool" {
    const bool_val = Value.initBool(true);
    const int_val = Value.initInt(1);

    const r1 = try runtime.php_is_bool(bool_val);
    try testing.expect(r1.asBool());

    const r2 = try runtime.php_is_bool(int_val);
    try testing.expect(!r2.asBool());
}

test "类型检查 - is_int" {
    const int_val = Value.initInt(42);
    const float_val = Value.initFloat(42.0);

    const r1 = try runtime.php_is_int(int_val);
    try testing.expect(r1.asBool());

    const r2 = try runtime.php_is_int(float_val);
    try testing.expect(!r2.asBool());
}

test "类型检查 - is_float" {
    const float_val = Value.initFloat(3.14);
    const int_val = Value.initInt(3);

    const r1 = try runtime.php_is_float(float_val);
    try testing.expect(r1.asBool());

    const r2 = try runtime.php_is_float(int_val);
    try testing.expect(!r2.asBool());
}

test "类型检查 - is_string" {
    const allocator = testing.allocator;
    const str = try PHPString.init(allocator, "test");
    defer str.release(allocator);

    const str_val = Value.initString(str);
    const int_val = Value.initInt(42);

    const r1 = try runtime.php_is_string(str_val);
    try testing.expect(r1.asBool());

    const r2 = try runtime.php_is_string(int_val);
    try testing.expect(!r2.asBool());
}

test "类型检查 - is_numeric" {
    const allocator = testing.allocator;

    const int_val = Value.initInt(42);
    const r1 = try runtime.php_is_numeric(int_val);
    try testing.expect(r1.asBool());

    const float_val = Value.initFloat(3.14);
    const r2 = try runtime.php_is_numeric(float_val);
    try testing.expect(r2.asBool());

    const num_str = try PHPString.init(allocator, "123");
    defer num_str.release(allocator);
    const str_val = Value.initString(num_str);
    const r3 = try runtime.php_is_numeric(str_val);
    try testing.expect(r3.asBool());
}

// 测试类型转换
test "类型转换 - intval" {
    const float_val = Value.initFloat(3.7);
    const result = try runtime.php_intval(float_val);
    try testing.expectEqual(@as(i64, 3), result.asInt());
}

test "类型转换 - floatval" {
    const int_val = Value.initInt(42);
    const result = try runtime.php_floatval(int_val);
    try testing.expectApproxEqAbs(@as(f64, 42.0), result.asFloat(), 0.001);
}

test "类型转换 - boolval" {
    const zero = Value.initInt(0);
    const r1 = try runtime.php_boolval(zero);
    try testing.expect(!r1.asBool());

    const one = Value.initInt(1);
    const r2 = try runtime.php_boolval(one);
    try testing.expect(r2.asBool());
}

// 测试数组操作
test "数组 - 创建和count" {
    const allocator = testing.allocator;
    const arr = try PHPArray.init(allocator);
    defer arr.release(allocator);

    try arr.push(allocator, Value.initInt(1));
    try arr.push(allocator, Value.initInt(2));
    try arr.push(allocator, Value.initInt(3));

    const arr_val = Value.initArray(arr);
    const count = try runtime.php_count(arr_val);
    try testing.expectEqual(@as(i64, 3), count.asInt());
}

test "数组 - in_array" {
    const allocator = testing.allocator;
    const arr = try PHPArray.init(allocator);
    defer arr.release(allocator);

    try arr.push(allocator, Value.initInt(1));
    try arr.push(allocator, Value.initInt(2));
    try arr.push(allocator, Value.initInt(3));

    const arr_val = Value.initArray(arr);

    const r1 = try runtime.php_in_array(Value.initInt(2), arr_val);
    try testing.expect(r1.asBool());

    const r2 = try runtime.php_in_array(Value.initInt(5), arr_val);
    try testing.expect(!r2.asBool());
}

test "数组 - array_keys" {
    const allocator = testing.allocator;
    const arr = try PHPArray.init(allocator);
    defer arr.release(allocator);

    try arr.push(allocator, Value.initInt(10));
    try arr.push(allocator, Value.initInt(20));

    const arr_val = Value.initArray(arr);
    const keys = try runtime.php_array_keys(arr_val, allocator);
    defer keys.asArray().release(allocator);

    try testing.expectEqual(@as(usize, 2), keys.asArray().count());
}

test "数组 - array_values" {
    const allocator = testing.allocator;
    const arr = try PHPArray.init(allocator);
    defer arr.release(allocator);

    try arr.push(allocator, Value.initInt(10));
    try arr.push(allocator, Value.initInt(20));

    const arr_val = Value.initArray(arr);
    const values = try runtime.php_array_values(arr_val, allocator);
    defer values.asArray().release(allocator);

    try testing.expectEqual(@as(usize, 2), values.asArray().count());
}

test "高阶数组函数 - array_map with strtoupper" {
    const allocator = testing.allocator;
    const arr = try PHPArray.init(allocator);
    defer arr.release(allocator);

    const str1 = try PHPString.init(allocator, "hello");
    defer str1.release(allocator);
    const str2 = try PHPString.init(allocator, "world");
    defer str2.release(allocator);
    try arr.push(allocator, Value.initString(str1));
    try arr.push(allocator, Value.initString(str2));

    const arr_val = Value.initArray(arr);
    const callback_name = try PHPString.init(allocator, "strtoupper");
    defer callback_name.release(allocator);
    const callback = Value.initString(callback_name);

    const result = try runtime.php_array_map(callback, arr_val, allocator);
    defer result.asArray().release(allocator);

    try testing.expectEqual(@as(usize, 2), result.asArray().count());

    const first = result.asArray().get(.{ .integer = 0 }).?;
    defer first.release(allocator);
    try testing.expect(first.isString());
    try testing.expectEqualStrings("HELLO", first.asString().data);
}

test "高阶数组函数 - array_filter with callback" {
    const allocator = testing.allocator;
    const arr = try PHPArray.init(allocator);
    defer arr.release(allocator);

    try arr.push(allocator, Value.initInt(1));
    try arr.push(allocator, Value.initInt(0));
    try arr.push(allocator, Value.initInt(2));
    try arr.push(allocator, Value.initInt(0));
    try arr.push(allocator, Value.initInt(3));

    const arr_val = Value.initArray(arr);
    const result = try runtime.php_array_filter(arr_val, Value.initNull(), allocator);
    defer result.asArray().release(allocator);

    try testing.expectEqual(@as(usize, 3), result.asArray().count());
}

test "高阶数组函数 - array_reduce sum" {
    const allocator = testing.allocator;

    const add_func = struct {
        fn add(ctx: Value, args: []const Value, alloc: std.mem.Allocator) !Value {
            _ = ctx;
            _ = alloc;
            if (args.len < 2) return error.InvalidArgumentCount;
            return runtime.php_add(args[0], args[1]);
        }
    }.add;

    const php_func = try runtime.PHPClosure.init(allocator, add_func, &.{});
    defer php_func.release(allocator);
    const callback = Value.initFunction(php_func);

    const arr = try PHPArray.init(allocator);
    defer arr.release(allocator);
    try arr.push(allocator, Value.initInt(1));
    try arr.push(allocator, Value.initInt(2));
    try arr.push(allocator, Value.initInt(3));
    try arr.push(allocator, Value.initInt(4));

    const arr_val = Value.initArray(arr);
    const result = try runtime.php_array_reduce(arr_val, callback, Value.initInt(0), allocator);

    try testing.expect(result.isInt());
    try testing.expectEqual(@as(i64, 10), result.asInt());
}
