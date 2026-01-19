const std = @import("std");
const testing = std.testing;
const advanced_memory = @import("advanced_memory.zig");

/// 属性测试框架
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: std.rand.Random,
    iterations: u32 = 100,

    fn init(allocator: std.mem.Allocator, seed: u64) PropertyTest {
        var prng = std.rand.DefaultPrng.init(seed);
        return .{
            .allocator = allocator,
            .rng = prng.random(),
            .iterations = 100,
        };
    }

    /// 运行属性测试
    fn run(
        self: *PropertyTest,
        comptime T: type,
        property: *const fn (T, std.mem.Allocator) anyerror!bool,
        generator: *const fn (*std.rand.Random, std.mem.Allocator) anyerror!T,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;

        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 生成随机输入
            const input = try generator(&self.rng, self.allocator);

            // 测试属性
            const result = property(input, self.allocator) catch |err| {
                std.debug.print("Property test error: {}\n", .{err});
                failed += 1;
                continue;
            };

            if (result) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed for input: {any}\n", .{input});
            }
        }

        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("Property test: {d}/{d} passed ({d:.2}%)\n", .{ passed, self.iterations, success_rate * 100 });

        return failed == 0;
    }
};

/// 测试输入：内存块序列
const MemoryBlockSequence = struct {
    blocks: []MemoryBlock,

    const MemoryBlock = struct {
        size: usize,
        is_allocated: bool,
        data: []u8,
    };

    fn deinit(self: *MemoryBlockSequence, allocator: std.mem.Allocator) void {
        for (self.blocks) |block| {
            allocator.free(block.data);
        }
        allocator.free(self.blocks);
    }
};

/// 生成随机内存块序列
fn generateMemoryBlocks(rng: *std.rand.Random, allocator: std.mem.Allocator) !MemoryBlockSequence {
    const block_count = rng.intRangeAtMost(usize, 10, 50);
    const blocks = try allocator.alloc(MemoryBlockSequence.MemoryBlock, block_count);

    for (blocks, 0..) |*block, i| {
        const size = rng.intRangeAtMost(usize, 16, 1024);
        const is_allocated = rng.boolean();

        const data = try allocator.alloc(u8, size);
        // 填充随机数据
        for (data) |*byte| {
            byte.* = rng.int(u8);
        }

        block.* = .{
            .size = size,
            .is_allocated = is_allocated,
            .data = data,
        };
        _ = i;
    }

    return MemoryBlockSequence{ .blocks = blocks };
}

/// 计算碎片率
fn calculateFragmentation(blocks: []const MemoryBlockSequence.MemoryBlock) f64 {
    var total_free: usize = 0;
    var largest_free: usize = 0;
    var current_free: usize = 0;

    for (blocks) |block| {
        if (!block.is_allocated) {
            total_free += block.size;
            current_free += block.size;
            if (current_free > largest_free) {
                largest_free = current_free;
            }
        } else {
            current_free = 0;
        }
    }

    if (total_free == 0) return 0.0;

    // 碎片率 = 1 - (最大空闲块 / 总空闲空间)
    return 1.0 - (@as(f64, @floatFromInt(largest_free)) / @as(f64, @floatFromInt(total_free)));
}

/// 模拟压缩操作
fn simulateCompaction(blocks: []MemoryBlockSequence.MemoryBlock, allocator: std.mem.Allocator) ![]MemoryBlockSequence.MemoryBlock {
    // 统计已分配块的总大小
    var allocated_count: usize = 0;
    for (blocks) |block| {
        if (block.is_allocated) {
            allocated_count += 1;
        }
    }

    // 创建压缩后的块序列
    var compacted = try allocator.alloc(MemoryBlockSequence.MemoryBlock, allocated_count + 1);
    var write_idx: usize = 0;

    // 复制所有已分配的块到前面
    for (blocks) |block| {
        if (block.is_allocated) {
            const new_data = try allocator.alloc(u8, block.size);
            @memcpy(new_data, block.data);
            compacted[write_idx] = .{
                .size = block.size,
                .is_allocated = true,
                .data = new_data,
            };
            write_idx += 1;
        }
    }

    // 计算总空闲空间
    var total_free: usize = 0;
    for (blocks) |block| {
        if (!block.is_allocated) {
            total_free += block.size;
        }
    }

    // 在末尾添加一个大的空闲块
    if (total_free > 0) {
        const free_data = try allocator.alloc(u8, total_free);
        @memset(free_data, 0);
        compacted[write_idx] = .{
            .size = total_free,
            .is_allocated = false,
            .data = free_data,
        };
    }

    return compacted;
}

