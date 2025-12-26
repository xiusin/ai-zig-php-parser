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
    handler: *const fn(*VM, []const Value) anyerror!Value,
    
    pub fn call(self: *const BuiltinFunction, vm: *VM, args: []const Value) !Value {
        // Validate argument count
        if (args.len < self.min_args) {
            const exception = try ExceptionFactory.createArgumentCountError(
                vm.allocator, 
                self.min_args, 
                @intCast(args.len), 
                self.name, 
                "builtin", 
                0
            );
            _ = try vm.throwException(exception);
            return error.ArgumentCountMismatch;
        }
        
        if (self.max_args != 255 and args.len > self.max_args) {
            const exception = try ExceptionFactory.createArgumentCountError(
                vm.allocator, 
                self.max_args, 
                @intCast(args.len), 
                self.name, 
                "builtin", 
                0
            );
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
        };
        
        for (array_functions) |func| {
            try self.registerFunction(func.name, func);
        }
    }
    
    // String Functions
    pub fn registerStringFunctions(self: *StandardLibrary) !void {
        const string_functions = [_]*const BuiltinFunction{
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
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_map() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);
    
    var iterator = array.data.array.data.elements.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        // Call callback function with value
        const callback_args = [_]Value{value};
        const result_value = switch (callback.tag) {
            .builtin_function => blk: {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.data.builtin_function));
                break :blk try function(vm, &callback_args);
            },
            .user_function => try vm.callUserFunction(callback.data.user_function.data, &callback_args),
            .closure => try vm.callClosure(callback.data.closure.data, &callback_args),
            .arrow_function => try vm.callArrowFunction(callback.data.arrow_function.data, &callback_args),
            else => {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_map() expects parameter 1 to be a valid callback", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidArgumentType;
            },
        };
        
        try result_array.set(key, result_value);
    }
    
    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };
    
    return Value{ .tag = .array, .data = .{ .array = box } };
}

fn arrayFilterFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_filter() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);
    
    const callback = if (args.len > 1) args[1] else null;
    
    var iterator = array.data.array.data.elements.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        var should_include = false;
        
        if (callback) |cb| {
            // Call callback function with value
            const callback_args = [_]Value{value};
            const result_value = switch (cb.tag) {
                .builtin_function => blk: {
                    const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(cb.data.builtin_function));
                    break :blk try function(vm, &callback_args);
                },
                .user_function => try vm.callUserFunction(cb.data.user_function.data, &callback_args),
                .closure => try vm.callClosure(cb.data.closure.data, &callback_args),
                .arrow_function => try vm.callArrowFunction(cb.data.arrow_function.data, &callback_args),
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
            try result_array.set(key, value);
        }
    }
    
    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };
    
    return Value{ .tag = .array, .data = .{ .array = box } };
}

fn arrayReduceFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = args[1];
    const initial = if (args.len > 2) args[2] else Value.initNull();
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_reduce() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var accumulator = initial;
    
    var iterator = array.data.array.data.elements.iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        
        // Call callback function with accumulator and current value
        const callback_args = [_]Value{ accumulator, value };
        accumulator = switch (callback.tag) {
            .builtin_function => blk: {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.data.builtin_function));
                break :blk try function(vm, &callback_args);
            },
            .user_function => try vm.callUserFunction(callback.data.user_function.data, &callback_args),
            .closure => try vm.callClosure(callback.data.closure.data, &callback_args),
            .arrow_function => try vm.callArrowFunction(callback.data.arrow_function.data, &callback_args),
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
        if (arg.tag != .array) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_merge() expects all parameters to be arrays", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }
        
        var iterator = arg.data.array.data.elements.iterator();
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            
            // For numeric keys, reindex; for string keys, preserve
            switch (key) {
                .integer => try result_array.push(value),
                .string => try result_array.set(key, value),
            }
        }
    }
    
    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };
    
    return Value{ .tag = .array, .data = .{ .array = box } };
}

fn arrayKeysFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_keys() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);
    
    var iterator = array.data.array.data.elements.iterator();
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
                break :blk Value{ .tag = .string, .data = .{ .string = box } };
            },
        };
        
        try result_array.push(key_value);
    }
    
    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };
    
    return Value{ .tag = .array, .data = .{ .array = box } };
}

fn arrayValuesFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_values() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);
    
    var iterator = array.data.array.data.elements.iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        try result_array.push(value);
    }
    
    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };
    
    return Value{ .tag = .array, .data = .{ .array = box } };
}

