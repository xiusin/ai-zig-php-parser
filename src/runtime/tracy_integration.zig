/// Tracy Profiler 集成
/// 
/// 提供与 Tracy profiler 的集成，支持：
/// - 函数作用域标记
/// - 帧标记
/// - 内存分配跟踪
/// - 消息日志
/// - 绘图数据
/// 
/// @platform 跨平台
/// @concurrency-model THREAD_SAFE
/// @ownership NON-OWNING (allocator)
/// 
/// Tracy 是一个实时、纳秒级精度的混合帧和采样分析器
/// 官网: https://github.com/wolfpld/tracy

const std = @import("std");
const builtin = @import("builtin");
const Profiler = @import("profiler.zig").Profiler;

/// Tracy 是否启用 (编译时配置)
pub const tracy_enabled = @import("builtin").mode != .Debug;

/// Tracy 区域颜色
pub const TracyColor = enum(u32) {
    red = 0xFF0000,
    green = 0x00FF00,
    blue = 0x0000FF,
    yellow = 0xFFFF00,
    cyan = 0x00FFFF,
    magenta = 0xFF00FF,
    white = 0xFFFFFF,
    orange = 0xFFA500,
    purple = 0x800080,
    pink = 0xFFC0CB,
    
    pub fn toU32(self: TracyColor) u32 {
        return @intFromEnum(self);
    }
};

/// Tracy 区域
pub const TracyZone = struct {
    name: []const u8,
    color: TracyColor,
    start_time: i64,
    active: bool,
    
    /// 开始区域
    pub fn begin(name: []const u8, color: TracyColor) TracyZone {
        const zone = TracyZone{
            .name = name,
            .color = color,
            .start_time = @intCast(std.time.nanoTimestamp()),
            .active = true,
        };
        
        if (tracy_enabled) {
            // 这里应该调用 Tracy C API
            // TracyZoneBegin(name, color)
            std.debug.print("[Tracy] Zone begin: {s}\n", .{name});
        }
        
        return zone;
    }
    
    /// 结束区域
    pub fn end(self: *TracyZone) void {
        if (!self.active) return;
        
        if (tracy_enabled) {
            const duration = std.time.nanoTimestamp() - self.start_time;
            // TracyZoneEnd()
            std.debug.print("[Tracy] Zone end: {s} ({d} ns)\n", .{ self.name, duration });
        }
        
        self.active = false;
    }
    
    /// 设置区域文本
    pub fn setText(self: *TracyZone, text: []const u8) void {
        if (!self.active) return;
        
        if (tracy_enabled) {
            // TracyZoneText(text)
            std.debug.print("[Tracy] Zone text: {s} - {s}\n", .{ self.name, text });
        }
    }
    
    /// 设置区域名称
    pub fn setName(self: *TracyZone, name: []const u8) void {
        if (!self.active) return;
        
        self.name = name;
        if (tracy_enabled) {
            // TracyZoneName(name)
            std.debug.print("[Tracy] Zone name: {s}\n", .{name});
        }
    }
    
    /// 设置区域颜色
    pub fn setColor(self: *TracyZone, color: TracyColor) void {
        if (!self.active) return;
        
        self.color = color;
        if (tracy_enabled) {
            // TracyZoneColor(color)
            std.debug.print("[Tracy] Zone color: {s} - 0x{X:0>6}\n", .{ self.name, color.toU32() });
        }
    }
};

/// Tracy 作用域区域 (RAII)
pub const TracyScopedZone = struct {
    zone: TracyZone,
    
    pub fn init(name: []const u8, color: TracyColor) TracyScopedZone {
        return TracyScopedZone{
            .zone = TracyZone.begin(name, color),
        };
    }
    
    pub fn deinit(self: *TracyScopedZone) void {
        self.zone.end();
    }
};

