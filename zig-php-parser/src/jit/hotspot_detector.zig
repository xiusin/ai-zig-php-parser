/// 热点检测器
/// 
/// 负责检测频繁执行的函数和循环，触发 JIT 编译
/// 
/// @concurrency-model ATOMIC
/// @thread-safety 所有计数器使用原子操作
/// @memory-safety 使用显式 Allocator，所有权清晰
const std = @import("std");

/// 热点检测器配置
pub const HotspotConfig = struct {
    /// 函数热点阈值（执行次数）
    function_threshold: u32 = 1000,
    
    /// 循环回边热点阈值
    loop_backedge_threshold: u32 = 10000,
    
    /// 是否启用热点检测
    enabled: bool = true,
    
    /// 是否启用循环回边检测
    loop_detection_enabled: bool = true,
};

/// 热点检测器
/// 
/// 使用原子计数器跟踪函数执行和循环回边，
/// 当计数达到阈值时标记为热点
/// 
/// @ownership NON-OWNING (allocator)
/// @concurrency-model ATOMIC
pub const HotspotDetector = struct {
    allocator: std.mem.Allocator,
    
    /// 函数执行计数器（原子操作）
    /// Key: 函数名, Value: 执行次数
    execution_counts: std.StringHashMap(std.atomic.Value(u32)),
    
    /// 循环回边计数器（原子操作）
    /// Key: 循环 ID (函数名:字节码偏移), Value: 回边次数
    loop_backedge_counts: std.StringHashMap(std.atomic.Value(u32)),
    
    /// 热点函数集合（已触发 JIT 编译）
    hotspot_functions: std.StringHashMap(void),
    
    /// 热点循环集合（已触发 OSR）
    hotspot_loops: std.StringHashMap(void),
    
    /// 配置
    config: HotspotConfig,
    
    /// 互斥锁（保护哈希表结构修改）
    mutex: std.Thread.Mutex,
    
    /// 统计信息
    stats: Stats,
    
    /// 统计信息
    pub const Stats = struct {
        total_function_calls: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_loop_backedges: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        hotspot_functions_detected: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        hotspot_loops_detected: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    };
    
    /// 初始化热点检测器
    /// 
    /// @pre allocator 必须有效
    /// @post 返回初始化的检测器实例
    /// @ownership TRANSFER
    pub fn init(allocator: std.mem.Allocator) !*HotspotDetector {
        return initWithConfig(allocator, HotspotConfig{});
    }
    
    /// 使用自定义配置初始化热点检测器
    /// 
    /// @pre allocator 必须有效
    /// @post 返回初始化的检测器实例
    /// @ownership TRANSFER
    pub fn initWithConfig(allocator: std.mem.Allocator, config: HotspotConfig) !*HotspotDetector {
        const detector = try allocator.create(HotspotDetector);
        errdefer allocator.destroy(detector);
        
        detector.* = HotspotDetector{
            .allocator = allocator,
            .execution_counts = std.StringHashMap(std.atomic.Value(u32)).init(allocator),
            .loop_backedge_counts = std.StringHashMap(std.atomic.Value(u32)).init(allocator),
            .hotspot_functions = std.StringHashMap(void).init(allocator),
            .hotspot_loops = std.StringHashMap(void).init(allocator),
            .config = config,
            .mutex = .{},
            .stats = .{},
        };
        
        return detector;
    }
    
    /// 释放热点检测器
    /// 
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *HotspotDetector) void {
        // 释放所有字符串键
        var exec_iter = self.execution_counts.keyIterator();
        while (exec_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        
        var loop_iter = self.loop_backedge_counts.keyIterator();
        while (loop_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        
        var hotspot_func_iter = self.hotspot_functions.keyIterator();
        while (hotspot_func_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        
        var hotspot_loop_iter = self.hotspot_loops.keyIterator();
        while (hotspot_loop_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        
        self.execution_counts.deinit();
        self.loop_backedge_counts.deinit();
        self.hotspot_functions.deinit();
        self.hotspot_loops.deinit();
        
        self.allocator.destroy(self);
    }
    
    /// 记录函数执行
    /// 
    /// 每次函数被调用时调用此方法，增加执行计数
    /// 
    /// @pre func_name 必须有效
    /// @post 函数执行计数增加 1
    /// @thread-safety ATOMIC
    pub fn recordExecution(self: *HotspotDetector, func_name: []const u8) !void {
        if (!self.config.enabled) return;
        
        // 增加总调用计数
        _ = self.stats.total_function_calls.fetchAdd(1, .monotonic);
        
        // 获取或创建计数器
        self.mutex.lock();
        const entry = try self.execution_counts.getOrPut(func_name);
        if (!entry.found_existing) {
            // 新函数 - 复制名称并初始化计数器
            const name_copy = try self.allocator.dupe(u8, func_name);
            errdefer self.allocator.free(name_copy);
            
            entry.key_ptr.* = name_copy;
            entry.value_ptr.* = std.atomic.Value(u32).init(0);
        }
        self.mutex.unlock();
        
        // 原子增加计数
        _ = entry.value_ptr.fetchAdd(1, .monotonic);
    }
    
    /// 记录循环回边
    /// 
    /// 每次循环回边（向后跳转）时调用此方法
    /// 
    /// @pre func_name 必须有效
    /// @pre bytecode_offset 必须是有效的字节码偏移
    /// @post 循环回边计数增加 1
    /// @thread-safety ATOMIC
    pub fn recordLoopBackedge(
        self: *HotspotDetector,
        func_name: []const u8,
        bytecode_offset: usize
    ) !void {
        if (!self.config.enabled or !self.config.loop_detection_enabled) return;
        
        // 增加总回边计数
        _ = self.stats.total_loop_backedges.fetchAdd(1, .monotonic);
        
        // 生成循环 ID: "函数名:偏移"
        const loop_id = try std.fmt.allocPrint(
            self.allocator,
            "{s}:{d}",
            .{ func_name, bytecode_offset }
        );
        defer self.allocator.free(loop_id);
        
        // 获取或创建计数器
        self.mutex.lock();
        const entry = try self.loop_backedge_counts.getOrPut(loop_id);
        if (!entry.found_existing) {
            // 新循环 - 复制 ID 并初始化计数器
            const id_copy = try self.allocator.dupe(u8, loop_id);
            errdefer self.allocator.free(id_copy);
            
            entry.key_ptr.* = id_copy;
            entry.value_ptr.* = std.atomic.Value(u32).init(0);
        }
        self.mutex.unlock();
        
        // 原子增加计数
        _ = entry.value_ptr.fetchAdd(1, .monotonic);
    }
    
    /// 检查函数是否为热点
    /// 
    /// @pre func_name 必须有效
    /// @post 返回函数是否达到热点阈值
    /// @thread-safety ATOMIC
    pub fn isHotspot(self: *HotspotDetector, func_name: []const u8) bool {
        if (!self.config.enabled) return false;
        
        // 检查是否已经是热点
        self.mutex.lock();
        const already_hotspot = self.hotspot_functions.contains(func_name);
        self.mutex.unlock();
        
        if (already_hotspot) return true;
        
        // 检查执行计数
        self.mutex.lock();
        const entry = self.execution_counts.get(func_name);
        self.mutex.unlock();
        
        if (entry) |counter| {
            const count = counter.load(.monotonic);
            if (count >= self.config.function_threshold) {
                // 标记为热点
                self.markAsHotspot(func_name) catch return false;
                return true;
            }
        }
        
        return false;
    }
    
    /// 检查循环是否为热点
    /// 
    /// @pre func_name 必须有效
    /// @pre bytecode_offset 必须是有效的字节码偏移
    /// @post 返回循环是否达到热点阈值
    /// @thread-safety ATOMIC
    pub fn isLoopHotspot(
        self: *HotspotDetector,
        func_name: []const u8,
        bytecode_offset: usize
    ) bool {
        if (!self.config.enabled or !self.config.loop_detection_enabled) return false;
        
        // 生成循环 ID
        const loop_id = std.fmt.allocPrint(
            self.allocator,
            "{s}:{d}",
            .{ func_name, bytecode_offset }
        ) catch return false;
        defer self.allocator.free(loop_id);
        
        // 检查是否已经是热点
        self.mutex.lock();
        const already_hotspot = self.hotspot_loops.contains(loop_id);
        self.mutex.unlock();
        
        if (already_hotspot) return true;
        
        // 检查回边计数
        self.mutex.lock();
        const entry = self.loop_backedge_counts.get(loop_id);
        self.mutex.unlock();
        
        if (entry) |counter| {
            const count = counter.load(.monotonic);
            if (count >= self.config.loop_backedge_threshold) {
                // 标记为热点
                self.markLoopAsHotspot(func_name, bytecode_offset) catch return false;
                return true;
            }
        }
        
        return false;
    }
    
    /// 获取函数执行次数
    /// 
    /// @pre func_name 必须有效
    /// @post 返回函数的执行次数
    /// @thread-safety ATOMIC
    pub fn getExecutionCount(self: *HotspotDetector, func_name: []const u8) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.execution_counts.get(func_name)) |counter| {
            return counter.load(.monotonic);
        }
        return 0;
    }
    
    /// 获取循环回边次数
    /// 
    /// @pre func_name 必须有效
    /// @pre bytecode_offset 必须是有效的字节码偏移
    /// @post 返回循环的回边次数
    /// @thread-safety ATOMIC
    pub fn getLoopBackedgeCount(
        self: *HotspotDetector,
        func_name: []const u8,
        bytecode_offset: usize
    ) u32 {
        const loop_id = std.fmt.allocPrint(
            self.allocator,
            "{s}:{d}",
            .{ func_name, bytecode_offset }
        ) catch return 0;
        defer self.allocator.free(loop_id);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.loop_backedge_counts.get(loop_id)) |counter| {
            return counter.load(.monotonic);
        }
        return 0;
    }
    
    /// 重置所有计数器
    /// 
    /// @post 所有计数器归零，热点标记清除
    pub fn reset(self: *HotspotDetector) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 重置执行计数
        var exec_iter = self.execution_counts.valueIterator();
        while (exec_iter.next()) |counter| {
            counter.store(0, .monotonic);
        }
        
        // 重置循环回边计数
        var loop_iter = self.loop_backedge_counts.valueIterator();
        while (loop_iter.next()) |counter| {
            counter.store(0, .monotonic);
        }
        
        // 清除热点标记
        var hotspot_func_iter = self.hotspot_functions.keyIterator();
        while (hotspot_func_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.hotspot_functions.clearRetainingCapacity();
        
        var hotspot_loop_iter = self.hotspot_loops.keyIterator();
        while (hotspot_loop_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.hotspot_loops.clearRetainingCapacity();
        
        // 重置统计
        self.stats.total_function_calls.store(0, .monotonic);
        self.stats.total_loop_backedges.store(0, .monotonic);
        self.stats.hotspot_functions_detected.store(0, .monotonic);
        self.stats.hotspot_loops_detected.store(0, .monotonic);
    }
    
    /// 获取统计信息快照
    /// 
    /// @post 返回当前统计信息的副本
    pub fn getStats(self: *HotspotDetector) StatsSnapshot {
        return StatsSnapshot{
            .total_function_calls = self.stats.total_function_calls.load(.monotonic),
            .total_loop_backedges = self.stats.total_loop_backedges.load(.monotonic),
            .hotspot_functions_detected = self.stats.hotspot_functions_detected.load(.monotonic),
            .hotspot_loops_detected = self.stats.hotspot_loops_detected.load(.monotonic),
            .unique_functions_tracked = @intCast(self.execution_counts.count()),
            .unique_loops_tracked = @intCast(self.loop_backedge_counts.count()),
        };
    }
    
    /// 统计信息快照
    pub const StatsSnapshot = struct {
        total_function_calls: u64,
        total_loop_backedges: u64,
        hotspot_functions_detected: u32,
        hotspot_loops_detected: u32,
        unique_functions_tracked: u32,
        unique_loops_tracked: u32,
    };
    
    /// 打印统计报告
    /// 
    /// @post 输出详细的统计信息到 stderr
    pub fn printStats(self: *HotspotDetector) void {
        const stats = self.getStats();
        
        std.debug.print("\n=== 热点检测器统计 ===\n", .{});
        std.debug.print("总函数调用次数: {d}\n", .{stats.total_function_calls});
        std.debug.print("总循环回边次数: {d}\n", .{stats.total_loop_backedges});
        std.debug.print("检测到的热点函数: {d}\n", .{stats.hotspot_functions_detected});
        std.debug.print("检测到的热点循环: {d}\n", .{stats.hotspot_loops_detected});
        std.debug.print("跟踪的唯一函数: {d}\n", .{stats.unique_functions_tracked});
        std.debug.print("跟踪的唯一循环: {d}\n", .{stats.unique_loops_tracked});
        std.debug.print("\n配置:\n", .{});
        std.debug.print("  函数热点阈值: {d}\n", .{self.config.function_threshold});
        std.debug.print("  循环热点阈值: {d}\n", .{self.config.loop_backedge_threshold});
        std.debug.print("  热点检测: {s}\n", .{if (self.config.enabled) "启用" else "禁用"});
        std.debug.print("  循环检测: {s}\n", .{if (self.config.loop_detection_enabled) "启用" else "禁用"});
        
        // 打印前 10 个最热的函数
        std.debug.print("\n前 10 个最热函数:\n", .{});
        self.printTopFunctions(10);
        
        // 打印前 10 个最热的循环
        std.debug.print("\n前 10 个最热循环:\n", .{});
        self.printTopLoops(10);
    }
    
    /// 打印执行次数最多的函数
    fn printTopFunctions(self: *HotspotDetector, count: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 收集所有函数及其计数
        var functions = std.ArrayList(struct { name: []const u8, count: u32 }).init(self.allocator);
        defer functions.deinit();
        
        var iter = self.execution_counts.iterator();
        while (iter.next()) |entry| {
            functions.append(.{
                .name = entry.key_ptr.*,
                .count = entry.value_ptr.load(.monotonic),
            }) catch continue;
        }
        
        // 按计数排序
        std.sort.pdq(
            @TypeOf(functions.items[0]),
            functions.items,
            {},
            struct {
                fn lessThan(_: void, a: @TypeOf(functions.items[0]), b: @TypeOf(functions.items[0])) bool {
                    return a.count > b.count;
                }
            }.lessThan
        );
        
        // 打印前 N 个
        const n = @min(count, functions.items.len);
        for (functions.items[0..n], 0..) |func, i| {
            const is_hotspot = self.hotspot_functions.contains(func.name);
            std.debug.print("  {d}. {s}: {d} 次 {s}\n", .{
                i + 1,
                func.name,
                func.count,
                if (is_hotspot) "[热点]" else "",
            });
        }
    }
    
    /// 打印回边次数最多的循环
    fn printTopLoops(self: *HotspotDetector, count: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 收集所有循环及其计数
        var loops = std.ArrayList(struct { id: []const u8, count: u32 }).init(self.allocator);
        defer loops.deinit();
        
        var iter = self.loop_backedge_counts.iterator();
        while (iter.next()) |entry| {
            loops.append(.{
                .id = entry.key_ptr.*,
                .count = entry.value_ptr.load(.monotonic),
            }) catch continue;
        }
        
        // 按计数排序
        std.sort.pdq(
            @TypeOf(loops.items[0]),
            loops.items,
            {},
            struct {
                fn lessThan(_: void, a: @TypeOf(loops.items[0]), b: @TypeOf(loops.items[0])) bool {
                    return a.count > b.count;
                }
            }.lessThan
        );
        
        // 打印前 N 个
        const n = @min(count, loops.items.len);
        for (loops.items[0..n], 0..) |loop, i| {
            const is_hotspot = self.hotspot_loops.contains(loop.id);
            std.debug.print("  {d}. {s}: {d} 次 {s}\n", .{
                i + 1,
                loop.id,
                loop.count,
                if (is_hotspot) "[热点]" else "",
            });
        }
    }
    
    // ========== 私有辅助方法 ==========
    
    /// 标记函数为热点
    fn markAsHotspot(self: *HotspotDetector, func_name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (!self.hotspot_functions.contains(func_name)) {
            const name_copy = try self.allocator.dupe(u8, func_name);
            try self.hotspot_functions.put(name_copy, {});
            _ = self.stats.hotspot_functions_detected.fetchAdd(1, .monotonic);
        }
    }
    
    /// 标记循环为热点
    fn markLoopAsHotspot(
        self: *HotspotDetector,
        func_name: []const u8,
        bytecode_offset: usize
    ) !void {
        const loop_id = try std.fmt.allocPrint(
            self.allocator,
            "{s}:{d}",
            .{ func_name, bytecode_offset }
        );
        errdefer self.allocator.free(loop_id);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (!self.hotspot_loops.contains(loop_id)) {
            try self.hotspot_loops.put(loop_id, {});
            _ = self.stats.hotspot_loops_detected.fetchAdd(1, .monotonic);
        } else {
            self.allocator.free(loop_id);
        }
    }
};

// ========== 测试 ==========

test "HotspotDetector: 基本初始化和释放" {
    const allocator = std.testing.allocator;
    
    const detector = try HotspotDetector.init(allocator);
    defer detector.deinit();
    
    try std.testing.expect(detector.config.enabled);
    try std.testing.expectEqual(@as(u32, 1000), detector.config.function_threshold);
}

test "HotspotDetector: 记录函数执行" {
    const allocator = std.testing.allocator;
    
    const detector = try HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 记录执行
    try detector.recordExecution("test_func");
    try detector.recordExecution("test_func");
    try detector.recordExecution("test_func");
    
    // 验证计数
    const count = detector.getExecutionCount("test_func");
    try std.testing.expectEqual(@as(u32, 3), count);
}

test "HotspotDetector: 热点检测" {
    const allocator = std.testing.allocator;
    
    var config = HotspotConfig{};
    config.function_threshold = 5; // 降低阈值以便测试
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    // 未达到阈值
    try detector.recordExecution("test_func");
    try std.testing.expect(!detector.isHotspot("test_func"));
    
    // 达到阈值
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        try detector.recordExecution("test_func");
    }
    
    try std.testing.expect(detector.isHotspot("test_func"));
}

