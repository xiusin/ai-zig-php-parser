const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const builtin_io = @import("builtin_io.zig");
const builtin_random = @import("builtin_random.zig");
const builtin_vars = @import("builtin_vars.zig");
const pcre2 = @import("pcre2.zig");

// 核心函数模块（DRY 原则：统一实现）
const core_string = @import("core/string_functions.zig");
const core_math = @import("core/math_functions.zig");
const core_time = @import("core/time_functions.zig");
const core_type = @import("core/type_functions.zig");

// SIMD optimized string operations for performance
const simd_ops = @import("simd_ops.zig");
const SimdString = simd_ops.SimdString;

// Forward declaration for VM
const VM = @import("vm.zig").VM;
const builtin_dispatch = @import("builtin_dispatch.zig");

// Helper function to create string return value (inline for performance)
inline fn createStringReturn(allocator: std.mem.Allocator, str: *PHPString) !Value {
    const box = try allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = str,
    };
    return Value.fromBox(box, Value.TYPE_STRING);
}

pub const BuiltinFunction = struct {
    name: []const u8,
    min_args: u8,
    max_args: u8, // 255 means unlimited
    handler: *const fn (*VM, []const Value) anyerror!Value,

    pub fn call(self: *const BuiltinFunction, vm: *VM, args: []const Value) !Value {
        // Validate argument count
        if (args.len < self.min_args) {
            const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, self.min_args, @intCast(args.len), self.name, "builtin", 0);
            _ = try vm.throwException(exception);
            return error.ArgumentCountMismatch;
        }

        if (self.max_args != 255 and args.len > self.max_args) {
            const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, self.max_args, @intCast(args.len), self.name, "builtin", 0);
            _ = try vm.throwException(exception);
            return error.ArgumentCountMismatch;
        }

        return self.handler(vm, args);
    }
};

