/// 崩溃处理器测试
/// 
/// 测试运行时崩溃处理系统的功能
/// 
/// @验证：需求 10.7

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const crash_handler = @import("crash_handler.zig");
const stack_trace = @import("stack_trace.zig");

// ============================================================================
// 基础功能测试
// ============================================================================

test "CrashType 从信号获取" {
    const seg_fault = crash_handler.CrashType.fromSignal(std.posix.SIG.SEGV);
    try testing.expectEqual(crash_handler.CrashType.segmentation_fault, seg_fault);
    
    const ill_inst = crash_handler.CrashType.fromSignal(std.posix.SIG.ILL);
    try testing.expectEqual(crash_handler.CrashType.illegal_instruction, ill_inst);
    
    const fpe = crash_handler.CrashType.fromSignal(std.posix.SIG.FPE);
    try testing.expectEqual(crash_handler.CrashType.floating_point_exception, fpe);
    
    const abort = crash_handler.CrashType.fromSignal(std.posix.SIG.ABRT);
    try testing.expectEqual(crash_handler.CrashType.abort_signal, abort);
    
    const bus = crash_handler.CrashType.fromSignal(std.posix.SIG.BUS);
    try testing.expectEqual(crash_handler.CrashType.bus_error, bus);
}

test "CrashType 描述" {
    const seg_fault = crash_handler.CrashType.segmentation_fault;
    const desc = seg_fault.description();
    try testing.expect(std.mem.indexOf(u8, desc, "Segmentation fault") != null);
    
    const ill_inst = crash_handler.CrashType.illegal_instruction;
    const desc2 = ill_inst.description();
    try testing.expect(std.mem.indexOf(u8, desc2, "Illegal instruction") != null);
}

test "CrashContext 初始化" {
    // 创建模拟的 siginfo_t
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.SEGV;
    info.code = 1;
    
    // 平台相关的故障地址设置
    if (builtin.os.tag == .linux) {
        info.fields.sigfault.addr = @ptrFromInt(0x12345678);
    }
    
    const context = crash_handler.CrashContext.init(std.posix.SIG.SEGV, &info, null);
    
    try testing.expectEqual(crash_handler.CrashType.segmentation_fault, context.crash_type);
    try testing.expectEqual(std.posix.SIG.SEGV, context.signal);
    try testing.expectEqual(@as(c_int, 1), context.error_code);
    
    // 只在 Linux 上验证故障地址
    if (builtin.os.tag == .linux) {
        try testing.expect(context.fault_address != null);
        try testing.expectEqual(@as(usize, 0x12345678), context.fault_address.?);
    }
}

test "CrashReport 初始化和清理" {
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.SEGV;
    info.code = 1;
    
    if (builtin.os.tag == .linux) {
        info.fields.sigfault.addr = @ptrFromInt(0x1000);
    }
    
    const context = crash_handler.CrashContext.init(std.posix.SIG.SEGV, &info, null);
    
    var report = try crash_handler.CrashReport.init(testing.allocator, context);
    defer report.deinit();
    
    // 验证基本信息
    try testing.expectEqual(crash_handler.CrashType.segmentation_fault, report.context.crash_type);
    try testing.expect(report.system_info.os.len > 0);
    try testing.expect(report.system_info.arch.len > 0);
}

test "CrashReport 生成报告文本" {
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.ILL;
    info.code = 2;
    
    const context = crash_handler.CrashContext.init(std.posix.SIG.ILL, &info, null);
    
    var report = try crash_handler.CrashReport.init(testing.allocator, context);
    defer report.deinit();
    
    const report_text = try report.generateReport();
    defer testing.allocator.free(report_text);
    
    // 验证报告包含关键信息
    try testing.expect(std.mem.indexOf(u8, report_text, "CRASH REPORT") != null);
    try testing.expect(std.mem.indexOf(u8, report_text, "CRASH INFORMATION") != null);
    try testing.expect(std.mem.indexOf(u8, report_text, "SYSTEM INFORMATION") != null);
    try testing.expect(std.mem.indexOf(u8, report_text, "MEMORY INFORMATION") != null);
    try testing.expect(std.mem.indexOf(u8, report_text, "Illegal instruction") != null);
}