test "HotspotDetector: 循环回边检测" {
    const allocator = std.testing.allocator;
    
    var config = HotspotConfig{};
    config.loop_backedge_threshold = 10; // 降低阈值以便测试
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    // 记录回边
    var i: u32 = 0;
    while (i < 15) : (i += 1) {
        try detector.recordLoopBackedge("test_func", 100);
    }
    
    // 验证热点
    try std.testing.expect(detector.isLoopHotspot("test_func", 100));
    
    // 验证计数
    const count = detector.getLoopBackedgeCount("test_func", 100);
    try std.testing.expectEqual(@as(u32, 15), count);
}

test "HotspotDetector: 统计信息" {
    const allocator = std.testing.allocator;
    
    var config = HotspotConfig{};
    config.function_threshold = 3;
    
    const detector = try HotspotDetector.initWithConfig(allocator, config);
    defer detector.deinit();
    
    // 记录多个函数
    try detector.recordExecution("func1");
    try detector.recordExecution("func1");
    try detector.recordExecution("func1");
    try detector.recordExecution("func1");
    
    try detector.recordExecution("func2");
    try detector.recordExecution("func2");
    
    // 触发热点检测
    _ = detector.isHotspot("func1");
    
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 6), stats.total_function_calls);
    try std.testing.expectEqual(@as(u32, 2), stats.unique_functions_tracked);
    try std.testing.expectEqual(@as(u32, 1), stats.hotspot_functions_detected);
}