pub const StandardLibrary = struct {
    functions: std.StringHashMap(*const BuiltinFunction),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !StandardLibrary {
        var stdlib = StandardLibrary{
            .functions = std.StringHashMap(*const BuiltinFunction).init(allocator),
            .allocator = allocator,
        };

        // Register all function groups
        try stdlib.registerArrayFunctions();
        try stdlib.registerStringFunctions();
        try stdlib.registerMathFunctions();
        try stdlib.registerFileFunctions();
        try stdlib.registerDateTimeFunctions();
        try stdlib.registerJsonFunctions();
        try stdlib.registerHashFunctions();
        try stdlib.registerPregFunctions();
        try stdlib.registerRandomFunctions();

        // Register PHP 8.5 URI functions
        const php85 = @import("php85_features.zig");
        try php85.registerUriFunctions(&stdlib);

        // Register extended functions
        const stdlib_ext = @import("stdlib_ext.zig");
        try stdlib_ext.registerExtendedFunctions(&stdlib);

        // Register variable/class/constant functions
        try builtin_vars.registerVariableFunctions(&stdlib);

        return stdlib;
    }

    pub fn deinit(self: *StandardLibrary) void {
        self.functions.deinit();
    }

    pub fn registerFunction(self: *StandardLibrary, name: []const u8, func: *const BuiltinFunction) !void {
        try self.functions.put(name, func);
    }

    pub fn getFunction(self: *StandardLibrary, name: []const u8) ?*const BuiltinFunction {
        return self.functions.get(name);
    }

    pub fn callBuiltinFast(vm: *VM, name: []const u8, args: []const Value) anyerror!?Value {
        const id = builtin_dispatch.lookup(name) orelse return null;

        const b_strlen: BuiltinFunction = .{ .name = "strlen", .min_args = 1, .max_args = 1, .handler = strlenFn };
        const b_count: BuiltinFunction = .{ .name = "count", .min_args = 1, .max_args = 2, .handler = countFn };
        const b_sizeof: BuiltinFunction = .{ .name = "sizeof", .min_args = 1, .max_args = 2, .handler = countFn };
        const b_strpos: BuiltinFunction = .{ .name = "strpos", .min_args = 2, .max_args = 3, .handler = strposFn };
        const b_stripos: BuiltinFunction = .{ .name = "stripos", .min_args = 2, .max_args = 3, .handler = striposFn };
        const b_substr: BuiltinFunction = .{ .name = "substr", .min_args = 2, .max_args = 3, .handler = substrFn };
        const b_strtolower: BuiltinFunction = .{ .name = "strtolower", .min_args = 1, .max_args = 1, .handler = strtolowerFn };
        const b_strtoupper: BuiltinFunction = .{ .name = "strtoupper", .min_args = 1, .max_args = 1, .handler = strtoupperFn };
        const b_trim: BuiltinFunction = .{ .name = "trim", .min_args = 1, .max_args = 2, .handler = trimFn };
        const b_ltrim: BuiltinFunction = .{ .name = "ltrim", .min_args = 1, .max_args = 2, .handler = ltrimFn };
        const b_rtrim: BuiltinFunction = .{ .name = "rtrim", .min_args = 1, .max_args = 2, .handler = rtrimFn };
        const b_array_map: BuiltinFunction = .{ .name = "array_map", .min_args = 2, .max_args = 255, .handler = arrayMapFn };
        const b_array_filter: BuiltinFunction = .{ .name = "array_filter", .min_args = 1, .max_args = 3, .handler = arrayFilterFn };
        const b_array_reduce: BuiltinFunction = .{ .name = "array_reduce", .min_args = 2, .max_args = 3, .handler = arrayReduceFn };
        const b_json_encode: BuiltinFunction = .{ .name = "json_encode", .min_args = 1, .max_args = 3, .handler = jsonEncodeFn };
        const b_json_decode: BuiltinFunction = .{ .name = "json_decode", .min_args = 1, .max_args = 4, .handler = jsonDecodeFn };
        const b_json_last_error: BuiltinFunction = .{ .name = "json_last_error", .min_args = 0, .max_args = 0, .handler = jsonLastErrorFn };
        const b_json_last_error_msg: BuiltinFunction = .{ .name = "json_last_error_msg", .min_args = 0, .max_args = 0, .handler = jsonLastErrorMsgFn };
        const b_echo: BuiltinFunction = .{ .name = "echo", .min_args = 1, .max_args = 255, .handler = echoFn };

        const result = switch (id) {
            .strlen => try b_strlen.call(vm, args),
            .count => try b_count.call(vm, args),
            .sizeof => try b_sizeof.call(vm, args),
            .strpos => try b_strpos.call(vm, args),
            .stripos => try b_stripos.call(vm, args),
            .substr => try b_substr.call(vm, args),
            .strtolower => try b_strtolower.call(vm, args),
            .strtoupper => try b_strtoupper.call(vm, args),
            .trim => try b_trim.call(vm, args),
            .ltrim => try b_ltrim.call(vm, args),
            .rtrim => try b_rtrim.call(vm, args),
            .array_map => try b_array_map.call(vm, args),
            .array_filter => try b_array_filter.call(vm, args),
            .array_reduce => try b_array_reduce.call(vm, args),
            .json_encode => try b_json_encode.call(vm, args),
            .json_decode => try b_json_decode.call(vm, args),
            .json_last_error => try b_json_last_error.call(vm, args),
            .json_last_error_msg => try b_json_last_error_msg.call(vm, args),
            .echo => try b_echo.call(vm, args),
            else => return null,
        };

        return result;
    }

    // Array Functions
    pub fn registerArrayFunctions(self: *StandardLibrary) !void {
        const array_functions = [_]*const BuiltinFunction{
            &.{ .name = "array_map", .min_args = 2, .max_args = 255, .handler = arrayMapFn },
            &.{ .name = "array_filter", .min_args = 1, .max_args = 3, .handler = arrayFilterFn },
            &.{ .name = "array_reduce", .min_args = 2, .max_args = 3, .handler = arrayReduceFn },
            &.{ .name = "array_merge", .min_args = 1, .max_args = 255, .handler = arrayMergeFn },
            &.{ .name = "array_keys", .min_args = 1, .max_args = 1, .handler = arrayKeysFn },
            &.{ .name = "array_values", .min_args = 1, .max_args = 1, .handler = arrayValuesFn },
            &.{ .name = "array_push", .min_args = 2, .max_args = 255, .handler = arrayPushFn },
            &.{ .name = "array_pop", .min_args = 1, .max_args = 1, .handler = arrayPopFn },
            &.{ .name = "array_shift", .min_args = 1, .max_args = 1, .handler = arrayShiftFn },
            &.{ .name = "array_unshift", .min_args = 2, .max_args = 255, .handler = arrayUnshiftFn },
            &.{ .name = "in_array", .min_args = 2, .max_args = 3, .handler = inArrayFn },
            &.{ .name = "array_search", .min_args = 2, .max_args = 3, .handler = arraySearchFn },
            // PHP 8.5 new array functions
            &.{ .name = "array_first", .min_args = 1, .max_args = 2, .handler = arrayFirstFn },
            &.{ .name = "array_last", .min_args = 1, .max_args = 2, .handler = arrayLastFn },
            // Additional array functions
            &.{ .name = "array_sum", .min_args = 1, .max_args = 1, .handler = arraySumFn },
            &.{ .name = "array_product", .min_args = 1, .max_args = 1, .handler = arrayProductFn },
            &.{ .name = "array_reverse", .min_args = 1, .max_args = 2, .handler = arrayReverseFn },
            &.{ .name = "array_unique", .min_args = 1, .max_args = 2, .handler = arrayUniqueFn },
            &.{ .name = "array_flip", .min_args = 1, .max_args = 1, .handler = arrayFlipFn },
            &.{ .name = "array_slice", .min_args = 2, .max_args = 4, .handler = arraySliceFn },
            &.{ .name = "array_column", .min_args = 2, .max_args = 3, .handler = arrayColumnFn },
            &.{ .name = "range", .min_args = 2, .max_args = 3, .handler = rangeFunction },
            &.{ .name = "array_fill", .min_args = 3, .max_args = 3, .handler = arrayFillFn },
            &.{ .name = "compact", .min_args = 1, .max_args = 255, .handler = compactFn },
            &.{ .name = "sort", .min_args = 1, .max_args = 2, .handler = sortFn },
            &.{ .name = "rsort", .min_args = 1, .max_args = 2, .handler = rsortFn },
            &.{ .name = "asort", .min_args = 1, .max_args = 2, .handler = asortFn },
            &.{ .name = "arsort", .min_args = 1, .max_args = 2, .handler = arsortFn },
            &.{ .name = "ksort", .min_args = 1, .max_args = 2, .handler = ksortFn },
            &.{ .name = "krsort", .min_args = 1, .max_args = 2, .handler = krsortFn },
            &.{ .name = "usort", .min_args = 2, .max_args = 2, .handler = usortFn },
            &.{ .name = "count", .min_args = 1, .max_args = 2, .handler = countFn },
            &.{ .name = "sizeof", .min_args = 1, .max_args = 2, .handler = countFn },
            &.{ .name = "array_key_exists", .min_args = 2, .max_args = 2, .handler = arrayKeyExistsFn },
            &.{ .name = "array_combine", .min_args = 2, .max_args = 2, .handler = arrayCombineFn },
            &.{ .name = "array_intersect", .min_args = 2, .max_args = 255, .handler = arrayIntersectFn },
            &.{ .name = "array_splice", .min_args = 2, .max_args = 4, .handler = arraySpliceFn },
            &.{ .name = "array_walk", .min_args = 2, .max_args = 3, .handler = arrayWalkFn },
            &.{ .name = "array_chunk", .min_args = 2, .max_args = 3, .handler = arrayChunkFn },
            &.{ .name = "array_pad", .min_args = 3, .max_args = 3, .handler = arrayPadFn },
            &.{ .name = "array_key_first", .min_args = 1, .max_args = 1, .handler = arrayKeyFirstFn },
            &.{ .name = "array_key_last", .min_args = 1, .max_args = 1, .handler = arrayKeyLastFn },
            &.{ .name = "array_fill_keys", .min_args = 2, .max_args = 2, .handler = arrayFillKeysFn },
            &.{ .name = "array_change_key_case", .min_args = 1, .max_args = 2, .handler = arrayChangeKeyCaseFn },
            &.{ .name = "array_count_values", .min_args = 1, .max_args = 1, .handler = arrayCountValuesFn },
            &.{ .name = "array_rand", .min_args = 1, .max_args = 2, .handler = arrayRandWrapper },
            &.{ .name = "shuffle", .min_args = 1, .max_args = 1, .handler = shuffleWrapper },
            &.{ .name = "array_diff", .min_args = 2, .max_args = 255, .handler = arrayDiffFn },
            &.{ .name = "isset", .min_args = 1, .max_args = 255, .handler = issetFn },
            &.{ .name = "end", .min_args = 1, .max_args = 1, .handler = endFn },
            &.{ .name = "reset", .min_args = 1, .max_args = 1, .handler = resetFn },
            &.{ .name = "current", .min_args = 1, .max_args = 1, .handler = currentFn },
            &.{ .name = "key", .min_args = 1, .max_args = 1, .handler = keyFn },
            &.{ .name = "next", .min_args = 1, .max_args = 1, .handler = nextFn },
            &.{ .name = "prev", .min_args = 1, .max_args = 1, .handler = prevFn },
        };

        for (array_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // String Functions
    pub fn registerStringFunctions(self: *StandardLibrary) !void {
        const string_functions = [_]*const BuiltinFunction{
            &.{ .name = "echo", .min_args = 1, .max_args = 255, .handler = echoFn },
            &.{ .name = "strlen", .min_args = 1, .max_args = 1, .handler = strlenFn },
            &.{ .name = "substr", .min_args = 2, .max_args = 3, .handler = substrFn },
            &.{ .name = "str_replace", .min_args = 3, .max_args = 4, .handler = strReplaceFn },
            &.{ .name = "str_ireplace", .min_args = 3, .max_args = 4, .handler = strIreplaceFn },
            &.{ .name = "strpos", .min_args = 2, .max_args = 3, .handler = strposFn },
            &.{ .name = "stripos", .min_args = 2, .max_args = 3, .handler = striposFn },
            &.{ .name = "strrpos", .min_args = 2, .max_args = 3, .handler = strrposFn },
            &.{ .name = "strripos", .min_args = 2, .max_args = 3, .handler = strriposFn },
            &.{ .name = "strtolower", .min_args = 1, .max_args = 1, .handler = strtolowerFn },
            &.{ .name = "strtoupper", .min_args = 1, .max_args = 1, .handler = strtoupperFn },
            &.{ .name = "trim", .min_args = 1, .max_args = 2, .handler = trimFn },
            &.{ .name = "ltrim", .min_args = 1, .max_args = 2, .handler = ltrimFn },
            &.{ .name = "rtrim", .min_args = 1, .max_args = 2, .handler = rtrimFn },
            &.{ .name = "explode", .min_args = 2, .max_args = 3, .handler = explodeFn },
            &.{ .name = "implode", .min_args = 2, .max_args = 2, .handler = implodeFn },
            &.{ .name = "str_repeat", .min_args = 2, .max_args = 2, .handler = strRepeatFn },
            // Additional string functions
            &.{ .name = "sprintf", .min_args = 1, .max_args = 255, .handler = sprintfFn },
            &.{ .name = "printf", .min_args = 1, .max_args = 255, .handler = printfFn },
            &.{ .name = "str_contains", .min_args = 2, .max_args = 2, .handler = strContainsFn },
            &.{ .name = "str_starts_with", .min_args = 2, .max_args = 2, .handler = strStartsWithFn },
            &.{ .name = "str_ends_with", .min_args = 2, .max_args = 2, .handler = strEndsWithFn },
            &.{ .name = "ucfirst", .min_args = 1, .max_args = 1, .handler = ucfirstFn },
            &.{ .name = "lcfirst", .min_args = 1, .max_args = 1, .handler = lcfirstFn },
            &.{ .name = "ucwords", .min_args = 1, .max_args = 2, .handler = ucwordsFn },
            &.{ .name = "str_pad", .min_args = 2, .max_args = 4, .handler = strPadFn },
            &.{ .name = "strrev", .min_args = 1, .max_args = 1, .handler = strrevFn },
            &.{ .name = "str_split", .min_args = 1, .max_args = 2, .handler = strSplitFn },
            &.{ .name = "chunk_split", .min_args = 1, .max_args = 3, .handler = chunkSplitFn },
            &.{ .name = "wordwrap", .min_args = 1, .max_args = 4, .handler = wordwrapFn },
            &.{ .name = "nl2br", .min_args = 1, .max_args = 2, .handler = nl2brFn },
            &.{ .name = "strip_tags", .min_args = 1, .max_args = 2, .handler = stripTagsFn },
            &.{ .name = "htmlspecialchars", .min_args = 1, .max_args = 4, .handler = htmlspecialcharsFn },
            &.{ .name = "htmlentities", .min_args = 1, .max_args = 4, .handler = htmlentitiesFn },
            &.{ .name = "number_format", .min_args = 1, .max_args = 4, .handler = numberFormatFn },
            &.{ .name = "bin2hex", .min_args = 1, .max_args = 1, .handler = bin2hexFn },
            &.{ .name = "hex2bin", .min_args = 1, .max_args = 1, .handler = hex2binFn },
            &.{ .name = "base64_encode", .min_args = 1, .max_args = 1, .handler = base64EncodeFn },
            &.{ .name = "base64_decode", .min_args = 1, .max_args = 2, .handler = base64DecodeFn },
            &.{ .name = "md5", .min_args = 1, .max_args = 2, .handler = md5Fn },
            &.{ .name = "sha1", .min_args = 1, .max_args = 2, .handler = sha1Fn },
            &.{ .name = "uniqid", .min_args = 0, .max_args = 2, .handler = uniqidFn },
            &.{ .name = "ord", .min_args = 1, .max_args = 1, .handler = ordFn },
            &.{ .name = "chr", .min_args = 1, .max_args = 1, .handler = chrFn },
            // Serialization functions
            &.{ .name = "serialize", .min_args = 1, .max_args = 1, .handler = serializeFn },
            &.{ .name = "unserialize", .min_args = 1, .max_args = 2, .handler = unserializeFn },
            // Debug functions
            &.{ .name = "var_dump", .min_args = 1, .max_args = 255, .handler = varDumpFn },
            &.{ .name = "print_r", .min_args = 1, .max_args = 2, .handler = printRFn },
            &.{ .name = "var_export", .min_args = 1, .max_args = 2, .handler = varExportFn },
            // Type functions
            &.{ .name = "gettype", .min_args = 1, .max_args = 1, .handler = gettypeFn },
            &.{ .name = "settype", .min_args = 2, .max_args = 2, .handler = settypeFn },
            &.{ .name = "is_null", .min_args = 1, .max_args = 1, .handler = isNullFn },
            &.{ .name = "is_bool", .min_args = 1, .max_args = 1, .handler = isBoolFn },
            &.{ .name = "is_int", .min_args = 1, .max_args = 1, .handler = isIntFn },
            &.{ .name = "is_integer", .min_args = 1, .max_args = 1, .handler = isIntFn },
            &.{ .name = "is_float", .min_args = 1, .max_args = 1, .handler = isFloatFn },
            &.{ .name = "is_double", .min_args = 1, .max_args = 1, .handler = isFloatFn },
            &.{ .name = "is_string", .min_args = 1, .max_args = 1, .handler = isStringFn },
            &.{ .name = "is_array", .min_args = 1, .max_args = 1, .handler = isArrayFn },
            &.{ .name = "is_object", .min_args = 1, .max_args = 1, .handler = isObjectFn },
            &.{ .name = "is_numeric", .min_args = 1, .max_args = 1, .handler = isNumericFn },
            &.{ .name = "is_scalar", .min_args = 1, .max_args = 1, .handler = isScalarFn },
            &.{ .name = "is_resource", .min_args = 1, .max_args = 1, .handler = isResourceFn },
            &.{ .name = "isset", .min_args = 1, .max_args = 255, .handler = issetFn },
            // Cast functions
            &.{ .name = "intval", .min_args = 1, .max_args = 2, .handler = intvalFn },
            &.{ .name = "floatval", .min_args = 1, .max_args = 1, .handler = floatvalFn },
            &.{ .name = "strval", .min_args = 1, .max_args = 1, .handler = strvalFn },
            &.{ .name = "boolval", .min_args = 1, .max_args = 1, .handler = boolvalFn },
            // HTTP functions
            &.{ .name = "header", .min_args = 1, .max_args = 3, .handler = headerFn },
            &.{ .name = "http_response_code", .min_args = 0, .max_args = 1, .handler = httpResponseCodeFn },
            &.{ .name = "exit", .min_args = 0, .max_args = 1, .handler = exitFn },
            &.{ .name = "die", .min_args = 0, .max_args = 1, .handler = exitFn },
        };

        for (string_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // Math Functions
    pub fn registerMathFunctions(self: *StandardLibrary) !void {
        const math_functions = [_]*const BuiltinFunction{
            &.{ .name = "abs", .min_args = 1, .max_args = 1, .handler = absFn },
            &.{ .name = "round", .min_args = 1, .max_args = 2, .handler = roundFn },
            &.{ .name = "sqrt", .min_args = 1, .max_args = 1, .handler = sqrtFn },
            &.{ .name = "pow", .min_args = 2, .max_args = 2, .handler = powFn },
            &.{ .name = "floor", .min_args = 1, .max_args = 1, .handler = floorFn },
            &.{ .name = "ceil", .min_args = 1, .max_args = 1, .handler = ceilFn },
            &.{ .name = "min", .min_args = 1, .max_args = 255, .handler = minFn },
            &.{ .name = "max", .min_args = 1, .max_args = 255, .handler = maxFn },
            &.{ .name = "rand", .min_args = 0, .max_args = 2, .handler = randFn },
            &.{ .name = "mt_rand", .min_args = 0, .max_args = 2, .handler = mtRandFn },
            // 位运算函数
            &.{ .name = "bit_and", .min_args = 2, .max_args = 2, .handler = bitAndFn },
            &.{ .name = "bit_or", .min_args = 2, .max_args = 2, .handler = bitOrFn },
            &.{ .name = "bit_xor", .min_args = 2, .max_args = 2, .handler = bitXorFn },
            &.{ .name = "bit_not", .min_args = 1, .max_args = 1, .handler = bitNotFn },
            &.{ .name = "bit_shift_left", .min_args = 2, .max_args = 2, .handler = bitShiftLeftFn },
            &.{ .name = "bit_shift_right", .min_args = 2, .max_args = 2, .handler = bitShiftRightFn },
            // 更多数学函数
            &.{ .name = "sin", .min_args = 1, .max_args = 1, .handler = sinFn },
            &.{ .name = "cos", .min_args = 1, .max_args = 1, .handler = cosFn },
            &.{ .name = "tan", .min_args = 1, .max_args = 1, .handler = tanFn },
            &.{ .name = "log", .min_args = 1, .max_args = 2, .handler = logFn },
            &.{ .name = "log10", .min_args = 1, .max_args = 1, .handler = log10Fn },
            &.{ .name = "exp", .min_args = 1, .max_args = 1, .handler = expFn },
            &.{ .name = "pi", .min_args = 0, .max_args = 0, .handler = piFn },
            &.{ .name = "deg2rad", .min_args = 1, .max_args = 1, .handler = deg2radFn },
            &.{ .name = "rad2deg", .min_args = 1, .max_args = 1, .handler = rad2degFn },
            &.{ .name = "asin", .min_args = 1, .max_args = 1, .handler = asinFn },
            &.{ .name = "acos", .min_args = 1, .max_args = 1, .handler = acosFn },
            &.{ .name = "atan", .min_args = 1, .max_args = 1, .handler = atanFn },
            &.{ .name = "atan2", .min_args = 2, .max_args = 2, .handler = atan2Fn },
            &.{ .name = "hypot", .min_args = 2, .max_args = 2, .handler = hypotFn },
            &.{ .name = "fmod", .min_args = 2, .max_args = 2, .handler = fmodFn },
        };

        for (math_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // File Functions
    pub fn registerFileFunctions(self: *StandardLibrary) !void {
        const file_functions = [_]*const BuiltinFunction{
            // Basic file operations
            &.{ .name = "file_get_contents", .min_args = 1, .max_args = 5, .handler = builtin_io.fileGetContentsFn },
            &.{ .name = "file_put_contents", .min_args = 2, .max_args = 4, .handler = builtin_io.filePutContentsFn },
            &.{ .name = "file_exists", .min_args = 1, .max_args = 1, .handler = builtin_io.fileExistsFn },
            &.{ .name = "is_file", .min_args = 1, .max_args = 1, .handler = builtin_io.isFileFn },
            &.{ .name = "is_dir", .min_args = 1, .max_args = 1, .handler = builtin_io.isDirFn },
            &.{ .name = "filesize", .min_args = 1, .max_args = 1, .handler = builtin_io.filesizeFn },
            &.{ .name = "filemtime", .min_args = 1, .max_args = 1, .handler = builtin_io.filemtimeFn },

            // File reading/writing
            &.{ .name = "file", .min_args = 1, .max_args = 3, .handler = builtin_io.fileFn },
            &.{ .name = "readfile", .min_args = 1, .max_args = 3, .handler = builtin_io.readfileFn },

            // File management
            &.{ .name = "unlink", .min_args = 1, .max_args = 1, .handler = builtin_io.unlinkFn },
            &.{ .name = "rename", .min_args = 2, .max_args = 2, .handler = builtin_io.renameFn },
            &.{ .name = "copy", .min_args = 2, .max_args = 3, .handler = builtin_io.copyFn },
            &.{ .name = "flock", .min_args = 2, .max_args = 2, .handler = builtin_io.flockFn },
            &.{ .name = "ftruncate", .min_args = 2, .max_args = 2, .handler = builtin_io.ftruncateFn },

            // File permission checks
            &.{ .name = "is_readable", .min_args = 1, .max_args = 1, .handler = builtin_io.isReadableFn },
            &.{ .name = "is_writable", .min_args = 1, .max_args = 1, .handler = builtin_io.isWritableFn },
            &.{ .name = "is_executable", .min_args = 1, .max_args = 1, .handler = builtin_io.isExecutableFn },

            // Stat/cache functions
            &.{ .name = "clearstatcache", .min_args = 0, .max_args = 255, .handler = builtin_io.clearstatcacheFn },
            &.{ .name = "disk_free_space", .min_args = 1, .max_args = 1, .handler = builtin_io.diskFreeSpaceFn },
            &.{ .name = "disk_total_space", .min_args = 1, .max_args = 1, .handler = builtin_io.diskTotalSpaceFn },

            // File operations (new)
            &.{ .name = "is_link", .min_args = 1, .max_args = 1, .handler = builtin_io.isLinkFn },
            &.{ .name = "chmod", .min_args = 2, .max_args = 2, .handler = builtin_io.chmodFn },
            &.{ .name = "chown", .min_args = 2, .max_args = 2, .handler = builtin_io.chownFn },
            &.{ .name = "chgrp", .min_args = 2, .max_args = 2, .handler = builtin_io.chgrpFn },
            &.{ .name = "link", .min_args = 2, .max_args = 2, .handler = builtin_io.linkFn },
            &.{ .name = "symlink", .min_args = 2, .max_args = 2, .handler = builtin_io.symlinkFn },
            &.{ .name = "readlink", .min_args = 1, .max_args = 1, .handler = builtin_io.readlinkFn },
            &.{ .name = "lstat", .min_args = 1, .max_args = 1, .handler = builtin_io.lstatFn },
            &.{ .name = "stat", .min_args = 1, .max_args = 1, .handler = builtin_io.statFn },
            &.{ .name = "fnmatch", .min_args = 2, .max_args = 3, .handler = builtin_io.fnmatchFn },
            &.{ .name = "glob", .min_args = 1, .max_args = 2, .handler = builtin_io.globFn },

            // Directory operations
            &.{ .name = "mkdir", .min_args = 1, .max_args = 3, .handler = builtin_io.mkdirFn },
            &.{ .name = "rmdir", .min_args = 1, .max_args = 2, .handler = builtin_io.rmdirFn },
            &.{ .name = "scandir", .min_args = 1, .max_args = 2, .handler = builtin_io.scandirFn },

            // Path functions
            &.{ .name = "basename", .min_args = 1, .max_args = 2, .handler = builtin_io.basenameFn },
            &.{ .name = "dirname", .min_args = 1, .max_args = 2, .handler = builtin_io.dirnameFn },
            &.{ .name = "realpath", .min_args = 1, .max_args = 1, .handler = builtin_io.realpathFn },

            // File stream operations
            &.{ .name = "fopen", .min_args = 2, .max_args = 3, .handler = builtin_io.fopenFn },
            &.{ .name = "fclose", .min_args = 1, .max_args = 1, .handler = builtin_io.fcloseFn },
            &.{ .name = "fread", .min_args = 2, .max_args = 2, .handler = builtin_io.freadFn },
            &.{ .name = "fwrite", .min_args = 2, .max_args = 3, .handler = builtin_io.fwriteFn },
            &.{ .name = "feof", .min_args = 1, .max_args = 1, .handler = builtin_io.feofFn },
            &.{ .name = "fseek", .min_args = 2, .max_args = 3, .handler = builtin_io.fseekFn },
            &.{ .name = "ftell", .min_args = 1, .max_args = 1, .handler = builtin_io.ftellFn },
            &.{ .name = "fgets", .min_args = 1, .max_args = 2, .handler = builtin_io.fgetsFn },
            &.{ .name = "fgetc", .min_args = 1, .max_args = 1, .handler = builtin_io.fgetcFn },
            &.{ .name = "rewind", .min_args = 1, .max_args = 1, .handler = builtin_io.rewindFn },
            &.{ .name = "fflush", .min_args = 1, .max_args = 1, .handler = builtin_io.fflushFn },
        };

        for (file_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // Date/Time Functions
    pub fn registerDateTimeFunctions(self: *StandardLibrary) !void {
        const datetime_functions = [_]*const BuiltinFunction{
            &.{ .name = "time", .min_args = 0, .max_args = 0, .handler = timeFn },
            &.{ .name = "microtime", .min_args = 0, .max_args = 1, .handler = microtimeFn },
            &.{ .name = "date", .min_args = 1, .max_args = 2, .handler = dateFn },
            &.{ .name = "strtotime", .min_args = 1, .max_args = 2, .handler = strtotimeFn },
            &.{ .name = "mktime", .min_args = 0, .max_args = 6, .handler = mktimeFn },
            &.{ .name = "gmdate", .min_args = 1, .max_args = 2, .handler = gmdateFn },
            &.{ .name = "usleep", .min_args = 1, .max_args = 1, .handler = usleepFn },
            &.{ .name = "sleep", .min_args = 1, .max_args = 1, .handler = sleepFn },
        };

        for (datetime_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // JSON Functions
    pub fn registerJsonFunctions(self: *StandardLibrary) !void {
        const json_functions = [_]*const BuiltinFunction{
            &.{ .name = "json_encode", .min_args = 1, .max_args = 3, .handler = jsonEncodeFn },
            &.{ .name = "json_decode", .min_args = 1, .max_args = 4, .handler = jsonDecodeFn },
            &.{ .name = "json_last_error", .min_args = 0, .max_args = 0, .handler = jsonLastErrorFn },
            &.{ .name = "json_last_error_msg", .min_args = 0, .max_args = 0, .handler = jsonLastErrorMsgFn },
        };

        for (json_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // Hash Functions
    pub fn registerHashFunctions(self: *StandardLibrary) !void {
        const hash_functions = [_]*const BuiltinFunction{
            &.{ .name = "md5", .min_args = 1, .max_args = 2, .handler = md5Fn },
            &.{ .name = "sha1", .min_args = 1, .max_args = 2, .handler = sha1Fn },
            &.{ .name = "sha256", .min_args = 1, .max_args = 2, .handler = sha256Fn },
            &.{ .name = "sha512", .min_args = 1, .max_args = 2, .handler = sha512Fn },
            &.{ .name = "hash", .min_args = 2, .max_args = 3, .handler = hashFn },
            &.{ .name = "hash_algos", .min_args = 0, .max_args = 0, .handler = hashAlgosFn },
        };

        for (hash_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // Regular Expression Functions (PCRE2)
    pub fn registerPregFunctions(self: *StandardLibrary) !void {
        const preg_functions = [_]*const BuiltinFunction{
            &.{ .name = "preg_match", .min_args = 2, .max_args = 5, .handler = pcre2.pregMatchFn },
            &.{ .name = "preg_match_all", .min_args = 2, .max_args = 5, .handler = pcre2.pregMatchAllFn },
            &.{ .name = "preg_replace", .min_args = 3, .max_args = 5, .handler = pcre2.pregReplaceFn },
            &.{ .name = "preg_filter", .min_args = 3, .max_args = 5, .handler = pcre2.pregFilterFn },
            &.{ .name = "preg_split", .min_args = 2, .max_args = 4, .handler = pcre2.pregSplitFn },
            &.{ .name = "preg_grep", .min_args = 2, .max_args = 3, .handler = pcre2.pregGrepFn },
            &.{ .name = "preg_quote", .min_args = 1, .max_args = 2, .handler = pcre2.pregQuoteFn },
            &.{ .name = "preg_last_error", .min_args = 0, .max_args = 0, .handler = pcre2.pregLastErrorFn },
        };

        for (preg_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // Random Functions
    pub fn registerRandomFunctions(self: *StandardLibrary) !void {
        const random_functions = [_]*const BuiltinFunction{
            &.{ .name = "shuffle", .min_args = 1, .max_args = 1, .handler = shuffleWrapper },
            &.{ .name = "array_rand", .min_args = 1, .max_args = 2, .handler = arrayRandWrapper },
        };

        for (random_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }
};

// Random function wrappers to handle type conversion
fn shuffleWrapper(vm: *VM, args: []const Value) !Value {
    return builtin_random.RandomBuiltins.shuffle(vm, args);
}

fn arrayRandWrapper(vm: *VM, args: []const Value) !Value {
    return builtin_random.RandomBuiltins.array_rand(vm, args);
}

// Fast path for callback invocation - optimized for array functions
// Skips call frame management and statistics for speed
inline fn invokeCallbackFast(vm: *VM, callback: Value, arg: Value) !Value {
    return switch (callback.getTag()) {
        .native_function => blk: {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            const args = [_]Value{arg};
            break :blk try function(vm, &args);
        },
        .closure => blk: {
            const closure = callback.getAsClosure().data;
            break :blk try vm.callClosureFast(closure, arg);
        },
        .arrow_function => blk: {
            const arrow_fn = callback.getAsArrowFunc().data;
            break :blk try vm.callArrowFunctionFast(arrow_fn, arg);
        },
        else => error.InvalidCallback,
    };
}

// 2-argument version for array_reduce
inline fn invokeCallbackFast2(vm: *VM, callback: Value, arg1: Value, arg2: Value) !Value {
    return switch (callback.getTag()) {
        .native_function => blk: {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            const args = [_]Value{ arg1, arg2 };
            break :blk try function(vm, &args);
        },
        .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, &[_]Value{ arg1, arg2 }),
        .closure => blk: {
            const closure = callback.getAsClosure().data;
            break :blk try vm.callClosureFast2(closure, arg1, arg2);
        },
        .arrow_function => blk: {
            const arrow_fn = callback.getAsArrowFunc().data;
            break :blk try vm.callArrowFunction(arrow_fn, &[_]Value{ arg1, arg2 });
        },
        else => error.InvalidCallback,
    };
}

// Helper function to invoke callback with 1-2 arguments
inline fn invokeCallback(vm: *VM, callback: Value, args: []const Value) !Value {
    return switch (callback.getTag()) {
        .native_function => blk: {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            break :blk try function(vm, args);
        },
        .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, args),
        .closure => try vm.callClosure(callback.getAsClosure().data, args),
        .arrow_function => try vm.callArrowFunction(callback.getAsArrowFunc().data, args),
        else => error.InvalidCallback,
    };
}

// Array Function Implementations
fn arrayMapFn(vm: *VM, args: []const Value) !Value {
    const callback = args[0];
    const array = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_map() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(count);

    var iterator = source_array.getElements().iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        // Use fast callback for native functions, closures, arrow functions
        const result_value = invokeCallbackFast(vm, callback, value) catch {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_map() expects parameter 1 to be a valid callback", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        };

        result_array.getElements().putAssumeCapacity(key, result_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayFilterFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_filter() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(count);

    const callback = if (args.len > 1) args[1] else null;

    var iterator = source_array.getElements().iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        var should_include = false;

        if (callback) |cb| {
            const result_value = invokeCallbackFast(vm, cb, value) catch {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_filter() expects parameter 2 to be a valid callback", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidArgumentType;
            };
            should_include = result_value.toBool();
        } else {
            should_include = value.toBool();
        }

        if (should_include) {
            result_array.getElements().putAssumeCapacity(key, value);
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayReduceFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];
    const initial = if (args.len > 2) args[2] else Value.initNull();

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_reduce() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var accumulator = initial;

    var iterator = array.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        accumulator = invokeCallbackFast2(vm, callback, accumulator, value) catch {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_reduce() expects parameter 2 to be a valid callback", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        };
    }

    return accumulator;
}

fn arrayMergeFn(vm: *VM, args: []const Value) !Value {
    // First pass: calculate total element count for pre-allocation
    var total_count: usize = 0;
    for (args) |arg| {
        if (arg.getTag() != .array) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_merge() expects all parameters to be arrays", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }
        total_count += arg.getAsArray().data.count();
    }

    if (total_count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_array,
        };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(total_count);

    // Second pass: merge all arrays with direct insertion
    for (args) |arg| {
        var iterator = arg.getAsArray().data.getElements().iterator();
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Direct insertion - retain value and put
            _ = value.retain();
            switch (key) {
                .integer => {
                    const dest_key = ArrayKey{ .integer = result_array.next_index };
                    result_array.next_index += 1;
                    result_array.getElements().putAssumeCapacity(dest_key, value);
                },
                .string => |s| {
                    // Retain string key
                    const new_key = ArrayKey{ .string = s };
                    new_key.string.retain();
                    result_array.getElements().putAssumeCapacity(new_key, value);
                },
            }
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayKeysFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_keys() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    if (count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_array,
        };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    // Pre-allocate result array
    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(count);

    var iterator = source_array.getElements().iterator();
    var idx: i64 = 0;
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;

        const key_value = switch (key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                const str = try PHPString.init(vm.allocator, s.data);
                const box = try vm.allocator.create(types.gc.Box(*PHPString));
                box.* = .{
                    .ref_count = 1,
                    .gc_info = .{},
                    .data = str,
                };
                break :blk Value.fromBox(box, Value.TYPE_STRING);
            },
        };

        // Direct insert with integer key
        const dest_key = ArrayKey{ .integer = idx };
        idx += 1;
        _ = key_value.retain();
        result_array.getElements().putAssumeCapacity(dest_key, key_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayValuesFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_values() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    if (count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_array,
        };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(count);

    // Direct insertion - avoid push overhead
    var iterator = source_array.getElements().iterator();
    var idx: i64 = 0;
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        _ = value.retain();
        const key = ArrayKey{ .integer = idx };
        idx += 1;
        result_array.getElements().putAssumeCapacity(key, value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayPushFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_push() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    // Push all additional arguments
    for (args[1..]) |value| {
        try php_array.push(vm.allocator, value);
    }

    return Value.initInt(@intCast(php_array.count()));
}

fn arrayPopFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_pop() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    if (php_array.count() == 0) {
        return Value.initNull();
    }

    // Find the last element (simplified implementation)
    var last_key: ?ArrayKey = null;
    var last_value: ?Value = null;

    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        last_key = entry.key_ptr.*;
        last_value = entry.value_ptr.*;
    }

    if (last_key) |key| {
        const result = last_value.?;
        _ = php_array.getElements().swapRemove(key);
        return result;
    }

    return Value.initNull();
}

fn arrayShiftFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_shift() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    if (php_array.count() == 0) {
        return Value.initNull();
    }

    // Find the first element (simplified implementation)
    var first_key: ?ArrayKey = null;
    var first_value: ?Value = null;

    var iterator = php_array.getElements().iterator();
    if (iterator.next()) |entry| {
        first_key = entry.key_ptr.*;
        first_value = entry.value_ptr.*;
    }

    if (first_key) |key| {
        const result = first_value.?;
        _ = php_array.getElements().swapRemove(key);
        return result;
    }

    return Value.initNull();
}

fn arrayUnshiftFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_unshift() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    // Create new array with unshifted elements
    var new_array = PHPArray.init(vm.allocator);

    // Add new elements first
    for (args[1..]) |value| {
        try new_array.push(vm.allocator, value);
    }

    // Add existing elements
    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        try new_array.push(vm.allocator, value);
    }

    // Replace the original array's contents by copying from new_array
    // First clear the old array
    php_array.getElements().clearRetainingCapacity();

    // Copy elements from new_array
    var new_iter = new_array.getElements().iterator();
    while (new_iter.next()) |entry| {
        try php_array.set(vm.allocator, entry.key_ptr.*, entry.value_ptr.*);
    }
    php_array.next_index = new_array.next_index;

    return Value.initInt(@intCast(php_array.count()));
}

fn inArrayFn(vm: *VM, args: []const Value) !Value {
    const needle = args[0];
    const haystack = args[1];
    const strict = if (args.len > 2) args[2].toBool() else false;

    if (haystack.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "in_array() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Fast path: if needle is already a string and we're not in strict mode,
    // we can avoid repeated conversions
    const needle_is_string = needle.getTag() == .string;
    var needle_str: ?*types.PHPString = null;
    defer if (needle_str) |s| s.release(vm.allocator);

    if (!strict and needle_is_string) {
        needle_str = needle.getAsString().data;
        needle_str.?.retain();
    }

    var iterator = haystack.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        if (strict) {
            // Strict comparison (type and value)
            if (needle.getTag() == value.getTag()) {
                const is_equal = switch (needle.getTag()) {
                    .null => true,
                    .boolean => needle.asBool() == value.asBool(),
                    .integer => needle.asInt() == value.asInt(),
                    .float => needle.asFloat() == value.asFloat(),
                    .string => std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data),
                    else => false, // Simplified for other types
                };
                if (is_equal) return Value.initBool(true);
            }
        } else {
            // Loose comparison - optimized path
            if (value.getTag() == needle.getTag()) {
                // Same type - can compare directly without conversion
                const is_equal = switch (needle.getTag()) {
                    .null => true,
                    .boolean => needle.asBool() == value.asBool(),
                    .integer => needle.asInt() == value.asInt(),
                    .float => needle.asFloat() == value.asFloat(),
                    .string => std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data),
                    else => false,
                };
                if (is_equal) return Value.initBool(true);
            } else if (needle_is_string and value.getTag() == .string) {
                // Both are strings - direct comparison
                if (std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data)) {
                    return Value.initBool(true);
                }
            } else {
                // Type mismatch - need conversion for comparison
                const needle_str_val = needle_str orelse needle: {
                    const s = try needle.toString(vm.allocator);
                    needle_str = s;
                    break :needle s;
                };
                const value_str = try value.toString(vm.allocator);
                defer value_str.deinit(vm.allocator);

                if (std.mem.eql(u8, needle_str_val.data, value_str.data)) {
                    return Value.initBool(true);
                }
            }
        }
    }

    return Value.initBool(false);
}

fn arraySearchFn(vm: *VM, args: []const Value) !Value {
    const needle = args[0];
    const haystack = args[1];
    const strict = if (args.len > 2) args[2].toBool() else false;

    if (haystack.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_search() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Fast path: if needle is already a string and we're not in strict mode,
    // we can avoid repeated conversions
    const needle_is_string = needle.getTag() == .string;
    var needle_str: ?*types.PHPString = null;
    defer if (needle_str) |s| s.release(vm.allocator);

    if (!strict and needle_is_string) {
        needle_str = needle.getAsString().data;
        needle_str.?.retain();
    }

    var iterator = haystack.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        var is_match = false;

        if (strict) {
            // Strict comparison
            if (needle.getTag() == value.getTag()) {
                is_match = switch (needle.getTag()) {
                    .null => true,
                    .boolean => needle.asBool() == value.asBool(),
                    .integer => needle.asInt() == value.asInt(),
                    .float => needle.asFloat() == value.asFloat(),
                    .string => std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data),
                    else => false,
                };
            }
        } else {
            // Loose comparison - optimized path
            if (value.getTag() == needle.getTag()) {
                // Same type - can compare directly without conversion
                is_match = switch (needle.getTag()) {
                    .null => true,
                    .boolean => needle.asBool() == value.asBool(),
                    .integer => needle.asInt() == value.asInt(),
                    .float => needle.asFloat() == value.asFloat(),
                    .string => std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data),
                    else => false,
                };
            } else if (needle_is_string and value.getTag() == .string) {
                // Both are strings - direct comparison
                is_match = std.mem.eql(u8, needle.getAsString().data.data, value.getAsString().data.data);
            } else {
                // Type mismatch - need conversion for comparison
                const needle_str_val = needle_str orelse needle: {
                    const s = try needle.toString(vm.allocator);
                    needle_str = s;
                    break :needle s;
                };
                const value_str = try value.toString(vm.allocator);
                defer value_str.deinit(vm.allocator);

                is_match = std.mem.eql(u8, needle_str_val.data, value_str.data);
            }
        }

        if (is_match) {
            return switch (key) {
                .integer => |i| Value.initInt(i),
                .string => |s| blk: {
                    const box = try vm.allocator.create(types.gc.Box(*PHPString));
                    box.* = .{
                        .ref_count = 1,
                        .gc_info = .{},
                        .data = try PHPString.init(vm.allocator, s.data),
                    };
                    break :blk Value.fromBox(box, Value.TYPE_STRING);
                },
            };
        }
    }

    return Value.initBool(false); // PHP returns false when not found
}

// String Function Implementations
fn strlenFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strlen() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    return Value.initInt(@intCast(str.getAsString().data.length));
}

fn substrFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const start = args[1];
    const length = if (args.len > 2) args[2] else Value.initNull();

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "substr() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (start.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "substr() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const start_int = start.asInt();
    const length_int = if (length.getTag() == .integer) length.asInt() else null;

    const result_str = try str.getAsString().data.substring(start_int, length_int, vm.allocator);
    return createStringReturn(vm.allocator, result_str);
}

fn stringReplaceOnce(allocator: std.mem.Allocator, subject_data: []const u8, search_data: []const u8, replace_data: []const u8, ignore_case: bool) ![]u8 {
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

fn valueToOwnedStringSlice(vm: *VM, val: Value) ![]u8 {
    if (val.getTag() == .string) return vm.allocator.dupe(u8, val.getAsString().data.data);
    const str = try val.toString(vm.allocator);
    defer str.release(vm.allocator);
    return vm.allocator.dupe(u8, str.data);
}

fn strReplaceCommon(vm: *VM, args: []const Value, ignore_case: bool) !Value {
    const search = args[0];
    const replace = args[1];
    const subject = args[2];

    if (subject.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, if (ignore_case) "str_ireplace() expects parameter 3 to be string" else "str_replace() expects parameter 3 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (search.getTag() == .array) {
        var current = try vm.allocator.dupe(u8, subject.getAsString().data.data);
        defer vm.allocator.free(current);

        const search_arr = search.getAsArray().data;
        const replace_is_array = replace.getTag() == .array;
        var i: usize = 0;
        while (i < search_arr.getElements().count()) : (i += 1) {
            const key = ArrayKey{ .integer = @intCast(i) };
            const search_val = search_arr.getElements().get(key) orelse continue;
            const search_slice = try valueToOwnedStringSlice(vm, search_val);
            defer vm.allocator.free(search_slice);

            const replace_slice = blk: {
                if (replace_is_array) {
                    const replace_arr = replace.getAsArray().data;
                    if (replace_arr.getElements().get(key)) |replace_val| {
                        break :blk try valueToOwnedStringSlice(vm, replace_val);
                    }
                    break :blk try vm.allocator.dupe(u8, "");
                }
                break :blk try valueToOwnedStringSlice(vm, replace);
            };
            defer vm.allocator.free(replace_slice);

            const next = try stringReplaceOnce(vm.allocator, current, search_slice, replace_slice, ignore_case);
            vm.allocator.free(current);
            current = next;
        }

        const result_str = try PHPString.init(vm.allocator, current);
        return createStringReturn(vm.allocator, result_str);
    }

    const search_slice = try valueToOwnedStringSlice(vm, search);
    defer vm.allocator.free(search_slice);
    const replace_slice = try valueToOwnedStringSlice(vm, replace);
    defer vm.allocator.free(replace_slice);
    const buffer = try stringReplaceOnce(vm.allocator, subject.getAsString().data.data, search_slice, replace_slice, ignore_case);
    defer vm.allocator.free(buffer);
    const result_str = try PHPString.init(vm.allocator, buffer);
    return createStringReturn(vm.allocator, result_str);
}

fn strReplaceFn(vm: *VM, args: []const Value) !Value {
    return strReplaceCommon(vm, args, false);
}

fn strIreplaceFn(vm: *VM, args: []const Value) !Value {
    return strReplaceCommon(vm, args, true);
}

fn strposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];
    const offset: usize = if (args.len > 2) @intCast(args[2].asInt()) else 0;

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strpos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    // Use SIMD-optimized search for better performance
    const search_slice = if (offset > 0 and offset < haystack_str.len) haystack_str[offset..] else haystack_str;
    if (SimdString.findSimd(search_slice, needle_str)) |pos| {
        return Value.initInt(@intCast(offset + pos));
    }
    return Value.initBool(false);
}

// Case-insensitive strpos (optimized - no string allocation)
fn striposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];
    const offset: usize = if (args.len > 2) @intCast(args[2].asInt()) else 0;

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "stripos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    // Use optimized std.ascii.indexOfIgnoreCasePos (no allocation needed)
    if (std.ascii.indexOfIgnoreCasePos(haystack_str, offset, needle_str)) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

// Find last occurrence of needle in haystack
fn strrposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strrpos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    if (std.mem.lastIndexOf(u8, haystack_str, needle_str)) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

// Case-insensitive strrpos - optimized with SIMD
fn strriposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strripos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const haystack_str = haystack.getAsString().data.data;
    const needle_str = needle.getAsString().data.data;

    const haystack_lower = try vm.allocator.alloc(u8, haystack_str.len);
    defer vm.allocator.free(haystack_lower);
    // Use SIMD-optimized toLower
    SimdString.toLowerSimd(haystack_lower, haystack_str);

    const needle_lower = try vm.allocator.alloc(u8, needle_str.len);
    defer vm.allocator.free(needle_lower);
    // Use SIMD-optimized toLower
    SimdString.toLowerSimd(needle_lower, needle_str);

    if (std.mem.lastIndexOf(u8, haystack_lower, needle_lower)) |pos| {
        return Value.initInt(@intCast(pos));
    }
    return Value.initBool(false);
}

fn strtolowerFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtolower() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const lower_data = try vm.allocator.alloc(u8, original.length);

    // Use SIMD-optimized toLower for better performance on longer strings
    SimdString.toLowerSimd(lower_data, original.data);

    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = lower_data,
        .length = original.length,
        .encoding = original.encoding,
        .ref_count = 1,
    };

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn strtoupperFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtoupper() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const upper_data = try vm.allocator.alloc(u8, original.length);

    // Use SIMD-optimized toUpper for better performance on longer strings
    SimdString.toUpperSimd(upper_data, original.data);

    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = upper_data,
        .length = original.length,
        .encoding = original.encoding,
        .ref_count = 1,
    };

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn trimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "trim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const trim_chars = if (chars.getTag() == .string) chars.getAsString().data.data else " \t\n\r\x00\x0B";

    var start: usize = 0;
    var end: usize = original.length;

    // Trim from start
    while (start < original.length) {
        var found = false;
        for (trim_chars) |trim_char| {
            if (original.data[start] == trim_char) {
                found = true;
                break;
            }
        }
        if (!found) break;
        start += 1;
    }

    // Trim from end
    while (end > start) {
        var found = false;
        for (trim_chars) |trim_char| {
            if (original.data[end - 1] == trim_char) {
                found = true;
                break;
            }
        }
        if (!found) break;
        end -= 1;
    }

    const result_str = try PHPString.init(vm.allocator, original.data[start..end]);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn ltrimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ltrim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const trim_chars = if (chars.getTag() == .string) chars.getAsString().data.data else " \t\n\r\x00\x0B";

    var start: usize = 0;

    // Trim from start only
    while (start < original.length) {
        var found = false;
        for (trim_chars) |trim_char| {
            if (original.data[start] == trim_char) {
                found = true;
                break;
            }
        }
        if (!found) break;
        start += 1;
    }

    const result_str = try PHPString.init(vm.allocator, original.data[start..]);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn rtrimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "rtrim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const original = str.getAsString().data;
    const trim_chars = if (chars.getTag() == .string) chars.getAsString().data.data else " \t\n\r\x00\x0B";

    var end: usize = original.length;

    // Trim from end only
    while (end > 0) {
        var found = false;
        for (trim_chars) |trim_char| {
            if (original.data[end - 1] == trim_char) {
                found = true;
                break;
            }
        }
        if (!found) break;
        end -= 1;
    }

    const result_str = try PHPString.init(vm.allocator, original.data[0..end]);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn explodeFn(vm: *VM, args: []const Value) !Value {
    const delimiter = args[0];
    const string = args[1];
    const limit = if (args.len > 2) args[2] else Value.initNull();

    if (delimiter.getTag() != .string or string.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "explode() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    const delim = delimiter.getAsString().data;
    const str = string.getAsString().data;

    if (delim.length == 0) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "explode(): Empty delimiter", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var start: usize = 0;
    var count: i64 = 0;
    const max_splits = if (limit.getTag() == .integer) limit.asInt() else std.math.maxInt(i64);

    while (start < str.length and count < max_splits - 1) {
        const pos = std.mem.indexOf(u8, str.data[start..], delim.data);
        if (pos) |p| {
            const actual_pos = start + p;

            // Use Value.initString helper (optimized)
            const value = try Value.initString(vm.allocator, str.data[start..actual_pos]);
            try result_array.push(vm.allocator, value);
            vm.releaseValue(value);

            start = actual_pos + delim.length;
            count += 1;
        } else {
            break;
        }
    }

    // Add the remaining part
    if (start < str.length) {
        // Use Value.initString helper (optimized)
        const value = try Value.initString(vm.allocator, str.data[start..]);
        try result_array.push(vm.allocator, value);
        vm.releaseValue(value);
    }

    const array_box = try vm.allocator.create(types.gc.Box(*PHPArray));
    array_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(array_box, Value.TYPE_ARRAY);
}

// Helper to calculate string length for implode - inlined for performance
inline fn getValueStringLen(value: Value) ?usize {
    if (value.getTag() == .string) {
        return value.getAsString().data.len;
    }
    return null;
}

fn implodeFn(vm: *VM, args: []const Value) !Value {
    const glue = args[0];
    const pieces = args[1];

    if (glue.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "implode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (pieces.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "implode() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Inline frequently accessed values (getAsString returns Box)
    const glue_box = glue.getAsString();
    const glue_data = glue_box.data.data;
    const glue_len = glue_data.len;
    const array_data = pieces.getAsArray().data;
    const count = array_data.getElements().count();

    if (count == 0) {
        const result_str = try PHPString.init(vm.allocator, "");
        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };
        return Value.fromBox(box, Value.TYPE_STRING);
    }

    // First pass: calculate total length
    var total_length: usize = 0;
    var iterator = array_data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        // Inline tag check
        if (value.getTag() == .string) {
            total_length += value.getAsString().data.data.len;
        } else {
            const value_str = try value.toString(vm.allocator);
            total_length += value_str.data.len;
            value_str.deinit(vm.allocator);
        }
    }

    if (count > 1) {
        total_length += (count - 1) * glue_len;
    }

    // Allocate exact size buffer
    const result_data = try vm.allocator.alloc(u8, total_length);

    // Second pass: copy strings directly to result buffer
    var pos: usize = 0;
    var first = true;
    iterator = array_data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        if (!first) {
            @memcpy(result_data[pos .. pos + glue_len], glue_data);
            pos += glue_len;
        }
        first = false;

        if (value.getTag() == .string) {
            const str_data = value.getAsString().data.data;
            const len = str_data.len;
            @memcpy(result_data[pos .. pos + len], str_data);
            pos += len;
        } else {
            const value_str = try value.toString(vm.allocator);
            const len = value_str.data.len;
            @memcpy(result_data[pos .. pos + len], value_str.data);
            pos += len;
            value_str.deinit(vm.allocator);
        }
    }

    const result_str = try PHPString.init(vm.allocator, result_data);
    vm.allocator.free(result_data);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    return Value.fromBox(box, Value.TYPE_STRING);
}

fn strRepeatFn(vm: *VM, args: []const Value) !Value {
    const input = args[0];
    const multiplier = args[1];

    if (input.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (multiplier.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const times = multiplier.asInt();
    if (times < 0) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat(): Second argument has to be greater than or equal to 0", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (times == 0) {
        return try Value.initString(vm.allocator, "");
    }

    const input_str = input.getAsString().data;
    const total_length = input_str.length * @as(usize, @intCast(times));
    const result_data = try vm.allocator.alloc(u8, total_length);

    for (0..@intCast(times)) |i| {
        const start = i * input_str.length;
        @memcpy(result_data[start .. start + input_str.length], input_str.data);
    }

    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = result_data,
        .length = total_length,
        .encoding = input_str.encoding,
        .ref_count = 1,
    };

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

// Math Function Implementations - 快速路径优化版本
fn absFn(vm: *VM, args: []const Value) !Value {
    const arg = args[0];
    // 快速路径：整数直接处理，避免浮点转换
    if (arg.getTag() == .integer) {
        const i = arg.asInt();
        return Value.initInt(if (i < 0) -i else i);
    }
    const num = try toFloat(vm, arg);
    return Value.initFloat(@abs(num));
}

fn roundFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    const precision = if (args.len > 1) args[1] else Value.initInt(0);

    if (precision.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "round() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const num_val = switch (number.getTag()) {
        .integer => @as(f64, @floatFromInt(number.asInt())),
        .float => number.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "round() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const prec = precision.asInt();
    const multiplier = std.math.pow(f64, 10.0, @floatFromInt(prec));
    const rounded = @round(num_val * multiplier) / multiplier;

    if (prec == 0) {
        return Value.initInt(@intFromFloat(rounded));
    } else {
        return Value.initFloat(rounded);
    }
}

fn sqrtFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];

    const num_val: f64 = switch (number.getTag()) {
        .integer => @as(f64, @floatFromInt(number.asInt())),
        .float => number.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "sqrt() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    if (num_val < 0) {
        return Value.initFloat(std.math.nan(f64));
    }

    return Value.initFloat(@sqrt(num_val));
}

