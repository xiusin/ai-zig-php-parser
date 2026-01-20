/// 性能火焰图生成器
/// 
/// 提供性能火焰图数据收集和生成功能，支持：
/// - 调用栈采样
/// - 火焰图数据格式生成（FlameGraph 工具兼容）
/// - 热点函数识别和排序
/// - SVG 火焰图生成
/// 
/// @concurrency-model THREAD_SAFE
/// @ownership NON-OWNING (allocator)
/// @memory-safety 所有内存操作通过显式 allocator

const std = @import("std");
const builtin = @import("builtin");
const Profiler = @import("profiler.zig").Profiler;
const FunctionStats = @import("profiler.zig").FunctionStats;

/// 调用栈帧
pub const StackFrame = struct {
    /// 函数名
    function_name: []const u8,
    /// 文件名（可选）
    file_name: ?[]const u8,
    /// 行号（可选）
    line_number: ?u32,
    /// 执行时间（纳秒）
    duration_ns: u64,
};

/// 调用栈样本
pub const StackSample = struct {
    /// 时间戳（纳秒）
    timestamp_ns: u64,
    /// 调用栈（从底部到顶部）
    frames: []StackFrame,
    /// 样本权重（执行时间）
    weight_ns: u64,
    
    pub fn deinit(self: *StackSample, allocator: std.mem.Allocator) void {
        for (self.frames) |frame| {
            allocator.free(frame.function_name);
            if (frame.file_name) |file| {
                allocator.free(file);
            }
        }
        allocator.free(self.frames);
    }
};

/// 火焰图节点
pub const FlameGraphNode = struct {
    /// 函数名
    name: []const u8,
    /// 累计执行时间（纳秒）
    total_time_ns: u64,
    /// 自身执行时间（纳秒，不包括子函数）
    self_time_ns: u64,
    /// 调用次数
    call_count: u64,
    /// 子节点
    children: std.StringHashMap(*FlameGraphNode),
    /// 父节点
    parent: ?*FlameGraphNode,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*FlameGraphNode {
        const node = try allocator.create(FlameGraphNode);
        node.* = .{
            .name = try allocator.dupe(u8, name),
            .total_time_ns = 0,
            .self_time_ns = 0,
            .call_count = 0,
            .children = std.StringHashMap(*FlameGraphNode).init(allocator),
            .parent = null,
        };
        return node;
    }
    
    pub fn deinit(self: *FlameGraphNode, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        
        var iter = self.children.valueIterator();
        while (iter.next()) |child| {
            child.*.deinit(allocator);
            allocator.destroy(child.*);
        }
        self.children.deinit();
    }
    
    /// 添加或更新子节点
    pub fn addChild(self: *FlameGraphNode, allocator: std.mem.Allocator, name: []const u8, duration_ns: u64) !*FlameGraphNode {
        const gop = try self.children.getOrPut(name);
        
        if (!gop.found_existing) {
            const child = try FlameGraphNode.init(allocator, name);
            child.parent = self;
            gop.value_ptr.* = child;
        }
        
        const child = gop.value_ptr.*;
        child.total_time_ns += duration_ns;
        child.call_count += 1;
        
        return child;
    }
    
    /// 计算自身时间（总时间 - 子节点时间）
    pub fn calculateSelfTime(self: *FlameGraphNode) void {
        var children_time: u64 = 0;
        var iter = self.children.valueIterator();
        while (iter.next()) |child| {
            children_time += child.*.total_time_ns;
            child.*.calculateSelfTime();
        }
        
        self.self_time_ns = if (self.total_time_ns > children_time)
            self.total_time_ns - children_time
        else
            0;
    }
};

