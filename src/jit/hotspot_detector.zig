const std = @import("std");

/// 热点检测器
///
/// 检测频繁执行的函数和循环，触发 JIT 编译
pub const HotspotDetector = struct {
    allocator: std.mem.Allocator,

    /// 函数执行计数器
    function_counters: std.StringHashMap(u32),
    /// 循环执行计数器
    loop_counters: std.AutoHashMap(*Loop, u32),

    /// 热点阈值
    function_threshold: u32 = 1000,
    loop_threshold: u32 = 10000,

    /// 循环表示
    pub const Loop = struct {
        id: u32,
        function_name: []const u8,
        start_offset: u32,
        end_offset: u32,
    };

    pub fn init(allocator: std.mem.Allocator) HotspotDetector {
        return .{
            .allocator = allocator,
            .function_counters = std.StringHashMap(u32).init(allocator),
            .loop_counters = std.AutoHashMap(*Loop, u32).init(allocator),
        };
    }

    pub fn deinit(self: *HotspotDetector) void {
        self.function_counters.deinit();
        self.loop_counters.deinit();
    }

    /// 记录函数调用
    /// @post 返回是否达到热点阈值
    pub fn recordFunctionCall(self: *HotspotDetector, function_name: []const u8) !bool {
        const entry = try self.function_counters.getOrPut(function_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;

        return entry.value_ptr.* >= self.function_threshold;
    }

    /// 记录循环迭代
    /// @post 返回是否达到热点阈值
    pub fn recordLoopIteration(self: *HotspotDetector, loop: *Loop) !bool {
        const entry = try self.loop_counters.getOrPut(loop);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;

        return entry.value_ptr.* >= self.loop_threshold;
    }

    /// 获取函数执行次数
    pub fn getFunctionCount(self: *HotspotDetector, function_name: []const u8) u32 {
        return self.function_counters.get(function_name) orelse 0;
    }

    /// 检查是否为热点函数
    pub fn isHotspot(self: *HotspotDetector, function_name: []const u8) bool {
        const count = self.function_counters.get(function_name) orelse 0;
        return count >= self.function_threshold;
    }

    /// 获取循环执行次数
    pub fn getLoopCount(self: *HotspotDetector, loop: *Loop) u32 {
        return self.loop_counters.get(loop) orelse 0;
    }

    /// 重置计数器
    pub fn reset(self: *HotspotDetector) void {
        self.function_counters.clearRetainingCapacity();
        self.loop_counters.clearRetainingCapacity();
    }

    /// 获取所有热点函数
    pub fn getHotFunctions(self: *HotspotDetector, allocator: std.mem.Allocator) ![][]const u8 {
        var hot_functions = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        errdefer hot_functions.deinit(allocator);

        var it = self.function_counters.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* >= self.function_threshold) {
                try hot_functions.append(allocator, entry.key_ptr.*);
            }
        }

        return hot_functions.toOwnedSlice(allocator);
    }

    /// 获取所有热点循环
    pub fn getHotLoops(self: *HotspotDetector, allocator: std.mem.Allocator) ![]*Loop {
        var hot_loops = try std.ArrayList(*Loop).initCapacity(allocator, 0);
        errdefer hot_loops.deinit(allocator);

        var it = self.loop_counters.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* >= self.loop_threshold) {
                try hot_loops.append(allocator, entry.key_ptr.*);
            }
        }

        return hot_loops.toOwnedSlice(allocator);
    }
};
