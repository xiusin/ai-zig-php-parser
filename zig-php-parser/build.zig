const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "php-interpreter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.linkLibC();

    b.installArtifact(exe);

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
    const test_runner = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "main", .module = b.createModule(.{ .root_source_file = b.path("src/main.zig") }) },
            },
        }),
    });
    test_runner.linkLibC();

    const run_tests = b.addRunArtifact(test_runner);
    test_step.dependOn(&run_tests.step);

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