fn powFn(vm: *VM, args: []const Value) !Value {
    const base = args[0];
    const exponent = args[1];

    const base_val = switch (base.getTag()) {
        .integer => @as(f64, @floatFromInt(base.asInt())),
        .float => base.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "pow() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const exp_val = switch (exponent.getTag()) {
        .integer => @as(f64, @floatFromInt(exponent.asInt())),
        .float => exponent.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "pow() expects parameter 2 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const result = std.math.pow(f64, base_val, exp_val);

    // Return integer if both inputs were integers and result is a whole number
    if (base.getTag() == .integer and exponent.getTag() == .integer and result == @floor(result)) {
        return Value.initInt(@intFromFloat(result));
    } else {
        return Value.initFloat(result);
    }
}

fn floorFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    // 快速路径：整数直接返回
    if (number.getTag() == .integer) return number;
    if (number.getTag() != .float) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "floor() expects parameter 1 to be numeric", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    return Value.initFloat(@floor(number.asFloat()));
}

fn ceilFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    // 快速路径：整数直接返回
    if (number.getTag() == .integer) return number;
    if (number.getTag() != .float) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ceil() expects parameter 1 to be numeric", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    return Value.initFloat(@ceil(number.asFloat()));
}

fn minFn(vm: *VM, args: []const Value) !Value {
    if (args.len == 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, 0, "min", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    var min_val = args[0];
    for (args[1..]) |arg| {
        const comparison = compareValues(min_val, arg);
        if (comparison > 0) {
            min_val = arg;
        }
    }

    return min_val;
}

fn maxFn(vm: *VM, args: []const Value) !Value {
    if (args.len == 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, 0, "max", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    var max_val = args[0];
    for (args[1..]) |arg| {
        const comparison = compareValues(max_val, arg);
        if (comparison < 0) {
            max_val = arg;
        }
    }

    return max_val;
}

fn randFn(vm: *VM, args: []const Value) !Value {
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();

    if (args.len == 0) {
        return Value.initInt(random.int(i32));
    } else if (args.len == 2) {
        const min = args[0];
        const max = args[1];

        if (min.getTag() != .integer or max.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "rand() expects parameters to be integers", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }

        const min_val = min.asInt();
        const max_val = max.asInt();

        if (min_val > max_val) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "rand(): min is greater than max", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }

        const range = @as(u64, @intCast(max_val - min_val + 1));
        const result = min_val + @as(i64, @intCast(random.uintLessThan(u64, range)));
        return Value.initInt(result);
    } else {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "rand", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }
}

fn mtRandFn(vm: *VM, args: []const Value) !Value {
    // mt_rand is the same as rand in this implementation
    return randFn(vm, args);
}

// Helper function for value comparison
fn compareValues(a: Value, b: Value) i8 {
    // Simplified comparison - would need full PHP comparison semantics
    if (a.getTag() == .integer and b.getTag() == .integer) {
        if (a.asInt() < b.asInt()) return -1;
        if (a.asInt() > b.asInt()) return 1;
        return 0;
    } else if (a.getTag() == .float and b.getTag() == .float) {
        if (a.asFloat() < b.asFloat()) return -1;
        if (a.asFloat() > b.asFloat()) return 1;
        return 0;
    } else {
        // Mixed types - convert to float for comparison
        const a_float = switch (a.getTag()) {
            .integer => @as(f64, @floatFromInt(a.asInt())),
            .float => a.asFloat(),
            else => 0.0,
        };
        const b_float = switch (b.getTag()) {
            .integer => @as(f64, @floatFromInt(b.asInt())),
            .float => b.asFloat(),
            else => 0.0,
        };

        if (a_float < b_float) return -1;
        if (a_float > b_float) return 1;
        return 0;
    }
}

const ArraySortItem = struct {
    key: ArrayKey,
    value: Value,
};

fn compareArrayKeys(a: ArrayKey, b: ArrayKey) i8 {
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

fn collectArraySortItems(vm: *VM, php_array: *types.PHPArray) !std.ArrayListUnmanaged(ArraySortItem) {
    var items = std.ArrayListUnmanaged(ArraySortItem){};
    errdefer items.deinit(vm.allocator);

    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        try items.append(vm.allocator, .{
            .key = entry.key_ptr.*,
            .value = entry.value_ptr.*,
        });
    }

    return items;
}

fn rebuildArrayWithSortedItems(php_array: *types.PHPArray, items: []const ArraySortItem) void {
    const elements = php_array.getElements();
    elements.clearRetainingCapacity();
    php_array.next_index = 0;

    for (items) |item| {
        elements.put(item.key, item.value) catch {};
        if (item.key == .integer and item.key.integer >= php_array.next_index) {
            php_array.next_index = item.key.integer + 1;
        }
    }
}
// File System Function Implementations
fn fileGetContentsFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_get_contents() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;

    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return Value.initBool(false),
            error.AccessDenied => return Value.initBool(false),
            else => return Value.initBool(false),
        }
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try vm.allocator.alloc(u8, file_size);
    _ = try file.readAll(contents);

    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = contents,
        .length = file_size,
        .encoding = .utf8,
        .ref_count = 1,
    };

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn filePutContentsFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    const data = args[1];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_put_contents() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const data_str = try data.toString(vm.allocator);
    defer data_str.deinit(vm.allocator);

    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        switch (err) {
            error.AccessDenied => return Value.initBool(false),
            error.PathAlreadyExists => {
                // Try to open existing file for writing
                const existing_file = std.fs.cwd().openFile(file_path, .{ .mode = .write_only }) catch {
                    return Value.initBool(false);
                };
                defer existing_file.close();
                try existing_file.writeAll(data_str.data);
                return Value.initInt(@intCast(data_str.length));
            },
            else => return Value.initBool(false),
        }
    };
    defer file.close();

    try file.writeAll(data_str.data);
    return Value.initInt(@intCast(data_str.length));
}

