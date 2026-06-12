const std = @import("std");
const IR = @import("ir.zig");
const Module = IR.Module;
const Instruction = IR.Instruction;
const Optimizer = @import("optimizer.zig");
const IROptimizer = Optimizer.IROptimizer;

test "IROptimizer.runLICM - hoist invariant" {
    const allocator = std.testing.allocator;
    
    // Setup module and function
    var module = Module.init(allocator, "test_module", "test.php");
    defer module.deinit();
    
    const func = try allocator.create(IR.Function);
    func.* = IR.Function.init(allocator, "test_func");
    try module.addFunction(func);
    
    // Create blocks
    const entry = try func.createBlock("entry");
    const header = try func.createBlock("header");
    const body = try func.createBlock("body");
    const latch = try func.createBlock("latch");
    const exit = try func.createBlock("exit");
    
    // Define invariants in entry
    const a = func.newRegister(.i64);
    const b = func.newRegister(.i64);
    
    const inst_a = try allocator.create(Instruction);
    inst_a.* = .{
        .result = a,
        .op = .{ .const_int = 10 },
        .location = .{},
    };
    try entry.appendInstruction(inst_a);

    const inst_b = try allocator.create(Instruction);
    inst_b.* = .{
        .result = b,
        .op = .{ .const_int = 20 },
        .location = .{},
    };
    try entry.appendInstruction(inst_b);

    entry.terminator = .{ .br = header };
    
    // Header: loop condition
    // i < 100
    const i = func.newRegister(.i64); // Phi for i
    const cond = func.newRegister(.bool);
    
    // Initial Phi with just entry (we'll update it later)
    const phi_inst = try allocator.create(Instruction);
    phi_inst.* = .{
        .result = i,
        .op = .{ .phi = .{ .incoming = try allocator.dupe(Instruction.PhiIncoming, &[_]Instruction.PhiIncoming{
            .{ .value = a, .block = entry }, // Initial i = a (10)
        }) } },
        .location = .{},
    };
    try header.appendInstruction(phi_inst);
    
    const cond_inst = try allocator.create(Instruction);
    cond_inst.* = .{
        .result = cond,
        .op = .{ .lt = .{ .lhs = i, .rhs = b } }, // i < 20
        .location = .{},
    };
    try header.appendInstruction(cond_inst);

    header.terminator = .{ .cond_br = .{ .cond = cond, .then_block = body, .else_block = exit } };
    
    // Body: invariant calculation
    // x = a + b (invariant)
    const x = func.newRegister(.i64);
    const x_inst = try allocator.create(Instruction);
    x_inst.* = .{
        .result = x,
        .op = .{ .add = .{ .lhs = a, .rhs = b } },
        .location = .{},
    };
    try body.appendInstruction(x_inst);
    
    // y = x + i (variant)
    const y = func.newRegister(.i64);
    const y_inst = try allocator.create(Instruction);
    y_inst.* = .{
        .result = y,
        .op = .{ .add = .{ .lhs = x, .rhs = i } },
        .location = .{},
    };
    try body.appendInstruction(y_inst);
    
    body.terminator = .{ .br = latch };
    
    // Latch: increment i
    const i_next = func.newRegister(.i64);
    const one = func.newRegister(.i64);

    const one_inst = try allocator.create(Instruction);
    one_inst.* = .{
        .result = one,
        .op = .{ .const_int = 1 },
        .location = .{},
    };
    try latch.appendInstruction(one_inst);

    const i_next_inst = try allocator.create(Instruction);
    i_next_inst.* = .{
        .result = i_next,
        .op = .{ .add = .{ .lhs = i, .rhs = one } },
        .location = .{},
    };
    try latch.appendInstruction(i_next_inst);

    latch.terminator = .{ .br = header };
    
    // Update Phi in header
    // We have to access the instruction we created.
    // It's the first instruction in header.
    const old_incoming = phi_inst.op.phi.incoming;
    // Allocate new slice
    const new_incoming = try allocator.alloc(Instruction.PhiIncoming, 2);
    new_incoming[0] = old_incoming[0];
    new_incoming[1] = .{ .value = i_next, .block = latch };
    
    // Free old slice (since we duped it)
    allocator.free(old_incoming);
    
    // Assign new slice
    phi_inst.op.phi.incoming = new_incoming;
    
    // Exit
    exit.terminator = .{ .ret = null };
    
    // Run Optimizer with LICM enabled
    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();
    
    // Ensure LICM is enabled, Loop Unroll is disabled (to avoid interfering with LICM test)
    optimizer.config.licm = true;
    optimizer.config.loop_unroll = false;
    
    // Run optimization
    _ = try optimizer.runLICMInFunction(func);
    
    // Verify results
    // The invariant instruction `x = a + b` should be moved to `entry` (or a new pre-header).
    // `entry` dominates `header`, and `entry` flows only to `header`.
    // So `entry` is a valid pre-header.
    
    // Check if `x` definition is in `entry`
    var found_in_entry = false;
    for (entry.instructions.items) |inst| {
        if (inst.result) |res| {
            if (res.id == x.id) {
                found_in_entry = true;
                break;
            }
        }
    }
    
    try std.testing.expect(found_in_entry);
    
    // Check if `x` definition is NOT in `body`
    var found_in_body = false;
    for (body.instructions.items) |inst| {
        if (inst.result) |res| {
            if (res.id == x.id) {
                found_in_body = true;
                break;
            }
        }
    }
    try std.testing.expect(!found_in_body);
}
