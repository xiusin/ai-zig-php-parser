//! ============================================================================
//! 编译时生成的内置函数分发表
//! ============================================================================
//!
//! 从 fn_table.zig 自动生成所有分发数据结构：
//! - BuiltinId (u16) — 函数 ID，值等于 FN_TABLE 中的索引
//! - META_TABLE 元数据表 — 从 FN_TABLE 自动映射
//! - NAME_LOOKUP 名称查找表 — comptime 生成的 StaticStringMap
//! - lookup / getMeta / validateArgs 函数
//! - 兼容旧 builtin_dispatch.zig 的接口
//!
//! 设计原则：
//! 1. 单一真相源：fn_table.zig 是唯一的函数声明来源
//! 2. 零手写 ID：BuiltinId 值由 FN_TABLE 索引自动确定
//! 3. 零手写分发表：META_TABLE 由 comptime 从 FN_TABLE 映射
//! 4. 高性能查找：std.StaticStringMap（编译时完美哈希）
//! 5. 统一参数校验：在 dispatch 层处理，函数实现无需重复
//!
//! Zig 0.16.0 适配说明：
//! - Zig 0.16.0 移除了 @Type，无法在 comptime 动态创建枚举类型
//! - BuiltinId 使用 u16 而非 comptime 枚举，功能等价
//! - 名称查找使用 std.StaticStringMap，性能优于 stringToEnum

const std = @import("std");
const fn_table = @import("fn_table.zig");
const types = @import("types.zig");
const Value = types.Value;

// Handler 模块导入 — 用于 comptime 生成 HANDLER_MAP_KVS
const stdlib_array = @import("stdlib_array.zig");
const stdlib_string = @import("stdlib_string.zig");
const stdlib_math = @import("stdlib_math.zig");
const stdlib_datetime = @import("stdlib_datetime.zig");
const stdlib_json = @import("stdlib_json.zig");
const stdlib_hash = @import("stdlib_hash.zig");
const stdlib_type = @import("stdlib_type.zig");
const stdlib_misc = @import("stdlib_misc.zig");
const builtin_io = @import("builtin_io.zig");
const pcre2 = @import("pcre2.zig");
const builtin_vars = @import("builtin_vars.zig");
const php85_features = @import("php85_features.zig");

// 避免在 build test 中出现模块冲突
// 当作为 runtime 模块的一部分时，types.zig 等通过相对路径导入
// 当作为独立测试时，通过 build.zig 的 addImport 注入

// ============================================================================
// 1. BuiltinId — 函数 ID 类型
// ============================================================================

/// 内置函数 ID 类型
/// 值等于 FN_TABLE 中的索引，范围 [0, FN_TABLE.len)
/// 使用 u16 而非 comptime 枚举，因为 Zig 0.16.0 移除了 @Type
pub const BuiltinId = u16;

/// 无效的 BuiltinId 值
pub const INVALID_BUILTIN_ID: BuiltinId = std.math.maxInt(BuiltinId);

/// BuiltinId 的有效范围
pub const BUILTIN_COUNT: usize = fn_table.FN_TABLE.len;

// ============================================================================
// 2. 元数据表 — 编译时生成
// ============================================================================

/// 内置函数元数据结构
pub const BuiltinMeta = struct {
    id: BuiltinId,
    name: []const u8,
    min_args: u8,
    max_args: u8, // 255 = variadic
    category: fn_table.FnCategory,
};

/// 编译时生成的元数据表
/// 索引即为 BuiltinId 的值
pub const META_TABLE: [fn_table.FN_TABLE.len]BuiltinMeta = blk: {
    @setEvalBranchQuota(fn_table.FN_TABLE.len * 10 + 1000);
    var table: [fn_table.FN_TABLE.len]BuiltinMeta = undefined;
    for (fn_table.FN_TABLE, 0..) |entry, i| {
        table[i] = .{
            .id = @intCast(i),
            .name = entry.name,
            .min_args = entry.min_args,
            .max_args = entry.max_args,
            .category = entry.category,
        };
    }
    break :blk table;
};

// ============================================================================
// 3. 名称查找 — comptime 生成的 StaticStringMap
// ============================================================================

/// 编译时生成的名称 → BuiltinId 查找表
/// 使用 StaticStringMap 实现高效查找
const NameLookupKVs = blk: {
    @setEvalBranchQuota(fn_table.FN_TABLE.len * 10 + 1000);
    var kvs: [fn_table.FN_TABLE.len]struct { []const u8, BuiltinId } = undefined;
    for (fn_table.FN_TABLE, 0..) |entry, i| {
        kvs[i] = .{ entry.name, @intCast(i) };
    }
    break :blk kvs[0..].*;
};

const NAME_LOOKUP = std.StaticStringMap(BuiltinId).initComptime(NameLookupKVs);

/// 从函数名查找 BuiltinId
/// 使用 StaticStringMap，编译时生成完美哈希，O(1) 查找
pub fn lookup(name: []const u8) ?BuiltinId {
    return NAME_LOOKUP.get(name);
}

/// 从 BuiltinId 获取元数据
/// O(1) 数组索引访问
pub fn getMeta(id: BuiltinId) ?*const BuiltinMeta {
    if (id >= fn_table.FN_TABLE.len) return null;
    return &META_TABLE[id];
}

// ============================================================================
// 4. 内置函数错误类型（从 builtin_registry.zig 迁移）
// ============================================================================

/// 内置函数错误类型
/// 从 builtin_registry.zig 迁移至此，作为统一的错误定义
/// 所有 builtin_* 模块应通过 fn_dispatch.BuiltinError 引用
pub const BuiltinError = error{
    FunctionNotFound,
    ArgumentCountMismatch,
    InvalidArgumentType,
    DivisionByZero,
    MathDomainError,
    RandomSeedError,
    BigDecimalOverflow,
    TimeFormatError,
    ChannelClosed,
    DeadlockDetected,
    CoroutineTimeout,
    StackOverflow,
    InvalidPriority,
    SchedulerNotRunning,
};

// ============================================================================
// 5. 统一参数校验
// ============================================================================

/// 参数校验错误
pub const ArgValidationError = error{
    TooFewArguments,
    TooManyArguments,
};

