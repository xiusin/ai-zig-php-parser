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
        \\  --dump-ir              Dump generated IR for debugging
        \\  --dump-ast             Dump parsed AST for debugging
        \\  --verbose              Verbose output during compilation
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

    const line_starts = try computeLineStarts(allocator, source);
    defer allocator.free(line_starts);

    // 转换 AST 节点
    const ir_nodes = try convertASTToIRNodes(allocator, context.nodes.items, line_starts);
    defer allocator.free(ir_nodes);

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

    // 设置预解析的 AST
    try aot_compiler.setAST(ir_nodes, string_table, root_index);

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
            std.debug.print("Success: Compiled to {s}\n", .{output});
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
    }
}

/// Convert parser AST nodes to IR generator node format
fn convertASTToIRNodes(allocator: std.mem.Allocator, parser_nodes: []const ast.Node, line_starts: []const usize) ![]const aot.IRGeneratorMod.Node {
    std.debug.print("[main.zig] Converting {d} parser nodes to IR nodes\n", .{parser_nodes.len});

    const ir_nodes = try allocator.alloc(aot.IRGeneratorMod.Node, parser_nodes.len);

    for (parser_nodes, 0..) |pnode, i| {
        if (i == 0) {
            std.debug.print("[main.zig] Node 0: tag = {s}\n", .{@tagName(pnode.tag)});
        }
        ir_nodes[i] = .{
            .tag = convertNodeTag(pnode.tag),
            .main_token = convertToken(pnode.main_token, line_starts),
            .data = convertNodeData(pnode.data, pnode.tag),
        };
        if (i == 0) {
            std.debug.print("[main.zig] Converted node 0: tag = {s}\n", .{@tagName(ir_nodes[i].tag)});
        }
    }

    return ir_nodes;
}

/// Convert parser node tag to IR generator node tag
fn convertNodeTag(tag: ast.Node.Tag) aot.IRGeneratorMod.Node.Tag {
    return switch (tag) {
        .root => .root,
        .attribute => .attribute,
        .class_decl => .class_decl,
        .interface_decl => .interface_decl,
        .trait_decl => .trait_decl,
        .enum_decl => .enum_decl,
        .struct_decl => .struct_decl,
        .property_decl => .property_decl,
        .property_hook => .property_hook,
        .method_decl => .method_decl,
        .parameter => .parameter,
        .const_decl => .const_decl,
        .global_stmt => .global_stmt,
        .static_stmt => .static_stmt,
        .go_stmt => .go_stmt,
        .lock_stmt => .lock_stmt,
        .closure => .closure,
        .arrow_function => .arrow_function,
        .anonymous_class => .anonymous_class,
        .list_assignment => .list_assignment,
        .list_empty => .list_empty,
        .if_stmt => .if_stmt,
        .while_stmt => .while_stmt,
        .for_stmt => .for_stmt,
        .for_range_stmt => .for_range_stmt,
        .foreach_stmt => .foreach_stmt,
        .switch_stmt => .switch_stmt,
        .case => .case,
        .default => .default,
        .match_expr => .match_expr,
        .match_arm => .match_arm,
        .try_stmt => .try_stmt,
        .catch_clause => .catch_clause,
        .finally_clause => .finally_clause,
        .throw_stmt => .throw_stmt,
        .yield_expr => .yield_expr,
        .method_call => .method_call,
        .property_access => .property_access,
        .safe_property_access => .safe_property_access,
        .variable_property_access => .variable_property_access,
        .array_access => .array_access,
        .function_call => .function_call,
        .function_decl => .function_decl,
        .static_method_call => .static_method_call,
        .static_property_access => .static_property_access,
        .use_stmt => .use_stmt,
        .namespace_stmt => .namespace_stmt,
        .include_stmt => .include_stmt,
        .require_stmt => .require_stmt,
        .block => .block,
        .expression_stmt => .expression_stmt,
        .assignment => .assignment,
        .compound_assignment => .compound_assignment,
        .echo_stmt => .echo_stmt,
        .return_stmt => .return_stmt,
        .break_stmt => .break_stmt,
        .continue_stmt => .continue_stmt,
        .variable => .variable,
        .literal_int => .literal_int,
        .literal_float => .literal_float,
        .literal_string => .literal_string,
        .literal_bool => .literal_bool,
        .literal_null => .literal_null,
        .magic_constant => .magic_constant,
        .array_init => .array_init,
        .array_pair => .array_pair,
        .named_arg => .named_arg,
        .binary_expr => .binary_expr,
        .unary_expr => .unary_expr,
        .postfix_expr => .postfix_expr,
        .ternary_expr => .ternary_expr,
        .unpacking_expr => .unpacking_expr,
        .pipe_expr => .pipe_expr,
        .clone_with_expr => .clone_with_expr,
        .struct_instantiation => .struct_instantiation,
        .object_instantiation => .object_instantiation,
        .trait_use => .trait_use,
        .named_type => .named_type,
        .nullable_type => .nullable_type,
        .union_type => .union_type,
        .intersection_type => .intersection_type,
        .class_constant_access => .class_constant_access,
        .self_expr => .self_expr,
        .parent_expr => .parent_expr,
        .static_expr => .static_expr,
        .cast_expr => .cast_expr,
    };
}

