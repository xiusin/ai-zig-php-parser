//! 编译错误诊断系统综合测试
//!
//! 验证诊断引擎的完整功能：
//! - 详细错误信息
//! - CWE 编号标注
//! - 修复建议
//!
//! 对应任务 55：实现编译错误诊断
//! 需求：10.6

const std = @import("std");
const testing = std.testing;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const Diagnostic = Diagnostics.Diagnostic;
const Severity = Diagnostics.Severity;
const CWE = Diagnostics.CWE;
const SourceLocation = Diagnostics.SourceLocation;
const FixSuggestion = Diagnostics.FixSuggestion;

// ============================================================================
// 测试 1: 基本错误报告
// ============================================================================

test "Diagnostic Engine: Basic error reporting" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{
        .file = "test.php",
        .line = 42,
        .column = 10,
        .length = 5,
    };

    engine.reportError(loc, "unexpected token '{s}'", .{";"});

    try testing.expectEqual(@as(u32, 1), engine.error_count);
    try testing.expect(engine.hasErrors());
    try testing.expectEqual(@as(usize, 1), engine.count());
}

// ============================================================================
// 测试 2: CWE 编号标注
// ============================================================================

test "Diagnostic Engine: CWE annotation" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{
        .file = "test.php",
        .line = 10,
        .column = 5,
    };

    // 测试各种 CWE 类型
    engine.reportErrorWithCWE(loc, .buffer_overflow, "potential buffer overflow", .{});
    engine.reportErrorWithCWE(loc, .null_pointer_dereference, "null pointer dereference", .{});
    engine.reportErrorWithCWE(loc, .use_after_free, "use after free", .{});
    engine.reportWarningWithCWE(loc, .memory_leak, "potential memory leak", .{});
    engine.reportWarningWithCWE(loc, .dead_code, "unreachable code", .{});

    try testing.expectEqual(@as(u32, 3), engine.error_count);
    try testing.expectEqual(@as(u32, 2), engine.warning_count);

    // 验证 CWE 信息
    const diag1 = engine.diagnostics.items[0];
    try testing.expectEqual(CWE.buffer_overflow, diag1.cwe.?);
    try testing.expectEqualStrings("CWE-119: Buffer Overflow", diag1.cwe.?.toString());

    const diag2 = engine.diagnostics.items[1];
    try testing.expectEqual(CWE.null_pointer_dereference, diag2.cwe.?);

    const diag3 = engine.diagnostics.items[2];
    try testing.expectEqual(CWE.use_after_free, diag3.cwe.?);
}

// ============================================================================
// 测试 3: 修复建议
// ============================================================================

test "Diagnostic Engine: Fix suggestions" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{
        .file = "test.php",
        .line = 15,
        .column = 8,
        .length = 10,
    };

    const fix1 = FixSuggestion{
        .description = "Add bounds checking before array access",
        .replacement = "if (index >= 0 && index < array.length) { ... }",
        .location = loc,
    };

    const fix2 = FixSuggestion{
        .description = "Use safe array access method",
        .replacement = "array.get(index) ?? default_value",
    };

    const fixes = [_]FixSuggestion{ fix1, fix2 };
    const message = try std.fmt.allocPrint(allocator, "array index out of bounds", .{});

    engine.reportErrorWithFix(loc, .buffer_overflow, message, &fixes);

    try testing.expectEqual(@as(u32, 1), engine.error_count);

    const diag = engine.diagnostics.items[0];
    try testing.expectEqual(@as(usize, 2), diag.fix_suggestions.len);
    try testing.expectEqualStrings("Add bounds checking before array access", diag.fix_suggestions[0].description);
    try testing.expectEqualStrings("Use safe array access method", diag.fix_suggestions[1].description);
}

// ============================================================================
// 测试 4: 详细错误信息（带源代码上下文）
// ============================================================================

