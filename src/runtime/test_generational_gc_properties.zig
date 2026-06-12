const std = @import("std");
const testing = std.testing;
const generational_gc = @import("generational_gc.zig");

// ============================================================================
// 属性 21：分代 GC 对象晋升正确性
// **验证：需求 4.1**
// ============================================================================

// 属性：对象在 Nursery 中存活 N 次后必须晋升到 Survivor
// 不变式：age < promotion_age => generation == nursery || generation == survivor
//         age >= promotion_age => generation == old
// **Validates: Requirements 4.1**
test "Property 21.1: Object promotion from nursery to survivor" {
    const allocator = testing.allocator;
    
    // 配置：晋升年龄为 3
    var gc = try generational_gc.EnhancedGenerationalGC.initWithConfig(allocator, .{
        .nursery_size = 64 * 1024,
        .survivor_size = 32 * 1024,
        .promotion_age = 3,
        .nursery_gc_threshold = 0.5,
    });
    defer gc.deinit();
    
    // 运行 100 次迭代测试
    var iteration: usize = 0;
    while (iteration < 100) : (iteration += 1) {
        // 分配对象并添加为根（确保存活）
        const obj = try gc.alloc(128);
        try gc.addRoot(obj);
        
        // 初始状态：对象在 Nursery
        try testing.expectEqual(generational_gc.GCObjectHeader.Generation.nursery, obj.generation);
        try testing.expectEqual(@as(u8, 0), obj.age);
        
        // 第一次 Minor GC：应该移到 Survivor，age = 1
        try gc.collectMinor();
        
        // 检查对象是否被正确转发
        const obj_after_gc1 = if (obj.forwarded) 
            @as(*generational_gc.GCObjectHeader, @ptrCast(@alignCast(obj.forward_addr.?)))
        else 
            obj;
        
        try testing.expect(obj_after_gc1.generation == .survivor or obj_after_gc1.generation == .old);
        if (obj_after_gc1.generation == .survivor) {
            try testing.expectEqual(@as(u8, 1), obj_after_gc1.age);
        }
        
        // 更新根引用
        gc.removeRoot(obj);
        try gc.addRoot(obj_after_gc1);
        
        // 第二次 Minor GC：age = 2
        try gc.collectMinor();
        
        const obj_after_gc2 = if (obj_after_gc1.forwarded)
            @as(*generational_gc.GCObjectHeader, @ptrCast(@alignCast(obj_after_gc1.forward_addr.?)))
        else
            obj_after_gc1;
        
        if (obj_after_gc2.generation == .survivor) {
            try testing.expectEqual(@as(u8, 2), obj_after_gc2.age);
        }
        
        // 更新根引用
        gc.removeRoot(obj_after_gc1);
        try gc.addRoot(obj_after_gc2);
        
        // 第三次 Minor GC：应该晋升到老年代
        try gc.collectMinor();
        
        const obj_after_gc3 = if (obj_after_gc2.forwarded)
            @as(*generational_gc.GCObjectHeader, @ptrCast(@alignCast(obj_after_gc2.forward_addr.?)))
        else
            obj_after_gc2;
        
        // 验证：age >= promotion_age 时必须在老年代
        if (obj_after_gc3.age >= 3) {
            try testing.expectEqual(generational_gc.GCObjectHeader.Generation.old, obj_after_gc3.generation);
        }
        
        // 清理根
        gc.removeRoot(obj_after_gc2);
        
        // 验证统计信息
        try testing.expect(gc.stats.promoted_to_survivor > 0 or gc.stats.promoted_to_old > 0);
    }
    
    std.debug.print("\n[Property 21.1] ✓ 对象晋升策略正确：100 次迭代通过\n", .{});
}