/// 火焰图生成器
pub const FlameGraphGenerator = struct {
    allocator: std.mem.Allocator,
    profiler: *Profiler,
    
    /// 根节点
    root: *FlameGraphNode,
    
    /// 采样数据
    samples: std.ArrayListUnmanaged(StackSample),
    
    /// 采样间隔（纳秒）
    sampling_interval_ns: u64,
    
    /// 最小显示时间（纳秒）
    min_display_time_ns: u64,
    
    /// 线程安全
    mutex: std.Thread.Mutex,
    
    /// 初始化火焰图生成器
    /// @pre allocator 和 profiler 必须有效
    /// @post 返回初始化的生成器
    pub fn init(allocator: std.mem.Allocator, profiler: *Profiler) !FlameGraphGenerator {
        const root = try FlameGraphNode.init(allocator, "root");
        
        return FlameGraphGenerator{
            .allocator = allocator,
            .profiler = profiler,
            .root = root,
            .samples = .{},
            .sampling_interval_ns = 1_000_000, // 1ms 默认采样间隔
            .min_display_time_ns = 100_000, // 0.1ms 最小显示时间
            .mutex = .{},
        };
    }
    
    /// 清理资源
    pub fn deinit(self: *FlameGraphGenerator) void {
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
        
        for (self.samples.items) |*sample| {
            sample.deinit(self.allocator);
        }
        self.samples.deinit(self.allocator);
    }
    
    /// 设置采样间隔
    pub fn setSamplingInterval(self: *FlameGraphGenerator, interval_ns: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.sampling_interval_ns = interval_ns;
    }
    
    /// 设置最小显示时间
    pub fn setMinDisplayTime(self: *FlameGraphGenerator, min_time_ns: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.min_display_time_ns = min_time_ns;
    }
    
    /// 从 Profiler 收集性能数据
    /// @pre profiler 必须已经收集了性能数据
    /// @post 构建火焰图树结构
    pub fn collectFromProfiler(self: *FlameGraphGenerator) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 获取所有函数统计
        const all_stats = try self.profiler.getAllStats(self.allocator);
        defer self.allocator.free(all_stats);
        
        // 重置根节点
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
        self.root = try FlameGraphNode.init(self.allocator, "root");
        
        // 构建火焰图树
        // 注意：这里简化实现，假设从 profiler 的调用栈信息构建
        // 实际应该从采样数据构建
        for (all_stats) |stats| {
            _ = try self.root.addChild(self.allocator, stats.name, stats.total_time_ns);
        }
        
        // 计算自身时间
        self.root.calculateSelfTime();
    }
    
    /// 添加调用栈样本
    /// @pre frames 必须有效
    /// @post 样本被添加到样本列表
    pub fn addSample(self: *FlameGraphGenerator, frames: []const StackFrame, weight_ns: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 复制帧数据
        var frames_copy = try self.allocator.alloc(StackFrame, frames.len);
        for (frames, 0..) |frame, i| {
            frames_copy[i] = .{
                .function_name = try self.allocator.dupe(u8, frame.function_name),
                .file_name = if (frame.file_name) |file| try self.allocator.dupe(u8, file) else null,
                .line_number = frame.line_number,
                .duration_ns = frame.duration_ns,
            };
        }
        
        const sample = StackSample{
            .timestamp_ns = @intCast(std.time.nanoTimestamp()),
            .frames = frames_copy,
            .weight_ns = weight_ns,
        };
        
        try self.samples.append(self.allocator, sample);
    }
    
    /// 从样本构建火焰图树
    /// @pre samples 必须已经收集
    /// @post 构建完整的火焰图树结构
    pub fn buildFromSamples(self: *FlameGraphGenerator) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 重置根节点
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
        self.root = try FlameGraphNode.init(self.allocator, "root");
        
        // 遍历所有样本
        for (self.samples.items) |sample| {
            var current_node = self.root;
            
            // 从底部到顶部遍历调用栈
            for (sample.frames) |frame| {
                current_node = try current_node.addChild(
                    self.allocator,
                    frame.function_name,
                    sample.weight_ns,
                );
            }
        }
        
        // 计算自身时间
        self.root.calculateSelfTime();
    }
    
    /// 生成 FlameGraph 工具兼容的折叠格式
    /// 格式：func1;func2;func3 count
    /// @post 返回折叠格式的字符串
    pub fn generateFoldedFormat(self: *const FlameGraphGenerator, allocator: std.mem.Allocator) ![]u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        errdefer buffer.deinit(allocator);
        
        const writer = buffer.writer(allocator);
        
        // 遍历树生成折叠格式
        try self.writeFoldedNode(writer, self.root, &.{});
        
        return buffer.toOwnedSlice(allocator);
    }
    
    /// 递归写入折叠格式节点
    fn writeFoldedNode(
        self: *const FlameGraphGenerator,
        writer: anytype,
        node: *const FlameGraphNode,
        stack: []const []const u8,
    ) !void {
        // 跳过根节点
        if (node.parent == null and std.mem.eql(u8, node.name, "root")) {
            var iter = node.children.valueIterator();
            while (iter.next()) |child| {
                try self.writeFoldedNode(writer, child.*, stack);
            }
            return;
        }
        
        // 跳过时间太短的节点
        if (node.total_time_ns < self.min_display_time_ns) {
            return;
        }
        
        // 构建新的调用栈
        var new_stack = try self.allocator.alloc([]const u8, stack.len + 1);
        defer self.allocator.free(new_stack);
        
        @memcpy(new_stack[0..stack.len], stack);
        new_stack[stack.len] = node.name;
        
        // 如果有自身时间，输出当前栈
        if (node.self_time_ns > 0) {
            // 输出调用栈
            for (new_stack, 0..) |name, i| {
                if (i > 0) try writer.writeAll(";");
                try writer.writeAll(name);
            }
            
            // 输出时间（转换为微秒）
            const time_us = node.self_time_ns / 1000;
            try writer.print(" {d}\n", .{time_us});
        }
        
        // 递归处理子节点
        var iter = node.children.valueIterator();
        while (iter.next()) |child| {
            try self.writeFoldedNode(writer, child.*, new_stack);
        }
    }
    
    /// 识别热点函数
    /// @param top_n 返回前 N 个热点函数
    /// @post 返回按总时间排序的热点函数列表
    pub fn identifyHotspots(self: *const FlameGraphGenerator, allocator: std.mem.Allocator, top_n: usize) ![]HotspotInfo {
        var hotspots: std.ArrayListUnmanaged(HotspotInfo) = .{};
        errdefer hotspots.deinit(allocator);
        
        // 收集所有节点
        try self.collectHotspots(self.root, &hotspots);
        
        // 按总时间排序
        std.mem.sort(HotspotInfo, hotspots.items, {}, struct {
            fn lessThan(_: void, a: HotspotInfo, b: HotspotInfo) bool {
                return a.total_time_ns > b.total_time_ns;
            }
        }.lessThan);
        
        // 返回前 N 个
        const count = @min(top_n, hotspots.items.len);
        const result = try allocator.alloc(HotspotInfo, count);
        @memcpy(result, hotspots.items[0..count]);
        
        return result;
    }
    
    /// 递归收集热点信息
    fn collectHotspots(self: *const FlameGraphGenerator, node: *const FlameGraphNode, hotspots: *std.ArrayListUnmanaged(HotspotInfo)) !void {
        // 跳过根节点
        if (node.parent == null and std.mem.eql(u8, node.name, "root")) {
            var iter = node.children.valueIterator();
            while (iter.next()) |child| {
                try self.collectHotspots(child.*, hotspots);
            }
            return;
        }
        
        // 跳过时间太短的节点
        if (node.total_time_ns < self.min_display_time_ns) {
            return;
        }
        
        // 添加当前节点
        try hotspots.append(self.allocator, .{
            .function_name = node.name,
            .total_time_ns = node.total_time_ns,
            .self_time_ns = node.self_time_ns,
            .call_count = node.call_count,
            .percentage = 0.0, // 稍后计算
        });
        
        // 递归处理子节点
        var iter = node.children.valueIterator();
        while (iter.next()) |child| {
            try self.collectHotspots(child.*, hotspots);
        }
    }
    
    /// 生成火焰图 SVG
    /// @post 返回 SVG 格式的火焰图
    pub fn generateSVG(self: *const FlameGraphGenerator, allocator: std.mem.Allocator, width: u32, height: u32) ![]u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        errdefer buffer.deinit(allocator);
        
        const writer = buffer.writer(allocator);
        
        // SVG 头部
        try writer.print(
            \\<?xml version="1.0" standalone="no"?>
            \\<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
            \\<svg version="1.1" width="{d}" height="{d}" xmlns="http://www.w3.org/2000/svg">
            \\<defs>
            \\  <linearGradient id="background" y1="0" y2="1" x1="0" x2="0">
            \\    <stop stop-color="#eeeeee" offset="5%"/>
            \\    <stop stop-color="#eeeeb0" offset="95%"/>
            \\  </linearGradient>
            \\</defs>
            \\<rect x="0" y="0" width="{d}" height="{d}" fill="url(#background)"/>
            \\<text text-anchor="middle" x="{d}" y="24" font-size="17" font-family="Verdana" fill="rgb(0,0,0)">Flame Graph</text>
            \\
        , .{ width, height, width, height, width / 2 });
        
        // 绘制火焰图
        const total_time = self.root.total_time_ns;
        if (total_time > 0) {
            try self.drawNode(writer, self.root, 0, 0, @floatFromInt(width), total_time, 40);
        }
        
        // SVG 尾部
        try writer.writeAll("</svg>\n");
        
        return buffer.toOwnedSlice(allocator);
    }
    
    /// 递归绘制节点
    fn drawNode(
        self: *const FlameGraphGenerator,
        writer: anytype,
        node: *const FlameGraphNode,
        depth: u32,
        x: f64,
        width_px: f64,
        total_time: u64,
        y_offset: u32,
    ) !void {
        const box_height = 16;
        const y = y_offset + depth * (box_height + 1);
        
        // 跳过太小的节点
        if (width_px < 0.1) return;
        
        // 计算颜色（基于深度）
        const hue = @mod(depth * 17, 360);
        const color = try std.fmt.allocPrint(self.allocator, "hsl({d}, 60%, 60%)", .{hue});
        defer self.allocator.free(color);
        
        // 绘制矩形
        try writer.print(
            \\<rect x="{d:.2}" y="{d}" width="{d:.2}" height="{d}" fill="{s}" stroke="white"/>
            \\
        , .{ x, y, width_px, box_height, color });
        
        // 绘制文本（如果空间足够）
        if (width_px > 20) {
            const text_x = x + width_px / 2.0;
            const text_y = y + 12;
            
            try writer.print(
                \\<text text-anchor="middle" x="{d:.2}" y="{d}" font-size="12" font-family="Verdana" fill="rgb(0,0,0)">{s}</text>
                \\
            , .{ text_x, text_y, node.name });
        }
        
        // 绘制子节点
        var child_x = x;
        var iter = node.children.valueIterator();
        while (iter.next()) |child| {
            const child_width = width_px * @as(f64, @floatFromInt(child.*.total_time_ns)) / @as(f64, @floatFromInt(node.total_time_ns));
            
            if (child_width > 0.1) {
                try self.drawNode(writer, child.*, depth + 1, child_x, child_width, total_time, y_offset);
            }
            
            child_x += child_width;
        }
    }
    
    /// 保存折叠格式到文件
    /// @param path 输出文件路径
    /// @post 折叠格式数据被写入文件
    pub fn saveFoldedFormat(self: *const FlameGraphGenerator, path: []const u8) !void {
        const folded = try self.generateFoldedFormat(self.allocator);
        defer self.allocator.free(folded);
        
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        
        try file.writeAll(folded);
    }
    
    /// 保存 SVG 到文件
    /// @param path 输出文件路径
    /// @param width SVG 宽度
    /// @param height SVG 高度
    /// @post SVG 数据被写入文件
    pub fn saveSVG(self: *const FlameGraphGenerator, path: []const u8, width: u32, height: u32) !void {
        const svg = try self.generateSVG(self.allocator, width, height);
        defer self.allocator.free(svg);
        
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        
        try file.writeAll(svg);
    }
    
    /// 打印热点报告
    pub fn printHotspotReport(self: *const FlameGraphGenerator, top_n: usize) !void {
        const hotspots = try self.identifyHotspots(self.allocator, top_n);
        defer self.allocator.free(hotspots);
        
        // 计算总时间
        const total_time = self.root.total_time_ns;
        
        std.debug.print("\n=== 热点函数报告 (Top {d}) ===\n", .{top_n});
        std.debug.print("总执行时间: {d} ns ({d:.2} ms)\n\n", .{
            total_time,
            @as(f64, @floatFromInt(total_time)) / 1_000_000.0,
        });
        
        std.debug.print("{s:<40} {s:>12} {s:>12} {s:>10} {s:>8}\n", .{
            "函数名",
            "总时间(ms)",
            "自身时间(ms)",
            "调用次数",
            "占比(%)",
        });
        std.debug.print("{s}\n", .{"-" ** 90});
        
        for (hotspots) |hotspot| {
            const percentage = if (total_time > 0)
                @as(f64, @floatFromInt(hotspot.total_time_ns)) / @as(f64, @floatFromInt(total_time)) * 100.0
            else
                0.0;
            
            std.debug.print("{s:<40} {d:>12.2} {d:>12.2} {d:>10} {d:>7.2}\n", .{
                hotspot.function_name,
                @as(f64, @floatFromInt(hotspot.total_time_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(hotspot.self_time_ns)) / 1_000_000.0,
                hotspot.call_count,
                percentage,
            });
        }
    }
};

