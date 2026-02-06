const std = @import("std");

// Configuration
const TEST_DIR = "test/aot_diff";
const INTERPRETER_BIN = "zig-out/bin/php-interpreter";
const SKIP_LIST = "test/aot_diff/.skip";
const XFAIL_LIST = "test/aot_diff/.xfail";

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

    const timeout_interp_ms = getenvU64(allocator, "AOT_DIFF_TIMEOUT_INTERP_MS") orelse 5_000;
    const timeout_compile_ms = getenvU64(allocator, "AOT_DIFF_TIMEOUT_COMPILE_MS") orelse 120_000;
    const timeout_run_ms = getenvU64(allocator, "AOT_DIFF_TIMEOUT_RUN_MS") orelse 10_000;

    var skip = try loadListFile(allocator, SKIP_LIST);
    defer freeListMap(allocator, &skip);
    var xfail = try loadListFile(allocator, XFAIL_LIST);
    defer freeListMap(allocator, &xfail);

    // Walk directory
    var dir = try std.fs.cwd().openDir(TEST_DIR, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var total_tests: usize = 0;
    var passed_tests: usize = 0;
    var failed_tests: usize = 0;
    var skipped_tests: usize = 0;
    var xfailed_tests: usize = 0;
    var xpassed_tests: usize = 0;

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".php")) continue;

        total_tests += 1;
        const relative_path = try std.fs.path.join(allocator, &.{TEST_DIR, entry.path});
        defer allocator.free(relative_path);
        
        std.debug.print("[TEST] {s} ... ", .{entry.path});

        if (skip.contains(entry.path)) {
            std.debug.print("SKIP\n", .{});
            skipped_tests += 1;
            continue;
        }

        const is_xfail = xfail.get(entry.path) != null;

        // 1. Run Interpreter
        const interp_args = &[_][]const u8{ interpreter_path, "--mode=tree", relative_path };
        const interp_result = try runCommand(allocator, interp_args, timeout_interp_ms);
        defer {
            allocator.free(interp_result.stdout);
            allocator.free(interp_result.stderr);
        }

        if (interp_result.exit_code != 0) {
            if (is_xfail) {
                std.debug.print("XFAIL (Interpreter Error)\n", .{});
                xfailed_tests += 1;
            } else {
                std.debug.print("FAIL (Interpreter Error)\n", .{});
                std.debug.print("Stderr: {s}\n", .{interp_result.stderr});
                failed_tests += 1;
            }
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
            "--mode=tree",
            "--compile",
            output_arg,
            relative_path
        };

        const compile_result = try runCommand(allocator, compile_args, timeout_compile_ms);
        defer {
            allocator.free(compile_result.stdout);
            allocator.free(compile_result.stderr);
        }

        if (compile_result.exit_code != 0) {
            if (is_xfail) {
                std.debug.print("XFAIL (Compilation Error)\n", .{});
                xfailed_tests += 1;
            } else {
                std.debug.print("FAIL (Compilation Error)\n", .{});
                std.debug.print("Stderr: {s}\n", .{compile_result.stderr});
                failed_tests += 1;
            }
            continue;
        }

        // 3. Run AOT Binary
        const aot_args = &[_][]const u8{temp_bin_path};
        const aot_result = try runCommand(allocator, aot_args, timeout_run_ms);
        defer {
            allocator.free(aot_result.stdout);
            allocator.free(aot_result.stderr);
            // Cleanup binary
            std.fs.deleteFileAbsolute(temp_bin_path) catch {};
        }

        if (aot_result.exit_code != 0) {
            if (is_xfail) {
                std.debug.print("XFAIL (Runtime Error)\n", .{});
                xfailed_tests += 1;
            } else {
                std.debug.print("FAIL (Runtime Error)\n", .{});
                std.debug.print("Stderr: {s}\n", .{aot_result.stderr});
                failed_tests += 1;
            }
            continue;
        }

        // 4. Compare Output
        if (!std.mem.eql(u8, interp_result.stdout, aot_result.stdout)) {
            if (is_xfail) {
                std.debug.print("XFAIL (Output Mismatch)\n", .{});
                xfailed_tests += 1;
            } else {
                std.debug.print("FAIL (Output Mismatch)\n", .{});
                std.debug.print("--- Interpreter Output ---\n{s}\n", .{interp_result.stdout});
                std.debug.print("--- AOT Output ---\n{s}\n", .{aot_result.stdout});
                failed_tests += 1;
            }
        } else {
            if (is_xfail) {
                std.debug.print("XPASS\n", .{});
                xpassed_tests += 1;
            } else {
                std.debug.print("PASS\n", .{});
                passed_tests += 1;
            }
        }
    }

    std.debug.print("\nSummary: {d} Tests, {d} Passed, {d} Failed, {d} Skipped, {d} XFailed, {d} XPassed\n", .{total_tests, passed_tests, failed_tests, skipped_tests, xfailed_tests, xpassed_tests});
    
    if (failed_tests > 0 or xpassed_tests > 0) {
        std.process.exit(1);
    }
}

