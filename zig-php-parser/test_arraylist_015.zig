const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Zig 0.15.2 的正确方式
    var list = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer list.deinit();
    
    // append 现在需要传递 allocator
    try list.append(allocator, 1);
    try list.append(allocator, 2);
    try list.append(allocator, 3);
    
    std.debug.print("ArrayList 长度: {}\n", .{list.items.len});
    std.debug.print("内容: {any}\n", .{list.items});
}
