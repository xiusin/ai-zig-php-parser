const std = @import("std");
const IR = @import("ir.zig");
const Module = IR.Module;
const Instruction = IR.Instruction;
const Optimizer = @import("optimizer.zig");
const IROptimizer = Optimizer.IROptimizer;
const PassConfig = Optimizer.PassConfig;

test "IROptimizer.sccp - prunes unreachable blocks" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "test_module", "test.php");
    defer module.deinit();

    const func = try allocator.create(IR.Function);
    func.* = IR.Function.init(allocator, "test_func");
    try module.addFunction(func);

    const entry = try func.createBlock("entry");
    const header = try func.createBlock("header");
    const body = try func.createBlock("body");
    const exit = try func.createBlock("exit");

    entry.terminator = .{ .br = header };

    const cond = func.newRegister(.bool);
    const cond_inst = try allocator.create(Instruction);
    cond_inst.* = .{
        .result = cond,
        .op = .{ .const_bool = true },
        .location = .{},
    };
    try header.appendInstruction(cond_inst);
    header.terminator = .{ .cond_br = .{ .cond = cond, .then_block = body, .else_block = exit } };

    body.terminator = .{ .ret = null };
    exit.terminator = .{ .ret = null };

    var optimizer = IROptimizer.init(allocator, .none, null);
    defer optimizer.deinit();
    optimizer.config = PassConfig.debug();
    optimizer.config.loop_unroll = false;
    optimizer.config.sccp = true;

    try optimizer.optimize(&module);

    try std.testing.expect(optimizer.stats.sccp_branches_simplified >= 1);
    try std.testing.expect(optimizer.stats.dead_blocks_removed >= 1);
    try std.testing.expect(header.terminator != null and header.terminator.? == .br);
}

test "IROptimizer.rcElision - removes adjacent retain/release pairs" {
    const allocator = std.testing.allocator;

    var module = Module.init(allocator, "test_module", "test.php");
    defer module.deinit();

    const func = try allocator.create(IR.Function);
    func.* = IR.Function.init(allocator, "test_func");
    try module.addFunction(func);

    const entry = try func.createBlock("entry");
    entry.terminator = .{ .ret = null };

    const v = func.newRegister(.php_value);
    const v_inst = try allocator.create(Instruction);
    v_inst.* = .{
        .result = v,
        .op = .{ .const_null = {} },
        .location = .{},
    };
    try entry.appendInstruction(v_inst);

    const ret_inst = try allocator.create(Instruction);
    ret_inst.* = .{
        .result = null,
        .op = .{ .retain = .{ .operand = v } },
        .location = .{},
    };
    try entry.appendInstruction(ret_inst);

    const rel_inst = try allocator.create(Instruction);
    rel_inst.* = .{
        .result = null,
        .op = .{ .release = .{ .operand = v } },
        .location = .{},
    };
    try entry.appendInstruction(rel_inst);

    var optimizer = IROptimizer.init(allocator, .none, null);
    defer optimizer.deinit();
    optimizer.config = PassConfig.debug();
    optimizer.config.loop_unroll = false;
    optimizer.config.rc_elision = true;

    try optimizer.optimize(&module);

    try std.testing.expectEqual(@as(u32, 1), optimizer.stats.rc_pairs_elided);
    try std.testing.expect(optimizer.stats.rc_instructions_removed >= 2);
}