test "HotspotDetector: 重置" {
    const allocator = std.testing.allocator;
    
    const detector = try HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 记录一些数据
    try detector.recordExecution("test_func");
    try detector.recordExecution("test_func");
    
    // 重置
    detector.reset();
    
    // 验证计数归零
    const count = detector.getExecutionCount("test_func");
    try std.testing.expectEqual(@as(u32, 0), count);
    
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.total_function_calls);
}

test "HotspotDetector: 并发安全" {
    const allocator = std.testing.allocator;
    
    const detector = try HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 创建多个线程同时记录
    const ThreadContext = struct {
        detector: *HotspotDetector,
        thread_id: u32,
    };
    
    const thread_fn = struct {
        fn run(ctx: ThreadContext) void {
            var i: u32 = 0;
            while (i < 100) : (i += 1) {
                const func_name = std.fmt.allocPrint(
                    ctx.detector.allocator,
                    "func_{d}",
                    .{ctx.thread_id}
                ) catch return;
                defer ctx.detector.allocator.free(func_name);
                
                ctx.detector.recordExecution(func_name) catch return;
            }
        }
    }.run;
    
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, thread_fn, .{ThreadContext{
            .detector = detector,
            .thread_id = @intCast(i),
        }});
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    // 验证统计
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 400), stats.total_function_calls);
}
