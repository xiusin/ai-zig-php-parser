//! 内存安全属性测试
//!
//! 本文件实现了内存安全相关的属性测试：
//! - 属性 29：无悬垂指针
//! - 属性 30：无缓冲区溢出
//! - 属性 31：无内存泄漏
//!
//! 验证需求：7.1, 7.2, 7.3, 7.4, 7.7

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const MemorySafety = @import("memory_safety.zig");

// ============================================================================
// 属性测试框架
// ============================================================================

const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: std.Random,
    iterations: u32 = 100,
    
    const Self = @This();
    
    fn init(allocator: std.mem.Allocator, seed: u64) Self {
        var prng = std.Random.DefaultPrng.init(seed);
        return .{
            .allocator = allocator,
            .rng = prng.random(),
        };
    }
    
    fn run(
        self: *Self,
        comptime TestInput: type,
        property_fn: fn (TestInput, std.mem.Allocator) anyerror!bool,
        generator_fn: fn (*std.Random, std.mem.Allocator) anyerror!TestInput,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const input = try generator_fn(&self.rng, self.allocator);
            
            const result = property_fn(input, self.allocator) catch |err| {
                std.debug.print("Property test error at iteration {d}: {}\n", .{ i, err });
                failed += 1;
                continue;
            };
            
            if (result) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed at iteration {d}\n", .{i});
            }
        }
        
        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("\nProperty test: {d}/{d} passed ({d:.2}%)\n", .{
            passed,
            self.iterations,
            success_rate * 100.0,
        });
        
        return failed == 0;
    }
};

// ============================================================================
// 测试输入生成器
// ============================================================================

const PointerTestInput = struct {
    allocate_count: usize,
    access_pattern: []const usize,
    invalidate_indices: []const usize,
};

fn generatePointerTestInput(rng: *std.Random, allocator: std.mem.Allocator) !PointerTestInput {
    const count = rng.intRangeAtMost(usize, 1, 10);
    
    const access_count = rng.intRangeAtMost(usize, 1, 20);
    const access_pattern = try allocator.alloc(usize, access_count);
    for (access_pattern) |*idx| {
        idx.* = rng.intRangeAtMost(usize, 0, count - 1);
    }
    
    const invalidate_count = rng.intRangeAtMost(usize, 0, count);
    const invalidate_indices = try allocator.alloc(usize, invalidate_count);
    for (invalidate_indices) |*idx| {
        idx.* = rng.intRangeAtMost(usize, 0, count - 1);
    }
    
    return .{
        .allocate_count = count,
        .access_pattern = access_pattern,
        .invalidate_indices = invalidate_indices,
    };
}

const ArrayTestInput = struct {
    array_size: usize,
    access_indices: []const usize,
};

fn generateArrayTestInput(rng: *std.Random, allocator: std.mem.Allocator) !ArrayTestInput {
    const size = rng.intRangeAtMost(usize, 1, 100);
    
    const access_count = rng.intRangeAtMost(usize, 1, 50);
    const access_indices = try allocator.alloc(usize, access_count);
    for (access_indices) |*idx| {
        // 生成一些有效和一些无效的索引
        if (rng.boolean()) {
            idx.* = rng.intRangeAtMost(usize, 0, size - 1);
        } else {
            idx.* = rng.intRangeAtMost(usize, size, size + 100);
        }
    }
    
    return .{
        .array_size = size,
        .access_indices = access_indices,
    };
}

const AllocationTestInput = struct {
    allocation_sizes: []const usize,
    free_indices: []const usize,
};

fn generateAllocationTestInput(rng: *std.Random, allocator: std.mem.Allocator) !AllocationTestInput {
    const count = rng.intRangeAtMost(usize, 1, 20);
    
    const sizes = try allocator.alloc(usize, count);
    for (sizes) |*size| {
        size.* = rng.intRangeAtMost(usize, 1, 1024);
    }
    
    const free_count = rng.intRangeAtMost(usize, 0, count);
    const free_indices = try allocator.alloc(usize, free_count);
    for (free_indices) |*idx| {
        idx.* = rng.intRangeAtMost(usize, 0, count - 1);
    }
    
    return .{
        .allocation_sizes = sizes,
        .free_indices = free_indices,
    };
}

// ============================================================================
// 属性 29：无悬垂指针
// ============================================================================

