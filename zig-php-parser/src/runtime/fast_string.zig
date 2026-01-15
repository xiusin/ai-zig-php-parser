//! 高性能字符串系统
//! 目标：零拷贝操作，O(1)查找，缓存友好
//!
//! 核心技术：
//! 1. FNV-1a 哈希 - 快速且分布均匀
//! 2. Open Addressing - 缓存友好的探测
//! 3. SSO (Small String Optimization) - 短字符串内联
//! 4. 字符串切片共享 - 避免拷贝

const std = @import("std");

// ============================================================================
// FNV-1a 哈希 - 快速字符串哈希
// ============================================================================

pub const FNV_OFFSET: u64 = 0xcbf29ce484222325;
pub const FNV_PRIME: u64 = 0x100000001b3;

pub fn fnv1a(data: []const u8) u64 {
    var h: u64 = FNV_OFFSET;
    for (data) |b| {
        h ^= b;
        h *%= FNV_PRIME;
    }
    return h;
}

/// 编译时 FNV-1a
pub fn comptime_fnv1a(comptime s: []const u8) u64 {
    var h: u64 = FNV_OFFSET;
    for (s) |b| {
        h ^= b;
        h *%= FNV_PRIME;
    }
    return h;
}

// ============================================================================
// SSO 字符串 - 短字符串优化
// ============================================================================

