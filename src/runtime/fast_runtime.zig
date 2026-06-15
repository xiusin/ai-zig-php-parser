//! 性能优化集成模块
//! 统一导出所有优化组件，提供配置和基准测试
const time_compat = @import("time_compat.zig");

const std = @import("std");

// 导出所有优化模块
pub const fast_pool = @import("fast_pool.zig");
pub const fast_string = @import("fast_string.zig");
pub const fast_value = @import("fast_value.zig");
pub const simd_ops = @import("simd_ops.zig");

// 类型别名
pub const SlabAllocator = fast_pool.SlabAllocator;
pub const BumpAllocator = fast_pool.BumpAllocator;
pub const MultiPool = fast_pool.MultiPool;
pub const PoolManager = fast_pool.PoolManager;

pub const StringPool = fast_string.StringPool;
pub const SSOString = fast_string.SSOString;
pub const fnv1a = fast_string.fnv1a;

pub const FastValue = fast_value.FastValue;
pub const FastOps = fast_value.FastOps;
pub const ValueStack = fast_value.ValueStack;
pub const small_int_cache = fast_value.small_int_cache;

pub const SimdString = simd_ops.SimdString;
pub const SimdArray = simd_ops.SimdArray;
pub const BranchOpt = simd_ops.BranchOpt;
pub const Prefetch = simd_ops.Prefetch;
pub const FastMem = simd_ops.FastMem;
pub const CACHE_LINE = simd_ops.CACHE_LINE;

// ============================================================================
// 优化配置
// ============================================================================

pub const OptLevel = enum {
    /// 无优化（调试用）
    none,
    /// 基础优化
    basic,
    /// 完全优化
    full,
    /// 激进优化（可能牺牲精度）
    aggressive,
};

pub const OptConfig = struct {
    level: OptLevel = .full,
    enable_simd: bool = true,
    enable_string_pool: bool = true,
    enable_small_int_cache: bool = true,
    enable_type_specialization: bool = true,
    enable_inline_cache: bool = true,
    enable_prefetch: bool = true,

    pub const default = OptConfig{};
    pub const debug = OptConfig{ .level = .none };
    pub const release = OptConfig{ .level = .full };
};

// ============================================================================
// 基准测试框架
// ============================================================================

pub const Benchmark = struct {
    name: []const u8,
    iterations: u64,
    total_ns: u64,
    min_ns: u64,
    max_ns: u64,

    pub fn run(name: []const u8, iterations: u64, func: *const fn () void) Benchmark {
        var total: u64 = 0;
        var min: u64 = std.math.maxInt(u64);
        var max: u64 = 0;

        // 预热
        for (0..10) |_| func();

        // 正式测试
        for (0..iterations) |_| {
            const start = time_compat.nanoTimestamp();
            func();
            const end = time_compat.nanoTimestamp();
            const elapsed = @as(u64, @intCast(end - start));

            total += elapsed;
            min = @min(min, elapsed);
            max = @max(max, elapsed);
        }

        return .{
            .name = name,
            .iterations = iterations,
            .total_ns = total,
            .min_ns = min,
            .max_ns = max,
        };
    }

    pub fn avgNs(self: *const Benchmark) u64 {
        return self.total_ns / self.iterations;
    }

    pub fn opsPerSec(self: *const Benchmark) u64 {
        const avg = self.avgNs();
        if (avg == 0) return 0;
        return 1_000_000_000 / avg;
    }

    pub fn print(self: *const Benchmark) void {
        std.debug.print(
            \\{s}:
            \\  iterations: {}
            \\  avg: {} ns
            \\  min: {} ns
            \\  max: {} ns
            \\  ops/sec: {}
            \\
        , .{
            self.name,
            self.iterations,
            self.avgNs(),
            self.min_ns,
            self.max_ns,
            self.opsPerSec(),
        });
    }
};

// ============================================================================
// 性能统计
// ============================================================================

pub const PerfStats = struct {
    allocations: u64 = 0,
    deallocations: u64 = 0,
    bytes_allocated: u64 = 0,
    string_pool_hits: u64 = 0,
    string_pool_misses: u64 = 0,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,
    type_checks: u64 = 0,
    simd_ops: u64 = 0,

    pub fn reset(self: *PerfStats) void {
        self.* = .{};
    }

    pub fn print(self: *const PerfStats) void {
        std.debug.print(
            \\=== Performance Statistics ===
            \\Allocations: {} ({} bytes)
            \\Deallocations: {}
            \\String Pool: {} hits, {} misses ({d:.1}% hit rate)
            \\Cache: {} hits, {} misses ({d:.1}% hit rate)
            \\Type Checks: {}
            \\SIMD Operations: {}
            \\
        , .{
            self.allocations,
            self.bytes_allocated,
            self.deallocations,
            self.string_pool_hits,
            self.string_pool_misses,
            self.stringPoolHitRate(),
            self.cache_hits,
            self.cache_misses,
            self.cacheHitRate(),
            self.type_checks,
            self.simd_ops,
        });
    }

    fn stringPoolHitRate(self: *const PerfStats) f64 {
        const total = self.string_pool_hits + self.string_pool_misses;
        if (total == 0) return 0;
        return @as(f64, @floatFromInt(self.string_pool_hits)) / @as(f64, @floatFromInt(total)) * 100;
    }

    fn cacheHitRate(self: *const PerfStats) f64 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total)) * 100;
    }
};

/// 全局性能统计
pub var perf_stats = PerfStats{};

// ============================================================================
// 优化运行时
// ============================================================================

pub const OptRuntime = struct {
    allocator: std.mem.Allocator,
    pool_manager: PoolManager,
    string_pool: ?StringPool,
    config: OptConfig,

    pub fn init(allocator: std.mem.Allocator, config: OptConfig) !OptRuntime {
        return .{
            .allocator = allocator,
            .pool_manager = PoolManager.init(allocator),
            .string_pool = if (config.enable_string_pool) try StringPool.init(allocator) else null,
            .config = config,
        };
    }

    pub fn deinit(self: *OptRuntime) void {
        self.pool_manager.deinit();
        if (self.string_pool) |*sp| sp.deinit();
    }

    /// 驻留字符串
    pub fn internString(self: *OptRuntime, s: []const u8) ![]const u8 {
        if (self.string_pool) |*sp| {
            return sp.intern(s);
        }
        return self.allocator.dupe(u8, s);
    }

    /// 临时分配
    pub fn tempAlloc(self: *OptRuntime, comptime T: type, n: usize) ![]T {
        return self.pool_manager.bump.alloc(T, n);
    }

    /// 重置临时分配
    pub fn resetTemp(self: *OptRuntime) void {
        self.pool_manager.resetTemp();
    }
};

// ============================================================================
// 测试
// ============================================================================

test "OptRuntime basic" {
    var rt = try OptRuntime.init(std.testing.allocator, OptConfig.default);
    defer rt.deinit();

    const s1 = try rt.internString("hello");
    const s2 = try rt.internString("hello");
    try std.testing.expect(s1.ptr == s2.ptr);

    const tmp = try rt.tempAlloc(u64, 10);
    tmp[0] = 42;
    rt.resetTemp();
}

test "Benchmark" {
    const result = Benchmark.run("noop", 1000, struct {
        fn f() void {}
    }.f);
    _ = result;
}
