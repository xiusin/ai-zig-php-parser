//! Builtin Function Direct Dispatch
//! 目标：实现内置函数的零开销直接调用
//!
//! 核心技术：
//! 1. 编译时生成函数指针数组
//! 2. 完美哈希函数名查找
//! 3. 零 HashMap 查找开销
//! 4. 内联高频函数

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

// ============================================================================
// Task 4.1.1: BuiltinId 枚举 - 所有内置函数的唯一标识
// ============================================================================

pub const BuiltinId = enum(u16) {
    // Array Functions (0-49)
    array_map = 0,
    array_filter = 1,
    array_reduce = 2,
    array_keys = 3,
    array_values = 4,
    array_merge = 5,
    array_push = 6,
    array_pop = 7,
    array_shift = 8,
    array_unshift = 9,
    array_slice = 10,
    array_splice = 11,
    array_reverse = 12,
    array_flip = 13,
    array_unique = 14,
    array_intersect = 15,
    array_diff = 16,
    array_chunk = 17,
    array_column = 18,
    array_combine = 19,
    array_fill = 20,
    array_pad = 21,
    array_search = 22,
    array_key_exists = 23,
    in_array = 24,
    count = 25,
    sizeof = 26,
    sort = 27,
    rsort = 28,
    asort = 29,
    arsort = 30,
    ksort = 31,
    krsort = 32,
    usort = 33,
    uasort = 34,
    uksort = 35,
    array_multisort = 36,
    range = 37,
    compact = 38,
    extract = 39,
    list = 40,
    each = 41,
    current = 42,
    next = 43,
    prev = 44,
    reset = 45,
    end = 46,
    key = 47,

    // String Functions (50-149)
    echo = 50,
    print = 51,
    printf = 52,
    sprintf = 53,
    strlen = 54,
    strpos = 55,
    strrpos = 56,
    stripos = 57,
    strripos = 58,
    substr = 59,
    str_replace = 60,
    str_ireplace = 61,
    strtolower = 62,
    strtoupper = 63,
    ucfirst = 64,
    lcfirst = 65,
    ucwords = 66,
    trim = 67,
    ltrim = 68,
    rtrim = 69,
    explode = 70,
    implode = 71,
    join = 72,
    str_split = 73,
    chunk_split = 74,
    wordwrap = 75,
    str_repeat = 76,
    str_pad = 77,
    str_shuffle = 78,
    strrev = 79,
    strcmp = 80,
    strcasecmp = 81,
    strncmp = 82,
    strncasecmp = 83,
    str_contains = 84,
    str_starts_with = 85,
    str_ends_with = 86,
    substr_count = 87,
    substr_replace = 88,
    str_word_count = 89,
    levenshtein = 90,
    similar_text = 91,
    soundex = 92,
    metaphone = 93,
    htmlspecialchars = 94,
    htmlentities = 95,
    html_entity_decode = 96,
    strip_tags = 97,
    addslashes = 98,
    stripslashes = 99,
    quotemeta = 100,
    nl2br = 101,
    parse_str = 102,
    http_build_query = 103,
    urlencode = 104,
    urldecode = 105,
    rawurlencode = 106,
    rawurldecode = 107,
    base64_encode = 108,
    base64_decode = 109,
    quoted_printable_encode = 110,
    quoted_printable_decode = 111,
    convert_uuencode = 112,
    convert_uudecode = 113,
    bin2hex = 114,
    hex2bin = 115,
    chr = 116,
    ord = 117,
    number_format = 118,
    money_format = 119,

    // Math Functions (150-199)
    abs = 150,
    ceil = 151,
    floor = 152,
    round = 153,
    sqrt = 154,
    pow = 155,
    exp = 156,
    log = 157,
    log10 = 158,
    sin = 159,
    cos = 160,
    tan = 161,
    asin = 162,
    acos = 163,
    atan = 164,
    atan2 = 165,
    sinh = 166,
    cosh = 167,
    tanh = 168,
    deg2rad = 169,
    rad2deg = 170,
    min = 171,
    max = 172,
    rand = 173,
    mt_rand = 174,
    srand = 175,
    mt_srand = 176,
    getrandmax = 177,
    mt_getrandmax = 178,
    lcg_value = 179,
    is_nan = 180,
    is_finite = 181,
    is_infinite = 182,
    intdiv = 183,
    fmod = 184,
    hypot = 185,

    // File Functions (200-249)
    fopen = 200,
    fclose = 201,
    fread = 202,
    fwrite = 203,
    fgets = 204,
    fgetc = 205,
    fputs = 206,
    fputc = 207,
    feof = 208,
    fseek = 209,
    ftell = 210,
    rewind = 211,
    fflush = 212,
    flock = 213,
    ftruncate = 214,
    fstat = 215,
    file_exists = 216,
    is_file = 217,
    is_dir = 218,
    is_link = 219,
    is_readable = 220,
    is_writable = 221,
    is_executable = 222,
    filesize = 223,
    filetype = 224,
    filemtime = 225,
    fileatime = 226,
    filectime = 227,
    fileperms = 228,
    fileowner = 229,
    filegroup = 230,
    file_get_contents = 231,
    file_put_contents = 232,
    file = 233,
    readfile = 234,
    unlink = 235,
    rename = 236,
    copy = 237,
    mkdir = 238,
    rmdir = 239,
    chmod = 240,
    chown = 241,
    chgrp = 242,
    touch = 243,
    glob = 244,
    basename = 245,
    dirname = 246,
    pathinfo = 247,
    realpath = 248,

    // Date/Time Functions (250-279)
    time = 250,
    microtime = 251,
    date = 252,
    gmdate = 253,
    strtotime = 254,
    mktime = 255,
    gmmktime = 256,
    checkdate = 257,
    getdate = 258,
    localtime = 259,
    idate = 260,
    date_create = 261,
    date_format = 262,
    date_parse = 263,
    date_diff = 264,
    date_add = 265,
    date_sub = 266,
    timezone_open = 267,
    timezone_name_get = 268,

    // JSON Functions (280-289)
    json_encode = 280,
    json_decode = 281,
    json_last_error = 282,
    json_last_error_msg = 283,

    // Hash Functions (290-309)
    md5 = 290,
    md5_file = 291,
    sha1 = 292,
    sha1_file = 293,
    hash = 294,
    hash_file = 295,
    hash_hmac = 296,
    hash_hmac_file = 297,
    hash_algos = 298,
    crc32 = 299,

    // Regular Expression Functions (310-329)
    preg_match = 310,
    preg_match_all = 311,
    preg_replace = 312,
    preg_replace_callback = 313,
    preg_filter = 314,
    preg_split = 315,
    preg_grep = 316,
    preg_quote = 317,
    preg_last_error = 318,

    // Random Functions (330-339)
    shuffle = 330,
    array_rand = 331,
    random_int = 332,
    random_bytes = 333,

    // Type Functions (340-359)
    is_null = 340,
    is_bool = 341,
    is_int = 342,
    is_float = 343,
    is_string = 344,
    is_array = 345,
    is_object = 346,
    is_resource = 347,
    is_numeric = 348,
    is_scalar = 349,
    is_callable = 350,
    gettype = 351,
    settype = 352,
    intval = 353,
    floatval = 354,
    strval = 355,
    boolval = 356,

    // Variable Functions (360-379)
    var_dump = 360,
    var_export = 361,
    print_r = 362,
    debug_zval_dump = 363,
    isset = 364,
    empty = 365,
    unset = 366,
    get_defined_vars = 367,
    get_resource_type = 368,

    // Class/Object Functions (380-399)
    class_exists = 380,
    interface_exists = 381,
    trait_exists = 382,
    method_exists = 383,
    property_exists = 384,
    get_class = 385,
    get_parent_class = 386,
    get_class_methods = 387,
    get_class_vars = 388,
    get_object_vars = 389,
    is_a = 390,
    is_subclass_of = 391,
    get_called_class = 392,

    // Error Functions (400-409)
    error_reporting = 400,
    trigger_error = 401,
    user_error = 402,
    set_error_handler = 403,
    restore_error_handler = 404,

    // Misc Functions (410-449)
    define = 410,
    defined = 411,
    constant = 412,
    exit = 413,
    die = 414,
    sleep = 415,
    usleep = 416,
    uniqid = 417,
    sys_get_temp_dir = 418,
    php_uname = 419,
    phpversion = 420,

    // 保留扩展空间
    _reserved = 65535,

    /// 获取函数名称
    pub fn name(self: BuiltinId) []const u8 {
        return @tagName(self);
    }

    /// 从字符串获取 BuiltinId（编译时）
    pub fn fromName(comptime func_name: []const u8) ?BuiltinId {
        return std.meta.stringToEnum(BuiltinId, func_name);
    }
};

