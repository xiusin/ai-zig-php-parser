// 字符串分割和连接测试辅助模块
// 包含 explode, implode, str_split, chunk_split 等函数的测试

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

/// 字符串分割连接测试辅助结构
pub const StringSplitTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,

    const Self = @This();

    /// 运行所有分割连接测试
    pub fn runAll(self: *Self) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串分割与连接性能测试 ===\n", .{});
        }

        try results.append(try self.testExplode());
        try results.append(try self.testImplode());
        try results.append(try self.testStrSplit());
        try results.append(try self.testChunkSplit());
        try results.append(try self.testStrWordCount());

        return results.toOwnedSlice();
    }

    /// 测试 explode
    fn testExplode(self: *Self) !StringOpResult {
        const test_name = "explode";
        const test_string = "The quick brown fox jumps over the lazy dog";
        const delimiter = " ";

        const start = std.time.nanoTimestamp();

        var total_count: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var iter = std.mem.splitSequence(u8, test_string, delimiter);
            var count: usize = 0;
            while (iter.next()) |_| {
                count += 1;
            }
            total_count += count;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_count);

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
            .category = "split",
        };
    }

    /// 测试 implode
    fn testImplode(self: *Self) !StringOpResult {
        const test_name = "implode";
        const parts = [_][]const u8{ "The", "quick", "brown", "fox" };
        const delimiter = " ";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try std.mem.join(self.allocator, delimiter, &parts);
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
            .category = "split",
        };
    }

    /// 测试 str_split
    fn testStrSplit(self: *Self) !StringOpResult {
        const test_name = "str_split";
        const test_string = "Hello World";
        const chunk_size: usize = 2;

        const start = std.time.nanoTimestamp();

        var total_count: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var pos: usize = 0;
            var count: usize = 0;
            while (pos < test_string.len) {
                const end_pos = @min(pos + chunk_size, test_string.len);
                _ = test_string[pos..end_pos];
                pos = end_pos;
                count += 1;
            }
            total_count += count;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_count);

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
            .category = "split",
        };
    }

    /// 测试 chunk_split
    fn testChunkSplit(self: *Self) !StringOpResult {
        const test_name = "chunk_split";
        const test_string = "The quick brown fox jumps over the lazy dog";
        const chunk_size: usize = 10;
        const separator = "\n";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
            defer result.deinit();

            var pos: usize = 0;
            while (pos < test_string.len) {
                const end_pos = @min(pos + chunk_size, test_string.len);
                try result.appendSlice(test_string[pos..end_pos]);
                if (end_pos < test_string.len) {
                    try result.appendSlice(separator);
                }
                pos = end_pos;
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
            .category = "split",
        };
    }

    /// 测试 str_word_count
    fn testStrWordCount(self: *Self) !StringOpResult {
        const test_name = "str_word_count";
        const test_string = "The quick brown fox jumps over the lazy dog";

        const start = std.time.nanoTimestamp();

        var total_count: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            var count: usize = 0;
            var in_word = false;

            for (test_string) |c| {
                if (std.ascii.isWhitespace(c)) {
                    in_word = false;
                } else if (!in_word) {
                    count += 1;
                    in_word = true;
                }
            }
            total_count += count;
        }

        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));

        std.mem.doNotOptimizeAway(&total_count);

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
            .category = "split",
        };
    }
};
