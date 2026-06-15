//! 字符串操作性能测试
//!
//! 实现完整的字符串操作性能测试，覆盖 80+ PHP 字符串函数
//!
//! ## 需求
//! - 需求 6.3：测试字符串操作时，覆盖所有 80+ 字符串函数
//! - 每个测试执行 10,000 次迭代
//! - 与原生 PHP 进行性能对比
//! - 目标：所有字符串函数性能达到原生 PHP 的 110-150%
//!
//! ## 测试分类
//! 1. 字符串查找与替换（strlen, strpos, str_replace等）
//! 2. 字符串转换（strtoupper, strtolower, ucfirst等）
//! 3. 字符串分割与连接（explode, implode, str_split等）
//! 4. 字符串比较（strcmp, strcasecmp, strnatcmp等）
//! 5. 字符串修剪（trim, ltrim, rtrim等）
//! 6. 字符串编码（htmlspecialchars, urlencode等）
//! 7. 字符串格式化（sprintf, printf, number_format等）
//! 8. 字符串解析（parse_str, str_getcsv等）

const std = @import("std");
const Allocator = std.mem.Allocator;
const framework = @import("framework.zig");

/// 字符串测试配置
pub const StringBenchmarkConfig = struct {
    /// 迭代次数
    iterations: u32 = 10_000,
    /// 是否启用详细日志
    verbose: bool = false,
    /// 是否生成 PHP 测试脚本
    generate_php_scripts: bool = true,
    /// 测试脚本输出目录
    script_output_dir: []const u8 = "tests/benchmarks/string",
};

/// 字符串操作测试结果
pub const StringOpResult = struct {
    test_name: []const u8,
    operations_per_second: f64,
    total_time_ns: u64,
    iterations: u32,
    category: []const u8,
};

/// 字符串测试套件结果
pub const StringBenchmarkResult = struct {
    search_results: []StringOpResult,
    transform_results: []StringOpResult,
    split_results: []StringOpResult,
    compare_results: []StringOpResult,
    trim_results: []StringOpResult,
    encode_results: []StringOpResult,
    format_results: []StringOpResult,
    parse_results: []StringOpResult,
    total_time_ns: u64,
    timestamp: i64,
};

