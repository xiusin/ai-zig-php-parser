const std = @import("std");
const testing = std.testing;
const advanced_memory = @import("advanced_memory.zig");

// 测试 Compactor 的完整实现
test "Compactor full implementation" {
    std.debug.print("\n=== Compactor Full Implementation Test ===\n", .{});

    var compactor = advanced_memory.Compactor.init(testing.allocator);
    defer compactor.deinit();

    // 创建一个内存区域
    var region = try advanced_memory.Compactor.MemoryRegion.init(testing.allocator, 4096);
    defer region.deinit(testing.allocator);

    // 添加一些对象
    try region.objects.append(testing.allocator, .{
        .offset = 0,
        .size = 100,
        .marked = false,
        .forwarding_address = null,
    });

    try region.objects.append(testing.allocator, .{
        .offset = 100,
        .size = 200,
        .marked = false,
        .forwarding_address = null,
    });

    try region.objects.append(testing.allocator, .{
        .offset = 300,
        .size = 150,
        .marked = false,
        .forwarding_address = null,
    });

    region.used = 450;

    // 添加区域到 compactor
    try compactor.memory_regions.append(testing.allocator, region);

    // 执行压缩
    try compactor.compact();

    // 验证统计信息
    const stats = compactor.compaction_stats;
    try testing.expect(stats.total_compactions >= 1);

    std.debug.print("Compaction stats:\n", .{});
    std.debug.print("  Total compactions: {d}\n", .{stats.total_compactions});
    std.debug.print("  Bytes reclaimed: {d}\n", .{stats.bytes_reclaimed});
    std.debug.print("  Fragmentation reduced: {d:.2}%\n", .{stats.fragmentation_reduced * 100});
}

// 测试空闲列表的合并功能
test "FreeList coalescing" {
    std.debug.print("\n=== FreeList Coalescing Test ===\n", .{});

    var free_list = advanced_memory.Compactor.FreeList.init();
    defer free_list.deinit(testing.allocator);

    // 添加一些空闲块（包括相邻的）
    try free_list.free(1000, 100, testing.allocator);
    try free_list.free(1100, 200, testing.allocator); // 相邻
    try free_list.free(1500, 150, testing.allocator); // 不相邻
    try free_list.free(1300, 200, testing.allocator); // 相邻

    std.debug.print("Before coalescing: {d} blocks\n", .{free_list.blocks.items.len});

    // 合并相邻块
    try free_list.coalesce(testing.allocator);

    std.debug.print("After coalescing: {d} blocks\n", .{free_list.blocks.items.len});

    // 验证合并后的块数量减少
    try testing.expect(free_list.blocks.items.len < 4);

    // 验证总空闲空间不变
    var total_size: usize = 0;
    for (free_list.blocks.items) |block| {
        total_size += block.size;
    }
    try testing.expectEqual(@as(usize, 650), total_size);
}

// 测试空闲列表的分配功能
test "FreeList allocation" {
    std.debug.print("\n=== FreeList Allocation Test ===\n", .{});

    var free_list = advanced_memory.Compactor.FreeList.init();
    defer free_list.deinit(testing.allocator);

    // 添加空闲块
    try free_list.free(1000, 500, testing.allocator);
    try free_list.free(2000, 300, testing.allocator);

    // 分配内存
    const addr1 = free_list.allocate(100, testing.allocator);
    try testing.expect(addr1 != null);
    std.debug.print("Allocated 100 bytes at: {d}\n", .{addr1.?});

    const addr2 = free_list.allocate(200, testing.allocator);
    try testing.expect(addr2 != null);
    std.debug.print("Allocated 200 bytes at: {d}\n", .{addr2.?});

    // 尝试分配超过可用空间的内存
    const addr3 = free_list.allocate(1000, testing.allocator);
    try testing.expect(addr3 == null);
    std.debug.print("Failed to allocate 1000 bytes (expected)\n", .{});
}

// 测试碎片率计算
test "Fragmentation calculation" {
    std.debug.print("\n=== Fragmentation Calculation Test ===\n", .{});

    var compactor = advanced_memory.Compactor.init(testing.allocator);
    defer compactor.deinit();

    // 添加一些空闲块（高碎片）
    try compactor.free_list.free(1000, 100, testing.allocator);
    try compactor.free_list.free(2000, 50, testing.allocator);
    try compactor.free_list.free(3000, 75, testing.allocator);
    try compactor.free_list.free(4000, 25, testing.allocator);

    const frag_before = try compactor.calculateFragmentation();
    std.debug.print("Fragmentation before coalescing: {d:.2}%\n", .{frag_before * 100});

    // 合并后碎片率应该降低
    try compactor.free_list.coalesce(testing.allocator);

    const frag_after = try compactor.calculateFragmentation();
    std.debug.print("Fragmentation after coalescing: {d:.2}%\n", .{frag_after * 100});

    // 验证碎片率降低
    try testing.expect(frag_after <= frag_before);
}

// 性能测试：压缩操作的时间复杂度
test "Compaction performance scaling" {
    std.debug.print("\n=== Compaction Performance Scaling Test ===\n", .{});

    const sizes = [_]usize{ 10, 50, 100, 500 };

    for (sizes) |size| {
        var compactor = advanced_memory.Compactor.init(testing.allocator);
        defer compactor.deinit();

        // 创建内存区域
        var region = try advanced_memory.Compactor.MemoryRegion.init(testing.allocator, size * 1000);
        defer region.deinit(testing.allocator);

        // 添加对象
        var offset: usize = 0;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            try region.objects.append(testing.allocator, .{
                .offset = offset,
                .size = 100,
                .marked = true,
                .forwarding_address = null,
            });
            offset += 100;
        }
        region.used = offset;

        try compactor.memory_regions.append(testing.allocator, region);

        // 测量压缩时间
        const start = std.time.nanoTimestamp();
        try compactor.compact();
        const end = std.time.nanoTimestamp();

        const duration_ns = end - start;
        const duration_us = @divTrunc(duration_ns, 1000);

        std.debug.print("Size: {d:4} objects, Time: {d:6} μs\n", .{ size, duration_us });
    }
}
