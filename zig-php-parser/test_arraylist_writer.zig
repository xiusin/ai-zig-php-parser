const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试ArrayList writer的正确用法
    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);
    
    // 尝试不同的writer获取方式
    const writer = list.writer(allocator);
    try writer.writeAll("Hello, World!\n");
    
    const slice = try list.toOwnedSlice(allocator);
    defer allocator.free(slice);
    
    std.debug.print("{s}", .{slice});
}