fn fileExistsFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;

    std.fs.cwd().access(file_path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

fn isFileFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_file() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;

    const stat = std.fs.cwd().statFile(file_path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(stat.kind == .file);
}

fn isDirFn(vm: *VM, args: []const Value) !Value {
    const dirname = args[0];

    if (dirname.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_dir() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const dir_path = dirname.getAsString().data.data;

    const stat = std.fs.cwd().statFile(dir_path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(stat.kind == .directory);
}

fn filesizeFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "filesize() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;

    const stat = std.fs.cwd().statFile(file_path) catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(stat.size));
}

fn basenameFn(vm: *VM, args: []const Value) !Value {
    const path = args[0];
    const suffix = if (args.len > 1) args[1] else Value.initNull();

    if (path.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "basename() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const path_str = path.getAsString().data.data;
    const basename = std.fs.path.basename(path_str);

    var result_name = basename;

    // Remove suffix if provided
    if (suffix.getTag() == .string) {
        const suffix_str = suffix.getAsString().data.data;
        if (std.mem.endsWith(u8, basename, suffix_str)) {
            result_name = basename[0 .. basename.len - suffix_str.len];
        }
    }

    const result_str = try PHPString.init(vm.allocator, result_name);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn dirnameFn(vm: *VM, args: []const Value) !Value {
    const path = args[0];
    const levels = if (args.len > 1) args[1] else Value.initInt(1);

    if (path.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "dirname() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (levels.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "dirname() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const path_str = path.getAsString().data.data;
    var dirname = std.fs.path.dirname(path_str) orelse ".";

    // Apply levels
    var remaining_levels = levels.asInt() - 1;
    while (remaining_levels > 0 and !std.mem.eql(u8, dirname, ".") and !std.mem.eql(u8, dirname, "/")) {
        dirname = std.fs.path.dirname(dirname) orelse ".";
        remaining_levels -= 1;
    }

    const result_str = try PHPString.init(vm.allocator, dirname);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

// Date/Time Function Implementations（调用 core_time 模块）
fn timeFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initInt(core_time.time());
}

fn microtimeFn(vm: *VM, args: []const Value) !Value {
    const as_float = if (args.len > 0) args[0].toBool() else false;
    if (as_float) {
        return Value.initFloat(core_time.microtime_float());
    } else {
        var ctx = core_string.common.CoreContext{ .allocator = vm.allocator };
        const result = try core_time.microtime_string(&ctx);
        defer vm.allocator.free(result);
        const str = try PHPString.init(vm.allocator, result);
        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = str };
        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

fn usleepFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const microseconds = args[0].asInt();
    std.Thread.sleep(@intCast(microseconds * 1000));
    return Value.initNull();
}

fn sleepFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const seconds = args[0].asInt();
    std.Thread.sleep(@intCast(seconds * 1_000_000_000));
    return Value.initInt(0);
}

fn dateFn(vm: *VM, args: []const Value) !Value {
    const format = args[0];
    const timestamp = if (args.len > 1) args[1] else Value.initInt(std.time.timestamp());

    if (format.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "date() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (timestamp.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "date() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const format_str = format.getAsString().data.data;
    const ts: i64 = timestamp.asInt();

    // Convert timestamp to epoch seconds
    const epoch_seconds: u64 = @intCast(ts);
    const epoch_day = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = epoch_day.getDaySeconds();
    const year_day = epoch_day.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    var result = try std.ArrayList(u8).initCapacity(vm.allocator, format_str.len * 2);
    defer result.deinit(vm.allocator);

    var i: usize = 0;
    while (i < format_str.len) : (i += 1) {
        const c = format_str[i];
        switch (c) {
            'Y' => try result.writer(vm.allocator).print("{d:0>4}", .{year_day.year}),
            'm' => try result.writer(vm.allocator).print("{d:0>2}", .{month_day.month.numeric()}),
            'd' => try result.writer(vm.allocator).print("{d:0>2}", .{month_day.day_index + 1}),
            'H' => try result.writer(vm.allocator).print("{d:0>2}", .{day_seconds.getHoursIntoDay()}),
            'i' => try result.writer(vm.allocator).print("{d:0>2}", .{day_seconds.getMinutesIntoHour()}),
            's' => try result.writer(vm.allocator).print("{d:0>2}", .{day_seconds.getSecondsIntoMinute()}),
            'U' => try result.writer(vm.allocator).print("{d}", .{ts}),
            else => try result.append(vm.allocator, c),
        }
    }

    return Value.initString(vm.allocator, result.items);
}

fn strtotimeFn(vm: *VM, args: []const Value) !Value {
    const time_str = args[0];
    const now = if (args.len > 1) args[1].asInt() else std.time.timestamp();

    if (time_str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtotime() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const time_string = time_str.getAsString().data.data;

    // Parse relative time strings
    if (std.mem.startsWith(u8, time_string, "+")) {
        var parts = std.mem.splitScalar(u8, time_string[1..], ' ');
        const num_str = parts.next() orelse return Value.initBool(false);
        const unit = parts.next() orelse return Value.initBool(false);

        const num = std.fmt.parseInt(i64, num_str, 10) catch return Value.initBool(false);
        const seconds: i64 = if (std.mem.eql(u8, unit, "day") or std.mem.eql(u8, unit, "days"))
            num * 86400
        else if (std.mem.eql(u8, unit, "hour") or std.mem.eql(u8, unit, "hours"))
            num * 3600
        else if (std.mem.eql(u8, unit, "minute") or std.mem.eql(u8, unit, "minutes"))
            num * 60
        else if (std.mem.eql(u8, unit, "week") or std.mem.eql(u8, unit, "weeks"))
            num * 604800
        else
            return Value.initBool(false);

        return Value.initInt(now + seconds);
    } else if (std.mem.startsWith(u8, time_string, "-")) {
        var parts = std.mem.splitScalar(u8, time_string[1..], ' ');
        const num_str = parts.next() orelse return Value.initBool(false);
        const unit = parts.next() orelse return Value.initBool(false);

        const num = std.fmt.parseInt(i64, num_str, 10) catch return Value.initBool(false);
        const seconds: i64 = if (std.mem.eql(u8, unit, "day") or std.mem.eql(u8, unit, "days"))
            num * 86400
        else if (std.mem.eql(u8, unit, "hour") or std.mem.eql(u8, unit, "hours"))
            num * 3600
        else
            return Value.initBool(false);

        return Value.initInt(now - seconds);
    } else if (std.mem.eql(u8, time_string, "now")) {
        return Value.initInt(now);
    }

    // Try to parse as timestamp
    const parsed = std.fmt.parseInt(i64, time_string, 10) catch return Value.initBool(false);
    return Value.initInt(parsed);
}

fn mktimeFn(vm: *VM, args: []const Value) !Value {
    // Simplified implementation - would need full mktime logic
    _ = vm;
    _ = args;
    return Value.initInt(std.time.timestamp());
}

fn gmdateFn(vm: *VM, args: []const Value) !Value {
    // gmdate is similar to date but uses GMT
    return dateFn(vm, args);
}

// JSON Function Implementations
fn jsonEncodeFn(vm: *VM, args: []const Value) !Value {
    const value = args[0];

    // Simplified JSON encoding
    const json_str = try encodeValueAsJson(value, vm.allocator);

    const result_str = try PHPString.init(vm.allocator, json_str);
    vm.allocator.free(json_str);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn jsonDecodeFn(vm: *VM, args: []const Value) !Value {
    const json_str = args[0];
    const assoc = if (args.len > 1) args[1].asBool() else false;

    if (json_str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "json_decode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const json_data = json_str.getAsString().data.data;
    var parser = JsonParser{ .input = json_data, .pos = 0 };
    return try parser.parseValue(vm.allocator, vm, assoc);
}

const JsonParser = struct {
    input: []const u8,
    pos: usize,

    fn skipWhitespace(self: *JsonParser) void {
        while (self.pos < self.input.len) {
            switch (self.input[self.pos]) {
                ' ', '\n', '\r', '\t' => self.pos += 1,
                else => break,
            }
        }
    }

    const JsonParseError = error{OutOfMemory};

    fn parseValue(self: *JsonParser, allocator: std.mem.Allocator, vm: *VM, assoc: bool) JsonParseError!Value {
        self.skipWhitespace();
        if (self.pos >= self.input.len) {
            return Value.initNull();
        }

        return switch (self.input[self.pos]) {
            'n' => self.parseNull() catch Value.initNull(),
            't' => self.parseTrue() catch Value.initNull(),
            'f' => self.parseFalse() catch Value.initNull(),
            '"' => self.parseString(allocator),
            '[' => self.parseArray(allocator, vm, assoc),
            '{' => self.parseObject(allocator, vm, assoc),
            '-', '0'...'9' => self.parseNumber(),
            else => Value.initNull(),
        };
    }

    fn parseNull(self: *JsonParser) !Value {
        if (std.mem.startsWith(u8, self.input[self.pos..], "null")) {
            self.pos += 4;
            return Value.initNull();
        }
        return Value.initNull();
    }

    fn parseTrue(self: *JsonParser) !Value {
        if (std.mem.startsWith(u8, self.input[self.pos..], "true")) {
            self.pos += 4;
            return Value.initBool(true);
        }
        return Value.initNull();
    }

    fn parseFalse(self: *JsonParser) !Value {
        if (std.mem.startsWith(u8, self.input[self.pos..], "false")) {
            self.pos += 5;
            return Value.initBool(false);
        }
        return Value.initNull();
    }

    fn parseString(self: *JsonParser, allocator: std.mem.Allocator) !Value {
        self.pos += 1; // Skip opening quote
        var result = std.ArrayListUnmanaged(u8){};
        defer result.deinit(allocator);

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == '"') {
                self.pos += 1;
                const slice = try result.toOwnedSlice(allocator);
                return try Value.initString(allocator, slice);
            }
            if (c == '\\' and self.pos + 1 < self.input.len) {
                self.pos += 1;
                const escaped = self.input[self.pos];
                switch (escaped) {
                    '"' => try result.append(allocator, '"'),
                    '\\' => try result.append(allocator, '\\'),
                    '/' => try result.append(allocator, '/'),
                    'b' => try result.append(allocator, '\x08'),
                    'f' => try result.append(allocator, '\x0C'),
                    'n' => try result.append(allocator, '\n'),
                    'r' => try result.append(allocator, '\r'),
                    't' => try result.append(allocator, '\t'),
                    'u' => {
                        // Unicode escape - skip for now
                        self.pos += 1;
                    },
                    else => try result.append(allocator, escaped),
                }
            } else {
                try result.append(allocator, c);
            }
            self.pos += 1;
        }

        return Value.initNull();
    }

    fn parseNumber(self: *JsonParser) !Value {
        const start = self.pos;
        if (self.input[self.pos] == '-') self.pos += 1;
        while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
            self.pos += 1;
        }
        if (self.pos < self.input.len and self.input[self.pos] == '.') {
            self.pos += 1;
            while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
                self.pos += 1;
            }
        }
        if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            self.pos += 1;
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) {
                self.pos += 1;
            }
            while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
                self.pos += 1;
            }
        }

        const num_str = self.input[start..self.pos];
        if (std.mem.indexOf(u8, num_str, ".") != null or
            std.mem.indexOf(u8, num_str, "e") != null or
            std.mem.indexOf(u8, num_str, "E") != null)
        {
            if (std.fmt.parseFloat(f64, num_str)) |f| {
                return Value.initFloat(f);
            } else |_| {}
        } else {
            if (std.fmt.parseInt(i64, num_str, 10)) |i| {
                return Value.initInt(i);
            } else |_| {}
        }

        return Value.initNull();
    }

    fn parseArray(self: *JsonParser, allocator: std.mem.Allocator, vm: *VM, assoc: bool) !Value {
        self.pos += 1; // Skip '['
        self.skipWhitespace();

        const array_box = try allocator.create(types.gc.Box(*types.PHPArray));
        const php_array = try allocator.create(types.PHPArray);
        php_array.* = types.PHPArray.init(allocator);
        array_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };

        var first = true;
        if (self.pos < self.input.len and self.input[self.pos] != ']') {
            while (true) {
                if (!first) {
                    self.skipWhitespace();
                    if (self.input[self.pos] == ',') {
                        self.pos += 1;
                    }
                }
                first = false;

                self.skipWhitespace();
                const value = self.parseValue(allocator, vm, assoc) catch Value.initNull();
                php_array.push(allocator, value) catch {};

                self.skipWhitespace();
                if (self.pos < self.input.len and self.input[self.pos] == ']') {
                    break;
                }
                if (self.pos >= self.input.len or self.input[self.pos] != ',') {
                    break;
                }
                self.pos += 1;
            }
        }

        if (self.pos < self.input.len and self.input[self.pos] == ']') {
            self.pos += 1;
        }

        return Value.fromBox(array_box, Value.TYPE_ARRAY);
    }

    fn parseObject(self: *JsonParser, allocator: std.mem.Allocator, vm: *VM, assoc: bool) !Value {
        _ = assoc; // Always use array for now
        self.pos += 1; // Skip '{'
        self.skipWhitespace();

        const array_box = try allocator.create(types.gc.Box(*types.PHPArray));
        const php_array = try allocator.create(types.PHPArray);
        php_array.* = types.PHPArray.init(allocator);
        array_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };

        var first = true;
        if (self.pos < self.input.len and self.input[self.pos] != '}') {
            while (true) {
                if (!first) {
                    self.skipWhitespace();
                    if (self.input[self.pos] == ',') {
                        self.pos += 1;
                    }
                }
                first = false;

                self.skipWhitespace();
                if (self.input[self.pos] != '"') break;

                // Parse key
                self.pos += 1;
                var key_builder = std.ArrayListUnmanaged(u8){};
                defer key_builder.deinit(allocator);

                while (self.pos < self.input.len) {
                    const c = self.input[self.pos];
                    if (c == '"') {
                        self.pos += 1; // Skip closing quote
                        break;
                    }
                    if (c == '\\' and self.pos + 1 < self.input.len) {
                        self.pos += 1;
                        const escaped = self.input[self.pos];
                        switch (escaped) {
                            '"' => try key_builder.append(allocator, '"'),
                            '\\' => try key_builder.append(allocator, '\\'),
                            '/' => try key_builder.append(allocator, '/'),
                            'n' => try key_builder.append(allocator, '\n'),
                            'r' => try key_builder.append(allocator, '\r'),
                            't' => try key_builder.append(allocator, '\t'),
                            else => try key_builder.append(allocator, escaped),
                        }
                    } else {
                        try key_builder.append(allocator, c);
                    }
                    self.pos += 1;
                }

                self.skipWhitespace();
                if (self.pos >= self.input.len or self.input[self.pos] != ':') {
                    // Try parsing even without colon if we have valid key-value
                    if (self.pos < self.input.len and self.input[self.pos] != ',') {
                        // Still try to parse value
                    }
                }
                self.pos += 1; // Skip ':'

                // Parse value
                self.skipWhitespace();
                const value = try self.parseValue(allocator, vm, false);

                // Store in array with string key
                const key_slice = try key_builder.toOwnedSlice(allocator);
                const key_str = try types.PHPString.init(allocator, key_slice);
                const key = types.ArrayKey{ .string = key_str };
                try php_array.set(allocator, key, value);

                self.skipWhitespace();
                if (self.pos < self.input.len and self.input[self.pos] == '}') {
                    break;
                }
                if (self.pos >= self.input.len or self.input[self.pos] != ',') {
                    break;
                }
                self.pos += 1;
            }
        }

        if (self.pos < self.input.len and self.input[self.pos] == '}') {
            self.pos += 1;
        }

        return Value.fromBox(array_box, Value.TYPE_ARRAY);
    }
};

fn jsonLastErrorFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    // Simplified - would track actual JSON errors
    return Value.initInt(0); // JSON_ERROR_NONE
}

fn jsonLastErrorMsgFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    return try Value.initString(vm.allocator, "No error");
}

// Static constants to avoid allocations
const JSON_NULL_STR = "null";
const JSON_TRUE_STR = "true";
const JSON_FALSE_STR = "false";
const JSON_OPEN_BRACE = "{";
const JSON_CLOSE_BRACE = "}";
const JSON_OPEN_BRACKET = "[";
const JSON_CLOSE_BRACKET = "]";
const JSON_COMMA = ",";
const JSON_COLON = ":";
const JSON_QUOTE = "\"";

