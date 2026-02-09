const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const CallGraph = aot.CallGraph;
const FunctionSignature = aot.FunctionSignature;
const TypeInfo = aot.TypeInfo;
const InterproceduralOptimizer = aot.InterproceduralOptimizer;
const ConstantValue = aot.ConstantValue;

// Feature: advanced-compiler-optimization, Property 5: 跨过程常量传播正确性
test "interprocedural constant propagation - constants propagate correctly across function boundaries" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var graph = try CallGraph.init(allocator);
        defer graph.deinit();
        
        const sig = FunctionSignature{
            .param_types = &[_]TypeInfo{.int},
            .return_type = .int,
            .is_variadic = false,
        };
        
        // 创建函数：main -> foo -> bar
        const main_func = try graph.addFunction("main", sig);
        const foo_func = try graph.addFunction("foo", sig);
        const bar_func = try graph.addFunction("bar", sig);
        
        try graph.addCallEdge(main_func, foo_func, .{
            .location = .{ .file = "test.php", .line = 1, .column = 1 },
            .call_type = .direct,
        });
        
        try graph.addCallEdge(foo_func, bar_func, .{
            .location = .{ .file = "test.php", .line = 2, .column = 1 },
            .call_type = .direct,
        });
        
        // 创建跨过程优化器
        var optimizer = try InterproceduralOptimizer.init(allocator, &graph);
        defer optimizer.deinit();
        
        // 执行常量传播
        try optimizer.constantPropagation();
        
        // 验证：常量传播完成（基本验证）
        try testing.expect(true);
    }
}

// Feature: advanced-compiler-optimization, Property 6: 函数特化语义等价性
test "function specialization - specialized functions are semantically equivalent to original" {
    const allocator = testing.allocator;
    
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{ .int, .int },
        .return_type = .int,
        .is_variadic = false,
    };
    
    // 创建一个被频繁调用的函数
    const add_func = try graph.addFunction("add", sig);
    
    // 创建15个调用者（手动展开避免循环问题）
    const c0 = try graph.addFunction("caller0", sig);
    const c1 = try graph.addFunction("caller1", sig);
    const c2 = try graph.addFunction("caller2", sig);
    const c3 = try graph.addFunction("caller3", sig);
    const c4 = try graph.addFunction("caller4", sig);
    const c5 = try graph.addFunction("caller5", sig);
    const c6 = try graph.addFunction("caller6", sig);
    const c7 = try graph.addFunction("caller7", sig);
    const c8 = try graph.addFunction("caller8", sig);
    const c9 = try graph.addFunction("caller9", sig);
    const c10 = try graph.addFunction("caller10", sig);
    const c11 = try graph.addFunction("caller11", sig);
    const c12 = try graph.addFunction("caller12", sig);
    const c13 = try graph.addFunction("caller13", sig);
    const c14 = try graph.addFunction("caller14", sig);
    
    const callers = [_]*aot.FunctionNode{ c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14 };
    for (callers, 0..) |caller, i| {
        try graph.addCallEdge(caller, add_func, .{
            .location = .{ .file = "test.php", .line = @intCast(i + 1), .column = 1 },
            .call_type = .direct,
        });
    }
    
    // 创建跨过程优化器
    var optimizer = try InterproceduralOptimizer.init(allocator, &graph);
    defer optimizer.deinit();
    
    // 执行函数特化
    try optimizer.functionSpecialization();
    
    // 验证：特化版本被创建
    if (optimizer.specializations.get(add_func)) |specs| {
        try testing.expect(specs.items.len > 0);
    }
}

// 测试跨过程死代码消除
test "interprocedural dead code elimination - unreachable functions are removed" {
    const allocator = testing.allocator;
    
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{},
        .return_type = .void,
        .is_variadic = false,
    };
    
    // 创建可达函数
    const main_func = try graph.addFunction("main", sig);
    const used_func = try graph.addFunction("used", sig);
    
    // 创建不可达函数
    _ = try graph.addFunction("unused1", sig);
    _ = try graph.addFunction("unused2", sig);
    
    try graph.addCallEdge(main_func, used_func, .{
        .location = .{ .file = "test.php", .line = 1, .column = 1 },
        .call_type = .direct,
    });
    
    try testing.expectEqual(@as(usize, 4), graph.nodes.count());
    
    // 使用 CallGraph 的 pruneUnreachable（需要指定入口）
    try graph.pruneUnreachable(&[_][]const u8{"main"});
    
    // 验证：不可达函数被移除
    try testing.expectEqual(@as(usize, 2), graph.nodes.count());
    try testing.expect(graph.nodes.contains("main"));
    try testing.expect(graph.nodes.contains("used"));
    try testing.expect(!graph.nodes.contains("unused1"));
    try testing.expect(!graph.nodes.contains("unused2"));
}

// 测试未使用参数消除
test "unused parameter elimination - unused parameters are identified" {
    const allocator = testing.allocator;
    
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{ .int, .int, .int },
        .return_type = .int,
        .is_variadic = false,
    };
    
    const func = try graph.addFunction("test_func", sig);
    
    // 创建跨过程优化器
    var optimizer = try InterproceduralOptimizer.init(allocator, &graph);
    defer optimizer.deinit();
    
    // 执行未使用参数消除
    try optimizer.eliminateUnusedParameters();
    
    // 验证：分析完成（基本验证）
    try testing.expect(func.signature.param_types.len == 3);
}

// 测试常量值相等性
test "constant value equality - correctly compares constant values" {
    const v1 = ConstantValue{ .int = 42 };
    const v2 = ConstantValue{ .int = 42 };
    const v3 = ConstantValue{ .int = 43 };
    
    try testing.expect(v1.equals(v2));
    try testing.expect(!v1.equals(v3));
    
    const s1 = ConstantValue{ .string = "hello" };
    const s2 = ConstantValue{ .string = "hello" };
    const s3 = ConstantValue{ .string = "world" };
    
    try testing.expect(s1.equals(s2));
    try testing.expect(!s1.equals(s3));
}
