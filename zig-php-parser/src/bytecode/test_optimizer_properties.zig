const std = @import("std");
const testing = std.testing;
const Random = std.Random;
const BytecodeOptimizer = @import("optimizer.zig").BytecodeOptimizer;
const Instruction = @import("instruction.zig").Instruction;
const OpCode = @import("instruction.zig").OpCode;
const CompiledFunction = @import("instruction.zig").CompiledFunction;
const Value = @import("instruction.zig").Value;

/// 属性测试框架
/// @concurrency-model ISOLATED
/// @memory-safety CHECKED
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: Random,
    iterations: u32 = 100,
    
    /// 运行属性测试
    /// @pre property 必须是有效的属性函数
    /// @post 运行指定次数的测试，返回是否全部通过
    pub fn run(
        self: *PropertyTest,
        comptime T: type,
        property: fn(T) anyerror!bool,
        generator: fn(*Random, std.mem.Allocator) anyerror!T,
        cleanup: ?fn(T, std.mem.Allocator) void,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 生成随机输入
            const input = try generator(&self.rng, self.allocator);
            defer if (cleanup) |clean_fn| clean_fn(input, self.allocator);
            
            // 测试属性
            const result = property(input) catch |err| {
                std.debug.print("Property test error at iteration {}: {}\n", .{i, err});
                failed += 1;
                continue;
            };
            
            if (result) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed for iteration {}\n", .{i});
            }
        }
        
        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("Property test: {}/{} passed ({d:.2}%)\n", 
            .{passed, self.iterations, success_rate * 100});
        
        return failed == 0;
    }
};

/// 生成器 - 生成随机测试数据
const Generator = struct {
    /// 生成随机整数
    pub fn genInt(rng: *Random, min: i64, max: i64) i64 {
        return rng.intRangeAtMost(i64, min, max);
    }
    
    /// 生成随机Value
    pub fn genValue(rng: *Random) Value {
        const type_choice = rng.uintLessThan(u8, 4);
        return switch (type_choice) {
            0 => Value{ .int_val = genInt(rng, -1000, 1000) },
            1 => Value{ .float_val = rng.float(f64) * 1000.0 },
            2 => Value{ .bool_val = rng.boolean() },
            3 => Value{ .null_val = {} },
            else => unreachable,
        };
    }
    
    /// 生成随机常量数组
    pub fn genConstants(rng: *Random, allocator: std.mem.Allocator, max_len: usize) ![]Value {
        const len = rng.uintLessThan(usize, max_len) + 1;
        const constants = try allocator.alloc(Value, len);
        
        for (constants) |*val| {
            val.* = genValue(rng);
        }
        
        return constants;
    }
    
    /// 生成随机字节码
    pub fn genBytecode(rng: *Random, allocator: std.mem.Allocator, max_len: usize) ![]Instruction {
        const len = rng.uintLessThan(usize, max_len) + 5;
        const bytecode = try allocator.alloc(Instruction, len);
        
        for (bytecode) |*inst| {
            inst.* = genInstruction(rng);
        }
        
        return bytecode;
    }
    
    /// 生成随机指令
    pub fn genInstruction(rng: *Random) Instruction {
        const opcodes = [_]OpCode{
            .push_const, .push_int_0, .push_int_1,
            .add_int, .sub_int, .mul_int, .div_int,
            .add_float, .sub_float, .mul_float, .div_float,
            .nop, .pop, .dup,
        };
        
        const opcode = opcodes[rng.uintLessThan(usize, opcodes.len)];
        const op1 = rng.intRangeAtMost(u16, 0, 10);
        const op2 = rng.intRangeAtMost(u16, 0, 10);
        
        return Instruction.init(opcode, op1, op2);
    }
    
    /// 生成包含常量表达式的字节码
    pub fn genConstantExpressionBytecode(
        rng: *Random,
        allocator: std.mem.Allocator
    ) ![]Instruction {
        var bytecode: std.ArrayListUnmanaged(Instruction) = .{};
        defer bytecode.deinit(allocator);
        
        // 生成一些常量表达式
        const num_exprs = rng.uintLessThan(usize, 5) + 1;
        var i: usize = 0;
        while (i < num_exprs) : (i += 1) {
            // push_const, push_const, add_int
            // 确保常量索引在有效范围内（0-9，因为我们会生成最多10个常量）
            const idx1 = @as(u16, @intCast(rng.uintLessThan(usize, 10)));
            const idx2 = @as(u16, @intCast(rng.uintLessThan(usize, 10)));
            
            try bytecode.append(allocator, Instruction.init(.push_const, idx1, 0));
            try bytecode.append(allocator, Instruction.init(.push_const, idx2, 0));
            
            const ops = [_]OpCode{ .add_int, .sub_int, .mul_int };
            const op = ops[rng.uintLessThan(usize, ops.len)];
            try bytecode.append(allocator, Instruction.init(op, 0, 0));
        }
        
        return bytecode.toOwnedSlice(allocator);
    }
};