const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8, timeout_ms: u64) !CommandResult {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    var done = std.atomic.Value(bool).init(false);
    var killed = std.atomic.Value(bool).init(false);
    const killer = try std.Thread.spawn(.{}, killAfterTimeout, .{ &child, &done, &killed, timeout_ms });

    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    child.collectOutput(allocator, &stdout_buf, &stderr_buf, 16 * 1024 * 1024) catch |err| switch (err) {
        error.StdoutStreamTooLong, error.StderrStreamTooLong => {},
        else => return err,
    };

    const stdout = try stdout_buf.toOwnedSlice(allocator);
    errdefer allocator.free(stdout);
    var stderr = try stderr_buf.toOwnedSlice(allocator);
    errdefer allocator.free(stderr);

    const term = child.wait() catch std.process.Child.Term{ .Signal = 15 };
    done.store(true, .release);
    killer.join();

    if (killed.load(.acquire)) {
        const suffix = "\n[AOT-DIFF] timeout\n";
        const combined = allocator.alloc(u8, stderr.len + suffix.len) catch return CommandResult{
            .stdout = stdout,
            .stderr = stderr,
            .exit_code = 124,
        };
        @memcpy(combined[0..stderr.len], stderr);
        @memcpy(combined[stderr.len..], suffix);
        allocator.free(stderr);
        stderr = combined;
    }

    const exit_code: u8 = if (killed.load(.acquire)) 124 else switch (term) {
        .Exited => |code| code,
        else => 255,
    };

    return CommandResult{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = exit_code,
    };
}

fn killAfterTimeout(child: *std.process.Child, done: *std.atomic.Value(bool), killed: *std.atomic.Value(bool), timeout_ms: u64) void {
    var remaining = timeout_ms;
    while (remaining > 0) {
        const slice_ms: u64 = if (remaining > 50) 50 else remaining;
        std.Thread.sleep(slice_ms * std.time.ns_per_ms);
        if (done.load(.acquire)) return;
        remaining -= slice_ms;
    }
    std.posix.kill(child.id, std.posix.SIG.KILL) catch |err| switch (err) {
        error.ProcessNotFound => return,
        else => return,
    };
    killed.store(true, .release);
}

fn getenvU64(allocator: std.mem.Allocator, name: []const u8) ?u64 {
    const raw = std.process.getEnvVarOwned(allocator, name) catch return null;
    defer allocator.free(raw);
    return std.fmt.parseInt(u64, raw, 10) catch null;
}

fn loadListFile(allocator: std.mem.Allocator, path: []const u8) !std.StringHashMap([]const u8) {
    var map = std.StringHashMap([]const u8).init(allocator);
    const file = std.fs.cwd().openFile(path, .{}) catch return map;
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    var it = std.mem.splitScalar(u8, contents, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        var parts = std.mem.splitScalar(u8, line, '\t');
        const file_name = parts.next() orelse continue;
        const reason = parts.next() orelse "";
        const key = try allocator.dupe(u8, file_name);
        const val = try allocator.dupe(u8, reason);
        try map.put(key, val);
    }
    return map;
}

fn freeListMap(allocator: std.mem.Allocator, map: *std.StringHashMap([]const u8)) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    map.deinit();
}
