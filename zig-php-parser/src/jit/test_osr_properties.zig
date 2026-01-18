const std = @import("std");
const osr = @import("osr.zig");
const FrameSnapshot = osr.FrameSnapshot;
const OSRManager = osr.OSRManager;
const StackCapture = osr.StackCapture;
const OSRTransition = osr.OSRTransition;

/// 属性测试框架
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    prng: std.Random.DefaultPrng,
    iterations: u32,
    
    fn init(allocator: std.mem.Allocator, seed: u64, iterations: u32) PropertyTest {
        return .{
            .allocator = allocator,
            .prng = std.Random.DefaultPrng.init(seed),
            .iterations = iterations,
        };
    }
    
    fn run(
        self: *PropertyTest,
        comptime T: type,
        property: fn (T) anyerror!bool,
        generator: fn (std.Random, std.mem.Allocator) anyerror!T,
        cleanup: ?fn (T, std.mem.Allocator) void,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const input = try generator(self.prng.random(), self.allocator);
            defer if (cleanup) |clean_fn| clean_fn(input, self.allocator);
            
            if (try property(input)) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed at iteration {d}\n", .{i});
            }
        }
        
        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("Property test: {d}/{d} passed ({d:.2}%)\n", 
            .{passed, self.iterations, success_rate * 100.0});
        
        return failed == 0;
    }
};

/// 测试输入：随机栈帧状态
const TestInput = struct {
    pc: u32,
    sp: u32,
    locals: []i64,
    stack: []i64,
    
    fn deinit(self: TestInput, allocator: std.mem.Allocator) void {
        allocator.free(self.locals);
        allocator.free(self.stack);
    }
};

/// 生成随机测试输入
fn generateTestInput(rng: std.Random, allocator: std.mem.Allocator) !TestInput {
    const pc = rng.int(u32);
    const local_count = rng.intRangeAtMost(usize, 1, 50);
    const stack_depth = rng.intRangeAtMost(usize, 1, 50);
    const sp = rng.intRangeAtMost(u32, 0, @intCast(stack_depth));
    
    const locals = try allocator.alloc(i64, local_count);
    for (locals) |*val| {
        val.* = rng.intRangeAtMost(i64, -1000, 1000);
    }
    
    const stack = try allocator.alloc(i64, stack_depth);
    for (stack) |*val| {
        val.* = rng.intRangeAtMost(i64, -1000, 1000);
    }
    
    return TestInput{
        .pc = pc,
        .sp = sp,
        .locals = locals,
        .stack = stack,
    };
}

// ============================================================================
// 属性 13：OSR 语义保持
// Feature: zig-php-performance-optimization, Property 13
// ============================================================================

// 属性 13：OSR 语义保持
// 
// 对于任意热循环，从解释执行切换到 JIT 代码后，循环的执行结果应该保持不变
// 
// 验证：需求 2.6
test "Property 13: OSR semantic preservation" {
    const allocator = std.testing.allocator;
    
    var pt = PropertyTest.init(allocator, 12345, 100);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            // 1. 捕获栈帧状态
            const snapshot = try StackCapture.captureFrame(
                input.pc,
                input.sp,
                input.locals,
                input.stack,
            );
            
            // 2. 验证快照完整性
            if (!StackCapture.validateSnapshot(&snapshot)) {
                return false;
            }
            
            // 3. 模拟解释执行结果
            const interpreted_result = computeInterpreted(&snapshot);
            
            // 4. 创建 OSR 管理器
            const manager = try OSRManager.init(std.testing.allocator);
            defer manager.deinit();
            
            // 5. 注册 JIT 代码（模拟相同的计算）
            const mock_jit = struct {
                fn execute(snap: *const FrameSnapshot) callconv(.c) i64 {
                    return computeJIT(snap);
                }
            }.execute;
            
            try manager.registerEntry(1, snapshot.pc, mock_jit);
            
            // 6. 执行 OSR 转换
            const entry = manager.findEntry(1, snapshot.pc) orelse return false;
            const jit_result = try OSRTransition.transitionToJIT(
                entry,
                &snapshot,
                &manager.stats,
            );
            
            // 7. 验证结果相同
            return interpreted_result == jit_result;
        }
        
        /// 模拟解释执行
        fn computeInterpreted(snapshot: *const FrameSnapshot) i64 {
            var sum: i64 = 0;
            
            // 累加局部变量
            for (snapshot.locals[0..snapshot.local_count]) |val| {
                sum +%= val;
            }
            
            // 累加栈元素
            for (snapshot.stack[0..snapshot.stack_depth]) |val| {
                sum +%= val;
            }
            
            return sum;
        }
        
        /// 模拟 JIT 执行（应该产生相同结果）
        fn computeJIT(snapshot: *const FrameSnapshot) i64 {
            var sum: i64 = 0;
            
            // 累加局部变量
            for (snapshot.locals[0..snapshot.local_count]) |val| {
                sum +%= val;
            }
            
            // 累加栈元素
            for (snapshot.stack[0..snapshot.stack_depth]) |val| {
                sum +%= val;
            }
            
            return sum;
        }
    }.check;
    
    const passed = try pt.run(
        TestInput,
        property,
        generateTestInput,
        TestInput.deinit,
    );
    
    try std.testing.expect(passed);
}

