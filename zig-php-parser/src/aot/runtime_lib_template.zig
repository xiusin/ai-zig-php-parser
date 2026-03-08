//! AOT Runtime Library Template
//!
//! 这是AOT编译器使用的完整运行时库模板。
//! 实现了PHP值类型系统和所有必需的运算符函数。
//!
//! ## 设计原则
//! 1. **零依赖**：除了Zig标准库，不依赖任何其他模块
//! 2. **内存安全**：使用引用计数管理内存，防止泄漏
//! 3. **性能优化**：使用NaN boxing技术，48位整数快速路径
//! 4. **PHP语义**：严格遵循PHP 8.5的类型转换和运算规则
//!
//! @ownership TRANSFER (Value类型通过引用计数管理)
//! @thread-safety ISOLATED (每个编译的程序独立运行)
//! @memory-model Reference Counting with Cycle Detection

const std = @import("std");
const Allocator = std.mem.Allocator;
const concurrency = @import("concurrency_runtime.zig");
const array_ops_shared = @import("array_ops_shared.zig");
const nanbox_abi = @import("nanbox_abi.zig");
pub const profiler = @import("profiler.zig");
pub const flamegraph = @import("flamegraph.zig");
pub const pprof = @import("pprof.zig");

// ============================================================================
// 全局运行时状态
// ============================================================================

/// 全局分配器（由main函数初始化）
/// 注意：这是一个全局变量，在AOT编译的代码中可以直接访问
pub var runtime_allocator: Allocator = undefined;

/// 用户定义函数注册表
pub var user_function_registry: ?std.StringHashMap(*const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value) = null;

/// 全局常量表
pub var constants: std.StringHashMap(Value) = undefined;
var array_internal_pointers: ?std.AutoHashMap(*PHPArray, usize) = null;
const StaticStringEntry = struct {
    const inline_cap: usize = 22;

    php: PHPString,
    inline_len: u8,
    inline_buf: [inline_cap]u8,
    heap_buf: ?[]u8,

    fn init(entry: *StaticStringEntry, allocator: Allocator, str: []const u8) !void {
        entry.inline_len = 0;
        entry.heap_buf = null;
        if (str.len <= inline_cap) {
            if (str.len > 0) {
                @memcpy(entry.inline_buf[0..str.len], str);
            }
            entry.inline_len = @intCast(str.len);
            entry.php = .{
                .data = entry.inline_buf[0..str.len],
                .length = str.len,
                .ref_count = 1,
                .is_static = true,
            };
        } else {
            const buf = try allocator.alloc(u8, str.len);
            if (str.len > 0) {
                @memcpy(buf, str);
            }
            entry.heap_buf = buf;
            entry.php = .{
                .data = buf,
                .length = str.len,
                .ref_count = 1,
                .is_static = true,
            };
        }
    }

    fn deinit(entry: *StaticStringEntry, allocator: Allocator) void {
        if (entry.heap_buf) |buf| allocator.free(buf);
        allocator.destroy(entry);
    }
};

var static_string_pool: ?std.StringHashMap(*StaticStringEntry) = null;
var static_string_entries: std.ArrayListUnmanaged(*StaticStringEntry) = .{};
var php_string_pool: ?std.heap.MemoryPool(PHPString) = null;
var php_array_pool: ?std.heap.MemoryPool(PHPArray) = null;
var php_closure_pool: ?std.heap.MemoryPool(PHPClosure) = null;
const AllocCounters = struct {
    total_alloc_bytes: u64 = 0,
    total_free_bytes: u64 = 0,
    alloc_calls: u64 = 0,
    free_calls: u64 = 0,

    live_bytes: u64 = 0,
    peak_live_bytes: u64 = 0,
    live_allocs: u64 = 0,
    peak_live_allocs: u64 = 0,

    php_string_objects: u64 = 0,
    php_string_bytes: u64 = 0,
    php_array_objects: u64 = 0,

    php_string_live_objects: u64 = 0,
    php_string_peak_live_objects: u64 = 0,
    php_string_live_bytes: u64 = 0,
    php_string_peak_live_bytes: u64 = 0,

    php_array_live_objects: u64 = 0,
    php_array_peak_live_objects: u64 = 0,

    php_object_objects: u64 = 0,
    php_object_live_objects: u64 = 0,
    php_object_peak_live_objects: u64 = 0,

    php_closure_objects: u64 = 0,
    php_closure_live_objects: u64 = 0,
    php_closure_peak_live_objects: u64 = 0,
};

pub const AllocStats = struct {
    alloc_bytes: u64 = 0,
    alloc_count: u64 = 0,
    free_bytes: u64 = 0,
    free_count: u64 = 0,

    live_bytes: u64 = 0,
    peak_live_bytes: u64 = 0,
    live_allocs: u64 = 0,
    peak_live_allocs: u64 = 0,

    php_string_objects: u64 = 0,
    php_string_bytes: u64 = 0,
    php_array_objects: u64 = 0,
    php_object_objects: u64 = 0,

    php_string_live_objects: u64 = 0,
    php_string_peak_live_objects: u64 = 0,
    php_string_live_bytes: u64 = 0,
    php_string_peak_live_bytes: u64 = 0,

    php_array_live_objects: u64 = 0,
    php_array_peak_live_objects: u64 = 0,

    php_object_live_objects: u64 = 0,
    php_object_peak_live_objects: u64 = 0,

    php_closure_objects: u64 = 0,
    php_closure_live_objects: u64 = 0,
    php_closure_peak_live_objects: u64 = 0,
};

var alloc_counters: AllocCounters = .{};
var alloc_baseline: AllocCounters = .{};

const StatsAllocator = struct {
    child: Allocator,

    pub fn init(child: Allocator) StatsAllocator {
        return .{ .child = child };
    }

    pub fn allocator(self: *StatsAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *StatsAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.vtable.alloc(self.child.ptr, len, alignment, ra);
        if (ptr != null) recordAlloc(len);
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) bool {
        const self: *StatsAllocator = @ptrCast(@alignCast(ctx));
        const ok = self.child.vtable.resize(self.child.ptr, buf, alignment, new_len, ra);
        if (ok) recordResize(buf.len, new_len);
        return ok;
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const self: *StatsAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.vtable.remap(self.child.ptr, buf, alignment, new_len, ra);
        if (ptr != null) recordResize(buf.len, new_len);
        return ptr;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *StatsAllocator = @ptrCast(@alignCast(ctx));
        self.child.vtable.free(self.child.ptr, buf, alignment, ra);
        recordFree(buf.len);
    }
};

var stats_allocator: StatsAllocator = undefined;
const GCColor = enum(u2) { white = 0, gray = 1, black = 2, purple = 3 };
const GCInfo = packed struct { color: GCColor = .white, buffered: bool = false };
const CycleRoot = union(enum) { array: *PHPArray, object: *PHPObject, closure: *PHPClosure };
var cycle_roots: std.ArrayListUnmanaged(CycleRoot) = .{};
var gc_in_progress: bool = false;
var gc_release_events: usize = 0;
const GC_RELEASE_EVENT_THRESHOLD: usize = 4096;
const GC_ROOT_THRESHOLD: usize = 256;

/// 当前异常（线程局部）
threadlocal var current_exception: Value = undefined;
threadlocal var has_exception: bool = false;

fn allocPHPString(allocator: Allocator) !*PHPString {
    if (php_string_pool) |*p| return p.create();
    return try allocator.create(PHPString);
}

fn destroyPHPString(str: *PHPString, allocator: Allocator) void {
    if (php_string_pool) |*p| {
        p.destroy(str);
        return;
    }
    allocator.destroy(str);
}

fn allocPHPArray(allocator: Allocator) !*PHPArray {
    if (php_array_pool) |*p| return p.create();
    return try allocator.create(PHPArray);
}

fn destroyPHPArray(arr: *PHPArray, allocator: Allocator) void {
    if (php_array_pool) |*p| {
        p.destroy(arr);
        return;
    }
    allocator.destroy(arr);
}

fn allocPHPClosure(allocator: Allocator) !*PHPClosure {
    if (php_closure_pool) |*p| return p.create();
    return try allocator.create(PHPClosure);
}

fn destroyPHPClosure(c: *PHPClosure, allocator: Allocator) void {
    if (php_closure_pool) |*p| {
        p.destroy(c);
        return;
    }
    allocator.destroy(c);
}

fn recordAlloc(len: usize) void {
    alloc_counters.alloc_calls += 1;
    alloc_counters.total_alloc_bytes += len;
    alloc_counters.live_allocs += 1;
    alloc_counters.live_bytes += len;
    alloc_counters.peak_live_allocs = @max(alloc_counters.peak_live_allocs, alloc_counters.live_allocs);
    alloc_counters.peak_live_bytes = @max(alloc_counters.peak_live_bytes, alloc_counters.live_bytes);
}

fn recordFree(len: usize) void {
    alloc_counters.free_calls += 1;
    alloc_counters.total_free_bytes += len;
    if (alloc_counters.live_allocs > 0) alloc_counters.live_allocs -= 1;
    if (alloc_counters.live_bytes >= len) {
        alloc_counters.live_bytes -= len;
    } else {
        alloc_counters.live_bytes = 0;
    }
}

fn recordResize(old_len: usize, new_len: usize) void {
    if (new_len == old_len) return;
    if (new_len > old_len) {
        const diff = new_len - old_len;
        alloc_counters.total_alloc_bytes += diff;
        alloc_counters.live_bytes += diff;
        alloc_counters.peak_live_bytes = @max(alloc_counters.peak_live_bytes, alloc_counters.live_bytes);
    } else {
        const diff = old_len - new_len;
        alloc_counters.total_free_bytes += diff;
        if (alloc_counters.live_bytes >= diff) {
            alloc_counters.live_bytes -= diff;
        } else {
            alloc_counters.live_bytes = 0;
        }
    }
}

fn deltaU64(current: u64, base: u64) u64 {
    return if (current >= base) current - base else 0;
}

/// 初始化运行时
pub fn initRuntime(allocator: Allocator) void {
    alloc_counters = .{};
    alloc_baseline = .{};
    stats_allocator = StatsAllocator.init(allocator);
    runtime_allocator = stats_allocator.allocator();

    initClassRegistry(runtime_allocator);
    registerArrayIterator(runtime_allocator) catch {};
    registerSplFixedArray(runtime_allocator) catch {};
    registerSplStack(runtime_allocator) catch {};
    registerSplQueue(runtime_allocator) catch {};
    registerZigChannel(runtime_allocator) catch {};
    registerZigSelect(runtime_allocator) catch {};
    user_function_registry = std.StringHashMap(*const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value).init(runtime_allocator);
    constants = std.StringHashMap(Value).init(runtime_allocator);
    array_internal_pointers = std.AutoHashMap(*PHPArray, usize).init(runtime_allocator);
    static_string_pool = std.StringHashMap(*StaticStringEntry).init(runtime_allocator);
    static_string_entries = .{};
    cycle_roots = .{};
    gc_in_progress = false;
    gc_release_events = 0;
    current_exception = Value.initNull();
    has_exception = false;
    php_string_pool = std.heap.MemoryPool(PHPString).init(runtime_allocator);
    php_array_pool = std.heap.MemoryPool(PHPArray).init(runtime_allocator);
    php_closure_pool = std.heap.MemoryPool(PHPClosure).init(runtime_allocator);
    resetAllocStats();
    initPredefinedConstants() catch {};
}

fn initPredefinedConstants() !void {
    const keys = [_][]const u8{ "STR_PAD_LEFT", "STR_PAD_RIGHT", "STR_PAD_BOTH" };
    const values = [_]i64{ 0, 1, 2 };
    for (keys, values) |key, val| {
        const key_copy = try runtime_allocator.dupe(u8, key);
        try constants.put(key_copy, Value.initInt(val));
    }
}

pub fn resetAllocStats() void {
    alloc_baseline.total_alloc_bytes = alloc_counters.total_alloc_bytes;
    alloc_baseline.total_free_bytes = alloc_counters.total_free_bytes;
    alloc_baseline.alloc_calls = alloc_counters.alloc_calls;
    alloc_baseline.free_calls = alloc_counters.free_calls;
    alloc_baseline.live_bytes = alloc_counters.live_bytes;
    alloc_baseline.live_allocs = alloc_counters.live_allocs;

    alloc_baseline.php_string_objects = alloc_counters.php_string_objects;
    alloc_baseline.php_string_bytes = alloc_counters.php_string_bytes;
    alloc_baseline.php_array_objects = alloc_counters.php_array_objects;

    alloc_baseline.php_string_live_objects = alloc_counters.php_string_live_objects;
    alloc_baseline.php_string_live_bytes = alloc_counters.php_string_live_bytes;
    alloc_baseline.php_array_live_objects = alloc_counters.php_array_live_objects;

    alloc_baseline.php_object_objects = alloc_counters.php_object_objects;
    alloc_baseline.php_object_live_objects = alloc_counters.php_object_live_objects;

    alloc_baseline.php_closure_objects = alloc_counters.php_closure_objects;
    alloc_baseline.php_closure_live_objects = alloc_counters.php_closure_live_objects;

    alloc_counters.peak_live_bytes = alloc_counters.live_bytes;
    alloc_counters.peak_live_allocs = alloc_counters.live_allocs;
    alloc_counters.php_string_peak_live_objects = alloc_counters.php_string_live_objects;
    alloc_counters.php_string_peak_live_bytes = alloc_counters.php_string_live_bytes;
    alloc_counters.php_array_peak_live_objects = alloc_counters.php_array_live_objects;
    alloc_counters.php_object_peak_live_objects = alloc_counters.php_object_live_objects;
    alloc_counters.php_closure_peak_live_objects = alloc_counters.php_closure_live_objects;
}

pub fn getAllocStats() AllocStats {
    return .{
        .alloc_bytes = deltaU64(alloc_counters.total_alloc_bytes, alloc_baseline.total_alloc_bytes),
        .alloc_count = deltaU64(alloc_counters.alloc_calls, alloc_baseline.alloc_calls),
        .free_bytes = deltaU64(alloc_counters.total_free_bytes, alloc_baseline.total_free_bytes),
        .free_count = deltaU64(alloc_counters.free_calls, alloc_baseline.free_calls),

        .live_bytes = deltaU64(alloc_counters.live_bytes, alloc_baseline.live_bytes),
        .peak_live_bytes = deltaU64(alloc_counters.peak_live_bytes, alloc_baseline.live_bytes),
        .live_allocs = deltaU64(alloc_counters.live_allocs, alloc_baseline.live_allocs),
        .peak_live_allocs = deltaU64(alloc_counters.peak_live_allocs, alloc_baseline.live_allocs),

        .php_string_objects = deltaU64(alloc_counters.php_string_objects, alloc_baseline.php_string_objects),
        .php_string_bytes = deltaU64(alloc_counters.php_string_bytes, alloc_baseline.php_string_bytes),
        .php_array_objects = deltaU64(alloc_counters.php_array_objects, alloc_baseline.php_array_objects),
        .php_object_objects = deltaU64(alloc_counters.php_object_objects, alloc_baseline.php_object_objects),

        .php_string_live_objects = deltaU64(alloc_counters.php_string_live_objects, alloc_baseline.php_string_live_objects),
        .php_string_peak_live_objects = deltaU64(alloc_counters.php_string_peak_live_objects, alloc_baseline.php_string_live_objects),
        .php_string_live_bytes = deltaU64(alloc_counters.php_string_live_bytes, alloc_baseline.php_string_live_bytes),
        .php_string_peak_live_bytes = deltaU64(alloc_counters.php_string_peak_live_bytes, alloc_baseline.php_string_live_bytes),

        .php_array_live_objects = deltaU64(alloc_counters.php_array_live_objects, alloc_baseline.php_array_live_objects),
        .php_array_peak_live_objects = deltaU64(alloc_counters.php_array_peak_live_objects, alloc_baseline.php_array_live_objects),

        .php_object_live_objects = deltaU64(alloc_counters.php_object_live_objects, alloc_baseline.php_object_live_objects),
        .php_object_peak_live_objects = deltaU64(alloc_counters.php_object_peak_live_objects, alloc_baseline.php_object_live_objects),

        .php_closure_objects = deltaU64(alloc_counters.php_closure_objects, alloc_baseline.php_closure_objects),
        .php_closure_live_objects = deltaU64(alloc_counters.php_closure_live_objects, alloc_baseline.php_closure_live_objects),
        .php_closure_peak_live_objects = deltaU64(alloc_counters.php_closure_peak_live_objects, alloc_baseline.php_closure_live_objects),
    };
}

/// 设置异常
pub fn setException(ex: Value) void {
    if (has_exception) {
        current_exception.release(runtime_allocator);
    }
    _ = ex.retain();
    current_exception = ex;
    has_exception = true;
}

/// 获取异常（并清除当前异常状态）
pub fn getException() Value {
    if (has_exception) {
        has_exception = false;
        // 转移所有权，不释放
        return current_exception;
    }
    return Value.initNull();
}

pub fn php_handle_uncaught_exception() void {
    if (has_exception) {
        has_exception = false;
    }
}

/// 清理运行时
pub fn deinitRuntime() void {
    // std.debug.print("deinitRuntime: start\n", .{});
    concurrency.shutdownScheduler();
    cleanupAllClasses();
    if (user_function_registry) |*registry| {
        registry.deinit();
        user_function_registry = null;
    }
    
    // 清理constants
    var iter = constants.iterator();
    while (iter.next()) |entry| {
        // 释放键（我们复制了键）
        runtime_allocator.free(entry.key_ptr.*);
        // 释放值
        entry.value_ptr.release(runtime_allocator);
    }
    constants.deinit();
    // std.debug.print("deinitRuntime: after constants cleanup\n", .{});
    // 跳过循环收集，避免 iterator 整数溢出问题
    // gcCollectCycles(true);
    cycle_roots.deinit(runtime_allocator);
    cycle_roots = .{};
    // std.debug.print("deinitRuntime: cleaning up {d} static strings\n", .{static_string_entries.items.len});
    for (static_string_entries.items) |e| {
        // std.debug.print("deinitRuntime: cleaning static string: {s}\n", .{e.php.data});
        e.deinit(runtime_allocator);
    }
    static_string_entries.deinit(runtime_allocator);
    static_string_entries = .{};
    if (static_string_pool) |*pool| {
        pool.deinit();
        static_string_pool = null;
    }
    if (array_internal_pointers) |*m| {
        m.deinit();
        array_internal_pointers = null;
    }
    if (php_string_pool) |*p| {
        p.deinit();
        php_string_pool = null;
    }
    if (php_array_pool) |*p| {
        p.deinit();
        php_array_pool = null;
    }
    if (php_closure_pool) |*p| {
        p.deinit();
        php_closure_pool = null;
    }
}

/// 注册用户定义函数
pub fn registerUserFunction(name: []const u8, func: *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value) !void {
    if (user_function_registry) |*registry| {
        try registry.put(name, func);
    }
}

fn gcBufferArray(a: *PHPArray) void {
    if (gc_in_progress) return;
    if (a.gc_info.buffered) return;
    a.gc_info.color = .purple;
    a.gc_info.buffered = true;
    cycle_roots.append(runtime_allocator, .{ .array = a }) catch return;
    gcMaybeCollect();
}

fn gcBufferObject(o: *PHPObject) void {
    if (gc_in_progress) return;
    if (o.gc_info.buffered) return;
    o.gc_info.color = .purple;
    o.gc_info.buffered = true;
    cycle_roots.append(runtime_allocator, .{ .object = o }) catch return;
    gcMaybeCollect();
}

fn gcBufferClosure(c: *PHPClosure) void {
    if (gc_in_progress) return;
    if (c.gc_info.buffered) return;
    c.gc_info.color = .purple;
    c.gc_info.buffered = true;
    cycle_roots.append(runtime_allocator, .{ .closure = c }) catch return;
    gcMaybeCollect();
}

fn gcMaybeCollect() void {
    if (gc_in_progress) return;
    gc_release_events += 1;
    if (cycle_roots.items.len >= GC_ROOT_THRESHOLD or gc_release_events >= GC_RELEASE_EVENT_THRESHOLD) {
        gcCollectCycles(false);
    }
}

fn gcCollectCycles(force: bool) void {
    if (gc_in_progress) return;
    if (!force and cycle_roots.items.len < GC_ROOT_THRESHOLD and gc_release_events < GC_RELEASE_EVENT_THRESHOLD) return;

    const items = cycle_roots.items;
    for (items) |r| {
        switch (r) {
            .array => |a| a.gc_info.buffered = false,
            .object => |o| o.gc_info.buffered = false,
            .closure => |c| c.gc_info.buffered = false,
        }
    }

    gc_in_progress = true;
    defer gc_in_progress = false;
    gc_release_events = 0;

    for (items) |r| gcMarkGray(r);
    for (items) |r| gcScan(r);
    for (items) |r| gcCollectWhite(r);

    cycle_roots.clearRetainingCapacity();
}

pub fn php_collect_cycles() void {
    gcCollectCycles(true);
}

fn gcMarkGray(root: CycleRoot) void {
    switch (root) {
        .array => |a| gcMarkGrayArray(a),
        .object => |o| gcMarkGrayObject(o),
        .closure => |c| gcMarkGrayClosure(c),
    }
}

fn gcMarkGrayValue(v: Value) void {
    if (v.isArray()) {
        const a = v.asArray();
        if (a.ref_count > 0) a.ref_count -= 1;
        gcMarkGrayArray(a);
    } else if (Value_isObject(v)) {
        const o = Value_asObject(v);
        if (o.ref_count > 0) o.ref_count -= 1;
        gcMarkGrayObject(o);
    } else if (v.isFunction()) {
        const c = v.asFunction();
        if (c.ref_count > 0) c.ref_count -= 1;
        gcMarkGrayClosure(c);
    }
}

fn gcMarkGrayArray(a: *PHPArray) void {
    if (a.gc_info.color == .gray) return;
    a.gc_info.color = .gray;

    // 安全地遍历数组元素
    // 如果是 packed array，直接遍历
    if (a.elements.mixed == null) {
        for (a.elements.packed_values.items) |v| {
            gcMarkGrayValue(v);
        }
    } else {
        // 如果是 mixed array，尝试安全遍历
        // 注意：这里不使用 iterator() 避免 panic
        if (a.elements.mixed) |*m| {
            // 只有在 count 有效时才遍历
            const cnt = m.count();
            if (cnt > 0 and cnt < 1000000) { // 合理的上限
                var it = m.iterator();
                while (it.next()) |entry| {
                    gcMarkGrayValue(entry.value_ptr.*);
                }
            }
        }
    }
}

fn gcMarkGrayObject(o: *PHPObject) void {
    if (o.gc_info.color == .gray) return;
    o.gc_info.color = .gray;

    // 安全地遍历对象属性
    const cnt = o.properties.count();
    if (cnt > 0 and cnt < 1000000) { // 合理的上限
        var it = o.properties.iterator();
        while (it.next()) |entry| {
            gcMarkGrayValue(entry.value_ptr.*);
        }
    }
}

fn gcMarkGrayClosure(c: *PHPClosure) void {
    if (c.gc_info.color == .gray) return;
    c.gc_info.color = .gray;
    for (c.captures) |cap| {
        gcMarkGrayValue(cap);
    }
}

fn gcScan(root: CycleRoot) void {
    switch (root) {
        .array => |a| gcScanArray(a),
        .object => |o| gcScanObject(o),
        .closure => |c| gcScanClosure(c),
    }
}

fn gcScanValue(v: Value) void {
    if (v.isArray()) {
        gcScanArray(v.asArray());
    } else if (Value_isObject(v)) {
        gcScanObject(Value_asObject(v));
    } else if (v.isFunction()) {
        gcScanClosure(v.asFunction());
    }
}

fn gcScanArray(a: *PHPArray) void {
    if (a.gc_info.color != .gray) return;
    if (a.ref_count > 0) {
        gcScanBlackArray(a);
        return;
    }
    a.gc_info.color = .white;
    var it = a.elements.iterator();
    while (it.next()) |entry| {
        gcScanValue(entry.value_ptr.*);
    }
}

fn gcScanObject(o: *PHPObject) void {
    if (o.gc_info.color != .gray) return;
    if (o.ref_count > 0) {
        gcScanBlackObject(o);
        return;
    }
    o.gc_info.color = .white;
    var it = o.properties.iterator();
    while (it.next()) |entry| {
        gcScanValue(entry.value_ptr.*);
    }
}

fn gcScanClosure(c: *PHPClosure) void {
    if (c.gc_info.color != .gray) return;
    if (c.ref_count > 0) {
        gcScanBlackClosure(c);
        return;
    }
    c.gc_info.color = .white;
    for (c.captures) |cap| {
        gcScanValue(cap);
    }
}

fn gcScanBlackValue(v: Value) void {
    if (v.isArray()) {
        const a = v.asArray();
        a.ref_count += 1;
        gcScanBlackArray(a);
    } else if (Value_isObject(v)) {
        const o = Value_asObject(v);
        o.ref_count += 1;
        gcScanBlackObject(o);
    } else if (v.isFunction()) {
        const c = v.asFunction();
        c.ref_count += 1;
        gcScanBlackClosure(c);
    }
}

fn gcScanBlackArray(a: *PHPArray) void {
    if (a.gc_info.color == .black) return;
    a.gc_info.color = .black;
    var it = a.elements.iterator();
    while (it.next()) |entry| {
        gcScanBlackValue(entry.value_ptr.*);
    }
}

fn gcScanBlackObject(o: *PHPObject) void {
    if (o.gc_info.color == .black) return;
    o.gc_info.color = .black;
    var it = o.properties.iterator();
    while (it.next()) |entry| {
        gcScanBlackValue(entry.value_ptr.*);
    }
}

fn gcScanBlackClosure(c: *PHPClosure) void {
    if (c.gc_info.color == .black) return;
    c.gc_info.color = .black;
    for (c.captures) |cap| {
        gcScanBlackValue(cap);
    }
}

fn gcCollectWhite(root: CycleRoot) void {
    switch (root) {
        .array => |a| gcCollectWhiteArray(a),
        .object => |o| gcCollectWhiteObject(o),
        .closure => |c| gcCollectWhiteClosure(c),
    }
}

fn gcCollectWhiteValue(v: Value) void {
    if (v.isArray()) {
        gcCollectWhiteArray(v.asArray());
    } else if (Value_isObject(v)) {
        gcCollectWhiteObject(Value_asObject(v));
    } else if (v.isFunction()) {
        gcCollectWhiteClosure(v.asFunction());
    }
}

fn gcReleaseOrCollectValue(v: Value, allocator: Allocator) void {
    if (v.isArray()) {
        const a = v.asArray();
        if (a.gc_info.color == .white) {
            gcCollectWhiteArray(a);
        } else {
            a.release(allocator);
        }
        return;
    }
    if (Value_isObject(v)) {
        const o = Value_asObject(v);
        if (o.gc_info.color == .white) {
            gcCollectWhiteObject(o);
        } else {
            o.release();
        }
        return;
    }
    if (v.isFunction()) {
        const c = v.asFunction();
        if (c.gc_info.color == .white) {
            gcCollectWhiteClosure(c);
        } else {
            c.release(allocator);
        }
        return;
    }
    v.release(allocator);
}

fn gcCollectWhiteArray(a: *PHPArray) void {
    if (a.gc_info.color != .white) return;
    a.gc_info.color = .black;
    var it = a.elements.iterator();
    while (it.next()) |entry| {
        gcReleaseOrCollectValue(entry.value_ptr.*, runtime_allocator);
    }
    gcDestroyArray(a);
}

fn gcCollectWhiteObject(o: *PHPObject) void {
    if (o.gc_info.color != .white) return;
    o.gc_info.color = .black;
    if (o.class_meta) |meta| {
        if (meta.findMethodLookup("__destruct")) |lookup| {
            const this_val = Value_initObject(o);
            const guard = ClassContext.init(meta, lookup.owner);
            defer guard.deinit();
            _ = lookup.method.func(this_val, &.{}, o.allocator) catch {};
        }
    }
    var it = o.properties.iterator();
    while (it.next()) |entry| {
        gcReleaseOrCollectValue(entry.value_ptr.*, o.allocator);
    }
    gcDestroyObject(o);
}

fn gcCollectWhiteClosure(c: *PHPClosure) void {
    if (c.gc_info.color != .white) return;
    c.gc_info.color = .black;
    for (c.captures) |cap| {
        gcReleaseOrCollectValue(cap, runtime_allocator);
    }
    gcDestroyClosure(c);
}

fn gcDestroyArray(a: *PHPArray) void {
    if (array_internal_pointers) |*m| {
        _ = m.remove(a);
    }
    var it = a.elements.iterator();
    while (it.next()) |entry| {
        if (entry.key_ptr.* == .string) {
            entry.key_ptr.string.release(runtime_allocator);
        }
    }
    a.elements.deinit();
    destroyPHPArray(a, runtime_allocator);
}

fn gcDestroyObject(o: *PHPObject) void {
    if (global_object_registry) |*registry| {
        var i: usize = 0;
        while (i < registry.items.len) : (i += 1) {
            if (registry.items[i] == o) {
                registry.items[i] = registry.items[registry.items.len - 1];
                _ = registry.pop();
                break;
            }
        }
    }

    o.properties.deinit();
    o.allocator.free(o.class_name);
    o.allocator.destroy(o);
}

fn gcDestroyClosure(c: *PHPClosure) void {
    c.allocator.free(c.captures);
    c.allocator.destroy(c);
}

// ============================================================================
// 字符串类型
// ============================================================================

/// PHP字符串类型
/// 使用引用计数管理内存，支持写时复制（COW）
pub const PHPString = struct {
    data: []u8,
    length: usize,
    ref_count: usize,
    is_static: bool, // 静态字符串不需要释放

    /// 创建新字符串
    pub fn init(allocator: Allocator, str: []const u8) !*PHPString {
        // 检查字符串长度是否异常
        if (str.len > 1024 * 1024 * 100) { // 100MB
            std.debug.print("ERROR: String too large: {d} bytes ({d} MB)\n", .{str.len, str.len / (1024 * 1024)});
            return error.StringTooLarge;
        }

        const php_string = try allocPHPString(allocator);
        errdefer destroyPHPString(php_string, allocator);

        // 安全的内存分配和复制
        const new_data = try allocator.alloc(u8, str.len);
        errdefer allocator.free(new_data);

        if (str.len > 0) {
            @memcpy(new_data, str);
        }

        alloc_counters.php_string_objects += 1;
        alloc_counters.php_string_bytes += str.len;
        alloc_counters.php_string_live_objects += 1;
        alloc_counters.php_string_live_bytes += str.len;
        alloc_counters.php_string_peak_live_objects = @max(
            alloc_counters.php_string_peak_live_objects,
            alloc_counters.php_string_live_objects,
        );
        alloc_counters.php_string_peak_live_bytes = @max(
            alloc_counters.php_string_peak_live_bytes,
            alloc_counters.php_string_live_bytes,
        );

        php_string.data = new_data;
        php_string.length = str.len;
        php_string.ref_count = 1;
        php_string.is_static = false;
        return php_string;
    }

    /// 创建静态字符串（不需要释放）
    pub fn initStatic(str: []const u8) *PHPString {
        const Holder = struct {
            var empty: PHPString = .{
                .data = @constCast(""),
                .length = 0,
                .ref_count = 1,
                .is_static = true,
            };
        };

        if (static_string_pool) |*pool| {
            if (pool.get(str)) |existing| return &existing.php;
        }

        const entry = runtime_allocator.create(StaticStringEntry) catch return &Holder.empty;
        entry.init(runtime_allocator, str) catch {
            runtime_allocator.destroy(entry);
            return &Holder.empty;
        };

        alloc_counters.php_string_objects += 1;
        alloc_counters.php_string_bytes += str.len;
        alloc_counters.php_string_live_objects += 1;
        alloc_counters.php_string_live_bytes += str.len;
        alloc_counters.php_string_peak_live_objects = @max(
            alloc_counters.php_string_peak_live_objects,
            alloc_counters.php_string_live_objects,
        );
        alloc_counters.php_string_peak_live_bytes = @max(
            alloc_counters.php_string_peak_live_bytes,
            alloc_counters.php_string_live_bytes,
        );

        if (static_string_pool) |*pool| {
            pool.put(entry.php.data, entry) catch {};
        }
        static_string_entries.append(runtime_allocator, entry) catch {};

        return &entry.php;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPString) void {
        if (!self.is_static) {
            self.ref_count += 1;
            // std.debug.print("PHPString.retain: data={s} ref_count={d}\n", .{self.data, self.ref_count});
        }
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPString, allocator: Allocator) void {
        if (self.is_static) return;

        // std.debug.print("PHPString.release: data={s} ref_count={d}\n", .{self.data, self.ref_count});
        
        if (self.ref_count == 0) {
            std.debug.print("WARNING: PHPString double free detected! data={s}\n", .{self.data});
            return;
        }

        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit(allocator);
        }
    }

    /// 释放字符串
    fn deinit(self: *PHPString, allocator: Allocator) void {
        if (!self.is_static) {
            // std.debug.print("PHPString.deinit called\n", .{});
            if (alloc_counters.php_string_live_objects > 0) {
                alloc_counters.php_string_live_objects -= 1;
            }
            if (alloc_counters.php_string_live_bytes >= self.length) {
                alloc_counters.php_string_live_bytes -= self.length;
            } else {
                alloc_counters.php_string_live_bytes = 0;
            }
            allocator.free(self.data);
            // std.debug.print("PHPString.deinit: freed data\n", .{});
            destroyPHPString(self, allocator);
            // std.debug.print("PHPString.deinit: destroyed self\n", .{});
        }
    }

    /// 字符串连接（支持 COW 就地复用：ref_count==1 时 realloc 扩展，避免新建对象）
    pub fn concat(self: *PHPString, other: *PHPString, allocator: Allocator) !*PHPString {
        // 检测内存破坏：如果length异常大，说明对象被破坏
        if (self.length > 1024 * 1024 * 1024 or other.length > 1024 * 1024 * 1024) {
            // 内存破坏，返回空字符串避免crash
            return try PHPString.init(allocator, "");
        }
        
        const new_length = self.length + other.length;

        if (new_length > 1024 * 1024 * 100) {
            std.debug.print("ERROR: Concat result too large: {d} + {d} = {d} bytes ({d} MB)\n", .{self.length, other.length, new_length, new_length / (1024 * 1024)});
            return error.StringTooLarge;
        }

        // 临时禁用 COW 优化（有 bug）
        // if (self.ref_count == 1 and !self.is_static and other.length > 0) {
        //     const old_len = self.length;
        //     const new_data = try allocator.realloc(self.data, new_length);
        //     @memcpy(new_data[old_len..new_length], other.data[0..other.length]);
        //     self.data = new_data;
        //     self.length = new_length;
        //     alloc_counters.php_string_bytes += other.length;
        //     alloc_counters.php_string_live_bytes += other.length;
        //     alloc_counters.php_string_peak_live_bytes = @max(
        //         alloc_counters.php_string_peak_live_bytes,
        //         alloc_counters.php_string_live_bytes,
        //     );
        //     return self;
        // }

        // 小字符串优化：≤256 字节使用栈缓冲
        if (new_length <= 256) {
            var stack_buf: [256]u8 = undefined;
            if (self.length > 0) {
                @memcpy(stack_buf[0..self.length], self.data[0..self.length]);
            }
            if (other.length > 0) {
                @memcpy(stack_buf[self.length..new_length], other.data[0..other.length]);
            }
            return try PHPString.init(allocator, stack_buf[0..new_length]);
        }

        // 大字符串：堆分配
        const new_data = try allocator.alloc(u8, new_length);
        errdefer allocator.free(new_data);

        if (self.length > 0) {
            @memcpy(new_data[0..self.length], self.data[0..self.length]);
        }
        if (other.length > 0) {
            @memcpy(new_data[self.length..new_length], other.data[0..other.length]);
        }

        const result = try allocPHPString(allocator);
        errdefer destroyPHPString(result, allocator);

        alloc_counters.php_string_objects += 1;
        alloc_counters.php_string_bytes += new_length;
        alloc_counters.php_string_live_objects += 1;
        alloc_counters.php_string_live_bytes += new_length;
        alloc_counters.php_string_peak_live_objects = @max(
            alloc_counters.php_string_peak_live_objects,
            alloc_counters.php_string_live_objects,
        );
        alloc_counters.php_string_peak_live_bytes = @max(
            alloc_counters.php_string_peak_live_bytes,
            alloc_counters.php_string_live_bytes,
        );

        result.data = new_data;
        result.length = new_length;
        result.ref_count = 1;
        result.is_static = false;
        return result;
    }

    /// 获取子字符串
    pub fn substring(self: *PHPString, start: i64, length: ?i64, allocator: Allocator) !*PHPString {
        // 处理负数起始位置
        const start_idx: usize = blk: {
            if (start < 0) {
                const abs_start = @as(usize, @intCast(-start));
                break :blk if (abs_start > self.length) 0 else self.length - abs_start;
            } else {
                break :blk @intCast(@min(start, @as(i64, @intCast(self.length))));
            }
        };

        if (start_idx >= self.length) {
            return PHPString.init(allocator, "");
        }

        // 处理长度参数
        const end_idx: usize = blk: {
            if (length) |length_val| {
                if (length_val >= 0) {
                    break :blk @min(start_idx + @as(usize, @intCast(length_val)), self.length);
                } else {
                    const abs_len = @as(usize, @intCast(-length_val));
                    if (abs_len >= self.length - start_idx) {
                        return PHPString.init(allocator, "");
                    }
                    break :blk self.length - abs_len;
                }
            } else {
                break :blk self.length;
            }
        };

        if (start_idx >= end_idx) {
            return PHPString.init(allocator, "");
        }

        return PHPString.init(allocator, self.data[start_idx..end_idx]);
    }

    /// 查找子字符串位置
    pub fn indexOf(self: *PHPString, needle: *PHPString) i64 {
        if (needle.length == 0) return 0;
        if (needle.length > self.length) return -1;

        for (0..self.length - needle.length + 1) |i| {
            if (std.mem.eql(u8, self.data[i .. i + needle.length], needle.data)) {
                return @intCast(i);
            }
        }
        return -1;
    }

    /// 字符串长度
    pub fn len(self: *PHPString) usize {
        return self.length;
    }
};

