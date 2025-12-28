const std = @import("std");

/// 处理双引号字符串中的转义序列
/// 支持: \n, \r, \t, \\, \", \$, \0, \x[0-9a-fA-F]{1,2}
pub fn processEscapeSequences(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, input.len);
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            const next = input[i + 1];
            switch (next) {
                'n' => {
                    try result.append(allocator, '\n');
                    i += 2;
                },
                'r' => {
                    try result.append(allocator, '\r');
                    i += 2;
                },
                't' => {
                    try result.append(allocator, '\t');
                    i += 2;
                },
                '\\' => {
                    try result.append(allocator, '\\');
                    i += 2;
                },
                '"' => {
                    try result.append(allocator, '"');
                    i += 2;
                },
                '$' => {
                    try result.append(allocator, '$');
                    i += 2;
                },
                '0' => {
                    try result.append(allocator, 0);
                    i += 2;
                },
                'x' => {
                    if (i + 2 < input.len) {
                        var hex_len: usize = 0;
                        var hex_val: u8 = 0;

                        var j: usize = i + 2;
                        while (j < input.len and j < i + 4 and std.ascii.isHex(input[j])) {
                            const digit = std.fmt.charToDigit(input[j], 16) catch break;
                            hex_val = hex_val * 16 + digit;
                            hex_len += 1;
                            j += 1;
                        }

                        if (hex_len > 0) {
                            try result.append(allocator, hex_val);
                            i = j;
                        } else {
                            try result.append(allocator, '\\');
                            i += 1;
                        }
                    } else {
                        try result.append(allocator, '\\');
                        i += 1;
                    }
                },
                'u' => {
                    if (i + 2 < input.len and input[i + 2] == '{') {
                        var j: usize = i + 3;
                        var codepoint: u21 = 0;
                        var valid = false;

                        while (j < input.len and input[j] != '}') {
                            if (std.ascii.isHex(input[j])) {
                                const digit = std.fmt.charToDigit(input[j], 16) catch break;
                                codepoint = codepoint * 16 + digit;
                                j += 1;
                            } else {
                                break;
                            }
                        }

                        if (j < input.len and input[j] == '}') {
                            valid = true;
                            j += 1;
                        }

                        if (valid and codepoint <= 0x10FFFF) {
                            var buf: [4]u8 = undefined;
                            const len = std.unicode.utf8Encode(codepoint, &buf) catch 0;
                            if (len > 0) {
                                try result.appendSlice(allocator, buf[0..len]);
                                i = j;
                            } else {
                                try result.append(allocator, '\\');
                                i += 1;
                            }
                        } else {
                            try result.append(allocator, '\\');
                            i += 1;
                        }
                    } else {
                        try result.append(allocator, '\\');
                        i += 1;
                    }
                },
                else => {
                    try result.append(allocator, input[i]);
                    i += 1;
                },
            }
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// 处理单引号字符串中的转义序列
/// 单引号字符串只支持: \\, \'
pub fn processSingleQuoteEscapes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, input.len);
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            const next = input[i + 1];
            switch (next) {
                '\\' => {
                    try result.append(allocator, '\\');
                    i += 2;
                },
                '\'' => {
                    try result.append(allocator, '\'');
                    i += 2;
                },
                else => {
                    // 其他转义序列在单引号字符串中保持原样
                    try result.append(allocator, input[i]);
                    i += 1;
                },
            }
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// 检查字符串是否包含需要处理的转义序列
pub fn hasEscapeSequences(input: []const u8) bool {
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            const next = input[i + 1];
            switch (next) {
                'n', 'r', 't', '\\', '"', '$', '0', 'x', 'u' => return true,
                else => {},
            }
        }
        i += 1;
    }
    return false;
}

test "escape sequences" {
    const allocator = std.testing.allocator;

    const result1 = try processEscapeSequences(allocator, "hello\\nworld");
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("hello\nworld", result1);

    const result2 = try processEscapeSequences(allocator, "tab\\there");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("tab\there", result2);

    const result3 = try processEscapeSequences(allocator, "quote\\\"test");
    defer allocator.free(result3);
    try std.testing.expectEqualStrings("quote\"test", result3);
}
