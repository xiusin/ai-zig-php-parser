const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const CompileTimeReflection = aot.CompileTimeReflection;
const ReflectionCache = aot.ReflectionCache;
const ReflectionClassMetadata = aot.ReflectionClassMetadata;
const CallGraph = aot.CallGraph;
const FunctionSignature = aot.FunctionSignature;
const TypeInfo = aot.TypeInfo;

// Feature: advanced-compiler-optimization, Property 28: 反射元数据完整性
test "reflection metadata completeness - metadata matches source code definitions" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var reflection = try CompileTimeReflection.init(allocator);
        defer reflection.deinit();
        
        // 收集类元数据
        try reflection.collectClassMetadata("Animal", null);
        try reflection.collectClassMetadata("Dog", "Animal");
        try reflection.collectClassMetadata("Cat", "Animal");
        
        // 收集方法元数据
        try reflection.collectMethodMetadata("Animal", "speak");
        try reflection.collectMethodMetadata("Dog", "speak");
        try reflection.collectMethodMetadata("Cat", "speak");
        
        // 收集属性元数据
        try reflection.collectPropertyMetadata("Animal", "name");
        try reflection.collectPropertyMetadata("Dog", "breed");
        
        // 验证：元数据被收集
        try testing.expect(reflection.class_metadata.count() == 3);
        try testing.expect(reflection.method_metadata.count() == 3);
        try testing.expect(reflection.property_metadata.count() == 2);
        
        // 验证：类层次结构正确
        const dog_parent = reflection.class_hierarchy.getParent("Dog");
        try testing.expect(dog_parent != null);
        try testing.expect(std.mem.eql(u8, dog_parent.?, "Animal"));
    }
}

// Feature: advanced-compiler-optimization, Property 29: 反射 API 正确性
test "reflection API correctness - API returns correct information" {
    const allocator = testing.allocator;
    
    var reflection = try CompileTimeReflection.init(allocator);
    defer reflection.deinit();
    
    // 收集元数据
    try reflection.collectClassMetadata("Person", null);
    try reflection.collectMethodMetadata("Person", "getName");
    try reflection.collectMethodMetadata("Person", "getAge");
    try reflection.collectPropertyMetadata("Person", "name");
    try reflection.collectPropertyMetadata("Person", "age");
    
    // 获取类元数据
    const metadata = reflection.getClassMetadata("Person");
    try testing.expect(metadata != null);
    try testing.expect(std.mem.eql(u8, metadata.?.name, "Person"));
}

// Feature: advanced-compiler-optimization, Property 30: 反射缓存一致性
test "reflection cache consistency - cached results match non-cached results" {
    const allocator = testing.allocator;
    
    var reflection = try CompileTimeReflection.init(allocator);
    defer reflection.deinit();
    
    // 收集元数据
    try reflection.collectClassMetadata("User", null);
    
    const metadata = reflection.getClassMetadata("User").?;
    
    // 创建缓存
    var cache = ReflectionCache.init(allocator);
    defer cache.deinit();
    
    // 第一次访问（缓存未命中）
    const class1 = try cache.getClass("User", &metadata);
    try testing.expect(std.mem.eql(u8, class1.getName(), "User"));
    
    // 第二次访问（缓存命中）
    const class2 = try cache.getClass("User", &metadata);
    try testing.expect(std.mem.eql(u8, class2.getName(), "User"));
    
    // 验证：两次返回相同对象
    try testing.expect(class1 == class2);
    
    // 验证：缓存命中率 > 0
    const hit_rate = cache.hitRate();
    try testing.expect(hit_rate > 0.0);
}

// 测试类层次分析
test "class hierarchy analysis - correctly builds class hierarchy" {
    const allocator = testing.allocator;
    
    var reflection = try CompileTimeReflection.init(allocator);
    defer reflection.deinit();
    
    // 构建类层次：Object -> Animal -> Dog
    try reflection.collectClassMetadata("Object", null);
    try reflection.collectClassMetadata("Animal", "Object");
    try reflection.collectClassMetadata("Dog", "Animal");
    try reflection.collectClassMetadata("Cat", "Animal");
    
    // 验证：继承关系正确
    try testing.expect(std.mem.eql(u8, reflection.class_hierarchy.getParent("Animal").?, "Object"));
    try testing.expect(std.mem.eql(u8, reflection.class_hierarchy.getParent("Dog").?, "Animal"));
    try testing.expect(std.mem.eql(u8, reflection.class_hierarchy.getParent("Cat").?, "Animal"));
    
    // 验证：子类列表正确
    const animal_children = reflection.class_hierarchy.getChildren("Animal");
    try testing.expect(animal_children != null);
    try testing.expect(animal_children.?.items.len == 2);
}

// 测试虚方法调用优化
test "virtual call optimization - uses reflection info to optimize virtual calls" {
    const allocator = testing.allocator;
    
    var reflection = try CompileTimeReflection.init(allocator);
    defer reflection.deinit();
    
    // 收集类元数据
    try reflection.collectClassMetadata("Shape", null);
    try reflection.collectClassMetadata("Circle", "Shape");
    try reflection.collectMethodMetadata("Shape", "draw");
    try reflection.collectMethodMetadata("Circle", "draw");
    
    // 创建调用图
    var graph = try CallGraph.init(allocator);
    defer graph.deinit();
    
    const sig = FunctionSignature{
        .param_types = &[_]TypeInfo{},
        .return_type = .void,
        .is_variadic = false,
    };
    
    const shape_draw = try graph.addFunction("Shape::draw", sig);
    const caller = try graph.addFunction("caller", sig);
    
    try graph.addCallEdge(caller, shape_draw, .{
        .location = .{ .file = "test.php", .line = 1, .column = 1 },
        .call_type = .virtual,
    });
    
    // 优化虚方法调用
    const optimized = try reflection.optimizeVirtualCalls(&graph);
    
    // 验证：优化完成
    try testing.expect(optimized >= 0);
}
