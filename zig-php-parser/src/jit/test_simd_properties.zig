const std = @import("std");
const testing = std.testing;
const simd = @import("simd.zig");

// 属性测试框架
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    prng: std.Random.DefaultPrng,
    iterations: u32 = 100,
    
    fn init(allocator: std.mem.Allocator, seed: u64) PropertyTest {
        return .{
            .allocator = allocator,
            .prng = std.Random.DefaultPrng.init(seed),
            .iterations = 100,
        };
    }
    
    fn random(self: *PropertyTest) std.Random {
        return self.prng.random();
    }
};

// 生成随机整数数组
fn generateRandomInt32Array(
    allocator: std.mem.Allocator,
    rng: std.Random,
    len: usize
) ![]i32 {
    const arr = try allocator.alloc(i32, len);
    for (arr) |*val| {
        val.* = rng.intRangeAtMost(i32, -1000, 1000);
    }
    return arr;
}

// 生成随机浮点数组
fn generateRandomFloat64Array(
    allocator: std.mem.Allocator,
    rng: std.Random,
    len: usize
) ![]f64 {
    const arr = try allocator.alloc(f64, len);
    for (arr) |*val| {
        val.* = (rng.float(f64) - 0.5) * 2000.0;
    }
    return arr;
}

// 属性 14：SIMD 语义保持 - 整数加法
// Feature: zig-php-performance-optimization, Property 14: SIMD semantic preservation
// 验证：需求 2.7
test "Property 14: SIMD integer addition semantic preservation" {
    var pt = PropertyTest.init(testing.allocator, 42);
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    var i: u32 = 0;
    while (i < pt.iterations) : (i += 1) {
        // 生成随机长度（1-1000）
        const len = pt.random().intRangeAtMost(usize, 1, 1000);
        
        // 生成随机输入
        const src1 = try generateRandomInt32Array(testing.allocator, pt.random(), len);
        defer testing.allocator.free(src1);
        
        const src2 = try generateRandomInt32Array(testing.allocator, pt.random(), len);
        defer testing.allocator.free(src2);
        
        // SIMD 版本
        const dst_simd = try testing.allocator.alloc(i32, len);
        defer testing.allocator.free(dst_simd);
        
        var vectorizer = simd.SIMDVectorizer.init(testing.allocator);
        vectorizer.addInt32(dst_simd, src1, src2);
        
        // 标量版本（参考实现）
        const dst_scalar = try testing.allocator.alloc(i32, len);
        defer testing.allocator.free(dst_scalar);
        
        for (dst_scalar, src1, src2) |*d, s1, s2| {
            d.* = s1 + s2;
        }
        
        // 验证结果相同
        var all_equal = true;
        for (dst_simd, dst_scalar) |simd_val, scalar_val| {
            if (simd_val != scalar_val) {
                all_equal = false;
                break;
            }
        }
        
        if (all_equal) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("Property failed for len={d}\n", .{len});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(pt.iterations));
    std.debug.print("\nProperty 14 (Int32 Add): {d}/{d} passed ({d:.2}%)\n", 
        .{passed, pt.iterations, success_rate * 100});
    
    try testing.expect(failed == 0);
}


