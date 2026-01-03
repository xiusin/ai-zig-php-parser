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

    // =========================================================================
    // AOT Runtime Library - Static Library for AOT compiled programs
    // =========================================================================
    const runtime_lib_step = b.step("build-runtime", "Build AOT runtime library as static library");

    // Build runtime library for the target platform
    const runtime_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "php-runtime",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/aot/runtime_lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    runtime_lib.linkLibC();

    // Install the static library
    const install_runtime = b.addInstallArtifact(runtime_lib, .{});
    runtime_lib_step.dependOn(&install_runtime.step);

    // Also add a step to build runtime for common cross-compilation targets
    const cross_runtime_step = b.step("build-runtime-all", "Build AOT runtime library for all supported targets");

    // Define supported targets for cross-compilation
    const cross_targets = [_]std.Target.Query{
        // Linux x86_64
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        // Linux ARM64
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
        // macOS x86_64
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        // macOS ARM64
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        // Windows x86_64
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc },
    };

    for (cross_targets) |cross_target| {
        const resolved_target = b.resolveTargetQuery(cross_target);
        const target_name = getTargetName(cross_target);

        const cross_runtime = b.addLibrary(.{
            .linkage = .static,
            .name = b.fmt("php-runtime-{s}", .{target_name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/aot/runtime_lib.zig"),
                .target = resolved_target,
                .optimize = optimize,
            }),
        });
        cross_runtime.linkLibC();

        const install_cross = b.addInstallArtifact(cross_runtime, .{});
        cross_runtime_step.dependOn(&install_cross.step);
    }

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
    
    // List of all test files
    const test_files = [_][]const u8{
        "src/test_enhanced_types.zig",
        "src/test_gc.zig",
        "src/test_enhanced_functions.zig",
        "src/test_enhanced_parser.zig",
        "src/test_error_handling.zig",
        "src/test_object_integration.zig",
        "src/test_object_system.zig",
        "src/test_reflection.zig",
        "src/test_attribute_system.zig",
        "src/test_bytecode_vm.zig",
        "src/test_gc_stress.zig",
        "src/test_bytecode_syntax_mode.zig",
        "src/aot/root.zig",
        "src/aot/diagnostics.zig",
        "src/aot/ir_generator.zig",
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


/// Helper function to get a human-readable target name
fn getTargetName(query: std.Target.Query) []const u8 {
    const arch = switch (query.cpu_arch orelse .x86_64) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .arm => "arm",
        .riscv64 => "riscv64",
        else => "unknown",
    };

    const os = switch (query.os_tag orelse .linux) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        .freebsd => "freebsd",
        else => "unknown",
    };

    // Return a static string based on the combination
    if (std.mem.eql(u8, arch, "x86_64") and std.mem.eql(u8, os, "linux")) return "x86_64-linux";
    if (std.mem.eql(u8, arch, "aarch64") and std.mem.eql(u8, os, "linux")) return "aarch64-linux";
    if (std.mem.eql(u8, arch, "x86_64") and std.mem.eql(u8, os, "macos")) return "x86_64-macos";
    if (std.mem.eql(u8, arch, "aarch64") and std.mem.eql(u8, os, "macos")) return "aarch64-macos";
    if (std.mem.eql(u8, arch, "x86_64") and std.mem.eql(u8, os, "windows")) return "x86_64-windows";
    return "unknown";
}
