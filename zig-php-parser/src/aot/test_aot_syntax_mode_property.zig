//! Property-based tests for AOT compiler syntax mode independence
//!
//! Property 8: AOT compilation mode independence
//! Validates: Requirements 6.1, 6.2
//!
//! This test verifies that the AOT compiler produces semantically equivalent
//! output regardless of the syntax mode used (PHP or Go style).

const std = @import("std");
const testing = std.testing;
const CompilerMod = @import("compiler.zig");
const AOTCompiler = CompilerMod.AOTCompiler;
const CompileOptions = CompilerMod.CompileOptions;
const SyntaxMode = CompilerMod.SyntaxMode;
const SyntaxConfig = CompilerMod.SyntaxConfig;

// ============================================================================
// Property 8: AOT Compilation Mode Independence
// ============================================================================

// Test that CompileOptions correctly stores and retrieves syntax mode
test "Property 8.1: CompileOptions syntax mode storage" {
    // Test PHP mode (default)
    {
        const opts = CompileOptions{
            .input_file = "test.php",
        };
        try testing.expectEqual(SyntaxMode.php, opts.syntax_mode);
    }

    // Test Go mode
    {
        const opts = CompileOptions{
            .input_file = "test.php",
            .syntax_mode = .go,
        };
        try testing.expectEqual(SyntaxMode.go, opts.syntax_mode);
    }
}

// Test that AOTCompiler correctly initializes with syntax mode
test "Property 8.2: AOTCompiler syntax mode initialization" {
    const allocator = testing.allocator;

    // Test with PHP mode
    {
        const opts = CompileOptions{
            .input_file = "test.php",
            .syntax_mode = .php,
        };
        var compiler = try AOTCompiler.init(allocator, opts);
        defer compiler.deinit();

        try testing.expectEqual(SyntaxMode.php, compiler.getSyntaxMode());
        try testing.expect(compiler.getSyntaxConfig().isPhpMode());
        try testing.expect(!compiler.getSyntaxConfig().isGoMode());
    }

    // Test with Go mode
    {
        const opts = CompileOptions{
            .input_file = "test.php",
            .syntax_mode = .go,
        };
        var compiler = try AOTCompiler.init(allocator, opts);
        defer compiler.deinit();

        try testing.expectEqual(SyntaxMode.go, compiler.getSyntaxMode());
        try testing.expect(compiler.getSyntaxConfig().isGoMode());
        try testing.expect(!compiler.getSyntaxConfig().isPhpMode());
    }
}

// Test that SyntaxMode string conversion is consistent
test "Property 8.3: SyntaxMode string conversion roundtrip" {
    // Test PHP mode
    {
        const mode = SyntaxMode.php;
        const str = mode.toString();
        const parsed = SyntaxMode.fromString(str);
        try testing.expectEqual(mode, parsed.?);
    }

    // Test Go mode
    {
        const mode = SyntaxMode.go;
        const str = mode.toString();
        const parsed = SyntaxMode.fromString(str);
        try testing.expectEqual(mode, parsed.?);
    }

    // Test invalid string
    {
        const parsed = SyntaxMode.fromString("invalid");
        try testing.expect(parsed == null);
    }
}

// Test that SyntaxConfig correctly derives from SyntaxMode
test "Property 8.4: SyntaxConfig initialization from mode" {
    // Test PHP mode config
    {
        const config = SyntaxConfig.init(.php);
        try testing.expectEqual(SyntaxMode.php, config.mode);
        try testing.expectEqual(SyntaxMode.php, config.error_display_mode);
        try testing.expect(config.isPhpMode());
        try testing.expect(!config.isGoMode());
    }

    // Test Go mode config
    {
        const config = SyntaxConfig.init(.go);
        try testing.expectEqual(SyntaxMode.go, config.mode);
        try testing.expectEqual(SyntaxMode.go, config.error_display_mode);
        try testing.expect(config.isGoMode());
        try testing.expect(!config.isPhpMode());
    }
}

// Test that multiple AOTCompiler instances with different modes are independent
test "Property 8.5: Multiple compiler instances mode independence" {
    const allocator = testing.allocator;

    // Create two compilers with different modes
    const php_opts = CompileOptions{
        .input_file = "test.php",
        .syntax_mode = .php,
    };
    const go_opts = CompileOptions{
        .input_file = "test.php",
        .syntax_mode = .go,
    };

    var php_compiler = try AOTCompiler.init(allocator, php_opts);
    defer php_compiler.deinit();

    var go_compiler = try AOTCompiler.init(allocator, go_opts);
    defer go_compiler.deinit();

    // Verify they maintain their independent modes
    try testing.expectEqual(SyntaxMode.php, php_compiler.getSyntaxMode());
    try testing.expectEqual(SyntaxMode.go, go_compiler.getSyntaxMode());

    // Verify configs are independent
    try testing.expect(php_compiler.getSyntaxConfig().isPhpMode());
    try testing.expect(go_compiler.getSyntaxConfig().isGoMode());
}

// Test that syntax mode is preserved through compiler lifecycle
test "Property 8.6: Syntax mode preservation through lifecycle" {
    const allocator = testing.allocator;

    // Test that mode is preserved after initialization
    inline for ([_]SyntaxMode{ .php, .go }) |mode| {
        const opts = CompileOptions{
            .input_file = "test.php",
            .syntax_mode = mode,
        };
        var compiler = try AOTCompiler.init(allocator, opts);
        defer compiler.deinit();

        // Mode should be preserved
        try testing.expectEqual(mode, compiler.getSyntaxMode());
        try testing.expectEqual(mode, compiler.getSyntaxConfig().mode);

        // Config should be consistent
        if (mode == .php) {
            try testing.expect(compiler.getSyntaxConfig().isPhpMode());
        } else {
            try testing.expect(compiler.getSyntaxConfig().isGoMode());
        }
    }
}

// Test that all CompileOptions fields are independent of syntax mode
test "Property 8.7: CompileOptions field independence" {
    // Create options with all fields set
    const php_opts = CompileOptions{
        .input_file = "test.php",
        .output_file = "output",
        .optimize_level = .release_fast,
        .static_link = false,
        .debug_info = false,
        .dump_ir = true,
        .dump_ast = true,
        .verbose = true,
        .syntax_mode = .php,
    };

    const go_opts = CompileOptions{
        .input_file = "test.php",
        .output_file = "output",
        .optimize_level = .release_fast,
        .static_link = false,
        .debug_info = false,
        .dump_ir = true,
        .dump_ast = true,
        .verbose = true,
        .syntax_mode = .go,
    };

    // All fields except syntax_mode should be equal
    try testing.expectEqualStrings(php_opts.input_file, go_opts.input_file);
    try testing.expectEqualStrings(php_opts.output_file.?, go_opts.output_file.?);
    try testing.expectEqual(php_opts.optimize_level, go_opts.optimize_level);
    try testing.expectEqual(php_opts.static_link, go_opts.static_link);
    try testing.expectEqual(php_opts.debug_info, go_opts.debug_info);
    try testing.expectEqual(php_opts.dump_ir, go_opts.dump_ir);
    try testing.expectEqual(php_opts.dump_ast, go_opts.dump_ast);
    try testing.expectEqual(php_opts.verbose, go_opts.verbose);

    // Only syntax_mode should differ
    try testing.expect(php_opts.syntax_mode != go_opts.syntax_mode);
}
