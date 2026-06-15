const std = @import("std");
const FlameGraphNode = @import("flamegraph.zig").FlameGraphNode;


/// Adapter that wraps ArrayListUnmanaged(u8) to provide a writer-like interface.
/// Used because ArrayListUnmanaged.writer() was removed in Zig 0.17.
const BufWriter = struct {
    buf: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    pub fn writeByte(self: *BufWriter, byte: u8) !void {
        try self.buf.append(self.allocator, byte);
    }

    pub fn writeAll(self: *BufWriter, bytes: []const u8) !void {
        try self.buf.appendSlice(self.allocator, bytes);
    }
};

const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    bytes = 2,
    fixed32 = 5,
};

fn writeKey(writer: anytype, field_number: u32, wire: WireType) !void {
    const key: u64 = (@as(u64, field_number) << 3) | @as(u64, @intFromEnum(wire));
    try writeVarint(writer, key);
}

fn writeVarint(writer: anytype, value: u64) !void {
    var v = value;
    while (v >= 0x80) {
        try writer.writeByte(@as(u8, @intCast((v & 0x7f) | 0x80)));
        v >>= 7;
    }
    try writer.writeByte(@as(u8, @intCast(v)));
}

fn writeSVarint(writer: anytype, value: i64) !void {
    const zigzag: u64 = @as(u64, @bitCast((value << 1) ^ (value >> 63)));
    try writeVarint(writer, zigzag);
}

fn writeBytes(writer: anytype, bytes: []const u8) !void {
    try writeVarint(writer, bytes.len);
    try writer.writeAll(bytes);
}

fn writeEmbedded(writer: anytype, field_number: u32, bytes: []const u8) !void {
    try writeKey(writer, field_number, .bytes);
    try writeBytes(writer, bytes);
}

const StringTable = struct {
    allocator: std.mem.Allocator,
    strings: std.ArrayListUnmanaged([]const u8) = .{ .items = &.{}, .capacity = 0 },
    index: std.StringHashMapUnmanaged(u64) = .{},

    fn init(allocator: std.mem.Allocator) !StringTable {
        var self = StringTable{ .allocator = allocator };
        try self.strings.append(allocator, "");
        try self.index.put(allocator, "", 0);
        return self;
    }

    fn deinit(self: *StringTable) void {
        self.strings.deinit(self.allocator);
        self.index.deinit(self.allocator);
    }

    fn intern(self: *StringTable, s: []const u8) !u64 {
        const gop = try self.index.getOrPut(self.allocator, s);
        if (gop.found_existing) return gop.value_ptr.*;
        const id: u64 = @intCast(self.strings.items.len);
        try self.strings.append(self.allocator, s);
        gop.value_ptr.* = id;
        return id;
    }
};

const FunctionEntry = struct {
    id: u64,
    name: []const u8,
};

const LocationEntry = struct {
    id: u64,
    function_id: u64,
};

const SampleEntry = struct {
    location_ids: []u64,
    value_ns: i64,
};

fn collectProfileData(
    allocator: std.mem.Allocator,
    root: *const FlameGraphNode,
    funcs: *std.ArrayListUnmanaged(FunctionEntry),
    locs: *std.ArrayListUnmanaged(LocationEntry),
    samples: *std.ArrayListUnmanaged(SampleEntry),
    func_ids: *std.StringHashMapUnmanaged(u64),
    loc_ids: *std.StringHashMapUnmanaged(u64),
) !void {
    var stack: std.ArrayListUnmanaged(u64) = .{ .items = &.{}, .capacity = 0 };
    defer stack.deinit(allocator);

    try walkNode(allocator, root, funcs, locs, samples, func_ids, loc_ids, &stack);
}

fn getOrCreateFunction(
    allocator: std.mem.Allocator,
    funcs: *std.ArrayListUnmanaged(FunctionEntry),
    func_ids: *std.StringHashMapUnmanaged(u64),
    name: []const u8,
) !u64 {
    const gop = try func_ids.getOrPut(allocator, name);
    if (gop.found_existing) return gop.value_ptr.*;
    const id: u64 = @intCast(funcs.items.len + 1);
    try funcs.append(allocator, .{ .id = id, .name = name });
    gop.value_ptr.* = id;
    return id;
}

