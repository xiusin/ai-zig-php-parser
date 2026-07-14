/// JIT 堆栈跟踪集成
///
/// 将 JIT 调试信息与统一堆栈跟踪系统集成
///
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED
/// @验证：需求 10.3
const std = @import("std");
const debug_info = @import("debug_info.zig");
const imports = @import("imports.zig");
const stack_trace = imports.stack_trace;

/// JIT 堆栈跟踪解析器
pub const JitStackTraceResolver = struct {
    allocator: std.mem.Allocator,

    /// JIT 调试信息管理器
    debug_info_manager: *debug_info.DebugInfoManager,

    /// 初始化解析器
    pub fn init(
        allocator: std.mem.Allocator,
        debug_info_manager: *debug_info.DebugInfoManager,
    ) JitStackTraceResolver {
        return .{
            .allocator = allocator,
            .debug_info_manager = debug_info_manager,
        };
    }

    /// 解析 JIT 地址到堆栈帧
    /// @pre address 必须是有效的 JIT 代码地址
    /// @post 返回解析后的堆栈帧，如果无法解析返回 null
    pub fn resolveAddress(
        self: *JitStackTraceResolver,
        address: usize,
    ) ?stack_trace.StackFrame {
        // 查找源代码位置
        const source_location = self.debug_info_manager.lookupSourceLocation(address) orelse return null;

        // 创建堆栈帧
        return stack_trace.StackFrame.init(
            .jit_compiled,
            source_location.function_name,
            source_location.file_path,
            source_location.line,
            source_location.column,
        ).withInstructionPointer(address);
    }

    /// 从返回地址列表生成堆栈跟踪
    /// @pre addresses 必须是有效的返回地址数组
    /// @post 返回完整的堆栈跟踪
    pub fn generateStackTrace(
        self: *JitStackTraceResolver,
        addresses: []const usize,
    ) !stack_trace.StackTrace {
        var trace = stack_trace.StackTrace.init(self.allocator);
        errdefer trace.deinit();

        for (addresses) |address| {
            if (self.resolveAddress(address)) |frame| {
                try trace.pushFrame(frame);
            } else {
                // 无法解析，创建未知帧
                const unknown_frame = stack_trace.StackFrame.init(
                    .jit_compiled,
                    "<unknown JIT function>",
                    "<unknown>",
                    0,
                    0,
                ).withInstructionPointer(address);

                try trace.pushFrame(unknown_frame);
            }
        }

        return trace;
    }

    /// 从函数名生成堆栈跟踪
    /// @pre function_name 必须是有效的函数名
    /// @post 返回函数的堆栈跟踪信息
    pub fn generateStackTraceForFunction(
        self: *JitStackTraceResolver,
        function_name: []const u8,
    ) !?stack_trace.StackTrace {
        // 查找函数地址范围
        const address_range = self.debug_info_manager.lookupFunctionAddress(function_name) orelse return null;

        var trace = stack_trace.StackTrace.init(self.allocator);
        errdefer trace.deinit();

        // 获取函数范围内的所有映射
        var mappings = try self.debug_info_manager.getMappingsInRange(address_range);
        defer mappings.deinit(self.allocator);

        // 为每个映射创建帧
        for (mappings.items) |mapping| {
            const frame = stack_trace.StackFrame.init(
                .jit_compiled,
                mapping.source_location.function_name,
                mapping.source_location.file_path,
                mapping.source_location.line,
                mapping.source_location.column,
            ).withInstructionPointer(mapping.address_range.start);

            try trace.pushFrame(frame);
        }

        return trace;
    }

    /// 增强现有堆栈跟踪
    /// @pre trace 必须是有效的堆栈跟踪
    /// @post 为 JIT 帧添加详细信息
    pub fn enhanceStackTrace(
        self: *JitStackTraceResolver,
        trace: *stack_trace.StackTrace,
    ) !void {
        for (trace.frames.items) |*frame| {
            // 只处理 JIT 帧
            if (frame.frame_type != .jit_compiled) continue;

            // 如果已有详细信息，跳过
            if (frame.line != 0) continue;

            // 尝试解析地址
            if (self.resolveAddress(frame.instruction_pointer)) |resolved_frame| {
                frame.file_path = resolved_frame.file_path;
                frame.line = resolved_frame.line;
                frame.column = resolved_frame.column;
                frame.function_name = resolved_frame.function_name;
            }
        }
    }
};

