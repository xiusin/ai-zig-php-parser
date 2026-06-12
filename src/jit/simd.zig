const std = @import("std");

/// SIMD 指令集类型
pub const SIMDInstructionSet = enum {
    none,
    sse,
    sse2,
    sse3,
    ssse3,
    sse4_1,
    sse4_2,
    avx,
    avx2,
    avx512f,
    avx512dq,
    avx512bw,
    avx512vl,
};

/// SIMD 能力检测器
/// @thread-safety ISOLATED (单线程初始化)
/// @ownership NON-OWNING
pub const SIMDCapabilities = struct {
    // 支持的指令集
    supported_sets: std.EnumSet(SIMDInstructionSet),
    
    // 最佳指令集（性能最高）
    best_set: SIMDInstructionSet,
    
    // CPU 信息
    vendor: []const u8,
    brand: []const u8,
    
    /// 检测 CPU SIMD 能力
    /// @post 返回检测到的 SIMD 能力
    pub fn detect() SIMDCapabilities {
        var caps = SIMDCapabilities{
            .supported_sets = std.EnumSet(SIMDInstructionSet).initEmpty(),
            .best_set = .none,
            .vendor = "",
            .brand = "",
        };
        
        // 使用 CPUID 指令检测
        if (@import("builtin").target.cpu.arch == .x86_64) {
            detectX86(&caps);
        } else if (@import("builtin").target.cpu.arch == .aarch64) {
            detectARM(&caps);
        }
        
        return caps;
    }

    
    /// 检测 x86-64 SIMD 能力
    fn detectX86(caps: *SIMDCapabilities) void {
        // CPUID 功能检测
        var eax: u32 = undefined;
        var ebx: u32 = undefined;
        var ecx: u32 = undefined;
        var edx: u32 = undefined;
        
        // 检查 CPUID 是否可用
        if (!cpuidAvailable()) return;
        
        // 获取最大功能号
        cpuid(0, &eax, &ebx, &ecx, &edx);
        const max_func = eax;
        
        if (max_func >= 1) {
            // 功能标志
            cpuid(1, &eax, &ebx, &ecx, &edx);
            
            // SSE
            if ((edx & (1 << 25)) != 0) {
                caps.supported_sets.insert(.sse);
                caps.best_set = .sse;
            }
            
            // SSE2
            if ((edx & (1 << 26)) != 0) {
                caps.supported_sets.insert(.sse2);
                caps.best_set = .sse2;
            }
            
            // SSE3
            if ((ecx & (1 << 0)) != 0) {
                caps.supported_sets.insert(.sse3);
                caps.best_set = .sse3;
            }
            
            // SSSE3
            if ((ecx & (1 << 9)) != 0) {
                caps.supported_sets.insert(.ssse3);
                caps.best_set = .ssse3;
            }
            
            // SSE4.1
            if ((ecx & (1 << 19)) != 0) {
                caps.supported_sets.insert(.sse4_1);
                caps.best_set = .sse4_1;
            }
            
            // SSE4.2
            if ((ecx & (1 << 20)) != 0) {
                caps.supported_sets.insert(.sse4_2);
                caps.best_set = .sse4_2;
            }
            
            // AVX
            if ((ecx & (1 << 28)) != 0) {
                caps.supported_sets.insert(.avx);
                caps.best_set = .avx;
            }
        }
        
        if (max_func >= 7) {
            // 扩展功能标志
            cpuid(7, &eax, &ebx, &ecx, &edx);
            
            // AVX2
            if ((ebx & (1 << 5)) != 0) {
                caps.supported_sets.insert(.avx2);
                caps.best_set = .avx2;
            }
            
            // AVX-512 Foundation
            if ((ebx & (1 << 16)) != 0) {
                caps.supported_sets.insert(.avx512f);
                caps.best_set = .avx512f;
            }
            
            // AVX-512 DQ
            if ((ebx & (1 << 17)) != 0) {
                caps.supported_sets.insert(.avx512dq);
                caps.best_set = .avx512dq;
            }
            
            // AVX-512 BW
            if ((ebx & (1 << 30)) != 0) {
                caps.supported_sets.insert(.avx512bw);
                caps.best_set = .avx512bw;
            }
            
            // AVX-512 VL
            if ((ebx & (1 << 31)) != 0) {
                caps.supported_sets.insert(.avx512vl);
                caps.best_set = .avx512vl;
            }
        }
    }
    
    /// 检测 ARM SIMD 能力
    fn detectARM(caps: *SIMDCapabilities) void {
        // ARM NEON 总是可用在 AArch64
        if (@import("builtin").target.cpu.arch == .aarch64) {
            caps.supported_sets.insert(.sse2); // 映射到等效能力
            caps.best_set = .sse2;
        }
    }
    
    /// 检查 CPUID 是否可用
    fn cpuidAvailable() bool {
        if (@import("builtin").target.cpu.arch != .x86_64) return false;
        
        // 在 x86-64 上 CPUID 总是可用
        return true;
    }
    
    /// 执行 CPUID 指令
    fn cpuid(leaf: u32, eax: *u32, ebx: *u32, ecx: *u32, edx: *u32) void {
        if (@import("builtin").target.cpu.arch != .x86_64) return;
        
        // 使用内联汇编执行 CPUID
        var eax_val: u32 = leaf;
        var ebx_val: u32 = 0;
        var ecx_val: u32 = 0;
        var edx_val: u32 = 0;
        
        asm volatile (
            \\cpuid
            : [eax] "={eax}" (eax_val),
              [ebx] "={ebx}" (ebx_val),
              [ecx] "={ecx}" (ecx_val),
              [edx] "={edx}" (edx_val)
            : [leaf] "{eax}" (eax_val),
              [subleaf] "{ecx}" (ecx_val)
        );
        
        eax.* = eax_val;
        ebx.* = ebx_val;
        ecx.* = ecx_val;
        edx.* = edx_val;
    }
    
    /// 检查是否支持指定指令集
    pub fn supports(self: *const SIMDCapabilities, set: SIMDInstructionSet) bool {
        return self.supported_sets.contains(set);
    }
    
    /// 获取最佳指令集
    pub fn getBest(self: *const SIMDCapabilities) SIMDInstructionSet {
        return self.best_set;
    }
};