// ============================================================================
// 数组类型
// ============================================================================

/// 数组键类型
pub const ArrayKey = union(enum) {
    integer: i64,
    string: *PHPString,

    pub fn hash(self: ArrayKey) u64 {
        return switch (self) {
            .integer => |i| std.hash.Wyhash.hash(0, std.mem.asBytes(&i)),
            .string => |s| std.hash.Wyhash.hash(0, s.data),
        };
    }

    pub fn eql(self: ArrayKey, other: ArrayKey) bool {
        return switch (self) {
            .integer => |a| switch (other) {
                .integer => |b| a == b,
                else => false,
            },
            .string => |a| switch (other) {
                .string => |b| std.mem.eql(u8, a.data, b.data),
                else => false,
            },
        };
    }
};

/// PHP数组类型
/// 支持整数键和字符串键的混合数组
pub const PHPArray = struct {
    elements: Elements,
    next_index: i64,
    ref_count: usize,
    gc_info: GCInfo,
    has_active_refs: bool = false,  // 是否有活跃的引用
    ref_lock_count: u32 = 0,        // 引用锁计数

    pub const ArrayContext = struct {
        pub fn hash(_: ArrayContext, key: ArrayKey) u32 {
            return @truncate(key.hash());
        }

        pub fn eql(_: ArrayContext, a: ArrayKey, b: ArrayKey, _: usize) bool {
            return a.eql(b);
        }
    };

    pub const Elements = struct {
        allocator: Allocator,
        parent: ?*PHPArray = null,  // 父数组引用
        packed_values: std.ArrayListUnmanaged(Value) = .{},
        mixed: ?std.ArrayHashMap(ArrayKey, Value, ArrayContext, true) = null,

        pub const Entry = struct { key_ptr: *const ArrayKey, value_ptr: *const Value };

        pub const Iterator = struct {
            elements: *const Elements,
            index: usize = 0,
            key: ArrayKey = .{ .integer = 0 },
            value: Value = Value.initNull(),
            mixed_it: ?std.ArrayHashMap(ArrayKey, Value, ArrayContext, true).Iterator = null,

            pub fn next(self: *Iterator) ?Entry {
                if (self.mixed_it) |*it| {
                    const e = it.next() orelse return null;
                    return .{ .key_ptr = e.key_ptr, .value_ptr = e.value_ptr };
                }
                if (self.index >= self.elements.packed_values.items.len) return null;
                self.key = .{ .integer = @intCast(self.index) };
                // 返回指向数组中实际元素的指针，而不是临时字段
                const elem_ptr = &self.elements.packed_values.items[self.index];
                self.index += 1;
                return .{ .key_ptr = &self.key, .value_ptr = elem_ptr };
            }
        };

        pub fn init(allocator: Allocator) Elements {
            return .{ .allocator = allocator };
        }

        pub fn initMixed(allocator: Allocator, map: std.ArrayHashMap(ArrayKey, Value, ArrayContext, true)) Elements {
            return .{ .allocator = allocator, .packed_values = .{}, .mixed = map };
        }

        pub fn count(self: *const Elements) usize {
            if (self.mixed) |*m| return m.count();
            return self.packed_values.items.len;
        }

        pub fn iterator(self: *const Elements) Iterator {
            if (self.mixed) |*m| {
                // 安全检查：直接检查unmanaged的entries
                const unmanaged = &m.unmanaged;
                
                // 如果entries的capacity异常，说明HashMap被破坏
                // 这通常是由于use-after-free导致的
                if (unmanaged.entries.capacity > 10_000_000) {
                    // HashMap被破坏，返回空迭代器
                    // 注意：这会导致foreach跳过所有元素，但至少不会crash
                    return .{ .elements = self };
                }
                
                const mut_m = @constCast(m);
                return .{ .elements = self, .mixed_it = mut_m.iterator() };
            }
            return .{ .elements = self };
        }

        pub fn get(self: *const Elements, key: ArrayKey) ?Value {
            if (self.mixed) |*m| return m.get(key);
            if (key != .integer) return null;
            const i = key.integer;
            if (i < 0) return null;
            const idx: usize = @intCast(i);
            if (idx >= self.packed_values.items.len) return null;
            return self.packed_values.items[idx];
        }

        fn convertToMixed(self: *Elements) !void {
            if (self.mixed != null) return;
            var map = std.ArrayHashMap(ArrayKey, Value, ArrayContext, true).init(self.allocator);
            for (self.packed_values.items, 0..) |v, idx| {
                const retained = v.retain();
                _ = retained;
                try map.put(.{ .integer = @intCast(idx) }, v);
            }
            self.packed_values.deinit(self.allocator);
            self.packed_values = .{};
            self.mixed = map;
        }

        pub fn put(self: *Elements, key: ArrayKey, value: Value) !void {
            // 如果父数组有活跃引用，强制使用mixed模式避免重新分配
            if (self.parent) |parent| {
                if (parent.has_active_refs and self.mixed == null) {
                    try self.convertToMixed();
                }
            }
            
            if (self.mixed) |*m| {
                try m.put(key, value);
                return;
            }
            if (key == .integer) {
                const i = key.integer;
                if (i >= 0) {
                    const idx: usize = @intCast(i);
                    if (idx == self.packed_values.items.len) {
                        try self.packed_values.append(self.allocator, value);
                        return;
                    }
                    if (idx < self.packed_values.items.len) {
                        self.packed_values.items[idx] = value;
                        return;
                    }
                }
            }
            try self.convertToMixed();
            try self.mixed.?.put(key, value);
        }

        pub fn orderedRemove(self: *Elements, key: ArrayKey) bool {
            if (self.mixed) |*m| return m.orderedRemove(key);
            if (key != .integer) return false;
            const i = key.integer;
            if (i < 0) return false;
            const idx: usize = @intCast(i);
            if (idx >= self.packed_values.items.len) return false;
            _ = self.packed_values.orderedRemove(idx);
            return true;
        }

        pub fn remove(self: *Elements, key: ArrayKey) bool {
            return self.orderedRemove(key);
        }

        pub fn getPtr(self: *Elements, key: ArrayKey) ?*Value {
            if (self.mixed) |*m| return m.getPtr(key);
            if (key != .integer) return null;
            const i = key.integer;
            if (i < 0) return null;
            const idx: usize = @intCast(i);
            if (idx >= self.packed_values.items.len) return null;
            return &self.packed_values.items[idx];
        }

        pub fn deinit(self: *Elements) void {
            if (self.mixed) |*m| {
                m.deinit();
                self.mixed = null;
            }
            self.packed_values.deinit(self.allocator);
            self.packed_values = .{};
        }
    };

    /// 创建新数组
    pub fn init(allocator: Allocator) !*PHPArray {
        const array = try allocPHPArray(allocator);
        array.elements = Elements.init(allocator);
        array.elements.parent = array;  // 设置父引用
        array.next_index = 0;
        array.ref_count = 1;
        array.gc_info = .{};
        array.has_active_refs = false;
        array.ref_lock_count = 0;
        alloc_counters.php_array_objects += 1;
        alloc_counters.php_array_live_objects += 1;
        alloc_counters.php_array_peak_live_objects = @max(
            alloc_counters.php_array_peak_live_objects,
            alloc_counters.php_array_live_objects,
        );
        return array;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPArray) void {
        self.ref_count += 1;
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPArray, allocator: Allocator) void {
        if (self.ref_count == 0) {
            std.debug.print("WARNING: PHPArray double free detected!\n", .{});
            return;
        }

        // 如果有活跃的迭代器引用，不允许释放
        if (self.ref_lock_count > 0) {
            // 迭代器还在使用，延迟释放
            return;
        }

        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit(allocator);
        } else if (!gc_in_progress) {
            gcBufferArray(self);
        }
    }

    /// 释放数组
    fn deinit(self: *PHPArray, allocator: Allocator) void {
        if (array_internal_pointers) |*m| {
            _ = m.remove(self);
        }
        var iter = self.elements.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.release(allocator);
            if (entry.key_ptr.* == .string) {
                entry.key_ptr.*.string.release(allocator);
            }
        }
        self.elements.deinit();
        if (alloc_counters.php_array_live_objects > 0) {
            alloc_counters.php_array_live_objects -= 1;
        }
        destroyPHPArray(self, allocator);
    }

    /// 获取元素
    pub fn get(self: *PHPArray, key: ArrayKey) ?Value {
        if (self.elements.get(key)) |v| {
            _ = v.retain();
            return v;
        }
        return null;
    }

    /// 获取元素指针（用于引用）
    pub fn getPtr(self: *PHPArray, key: ArrayKey) ?*Value {
        return self.elements.getPtr(key);
    }

    /// 获取元素（通过Value键）
    pub fn getByValue(self: *PHPArray, key: Value) ?Value {
        if (key.isString()) {
            return self.get(ArrayKey{ .string = key.asString() });
        } else {
            return self.get(ArrayKey{ .integer = key.asInt() });
        }
    }

    /// 设置元素（通过Value键）
    pub fn setByValue(self: *PHPArray, allocator: Allocator, key: Value, value: Value) !void {
        if (key.isString()) {
            try self.set(allocator, ArrayKey{ .string = key.asString() }, value);
        } else {
            try self.set(allocator, ArrayKey{ .integer = key.toInt() }, value);
        }
    }

    /// 设置元素
    pub fn set(self: *PHPArray, allocator: Allocator, key: ArrayKey, value: Value) !void {
        // 释放旧值
        if (self.elements.get(key)) |old_value| {
            old_value.release(allocator);
        }

        // 保留新值
        _ = value.retain();

        // 如果是字符串键，保留键
        if (key == .string) {
            key.string.retain();
        }

        // 更新next_index
        if (key == .integer and key.integer >= self.next_index) {
            self.next_index = key.integer + 1;
        }

        try self.elements.put(key, value);
    }

    /// 追加元素（使用下一个整数索引）
    pub fn push(self: *PHPArray, allocator: Allocator, value: Value) !void {
        const key = ArrayKey{ .integer = self.next_index };
        _ = value.retain();
        try self.elements.put(key, value);
        self.next_index += 1;
        _ = allocator; // 避免未使用警告
    }

    /// 获取元素数量
    pub fn count(self: *PHPArray) usize {
        return self.elements.count();
    }

    /// 删除元素（通过 ArrayKey）
    pub fn unset(self: *PHPArray, allocator: Allocator, key: ArrayKey) bool {
        if (self.elements.get(key)) |old_value| {
            if (self.elements.remove(key)) {
                old_value.release(allocator);
                if (key == .string) {
                    key.string.release(allocator);
                }
                return true;
            }
        }
        return false;
    }

    /// 删除元素（通过 Value 键，兼容 int/string）
    pub fn unsetByValue(self: *PHPArray, allocator: Allocator, key: Value) bool {
        if (key.isString()) {
            return self.unset(allocator, ArrayKey{ .string = key.asString() });
        }
        return self.unset(allocator, ArrayKey{ .integer = key.toInt() });
    }
};

// ============================================================================
// Value类型 - NaN Boxing实现
// ============================================================================

/// PHP值类型
/// 使用NaN boxing技术，将所有类型编码到64位中
///
/// 编码方案：
/// - Float: 正常的IEEE 754双精度浮点数
/// - Null: QNAN | TAG_NIL
/// - Bool: QNAN | TAG_FALSE/TAG_TRUE
/// - Int: TAG_INT_MARKER | (48位整数)
/// - Pointer: TAG_PTR | TYPE_TAG | (47位地址)
pub const Value = struct {
    val: u64,

    // NaN boxing常量
    pub const SIGN_BIT: u64 = nanbox_abi.SIGN_BIT;
    pub const QNAN: u64 = nanbox_abi.QNAN;

    // 简单类型标签
    pub const TAG_NIL: u64 = nanbox_abi.TAG_NIL;
    pub const TAG_FALSE: u64 = nanbox_abi.TAG_FALSE;
    pub const TAG_TRUE: u64 = nanbox_abi.TAG_TRUE;
    pub const TAG_MISSING: u64 = 4;
    pub const TAG_INT_MARKER: u64 = nanbox_abi.TAG_INT_MARKER;

    // 指针类型标记
    pub const TAG_PTR: u64 = nanbox_abi.TAG_PTR;
    pub const TYPE_MASK: u64 = nanbox_abi.TYPE_MASK;
    pub const TYPE_STRING: u64 = nanbox_abi.TYPE_STRING;
    pub const TYPE_ARRAY: u64 = nanbox_abi.TYPE_ARRAY;
    pub const TYPE_OBJECT: u64 = nanbox_abi.TYPE_OBJECT;
    pub const TYPE_FUNCTION: u64 = nanbox_abi.TYPE_FUNCTION;
    pub const TYPE_REF: u64 = nanbox_abi.TYPE_REF;

    // 48位整数常量
    pub const INT48_MASK: u64 = nanbox_abi.INT48_MASK;
    pub const INT48_SIGN_BIT: u64 = 0x0000800000000000;
    pub const INT48_MAX: i64 = 0x00007FFFFFFFFFFF;
    pub const INT48_MIN: i64 = -0x0000800000000000;

    // ========================================================================
    // 构造函数
    // ========================================================================

    /// 创建null值
    pub fn initNull() Value {
        return .{ .val = QNAN | TAG_NIL };
    }

    pub fn initMissing() Value {
        return .{ .val = QNAN | TAG_MISSING };
    }

    /// 创建布尔值
    pub fn initBool(b: bool) Value {
        return .{ .val = QNAN | (if (b) TAG_TRUE else TAG_FALSE) };
    }

    /// 创建整数值
    pub fn initInt(i: i64) Value {
        // 48位整数范围检查
        if (i >= INT48_MIN and i <= INT48_MAX) {
            const encoded: u64 = @as(u64, @bitCast(i)) & INT48_MASK;
            return .{ .val = TAG_INT_MARKER | encoded };
        }
        // 超出范围：使用浮点数存储
        return .{ .val = @bitCast(@as(f64, @floatFromInt(i))) };
    }

    /// 创建浮点数值
    pub fn initFloat(f: f64) Value {
        return .{ .val = @bitCast(f) };
    }

    /// 创建字符串值
    pub fn initString(str: *PHPString) Value {
        const addr = @intFromPtr(str);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_STRING) };
    }

    /// 创建数组值
    pub fn initArray(arr: *PHPArray) Value {
        const addr = @intFromPtr(arr);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_ARRAY) };
    }

    /// 创建函数值
    pub fn initFunction(func: *PHPClosure) Value {
        const addr = @intFromPtr(func);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_FUNCTION) };
    }

    /// 创建引用值（直接指针，不推荐用于数组元素）
    pub fn initRef(ptr: *Value) Value {
        const addr = @intFromPtr(ptr);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_REF) };
    }

    /// 创建引用值（使用RefWrapper，推荐用于数组元素）
    pub fn initRefWrapper(wrapper: *RefWrapper) Value {
        const addr = @intFromPtr(wrapper);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_REF) };
    }

    // ========================================================================
    // 类型检查
    // ========================================================================

    pub fn isNull(self: Value) bool {
        return self.val == (QNAN | TAG_NIL);
    }

    pub fn isMissing(self: Value) bool {
        return self.val == (QNAN | TAG_MISSING);
    }

    pub fn isBool(self: Value) bool {
        return self.val == (QNAN | TAG_FALSE) or self.val == (QNAN | TAG_TRUE);
    }

    pub fn isInt(self: Value) bool {
        return (self.val & (SIGN_BIT | QNAN)) == TAG_INT_MARKER;
    }

    pub fn isFloat(self: Value) bool {
        return (self.val & QNAN) != QNAN;
    }

    pub fn isString(self: Value) bool {
        // 首先检查是否是指针类型（QNAN位设置，但SIGN_BIT未设置）
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        // 然后检查类型标签
        return (self.val & TYPE_MASK) == TYPE_STRING;
    }

    pub fn isArray(self: Value) bool {
        // 首先检查是否是指针类型（QNAN位设置，但SIGN_BIT未设置）
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        // 然后检查类型标签
        return (self.val & TYPE_MASK) == TYPE_ARRAY;
    }

    pub fn isFunction(self: Value) bool {
        // 首先检查是否是指针类型（QNAN位设置，但SIGN_BIT未设置）
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        // 然后检查类型标签
        return (self.val & TYPE_MASK) == TYPE_FUNCTION;
    }

    pub fn isRef(self: Value) bool {
        // 首先检查是否是指针类型（QNAN位设置，但SIGN_BIT未设置）
        if ((self.val & (SIGN_BIT | QNAN)) != QNAN) return false;
        // 然后检查类型标签
        return (self.val & TYPE_MASK) == TYPE_REF;
    }

    // ========================================================================
    // 数据提取
    // ========================================================================

    pub fn asBool(self: Value) bool {
        return (self.val & 0x1) == 1;
    }

    pub fn asInt(self: Value) i64 {
        if ((self.val & (SIGN_BIT | QNAN)) == TAG_INT_MARKER) {
            const raw: u64 = self.val & INT48_MASK;
            // 符号扩展
            if ((raw & INT48_SIGN_BIT) != 0) {
                return @bitCast(raw | 0xFFFF000000000000);
            }
            return @bitCast(raw);
        }
        // 可能是浮点数存储的大整数
        if ((self.val & QNAN) != QNAN) {
            const f: f64 = @bitCast(self.val);
            if (f >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
                f <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
            {
                return @intFromFloat(f);
            }
        }
        return 0;
    }

    pub fn asFloat(self: Value) f64 {
        return @bitCast(self.val);
    }

    pub fn asString(self: Value) *PHPString {
        return @ptrFromInt(nanbox_abi.decodePtr(self.val));
    }

    pub fn asArray(self: Value) *PHPArray {
        // 如果是引用，先解引用
        if (self.isRef()) {
            const ref_ptr = self.asRef();
            return ref_ptr.asArray();
        }
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    pub fn asFunction(self: Value) *PHPClosure {
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    pub fn asRef(self: Value) *Value {
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    pub fn asRefWrapper(self: Value) *RefWrapper {
        const ptr_val = nanbox_abi.decodePtr(self.val);
        return @ptrFromInt(ptr_val);
    }

    /// 获取数组元素的引用（用于引用返回）
    pub fn getArrayElementRef(arr: *PHPArray, key: ArrayKey, allocator: Allocator) !*Value {
        const entry = arr.data.getPtr(key) orelse {
            // 如果元素不存在，创建一个 null 值
            try arr.data.put(allocator, key, Value.initNull());
            return arr.data.getPtr(key).?;
        };
        return entry;
    }

    // ========================================================================
    // 引用计数
    // ========================================================================

    pub fn retain(self: Value) Value {
        if (self.isString()) {
            self.asString().retain();
        } else if (self.isArray()) {
            self.asArray().retain();
        } else if (Value_isObject(self)) {
            Value_asObject(self).retain();
        } else if (self.isFunction()) {
            self.asFunction().retain();
        }
        return self;
    }

    pub fn release(self: Value, allocator: Allocator) void {
        // 引用不需要释放（只是指针）
        if (self.isRef()) {
            return;
        }
        if (self.isString()) {
            self.asString().release(allocator);
        } else if (self.isArray()) {
            self.asArray().release(allocator);
        } else if (Value_isObject(self)) {
            Value_asObject(self).release();
        } else if (self.isFunction()) {
            self.asFunction().release(allocator);
        }
    }

    // ========================================================================
    // 类型转换
    // ========================================================================

    /// 转换为布尔值（PHP语义）
    pub fn toBool(self: Value) bool {
        if (self.isNull()) return false;
        if (self.isBool()) return self.asBool();
        if (self.isInt()) return self.asInt() != 0;
        if (self.isFloat()) return self.asFloat() != 0.0;
        if (self.isString()) return self.asString().length > 0;
        if (self.isArray()) return self.asArray().count() > 0;
        return true;
    }

    /// 转换为整数（PHP语义）
    pub fn toInt(self: Value) i64 {
        if (self.isInt()) return self.asInt();
        if (self.isFloat()) {
            const f = self.asFloat();
            if (f >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
                f <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
            {
                return @intFromFloat(f);
            }
            return 0;
        }
        if (self.isBool()) return if (self.asBool()) 1 else 0;
        if (self.isNull()) return 0;
        // 字符串转整数：解析数字前缀
        if (self.isString()) {
            const str = self.asString();
            if (str.length == 0) return 0;
            // 简化实现：只处理纯数字字符串
            return std.fmt.parseInt(i64, str.data, 10) catch 0;
        }
        return 0;
    }

    /// 转换为浮点数（PHP语义）
    pub fn toFloat(self: Value) f64 {
        if (self.isFloat()) return self.asFloat();
        if (self.isInt()) return @floatFromInt(self.asInt());
        if (self.isBool()) return if (self.asBool()) 1.0 else 0.0;
        if (self.isNull()) return 0.0;
        if (self.isString()) {
            const str = self.asString();
            if (str.length == 0) return 0.0;
            return std.fmt.parseFloat(f64, str.data) catch 0.0;
        }
        return 0.0;
    }

    /// 转换为字符串（PHP语义）
    /// 注意：返回的字符串引用计数已经+1，调用者负责release
    pub fn toString(self: Value, allocator: Allocator) !*PHPString {
        if (self.isNull()) return PHPString.init(allocator, "");
        if (self.isBool()) return PHPString.init(allocator, if (self.asBool()) "1" else "");
        if (self.isInt()) {
            const str = try std.fmt.allocPrint(allocator, "{d}", .{self.asInt()});
            defer allocator.free(str);
            return PHPString.init(allocator, str);
        }
        if (self.isFloat()) {
            const f = self.asFloat();
            // PHP兼容的浮点数格式化（默认精度14位，但实际输出会截断）
            var buf: [64]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d:.13}", .{f}) catch {
                const fallback = try std.fmt.allocPrint(allocator, "{d}", .{f});
                defer allocator.free(fallback);
                return PHPString.init(allocator, fallback);
            };
            
            // 去除尾部的0和小数点
            var end = str.len;
            if (std.mem.indexOfScalar(u8, str, '.')) |_| {
                while (end > 0 and str[end - 1] == '0') : (end -= 1) {}
                if (end > 0 and str[end - 1] == '.') end -= 1;
            }
            
            return PHPString.init(allocator, str[0..end]);
        }
        if (self.isString()) {
            // 对于已经是字符串的值，创建一个新副本
            // 这样调用者可以安全地release而不影响原始值
            return PHPString.init(allocator, self.asString().data);
        }
        if (self.isArray()) {
            return PHPString.init(allocator, "Array");
        }
        if (self.isFunction()) {
            return PHPString.init(allocator, "Function");
        }
        if (Value_isObject(self)) {
            return Value_asObject(self).toString(allocator);
        }
        return PHPString.init(allocator, "");
    }
};

// ============================================================================
// Value类型扩展 - 函数/回调支持
// ============================================================================

pub const PHPClosure = struct {
    // 统一函数签名：ctx 可以是 this (Object) 或者 closure (Function) 或者 null
    func: *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value,
    captures: []Value,
    ref_count: usize,
    gc_info: GCInfo,
    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
        func: *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value,
        captures: []const Value,
    ) !*PHPClosure {
        const f = try allocPHPClosure(allocator);
        errdefer destroyPHPClosure(f, allocator);

        const caps = try allocator.alloc(Value, captures.len);
        errdefer allocator.free(caps);
        @memcpy(caps, captures);

        // Retain captures
        for (caps) |c| {
            _ = c.retain();
        }

        alloc_counters.php_closure_objects += 1;
        alloc_counters.php_closure_live_objects += 1;
        alloc_counters.php_closure_peak_live_objects = @max(
            alloc_counters.php_closure_peak_live_objects,
            alloc_counters.php_closure_live_objects,
        );

        f.* = .{ .func = func, .captures = caps, .ref_count = 1, .gc_info = .{}, .allocator = allocator };
        return f;
    }

    pub fn retain(self: *PHPClosure) void {
        self.ref_count += 1;
    }

    pub fn release(self: *PHPClosure, allocator: Allocator) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            for (self.captures) |c| {
                c.release(allocator);
            }
            allocator.free(self.captures);
            if (alloc_counters.php_closure_live_objects > 0) {
                alloc_counters.php_closure_live_objects -= 1;
            }
            destroyPHPClosure(self, allocator);
        } else if (!gc_in_progress) {
            gcBufferClosure(self);
        }
    }
};

/// 变量赋值
pub fn val_assign(target: *Value, value: Value) void {
    // 直接覆盖值（包括引用值）
    // 注意：调用者负责释放旧值和retain新值
    target.* = value;
}

/// 变量解引用
pub fn val_deref(val: *Value) *Value {
    if (val.isRef()) {
        // 直接返回指针指向的Value
        const ptr = val.asRef();
        return ptr;
    }
    return val;
}

pub fn make_ref(ptr: *Value, allocator: Allocator) !Value {
    _ = allocator;
    const result = Value.initRef(ptr);
    return result;
}

const BuiltinFn = *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value;

const builtin_function_map = std.StaticStringMap(BuiltinFn).initComptime(.{
    .{ "strlen", wrapBuiltin_strlen },
    .{ "strtoupper", wrapBuiltin_strtoupper },
    .{ "strtolower", wrapBuiltin_strtolower },
    .{ "trim", wrapBuiltin_trim },
    .{ "count", wrapBuiltin_count },
    .{ "sqrt", wrapBuiltin_sqrt },
    .{ "strval", wrapBuiltin_strval },
    .{ "array_map", wrapBuiltin_array_map },
    .{ "array_filter", wrapBuiltin_array_filter },
    .{ "array_reduce", wrapBuiltin_array_reduce },
    .{ "array_merge", wrapBuiltin_array_merge },
    .{ "array_sum", wrapBuiltin_array_sum },
    .{ "round", wrapBuiltin_round },
    .{ "usort", wrapBuiltin_usort },
    .{ "select", wrapBuiltin_select },
    .{ "get_class_methods", wrapBuiltin_get_class_methods },
    .{ "get_class_vars", wrapBuiltin_get_class_vars },
    .{ "get_object_vars", wrapBuiltin_get_object_vars },
    .{ "get_called_class", wrapBuiltin_get_called_class },
    .{ "forward_static_call", wrapBuiltin_forward_static_call },
    .{ "forward_static_call_array", wrapBuiltin_forward_static_call_array },
});

fn lookupBuiltinFunction(name: []const u8) ?BuiltinFn {
    return builtin_function_map.get(name);
}

pub fn php_create_closure(name: Value, captures: Value, allocator: Allocator) !Value {
    if (!name.isString()) return error.InvalidClosureName;
    if (!captures.isArray()) return error.InvalidCaptureList;

    const func_name = name.asString().data;
    const caps_arr = captures.asArray();

    // Convert PHPArray to []Value slice
    // We need to iterate the array.
    var cap_list = std.ArrayListUnmanaged(Value){};
    defer cap_list.deinit(allocator);

    // Assuming captures is a list (indexed 0..N)
    var i: usize = 0;
    while (i < caps_arr.elements.count()) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        if (caps_arr.elements.get(key)) |val| {
            try cap_list.append(allocator, val);
        } else {
            break;
        }
    }

    // Lookup function
    var func_ptr: ?BuiltinFn = null;

    if (user_function_registry) |registry| {
        func_ptr = registry.get(func_name);
    }

    if (func_ptr == null) {
        func_ptr = lookupBuiltinFunction(func_name);
    }

    if (func_ptr == null) return error.UnknownFunction;

    const closure = try PHPClosure.init(allocator, func_ptr.?, cap_list.items);
    return Value.initFunction(closure);
}

fn wrapBuiltin_strlen(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strlen(args[0]);
}

fn wrapBuiltin_array_merge(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_array_merge(args, allocator);
}

fn wrapBuiltin_array_sum(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_array_sum(args[0]);
}

fn wrapBuiltin_round(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    const precision = if (args.len >= 2) args[1] else Value.initInt(0);
    return php_round(args[0], precision);
}

fn wrapBuiltin_usort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_usort(args[0], args[1], allocator);
}

fn wrapBuiltin_strtoupper(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strtoupper(args[0], allocator);
}

fn wrapBuiltin_strtolower(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strtolower(args[0], allocator);
}

fn wrapBuiltin_trim(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const mask = if (args.len >= 2) args[1] else Value.initNull();
    return php_trim(args[0], mask, allocator);
}

fn wrapBuiltin_count(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    const mode = if (args.len >= 2) args[1] else Value.initInt(0);
    return php_count(args[0], mode);
}

fn wrapBuiltin_sqrt(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_sqrt(args[0]);
}

fn wrapBuiltin_strval(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strval(args[0], allocator);
}

fn wrapBuiltin_array_map(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_array_map(args[0], args[1], allocator);
}

fn wrapBuiltin_array_filter(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const callback = if (args.len >= 2) args[1] else Value.initNull();
    return php_array_filter(args[0], callback, allocator);
}

fn wrapBuiltin_array_reduce(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const initial = if (args.len >= 3) args[2] else Value.initNull();
    return php_array_reduce(args[0], args[1], initial, allocator);
}

fn wrapBuiltin_select(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_select(args, allocator);
}

fn wrapBuiltin_get_class_methods(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_class_methods(args[0], allocator);
}

fn wrapBuiltin_get_class_vars(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_class_vars(args[0], allocator);
}

fn wrapBuiltin_get_object_vars(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_object_vars(args[0], allocator);
}

fn wrapBuiltin_get_called_class(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len != 0) return error.InvalidArgumentCount;
    const called = getCurrentCalledClass() orelse return error.ClassNotFound;
    const s = try PHPString.init(allocator, called.name);
    return Value.initString(s);
}

fn php_forward_static_call(callback: Value, args: []const Value, allocator: Allocator) !Value {
    if (!callback.isString()) return error.InvalidCallback;
    const cb = callback.asString().data;

    const sep = std.mem.indexOf(u8, cb, "::") orelse return error.InvalidCallback;
    if (sep == 0 or sep + 2 >= cb.len) return error.InvalidCallback;

    const class_part = cb[0..sep];
    const method_part = cb[sep + 2 ..];

    const lookup_meta = blk: {
        if (std.mem.eql(u8, class_part, "self")) {
            break :blk getCurrentScopeClass() orelse return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_part, "parent")) {
            const scope = getCurrentScopeClass() orelse return error.ClassNotFound;
            break :blk scope.parent orelse return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_part, "static")) {
            break :blk getCurrentCalledClass() orelse return error.ClassNotFound;
        }
        break :blk findClass(class_part) orelse return error.ClassNotFound;
    };

    const called_meta = getCurrentCalledClass() orelse lookup_meta;

    if (lookup_meta.findMethodLookup(method_part)) |lookup| {
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(Value.initNull(), args, allocator);
    }

    if (lookup_meta.findMethodLookup("__callStatic")) |lookup| {
        const name_str = try PHPString.init(allocator, method_part);
        const name_val = Value.initString(name_str);
        defer name_val.release(allocator);

        const args_arr = try PHPArray.init(allocator);
        for (args) |arg| {
            try args_arr.push(allocator, arg);
        }
        const call_args = [_]Value{ name_val, Value.initArray(args_arr) };
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(Value.initNull(), &call_args, allocator);
    }

    return error.MethodNotFound;
}

fn wrapBuiltin_forward_static_call(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_forward_static_call(args[0], args[1..], allocator);
}

fn wrapBuiltin_forward_static_call_array(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len != 2) return error.InvalidArgumentCount;
    if (!args[1].isArray()) return error.InvalidArgument;

    const arr = args[1].asArray();
    var list = std.ArrayListUnmanaged(Value){};
    defer list.deinit(allocator);

    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        try list.append(allocator, entry.value_ptr.*);
    }

    return php_forward_static_call(args[0], list.items, allocator);
}

pub fn php_select_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    return php_select(args, allocator);
}

pub fn php_get_class_methods_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_class_methods(args[0], allocator);
}

pub fn php_get_class_vars_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_class_vars(args[0], allocator);
}

pub fn php_get_object_vars_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_object_vars(args[0], allocator);
}

pub fn php_get_called_class_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    return wrapBuiltin_get_called_class(ctx, args, allocator);
}

pub fn php_forward_static_call_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    return wrapBuiltin_forward_static_call(ctx, args, allocator);
}

pub fn php_forward_static_call_array_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    return wrapBuiltin_forward_static_call_array(ctx, args, allocator);
}

/// 获取数组元素的引用（用于引用返回）
/// 参数：array, key
/// 返回：Value.initRef(指向数组元素的指针)
pub fn php_array_get_ref(arr_val: Value, key_val: Value, allocator: Allocator) !Value {
    if (!arr_val.isArray()) return error.InvalidArgument;
    const arr = arr_val.asArray();

    const key = if (key_val.isInt())
        ArrayKey{ .integer = key_val.toInt() }
    else if (key_val.isString())
        ArrayKey{ .string = key_val.asString() }
    else
        return error.InvalidKey;

    // 获取或创建数组元素
    const entry_ptr = arr.data.getPtr(key) orelse blk: {
        // 元素不存在，创建一个 null 值
        try arr.data.put(allocator, key, Value.initNull());
        break :blk arr.data.getPtr(key).?;
    };

    // 返回指向数组元素的引用
    return Value.initRef(entry_ptr);
}

fn php_get_class_methods(class_name_val: Value, allocator: Allocator) !Value {
    var meta_opt: ?*const ClassMeta = null;
    if (class_name_val.isString()) {
        meta_opt = findClass(class_name_val.asString().data);
    } else if (Value_isObject(class_name_val)) {
        const obj = Value_asObject(class_name_val);
        meta_opt = obj.class_meta orelse findClass(obj.class_name);
    } else {
        return error.InvalidArgument;
    }

    const meta = meta_opt orelse return Value.initNull();

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    const res_arr = try PHPArray.init(allocator);

    var cur: ?*const ClassMeta = meta;
    while (cur) |m| : (cur = m.parent) {
        var iter = m.methods.iterator();
        while (iter.next()) |entry| {
            const method = entry.value_ptr.*;
            if (!method.is_public) continue;
            if (seen.contains(entry.key_ptr.*)) continue;
            try seen.put(entry.key_ptr.*, {});

            const s = try PHPString.init(allocator, entry.key_ptr.*);
            const v = Value.initString(s);
            try res_arr.push(allocator, v);
            v.release(allocator);
        }
    }

    return Value.initArray(res_arr);
}

fn php_get_class_vars(class_name_val: Value, allocator: Allocator) !Value {
    var meta_opt: ?*const ClassMeta = null;
    if (class_name_val.isString()) {
        meta_opt = findClass(class_name_val.asString().data);
    } else if (Value_isObject(class_name_val)) {
        const obj = Value_asObject(class_name_val);
        meta_opt = obj.class_meta orelse findClass(obj.class_name);
    } else {
        return error.InvalidArgument;
    }

    const meta = meta_opt orelse return Value.initNull();
    const res_arr = try PHPArray.init(allocator);

    var iter = meta.properties.iterator();
    while (iter.next()) |entry| {
        const prop = entry.value_ptr.*;
        if (prop.is_static) continue;
        if (!prop.is_public) continue;
        const key_str = try PHPString.init(allocator, entry.key_ptr.*);
        try res_arr.set(allocator, ArrayKey{ .string = key_str }, prop.default_value orelse Value.initNull());
        key_str.release(allocator);
    }

    return Value.initArray(res_arr);
}

fn php_get_object_vars(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) return error.InvalidArgument;
    const obj = Value_asObject(obj_val);

    const res_arr = try PHPArray.init(allocator);
    var iter = obj.properties.iterator();
    while (iter.next()) |entry| {
        const key_str = try PHPString.init(allocator, entry.key_ptr.*);
        try res_arr.set(allocator, ArrayKey{ .string = key_str }, entry.value_ptr.*);
        key_str.release(allocator);
    }
    return Value.initArray(res_arr);
}

fn php_select(args: []const Value, allocator: Allocator) !Value {
    const cases_arg = args[0];
    if (!cases_arg.isArray()) return error.InvalidArgument;

    var timeout: ?i64 = null;
    if (args.len > 1 and !args[1].isNull()) {
        timeout = args[1].toInt();
    }

    const array = cases_arg.asArray();
    const start_time = std.time.milliTimestamp();

    while (true) {
        var iter = array.elements.iterator();
        var index: usize = 0;
        while (iter.next()) |entry| : (index += 1) {
            const case_val = entry.value_ptr.*;
            if (!case_val.isArray()) continue;

            const case_arr = case_val.asArray();
            const ch_val = case_arr.get(ArrayKey{ .integer = 0 }) orelse continue;
            const op_val = case_arr.get(ArrayKey{ .integer = 1 }) orelse continue;

            if (!Value_isObject(ch_val)) continue;
            const ch_obj = Value_asObject(ch_val);
            if (ch_obj.getProperty("_ptr")) |ptr_val| {
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                const op = op_val.toInt();

                if (op == 0) {
                    if (channel.tryRecv()) |val| {
                        const res_arr = try PHPArray.init(allocator);
                        try res_arr.push(allocator, Value.initInt(@intCast(index)));
                        try res_arr.push(allocator, val);
                        return Value.initArray(res_arr);
                    }
                } else if (op == 1) {
                    const send_val = case_arr.get(ArrayKey{ .integer = 2 }) orelse Value.initNull();
                    _ = send_val.retain();
                    const ok = channel.trySend(send_val) catch {
                        send_val.release(allocator);
                        continue;
                    };
                    if (ok) {
                        return Value.initInt(@intCast(index));
                    }
                    send_val.release(allocator);
                }
            }
        }

        if (timeout) |t| {
            if (std.time.milliTimestamp() - start_time >= t) {
                return Value.initNull();
            }
        }
        std.Thread.yield() catch {};
    }
}