/// 统一参数校验（在 dispatch 层处理，函数实现无需重复）
/// max_args == 255 表示可变参数，不检查上限
pub fn validateArgs(id: BuiltinId, arg_count: usize) ArgValidationError!void {
    const meta = getMeta(id) orelse return error.TooFewArguments;
    if (arg_count < meta.min_args) return ArgValidationError.TooFewArguments;
    if (meta.max_args != 255 and arg_count > meta.max_args) return ArgValidationError.TooManyArguments;
}

// ============================================================================
// 6. Handler 分发表 — comptime 生成，O(1) 分发
// ============================================================================

/// Handler 类型 — 使用 anyopaque 避免与 VM 的循环依赖
/// 实际调用时通过 @ptrCast 转换为 *const fn (*VM, []const Value) anyerror!Value
pub const BuiltinHandler = *const fn (*anyopaque, []const Value) anyerror!Value;

/// 所有已实现函数的 handler 映射 — 新增函数只需在此追加一行
/// 这是 handler 注册的单一真相源，消除了 stdlib.zig 中的手动注册列表
/// 使用元组格式以兼容 std.StaticStringMap.initComptime
const HANDLER_MAP_KVS = [_]struct { []const u8, BuiltinHandler }{
    // ========================================================================
    // Array Functions (stdlib_array)
    // ========================================================================
    .{ "array_map", @ptrCast(&stdlib_array.arrayMapFn) },
    .{ "array_filter", @ptrCast(&stdlib_array.arrayFilterFn) },
    .{ "array_reduce", @ptrCast(&stdlib_array.arrayReduceFn) },
    .{ "array_merge", @ptrCast(&stdlib_array.arrayMergeFn) },
    .{ "array_keys", @ptrCast(&stdlib_array.arrayKeysFn) },
    .{ "array_values", @ptrCast(&stdlib_array.arrayValuesFn) },
    .{ "array_push", @ptrCast(&stdlib_array.arrayPushFn) },
    .{ "array_pop", @ptrCast(&stdlib_array.arrayPopFn) },
    .{ "array_shift", @ptrCast(&stdlib_array.arrayShiftFn) },
    .{ "array_unshift", @ptrCast(&stdlib_array.arrayUnshiftFn) },
    .{ "in_array", @ptrCast(&stdlib_array.inArrayFn) },
    .{ "array_search", @ptrCast(&stdlib_array.arraySearchFn) },
    .{ "array_first", @ptrCast(&stdlib_array.arrayFirstFn) },
    .{ "array_last", @ptrCast(&stdlib_array.arrayLastFn) },
    .{ "array_sum", @ptrCast(&stdlib_array.arraySumFn) },
    .{ "array_product", @ptrCast(&stdlib_array.arrayProductFn) },
    .{ "array_reverse", @ptrCast(&stdlib_array.arrayReverseFn) },
    .{ "array_unique", @ptrCast(&stdlib_array.arrayUniqueFn) },
    .{ "array_flip", @ptrCast(&stdlib_array.arrayFlipFn) },
    .{ "array_slice", @ptrCast(&stdlib_array.arraySliceFn) },
    .{ "array_column", @ptrCast(&stdlib_array.arrayColumnFn) },
    .{ "range", @ptrCast(&stdlib_array.rangeFunction) },
    .{ "array_fill", @ptrCast(&stdlib_array.arrayFillFn) },
    .{ "compact", @ptrCast(&stdlib_array.compactFn) },
    .{ "sort", @ptrCast(&stdlib_array.sortFn) },
    .{ "rsort", @ptrCast(&stdlib_array.rsortFn) },
    .{ "asort", @ptrCast(&stdlib_array.asortFn) },
    .{ "arsort", @ptrCast(&stdlib_array.arsortFn) },
    .{ "ksort", @ptrCast(&stdlib_array.ksortFn) },
    .{ "krsort", @ptrCast(&stdlib_array.krsortFn) },
    .{ "usort", @ptrCast(&stdlib_array.usortFn) },
    .{ "uasort", @ptrCast(&stdlib_array.uasortFn) },
    .{ "uksort", @ptrCast(&stdlib_array.uksortFn) },
    .{ "count", @ptrCast(&stdlib_array.countFn) },
    .{ "sizeof", @ptrCast(&stdlib_array.countFn) },
    .{ "array_key_exists", @ptrCast(&stdlib_array.arrayKeyExistsFn) },
    .{ "array_combine", @ptrCast(&stdlib_array.arrayCombineFn) },
    .{ "array_intersect", @ptrCast(&stdlib_array.arrayIntersectFn) },
    .{ "array_splice", @ptrCast(&stdlib_array.arraySpliceFn) },
    .{ "array_walk", @ptrCast(&stdlib_array.arrayWalkFn) },
    .{ "array_chunk", @ptrCast(&stdlib_array.arrayChunkFn) },
    .{ "array_pad", @ptrCast(&stdlib_array.arrayPadFn) },
    .{ "array_key_first", @ptrCast(&stdlib_array.arrayKeyFirstFn) },
    .{ "array_key_last", @ptrCast(&stdlib_array.arrayKeyLastFn) },
    .{ "array_fill_keys", @ptrCast(&stdlib_array.arrayFillKeysFn) },
    .{ "array_change_key_case", @ptrCast(&stdlib_array.arrayChangeKeyCaseFn) },
    .{ "array_count_values", @ptrCast(&stdlib_array.arrayCountValuesFn) },
    .{ "array_rand", @ptrCast(&stdlib_array.arrayRandWrapper) },
    .{ "shuffle", @ptrCast(&stdlib_array.shuffleWrapper) },
    .{ "array_diff", @ptrCast(&stdlib_array.arrayDiffFn) },
    .{ "isset", @ptrCast(&stdlib_array.issetFn) },
    .{ "end", @ptrCast(&stdlib_array.endFn) },
    .{ "reset", @ptrCast(&stdlib_array.resetFn) },
    .{ "current", @ptrCast(&stdlib_array.currentFn) },
    .{ "key", @ptrCast(&stdlib_array.keyFn) },
    .{ "next", @ptrCast(&stdlib_array.nextFn) },
    .{ "prev", @ptrCast(&stdlib_array.prevFn) },

    // ========================================================================
    // String Functions (stdlib_string)
    // ========================================================================
    .{ "echo", @ptrCast(&stdlib_string.echoFn) },
    .{ "strlen", @ptrCast(&stdlib_string.strlenFn) },
    .{ "substr", @ptrCast(&stdlib_string.substrFn) },
    .{ "str_replace", @ptrCast(&stdlib_string.strReplaceFn) },
    .{ "str_ireplace", @ptrCast(&stdlib_string.strIreplaceFn) },
    .{ "strpos", @ptrCast(&stdlib_string.strposFn) },
    .{ "stripos", @ptrCast(&stdlib_string.striposFn) },
    .{ "strrpos", @ptrCast(&stdlib_string.strrposFn) },
    .{ "strripos", @ptrCast(&stdlib_string.strriposFn) },
    .{ "strtolower", @ptrCast(&stdlib_string.strtolowerFn) },
    .{ "strtoupper", @ptrCast(&stdlib_string.strtoupperFn) },
    .{ "trim", @ptrCast(&stdlib_string.trimFn) },
    .{ "ltrim", @ptrCast(&stdlib_string.ltrimFn) },
    .{ "rtrim", @ptrCast(&stdlib_string.rtrimFn) },
    .{ "explode", @ptrCast(&stdlib_string.explodeFn) },
    .{ "implode", @ptrCast(&stdlib_string.implodeFn) },
    .{ "str_repeat", @ptrCast(&stdlib_string.strRepeatFn) },
    .{ "sprintf", @ptrCast(&stdlib_string.sprintfFn) },
    .{ "printf", @ptrCast(&stdlib_string.printfFn) },
    .{ "str_contains", @ptrCast(&stdlib_string.strContainsFn) },
    .{ "str_starts_with", @ptrCast(&stdlib_string.strStartsWithFn) },
    .{ "str_ends_with", @ptrCast(&stdlib_string.strEndsWithFn) },
    .{ "ucfirst", @ptrCast(&stdlib_string.ucfirstFn) },
    .{ "lcfirst", @ptrCast(&stdlib_string.lcfirstFn) },
    .{ "ucwords", @ptrCast(&stdlib_string.ucwordsFn) },
    .{ "str_pad", @ptrCast(&stdlib_string.strPadFn) },
    .{ "strrev", @ptrCast(&stdlib_string.strrevFn) },
    .{ "str_split", @ptrCast(&stdlib_string.strSplitFn) },
    .{ "chunk_split", @ptrCast(&stdlib_string.chunkSplitFn) },
    .{ "wordwrap", @ptrCast(&stdlib_string.wordwrapFn) },
    .{ "nl2br", @ptrCast(&stdlib_string.nl2brFn) },
    .{ "strip_tags", @ptrCast(&stdlib_string.stripTagsFn) },
    .{ "htmlspecialchars", @ptrCast(&stdlib_string.htmlspecialcharsFn) },
    .{ "htmlentities", @ptrCast(&stdlib_string.htmlentitiesFn) },
    .{ "number_format", @ptrCast(&stdlib_string.numberFormatFn) },
    .{ "bin2hex", @ptrCast(&stdlib_string.bin2hexFn) },
    .{ "hex2bin", @ptrCast(&stdlib_string.hex2binFn) },
    .{ "base64_encode", @ptrCast(&stdlib_string.base64EncodeFn) },
    .{ "base64_decode", @ptrCast(&stdlib_string.base64DecodeFn) },
    .{ "md5", @ptrCast(&stdlib_string.md5Fn) },
    .{ "sha1", @ptrCast(&stdlib_string.sha1Fn) },
    .{ "uniqid", @ptrCast(&stdlib_string.uniqidFn) },
    .{ "ord", @ptrCast(&stdlib_string.ordFn) },
    .{ "chr", @ptrCast(&stdlib_string.chrFn) },
    .{ "print", @ptrCast(&stdlib_string.printFn) },
    .{ "join", @ptrCast(&stdlib_string.joinFn) },
    .{ "strcmp", @ptrCast(&stdlib_string.strcmpFn) },
    .{ "strcasecmp", @ptrCast(&stdlib_string.strcasecmpFn) },
    .{ "strncmp", @ptrCast(&stdlib_string.strncmpFn) },
    .{ "strncasecmp", @ptrCast(&stdlib_string.strncasecmpFn) },
    .{ "substr_count", @ptrCast(&stdlib_string.substrCountFn) },
    .{ "substr_replace", @ptrCast(&stdlib_string.substrReplaceFn) },
    .{ "addslashes", @ptrCast(&stdlib_string.addslashesFn) },
    .{ "stripslashes", @ptrCast(&stdlib_string.stripslashesFn) },
    .{ "str_shuffle", @ptrCast(&stdlib_string.strShuffleFn) },
    .{ "html_entity_decode", @ptrCast(&stdlib_string.htmlEntityDecodeFn) },
    .{ "parse_str", @ptrCast(&stdlib_string.parseStrFn) },
    .{ "urlencode", @ptrCast(&stdlib_string.urlencodeFn) },
    .{ "urldecode", @ptrCast(&stdlib_string.urldecodeFn) },
    .{ "rawurlencode", @ptrCast(&stdlib_string.rawurlencodeFn) },
    .{ "rawurldecode", @ptrCast(&stdlib_string.rawurldecodeFn) },
    .{ "str_word_count", @ptrCast(&stdlib_string.strWordCountFn) },
    .{ "levenshtein", @ptrCast(&stdlib_string.levenshteinFn) },
    .{ "similar_text", @ptrCast(&stdlib_string.similarTextFn) },
    .{ "strstr", @ptrCast(&stdlib_string.strstrFn) },
    .{ "stristr", @ptrCast(&stdlib_string.stristrFn) },
    .{ "strrchr", @ptrCast(&stdlib_string.strrchrFn) },

    // ========================================================================
    // Math Functions (stdlib_math)
    // ========================================================================
    .{ "abs", @ptrCast(&stdlib_math.absFn) },
    .{ "round", @ptrCast(&stdlib_math.roundFn) },
    .{ "sqrt", @ptrCast(&stdlib_math.sqrtFn) },
    .{ "pow", @ptrCast(&stdlib_math.powFn) },
    .{ "floor", @ptrCast(&stdlib_math.floorFn) },
    .{ "ceil", @ptrCast(&stdlib_math.ceilFn) },
    .{ "min", @ptrCast(&stdlib_math.minFn) },
    .{ "max", @ptrCast(&stdlib_math.maxFn) },
    .{ "rand", @ptrCast(&stdlib_math.randFn) },
    .{ "mt_rand", @ptrCast(&stdlib_math.mtRandFn) },
    .{ "bit_and", @ptrCast(&stdlib_math.bitAndFn) },
    .{ "bit_or", @ptrCast(&stdlib_math.bitOrFn) },
    .{ "bit_xor", @ptrCast(&stdlib_math.bitXorFn) },
    .{ "bit_not", @ptrCast(&stdlib_math.bitNotFn) },
    .{ "bit_shift_left", @ptrCast(&stdlib_math.bitShiftLeftFn) },
    .{ "bit_shift_right", @ptrCast(&stdlib_math.bitShiftRightFn) },
    .{ "sin", @ptrCast(&stdlib_math.sinFn) },
    .{ "cos", @ptrCast(&stdlib_math.cosFn) },
    .{ "tan", @ptrCast(&stdlib_math.tanFn) },
    .{ "log", @ptrCast(&stdlib_math.logFn) },
    .{ "log10", @ptrCast(&stdlib_math.log10Fn) },
    .{ "log2", @ptrCast(&stdlib_math.log2Fn) },
    .{ "exp", @ptrCast(&stdlib_math.expFn) },
    .{ "pi", @ptrCast(&stdlib_math.piFn) },
    .{ "deg2rad", @ptrCast(&stdlib_math.deg2radFn) },
    .{ "rad2deg", @ptrCast(&stdlib_math.rad2degFn) },
    .{ "asin", @ptrCast(&stdlib_math.asinFn) },
    .{ "acos", @ptrCast(&stdlib_math.acosFn) },
    .{ "atan", @ptrCast(&stdlib_math.atanFn) },
    .{ "atan2", @ptrCast(&stdlib_math.atan2Fn) },
    .{ "hypot", @ptrCast(&stdlib_math.hypotFn) },
    .{ "fmod", @ptrCast(&stdlib_math.fmodFn) },
    .{ "intdiv", @ptrCast(&stdlib_math.intdivFn) },
    .{ "sinh", @ptrCast(&stdlib_math.sinhFn) },
    .{ "cosh", @ptrCast(&stdlib_math.coshFn) },
    .{ "tanh", @ptrCast(&stdlib_math.tanhFn) },
    .{ "is_nan", @ptrCast(&stdlib_math.isNanFn) },
    .{ "is_finite", @ptrCast(&stdlib_math.isFiniteFn) },
    .{ "is_infinite", @ptrCast(&stdlib_math.isInfiniteFn) },
    .{ "srand", @ptrCast(&stdlib_math.srandFn) },
    .{ "mt_srand", @ptrCast(&stdlib_math.mtSrandFn) },
    .{ "getrandmax", @ptrCast(&stdlib_math.getrandmaxFn) },
    .{ "mt_getrandmax", @ptrCast(&stdlib_math.mtGetrandmaxFn) },
    .{ "random_int", @ptrCast(&stdlib_math.randomIntFn) },
    .{ "random_bytes", @ptrCast(&stdlib_math.randomBytesFn) },
    .{ "decbin", @ptrCast(&stdlib_math.decbinFn) },
    .{ "dechex", @ptrCast(&stdlib_math.dechexFn) },
    .{ "decoct", @ptrCast(&stdlib_math.decoctFn) },
    .{ "bindec", @ptrCast(&stdlib_math.bindecFn) },
    .{ "hexdec", @ptrCast(&stdlib_math.hexdecFn) },
    .{ "octdec", @ptrCast(&stdlib_math.octdecFn) },
    .{ "base_convert", @ptrCast(&stdlib_math.baseConvertFn) },

    // ========================================================================
    // File Functions (builtin_io)
    // ========================================================================
    .{ "file_get_contents", @ptrCast(&builtin_io.fileGetContentsFn) },
    .{ "file_put_contents", @ptrCast(&builtin_io.filePutContentsFn) },
    .{ "file_exists", @ptrCast(&builtin_io.fileExistsFn) },
    .{ "is_file", @ptrCast(&builtin_io.isFileFn) },
    .{ "is_dir", @ptrCast(&builtin_io.isDirFn) },
    .{ "filesize", @ptrCast(&builtin_io.filesizeFn) },
    .{ "filemtime", @ptrCast(&builtin_io.filemtimeFn) },
    .{ "file", @ptrCast(&builtin_io.fileFn) },
    .{ "readfile", @ptrCast(&builtin_io.readfileFn) },
    .{ "unlink", @ptrCast(&builtin_io.unlinkFn) },
    .{ "rename", @ptrCast(&builtin_io.renameFn) },
    .{ "copy", @ptrCast(&builtin_io.copyFn) },
    .{ "flock", @ptrCast(&builtin_io.flockFn) },
    .{ "ftruncate", @ptrCast(&builtin_io.ftruncateFn) },
    .{ "is_readable", @ptrCast(&builtin_io.isReadableFn) },
    .{ "is_writable", @ptrCast(&builtin_io.isWritableFn) },
    .{ "is_executable", @ptrCast(&builtin_io.isExecutableFn) },
    .{ "clearstatcache", @ptrCast(&builtin_io.clearstatcacheFn) },
    .{ "disk_free_space", @ptrCast(&builtin_io.diskFreeSpaceFn) },
    .{ "disk_total_space", @ptrCast(&builtin_io.diskTotalSpaceFn) },
    .{ "is_link", @ptrCast(&builtin_io.isLinkFn) },
    .{ "chmod", @ptrCast(&builtin_io.chmodFn) },
    .{ "chown", @ptrCast(&builtin_io.chownFn) },
    .{ "chgrp", @ptrCast(&builtin_io.chgrpFn) },
    .{ "link", @ptrCast(&builtin_io.linkFn) },
    .{ "symlink", @ptrCast(&builtin_io.symlinkFn) },
    .{ "readlink", @ptrCast(&builtin_io.readlinkFn) },
    .{ "lstat", @ptrCast(&builtin_io.lstatFn) },
    .{ "stat", @ptrCast(&builtin_io.statFn) },
    .{ "fnmatch", @ptrCast(&builtin_io.fnmatchFn) },
    .{ "glob", @ptrCast(&builtin_io.globFn) },
    .{ "mkdir", @ptrCast(&builtin_io.mkdirFn) },
    .{ "rmdir", @ptrCast(&builtin_io.rmdirFn) },
    .{ "scandir", @ptrCast(&builtin_io.scandirFn) },
    .{ "basename", @ptrCast(&builtin_io.basenameFn) },
    .{ "dirname", @ptrCast(&builtin_io.dirnameFn) },
    .{ "realpath", @ptrCast(&builtin_io.realpathFn) },
    .{ "pathinfo", @ptrCast(&builtin_io.pathinfoFn) },
    .{ "fopen", @ptrCast(&builtin_io.fopenFn) },
    .{ "fclose", @ptrCast(&builtin_io.fcloseFn) },
    .{ "fread", @ptrCast(&builtin_io.freadFn) },
    .{ "fwrite", @ptrCast(&builtin_io.fwriteFn) },
    .{ "feof", @ptrCast(&builtin_io.feofFn) },
    .{ "fseek", @ptrCast(&builtin_io.fseekFn) },
    .{ "ftell", @ptrCast(&builtin_io.ftellFn) },
    .{ "fgets", @ptrCast(&builtin_io.fgetsFn) },
    .{ "fgetc", @ptrCast(&builtin_io.fgetcFn) },
    .{ "rewind", @ptrCast(&builtin_io.rewindFn) },
    .{ "fflush", @ptrCast(&builtin_io.fflushFn) },

    // ========================================================================
    // Date/Time Functions (stdlib_datetime)
    // ========================================================================
    .{ "time", @ptrCast(&stdlib_datetime.timeFn) },
    .{ "microtime", @ptrCast(&stdlib_datetime.microtimeFn) },
    .{ "date", @ptrCast(&stdlib_datetime.dateFn) },
    .{ "strtotime", @ptrCast(&stdlib_datetime.strtotimeFn) },
    .{ "mktime", @ptrCast(&stdlib_datetime.mktimeFn) },
    .{ "gmdate", @ptrCast(&stdlib_datetime.gmdateFn) },
    .{ "usleep", @ptrCast(&stdlib_datetime.usleepFn) },
    .{ "sleep", @ptrCast(&stdlib_datetime.sleepFn) },
    .{ "checkdate", @ptrCast(&stdlib_datetime.checkdateFn) },
    .{ "getdate", @ptrCast(&stdlib_datetime.getDateFn) },

    // ========================================================================
    // JSON Functions (stdlib_json)
    // ========================================================================
    .{ "json_encode", @ptrCast(&stdlib_json.jsonEncodeFn) },
    .{ "json_decode", @ptrCast(&stdlib_json.jsonDecodeFn) },
    .{ "json_last_error", @ptrCast(&stdlib_json.jsonLastErrorFn) },
    .{ "json_last_error_msg", @ptrCast(&stdlib_json.jsonLastErrorMsgFn) },

    // ========================================================================
    // Hash Functions (stdlib_hash + stdlib_string)
    // ========================================================================
    .{ "sha256", @ptrCast(&stdlib_hash.sha256Fn) },
    .{ "sha512", @ptrCast(&stdlib_hash.sha512Fn) },
    .{ "hash", @ptrCast(&stdlib_hash.hashFn) },
    .{ "hash_algos", @ptrCast(&stdlib_hash.hashAlgosFn) },
    .{ "crc32", @ptrCast(&stdlib_hash.crc32Fn) },

    // ========================================================================
    // Regular Expression Functions (pcre2)
    // ========================================================================
    .{ "preg_match", @ptrCast(&pcre2.pregMatchFn) },
    .{ "preg_match_all", @ptrCast(&pcre2.pregMatchAllFn) },
    .{ "preg_replace", @ptrCast(&pcre2.pregReplaceFn) },
    .{ "preg_replace_callback", @ptrCast(&pcre2.pregReplaceCallbackFn) },
    .{ "preg_filter", @ptrCast(&pcre2.pregFilterFn) },
    .{ "preg_split", @ptrCast(&pcre2.pregSplitFn) },
    .{ "preg_grep", @ptrCast(&pcre2.pregGrepFn) },
    .{ "preg_quote", @ptrCast(&pcre2.pregQuoteFn) },
    .{ "preg_last_error", @ptrCast(&pcre2.pregLastErrorFn) },

    // ========================================================================
    // Type Functions (stdlib_type)
    // ========================================================================
    .{ "serialize", @ptrCast(&stdlib_type.serializeFn) },
    .{ "unserialize", @ptrCast(&stdlib_type.unserializeFn) },
    .{ "gettype", @ptrCast(&stdlib_type.gettypeFn) },
    .{ "settype", @ptrCast(&stdlib_type.settypeFn) },
    .{ "is_null", @ptrCast(&stdlib_type.isNullFn) },
    .{ "is_bool", @ptrCast(&stdlib_type.isBoolFn) },
    .{ "is_int", @ptrCast(&stdlib_type.isIntFn) },
    .{ "is_integer", @ptrCast(&stdlib_type.isIntFn) },
    .{ "is_float", @ptrCast(&stdlib_type.isFloatFn) },
    .{ "is_double", @ptrCast(&stdlib_type.isFloatFn) },
    .{ "is_string", @ptrCast(&stdlib_type.isStringFn) },
    .{ "is_array", @ptrCast(&stdlib_type.isArrayFn) },
    .{ "is_object", @ptrCast(&stdlib_type.isObjectFn) },
    .{ "is_numeric", @ptrCast(&stdlib_type.isNumericFn) },
    .{ "is_scalar", @ptrCast(&stdlib_type.isScalarFn) },
    .{ "is_resource", @ptrCast(&stdlib_type.isResourceFn) },
    .{ "intval", @ptrCast(&stdlib_type.intvalFn) },
    .{ "floatval", @ptrCast(&stdlib_type.floatvalFn) },
    .{ "strval", @ptrCast(&stdlib_type.strvalFn) },
    .{ "boolval", @ptrCast(&stdlib_type.boolvalFn) },

    // ========================================================================
    // Debug/Misc Functions (stdlib_misc)
    // ========================================================================
    .{ "var_dump", @ptrCast(&stdlib_misc.varDumpFn) },
    .{ "print_r", @ptrCast(&stdlib_misc.printRFn) },
    .{ "var_export", @ptrCast(&stdlib_misc.varExportFn) },
    .{ "header", @ptrCast(&stdlib_misc.headerFn) },
    .{ "http_response_code", @ptrCast(&stdlib_misc.httpResponseCodeFn) },
    .{ "exit", @ptrCast(&stdlib_misc.exitFn) },
    .{ "die", @ptrCast(&stdlib_misc.exitFn) },
    .{ "mb_strlen", @ptrCast(&stdlib_misc.mbStrlenFn) },
    .{ "mb_substr", @ptrCast(&stdlib_misc.mbSubstrFn) },
    .{ "mb_strtolower", @ptrCast(&stdlib_misc.mbStrtolowerFn) },
    .{ "mb_strtoupper", @ptrCast(&stdlib_misc.mbStrtoupperFn) },
    .{ "mb_detect_encoding", @ptrCast(&stdlib_misc.mbDetectEncodingFn) },

    // ========================================================================
    // Variable/Class/Config Functions (builtin_vars)
    // ========================================================================
    .{ "empty", @ptrCast(&builtin_vars.emptyFn) },
    .{ "unset", @ptrCast(&builtin_vars.unsetFn) },
    .{ "is_callable", @ptrCast(&builtin_vars.isCallableFn) },
    .{ "call_user_func", @ptrCast(&builtin_vars.callUserFuncFn) },
    .{ "call_user_func_array", @ptrCast(&builtin_vars.callUserFuncArrayFn) },
    .{ "class_exists", @ptrCast(&builtin_vars.classExistsFn) },
    .{ "interface_exists", @ptrCast(&builtin_vars.interfaceExistsFn) },
    .{ "trait_exists", @ptrCast(&builtin_vars.traitExistsFn) },
    .{ "method_exists", @ptrCast(&builtin_vars.methodExistsFn) },
    .{ "property_exists", @ptrCast(&builtin_vars.propertyExistsFn) },
    .{ "is_a", @ptrCast(&builtin_vars.isAFn) },
    .{ "is_subclass_of", @ptrCast(&builtin_vars.isSubclassOfFn) },
    .{ "get_class", @ptrCast(&builtin_vars.getClassFn) },
    .{ "get_parent_class", @ptrCast(&builtin_vars.getParentClassFn) },
    .{ "get_class_methods", @ptrCast(&builtin_vars.getClassMethodsFn) },
    .{ "ini_get", @ptrCast(&builtin_vars.iniGetFn) },
    .{ "ini_set", @ptrCast(&builtin_vars.iniSetFn) },
    .{ "ini_restore", @ptrCast(&builtin_vars.iniRestoreFn) },
    .{ "error_reporting", @ptrCast(&builtin_vars.errorReportingFn) },
    .{ "trigger_error", @ptrCast(&builtin_vars.triggerErrorFn) },
    .{ "user_error", @ptrCast(&builtin_vars.userErrorFn) },
    .{ "define", @ptrCast(&builtin_vars.defineFn) },
    .{ "defined", @ptrCast(&builtin_vars.definedFn) },
    .{ "set_error_handler", @ptrCast(&builtin_vars.setErrorHandlerFn) },
    .{ "set_exception_handler", @ptrCast(&builtin_vars.setExceptionHandlerFn) },
    .{ "error_get_last", @ptrCast(&builtin_vars.errorGetLastFn) },
    .{ "parse_url", @ptrCast(&builtin_vars.parseUrlFn) },
    .{ "get_defined_vars", @ptrCast(&builtin_vars.getDefinedVarsFn) },
    .{ "get_defined_functions", @ptrCast(&builtin_vars.getDefinedFunctionsFn) },
    .{ "get_defined_constants", @ptrCast(&builtin_vars.getDefinedConstantsFn) },
    .{ "get_declared_classes", @ptrCast(&builtin_vars.getDeclaredClassesFn) },
    .{ "register_shutdown_function", @ptrCast(&builtin_vars.registerShutdownFunctionFn) },
    .{ "register_tick_function", @ptrCast(&builtin_vars.registerTickFunctionFn) },
    .{ "unregister_tick_function", @ptrCast(&builtin_vars.unregisterTickFunctionFn) },
    .{ "func_num_args", @ptrCast(&builtin_vars.funcNumArgsFn) },
    .{ "func_get_arg", @ptrCast(&builtin_vars.funcGetArgFn) },
    .{ "func_get_args", @ptrCast(&builtin_vars.funcGetArgsFn) },
    .{ "strtr", @ptrCast(&builtin_vars.strtrFn) },
    .{ "http_build_query", @ptrCast(&builtin_vars.httpBuildQueryFn) },
    .{ "get_loaded_extensions", @ptrCast(&builtin_vars.getLoadedExtensionsFn) },
    .{ "extension_loaded", @ptrCast(&builtin_vars.extensionLoadedFn) },

    // ========================================================================
    // PHP 8.5 URI Functions (php85_features)
    // ========================================================================
    .{ "uri_parse", @ptrCast(&php85_features.uriParseFn) },
    .{ "uri_build", @ptrCast(&php85_features.uriBuildFn) },
    .{ "uri_resolve", @ptrCast(&php85_features.uriResolveFn) },
};

