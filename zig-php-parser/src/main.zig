const std = @import("std");
const compiler = @import("compiler");
const runtime = @import("runtime");
const ast = compiler.ast;
const parser = compiler.parser;
const vm = runtime.vm;
const types = runtime.types;
const Value = types.Value;
const environment = runtime.environment;
const PHPContext = compiler.PHPContext;
const ExecutionMode = vm.ExecutionMode;
const aot = @import("aot/root.zig");
const aot_runtime = @import("aot/runtime_lib.zig");
const SyntaxMode = compiler.SyntaxMode;
const SyntaxConfig = compiler.SyntaxConfig;
const config_loader = @import("config/loader.zig");
const ConfigLoader = config_loader.ConfigLoader;

/// 打印使用帮助
fn printUsage() void {
    std.debug.print(
        \\Usage: zig-php [options] <file.php>
        \\       zig-php --compile [compile-options] <file.php>
        \\
        \\Interpreter Options:
        \\  --mode=<mode>      Execution mode: tree, bytecode, fast, auto (default: tree)
        \\  --jit              Enable JIT (bytecode mode only)
        \\  --syntax=<syntax>  Syntax mode: php, go (default: php)
        \\  --config=<file>    Load configuration from specified file
        \\  --help, -h         Show this help message
        \\  --version, -v      Show version information
        \\
        \\AOT Compiler Options:
        \\  --compile              Compile PHP to native executable
        \\  --output=<file>        Output file name (default: input name without .php)
        \\  --target=<triple>      Target platform (e.g., x86_64-linux-gnu)
        \\  --optimize=<level>     Optimization level: debug, release-safe,
        \\                         release-fast, release-small (default: debug)
        \\  --static               Generate fully static linked executable
        \\  --no-static            Disable static linking
        \\  --no-debug-info        Disable debug info (implies strip in non-Debug)
        \\  --no-link              Skip final link step (emits Zig code)
        \\  --dump-ir              Dump generated IR for debugging
        \\  --emit-ir[=<file>]     Emit optimized IR to file
        \\  --dump-ast             Dump parsed AST for debugging
        \\  --dump-zig             Dump generated Zig code
        \\  --dump-zig-path=<file> Path for dumped Zig code
        \\  --emit-asm[=<file>]    Emit assembly (.s) from Zig compilation
        \\  --emit-llvm-ir[=<file>] Emit LLVM IR (.ll) from Zig compilation
        \\  --emit-llvm-bc[=<file>] Emit LLVM bitcode (.bc) from Zig compilation
        \\  --mcpu=<cpu>           Pass -mcpu=<cpu> to Zig (e.g. native)
        \\  --zig-flag=<flag>      Extra flag passed to zig build-exe (repeatable)
        \\  --timing               Print per-stage AOT compilation timings
        \\  --timing-json=<file>   Write per-stage AOT timings as JSON
        \\  --verify-ir            Verify IR after each optimization pass
        \\  --no-opt-fallback      Disable conservative fallback on opt failure
        \\  --aot-disable-pass=<p> Disable specific IR pass
        \\  --aot-enable-pass=<p>  Enable specific IR pass
        \\  --aot-inline-threshold=<n> Override inlining threshold
        \\  --aot-unroll-factor=<n>    Override loop unroll factor
        \\  --aot-max-iterations=<n>   Override max optimization iterations
        \\  --verbose              Verbose output during compilation
        \\  --lowering-policy=<p>  Lowering policy for unsupported IR ops: warn, error (default: error)
        \\  --list-targets         List all supported target platforms
        \\
        \\Execution Modes:
        \\  tree      Tree-walking interpreter (most compatible, default)
        \\  bytecode  Bytecode virtual machine (higher performance)
        \\  fast      FastVM with NaN-boxing (highest performance, limited features)
        \\  auto      Automatically select based on code characteristics
        \\
        \\Syntax Modes:
        \\  php       PHP-style syntax: $var, $obj->prop (default)
        \\  go        Go-style syntax: var, obj.prop
        \\
        \\Configuration Files:
        \\  The interpreter searches for .zigphp.json or zigphp.config.json
        \\  in the current directory. Command line options override config file.
        \\
        \\Examples:
        \\  zig-php script.php                        Run with interpreter
        \\  zig-php --mode=bytecode app.php           Run with bytecode VM
        \\  zig-php --mode=fast app.php               Run with FastVM (highest perf)
        \\  zig-php --syntax=go app.php               Run with Go-style syntax
        \\  zig-php --config=myconfig.json app.php    Run with custom config
        \\  zig-php --compile hello.php               Compile to native executable
        \\  zig-php --compile --output=app hello.php  Compile with custom output name
        \\  zig-php --compile --optimize=release-fast --static app.php
        \\
    , .{});
}

