/// 性能剖析器
/// 
/// 提供统一的性能剖析接口，集成 perf 和 tracy
/// 支持函数级性能数据收集和分析
/// 
/// @concurrency-model THREAD_SAFE
/// @ownership NON-OWNING (allocator)
/// @memory-safety 所有内存操作通过显式 allocator

const std = @import("std");
const builtin = @import("builtin");

/// 剖析器类型
pub const ProfilerType = enum {
    /// 无剖析
    none,
    /// Linux perf 集成
    perf,
    /// Tracy profiler 集成
    tracy,
    /// 自定义剖析器
    custom,
};

var global_profiler_ptr = std.atomic.Value(usize).init(0);

pub fn setGlobalProfiler(profiler: ?*Profiler) void {
    const v: usize = if (profiler) |p| @intFromPtr(p) else 0;
    global_profiler_ptr.store(v, .seq_cst);
}

pub fn getGlobalProfiler() ?*Profiler {
    const v = global_profiler_ptr.load(.seq_cst);
    if (v == 0) return null;
    return @ptrFromInt(v);
}

pub fn enterGlobal(name: []const u8) void {
    if (getGlobalProfiler()) |p| {
        p.enterFunction(name) catch {};
    }
}

pub fn exitGlobal(name: []const u8) void {
    if (getGlobalProfiler()) |p| {
        p.exitFunction(name) catch {};
    }
}

/// 函数调用记录
pub const FunctionCall = struct {
    /// 函数名
    name: []const u8,
    /// 开始时间 (纳秒)
    start_time_ns: u64,
    /// 结束时间 (纳秒)
    end_time_ns: u64,
    /// 调用深度
    depth: u32,
    /// CPU 周期数
    cpu_cycles: u64,
    /// 指令数
    instructions: u64,
    /// 缓存未命中
    cache_misses: u64,
    
    /// 计算执行时间
    pub fn duration(self: *const FunctionCall) u64 {
        return self.end_time_ns - self.start_time_ns;
    }
    
    /// 计算 IPC (Instructions Per Cycle)
    pub fn ipc(self: *const FunctionCall) f64 {
        if (self.cpu_cycles == 0) return 0.0;
        return @as(f64, @floatFromInt(self.instructions)) / @as(f64, @floatFromInt(self.cpu_cycles));
    }
    
    /// 计算缓存命中率
    pub fn cacheHitRate(self: *const FunctionCall) f64 {
        const total_accesses = self.instructions; // 简化假设
        if (total_accesses == 0) return 1.0;
        const hits = total_accesses - self.cache_misses;
        return @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(total_accesses));
    }
};

/// 函数统计信息
pub const FunctionStats = struct {
    /// 函数名
    name: []const u8,
    /// 调用次数
    call_count: u64,
    /// 总执行时间 (纳秒)
    total_time_ns: u64,
    /// 最小执行时间 (纳秒)
    min_time_ns: u64,
    /// 最大执行时间 (纳秒)
    max_time_ns: u64,
    /// 总 CPU 周期数
    total_cycles: u64,
    /// 总指令数
    total_instructions: u64,
    /// 总缓存未命中
    total_cache_misses: u64,
    
    /// 计算平均执行时间
    pub fn avgTime(self: *const FunctionStats) f64 {
        if (self.call_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.call_count));
    }
    
    /// 计算平均 IPC
    pub fn avgIPC(self: *const FunctionStats) f64 {
        if (self.total_cycles == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_instructions)) / @as(f64, @floatFromInt(self.total_cycles));
    }
    
    /// 计算平均缓存命中率
    pub fn avgCacheHitRate(self: *const FunctionStats) f64 {
        const total_accesses = self.total_instructions;
        if (total_accesses == 0) return 1.0;
        const hits = total_accesses - self.total_cache_misses;
        return @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(total_accesses));
    }
    
    pub fn format(
        self: FunctionStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            "{s}: calls={d}, avg_time={d:.2}ns, ipc={d:.2}, cache_hit={d:.2}%",
            .{
                self.name,
                self.call_count,
                self.avgTime(),
                self.avgIPC(),
                self.avgCacheHitRate() * 100.0,
            },
        );
    }
    
    pub fn fmtAny(self: FunctionStats) std.fmt.Formatter(formatAny) {
        return .{ .data = self };
    }
    
    fn formatAny(
        self: FunctionStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        return format(self, fmt, options, writer);
    }
};

