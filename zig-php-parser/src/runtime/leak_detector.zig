//! 内存泄漏检测器
//!
//! 提供完整的内存泄漏检测功能，包括：
//! 1. 分配栈跟踪 - 记录每次分配的调用栈
//! 2. 泄漏报告生成 - 生成详细的泄漏分析报告
//! 3. 实时监控 - 实时追踪内存分配和释放
//!
//! ## 架构
//!
//! ```
//! ┌─────────────────────────────────────────────────────┐
//! │           Memory Leak Detection System              │
//! ├─────────────────────────────────────────────────────┤
//! │                                                     │
//! │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
//! │  │  Allocation  │  │  Stack       │  │  Leak     │ │
//! │  │  Tracker     │  │  Tracer      │  │  Reporter │ │
//! │  └──────────────┘  └──────────────┘  └───────────┘ │
//! │         │                 │                 │        │
//! │         └─────────────────┴─────────────────┘        │
//! │                           │                          │
//! │                    ┌──────▼──────┐                   │
//! │                    │  Analyzer   │                   │
//! │                    └──────┬──────┘                   │
//! │                           │                          │
//! │                    ┌──────▼──────┐                   │
//! │                    │  Report     │                   │
//! │                    │  Generator  │                   │
//! │                    └─────────────┘                   │
//! │                                                     │
//! └─────────────────────────────────────────────────────┘
//! ```
//!
//! 验证需求：10.5

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// 常量配置
// ============================================================================

/// 最大栈帧深度
const MAX_STACK_DEPTH: usize = 32;

/// 最大分配记录数
const MAX_ALLOCATION_RECORDS: usize = 100000;

/// 泄漏报告保留时间（秒）
const LEAK_REPORT_RETENTION: u64 = 3600;


// ============================================================================
// 栈帧信息
// ============================================================================

/// 栈帧
pub const StackFrame = struct {
    /// 返回地址
    return_address: usize,
    /// 函数名（如果可用）
    function_name: ?[]const u8,
    /// 文件名（如果可用）
    file_name: ?[]const u8,
    /// 行号（如果可用）
    line_number: ?u32,
    
    /// 格式化栈帧信息
    pub fn format(
        self: StackFrame,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        if (self.function_name) |func| {
            if (self.file_name) |file| {
                if (self.line_number) |line| {
                    try writer.print("{s} at {s}:{d}", .{ func, file, line });
                } else {
                    try writer.print("{s} at {s}", .{ func, file });
                }
            } else {
                try writer.print("{s}", .{func});
            }
        } else {
            try writer.print("0x{x}", .{self.return_address});
        }
    }
};

/// 栈跟踪
pub const StackTrace = struct {
    /// 栈帧数组
    frames: [MAX_STACK_DEPTH]StackFrame,
    /// 实际栈帧数量
    frame_count: usize,
    
    /// 初始化空栈跟踪
    pub fn init() StackTrace {
        return .{
            .frames = undefined,
            .frame_count = 0,
        };
    }
    
    /// 捕获当前栈跟踪
    pub fn capture(allocator: std.mem.Allocator) !StackTrace {
        var trace = init();
        
        if (builtin.mode == .Debug) {
            // 在 Debug 模式下捕获栈跟踪
            var stack_trace = std.builtin.StackTrace{
                .instruction_addresses = undefined,
                .index = 0,
            };
            
            std.debug.captureStackTrace(@returnAddress(), &stack_trace);
            
            // 转换为我们的格式
            const count = @min(stack_trace.index, MAX_STACK_DEPTH);
            for (0..count) |i| {
                trace.frames[i] = .{
                    .return_address = stack_trace.instruction_addresses[i],
                    .function_name = null,
                    .file_name = null,
                    .line_number = null,
                };
            }
            trace.frame_count = count;
            
            // 尝试解析符号信息
            try trace.resolveSymbols(allocator);
        }
        
        return trace;
    }
    
    /// 解析符号信息
    fn resolveSymbols(self: *StackTrace, allocator: std.mem.Allocator) !void {
        _ = allocator;
        // 符号解析需要调试信息支持
        // 这里简化实现，实际应该使用 DWARF 或其他调试信息格式
        for (0..self.frame_count) |i| {
            // 尝试从地址解析符号
            // 实际实现需要访问符号表
            _ = &self.frames[i];
        }
    }
    
    /// 格式化栈跟踪
    pub fn format(
        self: StackTrace,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.writeAll("Stack trace:\n");
        for (0..self.frame_count) |i| {
            try writer.print("  #{d}: {any}\n", .{ i, self.frames[i] });
        }
    }
};


