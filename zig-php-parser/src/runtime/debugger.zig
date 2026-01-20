//! 调试器
//!
//! 提供交互式调试功能，支持断点、变量监视、调用栈追踪等
//!
//! ## 架构
//!
//! ```
//! Debugger Interface -> Breakpoint Manager -> Variable Watcher
//!        ↓                    ↓                    ↓
//!  Command Parser    Breakpoint Set/Get   Variable Inspection
//!        ↓                    ↓                    ↓
//!  Execution Control  Step Over/Into    Expression Evaluation
//!        ↓                    ↓                    ↓
//!  Call Stack Trace  Continue/Stop     Value Modification
//! ```

const std = @import("std");
const Value = @import("types.zig").Value;
const ExpressionEvaluator = @import("expression_evaluator.zig").ExpressionEvaluator;

// ============================================================================
// 常量配置
// ============================================================================

/// 最大断点数
const MAX_BREAKPOINTS: usize = 256;

/// 最大监视变量数
const MAX_WATCHES: usize = 128;

/// 最大调用栈深度
const MAX_CALL_STACK_DEPTH: usize = 1024;

// ============================================================================
// 断点
// ============================================================================

pub const Breakpoint = struct {
    /// 文件路径
    file: []const u8,
    /// 行号
    line: u32,
    /// 列号
    column: u32,
    /// 条件表达式
    condition: ?[]const u8,
    /// 是否启用
    enabled: bool,
    /// 命中次数
    hit_count: u64,
    /// 忽略次数
    ignore_count: u64,
    /// 临时断点（命中一次后删除）
    temporary: bool,
    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, file: []const u8, line: u32) !Breakpoint {
        return .{
            .file = try allocator.dupe(u8, file),
            .line = line,
            .column = 0,
            .condition = null,
            .enabled = true,
            .hit_count = 0,
            .ignore_count = 0,
            .temporary = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Breakpoint) void {
        self.allocator.free(self.file);
        if (self.condition) |cond| {
            self.allocator.free(cond);
        }
    }

    /// 设置条件
    pub fn setCondition(self: *Breakpoint, condition: []const u8) !void {
        if (self.condition) |old| {
            self.allocator.free(old);
        }
        self.condition = try self.allocator.dupe(u8, condition);
    }

    /// 检查是否应该触发
    pub fn shouldTrigger(self: *Breakpoint, vm: *anyopaque, evaluator: *ExpressionEvaluator) bool {
        if (!self.enabled) return false;

        // 检查忽略次数
        if (self.hit_count < self.ignore_count) {
            return false;
        }

        // 检查条件
        if (self.condition) |cond| {
            // 使用表达式评估器评估条件
            _ = vm; // 可以从 VM 中提取变量值设置到 evaluator
            
            const result = evaluator.evaluate(cond) catch {
                // 评估失败，默认触发
                return true;
            };
            
            // 将结果转换为布尔值
            return switch (result.getTag()) {
                .boolean => result.asBool(),
                .integer => result.asInt() != 0,
                .float => result.asFloat() != 0.0,
                .null_type => false,
                else => true,
            };
        }

        return true;
    }

    /// 命中断点
    pub fn hit(self: *Breakpoint) void {
        self.hit_count += 1;

        // 临时断点在命中后删除
        if (self.temporary) {
            self.enabled = false;
        }
    }
};

// ============================================================================
// 监视变量
// ============================================================================

