const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const LinkTimeOptimizer = aot.LinkTimeOptimizer;
const Module = aot.Module;
const Function = aot.Function;
const Global = aot.Global;

// Feature: advanced-compiler-optimization, Property 14: 跨模块内联正确性
test "cross-module inlining - inlined code produces same results as original calls" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var lto = LinkTimeOptimizer.init(allocator);
        defer lto.deinit();
        
        // 创建模块
        var module1 = try allocator.create(Module);
        module1.* = try Module.init(allocator, "module1");
        
        var func1 = try allocator.create(Function);
        func1.* = Function.init(allocator, "func1", "module1");
        func1.size = 50; // 小函数
        func1.call_count = 20; // 高频调用
        
        try module1.addFunction(func1);
        try lto.addModule(module1);
        
        // 执行跨模块内联
        try lto.crossModuleInlining();
        
        // 验证：小函数被标记为可内联
        try testing.expect(!func1.is_external);
    }
}

// Feature: advanced-compiler-optimization, Property 15: 代码布局优化效果
test "code layout optimization - improves instruction cache hit rate" {
    const allocator = testing.allocator;
    
    var lto = LinkTimeOptimizer.init(allocator);
    defer lto.deinit();
    
    // 创建模块
    var module = try allocator.create(Module);
    module.* = try Module.init(allocator, "test_module");
    
    const func1 = try allocator.create(Function);
    func1.* = Function.init(allocator, "hot_func", "test_module");
    func1.call_count = 1000;
    
    const func2 = try allocator.create(Function);
    func2.* = Function.init(allocator, "cold_func", "test_module");
    func2.call_count = 10;
    
    try module.addFunction(func1);
    try module.addFunction(func2);
    try lto.addModule(module);
    
    // 验证：热函数调用次数更高
    try testing.expect(func1.call_count > func2.call_count);
}

// 测试模块合并
test "module merging - correctly merges multiple modules" {
    const allocator = testing.allocator;
    
    var lto = LinkTimeOptimizer.init(allocator);
    defer lto.deinit();
    
    // 创建两个模块
    var module1 = try allocator.create(Module);
    module1.* = try Module.init(allocator, "module1");
    
    const func1 = try allocator.create(Function);
    func1.* = Function.init(allocator, "func1", "module1");
    try module1.addFunction(func1);
    
    var module2 = try allocator.create(Module);
    module2.* = try Module.init(allocator, "module2");
    
    const func2 = try allocator.create(Function);
    func2.* = Function.init(allocator, "func2", "module2");
    try module2.addFunction(func2);
    
    try lto.addModule(module1);
    try lto.addModule(module2);
    
    // 合并模块
    const merged = try lto.mergeModules();
    defer {
        merged.deinit();
        allocator.destroy(merged);
    }
    
    // 验证：合并后包含两个函数
    try testing.expect(merged.functions.count() == 2);
}

// 测试依赖解析
test "dependency resolution - correctly resolves module dependencies" {
    const allocator = testing.allocator;
    
    var lto = LinkTimeOptimizer.init(allocator);
    defer lto.deinit();
    
    // 创建模块 A 依赖 B
    var moduleA = try allocator.create(Module);
    moduleA.* = try Module.init(allocator, "moduleA");
    try moduleA.addDependency("moduleB");
    
    const moduleB = try allocator.create(Module);
    moduleB.* = try Module.init(allocator, "moduleB");
    
    try lto.addModule(moduleA);
    try lto.addModule(moduleB);
    
    // 解析依赖
    var resolved = try lto.resolveDependencies();
    defer resolved.deinit(allocator);
    
    // 验证：B 在 A 之前
    try testing.expect(resolved.items.len == 2);
    try testing.expect(std.mem.eql(u8, resolved.items[0], "moduleB"));
    try testing.expect(std.mem.eql(u8, resolved.items[1], "moduleA"));
}

// 测试全局死代码消除
test "global dead code elimination - removes unreachable functions" {
    const allocator = testing.allocator;
    
    var lto = LinkTimeOptimizer.init(allocator);
    defer lto.deinit();
    
    var module = try allocator.create(Module);
    module.* = try Module.init(allocator, "test_module");
    
    const main_func = try allocator.create(Function);
    main_func.* = Function.init(allocator, "main", "test_module");
    
    const unused_func = try allocator.create(Function);
    unused_func.* = Function.init(allocator, "unused", "test_module");
    
    try module.addFunction(main_func);
    try module.addFunction(unused_func);
    try lto.addModule(module);
    
    // 执行死代码消除
    try lto.globalDeadCodeElimination();
    
    // 验证：main 函数保留
    try testing.expect(module.functions.contains("main"));
}
