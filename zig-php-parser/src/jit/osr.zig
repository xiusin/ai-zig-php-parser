const std = @import("std");

/// OSR (On-Stack Replacement) 实现
/// 
/// OSR 允许在循环执行过程中从解释执行切换到 JIT 编译的原生代码，
/// 无需等待函数返回。这对于长时间运行的循环特别有效。
///
/// @concurrency-model ISOLATED (单线程)
/// @memory-safety 所有指针生命周期明确标注

/// 栈帧状态快照
/// @ownership NON-OWNING (不拥有任何指针)
pub const FrameSnapshot = struct {
    /// 程序计数器（字节码偏移）
    pc: u32,
    
    /// 栈指针（相对于帧基址的偏移）
    sp: u32,
    
    /// 局部变量数量
    local_count: u16,
    
    /// 局部变量值（最多支持 256 个局部变量）
    locals: [256]i64,
    
    /// 操作数栈（最多支持 256 个栈元素）
    stack: [256]i64,
    
    /// 栈深度
    stack_depth: u16,
    
    /// 创建空快照
    pub fn init() FrameSnapshot {
        return .{
            .pc = 0,
            .sp = 0,
            .local_count = 0,
            .locals = [_]i64{0} ** 256,
            .stack = [_]i64{0} ** 256,
            .stack_depth = 0,
        };
    }
};

/// OSR 入口点
/// @ownership NON-OWNING (code_ptr 由 JIT 编译器管理)
pub const OSREntry = struct {
    /// 字节码偏移（OSR 点）
    bytecode_offset: u32,
    
    /// JIT 编译的代码入口
    /// @calling-convention x86_64_sysv
    /// @pre snapshot 必须有效
    /// @post 返回执行结果
    code_ptr: *const fn (*const FrameSnapshot) callconv(.c) i64,
    
    /// 编译时间戳（用于失效检测）
    timestamp: i64,
    
    /// 是否有效
    valid: bool,
};

/// OSR 管理器
/// @concurrency-model ISOLATED
/// @ownership TRANSFER (allocator)
pub const OSRManager = struct {
    allocator: std.mem.Allocator,
    
    /// OSR 入口点缓存
    /// Key: (function_id << 32) | bytecode_offset
    entries: std.AutoHashMap(u64, OSREntry),
    
    /// OSR 触发阈值（循环迭代次数）
    threshold: u32,
    
    /// 统计信息
    stats: OSRStats,
    
    /// 初始化 OSR 管理器
    /// @pre allocator 必须有效
    /// @post 返回初始化的管理器
    pub fn init(allocator: std.mem.Allocator) !*OSRManager {
        const manager = try allocator.create(OSRManager);
        manager.* = .{
            .allocator = allocator,
            .entries = std.AutoHashMap(u64, OSREntry).init(allocator),
            .threshold = 100, // 默认阈值
            .stats = OSRStats.init(),
        };
        return manager;
    }
    
    /// 释放资源
    /// @pre self 必须已初始化
    /// @post 所有资源被释放
    pub fn deinit(self: *OSRManager) void {
        self.entries.deinit();
        self.allocator.destroy(self);
    }
    
    /// 注册 OSR 入口点
    /// @pre code_ptr 必须有效
    /// @post OSR 入口点被缓存
    pub fn registerEntry(
        self: *OSRManager,
        function_id: u32,
        bytecode_offset: u32,
        code_ptr: *const fn (*const FrameSnapshot) callconv(.c) i64,
    ) !void {
        const key = makeKey(function_id, bytecode_offset);
        const entry = OSREntry{
            .bytecode_offset = bytecode_offset,
            .code_ptr = code_ptr,
            .timestamp = std.time.milliTimestamp(),
            .valid = true,
        };
        try self.entries.put(key, entry);
        self.stats.entries_created += 1;
    }
    
    /// 查找 OSR 入口点
    /// @pre function_id 和 bytecode_offset 必须有效
    /// @post 返回 OSR 入口点或 null
    pub fn findEntry(
        self: *OSRManager,
        function_id: u32,
        bytecode_offset: u32,
    ) ?*const OSREntry {
        const key = makeKey(function_id, bytecode_offset);
        if (self.entries.getPtr(key)) |entry| {
            if (entry.valid) {
                return entry;
            }
        }
        return null;
    }
    
    /// 使 OSR 入口点失效
    /// @pre function_id 和 bytecode_offset 必须有效
    /// @post OSR 入口点被标记为无效
    pub fn invalidateEntry(
        self: *OSRManager,
        function_id: u32,
        bytecode_offset: u32,
    ) void {
        const key = makeKey(function_id, bytecode_offset);
        if (self.entries.getPtr(key)) |entry| {
            entry.valid = false;
            self.stats.entries_invalidated += 1;
        }
    }
    
    /// 清除所有 OSR 入口点
    /// @post 所有 OSR 入口点被清除
    pub fn clearAll(self: *OSRManager) void {
        self.entries.clearRetainingCapacity();
        self.stats.entries_cleared += 1;
    }
    
    /// 生成缓存键
    fn makeKey(function_id: u32, bytecode_offset: u32) u64 {
        return (@as(u64, function_id) << 32) | @as(u64, bytecode_offset);
    }
};