/// JIT 异常处理器
/// 在 JIT 代码中捕获和处理异常
pub const JitExceptionHandler = struct {
    allocator: std.mem.Allocator,

    /// 堆栈跟踪解析器
    resolver: *JitStackTraceResolver,

    /// 当前异常
    current_exception: ?Exception,

    /// 异常
    pub const Exception = struct {
        /// 异常消息
        message: []const u8,

        /// 异常代码
        code: i32,

        /// 堆栈跟踪
        stack_trace: stack_trace.StackTrace,

        /// 清理资源
        pub fn deinit(self: *Exception) void {
            self.stack_trace.deinit();
        }
    };

    /// 初始化异常处理器
    pub fn init(
        allocator: std.mem.Allocator,
        resolver: *JitStackTraceResolver,
    ) JitExceptionHandler {
        return .{
            .allocator = allocator,
            .resolver = resolver,
            .current_exception = null,
        };
    }

    /// 清理资源
    pub fn deinit(self: *JitExceptionHandler) void {
        if (self.current_exception) |*exception| {
            exception.deinit();
        }
    }

    /// 抛出异常
    /// @pre message 必须有效
    /// @post 创建异常并捕获堆栈跟踪
    pub fn throwException(
        self: *JitExceptionHandler,
        message: []const u8,
        code: i32,
        return_addresses: []const usize,
    ) !void {
        // 清理旧异常
        if (self.current_exception) |*exception| {
            exception.deinit();
        }

        // 生成堆栈跟踪
        const trace = try self.resolver.generateStackTrace(return_addresses);

        // 创建新异常
        self.current_exception = Exception{
            .message = message,
            .code = code,
            .stack_trace = trace,
        };
    }

    /// 获取当前异常
    pub fn getCurrentException(self: *JitExceptionHandler) ?*Exception {
        if (self.current_exception) |*exception| {
            return exception;
        }
        return null;
    }

    /// 清除当前异常
    pub fn clearException(self: *JitExceptionHandler) void {
        if (self.current_exception) |*exception| {
            exception.deinit();
            self.current_exception = null;
        }
    }

    /// 打印异常信息
    pub fn printException(self: *JitExceptionHandler, writer: anytype) !void {
        if (self.current_exception) |*exception| {
            try writer.writeAll("\n=== JIT Exception ===\n");
            try writer.print("Message: {s}\n", .{exception.message});
            try writer.print("Code: {d}\n\n", .{exception.code});
            try exception.stack_trace.format("", .{}, writer);
        }
    }
};

/// JIT 调试上下文
/// 在 JIT 代码执行期间维护调试信息
pub const JitDebugContext = struct {
    allocator: std.mem.Allocator,

    /// 调试信息管理器
    debug_info_manager: *debug_info.DebugInfoManager,

    /// 堆栈跟踪解析器
    resolver: JitStackTraceResolver,

    /// 异常处理器
    exception_handler: JitExceptionHandler,

    /// 当前执行的函数
    current_function: ?[]const u8,

    /// 当前指令指针
    current_ip: usize,

    /// 初始化调试上下文
    pub fn init(
        allocator: std.mem.Allocator,
        debug_info_manager: *debug_info.DebugInfoManager,
    ) !JitDebugContext {
        var resolver = JitStackTraceResolver.init(allocator, debug_info_manager);

        return .{
            .allocator = allocator,
            .debug_info_manager = debug_info_manager,
            .resolver = resolver,
            .exception_handler = JitExceptionHandler.init(allocator, &resolver),
            .current_function = null,
            .current_ip = 0,
        };
    }

    /// 清理资源
    pub fn deinit(self: *JitDebugContext) void {
        self.exception_handler.deinit();
    }

    /// 进入函数
    pub fn enterFunction(self: *JitDebugContext, function_name: []const u8, ip: usize) void {
        self.current_function = function_name;
        self.current_ip = ip;
    }

    /// 退出函数
    pub fn exitFunction(self: *JitDebugContext) void {
        self.current_function = null;
        self.current_ip = 0;
    }

    /// 更新指令指针
    pub fn updateIP(self: *JitDebugContext, ip: usize) void {
        self.current_ip = ip;
    }

    /// 获取当前源代码位置
    pub fn getCurrentLocation(self: *JitDebugContext) ?debug_info.SourceLocation {
        if (self.current_ip == 0) return null;
        return self.debug_info_manager.lookupSourceLocation(self.current_ip);
    }

    /// 捕获当前堆栈跟踪
    pub fn captureStackTrace(self: *JitDebugContext) !stack_trace.StackTrace {
        // 使用 Zig 的内置堆栈跟踪
        var addresses: [64]usize = undefined;
        const count = std.debug.captureStackTrace(@returnAddress(), &addresses);

        return self.resolver.generateStackTrace(addresses[0..count]);
    }

    /// 处理运行时错误
    pub fn handleRuntimeError(
        self: *JitDebugContext,
        error_message: []const u8,
        error_code: i32,
    ) !void {
        // 捕获堆栈跟踪
        var addresses: [64]usize = undefined;
        const count = std.debug.captureStackTrace(@returnAddress(), &addresses);

        // 抛出异常
        try self.exception_handler.throwException(
            error_message,
            error_code,
            addresses[0..count],
        );
    }
};

// ============================================================================
// 测试
// ============================================================================

