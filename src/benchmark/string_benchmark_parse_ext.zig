//! 字符串解析扩展测试
//! 实现 parse_str, str_getcsv 等解析函数测试

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

/// 字符串解析扩展测试
pub const StringParseExtTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,
    generate_php_scripts: bool,
    script_output_dir: []const u8,

    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串解析扩展性能测试 ===\n", .{});
        }

        try results.append(self.allocator, try self.testParseStr());
        try results.append(self.allocator, try self.testStrGetcsv());

        return results.toOwnedSlice();
    }

    /// 测试 parse_str (解析查询字符串)
    fn testParseStr(self: *@This()) !StringOpResult {
        const test_name = "parse_str";
        const query_string = "name=John&age=25&city=NewYork";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "name=John&age=25&city=NewYork";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    parse_str($str, $result);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_pairs: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 解析查询字符串
            var pairs = std.mem.tokenizeScalar(u8, query_string, '&');
            var count: usize = 0;
            while (pairs.next()) |pair| {
                if (std.mem.indexOfScalar(u8, pair, '=')) |_| {
                    count += 1;
                }
            }
            total_pairs += count;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_pairs);

        const ops_per_sec = @as(f64, @floatFromInt(self.iterations)) /
            (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

        if (self.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "parse_ext",
        };
    }

    /// 测试 str_getcsv (解析 CSV 行)
    fn testStrGetcsv(self: *@This()) !StringOpResult {
        const test_name = "str_getcsv";
        const csv_line = "John,Doe,25,New York,Engineer";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "John,Doe,25,New York,Engineer";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = str_getcsv($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_fields: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 解析 CSV 行
            var fields = std.mem.tokenizeScalar(u8, csv_line, ',');
            var count: usize = 0;
            while (fields.next()) |_| {
                count += 1;
            }
            total_fields += count;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_fields);

        const ops_per_sec = @as(f64, @floatFromInt(self.iterations)) /
            (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

        if (self.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "parse_ext",
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

        const file = try std.fs.cwd.createFile(file_path, .{});
        defer file.close();

        try file.writeAll(script_content);
    }
};
