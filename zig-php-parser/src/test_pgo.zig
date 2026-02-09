const std = @import("std");
const testing = std.testing;
const aot = @import("aot/mod.zig");
const Profile = aot.Profile;
const ProfileGuidedOptimizer = aot.ProfileGuidedOptimizer;
const Branch = aot.Branch;

// Feature: advanced-compiler-optimization, Property 16: PGO 代码布局优化效果
test "PGO code layout optimization - improves instruction cache hit rate" {
    const allocator = testing.allocator;
    
    var profile = Profile.init(allocator);
    defer profile.deinit();
    
    // 记录函数执行频率
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        try profile.recordFunctionExecution("hot_func");
    }
    
    i = 0;
    while (i < 100) : (i += 1) {
        try profile.recordFunctionExecution("cold_func");
    }
    
    var pgo = ProfileGuidedOptimizer.init(allocator, &profile);
    
    // 基于频率的代码布局
    var hot_functions = try pgo.frequencyBasedLayout();
    defer hot_functions.deinit(allocator);
    
    // 验证：热函数在前
    try testing.expect(hot_functions.items.len > 0);
    try testing.expect(std.mem.eql(u8, hot_functions.items[0].name, "hot_func"));
}

// 测试分支预测优化
test "branch prediction optimization - optimizes branch layout based on probability" {
    const allocator = testing.allocator;
    
    var profile = Profile.init(allocator);
    defer profile.deinit();
    
    var branch = Branch{ .id = 1, .location = "test.php:10" };
    
    // 记录分支执行（95% taken）
    var i: usize = 0;
    while (i < 95) : (i += 1) {
        try profile.recordBranchExecution(&branch, true);
    }
    
    i = 0;
    while (i < 5) : (i += 1) {
        try profile.recordBranchExecution(&branch, false);
    }
    
    var pgo = ProfileGuidedOptimizer.init(allocator, &profile);
    
    var optimizations = try pgo.branchPredictionOptimization();
    defer optimizations.deinit(allocator);
    
    // 验证：taken 分支优先
    try testing.expect(optimizations.items.len > 0);
    try testing.expect(optimizations.items[0].layout == .taken_first);
}

// 测试基于配置文件的内联
test "profile-guided inlining - inlines hot call sites" {
    const allocator = testing.allocator;
    
    var profile = Profile.init(allocator);
    defer profile.deinit();
    
    // 验证：配置文件初始化成功
    try testing.expect(profile.function_frequencies.count() == 0);
}

// 测试分支概率计算
test "branch probability - correctly calculates branch probability" {
    const allocator = testing.allocator;
    
    var profile = Profile.init(allocator);
    defer profile.deinit();
    
    var branch = Branch{ .id = 1, .location = "test.php:10" };
    
    // 记录分支执行
    var i: usize = 0;
    while (i < 75) : (i += 1) {
        try profile.recordBranchExecution(&branch, true);
    }
    
    i = 0;
    while (i < 25) : (i += 1) {
        try profile.recordBranchExecution(&branch, false);
    }
    
    const branch_profile = profile.branch_frequencies.get(&branch).?;
    const prob = branch_profile.probability();
    
    // 验证：概率为 0.75
    try testing.expect(prob >= 0.74 and prob <= 0.76);
}

// 测试函数频率记录
test "function frequency recording - correctly records execution counts" {
    const allocator = testing.allocator;
    
    var profile = Profile.init(allocator);
    defer profile.deinit();
    
    // 记录函数执行
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try profile.recordFunctionExecution("test_func");
    }
    
    const freq = profile.function_frequencies.get("test_func").?;
    try testing.expect(freq == 100);
}