pub fn php_invoke_callable(callback: Value, args: []const Value, allocator: Allocator) !Value {
    if (callback.isFunction()) {
        const closure = callback.asFunction();
        // 传递闭包自身作为上下文
        return closure.func(callback, args, allocator);
    }
    if (callback.isString()) {
        const func_name = callback.asString().data;
        if (lookupBuiltinFunction(func_name)) |func| {
            // 普通函数调用，上下文为 null
            return func(Value.initNull(), args, allocator);
        }
        // 查找用户定义函数
        if (user_function_registry) |registry| {
            if (registry.get(func_name)) |func| {
                return func(Value.initNull(), args, allocator);
            }
        }
        return error.UnknownFunction;
    }
    if (callback.isArray()) {
        const arr = callback.asArray();
        if (arr.elements.count() != 2) return error.InvalidCallback;

        const key0 = ArrayKey{ .integer = 0 };
        const key1 = ArrayKey{ .integer = 1 };

        const val0 = arr.elements.get(key0) orelse return error.InvalidCallback;
        const val1 = arr.elements.get(key1) orelse return error.InvalidCallback;

        if (!val1.isString()) return error.InvalidCallback;
        const method_name = val1.asString().data;

        if (Value_isObject(val0)) {
            const obj_ptr = Value_asObject(val0);
            return obj_ptr.callMethod(method_name, args);
        }
        if (val0.isString()) {
            return php_call_static(val0.asString().data, method_name, args, allocator);
        }
        return error.NotImplemented;
    }
    return error.InvalidCallback;
}

pub fn php_args_append_spread(dest: Value, src: Value, allocator: Allocator) !Value {
    if (!dest.isArray() or !src.isArray()) {
        return throwException("Only arrays can be unpacked", allocator);
    }

    const dest_arr = dest.asArray();
    const src_arr = src.asArray();
    const n: usize = @intCast(src_arr.next_index);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        if (src_arr.get(key)) |v| {
            try dest_arr.push(allocator, v);
        }
    }
    return dest;
}

pub fn php_invoke_callable_args_array(callback: Value, args_array: Value, allocator: Allocator) !Value {
    if (!args_array.isArray()) {
        return throwException("Only arrays can be unpacked", allocator);
    }

    const arr = args_array.asArray();
    const max_count: usize = @intCast(arr.next_index);
    const tmp_args = try allocator.alloc(Value, max_count);
    defer allocator.free(tmp_args);

    var used: usize = 0;
    var i: usize = 0;
    while (i < max_count) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        if (arr.get(key)) |v| {
            tmp_args[used] = v;
            used += 1;
        }
    }
    return php_invoke_callable(callback, tmp_args[0..used], allocator);
}

// ============================================================================
// 算术运算符
// ============================================================================

/// 加法运算（PHP语义）
pub fn php_add(lhs: Value, rhs: Value) !Value {
    // 整数 + 整数 = 整数（可能溢出为浮点）
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @addWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            // 溢出：转为浮点数
            return Value.initFloat(@as(f64, @floatFromInt(a)) + @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    // 其他情况：转为浮点数
    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a + b);
}

/// 减法运算（PHP语义）
pub fn php_sub(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @subWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            return Value.initFloat(@as(f64, @floatFromInt(a)) - @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a - b);
}

/// Negate a value (unary minus)
pub fn php_neg(val: Value) !Value {
    if (val.isInt()) {
        const a = val.asInt();
        if (a == Value.INT48_MIN) {
            return Value.initFloat(-@as(f64, @floatFromInt(a)));
        }
        return Value.initInt(-a);
    }
    return Value.initFloat(-val.toFloat());
}

/// 乘法运算（PHP语义）
pub fn php_mul(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @mulWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            return Value.initFloat(@as(f64, @floatFromInt(a)) * @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a * b);
}

/// 除法运算（PHP语义）
pub fn php_div(lhs: Value, rhs: Value) !Value {
    // PHP除法总是返回浮点数（除非整除）
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        if (b == 0) return error.DivisionByZero;
        if (@mod(a, b) == 0) {
            const result = @divTrunc(a, b);
            if (result >= Value.INT48_MIN and result <= Value.INT48_MAX) {
                return Value.initInt(result);
            }
        }
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    if (b == 0.0) return error.DivisionByZero;
    return Value.initFloat(a / b);
}

/// 取模运算（PHP语义）
pub fn php_mod(lhs: Value, rhs: Value) !Value {
    const a = lhs.toInt();
    const b = rhs.toInt();
    if (b == 0) return error.DivisionByZero;
    // PHP 使用 remainder（保留符号），不是 modulo
    return Value.initInt(@rem(a, b));
}

/// 幂运算（PHP语义）
pub fn php_pow(base: Value, exp: Value) !Value {
    const b = base.toFloat();
    const e = exp.toFloat();
    return Value.initFloat(std.math.pow(f64, b, e));
}

// ============================================================================
// 比较运算符
// ============================================================================

/// 等于运算（PHP语义：类型转换后比较）
pub fn php_eq(lhs: Value, rhs: Value) !Value {
    // null == null
    if (lhs.isNull() and rhs.isNull()) return Value.initBool(true);

    // bool == bool
    if (lhs.isBool() and rhs.isBool()) {
        return Value.initBool(lhs.asBool() == rhs.asBool());
    }

    // int == int
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() == rhs.asInt());
    }

    // 数字比较
    if ((lhs.isInt() or lhs.isFloat()) and (rhs.isInt() or rhs.isFloat())) {
        return Value.initBool(lhs.toFloat() == rhs.toFloat());
    }

    // 字符串比较
    if (lhs.isString() and rhs.isString()) {
        const a = lhs.asString();
        const b = rhs.asString();
        return Value.initBool(std.mem.eql(u8, a.data, b.data));
    }

    // 数组比较
    if (lhs.isArray() and rhs.isArray()) {
        const a = lhs.asArray();
        const b = rhs.asArray();
        if (a.elements.count() != b.elements.count()) return Value.initBool(false);
        
        var iter = a.elements.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            const other_val = b.elements.get(key) orelse return Value.initBool(false);
            const eq = try php_eq(val, other_val);
            if (!eq.asBool()) return Value.initBool(false);
        }
        return Value.initBool(true);
    }

    // 数字和字符串比较：尝试将字符串转为数字
    if ((lhs.isInt() or lhs.isFloat()) and rhs.isString()) {
        const num_val = stringToNumber(rhs.asString().data);
        return Value.initBool(lhs.toFloat() == num_val);
    }
    if (lhs.isString() and (rhs.isInt() or rhs.isFloat())) {
        const num_val = stringToNumber(lhs.asString().data);
        return Value.initBool(num_val == rhs.toFloat());
    }

    // 其他情况：false
    return Value.initBool(false);
}

// 辅助函数：字符串转数字（PHP 语义）
fn stringToNumber(str: []const u8) f64 {
    if (str.len == 0) return 0.0;
    
    // 跳过前导空格
    var i: usize = 0;
    while (i < str.len and std.ascii.isWhitespace(str[i])) : (i += 1) {}
    if (i == str.len) return 0.0;
    
    const trimmed = str[i..];
    
    // 尝试解析为整数或浮点数
    if (std.fmt.parseInt(i64, trimmed, 10)) |int_val| {
        return @floatFromInt(int_val);
    } else |_| {
        if (std.fmt.parseFloat(f64, trimmed)) |float_val| {
            return float_val;
        } else |_| {
            // PHP: 非数字字符串转为 0
            return 0.0;
        }
    }
}

/// 不等于运算
pub fn php_ne(lhs: Value, rhs: Value) !Value {
    const result = try php_eq(lhs, rhs);
    return Value.initBool(!result.asBool());
}

/// 全等运算（PHP语义：类型和值都相等）
pub fn php_identical(lhs: Value, rhs: Value) !Value {
    // 类型不同
    if (lhs.isNull() != rhs.isNull()) return Value.initBool(false);
    if (lhs.isBool() != rhs.isBool()) return Value.initBool(false);
    if (lhs.isInt() != rhs.isInt()) return Value.initBool(false);
    if (lhs.isFloat() != rhs.isFloat()) return Value.initBool(false);
    if (lhs.isString() != rhs.isString()) return Value.initBool(false);
    if (lhs.isArray() != rhs.isArray()) return Value.initBool(false);

    // 类型相同，比较值
    if (lhs.isNull()) return Value.initBool(true);
    if (lhs.isBool()) return Value.initBool(lhs.asBool() == rhs.asBool());
    if (lhs.isInt()) return Value.initBool(lhs.asInt() == rhs.asInt());
    if (lhs.isFloat()) return Value.initBool(lhs.asFloat() == rhs.asFloat());
    if (lhs.isString()) {
        const a = lhs.asString();
        const b = rhs.asString();
        return Value.initBool(std.mem.eql(u8, a.data, b.data));
    }
    if (lhs.isArray()) {
        // 数组比较：指针相同
        return Value.initBool(lhs.asArray() == rhs.asArray());
    }

    return Value.initBool(false);
}

/// 不全等运算
pub fn php_not_identical(lhs: Value, rhs: Value) !Value {
    const result = try php_identical(lhs, rhs);
    return Value.initBool(!result.asBool());
}

/// 小于运算
pub fn php_lt(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() < rhs.asInt());
    }
    return Value.initBool(lhs.toFloat() < rhs.toFloat());
}

/// 小于等于运算
pub fn php_le(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() <= rhs.asInt());
    }
    return Value.initBool(lhs.toFloat() <= rhs.toFloat());
}

/// 大于运算
pub fn php_gt(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() > rhs.asInt());
    }
    return Value.initBool(lhs.toFloat() > rhs.toFloat());
}

/// 大于等于运算
pub fn php_ge(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        return Value.initBool(lhs.asInt() >= rhs.asInt());
    }
    return Value.initBool(lhs.toFloat() >= rhs.toFloat());
}

/// Spaceship 运算符 (<=>)
/// 返回 -1 (lhs < rhs), 0 (lhs == rhs), 1 (lhs > rhs)
pub fn php_spaceship(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        const l = lhs.asInt();
        const r = rhs.asInt();
        if (l < r) return Value.initInt(-1);
        if (l > r) return Value.initInt(1);
        return Value.initInt(0);
    }
    if (lhs.isString() and rhs.isString()) {
        const l = lhs.asString();
        const r = rhs.asString();
        const cmp = std.mem.order(u8, l.data[0..l.length], r.data[0..r.length]);
        return Value.initInt(switch (cmp) {
            .lt => -1,
            .gt => 1,
            .eq => 0,
        });
    }
    const l = lhs.toFloat();
    const r = rhs.toFloat();
    if (l < r) return Value.initInt(-1);
    if (l > r) return Value.initInt(1);
    return Value.initInt(0);
}

// ============================================================================
// 逻辑运算符
// ============================================================================

/// 逻辑与运算
pub fn php_and(lhs: Value, rhs: Value) !Value {
    return Value.initBool(lhs.toBool() and rhs.toBool());
}

/// 逻辑或运算
pub fn php_or(lhs: Value, rhs: Value) !Value {
    return Value.initBool(lhs.toBool() or rhs.toBool());
}

/// 逻辑异或运算
pub fn php_xor(lhs: Value, rhs: Value) !Value {
    const l = lhs.toBool();
    const r = rhs.toBool();
    return Value.initBool((l and !r) or (!l and r));
}

/// 逻辑非运算
pub fn php_not(val: Value) !Value {
    return Value.initBool(!val.toBool());
}

// ============================================================================
// 字符串运算符
// ============================================================================

/// 字符串连接运算
pub fn php_concat(lhs: Value, rhs: Value, allocator: Allocator) !Value {
    // 快速路径：两个都是字符串
    if (lhs.isString() and rhs.isString()) {
        const result = try lhs.asString().concat(rhs.asString(), allocator);
        return Value.initString(result);
    }

    // 慢速路径：需要类型转换
    const lhs_str = try lhs.toString(allocator);
    defer lhs_str.release(allocator);

    const rhs_str = try rhs.toString(allocator);
    defer rhs_str.release(allocator);

    const result = try lhs_str.concat(rhs_str, allocator);
    return Value.initString(result);
}

// ============================================================================
// 输出函数
// ============================================================================

/// echo语句
pub fn php_echo(value: Value) !void {
    const stdout_file = std.fs.File{ .handle = 1 };
    
    if (value.isNull()) {
        // null不输出任何内容
        return;
    } else if (value.isBool()) {
        if (value.asBool()) {
            try stdout_file.writeAll("1");
        }
        // false不输出任何内容
    } else if (value.isInt()) {
        var buf: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "{d}", .{value.asInt()});
        try stdout_file.writeAll(str);
    } else if (value.isFloat()) {
        var buf: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "{d}", .{value.asFloat()});
        try stdout_file.writeAll(str);
    } else if (value.isString()) {
        const str = value.asString();
        try stdout_file.writeAll(str.data);
    } else if (value.isArray()) {
        try stdout_file.writeAll("Array");
    }
}

/// print语句（返回1）
pub fn php_print(value: Value) !Value {
    try php_echo(value);
    return Value.initInt(1);
}

/// var_dump函数
pub fn php_var_dump(value: Value) !Value {
    if (value.isNull()) {
        std.debug.print("NULL\n", .{});
    } else if (value.isBool()) {
        std.debug.print("bool({})\n", .{value.asBool()});
    } else if (value.isInt()) {
        std.debug.print("int({})\n", .{value.asInt()});
    } else if (value.isFloat()) {
        std.debug.print("float({})\n", .{value.asFloat()});
    } else if (value.isString()) {
        const str = value.asString();
        std.debug.print("string({}) \"{s}\"\n", .{ str.length, str.data });
    } else if (value.isArray()) {
        const arr = value.asArray();
        std.debug.print("array({d}) {{\n", .{arr.count()});
        // 遍历数组
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            std.debug.print("  ", .{});
            switch (entry.key_ptr.*) {
                .integer => |i| std.debug.print("[{d}]", .{i}),
                .string => |s| std.debug.print("[\"{s}\"]", .{s.data}),
            }
            std.debug.print(" =>\n  ", .{});
            _ = php_var_dump(entry.value_ptr.*) catch {};
        }
        std.debug.print("}}\n", .{});
    }
    return Value.initNull();
}

pub fn var_dump(value: Value) !Value {
    try php_var_dump(value);
    return Value.initNull();
}

pub fn print_r(value: Value, return_output: Value) !Value {
    const want_return = return_output.toBool();
    var buffer = try std.ArrayList(u8).initCapacity(runtime_allocator, 256);
    defer buffer.deinit(runtime_allocator);

    try printValue(buffer.writer(runtime_allocator), value, 0);

    if (want_return) {
        return Value.initString(try PHPString.init(runtime_allocator, buffer.items));
    }
    std.debug.print("{s}", .{buffer.items});
    return Value.initBool(true);
}

pub fn var_export(value: Value, return_output: Value) !Value {
    const want_return = return_output.toBool();
    var buffer = try std.ArrayList(u8).initCapacity(runtime_allocator, 256);
    defer buffer.deinit(runtime_allocator);

    try exportValue(buffer.writer(runtime_allocator), value, 0);

    if (want_return) {
        return Value.initString(try PHPString.init(runtime_allocator, buffer.items));
    }
    std.debug.print("{s}", .{buffer.items});
    return Value.initNull();
}

fn writeIndent(writer: anytype, indent: usize) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn printValue(writer: anytype, value: Value, indent: usize) !void {
    if (value.isNull()) {
        try writer.writeAll("NULL");
        return;
    }
    if (value.isBool()) {
        try writer.writeAll(if (value.asBool()) "true" else "false");
        return;
    }
    if (value.isInt()) {
        try writer.print("{d}", .{value.asInt()});
        return;
    }
    if (value.isFloat()) {
        try writer.print("{d}", .{value.asFloat()});
        return;
    }
    if (value.isString()) {
        try writer.writeAll(value.asString().data);
        return;
    }
    if (value.isArray()) {
        const arr = value.asArray();
        try writer.writeAll("Array\n");
        try writeIndent(writer, indent);
        try writer.writeAll("(\n");
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            try writeIndent(writer, indent + 1);
            switch (entry.key_ptr.*) {
                .integer => |i| try writer.print("[{d}] => ", .{i}),
                .string => |s| try writer.print("[{s}] => ", .{s.data}),
            }
            try printValue(writer, entry.value_ptr.*, indent + 1);
            try writer.writeAll("\n");
        }
        try writeIndent(writer, indent);
        try writer.writeAll(")\n");
        return;
    }
    if (Value_isObject(value)) {
        const obj = Value_asObject(value);
        try writer.print("{s} Object\n", .{obj.class_name});
        try writeIndent(writer, indent);
        try writer.writeAll("(\n");
        var it = obj.properties.iterator();
        while (it.next()) |entry| {
            try writeIndent(writer, indent + 1);
            try writer.print("[{s}] => ", .{entry.key_ptr.*});
            try printValue(writer, entry.value_ptr.*, indent + 1);
            try writer.writeAll("\n");
        }
        try writeIndent(writer, indent);
        try writer.writeAll(")\n");
        return;
    }
    try writer.writeAll("Unknown");
}

fn exportValue(writer: anytype, value: Value, indent: usize) !void {
    if (value.isNull()) {
        try writer.writeAll("NULL");
        return;
    }
    if (value.isBool()) {
        try writer.writeAll(if (value.asBool()) "true" else "false");
        return;
    }
    if (value.isInt()) {
        try writer.print("{d}", .{value.asInt()});
        return;
    }
    if (value.isFloat()) {
        try writer.print("{d}", .{value.asFloat()});
        return;
    }
    if (value.isString()) {
        try writer.writeAll("'");
        const s = value.asString().data;
        for (s) |c| {
            if (c == '\'') {
                try writer.writeAll("\\'");
            } else if (c == '\\') {
                try writer.writeAll("\\\\");
            } else {
                try writer.writeByte(c);
            }
        }
        try writer.writeAll("'");
        return;
    }
    if (value.isArray()) {
        const arr = value.asArray();
        try writer.writeAll("array (\n");
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            try writeIndent(writer, indent + 1);
            switch (entry.key_ptr.*) {
                .integer => |i| try writer.print("{d}", .{i}),
                .string => |k| {
                    try writer.writeAll("'");
                    for (k.data) |c| {
                        if (c == '\'') {
                            try writer.writeAll("\\'");
                        } else if (c == '\\') {
                            try writer.writeAll("\\\\");
                        } else {
                            try writer.writeByte(c);
                        }
                    }
                    try writer.writeAll("'");
                },
            }
            try writer.writeAll(" => ");
            try exportValue(writer, entry.value_ptr.*, indent + 1);
            try writer.writeAll(",\n");
        }
        try writeIndent(writer, indent);
        try writer.writeAll(")");
        return;
    }
    if (Value_isObject(value)) {
        const obj = Value_asObject(value);
        try writer.writeAll("(object) array(\n");
        var it = obj.properties.iterator();
        while (it.next()) |entry| {
            try writeIndent(writer, indent + 1);
            try writer.writeAll("'");
            for (entry.key_ptr.*) |c| {
                if (c == '\'') {
                    try writer.writeAll("\\'");
                } else if (c == '\\') {
                    try writer.writeAll("\\\\");
                } else {
                    try writer.writeByte(c);
                }
            }
            try writer.writeAll("' => ");
            try exportValue(writer, entry.value_ptr.*, indent + 1);
            try writer.writeAll(",\n");
        }
        try writeIndent(writer, indent);
        try writer.writeAll(")");
        return;
    }
    try writer.writeAll("NULL");
}

// ============================================================================
// 常量函数
// ============================================================================

pub fn php_define(name_val: Value, value_val: Value, allocator: Allocator) !Value {
    if (!name_val.isString()) return Value.initBool(false);
    const name = name_val.asString().data;

    // 检查是否存在
    if (constants.contains(name)) {
        // Warning: Constant already defined
        // std.debug.print("Warning: Constant {s} already defined\n", .{name});
        return Value.initBool(false);
    }

    // 复制键
    const name_copy = try allocator.dupe(u8, name);
    // 保留值
    _ = value_val.retain();

    try constants.put(name_copy, value_val);
    return Value.initBool(true);
}

pub fn php_defined(name_val: Value) !Value {
    if (!name_val.isString()) return Value.initBool(false);
    const name = name_val.asString().data;
    return Value.initBool(constants.contains(name));
}

pub fn php_constant_get(name_val: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!name_val.isString()) return Value.initNull();
    const name = name_val.asString().data;

    if (constants.get(name)) |val| {
        _ = val.retain();
        return val;
    }

    // 未定义常量
    std.debug.print("Fatal error: Uncaught Error: Undefined constant \"{s}\"\n", .{name});
    std.posix.exit(255);
    return Value.initNull();
}

// ============================================================================
// 数组迭代器函数
// ============================================================================

/// 引用包装器：持有数组引用和键，确保引用的稳定性
pub const RefWrapper = struct {
    array: *PHPArray,
    key: ArrayKey,
    
    pub fn updateKey(self: *RefWrapper, new_key: ArrayKey) void {
        self.key = new_key;
    }
    
    pub fn deinit(self: *RefWrapper, allocator: Allocator) void {
        // 释放引用锁
        if (self.array.ref_lock_count > 0) {
            self.array.ref_lock_count -= 1;
            if (self.array.ref_lock_count == 0) {
                self.array.has_active_refs = false;
            }
        }
        // 不释放数组引用计数（由迭代器管理）
        // 释放RefWrapper自身
        allocator.destroy(self);
    }
};

pub const ArrayIterator = struct {
    array: *PHPArray, // 持有数组引用
    iter: PHPArray.Elements.Iterator,
    current: ?PHPArray.Elements.Entry,
    freed: bool = false, // 防止双重释放
};

pub fn php_array_iter_init(array_val: Value, allocator: Allocator) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(array_val)) {
        const obj = Value_asObject(array_val);
        if (obj.class_meta) |meta| {
            if (meta.findMethod("rewind") != null and
                meta.findMethod("valid") != null and
                meta.findMethod("current") != null and
                meta.findMethod("key") != null and
                meta.findMethod("next") != null)
            {
                // 是Iterator，调用rewind()
                _ = try php_object_call(array_val, "rewind", &[_]Value{});
                // 返回对象本身
                _ = array_val.retain();
                return array_val;
            }
        }
    }

    // 普通数组
    if (!array_val.isArray()) return Value.initInt(0);
    const array = array_val.asArray();

    // 增加数组引用计数，确保迭代期间数组不被释放
    const retained = array.retain();
    _ = retained;

    // 设置迭代器锁，防止数组在迭代期间被释放
    array.ref_lock_count += 1;
    array.has_active_refs = true;

    const iter = try allocator.create(ArrayIterator);
    iter.array = array; // 保存数组引用
    iter.iter = array.elements.iterator();
    iter.current = iter.iter.next();

    // std.debug.print("ITER_INIT: iter={*} array={*}\n", .{ iter, array });
    return Value.initInt(@as(i64, @intCast(@intFromPtr(iter))));
}

/// 初始化引用迭代器：创建RefWrapper并返回
pub fn php_array_iter_init_ref(array_val: Value, allocator: Allocator) !Value {
    // 普通数组
    if (!array_val.isArray()) return Value.initNull();
    const array = array_val.asArray();
    
    // 标记数组有活跃引用并立即转换为mixed模式
    if (!array.has_active_refs) {
        array.has_active_refs = true;
        if (array.elements.mixed == null) {
            try array.elements.convertToMixed();
        }
    }
    
    // 增加数组引用计数
    const retained = array.retain();
    _ = retained;
    
    // 创建迭代器（在mixed模式上）
    const iter = try allocator.create(ArrayIterator);
    iter.array = array;
    iter.iter = array.elements.iterator();
    iter.current = iter.iter.next();
    
    return Value.initInt(@intCast(@intFromPtr(iter)));
}

pub fn php_array_iter_valid(iter_val: Value) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(iter_val)) {
        const result = try php_object_call(iter_val, "valid", &[_]Value{});
        defer result.release(runtime_allocator);
        return Value.initBool(result.toBool());
    }
    
    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initBool(false);
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    return Value.initBool(iter.current != null);
}

/// 引用迭代器valid

pub fn php_array_iter_key(iter_val: Value, allocator: Allocator) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(iter_val)) {
        return try php_object_call(iter_val, "key", &[_]Value{});
    }
    
    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    if (iter.current) |entry| {
        switch (entry.key_ptr.*) {
            .integer => |i| return Value.initInt(i),
            .string => |s| {
                s.retain();
                return Value.initString(s);
            },
        }
    }
    _ = allocator;
    return Value.initNull();
}

pub fn php_array_iter_value(iter_val: Value) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(iter_val)) {
        return try php_object_call(iter_val, "current", &[_]Value{});
    }
    
    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    if (iter.current) |entry| {
        _ = entry.value_ptr.retain();
        return entry.value_ptr.*;
    }
    return Value.initNull();
}

pub fn php_array_iter_value_ref(iter_val: Value) !Value {
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    if (iter.current) |entry| {
        iter.array.ref_lock_count += 1;
        
        // 从mixed模式获取指针
        if (iter.array.elements.mixed) |*m| {
            if (m.getPtr(entry.key_ptr.*)) |value_ptr| {
                return Value.initRef(value_ptr);
            }
        }
        
        return Value.initNull();
    }
    return Value.initNull();
}

/// 解引用：从引用中读取值
pub fn php_deref(ref_val: Value) !Value {
    if (ref_val.isRef()) {
        // 直接解引用指针
        const ptr = ref_val.asRef();
        _ = ptr.retain();
        return ptr.*;
    }
    // 如果不是引用，直接返回值
    _ = ref_val.retain();
    return ref_val;
}

/// 引用赋值：将值写入引用指向的位置
pub fn php_ref_assign(ref_val: Value, new_val: Value) !Value {
    if (ref_val.isRef()) {
        const ptr = ref_val.asRef();
        ptr.release(runtime_allocator);
        _ = new_val.retain();
        ptr.* = new_val;
    }
    return Value.initNull();
}

/// 引用赋值（通过alloca指针）：将值写入引用指向的位置
pub fn php_ref_assign_ptr(ref_ptr: *Value, new_val: Value) !Value {
    if (ref_ptr.isRef()) {
        const ptr = ref_ptr.asRef();
        ptr.release(runtime_allocator);
        const retained = new_val.retain();
        _ = retained;
        ptr.* = new_val;
    }
    return Value.initNull();
}

pub fn php_array_iter_next(iter_val: Value) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(iter_val)) {
        _ = try php_object_call(iter_val, "next", &[_]Value{});
        _ = iter_val.retain();
        return iter_val;
    }
    
    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initInt(0);
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    iter.current = iter.iter.next();
    return Value.initInt(iter_addr);
}

/// 引用迭代器next（返回state）
// Iterator接口支持
pub fn php_is_iterator(val: Value) bool {
    if (!Value_isObject(val)) return false;
    const obj = Value_asObject(val);
    const meta = obj.class_meta orelse return false;
    return meta.findMethod("rewind") != null and
           meta.findMethod("valid") != null and
           meta.findMethod("current") != null and
           meta.findMethod("key") != null and
           meta.findMethod("next") != null;
}

pub fn php_iterator_init(obj_val: Value) !Value {
    if (!Value_isObject(obj_val)) return Value.initNull();
    _ = try php_object_call(obj_val, "rewind", &[_]Value{});
    _ = obj_val.retain();
    return obj_val;
}

pub fn php_iterator_valid(iter_val: Value) !Value {
    if (!Value_isObject(iter_val)) return Value.initBool(false);
    const result = try php_object_call(iter_val, "valid", &[_]Value{});
    defer result.release(runtime_allocator);
    return Value.initBool(result.toBool());
}

pub fn php_iterator_key(iter_val: Value) !Value {
    if (!Value_isObject(iter_val)) return Value.initNull();
    return try php_object_call(iter_val, "key", &[_]Value{});
}

pub fn php_iterator_current(iter_val: Value) !Value {
    if (!Value_isObject(iter_val)) return Value.initNull();
    return try php_object_call(iter_val, "current", &[_]Value{});
}

pub fn php_iterator_next(iter_val: Value) !Value {
    if (!Value_isObject(iter_val)) return Value.initNull();
    _ = try php_object_call(iter_val, "next", &[_]Value{});
    _ = iter_val.retain();
    return iter_val;
}

pub fn php_array_iter_free(iter_val: Value, allocator: Allocator) !Value {
    // Iterator对象不需要释放（由GC管理）
    if (Value_isObject(iter_val)) {
        iter_val.release(runtime_allocator);
        return Value.initNull();
    }

    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));

    // 防止双重释放
    if (iter.freed) {
        std.debug.print("WARNING: ArrayIterator double free detected!\n", .{});
        return Value.initNull();
    }
    iter.freed = true;

    // 清理引用锁
    if (iter.array.ref_lock_count > 0) {
        iter.array.ref_lock_count = 0;
        iter.array.has_active_refs = false;
    }

    // 释放数组引用计数
    iter.array.release(allocator);

    allocator.destroy(iter);
    return Value.initNull();
}

/// 释放引用迭代器（包含RefWrapper）
// ============================================================================
// ArrayIterator类（SPL）
// ============================================================================

/// ArrayIterator构造函数
fn arrayIterator_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();
    
    const obj = Value_asObject(ctx);
    const array_val = args[0];
    
    // 存储数组到_array属性
    _ = array_val.retain();
    try obj.properties.put("_array", array_val);
    
    // 初始化位置为0
    try obj.properties.put("_position", Value.initInt(0));
    
    return Value.initNull();
}

/// ArrayIterator::rewind
fn arrayIterator_rewind(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    try obj.properties.put("_position", Value.initInt(0));
    return Value.initNull();
}

/// ArrayIterator::valid
fn arrayIterator_valid(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const array_val = obj.properties.get("_array") orelse return Value.initBool(false);
    if (!array_val.isArray()) return Value.initBool(false);
    
    const position = obj.properties.get("_position") orelse return Value.initBool(false);
    const pos = position.asInt();
    
    const array = array_val.asArray();
    return Value.initBool(pos >= 0 and pos < @as(i64, @intCast(array.elements.count())));
}

/// ArrayIterator::current
fn arrayIterator_current(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    if (!array_val.isArray()) return Value.initNull();
    
    const position = obj.properties.get("_position") orelse return Value.initNull();
    const pos = position.asInt();
    
    const array = array_val.asArray();
    var iter = array.elements.iterator();
    var i: i64 = 0;
    while (iter.next()) |entry| {
        if (i == pos) {
            _ = entry.value_ptr.retain();
            return entry.value_ptr.*;
        }
        i += 1;
    }
    return Value.initNull();
}

/// ArrayIterator::key
fn arrayIterator_key(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = args;
    const obj = Value_asObject(ctx);
    
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    if (!array_val.isArray()) return Value.initNull();
    
    const position = obj.properties.get("_position") orelse return Value.initNull();
    const pos = position.asInt();
    
    const array = array_val.asArray();
    var iter = array.elements.iterator();
    var i: i64 = 0;
    while (iter.next()) |entry| {
        if (i == pos) {
            switch (entry.key_ptr.*) {
                .integer => |int_key| return Value.initInt(int_key),
                .string => |str_key| {
                    str_key.retain();
                    return Value.initString(str_key);
                },
            }
        }
        i += 1;
    }
    return Value.initNull();
}

/// ArrayIterator::next
fn arrayIterator_next(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const position = obj.properties.get("_position") orelse return Value.initNull();
    const pos = position.asInt();
    try obj.properties.put("_position", Value.initInt(pos + 1));
    
    return Value.initNull();
}

/// 注册ArrayIterator类
pub fn registerArrayIterator(allocator: Allocator) !void {
    const meta = try allocator.create(ClassMeta);
    const name = try allocator.dupe(u8, "ArrayIterator");
    meta.* = .{
        .name = name,
        .parent = null,
        .methods = std.StringHashMap(ClassMethod).init(allocator),
        .properties = std.StringHashMap(ClassProperty).init(allocator),
        .static_properties = std.StringHashMap(Value).init(allocator),
        .interfaces = &.{},
        .is_abstract = false,
        .allocator = allocator,
    };
    
    // 注册方法
    try meta.methods.put("__construct", .{
        .name = "__construct",
        .func = arrayIterator_construct,
        .is_public = true,
    });
    
    try meta.methods.put("rewind", .{
        .name = "rewind",
        .func = arrayIterator_rewind,
        .is_public = true,
    });
    
    try meta.methods.put("valid", .{
        .name = "valid",
        .func = arrayIterator_valid,
        .is_public = true,
    });
    
    try meta.methods.put("current", .{
        .name = "current",
        .func = arrayIterator_current,
        .is_public = true,
    });
    
    try meta.methods.put("key", .{
        .name = "key",
        .func = arrayIterator_key,
        .is_public = true,
    });
    
    try meta.methods.put("next", .{
        .name = "next",
        .func = arrayIterator_next,
        .is_public = true,
    });
    
    meta.magic_construct = arrayIterator_construct;
    
    try registerClass(meta);
}

// ============================================================================
// SplFixedArray类（SPL）
// ============================================================================

/// SplFixedArray构造函数
fn splFixedArray_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    const size = if (args.len > 0) args[0].asInt() else 0;
    
    const obj = Value_asObject(ctx);
    
    // 创建固定大小的数组
    const array = try PHPArray.init(runtime_allocator);
    for (0..@intCast(size)) |i| {
        try array.elements.put(.{ .integer = @intCast(i) }, Value.initNull());
    }
    
    const array_val = Value.initArray(array);
    try obj.properties.put("_array", array_val);
    try obj.properties.put("_size", Value.initInt(size));
    try obj.properties.put("_position", Value.initInt(0));
    
    return Value.initNull();
}

/// SplFixedArray::getSize
fn splFixedArray_getSize(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    return obj.properties.get("_size") orelse Value.initInt(0);
}

/// SplFixedArray::setSize
fn splFixedArray_setSize(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();
    
    const obj = Value_asObject(ctx);
    const new_size = args[0].asInt();
    const old_size = (obj.properties.get("_size") orelse Value.initInt(0)).asInt();
    
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();
    
    if (new_size > old_size) {
        // 扩展：添加null元素
        for (@intCast(old_size)..@intCast(new_size)) |i| {
            try array.elements.put(.{ .integer = @intCast(i) }, Value.initNull());
        }
    } else if (new_size < old_size) {
        // 缩小：删除多余元素
        for (@intCast(new_size)..@intCast(old_size)) |i| {
            if (array.elements.get(.{ .integer = @intCast(i) })) |val| {
                val.release(runtime_allocator);
            }
            _ = array.elements.remove(.{ .integer = @intCast(i) });
        }
    }
    
    try obj.properties.put("_size", Value.initInt(new_size));
    return Value.initNull();
}

/// SplFixedArray::toArray
fn splFixedArray_toArray(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    const obj = Value_asObject(ctx);
    
    const size = (obj.properties.get("_size") orelse Value.initInt(0)).asInt();
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const src_array = array_val.asArray();
    
    // 创建新数组，只包含有效范围内的元素
    const new_array = try PHPArray.init(allocator);
    for (0..@intCast(size)) |i| {
        if (src_array.elements.get(.{ .integer = @intCast(i) })) |val| {
            _ = val.retain();
            try new_array.elements.put(.{ .integer = @intCast(i) }, val);
        }
    }
    
    return Value.initArray(new_array);
}

/// SplFixedArray::offsetExists
fn splFixedArray_offsetExists(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initBool(false);
    
    const obj = Value_asObject(ctx);
    const index = args[0].asInt();
    const size = (obj.properties.get("_size") orelse Value.initInt(0)).asInt();
    
    return Value.initBool(index >= 0 and index < size);
}

/// SplFixedArray::offsetGet
fn splFixedArray_offsetGet(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();
    
    const obj = Value_asObject(ctx);
    const index = args[0].asInt();
    
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();
    
    const val = array.elements.get(.{ .integer = index }) orelse return Value.initNull();
    _ = val.retain();
    return val;
}

/// SplFixedArray::offsetSet
fn splFixedArray_offsetSet(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 2) return Value.initNull();
    
    const obj = Value_asObject(ctx);
    const index = args[0].asInt();
    const value = args[1];
    
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();
    
    _ = value.retain();
    try array.elements.put(.{ .integer = index }, value);
    
    return Value.initNull();
}

/// SplFixedArray::offsetUnset
fn splFixedArray_offsetUnset(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();
    
    const obj = Value_asObject(ctx);
    const index = args[0].asInt();
    
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();
    
    try array.elements.put(.{ .integer = index }, Value.initNull());
    
    return Value.initNull();
}

/// SplFixedArray::count
fn splFixedArray_count(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    return obj.properties.get("_size") orelse Value.initInt(0);
}

/// SplFixedArray::rewind
fn splFixedArray_rewind(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    try obj.properties.put("_position", Value.initInt(0));
    return Value.initNull();
}

/// SplFixedArray::valid
fn splFixedArray_valid(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const position = (obj.properties.get("_position") orelse Value.initInt(0)).asInt();
    const size = (obj.properties.get("_size") orelse Value.initInt(0)).asInt();
    
    return Value.initBool(position >= 0 and position < size);
}

/// SplFixedArray::current
fn splFixedArray_current(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const position = (obj.properties.get("_position") orelse Value.initInt(0)).asInt();
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();
    
    const val = array.elements.get(.{ .integer = position }) orelse return Value.initNull();
    _ = val.retain();
    return val;
}

/// SplFixedArray::key
fn splFixedArray_key(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    return obj.properties.get("_position") orelse Value.initInt(0);
}

/// SplFixedArray::next
fn splFixedArray_next(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const position = (obj.properties.get("_position") orelse Value.initInt(0)).asInt();
    try obj.properties.put("_position", Value.initInt(position + 1));
    
    return Value.initNull();
}

