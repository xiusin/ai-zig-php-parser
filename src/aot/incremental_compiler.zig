//! 增量编译器
//!
//! 实现增量编译，只重新编译变化的文件
//! 基于依赖追踪和缓存机制
//!
//! ## 架构
//!
//! ```
//! ┌─────────────────────────────────────────────────────┐
//! │           Incremental Compilation Flow              │
//! ├─────────────────────────────────────────────────────┤
//! │                                                     │
//! │  Source Files → Dependency Graph → Change Detection │
//! │       ↓                ↓                  ↓         │
//! │  File Hashes    Dependency Map    Affected Files  │
//! │       ↓                ↓                  ↓         │
//! │  Cache Lookup   Cache Invalidation   Compilation   │
//! │       ↓                ↓                  ↓         │
//! │  Cache Hit/Miss   Cache Update     Object Code     │
//! │                                                     │
//! └─────────────────────────────────────────────────────┘
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const SourceLocation = Diagnostics.SourceLocation;
const IR = @import("ir.zig");
const Module = IR.Module;
const CompilerMod = @import("compiler.zig");
const SymbolTable = @import("symbol_table.zig").SymbolTable;

// ============================================================================
// 常量配置
// ============================================================================

/// 缓存目录
const CACHE_DIR = ".zigphp-cache";

/// 缓存文件扩展名
const CACHE_EXT = ".cache";

/// 依赖文件扩展名
const DEP_EXT = ".dep";

/// 哈希算法
const HASH_ALGORITHM = std.crypto.hash.sha2.Sha256;

// ============================================================================
// 文件哈希
// ============================================================================

pub const FileHash = struct {
    /// 文件路径
    path: []const u8,
    /// SHA256哈希值
    hash: [HASH_ALGORITHM.digest_length]u8,
    /// 文件大小
    size: u64,
    /// 修改时间
    mtime: i64,

    /// 计算文件哈希
    pub fn compute(allocator: Allocator, path: []const u8) !FileHash {
        const file = try std.Io.Dir.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const size = stat.size;
        const mtime = stat.mtime;

        // 计算哈希
        var hasher = HASH_ALGORITHM.init(.{});
        var buf: [8192]u8 = undefined;

        while (true) {
            const bytes_read = try file.read(&buf);
            if (bytes_read == 0) break;
            hasher.update(buf[0..bytes_read]);
        }

        var hash: [HASH_ALGORITHM.digest_length]u8 = undefined;
        hasher.final(&hash);

        return .{
            .path = try allocator.dupe(u8, path),
            .hash = hash,
            .size = size,
            .mtime = mtime,
        };
    }

    /// 释放资源
    pub fn deinit(self: *FileHash, allocator: Allocator) void {
        allocator.free(self.path);
    }

    /// 比较两个哈希
    pub fn equals(self: *const FileHash, other: *const FileHash) bool {
        return std.mem.eql(u8, &self.hash, &other.hash) and
            self.size == other.size;
    }
};

// ============================================================================
// 依赖信息
// ============================================================================

