const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;

/// StringWrapper - 字符串方法封装
/// 提供完整的字符串操作方法，通过 -> 语法调用
pub const StringWrapper = struct {
    allocator: std.mem.Allocator,
    string: *PHPString,

    pub fn init(allocator: std.mem.Allocator, string: *PHPString) StringWrapper {
        return .{
            .allocator = allocator,
            .string = string,
        };
    }

    pub fn toUpper(self: *StringWrapper) !*PHPString {
        const result = try self.allocator.alloc(u8, self.string.length);
        for (self.string.data, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }
        return PHPString.init(self.allocator, result);
    }

    pub fn toLower(self: *StringWrapper) !*PHPString {
        const result = try self.allocator.alloc(u8, self.string.length);
        for (self.string.data, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return PHPString.init(self.allocator, result);
    }

    pub fn trim(self: *StringWrapper) !*PHPString {
        var start: usize = 0;
        var end: usize = self.string.length;

        while (start < end and std.ascii.isWhitespace(self.string.data[start])) {
            start += 1;
        }

        while (end > start and std.ascii.isWhitespace(self.string.data[end - 1])) {
            end -= 1;
        }

        if (start >= end) {
            return PHPString.init(self.allocator, "");
        }

        return PHPString.init(self.allocator, self.string.data[start..end]);
    }

    pub fn length(self: *const StringWrapper) usize {
        return self.string.length;
    }

    pub fn replace(self: *StringWrapper, search: []const u8, replacement: []const u8) !*PHPString {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < self.string.length) {
            if (i + search.len <= self.string.length and 
                std.mem.eql(u8, self.string.data[i..i + search.len], search)) {
                try result.appendSlice(replacement);
                i += search.len;
            } else {
                try result.append(self.string.data[i]);
                i += 1;
            }
        }

        return PHPString.init(self.allocator, result.items);
    }

    pub fn substring(self: *StringWrapper, start: i64, len: ?i64) !*PHPString {
        const start_idx: usize = if (start < 0) 0 else @intCast(start);
        if (start_idx >= self.string.length) {
            return PHPString.init(self.allocator, "");
        }

        const end_idx: usize = if (len) |l| {
            const length: usize = @intCast(@max(0, l));
            @min(start_idx + length, self.string.length);
        } else {
            self.string.length;
        };

        return PHPString.init(self.allocator, self.string.data[start_idx..end_idx]);
    }

    pub fn indexOf(self: *const StringWrapper, needle: []const u8) ?i64 {
        if (needle.len == 0 or needle.len > self.string.length) return null;

        var i: usize = 0;
        while (i <= self.string.length - needle.len) : (i += 1) {
            if (std.mem.eql(u8, self.string.data[i..i + needle.len], needle)) {
                return @intCast(i);
            }
        }
        return null;
    }

    pub fn split(self: *StringWrapper, delimiter: []const u8) !*types.PHPArray {
        const array = try self.allocator.create(types.PHPArray);
        array.* = types.PHPArray.init(self.allocator);

        if (delimiter.len == 0) {
            for (self.string.data, 0..) |c, i| {
                const char_str = try PHPString.init(self.allocator, &[_]u8{c});
                const value = try Value.initString(self.allocator, char_str);
                try array.push(self.allocator, value);
                _ = i;
            }
            return array;
        }

        var start: usize = 0;
        var i: usize = 0;
        while (i <= self.string.length - delimiter.len) : (i += 1) {
            if (std.mem.eql(u8, self.string.data[i..i + delimiter.len], delimiter)) {
                const part = try PHPString.init(self.allocator, self.string.data[start..i]);
                const value = try Value.initString(self.allocator, part);
                try array.push(self.allocator, value);
                i += delimiter.len - 1;
                start = i + 1;
            }
        }

        const last_part = try PHPString.init(self.allocator, self.string.data[start..]);
        const last_value = try Value.initString(self.allocator, last_part);
        try array.push(self.allocator, last_value);

        return array;
    }
};
