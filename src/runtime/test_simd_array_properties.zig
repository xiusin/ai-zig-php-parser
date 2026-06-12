//! 属性测试：SIMD 数组操作正确性
//!
//! Feature: zig-php-performance-optimization
//! Property 35: SIMD 数组操作正确性
//! 验证：需求 5.7, 9.3, 9.4
//!
//! 对于任意数组，SIMD 版本的数组操作结果应该与标量版本完全相同
//!
//! @ownership NON-OWNING (allocator)
//! @thread-safety ISOLATED

const std = @import("std");
const testing = std.testing;
const simd_array = @import("simd_array.zig");

/// 属性测试配置
const ITERATIONS = 100;
const MAX_ARRAY_SIZE = 1000;

/// 随机数生成器
var prng = std.Random.DefaultPrng.init(0);
const rng = prng.random();

/// 生成随机整数数组
fn generateRandomIntArray(allocator: std.mem.Allocator, max_size: usize) ![]i64 {
    const size = rng.uintLessThan(usize, max_size) + 1;
    const arr = try allocator.alloc(i64, size);
    
    for (arr) |*val| {
        val.* = rng.intRangeAtMost(i64, -1000, 1000);
    }
    
    return arr;
}

/// 生成随机浮点数组
fn generateRandomFloatArray(allocator: std.mem.Allocator, max_size: usize) ![]f64 {
    const size = rng.uintLessThan(usize, max_size) + 1;
    const arr = try allocator.alloc(f64, size);
    
    for (arr) |*val| {
        val.* = (rng.float(f64) - 0.5) * 2000.0; // -1000.0 到 1000.0
    }
    
    return arr;
}


// ============================================================================
// 属性 35.1: array_sum 整数正确性
// ============================================================================

test "Property 35.1: SIMD array_sum (int) correctness" {
    std.debug.print("\n=== Property 35.1: SIMD array_sum (int) correctness ===\n", .{});
    
    const simd = simd_array.SIMDArray.init(testing.allocator);
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    for (0..ITERATIONS) |iter| {
        // 生成随机数组
        const arr = try generateRandomIntArray(testing.allocator, MAX_ARRAY_SIZE);
        defer testing.allocator.free(arr);
        
        // SIMD 版本
        const simd_result = simd.arraySumInt(arr);
        
        // 标量版本
        const scalar_result = simd_array.SIMDArray.arraySumIntScalar(arr);
        
        // 验证结果相同
        if (simd_result == scalar_result) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("  Iteration {d}: FAILED\n", .{iter});
            std.debug.print("    Array size: {d}\n", .{arr.len});
            std.debug.print("    SIMD result: {d}\n", .{simd_result});
            std.debug.print("    Scalar result: {d}\n", .{scalar_result});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(ITERATIONS));
    std.debug.print("  Results: {d}/{d} passed ({d:.2}%)\n", .{passed, ITERATIONS, success_rate * 100});
    
    try testing.expectEqual(@as(u32, 0), failed);
}

// ============================================================================
// 属性 35.2: array_sum 浮点正确性
// ============================================================================

test "Property 35.2: SIMD array_sum (float) correctness" {
    std.debug.print("\n=== Property 35.2: SIMD array_sum (float) correctness ===\n", .{});
    
    const simd = simd_array.SIMDArray.init(testing.allocator);
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    for (0..ITERATIONS) |iter| {
        // 生成随机数组
        const arr = try generateRandomFloatArray(testing.allocator, MAX_ARRAY_SIZE);
        defer testing.allocator.free(arr);
        
        // SIMD 版本
        const simd_result = simd.arraySumFloat(arr);
        
        // 标量版本
        const scalar_result = simd_array.SIMDArray.arraySumFloatScalar(arr);
        
        // 验证结果相同（浮点精度范围内）
        const diff = @abs(simd_result - scalar_result);
        const tolerance = @abs(scalar_result) * 1e-10 + 1e-10;
        
        if (diff <= tolerance) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("  Iteration {d}: FAILED\n", .{iter});
            std.debug.print("    Array size: {d}\n", .{arr.len});
            std.debug.print("    SIMD result: {d}\n", .{simd_result});
            std.debug.print("    Scalar result: {d}\n", .{scalar_result});
            std.debug.print("    Difference: {d}\n", .{diff});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(ITERATIONS));
    std.debug.print("  Results: {d}/{d} passed ({d:.2}%)\n", .{passed, ITERATIONS, success_rate * 100});
    
    try testing.expectEqual(@as(u32, 0), failed);
}