pub const DependencyInfo = struct {
    /// 文件路径
    file_path: []const u8,
    /// 文件哈希
    hash: FileHash,
    /// 依赖的文件
    dependencies: std.ArrayListUnmanaged([]const u8),
    /// 被依赖的文件（反向依赖）
    dependents: std.ArrayListUnmanaged([]const u8),
    /// 编译时间戳
    compile_time: i64,
    /// 输出文件路径
    output_path: []const u8,

    pub fn init(allocator: Allocator, file_path: []const u8) DependencyInfo {
        return .{
            .file_path = try allocator.dupe(u8, file_path),
            .hash = undefined, // 需要单独计算
            .dependencies = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 },
            .dependents = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 },
            .compile_time = 0,
            .output_path = &.{},
        };
    }

    pub fn deinit(self: *DependencyInfo, allocator: Allocator) void {
        allocator.free(self.file_path);
        allocator.free(self.output_path);

        for (self.dependencies.items) |dep| {
            allocator.free(dep);
        }
        self.dependencies.deinit(allocator);

        for (self.dependents.items) |dep| {
            allocator.free(dep);
        }
        self.dependents.deinit(allocator);
    }

    /// 添加依赖
    pub fn addDependency(self: *DependencyInfo, allocator: Allocator, dep_path: []const u8) !void {
        const duped = try allocator.dupe(u8, dep_path);
        try self.dependencies.append(allocator, duped);
    }

    /// 添加被依赖
    pub fn addDependent(self: *DependencyInfo, allocator: Allocator, dep_path: []const u8) !void {
        const duped = try allocator.dupe(u8, dep_path);
        try self.dependents.append(allocator, duped);
    }

    /// 序列化
    pub fn serialize(self: *const DependencyInfo, allocator: Allocator) ![]const u8 {
        var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
        defer buffer.deinit(allocator);

        // 文件路径
        try buffer.writer().print("{}\n", .{std.fmt.fmtSliceHexLower(self.file_path)});

        // 哈希
        try buffer.writer().print("{}\n", .{std.fmt.fmtSliceHexLower(&self.hash.hash)});

        // 大小
        try buffer.writer().print("{}\n", .{self.hash.size});

        // 修改时间
        try buffer.writer().print("{}\n", .{self.hash.mtime});

        // 依赖数量
        try buffer.writer().print("{}\n", .{self.dependencies.items.len});

        // 依赖列表
        for (self.dependencies.items) |dep| {
            try buffer.writer().print("{}\n", .{std.fmt.fmtSliceHexLower(dep)});
        }

        // 被依赖数量
        try buffer.writer().print("{}\n", .{self.dependents.items.len});

        // 被依赖列表
        for (self.dependents.items) |dep| {
            try buffer.writer().print("{}\n", .{std.fmt.fmtSliceHexLower(dep)});
        }

        // 编译时间
        try buffer.writer().print("{}\n", .{self.compile_time});

        // 输出路径
        try buffer.writer().print("{}\n", .{std.fmt.fmtSliceHexLower(self.output_path)});

        return buffer.toOwnedSlice();
    }

    /// 反序列化
    pub fn deserialize(allocator: Allocator, data: []const u8) !DependencyInfo {
        var reader = std.io.fixedBufferStream(data).reader();

        var info = DependencyInfo{
            .file_path = undefined,
            .hash = undefined,
            .dependencies = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 },
            .dependents = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 },
            .compile_time = 0,
            .output_path = &.{},
        };

        // 读取文件路径
        var hex_buf: [1024]u8 = undefined;
        const path_len = try reader.readUntilDelimiter(&hex_buf, '\n');
        const path_hex = hex_buf[0..path_len];
        info.file_path = try hexToBytes(allocator, path_hex);

        // 读取哈希
        const hash_len = try reader.readUntilDelimiter(&hex_buf, '\n');
        const hash_hex = hex_buf[0..hash_len];
        const hash_bytes = try hexToBytes(allocator, hash_hex);
        @memcpy(&info.hash.hash, hash_bytes);
        allocator.free(hash_bytes);

        // 读取大小
        const size_str = try reader.readUntilDelimiter(&hex_buf, '\n');
        info.hash.size = try std.fmt.parseInt(u64, size_str, 10);

        // 读取修改时间
        const mtime_str = try reader.readUntilDelimiter(&hex_buf, '\n');
        info.hash.mtime = try std.fmt.parseInt(i64, mtime_str, 10);

        // 读取依赖数量
        const dep_count_str = try reader.readUntilDelimiter(&hex_buf, '\n');
        const dep_count = try std.fmt.parseInt(usize, dep_count_str, 10);

        // 读取依赖列表
        for (0..dep_count) |_| {
            const dep_hex = try reader.readUntilDelimiter(&hex_buf, '\n');
            const dep = try hexToBytes(allocator, dep_hex);
            try info.dependencies.append(allocator, dep);
        }

        // 读取被依赖数量
        const dependent_count_str = try reader.readUntilDelimiter(&hex_buf, '\n');
        const dependent_count = try std.fmt.parseInt(usize, dependent_count_str, 10);

        // 读取被依赖列表
        for (0..dependent_count) |_| {
            const dependent_hex = try reader.readUntilDelimiter(&hex_buf, '\n');
            const dependent = try hexToBytes(allocator, dependent_hex);
            try info.dependents.append(allocator, dependent);
        }

        // 读取编译时间
        const compile_time_str = try reader.readUntilDelimiter(&hex_buf, '\n');
        info.compile_time = try std.fmt.parseInt(i64, compile_time_str, 10);

        // 读取输出路径
        const output_hex = try reader.readUntilDelimiter(&hex_buf, '\n');
        info.output_path = try hexToBytes(allocator, output_hex);

        return info;
    }
};

