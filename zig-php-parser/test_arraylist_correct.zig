const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 正确的方式：使用 initCapacity 或者直接传递 allocator
    var list = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer list.deinit();
    
    try list.append(1);
    try list.append(2);
    try list.append(3);
    
    std.debug.print("ArrayList 长度: {}\n", .{list.items.len});
    std.debug.print("内容: {any}\n", .{list.items});
}
