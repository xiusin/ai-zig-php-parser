const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试ArrayList.writer在Zig 0.15.2中的正确用法
    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);
    
    const writer = list.writer(allocator);
    try writer.writeAll("Hello, ");
    try writer.writeAll("World!\n");
    
    std.debug.print("{s}", .{list.items});
}
