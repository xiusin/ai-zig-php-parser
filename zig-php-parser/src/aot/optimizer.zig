//! IR Optimizer for AOT Compiler
//!
//! This module provides optimization passes for the IR before code generation.
//! It implements:
//! - Dead Code Elimination (DCE)
//! - Function Inlining (for small functions)
//! - Type Specialization
//! - Constant Propagation
//! - Common Subexpression Elimination (CSE)
//!
//! ## Usage
//!
//! ```zig
//! var optimizer = try IROptimizer.init(allocator, .release_fast);
//! defer optimizer.deinit();
//!
//! try optimizer.optimize(ir_module);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const Module = IR.Module;
const Function = IR.Function;
const BasicBlock = IR.BasicBlock;
const Instruction = IR.Instruction;
const Register = IR.Register;
const Type = IR.Type;
const Terminator = IR.Terminator;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const Analysis = @import("analysis.zig");

// ============================================================================
// Optimization Level Configuration
// ============================================================================

/// Optimization level for IR passes
pub const OptimizeLevel = enum {
    /// No optimizations (debug mode)
    none,
    /// Basic optimizations (release-safe)
    basic,
    /// Aggressive optimizations (release-fast)
    aggressive,
    /// Size optimizations (release-small)
    size,

    /// Get default pass configuration for this level
    pub fn getPassConfig(self: OptimizeLevel) PassConfig {
        return switch (self) {
            .none => PassConfig.debug(),
            .basic => PassConfig.releaseSafe(),
            .aggressive => PassConfig.releaseFast(),
            .size => PassConfig.releaseSmall(),
        };
    }
};

/// Configuration for optimization passes
pub const PassConfig = struct {
    /// Enable dead code elimination
    dead_code_elimination: bool = true,
    /// Enable constant propagation
    constant_propagation: bool = true,
    /// Enable box/unbox elimination
    box_unbox_elim: bool = true,
    /// Enable function inlining
    function_inlining: bool = false,
    /// Maximum function size (in instructions) for inlining
    inline_threshold: u32 = 20,
    /// Enable type specialization
    type_specialization: bool = false,
    /// Enable common subexpression elimination
    cse: bool = false,
    /// Enable loop-invariant code motion
    licm: bool = false,
    /// Enable strength reduction
    strength_reduction: bool = false,
    /// Enable Mem2Reg (promote memory to registers)
    mem2reg: bool = false,
    /// Enable loop unrolling
    loop_unroll: bool = false,
    /// Enable CFG cleanup (block merge, trivial branch simplification, phi cleanup)
    cfg_cleanup: bool = true,
    /// Loop unroll factor (number of copies)
    unroll_factor: u32 = 4,
    /// Maximum optimization iterations
    max_iterations: u32 = 3,

    /// Debug configuration (no optimizations)
    pub fn debug() PassConfig {
        return .{
            .dead_code_elimination = false,
            .constant_propagation = false,
            .box_unbox_elim = false,
            .function_inlining = false,
            .inline_threshold = 0,
            .type_specialization = false,
            .cse = false,
            .licm = false,
            .strength_reduction = false,
            .mem2reg = false,
            .loop_unroll = true,
            .cfg_cleanup = false,
            .max_iterations = 1,
        };
    }

    /// Release-safe configuration (basic optimizations)
    pub fn releaseSafe() PassConfig {
        return .{
            .dead_code_elimination = true,
            .constant_propagation = true,
            .box_unbox_elim = true,
            .function_inlining = false,
            .inline_threshold = 10,
            .type_specialization = false,
            .cse = true,
            .licm = false,
            .strength_reduction = false,
            .mem2reg = true,
            .loop_unroll = true,
            .cfg_cleanup = true,
            .max_iterations = 2,
        };
    }

    /// Release-fast configuration (aggressive optimizations)
    pub fn releaseFast() PassConfig {
        return .{
            .dead_code_elimination = true,
            .constant_propagation = true,
            .box_unbox_elim = true,
            .function_inlining = true,
            .inline_threshold = 50,
            .type_specialization = true,
            .cse = true,
            .licm = true,
            .strength_reduction = true,
            .mem2reg = true,
            .loop_unroll = true,
            .cfg_cleanup = true,
            .max_iterations = 5,
        };
    }

    /// Release-small configuration (size optimizations)
    pub fn releaseSmall() PassConfig {
        return .{
            .dead_code_elimination = true,
            .constant_propagation = true,
            .box_unbox_elim = true,
            .function_inlining = false, // Inlining increases size
            .inline_threshold = 5,
            .type_specialization = false,
            .cse = true,
            .licm = false,
            .strength_reduction = true,
            .mem2reg = true,
            .loop_unroll = false, // Unrolling increases size
            .cfg_cleanup = true,
            .max_iterations = 2,
        };
    }
};

// ============================================================================
// Optimization Statistics
// ============================================================================

/// Statistics collected during optimization
pub const OptimizationStats = struct {
    /// Number of dead instructions removed
    dead_instructions_removed: u32 = 0,
    /// Number of dead blocks removed
    dead_blocks_removed: u32 = 0,
    /// Number of constants propagated
    constants_propagated: u32 = 0,
    /// Number of functions inlined
    functions_inlined: u32 = 0,
    /// Number of type specializations applied
    type_specializations: u32 = 0,
    /// Number of common subexpressions eliminated
    cse_eliminations: u32 = 0,
    /// Number of allocas promoted to registers
    allocas_promoted: u32 = 0,
    /// Number of loops unrolled
    loops_unrolled: u32 = 0,
    /// Number of optimization passes run
    passes_run: u32 = 0,

    /// Reset all statistics
    pub fn reset(self: *OptimizationStats) void {
        self.* = .{};
    }

    /// Print statistics summary
    pub fn print(self: *const OptimizationStats, writer: anytype) !void {
        try writer.writeAll("Optimization Statistics:\n");
        try writer.print("  Dead instructions removed: {d}\n", .{self.dead_instructions_removed});
        try writer.print("  Dead blocks removed: {d}\n", .{self.dead_blocks_removed});
        try writer.print("  Constants propagated: {d}\n", .{self.constants_propagated});
        try writer.print("  Functions inlined: {d}\n", .{self.functions_inlined});
        try writer.print("  Type specializations: {d}\n", .{self.type_specializations});
        try writer.print("  CSE eliminations: {d}\n", .{self.cse_eliminations});
        try writer.print("  Loops unrolled: {d}\n", .{self.loops_unrolled});
        try writer.print("  Passes run: {d}\n", .{self.passes_run});
    }
};

// ============================================================================
// IR Optimizer
// ============================================================================

