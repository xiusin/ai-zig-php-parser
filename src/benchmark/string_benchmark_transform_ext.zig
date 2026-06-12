//! 字符串转换扩展测试
//! 实现斜杠、引号等转换函数测试

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

/// 字符串转换扩展测试
pub const StringTransformExtTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,
    generate_php_scripts: bool,
    script_output_dir: []const u8,
    
    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        
        if (self.verbose) {
            std.debug.print("\n=== 字符串转换扩展性能测试 ===\n", .{});
        }
        
        try results.append(try self.testAddslashes());
        try results.append(try self.testStripslashes());
        try results.append(try self.testAddcslashes());
        try results.append(try self.testStripcslashes());
        try results.append(try self.testQuotemeta());
        try results.append(try self.testStrIncrement());
        try results.append(try self.testStrDecrement());
        
        return results.toOwnedSlice();
    }
    
    /// 测试 addslashes (添加斜杠转义)
    fn testAddslashes(self: *@This()) !StringOpResult {
        const test_name = "addslashes";
        const test_string = "It's a \"test\" string with \\ backslash";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "It's a \"test\" string with \\ backslash";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = addslashes($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
            defer result.deinit();
            
            for (test_string) |c| {
                switch (c) {
                    '\'', '"', '\\' => {
                        try result.append('\\');
                        try result.append(c);
                    },
                    0 => {
                        try result.append('\\');
                        try result.append('0');
                    },
                    else => try result.append(c),
                }
            }
            total_len += result.items.len;
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
            .category = "transform_ext",
        };
    }

    /// 测试 stripslashes (去除斜杠转义)
    fn testStripslashes(self: *@This()) !StringOpResult {
        const test_name = "stripslashes";
        const test_string = "It\\'s a \\\"test\\\" string with \\\\ backslash";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "It\\'s a \\\"test\\\" string with \\\\ backslash";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = stripslashes($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
            defer result.deinit();
            
            var idx: usize = 0;
            while (idx < test_string.len) : (idx += 1) {
                if (test_string[idx] == '\\' and idx + 1 < test_string.len) {
                    const next = test_string[idx + 1];
                    switch (next) {
                        '\'', '"', '\\' => {
                            try result.append(next);
                            idx += 1;
                        },
                        '0' => {
                            try result.append(0);
                            idx += 1;
                        },
                        else => try result.append(test_string[idx]),
                    }
                } else {
                    try result.append(test_string[idx]);
                }
            }
            total_len += result.items.len;
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
            .category = "transform_ext",
        };
    }
    
    /// 测试 addcslashes (C 风格添加斜杠)
    fn testAddcslashes(self: *@This()) !StringOpResult {
        const test_name = "addcslashes";
        const test_string = "Hello\nWorld\tTest\r\n";
        const charlist = "\n\r\t";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello\nWorld\tTest\r\n";
                \\$charlist = "\n\r\t";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = addcslashes($str, $charlist);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
            defer result.deinit();
            
            for (test_string) |c| {
                var should_escape = false;
                for (charlist) |escape_char| {
                    if (c == escape_char) {
                        should_escape = true;
                        break;
                    }
                }
                
                if (should_escape) {
                    try result.append('\\');
                    switch (c) {
                        '\n' => try result.append('n'),
                        '\r' => try result.append('r'),
                        '\t' => try result.append('t'),
                        else => try result.append(c),
                    }
                } else {
                    try result.append(c);
                }
            }
            total_len += result.items.len;
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
            .category = "transform_ext",
        };
    }
    
    /// 测试 stripcslashes (C 风格去除斜杠)
    fn testStripcslashes(self: *@This()) !StringOpResult {
        const test_name = "stripcslashes";
        const test_string = "Hello\\nWorld\\tTest\\r\\n";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello\\nWorld\\tTest\\r\\n";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = stripcslashes($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
            defer result.deinit();
            
            var idx: usize = 0;
            while (idx < test_string.len) : (idx += 1) {
                if (test_string[idx] == '\\' and idx + 1 < test_string.len) {
                    const next = test_string[idx + 1];
                    switch (next) {
                        'n' => {
                            try result.append('\n');
                            idx += 1;
                        },
                        'r' => {
                            try result.append('\r');
                            idx += 1;
                        },
                        't' => {
                            try result.append('\t');
                            idx += 1;
                        },
                        '\\' => {
                            try result.append('\\');
                            idx += 1;
                        },
                        else => try result.append(test_string[idx]),
                    }
                } else {
                    try result.append(test_string[idx]);
                }
            }
            total_len += result.items.len;
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
            .category = "transform_ext",
        };
    }
    
    /// 测试 quotemeta (转义元字符)
    fn testQuotemeta(self: *@This()) !StringOpResult {
        const test_name = "quotemeta";
        const test_string = "Hello. World? Test* [abc] (def) {ghi}";
        const meta_chars = ".\\+*?[^]($)";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello. World? Test* [abc] (def) {ghi}";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = quotemeta($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
            defer result.deinit();
            
            for (test_string) |c| {
                var is_meta = false;
                for (meta_chars) |meta| {
                    if (c == meta) {
                        is_meta = true;
                        break;
                    }
                }
                
                if (is_meta) {
                    try result.append('\\');
                }
                try result.append(c);
            }
            total_len += result.items.len;
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
            .category = "transform_ext",
        };
    }
    
    /// 测试 str_increment (字符串递增 - PHP 8.3+)
    fn testStrIncrement(self: *@This()) !StringOpResult {
        const test_name = "str_increment";
        const test_string = "abc";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "abc";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    // PHP 8.3+ str_increment
                \\    if (function_exists('str_increment')) {
                \\        $result = str_increment($str);
                \\    } else {
                \\        // Fallback for older PHP
                \\        $result = $str;
                \\        $result++;
                \\    }
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = try self.allocator.alloc(u8, test_string.len + 1);
            defer self.allocator.free(result);
            
            @memcpy(result[0..test_string.len], test_string);
            
            // 简单递增逻辑：从右到左递增字符
            var idx = test_string.len;
            var carry = true;
            while (idx > 0 and carry) {
                idx -= 1;
                if (result[idx] >= 'a' and result[idx] < 'z') {
                    result[idx] += 1;
                    carry = false;
                } else if (result[idx] == 'z') {
                    result[idx] = 'a';
                } else if (result[idx] >= 'A' and result[idx] < 'Z') {
                    result[idx] += 1;
                    carry = false;
                } else if (result[idx] == 'Z') {
                    result[idx] = 'A';
                } else if (result[idx] >= '0' and result[idx] < '9') {
                    result[idx] += 1;
                    carry = false;
                } else if (result[idx] == '9') {
                    result[idx] = '0';
                }
            }
            
            total_len += test_string.len;
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
            .category = "transform_ext",
        };
    }
    
    /// 测试 str_decrement (字符串递减 - PHP 8.3+)
    fn testStrDecrement(self: *@This()) !StringOpResult {
        const test_name = "str_decrement";
        const test_string = "abc";
        
        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "abc";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    // PHP 8.3+ str_decrement
                \\    if (function_exists('str_decrement')) {
                \\        $result = str_decrement($str);
                \\    } else {
                \\        // Fallback for older PHP
                \\        $result = $str;
                \\        $result--;
                \\    }
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = try self.allocator.alloc(u8, test_string.len);
            defer self.allocator.free(result);
            
            @memcpy(result[0..test_string.len], test_string);
            
            // 简单递减逻辑：从右到左递减字符
            var idx = test_string.len;
            var borrow = true;
            while (idx > 0 and borrow) {
                idx -= 1;
                if (result[idx] > 'a' and result[idx] <= 'z') {
                    result[idx] -= 1;
                    borrow = false;
                } else if (result[idx] == 'a') {
                    result[idx] = 'z';
                } else if (result[idx] > 'A' and result[idx] <= 'Z') {
                    result[idx] -= 1;
                    borrow = false;
                } else if (result[idx] == 'A') {
                    result[idx] = 'Z';
                } else if (result[idx] > '0' and result[idx] <= '9') {
                    result[idx] -= 1;
                    borrow = false;
                } else if (result[idx] == '0') {
                    result[idx] = '9';
                }
            }
            
            total_len += test_string.len;
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
            .category = "transform_ext",
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