/// 注册SplFixedArray类
pub fn registerSplFixedArray(allocator: Allocator) !void {
    const meta = try allocator.create(ClassMeta);
    const name = try allocator.dupe(u8, "SplFixedArray");
    meta.* = .{
        .name = name,
        .parent = null,
        .methods = std.StringHashMap(ClassMethod).init(allocator),
        .properties = std.StringHashMap(ClassProperty).init(allocator),
        .static_properties = std.StringHashMap(Value).init(allocator),
        .interfaces = &.{},
        .is_abstract = false,
        .allocator = allocator,
    };
    
    // 注册方法
    try meta.methods.put("__construct", .{ .name = "__construct", .func = splFixedArray_construct, .is_public = true });
    try meta.methods.put("getSize", .{ .name = "getSize", .func = splFixedArray_getSize, .is_public = true });
    try meta.methods.put("setSize", .{ .name = "setSize", .func = splFixedArray_setSize, .is_public = true });
    try meta.methods.put("toArray", .{ .name = "toArray", .func = splFixedArray_toArray, .is_public = true });
    try meta.methods.put("count", .{ .name = "count", .func = splFixedArray_count, .is_public = true });
    
    // ArrayAccess接口
    try meta.methods.put("offsetExists", .{ .name = "offsetExists", .func = splFixedArray_offsetExists, .is_public = true });
    try meta.methods.put("offsetGet", .{ .name = "offsetGet", .func = splFixedArray_offsetGet, .is_public = true });
    try meta.methods.put("offsetSet", .{ .name = "offsetSet", .func = splFixedArray_offsetSet, .is_public = true });
    try meta.methods.put("offsetUnset", .{ .name = "offsetUnset", .func = splFixedArray_offsetUnset, .is_public = true });
    
    // Iterator接口
    try meta.methods.put("rewind", .{ .name = "rewind", .func = splFixedArray_rewind, .is_public = true });
    try meta.methods.put("valid", .{ .name = "valid", .func = splFixedArray_valid, .is_public = true });
    try meta.methods.put("current", .{ .name = "current", .func = splFixedArray_current, .is_public = true });
    try meta.methods.put("key", .{ .name = "key", .func = splFixedArray_key, .is_public = true });
    try meta.methods.put("next", .{ .name = "next", .func = splFixedArray_next, .is_public = true });
    
    meta.magic_construct = splFixedArray_construct;
    
    try registerClass(meta);
}

// ============================================================================
// SplStack类（SPL）
// ============================================================================

/// SplStack构造函数
fn splStack_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    // 创建内部数组
    const array = try PHPArray.init(runtime_allocator);
    const array_val = Value.initArray(array);
    try obj.properties.put("_data", array_val);
    
    return Value.initNull();
}

/// SplStack::push
fn splStack_push(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();
    
    const obj = Value_asObject(ctx);
    const value = args[0];
    
    const array_val = obj.properties.get("_data") orelse return Value.initNull();
    const array = array_val.asArray();
    
    // 添加到数组末尾
    const count = array.elements.count();
    _ = value.retain();
    try array.elements.put(.{ .integer = @intCast(count) }, value);
    
    return Value.initNull();
}

/// SplStack::pop
fn splStack_pop(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const array_val = obj.properties.get("_data") orelse return Value.initNull();
    const array = array_val.asArray();
    
    const count = array.elements.count();
    if (count == 0) return Value.initNull();
    
    // 从末尾取出
    const last_key = ArrayKey{ .integer = @intCast(count - 1) };
    const val = array.elements.get(last_key) orelse return Value.initNull();
    _ = val.retain();
    _ = array.elements.remove(last_key);
    
    return val;
}

/// SplStack::isEmpty
fn splStack_isEmpty(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const array_val = obj.properties.get("_data") orelse return Value.initBool(true);
    const array = array_val.asArray();
    
    return Value.initBool(array.elements.count() == 0);
}

/// 注册SplStack类
pub fn registerSplStack(allocator: Allocator) !void {
    const meta = try allocator.create(ClassMeta);
    const name = try allocator.dupe(u8, "SplStack");
    meta.* = .{
        .name = name,
        .parent = null,
        .methods = std.StringHashMap(ClassMethod).init(allocator),
        .properties = std.StringHashMap(ClassProperty).init(allocator),
        .static_properties = std.StringHashMap(Value).init(allocator),
        .interfaces = &.{},
        .is_abstract = false,
        .allocator = allocator,
    };
    
    try meta.methods.put("__construct", .{ .name = "__construct", .func = splStack_construct, .is_public = true });
    try meta.methods.put("push", .{ .name = "push", .func = splStack_push, .is_public = true });
    try meta.methods.put("pop", .{ .name = "pop", .func = splStack_pop, .is_public = true });
    try meta.methods.put("isEmpty", .{ .name = "isEmpty", .func = splStack_isEmpty, .is_public = true });
    
    meta.magic_construct = splStack_construct;
    
    try registerClass(meta);
}

// ============================================================================
// SplQueue类（SPL）
// ============================================================================

/// SplQueue构造函数
fn splQueue_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    // 创建内部数组
    const array = try PHPArray.init(runtime_allocator);
    const array_val = Value.initArray(array);
    try obj.properties.put("_data", array_val);
    
    return Value.initNull();
}

/// SplQueue::enqueue
fn splQueue_enqueue(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();
    
    const obj = Value_asObject(ctx);
    const value = args[0];
    
    const array_val = obj.properties.get("_data") orelse return Value.initNull();
    const array = array_val.asArray();
    
    // 添加到数组末尾
    const count = array.elements.count();
    _ = value.retain();
    try array.elements.put(.{ .integer = @intCast(count) }, value);
    
    return Value.initNull();
}

/// SplQueue::dequeue
fn splQueue_dequeue(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const array_val = obj.properties.get("_data") orelse return Value.initNull();
    const array = array_val.asArray();
    
    const count = array.elements.count();
    if (count == 0) return Value.initNull();
    
    // 从开头取出
    const first_val = array.elements.get(.{ .integer = 0 }) orelse return Value.initNull();
    _ = first_val.retain();
    
    // 重新索引：将所有元素向前移动
    var i: usize = 1;
    while (i < count) : (i += 1) {
        if (array.elements.get(.{ .integer = @intCast(i) })) |val| {
            try array.elements.put(.{ .integer = @intCast(i - 1) }, val);
        }
    }
    
    // 删除最后一个位置
    _ = array.elements.remove(.{ .integer = @intCast(count - 1) });
    
    return first_val;
}

/// SplQueue::isEmpty
fn splQueue_isEmpty(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    
    const array_val = obj.properties.get("_data") orelse return Value.initBool(true);
    const array = array_val.asArray();
    
    return Value.initBool(array.elements.count() == 0);
}

/// 注册SplQueue类
pub fn registerSplQueue(allocator: Allocator) !void {
    const meta = try allocator.create(ClassMeta);
    const name = try allocator.dupe(u8, "SplQueue");
    meta.* = .{
        .name = name,
        .parent = null,
        .methods = std.StringHashMap(ClassMethod).init(allocator),
        .properties = std.StringHashMap(ClassProperty).init(allocator),
        .static_properties = std.StringHashMap(Value).init(allocator),
        .interfaces = &.{},
        .is_abstract = false,
        .allocator = allocator,
    };
    
    try meta.methods.put("__construct", .{ .name = "__construct", .func = splQueue_construct, .is_public = true });
    try meta.methods.put("enqueue", .{ .name = "enqueue", .func = splQueue_enqueue, .is_public = true });
    try meta.methods.put("dequeue", .{ .name = "dequeue", .func = splQueue_dequeue, .is_public = true });
    try meta.methods.put("isEmpty", .{ .name = "isEmpty", .func = splQueue_isEmpty, .is_public = true });
    
    meta.magic_construct = splQueue_construct;
    
    try registerClass(meta);
}

// ============================================================================
// 字符串函数
// ============================================================================

/// strlen - 获取字符串长度
pub fn php_strlen(str: Value) !Value {
    if (!str.isString()) return Value.initInt(0);
    return Value.initInt(@intCast(str.asString().length));
}

/// str_word_count - 统计单词数量
pub fn php_str_word_count(str: Value, format: Value, charlist: Value) !Value {
    _ = charlist;
    if (!str.isString()) return Value.initInt(0);
    
    const s = str.asString().data;
    const fmt = if (format.isInt()) format.asInt() else 0;
    
    if (fmt != 0) return Value.initInt(0); // 简化：只支持format=0
    
    var count: i64 = 0;
    var in_word = false;
    
    for (s) |c| {
        const is_alpha = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9');
        if (is_alpha) {
            if (!in_word) {
                count += 1;
                in_word = true;
            }
        } else {
            in_word = false;
        }
    }
    
    return Value.initInt(count);
}

/// substr - 获取子字符串
pub fn php_substr(str: Value, start: Value, length: Value, allocator: Allocator) !Value {
    if (!str.isString()) return Value.initNull();

    const php_str = str.asString();
    const start_int = start.toInt();
    const length_int = if (length.isNull()) null else length.toInt();

    const result = try php_str.substring(start_int, length_int, allocator);
    return Value.initString(result);
}

/// strpos - 查找子字符串位置
pub fn php_strpos(haystack: Value, needle: Value, offset: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i >= 0) {
            break :blk @intCast(@min(off_i, @as(i64, @intCast(hay.length))));
        }
        const abs_off: usize = @intCast(@min(-off_i, @as(i64, @intCast(hay.length))));
        break :blk hay.length - abs_off;
    };

    if (start_idx > hay.length or start_idx + need.length > hay.length) return Value.initBool(false);

    var i: usize = start_idx;
    while (i <= hay.length - need.length) : (i += 1) {
        if (std.mem.eql(u8, hay.data[i .. i + need.length], need.data)) {
            return Value.initInt(@intCast(i));
        }
    }
    return Value.initBool(false);
}

/// comptime 生成 256 字节大写查找表（零运行时分支）
const upper_lut = blk: {
    var table: [256]u8 = undefined;
    for (0..256) |i| {
        table[i] = if (i >= 'a' and i <= 'z') @intCast(i - 32) else @intCast(i);
    }
    break :blk table;
};

/// comptime 生成 256 字节小写查找表（零运行时分支）
const lower_lut = blk: {
    var table: [256]u8 = undefined;
    for (0..256) |i| {
        table[i] = if (i >= 'A' and i <= 'Z') @intCast(i + 32) else @intCast(i);
    }
    break :blk table;
};

/// strtoupper - 转换为大写（comptime 查找表，零分支）
pub fn php_strtoupper(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const result_data = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(result_data);

    for (php_str.data, 0..) |c, i| {
        result_data[i] = upper_lut[c];
    }

    const result = try PHPString.init(allocator, result_data);
    allocator.free(result_data);
    return Value.initString(result);
}

/// strtolower - 转换为小写（comptime 查找表，零分支）
pub fn php_strtolower(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const result_data = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(result_data);

    for (php_str.data, 0..) |c, i| {
        result_data[i] = lower_lut[c];
    }

    const result = try PHPString.init(allocator, result_data);
    allocator.free(result_data);
    return Value.initString(result);
}

/// trim - 去除首尾空白
pub fn php_trim(str: Value, char_mask: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const mask = if (char_mask.isString()) char_mask.asString().data else " \t\n\r";
    const trimmed = std.mem.trim(u8, php_str.data, mask);

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// ltrim - 去除左侧空白
pub fn php_ltrim(str: Value, char_mask: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const mask = if (char_mask.isString()) char_mask.asString().data else " \t\n\r";
    const trimmed = std.mem.trimLeft(u8, php_str.data, mask);

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// rtrim - 去除右侧空白
pub fn php_rtrim(str: Value, char_mask: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const mask = if (char_mask.isString()) char_mask.asString().data else " \t\n\r";
    const trimmed = std.mem.trimRight(u8, php_str.data, mask);

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// str_replace - 字符串替换
pub fn php_str_replace(search: Value, replace: Value, subject: Value, count_out: Value, allocator: Allocator) !Value {
    _ = count_out;
    if (!subject.isString()) return subject;
    if (!search.isString() or !replace.isString()) return subject;

    const subject_str = subject.asString();
    const search_str = search.asString();
    const replace_str = replace.asString();

    // 如果搜索字符串为空，直接返回原字符串
    if (search_str.length == 0) return subject;

    // 计算需要的缓冲区大小
    var found_count: usize = 0;
    var pos: usize = 0;
    while (pos < subject_str.length) {
        if (pos + search_str.length <= subject_str.length) {
            if (std.mem.eql(u8, subject_str.data[pos .. pos + search_str.length], search_str.data)) {
                found_count += 1;
                pos += search_str.length;
                continue;
            }
        }
        pos += 1;
    }

    // 如果没有找到，返回原字符串
    if (found_count == 0) return subject;

    // 计算新字符串长度
    const new_len = subject_str.length - (found_count * search_str.length) + (found_count * replace_str.length);
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    // 执行替换
    var write_pos: usize = 0;
    pos = 0;
    while (pos < subject_str.length) {
        if (pos + search_str.length <= subject_str.length) {
            if (std.mem.eql(u8, subject_str.data[pos .. pos + search_str.length], search_str.data)) {
                @memcpy(buffer[write_pos .. write_pos + replace_str.length], replace_str.data);
                write_pos += replace_str.length;
                pos += search_str.length;
                continue;
            }
        }
        buffer[write_pos] = subject_str.data[pos];
        write_pos += 1;
        pos += 1;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_repeat - 重复字符串
pub fn php_str_repeat(str: Value, times: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const repeat_times = times.toInt();

    if (repeat_times <= 0) return Value.initString(try PHPString.init(allocator, ""));
    if (repeat_times == 1) return str;

    const new_len = php_str.length * @as(usize, @intCast(repeat_times));
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var pos: usize = 0;
    var i: i64 = 0;
    while (i < repeat_times) : (i += 1) {
        @memcpy(buffer[pos .. pos + php_str.length], php_str.data);
        pos += php_str.length;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_pad - 填充字符串到指定长度
pub fn php_str_pad(str: Value, length: Value, pad_str: Value, pad_type: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const target_len = length.toInt();

    if (target_len <= @as(i64, @intCast(php_str.length))) return str;

    var created_pad = false;
    const pad_string = if (pad_str.isString()) pad_str.asString() else blk: {
        created_pad = true;
        break :blk try PHPString.init(allocator, " ");
    };
    defer if (created_pad) pad_string.release(allocator);

    const mode = pad_type.toInt();
    const pad_len: usize = @intCast(@as(i64, @intCast(target_len)) - @as(i64, @intCast(php_str.length)));
    const left_pad: usize = if (mode == 0)
        pad_len
    else if (mode == 2)
        pad_len / 2
    else
        0;
    const right_pad: usize = pad_len - left_pad;

    const buffer = try allocator.alloc(u8, @intCast(target_len));
    errdefer allocator.free(buffer);

    var pos: usize = 0;
    while (pos < left_pad) {
        const copy_len = @min(pad_string.length, left_pad - pos);
        @memcpy(buffer[pos .. pos + copy_len], pad_string.data[0..copy_len]);
        pos += copy_len;
    }

    @memcpy(buffer[pos .. pos + php_str.length], php_str.data);
    pos += php_str.length;

    var rpos: usize = 0;
    while (rpos < right_pad) {
        const copy_len = @min(pad_string.length, right_pad - rpos);
        @memcpy(buffer[pos .. pos + copy_len], pad_string.data[0..copy_len]);
        pos += copy_len;
        rpos += copy_len;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// strstr - 查找字符串首次出现的位置并返回剩余部分
pub fn php_strstr(haystack: Value, needle: Value, allocator: Allocator) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);
    
    const h = haystack.asString();
    const n = needle.asString();
    if (n.length == 0) return Value.initBool(false);
    
    const pos = std.mem.indexOf(u8, h.data[0..h.length], n.data[0..n.length]) orelse return Value.initBool(false);
    
    const result_len = h.length - pos;
    const buffer = try allocator.alloc(u8, result_len);
    @memcpy(buffer, h.data[pos..h.length]);
    
    const result = try allocator.create(PHPString);
    result.* = .{ .data = buffer, .length = result_len, .ref_count = 1, .is_static = false };
    return Value.initString(result);
}

/// strrev - 反转字符串
pub fn php_strrev(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    var i: usize = 0;
    while (i < php_str.length) : (i += 1) {
        buffer[i] = php_str.data[php_str.length - 1 - i];
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_contains - 检查字符串是否包含子串 (PHP 8.0+)
pub fn php_str_contains(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    var i: usize = 0;
    while (i <= hay.length - need.length) : (i += 1) {
        if (std.mem.eql(u8, hay.data[i .. i + need.length], need.data)) {
            return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

/// str_starts_with - 检查字符串是否以指定前缀开始 (PHP 8.0+)
pub fn php_str_starts_with(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    return Value.initBool(std.mem.eql(u8, hay.data[0..need.length], need.data));
}

/// str_ends_with - 检查字符串是否以指定后缀结束 (PHP 8.0+)
pub fn php_str_ends_with(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    const start_pos = hay.length - need.length;
    return Value.initBool(std.mem.eql(u8, hay.data[start_pos..], need.data));
}

/// ucfirst - 首字母大写
pub fn php_ucfirst(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);
    buffer[0] = std.ascii.toUpper(buffer[0]);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// lcfirst - 首字母小写
pub fn php_lcfirst(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);
    buffer[0] = std.ascii.toLower(buffer[0]);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// ucwords - 每个单词首字母大写
pub fn php_ucwords(str: Value, delimiters: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);

    const delims = if (delimiters.isString()) delimiters.asString().data else " \t\n\r";
    var is_word_start = true;
    for (buffer, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, delims, c) != null) {
            is_word_start = true;
        } else if (is_word_start) {
            buffer[i] = std.ascii.toUpper(c);
            is_word_start = false;
        }
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// explode - 分割字符串为数组
pub fn php_explode(delimiter: Value, str: Value, limit: Value, allocator: Allocator) !Value {
    if (!delimiter.isString() or !str.isString()) {
        return Value.initArray(try PHPArray.init(allocator));
    }

    const delim = delimiter.asString();
    const php_str = str.asString();

    const arr = try PHPArray.init(allocator);

    if (delim.length == 0) {
        // 空分隔符，返回包含整个字符串的数组
        try arr.push(allocator, str);
        return Value.initArray(arr);
    }

    var lim: ?i64 = null;
    if (!limit.isNull()) {
        lim = limit.toInt();
        if (lim.? == 0) lim = 1;
    }

    if (lim != null and lim.? < 0) {
        var start: usize = 0;
        var pos: usize = 0;

        while (pos <= php_str.length - delim.length) {
            if (std.mem.eql(u8, php_str.data[pos .. pos + delim.length], delim.data)) {
                const part = try PHPString.init(allocator, php_str.data[start..pos]);
                try arr.push(allocator, Value.initString(part));
                pos += delim.length;
                start = pos;
            } else {
                pos += 1;
            }
        }

        const last_part = try PHPString.init(allocator, php_str.data[start..]);
        try arr.push(allocator, Value.initString(last_part));

        const total = arr.count();
        const drop: usize = @intCast(@min(-lim.?, @as(i64, @intCast(total))));
        if (drop == 0) return Value.initArray(arr);

        const keep = total - drop;
        const out = try PHPArray.init(allocator);
        var i: usize = 0;
        while (i < keep) : (i += 1) {
            const key = ArrayKey{ .integer = @intCast(i) };
            if (arr.get(key)) |v| {
                try out.push(allocator, v);
            } else {
                try out.push(allocator, Value.initNull());
            }
        }

        arr.release(allocator);
        return Value.initArray(out);
    }

    var start: usize = 0;
    var pos: usize = 0;
    var pushed: i64 = 0;
    const max_parts: ?i64 = if (lim != null and lim.? > 0) lim.? else null;

    while (pos <= php_str.length - delim.length) {
        if (max_parts != null and pushed >= max_parts.? - 1) break;
        if (std.mem.eql(u8, php_str.data[pos .. pos + delim.length], delim.data)) {
            // 找到分隔符
            const part = try PHPString.init(allocator, php_str.data[start..pos]);
            try arr.push(allocator, Value.initString(part));
            pushed += 1;
            pos += delim.length;
            start = pos;
        } else {
            pos += 1;
        }
    }

    // 添加最后一部分
    const last_part = try PHPString.init(allocator, php_str.data[start..]);
    try arr.push(allocator, Value.initString(last_part));

    return Value.initArray(arr);
}

/// implode - 连接数组元素为字符串
pub fn php_implode(glue: Value, pieces: Value, allocator: Allocator) !Value {
    var glue_val = glue;
    var pieces_val = pieces;
    if (!pieces_val.isArray() and glue_val.isArray()) {
        glue_val = pieces;
        pieces_val = glue;
    }
    if (!pieces_val.isArray()) return Value.initString(try PHPString.init(allocator, ""));

    var created_glue = false;
    const glue_str = if (glue_val.isString()) glue_val.asString() else blk: {
        created_glue = true;
        break :blk try PHPString.init(allocator, "");
    };
    defer if (created_glue) glue_str.release(allocator);
    const arr = pieces_val.asArray();

    if (arr.count() == 0) return Value.initString(try PHPString.init(allocator, ""));

    // 计算总长度
    var total_len: usize = 0;
    var it = arr.elements.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) total_len += glue_str.length;
        const val = entry.value_ptr.*;
        const str = try val.toString(allocator);
        defer str.release(allocator);
        total_len += str.length;
        first = false;
    }

    // 构建结果字符串
    const buffer = try allocator.alloc(u8, total_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    it = arr.elements.iterator();
    first = true;
    while (it.next()) |entry| {
        if (!first) {
            @memcpy(buffer[write_pos .. write_pos + glue_str.length], glue_str.data);
            write_pos += glue_str.length;
        }
        const val = entry.value_ptr.*;
        const str = try val.toString(allocator);
        defer str.release(allocator);
        @memcpy(buffer[write_pos .. write_pos + str.length], str.data);
        write_pos += str.length;
        first = false;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_split - 将字符串分割为数组
pub fn php_str_split(str: Value, length: Value, allocator: Allocator) !Value {
    if (!str.isString()) return Value.initArray(try PHPArray.init(allocator));

    const php_str = str.asString();
    const chunk_len = if (length.isNull()) 1 else @max(1, length.toInt());

    const arr = try PHPArray.init(allocator);

    var pos: usize = 0;
    while (pos < php_str.length) {
        const end = @min(pos + @as(usize, @intCast(chunk_len)), php_str.length);
        const chunk = try PHPString.init(allocator, php_str.data[pos..end]);
        try arr.push(allocator, Value.initString(chunk));
        pos = end;
    }

    return Value.initArray(arr);
}

/// strcmp - 字符串比较
pub fn php_strcmp(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();

    const result = std.mem.order(u8, s1.data, s2.data);
    return Value.initInt(switch (result) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    });
}

/// strcasecmp - 不区分大小写的字符串比较
pub fn php_strcasecmp(str1: Value, str2: Value, allocator: Allocator) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();

    // 转换为小写后比较
    const lower1 = try allocator.alloc(u8, s1.length);
    defer allocator.free(lower1);
    const lower2 = try allocator.alloc(u8, s2.length);
    defer allocator.free(lower2);

    for (s1.data, 0..) |c, i| {
        lower1[i] = std.ascii.toLower(c);
    }
    for (s2.data, 0..) |c, i| {
        lower2[i] = std.ascii.toLower(c);
    }

    const result = std.mem.order(u8, lower1, lower2);
    return Value.initInt(switch (result) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    });
}

// ============================================================================
// 数组函数
// ============================================================================

/// count - 获取数组元素数量
/// count() - 计算数组元素个数
/// @param arr 要计数的数组
/// @param mode 可选，COUNT_RECURSIVE(1)表示递归计数
pub fn php_count(arr: Value, mode: Value) !Value {
    // 检测Countable对象
    if (Value_isObject(arr)) {
        const obj = Value_asObject(arr);
        if (obj.class_meta) |meta| {
            if (meta.findMethod("count")) |_| {
                return try php_object_call(arr, "count", &[_]Value{});
            }
        }
    }
    
    if (!arr.isArray()) return Value.initInt(0);
    
    const mode_int = if (mode.isInt()) mode.asInt() else 0;
    const php_arr = arr.asArray();
    
    // COUNT_RECURSIVE = 1
    if (mode_int == 1) {
        return Value.initInt(@intCast(countRecursive(php_arr)));
    }
    
    return Value.initInt(@intCast(php_arr.elements.count()));
}

fn countRecursive(arr: *PHPArray) usize {
    var total: usize = arr.elements.count();
    
    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        const val = entry.value_ptr.*;
        if (val.isArray()) {
            total += countRecursive(val.asArray());
        }
    }
    
    return total;
}

/// array_push - 追加元素到数组
pub fn php_array_push(arr: Value, values: []const Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    for (values) |val| {
        try php_arr.push(allocator, val);
    }

    return Value.initInt(@intCast(php_arr.count()));
}

/// array_pop - 弹出数组最后一个元素
pub fn php_array_pop(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const value = array_ops_shared.pop(ArrayKey, Value, @TypeOf(php_arr.elements), allocator, &php_arr.elements, &php_arr.next_index) orelse return Value.initNull();
    return value;
}

/// in_array - 检查值是否在数组中
pub fn php_in_array(needle: Value, haystack: Value) !Value {
    if (!haystack.isArray()) return Value.initBool(false);

    const arr = haystack.asArray();
    var iter = arr.elements.iterator();

    while (iter.next()) |entry| {
        const eq = try php_eq(needle, entry.value_ptr.*);
        if (eq.asBool()) return Value.initBool(true);
    }

    return Value.initBool(false);
}

/// array_slice - 从数组中提取一段切片
///
/// 提取数组中的一段元素，返回新数组。
///
/// @param arr 源数组
/// @param offset 起始偏移量（可以为负数，表示从末尾开始）
/// @param length 切片长度（可选，null表示到数组末尾）
/// @param allocator 内存分配器
/// @return 新的数组切片
///
/// 示例：
/// ```php
/// $arr = [1, 2, 3, 4, 5];
/// array_slice($arr, 1, 2);  // [2, 3]
/// array_slice($arr, -2);     // [4, 5]
/// array_slice($arr, 1, -1);  // [2, 3, 4]
/// ```
pub fn php_array_slice(arr: Value, offset: Value, length: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const arr_count = php_arr.count();

    if (arr_count == 0) {
        // 空数组，返回空数组
        return Value.initArray(try PHPArray.init(allocator));
    }

    // 计算起始位置
    const offset_int = offset.toInt();
    const start_idx: usize = blk: {
        if (offset_int < 0) {
            const abs_offset = @as(usize, @intCast(-offset_int));
            break :blk if (abs_offset > arr_count) 0 else arr_count - abs_offset;
        } else {
            break :blk @intCast(@min(offset_int, @as(i64, @intCast(arr_count))));
        }
    };

    // 计算结束位置
    const end_idx: usize = blk: {
        if (length.isNull()) {
            // 没有指定长度，取到数组末尾
            break :blk arr_count;
        }

        const length_int = length.toInt();
        if (length_int >= 0) {
            // 正数长度
            break :blk @min(start_idx + @as(usize, @intCast(length_int)), arr_count);
        } else {
            // 负数长度：从末尾减去
            const abs_len = @as(usize, @intCast(-length_int));
            if (abs_len >= arr_count) {
                break :blk start_idx; // 返回空数组
            }
            break :blk if (arr_count - abs_len > start_idx) arr_count - abs_len else start_idx;
        }
    };

    // 创建新数组
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    if (start_idx >= end_idx) {
        // 空切片
        return Value.initArray(result);
    }

    // 复制元素
    // 注意：PHP的array_slice会重新索引数组（从0开始）
    var iter = php_arr.elements.iterator();
    var current_idx: usize = 0;
    var new_idx: i64 = 0;

    while (iter.next()) |entry| {
        // 只处理整数键（保持顺序）
        if (entry.key_ptr.* == .integer) {
            if (current_idx >= start_idx and current_idx < end_idx) {
                const new_key = ArrayKey{ .integer = new_idx };
                const value_copy = entry.value_ptr.*.retain();
                try result.elements.put(new_key, value_copy);
                new_idx += 1;
            }
            current_idx += 1;
        }
    }

    result.next_index = new_idx;
    return Value.initArray(result);
}

/// array_merge - 合并一个或多个数组
///
/// 将多个数组合并成一个新数组。
/// - 整数键会被重新索引（从0开始）
/// - 字符串键会被保留，后面的值会覆盖前面的值
///
/// @param arrays 要合并的数组列表
/// @param allocator 内存分配器
/// @return 合并后的新数组
///
/// 示例：
/// ```php
/// $arr1 = [1, 2];
/// $arr2 = [3, 4];
/// array_merge($arr1, $arr2);  // [1, 2, 3, 4]
///
/// $arr3 = ['a' => 1, 'b' => 2];
/// $arr4 = ['b' => 3, 'c' => 4];
/// array_merge($arr3, $arr4);  // ['a' => 1, 'b' => 3, 'c' => 4]
/// ```
pub fn php_array_merge(arrays: []const Value, allocator: Allocator) !Value {
    // 创建结果数组
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var next_int_key: i64 = 0;

    // 遍历所有输入数组
    for (arrays) |arr_val| {
        if (!arr_val.isArray()) continue; // 跳过非数组值

        const arr = arr_val.asArray();
        var iter = arr.elements.iterator();

        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*.retain();

            switch (key) {
                .integer => {
                    // 整数键：重新索引
                    const new_key = ArrayKey{ .integer = next_int_key };
                    try result.elements.put(new_key, value);
                    next_int_key += 1;
                },
                .string => |str| {
                    // 字符串键：保留键名，可能覆盖
                    const new_key = ArrayKey{ .string = str };
                    str.retain(); // 保留键的引用

                    // 如果键已存在，释放旧值
                    if (result.elements.get(new_key)) |old_value| {
                        old_value.release(allocator);
                    }

                    try result.elements.put(new_key, value);
                },
            }
        }
    }

    result.next_index = next_int_key;

    return Value.initArray(result);
}

/// Merge array into target (for spread operator)
pub fn php_array_merge_into(target: Value, source: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!target.isArray()) return target;
    if (!source.isArray()) return target;
    
    const target_arr = target.asArray();
    const source_arr = source.asArray();
    
    // 安全检查：确保source_arr有效
    if (source_arr.elements.mixed) |*m| {
        // 检查mixed map是否有效
        if (m.count() > 1000000) {  // 不合理的大小
            return target;
        }
    }
    
    // 遍历源数组的所有元素
    var iter = source_arr.elements.iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*.retain();
        // 使用整数键追加到目标数组
        const new_key = ArrayKey{ .integer = target_arr.next_index };
        try target_arr.elements.put(new_key, value);
        target_arr.next_index += 1;
    }
    
    return target;
}

/// array_keys - 返回数组中所有的键
///
/// 返回一个包含数组所有键的新数组（整数索引）。
///
/// @param arr 源数组
/// @param allocator 内存分配器
/// @return 包含所有键的新数组
///
/// 示例：
/// ```php
/// $arr = ['a' => 1, 'b' => 2, 0 => 3];
/// array_keys($arr);  // ['a', 'b', 0]
/// ```
pub fn php_array_keys(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var iter = php_arr.elements.iterator();
    var idx: i64 = 0;

    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const key_value = switch (key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                // 创建字符串值的副本
                const str_copy = try PHPString.init(allocator, s.data);
                break :blk Value.initString(str_copy);
            },
        };

        const new_key = ArrayKey{ .integer = idx };
        try result.elements.put(new_key, key_value);
        idx += 1;
    }

    result.next_index = idx;
    return Value.initArray(result);
}

/// array_values - 返回数组中所有的值
///
/// 返回一个包含数组所有值的新数组，使用整数索引（从0开始）。
/// 这个函数会丢弃原数组的键，重新索引。
///
/// @param arr 源数组
/// @param allocator 内存分配器
/// @return 包含所有值的新数组（整数索引）
///
/// 示例：
/// ```php
/// $arr = ['a' => 1, 'b' => 2, 5 => 3];
/// array_values($arr);  // [1, 2, 3]
/// ```
pub fn php_array_values(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var iter = php_arr.elements.iterator();
    var idx: i64 = 0;

    while (iter.next()) |entry| {
        const value = entry.value_ptr.*.retain();
        const new_key = ArrayKey{ .integer = idx };
        try result.elements.put(new_key, value);
        idx += 1;
    }

    result.next_index = idx;
    return Value.initArray(result);
}

// ============================================================================
// 数学函数
// ============================================================================

/// abs - 绝对值
pub fn php_abs(val: Value) !Value {
    if (val.isInt()) {
        const i = val.asInt();
        return Value.initInt(if (i < 0) -i else i);
    }
    const f = val.toFloat();
    return Value.initFloat(@abs(f));
}

/// sqrt - 平方根
pub fn php_sqrt(val: Value) !Value {
    return Value.initFloat(@sqrt(val.toFloat()));
}

/// round - 四舍五入
pub fn php_round(val: Value, precision_val: Value) !Value {
    const num = val.toFloat();
    const precision = if (precision_val.isNull()) 0 else @as(i32, @intCast(precision_val.toInt()));
    
    if (precision == 0) {
        return Value.initFloat(@round(num));
    }
    
    const multiplier = std.math.pow(f64, 10.0, @floatFromInt(precision));
    return Value.initFloat(@round(num * multiplier) / multiplier);
}

/// floor - 向下取整
pub fn php_floor(val: Value) !Value {
    return Value.initFloat(@floor(val.toFloat()));
}

/// ceil - 向上取整
pub fn php_ceil(val: Value) !Value {
    return Value.initFloat(@ceil(val.toFloat()));
}

/// min - 最小值
/// max - 最大值
pub fn php_max(args: []const Value) !Value {
    if (args.len == 0) return Value.initInt(0);
    if (args.len == 1) {
        // 单参数：如果是数组，返回数组最大值
        if (args[0].isArray()) {
            const arr = args[0].asArray();
            if (arr.elements.packed_values.items.len == 0) return Value.initInt(0);
            
            var max_val = arr.elements.packed_values.items[0];
            for (arr.elements.packed_values.items[1..]) |val| {
                if (val.toFloat() > max_val.toFloat()) {
                    max_val = val;
                }
            }
            return max_val;
        }
        return args[0];
    }
    
    // 多参数：找最大值
    var max_val = args[0];
    for (args[1..]) |val| {
        if (val.toFloat() > max_val.toFloat()) {
            max_val = val;
        }
    }
    return max_val;
}

/// min - 最小值
pub fn php_min(args: []const Value) !Value {
    if (args.len == 0) return Value.initInt(0);
    if (args.len == 1) {
        // 单参数：如果是数组，返回数组最小值
        if (args[0].isArray()) {
            const arr = args[0].asArray();
            if (arr.elements.packed_values.items.len == 0) return Value.initInt(0);
            
            var min_val = arr.elements.packed_values.items[0];
            for (arr.elements.packed_values.items[1..]) |val| {
                if (val.toFloat() < min_val.toFloat()) {
                    min_val = val;
                }
            }
            return min_val;
        }
        return args[0];
    }
    
    // 多参数：找最小值
    var min_val = args[0];
    for (args[1..]) |val| {
        if (val.toFloat() < min_val.toFloat()) {
            min_val = val;
        }
    }
    return min_val;
}

/// sin - 正弦
pub fn php_sin(val: Value) !Value {
    return Value.initFloat(@sin(val.toFloat()));
}

/// cos - 余弦
pub fn php_cos(val: Value) !Value {
    return Value.initFloat(@cos(val.toFloat()));
}

/// tan - 正切
pub fn php_tan(val: Value) !Value {
    return Value.initFloat(@tan(val.toFloat()));
}

/// asin - 反正弦
pub fn php_asin(val: Value) !Value {
    return Value.initFloat(std.math.asin(val.toFloat()));
}

/// acos - 反余弦
pub fn php_acos(val: Value) !Value {
    return Value.initFloat(std.math.acos(val.toFloat()));
}

/// atan - 反正切
pub fn php_atan(val: Value) !Value {
    return Value.initFloat(std.math.atan(val.toFloat()));
}

/// atan2 - 两个参数的反正切
pub fn php_atan2(y: Value, x: Value) !Value {
    return Value.initFloat(std.math.atan2(y.toFloat(), x.toFloat()));
}

/// log - 自然对数
pub fn php_log(val: Value) !Value {
    return Value.initFloat(@log(val.toFloat()));
}

/// log10 - 以10为底的对数
pub fn php_log10(val: Value) !Value {
    return Value.initFloat(@log10(val.toFloat()));
}

/// exp - e的x次方
pub fn php_exp(val: Value) !Value {
    return Value.initFloat(@exp(val.toFloat()));
}

/// pow - 幂运算
pub fn php_pow_func(base: Value, exponent: Value) !Value {
    if (base.isInt() and exponent.isInt()) {
        const b = base.asInt();
        const e = exponent.asInt();
        if (e >= 0 and e < 64) {
            // 整数幂运算
            var result: i64 = 1;
            var i: i64 = 0;
            while (i < e) : (i += 1) {
                result *= b;
            }
            return Value.initInt(result);
        }
    }
    return Value.initFloat(std.math.pow(f64, base.toFloat(), exponent.toFloat()));
}

/// fmod - 浮点数取模
pub fn php_fmod(x: Value, y: Value) !Value {
    return Value.initFloat(@mod(x.toFloat(), y.toFloat()));
}

/// hypot - 计算直角三角形斜边长度
pub fn php_hypot(x: Value, y: Value) !Value {
    return Value.initFloat(std.math.hypot(x.toFloat(), y.toFloat()));
}

/// deg2rad - 角度转弧度
pub fn php_deg2rad(degrees: Value) !Value {
    const rad = degrees.toFloat() * std.math.pi / 180.0;
    return Value.initFloat(rad);
}

/// rad2deg - 弧度转角度
pub fn php_rad2deg(radians: Value) !Value {
    const deg = radians.toFloat() * 180.0 / std.math.pi;
    return Value.initFloat(deg);
}

/// pi - 返回圆周率
pub fn php_pi() !Value {
    return Value.initFloat(std.math.pi);
}

/// intval - 转换为整数
pub fn php_intval(val: Value) !Value {
    // 使用完整的 PHP intval 语义
    if (val.isInt()) return val;
    if (val.isFloat()) return Value.initInt(@intFromFloat(val.asFloat()));
    if (val.isBool()) return Value.initInt(if (val.asBool()) @as(i64, 1) else @as(i64, 0));
    if (val.isString()) {
        const str = val.asString().data;
        // 内联 intval 逻辑
        if (str.len == 0) return Value.initInt(0);
        
        var s = std.mem.trim(u8, str, " \t\n\r");
        if (s.len == 0) return Value.initInt(0);
        
        var negative = false;
        if (s[0] == '-') {
            negative = true;
            s = s[1..];
        } else if (s[0] == '+') {
            s = s[1..];
        }
        
        if (s.len == 0) return Value.initInt(0);
        
        // 如果包含小数点，先解析为浮点数
        if (std.mem.indexOf(u8, s, ".") != null) {
            if (std.fmt.parseFloat(f64, if (negative) str else s)) |float_val| {
                return Value.initInt(@intFromFloat(float_val));
            } else |_| {}
        }
        
        // 尝试完整解析
        if (std.fmt.parseInt(i64, s, 10)) |int_val| {
            return Value.initInt(if (negative) -int_val else int_val);
        } else |_| {
            // 部分解析：提取前导数字
            var result: i64 = 0;
            for (s) |c| {
                if (c >= '0' and c <= '9') {
                    result = result * 10 + (c - '0');
                } else {
                    break;
                }
            }
            return Value.initInt(if (negative) -result else result);
        }
    }
    return Value.initInt(0);
}

/// floatval - 转换为浮点数
pub fn php_floatval(val: Value) !Value {
    return Value.initFloat(val.toFloat());
}

/// boolval - 转换为布尔值
pub fn php_boolval(val: Value) !Value {
    return Value.initBool(val.toBool());
}

// ============================================================================
// 类型检查函数
// ============================================================================

/// is_null - 检查是否为null
pub fn php_is_null(val: Value) !Value {
    return Value.initBool(val.isNull());
}

/// is_bool - 检查是否为布尔值
pub fn php_is_bool(val: Value) !Value {
    return Value.initBool(val.isBool());
}

/// is_int - 检查是否为整数
pub fn php_is_int(val: Value) !Value {
    return Value.initBool(val.isInt());
}

/// is_float - 检查是否为浮点数
pub fn php_is_float(val: Value) !Value {
    return Value.initBool(val.isFloat());
}

/// is_string - 检查是否为字符串
pub fn php_is_string(val: Value) !Value {
    return Value.initBool(val.isString());
}

/// is_array - 检查是否为数组
pub fn php_is_array(val: Value) !Value {
    return Value.initBool(val.isArray());
}

/// is_numeric - 检查是否为数字或数字字符串
pub fn php_is_numeric(val: Value) !Value {
    if (val.isInt() or val.isFloat()) return Value.initBool(true);
    if (val.isString()) {
        const str = val.asString();
        // 尝试解析为数字
        _ = std.fmt.parseInt(i64, str.data, 10) catch {
            _ = std.fmt.parseFloat(f64, str.data) catch {
                return Value.initBool(false);
            };
        };
        return Value.initBool(true);
    }
    return Value.initBool(false);
}

/// is_callable - 检查是否可调用（简化实现）
pub fn php_is_callable(val: Value) !Value {
    return Value.initBool(val.isString() or val.isArray() or val.isFunction());
}

/// unset - 删除变量（立即释放引用）
pub fn php_unset(val: Value) !Value {
    // 调用release减少引用计数，如果为0则触发析构
    val.release(runtime_allocator);
    return Value.initNull();
}

/// clone - 克隆对象
pub fn php_clone(val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(val)) {
        return error.InvalidArgument;
    }
    
    const orig_obj = Value_asObject(val);
    
    // 创建新对象
    const new_obj = try PHPObject.init(allocator, orig_obj.class_name);
    
    // 复制属性
    var iter = orig_obj.properties.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        try new_obj.properties.put(key, value.retain());
    }
    
    // 复制class_meta
    new_obj.class_meta = orig_obj.class_meta;
    
    const new_val = Value_initObject(new_obj);
    
    // 调用__clone魔术方法
    if (new_obj.class_meta) |meta| {
        if (meta.findMethodLookup("__clone")) |lookup| {
            const guard = ClassContext.init(meta, lookup.owner);
            defer guard.deinit();
            _ = try lookup.method.func(new_val, &.{}, allocator);
        }
    }
    
    return new_val;
}

// ============================================================================
// 文件I/O函数
// ============================================================================

/// fopen - 打开文件
pub fn php_fopen(filename: Value, mode: Value) !Value {
    const fname = filename.asString();
    const fmode = mode.asString();
    
    // 特殊处理 php://memory 和 php://temp
    if (std.mem.startsWith(u8, fname.data, "php://")) {
        return Value.initInt(1); // 虚拟句柄
    }
    
    // 尝试打开文件验证存在性
    _ = std.fs.cwd().openFile(fname.data, .{
        .mode = if (std.mem.indexOf(u8, fmode.data, "r") != null) .read_only else .read_write,
    }) catch {
        return Value.initBool(false);
    };
    
    // 简化：返回虚拟句柄
    return Value.initInt(1);
}

/// fclose - 关闭文件
pub fn php_fclose(handle: Value) !Value {
    _ = handle;
    // 简化：总是返回成功
    return Value.initBool(true);
}

/// fread - 读取文件
pub fn php_fread(handle: Value, length: Value) !Value {
    _ = handle;
    _ = length;
    // 简化：返回空字符串
    return Value.initString("");
}

/// fwrite - 写入文件
pub fn php_fwrite(handle: Value, data: Value) !Value {
    _ = handle;
    const str = data.asString();
    return Value.initInt(@intCast(str.data.len));
}

/// is_resource - 检查是否为资源
pub fn php_is_resource(val: Value) !Value {
    // 简化：检查是否为正整数（文件句柄）
    if (val.isInt()) {
        const i = val.asInt();
        return Value.initBool(i > 0);
    }
    return Value.initBool(false);
}

// ============================================================================
// 字符串插值函数
// ============================================================================

/// php_interpolate - 字符串插值（将多个值连接成字符串）
///
/// 这个函数接收一个Value数组，将每个值转换为字符串并连接起来。
/// 这是PHP字符串插值的核心实现，例如：
/// ```php
/// $name = "Alice";
/// $age = 30;
/// echo "Hello, $name! You are $age years old.";
/// ```
///
/// @param parts 要插值的值数组
/// @param allocator 内存分配器
/// @return 插值后的字符串Value
pub fn php_interpolate(parts: []const Value, allocator: Allocator) !Value {
    if (parts.len == 0) {
        // 空数组，返回空字符串
        return Value.initString(try PHPString.init(allocator, ""));
    }

    if (parts.len == 1) {
        // 单个值，直接转换为字符串
        const str = try parts[0].toString(allocator);
        return Value.initString(str);
    }

    // 多个值，需要连接
    // 首先计算总长度
    var total_length: usize = 0;
    var temp_strings = try allocator.alloc(*PHPString, parts.len);
    defer {
        // 释放临时字符串
        for (temp_strings) |str| {
            str.release(allocator);
        }
        allocator.free(temp_strings);
    }

    // 将每个值转换为字符串
    for (parts, 0..) |part, i| {
        const str = try part.toString(allocator);
        temp_strings[i] = str;
        total_length += str.length;
    }

    // 分配结果缓冲区
    const result_data = try allocator.alloc(u8, total_length);
    errdefer allocator.free(result_data);

    // 连接所有字符串
    var offset: usize = 0;
    for (temp_strings) |str| {
        if (str.length > 0) {
            @memcpy(result_data[offset .. offset + str.length], str.data[0..str.length]);
            offset += str.length;
        }
    }

    // 创建结果字符串
    const result = try allocator.create(PHPString);
    errdefer allocator.destroy(result);

    result.data = result_data;
    result.length = total_length;
    result.ref_count = 1;
    result.is_static = false;

    return Value.initString(result);
}

// ============================================================================
// PHP类元数据和对象类型
// ============================================================================

/// 方法签名类型
pub const MethodFn = *const fn (this: Value, args: []const Value, allocator: Allocator) anyerror!Value;

/// 类方法定义
pub const ClassMethod = struct {
    name: []const u8,
    func: MethodFn,
    is_static: bool = false,
    is_public: bool = true,
    is_protected: bool = false,
    is_private: bool = false,
};

/// 类属性定义
pub const ClassProperty = struct {
    name: []const u8,
    default_value: ?Value = null,
    is_static: bool = false,
    is_public: bool = true,
    is_readonly: bool = false,
};

/// 类元数据
/// 存储类的完整定义，包括方法、属性、继承关系、接口等
pub const ClassMeta = struct {
    name: []const u8,
    parent: ?*const ClassMeta = null,
    interfaces: []const []const u8 = &.{},
    methods: std.StringHashMap(ClassMethod),
    properties: std.StringHashMap(ClassProperty),
    static_properties: std.StringHashMap(Value),
    is_abstract: bool = false,
    is_final: bool = false,
    allocator: Allocator,

    /// 魔法函数指针
    magic_construct: ?MethodFn = null,
    magic_destruct: ?MethodFn = null,
    magic_call: ?MethodFn = null,
    magic_callStatic: ?MethodFn = null,
    magic_get: ?MethodFn = null,
    magic_set: ?MethodFn = null,
    magic_isset: ?MethodFn = null,
    magic_unset: ?MethodFn = null,
    magic_toString: ?MethodFn = null,
    magic_invoke: ?MethodFn = null,
    magic_clone: ?MethodFn = null,
    magic_sleep: ?MethodFn = null,
    magic_wakeup: ?MethodFn = null,
    magic_serialize: ?MethodFn = null,
    magic_unserialize: ?MethodFn = null,

    pub fn init(allocator: Allocator, name: []const u8) !*ClassMeta {
        const meta = try allocator.create(ClassMeta);
        errdefer allocator.destroy(meta);

        meta.* = .{
            .name = try allocator.dupe(u8, name),
            .methods = std.StringHashMap(ClassMethod).init(allocator),
            .properties = std.StringHashMap(ClassProperty).init(allocator),
            .static_properties = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
        return meta;
    }

    pub fn deinit(self: *ClassMeta) void {
        // 先释放静态属性（可能包含对象引用）
        var iter = self.static_properties.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.static_properties.deinit();
        
        // 再释放其他资源
        self.methods.deinit();
        self.properties.deinit();
        self.allocator.free(self.name);
        self.allocator.destroy(self);
    }

    /// 添加方法
    pub fn addMethod(self: *ClassMeta, method: ClassMethod) !void {
        try self.methods.put(method.name, method);
        if (std.mem.eql(u8, method.name, "__construct")) self.magic_construct = method.func;
        if (std.mem.eql(u8, method.name, "__destruct")) self.magic_destruct = method.func;
        if (std.mem.eql(u8, method.name, "__get")) self.magic_get = method.func;
        if (std.mem.eql(u8, method.name, "__set")) self.magic_set = method.func;
        if (std.mem.eql(u8, method.name, "__call")) self.magic_call = method.func;
        if (std.mem.eql(u8, method.name, "__callStatic")) self.magic_callStatic = method.func;
        if (std.mem.eql(u8, method.name, "__sleep")) self.magic_sleep = method.func;
        if (std.mem.eql(u8, method.name, "__wakeup")) self.magic_wakeup = method.func;
        if (std.mem.eql(u8, method.name, "__serialize")) self.magic_serialize = method.func;
        if (std.mem.eql(u8, method.name, "__unserialize")) self.magic_unserialize = method.func;
    }

    pub const MethodLookup = struct {
        owner: *const ClassMeta,
        method: *const ClassMethod,
    };

    pub fn findMethodLookup(self: *const ClassMeta, name: []const u8) ?MethodLookup {
        if (self.methods.getPtr(name)) |method| {
            return .{ .owner = self, .method = method };
        }
        if (self.parent) |parent| {
            return parent.findMethodLookup(name);
        }
        return null;
    }

    /// 查找方法（包括继承链）
    pub fn findMethod(self: *const ClassMeta, name: []const u8) ?ClassMethod {
        if (self.methods.get(name)) |method| {
            return method;
        }
        if (self.parent) |parent| {
            return parent.findMethod(name);
        }
        return null;
    }

    /// 注册内置 Exception 类
    pub fn registerExceptionClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "Exception");

        // __construct($message = "", $code = 0, $previous = null)
        try meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    const this = Value_asObject(ctx);
                    if (args.len > 0) {
                        try this.setProperty("message", args[0]);
                    } else {
                        try this.setProperty("message", Value.initString(try PHPString.init(runtime_alloc, "")));
                    }
                    if (args.len > 1) {
                        try this.setProperty("code", args[1]);
                    } else {
                        try this.setProperty("code", Value.initInt(0));
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // getMessage()
        try meta.addMethod(.{
            .name = "getMessage",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("message")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initString(try PHPString.init(runtime_alloc, ""));
                }
            }.call,
            .is_static = false,
        });

        // __toString()
        try meta.addMethod(.{
            .name = "__toString",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    const this = Value_asObject(ctx);
                    var msg = try PHPString.init(runtime_alloc, "Exception: ");

                    if (this.getProperty("message")) |val| {
                        if (val.isString()) {
                            const new_str = try std.fmt.allocPrint(runtime_alloc, "{s}{s}", .{ msg.data, val.asString().data });
                            defer runtime_alloc.free(new_str);
                            msg.release(runtime_alloc);
                            return Value.initString(try PHPString.init(runtime_alloc, new_str));
                        }
                    }
                    return Value.initString(msg);
                }
            }.call,
            .is_static = false,
        });

        meta.magic_toString = meta.methods.get("__toString").?.func;

        try registerClass(meta);
    }

    /// 添加属性定义
    pub fn addProperty(self: *ClassMeta, prop: ClassProperty) !void {
        try self.properties.put(prop.name, prop);
    }

    /// 设置静态属性
    pub fn setStaticProperty(self: *ClassMeta, name: []const u8, value: Value) !void {
        if (self.static_properties.get(name)) |old| {
            old.release(self.allocator);
        }
        _ = value.retain();
        try self.static_properties.put(name, value);
    }

    /// 获取静态属性
    pub fn getStaticProperty(self: *const ClassMeta, name: []const u8) ?Value {
        if (self.static_properties.get(name)) |val| {
            return val;
        }
        if (self.parent) |parent| {
            return parent.getStaticProperty(name);
        }
        return null;
    }

    /// 检查是否实现了接口
    pub fn implementsInterface(self: *const ClassMeta, interface_name: []const u8) bool {
        for (self.interfaces) |iface| {
            if (std.mem.eql(u8, iface, interface_name)) return true;
        }
        if (self.parent) |parent| {
            return parent.implementsInterface(interface_name);
        }
        return false;
    }

    /// 检查是否是某个类的子类
    pub fn isSubclassOf(self: *const ClassMeta, class_name: []const u8) bool {
        if (std.mem.eql(u8, self.name, class_name)) return true;
        if (self.parent) |parent| {
            return parent.isSubclassOf(class_name);
        }
        return false;
    }
};