// Helper function for JSON encoding (optimized with pre-allocation)
fn encodeValueAsJson(value: Value, allocator: std.mem.Allocator) ![]u8 {
    return switch (value.getTag()) {
        .null => try allocator.dupe(u8, JSON_NULL_STR),
        .boolean => try allocator.dupe(u8, if (value.asBool()) JSON_TRUE_STR else JSON_FALSE_STR),
        .integer => try std.fmt.allocPrint(allocator, "{d}", .{value.asInt()}),
        .float => try std.fmt.allocPrint(allocator, "{d}", .{value.asFloat()}),
        .string => try std.fmt.allocPrint(allocator, "\"{s}\"", .{value.getAsString().data.data}),
        .array => {
            const arr = value.getAsArray().data;
            const len = arr.getElements().count();

            // Check if it's an associative array (has string keys)
            var is_object = false;
            var iter = arr.getElements().iterator();
            while (iter.next()) |entry| {
                if (entry.key_ptr.* == .string) {
                    is_object = true;
                    break;
                }
            }

            // Pre-allocate with estimated capacity (avg 10 chars per element + overhead)
            const estimated_cap = if (len == 0) 2 else len * 12 + 4;
            var result = std.ArrayListUnmanaged(u8){};
            try result.ensureTotalCapacity(allocator, estimated_cap);
            defer result.deinit(allocator);

            if (is_object) {
                // Output as JSON object
                result.appendAssumeCapacity('{');
                var first = true;
                var obj_iter = arr.getElements().iterator();
                while (obj_iter.next()) |entry| {
                    if (!first) result.appendAssumeCapacity(',');
                    first = false;

                    // Output key
                    switch (entry.key_ptr.*) {
                        .string => |s| {
                            result.appendAssumeCapacity('"');
                            result.appendSliceAssumeCapacity(s.data);
                            result.appendAssumeCapacity('"');
                        },
                        .integer => |i| {
                            const buf = try std.fmt.allocPrint(allocator, "{d}", .{i});
                            defer allocator.free(buf);
                            result.appendSliceAssumeCapacity(buf);
                        },
                    }
                    result.appendAssumeCapacity(':');

                    // Output value
                    const element_json = try encodeValueAsJson(entry.value_ptr.*, allocator);
                    defer allocator.free(element_json);
                    result.appendSliceAssumeCapacity(element_json);
                }
                result.appendAssumeCapacity('}');
            } else {
                // Output as JSON array
                result.appendAssumeCapacity('[');
                var first = true;
                var arr_iter = arr.getElements().iterator();
                while (arr_iter.next()) |entry| {
                    if (!first) result.appendAssumeCapacity(',');
                    first = false;

                    const element_json = try encodeValueAsJson(entry.value_ptr.*, allocator);
                    defer allocator.free(element_json);
                    result.appendSliceAssumeCapacity(element_json);
                }
                result.appendAssumeCapacity(']');
            }

            return try allocator.dupe(u8, result.items);
        },
        .object => try std.fmt.allocPrint(allocator, "{{\"class\":\"{s}\"}}", .{value.getAsObject().data.class.name.data}),
        .struct_instance => try std.fmt.allocPrint(allocator, "{{\"struct\":\"{s}\"}}", .{value.getAsStruct().data.struct_type.name.data}),
        else => try allocator.dupe(u8, JSON_NULL_STR),
    };
}

// Hash Function Implementations
fn md5Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "md5() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;
    var hasher = std.crypto.hash.Md5.init(.{});
    hasher.update(input);
    var hash: [16]u8 = undefined;
    hasher.final(&hash);

    if (raw_output) {
        const result_str = try PHPString.init(vm.allocator, &hash);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    } else {
        var hex_buffer: [32]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        const result_str = try PHPString.init(vm.allocator, &hex_buffer);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

fn sha1Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sha1() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(input);
    var hash: [20]u8 = undefined;
    hasher.final(&hash);

    if (raw_output) {
        const result_str = try PHPString.init(vm.allocator, &hash);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    } else {
        var hex_buffer: [40]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        const result_str = try PHPString.init(vm.allocator, &hex_buffer);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

fn uniqidFn(vm: *VM, args: []const Value) !Value {
    const prefix = if (args.len > 0 and args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const more_entropy = if (args.len > 1) args[1].toBool() else false;

    // Get current time in microseconds
    const timestamp = std.time.nanoTimestamp();
    const now = @divTrunc(timestamp, 1000); // Convert to microseconds
    const seconds = @as(u64, @intCast(@divTrunc(now, 1_000_000)));
    const microseconds = @as(u64, @intCast(@rem(now, 1_000_000)));

    // Build result string
    var result_str: *PHPString = undefined;
    if (more_entropy) {
        var result_buf: [64]u8 = undefined;
        // Format: prefix + seconds (13 hex) + microseconds (6 hex) + random (4 hex)
        var rand_bytes: [2]u8 = undefined;
        std.crypto.random.bytes(&rand_bytes);
        const rand_val = @as(u16, rand_bytes[0]) * 256 + rand_bytes[1];
        const formatted = try std.fmt.bufPrint(&result_buf, "{s}{x:0>13}{x:0>6}{x:0>4}", .{ prefix, seconds, microseconds, rand_val });
        result_str = try PHPString.init(vm.allocator, formatted);
    } else {
        var result_buf: [64]u8 = undefined;
        // Format: prefix + seconds (13 hex)
        const formatted = try std.fmt.bufPrint(&result_buf, "{s}{x:0>13}", .{ prefix, seconds });
        result_str = try PHPString.init(vm.allocator, formatted);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn sha256Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sha256() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(input);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    if (raw_output) {
        const result_str = try PHPString.init(vm.allocator, &hash);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    } else {
        var hex_buffer: [64]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        const result_str = try PHPString.init(vm.allocator, &hex_buffer);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

fn sha512Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sha512() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;
    var hasher = std.crypto.hash.sha2.Sha512.init(.{});
    hasher.update(input);
    var hash: [64]u8 = undefined;
    hasher.final(&hash);

    if (raw_output) {
        const result_str = try PHPString.init(vm.allocator, &hash);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    } else {
        var hex_buffer: [128]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        const result_str = try PHPString.init(vm.allocator, &hex_buffer);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

fn hashFn(vm: *VM, args: []const Value) !Value {
    const algo = args[0];
    const data = args[1];
    const raw_output = if (args.len > 2) args[2].toBool() else false;

    if (algo.getTag() != .string or data.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "hash() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const algorithm = algo.getAsString().data.data;

    if (std.mem.eql(u8, algorithm, "md5")) {
        return md5Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else if (std.mem.eql(u8, algorithm, "sha1")) {
        return sha1Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else if (std.mem.eql(u8, algorithm, "sha256")) {
        return sha256Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else if (std.mem.eql(u8, algorithm, "sha512")) {
        return sha512Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "hash(): Unknown hashing algorithm", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
}

fn hashAlgosFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    const algorithms = [_][]const u8{ "md5", "sha1", "sha256", "sha512" };

    for (algorithms) |algo| {
        const algo_str = try Value.initString(vm.allocator, algo);
        try result_array.push(vm.allocator, algo_str);
        vm.releaseValue(algo_str);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// PHP 8.5 Array Functions
fn arrayFirstFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = if (args.len > 1) args[1] else null;

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_first() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var iterator = array.getAsArray().data.getElements().iterator();

    if (callback) |cb| {
        // Find first element that matches callback
        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;

            const callback_args = [_]Value{value};
            const result_value = switch (cb.getTag()) {
                .native_function => blk: {
                    const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(cb.getAsNativeFunc()));
                    break :blk try function(vm, &callback_args);
                },
                .user_function => try vm.callUserFunction(cb.getAsUserFunc().data, &callback_args),
                .closure => try vm.callClosure(cb.getAsClosure().data, &callback_args),
                .arrow_function => try vm.callArrowFunction(cb.getAsArrowFunc().data, &callback_args),
                else => {
                    const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_first() expects parameter 2 to be a valid callback", "builtin", 0);
                    _ = try vm.throwException(exception);
                    return error.InvalidArgumentType;
                },
            };

            if (result_value.toBool()) {
                return value;
            }
        }
        return Value.initNull();
    } else {
        // Return first element
        if (iterator.next()) |entry| {
            return entry.value_ptr.*;
        }
        return Value.initNull();
    }
}

fn arrayLastFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = if (args.len > 1) args[1] else null;

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_last() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (callback) |cb| {
        // Find last element that matches callback
        var last_match: ?Value = null;
        var iterator = array.getAsArray().data.getElements().iterator();

        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;

            const callback_args = [_]Value{value};
            const result_value = switch (cb.getTag()) {
                .native_function => blk: {
                    const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(cb.getAsNativeFunc()));
                    break :blk try function(vm, &callback_args);
                },
                .user_function => try vm.callUserFunction(cb.getAsUserFunc().data, &callback_args),
                .closure => try vm.callClosure(cb.getAsClosure().data, &callback_args),
                .arrow_function => try vm.callArrowFunction(cb.getAsArrowFunc().data, &callback_args),
                else => {
                    const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_last() expects parameter 2 to be a valid callback", "builtin", 0);
                    _ = try vm.throwException(exception);
                    return error.InvalidArgumentType;
                },
            };

            if (result_value.toBool()) {
                last_match = value;
            }
        }
        return last_match orelse Value.initNull();
    } else {
        // Return last element
        var last_value: ?Value = null;
        var iterator = array.getAsArray().data.getElements().iterator();

        while (iterator.next()) |entry| {
            last_value = entry.value_ptr.*;
        }

        return last_value orelse Value.initNull();
    }
}

// Additional array functions
fn arraySumFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_sum() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // 使用PHPArray的SoA优化求和方法
    const php_array = array.getAsArray().data;
    const sum = php_array.sumFloats();

    // Return int if sum is a whole number
    if (@floor(sum) == sum and sum >= @as(f64, @floatFromInt(std.math.minInt(i64))) and sum <= @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
        return Value.initInt(@intFromFloat(sum));
    }
    return Value.initFloat(sum);
}

fn arrayProductFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_product() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var product: f64 = 1;
    var iterator = array.getAsArray().data.getElements().iterator();

    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        product *= switch (value.getTag()) {
            .integer => @floatFromInt(value.asInt()),
            .float => value.asFloat(),
            .string => std.fmt.parseFloat(f64, value.getAsString().data.data) catch 0,
            else => 0,
        };
    }

    if (@floor(product) == product and product >= @as(f64, @floatFromInt(std.math.minInt(i64))) and product <= @as(f64, @floatFromInt(std.math.maxInt(i64)))) {
        return Value.initInt(@intFromFloat(product));
    }
    return Value.initFloat(product);
}

fn arrayReverseFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const preserve_keys = if (args.len > 1) args[1].toBool() else false;

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_reverse() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();

    if (count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(count);

    // Pre-allocate temp array with exact size
    const temp = try vm.allocator.alloc(struct { key: ArrayKey, value: Value }, count);
    defer vm.allocator.free(temp);

    // Copy elements to temp (backwards order)
    var idx: usize = 0;
    var iterator = source_array.getElements().iterator();
    while (iterator.next()) |entry| {
        temp[idx] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
        idx += 1;
    }

    // Reverse insert directly
    var new_index: i64 = 0;
    var i: usize = count;
    while (i > 0) {
        i -= 1;
        const item = temp[i];
        _ = item.value.retain();
        if (preserve_keys) {
            // For string keys, need to retain
            if (item.key == .string) {
                item.key.string.retain();
            }
            result_array.getElements().putAssumeCapacity(item.key, item.value);
        } else {
            const dest_key = ArrayKey{ .integer = new_index };
            new_index += 1;
            result_array.getElements().putAssumeCapacity(dest_key, item.value);
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayUniqueFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_unique() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    var seen = std.StringHashMap(void).init(vm.allocator);
    defer seen.deinit();

    var iterator = array.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        const str_val = switch (value.getTag()) {
            .string => value.getAsString().data.data,
            .integer => blk: {
                const buf = try std.fmt.allocPrint(vm.allocator, "{d}", .{value.asInt()});
                break :blk buf;
            },
            else => "",
        };

        if (!seen.contains(str_val)) {
            try seen.put(str_val, {});
            try result_array.set(vm.allocator, entry.key_ptr.*, value);
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayFlipFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_flip() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const count = arr.getElements().count();

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    // Pre-allocate capacity
    try result_array.getElements().ensureTotalCapacity(count);

    var iterator = arr.getElements().iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const new_key: ArrayKey = switch (value.getTag()) {
            .integer => ArrayKey{ .integer = value.asInt() },
            .string => blk: {
                const str = try PHPString.init(vm.allocator, value.getAsString().data.data);
                break :blk ArrayKey{ .string = str };
            },
            else => continue,
        };

        const new_value = switch (key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                const box = try vm.allocator.create(types.gc.Box(*PHPString));
                box.* = .{ .ref_count = 1, .gc_info = .{}, .data = try PHPString.init(vm.allocator, s.data) };
                break :blk Value.fromBox(box, Value.TYPE_STRING);
            },
        };

        result_array.getElements().putAssumeCapacity(new_key, new_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arraySliceFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const offset_val = args[1];
    const length_val = if (args.len > 2) args[2] else Value.initNull();

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_slice() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_array = array.getAsArray().data;
    const count = source_array.getElements().count();
    const offset: i64 = if (offset_val.getTag() == .integer) offset_val.asInt() else 0;
    const length: i64 = if (length_val.getTag() == .integer) length_val.asInt() else @intCast(count);

    if (count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    // Calculate slice range
    const start: usize = if (offset < 0)
        @intCast(@max(0, @as(i64, @intCast(count)) + offset))
    else
        @intCast(@min(@as(i64, @intCast(count)), offset));

    const end: usize = if (length < 0)
        @intCast(@max(0, @as(i64, @intCast(count)) + length))
    else
        @intCast(@min(@as(i64, @intCast(count)), @as(i64, @intCast(start)) + length));

    const slice_count = if (end > start) end - start else 0;
    if (slice_count == 0) {
        const result_array = try vm.allocator.create(PHPArray);
        result_array.* = PHPArray.init(vm.allocator);
        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);
    try result_array.getElements().ensureTotalCapacity(slice_count);

    // Direct insertion - collect and copy values
    var iterator = source_array.getElements().iterator();
    var idx: usize = 0;
    var result_idx: i64 = 0;
    while (iterator.next()) |entry| {
        if (idx >= start and idx < end) {
            const value = entry.value_ptr.*;
            _ = value.retain();
            const key = ArrayKey{ .integer = result_idx };
            result_idx += 1;
            result_array.getElements().putAssumeCapacity(key, value);
        }
        idx += 1;
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayColumnFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const column_key = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_column() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    const col_key: ArrayKey = switch (column_key.getTag()) {
        .string => blk: {
            const str = try PHPString.init(vm.allocator, column_key.getAsString().data.data);
            break :blk ArrayKey{ .string = str };
        },
        .integer => ArrayKey{ .integer = column_key.asInt() },
        else => ArrayKey{ .integer = 0 },
    };

    var iterator = array.getAsArray().data.getElements().iterator();
    while (iterator.next()) |entry| {
        const row = entry.value_ptr.*;
        if (row.getTag() == .array) {
            if (row.getAsArray().data.get(col_key)) |col_value| {
                try result_array.push(vm.allocator, col_value);
            }
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn rangeFunction(vm: *VM, args: []const Value) !Value {
    const start_val = args[0];
    const end_val = args[1];
    const step_val = if (args.len > 2) args[2] else Value.initInt(1);

    const start: i64 = switch (start_val.getTag()) {
        .integer => start_val.asInt(),
        else => 0,
    };
    const end: i64 = switch (end_val.getTag()) {
        .integer => end_val.asInt(),
        else => 0,
    };
    const step: i64 = switch (step_val.getTag()) {
        .integer => @max(1, step_val.asInt()),
        else => 1,
    };

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    if (start <= end) {
        var i = start;
        while (i <= end) : (i += step) {
            try result_array.push(vm.allocator, Value.initInt(i));
        }
    } else {
        var i = start;
        while (i >= end) : (i -= step) {
            try result_array.push(vm.allocator, Value.initInt(i));
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn arrayFillFn(vm: *VM, args: []const Value) !Value {
    const start_index: i64 = if (args[0].getTag() == .integer) args[0].asInt() else 0;
    const num: i64 = if (args[1].getTag() == .integer) args[1].asInt() else 0;
    const value = args[2];

    if (num <= 0) {
        var empty_array = try vm.allocator.create(PHPArray);
        errdefer {
            empty_array.deinit(vm.allocator);
            vm.allocator.destroy(empty_array);
        }
        empty_array.* = PHPArray.init(vm.allocator);

        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = empty_array };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    // Retain value once for all uses
    _ = value.retain();

    var i: i64 = 0;
    while (i < num) : (i += 1) {
        try result_array.set(vm.allocator, ArrayKey{ .integer = start_index + i }, value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn compactFn(vm: *VM, args: []const Value) !Value {
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    for (args) |arg| {
        if (arg.getTag() == .string) {
            const var_name = arg.getAsString().data.data;
            const prefixed_name = try std.fmt.allocPrint(vm.allocator, "${s}", .{var_name});
            defer vm.allocator.free(prefixed_name);

            if (vm.getVariable(prefixed_name)) |value| {
                const key = try PHPString.init(vm.allocator, var_name);
                try result_array.set(vm.allocator, ArrayKey{ .string = key }, value);
            }
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// String functions implementations
fn sprintfFn(vm: *VM, args: []const Value) !Value {
    if (args.len == 0) return Value.initString(vm.allocator, "");
    const format = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";

    var result = try std.ArrayList(u8).initCapacity(vm.allocator, format.len);
    defer result.deinit(vm.allocator);

    var arg_idx: usize = 1;
    var i: usize = 0;
    while (i < format.len) : (i += 1) {
        if (format[i] == '%' and i + 1 < format.len) {
            const spec = format[i + 1];
            if (spec == '%') {
                try result.append(vm.allocator, '%');
                i += 1;
                continue;
            }

            if (arg_idx >= args.len) {
                try result.append(vm.allocator, '%');
                try result.append(vm.allocator, spec);
                i += 1;
                continue;
            }

            const arg = args[arg_idx];
            arg_idx += 1;

            switch (spec) {
                'd', 'i' => {
                    const val = if (arg.getTag() == .integer) arg.asInt() else 0;
                    try std.fmt.format(result.writer(vm.allocator), "{d}", .{val});
                },
                's' => {
                    const val = if (arg.getTag() == .string) arg.getAsString().data.data else "";
                    try result.appendSlice(vm.allocator, val);
                },
                'f' => {
                    const val = if (arg.getTag() == .float) arg.asFloat() else 0.0;
                    try std.fmt.format(result.writer(vm.allocator), "{d}", .{val});
                },
                else => {
                    try result.append(vm.allocator, '%');
                    try result.append(vm.allocator, spec);
                },
            }
            i += 1;
        } else {
            try result.append(vm.allocator, format[i]);
        }
    }

    return Value.initString(vm.allocator, result.items);
}

fn printfFn(vm: *VM, args: []const Value) !Value {
    const result = try sprintfFn(vm, args);
    if (result.getTag() == .string) {
        std.debug.print("{s}", .{result.getAsString().data.data});
    }
    return Value.initInt(@intCast(if (result.getTag() == .string) result.getAsString().data.length else 0));
}

fn strContainsFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const haystack = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const needle = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";
    return Value.initBool(std.mem.indexOf(u8, haystack, needle) != null);
}

fn strStartsWithFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const haystack = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const needle = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";
    return Value.initBool(std.mem.startsWith(u8, haystack, needle));
}

fn strEndsWithFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const haystack = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const needle = if (args[1].getTag() == .string) args[1].getAsString().data.data else "";
    return Value.initBool(std.mem.endsWith(u8, haystack, needle));
}

fn ucfirstFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    if (str.len == 0) return Value.initString(vm.allocator, "");
    var result = try vm.allocator.alloc(u8, str.len);
    @memcpy(result, str);
    result[0] = std.ascii.toUpper(result[0]);
    defer vm.allocator.free(result);
    return Value.initString(vm.allocator, result);
}

fn lcfirstFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    if (str.len == 0) return Value.initString(vm.allocator, "");
    var result = try vm.allocator.alloc(u8, str.len);
    @memcpy(result, str);
    result[0] = std.ascii.toLower(result[0]);
    defer vm.allocator.free(result);
    return Value.initString(vm.allocator, result);
}

fn ucwordsFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    if (str.len == 0) return Value.initString(vm.allocator, "");
    var result = try vm.allocator.alloc(u8, str.len);
    defer vm.allocator.free(result);
    var capitalize_next = true;
    for (str, 0..) |c, i| {
        if (c == ' ' or c == '\t' or c == '\n') {
            result[i] = c;
            capitalize_next = true;
        } else if (capitalize_next) {
            result[i] = std.ascii.toUpper(c);
            capitalize_next = false;
        } else {
            result[i] = c;
        }
    }
    return Value.initString(vm.allocator, result);
}

fn strPadFn(vm: *VM, args: []const Value) !Value {
    const input = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const length: usize = if (args[1].getTag() == .integer and args[1].asInt() > 0) @intCast(args[1].asInt()) else input.len;
    const pad_str = if (args.len > 2 and args[2].getTag() == .string) args[2].getAsString().data.data else " ";
    const pad_type: i64 = if (args.len > 3 and args[3].getTag() == .integer) args[3].asInt() else 1;

    if (input.len >= length or pad_str.len == 0) return Value.initString(vm.allocator, input);

    const pad_len = length - input.len;
    var result = try vm.allocator.alloc(u8, length);
    defer vm.allocator.free(result);

    if (pad_type == 0) { // STR_PAD_LEFT
        var i: usize = 0;
        while (i < pad_len) : (i += 1) result[i] = pad_str[i % pad_str.len];
        @memcpy(result[pad_len..], input);
    } else if (pad_type == 2) { // STR_PAD_BOTH
        const left_pad = pad_len / 2;
        const right_pad = pad_len - left_pad;
        var i: usize = 0;
        while (i < left_pad) : (i += 1) result[i] = pad_str[i % pad_str.len];
        @memcpy(result[left_pad .. left_pad + input.len], input);
        i = 0;
        while (i < right_pad) : (i += 1) result[left_pad + input.len + i] = pad_str[i % pad_str.len];
    } else { // STR_PAD_RIGHT (default)
        @memcpy(result[0..input.len], input);
        var i: usize = 0;
        while (i < pad_len) : (i += 1) result[input.len + i] = pad_str[i % pad_str.len];
    }
    return Value.initString(vm.allocator, result);
}

fn strrevFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    if (str.len == 0) return Value.initString(vm.allocator, "");
    const result = try core_string.strrev_raw(vm.allocator, str);
    defer vm.allocator.free(result);
    return Value.initString(vm.allocator, result);
}

fn strSplitFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const length: usize = if (args.len > 1 and args[1].getTag() == .integer and args[1].asInt() > 0) @intCast(args[1].asInt()) else 1;

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var i: usize = 0;
    while (i < str.len) {
        const end = @min(i + length, str.len);
        const chunk = try Value.initString(vm.allocator, str[i..end]);
        try result_array.push(vm.allocator, chunk);
        chunk.release(vm.allocator); // push retains, so release our ref
        i = end;
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn chunkSplitFn(vm: *VM, args: []const Value) !Value {
    const body = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    const chunklen: usize = if (args.len > 1 and args[1].getTag() == .integer) @intCast(@max(1, args[1].asInt())) else 76;
    const end = if (args.len > 2 and args[2].getTag() == .string) args[2].getAsString().data.data else "\r\n";

    const num_chunks = (body.len + chunklen - 1) / chunklen;
    const result_len = body.len + num_chunks * end.len;
    var result = try vm.allocator.alloc(u8, result_len);
    defer vm.allocator.free(result);

    var src_i: usize = 0;
    var dst_i: usize = 0;
    while (src_i < body.len) {
        const chunk_end = @min(src_i + chunklen, body.len);
        @memcpy(result[dst_i .. dst_i + (chunk_end - src_i)], body[src_i..chunk_end]);
        dst_i += chunk_end - src_i;
        @memcpy(result[dst_i .. dst_i + end.len], end);
        dst_i += end.len;
        src_i = chunk_end;
    }
    return Value.initString(vm.allocator, result[0..dst_i]);
}

fn wordwrapFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    return Value.initString(vm.allocator, str);
}

fn nl2brFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    var count: usize = 0;
    for (str) |c| if (c == '\n') {
        count += 1;
    };

    var result = try vm.allocator.alloc(u8, str.len + count * 5);
    defer vm.allocator.free(result);
    var j: usize = 0;
    for (str) |c| {
        if (c == '\n') {
            @memcpy(result[j .. j + 5], "<br>\n");
            j += 5;
        } else {
            result[j] = c;
            j += 1;
        }
    }
    return Value.initString(vm.allocator, result[0..j]);
}

fn stripTagsFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    var result = try vm.allocator.alloc(u8, str.len);
    defer vm.allocator.free(result);
    var j: usize = 0;
    var in_tag = false;
    for (str) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            result[j] = c;
            j += 1;
        }
    }
    return Value.initString(vm.allocator, result[0..j]);
}

fn htmlspecialcharsFn(vm: *VM, args: []const Value) !Value {
    const str = if (args[0].getTag() == .string) args[0].getAsString().data.data else "";
    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(vm.allocator);
    for (str) |c| {
        switch (c) {
            '&' => try result.appendSlice(vm.allocator, "&amp;"),
            '"' => try result.appendSlice(vm.allocator, "&quot;"),
            '\'' => try result.appendSlice(vm.allocator, "&#039;"),
            '<' => try result.appendSlice(vm.allocator, "&lt;"),
            '>' => try result.appendSlice(vm.allocator, "&gt;"),
            else => try result.append(vm.allocator, c),
        }
    }
    return Value.initString(vm.allocator, result.items);
}

fn htmlentitiesFn(vm: *VM, args: []const Value) !Value {
    return htmlspecialcharsFn(vm, args);
}

fn numberFormatFn(vm: *VM, args: []const Value) !Value {
    const num: f64 = switch (args[0].getTag()) {
        .integer => @floatFromInt(args[0].asInt()),
        .float => args[0].asFloat(),
        else => 0,
    };
    const decimals: u32 = if (args.len > 1 and args[1].getTag() == .integer) @intCast(@max(0, args[1].asInt())) else 0;
    const dec_point = if (args.len > 2 and args[2].getTag() == .string) args[2].getAsString().data.data else ".";
    const thousands_sep = if (args.len > 3 and args[3].getTag() == .string) args[3].getAsString().data.data else ",";

    // Format with decimals
    const formatted = try std.fmt.allocPrint(vm.allocator, "{d:.2}", .{num});
    defer vm.allocator.free(formatted);

    // Split into integer and decimal parts
    var parts = std.mem.splitScalar(u8, formatted, '.');
    const int_part = parts.next() orelse formatted;
    const dec_part = parts.next();

    // Add thousands separator
    var result = try std.ArrayList(u8).initCapacity(vm.allocator, formatted.len + 10);
    defer result.deinit(vm.allocator);

    const int_len = int_part.len;
    var i: usize = 0;
    while (i < int_len) : (i += 1) {
        if (i > 0 and (int_len - i) % 3 == 0) {
            try result.appendSlice(vm.allocator, thousands_sep);
        }
        try result.append(vm.allocator, int_part[i]);
    }

    if (decimals > 0) {
        try result.appendSlice(vm.allocator, dec_point);
        if (dec_part) |dp| {
            const len = @min(dp.len, decimals);
            try result.appendSlice(vm.allocator, dp[0..len]);
            for (len..decimals) |_| {
                try result.append(vm.allocator, '0');
            }
        } else {
            for (0..decimals) |_| {
                try result.append(vm.allocator, '0');
            }
        }
    }

    return Value.initString(vm.allocator, result.items);
}

// Debug functions
fn varDumpFn(_: *VM, args: []const Value) !Value {
    for (args) |arg| {
        dumpValueDebug(arg, 0);
        std.debug.print("\n", .{});
    }
    return Value.initNull();
}

fn dumpValueDebug(value: Value, indent: usize) void {
    const ind = "  " ** 10;
    switch (value.getTag()) {
        .null => std.debug.print("NULL", .{}),
        .boolean => std.debug.print("bool({s})", .{if (value.asBool()) "true" else "false"}),
        .integer => std.debug.print("int({d})", .{value.asInt()}),
        .float => std.debug.print("float({d})", .{value.asFloat()}),
        .string => std.debug.print("string({d}) \"{s}\"", .{ value.getAsString().data.length, value.getAsString().data.data }),
        .array => {
            const arr = value.getAsArray().data;
            std.debug.print("array({d}) {{\n", .{arr.count()});
            var iter = arr.getElements().iterator();
            while (iter.next()) |entry| {
                std.debug.print("{s}", .{ind[0..@min((indent + 1) * 2, ind.len)]});
                switch (entry.key_ptr.*) {
                    .integer => |i| std.debug.print("[{d}]=>\n", .{i}),
                    .string => |s| std.debug.print("[\"{s}\"]=>\n", .{s.data}),
                }
                std.debug.print("{s}", .{ind[0..@min((indent + 1) * 2, ind.len)]});
                dumpValueDebug(entry.value_ptr.*, indent + 1);
                std.debug.print("\n", .{});
            }
            std.debug.print("{s}}}", .{ind[0..@min(indent * 2, ind.len)]});
        },
        .object => std.debug.print("object({s})", .{value.getAsObject().data.class.name.data}),
        else => std.debug.print("unknown", .{}),
    }
}

fn printRFn(_: *VM, args: []const Value) !Value {
    printValueDebug(args[0], 0);
    return Value.initBool(true);
}

fn printValueDebug(value: Value, indent: usize) void {
    const ind = "    " ** 10;
    switch (value.getTag()) {
        .null => {},
        .boolean => std.debug.print("{s}", .{if (value.asBool()) "1" else ""}),
        .integer => std.debug.print("{d}", .{value.asInt()}),
        .float => std.debug.print("{d}", .{value.asFloat()}),
        .string => std.debug.print("{s}", .{value.getAsString().data.data}),
        .array => {
            std.debug.print("Array\n{s}(\n", .{ind[0..@min(indent * 4, ind.len)]});
            var iter = value.getAsArray().data.getElements().iterator();
            while (iter.next()) |entry| {
                std.debug.print("{s}", .{ind[0..@min((indent + 1) * 4, ind.len)]});
                switch (entry.key_ptr.*) {
                    .integer => |i| std.debug.print("[{d}] => ", .{i}),
                    .string => |s| std.debug.print("[{s}] => ", .{s.data}),
                }
                printValueDebug(entry.value_ptr.*, indent + 1);
                std.debug.print("\n", .{});
            }
            std.debug.print("{s})", .{ind[0..@min(indent * 4, ind.len)]});
        },
        else => {},
    }
}

fn varExportFn(_: *VM, args: []const Value) !Value {
    exportValueDebug(args[0]);
    return Value.initNull();
}

fn exportValueDebug(value: Value) void {
    switch (value.getTag()) {
        .null => std.debug.print("NULL", .{}),
        .boolean => std.debug.print("{s}", .{if (value.asBool()) "true" else "false"}),
        .integer => std.debug.print("{d}", .{value.asInt()}),
        .float => std.debug.print("{d}", .{value.asFloat()}),
        .string => std.debug.print("'{s}'", .{value.getAsString().data.data}),
        .array => {
            std.debug.print("array (\n", .{});
            var iter = value.getAsArray().data.getElements().iterator();
            while (iter.next()) |entry| {
                switch (entry.key_ptr.*) {
                    .integer => |i| std.debug.print("  {d} => ", .{i}),
                    .string => |s| std.debug.print("  '{s}' => ", .{s.data}),
                }
                exportValueDebug(entry.value_ptr.*);
                std.debug.print(",\n", .{});
            }
            std.debug.print(")", .{});
        },
        else => std.debug.print("NULL", .{}),
    }
}

// Type functions
fn gettypeFn(vm: *VM, args: []const Value) !Value {
    const type_name = switch (args[0].getTag()) {
        .null => "NULL",
        .boolean => "boolean",
        .integer => "integer",
        .float => "double",
        .string => "string",
        .array => "array",
        .object => "object",
        .resource => "resource",
        else => "unknown type",
    };
    return Value.initString(vm.allocator, type_name);
}

fn settypeFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initBool(true);
}

fn isNullFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .null);
}

fn isBoolFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .boolean);
}

fn isIntFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .integer);
}

fn isFloatFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .float);
}

fn isStringFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .string);
}