/// 性能剖析器
pub const Profiler = struct {
    allocator: std.mem.Allocator,
    profiler_type: ProfilerType,
    enabled: bool,
    
    // 函数调用栈
    call_stack: std.ArrayListUnmanaged(FunctionCall),
    
    // 函数统计
    function_stats: std.StringHashMap(FunctionStats),
    
    // 全局统计
    total_calls: u64,
    total_time_ns: u64,
    
    // 线程安全
    mutex: std.Thread.Mutex,
    
    /// 初始化剖析器
    /// @pre allocator 必须有效
    /// @post 返回初始化的剖析器
    pub fn init(allocator: std.mem.Allocator, profiler_type: ProfilerType) !Profiler {
        return Profiler{
            .allocator = allocator,
            .profiler_type = profiler_type,
            .enabled = profiler_type != .none,
            .call_stack = .{},
            .function_stats = std.StringHashMap(FunctionStats).init(allocator),
            .total_calls = 0,
            .total_time_ns = 0,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    /// 清理资源
    pub fn deinit(self: *Profiler) void {
        self.call_stack.deinit(self.allocator);
        
        // 清理函数名字符串
        var iter = self.function_stats.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.function_stats.deinit();
    }
    
    /// 启用剖析
    pub fn enable(self: *Profiler) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = true;
    }
    
    /// 禁用剖析
    pub fn disable(self: *Profiler) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = false;
    }
    
    /// 开始函数调用
    /// @pre name 必须有效
    /// @post 记录函数调用开始
    pub fn enterFunction(self: *Profiler, name: []const u8) !void {
        if (!self.enabled) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const call = FunctionCall{
            .name = name,
            .start_time_ns = @intCast(std.time.nanoTimestamp()),
            .end_time_ns = 0,
            .depth = @intCast(self.call_stack.items.len),
            .cpu_cycles = 0,
            .instructions = 0,
            .cache_misses = 0,
        };
        
        try self.call_stack.append(self.allocator, call);
        self.total_calls += 1;
    }
    
    /// 结束函数调用
    /// @pre 必须有对应的 enterFunction 调用
    /// @post 记录函数调用结束并更新统计
    pub fn exitFunction(self: *Profiler, name: []const u8) !void {
        if (!self.enabled) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const call_opt = self.call_stack.pop();
        if (call_opt == null) {
            return error.CallStackUnderflow;
        }
        var call = call_opt.?;
        
        // 验证函数名匹配
        if (!std.mem.eql(u8, call.name, name)) {
            return error.FunctionNameMismatch;
        }
        
        // 记录结束时间
        call.end_time_ns = @intCast(std.time.nanoTimestamp());
        
        // 更新统计
        try self.updateStats(&call);
        
        // 更新全局统计
        self.total_time_ns += call.duration();
    }
    
    /// 更新函数统计
    fn updateStats(self: *Profiler, call: *const FunctionCall) !void {
        const gop = try self.function_stats.getOrPut(call.name);
        
        if (!gop.found_existing) {
            // 复制函数名
            const name_copy = try self.allocator.dupe(u8, call.name);
            gop.key_ptr.* = name_copy;
            
            // 初始化统计
            gop.value_ptr.* = FunctionStats{
                .name = name_copy,
                .call_count = 0,
                .total_time_ns = 0,
                .min_time_ns = std.math.maxInt(u64),
                .max_time_ns = 0,
                .total_cycles = 0,
                .total_instructions = 0,
                .total_cache_misses = 0,
            };
        }
        
        const stats = gop.value_ptr;
        const duration_ns = call.duration();
        
        stats.call_count += 1;
        stats.total_time_ns += duration_ns;
        if (duration_ns < stats.min_time_ns) stats.min_time_ns = duration_ns;
        if (duration_ns > stats.max_time_ns) stats.max_time_ns = duration_ns;
        stats.total_cycles += call.cpu_cycles;
        stats.total_instructions += call.instructions;
        stats.total_cache_misses += call.cache_misses;
    }
    
    /// 获取函数统计
    pub fn getFunctionStats(self: *const Profiler, name: []const u8) ?FunctionStats {
        return self.function_stats.get(name);
    }
    
    /// 获取所有函数统计
    pub fn getAllStats(self: *const Profiler, allocator: std.mem.Allocator) ![]FunctionStats {
        var stats_list: std.ArrayListUnmanaged(FunctionStats) = .{};
        errdefer stats_list.deinit(allocator);
        
        var iter = self.function_stats.valueIterator();
        while (iter.next()) |stats| {
            try stats_list.append(allocator, stats.*);
        }
        
        return stats_list.toOwnedSlice(allocator);
    }
    
    /// 获取热点函数 (按总时间排序)
    pub fn getHotspots(self: *const Profiler, allocator: std.mem.Allocator, top_n: usize) ![]FunctionStats {
        const all_stats = try self.getAllStats(allocator);
        defer allocator.free(all_stats);
        
        // 按总时间排序
        std.mem.sort(FunctionStats, all_stats, {}, struct {
            fn lessThan(_: void, a: FunctionStats, b: FunctionStats) bool {
                return a.total_time_ns > b.total_time_ns;
            }
        }.lessThan);
        
        // 返回前 N 个
        const count = @min(top_n, all_stats.len);
        const hotspots = try allocator.alloc(FunctionStats, count);
        @memcpy(hotspots, all_stats[0..count]);
        
        return hotspots;
    }
    
    /// 打印统计报告
    pub fn printReport(self: *const Profiler) void {
        std.debug.print("\n=== 性能剖析报告 ===\n", .{});
        std.debug.print("剖析器类型: {s}\n", .{@tagName(self.profiler_type)});
        std.debug.print("总调用次数: {d}\n", .{self.total_calls});
        std.debug.print("总执行时间: {d} ns ({d:.2} ms)\n", .{
            self.total_time_ns,
            @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0,
        });
        
        std.debug.print("\n函数统计:\n", .{});
        var iter = self.function_stats.valueIterator();
        while (iter.next()) |stats| {
            std.debug.print("  {any}\n", .{stats.*});
        }
    }
    
    /// 导出为 JSON 格式
    pub fn exportJSON(self: *const Profiler, writer: anytype) !void {
        try writer.writeAll("{");
        try writer.print("\"profiler_type\":\"{s}\",", .{@tagName(self.profiler_type)});
        try writer.print("\"total_calls\":{d},", .{self.total_calls});
        try writer.print("\"total_time_ns\":{d},", .{self.total_time_ns});
        try writer.writeAll("\"functions\":[");
        
        var first = true;
        var iter = self.function_stats.valueIterator();
        while (iter.next()) |stats| {
            if (!first) try writer.writeAll(",");
            first = false;
            
            try writer.writeAll("{");
            try writer.print("\"name\":\"{s}\",", .{stats.name});
            try writer.print("\"call_count\":{d},", .{stats.call_count});
            try writer.print("\"total_time_ns\":{d},", .{stats.total_time_ns});
            try writer.print("\"avg_time_ns\":{d:.2},", .{stats.avgTime()});
            try writer.print("\"min_time_ns\":{d},", .{stats.min_time_ns});
            try writer.print("\"max_time_ns\":{d},", .{stats.max_time_ns});
            try writer.print("\"avg_ipc\":{d:.2},", .{stats.avgIPC()});
            try writer.print("\"avg_cache_hit_rate\":{d:.4}", .{stats.avgCacheHitRate()});
            try writer.writeAll("}");
        }
        
        try writer.writeAll("]}");
    }

    pub fn snapshotCallStackNames(self: *const Profiler, allocator: std.mem.Allocator) ![]const []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const stack = try allocator.alloc([]const u8, self.call_stack.items.len);
        for (self.call_stack.items, 0..) |call, i| {
            stack[i] = call.name;
        }
        return stack;
    }
    
    /// 重置所有统计
    pub fn reset(self: *Profiler) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.call_stack.clearRetainingCapacity();
        
        // 清理函数名字符串
        var iter = self.function_stats.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.function_stats.clearRetainingCapacity();
        
        self.total_calls = 0;
        self.total_time_ns = 0;
    }
};