/// 打印版本信息
fn printVersion() void {
    std.debug.print("zig-php 0.1.0 (Zig PHP Interpreter)\n", .{});
    std.debug.print("Execution modes: tree-walking, bytecode, fast_vm, auto\n", .{});
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
    } else if (std.mem.eql(u8, mode_str, "fast") or std.mem.eql(u8, mode_str, "fast_vm")) {
        // fast_vm 模式使用 FastVM (NaN-boxing 高性能执行)
        return .fast;
    } else if (std.mem.eql(u8, mode_str, "auto")) {
        return .auto;
    }
    return null;
}

fn applyPassToggle(overrides: *aot.PassOverrides, name: []const u8, enabled: bool) !void {
    if (std.mem.eql(u8, name, "dce") or std.mem.eql(u8, name, "dead-code-elimination")) {
        overrides.dead_code_elimination = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "constprop") or std.mem.eql(u8, name, "constant-propagation")) {
        overrides.constant_propagation = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "box-unbox") or std.mem.eql(u8, name, "box-unbox-elim")) {
        overrides.box_unbox_elim = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "inline") or std.mem.eql(u8, name, "function-inlining")) {
        overrides.function_inlining = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "typespec") or std.mem.eql(u8, name, "type-specialization")) {
        overrides.type_specialization = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "cse")) {
        overrides.cse = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "licm")) {
        overrides.licm = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "strength") or std.mem.eql(u8, name, "strength-reduction")) {
        overrides.strength_reduction = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "mem2reg")) {
        overrides.mem2reg = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "unroll") or std.mem.eql(u8, name, "loop-unroll")) {
        overrides.loop_unroll = enabled;
        return;
    }
    if (std.mem.eql(u8, name, "cfg-cleanup") or std.mem.eql(u8, name, "cfg")) {
        overrides.cfg_cleanup = enabled;
        return;
    }
    return error.UnknownPass;
}

