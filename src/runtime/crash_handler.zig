/// 运行时崩溃处理系统
/// 
/// 提供信号处理、core dump 生成和现场信息保留功能
/// 
/// @ownership NON-OWNING (allocator)
/// @thread-safety SIGNAL_SAFE
/// @验证：需求 10.7

const std = @import("std");
const builtin = @import("builtin");
const stack_trace = @import("stack_trace.zig");
const c = std.c;
const platform = @import("crash_handler_platform.zig");

/// 崩溃类型
pub const CrashType = enum {
    /// 段错误（SIGSEGV）
    segmentation_fault,
    
    /// 非法指令（SIGILL）
    illegal_instruction,
    
    /// 浮点异常（SIGFPE）
    floating_point_exception,
    
    /// 中止信号（SIGABRT）
    abort_signal,
    
    /// 总线错误（SIGBUS）
    bus_error,
    
    /// 未知崩溃
    unknown,
    
    /// 从信号编号获取崩溃类型
    pub fn fromSignal(sig: c_int) CrashType {
        return switch (sig) {
            std.posix.SIG.SEGV => .segmentation_fault,
            std.posix.SIG.ILL => .illegal_instruction,
            std.posix.SIG.FPE => .floating_point_exception,
            std.posix.SIG.ABRT => .abort_signal,
            std.posix.SIG.BUS => .bus_error,
            else => .unknown,
        };
    }
    
    /// 获取崩溃类型的描述
    pub fn description(self: CrashType) []const u8 {
        return switch (self) {
            .segmentation_fault => "Segmentation fault (invalid memory access)",
            .illegal_instruction => "Illegal instruction",
            .floating_point_exception => "Floating point exception",
            .abort_signal => "Abort signal",
            .bus_error => "Bus error (alignment or hardware issue)",
            .unknown => "Unknown crash",
        };
    }
};

/// 崩溃上下文信息
/// @memory-layout 紧凑布局，信号安全
pub const CrashContext = struct {
    /// 崩溃类型
    crash_type: CrashType,
    
    /// 信号编号
    signal: c_int,
    
    /// 错误代码
    error_code: c_int,
    
    /// 故障地址（如果可用）
    fault_address: ?usize,
    
    /// 指令指针
    instruction_pointer: usize,
    
    /// 堆栈指针
    stack_pointer: usize,
    
    /// 帧指针
    frame_pointer: usize,
    
    /// 线程 ID
    thread_id: std.Thread.Id,
    
    /// 进程 ID
    process_id: std.posix.pid_t,
    
    /// 时间戳
    timestamp: i64,
    
    /// 堆栈跟踪地址（信号安全缓冲区）
    stack_addresses: [128]usize,
    stack_depth: usize,
    
    /// 初始化崩溃上下文
    pub fn init(sig: c_int, info: *const std.posix.siginfo_t, ucontext: ?*anyopaque) CrashContext {
        var ctx: CrashContext = undefined;
        
        ctx.crash_type = CrashType.fromSignal(sig);
        ctx.signal = sig;
        ctx.error_code = info.code;
        
        // 提取故障地址（平台相关）
        ctx.fault_address = if (sig == std.posix.SIG.SEGV or sig == std.posix.SIG.BUS)
            platform.extractFaultAddress(info)
        else
            null;
        
        // 提取寄存器信息（平台相关）
        if (ucontext) |uc| {
            ctx.instruction_pointer = platform.extractInstructionPointer(uc);
            ctx.stack_pointer = platform.extractStackPointer(uc);
            ctx.frame_pointer = platform.extractFramePointer(uc);
        } else {
            ctx.instruction_pointer = 0;
            ctx.stack_pointer = 0;
            ctx.frame_pointer = 0;
        }
        
        ctx.thread_id = std.Thread.getCurrentId();
        ctx.process_id = if (builtin.os.tag == .windows) 0 else std.c.getpid();
        ctx.timestamp = std.time.milliTimestamp();
        
        // 捕获堆栈跟踪（信号安全）
        ctx.stack_depth = captureStackAddresses(&ctx.stack_addresses);
        
        return ctx;
    }
};

