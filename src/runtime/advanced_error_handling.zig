const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// 高级错误处理架构
/// 实现错误分类和错误恢复策略

// ============================================================================
// 错误分类体系
// ============================================================================

/// 错误类型分类
/// 错误类型
/// ├── 编译时错误
/// │   ├── 词法错误（Lexer Error）
/// │   ├── 语法错误（Parse Error）
/// │   └── 语义错误（Semantic Error）
/// ├── 运行时错误
/// │   ├── 类型错误（Type Error）
/// │   ├── 参数错误（Argument Error）
/// │   ├── 算术错误（Arithmetic Error）
/// │   └── 内存错误（Memory Error）
/// └── 用户错误
///     ├── 逻辑错误（Logic Error）
///     └── 业务错误（Business Error）
pub const ErrorType = enum {
    // 编译时错误
    lexer_error,
    parse_error,
    semantic_error,

    // 运行时错误
    type_error,
    argument_error,
    arithmetic_error,
    memory_error,

    // 用户错误
    logic_error,
    business_error,

    // 严重错误
    fatal_error,
    system_error,
};

pub const ErrorSeverity = enum {
    info,
    warning,
    err, // 重命名以避免与关键字冲突
    critical,
    fatal,
};

pub const ErrorContext = struct {
    error_type: ErrorType,
    severity: ErrorSeverity,
    message: []const u8,
    file: []const u8,
    line: u32,
    column: u32,
    source_code: ?[]const u8,
    suggestions: std.ArrayListUnmanaged([]const u8),
    related_errors: std.ArrayListUnmanaged(*ErrorInfo),
    timestamp: i64,
    stack_trace: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, error_type: ErrorType, message: []const u8, file: []const u8, line: u32) ErrorContext {
        _ = allocator; // 标记参数为未使用
        return .{
            .error_type = error_type,
            .severity = getSeverityForType(error_type),
            .message = message,
            .file = file,
            .line = line,
            .column = 0,
            .source_code = null,
            .suggestions = .{},
            .related_errors = .{},
            .timestamp = std.time.timestamp(),
            .stack_trace = null,
        };
    }

    pub fn deinit(self: *ErrorContext, allocator: std.mem.Allocator) void {
        self.suggestions.deinit(allocator);
        for (self.related_errors.items) |err| {
            err.deinit(allocator);
            allocator.destroy(err);
        }
        self.related_errors.deinit(allocator);
        if (self.stack_trace) |trace| {
            allocator.free(trace);
        }
        if (self.source_code) |code| {
            allocator.free(code);
        }
    }

    pub fn addSuggestion(self: *ErrorContext, allocator: std.mem.Allocator, suggestion: []const u8) !void {
        const owned_suggestion = try allocator.dupe(u8, suggestion);
        try self.suggestions.append(allocator, owned_suggestion);
    }

    pub fn addRelatedError(self: *ErrorContext, allocator: std.mem.Allocator, related: *ErrorInfo) !void {
        try self.related_errors.append(allocator, related);
    }

    pub fn setSourceCode(self: *ErrorContext, allocator: std.mem.Allocator, code: []const u8) !void {
        if (self.source_code) |old_code| {
            allocator.free(old_code);
        }
        self.source_code = try allocator.dupe(u8, code);
    }

    pub fn setStackTrace(self: *ErrorContext, allocator: std.mem.Allocator, trace: []const u8) !void {
        if (self.stack_trace) |old_trace| {
            allocator.free(old_trace);
        }
        self.stack_trace = try allocator.dupe(u8, trace);
    }

    fn getSeverityForType(error_type: ErrorType) ErrorSeverity {
        return switch (error_type) {
            .lexer_error, .parse_error, .semantic_error => .err,
            .type_error, .argument_error, .arithmetic_error => .err,
            .memory_error => .critical,
            .logic_error, .business_error => .warning,
            .fatal_error, .system_error => .fatal,
        };
    }

    pub fn format(self: *const ErrorContext, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        try writer.print("{s} in {s}:{d}:{d}\n", .{
            @tagName(self.error_type),
            self.file,
            self.line,
            self.column,
        });

        try writer.print("  {s}\n", .{self.message});

        if (self.source_code) |code| {
            try writer.print("  Code: {s}\n", .{code});
        }

        if (self.suggestions.items.len > 0) {
            try writer.print("  Suggestions:\n", .{});
            for (self.suggestions.items) |suggestion| {
                try writer.print("    - {s}\n", .{suggestion});
            }
        }

        if (self.stack_trace) |trace| {
            try writer.print("  Stack trace:\n{s}\n", .{trace});
        }

        return buffer.toOwnedSlice(allocator);
    }
};