pub const Watchpoint = struct {
    /// 变量名
    name: []const u8,
    /// 当前值
    current_value: Value,
    /// 旧值
    old_value: Value,
    /// 是否启用
    enabled: bool,
    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Watchpoint {
        return .{
            .name = try allocator.dupe(u8, name),
            .current_value = Value.initNull(),
            .old_value = Value.initNull(),
            .enabled = true,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Watchpoint) void {
        self.allocator.free(self.name);
        // 不需要释放Value，因为它们由VM管理
    }

    /// 更新值
    pub fn update(self: *Watchpoint, new_value: Value) bool {
        self.old_value = self.current_value;
        self.current_value = new_value;

        // 检查值是否改变
        return !self.valuesEqual(&self.old_value, &self.current_value);
    }

    /// 比较两个值
    fn valuesEqual(self: *Watchpoint, a: *const Value, b: *const Value) bool {
        _ = self;
        // 简化实现
        return a.getTag() == b.getTag();
    }
};

// ============================================================================
// 调用栈帧
// ============================================================================

pub const StackFrame = struct {
    /// 函数名
    function_name: []const u8,
    /// 文件路径
    file: []const u8,
    /// 行号
    line: u32,
    /// 列号
    column: u32,
    /// 局部变量
    locals: std.StringHashMap(Value),
    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, function_name: []const u8, file: []const u8, line: u32) !StackFrame {
        return .{
            .function_name = try allocator.dupe(u8, function_name),
            .file = try allocator.dupe(u8, file),
            .line = line,
            .column = 0,
            .locals = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StackFrame) void {
        self.allocator.free(self.function_name);
        self.allocator.free(self.file);
        self.locals.deinit();
    }

    /// 设置局部变量
    pub fn setLocal(self: *StackFrame, name: []const u8, value: Value) !void {
        try self.locals.put(name, value);
    }

    /// 获取局部变量
    pub fn getLocal(self: *StackFrame, name: []const u8) ?Value {
        return self.locals.get(name);
    }
};

// ============================================================================
// 调试器
// ============================================================================

pub const Debugger = struct {
    /// 断点管理器
    breakpoints: std.ArrayListUnmanaged(Breakpoint),
    /// 监视变量
    watches: std.ArrayListUnmanaged(Watchpoint),
    /// 调用栈
    call_stack: std.ArrayListUnmanaged(StackFrame),
    /// 当前状态
    state: DebuggerState,
    /// 分配器
    allocator: std.mem.Allocator,
    /// 统计信息
    stats: DebuggerStats,

    pub const DebuggerState = enum {
        /// 运行中
        running,
        /// 暂停
        paused,
        /// 步进
        stepping,
        /// 单步进入
        step_into,
        /// 单步跳过
        step_over,
        /// 单步跳出
        step_out,
    };

    const DebuggerStats = struct {
        /// 断点命中次数
        breakpoint_hits: u64 = 0,
        /// 步进次数
        step_count: u64 = 0,
        /// 继续次数
        continue_count: u64 = 0,
        /// 查看变量次数
        variable_inspects: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) Debugger {
        return .{
            .breakpoints = std.ArrayListUnmanaged(Breakpoint){},
            .watches = std.ArrayListUnmanaged(Watchpoint){},
            .call_stack = std.ArrayListUnmanaged(StackFrame){},
            .state = .running,
            .allocator = allocator,
            .stats = .{},
        };
    }

    pub fn deinit(self: *Debugger) void {
        for (self.breakpoints.items) |*bp| {
            bp.deinit();
        }
        self.breakpoints.deinit(self.allocator);

        for (self.watches.items) |*wp| {
            wp.deinit();
        }
        self.watches.deinit(self.allocator);

        for (self.call_stack.items) |*frame| {
            frame.deinit();
        }
        self.call_stack.deinit(self.allocator);
    }

    /// 设置断点
    pub fn setBreakpoint(self: *Debugger, file: []const u8, line: u32, temporary: bool) !void {
        if (self.breakpoints.items.len >= MAX_BREAKPOINTS) {
            return error.TooManyBreakpoints;
        }

        var bp = try Breakpoint.init(self.allocator, file, line);
        bp.temporary = temporary;

        try self.breakpoints.append(self.allocator, bp);
    }

    /// 删除断点
    pub fn removeBreakpoint(self: *Debugger, file: []const u8, line: u32) !void {
        for (self.breakpoints.items, 0..) |*bp, i| {
            if (std.mem.eql(u8, bp.file, file) and bp.line == line) {
                bp.deinit();
                _ = self.breakpoints.orderedRemove(i);
                return;
            }
        }
    }

    /// 查找断点
    pub fn findBreakpoint(self: *Debugger, file: []const u8, line: u32) ?*Breakpoint {
        for (self.breakpoints.items) |*bp| {
            if (std.mem.eql(u8, bp.file, file) and bp.line == line) {
                return bp;
            }
        }
        return null;
    }

    /// 检查断点
    pub fn checkBreakpoints(self: *Debugger, file: []const u8, line: u32, vm: *anyopaque) bool {
        for (self.breakpoints.items) |*bp| {
            if (std.mem.eql(u8, bp.file, file) and bp.line == line) {
                if (bp.shouldTrigger(vm)) {
                    bp.hit();
                    self.stats.breakpoint_hits += 1;
                    return true;
                }
            }
        }
        return false;
    }

    /// 添加监视变量
    pub fn addWatch(self: *Debugger, variable_name: []const u8) !void {
        if (self.watches.items.len >= MAX_WATCHES) {
            return error.TooManyWatches;
        }

        try self.watches.append(self.allocator, try Watchpoint.init(self.allocator, variable_name));
    }

    /// 移除监视变量
    pub fn removeWatch(self: *Debugger, variable_name: []const u8) !void {
        for (self.watches.items, 0..) |*wp, i| {
            if (std.mem.eql(u8, wp.name, variable_name)) {
                wp.deinit();
                _ = self.watches.orderedRemove(i);
                return;
            }
        }
    }

    /// 更新监视变量
    pub fn updateWatches(self: *Debugger, vm: *anyopaque) !void {
        for (self.watches.items) |*wp| {
            // 这里应该从VM获取变量值
            // 暂时简化实现
            _ = vm;
            const new_value = Value.initNull();
            _ = wp.update(new_value);
        }
    }

    /// 推入调用栈帧
    pub fn pushStackFrame(self: *Debugger, function_name: []const u8, file: []const u8, line: u32) !void {
        if (self.call_stack.items.len >= MAX_CALL_STACK_DEPTH) {
            return error.CallStackOverflow;
        }

        try self.call_stack.append(self.allocator, try StackFrame.init(self.allocator, function_name, file, line));
    }

    /// 弹出调用栈帧
    pub fn popStackFrame(self: *Debugger) void {
        if (self.call_stack.items.len > 0) {
            const frame = &self.call_stack.items[self.call_stack.items.len - 1];
            frame.deinit();
            _ = self.call_stack.pop();
        }
    }

    /// 获取调用栈
    pub fn getCallStack(self: *Debugger) []const StackFrame {
        return self.call_stack.items;
    }

    /// 暂停
    pub fn pause(self: *Debugger) void {
        self.state = .paused;
    }

    /// 继续
    pub fn resume(self: *Debugger) void {
        self.state = .running;
        self.stats.continue_count += 1;
    }

    /// 步进
    pub fn step(self: *Debugger) void {
        self.state = .stepping;
        self.stats.step_count += 1;
    }

    /// 单步进入
    pub fn stepInto(self: *Debugger) void {
        self.state = .step_into;
        self.stats.step_count += 1;
    }

    /// 单步跳过
    pub fn stepOver(self: *Debugger) void {
        self.state = .step_over;
        self.stats.step_count += 1;
    }

    /// 单步跳出
    pub fn stepOut(self: *Debugger) void {
        self.state = .step_out;
        self.stats.step_count += 1;
    }

    /// 获取状态
    pub fn getState(self: *Debugger) DebuggerState {
        return self.state;
    }

    /// 检查是否暂停
    pub fn isPaused(self: *Debugger) bool {
        return self.state == .paused;
    }

    /// 检查是否步进
    pub fn isStepping(self: *Debugger) bool {
        return self.state == .stepping or
            self.state == .step_into or
            self.state == .step_over or
            self.state == .step_out;
    }

    /// 获取统计信息
    pub fn getStats(self: *Debugger) DebuggerStats {
        return self.stats;
    }

    /// 列出所有断点
    pub fn listBreakpoints(self: *Debugger) !std.ArrayList([]const u8) {
        var list = std.ArrayList([]const u8).init(self.allocator);

        for (self.breakpoints.items) |bp| {
            const desc = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ bp.file, bp.line });
            try list.append(desc);
        }

        return list;
    }

    /// 列出所有监视变量
    pub fn listWatches(self: *Debugger) !std.ArrayList([]const u8) {
        var list = std.ArrayList([]const u8).init(self.allocator);

        for (self.watches.items) |wp| {
            try list.append(try self.allocator.dupe(u8, wp.name));
        }

        return list;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "breakpoint basic" {
    var bp = try Breakpoint.init(std.testing.allocator, "test.php", 10);
    defer bp.deinit();

    try std.testing.expect(std.mem.eql(u8, bp.file, "test.php"));
    try std.testing.expect(bp.line == 10);
    try std.testing.expect(bp.enabled == true);

    bp.hit();
    try std.testing.expect(bp.hit_count == 1);
}

test "watchpoint basic" {
    var wp = try Watchpoint.init(std.testing.allocator, "test_var");
    defer wp.deinit();

    try std.testing.expect(std.mem.eql(u8, wp.name, "test_var"));

    const value = Value.initInt(42);
    const changed = wp.update(value);

    try std.testing.expect(changed == true);
}

test "stack frame basic" {
    var frame = try StackFrame.init(std.testing.allocator, "test_func", "test.php", 10);
    defer frame.deinit();

    try std.testing.expect(std.mem.eql(u8, frame.function_name, "test_func"));
    try std.testing.expect(frame.line == 10);

    try frame.setLocal("x", Value.initInt(42));
    const found = frame.getLocal("x");
    try std.testing.expect(found != null);
}

test "debugger basic" {
    var debugger = Debugger.init(std.testing.allocator);
    defer debugger.deinit();

    // 设置断点
    try debugger.setBreakpoint("test.php", 10, false);

    // 添加监视变量
    try debugger.addWatch("test_var");

    // 推入调用栈帧
    try debugger.pushStackFrame("test_func", "test.php", 10);

    // 检查断点
    const triggered = debugger.checkBreakpoints("test.php", 10, null);
    try std.testing.expect(triggered == true);

    // 暂停
    debugger.pause();
    try std.testing.expect(debugger.isPaused());

    // 继续
    debugger.resume();
    try std.testing.expect(!debugger.isPaused());

    // 获取统计
    const stats = debugger.getStats();
    try std.testing.expect(stats.breakpoint_hits == 1);
}