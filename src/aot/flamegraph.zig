const std = @import("std");
const Profiler = @import("profiler.zig").Profiler;

pub const FlameGraphNode = struct {
    name: []const u8,
    total_time_ns: u64,
    self_time_ns: u64,
    children: std.StringHashMapUnmanaged(*FlameGraphNode),
    parent: ?*FlameGraphNode,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*FlameGraphNode {
        const node = try allocator.create(FlameGraphNode);
        errdefer allocator.destroy(node);

        node.name = try allocator.dupe(u8, name);
        errdefer allocator.free(node.name);
        node.total_time_ns = 0;
        node.self_time_ns = 0;
        node.children = .{};
        node.parent = null;
        return node;
    }

    pub fn deinit(self: *FlameGraphNode, allocator: std.mem.Allocator) void {
        var iter = self.children.valueIterator();
        while (iter.next()) |child| {
            child.*.deinit(allocator);
            allocator.destroy(child.*);
        }
        self.children.deinit(allocator);
        allocator.free(self.name);
    }

    pub fn addChild(self: *FlameGraphNode, allocator: std.mem.Allocator, name: []const u8, time_ns: u64) !*FlameGraphNode {
        if (self.children.get(name)) |child| {
            child.total_time_ns += time_ns;
            return child;
        }

        const child = try FlameGraphNode.init(allocator, name);
        child.parent = self;
        child.total_time_ns = time_ns;
        try self.children.put(allocator, child.name, child);
        return child;
    }

    pub fn calculateSelfTime(self: *FlameGraphNode) void {
        var children_time: u64 = 0;
        var iter = self.children.valueIterator();
        while (iter.next()) |child| {
            children_time += child.*.total_time_ns;
            child.*.calculateSelfTime();
        }
        self.self_time_ns = if (self.total_time_ns > children_time) self.total_time_ns - children_time else 0;
    }
};

pub const FlameGraphGenerator = struct {
    allocator: std.mem.Allocator,
    profiler: *Profiler,
    root: *FlameGraphNode,
    sampling_interval_ns: u64,
    min_display_time_ns: u64,
    mutex: std.atomic.Mutex,
    sampling_running: std.atomic.Value(bool),
    sampling_thread: ?std.Thread,

    pub fn init(allocator: std.mem.Allocator, profiler: *Profiler) !FlameGraphGenerator {
        const root = try FlameGraphNode.init(allocator, "root");
        return .{
            .allocator = allocator,
            .profiler = profiler,
            .root = root,
            .sampling_interval_ns = 1_000_000,
            .min_display_time_ns = 0,
            .mutex = .unlocked,
            .sampling_running = std.atomic.Value(bool).init(false),
            .sampling_thread = null,
        };
    }

    pub fn deinit(self: *FlameGraphGenerator) void {
        self.stopSampling();
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
    }

    pub fn setSamplingInterval(self: *FlameGraphGenerator, interval_ns: u64) void {
        self.sampling_interval_ns = interval_ns;
    }

    pub fn setMinDisplayTime(self: *FlameGraphGenerator, min_time_ns: u64) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        self.min_display_time_ns = min_time_ns;
    }

    pub fn startSampling(self: *FlameGraphGenerator) !void {
        if (self.sampling_running.swap(true, .seq_cst)) return;
        const thread = try std.Thread.spawn(.{}, samplingThreadMain, .{self});
        self.sampling_thread = thread;
    }

    pub fn stopSampling(self: *FlameGraphGenerator) void {
        if (!self.sampling_running.swap(false, .seq_cst)) return;
        if (self.sampling_thread) |thread| {
            thread.join();
            self.sampling_thread = null;
        }
    }

    fn samplingThreadMain(self: *FlameGraphGenerator) void {
        while (self.sampling_running.load(.seq_cst)) {
            self.sampleFromProfilerCurrentStack(self.sampling_interval_ns) catch {};
            var req: std.posix.timespec = .{ .sec = @intCast(self.sampling_interval_ns / 1_000_000_000), .nsec = @intCast(self.sampling_interval_ns % 1_000_000_000) };
            _ = std.posix.system.nanosleep(&req, null);
        }
    }

    pub fn sampleFromProfilerCurrentStack(self: *FlameGraphGenerator, weight_ns: u64) !void {
        const stack_names = try self.profiler.snapshotCallStackNames(self.allocator);
        defer self.allocator.free(stack_names);

        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        self.root.total_time_ns += weight_ns;

        var current = self.root;
        for (stack_names) |name| {
            const child = try current.addChild(self.allocator, name, weight_ns);
            current = child;
        }

        self.root.calculateSelfTime();
    }

    pub fn generateFoldedFormat(self: *FlameGraphGenerator, allocator: std.mem.Allocator) ![]u8 {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        var buffer: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };errdefer buffer.deinit(allocator);

        var aw = std.Io.Writer.Allocating.fromArrayList(allocator, &buffer);

        var stack: std.ArrayListUnmanaged([]const u8) = .{ .items = &.{}, .capacity = 0 };defer stack.deinit(allocator);

        try self.writeFoldedNode(&aw.writer, allocator, self.root, &stack);

        return buffer.toOwnedSlice(allocator);
    }

    fn writeFoldedNode(self: *FlameGraphGenerator, writer: anytype, allocator: std.mem.Allocator, node: *const FlameGraphNode, stack: *std.ArrayListUnmanaged([]const u8)) !void {
        if (node.parent == null and std.mem.eql(u8, node.name, "root")) {
            var iter = node.children.valueIterator();
            while (iter.next()) |child| {
                try self.writeFoldedNode(writer, allocator, child.*, stack);
            }
            return;
        }

        if (node.total_time_ns < self.min_display_time_ns) return;

        try stack.append(allocator, node.name);
        defer _ = stack.pop();

        if (node.self_time_ns > 0) {
            for (stack.items, 0..) |name, i| {
                if (i > 0) try writer.writeAll(";");
                try writer.writeAll(name);
            }
            const time_us = node.self_time_ns / 1000;
            try writer.print(" {d}\n", .{time_us});
        }

        var iter = node.children.valueIterator();
        while (iter.next()) |child| {
            try self.writeFoldedNode(writer, allocator, child.*, stack);
        }
    }
};
