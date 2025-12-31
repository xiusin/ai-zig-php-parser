const std = @import("std");
const ast = @import("compiler/ast.zig");
const parser = @import("compiler/parser.zig");
const vm = @import("runtime/vm.zig");
const types = @import("runtime/types.zig");
const Value = types.Value;
const Environment = @import("runtime/environment.zig");
const PHPContext = @import("compiler/parser.zig").PHPContext;
const ExecutionMode = vm.ExecutionMode;

/// 打印使用帮助
fn printUsage() void {
    std.debug.print(
        \\Usage: zig-php [options] <file.php>
        \\
        \\Options:
        \\  --mode=<mode>    Execution mode: tree, bytecode, auto (default: tree)
        \\  --help, -h       Show this help message
        \\  --version, -v    Show version information
        \\
        \\Execution Modes:
        \\  tree      Tree-walking interpreter (most compatible, default)
        \\  bytecode  Bytecode virtual machine (higher performance)
        \\  auto      Automatically select based on code characteristics
        \\
        \\Examples:
        \\  zig-php script.php              Run with tree-walking interpreter
        \\  zig-php --mode=bytecode app.php Run with bytecode VM
        \\  zig-php --mode=auto test.php    Auto-select execution mode
        \\
    , .{});
}

/// 打印版本信息
fn printVersion() void {
    std.debug.print("zig-php 0.1.0 (Zig PHP Interpreter)\n", .{});
    std.debug.print("Execution modes: tree-walking, bytecode, auto\n", .{});
}

/// 解析执行模式参数
fn parseExecutionMode(mode_str: []const u8) ?ExecutionMode {
    if (std.mem.eql(u8, mode_str, "tree")) {
        return .tree_walking;
    } else if (std.mem.eql(u8, mode_str, "bytecode")) {
        return .bytecode;
    } else if (std.mem.eql(u8, mode_str, "auto")) {
        return .auto;
    }
    return null;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var context = PHPContext.init(arena_allocator);

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse command line options
    var execution_mode: ExecutionMode = .tree_walking;
    var php_file: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            return;
        } else if (std.mem.startsWith(u8, arg, "--mode=")) {
            const mode_str = arg[7..];
            if (parseExecutionMode(mode_str)) |mode| {
                execution_mode = mode;
            } else {
                std.debug.print("Error: Unknown execution mode '{s}'\n", .{mode_str});
                std.debug.print("Valid modes: tree, bytecode, auto\n", .{});
                return;
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown option '{s}'\n", .{arg});
            printUsage();
            return;
        } else {
            // Assume it's a PHP file
            php_file = arg;
        }
    }

    var php_code: [:0]const u8 = undefined;

    if (php_file) |filename| {
        // Read PHP file from command line argument
        const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
            std.debug.print("Error opening file '{s}': {s}\n", .{ filename, @errorName(err) });
            return;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const contents = try arena_allocator.allocSentinel(u8, file_size, 0);

        _ = try file.readAll(contents);
        php_code = contents;
    } else {
        // Default code if no file specified
        php_code = "<?php echo 42;";
    }

    var p = try parser.Parser.init(arena_allocator, &context, php_code);
    const program = p.parse() catch |err| {
        std.debug.print("Error parsing code: {s}\n", .{@errorName(err)});
        if (context.errors.items.len > 0) {
            for (context.errors.items) |error_item| {
                std.debug.print("Parse error: {s}\n", .{error_item.msg});
            }
        }
        return;
    };

    var vm_instance = try vm.VM.init(allocator);
    vm_instance.context = &context;
    vm_instance.setExecutionMode(execution_mode);
    defer vm_instance.deinit();

    const result = vm_instance.run(program) catch |err| {
        if (err == error.Return) {
            const ret = vm_instance.return_value orelse Value.initNull();
            vm_instance.return_value = null;
            return ret.release(allocator);
        }
        // If it's a runtime exception (handled within VM but returned as error here), we just exit
        // If it's a Zig error, we print it
        std.debug.print("Runtime error: {s}\n", .{@errorName(err)});
        return;
    };

    // Release the final result to prevent memory leak
    result.release(allocator);
}