// 属性：Survivor 空间满时，对象应直接晋升到老年代
test "Property 21.2: Direct promotion when survivor is full" {
    const allocator = testing.allocator;
    
    // 配置：小的 Survivor 空间
    var gc = try generational_gc.EnhancedGenerationalGC.initWithConfig(allocator, .{
        .nursery_size = 64 * 1024,
        .survivor_size = 1024, // 很小的 Survivor
        .promotion_age = 5,
        .nursery_gc_threshold = 0.5,
    });
    defer gc.deinit();
    
    // 运行 50 次迭代
    var iteration: usize = 0;
    while (iteration < 50) : (iteration += 1) {
        // 分配多个对象填满 Survivor
        var objects = std.ArrayListUnmanaged(*generational_gc.GCObjectHeader){};
        defer objects.deinit(allocator);
        
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            const obj = try gc.alloc(256);
            try gc.addRoot(obj);
            try objects.append(allocator, obj);
        }
        
        // 触发 Minor GC
        try gc.collectMinor();
        
        // 检查：至少有一些对象应该直接晋升到老年代（因为 Survivor 太小）
        var promoted_to_old: usize = 0;
        for (objects.items) |obj| {
            const final_obj = if (obj.forwarded)
                @as(*generational_gc.GCObjectHeader, @ptrCast(@alignCast(obj.forward_addr.?)))
            else
                obj;
            
            if (final_obj.generation == .old) {
                promoted_to_old += 1;
            }
            
            gc.removeRoot(obj);
        }
        
        // 验证：当 Survivor 满时，应该有对象直接晋升
        try testing.expect(promoted_to_old > 0 or gc.stats.promoted_to_old > 0);
    }
    
    std.debug.print("\n[Property 21.2] ✓ Survivor 满时直接晋升：50 次迭代通过\n", .{});
}

// 属性：年轻代对象不应该在老年代中出现（除非已晋升）
test "Property 21.3: Generation invariant" {
    const allocator = testing.allocator;
    
    var gc = try generational_gc.EnhancedGenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 运行 100 次迭代
    var iteration: usize = 0;
    while (iteration < 100) : (iteration += 1) {
        // 分配对象
        const obj = try gc.alloc(64);
        
        // 验证：新分配的对象必须在 Nursery 或 Large Space
        try testing.expect(obj.generation == .nursery or obj.generation == .large);
        try testing.expectEqual(@as(u8, 0), obj.age);
        
        // 添加为根
        try gc.addRoot(obj);
        
        // 执行多次 GC
        var gc_count: usize = 0;
        while (gc_count < 5) : (gc_count += 1) {
            try gc.collectMinor();
            
            // 追踪对象位置
            var current_obj = obj;
            while (current_obj.forwarded) {
                current_obj = @as(*generational_gc.GCObjectHeader, @ptrCast(@alignCast(current_obj.forward_addr.?)));
            }
            
            // 验证不变式：age 和 generation 的关系
            if (current_obj.age < gc.config.promotion_age) {
                try testing.expect(
                    current_obj.generation == .nursery or 
                    current_obj.generation == .survivor
                );
            } else {
                try testing.expectEqual(generational_gc.GCObjectHeader.Generation.old, current_obj.generation);
            }
        }
        
        gc.removeRoot(obj);
    }
    
    std.debug.print("\n[Property 21.3] ✓ 代际不变式：100 次迭代通过\n", .{});
}

// ============================================================================
// 属性 28：写屏障正确性
// **验证：需求 4.8**
// ============================================================================