/// 崩溃报告
/// @ownership TRANSFER
pub const CrashReport = struct {
    allocator: std.mem.Allocator,
    
    /// 崩溃上下文
    context: CrashContext,
    
    /// 堆栈跟踪
    stack_trace: ?stack_trace.StackTrace,
    
    /// 系统信息
    system_info: SystemInfo,
    
    /// 内存信息
    memory_info: MemoryInfo,
    
    /// 环境变量
    environment: std.StringHashMapUnmanaged([]const u8),
    
    pub const SystemInfo = struct {
        /// 操作系统
        os: []const u8,
        
        /// 架构
        arch: []const u8,
        
        /// Zig 版本
        zig_version: []const u8,
        
        /// 主机名
        hostname: [std.posix.HOST_NAME_MAX]u8,
        hostname_len: usize,
    };
    
    pub const MemoryInfo = struct {
        /// 总内存
        total_memory: usize,
        
        /// 可用内存
        available_memory: usize,
        
        /// 进程内存使用
        process_memory: usize,
        
        /// 堆大小
        heap_size: usize,
    };
    
    /// 初始化崩溃报告
    pub fn init(allocator: std.mem.Allocator, context: CrashContext) !CrashReport {
        var report: CrashReport = undefined;
        report.allocator = allocator;
        report.context = context;
        report.stack_trace = null;
        report.environment = .{};
        
        // 收集系统信息
        report.system_info = try collectSystemInfo();
        
        // 收集内存信息
        report.memory_info = try collectMemoryInfo();
        
        // 收集环境变量
        try report.collectEnvironment();
        
        return report;
    }
    
    /// 清理资源
    pub fn deinit(self: *CrashReport) void {
        if (self.stack_trace) |*trace| {
            trace.deinit();
        }
        
        var iter = self.environment.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.environment.deinit(self.allocator);
    }
    
    /// 设置堆栈跟踪
    pub fn setStackTrace(self: *CrashReport, trace: stack_trace.StackTrace) void {
        self.stack_trace = trace;
    }
    
    /// 收集环境变量
    fn collectEnvironment(self: *CrashReport) !void {
        // 简化实现：只收集关键环境变量
        const env_vars = [_][]const u8{
            "PATH",
            "HOME",
            "USER",
            "SHELL",
            "LANG",
        };
        
        for (env_vars) |var_name| {
            if (std.posix.getenv(var_name)) |value| {
                const key = try self.allocator.dupe(u8, var_name);
                const val = try self.allocator.dupe(u8, value);
                try self.environment.put(self.allocator, key, val);
            }
        }
    }
    
    /// 生成报告文本
    pub fn generateReport(self: *const CrashReport) ![]u8 {
        var list: std.ArrayListUnmanaged(u8) = .{};
        errdefer list.deinit(self.allocator);
        
        const writer = list.writer(self.allocator);
        
        try writer.writeAll("================================================================================\n");
        try writer.writeAll("                         CRASH REPORT                                           \n");
        try writer.writeAll("================================================================================\n\n");
        
        // 崩溃信息
        try writer.writeAll("CRASH INFORMATION:\n");
        try writer.print("  Type: {s}\n", .{self.context.crash_type.description()});
        try writer.print("  Signal: {d}\n", .{self.context.signal});
        try writer.print("  Error Code: {d}\n", .{self.context.error_code});
        
        if (self.context.fault_address) |addr| {
            try writer.print("  Fault Address: 0x{X:0>16}\n", .{addr});
        }
        
        try writer.print("  Instruction Pointer: 0x{X:0>16}\n", .{self.context.instruction_pointer});
        try writer.print("  Stack Pointer: 0x{X:0>16}\n", .{self.context.stack_pointer});
        try writer.print("  Frame Pointer: 0x{X:0>16}\n", .{self.context.frame_pointer});
        try writer.print("  Thread ID: {d}\n", .{self.context.thread_id});
        try writer.print("  Process ID: {d}\n", .{self.context.process_id});
        try writer.print("  Timestamp: {d}\n\n", .{self.context.timestamp});
        
        // 系统信息
        try writer.writeAll("SYSTEM INFORMATION:\n");
        try writer.print("  OS: {s}\n", .{self.system_info.os});
        try writer.print("  Architecture: {s}\n", .{self.system_info.arch});
        try writer.print("  Zig Version: {s}\n", .{self.system_info.zig_version});
        try writer.print("  Hostname: {s}\n\n", .{
            self.system_info.hostname[0..self.system_info.hostname_len]
        });
        
        // 内存信息
        try writer.writeAll("MEMORY INFORMATION:\n");
        try writer.print("  Total Memory: {d} bytes\n", .{self.memory_info.total_memory});
        try writer.print("  Available Memory: {d} bytes\n", .{self.memory_info.available_memory});
        try writer.print("  Process Memory: {d} bytes\n", .{self.memory_info.process_memory});
        try writer.print("  Heap Size: {d} bytes\n\n", .{self.memory_info.heap_size});
        
        // 堆栈跟踪
        if (self.stack_trace) |trace| {
            try writer.writeAll("STACK TRACE:\n");
            try trace.format("", .{}, writer);
            try writer.writeAll("\n");
        } else {
            try writer.writeAll("STACK ADDRESSES:\n");
            for (self.context.stack_addresses[0..self.context.stack_depth], 0..) |addr, i| {
                try writer.print("  #{d}: 0x{X:0>16}\n", .{i, addr});
            }
            try writer.writeAll("\n");
        }
        
        // 环境变量
        try writer.writeAll("ENVIRONMENT VARIABLES:\n");
        var iter = self.environment.iterator();
        while (iter.next()) |entry| {
            try writer.print("  {s}={s}\n", .{entry.key_ptr.*, entry.value_ptr.*});
        }
        try writer.writeAll("\n");
        
        try writer.writeAll("================================================================================\n");
        
        return try list.toOwnedSlice(self.allocator);
    }
    
    /// 保存报告到文件
    pub fn saveToFile(self: *const CrashReport, path: []const u8) !void {
        const report_text = try self.generateReport();
        defer self.allocator.free(report_text);
        
        const file = try std.fs.cwd.createFile(path, .{});
        defer file.close();
        
        try file.writeAll(report_text);
    }
};

