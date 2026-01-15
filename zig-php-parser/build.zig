const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Use ReleaseSafe for main exe to work around Zig 0.15.2 LLVM Debug mode bug
    // The bug causes "Instruction does not dominate all uses" LLVM error in Debug mode
    const exe_optimize: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSafe else optimize;

    // Main executable
    const exe = b.addExecutable(.{
        .name = "php-interpreter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = exe_optimize,
        }),
    });
    exe.linkLibC();
    // Support both Intel (usr/local) and Apple Silicon (opt/homebrew) PCRE2 paths
    exe.addIncludePath(.{ .cwd_relative = "/usr/local/Cellar/pcre2/10.47/include" });
    exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/pcre2/include" });
    exe.linkSystemLibrary("pcre2-8");
    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/Cellar/pcre2/10.47/lib" });
    exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/pcre2/lib" });

    b.installArtifact(exe);

    // LSP Server
    const lsp = b.addExecutable(.{
        .name = "zig-php-lsp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tool/lsp/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Allow LSP to import files from src/ as if it were in the root
    lsp.root_module.addImport("project_root", b.createModule(.{
        .root_source_file = b.path("src/compiler/root.zig"), // Expose compiler root
    }));
    // We also need raw access to files for relative imports if we want to mimic src structure
    // But since Zig modules are strict, let's expose specific submodules or the compiler root.
    // The previous analysis showed compiler/root.zig exposes PHPContext.

    // Let's verify imports in main.zig:
    // const parser = @import("compiler/parser.zig");
    // This implies main.zig relies on file system structure relative to itself.

    // For the LSP, living in tool/lsp/main.zig, to import "compiler/parser.zig",
    // we would need to map "compiler" to "src/compiler".

    lsp.root_module.addImport("compiler", b.createModule(.{
        .root_source_file = b.path("src/compiler/root.zig"),
    }));

    lsp.linkLibC();
    b.installArtifact(lsp);

    // AOT module tests
    const aot_test_step = b.step("test-aot", "Run AOT module tests");
    const aot_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/aot/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_aot_test = b.addRunArtifact(aot_test);
    aot_test_step.dependOn(&run_aot_test.step);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const test_step = b.step("test", "Run unit tests");

    // List of all test files (only existing files)
    const test_files = [_][]const u8{
        // AOT module tests
        "src/aot/root.zig",
        "src/aot/diagnostics.zig",
        "src/aot/ir_generator.zig",
        // Runtime tests
        "src/runtime/coroutine_error_handling.zig",
        "src/runtime/coroutine_debugging.zig",
        "src/runtime/test_error_handling_property.zig",
    };

    // Add all test files
    for (test_files) |test_file| {
        const test_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_exe.linkLibC();

        const run_test = b.addRunArtifact(test_exe);
        test_step.dependOn(&run_test.step);
    }

    // PHP compatibility tests
    const compat_test_step = b.step("test-compat", "Run PHP compatibility tests");
    const compat_test_cmd = b.addSystemCommand(&[_][]const u8{"./run_compatibility_tests.sh"});
    compat_test_cmd.step.dependOn(b.getInstallStep());
    compat_test_step.dependOn(&compat_test_cmd.step);

    // All tests (unit + compatibility)
    const test_all_step = b.step("test-all", "Run all tests (unit + compatibility)");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(compat_test_step);

    // Documentation generation
    const docs_step = b.step("docs", "Generate documentation");
    const docs_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    docs_exe.linkLibC();

    const docs_cmd = b.addRunArtifact(docs_exe);
    docs_cmd.addArg("--help");
    docs_step.dependOn(&docs_cmd.step);

    // Benchmark step
    const bench_step = b.step("bench", "Run performance benchmarks");
    const bench_exe = b.addExecutable(.{
        .name = "php-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_exe.linkLibC();

    const bench_cmd = b.addRunArtifact(bench_exe);
    bench_cmd.addArg("examples/hello.php");
    bench_step.dependOn(&bench_cmd.step);

    // Memory leak check
    const leak_check_step = b.step("leak-check", "Check for memory leaks");
    const leak_check_exe = b.addExecutable(.{
        .name = "php-leak-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    leak_check_exe.linkLibC();

    const leak_check_cmd = b.addRunArtifact(leak_check_exe);
    leak_check_cmd.addArg("examples/hello.php");
    leak_check_step.dependOn(&leak_check_cmd.step);

    // Clean step
    const clean_step = b.step("clean", "Clean build artifacts");
    const clean_cmd = b.addSystemCommand(&[_][]const u8{ "rm", "-rf", "zig-out", ".zig-cache" });
    clean_step.dependOn(&clean_cmd.step);
}