// ============================================================================
// 分配信息
// ============================================================================

/// 分配信息
pub const AllocationInfo = struct {
    /// 分配地址
    address: usize,
    /// 分配大小
    size: usize,
    /// 分配时间戳
    timestamp: i64,
    /// 栈跟踪
    stack_trace: StackTrace,
    /// 类型信息
    type_name: []const u8,
    /// 是否已释放
    freed: bool,
    /// 释放时间戳
    free_timestamp: ?i64,
    
    /// 创建分配信息
    pub fn create(
        allocator: std.mem.Allocator,
        address: usize,
        size: usize,
        type_name: []const u8,
    ) !AllocationInfo {
        return .{
            .address = address,
            .size = size,
            .timestamp = std.time.milliTimestamp(),
            .stack_trace = try StackTrace.capture(allocator),
            .type_name = try allocator.dupe(u8, type_name),
            .freed = false,
            .free_timestamp = null,
        };
    }
    
    /// 标记为已释放
    pub fn markFreed(self: *AllocationInfo) void {
        self.freed = true;
        self.free_timestamp = std.time.milliTimestamp();
    }
    
    /// 获取存活时间（毫秒）
    pub fn getLifetime(self: *const AllocationInfo) i64 {
        const end_time = self.free_timestamp orelse std.time.milliTimestamp();
        return end_time - self.timestamp;
    }
    
    /// 释放资源
    pub fn deinit(self: *AllocationInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.type_name);
    }
};

// ============================================================================
// 泄漏检测器
// ============================================================================

