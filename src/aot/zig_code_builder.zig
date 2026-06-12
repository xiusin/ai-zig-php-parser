const std = @import("std");
const IR = @import("ir.zig");
const Allocator = std.mem.Allocator;

/// 结构化 Zig 代码构建器
/// 替代 native_linker 中硬编码的字符串拼接，提供：
/// - 动态缩进管理（支持任意嵌套深度）
/// - 类型安全的代码片段生成
/// - 作用域自动管理（花括号匹配）
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED
pub const ZigCodeBuilder = struct {
    allocator: Allocator,
    /// 底层输出缓冲
    buffer: std.ArrayList(u8),
    /// 当前缩进层级（每层 4 空格）
    indent_level: u32,
    /// 缩进栈（用于 scope 自动恢复）
    indent_stack: std.ArrayList(u32),

    const INDENT_UNIT: []const u8 = "    ";

    /// 初始化构建器
    pub fn init(allocator: Allocator) !ZigCodeBuilder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).initCapacity(
                allocator,
                0,
            ) catch unreachable,
            .indent_level = 0,
            .indent_stack = std.ArrayList(u32).initCapacity(
                allocator,
                0,
            ) catch unreachable,
        };
    }

    /// 释放资源
    pub fn deinit(self: *ZigCodeBuilder) void {
        self.buffer.deinit(self.allocator);
        self.indent_stack.deinit(self.allocator);
    }

    /// 获取已构建的代码（只读切片）
    pub fn getCode(self: *const ZigCodeBuilder) []const u8 {
        return self.buffer.items;
    }

    /// 将已构建的代码转移出去并重置
    pub fn toOwnedSlice(self: *ZigCodeBuilder) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    /// 写入当前缩进
    fn writeIndent(self: *ZigCodeBuilder) !void {
        var i: u32 = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.buffer.appendSlice(self.allocator, INDENT_UNIT);
        }
    }

    /// 写入一行带缩进的文本
    pub fn writeLine(self: *ZigCodeBuilder, text: []const u8) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, text);
        try self.buffer.append(self.allocator, '\n');
    }

    /// 写入格式化的一行（带缩进）
    pub fn writeLineFmt(
        self: *ZigCodeBuilder,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        try self.writeIndent();
        var buf: [2048]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, fmt, args) catch |err| switch (err) {
            error.NoSpaceLeft => {
                const str = try std.fmt.allocPrint(self.allocator, fmt, args);
                defer self.allocator.free(str);
                try self.buffer.appendSlice(self.allocator, str);
                try self.buffer.append(self.allocator, '\n');
                return;
            },
        };
        try self.buffer.appendSlice(self.allocator, result);
        try self.buffer.append(self.allocator, '\n');
    }

    /// 写入原始文本（无缩进）
    pub fn writeRaw(self: *ZigCodeBuilder, text: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, text);
    }

    /// 写入注释行
    pub fn writeComment(self: *ZigCodeBuilder, text: []const u8) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "// ");
        try self.buffer.appendSlice(self.allocator, text);
        try self.buffer.append(self.allocator, '\n');
    }

    /// 写入空行
    pub fn writeBlankLine(self: *ZigCodeBuilder) !void {
        try self.buffer.append(self.allocator, '\n');
    }

    /// 增加缩进层级
    pub fn indent(self: *ZigCodeBuilder) void {
        self.indent_level += 1;
    }

    /// 减少缩进层级
    pub fn dedent(self: *ZigCodeBuilder) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    /// 进入新作用域（写入 `{` 并增加缩进）
    pub fn beginScope(self: *ZigCodeBuilder, header: []const u8) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, header);
        try self.buffer.appendSlice(self.allocator, " {\n");
        try self.indent_stack.append(self.allocator, self.indent_level);
        self.indent_level += 1;
    }

    /// 带格式化的作用域开始
    pub fn beginScopeFmt(
        self: *ZigCodeBuilder,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        try self.writeIndent();
        var buf: [2048]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, fmt, args) catch |err| switch (err) {
            error.NoSpaceLeft => {
                const str = try std.fmt.allocPrint(self.allocator, fmt, args);
                defer self.allocator.free(str);
                try self.buffer.appendSlice(self.allocator, str);
                try self.buffer.appendSlice(self.allocator, " {\n");
                try self.indent_stack.append(self.allocator, self.indent_level);
                self.indent_level += 1;
                return;
            },
        };
        try self.buffer.appendSlice(self.allocator, result);
        try self.buffer.appendSlice(self.allocator, " {\n");
        try self.indent_stack.append(self.allocator, self.indent_level);
        self.indent_level += 1;
    }

    /// 结束作用域（恢复缩进并写入 `}`）
    pub fn endScope(self: *ZigCodeBuilder) !void {
        if (self.indent_stack.items.len > 0) {
            self.indent_level = self.indent_stack.pop() orelse self.indent_level;
        } else if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "}\n");
    }

    // ========================================================
    // 类型安全的代码生成辅助方法
    // ========================================================

    /// 生成寄存器赋值语句
    pub fn writeRegAssign(
        self: *ZigCodeBuilder,
        reg_id: usize,
        value_expr: []const u8,
    ) !void {
        try self.writeLineFmt("reg_{d} = {s};", .{ reg_id, value_expr });
    }

    /// 生成 while(true) 循环开始
    pub fn beginWhileTrue(self: *ZigCodeBuilder) !void {
        try self.beginScope("while (true)");
    }

    /// 生成 for 循环（Zig 风格的 while）
    pub fn beginForLoop(
        self: *ZigCodeBuilder,
        var_name: []const u8,
        init_val: i64,
        cond_expr: []const u8,
    ) !void {
        try self.writeLineFmt(
            "var {s}: i64 = {d};",
            .{ var_name, init_val },
        );
        try self.beginScopeFmt(
            "while ({s})",
            .{cond_expr},
        );
    }

    /// 生成 if 条件分支
    pub fn beginIf(self: *ZigCodeBuilder, cond_expr: []const u8) !void {
        try self.beginScopeFmt("if ({s})", .{cond_expr});
    }

    /// 生成 else 分支
    pub fn beginElse(self: *ZigCodeBuilder) !void {
        // 先回退到 if 的缩进，写 } else {
        if (self.indent_stack.items.len > 0) {
            self.indent_level = self.indent_stack.getLast();
        } else if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "} else {\n");
        self.indent_level += 1;
    }

    /// 生成 break 语句
    pub fn writeBreak(self: *ZigCodeBuilder) !void {
        try self.writeLine("break;");
    }

    /// 生成 continue 语句
    pub fn writeContinue(self: *ZigCodeBuilder) !void {
        try self.writeLine("continue;");
    }

    /// 生成类型安全的值表达式
    /// 根据源类型和目标类型自动注入转换
    pub fn writeTypedValueExpr(
        self: *ZigCodeBuilder,
        reg_id: usize,
        source_type: IR.Type,
        target_type: IR.Type,
    ) !void {
        const src_tag = @as(std.meta.Tag(IR.Type), source_type);
        const tgt_tag = @as(std.meta.Tag(IR.Type), target_type);

        if (src_tag == tgt_tag) {
            // 类型一致，直接赋值
            try self.writeLineFmt("reg_{d}", .{reg_id});
            return;
        }

        // i64 → Value
        if (src_tag == .i64 and tgt_tag == .php_value) {
            try self.writeLineFmt(
                "runtime.Value.initInt(reg_{d})",
                .{reg_id},
            );
            return;
        }

        // f64 → Value
        if (src_tag == .f64 and tgt_tag == .php_value) {
            try self.writeLineFmt(
                "runtime.Value.initFloat(reg_{d})",
                .{reg_id},
            );
            return;
        }

        // bool → Value
        if (src_tag == .bool and tgt_tag == .php_value) {
            try self.writeLineFmt(
                "runtime.Value.initBool(reg_{d})",
                .{reg_id},
            );
            return;
        }

        // Value → i64
        if (src_tag == .php_value and tgt_tag == .i64) {
            try self.writeLineFmt(
                "reg_{d}.asInt()",
                .{reg_id},
            );
            return;
        }

        // Value → f64
        if (src_tag == .php_value and tgt_tag == .f64) {
            try self.writeLineFmt(
                "reg_{d}.asFloat()",
                .{reg_id},
            );
            return;
        }

        // 兜底：直接使用
        try self.writeLineFmt("reg_{d}", .{reg_id});
    }

    /// 生成类型转换表达式字符串（返回格式化的表达式）
    pub fn formatTypeCast(
        self: *ZigCodeBuilder,
        reg_id: usize,
        source_type: IR.Type,
        target_type: IR.Type,
    ) ![]u8 {
        const src_tag = @as(std.meta.Tag(IR.Type), source_type);
        const tgt_tag = @as(std.meta.Tag(IR.Type), target_type);

        if (src_tag == tgt_tag) {
            return std.fmt.allocPrint(self.allocator, "reg_{d}", .{reg_id});
        }
        if (src_tag == .i64 and tgt_tag == .php_value) {
            return std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{reg_id});
        }
        if (src_tag == .f64 and tgt_tag == .php_value) {
            return std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{reg_id});
        }
        if (src_tag == .bool and tgt_tag == .php_value) {
            return std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{reg_id});
        }
        if (src_tag == .php_value and tgt_tag == .i64) {
            return std.fmt.allocPrint(self.allocator, "reg_{d}.asInt()", .{reg_id});
        }
        if (src_tag == .php_value and tgt_tag == .f64) {
            return std.fmt.allocPrint(self.allocator, "reg_{d}.asFloat()", .{reg_id});
        }
        return std.fmt.allocPrint(self.allocator, "reg_{d}", .{reg_id});
    }
};

