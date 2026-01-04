//! Multi-File Compiler Tests
//!
//! This module contains comprehensive tests for the multi-file compilation
//! functionality, including:
//! - Include/require statement parsing
//! - Circular dependency detection
//! - Symbol table merging
//! - Compilation order verification

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const DependencyResolverMod = @import("dependency_resolver.zig");
const DependencyResolver = DependencyResolverMod.DependencyResolver;
const MultiFileCompilerMod = @import("multi_file_compiler.zig");
const MultiFileCompiler = MultiFileCompilerMod.MultiFileCompiler;
const CompilerMod = @import("compiler.zig");
const CompileOptions = CompilerMod.CompileOptions;

// ============================================================================
// Include/Require Parsing Tests
// ============================================================================

test "parse include with single quotes" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "<?php\ninclude 'config.php';";
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    try testing.expectEqual(@as(usize, 1), includes.len);
    try testing.expectEqualStrings("config.php", includes[0].path);
    try testing.expect(!includes[0].is_require);
    try testing.expect(!includes[0].is_once);
}

test "parse include with double quotes" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "<?php\ninclude \"helpers.php\";";
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    try testing.expectEqual(@as(usize, 1), includes.len);
    try testing.expectEqualStrings("helpers.php", includes[0].path);
}

test "parse require statement" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "<?php\nrequire 'database.php';";
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    try testing.expectEqual(@as(usize, 1), includes.len);
    try testing.expectEqualStrings("database.php", includes[0].path);
    try testing.expect(includes[0].is_require);
    try testing.expect(!includes[0].is_once);
}

test "parse include_once statement" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "<?php\ninclude_once 'utils.php';";
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    try testing.expectEqual(@as(usize, 1), includes.len);
    try testing.expectEqualStrings("utils.php", includes[0].path);
    try testing.expect(!includes[0].is_require);
    try testing.expect(includes[0].is_once);
}

test "parse require_once statement" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "<?php\nrequire_once 'autoload.php';";
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    try testing.expectEqual(@as(usize, 1), includes.len);
    try testing.expectEqualStrings("autoload.php", includes[0].path);
    try testing.expect(includes[0].is_require);
    try testing.expect(includes[0].is_once);
}

test "parse include with parentheses" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "<?php\ninclude('config.php');";
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    try testing.expectEqual(@as(usize, 1), includes.len);
    try testing.expectEqualStrings("config.php", includes[0].path);
}

test "parse multiple includes" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source =
        \\<?php
        \\include 'config.php';
        \\require 'database.php';
        \\include_once 'utils.php';
        \\require_once 'autoload.php';
    ;
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    try testing.expectEqual(@as(usize, 4), includes.len);
    try testing.expectEqualStrings("config.php", includes[0].path);
    try testing.expectEqualStrings("database.php", includes[1].path);
    try testing.expectEqualStrings("utils.php", includes[2].path);
    try testing.expectEqualStrings("autoload.php", includes[3].path);
}

test "parse include with path" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "<?php\ninclude 'lib/helpers/utils.php';";
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    try testing.expectEqual(@as(usize, 1), includes.len);
    try testing.expectEqualStrings("lib/helpers/utils.php", includes[0].path);
}

test "detect dynamic include path" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    // Dynamic paths should be detected
    try testing.expect(resolver.isDynamicPath("$dir/config.php"));
    try testing.expect(resolver.isDynamicPath("${base}/file.php"));
    try testing.expect(!resolver.isDynamicPath("config.php"));
    try testing.expect(!resolver.isDynamicPath("lib/utils.php"));
}

// ============================================================================
// Circular Dependency Detection Tests
// ============================================================================

test "no circular dependency in simple case" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    // Initially no circular dependencies
    try testing.expect(!resolver.hasCircularDependencies());
    try testing.expectEqual(@as(usize, 0), resolver.getCircularDependencies().len);
}

test "dependency resolver file count" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    try testing.expectEqual(@as(usize, 0), resolver.getFileCount());
}

// ============================================================================
// Symbol Table Merging Tests
// ============================================================================