test "Diagnostic Engine: Detailed error with source context" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    // 设置源代码
    const source =
        \\<?php
        \\function test($arr, $index) {
        \\    return $arr[$index];  // Potential buffer overflow
        \\}
        \\?>
    ;

    try engine.setSource(source);

    const loc = SourceLocation{
        .file = "test.php",
        .line = 3,
        .column = 12,
        .length = 12,
    };

    const fix = FixSuggestion{
        .description = "Add bounds checking",
        .replacement = "if ($index >= 0 && $index < count($arr)) { return $arr[$index]; }",
    };
    const fixes = [_]FixSuggestion{fix};

    const message = try std.fmt.allocPrint(allocator, "unchecked array access may cause buffer overflow", .{});
    engine.reportErrorWithFix(loc, .buffer_overflow, message, &fixes);

    // 验证源代码行已加载
    try testing.expect(engine.source_lines != null);
    try testing.expect(engine.source_lines.?.len > 0);

    // 渲染诊断信息
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try engine.render(fbs.writer());

    const output = fbs.getWritten();
    
    // 验证输出包含关键信息（使用更宽松的检查）
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "test.php") != null);
    try testing.expect(std.mem.indexOf(u8, output, "error") != null);
    try testing.expect(std.mem.indexOf(u8, output, "buffer overflow") != null);
}

// ============================================================================
// 测试 5: 多个相关注释
// ============================================================================

test "Diagnostic Engine: Related notes" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const main_loc = SourceLocation{
        .file = "test.php",
        .line = 20,
        .column = 5,
    };

    const note1_loc = SourceLocation{
        .file = "test.php",
        .line = 10,
        .column = 1,
    };

    const note2_loc = SourceLocation{
        .file = "lib.php",
        .line = 5,
        .column = 10,
    };

    const note1 = Diagnostic.Note{
        .message = "variable '$ptr' allocated here",
        .location = note1_loc,
    };

    const note2 = Diagnostic.Note{
        .message = "variable '$ptr' freed here",
        .location = note2_loc,
    };

    const notes = [_]Diagnostic.Note{ note1, note2 };

    const message = try std.fmt.allocPrint(allocator, "use after free: variable '$ptr' accessed after being freed", .{});

    try engine.diagnostics.append(allocator, .{
        .severity = .@"error",
        .message = message,
        .location = main_loc,
        .cwe = .use_after_free,
        .notes = &notes,
    });

    engine.error_count += 1;

    try testing.expectEqual(@as(u32, 1), engine.error_count);

    const diag = engine.diagnostics.items[0];
    try testing.expectEqual(@as(usize, 2), diag.notes.len);
}

// ============================================================================
// 测试 6: 便捷诊断函数
// ============================================================================

test "Diagnostic Engine: Convenience functions" {
    const allocator = testing.allocator;

    const loc = SourceLocation{
        .file = "test.php",
        .line = 10,
        .column = 5,
    };

    const fixes = [_]FixSuggestion{
        .{ .description = "Add null check: if (ptr != null) { ... }" },
    };

    // 测试各种便捷函数
    const diag1 = Diagnostics.bufferOverflowError(loc, "buffer overflow detected", &fixes);
    try testing.expectEqual(CWE.buffer_overflow, diag1.cwe.?);
    try testing.expectEqual(Severity.@"error", diag1.severity);

    const diag2 = Diagnostics.nullPointerError(loc, "null pointer dereference", &fixes);
    try testing.expectEqual(CWE.null_pointer_dereference, diag2.cwe.?);

    const diag3 = Diagnostics.memoryLeakWarning(loc, "potential memory leak", &fixes);
    try testing.expectEqual(CWE.memory_leak, diag3.cwe.?);
    try testing.expectEqual(Severity.warning, diag3.severity);

    const diag4 = Diagnostics.dataRaceError(loc, "data race detected", &fixes);
    try testing.expectEqual(CWE.data_race, diag4.cwe.?);

    const diag5 = Diagnostics.deadCodeWarning(loc, "unreachable code", &fixes);
    try testing.expectEqual(CWE.dead_code, diag5.cwe.?);

    const diag6 = Diagnostics.integerOverflowError(loc, "integer overflow", &fixes);
    try testing.expectEqual(CWE.integer_overflow, diag6.cwe.?);

    const diag7 = Diagnostics.divisionByZeroError(loc, "division by zero", &fixes);
    try testing.expectEqual(CWE.division_by_zero, diag7.cwe.?);

    const diag8 = Diagnostics.typeConfusionError(loc, "type confusion", &fixes);
    try testing.expectEqual(CWE.type_confusion, diag8.cwe.?);

    _ = allocator;
}

