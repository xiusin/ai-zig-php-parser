//! 属性测试：SIMD 数学运算正确性
//!
//! 本测试验证 SIMD 加速的数学运算与标量实现的语义等价性
//!
//! 属性 36：SIMD 数学运算正确性
//! - 对于所有输入，SIMD 实现必须与标量实现产生相同结果
//! - 浮点运算允许微小误差（< 1e-10）
//! - 整数运算必须精确匹配
//!
//! 验证需求：5.8, 9.5

const std = @import("std");
const testing = std.testing;
const simd_math = @import("simd_math.zig");

// 随机数生成器
var prng = std.Random.DefaultPrng.init(0);

// 属性 36.1：向量加法正确性（整数）
// 对于任意整数向量 a 和 b，SIMD 加法结果必须与标量加法相同
test "Property 36.1: Vector addition correctness (integer)" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    // 运行 100 次迭代
    for (0..100) |_| {
        // 生成随机长度（1-128）
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        // 分配数组
        const a = try testing.allocator.alloc(i64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(i64, len);
        defer testing.allocator.free(b);
        const result_simd = try testing.allocator.alloc(i64, len);
        defer testing.allocator.free(result_simd);
        var result_scalar = try testing.allocator.alloc(i64, len);
        defer testing.allocator.free(result_scalar);
        
        // 生成随机数据（避免溢出）
        for (a, b) |*val_a, *val_b| {
            val_a.* = rand.intRangeAtMost(i64, -1000000, 1000000);
            val_b.* = rand.intRangeAtMost(i64, -1000000, 1000000);
        }
        
        // SIMD 实现
        simd.vectorAddInt(a, b, result_simd);
        
        // 标量实现
        for (a, b, 0..) |val_a, val_b, i| {
            result_scalar[i] = val_a + val_b;
        }
        
        // 验证结果相同
        try testing.expectEqualSlices(i64, result_scalar, result_simd);
    }
}

// 属性 36.2：向量加法正确性（浮点）
// 对于任意浮点向量 a 和 b，SIMD 加法结果必须与标量加法相同（允许微小误差）
test "Property 36.2: Vector addition correctness (float)" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(b);
        const result_simd = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result_simd);
        var result_scalar = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result_scalar);
        
        // 生成随机浮点数（-1000.0 到 1000.0）
        for (a, b) |*val_a, *val_b| {
            val_a.* = rand.float(f64) * 2000.0 - 1000.0;
            val_b.* = rand.float(f64) * 2000.0 - 1000.0;
        }
        
        // SIMD 实现
        simd.vectorAddFloat(a, b, result_simd);
        
        // 标量实现
        for (a, b, 0..) |val_a, val_b, i| {
            result_scalar[i] = val_a + val_b;
        }
        
        // 验证结果相同（允许微小误差）
        for (result_scalar, result_simd) |expected, actual| {
            try testing.expectApproxEqAbs(expected, actual, 1e-10);
        }
    }
}

// 属性 36.3：向量乘法正确性（整数）
// 对于任意整数向量 a 和 b，SIMD 乘法结果必须与标量乘法相同
test "Property 36.3: Vector multiplication correctness (integer)" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        const a = try testing.allocator.alloc(i64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(i64, len);
        defer testing.allocator.free(b);
        const result_simd = try testing.allocator.alloc(i64, len);
        defer testing.allocator.free(result_simd);
        var result_scalar = try testing.allocator.alloc(i64, len);
        defer testing.allocator.free(result_scalar);
        
        // 生成较小的随机数以避免溢出
        for (a, b) |*val_a, *val_b| {
            val_a.* = rand.intRangeAtMost(i64, -1000, 1000);
            val_b.* = rand.intRangeAtMost(i64, -1000, 1000);
        }
        
        // SIMD 实现
        simd.vectorMulInt(a, b, result_simd);
        
        // 标量实现
        for (a, b, 0..) |val_a, val_b, i| {
            result_scalar[i] = val_a * val_b;
        }
        
        // 验证结果相同
        try testing.expectEqualSlices(i64, result_scalar, result_simd);
    }
}

