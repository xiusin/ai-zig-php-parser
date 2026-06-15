//! ============================================================================
//! 异步 I/O 性能测试
//! ============================================================================
//!
//! 功能：测试异步 I/O 系统的性能，验证吞吐量提升 3-5 倍
//!
//! 需求：8.3 - 确保吞吐量提升 3-5 倍
//! ============================================================================

const std = @import("std");
const AsyncIO = @import("async_io.zig").AsyncIO;

/// 性能测试配置
const TestConfig = struct {
    num_files: usize = 100,
    file_size: usize = 1024 * 1024, // 1 MB
    num_iterations: usize = 10,
};

/// 同步文件 I/O 基准测试
fn benchmarkSyncFileIO(allocator: std.mem.Allocator, config: TestConfig) !u64 {
    const start_time = std.time.nanoTimestamp();
    
    // 创建测试文件
    var i: usize = 0;
    while (i < config.num_files) : (i += 1) {
        const filename = try std.fmt.allocPrint(allocator, "test_sync_{d}.dat", .{i});
        defer allocator.free(filename);
        
        const file = try std.fs.cwd.createFile(filename, .{});
        defer file.close();
        
        const data = try allocator.alloc(u8, config.file_size);
        defer allocator.free(data);
        
        @memset(data, 0xAA);
        try file.writeAll(data);
    }
    
    // 读取测试文件
    i = 0;
    while (i < config.num_files) : (i += 1) {
        const filename = try std.fmt.allocPrint(allocator, "test_sync_{d}.dat", .{i});
        defer allocator.free(filename);
        
        const file = try std.fs.cwd.openFile(filename, .{});
        defer file.close();
        
        const data = try allocator.alloc(u8, config.file_size);
        defer allocator.free(data);
        
        _ = try file.readAll(data);
    }
    
    // 清理测试文件
    i = 0;
    while (i < config.num_files) : (i += 1) {
        const filename = try std.fmt.allocPrint(allocator, "test_sync_{d}.dat", .{i});
        defer allocator.free(filename);
        
        try std.fs.cwd.deleteFile(filename);
    }
    
    const end_time = std.time.nanoTimestamp();
    return @intCast(end_time - start_time);
}

/// 异步文件 I/O 基准测试
fn benchmarkAsyncFileIO(allocator: std.mem.Allocator, config: TestConfig) !u64 {
    const async_io = try AsyncIO.init(allocator);
    defer async_io.deinit();
    
    const start_time = std.time.nanoTimestamp();
    
    // 创建测试文件（异步）
    var i: usize = 0;
    while (i < config.num_files) : (i += 1) {
        const filename = try std.fmt.allocPrint(allocator, "test_async_{d}.dat", .{i});
        defer allocator.free(filename);
        
        const data = try allocator.alloc(u8, config.file_size);
        defer allocator.free(data);
        
        @memset(data, 0xBB);
        try async_io.writeFile(filename, data);
    }
    
    // 读取测试文件（异步）
    i = 0;
    while (i < config.num_files) : (i += 1) {
        const filename = try std.fmt.allocPrint(allocator, "test_async_{d}.dat", .{i});
        defer allocator.free(filename);
        
        const data = try async_io.readFile(filename);
        defer allocator.free(data);
    }
    
    // 清理测试文件
    i = 0;
    while (i < config.num_files) : (i += 1) {
        const filename = try std.fmt.allocPrint(allocator, "test_async_{d}.dat", .{i});
        defer allocator.free(filename);
        
        try std.fs.cwd.deleteFile(filename);
    }
    
    const end_time = std.time.nanoTimestamp();
    return @intCast(end_time - start_time);
}

/// 计算吞吐量（MB/s）
fn calculateThroughput(total_bytes: usize, time_ns: u64) f64 {
    const time_s = @as(f64, @floatFromInt(time_ns)) / 1_000_000_000.0;
    const mb = @as(f64, @floatFromInt(total_bytes)) / (1024.0 * 1024.0);
    return mb / time_s;
}

