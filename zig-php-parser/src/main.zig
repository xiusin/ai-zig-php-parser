const std = @import("std");
const ast = @import("compiler/ast.zig");
const parser = @import("compiler/parser.zig");
const vm = @import("runtime/vm.zig");
const types = @import("runtime/types.zig");
const Value = types.Value;
const Environment = @import("runtime/environment.zig");
const PHPContext = @import("compiler/parser.zig").PHPContext;
const ExecutionMode = vm.ExecutionMode;
const aot = @import("aot/root.zig");

/// 打印使用帮助
fn printUsage() void {
    std.debug.print(
        \\Usage: zig-php [options] <file.php>
        \\       zig-php --compile [compile-options] <file.php>
        \\
        \\Interpreter Options:
        \\  --mode=<mode>    Execution mode: tree, bytecode, auto (default: tree)
        \\  --help, -h       Show this help message
        \\  --version, -v    Show version information
        \\
        \\AOT Compiler Options:
        \\  --compile              Compile PHP to native executable
        \\  --output=<file>        Output file name (default: input name without .php)
        \\  --target=<triple>      Target platform (e.g., x86_64-linux-gnu)
        \\  --optimize=<level>     Optimization level: debug, release-safe,
        \\                         release-fast, release-small (default: debug)
        \\  --static               Generate fully static linked executable
        \\  --dump-ir              Dump generated IR for debugging
        \\  --dump-ast             Dump parsed AST for debugging
        \\  --verbose              Verbose output during compilation
        \\  --list-targets         List all supported target platforms
        \\
        \\Execution Modes:
        \\  tree      Tree-walking interpreter (most compatible, default)
        \\  bytecode  Bytecode virtual machine (higher performance)
        \\  auto      Automatically select based on code characteristics
        \\
        \\Examples:
        \\  zig-php script.php                        Run with interpreter
        \\  zig-php --mode=bytecode app.php           Run with bytecode VM
        \\  zig-php --compile hello.php               Compile to native executable
        \\  zig-php --compile --output=app hello.php  Compile with custom output name
        \\  zig-php --compile --optimize=release-fast --static app.php
        \\
    , .{});
}

/// 打印版本信息
fn printVersion() void {
    std.debug.print("zig-php 0.1.0 (Zig PHP Interpreter)\n", .{});
    std.debug.print("Execution modes: tree-walking, bytecode, auto\n", .{});
    std.debug.print("AOT compilation: supported\n", .{});
}

/// 打印支持的目标平台列表
fn printTargets() void {
    std.debug.print("Supported target platforms:\n\n", .{});
    for (aot.supported_targets) |target| {
        std.debug.print("  {s}\n", .{target});
    }
    std.debug.print("\nUse --target=<triple> to specify a target platform.\n", .{});
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

    // AOT compilation options
    var compile_mode = false;
    var aot_options = aot.CompileOptions{
        .input_file = "",
    };

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            return;
        } else if (std.mem.eql(u8, arg, "--list-targets")) {
            printTargets();
            return;
        } else if (std.mem.eql(u8, arg, "--compile")) {
            compile_mode = true;
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            aot_options.output_file = arg[9..];
        } else if (std.mem.startsWith(u8, arg, "--target=")) {
            const target_str = arg[9..];
            aot_options.target = aot.Target.fromString(target_str) catch {
                std.debug.print("Error: Invalid target '{s}'\n", .{target_str});
                std.debug.print("Use --list-targets to see supported platforms.\n", .{});
                return;
            };
        } else if (std.mem.startsWith(u8, arg, "--optimize=")) {
            const opt_str = arg[11..];
            if (aot.OptimizeLevel.fromString(opt_str)) |level| {
                aot_options.optimize_level = level;
            } else {
                std.debug.print("Error: Invalid optimization level '{s}'\n", .{opt_str});
                std.debug.print("Valid levels: debug, release-safe, release-fast, release-small\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--static")) {
            aot_options.static_link = true;
        } else if (std.mem.eql(u8, arg, "--dump-ir")) {
            aot_options.dump_ir = true;
        } else if (std.mem.eql(u8, arg, "--dump-ast")) {
            aot_options.dump_ast = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            aot_options.verbose = true;
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

    // Handle AOT compilation mode
    if (compile_mode) {
        if (php_file) |filename| {
            aot_options.input_file = filename;
            try runAOTCompilation(allocator, aot_options);
        } else {
            std.debug.print("Error: No input file specified for compilation.\n", .{});
            printUsage();
        }
        return;
    }

    // Regular interpreter mode
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

/// Run AOT compilation
fn runAOTCompilation(allocator: std.mem.Allocator, options: aot.CompileOptions) !void {
    var diagnostics = aot.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    if (options.verbose) {
        std.debug.print("AOT Compiler starting...\n", .{});
        std.debug.print("  Input file: {s}\n", .{options.input_file});
        if (options.output_file) |out| {
            std.debug.print("  Output file: {s}\n", .{out});
        }
        if (options.target.toTriple(allocator)) |target_triple| {
            defer allocator.free(target_triple);
            std.debug.print("  Target: {s}\n", .{target_triple});
        } else |_| {
            std.debug.print("  Target: unknown\n", .{});
        }
        std.debug.print("  Optimize: {s}\n", .{options.optimize_level.toString()});
        std.debug.print("  Static link: {}\n", .{options.static_link});
    }

    // Read source file
    const file = std.fs.cwd().openFile(options.input_file, .{}) catch |err| {
        diagnostics.reportError(
            .{ .file = options.input_file },
            "cannot open file: {s}",
            .{@errorName(err)},
        );
        diagnostics.printToStderr();
        return;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const source = try allocator.allocSentinel(u8, file_size, 0);
    defer allocator.free(source);
    _ = try file.readAll(source);

    // Set source for diagnostic context
    try diagnostics.setSource(source);

    // Parse the source
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var context = PHPContext.init(arena.allocator());

    var p = try parser.Parser.init(arena.allocator(), &context, source);
    const program = p.parse() catch |err| {
        diagnostics.reportError(
            .{ .file = options.input_file },
            "parse error: {s}",
            .{@errorName(err)},
        );
        // Add parser errors to diagnostics
        for (context.errors.items) |error_item| {
            diagnostics.reportError(
                .{ .file = options.input_file, .line = error_item.line, .column = error_item.column },
                "{s}",
                .{error_item.msg},
            );
        }
        diagnostics.printToStderr();
        return;
    };

    if (options.dump_ast) {
        std.debug.print("\n=== AST Dump ===\n", .{});
        std.debug.print("(AST node type: {s})\n", .{@typeName(@TypeOf(program))});
        std.debug.print("=== End AST ===\n\n", .{});
    }

    if (options.dump_ir) {
        std.debug.print("\n=== IR Dump ===\n", .{});
        std.debug.print("(IR generation not yet implemented)\n", .{});
        std.debug.print("=== End IR ===\n\n", .{});
    }

    // TODO: Implement full AOT compilation pipeline
    // For now, just report that parsing succeeded
    if (options.verbose) {
        std.debug.print("Parsing completed successfully.\n", .{});
        std.debug.print("Note: Full AOT compilation pipeline not yet implemented.\n", .{});
    } else {
        std.debug.print("AOT compilation not yet fully implemented.\n", .{});
        std.debug.print("Parsing succeeded. Use --dump-ast to see the AST.\n", .{});
    }
}
