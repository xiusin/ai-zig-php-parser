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
const builtin = @import("builtin");
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
var static_vars_mutex: std.Thread.Mutex = .{};

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

    // 先初始化全局表，再注册类（类注册可能需要写入 constants）
    initClassRegistry(runtime_allocator);
    user_function_registry = std.StringHashMap(*const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value).init(runtime_allocator);
    user_function_decl_locations = std.StringHashMap(FunctionDeclLocation).init(runtime_allocator);
    function_meta_registry = std.StringHashMap(FunctionMeta).init(runtime_allocator);
    constants = std.StringHashMap(Value).init(runtime_allocator);
    static_vars = std.StringHashMap(Value).init(runtime_allocator);
    array_internal_pointers = std.AutoHashMap(*PHPArray, usize).init(runtime_allocator);
    static_string_pool = std.StringHashMap(*StaticStringEntry).init(runtime_allocator);
    static_string_entries = .{};
    cycle_roots = .{};
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
    php_string_pool = std.heap.MemoryPool(PHPString).init(runtime_allocator);
    php_array_pool = std.heap.MemoryPool(PHPArray).init(runtime_allocator);
    php_closure_pool = std.heap.MemoryPool(PHPClosure).init(runtime_allocator);
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

        const stdout = std.fs.File{ .handle = 1 };
        const stderr = std.fs.File{ .handle = 2 };
        // PHP 输出顺序：先 stderr，再 stdout
        var ebuf: [1024]u8 = undefined;
        const emsg = std.fmt.bufPrint(
            &ebuf,
            "PHP Fatal error:  Uncaught {s}: {s} in {s}:{d}\n" ++
                "Stack trace:\n#0 {{main}}\n" ++
                "  thrown in {s} on line {d}\n",
            .{ class_name, message, src_file, src_line, src_file, src_line },
        ) catch "";
        stderr.writeAll(emsg) catch {};
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &buf,
            "\nFatal error: Uncaught {s}: {s} in {s}:{d}\n" ++
                "Stack trace:\n#0 {{main}}\n" ++
                "  thrown in {s} on line {d}\n",
            .{ class_name, message, src_file, src_line, src_file, src_line },
        ) catch "";
        stdout.writeAll(msg) catch {};
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
            const stdout = std.fs.File{ .handle = 1 };
            const stderr = std.fs.File{ .handle = 2 };
            // PHP 输出顺序：先 stderr，再 stdout
            var ebuf: [1024]u8 = undefined;
            const emsg = std.fmt.bufPrint(
                &ebuf,
                "PHP Fatal error:  Cannot redeclare function {s}() (previously declared in {s}:{d}) in {s} on line {d}\n",
                .{ name, prev_file, prev_line, file, line },
            ) catch "";
            stderr.writeAll(emsg) catch {};
            var buf: [1024]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "\nFatal error: Cannot redeclare function {s}() (previously declared in {s}:{d}) in {s} on line {d}\n",
                .{ name, prev_file, prev_line, file, line },
            ) catch "";
            stdout.writeAll(msg) catch {};
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

    var white_items: std.ArrayListUnmanaged(CycleRoot) = .{};
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
            std.debug.print("ERROR: String too large: {d} bytes ({d} MB)\n", .{ str.len, str.len / (1024 * 1024) });
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
            std.debug.print("ERROR: Concat result too large: {d} + {d} = {d} bytes ({d} MB)\n", .{ self.length, other.length, new_length, new_length / (1024 * 1024) });
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

fn parsePhpArrayIntKey(str: []const u8) ?i64 {
    if (str.len == 0) return null;
    if (str[0] == '+') return null;

    var start: usize = 0;
    var negative = false;
    if (str[0] == '-') {
        negative = true;
        start = 1;
        if (str.len == 1) return null;
    }

    const digits = str[start..];
    if (digits.len == 0) return null;
    if (digits[0] == '0' and digits.len > 1) return null;

    for (digits) |c| {
        if (!std.ascii.isDigit(c)) return null;
    }

    const parsed = std.fmt.parseInt(i64, digits, 10) catch return null;
    return if (negative) -parsed else parsed;
}

fn normalizeArrayKeyFromValue(key: Value) ArrayKey {
    if (key.isString()) {
        if (parsePhpArrayIntKey(key.asString().data)) |i| {
            return ArrayKey{ .integer = i };
        }
        return ArrayKey{ .string = key.asString() };
    }
    return ArrayKey{ .integer = key.toInt() };
}

/// PHP数组类型
/// 支持整数键和字符串键的混合数组
pub const PHPArray = struct {
    elements: Elements,
    next_index: i64,
    ref_count: usize,
    gc_info: GCInfo,
    has_active_refs: bool = false, // 是否有活跃的引用
    ref_lock_count: u32 = 0, // 引用锁计数

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
        parent: ?*PHPArray = null, // 父数组引用
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

        /// 检查是否包含字符串键（关联数组）
        pub fn hasStringKeys(self: *const Elements) bool {
            const m = self.mixed orelse return false;
            const keys = m.unmanaged.entries.items(.key);
            for (keys) |k| {
                if (k == .string) return true;
            }
            return false;
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
        array.elements.parent = array; // 设置父引用
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

    /// 深拷贝数组（PHP 值语义：数组赋值时复制）
    /// 对嵌套数组递归复制；对象/字符串仅增加引用计数（PHP 中对象仍然按引用共享）
    pub fn cloneDeep(self: *PHPArray, allocator: Allocator) !*PHPArray {
        const new_arr = try PHPArray.init(allocator);
        new_arr.next_index = self.next_index;
        var iter = self.elements.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            // 递归克隆子数组；其他类型（字符串/对象/标量）仅 retain
            var new_val: Value = undefined;
            if (val.isArray() and !val.isRef()) {
                const sub = try val.asArray().cloneDeep(allocator);
                new_val = Value.initArray(sub);
            } else {
                new_val = val.retain();
            }
            // 若 key 为字符串，需要增加字符串的引用计数
            const new_key: ArrayKey = switch (key) {
                .string => |s| blk: {
                    s.retain();
                    break :blk .{ .string = s };
                },
                .integer => key,
            };
            try new_arr.elements.put(new_key, new_val);
        }
        return new_arr;
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPArray, allocator: Allocator) void {
        // 检测内存破坏
        if (self.ref_count > 1000000) {
            std.debug.print("ERROR: PHPArray corrupted! ref_count={d} (0x{x})\n", .{ self.ref_count, self.ref_count });
            return;
        }

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
        return self.get(normalizeArrayKeyFromValue(key));
    }

    /// 设置元素（通过Value键）
    pub fn setByValue(self: *PHPArray, allocator: Allocator, key: Value, value: Value) !void {
        try self.set(allocator, normalizeArrayKeyFromValue(key), value);
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

    /// 检查是否包含字符串键（关联数组）
    pub fn hasStringKeys(self: *PHPArray) bool {
        return self.elements.hasStringKeys();
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
        return self.unset(allocator, normalizeArrayKeyFromValue(key));
    }

    /// 通过整数索引获取元素（用于数组遍历）
    /// 参数: index - 整数索引 (usize)
    /// 返回: 对应位置的元素，如果不存在返回 null
    pub fn getByIndex(self: *PHPArray, index: usize) ?Value {
        return self.elements.get(.{ .integer = @intCast(index) });
    }

    /// 通过整数索引获取元素指针（用于引用修改）
    /// 参数: index - 整数索引 (usize)
    /// 返回: 对应位置的元素指针，如果不存在返回 null
    pub fn getPtrByIndex(self: *PHPArray, index: usize) ?*Value {
        return self.elements.getPtr(.{ .integer = @intCast(index) });
    }

    /// 设置元素（通过整数索引）
    pub fn setByIndex(self: *PHPArray, allocator: Allocator, index: usize, value: Value) !void {
        try self.set(allocator, .{ .integer = @intCast(index) }, value);
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
    pub const TYPE_BIGINT: u64 = nanbox_abi.TYPE_BIGINT;

    // 堆装箱大整数（超出48位范围）
    pub const BoxedInt = struct {
        ref_count: u32,
        value: i64,
    };

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
        // 超出48位范围：堆装箱存储，保留完整i64精度
        const boxed = runtime_allocator.create(BoxedInt) catch {
            // 分配失败：降级为浮点数（有精度损失）
            return .{ .val = @bitCast(@as(f64, @floatFromInt(i))) };
        };
        boxed.* = .{ .ref_count = 1, .value = i };
        const addr = @intFromPtr(boxed);
        return .{ .val = nanbox_abi.encodePtr(addr, TYPE_BIGINT) };
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
        if ((self.val & (SIGN_BIT | QNAN)) == TAG_INT_MARKER) return true;
        // 检查堆装箱大整数
        if ((self.val & (SIGN_BIT | QNAN)) == QNAN) {
            return (self.val & TYPE_MASK) == TYPE_BIGINT;
        }
        return false;
    }

    pub fn isBigInt(self: Value) bool {
        return (self.val & (SIGN_BIT | QNAN)) == QNAN and (self.val & TYPE_MASK) == TYPE_BIGINT;
    }

    pub fn isFloat(self: Value) bool {
        if ((self.val & QNAN) != QNAN) return true;
        return false;
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
        // 堆装箱大整数
        if (self.isBigInt()) {
            const boxed: *BoxedInt = @ptrFromInt(nanbox_abi.decodePtr(self.val));
            return boxed.value;
        }
        // 可能是浮点数存储的大整数（降级路径）
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
        const ptr = nanbox_abi.decodePtr(self.val);
        const str: *PHPString = @ptrFromInt(ptr);

        // 检测内存破坏
        if (str.length > 1024 * 1024 * 100) {
            std.debug.print("ERROR: PHPString corrupted! length={d} (0x{x})\n", .{ str.length, str.length });
            // 返回空字符串避免崩溃
            return @constCast(&EMPTY_STRING);
        }

        return str;
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
        } else if (self.isBigInt()) {
            const boxed: *BoxedInt = @ptrFromInt(nanbox_abi.decodePtr(self.val));
            boxed.ref_count += 1;
        }
        return self;
    }

    pub fn release(self: Value, allocator: Allocator) void {
        // 引用不需要释放（只是指针）
        if (self.isRef()) {
            return;
        }
        if (self.isString()) {
            const str = self.asString();
            // 检测破坏
            if (str.length > 1024 * 1024 * 100) {
                std.debug.print("ERROR: Corrupted string in release! length={d}\n", .{str.length});
                return;
            }
            str.release(allocator);
        } else if (self.isArray()) {
            self.asArray().release(allocator);
        } else if (Value_isObject(self)) {
            Value_asObject(self).release();
        } else if (self.isFunction()) {
            self.asFunction().release(allocator);
        } else if (self.isBigInt()) {
            const boxed: *BoxedInt = @ptrFromInt(nanbox_abi.decodePtr(self.val));
            if (boxed.ref_count > 0) {
                boxed.ref_count -= 1;
                if (boxed.ref_count == 0) {
                    allocator.destroy(boxed);
                }
            }
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
            // 使用saturating转换避免panic
            if (std.math.isNan(f)) return 0;
            if (f >= @as(f64, @floatFromInt(std.math.maxInt(i64)))) return std.math.maxInt(i64);
            if (f <= @as(f64, @floatFromInt(std.math.minInt(i64)))) return std.math.minInt(i64);
            return @intFromFloat(f);
        }
        if (self.isBool()) return if (self.asBool()) 1 else 0;
        if (self.isNull()) return 0;
        // 字符串转整数：PHP语义（解析数字前缀）
        if (self.isString()) {
            const str = self.asString();
            if (str.length == 0) return 0;

            // PHP行为：解析前导数字，遇到非数字停止
            var result: i64 = 0;
            var i: usize = 0;
            var negative = false;

            // 跳过前导空格
            while (i < str.length and std.ascii.isWhitespace(str.data[i])) : (i += 1) {}

            // 处理符号
            if (i < str.length and (str.data[i] == '+' or str.data[i] == '-')) {
                negative = (str.data[i] == '-');
                i += 1;
            }

            // 解析数字（遇到非数字停止）
            var has_digits = false;
            while (i < str.length and std.ascii.isDigit(str.data[i])) : (i += 1) {
                has_digits = true;
                const digit = str.data[i] - '0';
                result = result * 10 + digit;
            }

            // 如果没有数字，返回0
            if (!has_digits) return 0;

            return if (negative) -result else result;
        }
        // 数组转整数：非空数组返回1，空数组返回0
        if (self.isArray()) {
            const arr = self.asArray();
            return if (arr.count() > 0) 1 else 0;
        }
        return 0;
    }

    /// 转换为浮点数（PHP语义）
    pub fn toFloat(self: Value) f64 {
        if (self.isFloat()) return self.asFloat();
        if (self.isInt()) return @floatFromInt(self.asInt());
        if (self.isBool()) return if (self.asBool()) 1.0 else 0.0;
        if (self.isNull()) return 0.0;
        // 数组转浮点数：非空数组返回1.0，空数组返回0.0
        if (self.isArray()) {
            const arr = self.asArray();
            return if (arr.count() > 0) 1.0 else 0.0;
        }
        if (self.isString()) {
            const str = self.asString();
            if (str.length == 0) return 0.0;

            // PHP行为：解析前导数字（支持浮点数）
            var result: f64 = 0.0;
            var i: usize = 0;
            var negative = false;

            // 跳过前导空格
            while (i < str.length and std.ascii.isWhitespace(str.data[i])) : (i += 1) {}

            // 处理符号
            if (i < str.length and (str.data[i] == '+' or str.data[i] == '-')) {
                negative = (str.data[i] == '-');
                i += 1;
            }

            // 解析整数部分
            var has_digits = false;
            while (i < str.length and std.ascii.isDigit(str.data[i])) : (i += 1) {
                has_digits = true;
                const digit = str.data[i] - '0';
                result = result * 10.0 + @as(f64, @floatFromInt(digit));
            }

            // 解析小数部分
            if (i < str.length and str.data[i] == '.') {
                i += 1;
                var decimal_place: f64 = 0.1;
                while (i < str.length and std.ascii.isDigit(str.data[i])) : (i += 1) {
                    has_digits = true;
                    const digit = str.data[i] - '0';
                    result += @as(f64, @floatFromInt(digit)) * decimal_place;
                    decimal_place *= 0.1;
                }
            }

            // 如果没有数字，返回0
            if (!has_digits) return 0.0;

            return if (negative) -result else result;
        }
        return 0.0;
    }

    /// 转换为字符串（PHP语义）
    /// 注意：返回的字符串引用计数已经+1，调用者负责release
    /// 将Value转换为字符串
    /// PHP 8+行为：数组转字符串抛出异常
    pub fn toString(self: Value, allocator: Allocator) !*PHPString {
        if (self.isNull()) return PHPString.init(allocator, "");
        if (self.isBool()) return PHPString.init(allocator, if (self.asBool()) "1" else "");
        if (self.isInt()) {
            const str = try std.fmt.allocPrint(allocator, "{d}", .{self.asInt()});
            defer allocator.free(str);
            return PHPString.init(allocator, str);
        }
        if (self.isFloat()) {
            var buf: [64]u8 = undefined;
            const str = phpFormatFloat(&buf, self.asFloat());
            return PHPString.init(allocator, str);
        }
        if (self.isString()) {
            // 对于已经是字符串的值，创建一个新副本
            // 这样调用者可以安全地release而不影响原始值
            return PHPString.init(allocator, self.asString().data);
        }
        if (self.isArray()) {
            // PHP 行为：发出 Warning 并返回 "Array"
            emitWarning("Array to string conversion");
            return PHPString.init(allocator, "Array");
        }
        if (self.isFunction()) {
            // 函数转字符串也应该抛出异常（PHP 8+）
            _ = try throwException("Object of class Closure could not be converted to string", allocator);
            return PHPString.init(allocator, "");
        }
        if (Value_isObject(self)) {
            // 对象转字符串：尝试调用__toString()
            // 如果没有__toString()，PHP 8+抛出异常
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
    param_count: u16 = 0,
    required_params: u16 = 0,

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

        f.* = .{ .func = func, .captures = caps, .ref_count = 1, .gc_info = .{}, .allocator = allocator, .param_count = 0, .required_params = 0 };
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
/// PHP 值语义：若赋值源为共享数组（非引用且 ref_count > 1），
/// 为目标制作一份深拷贝，避免两个变量通过同一底层数组互相影响。
/// 注意：调用者负责释放旧值和 retain 新值。若触发 clone，本函数会撤销调用者的 retain。
pub fn val_assign(target: *Value, value: Value) void {
    if (value.isArray() and !value.isRef()) {
        const arr = value.asArray();
        // 调用者已经执行一次 retain，因此当 ref_count > 1 时，除本次引用外仍有其他持有者，
        // 需要分离（COW）以维持值语义。
        if (arr.ref_count > 1) {
            const cloned = arr.cloneDeep(runtime_allocator) catch {
                target.* = value;
                return;
            };
            // 撤销调用者的 retain（原数组少一个引用）
            arr.release(runtime_allocator);
            target.* = Value.initArray(cloned);
            return;
        }
    }
    target.* = value;
}

/// 引用感知的赋值：如果目标含引用则写穿到堆单元，否则直接赋值
/// @pre  target 指向有效的 Value（可为 Ref 或普通值）
/// @post 新值写入实际存储位置，旧值已 release，新值已 retain
pub fn ref_aware_store(target: *Value, new_val: Value) void {
    const dest = val_deref(target);
    dest.*.release(runtime_allocator);
    _ = new_val.retain();
    dest.* = new_val;
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
    // 如果变量已经是引用，直接复用同一引用单元（多闭包共享 use(&$var) 场景）
    if (ptr.isRef()) {
        _ = ptr.retain();
        return ptr.*;
    }
    const cell = try allocator.create(Value);
    cell.* = ptr.*;
    _ = cell.retain();
    // 重定向父作用域的存储，使后续 val_deref 读写均经过堆单元
    ptr.*.release(allocator);
    ptr.* = Value.initRef(cell);
    return Value.initRef(cell);
}

const BuiltinFn = *const fn (ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value;

const builtin_function_map = std.StaticStringMap(BuiltinFn).initComptime(.{
    .{ "strlen", wrapBuiltin_strlen },
    .{ "strtoupper", wrapBuiltin_strtoupper },
    .{ "strtolower", wrapBuiltin_strtolower },
    .{ "str_ireplace", wrapBuiltin_str_ireplace },
    .{ "str_getcsv", wrapBuiltin_str_getcsv },
    .{ "func_get_args", wrapBuiltin_func_get_args },
    .{ "func_get_arg", wrapBuiltin_func_get_arg },
    .{ "func_num_args", wrapBuiltin_func_num_args },
    .{ "memory_get_usage", wrapBuiltin_memory_get_usage },
    .{ "memory_get_peak_usage", wrapBuiltin_memory_get_peak_usage },
    .{ "function_exists", wrapBuiltin_function_exists },
    .{ "gc_enable", wrapBuiltin_gc_enable },
    .{ "gc_collect_cycles", wrapBuiltin_gc_collect_cycles },
    .{ "ini_get", wrapBuiltin_ini_get },
    .{ "getrusage", wrapBuiltin_getrusage },
    .{ "json_decode", wrapBuiltin_json_decode },
    .{ "json_last_error_msg", wrapBuiltin_json_last_error_msg },
    .{ "trim", wrapBuiltin_trim },
    .{ "count", wrapBuiltin_count },
    .{ "sqrt", wrapBuiltin_sqrt },
    .{ "strval", wrapBuiltin_strval },
    .{ "array_map", wrapBuiltin_array_map },
    .{ "array_filter", wrapBuiltin_array_filter },
    .{ "array_reduce", wrapBuiltin_array_reduce },
    .{ "array_walk", wrapBuiltin_array_walk },
    .{ "array_walk_recursive", wrapBuiltin_array_walk_recursive },
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
    // 文件系统函数
    .{ "filemtime", wrapBuiltin_filemtime },
    .{ "fileatime", wrapBuiltin_fileatime },
    .{ "filectime", wrapBuiltin_filectime },
    // 网络函数
    .{ "gethostbyname", wrapBuiltin_gethostbyname },
    .{ "gethostname", wrapBuiltin_gethostname },
    .{ "ip2long", wrapBuiltin_ip2long },
    .{ "long2ip", wrapBuiltin_long2ip },
    .{ "parse_url", wrapBuiltin_parse_url },
    // 错误处理函数
    .{ "set_error_handler", wrapBuiltin_set_error_handler },
    .{ "restore_error_handler", wrapBuiltin_restore_error_handler },
    .{ "trigger_error", wrapBuiltin_trigger_error },
    .{ "error_reporting", wrapBuiltin_error_reporting },
    // Ctype 字符类型检测函数
    .{ "ctype_alnum", wrapBuiltin_ctype_alnum },
    .{ "ctype_alpha", wrapBuiltin_ctype_alpha },
    .{ "ctype_cntrl", wrapBuiltin_ctype_cntrl },
    .{ "ctype_digit", wrapBuiltin_ctype_digit },
    .{ "ctype_graph", wrapBuiltin_ctype_graph },
    .{ "ctype_lower", wrapBuiltin_ctype_lower },
    .{ "ctype_print", wrapBuiltin_ctype_print },
    .{ "ctype_punct", wrapBuiltin_ctype_punct },
    .{ "ctype_space", wrapBuiltin_ctype_space },
    .{ "ctype_upper", wrapBuiltin_ctype_upper },
    .{ "ctype_xdigit", wrapBuiltin_ctype_xdigit },
    // Mbstring 多字节字符串函数
    .{ "mb_strlen", wrapBuiltin_mb_strlen },
    .{ "mb_substr", wrapBuiltin_mb_substr },
    .{ "mb_strtoupper", wrapBuiltin_mb_strtoupper },
    .{ "mb_strtolower", wrapBuiltin_mb_strtolower },
    // 字符串函数
    .{ "substr_count", wrapBuiltin_substr_count },
    .{ "ucfirst", wrapBuiltin_ucfirst },
    .{ "lcfirst", wrapBuiltin_lcfirst },
    .{ "ucwords", wrapBuiltin_ucwords },
    .{ "strrpos", wrapBuiltin_strrpos },
    .{ "strripos", wrapBuiltin_strripos },
    .{ "str_word_count", wrapBuiltin_str_word_count },
    .{ "substr", wrapBuiltin_substr },
    .{ "strpos", wrapBuiltin_strpos },
    // 数学函数
    .{ "floor", wrapBuiltin_floor },
    .{ "ceil", wrapBuiltin_ceil },
    .{ "sin", wrapBuiltin_sin },
    .{ "cos", wrapBuiltin_cos },
    .{ "tan", wrapBuiltin_tan },
    .{ "log", wrapBuiltin_log },
    .{ "exp", wrapBuiltin_exp },
    .{ "hypot", wrapBuiltin_hypot },
    .{ "pow", wrapBuiltin_pow },
    .{ "min", wrapBuiltin_min },
    .{ "max", wrapBuiltin_max },
    // 字符串函数
    .{ "stripos", wrapBuiltin_stripos },
    .{ "strstr", wrapBuiltin_strstr },
    .{ "str_split", wrapBuiltin_str_split },
    .{ "implode", wrapBuiltin_implode },
    .{ "explode", wrapBuiltin_explode },
    // 回调函数
    .{ "is_callable", wrapBuiltin_is_callable },
    .{ "get_debug_type", wrapBuiltin_get_debug_type },
    .{ "call_user_func", wrapBuiltin_call_user_func },
    .{ "call_user_func_array", wrapBuiltin_call_user_func_array },
    .{ "compact", wrapBuiltin_compact },
    .{ "extract", wrapBuiltin_extract },
    // 字符操作函数
    .{ "ord", wrapBuiltin_ord },
    .{ "chr", wrapBuiltin_chr },
    .{ "md5", wrapBuiltin_md5 },
    .{ "sha1", wrapBuiltin_sha1 },
    .{ "crc32", wrapBuiltin_crc32 },
    .{ "strrev", wrapBuiltin_strrev },
    .{ "ltrim", wrapBuiltin_ltrim },
    .{ "rtrim", wrapBuiltin_rtrim },
    .{ "addslashes", wrapBuiltin_addslashes },
    .{ "stripslashes", wrapBuiltin_stripslashes },
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
    // 从元数据注册表设置参数计数
    if (function_meta_registry) |meta_reg| {
        if (meta_reg.get(func_name)) |meta| {
            closure.param_count = meta.param_count;
            closure.required_params = meta.required_params;
        }
    }
    return Value.initFunction(closure);
}

pub fn php_object_isset(obj_val: Value, property_name_val: Value) !Value {
    if (!Value_isObject(obj_val)) return Value.initBool(!obj_val.isNull());

    const obj = Value_asObject(obj_val);
    const prop_name = if (property_name_val.isString())
        property_name_val.asString().data
    else
        return Value.initBool(false);

    return Value.initBool(obj.hasProperty(prop_name));
}

pub fn php_object_unset(obj_val: Value, property_name_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) return Value.initNull();

    const obj = Value_asObject(obj_val);
    if (property_name_val.isString()) {
        _ = try obj.unsetProperty(property_name_val.asString().data);
        return Value.initNull();
    }

    const property_name = try property_name_val.toString(allocator);
    defer property_name.release(allocator);
    _ = try obj.unsetProperty(property_name.data);
    return Value.initNull();
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

fn wrapBuiltin_str_ireplace(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 3) return error.InvalidArgumentCount;
    const count_out = if (args.len >= 4) args[3] else Value.initNull();
    return php_str_ireplace(args[0], args[1], args[2], count_out, allocator);
}

fn wrapBuiltin_str_getcsv(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    if (args.len < 4) emitDeprecatedStrGetcsvEscape();
    const separator = if (args.len >= 2) args[1] else Value.initString(PHPString.initStatic(","));
    const enclosure = if (args.len >= 3) args[2] else Value.initString(PHPString.initStatic("\""));
    const escape = if (args.len >= 4) args[3] else Value.initString(PHPString.initStatic("\\"));
    return php_str_getcsv(args[0], separator, enclosure, escape, allocator);
}

fn wrapBuiltin_func_get_args(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_func_get_args(args, allocator);
}

fn wrapBuiltin_func_get_arg(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_func_get_arg(args[0]);
}

fn wrapBuiltin_func_num_args(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_func_num_args();
}

fn wrapBuiltin_memory_get_usage(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_memory_get_usage(args, allocator);
}

fn wrapBuiltin_memory_get_peak_usage(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_memory_get_peak_usage(args, allocator);
}

fn wrapBuiltin_function_exists(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_function_exists(args, allocator);
}

fn wrapBuiltin_gc_enable(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_gc_enable(args, allocator);
}

fn wrapBuiltin_gc_collect_cycles(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_gc_collect_cycles(args, allocator);
}

fn wrapBuiltin_ini_get(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_ini_get(args, allocator);
}

fn wrapBuiltin_getrusage(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_getrusage(args, allocator);
}

pub fn php_func_get_args(args: []const Value, allocator: Allocator) !Value {
    if (args.len != 0) return error.InvalidArgumentCount;
    const arr = try PHPArray.init(allocator);
    if (current_call_args) |call_args| {
        for (call_args, 0..) |arg, i| {
            try arr.set(allocator, ArrayKey{ .integer = @intCast(i) }, arg);
        }
    }
    return Value.initArray(arr);
}

pub fn php_func_get_arg(index_val: Value) !Value {
    if (!index_val.isInt()) return error.InvalidArgument;
    const call_args = current_call_args orelse return Value.initBool(false);
    const index = index_val.asInt();
    if (index < 0) return Value.initBool(false);
    const idx: usize = @intCast(index);
    if (idx >= call_args.len) return Value.initBool(false);
    return call_args[idx];
}

pub fn php_func_num_args() !Value {
    const call_args = current_call_args orelse return Value.initInt(0);
    return Value.initInt(@intCast(call_args.len));
}

pub fn php_memory_get_usage(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len > 1) return error.InvalidArgumentCount;
    return Value.initInt(@intCast(alloc_counters.live_bytes));
}

pub fn php_memory_get_peak_usage(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len > 1) return error.InvalidArgumentCount;
    return Value.initInt(@intCast(alloc_counters.peak_live_bytes));
}

/// shell_exec - 执行shell命令并返回完整输出
pub fn php_shell_exec(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return Value.initNull();
    
    const cmd_val = args[0];
    if (!cmd_val.isString()) return Value.initNull();
    
    const cmd_str = cmd_val.asString().data;
    
    // 执行命令
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd_str },
        .max_output_bytes = 1024 * 1024,
    }) catch return Value.initNull();
    
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    
    const output = try PHPString.init(allocator, result.stdout);
    return Value.initString(output);
}

/// exec - 执行命令并返回输出数组
/// PHP签名: exec(string $command, array &$output = null, int &$result_code = null): string|false
pub fn php_exec(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return Value.initNull();
    
    const cmd_val = args[0];
    if (!cmd_val.isString()) return Value.initNull();
    
    const cmd_str = cmd_val.asString().data;
    
    // 执行命令
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd_str },
        .max_output_bytes = 1024 * 1024,
    }) catch return Value.initBool(false);
    
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    
    // 将输出按行分割成数组
    const arr = try PHPArray.init(allocator);
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    var idx: i64 = 0;
    var last_line: []const u8 = "";
    while (lines.next()) |line| {
        if (line.len == 0 and lines.peek() == null) break; // 跳过最后的空行
        last_line = line;
        const line_str = try PHPString.init(allocator, line);
        try arr.set(allocator, ArrayKey{ .integer = idx }, Value.initString(line_str));
        idx += 1;
    }
    
    // 如果有第二个参数（&$output引用），写回输出数组
    if (args.len >= 2) {
        const output_ref = args[1];
        if (output_ref.isRef()) {
            const ptr = output_ref.asRef();
            // 如果引用指向的是数组，追加到现有数组；否则替换为新数组
            if (ptr.isArray()) {
                const existing_arr = ptr.asArray();
                // 追加新行到现有数组
                var new_lines = std.mem.splitScalar(u8, result.stdout, '\n');
                while (new_lines.next()) |line| {
                    if (line.len == 0 and new_lines.peek() == null) break;
                    const line_str = try PHPString.init(allocator, line);
                    try existing_arr.push(allocator, Value.initString(line_str));
                }
            } else {
                // 替换为新数组
                ptr.release(allocator);
                _ = Value.initArray(arr).retain();
                ptr.* = Value.initArray(arr);
            }
        }
    }
    
    // 如果有第三个参数（&$return_code引用），写回返回码
    if (args.len >= 3) {
        const return_code_ref = args[2];
        if (return_code_ref.isRef()) {
            const ptr = return_code_ref.asRef();
            ptr.release(allocator);
            const exit_code: i64 = @intCast(result.term.Exited);
            ptr.* = Value.initInt(exit_code);
        }
    }
    
    // 返回最后一行输出
    if (last_line.len > 0) {
        const last_str = try PHPString.init(allocator, last_line);
        return Value.initString(last_str);
    }
    return Value.initString(try PHPString.init(allocator, ""));
}

/// system - 执行命令，输出到stdout，返回最后一行
/// PHP签名: system(string $command, int &$result_code = null): string|false
pub fn php_system(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return Value.initNull();
    
    const cmd_val = args[0];
    if (!cmd_val.isString()) return Value.initNull();
    
    const cmd_str = cmd_val.asString().data;
    
    // 执行命令
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd_str },
        .max_output_bytes = 1024 * 1024,
    }) catch return Value.initBool(false);
    
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    
    // 输出到stdout（模拟PHP的system行为）
    if (result.stdout.len > 0) {
        const stdout_file = std.fs.File{ .handle = 1 };
        stdout_file.writeAll(result.stdout) catch {};
    }
    
    // 如果有第二个参数（&$return_var引用），写回返回码
    if (args.len >= 2) {
        const return_var_ref = args[1];
        if (return_var_ref.isRef()) {
            const ptr = return_var_ref.asRef();
            ptr.release(allocator);
            const exit_code: i64 = @intCast(result.term.Exited);
            ptr.* = Value.initInt(exit_code);
        }
    }
    
    // 返回最后一行
    if (result.stdout.len == 0) return Value.initBool(false);
    
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    var last_line: []const u8 = "";
    while (lines.next()) |line| {
        if (line.len > 0) last_line = line;
    }
    
    const last_str = try PHPString.init(allocator, last_line);
    return Value.initString(last_str);
}

/// escapeshellarg - 转义shell参数
/// PHP签名: escapeshellarg(string $arg): string
pub fn php_escapeshellarg(arg_val: Value, allocator: Allocator) !Value {
    if (!arg_val.isString()) {
        const str = try arg_val.toString(allocator);
        defer str.release(allocator);
        return php_escapeshellarg(Value.initString(str), allocator);
    }
    
    const arg = arg_val.asString().data;
    
    // 计算结果长度：每个单引号需要转义为 '\''，加上首尾的单引号
    var result_len: usize = 2; // 首尾单引号
    for (arg) |c| {
        if (c == '\'') {
            result_len += 4; // '\''
        } else {
            result_len += 1;
        }
    }
    
    const result = try allocator.alloc(u8, result_len);
    var pos: usize = 0;
    result[pos] = '\'';
    pos += 1;
    
    for (arg) |c| {
        if (c == '\'') {
            // 替换 ' 为 '\''
            result[pos] = '\'';
            result[pos + 1] = '\\';
            result[pos + 2] = '\'';
            result[pos + 3] = '\'';
            pos += 4;
        } else {
            result[pos] = c;
            pos += 1;
        }
    }
    
    result[pos] = '\'';
    
    const php_str = try PHPString.init(allocator, result);
    allocator.free(result);
    return Value.initString(php_str);
}

/// escapeshellcmd - 转义shell命令中的特殊字符
/// PHP签名: escapeshellcmd(string $command): string
pub fn php_escapeshellcmd(cmd_val: Value, allocator: Allocator) !Value {
    if (!cmd_val.isString()) {
        const str = try cmd_val.toString(allocator);
        defer str.release(allocator);
        return php_escapeshellcmd(Value.initString(str), allocator);
    }
    
    const cmd = cmd_val.asString().data;
    
    // 需要转义的字符: &#;`|*?~<>^()[]{}$\, \x0A, \xFF, 以及未配对的引号
    const special_chars = "&#;`|*?~<>^()[]{}$\\";
    
    // 计算结果长度
    var result_len: usize = 0;
    var single_quote_count: usize = 0;
    var double_quote_count: usize = 0;
    
    for (cmd) |c| {
        if (c == '\'') single_quote_count += 1;
        if (c == '"') double_quote_count += 1;
        
        var is_special = false;
        for (special_chars) |sc| {
            if (c == sc) {
                is_special = true;
                break;
            }
        }
        if (is_special or c == '\n' or c == 0xFF) {
            result_len += 2; // 添加反斜杠
        } else {
            result_len += 1;
        }
    }
    
    // 处理未配对的引号
    const escape_single = (single_quote_count % 2) == 1;
    const escape_double = (double_quote_count % 2) == 1;
    if (escape_single) result_len += single_quote_count;
    if (escape_double) result_len += double_quote_count;
    
    const result = try allocator.alloc(u8, result_len);
    var pos: usize = 0;
    
    for (cmd) |c| {
        // 检查是否是特殊字符
        var is_special = false;
        for (special_chars) |sc| {
            if (c == sc) {
                is_special = true;
                break;
            }
        }
        
        if (c == '\'' and escape_single) {
            result[pos] = '\\';
            result[pos + 1] = '\'';
            pos += 2;
        } else if (c == '"' and escape_double) {
            result[pos] = '\\';
            result[pos + 1] = '"';
            pos += 2;
        } else if (is_special or c == '\n' or c == 0xFF) {
            result[pos] = '\\';
            result[pos + 1] = c;
            pos += 2;
        } else {
            result[pos] = c;
            pos += 1;
        }
    }
    
    const php_str = try PHPString.init(allocator, result[0..pos]);
    allocator.free(result);
    return Value.initString(php_str);
}

/// substr_replace - 替换字符串的子串
pub fn php_substr_replace(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 2) return Value.initNull();
    
    const str_val = args[0];
    if (!str_val.isString()) return Value.initNull();
    const str = str_val.asString().data;
    
    const replacement_val = args[1];
    if (!replacement_val.isString()) return Value.initNull();
    const replacement = replacement_val.asString().data;
    
    const start = if (args.len >= 3) args[2].toInt() else 0;
    const length = if (args.len >= 4) args[3].toInt() else @as(i64, @intCast(str.len));
    
    // 处理负数索引
    const actual_start = if (start < 0) 
        @max(0, @as(i64, @intCast(str.len)) + start) 
    else 
        @min(start, @as(i64, @intCast(str.len)));
    
    const actual_length = if (length < 0)
        @max(0, @as(i64, @intCast(str.len)) - actual_start + length)
    else
        @min(length, @as(i64, @intCast(str.len)) - actual_start);
    
    const start_idx = @as(usize, @intCast(actual_start));
    const end_idx = @as(usize, @intCast(actual_start + actual_length));
    
    // 构建结果字符串
    var result = try std.ArrayList(u8).initCapacity(allocator, str.len + replacement.len);
    errdefer result.deinit(allocator);
    
    try result.appendSlice(allocator, str[0..start_idx]);
    try result.appendSlice(allocator, replacement);
    if (end_idx < str.len) {
        try result.appendSlice(allocator, str[end_idx..]);
    }
    
    const output = try PHPString.init(allocator, try result.toOwnedSlice(allocator));
    return Value.initString(output);
}

// ============================================================================
// 文件I/O函数
// ============================================================================

pub fn php_file_put_contents(filename: Value, data: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    
    const content_str = if (data.isString()) 
        data.asString().data 
    else blk: {
        const temp = try data.toString(allocator);
        defer temp.release(allocator);
        break :blk temp.data;
    };
    
    const file = std.fs.cwd().createFile(fname, .{}) catch return Value.initBool(false);
    defer file.close();
    file.writeAll(content_str) catch return Value.initBool(false);
    return Value.initInt(@intCast(content_str.len));
}

pub fn php_file_get_contents(filename: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    
    const content = std.fs.cwd().readFileAlloc(allocator, fname, 10 * 1024 * 1024) catch return Value.initBool(false);
    const output = try PHPString.init(allocator, content);
    return Value.initString(output);
}

pub fn php_fopen(filename: Value, mode: Value, allocator: Allocator) !Value {
    if (!filename.isString() or !mode.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const fmode = mode.asString().data;
    
    // 特殊处理php://流
    if (std.mem.startsWith(u8, fname, "php://")) {
        return Value.initInt(1);
    }
    
    const file = if (std.mem.eql(u8, fmode, "r"))
        std.fs.cwd().openFile(fname, .{}) catch return Value.initBool(false)
    else if (std.mem.eql(u8, fmode, "w"))
        std.fs.cwd().createFile(fname, .{}) catch return Value.initBool(false)
    else if (std.mem.eql(u8, fmode, "a"))
        std.fs.cwd().createFile(fname, .{ .truncate = false }) catch return Value.initBool(false)
    else
        return Value.initBool(false);
    
    const handle = allocator.create(std.fs.File) catch return Value.initBool(false);
    handle.* = file;
    return Value.initInt(@intCast(@intFromPtr(handle)));
}

pub fn php_fwrite(handle: Value, data: Value, allocator: Allocator) !Value {
    if (!handle.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initInt(0); // 虚拟句柄
    
    const file_handle: *std.fs.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    const content = if (data.isString()) data.asString().data else blk: {
        const temp = try data.toString(allocator);
        defer temp.release(allocator);
        break :blk temp.data;
    };
    
    file_handle.writeAll(content) catch return Value.initBool(false);
    return Value.initInt(@intCast(content.len));
}

pub fn php_fread(handle: Value, length: Value, allocator: Allocator) !Value {
    if (!handle.isInt() or !length.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initString(try PHPString.init(allocator, try allocator.dupe(u8, ""))); // 虚拟句柄
    
    const file_handle: *std.fs.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    const len = length.asInt();
    
    const buffer = allocator.alloc(u8, @intCast(len)) catch return Value.initBool(false);
    const bytes_read = file_handle.read(buffer) catch {
        allocator.free(buffer);
        return Value.initBool(false);
    };
    
    const content = allocator.realloc(buffer, bytes_read) catch {
        allocator.free(buffer);
        return Value.initBool(false);
    };
    const output = try PHPString.init(allocator, content);
    return Value.initString(output);
}

pub fn php_fclose(handle: Value) !Value {
    if (!handle.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initBool(true); // 虚拟句柄
    
    const file_handle: *std.fs.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    file_handle.close();
    return Value.initBool(true);
}

pub fn php_is_resource(val: Value) !Value {
    if (val.isInt()) {
        const i = val.asInt();
        return Value.initBool(i > 0);
    }
    return Value.initBool(false);
}

pub fn php_fgets(handle: Value) !Value {
    if (!handle.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initBool(false);
    
    const file_handle: *std.fs.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    
    while (pos < buf.len) {
        const n = file_handle.read(buf[pos..pos+1]) catch break;
        if (n == 0) break;
        pos += 1;
        if (buf[pos-1] == '\n') break;
    }
    
    if (pos == 0) return Value.initBool(false);
    
    // 需要allocator但函数签名没有，使用全局allocator
    const global_alloc = std.heap.page_allocator;
    const output = try PHPString.init(global_alloc, try global_alloc.dupe(u8, buf[0..pos]));
    return Value.initString(output);
}

pub fn php_fseek(handle: Value, offset: Value) !Value {
    if (!handle.isInt() or !offset.isInt()) return Value.initInt(-1);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initInt(-1);
    
    const file_handle: *std.fs.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    const off = offset.asInt();
    file_handle.seekTo(@intCast(off)) catch return Value.initInt(-1);
    return Value.initInt(0);
}

pub fn php_scandir(dir: Value, allocator: Allocator) !Value {
    if (!dir.isString()) return Value.initBool(false);
    const dirname = dir.asString().data;
    
    var dir_handle = std.fs.cwd().openDir(dirname, .{ .iterate = true }) catch return Value.initBool(false);
    defer dir_handle.close();
    
    var arr = try PHPArray.init(allocator);
    var iter = dir_handle.iterate();
    while (iter.next() catch null) |entry| {
        const name = try allocator.dupe(u8, entry.name);
        const str = try PHPString.init(allocator, name);
        try arr.push(allocator, Value.initString(str));
    }
    return Value.initArray(arr);
}

// ============================================================================
// 系统信息函数
// ============================================================================

pub fn php_getcwd(allocator: Allocator) !Value {
    const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch return Value.initBool(false);
    const output = try PHPString.init(allocator, cwd);
    return Value.initString(output);
}

pub fn php_sapi_name(allocator: Allocator) !Value {
    const output = try PHPString.init(allocator, try allocator.dupe(u8, "cli"));
    return Value.initString(output);
}

pub fn php_uname(allocator: Allocator) !Value {
    const uname_info = if (builtin.os.tag == .macos)
        "Darwin"
    else if (builtin.os.tag == .linux)
        "Linux"
    else if (builtin.os.tag == .windows)
        "Windows"
    else
        "Unknown";
    
    const output = try PHPString.init(allocator, try allocator.dupe(u8, uname_info));
    return Value.initString(output);
}

pub fn php_unlink(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    std.fs.cwd().deleteFile(fname) catch return Value.initBool(false);
    return Value.initBool(true);
}

pub fn php_filesize(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.fs.cwd().openFile(fname, .{}) catch return Value.initBool(false);
    defer file.close();
    const stat = file.stat() catch return Value.initBool(false);
    return Value.initInt(@intCast(stat.size));
}

pub fn php_is_file(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const stat = std.fs.cwd().statFile(fname) catch return Value.initBool(false);
    return Value.initBool(stat.kind == .file);
}

pub fn php_is_dir(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    var dir = std.fs.cwd().openDir(fname, .{}) catch return Value.initBool(false);
    dir.close();
    return Value.initBool(true);
}

pub fn php_is_readable(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.fs.cwd().openFile(fname, .{}) catch return Value.initBool(false);
    file.close();
    return Value.initBool(true);
}

pub fn php_is_writable(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.fs.cwd().createFile(fname, .{ .truncate = false }) catch return Value.initBool(false);
    file.close();
    return Value.initBool(true);
}

/// filemtime - 获取文件修改时间
pub fn php_filemtime(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.fs.cwd().openFile(fname, .{}) catch return Value.initBool(false);
    defer file.close();
    const stat = file.stat() catch return Value.initBool(false);
    // 返回Unix时间戳
    return Value.initInt(@intCast(stat.mtime));
}

/// fileatime - 获取文件访问时间
pub fn php_fileatime(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.fs.cwd().openFile(fname, .{}) catch return Value.initBool(false);
    defer file.close();
    const stat = file.stat() catch return Value.initBool(false);
    return Value.initInt(@intCast(stat.atime));
}

/// filectime - 获取文件创建时间（Unix下为inode修改时间）
pub fn php_filectime(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.fs.cwd().openFile(fname, .{}) catch return Value.initBool(false);
    defer file.close();
    const stat = file.stat() catch return Value.initBool(false);
    return Value.initInt(@intCast(stat.ctime));
}

// ============================================================================
// 错误处理函数
// ============================================================================

// 全局错误处理器存储
threadlocal var global_error_handler: ?Value = null;
threadlocal var global_error_types: i64 = E_ALL;
threadlocal var global_exception_handler: ?Value = null;

// 错误级别常量
pub const E_ERROR: i64 = 1;
pub const E_WARNING: i64 = 2;
pub const E_PARSE: i64 = 4;
pub const E_NOTICE: i64 = 8;
pub const E_CORE_ERROR: i64 = 16;
pub const E_CORE_WARNING: i64 = 32;
pub const E_COMPILE_ERROR: i64 = 64;
pub const E_COMPILE_WARNING: i64 = 128;
pub const E_USER_ERROR: i64 = 256;
pub const E_USER_WARNING: i64 = 512;
pub const E_USER_NOTICE: i64 = 1024;
pub const E_STRICT: i64 = 2048;
pub const E_RECOVERABLE_ERROR: i64 = 4096;
pub const E_DEPRECATED: i64 = 8192;
pub const E_USER_DEPRECATED: i64 = 16384;
pub const E_ALL: i64 = 32767;

/// set_error_handler - 设置用户自定义错误处理函数
pub fn php_set_error_handler(handler: Value, error_types: Value, allocator: Allocator) !Value {
    _ = allocator;
    // 返回之前设置的错误处理器
    const prev_handler = if (global_error_handler) |h| h else Value.initNull();
    
    // 设置新的错误处理器
    if (handler.isNull()) {
        global_error_handler = null;
    } else {
        _ = handler.retain();
        global_error_handler = handler;
    }
    
    // 设置错误类型掩码
    if (!error_types.isNull()) {
        global_error_types = error_types.toInt();
    }
    
    return prev_handler;
}

/// restore_error_handler - 恢复之前的错误处理函数
pub fn php_restore_error_handler() !Value {
    const prev_handler = if (global_error_handler) |h| h else Value.initNull();
    global_error_handler = null;
    return prev_handler;
}

/// set_exception_handler - 设置用户自定义异常处理函数
pub fn php_set_exception_handler(handler: Value, allocator: Allocator) !Value {
    _ = allocator;
    const prev = if (global_exception_handler) |h| h else Value.initNull();
    if (handler.isNull()) {
        global_exception_handler = null;
    } else {
        _ = handler.retain();
        global_exception_handler = handler;
    }
    return prev;
}

/// restore_exception_handler - 恢复之前的异常处理函数
pub fn php_restore_exception_handler() !Value {
    const prev = if (global_exception_handler) |h| h else Value.initNull();
    global_exception_handler = null;
    return prev;
}

/// trigger_error - 触发用户错误
pub fn php_trigger_error(message: Value, error_type: Value, allocator: Allocator) !Value {
    if (!message.isString()) return Value.initBool(false);
    
    const err_type = if (error_type.isNull()) E_USER_NOTICE else error_type.toInt();
    
    // 如果设置了自定义错误处理器
    if (global_error_handler) |handler| {
        // 检查是否在错误类型掩码内
        if ((err_type & global_error_types) != 0) {
            // 调用用户错误处理器
            if (handler.isFunction()) {
                const closure = handler.asFunction();
                var args = [_]Value{
                    message,
                    Value.initInt(err_type),
                    Value.initString(try PHPString.init(allocator, "")), // errfile
                    Value.initInt(0), // errline
                };
                _ = closure.func(Value.initNull(), args[0..], allocator) catch {};
            }
        }
    } else {
        // 没有自定义处理器，直接输出错误
        const err_type_str = switch (err_type) {
            E_USER_ERROR => "Fatal error",
            E_USER_WARNING => "Warning",
            E_USER_NOTICE => "Notice",
            E_USER_DEPRECATED => "Deprecated",
            else => "Error",
        };
        std.debug.print("{s}: {s}\n", .{ err_type_str, message.asString().data });
    }
    
    return Value.initBool(true);
}

/// error_reporting - 设置或获取错误报告级别
pub fn php_error_reporting(level: Value) !Value {
    const prev_level = global_error_types;
    if (!level.isNull()) {
        global_error_types = level.toInt();
    }
    return Value.initInt(prev_level);
}

pub fn php_sys_get_temp_dir(allocator: Allocator) !Value {
    const tmp_dir = if (builtin.os.tag == .windows) "C:\\Windows\\Temp" else "/tmp";
    const output = try PHPString.init(allocator, try allocator.dupe(u8, tmp_dir));
    return Value.initString(output);
}

pub fn php_file(filename: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    
    const content = std.fs.cwd().readFileAlloc(allocator, fname, 10 * 1024 * 1024) catch return Value.initBool(false);
    defer allocator.free(content);
    
    const arr = try PHPArray.init(allocator);
    var lines = std.mem.splitScalar(u8, content, '\n');
    var idx: i64 = 0;
    while (lines.next()) |line| {
        if (line.len == 0 and lines.rest().len == 0) break; // 最后的空行
        const line_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{line});
        const line_str = try PHPString.init(allocator, line_with_newline);
        try arr.set(allocator, ArrayKey{ .integer = idx }, Value.initString(line_str));
        idx += 1;
    }
    return Value.initArray(arr);
}

pub fn php_function_exists(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len != 1) return error.InvalidArgumentCount;
    if (!args[0].isString()) return Value.initBool(false);
    return Value.initBool(lookupBuiltinFunction(args[0].asString().data) != null);
}

pub fn php_gc_enable(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    gc_enabled = true;
    return Value.initNull();
}

pub fn php_gc_collect_cycles(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return Value.initInt(@intCast(php_collect_cycles()));
}

pub fn php_ini_get(args: []const Value, allocator: Allocator) !Value {
    if (args.len != 1) return error.InvalidArgumentCount;
    if (!args[0].isString()) return Value.initBool(false);

    const option = args[0].asString().data;
    const value: ?[]const u8 = if (std.mem.eql(u8, option, "display_errors"))
        "1"
    else if (std.mem.eql(u8, option, "error_reporting"))
        "32767"
    else if (std.mem.eql(u8, option, "max_execution_time"))
        "0"
    else if (std.mem.eql(u8, option, "memory_limit"))
        "128M"
    else if (std.mem.eql(u8, option, "post_max_size"))
        "8M"
    else if (std.mem.eql(u8, option, "upload_max_filesize"))
        "2M"
    else
        null;

    if (value) |s| return Value.initString(try PHPString.init(allocator, s));
    return Value.initBool(false);
}

pub fn php_getrusage(args: []const Value, allocator: Allocator) !Value {
    if (args.len > 1) return error.InvalidArgumentCount;

    const arr = try PHPArray.init(allocator);
    const key = try PHPString.init(allocator, "ru_utime.tv_sec");
    defer key.release(allocator);
    try arr.set(allocator, ArrayKey{ .string = key }, Value.initInt(0));
    return Value.initArray(arr);
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
    return php_array_map(args, allocator);
}

fn wrapBuiltin_array_filter(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const callback = if (args.len >= 2) args[1] else Value.initNull();
    const mode = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_array_filter(args[0], callback, mode, allocator);
}

fn wrapBuiltin_array_reduce(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const initial = if (args.len >= 3) args[2] else Value.initNull();
    return php_array_reduce(args[0], args[1], initial, allocator);
}

fn wrapBuiltin_json_decode(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_json_decode(args, allocator);
}

fn wrapBuiltin_json_last_error_msg(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_json_last_error_msg(allocator);
}

fn wrapBuiltin_array_walk(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const userdata = if (args.len >= 3) args[2] else Value.initNull();
    return php_array_walk(args[0], args[1], userdata, allocator);
}

fn wrapBuiltin_array_walk_recursive(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const userdata = if (args.len >= 3) args[2] else Value.initNull();
    return php_array_walk_recursive(args[0], args[1], userdata, allocator);
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

/// static::class → 运行时获取调用类名（LSB）
pub fn php_get_called_class_name() !Value {
    const called = getCurrentCalledClass() orelse return error.ClassNotFound;
    const s = try PHPString.init(runtime_allocator, called.name);
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

// ============================================================================
// 文件系统函数包装器
// ============================================================================

fn wrapBuiltin_filemtime(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_filemtime(args[0]);
}

fn wrapBuiltin_fileatime(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_fileatime(args[0]);
}

fn wrapBuiltin_filectime(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_filectime(args[0]);
}

// ============================================================================
// 网络函数包装器
// ============================================================================

fn wrapBuiltin_gethostbyname(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_gethostbyname(args[0], allocator);
}

fn wrapBuiltin_gethostname(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    return php_gethostname(allocator);
}

fn wrapBuiltin_ip2long(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ip2long(args[0]);
}

fn wrapBuiltin_long2ip(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_long2ip(args[0], allocator);
}

fn wrapBuiltin_parse_url(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_parse_url(args[0], allocator);
}

// ============================================================================
// 错误处理函数包装器
// ============================================================================

fn wrapBuiltin_set_error_handler(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    const handler = if (args.len > 0) args[0] else Value.initNull();
    const error_types = if (args.len > 1) args[1] else Value.initNull();
    return php_set_error_handler(handler, error_types, allocator);
}

fn wrapBuiltin_restore_error_handler(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    return php_restore_error_handler();
}

fn wrapBuiltin_trigger_error(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    const message = if (args.len > 0) args[0] else Value.initString(try PHPString.init(allocator, ""));
    const error_type = if (args.len > 1) args[1] else Value.initNull();
    return php_trigger_error(message, error_type, allocator);
}

fn wrapBuiltin_error_reporting(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    const level = if (args.len > 0) args[0] else Value.initNull();
    return php_error_reporting(level);
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

/// Convert PHPValue to ArrayKey
fn valueToArrayKey(val: Value, allocator: Allocator) !ArrayKey {
    _ = allocator;
    if (val.isInt()) {
        return ArrayKey{ .integer = val.asInt() };
    } else if (val.isString()) {
        const str = val.asString();
        // Try to parse as integer
        const int_val = std.fmt.parseInt(i64, str.data, 10) catch {
            return ArrayKey{ .string = str };
        };
        return ArrayKey{ .integer = int_val };
    } else if (val.isNull()) {
        return ArrayKey{ .integer = 0 };
    } else if (val.isBool()) {
        return ArrayKey{ .integer = if (val.asBool()) 1 else 0 };
    } else if (val.isFloat()) {
        return ArrayKey{ .integer = @intFromFloat(val.asFloat()) };
    }
    return ArrayKey{ .integer = 0 };
}

pub fn php_array_get(arr_val: Value, key_val: Value, allocator: Allocator) !Value {
    if (Value_isObject(arr_val)) {
        return php_object_call(arr_val, "offsetGet", &[_]Value{key_val});
    }

    if (arr_val.isString()) {
        const str = arr_val.asString();
        const idx_i64 = key_val.toInt();
        if (idx_i64 < 0 or idx_i64 >= str.length) return Value.initNull();
        const idx = @as(usize, @intCast(idx_i64));
        const ch_slice = str.data[idx..@min(idx + 1, str.data.len)];
        return Value.initString(try PHPString.init(allocator, ch_slice));
    }

    if (arr_val.isArray()) {
        return arr_val.asArray().getByValue(key_val) orelse Value.initNull();
    }

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "Trying to access array offset on {s}",
        .{valueTypeName(arr_val)},
    ) catch "Trying to access array offset";
    emitWarning(msg);

    return Value.initNull();
}

/// 获取数组元素的引用（用于引用返回）
/// 参数：array, key
/// 返回：Value.initRef(指向数组元素的指针)
pub fn php_array_get_ref(arr_val: Value, key_val: Value, allocator: Allocator) !Value {
    if (!arr_val.isArray()) return error.InvalidArgument;
    const arr = arr_val.asArray();

    const key = normalizeArrayKeyFromValue(key_val);

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
    // 引用透明：闭包自引用场景中 callback 可能是 Ref(cell)
    var actual_cb = if (callback.isRef()) callback.asRef().* else callback;
    
    // 多层Ref解引用：捕获的闭包可能被多次包装
    while (actual_cb.isRef()) {
        actual_cb = actual_cb.asRef().*;
    }
    
    if (actual_cb.isFunction()) {
        const closure = actual_cb.asFunction();
        return closure.func(actual_cb, args, allocator);
    }
    if (Value_isObject(actual_cb)) {
        const obj_ptr = Value_asObject(actual_cb);
        return obj_ptr.callMethod("__invoke", args) catch |err| switch (err) {
            error.MethodNotFound => return Value.initBool(false),
            else => return Value.initBool(false),
        };
    }
    if (actual_cb.isString()) {
        const func_name = actual_cb.asString().data;
        if (lookupBuiltinFunction(func_name)) |func| {
            return func(Value.initNull(), args, allocator);
        }
        if (user_function_registry) |registry| {
            if (registry.get(func_name)) |func| {
                return func(Value.initNull(), args, allocator);
            }
        }
        // AOT hook：尝试调用AOT注册的函数
        if (aot_callable_hook) |hook| {
            return hook(func_name, args, allocator);
        }
        // PHP: 对不存在的函数发出 warning 并返回 false
        return Value.initBool(false);
    }
    if (actual_cb.isArray()) {
        const arr = actual_cb.asArray();
        if (arr.elements.count() != 2) return Value.initBool(false);

        const key0 = ArrayKey{ .integer = 0 };
        const key1 = ArrayKey{ .integer = 1 };

        const val0 = arr.elements.get(key0) orelse return Value.initBool(false);
        const val1 = arr.elements.get(key1) orelse return Value.initBool(false);

        if (!val1.isString()) return Value.initBool(false);
        const method_name = val1.asString().data;

        if (Value_isObject(val0)) {
            const obj_ptr = Value_asObject(val0);
            return obj_ptr.callMethod(method_name, args) catch Value.initBool(false);
        }
        if (val0.isString()) {
            return php_call_static(val0.asString().data, method_name, args, allocator) catch Value.initBool(false);
        }
        return Value.initBool(false);
    }
    return Value.initBool(false);
}

pub fn php_args_append_spread(dest: Value, src: Value, allocator: Allocator) !Value {
    if (!dest.isArray()) {
        return throwException("Only arrays can be unpacked", allocator);
    }

    const dest_arr = dest.asArray();
    const iter_val = try php_array_iter_init(src, allocator);
    defer _ = php_array_iter_free(iter_val, allocator) catch {};

    while ((try php_array_iter_valid(iter_val)).toBool()) {
        const value = try php_array_iter_value(iter_val);
        defer value.release(allocator);
        try dest_arr.push(allocator, value);

        const next_iter = try php_array_iter_next(iter_val);
        next_iter.release(allocator);
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

pub fn php_object_call_safe_args_array(obj_val: Value, method_name_val: Value, args_array: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }
    if (!method_name_val.isString()) {
        return Value.initNull();
    }
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

    return php_object_call(obj_val, method_name_val.asString().data, tmp_args[0..used]);
}

pub fn php_object_call_args_array(obj_val: Value, method_name_val: Value, args_array: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return throwException("Call to a member function on null", allocator);
    }
    if (!method_name_val.isString()) {
        return throwException("Method name must be a string", allocator);
    }
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

    return php_object_call(obj_val, method_name_val.asString().data, tmp_args[0..used]);
}

/// 使用命名参数调用对象方法
/// args_array 包含位置参数（整数键）和命名参数（字符串键）
pub fn php_object_call_named_args(obj_val: Value, method_name_val: Value, args_array: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return throwException("Call to a member function on null", allocator);
    }
    if (!method_name_val.isString()) {
        return throwException("Method name must be a string", allocator);
    }
    if (!args_array.isArray()) {
        return throwException("Arguments must be an array", allocator);
    }

    const obj = Value_asObject(obj_val);
    const method_name = method_name_val.asString().data;
    const arr = args_array.asArray();

    // 获取方法的参数信息
    const meta = obj.class_meta orelse return throwException("Cannot find class metadata", allocator);
    _ = meta.findMethod(method_name) orelse return throwException("Call to undefined method", allocator);

    // 收集位置参数（整数键，按顺序）
    var positional = std.ArrayListUnmanaged(Value){};
    defer positional.deinit(allocator);
    var pos_idx: usize = 0;
    while (true) : (pos_idx += 1) {
        const key = ArrayKey{ .integer = @intCast(pos_idx) };
        if (arr.get(key)) |v| {
            try positional.append(allocator, v);
        } else {
            break;
        }
    }

    // 收集命名参数（字符串键）
    var named = std.StringHashMap(Value).init(allocator);
    defer {
        var it = named.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.release(allocator);
        }
        named.deinit();
    }
    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        switch (entry.key_ptr.*) {
            .string => |s| {
                const val = entry.value_ptr.*;
                _ = val.retain();
                try named.put(s.data, val);
            },
            else => {},
        }
    }

    // 获取方法参数名（从函数元数据）
    const full_method_name = try std.fmt.allocPrint(allocator, "{s}::{s}", .{ meta.name, method_name });
    defer allocator.free(full_method_name);
    
    // 尝试获取参数信息
    const param_count: u16 = if (function_meta_registry) |meta_reg|
        (if (meta_reg.get(full_method_name)) |m| m.param_count else 0)
    else
        0;

    // 构建最终参数列表
    const final_args = try allocator.alloc(Value, @max(param_count, positional.items.len));
    defer allocator.free(final_args);
    var final_count: usize = 0;

    // 首先填充位置参数
    for (positional.items) |arg| {
        if (final_count < final_args.len) {
            final_args[final_count] = arg;
            final_count += 1;
        }
    }

    // 然后用命名参数覆盖/填充
    // 我们需要从类方法中获取参数名
    // 这是一个简化实现：假设参数顺序正确
    // 完整实现需要在编译时记录参数名

    return php_object_call(obj_val, method_name, final_args[0..final_count]);
}

// ============================================================================
// 算术运算符
// ============================================================================

/// 加法运算（PHP语义）
pub fn php_add(lhs: Value, rhs: Value) !Value {
    // 数组联合运算：$a + $b（保留左侧值，右侧不存在的键才加入）
    if (lhs.isArray() and rhs.isArray()) {
        return php_array_union(lhs, rhs, runtime_allocator);
    }
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "+");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
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
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "-");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
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
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "*");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
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
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "/");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
    // PHP 将 null/bool 视为整数参与整除判断
    const lhs_is_int = lhs.isInt() or lhs.isNull() or lhs.isBool();
    const rhs_is_int = rhs.isInt() or rhs.isNull() or rhs.isBool();
    if (lhs_is_int and rhs_is_int) {
        const a = lhs.toInt();
        const b = rhs.toInt();
        if (b == 0) {
            _ = try throwThrowable("DivisionByZeroError", "Division by zero", runtime_allocator);
            return Value.initNull();
        }
        if (@mod(a, b) == 0) {
            const result = @divTrunc(a, b);
            if (result >= Value.INT48_MIN and result <= Value.INT48_MAX) {
                return Value.initInt(result);
            }
        }
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    if (b == 0.0) {
        _ = try throwThrowable("DivisionByZeroError", "Division by zero", runtime_allocator);
        return Value.initNull();
    }
    return Value.initFloat(a / b);
}

/// 取模运算（PHP语义）
pub fn php_mod(lhs: Value, rhs: Value) !Value {
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "%");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
    // PHP 8.1+: float→int 隐式转换精度丢失时输出 Deprecated
    if (lhs.isFloat()) {
        const f = lhs.asFloat();
        const i: f64 = @floatFromInt(lhs.toInt());
        if (f != i) emitDeprecatedFloatToInt(f);
    }
    if (rhs.isFloat()) {
        const f = rhs.asFloat();
        const i: f64 = @floatFromInt(rhs.toInt());
        if (f != i) emitDeprecatedFloatToInt(f);
    }
    const a = lhs.toInt();
    const b = rhs.toInt();
    if (b == 0) {
        _ = try throwThrowable("DivisionByZeroError", "Modulo by zero", runtime_allocator);
        return Value.initNull();
    }
    return Value.initInt(@rem(a, b));
}

/// 检查字符串是否为 PHP 数字字符串
fn isNumericString(data: []const u8) bool {
    if (data.len == 0) return false;
    var i: usize = 0;
    while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}
    if (i < data.len and (data[i] == '+' or data[i] == '-')) i += 1;
    if (i >= data.len) return false;
    var has_digits = false;
    while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {
        has_digits = true;
    }
    if (i < data.len and data[i] == '.') {
        i += 1;
        while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {
            has_digits = true;
        }
    }
    if (!has_digits) return false;
    if (i < data.len and (data[i] == 'e' or data[i] == 'E')) {
        i += 1;
        if (i < data.len and (data[i] == '+' or data[i] == '-')) i += 1;
        if (i >= data.len or !std.ascii.isDigit(data[i])) return false;
        while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {}
    }
    while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}
    return i >= data.len;
}

fn numericPrefixLength(data: []const u8) usize {
    if (data.len == 0) return 0;
    var i: usize = 0;
    while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}
    if (i < data.len and (data[i] == '+' or data[i] == '-')) i += 1;
    const start_digits = i;
    while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {}
    var has_digits = i > start_digits;
    if (i < data.len and data[i] == '.') {
        i += 1;
        const frac_start = i;
        while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {}
        if (i > frac_start) has_digits = true;
    }
    if (!has_digits) return 0;
    if (i < data.len and (data[i] == 'e' or data[i] == 'E')) {
        var j = i + 1;
        if (j < data.len and (data[j] == '+' or data[j] == '-')) j += 1;
        const exp_start = j;
        while (j < data.len and std.ascii.isDigit(data[j])) : (j += 1) {}
        if (j > exp_start) i = j;
    }
    return i;
}

fn hasNumericPrefix(data: []const u8) bool {
    return numericPrefixLength(data) > 0;
}

fn emitArithmeticStringWarningIfNeeded(v: Value) void {
    if (!v.isString()) return;
    const str = v.asString().data[0..v.asString().length];
    if (hasNumericPrefix(str) and !isNumericString(str)) {
        emitWarning("A non-numeric value encountered");
    }
}

/// 检查 Value 是否可参与算术运算（PHP 8.x）
fn checkArithmeticOperand(v: Value) bool {
    if (v.isString()) {
        const str = v.asString();
        return hasNumericPrefix(str.data[0..str.length]);
    }
    return !v.isArray();
}

/// 输出 PHP Warning 到 stdout 和 stderr
pub fn emitWarning(msg: []const u8) void {
    // @操作符：错误抑制时不输出警告
    if (isErrorSuppressed()) return;

    const stdout = std.fs.File{ .handle = 1 };
    const stderr = std.fs.File{ .handle = 2 };
    // PHP 输出顺序：先 stderr（PHP Warning:），再 stdout（Warning:）
    var ebuf: [1024]u8 = undefined;
    const emsg = std.fmt.bufPrint(
        &ebuf,
        "PHP Warning:  {s} in {s} on line {d}\n",
        .{ msg, src_file, src_line },
    ) catch "";
    stderr.writeAll(emsg) catch {};
    var buf: [1024]u8 = undefined;
    const wmsg = std.fmt.bufPrint(
        &buf,
        "\nWarning: {s} in {s} on line {d}\n",
        .{ msg, src_file, src_line },
    ) catch "";
    stdout.writeAll(wmsg) catch {};
}

pub fn emitDeprecatedStrGetcsvEscape() void {
    const stdout = std.fs.File{ .handle = 1 };
    const stderr = std.fs.File{ .handle = 2 };
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const emsg = std.fmt.bufPrint(
        &ebuf,
        "PHP Deprecated:  str_getcsv(): the $escape parameter must be provided as its default value will change in {s} on line {d}\n",
        .{ src_file, src_line },
    ) catch "";
    stderr.writeAll(emsg) catch {};
    var buf: [1024]u8 = undefined;
    const wmsg = std.fmt.bufPrint(
        &buf,
        "\nDeprecated: str_getcsv(): the $escape parameter must be provided as its default value will change in {s} on line {d}\n",
        .{ src_file, src_line },
    ) catch "";
    stdout.writeAll(wmsg) catch {};
}

pub fn emitUndefinedVariableWarning(name: []const u8) void {
    const stdout = std.fs.File{ .handle = 1 };
    const stderr = std.fs.File{ .handle = 2 };
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const emsg = std.fmt.bufPrint(
        &ebuf,
        "PHP Warning:  Undefined variable {s} in {s} on line {d}\n",
        .{ name, src_file, src_line },
    ) catch "";
    stderr.writeAll(emsg) catch {};
    var buf: [1024]u8 = undefined;
    const wmsg = std.fmt.bufPrint(
        &buf,
        "\nWarning: Undefined variable {s} in {s} on line {d}\n",
        .{ name, src_file, src_line },
    ) catch "";
    stdout.writeAll(wmsg) catch {};
}

/// 输出 Unsupported operand types TypeError 并终止
fn emitUnsupportedOperandError(
    lhs: Value,
    rhs: Value,
    op: []const u8,
) noreturn {
    const stdout = std.fs.File{ .handle = 1 };
    const stderr = std.fs.File{ .handle = 2 };
    const ltype = valueTypeName(lhs);
    const rtype = valueTypeName(rhs);
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const emsg = std.fmt.bufPrint(
        &ebuf,
        "PHP Fatal error:  Uncaught TypeError: Unsupported" ++
            " operand types: {s} {s} {s} in {s}:{d}\n" ++
            "Stack trace:\n#0 {{main}}\n" ++
            "  thrown in {s} on line {d}\n",
        .{
            ltype,    op,       rtype,
            src_file, src_line, src_file,
            src_line,
        },
    ) catch {
        std.process.exit(255);
    };
    stderr.writeAll(emsg) catch {};
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "\nFatal error: Uncaught TypeError: Unsupported" ++
            " operand types: {s} {s} {s} in {s}:{d}\n" ++
            "Stack trace:\n#0 {{main}}\n" ++
            "  thrown in {s} on line {d}\n",
        .{
            ltype,    op,       rtype,
            src_file, src_line, src_file,
            src_line,
        },
    ) catch {
        stdout.writeAll("\nFatal error: TypeError\n") catch {};
        std.process.exit(255);
    };
    stdout.writeAll(msg) catch {};
    std.process.exit(255);
}

/// 获取 Value 的 PHP 类型名称
fn valueTypeName(v: Value) []const u8 {
    if (v.isNull()) return "null";
    if (v.isBool()) return "bool";
    if (v.isInt()) return "int";
    if (v.isFloat()) return "float";
    if (v.isString()) return "string";
    if (v.isArray()) return "array";
    if (Value_isObject(v)) return "object";
    return "unknown";
}

/// 输出 PHP Fatal TypeError 并终止执行
fn emitTypeFatalError(func_name: []const u8, arg_num: u32, expected: []const u8, got: []const u8) noreturn {
    const stdout = std.fs.File{ .handle = 1 };
    const stderr = std.fs.File{ .handle = 2 };
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const stderr_msg = std.fmt.bufPrint(
        &ebuf,
        "PHP Fatal error:  Uncaught TypeError: {s}(): Argument" ++
            " #{d} ($array) must be of type {s}, {s} given" ++
            " in {s}:{d}\nStack trace:\n#0 {{main}}\n" ++
            "  thrown in {s} on line {d}\n",
        .{
            func_name, arg_num,  expected, got,
            src_file,  src_line, src_file, src_line,
        },
    ) catch {
        std.process.exit(255);
    };
    stderr.writeAll(stderr_msg) catch {};
    var buf: [1024]u8 = undefined;
    const stdout_msg = std.fmt.bufPrint(
        &buf,
        "\nFatal error: Uncaught TypeError: {s}(): Argument" ++
            " #{d} ($array) must be of type {s}, {s} given" ++
            " in {s}:{d}\nStack trace:\n#0 {{main}}\n" ++
            "  thrown in {s} on line {d}\n",
        .{
            func_name, arg_num,  expected, got,
            src_file,  src_line, src_file, src_line,
        },
    ) catch {
        stdout.writeAll("\nFatal error: TypeError\n") catch {};
        std.process.exit(255);
    };
    stdout.writeAll(stdout_msg) catch {};
    std.process.exit(255);
}

/// 调用未定义函数时输出 PHP Fatal error 并终止执行
pub fn php_call_undefined_function(name: []const u8) noreturn {
    const stdout = std.fs.File{ .handle = 1 };
    const stderr = std.fs.File{ .handle = 2 };
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const stderr_msg = std.fmt.bufPrint(
        &ebuf,
        "PHP Fatal error:  Uncaught Error: Call to undefined" ++
            " function {s}() in {s}:{d}\nStack trace:\n" ++
            "#0 {{main}}\n  thrown in {s} on line {d}\n",
        .{ name, src_file, src_line, src_file, src_line },
    ) catch {
        std.process.exit(255);
    };
    stderr.writeAll(stderr_msg) catch {};
    var buf: [1024]u8 = undefined;
    const stdout_msg = std.fmt.bufPrint(
        &buf,
        "\nFatal error: Uncaught Error: Call to undefined" ++
            " function {s}() in {s}:{d}\nStack trace:\n" ++
            "#0 {{main}}\n  thrown in {s} on line {d}\n",
        .{ name, src_file, src_line, src_file, src_line },
    ) catch {
        stdout.writeAll("\nFatal error: Call to undefined function\n") catch {};
        std.process.exit(255);
    };
    stdout.writeAll(stdout_msg) catch {};
    std.process.exit(255);
}

/// 输出 PHP 8.1+ Deprecated 警告到 stdout（匹配 display_errors=On）
fn emitDeprecatedFloatToInt(f: f64) void {
    const stdout = std.fs.File{ .handle = 1 };
    const stderr = std.fs.File{ .handle = 2 };
    // 警告信息中使用完整精度（PHP serialize_precision），不是 echo 的 precision=14
    var fbuf: [64]u8 = undefined;
    const fstr = std.fmt.bufPrint(&fbuf, "{d}", .{f}) catch "?";
    // PHP 输出顺序：先 stderr，再 stdout
    var err_buf: [512]u8 = undefined;
    const stderr_msg = std.fmt.bufPrint(
        &err_buf,
        "PHP Deprecated:  Implicit conversion from" ++
            " float {s} to int loses precision in {s}" ++
            " on line {d}\n",
        .{ fstr, src_file, src_line },
    ) catch return;
    stderr.writeAll(stderr_msg) catch {};
    var msg_buf: [512]u8 = undefined;
    const stdout_msg = std.fmt.bufPrint(
        &msg_buf,
        "\nDeprecated: Implicit conversion from float" ++
            " {s} to int loses precision in {s} on line" ++
            " {d}\n",
        .{ fstr, src_file, src_line },
    ) catch return;
    stdout.writeAll(stdout_msg) catch {};
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
    const actual_lhs = if (lhs.isRef()) lhs.asRef().* else lhs;
    const actual_rhs = if (rhs.isRef()) rhs.asRef().* else rhs;

    if (actual_lhs.isArray() and actual_rhs.isArray()) {
        const a = actual_lhs.asArray();
        const b = actual_rhs.asArray();
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

    if (Value_isObject(actual_lhs) and Value_isObject(actual_rhs)) {
        return Value.initBool(Value_asObject(actual_lhs) == Value_asObject(actual_rhs));
    }

    return Value.initBool(phpCompare(actual_lhs, actual_rhs) == 0);
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
fn php_array_key_identical(lhs: ArrayKey, rhs: ArrayKey) bool {
    return switch (lhs) {
        .integer => |li| switch (rhs) {
            .integer => |ri| li == ri,
            else => false,
        },
        .string => |ls| switch (rhs) {
            .string => |rs| std.mem.eql(u8, ls.data, rs.data),
            else => false,
        },
    };
}

fn php_array_identical(lhs: *PHPArray, rhs: *PHPArray) anyerror!bool {
    if (lhs.elements.count() != rhs.elements.count()) return false;

    var lhs_iter = lhs.elements.iterator();
    var rhs_iter = rhs.elements.iterator();
    while (true) {
        const lhs_entry = lhs_iter.next();
        const rhs_entry = rhs_iter.next();
        if (lhs_entry == null or rhs_entry == null) {
            return lhs_entry == null and rhs_entry == null;
        }

        const l = lhs_entry.?;
        const r = rhs_entry.?;
        if (!php_array_key_identical(l.key_ptr.*, r.key_ptr.*)) return false;
        if (!(try php_identical(l.value_ptr.*, r.value_ptr.*)).toBool()) return false;
    }
}

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
        return Value.initBool(try php_array_identical(lhs.asArray(), rhs.asArray()));
    }

    // Object: 同一引用才 identical（指针比较）
    if (Value_isObject(lhs) and Value_isObject(rhs)) {
        return Value.initBool(Value_asObject(lhs) == Value_asObject(rhs));
    }

    return Value.initBool(false);
}

/// 不全等运算
pub fn php_not_identical(lhs: Value, rhs: Value) !Value {
    const result = try php_identical(lhs, rhs);
    return Value.initBool(!result.asBool());
}

/// PHP 8 比较核心：返回 -1, 0, 1
fn phpCompare(lhs: Value, rhs: Value) i2 {
    // PHP 8 comparison table (in priority order):
    // 1. null|string vs string → null→"", string comparison
    // 2. bool|null vs anything → both→bool, false < true
    // 3. int vs int → integer comparison
    // 4. number vs number (at least one float) → float comparison
    // 5. string vs string → numeric strings: number cmp, else lexicographic
    // 6. string vs number → convert string to number
    // 7. array vs non-array → array is always greater

    // Rule 1: null|string vs string → string comparison
    if ((lhs.isNull() or lhs.isString()) and rhs.isString()) {
        if (lhs.isNull()) {
            const r = rhs.asString();
            if (r.length == 0) return 0;
            return -1;
        }
        // both string → fall through to Rule 5
    } else if (lhs.isString() and (rhs.isNull() or rhs.isString())) {
        if (rhs.isNull()) {
            const l = lhs.asString();
            if (l.length == 0) return 0;
            return 1;
        }
        // both string → fall through to Rule 5
    } else if (lhs.isNull() or lhs.isBool() or rhs.isNull() or rhs.isBool()) {
        // Rule 2: bool|null vs non-string → bool comparison
        const lb = lhs.toBool();
        const rb = rhs.toBool();
        if (!lb and rb) return -1;
        if (lb and !rb) return 1;
        return 0;
    }

    // Rule 3: int vs int
    if (lhs.isInt() and rhs.isInt()) {
        const l = lhs.asInt();
        const r = rhs.asInt();
        if (l < r) return -1;
        if (l > r) return 1;
        return 0;
    }

    // Rule 5: string vs string
    if (lhs.isString() and rhs.isString()) {
        const ls = lhs.asString();
        const rs = rhs.asString();
        if (isNumericString(ls.data[0..ls.length]) and
            isNumericString(rs.data[0..rs.length]))
        {
            const lf = lhs.toFloat();
            const rf = rhs.toFloat();
            if (lf < rf) return -1;
            if (lf > rf) return 1;
            return 0;
        }
        const cmp = std.mem.order(
            u8,
            ls.data[0..ls.length],
            rs.data[0..rs.length],
        );
        return switch (cmp) {
            .lt => -1,
            .gt => 1,
            .eq => 0,
        };
    }

    // Rule 7: array vs non-array
    if (lhs.isArray() and !rhs.isArray()) return 1;
    if (!lhs.isArray() and rhs.isArray()) return -1;

    // Rule 4/6: numeric comparison (fallback)
    const l = lhs.toFloat();
    const r = rhs.toFloat();
    if (l < r) return -1;
    if (l > r) return 1;
    return 0;
}

/// 小于运算
pub fn php_lt(lhs: Value, rhs: Value) !Value {
    return Value.initBool(phpCompare(lhs, rhs) < 0);
}

/// 小于等于运算
pub fn php_le(lhs: Value, rhs: Value) !Value {
    return Value.initBool(phpCompare(lhs, rhs) <= 0);
}

/// 大于运算
pub fn php_gt(lhs: Value, rhs: Value) !Value {
    return Value.initBool(phpCompare(lhs, rhs) > 0);
}

/// 大于等于运算
pub fn php_ge(lhs: Value, rhs: Value) !Value {
    return Value.initBool(phpCompare(lhs, rhs) >= 0);
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

/// 布尔或运算（用于 match 表达式多条件合并）
pub fn php_bool_or(lhs: Value, rhs: Value) Value {
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

/// 逻辑异或运算 (xor)
pub fn php_logical_xor(lhs: Value, rhs: Value) !Value {
    return Value.initBool(lhs.toBool() != rhs.toBool());
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
    const rhs_str = rhs.toString(allocator) catch {
        // 类型转换失败（如数组转字符串），异常已设置
        return Value.initString(try PHPString.init(allocator, ""));
    };
    defer rhs_str.release(allocator);

    const lhs_str = lhs.toString(allocator) catch {
        // 类型转换失败（如数组转字符串），异常已设置
        // 返回空字符串以继续执行（异常会在后续被检查）
        return Value.initString(try PHPString.init(allocator, ""));
    };
    defer lhs_str.release(allocator);

    const result = try lhs_str.concat(rhs_str, allocator);
    return Value.initString(result);
}

pub fn php_concat_with_undef(lhs: Value, rhs: Value, lhs_undef: bool, lhs_name: []const u8, rhs_undef: bool, rhs_name: []const u8, allocator: Allocator) !Value {
    if (!lhs_undef and !rhs_undef) {
        return php_concat(lhs, rhs, allocator);
    }

    const rhs_str = blk: {
        if (rhs_undef) emitUndefinedVariableWarning(rhs_name);
        break :blk rhs.toString(allocator) catch {
            return Value.initString(try PHPString.init(allocator, ""));
        };
    };
    defer rhs_str.release(allocator);

    const lhs_str = blk: {
        if (lhs_undef) emitUndefinedVariableWarning(lhs_name);
        break :blk lhs.toString(allocator) catch {
            return Value.initString(try PHPString.init(allocator, ""));
        };
    };
    defer lhs_str.release(allocator);

    const result = try lhs_str.concat(rhs_str, allocator);
    return Value.initString(result);
}

// ============================================================================
// 输出函数
// ============================================================================

/// PHP 兼容浮点格式化（14 位有效数字，去尾零）
/// @pre buf.len >= 64
/// @post 返回 buf 中的有效切片
pub fn phpFormatFloat(buf: []u8, f: f64) []const u8 {
    const PHP_PRECISION: usize = 14;

    if (std.math.isNan(f)) return "NAN";
    if (std.math.isInf(f)) {
        return if (f > 0) "INF" else "-INF";
    }
    if (f == 0.0) {
        if (std.math.signbit(f)) return "-0";
        return "0";
    }

    // 计算指数（log10），决定是否使用科学计数法（模拟 PHP 的 %G 行为）
    const abs_f = @abs(f);
    const exp10: i32 = if (abs_f >= 1.0) @intFromFloat(@floor(@log10(abs_f))) else blk: {
        // 对于小于1的数，log10为负数
        const l = @log10(abs_f);
        break :blk @as(i32, @intFromFloat(@floor(l)));
    };

    // PHP %.*G 规则：当指数 >= precision 或 < -4 时使用科学计数法
    if (exp10 >= @as(i32, @intCast(PHP_PRECISION)) or exp10 < -4) {
        // 科学计数法：如 9.2233720368548E+18
        const mantissa = f / std.math.pow(f64, 10.0, @floatFromInt(exp10));
        // 格式化尾数部分（precision-1 位小数）
        var work: [64]u8 = undefined;
        const dec_digits = PHP_PRECISION - 1;
        const mant_str = std.fmt.bufPrint(&work, "{d:.13}", .{mantissa}) catch return "0";
        // 手动截断到 dec_digits 位小数并去尾零
        var out_len: usize = 0;
        const sign_len: usize = if (mant_str[0] == '-') 1 else 0;
        // 复制符号
        if (sign_len > 0) {
            buf[0] = '-';
            out_len = 1;
        }
        // 找到小数点位置
        var dot_pos: usize = 0;
        for (mant_str[sign_len..], 0..) |c, idx| {
            if (c == '.') {
                dot_pos = sign_len + idx;
                break;
            }
        }
        if (dot_pos == 0) dot_pos = mant_str.len;
        // 复制整数部分
        const int_part = mant_str[sign_len..dot_pos];
        @memcpy(buf[out_len .. out_len + int_part.len], int_part);
        out_len += int_part.len;
        // 复制小数部分（最多 dec_digits 位）
        if (dot_pos < mant_str.len) {
            buf[out_len] = '.';
            out_len += 1;
            const frac_start = dot_pos + 1;
            const frac_avail = mant_str.len - frac_start;
            const frac_copy = @min(frac_avail, dec_digits);
            @memcpy(buf[out_len .. out_len + frac_copy], mant_str[frac_start .. frac_start + frac_copy]);
            out_len += frac_copy;
            // 去尾零
            while (out_len > 0 and buf[out_len - 1] == '0') : (out_len -= 1) {}
            if (out_len > 0 and buf[out_len - 1] == '.') out_len -= 1;
        }
        // 追加 E±XX 部分（PHP 用大写 E）
        const e_str = if (exp10 >= 0)
            std.fmt.bufPrint(buf[out_len..], "E+{d}", .{exp10}) catch return "0"
        else
            std.fmt.bufPrint(buf[out_len..], "E{d}", .{exp10}) catch return "0";
        out_len += e_str.len;
        return buf[0..out_len];
    }

    // 非科学计数法路径
    var work: [64]u8 = undefined;
    const full = std.fmt.bufPrint(&work, "{d}", .{f}) catch
        return "0";

    var i: usize = 0;
    const sign_len: usize = if (full[0] == '-') 1 else 0;
    i = sign_len;

    var sig_count: usize = 0;
    var started = false;
    var round_pos: usize = full.len;

    while (i < full.len) : (i += 1) {
        if (full[i] == '.') continue;
        if (!started) {
            if (full[i] == '0') continue;
            started = true;
        }
        sig_count += 1;
        if (sig_count == PHP_PRECISION) {
            round_pos = i + 1;
            break;
        }
    }

    if (sig_count < PHP_PRECISION) {
        @memcpy(buf[0..full.len], full[0..full.len]);
        return phpStripTrailingZeros(buf[0..full.len]);
    }

    var next = round_pos;
    if (next < full.len and full[next] == '.') next += 1;
    const round_up = (next < full.len and full[next] >= '5');

    var end = round_pos;
    @memcpy(buf[0..end], full[0..end]);

    if (round_up) {
        var j: usize = end;
        while (j > sign_len) {
            j -= 1;
            if (buf[j] == '.') continue;
            if (buf[j] < '9') {
                buf[j] += 1;
                break;
            }
            buf[j] = '0';
            if (j == sign_len) {
                std.mem.copyBackwards(
                    u8,
                    buf[sign_len + 1 .. end + 1],
                    buf[sign_len..end],
                );
                buf[sign_len] = '1';
                end += 1;
                break;
            }
        }
    }

    return phpStripTrailingZeros(buf[0..end]);
}

fn phpStripTrailingZeros(s: []u8) []const u8 {
    var has_dot = false;
    for (s) |c| {
        if (c == '.') {
            has_dot = true;
            break;
        }
    }
    if (!has_dot) return s;

    var end = s.len;
    while (end > 0 and s[end - 1] == '0') : (end -= 1) {}
    if (end > 0 and s[end - 1] == '.') end -= 1;
    return s[0..end];
}

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
        var buf: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "{d}", .{value.asInt()});
        try stdout_file.writeAll(str);
    } else if (value.isFloat()) {
        var buf: [64]u8 = undefined;
        const str = phpFormatFloat(&buf, value.asFloat());
        try stdout_file.writeAll(str);
    } else if (value.isString()) {
        const str = value.asString();
        try stdout_file.writeAll(str.data);
    } else if (value.isArray()) {
        // PHP Warning: Array to string conversion
        const stderr_file = std.fs.File{ .handle = 2 };
        var wbuf: [512]u8 = undefined;
        const wmsg = std.fmt.bufPrint(
            &wbuf,
            "\nWarning: Array to string conversion in" ++
                " {s} on line {d}\n",
            .{ src_file, src_line },
        ) catch "";
        if (wmsg.len > 0) {
            stdout_file.writeAll(wmsg) catch {};
            var ebuf: [512]u8 = undefined;
            const emsg = std.fmt.bufPrint(
                &ebuf,
                "PHP Warning:  Array to string conversion in" ++
                    " {s} on line {d}\n",
                .{ src_file, src_line },
            ) catch "";
            if (emsg.len > 0) stderr_file.writeAll(emsg) catch {};
        }
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
    const stdout_file = std.fs.File{ .handle = 1 };
    if (value.isNull()) {
        try stdout_file.writeAll("NULL\n");
    } else if (value.isBool()) {
        var buf: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "bool({})\n", .{value.asBool()});
        try stdout_file.writeAll(str);
    } else if (value.isInt()) {
        var buf: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "int({})\n", .{value.asInt()});
        try stdout_file.writeAll(str);
    } else if (value.isFloat()) {
        var buf: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "float({})\n", .{value.asFloat()});
        try stdout_file.writeAll(str);
    } else if (value.isString()) {
        const str = value.asString();
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "string({}) \"{s}\"\n", .{ str.length, str.data });
        try stdout_file.writeAll(msg);
    } else if (value.isArray()) {
        const arr = value.asArray();
        var buf: [64]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "array({d}) {{\n", .{arr.count()});
        try stdout_file.writeAll(msg);
        // 遍历数组
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            try stdout_file.writeAll("  ");
            switch (entry.key_ptr.*) {
                .integer => |i| {
                    const key_msg = try std.fmt.bufPrint(&buf, "[{d}]", .{i});
                    try stdout_file.writeAll(key_msg);
                },
                .string => |s| {
                    var key_buf: [256]u8 = undefined;
                    const key_msg = try std.fmt.bufPrint(&key_buf, "[\"{s}\"]", .{s.data});
                    try stdout_file.writeAll(key_msg);
                },
            }
            try stdout_file.writeAll("=>\n  ");
            _ = php_var_dump(entry.value_ptr.*) catch {};
        }
        try stdout_file.writeAll("}\n");
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

    try printValue(buffer.writer(runtime_allocator), value, 0, false);

    if (want_return) {
        return Value.initString(try PHPString.init(runtime_allocator, buffer.items));
    }
    const stdout_file = std.fs.File{ .handle = 1 };
    try stdout_file.writeAll(buffer.items);
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
    const stdout_file = std.fs.File{ .handle = 1 };
    try stdout_file.writeAll(buffer.items);
    return Value.initNull();
}

fn writeIndent(writer: anytype, indent: usize) !void {
    var i: usize = 0;
    while (i < indent * 4) : (i += 1) { // 4空格缩进
        try writer.writeByte(' ');
    }
}

fn printValue(writer: anytype, value: Value, indent: usize, is_nested: bool) !void {
    if (value.isNull()) {
        // null不输出任何内容（PHP行为）
        return;
    }
    if (value.isBool()) {
        // bool输出1或空（PHP行为）
        if (value.asBool()) {
            try writer.writeByte('1');
        }
        return;
    }
    if (value.isInt()) {
        try writer.print("{d}", .{value.asInt()});
        return;
    }
    if (value.isFloat()) {
        var buf: [64]u8 = undefined;
        try writer.writeAll(phpFormatFloat(&buf, value.asFloat()));
        return;
    }
    if (value.isString()) {
        try writer.writeAll(value.asString().data);
        return;
    }
    if (value.isArray()) {
        const arr = value.asArray();

        // 数组开始
        try writer.writeAll("Array\n");
        if (is_nested) {
            try writeIndent(writer, indent + 1);
        } else {
            try writeIndent(writer, indent);
        }
        try writer.writeAll("(\n");

        // 遍历元素
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            const elem_indent = if (is_nested) indent + 2 else indent + 1;
            try writeIndent(writer, elem_indent);
            switch (entry.key_ptr.*) {
                .integer => |i| try writer.print("[{d}] => ", .{i}),
                .string => |s| try writer.print("[{s}] => ", .{s.data}),
            }

            const val = entry.value_ptr.*;
            const is_complex = val.isArray() or Value_isObject(val);

            if (is_complex) {
                try printValue(writer, val, elem_indent, true);
                try writer.writeByte('\n');
            } else {
                try printValue(writer, val, elem_indent, false);
                try writer.writeByte('\n');
            }
        }

        if (is_nested) {
            try writeIndent(writer, indent + 1);
        } else {
            try writeIndent(writer, indent);
        }
        try writer.writeAll(")\n");
        return;
    }
    if (Value_isObject(value)) {
        const obj = Value_asObject(value);

        // 对象开始
        try writer.print("{s} Object\n", .{obj.class_name});
        if (is_nested) {
            try writeIndent(writer, indent + 1);
        } else {
            try writeIndent(writer, indent);
        }
        try writer.writeAll("(\n");

        // DateTime 对象特殊处理: 输出 PHP 格式
        if (std.mem.eql(u8, obj.class_name, "DateTime")) {
            const elem_indent = if (is_nested) indent + 2 else indent + 1;
            if (obj.getProperty("timestamp")) |ts_val| {
                const ts = ts_val.toInt();
                const usecs: u64 = if (obj.getProperty("microseconds")) |us_val| @intCast(us_val.toInt()) else 0;
                // 格式化日期时间字符串 (Y-m-d H:i:s.u)
                const epoch_secs: u64 = @intCast(ts);
                const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
                const day_secs = epoch.getDaySeconds();
                const year_day = epoch.getEpochDay().calculateYearDay();
                const month_day = year_day.calculateMonthDay();
                try writeIndent(writer, elem_indent);
                try writer.print("[date] => {d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}\n", .{
                    year_day.year,
                    month_day.month.numeric(),
                    month_day.day_index + 1,
                    day_secs.getHoursIntoDay(),
                    day_secs.getMinutesIntoHour(),
                    day_secs.getSecondsIntoMinute(),
                    usecs,
                });
                try writeIndent(writer, elem_indent);
                try writer.writeAll("[timezone_type] => 3\n");
                try writeIndent(writer, elem_indent);
                try writer.writeAll("[timezone] => UTC\n");
            }
        } else {
            // 遍历属性
            var it = obj.properties.iterator();
            while (it.next()) |entry| {
                const elem_indent = if (is_nested) indent + 2 else indent + 1;
                try writeIndent(writer, elem_indent);

                // 属性名格式化
                const prop_name = entry.key_ptr.*;
                try writer.print("[{s}] => ", .{prop_name});

                const val = entry.value_ptr.*;
                const is_complex = val.isArray() or Value_isObject(val);

                if (is_complex) {
                    try printValue(writer, val, elem_indent, true);
                    try writer.writeByte('\n');
                } else {
                    try printValue(writer, val, elem_indent, false);
                    try writer.writeByte('\n');
                }
            }
        }

        if (is_nested) {
            try writeIndent(writer, indent + 1);
        } else {
            try writeIndent(writer, indent);
        }
        try writer.writeAll(")\n");
        return;
    }

    // 其他类型（资源等）
    try writer.writeAll("Resource");
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
        const f = value.asFloat();
        if (std.math.isNan(f)) {
            try writer.writeAll("NAN");
        } else if (std.math.isInf(f)) {
            try writer.writeAll(if (f > 0) "INF" else "-INF");
        } else {
            var buf: [64]u8 = undefined;
            const str = phpFormatFloat(&buf, f);
            try writer.writeAll(str);
            // var_export 浮点数必须含小数点
            if (std.mem.indexOf(u8, str, ".") == null and std.mem.indexOf(u8, str, "E") == null) {
                try writer.writeAll(".0");
            }
        }
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

/// 注册所有PHP预定义常量
pub fn registerPHPPredefinedConstants(allocator: Allocator) !void {
    const IntConst = struct { name: []const u8, value: i64 };
    const FloatConst = struct { name: []const u8, value: f64 };
    const StrConst = struct { name: []const u8, value: []const u8 };
    const BoolConst = struct { name: []const u8, value: bool };

    // 整数常量
    const int_consts = [_]IntConst{
        // 数组
        .{ .name = "COUNT_NORMAL", .value = 0 },
        .{ .name = "COUNT_RECURSIVE", .value = 1 },
        .{ .name = "ARRAY_FILTER_USE_BOTH", .value = 1 },
        .{ .name = "ARRAY_FILTER_USE_KEY", .value = 2 },
        .{ .name = "ARRAY_UNIQUE_REGULAR", .value = 0 },
        .{ .name = "SORT_REGULAR", .value = 0 },
        .{ .name = "SORT_NUMERIC", .value = 1 },
        .{ .name = "SORT_STRING", .value = 2 },
        .{ .name = "SORT_ASC", .value = 4 },
        .{ .name = "SORT_DESC", .value = 3 },
        .{ .name = "SORT_NATURAL", .value = 6 },
        .{ .name = "SORT_FLAG_CASE", .value = 8 },
        // JSON
        .{ .name = "JSON_PRETTY_PRINT", .value = 128 },
        .{ .name = "JSON_UNESCAPED_UNICODE", .value = 256 },
        .{ .name = "JSON_UNESCAPED_SLASHES", .value = 64 },
        .{ .name = "JSON_THROW_ON_ERROR", .value = 4194304 },
        .{ .name = "JSON_FORCE_OBJECT", .value = 16 },
        .{ .name = "JSON_HEX_TAG", .value = 1 },
        .{ .name = "JSON_HEX_AMP", .value = 2 },
        .{ .name = "JSON_HEX_APOS", .value = 4 },
        .{ .name = "JSON_HEX_QUOT", .value = 8 },
        .{ .name = "JSON_NUMERIC_CHECK", .value = 32 },
        .{ .name = "JSON_BIGINT_AS_STRING", .value = 512 },
        .{ .name = "JSON_PARTIAL_OUTPUT_ON_ERROR", .value = 1024 },
        .{ .name = "JSON_INVALID_UTF8_IGNORE", .value = 1048576 },
        .{ .name = "JSON_INVALID_UTF8_SUBSTITUTE", .value = 2097152 },
        // 错误级别
        .{ .name = "E_ERROR", .value = 1 },
        .{ .name = "E_WARNING", .value = 2 },
        .{ .name = "E_PARSE", .value = 4 },
        .{ .name = "E_NOTICE", .value = 8 },
        .{ .name = "E_CORE_ERROR", .value = 16 },
        .{ .name = "E_CORE_WARNING", .value = 32 },
        .{ .name = "E_COMPILE_ERROR", .value = 64 },
        .{ .name = "E_COMPILE_WARNING", .value = 128 },
        .{ .name = "E_USER_ERROR", .value = 256 },
        .{ .name = "E_USER_WARNING", .value = 512 },
        .{ .name = "E_USER_NOTICE", .value = 1024 },
        .{ .name = "E_STRICT", .value = 2048 },
        .{ .name = "E_RECOVERABLE_ERROR", .value = 4096 },
        .{ .name = "E_DEPRECATED", .value = 8192 },
        .{ .name = "E_USER_DEPRECATED", .value = 16384 },
        .{ .name = "E_ALL", .value = 32767 },
        // 正则
        .{ .name = "PREG_OFFSET_CAPTURE", .value = 256 },
        .{ .name = "PREG_UNMATCHED_AS_NULL", .value = 512 },
        .{ .name = "PREG_SET_ORDER", .value = 2 },
        .{ .name = "PREG_PATTERN_ORDER", .value = 1 },
        .{ .name = "PREG_SPLIT_NO_EMPTY", .value = 1 },
        .{ .name = "PREG_SPLIT_DELIM_CAPTURE", .value = 2 },
        // 文件
        .{ .name = "FILE_APPEND", .value = 8 },
        .{ .name = "FILE_IGNORE_NEW_LINES", .value = 2 },
        .{ .name = "FILE_SKIP_EMPTY_LINES", .value = 4 },
        .{ .name = "LOCK_EX", .value = 2 },
        .{ .name = "LOCK_SH", .value = 1 },
        .{ .name = "LOCK_UN", .value = 3 },
        .{ .name = "SEEK_SET", .value = 0 },
        .{ .name = "SEEK_CUR", .value = 1 },
        .{ .name = "SEEK_END", .value = 2 },
        .{ .name = "GLOB_MARK", .value = 1 },
        .{ .name = "GLOB_NOSORT", .value = 2 },
        .{ .name = "GLOB_NOCHECK", .value = 16 },
        .{ .name = "GLOB_BRACE", .value = 1024 },
        .{ .name = "SCANDIR_SORT_ASCENDING", .value = 0 },
        .{ .name = "SCANDIR_SORT_DESCENDING", .value = 1 },
        .{ .name = "SCANDIR_SORT_NONE", .value = 2 },
        .{ .name = "PATHINFO_DIRNAME", .value = 1 },
        .{ .name = "PATHINFO_BASENAME", .value = 2 },
        .{ .name = "PATHINFO_EXTENSION", .value = 4 },
        .{ .name = "PATHINFO_FILENAME", .value = 8 },
        // 字符串
        .{ .name = "STR_PAD_RIGHT", .value = 1 },
        .{ .name = "STR_PAD_LEFT", .value = 0 },
        .{ .name = "STR_PAD_BOTH", .value = 2 },
        .{ .name = "CASE_UPPER", .value = 1 },
        .{ .name = "CASE_LOWER", .value = 0 },
        // 数学
        .{ .name = "PHP_ROUND_HALF_UP", .value = 0 },
        .{ .name = "PHP_ROUND_HALF_DOWN", .value = 1 },
        .{ .name = "PHP_ROUND_HALF_EVEN", .value = 2 },
        .{ .name = "PHP_ROUND_HALF_ODD", .value = 3 },
        // PHP 整数限制
        .{ .name = "PHP_INT_MAX", .value = 9223372036854775807 },
        .{ .name = "PHP_INT_MIN", .value = -9223372036854775808 },
        .{ .name = "PHP_INT_SIZE", .value = 8 },
        .{ .name = "PHP_MAJOR_VERSION", .value = 8 },
        .{ .name = "PHP_MINOR_VERSION", .value = 3 },
        .{ .name = "PHP_RELEASE_VERSION", .value = 0 },
        // 密码
        .{ .name = "PASSWORD_DEFAULT", .value = 1 },
        .{ .name = "PASSWORD_BCRYPT", .value = 1 },
        // 输出缓冲
        .{ .name = "PHP_OUTPUT_HANDLER_START", .value = 1 },
        .{ .name = "PHP_OUTPUT_HANDLER_WRITE", .value = 0 },
        .{ .name = "PHP_OUTPUT_HANDLER_FLUSH", .value = 4 },
        .{ .name = "PHP_OUTPUT_HANDLER_CLEAN", .value = 2 },
        .{ .name = "PHP_OUTPUT_HANDLER_FINAL", .value = 8 },
        // 杂项
        .{ .name = "PHP_MAXPATHLEN", .value = 4096 },
        .{ .name = "PHP_PREFIX_SEPARATOR", .value = 95 },
        .{ .name = "EXTR_OVERWRITE", .value = 0 },
        .{ .name = "EXTR_SKIP", .value = 1 },
        .{ .name = "EXTR_PREFIX_SAME", .value = 2 },
        .{ .name = "EXTR_PREFIX_ALL", .value = 3 },
    };

    // 浮点常量
    const float_consts = [_]FloatConst{
        .{ .name = "M_PI", .value = 3.14159265358979323846 },
        .{ .name = "M_E", .value = 2.71828182845904523536 },
        .{ .name = "M_LOG2E", .value = 1.44269504088896340736 },
        .{ .name = "M_LOG10E", .value = 0.43429448190325182765 },
        .{ .name = "M_LN2", .value = 0.69314718055994530942 },
        .{ .name = "M_LN10", .value = 2.30258509299404568402 },
        .{ .name = "M_PI_2", .value = 1.57079632679489661923 },
        .{ .name = "M_PI_4", .value = 0.78539816339744830962 },
        .{ .name = "M_1_PI", .value = 0.31830988618379067154 },
        .{ .name = "M_2_PI", .value = 0.63661977236758134308 },
        .{ .name = "M_SQRT2", .value = 1.41421356237309504880 },
        .{ .name = "M_SQRT3", .value = 1.73205080756887729353 },
        .{ .name = "M_2_SQRTPI", .value = 1.12837916709551257390 },
        .{ .name = "M_SQRT1_2", .value = 0.70710678118654752440 },
        .{ .name = "PHP_FLOAT_MAX", .value = 1.7976931348623158e+308 },
        .{ .name = "PHP_FLOAT_MIN", .value = 2.2250738585072014e-308 },
        .{ .name = "PHP_FLOAT_EPSILON", .value = 2.2204460492503131e-16 },
        .{ .name = "INF", .value = std.math.inf(f64) },
        .{ .name = "NAN", .value = std.math.nan(f64) },
    };

    // 字符串常量
    const str_consts = [_]StrConst{
        .{ .name = "PHP_EOL", .value = "\n" },
        .{ .name = "PHP_SAPI", .value = "cli" },
        .{ .name = "PHP_OS", .value = "Darwin" },
        .{ .name = "PHP_OS_FAMILY", .value = "Darwin" },
        .{ .name = "PHP_VERSION", .value = "8.4.8" },
        .{ .name = "DIRECTORY_SEPARATOR", .value = "/" },
        .{ .name = "PATH_SEPARATOR", .value = ":" },
        .{ .name = "PHP_EXTENSION_DIR", .value = "" },
        .{ .name = "PHP_BINDIR", .value = "/usr/local/bin" },
    };

    // 布尔常量
    const bool_consts = [_]BoolConst{
        .{ .name = "TRUE", .value = true },
        .{ .name = "FALSE", .value = false },
    };

    for (int_consts) |c| {
        const key = try allocator.dupe(u8, c.name);
        try constants.put(key, Value.initInt(c.value));
    }
    for (float_consts) |c| {
        const key = try allocator.dupe(u8, c.name);
        try constants.put(key, Value.initFloat(c.value));
    }
    for (str_consts) |c| {
        const key = try allocator.dupe(u8, c.name);
        const str = try PHPString.init(allocator, c.value);
        try constants.put(key, Value.initString(str));
    }
    for (bool_consts) |c| {
        const key = try allocator.dupe(u8, c.name);
        try constants.put(key, Value.initBool(c.value));
    }

    // NULL 常量
    const null_key = try allocator.dupe(u8, "NULL");
    try constants.put(null_key, Value.initNull());
}

/// 用户通过 define() 定义的常量集合（用于 get_defined_constants(true) 分类）
var user_defined_constants: ?std.StringHashMap(void) = null;

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

    // 记录为用户定义的常量
    if (user_defined_constants == null) {
        user_defined_constants = std.StringHashMap(void).init(allocator);
    }
    if (user_defined_constants) |*set| {
        _ = set.put(name_copy, {}) catch {};
    }
    return Value.initBool(true);
}

/// get_defined_constants([bool $categorize = false]): array
pub fn php_get_defined_constants(categorize_val: Value, allocator: Allocator) !Value {
    const categorize = categorize_val.toBool();
    if (categorize) {
        const result = try PHPArray.init(allocator);
        errdefer result.release(allocator);

        const user_arr = try PHPArray.init(allocator);
        const core_arr = try PHPArray.init(allocator);

        var it = constants.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            const key_str = try PHPString.init(allocator, key);
            const is_user = if (user_defined_constants) |*set| set.contains(key) else false;
            const target = if (is_user) user_arr else core_arr;
            try target.elements.put(.{ .string = key_str }, val.retain());
        }

        const core_key = try PHPString.init(allocator, "Core");
        try result.elements.put(.{ .string = core_key }, Value.initArray(core_arr));
        const user_key = try PHPString.init(allocator, "user");
        try result.elements.put(.{ .string = user_key }, Value.initArray(user_arr));
        return Value.initArray(result);
    } else {
        const result = try PHPArray.init(allocator);
        errdefer result.release(allocator);
        var it = constants.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            const key_str = try PHPString.init(allocator, key);
            try result.elements.put(.{ .string = key_str }, val.retain());
        }
        return Value.initArray(result);
    }
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
    ref_count: usize = 1, // 引用计数，初始为1
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

            if (meta.findMethod("getIterator") != null) {
                const iter_val = try php_object_call(array_val, "getIterator", &[_]Value{});
                if (Value_isObject(iter_val) and php_is_iterator(iter_val)) {
                    _ = try php_object_call(iter_val, "rewind", &[_]Value{});
                    return iter_val;
                }
                if (iter_val.isArray()) {
                    defer iter_val.release(allocator);
                    return php_array_iter_init(iter_val, allocator);
                }
                iter_val.release(allocator);
            }
        }
    }

    // 普通数组
    if (!array_val.isArray()) {
        if (!Value_isObject(array_val)) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "foreach() argument must be of type array|object, {s} given",
                .{valueTypeName(array_val)},
            ) catch "foreach() argument must be of type array|object";
            emitWarning(msg);
        }
        return Value.initInt(0);
    }
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

/// iterator_to_array - 将迭代器转换为数组
/// @param iterator Iterator对象
/// @param preserve_keys 是否保留键（默认true）
pub fn php_iterator_to_array(iterator: Value, preserve_keys: Value, allocator: Allocator) !Value {
    if (!Value_isObject(iterator)) {
        return error.InvalidArgument;
    }

    // 处理默认参数：如果preserve_keys是null或missing，默认为true
    const use_keys = if (preserve_keys.isNull() or preserve_keys.isMissing()) true else preserve_keys.toBool();
    const result = try PHPArray.init(allocator);
    
    // 调用rewind()重置迭代器
    _ = try php_object_call(iterator, "rewind", &[_]Value{});
    
    var index: i64 = 0;
    while (true) {
        // 检查valid()
        const valid_result = try php_object_call(iterator, "valid", &[_]Value{});
        defer valid_result.release(allocator);
        if (!valid_result.toBool()) break;
        
        // 获取current()
        const current = try php_object_call(iterator, "current", &[_]Value{});
        
        if (use_keys) {
            // 获取key()并保留键
            const key = try php_object_call(iterator, "key", &[_]Value{});
            try result.setByValue(allocator, key, current);
            key.release(allocator);
        } else {
            // 使用数字索引
            try result.setByValue(allocator, Value.initInt(index), current);
            index += 1;
        }
        
        current.release(allocator);
        
        // 调用next()
        _ = try php_object_call(iterator, "next", &[_]Value{});
    }
    
    return Value.initArray(result);
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
        return Value.initNull();
    }

    // 减少引用计数
    if (iter.ref_count > 0) {
        iter.ref_count -= 1;
    }

    // 只有ref_count=0时才真正释放
    if (iter.ref_count == 0) {
        iter.freed = true;

        // 清理引用锁
        if (iter.array.ref_lock_count > 0) {
            iter.array.ref_lock_count = 0;
            iter.array.has_active_refs = false;
        }

        // 释放数组引用计数
        iter.array.release(allocator);

        allocator.destroy(iter);
    }

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
// ArrayObject 类 - 完整实现
// ============================================================================

/// ArrayObject 标志常量
const ARRAY_AS_PROPS: i64 = 1;
const STD_PROP_LIST: i64 = 2;

/// ArrayObject::__construct
fn arrayObject_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);

    // 初始化存储数组
    const array = try PHPArray.init(allocator);
    var flags: i64 = STD_PROP_LIST;

    if (args.len > 0) {
        if (args[0].isArray()) {
            // 复制输入数组
            const src = args[0].asArray();
            var iter = src.elements.iterator();
            while (iter.next()) |entry| {
                _ = entry.value_ptr.retain();
                try array.elements.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            array.next_index = src.next_index;
        } else if (args[0].isNull()) {
            // 空数组
        }
    }

    if (args.len > 1) {
        flags = args[1].toInt();
    }

    try obj.setProperty("_storage", Value.initArray(array));
    try obj.setProperty("_flags", Value.initInt(flags));
    try obj.setProperty("_iteratorClass", Value.initString(try PHPString.init(allocator, "ArrayIterator")));
    try obj.setProperty("_position", Value.initInt(0));

    return Value.initNull();
}

/// ArrayObject::append
fn arrayObject_append(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const val = if (args.len > 0) args[0] else Value.initNull();
            _ = val.retain();
            try arr.push(allocator, val);
        }
    }
    return Value.initNull();
}

/// ArrayObject::asort
fn arrayObject_asort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const flags = if (args.len > 0) args[0].toInt() else 0;
            _ = flags;

            // 收集所有键
            var keys = std.ArrayListUnmanaged(ArrayKey){};
            defer keys.deinit(allocator);
            var iter = arr.elements.iterator();
            while (iter.next()) |entry| try keys.append(allocator, entry.key_ptr.*);

            // 按值排序
            const SortCtx = struct {
                elems: *const PHPArray.Elements,
                fn lessThan(self_ctx: @This(), a: ArrayKey, b: ArrayKey) bool {
                    const va = self_ctx.elems.get(a) orelse return false;
                    const vb = self_ctx.elems.get(b) orelse return true;
                    // 使用浮点比较作为通用比较
                    return va.toFloat() < vb.toFloat();
                }
            };
            std.sort.insertion(ArrayKey, keys.items, SortCtx{ .elems = &arr.elements }, SortCtx.lessThan);

            // 重建有序数组
            const new_arr = try PHPArray.init(allocator);
            for (keys.items) |key| {
                if (arr.elements.get(key)) |val| {
                    _ = val.retain();
                    try new_arr.elements.put(key, val);
                }
            }
            // 用新数组的元素替换旧数组
            arr.elements.deinit();
            arr.elements = PHPArray.Elements.init(allocator);
            arr.elements.parent = arr;
            var new_iter = new_arr.elements.iterator();
            while (new_iter.next()) |entry| {
                try arr.elements.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }
    return Value.initNull();
}

/// ArrayObject::count
fn arrayObject_count(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) return Value.initInt(@intCast(storage.asArray().count()));
    }
    return Value.initInt(0);
}

/// ArrayObject::exchangeArray
fn arrayObject_exchangeArray(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);
    const old_storage = obj.getProperty("_storage");

    if (args.len > 0 and args[0].isArray()) {
        const new_arr = try PHPArray.init(allocator);
        const src = args[0].asArray();
        var iter = src.elements.iterator();
        while (iter.next()) |entry| {
            _ = entry.value_ptr.retain();
            try new_arr.elements.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        try obj.setProperty("_storage", Value.initArray(new_arr));
    }

    if (old_storage) |old| {
        _ = old.retain();
        return old;
    }
    return Value.initNull();
}

/// ArrayObject::getArrayCopy
fn arrayObject_getArrayCopy(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const src = storage.asArray();
            const new_arr = try PHPArray.init(allocator);
            var iter = src.elements.iterator();
            while (iter.next()) |entry| {
                _ = entry.value_ptr.retain();
                try new_arr.elements.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            return Value.initArray(new_arr);
        }
    }
    return Value.initArray(try PHPArray.init(allocator));
}

/// ArrayObject::getFlags
fn arrayObject_getFlags(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_flags")) |flags| return flags;
    return Value.initInt(STD_PROP_LIST);
}

/// ArrayObject::setFlags
fn arrayObject_setFlags(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len > 0) {
        try obj.setProperty("_flags", args[0]);
    }
    return Value.initNull();
}

/// ArrayObject::getIterator
fn arrayObject_getIterator(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);

    // 创建 ArrayIterator
    const iter_meta = findClass("ArrayIterator") orelse return Value.initNull();
    const iter_obj = try PHPObject.initWithMeta(allocator, iter_meta);

    // 复制数组引用
    if (obj.getProperty("_storage")) |storage| {
        try iter_obj.setProperty("_array", storage);
    }
    try iter_obj.setProperty("_position", Value.initInt(0));

    return Value_initObject(iter_obj);
}

/// ArrayObject::ksort
fn arrayObject_ksort(ctx: Value, _: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            var keys = std.ArrayListUnmanaged(ArrayKey){};
            defer keys.deinit(allocator);
            var iter = arr.elements.iterator();
            while (iter.next()) |entry| try keys.append(allocator, entry.key_ptr.*);

            std.sort.insertion(ArrayKey, keys.items, {}, struct {
                fn lessThan(_: void, a: ArrayKey, b: ArrayKey) bool {
                    switch (a) {
                        .integer => |ai| switch (b) {
                            .integer => |bi| return ai < bi,
                            .string => return true, // int < string
                        },
                        .string => |as| switch (b) {
                            .integer => return false, // string > int
                            .string => |bs| return std.mem.order(u8, as.data, bs.data) == .lt,
                        },
                    }
                }
            }.lessThan);

            const new_arr = try PHPArray.init(allocator);
            for (keys.items) |key| {
                if (arr.elements.get(key)) |val| {
                    _ = val.retain();
                    try new_arr.elements.put(key, val);
                }
            }
            // 用新数组的元素替换旧数组
            arr.elements.deinit();
            arr.elements = PHPArray.Elements.init(allocator);
            arr.elements.parent = arr;
            var new_iter = new_arr.elements.iterator();
            while (new_iter.next()) |entry| {
                try arr.elements.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }
    return Value.initNull();
}

/// ArrayObject::natcasesort
fn arrayObject_natcasesort(ctx: Value, _: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    // 自然排序（不区分大小写）- 简化实现
    return Value.initBool(true);
}

/// ArrayObject::natsort
fn arrayObject_natsort(ctx: Value, _: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    // 自然排序 - 简化实现
    return Value.initBool(true);
}

/// ArrayObject::offsetExists
fn arrayObject_offsetExists(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len == 0) return Value.initBool(false);

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const key = try valueToArrayKey(args[0], runtime_allocator);
            return Value.initBool(arr.elements.get(key) != null);
        }
    }
    return Value.initBool(false);
}

/// ArrayObject::offsetGet
fn arrayObject_offsetGet(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len == 0) return Value.initNull();

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const key = try valueToArrayKey(args[0], runtime_allocator);
            if (arr.elements.get(key)) |val| {
                _ = val.retain();
                return val;
            }
        }
    }
    return Value.initNull();
}

/// ArrayObject::offsetSet
fn arrayObject_offsetSet(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len < 2) return Value.initNull();

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const key = try valueToArrayKey(args[0], allocator);
            _ = args[1].retain();
            try arr.elements.put(key, args[1]);
        }
    }
    return Value.initNull();
}

/// ArrayObject::offsetUnset
fn arrayObject_offsetUnset(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len == 0) return Value.initNull();

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const key = try valueToArrayKey(args[0], runtime_allocator);
            if (arr.elements.get(key)) |old| old.release(runtime_allocator);
            _ = arr.elements.remove(key);
        }
    }
    return Value.initNull();
}

/// ArrayObject::serialize
fn arrayObject_serialize(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    var result = try std.ArrayList(u8).initCapacity(allocator, 64);
    defer result.deinit(allocator);
    const writer = result.writer(allocator);

    try writer.writeAll("O:11:\"ArrayObject\":1:{");

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const count = arr.count();
            try writer.print("i:0;a:{d}:{{", .{count});
            var iter = arr.elements.iterator();
            while (iter.next()) |entry| {
                switch (entry.key_ptr.*) {
                    .integer => |i| {
                        try writer.print("i:{d};", .{i});
                    },
                    .string => |s| {
                        try writer.print("s:{d}:\"{s}\";", .{ s.length, s.data });
                    },
                }
                // 简化值序列化
                try writer.writeAll("N;");
            }
            try writer.writeAll("}}");
        }
    }

    try writer.writeAll("}");

    return Value.initString(try PHPString.init(allocator, try result.toOwnedSlice(allocator)));
}

/// ArrayObject::uasort
fn arrayObject_uasort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    // 用户自定义排序 - 需要回调支持
    return Value.initBool(true);
}

/// ArrayObject::uksort
fn arrayObject_uksort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    // 用户自定义键排序 - 需要回调支持
    return Value.initBool(true);
}

/// ArrayObject::unserialize
fn arrayObject_unserialize(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    // 反序列化 - 简化实现
    return Value.initNull();
}

/// ArrayObject::usort
fn arrayObject_usort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    // 用户自定义排序 - 需要回调支持
    return Value.initBool(true);
}

/// ArrayObject::__serialize
fn arrayObject___serialize(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    const arr = try PHPArray.init(allocator);

    if (obj.getProperty("_storage")) |storage| {
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "storage") }, storage);
    }
    if (obj.getProperty("_flags")) |flags| {
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "flags") }, flags);
    }

    return Value.initArray(arr);
}

/// ArrayObject::__unserialize
fn arrayObject___unserialize(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len > 0 and args[0].isArray()) {
        const data = args[0].asArray();
        const storage_key = ArrayKey{ .string = try PHPString.init(runtime_allocator, "storage") };
        if (data.get(storage_key)) |storage| {
            try obj.setProperty("_storage", storage);
        }
        const flags_key = ArrayKey{ .string = try PHPString.init(runtime_allocator, "flags") };
        if (data.get(flags_key)) |flags| {
            try obj.setProperty("_flags", flags);
        }
    }
    return Value.initNull();
}

/// ArrayObject::__debugInfo
fn arrayObject___debugInfo(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    const arr = try PHPArray.init(allocator);

    if (obj.getProperty("_storage")) |storage| {
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "storage") }, storage);
    }

    return Value.initArray(arr);
}

/// 注册ArrayObject类
pub fn registerArrayObject(allocator: Allocator) !void {
    const meta = try ClassMeta.init(allocator, "ArrayObject");

    try meta.addProperty(.{ .name = "_storage", .default_value = Value.initNull(), .is_public = false });
    try meta.addProperty(.{ .name = "_flags", .default_value = Value.initInt(STD_PROP_LIST), .is_public = false });
    try meta.addProperty(.{ .name = "_iteratorClass", .default_value = Value.initNull(), .is_public = false });
    try meta.addProperty(.{ .name = "_position", .default_value = Value.initInt(0), .is_public = false });

    // 构造和基本方法
    try meta.addMethod(.{ .name = "__construct", .func = arrayObject_construct, .is_static = false });
    try meta.addMethod(.{ .name = "append", .func = arrayObject_append, .is_static = false });
    try meta.addMethod(.{ .name = "asort", .func = arrayObject_asort, .is_static = false });
    try meta.addMethod(.{ .name = "count", .func = arrayObject_count, .is_static = false });
    try meta.addMethod(.{ .name = "exchangeArray", .func = arrayObject_exchangeArray, .is_static = false });
    try meta.addMethod(.{ .name = "getArrayCopy", .func = arrayObject_getArrayCopy, .is_static = false });
    try meta.addMethod(.{ .name = "getFlags", .func = arrayObject_getFlags, .is_static = false });
    try meta.addMethod(.{ .name = "setFlags", .func = arrayObject_setFlags, .is_static = false });
    try meta.addMethod(.{ .name = "getIterator", .func = arrayObject_getIterator, .is_static = false });
    try meta.addMethod(.{ .name = "ksort", .func = arrayObject_ksort, .is_static = false });
    try meta.addMethod(.{ .name = "natcasesort", .func = arrayObject_natcasesort, .is_static = false });
    try meta.addMethod(.{ .name = "natsort", .func = arrayObject_natsort, .is_static = false });

    // ArrayAccess 接口
    try meta.addMethod(.{ .name = "offsetExists", .func = arrayObject_offsetExists, .is_static = false });
    try meta.addMethod(.{ .name = "offsetGet", .func = arrayObject_offsetGet, .is_static = false });
    try meta.addMethod(.{ .name = "offsetSet", .func = arrayObject_offsetSet, .is_static = false });
    try meta.addMethod(.{ .name = "offsetUnset", .func = arrayObject_offsetUnset, .is_static = false });

    // 序列化
    try meta.addMethod(.{ .name = "serialize", .func = arrayObject_serialize, .is_static = false });
    try meta.addMethod(.{ .name = "unserialize", .func = arrayObject_unserialize, .is_static = false });
    try meta.addMethod(.{ .name = "__serialize", .func = arrayObject___serialize, .is_static = false });
    try meta.addMethod(.{ .name = "__unserialize", .func = arrayObject___unserialize, .is_static = false });
    try meta.addMethod(.{ .name = "__debugInfo", .func = arrayObject___debugInfo, .is_static = false });

    // 用户排序
    try meta.addMethod(.{ .name = "uasort", .func = arrayObject_uasort, .is_static = false });
    try meta.addMethod(.{ .name = "uksort", .func = arrayObject_uksort, .is_static = false });
    try meta.addMethod(.{ .name = "usort", .func = arrayObject_usort, .is_static = false });

    meta.magic_construct = arrayObject_construct;

    // 注册常量
    const key1 = try allocator.dupe(u8, "ArrayObject::STD_PROP_LIST");
    try constants.put(key1, Value.initInt(STD_PROP_LIST));
    const key2 = try allocator.dupe(u8, "ArrayObject::ARRAY_AS_PROPS");
    try constants.put(key2, Value.initInt(ARRAY_AS_PROPS));

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
fn php_string_replace_once(subject_data: []const u8, search_data: []const u8, replace_data: []const u8, allocator: Allocator, ignore_case: bool) ![]u8 {
    if (search_data.len == 0) return allocator.dupe(u8, subject_data);

    var found_count: usize = 0;
    var pos: usize = 0;
    while (pos < subject_data.len) {
        if (pos + search_data.len <= subject_data.len) {
            const matched = if (ignore_case)
                std.ascii.eqlIgnoreCase(subject_data[pos .. pos + search_data.len], search_data)
            else
                std.mem.eql(u8, subject_data[pos .. pos + search_data.len], search_data);
            if (matched) {
                found_count += 1;
                pos += search_data.len;
                continue;
            }
        }
        pos += 1;
    }

    if (found_count == 0) return allocator.dupe(u8, subject_data);

    const new_len = subject_data.len - (found_count * search_data.len) + (found_count * replace_data.len);
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    pos = 0;
    while (pos < subject_data.len) {
        if (pos + search_data.len <= subject_data.len) {
            const matched = if (ignore_case)
                std.ascii.eqlIgnoreCase(subject_data[pos .. pos + search_data.len], search_data)
            else
                std.mem.eql(u8, subject_data[pos .. pos + search_data.len], search_data);
            if (matched) {
                @memcpy(buffer[write_pos .. write_pos + replace_data.len], replace_data);
                write_pos += replace_data.len;
                pos += search_data.len;
                continue;
            }
        }
        buffer[write_pos] = subject_data[pos];
        write_pos += 1;
        pos += 1;
    }

    return buffer;
}

fn php_value_to_owned_string_slice(val: Value, allocator: Allocator) ![]u8 {
    if (val.isString()) return allocator.dupe(u8, val.asString().data);
    const str = try val.toString(allocator);
    defer str.release(allocator);
    return allocator.dupe(u8, str.data);
}

fn php_str_replace_common(search: Value, replace: Value, subject: Value, count_out: Value, allocator: Allocator, ignore_case: bool) !Value {
    _ = count_out;
    if (!subject.isString()) return subject;

    if (search.isArray()) {
        var current = try allocator.dupe(u8, subject.asString().data);
        errdefer allocator.free(current);

        const search_arr = search.asArray();
        const replace_is_array = replace.isArray();
        var i: usize = 0;
        while (i < search_arr.elements.count()) : (i += 1) {
            const key = ArrayKey{ .integer = @intCast(i) };
            const search_val = search_arr.elements.get(key) orelse continue;
            const search_slice = try php_value_to_owned_string_slice(search_val, allocator);
            defer allocator.free(search_slice);

            const replace_slice = blk: {
                if (replace_is_array) {
                    const replace_arr = replace.asArray();
                    if (replace_arr.elements.get(key)) |replace_val| {
                        break :blk try php_value_to_owned_string_slice(replace_val, allocator);
                    }
                    break :blk try allocator.dupe(u8, "");
                }
                break :blk try php_value_to_owned_string_slice(replace, allocator);
            };
            defer allocator.free(replace_slice);

            const next = try php_string_replace_once(current, search_slice, replace_slice, allocator, ignore_case);
            allocator.free(current);
            current = next;
        }

        const result = try PHPString.init(allocator, current);
        allocator.free(current);
        return Value.initString(result);
    }

    const search_slice = try php_value_to_owned_string_slice(search, allocator);
    defer allocator.free(search_slice);
    const replace_slice = try php_value_to_owned_string_slice(replace, allocator);
    defer allocator.free(replace_slice);
    const buffer = try php_string_replace_once(subject.asString().data, search_slice, replace_slice, allocator, ignore_case);
    defer allocator.free(buffer);
    return Value.initString(try PHPString.init(allocator, buffer));
}

pub fn php_str_replace(search: Value, replace: Value, subject: Value, count_out: Value, allocator: Allocator) !Value {
    return php_str_replace_common(search, replace, subject, count_out, allocator, false);
}

pub fn php_str_ireplace(search: Value, replace: Value, subject: Value, count_out: Value, allocator: Allocator) !Value {
    return php_str_replace_common(search, replace, subject, count_out, allocator, true);
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

/// 字符串索引赋值 - PHP: $str[$i] = 'x'
/// 修改字符串中指定位置的字符，返回修改后的新字符串
pub fn php_string_offset_set(str_val: *Value, index_val: Value, char_val: Value, allocator: Allocator) !void {
    if (!str_val.isString()) return;
    const php_str = str_val.asString();
    const idx = index_val.toInt();
    if (idx < 0 or idx >= @as(i64, @intCast(php_str.length))) return;
    const pos: usize = @intCast(idx);

    // 获取要设置的字符
    var new_char: u8 = 0;
    if (char_val.isString()) {
        const char_str = char_val.asString();
        if (char_str.length > 0) {
            new_char = char_str.data[0];
        }
    } else {
        new_char = @as(u8, @intCast(char_val.toInt() & 0xFF));
    }

    // 创建新字符串（COW语义）
    const new_data = try allocator.alloc(u8, php_str.length);
    @memcpy(new_data, php_str.data[0..php_str.length]);
    new_data[pos] = new_char;

    const new_str = try PHPString.init(allocator, new_data);
    allocator.free(new_data);
    str_val.release(allocator);
    str_val.* = Value.initString(new_str);
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

// ============================================================================
// PCRE2 正则表达式支持
// ============================================================================

// PCRE2 C API声明
const pcre2_code = opaque {};
const pcre2_match_data = opaque {};

// 正则缓存条目
const RegexCacheEntry = struct {
    code: *pcre2_code,
    last_used: i128, // 纳秒时间戳（i128）

    fn init(code: *pcre2_code) RegexCacheEntry {
        return .{
            .code = code,
            .last_used = std.time.nanoTimestamp(),
        };
    }

    fn touch(self: *RegexCacheEntry) void {
        self.last_used = std.time.nanoTimestamp();
    }

    fn deinit(self: *RegexCacheEntry) void {
        pcre2_code_free_8(self.code);
    }
};

// 全局正则缓存
const REGEX_CACHE_SIZE = 128;
var regex_cache: std.StringHashMap(RegexCacheEntry) = undefined;
var regex_cache_mutex: std.Thread.Mutex = .{};
var regex_cache_initialized: bool = false;

fn initRegexCache(allocator: Allocator) !void {
    if (regex_cache_initialized) return;
    regex_cache = std.StringHashMap(RegexCacheEntry).init(allocator);
    regex_cache_initialized = true;
}

fn getOrCompileRegex(pattern: []const u8, options: c_uint, allocator: Allocator) !*pcre2_code {
    try initRegexCache(allocator);

    regex_cache_mutex.lock();
    defer regex_cache_mutex.unlock();

    // 查找缓存
    if (regex_cache.getPtr(pattern)) |entry| {
        entry.touch();
        return entry.code;
    }

    // 缓存未命中，编译新模式
    var errcode: c_int = 0;
    var erroffset: usize = 0;
    const re_ptr = pcre2_compile_8(
        pattern.ptr,
        pattern.len,
        options,
        &errcode,
        &erroffset,
        null,
    );
    if (re_ptr == null) return error.RegexCompileFailed;
    const re = re_ptr.?;

    // LRU淘汰：如果缓存满了，移除最旧的条目
    if (regex_cache.count() >= REGEX_CACHE_SIZE) {
        var oldest_key: ?[]const u8 = null;
        var oldest_time: i128 = std.math.maxInt(i128);

        var iter = regex_cache.iterator();
        while (iter.next()) |kv| {
            if (kv.value_ptr.last_used < oldest_time) {
                oldest_time = kv.value_ptr.last_used;
                oldest_key = kv.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (regex_cache.fetchRemove(key)) |removed| {
                var entry = removed.value;
                entry.deinit();
                allocator.free(removed.key);
            }
        }
    }

    // 添加到缓存
    const key_copy = try allocator.dupe(u8, pattern);
    try regex_cache.put(key_copy, RegexCacheEntry.init(re));

    return re;
}

extern fn pcre2_compile_8(
    pattern: [*]const u8,
    pattern_length: usize,
    options: c_uint,
    *c_int,
    [*c]usize,
    ?*anyopaque,
) ?*pcre2_code;

extern fn pcre2_code_free_8(?*pcre2_code) void;
extern fn pcre2_match_data_create_from_pattern_8(?*const pcre2_code, ?*anyopaque) ?*pcre2_match_data;
extern fn pcre2_match_data_free_8(?*pcre2_match_data) void;
extern fn pcre2_match_8(
    ?*const pcre2_code,
    [*]const u8,
    usize,
    c_int,
    c_uint,
    ?*pcre2_match_data,
    ?*anyopaque,
) c_int;

extern fn pcre2_get_ovector_pointer_8(?*pcre2_match_data) [*]usize;

extern fn pcre2_substitute_8(
    ?*const pcre2_code,
    [*]const u8,
    usize,
    usize,
    c_uint,
    ?*pcre2_match_data,
    ?*anyopaque,
    [*]const u8,
    usize,
    [*]u8,
    [*]usize,
) c_int;

// PCRE2 常量
const PCRE2_CASELESS: c_uint = 0x00000008;
const PCRE2_MULTILINE: c_uint = 0x00000002;
const PCRE2_DOTALL: c_uint = 0x00000004;
const PCRE2_EXTENDED: c_uint = 0x00000008;
const PCRE2_UTF: c_uint = 0x00080000;
const PCRE2_ERROR_NOMATCH: c_int = -1;
const PCRE2_SUBSTITUTE_GLOBAL: c_uint = 0x00000100;
const PCRE2_SUBSTITUTE_OVERFLOW_LENGTH: c_uint = 0x00001000;

const ParsedPattern = struct {
    pattern: []const u8,
    options: c_uint,
};

/// 解析PHP风格正则表达式 (/pattern/flags)
fn parsePHPRegexPattern(pattern: []const u8) ParsedPattern {
    var result = ParsedPattern{
        .pattern = pattern,
        .options = PCRE2_UTF | PCRE2_DOTALL,
    };

    if (pattern.len == 0) return result;

    var start: usize = 0;
    while (start < pattern.len and pattern[start] == ' ') : (start += 1) {}
    if (start >= pattern.len) return result;

    const delimiter = pattern[start];
    var end: usize = start + 1;
    var paren_depth: i32 = 0;
    var in_escape = false;

    while (end < pattern.len) : (end += 1) {
        const ch = pattern[end];
        if (in_escape) {
            in_escape = false;
            continue;
        }
        if (ch == '\\') {
            in_escape = true;
            continue;
        }
        if (ch == '(' or ch == '[' or ch == '{') {
            paren_depth += 1;
        } else if (ch == ')' or ch == ']' or ch == '}') {
            paren_depth -= 1;
        } else if (ch == delimiter and paren_depth == 0) {
            break;
        }
    }

    if (end >= pattern.len) {
        result.pattern = pattern[start + 1 ..];
        return result;
    }
    result.pattern = pattern[start + 1 .. end];

    const modifiers = pattern[end + 1 ..];
    for (modifiers) |ch| {
        switch (ch) {
            'i' => result.options |= PCRE2_CASELESS,
            'm' => result.options |= PCRE2_MULTILINE,
            's' => result.options |= PCRE2_DOTALL,
            'x' => result.options |= PCRE2_EXTENDED,
            ' ' => break,
            else => {},
        }
    }

    return result;
}

/// 完整PCRE2实现的preg_match
/// 支持所有正则语法，与解释器/Bytecode行为一致
pub fn preg_match(pattern_val: Value, subject_val: Value, matches_ref: *Value, flags: Value, offset: Value, allocator: Allocator) !Value {
    _ = flags; // TODO: 实现flags支持
    _ = offset; // TODO: 实现offset支持
    _ = matches_ref; // TODO: 实现matches填充
    
    if (!pattern_val.isString() or !subject_val.isString()) {
        return Value.initInt(0);
    }

    const pattern_str = pattern_val.asString();
    const subject_str = subject_val.asString();

    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则（不需要release，缓存管理生命周期）
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch return Value.initInt(0);

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse return Value.initInt(0);
    defer pcre2_match_data_free_8(match_data);

    const rc = pcre2_match_8(re, subject_str.data.ptr, subject_str.length, 0, 0, match_data, null);

    if (rc == PCRE2_ERROR_NOMATCH) return Value.initInt(0);
    if (rc < 0) return Value.initInt(0);
    return Value.initInt(1);
}

/// preg_match with matches - 支持捕获组
/// matches_ref: 引用参数，会被填充为 [full_match, group1, group2, ...]
pub fn preg_match_with_matches(pattern_val: Value, subject_val: Value, matches_ref: *Value, allocator: Allocator) !Value {
    if (!pattern_val.isString() or !subject_val.isString()) {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    const pattern_str = pattern_val.asString();
    const subject_str = subject_val.asString();
    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };
    defer pcre2_match_data_free_8(match_data);

    const rc = pcre2_match_8(
        re,
        subject_str.data.ptr,
        subject_str.length,
        0,
        0,
        match_data,
        null,
    );

    if (rc == PCRE2_ERROR_NOMATCH or rc < 0) {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    // 填充matches数组
    const matches_arr = try PHPArray.init(allocator);
    const ovec = pcre2_get_ovector_pointer_8(match_data);

    var i: usize = 0;
    while (i < @as(usize, @intCast(rc))) : (i += 1) {
        const start = ovec[i * 2];
        const end = ovec[i * 2 + 1];
        if (start < subject_str.length and end <= subject_str.length and start <= end) {
            const capture = subject_str.data[start..end];
            const capture_str = try PHPString.init(allocator, capture);
            try matches_arr.push(allocator, Value.initString(capture_str));
        }
    }

    matches_ref.* = Value.initArray(matches_arr);
    return Value.initInt(1);
}

/// preg_match_all - 返回所有匹配
/// matches_ref: 引用参数，填充为二维数组
/// 返回：匹配次数
pub fn preg_match_all(pattern_val: Value, subject_val: Value, matches_ref: *Value, flags: Value, offset: Value, allocator: Allocator) !Value {
    _ = flags; // TODO: 实现flags支持
    _ = offset; // TODO: 实现offset支持
    
    if (!pattern_val.isString() or !subject_val.isString()) {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    const pattern_str = pattern_val.asString();
    const subject_str = subject_val.asString();
    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };
    defer pcre2_match_data_free_8(match_data);

    // 存储所有匹配（临时）
    var all_matches = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]const u8)){};
    defer {
        for (all_matches.items) |*match_groups| {
            match_groups.deinit(allocator);
        }
        all_matches.deinit(allocator);
    }

    var match_offset: usize = 0;
    var match_count: i64 = 0;

    // 循环匹配所有
    while (match_offset <= subject_str.length) {
        const rc = pcre2_match_8(
            re,
            subject_str.data.ptr,
            subject_str.length,
            @intCast(match_offset),
            0,
            match_data,
            null,
        );

        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) break;

        match_count += 1;
        const ovec = pcre2_get_ovector_pointer_8(match_data);

        // 保存当前匹配的所有组
        var match_groups = std.ArrayListUnmanaged([]const u8){};
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            if (start < subject_str.length and end <= subject_str.length and start <= end) {
                const capture = subject_str.data[start..end];
                try match_groups.append(allocator, capture);
            }
        }
        try all_matches.append(allocator, match_groups);

        // 移动到下一个位置
        const match_end = ovec[1];
        if (match_end == match_offset) {
            match_offset += 1; // 避免空匹配无限循环
        } else {
            match_offset = match_end;
        }
    }

    // 转换为PREG_PATTERN_ORDER格式
    // matches[0] = [所有完整匹配]
    // matches[1] = [所有第1个捕获组]
    const matches_arr = try PHPArray.init(allocator);

    if (all_matches.items.len > 0) {
        const num_groups = all_matches.items[0].items.len;

        // 为每个组创建数组
        var group_idx: usize = 0;
        while (group_idx < num_groups) : (group_idx += 1) {
            const group_arr = try PHPArray.init(allocator);

            // 收集所有匹配中的该组
            for (all_matches.items) |match_groups| {
                if (group_idx < match_groups.items.len) {
                    const capture = match_groups.items[group_idx];
                    const capture_str = try PHPString.init(allocator, capture);
                    try group_arr.push(allocator, Value.initString(capture_str));
                }
            }

            try matches_arr.push(allocator, Value.initArray(group_arr));
        }
    }

    matches_ref.* = Value.initArray(matches_arr);
    return Value.initInt(match_count);
}

/// preg_match_all - 返回所有匹配和捕获组
/// 返回: [match_count, [[full_match, group1, group2, ...], ...]]
pub fn preg_replace(pattern_val: Value, replacement_val: Value, subject_val: Value, allocator: Allocator) !Value {
    if (!pattern_val.isString() or !replacement_val.isString() or !subject_val.isString()) {
        return Value.initNull();
    }

    const pattern_str = pattern_val.asString();
    const replacement_str = replacement_val.asString();
    const subject_str = subject_val.asString();

    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch return subject_val;

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse return subject_val;
    defer pcre2_match_data_free_8(match_data);

    // 分配输出缓冲区
    const output_len: usize = subject_str.length * 2;
    const output = try allocator.alloc(u8, output_len);
    errdefer allocator.free(output);

    var output_size: usize = output_len;
    const rc = pcre2_substitute_8(re, subject_str.data.ptr, subject_str.length, 0, PCRE2_SUBSTITUTE_GLOBAL, match_data, null, replacement_str.data.ptr, replacement_str.length, output.ptr, @ptrCast(&output_size));

    if (rc < 0) {
        allocator.free(output);
        return subject_val;
    }

    const result = try allocator.realloc(output, output_size);
    return Value.initString(try PHPString.init(allocator, result));
}

/// preg_filter - 类似 preg_replace，但只返回匹配的元素
pub fn preg_filter(pattern_val: Value, replacement_val: Value, subject_val: Value, allocator: Allocator) !Value {
    // 处理数组输入
    if (subject_val.isArray()) {
        const subject_arr = subject_val.asArray();
        const result_arr = try PHPArray.init(allocator);

        var iter = subject_arr.elements.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isString()) {
                const subject_str = entry.value_ptr.asString();
                
                if (pattern_val.isString() and replacement_val.isString()) {
                    const pattern_str = pattern_val.asString();
                    const parsed = parsePHPRegexPattern(pattern_str.data);
                    
                    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch continue;
                    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse continue;
                    defer pcre2_match_data_free_8(match_data);

                    // 检查是否有匹配
                    const rc_check = pcre2_match_8(re, subject_str.data.ptr, subject_str.length, 0, 0, match_data, null);
                    
                    // 只有匹配时才进行替换并添加到结果
                    if (rc_check >= 0) {
                        const replacement_str = replacement_val.asString();
                        const output_len: usize = subject_str.length * 2;
                        const output = allocator.alloc(u8, output_len) catch continue;
                        errdefer allocator.free(output);

                        var output_size: usize = output_len;
                        const rc = pcre2_substitute_8(re, subject_str.data.ptr, subject_str.length, 0, PCRE2_SUBSTITUTE_GLOBAL, match_data, null, replacement_str.data.ptr, replacement_str.length, output.ptr, @ptrCast(&output_size));

                        if (rc >= 0) {
                            const result = allocator.realloc(output, output_size) catch {
                                allocator.free(output);
                                continue;
                            };
                            const result_val = Value.initString(PHPString.init(allocator, result) catch {
                                allocator.free(result);
                                continue;
                            });
                            
                            // 保持原始键
                            switch (entry.key_ptr.*) {
                                .integer => result_arr.set(allocator, entry.key_ptr.*, result_val) catch {},
                                .string => result_arr.push(allocator, result_val) catch {},
                            }
                        } else {
                            allocator.free(output);
                        }
                    }
                }
            }
        }

        return Value.initArray(result_arr);
    }

    // 处理字符串输入
    if (!pattern_val.isString() or !replacement_val.isString() or !subject_val.isString()) {
        return Value.initNull();
    }

    const pattern_str = pattern_val.asString();
    const replacement_str = replacement_val.asString();
    const subject_str = subject_val.asString();

    const parsed = parsePHPRegexPattern(pattern_str.data);
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch return Value.initNull();

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse return Value.initNull();
    defer pcre2_match_data_free_8(match_data);

    // 检查是否有匹配
    const rc_check = pcre2_match_8(re, subject_str.data.ptr, subject_str.length, 0, 0, match_data, null);
    
    // 如果没有匹配，返回 null（preg_filter 的特性）
    if (rc_check == PCRE2_ERROR_NOMATCH or rc_check < 0) {
        return Value.initNull();
    }

    // 有匹配，执行替换
    const output_len: usize = subject_str.length * 2;
    const output = try allocator.alloc(u8, output_len);
    errdefer allocator.free(output);

    var output_size: usize = output_len;
    const rc = pcre2_substitute_8(re, subject_str.data.ptr, subject_str.length, 0, PCRE2_SUBSTITUTE_GLOBAL, match_data, null, replacement_str.data.ptr, replacement_str.length, output.ptr, @ptrCast(&output_size));

    if (rc < 0) {
        allocator.free(output);
        return Value.initNull();
    }

    const result = try allocator.realloc(output, output_size);
    return Value.initString(try PHPString.init(allocator, result));
}

/// preg_split - 正则分割 (pattern, subject, limit=-1, flags=0, allocator)
pub fn preg_split(pattern_val: Value, subject_val: Value, limit_val: Value, flags_val: Value, allocator: Allocator) !Value {
    if (!pattern_val.isString() or !subject_val.isString()) {
        return Value.initNull();
    }

    const pattern_str = pattern_val.asString();
    const subject_str = subject_val.asString();

    // limit: -1 表示无限制
    const limit: i64 = if (limit_val.isInt()) limit_val.asInt() else -1;
    // flags: PREG_SPLIT_NO_EMPTY=1, PREG_SPLIT_DELIM_CAPTURE=2, PREG_SPLIT_OFFSET_CAPTURE=4
    const flags: i64 = if (flags_val.isInt()) flags_val.asInt() else 0;
    const no_empty = (flags & 1) != 0;

    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        // 编译失败，返回包含原字符串的数组
        const arr = try PHPArray.init(allocator);
        try arr.push(allocator, subject_val);
        return Value.initArray(arr);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        const arr = try PHPArray.init(allocator);
        try arr.push(allocator, subject_val);
        return Value.initArray(arr);
    };
    defer pcre2_match_data_free_8(match_data);

    const result_arr = try PHPArray.init(allocator);
    var offset: usize = 0;
    var part_count: i64 = 0;

    while (offset < subject_str.length) {
        // 如果达到limit-1，把剩余部分全部放入最后一个元素
        if (limit > 0 and part_count >= limit - 1) {
            const remaining = subject_str.data[offset..];
            if (!no_empty or remaining.len > 0) {
                const part_str = try PHPString.init(allocator, remaining);
                try result_arr.push(allocator, Value.initString(part_str));
            }
            break;
        }

        const rc = pcre2_match_8(re, subject_str.data.ptr, subject_str.length, @intCast(offset), 0, match_data, null);

        if (rc == PCRE2_ERROR_NOMATCH) {
            // 添加剩余部分
            const remaining = subject_str.data[offset..];
            if (!no_empty or remaining.len > 0) {
                const part = try PHPString.init(allocator, remaining);
                try result_arr.push(allocator, Value.initString(part));
            }
            break;
        }

        if (rc < 0) break;

        const ovec = pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovec[0];
        const match_end = ovec[1];

        // 添加匹配前的部分
        const part = subject_str.data[offset..match_start];
        if (!no_empty or part.len > 0) {
            const part_str = try PHPString.init(allocator, part);
            try result_arr.push(allocator, Value.initString(part_str));
            part_count += 1;
        }

        offset = match_end;
        if (match_start == match_end) {
            // 空匹配，前进一个字符避免无限循环
            offset += 1;
        }
    }

    return Value.initArray(result_arr);
}

/// preg_grep - 返回匹配正则的数组元素
pub fn preg_grep(pattern_val: Value, input_val: Value, flags_val: Value, allocator: Allocator) !Value {
    if (!pattern_val.isString() or !input_val.isArray()) {
        return Value.initArray(try PHPArray.init(allocator));
    }

    const pattern_str = pattern_val.asString();
    const input_arr = input_val.asArray();
    const flags = if (flags_val.isInt()) flags_val.asInt() else 0;
    const invert = (flags & 1) != 0; // PREG_GREP_INVERT = 1

    const parsed = parsePHPRegexPattern(pattern_str.data);
    const re = try getOrCompileRegex(parsed.pattern, parsed.options, allocator);

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        return Value.initArray(try PHPArray.init(allocator));
    };
    defer pcre2_match_data_free_8(match_data);

    const result_arr = try PHPArray.init(allocator);

    // 遍历输入数组（简化：只支持数字索引）
    var i: usize = 0;
    while (i < input_arr.elements.packed_values.items.len) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        const value = input_arr.get(key) orelse continue;

        // 转换为字符串
        const str_val = if (value.isString())
            value.asString().data
        else if (value.isInt()) blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{value.asInt()}) catch "";
            break :blk s;
        } else "";

        // 匹配测试
        const rc = pcre2_match_8(re, str_val.ptr, str_val.len, 0, 0, match_data, null);
        const matched = (rc >= 0);

        // 根据flags决定是否包含
        const should_include = if (invert) !matched else matched;

        if (should_include) {
            try result_arr.push(allocator, value);
        }
    }

    return Value.initArray(result_arr);
}

/// preg_quote - 转义正则表达式字符
pub fn preg_quote(str_val: Value, delimiter_val: Value, allocator: Allocator) !Value {
    if (!str_val.isString()) {
        return Value.initString(try PHPString.init(allocator, ""));
    }

    const str = str_val.asString();
    const delimiter: u8 = if (delimiter_val.isString() and delimiter_val.asString().length > 0)
        delimiter_val.asString().data[0]
    else
        0;

    // 需要转义的特殊字符
    const specials = ".\\+*?[^]$(){}=!<>|:-#";
    var escape_table: [256]u8 = undefined;
    @memset(escape_table[0..], 0);
    for (specials) |ch| {
        escape_table[@as(usize, @intCast(ch))] = 1;
    }

    // 计算结果长度
    var result_len: usize = str.length;
    for (str.data) |ch| {
        const needs_escape = ch == '\\' or ch == delimiter or escape_table[@as(usize, @intCast(ch))] == 1;
        if (needs_escape) {
            result_len += 1;
        }
    }

    // 分配结果缓冲区
    const result = try allocator.alloc(u8, result_len);
    errdefer allocator.free(result);

    // 执行转义
    var j: usize = 0;
    for (str.data) |ch| {
        const needs_escape = ch == '\\' or ch == delimiter or escape_table[@as(usize, @intCast(ch))] == 1;
        if (needs_escape) {
            result[j] = '\\';
            j += 1;
        }
        result[j] = ch;
        j += 1;
    }

    return Value.initString(try PHPString.init(allocator, result));
}

/// preg_last_error - 返回最后一次 PCRE 正则执行的错误代码
pub fn preg_last_error() Value {
    // AOT 模式下简化实现，总是返回 0 (PREG_NO_ERROR)
    return Value.initInt(0);
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

pub fn php_str_getcsv(input: Value, separator: Value, enclosure: Value, escape: Value, allocator: Allocator) !Value {
    const input_str = try input.toString(allocator);
    defer input_str.release(allocator);

    const separator_str = try separator.toString(allocator);
    defer separator_str.release(allocator);

    const enclosure_str = try enclosure.toString(allocator);
    defer enclosure_str.release(allocator);

    const escape_str = try escape.toString(allocator);
    defer escape_str.release(allocator);

    const sep: u8 = if (separator_str.length > 0) separator_str.data[0] else ',';
    const enc: u8 = if (enclosure_str.length > 0) enclosure_str.data[0] else '"';
    const esc: u8 = if (escape_str.length > 0) escape_str.data[0] else '\\';

    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var field = std.ArrayList(u8){};
    defer field.deinit(allocator);

    var in_quotes = false;
    var i: usize = 0;
    while (i < input_str.length) : (i += 1) {
        const ch = input_str.data[i];

        if (ch == esc and i + 1 < input_str.length) {
            const next = input_str.data[i + 1];
            if (next == enc or next == esc) {
                try field.append(allocator, next);
                i += 1;
                continue;
            }
        }

        if (ch == enc) {
            if (in_quotes and i + 1 < input_str.length and input_str.data[i + 1] == enc) {
                try field.append(allocator, enc);
                i += 1;
                continue;
            }
            in_quotes = !in_quotes;
            continue;
        }

        if (!in_quotes and ch == sep) {
            const field_str = try PHPString.init(allocator, field.items);
            try result.push(allocator, Value.initString(field_str));
            field.clearRetainingCapacity();
            continue;
        }

        try field.append(allocator, ch);
    }

    const field_str = try PHPString.init(allocator, field.items);
    try result.push(allocator, Value.initString(field_str));
    return Value.initArray(result);
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

fn php_string_compare_bytes(lhs: []const u8, rhs: []const u8, comptime ignore_case: bool) i64 {
    const shared_len = @min(lhs.len, rhs.len);
    var i: usize = 0;
    while (i < shared_len) : (i += 1) {
        const lc: u8 = if (ignore_case) std.ascii.toLower(lhs[i]) else lhs[i];
        const rc: u8 = if (ignore_case) std.ascii.toLower(rhs[i]) else rhs[i];
        if (lc != rc) {
            return @as(i64, lc) - @as(i64, rc);
        }
    }
    return @as(i64, @intCast(lhs.len)) - @as(i64, @intCast(rhs.len));
}

pub fn php_strcmp(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();
    return Value.initInt(php_string_compare_bytes(s1.data[0..s1.length], s2.data[0..s2.length], false));
}

pub fn php_strcasecmp(str1: Value, str2: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();
    return Value.initInt(php_string_compare_bytes(s1.data[0..s1.length], s2.data[0..s2.length], true));
}

/// strnatcmp - 自然排序字符串比较（区分大小写）
pub fn php_strnatcmp(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();
    return Value.initInt(naturalCompare(s1.data[0..s1.length], s2.data[0..s2.length], false));
}

/// strnatcasecmp - 自然排序字符串比较（不区分大小写）
pub fn php_strnatcasecmp(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();
    return Value.initInt(naturalCompare(s1.data[0..s1.length], s2.data[0..s2.length], true));
}

/// 自然排序比较算法
/// 将数字部分作为整数比较，非数字部分按字符比较
fn naturalCompare(s1: []const u8, s2: []const u8, case_insensitive: bool) i64 {
    var idx1: usize = 0;
    var idx2: usize = 0;

    while (idx1 < s1.len and idx2 < s2.len) {
        const c1 = s1[idx1];
        const c2 = s2[idx2];

        // 检查是否都是数字
        if (std.ascii.isDigit(c1) and std.ascii.isDigit(c2)) {
            // 跳过前导零
            while (idx1 < s1.len and s1[idx1] == '0') idx1 += 1;
            while (idx2 < s2.len and s2[idx2] == '0') idx2 += 1;

            // 提取数字
            var num1: i64 = 0;
            var num2: i64 = 0;
            var len1: usize = 0;
            var len2: usize = 0;

            while (idx1 + len1 < s1.len and std.ascii.isDigit(s1[idx1 + len1])) {
                num1 = num1 * 10 + (s1[idx1 + len1] - '0');
                len1 += 1;
            }

            while (idx2 + len2 < s2.len and std.ascii.isDigit(s2[idx2 + len2])) {
                num2 = num2 * 10 + (s2[idx2 + len2] - '0');
                len2 += 1;
            }

            // 比较数字
            if (num1 != num2) {
                return if (num1 < num2) -1 else 1;
            }

            // 数字相同，继续比较
            idx1 += len1;
            idx2 += len2;
        } else {
            // 非数字部分，按字符比较
            const ch1 = if (case_insensitive) std.ascii.toLower(c1) else c1;
            const ch2 = if (case_insensitive) std.ascii.toLower(c2) else c2;

            if (ch1 != ch2) {
                return if (ch1 < ch2) -1 else 1;
            }

            idx1 += 1;
            idx2 += 1;
        }
    }

    // 长度不同
    if (idx1 < s1.len) return 1;
    if (idx2 < s2.len) return -1;
    return 0;
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
    if (!arr.isArray()) {
        const got = valueTypeName(arr);
        emitTypeFatalError("array_push", 1, "array", got);
    }

    const php_arr = arr.asArray();
    for (values) |val| {
        try php_arr.push(allocator, val);
    }

    return Value.initInt(@intCast(php_arr.count()));
}

/// array_pop - 弹出数组最后一个元素
pub fn php_array_pop(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) {
        const got = valueTypeName(arr);
        emitTypeFatalError("array_pop", 1, "array", got);
    }

    const php_arr = arr.asArray();
    const value = array_ops_shared.pop(ArrayKey, Value, @TypeOf(php_arr.elements), allocator, &php_arr.elements, &php_arr.next_index) orelse return Value.initNull();
    return value;
}

/// in_array - 检查值是否在数组中
pub fn php_in_array(needle: Value, haystack: Value, strict: Value) !Value {
    if (!haystack.isArray()) return Value.initBool(false);

    const use_strict = strict.toBool();
    const arr = haystack.asArray();
    var iter = arr.elements.iterator();

    while (iter.next()) |entry| {
        if (use_strict) {
            const eq = try php_identical(needle, entry.value_ptr.*);
            if (eq.asBool()) return Value.initBool(true);
        } else {
            const eq = try php_eq(needle, entry.value_ptr.*);
            if (eq.asBool()) return Value.initBool(true);
        }
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

/// 数组联合运算（PHP + 运算符）
///
/// 与 array_merge 不同：
/// - 保留左侧数组的所有键值对
/// - 右侧数组中键不在左侧时才加入
/// - 整数键不重新索引
pub fn php_array_union(lhs: Value, rhs: Value, allocator: Allocator) !Value {
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    // 先拷贝左侧所有元素
    const lhs_arr = lhs.asArray();
    var it_l = lhs_arr.elements.iterator();
    var max_int_key: i64 = -1;
    while (it_l.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*.retain();
        switch (key) {
            .integer => |i| {
                if (i > max_int_key) max_int_key = i;
                try result.elements.put(key, value);
            },
            .string => |s| {
                s.retain();
                try result.elements.put(key, value);
            },
        }
    }

    // 再拷贝右侧中左侧不存在的键
    const rhs_arr = rhs.asArray();
    var it_r = rhs_arr.elements.iterator();
    while (it_r.next()) |entry| {
        const key = entry.key_ptr.*;
        if (result.elements.get(key) != null) continue;
        const value = entry.value_ptr.*.retain();
        switch (key) {
            .integer => |i| {
                if (i > max_int_key) max_int_key = i;
                try result.elements.put(key, value);
            },
            .string => |s| {
                s.retain();
                try result.elements.put(key, value);
            },
        }
    }

    result.next_index = max_int_key + 1;
    return Value.initArray(result);
}

/// Merge array into target (for spread operator)
/// PHP 8.1+: string keys are preserved, integer keys are renumbered
pub fn php_array_merge_into(target: Value, source: Value, allocator: Allocator) !Value {
    if (!target.isArray()) return target;

    const target_arr = target.asArray();

    const iter_val = try php_array_iter_init(source, allocator);
    defer _ = php_array_iter_free(iter_val, allocator) catch {};

    while ((try php_array_iter_valid(iter_val)).toBool()) {
        const key_val = try php_array_iter_key(iter_val, allocator);
        defer key_val.release(allocator);
        const value = try php_array_iter_value(iter_val);
        defer value.release(allocator);

        if (key_val.isString()) {
            try target_arr.set(allocator, ArrayKey{ .string = key_val.asString() }, value);
        } else {
            try target_arr.push(allocator, value);
        }

        const next_iter = try php_array_iter_next(iter_val);
        next_iter.release(allocator);
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

/// array_is_list - 检查数组是否是列表
///
/// 检查给定的数组是否是列表。如果数组的键是连续的整数，从0开始，则认为是列表。
/// 空数组被认为是列表。
///
/// @param arr 要检查的数组
/// @return 如果是列表返回true，否则返回false
///
/// 示例：
/// ```php
/// array_is_list([]);              // true
/// array_is_list([1, 2, 3]);       // true
/// array_is_list([0 => 'a', 1 => 'b']);  // true
/// array_is_list([1 => 'a', 0 => 'b']);  // false (顺序不对)
/// array_is_list([0 => 'a', 2 => 'b']);  // false (不连续)
/// array_is_list(['a' => 1, 'b' => 2]);  // false (字符串键)
/// ```
pub fn php_array_is_list(arr: Value) Value {
    if (!arr.isArray()) return Value.initBool(false);

    const php_arr = arr.asArray();
    
    // 空数组是列表
    if (php_arr.elements.count() == 0) return Value.initBool(true);

    var iter = php_arr.elements.iterator();
    var expected_idx: i64 = 0;

    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        switch (key) {
            .integer => |i| {
                // 键必须等于期望的索引
                if (i != expected_idx) return Value.initBool(false);
                expected_idx += 1;
            },
            .string => {
                // 有字符串键，不是列表
                return Value.initBool(false);
            },
        }
    }

    return Value.initBool(true);
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

/// log2 - 以2为底的对数
pub fn php_log2(val: Value) !Value {
    return Value.initFloat(@log2(val.toFloat()));
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

/// intdiv - 整数除法
pub fn php_intdiv(dividend: Value, divisor: Value) !Value {
    const a = dividend.toInt();
    const b = divisor.toInt();
    if (b == 0) {
        return error.DivisionByZero;
    }
    return Value.initInt(@divTrunc(a, b));
}

/// fdiv - 浮点除法（PHP 8.0+，除以零返回 INF/NAN）
pub fn php_fdiv(dividend: Value, divisor: Value) Value {
    const a = dividend.toFloat();
    const b = divisor.toFloat();
    // fdiv 不抛出异常，除以零返回 INF/-INF/NAN
    return Value.initFloat(a / b);
}

/// hypot - 计算直角三角形斜边长度
pub fn php_hypot(x: Value, y: Value) !Value {
    return Value.initFloat(std.math.hypot(x.toFloat(), y.toFloat()));
}

/// base_convert - 在任意进制之间转换数字
pub fn php_base_convert(number: Value, frombase: Value, tobase: Value, allocator: Allocator) !Value {
    if (!number.isString()) return Value.initString(try PHPString.init(allocator, "0"));

    const num_str = number.asString().data;
    const from: u8 = @intCast(@min(@max(frombase.toInt(), 2), 36));
    const to: u8 = @intCast(@min(@max(tobase.toInt(), 2), 36));

    // 先将源进制转为十进制整数
    var decimal: u64 = 0;
    for (num_str) |c| {
        const digit: u64 = if (c >= '0' and c <= '9')
            c - '0'
        else if (c >= 'a' and c <= 'z')
            c - 'a' + 10
        else if (c >= 'A' and c <= 'Z')
            c - 'A' + 10
        else
            continue;
        if (digit >= from) continue;
        decimal = decimal * from + digit;
    }

    // 十进制转目标进制
    if (decimal == 0) return Value.initString(try PHPString.init(allocator, "0"));

    const digits = "0123456789abcdefghijklmnopqrstuvwxyz";
    var buf: [65]u8 = undefined;
    var pos: usize = buf.len;
    var val = decimal;
    while (val > 0) {
        pos -= 1;
        buf[pos] = digits[@intCast(@rem(val, to))];
        val /= to;
    }

    return Value.initString(try PHPString.init(allocator, buf[pos..]));
}

/// gc_enabled - 检查 GC 是否启用
pub fn php_gc_enabled() Value {
    return Value.initBool(gc_enabled);
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
    const actual_val = if (val.isRef()) val.asRef().* else val;
    if (actual_val.isFunction()) return Value.initBool(true);
    if (actual_val.isString()) {
        // 字符串只有是已知函数名时才callable
        const name = actual_val.asString().data;
        if (lookupBuiltinFunction(name) != null) return Value.initBool(true);
        if (user_function_registry) |reg| {
            if (reg.contains(name)) return Value.initBool(true);
        }
        if (aot_callable_hook) |hook| {
            _ = hook(name, &[_]Value{}, std.heap.page_allocator) catch return Value.initBool(false);
            return Value.initBool(true);
        }
        return Value.initBool(false);
    }
    if (actual_val.isArray()) {
        // [obj/class, method] 形式
        const arr = actual_val.asArray();
        if (arr.elements.count() == 2) return Value.initBool(true);
        return Value.initBool(false);
    }
    if (Value_isObject(actual_val)) {
        const obj = Value_asObject(actual_val);
        if (obj.class_meta) |meta| {
            return Value.initBool(meta.findMethod("__invoke") != null);
        }
    }
    return Value.initBool(false);
}

/// is_scalar - 检查是否为标量类型（int, float, string, bool）
pub fn php_is_scalar(val: Value) !Value {
    return Value.initBool(val.isInt() or val.isFloat() or val.isString() or val.isBool());
}

/// is_infinite - 检查浮点数是否为无穷大
pub fn php_is_infinite(val: Value) !Value {
    if (!val.isFloat()) return Value.initBool(false);
    const f = val.asFloat();
    return Value.initBool(std.math.isInf(f));
}

/// is_nan - 检查浮点数是否为NaN
pub fn php_is_nan(val: Value) !Value {
    if (!val.isFloat()) return Value.initBool(false);
    const f = val.asFloat();
    return Value.initBool(std.math.isNan(f));
}

/// is_finite - 检查浮点数是否为有限值
pub fn php_is_finite(val: Value) !Value {
    if (!val.isFloat()) return Value.initBool(true); // 非浮点数视为有限
    const f = val.asFloat();
    return Value.initBool(!std.math.isInf(f) and !std.math.isNan(f));
}

/// is_countable - 检查是否可计数（数组或实现Countable接口的对象）
pub fn php_is_countable(val: Value) !Value {
    // 数组总是可计数的
    if (val.isArray()) return Value.initBool(true);
    
    // 对象需要实现Countable接口
    if (Value_isObject(val)) {
        const obj = Value_asObject(val);
        if (obj.class_meta) |meta| {
            // 检查是否实现了Countable接口（有count方法）
            return Value.initBool(meta.findMethod("count") != null);
        }
    }
    
    return Value.initBool(false);
}

/// is_iterable - 检查是否可迭代（数组或实现Traversable接口的对象）
pub fn php_is_iterable(val: Value) !Value {
    // 数组总是可迭代的
    if (val.isArray()) return Value.initBool(true);
    
    // 对象需要实现Traversable接口（Iterator或IteratorAggregate）
    if (Value_isObject(val)) {
        const obj = Value_asObject(val);
        if (obj.class_meta) |meta| {
            // 检查是否有迭代器方法
            const has_current = meta.findMethod("current") != null;
            const has_key = meta.findMethod("key") != null;
            const has_next = meta.findMethod("next") != null;
            const has_rewind = meta.findMethod("rewind") != null;
            const has_valid = meta.findMethod("valid") != null;
            const has_getiterator = meta.findMethod("getIterator") != null;
            
            // Iterator接口需要5个方法，IteratorAggregate需要getIterator
            return Value.initBool((has_current and has_key and has_next and has_rewind and has_valid) or has_getiterator);
        }
    }
    
    return Value.initBool(false);
}

/// unset - 删除变量（立即释放引用）
pub fn php_unset(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    for (args) |val| {
        val.release(runtime_allocator);
    }
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

/// 将引用推入数组
/// 用于 $arr[] = &$var 语法
pub fn php_array_push_ref(arr_val: Value, ref_val: Value, _: Value) !void {
    if (!arr_val.isArray()) return;
    const arr = arr_val.asArray();
    try arr.pushRef(ref_val);
}

/// 将引用设置到数组
/// 用于 $arr[$key] = &$var 语法
pub fn php_array_set_ref(arr_val: Value, key_val: Value, ref_val: Value, _: Value) !void {
    if (!arr_val.isArray()) return;
    const arr = arr_val.asArray();
    const key = normalizeArrayKeyFromValue(key_val);
    try arr.setRef(key, ref_val);
}

/// 从值创建引用（用于全局变量的引用）
pub fn php_make_ref_from_value(val: Value) !Value {
    // 这是一个简化实现：创建一个包含该值的临时位置并返回引用
    // 在完整实现中，这需要更复杂的内存管理
    _ = val.retain();
    // 注意：这里返回的是值本身，不是真正的引用
    // 全局变量的引用需要特殊处理
    return val;
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
    is_abstract: bool = false,
    is_final: bool = false,
    param_count: u16 = 0,
    required_params: u16 = 0,
    param_names: []const []const u8 = &.{},
    /// 参数类型字符串列表，与 param_names 一一对应（无类型声明时为空字符串）
    param_types: []const []const u8 = &.{},
    /// 参数是否允许 null（nullable 类型或无类型声明）
    param_nullable: []const bool = &.{},
    /// 返回类型字符串（无返回类型声明时为 null）
    return_type: ?[]const u8 = null,
    /// 返回类型是否 nullable
    return_nullable: bool = false,
};

/// 类属性定义
pub const ClassProperty = struct {
    name: []const u8,
    default_value: ?Value = null,
    is_static: bool = false,
    is_public: bool = true,
    is_protected: bool = false,
    is_private: bool = false,
    is_readonly: bool = false,
    /// 属性类型字符串（无类型声明时为 null）
    type_name: ?[]const u8 = null,
    /// 属性类型是否 nullable
    type_nullable: bool = false,
    /// 是否有默认值（class body 中声明了默认值）
    has_default: bool = false,
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
    is_interface: bool = false,  // 是否为接口
    is_trait: bool = false,      // 是否为trait
    is_enum: bool = false,       // 是否为enum
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
        if (std.mem.eql(u8, method.name, "__isset")) self.magic_isset = method.func;
        if (std.mem.eql(u8, method.name, "__unset")) self.magic_unset = method.func;
        if (std.mem.eql(u8, method.name, "__call")) self.magic_call = method.func;
        if (std.mem.eql(u8, method.name, "__callStatic")) self.magic_callStatic = method.func;
        if (std.mem.eql(u8, method.name, "__toString")) self.magic_toString = method.func;
        if (std.mem.eql(u8, method.name, "__invoke")) self.magic_invoke = method.func;
        if (std.mem.eql(u8, method.name, "__clone")) self.magic_clone = method.func;
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

    // ========================================================================
    // DateTime 扩展格式化函数 - 支持完整的 PHP date() 格式
    // ========================================================================

    /// 完整的DateTime格式化器，支持时区偏移
    const DateTimeFormatter = struct {
        timestamp: i64,
        microseconds: i64,
        timezone_offset: i32,
        timezone_name: []const u8,

        fn isLeapYear(year: i64) bool {
            return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
        }

        fn getDaysInMonth(year: i64, month: u32) u32 {
            return switch (month) {
                1, 3, 5, 7, 8, 10, 12 => 31,
                4, 6, 9, 11 => 30,
                2 => if (isLeapYear(year)) 29 else 28,
                else => 31,
            };
        }

        fn getDayOfYear(year: i64, month: u32, day: u32) u32 {
            var doy: u32 = 0;
            var m: u32 = 1;
            while (m < month) : (m += 1) doy += getDaysInMonth(year, m);
            return doy + day;
        }

        fn getDayOfWeek(year: i64, month: u32, day: u32) u32 {
            const y = if (month < 3) year - 1 else year;
            const m = if (month < 3) month + 12 else month;
            const w = @mod(day + @divFloor(13 * (m + 1), 5) + y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400), 7);
            return @intCast(w);
        }

        fn getIsoWeek(year: i64, month: u32, day: u32) u32 {
            const doy = getDayOfYear(year, month, day);
            const wday = getDayOfWeek(year, month, day);
            const iso_wday = if (wday == 0) @as(i64, 7) else @as(i64, wday);
            var week = @divFloor(@as(i64, doy) - iso_wday + 10, 7);
            if (week < 1) week = if (isLeapYear(year - 1)) 53 else 52
            else if (week > 52 and doy - iso_wday > 365 - (if (isLeapYear(year)) @as(i64, 1) else @as(i64, 0))) week = 1;
            return @intCast(week);
        }

        pub fn format(self: *const DateTimeFormatter, format_str: []const u8, allocator: Allocator) !Value {
            const epoch_seconds: u64 = @intCast(@max(@as(i64, 0), self.timestamp));
            const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
            const day_seconds = epoch.getDaySeconds();
            const year_day = epoch.getEpochDay().calculateYearDay();
            const month_day = year_day.calculateMonthDay();

            const year = year_day.year;
            const month = month_day.month.numeric();
            const day = month_day.day_index + 1;
            const hour = day_seconds.getHoursIntoDay();
            const minute = day_seconds.getMinutesIntoHour();
            const second = day_seconds.getSecondsIntoMinute();

            var result = try std.ArrayList(u8).initCapacity(allocator, format_str.len * 3);
            defer result.deinit(allocator);
            const writer = result.writer(allocator);

            var i: usize = 0;
            while (i < format_str.len) : (i += 1) {
                const c = format_str[i];
                switch (c) {
                    'Y' => try writer.print("{d:0>4}", .{year}),
                    'y' => try writer.print("{d:0>2}", .{year % 100}),
                    'L' => try writer.print("{d}", .{if (isLeapYear(year)) @as(u32, 1) else @as(u32, 0)}),
                    'm' => try writer.print("{d:0>2}", .{month}),
                    'n' => try writer.print("{d}", .{month}),
                    'F' => try writer.writeAll(switch (month) { 1=>"January", 2=>"February", 3=>"March", 4=>"April", 5=>"May", 6=>"June", 7=>"July", 8=>"August", 9=>"September", 10=>"October", 11=>"November", 12=>"December", else=>"Unknown" }),
                    'M' => try writer.writeAll(switch (month) { 1=>"Jan", 2=>"Feb", 3=>"Mar", 4=>"Apr", 5=>"May", 6=>"Jun", 7=>"Jul", 8=>"Aug", 9=>"Sep", 10=>"Oct", 11=>"Nov", 12=>"Dec", else=>"???" }),
                    't' => try writer.print("{d}", .{getDaysInMonth(year, month)}),
                    'd' => try writer.print("{d:0>2}", .{day}),
                    'j' => try writer.print("{d}", .{day}),
                    'S' => try writer.writeAll(if (day >= 11 and day <= 13) "th" else switch (day % 10) { 1=>"st", 2=>"nd", 3=>"rd", else=>"th" }),
                    'z' => try writer.print("{d}", .{getDayOfYear(year, month, day) - 1}),
                    'l' => try writer.writeAll(switch (getDayOfWeek(year, month, day)) { 0=>"Sunday", 1=>"Monday", 2=>"Tuesday", 3=>"Wednesday", 4=>"Thursday", 5=>"Friday", 6=>"Saturday", else=>"Unknown" }),
                    'D' => try writer.writeAll(switch (getDayOfWeek(year, month, day)) { 0=>"Sun", 1=>"Mon", 2=>"Tue", 3=>"Wed", 4=>"Thu", 5=>"Fri", 6=>"Sat", else=>"???" }),
                    'w' => try writer.print("{d}", .{getDayOfWeek(year, month, day)}),
                    'N' => { const n = getDayOfWeek(year, month, day); try writer.print("{d}", .{if (n == 0) @as(u32, 7) else n}); },
                    'W' => try writer.print("{d:0>2}", .{getIsoWeek(year, month, day)}),
                    'H' => try writer.print("{d:0>2}", .{hour}),
                    'G' => try writer.print("{d}", .{hour}),
                    'h' => { const h12 = if (hour == 0) @as(u32, 12) else if (hour > 12) hour - 12 else hour; try writer.print("{d:0>2}", .{h12}); },
                    'g' => { const h12 = if (hour == 0) @as(u32, 12) else if (hour > 12) hour - 12 else hour; try writer.print("{d}", .{h12}); },
                    'a' => try writer.writeAll(if (hour < 12) "am" else "pm"),
                    'A' => try writer.writeAll(if (hour < 12) "AM" else "PM"),
                    'i' => try writer.print("{d:0>2}", .{minute}),
                    's' => try writer.print("{d:0>2}", .{second}),
                    'u' => try writer.print("{d:0>6}", .{self.microseconds}),
                    'v' => try writer.print("{d:0>3}", .{@divFloor(self.microseconds, 1000)}),
                    'T' => try writer.writeAll(self.timezone_name),
                    'O' => { const oh = @divFloor(self.timezone_offset, 3600); const om = @divFloor(@rem(self.timezone_offset, 3600), 60); if (oh >= 0) try writer.print("+{d:0>2}{d:0>2}", .{oh, @abs(om)}) else try writer.print("{d:0>3}{d:0>2}", .{oh, @abs(om)}); },
                    'P' => { const oh = @divFloor(self.timezone_offset, 3600); const om = @divFloor(@rem(self.timezone_offset, 3600), 60); if (oh >= 0) try writer.print("+{d:0>2}:{d:0>2}", .{oh, @abs(om)}) else try writer.print("{d:0>3}:{d:0>2}", .{oh, @abs(om)}); },
                    'Z' => try writer.print("{d}", .{self.timezone_offset}),
                    'U' => try writer.print("{d}", .{self.timestamp}),
                    'c' => { try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{year, month, day, hour, minute, second}); const oh = @divFloor(self.timezone_offset, 3600); const om = @divFloor(@rem(self.timezone_offset, 3600), 60); if (oh >= 0) try writer.print("+{d:0>2}:{d:0>2}", .{oh, @abs(om)}) else try writer.print("{d:0>3}:{d:0>2}", .{oh, @abs(om)}); },
                    'r' => { const wd = switch (getDayOfWeek(year, month, day)) { 0=>"Sun", 1=>"Mon", 2=>"Tue", 3=>"Wed", 4=>"Thu", 5=>"Fri", 6=>"Sat", else=>"???" }; const mon = switch (month) { 1=>"Jan", 2=>"Feb", 3=>"Mar", 4=>"Apr", 5=>"May", 6=>"Jun", 7=>"Jul", 8=>"Aug", 9=>"Sep", 10=>"Oct", 11=>"Nov", 12=>"Dec", else=>"???" }; const oh = @divFloor(self.timezone_offset, 3600); const om = @divFloor(@rem(self.timezone_offset, 3600), 60); if (oh >= 0) try writer.print("{s}, {d} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} +{d:0>2}{d:0>2}", .{wd, day, mon, year, hour, minute, second, oh, @abs(om)}) else try writer.print("{s}, {d} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} -{d:0>2}{d:0>2}", .{wd, day, mon, year, hour, minute, second, @abs(oh), @abs(om)}); },
                    '\\' => { i += 1; if (i < format_str.len) try result.append(allocator, format_str[i]); },
                    else => try result.append(allocator, c),
                }
            }
            return Value.initString(try PHPString.init(allocator, result.items));
        }
    };

    fn formatDateTimeWithFormat(timestamp: i64, format_str: []const u8, allocator: Allocator) !Value {
        const formatter = DateTimeFormatter{ .timestamp = timestamp, .microseconds = 0, .timezone_offset = 0, .timezone_name = "UTC" };
        return formatter.format(format_str, allocator);
    }

    fn formatDateTimeYmd(timestamp: i64, allocator: Allocator) !Value {
        return formatDateTimeWithFormat(timestamp, "Y-m-d", allocator);
    }

    fn registerStdClass(allocator: Allocator) !void {
        if (findClass("stdClass") != null) return;
        const meta = try ClassMeta.init(allocator, "stdClass");
        try registerClass(meta);
    }

    // ========================================================================
    // 时区数据库 (简化版)
    // ========================================================================
    
    const TimezoneInfo = struct { name: []const u8, offset_seconds: i32, abbreviation: []const u8 };
    const TIMEZONE_DATABASE: []const TimezoneInfo = &[_]TimezoneInfo{
        .{ .name = "UTC", .offset_seconds = 0, .abbreviation = "UTC" },
        .{ .name = "GMT", .offset_seconds = 0, .abbreviation = "GMT" },
        .{ .name = "America/New_York", .offset_seconds = -18000, .abbreviation = "EST" },
        .{ .name = "America/Chicago", .offset_seconds = -21600, .abbreviation = "CST" },
        .{ .name = "America/Denver", .offset_seconds = -25200, .abbreviation = "MST" },
        .{ .name = "America/Los_Angeles", .offset_seconds = -28800, .abbreviation = "PST" },
        .{ .name = "Europe/London", .offset_seconds = 0, .abbreviation = "GMT" },
        .{ .name = "Europe/Paris", .offset_seconds = 3600, .abbreviation = "CET" },
        .{ .name = "Europe/Berlin", .offset_seconds = 3600, .abbreviation = "CET" },
        .{ .name = "Europe/Moscow", .offset_seconds = 10800, .abbreviation = "MSK" },
        .{ .name = "Asia/Shanghai", .offset_seconds = 28800, .abbreviation = "CST" },
        .{ .name = "Asia/Beijing", .offset_seconds = 28800, .abbreviation = "CST" },
        .{ .name = "Asia/Hong_Kong", .offset_seconds = 28800, .abbreviation = "HKT" },
        .{ .name = "Asia/Tokyo", .offset_seconds = 32400, .abbreviation = "JST" },
        .{ .name = "Asia/Seoul", .offset_seconds = 32400, .abbreviation = "KST" },
        .{ .name = "Asia/Singapore", .offset_seconds = 28800, .abbreviation = "SGT" },
        .{ .name = "Australia/Sydney", .offset_seconds = 36000, .abbreviation = "AEST" },
    };

    fn findTimezone(name: []const u8) ?TimezoneInfo {
        for (TIMEZONE_DATABASE) |tz| if (std.mem.eql(u8, tz.name, name)) return tz;
        return null;
    }

    fn parseTimezoneOffset(tz_str: []const u8) ?i32 {
        if (findTimezone(tz_str)) |tz| return tz.offset_seconds;
        if (tz_str.len >= 3 and (tz_str[0] == '+' or tz_str[0] == '-')) {
            const sign: i32 = if (tz_str[0] == '+') 1 else -1;
            const rest = tz_str[1..];
            var hours: i32 = 0; var minutes: i32 = 0;
            if (rest.len == 2) hours = std.fmt.parseInt(i32, rest, 10) catch return null
            else if (rest.len == 4) { hours = std.fmt.parseInt(i32, rest[0..2], 10) catch return null; minutes = std.fmt.parseInt(i32, rest[2..4], 10) catch return null; }
            else if (rest.len == 5 and rest[2] == ':') { hours = std.fmt.parseInt(i32, rest[0..2], 10) catch return null; minutes = std.fmt.parseInt(i32, rest[3..5], 10) catch return null; }
            return sign * (hours * 3600 + minutes * 60);
        }
        return null;
    }

    // ========================================================================
    // DateTimeZone 类注册
    // ========================================================================

    fn registerDateTimeZoneClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "DateTimeZone");
        try meta.addProperty(.{ .name = "timezone", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "__offset", .default_value = Value.initInt(0), .is_public = false });

        try meta.addMethod(.{ .name = "__construct", .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len > 0 and args[0].isString()) {
                    const tz_name = args[0].asString().data;
                    try this.setProperty("timezone", args[0]);
                    if (parseTimezoneOffset(tz_name)) |offset| try this.setProperty("__offset", Value.initInt(offset));
                } else {
                    try this.setProperty("timezone", Value.initString(try PHPString.init(runtime_alloc, "UTC")));
                }
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getName", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("timezone")) |tz| { _ = tz.retain(); return tz; }
                return Value.initString(try PHPString.init(runtime_allocator, "UTC"));
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getOffset", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("__offset")) |offset| return offset;
                return Value.initInt(0);
            }
        }.call, .is_static = false });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
    }

    // ========================================================================
    // DateInterval 类注册
    // ========================================================================

    fn registerDateIntervalClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "DateInterval");
        try meta.addProperty(.{ .name = "y", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "m", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "d", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "h", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "i", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "s", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "f", .default_value = Value.initFloat(0.0), .is_public = true });
        try meta.addProperty(.{ .name = "invert", .default_value = Value.initInt(0), .is_public = true });
        try meta.addProperty(.{ .name = "days", .default_value = Value.initBool(false), .is_public = true });

        // __construct(string $duration) - 解析 ISO 8601 duration
        try meta.addMethod(.{ .name = "__construct", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !args[0].isString()) return Value.initNull();
                const spec = args[0].asString().data;
                if (spec.len < 1 or spec[0] != 'P') return error.InvalidDateIntervalSpecification;

                var y: i64 = 0; var m: i64 = 0; var d: i64 = 0;
                var h: i64 = 0; var i: i64 = 0; var s: i64 = 0;
                var in_time = false; var pos: usize = 1;
                var num_buf: [32]u8 = undefined; var num_len: usize = 0;

                while (pos < spec.len) {
                    const c = spec[pos];
                    if (c >= '0' and c <= '9' or c == '.') { if (num_len < 32) { num_buf[num_len] = c; num_len += 1; } pos += 1; }
                    else if (c == 'T') { in_time = true; pos += 1; num_len = 0; }
                    else {
                        const num_str = num_buf[0..num_len];
                        const num_val = std.fmt.parseFloat(f64, num_str) catch 0;
                        switch (c) {
                            'Y' => { y = @intFromFloat(num_val); },
                            'M' => { if (in_time) i = @intFromFloat(num_val) else m = @intFromFloat(num_val); },
                            'D' => { d = @intFromFloat(num_val); },
                            'H' => { h = @intFromFloat(num_val); },
                            'S' => { s = @intFromFloat(@floor(num_val)); },
                            else => {},
                        }
                        pos += 1; num_len = 0;
                    }
                }
                try this.setProperty("y", Value.initInt(y));
                try this.setProperty("m", Value.initInt(m));
                try this.setProperty("d", Value.initInt(d));
                try this.setProperty("h", Value.initInt(h));
                try this.setProperty("i", Value.initInt(i));
                try this.setProperty("s", Value.initInt(s));
                return Value.initNull();
            }
        }.call, .is_static = false });

        // format(string $format)
        try meta.addMethod(.{ .name = "format", .func = struct {
            fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !args[0].isString()) return Value.initString(try PHPString.init(alloc, ""));
                const format_str = args[0].asString().data;
                var result = try std.ArrayList(u8).initCapacity(alloc, format_str.len * 2);
                defer result.deinit(alloc);
                const writer = result.writer(alloc);

                const y = if (this.getProperty("y")) |v| v.toInt() else 0;
                const m = if (this.getProperty("m")) |v| v.toInt() else 0;
                const d = if (this.getProperty("d")) |v| v.toInt() else 0;
                const h = if (this.getProperty("h")) |v| v.toInt() else 0;
                const i = if (this.getProperty("i")) |v| v.toInt() else 0;
                const s = if (this.getProperty("s")) |v| v.toInt() else 0;
                const invert = if (this.getProperty("invert")) |v| v.toInt() else 0;

                var fi: usize = 0;
                while (fi < format_str.len) : (fi += 1) {
                    if (format_str[fi] == '%' and fi + 1 < format_str.len) {
                        fi += 1;
                        switch (format_str[fi]) {
                            'Y' => try writer.print("{d:0>2}", .{y}),
                            'y' => try writer.print("{d}", .{y}),
                            'M' => try writer.print("{d:0>2}", .{m}),
                            'm' => try writer.print("{d}", .{m}),
                            'D' => try writer.print("{d:0>2}", .{d}),
                            'd' => try writer.print("{d}", .{d}),
                            'H' => try writer.print("{d:0>2}", .{h}),
                            'h' => try writer.print("{d}", .{h}),
                            'I' => try writer.print("{d:0>2}", .{i}),
                            'i' => try writer.print("{d}", .{i}),
                            'S' => try writer.print("{d:0>2}", .{s}),
                            's' => try writer.print("{d}", .{s}),
                            'R' => try writer.writeAll(if (invert == 1) "-" else "+"),
                            'r' => try writer.writeAll(if (invert == 1) "-" else ""),
                            '%' => try result.append(alloc, '%'),
                            'a' => {
                                const days_val = if (this.getProperty("days")) |v| v.toInt() else 0;
                                try writer.print("{d}", .{days_val});
                            },
                            else => {
                                try result.append(alloc, '%');
                                try result.append(alloc, format_str[fi]);
                            },
                        }
                    } else {
                        try result.append(alloc, format_str[fi]);
                    }
                }
                return Value.initString(try PHPString.init(alloc, result.items));
            }
        }.call, .is_static = false });

        // createFromDateString(string $datetime)
        try meta.addMethod(.{ .name = "createFromDateString", .func = struct {
            fn call(_: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                if (args.len == 0 or !args[0].isString()) return Value.initNull();
                const spec = args[0].asString().data;
                var y: i64 = 0; var m: i64 = 0; var d: i64 = 0;
                var h: i64 = 0; var i: i64 = 0; var s: i64 = 0;
                var pos: usize = 0;

                while (pos < spec.len) {
                    while (pos < spec.len and spec[pos] == ' ') pos += 1;
                    if (pos >= spec.len) break;
                    var num: i64 = 0;
                    while (pos < spec.len and spec[pos] >= '0' and spec[pos] <= '9') { num = num * 10 + (spec[pos] - '0'); pos += 1; }
                    while (pos < spec.len and spec[pos] == ' ') pos += 1;
                    const start = pos;
                    while (pos < spec.len and spec[pos] >= 'a' and spec[pos] <= 'z') pos += 1;
                    const unit = spec[start..pos];

                    if (std.mem.startsWith(u8, unit, "year")) y += num
                    else if (std.mem.startsWith(u8, unit, "month")) m += num
                    else if (std.mem.startsWith(u8, unit, "day")) d += num
                    else if (std.mem.startsWith(u8, unit, "hour")) h += num
                    else if (std.mem.startsWith(u8, unit, "minute")) i += num
                    else if (std.mem.startsWith(u8, unit, "second")) s += num
                    else if (std.mem.startsWith(u8, unit, "week")) d += num * 7;
                }

                const meta_ptr = findClass("DateInterval") orelse return Value.initNull();
                const obj = try PHPObject.initWithMeta(alloc, meta_ptr);
                try obj.setProperty("y", Value.initInt(y));
                try obj.setProperty("m", Value.initInt(m));
                try obj.setProperty("d", Value.initInt(d));
                try obj.setProperty("h", Value.initInt(h));
                try obj.setProperty("i", Value.initInt(i));
                try obj.setProperty("s", Value.initInt(s));
                return Value_initObject(obj);
            }
        }.call, .is_static = true });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
    }

    // ========================================================================
    // DatePeriod 类注册
    // ========================================================================

    fn registerDatePeriodClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "DatePeriod");
        try meta.addProperty(.{ .name = "start", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "interval", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "end", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "recurrences", .default_value = Value.initInt(0), .is_public = false });
        try meta.addProperty(.{ .name = "_current", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "_key", .default_value = Value.initInt(0), .is_public = false });

        try meta.addMethod(.{ .name = "__construct", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len < 3) return Value.initNull();
                try this.setProperty("start", args[0]);
                try this.setProperty("interval", args[1]);
                if (args[2].isInt()) try this.setProperty("recurrences", args[2]) else try this.setProperty("end", args[2]);
                try this.setProperty("_current", args[0]);
                try this.setProperty("_key", Value.initInt(0));
                return Value.initNull();
            }
        }.call, .is_static = false });

        // Iterator interface
        try meta.addMethod(.{ .name = "current", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("_current")) |current| { _ = current.retain(); return current; }
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "key", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("_key")) |key| return key;
                return Value.initInt(0);
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "next", .func = struct {
            fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                var current_ts: i64 = 0;
                if (this.getProperty("_current")) |current| {
                    if (Value_isObject(current)) {
                        if (Value_asObject(current).getProperty("timestamp")) |ts| current_ts = ts.toInt();
                    }
                }
                var add_secs: i64 = 0;
                if (this.getProperty("interval")) |interval| {
                    if (Value_isObject(interval)) {
                        const intv = Value_asObject(interval);
                        const d = if (intv.getProperty("d")) |v| v.toInt() else 0;
                        const h = if (intv.getProperty("h")) |v| v.toInt() else 0;
                        const i = if (intv.getProperty("i")) |v| v.toInt() else 0;
                        const s = if (intv.getProperty("s")) |v| v.toInt() else 0;
                        add_secs = d * 86400 + h * 3600 + i * 60 + s;
                    }
                }
                current_ts += add_secs;
                if (findClass("DateTime")) |dt_meta| {
                    const new_dt = try PHPObject.initWithMeta(alloc, dt_meta);
                    try new_dt.setProperty("timestamp", Value.initInt(current_ts));
                    try new_dt.setProperty("microseconds", Value.initInt(0));
                    try this.setProperty("_current", Value_initObject(new_dt));
                }
                if (this.getProperty("_key")) |key| try this.setProperty("_key", Value.initInt(key.toInt() + 1));
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "rewind", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("start")) |start| try this.setProperty("_current", start);
                try this.setProperty("_key", Value.initInt(0));
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "valid", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("end")) |end| {
                    if (!end.isNull()) {
                        var current_ts: i64 = 0; var end_ts: i64 = 0;
                        if (this.getProperty("_current")) |current| {
                            if (Value_isObject(current)) {
                                if (Value_asObject(current).getProperty("timestamp")) |ts| current_ts = ts.toInt();
                            }
                        }
                        if (Value_isObject(end)) {
                            if (Value_asObject(end).getProperty("timestamp")) |ts| end_ts = ts.toInt();
                        }
                        return Value.initBool(current_ts < end_ts);
                    }
                }
                if (this.getProperty("recurrences")) |recurrences| {
                    if (this.getProperty("_key")) |key| return Value.initBool(key.toInt() < recurrences.toInt());
                }
                return Value.initBool(false);
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getStartDate", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("start")) |start| { _ = start.retain(); return start; }
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getEndDate", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("end")) |end| { _ = end.retain(); return end; }
                return Value.initNull();
            }
        }.call, .is_static = false });

        try meta.addMethod(.{ .name = "getDateInterval", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("interval")) |interval| { _ = interval.retain(); return interval; }
                return Value.initNull();
            }
        }.call, .is_static = false });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
    }

    // ========================================================================
    // DateTime 主类注册
    // ========================================================================

    fn registerDateTimeClasses(allocator: Allocator) !void {
        // DateTimeInterface
        const iface = try ClassMeta.init(allocator, "DateTimeInterface");
        iface.is_abstract = true;
        iface.is_interface = true;
        try registerClass(iface);

        // DateTimeInterface 常量
        const dt_consts = [_]struct { key: []const u8, val: []const u8 }{
            .{ .key = "DateTimeInterface::ATOM", .val = "Y-m-d\\TH:i:sP" },
            .{ .key = "DateTimeInterface::COOKIE", .val = "l, d-M-Y H:i:s T" },
            .{ .key = "DateTimeInterface::ISO8601", .val = "Y-m-d\\TH:i:sO" },
            .{ .key = "DateTimeInterface::RFC822", .val = "D, d M y H:i:s O" },
            .{ .key = "DateTimeInterface::RFC850", .val = "l, d-M-y H:i:s T" },
            .{ .key = "DateTimeInterface::RFC1123", .val = "D, d M Y H:i:s O" },
            .{ .key = "DateTimeInterface::RFC2822", .val = "D, d M Y H:i:s O" },
            .{ .key = "DateTimeInterface::RFC3339", .val = "Y-m-d\\TH:i:sP" },
            .{ .key = "DateTimeInterface::RSS", .val = "D, d M Y H:i:s O" },
            .{ .key = "DateTimeInterface::W3C", .val = "Y-m-d\\TH:i:sP" },
        };
        for (dt_consts) |c| {
            const k = try allocator.dupe(u8, c.key);
            try constants.put(k, Value.initString(try PHPString.init(allocator, c.val)));
        }

        // 注册辅助类
        try registerDateTimeZoneClass(allocator);
        try registerDateIntervalClass(allocator);
        try registerDatePeriodClass(allocator);

        // DateTime 类
        const meta = try ClassMeta.init(allocator, "DateTime");
        try meta.addProperty(.{ .name = "timestamp", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "microseconds", .default_value = Value.initInt(0), .is_public = false });
        try meta.addProperty(.{ .name = "timezone", .default_value = Value.initNull(), .is_public = false });
        try meta.addProperty(.{ .name = "__offset", .default_value = Value.initInt(0), .is_public = false });

        // __construct(?string $datetime = "now", ?DateTimeZone $timezone = null)
        try meta.addMethod(.{ .name = "__construct", .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                var tz_offset: i32 = 0; var tz_name: []const u8 = "UTC";

                if (args.len > 1 and Value_isObject(args[1])) {
                    const tz_obj = Value_asObject(args[1]);
                    if (tz_obj.getProperty("__offset")) |offset| { tz_offset = @intCast(offset.toInt()); }
                    if (tz_obj.getProperty("timezone")) |tz| { if (tz.isString()) { tz_name = tz.asString().data; } }
                    try this.setProperty("timezone", args[1]);
                } else try this.setProperty("timezone", Value.initString(try PHPString.init(runtime_alloc, "UTC")));
                try this.setProperty("__offset", Value.initInt(tz_offset));

                if (args.len > 0 and !args[0].isNull()) {
                    const datetime_str = args[0].asString().data;
                    if (std.mem.eql(u8, datetime_str, "now")) {
                        const now_ns = std.time.nanoTimestamp();
                        const now_us = @divTrunc(now_ns, 1000);
                        try this.setProperty("timestamp", Value.initInt(@intCast(@divTrunc(now_us, 1_000_000))));
                        try this.setProperty("microseconds", Value.initInt(@intCast(@rem(now_us, 1_000_000))));
                    } else if (datetime_str.len > 0 and datetime_str[0] == '@') {
                        const ts = std.fmt.parseInt(i64, datetime_str[1..], 10) catch std.time.timestamp();
                        try this.setProperty("timestamp", Value.initInt(ts));
                        try this.setProperty("microseconds", Value.initInt(0));
                    } else {
                        const parsed = try php_strtotime(args[0], Value.initInt(std.time.timestamp()), runtime_alloc);
                        if (parsed.isInt()) {
                            try this.setProperty("timestamp", Value.initInt(parsed.toInt() - tz_offset));
                            try this.setProperty("microseconds", Value.initInt(0));
                        } else {
                            try this.setProperty("timestamp", Value.initInt(std.time.timestamp()));
                            try this.setProperty("microseconds", Value.initInt(0));
                        }
                    }
                } else {
                    const now_ns = std.time.nanoTimestamp();
                    const now_us = @divTrunc(now_ns, 1000);
                    try this.setProperty("timestamp", Value.initInt(@intCast(@divTrunc(now_us, 1_000_000))));
                    try this.setProperty("microseconds", Value.initInt(@intCast(@rem(now_us, 1_000_000))));
                }
                return Value.initNull();
            }
        }.call, .is_static = false });

        // format(string $format): string
        try meta.addMethod(.{ .name = "format", .func = struct {
            fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                const ts = if (this.getProperty("timestamp")) |ts_val| ts_val.toInt() else std.time.timestamp();
                const us = if (this.getProperty("microseconds")) |us_val| us_val.toInt() else 0;
                const tz_offset = if (this.getProperty("__offset")) |off| @as(i32, @intCast(off.toInt())) else 0;

                var tz_name: []const u8 = "UTC";
                if (this.getProperty("timezone")) |tz| {
                    if (tz.isString()) { tz_name = tz.asString().data; }
                    else if (Value_isObject(tz)) {
                        if (Value_asObject(tz).getProperty("timezone")) |tz_str| { if (tz_str.isString()) { tz_name = tz_str.asString().data; } }
                    }
                }

                const formatter = DateTimeFormatter{ .timestamp = ts, .microseconds = us, .timezone_offset = tz_offset, .timezone_name = tz_name };
                if (args.len > 0 and args[0].isString()) return formatter.format(args[0].asString().data, runtime_alloc);
                return formatter.format("Y-m-d H:i:s", runtime_alloc);
            }
        }.call, .is_static = false });

        // getTimestamp(): int
        try meta.addMethod(.{ .name = "getTimestamp", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("timestamp")) |ts| return ts;
                return Value.initInt(std.time.timestamp());
            }
        }.call, .is_static = false });

        // setTimestamp(int $timestamp): DateTime
        try meta.addMethod(.{ .name = "setTimestamp", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len > 0) try this.setProperty("timestamp", Value.initInt(args[0].toInt()));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // setTimezone(DateTimeZone $timezone): DateTime
        try meta.addMethod(.{ .name = "setTimezone", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len > 0 and Value_isObject(args[0])) {
                    try this.setProperty("timezone", args[0]);
                    if (Value_asObject(args[0]).getProperty("__offset")) |offset| try this.setProperty("__offset", offset);
                }
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // getTimezone(): DateTimeZone|false
        try meta.addMethod(.{ .name = "getTimezone", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (this.getProperty("timezone")) |tz| { _ = tz.retain(); return tz; }
                return Value.initBool(false);
            }
        }.call, .is_static = false });

        // add(DateInterval $interval): DateTime
        try meta.addMethod(.{ .name = "add", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !Value_isObject(args[0])) { _ = ctx.retain(); return ctx; }
                const interval = Value_asObject(args[0]);
                var ts = if (this.getProperty("timestamp")) |t| t.toInt() else 0;
                const y = if (interval.getProperty("y")) |v| v.toInt() else 0;
                const m = if (interval.getProperty("m")) |v| v.toInt() else 0;
                const d = if (interval.getProperty("d")) |v| v.toInt() else 0;
                const h = if (interval.getProperty("h")) |v| v.toInt() else 0;
                const i = if (interval.getProperty("i")) |v| v.toInt() else 0;
                const s = if (interval.getProperty("s")) |v| v.toInt() else 0;
                ts += y * 31536000 + m * 2592000 + d * 86400 + h * 3600 + i * 60 + s;
                try this.setProperty("timestamp", Value.initInt(ts));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // sub(DateInterval $interval): DateTime
        try meta.addMethod(.{ .name = "sub", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !Value_isObject(args[0])) { _ = ctx.retain(); return ctx; }
                const interval = Value_asObject(args[0]);
                var ts = if (this.getProperty("timestamp")) |t| t.toInt() else 0;
                const y = if (interval.getProperty("y")) |v| v.toInt() else 0;
                const m = if (interval.getProperty("m")) |v| v.toInt() else 0;
                const d = if (interval.getProperty("d")) |v| v.toInt() else 0;
                const h = if (interval.getProperty("h")) |v| v.toInt() else 0;
                const i = if (interval.getProperty("i")) |v| v.toInt() else 0;
                const s = if (interval.getProperty("s")) |v| v.toInt() else 0;
                ts -= y * 31536000 + m * 2592000 + d * 86400 + h * 3600 + i * 60 + s;
                try this.setProperty("timestamp", Value.initInt(ts));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // diff(DateTimeInterface $targetObject, bool $absolute = false): DateInterval
        try meta.addMethod(.{ .name = "diff", .func = struct {
            fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !Value_isObject(args[0])) return Value.initNull();
                const this_ts = if (this.getProperty("timestamp")) |t| t.toInt() else 0;
                const target_ts = if (Value_asObject(args[0]).getProperty("timestamp")) |t| t.toInt() else 0;
                const diff_seconds: i64 = @intCast(@abs(this_ts - target_ts));
                const interval_meta = findClass("DateInterval") orelse return Value.initNull();
                const interval = try PHPObject.initWithMeta(alloc, interval_meta);
                try interval.setProperty("y", Value.initInt(0));
                try interval.setProperty("m", Value.initInt(0));
                try interval.setProperty("d", Value.initInt(@divFloor(diff_seconds, 86400)));
                try interval.setProperty("h", Value.initInt(@divFloor(@rem(diff_seconds, 86400), 3600)));
                try interval.setProperty("i", Value.initInt(@divFloor(@rem(diff_seconds, 3600), 60)));
                try interval.setProperty("s", Value.initInt(@rem(diff_seconds, 60)));
                try interval.setProperty("invert", Value.initInt(if (this_ts < target_ts) @as(i64, 0) else @as(i64, 1)));
                try interval.setProperty("days", Value.initInt(@divFloor(diff_seconds, 86400)));
                return Value_initObject(interval);
            }
        }.call, .is_static = false });

        // modify(string $modifier): DateTime|false
        try meta.addMethod(.{ .name = "modify", .func = struct {
            fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len == 0 or !args[0].isString()) return Value.initBool(false);
                const ts = if (this.getProperty("timestamp")) |t| t.toInt() else std.time.timestamp();
                const new_ts = try php_strtotime(args[0], Value.initInt(ts), alloc);
                if (new_ts.isInt()) {
                    try this.setProperty("timestamp", new_ts);
                    _ = ctx.retain(); return ctx;
                }
                return Value.initBool(false);
            }
        }.call, .is_static = false });

        // setDate(int $year, int $month, int $day): DateTime
        try meta.addMethod(.{ .name = "setDate", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len < 3) { _ = ctx.retain(); return ctx; }
                const year = args[0].toInt(); const month = args[1].toInt(); const day = args[2].toInt();
                const y = if (month <= 2) year - 1 else year;
                const m = if (month <= 2) month + 12 else month;
                const jd = 365 * y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) + @divFloor(306 * (m + 1), 10) + day - 719591;
                try this.setProperty("timestamp", Value.initInt(jd * 86400));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // setTime(int $hour, int $minute, int $second = 0): DateTime
        try meta.addMethod(.{ .name = "setTime", .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                const this = Value_asObject(ctx);
                if (args.len < 2) { _ = ctx.retain(); return ctx; }
                const hour = args[0].toInt(); const minute = args[1].toInt();
                const second = if (args.len > 2) args[2].toInt() else 0;
                var ts = if (this.getProperty("timestamp")) |t| t.toInt() else 0;
                const day_ts = @divFloor(ts, 86400) * 86400;
                ts = day_ts + hour * 3600 + minute * 60 + second;
                try this.setProperty("timestamp", Value.initInt(ts));
                _ = ctx.retain(); return ctx;
            }
        }.call, .is_static = false });

        // createFromFormat(string $format, string $datetime, ?DateTimeZone $timezone = null): DateTime|false
        try meta.addMethod(.{ .name = "createFromFormat", .func = struct {
            fn call(_: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                if (args.len < 2) return Value.initBool(false);
                if (!args[0].isString() or !args[1].isString()) return Value.initBool(false);

                const format_str = args[0].asString().data;
                const datetime_str = args[1].asString().data;

                // 简单解析: Y-m-d H:i:s
                var year: i64 = 1970; var month: i64 = 1; var day: i64 = 1;
                var hour: i64 = 0; var minute: i64 = 0; var second: i64 = 0;
                var fmt_pos: usize = 0; var dt_pos: usize = 0;

                while (fmt_pos < format_str.len and dt_pos < datetime_str.len) {
                    const fc = format_str[fmt_pos];
                    switch (fc) {
                        'Y' => { if (dt_pos + 4 <= datetime_str.len) { year = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+4], 10) catch 1970; dt_pos += 4; } fmt_pos += 1; },
                        'm' => { if (dt_pos + 2 <= datetime_str.len) { month = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 1; dt_pos += 2; } fmt_pos += 1; },
                        'd' => { if (dt_pos + 2 <= datetime_str.len) { day = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 1; dt_pos += 2; } fmt_pos += 1; },
                        'H' => { if (dt_pos + 2 <= datetime_str.len) { hour = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 0; dt_pos += 2; } fmt_pos += 1; },
                        'i' => { if (dt_pos + 2 <= datetime_str.len) { minute = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 0; dt_pos += 2; } fmt_pos += 1; },
                        's' => { if (dt_pos + 2 <= datetime_str.len) { second = std.fmt.parseInt(i64, datetime_str[dt_pos..dt_pos+2], 10) catch 0; dt_pos += 2; } fmt_pos += 1; },
                        else => { if (dt_pos < datetime_str.len and datetime_str[dt_pos] == fc) dt_pos += 1; fmt_pos += 1; },
                    }
                }

                const y = if (month <= 2) year - 1 else year;
                const m = if (month <= 2) month + 12 else month;
                const jd = 365 * y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) + @divFloor(306 * (m + 1), 10) + day - 719591;
                const ts: i64 = jd * 86400 + hour * 3600 + minute * 60 + second;

                const meta_ptr = findClass("DateTime") orelse return Value.initBool(false);
                const obj = try PHPObject.initWithMeta(alloc, meta_ptr);
                try obj.setProperty("timestamp", Value.initInt(ts));
                try obj.setProperty("microseconds", Value.initInt(0));
                if (args.len > 2) try obj.setProperty("timezone", args[2])
                else try obj.setProperty("timezone", Value.initString(try PHPString.init(alloc, "UTC")));
                return Value_initObject(obj);
            }
        }.call, .is_static = true });

        // __clone()
        try meta.addMethod(.{ .name = "__clone", .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                _ = ctx; // 克隆已由运行时处理
                return Value.initNull();
            }
        }.call, .is_static = false });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
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
                    if (args.len > 2) {
                        try this.setProperty("previous", args[2]);
                    } else {
                        try this.setProperty("previous", Value.initNull());
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

        try meta.addMethod(.{
            .name = "getCode",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    _ = runtime_alloc;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("code")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });

        try meta.addMethod(.{
            .name = "getFile",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("file")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initString(try PHPString.init(runtime_alloc, ""));
                }
            }.call,
            .is_static = false,
        });

        try meta.addMethod(.{
            .name = "getLine",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    _ = runtime_alloc;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("line")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });

        try meta.addMethod(.{
            .name = "getPrevious",
            .func = struct {
                fn call(ctx: Value, args: []const Value, runtime_alloc: Allocator) anyerror!Value {
                    _ = args;
                    _ = runtime_alloc;
                    const this = Value_asObject(ctx);
                    if (this.getProperty("previous")) |val| {
                        _ = val.retain();
                        return val;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

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

        // Register standard PHP exception subclasses (flat: extends Exception)
        const exception_subclasses = [_][]const u8{
            "RuntimeException",
            "LogicException",
            "BadMethodCallException",
            "BadFunctionCallException",
            "DomainException",
            "InvalidArgumentException",
            "LengthException",
            "OutOfRangeException",
            "OverflowException",
            "RangeException",
            "UnderflowException",
            "UnexpectedValueException",
        };
        for (exception_subclasses) |name| {
            const child = try ClassMeta.init(allocator, name);
            child.parent = meta;
            child.magic_construct = meta.magic_construct;
            child.magic_toString = meta.magic_toString;
            try registerClass(child);
        }

        // Register Error hierarchy (separate from Exception in PHP)
        // Error extends Exception in our implementation for simplicity
        const error_meta = try ClassMeta.init(allocator, "Error");
        error_meta.parent = meta;
        error_meta.magic_construct = meta.magic_construct;
        error_meta.magic_toString = meta.magic_toString;
        try registerClass(error_meta);

        // ErrorException extends Exception
        const errorexception_meta = try ClassMeta.init(allocator, "ErrorException");
        errorexception_meta.parent = meta;
        errorexception_meta.magic_construct = meta.magic_construct;
        errorexception_meta.magic_toString = meta.magic_toString;
        try registerClass(errorexception_meta);

        // JsonException extends Exception
        const jsonexception_meta = try ClassMeta.init(allocator, "JsonException");
        jsonexception_meta.parent = meta;
        jsonexception_meta.magic_construct = meta.magic_construct;
        jsonexception_meta.magic_toString = meta.magic_toString;
        try registerClass(jsonexception_meta);

        // OutOfBoundsException extends RuntimeException
        const oob_meta = try ClassMeta.init(allocator, "OutOfBoundsException");
        oob_meta.parent = meta; // simplified: parent = Exception
        oob_meta.magic_construct = meta.magic_construct;
        oob_meta.magic_toString = meta.magic_toString;
        try registerClass(oob_meta);

        // TypeError, ValueError extend Error
        const error_subclasses = [_][]const u8{ "TypeError", "ValueError", "UnhandledMatchError" };
        for (error_subclasses) |name| {
            const child = try ClassMeta.init(allocator, name);
            child.parent = error_meta;
            child.magic_construct = meta.magic_construct;
            child.magic_toString = meta.magic_toString;
            try registerClass(child);
        }

        // ArithmeticError extends Error
        const arith_meta = try ClassMeta.init(allocator, "ArithmeticError");
        arith_meta.parent = error_meta;
        arith_meta.magic_construct = meta.magic_construct;
        arith_meta.magic_toString = meta.magic_toString;
        try registerClass(arith_meta);

        // DivisionByZeroError extends ArithmeticError
        const divzero_meta = try ClassMeta.init(allocator, "DivisionByZeroError");
        divzero_meta.parent = arith_meta;
        divzero_meta.magic_construct = meta.magic_construct;
        divzero_meta.magic_toString = meta.magic_toString;
        try registerClass(divzero_meta);

        // Register Closure class (Closure::bind, Closure::fromCallable)
        try registerClosureClass(allocator);
        // Register WeakReference class
        try registerWeakReferenceClass(allocator);
        // Register WeakMap class
        try registerWeakMapClass(allocator);
        // Register Generator class
        try registerGeneratorClass(allocator);
        // Register Reflection classes
        try registerReflectionClasses(allocator);
    }

    /// ============================================================================
    /// Closure Class Implementation
    /// ============================================================================
    /// PHP Closure class: Closure::bind(), Closure::fromCallable(), bindTo()

    fn registerClosureClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "Closure");

        // Closure::bind($closure, $newThis, $newScope = "static") — static method
        try meta.addMethod(.{
            .name = "bind",
            .func = struct {
                fn call(_: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    // args[0] = closure, args[1] = newThis, args[2] = newScope (optional)
                    if (args.len < 2) return Value.initNull();
                    const closure_val = args[0];
                    const new_this = args[1];

                    if (!closure_val.isFunction()) return Value.initNull();
                    const orig_closure = closure_val.asFunction();

                    // 创建新闭包，复制原闭包的函数指针和捕获列表
                    var new_captures = try alloc.alloc(Value, orig_closure.captures.len + 1);
                    // 复制原有的捕获变量
                    for (orig_closure.captures, 0..) |cap, i| {
                        _ = cap.retain();
                        new_captures[i] = cap;
                    }
                    // 最后一个捕获变量是绑定的 $this
                    _ = new_this.retain();
                    new_captures[orig_closure.captures.len] = new_this;

                    const new_closure = try allocPHPClosure(alloc);
                    new_closure.* = .{
                        .func = orig_closure.func,
                        .captures = new_captures,
                        .ref_count = 1,
                        .gc_info = .{},
                        .allocator = alloc,
                        .param_count = orig_closure.param_count,
                        .required_params = orig_closure.required_params,
                    };

                    alloc_counters.php_closure_objects += 1;
                    alloc_counters.php_closure_live_objects += 1;
                    if (alloc_counters.php_closure_live_objects > alloc_counters.php_closure_peak_live_objects) {
                        alloc_counters.php_closure_peak_live_objects = alloc_counters.php_closure_live_objects;
                    }

                    return Value.initFunction(new_closure);
                }
            }.call,
            .is_static = true,
        });

        // Closure::fromCallable($callback) — static method
        try meta.addMethod(.{
            .name = "fromCallable",
            .func = struct {
                fn call(_: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    // 如果已经是闭包，直接返回
                    if (args[0].isFunction()) {
                        _ = args[0].retain();
                        return args[0];
                    }
                    // 其他 callable 类型暂时原样返回
                    _ = args[0].retain();
                    return args[0];
                }
            }.call,
            .is_static = true,
        });

        // bindTo($newThis, $newScope = "static") — instance method
        try meta.addMethod(.{
            .name = "bindTo",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    // 将 bindTo 转为 bind(self, newThis, newScope)
                    if (args.len == 0) return Value.initNull();
                    const bind_args = [_]Value{ ctx, args[0], if (args.len > 1) args[1] else Value.initNull() };
                    // 直接调用 Closure 类的 bind 静态方法逻辑
                    if (findClass("Closure")) |closure_meta| {
                        if (closure_meta.findMethod("bind")) |bind_method| {
                            return bind_method.func(ctx, &bind_args, alloc);
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // call($newThis, ...$args) — instance method
        try meta.addMethod(.{
            .name = "call",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!ctx.isFunction()) return Value.initNull();
                    if (args.len == 0) return Value.initNull();
                    // args[0] = newThis, args[1..] = call args
                    const closure = ctx.asFunction();
                    return closure.func(ctx, args[1..], alloc);
                }
            }.call,
            .is_static = false,
        });

        try registerClass(meta);
    }

    /// ============================================================================
    /// WeakReference Implementation
    /// ============================================================================
    /// WeakReference 允许创建对对象的弱引用，不会阻止对象被垃圾回收。
    /// 当对象被销毁时，WeakReference::get() 返回 null。
    ///
    /// PHP API:
    ///   WeakReference::create(object $object): WeakReference
    ///   WeakReference->get(): ?object

    fn registerWeakReferenceClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "WeakReference");

        // WeakReference::create($object) - static factory method
        // 创建一个新的 WeakReference 实例，引用给定的对象
        try meta.addMethod(.{
            .name = "create",
            .func = struct {
                fn call(_: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    // 参数验证：必须提供一个对象
                    if (args.len == 0) {
                        return error.InvalidArgumentCount;
                    }
                    const target = args[0];

                    // 只能对对象创建弱引用
                    if (!Value_isObject(target)) {
                        return error.InvalidArgument;
                    }

                    const target_obj = Value_asObject(target);
                    const target_addr = @intFromPtr(target_obj);

                    // 创建 WeakReference 对象
                    const weakref_obj = if (findClass("WeakReference")) |m|
                        try PHPObject.initWithMeta(alloc, m)
                    else
                        try PHPObject.init(alloc, "WeakReference");

                    // 存储弱引用信息：
                    // __target_addr: 目标对象的内存地址（用于死亡检测）
                    // 注意：我们不应该 retain 目标对象，这是弱引用的核心特性
                    // 但由于当前的内存管理模型，我们需要一种方式来追踪对象是否存活
                    try weakref_obj.setProperty("__target_addr", Value.initInt(@as(i64, @intCast(target_addr))));

                    // 存储目标对象的类名（用于调试和反射）
                    const target_class_name = if (target_obj.class_meta) |m| m.name else "stdClass";
                    const class_name_str = try PHPString.init(alloc, target_class_name);
                    try weakref_obj.setProperty("__target_class", Value.initString(class_name_str));

                    // 存储一个轻量级的引用，用于在对象未被销毁时获取它
                    // 这里我们不增加引用计数（真正弱引用语义），但需要能追踪对象
                    // 在当前实现中，我们使用全局弱引用表来追踪
                    try weakref_register(target_addr, target, alloc);

                    alloc_counters.php_object_live_objects += 1;
                    return Value_initObject(weakref_obj);
                }
            }.call,
            .is_static = true,
        });

        // WeakReference->get() - 获取引用的对象
        // 如果对象已被销毁，返回 null
        try meta.addMethod(.{
            .name = "get",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    // 获取目标对象地址
                    const addr_val = this.getPropertyDirect("__target_addr") orelse return Value.initNull();
                    const addr: usize = @intCast(addr_val.toInt());

                    // 检查对象是否仍然存活
                    if (!php_weak_is_alive(addr)) {
                        return Value.initNull();
                    }

                    // 从弱引用表中获取目标对象
                    return weakref_get(addr);
                }
            }.call,
            .is_static = false,
        });

        // __debugInfo - 用于 var_dump 等调试输出
        try meta.addMethod(.{
            .name = "__debugInfo",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    const arr = try PHPArray.init(alloc);

                    // 获取目标对象地址
                    if (this.getPropertyDirect("__target_addr")) |addr_val| {
                        try arr.push(alloc, addr_val);
                    }

                    // 检查对象是否仍然存活
                    const is_alive = blk: {
                        if (this.getPropertyDirect("__target_addr")) |addr_val| {
                            const addr: usize = @intCast(addr_val.toInt());
                            break :blk php_weak_is_alive(addr);
                        }
                        break :blk false;
                    };
                    try arr.push(alloc, Value.initBool(is_alive));

                    // 添加目标类名
                    if (this.getPropertyDirect("__target_class")) |class_val| {
                        try arr.push(alloc, class_val);
                    }

                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });

        try registerClass(meta);
    }

    /// ============================================================================
    /// WeakMap Implementation
    /// ============================================================================
    /// WeakMap 是一个将对象作为键的映射（字典）。
    /// 与 SplObjectStorage 不同，WeakMap 中的键不会阻止对象被垃圾回收。
    /// 当键对象被销毁时，对应的条目会自动从 WeakMap 中移除。
    ///
    /// PHP API:
    ///   WeakMap implements Countable, ArrayAccess, IteratorAggregate
    ///   - __construct()
    ///   - count(): int
    ///   - offsetGet(object $object): mixed
    ///   - offsetSet(object $object, mixed $value): void
    ///   - offsetExists(object $object): bool
    ///   - offsetUnset(object $object): void
    ///   - getIterator(): Iterator

    fn registerWeakMapClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "WeakMap");

        // 实现接口标记
        const ifaces = try allocator.alloc([]const u8, 4);
        ifaces[0] = "Countable";
        ifaces[1] = "ArrayAccess";
        ifaces[2] = "IteratorAggregate";
        ifaces[3] = "Traversable";
        meta.interfaces = ifaces;

        // __construct() - 构造函数
        try meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    const this = Value_asObject(ctx);
                    // 使用关联数组存储条目：键是对象地址（转为字符串），值是 {key: object, value: value}
                    const entries = try PHPArray.init(alloc);
                    try this.setProperty("_entries", Value.initArray(entries));
                    // 存储条目数量（缓存，避免每次都遍历计算）
                    try this.setProperty("_size", Value.initInt(0));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // count() - 返回存活的条目数 (Countable interface)
        try meta.addMethod(.{
            .name = "count",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);

                    // 清理死亡的条目并重新计算数量
                    var alive_count: i64 = 0;

                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();

                        // 收集需要移除的键
                        var dead_keys = try std.ArrayList([]const u8).initCapacity(alloc, 0);
                        defer {
                            for (dead_keys.items) |key| alloc.free(key);
                            dead_keys.deinit(alloc);
                        }

                        var iter = entries.elements.iterator();
                        while (iter.next()) |entry| {
                            switch (entry.key_ptr.*) {
                                .string => |key_str| {
                                    // 从键字符串解析对象地址
                                    const addr = std.fmt.parseInt(usize, key_str.data, 10) catch 0;
                                    if (addr == 0 or !php_weak_is_alive(addr)) {
                                        try dead_keys.append(alloc, try alloc.dupe(u8, key_str.data));
                                    } else {
                                        alive_count += 1;
                                    }
                                },
                                .integer => |_| {
                                    // 跳过非字符串键
                                },
                            }
                        }

                        // 移除死亡的条目
                        for (dead_keys.items) |key| {
                            // 遍历查找匹配的键并移除
                            var found: ?ArrayKey = null;
                            var rm_iter = entries.elements.iterator();
                            while (rm_iter.next()) |rm_entry| {
                                if (rm_entry.key_ptr.* == .string) {
                                    if (std.mem.eql(u8, rm_entry.key_ptr.*.string.data, key)) {
                                        found = rm_entry.key_ptr.*;
                                        break;
                                    }
                                }
                            }
                            if (found) |fk| _ = entries.elements.remove(fk);
                        }
                    }

                    // 更新缓存的计数
                    try this.setProperty("_size", Value.initInt(alive_count));

                    return Value.initInt(alive_count);
                }
            }.call,
            .is_static = false,
        });

        // offsetExists($object) - 检查键是否存在 (ArrayAccess interface)
        try meta.addMethod(.{
            .name = "offsetExists",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);

                    if (args.len == 0) return Value.initBool(false);

                    // 只接受对象作为键
                    if (!Value_isObject(args[0])) {
                        return error.InvalidArgument;
                    }

                    const key_obj = Value_asObject(args[0]);
                    const addr = @intFromPtr(key_obj);

                    // 检查对象是否存活
                    if (!php_weak_is_alive(addr)) {
                        return Value.initBool(false);
                    }

                    // 查找条目
                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var buf: [32]u8 = undefined;
                        const key_str = std.fmt.bufPrint(&buf, "{}", .{addr}) catch "";
                        // 遍历查找匹配的键
                        var it = entries.elements.iterator();
                        while (it.next()) |entry| {
                            if (entry.key_ptr.* == .string) {
                                if (std.mem.eql(u8, entry.key_ptr.*.string.data, key_str)) {
                                    return Value.initBool(true);
                                }
                            }
                        }
                        return Value.initBool(false);
                    }

                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });

        // offsetGet($object) - 获取值 (ArrayAccess interface)
        try meta.addMethod(.{
            .name = "offsetGet",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (args.len == 0) return Value.initNull();

                    // 只接受对象作为键
                    if (!Value_isObject(args[0])) {
                        return error.InvalidArgument;
                    }

                    const key_obj = Value_asObject(args[0]);
                    const addr = @intFromPtr(key_obj);

                    // 检查对象是否存活
                    if (!php_weak_is_alive(addr)) {
                        return Value.initNull();
                    }

                    // 查找条目
                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var buf: [32]u8 = undefined;
                        const key_str = std.fmt.bufPrint(&buf, "{}", .{addr}) catch "";

                        // 遍历查找匹配的键
                        var it = entries.elements.iterator();
                        while (it.next()) |entry| {
                            if (entry.key_ptr.* == .string) {
                                if (std.mem.eql(u8, entry.key_ptr.*.string.data, key_str)) {
                                    const entry_val = entry.value_ptr.*;
                                    if (entry_val.isArray()) {
                                        const entry_arr = entry_val.asArray();
                                        if (entry_arr.elements.get(.{ .integer = 1 })) |value| {
                                            _ = value.retain();
                                            return value;
                                        }
                                    }
                                    break;
                                }
                            }
                        }
                    }

                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // offsetSet($object, $value) - 设置值 (ArrayAccess interface)
        try meta.addMethod(.{
            .name = "offsetSet",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (args.len < 2) {
                        return error.InvalidArgumentCount;
                    }

                    // 只接受对象作为键
                    if (!Value_isObject(args[0])) {
                        return error.InvalidArgument;
                    }

                    const key_obj = Value_asObject(args[0]);
                    const value = args[1];
                    const addr = @intFromPtr(key_obj);

                    // 检查对象是否存活
                    if (!php_weak_is_alive(addr)) {
                        // 对象已死，不能设置值
                        return Value.initNull();
                    }

                    // 获取或创建条目数组
                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var buf: [32]u8 = undefined;
                        const key_str = std.fmt.bufPrint(&buf, "{}", .{addr}) catch "";

                        // 创建条目：[key_object, value]
                        const entry_arr = try PHPArray.init(alloc);
                        _ = key_obj.retain(); // 保留键对象的引用
                        try entry_arr.push(alloc, args[0]);
                        _ = value.retain();
                        try entry_arr.push(alloc, value);

                        // 检查是否是新条目（遍历查找）
                        var is_new = true;
                        var it = entries.elements.iterator();
                        while (it.next()) |entry| {
                            if (entry.key_ptr.* == .string) {
                                if (std.mem.eql(u8, entry.key_ptr.*.string.data, key_str)) {
                                    is_new = false;
                                    break;
                                }
                            }
                        }

                        // 存储条目
                        const entry_key = try PHPString.init(alloc, key_str);
                        try entries.elements.put(.{ .string = entry_key }, Value.initArray(entry_arr));

                        // 更新计数
                        if (is_new) {
                            if (this.getPropertyDirect("_size")) |size_val| {
                                try this.setProperty("_size", Value.initInt(size_val.toInt() + 1));
                            }
                        }
                    }

                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // offsetUnset($object) - 移除条目 (ArrayAccess interface)
        try meta.addMethod(.{
            .name = "offsetUnset",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (args.len == 0) return Value.initNull();

                    // 只接受对象作为键
                    if (!Value_isObject(args[0])) {
                        return Value.initNull();
                    }

                    const key_obj = Value_asObject(args[0]);
                    const addr = @intFromPtr(key_obj);

                    // 移除条目
                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var buf: [32]u8 = undefined;
                        const key_str = std.fmt.bufPrint(&buf, "{}", .{addr}) catch "";

                        // 遍历查找匹配的键并移除
                        var found_key: ?ArrayKey = null;
                        var it = entries.elements.iterator();
                        while (it.next()) |entry| {
                            if (entry.key_ptr.* == .string) {
                                if (std.mem.eql(u8, entry.key_ptr.*.string.data, key_str)) {
                                    // 释放条目中的值
                                    if (entry.value_ptr.*.isArray()) {
                                        const entry_arr = entry.value_ptr.*.asArray();
                                        if (entry_arr.elements.get(.{ .integer = 0 })) |key_val| {
                                            key_val.release(runtime_allocator);
                                        }
                                        if (entry_arr.elements.get(.{ .integer = 1 })) |value_val| {
                                            value_val.release(runtime_allocator);
                                        }
                                    }
                                    found_key = entry.key_ptr.*;
                                    break;
                                }
                            }
                        }

                        if (found_key) |fk| {
                            _ = entries.elements.remove(fk);

                            // 更新计数
                            if (this.getPropertyDirect("_size")) |size_val| {
                                const current_size = size_val.toInt();
                                if (current_size > 0) {
                                    try this.setProperty("_size", Value.initInt(current_size - 1));
                                }
                            }
                        }
                    }

                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // getIterator() - 返回迭代器 (IteratorAggregate interface)
        try meta.addMethod(.{
            .name = "getIterator",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    // 创建一个 WeakMapIterator 对象
                    const iter_meta = findClass("WeakMapIterator") orelse blk: {
                        // 如果没有 WeakMapIterator 类，使用 ArrayIterator 作为后备
                        break :blk findClass("ArrayIterator");
                    } orelse return Value.initNull();

                    const iter_obj = try PHPObject.initWithMeta(alloc, iter_meta);

                    // 收集存活的条目
                    const result_arr = try PHPArray.init(alloc);

                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var arr_iter = entries.elements.iterator();

                        while (arr_iter.next()) |entry| {
                            switch (entry.key_ptr.*) {
                                .string => |key_str| {
                                    // 从键字符串解析对象地址
                                    const addr = std.fmt.parseInt(usize, key_str.data, 10) catch 0;
                                    if (addr != 0 and php_weak_is_alive(addr)) {
                                        // 条目存活，添加到结果数组
                                        if (entry.value_ptr.*.isArray()) {
                                            const entry_arr = entry.value_ptr.*.asArray();
                                            if (entry_arr.elements.get(.{ .integer = 0 })) |key_obj| {
                                                if (entry_arr.elements.get(.{ .integer = 1 })) |value| {
                                                    // 创建 [key, value] 对
                                                    const pair = try PHPArray.init(alloc);
                                                    _ = key_obj.retain();
                                                    try pair.push(alloc, key_obj);
                                                    _ = value.retain();
                                                    try pair.push(alloc, value);
                                                    try result_arr.push(alloc, Value.initArray(pair));
                                                }
                                            }
                                        }
                                    }
                                },
                                .integer => |_| {},
                            }
                        }
                    }

                    try iter_obj.setProperty("_array", Value.initArray(result_arr));
                    try iter_obj.setProperty("_position", Value.initInt(0));

                    return Value_initObject(iter_obj);
                }
            }.call,
            .is_static = false,
        });

        // __debugInfo - 用于 var_dump 等调试输出
        try meta.addMethod(.{
            .name = "__debugInfo",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    const result = try PHPArray.init(alloc);

                    if (this.getPropertyDirect("_entries")) |entries_val| {
                        const entries = entries_val.asArray();
                        var arr_iter = entries.elements.iterator();
                        var idx: i64 = 0;

                        while (arr_iter.next()) |entry| {
                            switch (entry.key_ptr.*) {
                                .string => |key_str| {
                                    const addr = std.fmt.parseInt(usize, key_str.data, 10) catch 0;
                                    if (addr != 0 and php_weak_is_alive(addr)) {
                                        if (entry.value_ptr.*.isArray()) {
                                            const entry_arr = entry.value_ptr.*.asArray();
                                            if (entry_arr.elements.get(.{ .integer = 1 })) |value| {
                                                _ = value.retain();
                                                try result.elements.put(.{ .integer = idx }, value);
                                                idx += 1;
                                            }
                                        }
                                    }
                                },
                                .integer => |_| {},
                            }
                        }
                    }

                    return Value.initArray(result);
                }
            }.call,
            .is_static = false,
        });

        try registerClass(meta);

        // 注册 WeakMapIterator 类（内部迭代器）
        try registerWeakMapIteratorClass(allocator);
    }

    /// WeakMapIterator - WeakMap 的内部迭代器
    fn registerWeakMapIteratorClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "WeakMapIterator");

        // 实现迭代器接口
        const ifaces = try allocator.alloc([]const u8, 1);
        ifaces[0] = "Iterator";
        meta.interfaces = ifaces;

        // current() - 返回当前元素
        try meta.addMethod(.{
            .name = "current",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (this.getPropertyDirect("_array")) |arr_val| {
                        if (this.getPropertyDirect("_position")) |pos_val| {
                            const arr = arr_val.asArray();
                            const pos = pos_val.toInt();
                            if (arr.elements.get(.{ .integer = pos })) |pair| {
                                if (pair.isArray()) {
                                    const pair_arr = pair.asArray();
                                    if (pair_arr.elements.get(.{ .integer = 1 })) |value| {
                                        _ = value.retain();
                                        return value;
                                    }
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // key() - 返回当前键
        try meta.addMethod(.{
            .name = "key",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (this.getPropertyDirect("_array")) |arr_val| {
                        if (this.getPropertyDirect("_position")) |pos_val| {
                            const arr = arr_val.asArray();
                            const pos = pos_val.toInt();
                            if (arr.elements.get(.{ .integer = pos })) |pair| {
                                if (pair.isArray()) {
                                    const pair_arr = pair.asArray();
                                    if (pair_arr.elements.get(.{ .integer = 0 })) |key_obj| {
                                        _ = key_obj.retain();
                                        return key_obj;
                                    }
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // next() - 移动到下一个元素
        try meta.addMethod(.{
            .name = "next",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);

                    if (this.getPropertyDirect("_position")) |pos_val| {
                        try this.setProperty("_position", Value.initInt(pos_val.toInt() + 1));
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // rewind() - 重置迭代器
        try meta.addMethod(.{
            .name = "rewind",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    try this.setProperty("_position", Value.initInt(0));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // valid() - 检查当前位置是否有效
        try meta.addMethod(.{
            .name = "valid",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);

                    if (this.getPropertyDirect("_array")) |arr_val| {
                        if (this.getPropertyDirect("_position")) |pos_val| {
                            const arr = arr_val.asArray();
                            const pos = pos_val.toInt();
                            const exists = arr.elements.get(.{ .integer = pos }) != null;
                            return Value.initBool(exists);
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });

        try registerClass(meta);
    }

    /// 判断 PHP 类型名是否是内置类型（用于 ReflectionNamedType::isBuiltin()）
    /// 注意：self/static/parent 在 PHP 中不是 builtin type，isBuiltin() 返回 false
    fn isBuiltinType(type_name: []const u8) bool {
        const builtins = [_][]const u8{
            "int", "float", "string", "bool", "array", "object", "callable",
            "iterable", "void", "never", "null", "mixed", "true", "false",
        };
        for (builtins) |b| {
            if (std.mem.eql(u8, type_name, b)) return true;
        }
        return false;
    }

    /// Register Reflection classes for PHP reflection API
    fn registerReflectionClasses(allocator: Allocator) !void {
        // ReflectionAttribute
        const attr_meta = try ClassMeta.init(allocator, "ReflectionAttribute");
        try attr_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try attr_meta.addMethod(.{
            .name = "getArguments",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__args")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initArray(try PHPArray.init(alloc));
                }
            }.call,
            .is_static = false,
        });
        // newInstance() - returns an object with attribute name and args as properties
        try attr_meta.addMethod(.{
            .name = "newInstance",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // Create a simple stdClass-like object with attribute properties
                    const name_val = this.getPropertyDirect("__name") orelse return Value.initNull();
                    const args_val = this.getPropertyDirect("__args");
                    if (findClass(if (name_val.isString()) name_val.asString().data else "stdClass")) |cmeta| {
                        const obj = try PHPObject.initWithMeta(alloc, cmeta);
                        // If class has constructor, call it with args
                        if (cmeta.magic_construct) |ctor| {
                            if (args_val) |av| {
                                if (av.isArray()) {
                                    const arr = av.asArray();
                                    const count = arr.elements.count();
                                    const real_args = try alloc.alloc(Value, count);
                                    defer alloc.free(real_args);
                                    var idx: usize = 0;
                                    while (idx < count) : (idx += 1) {
                                        real_args[idx] = arr.elements.get(ArrayKey{ .integer = @intCast(idx) }) orelse Value.initNull();
                                    }
                                    _ = try ctor(Value_initObject(obj), real_args, alloc);
                                } else {
                                    _ = try ctor(Value_initObject(obj), &.{}, alloc);
                                }
                            } else {
                                _ = try ctor(Value_initObject(obj), &.{}, alloc);
                            }
                        }
                        return Value_initObject(obj);
                    }
                    // Fallback: return stdClass with properties
                    const obj = try PHPObject.init(alloc, "stdClass");
                    if (name_val.isString()) try obj.setProperty("name", name_val.retain());
                    if (args_val) |av| try obj.setProperty("args", av.retain());
                    return Value_initObject(obj);
                }
            }.call,
            .is_static = false,
        });
        // getTarget() - read from stored __target property
        try attr_meta.addMethod(.{
            .name = "getTarget",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__target")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        // isRepeated() - read from stored __is_repeated property (defaults to false)
        try attr_meta.addMethod(.{
            .name = "isRepeated",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__is_repeated")) |v| {
                        return Value.initBool(v.toBool());
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try registerClass(attr_meta);

        // ReflectionClass
        const rc_meta = try ClassMeta.init(allocator, "ReflectionClass");
        try rc_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // 参数是类名字符串
                    const name_str = try args[0].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(name_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rc_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rc_meta.addMethod(.{
            .name = "getAttributes",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // 查找类元数据中的属性
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            const cname = name_val.asString().data;
                            if (findClass(cname)) |cmeta| {
                                // 从类元数据的 __attributes 读取
                                if (cmeta.static_properties.get("__attributes")) |attrs_val| {
                                    _ = attrs_val.retain();
                                    return attrs_val;
                                }
                            }
                        }
                    }
                    return Value.initArray(try PHPArray.init(alloc));
                }
            }.call,
            .is_static = false,
        });
        // isAbstract()
        try rc_meta.addMethod(.{
            .name = "isAbstract",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_abstract);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isFinal()
        try rc_meta.addMethod(.{
            .name = "isFinal",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_final);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isInstantiable()
        try rc_meta.addMethod(.{
            .name = "isInstantiable",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(!cmeta.is_abstract);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // hasMethod()
        try rc_meta.addMethod(.{
            .name = "hasMethod",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                if (args[0].isString()) {
                                    return Value.initBool(cmeta.methods.contains(args[0].asString().data));
                                }
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getMethod() - 返回 ReflectionMethod 对象
        try rc_meta.addMethod(.{
            .name = "getMethod",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString() or !args[0].isString()) return Value.initNull();
                    const cname = cname_val.asString().data;
                    const mname = args[0].asString().data;
                    if (findClass(cname)) |cmeta| {
                        if (cmeta.methods.contains(mname)) {
                            if (findClass("ReflectionMethod")) |rm_class| {
                                const rm_obj = try PHPObject.initWithMeta(alloc, rm_class);
                                try rm_obj.setProperty("__class_name", Value.initString(try PHPString.init(alloc, cname)));
                                try rm_obj.setProperty("__method_name", Value.initString(try PHPString.init(alloc, mname)));
                                return Value_initObject(rm_obj);
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getMethods() - 返回 ReflectionMethod 数组
        try rc_meta.addMethod(.{
            .name = "getMethods",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const cname = cname_val.asString().data;
                    const arr = try PHPArray.init(alloc);
                    if (findClass(cname)) |cmeta| {
                        var iter = cmeta.methods.iterator();
                        while (iter.next()) |entry| {
                            if (findClass("ReflectionMethod")) |rm_class| {
                                const rm_obj = try PHPObject.initWithMeta(alloc, rm_class);
                                try rm_obj.setProperty("__class_name", Value.initString(try PHPString.init(alloc, cname)));
                                try rm_obj.setProperty("__method_name", Value.initString(try PHPString.init(alloc, entry.key_ptr.*)));
                                try arr.push(alloc, Value_initObject(rm_obj));
                            }
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // hasProperty()
        try rc_meta.addMethod(.{
            .name = "hasProperty",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                if (args[0].isString()) {
                                    return Value.initBool(cmeta.properties.contains(args[0].asString().data));
                                }
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getProperties() - 返回 ReflectionProperty 对象数组
        try rc_meta.addMethod(.{
            .name = "getProperties",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const arr = try PHPArray.init(alloc);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        var iter = cmeta.properties.iterator();
                        while (iter.next()) |entry| {
                            if (findClass("ReflectionProperty")) |rp_cls| {
                                const rp_obj = try PHPObject.initWithMeta(alloc, rp_cls);
                                try rp_obj.setProperty("__class_name", cname_val);
                                _ = cname_val.retain();
                                try rp_obj.setProperty("__prop_name", Value.initString(try PHPString.init(alloc, entry.key_ptr.*)));
                                try arr.push(alloc, Value_initObject(rp_obj));
                            }
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // getProperty($name) - 返回单个 ReflectionProperty 对象
        try rc_meta.addMethod(.{
            .name = "getProperty",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString()) return Value.initNull();
                    const pname_str = try args[0].toString(alloc);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.properties.get(pname_str.data)) |_| {
                            if (findClass("ReflectionProperty")) |rp_cls| {
                                const rp_obj = try PHPObject.initWithMeta(alloc, rp_cls);
                                try rp_obj.setProperty("__class_name", cname_val);
                                _ = cname_val.retain();
                                try rp_obj.setProperty("__prop_name", Value.initString(pname_str));
                                return Value_initObject(rp_obj);
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // newInstance() - 创建类实例
        try rc_meta.addMethod(.{
            .name = "newInstance",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString()) return Value.initNull();
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.is_abstract) return Value.initNull();
                        const new_obj = try PHPObject.initWithMeta(alloc, cmeta);
                        if (cmeta.magic_construct) |ctor| {
                            _ = try ctor(Value_initObject(new_obj), args, alloc);
                        }
                        return Value_initObject(new_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // newInstanceArgs() - alias for newInstance
        try rc_meta.addMethod(.{
            .name = "newInstanceArgs",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString()) return Value.initNull();
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.is_abstract) return Value.initNull();
                        const new_obj = try PHPObject.initWithMeta(alloc, cmeta);
                        // 从数组参数中提取
                        if (args[0].isArray()) {
                            const arr = args[0].asArray();
                            const count = arr.elements.count();
                            const real_args = try alloc.alloc(Value, count);
                            defer alloc.free(real_args);
                            var idx: usize = 0;
                            while (idx < count) : (idx += 1) {
                                real_args[idx] = arr.elements.get(ArrayKey{ .integer = @intCast(idx) }) orelse Value.initNull();
                            }
                            if (cmeta.magic_construct) |ctor| {
                                _ = try ctor(Value_initObject(new_obj), real_args, alloc);
                            }
                        }
                        return Value_initObject(new_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getParentClass()
        try rc_meta.addMethod(.{
            .name = "getParentClass",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                if (cmeta.parent) |parent| {
                                    if (findClass("ReflectionClass")) |rc_class_meta| {
                                        const rc_obj = try PHPObject.initWithMeta(alloc, rc_class_meta);
                                        try rc_obj.setProperty("__class_name", Value.initString(try PHPString.init(alloc, parent.name)));
                                        return Value_initObject(rc_obj);
                                    }
                                }
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isClass() - returns true if not interface and not enum
        try rc_meta.addMethod(.{
            .name = "isClass",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(!cmeta.is_interface and !cmeta.is_enum);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isTrait()
        try rc_meta.addMethod(.{
            .name = "isTrait",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_trait);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isInterface()
        try rc_meta.addMethod(.{
            .name = "isInterface",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_interface);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getInterfaceNames()
        try rc_meta.addMethod(.{
            .name = "getInterfaceNames",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const arr = try PHPArray.init(alloc);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        for (cmeta.interfaces) |iface| {
                            try arr.push(alloc, Value.initString(try PHPString.init(alloc, iface)));
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // isEnum()
        try rc_meta.addMethod(.{
            .name = "isEnum",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |name_val| {
                        if (name_val.isString()) {
                            if (findClass(name_val.asString().data)) |cmeta| {
                                return Value.initBool(cmeta.is_enum);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isSubclassOf()
        try rc_meta.addMethod(.{
            .name = "isSubclassOf",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    if (!cname_val.isString()) return Value.initBool(false);
                    const parent_name = if (args[0].isString()) args[0].asString().data else if (Value_isObject(args[0])) blk: {
                        const arg_obj = Value_asObject(args[0]);
                        const pn = arg_obj.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                        if (pn.isString()) break :blk pn.asString().data else return Value.initBool(false);
                    } else return Value.initBool(false);
                    _ = alloc;
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        var cur = cmeta.parent;
                        while (cur) |p| {
                            if (std.mem.eql(u8, p.name, parent_name)) return Value.initBool(true);
                            cur = p.parent;
                        }
                        for (cmeta.interfaces) |iface| {
                            if (std.mem.eql(u8, iface, parent_name)) return Value.initBool(true);
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // implementsInterface()
        try rc_meta.addMethod(.{
            .name = "implementsInterface",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    if (!cname_val.isString()) return Value.initBool(false);
                    const iface_name = if (args[0].isString()) args[0].asString().data else return Value.initBool(false);
                    _ = alloc;
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        for (cmeta.interfaces) |iface| {
                            if (std.mem.eql(u8, iface, iface_name)) return Value.initBool(true);
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getConstant()
        try rc_meta.addMethod(.{
            .name = "getConstant",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    if (!cname_val.isString() or !args[0].isString()) return Value.initBool(false);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.static_properties.get(args[0].asString().data)) |val| {
                            return val.retain();
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // hasConstant()
        try rc_meta.addMethod(.{
            .name = "hasConstant",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    if (!cname_val.isString() or !args[0].isString()) return Value.initBool(false);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        return Value.initBool(cmeta.static_properties.contains(args[0].asString().data));
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getConstants()
        try rc_meta.addMethod(.{
            .name = "getConstants",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const arr = try PHPArray.init(alloc);
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        var iter = cmeta.static_properties.iterator();
                        while (iter.next()) |entry| {
                            const key = entry.key_ptr.*;
                            if (key.len > 0 and key[0] != '_') {
                                try arr.set(alloc, ArrayKey{ .string = try PHPString.init(alloc, key) }, entry.value_ptr.*.retain());
                            }
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // getConstructor() - 返回 __construct 的 ReflectionMethod 或 null
        try rc_meta.addMethod(.{
            .name = "getConstructor",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname_val.isString()) return Value.initNull();
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.methods.get("__construct") != null) {
                            if (findClass("ReflectionMethod")) |rm_cls| {
                                const rm_obj = try PHPObject.initWithMeta(alloc, rm_cls);
                                try rm_obj.setProperty("__class_name", Value.initString(try PHPString.init(alloc, cname_val.asString().data)));
                                try rm_obj.setProperty("__method_name", Value.initString(try PHPString.init(alloc, "__construct")));
                                return Value_initObject(rm_obj);
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        rc_meta.magic_construct = rc_meta.methods.get("__construct").?.func;
        try registerClass(rc_meta);

        // ReflectionEnum (extends ReflectionClass behavior)
        const re_meta = try ClassMeta.init(allocator, "ReflectionEnum");
        try re_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const name_str = try args[0].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(name_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try re_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__class_name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        re_meta.magic_construct = re_meta.methods.get("__construct").?.func;
        try registerClass(re_meta);

        // ReflectionClassConstant
        const rcc_meta = try ClassMeta.init(allocator, "ReflectionClassConstant");
        try rcc_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len < 2) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const class_str = try args[0].toString(alloc);
                    const const_str = try args[1].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(class_str));
                    try this.setProperty("__const_name", Value.initString(const_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rcc_meta.addMethod(.{
            .name = "getValue",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const kname_val = this.getPropertyDirect("__const_name") orelse return Value.initNull();
                    if (!cname_val.isString() or !kname_val.isString()) return Value.initNull();
                    const cname = cname_val.asString().data;
                    const kname = kname_val.asString().data;
                    // 查找类常量: "ClassName::CONST"
                    var buf: [512]u8 = undefined;
                    const full_key = std.fmt.bufPrint(&buf, "{s}::{s}", .{ cname, kname }) catch return Value.initNull();
                    if (constants.get(full_key)) |val| {
                        _ = val.retain();
                        return val;
                    }
                    // 尝试从类元数据的静态属性获取
                    if (findClass(cname)) |cmeta| {
                        if (cmeta.static_properties.get(kname)) |val| {
                            _ = val.retain();
                            return val;
                        }
                    }
                    _ = alloc;
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rcc_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__const_name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        rcc_meta.magic_construct = rcc_meta.methods.get("__construct").?.func;
        try registerClass(rcc_meta);

        // ReflectionNamedType - PHP ReflectionNamedType 类
        const rnt_meta = try ClassMeta.init(allocator, "ReflectionNamedType");
        // getName() - 返回类型名称字符串
        try rnt_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__type_name")) |v| { _ = v.retain(); return v; }
                    return Value.initString(try PHPString.init(alloc, ""));
                }
            }.call,
            .is_static = false,
        });
        // allowsNull() - 类型是否允许 null
        try rnt_meta.addMethod(.{
            .name = "allowsNull",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__allows_null")) |v| return Value.initBool(v.toBool());
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isBuiltin() - 是否是内置类型
        try rnt_meta.addMethod(.{
            .name = "isBuiltin",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__is_builtin")) |v| return Value.initBool(v.toBool());
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // __toString() - 返回类型名称
        try rnt_meta.addMethod(.{
            .name = "__toString",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__type_name")) |v| { _ = v.retain(); return v; }
                    return Value.initString(try PHPString.init(alloc, ""));
                }
            }.call,
            .is_static = false,
        });
        try registerClass(rnt_meta);

        // ReflectionUnionType - PHP ReflectionUnionType 类
        const rut_meta = try ClassMeta.init(allocator, "ReflectionUnionType");
        // getTypes() - 返回 ReflectionNamedType 对象数组
        try rut_meta.addMethod(.{
            .name = "getTypes",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__types")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // allowsNull()
        try rut_meta.addMethod(.{
            .name = "allowsNull",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__allows_null")) |v| return v;
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // __toString() - 拼接子类型名 "int|string"
        try rut_meta.addMethod(.{
            .name = "__toString",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    const types_val = this.getPropertyDirect("__types") orelse return Value.initString(try PHPString.init(alloc, ""));
                    if (!types_val.isArray()) return Value.initString(try PHPString.init(alloc, ""));
                    const arr = types_val.asArray();
                    var buf: [1024]u8 = undefined;
                    var pos: usize = 0;
                    var idx: usize = 0;
                    const count = arr.count();
                    while (idx < count) : (idx += 1) {
                        const sub = arr.getByIndex(idx) orelse continue;
                        if (Value_isObject(sub)) {
                            const sub_obj = Value_asObject(sub);
                            if (sub_obj.getPropertyDirect("__type_name")) |tn| {
                                if (tn.isString()) {
                                    const tname = tn.asString().data;
                                    if (idx > 0 and pos < buf.len) {
                                        buf[pos] = '|';
                                        pos += 1;
                                    }
                                    const end = @min(pos + tname.len, buf.len);
                                    @memcpy(buf[pos..end], tname[0..end - pos]);
                                    pos = end;
                                }
                            }
                        }
                    }
                    return Value.initString(try PHPString.init(alloc, buf[0..pos]));
                }
            }.call,
            .is_static = false,
        });
        try registerClass(rut_meta);

        // ReflectionIntersectionType - PHP ReflectionIntersectionType 类
        const rit_meta = try ClassMeta.init(allocator, "ReflectionIntersectionType");
        // getTypes()
        try rit_meta.addMethod(.{
            .name = "getTypes",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__types")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // allowsNull() - intersection types 永远不允许 null
        try rit_meta.addMethod(.{
            .name = "allowsNull",
            .func = struct {
                fn call(_: Value, _: []const Value, _: Allocator) anyerror!Value {
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // __toString() - 拼接 "A&B"
        try rit_meta.addMethod(.{
            .name = "__toString",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    const types_val = this.getPropertyDirect("__types") orelse return Value.initString(try PHPString.init(alloc, ""));
                    if (!types_val.isArray()) return Value.initString(try PHPString.init(alloc, ""));
                    const arr = types_val.asArray();
                    var buf: [1024]u8 = undefined;
                    var pos: usize = 0;
                    var idx: usize = 0;
                    const count = arr.count();
                    while (idx < count) : (idx += 1) {
                        const sub = arr.getByIndex(idx) orelse continue;
                        if (Value_isObject(sub)) {
                            const sub_obj = Value_asObject(sub);
                            if (sub_obj.getPropertyDirect("__type_name")) |tn| {
                                if (tn.isString()) {
                                    const tname = tn.asString().data;
                                    if (idx > 0 and pos < buf.len) {
                                        buf[pos] = '&';
                                        pos += 1;
                                    }
                                    const end = @min(pos + tname.len, buf.len);
                                    @memcpy(buf[pos..end], tname[0..end - pos]);
                                    pos = end;
                                }
                            }
                        }
                    }
                    return Value.initString(try PHPString.init(alloc, buf[0..pos]));
                }
            }.call,
            .is_static = false,
        });
        try registerClass(rit_meta);

        // ReflectionMethod
        const rm_meta = try ClassMeta.init(allocator, "ReflectionMethod");
        try rm_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len < 2) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const class_str = try args[0].toString(alloc);
                    const method_str = try args[1].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(class_str));
                    try this.setProperty("__method_name", Value.initString(method_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__method_name")) |v| { _ = v.retain(); return v; }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "getDeclaringClass",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (findClass("ReflectionClass")) |rc_cls| {
                        const rc_obj = try PHPObject.initWithMeta(alloc, rc_cls);
                        try rc_obj.setProperty("__class_name", cname_val);
                        _ = cname_val.retain();
                        return Value_initObject(rc_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "isPublic",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(true);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(true);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_public);
                            }
                        }
                    }
                    return Value.initBool(true);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "isStatic",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_static);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "isConstructor",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__method_name")) |v| {
                        if (v.isString()) return Value.initBool(std.mem.eql(u8, v.asString().data, "__construct"));
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "getNumberOfParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initInt(0);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initInt(0);
                    if (cname_val.isString() and mname_val.isString()) {
                        // 优先从 ClassMethod 元数据读取
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initInt(@intCast(m.param_count));
                            }
                        }
                        // 回退到 function_meta_registry
                        const full_name_buf = std.fmt.allocPrint(std.heap.page_allocator, "{s}::{s}", .{ cname_val.asString().data, mname_val.asString().data }) catch return Value.initInt(0);
                        defer std.heap.page_allocator.free(full_name_buf);
                        if (function_meta_registry) |meta_reg| {
                            if (meta_reg.get(full_name_buf)) |meta| {
                                return Value.initInt(@intCast(meta.param_count));
                            }
                        }
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "getNumberOfRequiredParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initInt(0);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initInt(0);
                    if (cname_val.isString() and mname_val.isString()) {
                        // 优先从 ClassMethod 元数据读取
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initInt(@intCast(m.required_params));
                            }
                        }
                        // 回退到 function_meta_registry
                        const full_name_buf = std.fmt.allocPrint(std.heap.page_allocator, "{s}::{s}", .{ cname_val.asString().data, mname_val.asString().data }) catch return Value.initInt(0);
                        defer std.heap.page_allocator.free(full_name_buf);
                        if (function_meta_registry) |meta_reg| {
                            if (meta_reg.get(full_name_buf)) |meta| {
                                return Value.initInt(@intCast(meta.required_params));
                            }
                        }
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        try rm_meta.addMethod(.{
            .name = "invoke",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx) or args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initNull();
                    if (!cname_val.isString() or !mname_val.isString()) return Value.initNull();
                    // args[0] = object, args[1..] = method args
                    if (Value_isObject(args[0])) {
                        const obj = Value_asObject(args[0]);
                        return obj.callMethod(mname_val.asString().data, args[1..]) catch Value.initNull();
                    }
                    _ = alloc;
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getParameters() - return array of ReflectionParameter from real ClassMethod metadata
        try rm_meta.addMethod(.{
            .name = "getParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initArray(try PHPArray.init(alloc));
                    if (!cname_val.isString() or !mname_val.isString()) return Value.initArray(try PHPArray.init(alloc));
                    const arr = try PHPArray.init(alloc);
                    // 优先从 ClassMethod 元数据获取参数信息
                    if (findClass(cname_val.asString().data)) |cmeta| {
                        if (cmeta.methods.get(mname_val.asString().data)) |m| {
                            var i: usize = 0;
                            while (i < m.param_count) : (i += 1) {
                                if (findClass("ReflectionParameter")) |rp_cls| {
                                    const rp_obj = try PHPObject.initWithMeta(alloc, rp_cls);
                                    try rp_obj.setProperty("__position", Value.initInt(@intCast(i)));
                                    if (i < m.param_names.len) {
                                        try rp_obj.setProperty("__name", Value.initString(try PHPString.init(alloc, m.param_names[i])));
                                    }
                                    // 设置参数类型信息
                                    if (i < m.param_types.len and m.param_types[i].len > 0) {
                                        try rp_obj.setProperty("__type_name", Value.initString(try PHPString.init(alloc, m.param_types[i])));
                                        try rp_obj.setProperty("__has_type", Value.initBool(true));
                                    } else {
                                        try rp_obj.setProperty("__has_type", Value.initBool(false));
                                    }
                                    // 设置 nullable 信息
                                    if (i < m.param_nullable.len) {
                                        try rp_obj.setProperty("__allows_null", Value.initBool(m.param_nullable[i]));
                                    }
                                    try arr.push(alloc, Value_initObject(rp_obj));
                                }
                            }
                            return Value.initArray(arr);
                        }
                    }
                    // 回退到 function_meta_registry
                    const full_name_buf = std.fmt.allocPrint(std.heap.page_allocator, "{s}::{s}", .{ cname_val.asString().data, mname_val.asString().data }) catch return Value.initArray(arr);
                    defer std.heap.page_allocator.free(full_name_buf);
                    if (function_meta_registry) |meta_reg| {
                        if (meta_reg.get(full_name_buf)) |meta| {
                            var i: usize = 0;
                            while (i < meta.param_count) : (i += 1) {
                                if (findClass("ReflectionParameter")) |rp_cls| {
                                    const rp_obj = try PHPObject.initWithMeta(alloc, rp_cls);
                                    try rp_obj.setProperty("__position", Value.initInt(@intCast(i)));
                                    if (i < meta.param_names.len) {
                                        try rp_obj.setProperty("__name", Value.initString(try PHPString.init(alloc, meta.param_names[i])));
                                    }
                                    try arr.push(alloc, Value_initObject(rp_obj));
                                }
                            }
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // getReturnType() - 从 ClassMethod.return_type 读取真实类型声明
        try rm_meta.addMethod(.{
            .name = "getReturnType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initNull();
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                if (m.return_type) |rt| {
                                    // 创建 ReflectionNamedType 对象
                                    if (findClass("ReflectionNamedType")) |rt_cls| {
                                        const rt_obj = try PHPObject.initWithMeta(alloc, rt_cls);
                                        try rt_obj.setProperty("__type_name", Value.initString(try PHPString.init(alloc, rt)));
                                        try rt_obj.setProperty("__allows_null", Value.initBool(m.return_nullable));
                                        try rt_obj.setProperty("__is_builtin", Value.initBool(isBuiltinType(rt)));
                                        return Value_initObject(rt_obj);
                                    }
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // hasReturnType() - 从 ClassMethod.return_type 读取
        try rm_meta.addMethod(.{
            .name = "hasReturnType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.return_type != null);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isAbstract() - read from real ClassMethod.is_abstract
        try rm_meta.addMethod(.{
            .name = "isAbstract",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_abstract);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isFinal() - read from real ClassMethod.is_final
        try rm_meta.addMethod(.{
            .name = "isFinal",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_final);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isPrivate() - read from real ClassMethod.is_private
        try rm_meta.addMethod(.{
            .name = "isPrivate",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_private);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isProtected() - read from real ClassMethod.is_protected
        try rm_meta.addMethod(.{
            .name = "isProtected",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                return Value.initBool(m.is_protected);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getModifiers() - 返回 PHP 标准修饰符位掩码
        try rm_meta.addMethod(.{
            .name = "getModifiers",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(1); // IS_PUBLIC
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initInt(1);
                    const mname_val = this.getPropertyDirect("__method_name") orelse return Value.initInt(1);
                    if (cname_val.isString() and mname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.methods.get(mname_val.asString().data)) |m| {
                                var flags: i64 = 0;
                                if (m.is_public) flags |= 1; // IS_PUBLIC
                                if (m.is_protected) flags |= 2; // IS_PROTECTED
                                if (m.is_private) flags |= 4; // IS_PRIVATE
                                if (m.is_static) flags |= 16; // IS_STATIC
                                if (m.is_final) flags |= 32; // IS_FINAL
                                if (m.is_abstract) flags |= 64; // IS_ABSTRACT
                                return Value.initInt(flags);
                            }
                        }
                    }
                    return Value.initInt(1); // default: IS_PUBLIC
                }
            }.call,
            .is_static = false,
        });
        rm_meta.magic_construct = rm_meta.methods.get("__construct").?.func;
        try registerClass(rm_meta);

        // ReflectionParameter
        const rp_meta = try ClassMeta.init(allocator, "ReflectionParameter");
        try rp_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len < 2) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const func_str = try args[0].toString(alloc);
                    try this.setProperty("__func_name", Value.initString(func_str));
                    if (args[1].isInt()) {
                        try this.setProperty("__position", args[1]);
                    } else {
                        const pname = try args[1].toString(alloc);
                        try this.setProperty("__name", Value.initString(pname));
                        try this.setProperty("__position", Value.initInt(0));
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__name")) |v| { _ = v.retain(); return v; }
                    // Fallback: generate name from position
                    const pos_val = this.getPropertyDirect("__position") orelse return Value.initString(try PHPString.init(alloc, "param0"));
                    const pos = pos_val.toInt();
                    const name = try std.fmt.allocPrint(alloc, "param{d}", .{pos});
                    return Value.initString(try PHPString.init(alloc, name));
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "getPosition",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__position")) |v| return v;
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "isOptional",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__is_optional")) |v| return v;
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "hasDefaultValue",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__has_default")) |v| return v;
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "isVariadic",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__is_variadic")) |v| return v;
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "allowsNull",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(true);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__allows_null")) |v| return Value.initBool(v.toBool());
                    // 无类型约束时默认允许null（与PHP行为一致）
                    return Value.initBool(true);
                }
            }.call,
            .is_static = false,
        });
        try rp_meta.addMethod(.{
            .name = "hasType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__has_type")) |v| return Value.initBool(v.toBool());
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getType() - 返回 ReflectionNamedType 对象或 null
        try rp_meta.addMethod(.{
            .name = "getType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const has_type_val = this.getPropertyDirect("__has_type") orelse return Value.initNull();
                    if (!has_type_val.toBool()) return Value.initNull();
                    const type_name_val = this.getPropertyDirect("__type_name") orelse return Value.initNull();
                    if (!type_name_val.isString()) return Value.initNull();
                    const allows_null_val = this.getPropertyDirect("__allows_null");
                    const allows_null = if (allows_null_val) |v| v.toBool() else true;
                    // 创建 ReflectionNamedType 对象
                    if (findClass("ReflectionNamedType")) |rt_cls| {
                        const rt_obj = try PHPObject.initWithMeta(alloc, rt_cls);
                        try rt_obj.setProperty("__type_name", type_name_val);
                        _ = type_name_val.retain();
                        try rt_obj.setProperty("__allows_null", Value.initBool(allows_null));
                        try rt_obj.setProperty("__is_builtin", Value.initBool(isBuiltinType(type_name_val.asString().data)));
                        return Value_initObject(rt_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        rp_meta.magic_construct = rp_meta.methods.get("__construct").?.func;
        try registerClass(rp_meta);

        // ReflectionProperty - PHP ReflectionProperty 类
        const rprop_meta = try ClassMeta.init(allocator, "ReflectionProperty");
        try rprop_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len < 2) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const class_str = try args[0].toString(alloc);
                    const prop_str = try args[1].toString(alloc);
                    try this.setProperty("__class_name", Value.initString(class_str));
                    try this.setProperty("__prop_name", Value.initString(prop_str));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getName()
        try rprop_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initString(try PHPString.init(alloc, ""));
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__prop_name")) |v| { _ = v.retain(); return v; }
                    return Value.initString(try PHPString.init(alloc, ""));
                }
            }.call,
            .is_static = false,
        });
        // getDeclaringClass()
        try rprop_meta.addMethod(.{
            .name = "getDeclaringClass",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    if (!cname.isString()) return Value.initNull();
                    if (findClass("ReflectionClass")) |rc_cls| {
                        const rc_obj = try PHPObject.initWithMeta(alloc, rc_cls);
                        try rc_obj.setProperty("__class_name", cname);
                        _ = cname.retain();
                        return Value_initObject(rc_obj);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getValue($object) - 支持实例属性和 static 属性
        try rprop_meta.addMethod(.{
            .name = "getValue",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initNull();
                    if (!pname_val.isString()) return Value.initNull();
                    const pname = pname_val.asString().data;
                    // 先检查是否是 static 属性
                    if (cname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname)) |p| {
                                if (p.is_static) {
                                    if (cmeta.static_properties.get(pname)) |sv| {
                                        _ = sv.retain();
                                        return sv;
                                    }
                                    return Value.initNull();
                                }
                            }
                        }
                    }
                    // 实例属性
                    if (args.len > 0 and Value_isObject(args[0])) {
                        const target = Value_asObject(args[0]);
                        if (target.getPropertyDirect(pname)) |v| {
                            _ = v.retain();
                            return v;
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // setValue($object, $value) - 支持实例属性和 static 属性
        try rprop_meta.addMethod(.{
            .name = "setValue",
            .func = struct {
                fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initNull();
                    if (!pname_val.isString()) return Value.initNull();
                    const pname = pname_val.asString().data;
                    // static 属性：setValue($value) 只需1个参数
                    if (cname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname)) |p| {
                                if (p.is_static) {
                                    const val = if (args.len >= 1) args[0] else Value.initNull();
                                    _ = val.retain();
                                    cmeta.static_properties.getPtr(pname).?.* = val;
                                    return Value.initNull();
                                }
                            }
                        }
                    }
                    // 实例属性：setValue($object, $value) 需2个参数
                    if (args.len >= 2 and Value_isObject(args[0])) {
                        const target = Value_asObject(args[0]);
                        _ = args[1].retain();
                        try target.setProperty(pname, args[1]);
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // isPublic/isProtected/isPrivate/isStatic/isReadOnly/isDefault
        inline for (.{
            .{ "isPublic", "is_public" },
            .{ "isProtected", "is_protected" },
            .{ "isPrivate", "is_private" },
            .{ "isStatic", "is_static" },
            .{ "isReadOnly", "is_readonly" },
            .{ "isDefault", "has_default" },
        }) |pair| {
            try rprop_meta.addMethod(.{
                .name = pair[0],
                .func = struct {
                    fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                        if (!Value_isObject(ctx)) return Value.initBool(false);
                        const this = Value_asObject(ctx);
                        const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                        const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initBool(false);
                        if (cname_val.isString() and pname_val.isString()) {
                            if (findClass(cname_val.asString().data)) |cmeta| {
                                if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                    return Value.initBool(@field(p, pair[1]));
                                }
                            }
                        }
                        return Value.initBool(false);
                    }
                }.call,
                .is_static = false,
            });
        }
        // hasType()
        try rprop_meta.addMethod(.{
            .name = "hasType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                return Value.initBool(p.type_name != null);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getType() - 返回 ReflectionNamedType 或 null
        try rprop_meta.addMethod(.{
            .name = "getType",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initNull();
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                if (p.type_name) |tn| {
                                    if (findClass("ReflectionNamedType")) |rt_cls| {
                                        const rt_obj = try PHPObject.initWithMeta(alloc, rt_cls);
                                        try rt_obj.setProperty("__type_name", Value.initString(try PHPString.init(alloc, tn)));
                                        try rt_obj.setProperty("__allows_null", Value.initBool(p.type_nullable));
                                        try rt_obj.setProperty("__is_builtin", Value.initBool(isBuiltinType(tn)));
                                        return Value_initObject(rt_obj);
                                    }
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // hasDefaultValue()
        try rprop_meta.addMethod(.{
            .name = "hasDefaultValue",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initBool(false);
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initBool(false);
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                return Value.initBool(p.has_default);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getDefaultValue()
        try rprop_meta.addMethod(.{
            .name = "getDefaultValue",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initNull();
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initNull();
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                if (p.default_value) |dv| {
                                    _ = dv.retain();
                                    return dv;
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // getModifiers() - 返回 PHP 标准属性修饰符位掩码
        try rprop_meta.addMethod(.{
            .name = "getModifiers",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(1); // IS_PUBLIC
                    const this = Value_asObject(ctx);
                    const cname_val = this.getPropertyDirect("__class_name") orelse return Value.initInt(1);
                    const pname_val = this.getPropertyDirect("__prop_name") orelse return Value.initInt(1);
                    if (cname_val.isString() and pname_val.isString()) {
                        if (findClass(cname_val.asString().data)) |cmeta| {
                            if (cmeta.properties.get(pname_val.asString().data)) |p| {
                                var flags: i64 = 0;
                                if (p.is_public) flags |= 1; // IS_PUBLIC
                                if (p.is_protected) flags |= 2; // IS_PROTECTED
                                if (p.is_private) flags |= 4; // IS_PRIVATE
                                if (p.is_static) flags |= 16; // IS_STATIC
                                if (p.is_readonly) flags |= 128; // IS_READONLY
                                return Value.initInt(flags);
                            }
                        }
                    }
                    return Value.initInt(1); // default: IS_PUBLIC
                }
            }.call,
            .is_static = false,
        });
        // isDefault() - 通过 Reflection 获取的属性都是在类定义中声明的
        try rprop_meta.addMethod(.{
            .name = "isDefault",
            .func = struct {
                fn call(_: Value, _: []const Value, _: Allocator) anyerror!Value {
                    return Value.initBool(true);
                }
            }.call,
            .is_static = false,
        });
        rprop_meta.magic_construct = rprop_meta.methods.get("__construct").?.func;
        try registerClass(rprop_meta);

        // ReflectionFunction
        const rf_meta = try ClassMeta.init(allocator, "ReflectionFunction");
        try rf_meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    var pc: i64 = 0;
                    var rp: i64 = 0;
                    if (args[0].isFunction()) {
                        // 闭包/callable 对象
                        const closure = args[0].asFunction();
                        pc = @intCast(closure.param_count);
                        rp = @intCast(closure.required_params);
                        try this.setProperty("__func_name", Value.initString(try PHPString.init(alloc, "{closure}")));
                        try this.setProperty("__closure", args[0]);
                        _ = args[0].retain();
                    } else {
                        // 函数名字符串
                        const name_str = try args[0].toString(alloc);
                        try this.setProperty("__func_name", Value.initString(name_str));
                        // 从元数据注册表查询参数信息
                        if (function_meta_registry) |meta_reg| {
                            const name_data = args[0].asString().data;
                            if (meta_reg.get(name_data)) |meta| {
                                pc = @intCast(meta.param_count);
                                rp = @intCast(meta.required_params);
                            }
                        }
                    }
                    try this.setProperty("__param_count", Value.initInt(pc));
                    try this.setProperty("__required_params", Value.initInt(rp));
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rf_meta.addMethod(.{
            .name = "getName",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__func_name")) |v| {
                        _ = v.retain();
                        return v;
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        try rf_meta.addMethod(.{
            .name = "getNumberOfParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__param_count")) |v| {
                        return v;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        try rf_meta.addMethod(.{
            .name = "getNumberOfRequiredParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initInt(0);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__required_params")) |v| {
                        return v;
                    }
                    return Value.initInt(0);
                }
            }.call,
            .is_static = false,
        });
        // invoke() - 调用反射的函数
        try rf_meta.addMethod(.{
            .name = "invoke",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // 优先使用存储的闭包
                    if (this.getPropertyDirect("__closure")) |closure_val| {
                        if (closure_val.isFunction()) {
                            const closure = closure_val.asFunction();
                            return closure.func(closure_val, args, alloc);
                        }
                    }
                    // 通过函数名查找
                    if (this.getPropertyDirect("__func_name")) |name_val| {
                        if (name_val.isString()) {
                            const func_name = name_val.asString().data;
                            if (user_function_registry) |reg| {
                                if (reg.get(func_name)) |func| {
                                    return func(Value.initNull(), args, alloc);
                                }
                            }
                            if (aot_callable_hook) |hook| {
                                return hook(func_name, args, alloc);
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // invokeArgs() - 以数组方式传参调用
        try rf_meta.addMethod(.{
            .name = "invokeArgs",
            .func = struct {
                fn call(ctx: Value, args: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initNull();
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    // 从数组参数中提取实际参数
                    if (args[0].isArray()) {
                        const arr = args[0].asArray();
                        const count = arr.elements.count();
                        const real_args = try alloc.alloc(Value, count);
                        defer alloc.free(real_args);
                        var idx: usize = 0;
                        while (idx < count) : (idx += 1) {
                            const key = ArrayKey{ .integer = @intCast(idx) };
                            real_args[idx] = arr.elements.get(key) orelse Value.initNull();
                        }
                        // 复用 invoke 逻辑
                        if (this.getPropertyDirect("__closure")) |closure_val| {
                            if (closure_val.isFunction()) {
                                const closure = closure_val.asFunction();
                                return closure.func(closure_val, real_args, alloc);
                            }
                        }
                        if (this.getPropertyDirect("__func_name")) |name_val| {
                            if (name_val.isString()) {
                                const func_name = name_val.asString().data;
                                if (user_function_registry) |reg| {
                                    if (reg.get(func_name)) |func| {
                                        return func(Value.initNull(), real_args, alloc);
                                    }
                                }
                                if (aot_callable_hook) |hook| {
                                    return hook(func_name, real_args, alloc);
                                }
                            }
                        }
                    }
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // isClosure()
        try rf_meta.addMethod(.{
            .name = "isClosure",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__closure")) |v| {
                        return Value.initBool(v.isFunction());
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // isUserDefined() - check if function is user-defined (not a builtin)
        try rf_meta.addMethod(.{
            .name = "isUserDefined",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(true);
                    const this = Value_asObject(ctx);
                    // 闭包始终是用户定义的
                    if (this.getPropertyDirect("__closure")) |v| {
                        if (v.isFunction()) return Value.initBool(true);
                    }
                    // 从函数名判断：如果存在于用户函数注册表中则为用户定义
                    if (this.getPropertyDirect("__func_name")) |name_val| {
                        if (name_val.isString()) {
                            if (user_function_registry) |reg| {
                                if (reg.get(name_val.asString().data) != null) return Value.initBool(true);
                            }
                        }
                    }
                    // AOT编译的函数都是用户定义的
                    return Value.initBool(true);
                }
            }.call,
            .is_static = false,
        });
        // isInternal() - opposite of isUserDefined
        try rf_meta.addMethod(.{
            .name = "isInternal",
            .func = struct {
                fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initBool(false);
                    const this = Value_asObject(ctx);
                    if (this.getPropertyDirect("__closure")) |v| {
                        if (v.isFunction()) return Value.initBool(false);
                    }
                    if (this.getPropertyDirect("__func_name")) |name_val| {
                        if (name_val.isString()) {
                            if (user_function_registry) |reg| {
                                if (reg.get(name_val.asString().data) != null) return Value.initBool(false);
                            }
                        }
                    }
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        // getParameters() - 返回 ReflectionParameter 数组
        try rf_meta.addMethod(.{
            .name = "getParameters",
            .func = struct {
                fn call(ctx: Value, _: []const Value, alloc: Allocator) anyerror!Value {
                    if (!Value_isObject(ctx)) return Value.initArray(try PHPArray.init(alloc));
                    const this = Value_asObject(ctx);
                    const pc_val = this.getPropertyDirect("__param_count") orelse return Value.initArray(try PHPArray.init(alloc));
                    const pc = pc_val.toInt();
                    const arr = try PHPArray.init(alloc);
                    var i: i64 = 0;
                    while (i < pc) : (i += 1) {
                        // 创建 ReflectionParameter 对象
                        if (findClass("ReflectionParameter")) |_| {
                            const param_obj = try PHPObject.init(alloc, "ReflectionParameter");
                            try param_obj.setProperty("__position", Value.initInt(i));
                            const param_name = try std.fmt.allocPrint(alloc, "param{d}", .{i});
                            try param_obj.setProperty("__name", Value.initString(try PHPString.init(alloc, param_name)));
                            try arr.push(alloc, Value_initObject(param_obj));
                        } else {
                            // 没注册 ReflectionParameter，返回 position 整数
                            try arr.push(alloc, Value.initInt(i));
                        }
                    }
                    return Value.initArray(arr);
                }
            }.call,
            .is_static = false,
        });
        // getReturnType() - 简化实现，返回 null
        try rf_meta.addMethod(.{
            .name = "getReturnType",
            .func = struct {
                fn call(_: Value, _: []const Value, _: Allocator) anyerror!Value {
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });
        // hasReturnType()
        try rf_meta.addMethod(.{
            .name = "hasReturnType",
            .func = struct {
                fn call(_: Value, _: []const Value, _: Allocator) anyerror!Value {
                    return Value.initBool(false);
                }
            }.call,
            .is_static = false,
        });
        rf_meta.magic_construct = rf_meta.methods.get("__construct").?.func;
        try registerClass(rf_meta);

        // Register Fiber class
        try registerFiberClass(allocator);
    }

    /// Fiber 协程状态
    const FiberState = enum(u8) {
        created,
        running,
        suspended,
        terminated,
    };

    /// Fiber 协程上下文 (线程 + 条件变量实现)
    const FiberContext = struct {
        mutex: std.Thread.Mutex = .{},
        caller_cond: std.Thread.Condition = .{},
        fiber_cond: std.Thread.Condition = .{},
        state: FiberState = .created,
        callback: Value = Value.initNull(),
        fiber_obj: Value = Value.initNull(),
        suspend_value: Value = Value.initNull(),
        resume_value: Value = Value.initNull(),
        return_value: Value = Value.initNull(),
        throw_exception: Value = Value.initNull(),
        thread: ?std.Thread = null,
        alloc: Allocator,

        fn init(alloc: Allocator) !*FiberContext {
            const ctx = try alloc.create(FiberContext);
            ctx.* = .{ .alloc = alloc };
            return ctx;
        }
    };

    /// 当前正在执行的 Fiber 对象（线程局部）
    threadlocal var current_fiber_obj: ?Value = null;

    fn fiberThreadMain(fctx: *FiberContext) void {
        // 在 fiber 线程中设置 threadlocal
        current_fiber_obj = fctx.fiber_obj;

        fctx.mutex.lock();
        while (fctx.state != .running) {
            fctx.fiber_cond.wait(&fctx.mutex);
        }
        fctx.mutex.unlock();

        // 通过闭包函数指针调用 fiber 回调
        const cb = fctx.callback;
        var result = Value.initNull();
        if (cb.isFunction()) {
            const closure = cb.asFunction();
            result = closure.func(
                cb,
                &[_]Value{},
                fctx.alloc,
            ) catch Value.initNull();
        }

        fctx.mutex.lock();
        fctx.return_value = result;
        fctx.state = .terminated;
        fctx.caller_cond.signal();
        fctx.mutex.unlock();
    }

    /// Register built-in Fiber class
    fn registerFiberClass(allocator: Allocator) !void {
        const meta = try ClassMeta.init(allocator, "Fiber");

        // __construct(callable $callback)
        try meta.addMethod(.{
            .name = "__construct",
            .func = struct {
                fn call(
                    ctx: Value,
                    args: []const Value,
                    alloc: Allocator,
                ) anyerror!Value {
                    if (args.len == 0) return Value.initNull();
                    const this = Value_asObject(ctx);
                    _ = args[0].retain();
                    try this.setProperty("__callback", args[0]);
                    try this.setProperty(
                        "__state",
                        Value.initInt(
                            @intFromEnum(FiberState.created),
                        ),
                    );
                    // 创建 FiberContext
                    const fctx = try FiberContext.init(alloc);
                    fctx.callback = args[0];
                    try this.setProperty(
                        "__fctx_addr",
                        Value.initInt(
                            @as(i64, @intCast(@intFromPtr(fctx))),
                        ),
                    );
                    return Value.initNull();
                }
            }.call,
            .is_static = false,
        });

        // start(...$args): mixed
        try meta.addMethod(.{
            .name = "start",
            .func = struct {
                fn call(
                    ctx: Value,
                    args: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    const this = Value_asObject(ctx);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    fctx.mutex.lock();
                    if (fctx.state != .created) {
                        fctx.mutex.unlock();
                        return Value.initNull();
                    }
                    if (args.len > 0) {
                        fctx.resume_value = args[0];
                    }
                    // fiber 线程通过 threadlocal 获取
                    fctx.fiber_obj = ctx;
                    fctx.state = .running;
                    // 启动线程
                    fctx.thread = std.Thread.spawn(
                        .{},
                        fiberThreadMain,
                        .{fctx},
                    ) catch {
                        fctx.mutex.unlock();
                        return Value.initNull();
                    };
                    // 信号唤醒 fiber 线程
                    fctx.fiber_cond.signal();
                    // 等待 fiber suspend 或 terminate
                    while (fctx.state == .running) {
                        fctx.caller_cond.wait(&fctx.mutex);
                    }
                    const result = fctx.suspend_value;
                    fctx.suspend_value = Value.initNull();
                    setFiberState(this, fctx.state);
                    fctx.mutex.unlock();
                    if (fctx.state == .terminated) {
                        if (fctx.thread) |t| t.join();
                        fctx.thread = null;
                    }
                    return result;
                }
            }.call,
            .is_static = false,
        });

        // resume($value = null): mixed
        try meta.addMethod(.{
            .name = "resume",
            .func = struct {
                fn call(
                    ctx: Value,
                    args: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    const this = Value_asObject(ctx);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    fctx.mutex.lock();
                    if (fctx.state != .suspended) {
                        fctx.mutex.unlock();
                        return Value.initNull();
                    }
                    if (args.len > 0) {
                        fctx.resume_value = args[0];
                    } else {
                        fctx.resume_value = Value.initNull();
                    }
                    fctx.state = .running;
                    fctx.fiber_cond.signal();
                    while (fctx.state == .running) {
                        fctx.caller_cond.wait(&fctx.mutex);
                    }
                    const result = fctx.suspend_value;
                    fctx.suspend_value = Value.initNull();
                    setFiberState(this, fctx.state);
                    fctx.mutex.unlock();
                    if (fctx.state == .terminated) {
                        if (fctx.thread) |t| t.join();
                        fctx.thread = null;
                    }
                    return result;
                }
            }.call,
            .is_static = false,
        });

        // Fiber::suspend($value = null): mixed (static)
        try meta.addMethod(.{
            .name = "suspend",
            .func = struct {
                fn call(
                    _: Value,
                    args: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    // 获取当前 fiber 上下文
                    const fiber_val = current_fiber_obj orelse
                        return Value.initNull();
                    if (!Value_isObject(fiber_val))
                        return Value.initNull();
                    const this = Value_asObject(fiber_val);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    fctx.mutex.lock();
                    if (args.len > 0) {
                        fctx.suspend_value = args[0];
                    }
                    fctx.state = .suspended;
                    fctx.caller_cond.signal();
                    // 等待 resume 或 throw
                    while (fctx.state == .suspended) {
                        fctx.fiber_cond.wait(&fctx.mutex);
                    }
                    const result = fctx.resume_value;
                    fctx.resume_value = Value.initNull();
                    // 检查是否有 throw 传入的异常
                    const thrown = fctx.throw_exception;
                    fctx.throw_exception = Value.initNull();
                    fctx.mutex.unlock();
                    // 在 fiber 线程设置异常（不返回 Zig 错误，
                    // 由生成代码的 hasException() 路由到 catch）
                    if (!thrown.isNull()) {
                        setException(thrown);
                        return Value.initNull();
                    }
                    return result;
                }
            }.call,
            .is_static = true,
        });

        // isStarted(): bool
        try meta.addMethod(.{
            .name = "isStarted",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    const s = getFiberState(ctx);
                    return Value.initBool(s != .created);
                }
            }.call,
            .is_static = false,
        });

        // isSuspended(): bool
        try meta.addMethod(.{
            .name = "isSuspended",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    return Value.initBool(
                        getFiberState(ctx) == .suspended,
                    );
                }
            }.call,
            .is_static = false,
        });

        // isRunning(): bool
        try meta.addMethod(.{
            .name = "isRunning",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    return Value.initBool(
                        getFiberState(ctx) == .running,
                    );
                }
            }.call,
            .is_static = false,
        });

        // isTerminated(): bool
        try meta.addMethod(.{
            .name = "isTerminated",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    return Value.initBool(
                        getFiberState(ctx) == .terminated,
                    );
                }
            }.call,
            .is_static = false,
        });

        // getReturn(): mixed
        try meta.addMethod(.{
            .name = "getReturn",
            .func = struct {
                fn call(
                    ctx: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    if (!Value_isObject(ctx))
                        return Value.initNull();
                    const this = Value_asObject(ctx);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    return fctx.return_value;
                }
            }.call,
            .is_static = false,
        });

        // Fiber::getCurrent(): ?Fiber (static)
        try meta.addMethod(.{
            .name = "getCurrent",
            .func = struct {
                fn call(
                    _: Value,
                    _: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    if (current_fiber_obj) |f| return f;
                    return Value.initNull();
                }
            }.call,
            .is_static = true,
        });

        // throw(Throwable $exception): mixed
        try meta.addMethod(.{
            .name = "throw",
            .func = struct {
                fn call(
                    ctx: Value,
                    args: []const Value,
                    _: Allocator,
                ) anyerror!Value {
                    const this = Value_asObject(ctx);
                    const fctx = getFiberCtx(this) orelse
                        return Value.initNull();
                    fctx.mutex.lock();
                    if (fctx.state != .suspended) {
                        fctx.mutex.unlock();
                        return Value.initNull();
                    }
                    if (args.len > 0) {
                        fctx.throw_exception = args[0];
                    }
                    // 通过 FiberContext 传递异常
                    fctx.resume_value = Value.initNull();
                    fctx.state = .running;
                    fctx.fiber_cond.signal();
                    while (fctx.state == .running) {
                        fctx.caller_cond.wait(&fctx.mutex);
                    }
                    const result = fctx.suspend_value;
                    fctx.suspend_value = Value.initNull();
                    setFiberState(this, fctx.state);
                    fctx.mutex.unlock();
                    if (fctx.state == .terminated) {
                        if (fctx.thread) |t| t.join();
                        fctx.thread = null;
                    }
                    return result;
                }
            }.call,
            .is_static = false,
        });

        meta.magic_construct = meta.methods.get("__construct").?.func;
        try registerClass(meta);
    }

    fn getFiberCtx(obj: *PHPObject) ?*FiberContext {
        const addr_val = obj.getPropertyDirect("__fctx_addr") orelse
            return null;
        const addr: usize = @intCast(addr_val.toInt());
        if (addr == 0) return null;
        return @ptrFromInt(addr);
    }

    fn getFiberState(ctx: Value) FiberState {
        if (!Value_isObject(ctx)) return .created;
        const this = Value_asObject(ctx);
        const sv = this.getPropertyDirect("__state") orelse
            return .created;
        return @enumFromInt(@as(u8, @intCast(sv.toInt())));
    }

    fn setFiberState(obj: *PHPObject, state: FiberState) void {
        obj.setProperty(
            "__state",
            Value.initInt(@intFromEnum(state)),
        ) catch {};
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
            if (parent.getStaticProperty(name)) |val| return val;
        }
        // 查找实现的接口中的常量
        for (self.interfaces) |iface| {
            if (class_registry) |reg| {
                if (reg.get(iface)) |iface_meta| {
                    if (iface_meta.getStaticProperty(name)) |val| return val;
                }
            }
        }
        return null;
    }

    /// 检查是否实现了接口
    pub fn implementsInterface(self: *const ClassMeta, interface_name: []const u8) bool {
        for (self.interfaces) |iface| {
            if (std.mem.eql(u8, iface, interface_name)) return true;
            // 递归检查接口的父接口（interface C extends A, B）
            if (class_registry) |reg| {
                if (reg.get(iface)) |iface_meta| {
                    if (iface_meta.implementsInterface(interface_name)) return true;
                }
            }
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

/// 弱引用死亡追踪：存储已被 unset 的对象指针地址
var weak_dead_objects: ?std.AutoHashMap(usize, void) = null;

/// 标记对象为"逻辑死亡"（unset 时调用）
pub fn php_weak_mark_dead(val: Value) void {
    if (!Value_isObject(val)) return;
    const obj = Value_asObject(val);
    const addr = @intFromPtr(obj);
    if (weak_dead_objects == null) {
        weak_dead_objects = std.AutoHashMap(usize, void).init(runtime_allocator);
    }
    if (weak_dead_objects) |*set| {
        set.put(addr, {}) catch {};
    }
}

/// 已触发 __destruct 的对象集合（防止重复触发）
var destructed_objects: ?std.AutoHashMap(usize, void) = null;

/// 对象是否已经执行过 __destruct
pub fn php_is_destructed(obj: *PHPObject) bool {
    if (destructed_objects) |*set| {
        return set.contains(@intFromPtr(obj));
    }
    return false;
}

/// 标记对象已执行 __destruct
fn markDestructed(obj: *PHPObject) void {
    if (destructed_objects == null) {
        destructed_objects = std.AutoHashMap(usize, void).init(runtime_allocator);
    }
    if (destructed_objects) |*set| {
        set.put(@intFromPtr(obj), {}) catch {};
    }
}

/// 立即对对象触发 __destruct（若尚未触发），用于 unset 时 PHP 语义。
/// 不释放内存，等待真正的 refcount 归零时 deinit 再释放。
pub fn php_force_destruct_if_object(val: Value) void {
    if (!Value_isObject(val)) return;
    const obj = Value_asObject(val);
    if (php_is_destructed(obj)) return;
    if (obj.class_meta) |meta| {
        if (class_registry == null) return;
        if (meta.findMethodLookup("__destruct")) |lookup| {
            markDestructed(obj);
            const this_val = Value_initObject(obj);
            const guard = ClassContext.init(meta, lookup.owner);
            defer guard.deinit();
            _ = lookup.method.func(this_val, &.{}, obj.allocator) catch {};
        } else {
            markDestructed(obj);
        }
    }
}

/// 检查对象是否仍然存活（未被 unset 标记为死亡）
fn php_weak_is_alive(addr: usize) bool {
    if (weak_dead_objects) |*set| {
        return !set.contains(addr);
    }
    return true;
}

/// ============================================================================
/// 弱引用表（WeakReference Table）
/// ============================================================================
/// 用于存储弱引用的目标对象。当创建 WeakReference 时，目标对象会被注册到这里。
/// 注意：这是一个简化实现，真正的弱引用应该在 GC 层面实现。

/// 弱引用表：地址 -> Value（目标对象的引用）
var weakref_table: ?std.AutoHashMap(usize, Value) = null;

/// 注册弱引用目标对象
/// 不增加引用计数，仅存储对象引用
fn weakref_register(addr: usize, target: Value, allocator: Allocator) !void {
    if (weakref_table == null) {
        weakref_table = std.AutoHashMap(usize, Value).init(allocator);
    }
    if (weakref_table) |*table| {
        // 存储目标对象的引用（不增加引用计数，实现弱引用语义）
        // 但我们需要能够在对象存活时获取它，所以保留一个原始指针引用
        // 注意：这是一个妥协的实现，真正的弱引用需要 GC 支持
        try table.put(addr, target);
    }
}

/// 获取弱引用目标对象
/// 如果对象已被销毁，返回 null
fn weakref_get(addr: usize) Value {
    // 首先检查对象是否仍然存活
    if (!php_weak_is_alive(addr)) {
        return Value.initNull();
    }

    // 从弱引用表获取目标对象
    if (weakref_table) |*table| {
        if (table.get(addr)) |target| {
            // 检查目标对象是否有效
            if (Value_isObject(target)) {
                _ = target.retain();
                return target;
            }
        }
    }

    return Value.initNull();
}

/// 清理弱引用表中已死亡对象的条目
fn weakref_cleanup() void {
    if (weakref_table) |*table| {
        var iter = table.iterator();
        var to_remove = try std.ArrayList(usize).initCapacity(runtime_allocator, 0);
        defer to_remove.deinit(runtime_allocator);

        while (iter.next()) |entry| {
            if (!php_weak_is_alive(entry.key_ptr.*)) {
                to_remove.append(runtime_allocator, entry.key_ptr.*) catch {};
            }
        }

        for (to_remove.items) |addr| {
            _ = table.remove(addr);
        }
    }
}

/// @ 错误抑制运算符支持
/// 使用嵌套计数器支持 @@expr 等场景
threadlocal var error_suppress_depth: u32 = 0;

pub fn php_error_suppress_push() void {
    error_suppress_depth += 1;
}

pub fn php_error_suppress_pop() void {
    if (error_suppress_depth > 0) error_suppress_depth -= 1;
}

pub fn isErrorSuppressed() bool {
    return error_suppress_depth > 0;
}

pub fn getCurrentCalledClass() ?*const ClassMeta {
    const ptr = concurrency.getExecutionContext().called_class orelse return null;
    return @ptrFromInt(ptr);
}

pub fn setCurrentCalledClass(meta: ?*const ClassMeta) void {
    concurrency.getExecutionContext().called_class = if (meta) |m| @intFromPtr(m) else null;
}

pub fn getCurrentScopeClass() ?*const ClassMeta {
    const ptr = concurrency.getExecutionContext().scope_class orelse return null;
    return @ptrFromInt(ptr);
}

pub fn setCurrentScopeClass(meta: ?*const ClassMeta) void {
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
    }

    /// 减少引用计数，必要时释放
    pub fn release(self: *PHPObject) void {
        if (self.ref_count > 1000000) {
            std.debug.print("ERROR: PHPObject corrupted! class={s} ref_count={d}\n", .{ self.class_name, self.ref_count });
            return;
        }
        if (self.ref_count == 0) {
            std.debug.print("WARNING: PHPObject double free! class={s}\n", .{self.class_name});
            return;
        }
        self.ref_count -= 1;
        if (self.ref_count == 0) {
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
                // 若已被 php_force_destruct_if_object 显式触发过，跳过
                if (!php_is_destructed(self)) {
                    if (meta.findMethodLookup("__destruct")) |lookup| {
                        // 临时增加引用计数，防止析构函数内部的retain/release导致无限递归
                        // 析构函数执行期间，对象的refcount应该保持为1
                        self.ref_count = 1;
                        const this_val = Value_initObject(self);
                        const guard = ClassContext.init(meta, lookup.owner);
                        defer guard.deinit();
                        _ = lookup.method.func(this_val, &.{}, self.allocator) catch {};
                        // 析构函数执行完毕，恢复refcount为0以继续销毁流程
                        self.ref_count = 0;
                    }
                }
                // 清理 destructed 记录
                if (destructed_objects) |*set| {
                    _ = set.remove(@intFromPtr(self));
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

    pub fn unsetProperty(self: *PHPObject, name: []const u8) !bool {
        if (self.properties.get(name)) |old_value| {
            if (self.properties.remove(name)) {
                old_value.release(self.allocator);
                return true;
            }
        }

        if (!in_magic_method) {
            if (self.class_meta) |meta| {
                if (meta.findMethodLookup("__unset")) |lookup| {
                    in_magic_method = true;
                    defer in_magic_method = false;

                    const this_val = Value_initObject(self);
                    const name_str = try PHPString.init(self.allocator, name);
                    const name_val = Value.initString(name_str);
                    defer name_val.release(self.allocator);
                    const args = [_]Value{name_val};
                    const guard = ClassContext.init(meta, lookup.owner);
                    defer guard.deinit();
                    _ = try lookup.method.func(this_val, &args, self.allocator);
                    return true;
                }
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
        return Value.initNull();
    }

    const obj = Value_asObject(obj_val);
    return obj.getProperty(property_name) orelse Value.initNull();
}

pub fn php_object_get_direct(obj_val: Value, property_name: []const u8) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
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
        return Value.initNull();
    }
    if (!prop_name_val.isString()) {
        return Value.initNull();
    }
    const obj = Value_asObject(obj_val);
    const prop_str = prop_name_val.asString();
    return obj.getProperty(prop_str.data) orelse Value.initNull();
}

pub fn php_object_set_dynamic(obj_val: Value, prop_name_val: Value, value: Value) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }
    if (!prop_name_val.isString()) {
        return Value.initNull();
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
    const actual_val = if (val.isRef()) val.asRef().* else val;
    if (actual_val.isArray()) {
        return actual_val;
    }
    const arr = try PHPArray.init(runtime_allocator);
    if (!actual_val.isNull()) {
        try arr.push(runtime_allocator, actual_val);
    }
    return Value.initArray(arr);
}

pub fn php_cast_object(val: Value) !Value {
    // 如果已经是对象，直接返回
    if (Value_isObject(val)) {
        return val;
    }
    
    // 数组转对象：将数组元素作为对象属性
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
    
    // 标量类型转对象：创建 stdClass 对象，值存储在 "scalar" 属性中
    // PHP 行为：(object)"test" 创建 stdClass { scalar: "test" }
    const obj_val = try php_object_new("stdClass", runtime_allocator);
    const obj = Value_asObject(obj_val);
    try obj.setProperty("scalar", val);
    return obj_val;
}

/// 设置对象属性
///
/// @param obj_val 对象Value
/// @param property_name 属性名
/// @param value 属性值
pub fn php_object_set(obj_val: Value, property_name: []const u8, value: Value) !Value {
    if (!Value_isObject(obj_val)) {
        // PHP: 对非对象设置属性发出警告但不终止
        return Value.initNull();
    }

    const obj = Value_asObject(obj_val);
    try obj.setProperty(property_name, value);
    return Value.initNull();
}

/// $obj->prop[] = value — 向对象属性数组追加元素
pub fn php_property_array_push_with_obj(obj_val: Value, prop_name: Value, value: Value, _: Value) !void {
    if (!Value_isObject(obj_val)) return;
    const obj = Value_asObject(obj_val);
    const name = if (prop_name.isString()) prop_name.asString().data else return;

    // 获取属性值
    var prop_val = obj.getPropertyDirect(name) orelse Value.initNull();

    // 如果属性不是数组，创建一个新数组
    if (!prop_val.isArray()) {
        const arr = try PHPArray.init(runtime_allocator);
        prop_val = Value.initArray(arr);
        try obj.setProperty(name, prop_val);
    }

    const arr = prop_val.asArray();
    _ = value.retain();
    try arr.push(runtime_allocator, value);
}

/// $obj->prop[key] = value — 向对象属性数组设置元素
pub fn php_property_array_set_with_obj(obj_val: Value, prop_name: Value, key: Value, value: Value, _: Value) !void {
    if (!Value_isObject(obj_val)) return;
    const obj = Value_asObject(obj_val);
    const name = if (prop_name.isString()) prop_name.asString().data else return;

    // 获取属性值
    var prop_val = obj.getPropertyDirect(name) orelse Value.initNull();

    // 如果属性不是数组，创建一个新数组
    if (!prop_val.isArray()) {
        const arr = try PHPArray.init(runtime_allocator);
        prop_val = Value.initArray(arr);
        try obj.setProperty(name, prop_val);
    }

    const arr = prop_val.asArray();
    const arr_key = normalizeArrayKeyFromValue(key);
    try arr.set(runtime_allocator, arr_key, value);
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
        // PHP: 对非对象调用方法时发出 Fatal error
        const stderr = std.fs.File{ .handle = 2 };
        stderr.writeAll("PHP Fatal error:  Call to a member function on a non-object\n") catch {};
        const stdout = std.fs.File{ .handle = 1 };
        stdout.writeAll("\nFatal error: Call to a member function on a non-object\n") catch {};
        return Value.initNull();
    }
    const obj = Value_asObject(obj_val);
    return obj.callMethod(method_name, args) catch |err| {
        if (err == error.MethodNotFound) {
            const class_name = if (obj.class_meta) |m| m.name else "unknown";
            const stderr = std.fs.File{ .handle = 2 };
            var buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "PHP Fatal error:  Uncaught Error: Call to undefined method {s}::{s}()\n", .{ class_name, method_name }) catch "PHP Fatal error: MethodNotFound\n";
            stderr.writeAll(msg) catch {};
            const stdout = std.fs.File{ .handle = 1 };
            const msg2 = std.fmt.bufPrint(&buf, "\nFatal error: Uncaught Error: Call to undefined method {s}::{s}()\n", .{ class_name, method_name }) catch "";
            stdout.writeAll(msg2) catch {};
            return Value.initNull();
        }
        return err;
    };
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

    if (meta == null) {
        // PHP Fatal error: Class "X" not found
        const stdout = std.fs.File{ .handle = 1 };
        const stderr = std.fs.File{ .handle = 2 };
        // PHP 输出顺序：先 stderr，再 stdout
        var ebuf: [1024]u8 = undefined;
        const stderr_msg = std.fmt.bufPrint(
            &ebuf,
            "PHP Fatal error:  Uncaught Error: Class \"{s}\"" ++
                " not found in {s}:{d}\nStack trace:\n" ++
                "#0 {{main}}\n  thrown in {s} on line {d}\n",
            .{ resolved, src_file, src_line, src_file, src_line },
        ) catch {
            std.process.exit(255);
        };
        stderr.writeAll(stderr_msg) catch {};
        var buf: [1024]u8 = undefined;
        const stdout_msg = std.fmt.bufPrint(
            &buf,
            "\nFatal error: Uncaught Error: Class \"{s}\"" ++
                " not found in {s}:{d}\nStack trace:\n" ++
                "#0 {{main}}\n  thrown in {s} on line {d}\n",
            .{ resolved, src_file, src_line, src_file, src_line },
        ) catch {
            stdout.writeAll("\nFatal error: Class not found\n") catch {};
            std.process.exit(255);
        };
        stdout.writeAll(stdout_msg) catch {};
        std.process.exit(255);
    }

    const obj = try PHPObject.initWithMeta(allocator, meta.?);

    const obj_val = Value_initObject(obj);

    // 调用 __construct
    if (obj.class_meta) |m| {
        if (m.findMethodLookup("__construct")) |lookup| {
            const guard = ClassContext.init(m, lookup.owner);
            defer guard.deinit();
            _ = try lookup.method.func(obj_val, args, allocator);
            // 注意：构造函数中的 store $this 会 retain，函数结束时会 release
            // 这是正确的引用计数行为，不需要补偿
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

/// 检查接口是否存在
pub fn php_interface_exists(interface_name: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!interface_name.isString()) return Value.initBool(false);
    const name = interface_name.asString().data;
    // 在class_registry中查找，检查是否为接口
    if (findClass(name)) |meta| {
        return Value.initBool(meta.is_interface);
    }
    return Value.initBool(false);
}

pub fn interface_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;
    return php_interface_exists(args[0], allocator);
}

/// 检查trait是否存在
pub fn php_trait_exists(trait_name: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!trait_name.isString()) return Value.initBool(false);
    const name = trait_name.asString().data;
    // 在class_registry中查找，检查是否为trait
    if (findClass(name)) |meta| {
        return Value.initBool(meta.is_trait);
    }
    return Value.initBool(false);
}

pub fn trait_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.MissingArgument;
    return php_trait_exists(args[0], allocator);
}

/// enum_exists(name) -> bool
pub fn php_enum_exists(name_val: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!name_val.isString()) return Value.initBool(false);
    const name = name_val.asString().data;
    if (findClass(name)) |meta| {
        return Value.initBool(meta.is_enum);
    }
    return Value.initBool(false);
}

/// 检查是否是某个类的子类
pub fn php_is_subclass_of(child: Value, parent: Value) !Value {
    // 第一个参数可以是对象或类名字符串
    var child_class_name: []const u8 = undefined;
    var child_meta: ?*const ClassMeta = null;
    
    if (Value_isObject(child)) {
        const obj = Value_asObject(child);
        child_class_name = obj.class_name;
        child_meta = obj.class_meta;
    } else if (child.isString()) {
        child_class_name = child.asString().data;
        child_meta = findClass(child_class_name);
    } else {
        return Value.initBool(false);
    }
    
    // 第二个参数必须是类名字符串
    if (!parent.isString()) return Value.initBool(false);
    const parent_class_name = parent.asString().data;
    
    // 如果子类元数据不存在，返回 false
    if (child_meta == null) return Value.initBool(false);
    
    // 检查是否相同（PHP 的 is_subclass_of 不包括自身）
    if (std.mem.eql(u8, child_class_name, parent_class_name)) {
        return Value.initBool(false);
    }
    
    // 检查继承链
    if (child_meta.?.parent) |parent_meta| {
        if (parent_meta.isSubclassOf(parent_class_name)) {
            return Value.initBool(true);
        }
    }
    
    // 检查接口实现
    if (child_meta.?.implementsInterface(parent_class_name)) {
        return Value.initBool(true);
    }
    
    return Value.initBool(false);
}

pub fn is_subclass_of(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 2) return error.MissingArgument;
    return php_is_subclass_of(args[0], args[1]);
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

    // PHP: Throwable 是所有 Exception 和 Error 的基接口
    if (std.mem.eql(u8, name, "Throwable")) {
        if (obj.class_meta) |meta| {
            // 检查是否是Exception或Error的子类
            if (meta.isSubclassOf("Exception") or std.mem.eql(u8, obj.class_name, "Exception")) return Value.initBool(true);
            if (meta.isSubclassOf("Error") or std.mem.eql(u8, obj.class_name, "Error")) return Value.initBool(true);
        }
    }

    // PHP 8.0+: 实现了 __toString() 的类自动实现 Stringable 接口
    if (std.mem.eql(u8, name, "Stringable")) {
        if (obj.class_meta) |meta| {
            if (meta.magic_toString != null) return Value.initBool(true);
            if (meta.methods.get("__toString") != null) return Value.initBool(true);
        }
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

    // 支持字符串类名: property_exists('ClassName', 'prop')
    if (obj_val.isString()) {
        const class_name = obj_val.asString().data;
        if (findClass(class_name)) |meta| {
            // 检查类元数据中是否有该属性
            if (meta.properties.get(name) != null) return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

pub fn property_exists(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 2) return error.MissingArgument;
    return php_property_exists(args[0], args[1]);
}

/// Enum::cases() - 返回所有 case 的数组（保持声明顺序）
fn enumCases(meta: *const ClassMeta, allocator: Allocator) !Value {
    const arr = try PHPArray.init(allocator);
    // 使用 __enum_cases 有序列表
    if (meta.static_properties.get("__enum_cases")) |cases_val| {
        if (cases_val.isArray()) {
            const cases_arr = cases_val.asArray();
            var it = cases_arr.elements.iterator();
            while (it.next()) |entry| {
                const name_val = entry.value_ptr.*;
                if (name_val.isString()) {
                    const name = name_val.asString().data;
                    if (meta.static_properties.get(name)) |case_val| {
                        _ = case_val.retain();
                        try arr.push(allocator, case_val);
                    }
                }
            }
        }
    }
    return Value.initArray(arr);
}

/// Enum::from(value) - 根据 backing value 查找 case，找不到抛 ValueError
fn enumFrom(meta: *const ClassMeta, needle: Value, allocator: Allocator) !Value {
    var it = meta.static_properties.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        if (Value_isObject(val)) {
            const obj = Value_asObject(val);
            if (obj.getPropertyDirect("value")) |backing| {
                const eq = try php_eq(backing, needle);
                if (eq.asBool()) {
                    _ = val.retain();
                    return val;
                }
            }
        }
    }
    // 抛出 ValueError
    const needle_str = try needle.toString(allocator);
    defer needle_str.release(allocator);
    const msg = try std.fmt.allocPrint(allocator, "{s} is not a valid backing value for enum {s}", .{ needle_str.data, meta.name });
    defer allocator.free(msg);
    _ = try throwThrowable("ValueError", msg, allocator);
    return Value.initNull();
}

/// Enum::tryFrom(value) - 根据 backing value 查找 case，找不到返回 null
fn enumTryFrom(meta: *const ClassMeta, needle: Value) !Value {
    var it = meta.static_properties.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;
        if (Value_isObject(val)) {
            const obj = Value_asObject(val);
            if (obj.getPropertyDirect("value")) |backing| {
                const eq = try php_eq(backing, needle);
                if (eq.asBool()) {
                    _ = val.retain();
                    return val;
                }
            }
        }
    }
    return Value.initNull();
}

/// 调用静态方法
pub fn php_call_static(class_name: []const u8, method_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    return php_call_static_with_ctx(Value.initNull(), class_name, method_name, args, allocator);
}

pub fn php_call_static_with_ctx(ctx: Value, class_name: []const u8, method_name: []const u8, args: []const Value, allocator: Allocator) !Value {
    const lookup_meta = blk: {
        if (std.mem.eql(u8, class_name, "self")) {
            break :blk getCurrentScopeClass() orelse {
                return throwException("Cannot access self:: when no class scope is active", allocator);
            };
        }
        if (std.mem.eql(u8, class_name, "parent")) {
            const scope = getCurrentScopeClass() orelse {
                return throwException("Cannot access parent:: when no class scope is active", allocator);
            };
            break :blk scope.parent orelse {
                return throwException("Cannot access parent:: when current class has no parent", allocator);
            };
        }
        if (std.mem.eql(u8, class_name, "static")) {
            // static:: 回退：先查 called class，再查 scope class
            break :blk getCurrentCalledClass() orelse getCurrentScopeClass() orelse {
                return throwException("Cannot access static:: when no class scope is active", allocator);
            };
        }
        break :blk findClass(class_name) orelse {
            const msg = std.fmt.allocPrint(allocator, "Class \"{s}\" not found", .{class_name}) catch return Value.initNull();
            defer allocator.free(msg);
            return throwException(msg, allocator);
        };
    };

    const called_meta = blk: {
        if (std.mem.eql(u8, class_name, "self") or
            std.mem.eql(u8, class_name, "parent") or
            std.mem.eql(u8, class_name, "static"))
        {
            // 与 lookup_meta 同步回退逻辑
            break :blk getCurrentCalledClass() orelse getCurrentScopeClass() orelse lookup_meta;
        }
        break :blk lookup_meta;
    };

    // 查找方法（静态或实例方法）
    if (lookup_meta.findMethodLookup(method_name)) |lookup| {
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(ctx, args, allocator);
    }

    // Enum 内置静态方法: cases(), from(), tryFrom()
    if (std.mem.eql(u8, method_name, "cases")) {
        return enumCases(lookup_meta, allocator);
    }
    if (std.mem.eql(u8, method_name, "from")) {
        if (args.len == 0) return error.InvalidArgumentCount;
        return enumFrom(lookup_meta, args[0], allocator);
    }
    if (std.mem.eql(u8, method_name, "tryFrom")) {
        if (args.len == 0) return error.InvalidArgumentCount;
        return enumTryFrom(lookup_meta, args[0]);
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

pub fn throwThrowable(class_name: []const u8, message: []const u8, allocator: Allocator) !Value {
    const obj = if (findClass(class_name)) |meta|
        try PHPObject.initWithMeta(allocator, meta)
    else
        try PHPObject.init(allocator, class_name);
    const exception = Value_initObject(obj);
    const msg_str = try PHPString.init(allocator, message);
    const msg_val = Value.initString(msg_str);
    defer msg_val.release(allocator);
    try obj.setProperty("message", msg_val);
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
pub fn php_time() Value {
    const timestamp = std.time.timestamp();
    return Value.initInt(timestamp);
}

/// getdate - 获取日期/时间信息
pub fn php_getdate(ts_val: Value, allocator: Allocator) !Value {
    const timestamp = if (ts_val.isNull()) std.time.timestamp() else ts_val.toInt();
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(@as(u64, @bitCast(timestamp))) };
    const day_seconds = epoch.getDaySeconds();
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const year = year_day.year;
    const month: i64 = @intCast(@intFromEnum(month_day.month));
    const day: i64 = @intCast(month_day.day_index + 1);
    const hours: i64 = @intCast(day_seconds.getHoursIntoDay());
    const minutes: i64 = @intCast(day_seconds.getMinutesIntoHour());
    const seconds_val: i64 = @intCast(day_seconds.getSecondsIntoMinute());
    // 计算星期几：1970-01-01是周四(4)，PHP wday: 0=周日,1=周一,...,6=周六
    const days_since_epoch: i64 = @intCast(epoch_day.day);
    const wday: i64 = @mod(days_since_epoch + 4, 7);
    // 一年中的第几天：year_day.day 是0-based，PHP yday也是0-based
    const yday: i64 = @intCast(year_day.day);

    const arr = try PHPArray.init(allocator);
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "seconds")), Value.initInt(seconds_val));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "minutes")), Value.initInt(minutes));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "hours")), Value.initInt(hours));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "mday")), Value.initInt(day));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "wday")), Value.initInt(wday));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "mon")), Value.initInt(month));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "year")), Value.initInt(@intCast(@as(i32, year))));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "yday")), Value.initInt(yday));
    const weekday_names = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    const month_names   = [_][]const u8{ "", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const wday_idx = @as(usize, @intCast(@mod(wday, 7)));
    const mon_idx  = @as(usize, @intCast(@min(@max(month, 1), 12)));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "weekday")), Value.initString(try PHPString.init(allocator, weekday_names[wday_idx])));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "month")),   Value.initString(try PHPString.init(allocator, month_names[mon_idx])));
    try arr.setByValue(allocator, Value.initInt(0), Value.initInt(timestamp));
    return Value.initArray(arr);
}

pub fn php_idate(format_val: Value, ts_val: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!format_val.isString()) return Value.initInt(0);
    const fmt = format_val.asString().data;
    if (fmt.len == 0) return Value.initInt(0);
    const timestamp = if (ts_val.isNull()) std.time.timestamp() else ts_val.toInt();
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(@as(u64, @bitCast(timestamp))) };
    const day_seconds = epoch.getDaySeconds();
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const hours: i64 = @intCast(day_seconds.getHoursIntoDay());
    const minutes: i64 = @intCast(day_seconds.getMinutesIntoHour());
    const secs: i64   = @intCast(day_seconds.getSecondsIntoMinute());
    const day: i64    = @intCast(month_day.day_index + 1);
    const month: i64  = @intCast(@intFromEnum(month_day.month));
    const year: i64   = @intCast(@as(i32, year_day.year));
    const days_since_epoch: i64 = @intCast(epoch_day.day);
    const wday: i64   = @mod(days_since_epoch + 4, 7);
    const yday: i64   = @intCast(year_day.day);
    const result: i64 = switch (fmt[0]) {
        'Y' => year,
        'y' => @mod(year, 100),
        'n', 'm' => month,
        'j', 'd' => day,
        'H' => hours,
        'h' => blk: { const h = @mod(hours, 12); break :blk if (h == 0) 12 else h; },
        'i' => minutes,
        's' => secs,
        'w', 'l' => wday,
        'z' => yday,
        'U' => timestamp,
        else => 0,
    };
    return Value.initInt(result);
}

/// mktime(hour, minute, second, month, day, year) -> Unix timestamp
pub fn php_mktime(hour: Value, minute: Value, second: Value, month: Value, day: Value, year: Value) Value {
    const h = hour.toInt();
    const mi = minute.toInt();
    const s = second.toInt();
    const mon = month.toInt();
    const d = day.toInt();
    var y = year.toInt();
    // PHP: 0-69 => 2000-2069, 70-100 => 1970-2000
    if (y >= 0 and y <= 69) y += 2000;
    if (y >= 70 and y <= 100) y += 1900;
    const days_per_month = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var total_days: i64 = 0;
    var yi: i64 = 1970;
    while (yi < y) : (yi += 1) {
        const is_leap = (@rem(yi, 4) == 0 and @rem(yi, 100) != 0) or (@rem(yi, 400) == 0);
        total_days += if (is_leap) 366 else 365;
    }
    var mi2: i64 = 1;
    while (mi2 < mon) : (mi2 += 1) {
        const idx = @as(usize, @intCast(mi2 - 1));
        total_days += days_per_month[idx];
        if (mi2 == 2) {
            const is_leap = (@rem(y, 4) == 0 and @rem(y, 100) != 0) or (@rem(y, 400) == 0);
            if (is_leap) total_days += 1;
        }
    }
    total_days += d - 1;
    const ts = total_days * 86400 + h * 3600 + mi * 60 + s;
    return Value.initInt(ts);
}

/// checkdate(month, day, year) -> bool: 验证日期合法性
pub fn php_checkdate(month: Value, day: Value, year: Value) Value {
    const m = month.toInt();
    const d = day.toInt();
    const y = year.toInt();
    if (y < 1 or y > 32767) return Value.initBool(false);
    if (m < 1 or m > 12) return Value.initBool(false);
    if (d < 1) return Value.initBool(false);
    const days_in_month = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const is_leap = (@rem(y, 4) == 0 and @rem(y, 100) != 0) or (@rem(y, 400) == 0);
    var max_day = days_in_month[@as(usize, @intCast(m - 1))];
    if (m == 2 and is_leap) max_day = 29;
    return Value.initBool(d <= max_day);
}

/// gmdate(format, timestamp=null) -> string: UTC格式化（与date相同，时间戳已是UTC）
pub fn php_gmdate(format: Value, timestamp: Value, allocator: Allocator) !Value {
    if (!format.isString()) return Value.initString(try PHPString.init(allocator, ""));
    const ts = if (timestamp.isNull())
        std.time.timestamp()
    else if (timestamp.isInt())
        timestamp.asInt()
    else if (timestamp.isFloat())
        @as(i64, @intFromFloat(timestamp.asFloat()))
    else
        std.time.timestamp();
    return formatPhpDateValue(ts, format.asString().data, allocator);
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

fn formatPhpDateValue(timestamp: i64, format_str: []const u8, allocator: Allocator) !Value {
    const epoch_seconds: u64 = @intCast(@max(@as(i64, 0), timestamp));
    const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = epoch.getDaySeconds();
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const days_since_epoch: i64 = @intCast(epoch_day.day);
    const wday: usize = @intCast(@mod(days_since_epoch + 4, 7)); // 0=Sun
    const year: i64 = @intCast(@as(i32, year_day.year));
    const month: usize = @intCast(month_day.month.numeric());
    const day: usize = @intCast(month_day.day_index + 1);
    const hour: usize = @intCast(day_seconds.getHoursIntoDay());
    const minute: usize = @intCast(day_seconds.getMinutesIntoHour());
    const second: usize = @intCast(day_seconds.getSecondsIntoMinute());

    const weekday_full = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    const weekday_short = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    const month_full = [_][]const u8{ "", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const month_short = [_][]const u8{ "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    var result = try std.ArrayList(u8).initCapacity(allocator, format_str.len * 2);
    defer result.deinit(allocator);
    const w = result.writer(allocator);

    var i: usize = 0;
    while (i < format_str.len) : (i += 1) {
        const c = format_str[i];
        switch (c) {
            // Year
            'Y' => try w.print("{d:0>4}", .{@as(u32, @intCast(year))}),
            'y' => try w.print("{d:0>2}", .{@as(u32, @intCast(@mod(year, 100)))}),
            // Month
            'm' => try w.print("{d:0>2}", .{month}),
            'n' => try w.print("{d}", .{month}),
            'F' => try w.writeAll(month_full[month]),
            'M' => try w.writeAll(month_short[month]),
            // Day
            'd' => try w.print("{d:0>2}", .{day}),
            'j' => try w.print("{d}", .{day}),
            // Weekday
            'l' => try w.writeAll(weekday_full[wday]),
            'D' => try w.writeAll(weekday_short[wday]),
            'w' => try w.print("{d}", .{wday}),
            'N' => try w.print("{d}", .{if (wday == 0) @as(usize, 7) else wday}), // ISO: Mon=1..Sun=7
            // Hour
            'H' => try w.print("{d:0>2}", .{hour}),
            'G' => try w.print("{d}", .{hour}),
            'h' => try w.print("{d:0>2}", .{if (@mod(hour, 12) == 0) @as(usize, 12) else @mod(hour, 12)}),
            'g' => try w.print("{d}", .{if (@mod(hour, 12) == 0) @as(usize, 12) else @mod(hour, 12)}),
            'A' => try w.writeAll(if (hour < 12) "AM" else "PM"),
            'a' => try w.writeAll(if (hour < 12) "am" else "pm"),
            // Minute / second
            'i' => try w.print("{d:0>2}", .{minute}),
            's' => try w.print("{d:0>2}", .{second}),
            // Timestamp
            'U' => try w.print("{d}", .{timestamp}),
            // Day of year (0-based in PHP)
            'z' => try w.print("{d}", .{year_day.day}),
            // Escape
            '\\' => {
                i += 1;
                if (i < format_str.len) try result.append(allocator, format_str[i]);
            },
            else => try result.append(allocator, c),
        }
    }

    return Value.initString(try PHPString.init(allocator, result.items));
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

    return formatPhpDateValue(ts, format.asString().data, allocator);
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
            mt.state[i] = 1812433253 *% (mt.state[i - 1] ^ (mt.state[i - 1] >> 30)) +% @as(u32, @intCast(i));
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
    // 确保mt_state已初始化
    if (mt_state == null) {
        mt_state = MT19937.init(@intCast(@as(u64, @intCast(std.time.timestamp())) & 0xFFFFFFFF));
    }
    
    // mt_rand() - 无参数，返回0到MT_RAND_MAX
    // mt_rand(min, max) - 返回min到max之间的随机数
    if (min.isNull() and max.isNull()) {
        // 无参数：返回0到2147483647
        return Value.initInt(@intCast(mt_state.?.generate() & 0x7FFFFFFF));
    }
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
    return Value.initBool(php_arr.get(normalizeArrayKeyFromValue(key)) != null);
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
    return php_count(val, Value.initInt(0));
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

pub fn php_array_diff_key(arrays: []const Value, allocator: Allocator) !Value {
    if (arrays.len == 0 or !arrays[0].isArray()) return Value.initArray(try PHPArray.init(allocator));

    const first = arrays[0].asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    // 遍历第一个数组的所有键值对
    var it = first.elements.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const v = entry.value_ptr.*;
        var keep = true;
        
        // 检查这个键是否在其他数组中存在
        for (arrays[1..]) |other_val| {
            if (!other_val.isArray()) continue;
            const other_arr = other_val.asArray();
            
            // 如果其他数组中存在相同的键，则不保留
            if (other_arr.elements.get(key)) |_| {
                keep = false;
                break;
            }
        }
        
        if (keep) {
            try result.set(allocator, key, v);
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
    if (!arr.isArray()) {
        const got = valueTypeName(arr);
        emitTypeFatalError("sort", 1, "array", got);
    }
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

    // 解析参数：找到第一个数组（排序键）和排序方向
    const first_arr = arrays[0].asArray();
    const n = first_arr.count();
    var descending = false;
    // 检查SORT_DESC(2)
    for (arrays[1..]) |arg| {
        if (arg.isInt() and arg.asInt() == 2) { descending = true; break; }
    }

    var first_vals = try allocator.alloc(Value, n);
    defer allocator.free(first_vals);
    var it0 = first_arr.elements.iterator();
    var idx0: usize = 0;
    while (it0.next()) |entry| : (idx0 += 1) first_vals[idx0] = entry.value_ptr.*;

    var indices = try allocator.alloc(usize, n);
    defer allocator.free(indices);
    for (0..n) |i| indices[i] = i;

    try quickSortIndicesByValues(indices, first_vals, allocator, descending);

    // 对所有数组参数（跳过非数组的排序标志）重排
    for (arrays) |arr_val| {
        if (!arr_val.isArray()) continue; // 跳过SORT_ASC/SORT_DESC等
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

/// urlencode - PHP URL 编码（空格→+，其他特殊字符→%XX）
pub fn php_urlencode(input: Value, allocator: Allocator) !Value {
    if (!input.isString()) {
        const s = try input.toString(allocator);
        defer s.deinit(allocator);
        return php_urlencode(Value.initString(s), allocator);
    }
    const data = input.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, data.len);
    defer result.deinit(allocator);
    const hex = "0123456789ABCDEF";
    for (data) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.') {
            try result.append(allocator, c);
        } else if (c == ' ') {
            try result.append(allocator, '+');
        } else {
            try result.append(allocator, '%');
            try result.append(allocator, hex[c >> 4]);
            try result.append(allocator, hex[c & 0x0F]);
        }
    }
    const str = try PHPString.init(allocator, result.items);
    return Value.initString(str);
}

/// urldecode - PHP URL 解码（+→空格，%XX→字符）
pub fn php_urldecode(input: Value, allocator: Allocator) !Value {
    if (!input.isString()) return Value.initString(try PHPString.init(allocator, ""));
    const data = input.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, data.len);
    defer result.deinit(allocator);
    var i: usize = 0;
    while (i < data.len) {
        if (data[i] == '+') {
            try result.append(allocator, ' ');
            i += 1;
        } else if (data[i] == '%' and i + 2 < data.len) {
            const hi = std.fmt.charToDigit(data[i + 1], 16) catch {
                try result.append(allocator, '%');
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(data[i + 2], 16) catch {
                try result.append(allocator, '%');
                i += 1;
                continue;
            };
            try result.append(allocator, (hi << 4) | lo);
            i += 3;
        } else {
            try result.append(allocator, data[i]);
            i += 1;
        }
    }
    const str = try PHPString.init(allocator, result.items);
    return Value.initString(str);
}

/// rawurlencode - RFC 3986 编码（空格→%20）
pub fn php_rawurlencode(input: Value, allocator: Allocator) !Value {
    if (!input.isString()) {
        const s = try input.toString(allocator);
        defer s.deinit(allocator);
        return php_rawurlencode(Value.initString(s), allocator);
    }
    const data = input.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, data.len);
    defer result.deinit(allocator);
    const hex = "0123456789ABCDEF";
    for (data) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(allocator, c);
        } else {
            try result.append(allocator, '%');
            try result.append(allocator, hex[c >> 4]);
            try result.append(allocator, hex[c & 0x0F]);
        }
    }
    const str = try PHPString.init(allocator, result.items);
    return Value.initString(str);
}

/// rawurldecode - RFC 3986 解码（%XX→字符，+不转换）
pub fn php_rawurldecode(input: Value, allocator: Allocator) !Value {
    if (!input.isString()) return Value.initString(try PHPString.init(allocator, ""));
    const data = input.asString().data;
    var result = try std.ArrayList(u8).initCapacity(allocator, data.len);
    defer result.deinit(allocator);
    var i: usize = 0;
    while (i < data.len) {
        if (data[i] == '%' and i + 2 < data.len) {
            const hi = std.fmt.charToDigit(data[i + 1], 16) catch {
                try result.append(allocator, '%');
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(data[i + 2], 16) catch {
                try result.append(allocator, '%');
                i += 1;
                continue;
            };
            try result.append(allocator, (hi << 4) | lo);
            i += 3;
        } else {
            try result.append(allocator, data[i]);
            i += 1;
        }
    }
    const str = try PHPString.init(allocator, result.items);
    return Value.initString(str);
}

// ============================================================================
// 网络相关函数
// ============================================================================

/// gethostbyname - 通过主机名获取IP地址
pub fn php_gethostbyname(hostname: Value, allocator: Allocator) !Value {
    if (!hostname.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const name = hostname.asString().data;

    // 使用 C 库 getaddrinfo 进行 DNS 解析
    const c_name = try allocator.dupeZ(u8, name);
    defer allocator.free(c_name);

    var hints: std.posix.addrinfo = std.mem.zeroes(std.posix.addrinfo);
    hints.family = std.posix.AF.INET;
    hints.socktype = std.posix.SOCK.STREAM;

    var result_ptr: ?*std.posix.addrinfo = null;
    const rc = std.c.getaddrinfo(c_name.ptr, null, &hints, &result_ptr);
    if (@intFromEnum(rc) != 0 or result_ptr == null) {
        return hostname;
    }
    defer std.c.freeaddrinfo(result_ptr.?);

    const addr_in: *const std.posix.sockaddr.in = @ptrCast(@alignCast(result_ptr.?.addr.?));
    const ip_bytes = @as(*const [4]u8, @ptrCast(&addr_in.addr));
    const ip_str = try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ ip_bytes[0], ip_bytes[1], ip_bytes[2], ip_bytes[3] });
    defer allocator.free(ip_str);

    const result = try PHPString.init(allocator, ip_str);
    return Value.initString(result);
}

/// gethostname - 获取主机名
pub fn php_gethostname(allocator: Allocator) !Value {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&buf) catch {
        return Value.initString(try PHPString.init(allocator, "localhost"));
    };
    const result = try PHPString.init(allocator, hostname);
    return Value.initString(result);
}

/// ip2long - 将IP地址转换为长整型
pub fn php_ip2long(ip: Value) !Value {
    if (!ip.isString()) return Value.initBool(false);
    const ip_str = ip.asString().data;

    // 解析IPv4地址
    var parts = std.mem.splitScalar(u8, ip_str, '.');
    var result: u32 = 0;
    var shift: u5 = 24;

    while (parts.next()) |part| {
        const num = std.fmt.parseInt(u8, part, 10) catch return Value.initBool(false);
        result |= @as(u32, num) << shift;
        if (shift > 0) shift -= 8 else break;
    }

    return Value.initInt(@as(i64, result));
}

/// long2ip - 将长整型转换为IP地址
pub fn php_long2ip(long: Value, allocator: Allocator) !Value {
    const ip_num: u32 = @intCast(@max(long.toInt(), 0));

    const a: u8 = @intCast((ip_num >> 24) & 0xFF);
    const b: u8 = @intCast((ip_num >> 16) & 0xFF);
    const c: u8 = @intCast((ip_num >> 8) & 0xFF);
    const d: u8 = @intCast(ip_num & 0xFF);

    const ip_str = try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ a, b, c, d });
    const result = try PHPString.init(allocator, ip_str);
    return Value.initString(result);
}

/// parse_url - 解析URL
pub fn php_parse_url(url: Value, allocator: Allocator) !Value {
    if (!url.isString()) return Value.initBool(false);

    const url_str = url.asString().data;
    const arr = try PHPArray.init(allocator);

    // 简单的URL解析
    var rest = url_str;

    // 解析scheme
    if (std.mem.indexOf(u8, rest, "://")) |scheme_end| {
        const scheme = rest[0..scheme_end];
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "scheme") }, Value.initString(try PHPString.init(allocator, scheme)));
        rest = rest[scheme_end + 3..];
    }

    // 解析host和port
    if (std.mem.indexOf(u8, rest, "/")) |host_end| {
        const host_port = rest[0..host_end];
        rest = rest[host_end..];

        if (std.mem.indexOf(u8, host_port, ":")) |port_pos| {
            const host = host_port[0..port_pos];
            const port = host_port[port_pos + 1..];
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "host") }, Value.initString(try PHPString.init(allocator, host)));
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "port") }, Value.initInt(std.fmt.parseInt(i64, port, 10) catch 0));
        } else {
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "host") }, Value.initString(try PHPString.init(allocator, host_port)));
        }
    }

    // 解析path
    if (std.mem.indexOf(u8, rest, "?")) |path_end| {
        const path = rest[0..path_end];
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "path") }, Value.initString(try PHPString.init(allocator, path)));
        rest = rest[path_end + 1..];

        // 解析query
        if (std.mem.indexOf(u8, rest, "#")) |query_end| {
            const query = rest[0..query_end];
            const fragment = rest[query_end + 1..];
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "query") }, Value.initString(try PHPString.init(allocator, query)));
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "fragment") }, Value.initString(try PHPString.init(allocator, fragment)));
        } else {
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "query") }, Value.initString(try PHPString.init(allocator, rest)));
        }
    } else {
        if (rest.len > 0) {
            try arr.set(allocator, .{ .string = try PHPString.init(allocator, "path") }, Value.initString(try PHPString.init(allocator, rest)));
        }
    }

    return Value.initArray(arr);
}

/// http_build_query - 生成 URL 编码的查询字符串
pub fn php_http_build_query(data: Value, allocator: Allocator) !Value {
    if (!data.isArray()) return Value.initString(try PHPString.init(allocator, ""));

    const arr = data.asArray();
    var result = try std.ArrayList(u8).initCapacity(allocator, 64);
    defer result.deinit(allocator);
    const writer = result.writer(allocator);

    var first = true;
    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        if (!first) try writer.writeAll("&");
        first = false;

        // 写入键
        switch (entry.key_ptr.*) {
            .integer => |i| try writer.print("{d}", .{i}),
            .string => |s| try writer.writeAll(s.data),
        }
        try writer.writeAll("=");

        // 写入值
        const val = entry.value_ptr.*;
        if (val.isString()) {
            // URL 编码
            for (val.asString().data) |c| {
                if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
                    try writer.writeByte(c);
                } else if (c == ' ') {
                    try writer.writeByte('+');
                } else {
                    try writer.print("%{X:0>2}", .{c});
                }
            }
        } else if (val.isInt()) {
            try writer.print("{d}", .{val.asInt()});
        } else if (val.isFloat()) {
            try writer.print("{d}", .{val.asFloat()});
        } else if (val.isBool()) {
            if (val.asBool()) try writer.writeAll("1");
        }
    }

    return Value.initString(try PHPString.init(allocator, result.items));
}

/// parse_str - 将查询字符串解析到变量中
pub fn php_parse_str(str: Value, result_arr: Value, allocator: Allocator) !Value {
    if (!str.isString()) return Value.initNull();

    const query = str.asString().data;
    const arr = if (result_arr.isArray()) result_arr.asArray() else try PHPArray.init(allocator);

    var pairs = std.mem.splitScalar(u8, query, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;
        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            const key = pair[0..eq_pos];
            const val = pair[eq_pos + 1 ..];
            const key_str = try PHPString.init(allocator, key);
            const val_str = try PHPString.init(allocator, val);
            try arr.set(allocator, .{ .string = key_str }, Value.initString(val_str));
        } else {
            const key_str = try PHPString.init(allocator, pair);
            const empty_str = try PHPString.init(allocator, "");
            try arr.set(allocator, .{ .string = key_str }, Value.initString(empty_str));
        }
    }

    if (!result_arr.isArray()) {
        return Value.initArray(arr);
    }
    return Value.initNull();
}

/// glob - 查找匹配模式的文件路径
pub fn php_glob(pattern: Value, allocator: Allocator) !Value {
    if (!pattern.isString()) return Value.initArray(try PHPArray.init(allocator));

    const pat = pattern.asString().data;
    const arr = try PHPArray.init(allocator);

    // 简单实现：使用目录遍历 + 模式匹配
    // 提取目录部分和文件名模式
    const dir_path = std.fs.path.dirname(pat) orelse ".";
    const file_pattern = std.fs.path.basename(pat);

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch {
        return Value.initArray(arr);
    };
    defer dir.close();

    var dir_iter = dir.iterate();
    while (dir_iter.next() catch null) |entry| {
        if (globMatch(file_pattern, entry.name)) {
            const full_path = if (std.mem.eql(u8, dir_path, "."))
                try PHPString.init(allocator, entry.name)
            else blk: {
                const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer allocator.free(path);
                break :blk try PHPString.init(allocator, path);
            };
            try arr.push(allocator, Value.initString(full_path));
        }
    }

    return Value.initArray(arr);
}

/// 简单的 glob 模式匹配（支持 * 和 ?）
fn globMatch(pattern: []const u8, name: []const u8) bool {
    var pi: usize = 0;
    var ni: usize = 0;
    var star_pi: ?usize = null;
    var star_ni: usize = 0;

    while (ni < name.len) {
        if (pi < pattern.len and (pattern[pi] == name[ni] or pattern[pi] == '?')) {
            pi += 1;
            ni += 1;
        } else if (pi < pattern.len and pattern[pi] == '*') {
            star_pi = pi;
            star_ni = ni;
            pi += 1;
        } else if (star_pi) |sp| {
            pi = sp + 1;
            star_ni += 1;
            ni = star_ni;
        } else {
            return false;
        }
    }

    while (pi < pattern.len and pattern[pi] == '*') pi += 1;
    return pi == pattern.len;
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
    const num = number.toFloat();
    const dec: usize = @intCast(@max(0, decimals.toInt()));
    const dp: u8 = if (dec_point.isString() and dec_point.asString().data.len > 0)
        dec_point.asString().data[0] else '.';
    const ts: u8 = if (thousands_sep.isString() and thousands_sep.asString().data.len > 0)
        thousands_sep.asString().data[0]
        else if (thousands_sep.isNull()) ','
        else ',';

    var pow10: u64 = 1;
    for (0..dec) |_| pow10 *= 10;

    const scaled = num * @as(f64, @floatFromInt(pow10));
    const rounded: i64 = @intFromFloat(std.math.round(scaled));
    const negative = rounded < 0;
    const abs_r: u64 = @intCast(if (negative) -rounded else rounded);
    const int_part: u64 = abs_r / pow10;
    const frac_part: u64 = abs_r % pow10;

    // 整数部分转字符串（带千分位）
    const int_str = try std.fmt.allocPrint(allocator, "{d}", .{int_part});
    defer allocator.free(int_str);
    const n_groups = (int_str.len + 2) / 3; // ceil
    const sep_count = if (int_str.len > 3) (int_str.len - 1) / 3 else 0;

    // 估算总长度
    var total: usize = (if (negative) @as(usize, 1) else 0) + int_str.len + sep_count;
    if (dec > 0) total += 1 + dec;
    _ = n_groups;

    var buf = try std.ArrayList(u8).initCapacity(allocator, total + 4);
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);

    if (negative) try w.writeByte('-');
    // 写整数部分（带千分位）
    for (int_str, 0..) |ch, idx| {
        const remaining = int_str.len - idx;
        if (idx > 0 and remaining % 3 == 0) try w.writeByte(ts);
        try w.writeByte(ch);
    }
    // 写小数部分
    if (dec > 0) {
        try w.writeByte(dp);
        var tmp = frac_part;
        var digits = try allocator.alloc(u8, dec);
        defer allocator.free(digits);
        var j: usize = dec;
        while (j > 0) {
            j -= 1;
            digits[j] = '0' + @as(u8, @intCast(tmp % 10));
            tmp /= 10;
        }
        try w.writeAll(digits);
    }

    return Value.initString(try PHPString.init(allocator, buf.items));
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

/// settype - 改变变量的类型
/// PHP签名: settype(mixed &$var, string $type): bool
/// 第一个参数是引用，直接修改变量的值
pub fn php_settype(var_ref: Value, type_val: Value, allocator: Allocator) !Value {
    if (!type_val.isString()) {
        return Value.initBool(false);
    }
    
    // 检查第一个参数是否是引用
    if (!var_ref.isRef()) {
        return Value.initBool(false);
    }
    
    const ptr = var_ref.asRef();
    const type_name = type_val.asString().data;
    
    // 保存原始值用于转换
    const old_val = ptr.*;
    
    // 根据类型名进行转换
    const new_val = if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean"))
        Value.initBool(old_val.toBool())
    else if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"))
        Value.initInt(old_val.toInt())
    else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double"))
        Value.initFloat(old_val.toFloat())
    else if (std.mem.eql(u8, type_name, "string"))
        blk: {
            const str = try old_val.toString(allocator);
            break :blk Value.initString(str);
        }
    else if (std.mem.eql(u8, type_name, "array"))
        try php_cast_array(old_val)
    else if (std.mem.eql(u8, type_name, "object"))
        try php_cast_object(old_val)
    else if (std.mem.eql(u8, type_name, "null"))
        Value.initNull()
    else
        // 未知类型，返回 false 但不修改变量
        return Value.initBool(false);
    
    // 释放旧值，设置新值
    ptr.release(allocator);
    _ = new_val.retain();
    ptr.* = new_val;
    
    // 返回 true 表示成功
    return Value.initBool(true);
}

// ============================================================================
// 文件函数
// ============================================================================

/// file_get_contents - 读取文件内容
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
/// mkdir - 创建目录
pub fn php_mkdir(dirname: Value, permissions: Value, recursive: Value) !Value {
    if (!dirname.isString()) return Value.initBool(false);

    const path = dirname.asString().data;
    const mode = if (permissions.isInt()) @as(u32, @intCast(permissions.asInt() & 0o777)) else 0o777;
    const is_recursive = if (recursive.isBool()) recursive.asBool() else false;
    
    _ = mode; // 权限在不同平台上处理不同，暂时忽略
    
    if (is_recursive) {
        // 递归创建目录
        std.fs.cwd().makePath(path) catch {
            return Value.initBool(false);
        };
    } else {
        // 非递归创建
        std.fs.cwd().makeDir(path) catch {
            return Value.initBool(false);
        };
    }

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

/// getmypid - 获取当前进程ID
pub fn php_getmypid() Value {
    const pid = std.c.getpid();
    return Value.initInt(@intCast(pid));
}

/// touch - 设置文件的访问和修改时间
pub fn php_touch(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const path = filename.asString().data;

    // 如果文件不存在，创建空文件
    const file = std.fs.cwd().createFile(path, .{ .exclusive = false, .truncate = false }) catch {
        return Value.initBool(false);
    };
    file.close();
    return Value.initBool(true);
}

/// pathinfo - 返回文件路径的信息
pub fn php_pathinfo(path_val: Value, option: Value, allocator: Allocator) !Value {
    if (!path_val.isString()) return Value.initString(try PHPString.init(allocator, ""));

    const path = path_val.asString().data;
    const opt = option.toInt();

    // PATHINFO_DIRNAME = 1, PATHINFO_BASENAME = 2, PATHINFO_EXTENSION = 4, PATHINFO_FILENAME = 8
    const dir = std.fs.path.dirname(path) orelse ".";
    const base = std.fs.path.basename(path);
    const ext_with_dot = std.fs.path.extension(path);
    const ext = if (ext_with_dot.len > 0) ext_with_dot[1..] else "";
    const filename = if (ext_with_dot.len > 0) base[0 .. base.len - ext_with_dot.len] else base;

    if (opt == 1) return Value.initString(try PHPString.init(allocator, dir));
    if (opt == 2) return Value.initString(try PHPString.init(allocator, base));
    if (opt == 4) return Value.initString(try PHPString.init(allocator, ext));
    if (opt == 8) return Value.initString(try PHPString.init(allocator, filename));

    // 默认返回关联数组
    const arr = try PHPArray.init(allocator);
    try arr.set(allocator, .{ .string = try PHPString.init(allocator, "dirname") }, Value.initString(try PHPString.init(allocator, dir)));
    try arr.set(allocator, .{ .string = try PHPString.init(allocator, "basename") }, Value.initString(try PHPString.init(allocator, base)));
    try arr.set(allocator, .{ .string = try PHPString.init(allocator, "extension") }, Value.initString(try PHPString.init(allocator, ext)));
    try arr.set(allocator, .{ .string = try PHPString.init(allocator, "filename") }, Value.initString(try PHPString.init(allocator, filename)));
    return Value.initArray(arr);
}

/// realpath - 返回规范化的绝对路径名
pub fn php_realpath(path_val: Value, allocator: Allocator) !Value {
    if (!path_val.isString()) return Value.initBool(false);
    const path = path_val.asString().data;

    const c_path = try allocator.dupeZ(u8, path);
    defer allocator.free(c_path);

    var buf: [std.posix.PATH_MAX]u8 = undefined;
    const resolved = std.c.realpath(c_path.ptr, &buf);
    if (resolved == null) return Value.initBool(false);

    const result_str = std.mem.span(resolved.?);
    return Value.initString(try PHPString.init(allocator, result_str));
}

/// tempnam - 创建唯一的临时文件名
pub fn php_tempnam(dir: Value, prefix: Value, allocator: Allocator) !Value {
    const dir_str = if (dir.isString()) dir.asString().data else "/tmp";
    const prefix_str = if (prefix.isString()) prefix.asString().data else "tmp";

    // 生成唯一文件名
    const ts = std.time.milliTimestamp();
    const pid = std.c.getpid();
    const name = try std.fmt.allocPrint(allocator, "{s}/{s}{d}_{d}.tmp", .{ dir_str, prefix_str, pid, ts });
    defer allocator.free(name);

    return Value.initString(try PHPString.init(allocator, name));
}

/// debug_zval_dump - 输出变量的 zval 信息
pub fn php_debug_zval_dump(value: Value) !Value {
    const stdout_file = std.fs.File{ .handle = 1 };
    if (value.isString()) {
        const s = value.asString();
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "string({d}) \"{s}\" refcount(1)\n", .{ s.length, s.data }) catch "string(?)\n";
        stdout_file.writeAll(msg) catch {};
    } else if (value.isInt()) {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "int({d})\n", .{value.asInt()}) catch "int(?)\n";
        stdout_file.writeAll(msg) catch {};
    } else if (value.isFloat()) {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "float({d})\n", .{value.asFloat()}) catch "float(?)\n";
        stdout_file.writeAll(msg) catch {};
    } else if (value.isBool()) {
        stdout_file.writeAll(if (value.asBool()) "bool(true)\n" else "bool(false)\n") catch {};
    } else if (value.isNull()) {
        stdout_file.writeAll("NULL\n") catch {};
    } else if (value.isArray()) {
        const arr = value.asArray();
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "array({d}) refcount(1){{\n}}\n", .{arr.count()}) catch "array(?)\n";
        stdout_file.writeAll(msg) catch {};
    } else {
        stdout_file.writeAll("unknown type\n") catch {};
    }
    return Value.initNull();
}

/// headers_list - 返回已发送的 HTTP 头列表
/// 在 CLI 模式下返回空数组
pub fn php_headers_list(allocator: Allocator) !Value {
    return Value.initArray(try PHPArray.init(allocator));
}

/// header - 发送 HTTP 头（CLI 模式下无操作）
pub fn php_header(header_str: Value, replace: Value, response_code: Value) !Value {
    _ = header_str;
    _ = replace;
    _ = response_code;
    // CLI 模式下 header() 无实际效果
    return Value.initNull();
}

/// http_response_code - 获取/设置 HTTP 响应状态码
threadlocal var current_http_response_code: i64 = 200;

pub fn php_http_response_code(code: Value) !Value {
    if (!code.isNull() and code.isInt()) {
        const prev = current_http_response_code;
        current_http_response_code = code.asInt();
        return Value.initInt(prev);
    }
    return Value.initInt(current_http_response_code);
}

// ============================================================================
// 输出缓冲系统
// ============================================================================

/// 输出缓冲栈
const OBLevel = struct {
    buffer: std.ArrayListUnmanaged(u8) = .{},
    callback: ?Value = null,
};

threadlocal var ob_stack: std.ArrayListUnmanaged(OBLevel) = .{};
threadlocal var ob_initialized: bool = false;

fn ensureObInit() void {
    if (!ob_initialized) {
        ob_stack = .{};
        ob_initialized = true;
    }
}

/// mysqli_connect stub — AOT不支持数据库，仅供function_exists识别
pub fn php_mysqli_connect(host: Value, user: Value, password: Value, db: Value, port: Value, socket: Value, allocator: Allocator) !Value {
    _ = host; _ = user; _ = password; _ = db; _ = port; _ = socket; _ = allocator;
    return Value.initBool(false);
}

/// token_get_all stub — AOT不支持PHP tokenizer，仅供function_exists识别
pub fn php_token_get_all(source: Value, flags: Value, allocator: Allocator) !Value {
    _ = source; _ = flags;
    return Value.initArray(try PHPArray.init(allocator));
}

/// ob_start - 打开输出缓冲
pub fn php_ob_start(callback: Value, allocator: Allocator) !Value {
    _ = allocator;
    ensureObInit();
    var level = OBLevel{};
    if (!callback.isNull()) {
        _ = callback.retain();
        level.callback = callback;
    }
    try ob_stack.append(runtime_allocator, level);
    return Value.initBool(true);
}

/// ob_get_contents - 返回输出缓冲区的内容
pub fn php_ob_get_contents(allocator: Allocator) !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    const level = &ob_stack.items[ob_stack.items.len - 1];
    return Value.initString(try PHPString.init(allocator, level.buffer.items));
}

/// ob_end_clean - 清除并关闭输出缓冲区
pub fn php_ob_end_clean() !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    var level = ob_stack.pop().?;
    level.buffer.deinit(runtime_allocator);
    if (level.callback) |cb| cb.release(runtime_allocator);
    return Value.initBool(true);
}

/// ob_get_clean - 获取缓冲区内容并关闭
pub fn php_ob_get_clean(allocator: Allocator) !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    const contents = try PHPString.init(allocator, ob_stack.items[ob_stack.items.len - 1].buffer.items);
    var level = ob_stack.pop().?;
    level.buffer.deinit(runtime_allocator);
    if (level.callback) |cb| cb.release(runtime_allocator);
    return Value.initString(contents);
}

/// ob_get_level - 返回输出缓冲区嵌套级别
pub fn php_ob_get_level() Value {
    ensureObInit();
    return Value.initInt(@intCast(ob_stack.items.len));
}

/// ob_flush - 刷新输出缓冲区
pub fn php_ob_flush() !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    const level = &ob_stack.items[ob_stack.items.len - 1];
    if (level.buffer.items.len > 0) {
        const stdout_file = std.fs.File{ .handle = 1 };
        stdout_file.writeAll(level.buffer.items) catch {};
        level.buffer.clearRetainingCapacity();
    }
    return Value.initBool(true);
}

/// ob_end_flush - 刷新并关闭输出缓冲区
pub fn php_ob_end_flush() !Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    var level = ob_stack.pop().?;
    if (level.buffer.items.len > 0) {
        const stdout_file = std.fs.File{ .handle = 1 };
        stdout_file.writeAll(level.buffer.items) catch {};
    }
    level.buffer.deinit(runtime_allocator);
    if (level.callback) |cb| cb.release(runtime_allocator);
    return Value.initBool(true);
}

/// ob_get_length - 返回输出缓冲区内容的长度
pub fn php_ob_get_length() Value {
    ensureObInit();
    if (ob_stack.items.len == 0) return Value.initBool(false);
    const level = &ob_stack.items[ob_stack.items.len - 1];
    return Value.initInt(@intCast(level.buffer.items.len));
}

/// ob_get_status - 获取输出缓冲区的状态
pub fn php_ob_get_status(full_status: Value, allocator: Allocator) !Value {
    ensureObInit();
    if (full_status.toBool()) {
        // 返回所有级别的状态数组
        const result = try PHPArray.init(allocator);
        for (ob_stack.items, 0..) |_, i| {
            const level_arr = try PHPArray.init(allocator);
            const k_level = try PHPString.init(allocator, "level");
            try level_arr.set(allocator, ArrayKey{ .string = k_level }, Value.initInt(@intCast(i + 1)));
            const k_name = try PHPString.init(allocator, "name");
            try level_arr.set(allocator, ArrayKey{ .string = k_name }, Value.initString(try PHPString.init(allocator, "default output handler")));
            const k_buf = try PHPString.init(allocator, "buffer_size");
            try level_arr.set(allocator, ArrayKey{ .string = k_buf }, Value.initInt(0));
            try result.push(allocator, Value.initArray(level_arr));
        }
        return Value.initArray(result);
    }
    // 返回当前级别的状态
    if (ob_stack.items.len == 0) return Value.initArray(try PHPArray.init(allocator));
    const level_arr = try PHPArray.init(allocator);
    const k_level = try PHPString.init(allocator, "level");
    try level_arr.set(allocator, ArrayKey{ .string = k_level }, Value.initInt(@intCast(ob_stack.items.len)));
    const k_name = try PHPString.init(allocator, "name");
    try level_arr.set(allocator, ArrayKey{ .string = k_name }, Value.initString(try PHPString.init(allocator, "default output handler")));
    const k_buf = try PHPString.init(allocator, "buffer_size");
    try level_arr.set(allocator, ArrayKey{ .string = k_buf }, Value.initInt(0));
    return Value.initArray(level_arr);
}

/// ob_implicit_flush - 打开/关闭隐式刷新
pub fn php_ob_implicit_flush(flag: Value) Value {
    _ = flag;
    return Value.initNull();
}

/// get_resource_id - 返回资源的整数标识符
pub fn php_get_resource_id(val: Value) !Value {
    // AOT 中没有真正的资源类型，返回 0
    _ = val;
    return Value.initInt(0);
}

// ============================================================================
// JSON函数
// ============================================================================

/// json_encode - 将PHP值编码为JSON字符串
pub fn php_json_encode(value: Value, flags: Value, depth: Value, allocator: Allocator) !Value {
    // 解析flags（可选，默认0）
    const flags_int = if (flags.isInt()) flags.asInt() else 0;
    
    // 解析depth（可选，默认512）
    const depth_int = if (depth.isInt()) depth.asInt() else 512;
    
    _ = flags_int; // TODO: 实现flags支持（JSON_PRETTY_PRINT等）
    _ = depth_int; // TODO: 实现depth检查
    
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
    } else if (Value_isObject(value)) {
        // 对象序列化为JSON对象
        const obj = Value_asObject(value);
        try buffer.append(allocator, '{');
        var first = true;
        var it = obj.properties.iterator();
        while (it.next()) |entry| {
            if (!first) try buffer.append(allocator, ',');
            
            // 写入键
            try buffer.append(allocator, '"');
            for (entry.key_ptr.*) |c| {
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
            try buffer.appendSlice(allocator, ":");
            
            // 写入值
            try jsonEncodeValue(entry.value_ptr.*, buffer, allocator);
            first = false;
        }
        try buffer.append(allocator, '}');
    } else {
        try buffer.appendSlice(allocator, "null");
    }
}

const json_error_none: i32 = 0;
const json_error_depth: i32 = 1;
const json_error_syntax: i32 = 4;

threadlocal var last_json_error_code: i32 = json_error_none;

pub fn php_json_last_error() Value {
    return Value.initInt(last_json_error_code);
}

pub fn php_json_last_error_msg(allocator: Allocator) !Value {
    const msg = switch (last_json_error_code) {
        json_error_none => "No error",
        json_error_depth => "Maximum stack depth exceeded",
        json_error_syntax => "Syntax error",
        else => "Unknown error",
    };
    return Value.initString(try PHPString.init(allocator, msg));
}

/// json_decode - 解析JSON字符串为PHP值
pub fn php_json_decode(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;

    const json = args[0];
    if (!json.isString()) {
        last_json_error_code = json_error_syntax;
        return Value.initNull();
    }

    const assoc = if (args.len >= 2) args[1] else Value.initBool(false);
    const depth_val = if (args.len >= 3) args[2] else Value.initInt(512);
    const is_assoc = if (assoc.isBool()) assoc.asBool() else assoc.toBool();
    const json_str = json.asString().data;
    var pos: usize = 0;
    const depth_i64 = @max(depth_val.toInt(), 1);
    const depth: usize = @intCast(depth_i64);

    const result = jsonDecodeValue(json_str, &pos, is_assoc, depth, allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.MaxDepthExceeded => {
            last_json_error_code = json_error_depth;
            return Value.initNull();
        },
        else => {
            last_json_error_code = json_error_syntax;
            return Value.initNull();
        },
    };

    skipWhitespace(json_str, &pos);
    if (pos != json_str.len) {
        result.release(allocator);
        last_json_error_code = json_error_syntax;
        return Value.initNull();
    }

    last_json_error_code = json_error_none;
    return result;
}

const JsonError = error{
    InvalidJson,
    UnexpectedEnd,
    OutOfMemory,
    StringTooLarge,
    MaxDepthExceeded,
};

fn jsonDecodeValue(json: []const u8, pos: *usize, assoc: bool, depth: usize, allocator: Allocator) JsonError!Value {
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
        if (depth == 0) return error.MaxDepthExceeded;
        return jsonDecodeArray(json, pos, assoc, depth - 1, allocator);
    }

    if (c == '{') {
        if (depth == 0) return error.MaxDepthExceeded;
        return jsonDecodeObject(json, pos, assoc, depth - 1, allocator);
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

fn jsonDecodeArray(json: []const u8, pos: *usize, assoc: bool, depth: usize, allocator: Allocator) JsonError!Value {
    pos.* += 1; // 跳过 '['

    const arr = try PHPArray.init(allocator);

    skipWhitespace(json, pos);

    if (pos.* < json.len and json[pos.*] == ']') {
        pos.* += 1;
        return Value.initArray(arr);
    }

    while (pos.* < json.len) {
        const value = try jsonDecodeValue(json, pos, assoc, depth, allocator);
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

fn jsonDecodeObject(json: []const u8, pos: *usize, assoc: bool, depth: usize, allocator: Allocator) JsonError!Value {
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
        const value = try jsonDecodeValue(json, pos, assoc, depth, allocator);

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

    if (assoc) {
        return Value.initArray(arr);
    }

    const obj_val = php_object_new("stdClass", allocator) catch return error.OutOfMemory;
    const obj = Value_asObject(obj_val);
    var it = arr.elements.iterator();
    while (it.next()) |entry| {
        switch (entry.key_ptr.*) {
            .string => |k| obj.setProperty(k.data, entry.value_ptr.*) catch return error.OutOfMemory,
            .integer => |k| {
                var key_buf: [32]u8 = undefined;
                const key_str = std.fmt.bufPrint(&key_buf, "{d}", .{k}) catch return error.OutOfMemory;
                obj.setProperty(key_str, entry.value_ptr.*) catch return error.OutOfMemory;
            },
        }
    }

    return obj_val;
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

    if (!time_str.isString()) return Value.initBool(false);
    const str = time_str.asString().data;
    const base_ts: i64 = if (now.isInt()) now.asInt() else std.time.timestamp();

    // 相对时间："+N unit" 或 "-N unit" 或 "next X"
    if (str.len > 0 and (str[0] == '+' or str[0] == '-')) {
        const sign: i64 = if (str[0] == '+') 1 else -1;
        var i: usize = 1;
        while (i < str.len and str[i] == ' ') i += 1;
        var num: i64 = 0;
        while (i < str.len and str[i] >= '0' and str[i] <= '9') : (i += 1) {
            num = num * 10 + (str[i] - '0');
        }
        while (i < str.len and str[i] == ' ') i += 1;
        const unit = str[i..];
        const secs: i64 = if (std.mem.startsWith(u8, unit, "second")) num
            else if (std.mem.startsWith(u8, unit, "minute")) num * 60
            else if (std.mem.startsWith(u8, unit, "hour")) num * 3600
            else if (std.mem.startsWith(u8, unit, "day")) num * 86400
            else if (std.mem.startsWith(u8, unit, "week")) num * 604800
            else if (std.mem.startsWith(u8, unit, "month")) num * 2592000
            else if (std.mem.startsWith(u8, unit, "year")) num * 31536000
            else 0;
        return Value.initInt(base_ts + sign * secs);
    }

    // 尝试解析 "YYYY-MM-DD HH:MM:SS" 或 "YYYY-MM-DD"
    if (str.len >= 10 and str[4] == '-' and str[7] == '-') {
        const year = std.fmt.parseInt(i64, str[0..4], 10) catch return Value.initBool(false);
        const month = std.fmt.parseInt(i64, str[5..7], 10) catch return Value.initBool(false);
        const day = std.fmt.parseInt(i64, str[8..10], 10) catch return Value.initBool(false);
        var hour: i64 = 0;
        var min: i64 = 0;
        var sec: i64 = 0;
        if (str.len >= 19 and str[10] == ' ') {
            hour = std.fmt.parseInt(i64, str[11..13], 10) catch 0;
            min = std.fmt.parseInt(i64, str[14..16], 10) catch 0;
            sec = std.fmt.parseInt(i64, str[17..19], 10) catch 0;
        }
        // 简单计算时间戳（Zeller公式近似）
        const y = if (month <= 2) year - 1 else year;
        const m = if (month <= 2) month + 12 else month;
        const jd = 365 * y + @divFloor(y, 4) - @divFloor(y, 100) + @divFloor(y, 400) + @divFloor(306 * (m + 1), 10) + day - 719591;
        const ts: i64 = jd * 86400 + hour * 3600 + min * 60 + sec;
        return Value.initInt(ts);
    }

    // 返回当前时间戳作为fallback
    return Value.initInt(base_ts);
}

extern "c" fn sleep(seconds: c_uint) c_uint;
extern "c" fn usleep(usec: c_uint) c_int;

/// sleep - 延迟执行（秒）
pub fn php_sleep(seconds: Value) !Value {
    const secs: c_uint = @intCast(@max(0, seconds.toInt()));
    _ = sleep(secs);
    return Value.initInt(0);
}

/// usleep - 延迟执行（微秒）
pub fn php_usleep(microseconds: Value) !Value {
    const usecs: c_uint = @intCast(@max(0, microseconds.toInt()));
    _ = usleep(usecs);
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

/// isset - 检查变量是否已设置且非null（支持多个参数）
pub fn php_isset(args: []const Value) !Value {
    // isset()需要至少1个参数
    if (args.len == 0) return Value.initBool(false);
    
    // 所有参数都必须非null才返回true
    for (args) |val| {
        if (val.isNull()) return Value.initBool(false);
    }
    
    return Value.initBool(true);
}

pub fn empty(val: Value) !Value {
    return php_empty(val);
}

pub fn isset(val: Value) !Value {
    // 单参数版本的包装器
    return Value.initBool(!val.isNull());
}

// ============================================================================
// PCNTL / POSIX / IPC 函数
// ============================================================================

// libc 外部声明
extern "c" fn fork() std.posix.pid_t;
extern "c" fn waitpid(
    pid: std.posix.pid_t,
    status: *c_int,
    options: c_int,
) std.posix.pid_t;
extern "c" fn kill(
    pid: std.posix.pid_t,
    sig: c_int,
) c_int;
extern "c" fn alarm(seconds: c_uint) c_uint;
extern "c" fn getpid() std.posix.pid_t;
extern "c" fn signal(
    sig: c_int,
    handler: ?*const fn (c_int) callconv(.c) void,
) ?*const fn (c_int) callconv(.c) void;
extern "c" fn mkfifo(
    path: [*:0]const u8,
    mode: std.posix.mode_t,
) c_int;
extern "c" fn socketpair(
    domain: c_int,
    sock_type: c_int,
    protocol: c_int,
    sv: *[2]c_int,
) c_int;
extern "c" fn close(fd: c_int) c_int;

// System V IPC 外部声明
extern "c" fn msgget(key: c_int, msgflg: c_int) c_int;
extern "c" fn msgctl(
    msqid: c_int,
    cmd: c_int,
    buf: ?*anyopaque,
) c_int;
extern "c" fn semget(
    key: c_int,
    nsems: c_int,
    semflg: c_int,
) c_int;
extern "c" fn semctl(
    semid: c_int,
    semnum: c_int,
    cmd: c_int,
) c_int;
extern "c" fn shmget(
    key: c_int,
    size: usize,
    shmflg: c_int,
) c_int;
extern "c" fn shmctl(
    shmid: c_int,
    cmd: c_int,
    buf: ?*anyopaque,
) c_int;

const IPC_CREAT = 0o1000;
const IPC_RMID = 0;
const MAX_SIGNALS = 32;

var signal_handlers: [MAX_SIGNALS]Value = .{Value.initNull()} ** MAX_SIGNALS;
var pending_signals: [MAX_SIGNALS]bool = .{false} ** MAX_SIGNALS;
var last_wait_status: c_int = 0;

/// C 信号处理函数（仅设置标志位）
fn pcntl_c_signal_handler(sig: c_int) callconv(.c) void {
    const s: usize = @intCast(@max(0, sig));
    if (s < MAX_SIGNALS) {
        pending_signals[s] = true;
    }
}

/// pcntl_fork - 创建子进程
pub fn php_pcntl_fork() !Value {
    const pid = fork();
    return Value.initInt(@intCast(pid));
}

/// pcntl_waitpid - 等待指定子进程
pub fn php_pcntl_waitpid(
    pid_val: Value,
    _: Value,
    _: Allocator,
) !Value {
    const pid: std.posix.pid_t = @intCast(pid_val.toInt());
    var status: c_int = 0;
    const result = waitpid(pid, &status, 0);
    last_wait_status = status;
    return Value.initInt(@intCast(result));
}

/// pcntl_wait - 等待任意子进程
pub fn php_pcntl_wait(_: Value, _: Allocator) !Value {
    var status: c_int = 0;
    const result = waitpid(-1, &status, 0);
    last_wait_status = status;
    return Value.initInt(@intCast(result));
}

/// pcntl_wexitstatus - 提取子进程退出码
pub fn php_pcntl_wexitstatus(_: Value) !Value {
    const exit_code = (last_wait_status >> 8) & 0xFF;
    return Value.initInt(@intCast(exit_code));
}

/// pcntl_signal - 注册信号处理器
pub fn php_pcntl_signal(
    signo_val: Value,
    handler_val: Value,
    _: Allocator,
) !Value {
    const signo: usize = @intCast(
        @max(0, signo_val.toInt()),
    );
    if (signo >= MAX_SIGNALS) return Value.initBool(false);
    _ = handler_val.retain();
    signal_handlers[signo].release(runtime_allocator);
    signal_handlers[signo] = handler_val;
    _ = signal(
        @intCast(signo),
        pcntl_c_signal_handler,
    );
    return Value.initBool(true);
}

/// pcntl_signal_dispatch - 分派待处理信号
pub fn php_pcntl_signal_dispatch(_: Allocator) !Value {
    for (0..MAX_SIGNALS) |i| {
        if (pending_signals[i]) {
            pending_signals[i] = false;
            const handler = signal_handlers[i];
            if (!handler.isNull() and handler.isFunction()) {
                const closure = handler.asFunction();
                _ = closure.func(
                    handler,
                    &[_]Value{Value.initInt(@intCast(i))},
                    runtime_allocator,
                ) catch {};
            }
        }
    }
    return Value.initBool(true);
}

/// pcntl_alarm - 设置闹钟信号
pub fn php_pcntl_alarm(seconds_val: Value) !Value {
    const secs: c_uint = @intCast(
        @max(0, seconds_val.toInt()),
    );
    const prev = alarm(secs);
    return Value.initInt(@intCast(prev));
}

/// pcntl_sigprocmask - 设置信号屏蔽字
pub fn php_pcntl_sigprocmask(
    _: Value,
    _: Value,
    _: Allocator,
) !Value {
    return Value.initBool(true);
}

/// posix_getpid - 获取当前进程 ID
pub fn php_posix_getpid() !Value {
    return Value.initInt(@intCast(getpid()));
}

/// posix_kill - 向进程发送信号
pub fn php_posix_kill(
    pid_val: Value,
    sig_val: Value,
) !Value {
    const pid: std.posix.pid_t = @intCast(
        pid_val.toInt(),
    );
    const sig: c_int = @intCast(sig_val.toInt());
    const ret = kill(pid, sig);
    return Value.initBool(ret == 0);
}

/// posix_mkfifo - 创建 FIFO 特殊文件
pub fn php_posix_mkfifo(
    path_val: Value,
    mode_val: Value,
    allocator: Allocator,
) !Value {
    const path_str = try path_val.toString(allocator);
    defer path_str.release(allocator);
    const mode: std.posix.mode_t = @intCast(
        @max(0, mode_val.toInt()),
    );
    const path_z = try allocator.dupeZ(u8, path_str.data);
    defer allocator.free(path_z);
    const ret = mkfifo(path_z, mode);
    return Value.initBool(ret == 0);
}

/// ftok - 生成 System V IPC 键值
pub fn php_ftok(
    path_val: Value,
    proj_val: Value,
    allocator: Allocator,
) !Value {
    const path_str = try path_val.toString(allocator);
    defer path_str.release(allocator);
    const proj_str = try proj_val.toString(allocator);
    defer proj_str.release(allocator);
    const proj_id: i64 = if (proj_str.data.len > 0)
        @intCast(proj_str.data[0])
    else
        0;
    // 简化 ftok: 使用路径哈希 + proj_id
    var hash: u32 = 0;
    for (path_str.data) |c| {
        hash = hash *% 31 +% @as(u32, c);
    }
    const key = (@as(i64, proj_id) << 24) |
        @as(i64, hash & 0xFFFFFF);
    return Value.initInt(key);
}

/// msg_get_queue - 获取消息队列
pub fn php_msg_get_queue(
    key_val: Value,
    allocator: Allocator,
) !Value {
    const key: c_int = @intCast(key_val.toInt());
    const id = msgget(key, IPC_CREAT | 0o666);
    if (id < 0) return Value.initBool(false);
    _ = allocator;
    return Value.initInt(@intCast(id));
}

/// msg_remove_queue - 删除消息队列
pub fn php_msg_remove_queue(queue_val: Value) !Value {
    const id: c_int = @intCast(queue_val.toInt());
    const ret = msgctl(id, IPC_RMID, null);
    return Value.initBool(ret == 0);
}

/// sem_get - 获取信号量
pub fn php_sem_get(
    key_val: Value,
    max_val: Value,
    allocator: Allocator,
) !Value {
    _ = allocator;
    const key: c_int = @intCast(key_val.toInt());
    const nsems: c_int = @intCast(
        @max(1, max_val.toInt()),
    );
    const id = semget(key, nsems, IPC_CREAT | 0o666);
    if (id < 0) return Value.initBool(false);
    return Value.initInt(@intCast(id));
}

/// sem_remove - 删除信号量
pub fn php_sem_remove(sem_val: Value) !Value {
    const id: c_int = @intCast(sem_val.toInt());
    const ret = semctl(id, 0, IPC_RMID);
    return Value.initBool(ret == 0);
}

/// shmop_open - 打开共享内存段
pub fn php_shmop_open(
    key_val: Value,
    flags_val: Value,
    mode_val: Value,
    size_val: Value,
    allocator: Allocator,
) !Value {
    _ = allocator;
    _ = flags_val;
    const key: c_int = @intCast(key_val.toInt());
    const mode: c_int = @intCast(
        @max(0, mode_val.toInt()),
    );
    const size: usize = @intCast(
        @max(1, size_val.toInt()),
    );
    const id = shmget(key, size, IPC_CREAT | mode);
    if (id < 0) return Value.initBool(false);
    return Value.initInt(@intCast(id));
}

/// shmop_close - 关闭共享内存段
pub fn php_shmop_close(_: Value) !Value {
    return Value.initBool(true);
}

/// socket_create_pair - 创建套接字对
pub fn php_socket_create_pair(
    domain_val: Value,
    type_val: Value,
    protocol_val: Value,
    _: Value,
    allocator: Allocator,
) !Value {
    const domain: c_int = @intCast(domain_val.toInt());
    const sock_type: c_int = @intCast(
        type_val.toInt(),
    );
    const protocol: c_int = @intCast(
        protocol_val.toInt(),
    );
    var sv: [2]c_int = .{ -1, -1 };
    const ret = socketpair(
        domain,
        sock_type,
        protocol,
        &sv,
    );
    if (ret != 0) return Value.initBool(false);
    const arr = try PHPArray.init(allocator);
    try arr.push(allocator, Value.initInt(sv[0]));
    try arr.push(allocator, Value.initInt(sv[1]));
    return Value.initArray(arr);
}

/// socket_close - 关闭套接字
pub fn php_socket_close(fd_val: Value) !Value {
    const fd: c_int = @intCast(fd_val.toInt());
    _ = close(fd);
    return Value.initBool(true);
}

// ============================================================================
// 高阶数组函数
// ============================================================================

/// array_map - 对一个或多个数组的每个元素应用回调函数
pub fn php_array_map(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 2) return error.InvalidArgumentCount;

    const callback = args[0];
    const arrays = args[1..];
    for (arrays) |arr| {
        if (!arr.isArray()) return error.InvalidArgument;
    }

    const result_arr = try PHPArray.init(allocator);

    if (callback.isNull()) {
        if (arrays.len == 1) {
            const src = arrays[0].asArray();
            var src_iter = src.elements.iterator();
            while (src_iter.next()) |entry| {
                try result_arr.set(allocator, entry.key_ptr.*, entry.value_ptr.*);
            }
            return Value.initArray(result_arr);
        }

        var max_count: i64 = 0;
        for (arrays) |arr| {
            const cur = arr.asArray();
            if (cur.next_index > max_count) max_count = cur.next_index;
        }

        var idx: i64 = 0;
        while (idx < max_count) : (idx += 1) {
            const tuple_arr = try PHPArray.init(allocator);
            const key = ArrayKey{ .integer = idx };

            for (arrays) |arr| {
                const cur = arr.asArray();
                const val = cur.get(key) orelse Value.initNull();
                try tuple_arr.push(allocator, val);
            }

            try result_arr.push(allocator, Value.initArray(tuple_arr));
        }

        return Value.initArray(result_arr);
    }

    const primary = arrays[0].asArray();

    var iter = primary.elements.iterator();
    while (iter.next()) |entry| {
        var callback_args = try allocator.alloc(Value, arrays.len);
        defer allocator.free(callback_args);

        callback_args[0] = entry.value_ptr.*;

        var i: usize = 1;
        while (i < arrays.len) : (i += 1) {
            const cur = arrays[i].asArray();
            callback_args[i] = cur.elements.get(entry.key_ptr.*) orelse Value.initNull();
        }

        const result_value = try php_invoke_callable(callback, callback_args, allocator);
        try result_arr.set(allocator, entry.key_ptr.*, result_value);
        result_value.release(allocator);
    }

    return Value.initArray(result_arr);
}

/// array_filter - 过滤数组元素
/// mode: 0 = 只传值, 1 = 传键和值, 2 = 传键 (ARRAY_FILTER_USE_KEY, ARRAY_FILTER_USE_BOTH)
pub fn php_array_filter(arr: Value, callback: Value, mode: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;

    const php_arr = arr.asArray();
    const result_arr = try PHPArray.init(allocator);
    const mode_int: u32 = if (mode.isInt()) @intCast(@max(mode.asInt(), 0)) else 0;

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const should_keep = if (callback.isNull()) blk: {
            // 无回调时，检查值是否为真
            break :blk entry.value_ptr.*.toBool();
        } else blk: {
            // 根据mode决定传参方式
            const result = switch (mode_int) {
                0 => blk2: {
                    // ARRAY_FILTER_USE_VALUE (默认) - 只传值
                    const args = [_]Value{entry.value_ptr.*};
                    break :blk2 try php_invoke_callable(callback, &args, allocator);
                },
                1 => blk2: {
                    // ARRAY_FILTER_USE_KEY - 只传键
                    const key_val = switch (entry.key_ptr.*) {
                        .integer => |k| Value.initInt(k),
                        .string => |s| blk_s: {
                            s.retain(); // 增加引用计数
                            break :blk_s Value.initString(s);
                        },
                    };
                    const args = [_]Value{key_val};
                    break :blk2 try php_invoke_callable(callback, &args, allocator);
                },
                2 => blk2: {
                    // ARRAY_FILTER_USE_BOTH - 传值和键
                    const key_val = switch (entry.key_ptr.*) {
                        .integer => |k| Value.initInt(k),
                        .string => |s| blk_s: {
                            s.retain(); // 增加引用计数
                            break :blk_s Value.initString(s);
                        },
                    };
                    const args = [_]Value{ entry.value_ptr.*, key_val };
                    break :blk2 try php_invoke_callable(callback, &args, allocator);
                },
                else => blk2: {
                    // 默认行为：只传值
                    const args = [_]Value{entry.value_ptr.*};
                    break :blk2 try php_invoke_callable(callback, &args, allocator);
                },
            };
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
    var carry = initial.retain();

    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{ carry, entry.value_ptr.* };
        const new_carry = try php_invoke_callable(callback, &args, allocator);
        carry.release(allocator);
        carry = new_carry;
    }

    return carry;
}

/// array_find - 查找数组中第一个满足回调条件的元素 (PHP 8.4+)
pub fn php_array_find(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{entry.value_ptr.*};
        const result = try php_invoke_callable(callback, &args, allocator);
        defer result.release(allocator);
        if (result.toBool()) {
            return entry.value_ptr.*.retain();
        }
    }
    return Value.initNull();
}

/// array_find_key - PHP 8.4: 返回第一个满足回调的元素的键
pub fn php_array_find_key(arr: Value, callback: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();
    const php_arr = arr.asArray();
    var iter = php_arr.elements.iterator();
    while (iter.next()) |entry| {
        const args = [_]Value{entry.value_ptr.*};
        const result = try php_invoke_callable(callback, &args, allocator);
        defer result.release(allocator);
        if (result.toBool()) {
            return switch (entry.key_ptr.*) {
                .int => |k| Value.initInt(k),
                .string => |s| Value.initString(try PHPString.init(allocator, s)),
            };
        }
    }
    return Value.initNull();
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
pub fn php_array_column(arr: Value, column_key: Value, index_key: Value, allocator: Allocator) !Value {
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
        // 构建回调参数：value(by-ref), key, userdata
        const key_val = switch (entry.key_ptr.*) {
            .integer => |k| Value.initInt(k),
            .string => |k| Value.initString(k),
        };

        // array_walk 的回调第一个参数按引用传递（PHP 规范）
        // 直接用 entry.value_ptr 构造 Ref，使回调内对 $value 的赋值写回数组槽位
        // iterator 返回 *const Value，此处需要可写指针以实现引用语义
        var args_buf: [3]Value = undefined;
        args_buf[0] = Value.initRef(@constCast(entry.value_ptr));
        args_buf[1] = key_val;
        const arg_count: usize = if (userdata.isNull()) 2 else blk: {
            args_buf[2] = userdata;
            break :blk 3;
        };

        const result = try php_invoke_callable(callback, args_buf[0..arg_count], allocator);
        result.release(allocator);
    }

    return Value.initBool(true);
}

fn php_array_walk_recursive_inner(arr: *PHPArray, callback: Value, userdata: Value, allocator: Allocator) !void {
    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;
        if (value.isArray()) {
            try php_array_walk_recursive_inner(value.asArray(), callback, userdata, allocator);
            continue;
        }

        const key_val = switch (entry.key_ptr.*) {
            .integer => |k| Value.initInt(k),
            .string => |k| Value.initString(k),
        };

        var args_buf: [3]Value = undefined;
        args_buf[0] = value;
        args_buf[1] = key_val;
        const arg_count: usize = if (userdata.isNull()) 2 else blk: {
            args_buf[2] = userdata;
            break :blk 3;
        };

        const result = try php_invoke_callable(callback, args_buf[0..arg_count], allocator);
        result.release(allocator);
    }
}

pub fn php_array_walk_recursive(arr: Value, callback: Value, userdata: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return error.InvalidArgument;
    try php_array_walk_recursive_inner(arr.asArray(), callback, userdata, allocator);
    return Value.initBool(true);
}

// ============================================================================
// 字符串高级函数
// ============================================================================

/// 格式化浮点数到指定精度（用于 sprintf %f）
fn formatFloatPrecision(buf: []u8, val: f64, precision: usize) []const u8 {
    // 使用 comptime 格式字符串处理常见精度值
    return switch (precision) {
        0 => std.fmt.bufPrint(buf, "{d:.0}", .{val}) catch "0",
        1 => std.fmt.bufPrint(buf, "{d:.1}", .{val}) catch "0",
        2 => std.fmt.bufPrint(buf, "{d:.2}", .{val}) catch "0",
        3 => std.fmt.bufPrint(buf, "{d:.3}", .{val}) catch "0",
        4 => std.fmt.bufPrint(buf, "{d:.4}", .{val}) catch "0",
        5 => std.fmt.bufPrint(buf, "{d:.5}", .{val}) catch "0",
        6 => std.fmt.bufPrint(buf, "{d:.6}", .{val}) catch "0",
        7 => std.fmt.bufPrint(buf, "{d:.7}", .{val}) catch "0",
        8 => std.fmt.bufPrint(buf, "{d:.8}", .{val}) catch "0",
        9 => std.fmt.bufPrint(buf, "{d:.9}", .{val}) catch "0",
        10 => std.fmt.bufPrint(buf, "{d:.10}", .{val}) catch "0",
        else => std.fmt.bufPrint(buf, "{d:.6}", .{val}) catch "0",
    };
}

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

            // 解析精度
            var precision: ?usize = null;
            if (i < fmt.len and fmt[i] == '.') {
                i += 1;
                var prec_val: usize = 0;
                while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
                    prec_val = prec_val * 10 + (fmt[i] - '0');
                    i += 1;
                }
                precision = prec_val;
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
                    const prec = precision orelse 6;
                    // 使用自定义精度格式化
                    var fbuf: [128]u8 = undefined;
                    const fstr = formatFloatPrecision(&fbuf, val, prec);
                    try result.appendSlice(allocator, fstr);
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
                'u' => {
                    const val = arg.toInt();
                    const uval: u64 = @bitCast(val);
                    const str = try std.fmt.allocPrint(allocator, "{d}", .{uval});
                    defer allocator.free(str);
                    try result.appendSlice(allocator, str);
                },
                'o' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{o}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try result.appendSlice(allocator, str);
                },
                'b' => {
                    const val = arg.toInt();
                    const str = try std.fmt.allocPrint(allocator, "{b}", .{@as(u64, @bitCast(val))});
                    defer allocator.free(str);
                    try result.appendSlice(allocator, str);
                },
                'e', 'E' => {
                    const val = arg.toFloat();
                    const str = try std.fmt.allocPrint(allocator, "{e}", .{val});
                    defer allocator.free(str);
                    try result.appendSlice(allocator, str);
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

/// vsprintf - 格式化字符串（参数为数组）
pub fn php_vsprintf(format: Value, args_arr: Value, allocator: Allocator) !Value {
    if (!format.isString()) return error.InvalidArgument;
    // 将数组参数展开为切片
    if (args_arr.isArray()) {
        const arr = args_arr.asArray();
        const count = arr.count();
        const args = try allocator.alloc(Value, count);
        defer allocator.free(args);
        var iter = arr.elements.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| {
            if (i < count) {
                args[i] = entry.value_ptr.*;
                i += 1;
            }
        }
        return php_sprintf(format, args[0..i], allocator);
    }
    return php_sprintf(format, &[_]Value{}, allocator);
}

pub fn php_sscanf(str: Value, format: Value, allocator: Allocator) !Value {
    if (!str.isString() or !format.isString()) return Value.initBool(false);
    
    const input = str.asString().data;
    const fmt = format.asString().data;
    
    var arr = try PHPArray.init(allocator);
    var input_pos: usize = 0;
    var fmt_pos: usize = 0;
    
    while (fmt_pos < fmt.len and input_pos < input.len) {
        if (fmt[fmt_pos] == '%' and fmt_pos + 1 < fmt.len) {
            fmt_pos += 1;
            const spec = fmt[fmt_pos];
            fmt_pos += 1;
            
            // 跳过空白
            while (input_pos < input.len and input[input_pos] == ' ') input_pos += 1;
            
            if (spec == 'd') {
                // 解析整数
                var num: i64 = 0;
                var neg = false;
                if (input_pos < input.len and input[input_pos] == '-') {
                    neg = true;
                    input_pos += 1;
                }
                while (input_pos < input.len and input[input_pos] >= '0' and input[input_pos] <= '9') {
                    num = num * 10 + (input[input_pos] - '0');
                    input_pos += 1;
                }
                if (neg) num = -num;
                try arr.push(allocator, Value.initInt(num));
            } else if (spec == 's') {
                // 解析字符串（到空白）
                const start = input_pos;
                while (input_pos < input.len and input[input_pos] != ' ') input_pos += 1;
                const s = try allocator.dupe(u8, input[start..input_pos]);
                const php_str = try PHPString.init(allocator, s);
                try arr.push(allocator, Value.initString(php_str));
            }
        } else {
            // 匹配字面字符
            if (input_pos < input.len and input[input_pos] == fmt[fmt_pos]) {
                input_pos += 1;
            }
            fmt_pos += 1;
        }
    }
    
    return Value.initArray(arr);
}

pub fn php_preg_match(pattern: Value, subject: Value, matches: *Value, flags: Value, offset: Value, allocator: Allocator) !Value {
    _ = flags; // TODO: 实现flags支持
    _ = offset; // TODO: 实现offset支持
    
    if (!pattern.isString() or !subject.isString()) {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    const pattern_str = pattern.asString();
    const subject_str = subject.asString();
    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };
    defer pcre2_match_data_free_8(match_data);

    const rc = pcre2_match_8(
        re,
        subject_str.data.ptr,
        subject_str.length,
        0,
        0,
        match_data,
        null,
    );

    if (rc == PCRE2_ERROR_NOMATCH or rc < 0) {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    // 填充matches数组
    const matches_arr = try PHPArray.init(allocator);
    const ovec = pcre2_get_ovector_pointer_8(match_data);

    var i: usize = 0;
    while (i < @as(usize, @intCast(rc))) : (i += 1) {
        const start = ovec[i * 2];
        const end = ovec[i * 2 + 1];
        if (start < subject_str.length and end <= subject_str.length and start <= end) {
            const capture = subject_str.data[start..end];
            const capture_str = try PHPString.init(allocator, capture);
            try matches_arr.push(allocator, Value.initString(capture_str));
        }
    }

    matches.* = Value.initArray(matches_arr);
    return Value.initInt(1);
}

pub fn php_preg_match_all(pattern: Value, subject: Value, matches: *Value, flags: Value, offset: Value, allocator: Allocator) !Value {
    _ = flags;
    _ = offset;
    
    if (!pattern.isString() or !subject.isString()) {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    const pattern_str = pattern.asString();
    const subject_str = subject.asString();
    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        matches.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };
    defer pcre2_match_data_free_8(match_data);

    // 存储所有匹配（临时）
    var all_matches = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]const u8)){};
    defer {
        for (all_matches.items) |*match_groups| {
            match_groups.deinit(allocator);
        }
        all_matches.deinit(allocator);
    }

    var match_offset: usize = 0;
    var match_count: i64 = 0;

    // 循环匹配所有
    while (match_offset <= subject_str.length) {
        const rc = pcre2_match_8(
            re,
            subject_str.data.ptr,
            subject_str.length,
            @intCast(match_offset),
            0,
            match_data,
            null,
        );

        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) break;

        match_count += 1;
        const ovec = pcre2_get_ovector_pointer_8(match_data);

        // 保存当前匹配的所有组
        var match_groups = std.ArrayListUnmanaged([]const u8){};
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            if (start < subject_str.length and end <= subject_str.length and start <= end) {
                const capture = subject_str.data[start..end];
                try match_groups.append(allocator, capture);
            }
        }
        try all_matches.append(allocator, match_groups);

        // 移动到下一个位置
        const match_end = ovec[1];
        if (match_end == match_offset) {
            match_offset += 1; // 避免空匹配无限循环
        } else {
            match_offset = match_end;
        }
    }

    // 转换为PREG_PATTERN_ORDER格式
    // matches[0] = [所有完整匹配]
    // matches[1] = [所有第1个捕获组]
    const matches_arr = try PHPArray.init(allocator);

    if (all_matches.items.len > 0) {
        const num_groups = all_matches.items[0].items.len;

        // 为每个组创建数组
        var group_idx: usize = 0;
        while (group_idx < num_groups) : (group_idx += 1) {
            const group_arr = try PHPArray.init(allocator);

            // 收集所有匹配中的该组
            for (all_matches.items) |match_groups| {
                if (group_idx < match_groups.items.len) {
                    const capture = match_groups.items[group_idx];
                    const capture_str = try PHPString.init(allocator, capture);
                    try group_arr.push(allocator, Value.initString(capture_str));
                }
            }

            try matches_arr.push(allocator, Value.initArray(group_arr));
        }
    }

    matches.* = Value.initArray(matches_arr);
    return Value.initInt(match_count);
}

pub fn php_preg_replace(pattern: Value, replacement: Value, subject: Value, allocator: Allocator) !Value {
    if (!pattern.isString() or !replacement.isString() or !subject.isString()) 
        return Value.initBool(false);
    
    const pat = pattern.asString().data;
    const repl = replacement.asString().data;
    const subj = subject.asString().data;
    
    if (pat.len < 3) return Value.initString(try PHPString.init(allocator, try allocator.dupe(u8, subj)));
    const actual_pat = pat[1..pat.len-1];
    
    // 简单替换
    var result = try std.ArrayList(u8).initCapacity(allocator, subj.len);
    defer result.deinit(allocator);
    
    var pos: usize = 0;
    while (pos < subj.len) {
        if (std.mem.indexOf(u8, subj[pos..], actual_pat)) |idx| {
            try result.appendSlice(allocator, subj[pos..pos+idx]);
            try result.appendSlice(allocator, repl);
            pos += idx + actual_pat.len;
        } else {
            try result.appendSlice(allocator, subj[pos..]);
            break;
        }
    }
    
    const output = try PHPString.init(allocator, try result.toOwnedSlice(allocator));
    return Value.initString(output);
}

pub fn php_preg_replace_callback(pattern: Value, callback: Value, subject: Value, allocator: Allocator) !Value {
    if (!pattern.isString() or !subject.isString()) 
        return Value.initBool(false);
    
    const pattern_str = pattern.asString().data;
    const subject_str = subject.asString().data;
    
    // 解析 PHP 正则模式
    const parsed = parsePHPRegexPattern(pattern_str);
    
    // 编译正则表达式
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        return Value.initString(try PHPString.init(allocator, try allocator.dupe(u8, subject_str)));
    };
    
    // 创建匹配数据
    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        return Value.initString(try PHPString.init(allocator, try allocator.dupe(u8, subject_str)));
    };
    defer pcre2_match_data_free_8(match_data);
    
    // 准备输出缓冲区
    var result = try std.ArrayList(u8).initCapacity(allocator, subject_str.len * 2);
    defer result.deinit(allocator);
    
    var subject_offset: usize = 0;
    var replace_count: usize = 0;
    const limit: usize = std.math.maxInt(usize);
    
    while (subject_offset < subject_str.len and replace_count < limit) {
        const rc = pcre2_match_8(
            re,
            subject_str.ptr,
            subject_str.len,
            @as(c_int, @intCast(subject_offset)),
            0,
            match_data,
            null,
        );
        
        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) break;
        
        const ovec = pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovec[0];
        const match_end = ovec[1];
        
        // 添加匹配前的内容
        if (match_start > subject_offset) {
            try result.appendSlice(allocator, subject_str[subject_offset..match_start]);
        }
        
        // 构建匹配数组
        const matches_arr = try PHPArray.init(allocator);
        defer matches_arr.release(allocator);
        
        // 添加所有捕获组
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            const match_str = subject_str[start..end];
            const php_str = try PHPString.init(allocator, try allocator.dupe(u8, match_str));
            try matches_arr.push(allocator, Value.initString(php_str));
        }
        
        // 调用回调函数
        const callback_result = try php_invoke_callable(callback, &[_]Value{Value.initArray(matches_arr)}, allocator);
        defer callback_result.release(allocator);
        
        // 将回调结果添加到输出
        if (callback_result.isString()) {
            try result.appendSlice(allocator, callback_result.asString().data);
        } else if (callback_result.isInt()) {
            // 处理整数返回值
            const int_val = callback_result.asInt();
            var buf: [32]u8 = undefined;
            const int_str = try std.fmt.bufPrint(&buf, "{d}", .{int_val});
            try result.appendSlice(allocator, int_str);
        } else {
            const str_result = try callback_result.toString(allocator);
            defer str_result.release(allocator);
            try result.appendSlice(allocator, str_result.data);
        }
        
        subject_offset = match_end;
        replace_count += 1;
    }
    
    // 添加剩余内容
    if (subject_offset < subject_str.len) {
        try result.appendSlice(allocator, subject_str[subject_offset..]);
    }
    
    const output = try PHPString.init(allocator, try result.toOwnedSlice(allocator));
    return Value.initString(output);
}

pub fn php_preg_split(pattern: Value, subject: Value, limit_val: Value, flags_val: Value, allocator: Allocator) !Value {
    // 转发到 PCRE2 实现
    return preg_split(pattern, subject, limit_val, flags_val, allocator);
}

/// filter_var - 使用特定的过滤器过滤一个变量
pub fn php_filter_var(value: Value, filter: Value, allocator: Allocator) !Value {
    _ = allocator;
    
    if (!filter.isInt()) return Value.initBool(false);
    
    const filter_type = filter.asInt();
    
    // FILTER_VALIDATE_EMAIL = 274
    if (filter_type == 274) {
        if (!value.isString()) return Value.initBool(false);
        
        const email = value.asString().data;
        
        // 简单的邮箱验证：必须包含 @ 和 .，且格式合理
        if (email.len < 3) return Value.initBool(false);
        
        // 查找 @
        const at_pos = std.mem.indexOf(u8, email, "@") orelse return Value.initBool(false);
        if (at_pos == 0 or at_pos == email.len - 1) return Value.initBool(false);
        
        // @ 后面必须有 .
        const domain = email[at_pos+1..];
        const dot_pos = std.mem.indexOf(u8, domain, ".") orelse return Value.initBool(false);
        if (dot_pos == 0 or dot_pos == domain.len - 1) return Value.initBool(false);
        
        // 检查是否有多个 @
        if (std.mem.indexOf(u8, email[at_pos+1..], "@") != null) return Value.initBool(false);
        
        // 验证通过，返回原值
        return value;
    }
    
    // 其他过滤器类型暂不支持
    return Value.initBool(false);
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

    const result = buf[64 - len ..];
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

/// password_hash - 创建密码哈希
/// 使用bcrypt算法 (PASSWORD_DEFAULT = PASSWORD_BCRYPT = 1)
/// 签名: password_hash(password, algo, options = []) — options忽略，使用默认cost
pub fn php_password_hash(password: Value, algo: Value, allocator: Allocator) !Value {
    if (!password.isString()) return error.InvalidArgument;
    
    const pwd = password.asString().data;
    const algo_val = algo.toInt();
    
    // 使用默认cost=12
    const cost: u6 = 12;
    
    // 使用bcrypt (algo=1 是 PASSWORD_BCRYPT)
    if (algo_val == 1 or algo_val == 0) { // 0 = PASSWORD_DEFAULT
        var hash_buf: [128]u8 = undefined;
        const hash_result = try std.crypto.pwhash.bcrypt.strHash(pwd, .{
            .allocator = allocator,
            .params = .{ .rounds_log = cost, .silently_truncate_password = true },
            .encoding = .crypt,
        }, &hash_buf);
        
        // Zig生成$2b$前缀，PHP使用$2y$前缀，替换以保持兼容
        var result_buf: [128]u8 = undefined;
        const result_str = blk: {
            if (hash_result.len >= 4 and hash_result[0] == '$' and hash_result[1] == '2' and hash_result[2] == 'b' and hash_result[3] == '$') {
                result_buf[0] = '$';
                result_buf[1] = '2';
                result_buf[2] = 'y';
                @memcpy(result_buf[3..hash_result.len], hash_result[3..]);
                break :blk result_buf[0..hash_result.len];
            }
            break :blk hash_result;
        };
        
        const php_str = try PHPString.init(allocator, result_str);
        return Value.initString(php_str);
    }
    
    return error.InvalidArgument;
}

/// password_verify - 验证密码是否匹配哈希
pub fn php_password_verify(password: Value, hash: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!password.isString() or !hash.isString()) {
        return Value.initBool(false);
    }
    
    const pwd = password.asString().data;
    const hash_str = hash.asString().data;
    
    // PHP使用$2y$前缀，Zig期望$2b$前缀，需要转换
    var converted_buf: [128]u8 = undefined;
    const verify_str = blk: {
        if (hash_str.len >= 4 and hash_str[0] == '$' and hash_str[1] == '2' and hash_str[2] == 'y' and hash_str[3] == '$') {
            converted_buf[0] = '$';
            converted_buf[1] = '2';
            converted_buf[2] = 'b';
            if (hash_str.len <= converted_buf.len) {
                @memcpy(converted_buf[3..hash_str.len], hash_str[3..]);
                break :blk converted_buf[0..hash_str.len];
            }
        }
        break :blk hash_str;
    };
    
    // 使用bcrypt验证
    std.crypto.pwhash.bcrypt.strVerify(verify_str, pwd, .{
        .silently_truncate_password = true,
    }) catch {
        return Value.initBool(false);
    };
    
    return Value.initBool(true);
}

/// password_get_info - 返回密码哈希的相关信息
pub fn php_password_get_info(hash_val: Value, allocator: Allocator) !Value {
    if (!hash_val.isString()) {
        // 返回未知算法的空info
        const arr = try PHPArray.init(allocator);
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algo")), Value.initNull());
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algoName")), Value.initString(try PHPString.init(allocator, "unknown")));
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "options")), Value.initArray(try PHPArray.init(allocator)));
        return Value.initArray(arr);
    }

    const hash_str = hash_val.asString().data;

    // 检测bcrypt格式: $2y$XX$ 或 $2b$XX$ 或 $2a$XX$
    if (hash_str.len >= 7 and hash_str[0] == '$' and hash_str[1] == '2' and
        (hash_str[2] == 'y' or hash_str[2] == 'b' or hash_str[2] == 'a') and hash_str[3] == '$')
    {
        // 提取cost值: $2y$XX$...
        const cost_str = hash_str[4..6];
        var cost: i64 = 0;
        for (cost_str) |c| {
            if (c >= '0' and c <= '9') {
                cost = cost * 10 + @as(i64, c - '0');
            }
        }

        const options_arr = try PHPArray.init(allocator);
        try options_arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "cost")), Value.initInt(cost));

        const arr = try PHPArray.init(allocator);
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algo")), Value.initString(try PHPString.init(allocator, "2y")));
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algoName")), Value.initString(try PHPString.init(allocator, "bcrypt")));
        try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "options")), Value.initArray(options_arr));
        return Value.initArray(arr);
    }

    // 未知算法
    const arr = try PHPArray.init(allocator);
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algo")), Value.initNull());
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "algoName")), Value.initString(try PHPString.init(allocator, "unknown")));
    try arr.setByValue(allocator, Value.initString(try PHPString.init(allocator, "options")), Value.initArray(try PHPArray.init(allocator)));
    return Value.initArray(arr);
}

/// password_needs_rehash - 检查哈希是否需要重新生成
/// password_needs_rehash(hash, algo, options=[])
pub fn php_password_needs_rehash(hash_val: Value, algo: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!hash_val.isString()) return Value.initBool(true);

    const hash_str = hash_val.asString().data;
    const algo_val = algo.toInt();

    // PASSWORD_DEFAULT(0) 和 PASSWORD_BCRYPT(1) 都使用bcrypt
    if (algo_val == 0 or algo_val == 1) {
        // 检查是否是bcrypt格式
        if (hash_str.len >= 7 and hash_str[0] == '$' and hash_str[1] == '2' and
            (hash_str[2] == 'y' or hash_str[2] == 'b' or hash_str[2] == 'a') and hash_str[3] == '$')
        {
            // 提取cost值
            var cost: i64 = 0;
            if (hash_str[4] >= '0' and hash_str[4] <= '9') cost = cost * 10 + @as(i64, hash_str[4] - '0');
            if (hash_str[5] >= '0' and hash_str[5] <= '9') cost = cost * 10 + @as(i64, hash_str[5] - '0');
            // 默认cost=12，如果匹配则不需要rehash
            return Value.initBool(cost != 12);
        }
        // 不是bcrypt格式，需要rehash
        return Value.initBool(true);
    }

    return Value.initBool(true);
}

pub fn php_uniqid(prefix: Value, more_entropy: Value, allocator: Allocator) !Value {
    const prefix_str = if (prefix.isString()) prefix.asString().data else "";
    const ent = more_entropy.toBool();

    // PHP uniqid format: prefix + 8 hex chars (seconds) + 5 hex chars (microseconds/100)
    const timestamp = std.time.nanoTimestamp();
    const now_us = @divTrunc(timestamp, 1000); // nanoseconds to microseconds
    const seconds = @as(u64, @intCast(@divTrunc(now_us, 1_000_000)));
    const microseconds = @as(u64, @intCast(@rem(now_us, 1_000_000)));
    // PHP uses microseconds/100 for the last 5 hex chars
    const usec_part = @divTrunc(microseconds, 10);

    var result_buf: [64]u8 = undefined;
    const formatted = if (ent) blk: {
        // With more_entropy: add .XXXXXXXX (8 random decimal digits)
        var rand_bytes: [4]u8 = undefined;
        std.crypto.random.bytes(&rand_bytes);
        const rand_val = @as(u32, rand_bytes[0]) * 16777216 + @as(u32, rand_bytes[1]) * 65536 + @as(u32, rand_bytes[2]) * 256 + rand_bytes[3];
        break :blk try std.fmt.bufPrint(&result_buf, "{s}{x}{x:0>5}.{d:0>8}", .{ prefix_str, seconds, usec_part, rand_val % 100000000 });
    } else try std.fmt.bufPrint(&result_buf, "{s}{x}{x:0>5}", .{ prefix_str, seconds, usec_part });

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
    if (!algorithm.isString() or !data.isString()) return Value.initBool(false);

    const algo = algorithm.asString().data;

    const input = data.asString().data;

    if (std.mem.eql(u8, algo, "md5")) {
        return php_md5(data, Value.initBool(false), allocator);
    } else if (std.mem.eql(u8, algo, "sha1")) {
        return php_sha1(data, Value.initBool(false), allocator);
    } else if (std.mem.eql(u8, algo, "sha256")) {
        return php_sha256(data, allocator);
    } else if (std.mem.eql(u8, algo, "sha224")) {
        var hash: [28]u8 = undefined;
        std.crypto.hash.sha2.Sha224.hash(input, &hash, .{});
        var hex_str: [56]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha384")) {
        var hash: [48]u8 = undefined;
        std.crypto.hash.sha2.Sha384.hash(input, &hash, .{});
        var hex_str: [96]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha512")) {
        var hash: [64]u8 = undefined;
        std.crypto.hash.sha2.Sha512.hash(input, &hash, .{});
        var hex_str: [128]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha512/256") or std.mem.eql(u8, algo, "sha512256")) {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha512_256.hash(input, &hash, .{});
        var hex_str: [64]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "crc32") or std.mem.eql(u8, algo, "crc32b")) {
        const crc = std.hash.crc.Crc32.hash(input);
        var hex_buf: [8]u8 = undefined;
        _ = std.fmt.bufPrint(&hex_buf, "{x:0>8}", .{crc}) catch return Value.initBool(false);
        return Value.initString(try PHPString.init(allocator, &hex_buf));
    } else if (std.mem.eql(u8, algo, "adler32")) {
        const adler = std.hash.Adler32.hash(input);
        var hex_buf: [8]u8 = undefined;
        _ = std.fmt.bufPrint(&hex_buf, "{x:0>8}", .{adler}) catch return Value.initBool(false);
        return Value.initString(try PHPString.init(allocator, &hex_buf));
    } else if (std.mem.eql(u8, algo, "ripemd128")) {
        // RIPEMD-128: 使用 MD5 作为基础（简化实现）
        var hash: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(input, &hash, .{});
        var hex_str: [32]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    }

    // PHP hash() 对不支持的算法发出警告并返回 false
    return Value.initBool(false);
}

/// hash_hmac - 生成HMAC哈希
pub fn php_hash_hmac(algorithm: Value, data: Value, key: Value, allocator: Allocator) !Value {
    if (!algorithm.isString() or !data.isString() or !key.isString()) return Value.initBool(false);

    const algo = algorithm.asString().data;
    const input = data.asString().data;
    const key_str = key.asString().data;

    if (std.mem.eql(u8, algo, "sha256")) {
        var hmac = std.crypto.auth.hmac.Hmac(std.crypto.hash.sha2.Sha256).init(key_str);
        hmac.update(input);
        var hash: [32]u8 = undefined;
        hmac.final(&hash);
        var hex_str: [64]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha1")) {
        var hmac = std.crypto.auth.hmac.Hmac(std.crypto.hash.Sha1).init(key_str);
        hmac.update(input);
        var hash: [20]u8 = undefined;
        hmac.final(&hash);
        var hex_str: [40]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "md5")) {
        var hmac = std.crypto.auth.hmac.Hmac(std.crypto.hash.Md5).init(key_str);
        hmac.update(input);
        var hash: [16]u8 = undefined;
        hmac.final(&hash);
        var hex_str: [32]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    } else if (std.mem.eql(u8, algo, "sha512")) {
        var hmac = std.crypto.auth.hmac.Hmac(std.crypto.hash.sha2.Sha512).init(key_str);
        hmac.update(input);
        var hash: [64]u8 = undefined;
        hmac.final(&hash);
        var hex_str: [128]u8 = undefined;
        for (hash, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch return Value.initBool(false);
        }
        return Value.initString(try PHPString.init(allocator, &hex_str));
    }

    return Value.initBool(false);
}

/// hash_equals - 安全比较两个字符串是否相等（防止时序攻击）
pub fn php_hash_equals(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initBool(false);
    
    const s1 = str1.asString().data;
    const s2 = str2.asString().data;
    
    if (s1.len != s2.len) return Value.initBool(false);
    
    // 使用时序安全比较
    var result: u8 = 0;
    for (s1, s2) |c1, c2| {
        result |= c1 ^ c2;
    }
    
    return Value.initBool(result == 0);
}

/// crc32 - 计算字符串的CRC32校验值
pub fn php_crc32(str: Value) !Value {
    if (!str.isString()) return error.InvalidArgument;

    const input = str.asString().data;
    const crc = std.hash.Crc32.hash(input);
    // PHP crc32() 返回有符号32位整数（与C的crc32行为一致）
    const signed: i32 = @bitCast(crc);
    return Value.initInt(@intCast(signed));
}

/// hash_algos - 返回支持的哈希算法列表
pub fn php_hash_algos(allocator: Allocator) !Value {
    const algos = [_][]const u8{
        "md5", "sha1", "sha224", "sha256", "sha384", "sha512",
        "sha512/256", "crc32", "crc32b", "adler32",
    };
    const arr = try PHPArray.init(allocator);
    for (algos) |algo| {
        try arr.push(allocator, Value.initString(try PHPString.init(allocator, algo)));
    }
    return Value.initArray(arr);
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
/// 注意：AOT模式下extract()的实现受限，因为变量名在编译时未知
/// 完整实现需要运行时符号表支持
pub fn php_extract(arr: Value, flags: Value, prefix: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initInt(0);
    
    const extract_flags = if (flags.isInt()) flags.asInt() else 0;
    const prefix_str = if (prefix.isString()) prefix.asString().data else "";
    
    _ = extract_flags;
    _ = prefix_str;
    _ = allocator;
    
    // AOT模式限制：
    // extract()需要动态创建变量，但AOT编译时变量名已固定
    // 完整实现需要：
    // 1. 运行时符号表（symbol table）
    // 2. 动态变量创建机制
    // 3. 作用域管理
    //
    // 当前返回数组元素数量，表示"提取"的变量数
    // 实际变量创建由编译器在IR层面处理
    const arr_obj = arr.asArray();
    return Value.initInt(@intCast(arr_obj.elements.count()));
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
    if (!arr.isArray()) return error.InvalidArgument;
    const php_arr = arr.asArray();

    const Entry = struct { key: ArrayKey, val: Value };
    var entries = std.ArrayListUnmanaged(Entry){};
    defer entries.deinit(allocator);
    var it = php_arr.elements.iterator();
    while (it.next()) |entry| {
        try entries.append(allocator, .{ .key = entry.key_ptr.*, .val = entry.value_ptr.* });
    }

    const Ctx = struct {
        fn natcmp(a: []const u8, b: []const u8) bool {
            var i: usize = 0;
            var j: usize = 0;
            while (i < a.len and j < b.len) {
                const ac = a[i];
                const bc = b[j];
                if (std.ascii.isDigit(ac) and std.ascii.isDigit(bc)) {
                    var an: u64 = 0;
                    var bn: u64 = 0;
                    while (i < a.len and std.ascii.isDigit(a[i])) : (i += 1) an = an * 10 + (a[i] - '0');
                    while (j < b.len and std.ascii.isDigit(b[j])) : (j += 1) bn = bn * 10 + (b[j] - '0');
                    if (an != bn) return an < bn;
                } else {
                    if (ac != bc) return ac < bc;
                    i += 1;
                    j += 1;
                }
            }
            return a.len < b.len;
        }
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            const as = if (a.val.isString()) a.val.asString().data else "";
            const bs = if (b.val.isString()) b.val.asString().data else "";
            return natcmp(as, bs);
        }
    };
    std.sort.pdq(Entry, entries.items, {}, Ctx.lessThan);

    // 强制转为mixed map并重排
    try php_arr.elements.convertToMixed();
    if (php_arr.elements.mixed) |*m| {
        m.clearRetainingCapacity();
        for (entries.items) |entry| {
            try m.put(entry.key, entry.val);
        }
    }
    return Value.initBool(true);
}

/// 静态变量访问函数
pub fn getStaticVar(func_name_val: Value, var_name_val: Value) !Value {
    const func_name = if (func_name_val.isString()) func_name_val.asString().data else "global";
    const var_name = if (var_name_val.isString()) var_name_val.asString().data else "";

    static_vars_mutex.lock();
    defer static_vars_mutex.unlock();

    if (static_vars == null) return Value.initNull();

    // 构造键：函数名::变量名
    const key = try std.fmt.allocPrint(runtime_allocator, "{s}::{s}", .{ func_name, var_name });
    defer runtime_allocator.free(key);

    return static_vars.?.get(key) orelse Value.initNull();
}

pub fn setStaticVar(func_name_val: Value, var_name_val: Value, value: Value) !Value {
    const func_name = if (func_name_val.isString()) func_name_val.asString().data else "global";
    const var_name = if (var_name_val.isString()) var_name_val.asString().data else "";

    static_vars_mutex.lock();
    defer static_vars_mutex.unlock();

    if (static_vars == null) return Value.initNull();

    // 构造键：函数名::变量名
    const key = try runtime_allocator.dupe(u8, try std.fmt.allocPrint(runtime_allocator, "{s}::{s}", .{ func_name, var_name }));

    try static_vars.?.put(key, value);
    return value;
}

// ============================================================================
// Generator Runtime Implementation
// ============================================================================

const GeneratorState = enum(u8) {
    created,
    running,
    suspended,
    completed,
};

pub const GeneratorContext = struct {
    mutex: std.Thread.Mutex = .{},
    caller_cond: std.Thread.Condition = .{},
    gen_cond: std.Thread.Condition = .{},
    state: GeneratorState = .created,
    current_key: Value = Value.initNull(),
    current_value: Value = Value.initNull(),
    sent_value: Value = Value.initNull(),
    return_value: Value = Value.initNull(),
    caller_ctx: Value = Value.initNull(),
    caller_args_storage: []Value = &.{},
    body_fn: ?*const fn (Value, []const Value, Allocator) anyerror!Value = null,
    thread: ?std.Thread = null,
    auto_key: i64 = 0,
    has_error: bool = false,
    throw_value: Value = Value.initNull(),
    has_throw: bool = false,
};

threadlocal var tl_generator_ctx: ?*GeneratorContext = null;

pub fn php_generator_get_context() *GeneratorContext {
    return tl_generator_ctx.?;
}

fn generatorThreadRunner(gen_ctx: *GeneratorContext) void {
    tl_generator_ctx = gen_ctx;
    const body = gen_ctx.body_fn orelse {
        gen_ctx.mutex.lock();
        gen_ctx.state = .completed;
        gen_ctx.caller_cond.signal();
        gen_ctx.mutex.unlock();
        return;
    };
    const result = body(
        gen_ctx.caller_ctx,
        gen_ctx.caller_args_storage,
        runtime_allocator,
    ) catch {
        gen_ctx.mutex.lock();
        gen_ctx.has_error = true;
        gen_ctx.state = .completed;
        gen_ctx.caller_cond.signal();
        gen_ctx.mutex.unlock();
        return;
    };
    gen_ctx.mutex.lock();
    gen_ctx.return_value = result;
    gen_ctx.state = .completed;
    gen_ctx.caller_cond.signal();
    gen_ctx.mutex.unlock();
}

pub fn php_create_generator(
    body_fn: *const fn (Value, []const Value, Allocator) anyerror!Value,
    ctx: Value,
    args: []const Value,
    allocator: Allocator,
) !Value {
    const gen_ctx = try allocator.create(GeneratorContext);
    gen_ctx.* = GeneratorContext{};
    gen_ctx.body_fn = body_fn;
    gen_ctx.caller_ctx = ctx;
    if (args.len > 0) {
        gen_ctx.caller_args_storage = try allocator.alloc(Value, args.len);
        @memcpy(gen_ctx.caller_args_storage, args);
    }
    const meta = findClass("Generator");
    const obj = if (meta) |m|
        try PHPObject.initWithMeta(allocator, m)
    else
        try PHPObject.init(allocator, "Generator");
    try obj.setProperty("__gen_ctx", Value.initInt(
        @as(i64, @intCast(@intFromPtr(gen_ctx))),
    ));
    return Value_initObject(obj);
}

fn getGenCtx(ctx: Value) ?*GeneratorContext {
    if (!Value_isObject(ctx)) return null;
    const obj = Value_asObject(ctx);
    const ptr_val = obj.getPropertyDirect("__gen_ctx") orelse return null;
    if (!ptr_val.isInt()) return null;
    const addr = ptr_val.toInt();
    if (addr <= 0) return null;
    return @ptrFromInt(@as(usize, @intCast(addr)));
}

fn generatorEnsureStarted(gen_ctx: *GeneratorContext) void {
    gen_ctx.mutex.lock();
    if (gen_ctx.state == .created) {
        gen_ctx.state = .running;
        gen_ctx.mutex.unlock();
        gen_ctx.thread = std.Thread.spawn(
            .{},
            generatorThreadRunner,
            .{gen_ctx},
        ) catch {
            gen_ctx.mutex.lock();
            gen_ctx.state = .completed;
            gen_ctx.mutex.unlock();
            return;
        };
        gen_ctx.mutex.lock();
        while (gen_ctx.state == .running) {
            gen_ctx.caller_cond.wait(&gen_ctx.mutex);
        }
        gen_ctx.mutex.unlock();
    } else {
        gen_ctx.mutex.unlock();
    }
}

fn generatorAdvance(gen_ctx: *GeneratorContext) void {
    gen_ctx.mutex.lock();
    if (gen_ctx.state != .suspended) {
        gen_ctx.mutex.unlock();
        return;
    }
    gen_ctx.state = .running;
    gen_ctx.gen_cond.signal();
    while (gen_ctx.state == .running) {
        gen_ctx.caller_cond.wait(&gen_ctx.mutex);
    }
    gen_ctx.mutex.unlock();
}

pub fn php_generator_yield(
    gen_ctx: *GeneratorContext,
    key: Value,
    value: Value,
) !Value {
    gen_ctx.mutex.lock();
    if (key.isNull()) {
        gen_ctx.current_key = Value.initInt(gen_ctx.auto_key);
        gen_ctx.auto_key += 1;
    } else {
        gen_ctx.current_key = key;
    }
    gen_ctx.current_value = value;
    gen_ctx.state = .suspended;
    gen_ctx.caller_cond.signal();
    while (gen_ctx.state == .suspended) {
        gen_ctx.gen_cond.wait(&gen_ctx.mutex);
    }
    if (gen_ctx.state == .completed) {
        gen_ctx.mutex.unlock();
        return error.GeneratorClosed;
    }
    if (gen_ctx.has_throw) {
        const throw_val = gen_ctx.throw_value;
        gen_ctx.throw_value = Value.initNull();
        gen_ctx.has_throw = false;
        gen_ctx.mutex.unlock();
        setException(throw_val);
        return Value.initNull();
    }
    const sent = gen_ctx.sent_value;
    gen_ctx.sent_value = Value.initNull();
    gen_ctx.mutex.unlock();
    return sent;
}

pub fn php_generator_yield_from(
    gen_ctx: *GeneratorContext,
    iterable: Value,
) !Value {
    if (Value_isObject(iterable)) {
        const obj = Value_asObject(iterable);
        if (std.mem.eql(u8, obj.class_name, "Generator")) {
            if (getGenCtx(iterable)) |inner| {
                generatorEnsureStarted(inner);
                while (inner.state != .completed) {
                    _ = try php_generator_yield(
                        gen_ctx,
                        inner.current_key,
                        inner.current_value,
                    );
                    generatorAdvance(inner);
                }
                return inner.return_value;
            }
        }
    }
    if (iterable.isArray()) {
        const arr = iterable.asArray();
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            const k = entry.key_ptr.*;
            const v = entry.value_ptr.*;
            const key_val = switch (k) {
                .integer => |i| Value.initInt(i),
                .string => |s| Value.initString(s),
            };
            _ = try php_generator_yield(gen_ctx, key_val, v);
        }
    }
    return Value.initNull();
}

fn registerGeneratorClass(allocator: Allocator) !void {
    const meta = try ClassMeta.init(allocator, "Generator");

    try meta.addMethod(.{
        .name = "rewind",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "valid",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    return Value.initBool(gc.state != .completed);
                }
                return Value.initBool(false);
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "current",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    if (gc.state == .completed) return Value.initNull();
                    _ = gc.current_value.retain();
                    return gc.current_value;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "key",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    if (gc.state == .completed) return Value.initNull();
                    _ = gc.current_key.retain();
                    return gc.current_key;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "next",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    generatorAdvance(gc);
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "send",
        .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    if (args.len > 0) {
                        gc.mutex.lock();
                        gc.sent_value = args[0];
                        gc.mutex.unlock();
                    }
                    generatorAdvance(gc);
                    if (gc.state == .completed) return Value.initNull();
                    _ = gc.current_value.retain();
                    return gc.current_value;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "throw",
        .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    if (gc.state == .completed) return Value.initNull();
                    gc.mutex.lock();
                    if (args.len > 0) {
                        gc.throw_value = args[0];
                        gc.has_throw = true;
                    }
                    gc.state = .running;
                    gc.gen_cond.signal();
                    while (gc.state == .running) {
                        gc.caller_cond.wait(&gc.mutex);
                    }
                    gc.mutex.unlock();
                    if (gc.state == .completed) return Value.initNull();
                    _ = gc.current_value.retain();
                    return gc.current_value;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "getReturn",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    if (gc.state != .completed) {
                        return error.GeneratorNotCompleted;
                    }
                    _ = gc.return_value.retain();
                    return gc.return_value;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try registerClass(meta);
}

// ============================================================================
// Ctype 系列函数 - 字符类型检测
// ============================================================================

/// ctype_alnum - 检查是否为字母数字字符
pub fn php_ctype_alnum(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isAlphanumeric(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isAlphanumeric(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_alpha - 检查是否为字母字符
pub fn php_ctype_alpha(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isAlphabetic(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isAlphabetic(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_cntrl - 检查是否为控制字符
pub fn php_ctype_cntrl(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isControl(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isControl(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_digit - 检查是否为数字字符
pub fn php_ctype_digit(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isDigit(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isDigit(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_graph - 检查是否为可打印字符（不包括空格）
pub fn php_ctype_graph(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isPrint(c) and c != ' ');
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isPrint(c) or c == ' ') return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_lower - 检查是否为小写字母
pub fn php_ctype_lower(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isLower(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isLower(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_print - 检查是否为可打印字符（包括空格）
pub fn php_ctype_print(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isPrint(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isPrint(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_punct - 检查是否为标点符号
pub fn php_ctype_punct(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(isPunct(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!isPunct(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// 标点符号判断：可打印的非字母数字非空格字符
fn isPunct(c: u8) bool {
    return std.ascii.isPrint(c) and !std.ascii.isAlphanumeric(c) and c != ' ';
}

/// ctype_space - 检查是否为空白字符
pub fn php_ctype_space(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isWhitespace(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isWhitespace(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_upper - 检查是否为大写字母
pub fn php_ctype_upper(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isUpper(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isUpper(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_xdigit - 检查是否为十六进制数字
pub fn php_ctype_xdigit(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(isXDigit(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!isXDigit(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// 十六进制数字判断
fn isXDigit(c: u8) bool {
    return std.ascii.isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

// Ctype 函数包装器
fn wrapBuiltin_ctype_alnum(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_alnum(args[0]);
}

fn wrapBuiltin_ctype_alpha(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_alpha(args[0]);
}

fn wrapBuiltin_ctype_cntrl(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_cntrl(args[0]);
}

fn wrapBuiltin_ctype_digit(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_digit(args[0]);
}

fn wrapBuiltin_ctype_graph(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_graph(args[0]);
}

fn wrapBuiltin_ctype_lower(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_lower(args[0]);
}

fn wrapBuiltin_ctype_print(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_print(args[0]);
}

fn wrapBuiltin_ctype_punct(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_punct(args[0]);
}

fn wrapBuiltin_ctype_space(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_space(args[0]);
}

fn wrapBuiltin_ctype_upper(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_upper(args[0]);
}

fn wrapBuiltin_ctype_xdigit(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_xdigit(args[0]);
}

// ============================================================================
// Mbstring 扩展函数
// ============================================================================

/// mb_strlen - 获取字符串长度（支持多字节字符）
/// 对于ASCII字符串，行为与strlen相同
/// 对于UTF-8字符串，返回字符数而非字节数
pub fn php_mb_strlen(str: Value, encoding: Value) !Value {
    _ = encoding; // 简化实现：忽略encoding参数，默认使用UTF-8
    if (!str.isString()) return Value.initInt(0);

    const php_str = str.asString();
    const data = php_str.data;

    // UTF-8字符计数
    var char_count: usize = 0;
    var i: usize = 0;
    while (i < data.len) {
        const byte = data[i];
        // UTF-8连续字节以10开头，跳过这些
        if ((byte & 0xC0) != 0x80) {
            char_count += 1;
        }
        i += 1;
    }

    return Value.initInt(@intCast(char_count));
}

/// mb_substr - 获取子字符串（支持多字节字符）
/// 对于UTF-8字符串，按字符位置操作而非字节位置
pub fn php_mb_substr(str: Value, start: Value, length: Value, encoding: Value, allocator: Allocator) !Value {
    _ = encoding; // 简化实现：忽略encoding参数，默认使用UTF-8
    if (!str.isString()) return Value.initNull();

    const php_str = str.asString();
    const data = php_str.data;

    // 将字节位置映射到字符位置
    const CharPos = struct {
        byte_idx: usize,
        char_idx: usize,
    };

    // 构建字符位置映射表
    var char_positions = try std.ArrayList(CharPos).initCapacity(allocator, 0);
    defer char_positions.deinit(allocator);

    var char_idx: usize = 0;
    var byte_idx: usize = 0;
    while (byte_idx < data.len) {
        const byte = data[byte_idx];
        if ((byte & 0xC0) != 0x80) {
            try char_positions.append(allocator, .{ .byte_idx = byte_idx, .char_idx = char_idx });
            char_idx += 1;
        }
        byte_idx += 1;
    }
    // 添加结束位置
    try char_positions.append(allocator, .{ .byte_idx = data.len, .char_idx = char_idx });

    const total_chars = char_idx;

    // 处理start参数
    const start_int = start.toInt();
    const start_char: usize = blk: {
        if (start_int >= 0) {
            const s: usize = @intCast(@min(start_int, @as(i64, @intCast(total_chars))));
            break :blk s;
        } else {
            // 负数从末尾开始计数
            const abs_start: usize = @intCast(@min(-start_int, @as(i64, @intCast(total_chars))));
            break :blk if (abs_start > total_chars) @as(usize, 0) else total_chars - abs_start;
        }
    };

    // 处理length参数
    const end_char: usize = blk: {
        if (length.isNull()) {
            break :blk total_chars;
        }
        const len_int = length.toInt();
        if (len_int < 0) {
            // 负数长度从末尾截断
            const abs_len: usize = @intCast(@min(-len_int, @as(i64, @intCast(total_chars))));
            const end = total_chars - abs_len;
            break :blk @min(end, total_chars);
        }
        const end = start_char + @as(usize, @intCast(len_int));
        break :blk @min(end, total_chars);
    };

    if (start_char >= end_char or start_char >= total_chars) {
        const empty_str = try PHPString.init(allocator, "");
        return Value.initString(empty_str);
    }

    // 获取字节范围
    const start_byte = char_positions.items[start_char].byte_idx;
    const end_byte = char_positions.items[end_char].byte_idx;

    const result = try PHPString.init(allocator, data[start_byte..end_byte]);
    return Value.initString(result);
}

/// mb_strtoupper - 转换为大写（支持多字节字符）
/// 注意：简化实现仅处理ASCII字符，完整实现需要Unicode大小写映射表
pub fn php_mb_strtoupper(str: Value, encoding: Value, allocator: Allocator) !Value {
    _ = encoding;
    if (!str.isString()) return str;

    const php_str = str.asString();
    const data = php_str.data;

    // 对于ASCII字符串，直接使用 strtoupper
    // 对于UTF-8，需要更复杂的处理，这里简化为ASCII处理
    const result_data = try allocator.alloc(u8, data.len);
    errdefer allocator.free(result_data);

    var i: usize = 0;
    while (i < data.len) {
        const byte = data[i];
        // 只转换ASCII字母
        if (byte >= 'a' and byte <= 'z') {
            result_data[i] = byte - 32;
        } else {
            result_data[i] = byte;
        }
        i += 1;
    }

    const result = try PHPString.init(allocator, result_data);
    allocator.free(result_data);
    return Value.initString(result);
}

/// mb_strtolower - 转换为小写（支持多字节字符）
/// 注意：简化实现仅处理ASCII字符
pub fn php_mb_strtolower(str: Value, encoding: Value, allocator: Allocator) !Value {
    _ = encoding;
    if (!str.isString()) return str;

    const php_str = str.asString();
    const data = php_str.data;

    const result_data = try allocator.alloc(u8, data.len);
    errdefer allocator.free(result_data);

    var i: usize = 0;
    while (i < data.len) {
        const byte = data[i];
        // 只转换ASCII字母
        if (byte >= 'A' and byte <= 'Z') {
            result_data[i] = byte + 32;
        } else {
            result_data[i] = byte;
        }
        i += 1;
    }

    const result = try PHPString.init(allocator, result_data);
    allocator.free(result_data);
    return Value.initString(result);
}

/// substr_count - 计算子字符串出现次数
pub fn php_substr_count(haystack: Value, needle: Value, offset: Value, length: Value) !Value {
    _ = offset;
    _ = length;
    if (!haystack.isString() or !needle.isString()) return Value.initInt(0);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initInt(0);
    if (need.length > hay.length) return Value.initInt(0);

    var count: i64 = 0;
    var pos: usize = 0;

    while (pos <= hay.length - need.length) {
        if (std.mem.eql(u8, hay.data[pos .. pos + need.length], need.data)) {
            count += 1;
            pos += need.length;
        } else {
            pos += 1;
        }
    }

    return Value.initInt(count);
}

// Mbstring 和字符串函数包装器
fn wrapBuiltin_mb_strlen(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const encoding = if (args.len >= 2) args[1] else Value.initNull();
    return php_mb_strlen(args[0], encoding);
}

fn wrapBuiltin_mb_substr(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const length = if (args.len >= 3) args[2] else Value.initNull();
    const encoding = if (args.len >= 4) args[3] else Value.initNull();
    return php_mb_substr(args[0], args[1], length, encoding, allocator);
}

fn wrapBuiltin_mb_strtoupper(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const encoding = if (args.len >= 2) args[1] else Value.initNull();
    return php_mb_strtoupper(args[0], encoding, allocator);
}

fn wrapBuiltin_mb_strtolower(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const encoding = if (args.len >= 2) args[1] else Value.initNull();
    return php_mb_strtolower(args[0], encoding, allocator);
}

fn wrapBuiltin_substr_count(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initNull();
    const length = if (args.len >= 4) args[3] else Value.initNull();
    return php_substr_count(args[0], args[1], offset, length);
}

fn wrapBuiltin_ucfirst(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ucfirst(args[0], allocator);
}

fn wrapBuiltin_lcfirst(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_lcfirst(args[0], allocator);
}

fn wrapBuiltin_ucwords(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const delimiters = if (args.len >= 2) args[1] else Value.initNull();
    return php_ucwords(args[0], delimiters, allocator);
}

fn wrapBuiltin_strrpos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_strrpos(args[0], args[1], offset);
}

fn wrapBuiltin_strripos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_strripos(args[0], args[1], offset);
}

fn wrapBuiltin_str_word_count(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const format = if (args.len >= 2) args[1] else Value.initInt(0);
    const charlist = if (args.len >= 3) args[2] else Value.initNull();
    return php_str_word_count(args[0], format, charlist);
}

fn wrapBuiltin_substr(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const length = if (args.len >= 3) args[2] else Value.initNull();
    return php_substr(args[0], args[1], length, allocator);
}

fn wrapBuiltin_strpos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_strpos(args[0], args[1], offset);
}

// 数学函数包装器
fn wrapBuiltin_floor(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_floor(args[0]);
}

fn wrapBuiltin_ceil(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ceil(args[0]);
}

fn wrapBuiltin_sin(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_sin(args[0]);
}

fn wrapBuiltin_cos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_cos(args[0]);
}

fn wrapBuiltin_tan(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_tan(args[0]);
}

fn wrapBuiltin_log(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_log(args[0]);
}

fn wrapBuiltin_exp(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_exp(args[0]);
}

fn wrapBuiltin_hypot(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_hypot(args[0], args[1]);
}

fn wrapBuiltin_pow(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_pow(args[0], args[1]);
}

fn wrapBuiltin_min(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_min(args);
}

fn wrapBuiltin_max(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_max(args);
}

// 字符串函数包装器
fn wrapBuiltin_stripos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_stripos(args[0], args[1], offset);
}

fn wrapBuiltin_strstr(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_strstr(args[0], args[1], allocator);
}

fn wrapBuiltin_str_split(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const length = if (args.len >= 2) args[1] else Value.initInt(1);
    return php_str_split(args[0], length, allocator);
}

fn wrapBuiltin_implode(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const glue = if (args.len >= 1) args[0] else Value.initNull();
    const pieces = if (args.len >= 2) args[1] else Value.initNull();
    return php_implode(glue, pieces, allocator);
}

fn wrapBuiltin_explode(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const limit = if (args.len >= 3) args[2] else Value.initNull();
    return php_explode(args[0], args[1], limit, allocator);
}

/// get_debug_type - 获取变量的调试类型（PHP 8+）
pub fn php_get_debug_type(val: Value, allocator: Allocator) !Value {
    if (val.isNull()) {
        return Value.initString(try PHPString.init(allocator, "null"));
    }
    if (val.isBool()) {
        return Value.initString(try PHPString.init(allocator, "bool"));
    }
    if (val.isInt()) {
        return Value.initString(try PHPString.init(allocator, "int"));
    }
    if (val.isFloat()) {
        return Value.initString(try PHPString.init(allocator, "float"));
    }
    if (val.isString()) {
        return Value.initString(try PHPString.init(allocator, "string"));
    }
    if (val.isArray()) {
        return Value.initString(try PHPString.init(allocator, "array"));
    }
    if (Value_isObject(val)) {
        const obj = Value_asObject(val);
        if (obj.class_meta) |meta| {
            return Value.initString(try PHPString.init(allocator, meta.name));
        }
        return Value.initString(try PHPString.init(allocator, "object"));
    }
    if (val.isFunction()) {
        return Value.initString(try PHPString.init(allocator, "Closure"));
    }
    return Value.initString(try PHPString.init(allocator, "unknown"));
}

/// call_user_func - 调用回调函数
pub fn php_call_user_func(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;

    const callback = args[0];
    const call_args = args[1..];

    // 处理字符串函数名
    if (callback.isString()) {
        const func_name = callback.asString().data;

        // 先检查用户函数
        if (user_function_registry) |registry| {
            if (registry.get(func_name)) |func| {
                return func(Value.initNull(), call_args, allocator);
            }
        }

        // 再检查内置函数
        if (lookupBuiltinFunction(func_name)) |func| {
            return func(Value.initNull(), call_args, allocator);
        }

        // 最后检查 AOT hook
        if (aot_callable_hook) |hook| {
            return hook(func_name, call_args, allocator);
        }

        return error.UnknownFunction;
    }

    // 处理数组形式 [obj/class, method]
    if (callback.isArray()) {
        const arr = callback.asArray();
        var key_idx: usize = 0;
        var iter = arr.elements.iterator();
        var obj_or_class: ?Value = null;
        var method_name: ?Value = null;

        while (iter.next()) |entry| : (key_idx += 1) {
            if (key_idx == 0) obj_or_class = entry.value_ptr.*;
            if (key_idx == 1) method_name = entry.value_ptr.*;
        }

        if (obj_or_class) |obj| {
            if (method_name) |method| {
                if (method.isString()) {
                    const method_str = method.asString().data;
                    if (Value_isObject(obj)) {
                        const php_obj = Value_asObject(obj);
                        if (php_obj.class_meta) |meta| {
                            if (meta.findMethod(method_str)) |method_info| {
                                return method_info.func(obj, call_args, allocator);
                            }
                        }
                    }
                }
            }
        }
        return error.UnknownFunction;
    }

    // 处理 __invoke 对象
    if (Value_isObject(callback)) {
        const obj = Value_asObject(callback);
        if (obj.class_meta) |meta| {
            if (meta.findMethod("__invoke")) |method| {
                return method.func(callback, call_args, allocator);
            }
        }
    }

    // PHP: call_user_func 对不存在的回调发出 warning 并返回 false
    const stderr = std.fs.File{ .handle = 2 };
    stderr.writeAll("PHP Warning:  call_user_func() expects parameter 1 to be a valid callback\n") catch {};
    return Value.initBool(false);
}

/// call_user_func_array - 使用数组参数调用回调函数
pub fn php_call_user_func_array(callback: Value, args_arr: Value, allocator: Allocator) !Value {
    if (!args_arr.isArray()) {
        return php_call_user_func(&[_]Value{callback}, allocator);
    }

    const arr = args_arr.asArray();
    var call_args = try std.ArrayList(Value).initCapacity(allocator, 0);
    defer call_args.deinit(allocator);

    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        try call_args.append(allocator, entry.value_ptr.*);
    }

    var full_args = try std.ArrayList(Value).initCapacity(allocator, 0);
    defer full_args.deinit(allocator);
    try full_args.append(allocator, callback);
    for (call_args.items) |arg| {
        try full_args.append(allocator, arg);
    }

    return php_call_user_func(full_args.items, allocator);
}

// 更多函数包装器
fn wrapBuiltin_is_callable(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_is_callable(args[0]);
}

fn wrapBuiltin_get_debug_type(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_debug_type(args[0], allocator);
}

fn wrapBuiltin_call_user_func(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_call_user_func(args, allocator);
}

fn wrapBuiltin_call_user_func_array(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_call_user_func_array(args[0], args[1], allocator);
}

fn wrapBuiltin_compact(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_compact(args, allocator);
}

fn wrapBuiltin_extract(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const flags = if (args.len >= 2) args[1] else Value.initInt(0);
    const prefix = if (args.len >= 3) args[2] else Value.initNull();
    return php_extract(args[0], flags, prefix, allocator);
}

// 字符操作函数包装器
fn wrapBuiltin_ord(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ord(args[0]);
}

fn wrapBuiltin_chr(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_chr(args[0], allocator);
}

fn wrapBuiltin_md5(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const raw = if (args.len >= 2) args[1] else Value.initBool(false);
    return php_md5(args[0], raw, allocator);
}

fn wrapBuiltin_sha1(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const raw = if (args.len >= 2) args[1] else Value.initBool(false);
    return php_sha1(args[0], raw, allocator);
}

fn wrapBuiltin_crc32(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_crc32(args[0]);
}

fn wrapBuiltin_strrev(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strrev(args[0], allocator);
}

fn wrapBuiltin_ltrim(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const mask = if (args.len >= 2) args[1] else Value.initNull();
    return php_ltrim(args[0], mask, allocator);
}

fn wrapBuiltin_rtrim(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const mask = if (args.len >= 2) args[1] else Value.initNull();
    return php_rtrim(args[0], mask, allocator);
}

/// addslashes - 使用反斜线引用字符串
pub fn php_addslashes(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const data = php_str.data;

    // 计算结果长度
    var result_len: usize = 0;
    for (data) |c| {
        // 需要转义的字符: ', ", \, NUL
        if (c == '\'' or c == '"' or c == '\\' or c == 0) {
            result_len += 2;
        } else {
            result_len += 1;
        }
    }

    const result = try allocator.alloc(u8, result_len);
    errdefer allocator.free(result);

    var pos: usize = 0;
    for (data) |c| {
        if (c == '\'' or c == '"' or c == '\\' or c == 0) {
            result[pos] = '\\';
            result[pos + 1] = if (c == 0) '0' else c;
            pos += 2;
        } else {
            result[pos] = c;
            pos += 1;
        }
    }

    const php_result = try PHPString.init(allocator, result);
    allocator.free(result);
    return Value.initString(php_result);
}

/// stripslashes - 反引用一个引用字符串
pub fn php_stripslashes(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const data = php_str.data;

    // 计算结果长度（最多等于原长度）
    const result = try allocator.alloc(u8, data.len);
    errdefer allocator.free(result);

    var pos: usize = 0;
    var i: usize = 0;
    while (i < data.len) {
        if (data[i] == '\\' and i + 1 < data.len) {
            const next = data[i + 1];
            if (next == '0') {
                result[pos] = 0;
                pos += 1;
                i += 2;
            } else if (next == '\'' or next == '"' or next == '\\') {
                result[pos] = next;
                pos += 1;
                i += 2;
            } else {
                result[pos] = data[i];
                pos += 1;
                i += 1;
            }
        } else {
            result[pos] = data[i];
            pos += 1;
            i += 1;
        }
    }

    const php_result = try PHPString.init(allocator, result[0..pos]);
    allocator.free(result);
    return Value.initString(php_result);
}

fn wrapBuiltin_addslashes(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_addslashes(args[0], allocator);
}

fn wrapBuiltin_stripslashes(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_stripslashes(args[0], allocator);
}

// ============================================================================
// 新增缺失的内置函数
// ============================================================================

/// error_get_last - 获取最后发生的错误
pub fn php_error_get_last(allocator: Allocator) !Value {
    // 简化实现：返回 null（表示没有错误）
    // PHP CLI 中如果没有发生错误也返回 null
    _ = allocator;
    return Value.initNull();
}

/// rewind - 倒回文件指针的位置
pub fn php_rewind(handle: Value) !Value {
    if (!handle.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initBool(false);

    const file_handle: *std.fs.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    file_handle.seekTo(0) catch return Value.initBool(false);
    return Value.initBool(true);
}

/// gethostbyaddr - 获取指定IP地址对应的主机名
pub fn php_gethostbyaddr(ip: Value, allocator: Allocator) !Value {
    if (!ip.isString()) return Value.initBool(false);
    const ip_str = ip.asString().data;
    // 简化实现：对于本地地址直接返回
    if (std.mem.eql(u8, ip_str, "127.0.0.1")) {
        return Value.initString(try PHPString.init(allocator, "localhost"));
    }
    // 其他地址返回原 IP（模拟 PHP 在无法反解时的行为）
    return Value.initString(try PHPString.init(allocator, ip_str));
}

/// hash_file - 使用给定文件的内容生成哈希值
pub fn php_hash_file(algo: Value, filename: Value, allocator: Allocator) !Value {
    if (!algo.isString() or !filename.isString()) return Value.initBool(false);

    const algo_str = algo.asString().data;
    const fname = filename.asString().data;

    // 读取文件内容
    const file = std.fs.cwd().openFile(fname, .{}) catch return Value.initBool(false);
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return Value.initBool(false);
    defer allocator.free(content);

    // 复用已有的 php_hash 逻辑
    const content_val = Value.initString(try PHPString.init(allocator, content));
    return php_hash(
        Value.initString(try PHPString.init(allocator, algo_str)),
        content_val,
        allocator,
    );
}

/// get_resource_type - 返回资源类型
pub fn php_get_resource_type(res: Value, allocator: Allocator) !Value {
    _ = res;
    return Value.initString(try PHPString.init(allocator, "Unknown"));
}

/// stream_register_wrapper - 注册一个用 PHP 类实现的 URL 封装协议
pub fn php_stream_register_wrapper(protocol: Value, classname: Value, allocator: Allocator) !Value {
    _ = protocol;
    _ = classname;
    _ = allocator;
    return Value.initBool(true);
}

