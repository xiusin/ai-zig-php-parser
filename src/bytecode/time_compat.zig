const std = @import("std");

fn getIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

pub fn timestamp() i64 {
    const ts = std.Io.Timestamp.now(getIo(), .real);
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
}

pub fn nanoTimestamp() i128 {
    const ts = std.Io.Timestamp.now(getIo(), .real);
    return ts.nanoseconds;
}

pub fn milliTimestamp() i64 {
    const ts = std.Io.Timestamp.now(getIo(), .real);
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_ms));
}

pub fn microTimestamp() i64 {
    const ts = std.Io.Timestamp.now(getIo(), .real);
    return @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_us));
}

pub const Timer = struct {
    start_ts: std.Io.Timestamp,

    pub fn start() !Timer {
        return .{
            .start_ts = std.Io.Timestamp.now(getIo(), .awake),
        };
    }

    pub fn read(self: *const Timer) u64 {
        const now = std.Io.Timestamp.now(getIo(), .awake);
        return @intCast(self.start_ts.durationTo(now).nanoseconds);
    }

    pub fn lap(self: *Timer) u64 {
        const now = std.Io.Timestamp.now(getIo(), .awake);
        const elapsed = @as(u64, @intCast(self.start_ts.durationTo(now).nanoseconds));
        self.start_ts = now;
        return elapsed;
    }

    pub fn reset(self: *Timer) void {
        self.start_ts = std.Io.Timestamp.now(getIo(), .awake);
    }
};

pub fn sleep(ns: u64) void {
    const io = getIo();
    const duration: std.Io.Clock.Duration = .{
        .raw = .{ .nanoseconds = @intCast(ns) },
        .clock = .awake,
    };
    duration.sleep(io) catch {};
}