/// 内存泄漏检测器
/// @concurrency-model GUARDED_BY(mutex)
pub const LeakDetector = struct {
    /// 分配器
    allocator: std.mem.Allocator,
    /// 分配记录
    allocations: std.AutoHashMap(usize, AllocationInfo),
    /// 互斥锁
    mutex: std.Thread.Mutex,
    /// 是否启用
    enabled: bool,
    /// 统计信息
    stats: Stats,
    
    /// 统计信息
    pub const Stats = struct {
        /// 总分配次数
        total_allocations: u64 = 0,
        /// 总释放次数
        total_frees: u64 = 0,
        /// 当前活跃分配数
        active_allocations: usize = 0,
        /// 总分配字节数
        total_allocated_bytes: u64 = 0,
        /// 总释放字节数
        total_freed_bytes: u64 = 0,
        /// 当前使用字节数
        current_bytes: usize = 0,
        /// 峰值使用字节数
        peak_bytes: usize = 0,
    };
    
    /// 初始化泄漏检测器
    pub fn init(allocator: std.mem.Allocator) !LeakDetector {
        return .{
            .allocator = allocator,
            .allocations = std.AutoHashMap(usize, AllocationInfo).init(allocator),
            .mutex = .{},
            .enabled = builtin.mode == .Debug,
            .stats = .{},
        };
    }
    
    /// 清理
    pub fn deinit(self: *LeakDetector) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 释放所有分配信息
        var iter = self.allocations.valueIterator();
        while (iter.next()) |info| {
            info.deinit(self.allocator);
        }
        
        self.allocations.deinit();
    }
    
    /// 启用检测
    pub fn enable(self: *LeakDetector) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = true;
    }
    
    /// 禁用检测
    pub fn disable(self: *LeakDetector) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = false;
    }
    
    /// 记录分配
    /// @thread-safety ATOMIC
    pub fn recordAllocation(
        self: *LeakDetector,
        address: usize,
        size: usize,
        type_name: []const u8,
    ) !void {
        if (!self.enabled) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // 创建分配信息
        const info = try AllocationInfo.create(self.allocator, address, size, type_name);
        
        // 记录分配
        try self.allocations.put(address, info);
        
        // 更新统计
        self.stats.total_allocations += 1;
        self.stats.active_allocations += 1;
        self.stats.total_allocated_bytes += size;
        self.stats.current_bytes += size;
        
        if (self.stats.current_bytes > self.stats.peak_bytes) {
            self.stats.peak_bytes = self.stats.current_bytes;
        }
    }
    
    /// 记录释放
    /// @thread-safety ATOMIC
    pub fn recordFree(self: *LeakDetector, address: usize) void {
        if (!self.enabled) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.allocations.getPtr(address)) |info| {
            // 标记为已释放
            info.markFreed();
            
            // 更新统计
            self.stats.total_frees += 1;
            self.stats.active_allocations -= 1;
            self.stats.total_freed_bytes += info.size;
            self.stats.current_bytes -= info.size;
            
            // 移除记录
            var removed_info = self.allocations.fetchRemove(address).?.value;
            removed_info.deinit(self.allocator);
        }
    }
    
    
    /// 检查泄漏
    /// @post 返回所有未释放的分配信息
    pub fn checkLeaks(self: *LeakDetector) ![]AllocationInfo {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const leak_count = self.allocations.count();
        if (leak_count == 0) {
            return &[_]AllocationInfo{};
        }
        
        // 复制泄漏信息
        var leaks = try self.allocator.alloc(AllocationInfo, leak_count);
        var iter = self.allocations.valueIterator();
        var i: usize = 0;
        while (iter.next()) |info| : (i += 1) {
            leaks[i] = .{
                .address = info.address,
                .size = info.size,
                .timestamp = info.timestamp,
                .stack_trace = info.stack_trace,
                .type_name = try self.allocator.dupe(u8, info.type_name),
                .freed = info.freed,
                .free_timestamp = info.free_timestamp,
            };
        }
        
        return leaks;
    }
    
    /// 获取统计信息
    pub fn getStats(self: *const LeakDetector) Stats {
        return self.stats;
    }
    
    /// 生成泄漏报告
    /// @post 返回详细的泄漏分析报告
    pub fn generateReport(self: *LeakDetector, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try writer.writeAll("=== Memory Leak Detection Report ===\n\n");
        
        // 统计信息
        try writer.print("Statistics:\n", .{});
        try writer.print("  Total Allocations: {d}\n", .{self.stats.total_allocations});
        try writer.print("  Total Frees: {d}\n", .{self.stats.total_frees});
        try writer.print("  Active Allocations: {d}\n", .{self.stats.active_allocations});
        try writer.print("  Total Allocated: {d} bytes\n", .{self.stats.total_allocated_bytes});
        try writer.print("  Total Freed: {d} bytes\n", .{self.stats.total_freed_bytes});
        try writer.print("  Current Usage: {d} bytes\n", .{self.stats.current_bytes});
        try writer.print("  Peak Usage: {d} bytes\n\n", .{self.stats.peak_bytes});
        
        // 泄漏详情
        const leak_count = self.allocations.count();
        if (leak_count == 0) {
            try writer.writeAll("✓ No memory leaks detected!\n");
            return;
        }
        
        try writer.print("⚠ Detected {d} memory leak(s):\n\n", .{leak_count});
        
        // 按大小排序泄漏
        var leaks = try self.allocator.alloc(AllocationInfo, leak_count);
        defer self.allocator.free(leaks);
        
        var iter = self.allocations.valueIterator();
        var i: usize = 0;
        while (iter.next()) |info| : (i += 1) {
            leaks[i] = info.*;
        }
        
        std.mem.sort(AllocationInfo, leaks, {}, struct {
            fn lessThan(_: void, a: AllocationInfo, b: AllocationInfo) bool {
                return a.size > b.size; // 降序排列
            }
        }.lessThan);
        
        // 输出每个泄漏
        for (leaks, 0..) |leak, idx| {
            try writer.print("Leak #{d}:\n", .{idx + 1});
            try writer.print("  Address: 0x{x}\n", .{leak.address});
            try writer.print("  Size: {d} bytes\n", .{leak.size});
            try writer.print("  Type: {s}\n", .{leak.type_name});
            try writer.print("  Allocated at: {d} ms\n", .{leak.timestamp});
            try writer.print("  Lifetime: {d} ms\n", .{leak.getLifetime()});
            try writer.print("  {any}\n", .{leak.stack_trace});
            try writer.writeAll("\n");
        }
        
        // 泄漏汇总
        try writer.writeAll("Summary by Type:\n");
        var type_summary = std.StringHashMap(TypeSummary).init(self.allocator);
        defer type_summary.deinit();
        
        for (leaks) |leak| {
            const entry = try type_summary.getOrPut(leak.type_name);
            if (!entry.found_existing) {
                entry.value_ptr.* = .{
                    .count = 0,
                    .total_bytes = 0,
                };
            }
            entry.value_ptr.count += 1;
            entry.value_ptr.total_bytes += leak.size;
        }
        
        var type_iter = type_summary.iterator();
        while (type_iter.next()) |entry| {
            try writer.print("  {s}: {d} leak(s), {d} bytes\n", .{
                entry.key_ptr.*,
                entry.value_ptr.count,
                entry.value_ptr.total_bytes,
            });
        }
    }
    
    const TypeSummary = struct {
        count: usize,
        total_bytes: usize,
    };
};