// 属性 13.1：栈状态捕获完整性
// 
// 对于任意栈帧状态，捕获后的快照应该包含所有必要信息
test "Property 13.1: Stack capture completeness" {
    const allocator = std.testing.allocator;
    
    var pt = PropertyTest.init(allocator, 54321, 100);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            // 捕获栈帧
            const snapshot = try StackCapture.captureFrame(
                input.pc,
                input.sp,
                input.locals,
                input.stack,
            );
            
            // 验证 PC
            if (snapshot.pc != input.pc) return false;
            
            // 验证 SP
            if (snapshot.sp != input.sp) return false;
            
            // 验证局部变量数量
            if (snapshot.local_count != input.locals.len) return false;
            
            // 验证栈深度
            if (snapshot.stack_depth != input.stack.len) return false;
            
            // 验证局部变量值
            for (input.locals, 0..) |val, i| {
                if (snapshot.locals[i] != val) return false;
            }
            
            // 验证栈值
            for (input.stack, 0..) |val, i| {
                if (snapshot.stack[i] != val) return false;
            }
            
            return true;
        }
    }.check;
    
    const passed = try pt.run(
        TestInput,
        property,
        generateTestInput,
        TestInput.deinit,
    );
    
    try std.testing.expect(passed);
}

// 属性 13.2：OSR 转换幂等性
// 
// 对于任意有效的 OSR 入口点，多次转换应该产生相同结果
test "Property 13.2: OSR transition idempotence" {
    const allocator = std.testing.allocator;
    
    var pt = PropertyTest.init(allocator, 98765, 100);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            const snapshot = try StackCapture.captureFrame(
                input.pc,
                input.sp,
                input.locals,
                input.stack,
            );
            
            if (!StackCapture.validateSnapshot(&snapshot)) {
                return true; // 跳过无效快照
            }
            
            const manager = try OSRManager.init(std.testing.allocator);
            defer manager.deinit();
            
            // 注册确定性的 JIT 代码
            const mock_jit = struct {
                fn execute(snap: *const FrameSnapshot) callconv(.c) i64 {
                    var sum: i64 = 0;
                    for (snap.locals[0..snap.local_count]) |val| {
                        sum +%= val;
                    }
                    return sum;
                }
            }.execute;
            
            try manager.registerEntry(1, snapshot.pc, mock_jit);
            const entry = manager.findEntry(1, snapshot.pc) orelse return false;
            
            // 执行多次转换
            const result1 = try OSRTransition.transitionToJIT(entry, &snapshot, &manager.stats);
            const result2 = try OSRTransition.transitionToJIT(entry, &snapshot, &manager.stats);
            const result3 = try OSRTransition.transitionToJIT(entry, &snapshot, &manager.stats);
            
            // 所有结果应该相同
            return result1 == result2 and result2 == result3;
        }
    }.check;
    
    const passed = try pt.run(
        TestInput,
        property,
        generateTestInput,
        TestInput.deinit,
    );
    
    try std.testing.expect(passed);
}

