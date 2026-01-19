const std = @import("std");

test "check File.Writer methods" {
    var buffer: [1024]u8 = undefined;
    const file = try std.fs.cwd().createFile("test.txt", .{});
    defer file.close();
    defer std.fs.cwd().deleteFile("test.txt") catch {};
    
    const writer = file.writer(&buffer);
    
    // 测试 print 方法
    try writer.print("Hello {s}\n", .{"World"});
    
    std.debug.print("\nWriter type info:\n", .{});
    std.debug.print("Type: {s}\n", .{@typeName(@TypeOf(writer))});
}