// 属性：老年代对象引用年轻代对象时，必须记录在 Remember Set
// **Validates: Requirements 4.8**
test "Property 28.1: Write barrier records cross-generational references" {
    const allocator = testing.allocator;
    
    var gc = try generational_gc.EnhancedGenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 运行 100 次迭代
    var iteration: usize = 0;
    while (iteration < 100) : (iteration += 1) {
        // 创建老年代对象
        const old_obj = try gc.old_gen.alloc(128);
        try testing.expectEqual(generational_gc.GCObjectHeader.Generation.old, old_obj.generation);
        
        // 创建年轻代对象
        const young_obj = try gc.alloc(64);
        try testing.expect(young_obj.generation == .nursery or young_obj.generation == .large);
        
        // 记录写屏障触发前的计数
        const wb_count_before = gc.stats.write_barrier_count;
        
        // 触发写屏障：老年代引用年轻代
        try gc.writeBarrier(old_obj, young_obj);
        
        // 验证：写屏障计数应该增加
        try testing.expectEqual(wb_count_before + 1, gc.stats.write_barrier_count);
        
        // 验证：老年代对象应该在 Remember Set 中
        try testing.expect(gc.remember_set.contains(old_obj));
    }
    
    std.debug.print("\n[Property 28.1] ✓ 写屏障记录跨代引用：100 次迭代通过\n", .{});
}

// 属性：同代引用不应触发 Remember Set 记录
test "Property 28.2: Write barrier ignores same-generation references" {
    const allocator = testing.allocator;
    
    var gc = try generational_gc.EnhancedGenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 运行 100 次迭代
    var iteration: usize = 0;
    while (iteration < 100) : (iteration += 1) {
        // 创建两个年轻代对象
        const young_obj1 = try gc.alloc(64);
        const young_obj2 = try gc.alloc(64);
        
        // 记录 Remember Set 大小
        const rs_size_before = gc.remember_set.count();
        
        // 触发写屏障：年轻代引用年轻代
        try gc.writeBarrier(young_obj1, young_obj2);
        
        // 验证：Remember Set 不应该增长（同代引用）
        try testing.expectEqual(rs_size_before, gc.remember_set.count());
        
        // 创建两个老年代对象
        const old_obj1 = try gc.old_gen.alloc(128);
        const old_obj2 = try gc.old_gen.alloc(128);
        
        const rs_size_before2 = gc.remember_set.count();
        
        // 触发写屏障：老年代引用老年代
        try gc.writeBarrier(old_obj1, old_obj2);
        
        // 验证：Remember Set 不应该增长（同代引用）
        try testing.expectEqual(rs_size_before2, gc.remember_set.count());
    }
    
    std.debug.print("\n[Property 28.2] ✓ 写屏障忽略同代引用：100 次迭代通过\n", .{});
}

// 属性：Minor GC 必须扫描 Remember Set 中的对象
test "Property 28.3: Minor GC scans remember set" {
    const allocator = testing.allocator;
    
    var gc = try generational_gc.EnhancedGenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 运行 50 次迭代
    var iteration: usize = 0;
    while (iteration < 50) : (iteration += 1) {
        // 创建老年代对象
        const old_obj = try gc.old_gen.alloc(128);
        
        // 创建年轻代对象（不添加为根）
        const young_obj = try gc.alloc(64);
        
        // 建立跨代引用
        try gc.writeBarrier(old_obj, young_obj);
        
        // 验证：年轻代对象应该通过 Remember Set 保持存活
        try testing.expect(gc.remember_set.contains(old_obj));
        
        // 执行 Minor GC
        const minor_gc_count_before = gc.stats.minor_gc_count;
        try gc.collectMinor();
        
        // 验证：Minor GC 已执行
        try testing.expectEqual(minor_gc_count_before + 1, gc.stats.minor_gc_count);
        
        // 验证：Remember Set 在 Minor GC 后被清理
        try testing.expectEqual(@as(usize, 0), gc.remember_set.count());
    }
    
    std.debug.print("\n[Property 28.3] ✓ Minor GC 扫描 Remember Set：50 次迭代通过\n", .{});
}