/// 十六进制字符串转字节数组
fn hexToBytes(allocator: Allocator, hex: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, hex.len / 2);
    for (0..result.len) |i| {
        const byte_str = hex[2 * i .. 2 * i + 2];
        result[i] = try std.fmt.parseInt(u8, byte_str, 16);
    }
    return result;
}

// ============================================================================
// 编译缓存
// ============================================================================

pub const CompilationCache = struct {
    /// 缓存目录
    cache_dir: std.fs.Dir,
    /// 缓存条目
    entries: std.StringHashMap(CompilationEntry),
    /// 分配器
    allocator: Allocator,

    const CompilationEntry = struct {
        /// 依赖信息
        dependency_info: DependencyInfo,
        /// 编译后的IR
        ir: ?*Module,
        /// 缓存命中次数
        hits: u64,
        /// 缓存未命中次数
        misses: u64,
    };

    pub fn init(allocator: Allocator) !CompilationCache {
        // 创建缓存目录
        const cache_dir = try std.Io.Dir.cwd().makeOpenPath(CACHE_DIR, .{});

        return .{
            .cache_dir = cache_dir,
            .entries = std.StringHashMap(CompilationEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CompilationCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.dependency_info.deinit(self.allocator);
        }
        self.entries.deinit();
        self.cache_dir.close();
    }

    /// 查找缓存
    pub fn lookup(self: *CompilationCache, file_path: []const u8) !?*Module {
        // 计算当前文件哈希
        const current_hash = try FileHash.compute(self.allocator, file_path);
        defer current_hash.deinit(self.allocator);

        // 查找缓存条目
        const entry = self.entries.get(file_path) orelse {
            // 缓存未命中
            return null;
        };

        // 比较哈希
        if (!current_hash.equals(&entry.value_ptr.dependency_info.hash)) {
            // 文件已修改，缓存失效
            entry.value_ptr.misses += 1;
            return null;
        }

        // 缓存命中
        entry.value_ptr.hits += 1;
        return entry.value_ptr.ir;
    }

    /// 更新缓存
    pub fn update(self: *CompilationCache, file_path: []const u8, ir: *Module, dep_info: DependencyInfo) !void {
        const entry = try self.entries.getOrPut(file_path);

        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .dependency_info = dep_info,
                .ir = ir,
                .hits = 0,
                .misses = 0,
            };
        } else {
            // 更新现有条目
            entry.value_ptr.dependency_info.deinit(self.allocator);
            entry.value_ptr.dependency_info = dep_info;
            entry.value_ptr.ir = ir;
        }

        // 保存到磁盘
        try self.saveToDisk(file_path, &entry.value_ptr.dependency_info);
    }

    /// 保存到磁盘
    fn saveToDisk(self: *CompilationCache, file_path: []const u8, dep_info: *const DependencyInfo) !void {
        // 生成缓存文件名
        const cache_filename = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{
            std.fs.path.basename(file_path),
            CACHE_EXT,
        });
        defer self.allocator.free(cache_filename);

        // 序列化依赖信息
        const data = try dep_info.serialize(self.allocator);
        defer self.allocator.free(data);

        // 写入文件
        const file = try self.cache_dir.createFile(cache_filename, .{});
        defer file.close();

        try file.writeAll(data);
    }

    /// 从磁盘加载
    fn loadFromDisk(self: *CompilationCache, file_path: []const u8) !?DependencyInfo {
        // 生成缓存文件名
        const cache_filename = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{
            std.fs.path.basename(file_path),
            CACHE_EXT,
        });
        defer self.allocator.free(cache_filename);

        // 读取文件
        const file = self.cache_dir.openFile(cache_filename, .{}) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(data);

        // 反序列化
        return try DependencyInfo.deserialize(self.allocator, data);
    }

    /// 清除缓存
    pub fn clear(self: *CompilationCache) !void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.dependency_info.deinit(self.allocator);
        }
        self.entries.clearRetainingCapacity();

        // 删除缓存目录中的所有文件
        var dir_iter = self.cache_dir.iterate();
        while (try dir_iter.next()) |entry| {
            try self.cache_dir.deleteFile(entry.name);
        }
    }

    /// 获取缓存统计
    pub fn getStats(self: *CompilationCache) CacheStats {
        var total_hits: u64 = 0;
        var total_misses: u64 = 0;

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            total_hits += entry.value_ptr.hits;
            total_misses += entry.value_ptr.misses;
        }

        return .{
            .entry_count = self.entries.count(),
            .total_hits = total_hits,
            .total_misses = total_misses,
            .hit_rate = if (total_hits + total_misses > 0)
                @as(f64, @floatFromInt(total_hits)) / @as(f64, @floatFromInt(total_hits + total_misses))
            else
                0.0,
        };
    }

    pub const CacheStats = struct {
        entry_count: usize,
        total_hits: u64,
        total_misses: u64,
        hit_rate: f64,
    };
};