/// OSR 统计信息
pub const OSRStats = struct {
    /// 创建的 OSR 入口点数量
    entries_created: u64,
    
    /// 失效的 OSR 入口点数量
    entries_invalidated: u64,
    
    /// 清除操作次数
    entries_cleared: u64,
    
    /// 成功的 OSR 转换次数
    successful_transitions: u64,
    
    /// 失败的 OSR 转换次数
    failed_transitions: u64,
    
    /// 初始化统计信息
    pub fn init() OSRStats {
        return .{
            .entries_created = 0,
            .entries_invalidated = 0,
            .entries_cleared = 0,
            .successful_transitions = 0,
            .failed_transitions = 0,
        };
    }
    
    /// 打印统计报告
    pub fn printReport(self: *const OSRStats, writer: anytype) !void {
        try writer.print("=== OSR Statistics ===\n", .{});
        try writer.print("Entries Created: {d}\n", .{self.entries_created});
        try writer.print("Entries Invalidated: {d}\n", .{self.entries_invalidated});
        try writer.print("Entries Cleared: {d}\n", .{self.entries_cleared});
        try writer.print("Successful Transitions: {d}\n", .{self.successful_transitions});
        try writer.print("Failed Transitions: {d}\n", .{self.failed_transitions});
        
        const total_transitions = self.successful_transitions + self.failed_transitions;
        if (total_transitions > 0) {
            const success_rate = @as(f64, @floatFromInt(self.successful_transitions)) / 
                                @as(f64, @floatFromInt(total_transitions)) * 100.0;
            try writer.print("Success Rate: {d:.2}%\n", .{success_rate});
        }
    }
};

/// 栈状态捕获器
/// @ownership NON-OWNING
pub const StackCapture = struct {
    /// 捕获解释器栈帧状态
    /// @pre frame 必须有效
    /// @post 返回栈帧快照
    pub fn captureFrame(
        pc: u32,
        sp: u32,
        locals: []const i64,
        stack: []const i64,
    ) !FrameSnapshot {
        var snapshot = FrameSnapshot.init();
        snapshot.pc = pc;
        snapshot.sp = sp;
        
        // 复制局部变量
        const local_count = @min(locals.len, 256);
        snapshot.local_count = @intCast(local_count);
        @memcpy(snapshot.locals[0..local_count], locals[0..local_count]);
        
        // 复制操作数栈
        const stack_depth = @min(stack.len, 256);
        snapshot.stack_depth = @intCast(stack_depth);
        @memcpy(snapshot.stack[0..stack_depth], stack[0..stack_depth]);
        
        return snapshot;
    }
    
    /// 验证快照完整性
    /// @pre snapshot 必须有效
    /// @post 返回快照是否有效
    pub fn validateSnapshot(snapshot: *const FrameSnapshot) bool {
        // 检查局部变量数量
        if (snapshot.local_count > 256) return false;
        
        // 检查栈深度
        if (snapshot.stack_depth > 256) return false;
        
        // 检查栈指针
        if (snapshot.sp > snapshot.stack_depth) return false;
        
        return true;
    }
};

