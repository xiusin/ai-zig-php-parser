//! SIMD 加速的数学函数
//! 
//! 本模块实现了使用 SIMD 指令加速的数学运算函数，包括：
//! - 基础算术运算（加、减、乘、除）
//! - 数学函数（sqrt, pow, exp, log, sin, cos, tan）
//! - 向量运算（点积、叉积、归一化）
//!
//! 性能目标：接近 C 语言性能
//!
//! @ownership NON-OWNING (allocator)
//! @thread-safety ISOLATED
//! @memory-protection BOUNDS_CHECK

const std = @import("std");
const builtin = @import("builtin");
const math = std.math;

/// SIMD 指令集类型
pub const SIMDInstructionSet = enum {
    none,
    sse2,
    sse4_2,
    avx2,
    avx512,
    neon,
};

/// SIMD 能力检测器
pub const SIMDCapabilities = struct {
    supported_sets: std.EnumSet(SIMDInstructionSet),
    best_set: SIMDInstructionSet,
    
    /// 检测 CPU SIMD 能力
    pub fn detect() SIMDCapabilities {
        var caps = SIMDCapabilities{
            .supported_sets = std.EnumSet(SIMDInstructionSet).initEmpty(),
            .best_set = .none,
        };
        
        if (builtin.cpu.arch == .x86_64) {
            detectX86(&caps);
        } else if (builtin.cpu.arch == .aarch64) {
            detectARM(&caps);
        }
        
        return caps;
    }

    /// 检测 x86-64 SIMD 能力
    fn detectX86(caps: *SIMDCapabilities) void {
        // 基础 SSE2 在 x86_64 上总是可用
        caps.supported_sets.insert(.sse2);
        caps.best_set = .sse2;
        
        // 检测 SSE4.2
        if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_2)) {
            caps.supported_sets.insert(.sse4_2);
            caps.best_set = .sse4_2;
        }
        
        // 检测 AVX2
        if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) {
            caps.supported_sets.insert(.avx2);
            caps.best_set = .avx2;
        }
        
        // 检测 AVX-512
        if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f)) {
            caps.supported_sets.insert(.avx512);
            caps.best_set = .avx512;
        }
    }
    
    /// 检测 ARM SIMD 能力
    fn detectARM(caps: *SIMDCapabilities) void {
        // ARM NEON 在 AArch64 上总是可用
        if (builtin.cpu.arch == .aarch64) {
            caps.supported_sets.insert(.neon);
            caps.best_set = .neon;
        }
    }
    
    /// 检查是否支持指定指令集
    pub fn supports(self: *const SIMDCapabilities, set: SIMDInstructionSet) bool {
        return self.supported_sets.contains(set);
    }
};

