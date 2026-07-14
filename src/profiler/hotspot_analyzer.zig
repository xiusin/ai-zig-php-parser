const std = @import("std");
const Allocator = std.mem.Allocator;

/// 基本块（简化表示）
pub const BasicBlock = struct {
    name: []const u8,
    execution_count: u64,
};

/// 边（简化表示）
pub const Edge = struct {
    from: []const u8,
    to: []const u8,
    execution_count: u64,
};

/// 路径
pub const Path = struct {
    blocks: [][]const u8,
    total_count: u64,
};

/// 热点分析器
pub const HotspotAnalyzer = struct {
    allocator: Allocator,
    /// 基本块执行计数
    block_counters: std.StringHashMap(u64),
    /// 边执行计数
    edge_counters: std.StringHashMap(u64),

    pub fn init(allocator: Allocator) HotspotAnalyzer {
        return HotspotAnalyzer{
            .allocator = allocator,
            .block_counters = std.StringHashMap(u64).init(allocator),
            .edge_counters = std.StringHashMap(u64).init(allocator),
        };
    }

    pub fn deinit(self: *HotspotAnalyzer) void {
        // 释放所有 edge key
        var it = self.edge_counters.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }

        self.block_counters.deinit();
        self.edge_counters.deinit();
    }

    pub fn recordBlockExecution(self: *HotspotAnalyzer, block_name: []const u8) !void {
        const entry = try self.block_counters.getOrPut(block_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;
    }

    pub fn recordEdgeExecution(self: *HotspotAnalyzer, from: []const u8, to: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}->{s}", .{ from, to });
        errdefer self.allocator.free(key);

        const entry = try self.edge_counters.getOrPut(key);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        } else {
            // 如果已存在，释放新 key
            self.allocator.free(key);
        }
        entry.value_ptr.* += 1;
    }

    pub fn getBlockCount(self: *HotspotAnalyzer, block_name: []const u8) u64 {
        return self.block_counters.get(block_name) orelse 0;
    }

    pub fn getEdgeCount(self: *HotspotAnalyzer, from: []const u8, to: []const u8) u64 {
        const key = std.fmt.allocPrint(self.allocator, "{s}->{s}", .{ from, to }) catch return 0;
        defer self.allocator.free(key);
        return self.edge_counters.get(key) orelse 0;
    }

    pub fn findHotBlocks(self: *HotspotAnalyzer, threshold: u64) ![][]const u8 {
        var hot_blocks = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);

        var it = self.block_counters.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* >= threshold) {
                try hot_blocks.append(self.allocator, entry.key_ptr.*);
            }
        }

        return hot_blocks.toOwnedSlice(self.allocator);
    }

    pub fn generateReport(self: *HotspotAnalyzer, writer: anytype) !void {
        try writer.writeAll("=== Hotspot Analysis Report ===\n\n");

        // 收集并排序基本块
        var blocks = try std.ArrayList(struct { []const u8, u64 }).initCapacity(self.allocator, 0);
        defer blocks.deinit(self.allocator);

        var it = self.block_counters.iterator();
        while (it.next()) |entry| {
            try blocks.append(self.allocator, .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // 按执行次数排序
        std.mem.sort(@TypeOf(blocks.items[0]), blocks.items, {}, struct {
            fn lessThan(_: void, a: @TypeOf(blocks.items[0]), b: @TypeOf(blocks.items[0])) bool {
                return a[1] > b[1];
            }
        }.lessThan);

        // 输出前 20 个热点
        try writer.writeAll("Top 20 Hot Basic Blocks:\n");
        const limit = @min(20, blocks.items.len);
        for (blocks.items[0..limit], 0..) |item, i| {
            try writer.print("{d}. Block {s}: {d} executions\n", .{ i + 1, item[0], item[1] });
        }
    }
};
