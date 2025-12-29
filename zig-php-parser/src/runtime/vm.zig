const std = @import("std");
const ast = @import("../compiler/ast.zig");
const Token = @import("../compiler/token.zig").Token;
const Environment = @import("environment.zig").Environment;
const types = @import("types.zig");
const Value = types.Value;
const PHPContext = @import("../compiler/parser.zig").PHPContext;
const exceptions = @import("exceptions.zig");
const PHPException = exceptions.PHPException;
const ErrorHandler = exceptions.ErrorHandler;
const ErrorType = exceptions.ErrorType;
const TryCatchContext = exceptions.TryCatchContext;
const ExceptionFactory = exceptions.ExceptionFactory;
const stdlib = @import("stdlib.zig");
const StandardLibrary = stdlib.StandardLibrary;
const reflection = @import("reflection.zig");
const builtin_classes = @import("builtin_classes.zig");
const database = @import("database.zig");
const ReflectionSystem = reflection.ReflectionSystem;
const string_utils = @import("string_utils.zig");
const builtin_methods = @import("builtin_methods.zig");
const builtin_concurrency = @import("builtin_concurrency.zig");
const builtin_http = @import("builtin_http.zig");

const CapturedVar = struct { name: []const u8, value: Value };

pub const CallFrame = struct {
    function_name: []const u8,
    file: []const u8,
    line: u32,
    locals: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator, function_name: []const u8, file: []const u8, line: u32) CallFrame {
        return CallFrame{
            .function_name = function_name,
            .file = file,
            .line = line,
            .locals = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *CallFrame, allocator: std.mem.Allocator) void {
        var iterator = self.locals.iterator();
        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;
            switch (value.tag) {
                .string => value.data.string.release(allocator),
                .array => value.data.array.release(allocator),
                .object => value.data.object.release(allocator),
                .struct_instance => value.data.struct_instance.release(allocator),
                .resource => value.data.resource.release(allocator),
                .user_function => value.data.user_function.release(allocator),
                .closure => value.data.closure.release(allocator),
                .arrow_function => value.data.arrow_function.release(allocator),
                else => {},
            }
        }
        self.locals.deinit();
    }
};

pub const ExecutionStats = struct {
    function_calls: u64 = 0,
    memory_allocations: u64 = 0,
    gc_collections: u32 = 0,
    execution_time_ns: u64 = 0,
    peak_memory_usage: usize = 0,

    pub fn reset(self: *ExecutionStats) void {
        self.* = ExecutionStats{};
    }
};

pub const OptimizationFlags = packed struct {
    enable_string_interning: bool = true,
    enable_function_inlining: bool = false,
    enable_constant_folding: bool = true,
    enable_dead_code_elimination: bool = false,
    enable_jit_compilation: bool = false,
    enable_opcode_caching: bool = true,
    enable_memory_pooling: bool = true,
    enable_fast_property_access: bool = true,
};

pub const ErrorContext = struct {
    recent_errors: std.ArrayList(ErrorInfo),
    max_errors: usize = 100,

    pub const ErrorInfo = struct {
        timestamp: i64,
        error_type: ErrorType,
        message: []const u8,
        file: []const u8,
        line: u32,
        stack_trace: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) ErrorContext {
        _ = allocator; // Unused in this version
        return ErrorContext{
            .recent_errors = std.ArrayList(ErrorInfo){},
        };
    }

    pub fn deinit(self: *ErrorContext, allocator: std.mem.Allocator) void {
        for (self.recent_errors.items) |error_info| {
            allocator.free(error_info.message);
            allocator.free(error_info.file);
            allocator.free(error_info.stack_trace);
        }
        self.recent_errors.deinit(allocator);
    }

    pub fn addError(self: *ErrorContext, allocator: std.mem.Allocator, error_type: ErrorType, message: []const u8, file: []const u8, line: u32, stack_trace: []const u8) !void {
        // Remove oldest error if at capacity
        if (self.recent_errors.items.len >= self.max_errors) {
            const oldest = self.recent_errors.orderedRemove(0);
            allocator.free(oldest.message);
            allocator.free(oldest.file);
            allocator.free(oldest.stack_trace);
        }

        const error_info = ErrorInfo{
            .timestamp = std.time.timestamp(),
            .error_type = error_type,
            .message = try allocator.dupe(u8, message),
            .file = try allocator.dupe(u8, file),
            .line = line,
            .stack_trace = try allocator.dupe(u8, stack_trace),
        };

        try self.recent_errors.append(allocator, error_info);
    }
};

fn callUserFuncFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "call_user_func", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const callback = args[0];
    const func_args = if (args.len > 1) args[1..] else &[_]Value{};

    return switch (callback.tag) {
        .builtin_function => {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.data.builtin_function));
            return function(vm, func_args);
        },
        .user_function => {
            return vm.callUserFunction(callback.data.user_function.data, func_args);
        },
        .closure => {
            return vm.callClosure(callback.data.closure.data, func_args);
        },
        .arrow_function => {
            return vm.callArrowFunction(callback.data.arrow_function.data, func_args);
        },
        .string => {
            // Function name as string
            const func_name = callback.data.string.data.data;
            return vm.callUserFunc(func_name, func_args);
        },
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "call_user_func() expects parameter 1 to be a valid callback", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
}

fn callUserFuncArrayFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "call_user_func_array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const callback = args[0];
    const params_array = args[1];

    if (params_array.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "call_user_func_array() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Convert array to argument list
    const php_array = params_array.data.array.data;
    var func_args = try vm.allocator.alloc(Value, php_array.count());
    defer vm.allocator.free(func_args);

    var i: usize = 0;
    var iterator = php_array.elements.iterator();
    while (iterator.next()) |entry| {
        func_args[i] = entry.value_ptr.*;
        i += 1;
    }

    return switch (callback.tag) {
        .builtin_function => {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.data.builtin_function));
            return function(vm, func_args);
        },
        .user_function => {
            return vm.callUserFunction(callback.data.user_function.data, func_args);
        },
        .closure => {
            return vm.callClosure(callback.data.closure.data, func_args);
        },
        .arrow_function => {
            return vm.callArrowFunction(callback.data.arrow_function.data, func_args);
        },
        .string => {
            // Function name as string
            const func_name = callback.data.string.data.data;
            return vm.callUserFunc(func_name, func_args);
        },
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "call_user_func_array() expects parameter 1 to be a valid callback", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
}

fn pdoRollbackFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initBool(false); // Not implemented yet
}

fn pdoCommitFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initBool(false); // Not implemented yet
}

fn pdoBeginTransactionFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initBool(false); // Not implemented yet
}

fn pdoPrepareFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initNull(); // Not implemented yet
}

fn pdoQueryFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initNull(); // Not implemented yet
}

fn pdoExecFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_exec() expects exactly 2 parameters", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_value = args[0];
    const sql_value = args[1];

    if (pdo_value.tag != .object or sql_value.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_exec() expects PDO object and string", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    if (!std.mem.eql(u8, pdo_value.data.object.data.class.name.data, "PDO")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_exec() expects PDO object as first parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const sql = sql_value.data.string.data.data;

    // Get the stored PDO connection
    const connection_prop = pdo_value.data.object.data.getProperty("_pdo_connection") catch {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "PDO connection not initialized", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    };

    if (connection_prop.tag != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "Invalid PDO connection", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.data.integer))));
    const result = try pdo_ptr.exec(sql);
    return Value.initInt(result);
}

// Existing function implementations...

fn isCallableFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "is_callable", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const value = args[0];
    const is_callable = switch (value.tag) {
        .builtin_function, .user_function, .closure, .arrow_function => true,
        .string => {
            // Check if string refers to a valid function name
            const func_name = value.data.string.data.data;
            return Value.initBool(vm.global.get(func_name) != null);
        },
        else => false,
    };

    return Value.initBool(is_callable);
}

// Reflection functions
fn classExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "class_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const class_name_val = args[0];
    if (class_name_val.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "class_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const class_name = class_name_val.data.string.data.data;
    const exists = vm.getClass(class_name) != null;
    return Value.initBool(exists);
}

fn methodExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "method_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const object_or_class = args[0];
    const method_name_val = args[1];

    if (method_name_val.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "method_exists() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const method_name = method_name_val.data.string.data.data;

    const exists = switch (object_or_class.tag) {
        .object => {
            const object = object_or_class.data.object.data;
            return Value.initBool(object.hasMethod(method_name));
        },
        .string => {
            const class_name = object_or_class.data.string.data.data;
            const class = vm.getClass(class_name) orelse return Value.initBool(false);
            return Value.initBool(class.hasMethod(method_name));
        },
        else => false,
    };

    return Value.initBool(exists);
}

fn propertyExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "property_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const object_or_class = args[0];
    const property_name_val = args[1];

    if (property_name_val.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "property_exists() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const property_name = property_name_val.data.string.data.data;

    const exists = switch (object_or_class.tag) {
        .object => {
            const object = object_or_class.data.object.data;
            return Value.initBool(object.properties.contains(property_name) or object.class.hasProperty(property_name));
        },
        .string => {
            const class_name = object_or_class.data.string.data.data;
            const class = vm.getClass(class_name) orelse return Value.initBool(false);
            return Value.initBool(class.hasProperty(property_name));
        },
        else => false,
    };

    return Value.initBool(exists);
}

fn getClassFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_class", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const object_val = args[0];
    if (object_val.tag != .object) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_class() expects parameter 1 to be object", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const object = object_val.data.object.data;
    return Value.initStringWithManager(&vm.memory_manager, object.class.name.data);
}

fn getClassMethodsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_class_methods", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const class_name_val = args[0];
    const class_name = switch (class_name_val.tag) {
        .string => class_name_val.data.string.data.data,
        .object => class_name_val.data.object.data.class.name.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_class_methods() expects parameter 1 to be string or object", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const class = vm.getClass(class_name) orelse {
        return Value.initNull();
    };

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.data.array.data;

    var iterator = class.methods.iterator();
    while (iterator.next()) |entry| {
        const method_name_value = try Value.initStringWithManager(&vm.memory_manager, entry.key_ptr.*);
        try php_array.push(vm.allocator, method_name_value);
        vm.releaseValue(method_name_value);
    }

    return php_array_value;
}

fn getClassVarsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_class_vars", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const class_name_val = args[0];
    const class_name = switch (class_name_val.tag) {
        .string => class_name_val.data.string.data.data,
        .object => class_name_val.data.object.data.class.name.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_class_vars() expects parameter 1 to be string or object", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const class = vm.getClass(class_name) orelse {
        return Value.initNull();
    };

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.data.array.data;

    var iterator = class.properties.iterator();
    while (iterator.next()) |entry| {
        const property_name = entry.key_ptr.*;
        const property = entry.value_ptr.*;

        // Only include public properties
        if (property.modifiers.visibility == .public) {
            const key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, property_name) };
            const value = property.default_value orelse Value.initNull();
            try php_array.set(vm.allocator, key, value);
        }
    }

    return php_array_value;
}

fn getObjectVarsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_object_vars", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const object_val = args[0];
    if (object_val.tag != .object) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_object_vars() expects parameter 1 to be object", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const object = object_val.data.object.data;
    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.data.array.data;

    var iterator = object.properties.iterator();
    while (iterator.next()) |entry| {
        const property_name = entry.key_ptr.*;
        const property_value = entry.value_ptr.*;

        // Check if property is accessible (public or from same class context)
        // For now, include all properties (simplified)
        const key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, property_name) };
        try php_array.set(vm.allocator, key, property_value);
    }

    return php_array_value;
}

fn isAFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "is_a", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const object_val = args[0];
    const class_name_val = args[1];

    if (class_name_val.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_a() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const class_name = class_name_val.data.string.data.data;

    const is_instance = switch (object_val.tag) {
        .object => {
            const object = object_val.data.object.data;
            const target_class = vm.getClass(class_name) orelse return Value.initBool(false);
            return Value.initBool(object.isInstanceOf(target_class));
        },
        .string => {
            // Allow checking class names as strings
            const object_class_name = object_val.data.string.data.data;
            const object_class = vm.getClass(object_class_name) orelse return Value.initBool(false);
            const target_class = vm.getClass(class_name) orelse return Value.initBool(false);
            return Value.initBool(object_class.isInstanceOf(target_class));
        },
        else => false,
    };

    return Value.initBool(is_instance);
}

fn isSubclassOfFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "is_subclass_of", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const child_val = args[0];
    const parent_val = args[1];

    if (parent_val.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_subclass_of() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const parent_class_name = parent_val.data.string.data.data;
    const parent_class = vm.getClass(parent_class_name) orelse return Value.initBool(false);

    const is_subclass = switch (child_val.tag) {
        .object => {
            const object = child_val.data.object.data;
            // Check if object's class is a subclass (not the same class)
            return Value.initBool(object.class != parent_class and object.class.isInstanceOf(parent_class));
        },
        .string => {
            const child_class_name = child_val.data.string.data.data;
            const child_class = vm.getClass(child_class_name) orelse return Value.initBool(false);
            // Check if child class is a subclass (not the same class)
            return Value.initBool(child_class != parent_class and child_class.isInstanceOf(parent_class));
        },
        else => false,
    };

    return Value.initBool(is_subclass);
}

fn countFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "count", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }
    const arg = args[0];
    if (arg.tag != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "count() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    return Value.initInt(@intCast(arg.data.array.data.count()));
}

// Variable handling functions
fn unsetFn(vm: *VM, args: []const Value) !Value {
    // unset() can take multiple arguments
    if (args.len == 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, 0, "unset", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    // In PHP, unset() is a language construct, not a function
    // For our implementation, we'll simulate the behavior by returning null
    // The actual unsetting would need to be handled at the parser/compiler level
    // This is a simplified implementation for demonstration

    // In a real implementation, unset would need variable references
    // For now, we'll just return null to indicate successful "unset"
    return Value.initNull();
}

fn emptyFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "empty", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const arg = args[0];

    // PHP empty() returns true for:
    // - null
    // - false
    // - 0 (integer)
    // - 0.0 (float)
    // - "" (empty string)
    // - "0" (string containing only "0")
    // - empty array
    // - uninitialized variables (we treat as null)

    const is_empty = switch (arg.tag) {
        .null => true,
        .boolean => !arg.data.boolean,
        .integer => arg.data.integer == 0,
        .float => arg.data.float == 0.0,
        .string => blk: {
            const str_data = arg.data.string.data.data;
            break :blk str_data.len == 0 or std.mem.eql(u8, str_data, "0");
        },
        .array => arg.data.array.data.count() == 0,
        .object, .struct_instance, .resource => false, // Objects are never empty
        .number_wrapper => switch (arg.data.number_wrapper.value) {
            .integer => |v| v == 0,
            .float => |v| v == 0.0,
        },
        .builtin_function, .user_function, .closure, .arrow_function => false, // Functions are never empty
    };

    return Value.initBool(is_empty);
}

fn isNullFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "is_null", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const arg = args[0];
    return Value.initBool(arg.tag == .null);
}

// Reflection functions
fn getDeclaredClassesFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 0, @intCast(args.len), "get_declared_classes", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.data.array.data;

    var iterator = vm.classes.iterator();
    while (iterator.next()) |entry| {
        const class_name_value = try Value.initStringWithManager(&vm.memory_manager, entry.key_ptr.*);
        try php_array.push(vm.allocator, class_name_value);
        vm.releaseValue(class_name_value);
    }

    return php_array_value;
}

fn getDeclaredInterfacesFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 0, @intCast(args.len), "get_declared_interfaces", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    // Return empty array - interface tracking not yet implemented
    return try Value.initArrayWithManager(&vm.memory_manager);
}

fn getDeclaredTraitsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 0, @intCast(args.len), "get_declared_traits", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    // Return empty array - trait tracking not yet implemented
    return try Value.initArrayWithManager(&vm.memory_manager);
}

fn getParentClassFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_parent_class", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const arg = args[0];
    const class = switch (arg.tag) {
        .object => arg.data.object.data.class,
        .string => vm.getClass(arg.data.string.data.data) orelse return Value.initBool(false),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_parent_class() expects parameter 1 to be object or string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    if (class.parent) |parent| {
        return Value.initStringWithManager(&vm.memory_manager, parent.name.data);
    }

    return Value.initBool(false);
}

fn interfaceExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "interface_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const interface_name_val = args[0];
    if (interface_name_val.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "interface_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Interface tracking not yet implemented
    return Value.initBool(false);
}

fn traitExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "trait_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const trait_name_val = args[0];
    if (trait_name_val.tag != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "trait_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const trait_name = trait_name_val.data.string.data.data;
    if (vm.getClass(trait_name)) |_| {
        // Note: Current implementation doesn't distinguish traits from classes
        // Would need is_trait field in ClassModifiers
        return Value.initBool(false);
    }

    return Value.initBool(false);
}

fn getClassConstantsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_class_constants", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const class_name_val = args[0];
    const class_name = switch (class_name_val.tag) {
        .string => class_name_val.data.string.data.data,
        .object => class_name_val.data.object.data.class.name.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_class_constants() expects parameter 1 to be string or object", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const class = vm.getClass(class_name) orelse {
        return Value.initNull();
    };

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.data.array.data;

    var iterator = class.constants.iterator();
    while (iterator.next()) |entry| {
        const key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, entry.key_ptr.*) };
        try php_array.set(vm.allocator, key, entry.value_ptr.*);
    }

    return php_array_value;
}

