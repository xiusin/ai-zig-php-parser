//! ============================================================================
//! 声明式函数表 — 所有内置函数的单一真相源 (SSOT)
//! ============================================================================
//!
//! 设计原则：
//! 1. 新增函数只需在此表追加一行
//! 2. 函数名与 builtin_dispatch.zig 中 BuiltinId 枚举的 tag name 一致
//! 3. min_args/max_args 与 stdlib.zig 中注册的值一致
//! 4. 保留 BuiltinId 枚举中的编号分区设计
//! 5. comptime 验证确保无重复、无遗漏
//!
//! 编号分区：
//!   Array     0-49    String    50-149   Math      150-199
//!   File      200-249 DateTime  250-279  JSON      280-289
//!   Hash      290-309 Preg      310-329  Random    330-339
//!   Type      340-359 Variable  360-379  Class     380-399
//!   Error     400-409 Misc      410-449  HTTP      450-469
//!   IO        470-499
//!

const std = @import("std");

/// 函数分类
pub const FnCategory = enum {
    array,
    string,
    math,
    file,
    datetime,
    json,
    hash,
    preg,
    random,
    type_,
    variable,
    class,
    error_,
    misc,
    http,
    io,
};

/// 单个函数声明条目
pub const FnEntry = struct {
    name: []const u8,
    min_args: u8,
    max_args: u8, // 255 = variadic
    category: FnCategory,
};

