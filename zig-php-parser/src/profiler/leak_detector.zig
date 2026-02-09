const std = @import("std");
const Allocator = std.mem.Allocator;

/// 分配信息
pub const AllocationInfo = struct {
    size: usize,
    stack_trace: []usize,
    timestamp: i64,
};

/// 内存泄漏检测器
pub const LeakDetector = struct {
    allocator: Allocator,
    /// 分配记录
    allocations: std.AutoHashMap(usize, AllocationInfo),
    /// 是否启用
    enabled: bool,
    /// 互斥锁
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator) LeakDetector {
        return LeakDetector{
            .allocator = allocator,
            .allocations = std.AutoHashMap(usize, AllocationInfo).init(allocator),
            .enabled = false,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *LeakDetector) void {
        var it = self.allocations.valueIterator();
        while (it.next()) |info| {
            self.allocator.free(info.stack_trace);
        }
        self.allocations.deinit();
    }

    pub fn enable(self: *LeakDetector) void {
        self.enabled = true;
    }

    pub fn disable(self: *LeakDetector) void {
        self.enabled = false;
    }

    pub fn recordAllocation(self: *LeakDetector, ptr: usize, size: usize) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // 简化实现：不捕获栈追踪
        const stack_trace = try self.allocator.alloc(usize, 0);

        try self.allocations.put(ptr, .{
            .size = size,
            .stack_trace = stack_trace,
            .timestamp = std.time.milliTimestamp(),
        });
    }

    pub fn recordDeallocation(self: *LeakDetector, ptr: usize) void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.allocations.fetchRemove(ptr)) |entry| {
            self.allocator.free(entry.value.stack_trace);
        }
    }

    pub fn checkLeaks(self: *LeakDetector, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.allocations.count() == 0) {
            try writer.writeAll("No memory leaks detected.\n");
            return;
        }

        try writer.print("Detected {d} memory leaks:\n", .{self.allocations.count()});

        var it = self.allocations.iterator();
        while (it.next()) |entry| {
            const info = entry.value_ptr.*;
            try writer.print("\nLeak at 0x{x}:\n", .{entry.key_ptr.*});
            try writer.print("  Size: {d} bytes\n", .{info.size});
            try writer.print("  Timestamp: {d}\n", .{info.timestamp});
        }
    }

    pub fn getLeakCount(self: *LeakDetector) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.allocations.count();
    }
};