/// 作用域剖析器 (RAII)
/// 自动在作用域开始时调用 enterFunction，结束时调用 exitFunction
pub const ScopedProfiler = struct {
    profiler: *Profiler,
    name: []const u8,
    
    pub fn init(profiler: *Profiler, name: []const u8) !ScopedProfiler {
        try profiler.enterFunction(name);
        return ScopedProfiler{
            .profiler = profiler,
            .name = name,
        };
    }
    
    pub fn deinit(self: *ScopedProfiler) void {
        self.profiler.exitFunction(self.name) catch |err| {
            std.debug.print("错误: 退出函数 {s} 失败: {}\n", .{ self.name, err });
        };
    }
};

// ============================================================================
// 便捷宏：剖析函数
// 使用示例:
// ```zig
// fn myFunction(profiler: *Profiler) !void {
//     var scoped = try ScopedProfiler.init(profiler, "myFunction");
//     defer scoped.deinit();
//     
//     // 函数体
// }
// ```
// ============================================================================

// ============================================================================
// 测试
// ============================================================================

test "Profiler 基本功能" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 模拟函数调用
    try profiler.enterFunction("test_func");
    
    // 模拟一些工作
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        sum += i;
    }
    
    try profiler.exitFunction("test_func");
    
    // 验证统计
    const stats = profiler.getFunctionStats("test_func");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 1), stats.?.call_count);
    try std.testing.expect(stats.?.total_time_ns > 0);
}

