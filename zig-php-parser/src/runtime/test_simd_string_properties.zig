//! 属性测试：SIMD 字符串操作正确性
//!
//! Feature: zig-php-performance-optimization
//! Property 34: SIMD 字符串操作正确性
//! 验证：需求 5.6, 9.1, 9.2
//!
//! 对于任意字符串，SIMD 版本的字符串操作结果应该与标量版本完全相同

const std = @import("std");
const testing = std.testing;
const simd_string = @import("simd_string.zig");
const Random = std.Random;

/// 属性测试框架
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: Random,
    iterations: u32,
    
    fn init(allocator: std.mem.Allocator, seed: u64, iterations: u32) PropertyTest {
        var prng = std.Random.DefaultPrng.init(seed);
        return .{
            .allocator = allocator,
            .rng = prng.random(),
            .iterations = iterations,
        };
    }
    
    /// 运行属性测试
    fn run(
        self: *PropertyTest,
        comptime T: type,
        property: fn (T) bool,
        generator: fn (*Random, std.mem.Allocator) anyerror!T,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const input = try generator(&self.rng, self.allocator);
            defer if (@hasDecl(T, "deinit")) input.deinit();
            
            if (property(input)) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed for input: {any}\n", .{input});
            }
        }
        
        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("\nProperty test: {d}/{d} passed ({d:.2}%)\n", .{ passed, self.iterations, success_rate * 100 });
        
        return failed == 0;
    }
};

/// 生成器
const Generator = struct {

    /// 生成随机字符串
    fn genString(rng: *Random, allocator: std.mem.Allocator, max_len: usize) ![]u8 {
        const len = rng.uintLessThan(usize, max_len + 1);
        const str = try allocator.alloc(u8, len);
        
        for (str) |*c| {
            // 生成可打印 ASCII 字符
            c.* = rng.intRangeAtMost(u8, 32, 126);
        }
        
        return str;
    }
    
    /// 生成随机字符串（可能包含零字节）
    fn genStringWithZero(rng: *Random, allocator: std.mem.Allocator, max_len: usize) ![]u8 {
        const len = rng.uintLessThan(usize, max_len + 1);
        const str = try allocator.alloc(u8, len);
        
        for (str) |*c| {
            // 10% 概率生成零字节
            if (rng.uintLessThan(u8, 10) == 0) {
                c.* = 0;
            } else {
                c.* = rng.intRangeAtMost(u8, 32, 126);
            }
        }
        
        return str;
    }
    
    /// 生成字符串对
    fn genStringPair(rng: *Random, allocator: std.mem.Allocator, max_len: usize) !struct { s1: []u8, s2: []u8 } {
        const s1 = try genString(rng, allocator, max_len);
        const s2 = try genString(rng, allocator, max_len);
        return .{ .s1 = s1, .s2 = s2 };
    }
    
    /// 生成 haystack 和 needle
    fn genHaystackNeedle(rng: *Random, allocator: std.mem.Allocator) !struct { haystack: []u8, needle: []u8 } {
        const haystack = try genString(rng, allocator, 100);
        
        // needle 可能是 haystack 的子串，也可能不是
        const needle = if (rng.boolean() and haystack.len > 0) blk: {
            const start = rng.uintLessThan(usize, haystack.len);
            const max_end = @min(start + 20, haystack.len);
            const end = if (max_end > start) rng.intRangeAtMost(usize, start, max_end) else start;
            const needle_str = try allocator.alloc(u8, end - start);
            @memcpy(needle_str, haystack[start..end]);
            break :blk needle_str;
        } else try genString(rng, allocator, 20);
        
        return .{ .haystack = haystack, .needle = needle };
    }
};

// ============================================================================
// 属性 34：SIMD 字符串操作正确性
// ============================================================================

/// 测试输入：单个字符串
const StrlenInput = struct {
    str: []u8,
    allocator: std.mem.Allocator,
    
    fn deinit(self: StrlenInput) void {
        self.allocator.free(self.str);
    }
};


