const std = @import("std");
const Lexer = @import("src/compiler/lexer.zig").Lexer;
const Parser = @import("src/compiler/parser.zig").Parser;
const Context = @import("src/compiler/context.zig").Context;
const VM = @import("src/runtime/vm.zig").VM;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 验证String/Array方法调用 ===\n", .{});

    // 测试String方法
    const string_test =
        \\<?php
        \\$str = "hello world";
        \\$upper = $str->toUpper();
        \\echo $upper;
        \\echo "\n";
        \\$len = $str->length();
        \\echo "Length: ";
        \\echo $len;
        \\echo "\n";
    ;

    std.debug.print("\n--- 测试String方法 ---\n", .{});
    std.debug.print("PHP代码:\n{s}\n", .{string_test});

    try runPHPCode(allocator, string_test);

    // 测试Array方法
    const array_test =
        \\<?php
        \\$arr = [1, 2, 3];
        \\$count = $arr->count();
        \\echo "Count: ";
        \\echo $count;
        \\echo "\n";
        \\$keys = $arr->keys();
        \\print_r($keys);
    ;

    std.debug.print("\n--- 测试Array方法 ---\n", .{});
    std.debug.print("PHP代码:\n{s}\n", .{array_test});

    try runPHPCode(allocator, array_test);

    std.debug.print("\n=== 验证完成 ===\n", .{});
}

fn runPHPCode(allocator: std.mem.Allocator, code: []const u8) !void {
    var lexer = Lexer.init(code);
    var context = Context.init(allocator);
    defer context.deinit();

    var parser = Parser.init(allocator, &lexer, &context);
    const root = parser.parse() catch |err| {
        std.debug.print("解析错误: {any}\n", .{err});
        return err;
    };

    std.debug.print("解析成功，AST根节点: {d}\n", .{root});

    var vm = try VM.init(allocator, &context);
    defer vm.deinit();

    std.debug.print("执行PHP脚本...\n", .{});
    std.debug.print("--- 输出开始 ---\n", .{});

    const result = vm.run(root) catch |err| {
        std.debug.print("执行错误: {any}\n", .{err});
        return err;
    };

    std.debug.print("--- 输出结束 ---\n", .{});
    std.debug.print("执行结果: ", .{});
    try result.print();
    std.debug.print("\n", .{});
}