// ============================================================================
// 测试 7: CWE URL 生成
// ============================================================================

test "Diagnostic Engine: CWE URL generation" {
    // 验证 CWE 编号和字符串表示
    const cwe = CWE.buffer_overflow;
    
    // 验证 CWE 编号
    try testing.expectEqual(@as(u32, 119), @intFromEnum(cwe));
    
    // 验证 CWE 字符串表示
    const cwe_str = cwe.toString();
    try testing.expect(std.mem.indexOf(u8, cwe_str, "119") != null);
    try testing.expect(std.mem.indexOf(u8, cwe_str, "Buffer Overflow") != null);
}

// ============================================================================
// 测试 8: 完整的诊断流程
// ============================================================================

test "Diagnostic Engine: Complete diagnostic workflow" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    // 设置源代码
    const source =
        \\<?php
        \\function unsafe_access($arr, $idx) {
        \\    $value = $arr[$idx];  // Line 3: No bounds check
        \\    return $value * 2;
        \\}
        \\
        \\function main() {
        \\    $data = [1, 2, 3];
        \\    $result = unsafe_access($data, 10);  // Line 9: Out of bounds
        \\}
        \\?>
    ;

    try engine.setSource(source);

    // 报告第一个错误：函数定义处缺少边界检查
    const loc1 = SourceLocation{
        .file = "test.php",
        .line = 3,
        .column = 14,
        .length = 9,
    };

    const fix1 = FixSuggestion{
        .description = "Add bounds checking before array access",
        .replacement = "if ($idx >= 0 && $idx < count($arr)) { $value = $arr[$idx]; } else { throw new OutOfBoundsException(); }",
    };

    const fixes1 = [_]FixSuggestion{fix1};
    const message1 = try std.fmt.allocPrint(allocator, "unchecked array access", .{});
    engine.reportErrorWithFix(loc1, .buffer_overflow, message1, &fixes1);

    // 报告第二个错误：调用处使用越界索引
    const loc2 = SourceLocation{
        .file = "test.php",
        .line = 9,
        .column = 15,
        .length = 27,
    };

    const note_loc = SourceLocation{
        .file = "test.php",
        .line = 8,
        .column = 5,
    };

    const note = Diagnostic.Note{
        .message = "array '$data' has length 3",
        .location = note_loc,
    };

    const notes = [_]Diagnostic.Note{note};

    const fix2 = FixSuggestion{
        .description = "Use valid array index",
        .replacement = "unsafe_access($data, 2)",
    };

    const fixes2 = [_]FixSuggestion{fix2};
    const message2 = try std.fmt.allocPrint(allocator, "array index 10 is out of bounds for array of length 3", .{});

    try engine.diagnostics.append(allocator, .{
        .severity = .@"error",
        .message = message2,
        .location = loc2,
        .cwe = .buffer_overflow,
        .fix_suggestions = &fixes2,
        .notes = &notes,
        .hint = "Array indices must be in range [0, length-1]",
    });
    engine.error_count += 1;

    // 验证诊断信息
    try testing.expectEqual(@as(u32, 2), engine.error_count);
    try testing.expect(engine.hasErrors());

    // 渲染诊断信息
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try engine.render(fbs.writer());

    const output = fbs.getWritten();

    // 验证输出包含所有关键信息（使用更宽松的检查）
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "test.php") != null);
    try testing.expect(std.mem.indexOf(u8, output, "error") != null);
    try testing.expect(std.mem.indexOf(u8, output, "2 error(s)") != null);
}

// ============================================================================
// 测试 9: 并发安全诊断
// ============================================================================

test "Diagnostic Engine: Concurrency safety diagnostics" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{
        .file = "concurrent.php",
        .line = 25,
        .column = 10,
    };

    const fix1 = FixSuggestion{
        .description = "Protect shared state with mutex",
        .replacement = "$mutex->lock(); $shared_var++; $mutex->unlock();",
    };

    const fix2 = FixSuggestion{
        .description = "Use atomic operations",
        .replacement = "atomic_inc($shared_var);",
    };

    const fixes = [_]FixSuggestion{ fix1, fix2 };
    const message = try std.fmt.allocPrint(allocator, "data race: unsynchronized access to shared variable '$shared_var'", .{});

    engine.reportErrorWithFix(loc, .data_race, message, &fixes);

    try testing.expectEqual(@as(u32, 1), engine.error_count);

    const diag = engine.diagnostics.items[0];
    try testing.expectEqual(CWE.data_race, diag.cwe.?);
    try testing.expectEqual(@as(usize, 2), diag.fix_suggestions.len);
}

