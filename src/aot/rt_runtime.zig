const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

// ============================================================================
// 全局运行时状态
// ============================================================================

/// 全局分配器（由main函数初始化）
/// 注意：这是一个全局变量，在AOT编译的代码中可以直接访问
pub var runtime_allocator: Allocator = undefined;

/// 空字符串常量（用于错误恢复）
var EMPTY_STRING: PHPString = .{
    .data = &[_]u8{},
    .length = 0,
    .ref_count = 999999,
    .is_static = true,
};

/// 用户定义函数注册表
pub var user_function_registry: ?std.StringHashMap(*const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value) = null;
/// AOT hook：用于变量函数调用时查找AOT注册的函数
pub var aot_callable_hook: ?*const fn (name: []const u8, args: []const Value, allocator: Allocator) anyerror!Value = null;
const FunctionDeclLocation = struct {
    file: []const u8,
    line: u32,
};
pub var user_function_decl_locations: ?std.StringHashMap(FunctionDeclLocation) = null;

/// 函数元数据（参数计数等，用于反射 API）
pub const FunctionMeta = struct {
    param_count: u16 = 0,
    required_params: u16 = 0,
    param_names: []const []const u8 = &.{},
};
pub var function_meta_registry: ?std.StringHashMap(FunctionMeta) = null;

pub fn registerFunctionMeta(name: []const u8, param_count: u16, required_params: u16) void {
    if (function_meta_registry) |*registry| {
        registry.put(name, .{ .param_count = param_count, .required_params = required_params }) catch {};
    }
}

/// 全局常量表
pub var constants: std.StringHashMap(Value) = undefined;

/// 静态变量表（函数名::变量名 -> 值）
var static_vars: ?std.StringHashMap(Value) = null;
var static_vars_mutex: std.atomic.Mutex = .unlocked;

/// 自旋锁辅助函数（std.atomic.Mutex 没有 lock()，只有 tryLock()）
inline fn spinLock(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) std.atomic.spinLoopHint();
}

/// Zig 0.17 兼容：替代 nanoTimestamp()（已移除）
/// 使用 clock_gettime(CLOCK_REALTIME) 获取纳秒时间戳（syscall，无需 libc）
pub inline fn nanoTimestamp() i128 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return @as(i128, @intCast(ts.sec)) * std.time.ns_per_s + @as(i128, @intCast(ts.nsec));
}

/// Zig 0.17 兼容：替代 unixTimestamp()（已移除）
/// 返回 Unix 时间戳（秒）（syscall，无需 libc）
pub inline fn unixTimestamp() i64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.REALTIME, &ts);
    return @intCast(ts.sec);
}

/// Zig 0.17 兼容：替代 milliTimestamp()（已移除）
/// 返回自 Unix 纪元以来的毫秒时间戳（syscall，无需 libc）
pub inline fn milliTimestamp() i64 {
    return @intCast(@divFloor(nanoTimestamp(), 1_000_000));
}

/// Zig 0.17 兼容：替代 File.writeAll()（已移除）
/// 使用 POSIX write() 系统调用直接写入文件描述符（忽略错误，无需 libc）
pub inline fn fileWriteAll(fd: std.posix.fd_t, data: []const u8) void {
    _ = std.posix.system.write(fd, data.ptr, data.len);
}

/// Zig 0.17 兼容：获取 Io 实例（用于 Condition.wait/signal 等 API）
inline fn getIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// Zig 0.17 兼容：替代 File.writeAll()（可传播错误的版本，无需 libc）
const WriteError = error{WriteFailed};
inline fn tryFileWriteAll(fd: std.posix.fd_t, data: []const u8) WriteError!void {
    const result = std.posix.system.write(fd, data.ptr, data.len);
    if (result < 0) return error.WriteFailed;
}