pub const SSOString = extern struct {
    const INLINE_CAP = 23;

    data: extern union {
        inline_data: extern struct {
            buf: [INLINE_CAP]u8,
            len: u8, // 高位为0表示内联
        },
        heap_data: extern struct {
            ptr: [*]u8,
            len: u32,
            cap: u32,
            _pad: [7]u8,
            tag: u8, // 高位为1表示堆
        },
    },

    pub fn initInline(s: []const u8) SSOString {
        std.debug.assert(s.len <= INLINE_CAP);
        var result: SSOString = undefined;
        @memcpy(result.data.inline_data.buf[0..s.len], s);
        result.data.inline_data.len = @intCast(s.len);
        return result;
    }

    pub fn initHeap(allocator: std.mem.Allocator, s: []const u8) !SSOString {
        const ptr = try allocator.alloc(u8, s.len);
        @memcpy(ptr, s);
        var result: SSOString = undefined;
        result.data.heap_data.ptr = ptr.ptr;
        result.data.heap_data.len = @intCast(s.len);
        result.data.heap_data.cap = @intCast(s.len);
        result.data.heap_data.tag = 0x80;
        return result;
    }

    pub fn init(allocator: std.mem.Allocator, s: []const u8) !SSOString {
        if (s.len <= INLINE_CAP) {
            return initInline(s);
        }
        return initHeap(allocator, s);
    }

    pub fn deinit(self: *SSOString, allocator: std.mem.Allocator) void {
        if (self.isHeap()) {
            allocator.free(self.data.heap_data.ptr[0..self.data.heap_data.cap]);
        }
    }

    pub fn isHeap(self: *const SSOString) bool {
        return (self.data.heap_data.tag & 0x80) != 0;
    }

    pub fn slice(self: *const SSOString) []const u8 {
        if (self.isHeap()) {
            return self.data.heap_data.ptr[0..self.data.heap_data.len];
        }
        return self.data.inline_data.buf[0..self.data.inline_data.len];
    }

    pub fn len(self: *const SSOString) usize {
        if (self.isHeap()) return self.data.heap_data.len;
        return self.data.inline_data.len;
    }

    pub fn eql(self: *const SSOString, other: []const u8) bool {
        return std.mem.eql(u8, self.slice(), other);
    }

    pub fn hash(self: *const SSOString) u64 {
        return fnv1a(self.slice());
    }

    // ========================================================================
    // Task 3.2.5: Concat 优化 - 短字符串连接保持内联
    // ========================================================================

    /// 连接两个字符串，尽可能保持内联
    pub fn concat(self: *const SSOString, other: *const SSOString, allocator: std.mem.Allocator) !SSOString {
        const self_slice = self.slice();
        const other_slice = other.slice();
        const total_len = self_slice.len + other_slice.len;

        // 如果结果可以内联，直接内联存储
        if (total_len <= INLINE_CAP) {
            var result: SSOString = undefined;
            @memcpy(result.data.inline_data.buf[0..self_slice.len], self_slice);
            @memcpy(result.data.inline_data.buf[self_slice.len..total_len], other_slice);
            result.data.inline_data.len = @intCast(total_len);
            return result;
        }

        // 否则分配堆内存
        const ptr = try allocator.alloc(u8, total_len);
        @memcpy(ptr[0..self_slice.len], self_slice);
        @memcpy(ptr[self_slice.len..], other_slice);

        var result: SSOString = undefined;
        result.data.heap_data.ptr = ptr.ptr;
        result.data.heap_data.len = @intCast(total_len);
        result.data.heap_data.cap = @intCast(total_len);
        result.data.heap_data.tag = 0x80;
        return result;
    }

    /// 连接字符串切片，尽可能保持内联
    pub fn concatSlice(self: *const SSOString, other: []const u8, allocator: std.mem.Allocator) !SSOString {
        const self_slice = self.slice();
        const total_len = self_slice.len + other.len;

        if (total_len <= INLINE_CAP) {
            var result: SSOString = undefined;
            @memcpy(result.data.inline_data.buf[0..self_slice.len], self_slice);
            @memcpy(result.data.inline_data.buf[self_slice.len..total_len], other);
            result.data.inline_data.len = @intCast(total_len);
            return result;
        }

        const ptr = try allocator.alloc(u8, total_len);
        @memcpy(ptr[0..self_slice.len], self_slice);
        @memcpy(ptr[self_slice.len..], other);

        var result: SSOString = undefined;
        result.data.heap_data.ptr = ptr.ptr;
        result.data.heap_data.len = @intCast(total_len);
        result.data.heap_data.cap = @intCast(total_len);
        result.data.heap_data.tag = 0x80;
        return result;
    }

    /// 追加字符，尽可能保持内联
    pub fn appendChar(self: *SSOString, c: u8, allocator: std.mem.Allocator) !void {
        const current_len = self.len();

        if (!self.isHeap() and current_len < INLINE_CAP) {
            // 内联追加
            self.data.inline_data.buf[current_len] = c;
            self.data.inline_data.len = @intCast(current_len + 1);
            return;
        }

        // 需要转换为堆或扩展堆
        if (self.isHeap()) {
            // 检查容量
            if (current_len < self.data.heap_data.cap) {
                self.data.heap_data.ptr[current_len] = c;
                self.data.heap_data.len = @intCast(current_len + 1);
                return;
            }
            // 需要扩展
            const new_cap = self.data.heap_data.cap * 2;
            const new_ptr = try allocator.realloc(self.data.heap_data.ptr[0..self.data.heap_data.cap], new_cap);
            new_ptr[current_len] = c;
            self.data.heap_data.ptr = new_ptr.ptr;
            self.data.heap_data.len = @intCast(current_len + 1);
            self.data.heap_data.cap = @intCast(new_cap);
        } else {
            // 从内联转换为堆
            const old_slice = self.slice();
            const new_cap: usize = 32;
            const ptr = try allocator.alloc(u8, new_cap);
            @memcpy(ptr[0..old_slice.len], old_slice);
            ptr[old_slice.len] = c;
            self.data.heap_data.ptr = ptr.ptr;
            self.data.heap_data.len = @intCast(current_len + 1);
            self.data.heap_data.cap = @intCast(new_cap);
            self.data.heap_data.tag = 0x80;
        }
    }

    /// 从多个切片创建字符串
    pub fn fromSlices(allocator: std.mem.Allocator, slices: []const []const u8) !SSOString {
        var total_len: usize = 0;
        for (slices) |s| {
            total_len += s.len;
        }

        if (total_len <= INLINE_CAP) {
            var result: SSOString = undefined;
            var offset: usize = 0;
            for (slices) |s| {
                @memcpy(result.data.inline_data.buf[offset..][0..s.len], s);
                offset += s.len;
            }
            result.data.inline_data.len = @intCast(total_len);
            return result;
        }

        const ptr = try allocator.alloc(u8, total_len);
        var offset: usize = 0;
        for (slices) |s| {
            @memcpy(ptr[offset..][0..s.len], s);
            offset += s.len;
        }

        var result: SSOString = undefined;
        result.data.heap_data.ptr = ptr.ptr;
        result.data.heap_data.len = @intCast(total_len);
        result.data.heap_data.cap = @intCast(total_len);
        result.data.heap_data.tag = 0x80;
        return result;
    }

    /// 复制字符串
    pub fn clone(self: *const SSOString, allocator: std.mem.Allocator) !SSOString {
        if (!self.isHeap()) {
            // 内联字符串直接复制结构
            return self.*;
        }
        // 堆字符串需要分配新内存
        return initHeap(allocator, self.slice());
    }

    /// 比较两个 SSOString
    pub fn eqlSso(self: *const SSOString, other: *const SSOString) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }
};

// ============================================================================
// 高性能字符串驻留池
// ============================================================================