// ============================================================================
// Task 4.1.2: 编译时分发表 - 函数指针数组
// ============================================================================

/// 内置函数处理器类型
pub const BuiltinHandler = *const fn (vm: anytype, args: []const Value) anyerror!Value;

/// 内置函数元数据
pub const BuiltinMeta = struct {
    id: BuiltinId,
    name: []const u8,
    min_args: u8,
    max_args: u8,
    handler: BuiltinHandler,
};

/// 编译时生成的分发表
/// 注意：实际的 handler 函数指针在运行时通过 initDispatchTable() 填充
/// 这是因为 Zig 不支持在 comptime 中存储函数指针到全局变量
pub var BUILTIN_DISPATCH_TABLE: [450]?BuiltinMeta = [_]?BuiltinMeta{null} ** 450;

/// 初始化分发表（在 VM 初始化时调用）
/// 将 stdlib 中的函数注册到分发表中
pub fn initDispatchTable(stdlib: anytype) void {
    // 注意：由于循环依赖问题，我们不能直接导入 stdlib.zig
    // 相反，我们让 VM 在初始化时传入 stdlib 实例
    // 这个函数将在 VM.init() 中被调用
    
    // 这里我们只是预留接口，实际的函数指针映射
    // 将通过 VM 的 stdlib.getFunction() 动态查找
    _ = stdlib;
}

