//! Property-Based Tests for AOT Optimizer
//!
//! **Feature: zig-php-performance-optimization, Property 20: AOT 优化语义保持**
//! *For any* code, applying dead code elimination, constant propagation, CSE, and function inlining
//! SHALL produce execution results identical to the unoptimized version.
//!
//! **Validates: Requirements 3.6**
//!
//! This test suite validates that all AOT optimization passes preserve program semantics.
//! Each property test runs 100+ iterations with randomly generated IR to ensure correctness.

const std = @import("std");
const testing = std.testing;
const IR = @import("ir.zig");
const Optimizer = @import("optimizer.zig");
const IROptimizer = Optimizer.IROptimizer;
const OptimizeLevel = Optimizer.OptimizeLevel;
const Module = IR.Module;
const Function = IR.Function;
const BasicBlock = IR.BasicBlock;
const Instruction = IR.Instruction;
const Register = IR.Register;
const Type = IR.Type;
const Terminator = IR.Terminator;

// ============================================================================
// Test Configuration
// ============================================================================

const TEST_ITERATIONS = 100;
const MAX_INSTRUCTIONS = 50;
const MAX_BLOCKS = 5;
const MAX_REGISTERS = 20;

// ============================================================================
// Random IR Generator
// ============================================================================

/// Random IR generator for property testing
const IRGenerator = struct {
    allocator: std.mem.Allocator,
    rng: std.Random,
    next_reg_id: u32 = 0,
    next_block_id: u32 = 0,

    fn init(allocator: std.mem.Allocator, seed: u64) IRGenerator {
        var prng = std.Random.DefaultPrng.init(seed);
        return .{
            .allocator = allocator,
            .rng = prng.random(),
        };
    }

    fn nextRegister(self: *IRGenerator, type_: Type) Register {
        const id = self.next_reg_id;
        self.next_reg_id += 1;
        return Register{ .id = id, .type_ = type_ };
    }

    fn generateRandomType(self: *IRGenerator) Type {
        const choice = self.rng.uintLessThan(u8, 5);
        return switch (choice) {
            0 => .i64,
            1 => .f64,
            2 => .bool,
            3 => .php_string,
            4 => .php_value,
            else => unreachable,
        };
    }

    fn generateConstantInstruction(self: *IRGenerator, result: Register) !*Instruction {
        const inst = try self.allocator.create(Instruction);
        const choice = self.rng.uintLessThan(u8, 4);
        
        inst.* = Instruction{
            .result = result,
            .op = switch (choice) {
                0 => .{ .const_int = self.rng.intRangeAtMost(i64, -100, 100) },
                1 => .{ .const_float = self.rng.float(f64) * 100.0 },
                2 => .{ .const_bool = self.rng.boolean() },
                3 => .{ .const_null = {} },
                else => unreachable,
            },
            .location = null,
        };
        return inst;
    }

    fn generateBinaryInstruction(
        self: *IRGenerator,
        result: Register,
        lhs: Register,
        rhs: Register,
    ) !*Instruction {
        const inst = try self.allocator.create(Instruction);
        const choice = self.rng.uintLessThan(u8, 10);
        
        inst.* = Instruction{
            .result = result,
            .op = switch (choice) {
                0 => .{ .add = .{ .lhs = lhs, .rhs = rhs } },
                1 => .{ .sub = .{ .lhs = lhs, .rhs = rhs } },
                2 => .{ .mul = .{ .lhs = lhs, .rhs = rhs } },
                3 => .{ .div = .{ .lhs = lhs, .rhs = rhs } },
                4 => .{ .mod = .{ .lhs = lhs, .rhs = rhs } },
                5 => .{ .eq = .{ .lhs = lhs, .rhs = rhs } },
                6 => .{ .ne = .{ .lhs = lhs, .rhs = rhs } },
                7 => .{ .lt = .{ .lhs = lhs, .rhs = rhs } },
                8 => .{ .and_ = .{ .lhs = lhs, .rhs = rhs } },
                9 => .{ .or_ = .{ .lhs = lhs, .rhs = rhs } },
                else => unreachable,
            },
            .location = null,
        };
        return inst;
    }

    fn generateUnaryInstruction(
        self: *IRGenerator,
        result: Register,
        operand: Register,
    ) !*Instruction {
        const inst = try self.allocator.create(Instruction);
        const choice = self.rng.uintLessThan(u8, 2);
        
        inst.* = Instruction{
            .result = result,
            .op = switch (choice) {
                0 => .{ .neg = .{ .operand = operand } },
                1 => .{ .not = .{ .operand = operand } },
                else => unreachable,
            },
            .location = null,
        };
        return inst;
    }

    fn generateRandomFunction(self: *IRGenerator, name: []const u8) !*Function {
        const func = try self.allocator.create(Function);
        func.* = Function{
            .allocator = self.allocator,
            .name = name,
            .params = .{},
            .return_type = self.generateRandomType(),
            .blocks = .{},
            .is_exported = false,
            .is_method = false,
            .class_name = null,
            .location = .{},
            .next_register_id = 0,
        };

        // Generate 1-3 basic blocks
        const num_blocks = self.rng.intRangeAtMost(usize, 1, @min(MAX_BLOCKS, 3));
        var i: usize = 0;
        while (i < num_blocks) : (i += 1) {
            const block = try self.generateRandomBlock();
            try func.blocks.append(self.allocator, block);
        }

        return func;
    }

    fn generateRandomBlock(self: *IRGenerator) !*BasicBlock {
        const label = try std.fmt.allocPrint(self.allocator, "bb{d}", .{self.next_block_id});
        const block = try self.allocator.create(BasicBlock);
        block.* = BasicBlock.init(self.allocator, label);
        self.next_block_id += 1;

        // Generate 5-15 instructions
        const num_insts = self.rng.intRangeAtMost(usize, 5, @min(MAX_INSTRUCTIONS, 15));
        var registers = std.ArrayList(Register).init(self.allocator);
        defer registers.deinit();

        var i: usize = 0;
        while (i < num_insts) : (i += 1) {
            const result = self.nextRegister(self.generateRandomType());
            
            const inst = if (registers.items.len < 2 or self.rng.boolean())
                try self.generateConstantInstruction(result)
            else if (self.rng.boolean())
                try self.generateUnaryInstruction(
                    result,
                    registers.items[self.rng.uintLessThan(usize, registers.items.len)],
                )
            else
                try self.generateBinaryInstruction(
                    result,
                    registers.items[self.rng.uintLessThan(usize, registers.items.len)],
                    registers.items[self.rng.uintLessThan(usize, registers.items.len)],
                );
            
            try block.instructions.append(self.allocator, inst);
            try registers.append(result);
        }

        // Add return terminator
        const ret_val = if (registers.items.len > 0)
            registers.items[self.rng.uintLessThan(usize, registers.items.len)]
        else
            null;
        block.terminator = .{ .ret = ret_val };

        return block;
    }
};