// ============================================================================
// 增量编译器
// ============================================================================

pub const IncrementalCompiler = struct {
    /// 编译缓存
    cache: CompilationCache,
    /// 依赖图
    dependency_graph: DependencyGraph,
    /// 诊断引擎
    diagnostics: *DiagnosticEngine,
    /// 分配器
    allocator: Allocator,
    /// 统计信息
    stats: IncrementalStats,

    pub const IncrementalStats = struct {
        /// 总编译次数
        total_compilations: u64 = 0,
        /// 增量编译次数
        incremental_compilations: u64 = 0,
        /// 完全编译次数
        full_compilations: u64 = 0,
        /// 节省的时间（纳秒）
        time_saved_ns: u64 = 0,
    };

    pub fn init(allocator: Allocator, diagnostics: *DiagnosticEngine) !IncrementalCompiler {
        return .{
            .cache = try CompilationCache.init(allocator),
            .dependency_graph = DependencyGraph.init(allocator),
            .diagnostics = diagnostics,
            .allocator = allocator,
            .stats = .{},
        };
    }

    pub fn deinit(self: *IncrementalCompiler) void {
        self.cache.deinit();
        self.dependency_graph.deinit();
    }

    /// 编译文件（增量）
    pub fn compileFile(self: *IncrementalCompiler, file_path: []const u8) !*Module {
        const start_time = std.time.nanoTimestamp();

        // 检查缓存
        const cached_ir = try self.cache.lookup(file_path);

        if (cached_ir) |ir| {
            // 缓存命中，直接返回
            self.stats.incremental_compilations += 1;
            self.stats.total_compilations += 1;

            const end_time = std.time.nanoTimestamp();
            const time_saved = end_time - start_time;
            self.stats.time_saved_ns += @intCast(time_saved);

            return ir;
        }

        // 缓存未命中，需要编译
        self.stats.full_compilations += 1;
        self.stats.total_compilations += 1;

        // 执行编译
        const ir = try self.doCompileFile(file_path);

        // 构建依赖信息
        const dep_info = try self.buildDependencyInfo(file_path, ir);

        // 更新缓存
        try self.cache.update(file_path, ir, dep_info);

        // 更新依赖图
        try self.dependency_graph.update(file_path, dep_info);

        return ir;
    }

    /// 实际编译文件
    fn doCompileFile(self: *IncrementalCompiler, file_path: []const u8) !*Module {
        // 创建AOT编译器选项
        const aot_options = CompilerMod.CompileOptions{
            .input_file = file_path,
            .output_file = null,
            .target = .native(),
            .optimize_level = .debug,
            .static_link = false,
            .debug_info = true,
            .dump_ir = false,
            .dump_ast = false,
            .verbose = false,
            .syntax_mode = .php,
        };

        // 创建AOT编译器
        var aot_compiler = try CompilerMod.AOTCompiler.init(self.allocator, undefined, aot_options);
        defer aot_compiler.deinit();

        // 编译到IR
        const ir_module = try aot_compiler.compileToIR();

        if (ir_module == null) {
            return error.CompilationFailed;
        }

        return ir_module.?;
    }

    /// 构建依赖信息
    fn buildDependencyInfo(self: *IncrementalCompiler, file_path: []const u8, ir: *Module) !DependencyInfo {
        var dep_info = DependencyInfo.init(self.allocator, file_path);

        // 计算文件哈希
        dep_info.hash = try FileHash.compute(self.allocator, file_path);

        // 设置编译时间
        dep_info.compile_time = std.time.nanoTimestamp();

        // 从IR中提取依赖
        // 这里需要遍历IR，找出所有import/include语句
        // 暂时留空，实际实现需要集成

        _ = ir;

        return dep_info;
    }

    /// 检测受影响的文件
    pub fn detectAffectedFiles(self: *IncrementalCompiler, changed_file: []const u8) !std.ArrayList([]const u8) {
        var affected = std.ArrayList([]const u8){ .allocator = self.allocator };

        // 获取所有依赖该文件的文件
        const dependents = try self.dependency_graph.getDependents(changed_file);

        for (dependents.items) |dep| {
            try affected.append(try self.allocator.dupe(u8, dep));
        }

        // 递归检查
        var i: usize = 0;
        while (i < affected.items.len) {
            const file = affected.items[i];
            const transitive_deps = try self.dependency_graph.getDependents(file);

            for (transitive_deps.items) |dep| {
                // 检查是否已在列表中
                var found = false;
                for (affected.items) |existing| {
                    if (std.mem.eql(u8, existing, dep)) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    try affected.append(try self.allocator.dupe(u8, dep));
                }
            }

            i += 1;
        }

        return affected;
    }

    /// 清除缓存
    pub fn clearCache(self: *IncrementalCompiler) !void {
        try self.cache.clear();
    }

    /// 获取统计信息
    pub fn getStats(self: *IncrementalCompiler) IncrementalStats {
        return self.stats;
    }

    /// 获取缓存统计
    pub fn getCacheStats(self: *IncrementalCompiler) CompilationCache.CacheStats {
        return self.cache.getStats();
    }
};

