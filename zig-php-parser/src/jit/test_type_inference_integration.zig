/// 测试 JIT 编译器的类型推断集成
/// 
/// 验证类型推断引擎正确集成到 JIT 编译器中

const std = @import("std");
const testing = std.testing;
const Compiler = @import("compiler.zig").Compiler;
const TypeInference = @import("type_inference.zig").TypeInference;
const TypeInfo = @import("type_inference.zig").TypeInfo;

test "类型推断引擎初始化" {
    const allocator = testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录一些类型观察
    try inference.recordTypeObservation("x", .int);
    try inference.recordTypeObservation("x", .int);
    try inference.recordTypeObservation("x", .int);
    
    try inference.recordTypeObservation("y", .float);
    try inference.recordTypeObservation("y", .float);
    
    try inference.recordTypeObservation("z", .string);
    
    // 推断类型
    const x_type = inference.inferType("x");
    const y_type = inference.inferType("y");
    const z_type = inference.inferType("z");
    
    // 验证推断结果
    try testing.expectEqual(TypeInfo.dynamic, x_type); // 观察次数不够（需要 >= 10）
    try testing.expectEqual(TypeInfo.dynamic, y_type); // 观察次数不够
    try testing.expectEqual(TypeInfo.dynamic, z_type); // 观察次数不够
}

test "类型推断引擎 - 足够的观察" {
    const allocator = testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录足够的观察（>= 10 次，置信度 >= 95%）
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        try inference.recordTypeObservation("x", .int);
    }
    
    // 推断类型
    const x_type = inference.inferType("x");
    
    // 验证推断结果
    try testing.expectEqual(TypeInfo.int, x_type);
}

test "类型推断引擎 - 多态类型" {
    const allocator = testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录混合类型（60% int, 40% float）
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        try inference.recordTypeObservation("x", .int);
    }
    i = 0;
    while (i < 10) : (i += 1) {
        try inference.recordTypeObservation("x", .float);
    }
    
    // 推断类型（置信度 60%，不满足 95% 的要求）
    const x_type = inference.inferType("x");
    
    // 应该返回 dynamic（置信度不够）
    try testing.expectEqual(TypeInfo.dynamic, x_type);
}

test "类型推断引擎 - 批量推断" {
    const allocator = testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录多个变量的类型
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        try inference.recordTypeObservation("a", .int);
        try inference.recordTypeObservation("b", .float);
        try inference.recordTypeObservation("c", .string);
    }
    
    // 批量推断
    const var_names = [_][]const u8{ "a", "b", "c" };
    const types = try inference.inferParameterTypes(&var_names);
    defer allocator.free(types);
    
    // 验证结果
    try testing.expectEqual(@as(usize, 3), types.len);
    try testing.expectEqual(TypeInfo.int, types[0]);
    try testing.expectEqual(TypeInfo.float, types[1]);
    try testing.expectEqual(TypeInfo.string, types[2]);
}

test "编译器集成类型推断" {
    const allocator = testing.allocator;
    
    // 创建类型推断引擎
    var inference_ptr = try allocator.create(TypeInference);
    defer allocator.destroy(inference_ptr);
    inference_ptr.* = TypeInference.init(allocator);
    defer inference_ptr.deinit();
    
    // 记录类型观察
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        try inference_ptr.recordTypeObservation("local_0", .int);
        try inference_ptr.recordTypeObservation("local_1", .float);
    }
    
    // 创建编译器并集成类型推断
    var compiler = Compiler.initWithTypeInference(allocator, inference_ptr);
    defer fast_compiler.deinit();
    
    // 验证编译器有类型推断引擎
    try testing.expect(compiler.type_inference != null);
    
    // 验证类型推断工作正常
    const type_0 = compiler.type_inference.?.inferType("local_0");
    const type_1 = compiler.type_inference.?.inferType("local_1");
    
    try testing.expectEqual(TypeInfo.int, type_0);
    try testing.expectEqual(TypeInfo.float, type_1);
}

test "类型推断准确率统计" {
    const allocator = testing.allocator;
    
    var inference = TypeInference.init(allocator);
    defer inference.deinit();
    
    // 记录高置信度数据
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try inference.recordTypeObservation("a", .int);
    }
    
    // 记录低置信度数据
    i = 0;
    while (i < 5) : (i += 1) {
        try inference.recordTypeObservation("b", .int);
        try inference.recordTypeObservation("b", .float);
    }
    
    // 推断
    const type_a = inference.inferType("a");
    const type_b = inference.inferType("b");
    
    try testing.expectEqual(TypeInfo.int, type_a);
    try testing.expectEqual(TypeInfo.dynamic, type_b);
    
    // 检查准确率
    const accuracy = inference.getAccuracy();
    try testing.expect(accuracy >= 0.4 and accuracy <= 0.6); // 50% 准确率
}