// ============================================================================
// IR Interpreter (for semantic comparison)
// ============================================================================

/// Simple IR interpreter for comparing optimized vs unoptimized execution
const IRInterpreter = struct {
    allocator: std.mem.Allocator,
    registers: std.AutoHashMap(u32, Value),

    const Value = union(enum) {
        int: i64,
        float: f64,
        bool_val: bool,
        null_val: void,
    };

    fn init(allocator: std.mem.Allocator) IRInterpreter {
        return .{
            .allocator = allocator,
            .registers = std.AutoHashMap(u32, Value).init(allocator),
        };
    }

    fn deinit(self: *IRInterpreter) void {
        self.registers.deinit();
    }

    fn executeFunction(self: *IRInterpreter, func: *const Function) !?Value {
        self.registers.clearRetainingCapacity();

        // Execute entry block
        if (func.blocks.items.len == 0) return null;
        return try self.executeBlock(func.blocks.items[0]);
    }

    fn executeBlock(self: *IRInterpreter, block: *const BasicBlock) !?Value {
        // Execute instructions
        for (block.instructions.items) |inst| {
            try self.executeInstruction(inst);
        }

        // Handle terminator
        if (block.terminator) |term| {
            switch (term) {
                .ret => |ret_val| {
                    if (ret_val) |reg| {
                        return self.registers.get(reg.id);
                    }
                    return null;
                },
                else => return null,
            }
        }

        return null;
    }

    fn executeInstruction(self: *IRInterpreter, inst: *const Instruction) !void {
        const result = inst.result orelse return;

        const value = switch (inst.op) {
            .const_int => |v| Value{ .int = v },
            .const_float => |v| Value{ .float = v },
            .const_bool => |v| Value{ .bool_val = v },
            .const_null => Value{ .null_val = {} },
            
            .add => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .int = 0 };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .int = 0 };
                if (lhs == .int and rhs == .int) {
                    break :blk Value{ .int = lhs.int + rhs.int };
                } else if (lhs == .float and rhs == .float) {
                    break :blk Value{ .float = lhs.float + rhs.float };
                }
                break :blk Value{ .int = 0 };
            },
            
            .sub => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .int = 0 };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .int = 0 };
                if (lhs == .int and rhs == .int) {
                    break :blk Value{ .int = lhs.int - rhs.int };
                } else if (lhs == .float and rhs == .float) {
                    break :blk Value{ .float = lhs.float - rhs.float };
                }
                break :blk Value{ .int = 0 };
            },
            
            .mul => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .int = 0 };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .int = 0 };
                if (lhs == .int and rhs == .int) {
                    break :blk Value{ .int = lhs.int * rhs.int };
                } else if (lhs == .float and rhs == .float) {
                    break :blk Value{ .float = lhs.float * rhs.float };
                }
                break :blk Value{ .int = 0 };
            },
            
            .div => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .int = 0 };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .int = 1 };
                if (lhs == .int and rhs == .int and rhs.int != 0) {
                    break :blk Value{ .int = @divTrunc(lhs.int, rhs.int) };
                } else if (lhs == .float and rhs == .float and rhs.float != 0.0) {
                    break :blk Value{ .float = lhs.float / rhs.float };
                }
                break :blk Value{ .int = 0 };
            },
            
            .mod => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .int = 0 };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .int = 1 };
                if (lhs == .int and rhs == .int and rhs.int != 0) {
                    break :blk Value{ .int = @mod(lhs.int, rhs.int) };
                }
                break :blk Value{ .int = 0 };
            },
            
            .neg => |op| blk: {
                const operand = self.registers.get(op.operand.id) orelse break :blk Value{ .int = 0 };
                if (operand == .int) {
                    break :blk Value{ .int = -operand.int };
                } else if (operand == .float) {
                    break :blk Value{ .float = -operand.float };
                }
                break :blk Value{ .int = 0 };
            },
            
            .not => |op| blk: {
                const operand = self.registers.get(op.operand.id) orelse break :blk Value{ .bool_val = true };
                if (operand == .bool_val) {
                    break :blk Value{ .bool_val = !operand.bool_val };
                }
                break :blk Value{ .bool_val = false };
            },
            
            .eq => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .bool_val = false };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .bool_val = false };
                if (lhs == .int and rhs == .int) {
                    break :blk Value{ .bool_val = lhs.int == rhs.int };
                } else if (lhs == .bool_val and rhs == .bool_val) {
                    break :blk Value{ .bool_val = lhs.bool_val == rhs.bool_val };
                }
                break :blk Value{ .bool_val = false };
            },
            
            .ne => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .bool_val = true };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .bool_val = true };
                if (lhs == .int and rhs == .int) {
                    break :blk Value{ .bool_val = lhs.int != rhs.int };
                }
                break :blk Value{ .bool_val = true };
            },
            
            .lt => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .bool_val = false };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .bool_val = false };
                if (lhs == .int and rhs == .int) {
                    break :blk Value{ .bool_val = lhs.int < rhs.int };
                }
                break :blk Value{ .bool_val = false };
            },
            
            .and_ => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .bool_val = false };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .bool_val = false };
                if (lhs == .bool_val and rhs == .bool_val) {
                    break :blk Value{ .bool_val = lhs.bool_val and rhs.bool_val };
                }
                break :blk Value{ .bool_val = false };
            },
            
            .or_ => |op| blk: {
                const lhs = self.registers.get(op.lhs.id) orelse break :blk Value{ .bool_val = false };
                const rhs = self.registers.get(op.rhs.id) orelse break :blk Value{ .bool_val = false };
                if (lhs == .bool_val and rhs == .bool_val) {
                    break :blk Value{ .bool_val = lhs.bool_val or rhs.bool_val };
                }
                break :blk Value{ .bool_val = false };
            },
            
            else => Value{ .int = 0 },
        };

        try self.registers.put(result.id, value);
    }

    fn valuesEqual(a: ?Value, b: ?Value) bool {
        if (a == null and b == null) return true;
        if (a == null or b == null) return false;
        
        const av = a.?;
        const bv = b.?;
        
        if (@as(std.meta.Tag(Value), av) != @as(std.meta.Tag(Value), bv)) return false;
        
        return switch (av) {
            .int => av.int == bv.int,
            .float => @abs(av.float - bv.float) < 0.0001,
            .bool_val => av.bool_val == bv.bool_val,
            .null_val => true,
        };
    }
};