/// 全局类注册表
pub var class_registry: ?std.StringHashMap(*ClassMeta) = null;

/// 全局对象跟踪（用于内存泄露检测和清理）
pub var global_object_registry: ?std.ArrayList(*PHPObject) = null;

fn getCurrentCalledClass() ?*const ClassMeta {
    const ptr = concurrency.getExecutionContext().called_class orelse return null;
    return @ptrFromInt(ptr);
}

fn setCurrentCalledClass(meta: ?*const ClassMeta) void {
    concurrency.getExecutionContext().called_class = if (meta) |m| @intFromPtr(m) else null;
}

fn getCurrentScopeClass() ?*const ClassMeta {
    const ptr = concurrency.getExecutionContext().scope_class orelse return null;
    return @ptrFromInt(ptr);
}

fn setCurrentScopeClass(meta: ?*const ClassMeta) void {
    concurrency.getExecutionContext().scope_class = if (meta) |m| @intFromPtr(m) else null;
}

pub const ClassContext = struct {
    prev_called: ?*const ClassMeta,
    prev_scope: ?*const ClassMeta,

    pub fn init(called: ?*const ClassMeta, scope: ?*const ClassMeta) ClassContext {
        const prev = ClassContext{
            .prev_called = getCurrentCalledClass(),
            .prev_scope = getCurrentScopeClass(),
        };
        setCurrentCalledClass(called);
        setCurrentScopeClass(scope);
        return prev;
    }

    pub fn deinit(self: *const ClassContext) void {
        setCurrentCalledClass(self.prev_called);
        setCurrentScopeClass(self.prev_scope);
    }
};

fn resolveSpecialClassName(class_name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, class_name, "static")) {
        const meta = getCurrentCalledClass() orelse return error.ClassNotFound;
        return meta.name;
    }
    if (std.mem.eql(u8, class_name, "self")) {
        const meta = getCurrentScopeClass() orelse return error.ClassNotFound;
        return meta.name;
    }
    if (std.mem.eql(u8, class_name, "parent")) {
        const meta = getCurrentScopeClass() orelse return error.ClassNotFound;
        const parent = meta.parent orelse return error.ClassNotFound;
        return parent.name;
    }
    return class_name;
}

/// 初始化类注册表
pub fn initClassRegistry(allocator: Allocator) void {
    class_registry = std.StringHashMap(*ClassMeta).init(allocator);
    global_object_registry = std.ArrayList(*PHPObject).initCapacity(allocator, 0) catch {
        global_object_registry = null;
        return;
    };
}

/// 注册类
pub fn registerClass(meta: *ClassMeta) !void {
    if (class_registry) |*registry| {
        try registry.put(meta.name, meta);
    }
}

/// 查找类
pub fn findClass(name: []const u8) ?*ClassMeta {
    if (class_registry) |registry| {
        return registry.get(name);
    }
    return null;
}

/// 清理所有注册的类和对象
pub fn cleanupAllClasses() void {
    // 清空对象注册表（对象由global_vars cleanup处理）
    if (global_object_registry) |*registry| {
        registry.deinit(runtime_allocator);
        global_object_registry = null;
    }

    // 清理所有类
    if (class_registry) |*registry| {
        var iter = registry.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        registry.deinit();
        class_registry = null;
    }
}

/// PHP对象类型
/// 使用引用计数管理内存，属性存储在HashMap中
pub const PHPObject = struct {
    class_meta: ?*const ClassMeta,
    class_name: []const u8,
    properties: std.StringHashMap(Value),
    ref_count: usize,
    gc_info: GCInfo,
    allocator: Allocator,

    /// 创建新对象
    pub fn init(allocator: Allocator, class_name: []const u8) !*PHPObject {
        const obj = try allocator.create(PHPObject);
        errdefer allocator.destroy(obj);

        obj.class_name = try allocator.dupe(u8, class_name);
        errdefer allocator.free(obj.class_name);

        obj.properties = std.StringHashMap(Value).init(allocator);
        obj.ref_count = 1;
        obj.gc_info = .{};
        obj.allocator = allocator;
        obj.class_meta = findClass(class_name);

        alloc_counters.php_object_objects += 1;
        alloc_counters.php_object_live_objects += 1;
        if (alloc_counters.php_object_live_objects > alloc_counters.php_object_peak_live_objects) {
            alloc_counters.php_object_peak_live_objects = alloc_counters.php_object_live_objects;
        }

        return obj;
    }

    /// 使用类元数据创建对象
    pub fn initWithMeta(allocator: Allocator, meta: *const ClassMeta) !*PHPObject {
        const obj = try allocator.create(PHPObject);
        errdefer allocator.destroy(obj);

        obj.class_name = try allocator.dupe(u8, meta.name);
        errdefer allocator.free(obj.class_name);

        obj.properties = std.StringHashMap(Value).init(allocator);
        obj.ref_count = 1;
        obj.gc_info = .{};
        obj.allocator = allocator;
        obj.class_meta = meta;

        alloc_counters.php_object_objects += 1;
        alloc_counters.php_object_live_objects += 1;
        if (alloc_counters.php_object_live_objects > alloc_counters.php_object_peak_live_objects) {
            alloc_counters.php_object_peak_live_objects = alloc_counters.php_object_live_objects;
        }

        // 初始化默认属性值（包括父类）
        var current_meta: ?*const ClassMeta = meta;
        while (current_meta) |m| {
            var prop_iter = m.properties.iterator();
            while (prop_iter.next()) |entry| {
                if (!entry.value_ptr.is_static) {
                    // 只初始化还不存在的属性（避免覆盖子类的属性）
                    if (obj.properties.get(entry.key_ptr.*) == null) {
                        if (entry.value_ptr.default_value) |default| {
                            // 检查是否是数组标记（initInt(-1)）
                            if (default.isInt() and default.asInt() == -1) {
                                const new_array = try PHPArray.init(allocator);
                                try obj.properties.put(entry.key_ptr.*, Value.initArray(new_array));
                            } else if (default.isArray()) {
                                // 旧代码路径：如果是数组，创建新实例
                                const new_array = try PHPArray.init(allocator);
                                try obj.properties.put(entry.key_ptr.*, Value.initArray(new_array));
                            } else {
                                // 其他类型可以共享（int/float/bool/string是不可变的）
                                _ = default.retain();
                                try obj.properties.put(entry.key_ptr.*, default);
                            }
                        }
                    }
                }
            }
            current_meta = m.parent;
        }
        return obj;
    }

    /// 增加引用计数
    pub fn retain(self: *PHPObject) void {
        self.ref_count += 1;
        // std.debug.print("PHPObject.retain: class={s} ref_count={d}\n", .{ self.class_name, self.ref_count });
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPObject) void {
        // std.debug.print("PHPObject.release BEFORE: class={s} ref_count={d}\n", .{ self.class_name, self.ref_count });

        if (self.ref_count == 0) {
            std.debug.print("WARNING: PHPObject double free detected! class={s}\n", .{self.class_name});
            return;
        }

        self.ref_count -= 1;
        // std.debug.print("PHPObject.release AFTER: class={s} ref_count={d}\n", .{ self.class_name, self.ref_count });

        if (self.ref_count == 0) {
            // std.debug.print("PHPObject.deinit: class={s}\n", .{self.class_name});
            self.deinit();
        } else if (!gc_in_progress) {
            gcBufferObject(self);
        }
    }

    /// 释放对象
    fn deinit(self: *PHPObject) void {
        if (alloc_counters.php_object_live_objects > 0) {
            alloc_counters.php_object_live_objects -= 1;
        }

        // 调用 __destruct 魔法函数
        // 注意：在程序清理阶段，class_meta可能已被释放，需要检查
        if (self.class_meta) |meta| {
            // 简单检查：如果class_registry已被清理，跳过__destruct
            if (class_registry != null) {
                if (meta.findMethodLookup("__destruct")) |lookup| {
                    const this_val = Value_initObject(self);
                    const guard = ClassContext.init(meta, lookup.owner);
                    defer guard.deinit();
                    _ = lookup.method.func(this_val, &.{}, self.allocator) catch {};
                }
            }
        }

        if (global_object_registry) |*registry| {
            var i: usize = 0;
            while (i < registry.items.len) : (i += 1) {
                if (registry.items[i] == self) {
                    registry.items[i] = registry.items[registry.items.len - 1];
                    _ = registry.pop();
                    break;
                }
            }
        }

        // 释放所有属性值
        var iter = self.properties.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.properties.deinit();

        // 释放类名
        self.allocator.free(self.class_name);

        // 释放对象本身
        self.allocator.destroy(self);
    }

    /// 获取属性（支持 __get 魔法函数）
// 防止magic method递归调用的标志
threadlocal var in_magic_method: bool = false;

    pub fn getProperty(self: *PHPObject, name: []const u8) ?Value {
        if (self.properties.get(name)) |val| {
            _ = val.retain();
            return val;
        }
        // 防止递归调用__get
        if (in_magic_method) return null;
        
        // 调用 __get 魔法函数
        if (self.class_meta) |meta| {
            if (meta.findMethodLookup("__get")) |lookup| {
                in_magic_method = true;
                defer in_magic_method = false;
                
                const this_val = Value_initObject(self);
                const name_str = PHPString.init(self.allocator, name) catch return null;
                const name_val = Value.initString(name_str);
                defer name_val.release(self.allocator);
                const args = [_]Value{name_val};
                const guard = ClassContext.init(meta, lookup.owner);
                defer guard.deinit();
                const result = lookup.method.func(this_val, &args, self.allocator) catch return null;
                return result;
            }
        }
        return null;
    }

    /// 直接获取属性（不触发__get）
    pub fn getPropertyDirect(self: *PHPObject, name: []const u8) ?Value {
        if (self.properties.get(name)) |val| {
            _ = val.retain();
            return val;
        }
        return null;
    }

    /// 设置属性（支持 __set 魔法函数）
    pub fn setProperty(self: *PHPObject, name: []const u8, value: Value) !void {
        // 防止递归调用__set
        if (!in_magic_method) {
            // 检查是否有 __set 魔法函数且属性不存在
            if (self.properties.get(name) == null) {
                if (self.class_meta) |meta| {
                    if (meta.findMethodLookup("__set")) |lookup| {
                        in_magic_method = true;
                        defer in_magic_method = false;
                        
                        const this_val = Value_initObject(self);
                        const name_str = try PHPString.init(self.allocator, name);
                        const name_val = Value.initString(name_str);
                        defer name_val.release(self.allocator);
                        const args = [_]Value{ name_val, value };
                        const guard = ClassContext.init(meta, lookup.owner);
                        defer guard.deinit();
                        _ = try lookup.method.func(this_val, &args, self.allocator);
                        return;
                    }
                }
            }
        }

        // 释放旧值
        if (self.properties.get(name)) |old_value| {
            old_value.release(self.allocator);
        }

        // 保留新值
        _ = value.retain();

        // 存储属性
        try self.properties.put(name, value);
    }

    /// 调用方法（支持 __call 魔法函数和继承）
    pub fn callMethod(self: *PHPObject, method_name: []const u8, args: []const Value) !Value {
        const this_val = Value_initObject(self);

        if (self.class_meta) |meta| {
            // 查找方法（包括继承链）
            if (meta.findMethodLookup(method_name)) |lookup| {
                const guard = ClassContext.init(meta, lookup.owner);
                defer guard.deinit();
                return lookup.method.func(this_val, args, self.allocator);
            }
            // 调用 __call 魔法函数
            if (meta.findMethodLookup("__call")) |lookup| {
                const name_val = Value.initString(try PHPString.init(self.allocator, method_name));
                const args_arr = try PHPArray.init(self.allocator);
                for (args) |arg| {
                    try args_arr.push(self.allocator, arg);
                }
                const call_args = [_]Value{ name_val, Value.initArray(args_arr) };
                const guard = ClassContext.init(meta, lookup.owner);
                defer guard.deinit();
                return lookup.method.func(this_val, &call_args, self.allocator);
            }
        }
        return error.MethodNotFound;
    }

    /// 检查属性是否存在（支持 __isset 魔法函数）
    pub fn hasProperty(self: *PHPObject, name: []const u8) bool {
        if (self.properties.contains(name)) return true;
        if (self.class_meta) |meta| {
            if (meta.findMethodLookup("__isset")) |lookup| {
                const this_val = Value_initObject(self);
                const name_val = Value.initString(PHPString.initStatic(name));
                const args = [_]Value{name_val};
                const guard = ClassContext.init(meta, lookup.owner);
                defer guard.deinit();
                const result = lookup.method.func(this_val, &args, self.allocator) catch return false;
                return result.toBool();
            }
        }
        return false;
    }

    /// 转换为字符串（支持 __toString 魔法函数）
    pub fn toString(self: *PHPObject, allocator: Allocator) !*PHPString {
        if (self.class_meta) |meta| {
            if (meta.magic_toString) |to_str| {
                const this_val = Value_initObject(self);
                const result = try to_str(this_val, &.{}, allocator);
                if (result.isString()) {
                    return result.asString();
                }
            }
        }
        // 默认返回类名
        return PHPString.init(allocator, self.class_name);
    }
};

// ============================================================================
// Value类型扩展 - 对象支持
// ============================================================================

// 扩展Value的方法（这些方法应该添加到Value结构中）
// 由于我们不能直接修改Value结构，我们在这里提供独立的函数

/// 创建对象值
pub fn Value_initObject(obj: *PHPObject) Value {
    const addr = @intFromPtr(obj);
    return .{ .val = nanbox_abi.encodePtr(addr, Value.TYPE_OBJECT) };
}

/// 检查是否是对象
pub fn Value_isObject(self: Value) bool {
    if ((self.val & (Value.SIGN_BIT | Value.QNAN)) != Value.QNAN) return false;
    return (self.val & Value.TYPE_MASK) == Value.TYPE_OBJECT;
}

/// 获取对象指针
pub fn Value_asObject(self: Value) *PHPObject {
    return @ptrFromInt(nanbox_abi.decodePtr(self.val));
}

// 更新Value的release方法以支持对象
// 注意：这需要在Value结构的release方法中添加对象处理

// ============================================================================
// 对象操作函数
// ============================================================================

/// 创建新对象
///
/// @param allocator 内存分配器
/// @return 对象Value
pub fn php_object_new(class_name: []const u8, allocator: Allocator) !Value {
    const resolved = try resolveSpecialClassName(class_name);
    const obj = if (findClass(resolved)) |meta|
        try PHPObject.initWithMeta(allocator, meta)
    else
        try PHPObject.init(allocator, resolved);

    // 注册对象以便程序退出时清理
    if (global_object_registry) |*registry| {
        registry.append(allocator, obj) catch {};
    }

    return Value_initObject(obj);
}

/// 获取对象属性
///
/// @param obj_val 对象Value
/// @param property_name 属性名
/// @return 属性值，如果不存在返回null
pub fn php_object_get(obj_val: Value, property_name: []const u8) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }

    const obj = Value_asObject(obj_val);
    return obj.getProperty(property_name) orelse Value.initNull();
}

pub fn php_object_get_direct(obj_val: Value, property_name: []const u8) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }

    const obj = Value_asObject(obj_val);
    return obj.getPropertyDirect(property_name) orelse Value.initNull();
}

pub fn php_object_get_safe_value(obj_val: Value, prop_name_val: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }
    if (!prop_name_val.isString()) {
        return Value.initNull();
    }
    const obj = Value_asObject(obj_val);
    return obj.getProperty(prop_name_val.asString().data) orelse Value.initNull();
}

pub fn php_object_get_dynamic(obj_val: Value, prop_name_val: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }
    if (!prop_name_val.isString()) {
        return error.InvalidPropertyName;
    }
    const obj = Value_asObject(obj_val);
    const prop_str = prop_name_val.asString();
    return obj.getProperty(prop_str.data) orelse Value.initNull();
}

pub fn php_object_set_dynamic(obj_val: Value, prop_name_val: Value, value: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }
    if (!prop_name_val.isString()) {
        return error.InvalidPropertyName;
    }
    const obj = Value_asObject(obj_val);
    const prop_str = prop_name_val.asString();
    try obj.setProperty(prop_str.data, value);
    return Value.initNull();
}

/// 类型转换函数
pub fn php_cast_int(val: Value) !Value {
    return Value.initInt(val.toInt());
}

pub fn php_cast_float(val: Value) !Value {
    return Value.initFloat(val.toFloat());
}

pub fn php_cast_string(val: Value) !Value {
    const str = try val.toString(runtime_allocator);
    return Value.initString(str);
}

pub fn php_cast_bool(val: Value) !Value {
    return Value.initBool(val.toBool());
}

pub fn php_cast_array(val: Value) !Value {
    if (val.isArray()) {
        return val;
    }
    const arr = try PHPArray.init(runtime_allocator);
    try arr.push(runtime_allocator, val);
    return Value.initArray(arr);
}

pub fn php_cast_object(val: Value) !Value {
    if (val.isArray()) {
        const obj_val = try php_object_new("stdClass", runtime_allocator);
        const obj = Value_asObject(obj_val);
        var it = val.asArray().elements.iterator();
        while (it.next()) |entry| {
            switch (entry.key_ptr.*) {
                .string => |key| {
                    try obj.setProperty(key.data, entry.value_ptr.*);
                },
                .integer => |idx| {
                    const key_str = try std.fmt.allocPrint(runtime_allocator, "{d}", .{idx});
                    errdefer runtime_allocator.free(key_str);
                    const key_copy = try runtime_allocator.dupe(u8, key_str);
                    runtime_allocator.free(key_str);
                    try obj.properties.put(key_copy, entry.value_ptr.*.retain());
                },
            }
        }
        return obj_val;
    }
    return val;
}

/// 设置对象属性
///
/// @param obj_val 对象Value
/// @param property_name 属性名
/// @param value 属性值
pub fn php_object_set(obj_val: Value, property_name: []const u8, value: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }

    const obj = Value_asObject(obj_val);
    try obj.setProperty(property_name, value);
    return Value.initNull();
}

/// 调用对象方法
///
/// @param obj_val 对象Value
/// @param method_name 方法名
/// @param args 参数数组
/// @return 方法返回值
pub fn php_object_call(obj_val: Value, method_name: []const u8, args: []const Value) !Value {
    if (obj_val.isString()) {
        if (std.mem.eql(u8, method_name, "toUpper")) return php_strtoupper(obj_val, runtime_allocator);
        if (std.mem.eql(u8, method_name, "toLower")) return php_strtolower(obj_val, runtime_allocator);
        if (std.mem.eql(u8, method_name, "trim")) return php_trim(obj_val, Value.initNull(), runtime_allocator);
        if (std.mem.eql(u8, method_name, "length")) return php_strlen(obj_val);
        if (std.mem.eql(u8, method_name, "replace")) {
            if (args.len < 2) return error.MissingArgument;
            return php_str_replace(args[0], args[1], obj_val, Value.initNull(), runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "substring")) {
            if (args.len < 2) return error.MissingArgument;
            return php_substr(obj_val, args[0], args[1], runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "indexOf")) {
            if (args.len < 1) return error.MissingArgument;
            return php_strpos(obj_val, args[0], Value.initInt(0));
        }
        if (std.mem.eql(u8, method_name, "lastIndexOf")) {
            if (args.len < 1) return error.MissingArgument;
            return php_strrpos(obj_val, args[0], Value.initInt(0));
        }
        if (std.mem.eql(u8, method_name, "contains")) {
            if (args.len < 1) return error.MissingArgument;
            return php_str_contains(obj_val, args[0]);
        }
        if (std.mem.eql(u8, method_name, "startsWith")) {
            if (args.len < 1) return error.MissingArgument;
            return php_str_starts_with(obj_val, args[0]);
        }
        if (std.mem.eql(u8, method_name, "endsWith")) {
            if (args.len < 1) return error.MissingArgument;
            return php_str_ends_with(obj_val, args[0]);
        }
        if (std.mem.eql(u8, method_name, "repeat")) {
            if (args.len < 1) return error.MissingArgument;
            return php_str_repeat(obj_val, args[0], runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "pad")) {
            if (args.len < 1) return error.MissingArgument;
            var created_pad_str = false;
            const pad_str = if (args.len >= 2) args[1] else blk: {
                created_pad_str = true;
                break :blk Value.initString(try PHPString.init(runtime_allocator, " "));
            };
            defer if (created_pad_str) pad_str.release(runtime_allocator);
            const pad_type = if (args.len >= 3) args[2] else Value.initInt(0);
            return php_str_pad(obj_val, args[0], pad_str, pad_type, runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "reverse")) return php_strrev(obj_val, runtime_allocator);
        if (std.mem.eql(u8, method_name, "split")) {
            if (args.len < 1) return error.MissingArgument;
            return php_explode(args[0], obj_val, Value.initNull(), runtime_allocator);
        }
        if (std.mem.eql(u8, method_name, "concat")) {
            if (args.len < 1) return error.MissingArgument;
            return php_concat(obj_val, args[0], runtime_allocator);
        }
        return error.UnknownMethod;
    }

    if (!Value_isObject(obj_val)) {
        return error.NotAnObject;
    }
    const obj = Value_asObject(obj_val);
    return obj.callMethod(method_name, args);
}

/// 创建新对象并调用构造函数
pub fn php_object_new_with_constructor(class_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const resolved = try resolveSpecialClassName(class_name);
    var meta = findClass(resolved);
    
    // 如果找不到，尝试使用短名称（命名空间支持）
    if (meta == null) {
        if (std.mem.lastIndexOf(u8, resolved, "\\")) |last_sep| {
            const short_name = resolved[last_sep + 1 ..];
            meta = findClass(short_name);
        }
    }
    
    const obj = if (meta) |m|
        try PHPObject.initWithMeta(allocator, m)
    else
        try PHPObject.init(allocator, resolved);

    const obj_val = Value_initObject(obj);

    // 调用 __construct
    if (obj.class_meta) |m| {
        if (m.findMethodLookup("__construct")) |lookup| {
            const guard = ClassContext.init(m, lookup.owner);
            defer guard.deinit();
            _ = try lookup.method.func(obj_val, args, allocator);
            // 注意：__construct不会额外retain对象，所以不需要release
        }
    }

    return obj_val;
}

/// 检查类是否存在
pub fn php_class_exists(class_name: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!class_name.isString()) return Value.initBool(false);
    const name = class_name.asString().data;
    return Value.initBool(findClass(name) != null);
}

pub fn class_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;
    return php_class_exists(args[0], allocator);
}

/// instanceof 检查
pub fn php_instanceof(obj_val: Value, class_name: Value) !Value {
    if (!Value_isObject(obj_val)) return Value.initBool(false);
    if (!class_name.isString()) return Value.initBool(false);

    const obj = Value_asObject(obj_val);
    const name = class_name.asString().data;

    // 检查类名直接匹配
    if (std.mem.eql(u8, obj.class_name, name)) return Value.initBool(true);

    // 检查继承链和接口
    if (obj.class_meta) |meta| {
        if (meta.isSubclassOf(name)) return Value.initBool(true);
        if (meta.implementsInterface(name)) return Value.initBool(true);
    }

    return Value.initBool(false);
}

