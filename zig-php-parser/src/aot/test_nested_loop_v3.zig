//! 嵌套循环代码生成 V3 单元测试
//! 验证 ZigCodeBuilder + NestedLoopCodegenV3 的正确性

const std = @import("std");
const ZigCodeBuilder = @import("zig_code_builder.zig").ZigCodeBuilder;
const NestedLoopCodegen = @import("nested_loop_codegen.zig");
const IR = @import("ir.zig");
const TypeConstraintSolver = @import("type_constraint_solver.zig").TypeConstraintSolver;

// ============================================================
// ZigCodeBuilder 测试
// ============================================================

test "ZigCodeBuilder: 基础缩进正确性" {
    const allocator = std.testing.allocator;
    var builder = try ZigCodeBuilder.init(allocator);
    defer builder.deinit();

    try builder.writeLine("const x = 1;");
    try builder.beginScope("while (true)");
    try builder.writeLine("x += 1;");
    try builder.beginScope("if (x > 10)");
    try builder.writeLine("break;");
    try builder.endScope();
    try builder.endScope();

    const code = builder.getCode();
    try std.testing.expect(std.mem.indexOf(u8, code, "const x = 1;\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "    x += 1;\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "        break;\n") != null);
}

test "ZigCodeBuilder: 3层嵌套作用域" {
    const allocator = std.testing.allocator;
    var builder = try ZigCodeBuilder.init(allocator);
    defer builder.deinit();

    try builder.beginWhileTrue();
    try builder.writeComment("L1");
    try builder.beginWhileTrue();
    try builder.writeComment("L2");
    try builder.beginWhileTrue();
    try builder.writeComment("L3");
    try builder.writeBreak();
    try builder.endScope();
    try builder.endScope();
    try builder.endScope();

    const code = builder.getCode();
    // L3 的 break 应有 3 层缩进 = 12 空格
    try std.testing.expect(std.mem.indexOf(u8, code, "            break;\n") != null);
    // 验证 3 个闭合花括号
    var close_count: usize = 0;
    for (code) |c| {
        if (c == '}') close_count += 1;
    }
    try std.testing.expect(close_count == 3);
}

test "ZigCodeBuilder: writeLineFmt 格式化" {
    const allocator = std.testing.allocator;
    var builder = try ZigCodeBuilder.init(allocator);
    defer builder.deinit();

    builder.indent();
    try builder.writeLineFmt("reg_{d} = {d};", .{ 5, 42 });

    const code = builder.getCode();
    try std.testing.expect(std.mem.indexOf(u8, code, "    reg_5 = 42;\n") != null);
}

// ============================================================
// TypeConstraintSolver 增强测试
// ============================================================

test "TypeConstraintSolver: PHI 乐观推断" {
    const allocator = std.testing.allocator;
    var solver = TypeConstraintSolver.init(allocator);
    defer solver.deinit();

    // reg_0 = const_int (i64)
    try solver.addConcrete(0, .{ .i64 = {} });

    // reg_1 = phi(reg_0, reg_2) — reg_2 尚未知
    try solver.addPhi(&[_]usize{ 0, 2 }, 1);

    // reg_2 = add(reg_1, reg_3) — 二元运算
    try solver.addBinaryOp(1, 3, 2);

    // reg_3 = const_int (i64)
    try solver.addConcrete(3, .{ .i64 = {} });

    try solver.solve();

    // reg_1 应该被推断为 i64（通过乐观推断从 reg_0 传播）
    const t1 = solver.getInferredType(1);
    try std.testing.expect(t1 != null);
    const tag1 = @as(std.meta.Tag(IR.Type), t1.?);
    try std.testing.expect(tag1 == .i64);

    // reg_2 也应该是 i64
    const t2 = solver.getInferredType(2);
    try std.testing.expect(t2 != null);
    const tag2 = @as(std.meta.Tag(IR.Type), t2.?);
    try std.testing.expect(tag2 == .i64);
}

test "TypeConstraintSolver: 类型提升 i64+f64→f64" {
    const allocator = std.testing.allocator;
    var solver = TypeConstraintSolver.init(allocator);
    defer solver.deinit();

    // reg_0 = i64, reg_1 = f64
    try solver.addConcrete(0, .{ .i64 = {} });
    try solver.addConcrete(1, .{ .f64 = {} });

    // reg_2 = phi(reg_0, reg_1) → 应提升为 f64
    try solver.addPhi(&[_]usize{ 0, 1 }, 2);

    try solver.solve();

    const t2 = solver.getInferredType(2);
    try std.testing.expect(t2 != null);
    const tag2 = @as(std.meta.Tag(IR.Type), t2.?);
    try std.testing.expect(tag2 == .f64);
}

test "TypeConstraintSolver: 反向传播 result→incoming" {
    const allocator = std.testing.allocator;
    var solver = TypeConstraintSolver.init(allocator);
    defer solver.deinit();

    // reg_0 已知 i64
    try solver.addConcrete(0, .{ .i64 = {} });

    // reg_1 = phi(reg_0, reg_2)
    try solver.addPhi(&[_]usize{ 0, 2 }, 1);

    try solver.solve();

    // reg_1 通过乐观推断应为 i64
    const t1 = solver.getInferredType(1);
    try std.testing.expect(t1 != null);
    const tag1 = @as(std.meta.Tag(IR.Type), t1.?);
    try std.testing.expect(tag1 == .i64);

    // reg_2 通过反向传播也应为 i64
    const t2 = solver.getInferredType(2);
    try std.testing.expect(t2 != null);
    const tag2 = @as(std.meta.Tag(IR.Type), t2.?);
    try std.testing.expect(tag2 == .i64);
}

// ============================================================
// LoopMetadata 测试
// ============================================================

test "LoopMetadata: 基本结构" {
    var meta = IR.LoopMetadata{};
    try std.testing.expect(!meta.isInLoop());

    meta.depth = 1;
    meta.role = .header;
    try std.testing.expect(meta.isInLoop());
    try std.testing.expect(meta.role == .header);
}