// 属性 14：SIMD 语义保持 - 浮点加法
// Feature: zig-php-performance-optimization, Property 14: SIMD semantic preservation
// 验证：需求 2.7
test "Property 14: SIMD float addition semantic preservation" {
    var pt = PropertyTest.init(testing.allocator, 43);
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    var i: u32 = 0;
    while (i < pt.iterations) : (i += 1) {
        const len = pt.random().intRangeAtMost(usize, 1, 1000);
        
        const src1 = try generateRandomFloat64Array(testing.allocator, pt.random(), len);
        defer testing.allocator.free(src1);
        
        const src2 = try generateRandomFloat64Array(testing.allocator, pt.random(), len);
        defer testing.allocator.free(src2);
        
        // SIMD 版本
        const dst_simd = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(dst_simd);
        
        var vectorizer = simd.SIMDVectorizer.init(testing.allocator);
        vectorizer.addFloat64(dst_simd, src1, src2);
        
        // 标量版本
        const dst_scalar = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(dst_scalar);
        
        for (dst_scalar, src1, src2) |*d, s1, s2| {
            d.* = s1 + s2;
        }
        
        // 验证结果相同（浮点精度范围内）
        var all_equal = true;
        for (dst_simd, dst_scalar) |simd_val, scalar_val| {
            const diff = @abs(simd_val - scalar_val);
            const epsilon = 1e-10;
            if (diff > epsilon) {
                all_equal = false;
                break;
            }
        }
        
        if (all_equal) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("Property failed for len={d}\n", .{len});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(pt.iterations));
    std.debug.print("\nProperty 14 (Float64 Add): {d}/{d} passed ({d:.2}%)\n", 
        .{passed, pt.iterations, success_rate * 100});
    
    try testing.expect(failed == 0);
}

// 属性 14：SIMD 语义保持 - 整数乘法
// Feature: zig-php-performance-optimization, Property 14: SIMD semantic preservation
// 验证：需求 2.7
test "Property 14: SIMD integer multiplication semantic preservation" {
    var pt = PropertyTest.init(testing.allocator, 44);
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    var i: u32 = 0;
    while (i < pt.iterations) : (i += 1) {
        const len = pt.random().intRangeAtMost(usize, 1, 1000);
        
        const src1 = try generateRandomInt32Array(testing.allocator, pt.random(), len);
        defer testing.allocator.free(src1);
        
        const src2 = try generateRandomInt32Array(testing.allocator, pt.random(), len);
        defer testing.allocator.free(src2);
        
        // SIMD 版本
        const dst_simd = try testing.allocator.alloc(i32, len);
        defer testing.allocator.free(dst_simd);
        
        var vectorizer = simd.SIMDVectorizer.init(testing.allocator);
        vectorizer.mulInt32(dst_simd, src1, src2);
        
        // 标量版本
        const dst_scalar = try testing.allocator.alloc(i32, len);
        defer testing.allocator.free(dst_scalar);
        
        for (dst_scalar, src1, src2) |*d, s1, s2| {
            d.* = s1 * s2;
        }
        
        // 验证结果相同
        var all_equal = true;
        for (dst_simd, dst_scalar) |simd_val, scalar_val| {
            if (simd_val != scalar_val) {
                all_equal = false;
                break;
            }
        }
        
        if (all_equal) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("Property failed for len={d}\n", .{len});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(pt.iterations));
    std.debug.print("\nProperty 14 (Int32 Mul): {d}/{d} passed ({d:.2}%)\n", 
        .{passed, pt.iterations, success_rate * 100});
    
    try testing.expect(failed == 0);
}

// 属性 14：SIMD 语义保持 - 浮点乘法
// Feature: zig-php-performance-optimization, Property 14: SIMD semantic preservation
// 验证：需求 2.7
test "Property 14: SIMD float multiplication semantic preservation" {
    var pt = PropertyTest.init(testing.allocator, 45);
    
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    var i: u32 = 0;
    while (i < pt.iterations) : (i += 1) {
        const len = pt.random().intRangeAtMost(usize, 1, 1000);
        
        const src1 = try generateRandomFloat64Array(testing.allocator, pt.random(), len);
        defer testing.allocator.free(src1);
        
        const src2 = try generateRandomFloat64Array(testing.allocator, pt.random(), len);
        defer testing.allocator.free(src2);
        
        // SIMD 版本
        const dst_simd = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(dst_simd);
        
        var vectorizer = simd.SIMDVectorizer.init(testing.allocator);
        vectorizer.mulFloat64(dst_simd, src1, src2);
        
        // 标量版本
        const dst_scalar = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(dst_scalar);
        
        for (dst_scalar, src1, src2) |*d, s1, s2| {
            d.* = s1 * s2;
        }
        
        // 验证结果相同（浮点精度范围内）
        var all_equal = true;
        for (dst_simd, dst_scalar) |simd_val, scalar_val| {
            const diff = @abs(simd_val - scalar_val);
            const epsilon = 1e-10;
            if (diff > epsilon) {
                all_equal = false;
                break;
            }
        }
        
        if (all_equal) {
            passed += 1;
        } else {
            failed += 1;
            std.debug.print("Property failed for len={d}\n", .{len});
        }
    }
    
    const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(pt.iterations));
    std.debug.print("\nProperty 14 (Float64 Mul): {d}/{d} passed ({d:.2}%)\n", 
        .{passed, pt.iterations, success_rate * 100});
    
    try testing.expect(failed == 0);
}