fn getOrCreateLocation(
    allocator: std.mem.Allocator,
    locs: *std.ArrayListUnmanaged(LocationEntry),
    loc_ids: *std.StringHashMapUnmanaged(u64),
    function_id: u64,
    name: []const u8,
) !u64 {
    const gop = try loc_ids.getOrPut(allocator, name);
    if (gop.found_existing) return gop.value_ptr.*;
    const id: u64 = @intCast(locs.items.len + 1);
    try locs.append(allocator, .{ .id = id, .function_id = function_id });
    gop.value_ptr.* = id;
    return id;
}

fn walkNode(
    allocator: std.mem.Allocator,
    node: *const FlameGraphNode,
    funcs: *std.ArrayListUnmanaged(FunctionEntry),
    locs: *std.ArrayListUnmanaged(LocationEntry),
    samples: *std.ArrayListUnmanaged(SampleEntry),
    func_ids: *std.StringHashMapUnmanaged(u64),
    loc_ids: *std.StringHashMapUnmanaged(u64),
    stack: *std.ArrayListUnmanaged(u64),
) !void {
    if (!(node.parent == null and std.mem.eql(u8, node.name, "root"))) {
        const function_id = try getOrCreateFunction(allocator, funcs, func_ids, node.name);
        const location_id = try getOrCreateLocation(allocator, locs, loc_ids, function_id, node.name);
        try stack.append(allocator, location_id);
        defer _ = stack.pop();

        if (node.self_time_ns > 0) {
            const loc_count = stack.items.len;
            const locs_copy = try allocator.alloc(u64, loc_count);
            for (0..loc_count) |i| {
                locs_copy[i] = stack.items[loc_count - 1 - i];
            }
            try samples.append(allocator, .{
                .location_ids = locs_copy,
                .value_ns = @intCast(node.self_time_ns),
            });
        }
    }

    var it = node.children.valueIterator();
    while (it.next()) |child| {
        try walkNode(allocator, child.*, funcs, locs, samples, func_ids, loc_ids, stack);
    }
}

fn writeValueType(allocator: std.mem.Allocator, st: *StringTable, type_name: []const u8, unit: []const u8) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    errdefer buf.deinit(allocator);
    var w = BufWriter{ .buf = &buf, .allocator = allocator };

    const t = try st.intern(type_name);
    const u = try st.intern(unit);

    try writeKey(&w, 1, .varint);
    try writeVarint(&w, t);
    try writeKey(&w, 2, .varint);
    try writeVarint(&w, u);

    return buf.toOwnedSlice(allocator);
}

fn writeFunctionMsg(allocator: std.mem.Allocator, st: *StringTable, f: FunctionEntry) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    errdefer buf.deinit(allocator);
    var w = BufWriter{ .buf = &buf, .allocator = allocator };

    const name_id = try st.intern(f.name);
    const sys_id = try st.intern(f.name);

    try writeKey(&w, 1, .varint);
    try writeVarint(&w, f.id);
    try writeKey(&w, 2, .varint);
    try writeVarint(&w, name_id);
    try writeKey(&w, 3, .varint);
    try writeVarint(&w, sys_id);

    return buf.toOwnedSlice(allocator);
}

fn writeLocationMsg(allocator: std.mem.Allocator, loc: LocationEntry) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    errdefer buf.deinit(allocator);
    var w = BufWriter{ .buf = &buf, .allocator = allocator };

    try writeKey(&w, 1, .varint);
    try writeVarint(&w, loc.id);

    var line_buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    defer line_buf.deinit(allocator);
    var lw = BufWriter{ .buf = &line_buf, .allocator = allocator };
    try writeKey(&lw, 1, .varint);
    try writeVarint(&lw, loc.function_id);
    try writeEmbedded(&w, 4, line_buf.items);

    return buf.toOwnedSlice(allocator);
}