fn isArrayFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .array);
}

fn isObjectFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .object);
}

fn isNumericFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return switch (args[0].getTag()) {
        .integer, .float => Value.initBool(true),
        .string => blk: {
            const str = args[0].getAsString().data.data;
            _ = std.fmt.parseFloat(f64, str) catch {
                break :blk Value.initBool(false);
            };
            break :blk Value.initBool(true);
        },
        else => Value.initBool(false),
    };
}

fn isScalarFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(switch (args[0].getTag()) {
        .boolean, .integer, .float, .string => true,
        else => false,
    });
}

fn isResourceFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].getTag() == .resource);
}

fn issetFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    for (args) |arg| {
        if (arg.getTag() == .null) return Value.initBool(false);
    }
    return Value.initBool(true);
}

// Cast functions
fn intvalFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initInt(switch (args[0].getTag()) {
        .integer => args[0].asInt(),
        .float => @intFromFloat(args[0].asFloat()),
        .boolean => if (args[0].asBool()) @as(i64, 1) else @as(i64, 0),
        .string => blk: {
            const str = args[0].getAsString().data.data;
            if (str.len == 0) break :blk 0;

            // 去除前后空白
            var s = std.mem.trim(u8, str, " \t\n\r");
            if (s.len == 0) break :blk 0;

            // 处理符号
            var negative = false;
            if (s[0] == '-') {
                negative = true;
                s = s[1..];
            } else if (s[0] == '+') {
                s = s[1..];
            }

            if (s.len == 0) break :blk 0;

            // 如果包含小数点，先解析为浮点数
            if (std.mem.indexOf(u8, s, ".") != null) {
                if (std.fmt.parseFloat(f64, if (negative) str else s)) |float_val| {
                    break :blk @intFromFloat(float_val);
                } else |_| {}
            }

            // 尝试完整解析
            if (std.fmt.parseInt(i64, s, 10)) |int_val| {
                break :blk if (negative) -int_val else int_val;
            } else |_| {
                // 部分解析：提取前导数字
                var result: i64 = 0;
                for (s) |c| {
                    if (c >= '0' and c <= '9') {
                        result = result * 10 + (c - '0');
                    } else {
                        // 遇到非数字停止
                        break;
                    }
                }
                break :blk if (negative) -result else result;
            }
        },
        else => 0,
    });
}

fn floatvalFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initFloat(switch (args[0].getTag()) {
        .integer => @floatFromInt(args[0].asInt()),
        .float => args[0].asFloat(),
        .boolean => if (args[0].asBool()) @as(f64, 1) else @as(f64, 0),
        .string => std.fmt.parseFloat(f64, args[0].getAsString().data.data) catch 0,
        else => 0,
    });
}

fn strvalFn(vm: *VM, args: []const Value) !Value {
    return switch (args[0].getTag()) {
        .string => args[0],
        .integer => blk: {
            const s = try std.fmt.allocPrint(vm.allocator, "{d}", .{args[0].asInt()});
            defer vm.allocator.free(s);
            break :blk Value.initString(vm.allocator, s);
        },
        .float => blk: {
            const s = try std.fmt.allocPrint(vm.allocator, "{d}", .{args[0].asFloat()});
            defer vm.allocator.free(s);
            break :blk Value.initString(vm.allocator, s);
        },
        .boolean => Value.initString(vm.allocator, if (args[0].asBool()) "1" else ""),
        .null => Value.initString(vm.allocator, ""),
        else => Value.initString(vm.allocator, ""),
    };
}

fn boolvalFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    return Value.initBool(args[0].toBool());
}

// Serialization Functions
fn serializeFn(vm: *VM, args: []const Value) !Value {
    const value = args[0];
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(vm.allocator);

    try serializeValue(vm, &buffer, value);

    return Value.initString(vm.allocator, buffer.items);
}

fn serializeValue(vm: *VM, buffer: *std.ArrayListUnmanaged(u8), value: Value) !void {
    switch (value.getTag()) {
        .null => try buffer.appendSlice(vm.allocator, "N;"),
        .boolean => try buffer.writer(vm.allocator).print("b:{d};", .{if (value.asBool()) @as(i64, 1) else @as(i64, 0)}),
        .integer => try buffer.writer(vm.allocator).print("i:{d};", .{value.asInt()}),
        .float => try buffer.writer(vm.allocator).print("d:{d};", .{value.asFloat()}),
        .string => {
            const str = value.getAsString().data.data;
            try buffer.writer(vm.allocator).print("s:{d}:\"{s}\";", .{ str.len, str });
        },
        .array => {
            const arr = value.getAsArray().data;
            const count = arr.count();
            try buffer.writer(vm.allocator).print("a:{d}:{{", .{count});

            var iterator = arr.getElements().iterator();
            while (iterator.next()) |entry| {
                const key = entry.key_ptr.*;
                const val = entry.value_ptr.*;

                // Serialize key
                switch (key) {
                    .integer => |i| try buffer.writer(vm.allocator).print("i:{d};", .{i}),
                    .string => |s| try buffer.writer(vm.allocator).print("s:{d}:\"{s}\";", .{ s.data.len, s.data }),
                }

                // Serialize value
                try serializeValue(vm, buffer, val);
            }

            try buffer.appendSlice(vm.allocator, "}");
        },
        .object => {
            const obj = value.getAsObject().data;
            const class_name = obj.class.name.data;
            if (obj.class.hasMethod("__serialize")) {
                const data_val = try vm.callObjectMethod(value, "__serialize", &.{});
                defer data_val.release(vm.allocator);

                if (data_val.getTag() == .array) {
                    const arr = data_val.getAsArray().data;
                    const count = arr.count();
                    try buffer.writer(vm.allocator).print("O:{d}:\"{s}\":{d}:{{", .{ class_name.len, class_name, count });

                    var it = arr.getElements().iterator();
                    while (it.next()) |entry| {
                        const key = entry.key_ptr.*;
                        const val = entry.value_ptr.*;

                        switch (key) {
                            .integer => |i| try buffer.writer(vm.allocator).print("i:{d};", .{i}),
                            .string => |s| try buffer.writer(vm.allocator).print("s:{d}:\"{s}\";", .{ s.data.len, s.data }),
                        }

                        try serializeValue(vm, buffer, val);
                    }

                    try buffer.appendSlice(vm.allocator, "}");
                    return;
                }
            }

            var allow_list: ?*PHPArray = null;
            var allow_val: Value = Value.initNull();
            defer if (allow_val.getTag() != .null) allow_val.release(vm.allocator);

            if (obj.class.hasMethod("__sleep")) {
                allow_val = try vm.callObjectMethod(value, "__sleep", &.{});
                if (allow_val.getTag() == .array) {
                    allow_list = allow_val.getAsArray().data;
                }
            }

            const props_count: usize = if (allow_list) |list| list.count() else obj.shape.property_count;
            try buffer.writer(vm.allocator).print("O:{d}:\"{s}\":{d}:{{", .{ class_name.len, class_name, props_count });

            if (allow_list) |list| {
                var it_allow = list.getElements().iterator();
                while (it_allow.next()) |entry| {
                    const name_val = entry.value_ptr.*;
                    if (name_val.getTag() != .string) continue;
                    const prop_name = name_val.getAsString().data.data;

                    const val = if (obj.shape.property_map.get(prop_name)) |offset|
                        obj.property_values.items[offset]
                    else
                        Value.initNull();

                    const full_len = class_name.len + prop_name.len + 2;
                    try buffer.writer(vm.allocator).print("s:{d}:\"", .{full_len});
                    try buffer.appendSlice(vm.allocator, &[_]u8{0});
                    try buffer.appendSlice(vm.allocator, class_name);
                    try buffer.appendSlice(vm.allocator, &[_]u8{0});
                    try buffer.appendSlice(vm.allocator, prop_name);
                    try buffer.appendSlice(vm.allocator, "\";");
                    try serializeValue(vm, buffer, val);
                }
            } else {
                var iterator = obj.shape.property_map.iterator();
                while (iterator.next()) |entry| {
                    const prop_name = entry.key_ptr.*;
                    const offset = entry.value_ptr.*;
                    const val = obj.property_values.items[offset];

                    const full_len = class_name.len + prop_name.len + 2;
                    try buffer.writer(vm.allocator).print("s:{d}:\"", .{full_len});
                    try buffer.appendSlice(vm.allocator, &[_]u8{0});
                    try buffer.appendSlice(vm.allocator, class_name);
                    try buffer.appendSlice(vm.allocator, &[_]u8{0});
                    try buffer.appendSlice(vm.allocator, prop_name);
                    try buffer.appendSlice(vm.allocator, "\";");
                    try serializeValue(vm, buffer, val);
                }
            }

            try buffer.appendSlice(vm.allocator, "}");
        },
        else => try buffer.appendSlice(vm.allocator, "N;"),
    }
}

fn unserializeFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "unserialize() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    var pos: usize = 0;

    return unserializeValue(vm, data, &pos);
}

