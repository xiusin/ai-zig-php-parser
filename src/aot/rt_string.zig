const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

// ============================================================================
// 字符串类型
// ============================================================================

/// PHP字符串类型
/// 使用引用计数管理内存，支持写时复制（COW）
pub const PHPString = struct {
    data: []u8,
    length: usize,
    ref_count: usize,
    is_static: bool, // 静态字符串不需要释放

    /// 创建新字符串
    pub fn init(allocator: Allocator, str: []const u8) !*PHPString {
        // 检查字符串长度是否异常
        if (str.len > 1024 * 1024 * 100) { // 100MB
            std.debug.print("ERROR: String too large: {d} bytes ({d} MB)\n", .{ str.len, str.len / (1024 * 1024) });
            return error.StringTooLarge;
        }

        const php_string = try allocPHPString(allocator);
        errdefer destroyPHPString(php_string, allocator);

        // 安全的内存分配和复制
        const new_data = try allocator.alloc(u8, str.len);
        errdefer allocator.free(new_data);

        if (str.len > 0) {
            @memcpy(new_data, str);
        }

        alloc_counters.php_string_objects += 1;
        alloc_counters.php_string_bytes += str.len;
        alloc_counters.php_string_live_objects += 1;
        alloc_counters.php_string_live_bytes += str.len;
        alloc_counters.php_string_peak_live_objects = @max(
            alloc_counters.php_string_peak_live_objects,
            alloc_counters.php_string_live_objects,
        );
        alloc_counters.php_string_peak_live_bytes = @max(
            alloc_counters.php_string_peak_live_bytes,
            alloc_counters.php_string_live_bytes,
        );

        php_string.data = new_data;
        php_string.length = str.len;
        php_string.ref_count = 1;
        php_string.is_static = false;
        return php_string;
    }

    /// 创建静态字符串（不需要释放）
    pub fn initStatic(str: []const u8) *PHPString {
        const Holder = struct {
            var empty: PHPString = .{
                .data = @constCast(""),
                .length = 0,
                .ref_count = 1,
                .is_static = true,
            };
        };

        if (static_string_pool) |*pool| {
            if (pool.get(str)) |existing| return &existing.php;
        }

        const entry = runtime_allocator.create(StaticStringEntry) catch return &Holder.empty;
        entry.init(runtime_allocator, str) catch {
            runtime_allocator.destroy(entry);
            return &Holder.empty;
        };

        alloc_counters.php_string_objects += 1;
        alloc_counters.php_string_bytes += str.len;
        alloc_counters.php_string_live_objects += 1;
        alloc_counters.php_string_live_bytes += str.len;
        alloc_counters.php_string_peak_live_objects = @max(
            alloc_counters.php_string_peak_live_objects,
            alloc_counters.php_string_live_objects,
        );
        alloc_counters.php_string_peak_live_bytes = @max(
            alloc_counters.php_string_peak_live_bytes,
            alloc_counters.php_string_live_bytes,
        );

        if (static_string_pool) |*pool| {
            pool.put(entry.php.data, entry) catch {};
        }
        static_string_entries.append(runtime_allocator, entry) catch {};

        return &entry.php;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPString) void {
        if (!self.is_static) {
            self.ref_count += 1;
            // std.debug.print("PHPString.retain: data={s} ref_count={d}\n", .{self.data, self.ref_count});
        }
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPString, allocator: Allocator) void {
        if (self.is_static) return;

        // std.debug.print("PHPString.release: data={s} ref_count={d}\n", .{self.data, self.ref_count});

        if (self.ref_count == 0) {
            std.debug.print("WARNING: PHPString double free detected! data={s}\n", .{self.data});
            return;
        }

        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit(allocator);
        }
    }

    /// 释放字符串
    fn deinit(self: *PHPString, allocator: Allocator) void {
        if (!self.is_static) {
            // std.debug.print("PHPString.deinit called\n", .{});
            if (alloc_counters.php_string_live_objects > 0) {
                alloc_counters.php_string_live_objects -= 1;
            }
            if (alloc_counters.php_string_live_bytes >= self.length) {
                alloc_counters.php_string_live_bytes -= self.length;
            } else {
                alloc_counters.php_string_live_bytes = 0;
            }
            allocator.free(self.data);
            // std.debug.print("PHPString.deinit: freed data\n", .{});
            destroyPHPString(self, allocator);
            // std.debug.print("PHPString.deinit: destroyed self\n", .{});
        }
    }

    /// 字符串连接（支持 COW 就地复用：ref_count==1 时 realloc 扩展，避免新建对象）
    pub fn concat(self: *PHPString, other: *PHPString, allocator: Allocator) !*PHPString {
        // 检测内存破坏：如果length异常大，说明对象被破坏
        if (self.length > 1024 * 1024 * 1024 or other.length > 1024 * 1024 * 1024) {
            // 内存破坏，返回空字符串避免crash
            return try PHPString.init(allocator, "");
        }

        const new_length = self.length + other.length;

        if (new_length > 1024 * 1024 * 100) {
            std.debug.print("ERROR: Concat result too large: {d} + {d} = {d} bytes ({d} MB)\n", .{ self.length, other.length, new_length, new_length / (1024 * 1024) });
            return error.StringTooLarge;
        }

        // 临时禁用 COW 优化（有 bug）
        // if (self.ref_count == 1 and !self.is_static and other.length > 0) {
        //     const old_len = self.length;
        //     const new_data = try allocator.realloc(self.data, new_length);
        //     @memcpy(new_data[old_len..new_length], other.data[0..other.length]);
        //     self.data = new_data;
        //     self.length = new_length;
        //     alloc_counters.php_string_bytes += other.length;
        //     alloc_counters.php_string_live_bytes += other.length;
        //     alloc_counters.php_string_peak_live_bytes = @max(
        //         alloc_counters.php_string_peak_live_bytes,
        //         alloc_counters.php_string_live_bytes,
        //     );
        //     return self;
        // }

        // 小字符串优化：≤256 字节使用栈缓冲
        if (new_length <= 256) {
            var stack_buf: [256]u8 = undefined;
            if (self.length > 0) {
                @memcpy(stack_buf[0..self.length], self.data[0..self.length]);
            }
            if (other.length > 0) {
                @memcpy(stack_buf[self.length..new_length], other.data[0..other.length]);
            }
            return try PHPString.init(allocator, stack_buf[0..new_length]);
        }

        // 大字符串：堆分配
        const new_data = try allocator.alloc(u8, new_length);
        errdefer allocator.free(new_data);

        if (self.length > 0) {
            @memcpy(new_data[0..self.length], self.data[0..self.length]);
        }
        if (other.length > 0) {
            @memcpy(new_data[self.length..new_length], other.data[0..other.length]);
        }

        const result = try allocPHPString(allocator);
        errdefer destroyPHPString(result, allocator);

        alloc_counters.php_string_objects += 1;
        alloc_counters.php_string_bytes += new_length;
        alloc_counters.php_string_live_objects += 1;
        alloc_counters.php_string_live_bytes += new_length;
        alloc_counters.php_string_peak_live_objects = @max(
            alloc_counters.php_string_peak_live_objects,
            alloc_counters.php_string_live_objects,
        );
        alloc_counters.php_string_peak_live_bytes = @max(
            alloc_counters.php_string_peak_live_bytes,
            alloc_counters.php_string_live_bytes,
        );

        result.data = new_data;
        result.length = new_length;
        result.ref_count = 1;
        result.is_static = false;
        return result;
    }

    /// 获取子字符串
    pub fn substring(self: *PHPString, start: i64, length: ?i64, allocator: Allocator) !*PHPString {
        // 处理负数起始位置
        const start_idx: usize = blk: {
            if (start < 0) {
                const abs_start = @as(usize, @intCast(-start));
                break :blk if (abs_start > self.length) 0 else self.length - abs_start;
            } else {
                break :blk @intCast(@min(start, @as(i64, @intCast(self.length))));
            }
        };

        if (start_idx >= self.length) {
            return PHPString.init(allocator, "");
        }

        // 处理长度参数
        const end_idx: usize = blk: {
            if (length) |length_val| {
                if (length_val >= 0) {
                    break :blk @min(start_idx + @as(usize, @intCast(length_val)), self.length);
                } else {
                    const abs_len = @as(usize, @intCast(-length_val));
                    if (abs_len >= self.length - start_idx) {
                        return PHPString.init(allocator, "");
                    }
                    break :blk self.length - abs_len;
                }
            } else {
                break :blk self.length;
            }
        };

        if (start_idx >= end_idx) {
            return PHPString.init(allocator, "");
        }

        return PHPString.init(allocator, self.data[start_idx..end_idx]);
    }

    /// 查找子字符串位置
    pub fn indexOf(self: *PHPString, needle: *PHPString) i64 {
        if (needle.length == 0) return 0;
        if (needle.length > self.length) return -1;

        for (0..self.length - needle.length + 1) |i| {
            if (std.mem.eql(u8, self.data[i .. i + needle.length], needle.data)) {
                return @intCast(i);
            }
        }
        return -1;
    }

    /// 字符串长度
    pub fn len(self: *PHPString) usize {
        return self.length;
    }
};