/// Tracy 帧标记
pub const TracyFrame = struct {
    name: []const u8,
    
    /// 标记帧开始
    pub fn mark(name: []const u8) void {
        if (tracy_enabled) {
            // TracyFrameMark(name)
            std.debug.print("[Tracy] Frame mark: {s}\n", .{name});
        }
    }
    
    /// 标记命名帧开始
    pub fn markStart(name: []const u8) void {
        if (tracy_enabled) {
            // TracyFrameMarkStart(name)
            std.debug.print("[Tracy] Frame start: {s}\n", .{name});
        }
    }
    
    /// 标记命名帧结束
    pub fn markEnd(name: []const u8) void {
        if (tracy_enabled) {
            // TracyFrameMarkEnd(name)
            std.debug.print("[Tracy] Frame end: {s}\n", .{name});
        }
    }
};

/// Tracy 内存分配跟踪
pub const TracyAlloc = struct {
    /// 跟踪分配
    pub fn alloc(ptr: *anyopaque, size: usize) void {
        if (tracy_enabled) {
            // TracyAlloc(ptr, size)
            std.debug.print("[Tracy] Alloc: {*} ({d} bytes)\n", .{ ptr, size });
        }
    }
    
    /// 跟踪释放
    pub fn free(ptr: *anyopaque) void {
        if (tracy_enabled) {
            // TracyFree(ptr)
            std.debug.print("[Tracy] Free: {*}\n", .{ptr});
        }
    }
    
    /// 跟踪命名分配
    pub fn allocNamed(ptr: *anyopaque, size: usize, name: []const u8) void {
        if (tracy_enabled) {
            // TracyAllocN(ptr, size, name)
            std.debug.print("[Tracy] Alloc ({s}): {*} ({d} bytes)\n", .{ name, ptr, size });
        }
    }
    
    /// 跟踪命名释放
    pub fn freeNamed(ptr: *anyopaque, name: []const u8) void {
        if (tracy_enabled) {
            // TracyFreeN(ptr, name)
            std.debug.print("[Tracy] Free ({s}): {*}\n", .{ name, ptr });
        }
    }
};

/// Tracy 消息
pub const TracyMessage = struct {
    /// 发送消息
    pub fn send(message: []const u8) void {
        if (tracy_enabled) {
            // TracyMessage(message)
            std.debug.print("[Tracy] Message: {s}\n", .{message});
        }
    }
    
    /// 发送彩色消息
    pub fn sendColor(message: []const u8, color: TracyColor) void {
        if (tracy_enabled) {
            // TracyMessageC(message, color)
            std.debug.print("[Tracy] Message (0x{X:0>6}): {s}\n", .{ color.toU32(), message });
        }
    }
};

/// Tracy 绘图数据
pub const TracyPlot = struct {
    /// 绘制浮点值
    pub fn plotFloat(name: []const u8, value: f64) void {
        if (tracy_enabled) {
            // TracyPlot(name, value)
            std.debug.print("[Tracy] Plot {s}: {d}\n", .{ name, value });
        }
    }
    
    /// 绘制整数值
    pub fn plotInt(name: []const u8, value: i64) void {
        if (tracy_enabled) {
            // TracyPlotI(name, value)
            std.debug.print("[Tracy] Plot {s}: {d}\n", .{ name, value });
        }
    }
    
    /// 配置绘图
    pub fn configure(name: []const u8, plot_type: PlotType, step: bool, fill: bool, color: TracyColor) void {
        if (tracy_enabled) {
            // TracyPlotConfig(name, type, step, fill, color)
            std.debug.print("[Tracy] Plot config {s}: type={s}, step={}, fill={}, color=0x{X:0>6}\n", .{
                name,
                @tagName(plot_type),
                step,
                fill,
                color.toU32(),
            });
        }
    }
};

/// 绘图类型
pub const PlotType = enum {
    number,
    memory,
    percentage,
};