/// Feature: zig-php-performance-optimization, Property 29
/// 
/// 对于任意指针，在其生命周期内，指向的内存应该始终有效
/// 
/// 验证需求：7.4
fn property_no_dangling_pointers(input: PointerTestInput, allocator: std.mem.Allocator) !bool {
    // 仅在 Debug 模式下运行此测试
    if (builtin.mode != .Debug) return true;
    
    defer {
        allocator.free(input.access_pattern);
        allocator.free(input.invalidate_indices);
    }
    
    // 创建多个生命周期指针
    var pointers = try allocator.alloc(MemorySafety.LifetimePtr(i32), input.allocate_count);
    defer allocator.free(pointers);
    
    var values = try allocator.alloc(i32, input.allocate_count);
    defer allocator.free(values);
    
    // 初始化指针
    for (pointers, 0..) |*ptr, i| {
        values[i] = @intCast(i);
        ptr.* = try MemorySafety.LifetimePtr(i32).init(&values[i], allocator);
    }
    defer for (pointers) |*ptr| {
        ptr.deinit(allocator);
    };
    
    // 标记一些指针为无效
    for (input.invalidate_indices) |idx| {
        if (idx < pointers.len) {
            pointers[idx].invalidate();
        }
    }
    
    // 尝试访问指针
    for (input.access_pattern) |idx| {
        if (idx >= pointers.len) continue;
        
        const ptr = &pointers[idx];
        
        // 检查指针有效性
        if (ptr.isValid()) {
            // 有效指针应该可以解引用
            const deref = ptr.deref() catch {
                // 有效指针解引用失败 - 属性违反
                return false;
            };
            
            // 验证值正确
            if (deref.* != @as(i32, @intCast(idx))) {
                return false;
            }
        } else {
            // 无效指针不应该可以解引用
            if (ptr.deref()) |_| {
                // 无效指针解引用成功 - 属性违反
                return false;
            } else |err| {
                // 应该返回 DanglingPointer 错误
                if (err != error.DanglingPointer) {
                    return false;
                }
            }
        }
    }
    
    return true;
}

test "Property 29: No dangling pointers" {
    if (builtin.mode != .Debug) return error.SkipZigTest;
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var pt = PropertyTest.init(allocator, 12345);
    
    const passed = try pt.run(
        PointerTestInput,
        property_no_dangling_pointers,
        generatePointerTestInput,
    );
    
    try testing.expect(passed);
}

// ============================================================================
// 属性 30：无缓冲区溢出
// ============================================================================

/// Feature: zig-php-performance-optimization, Property 30
/// 
/// 对于任意数组访问，索引应该在有效范围内
/// 
/// 验证需求：7.3
fn property_no_buffer_overflow(input: ArrayTestInput, allocator: std.mem.Allocator) !bool {
    defer allocator.free(input.access_indices);
    
    // 创建边界检查数组
    const data = try allocator.alloc(i32, input.array_size);
    defer allocator.free(data);
    
    // 初始化数据
    for (data, 0..) |*val, i| {
        val.* = @intCast(i);
    }
    
    var arr = MemorySafety.BoundsCheckedArray(i32).init(data);
    
    // 尝试访问所有索引
    for (input.access_indices) |idx| {
        if (idx < input.array_size) {
            // 有效索引应该成功
            const val = arr.get(idx) catch {
                // 有效索引访问失败 - 属性违反
                return false;
            };
            
            // 验证值正确
            if (val != @as(i32, @intCast(idx))) {
                return false;
            }
        } else {
            // 无效索引应该失败
            if (arr.get(idx)) |_| {
                // 无效索引访问成功 - 属性违反
                return false;
            } else |err| {
                // 应该返回 IndexOutOfBounds 错误
                if (err != error.IndexOutOfBounds) {
                    return false;
                }
            }
        }
    }
    
    return true;
}

test "Property 30: No buffer overflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var pt = PropertyTest.init(allocator, 54321);
    
    const passed = try pt.run(
        ArrayTestInput,
        property_no_buffer_overflow,
        generateArrayTestInput,
    );
    
    try testing.expect(passed);
}

// ============================================================================
// 属性 31：无内存泄漏
// ============================================================================

/// Feature: zig-php-performance-optimization, Property 31
/// 
/// 对于任意分配的内存，应该在不再使用时被正确释放
/// 
/// 验证需求：7.1, 7.2, 7.7
fn property_no_memory_leaks(input: AllocationTestInput, allocator: std.mem.Allocator) !bool {
    // 仅在 Debug 模式下运行此测试
    if (builtin.mode != .Debug) return true;
    
    defer {
        allocator.free(input.allocation_sizes);
        allocator.free(input.free_indices);
    }
    
    // 创建泄漏检测器
    var detector = try MemorySafety.LeakDetector.init(allocator);
    defer detector.deinit();
    
    // 分配内存
    var allocations = try allocator.alloc([]u8, input.allocation_sizes.len);
    defer allocator.free(allocations);
    
    for (input.allocation_sizes, 0..) |size, i| {
        allocations[i] = try allocator.alloc(u8, size);
        const ptr = @intFromPtr(allocations[i].ptr);
        try detector.recordAllocation(ptr, size, @returnAddress());
    }
    
    // 创建一个集合来跟踪已释放的索引
    var freed_set = std.AutoHashMap(usize, void).init(allocator);
    defer freed_set.deinit();
    
    // 释放一些内存
    for (input.free_indices) |idx| {
        if (idx >= allocations.len) continue;
        
        // 避免重复释放
        if (freed_set.contains(idx)) continue;
        
        const ptr = @intFromPtr(allocations[idx].ptr);
        detector.recordDeallocation(ptr);
        allocator.free(allocations[idx]);
        allocations[idx] = &[_]u8{};
        try freed_set.put(idx, {});
    }
    
    // 检查泄漏
    const leaks = try detector.checkLeaks();
    defer if (leaks.len > 0) allocator.free(leaks);
    
    // 计算预期的泄漏数量
    const expected_leaks = input.allocation_sizes.len - freed_set.count();
    
    // 清理剩余的分配
    for (allocations) |alloc| {
        if (alloc.len > 0) {
            allocator.free(alloc);
        }
    }
    
    // 验证泄漏检测正确
    return leaks.len == expected_leaks;
}