// 属性 36.4：向量乘法正确性（浮点）
// 对于任意浮点向量 a 和 b，SIMD 乘法结果必须与标量乘法相同（允许微小误差）
test "Property 36.4: Vector multiplication correctness (float)" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(b);
        const result_simd = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result_simd);
        var result_scalar = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result_scalar);
        
        // 生成随机浮点数
        for (a, b) |*val_a, *val_b| {
            val_a.* = rand.float(f64) * 100.0 - 50.0;
            val_b.* = rand.float(f64) * 100.0 - 50.0;
        }
        
        // SIMD 实现
        simd.vectorMulFloat(a, b, result_simd);
        
        // 标量实现
        for (a, b, 0..) |val_a, val_b, i| {
            result_scalar[i] = val_a * val_b;
        }
        
        // 验证结果相同（允许微小误差）
        for (result_scalar, result_simd) |expected, actual| {
            try testing.expectApproxEqAbs(expected, actual, 1e-10);
        }
    }
}

// 属性 36.5：平方根正确性
// 对于任意非负浮点向量，SIMD sqrt 结果必须与标量 sqrt 相同
test "Property 36.5: Square root correctness" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        const arr = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(arr);
        const result_simd = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result_simd);
        var result_scalar = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result_scalar);
        
        // 生成非负随机浮点数
        for (arr) |*val| {
            val.* = rand.float(f64) * 1000.0;
        }
        
        // SIMD 实现
        simd.vectorSqrt(arr, result_simd);
        
        // 标量实现
        for (arr, 0..) |val, i| {
            result_scalar[i] = @sqrt(val);
        }
        
        // 验证结果相同（允许微小误差）
        for (result_scalar, result_simd) |expected, actual| {
            try testing.expectApproxEqAbs(expected, actual, 1e-10);
        }
    }
}

// 属性 36.6：点积正确性
// 对于任意浮点向量 a 和 b，SIMD 点积结果必须与标量点积相同
test "Property 36.6: Dot product correctness" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(b);
        
        // 生成随机浮点数
        for (a, b) |*val_a, *val_b| {
            val_a.* = rand.float(f64) * 100.0 - 50.0;
            val_b.* = rand.float(f64) * 100.0 - 50.0;
        }
        
        // SIMD 实现
        const result_simd = simd.dotProduct(a, b);
        
        // 标量实现
        var result_scalar: f64 = 0.0;
        for (a, b) |val_a, val_b| {
            result_scalar += val_a * val_b;
        }
        
        // 验证结果相同（允许微小误差）
        try testing.expectApproxEqAbs(result_scalar, result_simd, 1e-8);
    }
}

// 属性 36.7：结合律（向量加法）
// 对于任意向量 a, b, c，(a + b) + c = a + (b + c)
test "Property 36.7: Associativity of vector addition" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 64);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(b);
        const c = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(c);
        
        const temp1 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(temp1);
        const result1 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result1);
        
        const temp2 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(temp2);
        const result2 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result2);
        
        // 生成随机数据
        for (a, b, c) |*val_a, *val_b, *val_c| {
            val_a.* = rand.float(f64) * 100.0 - 50.0;
            val_b.* = rand.float(f64) * 100.0 - 50.0;
            val_c.* = rand.float(f64) * 100.0 - 50.0;
        }
        
        // 计算 (a + b) + c
        simd.vectorAddFloat(a, b, temp1);
        simd.vectorAddFloat(temp1, c, result1);
        
        // 计算 a + (b + c)
        simd.vectorAddFloat(b, c, temp2);
        simd.vectorAddFloat(a, temp2, result2);
        
        // 验证结果相同
        for (result1, result2) |r1, r2| {
            try testing.expectApproxEqAbs(r1, r2, 1e-8);
        }
    }
}

// 属性 36.8：交换律（向量加法）
// 对于任意向量 a, b，a + b = b + a
test "Property 36.8: Commutativity of vector addition" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(b);
        const result1 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result1);
        const result2 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result2);
        
        // 生成随机数据
        for (a, b) |*val_a, *val_b| {
            val_a.* = rand.float(f64) * 100.0 - 50.0;
            val_b.* = rand.float(f64) * 100.0 - 50.0;
        }
        
        // 计算 a + b
        simd.vectorAddFloat(a, b, result1);
        
        // 计算 b + a
        simd.vectorAddFloat(b, a, result2);
        
        // 验证结果相同
        for (result1, result2) |r1, r2| {
            try testing.expectApproxEqAbs(r1, r2, 1e-10);
        }
    }
}