pub fn main() !void {
    // Use GPA with safety=false to avoid internal allocation leak warnings.
    // These warnings from safety=true are false positives from Zig's runtime
    // (thread-local storage, internal caches) and don't indicate real leaks.
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .enable_memory_limit = false,
        .safety = false,
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var context = PHPContext.init(arena_allocator);
    defer context.deinit();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Track CLI overrides (null means not specified on CLI)
    var cli_syntax_mode: ?SyntaxMode = null;
    var cli_config_file: ?[]const u8 = null;
    var execution_mode: ExecutionMode = .bytecode;
    var enable_jit = false;
    var php_file: ?[]const u8 = null;

    // AOT compilation options
    var compile_mode = false;
    var aot_options = aot.CompileOptions{
        .input_file = "",
    };
    var aot_zig_flags = std.ArrayList([]const u8).init(allocator);
    defer aot_zig_flags.deinit();

    // First pass: parse CLI arguments to find config file and overrides
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
        } else if (std.mem.startsWith(u8, arg, "--zig-flag=")) {
            try aot_zig_flags.append(arg["--zig-flag=".len..]);
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
        } else if (std.mem.eql(u8, arg, "--no-static")) {
            aot_options.static_link = false;
        } else if (std.mem.eql(u8, arg, "--no-debug-info")) {
            aot_options.debug_info = false;
        } else if (std.mem.eql(u8, arg, "--no-link")) {
            aot_options.link_executable = false;
            if (!aot_options.dump_zig and aot_options.dump_zig_path == null) {
                aot_options.dump_zig = true;
            }
        } else if (std.mem.eql(u8, arg, "--dump-ir")) {
            aot_options.dump_ir = true;
        } else if (std.mem.eql(u8, arg, "--emit-ir")) {
            aot_options.emit_ir_path = "";
        } else if (std.mem.startsWith(u8, arg, "--emit-ir=")) {
            aot_options.emit_ir_path = arg["--emit-ir=".len..];
        } else if (std.mem.eql(u8, arg, "--dump-ast")) {
            aot_options.dump_ast = true;
        } else if (std.mem.eql(u8, arg, "--dump-zig")) {
            aot_options.dump_zig = true;
        } else if (std.mem.startsWith(u8, arg, "--dump-zig-path=")) {
            aot_options.dump_zig = true;
            aot_options.dump_zig_path = arg["--dump-zig-path=".len..];
        } else if (std.mem.eql(u8, arg, "--emit-asm")) {
            aot_options.emit_asm_path = "";
        } else if (std.mem.startsWith(u8, arg, "--emit-asm=")) {
            aot_options.emit_asm_path = arg["--emit-asm=".len..];
        } else if (std.mem.eql(u8, arg, "--emit-llvm-ir")) {
            aot_options.emit_llvm_ir_path = "";
        } else if (std.mem.startsWith(u8, arg, "--emit-llvm-ir=")) {
            aot_options.emit_llvm_ir_path = arg["--emit-llvm-ir=".len..];
        } else if (std.mem.eql(u8, arg, "--emit-llvm-bc")) {
            aot_options.emit_llvm_bc_path = "";
        } else if (std.mem.startsWith(u8, arg, "--emit-llvm-bc=")) {
            aot_options.emit_llvm_bc_path = arg["--emit-llvm-bc=".len..];
        } else if (std.mem.startsWith(u8, arg, "--mcpu=")) {
            aot_options.mcpu = arg["--mcpu=".len..];
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            aot_options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--timing")) {
            aot_options.timing = true;
        } else if (std.mem.startsWith(u8, arg, "--timing-json=")) {
            aot_options.timing = true;
            aot_options.timing_json_path = arg["--timing-json=".len..];
        } else if (std.mem.eql(u8, arg, "--verify-ir")) {
            aot_options.verify_ir = true;
        } else if (std.mem.eql(u8, arg, "--no-opt-fallback")) {
            aot_options.fallback_on_opt_fail = false;
        } else if (std.mem.startsWith(u8, arg, "--aot-disable-pass=")) {
            const name = arg["--aot-disable-pass=".len..];
            applyPassToggle(&aot_options.pass_overrides, name, false) catch {
                std.debug.print("Error: Unknown AOT pass '{s}'\n", .{name});
                return;
            };
        } else if (std.mem.startsWith(u8, arg, "--aot-enable-pass=")) {
            const name = arg["--aot-enable-pass=".len..];
            applyPassToggle(&aot_options.pass_overrides, name, true) catch {
                std.debug.print("Error: Unknown AOT pass '{s}'\n", .{name});
                return;
            };
        } else if (std.mem.startsWith(u8, arg, "--aot-inline-threshold=")) {
            const v = std.fmt.parseInt(u32, arg["--aot-inline-threshold=".len..], 10) catch {
                std.debug.print("Error: Invalid --aot-inline-threshold\n", .{});
                return;
            };
            aot_options.pass_overrides.inline_threshold = v;
        } else if (std.mem.startsWith(u8, arg, "--aot-unroll-factor=")) {
            const v = std.fmt.parseInt(u32, arg["--aot-unroll-factor=".len..], 10) catch {
                std.debug.print("Error: Invalid --aot-unroll-factor\n", .{});
                return;
            };
            aot_options.pass_overrides.unroll_factor = v;
        } else if (std.mem.startsWith(u8, arg, "--aot-max-iterations=")) {
            const v = std.fmt.parseInt(u32, arg["--aot-max-iterations=".len..], 10) catch {
                std.debug.print("Error: Invalid --aot-max-iterations\n", .{});
                return;
            };
            aot_options.pass_overrides.max_iterations = v;
        } else if (std.mem.startsWith(u8, arg, "--lowering-policy=")) {
            const policy_str = arg["--lowering-policy=".len..];
            if (aot.LoweringPolicy.fromString(policy_str)) |policy| {
                aot_options.lowering_policy = policy;
            } else {
                std.debug.print("Error: Invalid lowering policy '{s}'\n", .{policy_str});
                std.debug.print("Valid policies: warn, error\n", .{});
                return;
            }
        } else if (std.mem.startsWith(u8, arg, "--mode=")) {
            const mode_str = arg[7..];
            if (parseExecutionMode(mode_str)) |mode| {
                execution_mode = mode;
            } else {
                std.debug.print("Error: Unknown execution mode '{s}'\n", .{mode_str});
                std.debug.print("Valid modes: tree, bytecode, fast, auto\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--jit")) {
            enable_jit = true;
        } else if (std.mem.startsWith(u8, arg, "--syntax=")) {
            const syntax_str = arg[9..];
            if (SyntaxMode.fromString(syntax_str)) |mode| {
                cli_syntax_mode = mode;
            } else {
                std.debug.print("Error: Unknown syntax mode '{s}'\n", .{syntax_str});
                std.debug.print("Valid syntax modes: php (default), go\n", .{});
                return;
            }
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            cli_config_file = arg[9..];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown option '{s}'\n", .{arg});
            printUsage();
            return;
        } else {
            // Assume it's a PHP file
            php_file = arg;
        }
    }

    // Load configuration from file
    // Requirements: 12.1, 12.2, 12.3, 12.4
    var loader = ConfigLoader.init(allocator);
    var file_config = if (cli_config_file) |config_path|
        loader.load(config_path) catch |err| {
            std.debug.print("Error loading config file '{s}': {s}\n", .{ config_path, @errorName(err) });
            return;
        }
    else
        loader.loadDefault() catch |err| {
            std.debug.print("Error loading default config: {s}\n", .{@errorName(err)});
            return;
        };
    defer file_config.deinit(allocator);

    // Apply configuration precedence: CLI overrides config file (Requirements: 12.4)
    // Convert config SyntaxMode to compiler SyntaxMode
    const config_syntax_mode: SyntaxMode = switch (file_config.syntax_mode) {
        .php => .php,
        .go => .go,
    };
    const syntax_mode: SyntaxMode = cli_syntax_mode orelse config_syntax_mode;

    // Print info if Go mode is enabled
    if (syntax_mode == .go) {
        std.debug.print("Info: Go-style syntax mode enabled (a.b instead of $a->b)\n", .{});
    }

    // Handle AOT compilation mode
    if (compile_mode) {
        if (php_file) |filename| {
            aot_options.input_file = filename;
            if (aot_zig_flags.items.len > 0) {
                aot_options.extra_zig_flags = try aot_zig_flags.toOwnedSlice();
            }
            // Convert compiler SyntaxMode to AOT SyntaxMode
            aot_options.syntax_mode = switch (syntax_mode) {
                .php => .php,
                .go => .go,
            };
            try runAOTCompilation(allocator, aot_options);
        } else {
            std.debug.print("Error: No input file specified for compilation.\n", .{});
            printUsage();
        }
        return;
    }

    // Regular interpreter mode
    const php_code: [:0]const u8 = if (php_file) |filename| blk: {
        // Read PHP file from command line argument
        const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
            std.debug.print("Error opening file '{s}': {s}\n", .{ filename, @errorName(err) });
            return;
        };
        defer file.close();

        const file_size = file.getEndPos() catch |err| {
            std.debug.print("Error getting file size: {s}\n", .{@errorName(err)});
            return;
        };
        const contents = arena_allocator.allocSentinel(u8, file_size, 0) catch |err| {
            std.debug.print("Error allocating memory: {s}\n", .{@errorName(err)});
            return;
        };

        _ = file.readAll(contents) catch |err| {
            std.debug.print("Error reading file: {s}\n", .{@errorName(err)});
            return;
        };
        break :blk contents;
    } else "<?php echo 42;";

    // Detect syntax directive in the source code
    const syntax_mode_module = compiler.syntax_mode;
    const directive_result = syntax_mode_module.detectSyntaxDirective(php_code);
    const effective_syntax_mode: SyntaxMode = if (directive_result.found and directive_result.mode != null)
        directive_result.mode.?
    else
        syntax_mode;

    // Check for syntax mixing if a directive was found
    if (directive_result.found and directive_result.mode != null) {
        const detected_mode = directive_result.mode.?;
        // If file declares Go mode, check for PHP syntax mixing
        if (detected_mode == .go) {
            if (std.mem.indexOf(u8, php_code, "$") != null) {
                std.debug.print("Error: File declares Go mode (// @syntax: go) but contains PHP-style variables ($var). Syntax mixing is not allowed.\n", .{});
                return;
            }
        }
        // If file declares PHP mode, check for Go syntax mixing (optional, can be relaxed)
        if (detected_mode == .php) {
            // Check for Go-style property access (obj.prop) without ->
            // This is a heuristic check, not comprehensive
            var j: usize = 0;
            while (j < php_code.len - 1) : (j += 1) {
                if (php_code[j] == '.' and php_code[j + 1] >= 'a' and php_code[j + 1] <= 'z') {
                    // Found potential Go-style property access
                    // Check if it's not part of a number (e.g., 3.14)
                    if (j == 0 or !(php_code[j - 1] >= '0' and php_code[j - 1] <= '9')) {
                        std.debug.print("Warning: File declares PHP mode but may contain Go-style property access (obj.prop). Consider using -> instead.\n", .{});
                        break;
                    }
                }
            }
        }
    }

    var p = try parser.Parser.initWithMode(arena_allocator, &context, php_code, effective_syntax_mode);
    defer p.deinit();
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
    if (enable_jit) {
        try vm_instance.setJitEnabled(true);
    }
    if (php_file) |filename| {
        vm_instance.current_file = filename;
        vm_instance.current_source = php_code; // Set source code for line number calculation
    }
    defer vm_instance.deinit();

    const result = vm_instance.run(program) catch |err| {
        if (err == error.Return) {
            const ret = vm_instance.return_value orelse Value.initNull();
            vm_instance.return_value = null;
            const result = ret.release(allocator);
            // Clean up global variables to prevent memory leak warnings
            vm_instance.cleanupGlobalVariables();
            return result;
        }
        // If it's a runtime exception (handled within VM but returned as error here), we just exit
        // If it's a Zig error, we print it
        std.debug.print("Runtime error: {s}\n", .{@errorName(err)});
        // Clean up global variables to prevent memory leak warnings
        vm_instance.cleanupGlobalVariables();
        return;
    };

    // Release the final result to prevent memory leak
    result.release(allocator);

    // Clean up global variables to prevent memory leak warnings
    vm_instance.cleanupGlobalVariables();

    // Force garbage collection to clean up any remaining objects
    // This helps prevent memory leak warnings in test scenarios
    _ = vm_instance.memory_manager.gc.collect();

    // Clean up AOT runtime library resources to prevent memory leaks
    aot_runtime.deinitRuntime();
}

