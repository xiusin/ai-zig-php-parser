//! PProf profiling — stub for AOT
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn writeCpuProfileFromFlameGraph(allocator: Allocator, writer: anytype, root: anytype, sampling_interval_ns: u64) !void {
    _ = allocator;
    _ = writer;
    _ = root;
    _ = sampling_interval_ns;
}