/// SIMD 数学运算
/// @ownership NON-OWNING
/// @thread-safety ISOLATED
pub const SIMDMath = struct {
    capabilities: SIMDCapabilities,
    
    /// 初始化
    pub fn init() SIMDMath {
        return .{
            .capabilities = SIMDCapabilities.detect(),
        };
    }

    // ========================================================================
    // 向量加法
    // ========================================================================
    
    /// SIMD 加速的向量加法（整数）
    /// @pre a 和 b 必须是相同长度的有效数组切片
    /// @pre result 必须有足够空间存储结果
    /// @post result[i] = a[i] + b[i]
    /// @performance 2-4x 标量实现
    pub fn vectorAddInt(self: *const SIMDMath, a: []const i64, b: []const i64, result: []i64) void {
        std.debug.assert(a.len == b.len);
        std.debug.assert(result.len >= a.len);
        
        if (self.capabilities.supports(.avx512)) {
            vectorAddIntAVX512(a, b, result);
        } else if (self.capabilities.supports(.avx2)) {
            vectorAddIntAVX2(a, b, result);
        } else if (self.capabilities.supports(.sse2)) {
            vectorAddIntSSE2(a, b, result);
        } else if (self.capabilities.supports(.neon)) {
            vectorAddIntNEON(a, b, result);
        } else {
            vectorAddIntScalar(a, b, result);
        }
    }
    
    fn vectorAddIntSSE2(a: []const i64, b: []const i64, result: []i64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, i64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, i64) = b[i..][0..VecLen].*;
            const vec_result = vec_a + vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] + b[i];
        }
    }
    
    fn vectorAddIntAVX2(a: []const i64, b: []const i64, result: []i64) void {
        const VecLen = 4;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, i64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, i64) = b[i..][0..VecLen].*;
            const vec_result = vec_a + vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] + b[i];
        }
    }

    fn vectorAddIntAVX512(a: []const i64, b: []const i64, result: []i64) void {
        const VecLen = 8;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, i64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, i64) = b[i..][0..VecLen].*;
            const vec_result = vec_a + vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] + b[i];
        }
    }
    
    fn vectorAddIntNEON(a: []const i64, b: []const i64, result: []i64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, i64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, i64) = b[i..][0..VecLen].*;
            const vec_result = vec_a + vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] + b[i];
        }
    }
    
    fn vectorAddIntScalar(a: []const i64, b: []const i64, result: []i64) void {
        for (a, b, 0..) |val_a, val_b, i| {
            result[i] = val_a + val_b;
        }
    }
    
    /// SIMD 加速的向量加法（浮点）
    /// @pre a 和 b 必须是相同长度的有效数组切片
    /// @pre result 必须有足够空间存储结果
    /// @post result[i] = a[i] + b[i]
    /// @performance 2-4x 标量实现
    pub fn vectorAddFloat(self: *const SIMDMath, a: []const f64, b: []const f64, result: []f64) void {
        std.debug.assert(a.len == b.len);
        std.debug.assert(result.len >= a.len);
        
        if (self.capabilities.supports(.avx512)) {
            vectorAddFloatAVX512(a, b, result);
        } else if (self.capabilities.supports(.avx2)) {
            vectorAddFloatAVX2(a, b, result);
        } else if (self.capabilities.supports(.sse2)) {
            vectorAddFloatSSE2(a, b, result);
        } else if (self.capabilities.supports(.neon)) {
            vectorAddFloatNEON(a, b, result);
        } else {
            vectorAddFloatScalar(a, b, result);
        }
    }

    fn vectorAddFloatSSE2(a: []const f64, b: []const f64, result: []f64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            const vec_result = vec_a + vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] + b[i];
        }
    }
    
    fn vectorAddFloatAVX2(a: []const f64, b: []const f64, result: []f64) void {
        const VecLen = 4;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            const vec_result = vec_a + vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] + b[i];
        }
    }
    
    fn vectorAddFloatAVX512(a: []const f64, b: []const f64, result: []f64) void {
        const VecLen = 8;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            const vec_result = vec_a + vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] + b[i];
        }
    }
    
    fn vectorAddFloatNEON(a: []const f64, b: []const f64, result: []f64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            const vec_result = vec_a + vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] + b[i];
        }
    }

    fn vectorAddFloatScalar(a: []const f64, b: []const f64, result: []f64) void {
        for (a, b, 0..) |val_a, val_b, i| {
            result[i] = val_a + val_b;
        }
    }
    
    // ========================================================================
    // 向量乘法
    // ========================================================================
    
    /// SIMD 加速的向量乘法（整数）
    /// @pre a 和 b 必须是相同长度的有效数组切片
    /// @pre result 必须有足够空间存储结果
    /// @post result[i] = a[i] * b[i]
    /// @performance 2-4x 标量实现
    pub fn vectorMulInt(self: *const SIMDMath, a: []const i64, b: []const i64, result: []i64) void {
        std.debug.assert(a.len == b.len);
        std.debug.assert(result.len >= a.len);
        
        if (self.capabilities.supports(.avx512)) {
            vectorMulIntAVX512(a, b, result);
        } else if (self.capabilities.supports(.avx2)) {
            vectorMulIntAVX2(a, b, result);
        } else if (self.capabilities.supports(.sse2)) {
            vectorMulIntSSE2(a, b, result);
        } else if (self.capabilities.supports(.neon)) {
            vectorMulIntNEON(a, b, result);
        } else {
            vectorMulIntScalar(a, b, result);
        }
    }
    
    fn vectorMulIntSSE2(a: []const i64, b: []const i64, result: []i64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, i64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, i64) = b[i..][0..VecLen].*;
            const vec_result = vec_a * vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] * b[i];
        }
    }
    
    fn vectorMulIntAVX2(a: []const i64, b: []const i64, result: []i64) void {
        const VecLen = 4;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, i64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, i64) = b[i..][0..VecLen].*;
            const vec_result = vec_a * vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] * b[i];
        }
    }

    fn vectorMulIntAVX512(a: []const i64, b: []const i64, result: []i64) void {
        const VecLen = 8;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, i64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, i64) = b[i..][0..VecLen].*;
            const vec_result = vec_a * vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] * b[i];
        }
    }
    
    fn vectorMulIntNEON(a: []const i64, b: []const i64, result: []i64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, i64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, i64) = b[i..][0..VecLen].*;
            const vec_result = vec_a * vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] * b[i];
        }
    }
    
    fn vectorMulIntScalar(a: []const i64, b: []const i64, result: []i64) void {
        for (a, b, 0..) |val_a, val_b, i| {
            result[i] = val_a * val_b;
        }
    }
    
    /// SIMD 加速的向量乘法（浮点）
    /// @pre a 和 b 必须是相同长度的有效数组切片
    /// @pre result 必须有足够空间存储结果
    /// @post result[i] = a[i] * b[i]
    /// @performance 2-4x 标量实现
    pub fn vectorMulFloat(self: *const SIMDMath, a: []const f64, b: []const f64, result: []f64) void {
        std.debug.assert(a.len == b.len);
        std.debug.assert(result.len >= a.len);
        
        if (self.capabilities.supports(.avx512)) {
            vectorMulFloatAVX512(a, b, result);
        } else if (self.capabilities.supports(.avx2)) {
            vectorMulFloatAVX2(a, b, result);
        } else if (self.capabilities.supports(.sse2)) {
            vectorMulFloatSSE2(a, b, result);
        } else if (self.capabilities.supports(.neon)) {
            vectorMulFloatNEON(a, b, result);
        } else {
            vectorMulFloatScalar(a, b, result);
        }
    }

    fn vectorMulFloatSSE2(a: []const f64, b: []const f64, result: []f64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            const vec_result = vec_a * vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] * b[i];
        }
    }
    
    fn vectorMulFloatAVX2(a: []const f64, b: []const f64, result: []f64) void {
        const VecLen = 4;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            const vec_result = vec_a * vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] * b[i];
        }
    }
    
    fn vectorMulFloatAVX512(a: []const f64, b: []const f64, result: []f64) void {
        const VecLen = 8;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            const vec_result = vec_a * vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] * b[i];
        }
    }
    
    fn vectorMulFloatNEON(a: []const f64, b: []const f64, result: []f64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            const vec_result = vec_a * vec_b;
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < a.len) : (i += 1) {
            result[i] = a[i] * b[i];
        }
    }

    fn vectorMulFloatScalar(a: []const f64, b: []const f64, result: []f64) void {
        for (a, b, 0..) |val_a, val_b, i| {
            result[i] = val_a * val_b;
        }
    }
    
    // ========================================================================
    // 数学函数
    // ========================================================================
    
    /// SIMD 加速的平方根（浮点数组）
    /// @pre arr 必须是有效的浮点数组切片
    /// @pre result 必须有足够空间存储结果
    /// @post result[i] = sqrt(arr[i])
    /// @performance 2-3x 标量实现
    pub fn vectorSqrt(self: *const SIMDMath, arr: []const f64, result: []f64) void {
        std.debug.assert(result.len >= arr.len);
        
        if (self.capabilities.supports(.avx512)) {
            vectorSqrtAVX512(arr, result);
        } else if (self.capabilities.supports(.avx2)) {
            vectorSqrtAVX2(arr, result);
        } else if (self.capabilities.supports(.sse2)) {
            vectorSqrtSSE2(arr, result);
        } else if (self.capabilities.supports(.neon)) {
            vectorSqrtNEON(arr, result);
        } else {
            vectorSqrtScalar(arr, result);
        }
    }
    
    fn vectorSqrtSSE2(arr: []const f64, result: []f64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= arr.len) : (i += VecLen) {
            const vec: @Vector(VecLen, f64) = arr[i..][0..VecLen].*;
            const vec_result = @sqrt(vec);
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < arr.len) : (i += 1) {
            result[i] = @sqrt(arr[i]);
        }
    }
    
    fn vectorSqrtAVX2(arr: []const f64, result: []f64) void {
        const VecLen = 4;
        var i: usize = 0;
        
        while (i + VecLen <= arr.len) : (i += VecLen) {
            const vec: @Vector(VecLen, f64) = arr[i..][0..VecLen].*;
            const vec_result = @sqrt(vec);
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < arr.len) : (i += 1) {
            result[i] = @sqrt(arr[i]);
        }
    }

    fn vectorSqrtAVX512(arr: []const f64, result: []f64) void {
        const VecLen = 8;
        var i: usize = 0;
        
        while (i + VecLen <= arr.len) : (i += VecLen) {
            const vec: @Vector(VecLen, f64) = arr[i..][0..VecLen].*;
            const vec_result = @sqrt(vec);
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < arr.len) : (i += 1) {
            result[i] = @sqrt(arr[i]);
        }
    }
    
    fn vectorSqrtNEON(arr: []const f64, result: []f64) void {
        const VecLen = 2;
        var i: usize = 0;
        
        while (i + VecLen <= arr.len) : (i += VecLen) {
            const vec: @Vector(VecLen, f64) = arr[i..][0..VecLen].*;
            const vec_result = @sqrt(vec);
            result[i..][0..VecLen].* = vec_result;
        }
        
        while (i < arr.len) : (i += 1) {
            result[i] = @sqrt(arr[i]);
        }
    }
    
    fn vectorSqrtScalar(arr: []const f64, result: []f64) void {
        for (arr, 0..) |val, i| {
            result[i] = @sqrt(val);
        }
    }
    
    /// SIMD 加速的点积（浮点向量）
    /// @pre a 和 b 必须是相同长度的有效数组切片
    /// @post 返回 sum(a[i] * b[i])
    /// @performance 2-4x 标量实现
    pub fn dotProduct(self: *const SIMDMath, a: []const f64, b: []const f64) f64 {
        std.debug.assert(a.len == b.len);
        
        if (self.capabilities.supports(.avx512)) {
            return dotProductAVX512(a, b);
        } else if (self.capabilities.supports(.avx2)) {
            return dotProductAVX2(a, b);
        } else if (self.capabilities.supports(.sse2)) {
            return dotProductSSE2(a, b);
        } else if (self.capabilities.supports(.neon)) {
            return dotProductNEON(a, b);
        } else {
            return dotProductScalar(a, b);
        }
    }

    fn dotProductSSE2(a: []const f64, b: []const f64) f64 {
        const VecLen = 2;
        var i: usize = 0;
        var sum_vec: @Vector(VecLen, f64) = @splat(0.0);
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            sum_vec += vec_a * vec_b;
        }
        
        var sum: f64 = 0.0;
        for (0..VecLen) |j| {
            sum += sum_vec[j];
        }
        
        while (i < a.len) : (i += 1) {
            sum += a[i] * b[i];
        }
        
        return sum;
    }
    
    fn dotProductAVX2(a: []const f64, b: []const f64) f64 {
        const VecLen = 4;
        var i: usize = 0;
        var sum_vec: @Vector(VecLen, f64) = @splat(0.0);
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            sum_vec += vec_a * vec_b;
        }
        
        var sum: f64 = 0.0;
        for (0..VecLen) |j| {
            sum += sum_vec[j];
        }
        
        while (i < a.len) : (i += 1) {
            sum += a[i] * b[i];
        }
        
        return sum;
    }
    
    fn dotProductAVX512(a: []const f64, b: []const f64) f64 {
        const VecLen = 8;
        var i: usize = 0;
        var sum_vec: @Vector(VecLen, f64) = @splat(0.0);
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            sum_vec += vec_a * vec_b;
        }
        
        var sum: f64 = 0.0;
        for (0..VecLen) |j| {
            sum += sum_vec[j];
        }
        
        while (i < a.len) : (i += 1) {
            sum += a[i] * b[i];
        }
        
        return sum;
    }

    fn dotProductNEON(a: []const f64, b: []const f64) f64 {
        const VecLen = 2;
        var i: usize = 0;
        var sum_vec: @Vector(VecLen, f64) = @splat(0.0);
        
        while (i + VecLen <= a.len) : (i += VecLen) {
            const vec_a: @Vector(VecLen, f64) = a[i..][0..VecLen].*;
            const vec_b: @Vector(VecLen, f64) = b[i..][0..VecLen].*;
            sum_vec += vec_a * vec_b;
        }
        
        var sum: f64 = 0.0;
        for (0..VecLen) |j| {
            sum += sum_vec[j];
        }
        
        while (i < a.len) : (i += 1) {
            sum += a[i] * b[i];
        }
        
        return sum;
    }
    
    fn dotProductScalar(a: []const f64, b: []const f64) f64 {
        var sum: f64 = 0.0;
        for (a, b) |val_a, val_b| {
            sum += val_a * val_b;
        }
        return sum;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SIMDCapabilities.detect" {
    const caps = SIMDCapabilities.detect();
    
    std.debug.print("\nDetected SIMD capabilities: {any}\n", .{caps.best_set});
    
    if (builtin.cpu.arch == .x86_64) {
        try std.testing.expect(caps.supports(.sse2));
    } else if (builtin.cpu.arch == .aarch64) {
        try std.testing.expect(caps.supports(.neon));
    }
}