// 单元测试：SIMD 能力检测
test "SIMD capability detection" {
    const caps = simd.SIMDCapabilities.detect();
    
    std.debug.print("\n=== SIMD Capabilities ===\n", .{});
    std.debug.print("Best instruction set: {s}\n", .{@tagName(caps.best_set)});
    
    const type_info = @typeInfo(simd.SIMDInstructionSet);
    inline for (type_info.@"enum".fields) |field| {
        const set = @field(simd.SIMDInstructionSet, field.name);
        if (caps.supports(set)) {
            std.debug.print("  - {s}: supported\n", .{field.name});
        }
    }
    
    // 至少应该支持标量操作
    try testing.expect(caps.best_set != .none or @import("builtin").target.cpu.arch != .x86_64);
}

// 单元测试：边界情况 - 空数组
test "SIMD operations on empty arrays" {
    var vectorizer = simd.SIMDVectorizer.init(testing.allocator);
    
    const dst = try testing.allocator.alloc(i32, 0);
    defer testing.allocator.free(dst);
    
    const src1 = try testing.allocator.alloc(i32, 0);
    defer testing.allocator.free(src1);
    
    const src2 = try testing.allocator.alloc(i32, 0);
    defer testing.allocator.free(src2);
    
    // 不应该崩溃
    vectorizer.addInt32(dst, src1, src2);
}

// 单元测试：边界情况 - 单元素数组
test "SIMD operations on single element arrays" {
    var vectorizer = simd.SIMDVectorizer.init(testing.allocator);
    
    const dst = try testing.allocator.alloc(i32, 1);
    defer testing.allocator.free(dst);
    
    const src1 = try testing.allocator.alloc(i32, 1);
    defer testing.allocator.free(src1);
    src1[0] = 42;
    
    const src2 = try testing.allocator.alloc(i32, 1);
    defer testing.allocator.free(src2);
    src2[0] = 58;
    
    vectorizer.addInt32(dst, src1, src2);
    
    try testing.expectEqual(@as(i32, 100), dst[0]);
}

// 单元测试：边界情况 - 非对齐长度
test "SIMD operations on non-aligned length arrays" {
    var vectorizer = simd.SIMDVectorizer.init(testing.allocator);
    
    // 测试各种非对齐长度
    const lengths = [_]usize{ 3, 5, 7, 9, 11, 13, 15, 17 };
    
    for (lengths) |len| {
        const dst = try testing.allocator.alloc(i32, len);
        defer testing.allocator.free(dst);
        
        const src1 = try testing.allocator.alloc(i32, len);
        defer testing.allocator.free(src1);
        
        const src2 = try testing.allocator.alloc(i32, len);
        defer testing.allocator.free(src2);
        
        // 填充数据
        for (src1, 0..) |*val, i| {
            val.* = @intCast(i);
        }
        for (src2, 0..) |*val, i| {
            val.* = @intCast(i * 2);
        }
        
        vectorizer.addInt32(dst, src1, src2);
        
        // 验证结果
        for (dst, 0..) |val, i| {
            const expected = @as(i32, @intCast(i)) + @as(i32, @intCast(i * 2));
            try testing.expectEqual(expected, val);
        }
    }
}