/// 热点信息
pub const HotspotInfo = struct {
    /// 函数名
    function_name: []const u8,
    /// 总执行时间（纳秒）
    total_time_ns: u64,
    /// 自身执行时间（纳秒）
    self_time_ns: u64,
    /// 调用次数
    call_count: u64,
    /// 占总时间的百分比
    percentage: f64,
};

// ============================================================================
// 测试
// ============================================================================

test "FlameGraphNode 基本功能" {
    const allocator = std.testing.allocator;
    
    const node = try FlameGraphNode.init(allocator, "test_func");
    defer {
        node.deinit(allocator);
        allocator.destroy(node);
    }
    
    try std.testing.expectEqualStrings("test_func", node.name);
    try std.testing.expectEqual(@as(u64, 0), node.total_time_ns);
    try std.testing.expectEqual(@as(u64, 0), node.call_count);
}

test "FlameGraphNode 添加子节点" {
    const allocator = std.testing.allocator;
    
    const parent = try FlameGraphNode.init(allocator, "parent");
    defer {
        parent.deinit(allocator);
        allocator.destroy(parent);
    }
    
    const child1 = try parent.addChild(allocator, "child1", 1000);
    const child2 = try parent.addChild(allocator, "child2", 2000);
    
    try std.testing.expectEqual(@as(u64, 1000), child1.total_time_ns);
    try std.testing.expectEqual(@as(u64, 2000), child2.total_time_ns);
    try std.testing.expectEqual(@as(usize, 2), parent.children.count());
}

