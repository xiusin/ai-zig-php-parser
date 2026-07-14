/// JIT 编译失败回退机制
///
/// 本模块实现了 JIT 编译失败时的错误捕获、日志记录和回退到解释执行的机制。
///
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED (单线程)
/// @memory-protection 所有错误路径都使用 errdefer 确保资源释放
const std = @import("std");
const builtin = @import("builtin");
const time_compat = @import("runtime").time_compat;

/// JIT 编译错误类型
pub const JITCompilationError = error{
    /// 编译失败 - 通用编译错误
    CompilationFailed,

    /// 不支持的指令
    UnsupportedInstruction,

    /// 寄存器分配失败
    RegisterAllocationFailed,

    /// 代码生成失败
    CodeGenerationFailed,

    /// 无效的目标架构
    InvalidTargetArchitecture,

    /// 代码缓存已满
    CodeCacheFull,

    /// 无效的缓存条目
    InvalidCacheEntry,

    /// 内存不足
    OutOfMemory,

    /// 类型推断失败
    TypeInferenceFailed,

    /// 优化失败
    OptimizationFailed,
};

/// 编译失败原因
pub const CompilationFailureReason = enum {
    unsupported_instruction,
    register_allocation_failed,
    code_generation_failed,
    invalid_target_arch,
    code_cache_full,
    out_of_memory,
    type_inference_failed,
    optimization_failed,
    unknown,

    /// 从错误类型转换
    pub fn fromError(err: anyerror) CompilationFailureReason {
        return switch (err) {
            error.UnsupportedInstruction => .unsupported_instruction,
            error.RegisterAllocationFailed => .register_allocation_failed,
            error.CodeGenerationFailed => .code_generation_failed,
            error.InvalidTargetArchitecture => .invalid_target_arch,
            error.CodeCacheFull => .code_cache_full,
            error.OutOfMemory => .out_of_memory,
            error.TypeInferenceFailed => .type_inference_failed,
            error.OptimizationFailed => .optimization_failed,
            else => .unknown,
        };
    }

    /// 获取错误描述
    pub fn description(self: CompilationFailureReason) []const u8 {
        return switch (self) {
            .unsupported_instruction => "遇到不支持的指令",
            .register_allocation_failed => "寄存器分配失败",
            .code_generation_failed => "代码生成失败",
            .invalid_target_arch => "无效的目标架构",
            .code_cache_full => "代码缓存已满",
            .out_of_memory => "内存不足",
            .type_inference_failed => "类型推断失败",
            .optimization_failed => "优化失败",
            .unknown => "未知错误",
        };
    }
};

/// 编译失败记录
pub const CompilationFailureRecord = struct {
    /// 函数名称
    function_name: []const u8,

    /// 失败原因
    reason: CompilationFailureReason,

    /// 错误消息
    error_message: []const u8,

    /// 失败时间戳（纳秒）
    timestamp_ns: i64,

    /// 失败的指令偏移（如果适用）
    instruction_offset: ?usize,

    /// 堆栈跟踪（如果可用）
    stack_trace: ?[]const u8,

    /// 创建失败记录
    pub fn create(
        allocator: std.mem.Allocator,
        function_name: []const u8,
        reason: CompilationFailureReason,
        error_message: []const u8,
        instruction_offset: ?usize,
    ) !CompilationFailureRecord {
        const name_copy = try allocator.dupe(u8, function_name);
        errdefer allocator.free(name_copy);

        const msg_copy = try allocator.dupe(u8, error_message);
        errdefer allocator.free(msg_copy);

        return CompilationFailureRecord{
            .function_name = name_copy,
            .reason = reason,
            .error_message = msg_copy,
            .timestamp_ns = @intCast(time_compat.nanoTimestamp()),
            .instruction_offset = instruction_offset,
            .stack_trace = null,
        };
    }

    /// 释放资源
    pub fn deinit(self: *CompilationFailureRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.function_name);
        allocator.free(self.error_message);
        if (self.stack_trace) |trace| {
            allocator.free(trace);
        }
    }
};

