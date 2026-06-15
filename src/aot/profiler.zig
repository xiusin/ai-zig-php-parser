const std = @import("std");
const builtin = @import("builtin");

/// Zig 0.17 兼容：替代 nanoTimestamp()（已移除）
inline fn nanoTimestamp() i128 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return @as(i128, @intCast(ts.sec)) * std.time.ns_per_s + @as(i128, @intCast(ts.nsec));
}

pub const ProfilerType = enum {
    none,
    perf,
    tracy,
    custom,
};

pub const FunctionCall = struct {
    name: []const u8,
    start_time_ns: u64,
    end_time_ns: u64,
    depth: u32,
    cpu_cycles: u64,
    instructions: u64,
    cache_misses: u64,

    pub fn duration(self: *const FunctionCall) u64 {
        return self.end_time_ns - self.start_time_ns;
    }
};

pub const FunctionStats = struct {
    name: []const u8,
    call_count: u64,
    total_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    total_cycles: u64,
    total_instructions: u64,
    total_cache_misses: u64,

    pub fn avgTime(self: *const FunctionStats) u64 {
        if (self.call_count == 0) return 0;
        return self.total_time_ns / self.call_count;
    }
};

pub const Profiler = struct {
    allocator: std.mem.Allocator,
    profiler_type: ProfilerType,
    enabled: bool,
    call_stack: std.ArrayListUnmanaged(FunctionCall),
    function_stats: std.StringHashMapUnmanaged(FunctionStats),
    total_calls: u64,
    total_time_ns: u64,
    mutex: std.atomic.Mutex,

    pub fn init(allocator: std.mem.Allocator, profiler_type: ProfilerType) !Profiler {
        var profiler = Profiler{
            .allocator = allocator,
            .profiler_type = profiler_type,
            .enabled = false,
            .call_stack = .{ .items = &.{}, .capacity = 0 },
            .function_stats = .{},
            .total_calls = 0,
            .total_time_ns = 0,
            .mutex = .unlocked,
        };

        switch (profiler_type) {
            .perf => {
                if (builtin.os.tag != .linux) {
                    profiler.profiler_type = .custom;
                }
            },
            else => {},
        }

        return profiler;
    }

    pub fn deinit(self: *Profiler) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        var iter = self.function_stats.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.function_stats.deinit(self.allocator);
        self.call_stack.deinit(self.allocator);
    }

    pub fn enable(self: *Profiler) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        self.enabled = true;
    }

    pub fn disable(self: *Profiler) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        self.enabled = false;
    }

    pub fn enterFunction(self: *Profiler, name: []const u8) !void {
        if (!self.enabled) return;

        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        const call = FunctionCall{
            .name = name,
            .start_time_ns = @intCast(nanoTimestamp()),
            .end_time_ns = 0,
            .depth = @intCast(self.call_stack.items.len),
            .cpu_cycles = 0,
            .instructions = 0,
            .cache_misses = 0,
        };

        try self.call_stack.append(self.allocator, call);
        self.total_calls += 1;
    }

    pub fn exitFunction(self: *Profiler, name: []const u8) !void {
        if (!self.enabled) return;

        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        const call_opt = self.call_stack.pop();
        if (call_opt == null) return error.CallStackUnderflow;
        var call = call_opt.?;

        if (!std.mem.eql(u8, call.name, name)) {
            return error.FunctionNameMismatch;
        }

        call.end_time_ns = @intCast(nanoTimestamp());

        try self.updateStats(&call);
        self.total_time_ns += call.duration();
    }

    fn updateStats(self: *Profiler, call: *const FunctionCall) !void {
        const gop = try self.function_stats.getOrPut(self.allocator, call.name);
        if (!gop.found_existing) {
            const name_copy = try self.allocator.dupe(u8, call.name);
            gop.key_ptr.* = name_copy;
            gop.value_ptr.* = FunctionStats{
                .name = name_copy,
                .call_count = 0,
                .total_time_ns = 0,
                .min_time_ns = std.math.maxInt(u64),
                .max_time_ns = 0,
                .total_cycles = 0,
                .total_instructions = 0,
                .total_cache_misses = 0,
            };
        }

        const stats = gop.value_ptr;
        const duration = call.duration();

        stats.call_count += 1;
        stats.total_time_ns += duration;
        stats.total_cycles += call.cpu_cycles;
        stats.total_instructions += call.instructions;
        stats.total_cache_misses += call.cache_misses;

        if (duration < stats.min_time_ns) stats.min_time_ns = duration;
        if (duration > stats.max_time_ns) stats.max_time_ns = duration;
    }

    pub fn getAllStats(self: *Profiler, allocator: std.mem.Allocator) ![]FunctionStats {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        var list: std.ArrayListUnmanaged(FunctionStats) = .{ .items = &.{}, .capacity = 0 };
        errdefer list.deinit(allocator);

        var iter = self.function_stats.iterator();
        while (iter.next()) |entry| {
            try list.append(allocator, entry.value_ptr.*);
        }

        return list.toOwnedSlice(allocator);
    }

    pub fn snapshotCallStackNames(self: *Profiler, allocator: std.mem.Allocator) ![]const []const u8 {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        const stack = try allocator.alloc([]const u8, self.call_stack.items.len);
        for (self.call_stack.items, 0..) |call, i| {
            stack[i] = call.name;
        }
        return stack;
    }

    pub fn reset(self: *Profiler) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        self.call_stack.clearRetainingCapacity();
        self.total_calls = 0;
        self.total_time_ns = 0;

        var iter = self.function_stats.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.function_stats.clearRetainingCapacity();
    }
};

var global_profiler_ptr = std.atomic.Value(usize).init(0);

pub fn setGlobalProfiler(profiler: ?*Profiler) void {
    const v: usize = if (profiler) |p| @intFromPtr(p) else 0;
    global_profiler_ptr.store(v, .seq_cst);
}

pub fn getGlobalProfiler() ?*Profiler {
    const v = global_profiler_ptr.load(.seq_cst);
    if (v == 0) return null;
    return @ptrFromInt(v);
}

pub fn enterGlobal(name: []const u8) void {
    if (getGlobalProfiler()) |p| {
        p.enterFunction(name) catch {};
    }
}

pub fn exitGlobal(name: []const u8) void {
    if (getGlobalProfiler()) |p| {
        p.exitFunction(name) catch {};
    }
}