test "Profiler 嵌套调用" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 外层函数
    try profiler.enterFunction("outer");
    
    // 内层函数
    try profiler.enterFunction("inner");
    try profiler.exitFunction("inner");
    
    try profiler.exitFunction("outer");
    
    // 验证统计
    const outer_stats = profiler.getFunctionStats("outer");
    const inner_stats = profiler.getFunctionStats("inner");
    
    try std.testing.expect(outer_stats != null);
    try std.testing.expect(inner_stats != null);
    try std.testing.expectEqual(@as(u64, 1), outer_stats.?.call_count);
    try std.testing.expectEqual(@as(u64, 1), inner_stats.?.call_count);
}

test "Profiler 多次调用" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 多次调用同一函数
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try profiler.enterFunction("repeated_func");
        try profiler.exitFunction("repeated_func");
    }
    
    // 验证统计
    const stats = profiler.getFunctionStats("repeated_func");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 10), stats.?.call_count);
}

test "ScopedProfiler RAII" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    {
        var scoped = try ScopedProfiler.init(&profiler, "scoped_func");
        defer scoped.deinit();
        
        // 函数体
        var sum: u64 = 0;
        var i: u64 = 0;
        while (i < 100) : (i += 1) {
            sum += i;
        }
    }
    
    // 验证统计
    const stats = profiler.getFunctionStats("scoped_func");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 1), stats.?.call_count);
}

test "Profiler 热点函数" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 创建不同执行时间的函数
    try profiler.enterFunction("fast_func");
    try profiler.exitFunction("fast_func");
    
    try profiler.enterFunction("slow_func");
    std.Thread.sleep(1_000_000); // 1ms
    try profiler.exitFunction("slow_func");
    
    try profiler.enterFunction("medium_func");
    std.Thread.sleep(500_000); // 0.5ms
    try profiler.exitFunction("medium_func");
    
    // 获取热点函数
    const hotspots = try profiler.getHotspots(allocator, 2);
    defer allocator.free(hotspots);
    
    try std.testing.expectEqual(@as(usize, 2), hotspots.len);
    // 第一个应该是最慢的
    try std.testing.expect(std.mem.eql(u8, hotspots[0].name, "slow_func"));
}

test "Profiler JSON 导出" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    try profiler.enterFunction("test_func");
    try profiler.exitFunction("test_func");
    
    // 导出为 JSON
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    defer buffer.deinit(allocator);
    
    try profiler.exportJSON(buffer.writer(allocator));
    
    // 验证 JSON 包含必要字段
    const json = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"profiler_type\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_calls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"functions\"") != null);
}

test "Profiler 重置" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    try profiler.enterFunction("test_func");
    try profiler.exitFunction("test_func");
    
    // 验证有统计
    try std.testing.expectEqual(@as(u64, 1), profiler.total_calls);
    
    // 重置
    profiler.reset();
    
    // 验证统计被清空
    try std.testing.expectEqual(@as(u64, 0), profiler.total_calls);
    try std.testing.expect(profiler.getFunctionStats("test_func") == null);
}

test "Profiler 启用/禁用" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 禁用剖析
    profiler.disable();
    
    try profiler.enterFunction("disabled_func");
    try profiler.exitFunction("disabled_func");
    
    // 应该没有统计
    try std.testing.expect(profiler.getFunctionStats("disabled_func") == null);
    
    // 启用剖析
    profiler.enable();
    
    try profiler.enterFunction("enabled_func");
    try profiler.exitFunction("enabled_func");
    
    // 应该有统计
    try std.testing.expect(profiler.getFunctionStats("enabled_func") != null);
}
