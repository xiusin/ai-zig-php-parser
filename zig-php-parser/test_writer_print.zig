const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);
    
    const writer = list.writer(allocator);
    
    // 测试writeAll
    try writer.writeAll("Hello, ");
    std.debug.print("After writeAll\n", .{});
    
    // 测试print
    try writer.print("World {d}!\n", .{42});
    std.debug.print("After print\n", .{});
    
    std.debug.print("Result: {s}\n", .{list.items});
}
