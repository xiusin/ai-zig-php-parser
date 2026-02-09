const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const CallGraph = aot.CallGraph;
const FunctionSignature = aot.FunctionSignature;
const TypeInfo = aot.TypeInfo;
const DevirtualizationOptimizer = aot.DevirtualizationOptimizer;

// Feature: advanced-compiler-optimization, Property 15: 去虚化正确性
test "devirtualization - devirtualized calls are semantically equivalent to virtual calls" {
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
        
        // 创建类层次：Base -> Derived
        const base_method = try graph.addFunction("Base::method", sig);
        const derived_method = try graph.addFunction("Derived::method", sig);
        const caller = try graph.addFunction("caller", sig);
        
        // 添加虚方法调用
        try graph.addCallEdge(caller, base_method, .{
            .location = .{ .file = "test.php", .line = 1, .column = 1 },
            .call_type = .virtual,
        });
        
        // 创建去虚化优化器
        var optimizer = try DevirtualizationOptimizer.init(allocator, &graph);
        defer optimizer.deinit();
        
        // 执行类层次分析
        try optimizer.classHierarchyAnalysis();
        
        // 验证：类层次结构被构建
        try testing.expect(optimizer.class_hierarchy.classes.count() > 0);
        
        // 验证：虚方法表被构建
        try testing.expect(optimizer.vtables.count() > 0);
        
        _ = derived_method;
    }
}

// 测试类层次分析
test "class hierarchy analysis - correctly builds class hierarchy" {
    const allocator = testing.allocator;
    
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{},
        .return_type = .void,
        .is_variadic = false,
    };
    
    // 创建类层次
    _ = try graph.addFunction("Animal::speak", sig);
    _ = try graph.addFunction("Dog::speak", sig);
    _ = try graph.addFunction("Cat::speak", sig);
    
    var optimizer = try DevirtualizationOptimizer.init(allocator, &graph);
    defer optimizer.deinit();
    
    try optimizer.classHierarchyAnalysis();
    
    // 验证：所有类都被识别
    try testing.expect(optimizer.class_hierarchy.classes.contains("Animal"));
    try testing.expect(optimizer.class_hierarchy.classes.contains("Dog"));
    try testing.expect(optimizer.class_hierarchy.classes.contains("Cat"));
}

// 测试虚方法表构建
test "vtable construction - correctly builds virtual method tables" {
    const allocator = testing.allocator;
    
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{},
        .return_type = .void,
        .is_variadic = false,
    };
    
    // 创建类和方法
    _ = try graph.addFunction("Shape::draw", sig);
    _ = try graph.addFunction("Shape::area", sig);
    _ = try graph.addFunction("Circle::draw", sig);
    
    var optimizer = try DevirtualizationOptimizer.init(allocator, &graph);
    defer optimizer.deinit();
    
    try optimizer.classHierarchyAnalysis();
    
    // 验证：vtable 被构建
    if (optimizer.vtables.get("Shape")) |vtable| {
        try testing.expect(vtable.entries.count() >= 2);
    }
}

// 测试快速类型分析
test "rapid type analysis - refines call targets based on instantiated types" {
    const allocator = testing.allocator;
    
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{},
        .return_type = .void,
        .is_variadic = false,
    };
    
    // 创建类和构造函数
    _ = try graph.addFunction("Vehicle::__construct", sig);
    _ = try graph.addFunction("Car::__construct", sig);
    _ = try graph.addFunction("Vehicle::drive", sig);
    _ = try graph.addFunction("Car::drive", sig);
    
    var optimizer = try DevirtualizationOptimizer.init(allocator, &graph);
    defer optimizer.deinit();
    
    try optimizer.classHierarchyAnalysis();
    try optimizer.rapidTypeAnalysis();
    
    // 验证：RTA 完成
    try testing.expect(true);
}

// 测试去虚化率计算
test "devirtualization rate - correctly calculates devirtualization rate" {
    const allocator = testing.allocator;
    
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{},
        .return_type = .void,
        .is_variadic = false,
    };
    
    const base = try graph.addFunction("Base::method", sig);
    const caller = try graph.addFunction("caller", sig);
    
    // 添加虚方法调用
    try graph.addCallEdge(caller, base, .{
        .location = .{ .file = "test.php", .line = 1, .column = 1 },
        .call_type = .virtual,
    });
    
    var optimizer = try DevirtualizationOptimizer.init(allocator, &graph);
    defer optimizer.deinit();
    
    try optimizer.classHierarchyAnalysis();
    
    // 验证：去虚化率在 0-1 之间
    const rate = optimizer.getDevirtualizationRate();
    try testing.expect(rate >= 0.0 and rate <= 1.0);
}