/// 编译失败日志记录器
/// @concurrency-model ISOLATED
pub const CompilationLogger = struct {
    allocator: std.mem.Allocator,

    /// 失败记录列表
    failure_records: std.ArrayListUnmanaged(CompilationFailureRecord),

    /// 日志文件路径（可选）
    log_file_path: ?[]const u8,

    /// 日志文件句柄
    log_file: ?std.Io.File,

    /// 是否启用详细日志
    verbose: bool,

    /// 初始化日志记录器
    /// @pre allocator 必须有效
    /// @post 返回初始化的日志记录器
    pub fn init(allocator: std.mem.Allocator) CompilationLogger {
        return .{
            .allocator = allocator,
            .failure_records = .{},
            .log_file_path = null,
            .log_file = null,
            .verbose = false,
        };
    }

    /// 初始化日志记录器并指定日志文件
    pub fn initWithFile(
        allocator: std.mem.Allocator,
        log_file_path: []const u8,
    ) !CompilationLogger {
        const path_copy = try allocator.dupe(u8, log_file_path);
        errdefer allocator.free(path_copy);

        const io = std.Io.Threaded.global_single_threaded.io();
        const file = try std.Io.Dir.cwd().createFile(io, log_file_path, .{
            .truncate = false,
            .read = true,
        });
        errdefer file.close(io);

        // 移动到文件末尾以追加
        _ = std.os.linux.lseek(file.handle, 0, std.posix.SEEK.END);

        return .{
            .allocator = allocator,
            .failure_records = .{},
            .log_file_path = path_copy,
            .log_file = file,
            .verbose = false,
        };
    }

    /// 设置详细日志模式
    pub fn setVerbose(self: *CompilationLogger, verbose: bool) void {
        self.verbose = verbose;
    }

    /// 释放资源
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *CompilationLogger) void {
        for (self.failure_records.items) |*record| {
            record.deinit(self.allocator);
        }
        self.failure_records.deinit(self.allocator);

        if (self.log_file_path) |path| {
            self.allocator.free(path);
        }

        if (self.log_file) |file| {
            file.close(std.Io.Threaded.global_single_threaded.io());
        }
    }

    /// 记录编译失败
    /// @pre function_name 和 error_message 必须有效
    /// @post 失败记录被添加到列表并写入日志文件（如果有）
    pub fn logFailure(
        self: *CompilationLogger,
        function_name: []const u8,
        err: anyerror,
        error_message: []const u8,
        instruction_offset: ?usize,
    ) !void {
        const reason = CompilationFailureReason.fromError(err);

        // 创建失败记录
        var record = try CompilationFailureRecord.create(
            self.allocator,
            function_name,
            reason,
            error_message,
            instruction_offset,
        );
        errdefer record.deinit(self.allocator);

        // 添加到列表
        try self.failure_records.append(self.allocator, record);

        // 写入日志文件
        if (self.log_file) |file| {
            const last_record = &self.failure_records.items[self.failure_records.items.len - 1];
            try self.writeToFile(file, last_record);
        }

        // 如果启用详细模式，打印到标准错误
        if (self.verbose) {
            const last_record = &self.failure_records.items[self.failure_records.items.len - 1];
            try self.printToStderr(last_record);
        }
    }

    /// 写入日志文件
    fn writeToFile(self: *CompilationLogger, file: std.Io.File, record: *const CompilationFailureRecord) !void {
        _ = self;
        const io = std.Io.Threaded.global_single_threaded.io();

        var buf: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const allocator = fba.allocator();

        const msg = try std.fmt.allocPrint(allocator, "[{d}] JIT 编译失败\n  函数: {s}\n  原因: {s}\n  错误: {s}\n", .{
            record.timestamp_ns,
            record.function_name,
            record.reason.description(),
            record.error_message,
        });

        try file.writeStreamingAll(io, msg);

        if (record.instruction_offset) |offset| {
            const offset_msg = try std.fmt.allocPrint(allocator, "  指令偏移: {d}\n", .{offset});
            try file.writeStreamingAll(io, offset_msg);
        }

        try file.writeStreamingAll(io, "\n");
    }

    /// 打印到标准错误
    fn printToStderr(self: *CompilationLogger, record: *const CompilationFailureRecord) !void {
        _ = self;

        std.debug.print("[JIT 编译失败] 函数: {s}, 原因: {s}\n", .{
            record.function_name,
            record.reason.description(),
        });

        if (record.instruction_offset) |offset| {
            std.debug.print("  指令偏移: {d}\n", .{offset});
        }
    }

    /// 获取失败统计
    pub fn getStatistics(self: *const CompilationLogger) CompilationStatistics {
        var stats = CompilationStatistics{};

        for (self.failure_records.items) |record| {
            stats.total_failures += 1;

            switch (record.reason) {
                .unsupported_instruction => stats.unsupported_instruction_count += 1,
                .register_allocation_failed => stats.register_allocation_failures += 1,
                .code_generation_failed => stats.code_generation_failures += 1,
                .invalid_target_arch => stats.invalid_arch_count += 1,
                .code_cache_full => stats.cache_full_count += 1,
                .out_of_memory => stats.out_of_memory_count += 1,
                .type_inference_failed => stats.type_inference_failures += 1,
                .optimization_failed => stats.optimization_failures += 1,
                .unknown => stats.unknown_failures += 1,
            }
        }

        return stats;
    }

    /// 清除所有失败记录
    pub fn clear(self: *CompilationLogger) void {
        for (self.failure_records.items) |*record| {
            record.deinit(self.allocator);
        }
        self.failure_records.clearRetainingCapacity();
    }
};

