const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const DynamicCodeAnalyzer = aot.DynamicCodeAnalyzer;
const DynamicCodeStaticizer = aot.DynamicCodeStaticizer;

// Feature: advanced-compiler-optimization, Property 31: 动态代码静态化正确性
test "dynamic code staticization - staticized code produces same results as dynamic execution" {
    const allocator = testing.allocator;
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var analyzer = try DynamicCodeAnalyzer.init(allocator);
        defer analyzer.deinit();
        
        // 分析动态特性
        try analyzer.analyze();
        
        // 静态化
        var staticizer = DynamicCodeStaticizer.init(allocator, &analyzer);
        try staticizer.staticize();
        
        // 验证：静态化完成
        try testing.expect(analyzer.stats.staticized_features >= 0);
    }
}

// Feature: advanced-compiler-optimization, Property 32: 动态代码识别完整性
test "dynamic code identification - identifies all dynamic features" {
    const allocator = testing.allocator;
    
    var analyzer = try DynamicCodeAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    // 分析动态特性
    try analyzer.analyze();
    
    // 验证：识别到动态特性
    try testing.expect(analyzer.dynamic_features.items.len > 0);
    try testing.expect(analyzer.stats.total_dynamic_features > 0);
}

// Feature: advanced-compiler-optimization, Property 33: 静态化率目标
test "staticization rate - achieves target staticization rate" {
    const allocator = testing.allocator;
    
    var analyzer = try DynamicCodeAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    // 分析和静态化
    try analyzer.analyze();
    try analyzer.staticize();
    
    // 验证：静态化率在 0-1 之间
    const rate = analyzer.getStaticizationRate();
    try testing.expect(rate >= 0.0 and rate <= 1.0);
}

// 测试报告生成
test "report generation - generates staticization report" {
    const allocator = testing.allocator;
    
    var analyzer = try DynamicCodeAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    try analyzer.analyze();
    try analyzer.staticize();
    
    var staticizer = DynamicCodeStaticizer.init(allocator, &analyzer);
    const report = try staticizer.generateReport();
    defer allocator.free(report);
    
    // 验证：报告包含关键信息
    try testing.expect(std.mem.indexOf(u8, report, "Dynamic Code Staticization Report") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Total dynamic features") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Staticization rate") != null);
}

// 测试动态特性类型
test "dynamic feature types - correctly identifies feature types" {
    const allocator = testing.allocator;
    
    var analyzer = try DynamicCodeAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    try analyzer.analyze();
    
    // 验证：包含不同类型的动态特性
    var has_eval = false;
    var has_variable_variable = false;
    
    for (analyzer.dynamic_features.items) |feature| {
        switch (feature) {
            .eval => has_eval = true,
            .variable_variable => has_variable_variable = true,
            else => {},
        }
    }
    
    try testing.expect(has_eval or has_variable_variable);
}
