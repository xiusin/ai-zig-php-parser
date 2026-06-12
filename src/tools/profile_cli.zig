const std = @import("std");
const runtime = @import("runtime");

const FlameGraphGenerator = runtime.flamegraph.FlameGraphGenerator;
const Profiler = runtime.profiler.Profiler;

const Command = enum {
    folded_to_svg,
    folded_to_pprof,
    help,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) return printHelp();

    const command = std.meta.stringToEnum(Command, args[1]) orelse return printHelp();
    switch (command) {
        .folded_to_svg => try runFoldedToSvg(allocator, args[2..]),
        .folded_to_pprof => try runFoldedToPprof(allocator, args[2..]),
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

fn runFoldedToSvg(allocator: std.mem.Allocator, args: []const []const u8) !void {
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

    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();
    const content = try input_file.readToEndAlloc(allocator, 64 * 1024 * 1024);
    defer allocator.free(content);

    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();

    var gen = try FlameGraphGenerator.init(allocator, &profiler);
    defer gen.deinit();
    gen.setMinDisplayTime(0);

    try gen.buildFromFoldedFormat(content, unit);

    const svg = try gen.generateSVG(allocator, width, height);
    defer allocator.free(svg);

    const out = try std.fs.cwd().createFile(output_path, .{});
    defer out.close();
    try out.writeAll(svg);
}

fn runFoldedToPprof(allocator: std.mem.Allocator, args: []const []const u8) !void {
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

    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();
    const content = try input_file.readToEndAlloc(allocator, 64 * 1024 * 1024);
    defer allocator.free(content);

    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();

    var gen = try FlameGraphGenerator.init(allocator, &profiler);
    defer gen.deinit();
    gen.setMinDisplayTime(0);
    try gen.buildFromFoldedFormat(content, unit);

    const out = try std.fs.cwd().createFile(output_path, .{});
    defer out.close();
    var out_buf: [16 * 1024]u8 = undefined;
    var w = out.writer(&out_buf);
    try runtime.pprof.writeCpuProfileFromFlameGraph(allocator, &w.interface, gen.root, period_ns);
    try w.end();
}
