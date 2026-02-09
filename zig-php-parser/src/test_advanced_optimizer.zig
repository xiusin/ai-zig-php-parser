const std = @import("std");
const AdvancedOptimizer = @import("aot/advanced_optimizer.zig").AdvancedOptimizer;

test "advanced optimizer - scalar replacement" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 测试标量替换：3 个未逃逸对象
    const allocations = [_]bool{ false, true, false, false, true };
    const count = try optimizer.scalarReplacement(&allocations);
    try std.testing.expectEqual(@as(u32, 3), count);
    try std.testing.expectEqual(@as(u32, 3), optimizer.getStats().scalar_replacements);
}

test "advanced optimizer - GVN" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 测试 GVN：重复表达式消除
    const expressions = [_]u64{ 0x1234, 0x5678, 0x1234, 0x9ABC, 0x5678 };
    const eliminated = try optimizer.globalValueNumbering(&expressions);
    try std.testing.expectEqual(@as(u32, 2), eliminated); // 2 个重复
}

test "advanced optimizer - SCCP" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 测试 SCCP：常量传播
    const variables = [_]u32{ 1, 2, 3, 4 };
    const values = [_]?i64{ 10, null, 20, null };
    const propagated = try optimizer.sparseConditionalConstantPropagation(&variables, &values);
    try std.testing.expectEqual(@as(u32, 2), propagated);
}

test "advanced optimizer - SLP vectorization" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 测试 SLP：同构指令组
    const group1 = [_]u32{ 1, 2, 3, 4 };
    const group2 = [_]u32{ 5, 6 };
    const group3 = [_]u32{ 7 }; // 太小
    const groups = [_][]const u32{ &group1, &group2, &group3 };
    const vectorized = try optimizer.superwordLevelParallelism(&groups);
    try std.testing.expectEqual(@as(u32, 2), vectorized);
}

test "advanced optimizer - polyhedral optimization" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 测试多面体优化
    const loops = [_]AdvancedOptimizer.LoopInfo{
        .{ .is_affine = true, .nest_depth = 2, .is_vectorizable = true, .has_dependencies = false },
        .{ .is_affine = false, .nest_depth = 1, .is_vectorizable = false, .has_dependencies = true },
        .{ .is_affine = true, .nest_depth = 3, .is_vectorizable = true, .has_dependencies = false },
    };
    const transformed = try optimizer.polyhedralLoopOptimization(&loops);
    try std.testing.expectEqual(@as(u32, 2), transformed);
}

test "advanced optimizer - loop vectorization" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 测试循环向量化
    const loops = [_]AdvancedOptimizer.LoopInfo{
        .{ .is_affine = true, .nest_depth = 1, .is_vectorizable = true, .has_dependencies = false },
        .{ .is_affine = true, .nest_depth = 1, .is_vectorizable = false, .has_dependencies = true },
        .{ .is_affine = true, .nest_depth = 1, .is_vectorizable = true, .has_dependencies = false },
    };
    const vectorized = try optimizer.loopVectorization(&loops);
    try std.testing.expectEqual(@as(u32, 2), vectorized);
}

test "advanced optimizer - comprehensive pipeline" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 运行所有优化
    const allocations = [_]bool{ false, false, true };
    _ = try optimizer.scalarReplacement(&allocations);
    
    const expressions = [_]u64{ 0x1, 0x2, 0x1 };
    _ = try optimizer.globalValueNumbering(&expressions);
    
    const variables = [_]u32{ 1, 2 };
    const values = [_]?i64{ 10, null };
    _ = try optimizer.sparseConditionalConstantPropagation(&variables, &values);
    
    const group = [_]u32{ 1, 2, 3, 4 };
    const groups = [_][]const u32{&group};
    _ = try optimizer.superwordLevelParallelism(&groups);
    
    const loops = [_]AdvancedOptimizer.LoopInfo{
        .{ .is_affine = true, .nest_depth = 2, .is_vectorizable = true, .has_dependencies = false },
    };
    _ = try optimizer.polyhedralLoopOptimization(&loops);
    _ = try optimizer.loopVectorization(&loops);
    
    // 验证统计
    const stats = optimizer.getStats();
    try std.testing.expectEqual(@as(u32, 2), stats.scalar_replacements);
    try std.testing.expectEqual(@as(u32, 1), stats.gvn_eliminations);
    try std.testing.expectEqual(@as(u32, 1), stats.sccp_propagations);
    try std.testing.expectEqual(@as(u32, 1), stats.slp_vectorizations);
    try std.testing.expectEqual(@as(u32, 1), stats.polyhedral_transforms);
    try std.testing.expectEqual(@as(u32, 1), stats.loop_vectorizations);
}
