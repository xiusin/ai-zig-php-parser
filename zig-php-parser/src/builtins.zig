const std = @import("std");

pub const BuiltinType = enum { string, array, global };

pub const BuiltinFunc = struct {
    name: []const u8,
    type: BuiltinType,
    is_method: bool,
};

// 使用 Zig 的静态优化，在编译时或初始化时确定的内置函数表
pub const registry = [_]BuiltinFunc{
    // 字符串函数
    .{ .name = "strlen", .type = .string, .is_method = false },
    .{ .name = "substr", .type = .string, .is_method = false },
    .{ .name = "strpos", .type = .string, .is_method = false },
    .{ .name = "strtoupper", .type = .string, .is_method = false },
    .{ .name = "strtolower", .type = .string, .is_method = false },
    .{ .name = "trim", .type = .string, .is_method = false },
    .{ .name = "ltrim", .type = .string, .is_method = false },
    .{ .name = "rtrim", .type = .string, .is_method = false },
    .{ .name = "str_replace", .type = .string, .is_method = false },
    .{ .name = "str_repeat", .type = .string, .is_method = false },
    .{ .name = "str_pad", .type = .string, .is_method = false },
    .{ .name = "strrev", .type = .string, .is_method = false },
    .{ .name = "str_contains", .type = .string, .is_method = false },
    .{ .name = "str_starts_with", .type = .string, .is_method = false },
    .{ .name = "str_ends_with", .type = .string, .is_method = false },
    .{ .name = "ucfirst", .type = .string, .is_method = false },
    .{ .name = "lcfirst", .type = .string, .is_method = false },
    .{ .name = "ucwords", .type = .string, .is_method = false },
    .{ .name = "explode", .type = .string, .is_method = false },
    .{ .name = "implode", .type = .string, .is_method = false },
    .{ .name = "str_split", .type = .string, .is_method = false },
    .{ .name = "strcmp", .type = .string, .is_method = false },
    .{ .name = "strcasecmp", .type = .string, .is_method = false },
    
    // 字符串方法
    .{ .name = "length", .type = .string, .is_method = true },
    .{ .name = "contains", .type = .string, .is_method = true },
    
    // 数组函数
    .{ .name = "count", .type = .array, .is_method = true },
    .{ .name = "array_merge", .type = .array, .is_method = false },
    .{ .name = "array_push", .type = .array, .is_method = false },
    .{ .name = "array_pop", .type = .array, .is_method = false },
    .{ .name = "in_array", .type = .array, .is_method = false },
    .{ .name = "array_keys", .type = .array, .is_method = false },
    .{ .name = "array_values", .type = .array, .is_method = false },
    .{ .name = "array_slice", .type = .array, .is_method = false },
    
    // 数学函数
    .{ .name = "abs", .type = .global, .is_method = false },
    .{ .name = "sqrt", .type = .global, .is_method = false },
    .{ .name = "round", .type = .global, .is_method = false },
    .{ .name = "floor", .type = .global, .is_method = false },
    .{ .name = "ceil", .type = .global, .is_method = false },
    .{ .name = "min", .type = .global, .is_method = false },
    .{ .name = "max", .type = .global, .is_method = false },
    .{ .name = "sin", .type = .global, .is_method = false },
    .{ .name = "cos", .type = .global, .is_method = false },
    .{ .name = "tan", .type = .global, .is_method = false },
    .{ .name = "asin", .type = .global, .is_method = false },
    .{ .name = "acos", .type = .global, .is_method = false },
    .{ .name = "atan", .type = .global, .is_method = false },
    .{ .name = "atan2", .type = .global, .is_method = false },
    .{ .name = "log", .type = .global, .is_method = false },
    .{ .name = "log10", .type = .global, .is_method = false },
    .{ .name = "exp", .type = .global, .is_method = false },
    .{ .name = "pow", .type = .global, .is_method = false },
    .{ .name = "fmod", .type = .global, .is_method = false },
    .{ .name = "hypot", .type = .global, .is_method = false },
    .{ .name = "deg2rad", .type = .global, .is_method = false },
    .{ .name = "rad2deg", .type = .global, .is_method = false },
    .{ .name = "pi", .type = .global, .is_method = false },
    .{ .name = "rand", .type = .global, .is_method = false },
    .{ .name = "mt_rand", .type = .global, .is_method = false },
    
    // 时间函数
    .{ .name = "time", .type = .global, .is_method = false },
    .{ .name = "microtime", .type = .global, .is_method = false },
    .{ .name = "date", .type = .global, .is_method = false },
    
    // 随机数函数
    .{ .name = "srand", .type = .global, .is_method = false },
    .{ .name = "mt_srand", .type = .global, .is_method = false },
    .{ .name = "random_int", .type = .global, .is_method = false },
    .{ .name = "random_bytes", .type = .global, .is_method = false },
    
    // 类型转换函数
    .{ .name = "intval", .type = .global, .is_method = false },
    .{ .name = "floatval", .type = .global, .is_method = false },
    .{ .name = "boolval", .type = .global, .is_method = false },
    .{ .name = "strval", .type = .global, .is_method = false },
};

pub fn isBuiltinMethod(name: []const u8) bool {
    for (registry) |f| {
        if (f.is_method and std.mem.eql(u8, f.name, name)) return true;
    }
    return false;
}