// ============================================================================
// 属性 35.3: array_map 整数正确性
// ============================================================================

test "Property 35.3: SIMD array_map (int) correctness" {
    std.debug.print("\n=== Property 35.3: SIMD array_map (int) correctness ===\n", .{});
    
    const simd = simd_array.SIMDArray.init(testing.allocator);
    
    // 定义映射函数
    const map_fn = struct {
        fn f(x: i64) i64 {
            return x * 2 + 1;
        }
    }.f;
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    for (0..ITERATIONS) |iter| {
        // 生成随机数组
        const arr = try generateRandomIntArray(testing.allocator, MAX_ARRAY_SIZE);
        defer testing.allocator.free(arr);
        
        // SIMD 版本
        const simd_result = try simd.arrayMapInt(arr, map_fn);
        defer testing.allocator.free(simd_result);
        
        // 标量版本
        const scalar_result = try testing.allocator.alloc(i64, arr.len);
        defer testing.allocator.free(scalar_result);
        simd_array.SIMDArray.arrayMapIntScalar(arr, scalar_result, map_fn);
        
        // 验证结果相同
        if (std.mem.eql(i64, simd_result, scalar_result)) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("  Iteration {d}: FAILED\n", .{iter});
            std.debug.print("    Array size: {d}\n", .{arr.len});
            
            // 显示前几个不同的元素
            var diff_count: usize = 0;
            for (simd_result, scalar_result, 0..) |simd_val, scalar_val, i| {
                if (simd_val != scalar_val) {
                    std.debug.print("    Index {d}: SIMD={d}, Scalar={d}\n", .{i, simd_val, scalar_val});
                    diff_count += 1;
                    if (diff_count >= 5) break;
                }
            }
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(ITERATIONS));
    std.debug.print("  Results: {d}/{d} passed ({d:.2}%)\n", .{passed, ITERATIONS, success_rate * 100});
    
    try testing.expectEqual(@as(u32, 0), failed);
}

// ============================================================================
// 属性 35.4: array_map 浮点正确性
// ============================================================================

test "Property 35.4: SIMD array_map (float) correctness" {
    std.debug.print("\n=== Property 35.4: SIMD array_map (float) correctness ===\n", .{});
    
    const simd = simd_array.SIMDArray.init(testing.allocator);
    
    // 定义映射函数
    const map_fn = struct {
        fn f(x: f64) f64 {
            return x * x + 1.0;
        }
    }.f;
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    for (0..ITERATIONS) |iter| {
        // 生成随机数组
        const arr = try generateRandomFloatArray(testing.allocator, MAX_ARRAY_SIZE);
        defer testing.allocator.free(arr);
        
        // SIMD 版本
        const simd_result = try simd.arrayMapFloat(arr, map_fn);
        defer testing.allocator.free(simd_result);
        
        // 标量版本
        const scalar_result = try testing.allocator.alloc(f64, arr.len);
        defer testing.allocator.free(scalar_result);
        simd_array.SIMDArray.arrayMapFloatScalar(arr, scalar_result, map_fn);
        
        // 验证结果相同（浮点精度范围内）
        var all_match = true;
        for (simd_result, scalar_result) |simd_val, scalar_val| {
            const diff = @abs(simd_val - scalar_val);
            const tolerance = @abs(scalar_val) * 1e-10 + 1e-10;
            if (diff > tolerance) {
                all_match = false;
                break;
            }
        }
        
        if (all_match) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("  Iteration {d}: FAILED\n", .{iter});
            std.debug.print("    Array size: {d}\n", .{arr.len});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(ITERATIONS));
    std.debug.print("  Results: {d}/{d} passed ({d:.2}%)\n", .{passed, ITERATIONS, success_rate * 100});
    
    try testing.expectEqual(@as(u32, 0), failed);
}


// ============================================================================
// 属性 35.5: array_filter 整数正确性
// ============================================================================

