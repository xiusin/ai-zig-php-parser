//! 独立的文件系统函数测试
//! 不依赖其他模块，只测试核心逻辑

const std = @import("std");
const testing = std.testing;

// ============================================================================
// 目录条目结构（复制自 filesystem_complete.zig）
// ============================================================================

const DirEntry = struct {
    name: []const u8,
    kind: std.fs.File.Kind,
    size: u64,
    mtime: i128,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, kind: std.fs.File.Kind, size: u64, mtime: i128) !DirEntry {
        const name_copy = try allocator.dupe(u8, name);
        return DirEntry{
            .name = name_copy,
            .kind = kind,
            .size = size,
            .mtime = mtime,
        };
    }

    pub fn deinit(self: *DirEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

// ============================================================================
// glob 模式匹配（复制自 filesystem_complete.zig）
// ============================================================================

fn matchGlobPattern(pattern: []const u8, str: []const u8) bool {
    var p_idx: usize = 0;
    var s_idx: usize = 0;
    var star_idx: ?usize = null;
    var match_idx: usize = 0;

    while (s_idx < str.len) {
        if (p_idx < pattern.len) {
            const p = pattern[p_idx];

            if (p == '*') {
                star_idx = p_idx;
                match_idx = s_idx;
                p_idx += 1;
                continue;
            }

            if (p == '?' or p == str[s_idx]) {
                p_idx += 1;
                s_idx += 1;
                continue;
            }
        }

        if (star_idx) |star| {
            p_idx = star + 1;
            match_idx += 1;
            s_idx = match_idx;
            continue;
        }

        return false;
    }

    // 跳过剩余的 *
    while (p_idx < pattern.len and pattern[p_idx] == '*') {
        p_idx += 1;
    }

    return p_idx == pattern.len;
}

// ============================================================================
// 测试
// ============================================================================

test "DirEntry - 初始化和释放" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var entry = try DirEntry.init(allocator, "test.txt", .file, 1024, 0);
    defer entry.deinit(allocator);

    try testing.expectEqualStrings("test.txt", entry.name);
    try testing.expect(entry.kind == .file);
    try testing.expect(entry.size == 1024);
}

test "DirEntry - 升序排序" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var entries = std.ArrayList(DirEntry).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (entries.items) |*entry| {
            entry.deinit(allocator);
        }
        entries.deinit(allocator);
    }

    try entries.append(allocator, try DirEntry.init(allocator, "zzz.txt", .file, 0, 0));
    try entries.append(allocator, try DirEntry.init(allocator, "aaa.txt", .file, 0, 0));
    try entries.append(allocator, try DirEntry.init(allocator, "mmm.txt", .file, 0, 0));

    // 升序排序
    std.mem.sort(DirEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: DirEntry, b: DirEntry) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);

    try testing.expectEqualStrings("aaa.txt", entries.items[0].name);
    try testing.expectEqualStrings("mmm.txt", entries.items[1].name);
    try testing.expectEqualStrings("zzz.txt", entries.items[2].name);
}

test "DirEntry - 降序排序" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var entries = std.ArrayList(DirEntry).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (entries.items) |*entry| {
            entry.deinit(allocator);
        }
        entries.deinit(allocator);
    }

    try entries.append(allocator, try DirEntry.init(allocator, "aaa.txt", .file, 0, 0));
    try entries.append(allocator, try DirEntry.init(allocator, "zzz.txt", .file, 0, 0));
    try entries.append(allocator, try DirEntry.init(allocator, "mmm.txt", .file, 0, 0));

    // 降序排序
    std.mem.sort(DirEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: DirEntry, b: DirEntry) bool {
            return std.mem.order(u8, a.name, b.name) == .gt;
        }
    }.lessThan);

    try testing.expectEqualStrings("zzz.txt", entries.items[0].name);
    try testing.expectEqualStrings("mmm.txt", entries.items[1].name);
    try testing.expectEqualStrings("aaa.txt", entries.items[2].name);
}

test "matchGlobPattern - 精确匹配" {
    try testing.expect(matchGlobPattern("test.txt", "test.txt"));
    try testing.expect(!matchGlobPattern("test.txt", "other.txt"));
}

test "matchGlobPattern - 星号通配符" {
    try testing.expect(matchGlobPattern("*.txt", "file.txt"));
    try testing.expect(matchGlobPattern("*.txt", "test.txt"));
    try testing.expect(!matchGlobPattern("*.txt", "file.doc"));
    try testing.expect(matchGlobPattern("test*", "test123"));
    try testing.expect(matchGlobPattern("*test", "mytest"));
}

