/// 类型推断引擎属性测试
/// 
/// Feature: zig-php-performance-optimization
/// Property 10: 类型推断准确性
/// 
/// 验证：需求 2.3
/// 
/// 属性：对于任意具有运行时 profile 的变量，类型推断的准确率应该 > 95%

const std = @import("std");
const TypeInference = @import("type_inference.zig").TypeInference;
const TypeInfo = @import("type_inference.zig").TypeInfo;
const TypeProfile = @import("type_inference.zig").TypeProfile;

/// 属性测试框架
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: std.Random,
    iterations: u32,
    
    pub fn init(allocator: std.mem.Allocator, seed: u64, iterations: u32) PropertyTest {
        var prng = std.Random.DefaultPrng.init(seed);
        return .{
            .allocator = allocator,
            .rng = prng.random(),
            .iterations = iterations,
        };
    }
    
    /// 运行属性测试
    pub fn run(
        self: *PropertyTest,
        comptime T: type,
        property: *const fn(T) bool,
        generator: *const fn(*std.Random, std.mem.Allocator) anyerror!T,
        cleanup: ?*const fn(T, std.mem.Allocator) void,
    ) !TestResult {
        var passed: u32 = 0;
        var failed: u32 = 0;
        var errors: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 生成随机输入
            const input = generator(&self.rng, self.allocator) catch |err| {
                std.debug.print("生成器错误: {}\n", .{err});
                errors += 1;
                continue;
            };
            
            // 测试属性
            const result = property(input);
            
            // 清理
            if (cleanup) |cleanup_fn| {
                cleanup_fn(input, self.allocator);
            }
            
            if (result) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("属性测试失败 (迭代 {d})\n", .{i});
            }
        }
        
        return TestResult{
            .passed = passed,
            .failed = failed,
            .errors = errors,
            .total = self.iterations,
        };
    }
};

const TestResult = struct {
    passed: u32,
    failed: u32,
    errors: u32,
    total: u32,
    
    pub fn successRate(self: TestResult) f32 {
        if (self.total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.passed)) / @as(f32, @floatFromInt(self.total));
    }
    
    pub fn print(self: TestResult, debug_module: anytype) !void {
        _ = debug_module;
        std.debug.print("属性测试结果: {d}/{d} 通过 ({d:.2}%)\n", .{
            self.passed,
            self.total,
            self.successRate() * 100.0,
        });
        if (self.failed > 0) {
            std.debug.print("  失败: {d}\n", .{self.failed});
        }
        if (self.errors > 0) {
            std.debug.print("  错误: {d}\n", .{self.errors});
        }
    }
};

/// 生成器：生成随机类型
fn genRandomType(rng: *std.Random) TypeInfo {
    const type_choice = rng.uintLessThan(u8, 8);
    return switch (type_choice) {
        0 => .int,
        1 => .float,
        2 => .bool,
        3 => .string,
        4 => .array,
        5 => .object,
        6 => .null_type,
        7 => .dynamic,
        else => unreachable,
    };
}

/// 测试输入：单态类型场景
const MonomorphicInput = struct {
    var_name: []const u8,
    type_info: TypeInfo,
    observation_count: u32,
    
    fn cleanup(self: MonomorphicInput, allocator: std.mem.Allocator) void {
        allocator.free(self.var_name);
    }
};

/// 生成器：单态类型场景
fn genMonomorphicInput(rng: *std.Random, allocator: std.mem.Allocator) !MonomorphicInput {
    // 生成变量名
    const name_len = rng.uintLessThan(usize, 10) + 1;
    const var_name = try allocator.alloc(u8, name_len);
    for (var_name) |*c| {
        c.* = rng.intRangeAtMost(u8, 'a', 'z');
    }
    
    // 生成类型和观察次数（确保足够多以满足推断规则）
    const type_info = genRandomType(rng);
    const observation_count = rng.intRangeAtMost(u32, 10, 100);
    
    return MonomorphicInput{
        .var_name = var_name,
        .type_info = type_info,
        .observation_count = observation_count,
    };
}