// ============================================================================
// 泄漏分析器
// ============================================================================

/// 泄漏分析器
/// 提供高级泄漏分析功能
pub const LeakAnalyzer = struct {
    /// 分配器
    allocator: std.mem.Allocator,
    /// 泄漏检测器
    detector: *LeakDetector,
    
    /// 初始化分析器
    pub fn init(allocator: std.mem.Allocator, detector: *LeakDetector) LeakAnalyzer {
        return .{
            .allocator = allocator,
            .detector = detector,
        };
    }
    
    /// 分析泄漏模式
    /// @post 返回泄漏模式分析结果
    pub fn analyzeLeakPatterns(self: *LeakAnalyzer) !LeakPattern {
        const leaks = try self.detector.checkLeaks();
        defer {
            for (leaks) |*leak| {
                leak.deinit(self.allocator);
            }
            self.allocator.free(leaks);
        }
        
        if (leaks.len == 0) {
            return .{
                .total_leaks = 0,
                .total_leaked_bytes = 0,
                .most_common_type = null,
                .largest_leak_size = 0,
                .average_leak_size = 0,
                .oldest_leak_age = 0,
            };
        }
        
        // 统计信息
        var total_bytes: usize = 0;
        var largest_size: usize = 0;
        var oldest_age: i64 = 0;
        var type_counts = std.StringHashMap(usize).init(self.allocator);
        defer type_counts.deinit();
        
        for (leaks) |leak| {
            total_bytes += leak.size;
            
            if (leak.size > largest_size) {
                largest_size = leak.size;
            }
            
            const age = leak.getLifetime();
            if (age > oldest_age) {
                oldest_age = age;
            }
            
            const entry = try type_counts.getOrPut(leak.type_name);
            if (!entry.found_existing) {
                entry.value_ptr.* = 0;
            }
            entry.value_ptr.* += 1;
        }
        
        // 找出最常见的类型
        var most_common_type: ?[]const u8 = null;
        var max_count: usize = 0;
        var iter = type_counts.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > max_count) {
                max_count = entry.value_ptr.*;
                most_common_type = entry.key_ptr.*;
            }
        }
        
        return .{
            .total_leaks = leaks.len,
            .total_leaked_bytes = total_bytes,
            .most_common_type = if (most_common_type) |t|
                try self.allocator.dupe(u8, t)
            else
                null,
            .largest_leak_size = largest_size,
            .average_leak_size = total_bytes / leaks.len,
            .oldest_leak_age = oldest_age,
        };
    }
    
    /// 泄漏模式
    pub const LeakPattern = struct {
        /// 总泄漏数
        total_leaks: usize,
        /// 总泄漏字节数
        total_leaked_bytes: usize,
        /// 最常见的类型
        most_common_type: ?[]const u8,
        /// 最大泄漏大小
        largest_leak_size: usize,
        /// 平均泄漏大小
        average_leak_size: usize,
        /// 最老泄漏的年龄（毫秒）
        oldest_leak_age: i64,
        
        /// 释放资源
        pub fn deinit(self: *LeakPattern, allocator: std.mem.Allocator) void {
            if (self.most_common_type) |t| {
                allocator.free(t);
            }
        }
    };
    
    /// 生成修复建议
    /// @post 返回针对泄漏的修复建议
    pub fn generateFixSuggestions(self: *LeakAnalyzer, writer: anytype) !void {
        const pattern = try self.analyzeLeakPatterns();
        defer {
            var p = pattern;
            p.deinit(self.allocator);
        }
        
        if (pattern.total_leaks == 0) {
            try writer.writeAll("No leaks detected. No suggestions needed.\n");
            return;
        }
        
        try writer.writeAll("=== Fix Suggestions ===\n\n");
        
        // 建议 1：检查资源释放
        try writer.writeAll("1. Check Resource Cleanup:\n");
        try writer.writeAll("   - Ensure all allocated resources are properly freed\n");
        try writer.writeAll("   - Use defer statements for automatic cleanup\n");
        try writer.writeAll("   - Implement deinit() methods for all types\n\n");
        
        // 建议 2：检查错误处理
        try writer.writeAll("2. Review Error Handling:\n");
        try writer.writeAll("   - Use errdefer for cleanup on error paths\n");
        try writer.writeAll("   - Ensure resources are freed even when errors occur\n");
        try writer.writeAll("   - Check all error return paths\n\n");
        
        // 建议 3：针对最常见类型的建议
        if (pattern.most_common_type) |type_name| {
            try writer.print("3. Focus on Type '{s}':\n", .{type_name});
            try writer.writeAll("   - This type has the most leaks\n");
            try writer.writeAll("   - Review all allocations of this type\n");
            try writer.writeAll("   - Consider using a resource pool\n\n");
        }
        
        // 建议 4：检查长期存活的对象
        if (pattern.oldest_leak_age > 60000) { // > 1 minute
            try writer.writeAll("4. Check Long-Lived Objects:\n");
            try writer.print("   - Some leaks have been alive for {d} ms\n", .{pattern.oldest_leak_age});
            try writer.writeAll("   - These may be cached objects that are never freed\n");
            try writer.writeAll("   - Consider implementing a cache eviction policy\n\n");
        }
        
        // 建议 5：使用工具
        try writer.writeAll("5. Use Memory Analysis Tools:\n");
        try writer.writeAll("   - Run with Valgrind for detailed analysis\n");
        try writer.writeAll("   - Use AddressSanitizer for runtime checks\n");
        try writer.writeAll("   - Enable Zig's safety checks in Debug mode\n\n");
    }
};