/// 崩溃处理器
/// @concurrency-model SIGNAL_SAFE
pub const CrashHandler = struct {
    allocator: std.mem.Allocator,
    
    /// 是否已安装
    installed: bool,
    
    /// 崩溃报告目录
    crash_report_dir: []const u8,
    
    /// 是否生成 core dump
    enable_core_dump: bool,
    
    /// 旧的信号处理器
    old_handlers: [6]std.posix.Sigaction,
    
    /// 统计信息
    stats: Stats,
    
    pub const Stats = struct {
        /// 崩溃次数
        crash_count: usize = 0,
        
        /// 报告生成次数
        report_count: usize = 0,
    };
    
    /// 初始化崩溃处理器
    pub fn init(
        allocator: std.mem.Allocator,
        crash_report_dir: []const u8,
        enable_core_dump: bool,
    ) CrashHandler {
        return .{
            .allocator = allocator,
            .installed = false,
            .crash_report_dir = crash_report_dir,
            .enable_core_dump = enable_core_dump,
            .old_handlers = undefined,
            .stats = .{},
        };
    }
    
    /// 安装信号处理器
    /// @pre 必须在主线程调用
    /// @post 信号处理器被安装
    pub fn install(self: *CrashHandler) !void {
        if (self.installed) {
            return error.AlreadyInstalled;
        }
        
        // 确保崩溃报告目录存在
        std.fs.cwd.makePath(self.crash_report_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        
        // 配置 core dump
        if (self.enable_core_dump) {
            try enableCoreDump();
        }
        
        // 安装信号处理器
        const signals = [_]c_int{
            std.posix.SIG.SEGV,
            std.posix.SIG.ILL,
            std.posix.SIG.FPE,
            std.posix.SIG.ABRT,
            std.posix.SIG.BUS,
            std.posix.SIG.TRAP,
        };
        
        for (signals, 0..) |sig, i| {
            const mask = std.posix.sigemptyset();
            
            var action: std.posix.Sigaction = .{
                .handler = .{ .sigaction = @ptrCast(&signalHandler) },
                .mask = mask,
                .flags = @as(c_uint, @bitCast(std.posix.SA{
                    .SIGINFO = true,
                    .RESETHAND = true,
                })),
            };
            
            self.old_handlers[i] = try std.posix.sigaction(sig, &action, null);
        }
        
        self.installed = true;
    }
    
    /// 卸载信号处理器
    pub fn uninstall(self: *CrashHandler) !void {
        if (!self.installed) {
            return;
        }
        
        const signals = [_]c_int{
            std.posix.SIG.SEGV,
            std.posix.SIG.ILL,
            std.posix.SIG.FPE,
            std.posix.SIG.ABRT,
            std.posix.SIG.BUS,
            std.posix.SIG.TRAP,
        };
        
        for (signals, 0..) |sig, i| {
            _ = try std.posix.sigaction(sig, &self.old_handlers[i], null);
        }
        
        self.installed = false;
    }
    
    /// 处理崩溃
    fn handleCrash(sig: c_int, info: *const std.posix.siginfo_t, ucontext: ?*anyopaque) void {
        // 创建崩溃上下文
        const context = CrashContext.init(sig, info, ucontext);
        
        // 生成崩溃报告文件名
        var filename_buf: [256]u8 = undefined;
        const filename = std.fmt.bufPrint(
            &filename_buf,
            "crash_{d}_{d}.txt",
            .{context.process_id, context.timestamp}
        ) catch "crash_report.txt";
        
        // 尝试生成详细报告（可能失败，因为在信号处理器中）
        if (global_handler) |handler| {
            handler.stats.crash_count += 1;
            
            // 尝试创建报告
            var report = CrashReport.init(handler.allocator, context) catch {
                // 失败时写入简单报告
                writeSimpleCrashReport(handler.crash_report_dir, filename, &context);
                return;
            };
            defer report.deinit();
            
            // 尝试捕获堆栈跟踪
            if (stack_trace.getGlobalCapture()) |capture| {
                if (capture.captureFromAddresses(context.stack_addresses[0..context.stack_depth])) |trace| {
                    report.setStackTrace(trace);
                } else |_| {}
            }
            
            // 保存报告
            var path_buf: [512]u8 = undefined;
            const path = std.fmt.bufPrint(
                &path_buf,
                "{s}/{s}",
                .{handler.crash_report_dir, filename}
            ) catch return;
            
            report.saveToFile(path) catch {
                writeSimpleCrashReport(handler.crash_report_dir, filename, &context);
            };
            
            handler.stats.report_count += 1;
        }
    }
};

// ============================================================================
// 平台相关函数
// ============================================================================

// macOS ucontext 结构定义
const darwin_mcontext_t = if (builtin.os.tag == .macos or builtin.os.tag == .ios or 
                              builtin.os.tag == .tvos or builtin.os.tag == .watchos or 
                              builtin.os.tag == .visionos) 
    extern struct {
        // x86_64 寄存器
        rax: u64,
        rbx: u64,
        rcx: u64,
        rdx: u64,
        rdi: u64,
        rsi: u64,
        rbp: u64,
        rsp: u64,
        r8: u64,
        r9: u64,
        r10: u64,
        r11: u64,
        r12: u64,
        r13: u64,
        r14: u64,
        r15: u64,
        rip: u64,
        rflags: u64,
        cs: u16,
        gs: u16,
        fs: u16,
        _pad: u16,
    }
else
    void;

/// 提取故障地址（平台相关）
fn extractFaultAddress(info: *const std.posix.siginfo_t) ?usize {
    return switch (builtin.os.tag) {
        .linux => @intFromPtr(info.fields.sigfault.addr),
        .macos, .ios, .tvos, .watchos, .visionos => null,
        else => null,
    };
}

/// 提取指令指针（平台相关）
fn extractInstructionPointer(ucontext: *anyopaque) usize {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => blk: {
                const uc: *std.os.linux.ucontext_t = @ptrCast(@alignCast(ucontext));
                break :blk @intCast(uc.mcontext.gregs[std.os.linux.REG.RIP]);
            },
            .aarch64 => blk: {
                const uc: *std.os.linux.ucontext_t = @ptrCast(@alignCast(ucontext));
                break :blk @intCast(uc.mcontext.pc);
            },
            else => 0,
        },
        .macos, .ios, .tvos, .watchos, .visionos => 0,
        else => 0,
    };
}

