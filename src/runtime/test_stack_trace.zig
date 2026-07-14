/// 堆栈跟踪系统测试
///
/// 验证需求 10.3：错误堆栈跟踪
const std = @import("std");
const stack_trace = @import("stack_trace.zig");
const testing = std.testing;

// ============================================================================
// 单元测试
// ============================================================================

test "StackFrame 创建和访问" {
    const frame = stack_trace.StackFrame.init(
        .interpreted,
        "myFunction",
        "/path/to/file.php",
        100,
        20,
    );

    try testing.expectEqual(stack_trace.FrameType.interpreted, frame.frame_type);
    try testing.expectEqualStrings("myFunction", frame.function_name);
    try testing.expectEqualStrings("/path/to/file.php", frame.file_path);
    try testing.expectEqual(@as(u32, 100), frame.line);
    try testing.expectEqual(@as(u32, 20), frame.column);
    try testing.expect(frame.class_name == null);
    try testing.expectEqual(@as(usize, 0), frame.instruction_pointer);
}

test "StackFrame 链式构建" {
    const frame = stack_trace.StackFrame.init(
        .jit_compiled,
        "calculate",
        "math.php",
        50,
        10,
    )
        .withClassName("Calculator")
        .withInstructionPointer(0xDEADBEEF)
        .withFramePointer(0xCAFEBABE)
        .withReturnAddress(0xFEEDFACE)
        .withCounts(10, 3);

    try testing.expectEqualStrings("Calculator", frame.class_name.?);
    try testing.expectEqual(@as(usize, 0xDEADBEEF), frame.instruction_pointer);
    try testing.expectEqual(@as(usize, 0xCAFEBABE), frame.frame_pointer);
    try testing.expectEqual(@as(usize, 0xFEEDFACE), frame.return_address);
    try testing.expectEqual(@as(u16, 10), frame.local_count);
    try testing.expectEqual(@as(u16, 3), frame.param_count);
}

test "StackTrace 添加和访问帧" {
    var trace = stack_trace.StackTrace.init(testing.allocator);
    defer trace.deinit();

    // 添加多个帧
    try trace.pushFrame(stack_trace.StackFrame.init(
        .interpreted,
        "main",
        "index.php",
        1,
        1,
    ));

    try trace.pushFrame(stack_trace.StackFrame.init(
        .jit_compiled,
        "processData",
        "processor.php",
        45,
        12,
    ));

    try trace.pushFrame(stack_trace.StackFrame.init(
        .aot_compiled,
        "validateInput",
        "validator.php",
        78,
        5,
    ));

    // 验证深度
    try testing.expectEqual(@as(usize, 3), trace.depth());

    // 验证每个帧
    const frame0 = trace.getFrame(0).?;
    try testing.expectEqualStrings("main", frame0.function_name);
    try testing.expectEqual(stack_trace.FrameType.interpreted, frame0.frame_type);

    const frame1 = trace.getFrame(1).?;
    try testing.expectEqualStrings("processData", frame1.function_name);
    try testing.expectEqual(stack_trace.FrameType.jit_compiled, frame1.frame_type);

    const frame2 = trace.getFrame(2).?;
    try testing.expectEqualStrings("validateInput", frame2.function_name);
    try testing.expectEqual(stack_trace.FrameType.aot_compiled, frame2.frame_type);

    // 越界访问
    try testing.expect(trace.getFrame(3) == null);
    try testing.expect(trace.getFrame(100) == null);
}

test "StackTrace 空跟踪" {
    var trace = stack_trace.StackTrace.init(testing.allocator);
    defer trace.deinit();

    try testing.expectEqual(@as(usize, 0), trace.depth());
    try testing.expect(trace.getFrame(0) == null);
}