// ============================================================================
// Property Tests
// ============================================================================

test "Property 20: Dead Code Elimination preserves semantics" {
    // Feature: zig-php-performance-optimization, Property 20
    const allocator = testing.allocator;
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    var i: u32 = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var gen = IRGenerator.init(allocator, i);
        
        // Generate random function
        const func = try gen.generateRandomFunction("test_func");
        defer {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    allocator.destroy(inst);
                }
                block.instructions.deinit();
                block.predecessors.deinit();
                allocator.free(block.label);
                allocator.destroy(block);
            }
            func.blocks.deinit();
            func.params.deinit();
            allocator.destroy(func);
        }
        
        // Execute unoptimized version
        var interp1 = IRInterpreter.init(allocator);
        defer interp1.deinit();
        const result1 = try interp1.executeFunction(func);
        
        // Apply dead code elimination
        var optimizer = IROptimizer.init(allocator, .basic, null);
        defer optimizer.deinit();
        _ = try optimizer.eliminateDeadCodeInFunction(func);
        
        // Execute optimized version
        var interp2 = IRInterpreter.init(allocator);
        defer interp2.deinit();
        const result2 = try interp2.executeFunction(func);
        
        // Compare results
        if (IRInterpreter.valuesEqual(result1, result2)) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("DCE semantic mismatch at iteration {d}\n", .{i});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(TEST_ITERATIONS));
    std.debug.print("Dead Code Elimination: {d}/{d} passed ({d:.2}%)\n", 
        .{passed, TEST_ITERATIONS, success_rate * 100.0});
    
    try testing.expect(failed == 0);
}

