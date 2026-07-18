const std = @import("std");

const DEFAULT_TEST_DIR = "test/aot_diff";
const INTERPRETER_BIN = "zig-out/bin/php-interpreter";
const DEFAULT_CACHE_DIR = ".zig-cache/aot_diff_bins";

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded_io = std.Io.Threaded.init(allocator, .{
        .argv0 = .init(.{ .vector = &.{} }),
        .environ = .{ .block = .{ .slice = &.{} } },
    });
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const cwd = std.Io.Dir.cwd();

    // Ensure interpreter exists
    const cwd_path = try cwd.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(cwd_path);

    const interpreter_path = try std.fs.path.join(allocator, &.{ cwd_path, INTERPRETER_BIN });
    defer allocator.free(interpreter_path);

    cwd.access(io, interpreter_path, .{}) catch {
        std.debug.print("Error: Interpreter not found at {s}\n", .{interpreter_path});
        std.debug.print("Please run 'zig build' first.\n", .{});
        std.process.exit(1);
    };

    const test_dir = getenvOwned(allocator, "AOT_DIFF_TEST_DIR") orelse try allocator.dupe(u8, DEFAULT_TEST_DIR);
    defer allocator.free(test_dir);

    const skip_list_path = getenvOwned(allocator, "AOT_DIFF_SKIP_LIST") orelse blk: {
        break :blk try std.fs.path.join(allocator, &.{ test_dir, ".skip" });
    };
    defer allocator.free(skip_list_path);

    const xfail_list_path = getenvOwned(allocator, "AOT_DIFF_XFAIL_LIST") orelse blk: {
        break :blk try std.fs.path.join(allocator, &.{ test_dir, ".xfail" });
    };
    defer allocator.free(xfail_list_path);

    const only_contains = getenvOwned(allocator, "AOT_DIFF_ONLY_CONTAINS");
    defer if (only_contains) |s| allocator.free(s);

    const cache_dir = getenvOwned(allocator, "AOT_DIFF_CACHE_DIR") orelse try allocator.dupe(u8, DEFAULT_CACHE_DIR);
    defer allocator.free(cache_dir);
    const cache_enabled = (getenvU64(allocator, "AOT_DIFF_CACHE") orelse 1) != 0;

    const jobs = @max(@as(usize, 1), @as(usize, @intCast(getenvU64(allocator, "AOT_DIFF_JOBS") orelse std.Thread.getCpuCount() catch 1)));

    std.debug.print("Running AOT Differential Tests...\n", .{});
    std.debug.print("Test Directory: {s}\n", .{test_dir});
    std.debug.print("Interpreter: {s}\n", .{interpreter_path});
    std.debug.print("Jobs: {d}\n", .{jobs});
    std.debug.print("Cache: {s} ({s})\n", .{ cache_dir, if (cache_enabled) "enabled" else "disabled" });

    const timeout_interp_ms = getenvU64(allocator, "AOT_DIFF_TIMEOUT_INTERP_MS") orelse 5_000;
    const timeout_compile_ms = getenvU64(allocator, "AOT_DIFF_TIMEOUT_COMPILE_MS") orelse 120_000;
    const timeout_run_ms = getenvU64(allocator, "AOT_DIFF_TIMEOUT_RUN_MS") orelse 10_000;

    var skip = try loadListFile(allocator, io, cwd, skip_list_path);
    defer freeListMap(allocator, &skip);
    var xfail = try loadListFile(allocator, io, cwd, xfail_list_path);
    defer freeListMap(allocator, &xfail);

    // Walk directory
    var dir = try cwd.openDir(io, test_dir, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var test_paths = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
    defer {
        for (test_paths.items) |p| allocator.free(p);
        test_paths.deinit(allocator);
    }

    var total_tests: usize = 0;
    var passed_tests: usize = 0;
    var failed_tests: usize = 0;
    var skipped_tests: usize = 0;
    var xfailed_tests: usize = 0;
    var xpassed_tests: usize = 0;

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".php")) continue;

        if (only_contains) |needle| {
            if (std.mem.indexOf(u8, entry.path, needle) == null) continue;
        }

        const rel = try allocator.dupe(u8, entry.path);
        try test_paths.append(allocator, rel);
    }

    total_tests = test_paths.items.len;

    if (cache_enabled) {
        cwd.createDirPath(io, cache_dir) catch {};
    }

    var output_mutex: std.Io.Mutex = .init;
    var compile_mutex: std.Io.Mutex = .init;
    var index = std.atomic.Value(usize).init(0);

    const Shared = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        cwd: std.Io.Dir,
        cwd_path: []const u8,
        test_dir: []const u8,
        cache_dir: []const u8,
        cache_enabled: bool,
        interpreter_path: []const u8,
        timeout_interp_ms: u64,
        timeout_compile_ms: u64,
        timeout_run_ms: u64,
        skip: *std.StringHashMap([]const u8),
        xfail: *std.StringHashMap([]const u8),
        test_paths: []const []const u8,
        index: *std.atomic.Value(usize),
        output_mutex: *std.Io.Mutex,
        compile_mutex: *std.Io.Mutex,
        passed: *std.atomic.Value(usize),
        failed: *std.atomic.Value(usize),
        skipped: *std.atomic.Value(usize),
        xfailed: *std.atomic.Value(usize),
        xpassed: *std.atomic.Value(usize),
    };

    var passed_atomic = std.atomic.Value(usize).init(0);
    var failed_atomic = std.atomic.Value(usize).init(0);
    var skipped_atomic = std.atomic.Value(usize).init(0);
    var xfailed_atomic = std.atomic.Value(usize).init(0);
    var xpassed_atomic = std.atomic.Value(usize).init(0);

    const shared = Shared{
        .allocator = allocator,
        .io = io,
        .cwd = cwd,
        .cwd_path = cwd_path,
        .test_dir = test_dir,
        .cache_dir = cache_dir,
        .cache_enabled = cache_enabled,
        .interpreter_path = interpreter_path,
        .timeout_interp_ms = timeout_interp_ms,
        .timeout_compile_ms = timeout_compile_ms,
        .timeout_run_ms = timeout_run_ms,
        .skip = &skip,
        .xfail = &xfail,
        .test_paths = test_paths.items,
        .index = &index,
        .output_mutex = &output_mutex,
        .compile_mutex = &compile_mutex,
        .passed = &passed_atomic,
        .failed = &failed_atomic,
        .skipped = &skipped_atomic,
        .xfailed = &xfailed_atomic,
        .xpassed = &xpassed_atomic,
    };

    const threads = try allocator.alloc(std.Thread, jobs);
    defer allocator.free(threads);
    for (threads, 0..) |*t, tid| {
        _ = tid;
        t.* = try std.Thread.spawn(.{}, workerLoop, .{shared});
    }
    for (threads) |t| t.join();

    passed_tests = passed_atomic.load(.acquire);
    failed_tests = failed_atomic.load(.acquire);
    skipped_tests = skipped_atomic.load(.acquire);
    xfailed_tests = xfailed_atomic.load(.acquire);
    xpassed_tests = xpassed_atomic.load(.acquire);

    std.debug.print("\nSummary: {d} Tests, {d} Passed, {d} Failed, {d} Skipped, {d} XFailed, {d} XPassed\n", .{ total_tests, passed_tests, failed_tests, skipped_tests, xfailed_tests, xpassed_tests });

    if (failed_tests > 0 or xpassed_tests > 0) {
        std.process.exit(1);
    }
}