/// OSR 转换器
/// @ownership NON-OWNING
pub const OSRTransition = struct {
    /// 执行 OSR 转换（从解释执行到 JIT 代码）
    /// @pre entry 和 snapshot 必须有效
    /// @post 返回 JIT 代码执行结果
    pub fn transitionToJIT(
        entry: *const OSREntry,
        snapshot: *const FrameSnapshot,
        stats: *OSRStats,
    ) !i64 {
        // 验证快照
        if (!StackCapture.validateSnapshot(snapshot)) {
            stats.failed_transitions += 1;
            return error.InvalidSnapshot;
        }
        
        // 验证入口点
        if (!entry.valid) {
            stats.failed_transitions += 1;
            return error.InvalidEntry;
        }
        
        // 调用 JIT 代码
        const result = entry.code_ptr(snapshot);
        stats.successful_transitions += 1;
        
        return result;
    }
    
    /// 回退到解释执行
    /// @pre snapshot 必须有效
    /// @post 返回是否成功回退
    pub fn fallbackToInterpreter(
        snapshot: *const FrameSnapshot,
        stats: *OSRStats,
    ) bool {
        // 验证快照
        if (!StackCapture.validateSnapshot(snapshot)) {
            stats.failed_transitions += 1;
            return false;
        }
        
        // 标记回退成功
        // 实际的回退逻辑由调用者处理
        return true;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "OSR: FrameSnapshot initialization" {
    const snapshot = FrameSnapshot.init();
    
    try std.testing.expectEqual(@as(u32, 0), snapshot.pc);
    try std.testing.expectEqual(@as(u32, 0), snapshot.sp);
    try std.testing.expectEqual(@as(u16, 0), snapshot.local_count);
    try std.testing.expectEqual(@as(u16, 0), snapshot.stack_depth);
}

test "OSR: StackCapture basic" {
    const locals = [_]i64{ 1, 2, 3, 4, 5 };
    const stack = [_]i64{ 10, 20, 30 };
    
    const snapshot = try StackCapture.captureFrame(100, 3, &locals, &stack);
    
    try std.testing.expectEqual(@as(u32, 100), snapshot.pc);
    try std.testing.expectEqual(@as(u32, 3), snapshot.sp);
    try std.testing.expectEqual(@as(u16, 5), snapshot.local_count);
    try std.testing.expectEqual(@as(u16, 3), snapshot.stack_depth);
    
    // 验证局部变量
    for (locals, 0..) |val, i| {
        try std.testing.expectEqual(val, snapshot.locals[i]);
    }
    
    // 验证栈
    for (stack, 0..) |val, i| {
        try std.testing.expectEqual(val, snapshot.stack[i]);
    }
}

test "OSR: StackCapture validation" {
    var snapshot = FrameSnapshot.init();
    snapshot.local_count = 10;
    snapshot.stack_depth = 5;
    snapshot.sp = 3;
    
    try std.testing.expect(StackCapture.validateSnapshot(&snapshot));
    
    // 无效的栈指针
    snapshot.sp = 10;
    try std.testing.expect(!StackCapture.validateSnapshot(&snapshot));
    
    // 无效的局部变量数量
    snapshot.sp = 3;
    snapshot.local_count = 300;
    try std.testing.expect(!StackCapture.validateSnapshot(&snapshot));
}

test "OSR: OSRManager basic operations" {
    const allocator = std.testing.allocator;
    
    const manager = try OSRManager.init(allocator);
    defer manager.deinit();
    
    // 模拟 JIT 代码入口
    const mock_entry = struct {
        fn execute(_: *const FrameSnapshot) callconv(.c) i64 {
            return 42;
        }
    }.execute;
    
    // 注册 OSR 入口点
    try manager.registerEntry(1, 100, mock_entry);
    
    // 查找入口点
    const entry = manager.findEntry(1, 100);
    try std.testing.expect(entry != null);
    try std.testing.expect(entry.?.valid);
    try std.testing.expectEqual(@as(u32, 100), entry.?.bytecode_offset);
    
    // 使入口点失效
    manager.invalidateEntry(1, 100);
    const invalid_entry = manager.findEntry(1, 100);
    try std.testing.expect(invalid_entry == null);
    
    // 验证统计信息
    try std.testing.expectEqual(@as(u64, 1), manager.stats.entries_created);
    try std.testing.expectEqual(@as(u64, 1), manager.stats.entries_invalidated);
}

test "OSR: OSRTransition success" {
    const allocator = std.testing.allocator;
    
    const manager = try OSRManager.init(allocator);
    defer manager.deinit();
    
    // 创建快照
    const locals = [_]i64{ 1, 2, 3 };
    const stack = [_]i64{ 10, 20 };
    const snapshot = try StackCapture.captureFrame(100, 2, &locals, &stack);
    
    // 模拟 JIT 代码
    const mock_entry = struct {
        fn execute(snap: *const FrameSnapshot) callconv(.c) i64 {
            return snap.locals[0] + snap.stack[0];
        }
    }.execute;
    
    // 注册并执行 OSR 转换
    try manager.registerEntry(1, 100, mock_entry);
    const entry = manager.findEntry(1, 100).?;
    
    const result = try OSRTransition.transitionToJIT(entry, &snapshot, &manager.stats);
    try std.testing.expectEqual(@as(i64, 11), result); // 1 + 10
    try std.testing.expectEqual(@as(u64, 1), manager.stats.successful_transitions);
}

test "OSR: OSRTransition invalid snapshot" {
    const allocator = std.testing.allocator;
    
    const manager = try OSRManager.init(allocator);
    defer manager.deinit();
    
    // 创建无效快照
    var snapshot = FrameSnapshot.init();
    snapshot.sp = 300; // 无效的栈指针
    
    const mock_entry = struct {
        fn execute(_: *const FrameSnapshot) callconv(.c) i64 {
            return 0;
        }
    }.execute;
    
    try manager.registerEntry(1, 100, mock_entry);
    const entry = manager.findEntry(1, 100).?;
    
    // 应该失败
    const result = OSRTransition.transitionToJIT(entry, &snapshot, &manager.stats);
    try std.testing.expectError(error.InvalidSnapshot, result);
    try std.testing.expectEqual(@as(u64, 1), manager.stats.failed_transitions);
}