pub const StringPool = struct {
    const INIT_CAP = 1024;
    const LOAD_FACTOR = 0.75;

    const Entry = struct {
        hash: u64,
        str: []const u8,
        refs: u32,
    };

    allocator: std.mem.Allocator,
    entries: []?Entry,
    count: usize,
    mask: usize,

    // 统计
    hits: usize,
    misses: usize,

    pub fn init(allocator: std.mem.Allocator) !StringPool {
        const entries = try allocator.alloc(?Entry, INIT_CAP);
        @memset(entries, null);
        return .{
            .allocator = allocator,
            .entries = entries,
            .count = 0,
            .mask = INIT_CAP - 1,
            .hits = 0,
            .misses = 0,
        };
    }

    pub fn deinit(self: *StringPool) void {
        for (self.entries) |e| {
            if (e) |entry| {
                self.allocator.free(@constCast(entry.str));
            }
        }
        self.allocator.free(self.entries);
    }

    /// 驻留字符串 - O(1) 平均
    pub fn intern(self: *StringPool, s: []const u8) ![]const u8 {
        if (self.needsResize()) try self.resize();

        const h = fnv1a(s);
        var idx = h & self.mask;
        var dist: usize = 0;

        while (true) : ({
            idx = (idx + 1) & self.mask;
            dist += 1;
        }) {
            if (self.entries[idx]) |*e| {
                if (e.hash == h and std.mem.eql(u8, e.str, s)) {
                    e.refs += 1;
                    self.hits += 1;
                    return e.str;
                }
            } else {
                // 插入新条目
                const owned = try self.allocator.dupe(u8, s);
                self.entries[idx] = .{ .hash = h, .str = owned, .refs = 1 };
                self.count += 1;
                self.misses += 1;
                return owned;
            }

            if (dist > 32) break; // 防止无限循环
        }

        return error.HashTableFull;
    }

    /// 查找（不增加引用）
    pub fn lookup(self: *const StringPool, s: []const u8) ?[]const u8 {
        const h = fnv1a(s);
        var idx = h & self.mask;
        var dist: usize = 0;

        while (dist < 32) : ({
            idx = (idx + 1) & self.mask;
            dist += 1;
        }) {
            if (self.entries[idx]) |e| {
                if (e.hash == h and std.mem.eql(u8, e.str, s)) {
                    return e.str;
                }
            } else {
                return null;
            }
        }
        return null;
    }

    /// 释放引用
    pub fn release(self: *StringPool, s: []const u8) void {
        const h = fnv1a(s);
        var idx = h & self.mask;
        var dist: usize = 0;

        while (dist < 32) : ({
            idx = (idx + 1) & self.mask;
            dist += 1;
        }) {
            if (self.entries[idx]) |*e| {
                if (e.hash == h and std.mem.eql(u8, e.str, s)) {
                    if (e.refs > 0) e.refs -= 1;
                    if (e.refs == 0) {
                        self.allocator.free(@constCast(e.str));
                        self.entries[idx] = null;
                        self.count -= 1;
                    }
                    return;
                }
            } else {
                return;
            }
        }
    }

    fn needsResize(self: *const StringPool) bool {
        return @as(f64, @floatFromInt(self.count)) > @as(f64, @floatFromInt(self.entries.len)) * LOAD_FACTOR;
    }

    fn resize(self: *StringPool) !void {
        const new_cap = self.entries.len * 2;
        const new_entries = try self.allocator.alloc(?Entry, new_cap);
        @memset(new_entries, null);

        const new_mask = new_cap - 1;
        for (self.entries) |e| {
            if (e) |entry| {
                var idx = entry.hash & new_mask;
                while (new_entries[idx] != null) {
                    idx = (idx + 1) & new_mask;
                }
                new_entries[idx] = entry;
            }
        }

        self.allocator.free(self.entries);
        self.entries = new_entries;
        self.mask = new_mask;
    }

    pub fn hitRate(self: *const StringPool) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }
};

// ============================================================================
// 预计算的 PHP 关键字哈希
// ============================================================================

pub const Keywords = struct {
    pub const @"if" = comptime_fnv1a("if");
    pub const @"else" = comptime_fnv1a("else");
    pub const @"while" = comptime_fnv1a("while");
    pub const @"for" = comptime_fnv1a("for");
    pub const foreach = comptime_fnv1a("foreach");
    pub const function = comptime_fnv1a("function");
    pub const @"return" = comptime_fnv1a("return");
    pub const class = comptime_fnv1a("class");
    pub const public = comptime_fnv1a("public");
    pub const private = comptime_fnv1a("private");
    pub const protected = comptime_fnv1a("protected");
    pub const static = comptime_fnv1a("static");
    pub const @"const" = comptime_fnv1a("const");
    pub const new = comptime_fnv1a("new");
    pub const @"try" = comptime_fnv1a("try");
    pub const @"catch" = comptime_fnv1a("catch");
    pub const throw = comptime_fnv1a("throw");
    pub const echo = comptime_fnv1a("echo");
    pub const print = comptime_fnv1a("print");
    pub const array = comptime_fnv1a("array");
    pub const null_kw = comptime_fnv1a("null");
    pub const true_kw = comptime_fnv1a("true");
    pub const false_kw = comptime_fnv1a("false");

    /// 快速关键字检查
    pub fn isKeyword(h: u64) bool {
        return h == @"if" or h == @"else" or h == @"while" or h == @"for" or
            h == foreach or h == function or h == @"return" or h == class or
            h == public or h == private or h == protected or h == static or
            h == @"const" or h == new or h == @"try" or h == @"catch" or
            h == throw or h == echo or h == print or h == array or
            h == null_kw or h == true_kw or h == false_kw;
    }
};