// ============================================================
// 单元测试
// ============================================================

test "ZigCodeBuilder basic indentation" {
    const allocator = std.testing.allocator;
    var builder = try ZigCodeBuilder.init(allocator);
    defer builder.deinit();

    try builder.writeLine("const x = 1;");
    try builder.beginScope("while (true)");
    try builder.writeLine("x += 1;");
    try builder.beginScope("if (x > 10)");
    try builder.writeLine("break;");
    try builder.endScope();
    try builder.endScope();

    const code = builder.getCode();
    // 验证缩进层次正确
    try std.testing.expect(std.mem.indexOf(u8, code, "const x = 1;\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "    x += 1;\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "        break;\n") != null);
}

test "ZigCodeBuilder nested scopes" {
    const allocator = std.testing.allocator;
    var builder = try ZigCodeBuilder.init(allocator);
    defer builder.deinit();

    // 模拟 3 层嵌套循环
    try builder.beginWhileTrue();
    try builder.writeComment("outer loop");
    try builder.beginWhileTrue();
    try builder.writeComment("middle loop");
    try builder.beginWhileTrue();
    try builder.writeComment("inner loop");
    try builder.writeBreak();
    try builder.endScope();
    try builder.endScope();
    try builder.endScope();

    const code = builder.getCode();
    // 三层嵌套后的 break 应有 12 空格缩进
    try std.testing.expect(std.mem.indexOf(u8, code, "            break;\n") != null);
}
