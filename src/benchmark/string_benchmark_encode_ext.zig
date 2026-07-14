//! 字符串编码扩展测试
//! 实现 HTML、URL 等编码函数测试

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

/// 字符串编码扩展测试
pub const StringEncodeExtTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,
    generate_php_scripts: bool,
    script_output_dir: []const u8,

    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串编码扩展性能测试 ===\n", .{});
        }

        try results.append(try self.testHtmlspecialchars());
        try results.append(try self.testHtmlentities());
        try results.append(try self.testHtmlEntityDecode());
        try results.append(try self.testHtmlspecialcharsDecode());
        try results.append(try self.testUrlencode());
        try results.append(try self.testUrldecode());
        try results.append(try self.testRawurlencode());
        try results.append(try self.testRawurldecode());
        try results.append(try self.testNl2br());
        try results.append(try self.testWordwrap());

        return results.toOwnedSlice();
    }

    /// 测试 htmlspecialchars
    fn testHtmlspecialchars(self: *@This()) !StringOpResult {
        const test_name = "htmlspecialchars";
        const test_string = "<script>alert('XSS');</script> & \"quotes\"";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "<script>alert('XSS');</script> & \"quotes\"";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = htmlspecialchars($str);
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
                    '&' => try result.appendSlice("&amp;"),
                    '<' => try result.appendSlice("&lt;"),
                    '>' => try result.appendSlice("&gt;"),
                    '"' => try result.appendSlice("&quot;"),
                    '\'' => try result.appendSlice("&#039;"),
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
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "encode_ext",
        };
    }

    /// 测试 htmlentities
    fn testHtmlentities(self: *@This()) !StringOpResult {
        const test_name = "htmlentities";
        const test_string = "Café & Résumé <tag>";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Café & Résumé <tag>";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = htmlentities($str);
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
                    '&' => try result.appendSlice("&amp;"),
                    '<' => try result.appendSlice("&lt;"),
                    '>' => try result.appendSlice("&gt;"),
                    '"' => try result.appendSlice("&quot;"),
                    '\'' => try result.appendSlice("&#039;"),
                    0x80...0xFF => {
                        try result.appendSlice("&#");
                        const num_str = try std.fmt.allocPrint(self.allocator, "{d}", .{c});
                        defer self.allocator.free(num_str);
                        try result.appendSlice(num_str);
                        try result.append(';');
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
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "encode_ext",
        };
    }

    /// 测试 html_entity_decode
    fn testHtmlEntityDecode(self: *@This()) !StringOpResult {
        const test_name = "html_entity_decode";
        const test_string = "&lt;script&gt;alert(&quot;XSS&quot;);&lt;/script&gt;";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "&lt;script&gt;alert(&quot;XSS&quot;);&lt;/script&gt;";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = html_entity_decode($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try std.mem.replaceOwned(u8, self.allocator, test_string, "&lt;", "<");
            defer self.allocator.free(result);
            const result2 = try std.mem.replaceOwned(u8, self.allocator, result, "&gt;", ">");
            defer self.allocator.free(result2);
            const result3 = try std.mem.replaceOwned(u8, self.allocator, result2, "&quot;", "\"");
            defer self.allocator.free(result3);
            const result4 = try std.mem.replaceOwned(u8, self.allocator, result3, "&amp;", "&");
            defer self.allocator.free(result4);
            total_len += result4.len;
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
            .category = "encode_ext",
        };
    }

    /// 测试 htmlspecialchars_decode
    fn testHtmlspecialcharsDecode(self: *@This()) !StringOpResult {
        const test_name = "htmlspecialchars_decode";
        const test_string = "&lt;tag&gt; &amp; &quot;quotes&quot;";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "&lt;tag&gt; &amp; &quot;quotes&quot;";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = htmlspecialchars_decode($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try std.mem.replaceOwned(u8, self.allocator, test_string, "&lt;", "<");
            defer self.allocator.free(result);
            const result2 = try std.mem.replaceOwned(u8, self.allocator, result, "&gt;", ">");
            defer self.allocator.free(result2);
            const result3 = try std.mem.replaceOwned(u8, self.allocator, result2, "&quot;", "\"");
            defer self.allocator.free(result3);
            const result4 = try std.mem.replaceOwned(u8, self.allocator, result3, "&amp;", "&");
            defer self.allocator.free(result4);
            total_len += result4.len;
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
            .category = "encode_ext",
        };
    }

    /// 测试 urlencode
    fn testUrlencode(self: *@This()) !StringOpResult {
        const test_name = "urlencode";
        const test_string = "Hello World! This is a test & demo.";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello World! This is a test & demo.";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = urlencode($str);
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
                if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
                    try result.append(c);
                } else if (c == ' ') {
                    try result.append('+');
                } else {
                    try result.append('%');
                    const hex = std.fmt.bytesToHex(&[_]u8{c}, .upper);
                    try result.appendSlice(&hex);
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
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "encode_ext",
        };
    }

    /// 测试 urldecode
    fn testUrldecode(self: *@This()) !StringOpResult {
        const test_name = "urldecode";
        const test_string = "Hello+World%21+This+is+a+test+%26+demo.";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello+World%21+This+is+a+test+%26+demo.";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = urldecode($str);
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
            while (idx < test_string.len) {
                if (test_string[idx] == '+') {
                    try result.append(' ');
                    idx += 1;
                } else if (test_string[idx] == '%' and idx + 2 < test_string.len) {
                    const hex_str = test_string[idx + 1 .. idx + 3];
                    const byte = std.fmt.parseInt(u8, hex_str, 16) catch {
                        try result.append(test_string[idx]);
                        idx += 1;
                        continue;
                    };
                    try result.append(byte);
                    idx += 3;
                } else {
                    try result.append(test_string[idx]);
                    idx += 1;
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
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "encode_ext",
        };
    }

    /// 测试 rawurlencode
    fn testRawurlencode(self: *@This()) !StringOpResult {
        const test_name = "rawurlencode";
        const test_string = "Hello World! Test & Demo";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello World! Test & Demo";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = rawurlencode($str);
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
                if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
                    try result.append(c);
                } else {
                    try result.append('%');
                    const hex = std.fmt.bytesToHex(&[_]u8{c}, .upper);
                    try result.appendSlice(&hex);
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
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "encode_ext",
        };
    }

    /// 测试 rawurldecode
    fn testRawurldecode(self: *@This()) !StringOpResult {
        const test_name = "rawurldecode";
        const test_string = "Hello%20World%21%20Test%20%26%20Demo";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello%20World%21%20Test%20%26%20Demo";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = rawurldecode($str);
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
            while (idx < test_string.len) {
                if (test_string[idx] == '%' and idx + 2 < test_string.len) {
                    const hex_str = test_string[idx + 1 .. idx + 3];
                    const byte = std.fmt.parseInt(u8, hex_str, 16) catch {
                        try result.append(test_string[idx]);
                        idx += 1;
                        continue;
                    };
                    try result.append(byte);
                    idx += 3;
                } else {
                    try result.append(test_string[idx]);
                    idx += 1;
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
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "encode_ext",
        };
    }

    /// 测试 nl2br (换行转 BR 标签)
    fn testNl2br(self: *@This()) !StringOpResult {
        const test_name = "nl2br";
        const test_string = "Line 1\nLine 2\nLine 3\nLine 4";

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Line 1\nLine 2\nLine 3\nLine 4";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = nl2br($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try std.mem.replaceOwned(u8, self.allocator, test_string, "\n", "<br />\n");
            defer self.allocator.free(result);
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
            .category = "encode_ext",
        };
    }

    /// 测试 wordwrap (单词换行)
    fn testWordwrap(self: *@This()) !StringOpResult {
        const test_name = "wordwrap";
        const test_string = "The quick brown fox jumps over the lazy dog and runs away";
        const width: usize = 20;

        if (self.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "The quick brown fox jumps over the lazy dog and runs away";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = wordwrap($str, 20);
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

            var line_len: usize = 0;
            var last_space: ?usize = null;

            for (test_string, 0..) |c, idx| {
                if (c == ' ') {
                    last_space = result.items.len;
                }

                try result.append(c);
                line_len += 1;

                if (line_len >= width and last_space != null) {
                    result.items[last_space.?] = '\n';
                    line_len = idx - last_space.?;
                    last_space = null;
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
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{ test_name, ops_per_sec / 1_000_000.0 });
        }

        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.iterations,
            .category = "encode_ext",
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