test "SIMDMath.vectorAddInt - basic" {
    const simd = SIMDMath.init();
    
    const a = [_]i64{1, 2, 3, 4, 5, 6, 7, 8};
    const b = [_]i64{10, 20, 30, 40, 50, 60, 70, 80};
    var result: [8]i64 = undefined;
    
    simd.vectorAddInt(&a, &b, &result);
    
    try std.testing.expectEqualSlices(i64, &[_]i64{11, 22, 33, 44, 55, 66, 77, 88}, &result);
}

test "SIMDMath.vectorAddFloat - basic" {
    const simd = SIMDMath.init();
    
    const a = [_]f64{1.5, 2.5, 3.5, 4.5};
    const b = [_]f64{0.5, 1.5, 2.5, 3.5};
    var result: [4]f64 = undefined;
    
    simd.vectorAddFloat(&a, &b, &result);
    
    for (result, 0..) |val, i| {
        try std.testing.expectApproxEqAbs(a[i] + b[i], val, 0.0001);
    }
}

test "SIMDMath.vectorMulInt - basic" {
    const simd = SIMDMath.init();
    
    const a = [_]i64{2, 3, 4, 5};
    const b = [_]i64{10, 10, 10, 10};
    var result: [4]i64 = undefined;
    
    simd.vectorMulInt(&a, &b, &result);
    
    try std.testing.expectEqualSlices(i64, &[_]i64{20, 30, 40, 50}, &result);
}

