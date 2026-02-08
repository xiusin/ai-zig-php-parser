const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Use ReleaseSafe for main exe to work around Zig 0.15.2 LLVM Debug mode bug
    // The bug causes "Instruction does not dominate all uses" LLVM error in Debug mode
    const exe_optimize: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSafe else optimize;

    // ========== 定义共享模块 ==========
    // 这些模块用于解决 Zig 0.15.2 不推荐使用 `../` 跨目录导入的问题
    
    // 编译器模块
    const compiler_mod = b.createModule(.{
        .root_source_file = b.path("src/compiler/mod.zig"),
    });
    
    // 运行时模块
    const runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime/mod.zig"),
    });

    const nanbox_abi_mod = b.createModule(.{
        .root_source_file = b.path("src/shared/nanbox_abi.zig"),
    });
    
    // 模块相互依赖
    runtime_mod.addImport("compiler", compiler_mod);
    runtime_mod.addImport("nanbox_abi", nanbox_abi_mod);
    compiler_mod.addImport("runtime", runtime_mod);
    
    // 字节码模块
    const bytecode_mod = b.createModule(.{
        .root_source_file = b.path("src/bytecode/mod.zig"),
    });
    
    // bytecode 需要访问 runtime 和 compiler
    bytecode_mod.addImport("runtime", runtime_mod);
    bytecode_mod.addImport("compiler", compiler_mod);
    
    // JIT 模块
    const jit_mod = b.createModule(.{
        .root_source_file = b.path("src/jit/mod.zig"),
    });
    
    // jit 需要访问 runtime 和 compiler
    jit_mod.addImport("runtime", runtime_mod);
    jit_mod.addImport("compiler", compiler_mod);
    
    // 扩展模块
    const extension_mod = b.createModule(.{
        .root_source_file = b.path("src/extension/mod.zig"),
    });
    
    // runtime 需要访问其他模块
    runtime_mod.addImport("bytecode", bytecode_mod);
    runtime_mod.addImport("jit", jit_mod);
    runtime_mod.addImport("extension", extension_mod);
    
    // 添加 extension 模块到 compiler
    compiler_mod.addImport("extension", extension_mod);

    // Main executable
    const exe = b.addExecutable(.{
        .name = "php-interpreter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = exe_optimize,
        }),
    });
    
    // 添加模块导入到主可执行文件
    exe.root_module.addImport("compiler", compiler_mod);
    exe.root_module.addImport("runtime", runtime_mod);
    exe.root_module.addImport("bytecode", bytecode_mod);
    exe.root_module.addImport("jit", jit_mod);
    exe.root_module.addImport("extension", extension_mod);
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
    // 添加模块导入到 AOT 测试
    aot_test.root_module.addImport("compiler", compiler_mod);
    aot_test.root_module.addImport("runtime", runtime_mod);
    aot_test.root_module.addImport("bytecode", bytecode_mod);
    aot_test.root_module.addImport("jit", jit_mod);
    aot_test.root_module.addImport("extension", extension_mod);
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
        // "src/aot/root.zig",
        // "src/aot/diagnostics.zig",
        // "src/aot/ir_generator.zig",
        "src/aot/test_control_flow_ir.zig",
        "src/aot/test_licm.zig",
        "src/aot/test_loop_unroll.zig",
        "src/aot/test_runtime_arrays.zig",
        "src/aot/test_runtime_cycle_gc.zig",
        "src/aot/test_runtime_comprehensive.zig",
        // Runtime tests
        // "src/runtime/coroutine_error_handling.zig",
        // "src/runtime/coroutine_debugging.zig",
        // "src/runtime/test_error_handling_property.zig",
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
        test_exe.addIncludePath(.{ .cwd_relative = pcre2_prefix ++ "/include" });
        test_exe.addLibraryPath(.{ .cwd_relative = pcre2_prefix ++ "/lib" });
        test_exe.linkSystemLibrary("pcre2-8");
        // 添加模块导入
        test_exe.root_module.addImport("compiler", compiler_mod);
        test_exe.root_module.addImport("runtime", runtime_mod);
        test_exe.root_module.addImport("bytecode", bytecode_mod);
        test_exe.root_module.addImport("jit", jit_mod);
        test_exe.root_module.addImport("extension", extension_mod);

        const run_test = b.addRunArtifact(test_exe);
        test_step.dependOn(&run_test.step);
    }
    // PHP compatibility tests
    const compat_test_step = b.step("test-compat", "Run PHP compatibility tests");
    const compat_test_cmd = b.addSystemCommand(&[_][]const u8{ "bash", "run_compatibility_tests.sh" });
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
    // 添加模块导入
    docs_exe.root_module.addImport("compiler", compiler_mod);
    docs_exe.root_module.addImport("runtime", runtime_mod);
    docs_exe.root_module.addImport("bytecode", bytecode_mod);
    docs_exe.root_module.addImport("jit", jit_mod);
    docs_exe.root_module.addImport("extension", extension_mod);

    const docs_cmd = b.addRunArtifact(docs_exe);
    docs_cmd.addArg("--help");
    docs_step.dependOn(&docs_cmd.step);

    // AOT coverage report
    const aot_report_step = b.step("aot-report", "Generate AOT coverage report markdown");
    const aot_report_exe = b.addExecutable(.{
        .name = "aot-coverage-report",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/aot_coverage_report.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_aot_report = b.addRunArtifact(aot_report_exe);
    aot_report_step.dependOn(&run_aot_report.step);

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
    // 添加模块导入
    bench_exe.root_module.addImport("compiler", compiler_mod);
    bench_exe.root_module.addImport("runtime", runtime_mod);
    bench_exe.root_module.addImport("bytecode", bytecode_mod);
    bench_exe.root_module.addImport("jit", jit_mod);
    bench_exe.root_module.addImport("extension", extension_mod);

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
    // 添加模块导入
    string_bench_exe.root_module.addImport("compiler", compiler_mod);
    string_bench_exe.root_module.addImport("runtime", runtime_mod);
    string_bench_exe.root_module.addImport("bytecode", bytecode_mod);
    string_bench_exe.root_module.addImport("jit", jit_mod);
    string_bench_exe.root_module.addImport("extension", extension_mod);
    
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
    // 添加模块导入
    leak_check_exe.root_module.addImport("compiler", compiler_mod);
    leak_check_exe.root_module.addImport("runtime", runtime_mod);
    leak_check_exe.root_module.addImport("bytecode", bytecode_mod);
    leak_check_exe.root_module.addImport("jit", jit_mod);
    leak_check_exe.root_module.addImport("extension", extension_mod);

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
    // 添加模块导入
    array_bench_exe.root_module.addImport("compiler", compiler_mod);
    array_bench_exe.root_module.addImport("runtime", runtime_mod);
    array_bench_exe.root_module.addImport("bytecode", bytecode_mod);
    array_bench_exe.root_module.addImport("jit", jit_mod);
    array_bench_exe.root_module.addImport("extension", extension_mod);
    
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
    // 添加模块导入
    jit_bench_exe.root_module.addImport("compiler", compiler_mod);
    jit_bench_exe.root_module.addImport("runtime", runtime_mod);
    jit_bench_exe.root_module.addImport("bytecode", bytecode_mod);
    jit_bench_exe.root_module.addImport("jit", jit_mod);
    jit_bench_exe.root_module.addImport("extension", extension_mod);
    
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
    // 添加模块导入
    aot_bench_exe.root_module.addImport("compiler", compiler_mod);
    aot_bench_exe.root_module.addImport("runtime", runtime_mod);
    aot_bench_exe.root_module.addImport("bytecode", bytecode_mod);
    aot_bench_exe.root_module.addImport("jit", jit_mod);
    aot_bench_exe.root_module.addImport("extension", extension_mod);
    
    const aot_bench_cmd = b.addRunArtifact(aot_bench_exe);
    aot_bench_step.dependOn(&aot_bench_cmd.step);

    // All benchmarks
    const bench_all_step = b.step("bench-all", "Run all benchmarks");
    bench_all_step.dependOn(string_bench_step);
    bench_all_step.dependOn(array_bench_step);
    bench_all_step.dependOn(jit_bench_step);
    bench_all_step.dependOn(aot_bench_step);

    // Terminator debug test - TEMPORARILY DISABLED
    // const terminator_debug = b.addExecutable(.{
    //     .name = "test_terminator_debug",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("test_terminator_debug.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         .imports = &.{
    //             .{ .name = "Compiler", .module = compiler_mod },
    //             .{ .name = "Runtime", .module = runtime_mod },
    //             .{ .name = "Bytecode", .module = bytecode_mod },
    //             .{ .name = "JIT", .module = jit_mod },
    //             .{ .name = "Extension", .module = extension_mod },
    //             .{ .name = "AOT", .module = b.createModule(.{
    //                 .root_source_file = b.path("src/aot/root.zig"),
    //                 .target = target,
    //                 .optimize = optimize,
    //                 .imports = &.{
    //                     .{ .name = "compiler", .module = compiler_mod },
    //                     .{ .name = "runtime", .module = runtime_mod },
    //                     .{ .name = "bytecode", .module = bytecode_mod },
    //                     .{ .name = "jit", .module = jit_mod },
    //                     .{ .name = "extension", .module = extension_mod },
    //                 },
    //             }) },
    //         },
    //     }),
    // });
    // b.installArtifact(terminator_debug);
    
    // const terminator_debug_step = b.step("test-terminator", "Run terminator debug test");
    // const run_terminator_debug = b.addRunArtifact(terminator_debug);
    // terminator_debug_step.dependOn(&run_terminator_debug.step);

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
    // 添加模块导入
    perf_cli_exe.root_module.addImport("compiler", compiler_mod);
    perf_cli_exe.root_module.addImport("runtime", runtime_mod);
    perf_cli_exe.root_module.addImport("bytecode", bytecode_mod);
    perf_cli_exe.root_module.addImport("jit", jit_mod);
    perf_cli_exe.root_module.addImport("extension", extension_mod);
    perf_cli_exe.root_module.addImport("aot", b.createModule(.{
        .root_source_file = b.path("src/aot/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{
            .{ .name = "compiler", .module = compiler_mod },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "bytecode", .module = bytecode_mod },
            .{ .name = "jit", .module = jit_mod },
            .{ .name = "extension", .module = extension_mod },
        },
    }));
    perf_cli_exe.root_module.addImport("aot_runtime", b.createModule(.{
        .root_source_file = b.path("src/aot/runtime_lib_template.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    }));
    
    b.installArtifact(perf_cli_exe);

    const profile_cli_exe = b.addExecutable(.{
        .name = "profile-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/profile_cli.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    profile_cli_exe.linkLibC();
    profile_cli_exe.root_module.addImport("runtime", runtime_mod);
    b.installArtifact(profile_cli_exe);

    const install_profile_cli = b.addInstallArtifact(profile_cli_exe, .{});
    const profile_cli_step = b.step("profile-cli", "Build profile-cli");
    profile_cli_step.dependOn(&install_profile_cli.step);
    
    const perf_check_cmd = b.addRunArtifact(perf_cli_exe);
    perf_check_cmd.addArg("check");
    if (b.args) |args| {
        perf_check_cmd.addArgs(args);
    }
    perf_check_step.dependOn(&perf_check_cmd.step);

    // Update performance baselines
    const perf_update_step = b.step("perf-update", "Update performance baselines");
    
    const perf_update_cmd = b.addRunArtifact(perf_cli_exe);
    perf_update_cmd.addArg("update");
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

    // AOT Differential Tests
    const aot_diff_step = b.step("test-aot-diff", "Run AOT differential tests (Interpreter vs AOT)");
    
    const aot_diff_exe = b.addExecutable(.{
        .name = "aot-diff-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/aot/tools/aot_diff_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const run_aot_diff = b.addRunArtifact(aot_diff_exe);
    // Ensure the interpreter is built and installed first
    run_aot_diff.step.dependOn(b.getInstallStep());
    aot_diff_step.dependOn(&run_aot_diff.step);

    // Clean step
    const clean_step = b.step("clean", "Clean build artifacts");
    const clean_cmd = b.addSystemCommand(&[_][]const u8{ "rm", "-rf", "zig-out", ".zig-cache" });
    clean_step.dependOn(&clean_cmd.step);
}