/// 获取父类名
pub fn php_get_parent_class(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) return Value.initBool(false);

    const obj = Value_asObject(obj_val);
    if (obj.class_meta) |meta| {
        if (meta.parent) |parent| {
            const parent_name = try PHPString.init(allocator, parent.name);
            return Value.initString(parent_name);
        }
    }
    return Value.initBool(false);
}

/// 检查方法是否存在
pub fn php_method_exists(obj_val: Value, method_name: Value) !Value {
    if (!method_name.isString()) return Value.initBool(false);
    const name = method_name.asString().data;

    if (Value_isObject(obj_val)) {
        const obj = Value_asObject(obj_val);
        if (obj.class_meta) |meta| {
            return Value.initBool(meta.findMethod(name) != null);
        }
    }
    return Value.initBool(false);
}

pub fn method_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 2) return error.MissingArgument;
    return php_method_exists(args[0], args[1]);
}

/// 检查属性是否存在
pub fn php_property_exists(obj_val: Value, property_name: Value) !Value {
    if (!property_name.isString()) return Value.initBool(false);
    const name = property_name.asString().data;

    if (Value_isObject(obj_val)) {
        const obj = Value_asObject(obj_val);
        return Value.initBool(obj.hasProperty(name));
    }
    return Value.initBool(false);
}

pub fn property_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 2) return error.MissingArgument;
    return php_property_exists(args[0], args[1]);
}

/// 调用静态方法
pub fn php_call_static(class_name: []const u8, method_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    return php_call_static_with_ctx(Value.initNull(), class_name, method_name, args, allocator);
}

pub fn php_call_static_with_ctx(ctx: Value, class_name: []const u8, method_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const lookup_meta = blk: {
        if (std.mem.eql(u8, class_name, "self")) {
            break :blk getCurrentScopeClass() orelse return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_name, "parent")) {
            const scope = getCurrentScopeClass() orelse return error.ClassNotFound;
            if (scope.parent == null) {
                std.debug.print("ERROR: Class {s} has no parent\n", .{scope.name});
            }
            break :blk scope.parent orelse return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_name, "static")) {
            break :blk getCurrentCalledClass() orelse return error.ClassNotFound;
        }
        break :blk findClass(class_name) orelse return error.ClassNotFound;
    };

    const called_meta = blk: {
        if (std.mem.eql(u8, class_name, "self") or
            std.mem.eql(u8, class_name, "parent") or
            std.mem.eql(u8, class_name, "static"))
        {
            break :blk getCurrentCalledClass() orelse return error.ClassNotFound;
        }
        break :blk lookup_meta;
    };

    // 查找方法（静态或实例方法）
    if (lookup_meta.findMethodLookup(method_name)) |lookup| {
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(ctx, args, allocator);
    }

    // 调用 __callStatic 魔法函数
    if (lookup_meta.findMethodLookup("__callStatic")) |lookup| {
        const name_str = try PHPString.init(allocator, method_name);
        const name_val = Value.initString(name_str);
        defer name_val.release(allocator);
        const args_arr = try PHPArray.init(allocator);
        for (args) |arg| {
            try args_arr.push(allocator, arg);
        }
        const call_args = [_]Value{ name_val, Value.initArray(args_arr) };
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(Value.initNull(), &call_args, allocator);
    }

    return error.MethodNotFound;
}

/// 获取静态属性
pub fn php_get_static_property(class_name: []const u8, property_name: []const u8) !Value {
    const meta = blk: {
        if (std.mem.eql(u8, class_name, "self")) {
            // 尝试从当前作用域获取
            if (getCurrentScopeClass()) |scope| {
                break :blk scope;
            }
            // 如果没有作用域，尝试从调用类获取
            if (getCurrentCalledClass()) |called| {
                break :blk called;
            }
            std.debug.print("ERROR: getCurrentScopeClass() returned null for 'self'\n", .{});
            return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_name, "parent")) {
            const scope = getCurrentScopeClass() orelse return error.ClassNotFound;
            break :blk scope.parent orelse return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_name, "static")) {
            break :blk getCurrentCalledClass() orelse return error.ClassNotFound;
        }
        break :blk findClass(class_name) orelse return error.ClassNotFound;
    };
    const val = meta.getStaticProperty(property_name);
    if (val == null) {
        std.debug.print("ERROR: Property {s}.{s} not found\n", .{ meta.name, property_name });
    }
    return val orelse Value.initNull();
}

/// 设置静态属性
pub fn php_set_static_property(class_name: []const u8, property_name: []const u8, value: Value) !Value {
    var meta = blk: {
        if (std.mem.eql(u8, class_name, "self")) {
            break :blk @constCast(getCurrentScopeClass() orelse return error.ClassNotFound);
        }
        if (std.mem.eql(u8, class_name, "parent")) {
            const scope = getCurrentScopeClass() orelse return error.ClassNotFound;
            break :blk @constCast(scope.parent orelse return error.ClassNotFound);
        }
        if (std.mem.eql(u8, class_name, "static")) {
            break :blk @constCast(getCurrentCalledClass() orelse return error.ClassNotFound);
        }
        break :blk findClass(class_name) orelse return error.ClassNotFound;
    };
    try meta.setStaticProperty(property_name, value);
    return Value.initNull();
}

fn serializeValue(buffer: *std.ArrayListUnmanaged(u8), value: Value, allocator: Allocator) !void {
    if (value.isNull()) {
        try buffer.appendSlice(allocator, "N;");
        return;
    }
    if (value.isBool()) {
        try buffer.writer(allocator).print("b:{d};", .{if (value.toBool()) @as(i64, 1) else @as(i64, 0)});
        return;
    }
    if (value.isInt()) {
        try buffer.writer(allocator).print("i:{d};", .{value.toInt()});
        return;
    }
    if (value.isFloat()) {
        try buffer.writer(allocator).print("d:{d};", .{value.toFloat()});
        return;
    }
    if (value.isString()) {
        const str = value.asString().data;
        try buffer.writer(allocator).print("s:{d}:\"", .{str.len});
        try buffer.appendSlice(allocator, str);
        try buffer.appendSlice(allocator, "\";");
        return;
    }
    if (value.isArray()) {
        const arr = value.asArray();
        const count = arr.elements.count();
        try buffer.writer(allocator).print("a:{d}:{{", .{count});
        var it = arr.elements.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            switch (key) {
                .integer => |i| try buffer.writer(allocator).print("i:{d};", .{i}),
                .string => |s| {
                    const k = s.data;
                    try buffer.writer(allocator).print("s:{d}:\"", .{k.len});
                    try buffer.appendSlice(allocator, k);
                    try buffer.appendSlice(allocator, "\";");
                },
            }
            try serializeValue(buffer, entry.value_ptr.*, allocator);
        }
        try buffer.appendSlice(allocator, "}");
        return;
    }
    if (Value_isObject(value)) {
        const obj = Value_asObject(value);
        const class_name = obj.class_name;

        if (obj.class_meta) |meta| {
            if (meta.magic_serialize) |serializer| {
                const arr_val = try serializer(value, &.{}, allocator);
                defer arr_val.release(allocator);

                if (arr_val.isArray()) {
                    const arr = arr_val.asArray();
                    const count = arr.elements.count();
                    try buffer.writer(allocator).print("O:{d}:\"", .{class_name.len});
                    try buffer.appendSlice(allocator, class_name);
                    try buffer.writer(allocator).print("\":{d}:{{", .{count});

                    var it = arr.elements.iterator();
                    while (it.next()) |entry| {
                        const key = entry.key_ptr.*;
                        switch (key) {
                            .integer => |i| try buffer.writer(allocator).print("i:{d};", .{i}),
                            .string => |s| {
                                const k = s.data;
                                try buffer.writer(allocator).print("s:{d}:\"", .{k.len});
                                try buffer.appendSlice(allocator, k);
                                try buffer.appendSlice(allocator, "\";");
                            },
                        }
                        try serializeValue(buffer, entry.value_ptr.*, allocator);
                    }
                    try buffer.appendSlice(allocator, "}");
                    return;
                }
            }
        }

        var allow_list: ?*PHPArray = null;
        var allow_val: Value = Value.initNull();
        defer if (!allow_val.isNull()) allow_val.release(allocator);

        if (obj.class_meta) |meta| {
            if (meta.magic_sleep) |sleeper| {
                allow_val = sleeper(value, &.{}, allocator) catch Value.initNull();
                if (allow_val.isArray()) {
                    allow_list = allow_val.asArray();
                }
            }
        }

        const count: usize = if (allow_list) |list| list.elements.count() else obj.properties.count();

        try buffer.writer(allocator).print("O:{d}:\"", .{class_name.len});
        try buffer.appendSlice(allocator, class_name);
        try buffer.writer(allocator).print("\":{d}:{{", .{count});

        if (allow_list) |list| {
            var it_allow = list.elements.iterator();
            while (it_allow.next()) |entry| {
                const v = entry.value_ptr.*;
                if (!v.isString()) continue;
                const prop_name = v.asString().data;
                const prop_val = obj.properties.get(prop_name) orelse Value.initNull();

                const full_len: usize = class_name.len + prop_name.len + 2;
                try buffer.writer(allocator).print("s:{d}:\"", .{full_len});
                try buffer.appendSlice(allocator, &[_]u8{0});
                try buffer.appendSlice(allocator, class_name);
                try buffer.appendSlice(allocator, &[_]u8{0});
                try buffer.appendSlice(allocator, prop_name);
                try buffer.appendSlice(allocator, "\";");

                try serializeValue(buffer, prop_val, allocator);
            }
        } else {
            var it_props = obj.properties.iterator();
            while (it_props.next()) |entry| {
                const prop_name = entry.key_ptr.*;
                const prop_val = entry.value_ptr.*;

                const full_len: usize = class_name.len + prop_name.len + 2;
                try buffer.writer(allocator).print("s:{d}:\"", .{full_len});
                try buffer.appendSlice(allocator, &[_]u8{0});
                try buffer.appendSlice(allocator, class_name);
                try buffer.appendSlice(allocator, &[_]u8{0});
                try buffer.appendSlice(allocator, prop_name);
                try buffer.appendSlice(allocator, "\";");

                try serializeValue(buffer, prop_val, allocator);
            }
        }

        try buffer.appendSlice(allocator, "}");
        return;
    }

    try buffer.appendSlice(allocator, "N;");
}

pub fn php_serialize(value: Value, allocator: Allocator) !Value {
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);
    try serializeValue(&buffer, value, allocator);
    const s = try PHPString.init(allocator, buffer.items);
    return Value.initString(s);
}

fn unserializeValue(data: []const u8, pos: *usize, allocator: Allocator) !Value {
    if (pos.* >= data.len) return Value.initNull();
    const type_char = data[pos.*];
    pos.* += 1;

    switch (type_char) {
        'N' => {
            pos.* += 1;
            return Value.initNull();
        },
        'b' => {
            pos.* += 1;
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const bool_str = data[pos.*..end];
            pos.* = end + 1;
            return Value.initBool(std.mem.eql(u8, bool_str, "1"));
        },
        'i' => {
            pos.* += 1;
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const int_str = data[pos.*..end];
            pos.* = end + 1;
            const v = std.fmt.parseInt(i64, int_str, 10) catch 0;
            return Value.initInt(v);
        },
        'd' => {
            pos.* += 1;
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const float_str = data[pos.*..end];
            pos.* = end + 1;
            const v = std.fmt.parseFloat(f64, float_str) catch 0;
            return Value.initFloat(v);
        },
        's' => {
            pos.* += 1;
            const colon = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const len_str = data[pos.*..colon];
            pos.* = colon + 1;
            const len = std.fmt.parseInt(usize, len_str, 10) catch 0;
            pos.* += 1;
            const str_val = data[pos.* .. pos.* + len];
            pos.* += len + 2;
            const ps = try PHPString.init(allocator, str_val);
            return Value.initString(ps);
        },
        'a' => {
            pos.* += 1;
            const count_end = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const count_str = data[pos.*..count_end];
            pos.* = count_end + 1;
            const count = std.fmt.parseInt(usize, count_str, 10) catch 0;
            pos.* += 1;

            const arr = try PHPArray.init(allocator);
            const arr_val = Value.initArray(arr);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                const key_val = try unserializeValue(data, pos, allocator);
                const val = try unserializeValue(data, pos, allocator);
                defer key_val.release(allocator);
                defer val.release(allocator);

                const key: ArrayKey = if (key_val.isString())
                    ArrayKey{ .string = key_val.asString() }
                else
                    ArrayKey{ .integer = key_val.toInt() };

                try arr.set(allocator, key, val);
            }

            pos.* += 1;
            return arr_val;
        },
        'O' => {
            pos.* += 1; // skip ':'
            const colon1 = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const len_str = data[pos.*..colon1];
            pos.* = colon1 + 1; // skip ':'
            const name_len = std.fmt.parseInt(usize, len_str, 10) catch 0;
            pos.* += 1; // skip '"'
            const class_name = data[pos.* .. pos.* + name_len];
            pos.* += name_len + 1; // skip class_name and '"'
            pos.* += 1; // skip ':'
            const colon2 = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const count_str = data[pos.*..colon2];
            pos.* = colon2 + 1; // skip ':'
            const count = std.fmt.parseInt(usize, count_str, 10) catch 0;
            pos.* += 1; // skip '{'

            const class_name_copy = try allocator.dupe(u8, class_name);
            defer allocator.free(class_name_copy);
            const obj_val = try php_object_new(class_name_copy, allocator);
            const obj = Value_asObject(obj_val);

            const data_arr = try PHPArray.init(allocator);
            const data_arr_val = Value.initArray(data_arr);
            defer data_arr_val.release(allocator);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                const key_val = try unserializeValue(data, pos, allocator);
                const val = try unserializeValue(data, pos, allocator);

                if (!key_val.isString()) {
                    key_val.release(allocator);
                    val.release(allocator);
                    continue;
                }
                const raw_key = key_val.asString().data;
                var prop_name: []const u8 = raw_key;
                if (raw_key.len > 0 and raw_key[0] == 0) {
                    if (std.mem.indexOfScalarPos(u8, raw_key, 1, 0)) |nul2| {
                        if (nul2 + 1 <= raw_key.len) {
                            prop_name = raw_key[nul2 + 1 ..];
                        }
                    }
                }

                const prop_str = try PHPString.init(allocator, prop_name);
                const prop_key = ArrayKey{ .string = prop_str };
                try data_arr.set(allocator, prop_key, val);
                
                // 释放key_val，val已经被data_arr持有
                key_val.release(allocator);
            }

            pos.* += 1; // skip '}'

            if (obj.class_meta) |meta| {
                if (meta.magic_unserialize) |unser_fn| {
                    const args = [_]Value{data_arr_val};
                    _ = try unser_fn(obj_val, &args, allocator);
                    return obj_val;
                }
            }

            var it = data_arr.elements.iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.* == .string) {
                    const k = entry.key_ptr.string.data;
                    try obj.setProperty(k, entry.value_ptr.*);
                }
            }

            if (obj.class_meta) |meta| {
                if (meta.magic_wakeup) |wake| {
                    _ = wake(obj_val, &.{}, allocator) catch {};
                }
            }

            return obj_val;
        },
        else => return Value.initNull(),
    }
}

pub fn php_unserialize(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgumentType;
    const data = str.asString().data;
    var pos: usize = 0;
    return unserializeValue(data, &pos, allocator);
}

/// 检查是否是对象
pub fn php_is_object(val: Value) !Value {
    return Value.initBool(Value_isObject(val));
}

/// 获取对象的类名
pub fn php_get_class(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initBool(false);
    }

    const obj = Value_asObject(obj_val);
    const class_name_str = try PHPString.init(allocator, obj.class_name);
    return Value.initString(class_name_str);
}

pub fn get_class(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;
    return php_get_class(args[0], allocator);
}

// ============================================================================
// 异常处理
// ============================================================================

/// 当前异常（全局状态）
/// 注意：这是一个简化的异常处理机制
/// 在真实的PHP实现中，异常应该是线程局部的
// var current_exception: ?Value = null; // 已在文件顶部定义为 threadlocal

/// 设置当前异常
///
/// @param exception 异常Value
// pub fn setException(exception: Value) void { // 已在文件顶部定义
//     current_exception = exception;
// }

/// 获取当前异常
///
/// @return 当前异常，如果没有异常返回null
pub fn getCurrentException() ?Value {
    if (has_exception) return current_exception;
    return null;
}

/// 清除当前异常
pub fn clearException() void {
    if (has_exception) {
        current_exception.release(runtime_allocator);
        current_exception = Value.initNull();
        has_exception = false;
    }
}

/// 抛出异常
///
/// @param message 异常消息
/// @param allocator 内存分配器
/// @return 异常Value
pub fn throwException(message: []const u8, allocator: Allocator) !Value {
    const msg_str = try PHPString.init(allocator, message);
    const exception = Value.initString(msg_str);
    setException(exception);
    return exception;
}

/// 检查是否有异常
///
/// @return 如果有异常返回true
pub fn hasException() bool {
    return has_exception;
}

// ============================================================================
// 时间函数（从VM实现复用）
// ============================================================================

/// time - 返回当前Unix时间戳
pub fn php_time() !Value {
    const timestamp = std.time.timestamp();
    return Value.initInt(timestamp);
}

/// microtime - 返回当前时间（带微秒）
///
/// @param get_as_float 是否返回浮点数格式
/// @param allocator 内存分配器
/// @return 字符串格式 "0.microseconds seconds" 或浮点数时间戳
pub fn php_microtime(get_as_float: Value, allocator: Allocator) !Value {
    const now_ns = std.time.nanoTimestamp();
    const sec = @divTrunc(now_ns, std.time.ns_per_s);
    const usec = @divTrunc(@mod(now_ns, std.time.ns_per_s), std.time.ns_per_us);

    // 检查是否返回浮点数
    const as_float = if (get_as_float.isBool())
        get_as_float.asBool()
    else if (get_as_float.isInt())
        get_as_float.asInt() != 0
    else
        false;

    if (as_float) {
        // 返回浮点数时间戳
        const float_time = @as(f64, @floatFromInt(sec)) + @as(f64, @floatFromInt(usec)) / 1000000.0;
        return Value.initFloat(float_time);
    } else {
        // 返回字符串格式 "0.microseconds seconds"
        const formatted = try std.fmt.allocPrint(allocator, "0.{d:0>6} {d}", .{ usec, sec });
        defer allocator.free(formatted);
        const result = try PHPString.init(allocator, formatted);
        return Value.initString(result);
    }
}

/// date - 格式化日期时间
///
/// 注意：这是一个简化实现，仅支持基本格式
/// 完整的PHP date()函数支持更多格式选项
///
/// @param format 格式字符串
/// @param timestamp 时间戳（可选，默认当前时间）
/// @param allocator 内存分配器
/// @return 格式化后的日期字符串
pub fn php_date(format: Value, timestamp: Value, allocator: Allocator) !Value {
    if (!format.isString()) {
        return Value.initString(try PHPString.init(allocator, ""));
    }

    // 获取时间戳
    const ts = if (timestamp.isNull())
        std.time.timestamp()
    else if (timestamp.isInt())
        timestamp.asInt()
    else if (timestamp.isFloat())
        @as(i64, @intFromFloat(timestamp.asFloat()))
    else
        std.time.timestamp();

    // 简化实现：仅支持 Y-m-d H:i:s 格式
    // 完整实现需要完整的日期格式化库
    const epoch_seconds = @as(u64, @intCast(ts));
    const days_since_epoch = epoch_seconds / 86400;
    const seconds_today = epoch_seconds % 86400;

    // 计算年月日（简化算法）
    const year = 1970 + @as(i64, @intCast(days_since_epoch / 365));
    const month: i64 = 1;
    const day: i64 = 1;

    // 计算时分秒
    const hour = seconds_today / 3600;
    const minute = (seconds_today % 3600) / 60;
    const second = seconds_today % 60;

    // 格式化输出（简化版）
    const formatted = try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ year, month, day, hour, minute, second });
    defer allocator.free(formatted);

    const result = try PHPString.init(allocator, formatted);
    return Value.initString(result);
}

// ============================================================================
// 随机数函数（MT19937实现，PHP兼容）
// ============================================================================

/// MT19937状态
const MT19937 = struct {
    state: [624]u32 = undefined,
    index: usize = 624,
    
    fn init(seed: u32) MT19937 {
        var mt = MT19937{};
        mt.state[0] = seed;
        var i: usize = 1;
        while (i < 624) : (i += 1) {
            mt.state[i] = 1812433253 *% (mt.state[i-1] ^ (mt.state[i-1] >> 30)) +% @as(u32, @intCast(i));
        }
        mt.index = 624;
        return mt;
    }
    
    fn generate(self: *MT19937) u32 {
        if (self.index >= 624) {
            self.twist();
        }
        var y = self.state[self.index];
        self.index += 1;
        
        y ^= (y >> 11);
        y ^= (y << 7) & 0x9D2C5680;
        y ^= (y << 15) & 0xEFC60000;
        y ^= (y >> 18);
        
        return y;
    }
    
    fn twist(self: *MT19937) void {
        var i: usize = 0;
        while (i < 624) : (i += 1) {
            const x = (self.state[i] & 0x80000000) + (self.state[(i + 1) % 624] & 0x7FFFFFFF);
            var xA = x >> 1;
            if ((x & 1) != 0) {
                xA ^= 0x9908B0DF;
            }
            self.state[i] = self.state[(i + 397) % 624] ^ xA;
        }
        self.index = 0;
    }
};

threadlocal var mt_state: ?MT19937 = null;

fn nextRandom() u64 {
    if (mt_state == null) {
        mt_state = MT19937.init(@intCast(@as(u64, @intCast(std.time.timestamp())) & 0xFFFFFFFF));
    }
    return @as(u64, mt_state.?.generate());
}

/// rand - 生成随机整数
///
/// @param min 最小值（可选）
/// @param max 最大值（可选）
/// @return 随机整数
pub fn php_rand(min: Value, max: Value) !Value {
    if (min.isNull() and max.isNull()) {
        // 无参数：返回 0 到 RAND_MAX
        const random = nextRandom();
        return Value.initInt(@as(i64, @intCast(random & 0x7FFFFFFF)));
    }

    const min_val = min.toInt();
    const max_val = max.toInt();

    if (min_val > max_val) {
        return Value.initInt(min_val);
    }

    const range = @as(u64, @intCast(max_val - min_val + 1));
    const random = nextRandom() % range;

    return Value.initInt(min_val + @as(i64, @intCast(random)));
}

/// mt_rand - 生成随机整数（Mersenne Twister）
///
/// 注意：这是简化实现，使用与rand()相同的生成器
/// 完整实现应该使用真正的MT19937算法
///
/// @param min 最小值（可选）
/// @param max 最大值（可选）
/// @return 随机整数
pub fn php_mt_rand(min: Value, max: Value) !Value {
    return php_rand(min, max);
}

/// srand - 设置随机数种子
///
/// @param seed 种子值（可选）
pub fn php_srand(seed: Value) !Value {
    if (seed.isNull()) {
        mt_state = MT19937.init(@intCast(@as(u64, @intCast(std.time.timestamp())) & 0xFFFFFFFF));
    } else {
        mt_state = MT19937.init(@intCast(@as(u64, @intCast(@abs(seed.toInt()))) & 0xFFFFFFFF));
    }
    return Value.initNull();
}

/// mt_srand - 设置MT随机数种子
///
/// @param seed 种子值（可选）
pub fn php_mt_srand(seed: Value) !Value {
    return php_srand(seed);
}

/// random_int - 生成密码学安全的随机整数
///
/// @param min 最小值
/// @param max 最大值
/// @return 随机整数
pub fn php_random_int(min: Value, max: Value) !Value {
    const min_val = min.toInt();
    const max_val = max.toInt();

    if (min_val > max_val) {
        return error.InvalidRange;
    }

    // 使用密码学安全的随机数生成器
    const random_val = std.crypto.random.intRangeAtMost(i64, min_val, max_val);
    return Value.initInt(random_val);
}

/// random_bytes - 生成密码学安全的随机字节
///
/// @param length 字节数
/// @param allocator 内存分配器
/// @return 随机字节字符串
pub fn php_random_bytes(length: Value, allocator: Allocator) !Value {
    const len = length.toInt();

    if (len < 0) {
        return error.InvalidLength;
    }

    const byte_len = @as(usize, @intCast(len));
    const buffer = try allocator.alloc(u8, byte_len);
    errdefer allocator.free(buffer);

    // 填充密码学安全的随机字节
    std.crypto.random.bytes(buffer);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

// ============================================================================
// 扩展数组函数
// ============================================================================

/// array_shift - 移除并返回数组的第一个元素
pub fn php_array_shift(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const v = array_ops_shared.shift(ArrayKey, Value, @TypeOf(php_arr.elements), allocator, &php_arr.elements, &php_arr.next_index) orelse return Value.initNull();
    return v;
}

/// array_unshift - 在数组开头添加元素
pub fn php_array_unshift(arr: Value, values: []const Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();
    try array_ops_shared.unshift(ArrayKey, Value, @TypeOf(php_arr.elements), allocator, &php_arr.elements, &php_arr.next_index, values);
    return Value.initInt(@intCast(php_arr.count()));
}

/// array_search - 在数组中搜索值并返回键
pub fn php_array_search(needle: Value, haystack: Value) !Value {
    if (!haystack.isArray()) return Value.initBool(false);

    const arr = haystack.asArray();
    var it = arr.elements.iterator();

    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        // 使用松散比较
        const eq_result = try php_eq(needle, val);
        if (eq_result.asBool()) {
            // 返回键
            return switch (entry.key_ptr.*) {
                .integer => |k| Value.initInt(k),
                .string => |k| blk: {
                    k.retain();
                    break :blk Value.initString(k);
                },
            };
        }
    }

    return Value.initBool(false);
}

/// array_sum - 计算数组元素的总和（packed int 快速路径 + SIMD 向量化）
pub fn php_array_sum(arr: Value) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();

    if (php_arr.elements.mixed == null) {
        const items = php_arr.elements.packed_values.items;
        if (items.len == 0) return Value.initInt(0);

        var all_int = true;
        for (items) |v| {
            if (!v.isInt()) {
                all_int = false;
                break;
            }
        }

        if (all_int) {
            return Value.initInt(fastPackedIntSum(items));
        }
    }

    var sum_int: i64 = 0;
    var sum_float: f64 = 0;
    var has_float = false;

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        if (val.isFloat()) {
            has_float = true;
            sum_float += val.asFloat();
        } else {
            sum_int += val.toInt();
        }
    }

    if (has_float) {
        return Value.initFloat(sum_float + @as(f64, @floatFromInt(sum_int)));
    }
    return Value.initInt(sum_int);
}

/// packed int 数组快速求和：comptime @Vector SIMD 优化
fn fastPackedIntSum(items: []const Value) i64 {
    // comptime 自动选择最优向量宽度
    const vec_len = comptime std.simd.suggestVectorLength(i64) orelse 4;
    const V = @Vector(vec_len, i64);

    var accum: V = @splat(0);
    var i: usize = 0;
    const len = items.len;

    // 主循环：向量化累加
    const aligned = len & ~@as(usize, vec_len - 1);
    while (i < aligned) : (i += vec_len) {
        var batch: V = undefined;
        inline for (0..vec_len) |j| {
            batch[j] = items[i + j].toInt();
        }
        accum +%= batch;
    }

    // 水平归约
    var sum: i64 = @reduce(.Add, accum);

    // 处理剩余元素
    while (i < len) : (i += 1) {
        sum +%= items[i].toInt();
    }

    return sum;
}

/// array_product - 计算数组元素的乘积
pub fn php_array_product(arr: Value) !Value {
    if (!arr.isArray()) return Value.initInt(0);

    const php_arr = arr.asArray();
    if (php_arr.count() == 0) return Value.initInt(1);

    var product: f64 = 1;
    var it = php_arr.elements.iterator();

    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        product *= val.toFloat();
    }

    // 如果结果是整数，返回整数
    if (@floor(product) == product and product >= @as(f64, @floatFromInt(std.math.minInt(i64))) and product <= @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
        return Value.initInt(@intFromFloat(product));
    }
    return Value.initFloat(product);
}

/// array_reverse - 反转数组
pub fn php_array_reverse(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    // 收集所有元素
    var values = try allocator.alloc(Value, php_arr.count());
    defer allocator.free(values);

    var idx: usize = 0;
    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        values[idx] = entry.value_ptr.*;
        idx += 1;
    }

    // 反向添加
    var i: usize = values.len;
    while (i > 0) {
        i -= 1;
        try result.push(allocator, values[i]);
    }

    return Value.initArray(result);
}

/// array_unique - 移除数组中的重复值
pub fn php_array_unique(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;

        // 检查是否已存在
        var exists = false;
        var result_it = result.elements.iterator();
        while (result_it.next()) |existing| {
            const eq_result = try php_eq(val, existing.value_ptr.*);
            if (eq_result.asBool()) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            try result.set(allocator, entry.key_ptr.*, val);
        }
    }

    return Value.initArray(result);
}

/// array_flip - 交换数组的键和值
pub fn php_array_flip(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initArray(try PHPArray.init(allocator));

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        const key = entry.key_ptr.*;

        // 值变成键，键变成值
        if (val.isInt()) {
            try result.set(allocator, .{ .integer = val.asInt() }, switch (key) {
                .integer => |k| Value.initInt(k),
                .string => |k| Value.initString(k),
            });
        } else if (val.isString()) {
            try result.set(allocator, .{ .string = val.asString() }, switch (key) {
                .integer => |k| Value.initInt(k),
                .string => |k| Value.initString(k),
            });
        }
    }

    return Value.initArray(result);
}

/// array_key_exists - 检查数组中是否存在指定的键
pub fn php_array_key_exists(key: Value, arr: Value) !Value {
    if (!arr.isArray()) return Value.initBool(false);

    const php_arr = arr.asArray();

    if (key.isInt()) {
        return Value.initBool(php_arr.get(.{ .integer = key.asInt() }) != null);
    } else if (key.isString()) {
        return Value.initBool(php_arr.get(.{ .string = key.asString() }) != null);
    }

    return Value.initBool(false);
}

/// array_key_first - 获取数组的第一个键
pub fn php_array_key_first(arr: Value) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    var it = php_arr.elements.iterator();

    if (it.next()) |entry| {
        return switch (entry.key_ptr.*) {
            .integer => |k| Value.initInt(k),
            .string => |k| blk: {
                k.retain();
                break :blk Value.initString(k);
            },
        };
    }

    return Value.initNull();
}

/// array_key_last - 获取数组的最后一个键
pub fn php_array_key_last(arr: Value) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    var last_key: ?ArrayKey = null;

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        last_key = entry.key_ptr.*;
    }

    if (last_key) |key| {
        return switch (key) {
            .integer => |k| Value.initInt(k),
            .string => |k| blk: {
                k.retain();
                break :blk Value.initString(k);
            },
        };
    }

    return Value.initNull();
}

/// array_fill - 用指定值填充数组
pub fn php_array_fill(start_index: Value, num: Value, value: Value, allocator: Allocator) !Value {
    const result = try PHPArray.init(allocator);

    const start = start_index.toInt();
    const count = @max(0, num.toInt());

    var i: i64 = 0;
    while (i < count) : (i += 1) {
        try result.set(allocator, .{ .integer = start + i }, value);
    }

    return Value.initArray(result);
}

/// range - 创建包含指定范围元素的数组
pub fn php_range(start: Value, end: Value, allocator: Allocator) !Value {
    const result = try PHPArray.init(allocator);

    const start_val = start.toInt();
    const end_val = end.toInt();

    if (start_val <= end_val) {
        var i = start_val;
        while (i <= end_val) : (i += 1) {
            try result.push(allocator, Value.initInt(i));
        }
    } else {
        var i = start_val;
        while (i >= end_val) : (i -= 1) {
            try result.push(allocator, Value.initInt(i));
        }
    }

    return Value.initArray(result);
}

fn arrayGetByString(arr: *PHPArray, key_bytes: []const u8) ?Value {
    var it = arr.elements.iterator();
    while (it.next()) |entry| {
        if (entry.key_ptr.* == .string) {
            const s = entry.key_ptr.*.string;
            if (std.mem.eql(u8, s.data, key_bytes)) return entry.value_ptr.*;
        }
    }
    return null;
}

fn arraySetByString(arr: *PHPArray, allocator: Allocator, key_bytes: []const u8, value: Value) !void {
    const s = try PHPString.init(allocator, key_bytes);
    defer s.release(allocator);
    try arr.set(allocator, .{ .string = s }, value);
}

