const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Add test step
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
}