/// 字符串性能测试
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED
pub const StringBenchmark = struct {
    allocator: Allocator,
    config: StringBenchmarkConfig,
    framework_instance: *framework.BenchmarkFramework,
    
    const Self = @This();
    
    /// 初始化测试
    pub fn init(allocator: Allocator, config: StringBenchmarkConfig) !*Self {
        const self = try allocator.create(Self);
        
        const framework_config = framework.BenchmarkConfig{
            .warmup_iterations = 100,
            .test_iterations = config.iterations,
            .verbose = config.verbose,
        };
        
        self.* = .{
            .allocator = allocator,
            .config = config,
            .framework_instance = try framework.BenchmarkFramework.init(allocator, framework_config),
        };
        
        // 创建测试脚本目录
        if (config.generate_php_scripts) {
            std.fs.cwd.makePath(config.script_output_dir) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }
        
        return self;
    }
    
    /// 清理资源
    pub fn deinit(self: *Self) void {
        self.framework_instance.deinit();
        self.allocator.destroy(self);
    }
    
    /// 运行所有测试
    pub fn runAllTests(self: *Self) !StringBenchmarkResult {
        const start_time = std.time.nanoTimestamp();
        
        const search_results = try self.runSearchTests();
        const search_ext_results = try self.runSearchExtTests();
        const transform_results = try self.runTransformTests();
        const transform_ext_results = try self.runTransformExtTests();
        const split_results = try self.runSplitTests();
        const compare_results = try self.runCompareTests();
        const trim_results = try self.runTrimTests();
        const encode_results = try self.runEncodeTests();
        const encode_ext_results = try self.runEncodeExtTests();
        const format_results = try self.runFormatTests();
        const format_ext_results = try self.runFormatExtTests();
        const parse_results = try self.runParseTests();
        const parse_ext_results = try self.runParseExtTests();
        const misc_ext_results = try self.runMiscExtTests();
        
        // 合并搜索结果
        var all_search = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        try all_search.appendSlice(self.allocator, search_results);
        try all_search.appendSlice(self.allocator, search_ext_results);
        const merged_search = try all_search.toOwnedSlice(self.allocator);
        
        // 合并转换结果
        var all_transform = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        try all_transform.appendSlice(self.allocator, transform_results);
        try all_transform.appendSlice(self.allocator, transform_ext_results);
        const merged_transform = try all_transform.toOwnedSlice(self.allocator);
        
        // 合并编码结果
        var all_encode = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        try all_encode.appendSlice(self.allocator, encode_results);
        try all_encode.appendSlice(self.allocator, encode_ext_results);
        try all_encode.appendSlice(self.allocator, misc_ext_results);
        const merged_encode = try all_encode.toOwnedSlice(self.allocator);
        
        // 合并格式化结果
        var all_format = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        try all_format.appendSlice(self.allocator, format_results);
        try all_format.appendSlice(self.allocator, format_ext_results);
        const merged_format = try all_format.toOwnedSlice(self.allocator);
        
        // 合并解析结果
        var all_parse = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        try all_parse.appendSlice(self.allocator, parse_results);
        try all_parse.appendSlice(self.allocator, parse_ext_results);
        const merged_parse = try all_parse.toOwnedSlice(self.allocator);
        
        const end_time = std.time.nanoTimestamp();
        
        return StringBenchmarkResult{
            .search_results = merged_search,
            .transform_results = merged_transform,
            .split_results = split_results,
            .compare_results = compare_results,
            .trim_results = trim_results,
            .encode_results = merged_encode,
            .format_results = merged_format,
            .parse_results = merged_parse,
            .total_time_ns = @intCast(end_time - start_time),
            .timestamp = std.time.timestamp(),
        };
    }
    
    // ========================================================================
    // 字符串查找与替换测试
    // ========================================================================
    
    /// 运行字符串查找测试
    pub fn runSearchTests(self: *Self) ![]StringOpResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 字符串查找与替换性能测试 ===\n", .{});
        }
        
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        
        try results.append(self.allocator, try self.testStrlen());
        try results.append(self.allocator, try self.testStrpos());
        try results.append(try self.testStrrpos());
        try results.append(try self.testStripos());
        try results.append(try self.testStrstr());
        try results.append(try self.testStrReplace());
        try results.append(try self.testStrIreplace());
        try results.append(try self.testSubstr());
        try results.append(try self.testSubstrCount());
        try results.append(try self.testStrPad());
        
        return results.toOwnedSlice();
    }
    
    /// 测试 strlen
    fn testStrlen(self: *Self) !StringOpResult {
        const test_name = "strlen";
        const test_string = "Hello, World! This is a test string for performance benchmarking.";
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name, 
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello, World! This is a test string for performance benchmarking.";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $len = strlen($str);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            total_len += test_string.len;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_len);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 strpos
    fn testStrpos(self: *Self) !StringOpResult {
        const test_name = "strpos";
        const haystack = "The quick brown fox jumps over the lazy dog";
        const needle = "fox";
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox jumps over the lazy dog";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $pos = strpos($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_pos: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            if (std.mem.indexOf(u8, haystack, needle)) |pos| {
                total_pos += pos;
            }
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_pos);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 strrpos
    fn testStrrpos(self: *Self) !StringOpResult {
        const test_name = "strrpos";
        const haystack = "The quick brown fox jumps over the lazy fox";
        const needle = "fox";
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox jumps over the lazy fox";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $pos = strrpos($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_pos: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            if (std.mem.lastIndexOf(u8, haystack, needle)) |pos| {
                total_pos += pos;
            }
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_pos);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 stripos（不区分大小写查找）
    fn testStripos(self: *Self) !StringOpResult {
        const test_name = "stripos";
        const haystack = "The Quick Brown FOX Jumps Over The Lazy Dog";
        const needle = "fox";
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The Quick Brown FOX Jumps Over The Lazy Dog";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $pos = stripos($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_pos: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            // 不区分大小写查找
            const haystack_lower = try self.allocator.alloc(u8, haystack.len);
            defer self.allocator.free(haystack_lower);
            _ = std.ascii.lowerString(haystack_lower, haystack);
            
            if (std.mem.indexOf(u8, haystack_lower, needle)) |pos| {
                total_pos += pos;
            }
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_pos);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 strstr（查找子串）
    fn testStrstr(self: *Self) !StringOpResult {
        const test_name = "strstr";
        const haystack = "The quick brown fox jumps over the lazy dog";
        const needle = "fox";
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox jumps over the lazy dog";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = strstr($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            if (std.mem.indexOf(u8, haystack, needle)) |pos| {
                total_len += haystack.len - pos;
            }
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_len);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 str_replace（字符串替换）
    fn testStrReplace(self: *Self) !StringOpResult {
        const test_name = "str_replace";
        const haystack = "The quick brown fox jumps over the lazy dog";
        const search = "fox";
        const replace = "cat";
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox jumps over the lazy dog";
                \\$search = "fox";
                \\$replace = "cat";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = str_replace($search, $replace, $haystack);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const result = try std.mem.replaceOwned(u8, self.allocator, haystack, search, replace);
            defer self.allocator.free(result);
            total_len += result.len;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_len);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 str_ireplace（不区分大小写替换）
    fn testStrIreplace(self: *Self) !StringOpResult {
        const test_name = "str_ireplace";
        const haystack = "The quick brown FOX jumps over the lazy dog";
        const search = "fox";
        const replace = "cat";
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown FOX jumps over the lazy dog";
                \\$search = "fox";
                \\$replace = "cat";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = str_ireplace($search, $replace, $haystack);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            // 转换为小写后替换
            const haystack_lower = try self.allocator.alloc(u8, haystack.len);
            defer self.allocator.free(haystack_lower);
            _ = std.ascii.lowerString(haystack_lower, haystack);
            
            const result = try std.mem.replaceOwned(u8, self.allocator, haystack_lower, search, replace);
            defer self.allocator.free(result);
            total_len += result.len;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_len);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 substr（子串提取）
    fn testSubstr(self: *Self) !StringOpResult {
        const test_name = "substr";
        const str = "The quick brown fox jumps over the lazy dog";
        const start_pos: usize = 10;
        const length: usize = 15;
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "The quick brown fox jumps over the lazy dog";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = substr($str, 10, 15);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const end_pos = @min(start_pos + length, str.len);
            const substr = str[start_pos..end_pos];
            total_len += substr.len;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_len);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 substr_count（子串计数）
    fn testSubstrCount(self: *Self) !StringOpResult {
        const test_name = "substr_count";
        const haystack = "The quick brown fox jumps over the lazy fox and another fox";
        const needle = "fox";
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$haystack = "The quick brown fox jumps over the lazy fox and another fox";
                \\$needle = "fox";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $count = substr_count($haystack, $needle);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_count: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            var count: usize = 0;
            var pos: usize = 0;
            while (std.mem.indexOfPos(u8, haystack, pos, needle)) |found_pos| {
                count += 1;
                pos = found_pos + needle.len;
            }
            total_count += count;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_count);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    /// 测试 str_pad（字符串填充）
    fn testStrPad(self: *Self) !StringOpResult {
        const test_name = "str_pad";
        const str = "Hello";
        const pad_length: usize = 20;
        const pad_char = ' ';
        
        if (self.config.generate_php_scripts) {
            try self.generatePhpScript(test_name,
                \\<?php
                \\$iterations = 10000;
                \\$str = "Hello";
                \\$start = hrtime(true);
                \\for ($i = 0; $i < $iterations; $i++) {
                \\    $result = str_pad($str, 20, ' ', STR_PAD_RIGHT);
                \\}
                \\$end = hrtime(true);
                \\echo "Time: " . (($end - $start) / 1000000) . " ms\n";
            );
        }
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            var result = try self.allocator.alloc(u8, pad_length);
            defer self.allocator.free(result);
            
            @memcpy(result[0..str.len], str);
            @memset(result[str.len..], pad_char);
            total_len += result.len;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&total_len);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return StringOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
            .category = "search",
        };
    }
    
    // ========================================================================
    // 字符串查找扩展测试
    // ========================================================================
    
    /// 运行字符串查找扩展测试
    pub fn runSearchExtTests(self: *Self) ![]StringOpResult {
        const search_ext = @import("string_benchmark_search_ext.zig");
        var search_ext_tests = search_ext.StringSearchExtTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
            .generate_php_scripts = self.config.generate_php_scripts,
            .script_output_dir = self.config.script_output_dir,
        };
        return try search_ext_tests.runAll();
    }
    
    // ========================================================================
    // 字符串转换测试
    // ========================================================================
    
    /// 运行字符串转换测试
    pub fn runTransformTests(self: *Self) ![]StringOpResult {
        const transforms = @import("string_benchmark_transforms.zig");
        var transform_tests = transforms.StringTransformTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
            .generate_php_scripts = self.config.generate_php_scripts,
            .script_output_dir = self.config.script_output_dir,
        };
        return try transform_tests.runAll();
    }
    
    // ========================================================================
    // 字符串转换扩展测试
    // ========================================================================
    
    /// 运行字符串转换扩展测试
    pub fn runTransformExtTests(self: *Self) ![]StringOpResult {
        const transform_ext = @import("string_benchmark_transform_ext.zig");
        var transform_ext_tests = transform_ext.StringTransformExtTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
            .generate_php_scripts = self.config.generate_php_scripts,
            .script_output_dir = self.config.script_output_dir,
        };
        return try transform_ext_tests.runAll();
    }
    
    // ========================================================================
    // 字符串分割与连接测试
    // ========================================================================
    
    /// 运行字符串分割测试
    pub fn runSplitTests(self: *Self) ![]StringOpResult {
        const splits = @import("string_benchmark_split.zig");
        var split_tests = splits.StringSplitTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
        };
        return try split_tests.runAll();
    }
    
    // ========================================================================
    // 字符串比较测试
    // ========================================================================
    
    /// 运行字符串比较测试
    pub fn runCompareTests(self: *Self) ![]StringOpResult {
        const misc = @import("string_benchmark_misc.zig");
        var compare_tests = misc.StringCompareTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
        };
        return try compare_tests.runAll();
    }
    
    // ========================================================================
    // 字符串修剪测试
    // ========================================================================
    
    /// 运行字符串修剪测试
    pub fn runTrimTests(self: *Self) ![]StringOpResult {
        const misc = @import("string_benchmark_misc.zig");
        var trim_tests = misc.StringTrimTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
        };
        return try trim_tests.runAll();
    }
    
    // ========================================================================
    // 字符串编码测试
    // ========================================================================
    
    /// 运行字符串编码测试
    pub fn runEncodeTests(self: *Self) ![]StringOpResult {
        const misc = @import("string_benchmark_misc.zig");
        var encode_tests = misc.StringEncodeTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
        };
        return try encode_tests.runAll();
    }
    
    // ========================================================================
    // 字符串编码扩展测试
    // ========================================================================
    
    /// 运行字符串编码扩展测试
    pub fn runEncodeExtTests(self: *Self) ![]StringOpResult {
        const encode_ext = @import("string_benchmark_encode_ext.zig");
        var encode_ext_tests = encode_ext.StringEncodeExtTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
            .generate_php_scripts = self.config.generate_php_scripts,
            .script_output_dir = self.config.script_output_dir,
        };
        return try encode_ext_tests.runAll();
    }
    
    // ========================================================================
    // 字符串格式化测试
    // ========================================================================
    
    /// 运行字符串格式化测试
    pub fn runFormatTests(self: *Self) ![]StringOpResult {
        const misc = @import("string_benchmark_misc.zig");
        var format_tests = misc.StringFormatTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
        };
        return try format_tests.runAll();
    }
    
    // ========================================================================
    // 字符串格式化扩展测试
    // ========================================================================
    
    /// 运行字符串格式化扩展测试
    pub fn runFormatExtTests(self: *Self) ![]StringOpResult {
        const format_ext = @import("string_benchmark_format_ext.zig");
        var format_ext_tests = format_ext.StringFormatExtTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
            .generate_php_scripts = self.config.generate_php_scripts,
            .script_output_dir = self.config.script_output_dir,
        };
        return try format_ext_tests.runAll();
    }
    
    // ========================================================================
    // 字符串解析测试
    // ========================================================================
    
    /// 运行字符串解析测试
    pub fn runParseTests(self: *Self) ![]StringOpResult {
        const misc = @import("string_benchmark_misc.zig");
        var parse_tests = misc.StringParseTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
        };
        return try parse_tests.runAll();
    }
    
    // ========================================================================
    // 字符串解析扩展测试
    // ========================================================================
    
    /// 运行字符串解析扩展测试
    pub fn runParseExtTests(self: *Self) ![]StringOpResult {
        const parse_ext = @import("string_benchmark_parse_ext.zig");
        var parse_ext_tests = parse_ext.StringParseExtTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
            .generate_php_scripts = self.config.generate_php_scripts,
            .script_output_dir = self.config.script_output_dir,
        };
        return try parse_ext_tests.runAll();
    }
    
    // ========================================================================
    // 字符串其他扩展测试
    // ========================================================================
    
    /// 运行字符串其他扩展测试
    pub fn runMiscExtTests(self: *Self) ![]StringOpResult {
        const misc_ext = @import("string_benchmark_misc_ext.zig");
        var misc_ext_tests = misc_ext.StringMiscExtTests{
            .allocator = self.allocator,
            .iterations = self.config.iterations,
            .verbose = self.config.verbose,
            .generate_php_scripts = self.config.generate_php_scripts,
            .script_output_dir = self.config.script_output_dir,
        };
        return try misc_ext_tests.runAll();
    }
    
    // ========================================================================
    // 辅助函数
    // ========================================================================
    
    /// 生成 PHP 测试脚本
    fn generatePhpScript(self: *Self, test_name: []const u8, script_content: []const u8) !void {
        const file_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.php",
            .{ self.config.script_output_dir, test_name },
        );
        defer self.allocator.free(file_path);
        
        const file = try std.fs.cwd.createFile(file_path, .{});
        defer file.close();
        
        try file.writeAll(script_content);
    }
};
