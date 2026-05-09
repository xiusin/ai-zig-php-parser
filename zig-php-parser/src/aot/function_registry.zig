//! Function Registry - 统一函数注册表（单一真相源）
//!
//! 本模块为 AOT 编译器提供所有 builtin/stdlib 函数的统一元数据注册表。
//! 替代原先分散在 native_linker.zig 和 runtime_lib_template.zig 中的多套映射表。
//!
//! ## 设计目标
//! - 单一真相源：AOT/VM 两侧共享同一份函数元数据
//! - 高性能分发：编译期 StaticStringMap + FunctionId 索引，零运行时字符串比较
//! - 可扩展性：新增函数只需在此注册，无需修改代码生成器
//! - 模块化：按功能分类（Category），支持 feature flags 裁剪
//!
//! ## 核心抽象
//! - FunctionId: u16 稳定 ID，按模块/域分段
//! - FunctionMeta: 签名元数据（arity、ref_params、allocator、pure 等）
//! - Category: 函数分类（array/string/math/io/json/...）
//!
//! @thread-safety ISOLATED (comptime only)
//! @ownership NON-OWNING

const std = @import("std");

/// 函数分类枚举 - 支持 feature flags 裁剪
pub const Category = enum(u8) {
    output, // echo, print, var_dump, print_r
    string, // strlen, substr, strpos, ...
    array, // count, array_push, array_pop, ...
    math, // abs, sqrt, round, ...
    type_check, // is_null, is_int, is_string, ...
    type_cast, // intval, floatval, strval, ...
    json, // json_encode, json_decode, ...
    regex, // preg_match, preg_replace, ...
    file, // file_get_contents, fopen, ...
    time, // time, date, microtime, ...
    hash, // md5, sha1, hash, ...
    encoding, // base64_encode, urlencode, ...
    sort, // sort, rsort, usort, ...
    callback, // call_user_func, array_map, ...
    object, // get_class, class_exists, ...
    error_handling, // set_error_handler, trigger_error, ...
    system, // getenv, shell_exec, ...
    network, // gethostbyname, parse_url, ...
    ctype, // ctype_alnum, ctype_alpha, ...
    mbstring, // mb_strlen, mb_substr, ...
    process, // pcntl_fork, posix_getpid, ...
    gc, // gc_enable, gc_collect_cycles, ...
    reflection, // get_class_methods, get_object_vars, ...
    internal, // php_concat, php_array_iter_*, ...
    misc, // define, constant, function_exists, ...
};

/// 函数元数据
pub const FunctionMeta = struct {
    /// PHP 函数名
    php_name: []const u8,
    /// 运行时实现函数名（Zig 侧）
    runtime_name: []const u8,
    /// 是否需要 allocator 参数
    needs_allocator: bool = false,
    /// 是否可能抛出异常/错误
    may_raise: bool = true,
    /// 引用参数索引列表（0-based）
    ref_params: []const u8 = &[_]u8{},
    /// 函数分类
    category: Category = .misc,
    /// 是否为纯函数（无副作用，可用于常量折叠）
    is_pure: bool = false,
    /// 最少参数个数
    min_arity: u8 = 0,
    /// 最大参数个数（255 = variadic）
    max_arity: u8 = 255,
    /// 是否为语句函数（返回值通常被忽略）
    is_statement: bool = false,
};

/// FunctionId 类型 - u16 提供最多 65536 个函数 ID
pub const FunctionId = u16;

/// 无效函数 ID（表示动态调用 / 未解析）
pub const INVALID_FUNCTION_ID: FunctionId = 0;

// ============================================================
// 编译期函数注册表数据
// ============================================================