test "matchGlobPattern - 问号通配符" {
    try testing.expect(matchGlobPattern("file?.txt", "file1.txt"));
    try testing.expect(matchGlobPattern("file?.txt", "fileA.txt"));
    try testing.expect(!matchGlobPattern("file?.txt", "file12.txt"));
    try testing.expect(!matchGlobPattern("file?.txt", "file.txt"));
}

test "matchGlobPattern - 复杂模式" {
    try testing.expect(matchGlobPattern("test_*.txt", "test_1.txt"));
    try testing.expect(matchGlobPattern("test_*.txt", "test_abc.txt"));
    try testing.expect(!matchGlobPattern("test_*.txt", "test.txt"));
    try testing.expect(matchGlobPattern("*_test_*", "prefix_test_suffix"));
}

test "matchGlobPattern - 多个星号" {
    try testing.expect(matchGlobPattern("*.*", "file.txt"));
    try testing.expect(matchGlobPattern("*.*", "test.doc"));
    try testing.expect(!matchGlobPattern("*.*", "noextension"));
}

test "pathinfo - 解析完整路径" {
    const path = "/home/user/file.txt";

    const dirname = std.fs.path.dirname(path);
    try testing.expect(dirname != null);
    try testing.expectEqualStrings("/home/user", dirname.?);

    const basename = std.fs.path.basename(path);
    try testing.expectEqualStrings("file.txt", basename);

    const extension = std.fs.path.extension(basename);
    try testing.expectEqualStrings(".txt", extension);
}

test "pathinfo - 无扩展名" {
    const path = "/home/user/file";

    const basename = std.fs.path.basename(path);
    try testing.expectEqualStrings("file", basename);

    const extension = std.fs.path.extension(basename);
    try testing.expectEqualStrings("", extension);
}

test "pathinfo - 相对路径" {
    const path = "file.txt";

    const dirname = std.fs.path.dirname(path);
    try testing.expect(dirname == null);

    const basename = std.fs.path.basename(path);
    try testing.expectEqualStrings("file.txt", basename);
}

test "pathinfo - 多个点" {
    const path = "file.tar.gz";

    const basename = std.fs.path.basename(path);
    try testing.expectEqualStrings("file.tar.gz", basename);

    const extension = std.fs.path.extension(basename);
    try testing.expectEqualStrings(".gz", extension);
}

test "scandir - 实际目录测试" {
    const test_dir = "test_scandir_实际";

    // 创建测试目录
    std.fs.cwd.makeDir(test_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    defer std.fs.cwd.deleteTree(test_dir) catch {};

    // 创建测试文件
    {
        const file1 = try std.fs.cwd.createFile(test_dir ++ "/zzz.txt", .{});
        defer file1.close();

        const file2 = try std.fs.cwd.createFile(test_dir ++ "/aaa.txt", .{});
        defer file2.close();

        const file3 = try std.fs.cwd.createFile(test_dir ++ "/mmm.txt", .{});
        defer file3.close();
    }

    // 打开目录并读取条目
    var dir = try std.fs.cwd.openDir(test_dir, .{ .iterate = true });
    defer dir.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var entries = std.ArrayList(DirEntry).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (entries.items) |*entry| {
            entry.deinit(allocator);
        }
        entries.deinit(allocator);
    }

    // 添加 "." 和 ".."
    const dot_stat = try dir.statFile(".");
    try entries.append(allocator, try DirEntry.init(allocator, ".", dot_stat.kind, dot_stat.size, dot_stat.mtime));

    const dotdot_stat = try dir.statFile("..");
    try entries.append(allocator, try DirEntry.init(allocator, "..", dotdot_stat.kind, dotdot_stat.size, dotdot_stat.mtime));

    // 读取其他条目
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const stat = try dir.statFile(entry.name);
        try entries.append(allocator, try DirEntry.init(allocator, entry.name, entry.kind, stat.size, stat.mtime));
    }

    // 验证至少有 5 个条目（., .., 和 3 个文件）
    try testing.expect(entries.items.len >= 5);

    // 升序排序
    std.mem.sort(DirEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: DirEntry, b: DirEntry) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);

    // 验证排序（. 和 .. 应该在前面）
    try testing.expectEqualStrings(".", entries.items[0].name);
    try testing.expectEqualStrings("..", entries.items[1].name);
}
