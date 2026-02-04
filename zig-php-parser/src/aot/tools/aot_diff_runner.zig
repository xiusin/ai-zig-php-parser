const std = @import("std");

// Configuration
const TEST_DIR = "test/aot_diff";
const INTERPRETER_BIN = "zig-out/bin/php-interpreter";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Ensure interpreter exists
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    
    const interpreter_path = try std.fs.path.join(allocator, &.{cwd, INTERPRETER_BIN});
    defer allocator.free(interpreter_path);
    
    std.fs.cwd().access(interpreter_path, .{}) catch {
        std.debug.print("Error: Interpreter not found at {s}\n", .{interpreter_path});
        std.debug.print("Please run 'zig build' first.\n", .{});
        std.process.exit(1);
    };

    std.debug.print("Running AOT Differential Tests...\n", .{});
    std.debug.print("Test Directory: {s}\n", .{TEST_DIR});
    std.debug.print("Interpreter: {s}\n", .{interpreter_path});

    // Walk directory
    var dir = try std.fs.cwd().openDir(TEST_DIR, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var total_tests: usize = 0;
    var passed_tests: usize = 0;
    var failed_tests: usize = 0;

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".php")) continue;

        total_tests += 1;
        const relative_path = try std.fs.path.join(allocator, &.{TEST_DIR, entry.path});
        defer allocator.free(relative_path);
        
        std.debug.print("[TEST] {s} ... ", .{entry.path});

        // 1. Run Interpreter
        const interp_args = &[_][]const u8{interpreter_path, relative_path};
        const interp_result = try runCommand(allocator, interp_args);
        defer {
            allocator.free(interp_result.stdout);
            allocator.free(interp_result.stderr);
        }

        if (interp_result.exit_code != 0) {
            std.debug.print("FAIL (Interpreter Error)\n", .{});
            std.debug.print("Stderr: {s}\n", .{interp_result.stderr});
            failed_tests += 1;
            continue;
        }

        // 2. Compile AOT
        // Generate temp output path
        const timestamp = std.time.milliTimestamp();
        const temp_bin_name = try std.fmt.allocPrint(allocator, "temp_aot_{d}_{d}", .{timestamp, total_tests});
        defer allocator.free(temp_bin_name);
        
        const temp_bin_path = try std.fs.path.join(allocator, &.{cwd, temp_bin_name});
        defer allocator.free(temp_bin_path);
        
        const output_arg = try std.fmt.allocPrint(allocator, "--output={s}", .{temp_bin_path});
        defer allocator.free(output_arg);

        const compile_args = &[_][]const u8{
            interpreter_path,
            "--compile",
            output_arg,
            relative_path
        };

        const compile_result = try runCommand(allocator, compile_args);
        defer {
            allocator.free(compile_result.stdout);
            allocator.free(compile_result.stderr);
        }

        if (compile_result.exit_code != 0) {
            std.debug.print("FAIL (Compilation Error)\n", .{});
            std.debug.print("Stderr: {s}\n", .{compile_result.stderr});
            failed_tests += 1;
            continue;
        }

        // 3. Run AOT Binary
        const aot_args = &[_][]const u8{temp_bin_path};
        const aot_result = try runCommand(allocator, aot_args);
        defer {
            allocator.free(aot_result.stdout);
            allocator.free(aot_result.stderr);
            // Cleanup binary
            std.fs.deleteFileAbsolute(temp_bin_path) catch {};
        }

        if (aot_result.exit_code != 0) {
            std.debug.print("FAIL (Runtime Error)\n", .{});
            std.debug.print("Stderr: {s}\n", .{aot_result.stderr});
            failed_tests += 1;
            continue;
        }

        // 4. Compare Output
        if (!std.mem.eql(u8, interp_result.stdout, aot_result.stdout)) {
             std.debug.print("FAIL (Output Mismatch)\n", .{});
             std.debug.print("--- Interpreter Output ---\n{s}\n", .{interp_result.stdout});
             std.debug.print("--- AOT Output ---\n{s}\n", .{aot_result.stdout});
             failed_tests += 1;
        } else {
            std.debug.print("PASS\n", .{});
            passed_tests += 1;
        }
    }

    std.debug.print("\nSummary: {d} Tests, {d} Passed, {d} Failed\n", .{total_tests, passed_tests, failed_tests});
    
    if (failed_tests > 0) {
        std.process.exit(1);
    }
}

const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !CommandResult {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    
    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    
    const term = try child.wait();
    
    const exit_code: u8 = switch (term) {
        .Exited => |code| code,
        else => 255,
    };

    return CommandResult{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = exit_code,
    };
}