/// 声明式函数表 — 所有内置函数的单一真相源
/// 新增函数只需在此表追加一行
pub const FN_TABLE = [_]FnEntry{
    // ========================================================================
    // Array Functions (BuiltinId 0-49)
    // ========================================================================
    .{ .name = "array_map", .min_args = 2, .max_args = 255, .category = .array },
    .{ .name = "array_filter", .min_args = 1, .max_args = 3, .category = .array },
    .{ .name = "array_reduce", .min_args = 2, .max_args = 3, .category = .array },
    .{ .name = "array_keys", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_values", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_merge", .min_args = 1, .max_args = 255, .category = .array },
    .{ .name = "array_push", .min_args = 2, .max_args = 255, .category = .array },
    .{ .name = "array_pop", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_shift", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_unshift", .min_args = 2, .max_args = 255, .category = .array },
    .{ .name = "array_slice", .min_args = 2, .max_args = 4, .category = .array },
    .{ .name = "array_splice", .min_args = 2, .max_args = 4, .category = .array },
    .{ .name = "array_reverse", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "array_flip", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_unique", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "array_intersect", .min_args = 2, .max_args = 255, .category = .array },
    .{ .name = "array_diff", .min_args = 2, .max_args = 255, .category = .array },
    .{ .name = "array_chunk", .min_args = 2, .max_args = 3, .category = .array },
    .{ .name = "array_column", .min_args = 2, .max_args = 3, .category = .array },
    .{ .name = "array_combine", .min_args = 2, .max_args = 2, .category = .array },
    .{ .name = "array_fill", .min_args = 3, .max_args = 3, .category = .array },
    .{ .name = "array_pad", .min_args = 3, .max_args = 3, .category = .array },
    .{ .name = "array_search", .min_args = 2, .max_args = 3, .category = .array },
    .{ .name = "array_key_exists", .min_args = 2, .max_args = 2, .category = .array },
    .{ .name = "in_array", .min_args = 2, .max_args = 3, .category = .array },
    .{ .name = "count", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "sizeof", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "sort", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "rsort", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "asort", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "arsort", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "ksort", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "krsort", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "usort", .min_args = 2, .max_args = 2, .category = .array },
    .{ .name = "uasort", .min_args = 2, .max_args = 2, .category = .array },
    .{ .name = "uksort", .min_args = 2, .max_args = 2, .category = .array },
    .{ .name = "array_multisort", .min_args = 1, .max_args = 255, .category = .array },
    .{ .name = "range", .min_args = 2, .max_args = 3, .category = .array },
    .{ .name = "compact", .min_args = 1, .max_args = 255, .category = .array },
    .{ .name = "extract", .min_args = 1, .max_args = 3, .category = .array },
    .{ .name = "list", .min_args = 1, .max_args = 255, .category = .array },
    .{ .name = "each", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "current", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "next", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "prev", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "reset", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "end", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "key", .min_args = 1, .max_args = 1, .category = .array },
    // Extra array functions from stdlib.zig (not in BuiltinId)
    .{ .name = "array_first", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "array_last", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "array_sum", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_product", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_walk", .min_args = 2, .max_args = 3, .category = .array },
    .{ .name = "array_key_first", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_key_last", .min_args = 1, .max_args = 1, .category = .array },
    .{ .name = "array_fill_keys", .min_args = 2, .max_args = 2, .category = .array },
    .{ .name = "array_change_key_case", .min_args = 1, .max_args = 2, .category = .array },
    .{ .name = "array_count_values", .min_args = 1, .max_args = 1, .category = .array },

    // ========================================================================
    // String Functions (BuiltinId 50-149)
    // ========================================================================
    .{ .name = "echo", .min_args = 1, .max_args = 255, .category = .string },
    .{ .name = "print", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "printf", .min_args = 1, .max_args = 255, .category = .string },
    .{ .name = "sprintf", .min_args = 1, .max_args = 255, .category = .string },
    .{ .name = "strlen", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "strpos", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "strrpos", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "stripos", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "strripos", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "substr", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "str_replace", .min_args = 3, .max_args = 4, .category = .string },
    .{ .name = "str_ireplace", .min_args = 3, .max_args = 4, .category = .string },
    .{ .name = "strtolower", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "strtoupper", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "ucfirst", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "lcfirst", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "ucwords", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "trim", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "ltrim", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "rtrim", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "explode", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "implode", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "join", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "str_split", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "chunk_split", .min_args = 1, .max_args = 3, .category = .string },
    .{ .name = "wordwrap", .min_args = 1, .max_args = 4, .category = .string },
    .{ .name = "str_repeat", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "str_pad", .min_args = 2, .max_args = 4, .category = .string },
    .{ .name = "str_shuffle", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "strrev", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "strcmp", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "strcasecmp", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "strncmp", .min_args = 3, .max_args = 3, .category = .string },
    .{ .name = "strncasecmp", .min_args = 3, .max_args = 3, .category = .string },
    .{ .name = "str_contains", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "str_starts_with", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "str_ends_with", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "substr_count", .min_args = 2, .max_args = 4, .category = .string },
    .{ .name = "substr_replace", .min_args = 3, .max_args = 4, .category = .string },
    .{ .name = "str_word_count", .min_args = 1, .max_args = 3, .category = .string },
    .{ .name = "levenshtein", .min_args = 2, .max_args = 6, .category = .string },
    .{ .name = "similar_text", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "strstr", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "stristr", .min_args = 2, .max_args = 3, .category = .string },
    .{ .name = "strrchr", .min_args = 2, .max_args = 2, .category = .string },
    .{ .name = "soundex", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "metaphone", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "htmlspecialchars", .min_args = 1, .max_args = 4, .category = .string },
    .{ .name = "htmlentities", .min_args = 1, .max_args = 4, .category = .string },
    .{ .name = "html_entity_decode", .min_args = 1, .max_args = 3, .category = .string },
    .{ .name = "strip_tags", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "addslashes", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "stripslashes", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "quotemeta", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "nl2br", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "parse_str", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "http_build_query", .min_args = 1, .max_args = 5, .category = .variable },
    .{ .name = "urlencode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "urldecode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "rawurlencode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "rawurldecode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "base64_encode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "base64_decode", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "quoted_printable_encode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "quoted_printable_decode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "convert_uuencode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "convert_uudecode", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "bin2hex", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "hex2bin", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "chr", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "ord", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "number_format", .min_args = 1, .max_args = 4, .category = .string },
    .{ .name = "money_format", .min_args = 2, .max_args = 2, .category = .string },
    // Extra string functions from stdlib.zig/builtin_vars.zig (not in BuiltinId)
    .{ .name = "serialize", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "unserialize", .min_args = 1, .max_args = 2, .category = .type_ },
    .{ .name = "strtr", .min_args = 2, .max_args = 3, .category = .variable },

    // ========================================================================
    // Math Functions (BuiltinId 150-199)
    // ========================================================================
    .{ .name = "abs", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "ceil", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "floor", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "round", .min_args = 1, .max_args = 2, .category = .math },
    .{ .name = "sqrt", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "pow", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "exp", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "log", .min_args = 1, .max_args = 2, .category = .math },
    .{ .name = "log10", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "log2", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "sin", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "cos", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "tan", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "asin", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "acos", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "atan", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "atan2", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "sinh", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "cosh", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "tanh", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "deg2rad", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "rad2deg", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "min", .min_args = 1, .max_args = 255, .category = .math },
    .{ .name = "max", .min_args = 1, .max_args = 255, .category = .math },
    .{ .name = "rand", .min_args = 0, .max_args = 2, .category = .math },
    .{ .name = "mt_rand", .min_args = 0, .max_args = 2, .category = .math },
    .{ .name = "srand", .min_args = 0, .max_args = 1, .category = .math },
    .{ .name = "mt_srand", .min_args = 0, .max_args = 1, .category = .math },
    .{ .name = "getrandmax", .min_args = 0, .max_args = 0, .category = .math },
    .{ .name = "mt_getrandmax", .min_args = 0, .max_args = 0, .category = .math },
    .{ .name = "lcg_value", .min_args = 0, .max_args = 0, .category = .math },
    .{ .name = "is_nan", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "is_finite", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "is_infinite", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "intdiv", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "fmod", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "hypot", .min_args = 2, .max_args = 2, .category = .math },
    // Extra math functions from stdlib.zig (not in BuiltinId)
    .{ .name = "bit_and", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "bit_or", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "bit_xor", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "bit_not", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "bit_shift_left", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "bit_shift_right", .min_args = 2, .max_args = 2, .category = .math },
    .{ .name = "pi", .min_args = 0, .max_args = 0, .category = .math },
    .{ .name = "decbin", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "dechex", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "decoct", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "bindec", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "hexdec", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "octdec", .min_args = 1, .max_args = 1, .category = .math },
    .{ .name = "base_convert", .min_args = 3, .max_args = 3, .category = .math },

    // ========================================================================
    // File Functions (BuiltinId 200-249)
    // ========================================================================
    .{ .name = "fopen", .min_args = 2, .max_args = 3, .category = .file },
    .{ .name = "fclose", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "fread", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "fwrite", .min_args = 2, .max_args = 3, .category = .file },
    .{ .name = "fgets", .min_args = 1, .max_args = 2, .category = .file },
    .{ .name = "fgetc", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "fputs", .min_args = 2, .max_args = 3, .category = .file },
    .{ .name = "fputc", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "feof", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "fseek", .min_args = 2, .max_args = 3, .category = .file },
    .{ .name = "ftell", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "rewind", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "fflush", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "flock", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "ftruncate", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "fstat", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "file_exists", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "is_file", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "is_dir", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "is_link", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "is_readable", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "is_writable", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "is_executable", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "filesize", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "filetype", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "filemtime", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "fileatime", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "filectime", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "fileperms", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "fileowner", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "filegroup", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "file_get_contents", .min_args = 1, .max_args = 5, .category = .file },
    .{ .name = "file_put_contents", .min_args = 2, .max_args = 4, .category = .file },
    .{ .name = "file", .min_args = 1, .max_args = 3, .category = .file },
    .{ .name = "readfile", .min_args = 1, .max_args = 3, .category = .file },
    .{ .name = "unlink", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "rename", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "copy", .min_args = 2, .max_args = 3, .category = .file },
    .{ .name = "mkdir", .min_args = 1, .max_args = 3, .category = .file },
    .{ .name = "rmdir", .min_args = 1, .max_args = 2, .category = .file },
    .{ .name = "chmod", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "chown", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "chgrp", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "touch", .min_args = 1, .max_args = 3, .category = .file },
    .{ .name = "glob", .min_args = 1, .max_args = 2, .category = .file },
    .{ .name = "basename", .min_args = 1, .max_args = 2, .category = .file },
    .{ .name = "dirname", .min_args = 1, .max_args = 2, .category = .file },
    .{ .name = "pathinfo", .min_args = 1, .max_args = 2, .category = .file },
    .{ .name = "realpath", .min_args = 1, .max_args = 1, .category = .file },
    // Extra file functions from stdlib.zig (not in BuiltinId)
    .{ .name = "clearstatcache", .min_args = 0, .max_args = 255, .category = .file },
    .{ .name = "disk_free_space", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "disk_total_space", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "link", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "symlink", .min_args = 2, .max_args = 2, .category = .file },
    .{ .name = "readlink", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "lstat", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "stat", .min_args = 1, .max_args = 1, .category = .file },
    .{ .name = "fnmatch", .min_args = 2, .max_args = 3, .category = .file },
    .{ .name = "scandir", .min_args = 1, .max_args = 2, .category = .file },

    // ========================================================================
    // Date/Time Functions (BuiltinId 250-279)
    // ========================================================================
    .{ .name = "time", .min_args = 0, .max_args = 0, .category = .datetime },
    .{ .name = "microtime", .min_args = 0, .max_args = 1, .category = .datetime },
    .{ .name = "date", .min_args = 1, .max_args = 2, .category = .datetime },
    .{ .name = "gmdate", .min_args = 1, .max_args = 2, .category = .datetime },
    .{ .name = "strtotime", .min_args = 1, .max_args = 2, .category = .datetime },
    .{ .name = "mktime", .min_args = 0, .max_args = 6, .category = .datetime },
    .{ .name = "gmmktime", .min_args = 0, .max_args = 6, .category = .datetime },
    .{ .name = "checkdate", .min_args = 3, .max_args = 3, .category = .datetime },
    .{ .name = "getdate", .min_args = 0, .max_args = 1, .category = .datetime },
    .{ .name = "localtime", .min_args = 0, .max_args = 2, .category = .datetime },
    .{ .name = "idate", .min_args = 1, .max_args = 2, .category = .datetime },
    .{ .name = "date_create", .min_args = 0, .max_args = 2, .category = .datetime },
    .{ .name = "date_format", .min_args = 2, .max_args = 2, .category = .datetime },
    .{ .name = "date_parse", .min_args = 1, .max_args = 1, .category = .datetime },
    .{ .name = "date_diff", .min_args = 2, .max_args = 2, .category = .datetime },
    .{ .name = "date_add", .min_args = 2, .max_args = 2, .category = .datetime },
    .{ .name = "date_sub", .min_args = 2, .max_args = 2, .category = .datetime },
    .{ .name = "timezone_open", .min_args = 1, .max_args = 1, .category = .datetime },
    .{ .name = "timezone_name_get", .min_args = 1, .max_args = 1, .category = .datetime },

    // ========================================================================
    // JSON Functions (BuiltinId 280-289)
    // ========================================================================
    .{ .name = "json_encode", .min_args = 1, .max_args = 3, .category = .json },
    .{ .name = "json_decode", .min_args = 1, .max_args = 4, .category = .json },
    .{ .name = "json_last_error", .min_args = 0, .max_args = 0, .category = .json },
    .{ .name = "json_last_error_msg", .min_args = 0, .max_args = 0, .category = .json },

    // ========================================================================
    // Hash Functions (BuiltinId 290-309)
    // ========================================================================
    .{ .name = "md5", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "md5_file", .min_args = 1, .max_args = 2, .category = .hash },
    .{ .name = "sha1", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "sha1_file", .min_args = 1, .max_args = 2, .category = .hash },
    .{ .name = "hash", .min_args = 2, .max_args = 3, .category = .hash },
    .{ .name = "hash_file", .min_args = 2, .max_args = 3, .category = .hash },
    .{ .name = "hash_hmac", .min_args = 3, .max_args = 4, .category = .hash },
    .{ .name = "hash_hmac_file", .min_args = 3, .max_args = 4, .category = .hash },
    .{ .name = "hash_algos", .min_args = 0, .max_args = 0, .category = .hash },
    .{ .name = "crc32", .min_args = 1, .max_args = 2, .category = .hash },
    // Extra hash functions from stdlib.zig (not in BuiltinId)
    .{ .name = "sha256", .min_args = 1, .max_args = 2, .category = .hash },
    .{ .name = "sha512", .min_args = 1, .max_args = 2, .category = .hash },

    // ========================================================================
    // Regular Expression Functions (BuiltinId 310-329)
    // ========================================================================
    .{ .name = "preg_match", .min_args = 2, .max_args = 5, .category = .preg },
    .{ .name = "preg_match_all", .min_args = 2, .max_args = 5, .category = .preg },
    .{ .name = "preg_replace", .min_args = 3, .max_args = 5, .category = .preg },
    .{ .name = "preg_replace_callback", .min_args = 3, .max_args = 5, .category = .preg },
    .{ .name = "preg_filter", .min_args = 3, .max_args = 5, .category = .preg },
    .{ .name = "preg_split", .min_args = 2, .max_args = 4, .category = .preg },
    .{ .name = "preg_grep", .min_args = 2, .max_args = 3, .category = .preg },
    .{ .name = "preg_quote", .min_args = 1, .max_args = 2, .category = .preg },
    .{ .name = "preg_last_error", .min_args = 0, .max_args = 0, .category = .preg },

    // ========================================================================
    // Random Functions (BuiltinId 330-339)
    // ========================================================================
    .{ .name = "shuffle", .min_args = 1, .max_args = 1, .category = .random },
    .{ .name = "array_rand", .min_args = 1, .max_args = 2, .category = .random },
    .{ .name = "random_int", .min_args = 2, .max_args = 2, .category = .random },
    .{ .name = "random_bytes", .min_args = 1, .max_args = 1, .category = .random },

    // ========================================================================
    // Type Functions (BuiltinId 340-359)
    // ========================================================================
    .{ .name = "is_null", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_bool", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_int", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_float", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_string", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_array", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_object", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_resource", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_numeric", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_scalar", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_callable", .min_args = 1, .max_args = 3, .category = .variable },
    .{ .name = "gettype", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "settype", .min_args = 2, .max_args = 2, .category = .type_ },
    .{ .name = "intval", .min_args = 1, .max_args = 2, .category = .type_ },
    .{ .name = "floatval", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "strval", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "boolval", .min_args = 1, .max_args = 1, .category = .type_ },
    // Extra type aliases from stdlib.zig (not in BuiltinId)
    .{ .name = "is_integer", .min_args = 1, .max_args = 1, .category = .type_ },
    .{ .name = "is_double", .min_args = 1, .max_args = 1, .category = .type_ },

    // ========================================================================
    // Variable Functions (BuiltinId 360-379)
    // ========================================================================
    .{ .name = "var_dump", .min_args = 1, .max_args = 255, .category = .misc },
    .{ .name = "var_export", .min_args = 1, .max_args = 2, .category = .misc },
    .{ .name = "print_r", .min_args = 1, .max_args = 2, .category = .misc },
    .{ .name = "mb_strlen", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "mb_substr", .min_args = 2, .max_args = 4, .category = .string },
    .{ .name = "mb_strtolower", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "mb_strtoupper", .min_args = 1, .max_args = 2, .category = .string },
    .{ .name = "mb_detect_encoding", .min_args = 1, .max_args = 3, .category = .string },
    .{ .name = "debug_zval_dump", .min_args = 1, .max_args = 1, .category = .variable },
    .{ .name = "isset", .min_args = 1, .max_args = 255, .category = .array },
    .{ .name = "empty", .min_args = 1, .max_args = 1, .category = .variable },
    .{ .name = "unset", .min_args = 1, .max_args = 255, .category = .variable },
    .{ .name = "get_defined_vars", .min_args = 0, .max_args = 0, .category = .variable },
    .{ .name = "get_resource_type", .min_args = 1, .max_args = 1, .category = .variable },
    // Extra variable functions from builtin_vars.zig
    .{ .name = "call_user_func", .min_args = 1, .max_args = 255, .category = .variable },
    .{ .name = "call_user_func_array", .min_args = 2, .max_args = 2, .category = .variable },
    .{ .name = "get_defined_functions", .min_args = 0, .max_args = 0, .category = .variable },
    .{ .name = "get_defined_constants", .min_args = 0, .max_args = 1, .category = .variable },
    .{ .name = "get_declared_classes", .min_args = 0, .max_args = 0, .category = .variable },
    .{ .name = "func_num_args", .min_args = 0, .max_args = 0, .category = .variable },
    .{ .name = "func_get_arg", .min_args = 1, .max_args = 1, .category = .variable },
    .{ .name = "func_get_args", .min_args = 0, .max_args = 0, .category = .variable },

    // ========================================================================
    // Class/Object Functions (BuiltinId 380-399)
    // ========================================================================
    .{ .name = "class_exists", .min_args = 1, .max_args = 2, .category = .class },
    .{ .name = "interface_exists", .min_args = 1, .max_args = 2, .category = .class },
    .{ .name = "trait_exists", .min_args = 1, .max_args = 2, .category = .class },
    .{ .name = "method_exists", .min_args = 2, .max_args = 2, .category = .class },
    .{ .name = "property_exists", .min_args = 2, .max_args = 2, .category = .class },
    .{ .name = "get_class", .min_args = 0, .max_args = 1, .category = .class },
    .{ .name = "get_parent_class", .min_args = 0, .max_args = 1, .category = .class },
    .{ .name = "get_class_methods", .min_args = 0, .max_args = 1, .category = .class },
    .{ .name = "get_class_vars", .min_args = 1, .max_args = 1, .category = .class },
    .{ .name = "get_object_vars", .min_args = 1, .max_args = 1, .category = .class },
    .{ .name = "is_a", .min_args = 2, .max_args = 3, .category = .class },
    .{ .name = "is_subclass_of", .min_args = 2, .max_args = 2, .category = .class },
    .{ .name = "get_called_class", .min_args = 0, .max_args = 0, .category = .class },

    // ========================================================================
    // Error Functions (BuiltinId 400-409)
    // ========================================================================
    .{ .name = "error_reporting", .min_args = 0, .max_args = 1, .category = .error_ },
    .{ .name = "trigger_error", .min_args = 1, .max_args = 2, .category = .error_ },
    .{ .name = "user_error", .min_args = 1, .max_args = 2, .category = .error_ },
    .{ .name = "set_error_handler", .min_args = 1, .max_args = 2, .category = .error_ },
    .{ .name = "restore_error_handler", .min_args = 0, .max_args = 0, .category = .error_ },
    // Extra error functions from builtin_vars.zig
    .{ .name = "set_exception_handler", .min_args = 1, .max_args = 1, .category = .error_ },
    .{ .name = "error_get_last", .min_args = 0, .max_args = 0, .category = .error_ },

    // ========================================================================
    // Misc Functions (BuiltinId 410-449)
    // ========================================================================
    .{ .name = "define", .min_args = 2, .max_args = 3, .category = .misc },
    .{ .name = "defined", .min_args = 1, .max_args = 1, .category = .misc },
    .{ .name = "constant", .min_args = 1, .max_args = 1, .category = .misc },
    .{ .name = "exit", .min_args = 0, .max_args = 1, .category = .misc },
    .{ .name = "die", .min_args = 0, .max_args = 1, .category = .misc },
    .{ .name = "sleep", .min_args = 1, .max_args = 1, .category = .datetime },
    .{ .name = "usleep", .min_args = 1, .max_args = 1, .category = .datetime },
    .{ .name = "uniqid", .min_args = 0, .max_args = 2, .category = .string },
    .{ .name = "sys_get_temp_dir", .min_args = 0, .max_args = 0, .category = .misc },
    .{ .name = "php_uname", .min_args = 0, .max_args = 1, .category = .misc },
    .{ .name = "phpversion", .min_args = 0, .max_args = 0, .category = .misc },
    // Extra misc functions from builtin_vars.zig
    .{ .name = "ini_get", .min_args = 1, .max_args = 1, .category = .variable },
    .{ .name = "ini_set", .min_args = 2, .max_args = 2, .category = .variable },
    .{ .name = "ini_restore", .min_args = 1, .max_args = 1, .category = .variable },
    .{ .name = "parse_url", .min_args = 1, .max_args = 2, .category = .variable },
    .{ .name = "register_shutdown_function", .min_args = 1, .max_args = 255, .category = .variable },
    .{ .name = "register_tick_function", .min_args = 1, .max_args = 255, .category = .variable },
    .{ .name = "unregister_tick_function", .min_args = 1, .max_args = 1, .category = .variable },
    .{ .name = "get_loaded_extensions", .min_args = 0, .max_args = 0, .category = .variable },
    .{ .name = "extension_loaded", .min_args = 1, .max_args = 1, .category = .variable },

    // ========================================================================
    // HTTP Functions (BuiltinId 450-469)
    // ========================================================================
    .{ .name = "header", .min_args = 1, .max_args = 3, .category = .http },
    .{ .name = "http_response_code", .min_args = 0, .max_args = 1, .category = .http },

    // ========================================================================
    // IO Functions (BuiltinId 470-499)
    // ========================================================================
    // (reserved for future I/O-specific functions)

    // ========================================================================
    // PHP 8.5 URI Functions
    // ========================================================================
    .{ .name = "uri_parse", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "uri_build", .min_args = 1, .max_args = 1, .category = .string },
    .{ .name = "uri_resolve", .min_args = 2, .max_args = 2, .category = .string },
};

// ============================================================================
// Comptime 验证
// ============================================================================

// 编译时验证：确保没有重复的函数名
comptime {
    @setEvalBranchQuota(FN_TABLE.len * FN_TABLE.len * 20 + 1000);
    var i: usize = 0;
    while (i < FN_TABLE.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < FN_TABLE.len) : (j += 1) {
            if (std.mem.eql(u8, FN_TABLE[i].name, FN_TABLE[j].name)) {
                @compileError("Duplicate function name in FN_TABLE: " ++ FN_TABLE[i].name);
            }
        }
    }
}

// 编译时验证：确保 FN_TABLE 非空
comptime {
    if (FN_TABLE.len == 0) {
        @compileError("FN_TABLE is empty — at least one function must be declared");
    }
}

/// 编译时辅助：按名称查找函数条目
pub fn lookupByName(comptime name: []const u8) ?FnEntry {
    for (FN_TABLE) |entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return entry;
        }
    }
    return null;
}

