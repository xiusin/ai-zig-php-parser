const std = @import("std");

pub const BuiltinType = enum { string, array, global };

pub const BuiltinFunc = struct {
    name: []const u8,
    type: BuiltinType,
    is_method: bool,
};

// 使用 Zig 的静态优化，在编译时或初始化时确定的内置函数表
pub const registry = [_]BuiltinFunc{
    .{ .name = "strlen", .type = .string, .is_method = false },
    .{ .name = "length", .type = .string, .is_method = true }, // 支持 $str->length()
    .{ .name = "contains", .type = .string, .is_method = true },
    .{ .name = "count", .type = .array, .is_method = true },
    .{ .name = "array_merge", .type = .array, .is_method = false },
    .{ .name = "explode", .type = .global, .is_method = false },
};

pub fn isBuiltinMethod(name: []const u8) bool {
    for (registry) |f| {
        if (f.is_method and std.mem.eql(u8, f.name, name)) return true;
    }
    return false;
}