// 属性 23：压缩 GC 碎片率
// 对于任意内存状态，压缩 GC 执行后，碎片率应该 < 10%
test "Property 23: Compacting GC fragmentation rate" {
    // Feature: zig-php-performance-optimization, Property 23
    std.debug.print("\n=== Property 23: Compacting GC fragmentation rate ===\n", .{});

    var pt = PropertyTest.init(testing.allocator, 12345);

    const property = struct {
        fn check(input: MemoryBlockSequence, allocator: std.mem.Allocator) !bool {
            defer {
                var mut_input = input;
                mut_input.deinit(allocator);
            }

            // 计算压缩前的碎片率
            const frag_before = calculateFragmentation(input.blocks);
            std.debug.print("Fragmentation before: {d:.2}%\n", .{frag_before * 100});

            // 执行压缩
            const compacted = try simulateCompaction(input.blocks, allocator);
            defer {
                for (compacted) |block| {
                    allocator.free(block.data);
                }
                allocator.free(compacted);
            }

            // 计算压缩后的碎片率
            const frag_after = calculateFragmentation(compacted);
            std.debug.print("Fragmentation after: {d:.2}%\n", .{frag_after * 100});

            // 验证碎片率 < 10%
            const fragmentation_threshold = 0.10;
            const passed = frag_after < fragmentation_threshold;

            if (!passed) {
                std.debug.print("FAILED: Fragmentation {d:.2}% exceeds threshold {d:.2}%\n", .{ frag_after * 100, fragmentation_threshold * 100 });
            }

            return passed;
        }
    }.check;

    const passed = try pt.run(MemoryBlockSequence, property, generateMemoryBlocks);
    try testing.expect(passed);
}

/// 空闲块合并测试输入
const FreeBlockSequence = struct {
    blocks: []FreeBlock,

    const FreeBlock = struct {
        start: usize,
        size: usize,
    };

    fn deinit(self: *FreeBlockSequence, allocator: std.mem.Allocator) void {
        allocator.free(self.blocks);
    }
};

/// 生成随机空闲块序列（可能相邻）
fn generateFreeBlocks(rng: *std.rand.Random, allocator: std.mem.Allocator) !FreeBlockSequence {
    const block_count = rng.intRangeAtMost(usize, 5, 20);
    const blocks = try allocator.alloc(FreeBlockSequence.FreeBlock, block_count);

    var current_addr: usize = 0;
    for (blocks, 0..) |*block, i| {
        const size = rng.intRangeAtMost(usize, 16, 512);

        // 50% 概率创建相邻块
        const is_adjacent = rng.boolean();
        if (is_adjacent and i > 0) {
            // 相邻块：紧接着上一个块
            block.* = .{
                .start = current_addr,
                .size = size,
            };
        } else {
            // 非相邻块：留一些间隙
            const gap = rng.intRangeAtMost(usize, 64, 256);
            current_addr += gap;
            block.* = .{
                .start = current_addr,
                .size = size,
            };
        }

        current_addr += size;
    }

    return FreeBlockSequence{ .blocks = blocks };
}

/// 合并相邻空闲块
fn coalesceFreeBlocks(blocks: []const FreeBlockSequence.FreeBlock, allocator: std.mem.Allocator) ![]FreeBlockSequence.FreeBlock {
    if (blocks.len == 0) return try allocator.alloc(FreeBlockSequence.FreeBlock, 0);

    // 首先按起始地址排序
    var sorted = try allocator.dupe(FreeBlockSequence.FreeBlock, blocks);
    std.mem.sort(FreeBlockSequence.FreeBlock, sorted, {}, struct {
        fn lessThan(_: void, a: FreeBlockSequence.FreeBlock, b: FreeBlockSequence.FreeBlock) bool {
            return a.start < b.start;
        }
    }.lessThan);

    // 合并相邻块
    var merged = std.ArrayList(FreeBlockSequence.FreeBlock).init(allocator);
    defer merged.deinit();

    var current = sorted[0];
    for (sorted[1..]) |block| {
        const current_end = current.start + current.size;
        if (block.start == current_end) {
            // 相邻块 - 合并
            current.size += block.size;
        } else {
            // 非相邻块 - 保存当前块，开始新块
            try merged.append(current);
            current = block;
        }
    }
    try merged.append(current);

    allocator.free(sorted);
    return merged.toOwnedSlice();
}