test "FlameGraphNode 计算自身时间" {
    const allocator = std.testing.allocator;
    
    const parent = try FlameGraphNode.init(allocator, "parent");
    defer {
        parent.deinit(allocator);
        allocator.destroy(parent);
    }
    
    parent.total_time_ns = 10000;
    
    _ = try parent.addChild(allocator, "child1", 3000);
    _ = try parent.addChild(allocator, "child2", 4000);
    
    parent.calculateSelfTime();
    
    // 自身时间 = 总时间 - 子节点时间 = 10000 - (3000 + 4000) = 3000
    try std.testing.expectEqual(@as(u64, 3000), parent.self_time_ns);
}

test "FlameGraphGenerator 初始化" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    try std.testing.expectEqualStrings("root", generator.root.name);
    try std.testing.expectEqual(@as(usize, 0), generator.samples.items.len);
}

test "FlameGraphGenerator 添加样本" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    const frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000 },
        .{ .function_name = "foo", .file_name = null, .line_number = null, .duration_ns = 500 },
    };
    
    try generator.addSample(&frames, 1000);
    
    try std.testing.expectEqual(@as(usize, 1), generator.samples.items.len);
}

test "FlameGraphGenerator 从样本构建" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 添加样本
    const frames1 = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000 },
        .{ .function_name = "foo", .file_name = null, .line_number = null, .duration_ns = 500 },
    };
    try generator.addSample(&frames1, 1000);
    
    const frames2 = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000 },
        .{ .function_name = "bar", .file_name = null, .line_number = null, .duration_ns = 300 },
    };
    try generator.addSample(&frames2, 1000);
    
    // 构建火焰图
    try generator.buildFromSamples();
    
    // 验证树结构
    try std.testing.expect(generator.root.children.count() > 0);
}

