const std = @import("std");
const testing = std.testing;
const allocators = @import("memory/allocators.zig");
const ArenaAllocator = allocators.ArenaAllocator;
const SlabAllocator = allocators.SlabAllocator;
const BumpAllocator = allocators.BumpAllocator;

// Feature: advanced-compiler-optimization, Property 25: 内存池分配正确性
test "arena allocator - allocates and resets" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var arena = try ArenaAllocator.init(allocator, 1024);
        defer arena.deinit();
        
        const ptr1 = try arena.alloc(64);
        try testing.expect(ptr1.len == 64);
        
        const ptr2 = try arena.alloc(128);
        try testing.expect(ptr2.len == 128);
        
        // 重置后可重新分配
        arena.reset();
        const ptr3 = try arena.alloc(64);
        try testing.expect(ptr3.ptr == ptr1.ptr);
    }
}

// 测试 Slab 分配器
test "slab allocator - allocates fixed size objects" {
    const allocator = testing.allocator;
    
    var slab = try SlabAllocator.init(allocator, 32);
    defer slab.deinit();
    
    const ptr1 = try slab.alloc();
    try testing.expect(ptr1.len == 32);
    
    const ptr2 = try slab.alloc();
    try testing.expect(ptr2.len == 32);
    
    // 验证：不同的内存块
    try testing.expect(ptr1.ptr != ptr2.ptr);
}

// 测试 Bump 分配器
test "bump allocator - sequential allocation" {
    const allocator = testing.allocator;
    
    var bump = try BumpAllocator.init(allocator, 1024);
    defer bump.deinit();
    
    const ptr1 = try bump.alloc(64);
    const ptr2 = try bump.alloc(64);
    
    // 验证：连续分配
    try testing.expect(@intFromPtr(ptr2.ptr) == @intFromPtr(ptr1.ptr) + 64);
}

// 测试 Arena 溢出
test "arena allocator - handles overflow" {
    const allocator = testing.allocator;
    
    var arena = try ArenaAllocator.init(allocator, 100);
    defer arena.deinit();
    
    _ = try arena.alloc(50);
    
    // 尝试分配超过剩余空间
    const result = arena.alloc(100);
    try testing.expectError(error.OutOfMemory, result);
}

// 测试 Bump 重置
test "bump allocator - reset works correctly" {
    const allocator = testing.allocator;
    
    var bump = try BumpAllocator.init(allocator, 1024);
    defer bump.deinit();
    
    _ = try bump.alloc(512);
    try testing.expect(bump.offset == 512);
    
    bump.reset();
    try testing.expect(bump.offset == 0);
}
