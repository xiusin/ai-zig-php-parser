//! 优化集成层 - 桥接现有VM和优化模块
//! 提供简单的API让现有代码使用优化功能

const std = @import("std");
const fast_value = @import("fast_value.zig");
const fast_string = @import("fast_string.zig");
const fast_pool = @import("fast_pool.zig");
const fast_vm = @import("fast_vm.zig");

/// 优化的PHP值 - 兼容现有Value接口
pub const OptimizedValue = struct {
    inner: fast_value.FastValue,

    pub fn initNull() OptimizedValue {
        return .{ .inner = fast_value.FastValue.nil };
    }

    pub fn initBool(b: bool) OptimizedValue {
        return .{ .inner = if (b) fast_value.FastValue.true else fast_value.FastValue.false };
    }

    pub fn initInt(i: i64) OptimizedValue {
        const i32_val: i32 = @intCast(@min(@max(i, std.math.minInt(i32)), std.math.maxInt(i32)));
        return .{ .inner = fast_value.small_int_cache.get(i32_val) };
    }

    pub fn initFloat(f: f64) OptimizedValue {
        return .{ .inner = fast_value.FastValue.initFloat(f) };
    }

    pub fn isNull(self: OptimizedValue) bool {
        return self.inner.isNil();
    }

    pub fn isBool(self: OptimizedValue) bool {
        return self.inner.isBool();
    }

    pub fn isInt(self: OptimizedValue) bool {
        return self.inner.isInt();
    }

    pub fn isFloat(self: OptimizedValue) bool {
        return self.inner.isFloat();
    }

    pub fn asBool(self: OptimizedValue) bool {
        return self.inner.asBool();
    }

    pub fn asInt(self: OptimizedValue) i64 {
        return self.inner.asInt();
    }

    pub fn asFloat(self: OptimizedValue) f64 {
        return self.inner.asFloat();
    }

    pub fn toBool(self: OptimizedValue) bool {
        return self.inner.toBool();
    }

    pub fn toInt(self: OptimizedValue) i64 {
        return self.inner.toInt();
    }

    pub fn toFloat(self: OptimizedValue) f64 {
        return self.inner.toFloat();
    }

    // 算术操作
    pub fn add(self: OptimizedValue, other: OptimizedValue) OptimizedValue {
        return .{ .inner = fast_value.FastOps.add(self.inner, other.inner) };
    }

    pub fn sub(self: OptimizedValue, other: OptimizedValue) OptimizedValue {
        return .{ .inner = fast_value.FastOps.sub(self.inner, other.inner) };
    }

    pub fn mul(self: OptimizedValue, other: OptimizedValue) OptimizedValue {
        return .{ .inner = fast_value.FastOps.mul(self.inner, other.inner) };
    }

    pub fn div(self: OptimizedValue, other: OptimizedValue) OptimizedValue {
        return .{ .inner = fast_value.FastOps.div(self.inner, other.inner) };
    }

    pub fn eq(self: OptimizedValue, other: OptimizedValue) OptimizedValue {
        return .{ .inner = fast_value.FastOps.eq(self.inner, other.inner) };
    }

    pub fn lt(self: OptimizedValue, other: OptimizedValue) OptimizedValue {
        return .{ .inner = fast_value.FastOps.lt(self.inner, other.inner) };
    }

    pub fn gt(self: OptimizedValue, other: OptimizedValue) OptimizedValue {
        return .{ .inner = fast_value.FastOps.gt(self.inner, other.inner) };
    }
};

/// 优化的执行器 - 简单的表达式求值器
pub const OptimizedExecutor = struct {
    allocator: std.mem.Allocator,
    string_pool: fast_string.StringPool,
    pool_manager: fast_pool.PoolManager,
    output: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator) !OptimizedExecutor {
        return .{
            .allocator = allocator,
            .string_pool = try fast_string.StringPool.init(allocator),
            .pool_manager = fast_pool.PoolManager.init(allocator),
            .output = .{},
        };
    }

    pub fn deinit(self: *OptimizedExecutor) void {
        self.string_pool.deinit();
        self.pool_manager.deinit();
        self.output.deinit(self.allocator);
    }

    /// 执行简单的算术表达式
    pub fn evalExpression(self: *OptimizedExecutor, expr: []const u8) !OptimizedValue {
        _ = self;
        // 简单解析: "10 + 20"
        var it = std.mem.tokenizeAny(u8, expr, " \t\n");

        const left_str = it.next() orelse return OptimizedValue.initNull();
        const left_val = std.fmt.parseInt(i64, left_str, 10) catch return OptimizedValue.initNull();

        const op = it.next() orelse return OptimizedValue.initInt(left_val);

        const right_str = it.next() orelse return OptimizedValue.initNull();
        const right_val = std.fmt.parseInt(i64, right_str, 10) catch return OptimizedValue.initNull();

        const left = OptimizedValue.initInt(left_val);
        const right = OptimizedValue.initInt(right_val);

        if (std.mem.eql(u8, op, "+")) {
            return left.add(right);
        } else if (std.mem.eql(u8, op, "-")) {
            return left.sub(right);
        } else if (std.mem.eql(u8, op, "*")) {
            return left.mul(right);
        } else if (std.mem.eql(u8, op, "/")) {
            return left.div(right);
        }

        return OptimizedValue.initNull();
    }

    /// 输出值
    pub fn echo(self: *OptimizedExecutor, value: OptimizedValue) !void {
        if (value.isNull()) {
            // null 不输出
        } else if (value.isBool()) {
            if (value.asBool()) {
                try self.output.appendSlice(self.allocator, "1");
            }
        } else if (value.isInt()) {
            var buf: [32]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{d}", .{value.asInt()});
            try self.output.appendSlice(self.allocator, s);
        } else if (value.isFloat()) {
            var buf: [64]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{d}", .{value.asFloat()});
            try self.output.appendSlice(self.allocator, s);
        }
    }

    pub fn getOutput(self: *const OptimizedExecutor) []const u8 {
        return self.output.items;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "OptimizedValue basic" {
    const v1 = OptimizedValue.initInt(10);
    const v2 = OptimizedValue.initInt(20);
    const sum = v1.add(v2);

    try std.testing.expect(sum.isInt());
    try std.testing.expect(sum.asInt() == 30);
}

test "OptimizedExecutor" {
    var exec = try OptimizedExecutor.init(std.testing.allocator);
    defer exec.deinit();

    const result = try exec.evalExpression("10 + 20");
    try std.testing.expect(result.asInt() == 30);

    try exec.echo(result);
    try std.testing.expectEqualStrings("30", exec.getOutput());
}