/// 属性 10.1：单态类型推断准确性
/// 对于任意只观察到单一类型的变量，推断结果应该与观察到的类型一致
fn property_monomorphic_accuracy(input: MonomorphicInput) bool {
    const allocator = std.testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录观察
    var i: u32 = 0;
    while (i < input.observation_count) : (i += 1) {
        inference.recordTypeObservation(input.var_name, input.type_info) catch return false;
    }
    
    // 推断类型
    const inferred = inference.inferType(input.var_name);
    
    // 验证：推断结果应该与观察类型一致
    return inferred == input.type_info;
}

/// 测试输入：多态类型场景
const PolymorphicInput = struct {
    var_name: []const u8,
    primary_type: TypeInfo,
    primary_ratio: f32, // 主要类型的比例 (0.5 - 1.0)
    secondary_type: TypeInfo,
    total_observations: u32,
    
    fn cleanup(self: PolymorphicInput, allocator: std.mem.Allocator) void {
        allocator.free(self.var_name);
    }
};

/// 生成器：多态类型场景
fn genPolymorphicInput(rng: *std.Random, allocator: std.mem.Allocator) !PolymorphicInput {
    // 生成变量名
    const name_len = rng.uintLessThan(usize, 10) + 1;
    const var_name = try allocator.alloc(u8, name_len);
    for (var_name) |*c| {
        c.* = rng.intRangeAtMost(u8, 'a', 'z');
    }
    
    // 生成两种不同的类型
    const primary_type = genRandomType(rng);
    var secondary_type = genRandomType(rng);
    
    // 确保两种类型不同
    while (secondary_type == primary_type) {
        secondary_type = genRandomType(rng);
    }
    
    // 主要类型的比例（50% - 100%）
    const primary_ratio = rng.float(f32) * 0.5 + 0.5;
    
    // 总观察次数
    const total_observations = rng.intRangeAtMost(u32, 20, 100);
    
    return PolymorphicInput{
        .var_name = var_name,
        .primary_type = primary_type,
        .primary_ratio = primary_ratio,
        .secondary_type = secondary_type,
        .total_observations = total_observations,
    };
}

/// 属性 10.2：多态类型推断准确性
/// 对于任意观察到多种类型的变量，如果主要类型占比 >= 95%，推断结果应该是主要类型
fn property_polymorphic_accuracy(input: PolymorphicInput) bool {
    const allocator = std.testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 计算主要类型和次要类型的观察次数
    const primary_count = @as(u32, @intFromFloat(@as(f32, @floatFromInt(input.total_observations)) * input.primary_ratio));
    const secondary_count = input.total_observations - primary_count;
    
    // 记录主要类型观察
    var i: u32 = 0;
    while (i < primary_count) : (i += 1) {
        inference.recordTypeObservation(input.var_name, input.primary_type) catch return false;
    }
    
    // 记录次要类型观察
    i = 0;
    while (i < secondary_count) : (i += 1) {
        inference.recordTypeObservation(input.var_name, input.secondary_type) catch return false;
    }
    
    // 推断类型
    const inferred = inference.inferType(input.var_name);
    
    // 验证：如果主要类型占比 >= 95%，推断结果应该是主要类型
    if (input.primary_ratio >= 0.95) {
        return inferred == input.primary_type;
    } else {
        // 占比不够，可能推断为 dynamic 或主要类型
        return inferred == input.primary_type or inferred == .dynamic;
    }
}

/// 测试输入：批量推断场景
const BatchInferenceInput = struct {
    var_count: usize,
    var_names: [][]const u8,
    var_types: []TypeInfo,
    observation_count: u32,
    
    fn cleanup(self: BatchInferenceInput, allocator: std.mem.Allocator) void {
        for (self.var_names) |name| {
            allocator.free(name);
        }
        allocator.free(self.var_names);
        allocator.free(self.var_types);
    }
};