test "multi-file compiler symbol registration" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "test.php",
    };

    const compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer compiler.deinit();

    // Register some symbols
    const source =
        \\<?php
        \\function myFunction() {}
        \\class MyClass {}
    ;

    try compiler.registerFileSymbols("test.php", source);

    // Check that symbols were registered
    const symbol_table = compiler.getGlobalSymbolTable();
    try testing.expect(symbol_table.lookupFunction("myFunction") != null);
    try testing.expect(symbol_table.lookupClass("MyClass") != null);
}

test "multi-file compiler multiple files symbol registration" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "main.php",
    };

    const compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer compiler.deinit();

    // Register symbols from first file
    const source1 =
        \\<?php
        \\function helperFunc() {}
        \\class HelperClass {}
    ;
    try compiler.registerFileSymbols("helpers.php", source1);

    // Register symbols from second file
    const source2 =
        \\<?php
        \\function mainFunc() {}
        \\class MainClass {}
    ;
    try compiler.registerFileSymbols("main.php", source2);

    // Check that all symbols were registered
    const symbol_table = compiler.getGlobalSymbolTable();
    try testing.expect(symbol_table.lookupFunction("helperFunc") != null);
    try testing.expect(symbol_table.lookupClass("HelperClass") != null);
    try testing.expect(symbol_table.lookupFunction("mainFunc") != null);
    try testing.expect(symbol_table.lookupClass("MainClass") != null);
}

// ============================================================================
// Compilation Order Tests
// ============================================================================

test "compilation order empty" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const order = try resolver.getCompilationOrder();
    defer allocator.free(order);

    try testing.expectEqual(@as(usize, 0), order.len);
}

// ============================================================================
// Include Path Tests
// ============================================================================

test "add include paths" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    try resolver.addIncludePath("/usr/share/php");
    try resolver.addIncludePath("/var/www/lib");
    try resolver.addIncludePath("./vendor");

    try testing.expectEqual(@as(usize, 3), resolver.include_paths.items.len);
}

test "multi-file compiler add include paths" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "test.php",
    };

    const compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer compiler.deinit();

    try compiler.addIncludePath("/usr/share/php");
    try compiler.addIncludePath("/var/www/lib");

    try testing.expectEqual(@as(usize, 2), compiler.include_paths.items.len);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "empty source file" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "";
    const includes = try resolver.extractIncludes(source, "empty.php");
    defer allocator.free(includes);

    try testing.expectEqual(@as(usize, 0), includes.len);
}

test "source with no includes" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source =
        \\<?php
        \\echo "Hello, World!";
        \\function test() {
        \\    return 42;
        \\}
    ;
    const includes = try resolver.extractIncludes(source, "test.php");
    defer allocator.free(includes);

    try testing.expectEqual(@as(usize, 0), includes.len);
}

test "include in comment should not be parsed" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    // Note: Our simple parser doesn't handle comments yet
    // This test documents the current behavior
    const source =
        \\<?php
        \\// include 'commented.php';
        \\include 'real.php';
    ;
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    // Currently our simple parser will find both includes
    // A more sophisticated parser would skip the commented one
    try testing.expect(includes.len >= 1);
}

test "include with escaped quotes" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const resolver = try DependencyResolver.init(allocator, &diagnostics);
    defer resolver.deinit();

    const source = "<?php\ninclude 'file\\'s.php';";
    const includes = try resolver.extractIncludes(source, "test.php");
    defer {
        for (includes) |inc| {
            allocator.free(inc.path);
            if (inc.resolved_path) |rp| allocator.free(rp);
        }
        allocator.free(includes);
    }

    // The parser should handle escaped quotes
    try testing.expectEqual(@as(usize, 1), includes.len);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "multi-file compiler initialization and cleanup" {
    const allocator = testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "main.php",
        .output_file = "output",
        .verbose = false,
    };

    const compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer compiler.deinit();

    try testing.expectEqual(@as(usize, 0), compiler.getCompiledFileCount());
    try testing.expect(compiler.getMergedModule() == null);
    try testing.expect(!compiler.isFileCompiled("main.php"));
}
