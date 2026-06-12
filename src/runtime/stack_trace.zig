/// 统一的错误堆栈跟踪系统
/// 
/// 支持解释执行、JIT 编译和 AOT 编译代码的堆栈跟踪
/// 
/// @ownership NON-OWNING (allocator)
/// @thread-safety GUARDED_BY(mutex)
/// @验证：需求 10.3

const std = @import("std");

/// 堆栈帧类型
pub const FrameType = enum {
    /// 解释执行帧
    interpreted,
    
    /// JIT 编译帧
    jit_compiled,
    
    /// AOT 编译帧
    aot_compiled,
    
    /// 原生 C 函数帧
    native,
    
    /// 内联函数帧
    inlined,
};

/// 堆栈帧信息
/// @memory-layout 紧凑布局以优化缓存
pub const StackFrame = struct {
    /// 帧类型
    frame_type: FrameType,
    
    /// 函数名
    function_name: []const u8,
    
    /// 文件路径
    file_path: []const u8,
    
    /// 行号（从 1 开始）
    line: u32,
    
    /// 列号（从 1 开始）
    column: u32,
    
    /// 类名（如果是方法调用）
    class_name: ?[]const u8,
    
    /// 指令指针（机器码地址或字节码 IP）
    instruction_pointer: usize,
    
    /// 帧指针（栈帧基址）
    frame_pointer: usize,
    
    /// 返回地址
    return_address: usize,
    
    /// 局部变量数量
    local_count: u16,
    
    /// 参数数量
    param_count: u16,
    
    /// 创建堆栈帧
    pub fn init(
        frame_type: FrameType,
        function_name: []const u8,
        file_path: []const u8,
        line: u32,
        column: u32,
    ) StackFrame {
        return .{
            .frame_type = frame_type,
            .function_name = function_name,
            .file_path = file_path,
            .line = line,
            .column = column,
            .class_name = null,
            .instruction_pointer = 0,
            .frame_pointer = 0,
            .return_address = 0,
            .local_count = 0,
            .param_count = 0,
        };
    }
    
    /// 设置类名
    pub fn withClassName(self: StackFrame, class_name: []const u8) StackFrame {
        var frame = self;
        frame.class_name = class_name;
        return frame;
    }
    
    /// 设置指令指针
    pub fn withInstructionPointer(self: StackFrame, ip: usize) StackFrame {
        var frame = self;
        frame.instruction_pointer = ip;
        return frame;
    }
    
    /// 设置帧指针
    pub fn withFramePointer(self: StackFrame, fp: usize) StackFrame {
        var frame = self;
        frame.frame_pointer = fp;
        return frame;
    }
    
    /// 设置返回地址
    pub fn withReturnAddress(self: StackFrame, ra: usize) StackFrame {
        var frame = self;
        frame.return_address = ra;
        return frame;
    }
    
    /// 设置局部变量和参数数量
    pub fn withCounts(self: StackFrame, locals: u16, params: u16) StackFrame {
        var frame = self;
        frame.local_count = locals;
        frame.param_count = params;
        return frame;
    }
    
    /// 格式化输出
    pub fn format(
        self: StackFrame,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        // 输出帧类型标记
        const type_marker = switch (self.frame_type) {
            .interpreted => "[INT]",
            .jit_compiled => "[JIT]",
            .aot_compiled => "[AOT]",
            .native => "[NAT]",
            .inlined => "[INL]",
        };
        
        try writer.writeAll(type_marker);
        try writer.writeAll(" ");
        
        // 输出函数名
        if (self.class_name) |class_name| {
            try writer.print("{s}::{s}", .{ class_name, self.function_name });
        } else {
            try writer.writeAll(self.function_name);
        }
        
        // 输出位置信息
        try writer.print(" at {s}:{d}:{d}", .{
            self.file_path,
            self.line,
            self.column,
        });
        
        // 输出地址信息（如果有）
        if (self.instruction_pointer != 0) {
            try writer.print(" (IP: 0x{X:0>16})", .{self.instruction_pointer});
        }
    }
};

