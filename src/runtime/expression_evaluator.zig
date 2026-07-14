/// 简单的表达式评估器
///
/// 用于评估调试器条件断点中的表达式
/// 支持基本的比较和逻辑运算
///
/// @concurrency-model ISOLATED
/// @ownership NON-OWNING (allocator)
/// @memory-safety 所有内存操作通过显式 allocator
const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// 表达式求值错误
pub const EvalError = error{
    InvalidExpression,
    UndefinedVariable,
    TypeMismatch,
    DivisionByZero,
    OutOfMemory,
};

/// 表达式评估器
pub const ExpressionEvaluator = struct {
    allocator: std.mem.Allocator,
    variables: std.StringHashMap(Value),

    /// 初始化评估器
    pub fn init(allocator: std.mem.Allocator) ExpressionEvaluator {
        return .{
            .allocator = allocator,
            .variables = std.StringHashMap(Value).init(allocator),
        };
    }

    /// 清理资源
    pub fn deinit(self: *ExpressionEvaluator) void {
        self.variables.deinit();
    }

    /// 设置变量值
    pub fn setVariable(self: *ExpressionEvaluator, name: []const u8, value: Value) !void {
        try self.variables.put(name, value);
    }

    /// 获取变量值
    pub fn getVariable(self: *const ExpressionEvaluator, name: []const u8) ?Value {
        return self.variables.get(name);
    }

    /// 评估表达式
    /// @pre expr 必须是有效的表达式字符串
    /// @post 返回表达式的值
    pub fn evaluate(self: *ExpressionEvaluator, expr: []const u8) EvalError!Value {
        // 去除首尾空格
        const trimmed = std.mem.trim(u8, expr, &std.ascii.whitespace);

        if (trimmed.len == 0) {
            return EvalError.InvalidExpression;
        }

        // 尝试解析为字面量
        if (self.parseLiteral(trimmed)) |value| {
            return value;
        }

        // 尝试解析为变量
        if (self.getVariable(trimmed)) |value| {
            return value;
        }

        // 尝试解析为比较表达式
        if (self.parseComparison(trimmed)) |value| {
            return value;
        }

        // 尝试解析为逻辑表达式
        if (self.parseLogical(trimmed)) |value| {
            return value;
        }

        return EvalError.InvalidExpression;
    }

    /// 解析字面量
    fn parseLiteral(self: *ExpressionEvaluator, expr: []const u8) ?Value {
        _ = self;

        // 布尔值
        if (std.mem.eql(u8, expr, "true")) {
            return Value.initBool(true);
        }
        if (std.mem.eql(u8, expr, "false")) {
            return Value.initBool(false);
        }

        // null
        if (std.mem.eql(u8, expr, "null")) {
            return Value.initNull();
        }

        // 整数
        if (std.fmt.parseInt(i64, expr, 10)) |int_val| {
            return Value.initInt(int_val);
        } else |_| {}

        // 浮点数
        if (std.fmt.parseFloat(f64, expr)) |float_val| {
            return Value.initFloat(float_val);
        } else |_| {}

        // 字符串（带引号）
        if (expr.len >= 2) {
            if ((expr[0] == '"' and expr[expr.len - 1] == '"') or
                (expr[0] == '\'' and expr[expr.len - 1] == '\''))
            {
                // 简化：不处理转义字符
                return null; // 需要 allocator 创建字符串
            }
        }

        return null;
    }

    /// 解析比较表达式
    fn parseComparison(self: *ExpressionEvaluator, expr: []const u8) ?Value {
        // 支持的比较运算符：==, !=, <, >, <=, >=
        const operators = [_][]const u8{ "==", "!=", "<=", ">=", "<", ">" };

        for (operators) |op| {
            if (std.mem.indexOf(u8, expr, op)) |pos| {
                const left_expr = std.mem.trim(u8, expr[0..pos], &std.ascii.whitespace);
                const right_expr = std.mem.trim(u8, expr[pos + op.len ..], &std.ascii.whitespace);

                const left = self.evaluate(left_expr) catch return null;
                const right = self.evaluate(right_expr) catch return null;

                const result = self.compareValues(left, right, op) catch return null;
                return Value.initBool(result);
            }
        }

        return null;
    }

    /// 解析逻辑表达式
    fn parseLogical(self: *ExpressionEvaluator, expr: []const u8) ?Value {
        // 支持的逻辑运算符：&&, ||, !

        // && (AND)
        if (std.mem.indexOf(u8, expr, "&&")) |pos| {
            const left_expr = std.mem.trim(u8, expr[0..pos], &std.ascii.whitespace);
            const right_expr = std.mem.trim(u8, expr[pos + 2 ..], &std.ascii.whitespace);

            const left = self.evaluate(left_expr) catch return null;
            const right = self.evaluate(right_expr) catch return null;

            const left_bool = self.toBool(left);
            const right_bool = self.toBool(right);

            return Value.initBool(left_bool and right_bool);
        }

        // || (OR)
        if (std.mem.indexOf(u8, expr, "||")) |pos| {
            const left_expr = std.mem.trim(u8, expr[0..pos], &std.ascii.whitespace);
            const right_expr = std.mem.trim(u8, expr[pos + 2 ..], &std.ascii.whitespace);

            const left = self.evaluate(left_expr) catch return null;
            const right = self.evaluate(right_expr) catch return null;

            const left_bool = self.toBool(left);
            const right_bool = self.toBool(right);

            return Value.initBool(left_bool or right_bool);
        }

        // ! (NOT)
        if (expr.len > 0 and expr[0] == '!') {
            const inner_expr = std.mem.trim(u8, expr[1..], &std.ascii.whitespace);
            const inner = self.evaluate(inner_expr) catch return null;
            const inner_bool = self.toBool(inner);
            return Value.initBool(!inner_bool);
        }

        return null;
    }

    /// 比较两个值
    fn compareValues(self: *ExpressionEvaluator, left: Value, right: Value, op: []const u8) EvalError!bool {
        _ = self;

        // 类型必须相同（简化实现）
        if (left.getTag() != right.getTag()) {
            return EvalError.TypeMismatch;
        }

        return switch (left.getTag()) {
            .integer => {
                const l = left.asInt();
                const r = right.asInt();
                if (std.mem.eql(u8, op, "==")) return l == r;
                if (std.mem.eql(u8, op, "!=")) return l != r;
                if (std.mem.eql(u8, op, "<")) return l < r;
                if (std.mem.eql(u8, op, ">")) return l > r;
                if (std.mem.eql(u8, op, "<=")) return l <= r;
                if (std.mem.eql(u8, op, ">=")) return l >= r;
                return EvalError.InvalidExpression;
            },
            .float => {
                const l = left.asFloat();
                const r = right.asFloat();
                if (std.mem.eql(u8, op, "==")) return l == r;
                if (std.mem.eql(u8, op, "!=")) return l != r;
                if (std.mem.eql(u8, op, "<")) return l < r;
                if (std.mem.eql(u8, op, ">")) return l > r;
                if (std.mem.eql(u8, op, "<=")) return l <= r;
                if (std.mem.eql(u8, op, ">=")) return l >= r;
                return EvalError.InvalidExpression;
            },
            .boolean => {
                const l = left.asBool();
                const r = right.asBool();
                if (std.mem.eql(u8, op, "==")) return l == r;
                if (std.mem.eql(u8, op, "!=")) return l != r;
                return EvalError.InvalidExpression;
            },
            else => EvalError.TypeMismatch,
        };
    }

    /// 将值转换为布尔值
    fn toBool(self: *ExpressionEvaluator, value: Value) bool {
        _ = self;
        return switch (value.getTag()) {
            .boolean => value.asBool(),
            .integer => value.asInt() != 0,
            .float => value.asFloat() != 0.0,
            .null_type => false,
            else => true,
        };
    }
};