/// Run AOT compilation
fn runAOTCompilation(allocator: std.mem.Allocator, options: aot.CompileOptions) !void {
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
        std.debug.print("  Syntax mode: {s}\n", .{options.syntax_mode.toString()});
    }

    // 读取源文件
    const file = std.fs.cwd().openFile(options.input_file, .{}) catch |err| {
        std.debug.print("Error: Cannot open file '{s}': {s}\n", .{ options.input_file, @errorName(err) });
        return;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const source = try allocator.allocSentinel(u8, file_size, 0);
    defer allocator.free(source);

    _ = try file.readAll(source);

    // 创建 PHP 上下文和 Parser
    var context = PHPContext.init(allocator);
    defer context.deinit();

    const syntax_mode = switch (options.syntax_mode) {
        .php => SyntaxMode.php,
        .go => SyntaxMode.go,
    };

    var p = try parser.Parser.initWithMode(allocator, &context, source, syntax_mode);
    defer p.deinit();

    // 解析源码
    const root_index = p.parse() catch |err| {
        std.debug.print("Error: Parsing failed: {s}\n", .{@errorName(err)});
        if (context.errors.items.len > 0) {
            for (context.errors.items) |error_item| {
                std.debug.print("Parse error: {s}\n", .{error_item.msg});
            }
        }
        return;
    };

    if (options.verbose) {
        std.debug.print("  Parsing completed: root node index = {d}\n", .{root_index});
        std.debug.print("  Total nodes: {d}\n", .{context.nodes.items.len});
    }

    // 构建字符串表
    const string_table = try buildStringTable(allocator, &context.string_pool);
    defer {
        for (string_table) |s| {
            allocator.free(s);
        }
        allocator.free(string_table);
    }

    if (options.verbose) {
        std.debug.print("  String table: {d} entries\n", .{string_table.len});
    }

    // 创建 AOT 编译器实例
    var aot_compiler = try aot.AOTCompiler.init(allocator, options);
    defer aot_compiler.deinit();

    // 设置源码（用于报错定位）
    try aot_compiler.setSource(source);

    // 设置预解析的 AST
    try aot_compiler.setAST(context.nodes.items, string_table, root_index);

    // 执行完整的编译流程（IR生成、优化、代码生成、链接）
    const result = aot_compiler.compile() catch |err| {
        std.debug.print("Error: Compilation failed: {s}\n", .{@errorName(err)});
        if (aot_compiler.hasErrors()) {
            aot_compiler.printDiagnostics();
        }
        return;
    };

    // 检查编译结果
    if (result.success) {
        if (result.output_path) |output| {
            defer allocator.free(output);
            if (options.link_executable) {
                std.debug.print("Success: Compiled to {s}\n", .{output});
            } else {
                std.debug.print("Success: Generated Zig code to {s}\n", .{output});
            }
            if (options.verbose) {
                std.debug.print("  Errors: {d}\n", .{result.error_count});
                std.debug.print("  Warnings: {d}\n", .{result.warning_count});
            }
        } else {
            std.debug.print("Success: Compilation completed (no output file)\n", .{});
        }
    } else {
        std.debug.print("Error: Compilation failed with {d} errors, {d} warnings\n", .{
            result.error_count,
            result.warning_count,
        });
        aot_compiler.printDiagnostics();
        return error.CompilationFailed;
    }
}






/// Build string table from parser's string pool
fn buildStringTable(allocator: std.mem.Allocator, string_pool: *std.StringArrayHashMapUnmanaged(void)) ![][]const u8 {
    const count = string_pool.count();
    if (count == 0) {
        return try allocator.alloc([]const u8, 0);
    }

    const table = try allocator.alloc([]const u8, count);
    var i: usize = 0;
    var iter = string_pool.iterator();
    while (iter.next()) |entry| {
        table[i] = try allocator.dupe(u8, entry.key_ptr.*);
        i += 1;
    }
    return table;
}