test "Property 34.1: SIMD strlen correctness" {
    std.debug.print("\n=== Property 34.1: SIMD strlen correctness ===\n", .{});
    std.debug.print("Feature: zig-php-performance-optimization, Property 34\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 12345, 100);
    
    const property = struct {
        fn check(input: StrlenInput) bool {
            const simd = simd_string.SIMDString.init();
            
            // SIMD 版本
            const simd_result = simd.strlen(input.str);
            
            // 标量版本（参考实现）
            const scalar_result = simd_string.SIMDString.strlenScalar(input.str);
            
            // 验证结果相同
            if (simd_result != scalar_result) {
                std.debug.print("MISMATCH: SIMD={d}, Scalar={d}, str_len={d}\n", .{ simd_result, scalar_result, input.str.len });
                return false;
            }
            
            return true;
        }
    }.check;
    
    const generator = struct {
        fn gen(rng: *Random, allocator: std.mem.Allocator) !StrlenInput {
            const str = try Generator.genStringWithZero(rng, allocator, 200);
            return StrlenInput{ .str = str, .allocator = allocator };
        }
    }.gen;
    
    const passed = try pt.run(StrlenInput, property, generator);
    try testing.expect(passed);
}

/// 测试输入：字符串对
const StrcmpInput = struct {
    s1: []u8,
    s2: []u8,
    allocator: std.mem.Allocator,
    
    fn deinit(self: StrcmpInput) void {
        self.allocator.free(self.s1);
        self.allocator.free(self.s2);
    }
};

test "Property 34.2: SIMD strcmp correctness" {
    std.debug.print("\n=== Property 34.2: SIMD strcmp correctness ===\n", .{});
    std.debug.print("Feature: zig-php-performance-optimization, Property 34\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 23456, 100);
    
    const property = struct {
        fn check(input: StrcmpInput) bool {
            const simd = simd_string.SIMDString.init();
            
            // SIMD 版本
            const simd_result = simd.strcmp(input.s1, input.s2);
            
            // 标量版本（参考实现）
            const scalar_result = simd_string.SIMDString.strcmpScalar(input.s1, input.s2);
            
            // 验证结果符号相同（<0, 0, >0）
            const simd_sign = if (simd_result < 0) @as(i32, -1) else if (simd_result > 0) @as(i32, 1) else @as(i32, 0);
            const scalar_sign = if (scalar_result < 0) @as(i32, -1) else if (scalar_result > 0) @as(i32, 1) else @as(i32, 0);
            
            if (simd_sign != scalar_sign) {
                std.debug.print("MISMATCH: SIMD={d}, Scalar={d}\n", .{ simd_result, scalar_result });
                return false;
            }
            
            return true;
        }
    }.check;
    
    const generator = struct {
        fn gen(rng: *Random, allocator: std.mem.Allocator) !StrcmpInput {
            const pair = try Generator.genStringPair(rng, allocator, 150);
            return StrcmpInput{ .s1 = pair.s1, .s2 = pair.s2, .allocator = allocator };
        }
    }.gen;
    
    const passed = try pt.run(StrcmpInput, property, generator);
    try testing.expect(passed);
}


/// 测试输入：haystack 和 needle
const StrposInput = struct {
    haystack: []u8,
    needle: []u8,
    allocator: std.mem.Allocator,
    
    fn deinit(self: StrposInput) void {
        self.allocator.free(self.haystack);
        self.allocator.free(self.needle);
    }
};

test "Property 34.3: SIMD strpos correctness" {
    std.debug.print("\n=== Property 34.3: SIMD strpos correctness ===\n", .{});
    std.debug.print("Feature: zig-php-performance-optimization, Property 34\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 34567, 100);
    
    const property = struct {
        fn check(input: StrposInput) bool {
            const simd = simd_string.SIMDString.init();
            
            // SIMD 版本
            const simd_result = simd.strpos(input.haystack, input.needle);
            
            // 标量版本（参考实现）
            const scalar_result = simd_string.SIMDString.strposScalar(input.haystack, input.needle);
            
            // 验证结果相同
            if (simd_result != scalar_result) {
                std.debug.print("MISMATCH: SIMD={any}, Scalar={any}\n", .{ simd_result, scalar_result });
                std.debug.print("  haystack_len={d}, needle_len={d}\n", .{ input.haystack.len, input.needle.len });
                return false;
            }
            
            return true;
        }
    }.check;
    
    const generator = struct {
        fn gen(rng: *Random, allocator: std.mem.Allocator) !StrposInput {
            const pair = try Generator.genHaystackNeedle(rng, allocator);
            return StrposInput{ .haystack = pair.haystack, .needle = pair.needle, .allocator = allocator };
        }
    }.gen;
    
    const passed = try pt.run(StrposInput, property, generator);
    try testing.expect(passed);
}

test "Property 34.4: SIMD strrpos correctness" {
    std.debug.print("\n=== Property 34.4: SIMD strrpos correctness ===\n", .{});
    std.debug.print("Feature: zig-php-performance-optimization, Property 34\n", .{});
    
    var pt = PropertyTest.init(testing.allocator, 45678, 100);
    
    const property = struct {
        fn check(input: StrposInput) bool {
            const simd = simd_string.SIMDString.init();
            
            // SIMD 版本
            const simd_result = simd.strrpos(input.haystack, input.needle);
            
            // 标量版本（参考实现）
            const scalar_result = simd_string.SIMDString.strrposScalar(input.haystack, input.needle);
            
            // 验证结果相同
            if (simd_result != scalar_result) {
                std.debug.print("MISMATCH: SIMD={any}, Scalar={any}\n", .{ simd_result, scalar_result });
                return false;
            }
            
            return true;
        }
    }.check;
    
    const generator = struct {
        fn gen(rng: *Random, allocator: std.mem.Allocator) !StrposInput {
            const pair = try Generator.genHaystackNeedle(rng, allocator);
            return StrposInput{ .haystack = pair.haystack, .needle = pair.needle, .allocator = allocator };
        }
    }.gen;
    
    const passed = try pt.run(StrposInput, property, generator);
    try testing.expect(passed);
}

// ============================================================================
// 性能基准测试
// ============================================================================

test "Benchmark: strlen performance" {
    std.debug.print("\n=== Benchmark: strlen performance ===\n", .{});
    
    const simd = simd_string.SIMDString.init();
    // 使用更长的字符串以展示 SIMD 优势
    const test_str = "This is a test string that is long enough to trigger SIMD processing and show performance benefits over scalar implementation. " ++
        "We need a sufficiently long string to amortize the overhead of SIMD setup and demonstrate the throughput advantages of vectorized operations. " ++
        "This string should be at least 256 bytes to ensure multiple SIMD iterations are performed during the strlen operation.";
    
    const iterations = 10000;
    
    // SIMD 版本
    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = simd.strlen(test_str);
    }
    const simd_time = timer.read();
    
    // 标量版本
    timer.reset();
    i = 0;
    while (i < iterations) : (i += 1) {
        _ = simd_string.SIMDString.strlenScalar(test_str);
    }
    const scalar_time = timer.read();
    
    const speedup = @as(f64, @floatFromInt(scalar_time)) / @as(f64, @floatFromInt(simd_time));
    
    std.debug.print("SIMD:   {d} ns/op\n", .{simd_time / iterations});
    std.debug.print("Scalar: {d} ns/op\n", .{scalar_time / iterations});
    std.debug.print("Speedup: {d:.2}x\n", .{speedup});
    
    // 对于 strlen，性能提升可能不明显，因为它主要受内存带宽限制
    // 我们期望至少不会变慢（speedup >= 0.8）
    try testing.expect(speedup >= 0.8);
}


test "Benchmark: strcmp performance" {
    std.debug.print("\n=== Benchmark: strcmp performance ===\n", .{});
    
    const simd = simd_string.SIMDString.init();
    const s1 = "This is a test string for comparison that is long enough to show SIMD benefits";
    const s2 = "This is a test string for comparison that is long enough to show SIMD benefits";
    
    const iterations = 10000;
    
    // SIMD 版本
    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = simd.strcmp(s1, s2);
    }
    const simd_time = timer.read();
    
    // 标量版本
    timer.reset();
    i = 0;
    while (i < iterations) : (i += 1) {
        _ = simd_string.SIMDString.strcmpScalar(s1, s2);
    }
    const scalar_time = timer.read();
    
    const speedup = @as(f64, @floatFromInt(scalar_time)) / @as(f64, @floatFromInt(simd_time));
    
    std.debug.print("SIMD:   {d} ns/op\n", .{simd_time / iterations});
    std.debug.print("Scalar: {d} ns/op\n", .{scalar_time / iterations});
    std.debug.print("Speedup: {d:.2}x\n", .{speedup});
    
    try testing.expect(speedup >= 1.5);
}

test "Benchmark: strpos performance" {
    std.debug.print("\n=== Benchmark: strpos performance ===\n", .{});
    
    const simd = simd_string.SIMDString.init();
    const haystack = "This is a very long string that contains multiple occurrences of the word test and we want to find the first occurrence of test in this string";
    const needle = "test";
    
    const iterations = 10000;
    
    // SIMD 版本
    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = simd.strpos(haystack, needle);
    }
    const simd_time = timer.read();
    
    // 标量版本
    timer.reset();
    i = 0;
    while (i < iterations) : (i += 1) {
        _ = simd_string.SIMDString.strposScalar(haystack, needle);
    }
    const scalar_time = timer.read();
    
    const speedup = @as(f64, @floatFromInt(scalar_time)) / @as(f64, @floatFromInt(simd_time));
    
    std.debug.print("SIMD:   {d} ns/op\n", .{simd_time / iterations});
    std.debug.print("Scalar: {d} ns/op\n", .{scalar_time / iterations});
    std.debug.print("Speedup: {d:.2}x\n", .{speedup});
    
    // strpos 应该有更显著的性能提升
    try testing.expect(speedup >= 2.0);
}