// 属性 13.3：OSR 回退安全性
// 
// 对于任意无效的 OSR 转换，系统应该能够安全回退到解释执行
test "Property 13.3: OSR fallback safety" {
    const allocator = std.testing.allocator;
    
    var pt = PropertyTest.init(allocator, 11111, 100);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            const snapshot = try StackCapture.captureFrame(
                input.pc,
                input.sp,
                input.locals,
                input.stack,
            );
            
            const manager = try OSRManager.init(std.testing.allocator);
            defer manager.deinit();
            
            // 测试有效快照的回退
            if (StackCapture.validateSnapshot(&snapshot)) {
                const can_fallback = OSRTransition.fallbackToInterpreter(
                    &snapshot,
                    &manager.stats,
                );
                if (!can_fallback) return false;
            }
            
            // 测试无效快照的回退
            var invalid_snapshot = snapshot;
            invalid_snapshot.sp = 300; // 使其无效
            
            const cannot_fallback = OSRTransition.fallbackToInterpreter(
                &invalid_snapshot,
                &manager.stats,
            );
            
            // 无效快照应该无法回退
            return !cannot_fallback;
        }
    }.check;
    
    const passed = try pt.run(
        TestInput,
        property,
        generateTestInput,
        TestInput.deinit,
    );
    
    try std.testing.expect(passed);
}

// 属性 13.4：OSR 入口点缓存一致性
// 
// 对于任意 OSR 入口点，注册后应该能够正确查找和失效
test "Property 13.4: OSR entry cache consistency" {
    const allocator = std.testing.allocator;
    
    var pt = PropertyTest.init(allocator, 22222, 100);
    
    const TestCase = struct {
        function_id: u32,
        bytecode_offset: u32,
    };
    
    const generator = struct {
        fn gen(rng: std.Random, alloc: std.mem.Allocator) !TestCase {
            _ = alloc;
            return TestCase{
                .function_id = rng.int(u32),
                .bytecode_offset = rng.int(u32),
            };
        }
    }.gen;
    
    const property = struct {
        fn check(input: TestCase) !bool {
            const manager = try OSRManager.init(std.testing.allocator);
            defer manager.deinit();
            
            const mock_jit = struct {
                fn execute(_: *const FrameSnapshot) callconv(.c) i64 {
                    return 0;
                }
            }.execute;
            
            // 注册入口点
            try manager.registerEntry(
                input.function_id,
                input.bytecode_offset,
                mock_jit,
            );
            
            // 应该能够查找到
            const entry1 = manager.findEntry(input.function_id, input.bytecode_offset);
            if (entry1 == null) return false;
            if (!entry1.?.valid) return false;
            
            // 使其失效
            manager.invalidateEntry(input.function_id, input.bytecode_offset);
            
            // 应该无法查找到有效入口点
            const entry2 = manager.findEntry(input.function_id, input.bytecode_offset);
            if (entry2 != null) return false;
            
            return true;
        }
    }.check;
    
    const cleanup = struct {
        fn clean(_: TestCase, _: std.mem.Allocator) void {}
    }.clean;
    
    const passed = try pt.run(
        TestCase,
        property,
        generator,
        cleanup,
    );
    
    try std.testing.expect(passed);
}

// 属性 13.5：OSR 状态转换原子性
// 
// 对于任意 OSR 转换，要么完全成功，要么完全失败，不存在中间状态
test "Property 13.5: OSR transition atomicity" {
    const allocator = std.testing.allocator;
    
    var pt = PropertyTest.init(allocator, 33333, 100);
    
    const property = struct {
        fn check(input: TestInput) !bool {
            const snapshot = try StackCapture.captureFrame(
                input.pc,
                input.sp,
                input.locals,
                input.stack,
            );
            
            const manager = try OSRManager.init(std.testing.allocator);
            defer manager.deinit();
            
            const mock_jit = struct {
                fn execute(snap: *const FrameSnapshot) callconv(.c) i64 {
                    return snap.pc;
                }
            }.execute;
            
            try manager.registerEntry(1, snapshot.pc, mock_jit);
            const entry = manager.findEntry(1, snapshot.pc) orelse return false;
            
            const initial_success = manager.stats.successful_transitions;
            const initial_failed = manager.stats.failed_transitions;
            
            // 尝试转换
            const result = OSRTransition.transitionToJIT(entry, &snapshot, &manager.stats);
            
            // 检查统计信息的原子性
            const final_success = manager.stats.successful_transitions;
            const final_failed = manager.stats.failed_transitions;
            
            if (result) |_| {
                // 成功：只有 successful_transitions 增加
                return final_success == initial_success + 1 and
                       final_failed == initial_failed;
            } else |_| {
                // 失败：只有 failed_transitions 增加
                return final_success == initial_success and
                       final_failed == initial_failed + 1;
            }
        }
    }.check;
    
    const passed = try pt.run(
        TestInput,
        property,
        generateTestInput,
        TestInput.deinit,
    );
    
    try std.testing.expect(passed);
}