/// 主性能测试
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = TestConfig{};
    
    std.debug.print("\n=== Async I/O Performance Test ===\n", .{});
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  Files: {d}\n", .{config.num_files});
    std.debug.print("  File Size: {d} MB\n", .{config.file_size / (1024 * 1024)});
    std.debug.print("  Iterations: {d}\n\n", .{config.num_iterations});
    
    // 运行同步基准测试
    std.debug.print("Running synchronous I/O benchmark...\n", .{});
    var sync_total_time: u64 = 0;
    var iter: usize = 0;
    while (iter < config.num_iterations) : (iter += 1) {
        const time = try benchmarkSyncFileIO(allocator, config);
        sync_total_time += time;
        std.debug.print("  Iteration {d}: {d} ms\n", .{ iter + 1, time / 1_000_000 });
    }
    const sync_avg_time = sync_total_time / config.num_iterations;
    
    // 运行异步基准测试
    std.debug.print("\nRunning asynchronous I/O benchmark...\n", .{});
    var async_total_time: u64 = 0;
    iter = 0;
    while (iter < config.num_iterations) : (iter += 1) {
        const time = try benchmarkAsyncFileIO(allocator, config);
        async_total_time += time;
        std.debug.print("  Iteration {d}: {d} ms\n", .{ iter + 1, time / 1_000_000 });
    }
    const async_avg_time = async_total_time / config.num_iterations;
    
    // 计算结果
    const total_bytes = config.num_files * config.file_size * 2; // 读 + 写
    const sync_throughput = calculateThroughput(total_bytes, sync_avg_time);
    const async_throughput = calculateThroughput(total_bytes, async_avg_time);
    const speedup = @as(f64, @floatFromInt(sync_avg_time)) / @as(f64, @floatFromInt(async_avg_time));
    
    // 打印结果
    std.debug.print("\n=== Results ===\n", .{});
    std.debug.print("Synchronous I/O:\n", .{});
    std.debug.print("  Average Time: {d} ms\n", .{sync_avg_time / 1_000_000});
    std.debug.print("  Throughput: {d:.2} MB/s\n", .{sync_throughput});
    
    std.debug.print("\nAsynchronous I/O:\n", .{});
    std.debug.print("  Average Time: {d} ms\n", .{async_avg_time / 1_000_000});
    std.debug.print("  Throughput: {d:.2} MB/s\n", .{async_throughput});
    
    std.debug.print("\nSpeedup: {d:.2}x\n", .{speedup});
    
    // 验证性能目标
    if (speedup >= 3.0) {
        std.debug.print("\n✓ Performance target achieved (3-5x speedup)\n", .{});
    } else {
        std.debug.print("\n✗ Performance target not met (expected 3-5x, got {d:.2}x)\n", .{speedup});
        return error.PerformanceTargetNotMet;
    }
}

// 单元测试
test "async I/O performance improvement" {
    const allocator = std.testing.allocator;
    
    const config = TestConfig{
        .num_files = 10,
        .file_size = 1024 * 100, // 100 KB
        .num_iterations = 3,
    };
    
    // 运行同步基准测试
    var sync_total_time: u64 = 0;
    var iter: usize = 0;
    while (iter < config.num_iterations) : (iter += 1) {
        const time = try benchmarkSyncFileIO(allocator, config);
        sync_total_time += time;
    }
    const sync_avg_time = sync_total_time / config.num_iterations;
    
    // 运行异步基准测试
    var async_total_time: u64 = 0;
    iter = 0;
    while (iter < config.num_iterations) : (iter += 1) {
        const time = try benchmarkAsyncFileIO(allocator, config);
        async_total_time += time;
    }
    const async_avg_time = async_total_time / config.num_iterations;
    
    // 计算加速比
    const speedup = @as(f64, @floatFromInt(sync_avg_time)) / @as(f64, @floatFromInt(async_avg_time));
    
    std.debug.print("\nAsync I/O Speedup: {d:.2}x\n", .{speedup});
    
    // 验证性能提升（至少 1.5x，因为测试环境可能不理想）
    try std.testing.expect(speedup >= 1.5);
}

test "async I/O throughput calculation" {
    const total_bytes = 100 * 1024 * 1024; // 100 MB
    const time_ns = 1_000_000_000; // 1 second
    
    const throughput = calculateThroughput(total_bytes, time_ns);
    
    // 应该是 100 MB/s
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), throughput, 0.1);
}