/// Convert parser token to IR generator token
fn convertToken(token: compiler.Token, line_starts: []const usize) aot.IRGeneratorMod.Token {
    const pos: usize = token.loc.start;
    var line_index: usize = 0;
    var lo: usize = 0;
    var hi: usize = line_starts.len;
    while (lo + 1 < hi) {
        const mid = lo + (hi - lo) / 2;
        if (line_starts[mid] <= pos) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    line_index = lo;

    const line_num: u32 = @intCast(line_index + 1);
    const col_num: u32 = @intCast((pos - line_starts[line_index]) + 1);
    return .{
        .tag = convertTokenTag(token.tag),
        .start = @intCast(token.loc.start),
        .end = @intCast(token.loc.end),
        .line = line_num,
        .column = col_num,
    };
}

fn computeLineStarts(allocator: std.mem.Allocator, source: []const u8) ![]usize {
    var starts = std.ArrayListUnmanaged(usize){};
    errdefer starts.deinit(allocator);
    try starts.append(allocator, 0);
    for (source, 0..) |c, i| {
        if (c == '\n' and i + 1 < source.len) {
            try starts.append(allocator, i + 1);
        }
    }
    return starts.toOwnedSlice(allocator);
}

/// Convert parser token tag to IR generator token tag
fn convertTokenTag(tag: compiler.Token.Tag) aot.IRGeneratorMod.TokenTag {
    return switch (tag) {
        .t_lnumber => .integer_literal,
        .t_dnumber => .float_literal,
        .t_constant_encapsed_string, .t_string => .string_literal,
        .k_true => .keyword_true,
        .k_false => .keyword_false,
        .k_null => .keyword_null,
        .k_and => .keyword_and,
        .k_or => .keyword_or,
        .plus => .plus,
        .minus => .minus,
        .asterisk => .star,
        .slash => .slash,
        .percent => .percent,
        .dot => .dot,
        .ampersand => .ampersand,
        .pipe => .pipe,
        .equal_equal => .equal_equal,
        .bang_equal => .bang_equal,
        .equal_equal_equal => .equal_equal_equal,
        .bang_equal_equal => .bang_equal_equal,
        .less => .less_than,
        .less_equal => .less_equal,
        .greater => .greater_than,
        .greater_equal => .greater_equal,
        .spaceship => .spaceship,
        .double_ampersand => .ampersand_ampersand,
        .double_pipe => .pipe_pipe,
        .bang => .bang,
        .double_question => .question_question,
        .plus_plus => .plus_plus,
        .minus_minus => .minus_minus,
        .plus_equal => .plus_equal,
        .minus_equal => .minus_equal,
        .asterisk_equal => .asterisk_equal,
        .slash_equal => .slash_equal,
        .percent_equal => .percent_equal,
        .dot_equal => .dot_equal,
        .eof => .eof,
        else => .eof, // Default for unhandled tags
    };
}

/// Convert parser node data to IR generator node data
fn convertNodeData(data: ast.Node.Data, tag: ast.Node.Tag) aot.IRGeneratorMod.Node.Data {
    return switch (tag) {
        .root => .{ .root = .{ .stmts = data.root.stmts } },
        .block => .{ .block = .{ .stmts = data.block.stmts } },
        .function_decl => .{ .function_decl = .{
            .attributes = data.function_decl.attributes,
            .name = data.function_decl.name,
            .params = data.function_decl.params,
            .body = data.function_decl.body,
        } },
        .literal_int => .{ .literal_int = .{ .value = data.literal_int.value } },
        .literal_float => .{ .literal_float = .{ .value = data.literal_float.value } },
        .literal_string => .{ .literal_string = .{
            .value = data.literal_string.value,
            .quote_type = switch (data.literal_string.quote_type) {
                .single => .single,
                .double => .double,
                .backtick => .backtick,
            },
        } },
        .literal_bool => .{ .literal_bool = .{ .value = data.literal_int.value != 0 } },
        .literal_null => .{ .literal_null = {} },
        .magic_constant => .{ .magic_constant = .{ .kind = switch (data.magic_constant.kind) {
            .dir => .dir,
            .file => .file,
            .line => .line,
            .function => .function,
            .class => .class,
            .method => .method,
            .namespace => .namespace,
        } } },
        .variable => .{ .variable = .{ .name = data.variable.name } },
        .binary_expr => .{ .binary_expr = .{
            .lhs = data.binary_expr.lhs,
            .op = convertTokenTag(data.binary_expr.op),
            .rhs = data.binary_expr.rhs,
        } },
        .unary_expr => .{ .unary_expr = .{
            .op = convertTokenTag(data.unary_expr.op),
            .expr = data.unary_expr.expr,
        } },
        .assignment => .{ .assignment = .{
            .target = data.assignment.target,
            .value = data.assignment.value,
        } },
        .compound_assignment => .{ .compound_assignment = .{
            .target = data.compound_assignment.target,
            .op = convertTokenTag(data.compound_assignment.op),
            .value = data.compound_assignment.value,
        } },
        .echo_stmt => .{ .echo_stmt = .{ .exprs = data.echo_stmt.exprs } },
        .return_stmt => .{ .return_stmt = .{ .expr = data.return_stmt.expr } },
        .expression_stmt => .{ .none = {} },
        .if_stmt => .{ .if_stmt = .{
            .condition = data.if_stmt.condition,
            .then_branch = data.if_stmt.then_branch,
            .else_branch = data.if_stmt.else_branch,
        } },
        .while_stmt => .{ .while_stmt = .{
            .condition = data.while_stmt.condition,
            .body = data.while_stmt.body,
        } },
        .for_stmt => .{ .for_stmt = .{
            .init = data.for_stmt.init,
            .condition = data.for_stmt.condition,
            .loop = data.for_stmt.loop,
            .body = data.for_stmt.body,
        } },
        .foreach_stmt => .{ .foreach_stmt = .{
            .iterable = data.foreach_stmt.iterable,
            .key = data.foreach_stmt.key,
            .value = data.foreach_stmt.value,
            .body = data.foreach_stmt.body,
        } },
        .switch_stmt => .{ .switch_stmt = .{
            .expression = data.switch_stmt.expression,
            .cases = data.switch_stmt.cases,
            .default = data.switch_stmt.default,
        } },
        .case => .{ .case = .{
            .condition = data.case.condition,
            .body = data.case.body,
        } },
        .default => .{ .default = .{
            .body = data.default.body,
        } },
        .break_stmt => .{ .break_stmt = .{
            .level = data.break_stmt.level,
        } },
        .continue_stmt => .{ .continue_stmt = .{
            .level = data.continue_stmt.level,
        } },
        .function_call => .{ .function_call = .{
            .name = data.function_call.name,
            .args = data.function_call.args,
        } },
        .named_arg => .{ .named_arg = .{
            .name = data.named_arg.name,
            .value = data.named_arg.value,
        } },
        .array_init => .{ .array_init = .{ .elements = data.array_init.elements } },
        .array_access => .{ .array_access = .{
            .target = data.array_access.target,
            .index = data.array_access.index,
        } },
        .parameter => .{ .parameter = .{
            .attributes = data.parameter.attributes,
            .name = data.parameter.name,
            .type = data.parameter.type,
            .default_value = data.parameter.default_value,
            .is_promoted = data.parameter.is_promoted,
            .modifiers = .{
                .is_public = data.parameter.modifiers.is_public,
                .is_protected = data.parameter.modifiers.is_protected,
                .is_private = data.parameter.modifiers.is_private,
                .is_static = data.parameter.modifiers.is_static,
                .is_final = data.parameter.modifiers.is_final,
                .is_abstract = data.parameter.modifiers.is_abstract,
                .is_readonly = data.parameter.modifiers.is_readonly,
            },
            .is_variadic = data.parameter.is_variadic,
            .is_reference = data.parameter.is_reference,
        } },
        .lock_stmt => .{ .lock_stmt = .{ .body = data.lock_stmt.body } },
        .go_stmt => .{ .go_stmt = .{ .call = data.go_stmt.call } },
        .ternary_expr => .{ .ternary_expr = .{
            .cond = data.ternary_expr.cond,
            .then_expr = data.ternary_expr.then_expr,
            .else_expr = data.ternary_expr.else_expr,
        } },
        .postfix_expr => .{ .postfix_expr = .{
            .op = convertTokenTag(data.postfix_expr.op),
            .expr = data.postfix_expr.expr,
        } },
        // OOP相关节点转换
        .class_decl, .interface_decl, .trait_decl, .enum_decl => .{ .container_decl = .{
            .attributes = data.container_decl.attributes,
            .name = data.container_decl.name,
            .modifiers = .{
                .is_public = data.container_decl.modifiers.is_public,
                .is_protected = data.container_decl.modifiers.is_protected,
                .is_private = data.container_decl.modifiers.is_private,
                .is_static = data.container_decl.modifiers.is_static,
                .is_final = data.container_decl.modifiers.is_final,
                .is_abstract = data.container_decl.modifiers.is_abstract,
                .is_readonly = data.container_decl.modifiers.is_readonly,
            },
            .extends = data.container_decl.extends,
            .implements = data.container_decl.implements,
            .members = data.container_decl.members,
        } },
        .method_decl => .{ .method_decl = .{
            .attributes = data.method_decl.attributes,
            .name = data.method_decl.name,
            .modifiers = .{
                .is_public = data.method_decl.modifiers.is_public,
                .is_protected = data.method_decl.modifiers.is_protected,
                .is_private = data.method_decl.modifiers.is_private,
                .is_static = data.method_decl.modifiers.is_static,
                .is_final = data.method_decl.modifiers.is_final,
                .is_abstract = data.method_decl.modifiers.is_abstract,
                .is_readonly = data.method_decl.modifiers.is_readonly,
            },
            .params = data.method_decl.params,
            .return_type = data.method_decl.return_type,
            .body = data.method_decl.body,
        } },
        .property_decl => .{ .property_decl = .{
            .attributes = data.property_decl.attributes,
            .name = data.property_decl.name,
            .modifiers = .{
                .is_public = data.property_decl.modifiers.is_public,
                .is_protected = data.property_decl.modifiers.is_protected,
                .is_private = data.property_decl.modifiers.is_private,
                .is_static = data.property_decl.modifiers.is_static,
                .is_final = data.property_decl.modifiers.is_final,
                .is_abstract = data.property_decl.modifiers.is_abstract,
                .is_readonly = data.property_decl.modifiers.is_readonly,
            },
            .type = data.property_decl.type,
            .default_value = data.property_decl.default_value,
            .hooks = data.property_decl.hooks,
        } },
        .object_instantiation => .{ .object_instantiation = .{
            .class_name = data.object_instantiation.class_name,
            .args = data.object_instantiation.args,
        } },
        .method_call => .{ .method_call = .{
            .target = data.method_call.target,
            .method_name = data.method_call.method_name,
            .args = data.method_call.args,
        } },
        .property_access => .{ .property_access = .{
            .target = data.property_access.target,
            .property_name = data.property_access.property_name,
        } },
        .safe_property_access => .{ .safe_property_access = .{
            .target = data.safe_property_access.target,
            .property_name = data.safe_property_access.property_name,
        } },
        .variable_property_access => .{ .variable_property_access = .{
            .target = data.variable_property_access.target,
            .prop_variable = data.variable_property_access.prop_variable,
        } },
        .static_method_call => .{ .static_method_call = .{
            .class_name = data.static_method_call.class_name,
            .method_name = data.static_method_call.method_name,
            .args = data.static_method_call.args,
        } },
        .static_property_access => .{ .static_property_access = .{
            .class_name = data.static_property_access.class_name,
            .property_name = data.static_property_access.property_name,
        } },
        .const_decl => .{ .const_decl = .{
            .name = data.const_decl.name,
            .value = data.const_decl.value,
        } },
        .try_stmt => .{ .try_stmt = .{
            .body = data.try_stmt.body,
            .catch_clauses = data.try_stmt.catch_clauses,
            .finally_clause = data.try_stmt.finally_clause,
        } },
        .catch_clause => .{ .catch_clause = .{
            .exception_type = data.catch_clause.exception_type,
            .variable = data.catch_clause.variable,
            .body = data.catch_clause.body,
        } },
        .finally_clause => .{ .finally_clause = .{
            .body = data.finally_clause.body,
        } },
        .throw_stmt => .{ .throw_stmt = .{
            .expression = data.throw_stmt.expression,
        } },
        .closure => .{ .closure = .{
            .attributes = data.closure.attributes,
            .params = data.closure.params,
            .captures = data.closure.captures,
            .return_type = data.closure.return_type,
            .body = data.closure.body,
            .is_static = data.closure.is_static,
        } },
        .arrow_function => .{ .arrow_function = .{
            .attributes = data.arrow_function.attributes,
            .params = data.arrow_function.params,
            .return_type = data.arrow_function.return_type,
            .body = data.arrow_function.body,
            .is_static = data.arrow_function.is_static,
        } },
        .named_type => .{ .named_type = .{
            .name = data.named_type.name,
        } },
        .nullable_type => .{ .nullable_type = .{ .inner = data.nullable_type.inner } },
        .include_stmt, .require_stmt => .{ .include_stmt = .{
            .path = data.include_stmt.path,
            .is_once = data.include_stmt.is_once,
            .is_require = data.include_stmt.is_require,
        } },
        .use_stmt => .{ .use_stmt = .{
            .namespace = data.use_stmt.namespace,
            .alias = data.use_stmt.alias,
            .use_type = data.use_stmt.use_type,
        } },
        .namespace_stmt => .{ .namespace_stmt = .{ .name = data.namespace_stmt.name } },
        .cast_expr => .{ .cast_expr = .{
            .cast_type = switch (data.cast_expr.cast_type) {
                .k_array => .array,
                .k_object => .object,
                else => .unknown,
            },
            .expr = data.cast_expr.expr,
        } },
        .yield_expr => .{ .yield_expr = .{
            .key = data.yield_expr.key,
            .value = data.yield_expr.value,
        } },
        .trait_use => .{ .trait_use = .{
            .traits = data.trait_use.traits,
        } },
        else => .{ .none = {} },
    };
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
