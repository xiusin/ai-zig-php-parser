//! ConstantFolder — 统一的常量折叠模块 (P2-4)
//!
//! 消除 optimizer.zig 中 foldConstantExpression 和 evalSCCPInstruction 之间的
//! 重复常量折叠逻辑。提供 foldBinary / foldUnary 作为单一折叠入口。
//!
//! 所有运算遵循 PHP 语义：
//! - 整数除法在整除时返回 int，否则返回 float
//! - 整数取模遵循 @mod（截断向零）
//! - 比较运算返回 bool

const std = @import("std");
const IR = @import("ir.zig");

/// 常量值类型（与 optimizer.IROptimizer.ConstantValue 兼容）
pub const ConstantValue = union(enum) {
    int: i64,
    float: f64,
    bool_val: bool,
    null_val: void,
    missing_val: void,
    string_id: u32,
};

/// 二元运算折叠结果
pub const FoldResult = union(enum) {
    /// 成功折叠为一个常量
    folded: ConstantValue,
    /// 无法折叠（类型不匹配、除零等）
    cannot_fold,
    /// 至少一个操作数未知（用于 SCCP lattice 传播）
    unknown,
};

/// 折叠二元运算
///
/// 参数：
/// - op_tag: IR 指令的 Op tag（如 .add, .sub, .mul, .div 等）
/// - lhs: 左操作数常量值
/// - rhs: 右操作数常量值
///
/// 返回 FoldResult：
/// - .folded: 成功折叠
/// - .cannot_fold: 类型不匹配或不支持的操作
/// - .unknown: 不应到达此处（调用方应先检查操作数是否为常量）
pub fn foldBinary(op_tag: std.meta.Tag(IR.Instruction.Op), lhs: ConstantValue, rhs: ConstantValue) FoldResult {
    return switch (op_tag) {
        // 算术运算
        .add => foldArithmetic(lhs, rhs, .add),
        .sub => foldArithmetic(lhs, rhs, .sub),
        .mul => foldArithmetic(lhs, rhs, .mul),
        .div => foldDiv(lhs, rhs),
        .mod => foldMod(lhs, rhs),

        // 位运算
        .bit_and => foldBitwise(lhs, rhs, .bit_and),
        .bit_or => foldBitwise(lhs, rhs, .bit_or),
        .bit_xor => foldBitwise(lhs, rhs, .bit_xor),
        .shl => foldShift(lhs, rhs, .shl),
        .shr => foldShift(lhs, rhs, .shr),

        // 比较运算
        .eq => foldCompare(lhs, rhs, .eq),
        .ne => foldCompare(lhs, rhs, .ne),
        .lt => foldCompare(lhs, rhs, .lt),
        .le => foldCompare(lhs, rhs, .le),
        .gt => foldCompare(lhs, rhs, .gt),
        .ge => foldCompare(lhs, rhs, .ge),

        // 逻辑运算
        .and_ => foldLogical(lhs, rhs, .and_),
        .or_ => foldLogical(lhs, rhs, .or_),

        else => .cannot_fold,
    };
}

/// 折叠一元运算
pub fn foldUnary(op_tag: std.meta.Tag(IR.Instruction.Op), operand: ConstantValue) FoldResult {
    return switch (op_tag) {
        .neg => switch (operand) {
            .int => |v| .{ .folded = .{ .int = -v } },
            .float => |v| .{ .folded = .{ .float = -v } },
            else => .cannot_fold,
        },
        .not => switch (operand) {
            .bool_val => |v| .{ .folded = .{ .bool_val = !v } },
            else => .cannot_fold,
        },
        .bit_not => switch (operand) {
            .int => |v| .{ .folded = .{ .int = ~v } },
            else => .cannot_fold,
        },
        else => .cannot_fold,
    };
}

// ============================================================================
// 内部折叠实现
// ============================================================================

const ArithOp = enum { add, sub, mul };
const BitOp = enum { bit_and, bit_or, bit_xor };
const ShiftOp = enum { shl, shr };
const CmpOp = enum { eq, ne, lt, le, gt, ge };
const LogicOp = enum { and_, or_ };

fn foldArithmetic(lhs: ConstantValue, rhs: ConstantValue, op: ArithOp) FoldResult {
    // int + int
    if (lhs == .int and rhs == .int) {
        return .{ .folded = .{ .int = switch (op) {
            .add => lhs.int + rhs.int,
            .sub => lhs.int - rhs.int,
            .mul => lhs.int * rhs.int,
        } } };
    }
    // float + float 或 mixed int/float → 提升为 float
    if ((lhs == .float or lhs == .int) and (rhs == .float or rhs == .int)) {
        const lf: f64 = if (lhs == .float) lhs.float else @floatFromInt(lhs.int);
        const rf: f64 = if (rhs == .float) rhs.float else @floatFromInt(rhs.int);
        return .{ .folded = .{ .float = switch (op) {
            .add => lf + rf,
            .sub => lf - rf,
            .mul => lf * rf,
        } } };
    }
    return .cannot_fold;
}