/// SIMD 向量化器
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED
pub const SIMDVectorizer = struct {
    allocator: std.mem.Allocator,
    capabilities: SIMDCapabilities,
    
    /// 初始化向量化器
    /// @pre allocator 必须有效
    /// @post 返回初始化的向量化器
    pub fn init(allocator: std.mem.Allocator) SIMDVectorizer {
        return .{
            .allocator = allocator,
            .capabilities = SIMDCapabilities.detect(),
        };
    }
    
    /// 向量化整数加法
    /// @pre dst, src1, src2 长度必须相同
    /// @post dst[i] = src1[i] + src2[i] for all i
    pub fn addInt32(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        std.debug.assert(dst.len == src1.len);
        std.debug.assert(dst.len == src2.len);
        
        // 自适应选择最佳实现
        if (self.capabilities.supports(.avx512f)) {
            self.addInt32AVX512(dst, src1, src2);
        } else if (self.capabilities.supports(.avx2)) {
            self.addInt32AVX2(dst, src1, src2);
        } else if (self.capabilities.supports(.sse2)) {
            self.addInt32SSE2(dst, src1, src2);
        } else {
            self.addInt32Scalar(dst, src1, src2);
        }
    }
    
    /// SSE2 整数加法
    fn addInt32SSE2(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        _ = self;
        const vec_size = 4; // SSE2 处理 4 个 i32
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            // 加载向量
            const v1 = @as(@Vector(4, i32), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(4, i32), src2[offset..][0..vec_size].*);
            
            // 向量加法
            const result = v1 + v2;
            
            // 存储结果
            dst[offset..][0..vec_size].* = result;
        }
        
        // 处理剩余元素
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] + src2[offset + j];
        }
    }
    
    /// AVX2 整数加法
    fn addInt32AVX2(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        _ = self;
        const vec_size = 8; // AVX2 处理 8 个 i32
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            // 加载向量
            const v1 = @as(@Vector(8, i32), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(8, i32), src2[offset..][0..vec_size].*);
            
            // 向量加法
            const result = v1 + v2;
            
            // 存储结果
            dst[offset..][0..vec_size].* = result;
        }
        
        // 处理剩余元素
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] + src2[offset + j];
        }
    }
    
    /// AVX-512 整数加法
    fn addInt32AVX512(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        _ = self;
        const vec_size = 16; // AVX-512 处理 16 个 i32
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            // 加载向量
            const v1 = @as(@Vector(16, i32), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(16, i32), src2[offset..][0..vec_size].*);
            
            // 向量加法
            const result = v1 + v2;
            
            // 存储结果
            dst[offset..][0..vec_size].* = result;
        }
        
        // 处理剩余元素
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] + src2[offset + j];
        }
    }
    
    /// 标量整数加法（回退实现）
    fn addInt32Scalar(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        _ = self;
        for (dst, src1, src2) |*d, s1, s2| {
            d.* = s1 + s2;
        }
    }

    
    /// 向量化浮点加法
    /// @pre dst, src1, src2 长度必须相同
    /// @post dst[i] = src1[i] + src2[i] for all i
    pub fn addFloat64(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        std.debug.assert(dst.len == src1.len);
        std.debug.assert(dst.len == src2.len);
        
        // 自适应选择最佳实现
        if (self.capabilities.supports(.avx512f)) {
            self.addFloat64AVX512(dst, src1, src2);
        } else if (self.capabilities.supports(.avx)) {
            self.addFloat64AVX(dst, src1, src2);
        } else if (self.capabilities.supports(.sse2)) {
            self.addFloat64SSE2(dst, src1, src2);
        } else {
            self.addFloat64Scalar(dst, src1, src2);
        }
    }
    
    /// SSE2 浮点加法
    fn addFloat64SSE2(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        _ = self;
        const vec_size = 2; // SSE2 处理 2 个 f64
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            const v1 = @as(@Vector(2, f64), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(2, f64), src2[offset..][0..vec_size].*);
            const result = v1 + v2;
            
            dst[offset..][0..vec_size].* = result;
        }
        
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] + src2[offset + j];
        }
    }
    
    /// AVX 浮点加法
    fn addFloat64AVX(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        _ = self;
        const vec_size = 4; // AVX 处理 4 个 f64
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            const v1 = @as(@Vector(4, f64), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(4, f64), src2[offset..][0..vec_size].*);
            const result = v1 + v2;
            
            dst[offset..][0..vec_size].* = result;
        }
        
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] + src2[offset + j];
        }
    }
    
    /// AVX-512 浮点加法
    fn addFloat64AVX512(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        _ = self;
        const vec_size = 8; // AVX-512 处理 8 个 f64
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            const v1 = @as(@Vector(8, f64), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(8, f64), src2[offset..][0..vec_size].*);
            const result = v1 + v2;
            
            dst[offset..][0..vec_size].* = result;
        }
        
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] + src2[offset + j];
        }
    }
    
    /// 标量浮点加法（回退实现）
    fn addFloat64Scalar(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        _ = self;
        for (dst, src1, src2) |*d, s1, s2| {
            d.* = s1 + s2;
        }
    }
    
    /// 向量化整数乘法
    /// @pre dst, src1, src2 长度必须相同
    /// @post dst[i] = src1[i] * src2[i] for all i
    pub fn mulInt32(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        std.debug.assert(dst.len == src1.len);
        std.debug.assert(dst.len == src2.len);
        
        if (self.capabilities.supports(.avx2)) {
            self.mulInt32AVX2(dst, src1, src2);
        } else if (self.capabilities.supports(.sse4_1)) {
            self.mulInt32SSE41(dst, src1, src2);
        } else {
            self.mulInt32Scalar(dst, src1, src2);
        }
    }
    
    /// SSE4.1 整数乘法
    fn mulInt32SSE41(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        _ = self;
        const vec_size = 4;
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            const v1 = @as(@Vector(4, i32), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(4, i32), src2[offset..][0..vec_size].*);
            const result = v1 * v2;
            
            dst[offset..][0..vec_size].* = result;
        }
        
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] * src2[offset + j];
        }
    }
    
    /// AVX2 整数乘法
    fn mulInt32AVX2(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        _ = self;
        const vec_size = 8;
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            const v1 = @as(@Vector(8, i32), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(8, i32), src2[offset..][0..vec_size].*);
            const result = v1 * v2;
            
            dst[offset..][0..vec_size].* = result;
        }
        
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] * src2[offset + j];
        }
    }
    
    /// 标量整数乘法
    fn mulInt32Scalar(
        self: *SIMDVectorizer,
        dst: []i32,
        src1: []const i32,
        src2: []const i32
    ) void {
        _ = self;
        for (dst, src1, src2) |*d, s1, s2| {
            d.* = s1 * s2;
        }
    }
    
    /// 向量化浮点乘法
    /// @pre dst, src1, src2 长度必须相同
    /// @post dst[i] = src1[i] * src2[i] for all i
    pub fn mulFloat64(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        std.debug.assert(dst.len == src1.len);
        std.debug.assert(dst.len == src2.len);
        
        if (self.capabilities.supports(.avx)) {
            self.mulFloat64AVX(dst, src1, src2);
        } else if (self.capabilities.supports(.sse2)) {
            self.mulFloat64SSE2(dst, src1, src2);
        } else {
            self.mulFloat64Scalar(dst, src1, src2);
        }
    }
    
    /// SSE2 浮点乘法
    fn mulFloat64SSE2(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        _ = self;
        const vec_size = 2;
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            const v1 = @as(@Vector(2, f64), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(2, f64), src2[offset..][0..vec_size].*);
            const result = v1 * v2;
            
            dst[offset..][0..vec_size].* = result;
        }
        
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] * src2[offset + j];
        }
    }
    
    /// AVX 浮点乘法
    fn mulFloat64AVX(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        _ = self;
        const vec_size = 4;
        const vec_count = dst.len / vec_size;
        const remainder = dst.len % vec_size;
        
        var i: usize = 0;
        while (i < vec_count) : (i += 1) {
            const offset = i * vec_size;
            
            const v1 = @as(@Vector(4, f64), src1[offset..][0..vec_size].*);
            const v2 = @as(@Vector(4, f64), src2[offset..][0..vec_size].*);
            const result = v1 * v2;
            
            dst[offset..][0..vec_size].* = result;
        }
        
        const offset = vec_count * vec_size;
        for (0..remainder) |j| {
            dst[offset + j] = src1[offset + j] * src2[offset + j];
        }
    }
    
    /// 标量浮点乘法
    fn mulFloat64Scalar(
        self: *SIMDVectorizer,
        dst: []f64,
        src1: []const f64,
        src2: []const f64
    ) void {
        _ = self;
        for (dst, src1, src2) |*d, s1, s2| {
            d.* = s1 * s2;
        }
    }
};
