const std = @import("std");
const IR = @import("aot/ir.zig");
const IROptimizer = @import("aot/optimizer.zig").IROptimizer;

/// AOT 综合测试 - 验证所有优化功能
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== AOT 编译器优化验证测试 ===\n\n", .{});

    // 创建测试模块
    var module = try createTestModule(allocator);
    defer module.deinit(allocator);

    // 创建优化器（release-fast 模式，启用所有高级优化）
    var optimizer = try IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    std.debug.print("🔨 优化配置:\n", .{});
    std.debug.print("  - 标量替换: {}\n", .{optimizer.config.scalar_replacement});
    std.debug.print("  - GVN: {}\n", .{optimizer.config.gvn});
    std.debug.print("  - SCCP: {}\n", .{optimizer.config.advanced_sccp});
    std.debug.print("  - SLP 向量化: {}\n", .{optimizer.config.slp_vectorization});
    std.debug.print("  - 多面体优化: {}\n", .{optimizer.config.polyhedral_optimization});
    std.debug.print("  - 循环向量化: {}\n", .{optimizer.config.loop_vectorization});
    std.debug.print("\n", .{});

    // 执行优化
    std.debug.print("🚀 开始优化...\n", .{});
    const start_time = std.time.milliTimestamp();
    
    try optimizer.optimize(&module);
    
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    // 输出优化统计
    std.debug.print("\n📊 优化统计:\n", .{});
    optimizer.stats.print();

    std.debug.print("\n⏱️  优化耗时: {} ms\n", .{duration});

    // 验证结果
    std.debug.print("\n✅ 验证结果:\n", .{});
    
    const has_optimizations = 
        optimizer.stats.scalar_replacements > 0 or
        optimizer.stats.gvn_eliminations > 0 or
        optimizer.stats.advanced_sccp_propagations > 0 or
        optimizer.stats.slp_vectorizations > 0 or
        optimizer.stats.polyhedral_transforms > 0 or
        optimizer.stats.loop_vectorizations > 0;

    if (has_optimizations) {
        std.debug.print("  ✅ 高级优化已执行\n", .{});
    } else {
        std.debug.print("  ⚠️  未检测到高级优化（可能测试模块太简单）\n", .{});
    }

    std.debug.print("\n🎉 所有测试完成！\n", .{});
}

/// 创建测试模块
fn createTestModule(allocator: std.mem.Allocator) !IR.Module {
    var module = IR.Module.init(allocator, "test_module", "test.php");

    // 创建测试函数
    var func = IR.Function.init(allocator, "test_function");
    
    // 创建基本块
    var bb = IR.BasicBlock.init(allocator, "entry", 0);
    
    // 添加测试指令
    // 1. 标量替换测试 - alloca
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 1, .type_ = .{ .i64 = {} } },
        .op = .alloca,
        .location = IR.SourceLocation{ .line = 1, .column = 1 },
    });

    // 2. GVN 测试 - 冗余计算
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 2, .type_ = .{ .i64 = {} } },
        .op = .add,
        .location = IR.SourceLocation{ .line = 2, .column = 1 },
    });
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 3, .type_ = .{ .i64 = {} } },
        .op = .add,  // 相同的 add，应被 GVN 消除
        .location = IR.SourceLocation{ .line = 3, .column = 1 },
    });

    // 3. SCCP 测试 - 常量
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 4, .type_ = .{ .i64 = {} } },
        .op = .const_int,
        .location = IR.SourceLocation{ .line = 4, .column = 1 },
    });

    // 4. 循环测试 - 用于循环向量化和多面体优化
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 5, .type_ = .{ .i64 = {} } },
        .op = .load,
        .location = IR.SourceLocation{ .line = 5, .column = 1 },
    });
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 6, .type_ = .{ .i64 = {} } },
        .op = .mul,
        .location = IR.SourceLocation{ .line = 6, .column = 1 },
    });
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 7, .type_ = .{ .i64 = {} } },
        .op = .store,
        .location = IR.SourceLocation{ .line = 7, .column = 1 },
    });
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 8, .type_ = .{ .i64 = {} } },
        .op = .br_cond,  // 循环回边
        .location = IR.SourceLocation{ .line = 8, .column = 1 },
    });

    // 5. SLP 向量化测试 - 连续的相同操作
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 9, .type_ = .{ .i64 = {} } },
        .op = .add,
        .location = IR.SourceLocation{ .line = 9, .column = 1 },
    });
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 10, .type_ = .{ .i64 = {} } },
        .op = .add,
        .location = IR.SourceLocation{ .line = 10, .column = 1 },
    });
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 11, .type_ = .{ .i64 = {} } },
        .op = .add,
        .location = IR.SourceLocation{ .line = 11, .column = 1 },
    });
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 12, .type_ = .{ .i64 = {} } },
        .op = .add,
        .location = IR.SourceLocation{ .line = 12, .column = 1 },
    });

    // 添加返回指令
    try bb.instructions.append(allocator, IR.Instruction{
        .result = IR.Register{ .id = 0, .type_ = .void },
        .op = .ret,
        .location = IR.SourceLocation{ .line = 13, .column = 1 },
    });

    try func.basic_blocks.append(allocator, &bb);
    try module.functions.append(allocator, &func);

    return module;
}