fn foldDiv(lhs: ConstantValue, rhs: ConstantValue) FoldResult {
    // PHP 语义：整数除法在整除时返回 int，否则返回 float
    if (lhs == .int and rhs == .int and rhs.int != 0) {
        if (@mod(lhs.int, rhs.int) == 0) {
            return .{ .folded = .{ .int = @divTrunc(lhs.int, rhs.int) } };
        } else {
            return .{ .folded = .{ .float = @as(f64, @floatFromInt(lhs.int)) / @as(f64, @floatFromInt(rhs.int)) } };
        }
    }
    // float / float 或 mixed int/float → 提升为 float
    if ((lhs == .float or lhs == .int) and (rhs == .float or rhs == .int)) {
        const lf: f64 = if (lhs == .float) lhs.float else @floatFromInt(lhs.int);
        const rf: f64 = if (rhs == .float) rhs.float else @floatFromInt(rhs.int);
        if (rf != 0.0) {
            return .{ .folded = .{ .float = lf / rf } };
        }
    }
    return .cannot_fold;
}

fn foldMod(lhs: ConstantValue, rhs: ConstantValue) FoldResult {
    if (lhs == .int and rhs == .int and rhs.int != 0) {
        return .{ .folded = .{ .int = @rem(lhs.int, rhs.int) } };
    }
    return .cannot_fold;
}

fn foldBitwise(lhs: ConstantValue, rhs: ConstantValue, op: BitOp) FoldResult {
    if (lhs == .int and rhs == .int) {
        return .{ .folded = .{ .int = switch (op) {
            .bit_and => lhs.int & rhs.int,
            .bit_or => lhs.int | rhs.int,
            .bit_xor => lhs.int ^ rhs.int,
        } } };
    }
    return .cannot_fold;
}

fn foldShift(lhs: ConstantValue, rhs: ConstantValue, op: ShiftOp) FoldResult {
    if (lhs == .int and rhs == .int) {
        const shift_amt: u6 = @intCast(@mod(rhs.int, 64));
        return .{ .folded = .{ .int = switch (op) {
            .shl => lhs.int << shift_amt,
            .shr => lhs.int >> shift_amt,
        } } };
    }
    return .cannot_fold;
}

fn foldCompare(lhs: ConstantValue, rhs: ConstantValue, op: CmpOp) FoldResult {
    // int vs int — 支持所有比较
    if (lhs == .int and rhs == .int) {
        return .{ .folded = .{ .bool_val = switch (op) {
            .eq => lhs.int == rhs.int,
            .ne => lhs.int != rhs.int,
            .lt => lhs.int < rhs.int,
            .le => lhs.int <= rhs.int,
            .gt => lhs.int > rhs.int,
            .ge => lhs.int >= rhs.int,
        } } };
    }
    // float vs float 或 mixed int/float — 提升为 float 比较
    if ((lhs == .float or lhs == .int) and (rhs == .float or rhs == .int)) {
        const lf: f64 = if (lhs == .float) lhs.float else @floatFromInt(lhs.int);
        const rf: f64 = if (rhs == .float) rhs.float else @floatFromInt(rhs.int);
        return .{ .folded = .{ .bool_val = switch (op) {
            .eq => lf == rf,
            .ne => lf != rf,
            .lt => lf < rf,
            .le => lf <= rf,
            .gt => lf > rf,
            .ge => lf >= rf,
        } } };
    }
    // bool vs bool — 仅支持 == 和 !=
    if (lhs == .bool_val and rhs == .bool_val) {
        return switch (op) {
            .eq => .{ .folded = .{ .bool_val = lhs.bool_val == rhs.bool_val } },
            .ne => .{ .folded = .{ .bool_val = lhs.bool_val != rhs.bool_val } },
            else => .cannot_fold,
        };
    }
    return .cannot_fold;
}

fn foldLogical(lhs: ConstantValue, rhs: ConstantValue, op: LogicOp) FoldResult {
    if (lhs == .bool_val and rhs == .bool_val) {
        return .{ .folded = .{ .bool_val = switch (op) {
            .and_ => lhs.bool_val and rhs.bool_val,
            .or_ => lhs.bool_val or rhs.bool_val,
        } } };
    }
    return .cannot_fold;
}