/// Zig 0.17 兼容：替代 std.process.getEnvVarOwned()（已移除）
/// 简化实现：AOT 模式下直接返回 null（不支持运行时环境变量查询）
pub inline fn getEnvVar(name: [*:0]const u8) ?[]const u8 {
    const c_val = std.c.getenv(name);
    if (c_val == null) return null;
    return std.mem.sliceTo(c_val.?, 0);
}

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
var static_string_entries: std.ArrayListUnmanaged(*StaticStringEntry) = .{ .items = &.{}, .capacity = 0 };
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
var cycle_roots: std.ArrayListUnmanaged(CycleRoot) = .{ .items = &.{}, .capacity = 0 };
var gc_in_progress: bool = false;
var gc_enabled: bool = true;
var gc_release_events: usize = 0;
const GC_RELEASE_EVENT_THRESHOLD: usize = 4096;
const GC_ROOT_THRESHOLD: usize = 256;

/// 当前异常（线程局部）
threadlocal var current_exception: Value = undefined;
threadlocal var has_exception: bool = false;
threadlocal var current_call_args: ?[]const Value = null;

/// 源码位置跟踪（用于 Deprecated 警告输出）
threadlocal var src_file: []const u8 = "";
threadlocal var src_line: u32 = 0;

pub fn setSourceLocation(file: []const u8, line: u32) void {
    src_file = file;
    src_line = line;
}

pub fn setCurrentCallArgs(args: []const Value) ?[]const Value {
    const prev = current_call_args;
    current_call_args = args;
    return prev;
}

pub fn restoreCurrentCallArgs(prev: ?[]const Value) void {
    current_call_args = prev;
}