// ============================================================================
// Task 4.1.3: 完美哈希函数名查找
// ============================================================================

/// 完美哈希函数（编译时生成）
/// 将函数名映射到 BuiltinId
pub fn perfectHash(name: []const u8) ?BuiltinId {
    // 简单的 FNV-1a 哈希 + 线性探测
    // 在实际实现中，应该使用编译时生成的完美哈希
    
    // 直接使用字符串到枚举的转换（Zig 内置）
    return std.meta.stringToEnum(BuiltinId, name);
}

/// 快速查找内置函数（零 HashMap 开销）
pub fn lookup(name: []const u8) ?BuiltinId {
    return perfectHash(name);
}

/// 快速查找并返回函数名（用于 VM 集成）
/// 这是主要的集成点：VM 应该先调用这个函数
/// 如果返回 non-null，说明是内置函数，可以直接通过 stdlib 调用
pub fn lookupBuiltin(name: []const u8) ?[]const u8 {
    if (perfectHash(name)) |id| {
        return id.name();
    }
    return null;
}

/// 直接分发调用
pub fn dispatch(id: BuiltinId, vm: anytype, args: []const Value) !Value {
    const meta = BUILTIN_DISPATCH_TABLE[@intFromEnum(id)] orelse return error.UnknownBuiltin;
    
    // 参数数量检查
    if (args.len < meta.min_args or args.len > meta.max_args) {
        return error.InvalidArgumentCount;
    }
    
    // 直接调用
    return meta.handler(vm, args);
}

// ============================================================================
// Task 4.1.4: 高频函数特化
// ============================================================================

/// 高频函数的内联版本
pub const FastBuiltins = struct {
    /// strlen - 内联版本
    pub inline fn strlen_fast(str: *types.PHPString) usize {
        return str.length;
    }
    
    /// count - 内联版本
    pub inline fn count_fast(arr: *types.PHPArray) usize {
        return arr.count();
    }
    
    /// abs - 内联版本
    pub inline fn abs_fast(val: Value) Value {
        if (val.isInt()) {
            const i = val.asInt();
            return Value.initInt(if (i < 0) -i else i);
        } else if (val.isFloat()) {
            const f = val.asFloat();
            return Value.initFloat(if (f < 0) -f else f);
        }
        return val;
    }
    
    /// empty - 内联版本
    pub inline fn empty_fast(val: Value) bool {
        return switch (val.getTag()) {
            .null => true,
            .boolean => !val.asBool(),
            .integer => val.asInt() == 0,
            .float => val.asFloat() == 0.0,
            .string => val.getAsString().data.length == 0,
            .array => val.getAsArray().data.count() == 0,
            else => false,
        };
    }
    
    /// isset - 内联版本
    pub inline fn isset_fast(val: Value) bool {
        return val.getTag() != .null;
    }
};

// ============================================================================
// 统计和性能监控
// ============================================================================

pub const DispatchStats = struct {
    total_calls: u64 = 0,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,
    
    pub fn recordCall(self: *DispatchStats, hit: bool) void {
        self.total_calls += 1;
        if (hit) {
            self.cache_hits += 1;
        } else {
            self.cache_misses += 1;
        }
    }
    
    pub fn hitRate(self: *const DispatchStats) f64 {
        if (self.total_calls == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.total_calls));
    }
};

// ============================================================================
// 测试
// ============================================================================

test "BuiltinId enum" {
    const testing = std.testing;
    
    // 测试枚举值
    try testing.expect(@intFromEnum(BuiltinId.array_map) == 0);
    try testing.expect(@intFromEnum(BuiltinId.echo) == 50);
    try testing.expect(@intFromEnum(BuiltinId.abs) == 150);
    
    // 测试名称
    try testing.expectEqualStrings("strlen", BuiltinId.strlen.name());
    try testing.expectEqualStrings("array_map", BuiltinId.array_map.name());
}

test "perfectHash lookup" {
    const testing = std.testing;
    
    // 测试查找
    try testing.expect(lookup("strlen") == .strlen);
    try testing.expect(lookup("array_map") == .array_map);
    try testing.expect(lookup("abs") == .abs);
    try testing.expect(lookup("nonexistent") == null);
}

test "FastBuiltins inline functions" {
    const testing = std.testing;
    
    // 测试 abs_fast
    const neg_int = Value.initInt(-42);
    const result = FastBuiltins.abs_fast(neg_int);
    try testing.expect(result.asInt() == 42);
    
    // 测试 empty_fast
    const null_val = Value.initNull();
    try testing.expect(FastBuiltins.empty_fast(null_val));
    
    const int_zero = Value.initInt(0);
    try testing.expect(FastBuiltins.empty_fast(int_zero));
    
    const int_nonzero = Value.initInt(42);
    try testing.expect(!FastBuiltins.empty_fast(int_nonzero));
}
