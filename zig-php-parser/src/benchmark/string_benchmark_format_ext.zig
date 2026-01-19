//! 字符串格式化扩展测试
//! 实现 printf 系列和其他格式化函数测试

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

/// 字符串格式化扩展测试
pub const StringFormatExtTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,
    generate_php_scripts: bool,
    script_output_dir: []const u8,
    
    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        
        if (self.verbose) {
            std.debug.print("\n=== 字符串格式化扩展性能测试 ===\n", .{});
        }
        
        try results.append(try self.testPrintf());
        try results.append(try self.testVsprintf());
        try results.append(try self.testSscanf());
        
        return results.toOwnedSlice();
    }
    
    /// 测试 printf (格式化输出)
    fn testPrintf(self: *@This()) !StringOpResult {
        const test_name = "printf";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$start = hrtime(true);
                \\ob_start();
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    printf("Hello %s, you are %d years old", "World", 25);
                \\}
                \\ob_end_clean();
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try std.fmt.allocPrint(
                self.allocator,
                "Hello {s}, you are {d} years old",
                .{ "World", 25 },
            );
            defer self.allocator.free(result);
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
            .category = "format_ext",
        };
    }

    /// 测试 vsprintf (变参格式化字符串)
    fn testVsprintf(self: *@This()) !StringOpResult {
        const test_name = "vsprintf";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$format = "Hello %s, you are %d years old";
                \\$args = ["World", 25];
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = vsprintf($format, $args);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try std.fmt.allocPrint(
                self.allocator,
                "Hello {s}, you are {d} years old",
                .{ "World", 25 },
            );
            defer self.allocator.free(result);
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
            .category = "format_ext",
        };
    }
    
    /// 测试 sscanf (格式化解析)
    fn testSscanf(self: *@This()) !StringOpResult {
        const test_name = "sscanf";
        const test_string = "Hello World 25";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello World 25";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    sscanf($str, "%s %s %d", $word1, $word2, $num);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_parsed: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 简单的解析实现
            var iter = std.mem.tokenizeScalar(u8, test_string, ' ');
            var count: usize = 0;
            while (iter.next()) |_| {
                count += 1;
            }
            total_parsed += count;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_parsed);
        
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
            .category = "format_ext",
        };
    }
    
    /// 生成 PHP 测试脚本
    fn generatePhpScript(self: *@This(), test_name: []const u8, script_content: []const u8) !void {
        const file_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.php",
            .{ self.script_output_dir, test_name },
        );
        defer self.allocator.free(file_path);
        
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();
        
        try file.writeAll(script_content);
    }
};