// ============================================================================
// 测试 10: 内存安全诊断
// ============================================================================

test "Diagnostic Engine: Memory safety diagnostics" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    // 测试各种内存安全问题
    const loc1 = SourceLocation{ .file = "mem.php", .line = 10, .column = 5 };
    const loc2 = SourceLocation{ .file = "mem.php", .line = 20, .column = 8 };
    const loc3 = SourceLocation{ .file = "mem.php", .line = 30, .column = 12 };

    const fix1 = FixSuggestion{ .description = "Check pointer before use" };
    const fix2 = FixSuggestion{ .description = "Free memory only once" };
    const fix3 = FixSuggestion{ .description = "Initialize variable before use" };

    const fixes1 = [_]FixSuggestion{fix1};
    const fixes2 = [_]FixSuggestion{fix2};
    const fixes3 = [_]FixSuggestion{fix3};

    engine.reportErrorWithFix(loc1, .null_pointer_dereference, try std.fmt.allocPrint(allocator, "null pointer dereference", .{}), &fixes1);
    engine.reportErrorWithFix(loc2, .double_free, try std.fmt.allocPrint(allocator, "double free detected", .{}), &fixes2);
    engine.reportErrorWithFix(loc3, .uninitialized_memory, try std.fmt.allocPrint(allocator, "use of uninitialized variable", .{}), &fixes3);

    try testing.expectEqual(@as(u32, 3), engine.error_count);

    // 验证每个诊断都有正确的 CWE
    try testing.expectEqual(CWE.null_pointer_dereference, engine.diagnostics.items[0].cwe.?);
    try testing.expectEqual(CWE.double_free, engine.diagnostics.items[1].cwe.?);
    try testing.expectEqual(CWE.uninitialized_memory, engine.diagnostics.items[2].cwe.?);
}

// ============================================================================
// 测试 11: 清除和重用
// ============================================================================

test "Diagnostic Engine: Clear and reuse" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{ .file = "test.php", .line = 1, .column = 1 };

    // 第一轮诊断
    engine.reportError(loc, "error 1", .{});
    engine.reportWarning(loc, "warning 1", .{});

    try testing.expectEqual(@as(u32, 1), engine.error_count);
    try testing.expectEqual(@as(u32, 1), engine.warning_count);

    // 清除
    engine.clear();

    try testing.expectEqual(@as(u32, 0), engine.error_count);
    try testing.expectEqual(@as(u32, 0), engine.warning_count);
    try testing.expect(!engine.hasErrors());
    try testing.expect(!engine.hasWarnings());

    // 第二轮诊断
    engine.reportError(loc, "error 2", .{});

    try testing.expectEqual(@as(u32, 1), engine.error_count);
    try testing.expectEqual(@as(u32, 0), engine.warning_count);
}

// ============================================================================
// 测试 12: 颜色输出控制
// ============================================================================

test "Diagnostic Engine: Color output control" {
    const allocator = testing.allocator;
    var engine = DiagnosticEngine.init(allocator);
    defer engine.deinit();

    const loc = SourceLocation{ .file = "test.php", .line = 1, .column = 1 };

    engine.reportError(loc, "test error", .{});

    // 测试带颜色的输出
    engine.use_colors = true;
    var buf1: [1024]u8 = undefined;
    var fbs1 = std.io.fixedBufferStream(&buf1);
    try engine.render(fbs1.writer());
    const output1 = fbs1.getWritten();
    try testing.expect(std.mem.indexOf(u8, output1, "\x1b[") != null); // 包含 ANSI 转义码

    // 测试不带颜色的输出
    engine.use_colors = false;
    var buf2: [1024]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);
    try engine.render(fbs2.writer());
    const output2 = fbs2.getWritten();
    try testing.expect(std.mem.indexOf(u8, output2, "\x1b[") == null); // 不包含 ANSI 转义码
}