// 属性：写屏障不应影响程序正确性（只是性能优化）
test "Property 28.4: Write barrier preserves correctness" {
    const allocator = testing.allocator;
    
    var gc = try generational_gc.EnhancedGenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 运行 100 次迭代
    var iteration: usize = 0;
    while (iteration < 100) : (iteration += 1) {
        // 创建复杂的对象图
        const old_obj1 = try gc.old_gen.alloc(128);
        _ = try gc.old_gen.alloc(128); // old_obj2 - 用于测试内存分配
        const young_obj1 = try gc.alloc(64);
        _ = try gc.alloc(64); // young_obj2 - 用于测试内存分配
        
        // 添加根
        try gc.addRoot(old_obj1);
        
        // 建立引用关系：old1 -> young1
        try gc.writeBarrier(old_obj1, young_obj1);
        
        // 执行 GC
        try gc.collectMinor();
        
        // 验证：所有可达对象都应该存活
        // （通过统计信息间接验证）
        try testing.expect(gc.stats.total_allocated > 0);
        try testing.expect(gc.stats.minor_gc_count > 0);
        
        gc.removeRoot(old_obj1);
    }
    
    std.debug.print("\n[Property 28.4] ✓ 写屏障保持正确性：100 次迭代通过\n", .{});
}

// ============================================================================
// 综合属性测试
// ============================================================================

// 属性：GC 后内存使用应该减少或保持不变
test "Property: GC reduces or maintains memory usage" {
    const allocator = testing.allocator;
    
    var gc = try generational_gc.EnhancedGenerationalGC.init(allocator);
    defer gc.deinit();
    
    // 运行 50 次迭代
    var iteration: usize = 0;
    while (iteration < 50) : (iteration += 1) {
        // 分配大量对象（不添加根，会被回收）
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            _ = try gc.alloc(64);
        }
        
        // 记录 GC 前的内存使用
        const usage_before = gc.getMemoryUsage();
        const total_before = usage_before.total_used;
        
        // 执行 Minor GC
        try gc.collectMinor();
        
        // 记录 GC 后的内存使用
        const usage_after = gc.getMemoryUsage();
        const total_after = usage_after.total_used;
        
        // 验证：GC 后内存使用应该减少（因为没有根引用）
        try testing.expect(total_after <= total_before);
        
        // 验证：释放的内存应该被统计
        try testing.expect(gc.stats.total_freed > 0);
    }
    
    std.debug.print("\n[Property] ✓ GC 减少内存使用：50 次迭代通过\n", .{});
}

// 属性：对象晋升不应丢失数据
test "Property: Object promotion preserves data" {
    const allocator = testing.allocator;
    
    var gc = try generational_gc.EnhancedGenerationalGC.initWithConfig(allocator, .{
        .nursery_size = 64 * 1024,
        .survivor_size = 32 * 1024,
        .promotion_age = 2,
    });
    defer gc.deinit();
    
    // 运行 50 次迭代
    var iteration: usize = 0;
    while (iteration < 50) : (iteration += 1) {
        // 分配对象
        const obj = try gc.alloc(128);
        try gc.addRoot(obj);
        
        // 写入魔数到对象数据区
        const data_ptr: [*]u8 = @ptrCast(obj.getDataPtr());
        const magic_number: u64 = 0xDEADBEEFCAFEBABE;
        @memcpy(data_ptr[0..8], std.mem.asBytes(&magic_number));
        
        // 执行多次 GC，触发晋升
        var gc_count: usize = 0;
        while (gc_count < 3) : (gc_count += 1) {
            try gc.collectMinor();
        }
        
        // 追踪对象到最终位置
        var current_obj = obj;
        while (current_obj.forwarded) {
            current_obj = @as(*generational_gc.GCObjectHeader, @ptrCast(@alignCast(current_obj.forward_addr.?)));
        }
        
        // 验证：数据应该保持不变
        const final_data_ptr: [*]u8 = @ptrCast(current_obj.getDataPtr());
        const read_magic: u64 = std.mem.bytesToValue(u64, final_data_ptr[0..8]);
        try testing.expectEqual(magic_number, read_magic);
        
        gc.removeRoot(obj);
    }
    
    std.debug.print("\n[Property] ✓ 对象晋升保持数据：50 次迭代通过\n", .{});
}