/// 堆栈跟踪
/// @ownership TRANSFER
pub const StackTrace = struct {
    allocator: std.mem.Allocator,
    
    /// 堆栈帧列表（从最内层到最外层）
    frames: std.ArrayListUnmanaged(StackFrame),
    
    /// 捕获时间戳
    timestamp: i64,
    
    /// 线程 ID
    thread_id: std.Thread.Id,
    
    /// 初始化堆栈跟踪
    pub fn init(allocator: std.mem.Allocator) StackTrace {
        return .{
            .allocator = allocator,
            .frames = .{},
            .timestamp = std.time.milliTimestamp(),
            .thread_id = std.Thread.getCurrentId(),
        };
    }
    
    /// 清理资源
    pub fn deinit(self: *StackTrace) void {
        self.frames.deinit(self.allocator);
    }
    
    /// 添加堆栈帧
    pub fn pushFrame(self: *StackTrace, frame: StackFrame) !void {
        try self.frames.append(self.allocator, frame);
    }
    
    /// 获取帧数量
    pub fn depth(self: *const StackTrace) usize {
        return self.frames.items.len;
    }
    
    /// 获取指定深度的帧
    pub fn getFrame(self: *const StackTrace, index: usize) ?StackFrame {
        if (index >= self.frames.items.len) return null;
        return self.frames.items[index];
    }
    
    /// 格式化输出
    pub fn format(
        self: StackTrace,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.writeAll("Stack trace:\n");
        try writer.print("  Thread: {d}\n", .{self.thread_id});
        try writer.print("  Timestamp: {d}\n", .{self.timestamp});
        try writer.print("  Depth: {d}\n\n", .{self.frames.items.len});
        
        for (self.frames.items, 0..) |frame, i| {
            try writer.print("  #{d}: ", .{i});
            try frame.format("", .{}, writer);
            try writer.writeAll("\n");
        }
    }
    
    /// 转换为字符串
    pub fn toString(self: *const StackTrace) ![]u8 {
        // 使用 ArrayListUnmanaged 来避免 ArrayList API 问题
        var list: std.ArrayListUnmanaged(u8) = .{};
        errdefer list.deinit(self.allocator);
        
        try self.format("", .{}, list.writer(self.allocator));
        return try list.toOwnedSlice(self.allocator);
    }
};

