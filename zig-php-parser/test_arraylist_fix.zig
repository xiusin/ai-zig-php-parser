const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试新的 ArrayList 初始化方式
    var list1 = std.ArrayList(u8){ .allocator = allocator };
    defer list1.deinit();
    
    try list1.append(1);
    try list1.append(2);
    try list1.append(3);
    
    std.debug.print("ArrayList 修复成功！列表长度: {}\n", .{list1.items.len});
    
    // 测试 ArrayListUnmanaged
    var list2 = std.ArrayListUnmanaged(u32){};
    defer list2.deinit(allocator);
    
    try list2.append(allocator, 10);
    try list2.append(allocator, 20);
    
    std.debug.print("ArrayListUnmanaged 修复成功！列表长度: {}\n", .{list2.items.len});
}