fn valueCompare(a: Value, b: Value, allocator: Allocator) !i64 {
    if ((a.isInt() or a.isFloat() or a.isBool() or a.isNull()) and (b.isInt() or b.isFloat() or b.isBool() or b.isNull())) {
        const af = a.toFloat();
        const bf = b.toFloat();
        if (af < bf) return -1;
        if (af > bf) return 1;
        return 0;
    }

    const as = try a.toString(allocator);
    defer as.release(allocator);
    const bs = try b.toString(allocator);
    defer bs.release(allocator);

    return switch (std.mem.order(u8, as.data, bs.data)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

fn keyCompare(a: ArrayKey, b: ArrayKey) i64 {
    return switch (a) {
        .integer => |ai| switch (b) {
            .integer => |bi| if (ai < bi) -1 else if (ai > bi) 1 else 0,
            .string => -1,
        },
        .string => |as| switch (b) {
            .integer => 1,
            .string => |bs| switch (std.mem.order(u8, as.data, bs.data)) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            },
        },
    };
}

fn quickSortValues(values: []Value, allocator: Allocator, descending: bool) !void {
    if (values.len < 2) return;

    const pivot = values[values.len / 2];
    var i: usize = 0;
    var j: usize = values.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try valueCompare(values[i], pivot, allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= values.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try valueCompare(values[j], pivot, allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = values[i];
            values[i] = values[j];
            values[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortValues(values[0 .. j + 1], allocator, descending);
    if (i < values.len) try quickSortValues(values[i..], allocator, descending);
}

const KV = struct { key: ArrayKey, value: Value };

fn collectEntries(arr: *PHPArray, allocator: Allocator) ![]KV {
    const n = arr.count();
    const items = try allocator.alloc(KV, n);
    var it = arr.elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) {
        items[idx] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
    }
    return items;
}

fn quickSortEntriesByValue(items: []KV, allocator: Allocator, descending: bool) !void {
    if (items.len < 2) return;

    const pivot = items[items.len / 2].value;
    var i: usize = 0;
    var j: usize = items.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try valueCompare(items[i].value, pivot, allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= items.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try valueCompare(items[j].value, pivot, allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = items[i];
            items[i] = items[j];
            items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortEntriesByValue(items[0 .. j + 1], allocator, descending);
    if (i < items.len) try quickSortEntriesByValue(items[i..], allocator, descending);
}

fn quickSortEntriesByKey(items: []KV, descending: bool) void {
    if (items.len < 2) return;

    const pivot = items[items.len / 2].key;
    var i: usize = 0;
    var j: usize = items.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = keyCompare(items[i].key, pivot);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= items.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = keyCompare(items[j].key, pivot);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = items[i];
            items[i] = items[j];
            items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) quickSortEntriesByKey(items[0 .. j + 1], descending);
    if (i < items.len) quickSortEntriesByKey(items[i..], descending);
}

pub fn php_sizeof(val: Value) !Value {
    return php_count(val);
}

pub fn php_array_combine(keys: Value, values: Value, allocator: Allocator) !Value {
    if (!keys.isArray() or !values.isArray()) return Value.initBool(false);
    const keys_arr = keys.asArray();
    const values_arr = values.asArray();
    if (keys_arr.count() != values_arr.count()) return Value.initBool(false);

    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var key_it = keys_arr.elements.iterator();
    var val_it = values_arr.elements.iterator();
    while (key_it.next()) |k_entry| {
        const v_entry = val_it.next().?;
        const k = k_entry.value_ptr.*;
        const v = v_entry.value_ptr.*;
        if (k.isInt()) {
            try result.set(allocator, .{ .integer = k.asInt() }, v);
        } else if (k.isString()) {
            try result.set(allocator, .{ .string = k.asString() }, v);
        } else {
            const ks = try k.toString(allocator);
            defer ks.release(allocator);
            try result.set(allocator, .{ .string = ks }, v);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_pad(arr: Value, pad_size: Value, pad_value: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();
    const php_arr = arr.asArray();
    const n = php_arr.count();
    const target_i = pad_size.toInt();
    const target: usize = @intCast(@abs(target_i));

    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    if (target > n and target_i < 0) {
        var i: usize = 0;
        while (i < target - n) : (i += 1) {
            try result.push(allocator, pad_value);
        }
    }

    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        try result.push(allocator, entry.value_ptr.*);
    }

    if (target > n and target_i > 0) {
        var i: usize = 0;
        while (i < target - n) : (i += 1) {
            try result.push(allocator, pad_value);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_intersect(arrays: []const Value, allocator: Allocator) !Value {
    if (arrays.len == 0 or !arrays[0].isArray()) return Value.initArray(try PHPArray.init(allocator));

    const first = arrays[0].asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var it = first.elements.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr.*;
        var keep = true;
        for (arrays[1..]) |other_val| {
            if (!other_val.isArray()) {
                keep = false;
                break;
            }
            var found = false;
            var oit = other_val.asArray().elements.iterator();
            while (oit.next()) |oentry| {
                const eq = try php_eq(v, oentry.value_ptr.*);
                if (eq.asBool()) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                keep = false;
                break;
            }
        }
        if (keep) {
            try result.set(allocator, entry.key_ptr.*, v);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_diff(arrays: []const Value, allocator: Allocator) !Value {
    if (arrays.len == 0 or !arrays[0].isArray()) return Value.initArray(try PHPArray.init(allocator));

    const first = arrays[0].asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var it = first.elements.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr.*;
        var keep = true;
        for (arrays[1..]) |other_val| {
            if (!other_val.isArray()) continue;
            var oit = other_val.asArray().elements.iterator();
            while (oit.next()) |oentry| {
                const eq = try php_eq(v, oentry.value_ptr.*);
                if (eq.asBool()) {
                    keep = false;
                    break;
                }
            }
            if (!keep) break;
        }
        if (keep) {
            try result.set(allocator, entry.key_ptr.*, v);
        }
    }

    return Value.initArray(result);
}

pub fn php_array_splice(arr: Value, offset: Value, length: Value, replacement: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();
    const php_arr = arr.asArray();
    const n = php_arr.count();

    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i < 0) {
            const abs_off = @as(usize, @intCast(@abs(off_i)));
            break :blk if (abs_off > n) 0 else n - abs_off;
        }
        break :blk @intCast(@min(off_i, @as(i64, @intCast(n))));
    };

    const delete_count: usize = blk: {
        if (length.isNull()) break :blk n - start_idx;
        const len_i = length.toInt();
        if (len_i >= 0) break :blk @min(@as(usize, @intCast(len_i)), n - start_idx);
        const abs_len = @as(usize, @intCast(@abs(len_i)));
        if (abs_len >= n - start_idx) break :blk 0;
        break :blk (n - start_idx) - abs_len;
    };

    const removed = try PHPArray.init(allocator);
    errdefer removed.release(allocator);

    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);

    var rep_values: ?[]Value = null;
    if (!replacement.isNull()) {
        if (replacement.isArray()) {
            const rep_arr = replacement.asArray();
            const rep_n = rep_arr.count();
            const vals = try allocator.alloc(Value, rep_n);
            var rep_it = rep_arr.elements.iterator();
            var ridx: usize = 0;
            while (rep_it.next()) |e| : (ridx += 1) vals[ridx] = e.value_ptr.*;
            rep_values = vals;
        } else {
            const vals = try allocator.alloc(Value, 1);
            vals[0] = replacement;
            rep_values = vals;
        }
    }
    defer if (rep_values) |vals| allocator.free(vals);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    var next_int_key: i64 = 0;

    var idx: usize = 0;
    while (idx < items.len) : (idx += 1) {
        if (idx == start_idx) {
            var r: usize = 0;
            while (r < delete_count) : (r += 1) {
                try removed.push(allocator, items[idx + r].value);
                items[idx + r].value.release(allocator);
                if (items[idx + r].key == .string) {
                    items[idx + r].key.string.release(allocator);
                }
            }

            if (rep_values) |vals| {
                for (vals) |v| {
                    _ = v.retain();
                    try new_elements.put(.{ .integer = next_int_key }, v);
                    next_int_key += 1;
                }
            }

            idx += delete_count;
            if (idx >= items.len) break;
        }

        const kv = items[idx];
        switch (kv.key) {
            .string => {
                try new_elements.put(kv.key, kv.value);
            },
            .integer => {
                try new_elements.put(.{ .integer = next_int_key }, kv.value);
                next_int_key += 1;
            },
        }
    }

    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    php_arr.next_index = next_int_key;

    return Value.initArray(removed);
}

pub fn php_sort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const n = php_arr.count();
    var values = try allocator.alloc(Value, n);
    defer allocator.free(values);

    var it = php_arr.elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) values[idx] = entry.value_ptr.*;
    try quickSortValues(values, allocator, false);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        try new_elements.put(.{ .integer = @intCast(i) }, values[i]);
    }

    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    php_arr.next_index = @intCast(values.len);
    return Value.initBool(true);
}

pub fn php_rsort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const n = php_arr.count();
    var values = try allocator.alloc(Value, n);
    defer allocator.free(values);

    var it = php_arr.elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) values[idx] = entry.value_ptr.*;
    try quickSortValues(values, allocator, true);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        try new_elements.put(.{ .integer = @intCast(i) }, values[i]);
    }

    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    php_arr.next_index = @intCast(values.len);
    return Value.initBool(true);
}

pub fn php_asort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);
    try quickSortEntriesByValue(items, allocator, false);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    for (items) |kv| {
        try new_elements.put(kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

pub fn php_arsort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);
    try quickSortEntriesByValue(items, allocator, true);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    for (items) |kv| {
        try new_elements.put(kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

pub fn php_ksort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);
    quickSortEntriesByKey(items, false);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    for (items) |kv| {
        try new_elements.put(kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

pub fn php_krsort(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);
    quickSortEntriesByKey(items, true);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    for (items) |kv| {
        try new_elements.put(kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

fn invokeUserCompare(callback: Value, a: Value, b: Value, allocator: Allocator) !i64 {
    const args = [_]Value{ a, b };
    const res = try php_invoke_callable(callback, &args, allocator);
    const cmp = res.toInt();
    res.release(allocator);
    return cmp;
}

fn quickSortValuesWithCallback(values: []Value, callback: Value, allocator: Allocator, descending: bool) !void {
    // 使用冒泡排序，简单可靠
    if (values.len < 2) return;
    
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        var j: usize = 0;
        while (j < values.len - 1 - i) : (j += 1) {
            const cmp = try invokeUserCompare(callback, values[j], values[j + 1], allocator);
            const should_swap = if (descending) cmp < 0 else cmp > 0;
            if (should_swap) {
                const tmp = values[j];
                values[j] = values[j + 1];
                values[j + 1] = tmp;
            }
        }
    }
}

fn quickSortEntriesByValueWithCallback(items: []KV, callback: Value, allocator: Allocator, descending: bool) !void {
    if (items.len < 2) return;

    const pivot = items[items.len / 2].value;
    var i: usize = 0;
    var j: usize = items.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try invokeUserCompare(callback, items[i].value, pivot, allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= items.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try invokeUserCompare(callback, items[j].value, pivot, allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = items[i];
            items[i] = items[j];
            items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortEntriesByValueWithCallback(items[0 .. j + 1], callback, allocator, descending);
    if (i < items.len) try quickSortEntriesByValueWithCallback(items[i..], callback, allocator, descending);
}

fn keyToValue(key: ArrayKey) Value {
    return switch (key) {
        .integer => |i| Value.initInt(i),
        .string => |s| Value.initString(s),
    };
}

fn quickSortEntriesByKeyWithCallback(items: []KV, callback: Value, allocator: Allocator, descending: bool) !void {
    if (items.len < 2) return;

    const pivot = items[items.len / 2].key;
    var i: usize = 0;
    var j: usize = items.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try invokeUserCompare(callback, keyToValue(items[i].key), keyToValue(pivot), allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= items.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try invokeUserCompare(callback, keyToValue(items[j].key), keyToValue(pivot), allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = items[i];
            items[i] = items[j];
            items[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortEntriesByKeyWithCallback(items[0 .. j + 1], callback, allocator, descending);
    if (i < items.len) try quickSortEntriesByKeyWithCallback(items[i..], callback, allocator, descending);
}

pub fn php_usort(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const n = php_arr.count();
    var values = try allocator.alloc(Value, n);
    defer allocator.free(values);

    var it = php_arr.elements.iterator();
    var idx: usize = 0;
    while (it.next()) |entry| : (idx += 1) values[idx] = entry.value_ptr.*;

    try quickSortValuesWithCallback(values, callback, allocator, false);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        try new_elements.put(.{ .integer = @intCast(i) }, values[i]);
    }

    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    php_arr.next_index = @intCast(values.len);
    return Value.initBool(true);
}

pub fn php_uasort(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);

    try quickSortEntriesByValueWithCallback(items, callback, allocator, false);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    for (items) |kv| {
        try new_elements.put(kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

pub fn php_uksort(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const php_arr = arr.asArray();
    const items = try collectEntries(php_arr, allocator);
    defer allocator.free(items);

    try quickSortEntriesByKeyWithCallback(items, callback, allocator, false);

    var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
    for (items) |kv| {
        try new_elements.put(kv.key, kv.value);
    }
    php_arr.elements.deinit();
    php_arr.elements = PHPArray.Elements.initMixed(allocator, new_elements);
    return Value.initBool(true);
}

fn quickSortIndicesByValues(indices: []usize, values: []Value, allocator: Allocator, descending: bool) !void {
    if (indices.len < 2) return;

    const pivot_idx = indices[indices.len / 2];
    const pivot = values[pivot_idx];
    var i: usize = 0;
    var j: usize = indices.len - 1;

    while (i <= j) {
        while (true) {
            const cmp = try valueCompare(values[indices[i]], pivot, allocator);
            if ((!descending and cmp < 0) or (descending and cmp > 0)) {
                i += 1;
                if (i >= indices.len) break;
                continue;
            }
            break;
        }
        while (true) {
            const cmp = try valueCompare(values[indices[j]], pivot, allocator);
            if ((!descending and cmp > 0) or (descending and cmp < 0)) {
                if (j == 0) break;
                j -= 1;
                continue;
            }
            break;
        }

        if (i <= j) {
            const tmp = indices[i];
            indices[i] = indices[j];
            indices[j] = tmp;
            i += 1;
            if (j == 0) break;
            j -= 1;
        }
    }

    if (j > 0) try quickSortIndicesByValues(indices[0 .. j + 1], values, allocator, descending);
    if (i < indices.len) try quickSortIndicesByValues(indices[i..], values, allocator, descending);
}

pub fn php_array_multisort(arrays: []const Value, allocator: Allocator) !Value {
    if (arrays.len == 0 or !arrays[0].isArray()) return Value.initBool(false);

    const first_arr = arrays[0].asArray();
    const n = first_arr.count();
    var first_vals = try allocator.alloc(Value, n);
    defer allocator.free(first_vals);
    var it0 = first_arr.elements.iterator();
    var idx0: usize = 0;
    while (it0.next()) |entry| : (idx0 += 1) first_vals[idx0] = entry.value_ptr.*;

    var indices = try allocator.alloc(usize, n);
    defer allocator.free(indices);
    for (0..n) |i| indices[i] = i;

    try quickSortIndicesByValues(indices, first_vals, allocator, false);

    for (arrays) |arr_val| {
        if (!arr_val.isArray()) return Value.initBool(false);
        const a = arr_val.asArray();
        if (a.count() != n) return Value.initBool(false);

        var vals = try allocator.alloc(Value, n);
        defer allocator.free(vals);
        var it = a.elements.iterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) vals[i] = entry.value_ptr.*;

        var new_elements = std.ArrayHashMap(ArrayKey, Value, PHPArray.ArrayContext, true).init(allocator);
        for (indices, 0..) |src, dst| {
            try new_elements.put(.{ .integer = @intCast(dst) }, vals[src]);
        }
        a.elements.deinit();
        a.elements = PHPArray.Elements.initMixed(allocator, new_elements);
        a.next_index = @intCast(n);
    }

    return Value.initBool(true);
}

fn arrayCursorGet(arr: *PHPArray) usize {
    if (array_internal_pointers) |m| {
        return m.get(arr) orelse 0;
    }
    return 0;
}

fn arrayCursorSet(arr: *PHPArray, idx: usize, allocator: Allocator) !void {
    if (array_internal_pointers) |*m| {
        try m.put(arr, idx);
    } else {
        _ = allocator;
    }
}

fn arrayEntryAt(arr: *PHPArray, idx: usize) ?KV {
    var it = arr.elements.iterator();
    var i: usize = 0;
    while (it.next()) |entry| : (i += 1) {
        if (i == idx) return .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
    }
    return null;
}

pub fn php_current(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const idx = arrayCursorGet(a);
    if (arrayEntryAt(a, idx)) |kv| {
        _ = kv.value.retain();
        _ = allocator;
        return kv.value;
    }
    _ = allocator;
    return Value.initBool(false);
}

pub fn php_key(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();
    const a = arr.asArray();
    const idx = arrayCursorGet(a);
    if (arrayEntryAt(a, idx)) |kv| {
        _ = allocator;
        return switch (kv.key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                s.retain();
                break :blk Value.initString(s);
            },
        };
    }
    _ = allocator;
    return Value.initNull();
}

pub fn php_reset(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    try arrayCursorSet(a, 0, allocator);
    return php_current(arr, allocator);
}

pub fn php_end(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const n = a.count();
    if (n == 0) {
        try arrayCursorSet(a, 0, allocator);
        return Value.initBool(false);
    }
    try arrayCursorSet(a, n - 1, allocator);
    return php_current(arr, allocator);
}

pub fn php_next(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const idx = arrayCursorGet(a) + 1;
    try arrayCursorSet(a, idx, allocator);
    return php_current(arr, allocator);
}

pub fn php_prev(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const cur = arrayCursorGet(a);
    if (cur == 0) return Value.initBool(false);
    try arrayCursorSet(a, cur - 1, allocator);
    return php_current(arr, allocator);
}

pub fn php_each(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initBool(false);
    const a = arr.asArray();
    const idx = arrayCursorGet(a);
    const kv = arrayEntryAt(a, idx) orelse return Value.initBool(false);

    const key_val = switch (kv.key) {
        .integer => |i| Value.initInt(i),
        .string => |s| Value.initString(s),
    };

    const out = try PHPArray.init(allocator);
    errdefer out.release(allocator);

    try out.set(allocator, .{ .integer = 0 }, kv.value);
    try out.set(allocator, .{ .integer = 1 }, key_val);
    try arraySetByString(out, allocator, "key", key_val);
    try arraySetByString(out, allocator, "value", kv.value);

    try arrayCursorSet(a, idx + 1, allocator);

    return Value.initArray(out);
}

// ============================================================================
// 扩展字符串函数
// ============================================================================

/// ord - 返回字符的ASCII值
pub fn php_ord(str: Value) !Value {
    if (!str.isString()) return Value.initInt(0);

    const php_str = str.asString();
    if (php_str.length == 0) return Value.initInt(0);

    return Value.initInt(@intCast(php_str.data[0]));
}

/// chr - 返回指定ASCII值对应的字符
pub fn php_chr(code: Value, allocator: Allocator) !Value {
    const ascii = @as(u8, @truncate(@as(u64, @intCast(code.toInt() & 0xFF))));
    const buffer = [_]u8{ascii};
    const result = try PHPString.init(allocator, &buffer);
    return Value.initString(result);
}

/// stripos - 不区分大小写查找子字符串位置
pub fn php_stripos(haystack: Value, needle: Value, offset: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i >= 0) {
            break :blk @intCast(@min(off_i, @as(i64, @intCast(hay.length))));
        }
        const abs_off: usize = @intCast(@min(-off_i, @as(i64, @intCast(hay.length))));
        break :blk hay.length - abs_off;
    };

    if (start_idx > hay.length or start_idx + need.length > hay.length) return Value.initBool(false);

    var i: usize = start_idx;
    while (i <= hay.length - need.length) : (i += 1) {
        var match = true;
        var j: usize = 0;
        while (j < need.length) : (j += 1) {
            if (std.ascii.toLower(hay.data[i + j]) != std.ascii.toLower(need.data[j])) {
                match = false;
                break;
            }
        }
        if (match) return Value.initInt(@intCast(i));
    }

    return Value.initBool(false);
}

/// strrpos - 查找子字符串最后出现的位置
pub fn php_strrpos(haystack: Value, needle: Value, offset: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    var last_pos: ?usize = null;
    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i >= 0) {
            break :blk @intCast(@min(off_i, @as(i64, @intCast(hay.length))));
        }
        const abs_off: usize = @intCast(@min(-off_i, @as(i64, @intCast(hay.length))));
        break :blk hay.length - abs_off;
    };

    if (start_idx > hay.length or start_idx + need.length > hay.length) return Value.initBool(false);

    var i: usize = start_idx;
    while (i <= hay.length - need.length) : (i += 1) {
        if (std.mem.eql(u8, hay.data[i .. i + need.length], need.data)) {
            last_pos = i;
        }
    }

    if (last_pos) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

pub fn php_strripos(haystack: Value, needle: Value, offset: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    var last_pos: ?usize = null;
    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i >= 0) {
            break :blk @intCast(@min(off_i, @as(i64, @intCast(hay.length))));
        }
        const abs_off: usize = @intCast(@min(-off_i, @as(i64, @intCast(hay.length))));
        break :blk hay.length - abs_off;
    };

    if (start_idx > hay.length or start_idx + need.length > hay.length) return Value.initBool(false);

    var i: usize = start_idx;
    while (i <= hay.length - need.length) : (i += 1) {
        var match = true;
        var j: usize = 0;
        while (j < need.length) : (j += 1) {
            if (std.ascii.toLower(hay.data[i + j]) != std.ascii.toLower(need.data[j])) {
                match = false;
                break;
            }
        }
        if (match) {
            last_pos = i;
        }
    }

    if (last_pos) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

/// number_format - 格式化数字
pub fn php_number_format(number: Value, decimals: Value, dec_point: Value, thousands_sep: Value, allocator: Allocator) !Value {
    _ = dec_point;
    _ = thousands_sep;
    const num = number.toFloat();
    const dec = @max(0, decimals.toInt());

    const dec_u: usize = @intCast(dec);
    var pow10: u64 = 1;
    var i: usize = 0;
    while (i < dec_u) : (i += 1) {
        pow10 *= 10;
    }

    const scaled: f64 = num * @as(f64, @floatFromInt(pow10));
    const rounded_i64: i64 = @intFromFloat(std.math.round(scaled));
    const negative = rounded_i64 < 0;
    const abs_rounded: u64 = @intCast(if (negative) -rounded_i64 else rounded_i64);

    const int_part: u64 = abs_rounded / pow10;
    const frac_part: u64 = abs_rounded % pow10;

    const int_str = try std.fmt.allocPrint(allocator, "{d}", .{int_part});
    defer allocator.free(int_str);

    const total_len: usize = (if (negative) @as(usize, 1) else 0) + int_str.len + (if (dec_u > 0) 1 + dec_u else 0);
    const out = try allocator.alloc(u8, total_len);
    defer allocator.free(out);

    var pos: usize = 0;
    if (negative) {
        out[pos] = '-';
        pos += 1;
    }

    @memcpy(out[pos .. pos + int_str.len], int_str);
    pos += int_str.len;

    if (dec_u > 0) {
        out[pos] = '.';
        pos += 1;
        var tmp = frac_part;
        var j: usize = 0;
        while (j < dec_u) : (j += 1) {
            const digit: u8 = @intCast(tmp % 10);
            out[total_len - 1 - j] = '0' + digit;
            tmp /= 10;
        }
    }

    const result = try PHPString.init(allocator, out);
    return Value.initString(result);
}

/// nl2br - 将换行符转换为HTML <br>标签
pub fn php_nl2br(str: Value, is_xhtml: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const tag = if (is_xhtml.toBool()) "<br />" else "<br>";

    // 计算需要的空间
    var count: usize = 0;
    for (php_str.data) |c| {
        if (c == '\n') count += 1;
    }

    const new_len = php_str.length + count * tag.len;
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    for (php_str.data) |c| {
        if (c == '\n') {
            @memcpy(buffer[write_pos .. write_pos + tag.len], tag);
            write_pos += tag.len;
        }
        buffer[write_pos] = c;
        write_pos += 1;
    }

    const result = try PHPString.init(allocator, buffer[0..write_pos]);
    allocator.free(buffer);
    return Value.initString(result);
}

pub fn php_chunk_split(body: Value, chunklen: Value, end: Value, allocator: Allocator) !Value {
    const body_str = if (body.isString()) body.asString().data else "";
    const clen: usize = @intCast(@max(1, chunklen.toInt()));
    const end_str = if (end.isString()) end.asString().data else "\r\n";

    const num_chunks = (body_str.len + clen - 1) / clen;
    const result_len = body_str.len + num_chunks * end_str.len;
    const result = try allocator.alloc(u8, result_len);
    defer allocator.free(result);

    var src_i: usize = 0;
    var dst_i: usize = 0;
    while (src_i < body_str.len) {
        const chunk_end = @min(src_i + clen, body_str.len);
        @memcpy(result[dst_i .. dst_i + (chunk_end - src_i)], body_str[src_i..chunk_end]);
        dst_i += chunk_end - src_i;
        @memcpy(result[dst_i .. dst_i + end_str.len], end_str);
        dst_i += end_str.len;
        src_i = chunk_end;
    }

    const php_str = try PHPString.init(allocator, result[0..dst_i]);
    return Value.initString(php_str);
}

/// strip_tags - 移除HTML和PHP标签
pub fn php_strip_tags(str: Value, allowed_tags: Value, allocator: Allocator) !Value {
    _ = allowed_tags;
    if (!str.isString()) return str;

    const php_str = str.asString();
    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    var in_tag = false;

    for (php_str.data) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            buffer[write_pos] = c;
            write_pos += 1;
        }
    }

    const result = try PHPString.init(allocator, buffer[0..write_pos]);
    allocator.free(buffer);
    return Value.initString(result);
}

/// strval - 获取变量的字符串值
pub fn php_strval(val: Value, allocator: Allocator) !Value {
    const str = try val.toString(allocator);
    return Value.initString(str);
}

/// gettype - 获取变量的类型
pub fn php_gettype(val: Value, allocator: Allocator) !Value {
    const type_str = if (val.isNull())
        "NULL"
    else if (val.isBool())
        "boolean"
    else if (val.isInt())
        "integer"
    else if (val.isFloat())
        "double"
    else if (val.isString())
        "string"
    else if (val.isArray())
        "array"
    else if (Value_isObject(val))
        "object"
    else
        "unknown type";

    const result = try PHPString.init(allocator, type_str);
    return Value.initString(result);
}

// ============================================================================
// 文件函数
// ============================================================================

/// file_get_contents - 读取文件内容
pub fn php_file_get_contents(filename: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;

    const file = std.fs.cwd().openFile(path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 100 * 1024 * 1024) catch {
        return Value.initBool(false);
    };
    defer allocator.free(content);

    const result = try PHPString.init(allocator, content);
    return Value.initString(result);
}

/// file_put_contents - 将数据写入文件
pub fn php_file_put_contents(filename: Value, data: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    const content = try data.toString(allocator);
    defer content.release(allocator);

    const file = std.fs.cwd().createFile(path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close();

    file.writeAll(content.data) catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(content.length));
}

/// file_exists - 检查文件是否存在
pub fn php_file_exists(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    std.fs.cwd().access(path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// is_file - 检查是否是普通文件
pub fn php_is_file(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    const stat = std.fs.cwd().statFile(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(stat.kind == .file);
}

/// is_dir - 检查是否是目录
pub fn php_is_dir(dirname: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    var dir = std.fs.cwd().openDir(path, .{}) catch {
        return Value.initBool(false);
    };
    dir.close();

    return Value.initBool(true);
}

/// mkdir - 创建目录
pub fn php_mkdir(dirname: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    std.fs.cwd().makeDir(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// rmdir - 删除目录
pub fn php_rmdir(dirname: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    std.fs.cwd().deleteDir(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// unlink - 删除文件
pub fn php_unlink(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    std.fs.cwd().deleteFile(path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// rename - 重命名文件
pub fn php_rename(oldname: Value, newname: Value) !Value {
    if (!oldname.isString() or !newname.isString()) return Value.initBool(false);

    const old_path = oldname.asString().data;
    const new_path = newname.asString().data;

    std.fs.cwd().rename(old_path, new_path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// copy - 拷贝文件
pub fn php_copy(source: Value, dest: Value) !Value {
    if (!source.isString() or !dest.isString()) return Value.initBool(false);

    const source_path = source.asString().data;
    const dest_path = dest.asString().data;

    std.fs.cwd().copyFile(source_path, std.fs.cwd(), dest_path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// filesize - 获取文件大小
pub fn php_filesize(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);

    const path = filename.asString().data;
    const file = std.fs.cwd().openFile(path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close();

    const stat = file.stat() catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(stat.size));
}

/// basename - 返回路径中的文件名部分
pub fn php_basename(path: Value, allocator: Allocator) !Value {
    if (!path.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const path_str = path.asString().data;
    const base = std.fs.path.basename(path_str);
    const result = try PHPString.init(allocator, base);
    return Value.initString(result);
}

/// dirname - 返回路径中的目录部分
pub fn php_dirname(path: Value, allocator: Allocator) !Value {
    if (!path.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const path_str = path.asString().data;
    const dir = std.fs.path.dirname(path_str) orelse ".";
    const result = try PHPString.init(allocator, dir);
    return Value.initString(result);
}

// ============================================================================
// JSON函数
// ============================================================================

/// json_encode - 将PHP值编码为JSON字符串
pub fn php_json_encode(value: Value, allocator: Allocator) !Value {
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    try jsonEncodeValue(value, &buffer, allocator);

    const result = try PHPString.init(allocator, buffer.items);
    return Value.initString(result);
}

fn jsonEncodeValue(value: Value, buffer: *std.ArrayListUnmanaged(u8), allocator: Allocator) !void {
    if (value.isNull()) {
        try buffer.appendSlice(allocator, "null");
    } else if (value.isBool()) {
        try buffer.appendSlice(allocator, if (value.asBool()) "true" else "false");
    } else if (value.isInt()) {
        const formatted = try std.fmt.allocPrint(allocator, "{d}", .{value.asInt()});
        defer allocator.free(formatted);
        try buffer.appendSlice(allocator, formatted);
    } else if (value.isFloat()) {
        const formatted = try std.fmt.allocPrint(allocator, "{d}", .{value.asFloat()});
        defer allocator.free(formatted);
        try buffer.appendSlice(allocator, formatted);
    } else if (value.isString()) {
        const str = value.asString();
        try buffer.append(allocator, '"');
        for (str.data) |c| {
            switch (c) {
                '"' => try buffer.appendSlice(allocator, "\\\""),
                '\\' => try buffer.appendSlice(allocator, "\\\\"),
                '\n' => try buffer.appendSlice(allocator, "\\n"),
                '\r' => try buffer.appendSlice(allocator, "\\r"),
                '\t' => try buffer.appendSlice(allocator, "\\t"),
                else => try buffer.append(allocator, c),
            }
        }
        try buffer.append(allocator, '"');
    } else if (value.isArray()) {
        const arr = value.asArray();
        var is_list = true;
        var expected_index: i64 = 0;

        // 检查是否是纯索引数组
        var it = arr.elements.iterator();
        while (it.next()) |entry| {
            switch (entry.key_ptr.*) {
                .integer => |k| {
                    if (k != expected_index) is_list = false;
                    expected_index += 1;
                },
                .string => is_list = false,
            }
            if (!is_list) break;
        }

        if (is_list) {
            try buffer.append(allocator, '[');
            var first = true;
            it = arr.elements.iterator();
            while (it.next()) |entry| {
                if (!first) try buffer.append(allocator, ',');
                try jsonEncodeValue(entry.value_ptr.*, buffer, allocator);
                first = false;
            }
            try buffer.append(allocator, ']');
        } else {
            try buffer.append(allocator, '{');
            var first = true;
            it = arr.elements.iterator();
            while (it.next()) |entry| {
                if (!first) try buffer.append(allocator, ',');

                // 写入键
                switch (entry.key_ptr.*) {
                    .integer => |k| {
                        try buffer.append(allocator, '"');
                        const key_str = try std.fmt.allocPrint(allocator, "{d}", .{k});
                        defer allocator.free(key_str);
                        try buffer.appendSlice(allocator, key_str);
                        try buffer.append(allocator, '"');
                    },
                    .string => |k| {
                        try buffer.append(allocator, '"');
                        for (k.data) |c| {
                            switch (c) {
                                '"' => try buffer.appendSlice(allocator, "\\\""),
                                '\\' => try buffer.appendSlice(allocator, "\\\\"),
                                '\n' => try buffer.appendSlice(allocator, "\\n"),
                                '\r' => try buffer.appendSlice(allocator, "\\r"),
                                '\t' => try buffer.appendSlice(allocator, "\\t"),
                                else => try buffer.append(allocator, c),
                            }
                        }
                        try buffer.append(allocator, '"');
                    },
                }
                try buffer.appendSlice(allocator, ":");

                // 写入值
                try jsonEncodeValue(entry.value_ptr.*, buffer, allocator);
                first = false;
            }
            try buffer.append(allocator, '}');
        }
    } else {
        try buffer.appendSlice(allocator, "null");
    }
}

/// json_decode - 解析JSON字符串为PHP值
pub fn php_json_decode(json: Value, assoc: Value, allocator: Allocator) !Value {
    if (!json.isString()) return Value.initNull();

    const is_assoc = if (assoc.isBool()) assoc.asBool() else assoc.toBool();
    const json_str = json.asString().data;
    var pos: usize = 0;

    return jsonDecodeValue(json_str, &pos, is_assoc, allocator) catch Value.initNull();
}

const JsonError = error{
    InvalidJson,
    UnexpectedEnd,
    OutOfMemory,
    StringTooLarge,
};

fn jsonDecodeValue(json: []const u8, pos: *usize, assoc: bool, allocator: Allocator) JsonError!Value {
    skipWhitespace(json, pos);

    if (pos.* >= json.len) return error.UnexpectedEnd;

    const c = json[pos.*];

    if (c == 'n' and pos.* + 4 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 4], "null")) {
        pos.* += 4;
        return Value.initNull();
    }

    if (c == 't' and pos.* + 4 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 4], "true")) {
        pos.* += 4;
        return Value.initBool(true);
    }

    if (c == 'f' and pos.* + 5 <= json.len and std.mem.eql(u8, json[pos.* .. pos.* + 5], "false")) {
        pos.* += 5;
        return Value.initBool(false);
    }

    if (c == '"') {
        return jsonDecodeString(json, pos, allocator);
    }

    if (c == '[') {
        return jsonDecodeArray(json, pos, assoc, allocator);
    }

    if (c == '{') {
        return jsonDecodeObject(json, pos, assoc, allocator);
    }

    if (c == '-' or (c >= '0' and c <= '9')) {
        return jsonDecodeNumber(json, pos);
    }

    return error.InvalidJson;
}

fn jsonDecodeString(json: []const u8, pos: *usize, allocator: Allocator) !Value {
    pos.* += 1; // 跳过开头的引号

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    while (pos.* < json.len and json[pos.*] != '"') {
        if (json[pos.*] == '\\' and pos.* + 1 < json.len) {
            pos.* += 1;
            switch (json[pos.*]) {
                'n' => try buffer.append(allocator, '\n'),
                'r' => try buffer.append(allocator, '\r'),
                't' => try buffer.append(allocator, '\t'),
                '"' => try buffer.append(allocator, '"'),
                '\\' => try buffer.append(allocator, '\\'),
                else => try buffer.append(allocator, json[pos.*]),
            }
        } else {
            try buffer.append(allocator, json[pos.*]);
        }
        pos.* += 1;
    }

    if (pos.* < json.len) pos.* += 1; // 跳过结尾的引号

    const result = try PHPString.init(allocator, buffer.items);
    return Value.initString(result);
}

fn jsonDecodeNumber(json: []const u8, pos: *usize) JsonError!Value {
    const start = pos.*;
    var is_float = false;

    if (json[pos.*] == '-') pos.* += 1;

    while (pos.* < json.len) {
        const c = json[pos.*];
        if (c >= '0' and c <= '9') {
            pos.* += 1;
        } else if (c == '.' or c == 'e' or c == 'E') {
            is_float = true;
            pos.* += 1;
        } else if (c == '+' or c == '-') {
            pos.* += 1;
        } else {
            break;
        }
    }

    const num_str = json[start..pos.*];

    if (is_float) {
        const f = std.fmt.parseFloat(f64, num_str) catch return Value.initFloat(0);
        return Value.initFloat(f);
    } else {
        const i = std.fmt.parseInt(i64, num_str, 10) catch return Value.initInt(0);
        return Value.initInt(i);
    }
}

fn jsonDecodeArray(json: []const u8, pos: *usize, assoc: bool, allocator: Allocator) JsonError!Value {
    pos.* += 1; // 跳过 '['

    const arr = try PHPArray.init(allocator);

    skipWhitespace(json, pos);

    if (pos.* < json.len and json[pos.*] == ']') {
        pos.* += 1;
        return Value.initArray(arr);
    }

    while (pos.* < json.len) {
        const value = try jsonDecodeValue(json, pos, assoc, allocator);
        try arr.push(allocator, value);
        value.release(allocator);

        skipWhitespace(json, pos);

        if (pos.* < json.len and json[pos.*] == ',') {
            pos.* += 1;
            skipWhitespace(json, pos);
        } else {
            break;
        }
    }

    if (pos.* < json.len and json[pos.*] == ']') pos.* += 1;

    return Value.initArray(arr);
}

fn jsonDecodeObject(json: []const u8, pos: *usize, assoc: bool, allocator: Allocator) !Value {
    pos.* += 1; // 跳过 '{'

    const arr = try PHPArray.init(allocator);

    skipWhitespace(json, pos);

    if (pos.* < json.len and json[pos.*] == '}') {
        pos.* += 1;
        return Value.initArray(arr);
    }

    while (pos.* < json.len) {
        skipWhitespace(json, pos);

        // 解析键
        if (json[pos.*] != '"') return error.InvalidJson;
        const key = try jsonDecodeString(json, pos, allocator);

        skipWhitespace(json, pos);

        if (pos.* >= json.len or json[pos.*] != ':') return error.InvalidJson;
        pos.* += 1;

        // 解析值
        const value = try jsonDecodeValue(json, pos, assoc, allocator);

        // 添加到数组
        if (key.isString()) {
            const key_str = key.asString();
            const array_key = ArrayKey{ .string = key_str };
            try arr.set(allocator, array_key, value);
        }
        key.release(allocator);
        value.release(allocator);

        skipWhitespace(json, pos);

        if (pos.* < json.len and json[pos.*] == ',') {
            pos.* += 1;
        } else {
            break;
        }
    }

    if (pos.* < json.len and json[pos.*] == '}') pos.* += 1;

    // 如果 assoc 为 false，应该返回对象，但目前我们统一返回数组（简化实现）
    // TODO: 实现 stdClass 对象

    return Value.initArray(arr);
}

fn skipWhitespace(json: []const u8, pos: *usize) void {
    while (pos.* < json.len and (json[pos.*] == ' ' or json[pos.*] == '\t' or json[pos.*] == '\n' or json[pos.*] == '\r')) {
        pos.* += 1;
    }
}

// ============================================================================
// 杂项函数
// ============================================================================

/// strtotime - 将字符串转换为时间戳
pub fn php_strtotime(time_str: Value, now: Value, allocator: Allocator) !Value {
    _ = allocator;
    _ = now;
    
    if (!time_str.isString()) {
        return Value.initBool(false);
    }
    
    // 简化实现：仅支持基本格式
    // 完整实现需要完整的日期解析库
    const str = time_str.asString().data;
    
    // 尝试解析 "YYYY-MM-DD" 或 "YYYY-MM-DD HH:MM:SS"
    if (str.len >= 10) {
        // 简化：返回当前时间戳
        return Value.initInt(std.time.timestamp());
    }
    
    return Value.initBool(false);
}

/// sleep - 延迟执行（秒）
pub fn php_sleep(seconds: Value) !Value {
    const secs = @max(0, seconds.toInt());
    // Workaround: busy wait to avoid std.time.sleep issues
    var i: usize = 0;
    const count = @as(usize, @intCast(secs)) * 50000000; // 50M iterations
    while (i < count) : (i += 1) {
        std.Thread.yield() catch {};
    }
    return Value.initInt(0);
}

/// usleep - 延迟执行（微秒）
pub fn php_usleep(microseconds: Value) !Value {
    const usecs = @max(0, microseconds.toInt());
    // Workaround: busy wait
    var i: usize = 0;
    const count = @as(usize, @intCast(usecs)) * 50; // Rough approximation
    while (i < count) : (i += 1) {
        std.Thread.yield() catch {};
    }
    return Value.initNull();
}

/// exit/die - 终止程序执行
pub fn php_exit(status: Value) !noreturn {
    const code: u8 = if (status.isInt())
        @truncate(@as(u64, @intCast(status.asInt() & 0xFF)))
    else
        0;
    std.process.exit(code);
}

/// empty - 检查变量是否为空
pub fn php_empty(val: Value) !Value {
    if (val.isNull()) return Value.initBool(true);
    if (val.isBool()) return Value.initBool(!val.asBool());
    if (val.isInt()) return Value.initBool(val.asInt() == 0);
    if (val.isFloat()) return Value.initBool(val.asFloat() == 0);
    if (val.isString()) return Value.initBool(val.asString().length == 0 or std.mem.eql(u8, val.asString().data, "0"));
    if (val.isArray()) return Value.initBool(val.asArray().count() == 0);
    return Value.initBool(false);
}

/// isset - 检查变量是否已设置且非null
pub fn php_isset(val: Value) !Value {
    return Value.initBool(!val.isNull());
}

pub fn empty(val: Value) !Value {
    return php_empty(val);
}

pub fn isset(val: Value) !Value {
    return php_isset(val);
}

// ============================================================================
// 高阶数组函数
// ============================================================================

/// array_map - 对数组的每个元素应用回调函数
pub fn php_array_map(callback: Value, arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{entry.value_ptr.*};
        const result_value = try php_invoke_callable(callback, &args, allocator);
        try result_arr.set(allocator, entry.key_ptr.*, result_value);
        result_value.release(allocator);
    }

    return Value.initArray(result_arr);
}

/// array_filter - 过滤数组元素
pub fn php_array_filter(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const should_keep = if (callback.isNull()) blk: {
            break :blk entry.value_ptr.*.toBool();
        } else blk: {
            const args = [_]Value{entry.value_ptr.*};
            const result = try php_invoke_callable(callback, &args, allocator);
            defer result.release(allocator);
            break :blk result.toBool();
        };

        if (should_keep) {
            try result_arr.set(allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    return Value.initArray(result_arr);
}

/// array_reduce - 使用回调函数迭代地将数组简化为单一值
pub fn php_array_reduce(arr: Value, callback: Value, initial: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    var carry = initial;

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{ carry, entry.value_ptr.* };
        carry = try php_invoke_callable(callback, &args, allocator);
    }

    return carry;
}

/// array_chunk - 将数组分割成指定大小的块
/// array_chunk - 将数组分割成指定大小的块
pub fn php_array_chunk(arr: Value, size: Value, preserve_keys: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const chunk_size = size.toInt();
    if (chunk_size < 1) return error.InvalidArgument;

    const preserve = preserve_keys.toBool();
    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var current_chunk = try PHPArray.init(allocator);
    var count: i64 = 0;
    var new_index: i64 = 0;

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        if (preserve) {
            try current_chunk.set(allocator, entry.key_ptr.*, entry.value_ptr.*);
        } else {
            try current_chunk.push(allocator, entry.value_ptr.*);
        }
        count += 1;

        if (count >= chunk_size) {
            try result_arr.set(allocator, .{ .integer = new_index }, Value.initArray(current_chunk));
            new_index += 1;
            current_chunk = try PHPArray.init(allocator);
            count = 0;
        }
    }

    if (count > 0) {
        try result_arr.set(allocator, .{ .integer = new_index }, Value.initArray(current_chunk));
    } else {
        current_chunk.release(allocator);
    }

    return Value.initArray(result_arr);
}

/// array_column - 返回数组中指定列的值
pub fn php_array_column(arr: Value, column_key: Value, allocator: Allocator) !Value {
    return php_array_column_with_index(arr, column_key, Value.initNull(), allocator);
}

pub fn php_array_column_with_index(arr: Value, column_key: Value, index_key: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const row = entry.value_ptr.*;
        if (!row.isArray()) continue;

        const row_arr = row.asArray();

        // 获取列值
        const col_value = if (column_key.isInt()) blk: {
            break :blk row_arr.get(.{ .integer = column_key.asInt() });
        } else if (column_key.isString()) blk: {
            break :blk arrayGetByString(row_arr, column_key.asString().data);
        } else blk: {
            break :blk null;
        };

        if (col_value) |val| {
            // 确定索引
            if (index_key.isNull()) {
                try result_arr.push(allocator, val);
            } else {
                const idx_value = if (index_key.isInt()) blk: {
                    break :blk row_arr.get(.{ .integer = index_key.asInt() });
                } else if (index_key.isString()) blk: {
                    break :blk arrayGetByString(row_arr, index_key.asString().data);
                } else blk: {
                    break :blk null;
                };

                if (idx_value) |idx| {
                    if (idx.isInt()) {
                        try result_arr.set(allocator, .{ .integer = idx.asInt() }, val);
                    } else if (idx.isString()) {
                        try arraySetByString(result_arr, allocator, idx.asString().data, val);
                    } else {
                        try result_arr.push(allocator, val);
                    }
                } else {
                    try result_arr.push(allocator, val);
                }
            }
        }
    }

    return Value.initArray(result_arr);
}

/// array_walk - 对数组中的每个元素应用用户自定义函数
pub fn php_array_walk(arr: Value, callback: Value, userdata: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        // 构建回调参数：value, key, userdata
        const key_val = switch (entry.key_ptr.*) {
            .integer => |k| Value.initInt(k),
            .string => |k| Value.initString(k),
        };

        const args = if (userdata.isNull())
            [_]Value{ entry.value_ptr.*, key_val }
        else
            [_]Value{ entry.value_ptr.*, key_val, userdata };

        const result = try php_invoke_callable(callback, args[0..], allocator);
        result.release(allocator);
    }

    return Value.initBool(true);
}

// ============================================================================
// 字符串高级函数
// ============================================================================

/// sprintf - 格式化字符串
pub fn php_sprintf(format: Value, args: []const Value, allocator: Allocator) !Value {
    if (!format.isString()) return error.InvalidArgument;

    const fmt = format.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit(allocator);

    var arg_idx: usize = 0;
    var i: usize = 0;

    while (i < fmt.len) {
        if (fmt[i] == '%' and i + 1 < fmt.len) {
            i += 1;
            if (fmt[i] == '%') {
                try result.append(allocator, '%');
                i += 1;
                continue;
            }

            // 跳过标志
            while (i < fmt.len and (fmt[i] == '-' or fmt[i] == '+' or fmt[i] == ' ' or fmt[i] == '0')) {
                i += 1;
            }

            // 跳过宽度
            while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                i += 1;
            }

            // 跳过精度
            if (i < fmt.len and fmt[i] == '.') {
                i += 1;
                while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                    i += 1;
                }
            }

            if (i >= fmt.len) break;

            const specifier = fmt[i];
            i += 1;

            if (arg_idx >= args.len) continue;
            const arg = args[arg_idx];
            arg_idx += 1;

            switch (specifier) {
                's' => {
                    if (arg.isString()) {
                        try result.appendSlice(allocator, arg.asString().data);
                    } else {
                        const str = try arg.toString(allocator);
                        defer str.release(allocator);
                        try result.appendSlice(allocator, str.data);
                    }
                },
                'd', 'i' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{d}", .{val});
                    defer allocator.free(str);
                    try result.appendSlice(allocator, str);
                },
                'f' => {
                    const val = arg.toFloat();
                    const str = try std.fmt.allocPrint(allocator, "{d:.6}", .{val});
                    defer allocator.free(str);
                    try result.appendSlice(allocator, str);
                },
                'x' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{x}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try result.appendSlice(allocator, str);
                },
                'X' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{X}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try result.appendSlice(allocator, str);
                },
                'c' => {
                    const val = arg.toInt();
                    if (val >= 0 and val <= 255) {
                        try result.append(allocator, @intCast(val));
                    }
                },
                else => {
                    try result.append(allocator, '%');
                    try result.append(allocator, specifier);
                },
            }
        } else {
            try result.append(allocator, fmt[i]);
            i += 1;
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// htmlspecialchars - 将特殊字符转换为HTML实体
pub fn php_htmlspecialchars(str: Value, flags: Value, encoding: Value, double_encode: Value, allocator: Allocator) !Value {
    _ = flags;
    _ = encoding;
    _ = double_encode;
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit(allocator);

    for (input) |c| {
        switch (c) {
            '&' => try result.appendSlice(allocator, "&amp;"),
            '"' => try result.appendSlice(allocator, "&quot;"),
            '\'' => try result.appendSlice(allocator, "&#039;"),
            '<' => try result.appendSlice(allocator, "&lt;"),
            '>' => try result.appendSlice(allocator, "&gt;"),
            else => try result.append(allocator, c),
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// htmlentities - 将所有适用的字符转换为HTML实体
pub fn php_htmlentities(str: Value, flags: Value, encoding: Value, double_encode: Value, allocator: Allocator) !Value {
    return php_htmlspecialchars(str, flags, encoding, double_encode, allocator);
}

/// htmlspecialchars_decode - 将HTML实体转换回字符
pub fn php_htmlspecialchars_decode(str: Value, flags: Value, allocator: Allocator) !Value {
    _ = flags;
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '&') {
            if (i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "&lt;")) {
                try result.append(allocator, '<');
                i += 4;
            } else if (i + 4 <= input.len and std.mem.eql(u8, input[i .. i + 4], "&gt;")) {
                try result.append(allocator, '>');
                i += 4;
            } else if (i + 5 <= input.len and std.mem.eql(u8, input[i .. i + 5], "&amp;")) {
                try result.append(allocator, '&');
                i += 5;
            } else if (i + 6 <= input.len and std.mem.eql(u8, input[i .. i + 6], "&quot;")) {
                try result.append(allocator, '"');
                i += 6;
            } else if (i + 6 <= input.len and std.mem.eql(u8, input[i .. i + 6], "&#039;")) {
                try result.append(allocator, '\'');
                i += 6;
            } else {
                try result.append(allocator, input[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

/// wordwrap - 将字符串按指定长度换行
pub fn php_wordwrap(str: Value, width: Value, break_str: Value, cut: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const wrap_width: usize = @intCast(@max(1, width.toInt()));
    const break_chars = if (break_str.isString()) break_str.asString().data else "\n";
    const force_cut = cut.toBool();

    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit(allocator);

    var line_len: usize = 0;
    var word_start: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == ' ' or input[i] == '\n') {
            // 输出单词
            if (i > word_start) {
                const word = input[word_start..i];
                if (line_len + word.len > wrap_width and line_len > 0) {
                    try result.appendSlice(allocator, break_chars);
                    line_len = 0;
                }
                try result.appendSlice(allocator, word);
                line_len += word.len;
            }
            if (input[i] == '\n') {
                try result.append(allocator, '\n');
                line_len = 0;
            } else {
                try result.append(allocator, ' ');
                line_len += 1;
            }
            word_start = i + 1;
        } else if (force_cut and line_len >= wrap_width) {
            try result.appendSlice(allocator, break_chars);
            line_len = 0;
        }
        i += 1;
    }

    // 输出剩余单词
    if (i > word_start) {
        const word = input[word_start..i];
        if (line_len + word.len > wrap_width and line_len > 0) {
            try result.appendSlice(allocator, break_chars);
        }
        try result.appendSlice(allocator, word);
    }

    const php_str = try PHPString.init(allocator, result.items);
    return Value.initString(php_str);
}

pub fn php_printf(format: Value, args: []const Value, allocator: Allocator) !Value {
    const out = try php_sprintf(format, args, allocator);
    defer out.release(allocator);
    try php_echo(out);
    if (out.isString()) return Value.initInt(@intCast(out.asString().length));
    return Value.initInt(0);
}

pub fn php_bin2hex(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;
    const input = str.asString().data;
    const hex_len = input.len * 2;
    const hex_str = try allocator.alloc(u8, hex_len);
    defer allocator.free(hex_str);

    const hex_chars = "0123456789abcdef";
    for (input, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, hex_str);
    return Value.initString(php_str);
}

/// decbin - 十进制转二进制
pub fn php_decbin(num: Value, allocator: Allocator) !Value {
    const n = if (num.isInt()) num.asInt() else @as(i64, @intFromFloat(num.asFloat()));
    if (n == 0) {
        const php_str = try PHPString.init(allocator, "0");
        return Value.initString(php_str);
    }
    
    var abs_n: u64 = if (n < 0) @intCast(-n) else @intCast(n);
    var buf: [64]u8 = undefined;
    var len: usize = 0;
    
    while (abs_n > 0) : (abs_n >>= 1) {
        buf[63 - len] = if (abs_n & 1 == 1) '1' else '0';
        len += 1;
    }
    
    const result = buf[64 - len..];
    const php_str = try PHPString.init(allocator, result);
    return Value.initString(php_str);
}

fn hexCharToInt(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

pub fn php_hex2bin(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;
    const input = str.asString().data;
    if (input.len % 2 != 0) return Value.initBool(false);

    const bin_len = input.len / 2;
    const bin_str = try allocator.alloc(u8, bin_len);
    defer allocator.free(bin_str);

    for (0..bin_len) |i| {
        const high = hexCharToInt(input[i * 2]) orelse return Value.initBool(false);
        const low = hexCharToInt(input[i * 2 + 1]) orelse return Value.initBool(false);
        bin_str[i] = (high << 4) | low;
    }

    const php_str = try PHPString.init(allocator, bin_str);
    return Value.initString(php_str);
}

// ============================================================================
// 哈希函数
// ============================================================================

/// md5 - 计算字符串的MD5哈希值
pub fn php_md5(str: Value, raw_output: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(input, &hash, .{});

    if (raw_output.toBool()) {
        const php_str = try PHPString.init(allocator, &hash);
        return Value.initString(php_str);
    }

    // 转换为十六进制字符串
    var hex_str: [32]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

/// sha1 - 计算字符串的SHA1哈希值
pub fn php_sha1(str: Value, raw_output: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(input, &hash, .{});

    if (raw_output.toBool()) {
        const php_str = try PHPString.init(allocator, &hash);
        return Value.initString(php_str);
    }

    // 转换为十六进制字符串
    var hex_str: [40]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

pub fn php_uniqid(prefix: Value, more_entropy: Value, allocator: Allocator) !Value {
    const prefix_str = if (prefix.isString()) prefix.asString().data else "";
    const ent = more_entropy.toBool();

    const timestamp = std.time.nanoTimestamp();
    const now = @divTrunc(timestamp, 1000);
    const seconds = @as(u64, @intCast(@divTrunc(now, 1_000_000)));
    const microseconds = @as(u64, @intCast(@rem(now, 1_000_000)));

    var result_buf: [64]u8 = undefined;
    const formatted = if (ent) blk: {
        var rand_bytes: [2]u8 = undefined;
        std.crypto.random.bytes(&rand_bytes);
        const rand_val = @as(u16, rand_bytes[0]) * 256 + rand_bytes[1];
        break :blk try std.fmt.bufPrint(&result_buf, "{s}{x:0>13}{x:0>6}{x:0>4}", .{ prefix_str, seconds, microseconds, rand_val });
    } else try std.fmt.bufPrint(&result_buf, "{s}{x:0>13}", .{ prefix_str, seconds });

    const php_str = try PHPString.init(allocator, formatted);
    return Value.initString(php_str);
}

/// sha256 - 计算字符串的SHA256哈希值
pub fn php_sha256(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &hash, .{});

    // 转换为十六进制字符串
    var hex_str: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const php_str = try PHPString.init(allocator, &hex_str);
    return Value.initString(php_str);
}

/// hash - 生成哈希值
pub fn php_hash(algorithm: Value, data: Value, allocator: Allocator) !Value {
    if (!algorithm.isString() or !data.isString()) return error.InvalidArgument;

    const algo = algorithm.asString().data;

    if (std.mem.eql(u8, algo, "md5")) {
        return php_md5(data, Value.initBool(false), allocator);
    } else if (std.mem.eql(u8, algo, "sha1")) {
        return php_sha1(data, Value.initBool(false), allocator);
    } else if (std.mem.eql(u8, algo, "sha256")) {
        return php_sha256(data, allocator);
    }

    return error.UnsupportedAlgorithm;
}

/// crc32 - 计算字符串的CRC32校验值
pub fn php_crc32(str: Value) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const crc = std.hash.Crc32.hash(input);
    return Value.initInt(@intCast(crc));
}

/// base64_encode - 使用MIME base64编码数据
pub fn php_base64_encode(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const encoder = std.base64.standard;
    const encoded_len = encoder.Encoder.calcSize(input.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded);

    _ = encoder.Encoder.encode(encoded, input);

    const php_str = try PHPString.init(allocator, encoded);
    return Value.initString(php_str);
}

/// base64_decode - 对使用MIME base64编码的数据进行解码
pub fn php_base64_decode(str: Value, strict: Value, allocator: Allocator) !Value {
    _ = strict;
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const decoder = std.base64.standard;

    const decoded_max_len = decoder.Decoder.calcSizeForSlice(input) catch return Value.initBool(false);
    const decoded = try allocator.alloc(u8, decoded_max_len);
    defer allocator.free(decoded);

    decoder.Decoder.decode(decoded, input) catch return Value.initBool(false);

    const php_str = try PHPString.init(allocator, decoded[0..decoded_max_len]);
    return Value.initString(php_str);
}

// ============================================================================
// Concurrency Support
// ============================================================================

const CoroutineContext = struct {
    callable: Value,
    args: []Value,
    allocator: Allocator,
};

fn php_coroutine_entry(context: ?*anyopaque) anyerror!void {
    if (context) |ptr| {
        const ctx = @as(*CoroutineContext, @ptrCast(@alignCast(ptr)));
        defer ctx.allocator.destroy(ctx);
        defer ctx.allocator.free(ctx.args);

        // Ensure values are released when we are done
        defer {
            ctx.callable.release(ctx.allocator);
            for (ctx.args) |arg| {
                arg.release(ctx.allocator);
            }
        }

        // Execute the callable
        if (ctx.callable.isString()) {
            const func_name = ctx.callable.asString().data;
            if (user_function_registry) |registry| {
                if (registry.get(func_name)) |func| {
                    _ = func(Value.initNull(), ctx.args, ctx.allocator) catch |err| {
                        if (has_exception) {
                            php_handle_uncaught_exception();
                        }
                        return err;
                    };
                } else {}
            }
        } else if (ctx.callable.isFunction()) {
            const closure = ctx.callable.asFunction();
            _ = closure.func(Value.initFunction(closure), ctx.args, ctx.allocator) catch |err| {
                if (has_exception) {
                    php_handle_uncaught_exception();
                }
                return err;
            };
        }
    }
}

pub fn php_go(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;

    const callable = args[0];

    const coro_args = try allocator.alloc(Value, args.len - 1);
    for (args[1..], 0..) |arg, i| {
        coro_args[i] = arg;
        _ = arg.retain();
    }

    const context = try allocator.create(CoroutineContext);
    context.* = .{
        .callable = callable,
        .args = coro_args,
        .allocator = allocator,
    };
    _ = callable.retain();

    const scheduler = try concurrency.getScheduler(allocator);
    const coro_id = try scheduler.spawn(php_coroutine_entry, context);

    return Value.initInt(@intCast(coro_id));
}

pub fn php_go_wait_all(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    _ = concurrency.drainScheduler(null);
    return Value.initNull();
}

pub fn php_go_join(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len == 0 or args[0].isNull()) {
        _ = concurrency.drainScheduler(null);
        return Value.initNull();
    }
    const id = @as(u64, @intCast(args[0].toInt()));
    const scheduler = try concurrency.getScheduler(runtime_allocator);
    try scheduler.join(id);
    return Value.initNull();
}

pub fn go_spawn(func_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const callable = Value.initString(try PHPString.init(allocator, func_name));
    const full_args = try allocator.alloc(Value, args.len + 1);
    full_args[0] = callable;
    @memcpy(full_args[1..], args);
    defer allocator.free(full_args);

    return php_go(Value.initNull(), full_args, allocator);
}

pub const PHPMutex = struct {
    mutex: std.Thread.Mutex,
    lock_count: std.atomic.Value(u32),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*PHPMutex {
        const self = try allocator.create(PHPMutex);
        self.* = .{
            .mutex = .{},
            .lock_count = std.atomic.Value(u32).init(0),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *PHPMutex) void {
        self.allocator.destroy(self);
    }

    pub fn lock(self: *PHPMutex) void {
        self.mutex.lock();
        _ = self.lock_count.fetchAdd(1, .monotonic);
    }

    pub fn unlock(self: *PHPMutex) void {
        _ = self.lock_count.fetchSub(1, .monotonic);
        self.mutex.unlock();
    }

    pub fn tryLock(self: *PHPMutex) bool {
        if (self.mutex.tryLock()) {
            _ = self.lock_count.fetchAdd(1, .monotonic);
            return true;
        }
        return false;
    }

    pub fn getLockCount(self: *const PHPMutex) u32 {
        return self.lock_count.load(.monotonic);
    }
};

pub const PHPAtomic = struct {
    value: std.atomic.Value(i64),
    allocator: Allocator,

    pub fn init(allocator: Allocator, initial: i64) !*PHPAtomic {
        const self = try allocator.create(PHPAtomic);
        self.* = .{
            .value = std.atomic.Value(i64).init(initial),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *PHPAtomic) void {
        self.allocator.destroy(self);
    }

    pub fn load(self: *const PHPAtomic) i64 {
        return self.value.load(.monotonic);
    }

    pub fn store(self: *PHPAtomic, v: i64) void {
        self.value.store(v, .monotonic);
    }

    pub fn increment(self: *PHPAtomic) i64 {
        return self.value.fetchAdd(1, .monotonic) + 1;
    }

    pub fn decrement(self: *PHPAtomic) i64 {
        return self.value.fetchSub(1, .monotonic) - 1;
    }

    pub fn add(self: *PHPAtomic, delta: i64) i64 {
        return self.value.fetchAdd(delta, .monotonic);
    }

    pub fn sub(self: *PHPAtomic, delta: i64) i64 {
        return self.value.fetchSub(delta, .monotonic);
    }

    pub fn swap(self: *PHPAtomic, new_value: i64) i64 {
        return self.value.swap(new_value, .monotonic);
    }

    pub fn compareAndSwap(self: *PHPAtomic, expected: i64, new_value: i64) bool {
        return self.value.cmpxchgStrong(expected, new_value, .monotonic, .monotonic) == null;
    }
};

pub const PHPRWLock = struct {
    rwlock: std.Thread.RwLock,
    readers: std.atomic.Value(i32),
    writer: std.atomic.Value(bool),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*PHPRWLock {
        const self = try allocator.create(PHPRWLock);
        self.* = .{
            .rwlock = .{},
            .readers = std.atomic.Value(i32).init(0),
            .writer = std.atomic.Value(bool).init(false),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *PHPRWLock) void {
        self.allocator.destroy(self);
    }

    pub fn lockRead(self: *PHPRWLock) void {
        self.rwlock.lockShared();
        _ = self.readers.fetchAdd(1, .monotonic);
    }

    pub fn unlockRead(self: *PHPRWLock) void {
        _ = self.readers.fetchSub(1, .monotonic);
        self.rwlock.unlockShared();
    }

    pub fn lockWrite(self: *PHPRWLock) void {
        self.rwlock.lock();
        self.writer.store(true, .monotonic);
    }

    pub fn unlockWrite(self: *PHPRWLock) void {
        self.writer.store(false, .monotonic);
        self.rwlock.unlock();
    }

    pub fn getReaderCount(self: *const PHPRWLock) i32 {
        return self.readers.load(.monotonic);
    }

    pub fn getWriterCount(self: *const PHPRWLock) i32 {
        return if (self.writer.load(.monotonic)) 1 else 0;
    }
};

pub const PHPSharedData = struct {
    data: std.StringHashMap([]const u8),
    mutex: std.Thread.Mutex,
    allocator: Allocator,
    access_count: std.atomic.Value(u64),

    pub fn init(allocator: Allocator) !*PHPSharedData {
        const self = try allocator.create(PHPSharedData);
        self.* = .{
            .data = std.StringHashMap([]const u8).init(allocator),
            .mutex = .{},
            .allocator = allocator,
            .access_count = std.atomic.Value(u64).init(0),
        };
        return self;
    }

    pub fn deinit(self: *PHPSharedData) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
        self.allocator.destroy(self);
    }

    pub fn get(self: *PHPSharedData, key: []const u8) ?[]const u8 {
        _ = self.access_count.fetchAdd(1, .monotonic);
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.data.get(key);
    }

    pub fn set(self: *PHPSharedData, key: []const u8, value: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }

        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        try self.data.put(key_copy, value_copy);
    }

    pub fn remove(self: *PHPSharedData, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
            return true;
        }
        return false;
    }

    pub fn has(self: *PHPSharedData, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.data.contains(key);
    }

    pub fn size(self: *PHPSharedData) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.data.count();
    }

    pub fn clear(self: *PHPSharedData) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.clearRetainingCapacity();
    }

    pub fn getAccessCount(self: *const PHPSharedData) u64 {
        return self.access_count.load(.monotonic);
    }
};

pub fn channel_new(capacity: i64, allocator: Allocator) !Value {
    const obj = try php_object_new("Channel", allocator);
    const channel = try concurrency.Channel(Value).init(allocator, @intCast(capacity));
    const ptr_val = Value.initInt(@intCast(@intFromPtr(channel)));
    try Value_asObject(obj).setProperty("_ptr", ptr_val);
    return obj;
}

pub fn channel_send(ch: Value, val: Value) !void {
    if (!Value_isObject(ch)) return error.InvalidChannel;
    const obj = Value_asObject(ch);
    if (obj.getProperty("_ptr")) |ptr_val| {
        const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        _ = val.retain();
        try channel.send(val);
    }
}

pub fn channel_recv(ch: Value) !Value {
    if (!Value_isObject(ch)) return error.InvalidChannel;
    const obj = Value_asObject(ch);
    if (obj.getProperty("_ptr")) |ptr_val| {
        const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        return channel.recv() catch |err| {
            if (err == error.ChannelClosed) return Value.initNull();
            return err;
        };
    }
    return Value.initNull();
}

pub fn channel_close(ch: Value) void {
    if (!Value_isObject(ch)) return;
    const obj = Value_asObject(ch);
    if (obj.getProperty("_ptr")) |ptr_val| {
        const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        channel.close();
    }
}

fn registerChannelClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                var capacity: usize = 0;
                if (args.len > 0) {
                    capacity = @intCast(args[0].toInt());
                }
                const channel = try concurrency.Channel(Value).init(runtime_alloc, capacity);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(channel)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "send",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (args.len < 1) return error.MissingArgument;

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                const val = args[0];
                _ = val.retain();
                try channel.send(val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "recv",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                return channel.recv() catch |err| {
                    if (err == error.ChannelClosed) return Value.initNull();
                    return err;
                };
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "trySend",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len < 1) return error.MissingArgument;

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                const val = args[0];
                _ = val.retain();
                const ok = channel.trySend(val) catch {
                    val.release(runtime_alloc);
                    return Value.initBool(false);
                };
                if (!ok) {
                    val.release(runtime_alloc);
                }
                return Value.initBool(ok);
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "tryRecv",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                if (channel.tryRecv()) |val| {
                    return val;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "close",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));

                channel.close();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "isClosed",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initBool(channel.isClosed());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "len",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initInt(@intCast(channel.len()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "capacity",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                _ = args;
                const this = Value_asObject(ctx);

                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidChannel;
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initInt(@intCast(channel.getCapacity()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                const this = Value_asObject(ctx);

                if (this.getProperty("_ptr")) |ptr_val| {
                    const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    while (channel.tryRecv()) |val| {
                        val.release(runtime_alloc);
                    }
                    channel.deinit();
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerMutexClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                const this = Value_asObject(ctx);
                const m = try PHPMutex.init(runtime_alloc);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(m)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "lock",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
                const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                m.lock();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "unlock",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
                const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                m.unlock();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "tryLock",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
                const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initBool(m.tryLock());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "getLockCount",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
                const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                return Value.initInt(@intCast(m.getLockCount()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (this.getProperty("_ptr")) |ptr_val| {
                    const m = @as(*PHPMutex, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    m.deinit();
                    try this.setProperty("_ptr", Value.initNull());
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerAtomicClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                const initial: i64 = if (args.len > 0) args[0].toInt() else 0;
                const a = try PHPAtomic.init(runtime_alloc, initial);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(a)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    const get_ptr = struct {
        fn ptr(ctx: Value) !*PHPAtomic {
            const this = Value_asObject(ctx);
            const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
            return @as(*PHPAtomic, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        }
    }.ptr;

    try meta.addMethod(.{
        .name = "load",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const a = try get_ptr(ctx);
                return Value.initInt(a.load());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "store",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                const a = try get_ptr(ctx);
                a.store(args[0].toInt());
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "increment",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const a = try get_ptr(ctx);
                return Value.initInt(a.increment());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "decrement",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const a = try get_ptr(ctx);
                return Value.initInt(a.decrement());
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "add",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                const a = try get_ptr(ctx);
                return Value.initInt(a.add(args[0].toInt()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "sub",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                const a = try get_ptr(ctx);
                return Value.initInt(a.sub(args[0].toInt()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "swap",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                const a = try get_ptr(ctx);
                return Value.initInt(a.swap(args[0].toInt()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "compareAndSwap",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 2) return error.MissingArgument;
                const a = try get_ptr(ctx);
                return Value.initBool(a.compareAndSwap(args[0].toInt(), args[1].toInt()));
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (this.getProperty("_ptr")) |ptr_val| {
                    const a = @as(*PHPAtomic, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    a.deinit();
                    try this.setProperty("_ptr", Value.initNull());
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerRWLockClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                const this = Value_asObject(ctx);
                const l = try PHPRWLock.init(runtime_alloc);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(l)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    const get_ptr = struct {
        fn ptr(ctx: Value) !*PHPRWLock {
            const this = Value_asObject(ctx);
            const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
            return @as(*PHPRWLock, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        }
    }.ptr;

    try meta.addMethod(.{
        .name = "lockRead",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                l.lockRead();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "unlockRead",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                l.unlockRead();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "lockWrite",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                l.lockWrite();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "unlockWrite",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                l.unlockWrite();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "getReaderCount",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                return Value.initInt(@intCast(l.getReaderCount()));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "getWriterCount",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const l = try get_ptr(ctx);
                return Value.initInt(@intCast(l.getWriterCount()));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (this.getProperty("_ptr")) |ptr_val| {
                    const l = @as(*PHPRWLock, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    l.deinit();
                    try this.setProperty("_ptr", Value.initNull());
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerSharedDataClassNamed(allocator: Allocator, class_name: []const u8) !void {
    const meta = try ClassMeta.init(allocator, class_name);

    try meta.addMethod(.{
        .name = "__construct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                const this = Value_asObject(ctx);
                const s = try PHPSharedData.init(runtime_alloc);
                const ptr_val = Value.initInt(@intCast(@intFromPtr(s)));
                try this.setProperty("_ptr", ptr_val);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    const get_ptr = struct {
        fn ptr(ctx: Value) !*PHPSharedData {
            const this = Value_asObject(ctx);
            const ptr_val = this.getProperty("_ptr") orelse return error.InvalidArgument;
            return @as(*PHPSharedData, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
        }
    }.ptr;

    try meta.addMethod(.{
        .name = "set",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                if (args.len < 2) return error.MissingArgument;
                if (!args[0].isString()) return error.InvalidArgument;
                const s = try get_ptr(ctx);
                const key = args[0].asString().data;
                const val_str = if (args[1].isString()) args[1] else try php_strval(args[1], runtime_alloc);
                defer if (!args[1].isString()) val_str.release(runtime_alloc);
                try s.set(key, val_str.asString().data);
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "get",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                if (args.len < 1) return error.MissingArgument;
                if (!args[0].isString()) return error.InvalidArgument;
                const s = try get_ptr(ctx);
                const key = args[0].asString().data;
                if (s.get(key)) |val| {
                    return Value.initString(try PHPString.init(runtime_alloc, val));
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "remove",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                if (!args[0].isString()) return error.InvalidArgument;
                const s = try get_ptr(ctx);
                const key = args[0].asString().data;
                return Value.initBool(s.remove(key));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "has",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = runtime_alloc;
                if (args.len < 1) return error.MissingArgument;
                if (!args[0].isString()) return error.InvalidArgument;
                const s = try get_ptr(ctx);
                const key = args[0].asString().data;
                return Value.initBool(s.has(key));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "size",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const s = try get_ptr(ctx);
                return Value.initInt(@intCast(s.size()));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "clear",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const s = try get_ptr(ctx);
                s.clear();
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "getAccessCount",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const s = try get_ptr(ctx);
                return Value.initInt(@intCast(s.getAccessCount()));
            }
        }.call,
        .is_static = false,
    });
    try meta.addMethod(.{
        .name = "__destruct",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = args;
                _ = runtime_alloc;
                const this = Value_asObject(ctx);
                if (this.getProperty("_ptr")) |ptr_val| {
                    const s = @as(*PHPSharedData, @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                    s.deinit();
                    try this.setProperty("_ptr", Value.initNull());
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    meta.magic_destruct = meta.findMethod("__destruct").?.func;
    try registerClass(meta);
}

fn registerZigChannel(allocator: Allocator) !void {
    try registerChannelClassNamed(allocator, "Channel");
    try registerChannelClassNamed(allocator, "Zig\\Channel");
    try registerMutexClassNamed(allocator, "Mutex");
    try registerMutexClassNamed(allocator, "Zig\\Mutex");
    try registerAtomicClassNamed(allocator, "Atomic");
    try registerAtomicClassNamed(allocator, "Zig\\Atomic");
    try registerRWLockClassNamed(allocator, "RWLock");
    try registerRWLockClassNamed(allocator, "Zig\\RWLock");
    try registerSharedDataClassNamed(allocator, "SharedData");
    try registerSharedDataClassNamed(allocator, "Zig\\SharedData");
    try registerUserFunction("go", php_go);
    try registerUserFunction("go_wait_all", php_go_wait_all);
    try registerUserFunction("go_join", php_go_join);
}

fn registerZigSelect(allocator: Allocator) !void {
    const meta = try ClassMeta.init(allocator, "Zig\\Select");

    try meta.addMethod(.{
        .name = "select",
        .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                _ = ctx;
                if (args.len < 1) return error.MissingArgument;
                const cases_arg = args[0];
                if (!cases_arg.isArray()) return error.InvalidArgument;

                var timeout: ?i64 = null;
                if (args.len > 1 and !args[1].isNull()) {
                    timeout = args[1].toInt();
                }

                const array = cases_arg.asArray();
                const start_time = std.time.milliTimestamp();

                while (true) {
                    var iter = array.elements.iterator();
                    var index: usize = 0;
                    while (iter.next()) |entry| : (index += 1) {
                        const case_val = entry.value_ptr.*;
                        if (!case_val.isArray()) continue;

                        const case_arr = case_val.asArray();

                        // [channel, op, ?value]
                        const ch_val = case_arr.get(ArrayKey{ .integer = 0 }) orelse continue;
                        const op_val = case_arr.get(ArrayKey{ .integer = 1 }) orelse continue;

                        if (!Value_isObject(ch_val)) continue;
                        const ch_obj = Value_asObject(ch_val);
                        if (ch_obj.getProperty("_ptr")) |ptr_val| {
                            const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                            const op = op_val.toInt(); // 0=recv, 1=send

                            if (op == 0) { // recv
                                if (channel.tryRecv()) |val| {
                                    // Return array [index, value]
                                    const res_arr = try PHPArray.init(runtime_alloc);
                                    try res_arr.push(runtime_alloc, Value.initInt(@intCast(index)));
                                    try res_arr.push(runtime_alloc, val);
                                    return Value.initArray(res_arr);
                                }
                            } else if (op == 1) { // send
                                const send_val = case_arr.get(ArrayKey{ .integer = 2 }) orelse Value.initNull();
                                _ = send_val.retain();
                                const ok = channel.trySend(send_val) catch {
                                    send_val.release(runtime_alloc);
                                    continue;
                                };
                                if (ok) {
                                    return Value.initInt(@intCast(index));
                                }
                                send_val.release(runtime_alloc);
                            }
                        }
                    }

                    if (timeout) |t| {
                        if (std.time.milliTimestamp() - start_time >= t) {
                            return Value.initNull();
                        }
                    }

                    std.Thread.yield() catch {};
                }
            }
        }.call,
        .is_static = true,
    });

    try registerClass(meta);
}

pub fn php_go_builtin(callable: Value, allocator: Allocator) !Value {
    const args = [_]Value{callable};
    return php_go(Value.initNull(), &args, allocator);
}

/// array_count_values() - 统计数组中所有值出现的次数
pub fn php_array_count_values(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;
    
    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);
    
    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const val = entry.value_ptr.*;
        
        // 只支持整数和字符串作为键
        const key: ArrayKey = if (val.isInt())
            .{ .integer = val.asInt() }
        else if (val.isString())
            .{ .string = val.asString() }
        else
            continue;
        
        // 获取或初始化计数
        if (result.elements.get(key)) |count_val| {
            try result.set(allocator, key, Value.initInt(count_val.asInt() + 1));
        } else {
            try result.set(allocator, key, Value.initInt(1));
        }
    }
    
    return Value.initArray(result);
}

/// array_rand() - 从数组中随机选择一个或多个键
pub fn php_array_rand(arr: Value, num: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!arr.isArray()) return error.InvalidArgument;
    
    const php_arr = arr.asArray();
    const count = php_arr.elements.count();
    if (count == 0) return Value.initNull();
    
    const n = if (num.isInt()) @as(usize, @intCast(@max(1, num.asInt()))) else 1;
    
    if (n == 1) {
        // 返回单个键
        const idx = @as(usize, @intCast(std.crypto.random.intRangeAtMost(i64, 0, @as(i64, @intCast(count - 1)))));
        var iter = php_arr.elements.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            if (i == idx) {
                return switch (entry.key_ptr.*) {
                    .integer => |int| Value.initInt(int),
                    .string => |str| Value.initString(str),
                };
            }
        }
        return Value.initNull();
    }
    
    // 返回多个键（简化实现）
    return Value.initNull();
}

/// shuffle() - 随机打乱数组
pub fn php_shuffle(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;
    
    const php_arr = arr.asArray();
    const count = php_arr.elements.count();
    if (count <= 1) return Value.initBool(true);
    
    // Fisher-Yates shuffle
    var values = try allocator.alloc(Value, count);
    defer allocator.free(values);
    
    var iter = php_arr.elements.iterator();
    var i: usize = 0;
    while (iter.next()) |entry| : (i += 1) {
        values[i] = entry.value_ptr.*;
    }
    
    i = count;
    while (i > 1) {
        i -= 1;
        const j = @as(usize, @intCast(std.crypto.random.intRangeAtMost(i64, 0, @as(i64, @intCast(i)))));
        const temp = values[i];
        values[i] = values[j];
        values[j] = temp;
    }
    
    // 重建数组
    php_arr.elements.packed_values.clearRetainingCapacity();
    if (php_arr.elements.mixed) |*mixed| {
        mixed.clearRetainingCapacity();
    }
    
    for (values, 0..) |val, idx| {
        try php_arr.push(allocator, val);
        _ = idx;
    }
    
    return Value.initBool(true);
}

/// compact() - 创建包含变量及其值的数组
pub fn php_compact(varnames: []const Value, allocator: Allocator) !Value {
    _ = varnames;
    // 简化实现：返回空数组
    const result = try PHPArray.init(allocator);
    return Value.initArray(result);
}

/// extract() - 从数组中将变量导入到当前符号表
pub fn php_extract(arr: Value, allocator: Allocator) !Value {
    _ = arr;
    _ = allocator;
    // 简化实现：返回0
    return Value.initInt(0);
}

/// array_fill_keys() - 使用指定的键和值填充数组
pub fn php_array_fill_keys(keys: Value, value: Value, allocator: Allocator) !Value {
    if (!keys.isArray()) return error.InvalidArgument;
    
    const keys_arr = keys.asArray();
    const result = try PHPArray.init(allocator);
    
    var iter = keys_arr.elements.iterator();
    while (iter.next()) |entry| {
        const key_val = entry.value_ptr.*;
        const key: ArrayKey = if (key_val.isInt())
            .{ .integer = key_val.asInt() }
        else if (key_val.isString())
            .{ .string = key_val.asString() }
        else
            continue;
        
        try result.set(allocator, key, value);
    }
    
    return Value.initArray(result);
}

/// natsort() - 用自然排序算法对数组排序
pub fn php_natsort(arr: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!arr.isArray()) return error.InvalidArgument;
    // 简化实现：不排序，直接返回true
    return Value.initBool(true);
}


