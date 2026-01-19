const std = @import("std");

test "ArrayList init" {
    const allocator = std.testing.allocator;
    var list: std.ArrayList(u8) = .{};
    list.allocator = allocator;
    defer list.deinit();
    
    try list.append(42);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
}