/// 编译统计信息
pub const CompilationStatistics = struct {
    total_failures: usize = 0,
    unsupported_instruction_count: usize = 0,
    register_allocation_failures: usize = 0,
    code_generation_failures: usize = 0,
    invalid_arch_count: usize = 0,
    cache_full_count: usize = 0,
    out_of_memory_count: usize = 0,
    type_inference_failures: usize = 0,
    optimization_failures: usize = 0,
    unknown_failures: usize = 0,

    /// 打印统计信息
    pub fn print(self: *const CompilationStatistics, writer: anytype) !void {
        try writer.print("=== JIT 编译失败统计 ===\n", .{});
        try writer.print("总失败次数: {d}\n", .{self.total_failures});
        try writer.print("  不支持的指令: {d}\n", .{self.unsupported_instruction_count});
        try writer.print("  寄存器分配失败: {d}\n", .{self.register_allocation_failures});
        try writer.print("  代码生成失败: {d}\n", .{self.code_generation_failures});
        try writer.print("  无效架构: {d}\n", .{self.invalid_arch_count});
        try writer.print("  缓存已满: {d}\n", .{self.cache_full_count});
        try writer.print("  内存不足: {d}\n", .{self.out_of_memory_count});
        try writer.print("  类型推断失败: {d}\n", .{self.type_inference_failures});
        try writer.print("  优化失败: {d}\n", .{self.optimization_failures});
        try writer.print("  未知错误: {d}\n", .{self.unknown_failures});
    }
};

/// JIT 编译回退管理器
/// @concurrency-model ISOLATED
pub const FallbackManager = struct {
    allocator: std.mem.Allocator,

    /// 日志记录器
    logger: CompilationLogger,

    /// 是否启用回退
    fallback_enabled: bool,

    /// 回退计数器
    fallback_count: usize,

    /// 初始化回退管理器
    pub fn init(allocator: std.mem.Allocator) FallbackManager {
        return .{
            .allocator = allocator,
            .logger = CompilationLogger.init(allocator),
            .fallback_enabled = true,
            .fallback_count = 0,
        };
    }

    /// 初始化回退管理器并指定日志文件
    pub fn initWithLogger(
        allocator: std.mem.Allocator,
        log_file_path: []const u8,
    ) !FallbackManager {
        return .{
            .allocator = allocator,
            .logger = try CompilationLogger.initWithFile(allocator, log_file_path),
            .fallback_enabled = true,
            .fallback_count = 0,
        };
    }

    /// 释放资源
    pub fn deinit(self: *FallbackManager) void {
        self.logger.deinit();
    }

    /// 启用/禁用回退
    pub fn setFallbackEnabled(self: *FallbackManager, enabled: bool) void {
        self.fallback_enabled = enabled;
    }

    /// 设置详细日志模式
    pub fn setVerbose(self: *FallbackManager, verbose: bool) void {
        self.logger.setVerbose(verbose);
    }

    /// 处理编译失败并回退
    /// @pre function_name 必须有效
    /// @post 记录失败并返回是否应该回退到解释执行
    pub fn handleCompilationFailure(
        self: *FallbackManager,
        function_name: []const u8,
        err: anyerror,
        error_message: []const u8,
        instruction_offset: ?usize,
    ) !bool {
        // 记录失败
        try self.logger.logFailure(
            function_name,
            err,
            error_message,
            instruction_offset,
        );

        // 增加回退计数
        self.fallback_count += 1;

        // 返回是否应该回退
        return self.fallback_enabled;
    }

    /// 获取回退计数
    pub fn getFallbackCount(self: *const FallbackManager) usize {
        return self.fallback_count;
    }

    /// 获取编译统计
    pub fn getStatistics(self: *const FallbackManager) CompilationStatistics {
        return self.logger.getStatistics();
    }

    /// 重置统计
    pub fn resetStatistics(self: *FallbackManager) void {
        self.logger.clear();
        self.fallback_count = 0;
    }
};
