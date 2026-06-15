const std = @import("std");
const runtime = @import("runtime");

const FlameGraphGenerator = runtime.flamegraph.FlameGraphGenerator;
const Profiler = runtime.profiler.Profiler;

const Command = enum {
    folded_to_svg,
    folded_to_pprof,
    help,
};

pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create thread-local Io for file operations (Zig 0.17 API)
    var environ: [0:null]?[*:0]u8 = [_:null]?[*:0]u8{};
    var threaded = std.Io.Threaded.init(allocator, .{
        .argv0 = .init(.{ .vector = &.{} }),
        .environ = .{ .block = .{ .slice = &environ } },
    });
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args_iter = try std.process.Args.Iterator.initAllocator(init.args, allocator);
    defer args_iter.deinit();
    var args_list = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer args_list.deinit();
    while (args_iter.next()) |arg| {
        try args_list.append(arg);
    }
    const args = args_list.items;

    if (args.len < 2) return printHelp();

    const command = std.meta.stringToEnum(Command, args[1]) orelse return printHelp();
    switch (command) {
        .folded_to_svg => try runFoldedToSvg(allocator, io, cwd, args[2..]),
        .folded_to_pprof => try runFoldedToPprof(allocator, io, cwd, args[2..]),
        .help => try printHelp(),
    }
}

fn printHelp() !void {
    std.debug.print(
        \\Profile Tooling
        \\
        \\Usage:
        \\  profile-cli folded_to_svg <input.folded> <output.svg> [--width <n>] [--height <n>] [--unit us|ns]
        \\  profile-cli folded_to_pprof <input.folded> <output.pb> [--unit us|ns] [--period-ns <n>]
        \\
    , .{});
}

fn parseUnit(s: []const u8) FlameGraphGenerator.FoldedUnit {
    if (std.mem.eql(u8, s, "ns")) return .nanoseconds;
    return .microseconds;
}

fn runFoldedToSvg(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, args: []const []const u8) !void {
    if (args.len < 2) return printHelp();

    const input_path = args[0];
    const output_path = args[1];

    var width: u32 = 1200;
    var height: u32 = 800;
    var unit: FlameGraphGenerator.FoldedUnit = .microseconds;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--width") and i + 1 < args.len) {
            width = try std.fmt.parseInt(u32, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--height") and i + 1 < args.len) {
            height = try std.fmt.parseInt(u32, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--unit") and i + 1 < args.len) {
            unit = parseUnit(args[i + 1]);
            i += 1;
        }
    }

    const content = try cwd.readFileAlloc(io, input_path, allocator, .unlimited);
    defer allocator.free(content);

    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();

    var gen = try FlameGraphGenerator.init(allocator, io, &profiler);
    defer gen.deinit();
    gen.setMinDisplayTime(0);

    try gen.buildFromFoldedFormat(content, unit);

    const svg = try gen.generateSVG(allocator, width, height);
    defer allocator.free(svg);

    const out = try cwd.createFile(io, output_path, .{});
    defer out.close(io);
    var out_buf: [4096]u8 = undefined;
    var writer = out.writer(io, &out_buf);
    try writer.interface.writeAll(svg);
    try writer.flush();
}

fn runFoldedToPprof(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, args: []const []const u8) !void {
    if (args.len < 2) return printHelp();

    const input_path = args[0];
    const output_path = args[1];

    var unit: FlameGraphGenerator.FoldedUnit = .microseconds;
    var period_ns: u64 = 1_000_000;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--unit") and i + 1 < args.len) {
            unit = parseUnit(args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--period-ns") and i + 1 < args.len) {
            period_ns = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        }
    }

    const content = try cwd.readFileAlloc(io, input_path, allocator, .unlimited);
    defer allocator.free(content);

    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();

    var gen = try FlameGraphGenerator.init(allocator, io, &profiler);
    defer gen.deinit();
    gen.setMinDisplayTime(0);
    try gen.buildFromFoldedFormat(content, unit);

    const out = try cwd.createFile(io, output_path, .{});
    defer out.close(io);
    var out_buf: [16 * 1024]u8 = undefined;
    var writer = out.writer(io, &out_buf);
    try runtime.pprof.writeCpuProfileFromFlameGraph(allocator, &writer.interface, gen.root, period_ns);
    try writer.flush();
}