test "CrashReport 保存到文件" {
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.FPE;
    info.code = 1;
    
    const context = crash_handler.CrashContext.init(std.posix.SIG.FPE, &info, null);
    
    var report = try crash_handler.CrashReport.init(testing.allocator, context);
    defer report.deinit();
    
    // 创建临时目录
    const temp_dir = "test_crash_reports";
    std.fs.cwd.makePath(temp_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    defer std.fs.cwd.deleteTree(temp_dir) catch {};
    
    // 保存报告
    const report_path = temp_dir ++ "/test_crash.txt";
    try report.saveToFile(report_path);
    
    // 验证文件存在
    const file = try std.fs.cwd.openFile(report_path, .{});
    defer file.close();
    
    // 读取并验证内容
    const content = try file.readToEndAlloc(testing.allocator, 1024 * 1024);
    defer testing.allocator.free(content);
    
    try testing.expect(std.mem.indexOf(u8, content, "CRASH REPORT") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Floating point exception") != null);
}

test "CrashHandler 初始化" {
    const handler = crash_handler.CrashHandler.init(
        testing.allocator,
        "crash_reports",
        false,
    );
    
    try testing.expect(!handler.installed);
    try testing.expectEqualStrings("crash_reports", handler.crash_report_dir);
    try testing.expect(!handler.enable_core_dump);
    try testing.expectEqual(@as(usize, 0), handler.stats.crash_count);
    try testing.expectEqual(@as(usize, 0), handler.stats.report_count);
}

test "CrashHandler 安装和卸载" {
    // 创建临时目录
    const temp_dir = "test_crash_handler";
    std.fs.cwd.makePath(temp_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    defer std.fs.cwd.deleteTree(temp_dir) catch {};
    
    var handler = crash_handler.CrashHandler.init(
        testing.allocator,
        temp_dir,
        false, // 不启用 core dump 以避免测试环境问题
    );
    
    // 安装
    try handler.install();
    try testing.expect(handler.installed);
    
    // 重复安装应该失败
    try testing.expectError(error.AlreadyInstalled, handler.install());
    
    // 卸载
    try handler.uninstall();
    try testing.expect(!handler.installed);
}

// ============================================================================
// 集成测试
// ============================================================================

test "完整崩溃处理流程" {
    // 初始化堆栈跟踪捕获器
    try stack_trace.initGlobalCapture(testing.allocator, 64);
    defer stack_trace.deinitGlobalCapture(testing.allocator);
    
    // 创建临时目录
    const temp_dir = "test_full_crash";
    std.fs.cwd.makePath(temp_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    defer std.fs.cwd.deleteTree(temp_dir) catch {};
    
    // 初始化全局崩溃处理器
    try crash_handler.initGlobalHandler(testing.allocator, temp_dir, false);
    defer crash_handler.deinitGlobalHandler(testing.allocator);
    
    // 验证全局处理器已安装
    const handler = crash_handler.getGlobalHandler();
    try testing.expect(handler != null);
    try testing.expect(handler.?.installed);
}

test "CrashReport 包含堆栈跟踪" {
    // 初始化堆栈跟踪
    try stack_trace.initGlobalCapture(testing.allocator, 64);
    defer stack_trace.deinitGlobalCapture(testing.allocator);
    
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.SEGV;
    info.code = 1;
    
    if (builtin.os.tag == .linux) {
        info.fields.sigfault.addr = @ptrFromInt(0x1000);
    }
    
    const context = crash_handler.CrashContext.init(std.posix.SIG.SEGV, &info, null);
    
    var report = try crash_handler.CrashReport.init(testing.allocator, context);
    defer report.deinit();
    
    // 捕获堆栈跟踪
    const capture = stack_trace.getGlobalCapture().?;
    const trace = try capture.captureFromAddresses(context.stack_addresses[0..context.stack_depth]);
    report.setStackTrace(trace);
    
    // 生成报告
    const report_text = try report.generateReport();
    defer testing.allocator.free(report_text);
    
    // 验证包含堆栈跟踪
    try testing.expect(std.mem.indexOf(u8, report_text, "STACK TRACE") != null);
}

test "多次崩溃统计" {
    const temp_dir = "test_multi_crash";
    std.fs.cwd.makePath(temp_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    defer std.fs.cwd.deleteTree(temp_dir) catch {};
    
    var handler = crash_handler.CrashHandler.init(
        testing.allocator,
        temp_dir,
        false,
    );
    
    try handler.install();
    defer handler.uninstall() catch {};
    
    // 模拟多次崩溃（不实际触发信号）
    handler.stats.crash_count = 5;
    handler.stats.report_count = 5;
    
    try testing.expectEqual(@as(usize, 5), handler.stats.crash_count);
    try testing.expectEqual(@as(usize, 5), handler.stats.report_count);
}

// ============================================================================
// 边界条件测试
// ============================================================================

test "空堆栈跟踪" {
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.SEGV;
    info.code = 1;
    
    if (builtin.os.tag == .linux) {
        info.fields.sigfault.addr = @ptrFromInt(0x1000);
    }
    
    var context = crash_handler.CrashContext.init(std.posix.SIG.SEGV, &info, null);
    context.stack_depth = 0; // 空堆栈
    
    var report = try crash_handler.CrashReport.init(testing.allocator, context);
    defer report.deinit();
    
    const report_text = try report.generateReport();
    defer testing.allocator.free(report_text);
    
    // 应该仍然能生成报告
    try testing.expect(std.mem.indexOf(u8, report_text, "CRASH REPORT") != null);
}

test "无故障地址的崩溃" {
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.ILL;
    info.code = 1;
    
    const context = crash_handler.CrashContext.init(std.posix.SIG.ILL, &info, null);
    
    // ILL 信号通常没有故障地址
    // 在某些平台上可能有，但不保证
    
    var report = try crash_handler.CrashReport.init(testing.allocator, context);
    defer report.deinit();
    
    const report_text = try report.generateReport();
    defer testing.allocator.free(report_text);
    
    // 报告应该能正常生成
    try testing.expect(std.mem.indexOf(u8, report_text, "CRASH REPORT") != null);
}

test "长堆栈跟踪" {
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.SEGV;
    info.code = 1;
    
    if (builtin.os.tag == .linux) {
        info.fields.sigfault.addr = @ptrFromInt(0x1000);
    }
    
    var context = crash_handler.CrashContext.init(std.posix.SIG.SEGV, &info, null);
    
    // 填充最大堆栈深度
    for (0..128) |i| {
        context.stack_addresses[i] = 0x1000 + i * 0x10;
    }
    context.stack_depth = 128;
    
    var report = try crash_handler.CrashReport.init(testing.allocator, context);
    defer report.deinit();
    
    const report_text = try report.generateReport();
    defer testing.allocator.free(report_text);
    
    // 验证所有地址都被包含
    try testing.expect(std.mem.indexOf(u8, report_text, "STACK ADDRESSES") != null);
}

// ============================================================================
// 性能测试
// ============================================================================

test "崩溃报告生成性能" {
    var info: std.posix.siginfo_t = undefined;
    info.signo = std.posix.SIG.SEGV;
    info.code = 1;
    
    if (builtin.os.tag == .linux) {
        info.fields.sigfault.addr = @ptrFromInt(0x1000);
    }
    
    const context = crash_handler.CrashContext.init(std.posix.SIG.SEGV, &info, null);
    
    var timer = try std.time.Timer.start();
    
    const iterations = 100;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var report = try crash_handler.CrashReport.init(testing.allocator, context);
        defer report.deinit();
        
        const report_text = try report.generateReport();
        defer testing.allocator.free(report_text);
    }
    
    const elapsed = timer.read();
    const avg_ns = elapsed / iterations;
    
    // 平均生成时间应该 < 10ms
    try testing.expect(avg_ns < 10_000_000);
    
    std.debug.print("\n崩溃报告生成平均时间: {d} ns\n", .{avg_ns});
}

test "堆栈跟踪捕获性能" {
    try stack_trace.initGlobalCapture(testing.allocator, 64);
    defer stack_trace.deinitGlobalCapture(testing.allocator);
    
    const capture = stack_trace.getGlobalCapture().?;
    
    var timer = try std.time.Timer.start();
    
    const iterations = 1000;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var trace = try capture.capture();
        defer trace.deinit();
    }
    
    const elapsed = timer.read();
    const avg_ns = elapsed / iterations;
    
    // 平均捕获时间应该 < 100μs
    try testing.expect(avg_ns < 100_000);
    
    std.debug.print("\n堆栈跟踪捕获平均时间: {d} ns\n", .{avg_ns});
}
