const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;

// Forward declaration for VM
const VM = @import("vm.zig").VM;

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

        // Register PHP 8.5 URI functions
        const php85 = @import("php85_features.zig");
        try php85.registerUriFunctions(&stdlib);

        // Register extended functions
        const stdlib_ext = @import("stdlib_ext.zig");
        try stdlib_ext.registerExtendedFunctions(&stdlib);

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
            &.{ .name = "strpos", .min_args = 2, .max_args = 3, .handler = strposFn },
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
            &.{ .name = "isset", .min_args = 1, .max_args = 255, .handler = issetFn },
            // Cast functions
            &.{ .name = "intval", .min_args = 1, .max_args = 2, .handler = intvalFn },
            &.{ .name = "floatval", .min_args = 1, .max_args = 1, .handler = floatvalFn },
            &.{ .name = "strval", .min_args = 1, .max_args = 1, .handler = strvalFn },
            &.{ .name = "boolval", .min_args = 1, .max_args = 1, .handler = boolvalFn },
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
            &.{ .name = "exp", .min_args = 1, .max_args = 1, .handler = expFn },
        };

        for (math_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // File System Functions
    pub fn registerFileFunctions(self: *StandardLibrary) !void {
        const file_functions = [_]*const BuiltinFunction{
            &.{ .name = "file_get_contents", .min_args = 1, .max_args = 5, .handler = fileGetContentsFn },
            &.{ .name = "file_put_contents", .min_args = 2, .max_args = 4, .handler = filePutContentsFn },
            &.{ .name = "file_exists", .min_args = 1, .max_args = 1, .handler = fileExistsFn },
            &.{ .name = "is_file", .min_args = 1, .max_args = 1, .handler = isFileFn },
            &.{ .name = "is_dir", .min_args = 1, .max_args = 1, .handler = isDirFn },
            &.{ .name = "filesize", .min_args = 1, .max_args = 1, .handler = filesizeFn },
            &.{ .name = "basename", .min_args = 1, .max_args = 2, .handler = basenameFn },
            &.{ .name = "dirname", .min_args = 1, .max_args = 2, .handler = dirnameFn },
        };

        for (file_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }

    // Date/Time Functions
    pub fn registerDateTimeFunctions(self: *StandardLibrary) !void {
        const datetime_functions = [_]*const BuiltinFunction{
            &.{ .name = "time", .min_args = 0, .max_args = 0, .handler = timeFn },
            &.{ .name = "date", .min_args = 1, .max_args = 2, .handler = dateFn },
            &.{ .name = "strtotime", .min_args = 1, .max_args = 2, .handler = strtotimeFn },
            &.{ .name = "mktime", .min_args = 0, .max_args = 6, .handler = mktimeFn },
            &.{ .name = "gmdate", .min_args = 1, .max_args = 2, .handler = gmdateFn },
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
};

// Array Function Implementations
fn arrayMapFn(vm: *VM, args: []const Value) !Value {
    const callback = args[0];
    const array = args[1];

    if (array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_map() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var iterator = array.getAsArray().data.elements.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        // Call callback function with value
        const callback_args = [_]Value{value};
        const result_value = switch (callback.getTag()) {
            .native_function => blk: {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
                break :blk try function(vm, &callback_args);
            },
            .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, &callback_args),
            .closure => try vm.callClosure(callback.getAsClosure().data, &callback_args),
            .arrow_function => try vm.callArrowFunction(callback.getAsArrowFunc().data, &callback_args),
            else => {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_map() expects parameter 1 to be a valid callback", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidArgumentType;
            },
        };

        try result_array.set(vm.allocator, key, result_value);
        vm.releaseValue(result_value);
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

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    const callback = if (args.len > 1) args[1] else null;

    var iterator = array.getAsArray().data.elements.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        var should_include = false;

        if (callback) |cb| {
            // Call callback function with value
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
                    const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_filter() expects parameter 2 to be a valid callback", "builtin", 0);
                    _ = try vm.throwException(exception);
                    return error.InvalidArgumentType;
                },
            };
            should_include = result_value.toBool();
        } else {
            // No callback, filter out falsy values
            should_include = value.toBool();
        }

        if (should_include) {
            try result_array.set(vm.allocator, key, value);
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

    var iterator = array.getAsArray().data.elements.iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        // Call callback function with accumulator and current value
        const callback_args = [_]Value{ accumulator, value };
        accumulator = switch (callback.getTag()) {
            .native_function => blk: {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
                break :blk try function(vm, &callback_args);
            },
            .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, &callback_args),
            .closure => try vm.callClosure(callback.getAsClosure().data, &callback_args),
            .arrow_function => try vm.callArrowFunction(callback.getAsArrowFunc().data, &callback_args),
            else => {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_reduce() expects parameter 2 to be a valid callback", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidArgumentType;
            },
        };
    }

    return accumulator;
}