/// Tracy 集成器
pub const TracyIntegration = struct {
    allocator: std.mem.Allocator,
    profiler: *Profiler,
    enabled: bool,
    
    // 统计
    zone_count: u64,
    frame_count: u64,
    alloc_count: u64,
    free_count: u64,
    message_count: u64,
    
    /// 初始化 Tracy 集成
    pub fn init(allocator: std.mem.Allocator, profiler: *Profiler) TracyIntegration {
        return .{
            .allocator = allocator,
            .profiler = profiler,
            .enabled = tracy_enabled,
            .zone_count = 0,
            .frame_count = 0,
            .alloc_count = 0,
            .free_count = 0,
            .message_count = 0,
        };
    }
    
    /// 清理资源
    pub fn deinit(self: *TracyIntegration) void {
        _ = self;
        // Tracy 不需要显式清理
    }
    
    /// 开始函数区域
    pub fn enterFunction(self: *TracyIntegration, name: []const u8) TracyZone {
        self.zone_count += 1;
        return TracyZone.begin(name, .green);
    }
    
    /// 结束函数区域
    pub fn exitFunction(self: *TracyIntegration, zone: *TracyZone) void {
        _ = self;
        zone.end();
    }
    
    /// 标记帧
    pub fn markFrame(self: *TracyIntegration) void {
        self.frame_count += 1;
        TracyFrame.mark("main");
    }
    
    /// 跟踪分配
    pub fn trackAlloc(self: *TracyIntegration, ptr: *anyopaque, size: usize) void {
        self.alloc_count += 1;
        TracyAlloc.alloc(ptr, size);
    }
    
    /// 跟踪释放
    pub fn trackFree(self: *TracyIntegration, ptr: *anyopaque) void {
        self.free_count += 1;
        TracyAlloc.free(ptr);
    }
    
    /// 发送消息
    pub fn sendMessage(self: *TracyIntegration, message: []const u8) void {
        self.message_count += 1;
        TracyMessage.send(message);
    }
    
    /// 绘制性能指标
    pub fn plotMetrics(self: *TracyIntegration) void {
        // 绘制函数调用统计
        const all_stats = self.profiler.getAllStats(self.allocator) catch return;
        defer self.allocator.free(all_stats);
        
        for (all_stats) |stats| {
            TracyPlot.plotFloat(stats.name, stats.avgTime());
        }
        
        // 绘制全局统计
        TracyPlot.plotInt("total_calls", @intCast(self.profiler.total_calls));
        TracyPlot.plotInt("total_time_ns", @intCast(self.profiler.total_time_ns));
    }
    
    /// 打印统计报告
    pub fn printReport(self: *const TracyIntegration) void {
        std.debug.print("\n=== Tracy 集成报告 ===\n", .{});
        std.debug.print("启用状态: {}\n", .{self.enabled});
        std.debug.print("区域数量: {d}\n", .{self.zone_count});
        std.debug.print("帧数量: {d}\n", .{self.frame_count});
        std.debug.print("分配次数: {d}\n", .{self.alloc_count});
        std.debug.print("释放次数: {d}\n", .{self.free_count});
        std.debug.print("消息数量: {d}\n", .{self.message_count});
    }
};

/// Tracy 分配器包装器
/// 自动跟踪所有内存分配和释放
pub fn TracyAllocator(comptime BaseAllocator: type) type {
    return struct {
        base_allocator: BaseAllocator,
        name: []const u8,
        
        const Self = @This();
        
        pub fn init(base_allocator: BaseAllocator, name: []const u8) Self {
            return .{
                .base_allocator = base_allocator,
                .name = name,
            };
        }
        
        pub fn allocator(self: *Self) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .free = free,
                },
            };
        }
        
        fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const result = self.base_allocator.rawAlloc(len, ptr_align, ret_addr);
            
            if (result) |ptr| {
                TracyAlloc.allocNamed(ptr, len, self.name);
            }
            
            return result;
        }
        
        fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.base_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        }
        
        fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            TracyAlloc.freeNamed(buf.ptr, self.name);
            self.base_allocator.rawFree(buf, buf_align, ret_addr);
        }
    };
}

// ============================================================================
// 便捷宏
// ============================================================================

// ============================================================================
// 便捷宏：Tracy 作用域
// 使用示例:
// ```zig
// fn myFunction() void {
//     var zone = TracyScopedZone.init("myFunction", .green);
//     defer zone.deinit();
//     
//     // 函数体
// }
// ```
// ============================================================================

// ============================================================================
// 测试
// ============================================================================

test "TracyZone 基本功能" {
    var zone = TracyZone.begin("test_zone", .green);
    
    // 模拟工作
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        sum += i;
    }
    
    zone.end();
    
    try std.testing.expect(!zone.active);
}