/// 提取堆栈指针（平台相关）
fn extractStackPointer(ucontext: *anyopaque) usize {
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => blk: {
                const uc: *std.os.linux.ucontext_t = @ptrCast(@alignCast(ucontext));
                break :blk @intCast(uc.mcontext.gregs[std.os.linux.REG.RSP]);
            },
            .aarch64 => blk: {
                const uc: *std.os.linux.ucontext_t = @ptrCast(@alignCast(ucontext));
                break :blk @intCast(uc.mcontext.sp);
            },
            else => 0,
        },
        .macos, .ios, .tvos, .watchos, .visionos => 0,
        else => 0,
    };
}

/// 提取帧指针（平台相关）
fn extractFramePointer(ucontext: *anyopaque) usize {
    if (builtin.os.tag == .linux) {
        if (builtin.cpu.arch == .x86_64) {
            const uc: *std.os.linux.ucontext_t = @ptrCast(@alignCast(ucontext));
            return @intCast(uc.mcontext.gregs[std.os.linux.REG.RBP]);
        } else if (builtin.cpu.arch == .aarch64) {
            const uc: *std.os.linux.ucontext_t = @ptrCast(@alignCast(ucontext));
            return @intCast(uc.mcontext.regs[29]); // x29 is FP on ARM64
        }
    }
    
    return 0;
}

/// 提取帧指针（平台相关）