/// 编译时辅助：按分类获取函数数量
pub fn countByCategory(comptime cat: FnCategory) comptime_int {
    var count: comptime_int = 0;
    for (FN_TABLE) |entry| {
        if (entry.category == cat) {
            count += 1;
        }
    }
    return count;
}

/// 编译时辅助：获取所有函数名列表
pub const ALL_FUNCTION_NAMES = blk: {
    var names: [FN_TABLE.len][]const u8 = undefined;
    for (FN_TABLE, 0..) |entry, i| {
        names[i] = entry.name;
    }
    break :blk names;
};

/// 编译时统计：每个分类的函数数量
pub const CATEGORY_COUNTS = struct {
    pub const array = countByCategory(.array);
    pub const string = countByCategory(.string);
    pub const math = countByCategory(.math);
    pub const file = countByCategory(.file);
    pub const datetime = countByCategory(.datetime);
    pub const json = countByCategory(.json);
    pub const hash = countByCategory(.hash);
    pub const preg = countByCategory(.preg);
    pub const random = countByCategory(.random);
    pub const type_ = countByCategory(.type_);
    pub const variable = countByCategory(.variable);
    pub const class = countByCategory(.class);
    pub const error_ = countByCategory(.error_);
    pub const misc = countByCategory(.misc);
    pub const http = countByCategory(.http);
    pub const io = countByCategory(.io);
};