// ============================================================================
// 依赖图
// ============================================================================

pub const DependencyGraph = struct {
    /// 节点映射
    nodes: std.StringHashMap(DependencyNode),
    /// 分配器
    allocator: Allocator,

    const DependencyNode = struct {
        /// 文件路径
        file_path: []const u8,
        /// 依赖的文件
        dependencies: std.StringHashMap(void),
        /// 被依赖的文件
        dependents: std.StringHashMap(void),
    };

    pub fn init(allocator: Allocator) DependencyGraph {
        return .{
            .nodes = std.StringHashMap(DependencyNode).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DependencyGraph) void {
        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.file_path);
            entry.value_ptr.dependencies.deinit();
            entry.value_ptr.dependents.deinit();
        }
        self.nodes.deinit();
    }

    /// 更新依赖图
    pub fn update(self: *DependencyGraph, file_path: []const u8, dep_info: DependencyInfo) !void {
        const node = try self.nodes.getOrPut(file_path);

        if (!node.found_existing) {
            node.value_ptr.* = .{
                .file_path = try self.allocator.dupe(u8, file_path),
                .dependencies = std.StringHashMap(void).init(self.allocator),
                .dependents = std.StringHashMap(void).init(self.allocator),
            };
        }

        // 清除旧依赖
        node.value_ptr.dependencies.clearRetainingCapacity();

        // 添加新依赖
        for (dep_info.dependencies.items) |dep| {
            try node.value_ptr.dependencies.put(try self.allocator.dupe(u8, dep), {});
            try self.addDependent(dep, file_path);
        }
    }

    /// 添加被依赖关系
    fn addDependent(self: *DependencyGraph, file_path: []const u8, dependent: []const u8) !void {
        const node = try self.nodes.getOrPut(file_path);

        if (!node.found_existing) {
            node.value_ptr.* = .{
                .file_path = try self.allocator.dupe(u8, file_path),
                .dependencies = std.StringHashMap(void).init(self.allocator),
                .dependents = std.StringHashMap(void).init(self.allocator),
            };
        }

        try node.value_ptr.dependents.put(try self.allocator.dupe(u8, dependent), {});
    }

    /// 获取被依赖的文件
    pub fn getDependents(self: *DependencyGraph, file_path: []const u8) !std.ArrayList([]const u8) {
        var dependents = std.ArrayList([]const u8){ .allocator = self.allocator };

        if (self.nodes.get(file_path)) |node| {
            var iter = node.dependents.iterator();
            while (iter.next()) |entry| {
                try dependents.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        return dependents;
    }

    /// 检测循环依赖
    pub fn detectCycles(self: *DependencyGraph) !std.ArrayList([]const u8) {
        var cycles = std.ArrayList([]const u8){ .allocator = self.allocator };

        // 使用DFS检测循环
        var visited = std.StringHashMap(bool).init(self.allocator);
        var rec_stack = std.StringHashMap(bool).init(self.allocator);

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            if (!visited.get(entry.key_ptr.*)) |_| {
                if (try self.dfsDetectCycle(entry.key_ptr.*, &visited, &rec_stack)) {
                    try cycles.append(try self.allocator.dupe(u8, entry.key_ptr.*));
                }
            }
        }

        visited.deinit();
        rec_stack.deinit();

        return cycles;
    }

    /// DFS检测循环
    fn dfsDetectCycle(self: *DependencyGraph, file_path: []const u8, visited: *std.StringHashMap(bool), rec_stack: *std.StringHashMap(bool)) !bool {
        try visited.put(file_path, true);
        try rec_stack.put(file_path, true);

        if (self.nodes.get(file_path)) |node| {
            var iter = node.dependencies.iterator();
            while (iter.next()) |entry| {
                const dep = entry.key_ptr.*;

                if (!visited.get(dep)) |_| {
                    if (try self.dfsDetectCycle(dep, visited, rec_stack)) {
                        return true;
                    }
                } else if (rec_stack.get(dep)) |_| {
                    return true; // 发现循环
                }
            }
        }

        _ = rec_stack.remove(file_path);
        return false;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "file hash computation" {
    // 创建临时文件
    const tmp_file = try std.testing.tmpDir(.{});
    defer tmp_file.cleanup();

    const file_path = "test.txt";
    const content = "Hello, World!";

    try tmp_file.dir.writeFile(.{ .sub_path = file_path, .data = content });

    // 计算哈希
    const full_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{
        tmp_file.dir_path, file_path,
    });
    defer std.testing.allocator.free(full_path);

    const hash = try FileHash.compute(std.testing.allocator, full_path);
    defer hash.deinit(std.testing.allocator);

    try std.testing.expect(hash.size == content.len);
}

test "compilation cache basic" {
    var cache = try CompilationCache.init(std.testing.allocator);
    defer cache.deinit();

    // 尝试查找不存在的缓存
    const result = try cache.lookup("nonexistent.php");
    try std.testing.expect(result == null);

    // 获取统计
    const stats = cache.getStats();
    try std.testing.expect(stats.entry_count == 0);
}

test "dependency graph basic" {
    var graph = DependencyGraph.init(std.testing.allocator);
    defer graph.deinit();

    // 添加依赖关系
    var dep_info = DependencyInfo.init(std.testing.allocator, "a.php");
    defer dep_info.deinit(std.testing.allocator);

    try dep_info.addDependency(std.testing.allocator, "b.php");
    try dep_info.addDependency(std.testing.allocator, "c.php");

    try graph.update("a.php", dep_info);

    // 获取被依赖的文件
    const dependents = try graph.getDependents("b.php");
    defer {
        for (dependents.items) |dep| {
            std.testing.allocator.free(dep);
        }
        dependents.deinit();
    }

    try std.testing.expect(dependents.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, dependents.items[0], "a.php"));
}