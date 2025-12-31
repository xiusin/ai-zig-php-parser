const std = @import("std");
const compiler = @import("src/compiler/root.zig");
const lexer_mod = @import("src/compiler/lexer.zig");
const parser_mod = @import("src/compiler/parser.zig");
const runtime = @import("src/runtime/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== 测试echo多参数功能 ===", .{});

    // 测试PHP代码
    const php_source = "<?php echo \"Hello\", \" \", \"World\", \"\\n\"; echo \"Multiple\", \" \", \"parameters\", \" \", \"work\", \"!\\n\";";

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

    // 检查AST结构
    if (ast < context.nodes.items.len) {
        const root_node = context.nodes.items[ast];
        std.log.info("根节点类型: {}", .{root_node.tag});

        if (root_node.tag == .root) {
            const stmt_count = root_node.data.root.stmts.len;
            std.log.info("语句数量: {}", .{stmt_count});

            // 分析echo语句
            var echo_count: usize = 0;
            for (root_node.data.root.stmts) |stmt_idx| {
                if (stmt_idx < context.nodes.items.len) {
                    const stmt = context.nodes.items[stmt_idx];
                    if (stmt.tag == .echo_stmt) {
                        echo_count += 1;
                        const exprs = stmt.data.echo_stmt.exprs;
                        std.log.info("echo语句 {}: {} 个参数", .{ echo_count, exprs.len });
                        for (exprs, 0..) |expr_idx, i| {
                            std.log.info("  参数 {}: 表达式节点 {}", .{ i + 1, expr_idx });
                        }
                    }
                }
            }
            std.log.info("共发现 {} 个echo语句", .{echo_count});
        }
    }

    std.log.info("=== echo多参数功能测试完成 ===", .{});
}