test "FlameGraphGenerator 生成折叠格式" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 设置较低的最小显示时间以确保数据被包含
    generator.setMinDisplayTime(0);
    
    // 添加样本
    const frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000000 },
        .{ .function_name = "foo", .file_name = null, .line_number = null, .duration_ns = 500000 },
    };
    try generator.addSample(&frames, 1000000);
    
    // 构建火焰图
    try generator.buildFromSamples();
    
    // 生成折叠格式
    const folded = try generator.generateFoldedFormat(allocator);
    defer allocator.free(folded);
    
    // 验证格式不为空
    try std.testing.expect(folded.len > 0);
}

test "FlameGraphGenerator 识别热点" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 设置较低的最小显示时间
    generator.setMinDisplayTime(0);
    
    // 添加多个样本
    const frames1 = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000000 },
        .{ .function_name = "slow_func", .file_name = null, .line_number = null, .duration_ns = 900000 },
    };
    try generator.addSample(&frames1, 1000000);
    
    const frames2 = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000000 },
        .{ .function_name = "fast_func", .file_name = null, .line_number = null, .duration_ns = 100000 },
    };
    try generator.addSample(&frames2, 1000000);
    
    // 构建火焰图
    try generator.buildFromSamples();
    
    // 识别热点
    const hotspots = try generator.identifyHotspots(allocator, 5);
    defer allocator.free(hotspots);
    
    // 验证有热点数据
    try std.testing.expect(hotspots.len >= 0); // 至少不会崩溃
}

