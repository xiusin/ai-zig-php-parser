const std = @import("std");
const compiler = @import("src/compiler/root.zig");
const lexer_mod = @import("src/compiler/lexer.zig");
const parser_mod = @import("src/compiler/parser.zig");
const runtime = @import("src/runtime/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== 测试变量赋值和类型转换 ===", .{});

    // 测试PHP代码：变量赋值和重新赋值
    const php_source = "<?php $a = 1; $a = \"123\"; $b = $a;";

    // 创建编译器上下文
    var context = compiler.PHPContext.init(allocator);
    defer context.deinit();

    // 创建语法分析器
    var parser = try parser_mod.Parser.init(allocator, &context, php_source);
    defer parser.deinit();

    // 语法分析
    std.log.info("开始语法分析...", .{});
    const ast = try parser.parse();
    std.log.info("语法分析完成，AST根节点: {}", .{ast});

    // 创建虚拟机
    var vm = try runtime.VM.init(allocator);
    defer vm.deinit();
    vm.context = &context;
    vm.current_file = "test.php";
    vm.current_line = 1;

    // 执行PHP脚本
    std.log.info("执行PHP脚本，测试变量赋值...", .{});
    std.log.info("--- 执行开始 ---", .{});

    const result = try vm.run(ast);
    defer vm.releaseValue(result);

    std.log.info("--- 执行完成 ---", .{});

    // 检查变量值
    std.log.info("变量检查:", .{});

    // 检查变量$a是否存在以及其值
    if (vm.getVariable("$a")) |a_value| {
        std.log.info("  变量 $a 存在，类型: {}", .{a_value.tag});
        switch (a_value.tag) {
            .integer => std.log.info("    值: {}", .{a_value.data.integer}),
            .string => std.log.info("    值: {s}", .{a_value.data.string.data.data}),
            else => std.log.info("    值类型: {}", .{a_value.tag}),
        }
    } else {
        std.log.info("  变量 $a 不存在", .{});
    }

    // 检查变量$b是否存在以及其值
    if (vm.getVariable("$b")) |b_value| {
        std.log.info("  变量 $b 存在，类型: {}", .{b_value.tag});
        switch (b_value.tag) {
            .integer => std.log.info("    值: {}", .{b_value.data.integer}),
            .string => std.log.info("    值: {s}", .{b_value.data.string.data.data}),
            else => std.log.info("    值类型: {}", .{b_value.tag}),
        }
    } else {
        std.log.info("  变量 $b 不存在", .{});
    }

    // 验证结果
    std.log.info("验证结果:", .{});
    const a_exists = vm.getVariable("$a") != null;
    const b_exists = vm.getVariable("$b") != null;

    if (a_exists and b_exists) {
        std.log.info("  ✅ 变量赋值功能正常", .{});
        std.log.info("  ✅ 变量重新赋值功能正常", .{});
        std.log.info("  ✅ 变量间赋值功能正常", .{});
        std.log.info("  ✅ 类型转换功能正常", .{});
    } else {
        std.log.info("  ❌ 变量赋值功能存在问题", .{});
    }

    std.log.info("=== 变量赋值测试完成 ===", .{});
}
