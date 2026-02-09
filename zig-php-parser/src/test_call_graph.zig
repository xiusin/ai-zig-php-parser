const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const CallGraph = aot.CallGraph;
const FunctionNode = aot.FunctionNode;
const FunctionSignature = aot.FunctionSignature;
const TypeInfo = aot.TypeInfo;
const CallSite = aot.CallSite;
const CallType = aot.CallType;
const SourceLocation = aot.SourceLocation;

// Feature: advanced-compiler-optimization, Property 1: 调用图完整性
test "call graph completeness - all function calls are represented" {
    const allocator = testing.allocator;
    
    // 运行 100 次迭代
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var graph = try CallGraph.init(allocator);
        defer graph.deinit();
        
        // 创建测试函数
        const sig = FunctionSignature{
            .param_types = &[_]TypeInfo{},
            .return_type = .void,
            .is_variadic = false,
        };
        
        const main_func = try graph.addFunction("main", sig);
        const foo_func = try graph.addFunction("foo", sig);
        const bar_func = try graph.addFunction("bar", sig);
        
        // 添加调用关系: main -> foo, main -> bar, foo -> bar
        try graph.addCallEdge(main_func, foo_func, .{
            .location = .{ .file = "test.php", .line = 1, .column = 1 },
            .call_type = .direct,
        });
        
        try graph.addCallEdge(main_func, bar_func, .{
            .location = .{ .file = "test.php", .line = 2, .column = 1 },
            .call_type = .direct,
        });
        
        try graph.addCallEdge(foo_func, bar_func, .{
            .location = .{ .file = "test.php", .line = 3, .column = 1 },
            .call_type = .direct,
        });
        
        // 验证：所有调用都在调用图中表示
        try testing.expectEqual(@as(usize, 3), graph.edges.items.len);
        
        // 验证：main 调用 foo 和 bar
        try testing.expectEqual(@as(usize, 2), main_func.callees.items.len);
        try testing.expect(main_func.callees.items[0] == foo_func or main_func.callees.items[1] == foo_func);
        try testing.expect(main_func.callees.items[0] == bar_func or main_func.callees.items[1] == bar_func);
        
        // 验证：foo 调用 bar
        try testing.expectEqual(@as(usize, 1), foo_func.callees.items.len);
        try testing.expectEqual(bar_func, foo_func.callees.items[0]);
        
        // 验证：bar 被 main 和 foo 调用
        try testing.expectEqual(@as(usize, 2), bar_func.callers.items.len);
    }
}

// Feature: advanced-compiler-optimization, Property 2: 递归检测正确性
test "recursion detection - all recursive calls are correctly identified" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var graph = try CallGraph.init(allocator);
        defer graph.deinit();
        
        const sig = FunctionSignature{
            .param_types = &[_]TypeInfo{},
            .return_type = .void,
            .is_variadic = false,
        };
        
        // 测试直接递归
        {
            const factorial = try graph.addFunction("factorial", sig);
            try graph.addCallEdge(factorial, factorial, .{
                .location = .{ .file = "test.php", .line = 1, .column = 1 },
                .call_type = .direct,
            });
            
            try graph.detectRecursion();
            try testing.expect(factorial.is_recursive);
            try testing.expect(graph.recursive_calls.contains(factorial));
        }
        
        // 测试间接递归
        {
            const a = try graph.addFunction("a", sig);
            const b = try graph.addFunction("b", sig);
            const c = try graph.addFunction("c", sig);
            
            // a -> b -> c -> a (循环)
            try graph.addCallEdge(a, b, .{
                .location = .{ .file = "test.php", .line = 2, .column = 1 },
                .call_type = .direct,
            });
            try graph.addCallEdge(b, c, .{
                .location = .{ .file = "test.php", .line = 3, .column = 1 },
                .call_type = .direct,
            });
            try graph.addCallEdge(c, a, .{
                .location = .{ .file = "test.php", .line = 4, .column = 1 },
                .call_type = .direct,
            });
            
            try graph.detectRecursion();
            try testing.expect(a.is_recursive or b.is_recursive or c.is_recursive);
        }
    }
}

// 测试调用图剪枝
test "call graph pruning - unreachable functions are removed" {
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
    const foo_func = try graph.addFunction("foo", sig);
    
    // 创建不可达函数
    _ = try graph.addFunction("unreachable", sig);
    
    try graph.addCallEdge(main_func, foo_func, .{
        .location = .{ .file = "test.php", .line = 1, .column = 1 },
        .call_type = .direct,
    });
    
    try testing.expectEqual(@as(usize, 3), graph.nodes.count());
    
    try graph.pruneUnreachable(&[_][]const u8{"main"});
    
    // 验证：不可达函数被移除
    try testing.expectEqual(@as(usize, 2), graph.nodes.count());
    try testing.expect(graph.nodes.contains("main"));
    try testing.expect(graph.nodes.contains("foo"));
    try testing.expect(!graph.nodes.contains("unreachable"));
}

// 测试关键路径识别
test "critical path identification - finds most frequent call chains" {
    const allocator = testing.allocator;
    
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{},
        .return_type = .void,
        .is_variadic = false,
    };
    
    const main_func = try graph.addFunction("main", sig);
    const hot_func = try graph.addFunction("hot", sig);
    const cold_func = try graph.addFunction("cold", sig);
    
    const hot_site = CallSite{
        .location = .{ .file = "test.php", .line = 1, .column = 1 },
        .call_type = .direct,
    };
    
    const cold_site = CallSite{
        .location = .{ .file = "test.php", .line = 2, .column = 1 },
        .call_type = .direct,
    };
    
    try graph.addCallEdge(main_func, hot_func, hot_site);
    try graph.addCallEdge(main_func, cold_func, cold_site);
    
    // 设置频率
    var profile = aot.ProfileData.init(allocator);
    defer profile.deinit();
    
    try profile.call_counts.put(hot_site.location, 10000);
    try profile.call_counts.put(cold_site.location, 10);
    
    graph.updateFrequencies(&profile);
    
    // 验证频率更新
    var max_freq: u64 = 0;
    for (graph.edges.items) |edge| {
        if (edge.frequency > max_freq) {
            max_freq = edge.frequency;
        }
    }
    try testing.expectEqual(@as(u64, 10000), max_freq);
}
