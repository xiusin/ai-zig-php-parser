const std = @import("std");
const Allocator = std.mem.Allocator;

/// 函数统计信息
pub const FunctionStats = struct {
    name: []const u8,
    call_count: u64,
    total_time_ns: u64,
    self_time_ns: u64,

    pub fn avgTime(self: FunctionStats) u64 {
        if (self.call_count == 0) return 0;
        return self.total_time_ns / self.call_count;
    }
};

/// 实时性能分析器
pub const Profiler = struct {
    allocator: Allocator,
    /// 采样间隔（微秒）
    sample_interval_us: u64,
    /// 函数统计信息
    function_stats: std.StringHashMap(FunctionStats),
    /// 是否正在运行
    running: std.atomic.Value(bool),
    /// 采样线程
    sampler_thread: ?std.Thread,

    pub fn init(allocator: Allocator, sample_interval_us: u64) !Profiler {
        return Profiler{
            .allocator = allocator,
            .sample_interval_us = sample_interval_us,
            .function_stats = std.StringHashMap(FunctionStats).init(allocator),
            .running = std.atomic.Value(bool).init(false),
            .sampler_thread = null,
        };
    }

    pub fn deinit(self: *Profiler) void {
        self.stop();
        self.function_stats.deinit();
    }

    pub fn start(self: *Profiler) !void {
        self.running.store(true, .seq_cst);
        self.sampler_thread = try std.Thread.spawn(.{}, samplerLoop, .{self});
    }

    pub fn stop(self: *Profiler) void {
        self.running.store(false, .seq_cst);
        if (self.sampler_thread) |thread| {
            thread.join();
            self.sampler_thread = null;
        }
    }

    fn samplerLoop(self: *Profiler) void {
        while (self.running.load(.seq_cst)) {
            // 采样当前调用栈（简化实现）
            self.recordSample("main") catch {};

            // 休眠
            std.Thread.sleep(self.sample_interval_us * 1000);
        }
    }

    fn recordSample(self: *Profiler, function_name: []const u8) !void {
        const entry = try self.function_stats.getOrPut(function_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .name = function_name,
                .call_count = 0,
                .total_time_ns = 0,
                .self_time_ns = 0,
            };
        }
        entry.value_ptr.call_count += 1;
    }

    /// 记录函数调用
    pub fn recordFunctionCall(self: *Profiler, function_name: []const u8, duration_ns: u64) !void {
        const entry = try self.function_stats.getOrPut(function_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .name = function_name,
                .call_count = 0,
                .total_time_ns = 0,
                .self_time_ns = 0,
            };
        }
        entry.value_ptr.call_count += 1;
        entry.value_ptr.total_time_ns += duration_ns;
        entry.value_ptr.self_time_ns += duration_ns;
    }

    /// 生成火焰图数据（Folded Stack 格式）
    pub fn generateFlameGraph(self: *Profiler, writer: anytype) !void {
        var it = self.function_stats.iterator();
        while (it.next()) |entry| {
            const stats = entry.value_ptr.*;
            try writer.print("{s} {d}\n", .{ stats.name, stats.total_time_ns });
        }
    }

    /// 获取统计信息
    pub fn getStats(self: *Profiler, function_name: []const u8) ?FunctionStats {
        return self.function_stats.get(function_name);
    }
};
