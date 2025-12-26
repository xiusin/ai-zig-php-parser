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
    
    // Add test for enhanced types
    const enhanced_types_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_enhanced_types.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    enhanced_types_test.linkLibC();
    
    // Add test for garbage collection
    const gc_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_gc.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gc_test.linkLibC();
    
    const run_enhanced_types_test = b.addRunArtifact(enhanced_types_test);
    const run_gc_test = b.addRunArtifact(gc_test);
    
    test_step.dependOn(&run_enhanced_types_test.step);
    test_step.dependOn(&run_gc_test.step);
}
