const std = @import("std");

pub fn main() !void {
    // 方法3: 使用 buffered writer
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buf: [4096]u8 = undefined;
    const stdout = stdout_file.writer(&buf);
    try stdout.writeAll("Test 3: buffered writer\n");
}
