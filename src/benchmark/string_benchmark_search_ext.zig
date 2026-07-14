//! 字符串查找扩展测试
//! 实现额外的字符串查找和匹配函数测试

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

/// 字符串查找扩展测试
pub const StringSearchExtTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,
    generate_php_scripts: bool,
    script_output_dir: []const u8,

    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串查找扩展性能测试 ===\n", .{});
        }

        try results.append(try self.testStrContains());
        try results.append(try self.testStrStartsWith());
        try results.append(try self.testStrEndsWith());
        try results.append(try self.testStristr());
        try results.append(try self.testStrrchr());
        try results.append(try self.testStrchr());
        try results.append(try self.testStrripos());
        try results.append(try self.testStrpbrk());
        try results.append(try self.testStrspn());
        try results.append(try self.testStrcspn());
        try results.append(try self.testSubstrReplace());
        try results.append(try self.testStrRot13());
        try results.append(try self.testLevenshtein());
        try results.append(try self.testSimilarText());
        try results.append(try self.testSoundex());

        return results.toOwnedSlice();
    }

    /// 测试 str_contains (PHP 8+)
    fn testStrContains(self: *@This()) !StringOpResult {
        const test_name = "str_contains";
        const haystack = "The quick brown fox jumps over the lazy dog";
        const needle = "fox";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox jumps over the lazy dog";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = str_contains($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total: u32 = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const contains = std.mem.indexOf(u8, haystack, needle) != null;
            total += if (contains) 1 else 0;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total);

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
            .category = "search_ext",
        };
    }

    /// 测试 str_starts_with (PHP 8+)
    fn testStrStartsWith(self: *@This()) !StringOpResult {
        const test_name = "str_starts_with";
        const haystack = "The quick brown fox";
        const needle = "The";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox";
                \\$needle = "The";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = str_starts_with($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total: u32 = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const starts_with = std.mem.startsWith(u8, haystack, needle);
            total += if (starts_with) 1 else 0;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total);

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
            .category = "search_ext",
        };
    }

    /// 测试 str_ends_with (PHP 8+)
    fn testStrEndsWith(self: *@This()) !StringOpResult {
        const test_name = "str_ends_with";
        const haystack = "The quick brown fox";
        const needle = "fox";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = str_ends_with($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total: u32 = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const ends_with = std.mem.endsWith(u8, haystack, needle);
            total += if (ends_with) 1 else 0;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total);

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
            .category = "search_ext",
        };
    }

    /// 测试 stristr (不区分大小写查找子串)
    fn testStristr(self: *@This()) !StringOpResult {
        const test_name = "stristr";
        const haystack = "The Quick Brown FOX Jumps";
        const needle = "fox";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The Quick Brown FOX Jumps";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = stristr($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const haystack_lower = try self.allocator.alloc(u8, haystack.len);
            defer self.allocator.free(haystack_lower);
            _ = std.ascii.lowerString(haystack_lower, haystack);

            if (std.mem.indexOf(u8, haystack_lower, needle)) |pos| {
                total_len += haystack.len - pos;
            }
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
        };
    }

    /// 测试 strrchr (查找最后一个字符)
    fn testStrrchr(self: *@This()) !StringOpResult {
        const test_name = "strrchr";
        const haystack = "The quick brown fox jumps over the lazy fox";
        const needle: u8 = 'f';

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox jumps over the lazy fox";
                \\$needle = 'f';
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = strrchr($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            if (std.mem.lastIndexOfScalar(u8, haystack, needle)) |pos| {
                total_len += haystack.len - pos;
            }
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
        };
    }

    /// 测试 strchr (查找字符)
    fn testStrchr(self: *@This()) !StringOpResult {
        const test_name = "strchr";
        const haystack = "The quick brown fox";
        const needle: u8 = 'q';

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox";
                \\$needle = 'q';
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = strchr($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            if (std.mem.indexOfScalar(u8, haystack, needle)) |pos| {
                total_len += haystack.len - pos;
            }
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
        };
    }

    /// 测试 strripos (不区分大小写反向查找)
    fn testStrripos(self: *@This()) !StringOpResult {
        const test_name = "strripos";
        const haystack = "The quick brown FOX jumps over the lazy fox";
        const needle = "fox";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown FOX jumps over the lazy fox";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = strripos($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_pos: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const haystack_lower = try self.allocator.alloc(u8, haystack.len);
            defer self.allocator.free(haystack_lower);
            _ = std.ascii.lowerString(haystack_lower, haystack);

            if (std.mem.lastIndexOf(u8, haystack_lower, needle)) |pos| {
                total_pos += pos;
            }
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_pos);

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
            .category = "search_ext",
        };
    }

    /// 测试 strpbrk (查找字符集合中的任意字符)
    fn testStrpbrk(self: *@This()) !StringOpResult {
        const test_name = "strpbrk";
        const haystack = "The quick brown fox";
        const char_set = "aeiou";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox";
                \\$char_set = "aeiou";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = strpbrk($haystack, $char_set);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            for (haystack, 0..) |c, idx| {
                if (std.mem.indexOfScalar(u8, char_set, c) != null) {
                    total_len += haystack.len - idx;
                    break;
                }
            }
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
        };
    }

    /// 测试 strspn (计算匹配长度)
    fn testStrspn(self: *@This()) !StringOpResult {
        const test_name = "strspn";
        const haystack = "12345abc";
        const char_set = "0123456789";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "12345abc";
                \\$char_set = "0123456789";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = strspn($haystack, $char_set);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var len: usize = 0;
            for (haystack) |c| {
                if (std.mem.indexOfScalar(u8, char_set, c) == null) break;
                len += 1;
            }
            total_len += len;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
        };
    }

    /// 测试 strcspn (计算不匹配长度)
    fn testStrcspn(self: *@This()) !StringOpResult {
        const test_name = "strcspn";
        const haystack = "abcdef123";
        const char_set = "0123456789";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "abcdef123";
                \\$char_set = "0123456789";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = strcspn($haystack, $char_set);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var len: usize = 0;
            for (haystack) |c| {
                if (std.mem.indexOfScalar(u8, char_set, c) != null) break;
                len += 1;
            }
            total_len += len;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
        };
    }

    /// 测试 substr_replace (子串替换)
    fn testSubstrReplace(self: *@This()) !StringOpResult {
        const test_name = "substr_replace";
        const haystack = "The quick brown fox";
        const replacement = "slow";
        const start_pos: usize = 4;
        const length: usize = 5;

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox";
                \\$replacement = "slow";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = substr_replace($haystack, $replacement, 4, 5);
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

            try result.appendSlice(haystack[0..start_pos]);
            try result.appendSlice(replacement);
            if (start_pos + length < haystack.len) {
                try result.appendSlice(haystack[start_pos + length ..]);
            }
            total_len += result.items.len;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
        };
    }

    /// 测试 str_rot13 (ROT13 编码)
    fn testStrRot13(self: *@This()) !StringOpResult {
        const test_name = "str_rot13";
        const test_string = "The Quick Brown Fox";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "The Quick Brown Fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = str_rot13($str);
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

            for (test_string, 0..) |c, idx| {
                result[idx] = switch (c) {
                    'A'...'M', 'a'...'m' => c + 13,
                    'N'...'Z', 'n'...'z' => c - 13,
                    else => c,
                };
            }
            total_len += result.len;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
        };
    }

    /// 测试 levenshtein (编辑距离)
    fn testLevenshtein(self: *@This()) !StringOpResult {
        const test_name = "levenshtein";
        const str1 = "kitten";
        const str2 = "sitting";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str1 = "kitten";
                \\$str2 = "sitting";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = levenshtein($str1, $str2);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_dist: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 简化的 Levenshtein 距离算法
            const m = str1.len;
            const n = str2.len;

            var matrix = try self.allocator.alloc([]usize, m + 1);
            defer self.allocator.free(matrix);

            for (matrix, 0..) |*row, idx| {
                row.* = try self.allocator.alloc(usize, n + 1);
                row.*[0] = idx;
            }
            defer for (matrix) |row| self.allocator.free(row);

            for (0..n + 1) |j| {
                matrix[0][j] = j;
            }

            for (1..m + 1) |row_idx| {
                for (1..n + 1) |col_idx| {
                    const cost: usize = if (str1[row_idx - 1] == str2[col_idx - 1]) 0 else 1;
                    const deletion = matrix[row_idx - 1][col_idx] + 1;
                    const insertion = matrix[row_idx][col_idx - 1] + 1;
                    const substitution = matrix[row_idx - 1][col_idx - 1] + cost;
                    matrix[row_idx][col_idx] = @min(@min(deletion, insertion), substitution);
                }
            }

            total_dist += matrix[m][n];
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_dist);

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
            .category = "search_ext",
        };
    }

    /// 测试 similar_text (相似度)
    fn testSimilarText(self: *@This()) !StringOpResult {
        const test_name = "similar_text";
        const str1 = "Hello World";
        const str2 = "Hello PHP";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str1 = "Hello World";
                \\$str2 = "Hello PHP";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = similar_text($str1, $str2);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_sim: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 简化的相似度计算
            var sim: usize = 0;
            const min_len = @min(str1.len, str2.len);
            for (0..min_len) |idx| {
                if (str1[idx] == str2[idx]) {
                    sim += 1;
                }
            }
            total_sim += sim;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_sim);

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
            .category = "search_ext",
        };
    }

    /// 测试 soundex (语音编码)
    fn testSoundex(self: *@This()) !StringOpResult {
        const test_name = "soundex";
        const test_string = "Robert";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Robert";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = soundex($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = try self.allocator.alloc(u8, 4);
            defer self.allocator.free(result);

            // 简化的 Soundex 算法
            result[0] = std.ascii.toUpper(test_string[0]);
            var idx: usize = 1;
            var prev_code: u8 = 0;

            for (test_string[1..]) |c| {
                if (idx >= 4) break;

                const code: u8 = switch (std.ascii.toLower(c)) {
                    'b', 'f', 'p', 'v' => '1',
                    'c', 'g', 'j', 'k', 'q', 's', 'x', 'z' => '2',
                    'd', 't' => '3',
                    'l' => '4',
                    'm', 'n' => '5',
                    'r' => '6',
                    else => 0,
                };

                if (code != 0 and code != prev_code) {
                    result[idx] = code;
                    idx += 1;
                    prev_code = code;
                }
            }

            while (idx < 4) : (idx += 1) {
                result[idx] = '0';
            }

            total_len += result.len;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_len);

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
            .category = "search_ext",
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
