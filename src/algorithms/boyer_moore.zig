const std = @import("std");
const Allocator = std.mem.Allocator;

/// Boyer-Moore 字符串搜索算法
pub const BoyerMoore = struct {
    allocator: Allocator,
    /// 坏字符表
    bad_char_table: [256]usize,
    /// 好后缀表
    good_suffix_table: []usize,
    /// 模式串
    pattern: []const u8,

    pub fn init(allocator: Allocator, pattern: []const u8) !BoyerMoore {
        var self = BoyerMoore{
            .allocator = allocator,
            .bad_char_table = undefined,
            .good_suffix_table = try allocator.alloc(usize, pattern.len),
            .pattern = pattern,
        };

        try self.buildBadCharTable();
        try self.buildGoodSuffixTable();

        return self;
    }

    pub fn deinit(self: *BoyerMoore) void {
        self.allocator.free(self.good_suffix_table);
    }

    fn buildBadCharTable(self: *BoyerMoore) !void {
        // 初始化为模式长度
        @memset(&self.bad_char_table, self.pattern.len);

        // 填充每个字符最后出现的位置
        for (self.pattern, 0..) |c, i| {
            self.bad_char_table[c] = self.pattern.len - 1 - i;
        }
    }

    fn buildGoodSuffixTable(self: *BoyerMoore) !void {
        const m = self.pattern.len;
        
        // 简化实现：所有位置都使用模式长度
        for (self.good_suffix_table) |*entry| {
            entry.* = m;
        }
    }

    pub fn search(self: *BoyerMoore, text: []const u8) ?usize {
        const m = self.pattern.len;
        const n = text.len;

        if (m == 0) return 0;
        if (m > n) return null;

        var i: usize = 0;
        while (i <= n - m) {
            var j: isize = @as(isize, @intCast(m)) - 1;

            while (j >= 0 and self.pattern[@intCast(j)] == text[i + @as(usize, @intCast(j))]) {
                if (j == 0) return i;
                j -= 1;
            }

            // 计算跳跃距离（简化：只使用坏字符表）
            const uj: usize = @intCast(j);
            const bad_char_shift = if (uj < m) self.bad_char_table[text[i + uj]] else 1;
            i += @max(bad_char_shift, 1);
        }

        return null;
    }
};