/// 堆栈跟踪捕获器
/// @concurrency-model GUARDED_BY(mutex)
pub const StackTraceCapture = struct {
    allocator: std.mem.Allocator,
    
    /// JIT 调试信息管理器（可选）
    jit_debug_info: ?*anyopaque,
    
    /// AOT 调试信息管理器（可选）
    aot_debug_info: ?*anyopaque,
    
    /// 最大捕获深度
    max_depth: usize,
    
    /// 互斥锁
    mutex: std.Thread.Mutex,
    
    /// 统计信息
    stats: Stats,
    
    pub const Stats = struct {
        /// 捕获次数
        capture_count: usize = 0,
        
        /// 捕获的总帧数
        total_frames: usize = 0,
        
        /// 平均帧数
        pub fn averageDepth(self: Stats) f64 {
            if (self.capture_count == 0) return 0.0;
            return @as(f64, @floatFromInt(self.total_frames)) / 
                   @as(f64, @floatFromInt(self.capture_count));
        }
    };
    
    /// 初始化捕获器
    pub fn init(allocator: std.mem.Allocator, max_depth: usize) StackTraceCapture {
        return .{
            .allocator = allocator,
            .jit_debug_info = null,
            .aot_debug_info = null,
            .max_depth = max_depth,
            .mutex = .{},
            .stats = .{},
        };
    }
    
    /// 设置 JIT 调试信息
    pub fn setJitDebugInfo(self: *StackTraceCapture, debug_info: *anyopaque) void {
        self.jit_debug_info = debug_info;
    }
    
    /// 设置 AOT 调试信息
    pub fn setAotDebugInfo(self: *StackTraceCapture, debug_info: *anyopaque) void {
        self.aot_debug_info = debug_info;
    }
    
    /// 捕获当前堆栈跟踪
    /// @pre 必须在有效的执行上下文中调用
    /// @post 返回完整的堆栈跟踪
    pub fn capture(self: *StackTraceCapture) !StackTrace {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var trace = StackTrace.init(self.allocator);
        errdefer trace.deinit();
        
        // 捕获原生堆栈
        try self.captureNativeStack(&trace);
        
        // 更新统计
        self.stats.capture_count += 1;
        self.stats.total_frames += trace.depth();
        
        return trace;
    }
    
    /// 从返回地址列表捕获堆栈跟踪
    /// @pre addresses 必须是有效的返回地址数组
    /// @post 返回解析后的堆栈跟踪
    pub fn captureFromAddresses(
        self: *StackTraceCapture,
        addresses: []const usize,
    ) !StackTrace {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var trace = StackTrace.init(self.allocator);
        errdefer trace.deinit();
        
        for (addresses) |address| {
            if (trace.depth() >= self.max_depth) break;
            
            // 尝试解析地址
            if (try self.resolveAddress(address)) |frame| {
                try trace.pushFrame(frame);
            } else {
                // 无法解析，创建未知帧
                const unknown_frame = StackFrame.init(
                    .native,
                    "<unknown>",
                    "<unknown>",
                    0,
                    0,
                ).withInstructionPointer(address);
                
                try trace.pushFrame(unknown_frame);
            }
        }
        
        // 更新统计
        self.stats.capture_count += 1;
        self.stats.total_frames += trace.depth();
        
        return trace;
    }
    
    /// 捕获原生堆栈
    fn captureNativeStack(self: *StackTraceCapture, trace: *StackTrace) !void {
        // 使用 Zig 的内置堆栈跟踪功能
        var stack_trace_buf: [64]usize = undefined;
        const stack_trace = std.debug.captureStackTrace(@returnAddress(), &stack_trace_buf);
        
        for (stack_trace) |address| {
            if (trace.depth() >= self.max_depth) break;
            
            if (try self.resolveAddress(address)) |frame| {
                try trace.pushFrame(frame);
            }
        }
    }
    
    /// 解析地址到堆栈帧
    fn resolveAddress(self: *StackTraceCapture, address: usize) !?StackFrame {
        // 首先尝试 JIT 调试信息
        if (self.jit_debug_info) |jit_info| {
            if (try self.resolveJitAddress(jit_info, address)) |frame| {
                return frame;
            }
        }
        
        // 然后尝试 AOT 调试信息
        if (self.aot_debug_info) |aot_info| {
            if (try self.resolveAotAddress(aot_info, address)) |frame| {
                return frame;
            }
        }
        
        // 最后尝试原生符号解析
        return try self.resolveNativeAddress(address);
    }
    
    /// 解析 JIT 地址
    fn resolveJitAddress(
        self: *StackTraceCapture,
        jit_info: *anyopaque,
        address: usize,
    ) !?StackFrame {
        _ = self;
        _ = jit_info;
        _ = address;
        
        // TODO: 实现 JIT 地址解析
        // 这需要访问 JIT 调试信息管理器
        return null;
    }
    
    /// 解析 AOT 地址
    fn resolveAotAddress(
        self: *StackTraceCapture,
        aot_info: *anyopaque,
        address: usize,
    ) !?StackFrame {
        _ = self;
        _ = aot_info;
        _ = address;
        
        // TODO: 实现 AOT 地址解析
        // 这需要访问 AOT 调试信息（DWARF）
        return null;
    }
    
    /// 解析原生地址
    fn resolveNativeAddress(self: *StackTraceCapture, address: usize) !?StackFrame {
        // 尝试使用 Zig 的符号解析
        var debug_info = std.debug.getSelfDebugInfo() catch return null;
        
        const module = debug_info.getModuleForAddress(address) catch return null;
        const symbol_info = module.getSymbolAtAddress(self.allocator, address) catch return null;
        
        // 简化版本：只返回基本信息
        return StackFrame.init(
            .native,
            symbol_info.name,
            "<native>",
            0,
            0,
        ).withInstructionPointer(address);
    }
    
    /// 打印统计信息
    pub fn printStats(self: *StackTraceCapture, writer: anytype) !void {
        try writer.writeAll("\n=== Stack Trace Capture Statistics ===\n");
        try writer.print("Capture count: {d}\n", .{self.stats.capture_count});
        try writer.print("Total frames: {d}\n", .{self.stats.total_frames});
        try writer.print("Average depth: {d:.2}\n", .{self.stats.averageDepth()});
    }
};

/// 全局堆栈跟踪捕获器
var global_capture: ?*StackTraceCapture = null;
var global_capture_mutex: std.Thread.Mutex = .{};

