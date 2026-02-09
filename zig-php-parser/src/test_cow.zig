const std = @import("std");
const testing = std.testing;
const cow = @import("memory/cow.zig");
const CowString = cow.CowString;
const CowArray = cow.CowArray;

// Feature: advanced-compiler-optimization, Property 24: Copy-on-Write 延迟复制
test "CoW string - delays copy until modification" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var str1 = try CowString.init(allocator, "hello");
        defer str1.deinit();
        
        var str2 = str1.share();
        defer str2.deinit();
        
        // 验证：共享相同数据
        try testing.expect(str1.data.ptr == str2.data.ptr);
        
        // 修改时创建副本
        const mutable = try str2.makeMutable();
        mutable[0] = 'H';
        
        // 验证：数据不再共享
        try testing.expect(str1.data.ptr != str2.data.ptr);
        try testing.expect(str1.data[0] == 'h');
        try testing.expect(str2.data[0] == 'H');
    }
}

// 测试 CoW 数组
test "CoW array - delays copy until modification" {
    const allocator = testing.allocator;
    
    const arr = [_]i32{ 1, 2, 3 };
    var arr1 = try CowArray.init(allocator, &arr);
    defer arr1.deinit();
    
    var arr2 = arr1.share();
    defer arr2.deinit();
    
    // 验证：共享相同数据
    try testing.expect(arr1.elements.ptr == arr2.elements.ptr);
    
    // 修改时创建副本
    const mutable = try arr2.makeMutable();
    mutable[0] = 10;
    
    // 验证：数据不再共享
    try testing.expect(arr1.elements.ptr != arr2.elements.ptr);
    try testing.expect(arr1.elements[0] == 1);
    try testing.expect(arr2.elements[0] == 10);
}

// 测试引用计数
test "CoW reference counting - correctly tracks references" {
    const allocator = testing.allocator;
    
    var str1 = try CowString.init(allocator, "test");
    defer str1.deinit();
    
    try testing.expect(str1.ref_count.load(.monotonic) == 1);
    
    var str2 = str1.share();
    try testing.expect(str1.ref_count.load(.monotonic) == 2);
    
    str2.deinit();
    try testing.expect(str1.ref_count.load(.monotonic) == 1);
}

// 测试多次共享
test "CoW multiple shares - handles multiple references" {
    const allocator = testing.allocator;
    
    var str1 = try CowString.init(allocator, "shared");
    defer str1.deinit();
    
    var str2 = str1.share();
    defer str2.deinit();
    
    var str3 = str1.share();
    defer str3.deinit();
    
    try testing.expect(str1.ref_count.load(.monotonic) == 3);
    try testing.expect(str1.data.ptr == str2.data.ptr);
    try testing.expect(str1.data.ptr == str3.data.ptr);
}

// 测试单一所有者不复制
test "CoW single owner - no copy on modification" {
    const allocator = testing.allocator;
    
    var str = try CowString.init(allocator, "hello");
    defer str.deinit();
    
    const original_ptr = str.data.ptr;
    
    // 单一所有者修改不复制
    const mutable = try str.makeMutable();
    mutable[0] = 'H';
    
    try testing.expect(str.data.ptr == original_ptr);
}