/// 所有 builtin 函数的注册表（comptime 数组）
/// 索引即为 FunctionId（从 1 开始，0 保留为 INVALID）
pub const registry = [_]FunctionMeta{
    // ===== ID 0: 保留（INVALID） =====
    .{ .php_name = "__invalid__", .runtime_name = "__invalid__", .category = .misc },

    // ===== Output 函数 (ID 1-4) =====
    .{ .php_name = "echo", .runtime_name = "php_echo", .category = .output, .is_statement = true },
    .{ .php_name = "print", .runtime_name = "php_print", .category = .output },
    .{ .php_name = "var_dump", .runtime_name = "php_var_dump", .category = .output, .is_statement = true },
    .{ .php_name = "print_r", .runtime_name = "print_r", .category = .output, .is_statement = true },
    .{ .php_name = "var_export", .runtime_name = "var_export", .category = .output },

    // ===== String 函数 (ID 6-) =====
    .{ .php_name = "strlen", .runtime_name = "php_strlen", .category = .string, .is_pure = true, .min_arity = 1, .max_arity = 1 },
    .{ .php_name = "substr", .runtime_name = "php_substr", .needs_allocator = true, .category = .string, .min_arity = 2, .max_arity = 3 },
    .{ .php_name = "strpos", .runtime_name = "php_strpos", .category = .string, .min_arity = 2, .max_arity = 3 },
    .{ .php_name = "strtoupper", .runtime_name = "php_strtoupper", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "strtolower", .runtime_name = "php_strtolower", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "trim", .runtime_name = "php_trim", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "ltrim", .runtime_name = "php_ltrim", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "rtrim", .runtime_name = "php_rtrim", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "str_replace", .runtime_name = "php_str_replace", .needs_allocator = true, .category = .string, .ref_params = &[_]u8{3} },
    .{ .php_name = "str_ireplace", .runtime_name = "php_str_ireplace", .needs_allocator = true, .category = .string, .ref_params = &[_]u8{3} },
    .{ .php_name = "str_repeat", .runtime_name = "php_str_repeat", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "str_pad", .runtime_name = "php_str_pad", .needs_allocator = true, .category = .string },
    .{ .php_name = "strstr", .runtime_name = "php_strstr", .needs_allocator = true, .category = .string },
    .{ .php_name = "stristr", .runtime_name = "php_stristr", .needs_allocator = true, .category = .string },
    .{ .php_name = "strrchr", .runtime_name = "php_strrchr", .needs_allocator = true, .category = .string },
    .{ .php_name = "strnatcmp", .runtime_name = "php_strnatcmp", .category = .string, .is_pure = true },
    .{ .php_name = "strnatcasecmp", .runtime_name = "php_strnatcasecmp", .category = .string, .is_pure = true },
    .{ .php_name = "strchr", .runtime_name = "php_strstr", .needs_allocator = true, .category = .string }, // alias
    .{ .php_name = "strrev", .runtime_name = "php_strrev", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "str_shuffle", .runtime_name = "php_str_shuffle", .needs_allocator = true, .category = .string },
    .{ .php_name = "str_contains", .runtime_name = "php_str_contains", .category = .string, .is_pure = true },
    .{ .php_name = "str_starts_with", .runtime_name = "php_str_starts_with", .category = .string, .is_pure = true },
    .{ .php_name = "str_ends_with", .runtime_name = "php_str_ends_with", .category = .string, .is_pure = true },
    .{ .php_name = "str_word_count", .runtime_name = "php_str_word_count", .category = .string },
    .{ .php_name = "count_chars", .runtime_name = "php_count_chars", .needs_allocator = true, .category = .string },
    .{ .php_name = "ucfirst", .runtime_name = "php_ucfirst", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "lcfirst", .runtime_name = "php_lcfirst", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "ucwords", .runtime_name = "php_ucwords", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "explode", .runtime_name = "php_explode", .needs_allocator = true, .category = .string },
    .{ .php_name = "implode", .runtime_name = "php_implode", .needs_allocator = true, .category = .string },
    .{ .php_name = "join", .runtime_name = "php_implode", .needs_allocator = true, .category = .string }, // alias
    .{ .php_name = "str_getcsv", .runtime_name = "php_str_getcsv", .needs_allocator = true, .category = .string },
    .{ .php_name = "str_split", .runtime_name = "php_str_split", .needs_allocator = true, .category = .string },
    .{ .php_name = "strcmp", .runtime_name = "php_strcmp", .category = .string, .is_pure = true },
    .{ .php_name = "strcasecmp", .runtime_name = "php_strcasecmp", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "strncasecmp", .runtime_name = "php_strncasecmp", .category = .string, .is_pure = true },
    .{ .php_name = "stripos", .runtime_name = "php_stripos", .category = .string },
    .{ .php_name = "strrpos", .runtime_name = "php_strrpos", .category = .string },
    .{ .php_name = "strripos", .runtime_name = "php_strripos", .category = .string },
    .{ .php_name = "sprintf", .runtime_name = "php_sprintf", .needs_allocator = true, .category = .string },
    .{ .php_name = "vsprintf", .runtime_name = "php_vsprintf", .needs_allocator = true, .category = .string },
    .{ .php_name = "sscanf", .runtime_name = "php_sscanf", .needs_allocator = true, .category = .string },
    .{ .php_name = "printf", .runtime_name = "php_printf", .needs_allocator = true, .category = .string },
    .{ .php_name = "chunk_split", .runtime_name = "php_chunk_split", .needs_allocator = true, .category = .string },
    .{ .php_name = "wordwrap", .runtime_name = "php_wordwrap", .needs_allocator = true, .category = .string },
    .{ .php_name = "nl2br", .runtime_name = "php_nl2br", .needs_allocator = true, .category = .string },
    .{ .php_name = "strip_tags", .runtime_name = "php_strip_tags", .needs_allocator = true, .category = .string },
    .{ .php_name = "htmlspecialchars", .runtime_name = "php_htmlspecialchars", .needs_allocator = true, .category = .string },
    .{ .php_name = "htmlentities", .runtime_name = "php_htmlentities", .needs_allocator = true, .category = .string },
    .{ .php_name = "htmlspecialchars_decode", .runtime_name = "php_htmlspecialchars_decode", .needs_allocator = true, .category = .string },
    .{ .php_name = "number_format", .runtime_name = "php_number_format", .needs_allocator = true, .category = .string },
    .{ .php_name = "addslashes", .runtime_name = "php_addslashes", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "stripslashes", .runtime_name = "php_stripslashes", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "substr_count", .runtime_name = "php_substr_count", .category = .string, .is_pure = true },
    .{ .php_name = "substr_replace", .runtime_name = "php_substr_replace", .needs_allocator = true, .category = .string, .may_raise = false },
    .{ .php_name = "crc32", .runtime_name = "php_crc32", .category = .string, .is_pure = true },
    .{ .php_name = "ord", .runtime_name = "php_ord", .category = .string, .is_pure = true },
    .{ .php_name = "chr", .runtime_name = "php_chr", .needs_allocator = true, .category = .string, .is_pure = true },
    .{ .php_name = "filter_var", .runtime_name = "php_filter_var", .needs_allocator = true, .category = .string },

    // ===== Encoding 函数 =====
    .{ .php_name = "bin2hex", .runtime_name = "php_bin2hex", .needs_allocator = true, .category = .encoding, .is_pure = true },
    .{ .php_name = "hex2bin", .runtime_name = "php_hex2bin", .needs_allocator = true, .category = .encoding, .is_pure = true },
    .{ .php_name = "base64_encode", .runtime_name = "php_base64_encode", .needs_allocator = true, .category = .encoding, .is_pure = true },
    .{ .php_name = "base64_decode", .runtime_name = "php_base64_decode", .needs_allocator = true, .category = .encoding, .is_pure = true },
    .{ .php_name = "urlencode", .runtime_name = "php_urlencode", .needs_allocator = true, .category = .encoding, .is_pure = true },
    .{ .php_name = "urldecode", .runtime_name = "php_urldecode", .needs_allocator = true, .category = .encoding, .is_pure = true },
    .{ .php_name = "rawurlencode", .runtime_name = "php_rawurlencode", .needs_allocator = true, .category = .encoding, .is_pure = true },
    .{ .php_name = "rawurldecode", .runtime_name = "php_rawurldecode", .needs_allocator = true, .category = .encoding, .is_pure = true },

    // ===== Hash 函数 =====
    .{ .php_name = "md5", .runtime_name = "php_md5", .needs_allocator = true, .category = .hash, .is_pure = true },
    .{ .php_name = "sha1", .runtime_name = "php_sha1", .needs_allocator = true, .category = .hash, .is_pure = true },
    .{ .php_name = "hash", .runtime_name = "php_hash", .needs_allocator = true, .category = .hash },
    .{ .php_name = "hash_hmac", .runtime_name = "php_hash_hmac", .needs_allocator = true, .category = .hash },
    .{ .php_name = "hash_equals", .runtime_name = "php_hash_equals", .category = .hash, .is_pure = true },
    .{ .php_name = "hash_algos", .runtime_name = "php_hash_algos", .needs_allocator = true, .category = .hash },
    .{ .php_name = "hash_file", .runtime_name = "php_hash_file", .needs_allocator = true, .category = .hash },
    .{ .php_name = "password_hash", .runtime_name = "php_password_hash", .needs_allocator = true, .category = .hash },
    .{ .php_name = "password_verify", .runtime_name = "php_password_verify", .needs_allocator = true, .category = .hash },
    .{ .php_name = "password_get_info", .runtime_name = "php_password_get_info", .needs_allocator = true, .category = .hash },
    .{ .php_name = "password_needs_rehash", .runtime_name = "php_password_needs_rehash", .needs_allocator = true, .category = .hash },
    .{ .php_name = "uniqid", .runtime_name = "php_uniqid", .needs_allocator = true, .category = .hash },

    // ===== Array 函数 =====
    .{ .php_name = "count", .runtime_name = "php_count", .category = .array, .is_pure = true },
    .{ .php_name = "sizeof", .runtime_name = "php_sizeof", .category = .array, .is_pure = true },
    .{ .php_name = "in_array", .runtime_name = "php_in_array", .category = .array },
    .{ .php_name = "array_key_exists", .runtime_name = "php_array_key_exists", .category = .array },
    .{ .php_name = "array_keys", .runtime_name = "php_array_keys", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_values", .runtime_name = "php_array_values", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_is_list", .runtime_name = "php_array_is_list", .category = .array, .may_raise = false, .is_pure = true },
    .{ .php_name = "array_push", .runtime_name = "php_array_push", .needs_allocator = true, .category = .array, .is_statement = true },
    .{ .php_name = "array_pop", .runtime_name = "php_array_pop", .needs_allocator = true, .category = .array, .is_statement = true },
    .{ .php_name = "array_shift", .runtime_name = "php_array_shift", .needs_allocator = true, .category = .array, .is_statement = true },
    .{ .php_name = "array_unshift", .runtime_name = "php_array_unshift", .needs_allocator = true, .category = .array, .is_statement = true },
    .{ .php_name = "array_slice", .runtime_name = "php_array_slice", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_splice", .runtime_name = "php_array_splice", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_merge", .runtime_name = "php_array_merge", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_map", .runtime_name = "php_array_map", .needs_allocator = true, .category = .callback },
    .{ .php_name = "array_filter", .runtime_name = "php_array_filter", .needs_allocator = true, .category = .callback },
    .{ .php_name = "array_reduce", .runtime_name = "php_array_reduce", .needs_allocator = true, .category = .callback },
    .{ .php_name = "array_find", .runtime_name = "php_array_find", .needs_allocator = true, .category = .callback },
    .{ .php_name = "array_find_key", .runtime_name = "php_array_find_key", .needs_allocator = true, .category = .callback },
    .{ .php_name = "array_chunk", .runtime_name = "php_array_chunk", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_column", .runtime_name = "php_array_column", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_sum", .runtime_name = "php_array_sum", .category = .array, .is_pure = true },
    .{ .php_name = "array_product", .runtime_name = "php_array_product", .category = .array, .is_pure = true },
    .{ .php_name = "array_search", .runtime_name = "php_array_search", .category = .array },
    .{ .php_name = "array_reverse", .runtime_name = "php_array_reverse", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_unique", .runtime_name = "php_array_unique", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_flip", .runtime_name = "php_array_flip", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_combine", .runtime_name = "php_array_combine", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_pad", .runtime_name = "php_array_pad", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_fill", .runtime_name = "php_array_fill", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_fill_keys", .runtime_name = "php_array_fill_keys", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_intersect", .runtime_name = "php_array_intersect", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_diff", .runtime_name = "php_array_diff", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_diff_key", .runtime_name = "php_array_diff_key", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_walk", .runtime_name = "php_array_walk", .needs_allocator = true, .category = .callback },
    .{ .php_name = "array_walk_recursive", .runtime_name = "php_array_walk_recursive", .needs_allocator = true, .category = .callback },
    .{ .php_name = "iterator_to_array", .runtime_name = "php_iterator_to_array", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_count_values", .runtime_name = "php_array_count_values", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_rand", .runtime_name = "php_array_rand", .needs_allocator = true, .category = .array },
    .{ .php_name = "array_key_first", .runtime_name = "php_array_key_first", .category = .array },
    .{ .php_name = "array_key_last", .runtime_name = "php_array_key_last", .category = .array },
    .{ .php_name = "array_multisort", .runtime_name = "php_array_multisort", .needs_allocator = true, .category = .array },
    .{ .php_name = "compact", .runtime_name = "php_compact", .needs_allocator = true, .category = .array },
    .{ .php_name = "extract", .runtime_name = "php_extract", .needs_allocator = true, .category = .array },
    .{ .php_name = "natsort", .runtime_name = "php_natsort", .needs_allocator = true, .category = .sort },
    .{ .php_name = "range", .runtime_name = "php_range", .needs_allocator = true, .category = .array },
    .{ .php_name = "current", .runtime_name = "php_current", .needs_allocator = true, .category = .array },
    .{ .php_name = "next", .runtime_name = "php_next", .needs_allocator = true, .category = .array },
    .{ .php_name = "prev", .runtime_name = "php_prev", .needs_allocator = true, .category = .array },
    .{ .php_name = "reset", .runtime_name = "php_reset", .needs_allocator = true, .category = .array },
    .{ .php_name = "end", .runtime_name = "php_end", .needs_allocator = true, .category = .array },
    .{ .php_name = "key", .runtime_name = "php_key", .needs_allocator = true, .category = .array },
    .{ .php_name = "each", .runtime_name = "php_each", .needs_allocator = true, .category = .array },
    .{ .php_name = "shuffle", .runtime_name = "php_shuffle", .needs_allocator = true, .category = .sort, .is_statement = true },

    // ===== Sort 函数 =====
    .{ .php_name = "sort", .runtime_name = "php_sort", .needs_allocator = true, .category = .sort, .is_statement = true },
    .{ .php_name = "rsort", .runtime_name = "php_rsort", .needs_allocator = true, .category = .sort, .is_statement = true },
    .{ .php_name = "asort", .runtime_name = "php_asort", .needs_allocator = true, .category = .sort, .is_statement = true },
    .{ .php_name = "arsort", .runtime_name = "php_arsort", .needs_allocator = true, .category = .sort, .is_statement = true },
    .{ .php_name = "ksort", .runtime_name = "php_ksort", .needs_allocator = true, .category = .sort, .is_statement = true },
    .{ .php_name = "krsort", .runtime_name = "php_krsort", .needs_allocator = true, .category = .sort, .is_statement = true },
    .{ .php_name = "usort", .runtime_name = "php_usort", .needs_allocator = true, .category = .sort, .is_statement = true },
    .{ .php_name = "uasort", .runtime_name = "php_uasort", .needs_allocator = true, .category = .sort, .is_statement = true },
    .{ .php_name = "uksort", .runtime_name = "php_uksort", .needs_allocator = true, .category = .sort, .is_statement = true },

    // ===== Math 函数 =====
    .{ .php_name = "abs", .runtime_name = "php_abs", .category = .math, .is_pure = true },
    .{ .php_name = "sqrt", .runtime_name = "php_sqrt", .category = .math, .is_pure = true },
    .{ .php_name = "round", .runtime_name = "php_round", .category = .math, .is_pure = true },
    .{ .php_name = "floor", .runtime_name = "php_floor", .category = .math, .is_pure = true },
    .{ .php_name = "ceil", .runtime_name = "php_ceil", .category = .math, .is_pure = true },
    .{ .php_name = "min", .runtime_name = "php_min", .category = .math },
    .{ .php_name = "max", .runtime_name = "php_max", .category = .math },
    .{ .php_name = "pow", .runtime_name = "php_pow_func", .category = .math, .is_pure = true },
    .{ .php_name = "sin", .runtime_name = "php_sin", .category = .math, .is_pure = true },
    .{ .php_name = "cos", .runtime_name = "php_cos", .category = .math, .is_pure = true },
    .{ .php_name = "tan", .runtime_name = "php_tan", .category = .math, .is_pure = true },
    .{ .php_name = "asin", .runtime_name = "php_asin", .category = .math, .is_pure = true },
    .{ .php_name = "acos", .runtime_name = "php_acos", .category = .math, .is_pure = true },
    .{ .php_name = "atan", .runtime_name = "php_atan", .category = .math, .is_pure = true },
    .{ .php_name = "atan2", .runtime_name = "php_atan2", .category = .math, .is_pure = true },
    .{ .php_name = "sinh", .runtime_name = "php_sinh", .category = .math, .is_pure = true },
    .{ .php_name = "cosh", .runtime_name = "php_cosh", .category = .math, .is_pure = true },
    .{ .php_name = "tanh", .runtime_name = "php_tanh", .category = .math, .is_pure = true },
    .{ .php_name = "log", .runtime_name = "php_log", .category = .math, .is_pure = true },
    .{ .php_name = "log10", .runtime_name = "php_log10", .category = .math, .is_pure = true },
    .{ .php_name = "log2", .runtime_name = "php_log2", .category = .math, .is_pure = true },
    .{ .php_name = "exp", .runtime_name = "php_exp", .category = .math, .is_pure = true },
    .{ .php_name = "fmod", .runtime_name = "php_fmod", .category = .math, .is_pure = true },
    .{ .php_name = "intdiv", .runtime_name = "php_intdiv", .category = .math, .is_pure = true },
    .{ .php_name = "fdiv", .runtime_name = "php_fdiv", .category = .math, .may_raise = false, .is_pure = true },
    .{ .php_name = "hypot", .runtime_name = "php_hypot", .category = .math, .is_pure = true },
    .{ .php_name = "deg2rad", .runtime_name = "php_deg2rad", .category = .math, .is_pure = true },
    .{ .php_name = "rad2deg", .runtime_name = "php_rad2deg", .category = .math, .is_pure = true },
    .{ .php_name = "pi", .runtime_name = "php_pi", .category = .math, .is_pure = true, .may_raise = false },
    .{ .php_name = "rand", .runtime_name = "php_rand", .category = .math },
    .{ .php_name = "mt_rand", .runtime_name = "php_mt_rand", .category = .math },
    .{ .php_name = "srand", .runtime_name = "php_srand", .category = .math },
    .{ .php_name = "mt_srand", .runtime_name = "php_mt_srand", .category = .math },
    .{ .php_name = "random_int", .runtime_name = "php_random_int", .category = .math },
    .{ .php_name = "random_bytes", .runtime_name = "php_random_bytes", .needs_allocator = true, .category = .math },
    .{ .php_name = "decbin", .runtime_name = "php_decbin", .needs_allocator = true, .category = .math, .is_pure = true },
    .{ .php_name = "dechex", .runtime_name = "php_dechex", .needs_allocator = true, .category = .math, .is_pure = true },
    .{ .php_name = "decoct", .runtime_name = "php_decoct", .needs_allocator = true, .category = .math, .is_pure = true },
    .{ .php_name = "bindec", .runtime_name = "php_bindec", .category = .math, .is_pure = true },
    .{ .php_name = "hexdec", .runtime_name = "php_hexdec", .category = .math, .is_pure = true },
    .{ .php_name = "octdec", .runtime_name = "php_octdec", .category = .math, .is_pure = true },
    .{ .php_name = "base_convert", .runtime_name = "php_base_convert", .needs_allocator = true, .category = .math },

    // ===== Type Check 函数 =====
    .{ .php_name = "is_null", .runtime_name = "php_is_null", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_bool", .runtime_name = "php_is_bool", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_int", .runtime_name = "php_is_int", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_float", .runtime_name = "php_is_float", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_string", .runtime_name = "php_is_string", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_array", .runtime_name = "php_is_array", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_object", .runtime_name = "php_is_object", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_numeric", .runtime_name = "php_is_numeric", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_callable", .runtime_name = "php_is_callable", .category = .type_check },
    .{ .php_name = "is_resource", .runtime_name = "php_is_resource", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_scalar", .runtime_name = "php_is_scalar", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_infinite", .runtime_name = "php_is_infinite", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_nan", .runtime_name = "php_is_nan", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_finite", .runtime_name = "php_is_finite", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_countable", .runtime_name = "php_is_countable", .category = .type_check, .is_pure = true },
    .{ .php_name = "is_iterable", .runtime_name = "php_is_iterable", .category = .type_check, .is_pure = true },
    .{ .php_name = "isset", .runtime_name = "php_isset", .category = .type_check },
    .{ .php_name = "empty", .runtime_name = "php_empty", .category = .type_check },
    .{ .php_name = "is_subclass_of", .runtime_name = "php_is_subclass_of", .category = .type_check },

    // ===== Type Cast 函数 =====
    .{ .php_name = "intval", .runtime_name = "php_intval", .category = .type_cast, .is_pure = true },
    .{ .php_name = "floatval", .runtime_name = "php_floatval", .category = .type_cast, .is_pure = true },
    .{ .php_name = "strval", .runtime_name = "php_strval", .needs_allocator = true, .category = .type_cast },
    .{ .php_name = "boolval", .runtime_name = "php_boolval", .category = .type_cast, .is_pure = true },
    .{ .php_name = "gettype", .runtime_name = "php_gettype", .needs_allocator = true, .category = .type_cast },
    .{ .php_name = "settype", .runtime_name = "php_settype", .needs_allocator = true, .category = .type_cast, .may_raise = false, .ref_params = &[_]u8{0} },
    .{ .php_name = "unset", .runtime_name = "php_unset", .needs_allocator = true, .category = .type_cast, .may_raise = false, .is_statement = true },

    // ===== JSON 函数 =====
    .{ .php_name = "json_encode", .runtime_name = "php_json_encode", .needs_allocator = true, .category = .json },
    .{ .php_name = "json_decode", .runtime_name = "php_json_decode", .needs_allocator = true, .category = .json },
    .{ .php_name = "json_last_error", .runtime_name = "php_json_last_error", .category = .json, .may_raise = false },
    .{ .php_name = "json_last_error_msg", .runtime_name = "php_json_last_error_msg", .needs_allocator = true, .category = .json, .may_raise = false },
    .{ .php_name = "serialize", .runtime_name = "php_serialize", .needs_allocator = true, .category = .json },
    .{ .php_name = "unserialize", .runtime_name = "php_unserialize", .needs_allocator = true, .category = .json },

    // ===== Regex 函数 =====
    .{ .php_name = "preg_match", .runtime_name = "php_preg_match", .needs_allocator = true, .category = .regex },
    .{ .php_name = "preg_match_with_matches", .runtime_name = "preg_match_with_matches", .needs_allocator = true, .category = .regex },
    .{ .php_name = "preg_match_all", .runtime_name = "php_preg_match_all", .needs_allocator = true, .category = .regex },
    .{ .php_name = "preg_replace", .runtime_name = "preg_replace", .needs_allocator = true, .category = .regex },
    .{ .php_name = "preg_filter", .runtime_name = "preg_filter", .needs_allocator = true, .category = .regex },
    .{ .php_name = "preg_replace_callback", .runtime_name = "php_preg_replace_callback", .needs_allocator = true, .category = .regex },
    .{ .php_name = "preg_split", .runtime_name = "php_preg_split", .needs_allocator = true, .category = .regex },
    .{ .php_name = "preg_grep", .runtime_name = "preg_grep", .needs_allocator = true, .category = .regex },
    .{ .php_name = "preg_quote", .runtime_name = "preg_quote", .needs_allocator = true, .category = .regex, .is_pure = true },
    .{ .php_name = "preg_last_error", .runtime_name = "preg_last_error", .category = .regex, .may_raise = false },

    // ===== File 函数 =====
    .{ .php_name = "file_get_contents", .runtime_name = "php_file_get_contents", .needs_allocator = true, .category = .file },
    .{ .php_name = "file_put_contents", .runtime_name = "php_file_put_contents", .needs_allocator = true, .category = .file },
    .{ .php_name = "file_exists", .runtime_name = "php_file_exists", .category = .file },
    .{ .php_name = "is_file", .runtime_name = "php_is_file", .category = .file },
    .{ .php_name = "is_dir", .runtime_name = "php_is_dir", .category = .file },
    .{ .php_name = "is_readable", .runtime_name = "php_is_readable", .category = .file },
    .{ .php_name = "is_writable", .runtime_name = "php_is_writable", .category = .file },
    .{ .php_name = "filesize", .runtime_name = "php_filesize", .category = .file },
    .{ .php_name = "unlink", .runtime_name = "php_unlink", .category = .file },
    .{ .php_name = "rename", .runtime_name = "php_rename", .category = .file },
    .{ .php_name = "copy", .runtime_name = "php_copy", .category = .file },
    .{ .php_name = "mkdir", .runtime_name = "php_mkdir", .category = .file },
    .{ .php_name = "rmdir", .runtime_name = "php_rmdir", .category = .file },
    .{ .php_name = "basename", .runtime_name = "php_basename", .needs_allocator = true, .category = .file },
    .{ .php_name = "dirname", .runtime_name = "php_dirname", .needs_allocator = true, .category = .file },
    .{ .php_name = "fopen", .runtime_name = "php_fopen", .needs_allocator = true, .category = .file },
    .{ .php_name = "fwrite", .runtime_name = "php_fwrite", .needs_allocator = true, .category = .file },
    .{ .php_name = "fread", .runtime_name = "php_fread", .needs_allocator = true, .category = .file },
    .{ .php_name = "fclose", .runtime_name = "php_fclose", .category = .file },
    .{ .php_name = "fgets", .runtime_name = "php_fgets", .category = .file },
    .{ .php_name = "fseek", .runtime_name = "php_fseek", .category = .file },
    .{ .php_name = "rewind", .runtime_name = "php_rewind", .category = .file },
    .{ .php_name = "scandir", .runtime_name = "php_scandir", .needs_allocator = true, .category = .file },
    .{ .php_name = "file", .runtime_name = "php_file", .needs_allocator = true, .category = .file },
    .{ .php_name = "sys_get_temp_dir", .runtime_name = "php_sys_get_temp_dir", .needs_allocator = true, .category = .file },
    .{ .php_name = "getcwd", .runtime_name = "php_getcwd", .needs_allocator = true, .category = .file },
    .{ .php_name = "glob", .runtime_name = "php_glob", .needs_allocator = true, .category = .file },
    .{ .php_name = "touch", .runtime_name = "php_touch", .category = .file },
    .{ .php_name = "pathinfo", .runtime_name = "php_pathinfo", .category = .file },
    .{ .php_name = "realpath", .runtime_name = "php_realpath", .needs_allocator = true, .category = .file },
    .{ .php_name = "tempnam", .runtime_name = "php_tempnam", .needs_allocator = true, .category = .file },
    .{ .php_name = "filemtime", .runtime_name = "php_filemtime", .category = .file },
    .{ .php_name = "fileatime", .runtime_name = "php_fileatime", .category = .file },

    // ===== Time 函数 =====
    .{ .php_name = "time", .runtime_name = "php_time", .category = .time, .may_raise = false },
    .{ .php_name = "getdate", .runtime_name = "php_getdate", .needs_allocator = true, .category = .time },
    .{ .php_name = "idate", .runtime_name = "php_idate", .needs_allocator = true, .category = .time },
    .{ .php_name = "mktime", .runtime_name = "php_mktime", .category = .time, .may_raise = false },
    .{ .php_name = "checkdate", .runtime_name = "php_checkdate", .category = .time, .may_raise = false, .is_pure = true },
    .{ .php_name = "gmdate", .runtime_name = "php_gmdate", .needs_allocator = true, .category = .time },
    .{ .php_name = "microtime", .runtime_name = "php_microtime", .needs_allocator = true, .category = .time },
    .{ .php_name = "date", .runtime_name = "php_date", .needs_allocator = true, .category = .time },
    .{ .php_name = "strtotime", .runtime_name = "php_strtotime", .needs_allocator = true, .category = .time },
    .{ .php_name = "sleep", .runtime_name = "php_sleep", .category = .time },
    .{ .php_name = "usleep", .runtime_name = "php_usleep", .category = .time },

    // ===== Object/Class 函数 =====
    .{ .php_name = "class_exists", .runtime_name = "php_class_exists", .needs_allocator = true, .category = .object },
    .{ .php_name = "enum_exists", .runtime_name = "php_enum_exists", .needs_allocator = true, .category = .object },
    .{ .php_name = "interface_exists", .runtime_name = "php_interface_exists", .needs_allocator = true, .category = .object },
    .{ .php_name = "trait_exists", .runtime_name = "php_trait_exists", .needs_allocator = true, .category = .object },
    .{ .php_name = "method_exists", .runtime_name = "php_method_exists", .category = .object },
    .{ .php_name = "property_exists", .runtime_name = "php_property_exists", .category = .object },
    .{ .php_name = "get_class", .runtime_name = "php_get_class", .needs_allocator = true, .category = .object },
    .{ .php_name = "get_parent_class", .runtime_name = "php_get_parent_class", .needs_allocator = true, .category = .object },
    .{ .php_name = "get_debug_type", .runtime_name = "php_get_debug_type", .needs_allocator = true, .category = .object },

    // ===== Callback 函数 =====
    .{ .php_name = "call_user_func", .runtime_name = "php_call_user_func", .category = .callback },
    .{ .php_name = "call_user_func_array", .runtime_name = "php_call_user_func_array", .category = .callback },

    // ===== Misc 函数 =====
    .{ .php_name = "define", .runtime_name = "php_define", .needs_allocator = true, .category = .misc },
    .{ .php_name = "defined", .runtime_name = "php_defined", .category = .misc },
    .{ .php_name = "constant", .runtime_name = "php_constant_get", .needs_allocator = true, .category = .misc },
    .{ .php_name = "get_defined_constants", .runtime_name = "php_get_defined_constants", .needs_allocator = true, .category = .misc },
    .{ .php_name = "function_exists", .runtime_name = "aot_function_exists", .category = .misc, .may_raise = false },
    .{ .php_name = "exit", .runtime_name = "php_exit", .category = .misc },
    .{ .php_name = "die", .runtime_name = "php_exit", .category = .misc }, // alias
    .{ .php_name = "func_get_args", .runtime_name = "php_func_get_args", .needs_allocator = true, .category = .misc },
    .{ .php_name = "func_get_arg", .runtime_name = "php_func_get_arg", .category = .misc },
    .{ .php_name = "func_num_args", .runtime_name = "php_func_num_args", .category = .misc, .may_raise = false },
    .{ .php_name = "memory_get_usage", .runtime_name = "php_memory_get_usage", .needs_allocator = true, .category = .misc, .may_raise = false },
    .{ .php_name = "memory_get_peak_usage", .runtime_name = "php_memory_get_peak_usage", .needs_allocator = true, .category = .misc, .may_raise = false },
    .{ .php_name = "debug_zval_dump", .runtime_name = "php_debug_zval_dump", .category = .misc },

    // ===== Error Handling 函数 =====
    .{ .php_name = "set_error_handler", .runtime_name = "php_set_error_handler", .category = .error_handling },
    .{ .php_name = "restore_error_handler", .runtime_name = "php_restore_error_handler", .category = .error_handling },
    .{ .php_name = "trigger_error", .runtime_name = "php_trigger_error", .category = .error_handling },
    .{ .php_name = "user_error", .runtime_name = "php_trigger_error", .category = .error_handling }, // alias
    .{ .php_name = "set_exception_handler", .runtime_name = "php_set_exception_handler", .needs_allocator = true, .category = .error_handling },
    .{ .php_name = "restore_exception_handler", .runtime_name = "php_restore_exception_handler", .category = .error_handling },
    .{ .php_name = "error_get_last", .runtime_name = "php_error_get_last", .needs_allocator = true, .category = .error_handling, .may_raise = false },

    // ===== System 函数 =====
    .{ .php_name = "shell_exec", .runtime_name = "php_shell_exec", .needs_allocator = true, .category = .system, .may_raise = false },
    .{ .php_name = "exec", .runtime_name = "php_exec", .needs_allocator = true, .category = .system, .may_raise = false, .ref_params = &[_]u8{ 1, 2 } },
    .{ .php_name = "system", .runtime_name = "php_system", .needs_allocator = true, .category = .system, .may_raise = false, .ref_params = &[_]u8{1} },
    .{ .php_name = "escapeshellarg", .runtime_name = "php_escapeshellarg", .needs_allocator = true, .category = .system, .may_raise = false },
    .{ .php_name = "escapeshellcmd", .runtime_name = "php_escapeshellcmd", .needs_allocator = true, .category = .system, .may_raise = false },
    .{ .php_name = "getenv", .runtime_name = "php_getenv", .needs_allocator = true, .category = .system },
    .{ .php_name = "getmypid", .runtime_name = "php_getmypid", .category = .system, .may_raise = false },
    .{ .php_name = "getmygid", .runtime_name = "php_getmygid", .category = .system, .may_raise = false },
    .{ .php_name = "phpversion", .runtime_name = "php_phpversion", .needs_allocator = true, .category = .system, .may_raise = false },
    .{ .php_name = "extension_loaded", .runtime_name = "php_extension_loaded", .category = .system, .may_raise = false },
    .{ .php_name = "get_loaded_extensions", .runtime_name = "php_get_loaded_extensions", .needs_allocator = true, .category = .system, .may_raise = false },
    .{ .php_name = "php_sapi_name", .runtime_name = "php_sapi_name", .needs_allocator = true, .category = .system },
    .{ .php_name = "php_uname", .runtime_name = "php_uname", .needs_allocator = true, .category = .system },
    .{ .php_name = "gc_enable", .runtime_name = "php_gc_enable", .needs_allocator = true, .category = .gc, .may_raise = false },
    .{ .php_name = "gc_collect_cycles", .runtime_name = "php_gc_collect_cycles", .needs_allocator = true, .category = .gc, .may_raise = false },
    .{ .php_name = "gc_enabled", .runtime_name = "php_gc_enabled", .category = .gc, .may_raise = false },
    .{ .php_name = "ini_get", .runtime_name = "php_ini_get", .needs_allocator = true, .category = .system, .may_raise = false },
    .{ .php_name = "getrusage", .runtime_name = "php_getrusage", .needs_allocator = true, .category = .system, .may_raise = false },

    // ===== Network 函数 =====
    .{ .php_name = "gethostbyname", .runtime_name = "php_gethostbyname", .needs_allocator = true, .category = .network },
    .{ .php_name = "gethostname", .runtime_name = "php_gethostname", .needs_allocator = true, .category = .network },
    .{ .php_name = "gethostbyaddr", .runtime_name = "php_gethostbyaddr", .needs_allocator = true, .category = .network },
    .{ .php_name = "parse_url", .runtime_name = "php_parse_url", .needs_allocator = true, .category = .network },
    .{ .php_name = "ip2long", .runtime_name = "php_ip2long", .category = .network },
    .{ .php_name = "long2ip", .runtime_name = "php_long2ip", .needs_allocator = true, .category = .network },
    .{ .php_name = "http_build_query", .runtime_name = "php_http_build_query", .needs_allocator = true, .category = .network },
    .{ .php_name = "parse_str", .runtime_name = "php_parse_str", .needs_allocator = true, .category = .network },
    .{ .php_name = "header", .runtime_name = "php_header", .category = .network },
    .{ .php_name = "headers_list", .runtime_name = "php_headers_list", .needs_allocator = true, .category = .network },
    .{ .php_name = "http_response_code", .runtime_name = "php_http_response_code", .category = .network },

    // ===== Ctype 函数 =====
    .{ .php_name = "ctype_alnum", .runtime_name = "php_ctype_alnum", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_alpha", .runtime_name = "php_ctype_alpha", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_digit", .runtime_name = "php_ctype_digit", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_lower", .runtime_name = "php_ctype_lower", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_upper", .runtime_name = "php_ctype_upper", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_space", .runtime_name = "php_ctype_space", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_print", .runtime_name = "php_ctype_print", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_punct", .runtime_name = "php_ctype_punct", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_xdigit", .runtime_name = "php_ctype_xdigit", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_cntrl", .runtime_name = "php_ctype_cntrl", .category = .ctype, .may_raise = false, .is_pure = true },
    .{ .php_name = "ctype_graph", .runtime_name = "php_ctype_graph", .category = .ctype, .may_raise = false, .is_pure = true },

    // ===== Mbstring 函数 =====
    .{ .php_name = "mb_strlen", .runtime_name = "php_mb_strlen", .category = .mbstring },
    .{ .php_name = "mb_substr", .runtime_name = "php_mb_substr", .category = .mbstring },
    .{ .php_name = "mb_strtoupper", .runtime_name = "php_mb_strtoupper", .category = .mbstring },
    .{ .php_name = "mb_strtolower", .runtime_name = "php_mb_strtolower", .category = .mbstring },
    .{ .php_name = "mb_detect_encoding", .runtime_name = "php_mb_detect_encoding", .needs_allocator = true, .category = .mbstring },

    // ===== Process 函数 =====
    .{ .php_name = "pcntl_fork", .runtime_name = "php_pcntl_fork", .category = .process },
    .{ .php_name = "pcntl_waitpid", .runtime_name = "php_pcntl_waitpid", .needs_allocator = true, .category = .process },
    .{ .php_name = "pcntl_wait", .runtime_name = "php_pcntl_wait", .needs_allocator = true, .category = .process },
    .{ .php_name = "pcntl_wexitstatus", .runtime_name = "php_pcntl_wexitstatus", .category = .process },
    .{ .php_name = "pcntl_signal", .runtime_name = "php_pcntl_signal", .needs_allocator = true, .category = .process },
    .{ .php_name = "pcntl_signal_dispatch", .runtime_name = "php_pcntl_signal_dispatch", .needs_allocator = true, .category = .process },
    .{ .php_name = "pcntl_alarm", .runtime_name = "php_pcntl_alarm", .category = .process },
    .{ .php_name = "pcntl_sigprocmask", .runtime_name = "php_pcntl_sigprocmask", .needs_allocator = true, .category = .process },
    .{ .php_name = "posix_getpid", .runtime_name = "php_posix_getpid", .category = .process },
    .{ .php_name = "posix_kill", .runtime_name = "php_posix_kill", .category = .process },
    .{ .php_name = "posix_mkfifo", .runtime_name = "php_posix_mkfifo", .needs_allocator = true, .category = .process },
    .{ .php_name = "ftok", .runtime_name = "php_ftok", .needs_allocator = true, .category = .process },
    .{ .php_name = "msg_get_queue", .runtime_name = "php_msg_get_queue", .needs_allocator = true, .category = .process },
    .{ .php_name = "msg_remove_queue", .runtime_name = "php_msg_remove_queue", .category = .process },
    .{ .php_name = "sem_get", .runtime_name = "php_sem_get", .needs_allocator = true, .category = .process },
    .{ .php_name = "sem_remove", .runtime_name = "php_sem_remove", .category = .process },
    .{ .php_name = "shmop_open", .runtime_name = "php_shmop_open", .needs_allocator = true, .category = .process },
    .{ .php_name = "shmop_close", .runtime_name = "php_shmop_close", .category = .process },
    .{ .php_name = "socket_create_pair", .runtime_name = "php_socket_create_pair", .needs_allocator = true, .category = .process },
    .{ .php_name = "socket_close", .runtime_name = "php_socket_close", .category = .process },

    // ===== Internal 函数（AOT 内部使用） =====
    .{ .php_name = "php_deref", .runtime_name = "php_deref", .category = .internal },
    .{ .php_name = "php_ref_assign", .runtime_name = "php_ref_assign", .category = .internal, .may_raise = false },
    .{ .php_name = "php_ref_assign_ptr", .runtime_name = "php_ref_assign_ptr", .category = .internal, .may_raise = false },
    .{ .php_name = "php_object_new", .runtime_name = "php_object_new", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_object_new_with_constructor", .runtime_name = "php_object_new_with_constructor", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_concat", .runtime_name = "php_concat", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_array_iter_init", .runtime_name = "php_array_iter_init", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_array_iter_init_snapshot", .runtime_name = "php_array_iter_init_snapshot", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_array_iter_init_ref", .runtime_name = "php_array_iter_init_ref", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_array_iter_key", .runtime_name = "php_array_iter_key", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_array_iter_value_ref_reuse", .runtime_name = "php_array_iter_value_ref_reuse", .category = .internal },
    .{ .php_name = "php_array_iter_valid_ref", .runtime_name = "php_array_iter_valid_ref", .category = .internal },
    .{ .php_name = "php_array_iter_next_ref", .runtime_name = "php_array_iter_next_ref", .category = .internal },
    .{ .php_name = "php_array_iter_free", .runtime_name = "php_array_iter_free", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_array_iter_free_ref", .runtime_name = "php_array_iter_free_ref", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_create_closure", .runtime_name = "php_create_closure", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_object_unset", .runtime_name = "php_object_unset", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_args_append_spread", .runtime_name = "php_args_append_spread", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_invoke_callable_args_array", .runtime_name = "php_invoke_callable_args_array", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_object_call_safe_args_array", .runtime_name = "php_object_call_safe_args_array", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_object_call_args_array", .runtime_name = "php_object_call_args_array", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_object_call_named_args", .runtime_name = "php_object_call_named_args", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_constant_get", .runtime_name = "php_constant_get", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_json_encode", .runtime_name = "php_json_encode", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_go_builtin", .runtime_name = "php_go_builtin", .needs_allocator = true, .category = .internal },
    .{ .php_name = "php_bool_or", .runtime_name = "php_bool_or", .category = .internal, .may_raise = false },
    .{ .php_name = "php_property_array_push_with_obj", .runtime_name = "php_property_array_push_with_obj", .category = .internal },
    .{ .php_name = "php_property_array_set_with_obj", .runtime_name = "php_property_array_set_with_obj", .category = .internal },
    .{ .php_name = "php_array_merge_into", .runtime_name = "php_array_merge_into", .needs_allocator = true, .category = .internal },
    .{ .php_name = "getStaticVar", .runtime_name = "getStaticVar", .category = .internal },
    .{ .php_name = "setStaticVar", .runtime_name = "setStaticVar", .category = .internal },
    .{ .php_name = "throwThrowable", .runtime_name = "throwThrowable", .needs_allocator = true, .category = .internal },
    .{ .php_name = "go", .runtime_name = "php_go_builtin", .needs_allocator = true, .category = .internal },

    // ===== Output Buffer 函数 =====
    .{ .php_name = "ob_start", .runtime_name = "php_ob_start", .category = .output },
    .{ .php_name = "ob_gzhandler", .runtime_name = "php_ob_gzhandler", .needs_allocator = true, .category = .output },
    .{ .php_name = "ob_get_contents", .runtime_name = "php_ob_get_contents", .needs_allocator = true, .category = .output },
    .{ .php_name = "ob_end_clean", .runtime_name = "php_ob_end_clean", .category = .output },
    .{ .php_name = "ob_get_clean", .runtime_name = "php_ob_get_clean", .needs_allocator = true, .category = .output },
    .{ .php_name = "ob_get_level", .runtime_name = "php_ob_get_level", .category = .output, .may_raise = false },
    .{ .php_name = "ob_flush", .runtime_name = "php_ob_flush", .category = .output },
    .{ .php_name = "ob_end_flush", .runtime_name = "php_ob_end_flush", .category = .output },
    .{ .php_name = "ob_get_length", .runtime_name = "php_ob_get_length", .category = .output, .may_raise = false },
    .{ .php_name = "ob_get_status", .runtime_name = "php_ob_get_status", .needs_allocator = true, .category = .output },
    .{ .php_name = "ob_implicit_flush", .runtime_name = "php_ob_implicit_flush", .category = .output, .may_raise = false },

    // ===== Misc 补充 =====
    .{ .php_name = "mysqli_connect", .runtime_name = "php_mysqli_connect", .needs_allocator = true, .category = .misc, .may_raise = false },
    .{ .php_name = "token_get_all", .runtime_name = "php_token_get_all", .needs_allocator = true, .category = .misc },
    .{ .php_name = "get_resource_id", .runtime_name = "php_get_resource_id", .category = .misc },
    .{ .php_name = "get_resource_type", .runtime_name = "php_get_resource_type", .needs_allocator = true, .category = .misc },
    .{ .php_name = "stream_register_wrapper", .runtime_name = "php_stream_register_wrapper", .needs_allocator = true, .category = .misc },
    .{ .php_name = "stream_wrapper_register", .runtime_name = "php_stream_register_wrapper", .needs_allocator = true, .category = .misc }, // alias
};

/// 注册表大小（含 ID 0 保留项）
pub const REGISTRY_SIZE: usize = registry.len;

/// 有效函数数量（不含 ID 0）
pub const FUNCTION_COUNT: usize = REGISTRY_SIZE - 1;

// ============================================================
// 编译期 PHP名称 → FunctionId 查找表
// ============================================================

/// 编译期生成的 PHP 函数名 → FunctionId 映射
const NameToIdEntry = struct { []const u8, FunctionId };

/// 生成 name→id 映射表的 comptime 数组
fn generateNameToIdEntries() [REGISTRY_SIZE]NameToIdEntry {
    var entries: [REGISTRY_SIZE]NameToIdEntry = undefined;
    for (0..REGISTRY_SIZE) |i| {
        entries[i] = .{ registry[i].php_name, @intCast(i) };
    }
    return entries;
}

const name_to_id_entries = generateNameToIdEntries();

/// 编译期 StaticStringMap: PHP 函数名 → FunctionId
/// 算法复杂度: O(1) 完美哈希查找
const name_to_id_map = std.StaticStringMap(FunctionId).initComptime(
    @as([]const NameToIdEntry, &name_to_id_entries),
);

// ============================================================
// 公共查询 API
// ============================================================

/// 通过 PHP 函数名查找 FunctionId
/// 算法: O(1) StaticStringMap 查找
/// @return FunctionId 或 null（未注册函数）
pub fn lookupByName(php_name: []const u8) ?FunctionId {
    return name_to_id_map.get(php_name);
}

/// Comptime-only 查找: 线性扫描 registry 获取 FunctionId
/// 仅用于生成 switch case 常量，编译期零开销
/// 找不到时触发 @compileError
pub fn comptimeLookup(comptime php_name: []const u8) FunctionId {
    inline for (0..REGISTRY_SIZE) |i| {
        if (comptime std.mem.eql(u8, registry[i].php_name, php_name)) {
            return @intCast(i);
        }
    }
    @compileError("Function not registered: " ++ php_name);
}

/// 通过 FunctionId 获取元数据
/// 算法: O(1) 数组索引
/// @return FunctionMeta 引用
pub fn getMeta(id: FunctionId) *const FunctionMeta {
    return &registry[id];
}

/// 通过 PHP 函数名获取元数据（便捷 API，等价于 lookupByName + getMeta）
/// @return FunctionMeta 或 null
pub fn getMetaByName(php_name: []const u8) ?*const FunctionMeta {
    const id = lookupByName(php_name) orelse return null;
    return getMeta(id);
}

/// 检查 PHP 函数名是否已注册
pub fn isRegistered(php_name: []const u8) bool {
    return lookupByName(php_name) != null;
}

/// 检查函数是否需要 allocator
pub fn needsAllocator(php_name: []const u8) bool {
    const meta = getMetaByName(php_name) orelse return false;
    return meta.needs_allocator;
}

/// 获取函数的运行时名称
pub fn getRuntimeName(php_name: []const u8) ?[]const u8 {
    const meta = getMetaByName(php_name) orelse return null;
    return meta.runtime_name;
}

/// 获取引用参数索引列表
pub fn getRefParams(php_name: []const u8) []const u8 {
    const meta = getMetaByName(php_name) orelse return &[_]u8{};
    return meta.ref_params;
}

/// 检查函数是否为语句函数（返回值通常被忽略）
pub fn isStatementFunction(php_name: []const u8) bool {
    const meta = getMetaByName(php_name) orelse return false;
    return meta.is_statement;
}

/// 检查函数是否为纯函数
pub fn isPure(php_name: []const u8) bool {
    const meta = getMetaByName(php_name) orelse return false;
    return meta.is_pure;
}

/// 获取函数分类
pub fn getCategory(php_name: []const u8) ?Category {
    const meta = getMetaByName(php_name) orelse return null;
    return meta.category;
}

// ============================================================
// 兼容层 - 为 native_linker.zig 提供向后兼容的 BuiltinInfo 接口
// ============================================================

/// 兼容旧 BuiltinInfo 结构
pub const BuiltinInfo = struct {
    runtime_name: []const u8,
    needs_allocator: bool,
    may_raise: bool = true,
    ref_params: []const u8 = &[_]u8{},
};

/// 兼容旧的 builtinInfo() 查询接口
/// 直接从 registry 转换为 BuiltinInfo
pub fn builtinInfo(func_name: []const u8) ?BuiltinInfo {
    const meta = getMetaByName(func_name) orelse return null;
    return BuiltinInfo{
        .runtime_name = meta.runtime_name,
        .needs_allocator = meta.needs_allocator,
        .may_raise = meta.may_raise,
        .ref_params = meta.ref_params,
    };
}

// ============================================================
// 编译期自检
// ============================================================

comptime {
    // 确保 registry[0] 是 INVALID
    if (!std.mem.eql(u8, registry[0].php_name, "__invalid__")) {
        @compileError("registry[0] must be __invalid__ (INVALID_FUNCTION_ID)");
    }
    // 确保 REGISTRY_SIZE 在 u16 范围内
    if (REGISTRY_SIZE > std.math.maxInt(FunctionId)) {
        @compileError("Registry size exceeds FunctionId capacity (u16)");
    }
}

// ============================================================
// 测试
// ============================================================

test "FunctionRegistry: basic lookup" {
    const testing = std.testing;

    // 查找已注册函数
    const echo_id = lookupByName("echo");
    try testing.expect(echo_id != null);
    try testing.expect(echo_id.? != INVALID_FUNCTION_ID);

    const meta = getMeta(echo_id.?);
    try testing.expectEqualStrings("php_echo", meta.runtime_name);
    try testing.expect(!meta.needs_allocator);
    try testing.expect(meta.category == .output);
    try testing.expect(meta.is_statement);

    // 查找未注册函数
    try testing.expect(lookupByName("nonexistent_func") == null);
}

test "FunctionRegistry: compatibility layer" {
    const testing = std.testing;

    const info = builtinInfo("str_replace");
    try testing.expect(info != null);
    try testing.expectEqualStrings("php_str_replace", info.?.runtime_name);
    try testing.expect(info.?.needs_allocator);
    try testing.expect(info.?.ref_params.len == 1);
    try testing.expect(info.?.ref_params[0] == 3);
}

test "FunctionRegistry: ref params" {
    const testing = std.testing;

    const exec_params = getRefParams("exec");
    try testing.expect(exec_params.len == 2);
    try testing.expect(exec_params[0] == 1);
    try testing.expect(exec_params[1] == 2);

    const no_ref = getRefParams("strlen");
    try testing.expect(no_ref.len == 0);
}

test "FunctionRegistry: pure functions" {
    const testing = std.testing;

    try testing.expect(isPure("strlen"));
    try testing.expect(isPure("abs"));
    try testing.expect(isPure("is_null"));
    try testing.expect(!isPure("echo"));
    try testing.expect(!isPure("time"));
}

test "FunctionRegistry: statement functions" {
    const testing = std.testing;

    try testing.expect(isStatementFunction("echo"));
    try testing.expect(isStatementFunction("var_dump"));
    try testing.expect(isStatementFunction("sort"));
    try testing.expect(!isStatementFunction("strlen"));
    try testing.expect(!isStatementFunction("count"));
}

test "FunctionRegistry: category" {
    const testing = std.testing;

    try testing.expect(getCategory("strlen").? == .string);
    try testing.expect(getCategory("count").? == .array);
    try testing.expect(getCategory("abs").? == .math);
    try testing.expect(getCategory("json_encode").? == .json);
    try testing.expect(getCategory("nonexistent") == null);
}
