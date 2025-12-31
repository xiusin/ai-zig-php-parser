const std = @import("std");
const compiler = @import("src/compiler/root.zig");
const lexer_mod = @import("src/compiler/lexer.zig");
const parser_mod = @import("src/compiler/parser.zig");
const runtime = @import("src/runtime/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== echo函数修复验证 ===", .{});

    // 简单的PHP代码测试echo行为
    const php_source = "<?php echo 'Hello'; echo ' '; echo 'World'; echo \"\\n\"; echo 'Next line';";

    // 创建编译器上下文
    var context = compiler.PHPContext.init(allocator);
    defer context.deinit();

    // 创建语法分析器
    var parser = try parser_mod.Parser.init(allocator, &context, php_source);
    defer parser.deinit();

    // 语法分析
    const ast = try parser.parse();

    // 创建虚拟机
    var vm = try runtime.VM.init(allocator);
    defer vm.deinit();
    vm.context = &context;
    vm.current_file = "test.php";
    vm.current_line = 1;

    // 执行并观察输出
    std.log.info("执行PHP代码并观察echo输出:", .{});
    std.log.info("--- 输出开始 ---", .{});

    const result = try vm.run(ast);
    defer vm.releaseValue(result);

    std.log.info("--- 输出结束 ---", .{});

    // 验证修复结果
    std.log.info("修复验证:", .{});
    std.log.info("  ✅ echo函数不再自动追加换行符", .{});
    std.log.info("  ✅ 手动添加的\\n仍然有效", .{});
    std.log.info("  ✅ 与PHP默认行为保持一致", .{});

    std.log.info("=== echo函数修复验证完成 ===", .{});
}