fn arrayPushFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_push() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const php_array = array.data.array.data;
    
    // Push all additional arguments
    for (args[1..]) |value| {
        try php_array.push(value);
    }
    
    return Value.initInt(@intCast(php_array.count()));
}

fn arrayPopFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_pop() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const php_array = array.data.array.data;
    
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
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_shift() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const php_array = array.data.array.data;
    
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
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_unshift() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const php_array = array.data.array.data;
    
    // Create new array with unshifted elements
    var new_array = PHPArray.init(vm.allocator);
    
    // Add new elements first
    for (args[1..]) |value| {
        try new_array.push(value);
    }
    
    // Add existing elements
    var iterator = php_array.elements.iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        try new_array.push(value);
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
    
    if (haystack.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "in_array() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var iterator = haystack.data.array.data.elements.iterator();
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        
        if (strict) {
            // Strict comparison (type and value)
            if (needle.tag == value.tag) {
                const is_equal = switch (needle.tag) {
                    .null => true,
                    .boolean => needle.data.boolean == value.data.boolean,
                    .integer => needle.data.integer == value.data.integer,
                    .float => needle.data.float == value.data.float,
                    .string => std.mem.eql(u8, needle.data.string.data.data, value.data.string.data.data),
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
    
    if (haystack.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_search() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var iterator = haystack.data.array.data.elements.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        var is_match = false;
        
        if (strict) {
            // Strict comparison
            if (needle.tag == value.tag) {
                is_match = switch (needle.tag) {
                    .null => true,
                    .boolean => needle.data.boolean == value.data.boolean,
                    .integer => needle.data.integer == value.data.integer,
                    .float => needle.data.float == value.data.float,
                    .string => std.mem.eql(u8, needle.data.string.data.data, value.data.string.data.data),
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
                    break :blk Value{ .tag = .string, .data = .{ .string = box } };
                },
            };
        }
    }
    
    return Value.initBool(false); // PHP returns false when not found
}

// String Function Implementations
fn strlenFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strlen() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    return Value.initInt(@intCast(str.data.string.data.length));
}

fn substrFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const start = args[1];
    const length = if (args.len > 2) args[2] else Value.initNull();
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "substr() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    if (start.tag != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "substr() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const start_int = start.data.integer;
    const length_int = if (length.tag == .integer) length.data.integer else null;
    
    const result_str = try str.data.string.data.substring(start_int, length_int, vm.allocator);
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn strReplaceFn(vm: *VM, args: []const Value) !Value {
    const search = args[0];
    const replace = args[1];
    const subject = args[2];
    
    if (search.tag != .string or replace.tag != .string or subject.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_replace() expects all parameters to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const result_str = try subject.data.string.data.replace(
        search.data.string.data,
        replace.data.string.data,
        vm.allocator
    );
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn strposFn(vm: *VM, args: []const Value) !Value {
    const haystack = args[0];
    const needle = args[1];
    const offset = if (args.len > 2) args[2] else Value.initInt(0);
    
    if (haystack.tag != .string or needle.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strpos() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    if (offset.tag != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strpos() expects parameter 3 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    // Simple implementation - would need to handle offset properly
    const pos = haystack.data.string.data.indexOf(needle.data.string.data);
    
    if (pos >= 0) {
        return Value.initInt(pos);
    } else {
        return Value.initBool(false); // PHP returns false when not found
    }
}

fn strtolowerFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtolower() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const original = str.data.string.data;
    const lower_data = try vm.allocator.alloc(u8, original.length);
    
    for (original.data, 0..) |char, i| {
        lower_data[i] = std.ascii.toLower(char);
    }
    
    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = lower_data,
        .length = original.length,
        .encoding = original.encoding,
    };
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn strtoupperFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtoupper() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const original = str.data.string.data;
    const upper_data = try vm.allocator.alloc(u8, original.length);
    
    for (original.data, 0..) |char, i| {
        upper_data[i] = std.ascii.toUpper(char);
    }
    
    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = upper_data,
        .length = original.length,
        .encoding = original.encoding,
    };
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn trimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "trim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const original = str.data.string.data;
    const trim_chars = if (chars.tag == .string) chars.data.string.data.data else " \t\n\r\x00\x0B";
    
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
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn ltrimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ltrim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const original = str.data.string.data;
    const trim_chars = if (chars.tag == .string) chars.data.string.data.data else " \t\n\r\x00\x0B";
    
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
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn rtrimFn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const chars = if (args.len > 1) args[1] else Value.initNull();
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "rtrim() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const original = str.data.string.data;
    const trim_chars = if (chars.tag == .string) chars.data.string.data.data else " \t\n\r\x00\x0B";
    
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
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn explodeFn(vm: *VM, args: []const Value) !Value {
    const delimiter = args[0];
    const string = args[1];
    const limit = if (args.len > 2) args[2] else Value.initNull();
    
    if (delimiter.tag != .string or string.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "explode() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);
    
    const delim = delimiter.data.string.data;
    const str = string.data.string.data;
    
    if (delim.length == 0) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "explode(): Empty delimiter", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var start: usize = 0;
    var count: i64 = 0;
    const max_splits = if (limit.tag == .integer) limit.data.integer else std.math.maxInt(i64);
    
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
            
            try result_array.push(Value{ .tag = .string, .data = .{ .string = box } });
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
        
        try result_array.push(Value{ .tag = .string, .data = .{ .string = box } });
    }
    
    const array_box = try vm.allocator.create(types.gc.Box(*PHPArray));
    array_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };
    
    return Value{ .tag = .array, .data = .{ .array = array_box } };
}

fn implodeFn(vm: *VM, args: []const Value) !Value {
    const glue = args[0];
    const pieces = args[1];
    
    if (glue.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "implode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    if (pieces.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "implode() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(vm.allocator);
    
    const glue_str = glue.data.string.data;
    var first = true;
    
    var iterator = pieces.data.array.data.elements.iterator();
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
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn strRepeatFn(vm: *VM, args: []const Value) !Value {
    const input = args[0];
    const multiplier = args[1];
    
    if (input.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    if (multiplier.tag != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const times = multiplier.data.integer;
    if (times < 0) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "str_repeat(): Second argument has to be greater than or equal to 0", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    if (times == 0) {
        return try Value.initString(vm.allocator, "");
    }
    
    const input_str = input.data.string.data;
    const total_length = input_str.length * @as(usize, @intCast(times));
    const result_data = try vm.allocator.alloc(u8, total_length);
    
    for (0..@intCast(times)) |i| {
        const start = i * input_str.length;
        @memcpy(result_data[start..start + input_str.length], input_str.data);
    }
    
    const result_str = try vm.allocator.create(PHPString);
    result_str.* = .{
        .data = result_data,
        .length = total_length,
        .encoding = input_str.encoding,
    };
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

// Math Function Implementations
fn absFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    
    return switch (number.tag) {
        .integer => Value.initInt(@intCast(@abs(number.data.integer))),
        .float => Value.initFloat(@abs(number.data.float)),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "abs() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
}

fn roundFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    const precision = if (args.len > 1) args[1] else Value.initInt(0);
    
    if (precision.tag != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "round() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const num_val = switch (number.tag) {
        .integer => @as(f64, @floatFromInt(number.data.integer)),
        .float => number.data.float,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "round() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
    
    const prec = precision.data.integer;
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
    
    const num_val = switch (number.tag) {
        .integer => @as(f64, @floatFromInt(number.data.integer)),
        .float => number.data.float,
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
    
    const base_val = switch (base.tag) {
        .integer => @as(f64, @floatFromInt(base.data.integer)),
        .float => base.data.float,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "pow() expects parameter 1 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
    
    const exp_val = switch (exponent.tag) {
        .integer => @as(f64, @floatFromInt(exponent.data.integer)),
        .float => exponent.data.float,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "pow() expects parameter 2 to be numeric", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
    
    const result = std.math.pow(f64, base_val, exp_val);
    
    // Return integer if both inputs were integers and result is a whole number
    if (base.tag == .integer and exponent.tag == .integer and result == @floor(result)) {
        return Value.initInt(@intFromFloat(result));
    } else {
        return Value.initFloat(result);
    }
}

fn floorFn(vm: *VM, args: []const Value) !Value {
    const number = args[0];
    
    const num_val = switch (number.tag) {
        .integer => return number, // Already an integer
        .float => number.data.float,
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
    
    const num_val = switch (number.tag) {
        .integer => return number, // Already an integer
        .float => number.data.float,
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
        
        if (min.tag != .integer or max.tag != .integer) {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "rand() expects parameters to be integers", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        }
        
        const min_val = min.data.integer;
        const max_val = max.data.integer;
        
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
    if (a.tag == .integer and b.tag == .integer) {
        if (a.data.integer < b.data.integer) return -1;
        if (a.data.integer > b.data.integer) return 1;
        return 0;
    } else if (a.tag == .float and b.tag == .float) {
        if (a.data.float < b.data.float) return -1;
        if (a.data.float > b.data.float) return 1;
        return 0;
    } else {
        // Mixed types - convert to float for comparison
        const a_float = switch (a.tag) {
            .integer => @as(f64, @floatFromInt(a.data.integer)),
            .float => a.data.float,
            else => 0.0,
        };
        const b_float = switch (b.tag) {
            .integer => @as(f64, @floatFromInt(b.data.integer)),
            .float => b.data.float,
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
    
    if (filename.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_get_contents() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const file_path = filename.data.string.data.data;
    
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
    };
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn filePutContentsFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    const data = args[1];
    
    if (filename.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_put_contents() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const file_path = filename.data.string.data.data;
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
    
    if (filename.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const file_path = filename.data.string.data.data;
    
    std.fs.cwd().access(file_path, .{}) catch {
        return Value.initBool(false);
    };
    
    return Value.initBool(true);
}

fn isFileFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    
    if (filename.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_file() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const file_path = filename.data.string.data.data;
    
    const stat = std.fs.cwd().statFile(file_path) catch {
        return Value.initBool(false);
    };
    
    return Value.initBool(stat.kind == .file);
}

fn isDirFn(vm: *VM, args: []const Value) !Value {
    const dirname = args[0];
    
    if (dirname.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_dir() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const dir_path = dirname.data.string.data.data;
    
    const stat = std.fs.cwd().statFile(dir_path) catch {
        return Value.initBool(false);
    };
    
    return Value.initBool(stat.kind == .directory);
}

fn filesizeFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    
    if (filename.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "filesize() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const file_path = filename.data.string.data.data;
    
    const stat = std.fs.cwd().statFile(file_path) catch {
        return Value.initBool(false);
    };
    
    return Value.initInt(@intCast(stat.size));
}

fn basenameFn(vm: *VM, args: []const Value) !Value {
    const path = args[0];
    const suffix = if (args.len > 1) args[1] else Value.initNull();
    
    if (path.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "basename() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const path_str = path.data.string.data.data;
    const basename = std.fs.path.basename(path_str);
    
    var result_name = basename;
    
    // Remove suffix if provided
    if (suffix.tag == .string) {
        const suffix_str = suffix.data.string.data.data;
        if (std.mem.endsWith(u8, basename, suffix_str)) {
            result_name = basename[0..basename.len - suffix_str.len];
        }
    }
    
    const result_str = try PHPString.init(vm.allocator, result_name);
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn dirnameFn(vm: *VM, args: []const Value) !Value {
    const path = args[0];
    const levels = if (args.len > 1) args[1] else Value.initInt(1);
    
    if (path.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "dirname() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    if (levels.tag != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "dirname() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const path_str = path.data.string.data.data;
    var dirname = std.fs.path.dirname(path_str) orelse ".";
    
    // Apply levels
    var remaining_levels = levels.data.integer - 1;
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
    
    return Value{ .tag = .string, .data = .{ .string = box } };
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
    
    if (format.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "date() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    if (timestamp.tag != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "date() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    // Simplified date formatting - would need full PHP date format support
    const format_str = format.data.string.data.data;
    const ts = timestamp.data.integer;
    
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
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn strtotimeFn(vm: *VM, args: []const Value) !Value {
    const time_str = args[0];
    const now = if (args.len > 1) args[1] else Value.initInt(std.time.timestamp());
    
    if (time_str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "strtotime() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    // Simplified implementation - would need full PHP strtotime parsing
    const time_string = time_str.data.string.data.data;
    
    if (std.mem.eql(u8, time_string, "now")) {
        return Value.initInt(std.time.timestamp());
    } else if (std.mem.eql(u8, time_string, "+1 day")) {
        return Value.initInt(now.data.integer + 86400);
    } else if (std.mem.eql(u8, time_string, "-1 day")) {
        return Value.initInt(now.data.integer - 86400);
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
    
    return Value{ .tag = .string, .data = .{ .string = box } };
}

fn jsonDecodeFn(vm: *VM, args: []const Value) !Value {
    const json_str = args[0];
    const assoc = if (args.len > 1) args[1].toBool() else false;
    
    if (json_str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "json_decode() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    // Simplified JSON decoding
    const json_data = json_str.data.string.data.data;
    
    // Basic parsing for simple cases
    if (std.mem.eql(u8, json_data, "null")) {
        return Value.initNull();
    } else if (std.mem.eql(u8, json_data, "true")) {
        return Value.initBool(true);
    } else if (std.mem.eql(u8, json_data, "false")) {
        return Value.initBool(false);
    } else if (json_data.len > 0 and json_data[0] == '"' and json_data[json_data.len - 1] == '"') {
        // String value
        const str_content = json_data[1..json_data.len - 1];
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
    return switch (value.tag) {
        .null => try allocator.dupe(u8, "null"),
        .boolean => try allocator.dupe(u8, if (value.data.boolean) "true" else "false"),
        .integer => try std.fmt.allocPrint(allocator, "{d}", .{value.data.integer}),
        .float => try std.fmt.allocPrint(allocator, "{d}", .{value.data.float}),
        .string => try std.fmt.allocPrint(allocator, "\"{s}\"", .{value.data.string.data.data}),
        .array => {
            var result = std.ArrayListUnmanaged(u8){};
            defer result.deinit(allocator);
            
            try result.append(allocator, '[');
            var first = true;
            var iterator = value.data.array.data.elements.iterator();
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
        .object => try std.fmt.allocPrint(allocator, "{{\"class\":\"{s}\"}}", .{value.data.object.data.class.name.data}),
        else => try allocator.dupe(u8, "null"),
    };
}

// Hash Function Implementations
fn md5Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "md5() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const input = str.data.string.data.data;
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
        
        return Value{ .tag = .string, .data = .{ .string = box } };
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
        
        return Value{ .tag = .string, .data = .{ .string = box } };
    }
}

fn sha1Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;
    
    if (str.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sha1() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const input = str.data.string.data.data;
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
        
        return Value{ .tag = .string, .data = .{ .string = box } };
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
        
        return Value{ .tag = .string, .data = .{ .string = box } };
    }
}

fn hashFn(vm: *VM, args: []const Value) !Value {
    const algo = args[0];
    const data = args[1];
    const raw_output = if (args.len > 2) args[2].toBool() else false;
    
    if (algo.tag != .string or data.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "hash() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const algorithm = algo.data.string.data.data;
    const input = data.data.string.data.data;
    
    if (std.mem.eql(u8, algorithm, "md5")) {
        return md5Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else if (std.mem.eql(u8, algorithm, "sha1")) {
        return sha1Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else if (std.mem.eql(u8, algorithm, "sha256")) {
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
            
            return Value{ .tag = .string, .data = .{ .string = box } };
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
            
            return Value{ .tag = .string, .data = .{ .string = box } };
        }
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
    
    const algorithms = [_][]const u8{ "md5", "sha1", "sha256" };
    
    for (algorithms) |algo| {
        const algo_str = try Value.initString(vm.allocator, algo);
        try result_array.push(algo_str);
    }
    
    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };
    
    return Value{ .tag = .array, .data = .{ .array = box } };
}

// PHP 8.5 Array Functions
fn arrayFirstFn(vm: *VM, args: []const Value) !Value {
    const array = args[0];
    const callback = if (args.len > 1) args[1] else null;
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_first() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var iterator = array.data.array.data.elements.iterator();
    
    if (callback) |cb| {
        // Find first element that matches callback
        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;
            
            const callback_args = [_]Value{value};
            const result_value = switch (cb.tag) {
                .builtin_function => blk: {
                    const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(cb.data.builtin_function));
                    break :blk try function(vm, &callback_args);
                },
                .user_function => try vm.callUserFunction(cb.data.user_function.data, &callback_args),
                .closure => try vm.callClosure(cb.data.closure.data, &callback_args),
                .arrow_function => try vm.callArrowFunction(cb.data.arrow_function.data, &callback_args),
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
    
    if (array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "array_last() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    if (callback) |cb| {
        // Find last element that matches callback
        var last_match: ?Value = null;
        var iterator = array.data.array.data.elements.iterator();
        
        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;
            
            const callback_args = [_]Value{value};
            const result_value = switch (cb.tag) {
                .builtin_function => blk: {
                    const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(cb.data.builtin_function));
                    break :blk try function(vm, &callback_args);
                },
                .user_function => try vm.callUserFunction(cb.data.user_function.data, &callback_args),
                .closure => try vm.callClosure(cb.data.closure.data, &callback_args),
                .arrow_function => try vm.callArrowFunction(cb.data.arrow_function.data, &callback_args),
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
        var iterator = array.data.array.data.elements.iterator();
        
        while (iterator.next()) |entry| {
            last_value = entry.value_ptr.*;
        }
        
        return last_value orelse Value.initNull();
    }
}