fn arrayMergeFn(vm: *VM, args: []const Value) !Value {
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    for (args) |arg| {
        if (arg.getTag() != .array) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_merge() expects all parameters to be arrays", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }

        var iterator = arg.getAsArray().data.elements.iterator();
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // For numeric keys, reindex; for string keys, preserve
            switch (key) {
                .integer => try result_array.push(vm.allocator, value),
                .string => try result_array.set(vm.allocator, key, value),
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

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var iterator = array.getAsArray().data.elements.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;

        const key_value = switch (key) {
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

        try result_array.push(vm.allocator, key_value);
        vm.releaseValue(key_value);
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

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var iterator = array.getAsArray().data.elements.iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        try result_array.push(vm.allocator, value);
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

    var iterator = php_array.elements.iterator();
    while (iterator.next()) |entry| {
        last_key = entry.key_ptr.*;
        last_value = entry.value_ptr.*;
    }

    if (last_key) |key| {
        const result = last_value.?;
        _ = php_array.elements.swapRemove(key);
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

    var iterator = php_array.elements.iterator();
    if (iterator.next()) |entry| {
        first_key = entry.key_ptr.*;
        first_value = entry.value_ptr.*;
    }

    if (first_key) |key| {
        const result = first_value.?;
        _ = php_array.elements.swapRemove(key);
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
    var iterator = php_array.elements.iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        try new_array.push(vm.allocator, value);
    }

    // Replace the original array's contents
    php_array.elements.deinit();
    php_array.elements = new_array.elements;
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

    var iterator = haystack.getAsArray().data.elements.iterator();
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
            // Loose comparison (convert and compare)
            const needle_str = try needle.toString(vm.allocator);
            defer needle_str.deinit(vm.allocator);
            const value_str = try value.toString(vm.allocator);
            defer value_str.deinit(vm.allocator);

            if (std.mem.eql(u8, needle_str.data, value_str.data)) {
                return Value.initBool(true);
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

    var iterator = haystack.getAsArray().data.elements.iterator();
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
            // Loose comparison
            const needle_str = try needle.toString(vm.allocator);
            defer needle_str.deinit(vm.allocator);
            const value_str = try value.toString(vm.allocator);
            defer value_str.deinit(vm.allocator);

            is_match = std.mem.eql(u8, needle_str.data, value_str.data);
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

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn strReplaceFn(vm: *VM, args: []const Value) !Value {
    const search = args[0];
    const replace = args[1];
    const subject = args[2];

    if (search.getTag() != .string or replace.getTag() != .string or subject.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_replace() expects all parameters to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const result_str = try subject.getAsString().data.replace(search.getAsString().data, replace.getAsString().data, vm.allocator);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn strposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];
    const offset = if (args.len > 2) args[2] else Value.initInt(0);

    if (haystack.getTag() != .string or needle.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strpos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (offset.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strpos() expects parameter 3 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Simple implementation - would need to handle offset properly
    const pos = haystack.getAsString().data.indexOf(needle.getAsString().data);

    if (pos >= 0) {
        return Value.initInt(pos);
    } else {
        return Value.initBool(false); // PHP returns false when not found
    }
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

    for (original.data, 0..) |char, i| {
        lower_data[i] = std.ascii.toLower(char);
    }

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

    for (original.data, 0..) |char, i| {
        upper_data[i] = std.ascii.toUpper(char);
    }

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
            const part = try PHPString.init(vm.allocator, str.data[start..actual_pos]);

            const box = try vm.allocator.create(types.gc.Box(*PHPString));
            box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = part,
            };

            const value = Value.fromBox(box, Value.TYPE_STRING);
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
        const part = try PHPString.init(vm.allocator, str.data[start..]);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = part,
        };

        const value = Value.fromBox(box, Value.TYPE_STRING);
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

    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(vm.allocator);

    const glue_str = glue.getAsString().data;
    var first = true;

    var iterator = pieces.getAsArray().data.elements.iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;

        if (!first) {
            try result.appendSlice(vm.allocator, glue_str.data);
        }
        first = false;

        const value_str = try value.toString(vm.allocator);
        defer value_str.deinit(vm.allocator);
        try result.appendSlice(vm.allocator, value_str.data);
    }

    const result_str = try PHPString.init(vm.allocator, result.items);

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

// Math Function Implementations
fn absFn(vm: *VM, args: []const Value) !Value {
    const num = try toFloat(vm, args[0]);
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

    const num_val = switch (number.getTag()) {
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

    const num_val = switch (number.getTag()) {
        .integer => return number, // Already an integer
        .float => number.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "floor() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    return Value.initFloat(@floor(num_val));
}

fn ceilFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];

    const num_val = switch (number.getTag()) {
        .integer => return number, // Already an integer
        .float => number.asFloat(),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "ceil() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    return Value.initFloat(@ceil(num_val));
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

// Date/Time Function Implementations
fn timeFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    const timestamp = std.time.timestamp();
    return Value.initInt(timestamp);
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

    // Simplified date formatting - would need full PHP date format support
    const format_str = format.getAsString().data.data;
    const ts = timestamp.asInt();

    // Basic implementation for common formats
    var result_str: []const u8 = undefined;
    if (std.mem.eql(u8, format_str, "Y-m-d H:i:s")) {
        result_str = try std.fmt.allocPrint(vm.allocator, "2024-01-01 00:00:00", .{});
    } else if (std.mem.eql(u8, format_str, "Y-m-d")) {
        result_str = try std.fmt.allocPrint(vm.allocator, "2024-01-01", .{});
    } else if (std.mem.eql(u8, format_str, "U")) {
        result_str = try std.fmt.allocPrint(vm.allocator, "{d}", .{ts});
    } else {
        // Default format
        result_str = try std.fmt.allocPrint(vm.allocator, "{d}", .{ts});
    }

    const php_str = try PHPString.init(vm.allocator, result_str);
    vm.allocator.free(result_str);

    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = php_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

fn strtotimeFn(vm: *VM, args: []const Value) !Value {
    const time_str = args[0];
    const now = if (args.len > 1) args[1] else Value.initInt(std.time.timestamp());

    if (time_str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtotime() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Simplified implementation - would need full PHP strtotime parsing
    const time_string = time_str.getAsString().data.data;

    if (std.mem.eql(u8, time_string, "now")) {
        return Value.initInt(std.time.timestamp());
    } else if (std.mem.eql(u8, time_string, "+1 day")) {
        return Value.initInt(now.asInt() + 86400);
    } else if (std.mem.eql(u8, time_string, "-1 day")) {
        return Value.initInt(now.asInt() - 86400);
    } else {
        // Try to parse as timestamp
        const parsed = std.fmt.parseInt(i64, time_string, 10) catch {
            return Value.initBool(false);
        };
        return Value.initInt(parsed);
    }
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
    const assoc = if (args.len > 1) args[1].toBool() else false;

    if (json_str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "json_decode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Simplified JSON decoding
    const json_data = json_str.getAsString().data.data;

    // Basic parsing for simple cases
    if (std.mem.eql(u8, json_data, "null")) {
        return Value.initNull();
    } else if (std.mem.eql(u8, json_data, "true")) {
        return Value.initBool(true);
    } else if (std.mem.eql(u8, json_data, "false")) {
        return Value.initBool(false);
    } else if (json_data.len > 0 and json_data[0] == '"' and json_data[json_data.len - 1] == '"') {
        // String value
        const str_content = json_data[1 .. json_data.len - 1];
        return try Value.initString(vm.allocator, str_content);
    } else if (std.fmt.parseInt(i64, json_data, 10)) |int_val| {
        return Value.initInt(int_val);
    } else |_| {
        if (std.fmt.parseFloat(f64, json_data)) |float_val| {
            return Value.initFloat(float_val);
        } else |_| {
            // Invalid JSON
            return Value.initNull();
        }
    }

    _ = assoc; // Would be used for object/array decoding
}

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

// Helper function for JSON encoding
fn encodeValueAsJson(value: Value, allocator: std.mem.Allocator) ![]u8 {
    return switch (value.getTag()) {
        .null => try allocator.dupe(u8, "null"),
        .boolean => try allocator.dupe(u8, if (value.asBool()) "true" else "false"),
        .integer => try std.fmt.allocPrint(allocator, "{d}", .{value.asInt()}),
        .float => try std.fmt.allocPrint(allocator, "{d}", .{value.asFloat()}),
        .string => try std.fmt.allocPrint(allocator, "\"{s}\"", .{value.getAsString().data.data}),
        .array => {
            var result = std.ArrayListUnmanaged(u8){};
            defer result.deinit(allocator);

            try result.append(allocator, '[');
            var first = true;
            var iterator = value.getAsArray().data.elements.iterator();
            while (iterator.next()) |entry| {
                if (!first) try result.appendSlice(allocator, ",");
                first = false;

                const element_json = try encodeValueAsJson(entry.value_ptr.*, allocator);
                defer allocator.free(element_json);
                try result.appendSlice(allocator, element_json);
            }
            try result.append(allocator, ']');

            return try allocator.dupe(u8, result.items);
        },
        .object => try std.fmt.allocPrint(allocator, "{{\"class\":\"{s}\"}}", .{value.getAsObject().data.class.name.data}),
        .struct_instance => try std.fmt.allocPrint(allocator, "{{\"struct\":\"{s}\"}}", .{value.getAsStruct().data.struct_type.name.data}),
        else => try allocator.dupe(u8, "null"),
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
        const hex_str = try std.fmt.bufPrint(&hex_buffer, "{x:0>32}", .{hash});

        const result_str = try PHPString.init(vm.allocator, hex_str);

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
        const hex_str = try std.fmt.bufPrint(&hex_buffer, "{x:0>40}", .{hash});

        const result_str = try PHPString.init(vm.allocator, hex_str);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
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
        const hex_str = try std.fmt.bufPrint(&hex_buffer, "{x:0>64}", .{hash});

        const result_str = try PHPString.init(vm.allocator, hex_str);

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
        const hex_str = try std.fmt.bufPrint(&hex_buffer, "{x:0>128}", .{hash});

        const result_str = try PHPString.init(vm.allocator, hex_str);

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

    var iterator = array.getAsArray().data.elements.iterator();

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
        var iterator = array.getAsArray().data.elements.iterator();

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
        var iterator = array.getAsArray().data.elements.iterator();

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

    var sum: f64 = 0;
    var iterator = array.getAsArray().data.elements.iterator();

    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        sum += switch (value.getTag()) {
            .integer => @floatFromInt(value.asInt()),
            .float => value.asFloat(),
            .string => std.fmt.parseFloat(f64, value.getAsString().data.data) catch 0,
            else => 0,
        };
    }

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
    var iterator = array.getAsArray().data.elements.iterator();

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

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    // Collect elements in reverse order using ArrayListUnmanaged
    var temp = std.ArrayListUnmanaged(struct { key: ArrayKey, value: Value }){};
    defer temp.deinit(vm.allocator);

    var iterator = array.getAsArray().data.elements.iterator();
    while (iterator.next()) |entry| {
        try temp.append(vm.allocator, .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
    }

    var i = temp.items.len;
    var new_index: i64 = 0;
    while (i > 0) {
        i -= 1;
        const item = temp.items[i];
        if (preserve_keys) {
            try result_array.set(vm.allocator, item.key, item.value);
        } else {
            try result_array.set(vm.allocator, ArrayKey{ .integer = new_index }, item.value);
            new_index += 1;
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
    result_array.* = PHPArray.init(vm.allocator);

    var seen = std.StringHashMap(void).init(vm.allocator);
    defer seen.deinit();

    var iterator = array.getAsArray().data.elements.iterator();
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

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var iterator = array.getAsArray().data.elements.iterator();
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

        try result_array.set(vm.allocator, new_key, new_value);
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

    const offset: i64 = if (offset_val.getTag() == .integer) offset_val.asInt() else 0;
    const count = array.getAsArray().data.count();
    const length: i64 = if (length_val.getTag() == .integer) length_val.asInt() else @intCast(count);

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    // Collect elements
    var temp = std.ArrayListUnmanaged(Value){};
    defer temp.deinit(vm.allocator);

    var iterator = array.getAsArray().data.elements.iterator();
    while (iterator.next()) |entry| {
        try temp.append(vm.allocator, entry.value_ptr.*);
    }

    // Handle negative offset
    const start: usize = if (offset < 0)
        @intCast(@max(0, @as(i64, @intCast(temp.items.len)) + offset))
    else
        @intCast(@min(@as(i64, @intCast(temp.items.len)), offset));

    // Handle negative length
    const end: usize = if (length < 0)
        @intCast(@max(0, @as(i64, @intCast(temp.items.len)) + length))
    else
        @intCast(@min(@as(i64, @intCast(temp.items.len)), @as(i64, @intCast(start)) + length));

    var idx: i64 = 0;
    for (temp.items[start..end]) |value| {
        try result_array.set(vm.allocator, ArrayKey{ .integer = idx }, value);
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
    result_array.* = PHPArray.init(vm.allocator);

    const col_key: ArrayKey = switch (column_key.getTag()) {
        .string => blk: {
            const str = try PHPString.init(vm.allocator, column_key.getAsString().data.data);
            break :blk ArrayKey{ .string = str };
        },
        .integer => ArrayKey{ .integer = column_key.asInt() },
        else => ArrayKey{ .integer = 0 },
    };

    var iterator = array.getAsArray().data.elements.iterator();
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

    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

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
    // Simplified sprintf - just return format for now
    return Value.initString(vm.allocator, format);
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
    var result = try vm.allocator.alloc(u8, str.len);
    defer vm.allocator.free(result);
    for (str, 0..) |c, i| result[str.len - 1 - i] = c;
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
    _ = decimals;
    const result = try std.fmt.allocPrint(vm.allocator, "{d}", .{num});
    defer vm.allocator.free(result);
    return Value.initString(vm.allocator, result);
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
            var iter = arr.elements.iterator();
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
            var iter = value.getAsArray().data.elements.iterator();
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
            var iter = value.getAsArray().data.elements.iterator();
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
        .string => std.fmt.parseInt(i64, args[0].getAsString().data.data, 10) catch 0,
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

            var iterator = arr.elements.iterator();
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
            const props_count = obj.shape.property_count;

            try buffer.writer(vm.allocator).print("O:{d}:\"{s}\":{d}:{{", .{ class_name.len, class_name, props_count });

            var iterator = obj.shape.property_map.iterator();
            while (iterator.next()) |entry| {
                const key = entry.key_ptr.*;
                const offset = entry.value_ptr.*;
                const val = obj.property_values.items[offset];

                // Serialize property name (as private property)
                try buffer.writer(vm.allocator).print("s:{d}:\"\\0{s}\\0{s}\";", .{ key.len + 2, class_name, key });

                // Serialize value
                try serializeValue(vm, buffer, val);
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