test "Property 20: Constant Propagation preserves semantics" {
    // Feature: zig-php-performance-optimization, Property 20
    const allocator = testing.allocator;
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    var i: u32 = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var gen = IRGenerator.init(allocator, i + 1000);
        
        // Generate random function
        const func = try gen.generateRandomFunction("test_func");
        defer {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    allocator.destroy(inst);
                }
                block.instructions.deinit();
                block.predecessors.deinit();
                allocator.free(block.label);
                allocator.destroy(block);
            }
            func.blocks.deinit();
            func.params.deinit();
            allocator.destroy(func);
        }
        
        // Execute unoptimized version
        var interp1 = IRInterpreter.init(allocator);
        defer interp1.deinit();
        const result1 = try interp1.executeFunction(func);
        
        // Apply constant propagation
        var optimizer = IROptimizer.init(allocator, .basic, null);
        defer optimizer.deinit();
        _ = try optimizer.propagateConstantsInFunction(func);
        
        // Execute optimized version
        var interp2 = IRInterpreter.init(allocator);
        defer interp2.deinit();
        const result2 = try interp2.executeFunction(func);
        
        // Compare results
        if (IRInterpreter.valuesEqual(result1, result2)) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("Constant propagation semantic mismatch at iteration {d}\n", .{i});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(TEST_ITERATIONS));
    std.debug.print("Constant Propagation: {d}/{d} passed ({d:.2}%)\n", 
        .{passed, TEST_ITERATIONS, success_rate * 100.0});
    
    try testing.expect(failed == 0);
}

