const std = @import("std");

test "simple" {
    const allocator = std.testing.allocator;
    const ArrayList = std.ArrayList(u8);
    var list = ArrayList.init(allocator);
    defer list.deinit();
    
    try list.append(42);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
}