// ============================================================================
// 字符串切片 - 零拷贝子串
// ============================================================================

pub const StringSlice = struct {
    base: []const u8,
    start: u32,
    end: u32,

    pub fn init(base: []const u8, start: usize, end: usize) StringSlice {
        return .{
            .base = base,
            .start = @intCast(start),
            .end = @intCast(end),
        };
    }

    pub fn slice(self: StringSlice) []const u8 {
        return self.base[self.start..self.end];
    }

    pub fn len(self: StringSlice) usize {
        return self.end - self.start;
    }

    pub fn subslice(self: StringSlice, start: usize, end: usize) StringSlice {
        return .{
            .base = self.base,
            .start = self.start + @as(u32, @intCast(start)),
            .end = self.start + @as(u32, @intCast(end)),
        };
    }
};

// ============================================================================
// 测试
// ============================================================================

test "fnv1a" {
    try std.testing.expect(fnv1a("hello") == comptime_fnv1a("hello"));
    try std.testing.expect(fnv1a("") == FNV_OFFSET);
}

test "SSOString inline" {
    var s = SSOString.initInline("hello");
    try std.testing.expectEqualStrings("hello", s.slice());
    try std.testing.expect(!s.isHeap());
}

test "SSOString heap" {
    const long = "this is a very long string that exceeds inline capacity";
    var s = try SSOString.initHeap(std.testing.allocator, long);
    defer s.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(long, s.slice());
    try std.testing.expect(s.isHeap());
}

test "StringPool" {
    var pool = try StringPool.init(std.testing.allocator);
    defer pool.deinit();

    const s1 = try pool.intern("hello");
    const s2 = try pool.intern("hello");
    try std.testing.expect(s1.ptr == s2.ptr);
    try std.testing.expect(pool.hits == 1);
}

test "Keywords" {
    try std.testing.expect(Keywords.isKeyword(fnv1a("if")));
    try std.testing.expect(Keywords.isKeyword(fnv1a("function")));
    try std.testing.expect(!Keywords.isKeyword(fnv1a("myvar")));
}

test "StringSlice" {
    const base = "hello world";
    const s = StringSlice.init(base, 0, 5);
    try std.testing.expectEqualStrings("hello", s.slice());

    const sub = s.subslice(1, 4);
    try std.testing.expectEqualStrings("ell", sub.slice());
}

test "SSOString concat inline" {
    // 两个短字符串连接保持内联
    const s1 = SSOString.initInline("hello");
    const s2 = SSOString.initInline(" world");
    var result = try s1.concat(&s2, std.testing.allocator);
    defer if (result.isHeap()) result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("hello world", result.slice());
    try std.testing.expect(!result.isHeap()); // 应该保持内联
}

test "SSOString concat to heap" {
    // 连接结果超过内联容量
    const s1 = SSOString.initInline("this is a longer");
    const s2 = SSOString.initInline(" string test");
    var result = try s1.concat(&s2, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("this is a longer string test", result.slice());
    try std.testing.expect(result.isHeap()); // 应该在堆上
}

test "SSOString concatSlice" {
    const s1 = SSOString.initInline("hello");
    var result = try s1.concatSlice(" world!", std.testing.allocator);
    defer if (result.isHeap()) result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("hello world!", result.slice());
    try std.testing.expect(!result.isHeap());
}

test "SSOString fromSlices" {
    const slices = [_][]const u8{ "hello", " ", "world" };
    var result = try SSOString.fromSlices(std.testing.allocator, &slices);
    defer if (result.isHeap()) result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("hello world", result.slice());
    try std.testing.expect(!result.isHeap());
}

test "SSOString clone" {
    // 克隆内联字符串
    const s1 = SSOString.initInline("hello");
    var s2 = try s1.clone(std.testing.allocator);
    try std.testing.expectEqualStrings("hello", s2.slice());

    // 克隆堆字符串
    const long = "this is a very long string that exceeds inline capacity";
    var s3 = try SSOString.initHeap(std.testing.allocator, long);
    defer s3.deinit(std.testing.allocator);
    var s4 = try s3.clone(std.testing.allocator);
    defer s4.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(long, s4.slice());
}
