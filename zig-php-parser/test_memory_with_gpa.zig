// 使用Zig的GeneralPurposeAllocator检测内存泄漏
// 这个工具可以在macOS上使用（Valgrind不支持macOS）

const std = @import("std");

pub fn main() !void {
    // 使用GeneralPurposeAllocator，它会检测内存泄漏
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .thread_safe = true,
    }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("\n❌ 检测到内存泄漏！\n", .{});
            std.process.exit(1);
        } else {
            std.debug.print("\n✓ 无内存泄漏\n", .{});
        }
    }
    
    const allocator = gpa.allocator();
    
    std.debug.print("====================================\n", .{});
    std.debug.print("内存泄漏检测工具\n", .{});
    std.debug.print("====================================\n\n", .{});
    
    // 获取命令行参数
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        std.debug.print("用法: {s} <可执行文件>\n", .{args[0]});
        std.debug.print("示例: {s} ./test_memory_leak_1_simple\n", .{args[0]});
        return error.InvalidArguments;
    }
    
    const exe_path = args[1];
    std.debug.print("测试程序: {s}\n\n", .{exe_path});
    
    // 运行测试程序
    std.debug.print("运行测试程序...\n", .{});
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_path},
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    // 显示输出
    if (result.stdout.len > 0) {
        std.debug.print("\n--- 标准输出 ---\n{s}\n", .{result.stdout});
    }
    
    if (result.stderr.len > 0) {
        std.debug.print("\n--- 标准错误 ---\n{s}\n", .{result.stderr});
    }
    
    // 检查退出码
    switch (result.term) {
        .Exited => |code| {
            if (code == 0) {
                std.debug.print("\n✓ 程序正常退出\n", .{});
            } else {
                std.debug.print("\n✗ 程序异常退出，退出码: {d}\n", .{code});
                return error.ProgramFailed;
            }
        },
        else => {
            std.debug.print("\n✗ 程序异常终止\n", .{});
            return error.ProgramCrashed;
        },
    }
}