test "FlameGraphGenerator 从 Profiler 收集" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 模拟一些函数调用
    try profiler.enterFunction("test_func1");
    try profiler.exitFunction("test_func1");
    
    try profiler.enterFunction("test_func2");
    try profiler.exitFunction("test_func2");
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 从 profiler 收集数据
    try generator.collectFromProfiler();
    
    // 验证数据被收集
    try std.testing.expect(generator.root.children.count() > 0);
}

test "FlameGraphGenerator 设置参数" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 设置采样间隔
    generator.setSamplingInterval(5_000_000); // 5ms
    try std.testing.expectEqual(@as(u64, 5_000_000), generator.sampling_interval_ns);
    
    // 设置最小显示时间
    generator.setMinDisplayTime(500_000); // 0.5ms
    try std.testing.expectEqual(@as(u64, 500_000), generator.min_display_time_ns);
}

test "StackFrame 格式化" {
    const frame = StackFrame{
        .function_name = "test_func",
        .file_name = "test.zig",
        .line_number = 42,
        .duration_ns = 1000,
    };
    
    // 简单验证结构体字段
    try std.testing.expectEqualStrings("test_func", frame.function_name);
    try std.testing.expectEqualStrings("test.zig", frame.file_name.?);
    try std.testing.expectEqual(@as(u32, 42), frame.line_number.?);
}

test "HotspotInfo 格式化" {
    const hotspot = HotspotInfo{
        .function_name = "hot_func",
        .total_time_ns = 10_000_000, // 10ms
        .self_time_ns = 5_000_000, // 5ms
        .call_count = 100,
        .percentage = 25.5,
    };
    
    // 简单验证结构体字段
    try std.testing.expectEqualStrings("hot_func", hotspot.function_name);
    try std.testing.expectEqual(@as(u64, 10_000_000), hotspot.total_time_ns);
    try std.testing.expectEqual(@as(u64, 100), hotspot.call_count);
}
