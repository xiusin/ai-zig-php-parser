const std = @import("std");
const AdvancedOptimizer = @import("aot/advanced_optimizer.zig").AdvancedOptimizer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("\n❌ 检测到内存泄漏！\n", .{});
            std.process.exit(1);
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("=== AOT 高级优化器测试 ===\n\n", .{});

    // 创建优化器
    var optimizer = AdvancedOptimizer.init(allocator);
    defer optimizer.deinit();

    std.debug.print("📊 测试 1: 标量替换\n", .{});
    {
        const allocations = [_]bool{ false, false, false, true, true };
        const result = try optimizer.scalarReplacement(&allocations);
        std.debug.print("  非逃逸对象: {d}\n", .{result});
    }

    std.debug.print("\n📊 测试 2: 全局值编号 (GVN)\n", .{});
    {
        const expressions = [_]u64{ 0x1234, 0x5678, 0x1234, 0x9ABC, 0x5678 };
        const result = try optimizer.globalValueNumbering(&expressions);
        std.debug.print("  消除的冗余表达式: {d}\n", .{result});
    }

    std.debug.print("\n📊 测试 3: 稀疏条件常量传播 (SCCP)\n", .{});
    {
        const variables = [_]u32{ 1, 2, 3, 4 };
        const initial_values = [_]?i64{ 10, null, 20, null };
        const result = try optimizer.sparseConditionalConstantPropagation(&variables, &initial_values);
        std.debug.print("  传播的常量: {d}\n", .{result});
    }

    std.debug.print("\n📊 测试 4: SLP 向量化\n", .{});
    {
        const group1 = [_]u32{ 1, 2, 3, 4 };
        const group2 = [_]u32{ 5, 6, 7, 8 };
        const groups = [_][]const u32{ &group1, &group2 };
        const result = try optimizer.superwordLevelParallelism(&groups);
        std.debug.print("  向量化的指令组: {d}\n", .{result});
    }

    std.debug.print("\n📊 测试 5: 多面体循环优化\n", .{});
    {
        const loop1 = AdvancedOptimizer.LoopInfo{ 
            .nest_depth = 2, 
            .is_affine = true,
            .is_vectorizable = false,
            .has_dependencies = false,
        };
        const loop2 = AdvancedOptimizer.LoopInfo{ 
            .nest_depth = 3, 
            .is_affine = true,
            .is_vectorizable = false,
            .has_dependencies = false,
        };
        const loop3 = AdvancedOptimizer.LoopInfo{ 
            .nest_depth = 1, 
            .is_affine = false,
            .is_vectorizable = false,
            .has_dependencies = false,
        };
        const loops = [_]AdvancedOptimizer.LoopInfo{ loop1, loop2, loop3 };
        const result = try optimizer.polyhedralLoopOptimization(&loops);
        std.debug.print("  变换的循环: {d}\n", .{result});
    }

    std.debug.print("\n📊 测试 6: 循环向量化\n", .{});
    {
        const loop1 = AdvancedOptimizer.LoopInfo{ 
            .nest_depth = 1, 
            .is_affine = true,
            .is_vectorizable = true,
            .has_dependencies = false,
        };
        const loop2 = AdvancedOptimizer.LoopInfo{ 
            .nest_depth = 1, 
            .is_affine = true,
            .is_vectorizable = true,
            .has_dependencies = false,
        };
        const loop3 = AdvancedOptimizer.LoopInfo{ 
            .nest_depth = 2, 
            .is_affine = false,
            .is_vectorizable = false,
            .has_dependencies = true,
        };
        const loops = [_]AdvancedOptimizer.LoopInfo{ loop1, loop2, loop3 };
        const result = try optimizer.loopVectorization(&loops);
        std.debug.print("  向量化的循环: {d}\n", .{result});
    }

    std.debug.print("\n✅ 所有测试完成！\n", .{});
    std.debug.print("✅ 无内存泄漏！\n", .{});
}
