const std = @import("std");
const AdvancedOptimizer = @import("aot/advanced_optimizer.zig").AdvancedOptimizer;

test "advanced optimizer - framework initialization" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 验证初始统计为 0
    const stats = optimizer.getStats();
    try std.testing.expectEqual(@as(u32, 0), stats.scalar_replacements);
    try std.testing.expectEqual(@as(u32, 0), stats.loop_vectorizations);
    try std.testing.expectEqual(@as(u32, 0), stats.slp_vectorizations);
    try std.testing.expectEqual(@as(u32, 0), stats.polyhedral_transforms);
    try std.testing.expectEqual(@as(u32, 0), stats.gvn_eliminations);
    try std.testing.expectEqual(@as(u32, 0), stats.sccp_propagations);
}

test "advanced optimizer - optimization pipeline" {
    const allocator = std.testing.allocator;
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();
    
    // 创建简单的 IR
    var functions = try std.ArrayList(*AdvancedOptimizer.Function).initCapacity(allocator, 0);
    defer functions.deinit(allocator);
    
    var ir = AdvancedOptimizer.IR{
        .functions = functions,
    };
    
    // 测试优化流水线（框架验证）
    try optimizer.sparseConditionalConstantPropagation(&ir);
    try optimizer.globalValueNumbering(&ir);
    try optimizer.scalarReplacement(&ir);
    try optimizer.loopVectorization(&ir);
    try optimizer.superwordLevelParallelism(&ir);
    try optimizer.polyhedralLoopOptimization(&ir);
    
    // 验证优化器可以正常运行
    const stats = optimizer.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.sccp_propagations);
    try std.testing.expectEqual(@as(u32, 1), stats.gvn_eliminations);
    try std.testing.expectEqual(@as(u32, 1), stats.loop_vectorizations);
    try std.testing.expectEqual(@as(u32, 1), stats.slp_vectorizations);
    try std.testing.expectEqual(@as(u32, 1), stats.polyhedral_transforms);
}