/// IR Optimizer - applies optimization passes to IR modules
pub const IROptimizer = struct {
    allocator: Allocator,
    config: PassConfig,
    stats: OptimizationStats,
    diagnostics: ?*DiagnosticEngine,
    verify_ir: bool = false,

    /// Set of used registers (for dead code elimination)
    used_registers: std.AutoHashMap(u32, void),
    /// Constant values for propagation
    constant_values: std.AutoHashMap(u32, ConstantValue),
    /// Function call graph for inlining decisions
    call_graph: std.StringHashMap(FunctionInfo),
    /// Scratch map for type specialization to avoid per-function allocations
    type_known_types: std.AutoHashMap(u32, Type),

    const Self = @This();

    /// Constant value representation
    pub const ConstantValue = union(enum) {
        int: i64,
        float: f64,
        bool_val: bool,
        null_val: void,
        missing_val: void,
        string_id: u32,
    };

    /// Function information for inlining
    pub const FunctionInfo = struct {
        instruction_count: u32,
        call_count: u32,
        block_count: u32,
        branch_count: u32,
        alloc_count: u32,
        may_throw: bool,
        estimated_cost: u32,
        has_side_effects: bool,
        is_recursive: bool,
        can_inline: bool,
    };

    /// Initialize the optimizer
    pub fn init(allocator: Allocator, level: OptimizeLevel, diagnostics: ?*DiagnosticEngine) Self {
        return .{
            .allocator = allocator,
            .config = level.getPassConfig(),
            .stats = .{},
            .diagnostics = diagnostics,
            .verify_ir = false,
            .used_registers = std.AutoHashMap(u32, void).init(allocator),
            .constant_values = std.AutoHashMap(u32, ConstantValue).init(allocator),
            .call_graph = std.StringHashMap(FunctionInfo).init(allocator),
            .type_known_types = std.AutoHashMap(u32, Type).init(allocator),
        };
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: Allocator, config: PassConfig, diagnostics: ?*DiagnosticEngine) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .stats = .{},
            .diagnostics = diagnostics,
            .verify_ir = false,
            .used_registers = std.AutoHashMap(u32, void).init(allocator),
            .constant_values = std.AutoHashMap(u32, ConstantValue).init(allocator),
            .call_graph = std.StringHashMap(FunctionInfo).init(allocator),
            .type_known_types = std.AutoHashMap(u32, Type).init(allocator),
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.used_registers.deinit();
        self.constant_values.deinit();
        self.call_graph.deinit();
        self.type_known_types.deinit();
    }

    /// Get optimization statistics
    pub fn getStats(self: *const Self) OptimizationStats {
        return self.stats;
    }

    /// Reset optimization statistics
    pub fn resetStats(self: *Self) void {
        self.stats.reset();
    }

    // ========================================================================
    // Main Optimization Entry Point
    // ========================================================================

    /// Optimize an IR module
    pub fn optimize(self: *Self, module: *Module) !void {
        // Build call graph for inlining decisions
        try self.buildCallGraph(module);

        // Run optimization passes iteratively
        var iteration: u32 = 0;
        var changed = true;

        while (changed and iteration < self.config.max_iterations) {
            changed = false;
            iteration += 1;
            self.stats.passes_run += 1;

            // Run each enabled pass
            if (self.config.mem2reg) {
                if (try self.runMem2Reg(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.constant_propagation) {
                if (try self.runConstantPropagation(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.box_unbox_elim) {
                if (try self.runBoxUnboxElimination(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.dead_code_elimination) {
                if (try self.runDeadCodeElimination(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.function_inlining) {
                if (try self.runFunctionInlining(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.type_specialization) {
                if (try self.runTypeSpecialization(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.cse) {
                if (try self.runCSE(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.strength_reduction) {
                if (try self.runStrengthReduction(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.licm) {
                if (try self.runLICM(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.loop_unroll) {
                if (try self.runLoopUnroll(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (changed and self.config.dead_code_elimination and (self.config.licm or self.config.loop_unroll)) {
                if (try self.runDeadCodeElimination(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }

            if (self.config.cfg_cleanup) {
                if (try self.runCFGCleanup(module)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyModule(module);
            }
        }
    }

    /// Optimize a single function
    pub fn optimizeFunction(self: *Self, func: *Function) !void {
        var changed = true;
        var iteration: u32 = 0;

        while (changed and iteration < self.config.max_iterations) {
            changed = false;
            iteration += 1;

            if (self.config.mem2reg) {
                if (try self.promoteMemoryToRegisters(func)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyFunction(func);
            }

            if (self.config.constant_propagation) {
                if (try self.propagateConstantsInFunction(func)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyFunction(func);
            }

            if (self.config.box_unbox_elim) {
                if (try self.eliminateBoxUnboxInFunction(func)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyFunction(func);
            }

            if (self.config.dead_code_elimination) {
                if (try self.eliminateDeadCodeInFunction(func)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyFunction(func);
            }

            if (self.config.cse) {
                if (try self.eliminateCSEInFunction(func)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyFunction(func);
            }

            if (self.config.licm) {
                if (try self.runLICMInFunction(func)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyFunction(func);
            }

            if (changed and self.config.dead_code_elimination and self.config.licm) {
                if (try self.eliminateDeadCodeInFunction(func)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyFunction(func);
            }

            if (self.config.cfg_cleanup) {
                if (try self.cleanupCFGInFunction(func)) {
                    changed = true;
                }
                if (self.verify_ir) try self.verifyFunction(func);
            }
        }
    }

    fn verifyModule(self: *Self, module: *Module) !void {
        for (module.functions.items) |func| {
            try self.verifyFunction(func);
        }
    }

    fn verifyFunction(self: *Self, func: *Function) !void {
        var block_set = std.AutoHashMap(*BasicBlock, void).init(self.allocator);
        defer block_set.deinit();

        for (func.blocks.items) |b| {
            try block_set.put(b, {});
        }

        for (func.blocks.items) |b| {
            if (b.exception_handler) |h| {
                if (!block_set.contains(h)) return error.InvalidIR;
            }

            for (b.predecessors.items) |p| {
                if (!block_set.contains(p)) return error.InvalidIR;
            }

            for (b.successors.items) |s| {
                if (!block_set.contains(s)) return error.InvalidIR;
            }

            if (b.terminator) |t| {
                switch (t) {
                    .ret => {},
                    .unreachable_ => {},
                    .br => |dst| {
                        if (!block_set.contains(dst)) return error.InvalidIR;
                    },
                    .cond_br => |cb| {
                        if (!block_set.contains(cb.then_block)) return error.InvalidIR;
                        if (!block_set.contains(cb.else_block)) return error.InvalidIR;
                    },
                    .switch_ => |sw| {
                        if (!block_set.contains(sw.default)) return error.InvalidIR;
                        for (sw.cases) |c| {
                            if (!block_set.contains(c.block)) return error.InvalidIR;
                        }
                    },
                    else => {},
                }
            }
        }
    }

    // ========================================================================
    // Loop Invariant Code Motion (LICM)
    // ========================================================================

    /// Run LICM on the entire module
    fn runLICM(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.runLICMInFunction(func)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Run LICM on a single function
    pub fn runLICMInFunction(self: *Self, func: *Function) !bool {
        // 0. Rebuild CFG
        try Analysis.rebuildCFG(func);

        // 1. Compute Dominators
        var dt = try Analysis.computeDominators(self.allocator, func);
        defer dt.deinit();

        // 2. Compute Loops
        var loop_info = try Analysis.computeLoops(self.allocator, func, &dt);
        defer loop_info.deinit();

        if (loop_info.loops.items.len == 0) return false;

        var changed = false;

        // 3. Optimize Loops
        // We iterate top-level loops. optimizeLoop will handle sub-loops recursively if needed,
        // or we can just iterate all loops if we flatten them. 
        // Analysis returns hierarchy. Let's process bottom-up (inner loops first) usually better,
        // but for basic LICM, processing any order is fine as long as we hoist to immediate pre-header.
        
        for (loop_info.loops.items) |loop| {
            if (try self.optimizeLoop(func, loop, &dt)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Optimize a single loop (and its sub-loops)
    fn optimizeLoop(self: *Self, func: *Function, loop: *Analysis.Loop, dt: *const Analysis.DominatorTree) !bool {
        var changed = false;

        // Process sub-loops first (bottom-up)
        for (loop.sub_loops.items) |sub_loop| {
            if (try self.optimizeLoop(func, sub_loop, dt)) {
                changed = true;
            }
        }

        // Loop Unrolling
        // We only unroll innermost loops (no sub-loops) for now to keep it simple.
        if (self.config.loop_unroll and loop.sub_loops.items.len == 0) {
            if (try self.unrollLoop(func, loop, dt)) {
                self.stats.loops_unrolled += 1;
                changed = true;
                // If unrolled, the loop structure changes significantly.
                // We might need to stop further optimizations on this loop struct.
                return true;
            }
        }

        // Find loop invariants
        // An instruction is invariant if:
        // 1. It is side-effect free
        // 2. All operands are loop-invariant (constants or defined outside the loop)
        
        var invariant_instrs = std.ArrayListUnmanaged(*Instruction){};
        defer invariant_instrs.deinit(self.allocator);

        // Iterate over all blocks in the loop
        for (loop.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (self.isLoopInvariant(inst, loop)) {
                    try invariant_instrs.append(self.allocator, inst);
                }
            }
        }

        if (invariant_instrs.items.len == 0) return changed;

        // Move invariants to pre-header
        if (invariant_instrs.items.len > 0) {
            const pre_header = try self.getOrCreatePreHeader(func, loop, dt);
            
            for (invariant_instrs.items) |inst| {
                // Remove from original block
                // We need to find which block it belongs to.
                // Since we don't store parent pointer in Instruction, we search.
                // Optimization: isLoopInvariant could return the block too.
                // Or we just search again.
                
                var removed = false;
                for (loop.blocks.items) |block| {
                    if (self.removeInstructionFromBlock(block, inst)) {
                        removed = true;
                        break;
                    }
                }

                if (removed) {
                    // Insert into pre-header (before terminator)
                    // If pre-header is empty (except terminator), just append.
                    // Pre-header should be a new block or a unique predecessor.
                    
                    // We need to insert at the end of instructions list, but before terminator?
                    // BasicBlock.instructions does not include terminator.
                    try pre_header.instructions.append(self.allocator, inst);
                    changed = true;
                }
            }
        }

        return changed;
    }

    /// Check if instruction is loop invariant
    fn isLoopInvariant(self: *Self, inst: *Instruction, loop: *Analysis.Loop) bool {
        // 1. Must be side-effect free
        if (self.hasSideEffects(inst)) return false;

        // 2. Operands must be invariant
        return self.areOperandsInvariant(inst, loop);
    }

    /// Check if all operands of an instruction are invariant
    fn areOperandsInvariant(self: *Self, inst: *Instruction, loop: *Analysis.Loop) bool {
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod, .pow => |op| return self.isInvariant(op.lhs, loop) and self.isInvariant(op.rhs, loop),
            .bit_and, .bit_or, .bit_xor, .shl, .shr => |op| return self.isInvariant(op.lhs, loop) and self.isInvariant(op.rhs, loop),
            .eq, .ne, .lt, .le, .gt, .ge, .identical, .not_identical, .spaceship => |op| return self.isInvariant(op.lhs, loop) and self.isInvariant(op.rhs, loop),
            .and_, .or_, .concat => |op| return self.isInvariant(op.lhs, loop) and self.isInvariant(op.rhs, loop),
            .neg, .bit_not, .not, .strlen, .array_count, .clone, .retain, .release, .debug_print, .get_type => |op| return self.isInvariant(op.operand, loop),
            .load => |op| {
                // Load is invariant if pointer is invariant AND memory is not modified in loop.
                // For now, assume any store invalidates loads (conservative).
                // Or better: check if there are any stores in the loop.
                if (!self.isInvariant(op.ptr, loop)) return false;
                if (self.hasStoreInLoop(loop)) return false; 
                return true;
            },
            .cast => |op| return self.isInvariant(op.value, loop),
            .type_check => |op| return self.isInvariant(op.value, loop),
            .box => |op| return self.isInvariant(op.value, loop),
            .unbox => |op| return self.isInvariant(op.value, loop),
            // Constants are always invariant
            .const_int, .const_float, .const_bool, .const_string, .const_null, .const_missing, .arg_count, .has_arg => return true,
            // Allocas are invariant (address is constant)
            .alloca => return true, 
            else => return false, // Conservative
        }
    }

    /// Check if a register is defined outside the loop (or is constant)
    fn isInvariant(self: *Self, reg: Register, loop: *Analysis.Loop) bool {
        _ = self;
        // Find definition of register
        // Since we don't have use-def chains, we have to search blocks.
        // Optimization: If register ID is very small (params), it's invariant.
        
        // Scan loop blocks to see if they define this register
        for (loop.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |res| {
                    if (res.id == reg.id) return false; // Defined inside loop
                }
            }
            // Check Phis? (Phis in header are defined "inside" loop logic usually)
            // But Phis at header might take values from outside.
            // However, a Phi in a loop header depends on back-edge, so it varies.
            // So Phi result is NOT invariant.
        }
        
        return true; // Defined outside
    }

    /// Check if loop contains any store instructions
    fn hasStoreInLoop(self: *Self, loop: *Analysis.Loop) bool {
        _ = self;
        for (loop.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .store) return true;
                // Calls also modify memory
                if (inst.op == .call or inst.op == .call_indirect) return true;
            }
        }
        return false;
    }

    /// Remove instruction from block
    fn removeInstructionFromBlock(self: *Self, block: *BasicBlock, inst: *Instruction) bool {
        _ = self;
        for (block.instructions.items, 0..) |it, i| {
            if (it == inst) {
                _ = block.instructions.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Get or create a pre-header for the loop
    fn getOrCreatePreHeader(self: *Self, func: *Function, loop: *Analysis.Loop, dt: *const Analysis.DominatorTree) !*BasicBlock {
        _ = dt;
        const header = loop.header;
        
        // Check if there is already a unique predecessor that dominates header and is not in loop
        // And is not a back-edge source (which is in loop).
        // Ideally, a pre-header is a block that has only 'header' as successor, 
        // and 'header' has only 'pre-header' as non-loop predecessor.
        
        // Count non-loop predecessors
        var non_loop_preds = std.ArrayListUnmanaged(*BasicBlock){};
        defer non_loop_preds.deinit(self.allocator);
        
        for (header.predecessors.items) |pred| {
            if (!loop.contains(pred)) {
                try non_loop_preds.append(self.allocator, pred);
            }
        }
        
        if (non_loop_preds.items.len == 1) {
            const pred = non_loop_preds.items[0];
            // Check if this pred flows ONLY to header
            if (pred.successors.items.len == 1 and pred.successors.items[0] == header) {
                return pred; // Found valid pre-header
            }
        }
        
        // Create new pre-header
        const pre_header = try func.createBlock("preheader");
        
        // Redirect non-loop predecessors to pre-header
        for (non_loop_preds.items) |pred| {
            try self.redirectEdge(pred, header, pre_header);
        }
        
        // Connect pre-header to header
        pre_header.terminator = .{ .br = header };
        try Analysis.rebuildCFG(func); // Update edges
        
        return pre_header;
    }

    /// Redirect an edge from->old_to to from->new_to
    fn redirectEdge(self: *Self, from: *BasicBlock, old_to: *BasicBlock, new_to: *BasicBlock) !void {
        if (from.terminator) |*term| {
            switch (term.*) {
                .br => |target| {
                    if (target == old_to) term.br = new_to;
                },
                .cond_br => |*cb| {
                    if (cb.then_block == old_to) cb.then_block = new_to;
                    if (cb.else_block == old_to) cb.else_block = new_to;
                },
                .switch_ => |*sw| {
                    var modified = false;
                    for (sw.cases) |case| {
                        if (case.block == old_to) {
                            modified = true;
                            break;
                        }
                    }
                    
                    if (modified) {
                        const new_cases = try self.allocator.alloc(Terminator.SwitchCase, sw.cases.len);
                        for (sw.cases, 0..) |case, i| {
                            new_cases[i] = case;
                            if (case.block == old_to) {
                                new_cases[i].block = new_to;
                            }
                        }
                        // We should free old cases if we owned them, but they are const.
                        // Ideally we track ownership.
                        sw.cases = new_cases;
                    }

                    if (sw.default == old_to) sw.default = new_to;
                },
                else => {},
            }
        }
    }

    // ========================================================================
    // Loop Unrolling
    // ========================================================================

    /// Run Loop Unrolling on the entire module
    fn runLoopUnroll(self: *Self, module: *Module) !bool {
        var changed = false;
        for (module.functions.items) |func| {
            if (try self.runLoopUnrollInFunction(func)) {
                changed = true;
            }
        }
        return changed;
    }

    /// Run Loop Unrolling on a function
    fn runLoopUnrollInFunction(self: *Self, func: *Function) !bool {
        var changed = false;
        
        // We need dominator tree for loop detection
        // Note: Rebuild CFG first to be safe
        try Analysis.rebuildCFG(func);
        var dt = try Analysis.computeDominators(self.allocator, func);
        defer dt.deinit();
        
        var loop_info = try Analysis.computeLoops(self.allocator, func, &dt);
        defer loop_info.deinit();
        
        // Iterate loops
        // Since unrolling modifies CFG, we should be careful.
        // Safe approach: unroll one loop per pass, or handle carefully.
        // For now, let's just try to unroll loops, and if we unroll one, we stop for this pass.
        for (loop_info.loops.items) |loop| {
             if (try self.unrollLoop(func, loop, &dt)) {
                 changed = true;
                 // Rebuild CFG to ensure successors/predecessors are correct for next passes
                 try Analysis.rebuildCFG(func);
                 break; // CFG changed, stop processing loops
             }
        }
        
        return changed;
    }

    /// Try to unroll a loop
    fn unrollLoop(self: *Self, func: *Function, loop: *Analysis.Loop, dt: *const Analysis.DominatorTree) !bool {
        _ = dt;
        
        // 1. Analyze loop to check if it's a candidate
        // We verify it has a single latch that conditionally branches to header (do-while style)
        // OR we can handle standard while loops if we are careful.
        // For now, let's stick to the structure:
        // Latch -> Header (Back Edge)
        
        var latch: ?*BasicBlock = null;
        for (loop.blocks.items) |block| {
            for (block.successors.items) |succ| {
                if (succ == loop.header) {
                    if (latch != null) {
                        // std.debug.print("Multiple latches found\n", .{});
                        return false; 
                    }
                    latch = block;
                }
            }
        }
        
        if (latch == null) {
            // std.debug.print("No latch found. Loop blocks: {d}\n", .{loop.blocks.items.len});
            return false;
        }
        const latch_block = latch.?;
        // std.debug.print("Found latch: {s}\n", .{latch_block.label});
        
        // Check loop size
        var instruction_count: usize = 0;
        for (loop.blocks.items) |block| {
            instruction_count += block.instructions.items.len;
        }
        if (instruction_count > 50) {
            // std.debug.print("Loop too large: {d}\n", .{instruction_count});
            return false;
        }
        
        const factor = self.config.unroll_factor;
        if (factor <= 1) {
            // std.debug.print("Unroll factor too small: {d}\n", .{factor});
            return false;
        }
        
        // Map to track register renames across iterations (Original -> Latest)
        var reg_map = std.AutoHashMap(u32, u32).init(self.allocator);
        defer reg_map.deinit();

        // Identify Header PHIs and their back-edge inputs
        // Map: Header_PHI_Reg_ID -> Back_Edge_Input_Reg_ID
        var phi_back_edge_map = std.AutoHashMap(u32, u32).init(self.allocator);
        defer phi_back_edge_map.deinit();

        for (loop.header.instructions.items) |inst| {
            if (inst.op == .phi) {
                for (inst.op.phi.incoming) |inc| {
                    if (inc.block == latch_block) {
                        try phi_back_edge_map.put(inst.result.?.id, inc.value.id);
                        // std.debug.print("PHI Map: reg_{d} <- reg_{d}\n", .{inst.result.?.id, inc.value.id});
                        break;
                    } else {
                        // std.debug.print("PHI mismatch: inc.block {s} != latch {s}\n", .{inc.block.label, latch_block.label});
                    }
                }
            }
        }
        
        // We will chain: Latch(Original) -> Clone1 -> Clone2 -> ... -> Clone(K-1) -> Header(Original)
        // The Latch(Original) currently points to Header. We will redirect it to Clone1.
        
        var current_predecessor = latch_block;
        var expected_target = loop.header;
        var first_unrolled_header: ?*BasicBlock = null;
        
        // We need to order blocks for cloning.
        // Simple heuristic: Header first, then others. 
        // If we just iterate loop.blocks, we might visit in wrong order, but since we are mapping
        // based on "latest", and definitions usually dominate uses, 
        // and we handle PHIs specially, topological sort of body is best.
        // Since we assume simple loops, let's just use the order in loop.blocks but ensure Header is processed.
        
        // Perform unrolling
        for (1..factor) |k| {
            // 1. Resolve Header PHIs for this iteration
            // The "PHI" value in this iteration is the value flowing from the previous iteration's latch.
            var phi_it = phi_back_edge_map.iterator();
            while (phi_it.next()) |entry| {
                const phi_id = entry.key_ptr.*;
                const input_id = entry.value_ptr.*;
                
                // Get the remapped input from previous iteration (or original if first iter)
                const resolved_input = reg_map.get(input_id) orelse input_id;
                
                // Map the PHI result in this iteration to that input
                try reg_map.put(phi_id, resolved_input);
            }
            
            // 2. Clone blocks
            var first_cloned_block: ?*BasicBlock = null;
            var last_cloned_block: ?*BasicBlock = null;
            
            // We need to map OriginalBlock -> NewBlock for this iteration to fix internal edges
            var block_map = std.AutoHashMap(*BasicBlock, *BasicBlock).init(self.allocator);
            defer block_map.deinit();
            
            // First pass: Create blocks
            for (loop.blocks.items) |block| {
                const suffix = try std.fmt.allocPrint(self.allocator, "_unroll_{d}_{s}", .{k, block.label});
                defer self.allocator.free(suffix);
                const new_block = try func.createBlock(suffix);
                try block_map.put(block, new_block);
                
                if (block == loop.header) first_cloned_block = new_block;
                if (block == latch_block) last_cloned_block = new_block;
            }
            
            // Second pass: Clone instructions and fix edges
            for (loop.blocks.items) |block| {
                const new_block = block_map.get(block).?;
                
                // Clone instructions
                for (block.instructions.items) |inst| {
                    // Skip PHIs in Header (we mapped them already)
                    if (block == loop.header and inst.op == .phi) continue;
                    
                    if (try self.cloneAndRemapInstruction(inst, &reg_map, &func.next_register_id)) |new_inst| {
                        try new_block.appendInstruction(new_inst);
                    }
                }
                
                // Clone terminator
                if (block.terminator) |term| {
                    var new_term = term;
                    self.remapRegistersInTerminator(&new_term, &reg_map);
                    
                    // Remap branch targets
                    switch (new_term) {
                        .br => |*target| {
                            if (block_map.get(target.*)) |new_target| {
                                target.* = new_target;
                            }
                        },
                        .cond_br => |*cb| {
                            if (block_map.get(cb.then_block)) |new_target| cb.then_block = new_target;
                            if (block_map.get(cb.else_block)) |new_target| cb.else_block = new_target;
                        },
                        // Handle switch if needed
                        else => {},
                    }
                    new_block.terminator = new_term;
                }
            }
            
            // Link previous latch to this iteration's header
            if (k == 1) {
                first_unrolled_header = first_cloned_block;
            } else {
                // Link Clone (k-1) Latch -> Clone k Header
                var linked = false;
                if (current_predecessor.terminator) |*term| {
                    switch (term.*) {
                        .br => |*target| {
                            if (target.* == expected_target) {
                                target.* = first_cloned_block.?;
                                linked = true;
                            }
                        },
                        .cond_br => |*cb| {
                            if (cb.then_block == expected_target) {
                                cb.then_block = first_cloned_block.?;
                                linked = true;
                            }
                            if (cb.else_block == expected_target) {
                                cb.else_block = first_cloned_block.?;
                                linked = true;
                            }
                        },
                        else => {},
                    }
                }
                if (!linked) {
                     // var actual_target_label: []const u8 = "unknown";
                     // if (current_predecessor.terminator) |*term| {
                     //     switch (term.*) {
                     //         .br => |*target| actual_target_label = target.*.label,
                     //         .cond_br => |*cb| actual_target_label = cb.then_block.label,
                     //         else => {},
                     //     }
                     // }
                     // std.debug.print("Failed to link latch {s} to clone header {s} (expected {s}, actual {s})\n", .{current_predecessor.label, first_cloned_block.?.label, expected_target.label, actual_target_label});
                } else {
                    // std.debug.print("Linked latch {s} to clone header {s}\n", .{current_predecessor.label, first_cloned_block.?.label});
                }
            }
            
            // Update expected target for next iteration
            // The cloned latch will point to the cloned header (because of cloneAndRemap)
            expected_target = first_cloned_block.?;
            
            current_predecessor = last_cloned_block.?;
        }
        
        // 3. Final Linking
        
        // Link Original Latch -> Clone 1 Header
        if (latch_block.terminator) |*term| {
             switch (term.*) {
                 .br => |*target| {
                     if (target.* == loop.header) target.* = first_unrolled_header.?;
                 },
                 .cond_br => |*cb| {
                     if (cb.then_block == loop.header) cb.then_block = first_unrolled_header.?;
                     if (cb.else_block == loop.header) cb.else_block = first_unrolled_header.?;
                 },
                 else => {},
             }
        }
        
        // Link Last Clone Latch -> Original Header
        if (current_predecessor.terminator) |*term| {
             switch (term.*) {
                 .br => |*target| {
                     if (target.* == expected_target) target.* = loop.header;
                 },
                 .cond_br => |*cb| {
                     if (cb.then_block == expected_target) cb.then_block = loop.header;
                     if (cb.else_block == expected_target) cb.else_block = loop.header;
                 },
                 else => {},
             }
        }
        
        // 4. Update Original Header PHIs to take input from `current_predecessor` instead of `latch_block`.
        for (loop.header.instructions.items) |inst| {
            if (inst.op == .phi) {
                // The phi incoming values from latch need to be updated.
                // The incoming VALUE should be what `current_predecessor` produces.
                // This is `reg_map.get(original_incoming_id)`.
                
                // We need to modify the `PhiIncoming` struct.
                // `inst.op.phi.incoming` is a slice. We can modify in place.
                const inc_ptr = @constCast(inst.op.phi.incoming.ptr);
                for (0..inst.op.phi.incoming.len) |i| {
                    if (inc_ptr[i].block == latch_block) {
                        // Update block
                        inc_ptr[i].block = current_predecessor;
                        // Update value
                        const old_val_id = inc_ptr[i].value.id;
                        if (reg_map.get(old_val_id)) |new_id| {
                            inc_ptr[i].value.id = new_id;
                        }
                    }
                }
            }
        }
        
        // Rebuild CFG info (preds/succs) since we messed with pointers
        // Ideally we should update incrementally, but full rebuild is safer.
        // Analysis.rebuildCFG(func); // Call this after optimization pass
        
        self.stats.loops_unrolled += 1;
        return true;
    }

    /// Remap registers in a terminator
    fn remapRegistersInTerminator(self: *Self, term: *Terminator, reg_map: *std.AutoHashMap(u32, u32)) void {
        _ = self;
        switch (term.*) {
            .ret => |*val| {
                if (val.*) |*v| {
                    if (reg_map.get(v.id)) |new_id| v.id = new_id;
                }
            },
            .cond_br => |*cb| {
                if (reg_map.get(cb.cond.id)) |new_id| cb.cond.id = new_id;
            },
            .switch_ => |*sw| {
                if (reg_map.get(sw.value.id)) |new_id| sw.value.id = new_id;
            },
            .throw => |*val| {
                if (reg_map.get(val.id)) |new_id| val.id = new_id;
            },
            else => {},
        }
    }

    // ========================================================================
    // Mem2Reg (Promote Memory to Register)
    // ========================================================================

    /// Run Mem2Reg on the entire module
    fn runMem2Reg(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.promoteMemoryToRegisters(func)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Promote memory to registers in a single function
    fn promoteMemoryToRegisters(self: *Self, func: *Function) !bool {
        // 0. Rebuild CFG (ensure predecessors/successors are up to date)
        try Analysis.rebuildCFG(func);

        // 1. Compute Dominators
        var dt = try Analysis.computeDominators(self.allocator, func);
        defer dt.deinit();

        // 2. Find promotable allocas
        var promotable_allocas = std.ArrayListUnmanaged(*Instruction){};
        defer promotable_allocas.deinit(self.allocator);

        // Map alloca -> list of definition blocks
        var def_blocks = std.AutoHashMap(*Instruction, std.ArrayListUnmanaged(*BasicBlock)).init(self.allocator);
        defer {
            var it = def_blocks.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            def_blocks.deinit();
        }

        // Map Register ID -> Alloca Instruction (for fast lookup)
        var reg_to_alloca = std.AutoHashMap(u32, *Instruction).init(self.allocator);
        defer reg_to_alloca.deinit();

        // Scan entry block for allocas
        if (func.getEntryBlock()) |entry| {
            for (entry.instructions.items) |inst| {
                if (inst.op == .alloca) {
                    if (self.isPromotable(inst, func)) {
                        try promotable_allocas.append(self.allocator, inst);
                        try def_blocks.put(inst, .{});
                        if (inst.result) |res| {
                            try reg_to_alloca.put(res.id, inst);
                        }
                    } else {
                        // Alloca rejected
                    }
                }
            }
        }

        if (promotable_allocas.items.len == 0) return false;

        // 3. Collect Defs
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                switch (inst.op) {
                    .store => |op| {
                        if (reg_to_alloca.get(op.ptr.id)) |alloca| {
                            var list = def_blocks.getPtr(alloca).?;
                            // Add block if not already there
                            var found = false;
                            for (list.items) |b| {
                                if (b == block) { found = true; break; }
                            }
                            if (!found) try list.append(self.allocator, block);
                        }
                    },
                    else => {},
                }
            }
        }

        // 4. Insert Phi Nodes
        // Map: Block -> Map: Alloca -> PhiInstruction
        // We need this to quickly find the phi node for a variable in a block during renaming
        var new_phis = std.AutoHashMap(*BasicBlock, std.AutoHashMap(*Instruction, *Instruction)).init(self.allocator);
        defer {
            var it = new_phis.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            new_phis.deinit();
        }

        for (promotable_allocas.items) |alloca| {
            const defs = def_blocks.get(alloca).?;
            // Compute IDF
            var idf = try self.computeIDF(defs.items, &dt);
            defer idf.deinit(self.allocator);

            for (idf.items) |block| {
                // Insert Phi node
                const phi_reg = func.newRegister(alloca.op.alloca.type_);
                const phi_inst = try self.allocator.create(Instruction);
                phi_inst.* = .{
                    .result = phi_reg,
                    .op = .{ .phi = .{ .incoming = &.{} } }, // Empty initially
                    .location = alloca.location,
                };
                
                // Prepend to block instructions (Phis must be first)
                try block.instructions.insert(self.allocator, 0, phi_inst);

                // Record phi
                var phis_in_block = new_phis.getPtr(block);
                if (phis_in_block == null) {
                    try new_phis.put(block, std.AutoHashMap(*Instruction, *Instruction).init(self.allocator));
                    phis_in_block = new_phis.getPtr(block);
                }
                try phis_in_block.?.put(alloca, phi_inst);
            }
        }

        // 5. Rename Variables
        // Stack of current values for each alloca
        var current_values = std.AutoHashMap(*Instruction, std.ArrayListUnmanaged(Register)).init(self.allocator);
        defer {
            var it = current_values.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            current_values.deinit();
        }

        // Initialize stacks with undefined/null or initial value?
        // Allocas are uninitialized. We can use a special "undef" value or just rely on correctness.
        // For strictness, we can create an undef register.
        // But typically we don't need to push anything initially if the code is correct (defs dominate uses).
        // However, if there are uses before defs (uninitialized read), we might crash.
        // We'll assume valid code or handle it.

        if (func.getEntryBlock()) |entry| {
             try self.renameVariables(entry, &dt, &current_values, &new_phis, &reg_to_alloca);
        }

        // 6. Cleanup (Remove allocas)
        // Stores and loads were marked as NOPs in renameVariables.
        // We just need to remove the allocas themselves.
        for (promotable_allocas.items) |alloca| {
             alloca.op = .nop;
             self.stats.allocas_promoted += 1;
        }

        return true;
    }

    /// Compute Iterated Dominance Frontier
    fn computeIDF(self: *Self, defs: []const *BasicBlock, dt: *const Analysis.DominatorTree) !std.ArrayListUnmanaged(*BasicBlock) {
        var idf = std.ArrayListUnmanaged(*BasicBlock){};
        
        // Priority Queue using level (higher level = deeper)
        // We actually need to process by level for efficiency, but simple worklist is fine.
        var worklist = std.ArrayListUnmanaged(*BasicBlock){};
        defer worklist.deinit(self.allocator);
        
        var visited = std.AutoHashMap(*BasicBlock, void).init(self.allocator);
        defer visited.deinit();

        for (defs) |def| {
            try worklist.append(self.allocator, def);
            try visited.put(def, {});
        }

        var i: usize = 0;
        while (i < worklist.items.len) {
            const block = worklist.items[i];
            i += 1;

            const frontier = dt.frontiers[block.index];
            for (frontier.items) |f_block| {
                if (!visited.contains(f_block)) {
                    try visited.put(f_block, {});
                    try worklist.append(self.allocator, f_block);
                    try idf.append(self.allocator, f_block);
                }
            }
        }

        return idf;
    }

    /// Check if alloca is promotable
    fn isPromotable(self: *Self, alloca: *Instruction, func: *Function) bool {
        // Result must be used
        const result_reg = alloca.result orelse return false;
        const result_id = result_reg.id;

        // Check all uses
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                switch (inst.op) {
                    .load => |op| {
                        if (op.ptr.id == result_id) {
                            // Valid use
                            if (!op.type_.eql(alloca.op.alloca.type_)) return false; // Type mismatch
                        }
                    },
                    .store => |op| {
                        if (op.ptr.id == result_id) {
                            // Valid use
                            if (op.value.id == result_id) return false; // Storing pointer to itself?
                        } else if (op.value.id == result_id) {
                            // Escaping pointer!
                            return false;
                        }
                    },
                    else => {
                        // Check if register is used in other operands
                        // We need to check all operands.
                        // Ideally we have use-def chains.
                        // Here we just scan.
                        if (self.usesRegister(inst, result_id)) return false;
                    },
                }
            }
        }
        return true;
    }

    /// Check if instruction uses a register
    fn usesRegister(self: *Self, inst: *Instruction, reg_id: u32) bool {
        _ = self;
        switch (inst.op) {
            .load => |op| return op.ptr.id == reg_id,
            .store => |op| return op.ptr.id == reg_id or op.value.id == reg_id,
            .add, .sub, .mul, .div, .mod, .pow => |op| return op.lhs.id == reg_id or op.rhs.id == reg_id,
            .bit_and, .bit_or, .bit_xor, .shl, .shr => |op| return op.lhs.id == reg_id or op.rhs.id == reg_id,
            .eq, .ne, .lt, .le, .gt, .ge, .identical, .not_identical, .spaceship => |op| return op.lhs.id == reg_id or op.rhs.id == reg_id,
            .and_, .or_, .concat => |op| return op.lhs.id == reg_id or op.rhs.id == reg_id,
            .neg, .bit_not, .not, .strlen, .array_count, .clone, .retain, .release, .debug_print, .get_type => |op| return op.operand.id == reg_id,
            .call => |op| {
                for (op.args) |arg| if (arg.id == reg_id) return true;
                return false;
            },
            // ... (check other ops)
            // For brevity, assuming other ops are checked similar to above or via generic scan
            else => return false, // Simplified for now
        }
    }

    /// Rename variables in the dominator tree
    fn renameVariables(
        self: *Self,
        block: *BasicBlock,
        dt: *const Analysis.DominatorTree,
        current_values: *std.AutoHashMap(*Instruction, std.ArrayListUnmanaged(Register)),
        new_phis: *std.AutoHashMap(*BasicBlock, std.AutoHashMap(*Instruction, *Instruction)),
        reg_to_alloca: *std.AutoHashMap(u32, *Instruction),
    ) !void {
        // Record stack heights to pop later
        var stack_heights = std.AutoHashMap(*Instruction, usize).init(self.allocator);
        defer stack_heights.deinit();

        // 1. Process Phis
        if (new_phis.getPtr(block)) |phis| {
            var it = phis.iterator();
            while (it.next()) |entry| {
                const alloca = entry.key_ptr.*;
                const phi_inst = entry.value_ptr.*;
                
                // Push phi result to stack
                var stack = current_values.getPtr(alloca);
                if (stack == null) {
                     try current_values.put(alloca, .{});
                     stack = current_values.getPtr(alloca);
                }
                
                // Save current height
                try stack_heights.put(alloca, stack.?.items.len);
                
                if (phi_inst.result) |res| {
                    try stack.?.append(self.allocator, res);
                }
            }
        }

        // 2. Process Instructions
        for (block.instructions.items) |inst| {
            switch (inst.op) {
                .load => |op| {
                    if (reg_to_alloca.get(op.ptr.id)) |alloca| {
                        // Replace result with current value
                        if (current_values.getPtr(alloca)) |stack| {
                            if (stack.items.len > 0) {
                                const val = stack.items[stack.items.len - 1];
                                // We can't easily replace all uses of inst.result without use-def chains.
                                // But since we are iterating, we can't update future instructions yet.
                                // Wait, in SSA construction, we usually update uses.
                                // But here we don't have use lists.
                                // So we cheat: We make this load a "copy" or "move" (identity cast) 
                                // or simply replace the instruction in place with a specialized "alias" op?
                                // No, standard way is to map the old register ID to the new register ID (val.id).
                                // BUT, we don't have a global map for that here.
                                //
                                // Alternative: Modify the instruction to be a `cast` or similar from val to result.
                                // Then Copy Propagation will clean it up.
                                //
                                // Better: Update `inst.result`'s ID to match `val.id`? No, registers must be unique-ish.
                                //
                                // Correct way: We need a map of "Renames": OldReg -> NewReg.
                                // And when we see a use of OldReg, we use NewReg.
                                // But `renameVariables` visits definitions.
                                //
                                // Ah, the standard algorithm assumes we can update uses.
                                // Since we don't have use-lists, we must carry a map "OldReg -> NewReg" and apply it to operands.
                                // But we are only visiting blocks once.
                                //
                                // Wait, the stack `current_values` GIVES us the new register for an alloca.
                                // When we see a load `r1 = load alloca`, we want `r1` to be an alias for `stack.top()`.
                                // We can change the load to `r1 = bitcast stack.top()`.
                                // Or better: `r1` IS the register we want to replace.
                                // But `r1` is defined here.
                                //
                                // We can change `inst.op` to `.bit_or { .lhs = val, .rhs = val }` (nop move) 
                                // or `.cast` or `.select`.
                                //
                                // Let's use a new op `copy` or just `add val, 0` or similar.
                                // Or reuse `cast` with same type.
                                inst.op = .{ .cast = .{ .value = val, .from_type = val.type_, .to_type = op.type_ } };
                                // And later Copy Propagation / DCE removes it.
                                // This avoids needing to update all users of `inst.result` immediately.
                            }
                        }
                    }
                },
                .store => |op| {
                    if (reg_to_alloca.get(op.ptr.id)) |alloca| {
                        // Push value to stack
                        var stack = current_values.getPtr(alloca);
                        if (stack == null) {
                             try current_values.put(alloca, .{});
                             stack = current_values.getPtr(alloca);
                        }
                        
                        // Save current height (if not already saved for this block? No, stores push new values)
                        // Actually we need to pop *all* pushes from this block.
                        // So we should track pushes.
                        // `stack_heights` tracks the height *before* entry to this block.
                        // No, `stack_heights` stores the height *before* the push we just did?
                        // We need to restore the stack to the state it was at the start of the block.
                        // So we only record height ONCE per alloca per block.
                        if (!stack_heights.contains(alloca)) {
                            try stack_heights.put(alloca, stack.?.items.len);
                        }
                        
                        try stack.?.append(self.allocator, op.value);
                        
                        // Remove store
                        inst.op = .nop;
                    }
                },
                else => {},
            }
        }

        // 3. Update Successors' Phis
        for (block.successors.items) |succ| {
             if (new_phis.getPtr(succ)) |succ_phis| {
                 var it = succ_phis.iterator();
                 while (it.next()) |entry| {
                     const alloca = entry.key_ptr.*;
                     const phi_inst = entry.value_ptr.*;
                     
                     if (current_values.getPtr(alloca)) |stack| {
                         if (stack.items.len > 0) {
                             const val = stack.items[stack.items.len - 1];
                             
                             // Add incoming value to phi
                             // We need to reallocate the incoming slice
                             const old_incoming = phi_inst.op.phi.incoming;
                             const new_incoming = try self.allocator.alloc(IR.Instruction.PhiIncoming, old_incoming.len + 1);
                             @memcpy(new_incoming[0..old_incoming.len], old_incoming);
                             new_incoming[old_incoming.len] = .{ .value = val, .block = block };
                             
                             // Free old slice if it wasn't empty/static?
                             // Currently slices are owned by instruction if created.
                             if (old_incoming.len > 0) self.allocator.free(old_incoming);
                             
                             phi_inst.op.phi.incoming = new_incoming;
                         }
                     }
                 }
             }
        }

        // 4. Recurse
        if (dt.children[block.index].items.len > 0) {
            for (dt.children[block.index].items) |child| {
                try self.renameVariables(child, dt, current_values, new_phis, reg_to_alloca);
            }
        }

        // 5. Pop Stacks
        var it = stack_heights.iterator();
        while (it.next()) |entry| {
            const alloca = entry.key_ptr.*;
            const height = entry.value_ptr.*;
            
            if (current_values.getPtr(alloca)) |stack| {
                stack.shrinkRetainingCapacity(height);
            }
        }
    }

    // ========================================================================
    // Dead Code Elimination
    // ========================================================================

    /// Run dead code elimination on the entire module
    fn runDeadCodeElimination(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.eliminateDeadCodeInFunction(func)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Eliminate dead code in a single function
    fn eliminateDeadCodeInFunction(self: *Self, func: *Function) !bool {
        var changed = false;

        // Phase 1: Mark all used registers
        self.used_registers.clearRetainingCapacity();
        try self.markUsedRegisters(func);

        // Phase 2: Remove instructions with unused results
        for (func.blocks.items) |block| {
            var i: usize = 0;
            while (i < block.instructions.items.len) {
                const inst = block.instructions.items[i];

                // Check if instruction result is used
                if (inst.result) |result| {
                    if (!self.used_registers.contains(result.id)) {
                        // Check if instruction has side effects
                        if (!self.hasSideEffects(inst)) {
                            // Remove dead instruction
                            _ = block.instructions.orderedRemove(i);
                            inst.deinit(self.allocator);
                            self.allocator.destroy(inst);
                            self.stats.dead_instructions_removed += 1;
                            changed = true;
                            continue;
                        }
                    }
                }
                i += 1;
            }
        }

        // Phase 3: Remove unreachable blocks
        if (try self.removeUnreachableBlocks(func)) {
            changed = true;
        }

        return changed;
    }

    /// Mark all registers that are used
    fn markUsedRegisters(self: *Self, func: *const Function) !void {
        for (func.blocks.items) |block| {
            // Mark registers used in instructions
            for (block.instructions.items) |inst| {
                try self.markRegistersInInstruction(inst);
            }

            // Mark registers used in terminator
            if (block.terminator) |term| {
                try self.markRegistersInTerminator(term);
            }
        }
    }

    /// Mark registers used in an instruction
    fn markRegistersInInstruction(self: *Self, inst: *const Instruction) !void {
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod, .pow => |op| {
                try self.used_registers.put(op.lhs.id, {});
                try self.used_registers.put(op.rhs.id, {});
            },
            .bit_and, .bit_or, .bit_xor, .shl, .shr => |op| {
                try self.used_registers.put(op.lhs.id, {});
                try self.used_registers.put(op.rhs.id, {});
            },
            .eq, .ne, .lt, .le, .gt, .ge, .identical, .not_identical, .spaceship => |op| {
                try self.used_registers.put(op.lhs.id, {});
                try self.used_registers.put(op.rhs.id, {});
            },
            .and_, .or_, .concat => |op| {
                try self.used_registers.put(op.lhs.id, {});
                try self.used_registers.put(op.rhs.id, {});
            },
            .neg, .bit_not, .not, .strlen, .array_count, .clone => |op| {
                try self.used_registers.put(op.operand.id, {});
            },
            .retain, .release, .debug_print, .get_type => |op| {
                try self.used_registers.put(op.operand.id, {});
            },
            .load => |op| {
                try self.used_registers.put(op.ptr.id, {});
            },
            .store => |op| {
                try self.used_registers.put(op.ptr.id, {});
                try self.used_registers.put(op.value.id, {});
            },
            .call => |op| {
                for (op.args) |arg| {
                    try self.used_registers.put(arg.id, {});
                }
            },
            .call_indirect => |op| {
                try self.used_registers.put(op.func_ptr.id, {});
                for (op.args) |arg| {
                    try self.used_registers.put(arg.id, {});
                }
            },
            .cast => |op| {
                try self.used_registers.put(op.value.id, {});
            },
            .type_check => |op| {
                try self.used_registers.put(op.value.id, {});
            },
            .array_get => |op| {
                try self.used_registers.put(op.array.id, {});
                try self.used_registers.put(op.key.id, {});
            },
            .array_set => |op| {
                try self.used_registers.put(op.array.id, {});
                try self.used_registers.put(op.key.id, {});
                try self.used_registers.put(op.value.id, {});
            },
            .array_push => |op| {
                try self.used_registers.put(op.array.id, {});
                try self.used_registers.put(op.value.id, {});
            },
            .array_key_exists => |op| {
                try self.used_registers.put(op.array.id, {});
                try self.used_registers.put(op.key.id, {});
            },
            .array_unset => |op| {
                try self.used_registers.put(op.array.id, {});
                try self.used_registers.put(op.key.id, {});
            },
            .property_get => |op| {
                try self.used_registers.put(op.object.id, {});
            },
            .make_ref => |op| {
                try self.used_registers.put(op.ptr.id, {});
            },
            .property_set => |op| {
                try self.used_registers.put(op.object.id, {});
                try self.used_registers.put(op.value.id, {});
            },
            .method_call => |op| {
                try self.used_registers.put(op.object.id, {});
                for (op.args) |arg| {
                    try self.used_registers.put(arg.id, {});
                }
            },
            .new_object => |op| {
                for (op.args) |arg| {
                    try self.used_registers.put(arg.id, {});
                }
            },
            .instanceof => |op| {
                try self.used_registers.put(op.object.id, {});
            },
            .implements_interface => |op| {
                try self.used_registers.put(op.object.id, {});
            },
            .static_method_call => |op| {
                for (op.args) |arg| {
                    try self.used_registers.put(arg.id, {});
                }
            },
            .static_property_get => {},
            .static_property_set => |op| {
                try self.used_registers.put(op.value.id, {});
            },
            .closure_new => |op| {
                try self.used_registers.put(op.func_ptr.id, {});
                for (op.captures) |cap| {
                    try self.used_registers.put(cap.id, {});
                }
            },
            .closure_bind => |op| {
                try self.used_registers.put(op.closure.id, {});
                try self.used_registers.put(op.object.id, {});
            },
            .parent_call => |op| {
                try self.used_registers.put(op.object.id, {});
                for (op.args) |arg| {
                    try self.used_registers.put(arg.id, {});
                }
            },
            .box => |op| {
                try self.used_registers.put(op.value.id, {});
            },
            .unbox => |op| {
                try self.used_registers.put(op.value.id, {});
            },
            .phi => |op| {
                for (op.incoming) |inc| {
                    try self.used_registers.put(inc.value.id, {});
                }
            },
            .select => |op| {
                try self.used_registers.put(op.cond.id, {});
                try self.used_registers.put(op.then_value.id, {});
                try self.used_registers.put(op.else_value.id, {});
            },
            .interpolate => |op| {
                for (op.parts) |part| {
                    try self.used_registers.put(part.id, {});
                }
            },
            // Instructions with no register operands
            .alloca, .array_new, .const_int, .const_float, .const_bool, .const_string, .const_null, .const_missing, .param, .capture_get, .arg_count, .has_arg => {},
            .try_begin, .try_end, .get_exception, .clear_exception => {},
            .mutex_lock, .mutex_unlock, .mutex_new => {},
            .catch_ => {},
            // Concurrency operations
            .go_spawn => |op| {
                for (op.args) |arg| {
                    try self.used_registers.put(arg.id, {});
                }
            },
            .channel_new => {},
            .channel_send => |op| {
                try self.used_registers.put(op.channel.id, {});
                try self.used_registers.put(op.value.id, {});
            },
            .channel_recv => |op| {
                try self.used_registers.put(op.channel.id, {});
            },
            .channel_close, .await_ => |op| {
                try self.used_registers.put(op.operand.id, {});
            },
            .select_ => |op| {
                for (op.cases) |case| {
                    try self.used_registers.put(case.channel.id, {});
                    if (case.value) |v| {
                        try self.used_registers.put(v.id, {});
                    }
                }
            },
            .nop => {},
        }
    }

    /// Mark registers used in a terminator
    fn markRegistersInTerminator(self: *Self, term: Terminator) !void {
        switch (term) {
            .ret => |val| {
                if (val) |reg| {
                    try self.used_registers.put(reg.id, {});
                }
            },
            .cond_br => |cb| {
                try self.used_registers.put(cb.cond.id, {});
            },
            .switch_ => |sw| {
                try self.used_registers.put(sw.value.id, {});
            },
            .throw => |reg| {
                try self.used_registers.put(reg.id, {});
            },
            .br, .unreachable_ => {},
        }
    }

    /// Check if an instruction has side effects
    fn hasSideEffects(self: *const Self, inst: *const Instruction) bool {
        _ = self;
        return switch (inst.op) {
            // Side-effect free operations
            .add, .sub, .mul, .div, .mod, .pow => false,
            .bit_and, .bit_or, .bit_xor, .bit_not, .shl, .shr => false,
            .eq, .ne, .lt, .le, .gt, .ge, .identical, .not_identical, .spaceship => false,
            .and_, .or_, .not => false,
            .neg => false,
            .const_int, .const_float, .const_bool, .const_string, .const_null, .const_missing => false,
            .param, .capture_get, .arg_count, .has_arg => false,
            .cast, .type_check, .get_type => false,
            .box, .unbox => false,
            .phi, .select => false,
            .alloca => false,
            .load => false,
            .make_ref => false,
            .strlen, .array_count => false,
            .instanceof => false,
            .implements_interface => false,

            // Operations with side effects
            .store => true,
            .call, .call_indirect => true,
            .array_new, .array_get, .array_set, .array_push, .array_key_exists, .array_unset => true,
            .concat, .interpolate => true,
            .new_object, .property_get, .property_set, .method_call, .clone => true,
            .static_method_call, .static_property_get, .static_property_set => true,
            .closure_new, .closure_bind, .parent_call => true,
            .retain, .release => true,
            .try_begin, .try_end, .catch_, .get_exception, .clear_exception => true,
            .mutex_lock, .mutex_unlock, .mutex_new => true,
            .go_spawn, .channel_new, .channel_send, .channel_recv, .channel_close, .select_, .await_ => true,
            .debug_print => true,
            .nop => false,
        };
    }

    fn isAllocationLike(self: *const Self, inst: *const Instruction) bool {
        _ = self;
        return switch (inst.op) {
            .array_new, .new_object, .concat, .interpolate, .closure_new => true,
            else => false,
        };
    }

    fn mayRaiseException(self: *const Self, inst: *const Instruction) bool {
        _ = self;
        return switch (inst.op) {
            .call, .call_indirect, .method_call, .static_method_call, .new_object, .parent_call => true,
            .array_get, .array_set, .array_push, .array_unset, .array_key_exists => true,
            .property_get, .property_set, .static_property_get, .static_property_set => true,
            .concat, .interpolate, .closure_new, .closure_bind => true,
            .cast, .type_check, .unbox => true,
            else => false,
        };
    }

    /// Remove unreachable basic blocks
    fn removeUnreachableBlocks(self: *Self, func: *Function) !bool {
        if (func.blocks.items.len <= 1) return false;

        var changed = false;
        var reachable = std.AutoHashMap(*BasicBlock, void).init(self.allocator);
        defer reachable.deinit();

        // Mark reachable blocks starting from entry
        if (func.getEntryBlock()) |entry| {
            try self.markReachableBlocks(entry, &reachable);
        }

        // Remove unreachable blocks
        var i: usize = 0;
        while (i < func.blocks.items.len) {
            const block = func.blocks.items[i];
            if (!reachable.contains(block)) {
                // Remove block
                _ = func.blocks.orderedRemove(i);
                block.deinit();
                self.allocator.destroy(block);
                self.stats.dead_blocks_removed += 1;
                changed = true;
            } else {
                i += 1;
            }
        }

        if (changed) {
            try Analysis.rebuildCFG(func);
        }

        return changed;
    }

    /// Mark all blocks reachable from a given block
    fn markReachableBlocks(self: *Self, block: *BasicBlock, reachable: *std.AutoHashMap(*BasicBlock, void)) !void {
        if (reachable.contains(block)) return;
        try reachable.put(block, {});

        // Follow terminator to successors
        if (block.terminator) |term| {
            switch (term) {
                .br => |target| {
                    try self.markReachableBlocks(target, reachable);
                },
                .cond_br => |cb| {
                    try self.markReachableBlocks(cb.then_block, reachable);
                    try self.markReachableBlocks(cb.else_block, reachable);
                },
                .switch_ => |sw| {
                    for (sw.cases) |case| {
                        try self.markReachableBlocks(case.block, reachable);
                    }
                    try self.markReachableBlocks(sw.default, reachable);
                },
                .ret, .unreachable_, .throw => {},
            }
        }
    }

    // ========================================================================
    // Constant Propagation
    // ========================================================================

    /// Run constant propagation on the entire module
    fn runConstantPropagation(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.propagateConstantsInFunction(func)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Propagate constants in a single function
    fn propagateConstantsInFunction(self: *Self, func: *Function) !bool {
        var changed = false;
        self.constant_values.clearRetainingCapacity();

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                // Record constant definitions
                if (inst.result) |result| {
                    if (self.getConstantValue(inst)) |const_val| {
                        try self.constant_values.put(result.id, const_val);
                    }
                }

                // Try to fold constant expressions
                if (try self.foldConstantExpression(inst)) {
                    changed = true;
                    self.stats.constants_propagated += 1;
                }
            }
        }

        return changed;
    }

    /// Get constant value from an instruction if it's a constant
    fn getConstantValue(self: *const Self, inst: *const Instruction) ?ConstantValue {
        _ = self;
        return switch (inst.op) {
            .const_int => |val| .{ .int = val },
            .const_float => |val| .{ .float = val },
            .const_bool => |val| .{ .bool_val = val },
            .const_null => .{ .null_val = {} },
            .const_missing => .{ .missing_val = {} },
            .const_string => |id| .{ .string_id = id },
            else => null,
        };
    }

    /// Try to fold a constant expression
    fn foldConstantExpression(self: *Self, inst: *Instruction) !bool {
        switch (inst.op) {
            .add => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_int = lhs.int + rhs.int };
                            return true;
                        }
                        if (lhs == .float and rhs == .float) {
                            inst.op = .{ .const_float = lhs.float + rhs.float };
                            return true;
                        }
                    }
                }
            },
            .sub => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_int = lhs.int - rhs.int };
                            return true;
                        }
                        if (lhs == .float and rhs == .float) {
                            inst.op = .{ .const_float = lhs.float - rhs.float };
                            return true;
                        }
                    }
                }
            },
            .mul => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_int = lhs.int * rhs.int };
                            return true;
                        }
                        if (lhs == .float and rhs == .float) {
                            inst.op = .{ .const_float = lhs.float * rhs.float };
                            return true;
                        }
                    }
                }
            },
            .div => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int and rhs.int != 0) {
                            inst.op = .{ .const_int = @divTrunc(lhs.int, rhs.int) };
                            return true;
                        }
                        if (lhs == .float and rhs == .float and rhs.float != 0.0) {
                            inst.op = .{ .const_float = lhs.float / rhs.float };
                            return true;
                        }
                    }
                }
            },
            .mod => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int and rhs.int != 0) {
                            inst.op = .{ .const_int = @mod(lhs.int, rhs.int) };
                            return true;
                        }
                    }
                }
            },
            .neg => |op| {
                if (self.constant_values.get(op.operand.id)) |val| {
                    if (val == .int) {
                        inst.op = .{ .const_int = -val.int };
                        return true;
                    }
                    if (val == .float) {
                        inst.op = .{ .const_float = -val.float };
                        return true;
                    }
                }
            },
            .not => |op| {
                if (self.constant_values.get(op.operand.id)) |val| {
                    if (val == .bool_val) {
                        inst.op = .{ .const_bool = !val.bool_val };
                        return true;
                    }
                }
            },
            .eq => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_bool = lhs.int == rhs.int };
                            return true;
                        }
                        if (lhs == .bool_val and rhs == .bool_val) {
                            inst.op = .{ .const_bool = lhs.bool_val == rhs.bool_val };
                            return true;
                        }
                    }
                }
            },
            .ne => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_bool = lhs.int != rhs.int };
                            return true;
                        }
                    }
                }
            },
            .lt => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_bool = lhs.int < rhs.int };
                            return true;
                        }
                    }
                }
            },
            .le => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_bool = lhs.int <= rhs.int };
                            return true;
                        }
                    }
                }
            },
            .gt => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_bool = lhs.int > rhs.int };
                            return true;
                        }
                    }
                }
            },
            .ge => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .int and rhs == .int) {
                            inst.op = .{ .const_bool = lhs.int >= rhs.int };
                            return true;
                        }
                    }
                }
            },
            .and_ => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .bool_val and rhs == .bool_val) {
                            inst.op = .{ .const_bool = lhs.bool_val and rhs.bool_val };
                            return true;
                        }
                    }
                }
            },
            .or_ => |op| {
                if (self.constant_values.get(op.lhs.id)) |lhs| {
                    if (self.constant_values.get(op.rhs.id)) |rhs| {
                        if (lhs == .bool_val and rhs == .bool_val) {
                            inst.op = .{ .const_bool = lhs.bool_val or rhs.bool_val };
                            return true;
                        }
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn runBoxUnboxElimination(self: *Self, module: *Module) !bool {
        var changed = false;
        for (module.functions.items) |func| {
            if (try self.eliminateBoxUnboxInFunction(func)) {
                changed = true;
            }
        }
        return changed;
    }

    fn eliminateBoxUnboxInFunction(self: *Self, func: *Function) !bool {
        var changed = false;
        var defs = std.AutoHashMap(u32, *Instruction).init(self.allocator);
        defer defs.deinit();

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |r| {
                    try defs.put(r.id, inst);
                }
            }
        }

        for (func.blocks.items) |block| {
            var i: usize = 0;
            while (i < block.instructions.items.len) {
                const inst = block.instructions.items[i];
                if (inst.op == .unbox and inst.result != null) {
                    const op = inst.op.unbox;
                    if (defs.get(op.value.id)) |def_inst| {
                        if (def_inst.op == .box and def_inst.result != null and def_inst.result.?.id == op.value.id) {
                            const b = def_inst.op.box;
                            if (b.from_type.eql(op.to_type)) {
                                self.replaceRegisterUsage(func, inst.result.?, b.value);
                                _ = block.instructions.orderedRemove(i);
                                inst.deinit(self.allocator);
                                self.allocator.destroy(inst);
                                changed = true;
                                continue;
                            }
                        }
                    }
                }
                i += 1;
            }
        }

        return changed;
    }

    fn runCFGCleanup(self: *Self, module: *Module) !bool {
        var changed = false;
        for (module.functions.items) |func| {
            if (try self.cleanupCFGInFunction(func)) {
                changed = true;
            }
        }
        return changed;
    }

    fn cleanupCFGInFunction(self: *Self, func: *Function) !bool {
        if (func.blocks.items.len == 0) return false;
        try Analysis.rebuildCFG(func);

        var changed = false;
        var i: usize = 0;
        while (i < func.blocks.items.len) {
            const block = func.blocks.items[i];
            const is_entry = (i == 0);
            if (!is_entry) {
                if (try self.tryRemoveTrampolineBlock(func, block, &i)) {
                    changed = true;
                    continue;
                }
            }
            i += 1;
        }

        try Analysis.rebuildCFG(func);

        i = 0;
        while (i < func.blocks.items.len) {
            const block = func.blocks.items[i];
            if (try self.tryMergeBlockWithSingleSuccessor(func, block)) {
                changed = true;
                try Analysis.rebuildCFG(func);
                i = 0;
                continue;
            }
            i += 1;
        }

        if (try self.simplifyTrivialConditionalBranches(func)) {
            changed = true;
            try Analysis.rebuildCFG(func);
        }

        return changed;
    }

    fn simplifyTrivialConditionalBranches(self: *Self, func: *Function) !bool {
        var changed = false;

        var bool_consts = std.AutoHashMap(u32, bool).init(self.allocator);
        defer bool_consts.deinit();

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |r| {
                    if (inst.op == .const_bool) {
                        try bool_consts.put(r.id, inst.op.const_bool);
                    }
                }
            }
        }

        for (func.blocks.items) |block| {
            if (block.terminator) |*term| {
                switch (term.*) {
                    .cond_br => |cb| {
                        if (cb.then_block == cb.else_block) {
                            term.* = .{ .br = cb.then_block };
                            changed = true;
                            continue;
                        }
                        if (bool_consts.get(cb.cond.id)) |v| {
                            term.* = .{ .br = if (v) cb.then_block else cb.else_block };
                            changed = true;
                        }
                    },
                    else => {},
                }
            }
        }

        return changed;
    }

    fn tryRemoveTrampolineBlock(self: *Self, func: *Function, block: *BasicBlock, i: *usize) !bool {
        if (block.instructions.items.len != 0) return false;
        if (block.exception_handler != null) return false;

        const term = block.terminator orelse return false;
        if (term != .br) return false;

        const target = term.br;

        for (block.predecessors.items) |pred| {
            if (pred.terminator) |*pt| {
                self.replaceBlockInTerminator(pt, block, target);
            }
        }

        try self.expandPhiIncomingForRemovedBlock(target, block, block.predecessors.items);

        _ = func.blocks.orderedRemove(i.*);
        block.deinit();
        self.allocator.destroy(block);
        return true;
    }

    fn tryMergeBlockWithSingleSuccessor(self: *Self, func: *Function, block: *BasicBlock) !bool {
        const term = block.terminator orelse return false;
        if (term != .br) return false;

        const succ = term.br;
        if (succ == block) return false;

        if (succ.predecessors.items.len != 1 or succ.predecessors.items[0] != block) return false;

        if (try self.simplifySinglePredecessorPhiNodes(func, succ)) {}

        for (succ.instructions.items) |inst| {
            try block.instructions.append(self.allocator, inst);
        }
        succ.instructions.shrinkRetainingCapacity(0);

        block.terminator = succ.terminator;
        succ.terminator = null;

        self.rewritePhiBlockRefInSuccessors(succ, block);

        for (func.blocks.items, 0..) |b, idx| {
            if (b == succ) {
                _ = func.blocks.orderedRemove(idx);
                succ.deinit();
                self.allocator.destroy(succ);
                break;
            }
        }

        return true;
    }

    fn simplifySinglePredecessorPhiNodes(self: *Self, func: *Function, block: *BasicBlock) !bool {
        var changed = false;
        var i: usize = 0;
        while (i < block.instructions.items.len) {
            const inst = block.instructions.items[i];
            if (inst.op == .phi and inst.result != null) {
                const inc = inst.op.phi.incoming;
                if (inc.len == 1) {
                    self.replaceRegisterUsage(func, inst.result.?, inc[0].value);
                    _ = block.instructions.orderedRemove(i);
                    inst.deinit(self.allocator);
                    self.allocator.destroy(inst);
                    changed = true;
                    continue;
                }
            }
            i += 1;
        }
        return changed;
    }

    fn expandPhiIncomingForRemovedBlock(
        self: *Self,
        target: *BasicBlock,
        removed_block: *BasicBlock,
        preds: []const *BasicBlock,
    ) !void {
        for (target.instructions.items) |inst| {
            switch (inst.op) {
                .phi => |*op| {
                    const old = op.incoming;
                    var new_len: usize = 0;
                    for (old) |inc| {
                        if (inc.block == removed_block) {
                            new_len += preds.len;
                        } else {
                            new_len += 1;
                        }
                    }

                    if (new_len == old.len) continue;

                    const new_incoming = try self.allocator.alloc(Instruction.PhiIncoming, new_len);
                    var j: usize = 0;
                    for (old) |inc| {
                        if (inc.block == removed_block) {
                            for (preds) |p| {
                                new_incoming[j] = .{ .value = inc.value, .block = p };
                                j += 1;
                            }
                        } else {
                            new_incoming[j] = inc;
                            j += 1;
                        }
                    }

                    self.allocator.free(old);
                    op.incoming = new_incoming;
                },
                else => {},
            }
        }
    }

    fn rewritePhiBlockRefInSuccessors(self: *Self, old_block: *BasicBlock, new_block: *BasicBlock) void {
        if (old_block.terminator) |term| {
            switch (term) {
                .br => |b| self.rewritePhiBlockRefInBlock(b, old_block, new_block),
                .cond_br => |cb| {
                    self.rewritePhiBlockRefInBlock(cb.then_block, old_block, new_block);
                    self.rewritePhiBlockRefInBlock(cb.else_block, old_block, new_block);
                },
                .switch_ => |sw| {
                    for (sw.cases) |c| self.rewritePhiBlockRefInBlock(c.block, old_block, new_block);
                    self.rewritePhiBlockRefInBlock(sw.default, old_block, new_block);
                },
                else => {},
            }
        }
    }

    fn rewritePhiBlockRefInBlock(self: *Self, block: *BasicBlock, old_block: *BasicBlock, new_block: *BasicBlock) void {
        _ = self;
        for (block.instructions.items) |inst| {
            if (inst.op == .phi) {
                const inc_ptr = @constCast(inst.op.phi.incoming.ptr);
                for (0..inst.op.phi.incoming.len) |idx| {
                    if (inc_ptr[idx].block == old_block) inc_ptr[idx].block = new_block;
                }
            }
        }
    }

    fn replaceBlockInTerminator(self: *Self, term: *Terminator, old_block: *BasicBlock, new_block: *BasicBlock) void {
        _ = self;
        switch (term.*) {
            .br => |*b| {
                if (b.* == old_block) b.* = new_block;
            },
            .cond_br => |*cb| {
                if (cb.then_block == old_block) cb.then_block = new_block;
                if (cb.else_block == old_block) cb.else_block = new_block;
            },
            .switch_ => |*sw| {
                const cases_ptr = @constCast(sw.cases.ptr);
                for (0..sw.cases.len) |idx| {
                    if (cases_ptr[idx].block == old_block) cases_ptr[idx].block = new_block;
                }
                if (sw.default == old_block) sw.default = new_block;
            },
            else => {},
        }
    }

    // ========================================================================
    // Function Inlining
    // ========================================================================

    /// Build call graph for inlining decisions
    fn buildCallGraph(self: *Self, module: *const Module) !void {
        self.call_graph.clearRetainingCapacity();

        for (module.functions.items) |func| {
            var info = FunctionInfo{
                .instruction_count = 0,
                .call_count = 0,
                .block_count = @intCast(func.blocks.items.len),
                .branch_count = 0,
                .alloc_count = 0,
                .may_throw = false,
                .estimated_cost = 0,
                .has_side_effects = false,
                .is_recursive = false,
                .can_inline = true,
            };

            // Count instructions and analyze function
            for (func.blocks.items) |block| {
                info.instruction_count += @intCast(block.instructions.items.len);

                for (block.instructions.items) |inst| {
                    // Check for side effects
                    if (self.hasSideEffects(inst)) {
                        info.has_side_effects = true;
                    }

                    if (self.mayRaiseException(inst)) {
                        info.may_throw = true;
                    }

                    if (self.isAllocationLike(inst)) {
                        info.alloc_count += 1;
                    }

                    // Check for recursive calls
                    switch (inst.op) {
                        .call => |op| {
                            if (std.mem.eql(u8, op.func_name, func.name)) {
                                info.is_recursive = true;
                            }
                        },
                        else => {},
                    }
                }

                if (block.terminator) |term| {
                    switch (term) {
                        .cond_br, .switch_ => info.branch_count += 1,
                        else => {},
                    }
                }
            }

            const base_cost: u32 = info.instruction_count;
            const branch_cost: u32 = info.branch_count * 3;
            const alloc_cost: u32 = info.alloc_count * 10;
            const throw_cost: u32 = if (info.may_throw) 20 else 0;
            info.estimated_cost = base_cost + branch_cost + alloc_cost + throw_cost;

            // Determine if function can be inlined
            info.can_inline = !info.is_recursive and
                info.estimated_cost <= self.config.inline_threshold and
                info.block_count <= 6;

            try self.call_graph.put(func.name, info);
        }

        // Count call sites
        for (module.functions.items) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    switch (inst.op) {
                        .call => |op| {
                            if (self.call_graph.getPtr(op.func_name)) |info| {
                                info.call_count += 1;
                            }
                        },
                        else => {},
                    }
                }
            }
        }
    }

    /// Run function inlining on the entire module
    fn runFunctionInlining(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.inlineFunctionsInFunction(func, module)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Inline functions in a single function
    fn inlineFunctionsInFunction(self: *Self, func: *Function, module: *const Module) !bool {
        var changed = false;

        for (func.blocks.items) |block| {
            var i: usize = 0;
            while (i < block.instructions.items.len) {
                const inst = block.instructions.items[i];

                switch (inst.op) {
                    .call => |op| {
                        // Check if function should be inlined
                        if (self.shouldInline(op.func_name)) {
                            // Find the callee function
                            if (module.findFunction(op.func_name)) |callee| {
                                // Inline the function
                                if (try self.inlineFunction(func, block, i, callee, op.args)) {
                                    self.stats.functions_inlined += 1;
                                    changed = true;
                                    continue; // Don't increment i, instruction was replaced
                                }
                            }
                        }
                    },
                    else => {},
                }
                i += 1;
            }
        }

        return changed;
    }

    /// Check if a function should be inlined
    fn shouldInline(self: *const Self, func_name: []const u8) bool {
        if (self.call_graph.get(func_name)) |info| {
            if (!info.can_inline) return false;
            const very_small = info.estimated_cost * 4 <= self.config.inline_threshold;
            const max_calls: u32 = if (very_small) 10 else 3;
            return info.call_count <= max_calls;
        }
        return false;
    }

    /// Inline a function at a call site
    fn inlineFunction(
        self: *Self,
        caller: *Function,
        block: *BasicBlock,
        inst_index: usize,
        callee: *const Function,
        args: []const Register,
    ) !bool {
        // Safety checks
        if (callee.blocks.items.len == 0) return false;
        if (callee.blocks.items.len > 3) return false; // Only inline simple functions

        const call_inst = block.instructions.items[inst_index];
        const result_reg = call_inst.result;

        // Get callee's entry block
        const callee_entry = callee.getEntryBlock() orelse return false;

        // Create register mapping: callee register ID -> new register ID in caller
        var reg_map = std.AutoHashMap(u32, u32).init(self.allocator);
        defer reg_map.deinit();

        // Map parameters to arguments
        for (callee.params.items, 0..) |_, i| {
            if (i < args.len) {
                // Map parameter register to argument register
                // Note: Parameters are typically represented by their index
                try reg_map.put(@intCast(i), args[i].id);
            }
        }

        // Allocate new registers for callee's local registers
        var next_reg_id = caller.getNextRegisterId();

        // Collect instructions to inline (excluding terminators)
        var inlined_instructions: std.ArrayListUnmanaged(*Instruction) = .{};
        defer inlined_instructions.deinit(self.allocator);

        // Process callee's entry block instructions
        for (callee_entry.instructions.items) |callee_inst| {
            // Clone and remap the instruction
            const new_inst = try self.cloneAndRemapInstruction(callee_inst, &reg_map, &next_reg_id);
            if (new_inst) |inst| {
                try inlined_instructions.append(self.allocator, inst);
            }
        }

        // Handle return value: find the return terminator and map its value
        if (callee_entry.terminator) |term| {
            switch (term) {
                .ret => |ret_val| {
                    if (ret_val) |ret_reg| {
                        // Map the return value to the call result
                        if (result_reg) |res| {
                            const mapped_ret_id = reg_map.get(ret_reg.id) orelse ret_reg.id;
                            // Create a copy instruction from return value to result
                            const copy_inst = try self.allocator.create(Instruction);
                            copy_inst.* = Instruction{
                                .result = res,
                                .op = .{ .load = .{
                                    .ptr = Register{ .id = mapped_ret_id, .type_ = ret_reg.type_ },
                                    .type_ = ret_reg.type_,
                                } },
                                .location = call_inst.location,
                            };
                            try inlined_instructions.append(self.allocator, copy_inst);
                        }
                    }
                },
                else => {},
            }
        }

        // Replace the call instruction with inlined instructions
        if (inlined_instructions.items.len > 0) {
            // Remove the call instruction
            _ = block.instructions.orderedRemove(inst_index);
            self.allocator.destroy(call_inst);

            // Insert inlined instructions at the call site
            for (inlined_instructions.items, 0..) |inst, i| {
                try block.instructions.insert(self.allocator, inst_index + i, inst);
            }

            return true;
        }

        return false;
    }

    /// Clone an instruction and remap its registers
    fn cloneAndRemapInstruction(
        self: *Self,
        inst: *const Instruction,
        reg_map: *std.AutoHashMap(u32, u32),
        next_reg_id: *u32,
    ) !?*Instruction {
        const new_inst = try self.allocator.create(Instruction);
        errdefer self.allocator.destroy(new_inst);

        // Remap result register
        var new_result: ?Register = null;
        if (inst.result) |res| {
            const new_id = next_reg_id.*;
            next_reg_id.* += 1;
            try reg_map.put(res.id, new_id);
            new_result = Register{ .id = new_id, .type_ = res.type_ };
        }

        // Clone and remap operands based on instruction type
        const new_op = try self.remapInstructionOp(inst.op, reg_map);

        new_inst.* = Instruction{
            .result = new_result,
            .op = new_op,
            .location = inst.location,
        };

        return new_inst;
    }

    /// Remap registers in an instruction operation
    fn remapInstructionOp(
        self: *Self,
        op: Instruction.Op,
        reg_map: *std.AutoHashMap(u32, u32),
    ) !Instruction.Op {
        return switch (op) {
            .add => |bin| .{ .add = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .sub => |bin| .{ .sub = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .mul => |bin| .{ .mul = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .div => |bin| .{ .div = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .mod => |bin| .{ .mod = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .neg => |un| .{ .neg = .{
                .operand = remapRegister(un.operand, reg_map),
            } },
            .not => |un| .{ .not = .{
                .operand = remapRegister(un.operand, reg_map),
            } },
            .eq => |bin| .{ .eq = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .ne => |bin| .{ .ne = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .lt => |bin| .{ .lt = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .le => |bin| .{ .le = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .gt => |bin| .{ .gt = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .ge => |bin| .{ .ge = .{
                .lhs = remapRegister(bin.lhs, reg_map),
                .rhs = remapRegister(bin.rhs, reg_map),
            } },
            .load => |ld| .{ .load = .{
                .ptr = remapRegister(ld.ptr, reg_map),
                .type_ = ld.type_,
            } },
            .store => |st| .{ .store = .{
                .ptr = remapRegister(st.ptr, reg_map),
                .value = remapRegister(st.value, reg_map),
            } },
            .const_int, .const_float, .const_bool, .const_string, .const_null, .const_missing, .arg_count, .has_arg => op,
            .alloca => op,
            .param => op,
            
            // Deep copy needed for slice fields
            .call => |call| blk: {
                const new_args = try self.allocator.alloc(Register, call.args.len);
                for (call.args, 0..) |arg, i| {
                    new_args[i] = remapRegister(arg, reg_map);
                }
                break :blk .{ .call = .{
                     .func_name = call.func_name, // String literal/slice, usually static or owned by module? Assumed safe to share if const
                     .args = new_args,
                     .return_type = call.return_type,
                 } };
             },
            .call_indirect => |call| blk: {
                const new_args = try self.allocator.alloc(Register, call.args.len);
                for (call.args, 0..) |arg, i| {
                    new_args[i] = remapRegister(arg, reg_map);
                }
                break :blk .{ .call_indirect = .{
                    .func_ptr = remapRegister(call.func_ptr, reg_map),
                    .args = new_args,
                    .return_type = call.return_type,
                } };
            },
            .interpolate => |interp| blk: {
                const new_parts = try self.allocator.alloc(Register, interp.parts.len);
                for (interp.parts, 0..) |part, i| {
                    new_parts[i] = remapRegister(part, reg_map);
                }
                break :blk .{ .interpolate = .{ .parts = new_parts } };
            },
            .new_object => |op0| blk: {
                const new_args = try self.allocator.alloc(Register, op0.args.len);
                for (op0.args, 0..) |arg, i| {
                    new_args[i] = remapRegister(arg, reg_map);
                }
                break :blk .{ .new_object = .{ .class_name = op0.class_name, .args = new_args } };
            },
            .method_call => |op0| blk: {
                const new_args = try self.allocator.alloc(Register, op0.args.len);
                for (op0.args, 0..) |arg, i| {
                    new_args[i] = remapRegister(arg, reg_map);
                }
                break :blk .{ .method_call = .{
                    .object = remapRegister(op0.object, reg_map),
                    .method_name = op0.method_name,
                    .args = new_args,
                } };
            },
            .static_method_call => |op0| blk: {
                const new_args = try self.allocator.alloc(Register, op0.args.len);
                for (op0.args, 0..) |arg, i| {
                    new_args[i] = remapRegister(arg, reg_map);
                }
                break :blk .{ .static_method_call = .{
                    .class_name = op0.class_name,
                    .method_name = op0.method_name,
                    .args = new_args,
                } };
            },
            .closure_new => |op0| blk: {
                const new_caps = try self.allocator.alloc(Register, op0.captures.len);
                for (op0.captures, 0..) |cap, i| {
                    new_caps[i] = remapRegister(cap, reg_map);
                }
                break :blk .{ .closure_new = .{
                    .func_ptr = remapRegister(op0.func_ptr, reg_map),
                    .captures = new_caps,
                    .param_count = op0.param_count,
                } };
            },
            .parent_call => |op0| blk: {
                const new_args = try self.allocator.alloc(Register, op0.args.len);
                for (op0.args, 0..) |arg, i| {
                    new_args[i] = remapRegister(arg, reg_map);
                }
                break :blk .{ .parent_call = .{
                    .object = remapRegister(op0.object, reg_map),
                    .method_name = op0.method_name,
                    .args = new_args,
                } };
            },
            .phi => |phi| blk: {
                 const IncomingType = @TypeOf(phi.incoming[0]);
                 const new_incoming = try self.allocator.alloc(IncomingType, phi.incoming.len);
                 for (phi.incoming, 0..) |inc, i| {
                    // Block pointers need to be remapped if we are cloning blocks... 
                    // But here we only remap registers.
                    // If blocks are also cloned, we might need a block map.
                    // For Loop Unrolling, we fix up Phi nodes separately after cloning.
                    // So we can just copy the block pointer for now?
                    // Or maybe we should clone the structure.
                    new_incoming[i] = .{
                        .block = inc.block, 
                        .value = remapRegister(inc.value, reg_map),
                    };
                }
                break :blk .{ .phi = .{ .incoming = new_incoming } };
            },
            else => op,
        };
    }

    /// Remap a single register using the mapping
    fn remapRegister(reg: Register, reg_map: *std.AutoHashMap(u32, u32)) Register {
        const new_id = reg_map.get(reg.id) orelse reg.id;
        return Register{ .id = new_id, .type_ = reg.type_ };
    }

    // ========================================================================
    // Type Specialization
    // ========================================================================

    /// Run type specialization on the entire module
    fn runTypeSpecialization(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.specializeTypesInFunction(func)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Specialize types in a single function
    fn specializeTypesInFunction(self: *Self, func: *Function) !bool {
        var changed = false;

        // Track known types for registers
        self.type_known_types.clearRetainingCapacity();
        var known_types = &self.type_known_types;

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                // Record type information from constants
                if (inst.result) |result| {
                    switch (inst.op) {
                        .const_int => try known_types.put(result.id, .i64),
                        .const_float => try known_types.put(result.id, .f64),
                        .const_bool => try known_types.put(result.id, .bool),
                        .const_string => try known_types.put(result.id, .php_string),
                        .const_null => try known_types.put(result.id, .void),
                        .const_missing => try known_types.put(result.id, .php_value),
                        .array_new => try known_types.put(result.id, .php_array),
                        else => {},
                    }
                }

                // Try to specialize operations based on known types
                if (try self.specializeInstruction(inst, known_types)) {
                    changed = true;
                    self.stats.type_specializations += 1;
                }
            }
        }

        return changed;
    }

    /// Try to specialize an instruction based on known types
    fn specializeInstruction(self: *Self, inst: *Instruction, known_types: *std.AutoHashMap(u32, Type)) !bool {
        _ = self;

        switch (inst.op) {
            // Specialize arithmetic operations when both operands have known integer types
            .add => |op| {
                const lhs_type = known_types.get(op.lhs.id);
                const rhs_type = known_types.get(op.rhs.id);
                if (lhs_type != null and rhs_type != null) {
                    if (lhs_type.? == .i64 and rhs_type.? == .i64) {
                        // Already specialized to integer, update result type
                        if (inst.result) |*res| {
                            if (res.type_ == .php_value) {
                                res.type_ = .i64;
                                return true;
                            }
                        }
                    } else if (lhs_type.? == .f64 or rhs_type.? == .f64) {
                        // Specialize to float
                        if (inst.result) |*res| {
                            if (res.type_ == .php_value) {
                                res.type_ = .f64;
                                return true;
                            }
                        }
                    }
                }
            },
            .sub => |op| {
                const lhs_type = known_types.get(op.lhs.id);
                const rhs_type = known_types.get(op.rhs.id);
                if (lhs_type != null and rhs_type != null) {
                    if (lhs_type.? == .i64 and rhs_type.? == .i64) {
                        if (inst.result) |*res| {
                            if (res.type_ == .php_value) {
                                res.type_ = .i64;
                                return true;
                            }
                        }
                    } else if (lhs_type.? == .f64 or rhs_type.? == .f64) {
                        if (inst.result) |*res| {
                            if (res.type_ == .php_value) {
                                res.type_ = .f64;
                                return true;
                            }
                        }
                    }
                }
            },
            .mul => |op| {
                const lhs_type = known_types.get(op.lhs.id);
                const rhs_type = known_types.get(op.rhs.id);
                if (lhs_type != null and rhs_type != null) {
                    if (lhs_type.? == .i64 and rhs_type.? == .i64) {
                        if (inst.result) |*res| {
                            if (res.type_ == .php_value) {
                                res.type_ = .i64;
                                return true;
                            }
                        }
                    } else if (lhs_type.? == .f64 or rhs_type.? == .f64) {
                        if (inst.result) |*res| {
                            if (res.type_ == .php_value) {
                                res.type_ = .f64;
                                return true;
                            }
                        }
                    }
                }
            },
            .div => |op| {
                const lhs_type = known_types.get(op.lhs.id);
                const rhs_type = known_types.get(op.rhs.id);
                if (lhs_type != null and rhs_type != null) {
                    // Division typically produces float in PHP
                    if (inst.result) |*res| {
                        if (res.type_ == .php_value) {
                            res.type_ = .f64;
                            return true;
                        }
                    }
                }
            },
            // Specialize comparison operations
            .eq, .ne, .lt, .le, .gt, .ge => {
                // Comparisons always return bool
                if (inst.result) |*res| {
                    if (res.type_ == .php_value) {
                        res.type_ = .bool;
                        return true;
                    }
                }
            },
            // Specialize logical operations
            .and_, .or_, .not => {
                // Logical operations always return bool
                if (inst.result) |*res| {
                    if (res.type_ == .php_value) {
                        res.type_ = .bool;
                        return true;
                    }
                }
            },
            // Specialize negation
            .neg => |op| {
                const operand_type = known_types.get(op.operand.id);
                if (operand_type) |t| {
                    if (inst.result) |*res| {
                        if (res.type_ == .php_value) {
                            res.type_ = t;
                            return true;
                        }
                    }
                }
            },
            // Specialize strlen - always returns int
            .strlen => {
                if (inst.result) |*res| {
                    if (res.type_ == .php_value) {
                        res.type_ = .i64;
                        return true;
                    }
                }
            },
            // Specialize array_count - always returns int
            .array_count => {
                if (inst.result) |*res| {
                    if (res.type_ == .php_value) {
                        res.type_ = .i64;
                        return true;
                    }
                }
            },
            // Specialize type_check - always returns bool
            .type_check => {
                if (inst.result) |*res| {
                    if (res.type_ == .php_value) {
                        res.type_ = .bool;
                        return true;
                    }
                }
            },
            // Specialize instanceof - always returns bool
            .instanceof => {
                if (inst.result) |*res| {
                    if (res.type_ == .php_value) {
                        res.type_ = .bool;
                        return true;
                    }
                }
            },
            // Specialize array_key_exists - always returns bool
            .array_key_exists => {
                if (inst.result) |*res| {
                    if (res.type_ == .php_value) {
                        res.type_ = .bool;
                        return true;
                    }
                }
            },
            else => {},
        }
        return false;
    }

    // ========================================================================
    // Common Subexpression Elimination (CSE)
    // ========================================================================

    /// Run CSE on the entire module
    fn runCSE(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.eliminateCSEInFunction(func)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Eliminate common subexpressions in a function
    fn eliminateCSEInFunction(self: *Self, func: *Function) !bool {
        // We need dominator tree for safe GVN/CSE
        try Analysis.rebuildCFG(func);
        var dt = try Analysis.computeDominators(self.allocator, func);
        defer dt.deinit();

        var changed = false;

        // Map from expression hash to (Register, defining_block)
        const CSEEntry = struct {
            reg: Register,
            block: *BasicBlock,
        };
        var expr_map = std.AutoHashMap(u64, CSEEntry).init(self.allocator);
        defer expr_map.deinit();
        
        // We must visit blocks in dominance order (e.g. RPO or pre-order on DomTree)
        // For simplicity, we just iterate blocks. But to be correct, we only reuse if:
        // 1. Definition dominates Use
        // Since we process all instructions, if we find a match in expr_map, we check dominance.
        
        for (func.blocks.items) |block| {
            // Optimization: If we process blocks in RPO, we see definitions before uses more often.
            // But checking dominance is always required for correctness unless we scope the map.
            
            for (block.instructions.items) |inst| {
                // Only consider pure expressions
                if (self.hasSideEffects(inst)) continue;

                // Compute expression hash
                const hash = self.hashExpression(inst);
                if (hash == 0) continue;

                if (expr_map.get(hash)) |entry| {
                    // Check if the defining block dominates the current block
                    if (dt.dominates(entry.block, block)) {
                        // Found common subexpression - replace usage
                        if (inst.result) |result| {
                            // We can replace 'result' with 'entry.reg'
                            // But we need to update all USERS of 'result' to use 'entry.reg'
                            // Since we don't have use-def chains, this is expensive (scan all insts).
                            // For now, let's just mark it.
                            // To implement replacement: 
                            // 1. Replace usages
                            // 2. Turn this inst into a COPY (or NOP if we replace usages directly)
                            
                            // Let's implement usage replacement
                            self.replaceRegisterUsage(func, result, entry.reg);
                            
                            // Turn current instruction into NOP
                            // We can't easily remove it from list while iterating (unless we handle index)
                            // So we make it a NOP or a COPY.
                            // But we don't have COPY instruction? 
                            // If we replaced usages, this instruction is dead (if side-effect free).
                            // DCE will remove it later.
                            
                            // We should clear the result so it looks like it produces nothing?
                            // Or just change op to Nop.
                            // However, 'inst' is a pointer to the instruction in the list.
                            
                            // IMPORTANT: We need to modify the instruction in place.
                            // Deinit old ops if needed.
                            inst.deinit(self.allocator);
                            inst.op = .nop;
                            inst.result = null; // Result is no longer produced here
                            
                            self.stats.cse_eliminations += 1;
                            changed = true;
                        }
                    }
                } else {
                    // Record this expression
                    if (inst.result) |result| {
                        try expr_map.put(hash, .{ .reg = result, .block = block });
                    }
                }
            }
        }

        return changed;
    }

    /// Replace all usages of old_reg with new_reg in the function
    fn replaceRegisterUsage(self: *Self, func: *Function, old_reg: Register, new_reg: Register) void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                self.replaceRegisterInInst(inst, old_reg, new_reg);
            }
            // Check terminator
            if (block.terminator) |*term| {
                self.replaceRegisterInTerminator(term, old_reg, new_reg);
            }
        }
    }

    /// Helper to replace register in instruction operands
    fn replaceRegisterInInst(self: *Self, inst: *Instruction, old_reg: Register, new_reg: Register) void {
        _ = self;
        switch (inst.op) {
            .add, .sub, .mul, .div, .mod, .pow,
            .bit_and, .bit_or, .bit_xor, .shl, .shr,
            .eq, .ne, .lt, .le, .gt, .ge, .identical, .not_identical, .spaceship,
            .and_, .or_, .concat => |*op| {
                if (op.lhs.id == old_reg.id) op.lhs = new_reg;
                if (op.rhs.id == old_reg.id) op.rhs = new_reg;
            },
            .neg, .bit_not, .not, .strlen, .array_count, .clone, .retain, .release, .debug_print, .get_type,
            .channel_close, .await_ => |*op| {
                if (op.operand.id == old_reg.id) op.operand = new_reg;
            },
            .channel_recv => |*op| {
                if (op.channel.id == old_reg.id) op.channel = new_reg;
            },
            .cast => |*op| {
                if (op.value.id == old_reg.id) op.value = new_reg;
            },
            .type_check => |*op| {
                if (op.value.id == old_reg.id) op.value = new_reg;
            },
            .box => |*op| {
                if (op.value.id == old_reg.id) op.value = new_reg;
            },
            .unbox => |*op| {
                if (op.value.id == old_reg.id) op.value = new_reg;
            },
            .load => |*op| {
                if (op.ptr.id == old_reg.id) op.ptr = new_reg;
            },
            .store => |*op| {
                if (op.ptr.id == old_reg.id) op.ptr = new_reg;
                if (op.value.id == old_reg.id) op.value = new_reg;
            },
            .call => |*op| {
                // args is []const Register, we need to cast to mutable to update in place?
                // Or reallocation? The args are usually in an array allocated by allocator.
                // It is const in the struct definition.
                // We strictly shouldn't modify const data.
                // But this is an optimizer, rewriting code.
                // We cast away const for optimization.
                const args_ptr = @constCast(op.args.ptr);
                for (0..op.args.len) |i| {
                    if (args_ptr[i].id == old_reg.id) args_ptr[i] = new_reg;
                }
            },
            .phi => |*op| {
                const inc_ptr = @constCast(op.incoming.ptr);
                for (0..op.incoming.len) |i| {
                    if (inc_ptr[i].value.id == old_reg.id) inc_ptr[i].value = new_reg;
                }
            },
            // Handle other ops...
            else => {},
        }
    }

    /// Helper to replace register in terminator
    fn replaceRegisterInTerminator(self: *Self, term: *Terminator, old_reg: Register, new_reg: Register) void {
        _ = self;
        switch (term.*) {
            .ret => |*val| {
                if (val.*) |*v| {
                    if (v.id == old_reg.id) v.* = new_reg;
                }
            },
            .cond_br => |*cb| {
                if (cb.cond.id == old_reg.id) cb.cond = new_reg;
            },
            .switch_ => |*sw| {
                if (sw.value.id == old_reg.id) sw.value = new_reg;
            },
            .throw => |*val| {
                if (val.id == old_reg.id) val.* = new_reg;
            },
            else => {},
        }
    }

    /// Compute a hash for an expression (for CSE)
    fn hashExpression(self: *const Self, inst: *const Instruction) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);

        switch (inst.op) {
            // Arithmetic operations
            .add => |op| {
                hasher.update("add");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .sub => |op| {
                hasher.update("sub");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .mul => |op| {
                hasher.update("mul");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .div => |op| {
                hasher.update("div");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .mod => |op| {
                hasher.update("mod");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .pow => |op| {
                hasher.update("pow");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            // Bitwise operations
            .bit_and => |op| {
                hasher.update("bit_and");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .bit_or => |op| {
                hasher.update("bit_or");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .bit_xor => |op| {
                hasher.update("bit_xor");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .shl => |op| {
                hasher.update("shl");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .shr => |op| {
                hasher.update("shr");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            // Comparison operations
            .eq => |op| {
                hasher.update("eq");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .ne => |op| {
                hasher.update("ne");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .lt => |op| {
                hasher.update("lt");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .le => |op| {
                hasher.update("le");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .gt => |op| {
                hasher.update("gt");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .ge => |op| {
                hasher.update("ge");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .identical => |op| {
                hasher.update("identical");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .not_identical => |op| {
                hasher.update("not_identical");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .spaceship => |op| {
                hasher.update("spaceship");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            // Logical operations
            .and_ => |op| {
                hasher.update("and");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .or_ => |op| {
                hasher.update("or");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            // Unary operations
            .neg => |op| {
                hasher.update("neg");
                hasher.update(std.mem.asBytes(&op.operand.id));
            },
            .not => |op| {
                hasher.update("not");
                hasher.update(std.mem.asBytes(&op.operand.id));
            },
            .bit_not => |op| {
                hasher.update("bit_not");
                hasher.update(std.mem.asBytes(&op.operand.id));
            },
            // String operations
            .concat => |op| {
                hasher.update("concat");
                hasher.update(std.mem.asBytes(&op.lhs.id));
                hasher.update(std.mem.asBytes(&op.rhs.id));
            },
            .strlen => |op| {
                hasher.update("strlen");
                hasher.update(std.mem.asBytes(&op.operand.id));
            },
            // Array operations
            .array_count => |op| {
                hasher.update("array_count");
                hasher.update(std.mem.asBytes(&op.operand.id));
            },
            // Type operations
            .cast => |op| {
                hasher.update("cast");
                hasher.update(std.mem.asBytes(&op.value.id));
                hasher.update(std.mem.asBytes(&op.to_type));
            },
            .type_check => |op| {
                hasher.update("type_check");
                hasher.update(std.mem.asBytes(&op.value.id));
                hasher.update(std.mem.asBytes(&op.expected_type));
            },
            .get_type => |op| {
                hasher.update("get_type");
                hasher.update(std.mem.asBytes(&op.operand.id));
            },
            // Load operations (pure if pointer is the same)
            .load => |op| {
                hasher.update("load");
                hasher.update(std.mem.asBytes(&op.ptr.id));
            },
            // Box/unbox operations
            .box => |op| {
                hasher.update("box");
                hasher.update(std.mem.asBytes(&op.value.id));
            },
            .unbox => |op| {
                hasher.update("unbox");
                hasher.update(std.mem.asBytes(&op.value.id));
            },
            // Constants - hash by value
            .const_int => |val| {
                hasher.update("const_int");
                hasher.update(std.mem.asBytes(&val));
            },
            .const_float => |val| {
                hasher.update("const_float");
                hasher.update(std.mem.asBytes(&val));
            },
            .const_bool => |val| {
                hasher.update("const_bool");
                hasher.update(std.mem.asBytes(&val));
            },
            .const_string => |id| {
                hasher.update("const_string");
                hasher.update(std.mem.asBytes(&id));
            },
            .const_null => {
                hasher.update("const_null");
            },
            .const_missing => {
                hasher.update("const_missing");
            },
            else => return 0, // Not hashable (has side effects or complex)
        }

        return hasher.final();
    }

    // ========================================================================
    // Strength Reduction
    // ========================================================================

    /// Run strength reduction on the entire module
    pub fn runStrengthReduction(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.reduceStrengthInFunction(func)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Apply strength reduction in a function
    pub fn reduceStrengthInFunction(self: *Self, func: *Function) !bool {
        var changed = false;

        for (func.blocks.items) |block| {
            var i: usize = 0;
            while (i < block.instructions.items.len) {
                const inst = block.instructions.items[i];
                if (try self.reduceStrength(func, block, i, inst)) |inserted| {
                    changed = true;
                    // Skip inserted instructions + current instruction
                    i += inserted + 1;
                } else {
                    i += 1;
                }
            }
        }

        return changed;
    }

    /// Apply strength reduction to an instruction
    fn reduceStrength(self: *Self, func: *Function, block: *BasicBlock, index: usize, inst: *Instruction) !?usize {
        switch (inst.op) {
            .mul => |op| {
                // Multiply by power of 2 -> shift left
                if (self.constant_values.get(op.rhs.id)) |rhs| {
                    if (rhs == .int) {
                        if (self.isPowerOfTwo(rhs.int)) |shift| {
                            // Create constant for shift amount
                            const shift_reg = func.newRegister(.i64);
                            const shift_inst = try self.allocator.create(Instruction);
                            shift_inst.* = .{
                                .result = shift_reg,
                                .op = .{ .const_int = shift },
                                .location = inst.location,
                            };
                            
                            try block.instructions.insert(self.allocator, index, shift_inst);
                            
                            inst.op = .{ .shl = .{
                                .lhs = op.lhs,
                                .rhs = shift_reg,
                            } };
                            
                            return 1;
                        }
                    }
                }
            },
            .div => |op| {
                // Divide by power of 2 -> shift right
                if (self.constant_values.get(op.rhs.id)) |rhs| {
                    if (rhs == .int and rhs.int > 0) {
                        if (self.isPowerOfTwo(rhs.int)) |shift| {
                            const shift_reg = func.newRegister(.i64);
                            const shift_inst = try self.allocator.create(Instruction);
                            shift_inst.* = .{
                                .result = shift_reg,
                                .op = .{ .const_int = shift },
                                .location = inst.location,
                            };
                            
                            try block.instructions.insert(self.allocator, index, shift_inst);
                            
                            inst.op = .{ .shr = .{
                                .lhs = op.lhs,
                                .rhs = shift_reg,
                            } };
                            
                            return 1;
                        }
                    }
                }
            },
            .mod => |op| {
                // Modulo by power of 2 -> bitwise and
                if (self.constant_values.get(op.rhs.id)) |rhs| {
                    if (rhs == .int and rhs.int > 0) {
                        if (self.isPowerOfTwo(rhs.int)) |_| {
                            const mask_reg = func.newRegister(.i64);
                            const mask_inst = try self.allocator.create(Instruction);
                            mask_inst.* = .{
                                .result = mask_reg,
                                .op = .{ .const_int = rhs.int - 1 },
                                .location = inst.location,
                            };
                            
                            try block.instructions.insert(self.allocator, index, mask_inst);
                            
                            inst.op = .{ .bit_and = .{
                                .lhs = op.lhs,
                                .rhs = mask_reg,
                            } };
                            
                            return 1;
                        }
                    }
                }
            },
            else => {},
        }
        return null;
    }

    /// Check if a value is a power of 2 and return the exponent
    fn isPowerOfTwo(self: *const Self, val: i64) ?u6 {
        _ = self;
        if (val <= 0) return null;
        const uval: u64 = @intCast(val);
        if (uval & (uval - 1) != 0) return null;
        return @intCast(@ctz(uval));
    }
};

// ============================================================================
// LLVM Optimization Configuration
// ============================================================================

/// LLVM Pass Manager configuration
pub const LLVMPassConfig = struct {
    /// Enable basic alias analysis
    basic_aa: bool = true,
    /// Enable type-based alias analysis
    tbaa: bool = true,
    /// Enable scalar replacement of aggregates
    sroa: bool = true,
    /// Enable early CSE
    early_cse: bool = true,
    /// Enable lower expect intrinsic
    lower_expect: bool = true,
    /// Enable GVN (Global Value Numbering)
    gvn: bool = false,
    /// Enable instruction combining
    instcombine: bool = true,
    /// Enable jump threading
    jump_threading: bool = false,
    /// Enable CFG simplification
    simplifycfg: bool = true,
    /// Enable reassociate
    reassociate: bool = false,
    /// Enable loop rotate
    loop_rotate: bool = false,
    /// Enable LICM (Loop Invariant Code Motion)
    licm: bool = false,
    /// Enable loop unroll
    loop_unroll: bool = false,
    /// Enable loop vectorize
    loop_vectorize: bool = false,
    /// Enable SLP vectorize
    slp_vectorize: bool = false,
    /// Enable memcpy optimization
    memcpyopt: bool = false,
    /// Enable dead store elimination
    dse: bool = true,
    /// Enable aggressive dead code elimination
    adce: bool = false,
    /// Enable function inlining
    inline_functions: bool = false,
    /// Inline threshold (higher = more inlining)
    inline_threshold: u32 = 225,
    /// Enable tail call elimination
    tailcallelim: bool = false,
    /// Enable merge functions
    mergefunc: bool = false,
    /// Enable global DCE
    globaldce: bool = false,
    /// Enable constant merge
    constmerge: bool = false,
    /// Enable strip dead prototypes
    strip_dead_prototypes: bool = false,

    /// Get configuration for debug builds
    pub fn debug() LLVMPassConfig {
        return .{
            .basic_aa = false,
            .tbaa = false,
            .sroa = false,
            .early_cse = false,
            .lower_expect = false,
            .gvn = false,
            .instcombine = false,
            .jump_threading = false,
            .simplifycfg = false,
            .reassociate = false,
            .loop_rotate = false,
            .licm = false,
            .loop_unroll = false,
            .loop_vectorize = false,
            .slp_vectorize = false,
            .memcpyopt = false,
            .dse = false,
            .adce = false,
            .inline_functions = false,
            .inline_threshold = 0,
            .tailcallelim = false,
            .mergefunc = false,
            .globaldce = false,
            .constmerge = false,
            .strip_dead_prototypes = false,
        };
    }

    /// Get configuration for release-safe builds (O1-like)
    pub fn releaseSafe() LLVMPassConfig {
        return .{
            .basic_aa = true,
            .tbaa = true,
            .sroa = true,
            .early_cse = true,
            .lower_expect = true,
            .gvn = false,
            .instcombine = true,
            .jump_threading = false,
            .simplifycfg = true,
            .reassociate = true,
            .loop_rotate = false,
            .licm = false,
            .loop_unroll = false,
            .loop_vectorize = false,
            .slp_vectorize = false,
            .memcpyopt = false,
            .dse = true,
            .adce = false,
            .inline_functions = false,
            .inline_threshold = 225,
            .tailcallelim = false,
            .mergefunc = false,
            .globaldce = false,
            .constmerge = false,
            .strip_dead_prototypes = false,
        };
    }

    /// Get configuration for release-fast builds (O3-like)
    pub fn releaseFast() LLVMPassConfig {
        return .{
            .basic_aa = true,
            .tbaa = true,
            .sroa = true,
            .early_cse = true,
            .lower_expect = true,
            .gvn = true,
            .instcombine = true,
            .jump_threading = true,
            .simplifycfg = true,
            .reassociate = true,
            .loop_rotate = true,
            .licm = true,
            .loop_unroll = true,
            .loop_vectorize = true,
            .slp_vectorize = true,
            .memcpyopt = true,
            .dse = true,
            .adce = true,
            .inline_functions = true,
            .inline_threshold = 500,
            .tailcallelim = true,
            .mergefunc = false,
            .globaldce = true,
            .constmerge = true,
            .strip_dead_prototypes = true,
        };
    }

    /// Get configuration for release-small builds (Os-like)
    pub fn releaseSmall() LLVMPassConfig {
        return .{
            .basic_aa = true,
            .tbaa = true,
            .sroa = true,
            .early_cse = true,
            .lower_expect = true,
            .gvn = false,
            .instcombine = true,
            .jump_threading = false,
            .simplifycfg = true,
            .reassociate = true,
            .loop_rotate = false,
            .licm = false,
            .loop_unroll = false, // Unrolling increases size
            .loop_vectorize = false, // Vectorization increases size
            .slp_vectorize = false,
            .memcpyopt = true,
            .dse = true,
            .adce = true,
            .inline_functions = false, // Inlining increases size
            .inline_threshold = 25, // Very conservative
            .tailcallelim = true,
            .mergefunc = true, // Merge identical functions
            .globaldce = true,
            .constmerge = true,
            .strip_dead_prototypes = true,
        };
    }
};

/// LLVM Pass Manager wrapper
pub const LLVMPassManager = struct {
    allocator: Allocator,
    config: LLVMPassConfig,
    pass_manager: ?*anyopaque, // LLVMPassManagerRef when LLVM is available
    llvm_available: bool,

    const Self = @This();

    /// Initialize the pass manager
    pub fn init(allocator: Allocator, level: OptimizeLevel) Self {
        const config = switch (level) {
            .none => LLVMPassConfig.debug(),
            .basic => LLVMPassConfig.releaseSafe(),
            .aggressive => LLVMPassConfig.releaseFast(),
            .size => LLVMPassConfig.releaseSmall(),
        };

        return .{
            .allocator = allocator,
            .config = config,
            .pass_manager = null,
            .llvm_available = false,
        };
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: Allocator, config: LLVMPassConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .pass_manager = null,
            .llvm_available = false,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        // In real LLVM mode: LLVMDisposePassManager(self.pass_manager)
        _ = self;
    }

    /// Create the LLVM pass manager with configured passes
    pub fn create(self: *Self) !void {
        if (!self.llvm_available) return;

        // In real LLVM mode:
        // self.pass_manager = LLVMCreatePassManager();
        // Then add passes based on config:
        // if (self.config.basic_aa) LLVMAddBasicAliasAnalysisPass(self.pass_manager);
        // if (self.config.tbaa) LLVMAddTypeBasedAliasAnalysisPass(self.pass_manager);
        // etc.
    }

    /// Run the pass manager on a module
    pub fn run(self: *Self, module: ?*anyopaque) !bool {
        if (!self.llvm_available or self.pass_manager == null) return false;
        _ = module;

        // In real LLVM mode:
        // return LLVMRunPassManager(self.pass_manager, module) != 0;
        return false;
    }

    /// Get the list of enabled passes (for debugging)
    pub fn getEnabledPasses(self: *const Self, allocator: Allocator) ![]const []const u8 {
        var passes = std.ArrayListUnmanaged([]const u8){};

        if (self.config.basic_aa) try passes.append(allocator, "basic-aa");
        if (self.config.tbaa) try passes.append(allocator, "tbaa");
        if (self.config.sroa) try passes.append(allocator, "sroa");
        if (self.config.early_cse) try passes.append(allocator, "early-cse");
        if (self.config.lower_expect) try passes.append(allocator, "lower-expect");
        if (self.config.gvn) try passes.append(allocator, "gvn");
        if (self.config.instcombine) try passes.append(allocator, "instcombine");
        if (self.config.jump_threading) try passes.append(allocator, "jump-threading");
        if (self.config.simplifycfg) try passes.append(allocator, "simplifycfg");
        if (self.config.reassociate) try passes.append(allocator, "reassociate");
        if (self.config.loop_rotate) try passes.append(allocator, "loop-rotate");
        if (self.config.licm) try passes.append(allocator, "licm");
        if (self.config.loop_unroll) try passes.append(allocator, "loop-unroll");
        if (self.config.loop_vectorize) try passes.append(allocator, "loop-vectorize");
        if (self.config.slp_vectorize) try passes.append(allocator, "slp-vectorize");
        if (self.config.memcpyopt) try passes.append(allocator, "memcpyopt");
        if (self.config.dse) try passes.append(allocator, "dse");
        if (self.config.adce) try passes.append(allocator, "adce");
        if (self.config.inline_functions) try passes.append(allocator, "inline");
        if (self.config.tailcallelim) try passes.append(allocator, "tailcallelim");
        if (self.config.mergefunc) try passes.append(allocator, "mergefunc");
        if (self.config.globaldce) try passes.append(allocator, "globaldce");
        if (self.config.constmerge) try passes.append(allocator, "constmerge");
        if (self.config.strip_dead_prototypes) try passes.append(allocator, "strip-dead-prototypes");

        return passes.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "OptimizeLevel.getPassConfig" {
    const debug_config = OptimizeLevel.none.getPassConfig();
    try std.testing.expect(!debug_config.dead_code_elimination);
    try std.testing.expect(!debug_config.constant_propagation);
    try std.testing.expect(!debug_config.function_inlining);

    const fast_config = OptimizeLevel.aggressive.getPassConfig();
    try std.testing.expect(fast_config.dead_code_elimination);
    try std.testing.expect(fast_config.constant_propagation);
    try std.testing.expect(fast_config.function_inlining);
    try std.testing.expect(fast_config.type_specialization);
}

test "PassConfig presets" {
    const debug = PassConfig.debug();
    try std.testing.expect(!debug.dead_code_elimination);
    try std.testing.expectEqual(@as(u32, 1), debug.max_iterations);

    const safe = PassConfig.releaseSafe();
    try std.testing.expect(safe.dead_code_elimination);
    try std.testing.expect(safe.cse);
    try std.testing.expect(!safe.function_inlining);

    const fast = PassConfig.releaseFast();
    try std.testing.expect(fast.function_inlining);
    try std.testing.expect(fast.type_specialization);
    try std.testing.expect(fast.licm);
    try std.testing.expectEqual(@as(u32, 50), fast.inline_threshold);

    const small = PassConfig.releaseSmall();
    try std.testing.expect(!small.function_inlining);
    try std.testing.expect(small.strength_reduction);
}

test "OptimizationStats" {
    var stats = OptimizationStats{};
    stats.dead_instructions_removed = 5;
    stats.constants_propagated = 3;

    try std.testing.expectEqual(@as(u32, 5), stats.dead_instructions_removed);
    try std.testing.expectEqual(@as(u32, 3), stats.constants_propagated);

    stats.reset();
    try std.testing.expectEqual(@as(u32, 0), stats.dead_instructions_removed);
    try std.testing.expectEqual(@as(u32, 0), stats.constants_propagated);
}

test "IROptimizer.init and deinit" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    try std.testing.expect(optimizer.config.dead_code_elimination);
    try std.testing.expect(optimizer.config.function_inlining);
}

test "IROptimizer.initWithConfig" {
    const allocator = std.testing.allocator;

    const config = PassConfig{
        .dead_code_elimination = true,
        .constant_propagation = false,
        .function_inlining = false,
        .inline_threshold = 100,
        .type_specialization = false,
        .cse = true,
        .licm = false,
        .strength_reduction = false,
        .max_iterations = 10,
    };

    var optimizer = IROptimizer.initWithConfig(allocator, config, null);
    defer optimizer.deinit();

    try std.testing.expect(optimizer.config.dead_code_elimination);
    try std.testing.expect(!optimizer.config.constant_propagation);
    try std.testing.expectEqual(@as(u32, 100), optimizer.config.inline_threshold);
    try std.testing.expectEqual(@as(u32, 10), optimizer.config.max_iterations);
}

test "IROptimizer.getStats and resetStats" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .basic, null);
    defer optimizer.deinit();

    optimizer.stats.dead_instructions_removed = 10;
    optimizer.stats.constants_propagated = 5;

    const stats = optimizer.getStats();
    try std.testing.expectEqual(@as(u32, 10), stats.dead_instructions_removed);
    try std.testing.expectEqual(@as(u32, 5), stats.constants_propagated);

    optimizer.resetStats();
    const reset_stats = optimizer.getStats();
    try std.testing.expectEqual(@as(u32, 0), reset_stats.dead_instructions_removed);
    try std.testing.expectEqual(@as(u32, 0), reset_stats.constants_propagated);
}

test "IROptimizer.isPowerOfTwo" {
    const allocator = std.testing.allocator;
    var optimizer = IROptimizer.init(allocator, .none, null);
    defer optimizer.deinit();

    try std.testing.expectEqual(@as(?u6, 0), optimizer.isPowerOfTwo(1));
    try std.testing.expectEqual(@as(?u6, 1), optimizer.isPowerOfTwo(2));
    try std.testing.expectEqual(@as(?u6, 2), optimizer.isPowerOfTwo(4));
    try std.testing.expectEqual(@as(?u6, 3), optimizer.isPowerOfTwo(8));
    try std.testing.expectEqual(@as(?u6, 4), optimizer.isPowerOfTwo(16));
    try std.testing.expectEqual(@as(?u6, 10), optimizer.isPowerOfTwo(1024));

    try std.testing.expect(optimizer.isPowerOfTwo(0) == null);
    try std.testing.expect(optimizer.isPowerOfTwo(-1) == null);
    try std.testing.expect(optimizer.isPowerOfTwo(3) == null);
    try std.testing.expect(optimizer.isPowerOfTwo(5) == null);
    try std.testing.expect(optimizer.isPowerOfTwo(6) == null);
    try std.testing.expect(optimizer.isPowerOfTwo(7) == null);
}

test "IROptimizer.hasSideEffects" {
    const allocator = std.testing.allocator;
    var optimizer = IROptimizer.init(allocator, .none, null);
    defer optimizer.deinit();

    // Create test instructions
    const add_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .add = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expect(!optimizer.hasSideEffects(&add_inst));

    const const_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .const_int = 42 },
        .location = .{},
    };
    try std.testing.expect(!optimizer.hasSideEffects(&const_inst));

    const call_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .php_value },
        .op = .{ .call = .{
            .func_name = "test",
            .args = &[_]Register{},
            .return_type = .php_value,
        } },
        .location = .{},
    };
    try std.testing.expect(optimizer.hasSideEffects(&call_inst));

    const store_inst = Instruction{
        .result = null,
        .op = .{ .store = .{
            .ptr = Register{ .id = 1, .type_ = .php_value },
            .value = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expect(optimizer.hasSideEffects(&store_inst));
}

test "LLVMPassConfig presets" {
    const debug = LLVMPassConfig.debug();
    try std.testing.expect(!debug.basic_aa);
    try std.testing.expect(!debug.instcombine);
    try std.testing.expect(!debug.inline_functions);
    try std.testing.expectEqual(@as(u32, 0), debug.inline_threshold);

    const safe = LLVMPassConfig.releaseSafe();
    try std.testing.expect(safe.basic_aa);
    try std.testing.expect(safe.instcombine);
    try std.testing.expect(safe.simplifycfg);
    try std.testing.expect(!safe.inline_functions);
    try std.testing.expect(!safe.loop_vectorize);

    const fast = LLVMPassConfig.releaseFast();
    try std.testing.expect(fast.basic_aa);
    try std.testing.expect(fast.gvn);
    try std.testing.expect(fast.inline_functions);
    try std.testing.expect(fast.loop_vectorize);
    try std.testing.expect(fast.slp_vectorize);
    try std.testing.expect(fast.licm);
    try std.testing.expectEqual(@as(u32, 500), fast.inline_threshold);

    const small = LLVMPassConfig.releaseSmall();
    try std.testing.expect(small.basic_aa);
    try std.testing.expect(!small.inline_functions);
    try std.testing.expect(!small.loop_unroll);
    try std.testing.expect(!small.loop_vectorize);
    try std.testing.expect(small.mergefunc);
    try std.testing.expect(small.globaldce);
    try std.testing.expectEqual(@as(u32, 25), small.inline_threshold);
}

test "LLVMPassManager.init" {
    const allocator = std.testing.allocator;

    var pm = LLVMPassManager.init(allocator, .aggressive);
    defer pm.deinit();

    try std.testing.expect(pm.config.gvn);
    try std.testing.expect(pm.config.inline_functions);
    try std.testing.expect(!pm.llvm_available);
}

test "LLVMPassManager.initWithConfig" {
    const allocator = std.testing.allocator;

    const config = LLVMPassConfig{
        .basic_aa = true,
        .instcombine = true,
        .simplifycfg = true,
        .inline_functions = false,
        .inline_threshold = 100,
    };

    var pm = LLVMPassManager.initWithConfig(allocator, config);
    defer pm.deinit();

    try std.testing.expect(pm.config.basic_aa);
    try std.testing.expect(pm.config.instcombine);
    try std.testing.expect(!pm.config.inline_functions);
    try std.testing.expectEqual(@as(u32, 100), pm.config.inline_threshold);
}

test "LLVMPassManager.getEnabledPasses" {
    const allocator = std.testing.allocator;

    var pm = LLVMPassManager.init(allocator, .basic);
    defer pm.deinit();

    const passes = try pm.getEnabledPasses(allocator);
    defer allocator.free(passes);

    // Check that some expected passes are present
    var has_instcombine = false;
    var has_simplifycfg = false;
    for (passes) |pass| {
        if (std.mem.eql(u8, pass, "instcombine")) has_instcombine = true;
        if (std.mem.eql(u8, pass, "simplifycfg")) has_simplifycfg = true;
    }
    try std.testing.expect(has_instcombine);
    try std.testing.expect(has_simplifycfg);
}

test "ConstantValue union" {
    const int_val = IROptimizer.ConstantValue{ .int = 42 };
    try std.testing.expectEqual(@as(i64, 42), int_val.int);

    const float_val = IROptimizer.ConstantValue{ .float = 3.14 };
    try std.testing.expectEqual(@as(f64, 3.14), float_val.float);

    const bool_val = IROptimizer.ConstantValue{ .bool_val = true };
    try std.testing.expect(bool_val.bool_val);

    const null_val = IROptimizer.ConstantValue{ .null_val = {} };
    _ = null_val;

    const string_val = IROptimizer.ConstantValue{ .string_id = 123 };
    try std.testing.expectEqual(@as(u32, 123), string_val.string_id);
}

test "FunctionInfo struct" {
    const info = IROptimizer.FunctionInfo{
        .instruction_count = 15,
        .call_count = 3,
        .block_count = 2,
        .branch_count = 1,
        .alloc_count = 0,
        .may_throw = true,
        .estimated_cost = 45,
        .has_side_effects = true,
        .is_recursive = false,
        .can_inline = true,
    };

    try std.testing.expectEqual(@as(u32, 15), info.instruction_count);
    try std.testing.expectEqual(@as(u32, 3), info.call_count);
    try std.testing.expect(info.has_side_effects);
    try std.testing.expect(!info.is_recursive);
    try std.testing.expect(info.can_inline);
}

test "OptimizationStats.print" {
    var stats = OptimizationStats{
        .dead_instructions_removed = 10,
        .dead_blocks_removed = 2,
        .constants_propagated = 5,
        .functions_inlined = 1,
        .type_specializations = 3,
        .cse_eliminations = 4,
        .passes_run = 3,
    };

    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try stats.print(stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Dead instructions removed: 10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Dead blocks removed: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Constants propagated: 5") != null);
}

test "IROptimizer.remapRegister" {
    var reg_map = std.AutoHashMap(u32, u32).init(std.testing.allocator);
    defer reg_map.deinit();

    try reg_map.put(1, 100);
    try reg_map.put(2, 200);

    // Test remapping existing register
    const reg1 = Register{ .id = 1, .type_ = .i64 };
    const remapped1 = IROptimizer.remapRegister(reg1, &reg_map);
    try std.testing.expectEqual(@as(u32, 100), remapped1.id);
    try std.testing.expectEqual(Type.i64, remapped1.type_);

    // Test remapping non-existing register (should keep original)
    const reg3 = Register{ .id = 3, .type_ = .f64 };
    const remapped3 = IROptimizer.remapRegister(reg3, &reg_map);
    try std.testing.expectEqual(@as(u32, 3), remapped3.id);
    try std.testing.expectEqual(Type.f64, remapped3.type_);
}

test "IROptimizer.shouldInline" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    // Add a function to call graph that can be inlined
    try optimizer.call_graph.put("small_func", .{
        .instruction_count = 5,
        .call_count = 2,
        .block_count = 1,
        .branch_count = 0,
        .alloc_count = 0,
        .may_throw = false,
        .estimated_cost = 5,
        .has_side_effects = false,
        .is_recursive = false,
        .can_inline = true,
    });

    // Add a function that cannot be inlined (too many calls)
    try optimizer.call_graph.put("hot_func", .{
        .instruction_count = 5,
        .call_count = 10,
        .block_count = 1,
        .branch_count = 0,
        .alloc_count = 0,
        .may_throw = false,
        .estimated_cost = 20,
        .has_side_effects = false,
        .is_recursive = false,
        .can_inline = true,
    });

    // Add a recursive function
    try optimizer.call_graph.put("recursive_func", .{
        .instruction_count = 5,
        .call_count = 1,
        .block_count = 1,
        .branch_count = 0,
        .alloc_count = 0,
        .may_throw = false,
        .estimated_cost = 5,
        .has_side_effects = false,
        .is_recursive = true,
        .can_inline = false,
    });

    try std.testing.expect(optimizer.shouldInline("small_func"));
    try std.testing.expect(!optimizer.shouldInline("hot_func")); // Too many call sites
    try std.testing.expect(!optimizer.shouldInline("recursive_func")); // Recursive
    try std.testing.expect(!optimizer.shouldInline("unknown_func")); // Not in call graph
}

test "IROptimizer.specializeInstruction - comparison operations" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    var known_types = std.AutoHashMap(u32, Type).init(allocator);
    defer known_types.deinit();

    // Test eq specialization
    var eq_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .php_value },
        .op = .{ .eq = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };

    const specialized = try optimizer.specializeInstruction(&eq_inst, &known_types);
    try std.testing.expect(specialized);
    try std.testing.expectEqual(Type.bool, eq_inst.result.?.type_);
}

test "IROptimizer.specializeInstruction - arithmetic with known types" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    var known_types = std.AutoHashMap(u32, Type).init(allocator);
    defer known_types.deinit();

    // Set up known types
    try known_types.put(1, .i64);
    try known_types.put(2, .i64);

    // Test add specialization with integer operands
    var add_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .php_value },
        .op = .{ .add = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };

    const specialized = try optimizer.specializeInstruction(&add_inst, &known_types);
    try std.testing.expect(specialized);
    try std.testing.expectEqual(Type.i64, add_inst.result.?.type_);
}

test "IROptimizer.specializeInstruction - strlen returns int" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    var known_types = std.AutoHashMap(u32, Type).init(allocator);
    defer known_types.deinit();

    var strlen_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .php_value },
        .op = .{ .strlen = .{
            .operand = Register{ .id = 1, .type_ = .php_string },
        } },
        .location = .{},
    };

    const specialized = try optimizer.specializeInstruction(&strlen_inst, &known_types);
    try std.testing.expect(specialized);
    try std.testing.expectEqual(Type.i64, strlen_inst.result.?.type_);
}

test "IROptimizer.specializeInstruction - logical operations return bool" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    var known_types = std.AutoHashMap(u32, Type).init(allocator);
    defer known_types.deinit();

    // Test not operation
    var not_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .php_value },
        .op = .{ .not = .{
            .operand = Register{ .id = 1, .type_ = .bool },
        } },
        .location = .{},
    };

    const specialized = try optimizer.specializeInstruction(&not_inst, &known_types);
    try std.testing.expect(specialized);
    try std.testing.expectEqual(Type.bool, not_inst.result.?.type_);
}

test "IROptimizer.specializeInstruction - float promotion" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    var known_types = std.AutoHashMap(u32, Type).init(allocator);
    defer known_types.deinit();

    // Set up known types - one int, one float
    try known_types.put(1, .i64);
    try known_types.put(2, .f64);

    // Test mul specialization with mixed types -> float
    var mul_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .php_value },
        .op = .{ .mul = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .f64 },
        } },
        .location = .{},
    };

    const specialized = try optimizer.specializeInstruction(&mul_inst, &known_types);
    try std.testing.expect(specialized);
    try std.testing.expectEqual(Type.f64, mul_inst.result.?.type_);
}

test "IROptimizer.cloneAndRemapInstruction" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    var reg_map = std.AutoHashMap(u32, u32).init(allocator);
    defer reg_map.deinit();

    try reg_map.put(1, 100);
    try reg_map.put(2, 200);

    var next_reg_id: u32 = 300;

    // Create an add instruction to clone
    const original = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .add = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };

    const cloned = try optimizer.cloneAndRemapInstruction(&original, &reg_map, &next_reg_id);
    defer if (cloned) |c| allocator.destroy(c);

    try std.testing.expect(cloned != null);
    try std.testing.expectEqual(@as(u32, 300), cloned.?.result.?.id);
    try std.testing.expectEqual(@as(u32, 301), next_reg_id);

    // Check operands are remapped
    switch (cloned.?.op) {
        .add => |op| {
            try std.testing.expectEqual(@as(u32, 100), op.lhs.id);
            try std.testing.expectEqual(@as(u32, 200), op.rhs.id);
        },
        else => try std.testing.expect(false),
    }
}

test "IROptimizer.remapInstructionOp - constants unchanged" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    var reg_map = std.AutoHashMap(u32, u32).init(allocator);
    defer reg_map.deinit();

    // Test that constants are not remapped
    const const_op = Instruction.Op{ .const_int = 42 };
    const remapped = try optimizer.remapInstructionOp(const_op, &reg_map);

    switch (remapped) {
        .const_int => |val| try std.testing.expectEqual(@as(i64, 42), val),
        else => try std.testing.expect(false),
    }
}

test "IROptimizer.hashExpression - comprehensive coverage" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    // Test arithmetic operations produce non-zero hashes
    const add_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .add = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expect(optimizer.hashExpression(&add_inst) != 0);

    // Test comparison operations
    const eq_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .bool },
        .op = .{ .eq = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expect(optimizer.hashExpression(&eq_inst) != 0);

    // Test unary operations
    const neg_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .neg = .{
            .operand = Register{ .id = 1, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expect(optimizer.hashExpression(&neg_inst) != 0);

    // Test constants
    const const_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .const_int = 42 },
        .location = .{},
    };
    try std.testing.expect(optimizer.hashExpression(&const_inst) != 0);

    // Test that different operations produce different hashes
    const sub_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .sub = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expect(optimizer.hashExpression(&add_inst) != optimizer.hashExpression(&sub_inst));

    // Test that same operation with same operands produces same hash
    const add_inst2 = Instruction{
        .result = Register{ .id = 10, .type_ = .i64 }, // Different result register
        .op = .{ .add = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expectEqual(optimizer.hashExpression(&add_inst), optimizer.hashExpression(&add_inst2));

    // Test side-effect operations return 0
    const call_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .php_value },
        .op = .{ .call = .{
            .func_name = "test",
            .args = &[_]Register{},
            .return_type = .php_value,
        } },
        .location = .{},
    };
    try std.testing.expectEqual(@as(u64, 0), optimizer.hashExpression(&call_inst));
}

test "IROptimizer.hashExpression - bitwise operations" {
    const allocator = std.testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    const bit_and_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .bit_and = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expect(optimizer.hashExpression(&bit_and_inst) != 0);

    const bit_or_inst = Instruction{
        .result = Register{ .id = 0, .type_ = .i64 },
        .op = .{ .bit_or = .{
            .lhs = Register{ .id = 1, .type_ = .i64 },
            .rhs = Register{ .id = 2, .type_ = .i64 },
        } },
        .location = .{},
    };
    try std.testing.expect(optimizer.hashExpression(&bit_or_inst) != 0);

    // Different bitwise ops should have different hashes
    try std.testing.expect(optimizer.hashExpression(&bit_and_inst) != optimizer.hashExpression(&bit_or_inst));
}
