//! 字符串转换操作性能测试
//! 
//! 这个文件包含字符串转换相关的测试函数

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

/// 字符串转换测试辅助结构
pub const StringTransformTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,
    generate_php_scripts: bool,
    script_output_dir: []const u8,
    
    const Self = @This();
    
    /// 测试 strtoupper（转大写）
    pub fn testStrtoupper(self: *Self) !StringOpResult {
        const test_name = "strtoupper";
        const str = "Hello, World! This is a test string.";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = try self.allocator.alloc(u8, str.len);
            defer self.allocator.free(result);
            _ = std.ascii.upperString(result, str);
            total_len += result.len;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_len);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "transform",
        };
    }
    
    /// 测试 strtolower（转小写）
    pub fn testStrtolower(self: *Self) !StringOpResult {
        const test_name = "strtolower";
        const str = "HELLO, WORLD! THIS IS A TEST STRING.";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = try self.allocator.alloc(u8, str.len);
            defer self.allocator.free(result);
            _ = std.ascii.lowerString(result, str);
            total_len += result.len;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_len);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "transform",
        };
    }
};