/// 初始化全局捕获器
/// @pre allocator 必须有效
/// @post 全局捕获器被初始化
pub fn initGlobalCapture(allocator: std.mem.Allocator, max_depth: usize) !void {
    global_capture_mutex.lock();
    defer global_capture_mutex.unlock();
    
    if (global_capture != null) {
        return error.AlreadyInitialized;
    }
    
    const capture = try allocator.create(StackTraceCapture);
    capture.* = StackTraceCapture.init(allocator, max_depth);
    global_capture = capture;
}

/// 清理全局捕获器
pub fn deinitGlobalCapture(allocator: std.mem.Allocator) void {
    global_capture_mutex.lock();
    defer global_capture_mutex.unlock();
    
    if (global_capture) |capture| {
        allocator.destroy(capture);
        global_capture = null;
    }
}

/// 获取全局捕获器
pub fn getGlobalCapture() ?*StackTraceCapture {
    global_capture_mutex.lock();
    defer global_capture_mutex.unlock();
    
    return global_capture;
}

/// 捕获当前堆栈跟踪（便捷函数）
/// @post 返回当前的堆栈跟踪
pub fn captureStackTrace() !StackTrace {
    const capture = getGlobalCapture() orelse return error.NotInitialized;
    return capture.capture();
}

/// 从返回地址捕获堆栈跟踪（便捷函数）
pub fn captureStackTraceFromAddresses(addresses: []const usize) !StackTrace {
    const capture = getGlobalCapture() orelse return error.NotInitialized;
    return capture.captureFromAddresses(addresses);
}

// ============================================================================
// 测试
// ============================================================================

test "StackFrame 基本功能" {
    const frame = StackFrame.init(
        .interpreted,
        "testFunction",
        "test.php",
        42,
        10,
    );
    
    try std.testing.expectEqual(FrameType.interpreted, frame.frame_type);
    try std.testing.expectEqualStrings("testFunction", frame.function_name);
    try std.testing.expectEqualStrings("test.php", frame.file_path);
    try std.testing.expectEqual(@as(u32, 42), frame.line);
    try std.testing.expectEqual(@as(u32, 10), frame.column);
    try std.testing.expect(frame.class_name == null);
}

test "StackFrame 构建器模式" {
    const frame = StackFrame.init(
        .jit_compiled,
        "myFunc",
        "test.php",
        10,
        5,
    )
        .withClassName("MyClass")
        .withInstructionPointer(0x1000)
        .withFramePointer(0x2000)
        .withReturnAddress(0x3000)
        .withCounts(5, 3);
    
    try std.testing.expectEqualStrings("MyClass", frame.class_name.?);
    try std.testing.expectEqual(@as(usize, 0x1000), frame.instruction_pointer);
    try std.testing.expectEqual(@as(usize, 0x2000), frame.frame_pointer);
    try std.testing.expectEqual(@as(usize, 0x3000), frame.return_address);
    try std.testing.expectEqual(@as(u16, 5), frame.local_count);
    try std.testing.expectEqual(@as(u16, 3), frame.param_count);
}

test "StackTrace 基本操作" {
    var trace = StackTrace.init(std.testing.allocator);
    defer trace.deinit();
    
    // 添加帧
    try trace.pushFrame(StackFrame.init(
        .interpreted,
        "func1",
        "test.php",
        10,
        5,
    ));
    
    try trace.pushFrame(StackFrame.init(
        .jit_compiled,
        "func2",
        "test.php",
        20,
        10,
    ));
    
    try trace.pushFrame(StackFrame.init(
        .aot_compiled,
        "func3",
        "test.php",
        30,
        15,
    ));
    
    // 验证深度
    try std.testing.expectEqual(@as(usize, 3), trace.depth());
    
    // 验证帧
    const frame0 = trace.getFrame(0).?;
    try std.testing.expectEqualStrings("func1", frame0.function_name);
    try std.testing.expectEqual(FrameType.interpreted, frame0.frame_type);
    
    const frame1 = trace.getFrame(1).?;
    try std.testing.expectEqualStrings("func2", frame1.function_name);
    try std.testing.expectEqual(FrameType.jit_compiled, frame1.frame_type);
    
    const frame2 = trace.getFrame(2).?;
    try std.testing.expectEqualStrings("func3", frame2.function_name);
    try std.testing.expectEqual(FrameType.aot_compiled, frame2.frame_type);
    
    // 越界访问
    try std.testing.expect(trace.getFrame(3) == null);
}