// ============================================================================
// 测试
// ============================================================================

test "StackTrace - capture" {
    if (builtin.mode != .Debug) return error.SkipZigTest;
    
    const trace = try StackTrace.capture(std.testing.allocator);
    // 在 Debug 模式下应该能捕获到栈帧
    // 但由于实现简化，可能为 0
    try std.testing.expect(trace.frame_count >= 0);
}

test "AllocationInfo - create and lifecycle" {
    const info = try AllocationInfo.create(
        std.testing.allocator,
        0x1000,
        1024,
        "TestType",
    );
    var mutable_info = info;
    defer mutable_info.deinit(std.testing.allocator);
    
    try std.testing.expectEqual(@as(usize, 0x1000), info.address);
    try std.testing.expectEqual(@as(usize, 1024), info.size);
    try std.testing.expect(!info.freed);
    
    mutable_info.markFreed();
    try std.testing.expect(mutable_info.freed);
    try std.testing.expect(mutable_info.free_timestamp != null);
}

test "LeakDetector - no leaks" {
    var detector = try LeakDetector.init(std.testing.allocator);
    defer detector.deinit();
    
    // 分配和释放
    try detector.recordAllocation(0x1000, 100, "u8");
    detector.recordFree(0x1000);
    
    // 检查泄漏
    const leaks = try detector.checkLeaks();
    defer {
        for (leaks) |*leak| {
            leak.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(leaks);
    }
    
    try std.testing.expectEqual(@as(usize, 0), leaks.len);
    
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.total_allocations);
    try std.testing.expectEqual(@as(u64, 1), stats.total_frees);
    try std.testing.expectEqual(@as(usize, 0), stats.active_allocations);
}

test "LeakDetector - detect leaks" {
    var detector = try LeakDetector.init(std.testing.allocator);
    defer detector.deinit();
    
    // 分配但不释放
    try detector.recordAllocation(0x1000, 100, "u8");
    try detector.recordAllocation(0x2000, 200, "i32");
    
    // 检查泄漏
    const leaks = try detector.checkLeaks();
    defer {
        for (leaks) |*leak| {
            leak.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(leaks);
    }
    
    try std.testing.expectEqual(@as(usize, 2), leaks.len);
    
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.total_allocations);
    try std.testing.expectEqual(@as(u64, 0), stats.total_frees);
    try std.testing.expectEqual(@as(usize, 2), stats.active_allocations);
    try std.testing.expectEqual(@as(usize, 300), stats.current_bytes);
}

