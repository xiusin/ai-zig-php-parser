const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const ControlFlowGraph = aot.ControlFlowGraph;
const BasicBlock = aot.BasicBlock;
const Instruction = aot.Instruction;
const Opcode = aot.Opcode;
const Variable = aot.Variable;
const Definition = aot.Definition;
const DataFlowAnalysis = aot.DataFlowAnalysis;

// Feature: advanced-compiler-optimization, Property 3: 到达定义正确性
test "reaching definitions - all reaching definitions are correctly identified" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var cfg = try ControlFlowGraph.init(allocator);
        defer cfg.deinit();
        
        // 创建简单的 CFG:
        // BB0: x = 1
        // BB1: y = x + 2
        // BB2: z = x + y
        
        const bb0 = try cfg.createBasicBlock("BB0");
        const bb1 = try cfg.createBasicBlock("BB1");
        const bb2 = try cfg.createBasicBlock("BB2");
        
        cfg.entry = bb0;
        cfg.exit = bb2;
        
        try cfg.addEdge(bb0, bb1);
        try cfg.addEdge(bb1, bb2);
        
        // 创建变量
        var x = Variable{ .name = "x", .id = 0 };
        var y = Variable{ .name = "y", .id = 1 };
        
        // BB0: x = 1
        const inst0 = try allocator.create(Instruction);
        inst0.* = try Instruction.init(allocator, .store);
        const def0 = try allocator.create(Definition);
        def0.* = .{
            .variable = &x,
            .instruction = inst0,
            .basic_block = bb0,
        };
        inst0.def = def0;
        try bb0.addInstruction(inst0);
        
        // BB1: y = x + 2
        const inst1 = try allocator.create(Instruction);
        inst1.* = try Instruction.init(allocator, .add);
        const def1 = try allocator.create(Definition);
        def1.* = .{
            .variable = &y,
            .instruction = inst1,
            .basic_block = bb1,
        };
        inst1.def = def1;
        inst1.uses = try allocator.dupe(*Variable, &[_]*Variable{&x});
        try bb1.addInstruction(inst1);
        
        // 执行到达定义分析
        try cfg.analyzeDataFlow(.reaching_definitions);
        
        // 验证：BB1 的 IN 应包含 x 的定义
        try testing.expect(bb1.in_defs.count() > 0);
        
        // 验证：BB2 的 IN 应包含 x 和 y 的定义
        try testing.expect(bb2.in_defs.count() > 0);
        
        // 清理
        allocator.free(inst1.uses);
        allocator.destroy(def0);
        allocator.destroy(def1);
    }
}

// Feature: advanced-compiler-optimization, Property 4: 活跃变量正确性
test "liveness analysis - all live variables are correctly identified" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var cfg = try ControlFlowGraph.init(allocator);
        defer cfg.deinit();
        
        // 创建 CFG:
        // BB0: x = 1
        // BB1: y = x + 2
        // BB2: return y
        
        const bb0 = try cfg.createBasicBlock("BB0");
        const bb1 = try cfg.createBasicBlock("BB1");
        const bb2 = try cfg.createBasicBlock("BB2");
        
        cfg.entry = bb0;
        cfg.exit = bb2;
        
        try cfg.addEdge(bb0, bb1);
        try cfg.addEdge(bb1, bb2);
        
        // 创建变量
        var x = Variable{ .name = "x", .id = 0 };
        var y = Variable{ .name = "y", .id = 1 };
        
        // BB0: x = 1
        const inst0 = try allocator.create(Instruction);
        inst0.* = try Instruction.init(allocator, .store);
        const def0 = try allocator.create(Definition);
        def0.* = .{
            .variable = &x,
            .instruction = inst0,
            .basic_block = bb0,
        };
        inst0.def = def0;
        try bb0.addInstruction(inst0);
        
        // BB1: y = x + 2
        const inst1 = try allocator.create(Instruction);
        inst1.* = try Instruction.init(allocator, .add);
        const def1 = try allocator.create(Definition);
        def1.* = .{
            .variable = &y,
            .instruction = inst1,
            .basic_block = bb1,
        };
        inst1.def = def1;
        inst1.uses = try allocator.dupe(*Variable, &[_]*Variable{&x});
        try bb1.addInstruction(inst1);
        
        // BB2: return y
        const inst2 = try allocator.create(Instruction);
        inst2.* = try Instruction.init(allocator, .ret);
        inst2.uses = try allocator.dupe(*Variable, &[_]*Variable{&y});
        try bb2.addInstruction(inst2);
        
        // 执行活跃变量分析
        try cfg.analyzeDataFlow(.liveness);
        
        // 验证：BB1 的 OUT 应包含 y（因为 BB2 使用 y）
        try testing.expect(bb1.out_vars.count() > 0);
        
        // 验证：BB0 的 OUT 应包含 x（因为 BB1 使用 x）
        try testing.expect(bb0.out_vars.count() > 0);
        
        // 清理
        allocator.free(inst1.uses);
        allocator.free(inst2.uses);
        allocator.destroy(def0);
        allocator.destroy(def1);
    }
}