pub const ErrorInfo = struct {
    context: ErrorContext,
    recovery_action: ?ErrorRecoveryAction,
    error_id: u64,

    pub fn init(allocator: std.mem.Allocator, error_type: ErrorType, message: []const u8, file: []const u8, line: u32) ErrorInfo {
        return .{
            .context = ErrorContext.init(allocator, error_type, message, file, line),
            .recovery_action = null,
            .error_id = std.hash.Wyhash.hash(0, message) ^ @as(u64, @intCast(std.time.timestamp())),
        };
    }

    pub fn deinit(self: *ErrorInfo, allocator: std.mem.Allocator) void {
        self.context.deinit(allocator);
    }

    pub fn setRecoveryAction(self: *ErrorInfo, action: ErrorRecoveryAction) void {
        self.recovery_action = action;
    }
};

// ============================================================================
// 错误恢复策略
// ============================================================================

pub const ErrorRecoveryAction = union(enum) {
    /// 跳过到下一个同步点
    skip_to_sync_point: struct {
        sync_token: []const u8,
    },

    /// 插入缺失的令牌
    insert_token: struct {
        token_type: []const u8,
        token_value: []const u8,
    },

    /// 替换无效令牌
    replace_token: struct {
        old_token: []const u8,
        new_token: []const u8,
    },

    /// 语句边界恢复
    statement_boundary: struct {
        insert_semicolon: bool,
    },

    /// 表达式恢复
    expression_recovery: struct {
        wrap_in_parentheses: bool,
        default_value: ?Value,
    },

    /// 异常捕获和恢复
    exception_handling: struct {
        catch_type: []const u8,
        recovery_code: []const u8,
    },

    /// 错误传播
    error_propagation: struct {
        propagate_to_caller: bool,
    },
};

pub const ErrorRecoveryStrategy = struct {
    allocator: std.mem.Allocator,
    strategies: std.StringHashMapUnmanaged(ErrorRecoveryAction),
    recovery_stats: RecoveryStats,

    pub const RecoveryStats = struct {
        total_recoveries: usize = 0,
        successful_recoveries: usize = 0,
        failed_recoveries: usize = 0,
        lexer_recoveries: usize = 0,
        parser_recoveries: usize = 0,
        runtime_recoveries: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) ErrorRecoveryStrategy {
        return .{
            .allocator = allocator,
            .strategies = .{},
            .recovery_stats = .{},
        };
    }

    pub fn deinit(self: *ErrorRecoveryStrategy) void {
        self.strategies.deinit(self.allocator);
    }

    /// 词法分析阶段错误恢复
    /// 同步恢复（跳过到下一个同步点）
    /// 令牌插入（插入缺失的分号）
    /// 令牌替换（替换无效令牌）
    pub fn recoverLexerError(self: *ErrorRecoveryStrategy, error_info: *ErrorInfo) !bool {
        self.recovery_stats.lexer_recoveries += 1;

        const action = switch (error_info.context.error_type) {
            .lexer_error => blk: {
                // 尝试同步恢复
                const sync_action = ErrorRecoveryAction{
                    .skip_to_sync_point = .{
                        .sync_token = ";",
                    },
                };
                try self.strategies.put(self.allocator, "lexer_sync", sync_action);
                break :blk sync_action;
            },
            else => return false,
        };

        error_info.setRecoveryAction(action);
        self.recovery_stats.total_recoveries += 1;
        self.recovery_stats.successful_recoveries += 1;

        return true;
    }

    /// 语法分析阶段错误恢复
    /// 语句边界恢复
    /// 表达式恢复
    /// 错误聚合（收集多个错误）
    pub fn recoverParserError(self: *ErrorRecoveryStrategy, error_info: *ErrorInfo) !bool {
        self.recovery_stats.parser_recoveries += 1;

        const action = switch (error_info.context.error_type) {
            .parse_error => blk: {
                // 尝试语句边界恢复
                const boundary_action = ErrorRecoveryAction{
                    .statement_boundary = .{
                        .insert_semicolon = true,
                    },
                };
                try self.strategies.put(self.allocator, "parser_boundary", boundary_action);
                break :blk boundary_action;
            },
            else => return false,
        };

        error_info.setRecoveryAction(action);
        self.recovery_stats.total_recoveries += 1;
        self.recovery_stats.successful_recoveries += 1;

        return true;
    }

    /// 运行时阶段错误恢复
    /// 异常捕获和恢复
    /// 错误传播
    /// 堆栈跟踪
    pub fn recoverRuntimeError(self: *ErrorRecoveryStrategy, error_info: *ErrorInfo) !bool {
        self.recovery_stats.runtime_recoveries += 1;

        const action = switch (error_info.context.error_type) {
            .type_error, .argument_error => blk: {
                // 尝试异常处理
                const exception_action = ErrorRecoveryAction{
                    .exception_handling = .{
                        .catch_type = "Exception",
                        .recovery_code = "return null;",
                    },
                };
                try self.strategies.put(self.allocator, "runtime_exception", exception_action);
                break :blk exception_action;
            },
            .arithmetic_error => blk: {
                // 算术错误恢复
                const recovery_action = ErrorRecoveryAction{
                    .expression_recovery = .{
                        .wrap_in_parentheses = false,
                        .default_value = Value.initInt(0),
                    },
                };
                try self.strategies.put(self.allocator, "arithmetic_recovery", recovery_action);
                break :blk recovery_action;
            },
            .memory_error => blk: {
                // 内存错误通常无法恢复，传播给调用者
                const propagation_action = ErrorRecoveryAction{
                    .error_propagation = .{
                        .propagate_to_caller = true,
                    },
                };
                try self.strategies.put(self.allocator, "memory_propagation", propagation_action);
                break :blk propagation_action;
            },
            else => return false,
        };

        error_info.setRecoveryAction(action);
        self.recovery_stats.total_recoveries += 1;
        self.recovery_stats.successful_recoveries += 1;

        return true;
    }

    pub fn getRecoveryStats(self: *const ErrorRecoveryStrategy) RecoveryStats {
        return self.recovery_stats;
    }
};