// ============================================================================
// 测试
// ============================================================================

const testing = std.testing;

test "表达式评估器 - 字面量" {
    const allocator = testing.allocator;
    var evaluator = ExpressionEvaluator.init(allocator);
    defer evaluator.deinit();

    // 布尔值
    const true_val = try evaluator.evaluate("true");
    try testing.expect(true_val.asBool());

    const false_val = try evaluator.evaluate("false");
    try testing.expect(!false_val.asBool());

    // null
    const null_val = try evaluator.evaluate("null");
    try testing.expect(null_val.getTag() == .null_type);

    // 整数
    const int_val = try evaluator.evaluate("42");
    try testing.expectEqual(@as(i64, 42), int_val.asInt());

    // 浮点数
    const float_val = try evaluator.evaluate("3.14");
    try testing.expectApproxEqAbs(@as(f64, 3.14), float_val.asFloat(), 0.001);
}

test "表达式评估器 - 变量" {
    const allocator = testing.allocator;
    var evaluator = ExpressionEvaluator.init(allocator);
    defer evaluator.deinit();

    // 设置变量
    try evaluator.setVariable("x", Value.initInt(10));
    try evaluator.setVariable("y", Value.initInt(20));

    // 获取变量
    const x = try evaluator.evaluate("x");
    try testing.expectEqual(@as(i64, 10), x.asInt());

    const y = try evaluator.evaluate("y");
    try testing.expectEqual(@as(i64, 20), y.asInt());
}

test "表达式评估器 - 比较" {
    const allocator = testing.allocator;
    var evaluator = ExpressionEvaluator.init(allocator);
    defer evaluator.deinit();

    try evaluator.setVariable("x", Value.initInt(10));
    try evaluator.setVariable("y", Value.initInt(20));

    // ==
    const eq = try evaluator.evaluate("x == 10");
    try testing.expect(eq.asBool());

    // !=
    const ne = try evaluator.evaluate("x != 20");
    try testing.expect(ne.asBool());

    // <
    const lt = try evaluator.evaluate("x < y");
    try testing.expect(lt.asBool());

    // >
    const gt = try evaluator.evaluate("y > x");
    try testing.expect(gt.asBool());

    // <=
    const le = try evaluator.evaluate("x <= 10");
    try testing.expect(le.asBool());

    // >=
    const ge = try evaluator.evaluate("y >= 20");
    try testing.expect(ge.asBool());
}

test "表达式评估器 - 逻辑运算" {
    const allocator = testing.allocator;
    var evaluator = ExpressionEvaluator.init(allocator);
    defer evaluator.deinit();

    try evaluator.setVariable("x", Value.initInt(10));
    try evaluator.setVariable("y", Value.initInt(20));

    // &&
    const and_expr = try evaluator.evaluate("x == 10 && y == 20");
    try testing.expect(and_expr.asBool());

    // ||
    const or_expr = try evaluator.evaluate("x == 5 || y == 20");
    try testing.expect(or_expr.asBool());

    // !
    const not_expr = try evaluator.evaluate("!false");
    try testing.expect(not_expr.asBool());
}
