const std = @import("std");
const builtin = @import("builtin");

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
    // Detect platform for Homebrew PCRE2 paths
    const pcre2_prefix = if (builtin.target.cpu.arch == .aarch64) "/opt/homebrew/opt/pcre2" else "/usr/local/opt/pcre2";
    exe.addIncludePath(.{ .cwd_relative = pcre2_prefix ++ "/include" });
    exe.addLibraryPath(.{ .cwd_relative = pcre2_prefix ++ "/lib" });
    exe.linkSystemLibrary("pcre2-8");

    b.installArtifact(exe);

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
        // JIT tests
        "src/jit/test_fallback_properties.zig",
        "src/jit/test_fallback_integration.zig",
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
    
    // Bytecode optimizer property tests
    const optimizer_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bytecode/test_optimizer_properties.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    optimizer_test.linkLibC();
    const run_optimizer_test = b.addRunArtifact(optimizer_test);
    test_step.dependOn(&run_optimizer_test.step);
    
    // VM property tests
    const vm_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bytecode/test_vm_properties.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    vm_test.linkLibC();
    const run_vm_test = b.addRunArtifact(vm_test);
    test_step.dependOn(&run_vm_test.step);
    
    // GC property tests
    const gc_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bytecode/test_gc_properties.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gc_test.linkLibC();
    const run_gc_test = b.addRunArtifact(gc_test);
    test_step.dependOn(&run_gc_test.step);

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

    // String benchmark tests
    const string_bench_step = b.step("bench-string", "Run string benchmark tests");
    
    // 创建基准测试模块
    const benchmark_module = b.createModule(.{
        .root_source_file = b.path("src/benchmark/string_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    
    const string_bench_exe = b.addExecutable(.{
        .name = "string-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/benchmarks/run_string_benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    string_bench_exe.root_module.addImport("string_benchmark", benchmark_module);
    string_bench_exe.linkLibC();
    
    const string_bench_cmd = b.addRunArtifact(string_bench_exe);
    string_bench_step.dependOn(&string_bench_cmd.step);

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

    // Array benchmark tests
    const array_bench_step = b.step("bench-array", "Run array benchmark tests");
    
    const array_benchmark_module = b.createModule(.{
        .root_source_file = b.path("src/benchmark/array_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    
    const array_bench_exe = b.addExecutable(.{
        .name = "array-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/benchmarks/run_array_benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    array_bench_exe.root_module.addImport("array_benchmark", array_benchmark_module);
    array_bench_exe.linkLibC();
    
    const array_bench_cmd = b.addRunArtifact(array_bench_exe);
    array_bench_step.dependOn(&array_bench_cmd.step);

    // JIT benchmark tests
    const jit_bench_step = b.step("bench-jit", "Run JIT benchmark tests");
    
    const jit_bench_exe = b.addExecutable(.{
        .name = "jit-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark/jit_benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    jit_bench_exe.linkLibC();
    
    const jit_bench_cmd = b.addRunArtifact(jit_bench_exe);
    jit_bench_step.dependOn(&jit_bench_cmd.step);

    // AOT benchmark tests
    const aot_bench_step = b.step("bench-aot", "Run AOT benchmark tests");
    
    const aot_bench_exe = b.addExecutable(.{
        .name = "aot-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark/aot_benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    aot_bench_exe.linkLibC();
    
    const aot_bench_cmd = b.addRunArtifact(aot_bench_exe);
    aot_bench_step.dependOn(&aot_bench_cmd.step);

    // All benchmarks
    const bench_all_step = b.step("bench-all", "Run all benchmarks");
    bench_all_step.dependOn(string_bench_step);
    bench_all_step.dependOn(array_bench_step);
    bench_all_step.dependOn(jit_bench_step);
    bench_all_step.dependOn(aot_bench_step);

    // Performance regression check
    const perf_check_step = b.step("perf-check", "Check for performance regressions");
    
    const perf_cli_exe = b.addExecutable(.{
        .name = "perf-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark/perf_cli.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    perf_cli_exe.linkLibC();
    
    b.installArtifact(perf_cli_exe);
    
    const perf_check_cmd = b.addRunArtifact(perf_cli_exe);
    perf_check_cmd.addArg("check");
    perf_check_cmd.step.dependOn(bench_all_step);
    perf_check_step.dependOn(&perf_check_cmd.step);

    // Update performance baselines
    const perf_update_step = b.step("perf-update", "Update performance baselines");
    
    const perf_update_cmd = b.addRunArtifact(perf_cli_exe);
    perf_update_cmd.addArg("update");
    perf_update_cmd.step.dependOn(bench_all_step);
    perf_update_step.dependOn(&perf_update_cmd.step);

    // List performance baselines
    const perf_list_step = b.step("perf-list", "List performance baselines");
    
    const perf_list_cmd = b.addRunArtifact(perf_cli_exe);
    perf_list_cmd.addArg("list");
    perf_list_step.dependOn(&perf_list_cmd.step);

    // Regression detector tests
    const regression_test_step = b.step("test-regression", "Test regression detector");
    
    const regression_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark/regression_detector.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const run_regression_test = b.addRunArtifact(regression_test);
    regression_test_step.dependOn(&run_regression_test.step);
    test_step.dependOn(&run_regression_test.step);

    // CI integration tests
    const ci_test_step = b.step("test-ci", "Test CI integration");
    
    const ci_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark/ci_integration.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const run_ci_test = b.addRunArtifact(ci_test);
    ci_test_step.dependOn(&run_ci_test.step);
    test_step.dependOn(&run_ci_test.step);

    // Clean step
    const clean_step = b.step("clean", "Clean build artifacts");
    const clean_cmd = b.addSystemCommand(&[_][]const u8{ "rm", "-rf", "zig-out", ".zig-cache" });
    clean_step.dependOn(&clean_cmd.step);
}