fn workerLoop(shared: anytype) void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    while (true) {
        const i = shared.index.fetchAdd(1, .acq_rel);
        if (i >= shared.test_paths.len) return;

        _ = arena_state.reset(.retain_capacity);

        const entry_path = shared.test_paths[i];

        shared.output_mutex.lockUncancelable(shared.io);
        std.debug.print("[TEST] {s} ... ", .{entry_path});
        shared.output_mutex.unlock(shared.io);

        if (shared.skip.contains(entry_path)) {
            shared.output_mutex.lockUncancelable(shared.io);
            std.debug.print("SKIP\n", .{});
            shared.output_mutex.unlock(shared.io);
            _ = shared.skipped.fetchAdd(1, .acq_rel);
            continue;
        }

        const is_xfail = shared.xfail.get(entry_path) != null;
        const relative_path = std.fs.path.join(arena, &.{ shared.test_dir, entry_path }) catch {
            shared.output_mutex.lockUncancelable(shared.io);
            std.debug.print("FAIL (Path)\n", .{});
            shared.output_mutex.unlock(shared.io);
            _ = shared.failed.fetchAdd(1, .acq_rel);
            continue;
        };

        const interp_args = &[_][]const u8{ shared.interpreter_path, "--mode=tree", relative_path };
        const interp_result = runCommand(shared.allocator, shared.io, interp_args, shared.timeout_interp_ms) catch {
            shared.output_mutex.lockUncancelable(shared.io);
            std.debug.print("FAIL (Interpreter Spawn)\n", .{});
            shared.output_mutex.unlock(shared.io);
            _ = shared.failed.fetchAdd(1, .acq_rel);
            continue;
        };
        defer {
            shared.allocator.free(interp_result.stdout);
            shared.allocator.free(interp_result.stderr);
        }

        if (interp_result.exit_code != 0) {
            shared.output_mutex.lockUncancelable(shared.io);
            if (is_xfail) {
                std.debug.print("XFAIL (Interpreter Error)\n", .{});
                _ = shared.xfailed.fetchAdd(1, .acq_rel);
            } else {
                std.debug.print("FAIL (Interpreter Error)\n", .{});
                std.debug.print("Stderr: {s}\n", .{interp_result.stderr});
                _ = shared.failed.fetchAdd(1, .acq_rel);
            }
            shared.output_mutex.unlock(shared.io);
            continue;
        }

        const cache_key = hashFileHex(arena, shared.io, shared.cwd, relative_path) catch null;
        var bin_path: []const u8 = undefined;
        var should_cleanup: bool = false;

        if (shared.cache_enabled and cache_key != null) {
            const key = cache_key.?;
            const name = std.fmt.allocPrint(arena, "{s}.bin", .{key}) catch null;
            if (name) |n| {
                bin_path = std.fs.path.join(arena, &.{ shared.cache_dir, n }) catch "";
                if (bin_path.len != 0) {
                    shared.cwd.access(shared.io, bin_path, .{}) catch {
                        const timestamp = std.Io.Timestamp.now(shared.io, .real).toMilliseconds();
                        const temp_name = std.fmt.allocPrint(arena, "tmp_{d}_{d}.bin", .{ timestamp, i }) catch "";
                        const temp_path = std.fs.path.join(arena, &.{ shared.cache_dir, temp_name }) catch "";
                        if (temp_path.len == 0) {
                            shared.output_mutex.lockUncancelable(shared.io);
                            std.debug.print("FAIL (Cache Path)\n", .{});
                            shared.output_mutex.unlock(shared.io);
                            _ = shared.failed.fetchAdd(1, .acq_rel);
                            continue;
                        }

                        const output_arg = std.fmt.allocPrint(arena, "--output={s}", .{temp_path}) catch "";
                        const compile_args = &[_][]const u8{ shared.interpreter_path, "--mode=tree", "--compile", output_arg, relative_path };
                        shared.compile_mutex.lockUncancelable(shared.io);
                        const compile_result = runCommand(shared.allocator, shared.io, compile_args, shared.timeout_compile_ms) catch {
                            shared.compile_mutex.unlock(shared.io);
                            shared.output_mutex.lockUncancelable(shared.io);
                            std.debug.print("FAIL (Compilation Spawn)\n", .{});
                            shared.output_mutex.unlock(shared.io);
                            _ = shared.failed.fetchAdd(1, .acq_rel);
                            continue;
                        };
                        shared.compile_mutex.unlock(shared.io);
                        defer {
                            shared.allocator.free(compile_result.stdout);
                            shared.allocator.free(compile_result.stderr);
                        }

                        if (compile_result.exit_code != 0) {
                            shared.output_mutex.lockUncancelable(shared.io);
                            if (is_xfail) {
                                std.debug.print("XFAIL (Compilation Error)\n", .{});
                                _ = shared.xfailed.fetchAdd(1, .acq_rel);
                            } else {
                                std.debug.print("FAIL (Compilation Error)\n", .{});
                                std.debug.print("Stderr: {s}\n", .{compile_result.stderr});
                                _ = shared.failed.fetchAdd(1, .acq_rel);
                            }
                            shared.output_mutex.unlock(shared.io);
                            shared.cwd.deleteFile(shared.io, temp_path) catch {};
                            continue;
                        }

                        shared.cwd.rename(temp_path, shared.cwd, bin_path, shared.io) catch {
                            shared.cwd.deleteFile(shared.io, temp_path) catch {};
                        };
                    };
                }
            }
            should_cleanup = false;
        } else {
            const timestamp = std.Io.Timestamp.now(shared.io, .real).toMilliseconds();
            const temp_name = std.fmt.allocPrint(arena, "temp_aot_{d}_{d}.bin", .{ timestamp, i }) catch "";
            const temp_path = std.fs.path.join(arena, &.{ shared.cwd_path, temp_name }) catch "";
            if (temp_path.len == 0) {
                shared.output_mutex.lockUncancelable(shared.io);
                std.debug.print("FAIL (Temp Path)\n", .{});
                shared.output_mutex.unlock(shared.io);
                _ = shared.failed.fetchAdd(1, .acq_rel);
                continue;
            }
            bin_path = temp_path;
            should_cleanup = true;

            const output_arg = std.fmt.allocPrint(arena, "--output={s}", .{bin_path}) catch "";
            const compile_args = &[_][]const u8{ shared.interpreter_path, "--mode=tree", "--compile", output_arg, relative_path };
            shared.compile_mutex.lockUncancelable(shared.io);
            const compile_result = runCommand(shared.allocator, shared.io, compile_args, shared.timeout_compile_ms) catch {
                shared.compile_mutex.unlock(shared.io);
                shared.output_mutex.lockUncancelable(shared.io);
                std.debug.print("FAIL (Compilation Spawn)\n", .{});
                shared.output_mutex.unlock(shared.io);
                _ = shared.failed.fetchAdd(1, .acq_rel);
                continue;
            };
            shared.compile_mutex.unlock(shared.io);
            defer {
                shared.allocator.free(compile_result.stdout);
                shared.allocator.free(compile_result.stderr);
            }

            if (compile_result.exit_code != 0) {
                shared.output_mutex.lockUncancelable(shared.io);
                if (is_xfail) {
                    std.debug.print("XFAIL (Compilation Error)\n", .{});
                    _ = shared.xfailed.fetchAdd(1, .acq_rel);
                } else {
                    std.debug.print("FAIL (Compilation Error)\n", .{});
                    std.debug.print("Stderr: {s}\n", .{compile_result.stderr});
                    _ = shared.failed.fetchAdd(1, .acq_rel);
                }
                shared.output_mutex.unlock(shared.io);
                std.Io.Dir.deleteFileAbsolute(shared.io, bin_path) catch {};
                continue;
            }
        }

        const aot_args = &[_][]const u8{bin_path};
        const aot_result = runCommand(shared.allocator, shared.io, aot_args, shared.timeout_run_ms) catch {
            shared.output_mutex.lockUncancelable(shared.io);
            std.debug.print("FAIL (AOT Spawn)\n", .{});
            shared.output_mutex.unlock(shared.io);
            _ = shared.failed.fetchAdd(1, .acq_rel);
            if (should_cleanup) std.Io.Dir.deleteFileAbsolute(shared.io, bin_path) catch {};
            continue;
        };
        defer {
            shared.allocator.free(aot_result.stdout);
            shared.allocator.free(aot_result.stderr);
            if (should_cleanup) std.Io.Dir.deleteFileAbsolute(shared.io, bin_path) catch {};
        }

        if (aot_result.exit_code != 0) {
            shared.output_mutex.lockUncancelable(shared.io);
            if (is_xfail) {
                std.debug.print("XFAIL (Runtime Error)\n", .{});
                _ = shared.xfailed.fetchAdd(1, .acq_rel);
            } else {
                std.debug.print("FAIL (Runtime Error)\n", .{});
                std.debug.print("Stderr: {s}\n", .{aot_result.stderr});
                _ = shared.failed.fetchAdd(1, .acq_rel);
            }
            shared.output_mutex.unlock(shared.io);
            continue;
        }

        const ok = std.mem.eql(u8, interp_result.stdout, aot_result.stdout);
        shared.output_mutex.lockUncancelable(shared.io);
        if (!ok) {
            if (is_xfail) {
                std.debug.print("XFAIL (Output Mismatch)\n", .{});
                _ = shared.xfailed.fetchAdd(1, .acq_rel);
            } else {
                std.debug.print("FAIL (Output Mismatch)\n", .{});
                std.debug.print("--- Interpreter Output ---\n{s}\n", .{interp_result.stdout});
                std.debug.print("--- AOT Output ---\n{s}\n", .{aot_result.stdout});
                _ = shared.failed.fetchAdd(1, .acq_rel);
            }
        } else {
            if (is_xfail) {
                std.debug.print("XPASS\n", .{});
                _ = shared.xpassed.fetchAdd(1, .acq_rel);
            } else {
                std.debug.print("PASS\n", .{});
                _ = shared.passed.fetchAdd(1, .acq_rel);
            }
        }
        shared.output_mutex.unlock(shared.io);
    }
}

