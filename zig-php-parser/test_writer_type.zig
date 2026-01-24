const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);
    
    const writer = list.writer(allocator);
    std.debug.print("Writer type: {s}\n", .{@typeName(@TypeOf(writer))});
    
    // 测试传递writer到函数
    try testWriter(writer);
    std.debug.print("Result: {s}\n", .{list.items});
}

fn testWriter(writer: anytype) !void {
    try writer.writeAll("Hello from function!\n");
}