/// 编译时生成的名称 → handler 查找表
/// 使用 StaticStringMap 实现高效 O(1) 查找
const HANDLER_NAME_MAP = std.StaticStringMap(BuiltinHandler).initComptime(HANDLER_MAP_KVS);

/// comptime 生成的 handler 表 — 索引与 FN_TABLE 一一对应
/// null 表示该函数尚未实现 handler
pub const COMPTIME_HANDLER_TABLE: [BUILTIN_COUNT]?BuiltinHandler = blk: {
    @setEvalBranchQuota(fn_table.FN_TABLE.len * HANDLER_MAP_KVS.len * 4 + 50000);
    var table: [BUILTIN_COUNT]?BuiltinHandler = .{null} ** BUILTIN_COUNT;
    for (fn_table.FN_TABLE, 0..) |entry, i| {
        table[i] = HANDLER_NAME_MAP.get(entry.name);
    }
    break :blk table;
};

/// 通过 BuiltinId 直接调用 handler — O(1) 分发
/// vm_ptr: *anyopaque 类型，调用方需 @ptrCast 传入 *VM
/// 返回 null 表示该函数未注册 handler 或 BuiltinId 无效
pub fn dispatch(vm_ptr: *anyopaque, id: BuiltinId, args: []const Value) anyerror!?Value {
    if (id >= BUILTIN_COUNT) return null;
    const handler = COMPTIME_HANDLER_TABLE[id] orelse return null;
    const result = try handler(vm_ptr, args);
    return result;
}

