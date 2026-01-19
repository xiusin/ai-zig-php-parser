const std = @import("std");

const MyStruct = struct {
    value: i32,
};

test "ArrayList init correct" {
    const allocator = std.testing.allocator;
    
    // 正确方式：使用 init 作为类型的方法
    const ArrayList = std.ArrayList(MyStruct);
    var list1 = ArrayList.init(allocator);
    defer list1.deinit();
    
    try std.testing.expect(true);
}
