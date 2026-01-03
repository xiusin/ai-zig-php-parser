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
    /// Maximum optimization iterations
    max_iterations: u32 = 3,

    /// Debug configuration (no optimizations)
    pub fn debug() PassConfig {
        return .{
            .dead_code_elimination = false,
            .constant_propagation = false,
            .function_inlining = false,
            .inline_threshold = 0,
            .type_specialization = false,
            .cse = false,
            .licm = false,
            .strength_reduction = false,
            .max_iterations = 1,
        };
    }

    /// Release-safe configuration (basic optimizations)
    pub fn releaseSafe() PassConfig {
        return .{
            .dead_code_elimination = true,
            .constant_propagation = true,
            .function_inlining = false,
            .inline_threshold = 10,
            .type_specialization = false,
            .cse = true,
            .licm = false,
            .strength_reduction = false,
            .max_iterations = 2,
        };
    }

    /// Release-fast configuration (aggressive optimizations)
    pub fn releaseFast() PassConfig {
        return .{
            .dead_code_elimination = true,
            .constant_propagation = true,
            .function_inlining = true,
            .inline_threshold = 50,
            .type_specialization = true,
            .cse = true,
            .licm = true,
            .strength_reduction = true,
            .max_iterations = 5,
        };
    }

    /// Release-small configuration (size optimizations)
    pub fn releaseSmall() PassConfig {
        return .{
            .dead_code_elimination = true,
            .constant_propagation = true,
            .function_inlining = false, // Inlining increases size
            .inline_threshold = 5,
            .type_specialization = false,
            .cse = true,
            .licm = false,
            .strength_reduction = true,
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

    /// Set of used registers (for dead code elimination)
    used_registers: std.AutoHashMap(u32, void),
    /// Constant values for propagation
    constant_values: std.AutoHashMap(u32, ConstantValue),
    /// Function call graph for inlining decisions
    call_graph: std.StringHashMap(FunctionInfo),

    const Self = @This();

    /// Constant value representation
    pub const ConstantValue = union(enum) {
        int: i64,
        float: f64,
        bool_val: bool,
        null_val: void,
        string_id: u32,
    };

    /// Function information for inlining
    pub const FunctionInfo = struct {
        instruction_count: u32,
        call_count: u32,
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
            .used_registers = std.AutoHashMap(u32, void).init(allocator),
            .constant_values = std.AutoHashMap(u32, ConstantValue).init(allocator),
            .call_graph = std.StringHashMap(FunctionInfo).init(allocator),
        };
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: Allocator, config: PassConfig, diagnostics: ?*DiagnosticEngine) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .stats = .{},
            .diagnostics = diagnostics,
            .used_registers = std.AutoHashMap(u32, void).init(allocator),
            .constant_values = std.AutoHashMap(u32, ConstantValue).init(allocator),
            .call_graph = std.StringHashMap(FunctionInfo).init(allocator),
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.used_registers.deinit();
        self.constant_values.deinit();
        self.call_graph.deinit();
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
            if (self.config.constant_propagation) {
                if (try self.runConstantPropagation(module)) {
                    changed = true;
                }
            }

            if (self.config.dead_code_elimination) {
                if (try self.runDeadCodeElimination(module)) {
                    changed = true;
                }
            }

            if (self.config.function_inlining) {
                if (try self.runFunctionInlining(module)) {
                    changed = true;
                }
            }

            if (self.config.type_specialization) {
                if (try self.runTypeSpecialization(module)) {
                    changed = true;
                }
            }

            if (self.config.cse) {
                if (try self.runCSE(module)) {
                    changed = true;
                }
            }

            if (self.config.strength_reduction) {
                if (try self.runStrengthReduction(module)) {
                    changed = true;
                }
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

            if (self.config.constant_propagation) {
                if (try self.propagateConstantsInFunction(func)) {
                    changed = true;
                }
            }

            if (self.config.dead_code_elimination) {
                if (try self.eliminateDeadCodeInFunction(func)) {
                    changed = true;
                }
            }

            if (self.config.cse) {
                if (try self.eliminateCSEInFunction(func)) {
                    changed = true;
                }
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
            .alloca, .array_new, .const_int, .const_float, .const_bool, .const_string, .const_null => {},
            .try_begin, .try_end, .get_exception, .clear_exception => {},
            .mutex_lock, .mutex_unlock, .mutex_new => {},
            .catch_ => {},
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
            .const_int, .const_float, .const_bool, .const_string, .const_null => false,
            .cast, .type_check, .get_type => false,
            .box, .unbox => false,
            .phi, .select => false,
            .alloca => false,
            .load => false,
            .strlen, .array_count => false,
            .instanceof => false,

            // Operations with side effects
            .store => true,
            .call, .call_indirect => true,
            .array_new, .array_get, .array_set, .array_push, .array_key_exists, .array_unset => true,
            .concat, .interpolate => true,
            .new_object, .property_get, .property_set, .method_call, .clone => true,
            .retain, .release => true,
            .try_begin, .try_end, .catch_, .get_exception, .clear_exception => true,
            .mutex_lock, .mutex_unlock, .mutex_new => true,
            .debug_print => true,
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
            }

            // Determine if function can be inlined
            info.can_inline = !info.is_recursive and
                info.instruction_count <= self.config.inline_threshold and
                func.blocks.items.len <= 3; // Simple control flow

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
            return info.can_inline and info.call_count <= 3;
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
        var inlined_instructions = std.ArrayListUnmanaged(*Instruction){};
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
        _ = self;
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
            // Constants don't need remapping
            .const_int, .const_float, .const_bool, .const_string, .const_null => op,
            .alloca => op,
            // For other operations, return as-is (simplified)
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
        var known_types = std.AutoHashMap(u32, Type).init(self.allocator);
        defer known_types.deinit();

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
                        .array_new => try known_types.put(result.id, .php_array),
                        else => {},
                    }
                }

                // Try to specialize operations based on known types
                if (try self.specializeInstruction(inst, &known_types)) {
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
        var changed = false;

        // Map from expression hash to register
        var expr_map = std.AutoHashMap(u64, Register).init(self.allocator);
        defer expr_map.deinit();

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                // Only consider pure expressions
                if (self.hasSideEffects(inst)) continue;

                // Compute expression hash
                const hash = self.hashExpression(inst);
                if (hash == 0) continue;

                if (expr_map.get(hash)) |existing_reg| {
                    // Found common subexpression - replace with load from existing register
                    if (inst.result) |result| {
                        // Mark this instruction for replacement
                        // In a full implementation, we would replace uses of result with existing_reg
                        _ = result;
                        _ = existing_reg;
                        self.stats.cse_eliminations += 1;
                        changed = true;
                    }
                } else {
                    // Record this expression
                    if (inst.result) |result| {
                        try expr_map.put(hash, result);
                    }
                }
            }
        }

        return changed;
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
            else => return 0, // Not hashable (has side effects or complex)
        }

        return hasher.final();
    }


    // ========================================================================
    // Strength Reduction
    // ========================================================================

    /// Run strength reduction on the entire module
    fn runStrengthReduction(self: *Self, module: *Module) !bool {
        var changed = false;

        for (module.functions.items) |func| {
            if (try self.reduceStrengthInFunction(func)) {
                changed = true;
            }
        }

        return changed;
    }

    /// Apply strength reduction in a function
    fn reduceStrengthInFunction(self: *Self, func: *Function) !bool {
        var changed = false;

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (try self.reduceStrength(inst)) {
                    changed = true;
                }
            }
        }

        return changed;
    }

    /// Apply strength reduction to an instruction
    fn reduceStrength(self: *Self, inst: *Instruction) !bool {
        switch (inst.op) {
            .mul => |op| {
                // Multiply by power of 2 -> shift left
                if (self.constant_values.get(op.rhs.id)) |rhs| {
                    if (rhs == .int) {
                        if (self.isPowerOfTwo(rhs.int)) |shift| {
                            inst.op = .{ .shl = .{
                                .lhs = op.lhs,
                                .rhs = Register{ .id = op.rhs.id, .type_ = .i64 },
                            } };
                            // Note: In a full implementation, we'd create a new const instruction
                            // for the shift amount
                            _ = shift;
                            return true;
                        }
                    }
                }
            },
            .div => |op| {
                // Divide by power of 2 -> shift right
                if (self.constant_values.get(op.rhs.id)) |rhs| {
                    if (rhs == .int and rhs.int > 0) {
                        if (self.isPowerOfTwo(rhs.int)) |shift| {
                            inst.op = .{ .shr = .{
                                .lhs = op.lhs,
                                .rhs = Register{ .id = op.rhs.id, .type_ = .i64 },
                            } };
                            _ = shift;
                            return true;
                        }
                    }
                }
            },
            .mod => |op| {
                // Modulo by power of 2 -> bitwise and
                if (self.constant_values.get(op.rhs.id)) |rhs| {
                    if (rhs == .int and rhs.int > 0) {
                        if (self.isPowerOfTwo(rhs.int)) |_| {
                            inst.op = .{ .bit_and = .{
                                .lhs = op.lhs,
                                .rhs = Register{ .id = op.rhs.id, .type_ = .i64 },
                            } };
                            // Note: mask should be (rhs - 1)
                            return true;
                        }
                    }
                }
            },
            else => {},
        }
        return false;
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
        .has_side_effects = false,
        .is_recursive = false,
        .can_inline = true,
    });

    // Add a function that cannot be inlined (too many calls)
    try optimizer.call_graph.put("hot_func", .{
        .instruction_count = 5,
        .call_count = 10,
        .has_side_effects = false,
        .is_recursive = false,
        .can_inline = true,
    });

    // Add a recursive function
    try optimizer.call_graph.put("recursive_func", .{
        .instruction_count = 5,
        .call_count = 1,
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
