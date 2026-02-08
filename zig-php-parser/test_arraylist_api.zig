const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试方式1：空初始化
    var list1 = std.ArrayList(u8){};
    list1.allocator = allocator;
    defer list1.deinit();
    
    try list1.append(1);
    std.debug.print("方式1成功\n", .{});
    
    // 测试方式2：使用 initCapacity
    var list2 = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer list2.deinit();
    
    try list2.append(2);
    std.debug.print("方式2成功\n", .{});
}