test "StackTrace 格式化输出包含所有信息" {
    var trace = stack_trace.StackTrace.init(testing.allocator);
    defer trace.deinit();

    try trace.pushFrame(stack_trace.StackFrame.init(
        .interpreted,
        "topLevel",
        "main.php",
        10,
        5,
    ));

    try trace.pushFrame(stack_trace.StackFrame.init(
        .jit_compiled,
        "helper",
        "utils.php",
        25,
        15,
    ).withClassName("Utils"));

    const output = try trace.toString();
    defer testing.allocator.free(output);

    // 验证包含关键信息
    try testing.expect(std.mem.indexOf(u8, output, "Stack trace:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Thread:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Depth: 2") != null);
    try testing.expect(std.mem.indexOf(u8, output, "topLevel") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Utils::helper") != null);
    try testing.expect(std.mem.indexOf(u8, output, "main.php:10:5") != null);
    try testing.expect(std.mem.indexOf(u8, output, "utils.php:25:15") != null);
    try testing.expect(std.mem.indexOf(u8, output, "[INT]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "[JIT]") != null);
}

test "StackTraceCapture 初始化和配置" {
    const capture = stack_trace.StackTraceCapture.init(testing.allocator, 128);

    try testing.expectEqual(@as(usize, 128), capture.max_depth);
    try testing.expectEqual(@as(usize, 0), capture.stats.capture_count);
    try testing.expectEqual(@as(usize, 0), capture.stats.total_frames);
    try testing.expect(capture.jit_debug_info == null);
    try testing.expect(capture.aot_debug_info == null);
}

test "StackTraceCapture 从地址列表捕获" {
    var capture = stack_trace.StackTraceCapture.init(testing.allocator, 64);

    // 模拟返回地址
    const addresses = [_]usize{
        0x0000000100001000,
        0x0000000100002000,
        0x0000000100003000,
        0x0000000100004000,
    };

    var trace = try capture.captureFromAddresses(&addresses);
    defer trace.deinit();

    // 验证捕获了所有地址
    try testing.expectEqual(@as(usize, 4), trace.depth());

    // 验证每个帧都有地址
    for (addresses, 0..) |addr, i| {
        const frame = trace.getFrame(i).?;
        try testing.expectEqual(addr, frame.instruction_pointer);
    }

    // 验证统计
    try testing.expectEqual(@as(usize, 1), capture.stats.capture_count);
    try testing.expectEqual(@as(usize, 4), capture.stats.total_frames);
}

test "StackTraceCapture 最大深度限制" {
    var capture = stack_trace.StackTraceCapture.init(testing.allocator, 3);

    const addresses = [_]usize{
        0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000,
    };

    var trace = try capture.captureFromAddresses(&addresses);
    defer trace.deinit();

    // 应该只捕获前 3 个
    try testing.expectEqual(@as(usize, 3), trace.depth());

    const frame0 = trace.getFrame(0).?;
    try testing.expectEqual(@as(usize, 0x1000), frame0.instruction_pointer);

    const frame2 = trace.getFrame(2).?;
    try testing.expectEqual(@as(usize, 0x3000), frame2.instruction_pointer);
}

test "StackTraceCapture 空地址列表" {
    var capture = stack_trace.StackTraceCapture.init(testing.allocator, 64);

    const addresses: []const usize = &[_]usize{};
    var trace = try capture.captureFromAddresses(addresses);
    defer trace.deinit();

    try testing.expectEqual(@as(usize, 0), trace.depth());
    try testing.expectEqual(@as(usize, 1), capture.stats.capture_count);
    try testing.expectEqual(@as(usize, 0), capture.stats.total_frames);
}

test "StackTraceCapture 统计信息计算" {
    var capture = stack_trace.StackTraceCapture.init(testing.allocator, 64);

    // 第一次捕获：2 个帧
    const addresses1 = [_]usize{ 0x1000, 0x2000 };
    var trace1 = try capture.captureFromAddresses(&addresses1);
    defer trace1.deinit();

    // 第二次捕获：3 个帧
    const addresses2 = [_]usize{ 0x3000, 0x4000, 0x5000 };
    var trace2 = try capture.captureFromAddresses(&addresses2);
    defer trace2.deinit();

    // 第三次捕获：1 个帧
    const addresses3 = [_]usize{0x6000};
    var trace3 = try capture.captureFromAddresses(&addresses3);
    defer trace3.deinit();

    // 验证统计
    try testing.expectEqual(@as(usize, 3), capture.stats.capture_count);
    try testing.expectEqual(@as(usize, 6), capture.stats.total_frames);

    const avg = capture.stats.averageDepth();
    try testing.expect(avg > 1.99 and avg < 2.01); // 6 / 3 = 2.0
}

test "StackTraceCapture 统计信息边界情况" {
    var capture = stack_trace.StackTraceCapture.init(testing.allocator, 64);

    // 没有捕获时平均深度应该是 0
    try testing.expectEqual(@as(f64, 0.0), capture.stats.averageDepth());
}

test "全局捕获器生命周期" {
    // 初始化
    try stack_trace.initGlobalCapture(testing.allocator, 64);

    // 获取全局捕获器
    const capture1 = stack_trace.getGlobalCapture();
    try testing.expect(capture1 != null);
    try testing.expectEqual(@as(usize, 64), capture1.?.max_depth);

    // 再次获取应该返回同一个实例
    const capture2 = stack_trace.getGlobalCapture();
    try testing.expect(capture2 != null);
    try testing.expectEqual(@intFromPtr(capture1.?), @intFromPtr(capture2.?));

    // 清理
    stack_trace.deinitGlobalCapture(testing.allocator);

    // 清理后应该返回 null
    const capture3 = stack_trace.getGlobalCapture();
    try testing.expect(capture3 == null);
}

test "全局捕获器重复初始化" {
    try stack_trace.initGlobalCapture(testing.allocator, 64);
    defer stack_trace.deinitGlobalCapture(testing.allocator);

    // 重复初始化应该失败
    try testing.expectError(
        error.AlreadyInitialized,
        stack_trace.initGlobalCapture(testing.allocator, 128),
    );
}

test "全局捕获器便捷函数" {
    try stack_trace.initGlobalCapture(testing.allocator, 64);
    defer stack_trace.deinitGlobalCapture(testing.allocator);

    // 使用便捷函数捕获
    const addresses = [_]usize{ 0x1000, 0x2000, 0x3000 };
    var trace = try stack_trace.captureStackTraceFromAddresses(&addresses);
    defer trace.deinit();

    try testing.expectEqual(@as(usize, 3), trace.depth());
}

test "全局捕获器未初始化错误" {
    // 确保全局捕获器未初始化
    stack_trace.deinitGlobalCapture(testing.allocator);

    // 尝试使用便捷函数应该失败
    const addresses = [_]usize{0x1000};
    try testing.expectError(
        error.NotInitialized,
        stack_trace.captureStackTraceFromAddresses(&addresses),
    );
}

test "StackFrame 不同类型标记" {
    var list: std.ArrayListUnmanaged(u8) = .{};
    defer list.deinit(testing.allocator);

    const frame_types = [_]stack_trace.FrameType{
        .interpreted,
        .jit_compiled,
        .aot_compiled,
        .native,
        .inlined,
    };

    const expected_markers = [_][]const u8{
        "[INT]",
        "[JIT]",
        "[AOT]",
        "[NAT]",
        "[INL]",
    };

    for (frame_types, expected_markers) |frame_type, expected_marker| {
        list.clearRetainingCapacity();

        const frame = stack_trace.StackFrame.init(
            frame_type,
            "testFunc",
            "test.php",
            10,
            5,
        );

        try frame.format("", .{}, list.writer(testing.allocator));

        const output = list.items;
        try testing.expect(std.mem.indexOf(u8, output, expected_marker) != null);
    }
}

test "StackFrame 格式化包含所有字段" {
    var list: std.ArrayListUnmanaged(u8) = .{};
    defer list.deinit(testing.allocator);

    const frame = stack_trace.StackFrame.init(
        .jit_compiled,
        "complexFunction",
        "/var/www/app.php",
        123,
        45,
    )
        .withClassName("MyNamespace\\MyClass")
        .withInstructionPointer(0x123456789ABCDEF0);

    try frame.format("", .{}, list.writer(testing.allocator));

    const output = list.items;

    // 验证所有关键信息都在输出中
    try testing.expect(std.mem.indexOf(u8, output, "[JIT]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "MyNamespace\\MyClass::complexFunction") != null);
    try testing.expect(std.mem.indexOf(u8, output, "/var/www/app.php:123:45") != null);
    try testing.expect(std.mem.indexOf(u8, output, "0x123456789ABCDEF0") != null);
}

test "StackTrace 大量帧" {
    var trace = stack_trace.StackTrace.init(testing.allocator);
    defer trace.deinit();

    // 添加 100 个帧
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try trace.pushFrame(stack_trace.StackFrame.init(
            .interpreted,
            "func",
            "test.php",
            @intCast(i + 1),
            1,
        ));
    }

    try testing.expectEqual(@as(usize, 100), trace.depth());

    // 验证第一个和最后一个帧
    const first = trace.getFrame(0).?;
    try testing.expectEqual(@as(u32, 1), first.line);

    const last = trace.getFrame(99).?;
    try testing.expectEqual(@as(u32, 100), last.line);
}

test "StackTraceCapture 设置调试信息" {
    var capture = stack_trace.StackTraceCapture.init(testing.allocator, 64);

    // 模拟调试信息指针
    var dummy_jit: u32 = 0;
    var dummy_aot: u32 = 0;

    capture.setJitDebugInfo(&dummy_jit);
    capture.setAotDebugInfo(&dummy_aot);

    try testing.expect(capture.jit_debug_info != null);
    try testing.expect(capture.aot_debug_info != null);
}

// ============================================================================
// 集成测试
// ============================================================================

test "完整堆栈跟踪工作流" {
    // 初始化全局捕获器
    try stack_trace.initGlobalCapture(testing.allocator, 64);
    defer stack_trace.deinitGlobalCapture(testing.allocator);

    // 模拟函数调用链
    const addresses = [_]usize{
        0x0000000100001000, // main
        0x0000000100002000, // processRequest
        0x0000000100003000, // validateData
        0x0000000100004000, // checkPermissions
    };

    // 捕获堆栈跟踪
    var trace = try stack_trace.captureStackTraceFromAddresses(&addresses);
    defer trace.deinit();

    // 验证跟踪
    try testing.expectEqual(@as(usize, 4), trace.depth());

    // 验证每个帧都有正确的地址
    for (addresses, 0..) |addr, i| {
        const frame = trace.getFrame(i).?;
        try testing.expectEqual(addr, frame.instruction_pointer);
    }

    // 格式化输出
    const output = try trace.toString();
    defer testing.allocator.free(output);

    // 验证输出包含所有地址
    for (addresses) |addr| {
        const addr_str = try std.fmt.allocPrint(testing.allocator, "0x{x:0>16}", .{addr});
        defer testing.allocator.free(addr_str);
        try testing.expect(std.mem.indexOf(u8, output, addr_str) != null);
    }
}

test "混合帧类型堆栈跟踪" {
    var trace = stack_trace.StackTrace.init(testing.allocator);
    defer trace.deinit();

    // 添加不同类型的帧
    try trace.pushFrame(stack_trace.StackFrame.init(
        .interpreted,
        "main",
        "index.php",
        1,
        1,
    ));

    try trace.pushFrame(stack_trace.StackFrame.init(
        .jit_compiled,
        "hotFunction",
        "hot.php",
        50,
        10,
    ).withInstructionPointer(0x1000));

    try trace.pushFrame(stack_trace.StackFrame.init(
        .aot_compiled,
        "optimizedFunc",
        "optimized.php",
        100,
        20,
    ).withInstructionPointer(0x2000));

    try trace.pushFrame(stack_trace.StackFrame.init(
        .native,
        "nativeHelper",
        "native.c",
        200,
        30,
    ).withInstructionPointer(0x3000));

    try trace.pushFrame(stack_trace.StackFrame.init(
        .inlined,
        "inlinedFunc",
        "inline.php",
        300,
        40,
    ));

    // 验证所有帧
    try testing.expectEqual(@as(usize, 5), trace.depth());

    const output = try trace.toString();
    defer testing.allocator.free(output);

    // 验证所有类型标记都存在
    try testing.expect(std.mem.indexOf(u8, output, "[INT]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "[JIT]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "[AOT]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "[NAT]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "[INL]") != null);
}