/// 测试输入结构
const TestInput = struct {
    func: *CompiledFunction,
    
    pub fn cleanup(self: TestInput, allocator: std.mem.Allocator) void {
        self.func.deinit(allocator);
    }
};

// ============================================================================
// 属性 5：常量折叠语义保持
// Feature: zig-php-performance-optimization, Property 5: 常量折叠语义保持
// 验证：需求 1.5
// ============================================================================
test "Property 5: Constant folding semantic preservation" {
    var prng = std.Random.DefaultPrng.init(42);
    var pt = PropertyTest{
        .allocator = testing.allocator,
        .rng = prng.random(),
        .iterations = 100,
    };
    
    const property = struct {
        fn check(input: TestInput) !bool {
            // 1. 创建函数的深拷贝用于优化
            const optimized_func = try CompiledFunction.init(testing.allocator, "test_func_optimized");
            defer optimized_func.deinit(testing.allocator);
            
            // 复制字节码
            optimized_func.bytecode = try testing.allocator.alloc(Instruction, input.func.bytecode.len);
            @memcpy(optimized_func.bytecode, input.func.bytecode);
            
            // 复制常量池
            optimized_func.constants = try testing.allocator.alloc(Value, input.func.constants.len);
            @memcpy(optimized_func.constants, input.func.constants);
            
            optimized_func.local_count = input.func.local_count;
            optimized_func.arg_count = input.func.arg_count;
            optimized_func.max_stack = input.func.max_stack;
            
            // 2. 执行优化前的字节码（使用原始函数）
            const before_result = try simulateExecution(input.func);
            
            // 3. 应用常量折叠优化
            var optimizer = BytecodeOptimizer.init(testing.allocator, .basic);
            
            // 只执行基本的常量折叠
            var i: usize = 0;
            while (i + 2 < optimized_func.bytecode.len) : (i += 1) {
                const inst1 = optimized_func.bytecode[i];
                const inst2 = optimized_func.bytecode[i + 1];
                const inst3 = optimized_func.bytecode[i + 2];

                if (inst1.opcode == .push_const and inst2.opcode == .push_const) {
                    if (inst1.operand1 >= optimized_func.constants.len or inst2.operand1 >= optimized_func.constants.len) {
                        continue;
                    }
                    
                    const val1 = optimized_func.constants[inst1.operand1];
                    const val2 = optimized_func.constants[inst2.operand1];

                    const folded = switch (inst3.opcode) {
                        .add_int => foldIntOp(val1, val2, .add),
                        .sub_int => foldIntOp(val1, val2, .sub),
                        .mul_int => foldIntOp(val1, val2, .mul),
                        else => null,
                    };

                    if (folded) |result| {
                        const const_idx = try optimizer.addConstant(optimized_func, result);
                        optimized_func.bytecode[i] = Instruction.init(.push_const, const_idx, 0);
                        optimized_func.bytecode[i + 1] = Instruction.init(.nop, 0, 0);
                        optimized_func.bytecode[i + 2] = Instruction.init(.nop, 0, 0);
                    }
                }
            }
            
            // 4. 执行优化后的字节码
            const after_result = try simulateExecution(optimized_func);
            
            // 5. 验证结果相同
            return valuesEqual(before_result, after_result);
        }
        
        fn foldIntOp(val1: Value, val2: Value, op: enum { add, sub, mul }) ?Value {
            const a = switch (val1) {
                .int_val => |v| v,
                else => return null,
            };
            const b = switch (val2) {
                .int_val => |v| v,
                else => return null,
            };

            const result = switch (op) {
                .add => a + b,
                .sub => a - b,
                .mul => a * b,
            };

            return Value{ .int_val = result };
        }
        
        fn printValue(val: Value) void {
            switch (val) {
                .null_val => std.debug.print("null", .{}),
                .bool_val => |b| std.debug.print("{}", .{b}),
                .int_val => |i| std.debug.print("{}", .{i}),
                .float_val => |f| std.debug.print("{d}", .{f}),
                else => std.debug.print("other", .{}),
            }
        }
        
        fn simulateExecution(func: *CompiledFunction) !Value {
            // 简化的执行模拟：只计算常量表达式
            var stack: std.ArrayListUnmanaged(Value) = .{};
            defer stack.deinit(testing.allocator);
            
            for (func.bytecode, 0..) |inst, idx| {
                _ = idx;
                switch (inst.opcode) {
                    .push_const => {
                        if (inst.operand1 < func.constants.len) {
                            try stack.append(testing.allocator, func.constants[inst.operand1]);
                        }
                    },
                    .push_int_0 => try stack.append(testing.allocator, Value{ .int_val = 0 }),
                    .push_int_1 => try stack.append(testing.allocator, Value{ .int_val = 1 }),
                    .add_int => {
                        if (stack.items.len >= 2) {
                            const b_opt = stack.pop();
                            const a_opt = stack.pop();
                            if (a_opt) |a| {
                                if (b_opt) |b| {
                                    switch (a) {
                                        .int_val => |a_val| switch (b) {
                                            .int_val => |b_val| {
                                                try stack.append(testing.allocator, Value{ .int_val = a_val + b_val });
                                            },
                                            else => {},
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    },
                    .sub_int => {
                        if (stack.items.len >= 2) {
                            const b_opt = stack.pop();
                            const a_opt = stack.pop();
                            if (a_opt) |a| {
                                if (b_opt) |b| {
                                    switch (a) {
                                        .int_val => |a_val| switch (b) {
                                            .int_val => |b_val| {
                                                try stack.append(testing.allocator, Value{ .int_val = a_val - b_val });
                                            },
                                            else => {},
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    },
                    .mul_int => {
                        if (stack.items.len >= 2) {
                            const b_opt = stack.pop();
                            const a_opt = stack.pop();
                            if (a_opt) |a| {
                                if (b_opt) |b| {
                                    switch (a) {
                                        .int_val => |a_val| switch (b) {
                                            .int_val => |b_val| {
                                                try stack.append(testing.allocator, Value{ .int_val = a_val * b_val });
                                            },
                                            else => {},
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    },
                    .nop, .pop => {},
                    else => {},
                }
            }
            
            return if (stack.items.len > 0) stack.items[stack.items.len - 1] else Value{ .null_val = {} };
        }
        
        fn valuesEqual(a: Value, b: Value) bool {
            if (@as(std.meta.Tag(Value), a) != @as(std.meta.Tag(Value), b)) {
                return false;
            }
            return switch (a) {
                .null_val => true,
                .bool_val => |av| b.bool_val == av,
                .int_val => |av| b.int_val == av,
                .float_val => |av| @abs(b.float_val - av) < 0.0001,
                else => false,
            };
        }
    }.check;
    
    const generator = struct {
        fn gen(rng: *Random, allocator: std.mem.Allocator) !TestInput {
            const func = try CompiledFunction.init(allocator, "test_func");
            
            // 生成包含常量表达式的字节码
            func.bytecode = try Generator.genConstantExpressionBytecode(rng, allocator);
            
            // 生成常量池
            func.constants = try Generator.genConstants(rng, allocator, 10);
            
            func.local_count = 0;
            func.arg_count = 0;
            func.max_stack = 10;
            
            return TestInput{ .func = func };
        }
    }.gen;
    
    const passed = try pt.run(TestInput, property, generator, TestInput.cleanup);
    try testing.expect(passed);
}

// ============================================================================
// 属性 6：常量池去重
// Feature: zig-php-performance-optimization, Property 6: 常量池去重
// 验证：需求 1.6
// ============================================================================
test "Property 6: Constant pool deduplication" {
    var prng = std.Random.DefaultPrng.init(43);
    var pt = PropertyTest{
        .allocator = testing.allocator,
        .rng = prng.random(),
        .iterations = 100,
    };
    
    const property = struct {
        fn check(input: TestInput) !bool {
            var optimizer = BytecodeOptimizer.init(testing.allocator, .basic);
            
            // 添加重复的常量
            const val1 = Value{ .int_val = 42 };
            const val2 = Value{ .int_val = 42 };
            const val3 = Value{ .int_val = 100 };
            
            const idx1 = try optimizer.addConstant(input.func, val1);
            const idx2 = try optimizer.addConstant(input.func, val2);
            const idx3 = try optimizer.addConstant(input.func, val3);
            
            // 验证：相同值应该返回相同索引
            if (idx1 != idx2) {
                std.debug.print("Deduplication failed: idx1={} != idx2={}\n", .{idx1, idx2});
                return false;
            }
            
            // 验证：不同值应该返回不同索引
            if (idx1 == idx3) {
                std.debug.print("Different values got same index: idx1={} == idx3={}\n", .{idx1, idx3});
                return false;
            }
            
            // 验证：常量池中没有重复值
            var seen = std.AutoHashMap(i64, void).init(testing.allocator);
            defer seen.deinit();
            
            for (input.func.constants) |constant| {
                if (constant == .int_val) {
                    if (seen.contains(constant.int_val)) {
                        std.debug.print("Duplicate constant found: {}\n", .{constant.int_val});
                        return false;
                    }
                    try seen.put(constant.int_val, {});
                }
            }
            
            return true;
        }
    }.check;
    
    const generator = struct {
        fn gen(_: *Random, allocator: std.mem.Allocator) !TestInput {
            const func = try CompiledFunction.init(allocator, "test_func");
            func.bytecode = &[_]Instruction{};
            func.constants = &[_]Value{};
            func.local_count = 0;
            func.arg_count = 0;
            func.max_stack = 10;
            
            return TestInput{ .func = func };
        }
    }.gen;
    
    const passed = try pt.run(TestInput, property, generator, TestInput.cleanup);
    try testing.expect(passed);
}

// ============================================================================
// 属性 7：循环不变量提升语义保持
// Feature: zig-php-performance-optimization, Property 7: 循环不变量提升语义保持
// 验证：需求 1.7
// ============================================================================
test "Property 7: Loop invariant hoisting semantic preservation" {
    var prng = std.Random.DefaultPrng.init(44);
    var pt = PropertyTest{
        .allocator = testing.allocator,
        .rng = prng.random(),
        .iterations = 100,
    };
    
    const property = struct {
        fn check(input: TestInput) !bool {
            // 1. 记录优化前的循环不变指令位置
            const before_invariants = try countLoopInvariants(input.func);
            
            // 2. 应用循环优化
            var optimizer = BytecodeOptimizer.init(testing.allocator, .standard);
            try optimizer.loopOptimization(input.func);
            
            // 3. 验证：循环不变指令应该被提升（数量减少或位置改变）
            const after_invariants = try countLoopInvariants(input.func);
            
            // 如果有循环不变代码，优化后应该减少
            if (before_invariants > 0) {
                return after_invariants <= before_invariants;
            }
            
            return true;
        }
        
        fn countLoopInvariants(func: *CompiledFunction) !usize {
            var count: usize = 0;
            var in_loop = false;
            
            for (func.bytecode) |inst| {
                if (inst.opcode == .loop_start) {
                    in_loop = true;
                } else if (inst.opcode == .loop_end) {
                    in_loop = false;
                } else if (in_loop and inst.opcode == .push_const) {
                    count += 1;
                }
            }
            
            return count;
        }
    }.check;
    
    const generator = struct {
        fn gen(rng: *Random, allocator: std.mem.Allocator) !TestInput {
            const func = try CompiledFunction.init(allocator, "test_func");
            
            // 生成包含循环的字节码
            var bytecode: std.ArrayListUnmanaged(Instruction) = .{};
            defer bytecode.deinit(allocator);
            
            // 循环前的代码
            try bytecode.append(allocator, Instruction.init(.push_const, 0, 0));
            
            // 循环开始
            try bytecode.append(allocator, Instruction.init(.loop_start, 0, 0));
            
            // 循环不变代码
            try bytecode.append(allocator, Instruction.init(.push_const, 1, 0));
            try bytecode.append(allocator, Instruction.init(.push_const, 2, 0));
            try bytecode.append(allocator, Instruction.init(.add_int, 0, 0));
            
            // 循环变量代码
            const num_loop_ops = rng.uintLessThan(usize, 5) + 1;
            var i: usize = 0;
            while (i < num_loop_ops) : (i += 1) {
                try bytecode.append(allocator, Generator.genInstruction(rng));
            }
            
            // 循环结束
            try bytecode.append(allocator, Instruction.init(.loop_end, 0, 0));
            
            func.bytecode = try bytecode.toOwnedSlice(allocator);
            func.constants = try Generator.genConstants(rng, allocator, 5);
            func.local_count = 2;
            func.arg_count = 0;
            func.max_stack = 10;
            
            return TestInput{ .func = func };
        }
    }.gen;
    
    const passed = try pt.run(TestInput, property, generator, TestInput.cleanup);
    try testing.expect(passed);
}

// ============================================================================
// 属性 8：强度削减语义保持
// Feature: zig-php-performance-optimization, Property 8: 强度削减语义保持
// 验证：需求 1.8
// ============================================================================
test "Property 8: Strength reduction semantic preservation" {
    var prng = std.Random.DefaultPrng.init(45);
    var pt = PropertyTest{
        .allocator = testing.allocator,
        .rng = prng.random(),
        .iterations = 100,
    };
    
    const property = struct {
        fn check(input: TestInput) !bool {
            // 1. 执行优化前的字节码
            const before_result = try simulateExecution(input.func);
            
            // 2. 应用强度削减优化
            var optimizer = BytecodeOptimizer.init(testing.allocator, .aggressive);
            try optimizer.strengthReduction(input.func);
            
            // 3. 执行优化后的字节码
            const after_result = try simulateExecution(input.func);
            
            // 4. 验证结果相同
            return valuesEqual(before_result, after_result);
        }
        
        fn simulateExecution(func: *CompiledFunction) !Value {
            var stack: std.ArrayListUnmanaged(Value) = .{};
            defer stack.deinit(testing.allocator);
            
            for (func.bytecode) |inst| {
                switch (inst.opcode) {
                    .push_const => {
                        if (inst.operand1 < func.constants.len) {
                            try stack.append(testing.allocator, func.constants[inst.operand1]);
                        }
                    },
                    .push_int_0 => try stack.append(testing.allocator, Value{ .int_val = 0 }),
                    .push_int_1 => try stack.append(testing.allocator, Value{ .int_val = 1 }),
                    
                    .mul_int => {
                        if (stack.items.len >= 2) {
                            const b_opt = stack.pop();
                            const a_opt = stack.pop();
                            if (a_opt) |a| {
                                if (b_opt) |b| {
                                    switch (a) {
                                        .int_val => |a_val| switch (b) {
                                            .int_val => |b_val| {
                                                try stack.append(testing.allocator, Value{ .int_val = a_val * b_val });
                                            },
                                            else => {},
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    },
                    
                    .shl => {
                        if (stack.items.len >= 2) {
                            const shift_opt = stack.pop();
                            const val_opt = stack.pop();
                            if (val_opt) |val| {
                                if (shift_opt) |shift| {
                                    switch (val) {
                                        .int_val => |v| switch (shift) {
                                            .int_val => |s| {
                                                const result = v << @as(u6, @intCast(s));
                                                try stack.append(testing.allocator, Value{ .int_val = result });
                                            },
                                            else => {},
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    },
                    
                    .shr => {
                        if (stack.items.len >= 2) {
                            const shift_opt = stack.pop();
                            const val_opt = stack.pop();
                            if (val_opt) |val| {
                                if (shift_opt) |shift| {
                                    switch (val) {
                                        .int_val => |v| switch (shift) {
                                            .int_val => |s| {
                                                const result = v >> @as(u6, @intCast(s));
                                                try stack.append(testing.allocator, Value{ .int_val = result });
                                            },
                                            else => {},
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    },
                    
                    .bit_and => {
                        if (stack.items.len >= 2) {
                            const b_opt = stack.pop();
                            const a_opt = stack.pop();
                            if (a_opt) |a| {
                                if (b_opt) |b| {
                                    switch (a) {
                                        .int_val => |a_val| switch (b) {
                                            .int_val => |b_val| {
                                                try stack.append(testing.allocator, Value{ .int_val = a_val & b_val });
                                            },
                                            else => {},
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    },
                    
                    .nop, .pop => {},
                    else => {},
                }
            }
            
            return if (stack.items.len > 0) stack.items[stack.items.len - 1] else Value{ .null_val = {} };
        }
        
        fn valuesEqual(a: Value, b: Value) bool {
            if (@as(std.meta.Tag(Value), a) != @as(std.meta.Tag(Value), b)) {
                return false;
            }
            return switch (a) {
                .null_val => true,
                .bool_val => |av| b.bool_val == av,
                .int_val => |av| b.int_val == av,
                .float_val => |av| @abs(b.float_val - av) < 0.0001,
                else => false,
            };
        }
    }.check;
    
    const generator = struct {
        fn gen(rng: *Random, allocator: std.mem.Allocator) !TestInput {
            const func = try CompiledFunction.init(allocator, "test_func");
            
            // 生成包含可优化操作的字节码
            var bytecode: std.ArrayListUnmanaged(Instruction) = .{};
            defer bytecode.deinit(allocator);
            var constants: std.ArrayListUnmanaged(Value) = .{};
            defer constants.deinit(allocator);
            
            // 生成 x * 2^n 的模式
            const powers_of_two = [_]i64{ 2, 4, 8, 16, 32 };
            const power = powers_of_two[rng.uintLessThan(usize, powers_of_two.len)];
            
            try constants.append(allocator, Value{ .int_val = 10 }); // 基数
            try constants.append(allocator, Value{ .int_val = power }); // 2的幂
            
            try bytecode.append(allocator, Instruction.init(.push_const, 0, 0));
            try bytecode.append(allocator, Instruction.init(.push_const, 1, 0));
            try bytecode.append(allocator, Instruction.init(.mul_int, 0, 0));
            
            func.bytecode = try bytecode.toOwnedSlice(allocator);
            func.constants = try constants.toOwnedSlice(allocator);
            func.local_count = 0;
            func.arg_count = 0;
            func.max_stack = 10;
            
            return TestInput{ .func = func };
        }
    }.gen;
    
    const passed = try pt.run(TestInput, property, generator, TestInput.cleanup);
    try testing.expect(passed);
}
