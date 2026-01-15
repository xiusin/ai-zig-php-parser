const std = @import("std");
const fast_runtime = @import("src/runtime/fast_runtime.zig");
const fast_value = @import("src/runtime/fast_value.zig");
const fast_vm = @import("src/runtime/fast_vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zig-PHP Optimization Benchmark ===\n\n", .{});

    // 测试 1: FastValue 整数算术
    {
        std.debug.print("1. FastValue Integer Arithmetic (1M iterations)\n", .{});
        const start = std.time.nanoTimestamp();
        
        var sum = fast_value.FastValue.initInt(0);
        var i: i32 = 0;
        while (i < 1000000) : (i += 1) {
            const val = fast_value.small_int_cache.get(1);
            sum = fast_value.FastOps.addInt(sum, val);
        }
        
        const end = std.time.nanoTimestamp();
        const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        std.debug.print("   Result: {}\n", .{sum.asInt()});
        std.debug.print("   Time: {d:.2} ms\n\n", .{elapsed_ms});
    }

    // 测试 2: 字符串驻留
    {
        std.debug.print("2. String Interning (100K iterations)\n", .{});
        var pool = try fast_runtime.StringPool.init(allocator);
        defer pool.deinit();

        const start = std.time.nanoTimestamp();
        
        var i: usize = 0;
        while (i < 100000) : (i += 1) {
            _ = try pool.intern("hello");
            _ = try pool.intern("world");
            _ = try pool.intern("test");
        }
        
        const end = std.time.nanoTimestamp();
        const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        std.debug.print("   Hit rate: {d:.1}%\n", .{pool.hitRate() * 100});
        std.debug.print("   Time: {d:.2} ms\n\n", .{elapsed_ms});
    }

    // 测试 3: FastVM 执行
    {
        std.debug.print("3. FastVM Loop Execution\n", .{});
        var vm = try fast_vm.FastVM.init(allocator);
        defer vm.deinit();

        // 简单循环: sum = 0; for i = 1 to 100: sum += i
        const code = [_]u8{
            @intFromEnum(fast_vm.OpCode.push_0),
            @intFromEnum(fast_vm.OpCode.store_local), 0,
            @intFromEnum(fast_vm.OpCode.push_1),
            @intFromEnum(fast_vm.OpCode.store_local), 1,
            // loop:
            @intFromEnum(fast_vm.OpCode.push_local), 0,
            @intFromEnum(fast_vm.OpCode.push_local), 1,
            @intFromEnum(fast_vm.OpCode.add_i),
            @intFromEnum(fast_vm.OpCode.store_local), 0,
            @intFromEnum(fast_vm.OpCode.load_inc_store), 1,
            @intFromEnum(fast_vm.OpCode.push_local), 1,
            @intFromEnum(fast_vm.OpCode.push_int), 100, 0, 0, 0,
            @intFromEnum(fast_vm.OpCode.le),
            @intFromEnum(fast_vm.OpCode.jnz), @as(u8, @bitCast(@as(i8, -18))), 0xFF,
            @intFromEnum(fast_vm.OpCode.push_local), 0,
            @intFromEnum(fast_vm.OpCode.halt),
        };

        const func = fast_vm.CompiledFunc{
            .name = "sum_loop",
            .code = &code,
            .constants = &[_]fast_value.FastValue{},
            .locals_count = 2,
            .params_count = 0,
            .max_stack = 8,
        };

        const start = std.time.nanoTimestamp();
        const result = try vm.execute(&func);
        const end = std.time.nanoTimestamp();
        
        const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        std.debug.print("   Result: {}\n", .{result.asInt()});
        std.debug.print("   Time: {d:.2} ms\n\n", .{elapsed_ms});
    }

    // 测试 4: SIMD 字符串操作
    {
        std.debug.print("4. SIMD String Operations (100K iterations)\n", .{});
        const simd_ops = @import("src/runtime/simd_ops.zig");
        
        const start = std.time.nanoTimestamp();
        
        var i: usize = 0;
        while (i < 100000) : (i += 1) {
            const eq = simd_ops.SimdString.eqlSimd("hello world test", "hello world test");
            if (!eq) unreachable;
        }
        
        const end = std.time.nanoTimestamp();
        const elapsed_ms = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
        std.debug.print("   Time: {d:.2} ms\n\n", .{elapsed_ms});
    }

    std.debug.print("=== Benchmark Complete ===\n", .{});
}