fn unserializeValue(vm: *VM, data: []const u8, pos: *usize) !Value {
    if (pos.* >= data.len) return Value.initNull();

    const type_char = data[pos.*];
    pos.* += 1;

    return switch (type_char) {
        'N' => blk: {
            pos.* += 1; // Skip ';'
            break :blk Value.initNull();
        },
        'b' => blk: {
            pos.* += 1; // Skip ':'
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const bool_str = data[pos.*..end];
            pos.* = end + 1;
            const value = if (std.mem.eql(u8, bool_str, "1")) true else false;
            break :blk Value.initBool(value);
        },
        'i' => blk: {
            pos.* += 1; // Skip ':'
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const int_str = data[pos.*..end];
            pos.* = end + 1;
            const value = std.fmt.parseInt(i64, int_str, 10) catch 0;
            break :blk Value.initInt(value);
        },
        'd' => blk: {
            pos.* += 1; // Skip ':'
            const end = std.mem.indexOfScalarPos(u8, data, pos.*, ';') orelse data.len;
            const float_str = data[pos.*..end];
            pos.* = end + 1;
            const value = std.fmt.parseFloat(f64, float_str) catch 0;
            break :blk Value.initFloat(value);
        },
        's' => blk: {
            pos.* += 1; // Skip ':'
            const colon = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const len_str = data[pos.*..colon];
            pos.* = colon + 1;
            const len = std.fmt.parseInt(usize, len_str, 10) catch 0;
            pos.* += 1; // Skip '"'
            const str_val = data[pos.* .. pos.* + len];
            pos.* += len + 2; // Skip string and '";'

            const result_str = try PHPString.init(vm.allocator, str_val);
            const box = try vm.allocator.create(types.gc.Box(*PHPString));
            box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = result_str,
            };

            break :blk Value.fromBox(box, Value.TYPE_STRING);
        },
        'a' => blk: {
            pos.* += 1; // Skip ':'
            const count_end = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const count_str = data[pos.*..count_end];
            pos.* = count_end + 1;
            const count = std.fmt.parseInt(usize, count_str, 10) catch 0;
            pos.* += 1; // Skip '{'

            var result_array = try vm.allocator.create(PHPArray);
            errdefer {
                result_array.deinit(vm.allocator);
                vm.allocator.destroy(result_array);
            }
            result_array.* = PHPArray.init(vm.allocator);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                const key = try unserializeValue(vm, data, pos);
                const val = try unserializeValue(vm, data, pos);

                const array_key: ArrayKey = switch (key.getTag()) {
                    .integer => ArrayKey{ .integer = key.asInt() },
                    .string => blk2: {
                        const str = try PHPString.init(vm.allocator, key.getAsString().data.data);
                        break :blk2 ArrayKey{ .string = str };
                    },
                    else => ArrayKey{ .integer = 0 },
                };

                try result_array.set(vm.allocator, array_key, val);
            }

            pos.* += 1; // Skip '}'

            const box = try vm.allocator.create(types.gc.Box(*PHPArray));
            box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = result_array,
            };

            break :blk Value.fromBox(box, Value.TYPE_ARRAY);
        },
        'O' => blk: {
            pos.* += 1; // Skip ':'
            const colon1 = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const name_len_str = data[pos.*..colon1];
            pos.* = colon1 + 1;
            const name_len = std.fmt.parseInt(usize, name_len_str, 10) catch 0;
            pos.* += 1; // Skip '"'
            const class_name = data[pos.* .. pos.* + name_len];
            pos.* += name_len + 2; // Skip class and '":'

            const colon2 = std.mem.indexOfScalarPos(u8, data, pos.*, ':') orelse data.len;
            const count_str = data[pos.*..colon2];
            pos.* = colon2 + 1;
            const count = std.fmt.parseInt(usize, count_str, 10) catch 0;
            pos.* += 1; // Skip '{'

            const obj_val = try vm.createObject(class_name);
            const obj = obj_val.getAsObject().data;

            const data_arr_val = try Value.initArrayWithManager(&vm.memory_manager);
            const data_arr = data_arr_val.getAsArray().data;
            defer data_arr_val.release(vm.allocator);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                const key_val = try unserializeValue(vm, data, pos);
                const val = try unserializeValue(vm, data, pos);
                defer key_val.release(vm.allocator);
                defer val.release(vm.allocator);

                if (key_val.getTag() != .string) continue;
                const raw_key = key_val.getAsString().data.data;
                var prop_name: []const u8 = raw_key;
                if (raw_key.len > 0 and raw_key[0] == 0) {
                    if (std.mem.indexOfScalarPos(u8, raw_key, 1, 0)) |nul2| {
                        if (nul2 + 1 <= raw_key.len) prop_name = raw_key[nul2 + 1 ..];
                    }
                }

                const key_str = try PHPString.init(vm.allocator, prop_name);
                defer key_str.release(vm.allocator);
                try data_arr.set(vm.allocator, ArrayKey{ .string = key_str }, val);
            }

            pos.* += 1; // Skip '}'

            if (obj.class.hasMethod("__unserialize")) {
                const args = [_]Value{data_arr_val};
                _ = try vm.callObjectMethod(obj_val, "__unserialize", &args);
                break :blk obj_val;
            }

            var it = data_arr.getElements().iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (key != .string) continue;
                try obj.setProperty(vm.allocator, key.string.data, entry.value_ptr.*);
            }

            if (obj.class.hasMethod("__wakeup")) {
                _ = vm.callObjectMethod(obj_val, "__wakeup", &.{}) catch {};
            }

            break :blk obj_val;
        },
        else => Value.initNull(),
    };
}

// echo function implementation - supports multiple arguments like echo("a", "b", "c")
fn echoFn(vm: *VM, args: []const Value) !Value {
    _ = vm; // Mark vm parameter as intentionally unused
    // Echo all arguments sequentially without adding newline between them
    for (args) |arg| {
        try arg.print();
    }
    return Value.initNull();
}

// 位运算函数实现
fn bitAndFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    return Value.initInt(a & b);
}

fn bitOrFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    return Value.initInt(a | b);
}

fn bitXorFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    return Value.initInt(a ^ b);
}

fn bitNotFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    return Value.initInt(~a);
}

fn bitShiftLeftFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    const shift: u6 = @intCast(@mod(b, 64));
    return Value.initInt(a << shift);
}

fn bitShiftRightFn(vm: *VM, args: []const Value) !Value {
    const a = try toInteger(vm, args[0]);
    const b = try toInteger(vm, args[1]);
    const shift: u6 = @intCast(@mod(b, 64));
    return Value.initInt(a >> shift);
}

// 三角函数实现
fn sinFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@sin(num));
}

fn cosFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@cos(num));
}

fn tanFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@tan(num));
}

fn logFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    if (args.len > 1) {
        const base = try toFloat(vm, args[1]);
        return Value.initFloat(@log(num) / @log(base));
    }
    return Value.initFloat(@log(num));
}

fn expFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@exp(num));
}

fn piFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initFloat(std.math.pi);
}

fn log10Fn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(@log10(num));
}

fn deg2radFn(vm: *VM, args: []const Value) !Value {
    const degrees = try toFloat(vm, args[0]);
    return Value.initFloat(degrees * std.math.pi / 180.0);
}

fn rad2degFn(vm: *VM, args: []const Value) !Value {
    const radians = try toFloat(vm, args[0]);
    return Value.initFloat(radians * 180.0 / std.math.pi);
}

fn asinFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.asin(num));
}

fn acosFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.acos(num));
}

fn atanFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
    return Value.initFloat(std.math.atan(num));
}

fn atan2Fn(vm: *VM, args: []const Value) !Value {
    const y = try toFloat(vm, args[0]);
    const x = try toFloat(vm, args[1]);
    return Value.initFloat(std.math.atan2(y, x));
}

fn hypotFn(vm: *VM, args: []const Value) !Value {
    const x = try toFloat(vm, args[0]);
    const y = try toFloat(vm, args[1]);
    return Value.initFloat(std.math.hypot(x, y));
}

fn fmodFn(vm: *VM, args: []const Value) !Value {
    const x = try toFloat(vm, args[0]);
    const y = try toFloat(vm, args[1]);
    return Value.initFloat(@mod(x, y));
}

// 辅助函数：将 Value 转换为整数
fn toInteger(vm: *VM, value: Value) !i64 {
    return switch (value.getTag()) {
        .integer => value.asInt(),
        .float => @intFromFloat(value.asFloat()),
        .boolean => if (value.asBool()) @as(i64, 1) else @as(i64, 0),
        .string => std.fmt.parseInt(i64, value.getAsString().data.data, 10) catch 0,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "Cannot convert value to integer", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
}

// 辅助函数：将 Value 转换为浮点数
fn toFloat(vm: *VM, value: Value) !f64 {
    return switch (value.getTag()) {
        .float => value.asFloat(),
        .integer => @floatFromInt(value.asInt()),
        .boolean => if (value.asBool()) @as(f64, 1.0) else @as(f64, 0.0),
        .string => std.fmt.parseFloat(f64, value.getAsString().data.data) catch 0.0,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "Cannot convert value to float", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
}

// PHP sort() - Sort an array in ascending order
fn sortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    // flags parameter (args[1]) ignored for now - uses default SORT_REGULAR

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    // Collect values into a temporary list for sorting
    var values = std.ArrayListUnmanaged(Value){};
    defer values.deinit(vm.allocator);

    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        try values.append(vm.allocator, entry.value_ptr.*);
    }

    // Sort values using comparison
    std.mem.sort(Value, values.items, {}, struct {
        fn lessThan(_: void, a: Value, b: Value) bool {
            return compareValues(a, b) < 0;
        }
    }.lessThan);

    // Clear and rebuild array with numeric keys
    php_array.getElements().clearRetainingCapacity();
    php_array.next_index = 0;

    for (values.items) |value| {
        const key = ArrayKey{ .integer = @intCast(php_array.next_index) };
        php_array.getElements().put(key, value) catch {};
        php_array.next_index += 1;
    }

    return Value.initBool(true);
}

// PHP rsort() - Sort array in descending order
fn rsortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "rsort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    var values = std.ArrayListUnmanaged(Value){};
    defer values.deinit(vm.allocator);

    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        try values.append(vm.allocator, entry.value_ptr.*);
    }

    // Sort in descending order
    std.mem.sort(Value, values.items, {}, struct {
        fn lessThan(_: void, a: Value, b: Value) bool {
            return compareValues(a, b) > 0;
        }
    }.lessThan);

    php_array.getElements().clearRetainingCapacity();
    php_array.next_index = 0;

    for (values.items) |value| {
        const key = ArrayKey{ .integer = @intCast(php_array.next_index) };
        php_array.getElements().put(key, value) catch {};
        php_array.next_index += 1;
    }

    return Value.initBool(true);
}

// PHP asort() - Sort array maintaining index association
fn asortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "asort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;
    var items = try collectArraySortItems(vm, php_array);
    defer items.deinit(vm.allocator);

    std.mem.sort(ArraySortItem, items.items, {}, struct {
        fn lessThan(_: void, a: ArraySortItem, b: ArraySortItem) bool {
            return compareValues(a.value, b.value) < 0;
        }
    }.lessThan);

    rebuildArrayWithSortedItems(php_array, items.items);
    return Value.initBool(true);
}

// PHP arsort() - Sort array in descending order maintaining index association
fn arsortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "arsort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;
    var items = try collectArraySortItems(vm, php_array);
    defer items.deinit(vm.allocator);

    std.mem.sort(ArraySortItem, items.items, {}, struct {
        fn lessThan(_: void, a: ArraySortItem, b: ArraySortItem) bool {
            return compareValues(a.value, b.value) > 0;
        }
    }.lessThan);

    rebuildArrayWithSortedItems(php_array, items.items);
    return Value.initBool(true);
}

// PHP ksort() - Sort array by key
fn ksortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ksort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;
    var items = try collectArraySortItems(vm, php_array);
    defer items.deinit(vm.allocator);

    std.mem.sort(ArraySortItem, items.items, {}, struct {
        fn lessThan(_: void, a: ArraySortItem, b: ArraySortItem) bool {
            return compareArrayKeys(a.key, b.key) < 0;
        }
    }.lessThan);

    rebuildArrayWithSortedItems(php_array, items.items);
    return Value.initBool(true);
}

// PHP krsort() - Sort array by key in descending order
fn krsortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "krsort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;
    var items = try collectArraySortItems(vm, php_array);
    defer items.deinit(vm.allocator);

    std.mem.sort(ArraySortItem, items.items, {}, struct {
        fn lessThan(_: void, a: ArraySortItem, b: ArraySortItem) bool {
            return compareArrayKeys(a.key, b.key) > 0;
        }
    }.lessThan);

    rebuildArrayWithSortedItems(php_array, items.items);
    return Value.initBool(true);
}

// PHP usort() - Sort array by user-defined comparison function
fn usortFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "usort() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    _ = callback;
    _ = array.getAsArray().data;
    return Value.initBool(true);
}

// PHP count() / sizeof() - Count elements in array
fn countFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    const value = args[0];

    return switch (value.getTag()) {
        .array => Value.initInt(@intCast(value.getAsArray().data.count())),
        .string => Value.initInt(@intCast(value.getAsString().data.length)),
        .null => Value.initInt(0),
        else => Value.initInt(1),
    };
}

// PHP array_key_exists() - Check if key exists in array
fn arrayKeyExistsFn(vm: *VM, args: []const Value) !Value {
    const key = args[0];
    const array = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_key_exists() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const php_array = array.getAsArray().data;

    const exists = switch (key.getTag()) {
        .integer => php_array.getElements().contains(ArrayKey{ .integer = key.asInt() }),
        .string => php_array.getElements().contains(ArrayKey{ .string = key.getAsString().data }),
        else => false,
    };

    return Value.initBool(exists);
}

// PHP array_combine() - Create array using one array for keys and another for values
fn arrayCombineFn(vm: *VM, args: []const Value) !Value {
    const keys = args[0];
    const values = args[1];

    if (keys.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_combine() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (values.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_combine() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const keys_array = keys.getAsArray().data;
    const values_array = values.getAsArray().data;

    if (keys_array.count() != values_array.count()) {
        // array_combine(): Number of elements in key and value arrays don't match
        // Note: This is a warning in PHP, continuing with result
    }

    const result = try Value.initArrayWithManager(&vm.memory_manager);
    errdefer result.release(vm.allocator);

    const result_arr = result.getAsArray().data;

    var key_idx: i64 = 0;
    var value_idx: i64 = 0;

    while (true) {
        const key_opt = keys_array.get(ArrayKey{ .integer = key_idx });
        const value_opt = values_array.get(ArrayKey{ .integer = value_idx });

        if (key_opt == null or value_opt == null) break;

        const key_copy = key_opt.?.retain();
        const value_copy = value_opt.?.retain();

        const array_key = switch (key_copy.getTag()) {
            .integer => ArrayKey{ .integer = key_copy.asInt() },
            .string => ArrayKey{ .string = key_copy.getAsString().data },
            else => ArrayKey{ .integer = key_idx },
        };

        result_arr.set(vm.allocator, array_key, value_copy) catch {};
        key_idx += 1;
        value_idx += 1;
    }

    return result;
}

// PHP array_intersect() - Returns the values of array1 that are present in all the arrays
fn arrayIntersectFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        // array_intersect(): At least two parameters are required
        // Return empty array for now
        return Value.initArrayWithManager(&vm.memory_manager);
    }

    const array1 = args[0];
    if (array1.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_intersect() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr1 = array1.getAsArray().data;

    // Collect all values from all other arrays into a set
    // Using a simple approach: for each value in arr1, check if it exists in all other arrays
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    errdefer result.release(vm.allocator);

    const result_arr = result.getAsArray().data;

    // For each value in arr1, check if it exists in all other arrays
    var iter1 = arr1.getElements().iterator();
    while (iter1.next()) |entry1| {
        const value1 = entry1.value_ptr.*;

        // Check if this value exists in all other arrays
        var found_in_all = true;
        for (args[1..]) |arg| {
            if (arg.getTag() != .array) {
                found_in_all = false;
                break;
            }

            const arr = arg.getAsArray().data;
            var found = false;
            var iter = arr.getElements().iterator();
            while (iter.next()) |entry| {
                const value = entry.value_ptr.*;

                // Compare values
                const equal = blk: {
                    // Both integers
                    if (value1.getTag() == .integer and value.getTag() == .integer) {
                        break :blk value1.asInt() == value.asInt();
                    }
                    // Both floats
                    if (value1.getTag() == .float and value.getTag() == .float) {
                        break :blk value1.asFloat() == value.asFloat();
                    }
                    // Both strings
                    if (value1.getTag() == .string and value.getTag() == .string) {
                        const str1 = value1.getAsString().data.data;
                        const str2 = value.getAsString().data.data;
                        break :blk std.mem.eql(u8, str1, str2);
                    }
                    // Integer and float comparison
                    if (value1.getTag() == .integer and value.getTag() == .float) {
                        break :blk @as(f64, @floatFromInt(value1.asInt())) == value.asFloat();
                    }
                    if (value1.getTag() == .float and value.getTag() == .integer) {
                        break :blk value1.asFloat() == @as(f64, @floatFromInt(value.asInt()));
                    }
                    break :blk false;
                };

                if (equal) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                found_in_all = false;
                break;
            }
        }

        if (found_in_all) {
            const value_copy = value1.retain();
            result_arr.set(vm.allocator, ArrayKey{ .integer = @as(i64, @intCast(result_arr.count())) }, value_copy) catch {};
        }
    }

    return result;
}

// PHP array_diff() - Returns the values of array1 that are not present in the other arrays
fn arrayDiffFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        // array_diff(): At least two parameters are required
        return Value.initArrayWithManager(&vm.memory_manager);
    }

    const array1 = args[0];
    if (array1.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_diff() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr1 = array1.getAsArray().data;

    // Collect all values from all other arrays into a set
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    errdefer result.release(vm.allocator);

    const result_arr = result.getAsArray().data;

    // For each value in arr1, check if it exists in any other array
    var iter1 = arr1.getElements().iterator();
    while (iter1.next()) |entry1| {
        const value1 = entry1.value_ptr.*;

        // Check if this value exists in any other array
        var found = false;
        for (args[1..]) |arg| {
            if (arg.getTag() != .array) continue;

            const arr = arg.getAsArray().data;
            var iter = arr.getElements().iterator();
            while (iter.next()) |entry| {
                const value = entry.value_ptr.*;

                // Compare values
                const equal = blk: {
                    // Both integers
                    if (value1.getTag() == .integer and value.getTag() == .integer) {
                        break :blk value1.asInt() == value.asInt();
                    }
                    // Both floats
                    if (value1.getTag() == .float and value.getTag() == .float) {
                        break :blk value1.asFloat() == value.asFloat();
                    }
                    // Both strings
                    if (value1.getTag() == .string and value.getTag() == .string) {
                        const str1 = value1.getAsString().data.data;
                        const str2 = value.getAsString().data.data;
                        break :blk std.mem.eql(u8, str1, str2);
                    }
                    // Integer and float comparison
                    if (value1.getTag() == .integer and value.getTag() == .float) {
                        break :blk @as(f64, @floatFromInt(value1.asInt())) == value.asFloat();
                    }
                    if (value1.getTag() == .float and value.getTag() == .integer) {
                        break :blk value1.asFloat() == @as(f64, @floatFromInt(value.asInt()));
                    }
                    break :blk false;
                };

                if (equal) {
                    found = true;
                    break;
                }
            }

            if (found) break;
        }

        if (!found) {
            const value_copy = value1.retain();
            result_arr.set(vm.allocator, ArrayKey{ .integer = @as(i64, @intCast(result_arr.count())) }, value_copy) catch {};
        }
    }

    return result;
}

