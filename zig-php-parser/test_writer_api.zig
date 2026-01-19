const std = @import("std");

test "check writer API" {
    const file = try std.fs.cwd().createFile("test_output.txt", .{});
    defer file.close();
    defer std.fs.cwd().deleteFile("test_output.txt") catch {};
    
    const writer = file.writer();
    const T = @TypeOf(writer);
    std.debug.print("\nWriter type: {s}\n", .{@typeName(T)});
    
    // 测试 write 方法
    _ = try writer.write("Hello\n");
    
    // 测试 print 方法
    try writer.print("Number: {d}\n", .{42});
}