// ============================================================================
// 错误处理器
// ============================================================================

pub const ErrorHandler = struct {
    allocator: std.mem.Allocator,
    error_queue: std.ArrayListUnmanaged(*ErrorInfo),
    recovery_strategy: ErrorRecoveryStrategy,
    error_handlers: std.StringHashMapUnmanaged(ErrorHandlerFn),
    handler_stats: HandlerStats,

    pub const ErrorHandlerFn = *const fn (*ErrorHandler, *ErrorInfo) anyerror!bool;
    pub const HandlerStats = struct {
        total_errors: usize = 0,
        handled_errors: usize = 0,
        unhandled_errors: usize = 0,
        critical_errors: usize = 0,
        fatal_errors: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) ErrorHandler {
        return .{
            .allocator = allocator,
            .error_queue = .{},
            .recovery_strategy = ErrorRecoveryStrategy.init(allocator),
            .error_handlers = .{},
            .handler_stats = .{},
        };
    }

    pub fn deinit(self: *ErrorHandler) void {
        for (self.error_queue.items) |err| {
            err.deinit(self.allocator);
            self.allocator.destroy(err);
        }
        self.error_queue.deinit(self.allocator);
        self.recovery_strategy.deinit();
        self.error_handlers.deinit(self.allocator);
    }

    pub fn registerHandler(self: *ErrorHandler, error_type: []const u8, handler: ErrorHandlerFn) !void {
        try self.error_handlers.put(self.allocator, error_type, handler);
    }

    pub fn reportError(self: *ErrorHandler, error_type: ErrorType, message: []const u8, file: []const u8, line: u32) !void {
        const error_info = try self.allocator.create(ErrorInfo);
        error_info.* = ErrorInfo.init(self.allocator, error_type, message, file, line);
        try self.error_queue.append(self.allocator, error_info);

        self.handler_stats.total_errors += 1;

        // 立即尝试处理错误
        try self.processError(error_info);
    }

    pub fn reportErrorWithContext(self: *ErrorHandler, error_info: *ErrorInfo) !void {
        try self.error_queue.append(self.allocator, error_info);
        self.handler_stats.total_errors += 1;
        try self.processError(error_info);
    }

    fn processError(self: *ErrorHandler, error_info: *ErrorInfo) !void {
        // 首先尝试错误恢复
        const recovered = switch (error_info.context.error_type) {
            .lexer_error => try self.recovery_strategy.recoverLexerError(error_info),
            .parse_error => try self.recovery_strategy.recoverParserError(error_info),
            .type_error, .argument_error, .arithmetic_error, .memory_error => try self.recovery_strategy.recoverRuntimeError(error_info),
            else => false,
        };

        if (recovered) {
            self.handler_stats.handled_errors += 1;
            return;
        }

        // 如果无法恢复，查找专门的错误处理器
        const type_name = @tagName(error_info.context.error_type);
        if (self.error_handlers.get(type_name)) |handler| {
            const handled = try handler(self, error_info);
            if (handled) {
                self.handler_stats.handled_errors += 1;
                return;
            }
        }

        // 无法处理的错误
        self.handler_stats.unhandled_errors += 1;

        // 严重错误需要特殊处理
        if (error_info.context.severity == .critical or error_info.context.severity == .fatal) {
            self.handler_stats.critical_errors += 1;
            try self.handleCriticalError(error_info);
        } else {
            // 打印错误信息
            const formatted_error = try error_info.context.format(self.allocator);
            defer self.allocator.free(formatted_error);
            std.log.err("{s}", .{formatted_error});
        }
    }

    fn handleCriticalError(self: *ErrorHandler, error_info: *ErrorInfo) !void {
        self.handler_stats.fatal_errors += 1;

        // 生成详细的错误报告
        const report = try self.generateErrorReport(error_info);
        defer self.allocator.free(report);

        std.log.err("CRITICAL ERROR REPORT:\n{s}", .{report});

        // 对于致命错误，可能需要终止程序或执行紧急清理
        if (error_info.context.severity == .fatal) {
            std.log.err("Fatal error encountered. Program may be in an unstable state.", .{});
        }
    }

    fn generateErrorReport(self: *ErrorHandler, error_info: *ErrorInfo) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        try writer.print("Error ID: {x}\n", .{error_info.error_id});
        try writer.print("Timestamp: {}\n", .{error_info.context.timestamp});

        const formatted = try error_info.context.format(self.allocator);
        defer self.allocator.free(formatted);
        try writer.writeAll(formatted);

        // 添加相关错误
        if (error_info.context.related_errors.items.len > 0) {
            try writer.print("Related Errors:\n", .{});
            for (error_info.context.related_errors.items, 0..) |related, i| {
                try writer.print("  [{d}] ", .{i + 1});
                const related_formatted = try related.context.format(self.allocator);
                defer self.allocator.free(related_formatted);
                try writer.writeAll(related_formatted);
            }
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    pub fn getStats(self: *const ErrorHandler) HandlerStats {
        return self.handler_stats;
    }

    pub fn getRecoveryStats(self: *const ErrorHandler) ErrorRecoveryStrategy.RecoveryStats {
        return self.recovery_strategy.getRecoveryStats();
    }

    pub fn clearErrors(self: *ErrorHandler) void {
        for (self.error_queue.items) |err| {
            err.deinit(self.allocator);
            self.allocator.destroy(err);
        }
        self.error_queue.clearRetainingCapacity();
    }
};

// ============================================================================
// 错误监控和报告
// ============================================================================

pub const ErrorMonitor = struct {
    allocator: std.mem.Allocator,
    error_history: std.ArrayListUnmanaged(*ErrorInfo),
    error_patterns: std.StringHashMapUnmanaged(usize), // 错误模式 -> 出现次数
    monitoring_stats: MonitoringStats,

    pub const MonitoringStats = struct {
        total_monitored_errors: usize = 0,
        unique_error_patterns: usize = 0,
        most_frequent_error: ?[]const u8 = null,
        error_rate_per_minute: f64 = 0.0,
        monitoring_start_time: i64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) ErrorMonitor {
        return .{
            .allocator = allocator,
            .error_history = .{},
            .error_patterns = .{},
            .monitoring_stats = .{
                .monitoring_start_time = std.time.timestamp(),
            },
        };
    }

    pub fn deinit(self: *ErrorMonitor) void {
        for (self.error_history.items) |err| {
            err.deinit(self.allocator);
            self.allocator.destroy(err);
        }
        self.error_history.deinit(self.allocator);

        var iter = self.error_patterns.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(@constCast(entry.key_ptr.*));
        }
        self.error_patterns.deinit(self.allocator);
    }

    pub fn recordError(self: *ErrorMonitor, error_info: *ErrorInfo) !void {
        // 记录到历史
        try self.error_history.append(self.allocator, error_info);

        // 更新模式统计
        const pattern_key = try std.fmt.allocPrint(self.allocator, "{s}:{s}:{d}", .{
            @tagName(error_info.context.error_type),
            error_info.context.file,
            error_info.context.line,
        });
        defer self.allocator.free(pattern_key);

        const count = self.error_patterns.get(pattern_key) orelse 0;
        const owned_key = try self.allocator.dupe(u8, pattern_key);
        try self.error_patterns.put(self.allocator, owned_key, count + 1);

        self.monitoring_stats.total_monitored_errors += 1;
        self.monitoring_stats.unique_error_patterns = self.error_patterns.count();

        // 更新最频繁错误
        self.updateMostFrequentError();
        self.updateErrorRate();
    }

    fn updateMostFrequentError(self: *ErrorMonitor) void {
        var max_count: usize = 0;
        var max_pattern: ?[]const u8 = null;

        var iter = self.error_patterns.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > max_count) {
                max_count = entry.value_ptr.*;
                max_pattern = entry.key_ptr.*;
            }
        }

        self.monitoring_stats.most_frequent_error = max_pattern;
    }

    fn updateErrorRate(self: *ErrorMonitor) void {
        const elapsed_minutes = @as(f64, @floatFromInt(std.time.timestamp() - self.monitoring_stats.monitoring_start_time)) / 60.0;
        if (elapsed_minutes > 0) {
            self.monitoring_stats.error_rate_per_minute =
                @as(f64, @floatFromInt(self.monitoring_stats.total_monitored_errors)) / elapsed_minutes;
        }
    }

    pub fn generateReport(self: *ErrorMonitor) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        try writer.print("=== Error Monitoring Report ===\n", .{});
        try writer.print("Monitoring Duration: {d} minutes\n", .{
            (std.time.timestamp() - self.monitoring_stats.monitoring_start_time) / 60,
        });
        try writer.print("Total Errors: {}\n", .{self.monitoring_stats.total_monitored_errors});
        try writer.print("Unique Error Patterns: {}\n", .{self.monitoring_stats.unique_error_patterns});
        try writer.print("Error Rate: {d:.2} errors/minute\n", .{self.monitoring_stats.error_rate_per_minute});

        if (self.monitoring_stats.most_frequent_error) |pattern| {
            try writer.print("Most Frequent Error: {s}\n", .{pattern});
        }

        try writer.print("\nTop Error Patterns:\n", .{});
        // 简化的模式排序（实际实现需要更复杂的排序）
        var iter = self.error_patterns.iterator();
        var count: usize = 0;
        while (iter.next() and count < 5) |entry| {
            try writer.print("  {s}: {} occurrences\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            count += 1;
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    pub fn getStats(self: *const ErrorMonitor) MonitoringStats {
        return self.monitoring_stats;
    }
};

// ============================================================================
// 高级错误处理系统
// ============================================================================

pub const AdvancedErrorSystem = struct {
    allocator: std.mem.Allocator,
    error_handler: ErrorHandler,
    error_monitor: ErrorMonitor,
    system_stats: SystemStats,

    pub const SystemStats = struct {
        total_errors_processed: usize = 0,
        errors_recovered: usize = 0,
        errors_escalated: usize = 0,
        system_uptime_seconds: u64 = 0,
        error_free_periods: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) AdvancedErrorSystem {
        return .{
            .allocator = allocator,
            .error_handler = ErrorHandler.init(allocator),
            .error_monitor = ErrorMonitor.init(allocator),
            .system_stats = .{},
        };
    }

    pub fn deinit(self: *AdvancedErrorSystem) void {
        self.error_handler.deinit();
        self.error_monitor.deinit();
    }

    pub fn handleError(self: *AdvancedErrorSystem, error_type: ErrorType, message: []const u8, file: []const u8, line: u32) !void {
        try self.error_handler.reportError(error_type, message, file, line);
        self.system_stats.total_errors_processed += 1;

        // 监控错误
        const error_info = self.error_handler.error_queue.items[self.error_handler.error_queue.items.len - 1];
        try self.error_monitor.recordError(error_info);

        // 更新统计
        if (self.error_handler.getStats().handled_errors > self.system_stats.errors_recovered) {
            self.system_stats.errors_recovered += 1;
        }
    }

    pub fn getComprehensiveStats(self: *AdvancedErrorSystem) !SystemStats {
        const handler_stats = self.error_handler.getStats();
        const recovery_stats = self.error_handler.getRecoveryStats();
        const monitor_stats = self.error_monitor.getStats();

        return SystemStats{
            .total_errors_processed = handler_stats.total_errors,
            .errors_recovered = recovery_stats.successful_recoveries,
            .errors_escalated = handler_stats.unhandled_errors,
            .system_uptime_seconds = @intCast(std.time.timestamp() - monitor_stats.monitoring_start_time),
            .error_free_periods = if (handler_stats.total_errors == 0) 1 else 0,
        };
    }

    pub fn generateSystemReport(self: *AdvancedErrorSystem) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        try writer.print("=== Advanced Error System Report ===\n\n", .{});

        // 系统统计
        const system_stats = try self.getComprehensiveStats();
        try writer.print("System Statistics:\n", .{});
        try writer.print("  Total Errors Processed: {}\n", .{system_stats.total_errors_processed});
        try writer.print("  Errors Recovered: {}\n", .{system_stats.errors_recovered});
        try writer.print("  Errors Escalated: {}\n", .{system_stats.errors_escalated});
        try writer.print("  System Uptime: {} seconds\n", .{system_stats.system_uptime_seconds});
        try writer.print("  Error-free Periods: {}\n\n", .{system_stats.error_free_periods});

        // 错误处理器统计
        const handler_stats = self.error_handler.getStats();
        try writer.print("Error Handler Statistics:\n", .{});
        try writer.print("  Handled Errors: {}\n", .{handler_stats.handled_errors});
        try writer.print("  Unhandled Errors: {}\n", .{handler_stats.unhandled_errors});
        try writer.print("  Critical Errors: {}\n", .{handler_stats.critical_errors});
        try writer.print("  Fatal Errors: {}\n\n", .{handler_stats.fatal_errors});

        // 恢复统计
        const recovery_stats = self.error_handler.getRecoveryStats();
        try writer.print("Recovery Statistics:\n", .{});
        try writer.print("  Total Recoveries: {}\n", .{recovery_stats.total_recoveries});
        try writer.print("  Successful Recoveries: {}\n", .{recovery_stats.successful_recoveries});
        try writer.print("  Lexer Recoveries: {}\n", .{recovery_stats.lexer_recoveries});
        try writer.print("  Parser Recoveries: {}\n", .{recovery_stats.parser_recoveries});
        try writer.print("  Runtime Recoveries: {}\n\n", .{recovery_stats.runtime_recoveries});

        // 监控报告
        const monitor_report = try self.error_monitor.generateReport();
        defer self.allocator.free(monitor_report);
        try writer.writeAll(monitor_report);

        return buffer.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// 测试
// ============================================================================

test "error classification" {
    var context = ErrorContext.init(std.testing.allocator, .type_error, "Type mismatch", "test.php", 42);
    defer context.deinit(std.testing.allocator);

    try std.testing.expect(context.error_type == .type_error);
    try std.testing.expect(context.severity == .err);
    try std.testing.expect(std.mem.eql(u8, context.message, "Type mismatch"));
}

test "error recovery strategy" {
    var strategy = ErrorRecoveryStrategy.init(std.testing.allocator);
    defer strategy.deinit();

    var error_info = ErrorInfo.init(std.testing.allocator, .parse_error, "Missing semicolon", "test.php", 10);
    defer error_info.deinit(std.testing.allocator);

    const recovered = try strategy.recoverParserError(&error_info);
    try std.testing.expect(recovered);

    const stats = strategy.getRecoveryStats();
    try std.testing.expect(stats.successful_recoveries == 1);
    try std.testing.expect(stats.parser_recoveries == 1);
}

test "error handler" {
    var handler = ErrorHandler.init(std.testing.allocator);
    defer handler.deinit();

    try handler.reportError(.lexer_error, "Unexpected token", "test.php", 5);

    const stats = handler.getStats();
    try std.testing.expect(stats.total_errors == 1);
    try std.testing.expect(stats.handled_errors == 1);
}

test "error monitor" {
    var monitor = ErrorMonitor.init(std.testing.allocator);
    defer monitor.deinit();

    var error_info = ErrorInfo.init(std.testing.allocator, .type_error, "Invalid type", "test.php", 15);
    defer error_info.deinit(std.testing.allocator);

    try monitor.recordError(&error_info);

    const stats = monitor.getStats();
    try std.testing.expect(stats.total_monitored_errors == 1);
    try std.testing.expect(stats.unique_error_patterns == 1);
}

test "advanced error system" {
    var system = AdvancedErrorSystem.init(std.testing.allocator);
    defer system.deinit();

    try system.handleError(.argument_error, "Invalid argument count", "test.php", 20);

    const stats = try system.getComprehensiveStats();
    try std.testing.expect(stats.total_errors_processed == 1);
    try std.testing.expect(stats.errors_recovered == 1);
}