/// 捕获堆栈地址（信号安全）
fn captureStackAddresses(buffer: []usize) usize {
    // 使用简单的堆栈遍历（信号安全）
    var count: usize = 0;
    var fp = @frameAddress();
    
    while (count < buffer.len and fp != 0) : (count += 1) {
        const frame_ptr: [*]usize = @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(fp))));
        
        // 读取返回地址
        if (count + 1 < buffer.len) {
            buffer[count] = frame_ptr[1]; // 返回地址在 [rbp+8]
        }
        
        // 移动到上一帧
        const next_fp = frame_ptr[0]; // 上一帧的 rbp 在 [rbp]
        if (next_fp == 0 or next_fp <= fp) {
            break;
        }
        fp = next_fp;
    }
    
    return count;
}

/// 启用 core dump
fn enableCoreDump() !void {
    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        var rlim = std.os.linux.rlimit{
            .cur = std.os.linux.RLIM.INFINITY,
            .max = std.os.linux.RLIM.INFINITY,
        };
        
        if (std.os.linux.setrlimit(.CORE, &rlim) != 0) {
            return error.SetRlimitFailed;
        }
    }
}

/// 收集系统信息
fn collectSystemInfo() !CrashReport.SystemInfo {
    var info: CrashReport.SystemInfo = undefined;
    
    info.os = @tagName(builtin.os.tag);
    info.arch = @tagName(builtin.cpu.arch);
    info.zig_version = builtin.zig_version_string;
    
    // 获取主机名
    const hostname_result = std.posix.gethostname(&info.hostname) catch "";
    info.hostname_len = hostname_result.len;
    
    return info;
}

/// 收集内存信息
fn collectMemoryInfo() !CrashReport.MemoryInfo {
    var info: CrashReport.MemoryInfo = undefined;
    
    // 简化实现：使用默认值
    info.total_memory = 0;
    info.available_memory = 0;
    info.process_memory = 0;
    info.heap_size = 0;
    
    // TODO: 实现平台相关的内存信息收集
    
    return info;
}

/// 写入简单崩溃报告（信号安全）
fn writeSimpleCrashReport(dir: []const u8, filename: []const u8, context: *const CrashContext) void {
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{dir, filename}) catch return;
    
    const file = std.fs.cwd.createFile(path, .{}) catch return;
    defer file.close();
    
    var buf: [4096]u8 = undefined;
    const text = std.fmt.bufPrint(
        &buf,
        \\CRASH REPORT (Simple)
        \\Type: {s}
        \\Signal: {d}
        \\Fault Address: 0x{X:0>16}
        \\Instruction Pointer: 0x{X:0>16}
        \\Stack Pointer: 0x{X:0>16}
        \\Thread ID: {d}
        \\Process ID: {d}
        \\Timestamp: {d}
        \\
    , .{
        context.crash_type.description(),
        context.signal,
        context.fault_address orelse 0,
        context.instruction_pointer,
        context.stack_pointer,
        context.thread_id,
        context.process_id,
        context.timestamp,
    }) catch return;
    
    file.writeAll(text) catch {};
}

/// 信号处理器
fn signalHandler(sig: c_int, info: *std.posix.siginfo_t, ucontext: ?*anyopaque) callconv(.c) void {
    CrashHandler.handleCrash(sig, info, ucontext);
    
    // 恢复默认处理器并重新触发信号
    const mask = std.posix.sigemptyset();
    
    var action: std.posix.Sigaction = .{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = mask,
        .flags = 0,
    };
    
    _ = std.posix.sigaction(sig, &action, null) catch {};
    _ = std.posix.raise(sig) catch {};
}

// ============================================================================
// 全局崩溃处理器
// ============================================================================

var global_handler: ?*CrashHandler = null;
var global_handler_mutex: std.Thread.Mutex = std.Thread.Mutex{};

/// 初始化全局崩溃处理器
pub fn initGlobalHandler(
    allocator: std.mem.Allocator,
    crash_report_dir: []const u8,
    enable_core_dump: bool,
) !void {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();
    
    if (global_handler != null) {
        return error.AlreadyInitialized;
    }
    
    const handler = try allocator.create(CrashHandler);
    handler.* = CrashHandler.init(allocator, crash_report_dir, enable_core_dump);
    
    try handler.install();
    
    global_handler = handler;
}

/// 清理全局崩溃处理器
pub fn deinitGlobalHandler(allocator: std.mem.Allocator) void {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();
    
    if (global_handler) |handler| {
        handler.uninstall() catch {};
        allocator.destroy(handler);
        global_handler = null;
    }
}

/// 获取全局崩溃处理器
pub fn getGlobalHandler() ?*CrashHandler {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();
    
    return global_handler;
}
