const std = @import("std");
const OSRManager = @import("jit/osr.zig").OSRManager;
const TypeSpecializer = @import("jit/type_specialization.zig").TypeSpecializer;
const TieredCompilation = @import("jit/tiered_compilation.zig").TieredCompilation;

test "JIT integration - OSR basic functionality" {
    const allocator = std.testing.allocator;
    var osr = OSRManager.init(allocator);
    defer osr.deinit();
    
    // 验证 OSR 点注册
    const dummy_entry = struct {
        fn entry(_: *OSRManager.InterpreterFrame) callconv(.c) void {}
    }.entry;
    
    const stack_map = OSRManager.StackMap{
        .locals = &[_]OSRManager.StackMap.LocalMapping{},
        .operand_stack = &[_]OSRManager.StackMap.OperandMapping{},
    };
    
    try osr.registerOSRPoint(100, dummy_entry, stack_map);
    try std.testing.expect(osr.canPerformOSR(100));
    try std.testing.expect(!osr.canPerformOSR(200));
}

test "JIT integration - type specialization workflow" {
    const allocator = std.testing.allocator;
    var specializer = TypeSpecializer.init(allocator);
    defer specializer.deinit();
    
    // 创建类型反馈
    var feedback = TypeSpecializer.TypeFeedback.init(allocator);
    defer feedback.deinit();
    
    // 记录类型观察（100 次 int）
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try feedback.recordType(.int);
    }
    
    // 验证类型稳定性
    try std.testing.expect(feedback.stability >= 0.95);
    
    // 特化函数
    const specialized = try specializer.specialize("testFunc", &feedback);
    try std.testing.expect(specialized != null);
    try std.testing.expectEqual(TypeSpecializer.Type.int, specialized.?.specialized_type);
}

test "JIT integration - tiered compilation progression" {
    const allocator = std.testing.allocator;
    var tiered = TieredCompilation.init(allocator);
    defer tiered.deinit();
    
    const function_name = "testFunction";
    
    // 初始状态：解释器
    _ = try tiered.recordExecution(function_name);
    try std.testing.expectEqual(TieredCompilation.Tier.interpreter, tiered.getCurrentTier(function_name).?);
    
    // 执行 100 次 → 基础 JIT
    var i: u32 = 0;
    while (i < 99) : (i += 1) {
        _ = try tiered.recordExecution(function_name);
    }
    
    const should_upgrade = try tiered.recordExecution(function_name);
    try std.testing.expect(should_upgrade);
    
    try tiered.upgrade(function_name);
    try std.testing.expectEqual(TieredCompilation.Tier.baseline_jit, tiered.getCurrentTier(function_name).?);
}

test "JIT integration - deoptimization" {
    const allocator = std.testing.allocator;
    var tiered = TieredCompilation.init(allocator);
    defer tiered.deinit();
    
    const function_name = "testFunction";
    
    // 强制编译到优化 JIT
    try tiered.forceCompile(function_name, .optimizing_jit);
    try std.testing.expectEqual(TieredCompilation.Tier.optimizing_jit, tiered.getCurrentTier(function_name).?);
    
    // 去优化
    try tiered.deoptimize(function_name);
    try std.testing.expectEqual(TieredCompilation.Tier.interpreter, tiered.getCurrentTier(function_name).?);
}

test "JIT integration - compilation stats" {
    const allocator = std.testing.allocator;
    var tiered = TieredCompilation.init(allocator);
    defer tiered.deinit();
    
    // 创建不同层级的函数
    try tiered.forceCompile("func1", .interpreter);
    try tiered.forceCompile("func2", .baseline_jit);
    try tiered.forceCompile("func3", .optimizing_jit);
    
    const stats = tiered.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.interpreter_count);
    try std.testing.expectEqual(@as(u32, 1), stats.baseline_count);
    try std.testing.expectEqual(@as(u32, 1), stats.optimizing_count);
}