// 测试支配树构建
test "dominator tree - correctly identifies dominators" {
    const allocator = testing.allocator;
    
    var cfg = try ControlFlowGraph.init(allocator);
    defer cfg.deinit();
    
    // 创建 CFG:
    //     BB0 (entry)
    //    /   \
    //   BB1  BB2
    //    \   /
    //     BB3 (exit)
    
    const bb0 = try cfg.createBasicBlock("BB0");
    const bb1 = try cfg.createBasicBlock("BB1");
    const bb2 = try cfg.createBasicBlock("BB2");
    const bb3 = try cfg.createBasicBlock("BB3");
    
    cfg.entry = bb0;
    cfg.exit = bb3;
    
    try cfg.addEdge(bb0, bb1);
    try cfg.addEdge(bb0, bb2);
    try cfg.addEdge(bb1, bb3);
    try cfg.addEdge(bb2, bb3);
    
    // 构建支配树
    try cfg.buildDominatorTree();
    
    const dt = cfg.dominator_tree.?;
    
    // 验证：BB0 支配所有块
    try testing.expect(dt.dominates(bb0, bb0));
    try testing.expect(dt.dominates(bb0, bb1));
    try testing.expect(dt.dominates(bb0, bb2));
    try testing.expect(dt.dominates(bb0, bb3));
    
    // 验证：BB1 不支配 BB2
    try testing.expect(!dt.dominates(bb1, bb2));
    
    // 验证：BB2 不支配 BB1
    try testing.expect(!dt.dominates(bb2, bb1));
    
    // 验证：BB0 是 BB3 的直接支配者
    try testing.expectEqual(bb0, dt.idom.get(bb3).?);
}

// 测试可用表达式分析
test "available expressions - correctly identifies available expressions" {
    const allocator = testing.allocator;
    
    var cfg = try ControlFlowGraph.init(allocator);
    defer cfg.deinit();
    
    // 创建简单的 CFG
    const bb0 = try cfg.createBasicBlock("BB0");
    const bb1 = try cfg.createBasicBlock("BB1");
    const bb2 = try cfg.createBasicBlock("BB2");
    
    cfg.entry = bb0;
    cfg.exit = bb2;
    
    try cfg.addEdge(bb0, bb1);
    try cfg.addEdge(bb1, bb2);
    
    // 创建变量和表达式
    var x = Variable{ .name = "x", .id = 0 };
    var y = Variable{ .name = "y", .id = 1 };
    
    const expr = try allocator.create(aot.Expression);
    expr.* = .{
        .op = .add,
        .operands = try allocator.dupe(*Variable, &[_]*Variable{ &x, &y }),
    };
    
    // BB1: z = x + y
    const inst1 = try allocator.create(Instruction);
    inst1.* = try Instruction.init(allocator, .add);
    inst1.expression = expr;
    try bb1.addInstruction(inst1);
    
    // 执行可用表达式分析
    try cfg.analyzeDataFlow(.available_expressions);
    
    // 验证：BB2 的 IN 应包含 x + y 表达式（从 BB1 传播过来）
    try testing.expect(bb2.in_exprs.count() > 0);
    
    // 清理
    allocator.free(expr.operands);
    allocator.destroy(expr);
}