fn allocPHPString(allocator: Allocator) !*PHPString {
    if (php_string_pool) |*p| return p.create(allocator);
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
    if (php_array_pool) |*p| return p.create(allocator);
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
    if (php_closure_pool) |*p| return p.create(allocator);
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
pub fn initRuntime(allocator: Allocator) !void {
    alloc_counters = .{};
    alloc_baseline = .{};
    stats_allocator = StatsAllocator.init(allocator);
    runtime_allocator = stats_allocator.allocator();

    // 先初始化全局表，再注册类（类注册可能需要写入 constants）
    initClassRegistry(runtime_allocator);
    user_function_registry = std.StringHashMap(*const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value).init(runtime_allocator);
    user_function_decl_locations = std.StringHashMap(FunctionDeclLocation).init(runtime_allocator);
    function_meta_registry = std.StringHashMap(FunctionMeta).init(runtime_allocator);
    constants = std.StringHashMap(Value).init(runtime_allocator);
    static_vars = std.StringHashMap(Value).init(runtime_allocator);
    array_internal_pointers = std.AutoHashMap(*PHPArray, usize).init(runtime_allocator);
    static_string_pool = std.StringHashMap(*StaticStringEntry).init(runtime_allocator);
    static_string_entries = .{ .items = &.{}, .capacity = 0 };
    cycle_roots = .{ .items = &.{}, .capacity = 0 };
    gc_in_progress = false;
    gc_enabled = true;

    // 注册内置类
    ClassMeta.registerStdClass(runtime_allocator) catch {};
    registerArrayIterator(runtime_allocator) catch {};
    registerArrayObject(runtime_allocator) catch {};
    registerSplFixedArray(runtime_allocator) catch {};
    registerSplStack(runtime_allocator) catch {};
    registerSplQueue(runtime_allocator) catch {};
    ClassMeta.registerDateTimeClasses(runtime_allocator) catch {};
    registerZigChannel(runtime_allocator) catch {};
    registerZigSelect(runtime_allocator) catch {};
    gc_release_events = 0;
    current_exception = Value.initNull();
    has_exception = false;
    php_string_pool = try std.heap.MemoryPool(PHPString).initCapacity(runtime_allocator, 64);
    php_array_pool = try std.heap.MemoryPool(PHPArray).initCapacity(runtime_allocator, 64);
    php_closure_pool = try std.heap.MemoryPool(PHPClosure).initCapacity(runtime_allocator, 16);
    resetAllocStats();
    initPredefinedConstants() catch {};
}

fn initPredefinedConstants() !void {
    // PHP核心常量 - 使用真正的64位整数范围
    const php_keys = [_][]const u8{ "PHP_INT_MAX", "PHP_INT_MIN", "PHP_INT_SIZE" };
    const php_vals = [_]i64{ std.math.maxInt(i64), std.math.minInt(i64), 8 };
    for (php_keys, php_vals) |key, val| {
        const key_copy = try runtime_allocator.dupe(u8, key);
        try constants.put(key_copy, Value.initInt(val));
    }

    // PHP版本和浮点常量
    {
        const ver_key = try runtime_allocator.dupe(u8, "PHP_VERSION");
        const ver_str = try PHPString.init(runtime_allocator, "8.4.8");
        try constants.put(ver_key, Value.initString(ver_str));
        const ver_id_key = try runtime_allocator.dupe(u8, "PHP_VERSION_ID");
        try constants.put(ver_id_key, Value.initInt(80408));
        const release_key = try runtime_allocator.dupe(u8, "PHP_RELEASE_VERSION");
        try constants.put(release_key, Value.initInt(8));

        const major_key = try runtime_allocator.dupe(u8, "PHP_MAJOR_VERSION");
        try constants.put(major_key, Value.initInt(8));
        const minor_key = try runtime_allocator.dupe(u8, "PHP_MINOR_VERSION");
        try constants.put(minor_key, Value.initInt(4));

        const fmax_key = try runtime_allocator.dupe(u8, "PHP_FLOAT_MAX");
        try constants.put(fmax_key, Value.initFloat(std.math.floatMax(f64)));
        const fmin_key = try runtime_allocator.dupe(u8, "PHP_FLOAT_MIN");
        try constants.put(fmin_key, Value.initFloat(std.math.floatMin(f64)));
        const feps_key = try runtime_allocator.dupe(u8, "PHP_FLOAT_EPSILON");
        try constants.put(feps_key, Value.initFloat(std.math.floatEps(f64)));
        const fdig_key = try runtime_allocator.dupe(u8, "PHP_FLOAT_DIG");
        try constants.put(fdig_key, Value.initInt(15));

        // INF和NAN常量
        const inf_key = try runtime_allocator.dupe(u8, "INF");
        try constants.put(inf_key, Value.initFloat(std.math.inf(f64)));
        const nan_key = try runtime_allocator.dupe(u8, "NAN");
        try constants.put(nan_key, Value.initFloat(std.math.nan(f64)));

        const eol_key = try runtime_allocator.dupe(u8, "PHP_EOL");
        const eol_str = try PHPString.init(runtime_allocator, "\n");
        try constants.put(eol_key, Value.initString(eol_str));

        const stdin_key = try runtime_allocator.dupe(u8, "STDIN");
        try constants.put(stdin_key, Value.initInt(1));
        const stdout_key = try runtime_allocator.dupe(u8, "STDOUT");
        try constants.put(stdout_key, Value.initInt(2));
        const stderr_key = try runtime_allocator.dupe(u8, "STDERR");
        try constants.put(stderr_key, Value.initInt(3));

        const maxpath_key = try runtime_allocator.dupe(u8, "PHP_MAXPATHLEN");
        try constants.put(maxpath_key, Value.initInt(4096));
    }

    // 排序常量
    const sort_keys = [_][]const u8{ "SORT_ASC", "SORT_DESC", "SORT_REGULAR", "SORT_NUMERIC", "SORT_STRING", "SORT_NATURAL", "SORT_FLAG_CASE" };
    const sort_vals = [_]i64{ 1, 2, 0, 1, 2, 6, 8 };
    for (sort_keys, sort_vals) |key, val| {
        const key_copy = try runtime_allocator.dupe(u8, key);
        try constants.put(key_copy, Value.initInt(val));
    }

    // 数组常量
    const array_keys = [_][]const u8{ "CASE_LOWER", "CASE_UPPER", "COUNT_NORMAL", "COUNT_RECURSIVE", "EXTR_OVERWRITE", "EXTR_SKIP", "EXTR_PREFIX_SAME", "EXTR_PREFIX_ALL" };
    const array_vals = [_]i64{ 0, 1, 0, 1, 0, 1, 3, 4 };
    for (array_keys, array_vals) |key, val| {
        const key_copy = try runtime_allocator.dupe(u8, key);
        try constants.put(key_copy, Value.initInt(val));
    }

    const keys = [_][]const u8{ "STR_PAD_LEFT", "STR_PAD_RIGHT", "STR_PAD_BOTH" };
    const values = [_]i64{ 0, 1, 2 };
    for (keys, values) |key, val| {
        const key_copy = try runtime_allocator.dupe(u8, key);
        try constants.put(key_copy, Value.initInt(val));
    }
    // POSIX 信号常量
    const sig_keys = [_][]const u8{
        "SIGHUP",  "SIGINT",  "SIGQUIT",
        "SIGILL",  "SIGTRAP", "SIGABRT",
        "SIGFPE",  "SIGKILL", "SIGBUS",
        "SIGSEGV", "SIGSYS",  "SIGPIPE",
        "SIGALRM", "SIGTERM", "SIGURG",
        "SIGSTOP", "SIGTSTP", "SIGCONT",
        "SIGCHLD", "SIGTTIN", "SIGTTOU",
        "SIGXCPU", "SIGXFSZ", "SIGVTALRM",
        "SIGPROF", "SIGUSR1", "SIGUSR2",
    };
    const sig_vals = [_]i64{
        1,  2,  3,  4,  5,  6,  8,  9,  10,
        11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 24, 25, 26, 27, 30, 31,
    };
    for (sig_keys, sig_vals) |sk, sv| {
        const k = try runtime_allocator.dupe(u8, sk);
        try constants.put(k, Value.initInt(sv));
    }
    // pcntl_sigprocmask 常量
    const mask_keys = [_][]const u8{
        "SIG_BLOCK", "SIG_UNBLOCK", "SIG_SETMASK",
    };
    const mask_vals = [_]i64{ 1, 2, 3 };
    for (mask_keys, mask_vals) |mk, mv| {
        const k = try runtime_allocator.dupe(u8, mk);
        try constants.put(k, Value.initInt(mv));
    }
    // Socket 常量
    const sock_keys = [_][]const u8{
        "AF_UNIX",    "AF_INET", "SOCK_STREAM",
        "SOCK_DGRAM",
    };
    const sock_vals = [_]i64{ 1, 2, 1, 2 };
    for (sock_keys, sock_vals) |sk2, sv2| {
        const k = try runtime_allocator.dupe(u8, sk2);
        try constants.put(k, Value.initInt(sv2));
    }

    // Filter 常量
    const filter_keys = [_][]const u8{
        "FILTER_VALIDATE_EMAIL",
        "FILTER_VALIDATE_URL",
        "FILTER_VALIDATE_IP",
        "FILTER_VALIDATE_INT",
        "FILTER_VALIDATE_BOOLEAN",
        "FILTER_VALIDATE_FLOAT",
    };
    const filter_vals = [_]i64{ 274, 273, 275, 257, 258, 259 };
    for (filter_keys, filter_vals) |fk, fv| {
        const k = try runtime_allocator.dupe(u8, fk);
        try constants.put(k, Value.initInt(fv));
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
    if (Value_isObject(ex)) {
        const obj = Value_asObject(ex);
        var has_file = false;
        if (obj.getProperty("file")) |val| {
            has_file = !val.isNull();
        }
        if (!has_file) {
            const file_str = PHPString.init(runtime_allocator, src_file) catch null;
            if (file_str) |s| {
                obj.setProperty("file", Value.initString(s)) catch {};
            }
        }

        var has_line = false;
        if (obj.getProperty("line")) |val| {
            has_line = !val.isNull();
        }
        if (!has_line) {
            obj.setProperty("line", Value.initInt(@intCast(src_line))) catch {};
        }
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

/// 查看当前异常但不消费（用于 catch 类型分派）
pub fn peekException() Value {
    if (has_exception) {
        _ = current_exception.retain();
        return current_exception;
    }
    return Value.initNull();
}

pub fn php_handle_uncaught_exception() void {
    if (has_exception) {
        var ex = getException();
        defer ex.release(runtime_allocator);

        var class_name: []const u8 = "Exception";
        var message: []const u8 = "";

        if (Value_isObject(ex)) {
            const obj = Value_asObject(ex);
            class_name = obj.class_name;
            if (obj.getProperty("message")) |msg_val| {
                if (msg_val.isString()) {
                    message = msg_val.asString().data;
                }
            }
        } else if (ex.isString()) {
            message = ex.asString().data;
        }

        // PHP 输出顺序：先 stderr，再 stdout
        var ebuf: [1024]u8 = undefined;
        const emsg = std.fmt.bufPrint(
            &ebuf,
            "PHP Fatal error:  Uncaught {s}: {s} in {s}:{d}\n" ++
                "Stack trace:\n#0 {{main}}\n" ++
                "  thrown in {s} on line {d}\n",
            .{ class_name, message, src_file, src_line, src_file, src_line },
        ) catch "";
        fileWriteAll(2, emsg);
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &buf,
            "\nFatal error: Uncaught {s}: {s} in {s}:{d}\n" ++
                "Stack trace:\n#0 {{main}}\n" ++
                "  thrown in {s} on line {d}\n",
            .{ class_name, message, src_file, src_line, src_file, src_line },
        ) catch "";
        fileWriteAll(1, msg);
        std.process.exit(255);
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
    if (user_function_decl_locations) |*locations| {
        locations.deinit();
        user_function_decl_locations = null;
    }
    if (function_meta_registry) |*meta_reg| {
        meta_reg.deinit();
        function_meta_registry = null;
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
    cycle_roots = .{ .items = &.{}, .capacity = 0 };
    // std.debug.print("deinitRuntime: cleaning up {d} static strings\n", .{static_string_entries.items.len});
    for (static_string_entries.items) |e| {
        // std.debug.print("deinitRuntime: cleaning static string: {s}\n", .{e.php.data});
        e.deinit(runtime_allocator);
    }
    static_string_entries.deinit(runtime_allocator);
    static_string_entries = .{ .items = &.{}, .capacity = 0 };
    if (static_string_pool) |*pool| {
        pool.deinit();
        static_string_pool = null;
    }
    if (array_internal_pointers) |*m| {
        m.deinit();
        array_internal_pointers = null;
    }
    if (php_string_pool) |*p| {
        p.deinit(runtime_allocator);
        php_string_pool = null;
    }
    if (php_array_pool) |*p| {
        p.deinit(runtime_allocator);
        php_array_pool = null;
    }
    if (php_closure_pool) |*p| {
        p.deinit(runtime_allocator);
        php_closure_pool = null;
    }
}

/// 注册用户定义函数
pub fn registerUserFunction(name: []const u8, func: *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value) !void {
    try registerUserFunctionWithLocation(name, func, "", 0);
}

pub fn registerUserFunctionWithLocation(name: []const u8, func: *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value, file: []const u8, line: u32) !void {
    if (user_function_registry) |*registry| {
        if (registry.get(name) != null) {
            var prev_file = file;
            var prev_line = line;
            if (user_function_decl_locations) |*locations| {
                if (locations.get(name)) |loc| {
                    prev_file = loc.file;
                    prev_line = loc.line;
                }
            }
            // PHP 输出顺序：先 stderr，再 stdout
            var ebuf: [1024]u8 = undefined;
            const emsg = std.fmt.bufPrint(
                &ebuf,
                "PHP Fatal error:  Cannot redeclare function {s}() (previously declared in {s}:{d}) in {s} on line {d}\n",
                .{ name, prev_file, prev_line, file, line },
            ) catch "";
            fileWriteAll(2, emsg);
            var buf: [1024]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "\nFatal error: Cannot redeclare function {s}() (previously declared in {s}:{d}) in {s} on line {d}\n",
                .{ name, prev_file, prev_line, file, line },
            ) catch "";
            fileWriteAll(1, msg);
            std.process.exit(255);
        }
        try registry.put(name, func);
        if (user_function_decl_locations) |*locations| {
            try locations.put(name, .{ .file = file, .line = line });
        }
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
    if (gc_in_progress or !gc_enabled) return;
    gc_release_events += 1;
    if (cycle_roots.items.len >= GC_ROOT_THRESHOLD or gc_release_events >= GC_RELEASE_EVENT_THRESHOLD) {
        _ = gcCollectCycles(false);
    }
}

fn gcCollectCycles(force: bool) usize {
    if (gc_in_progress) return 0;
    if (!force) {
        if (!gc_enabled) return 0;
        if (cycle_roots.items.len < GC_ROOT_THRESHOLD and gc_release_events < GC_RELEASE_EVENT_THRESHOLD) return 0;
    }

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

    var white_items: std.ArrayListUnmanaged(CycleRoot) = .{ .items = &.{}, .capacity = 0 };
    defer white_items.deinit(runtime_allocator);
    var seen_arrays = std.AutoHashMap(*PHPArray, void).init(runtime_allocator);
    defer seen_arrays.deinit();
    var seen_objects = std.AutoHashMap(*PHPObject, void).init(runtime_allocator);
    defer seen_objects.deinit();
    var seen_closures = std.AutoHashMap(*PHPClosure, void).init(runtime_allocator);
    defer seen_closures.deinit();

    for (items) |r| {
        gcGatherWhite(
            r,
            &white_items,
            &seen_arrays,
            &seen_objects,
            &seen_closures,
        );
    }

    const collected = white_items.items.len;
    for (white_items.items) |r| {
        gcCollectWhiteKnown(
            r,
            &seen_arrays,
            &seen_objects,
            &seen_closures,
        );
    }

    cycle_roots.clearRetainingCapacity();
    return collected;
}

pub fn php_collect_cycles() usize {
    return gcCollectCycles(true);
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

fn gcGatherWhite(
    root: CycleRoot,
    white_items: *std.ArrayListUnmanaged(CycleRoot),
    seen_arrays: *std.AutoHashMap(*PHPArray, void),
    seen_objects: *std.AutoHashMap(*PHPObject, void),
    seen_closures: *std.AutoHashMap(*PHPClosure, void),
) void {
    switch (root) {
        .array => |a| {
            if (a.gc_info.color != .white) return;
            if (seen_arrays.contains(a)) return;
            seen_arrays.put(a, {}) catch return;
            white_items.append(runtime_allocator, .{ .array = a }) catch return;
            var it = a.elements.iterator();
            while (it.next()) |entry| {
                gcGatherWhiteValue(entry.value_ptr.*, white_items, seen_arrays, seen_objects, seen_closures);
            }
        },
        .object => |o| {
            if (o.gc_info.color != .white) return;
            if (seen_objects.contains(o)) return;
            seen_objects.put(o, {}) catch return;
            white_items.append(runtime_allocator, .{ .object = o }) catch return;
            var it = o.properties.iterator();
            while (it.next()) |entry| {
                gcGatherWhiteValue(entry.value_ptr.*, white_items, seen_arrays, seen_objects, seen_closures);
            }
        },
        .closure => |c| {
            if (c.gc_info.color != .white) return;
            if (seen_closures.contains(c)) return;
            seen_closures.put(c, {}) catch return;
            white_items.append(runtime_allocator, .{ .closure = c }) catch return;
            for (c.captures) |cap| {
                gcGatherWhiteValue(cap, white_items, seen_arrays, seen_objects, seen_closures);
            }
        },
    }
}

fn gcGatherWhiteValue(
    v: Value,
    white_items: *std.ArrayListUnmanaged(CycleRoot),
    seen_arrays: *std.AutoHashMap(*PHPArray, void),
    seen_objects: *std.AutoHashMap(*PHPObject, void),
    seen_closures: *std.AutoHashMap(*PHPClosure, void),
) void {
    if (v.isArray()) {
        gcGatherWhite(.{ .array = v.asArray() }, white_items, seen_arrays, seen_objects, seen_closures);
    } else if (Value_isObject(v)) {
        gcGatherWhite(.{ .object = Value_asObject(v) }, white_items, seen_arrays, seen_objects, seen_closures);
    } else if (v.isFunction()) {
        gcGatherWhite(.{ .closure = v.asFunction() }, white_items, seen_arrays, seen_objects, seen_closures);
    }
}

fn gcCollectWhiteKnown(
    root: CycleRoot,
    seen_arrays: *std.AutoHashMap(*PHPArray, void),
    seen_objects: *std.AutoHashMap(*PHPObject, void),
    seen_closures: *std.AutoHashMap(*PHPClosure, void),
) void {
    switch (root) {
        .array => |a| gcCollectWhiteArrayKnown(a, seen_arrays, seen_objects, seen_closures),
        .object => |o| gcCollectWhiteObjectKnown(o, seen_arrays, seen_objects, seen_closures),
        .closure => |c| gcCollectWhiteClosureKnown(c, seen_arrays, seen_objects, seen_closures),
    }
}

fn gcReleaseUnlessWhiteKnown(
    v: Value,
    allocator: Allocator,
    seen_arrays: *std.AutoHashMap(*PHPArray, void),
    seen_objects: *std.AutoHashMap(*PHPObject, void),
    seen_closures: *std.AutoHashMap(*PHPClosure, void),
) void {
    if (v.isArray()) {
        const a = v.asArray();
        if (seen_arrays.contains(a)) return;
        a.release(allocator);
        return;
    }
    if (Value_isObject(v)) {
        const o = Value_asObject(v);
        if (seen_objects.contains(o)) return;
        o.release();
        return;
    }
    if (v.isFunction()) {
        const c = v.asFunction();
        if (seen_closures.contains(c)) return;
        c.release(allocator);
        return;
    }
    v.release(allocator);
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
        if (a.gc_info.color != .white) {
            a.release(allocator);
        }
        return;
    }
    if (Value_isObject(v)) {
        const o = Value_asObject(v);
        if (o.gc_info.color != .white) {
            o.release();
        }
        return;
    }
    if (v.isFunction()) {
        const c = v.asFunction();
        if (c.gc_info.color != .white) {
            c.release(allocator);
        }
        return;
    }
    v.release(allocator);
}

fn gcCollectWhiteArrayKnown(
    a: *PHPArray,
    seen_arrays: *std.AutoHashMap(*PHPArray, void),
    seen_objects: *std.AutoHashMap(*PHPObject, void),
    seen_closures: *std.AutoHashMap(*PHPClosure, void),
) void {
    if (a.gc_info.color != .white) return;
    a.gc_info.color = .black;
    var it = a.elements.iterator();
    while (it.next()) |entry| {
        gcReleaseUnlessWhiteKnown(entry.value_ptr.*, runtime_allocator, seen_arrays, seen_objects, seen_closures);
    }
    gcDestroyArray(a);
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

fn gcCollectWhiteObjectKnown(
    o: *PHPObject,
    seen_arrays: *std.AutoHashMap(*PHPArray, void),
    seen_objects: *std.AutoHashMap(*PHPObject, void),
    seen_closures: *std.AutoHashMap(*PHPClosure, void),
) void {
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
        gcReleaseUnlessWhiteKnown(entry.value_ptr.*, o.allocator, seen_arrays, seen_objects, seen_closures);
    }
    gcDestroyObject(o);
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

fn gcCollectWhiteClosureKnown(
    c: *PHPClosure,
    seen_arrays: *std.AutoHashMap(*PHPArray, void),
    seen_objects: *std.AutoHashMap(*PHPObject, void),
    seen_closures: *std.AutoHashMap(*PHPClosure, void),
) void {
    if (c.gc_info.color != .white) return;
    c.gc_info.color = .black;
    for (c.captures) |cap| {
        gcReleaseUnlessWhiteKnown(cap, runtime_allocator, seen_arrays, seen_objects, seen_closures);
    }
    gcDestroyClosure(c);
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