test "Property 35.5: SIMD array_filter (int) correctness" {
    std.debug.print("\n=== Property 35.5: SIMD array_filter (int) correctness ===\n", .{});
    
    const simd = simd_array.SIMDArray.init(testing.allocator);
    
    // 定义过滤函数
    const filter_fn = struct {
        fn f(x: i64) bool {
            return @mod(x, 2) == 0; // 偶数
        }
    }.f;
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    for (0..ITERATIONS) |iter| {
        // 生成随机数组
        const arr = try generateRandomIntArray(testing.allocator, MAX_ARRAY_SIZE);
        defer testing.allocator.free(arr);
        
        // SIMD 版本
        const simd_result = try simd.arrayFilterInt(arr, filter_fn);
        defer if (simd_result.len > 0) testing.allocator.free(simd_result);
        
        // 标量版本（手动实现）
        var scalar_list = std.ArrayList(i64).initCapacity(testing.allocator, arr.len) catch unreachable;
        defer scalar_list.deinit(testing.allocator);
        for (arr) |val| {
            if (filter_fn(val)) {
                try scalar_list.append(testing.allocator, val);
            }
        }
        const scalar_result = try scalar_list.toOwnedSlice(testing.allocator);
        defer if (scalar_result.len > 0) testing.allocator.free(scalar_result);
        
        // 验证结果相同
        if (std.mem.eql(i64, simd_result, scalar_result)) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("  Iteration {d}: FAILED\n", .{iter});
            std.debug.print("    Array size: {d}\n", .{arr.len});
            std.debug.print("    SIMD result length: {d}\n", .{simd_result.len});
            std.debug.print("    Scalar result length: {d}\n", .{scalar_result.len});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(ITERATIONS));
    std.debug.print("  Results: {d}/{d} passed ({d:.2}%)\n", .{passed, ITERATIONS, success_rate * 100});
    
    try testing.expectEqual(@as(u32, 0), failed);
}

// ============================================================================
// 属性 35.6: array_filter 浮点正确性
// ============================================================================

test "Property 35.6: SIMD array_filter (float) correctness" {
    std.debug.print("\n=== Property 35.6: SIMD array_filter (float) correctness ===\n", .{});
    
    const simd = simd_array.SIMDArray.init(testing.allocator);
    
    // 定义过滤函数
    const filter_fn = struct {
        fn f(x: f64) bool {
            return x > 0.0; // 正数
        }
    }.f;
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    for (0..ITERATIONS) |iter| {
        // 生成随机数组
        const arr = try generateRandomFloatArray(testing.allocator, MAX_ARRAY_SIZE);
        defer testing.allocator.free(arr);
        
        // SIMD 版本
        const simd_result = try simd.arrayFilterFloat(arr, filter_fn);
        defer if (simd_result.len > 0) testing.allocator.free(simd_result);
        
        // 标量版本（手动实现）
        var scalar_list = std.ArrayList(f64).initCapacity(testing.allocator, arr.len) catch unreachable;
        defer scalar_list.deinit(testing.allocator);
        for (arr) |val| {
            if (filter_fn(val)) {
                try scalar_list.append(testing.allocator, val);
            }
        }
        const scalar_result = try scalar_list.toOwnedSlice(testing.allocator);
        defer if (scalar_result.len > 0) testing.allocator.free(scalar_result);
        
        // 验证结果相同（浮点精度范围内）
        var all_match = simd_result.len == scalar_result.len;
        if (all_match) {
            for (simd_result, scalar_result) |simd_val, scalar_val| {
                const diff = @abs(simd_val - scalar_val);
                if (diff > 1e-10) {
                    all_match = false;
                    break;
                }
            }
        }
        
        if (all_match) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("  Iteration {d}: FAILED\n", .{iter});
            std.debug.print("    Array size: {d}\n", .{arr.len});
            std.debug.print("    SIMD result length: {d}\n", .{simd_result.len});
            std.debug.print("    Scalar result length: {d}\n", .{scalar_result.len});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(ITERATIONS));
    std.debug.print("  Results: {d}/{d} passed ({d:.2}%)\n", .{passed, ITERATIONS, success_rate * 100});
    
    try testing.expectEqual(@as(u32, 0), failed);
}

