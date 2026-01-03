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
const SyntaxMode = @import("compiler/syntax_mode.zig").SyntaxMode;
const SyntaxConfig = @import("compiler/syntax_mode.zig").SyntaxConfig;
const config_loader = @import("config/loader.zig");
const ConfigLoader = config_loader.ConfigLoader;

/// 打印使用帮助
fn printUsage() void {
    std.debug.print(
        \\Usage: zig-php [options] <file.php>
        \\       zig-php --compile [compile-options] <file.php>
        \\
        \\Interpreter Options:
        \\  --mode=<mode>      Execution mode: tree, bytecode, auto (default: tree)
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
        \\  --dump-zig             Dump generated Zig code for debugging
        \\  --verbose              Verbose output during compilation
        \\  --list-targets         List all supported target platforms
        \\
        \\Execution Modes:
        \\  tree      Tree-walking interpreter (most compatible, default)
        \\  bytecode  Bytecode virtual machine (higher performance)
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

    // Track CLI overrides (null means not specified on CLI)
    var cli_syntax_mode: ?SyntaxMode = null;
    var cli_config_file: ?[]const u8 = null;
    var execution_mode: ExecutionMode = .tree_walking;
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
        } else if (std.mem.eql(u8, arg, "--dump-zig")) {
            aot_options.dump_zig = true;
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
            std.debug.print("Error loading default config: {s}\n", .{@errorName(err) });
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

    var p = try parser.Parser.initWithMode(arena_allocator, &context, php_code, syntax_mode);
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
    if (php_file) |filename| {
        vm_instance.current_file = filename;
    }
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
    // Read source file
    const file = std.fs.cwd().openFile(options.input_file, .{}) catch |err| {
        std.debug.print("Error: cannot open file '{s}': {s}\n", .{ options.input_file, @errorName(err) });
        return;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const source = try allocator.allocSentinel(u8, file_size, 0);
    defer allocator.free(source);
    _ = try file.readAll(source);

    // Parse the source
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var context = PHPContext.init(arena.allocator());

    // Convert AOT SyntaxMode to compiler SyntaxMode for parser
    const parser_syntax_mode: SyntaxMode = switch (options.syntax_mode) {
        .php => .php,
        .go => .go,
    };

    var p = try parser.Parser.initWithMode(arena.allocator(), &context, source, parser_syntax_mode);
    const program = p.parse() catch |err| {
        std.debug.print("Parse error: {s}\n", .{@errorName(err)});
        // Add parser errors
        for (context.errors.items) |error_item| {
            std.debug.print("  {s}:{d}:{d}: {s}\n", .{
                options.input_file,
                error_item.line,
                error_item.column,
                error_item.msg,
            });
        }
        return;
    };

    // Convert parser AST to IR generator format
    const ir_nodes = try convertASTToIRNodes(allocator, context.nodes.items);
    defer allocator.free(ir_nodes);

    // Build string table from string pool
    const string_table = try buildStringTable(allocator, &context.string_pool);
    defer {
        for (string_table) |s| {
            allocator.free(s);
        }
        allocator.free(string_table);
    }

    // Use the AOTCompiler for the full compilation pipeline
    var compiler = try aot.AOTCompiler.init(allocator, options);
    defer compiler.deinit();

    // Set the pre-parsed AST (with root node index for proper IR generation)
    try compiler.setASTWithRoot(ir_nodes, string_table, program);

    // Set source for diagnostics
    try compiler.getDiagnostics().setSource(source);

    // Run the full compilation pipeline
    const result = try compiler.compile();

    // Report compilation result
    if (result.success) {
        if (result.output_path) |output_path| {
            defer allocator.free(output_path);
            std.debug.print("Compilation successful: {s}\n", .{output_path});
        }
    } else {
        // Free output_path if it was allocated but compilation failed
        if (result.output_path) |output_path| {
            allocator.free(output_path);
        }
        // Print any diagnostics
        if (compiler.hasErrors()) {
            compiler.printDiagnostics();
        }
        std.debug.print("Compilation failed with {d} error(s) and {d} warning(s).\n", .{
            result.error_count,
            result.warning_count,
        });
    }
}

/// Convert parser AST nodes to IR generator node format
fn convertASTToIRNodes(allocator: std.mem.Allocator, parser_nodes: []const ast.Node) ![]const aot.IRGeneratorMod.Node {
    const ir_nodes = try allocator.alloc(aot.IRGeneratorMod.Node, parser_nodes.len);

    for (parser_nodes, 0..) |pnode, i| {
        ir_nodes[i] = .{
            .tag = convertNodeTag(pnode.tag),
            .main_token = convertToken(pnode.main_token),
            .data = convertNodeData(pnode.data, pnode.tag),
        };
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
        .if_stmt => .if_stmt,
        .while_stmt => .while_stmt,
        .for_stmt => .for_stmt,
        .for_range_stmt => .for_range_stmt,
        .foreach_stmt => .foreach_stmt,
        .match_expr => .match_expr,
        .match_arm => .match_arm,
        .try_stmt => .try_stmt,
        .catch_clause => .catch_clause,
        .finally_clause => .finally_clause,
        .throw_stmt => .throw_stmt,
        .method_call => .method_call,
        .property_access => .property_access,
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
        .compound_assignment => .assignment, // Map to assignment for IR generation
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
        .magic_constant => .literal_string, // Map magic constants to string literals for IR
        .array_init => .array_init,
        .array_pair => .array_pair,
        .named_arg => .array_pair, // Map named_arg to array_pair for IR (key-value pair)
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
        .cast_expr => .unary_expr, // Map cast expressions to unary expressions for IR
    };
}

/// Convert parser token to IR generator token
fn convertToken(token: @import("compiler/token.zig").Token) aot.IRGeneratorMod.Token {
    return .{
        .tag = convertTokenTag(token.tag),
        .start = @intCast(token.loc.start),
        .end = @intCast(token.loc.end),
        .line = 0, // Line info not directly available in parser token
        .column = 0,
    };
}

/// Convert parser token tag to IR generator token tag
fn convertTokenTag(tag: @import("compiler/token.zig").Token.Tag) aot.IRGeneratorMod.TokenTag {
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
        .echo_stmt => .{ .echo_stmt = .{ .exprs = data.echo_stmt.exprs } },
        .return_stmt => .{ .return_stmt = .{ .expr = data.return_stmt.expr } },
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
        .function_call => .{ .function_call = .{
            .name = data.function_call.name,
            .args = data.function_call.args,
        } },
        .array_init => .{ .array_init = .{ .elements = data.array_init.elements } },
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
        .named_type => .{ .named_type = .{ .name = data.named_type.name } },
        .array_pair => .{ .array_pair = .{ .key = data.array_pair.key, .value = data.array_pair.value } },
        .expression_stmt => .{ .none = {} }, // Expression statements wrap expressions
        .break_stmt, .continue_stmt => .{ .none = {} }, // Control flow statements
        .postfix_expr => .{ .postfix_expr = .{
            .op = convertTokenTag(data.postfix_expr.op),
            .expr = data.postfix_expr.expr,
        } },
        .ternary_expr => .{ .ternary_expr = .{
            .cond = data.ternary_expr.cond,
            .then_expr = data.ternary_expr.then_expr,
            .else_expr = data.ternary_expr.else_expr,
        } },
        .array_access => .{ .array_access = .{ .target = data.array_access.target, .index = data.array_access.index } },
        .object_instantiation => .{ .object_instantiation = .{
            .class_name = data.object_instantiation.class_name,
            .args = data.object_instantiation.args,
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
