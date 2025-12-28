const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const gc = types.gc;
const VM = @import("vm.zig").VM;

/// StringWrapper - 包装字符串变量，提供链式方法调用
/// 类似JavaScript的String对象，支持流畅的API设计
pub const StringWrapper = struct {
    allocator: std.mem.Allocator,
    value: *PHPString,

    pub fn init(allocator: std.mem.Allocator, str: []const u8) !StringWrapper {
        return StringWrapper{
            .allocator = allocator,
            .value = try PHPString.init(allocator, str),
        };
    }

    pub fn initFromPHPString(allocator: std.mem.Allocator, php_string: *PHPString) StringWrapper {
        php_string.retain();
        return StringWrapper{
            .allocator = allocator,
            .value = php_string,
        };
    }

    pub fn deinit(self: *StringWrapper) void {
        self.value.release(self.allocator);
    }

    /// 获取字符串长度
    pub fn length(self: *const StringWrapper) usize {
        return self.value.length;
    }

    /// 获取原始数据
    pub fn data(self: *const StringWrapper) []const u8 {
        return self.value.data;
    }

    /// 转换为大写
    pub fn toUpper(self: *StringWrapper) !StringWrapper {
        var new_data = try self.allocator.alloc(u8, self.value.length);
        for (self.value.data, 0..) |c, i| {
            new_data[i] = std.ascii.toUpper(c);
        }
        const result = try self.allocator.create(PHPString);
        result.* = .{
            .data = new_data,
            .length = self.value.length,
            .encoding = self.value.encoding,
            .ref_count = 1,
        };
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 转换为小写
    pub fn toLower(self: *StringWrapper) !StringWrapper {
        var new_data = try self.allocator.alloc(u8, self.value.length);
        for (self.value.data, 0..) |c, i| {
            new_data[i] = std.ascii.toLower(c);
        }
        const result = try self.allocator.create(PHPString);
        result.* = .{
            .data = new_data,
            .length = self.value.length,
            .encoding = self.value.encoding,
            .ref_count = 1,
        };
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 去除首尾空白
    pub fn trim(self: *StringWrapper) !StringWrapper {
        const trimmed = std.mem.trim(u8, self.value.data, " \t\r\n");
        const result = try PHPString.init(self.allocator, trimmed);
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 去除左侧空白
    pub fn trimLeft(self: *StringWrapper) !StringWrapper {
        const trimmed = std.mem.trimLeft(u8, self.value.data, " \t\r\n");
        const result = try PHPString.init(self.allocator, trimmed);
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 去除右侧空白
    pub fn trimRight(self: *StringWrapper) !StringWrapper {
        const trimmed = std.mem.trimRight(u8, self.value.data, " \t\r\n");
        const result = try PHPString.init(self.allocator, trimmed);
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 字符串替换
    pub fn replace(self: *StringWrapper, search: []const u8, replacement: []const u8) !StringWrapper {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var i: usize = 0;
        while (i < self.value.length) {
            if (i + search.len <= self.value.length and
                std.mem.eql(u8, self.value.data[i .. i + search.len], search))
            {
                try result.appendSlice(replacement);
                i += search.len;
            } else {
                try result.append(self.value.data[i]);
                i += 1;
            }
        }

        const php_str = try PHPString.init(self.allocator, result.items);
        result.deinit();
        return StringWrapper{ .allocator = self.allocator, .value = php_str };
    }

    /// 分割字符串
    pub fn split(self: *StringWrapper, delimiter: []const u8) ![]StringWrapper {
        var parts = std.ArrayList(StringWrapper).init(self.allocator);
        errdefer {
            for (parts.items) |*part| {
                part.deinit();
            }
            parts.deinit();
        }

        var iter = std.mem.splitSequence(u8, self.value.data, delimiter);
        while (iter.next()) |part| {
            const wrapper = try StringWrapper.init(self.allocator, part);
            try parts.append(wrapper);
        }

        return parts.toOwnedSlice();
    }

    /// 子字符串
    pub fn substring(self: *StringWrapper, start: i64, len: ?i64) !StringWrapper {
        const start_idx: usize = if (start < 0) 0 else @min(@as(usize, @intCast(start)), self.value.length);
        const end_idx: usize = if (len) |l| blk: {
            if (l < 0) break :blk self.value.length;
            break :blk @min(start_idx + @as(usize, @intCast(l)), self.value.length);
        } else self.value.length;

        if (start_idx >= end_idx) {
            return StringWrapper.init(self.allocator, "");
        }

        const result = try PHPString.init(self.allocator, self.value.data[start_idx..end_idx]);
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 查找子字符串位置
    pub fn indexOf(self: *const StringWrapper, needle: []const u8) i64 {
        if (needle.len == 0) return 0;
        if (needle.len > self.value.length) return -1;

        if (std.mem.indexOf(u8, self.value.data, needle)) |pos| {
            return @intCast(pos);
        }
        return -1;
    }

    /// 从末尾查找子字符串位置
    pub fn lastIndexOf(self: *const StringWrapper, needle: []const u8) i64 {
        if (needle.len == 0) return @intCast(self.value.length);
        if (needle.len > self.value.length) return -1;

        if (std.mem.lastIndexOf(u8, self.value.data, needle)) |pos| {
            return @intCast(pos);
        }
        return -1;
    }

    /// 是否包含子字符串
    pub fn contains(self: *const StringWrapper, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.value.data, needle) != null;
    }

    /// 是否以指定前缀开头
    pub fn startsWith(self: *const StringWrapper, prefix: []const u8) bool {
        return std.mem.startsWith(u8, self.value.data, prefix);
    }

    /// 是否以指定后缀结尾
    pub fn endsWith(self: *const StringWrapper, suffix: []const u8) bool {
        return std.mem.endsWith(u8, self.value.data, suffix);
    }

    /// 连接字符串
    pub fn concat(self: *StringWrapper, other: []const u8) !StringWrapper {
        const new_len = self.value.length + other.len;
        var new_data = try self.allocator.alloc(u8, new_len);
        @memcpy(new_data[0..self.value.length], self.value.data);
        @memcpy(new_data[self.value.length..], other);

        const result = try self.allocator.create(PHPString);
        result.* = .{
            .data = new_data,
            .length = new_len,
            .encoding = self.value.encoding,
            .ref_count = 1,
        };
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 重复字符串
    pub fn repeat(self: *StringWrapper, count: usize) !StringWrapper {
        if (count == 0) {
            return StringWrapper.init(self.allocator, "");
        }

        const new_len = self.value.length * count;
        var new_data = try self.allocator.alloc(u8, new_len);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            @memcpy(new_data[i * self.value.length .. (i + 1) * self.value.length], self.value.data);
        }

        const result = try self.allocator.create(PHPString);
        result.* = .{
            .data = new_data,
            .length = new_len,
            .encoding = self.value.encoding,
            .ref_count = 1,
        };
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 填充到指定长度（左侧）
    pub fn padLeft(self: *StringWrapper, total_len: usize, pad_char: u8) !StringWrapper {
        if (self.value.length >= total_len) {
            self.value.retain();
            return StringWrapper{ .allocator = self.allocator, .value = self.value };
        }

        const pad_len = total_len - self.value.length;
        var new_data = try self.allocator.alloc(u8, total_len);
        @memset(new_data[0..pad_len], pad_char);
        @memcpy(new_data[pad_len..], self.value.data);

        const result = try self.allocator.create(PHPString);
        result.* = .{
            .data = new_data,
            .length = total_len,
            .encoding = self.value.encoding,
            .ref_count = 1,
        };
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 填充到指定长度（右侧）
    pub fn padRight(self: *StringWrapper, total_len: usize, pad_char: u8) !StringWrapper {
        if (self.value.length >= total_len) {
            self.value.retain();
            return StringWrapper{ .allocator = self.allocator, .value = self.value };
        }

        var new_data = try self.allocator.alloc(u8, total_len);
        @memcpy(new_data[0..self.value.length], self.value.data);
        @memset(new_data[self.value.length..], pad_char);

        const result = try self.allocator.create(PHPString);
        result.* = .{
            .data = new_data,
            .length = total_len,
            .encoding = self.value.encoding,
            .ref_count = 1,
        };
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 反转字符串
    pub fn reverse(self: *StringWrapper) !StringWrapper {
        var new_data = try self.allocator.alloc(u8, self.value.length);
        var i: usize = 0;
        while (i < self.value.length) : (i += 1) {
            new_data[i] = self.value.data[self.value.length - 1 - i];
        }

        const result = try self.allocator.create(PHPString);
        result.* = .{
            .data = new_data,
            .length = self.value.length,
            .encoding = self.value.encoding,
            .ref_count = 1,
        };
        return StringWrapper{ .allocator = self.allocator, .value = result };
    }

    /// 转换为Value
    pub fn toValue(self: *StringWrapper, memory_manager: *gc.MemoryManager) !Value {
        return Value.initStringWithManager(memory_manager, self.value.data);
    }
};

/// 注册String类的内置方法到VM
pub fn registerStringMethods(vm: anytype) !void {
    _ = vm;
    // 这里会在VM中注册String类的方法
    // 方法调用通过method_call AST节点处理
}

test "StringWrapper basic operations" {
    const allocator = std.testing.allocator;

    var wrapper = try StringWrapper.init(allocator, "hello world");
    defer wrapper.deinit();

    try std.testing.expectEqual(@as(usize, 11), wrapper.length());
    try std.testing.expectEqualStrings("hello world", wrapper.data());

    var upper = try wrapper.toUpper();
    defer upper.deinit();
    try std.testing.expectEqualStrings("HELLO WORLD", upper.data());

    var lower = try wrapper.toLower();
    defer lower.deinit();
    try std.testing.expectEqualStrings("hello world", lower.data());
}

test "StringWrapper trim operations" {
    const allocator = std.testing.allocator;

    var wrapper = try StringWrapper.init(allocator, "  hello  ");
    defer wrapper.deinit();

    var trimmed = try wrapper.trim();
    defer trimmed.deinit();
    try std.testing.expectEqualStrings("hello", trimmed.data());
}

test "StringWrapper search operations" {
    const allocator = std.testing.allocator;

    var wrapper = try StringWrapper.init(allocator, "hello world");
    defer wrapper.deinit();

    try std.testing.expectEqual(@as(i64, 6), wrapper.indexOf("world"));
    try std.testing.expectEqual(@as(i64, -1), wrapper.indexOf("foo"));
    try std.testing.expect(wrapper.contains("world"));
    try std.testing.expect(wrapper.startsWith("hello"));
    try std.testing.expect(wrapper.endsWith("world"));
}