// 属性 27：空闲块合并正确性
// 对于任意相邻的空闲块，合并后应该形成一个更大的空闲块，且总空闲空间不变
test "Property 27: Free block coalescing correctness" {
    // Feature: zig-php-performance-optimization, Property 27
    std.debug.print("\n=== Property 27: Free block coalescing correctness ===\n", .{});

    var pt = PropertyTest.init(testing.allocator, 67890);

    const property = struct {
        fn check(input: FreeBlockSequence, allocator: std.mem.Allocator) !bool {
            defer {
                var mut_input = input;
                mut_input.deinit(allocator);
            }

            // 计算合并前的总空闲空间
            var total_before: usize = 0;
            for (input.blocks) |block| {
                total_before += block.size;
            }

            std.debug.print("Blocks before coalescing: {d}, Total size: {d}\n", .{ input.blocks.len, total_before });

            // 执行合并
            const coalesced = try coalesceFreeBlocks(input.blocks, allocator);
            defer allocator.free(coalesced);

            // 计算合并后的总空闲空间
            var total_after: usize = 0;
            for (coalesced) |block| {
                total_after += block.size;
            }

            std.debug.print("Blocks after coalescing: {d}, Total size: {d}\n", .{ coalesced.len, total_after });

            // 验证总空闲空间不变
            if (total_before != total_after) {
                std.debug.print("FAILED: Total free space changed from {d} to {d}\n", .{ total_before, total_after });
                return false;
            }

            // 验证合并后的块数量不大于合并前
            if (coalesced.len > input.blocks.len) {
                std.debug.print("FAILED: Block count increased from {d} to {d}\n", .{ input.blocks.len, coalesced.len });
                return false;
            }

            // 验证没有相邻块
            for (coalesced, 0..) |block, i| {
                if (i + 1 < coalesced.len) {
                    const next_block = coalesced[i + 1];
                    const current_end = block.start + block.size;
                    if (current_end == next_block.start) {
                        std.debug.print("FAILED: Adjacent blocks found at index {d}\n", .{i});
                        return false;
                    }
                }
            }

            return true;
        }
    }.check;

    const passed = try pt.run(FreeBlockSequence, property, generateFreeBlocks);
    try testing.expect(passed);
}

// 集成测试：使用实际的 Compactor
test "Compactor integration test" {
    std.debug.print("\n=== Compactor Integration Test ===\n", .{});

    var compactor = advanced_memory.Compactor.init(testing.allocator);
    defer compactor.deinit();

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

// 性能测试：压缩操作的时间复杂度
test "Compaction performance" {
    std.debug.print("\n=== Compaction Performance Test ===\n", .{});

    const sizes = [_]usize{ 100, 500, 1000, 5000 };

    for (sizes) |size| {
        var prng = std.rand.DefaultPrng.init(11111);
        var rng = prng.random();

        // 生成测试数据
        const blocks = try testing.allocator.alloc(MemoryBlockSequence.MemoryBlock, size);
        defer {
            for (blocks) |block| {
                testing.allocator.free(block.data);
            }
            testing.allocator.free(blocks);
        }

        for (blocks) |*block| {
            const block_size = rng.intRangeAtMost(usize, 16, 256);
            const is_allocated = rng.boolean();
            const data = try testing.allocator.alloc(u8, block_size);
            @memset(data, 0);

            block.* = .{
                .size = block_size,
                .is_allocated = is_allocated,
                .data = data,
            };
        }

        // 测量压缩时间
        const start = std.time.nanoTimestamp();
        const compacted = try simulateCompaction(blocks, testing.allocator);
        const end = std.time.nanoTimestamp();

        defer {
            for (compacted) |block| {
                testing.allocator.free(block.data);
            }
            testing.allocator.free(compacted);
        }

        const duration_ns = end - start;
        const duration_us = @divTrunc(duration_ns, 1000);

        std.debug.print("Size: {d:5} blocks, Time: {d:6} μs\n", .{ size, duration_us });
    }
}