test "JitStackTraceResolver 基本功能" {
    var debug_mgr = debug_info.DebugInfoManager.init(std.testing.allocator);
    defer debug_mgr.deinit();

    // 添加测试映射
    const mapping = debug_info.CodeMapping.init(
        .{ .start = 0x1000, .end = 0x1010 },
        debug_info.SourceLocation.init("test.php", 42, 10, "testFunc"),
        0,
    );
    try debug_mgr.addCodeMapping(mapping);

    // 创建解析器
    var resolver = JitStackTraceResolver.init(std.testing.allocator, &debug_mgr);

    // 解析地址
    const frame = resolver.resolveAddress(0x1005);
    try std.testing.expect(frame != null);
    try std.testing.expectEqual(stack_trace.FrameType.jit_compiled, frame.?.frame_type);
    try std.testing.expectEqualStrings("testFunc", frame.?.function_name);
    try std.testing.expectEqual(@as(u32, 42), frame.?.line);

    // 无法解析的地址
    const no_frame = resolver.resolveAddress(0x2000);
    try std.testing.expect(no_frame == null);
}

test "JitStackTraceResolver 生成堆栈跟踪" {
    var debug_mgr = debug_info.DebugInfoManager.init(std.testing.allocator);
    defer debug_mgr.deinit();

    // 添加多个映射
    try debug_mgr.addCodeMapping(debug_info.CodeMapping.init(
        .{ .start = 0x1000, .end = 0x1010 },
        debug_info.SourceLocation.init("test.php", 10, 5, "func1"),
        0,
    ));

    try debug_mgr.addCodeMapping(debug_info.CodeMapping.init(
        .{ .start = 0x2000, .end = 0x2010 },
        debug_info.SourceLocation.init("test.php", 20, 5, "func2"),
        10,
    ));

    // 创建解析器
    var resolver = JitStackTraceResolver.init(std.testing.allocator, &debug_mgr);

    // 生成堆栈跟踪
    const addresses = [_]usize{ 0x1005, 0x2005, 0x3000 };
    var trace = try resolver.generateStackTrace(&addresses);
    defer trace.deinit();

    // 验证
    try std.testing.expectEqual(@as(usize, 3), trace.depth());

    const frame0 = trace.getFrame(0).?;
    try std.testing.expectEqualStrings("func1", frame0.function_name);

    const frame1 = trace.getFrame(1).?;
    try std.testing.expectEqualStrings("func2", frame1.function_name);

    const frame2 = trace.getFrame(2).?;
    try std.testing.expectEqualStrings("<unknown JIT function>", frame2.function_name);
}

test "JitExceptionHandler 异常处理" {
    var debug_mgr = debug_info.DebugInfoManager.init(std.testing.allocator);
    defer debug_mgr.deinit();

    // 添加映射
    try debug_mgr.addCodeMapping(debug_info.CodeMapping.init(
        .{ .start = 0x1000, .end = 0x1010 },
        debug_info.SourceLocation.init("test.php", 42, 10, "testFunc"),
        0,
    ));

    var resolver = JitStackTraceResolver.init(std.testing.allocator, &debug_mgr);
    var handler = JitExceptionHandler.init(std.testing.allocator, &resolver);
    defer handler.deinit();

    // 抛出异常
    const addresses = [_]usize{0x1005};
    try handler.throwException("Test error", 123, &addresses);

    // 验证异常
    const exception = handler.getCurrentException();
    try std.testing.expect(exception != null);
    try std.testing.expectEqualStrings("Test error", exception.?.message);
    try std.testing.expectEqual(@as(i32, 123), exception.?.code);
    try std.testing.expectEqual(@as(usize, 1), exception.?.stack_trace.depth());

    // 清除异常
    handler.clearException();
    try std.testing.expect(handler.getCurrentException() == null);
}

test "JitDebugContext 基本操作" {
    var debug_mgr = debug_info.DebugInfoManager.init(std.testing.allocator);
    defer debug_mgr.deinit();

    // 添加映射
    try debug_mgr.addCodeMapping(debug_info.CodeMapping.init(
        .{ .start = 0x1000, .end = 0x1010 },
        debug_info.SourceLocation.init("test.php", 42, 10, "testFunc"),
        0,
    ));

    var context = try JitDebugContext.init(std.testing.allocator, &debug_mgr);
    defer context.deinit();

    // 进入函数
    context.enterFunction("testFunc", 0x1005);
    try std.testing.expectEqualStrings("testFunc", context.current_function.?);
    try std.testing.expectEqual(@as(usize, 0x1005), context.current_ip);

    // 获取当前位置
    const location = context.getCurrentLocation();
    try std.testing.expect(location != null);
    try std.testing.expectEqual(@as(u32, 42), location.?.line);

    // 退出函数
    context.exitFunction();
    try std.testing.expect(context.current_function == null);
    try std.testing.expectEqual(@as(usize, 0), context.current_ip);
}

test "JitDebugContext 错误处理" {
    var debug_mgr = debug_info.DebugInfoManager.init(std.testing.allocator);
    defer debug_mgr.deinit();

    var context = try JitDebugContext.init(std.testing.allocator, &debug_mgr);
    defer context.deinit();

    // 处理运行时错误
    try context.handleRuntimeError("Division by zero", 1);

    // 验证异常被捕获
    const exception = context.exception_handler.getCurrentException();
    try std.testing.expect(exception != null);
    try std.testing.expectEqualStrings("Division by zero", exception.?.message);
    try std.testing.expectEqual(@as(i32, 1), exception.?.code);
}