test "Property 20: CSE preserves semantics" {
    // Feature: zig-php-performance-optimization, Property 20
    const allocator = testing.allocator;
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    var i: u32 = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var gen = IRGenerator.init(allocator, i + 2000);
        
        // Generate random function
        const func = try gen.generateRandomFunction("test_func");
        defer {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    allocator.destroy(inst);
                }
                block.instructions.deinit();
                block.predecessors.deinit();
                allocator.free(block.label);
                allocator.destroy(block);
            }
            func.blocks.deinit();
            func.params.deinit();
            allocator.destroy(func);
        }
        
        // Execute unoptimized version
        var interp1 = IRInterpreter.init(allocator);
        defer interp1.deinit();
        const result1 = try interp1.executeFunction(func);
        
        // Apply CSE
        var optimizer = IROptimizer.init(allocator, .basic, null);
        defer optimizer.deinit();
        _ = try optimizer.eliminateCSEInFunction(func);
        
        // Execute optimized version
        var interp2 = IRInterpreter.init(allocator);
        defer interp2.deinit();
        const result2 = try interp2.executeFunction(func);
        
        // Compare results
        if (IRInterpreter.valuesEqual(result1, result2)) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("CSE semantic mismatch at iteration {d}\n", .{i});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(TEST_ITERATIONS));
    std.debug.print("CSE: {d}/{d} passed ({d:.2}%)\n", 
        .{passed, TEST_ITERATIONS, success_rate * 100.0});
    
    try testing.expect(failed == 0);
}

test "Property 20: Combined optimizations preserve semantics" {
    // Feature: zig-php-performance-optimization, Property 20
    const allocator = testing.allocator;
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    var i: u32 = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        var gen = IRGenerator.init(allocator, i + 3000);
        
        // Generate random function
        const func = try gen.generateRandomFunction("test_func");
        defer {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    allocator.destroy(inst);
                }
                block.instructions.deinit();
                block.predecessors.deinit();
                allocator.free(block.label);
                allocator.destroy(block);
            }
            func.blocks.deinit();
            func.params.deinit();
            allocator.destroy(func);
        }
        
        // Execute unoptimized version
        var interp1 = IRInterpreter.init(allocator);
        defer interp1.deinit();
        const result1 = try interp1.executeFunction(func);
        
        // Apply all optimizations
        var optimizer = IROptimizer.init(allocator, .aggressive, null);
        defer optimizer.deinit();
        try optimizer.optimizeFunction(func);
        
        // Execute optimized version
        var interp2 = IRInterpreter.init(allocator);
        defer interp2.deinit();
        const result2 = try interp2.executeFunction(func);
        
        // Compare results
        if (IRInterpreter.valuesEqual(result1, result2)) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("Combined optimization semantic mismatch at iteration {d}\n", .{i});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(TEST_ITERATIONS));
    std.debug.print("Combined Optimizations: {d}/{d} passed ({d:.2}%)\n", 
        .{passed, TEST_ITERATIONS, success_rate * 100.0});
    
    try testing.expect(failed == 0);
}