test "Property 31: No memory leaks" {
    if (builtin.mode != .Debug) return error.SkipZigTest;
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var pt = PropertyTest.init(allocator, 98765);
    
    const passed = try pt.run(
        AllocationTestInput,
        property_no_memory_leaks,
        generateAllocationTestInput,
    );
    
    try testing.expect(passed);
}

// ============================================================================
// 集成测试：SafeAllocator 与泄漏检测
// ============================================================================

test "Integration: SafeAllocator with leak detection" {
    if (builtin.mode != .Debug) return error.SkipZigTest;
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var safe = MemorySafety.SafeAllocator.init(gpa.allocator());
    const allocator = safe.getAllocator();
    
    // 分配一些内存
    const data1 = try allocator.alloc(u8, 100);
    const data2 = try allocator.alloc(u8, 200);
    const data3 = try allocator.alloc(u8, 300);
    
    // 释放部分内存
    allocator.free(data1);
    allocator.free(data3);
    
    // 检查统计信息
    const stats = safe.getStats().?;
    try testing.expect(stats.allocation_count >= 3);
    try testing.expect(stats.deallocation_count >= 2);
    try testing.expect(stats.hasLeaks());
    try testing.expectEqual(@as(usize, 1), stats.leakCount());
    
    // 清理泄漏
    allocator.free(data2);
}

// ============================================================================
// 集成测试：资源守卫
// ============================================================================

test "Integration: Resource guard with defer/errdefer" {
    const TestResource = struct {
        value: i32,
        allocator: std.mem.Allocator,
        buffer: []u8,
        
        fn init(allocator: std.mem.Allocator, value: i32) !*@This() {
            const self = try allocator.create(@This());
            errdefer allocator.destroy(self);
            
            const buffer = try allocator.alloc(u8, 100);
            errdefer allocator.free(buffer);
            
            self.* = .{
                .value = value,
                .allocator = allocator,
                .buffer = buffer,
            };
            
            return self;
        }
        
        fn deinit(self: *@This()) void {
            self.allocator.free(self.buffer);
            self.allocator.destroy(self);
        }
    };
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 成功情况
    {
        const resource = try TestResource.init(allocator, 42);
        var guard = MemorySafety.ResourceGuard(*TestResource, TestResource.deinit).init(resource);
        defer guard.deinit();
        
        try testing.expectEqual(@as(i32, 42), resource.value);
    }
    
    // 错误情况（errdefer 应该清理）
    const FailingResource = struct {
        fn init(alloc: std.mem.Allocator) !*TestResource {
            const res = try TestResource.init(alloc, 99);
            errdefer res.deinit();
            
            // 模拟错误
            return error.SimulatedError;
        }
    };
    
    try testing.expectError(error.SimulatedError, FailingResource.init(allocator));
}

// ============================================================================
// 性能测试：边界检查开销
// ============================================================================

test "Performance: Bounds checking overhead" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const size = 10000;
    const data = try allocator.alloc(i32, size);
    defer allocator.free(data);
    
    for (data, 0..) |*val, i| {
        val.* = @intCast(i);
    }
    
    // 测试无边界检查的访问
    var timer = try std.time.Timer.start();
    var sum1: i64 = 0;
    for (0..size) |i| {
        sum1 += data[i];
    }
    const time1 = timer.read();
    
    // 测试有边界检查的访问
    var arr = MemorySafety.BoundsCheckedArray(i32).init(data);
    timer.reset();
    var sum2: i64 = 0;
    for (0..size) |i| {
        sum2 += try arr.get(i);
    }
    const time2 = timer.read();
    
    try testing.expectEqual(sum1, sum2);
    
    const overhead = @as(f64, @floatFromInt(time2)) / @as(f64, @floatFromInt(time1));
    std.debug.print("\nBounds checking overhead: {d:.2}x\n", .{overhead});
    
    // 边界检查开销应该小于 2x
    try testing.expect(overhead < 2.0);
}