/// 检查 handler 是否已注册（comptime 版本）
pub fn isHandlerRegistered(id: BuiltinId) bool {
    if (id >= BUILTIN_COUNT) return false;
    return COMPTIME_HANDLER_TABLE[id] != null;
}

/// 获取已注册的 handler 数量（comptime 版本）
pub fn registeredHandlerCount() usize {
    comptime {
        var count: usize = 0;
        for (COMPTIME_HANDLER_TABLE) |h| {
            if (h != null) count += 1;
        }
        return count;
    }
}

// 编译时验证：HANDLER_MAP_KVS 中不应有重复的函数名
comptime {
    @setEvalBranchQuota(HANDLER_MAP_KVS.len * HANDLER_MAP_KVS.len * 4 + 2000);
    for (HANDLER_MAP_KVS, 0..) |entry, i| {
        for (HANDLER_MAP_KVS, 0..) |other, j| {
            if (i != j and std.mem.eql(u8, entry.@"0", other.@"0")) {
                @compileError("Duplicate handler name in HANDLER_MAP_KVS: " ++ entry.@"0");
            }
        }
    }
}

// ============================================================================
// 7. 兼容层 — 重导出旧接口
// ============================================================================

/// 兼容旧 builtin_dispatch.zig 的 lookupBuiltin 接口
/// 如果找到内置函数，返回函数名字符串
pub fn lookupBuiltin(name: []const u8) ?[]const u8 {
    if (lookup(name)) |id| {
        return META_TABLE[id].name;
    }
    return null;
}