pub const VM = struct {
    allocator: std.mem.Allocator,
    global: *Environment,
    context: *PHPContext,
    classes: std.StringHashMap(*types.PHPClass),
    interfaces: std.StringHashMap(*types.PHPInterface),
    traits: std.StringHashMap(*types.PHPTrait),
    structs: std.StringHashMap(*types.PHPStruct),
    error_handler: ErrorHandler,
    current_file: []const u8,
    current_line: u32,
    try_catch_stack: std.ArrayList(TryCatchContext),
    stdlib: StandardLibrary,
    reflection_system: ReflectionSystem,
    memory_manager: types.gc.MemoryManager,

    // Performance optimization fields
    call_stack: std.ArrayList(CallFrame),
    execution_stats: ExecutionStats,
    optimization_flags: OptimizationFlags,

    // Enhanced error reporting
    error_context: ErrorContext,

    // Memory optimization
    string_intern_pool: std.StringHashMap(*types.gc.Box(*types.PHPString)),
    current_class: ?*types.PHPClass = null,
    return_value: ?Value = null,
    break_level: u32 = 0,
    continue_level: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) !*VM {
        var vm = try allocator.create(VM);
        vm.* = .{
            .allocator = allocator,
            .global = try allocator.create(Environment),
            .context = undefined,
            .classes = std.StringHashMap(*types.PHPClass).init(allocator),
            .interfaces = std.StringHashMap(*types.PHPInterface).init(allocator),
            .traits = std.StringHashMap(*types.PHPTrait).init(allocator),
            .structs = std.StringHashMap(*types.PHPStruct).init(allocator),
            .error_handler = ErrorHandler.init(allocator),
            .current_file = "unknown",
            .current_line = 0,
            .try_catch_stack = std.ArrayList(TryCatchContext){},
            .stdlib = try StandardLibrary.init(allocator),
            .reflection_system = undefined, // Will be initialized after VM creation
            .memory_manager = try types.gc.MemoryManager.init(allocator),
            .call_stack = std.ArrayList(CallFrame){},
            .execution_stats = ExecutionStats{},
            .optimization_flags = OptimizationFlags{},
            .error_context = ErrorContext.init(allocator),
            .string_intern_pool = std.StringHashMap(*types.gc.Box(*types.PHPString)).init(allocator),
            .current_class = null,
            .return_value = null,
            .break_level = 0,
            .continue_level = 0,
        };

        vm.global.* = Environment.init(allocator);
        vm.reflection_system = ReflectionSystem.init(allocator, vm);

        // Initialize builtin classes
        var builtin_class_manager = try builtin_classes.BuiltinClassManager.init(allocator);
        defer builtin_class_manager.deinit();
        var class_iter = builtin_class_manager.classes.iterator();
        while (class_iter.next()) |entry| {
            try vm.classes.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Register built-in functions with optimized registration
        try vm.registerBuiltinFunctions();

        // Register all standard library functions
        try vm.registerStandardLibraryFunctions();

        // Register concurrency classes (Mutex, Atomic, RWLock, SharedData)
        try builtin_concurrency.registerConcurrencyClasses(vm);

        // Register HTTP classes (HttpServer, HttpClient, Router)
        try builtin_http.registerHttpClasses(vm);

        // Initialize performance monitoring
        vm.execution_stats.reset();

        return vm;
    }

    pub fn deinit(self: *VM) void {
        // Performance statistics logging
        if (self.optimization_flags.enable_opcode_caching) {
            self.logPerformanceStats();
        }

        // Clean up call stack
        for (self.call_stack.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.call_stack.deinit(self.allocator);

        // Clean up string intern pool
        var intern_iterator = self.string_intern_pool.iterator();
        while (intern_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.release(self.allocator);
        }
        self.string_intern_pool.deinit();

        // Clean up error context
        self.error_context.deinit(self.allocator);

        // Clean up all global variables (this will release their references)
        var global_iterator = self.global.vars.iterator();
        while (global_iterator.next()) |entry| {
            // Only release if it's a managed type
            switch (entry.value_ptr.*.tag) {
                .string, .array, .object, .struct_instance, .resource, .user_function, .closure, .arrow_function => {
                    types.gc.decRef(&self.memory_manager, entry.value_ptr.*);
                },
                else => {},
            }
        }

        // Clean up try-catch stack
        self.try_catch_stack.deinit(self.allocator);

        // Clean up error handler
        self.error_handler.deinit();

        // Clean up standard library
        self.stdlib.deinit();

        // Clean up structs - 简化清理避免迭代器问题
        self.structs.deinit();

        // Clean up traits
        var trait_iterator = self.traits.iterator();
        while (trait_iterator.next()) |entry| {
            const trait_ptr = entry.value_ptr.*;
            trait_ptr.deinit(self.allocator);
            self.allocator.destroy(trait_ptr);
        }
        self.traits.deinit();

        // Clean up interfaces
        var interface_iterator = self.interfaces.iterator();
        while (interface_iterator.next()) |entry| {
            const interface_ptr = entry.value_ptr.*;
            interface_ptr.deinit(self.allocator);
            self.allocator.destroy(interface_ptr);
        }
        self.interfaces.deinit();

        // Clean up classes - 调用PHPClass.deinit释放属性名和方法名
        var class_iterator = self.classes.iterator();
        while (class_iterator.next()) |entry| {
            const class_ptr = entry.value_ptr.*;
            class_ptr.deinit(self.allocator);
            self.allocator.destroy(class_ptr);
        }
        self.classes.deinit();

        // Clean up memory manager (this will force final garbage collection)
        self.memory_manager.deinit();

        self.global.deinit();
        self.allocator.destroy(self.global);
        self.allocator.destroy(self);
    }

    pub fn getVariable(self: *VM, name: []const u8) ?Value {
        // Check current call frame first
        if (self.call_stack.items.len > 0) {
            const current_frame = &self.call_stack.items[self.call_stack.items.len - 1];
            if (current_frame.locals.get(name)) |value| {
                return value;
            }
        }

        // Then check global scope
        return self.global.get(name);
    }

    pub fn setVariable(self: *VM, name: []const u8, value: Value) !void {
        // Check current call frame first
        if (self.call_stack.items.len > 0) {
            var current_frame = &self.call_stack.items[self.call_stack.items.len - 1];

            // If it's a new variable in local scope, retain it
            // If it exists, set() will handle release/retain
            if (current_frame.locals.get(name)) |old_value| {
                self.releaseValue(old_value);
            }

            self.retainValue(value);
            try current_frame.locals.put(name, value);
            return;
        }

        // Then set in global scope
        try self.global.set(name, value);
    }

    pub fn deleteVariable(self: *VM, name: []const u8) bool {
        // Check current call frame first
        if (self.call_stack.items.len > 0) {
            var current_frame = &self.call_stack.items[self.call_stack.items.len - 1];

            if (current_frame.locals.get(name)) |old_value| {
                self.releaseValue(old_value);
                _ = current_frame.locals.remove(name);
                return true;
            }
        }

        // Then check global scope
        return self.global.remove(name);
    }

    fn retainValue(self: *VM, value: Value) void {
        _ = self;
        switch (value.tag) {
            .string => _ = value.data.string.retain(),
            .array => _ = value.data.array.retain(),
            .object => _ = value.data.object.retain(),
            .struct_instance => _ = value.data.struct_instance.retain(),
            .resource => _ = value.data.resource.retain(),
            .user_function => _ = value.data.user_function.retain(),
            .closure => _ = value.data.closure.retain(),
            .arrow_function => _ = value.data.arrow_function.retain(),
            else => {},
        }
    }

    fn processParameters(self: *VM, params_indices: []const ast.Node.Index) ![]types.Method.Parameter {
        const parameters = try self.allocator.alloc(types.Method.Parameter, params_indices.len);
        for (params_indices, 0..) |param_idx, i| {
            const param_node = self.context.nodes.items[param_idx];
            if (param_node.tag == .parameter) {
                const param_data = param_node.data.parameter;
                const param_name = self.context.string_pool.keys()[param_data.name];
                const php_param_name = try types.PHPString.init(self.allocator, param_name);
                defer php_param_name.release(self.allocator);

                parameters[i] = types.Method.Parameter.init(php_param_name);

                parameters[i].is_variadic = param_data.is_variadic;
                parameters[i].is_reference = param_data.is_reference;

                // Store default value as AST node index, not evaluated value
                // It will be evaluated when the function is called
                if (param_data.default_value) |dv_idx| {
                    // For now, evaluate simple literals only
                    const dv_node = self.context.nodes.items[dv_idx];
                    switch (dv_node.tag) {
                        .literal_int => {
                            parameters[i].default_value = Value.initInt(dv_node.data.literal_int.value);
                        },
                        .literal_float => {
                            parameters[i].default_value = Value.initFloat(dv_node.data.literal_float.value);
                        },
                        .literal_string => {
                            const str_id = dv_node.data.literal_string.value;
                            const str_val = self.context.string_pool.keys()[str_id];
                            parameters[i].default_value = try Value.initStringWithManager(&self.memory_manager, str_val);
                        },
                        else => {
                            // For complex expressions, don't evaluate at definition time
                            // Leave default_value as null and handle it at call time
                            parameters[i].default_value = null;
                        },
                    }
                }
            }
        }
        return parameters;
    }

    pub fn defineBuiltin(self: *VM, name: []const u8, function: anytype) !void {
        const value = Value{
            .tag = .builtin_function,
            .data = .{ .builtin_function = @ptrCast(&function) },
        };
        try self.global.set(name, value);
    }

    // Optimized builtin function registration
    pub fn registerBuiltinFunctions(self: *VM) !void {
        try self.defineBuiltin("count", countFn);
        try self.defineBuiltin("call_user_func", callUserFuncFn);
        try self.defineBuiltin("call_user_func_array", callUserFuncArrayFn);
        try self.defineBuiltin("is_callable", isCallableFn);
        try self.defineBuiltin("class_exists", classExistsFn);
        try self.defineBuiltin("method_exists", methodExistsFn);
        try self.defineBuiltin("property_exists", propertyExistsFn);
        try self.defineBuiltin("get_class", getClassFn);
        try self.defineBuiltin("get_class_methods", getClassMethodsFn);
        try self.defineBuiltin("get_class_vars", getClassVarsFn);
        try self.defineBuiltin("get_object_vars", getObjectVarsFn);
        try self.defineBuiltin("is_a", isAFn);
        try self.defineBuiltin("is_subclass_of", isSubclassOfFn);

        // PDO functions
        try self.defineBuiltin("pdo_exec", pdoExecFn);
        try self.defineBuiltin("pdo_query", pdoQueryFn);
        try self.defineBuiltin("pdo_prepare", pdoPrepareFn);
        try self.defineBuiltin("pdo_begin_transaction", pdoBeginTransactionFn);
        try self.defineBuiltin("pdo_commit", pdoCommitFn);
        try self.defineBuiltin("pdo_rollback", pdoRollbackFn);

        // Variable handling functions
        try self.defineBuiltin("unset", unsetFn);
        try self.defineBuiltin("empty", emptyFn);
        try self.defineBuiltin("is_null", isNullFn);

        // Reflection functions
        try self.defineBuiltin("get_declared_classes", getDeclaredClassesFn);
        try self.defineBuiltin("get_declared_interfaces", getDeclaredInterfacesFn);
        try self.defineBuiltin("get_declared_traits", getDeclaredTraitsFn);
        try self.defineBuiltin("get_parent_class", getParentClassFn);
        try self.defineBuiltin("interface_exists", interfaceExistsFn);
        try self.defineBuiltin("trait_exists", traitExistsFn);
        try self.defineBuiltin("get_class_constants", getClassConstantsFn);
    }

    pub fn registerStandardLibraryFunctions(self: *VM) !void {
        const start_time = std.time.nanoTimestamp();

        var iterator = self.stdlib.functions.iterator();
        while (iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            const builtin_func = entry.value_ptr.*;

            const value = Value{
                .tag = .builtin_function,
                .data = .{ .builtin_function = @ptrCast(builtin_func.handler) },
            };
            try self.global.set(name, value);
        }

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
    }

    // Performance monitoring and optimization methods
    pub fn logPerformanceStats(self: *VM) void {
        std.debug.print("\n=== PHP Interpreter Performance Statistics ===\n", .{});
        std.debug.print("Function calls: {d}\n", .{self.execution_stats.function_calls});
        std.debug.print("Memory allocations: {d}\n", .{self.execution_stats.memory_allocations});
        std.debug.print("GC collections: {d}\n", .{self.execution_stats.gc_collections});
        std.debug.print("Execution time: {d}ns\n", .{self.execution_stats.execution_time_ns});
        std.debug.print("Peak memory usage: {d} bytes\n", .{self.execution_stats.peak_memory_usage});
        std.debug.print("String intern pool size: {d}\n", .{self.string_intern_pool.count()});
        std.debug.print("Call stack depth: {d}\n", .{self.call_stack.items.len});
        std.debug.print("===============================================\n", .{});
    }

    pub fn getMemoryUsage(self: *VM) usize {
        return self.memory_manager.getMemoryUsage();
    }

    pub fn forceGarbageCollection(self: *VM) u32 {
        const collected = self.memory_manager.forceCollect();
        self.execution_stats.gc_collections += 1;
        return collected;
    }

    pub fn optimizeMemoryUsage(self: *VM) !void {
        // Force garbage collection
        _ = self.forceGarbageCollection();

        // Clean up string intern pool of unused strings
        if (self.optimization_flags.enable_string_interning) {
            try self.cleanupStringInternPool();
        }

        // Update peak memory usage
        const current_usage = self.getMemoryUsage();
        if (current_usage > self.execution_stats.peak_memory_usage) {
            self.execution_stats.peak_memory_usage = current_usage;
        }
    }

    fn cleanupStringInternPool(self: *VM) !void {
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        var iterator = self.string_intern_pool.iterator();
        while (iterator.next()) |entry| {
            // If reference count is 1, it means only the pool is holding it
            if (entry.value_ptr.*.ref_count == 1) {
                try to_remove.append(entry.key_ptr.*);
            }
        }

        // Remove unused strings
        for (to_remove.items) |key| {
            if (self.string_intern_pool.fetchRemove(key)) |removed| {
                removed.value.release(self.allocator);
                self.allocator.free(key);
            }
        }
    }

    // Memory pooling optimization for frequently allocated objects
    pub fn initializeMemoryPools(self: *VM) !void {
        if (!self.optimization_flags.enable_memory_pooling) return;

        // Pre-allocate common object pools
        // This would be implemented with actual memory pools in a real system
        // Placeholder implementation - would initialize memory pools here
    }

    // JIT compilation hooks (placeholder for future implementation)
    pub fn compileToJIT(self: *VM, function: *types.UserFunction) !void {
        if (!self.optimization_flags.enable_jit_compilation) return;

        // Placeholder for JIT compilation
        // Would analyze function body and generate optimized machine code
        // For now, just track the compilation attempt
        self.execution_stats.function_calls += 1;
        _ = function;
    }

    // Opcode caching system
    pub fn cacheOpcode(self: *VM, node_idx: ast.Node.Index, opcode: []const u8) !void {
        if (!self.optimization_flags.enable_opcode_caching) return;

        // Placeholder for opcode caching
        // Would store compiled opcodes for faster re-execution
        // For now, just track that we would cache this opcode
        self.execution_stats.function_calls += 1; // Track cache operations
        _ = node_idx;
        _ = opcode;
    }

    pub fn getCachedOpcode(self: *VM, node_idx: ast.Node.Index) ?[]const u8 {
        if (!self.optimization_flags.enable_opcode_caching) return null;

        // Placeholder for opcode retrieval
        // Would retrieve cached opcodes here
        self.execution_stats.function_calls += 1; // Track cache lookups
        _ = node_idx;
        return null;
    }

    // Enhanced error reporting with better context
    pub fn reportError(self: *VM, error_type: ErrorType, message: []const u8, suggestions: []const []const u8) !void {
        // Generate detailed error report
        const stack_trace = try self.generateStackTrace();
        defer self.allocator.free(stack_trace);

        // Add error to context
        try self.error_context.addError(self.allocator, error_type, message, self.current_file, self.current_line, stack_trace);

        // Print enhanced error message
        std.debug.print("PHP Error: {s}\n", .{message});
        std.debug.print("File: {s}, Line: {d}\n", .{ self.current_file, self.current_line });
        std.debug.print("Stack trace:\n{s}\n", .{stack_trace});

        if (suggestions.len > 0) {
            std.debug.print("Suggestions:\n", .{});
            for (suggestions) |suggestion| {
                std.debug.print("  - {s}\n", .{suggestion});
            }
        }
    }

    // Performance optimization: Fast property access
    pub fn getObjectPropertyOptimized(self: *VM, object_value: Value, property_name: []const u8) !Value {
        if (!self.optimization_flags.enable_fast_property_access) {
            return self.getObjectProperty(object_value, property_name);
        }

        if (object_value.tag != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property access on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const object = object_value.data.object.data;

        // Fast path: direct property lookup without method calls
        if (object.properties.get(property_name)) |value| {
            return value;
        }

        // Check class properties
        if (object.class.hasProperty(property_name)) {
            const property = object.class.getProperty(property_name);
            if (property.default_value) |default_val| {
                return default_val;
            }
        }

        // Fall back to magic method handling
        return self.getObjectProperty(object_value, property_name);
    }

    // Constant folding optimization
    pub fn evaluateConstantExpression(self: *VM, node: ast.Node.Index) ?Value {
        if (!self.optimization_flags.enable_constant_folding) return null;

        const ast_node = self.context.nodes.items[node];

        return switch (ast_node.tag) {
            .literal_int => Value.initInt(ast_node.data.literal_int.value),
            .literal_float => Value.initFloat(ast_node.data.literal_float.value),
            .literal_string => {
                const str_id = ast_node.data.literal_string.value;
                const str_val = self.context.string_pool.keys()[str_id];
                return Value.initStringWithManager(&self.memory_manager, str_val) catch null;
            },
            .binary_expr => {
                const left_const = self.evaluateConstantExpression(ast_node.data.binary_expr.lhs);
                const right_const = self.evaluateConstantExpression(ast_node.data.binary_expr.rhs);

                if (left_const != null and right_const != null) {
                    return self.evaluateBinaryOperation(left_const.?, ast_node.data.binary_expr.op, right_const.?) catch null;
                }
                return null;
            },
            else => null,
        };
    }

    // Optimized string creation with interning
    pub fn createInternedString(self: *VM, str: []const u8) !Value {
        if (!self.optimization_flags.enable_string_interning) {
            return Value.initStringWithManager(&self.memory_manager, str);
        }

        // Check if string is already interned
        if (self.string_intern_pool.get(str)) |interned_box| {
            // Return reference to existing string and increment ref count
            interned_box.ref_count += 1;
            return Value{ .tag = .string, .data = .{ .string = interned_box } };
        }

        // Create new interned string
        const php_string = try types.PHPString.init(self.allocator, str);
        const key = try self.allocator.dupe(u8, str);

        const box = try self.allocator.create(types.gc.Box(*types.PHPString));
        box.* = .{
            .ref_count = 2, // One for the pool, one for the returned Value
            .gc_info = .{},
            .data = php_string,
        };

        try self.string_intern_pool.put(key, box);

        return Value{ .tag = .string, .data = .{ .string = box } };
    }

    pub fn setCurrentLocation(self: *VM, file: []const u8, line: u32) void {
        self.current_file = file;
        self.current_line = line;
    }

    // Enhanced error handling with better context
    pub fn throwExceptionWithContext(self: *VM, exception: *PHPException) !Value {
        // Add current call stack to exception
        try self.addCallStackToException(exception);

        // Log error to context
        const stack_trace = try self.generateStackTrace();
        defer self.allocator.free(stack_trace);

        try self.error_context.addError(self.allocator, .fatal_error, // Map exception type to error type
            exception.message.data, exception.file.data, exception.line, stack_trace);

        // Check if we're in a try-catch block
        if (self.try_catch_stack.items.len > 0) {
            var context = &self.try_catch_stack.items[self.try_catch_stack.items.len - 1];

            // Try to catch the exception
            if (context.catchException(exception, exception.exception_type)) {
                // Exception was caught, continue execution
                return Value.initNull();
            }
        }

        // No catch block found, handle as uncaught exception
        const result = self.error_handler.handleException(exception);
        // Clean up the exception after handling
        exception.deinit(self.allocator);
        try result;
        return error.UncaughtException;
    }

    fn addCallStackToException(self: *VM, exception: *PHPException) !void {
        var stack_frames = std.ArrayList(exceptions.StackFrame){};
        defer stack_frames.deinit(self.allocator);

        // Add current location
        const current_frame = try exceptions.StackFrame.init(self.allocator, "main", self.current_file, self.current_line, 0);
        try stack_frames.append(self.allocator, current_frame);

        // Add call stack frames
        for (self.call_stack.items) |frame| {
            const stack_frame = try exceptions.StackFrame.init(self.allocator, frame.function_name, frame.file, frame.line, 0);
            try stack_frames.append(self.allocator, stack_frame);
        }

        try exception.setTrace(self.allocator, stack_frames.items);
    }

    fn generateStackTrace(self: *VM) ![]u8 {
        var trace = std.ArrayList(u8){};
        defer trace.deinit(self.allocator);

        // Add current location
        const current_line = try std.fmt.allocPrint(self.allocator, "#0 {s}({d}): main\n", .{ self.current_file, self.current_line });
        defer self.allocator.free(current_line);
        try trace.appendSlice(self.allocator, current_line);

        // Add call stack
        for (self.call_stack.items, 1..) |frame, i| {
            const frame_line = try std.fmt.allocPrint(self.allocator, "#{d} {s}({d}): {s}\n", .{ i, frame.file, frame.line, frame.function_name });
            defer self.allocator.free(frame_line);
            try trace.appendSlice(self.allocator, frame_line);
        }

        return trace.toOwnedSlice(self.allocator);
    }

    pub fn pushCallFrame(self: *VM, function_name: []const u8, file: []const u8, line: u32) !void {
        const frame = CallFrame.init(self.allocator, function_name, file, line);
        try self.call_stack.append(self.allocator, frame);
    }

    pub fn popCallFrame(self: *VM) void {
        if (self.call_stack.items.len > 0) {
            var frame = &self.call_stack.items[self.call_stack.items.len - 1];
            frame.deinit(self.allocator);
            _ = self.call_stack.pop();
        }
    }

    pub fn throwException(self: *VM, exception: *PHPException) !Value {
        return self.throwExceptionWithContext(exception);
    }

    pub fn handleError(self: *VM, error_type: ErrorType, message: []const u8) !void {
        try self.error_handler.handleError(error_type, message, self.current_file, self.current_line);
    }

    pub fn enterTryCatch(self: *VM) !void {
        const context = TryCatchContext.init(self.allocator);
        try self.try_catch_stack.append(self.allocator, context);
    }

    pub fn exitTryCatch(self: *VM) void {
        // Simplified - just remove the last item without cleanup for now
        if (self.try_catch_stack.items.len > 0) {
            _ = self.try_catch_stack.pop();
        }
    }

    pub fn executeFinally(self: *VM) void {
        if (self.try_catch_stack.items.len > 0) {
            var context = &self.try_catch_stack.items[self.try_catch_stack.items.len - 1];
            context.executeFinally();
        }
    }

    pub fn defineClass(self: *VM, name: []const u8, class: *types.PHPClass) !void {
        try self.classes.put(name, class);
    }

    pub fn defineInterface(self: *VM, name: []const u8, interface_obj: *types.PHPInterface) !void {
        try self.interfaces.put(name, interface_obj);
    }

    pub fn defineTrait(self: *VM, name: []const u8, trait_obj: *types.PHPTrait) !void {
        try self.traits.put(name, trait_obj);
    }

    pub fn getClass(self: *VM, name: []const u8) ?*types.PHPClass {
        return self.classes.get(name);
    }

    pub fn getInterface(self: *VM, name: []const u8) ?*types.PHPInterface {
        return self.interfaces.get(name);
    }

    pub fn getTrait(self: *VM, name: []const u8) ?*types.PHPTrait {
        return self.traits.get(name);
    }

    pub fn createObject(self: *VM, class_name: []const u8) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.memory_allocations += 1;

        const class = self.getClass(class_name) orelse {
            const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
            return self.throwException(exception);
        };

        // Check if class is abstract
        if (class.modifiers.is_abstract) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot instantiate abstract class", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const value = try Value.initObjectWithManager(&self.memory_manager, class);
        const object = value.data.object.data;

        // Initialize properties with default values (optimized)
        if (self.optimization_flags.enable_fast_property_access) {
            try self.initializeObjectPropertiesOptimized(object, class);
        } else {
            try self.initializeObjectProperties(object, class);
        }

        // Don't call constructor here - it will be called by evaluateObjectInstantiation
        // with the proper arguments

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return value;
    }

    fn initializeObjectProperties(self: *VM, object: *types.PHPObject, class: *types.PHPClass) !void {
        var prop_iterator = class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                try object.setProperty(self.allocator, entry.key_ptr.*, default_val);
            }
        }
    }

    fn initializeObjectPropertiesOptimized(self: *VM, object: *types.PHPObject, class: *types.PHPClass) !void {
        // Pre-allocate property map with expected size
        const expected_size = class.properties.count();
        try object.properties.ensureTotalCapacity(expected_size);

        var prop_iterator = class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                try object.setProperty(self.allocator, entry.key_ptr.*, default_val);
            }
        }
    }

    pub fn callObjectMethod(self: *VM, object_value: Value, method_name: []const u8, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        if (object_value.tag != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Method call on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const object = object_value.data.object.data;
        const result = object.callMethod(self, object_value, method_name, args) catch |err| switch (err) {
            error.MagicMethodCall => {
                const name_val = try Value.initString(self.allocator, method_name);
                defer name_val.release(self.allocator);

                // Wrap arguments in a PHP array
                const args_array_val = try Value.initArrayWithManager(&self.memory_manager);
                const args_array = args_array_val.data.array.data;
                for (args) |arg| {
                    try args_array.push(self.allocator, arg);
                }
                defer args_array_val.release(self.allocator);

                const magic_args = [_]Value{ name_val, args_array_val };
                return self.callObjectMethod(object_value, "__call", &magic_args);
            },
            else => return err,
        };
        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    pub fn callPDOMethod(self: *VM, pdo_value: Value, method_name: []const u8, args: []const Value) !Value {

        // Get the underlying PDO struct from the object's properties or data
        // For now, we'll assume the PDO object has the database connection stored
        // This is a simplified implementation

        if (std.mem.eql(u8, method_name, "exec")) {
            return self.callPDOExec(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "query")) {
            return self.callPDOQuery(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "prepare")) {
            return self.callPDOPrepare(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "beginTransaction")) {
            return self.callPDOBeginTransaction(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "commit")) {
            return self.callPDOCommit(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "rollBack")) {
            return self.callPDORollBack(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "lastInsertId")) {
            return self.callPDOLastInsertId(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "quote")) {
            return self.callPDOQuote(pdo_value, args);
        }

        const error_msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method PDO::{s}", .{method_name});
        defer self.allocator.free(error_msg);
        const exception = try ExceptionFactory.createTypeError(self.allocator, error_msg, self.current_file, self.current_line);
        return self.throwException(exception);
    }

    pub fn callConcurrencyMethod(self: *VM, obj_value: Value, method_name: []const u8, args: []const Value) !Value {
        const obj = obj_value.data.object.data;
        const class_name = obj.class.name.data;

        // builtin_concurrency functions expect []Value (mutable)
        // We'll create a temporary mutable slice
        const mutable_args = try self.allocator.alloc(Value, args.len);
        defer self.allocator.free(mutable_args);
        @memcpy(mutable_args, args);

        if (std.mem.eql(u8, class_name, "Mutex")) {
            return try builtin_concurrency.callMutexMethod(self, obj, method_name, mutable_args);
        } else if (std.mem.eql(u8, class_name, "Atomic")) {
            return try builtin_concurrency.callAtomicMethod(self, obj, method_name, mutable_args);
        } else if (std.mem.eql(u8, class_name, "RWLock")) {
            return try builtin_concurrency.callRWLockMethod(self, obj, method_name, mutable_args);
        } else if (std.mem.eql(u8, class_name, "SharedData")) {
            return try builtin_concurrency.callSharedDataMethod(self, obj, method_name, mutable_args);
        } else if (std.mem.eql(u8, class_name, "Channel")) {
            return try builtin_concurrency.callChannelMethod(self, obj, method_name, mutable_args);
        }

        return error.MethodNotFound;
    }

    fn callPDOExec(self: *VM, pdo_value: Value, args: []const Value) !Value {
        if (args.len != 1 or args[0].tag != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::exec() expects exactly 1 parameter, string given", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const sql = args[0].data.string.data.data;
        const pdo_object = pdo_value.data.object.data;

        // Get the stored PDO connection
        const connection_prop = pdo_object.getProperty("_pdo_connection") catch {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO connection not initialized", self.current_file, self.current_line);
            return self.throwException(exception);
        };

        if (connection_prop.tag != .integer) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid PDO connection", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.data.integer))));
        const result = try pdo_ptr.exec(sql);
        return Value.initInt(result);
    }

    fn callPDOQuery(self: *VM, pdo_value: Value, args: []const Value) !Value {
        _ = pdo_value;
        if (args.len != 1 or args[0].tag != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::query() expects exactly 1 parameter, string given", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        // Similar to exec, but returns a PDOStatement
        const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::query() not implemented yet", self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn callPDOPrepare(self: *VM, pdo_value: Value, args: []const Value) !Value {
        _ = pdo_value;
        if (args.len != 1 or args[0].tag != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::prepare() expects exactly 1 parameter, string given", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        // Return a PDOStatement object
        const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::prepare() not implemented yet", self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn callPDOBeginTransaction(self: *VM, pdo_value: Value, args: []const Value) !Value {
        _ = pdo_value;
        _ = args;
        const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::beginTransaction() not implemented yet", self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn callPDOCommit(self: *VM, pdo_value: Value, args: []const Value) !Value {
        _ = pdo_value;
        _ = args;
        const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::commit() not implemented yet", self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn callPDORollBack(self: *VM, pdo_value: Value, args: []const Value) !Value {
        _ = pdo_value;
        _ = args;
        const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::rollBack() not implemented yet", self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn callPDOLastInsertId(self: *VM, pdo_value: Value, args: []const Value) !Value {
        _ = pdo_value;
        _ = args;
        const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::lastInsertId() not implemented yet", self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn callPDOQuote(self: *VM, pdo_value: Value, args: []const Value) !Value {
        _ = pdo_value;
        if (args.len != 1 or args[0].tag != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::quote() expects exactly 1 parameter, string given", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const str = args[0].data.string.data.data;
        // Simple quoting - in real PDO this would escape properly based on driver
        const quoted = try std.fmt.allocPrint(self.allocator, "'{s}'", .{str});
        defer self.allocator.free(quoted);

        return try Value.initString(self.allocator, quoted);
    }

    pub fn callStructMethod(self: *VM, struct_value: Value, method_name: []const u8, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        if (struct_value.tag != .struct_instance) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Method call on non-struct", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const struct_inst = struct_value.data.struct_instance.data;

        const result = try struct_inst.callMethod(self, struct_value, method_name, args);

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    pub fn getObjectProperty(self: *VM, object_value: Value, property_name: []const u8) !Value {
        if (object_value.tag != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property access on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const object = object_value.data.object.data;
        const value = object.getProperty(property_name) catch |err| switch (err) {
            error.MagicMethodCall => {
                const name_val = try Value.initString(self.allocator, property_name);
                defer name_val.release(self.allocator);
                const args = [_]Value{name_val};
                return self.callObjectMethod(object_value, "__get", &args);
            },
            error.UndefinedProperty => {
                const exception = try ExceptionFactory.createUndefinedPropertyError(self.allocator, object.class.name.data, property_name, self.current_file, self.current_line);
                return self.throwException(exception);
            },
            else => return err,
        };
        self.retainValue(value);
        return value;
    }

    pub fn setObjectProperty(self: *VM, object_value: Value, property_name: []const u8, value: Value) !void {
        if (object_value.tag != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property assignment on non-object", self.current_file, self.current_line);
            _ = try self.throwException(exception);
            return;
        }

        const object = object_value.data.object.data;
        object.setProperty(self.allocator, property_name, value) catch |err| switch (err) {
            error.MagicMethodCall => {
                const name_val = try Value.initString(self.allocator, property_name);
                defer name_val.release(self.allocator);
                const args = [_]Value{ name_val, value };
                const result = try self.callObjectMethod(object_value, "__set", &args);
                defer self.releaseValue(result);
                return;
            },
            error.ReadonlyPropertyModification => {
                const exception = try ExceptionFactory.createReadonlyPropertyError(self.allocator, object.class.name.data, property_name, self.current_file, self.current_line);
                _ = try self.throwException(exception);
                return;
            },
            else => return err,
        };
    }

    pub fn callUserFunction(self: *VM, function: *types.UserFunction, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        // Push call frame for better error reporting
        try self.pushCallFrame(function.name.data, self.current_file, self.current_line);
        defer self.popCallFrame();

        // Validate arguments
        try function.validateArguments(args);

        // Bind arguments to parameters
        var bound_args = try function.bindArguments(args, self.allocator);
        defer {
            var it = bound_args.iterator();
            while (it.next()) |entry| {
                self.releaseValue(entry.value_ptr.*);
            }
            bound_args.deinit();
        }

        // Populate local variables in the current frame
        var current_frame = &self.call_stack.items[self.call_stack.items.len - 1];
        var it = bound_args.iterator();
        while (it.next()) |entry| {
            // Transfer ownership to locals
            self.retainValue(entry.value_ptr.*);
            try current_frame.locals.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Execute body
        var result = Value.initNull();
        if (function.body) |body_ptr| {
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
            result = self.eval(body_node) catch |err| {
                if (err == error.Return) {
                    if (self.return_value) |val| {
                        const ret = val;
                        self.return_value = null;
                        return ret;
                    }
                    return Value.initNull();
                }
                return err;
            };
        }

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    pub fn callClosure(self: *VM, closure: *types.Closure, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        // Push call frame
        try self.pushCallFrame("closure", self.current_file, self.current_line);
        defer self.popCallFrame();

        const result = closure.call(self, args) catch |err| {
            if (err == error.Return) {
                if (self.return_value) |val| {
                    const ret = val;
                    self.return_value = null;
                    return ret;
                }
                return Value.initNull();
            }
            return err;
        };

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    pub fn callArrowFunction(self: *VM, arrow_function: *types.ArrowFunction, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        // Push call frame
        try self.pushCallFrame("arrow_function", self.current_file, self.current_line);
        defer self.popCallFrame();

        const result = arrow_function.call(self, args) catch |err| {
            if (err == error.Return) {
                if (self.return_value) |val| {
                    const ret = val;
                    self.return_value = null;
                    return ret;
                }
                return Value.initNull();
            }
            return err;
        };

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    pub fn createClosure(self: *VM, function: types.UserFunction, captured_vars: []const CapturedVar) !Value {
        var closure = types.Closure.init(self.allocator, function);

        // Capture variables
        for (captured_vars) |capture| {
            try closure.captureVariable(capture.name, capture.value);
        }

        const box = try self.memory_manager.allocClosure(closure);
        return Value{ .tag = .closure, .data = .{ .closure = box } };
    }

    pub fn createArrowFunction(self: *VM, parameters: []const types.Method.Parameter, body: ?*anyopaque) !Value {
        var arrow_function = types.ArrowFunction.init(self.allocator);
        arrow_function.parameters = parameters;
        arrow_function.body = body;

        // Auto-capture variables from current scope (simplified)
        // In a real implementation, this would analyze the body for variable references

        const box = try self.memory_manager.allocArrowFunction(arrow_function);
        return Value{ .tag = .arrow_function, .data = .{ .arrow_function = box } };
    }

    pub fn callUserFunc(self: *VM, function_name: []const u8, args: []const Value) !Value {
        const function_val = self.global.get(function_name) orelse {
            const exception = try ExceptionFactory.createUndefinedFunctionError(self.allocator, function_name, self.current_file, self.current_line);
            return self.throwException(exception);
        };

        return switch (function_val.tag) {
            .builtin_function => {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(function_val.data.builtin_function));
                return function(self, args);
            },
            .user_function => {
                return self.callUserFunction(function_val.data.user_function.data, args);
            },
            .closure => {
                return self.callClosure(function_val.data.closure.data, args);
            },
            .arrow_function => {
                return self.callArrowFunction(function_val.data.arrow_function.data, args);
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Not a callable function", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        };
    }

    // Reflection system convenience methods
    pub fn getReflectionClass(self: *VM, name: []const u8) !reflection.ReflectionClass {
        return self.reflection_system.getClass(name);
    }

    pub fn getReflectionObject(self: *VM, object: *types.PHPObject) reflection.ReflectionObject {
        return self.reflection_system.getObject(object);
    }

    pub fn getReflectionFunction(self: *VM, name: []const u8) !reflection.ReflectionFunction {
        return self.reflection_system.getFunction(name);
    }

    pub fn getReflectionMethod(self: *VM, class_name: []const u8, method_name: []const u8) !reflection.ReflectionMethod {
        return self.reflection_system.getMethod(class_name, method_name);
    }

    pub fn getReflectionProperty(self: *VM, class_name: []const u8, property_name: []const u8) !reflection.ReflectionProperty {
        return self.reflection_system.getProperty(class_name, property_name);
    }

    // Attribute system methods
    pub fn createAttributeClass(self: *VM, name: []const u8, target: types.Attribute.AttributeTarget) !*types.PHPClass {
        return self.reflection_system.createAttributeClass(name, target);
    }

    pub fn getReflectionAttribute(self: *VM, attribute: *const types.Attribute) reflection.ReflectionAttribute {
        return self.reflection_system.getAttribute(attribute);
    }

    pub fn defineAttribute(self: *VM, name: []const u8, target: types.Attribute.AttributeTarget) !void {
        _ = try self.createAttributeClass(name, target);
    }

    pub fn applyAttribute(self: *VM, target_type: types.Attribute.AttributeTargetType, target_name: []const u8, attribute_name: []const u8, args: []const Value) !void {
        // Create attribute instance
        const attr_name = try types.PHPString.init(self.allocator, attribute_name);
        const attribute = types.Attribute.init(attr_name, args, .{ .all = true }); // Simplified - would check actual target

        // Apply to appropriate target based on type
        switch (target_type) {
            .class => {
                if (self.getClass(target_name)) |class| {
                    // In a real implementation, would add to class.attributes
                    _ = class;
                    _ = attribute;
                }
            },
            .method => {
                // Would find method and add attribute
                _ = attribute;
            },
            .property => {
                // Would find property and add attribute
                _ = attribute;
            },
            .parameter => {
                // Would find parameter and add attribute
                _ = attribute;
            },
            .function => {
                // Would find function and add attribute
                _ = attribute;
            },
            .constant => {
                // Would find constant and add attribute
                _ = attribute;
            },
        }
    }

    pub fn run(self: *VM, node: ast.Node.Index) !Value {
        return self.eval(node);
    }

    fn evaluateBinaryExpression(self: *VM, binary_expr: anytype) !Value {
        const left = try self.eval(binary_expr.lhs);
        defer self.releaseValue(left);

        const right = try self.eval(binary_expr.rhs);
        defer self.releaseValue(right);

        return self.evaluateBinaryOp(binary_expr.op, left, right);
    }

    fn evaluateAddition(self: *VM, left: Value, right: Value) !Value {
        return switch (left.tag) {
            .integer => switch (right.tag) {
                .integer => Value.initInt(left.data.integer + right.data.integer),
                .float => Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) + right.data.float),
                else => self.handleInvalidOperands("addition"),
            },
            .float => switch (right.tag) {
                .integer => Value.initFloat(left.data.float + @as(f64, @floatFromInt(right.data.integer))),
                .float => Value.initFloat(left.data.float + right.data.float),
                else => self.handleInvalidOperands("addition"),
            },
            .string => switch (right.tag) {
                .string => self.concatenateStrings(left, right),
                else => self.handleInvalidOperands("addition"),
            },
            else => self.handleInvalidOperands("addition"),
        };
    }

    fn evaluateSubtraction(self: *VM, left: Value, right: Value) !Value {
        return switch (left.tag) {
            .integer => switch (right.tag) {
                .integer => Value.initInt(left.data.integer - right.data.integer),
                .float => Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) - right.data.float),
                else => self.handleInvalidOperands("subtraction"),
            },
            .float => switch (right.tag) {
                .integer => Value.initFloat(left.data.float - @as(f64, @floatFromInt(right.data.integer))),
                .float => Value.initFloat(left.data.float - right.data.float),
                else => self.handleInvalidOperands("subtraction"),
            },
            else => self.handleInvalidOperands("subtraction"),
        };
    }

    fn evaluateMultiplication(self: *VM, left: Value, right: Value) !Value {
        return switch (left.tag) {
            .integer => switch (right.tag) {
                .integer => Value.initInt(left.data.integer * right.data.integer),
                .float => Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) * right.data.float),
                else => self.handleInvalidOperands("multiplication"),
            },
            .float => switch (right.tag) {
                .integer => Value.initFloat(left.data.float * @as(f64, @floatFromInt(right.data.integer))),
                .float => Value.initFloat(left.data.float * right.data.float),
                else => self.handleInvalidOperands("multiplication"),
            },
            else => self.handleInvalidOperands("multiplication"),
        };
    }

    fn evaluateDivision(self: *VM, left: Value, right: Value) !Value {
        // Check for division by zero first
        const is_zero = switch (right.tag) {
            .integer => right.data.integer == 0,
            .float => right.data.float == 0.0,
            else => false,
        };

        if (is_zero) {
            const exception = try ExceptionFactory.createDivisionByZeroError(self.allocator, self.current_file, self.current_line);
            return self.throwException(exception);
        }

        return switch (left.tag) {
            .integer => switch (right.tag) {
                .integer => Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) / @as(f64, @floatFromInt(right.data.integer))),
                .float => Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) / right.data.float),
                else => self.handleInvalidOperands("division"),
            },
            .float => switch (right.tag) {
                .integer => Value.initFloat(left.data.float / @as(f64, @floatFromInt(right.data.integer))),
                .float => Value.initFloat(left.data.float / right.data.float),
                else => self.handleInvalidOperands("division"),
            },
            else => self.handleInvalidOperands("division"),
        };
    }

    fn evaluateConcatenation(self: *VM, left: Value, right: Value) !Value {
        const left_result = try self.valueToString(left);
        defer if (left_result.needs_free) self.allocator.free(left_result.str);

        const right_result = try self.valueToString(right);
        defer if (right_result.needs_free) self.allocator.free(right_result.str);

        if (self.optimization_flags.enable_string_interning) {
            const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_result.str, right_result.str });
            defer self.allocator.free(result);
            return self.createInternedString(result);
        } else {
            const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_result.str, right_result.str });
            defer self.allocator.free(result);
            return Value.initStringWithManager(&self.memory_manager, result);
        }
    }

    fn concatenateStrings(self: *VM, left: Value, right: Value) !Value {
        const left_str = left.data.string.data.data;
        const right_str = right.data.string.data.data;

        if (self.optimization_flags.enable_string_interning) {
            const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_str, right_str });
            defer self.allocator.free(result);
            return self.createInternedString(result);
        } else {
            const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_str, right_str });
            defer self.allocator.free(result);
            return Value.initStringWithManager(&self.memory_manager, result);
        }
    }

    fn handleInvalidOperands(self: *VM, operation: []const u8) !Value {
        const message = try std.fmt.allocPrint(self.allocator, "Invalid operands for {s}", .{operation});
        defer self.allocator.free(message);
        const exception = try ExceptionFactory.createTypeError(self.allocator, message, self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn valueToString(self: *VM, value: Value) !struct { str: []const u8, needs_free: bool } {
        const php_str = value.toString(self.allocator) catch |err| switch (err) {
            error.MagicMethodCall => blk: {
                const res = try self.callObjectMethod(value, "__toString", &.{});
                defer self.releaseValue(res);
                const s = try res.toString(self.allocator);
                break :blk s;
            },
            else => return err,
        };
        defer php_str.release(self.allocator);
        return .{ .str = try self.allocator.dupe(u8, php_str.data), .needs_free = true };
    }

    pub fn eval(self: *VM, node: ast.Node.Index) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        const ast_node = self.context.nodes.items[node];

        // Update current line for error reporting
        // We can approximate line number from token location if we had source map
        // For now, let's just use what we have if we can map it, but we don't have line info in Token yet?
        // Token has loc.start/end. We need to map that to line number.
        // Assuming we don't have easy line mapping yet, we skip this or implement it later.
        // But wait, ExceptionFactory takes line number.
        // Let's assume we can't easily get it right now without scanning source.

        switch (ast_node.tag) {
            .root => {
                var last_val = Value.initNull();
                for (ast_node.data.root.stmts) |stmt| {
                    // Release the previous value before evaluating the next one
                    self.releaseValue(last_val);
                    last_val = try self.eval(stmt);
                }
                return last_val;
            },
            .literal_string => {
                const str_id = ast_node.data.literal_string.value;
                const str_val = self.context.string_pool.keys()[str_id];
                const quote_type = ast_node.data.literal_string.quote_type;

                // 只对双引号字符串处理转义序列
                // 单引号字符串：只处理 \' 和 \\
                // 反引号字符串：完全原始，不处理任何转义
                if (quote_type == .double and string_utils.hasEscapeSequences(str_val)) {
                    const processed = try string_utils.processEscapeSequences(self.allocator, str_val);
                    defer self.allocator.free(processed);
                    return Value.initStringWithManager(&self.memory_manager, processed);
                } else if (quote_type == .single) {
                    // 单引号字符串只处理 \' 和 \\
                    const processed = try string_utils.processSingleQuoteEscapes(self.allocator, str_val);
                    defer self.allocator.free(processed);
                    return Value.initStringWithManager(&self.memory_manager, processed);
                }

                // 反引号字符串或无转义的字符串直接返回
                if (self.optimization_flags.enable_string_interning) {
                    return self.createInternedString(str_val);
                } else {
                    return Value.initStringWithManager(&self.memory_manager, str_val);
                }
            },
            .literal_int => {
                return Value.initInt(ast_node.data.literal_int.value);
            },
            .literal_float => {
                return Value.initFloat(ast_node.data.literal_float.value);
            },
            .literal_bool => {
                return Value.initBool(ast_node.data.literal_int.value != 0);
            },
            .literal_null => {
                return Value.initNull();
            },
            .variable => {
                const name_id = ast_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];
                if (self.getVariable(name)) |value| {
                    self.retainValue(value);
                    return value;
                } else {
                    const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, name, self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .assignment => {
                const target_idx = ast_node.data.assignment.target;
                const target_node = self.context.nodes.items[target_idx];

                const value = try self.eval(ast_node.data.assignment.value);

                if (target_node.tag == .variable) {
                    const name_id = target_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    try self.setVariable(name, value);
                } else if (target_node.tag == .property_access) {
                    const obj_val = try self.eval(target_node.data.property_access.target);
                    defer self.releaseValue(obj_val);

                    const prop_name = self.context.string_pool.keys()[target_node.data.property_access.property_name];

                    if (obj_val.tag == .struct_instance) {
                        const struct_inst = obj_val.data.struct_instance.data;
                        try struct_inst.setField(self.allocator, prop_name, value);
                    } else if (obj_val.tag == .object) {
                        try self.setObjectProperty(obj_val, prop_name, value);
                    } else {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Property assignment on non-object", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else if (target_node.tag == .array_access) {
                    const arr_val = try self.eval(target_node.data.array_access.target);
                    defer self.releaseValue(arr_val);

                    if (arr_val.tag != .array) {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use value as array", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }

                    const php_array = arr_val.data.array.data;
                    if (target_node.data.array_access.index) |index_idx| {
                        const index_val = try self.eval(index_idx);
                        defer self.releaseValue(index_val);

                        const key = switch (index_val.tag) {
                            .integer => types.ArrayKey{ .integer = index_val.data.integer },
                            .string => types.ArrayKey{ .string = index_val.data.string.data },
                            else => {
                                const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid array key type", self.current_file, self.current_line);
                                return self.throwException(exception);
                            },
                        };
                        try php_array.set(self.allocator, key, value);
                    } else {
                        // Push operation: $a[] = $val
                        try php_array.push(self.allocator, value);
                    }
                } else if (target_node.tag == .static_property_access) {
                    // ... (keep existing implementation)
                    const class_name = self.context.string_pool.keys()[target_node.data.static_property_access.class_name];
                    const prop_name = self.context.string_pool.keys()[target_node.data.static_property_access.property_name];

                    // Resolve class
                    const class = if (std.mem.eql(u8, class_name, "self")) blk: {
                        break :blk self.current_class orelse {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access self:: outside of class scope", self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                    } else if (std.mem.eql(u8, class_name, "parent")) blk: {
                        const curr_class = self.current_class orelse {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: outside of class scope", self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                        break :blk curr_class.parent orelse {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: when class has no parent", self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                    } else if (class_name.len > 0 and class_name[0] == '$') blk: {
                        // Variable class name
                        const var_value = self.getVariable(class_name) orelse {
                            const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, class_name, self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                        if (var_value.tag == .object) {
                            break :blk var_value.data.object.data.class;
                        } else if (var_value.tag == .string) {
                            const str_class_name = var_value.data.string.data.data;
                            break :blk self.getClass(str_class_name) orelse {
                                const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, str_class_name, self.current_file, self.current_line);
                                return self.throwException(exception);
                            };
                        } else {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use non-object as class in static property access", self.current_file, self.current_line);
                            return self.throwException(exception);
                        }
                    } else blk: {
                        break :blk self.getClass(class_name) orelse {
                            const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                    };

                    // Set static property
                    var property_set = false;

                    if (class.properties.getPtr(prop_name)) |prop| {
                        if (prop.modifiers.is_static) {
                            if (prop.default_value) |old_val| {
                                self.releaseValue(old_val);
                            }
                            self.retainValue(value);
                            prop.default_value = value;
                            property_set = true;
                        }
                    }

                    if (!property_set) {
                        // Check parent classes
                        var current = class.parent;
                        while (current) |parent| {
                            if (parent.properties.getPtr(prop_name)) |prop| {
                                if (prop.modifiers.is_static) {
                                    if (prop.default_value) |old_val| {
                                        self.releaseValue(old_val);
                                    }
                                    self.retainValue(value);
                                    prop.default_value = value;
                                    property_set = true;
                                    break;
                                }
                            }
                            current = parent.parent;
                        }
                    }

                    if (!property_set) {
                        // 如果属性存在但不是静态的，或者属性不存在
                        if (class.properties.contains(prop_name)) {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Accessing non-static property as static", self.current_file, self.current_line);
                            return self.throwException(exception);
                        }
                        const exception = try ExceptionFactory.createUndefinedPropertyError(self.allocator, class.name.data, prop_name, self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else {
                    std.debug.print("Invalid assignment target tag: {any}\n", .{target_node.tag});
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid assignment target", self.current_file, self.current_line);
                    return self.throwException(exception);
                }

                return value;
            },
            .echo_stmt => {
                // Handle multiple expressions in echo statement
                const exprs = ast_node.data.echo_stmt.exprs;
                for (exprs) |expr_idx| {
                    const value = try self.eval(expr_idx);
                    defer self.releaseValue(value);

                    try value.print();
                }
                return Value.initNull();
            },
            .function_call => {
                return self.evaluateFunctionCall(ast_node.data.function_call);
            },
            .method_call => {
                return self.evaluateMethodCall(ast_node.data.method_call);
            },
            .property_access => {
                return self.evaluatePropertyAccess(ast_node.data.property_access);
            },
            .array_access => {
                return self.evaluateArrayAccess(ast_node.data.array_access);
            },
            .array_init => {
                return self.evaluateArrayInit(ast_node.data.array_init);
            },
            .class_decl => {
                return self.evaluateClassDeclaration(ast_node.data.container_decl);
            },
            .trait_decl => {
                return self.evaluateTraitDeclaration(ast_node.data.container_decl);
            },
            .interface_decl => {
                return self.evaluateInterfaceDeclaration(ast_node.data.container_decl);
            },
            .struct_decl => {
                return self.evaluateStructDeclaration(ast_node.data.container_decl);
            },
            .struct_instantiation => {
                return self.evaluateStructInstantiation(ast_node.data.struct_instantiation);
            },
            .object_instantiation => {
                return self.evaluateObjectInstantiation(ast_node.data.object_instantiation);
            },
            .try_stmt => {
                return self.evaluateTryStatement(ast_node.data.try_stmt);
            },
            .throw_stmt => {
                return self.evaluateThrowStatement(ast_node.data.throw_stmt);
            },
            .closure => {
                return self.evaluateClosureCreation(ast_node.data.closure);
            },
            .arrow_function => {
                return self.evaluateArrowFunction(ast_node.data.arrow_function);
            },
            .binary_expr => {
                return self.evaluateBinaryExpression(ast_node.data.binary_expr);
            },
            .unary_expr => {
                return self.evaluateUnaryExpression(ast_node.data.unary_expr);
            },
            .postfix_expr => {
                return self.evaluatePostfixExpression(ast_node.data.postfix_expr);
            },
            .ternary_expr => {
                return self.evaluateTernaryExpression(ast_node.data.ternary_expr);
            },
            .pipe_expr => {
                return self.evaluatePipeExpression(ast_node.data.pipe_expr);
            },
            .clone_with_expr => {
                return self.evaluateCloneWithExpression(ast_node.data.clone_with_expr);
            },
            .function_decl => {
                return self.evaluateFunctionDeclaration(ast_node.data.function_decl);
            },
            .block => {
                return self.evaluateBlock(ast_node.data.block);
            },
            .if_stmt => {
                return self.evaluateIfStatement(ast_node.data.if_stmt);
            },
            .while_stmt => {
                return self.evaluateWhileStatement(ast_node.data.while_stmt);
            },
            .for_stmt => {
                return self.evaluateForStatement(ast_node.data.for_stmt);
            },
            .for_range_stmt => {
                return self.evaluateForRangeStatement(ast_node.data.for_range_stmt);
            },
            .foreach_stmt => {
                return self.evaluateForeachStatement(ast_node.data.foreach_stmt);
            },
            .return_stmt => {
                return self.evaluateReturnStatement(ast_node.data.return_stmt);
            },
            .break_stmt => {
                return self.evaluateBreakStatement(ast_node.data.break_stmt);
            },
            .continue_stmt => {
                return self.evaluateContinueStatement(ast_node.data.continue_stmt);
            },
            .static_method_call => {
                return self.evaluateStaticMethodCall(ast_node.data.static_method_call);
            },
            .static_property_access => {
                // Map to evaluateClassConstantAccess which already handles static properties
                const data = .{
                    .class_name = ast_node.data.static_property_access.class_name,
                    .constant_name = ast_node.data.static_property_access.property_name,
                };
                return self.evaluateClassConstantAccess(data);
            },
            .class_constant_access => {
                return self.evaluateClassConstantAccess(ast_node.data.class_constant_access);
            },
            .const_decl => {
                const name_id = ast_node.data.const_decl.name;
                const name = self.context.string_pool.keys()[name_id];
                const value = try self.eval(ast_node.data.const_decl.value);
                // PHP constants are global. Storing them in global environment without '$' prefix.
                try self.global.set(name, value);
                return value;
            },
            .property_decl, .method_decl => {
                // Member declarations are handled during class declaration processing.
                // If they appear at top level (e.g. due to parse errors), we ignore them.
                return Value.initNull();
            },
            .expression_stmt => {
                // Expression statements like namespace or use don't have a value to return.
                return Value.initNull();
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Unsupported AST node type", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }
    }

    pub fn releaseValue(self: *VM, value: Value) void {
        switch (value.tag) {
            .string => value.data.string.release(self.allocator),
            .array => value.data.array.release(self.allocator),
            .object => value.data.object.release(self.allocator),
            .struct_instance => value.data.struct_instance.release(self.allocator),
            .resource => value.data.resource.release(self.allocator),
            .user_function => value.data.user_function.release(self.allocator),
            .closure => value.data.closure.release(self.allocator),
            .arrow_function => value.data.arrow_function.release(self.allocator),
            else => {},
        }
    }

    fn evaluateFunctionCall(self: *VM, call_data: anytype) anyerror!Value {
        const name_node = self.context.nodes.items[call_data.name];

        // Prepare arguments
        var args = std.ArrayList(Value){};
        try args.ensureTotalCapacity(self.allocator, call_data.args.len);
        defer {
            for (args.items) |arg| {
                self.releaseValue(arg);
            }
            args.deinit(self.allocator);
        }

        for (call_data.args) |arg_node_idx| {
            const arg_value = try self.eval(arg_node_idx);
            try args.append(self.allocator, arg_value);
        }

        // Determine function to call
        if (name_node.tag == .variable) {
            const name_id = name_node.data.variable.name;
            const name = self.context.string_pool.keys()[name_id];

            // Check if it's a variable function call ($func()) or direct call (func())
            if (name_node.main_token.tag == .t_variable) {
                // Variable function call: $func()
                // Try to get variable value
                if (self.getVariable(name)) |val| {
                    // If it's a callable object
                    switch (val.tag) {
                        .user_function => return self.callUserFunction(val.data.user_function.data, args.items),
                        .closure => return self.callClosure(val.data.closure.data, args.items),
                        .arrow_function => return self.callArrowFunction(val.data.arrow_function.data, args.items),
                        .string => {
                            // If it's a string, use it as function name
                            const func_name = val.data.string.data.data;
                            return self.callFunctionByName(func_name, args.items);
                        },
                        else => {
                            std.debug.print("DEBUG: Value is not callable. Tag: {any}\n", .{val.tag});
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Value is not callable", self.current_file, self.current_line);
                            return self.throwException(exception);
                        },
                    }
                } else {
                    // Undefined variable
                    std.debug.print("DEBUG: Variable function call: Undefined variable '{s}'\n", .{name});
                    const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, name, self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            } else {
                // Direct function call: func() where func is an identifier (parsed as variable node)
                return self.callFunctionByName(name, args.items);
            }
        } else if (name_node.tag == .literal_string) {
            // Direct function call: func() - Parser might store name as literal_string?
            // Actually parser stores name index in function_call struct.
            // AST: function_call: struct { name: Index, args: []const Index }
            // name is Index to a node.
            const name_id = name_node.data.literal_string.value;
            const func_name = self.context.string_pool.keys()[name_id];
            return self.callFunctionByName(func_name, args.items);
        } else {
            // Try to interpret whatever node as a name?
            // In parser.zig parseFunctionCall uses parsePrimary for name?
            // Usually it eats T_STRING.
            // Let's assume if not variable, we extract string.
            // But for now, let's implement callFunctionByName helper.

            // Fallback for previous logic (assuming name_node contains name string)
            // The previous logic assumed name_node.tag == .variable was WRONG for direct calls too?
            // Wait, previous logic:
            // if (name_node.tag != .variable) Error
            // const name_id = name_node.data.variable.name;
            // This suggests parser stores function name as a VARIABLE node even for direct calls?
            // Let's check Parser.parseFunctionCall.
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid function name node", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    pub fn callFunctionByName(self: *VM, name: []const u8, args: []const Value) !Value {
        // First check if it's a standard library function (optimized lookup)
        if (self.stdlib.getFunction(name)) |builtin_func| {
            return builtin_func.call(self, args);
        }

        // Then check global functions
        const function_val = self.global.get(name) orelse {
            const exception = try ExceptionFactory.createUndefinedFunctionError(self.allocator, name, self.current_file, self.current_line);
            return self.throwException(exception);
        };

        return switch (function_val.tag) {
            .builtin_function => {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(function_val.data.builtin_function));
                return function(self, args);
            },
            .user_function => self.callUserFunction(function_val.data.user_function.data, args),
            .closure => self.callClosure(function_val.data.closure.data, args),
            .arrow_function => self.callArrowFunction(function_val.data.arrow_function.data, args),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Not a callable function", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        };
    }

    fn evaluatePropertyAccess(self: *VM, property_data: anytype) !Value {
        const target_value = try self.eval(property_data.target);
        defer self.releaseValue(target_value);

        const property_name = self.context.string_pool.keys()[property_data.property_name];

        if (target_value.tag == .struct_instance) {
            const struct_inst = target_value.data.struct_instance.data;
            const value = try struct_inst.getField(property_name);
            self.retainValue(value);
            return value;
        } else if (target_value.tag == .object) {
            return self.getObjectProperty(target_value, property_name);
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property access on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn evaluateArrayAccess(self: *VM, array_access: anytype) !Value {
        const target_value = try self.eval(array_access.target);
        defer self.releaseValue(target_value);

        if (target_value.tag != .array) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use value as array", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const php_array = target_value.data.array.data;
        if (array_access.index) |index_idx| {
            const index_val = try self.eval(index_idx);
            defer self.releaseValue(index_val);

            const key = switch (index_val.tag) {
                .integer => types.ArrayKey{ .integer = index_val.data.integer },
                .string => types.ArrayKey{ .string = index_val.data.string.data },
                else => {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid array key type", self.current_file, self.current_line);
                    return self.throwException(exception);
                },
            };

            if (php_array.get(key)) |val| {
                self.retainValue(val);
                return val;
            } else {
                return Value.initNull();
            }
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use [] for reading", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn evaluateObjectInstantiation(self: *VM, instantiation_data: anytype) !Value {
        const class_name_node = self.context.nodes.items[instantiation_data.class_name];
        if (class_name_node.tag != .variable) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid class name", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const name_id = class_name_node.data.variable.name;
        const name = self.context.string_pool.keys()[name_id];

        // Check if it's a struct
        if (self.getStruct(name)) |_| {
            // Re-use evaluateStructInstantiation by building appropriate data
            const struct_data = .{
                .struct_type = instantiation_data.class_name,
                .args = instantiation_data.args,
            };
            return self.evaluateStructInstantiation(struct_data);
        }

        // Check if there's a builtin constructor (for concurrency classes)
        if (std.mem.eql(u8, name, "Mutex") or std.mem.eql(u8, name, "Atomic") or
            std.mem.eql(u8, name, "RWLock") or std.mem.eql(u8, name, "SharedData") or
            std.mem.eql(u8, name, "Channel"))
        {
            if (self.global.get(name)) |constructor_value| {
                if (constructor_value.tag == .builtin_function) {
                    // Call the builtin constructor
                    var args = std.ArrayList(Value){};
                    defer {
                        for (args.items) |arg| {
                            self.releaseValue(arg);
                        }
                        args.deinit(self.allocator);
                    }

                    try args.ensureTotalCapacity(self.allocator, instantiation_data.args.len);
                    for (instantiation_data.args) |arg_idx| {
                        try args.append(self.allocator, try self.eval(arg_idx));
                    }

                    // Call the constructor directly based on the class name
                    if (std.mem.eql(u8, name, "Mutex")) {
                        return builtin_concurrency.mutexConstructor(self, args.items);
                    } else if (std.mem.eql(u8, name, "Atomic")) {
                        return builtin_concurrency.atomicConstructor(self, args.items);
                    } else if (std.mem.eql(u8, name, "RWLock")) {
                        return builtin_concurrency.rwlockConstructor(self, args.items);
                    } else if (std.mem.eql(u8, name, "SharedData")) {
                        return builtin_concurrency.sharedDataConstructor(self, args.items);
                    } else if (std.mem.eql(u8, name, "Channel")) {
                        return builtin_concurrency.channelConstructor(self, args.items);
                    }
                }
            }
        }

        // Otherwise assume it's a class
        const value = try self.createObject(name);

        // Special handling for PDO objects
        if (std.mem.eql(u8, name, "PDO")) {
            const pdo_object = value.data.object.data;

            // Create and store the PDO database connection
            var pdo_connection = try self.allocator.create(database.PDO);
            pdo_connection.* = database.PDO{
                .allocator = self.allocator,
                .driver = .sqlite,
                .connection = null,
                .in_transaction = false,
                .error_mode = .exception,
                .last_error = null,
                .attributes = std.StringHashMap(Value).init(self.allocator),
            };

            // Parse DSN from constructor arguments (simplified)
            var dsn: []const u8 = "sqlite::memory:";
            if (instantiation_data.args.len > 0) {
                const dsn_arg = instantiation_data.args[0];
                const dsn_node = self.context.nodes.items[dsn_arg];
                if (dsn_node.tag == .literal_string) {
                    const dsn_id = dsn_node.data.literal_string.value;
                    dsn = self.context.string_pool.keys()[dsn_id];
                }
            }

            const parsed_dsn = try database.parseDSN(self.allocator, dsn);
            defer {
                if (parsed_dsn.host.len > 0 and !std.mem.eql(u8, parsed_dsn.host, "localhost")) self.allocator.free(parsed_dsn.host);
                if (parsed_dsn.database.len > 0) self.allocator.free(parsed_dsn.database);
                self.allocator.free(parsed_dsn.charset);
            }

            try pdo_connection.connect(parsed_dsn, null, null);

            // Store the PDO connection in the object (simplified - using a property)
            const connection_value = Value.initInt(@intCast(@intFromPtr(pdo_connection))); // Store pointer as int
            try pdo_object.setProperty(self.allocator, "_pdo_connection", connection_value);

            return value;
        }

        // Call constructor if it exists
        const object = value.data.object.data;
        if (object.class.hasMethod("__construct")) {
            var args = std.ArrayList(Value){};
            defer {
                for (args.items) |arg| {
                    self.releaseValue(arg);
                }
                args.deinit(self.allocator);
            }

            try args.ensureTotalCapacity(self.allocator, instantiation_data.args.len);
            for (instantiation_data.args) |arg_idx| {
                try args.append(self.allocator, try self.eval(arg_idx));
            }

            const ctor_result = try self.callObjectMethod(value, "__construct", args.items);
            self.releaseValue(ctor_result);
        }

        return value;
    }

    fn evaluateMethodCall(self: *VM, method_data: anytype) !Value {
        const target_value = try self.eval(method_data.target);
        defer self.releaseValue(target_value);

        const method_name = self.context.string_pool.keys()[method_data.method_name];

        var args = std.ArrayList(Value){};
        try args.ensureTotalCapacity(self.allocator, method_data.args.len);
        defer {
            for (args.items) |arg| {
                self.releaseValue(arg);
            }
            args.deinit(self.allocator);
        }

        for (method_data.args) |arg_node_idx| {
            try args.append(self.allocator, try self.eval(arg_node_idx));
        }

        // 处理数字类型的内置方法（NumberWrapper）
        if (target_value.tag == .integer or target_value.tag == .float) {
            const number_wrapper = if (target_value.tag == .integer)
                types.number_wrapper.NumberWrapper.initInt(target_value.data.integer)
            else
                types.number_wrapper.NumberWrapper.initFloat(target_value.data.float);

            if (std.mem.eql(u8, method_name, "abs")) {
                return Value.initFloat(number_wrapper.abs());
            } else if (std.mem.eql(u8, method_name, "ceil")) {
                return Value.initFloat(number_wrapper.ceil());
            } else if (std.mem.eql(u8, method_name, "floor")) {
                return Value.initFloat(number_wrapper.floor());
            } else if (std.mem.eql(u8, method_name, "round")) {
                return Value.initFloat(number_wrapper.round());
            } else if (std.mem.eql(u8, method_name, "sqrt")) {
                return Value.initFloat(number_wrapper.sqrt());
            } else if (std.mem.eql(u8, method_name, "sin")) {
                return Value.initFloat(number_wrapper.sin());
            } else if (std.mem.eql(u8, method_name, "cos")) {
                return Value.initFloat(number_wrapper.cos());
            } else if (std.mem.eql(u8, method_name, "tan")) {
                return Value.initFloat(number_wrapper.tan());
            } else if (std.mem.eql(u8, method_name, "log")) {
                return Value.initFloat(number_wrapper.log());
            } else if (std.mem.eql(u8, method_name, "exp")) {
                return Value.initFloat(number_wrapper.exp());
            } else if (std.mem.eql(u8, method_name, "pow")) {
                if (args.items.len == 1) {
                    const exponent_val = args.items[0];
                    const exponent_wrapper = if (exponent_val.tag == .integer)
                        types.number_wrapper.NumberWrapper.initInt(exponent_val.data.integer)
                    else if (exponent_val.tag == .float)
                        types.number_wrapper.NumberWrapper.initFloat(exponent_val.data.float)
                    else
                        return Value.initFloat(std.math.nan(f64));
                    return Value.initFloat(number_wrapper.pow(exponent_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitAnd") or std.mem.eql(u8, method_name, "bit_and")) {
                if (args.items.len == 1) {
                    const other_val = args.items[0];
                    const other_wrapper = if (other_val.tag == .integer)
                        types.number_wrapper.NumberWrapper.initInt(other_val.data.integer)
                    else if (other_val.tag == .float)
                        types.number_wrapper.NumberWrapper.initFloat(other_val.data.float)
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitAnd(other_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitOr") or std.mem.eql(u8, method_name, "bit_or")) {
                if (args.items.len == 1) {
                    const other_val = args.items[0];
                    const other_wrapper = if (other_val.tag == .integer)
                        types.number_wrapper.NumberWrapper.initInt(other_val.data.integer)
                    else if (other_val.tag == .float)
                        types.number_wrapper.NumberWrapper.initFloat(other_val.data.float)
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitOr(other_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitXor") or std.mem.eql(u8, method_name, "bit_xor")) {
                if (args.items.len == 1) {
                    const other_val = args.items[0];
                    const other_wrapper = if (other_val.tag == .integer)
                        types.number_wrapper.NumberWrapper.initInt(other_val.data.integer)
                    else if (other_val.tag == .float)
                        types.number_wrapper.NumberWrapper.initFloat(other_val.data.float)
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitXor(other_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitNot") or std.mem.eql(u8, method_name, "bit_not")) {
                return Value.initInt(number_wrapper.bitNot());
            } else if (std.mem.eql(u8, method_name, "bitShiftLeft") or std.mem.eql(u8, method_name, "bit_shift_left")) {
                if (args.items.len == 1) {
                    const shift_val = args.items[0];
                    const shift_wrapper = if (shift_val.tag == .integer)
                        types.number_wrapper.NumberWrapper.initInt(shift_val.data.integer)
                    else if (shift_val.tag == .float)
                        types.number_wrapper.NumberWrapper.initFloat(shift_val.data.float)
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitShiftLeft(shift_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitShiftRight") or std.mem.eql(u8, method_name, "bit_shift_right")) {
                if (args.items.len == 1) {
                    const shift_val = args.items[0];
                    const shift_wrapper = if (shift_val.tag == .integer)
                        types.number_wrapper.NumberWrapper.initInt(shift_val.data.integer)
                    else if (shift_val.tag == .float)
                        types.number_wrapper.NumberWrapper.initFloat(shift_val.data.float)
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitShiftRight(shift_wrapper));
                }
            }
        }

        // 处理String类型的内置方法
        if (target_value.tag == .string) {
            if (std.mem.eql(u8, method_name, "toUpper") or std.mem.eql(u8, method_name, "upper")) {
                return builtin_methods.StringMethods.toUpper(self, target_value);
            } else if (std.mem.eql(u8, method_name, "toLower") or std.mem.eql(u8, method_name, "lower")) {
                return builtin_methods.StringMethods.toLower(self, target_value);
            } else if (std.mem.eql(u8, method_name, "trim")) {
                return builtin_methods.StringMethods.trim(self, target_value);
            } else if (std.mem.eql(u8, method_name, "length") or std.mem.eql(u8, method_name, "len")) {
                return builtin_methods.StringMethods.length(self, target_value);
            } else if (std.mem.eql(u8, method_name, "replace")) {
                return builtin_methods.StringMethods.replace(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "substring") or std.mem.eql(u8, method_name, "substr")) {
                return builtin_methods.StringMethods.substring(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "indexOf") or std.mem.eql(u8, method_name, "strpos")) {
                return builtin_methods.StringMethods.indexOf(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "split") or std.mem.eql(u8, method_name, "explode")) {
                return builtin_methods.StringMethods.split(self, target_value, args.items);
            }
        }

        // 处理Array类型的内置方法
        if (target_value.tag == .array) {
            if (std.mem.eql(u8, method_name, "push")) {
                return builtin_methods.ArrayMethods.push(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "pop")) {
                return builtin_methods.ArrayMethods.pop(self, target_value);
            } else if (std.mem.eql(u8, method_name, "shift")) {
                return builtin_methods.ArrayMethods.shift(self, target_value);
            } else if (std.mem.eql(u8, method_name, "unshift")) {
                return builtin_methods.ArrayMethods.unshift(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "merge")) {
                return builtin_methods.ArrayMethods.merge(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "reverse")) {
                return builtin_methods.ArrayMethods.reverse(self, target_value);
            } else if (std.mem.eql(u8, method_name, "keys")) {
                return builtin_methods.ArrayMethods.keys(self, target_value);
            } else if (std.mem.eql(u8, method_name, "values")) {
                return builtin_methods.ArrayMethods.values(self, target_value);
            } else if (std.mem.eql(u8, method_name, "filter")) {
                return builtin_methods.ArrayMethods.filter(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "map")) {
                return builtin_methods.ArrayMethods.map(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "count") or std.mem.eql(u8, method_name, "length")) {
                return builtin_methods.ArrayMethods.count(self, target_value);
            } else if (std.mem.eql(u8, method_name, "isEmpty")) {
                return builtin_methods.ArrayMethods.isEmpty(self, target_value);
            }
        }

        // Special handling for PDO objects
        if (target_value.tag == .object and std.mem.eql(u8, target_value.data.object.data.class.name.data, "PDO")) {
            return self.callPDOMethod(target_value, method_name, args.items);
        }

        if (target_value.tag == .struct_instance) {
            return self.callStructMethod(target_value, method_name, args.items);
        }

        return self.callObjectMethod(target_value, method_name, args.items);
    }

    fn evaluateArrayInit(self: *VM, array_data: anytype) !Value {
        const php_array_value = try Value.initArrayWithManager(&self.memory_manager);
        const php_array = php_array_value.data.array.data;

        // Pre-allocate capacity for better performance
        if (self.optimization_flags.enable_memory_pooling) {
            try php_array.elements.ensureTotalCapacity(array_data.elements.len);
        }

        var auto_index: i64 = 0;
        for (array_data.elements) |item_node_idx| {
            const item_node = self.context.nodes.items[item_node_idx];

            // 检查是否是键值对节点
            if (item_node.tag == .array_pair) {
                // 关联数组：有显式的键
                const key_value = try self.eval(item_node.data.array_pair.key);
                defer self.releaseValue(key_value);

                const value = try self.eval(item_node.data.array_pair.value);

                // 根据键的类型创建ArrayKey
                const key = switch (key_value.tag) {
                    .integer => types.ArrayKey{ .integer = key_value.data.integer },
                    .string => types.ArrayKey{ .string = key_value.data.string.data },
                    else => types.ArrayKey{ .integer = auto_index },
                };

                try php_array.set(self.allocator, key, value);
                self.releaseValue(value);

                // 如果键是整数，更新自动索引
                if (key == .integer and key.integer >= auto_index) {
                    auto_index = key.integer + 1;
                }
            } else {
                // 普通数组：使用自动索引
                const value = try self.eval(item_node_idx);
                const key = types.ArrayKey{ .integer = auto_index };
                try php_array.set(self.allocator, key, value);
                self.releaseValue(value);
                auto_index += 1;
            }
        }

        return php_array_value;
    }

    // Missing evaluation methods implementation
    fn evaluateArrowFunction(self: *VM, arrow_func: anytype) !Value {
        // Process parameters
        const parameters = try self.processParameters(arrow_func.params);

        // Create arrow function with proper parameters
        var arrow_function = types.ArrowFunction.init(self.allocator);
        arrow_function.parameters = parameters;
        // Store body as pointer (Index converted to usize then to pointer)
        arrow_function.body = @ptrFromInt(@as(usize, arrow_func.body));
        arrow_function.is_static = arrow_func.is_static;

        // Auto-capture all variables from current scope
        if (self.call_stack.items.len > 0) {
            const current_frame = &self.call_stack.items[self.call_stack.items.len - 1];
            var locals_iter = current_frame.locals.iterator();
            while (locals_iter.next()) |entry| {
                try arrow_function.autoCaptureVariable(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        const arrow_func_box = try self.memory_manager.allocArrowFunction(arrow_function);
        return Value{ .tag = .arrow_function, .data = .{ .arrow_function = arrow_func_box } };
    }

    fn evaluateUnaryExpression(self: *VM, unary_expr: anytype) !Value {
        // Handle increment/decrement which requires variable assignment
        if (unary_expr.op == .plus_plus or unary_expr.op == .minus_minus) {
            const expr_node = self.context.nodes.items[unary_expr.expr];

            if (expr_node.tag == .variable) {
                const name_id = expr_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];

                // Get current value
                const current_val = if (self.getVariable(name)) |v| v else Value.initInt(0);

                // Increment/Decrement
                var new_val: Value = undefined;
                if (unary_expr.op == .plus_plus) {
                    new_val = try self.incrementValue(current_val);
                } else {
                    new_val = try self.decrementValue(current_val);
                }

                // Update variable (setVariable retains the new value)
                try self.setVariable(name, new_val);

                // For prefix, return new value.
                _ = self.retainValue(new_val);
                return new_val;
            } else {
                std.debug.print("DEBUG: Inc/Dec on non-variable tag={any}\n", .{expr_node.tag});
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Increment/decrement only supports variables", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        }

        const operand = try self.eval(unary_expr.expr);
        defer self.releaseValue(operand);

        return self.evaluateUnaryOp(unary_expr.op, operand);
    }

    fn evaluatePostfixExpression(self: *VM, postfix_expr: anytype) !Value {
        if (postfix_expr.op == .plus_plus or postfix_expr.op == .minus_minus) {
            const expr_node = self.context.nodes.items[postfix_expr.expr];

            if (expr_node.tag == .variable) {
                const name_id = expr_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];

                // Get current value
                const current_val = if (self.getVariable(name)) |v| v else Value.initInt(0);

                // Retain current value because we will return it, and setVariable might release the one in storage
                self.retainValue(current_val);

                // Calculate new value
                var new_val: Value = undefined;
                if (postfix_expr.op == .plus_plus) {
                    new_val = try self.incrementValue(current_val);
                } else {
                    new_val = try self.decrementValue(current_val);
                }

                // Update variable
                try self.setVariable(name, new_val);

                return current_val;
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Increment/decrement only supports variables", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        }

        return Value.initNull();
    }

    fn incrementValue(self: *VM, value: Value) !Value {
        _ = self;
        switch (value.tag) {
            .integer => return Value.initInt(value.data.integer + 1),
            .float => return Value.initFloat(value.data.float + 1.0),
            .string => {
                // Simple alphanumeric increment not fully implemented, fall back to int conversion?
                // PHP does perl-style string increment.
                // For now, let's cast to int/float if numeric, otherwise return as is or error?
                // Simplest: cast to int, increment.
                // Or if it is not numeric, PHP 8 throws error?
                // For "5", it becomes 6.
                // For now assuming numeric string or integer.
                // Let's just try to convert to number.
                if (std.fmt.parseInt(i64, value.data.string.data.data, 10)) |i| {
                    return Value.initInt(i + 1);
                } else |_| {
                    // Fallback
                    return Value.initInt(1);
                }
            },
            .null => return Value.initInt(1),
            .boolean => return Value.initInt(1), // true++ is still true/1? PHP: bool not affected? Wait.
            // PHP: $a = true; $a++; -> $a is still true.
            // But we treat it as number 1?
            else => return Value.initInt(1),
        }
    }

    fn decrementValue(self: *VM, value: Value) !Value {
        _ = self;
        switch (value.tag) {
            .integer => return Value.initInt(value.data.integer - 1),
            .float => return Value.initFloat(value.data.float - 1.0),
            .string => {
                if (std.fmt.parseInt(i64, value.data.string.data.data, 10)) |i| {
                    return Value.initInt(i - 1);
                } else |_| {
                    return Value.initInt(-1);
                }
            },
            .null => return Value.initNull(), // null-- is null
            .boolean => return value, // bool-- no effect
            else => return Value.initInt(0),
        }
    }

    fn evaluateTernaryExpression(self: *VM, ternary_expr: anytype) !Value {
        const condition = try self.eval(ternary_expr.cond);
        defer self.releaseValue(condition);

        const is_truthy = condition.toBool();

        if (is_truthy) {
            if (ternary_expr.then_expr) |then_expr| {
                return self.eval(then_expr);
            } else {
                return condition.retain(); // Elvis operator: condition ?: else_expr
            }
        } else {
            return self.eval(ternary_expr.else_expr);
        }
    }

    fn evaluatePipeExpression(self: *VM, pipe_expr: anytype) !Value {
        const left = try self.eval(pipe_expr.left);
        defer self.releaseValue(left);

        // The right side should be a callable (function, method, closure)
        const right_node = self.context.nodes.items[pipe_expr.right];

        switch (right_node.tag) {
            .function_call => {
                // Modify the function call to include left as first argument
                var args = std.ArrayList(Value){};
                try args.ensureTotalCapacity(self.allocator, right_node.data.function_call.args.len + 1);
                defer {
                    for (args.items) |arg| {
                        self.releaseValue(arg);
                    }
                    args.deinit(self.allocator);
                }

                try args.append(self.allocator, left);

                // Add existing arguments
                for (right_node.data.function_call.args) |arg_idx| {
                    const arg_value = try self.eval(arg_idx);
                    try args.append(self.allocator, arg_value);
                }

                // Call the function with modified arguments
                const func_name_node = self.context.nodes.items[right_node.data.function_call.name];
                if (func_name_node.tag == .variable) {
                    const name_id = func_name_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    return self.callUserFunc(name, args.items);
                }
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid pipe target", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }

        return Value.initNull();
    }

    fn evaluateCloneWithExpression(self: *VM, clone_with_expr: anytype) !Value {
        const object = try self.eval(clone_with_expr.object);
        defer self.releaseValue(object);

        if (object.tag != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Clone with can only be used on objects", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        // Clone the object
        const cloned_object = try object.data.object.data.clone(self.allocator);

        // Apply property modifications
        const properties = try self.eval(clone_with_expr.properties);
        defer self.releaseValue(properties);

        if (properties.tag == .array) {
            var iterator = properties.data.array.data.elements.iterator();
            while (iterator.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;

                switch (key) {
                    .string => |prop_name| {
                        try cloned_object.setProperty(self.allocator, prop_name.data, value);
                    },
                    else => {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid property key in clone with", self.current_file, self.current_line);
                        return self.throwException(exception);
                    },
                }
            }
        }

        return object;
    }

    fn evaluateFunctionDeclaration(self: *VM, func_decl: anytype) !Value {
        const name_id = func_decl.name;
        const name = self.context.string_pool.keys()[name_id];

        var user_function = types.UserFunction.init(try types.PHPString.init(self.allocator, name));
        user_function.parameters = try self.processParameters(func_decl.params);
        user_function.return_type = null;
        user_function.attributes = &[_]types.Attribute{}; // TODO: Convert func_decl.attributes
        user_function.body = @ptrFromInt(func_decl.body);
        user_function.is_variadic = false;
        user_function.min_args = 0;

        // Count required parameters
        for (user_function.parameters) |param| {
            if (param.default_value == null and !param.is_variadic) {
                user_function.min_args += 1;
            }
        }
        user_function.max_args = if (user_function.is_variadic) null else @as(u32, @intCast(user_function.parameters.len));

        const func_box = try self.memory_manager.allocUserFunction(user_function);
        const func_value = Value{ .tag = .user_function, .data = .{ .user_function = func_box } };
        try self.global.set(name, func_value);
        self.releaseValue(func_value);

        return Value.initNull();
    }

    fn evaluateBlock(self: *VM, block: anytype) !Value {
        var last_val = Value.initNull();
        for (block.stmts) |stmt| {
            self.releaseValue(last_val);
            last_val = try self.eval(stmt);
        }
        return last_val;
    }

    fn evaluateIfStatement(self: *VM, if_stmt: anytype) !Value {
        const condition = try self.eval(if_stmt.condition);
        defer self.releaseValue(condition);

        if (condition.toBool()) {
            return self.eval(if_stmt.then_branch);
        } else if (if_stmt.else_branch) |else_branch| {
            return self.eval(else_branch);
        }

        return Value.initNull();
    }

    fn evaluateWhileStatement(self: *VM, while_stmt: anytype) !Value {
        var last_val = Value.initNull();

        loop: while (true) {
            const condition = try self.eval(while_stmt.condition);
            const condition_bool = condition.toBool();
            self.releaseValue(condition);

            if (!condition_bool) break;

            self.releaseValue(last_val);
            last_val = self.eval(while_stmt.body) catch |err| blk: {
                if (err == error.Break) {
                    self.break_level -= 1;
                    if (self.break_level > 0) return error.Break;
                    break :loop;
                }
                if (err == error.Continue) {
                    self.continue_level -= 1;
                    if (self.continue_level > 0) return error.Continue;
                    break :blk Value.initNull();
                }
                return err;
            };
        }

        return last_val;
    }

    fn evaluateForStatement(self: *VM, for_stmt: anytype) !Value {
        // Execute initialization
        if (for_stmt.init) |init_idx| {
            const init_val = try self.eval(init_idx);
            self.releaseValue(init_val);
        }

        var last_val = Value.initNull();

        loop: while (true) {
            // Check condition
            if (for_stmt.condition) |cond_idx| {
                const condition = try self.eval(cond_idx);
                const condition_bool = condition.toBool();
                self.releaseValue(condition);

                if (!condition_bool) break;
            }

            // Execute body
            self.releaseValue(last_val);
            last_val = self.eval(for_stmt.body) catch |err| blk: {
                if (err == error.Break) {
                    self.break_level -= 1;
                    if (self.break_level > 0) return error.Break;
                    break :loop;
                }
                if (err == error.Continue) {
                    self.continue_level -= 1;
                    if (self.continue_level > 0) return error.Continue;
                    break :blk Value.initNull();
                }
                return err;
            };
            // Fallthrough for Continue or normal execution: execute loop expression

            // Execute loop expression (increment/decrement)
            if (for_stmt.loop) |loop_idx| {
                const loop_val = try self.eval(loop_idx);
                self.releaseValue(loop_val);
            }
        }

        return last_val;
    }

    fn evaluateForRangeStatement(self: *VM, range_stmt: anytype) !Value {
        const count_val = try self.eval(range_stmt.count);
        defer self.releaseValue(count_val);

        var count: i64 = 0;
        switch (count_val.tag) {
            .integer => count = count_val.data.integer,
            .float => count = @intFromFloat(count_val.data.float),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Range count must be a number", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }

        var last_val = Value.initNull();
        var i: i64 = 0;
        loop: while (i < count) : (i += 1) {
            // Set variable if present
            if (range_stmt.variable) |var_idx| {
                const var_node = self.context.nodes.items[var_idx];
                if (var_node.tag == .variable) {
                    const name_id = var_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    try self.setVariable(name, Value.initInt(i));
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Range variable must be a variable", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            }

            self.releaseValue(last_val);

            last_val = self.eval(range_stmt.body) catch |err| blk: {
                if (err == error.Break) {
                    self.break_level -= 1;
                    if (self.break_level > 0) return error.Break;
                    break :loop;
                }
                if (err == error.Continue) {
                    self.continue_level -= 1;
                    if (self.continue_level > 0) return error.Continue;
                    break :blk Value.initNull();
                }
                return err;
            };
        }

        return last_val;
    }

    fn evaluateForeachStatement(self: *VM, foreach_stmt: anytype) !Value {
        const iterable = try self.eval(foreach_stmt.iterable);
        defer self.releaseValue(iterable);

        if (iterable.tag != .array) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Foreach can only iterate over arrays", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        var last_val = Value.initNull();
        var iterator = iterable.data.array.data.elements.iterator();

        loop: while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Set key variable if specified
            if (foreach_stmt.key) |key_idx| {
                const key_node = self.context.nodes.items[key_idx];
                if (key_node.tag == .variable) {
                    const key_name_id = key_node.data.variable.name;
                    const key_name = self.context.string_pool.keys()[key_name_id];
                    const key_value = switch (key) {
                        .integer => |iv| Value.initInt(iv),
                        .string => |s| try Value.initStringWithManager(&self.memory_manager, s.data),
                    };
                    try self.setVariable(key_name, key_value);
                    self.releaseValue(key_value);
                }
            }

            // Set value variable
            const value_node = self.context.nodes.items[foreach_stmt.value];
            if (value_node.tag == .variable) {
                const value_name_id = value_node.data.variable.name;
                const value_name = self.context.string_pool.keys()[value_name_id];
                try self.setVariable(value_name, value);
            }

            // Execute body
            self.releaseValue(last_val);
            last_val = self.eval(foreach_stmt.body) catch |err| blk: {
                if (err == error.Break) {
                    self.break_level -= 1;
                    if (self.break_level > 0) return error.Break;
                    break :loop;
                }
                if (err == error.Continue) {
                    self.continue_level -= 1;
                    if (self.continue_level > 0) return error.Continue;
                    break :blk Value.initNull();
                }
                return err;
            };
        }

        return last_val;
    }

    fn evaluateReturnStatement(self: *VM, return_stmt: anytype) !Value {
        if (return_stmt.expr) |expr| {
            // Release previous return value if any (shouldn't happen in normal flow but safe to do)
            if (self.return_value) |val| {
                self.releaseValue(val);
            }
            self.return_value = try self.eval(expr);
        } else {
            if (self.return_value) |val| {
                self.releaseValue(val);
            }
            self.return_value = Value.initNull();
        }
        return error.Return;
    }

    fn evaluateBreakStatement(self: *VM, break_stmt: anytype) !Value {
        if (break_stmt.level) |level_idx| {
            const level_val = try self.eval(level_idx);
            defer self.releaseValue(level_val);
            if (level_val.tag == .integer) {
                self.break_level = @intCast(level_val.data.integer);
            } else {
                self.break_level = 1;
            }
        } else {
            self.break_level = 1;
        }
        return error.Break;
    }

    fn evaluateContinueStatement(self: *VM, continue_stmt: anytype) !Value {
        if (continue_stmt.level) |level_idx| {
            const level_val = try self.eval(level_idx);
            defer self.releaseValue(level_val);
            if (level_val.tag == .integer) {
                self.continue_level = @intCast(level_val.data.integer);
            } else {
                self.continue_level = 1;
            }
        } else {
            self.continue_level = 1;
        }
        return error.Continue;
    }

    fn evaluateBinaryOp(self: *VM, op: Token.Tag, left: Value, right: Value) !Value {
        switch (op) {
            .plus => return self.addValues(left, right),
            .minus => return self.subtractValues(left, right),
            .asterisk => return self.multiplyValues(left, right),
            .slash => return self.divideValues(left, right),
            .percent => return self.moduloValues(left, right),
            .equal_equal => {
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initBool(left.data.integer == right.data.integer);
                } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
                    const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
                    const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
                    return Value.initBool(left_float == right_float);
                } else if (left.tag == .string and right.tag == .string) {
                    return Value.initBool(std.mem.eql(u8, left.data.string.data.data, right.data.string.data.data));
                } else if (left.tag == .boolean and right.tag == .boolean) {
                    return Value.initBool(left.data.boolean == right.data.boolean);
                } else if (left.tag == .null and right.tag == .null) {
                    return Value.initBool(true);
                }
                return Value.initBool(false);
            },
            .equal_equal_equal => {
                if (left.tag != right.tag) return Value.initBool(false);
                switch (left.tag) {
                    .null => return Value.initBool(true),
                    .boolean => return Value.initBool(left.data.boolean == right.data.boolean),
                    .integer => return Value.initBool(left.data.integer == right.data.integer),
                    .float => return Value.initBool(left.data.float == right.data.float),
                    .string => return Value.initBool(std.mem.eql(u8, left.data.string.data.data, right.data.string.data.data)),
                    .array => return Value.initBool(left.data.array == right.data.array),
                    .object => return Value.initBool(left.data.object == right.data.object),
                    else => return Value.initBool(false),
                }
            },
            .bang_equal => {
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initBool(left.data.integer != right.data.integer);
                } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
                    const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
                    const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
                    return Value.initBool(left_float != right_float);
                } else if (left.tag == .string and right.tag == .string) {
                    return Value.initBool(!std.mem.eql(u8, left.data.string.data.data, right.data.string.data.data));
                } else if (left.tag == .boolean and right.tag == .boolean) {
                    return Value.initBool(left.data.boolean != right.data.boolean);
                } else if (left.tag == .null and right.tag == .null) {
                    return Value.initBool(false);
                }
                return Value.initBool(true);
            },
            .bang_equal_equal => {
                if (left.tag != right.tag) return Value.initBool(true);
                switch (left.tag) {
                    .null => return Value.initBool(false),
                    .boolean => return Value.initBool(left.data.boolean != right.data.boolean),
                    .integer => return Value.initBool(left.data.integer != right.data.integer),
                    .float => return Value.initBool(left.data.float != right.data.float),
                    .string => return Value.initBool(!std.mem.eql(u8, left.data.string.data.data, right.data.string.data.data)),
                    .array => return Value.initBool(left.data.array != right.data.array),
                    .object => return Value.initBool(left.data.object != right.data.object),
                    else => return Value.initBool(true),
                }
            },
            .less => {
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initBool(left.data.integer < right.data.integer);
                } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
                    const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
                    const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
                    return Value.initBool(left_float < right_float);
                }
                return Value.initBool(false);
            },
            .less_equal => {
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initBool(left.data.integer <= right.data.integer);
                } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
                    const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
                    const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
                    return Value.initBool(left_float <= right_float);
                }
                return Value.initBool(false);
            },
            .greater => {
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initBool(left.data.integer > right.data.integer);
                } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
                    const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
                    const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
                    return Value.initBool(left_float > right_float);
                }
                return Value.initBool(false);
            },
            .greater_equal => {
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initBool(left.data.integer >= right.data.integer);
                } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
                    const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
                    const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
                    return Value.initBool(left_float >= right_float);
                }
                return Value.initBool(false);
            },
            .double_ampersand => return Value.initBool(left.toBool() and right.toBool()),
            .double_pipe => return Value.initBool(left.toBool() or right.toBool()),
            .double_question => {
                if (left.tag != .null) return left.retain();
                return right.retain();
            },
            .dot => return self.concatenateValues(left, right),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Unsupported binary operator", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }
    }

    fn evaluateUnaryOp(self: *VM, op: Token.Tag, operand: Value) !Value {
        switch (op) {
            .minus => return self.negateValue(operand),
            .bang => return Value.initBool(!operand.toBool()),
            .plus => return operand, // Unary plus
            .ampersand => return operand, // Reference operator (treat as value for now to prevent crash)
            .k_clone => {
                if (operand.tag != .object) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "__clone method called on non-object", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
                const cloned_obj = try operand.data.object.data.clone(self.allocator);
                const cloned_val = try Value.initObjectWithObject(&self.memory_manager, cloned_obj);

                if (cloned_obj.class.hasMethod("__clone")) {
                    const result = try self.callObjectMethod(cloned_val, "__clone", &.{});
                    defer self.releaseValue(result);
                }

                return cloned_val;
            },
            else => {
                std.debug.print("Error: Unsupported unary operator: {any}\n", .{op});
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Unsupported unary operator", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }
    }

    fn addValues(self: *VM, left: Value, right: Value) !Value {
        if (left.tag == .integer and right.tag == .integer) {
            return Value.initInt(left.data.integer + right.data.integer);
        } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
            const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
            const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
            return Value.initFloat(left_float + right_float);
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for addition", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn subtractValues(self: *VM, left: Value, right: Value) !Value {
        if (left.tag == .integer and right.tag == .integer) {
            return Value.initInt(left.data.integer - right.data.integer);
        } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
            const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
            const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
            return Value.initFloat(left_float - right_float);
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for subtraction", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn multiplyValues(self: *VM, left: Value, right: Value) !Value {
        if (left.tag == .integer and right.tag == .integer) {
            return Value.initInt(left.data.integer * right.data.integer);
        } else if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
            const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
            const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));
            return Value.initFloat(left_float * right_float);
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for multiplication", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn divideValues(self: *VM, left: Value, right: Value) !Value {
        if ((left.tag == .integer or left.tag == .float) and (right.tag == .integer or right.tag == .float)) {
            const left_float = if (left.tag == .float) left.data.float else @as(f64, @floatFromInt(left.data.integer));
            const right_float = if (right.tag == .float) right.data.float else @as(f64, @floatFromInt(right.data.integer));

            if (right_float == 0.0) {
                const exception = try ExceptionFactory.createDivisionByZeroError(self.allocator, self.current_file, self.current_line);
                return self.throwException(exception);
            }

            return Value.initFloat(left_float / right_float);
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for division", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn moduloValues(self: *VM, left: Value, right: Value) !Value {
        if (left.tag == .integer and right.tag == .integer) {
            if (right.data.integer == 0) {
                const exception = try ExceptionFactory.createDivisionByZeroError(self.allocator, self.current_file, self.current_line);
                return self.throwException(exception);
            }
            return Value.initInt(@mod(left.data.integer, right.data.integer));
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for modulo", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn concatenateValues(self: *VM, left: Value, right: Value) !Value {
        const left_res = try self.valueToString(left);
        defer if (left_res.needs_free) self.allocator.free(left_res.str);

        const right_res = try self.valueToString(right);
        defer if (right_res.needs_free) self.allocator.free(right_res.str);

        const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_res.str, right_res.str });
        defer self.allocator.free(result);
        return Value.initStringWithManager(&self.memory_manager, result);
    }

    fn negateValue(self: *VM, operand: Value) !Value {
        switch (operand.tag) {
            .integer => return Value.initInt(-operand.data.integer),
            .float => return Value.initFloat(-operand.data.float),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operand for negation", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }
    }
    fn evaluateInterfaceDeclaration(self: *VM, interface_data: anytype) !Value {
        const interface_name = self.context.string_pool.keys()[interface_data.name];
        const php_interface_name = try types.PHPString.init(self.allocator, interface_name);
        defer php_interface_name.release(self.allocator);

        // Create new interface
        var php_interface = types.PHPInterface.init(self.allocator, php_interface_name);

        // Process interface members
        for (interface_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .method_decl => {
                    try self.processInterfaceMethodDeclaration(&php_interface, member_node.data.method_decl);
                },
                .const_decl => {
                    try self.processInterfaceConstantDeclaration(&php_interface, member_node.data.const_decl);
                },
                else => {
                    // Skip unsupported member types
                },
            }
        }

        // Register the interface
        const interface_ptr = try self.allocator.create(types.PHPInterface);
        interface_ptr.* = php_interface;
        try self.defineInterface(interface_name, interface_ptr);

        return Value.initNull();
    }

    fn processInterfaceMethodDeclaration(self: *VM, interface_obj: *types.PHPInterface, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];
        const php_method_name = try types.PHPString.init(self.allocator, method_name);
        defer php_method_name.release(self.allocator);

        var method = types.Method.init(php_method_name);

        // Interface methods are public and abstract
        method.modifiers = .{
            .visibility = .public,
            .is_abstract = true,
            .is_static = method_data.modifiers.is_static,
        };

        method.parameters = try self.processParameters(method_data.params);
        try interface_obj.methods.put(method_name, method);
    }

    fn processInterfaceConstantDeclaration(self: *VM, interface_obj: *types.PHPInterface, const_data: anytype) !void {
        const const_name = self.context.string_pool.keys()[const_data.name];
        const const_value = try self.eval(const_data.value);
        try interface_obj.constants.put(const_name, const_value);
    }

    fn checkInterfaceImplementation(self: *VM, class: *types.PHPClass, interface: *types.PHPInterface) !void {
        var it = interface.methods.iterator();
        while (it.next()) |entry| {
            const method_name = entry.key_ptr.*;
            // Check if class has this method (or inherits it)
            if (!class.hasMethod(method_name)) {
                const msg = try std.fmt.allocPrint(self.allocator, "Class {s} contains 1 abstract method and must therefore be declared abstract or implement the remaining methods ({s}::{s})", .{ class.name.data, interface.name.data, method_name });
                defer self.allocator.free(msg);
                const exception = try ExceptionFactory.createTypeError(self.allocator, msg, self.current_file, self.current_line);
                _ = try self.throwException(exception);
                return error.UncaughtException;
            }
        }

        for (interface.extends) |parent_interface| {
            try self.checkInterfaceImplementation(class, parent_interface);
        }
    }

    fn evaluateTraitDeclaration(self: *VM, trait_data: anytype) !Value {
        const trait_name = self.context.string_pool.keys()[trait_data.name];
        const php_trait_name = try types.PHPString.init(self.allocator, trait_name);
        defer php_trait_name.release(self.allocator);

        var php_trait = types.PHPTrait.init(self.allocator, php_trait_name);

        // Process trait members
        for (trait_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .method_decl => {
                    try self.processTraitMethodDeclaration(&php_trait, member_node.data.method_decl);
                },
                .property_decl => {
                    try self.processTraitPropertyDeclaration(&php_trait, member_node.data.property_decl);
                },
                else => {},
            }
        }

        // Register the trait
        const trait_ptr = try self.allocator.create(types.PHPTrait);
        trait_ptr.* = php_trait;
        try self.defineTrait(trait_name, trait_ptr);

        return Value.initNull();
    }

    fn processTraitMethodDeclaration(self: *VM, trait_obj: *types.PHPTrait, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];
        const php_method_name = try types.PHPString.init(self.allocator, method_name);
        defer php_method_name.release(self.allocator);

        var method = types.Method.init(php_method_name);
        method.modifiers = .{
            .visibility = if (method_data.modifiers.is_public) .public else if (method_data.modifiers.is_protected) .protected else if (method_data.modifiers.is_private) .private else .public,
            .is_static = method_data.modifiers.is_static,
            .is_final = method_data.modifiers.is_final,
            .is_abstract = method_data.modifiers.is_abstract,
        };
        method.parameters = try self.processParameters(method_data.params);
        method.body = if (method_data.body) |body_idx| @ptrFromInt(@as(usize, body_idx)) else null;
        try trait_obj.methods.put(method_name, method);
    }

    fn processTraitPropertyDeclaration(self: *VM, trait_obj: *types.PHPTrait, property_data: anytype) !void {
        const prop_name = self.context.string_pool.keys()[property_data.name];
        const php_prop_name = try types.PHPString.init(self.allocator, prop_name);
        defer php_prop_name.release(self.allocator);

        var property = types.Property.init(php_prop_name);
        property.modifiers = .{
            .visibility = if (property_data.modifiers.is_public) .public else if (property_data.modifiers.is_protected) .protected else if (property_data.modifiers.is_private) .private else .public,
            .is_static = property_data.modifiers.is_static,
            .is_readonly = property_data.modifiers.is_readonly,
        };
        if (property_data.default_value) |default_idx| {
            property.default_value = try self.eval(default_idx);
        }
        try trait_obj.properties.put(prop_name, property);
    }

    fn processTraitUse(self: *VM, class: *types.PHPClass, trait_use_data: anytype) !void {
        // Process each trait in the use statement
        for (trait_use_data.traits) |trait_idx| {
            const trait_node = self.context.nodes.items[trait_idx];
            if (trait_node.tag == .named_type) {
                const trait_name = self.context.string_pool.keys()[trait_node.data.named_type.name];
                if (self.getTrait(trait_name)) |trait_obj| {
                    // Mix in trait methods (class methods take precedence)
                    var method_iter = trait_obj.methods.iterator();
                    while (method_iter.next()) |entry| {
                        const method_name = entry.key_ptr.*;
                        // Only add if class doesn't already have this method
                        if (!class.methods.contains(method_name)) {
                            var method_copy = entry.value_ptr.*;
                            // Retain the method name reference
                            method_copy.name.retain();

                            // Allocate new parameter array and retain parameter names
                            if (method_copy.parameters.len > 0) {
                                const new_params = try self.allocator.alloc(types.Method.Parameter, method_copy.parameters.len);
                                for (method_copy.parameters, 0..) |param, i| {
                                    new_params[i] = param;
                                    new_params[i].name.retain();
                                }
                                method_copy.parameters = new_params;
                            }

                            try class.methods.put(method_name, method_copy);
                        }
                    }

                    // Mix in trait properties
                    var prop_iter = trait_obj.properties.iterator();
                    while (prop_iter.next()) |entry| {
                        const prop_name = entry.key_ptr.*;
                        if (!class.properties.contains(prop_name)) {
                            var prop_copy = entry.value_ptr.*;
                            // Retain the property name reference
                            prop_copy.name.retain();
                            // Retain default value if present
                            if (prop_copy.default_value) |val| {
                                switch (val.tag) {
                                    .string => _ = val.data.string.retain(),
                                    .array => _ = val.data.array.retain(),
                                    .object => _ = val.data.object.retain(),
                                    else => {},
                                }
                            }
                            try class.properties.put(prop_name, prop_copy);
                        }
                    }
                }
            }
        }
    }

    fn evaluateClassDeclaration(self: *VM, class_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        const class_name = self.context.string_pool.keys()[class_data.name];
        const php_class_name = try types.PHPString.init(self.allocator, class_name);
        defer php_class_name.release(self.allocator);

        // Create new class
        var php_class = types.PHPClass.init(self.allocator, php_class_name);

        // Set class modifiers
        php_class.modifiers = .{
            .is_abstract = class_data.modifiers.is_abstract,
            .is_final = class_data.modifiers.is_final,
            .is_readonly = class_data.modifiers.is_readonly,
        };

        // Process extends clause
        if (class_data.extends) |extends_idx| {
            const extends_node = self.context.nodes.items[extends_idx];
            if (extends_node.tag == .variable) {
                const parent_name = self.context.string_pool.keys()[extends_node.data.variable.name];
                if (self.getClass(parent_name)) |parent_class| {
                    php_class.parent = parent_class;
                } else {
                    const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, parent_name, self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            }
        }

        // Process implements clause
        if (class_data.implements.len > 0) {
            const interfaces = try self.allocator.alloc(*types.PHPInterface, class_data.implements.len);
            php_class.interfaces = interfaces;

            for (class_data.implements, 0..) |interface_idx, i| {
                const interface_node = self.context.nodes.items[interface_idx];
                if (interface_node.tag == .variable) {
                    const interface_name = self.context.string_pool.keys()[interface_node.data.variable.name];
                    if (self.getInterface(interface_name)) |interface_obj| {
                        interfaces[i] = interface_obj;
                    } else {
                        php_class.deinit(self.allocator);
                        const msg = try std.fmt.allocPrint(self.allocator, "Interface '{s}' not found", .{interface_name});
                        defer self.allocator.free(msg);
                        const exception = try ExceptionFactory.createTypeError(self.allocator, msg, self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else {
                    php_class.deinit(self.allocator);
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid interface name", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            }
        }

        // Process class members
        for (class_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .trait_use => {
                    try self.processTraitUse(&php_class, member_node.data.trait_use);
                },
                .method_decl => {
                    try self.processMethodDeclaration(&php_class, member_node.data.method_decl);
                },
                .property_decl => {
                    try self.processPropertyDeclaration(&php_class, member_node.data.property_decl);
                },
                .const_decl => {
                    try self.processConstantDeclaration(&php_class, member_node.data.const_decl);
                },
                else => {
                    // Skip unsupported member types
                },
            }
        }

        // Abstract method check - performed on &php_class before allocation/registration
        if (!php_class.modifiers.is_abstract) {
            // Check interface methods
            for (php_class.interfaces) |interface_obj| {
                self.checkInterfaceImplementation(&php_class, interface_obj) catch |err| {
                    php_class.deinit(self.allocator);
                    return err;
                };
            }

            var curr = php_class.parent;
            while (curr) |parent| {
                var it = parent.methods.iterator();
                while (it.next()) |entry| {
                    const method = entry.value_ptr;
                    if (method.modifiers.is_abstract) {
                        if (php_class.getMethod(entry.key_ptr.*)) |resolved_method| {
                            if (resolved_method.modifiers.is_abstract) {
                                // Error found: Clean up php_class before throwing
                                php_class.deinit(self.allocator);
                                const exception = try ExceptionFactory.createTypeError(self.allocator, "Class must implement abstract method", self.current_file, self.current_line);
                                return self.throwException(exception);
                            }
                        } else {
                            // Abstract method not implemented (not found)
                            php_class.deinit(self.allocator);
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Class must implement abstract method", self.current_file, self.current_line);
                            return self.throwException(exception);
                        }
                    }
                }
                curr = parent.parent;
            }
        }

        // Register the class
        const class_ptr = try self.allocator.create(types.PHPClass);
        class_ptr.* = php_class;

        // Define class (takes ownership of class_ptr, but if it fails we must handle it)
        self.defineClass(class_name, class_ptr) catch |err| {
            class_ptr.deinit(self.allocator);
            self.allocator.destroy(class_ptr);
            return err;
        };

        return Value.initNull();
    }

    fn processMethodDeclaration(self: *VM, class: *types.PHPClass, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];

        // Check if parent has final method with same name
        if (class.parent) |parent| {
            if (parent.getMethod(method_name)) |parent_method| {
                if (parent_method.modifiers.is_final) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot override final method", self.current_file, self.current_line);
                    _ = try self.throwException(exception);
                    return;
                }
            }
        }

        const php_method_name = try types.PHPString.init(self.allocator, method_name);
        defer php_method_name.release(self.allocator);

        // Create method
        var method = types.Method.init(php_method_name);

        // Set method modifiers
        method.modifiers = .{
            .is_static = method_data.modifiers.is_static,
            .is_final = method_data.modifiers.is_final,
            .is_abstract = method_data.modifiers.is_abstract,
            .visibility = if (method_data.modifiers.is_public) .public else if (method_data.modifiers.is_protected) .protected else .private,
        };

        // Process parameters
        method.parameters = try self.processParameters(method_data.params);

        // Set method body
        if (method_data.body) |body_idx| {
            method.body = @ptrFromInt(body_idx);
        }

        // Add method to class (simplified - just store in methods map)
        try class.methods.put(method_name, method);
    }

    fn addClassProperty(self: *VM, class: *types.PHPClass, name: []const u8, visibility: types.Property.Visibility, default_value: ?Value) !void {
        const prop_name = try types.PHPString.init(self.allocator, name);
        var property = types.Property.init(prop_name);
        property.modifiers.visibility = visibility;
        property.default_value = default_value;
        try class.properties.put(name, property);
    }

    fn processPropertyDeclaration(self: *VM, class: *types.PHPClass, property_data: anytype) !void {
        const property_name = self.context.string_pool.keys()[property_data.name];

        // Create property
        const property_name_str = try types.PHPString.init(self.allocator, property_name);
        defer property_name_str.release(self.allocator);
        var property = types.Property.init(property_name_str);

        // Set property modifiers
        property.modifiers = .{
            .is_static = property_data.modifiers.is_static,
            .is_readonly = property_data.modifiers.is_readonly,
            .visibility = if (property_data.modifiers.is_public) .public else if (property_data.modifiers.is_protected) .protected else .private,
        };

        // Set default value if present
        if (property_data.default_value) |default_idx| {
            property.default_value = try self.eval(default_idx);
        }

        // Process property hooks if present
        for (property_data.hooks) |hook_idx| {
            const hook_node = self.context.nodes.items[hook_idx];
            if (hook_node.tag == .property_hook) {
                const hook_data = hook_node.data.property_hook;
                const hook_name = self.context.string_pool.keys()[hook_data.name];

                if (std.mem.eql(u8, hook_name, "get")) {
                    // Property hooks not implemented yet - skip
                } else if (std.mem.eql(u8, hook_name, "set")) {
                    // Property hooks not implemented yet - skip
                }
            }
        }

        // Add property to class (simplified - just store in properties map)
        try class.properties.put(property_name, property);
    }

    fn processConstantDeclaration(self: *VM, class: *types.PHPClass, const_data: anytype) !void {
        const const_name = self.context.string_pool.keys()[const_data.name];
        const const_value = try self.eval(const_data.value);

        // Add constant to class (simplified - skip for now)
        _ = class;
        _ = const_name;
        _ = const_value;
    }

    fn evaluateStructDeclaration(self: *VM, struct_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        const struct_name = self.context.string_pool.keys()[struct_data.name];
        const php_struct_name = try types.PHPString.init(self.allocator, struct_name);

        // Create new struct
        var php_struct = types.PHPStruct.init(self.allocator, php_struct_name);

        // Process struct members
        for (struct_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .method_decl => {
                    try self.processStructMethodDeclaration(&php_struct, member_node.data.method_decl);
                },
                .property_decl => {
                    try self.processStructFieldDeclaration(&php_struct, member_node.data.property_decl);
                },
                else => {
                    // Skip unsupported member types
                },
            }
        }

        // Register the struct
        const struct_ptr = try self.allocator.create(types.PHPStruct);
        struct_ptr.* = php_struct;
        try self.defineStruct(struct_name, struct_ptr);

        return Value.initNull();
    }

    fn evaluateStructInstantiation(self: *VM, struct_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        // Get struct type
        const struct_type_node = self.context.nodes.items[struct_data.struct_type];
        if (struct_type_node.tag != .variable) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid struct type", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const struct_name = self.context.string_pool.keys()[struct_type_node.data.variable.name];
        const struct_type = self.getStruct(struct_name) orelse {
            const exception = try ExceptionFactory.createUndefinedStructError(self.allocator, struct_name, self.current_file, self.current_line);
            return self.throwException(exception);
        };

        // Create struct instance
        const struct_instance = try self.allocator.create(types.StructInstance);
        struct_instance.* = types.StructInstance.init(self.allocator, struct_type);

        // Evaluate constructor arguments
        var args = std.ArrayList(Value){};
        try args.ensureTotalCapacity(self.allocator, struct_data.args.len);
        defer {
            for (args.items) |arg| {
                self.releaseValue(arg);
            }
            args.deinit(self.allocator);
        }

        for (struct_data.args) |arg_idx| {
            const arg_value = try self.eval(arg_idx);
            try args.append(self.allocator, arg_value);
        }

        // Initialize struct fields with default values
        try self.initializeStructFields(struct_instance, struct_type);

        // Create boxed value for the instance
        const box = try self.allocator.create(types.gc.Box(*types.StructInstance));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = struct_instance,
        };
        const instance_value = Value{ .tag = .struct_instance, .data = .{ .struct_instance = box } };

        // Call constructor if it exists
        if (struct_type.hasMethod("__construct")) {
            const ctor_result = try struct_instance.callMethod(self, instance_value, "__construct", args.items);
            self.releaseValue(ctor_result);
        }

        return instance_value;
    }

    fn processStructMethodDeclaration(self: *VM, struct_type: *types.PHPStruct, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];
        const php_method_name = try types.PHPString.init(self.allocator, method_name);

        // Create method
        var method = types.Method.init(php_method_name);

        // Set method modifiers
        method.modifiers = .{
            .is_static = method_data.modifiers.is_static,
            .is_final = method_data.modifiers.is_final,
            .is_abstract = method_data.modifiers.is_abstract,
            .visibility = if (method_data.modifiers.is_public) .public else if (method_data.modifiers.is_protected) .protected else .private,
        };

        // Process parameters
        method.parameters = try self.processParameters(method_data.params);

        // Set method body
        if (method_data.body) |body_idx| {
            method.body = @ptrFromInt(body_idx);
        }

        // Add method to struct
        try struct_type.addMethod(method);
    }

    fn processStructFieldDeclaration(self: *VM, struct_type: *types.PHPStruct, field_data: anytype) !void {
        const field_name = self.context.string_pool.keys()[field_data.name];
        const php_field_name = try types.PHPString.init(self.allocator, field_name);

        // Create field
        var field = types.PHPStruct.StructField{
            .name = php_field_name,
            .type = null, // Would process type information here
            .default_value = null,
            .modifiers = .{
                .is_public = field_data.modifiers.is_public,
                .is_protected = field_data.modifiers.is_protected,
                .is_private = field_data.modifiers.is_private,
                .is_readonly = field_data.modifiers.is_readonly,
            },
            .offset = 0, // Would calculate proper offset
        };

        // Set default value if present
        if (field_data.default_value) |default_idx| {
            field.default_value = try self.eval(default_idx);
        }

        // Add field to struct
        try struct_type.addField(field);
    }

    fn initializeStructFields(self: *VM, instance: *types.StructInstance, struct_type: *types.PHPStruct) !void {
        var field_iter = struct_type.fields.iterator();
        while (field_iter.next()) |entry| {
            const field = entry.value_ptr.*;
            const field_name = field.name.data;

            if (field.default_value) |default_val| {
                try instance.setField(self.allocator, field_name, default_val);
            } else {
                // Initialize with null if no default value
                try instance.setField(self.allocator, field_name, Value.initNull());
            }
        }
    }

    pub fn defineStruct(self: *VM, name: []const u8, struct_type: *types.PHPStruct) !void {
        try self.structs.put(name, struct_type);
    }

    pub fn getStruct(self: *VM, name: []const u8) ?*types.PHPStruct {
        return self.structs.get(name);
    }

    fn evaluateTryStatement(self: *VM, try_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        // Enter try-catch context
        try self.enterTryCatch();
        defer self.exitTryCatch();

        var result = Value.initNull();
        var exception_caught = false;

        // Execute try block
        result = self.eval(try_data.body) catch |err| switch (err) {
            // Check if it's an exception we can handle
            error.UncaughtException => blk: {
                exception_caught = true;

                // Try to match with catch clauses
                for (try_data.catch_clauses) |catch_idx| {
                    const catch_node = self.context.nodes.items[catch_idx];
                    if (catch_node.tag == .catch_clause) {
                        const catch_data = catch_node.data.catch_clause;

                        // For now, catch all exceptions (simplified)
                        // In a real implementation, would check exception type matching

                        // Bind exception to variable if specified
                        if (catch_data.variable) |var_idx| {
                            const var_node = self.context.nodes.items[var_idx];
                            if (var_node.tag == .variable) {
                                const var_name = self.context.string_pool.keys()[var_node.data.variable.name];
                                // Would bind the actual exception object here
                                try self.global.set(var_name, Value.initNull());
                            }
                        }

                        // Execute catch block
                        result = try self.eval(catch_data.body);
                        exception_caught = true;
                        break;
                    }
                }

                if (!exception_caught) {
                    return err; // Re-throw if no catch clause handled it
                }

                break :blk result;
            },
            else => return err, // Re-throw non-exception errors
        };

        // Execute finally block if present
        if (try_data.finally_clause) |finally_idx| {
            const finally_node = self.context.nodes.items[finally_idx];
            if (finally_node.tag == .finally_clause) {
                const finally_data = finally_node.data.finally_clause;
                _ = try self.eval(finally_data.body);
            }
        }

        return result;
    }

    fn evaluateThrowStatement(self: *VM, throw_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        // Evaluate the expression to throw
        const exception_value = try self.eval(throw_data.expression);
        defer self.releaseValue(exception_value);

        // Create exception based on the value
        const exception = switch (exception_value.tag) {
            .object => blk: {
                // If it's already an exception object, use it
                const object = exception_value.data.object.data;
                // Simplified check - just check if it has a message property
                if (object.properties.contains("message")) {
                    // Convert object to PHPException
                    const message_prop = object.getProperty("message") catch (try Value.initString(self.allocator, "Exception"));
                    const message_str = switch (message_prop.tag) {
                        .string => message_prop.data.string.data.data,
                        else => "Exception",
                    };

                    break :blk try ExceptionFactory.createTypeError(self.allocator, message_str, self.current_file, self.current_line);
                } else {
                    break :blk try ExceptionFactory.createTypeError(self.allocator, "Can only throw objects that implement Throwable", self.current_file, self.current_line);
                }
            },
            .string => blk: {
                // Throw string as exception message
                const message = exception_value.data.string.data.data;
                break :blk try ExceptionFactory.createTypeError(self.allocator, message, self.current_file, self.current_line);
            },
            else => blk: {
                break :blk try ExceptionFactory.createTypeError(self.allocator, "Can only throw objects that implement Throwable", self.current_file, self.current_line);
            },
        };

        return self.throwException(exception);
    }

    fn evaluateClosureCreation(self: *VM, closure_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        // Create user function for the closure
        const closure_name = try types.PHPString.init(self.allocator, "closure");
        var user_function = types.UserFunction.init(closure_name);

        // Process parameters
        user_function.parameters = try self.processParameters(closure_data.params);

        var min_args: u32 = 0;
        var is_variadic = false;

        for (user_function.parameters) |param| {
            if (param.is_variadic) {
                is_variadic = true;
            }
            if (param.default_value == null and !param.is_variadic) {
                min_args += 1;
            }
        }

        // 设置max_args：variadic函数为null（无限制），否则为参数数量
        const max_args: ?u32 = if (is_variadic) null else @as(u32, @intCast(user_function.parameters.len));

        user_function.body = @ptrFromInt(closure_data.body);
        user_function.is_variadic = is_variadic;
        user_function.min_args = min_args;
        user_function.max_args = max_args;

        // Process capture list
        var captured_vars_list = std.ArrayList(CapturedVar){};
        try captured_vars_list.ensureTotalCapacity(self.allocator, closure_data.captures.len);
        defer captured_vars_list.deinit(self.allocator);

        for (closure_data.captures) |capture_idx| {
            const capture_node = self.context.nodes.items[capture_idx];
            var var_name: []const u8 = undefined;
            var should_capture = false;

            if (capture_node.tag == .variable) {
                var_name = self.context.string_pool.keys()[capture_node.data.variable.name];
                should_capture = true;
            } else if (capture_node.tag == .unary_expr and capture_node.data.unary_expr.op == .ampersand) {
                // Reference capture: use (&$var)
                // Peel off the ampersand and get the variable
                const expr_idx = capture_node.data.unary_expr.expr;
                const expr_node = self.context.nodes.items[expr_idx];
                if (expr_node.tag == .variable) {
                    var_name = self.context.string_pool.keys()[expr_node.data.variable.name];
                    should_capture = true;
                }
            }

            if (should_capture) {
                // Only capture if variable exists in current scope
                if (self.getVariable(var_name)) |var_value| {
                    try captured_vars_list.append(self.allocator, .{ .name = var_name, .value = var_value });
                }
                // If variable doesn't exist, skip it
            }
        }

        return self.createClosure(user_function, captured_vars_list.items);
    }

    fn evaluateStaticMethodCall(self: *VM, static_call_data: anytype) !Value {
        const class_name = self.context.string_pool.keys()[static_call_data.class_name];
        const method_name = self.context.string_pool.keys()[static_call_data.method_name];

        // 解析类引用：self、parent、具体类名或变量（$obj::method()）
        const class = if (std.mem.eql(u8, class_name, "self")) blk: {
            break :blk self.current_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access self:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
        } else if (std.mem.eql(u8, class_name, "parent")) blk: {
            const curr_class = self.current_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
            break :blk curr_class.parent orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: when class has no parent", self.current_file, self.current_line);
                return self.throwException(exception);
            };
        } else if (class_name.len > 0 and class_name[0] == '$') blk: {
            // 变量形式的静态调用：$obj::method()
            const var_value = self.getVariable(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
            if (var_value.tag == .object) {
                break :blk var_value.data.object.data.class;
            } else if (var_value.tag == .string) {
                // 字符串作为类名
                const str_class_name = var_value.data.string.data.data;
                break :blk self.getClass(str_class_name) orelse {
                    const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, str_class_name, self.current_file, self.current_line);
                    return self.throwException(exception);
                };
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use non-object as class in static method call", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        } else blk: {
            break :blk self.getClass(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
        };

        // Evaluate arguments
        var args = std.ArrayList(Value){};
        try args.ensureTotalCapacity(self.allocator, static_call_data.args.len);
        defer {
            for (args.items) |arg| {
                self.releaseValue(arg);
            }
            args.deinit(self.allocator);
        }

        for (static_call_data.args) |arg_node_idx| {
            const arg_value = try self.eval(arg_node_idx);
            try args.append(self.allocator, arg_value);
        }

        // 查找并调用静态方法（也支持调用非静态方法，与PHP兼容）
        const method = class.getMethod(method_name) orelse blk: {
            // Check for __callStatic magic method later
            break :blk null;
        };

        if (method) |m| {
            // Push call frame
            const full_method_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
            defer self.allocator.free(full_method_name);
            try self.pushCallFrame(full_method_name, self.current_file, self.current_line);
            defer self.popCallFrame();

            // Bind arguments to parameters
            for (m.parameters, 0..) |param, i| {
                if (i < args.items.len) {
                    try self.setVariable(param.name.data, args.items[i]);
                } else if (param.default_value) |default| {
                    try self.setVariable(param.name.data, default);
                }
            }

            // Set current class for 'self' resolution
            const old_class = self.current_class;
            self.current_class = class;
            defer self.current_class = old_class;

            // Execute method body
            if (m.body) |body_ptr| {
                const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
                return self.eval(body_node) catch |err| {
                    if (err == error.Return) {
                        if (self.return_value) |val| {
                            const ret = val;
                            self.return_value = null;
                            return ret;
                        }
                        return Value.initNull();
                    }
                    return err;
                };
            }

            return Value.initNull();
        } else {
            // Check for __callStatic magic method
            if (class.methods.get("__callStatic")) |call_static| {
                _ = call_static;
                const name_val = try Value.initString(self.allocator, method_name);
                defer name_val.release(self.allocator);

                // Wrap arguments in a PHP array
                const args_array_val = try Value.initArrayWithManager(&self.memory_manager);
                const args_array = args_array_val.data.array.data;
                for (args.items) |arg| {
                    try args_array.push(self.allocator, arg);
                }
                defer args_array_val.release(self.allocator);

                const magic_args = [_]Value{ name_val, args_array_val };

                // Set current class for 'self' resolution
                const old_class = self.current_class;
                self.current_class = class;
                defer self.current_class = old_class;

                // Call __callStatic
                if (class.methods.get("__callStatic")) |inner_call_static| {
                    const full_method_name = try std.fmt.allocPrint(self.allocator, "{s}::__callStatic", .{class_name});
                    defer self.allocator.free(full_method_name);
                    try self.pushCallFrame(full_method_name, self.current_file, self.current_line);
                    defer self.popCallFrame();

                    // Bind arguments to parameters
                    for (inner_call_static.parameters, 0..) |param, i| {
                        if (i < magic_args.len) {
                            try self.setVariable(param.name.data, magic_args[i]);
                        }
                    }

                    if (inner_call_static.body) |body_ptr| {
                        const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
                        return self.eval(body_node) catch |err| {
                            if (err == error.Return) {
                                if (self.return_value) |val| {
                                    const ret = val;
                                    self.return_value = null;
                                    return ret;
                                }
                                return Value.initNull();
                            }
                            return err;
                        };
                    }
                }
                return Value.initNull();
            }

            const msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name });
            defer self.allocator.free(msg);
            const exception = try ExceptionFactory.createTypeError(self.allocator, msg, self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn evaluateClassConstantAccess(self: *VM, const_access_data: anytype) !Value {
        const class_name = self.context.string_pool.keys()[const_access_data.class_name];
        const constant_name = self.context.string_pool.keys()[const_access_data.constant_name];

        // 解析类引用：self、parent、具体类名或变量（$obj::$prop）
        const class = if (std.mem.eql(u8, class_name, "self")) blk: {
            break :blk self.current_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access self:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
        } else if (std.mem.eql(u8, class_name, "parent")) blk: {
            const curr_class = self.current_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
            break :blk curr_class.parent orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: when class has no parent", self.current_file, self.current_line);
                return self.throwException(exception);
            };
        } else if (class_name.len > 0 and class_name[0] == '$') blk: {
            // 变量形式的静态访问：$obj::$prop
            const var_value = self.getVariable(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
            if (var_value.tag == .object) {
                break :blk var_value.data.object.data.class;
            } else if (var_value.tag == .string) {
                const str_class_name = var_value.data.string.data.data;
                break :blk self.getClass(str_class_name) orelse {
                    const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, str_class_name, self.current_file, self.current_line);
                    return self.throwException(exception);
                };
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use non-object as class in static property access", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        } else blk: {
            break :blk self.getClass(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
        };

        // Look up constant in class (包括继承链)
        if (class.constants.get(constant_name)) |value| {
            return value.retain();
        }

        // Check if it's a static property (包括继承链查找)
        if (class.getProperty(constant_name)) |prop| {
            if (prop.modifiers.is_static) {
                if (prop.default_value) |val| {
                    return val.retain();
                }
                return Value.initNull();
            }
        }

        // 检查父类常量
        var current_class: ?*types.PHPClass = class.parent;
        while (current_class) |parent_class| {
            if (parent_class.constants.get(constant_name)) |value| {
                return value.retain();
            }
            current_class = parent_class.parent;
        }

        const msg = try std.fmt.allocPrint(self.allocator, "Undefined class constant or static property {s}::{s}", .{ class_name, constant_name });
        defer self.allocator.free(msg);
        const exception = try ExceptionFactory.createTypeError(self.allocator, msg, self.current_file, self.current_line);
        return self.throwException(exception);
    }
};
