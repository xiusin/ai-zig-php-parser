const std = @import("std");
const Value = @import("types.zig").Value;
const PHPString = @import("types.zig").PHPString;
const PHPArray = @import("types.zig").PHPArray;
const PHPObject = @import("types.zig").PHPObject;
const PHPResource = @import("types.zig").PHPResource;
const UserFunction = @import("types.zig").UserFunction;
const Closure = @import("types.zig").Closure;
const ArrowFunction = @import("types.zig").ArrowFunction;
const StructInstance = @import("types.zig").StructInstance;

pub fn Box(comptime T: type) type {
    return struct {
        ref_count: u32,
        gc_info: GCInfo,
        data: T,

        pub const GCInfo = packed struct {
            color: Color = .white,
            buffered: bool = false,

            pub const Color = enum(u2) {
                white = 0,
                gray = 1,
                black = 2,
                purple = 3,
            };
        };

        pub fn retain(self: *@This()) *@This() {
            self.ref_count += 1;
            return self;
        }

        pub fn release(self: *@This(), allocator: std.mem.Allocator) void {
            // Safety check to prevent double-free
            if (self.ref_count == 0) {
                return; // Already freed
            }

            self.ref_count -= 1;
            if (self.ref_count == 0) {
                self.destroy(allocator);
            } else {
                // Mark as potential cycle root when ref count decreases
                self.gc_info.color = .purple;
            }
        }

        fn destroy(self: *@This(), allocator: std.mem.Allocator) void {
            // Additional safety check - if already destroyed, don't destroy again
            if (self.gc_info.color == .black) {
                return; // Already destroyed
            }

            // Call destructor if this is an object with __destruct method
            switch (T) {
                *PHPString => {
                    self.data.release(allocator);
                },
                *PHPArray => {
                    // Decrease reference count for all contained values
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *PHPObject => {
                    // Call destructor if defined
                    if (self.data.class.methods.get("__destruct")) |destruct_method| {
                        // 调用析构方法（需要VM实例，这里简化处理）
                        // 实际实现需要传入VM并调用destruct_method
                        _ = destruct_method;
                    }

                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *StructInstance => {
                    // Decrease reference count for all fields
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        decrementValueRefCount(entry.value_ptr.*, allocator);
                    }
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *PHPResource => {
                    self.data.destroy();
                    allocator.destroy(self.data);
                },
                *UserFunction => {
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *Closure => {
                    // Decrease reference count for captured variables
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        decrementValueRefCount(entry.value_ptr.*, allocator);
                    }
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                *ArrowFunction => {
                    // Decrease reference count for captured variables
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        decrementValueRefCount(entry.value_ptr.*, allocator);
                    }
                    self.data.deinit(allocator);
                    allocator.destroy(self.data);
                },
                else => {},
            }

            // Mark as destroyed
            self.gc_info.color = .black;
            self.ref_count = 0;
            allocator.destroy(self);
        }

        pub fn markGray(self: *@This()) void {
            if (self.gc_info.color != .gray) {
                self.gc_info.color = .gray;
                // Mark children gray recursively
                self.markChildrenGray();
            }
        }

        pub fn markChildrenGray(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *StructInstance => {
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }

        pub fn scan(self: *@This()) void {
            if (self.gc_info.color == .gray) {
                if (self.ref_count > 0) {
                    self.markBlack();
                } else {
                    self.gc_info.color = .white;
                    self.scanChildren();
                }
            }
        }

        pub fn scanChildren(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *StructInstance => {
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }

        pub fn markBlack(self: *@This()) void {
            self.gc_info.color = .black;
            self.markChildrenBlack();
        }

        pub fn markChildrenBlack(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *StructInstance => {
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }

        pub fn collectWhite(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.gc_info.color == .white and !self.gc_info.buffered) {
                self.gc_info.color = .black; // Prevent double collection
                self.collectChildrenWhite(allocator);
                self.destroy(allocator);
            }
        }

        pub fn collectChildrenWhite(self: *@This(), allocator: std.mem.Allocator) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *StructInstance => {
                    var iterator = self.data.fields.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                else => {},
            }
        }
    };
}

// Helper functions for cycle detection algorithm
fn decrementValueRefCount(value: Value, allocator: std.mem.Allocator) void {
    switch (value.getTag()) {
        .string => value.getAsString().release(allocator),
        .array => value.getAsArray().release(allocator),
        .object => value.getAsObject().release(allocator),
        .struct_instance => value.getAsStruct().release(allocator),
        .resource => value.getAsResource().release(allocator),
        .user_function => value.getAsUserFunc().release(allocator),
        .closure => value.getAsClosure().release(allocator),
        .arrow_function => value.getAsArrowFunc().release(allocator),
        else => {},
    }
}

fn markValueGray(value: Value) void {
    switch (value.getTag()) {
        .string => value.getAsString().markGray(),
        .array => value.getAsArray().markGray(),
        .object => value.getAsObject().markGray(),
        .struct_instance => value.getAsStruct().markGray(),
        .resource => value.getAsResource().markGray(),
        .user_function => value.getAsUserFunc().markGray(),
        .closure => value.getAsClosure().markGray(),
        .arrow_function => value.getAsArrowFunc().markGray(),
        else => {},
    }
}

fn scanValue(value: Value) void {
    switch (value.getTag()) {
        .string => value.getAsString().scan(),
        .array => value.getAsArray().scan(),
        .object => value.getAsObject().scan(),
        .struct_instance => value.getAsStruct().scan(),
        .resource => value.getAsResource().scan(),
        .user_function => value.getAsUserFunc().scan(),
        .closure => value.getAsClosure().scan(),
        .arrow_function => value.getAsArrowFunc().scan(),
        else => {},
    }
}

fn markValueBlack(value: Value) void {
    switch (value.getTag()) {
        .string => value.getAsString().markBlack(),
        .array => value.getAsArray().markBlack(),
        .object => value.getAsObject().markBlack(),
        .struct_instance => value.getAsStruct().markBlack(),
        .resource => value.getAsResource().markBlack(),
        .user_function => value.getAsUserFunc().markBlack(),
        .closure => value.getAsClosure().markBlack(),
        .arrow_function => value.getAsArrowFunc().markBlack(),
        else => {},
    }
}

fn collectValueWhite(value: Value, allocator: std.mem.Allocator) void {
    switch (value.getTag()) {
        .string => value.getAsString().collectWhite(allocator),
        .array => value.getAsArray().collectWhite(allocator),
        .object => value.getAsObject().collectWhite(allocator),
        .struct_instance => value.getAsStruct().collectWhite(allocator),
        .resource => value.getAsResource().collectWhite(allocator),
        .user_function => value.getAsUserFunc().collectWhite(allocator),
        .closure => value.getAsClosure().collectWhite(allocator),
        .arrow_function => value.getAsArrowFunc().collectWhite(allocator),
        else => {},
    }
}

pub const GarbageCollector = struct {
    allocator: std.mem.Allocator,
    memory_threshold: usize,
    allocated_memory: usize,

    /// 增量标记状态
    incremental_state: IncrementalState = .idle,
    gray_list: std.ArrayList(*anyopaque),

    /// 分代GC配置
    nursery_size: usize = 256 * 1024, // 256KB年轻代
    nursery_used: usize = 0,
    promotion_threshold: u8 = 2, // 存活2次后晋升

    /// 写屏障缓冲区
    write_barrier_buffer: std.ArrayList(WriteBarrierEntry),

    /// GC统计
    stats: GCStats = .{},

    /// 时间戳记录 (用于增量GC时间统计)
    mark_start_time: i64 = 0,
    sweep_start_time: i64 = 0,

    pub const IncrementalState = enum {
        idle,
        marking,
        sweeping,
    };

    pub const WriteBarrierEntry = struct {
        source: *anyopaque,
        target: *anyopaque,
    };

    pub const GCStats = struct {
        total_collections: u64 = 0,
        incremental_steps: u64 = 0,
        objects_marked: u64 = 0,
        objects_swept: u64 = 0,
        nursery_promotions: u64 = 0,

        // 增强的时间统计 (Requirements 2.6, 9.2)
        timing: GCTiming = .{},

        // 内存统计
        memory: GCMemoryStats = .{},

        pub const GCTiming = struct {
            /// 最近一次标记阶段耗时 (纳秒)
            last_mark_time_ns: u64 = 0,
            /// 最近一次清除阶段耗时 (纳秒)
            last_sweep_time_ns: u64 = 0,
            /// 最近一次GC总停顿时间 (纳秒)
            last_pause_time_ns: u64 = 0,
            /// 累计标记时间 (纳秒)
            total_mark_time_ns: u64 = 0,
            /// 累计清除时间 (纳秒)
            total_sweep_time_ns: u64 = 0,
            /// 累计停顿时间 (纳秒)
            total_pause_time_ns: u64 = 0,
            /// 最大停顿时间 (纳秒)
            max_pause_time_ns: u64 = 0,
            /// 平均停顿时间 (纳秒)
            avg_pause_time_ns: u64 = 0,
        };

        pub const GCMemoryStats = struct {
            /// 回收前内存使用量
            memory_before_gc: usize = 0,
            /// 回收后内存使用量
            memory_after_gc: usize = 0,
            /// 本次回收释放的内存
            memory_freed: usize = 0,
            /// 累计回收的内存
            total_memory_freed: usize = 0,
            /// 峰值内存使用量
            peak_memory_usage: usize = 0,
        };

        /// 更新平均停顿时间
        pub fn updateAveragePauseTime(self: *GCStats) void {
            if (self.total_collections > 0) {
                self.timing.avg_pause_time_ns = self.timing.total_pause_time_ns / self.total_collections;
            }
        }

        /// 记录GC开始
        pub fn recordGCStart(self: *GCStats, current_memory: usize) void {
            self.memory.memory_before_gc = current_memory;
            if (current_memory > self.memory.peak_memory_usage) {
                self.memory.peak_memory_usage = current_memory;
            }
        }

        /// 记录GC结束
        pub fn recordGCEnd(self: *GCStats, current_memory: usize, pause_time_ns: u64) void {
            self.memory.memory_after_gc = current_memory;
            self.memory.memory_freed = if (self.memory.memory_before_gc > current_memory)
                self.memory.memory_before_gc - current_memory
            else
                0;
            self.memory.total_memory_freed += self.memory.memory_freed;

            self.timing.last_pause_time_ns = pause_time_ns;
            self.timing.total_pause_time_ns += pause_time_ns;
            if (pause_time_ns > self.timing.max_pause_time_ns) {
                self.timing.max_pause_time_ns = pause_time_ns;
            }
            self.updateAveragePauseTime();
        }

        /// 生成统计报告
        pub fn generateReport(self: *const GCStats) GCReport {
            return .{
                .total_collections = self.total_collections,
                .incremental_steps = self.incremental_steps,
                .objects_marked = self.objects_marked,
                .objects_swept = self.objects_swept,
                .nursery_promotions = self.nursery_promotions,
                .last_pause_ms = @as(f64, @floatFromInt(self.timing.last_pause_time_ns)) / 1_000_000.0,
                .avg_pause_ms = @as(f64, @floatFromInt(self.timing.avg_pause_time_ns)) / 1_000_000.0,
                .max_pause_ms = @as(f64, @floatFromInt(self.timing.max_pause_time_ns)) / 1_000_000.0,
                .total_memory_freed_mb = @as(f64, @floatFromInt(self.memory.total_memory_freed)) / (1024.0 * 1024.0),
                .peak_memory_mb = @as(f64, @floatFromInt(self.memory.peak_memory_usage)) / (1024.0 * 1024.0),
            };
        }
    };

    /// GC报告结构 - 用于外部消费
    pub const GCReport = struct {
        total_collections: u64,
        incremental_steps: u64,
        objects_marked: u64,
        objects_swept: u64,
        nursery_promotions: u64,
        last_pause_ms: f64,
        avg_pause_ms: f64,
        max_pause_ms: f64,
        total_memory_freed_mb: f64,
        peak_memory_mb: f64,
    };

    pub fn init(allocator: std.mem.Allocator, memory_threshold: usize) !GarbageCollector {
        return GarbageCollector{
            .allocator = allocator,
            .memory_threshold = memory_threshold,
            .allocated_memory = 0,
            .gray_list = .{},
            .write_barrier_buffer = .{},
        };
    }

    pub fn deinit(self: *GarbageCollector) void {
        self.gray_list.deinit(self.allocator);
        self.write_barrier_buffer.deinit(self.allocator);
    }

    /// 写屏障：在指针更新时调用，用于增量标记的正确性
    pub fn writeBarrier(self: *GarbageCollector, source: *anyopaque, target: *anyopaque) void {
        if (self.incremental_state == .marking) {
            self.write_barrier_buffer.append(self.allocator, .{
                .source = source,
                .target = target,
            }) catch {};
        }
    }

    /// 增量标记步进：每次执行少量标记工作
    pub fn incrementalStep(self: *GarbageCollector, max_work: usize) bool {
        var work_done: usize = 0;
        const step_start: i64 = @intCast(std.time.nanoTimestamp());

        switch (self.incremental_state) {
            .idle => {
                self.incremental_state = .marking;
                self.mark_start_time = step_start;
                self.stats.recordGCStart(self.allocated_memory);
                return false;
            },
            .marking => {
                while (work_done < max_work and self.gray_list.items.len > 0) {
                    _ = self.gray_list.pop();
                    work_done += 1;
                    self.stats.objects_marked += 1;
                }

                // 处理写屏障缓冲区
                while (self.write_barrier_buffer.items.len > 0 and work_done < max_work) {
                    _ = self.write_barrier_buffer.pop();
                    work_done += 1;
                }

                if (self.gray_list.items.len == 0 and self.write_barrier_buffer.items.len == 0) {
                    const mark_end: i64 = @intCast(std.time.nanoTimestamp());
                    self.stats.timing.last_mark_time_ns = @intCast(mark_end - self.mark_start_time);
                    self.stats.timing.total_mark_time_ns += self.stats.timing.last_mark_time_ns;
                    self.incremental_state = .sweeping;
                    self.sweep_start_time = mark_end;
                }
                self.stats.incremental_steps += 1;
                return false;
            },
            .sweeping => {
                const sweep_end: i64 = @intCast(std.time.nanoTimestamp());
                self.stats.timing.last_sweep_time_ns = @intCast(sweep_end - self.sweep_start_time);
                self.stats.timing.total_sweep_time_ns += self.stats.timing.last_sweep_time_ns;

                const total_pause = self.stats.timing.last_mark_time_ns + self.stats.timing.last_sweep_time_ns;
                self.stats.recordGCEnd(self.allocated_memory, total_pause);

                self.incremental_state = .idle;
                self.stats.total_collections += 1;
                return true;
            },
        }
    }

    /// 年轻代分配（Bump Allocation）
    pub fn nurseryAlloc(self: *GarbageCollector, size: usize) bool {
        if (self.nursery_used + size <= self.nursery_size) {
            self.nursery_used += size;
            return true;
        }
        return false;
    }

    /// 年轻代回收
    pub fn collectNursery(self: *GarbageCollector) void {
        self.nursery_used = 0;
    }

    /// 晋升对象到老年代
    pub fn promoteToOldGen(self: *GarbageCollector) void {
        self.stats.nursery_promotions += 1;
    }

    pub fn collect(self: *GarbageCollector) u32 {
        // 执行增量收集直到完成
        while (!self.incrementalStep(100)) {}
        return @intCast(self.stats.objects_swept);
    }

    pub fn addRoot(self: *GarbageCollector, root: *anyopaque) !void {
        try self.gray_list.append(self.allocator, root);
    }

    pub fn removeRoot(self: *GarbageCollector, root: *anyopaque) void {
        for (self.gray_list.items, 0..) |item, i| {
            if (item == root) {
                _ = self.gray_list.swapRemove(i);
                return;
            }
        }
    }

    pub fn shouldCollect(self: *GarbageCollector) bool {
        return self.allocated_memory >= self.memory_threshold;
    }

    pub fn trackAllocation(self: *GarbageCollector, size: usize) void {
        self.allocated_memory += size;
    }

    pub fn trackDeallocation(self: *GarbageCollector, size: usize) void {
        if (self.allocated_memory >= size) {
            self.allocated_memory -= size;
        } else {
            self.allocated_memory = 0;
        }
    }

    /// 获取GC统计信息
    pub fn getStats(self: *GarbageCollector) GCStats {
        return self.stats;
    }

    /// 获取GC报告 (用于外部消费的格式化报告)
    pub fn getReport(self: *GarbageCollector) GCReport {
        return self.stats.generateReport();
    }
};

pub const Header = struct {
    ref_count: u32,
};

pub fn incRef(comptime T: type) fn (ptr: T) void {
    return struct {
        fn anon(ptr: T) void {
            ptr.ref_count += 1;
        }
    }.anon;
}

pub fn decRef(mm: *MemoryManager, val: Value) void {
    switch (val.getTag()) {
        .string => {
            val.getAsString().release(mm.allocator);
        },
        .array => {
            val.getAsArray().release(mm.allocator);
        },
        .object => {
            val.getAsObject().release(mm.allocator);
        },
        .struct_instance => {
            val.getAsStruct().release(mm.allocator);
        },
        .resource => {
            val.getAsResource().release(mm.allocator);
        },
        .user_function => {
            val.getAsUserFunc().release(mm.allocator);
        },
        .closure => {
            val.getAsClosure().release(mm.allocator);
        },
        .arrow_function => {
            val.getAsClosure().release(mm.allocator);
        },
        else => {},
    }
}

pub const MemoryManager = struct {
    allocator: std.mem.Allocator,
    gc: GarbageCollector,

    pub fn init(allocator: std.mem.Allocator) !MemoryManager {
        const default_threshold = 1024 * 1024; // 1MB default threshold
        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, default_threshold),
        };
    }

    pub fn initWithThreshold(allocator: std.mem.Allocator, memory_threshold: usize) !MemoryManager {
        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, memory_threshold),
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        self.gc.deinit();
    }

    pub fn allocString(self: *MemoryManager, data: []const u8) !*Box(*PHPString) {
        const php_string = try PHPString.init(self.allocator, data);
        const box = try self.allocator.create(Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_string,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPString)) + data.len);
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocArray(self: *MemoryManager) !*Box(*PHPArray) {
        const php_array = try self.allocator.create(PHPArray);
        php_array.* = PHPArray.init(self.allocator);
        const box = try self.allocator.create(Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPArray)) + @sizeOf(PHPArray));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocObject(self: *MemoryManager, class: *@import("types.zig").PHPClass) !*Box(*PHPObject) {
        const php_object = try self.allocator.create(PHPObject);
        php_object.* = try PHPObject.init(self.allocator, class);
        return self.wrapObject(php_object);
    }

    pub fn wrapObject(self: *MemoryManager, php_object: *PHPObject) !*Box(*PHPObject) {
        const box = try self.allocator.create(Box(*PHPObject));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_object,
        };
        self.gc.trackAllocation(@sizeOf(Box(*PHPObject)) + @sizeOf(PHPObject));
        return box;
    }

    pub fn wrapArray(self: *MemoryManager, php_array: *PHPArray) !*Box(*PHPArray) {
        const box = try self.allocator.create(Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };
        self.gc.trackAllocation(@sizeOf(Box(*PHPArray)) + @sizeOf(PHPArray));
        return box;
    }

    pub fn allocResource(self: *MemoryManager, resource: PHPResource) !*Box(*PHPResource) {
        const php_resource = try self.allocator.create(PHPResource);
        php_resource.* = resource;
        const box = try self.allocator.create(Box(*PHPResource));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_resource,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPResource)) + @sizeOf(PHPResource));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocUserFunction(self: *MemoryManager, function: UserFunction) !*Box(*UserFunction) {
        const user_function = try self.allocator.create(UserFunction);
        user_function.* = function;
        const box = try self.allocator.create(Box(*UserFunction));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = user_function,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*UserFunction)) + @sizeOf(UserFunction));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocClosure(self: *MemoryManager, closure: Closure) !*Box(*Closure) {
        const closure_ptr = try self.allocator.create(Closure);
        closure_ptr.* = closure;
        const box = try self.allocator.create(Box(*Closure));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = closure_ptr,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*Closure)) + @sizeOf(Closure));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn allocArrowFunction(self: *MemoryManager, arrow_function: ArrowFunction) !*Box(*ArrowFunction) {
        const arrow_function_ptr = try self.allocator.create(ArrowFunction);
        arrow_function_ptr.* = arrow_function;
        const box = try self.allocator.create(Box(*ArrowFunction));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = arrow_function_ptr,
        };

        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*ArrowFunction)) + @sizeOf(ArrowFunction));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }

        return box;
    }

    pub fn collect(self: *MemoryManager) u32 {
        return self.gc.collect();
    }

    pub fn addRoot(self: *MemoryManager, root: *anyopaque) !void {
        try self.gc.addRoot(root);
    }

    pub fn removeRoot(self: *MemoryManager, root: *anyopaque) void {
        self.gc.removeRoot(root);
    }

    pub fn forceCollect(self: *MemoryManager) u32 {
        return self.gc.collect();
    }

    pub fn getMemoryUsage(self: *MemoryManager) usize {
        return self.gc.allocated_memory;
    }

    pub fn setMemoryThreshold(self: *MemoryManager, threshold: usize) void {
        self.gc.memory_threshold = threshold;
    }
};

// Global function to manually trigger garbage collection (gc_collect_cycles equivalent)
pub fn collectCycles(mm: *MemoryManager) u32 {
    return mm.forceCollect();
}
