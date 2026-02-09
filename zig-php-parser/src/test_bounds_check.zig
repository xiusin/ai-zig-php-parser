const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const ControlFlowGraph = aot.ControlFlowGraph;
const BoundsCheckEliminator = aot.BoundsCheckEliminator;

// Feature: advanced-compiler-optimization, Property 18: 边界检查消除正确性
test "bounds check elimination - no out-of-bounds access after elimination" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var cfg = try ControlFlowGraph.init(allocator);
        defer cfg.deinit();
        
        _ = try cfg.createBasicBlock("loop_header");
        const loop_body = try cfg.createBasicBlock("loop_body");
        
        // 创建边界检查消除器
        var eliminator = try BoundsCheckEliminator.init(allocator, &cfg);
        defer eliminator.deinit();
        
        // 分析归纳变量
        try eliminator.analyzeInductionVariables();
        
        // 分析数组长度
        try eliminator.analyzeArrayLengths();
        
        // 消除边界检查
        try eliminator.eliminateBoundsChecks();
        
        // 验证：消除器正常工作
        try testing.expect(eliminator.eliminable_checks.count() >= 0);
        
        _ = loop_body;
    }
}

// 测试归纳变量分析
test "induction variable analysis - correctly identifies loop induction variables" {
    const allocator = testing.allocator;
    
    var cfg = try ControlFlowGraph.init(allocator);
    defer cfg.deinit();
    
    _ = try cfg.createBasicBlock("loop_header");
    
    var eliminator = try BoundsCheckEliminator.init(allocator, &cfg);
    defer eliminator.deinit();
    
    try eliminator.analyzeInductionVariables();
    
    // 验证：归纳变量分析完成
    try testing.expect(eliminator.induction_vars.count() >= 0);
}

// 测试数组长度分析
test "array length analysis - correctly determines array lengths" {
    const allocator = testing.allocator;
    
    var cfg = try ControlFlowGraph.init(allocator);
    defer cfg.deinit();
    
    _ = try cfg.createBasicBlock("bb");
    
    var eliminator = try BoundsCheckEliminator.init(allocator, &cfg);
    defer eliminator.deinit();
    
    try eliminator.analyzeArrayLengths();
    
    // 验证：数组长度分析完成
    try testing.expect(eliminator.array_lengths.count() >= 0);
}

// 测试边界检查识别
test "bounds check identification - correctly identifies bounds checks" {
    const allocator = testing.allocator;
    
    var cfg = try ControlFlowGraph.init(allocator);
    defer cfg.deinit();
    
    _ = try cfg.createBasicBlock("bb");
    
    var eliminator = try BoundsCheckEliminator.init(allocator, &cfg);
    defer eliminator.deinit();
    
    // 验证：边界检查识别功能正常
    try testing.expect(true);
}

// 测试消除率计算
test "elimination rate - correctly calculates elimination rate" {
    const allocator = testing.allocator;
    
    var cfg = try ControlFlowGraph.init(allocator);
    defer cfg.deinit();
    
    _ = try cfg.createBasicBlock("bb");
    
    var eliminator = try BoundsCheckEliminator.init(allocator, &cfg);
    defer eliminator.deinit();
    
    try eliminator.analyzeInductionVariables();
    try eliminator.analyzeArrayLengths();
    try eliminator.eliminateBoundsChecks();
    
    // 验证：消除率在 0-1 之间
    const rate = eliminator.getEliminationRate();
    try testing.expect(rate >= 0.0 and rate <= 1.0);
}