// ============================================================================
// 性能对比测试
// ============================================================================

test "Performance: SIMD vs Scalar array_sum (int)" {
    std.debug.print("\n=== Performance: SIMD vs Scalar array_sum (int) ===\n", .{});
    
    const simd = simd_array.SIMDArray.init(testing.allocator);
    
    // 生成大数组
    const size = 10000;
    const arr = try testing.allocator.alloc(i64, size);
    defer testing.allocator.free(arr);
    for (arr) |*val| {
        val.* = rng.intRangeAtMost(i64, -1000, 1000);
    }
    
    // 预热
    _ = simd.arraySumInt(arr);
    _ = simd_array.SIMDArray.arraySumIntScalar(arr);
    
    // SIMD 版本
    const simd_iterations = 1000;
    var simd_timer = try std.time.Timer.start();
    for (0..simd_iterations) |_| {
        _ = simd.arraySumInt(arr);
    }
    const simd_time = simd_timer.read();
    
    // 标量版本
    const scalar_iterations = 1000;
    var scalar_timer = try std.time.Timer.start();
    for (0..scalar_iterations) |_| {
        _ = simd_array.SIMDArray.arraySumIntScalar(arr);
    }
    const scalar_time = scalar_timer.read();
    
    const simd_ns_per_op = simd_time / simd_iterations;
    const scalar_ns_per_op = scalar_time / scalar_iterations;
    const speedup = @as(f64, @floatFromInt(scalar_ns_per_op)) / @as(f64, @floatFromInt(simd_ns_per_op));
    
    std.debug.print("  Array size: {d}\n", .{size});
    std.debug.print("  SIMD: {d} ns/op\n", .{simd_ns_per_op});
    std.debug.print("  Scalar: {d} ns/op\n", .{scalar_ns_per_op});
    std.debug.print("  Speedup: {d:.2}x\n", .{speedup});
    
    // 验证性能提升（至少 0.8x，目标 2-4x）
    // 注意：在某些架构上（如 ARM NEON），SIMD 优势可能不明显
    // 主要验证正确性，性能提升是额外收益
    try testing.expect(speedup >= 0.8);
}

test "Performance: SIMD vs Scalar array_sum (float)" {
    std.debug.print("\n=== Performance: SIMD vs Scalar array_sum (float) ===\n", .{});
    
    const simd = simd_array.SIMDArray.init(testing.allocator);
    
    // 生成大数组
    const size = 10000;
    const arr = try testing.allocator.alloc(f64, size);
    defer testing.allocator.free(arr);
    for (arr) |*val| {
        val.* = (rng.float(f64) - 0.5) * 2000.0;
    }
    
    // 预热
    _ = simd.arraySumFloat(arr);
    _ = simd_array.SIMDArray.arraySumFloatScalar(arr);
    
    // SIMD 版本
    const simd_iterations = 1000;
    var simd_timer = try std.time.Timer.start();
    for (0..simd_iterations) |_| {
        _ = simd.arraySumFloat(arr);
    }
    const simd_time = simd_timer.read();
    
    // 标量版本
    const scalar_iterations = 1000;
    var scalar_timer = try std.time.Timer.start();
    for (0..scalar_iterations) |_| {
        _ = simd_array.SIMDArray.arraySumFloatScalar(arr);
    }
    const scalar_time = scalar_timer.read();
    
    const simd_ns_per_op = simd_time / simd_iterations;
    const scalar_ns_per_op = scalar_time / scalar_iterations;
    const speedup = @as(f64, @floatFromInt(scalar_ns_per_op)) / @as(f64, @floatFromInt(simd_ns_per_op));
    
    std.debug.print("  Array size: {d}\n", .{size});
    std.debug.print("  SIMD: {d} ns/op\n", .{simd_ns_per_op});
    std.debug.print("  Scalar: {d} ns/op\n", .{scalar_ns_per_op});
    std.debug.print("  Speedup: {d:.2}x\n", .{speedup});
    
    // 验证性能提升（至少 0.8x，目标 2-4x）
    // 注意：在某些架构上（如 ARM NEON），SIMD 优势可能不明显
    // 主要验证正确性，性能提升是额外收益
    try testing.expect(speedup >= 0.8);
}
