const std = @import("std");

const MyStruct = struct {
    value: i32,
};

test "ArrayList init" {
    const allocator = std.testing.allocator;
    
    // 方式 1: 直接初始化
    var list1 = std.ArrayList(MyStruct).init(allocator);
    defer list1.deinit();
    
    // 方式 2: 在结构体中
    const S = struct {
        list: std.ArrayList(MyStruct),
    };
    
    var s: S = undefined;
    s.list = std.ArrayList(MyStruct).init(allocator);
    defer s.list.deinit();
    
    try std.testing.expect(true);
}