test "TracyScopedZone RAII" {
    {
        var zone = TracyScopedZone.init("scoped_zone", .blue);
        defer zone.deinit();
        
        // 函数体
        var sum: u64 = 0;
        var i: u64 = 0;
        while (i < 100) : (i += 1) {
            sum += i;
        }
    }
    
    // zone 应该已经自动结束
}

test "TracyZone 文本和颜色" {
    var zone = TracyZone.begin("test_zone", .green);
    defer zone.end();
    
    zone.setText("Processing data");
    zone.setColor(.yellow);
    zone.setName("renamed_zone");
    
    try std.testing.expect(zone.active);
}

test "TracyFrame 标记" {
    TracyFrame.mark("main");
    TracyFrame.markStart("render");
    TracyFrame.markEnd("render");
    
    // 无错误即通过
}

test "TracyAlloc 跟踪" {
    const allocator = std.testing.allocator;
    
    const ptr = try allocator.create(u64);
    defer allocator.destroy(ptr);
    
    TracyAlloc.alloc(ptr, @sizeOf(u64));
    TracyAlloc.free(ptr);
    
    TracyAlloc.allocNamed(ptr, @sizeOf(u64), "test_alloc");
    TracyAlloc.freeNamed(ptr, "test_alloc");
}

test "TracyMessage 发送" {
    TracyMessage.send("Test message");
    TracyMessage.sendColor("Colored message", .red);
    
    // 无错误即通过
}

test "TracyPlot 绘图" {
    TracyPlot.plotFloat("fps", 60.0);
    TracyPlot.plotInt("frame_count", 1000);
    TracyPlot.configure("memory", .memory, false, true, .cyan);
    
    // 无错误即通过
}

test "TracyIntegration 初始化" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .tracy);
    defer profiler.deinit();
    
    var tracy = TracyIntegration.init(allocator, &profiler);
    defer tracy.deinit();
    
    try std.testing.expectEqual(@as(u64, 0), tracy.zone_count);
    try std.testing.expectEqual(@as(u64, 0), tracy.frame_count);
}

test "TracyIntegration 函数跟踪" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .tracy);
    defer profiler.deinit();
    
    var tracy = TracyIntegration.init(allocator, &profiler);
    defer tracy.deinit();
    
    var zone = tracy.enterFunction("test_func");
    
    // 模拟工作
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        sum += i;
    }
    
    tracy.exitFunction(&zone);
    
    try std.testing.expectEqual(@as(u64, 1), tracy.zone_count);
}

test "TracyIntegration 帧标记" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .tracy);
    defer profiler.deinit();
    
    var tracy = TracyIntegration.init(allocator, &profiler);
    defer tracy.deinit();
    
    tracy.markFrame();
    tracy.markFrame();
    tracy.markFrame();
    
    try std.testing.expectEqual(@as(u64, 3), tracy.frame_count);
}

test "TracyIntegration 内存跟踪" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .tracy);
    defer profiler.deinit();
    
    var tracy = TracyIntegration.init(allocator, &profiler);
    defer tracy.deinit();
    
    const ptr = try allocator.create(u64);
    defer allocator.destroy(ptr);
    
    tracy.trackAlloc(ptr, @sizeOf(u64));
    tracy.trackFree(ptr);
    
    try std.testing.expectEqual(@as(u64, 1), tracy.alloc_count);
    try std.testing.expectEqual(@as(u64, 1), tracy.free_count);
}

test "TracyIntegration 消息" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .tracy);
    defer profiler.deinit();
    
    var tracy = TracyIntegration.init(allocator, &profiler);
    defer tracy.deinit();
    
    tracy.sendMessage("Test message 1");
    tracy.sendMessage("Test message 2");
    
    try std.testing.expectEqual(@as(u64, 2), tracy.message_count);
}

test "TracyColor 转换" {
    const red = TracyColor.red;
    try std.testing.expectEqual(@as(u32, 0xFF0000), red.toU32());
    
    const green = TracyColor.green;
    try std.testing.expectEqual(@as(u32, 0x00FF00), green.toU32());
}
