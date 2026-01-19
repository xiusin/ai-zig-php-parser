// 字符串转换测试辅助模块
// 包含 strtoupper, strtolower, ucfirst, ucwords 等转换函数的测试

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
    
    /// 运行所有转换测试
    pub fn runAll(self: *Self) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);
        
        if (self.verbose) {
            std.debug.print("\n=== 字符串转换性能测试 ===\n", .{});
        }
        
        try results.append(try self.testStrtoupper());
        try results.append(try self.testStrtolower());
        try results.append(try self.testUcfirst());
        try results.append(try self.testLcfirst());
        try results.append(try self.testUcwords());
        try results.append(try self.testStrrev());
        try results.append(try self.testStrRepeat());
        try results.append(try self.testStrShuffle());
        
        return results.toOwnedSlice();
    }
    
    /// 测试 strtoupper
    fn testStrtoupper(self: *Self) !StringOpResult {
        const test_name = "strtoupper";
        const test_string = "the quick brown fox jumps over the lazy dog";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try self.allocator.alloc(u8, test_string.len);
            defer self.allocator.free(result);
            _ = std.ascii.upperString(result, test_string);
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
    
    /// 测试 strtolower
    fn testStrtolower(self: *Self) !StringOpResult {
        const test_name = "strtolower";
        const test_string = "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try self.allocator.alloc(u8, test_string.len);
            defer self.allocator.free(result);
            _ = std.ascii.lowerString(result, test_string);
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
    
    /// 测试 ucfirst
    fn testUcfirst(self: *Self) !StringOpResult {
        const test_name = "ucfirst";
        const test_string = "hello world";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try self.allocator.alloc(u8, test_string.len);
            defer self.allocator.free(result);
            @memcpy(result, test_string);
            if (result.len > 0) {
                result[0] = std.ascii.toUpper(result[0]);
            }
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
    
    /// 测试 lcfirst
    fn testLcfirst(self: *Self) !StringOpResult {
        const test_name = "lcfirst";
        const test_string = "HELLO WORLD";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try self.allocator.alloc(u8, test_string.len);
            defer self.allocator.free(result);
            @memcpy(result, test_string);
            if (result.len > 0) {
                result[0] = std.ascii.toLower(result[0]);
            }
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
    
    /// 测试 ucwords
    fn testUcwords(self: *Self) !StringOpResult {
        const test_name = "ucwords";
        const test_string = "the quick brown fox";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try self.allocator.alloc(u8, test_string.len);
            defer self.allocator.free(result);
            @memcpy(result, test_string);
            
            var capitalize_next = true;
            for (result) |*c| {
                if (std.ascii.isWhitespace(c.*)) {
                    capitalize_next = true;
                } else if (capitalize_next) {
                    c.* = std.ascii.toUpper(c.*);
                    capitalize_next = false;
                }
            }
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
    
    /// 测试 strrev
    fn testStrrev(self: *Self) !StringOpResult {
        const test_name = "strrev";
        const test_string = "The quick brown fox jumps over the lazy dog";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try self.allocator.alloc(u8, test_string.len);
            defer self.allocator.free(result);
            std.mem.reverse(u8, result);
            @memcpy(result, test_string);
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
    
    /// 测试 str_repeat
    fn testStrRepeat(self: *Self) !StringOpResult {
        const test_name = "str_repeat";
        const test_string = "x";
        const repeat_count: usize = 10;
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try self.allocator.alloc(u8, test_string.len * repeat_count);
            defer self.allocator.free(result);
            
            var j: usize = 0;
            while (j < repeat_count) : (j += 1) {
                @memcpy(result[j * test_string.len..][0..test_string.len], test_string);
            }
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
    
    /// 测试 str_shuffle
    fn testStrShuffle(self: *Self) !StringOpResult {
        const test_name = "str_shuffle";
        const test_string = "Hello World";
        
        const start = std.time.nanoTimestamp();
        
        var total_len: usize = 0;
        var i: u32 = 0;
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        
        while (i < self.iterations) : (i += 1) {
            const result = try self.allocator.alloc(u8, test_string.len);
            defer self.allocator.free(result);
            @memcpy(result, test_string);
            random.shuffle(u8, result);
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