fn writeSampleMsg(allocator: std.mem.Allocator, s: SampleEntry) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    errdefer buf.deinit(allocator);
    var w = BufWriter{ .buf = &buf, .allocator = allocator };

    for (s.location_ids) |loc_id| {
        try writeKey(&w, 1, .varint);
        try writeVarint(&w, loc_id);
    }
    try writeKey(&w, 2, .varint);
    try writeSVarint(&w, s.value_ns);

    return buf.toOwnedSlice(allocator);
}

pub fn writeCpuProfileFromFlameGraph(
    allocator: std.mem.Allocator,
    writer: anytype,
    root: *const FlameGraphNode,
    sampling_period_ns: u64,
) !void {
    var st = try StringTable.init(allocator);
    defer st.deinit();

    var funcs: std.ArrayListUnmanaged(FunctionEntry) = .{ .items = &.{}, .capacity = 0 };
    defer funcs.deinit(allocator);
    var locs: std.ArrayListUnmanaged(LocationEntry) = .{ .items = &.{}, .capacity = 0 };
    defer locs.deinit(allocator);
    var samples: std.ArrayListUnmanaged(SampleEntry) = .{ .items = &.{}, .capacity = 0 };
    defer {
        for (samples.items) |s| allocator.free(s.location_ids);
        samples.deinit(allocator);
    }

    var func_ids: std.StringHashMapUnmanaged(u64) = .{};defer func_ids.deinit(allocator);
    var loc_ids: std.StringHashMapUnmanaged(u64) = .{};defer loc_ids.deinit(allocator);

    try collectProfileData(allocator, root, &funcs, &locs, &samples, &func_ids, &loc_ids);

    const cpu_type = try writeValueType(allocator, &st, "cpu", "nanoseconds");
    defer allocator.free(cpu_type);

    var profile_buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    defer profile_buf.deinit(allocator);
    var pw = BufWriter{ .buf = &profile_buf, .allocator = allocator };

    const now_ns: u64 = blk: {
    var ts: std.os.linux.timespec = undefined;
    if (std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts) != 0) return error.ClockFailed;
    break :blk @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
};
    try writeKey(&pw, 1, .varint);
    try writeVarint(&pw, now_ns);

    try writeKey(&pw, 2, .varint);
    try writeVarint(&pw, root.total_time_ns);

    try writeEmbedded(&pw, 3, cpu_type);
    try writeKey(&pw, 4, .varint);
    try writeVarint(&pw, sampling_period_ns);

    try writeEmbedded(&pw, 5, cpu_type);

    for (samples.items) |s| {
        const sm = try writeSampleMsg(allocator, s);
        defer allocator.free(sm);
        try writeEmbedded(&pw, 6, sm);
    }

    for (locs.items) |l| {
        const lm = try writeLocationMsg(allocator, l);
        defer allocator.free(lm);
        try writeEmbedded(&pw, 8, lm);
    }

    for (funcs.items) |f| {
        const fm = try writeFunctionMsg(allocator, &st, f);
        defer allocator.free(fm);
        try writeEmbedded(&pw, 9, fm);
    }

    const default_type = try st.intern("cpu");
    try writeKey(&pw, 14, .varint);
    try writeVarint(&pw, default_type);

    for (st.strings.items) |s| {
        try writeKey(&pw, 13, .bytes);
        try writeBytes(&pw, s);
    }

    try writer.writeAll(profile_buf.items);
}

test "pprof writes cpu profile protobuf" {
    const allocator = std.testing.allocator;

    const root = try FlameGraphNode.init(allocator, "root");
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
    }
    root.total_time_ns = 2_000_000;

    const a = try root.addChild(allocator, "main", 2_000_000);
    _ = try a.addChild(allocator, "hot", 2_000_000);
    root.calculateSelfTime();

    var buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    defer buf.deinit(allocator);

    try writeCpuProfileFromFlameGraph(allocator, buf.writer(), root, 1_000_000);
    try std.testing.expect(buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "cpu") != null);
}