/// 生成器：批量推断场景
fn genBatchInferenceInput(rng: *std.Random, allocator: std.mem.Allocator) !BatchInferenceInput {
    const var_count = rng.intRangeAtMost(usize, 1, 10);
    
    var var_names = try allocator.alloc([]const u8, var_count);
    errdefer {
        for (var_names[0..var_count]) |name| {
            allocator.free(name);
        }
        allocator.free(var_names);
    }
    
    var var_types = try allocator.alloc(TypeInfo, var_count);
    errdefer allocator.free(var_types);
    
    for (0..var_count) |i| {
        // 生成变量名
        const name_len = rng.uintLessThan(usize, 10) + 1;
        const name = try allocator.alloc(u8, name_len);
        for (name) |*c| {
            c.* = rng.intRangeAtMost(u8, 'a', 'z');
        }
        var_names[i] = name;
        
        // 生成类型
        var_types[i] = genRandomType(rng);
    }
    
    const observation_count = rng.intRangeAtMost(u32, 10, 50);
    
    return BatchInferenceInput{
        .var_count = var_count,
        .var_names = var_names,
        .var_types = var_types,
        .observation_count = observation_count,
    };
}

/// 属性 10.3：批量推断准确性
/// 对于任意一组变量，批量推断的结果应该与单独推断每个变量的结果一致
fn property_batch_inference_accuracy(input: BatchInferenceInput) bool {
    const allocator = std.testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录观察
    for (input.var_names, input.var_types) |var_name, type_info| {
        var i: u32 = 0;
        while (i < input.observation_count) : (i += 1) {
            inference.recordTypeObservation(var_name, type_info) catch return false;
        }
    }
    
    // 批量推断
    const batch_types = inference.inferParameterTypes(input.var_names) catch return false;
    defer allocator.free(batch_types);
    
    // 单独推断并比较
    for (input.var_names, batch_types) |var_name, batch_type| {
        const individual_type = inference.inferType(var_name);
        if (batch_type != individual_type) {
            return false;
        }
    }
    
    return true;
}

/// 属性 10.4：推断准确率目标
/// 对于任意一组高质量的 profile 数据，整体推断准确率应该 > 95%
fn property_overall_accuracy_target(input: BatchInferenceInput) bool {
    const allocator = std.testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录高质量观察数据（足够多的观察次数）
    for (input.var_names, input.var_types) |var_name, type_info| {
        var i: u32 = 0;
        while (i < input.observation_count) : (i += 1) {
            inference.recordTypeObservation(var_name, type_info) catch return false;
        }
    }
    
    // 推断所有变量
    for (input.var_names) |var_name| {
        _ = inference.inferType(var_name);
    }
    
    // 检查准确率
    const accuracy = inference.getAccuracy();
    
    // 验证：准确率应该 > 95%
    return accuracy > 0.95;
}

// ============================================================================
// 主测试入口
// ============================================================================

test "Property 10.1: 单态类型推断准确性" {
    std.debug.print("\n=== 属性 10.1: 单态类型推断准确性 ===\n", .{});
    
    var pt = PropertyTest.init(std.testing.allocator, 12345, 100);
    
    const result = try pt.run(
        MonomorphicInput,
        &property_monomorphic_accuracy,
        &genMonomorphicInput,
        &MonomorphicInput.cleanup,
    );
    
    try result.print(std.debug);
    
    // 验证：至少 95% 的测试应该通过
    try std.testing.expect(result.successRate() >= 0.95);
}

test "Property 10.2: 多态类型推断准确性" {
    std.debug.print("\n=== 属性 10.2: 多态类型推断准确性 ===\n", .{});
    
    var pt = PropertyTest.init(std.testing.allocator, 67890, 100);
    
    const result = try pt.run(
        PolymorphicInput,
        &property_polymorphic_accuracy,
        &genPolymorphicInput,
        &PolymorphicInput.cleanup,
    );
    
    try result.print(std.debug);
    
    // 验证：至少 90% 的测试应该通过（多态情况更复杂）
    try std.testing.expect(result.successRate() >= 0.90);
}

test "Property 10.3: 批量推断准确性" {
    std.debug.print("\n=== 属性 10.3: 批量推断准确性 ===\n", .{});
    
    var pt = PropertyTest.init(std.testing.allocator, 11111, 100);
    
    const result = try pt.run(
        BatchInferenceInput,
        &property_batch_inference_accuracy,
        &genBatchInferenceInput,
        &BatchInferenceInput.cleanup,
    );
    
    try result.print(std.debug);
    
    // 验证：100% 的测试应该通过（批量推断应该与单独推断一致）
    try std.testing.expect(result.successRate() == 1.0);
}