// 属性 36.9：分配律（向量乘法和加法）
// 对于任意向量 a, b, c，a * (b + c) = a * b + a * c
test "Property 36.9: Distributivity of multiplication over addition" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 64);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(b);
        const c = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(c);
        
        const temp1 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(temp1);
        const result1 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result1);
        
        const temp2 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(temp2);
        const temp3 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(temp3);
        const result2 = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result2);
        
        // 生成随机数据
        for (a, b, c) |*val_a, *val_b, *val_c| {
            val_a.* = rand.float(f64) * 10.0 - 5.0;
            val_b.* = rand.float(f64) * 10.0 - 5.0;
            val_c.* = rand.float(f64) * 10.0 - 5.0;
        }
        
        // 计算 a * (b + c)
        simd.vectorAddFloat(b, c, temp1);
        simd.vectorMulFloat(a, temp1, result1);
        
        // 计算 a * b + a * c
        simd.vectorMulFloat(a, b, temp2);
        simd.vectorMulFloat(a, c, temp3);
        simd.vectorAddFloat(temp2, temp3, result2);
        
        // 验证结果相同
        for (result1, result2) |r1, r2| {
            try testing.expectApproxEqAbs(r1, r2, 1e-8);
        }
    }
}

// 属性 36.10：点积的双线性性
// 对于任意向量 a, b, c 和标量 k，dot(a + b, c) = dot(a, c) + dot(b, c)
test "Property 36.10: Bilinearity of dot product" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 64);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const b = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(b);
        const c = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(c);
        const temp = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(temp);
        
        // 生成随机数据
        for (a, b, c) |*val_a, *val_b, *val_c| {
            val_a.* = rand.float(f64) * 10.0 - 5.0;
            val_b.* = rand.float(f64) * 10.0 - 5.0;
            val_c.* = rand.float(f64) * 10.0 - 5.0;
        }
        
        // 计算 dot(a + b, c)
        simd.vectorAddFloat(a, b, temp);
        const result1 = simd.dotProduct(temp, c);
        
        // 计算 dot(a, c) + dot(b, c)
        const dot_ac = simd.dotProduct(a, c);
        const dot_bc = simd.dotProduct(b, c);
        const result2 = dot_ac + dot_bc;
        
        // 验证结果相同
        try testing.expectApproxEqAbs(result1, result2, 1e-8);
    }
}

// 属性 36.11：边界情况 - 零向量
// 对于任意向量 a，a + 0 = a
test "Property 36.11: Identity element for addition" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const zero = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(zero);
        const result = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result);
        
        // 生成随机数据
        for (a, zero) |*val_a, *val_zero| {
            val_a.* = rand.float(f64) * 100.0 - 50.0;
            val_zero.* = 0.0;
        }
        
        // 计算 a + 0
        simd.vectorAddFloat(a, zero, result);
        
        // 验证结果等于 a
        for (a, result) |expected, actual| {
            try testing.expectApproxEqAbs(expected, actual, 1e-10);
        }
    }
}

// 属性 36.12：边界情况 - 单位向量乘法
// 对于任意向量 a，a * 1 = a
test "Property 36.12: Identity element for multiplication" {
    const simd = simd_math.SIMDMath.init();
    const rand = prng.random();
    
    for (0..100) |_| {
        const len = rand.intRangeAtMost(usize, 1, 128);
        
        const a = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(a);
        const one = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(one);
        const result = try testing.allocator.alloc(f64, len);
        defer testing.allocator.free(result);
        
        // 生成随机数据
        for (a, one) |*val_a, *val_one| {
            val_a.* = rand.float(f64) * 100.0 - 50.0;
            val_one.* = 1.0;
        }
        
        // 计算 a * 1
        simd.vectorMulFloat(a, one, result);
        
        // 验证结果等于 a
        for (a, result) |expected, actual| {
            try testing.expectApproxEqAbs(expected, actual, 1e-10);
        }
    }
}