// ============================================================================
// Tests
// ============================================================================

test "FN_TABLE has no duplicate names" {
    // comptime validation already covers this, but runtime test for completeness
    var i: usize = 0;
    while (i < FN_TABLE.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < FN_TABLE.len) : (j += 1) {
            try std.testing.expect(!std.mem.eql(u8, FN_TABLE[i].name, FN_TABLE[j].name));
        }
    }
}

test "FN_TABLE total count matches sum of categories" {
    const total = CATEGORY_COUNTS.array +
        CATEGORY_COUNTS.string +
        CATEGORY_COUNTS.math +
        CATEGORY_COUNTS.file +
        CATEGORY_COUNTS.datetime +
        CATEGORY_COUNTS.json +
        CATEGORY_COUNTS.hash +
        CATEGORY_COUNTS.preg +
        CATEGORY_COUNTS.random +
        CATEGORY_COUNTS.type_ +
        CATEGORY_COUNTS.variable +
        CATEGORY_COUNTS.class +
        CATEGORY_COUNTS.error_ +
        CATEGORY_COUNTS.misc +
        CATEGORY_COUNTS.http +
        CATEGORY_COUNTS.io;
    try std.testing.expectEqual(@as(usize, FN_TABLE.len), total);
}

test "lookupByName works for known functions" {
    try std.testing.expect(lookupByName("strlen") != null);
    try std.testing.expect(lookupByName("count") != null);
    try std.testing.expect(lookupByName("nonexistent_function") == null);
}

test "lookupByName returns correct metadata" {
    const strlen_entry = lookupByName("strlen").?;
    try std.testing.expectEqualStrings("strlen", strlen_entry.name);
    try std.testing.expectEqual(@as(u8, 1), strlen_entry.min_args);
    try std.testing.expectEqual(@as(u8, 1), strlen_entry.max_args);
    try std.testing.expect(strlen_entry.category == .string);

    const array_map_entry = lookupByName("array_map").?;
    try std.testing.expectEqual(@as(u8, 2), array_map_entry.min_args);
    try std.testing.expectEqual(@as(u8, 255), array_map_entry.max_args);
    try std.testing.expect(array_map_entry.category == .array);
}

test "ALL_FUNCTION_NAMES contains all entries" {
    try std.testing.expectEqual(@as(usize, FN_TABLE.len), ALL_FUNCTION_NAMES.len);
}