// Array pointer functions
fn arrayRandFn(vm: *VM, args: []const Value) !Value {
    const arr_val = args[0];
    if (arr_val.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_rand() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = arr_val.getAsArray().data;
    const count = arr.count();
    if (count == 0) return Value.initNull();

    const num = if (args.len > 1) @as(usize, @intCast(@max(1, args[1].asInt()))) else 1;

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();

    if (num == 1) {
        // Return single key
        const idx = random.intRangeAtMost(usize, 0, count - 1);
        var iter = arr.getElements().iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            if (i == idx) {
                return switch (entry.key_ptr.*) {
                    .integer => |int| Value.initInt(int),
                    .string => |str| Value.initString(vm.allocator, str.data),
                };
            }
        }
    }

    // Return array of keys
    const result = try vm.allocator.create(PHPArray);
    result.* = PHPArray.init(vm.allocator);

    var selected = try std.ArrayList(usize).initCapacity(vm.allocator, num);
    defer selected.deinit(vm.allocator);

    while (selected.items.len < @min(num, count)) {
        const idx = random.intRangeAtMost(usize, 0, count - 1);
        var found = false;
        for (selected.items) |s| {
            if (s == idx) {
                found = true;
                break;
            }
        }
        if (!found) {
            try selected.append(vm.allocator, idx);
        }
    }

    var iter = arr.getElements().iterator();
    var i: usize = 0;
    var result_idx: i64 = 0;
    while (iter.next()) |entry| : (i += 1) {
        for (selected.items) |s| {
            if (s == i) {
                const key_val = switch (entry.key_ptr.*) {
                    .integer => |int| Value.initInt(int),
                    .string => |str| try Value.initString(vm.allocator, str.data),
                };
                try result.set(vm.allocator, .{ .integer = result_idx }, key_val);
                result_idx += 1;
                break;
            }
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn endFn(_: *VM, args: []const Value) !Value {
    const arr_val = args[0];
    if (arr_val.getTag() != .array) return Value.initBool(false);

    const arr = arr_val.getAsArray().data;
    if (arr.count() == 0) return Value.initBool(false);

    var iter = arr.getElements().iterator();
    var last: ?Value = null;
    while (iter.next()) |entry| {
        last = entry.value_ptr.*;
    }

    return if (last) |v| v else Value.initBool(false);
}

fn resetFn(_: *VM, args: []const Value) !Value {
    const arr_val = args[0];
    if (arr_val.getTag() != .array) return Value.initBool(false);

    const arr = arr_val.getAsArray().data;
    if (arr.count() == 0) return Value.initBool(false);

    var iter = arr.getElements().iterator();
    if (iter.next()) |entry| {
        return entry.value_ptr.*;
    }

    return Value.initBool(false);
}

fn currentFn(vm: *VM, args: []const Value) !Value {
    return resetFn(vm, args);
}

fn keyFn(vm: *VM, args: []const Value) !Value {
    const arr_val = args[0];
    if (arr_val.getTag() != .array) return Value.initNull();

    const arr = arr_val.getAsArray().data;
    if (arr.count() == 0) return Value.initNull();

    var iter = arr.getElements().iterator();
    if (iter.next()) |entry| {
        return switch (entry.key_ptr.*) {
            .integer => |i| Value.initInt(i),
            .string => |s| Value.initString(vm.allocator, s.data),
        };
    }

    return Value.initNull();
}

fn nextFn(vm: *VM, args: []const Value) !Value {
    return resetFn(vm, args);
}

fn prevFn(vm: *VM, args: []const Value) !Value {
    return resetFn(vm, args);
}

// PHP array_splice() - Remove a portion of the array and replace it
fn arraySpliceFn(vm: *VM, args: []const Value) !Value {
    const input_array = args[0];
    const offset = args[1].asInt();

    if (input_array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_splice() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const length = if (args.len > 2) args[2].asInt() else null;
    const replacement = if (args.len > 3) args[3] else null;

    const arr = input_array.getAsArray().data;
    const arr_count = @as(i64, @intCast(arr.count()));

    // Create result array (removed elements)
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    errdefer result.release(vm.allocator);

    const result_arr = result.getAsArray().data;

    // Calculate actual start and end
    const start = if (offset < 0) arr_count + offset else offset;
    const end = if (length) |l| start + l else arr_count;

    // Copy removed elements to result
    var idx: i64 = 0;
    var result_idx: i64 = 0;
    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;
        if (idx >= start and idx < end) {
            const value_copy = value.retain();
            result_arr.set(vm.allocator, ArrayKey{ .integer = result_idx }, value_copy) catch {};
            result_idx += 1;
        }
        idx += 1;
    }

    // Now actually modify the original array
    // Remove the elements in the specified range
    if (start >= 0 and start < arr_count) {
        const actual_end = if (end > arr_count) arr_count else end;
        _ = arr.removeRange(vm.allocator, start, actual_end);

        // Insert replacement elements if provided
        if (replacement) |rep| {
            if (rep.getTag() == .array) {
                const rep_arr = rep.getAsArray().data;
                var rep_iter = rep_arr.getElements().iterator();
                var insert_idx = start;
                while (rep_iter.next()) |entry| {
                    const rep_value = entry.value_ptr.*;
                    try arr.insertAt(vm.allocator, insert_idx, rep_value.retain());
                    insert_idx += 1;
                }
            }
        }
    }

    return result;
}

// PHP array_walk() - Apply a user function to every element of an array
fn arrayWalkFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_walk() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const userdata = if (args.len > 2) args[2] else null;

    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const key_value = switch (key) {
            .integer => Value.initInt(key.integer),
            .string => Value.initStringWithManager(&vm.memory_manager, key.string.data) catch Value.initNull(),
        };

        // Build callback arguments
        var callback_args = try std.ArrayList(Value).initCapacity(vm.allocator, 3);
        defer callback_args.deinit(vm.allocator);
        try callback_args.append(vm.allocator, value.retain());
        try callback_args.append(vm.allocator, key_value);
        if (userdata) |ud| {
            try callback_args.append(vm.allocator, ud.retain());
        }

        const result_value = switch (callback.getTag()) {
            .native_function => blk: {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
                break :blk try function(vm, callback_args.items);
            },
            .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, callback_args.items),
            .closure => try vm.callClosure(callback.getAsClosure().data, callback_args.items),
            .arrow_function => try vm.callArrowFunction(callback.getAsArrowFunc().data, callback_args.items),
            else => {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_walk() expects parameter 2 to be a valid callback", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidArgumentType;
            },
        };
        _ = result_value; // Ignore callback return value
    }

    return Value.initBool(true);
}

// PHP array_chunk() - Split an array into chunks (optimized)
fn arrayChunkFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const size = args[1];
    const preserve_keys = if (args.len > 2) args[2].asBool() else false;

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_chunk() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const chunk_size = @as(usize, @intCast(size.asInt()));
    if (chunk_size < 1) {
        const exception = try ExceptionFactory.createValueError(vm.allocator, "array_chunk() size parameter must be positive", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const count = arr.count();

    // Pre-allocate temp ArrayList with exact size
    var temp = std.ArrayListUnmanaged(struct { key: ArrayKey, value: Value }){};
    try temp.ensureTotalCapacity(vm.allocator, count);
    defer temp.deinit(vm.allocator);

    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        temp.appendAssumeCapacity(.{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
    }

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    var chunk_idx: i64 = 0;
    var chunk_array: ?*PHPArray = null;
    var element_idx: usize = 0;

    for (temp.items) |item| {
        if (chunk_array == null or element_idx >= chunk_size) {
            // Create a new chunk array
            const new_chunk = try vm.allocator.create(PHPArray);
            errdefer vm.allocator.destroy(new_chunk);
            new_chunk.* = PHPArray.init(vm.allocator);

            // If there's a previous chunk, add it to result
            if (chunk_array) |prev_chunk| {
                const chunk_str = try std.fmt.allocPrint(vm.allocator, "{d}", .{chunk_idx});
                const chunk_key = try PHPString.init(vm.allocator, chunk_str);

                const chunk_box = try vm.allocator.create(types.gc.Box(*PHPArray));
                chunk_box.* = .{ .ref_count = 1, .gc_info = .{}, .data = prev_chunk };

                try result_array.set(vm.allocator, .{ .string = chunk_key }, Value.fromBox(chunk_box, Value.TYPE_ARRAY));
                chunk_idx += 1;
            }

            chunk_array = new_chunk;
            element_idx = 0;
        }

        const current_chunk = chunk_array orelse continue;

        if (preserve_keys) {
            try current_chunk.set(vm.allocator, item.key, item.value);
        } else {
            const int_key: i64 = @as(i64, @intCast(element_idx));
            try current_chunk.set(vm.allocator, .{ .integer = int_key }, item.value);
        }
        element_idx += 1;
    }

    // Add the last chunk
    if (chunk_array) |last_chunk| {
        const chunk_str = try std.fmt.allocPrint(vm.allocator, "{d}", .{chunk_idx});
        const chunk_key = try PHPString.init(vm.allocator, chunk_str);

        const chunk_box = try vm.allocator.create(types.gc.Box(*PHPArray));
        chunk_box.* = .{ .ref_count = 1, .gc_info = .{}, .data = last_chunk };

        try result_array.set(vm.allocator, .{ .string = chunk_key }, Value.fromBox(chunk_box, Value.TYPE_ARRAY));
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_array };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// PHP array_pad() - Pad array to specified length
fn arrayPadFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const pad_size = args[1];
    const pad_value = args[2];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_pad() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const count = arr.getElements().count();
    const target_size = @as(usize, @intCast(pad_size.asInt()));

    if (target_size < count) {
        // No padding needed, just return a copy of the array
        const result = try vm.allocator.create(PHPArray);
        errdefer vm.allocator.destroy(result);
        result.* = PHPArray.init(vm.allocator);

        // Pre-allocate capacity
        try result.getElements().ensureTotalCapacity(count);

        var iter = arr.getElements().iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            switch (key) {
                .integer => {
                    result.getElements().putAssumeCapacity(.{ .integer = key.integer }, value.retain());
                },
                .string => {
                    const str_key = try PHPString.init(vm.allocator, key.string.data);
                    result.getElements().putAssumeCapacity(.{ .string = str_key }, value.retain());
                },
            }
        }

        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }

    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    const pad_needed = target_size - count;
    const before_pad = if (pad_size.asInt() < 0) @as(usize, @intCast(-pad_size.asInt())) else 0;
    const after_pad = pad_needed - before_pad;

    // Pre-allocate capacity for all elements
    try result.getElements().ensureTotalCapacity(target_size);

    // Add before padding
    var i: usize = 0;
    while (i < before_pad) : (i += 1) {
        const int_key: i64 = @as(i64, @intCast(-@as(i64, @intCast(i + 1))));
        result.getElements().putAssumeCapacity(.{ .integer = int_key }, pad_value.retain());
    }

    // Copy original array
    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        switch (key) {
            .integer => {
                result.getElements().putAssumeCapacity(.{ .integer = key.integer }, value);
            },
            .string => {
                const str_key = try PHPString.init(vm.allocator, key.string.data);
                result.getElements().putAssumeCapacity(.{ .string = str_key }, value);
            },
        }
    }

    // Add after padding
    i = 0;
    while (i < after_pad) : (i += 1) {
        const int_key: i64 = @as(i64, @intCast(count + i));
        result.getElements().putAssumeCapacity(.{ .integer = int_key }, pad_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// PHP array_key_first() - Get the first key of an array
fn arrayKeyFirstFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_key_first() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    if (arr.getElements().count() == 0) {
        return Value.initBool(false);
    }

    if (arr.getElements().count() == 0) {
        return Value.initBool(false);
    }

    var iter = arr.getElements().iterator();
    const first_entry = iter.next() orelse return Value.initBool(false);
    const first_key = first_entry.key_ptr.*;

    return switch (first_key) {
        .integer => Value.initInt(first_key.integer),
        .string => Value.initStringWithManager(&vm.memory_manager, first_key.string.data) catch Value.initNull(),
    };
}

// PHP array_key_last() - Get the last key of an array
fn arrayKeyLastFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_key_last() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    if (arr.getElements().count() == 0) {
        return Value.initBool(false);
    }

    var last_key: ArrayKey = undefined;
    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        last_key = entry.key_ptr.*;
    }

    return switch (last_key) {
        .integer => Value.initInt(last_key.integer),
        .string => Value.initStringWithManager(&vm.memory_manager, last_key.string.data) catch Value.initNull(),
    };
}

// PHP array_fill_keys() - Fill an array with values, specifying keys
fn arrayFillKeysFn(vm: *VM, args: []const Value) !Value {
    const keys = args[0];
    const value = args[1];

    if (keys.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_fill_keys() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const keys_arr = keys.getAsArray().data;
    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    var iter = keys_arr.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const key_copy = switch (key) {
            .integer => ArrayKey{ .integer = key.integer },
            .string => blk: {
                const str_key = try PHPString.init(vm.allocator, key.string.data);
                break :blk ArrayKey{ .string = str_key };
            },
        };
        try result.set(vm.allocator, key_copy, value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// PHP array_change_key_case() - Changes the case of array keys
fn arrayChangeKeyCaseFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const case_type = if (args.len > 1) args[1].asInt() else 0; // 0 = CASE_LOWER, 1 = CASE_UPPER

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_change_key_case() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const new_key = switch (key) {
            .integer => key, // Integers stay the same
            .string => blk: {
                const new_data = try vm.allocator.alloc(u8, key.string.data.len);
                @memcpy(new_data, key.string.data);
                for (new_data) |*c| {
                    if (case_type == 0) {
                        c.* = std.ascii.toLower(c.*);
                    } else {
                        c.* = std.ascii.toUpper(c.*);
                    }
                }
                const str_key = try PHPString.init(vm.allocator, new_data);
                break :blk ArrayKey{ .string = str_key };
            },
        };
        try result.set(vm.allocator, new_key, value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// PHP array_count_values() - Counts all the values of an array
fn arrayCountValuesFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_count_values() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const arr = array.getAsArray().data;
    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    var iter = arr.getElements().iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;

        // Use value as key (integers and strings only)
        const key: ArrayKey = switch (value.getTag()) {
            .integer => .{ .integer = value.asInt() },
            .string => .{ .string = value.getAsString().data },
            else => continue,
        };

        // Check if key already exists and increment count
        const existing = result.getElements().get(key);
        if (existing) |count_val| {
            try result.set(vm.allocator, key, Value.initInt(count_val.asInt() + 1));
        } else {
            try result.set(vm.allocator, key, Value.initInt(1));
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// bin2hex - Convert binary data to hexadecimal
fn bin2hexFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "bin2hex() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    const hex_len = data.len * 2;
    const hex_str = try vm.allocator.alloc(u8, hex_len);

    const hex_chars = "0123456789abcdef";
    for (data, 0..) |byte, i| {
        hex_str[i * 2] = hex_chars[byte >> 4];
        hex_str[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    const result_str = try PHPString.init(vm.allocator, hex_str);
    defer vm.allocator.free(hex_str);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

// hex2bin - Decode hexadecimal string
fn hex2binFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "hex2bin() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const hex_data = str.getAsString().data.data;
    if (hex_data.len % 2 != 0) {
        return Value.initBool(false);
    }

    const bin_len = hex_data.len / 2;
    const bin_str = try vm.allocator.alloc(u8, bin_len);

    for (0..bin_len) |i| {
        const high = hexCharToInt(hex_data[i * 2]) orelse {
            vm.allocator.free(bin_str);
            return Value.initBool(false);
        };
        const low = hexCharToInt(hex_data[i * 2 + 1]) orelse {
            vm.allocator.free(bin_str);
            return Value.initBool(false);
        };
        bin_str[i] = (high << 4) | low;
    }

    const result_str = try PHPString.init(vm.allocator, bin_str);
    defer vm.allocator.free(bin_str);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

fn hexCharToInt(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

// base64_encode - Simple base64 encoding
fn base64EncodeFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "base64_encode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    const encoded = std.base64.standard.Encoder.calcSize(data.len);
    const result = try vm.allocator.alloc(u8, encoded);
    _ = std.base64.standard.Encoder.encode(result, data);

    const result_str = try PHPString.init(vm.allocator, result);
    defer vm.allocator.free(result);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

// base64_decode - Simple base64 decoding
fn base64DecodeFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "base64_decode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(data) catch return Value.initBool(false);
    const result = try vm.allocator.alloc(u8, decoded_size);
    _ = std.base64.standard.Decoder.decode(result, data) catch {
        vm.allocator.free(result);
        return Value.initBool(false);
    };

    const result_str = try PHPString.init(vm.allocator, result);
    defer vm.allocator.free(result);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

// ord - Get ASCII value of first character
fn ordFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ord() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const data = str.getAsString().data.data;
    if (data.len == 0) {
        return Value.initInt(0);
    }
    return Value.initInt(@intCast(data[0]));
}

// HTTP Functions
fn headerFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    // In a real implementation, this would set HTTP headers
    // For now, we just ignore it (common in CLI mode)
    _ = args;
    return Value.initNull();
}

fn httpResponseCodeFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    if (args.len > 0) {
        // Set response code - ignore in CLI mode
        return args[0];
    }
    return Value.initInt(200); // Default response code
}

fn exitFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    if (args.len > 0) {
        const arg = args[0];
        if (arg.getTag() == .string) {
            try arg.print();
        }
    }
    return error.Exit;
}

// chr - Get character from ASCII value
fn chrFn(vm: *VM, args: []const Value) !Value {
    const code = args[0];
    if (code.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "chr() expects parameter 1 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const byte_val = code.asInt();
    const char_buf = try vm.allocator.alloc(u8, 1);
    char_buf[0] = @truncate(@as(u64, @bitCast(byte_val)));

    const result_str = try PHPString.init(vm.allocator, char_buf);
    defer vm.allocator.free(char_buf);
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result_str };
    return Value.fromBox(box, Value.TYPE_STRING);
}

// File operation functions
const FileResource = struct {
    file: std.fs.File,
    mode: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, file: std.fs.File, mode: []const u8) !*FileResource {
        const resource = try allocator.create(FileResource);
        resource.* = .{
            .file = file,
            .mode = try allocator.dupe(u8, mode),
            .allocator = allocator,
        };
        return resource;
    }

    pub fn deinit(self: *FileResource) void {
        self.file.close();
        self.allocator.free(self.mode);
        self.allocator.destroy(self);
    }
};

fn fopenFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    const mode = args[1];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fopen() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (mode.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fopen() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const filename_str = filename.getAsString().data.data;
    const mode_str = mode.getAsString().data.data;

    // For simplicity, just try to open as read-only first
    // fopen in PHP returns false on failure, so we handle errors gracefully
    const file = std.fs.cwd().openFile(filename_str, .{ .mode = .read_only }) catch {
        return Value.initBool(false); // PHP returns false on failure
    };

    const file_resource = try FileResource.init(vm.allocator, file, mode_str);
    const type_name = try types.PHPString.init(vm.allocator, "file");

    const resource_data = types.PHPResource.init(type_name, file_resource, &fileResourceDestructor);
    return Value.initResourceWithManager(&vm.memory_manager, resource_data);
}

fn fileResourceDestructor(data: *anyopaque) void {
    const file_resource: *FileResource = @ptrCast(@alignCast(data));
    file_resource.deinit();
}

fn freadFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];
    const length = args[1];

    if (handle.getTag() != .resource) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fread() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (length.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fread() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const resource = handle.getAsResource().data;
    if (!std.mem.eql(u8, resource.type_name.data, "file")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fread(): Not a valid file handle", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_resource: *FileResource = @ptrCast(@alignCast(resource.data));
    const read_length = length.asInt();

    if (read_length <= 0) {
        return Value.initStringWithManager(&vm.memory_manager, "");
    }

    const buffer = try vm.allocator.alloc(u8, @intCast(read_length));
    defer vm.allocator.free(buffer);

    const bytes_read = file_resource.file.read(buffer) catch {
        return Value.initStringWithManager(&vm.memory_manager, "");
    };

    return Value.initStringWithManager(&vm.memory_manager, buffer[0..bytes_read]);
}

fn fcloseFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];

    if (handle.getTag() != .resource) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fclose() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const resource = handle.getAsResource().data;
    if (!std.mem.eql(u8, resource.type_name.data, "file")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fclose(): Not a valid file handle", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // The resource destructor will handle cleanup
    resource.destroy();

    return Value.initBool(true);
}

fn feofFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];

    if (handle.getTag() != .resource) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "feof() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const resource = handle.getAsResource().data;
    if (!std.mem.eql(u8, resource.type_name.data, "file")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "feof(): Not a valid file handle", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_resource: *FileResource = @ptrCast(@alignCast(resource.data));
    // Simplified EOF check - try to get file position vs size
    const pos = file_resource.file.getPos() catch 0;
    const end_pos = file_resource.file.getEndPos() catch 0;
    const is_eof = pos >= end_pos;

    return Value.initBool(is_eof);
}

fn fwriteFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];
    const string = args[1];

    if (handle.getTag() != .resource) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fwrite() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (string.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fwrite() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const resource = handle.getAsResource().data;
    if (!std.mem.eql(u8, resource.type_name.data, "file")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fwrite(): Not a valid file handle", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_resource: *FileResource = @ptrCast(@alignCast(resource.data));
    const str_data = string.getAsString().data.data;

    const bytes_written = file_resource.file.write(str_data) catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(bytes_written));
}