test "StackTrace 格式化输出" {
    var trace = StackTrace.init(std.testing.allocator);
    defer trace.deinit();
    
    try trace.pushFrame(StackFrame.init(
        .interpreted,
        "main",
        "test.php",
        1,
        1,
    ));
    
    try trace.pushFrame(StackFrame.init(
        .jit_compiled,
        "helper",
        "test.php",
        10,
        5,
    ).withClassName("MyClass"));
    
    // 转换为字符串
    const str = try trace.toString();
    defer std.testing.allocator.free(str);
    
    // 验证包含关键信息
    try std.testing.expect(std.mem.indexOf(u8, str, "Stack trace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "MyClass::helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "[INT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "[JIT]") != null);
}

test "StackTraceCapture 初始化和配置" {
    const capture = StackTraceCapture.init(std.testing.allocator, 128);
    
    try std.testing.expectEqual(@as(usize, 128), capture.max_depth);
    try std.testing.expectEqual(@as(usize, 0), capture.stats.capture_count);
    try std.testing.expectEqual(@as(usize, 0), capture.stats.total_frames);
}

test "StackTraceCapture 从地址捕获" {
    var capture = StackTraceCapture.init(std.testing.allocator, 64);
    
    // 模拟一些返回地址
    const addresses = [_]usize{ 0x1000, 0x2000, 0x3000 };
    
    var trace = try capture.captureFromAddresses(&addresses);
    defer trace.deinit();
    
    // 验证捕获了帧
    try std.testing.expectEqual(@as(usize, 3), trace.depth());
    
    // 验证统计
    try std.testing.expectEqual(@as(usize, 1), capture.stats.capture_count);
    try std.testing.expectEqual(@as(usize, 3), capture.stats.total_frames);
}

test "StackTraceCapture 最大深度限制" {
    var capture = StackTraceCapture.init(std.testing.allocator, 2);
    
    const addresses = [_]usize{ 0x1000, 0x2000, 0x3000, 0x4000 };
    
    var trace = try capture.captureFromAddresses(&addresses);
    defer trace.deinit();
    
    // 应该只捕获前 2 个帧
    try std.testing.expectEqual(@as(usize, 2), trace.depth());
}

test "StackTraceCapture 统计信息" {
    var capture = StackTraceCapture.init(std.testing.allocator, 64);
    
    // 捕获多次
    const addresses1 = [_]usize{ 0x1000, 0x2000 };
    var trace1 = try capture.captureFromAddresses(&addresses1);
    defer trace1.deinit();
    
    const addresses2 = [_]usize{ 0x3000, 0x4000, 0x5000 };
    var trace2 = try capture.captureFromAddresses(&addresses2);
    defer trace2.deinit();
    
    // 验证统计
    try std.testing.expectEqual(@as(usize, 2), capture.stats.capture_count);
    try std.testing.expectEqual(@as(usize, 5), capture.stats.total_frames);
    
    const avg = capture.stats.averageDepth();
    try std.testing.expect(avg > 2.4 and avg < 2.6);
}

test "全局捕获器" {
    // 初始化
    try initGlobalCapture(std.testing.allocator, 64);
    defer deinitGlobalCapture(std.testing.allocator);
    
    // 获取全局捕获器
    const capture = getGlobalCapture();
    try std.testing.expect(capture != null);
    
    // 重复初始化应该失败
    try std.testing.expectError(error.AlreadyInitialized, initGlobalCapture(std.testing.allocator, 64));
}

test "StackFrame 格式化输出" {
    var list: std.ArrayListUnmanaged(u8) = .{};
    defer list.deinit(std.testing.allocator);
    
    const frame = StackFrame.init(
        .jit_compiled,
        "testFunc",
        "test.php",
        42,
        10,
    ).withClassName("TestClass").withInstructionPointer(0x123456789ABCDEF0);
    
    try frame.format("", .{}, list.writer(std.testing.allocator));
    
    const output = list.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "[JIT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "TestClass::testFunc") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test.php:42:10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "0x123456789ABCDEF0") != null);
}
