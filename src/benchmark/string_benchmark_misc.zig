// 字符串其他操作测试辅助模块
// 包含比较、修剪、编码、格式化等函数的测试

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringOpResult = @import("string_benchmark.zig").StringOpResult;

/// 字符串比较测试
pub const StringCompareTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,

    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串比较性能测试 ===\n", .{});
        }

        try results.append(try self.testStrcmp());
        try results.append(try self.testStrcasecmp());
        try results.append(try self.testStrncmp());

        return results.toOwnedSlice();
    }

    fn testStrcmp(self: *@This()) !StringOpResult {
        const test_name = "strcmp";
        const str1 = "Hello World";
        const str2 = "Hello World";

        const start = std.time.nanoTimestamp();

        var total: i32 = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const cmp = std.mem.order(u8, str1, str2);
            total += @intFromEnum(cmp);
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
            .category = "compare",
        };
    }

    fn testStrcasecmp(self: *@This()) !StringOpResult {
        const test_name = "strcasecmp";
        const str1 = "Hello World";
        const str2 = "hello world";

        const start = std.time.nanoTimestamp();

        var total: i32 = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const cmp = std.ascii.eqlIgnoreCase(str1, str2);
            total += if (cmp) 0 else 1;
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
            .category = "compare",
        };
    }

    fn testStrncmp(self: *@This()) !StringOpResult {
        const test_name = "strncmp";
        const str1 = "Hello World";
        const str2 = "Hello PHP";
        const n: usize = 5;

        const start = std.time.nanoTimestamp();

        var total: i32 = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const cmp = std.mem.order(u8, str1[0..n], str2[0..n]);
            total += @intFromEnum(cmp);
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
            .category = "compare",
        };
    }
};

/// 字符串修剪测试
pub const StringTrimTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,

    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串修剪性能测试 ===\n", .{});
        }

        try results.append(try self.testTrim());
        try results.append(try self.testLtrim());
        try results.append(try self.testRtrim());

        return results.toOwnedSlice();
    }

    fn testTrim(self: *@This()) !StringOpResult {
        const test_name = "trim";
        const test_string = "  Hello World  ";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const trimmed = std.mem.trim(u8, test_string, " \t\n\r");
            total_len += trimmed.len;
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
            .category = "trim",
        };
    }

    fn testLtrim(self: *@This()) !StringOpResult {
        const test_name = "ltrim";
        const test_string = "  Hello World";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const trimmed = std.mem.trimLeft(u8, test_string, " \t\n\r");
            total_len += trimmed.len;
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
            .category = "trim",
        };
    }

    fn testRtrim(self: *@This()) !StringOpResult {
        const test_name = "rtrim";
        const test_string = "Hello World  ";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const trimmed = std.mem.trimRight(u8, test_string, " \t\n\r");
            total_len += trimmed.len;
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
            .category = "trim",
        };
    }
};

/// 字符串编码测试
pub const StringEncodeTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,

    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串编码性能测试 ===\n", .{});
        }

        try results.append(try self.testBase64Encode());
        try results.append(try self.testBase64Decode());
        try results.append(try self.testHexEncode());

        return results.toOwnedSlice();
    }

    fn testBase64Encode(self: *@This()) !StringOpResult {
        const test_name = "base64_encode";
        const test_string = "The quick brown fox jumps over the lazy dog";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        const encoder = std.base64.standard.Encoder;

        while (i < self.iterations) : (i += 1) {
            const encoded_len = encoder.calcSize(test_string.len);
            const result = try self.allocator.alloc(u8, encoded_len);
            defer self.allocator.free(result);
            _ = encoder.encode(result, test_string);
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
            .category = "encode",
        };
    }

    fn testBase64Decode(self: *@This()) !StringOpResult {
        const test_name = "base64_decode";
        const test_string = "VGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZw==";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        const decoder = std.base64.standard.Decoder;

        while (i < self.iterations) : (i += 1) {
            const decoded_len = try decoder.calcSizeForSlice(test_string);
            const result = try self.allocator.alloc(u8, decoded_len);
            defer self.allocator.free(result);
            try decoder.decode(result, test_string);
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
            .category = "encode",
        };
    }

    fn testHexEncode(self: *@This()) !StringOpResult {
        const test_name = "hex_encode";
        const test_string = "Hello World";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;

        while (i < self.iterations) : (i += 1) {
            const result = std.fmt.bytesToHex(test_string, .lower);
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
            .category = "encode",
        };
    }
};

/// 字符串格式化测试
pub const StringFormatTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,

    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串格式化性能测试 ===\n", .{});
        }

        try results.append(try self.testSprintf());
        try results.append(try self.testNumberFormat());

        return results.toOwnedSlice();
    }

    fn testSprintf(self: *@This()) !StringOpResult {
        const test_name = "sprintf";

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try std.fmt.allocPrint(self.allocator, "Number: {d}, String: {s}", .{ i, "Hello" });
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
            .category = "format",
        };
    }

    fn testNumberFormat(self: *@This()) !StringOpResult {
        const test_name = "number_format";
        const number: f64 = 1234567.89;

        const start = std.time.nanoTimestamp();

        var total_len: usize = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const result = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{number});
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
            .category = "format",
        };
    }
};

/// 字符串解析测试
pub const StringParseTests = struct {
    allocator: Allocator,
    iterations: u32,
    verbose: bool,

    pub fn runAll(self: *@This()) ![]StringOpResult {
        var results = std.array_list.AlignedManaged(StringOpResult, null).init(self.allocator);

        if (self.verbose) {
            std.debug.print("\n=== 字符串解析性能测试 ===\n", .{});
        }

        try results.append(try self.testParseInt());
        try results.append(try self.testParseFloat());

        return results.toOwnedSlice();
    }

    fn testParseInt(self: *@This()) !StringOpResult {
        const test_name = "parse_int";
        const test_string = "12345";

        const start = std.time.nanoTimestamp();

        var total: i64 = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const value = try std.fmt.parseInt(i64, test_string, 10);
            total += value;
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
            .category = "parse",
        };
    }

    fn testParseFloat(self: *@This()) !StringOpResult {
        const test_name = "parse_float";
        const test_string = "123.45";

        const start = std.time.nanoTimestamp();

        var total: f64 = 0;
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            const value = try std.fmt.parseFloat(f64, test_string);
            total += value;
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
            .category = "parse",
        };
    }
};