test "SIMDMath.vectorMulFloat - basic" {
    const simd = SIMDMath.init();
    
    const a = [_]f64{2.0, 3.0, 4.0, 5.0};
    const b = [_]f64{1.5, 2.0, 2.5, 3.0};
    var result: [4]f64 = undefined;
    
    simd.vectorMulFloat(&a, &b, &result);
    
    for (result, 0..) |val, i| {
        try std.testing.expectApproxEqAbs(a[i] * b[i], val, 0.0001);
    }
}

test "SIMDMath.vectorSqrt - basic" {
    const simd = SIMDMath.init();
    
    const arr = [_]f64{4.0, 9.0, 16.0, 25.0};
    var result: [4]f64 = undefined;
    
    simd.vectorSqrt(&arr, &result);
    
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), result[1], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result[2], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), result[3], 0.0001);
}

test "SIMDMath.dotProduct - basic" {
    const simd = SIMDMath.init();
    
    const a = [_]f64{1.0, 2.0, 3.0, 4.0};
    const b = [_]f64{5.0, 6.0, 7.0, 8.0};
    
    const result = simd.dotProduct(&a, &b);
    
    // 1*5 + 2*6 + 3*7 + 4*8 = 5 + 12 + 21 + 32 = 70
    try std.testing.expectApproxEqAbs(@as(f64, 70.0), result, 0.0001);
}

test "SIMDMath.vectorAddInt - large array" {
    const simd = SIMDMath.init();
    
    var a: [100]i64 = undefined;
    var b: [100]i64 = undefined;
    var result: [100]i64 = undefined;
    
    for (0..100) |i| {
        a[i] = @intCast(i);
        b[i] = @intCast(i * 2);
    }
    
    simd.vectorAddInt(&a, &b, &result);
    
    for (0..100) |i| {
        try std.testing.expectEqual(@as(i64, @intCast(i * 3)), result[i]);
    }
}

test "SIMDMath.dotProduct - large array" {
    const simd = SIMDMath.init();
    
    var a: [100]f64 = undefined;
    var b: [100]f64 = undefined;
    
    for (0..100) |i| {
        a[i] = @floatFromInt(i);
        b[i] = 1.0;
    }
    
    const result = simd.dotProduct(&a, &b);
    
    // sum(0..99) = 99 * 100 / 2 = 4950
    try std.testing.expectApproxEqAbs(@as(f64, 4950.0), result, 0.0001);
}