test "Property 10.4: 推断准确率目标 > 95%" {
    std.debug.print("\n=== 属性 10.4: 推断准确率目标 > 95% ===\n", .{});
    
    var pt = PropertyTest.init(std.testing.allocator, 22222, 100);
    
    const result = try pt.run(
        BatchInferenceInput,
        &property_overall_accuracy_target,
        &genBatchInferenceInput,
        &BatchInferenceInput.cleanup,
    );
    
    try result.print(std.debug);
    
    // 验证：至少 95% 的测试应该通过
    try std.testing.expect(result.successRate() >= 0.95);
}

// ============================================================================
// 集成测试
// ============================================================================

test "集成测试：类型推断引擎完整流程" {
    std.debug.print("\n=== 集成测试：类型推断引擎完整流程 ===\n", .{});
    
    const allocator = std.testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 模拟真实场景：记录多个变量的类型观察
    const scenarios = [_]struct {
        var_name: []const u8,
        type_info: TypeInfo,
        count: u32,
    }{
        .{ .var_name = "counter", .type_info = .int, .count = 100 },
        .{ .var_name = "price", .type_info = .float, .count = 80 },
        .{ .var_name = "name", .type_info = .string, .count = 50 },
        .{ .var_name = "items", .type_info = .array, .count = 60 },
        .{ .var_name = "user", .type_info = .object, .count = 40 },
    };
    
    // 记录观察
    for (scenarios) |scenario| {
        var i: u32 = 0;
        while (i < scenario.count) : (i += 1) {
            try inference.recordTypeObservation(scenario.var_name, scenario.type_info);
        }
    }
    
    // 推断所有变量
    var correct_inferences: u32 = 0;
    for (scenarios) |scenario| {
        const inferred = inference.inferType(scenario.var_name);
        if (inferred == scenario.type_info) {
            correct_inferences += 1;
        }
    }
    
    // 验证准确率
    const accuracy = @as(f32, @floatFromInt(correct_inferences)) / @as(f32, @floatFromInt(scenarios.len));
    std.debug.print("推断准确率: {d:.2}%\n", .{accuracy * 100.0});
    
    try std.testing.expect(accuracy >= 0.95);
    
    // 打印统计信息
    std.debug.print("\n", .{});
    try inference.printStats(std.debug);
}

test "性能测试：类型推断引擎性能" {
    std.debug.print("\n=== 性能测试：类型推断引擎性能 ===\n", .{});
    
    const allocator = std.testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录大量观察 - 使用较少的变量数量避免内存问题
    const var_count = 10;
    const observations_per_var = 100;
    
    var timer = try std.time.Timer.start();
    
    // 预先分配变量名
    var var_names = try allocator.alloc([]u8, var_count);
    defer {
        for (var_names) |name| {
            allocator.free(name);
        }
        allocator.free(var_names);
    }
    
    for (0..var_count) |i| {
        var_names[i] = try std.fmt.allocPrint(allocator, "var_{d}", .{i});
    }
    
    // 记录观察
    for (var_names) |var_name| {
        var j: usize = 0;
        while (j < observations_per_var) : (j += 1) {
            try inference.recordTypeObservation(var_name, .int);
        }
    }
    
    const record_time = timer.read();
    
    // 推断所有变量
    timer.reset();
    
    for (var_names) |var_name| {
        _ = inference.inferType(var_name);
    }
    
    const infer_time = timer.read();
    
    std.debug.print("记录 {d} 个变量 x {d} 次观察: {d} ms\n", .{
        var_count,
        observations_per_var,
        record_time / std.time.ns_per_ms,
    });
    std.debug.print("推断 {d} 个变量: {d} ms\n", .{
        var_count,
        infer_time / std.time.ns_per_ms,
    });
    std.debug.print("平均推断时间: {d} ns/变量\n", .{
        infer_time / var_count,
    });
}