/// 兼容旧 builtin_dispatch.zig 的 FastBuiltins
/// 高频函数的内联版本，直接在此实现以避免循环依赖
pub const FastBuiltins = struct {
    /// strlen - 内联版本
    pub inline fn strlen_fast(str: *types.PHPString) usize {
        return str.length;
    }

    /// count - 内联版本
    pub inline fn count_fast(arr: *types.PHPArray) usize {
        return arr.count();
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
// 8. 统计信息
// ============================================================================

/// 分发表统计
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
// 9. 编译时验证
// ============================================================================

comptime {
    // 确保 META_TABLE 长度与 FN_TABLE 长度一致
    if (META_TABLE.len != fn_table.FN_TABLE.len) {
        @compileError("META_TABLE length mismatch with FN_TABLE");
    }
}

// ============================================================================
// Tests
// ============================================================================

test "BuiltinId type and count" {
    const testing = std.testing;

    // BuiltinId 是 u16
    try testing.expectEqual(@as(usize, 2), @sizeOf(BuiltinId));

    // BUILTIN_COUNT 等于 FN_TABLE 长度
    try testing.expectEqual(@as(usize, fn_table.FN_TABLE.len), BUILTIN_COUNT);
}

test "META_TABLE metadata correctness" {
    const testing = std.testing;

    // META_TABLE 长度应等于 FN_TABLE 长度
    try testing.expectEqual(@as(usize, fn_table.FN_TABLE.len), META_TABLE.len);

    // 验证第一个条目（array_map）
    try testing.expectEqualStrings("array_map", META_TABLE[0].name);
    try testing.expectEqual(@as(u8, 2), META_TABLE[0].min_args);
    try testing.expectEqual(@as(u8, 255), META_TABLE[0].max_args);
    try testing.expect(META_TABLE[0].category == .array);
    try testing.expectEqual(@as(BuiltinId, 0), META_TABLE[0].id);

    // 验证 strlen 条目
    const strlen_id = lookup("strlen").?;
    const strlen_meta = getMeta(strlen_id).?;
    try testing.expectEqualStrings("strlen", strlen_meta.name);
    try testing.expectEqual(@as(u8, 1), strlen_meta.min_args);
    try testing.expectEqual(@as(u8, 1), strlen_meta.max_args);
    try testing.expect(strlen_meta.category == .string);

    // 验证 count 条目
    const count_id = lookup("count").?;
    const count_meta = getMeta(count_id).?;
    try testing.expectEqualStrings("count", count_meta.name);
    try testing.expectEqual(@as(u8, 1), count_meta.min_args);
    try testing.expectEqual(@as(u8, 2), count_meta.max_args);
    try testing.expect(count_meta.category == .array);
}

test "lookup function" {
    const testing = std.testing;

    // 查找存在的函数
    try testing.expect(lookup("strlen") != null);
    try testing.expect(lookup("array_map") != null);
    try testing.expect(lookup("abs") != null);
    try testing.expect(lookup("json_encode") != null);
    try testing.expect(lookup("md5") != null);

    // 查找不存在的函数
    try testing.expect(lookup("nonexistent_function") == null);
    try testing.expect(lookup("") == null);
}

test "lookup returns correct indices" {
    const testing = std.testing;

    // array_map 是 FN_TABLE[0]
    try testing.expectEqual(@as(BuiltinId, 0), lookup("array_map").?);

    // strlen 在 FN_TABLE 中的索引
    const strlen_idx = for (fn_table.FN_TABLE, 0..) |entry, i| {
        if (std.mem.eql(u8, entry.name, "strlen")) break @as(BuiltinId, @intCast(i));
    } else unreachable;
    try testing.expectEqual(strlen_idx, lookup("strlen").?);
}

test "validateArgs function" {
    const testing = std.testing;

    // strlen: min=1, max=1
    const strlen_id = lookup("strlen").?;
    try testing.expectError(ArgValidationError.TooFewArguments, validateArgs(strlen_id, 0));
    try validateArgs(strlen_id, 1); // 正好
    try testing.expectError(ArgValidationError.TooManyArguments, validateArgs(strlen_id, 2));

    // array_map: min=2, max=255 (variadic)
    const array_map_id = lookup("array_map").?;
    try testing.expectError(ArgValidationError.TooFewArguments, validateArgs(array_map_id, 1));
    try validateArgs(array_map_id, 2); // 最少
    try validateArgs(array_map_id, 100); // variadic，不检查上限

    // time: min=0, max=0
    const time_id = lookup("time").?;
    try validateArgs(time_id, 0); // 正好
    try testing.expectError(ArgValidationError.TooManyArguments, validateArgs(time_id, 1));
}

test "lookupBuiltin compatibility" {
    const testing = std.testing;

    // 兼容旧接口
    try testing.expectEqualStrings("strlen", lookupBuiltin("strlen").?);
    try testing.expectEqualStrings("array_map", lookupBuiltin("array_map").?);
    try testing.expect(lookupBuiltin("nonexistent") == null);
}

test "getMeta returns correct pointer" {
    const testing = std.testing;

    const id = lookup("abs").?;
    const meta = getMeta(id).?;
    try testing.expectEqualStrings("abs", meta.name);
    try testing.expectEqual(@as(u8, 1), meta.min_args);
    try testing.expectEqual(@as(u8, 1), meta.max_args);
    try testing.expect(meta.category == .math);

    // 验证 id 字段与查找值一致
    try testing.expectEqual(id, meta.id);

    // 无效 ID 返回 null
    try testing.expect(getMeta(INVALID_BUILTIN_ID) == null);
}

test "META_TABLE and FN_TABLE alignment" {
    const testing = std.testing;

    // 验证 META_TABLE[i] 与 FN_TABLE[i] 一致
    for (META_TABLE, 0..) |meta, i| {
        try testing.expectEqual(@as(BuiltinId, @intCast(i)), meta.id);
        try testing.expectEqualStrings(fn_table.FN_TABLE[i].name, meta.name);
        try testing.expectEqual(fn_table.FN_TABLE[i].min_args, meta.min_args);
        try testing.expectEqual(fn_table.FN_TABLE[i].max_args, meta.max_args);
        try testing.expect(fn_table.FN_TABLE[i].category == meta.category);
    }
}

test "FastBuiltins inline functions" {
    const testing = std.testing;

    // 测试 empty_fast
    const null_val = Value.initNull();
    try testing.expect(FastBuiltins.empty_fast(null_val));

    const int_zero = Value.initInt(0);
    try testing.expect(FastBuiltins.empty_fast(int_zero));

    const int_nonzero = Value.initInt(42);
    try testing.expect(!FastBuiltins.empty_fast(int_nonzero));

    // 测试 isset_fast
    try testing.expect(!FastBuiltins.isset_fast(null_val));
    try testing.expect(FastBuiltins.isset_fast(int_nonzero));
}

test "DispatchStats" {
    const testing = std.testing;

    var stats = DispatchStats{};
    try testing.expectEqual(@as(u64, 0), stats.total_calls);
    try testing.expectEqual(@as(f64, 0.0), stats.hitRate());

    stats.recordCall(true);
    stats.recordCall(true);
    stats.recordCall(false);
    try testing.expectEqual(@as(u64, 3), stats.total_calls);
    try testing.expectEqual(@as(u64, 2), stats.cache_hits);
    try testing.expectEqual(@as(u64, 1), stats.cache_misses);

    const rate = stats.hitRate();
    try testing.expect(rate > 0.65 and rate < 0.69); // 2/3 ≈ 0.667
}

test "COMPTIME_HANDLER_TABLE correctness" {
    const testing = std.testing;

    // COMPTIME_HANDLER_TABLE 长度应等于 BUILTIN_COUNT
    try testing.expectEqual(@as(usize, BUILTIN_COUNT), COMPTIME_HANDLER_TABLE.len);

    // strlen 应该有 handler（来自 stdlib_string）
    const strlen_id = lookup("strlen").?;
    try testing.expect(isHandlerRegistered(strlen_id));

    // array_map 应该有 handler（来自 stdlib_array）
    const array_map_id = lookup("array_map").?;
    try testing.expect(isHandlerRegistered(array_map_id));

    // count 应该有 handler（来自 stdlib_array）
    const count_id = lookup("count").?;
    try testing.expect(isHandlerRegistered(count_id));

    // abs 应该有 handler（来自 stdlib_math）
    const abs_id = lookup("abs").?;
    try testing.expect(isHandlerRegistered(abs_id));

    // 已注册的 handler 数量应大于 0
    try testing.expect(registeredHandlerCount() > 0);

    // HANDLER_MAP_KVS 中不应有重复
    // （comptime 验证已覆盖此检查）
}

test "dispatch with comptime handler table" {
    const testing = std.testing;

    // dispatch 未注册的 handler（无效 ID）应返回 null
    const result1 = dispatch(undefined, INVALID_BUILTIN_ID, &.{});
    try testing.expect(result1 == null);

    // 超出范围的 ID 应返回 null
    const result2 = dispatch(undefined, @intCast(BUILTIN_COUNT), &.{});
    try testing.expect(result2 == null);
}

test "HANDLER_MAP_KVS no duplicates" {
    const testing = std.testing;

    // 验证 HANDLER_MAP_KVS 中没有重复的函数名
    // comptime 验证已覆盖此检查，但运行时测试也验证
    for (HANDLER_MAP_KVS, 0..) |entry, i| {
        for (HANDLER_MAP_KVS, 0..) |other, j| {
            if (i != j) {
                try testing.expect(!std.mem.eql(u8, entry.@"0", other.@"0"));
            }
        }
    }
}

test "COMPTIME_HANDLER_TABLE alignment with FN_TABLE" {
    const testing = std.testing;

    // 验证 COMPTIME_HANDLER_TABLE 中的 handler 与 FN_TABLE 对齐
    // 对于每个有 handler 的条目，其名称应与 FN_TABLE 中的名称一致
    for (COMPTIME_HANDLER_TABLE, 0..) |handler_opt, i| {
        if (handler_opt) |_| {
            // 该函数有 handler，验证 FN_TABLE 中有对应条目
            try testing.expect(fn_table.FN_TABLE[i].name.len > 0);
        }
    }
}

test "registeredHandlerCount matches HANDLER_MAP_KVS" {
    const testing = std.testing;

    // 已注册的 handler 数量应等于 HANDLER_MAP_KVS 的长度
    // （前提：HANDLER_MAP_KVS 中的所有函数名都在 FN_TABLE 中）
    try testing.expectEqual(@as(usize, HANDLER_MAP_KVS.len), registeredHandlerCount());
}
