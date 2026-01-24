const std = @import("std");

pub fn main() !void {
    // Zig 0.15.2 正确的stdout API
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("Test\n");
}