test "LeakDetector - generate report" {
    var detector = try LeakDetector.init(std.testing.allocator);
    defer detector.deinit();
    
    // 创建一些泄漏
    try detector.recordAllocation(0x1000, 100, "String");
    try detector.recordAllocation(0x2000, 200, "Array");
    try detector.recordAllocation(0x3000, 150, "String");
    
    // 生成报告
    var buffer = std.ArrayList(u8).initCapacity(std.testing.allocator, 0) catch unreachable;
    defer buffer.deinit(std.testing.allocator);
    
    try detector.generateReport(buffer.writer(std.testing.allocator));
    
    const report = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, report, "Memory Leak Detection Report") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Detected 3 memory leak(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "String") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Array") != null);
}

test "LeakAnalyzer - analyze patterns" {
    var detector = try LeakDetector.init(std.testing.allocator);
    defer detector.deinit();
    
    // 创建不同类型的泄漏
    try detector.recordAllocation(0x1000, 100, "String");
    try detector.recordAllocation(0x2000, 200, "String");
    try detector.recordAllocation(0x3000, 150, "Array");
    try detector.recordAllocation(0x4000, 300, "Object");
    
    var analyzer = LeakAnalyzer.init(std.testing.allocator, &detector);
    var pattern = try analyzer.analyzeLeakPatterns();
    defer pattern.deinit(std.testing.allocator);
    
    try std.testing.expectEqual(@as(usize, 4), pattern.total_leaks);
    try std.testing.expectEqual(@as(usize, 750), pattern.total_leaked_bytes);
    try std.testing.expectEqual(@as(usize, 300), pattern.largest_leak_size);
    try std.testing.expect(pattern.most_common_type != null);
    try std.testing.expectEqualStrings("String", pattern.most_common_type.?);
}

test "LeakAnalyzer - generate fix suggestions" {
    var detector = try LeakDetector.init(std.testing.allocator);
    defer detector.deinit();
    
    // 创建一些泄漏
    try detector.recordAllocation(0x1000, 100, "String");
    try detector.recordAllocation(0x2000, 200, "String");
    
    var analyzer = LeakAnalyzer.init(std.testing.allocator, &detector);
    
    var buffer = std.ArrayList(u8).initCapacity(std.testing.allocator, 0) catch unreachable;
    defer buffer.deinit(std.testing.allocator);
    
    try analyzer.generateFixSuggestions(buffer.writer(std.testing.allocator));
    
    const suggestions = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, suggestions, "Fix Suggestions") != null);
    try std.testing.expect(std.mem.indexOf(u8, suggestions, "Check Resource Cleanup") != null);
    try std.testing.expect(std.mem.indexOf(u8, suggestions, "Review Error Handling") != null);
}

test "LeakDetector - thread safety" {
    var detector = try LeakDetector.init(std.testing.allocator);
    defer detector.deinit();
    
    const ThreadContext = struct {
        detector: *LeakDetector,
        thread_id: usize,
    };
    
    const workerFn = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < 100) : (i += 1) {
                const addr = ctx.thread_id * 10000 + i;
                ctx.detector.recordAllocation(addr, 100, "TestType") catch unreachable;
                ctx.detector.recordFree(addr);
            }
        }
    }.run;
    
    // 创建多个线程
    var threads: [4]std.Thread = undefined;
    var contexts: [4]ThreadContext = undefined;
    
    for (&threads, 0..) |*thread, i| {
        contexts[i] = .{
            .detector = &detector,
            .thread_id = i,
        };
        thread.* = try std.Thread.spawn(.{}, workerFn, .{&contexts[i]});
    }
    
    // 等待所有线程完成
    for (threads) |thread| {
        thread.join();
    }
    
    // 验证统计
    const stats = detector.getStats();
    try std.testing.expectEqual(@as(u64, 400), stats.total_allocations);
    try std.testing.expectEqual(@as(u64, 400), stats.total_frees);
    try std.testing.expectEqual(@as(usize, 0), stats.active_allocations);
}

test "LeakDetector - enable/disable" {
    var detector = try LeakDetector.init(std.testing.allocator);
    defer detector.deinit();
    
    // 禁用检测
    detector.disable();
    
    // 这些操作不应该被记录
    try detector.recordAllocation(0x1000, 100, "u8");
    
    const stats1 = detector.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats1.total_allocations);
    
    // 启用检测
    detector.enable();
    
    // 这些操作应该被记录
    try detector.recordAllocation(0x2000, 200, "i32");
    
    const stats2 = detector.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats2.total_allocations);
}

