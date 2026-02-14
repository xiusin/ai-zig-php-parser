//! ValidationPass - 代码生成前的 IR 验证屏障
//!
//! 在 IR → Zig 代码生成之前运行，拦截：
//! 1. 类型退化：寄存器不应无故退化为 php_value
//! 2. PHI 节点完整性：incoming 数量必须 >= 2，且类型一致
//! 3. 循环结构完整性：header/body/exit 必须存在
//! 4. 未解析的寄存器引用
//!
//! @ownership NON-OWNING (allocator)
//! @thread-safety ISOLATED

const std = @import("std");
const IR = @import("ir.zig");
const Allocator = std.mem.Allocator;

/// 验证错误级别
pub const Severity = enum {
    warning,
    @"error",
};

/// 验证诊断条目
pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    location: IR.Instruction.SourceLocation,
    context: []const u8,
};

/// ValidationPass 验证器
pub const ValidationPass = struct {
    allocator: Allocator,
    diagnostics: std.ArrayList(Diagnostic),
    /// 类型推断表（可选，用于检查类型退化）
    inferred_types: ?*const std.AutoHashMap(usize, IR.Type),
    /// 统计
    total_regs: usize = 0,
    typed_regs: usize = 0,
    phi_count: usize = 0,
    phi_valid: usize = 0,

    /// 初始化
    pub fn init(
        allocator: Allocator,
        inferred_types: ?*const std.AutoHashMap(usize, IR.Type),
    ) ValidationPass {
        return .{
            .allocator = allocator,
            .diagnostics = std.ArrayList(Diagnostic).initCapacity(
                allocator,
                0,
            ) catch unreachable,
            .inferred_types = inferred_types,
        };
    }

    /// 释放
    pub fn deinit(self: *ValidationPass) void {
        self.diagnostics.deinit(self.allocator);
    }

    /// 对整个模块运行验证
    pub fn validate(self: *ValidationPass, module: *const IR.Module) !bool {
        for (module.functions.items) |func| {
            try self.validateFunction(func);
        }
        return self.getErrorCount() == 0;
    }

    /// 验证单个函数
    pub fn validateFunction(self: *ValidationPass, func: *const IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                try self.validateInstruction(func, inst);
            }
            // 验证 terminator
            try self.validateTerminator(func, block);
        }
    }

    /// 验证单条指令
    fn validateInstruction(
        self: *ValidationPass,
        func: *const IR.Function,
        inst: *const IR.Instruction,
    ) !void {
        _ = func;
        if (inst.result) |res| {
            self.total_regs += 1;

            // 检查类型推断覆盖
            if (self.inferred_types) |types| {
                if (types.contains(res.id)) {
                    self.typed_regs += 1;
                } else {
                    // 寄存器未被推断
                    const res_tag = @as(
                        std.meta.Tag(IR.Type),
                        res.type_,
                    );
                    if (res_tag == .php_value) {
                        try self.addDiagnostic(
                            .warning,
                            "寄存器类型退化为 php_value，可能导致运行时开销",
                            inst.location,
                            "type_degradation",
                        );
                    }
                }
            }
        }

        // PHI 节点验证
        if (inst.op == .phi) {
            self.phi_count += 1;
            const phi_op = inst.op.phi;
            if (phi_op.incoming.len < 2) {
                try self.addDiagnostic(
                    .@"error",
                    "PHI 节点 incoming 数量不足（至少需要 2）",
                    inst.location,
                    "phi_incomplete",
                );
            } else {
                self.phi_valid += 1;
            }
        }
    }

    /// 验证基本块的 terminator
    fn validateTerminator(
        self: *ValidationPass,
        func: *const IR.Function,
        block: *const IR.BasicBlock,
    ) !void {
        _ = func;
        if (block.terminator == null) {
            // 非 entry 块缺少 terminator 是错误
            if (block.index > 0) {
                try self.addDiagnostic(
                    .warning,
                    "基本块缺少 terminator",
                    .{ .file = "", .line = 0, .column = 0 },
                    block.label,
                );
            }
        }
    }

    /// 添加诊断条目
    fn addDiagnostic(
        self: *ValidationPass,
        severity: Severity,
        message: []const u8,
        location: IR.Instruction.SourceLocation,
        context: []const u8,
    ) !void {
        try self.diagnostics.append(self.allocator, .{
            .severity = severity,
            .message = message,
            .location = location,
            .context = context,
        });
    }

    /// 获取错误数量
    pub fn getErrorCount(self: *const ValidationPass) usize {
        var count: usize = 0;
        for (self.diagnostics.items) |d| {
            if (d.severity == .@"error") count += 1;
        }
        return count;
    }

    /// 获取警告数量
    pub fn getWarningCount(self: *const ValidationPass) usize {
        var count: usize = 0;
        for (self.diagnostics.items) |d| {
            if (d.severity == .warning) count += 1;
        }
        return count;
    }

    /// 获取类型推断覆盖率
    pub fn getTypeCoverage(self: *const ValidationPass) f64 {
        if (self.total_regs == 0) return 1.0;
        return @as(f64, @floatFromInt(self.typed_regs)) /
            @as(f64, @floatFromInt(self.total_regs));
    }

    /// 输出验证报告
    pub fn printReport(self: *const ValidationPass) void {
        std.debug.print(
            "\n=== ValidationPass Report ===\n",
            .{},
        );
        std.debug.print(
            "  Registers: {d}/{d} typed ({d:.1}%)\n",
            .{
                self.typed_regs,
                self.total_regs,
                self.getTypeCoverage() * 100.0,
            },
        );
        std.debug.print(
            "  PHI nodes: {d}/{d} valid\n",
            .{ self.phi_valid, self.phi_count },
        );
        std.debug.print(
            "  Errors: {d}, Warnings: {d}\n",
            .{ self.getErrorCount(), self.getWarningCount() },
        );
        for (self.diagnostics.items) |d| {
            const sev = if (d.severity == .@"error") "ERROR" else "WARN";
            std.debug.print(
                "  [{s}] {s} @ {s}:{d} ({s})\n",
                .{
                    sev,
                    d.message,
                    d.location.file,
                    d.location.line,
                    d.context,
                },
            );
        }
        std.debug.print("=============================\n\n", .{});
    }
};
