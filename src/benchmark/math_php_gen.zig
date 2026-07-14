//! PHP 测试脚本生成器
//! 为数学运算测试生成对应的 PHP 脚本

const std = @import("std");

/// 生成 PHP 脚本的通用模板
pub fn generatePhpScript(
    allocator: std.mem.Allocator,
    output_path: []const u8,
    test_name: []const u8,
    iterations: u32,
    code: []const u8,
) !void {
    const file = try std.fs.cwd.createFile(output_path, .{});
    defer file.close();

    const writer = file.writer();

    try writer.writeAll("<?php\n");
    try writer.print("// {s} - PHP 性能测试\n", .{test_name});
    try writer.print("// 迭代次数: {d}\n\n", .{iterations});
    try writer.writeAll("$iterations = ");
    try writer.print("{d};\n\n", .{iterations});
    try writer.writeAll(code);
    try writer.writeAll("\n?>\n");

    _ = allocator;
}