fn hashFileHex(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, path: []const u8) ![]const u8 {
    const data = try cwd.readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(data);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    return bytesToHexLower(allocator, &digest);
}

fn bytesToHexLower(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const hex = "0123456789abcdef";
    var out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0F];
    }
    return out;
}

const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

fn runCommand(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8, timeout_ms: u64) !CommandResult {
    const timeout: std.Io.Timeout = if (timeout_ms == 0) .none else .{ .duration = .{
        .raw = std.Io.Duration.fromMilliseconds(@intCast(timeout_ms)),
        .clock = .real,
    } };

    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .timeout = timeout,
        .stdout_limit = .limited(16 * 1024 * 1024),
        .stderr_limit = .limited(16 * 1024 * 1024),
    }) catch |err| switch (err) {
        error.Timeout => return CommandResult{
            .stdout = try allocator.dupe(u8, ""),
            .stderr = try std.fmt.allocPrint(allocator, "\n[AOT-DIFF] timeout\n", .{}),
            .exit_code = 124,
        },
        else => return err,
    };

    const exit_code: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };

    return CommandResult{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = exit_code,
    };
}

fn getenvU64(allocator: std.mem.Allocator, name: []const u8) ?u64 {
    const raw = getenvOwned(allocator, name) orelse return null;
    defer allocator.free(raw);
    return std.fmt.parseInt(u64, raw, 10) catch null;
}

fn getenvOwned(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    // std.c.getenv 需要 sentinel-terminated 字符串
    var name_buf: [256]u8 = undefined;
    if (name.len + 1 > name_buf.len) return null;
    @memcpy(name_buf[0..name.len], name);
    name_buf[name.len] = 0;
    const name_z: [*:0]const u8 = @ptrCast(&name_buf);
    const raw = std.c.getenv(name_z) orelse return null;
    return allocator.dupe(u8, std.mem.span(raw)) catch return null;
}

fn loadListFile(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, path: []const u8) !std.StringHashMap([]const u8) {
    var map = std.StringHashMap([]const u8).init(allocator);
    const contents = cwd.readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch return map;
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
