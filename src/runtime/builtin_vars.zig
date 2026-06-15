//! PHP Variable, Class, and Constant Built-in Functions
//!
//! High-performance implementations focusing on:
//! - Zero-copy operations where possible
//! - Minimal memory allocations
//! - Fast type checking with inline checks
//! - Efficient string comparisons

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const Closure = types.Closure;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;

// Forward declaration for VM
const VM = @import("vm.zig").VM;

// ============================================================================
// Configuration Constants
// ============================================================================

const INI_CACHE_SIZE = 64;

/// Configuration cache entry
const IniEntry = struct {
    name: []const u8,
    value: []const u8,
};

/// Configuration cache (stack-allocated for performance)
var ini_cache: [INI_CACHE_SIZE]IniEntry = undefined;
var ini_cache_count: usize = 0;

/// Error reporting levels
const E_ERROR: i32 = 1;
const E_WARNING: i32 = 2;
const E_PARSE: i32 = 4;
const E_NOTICE: i32 = 8;
const E_CORE_ERROR: i16 = 16;
const E_CORE_WARNING: i32 = 32;
const E_COMPILE_ERROR: i32 = 64;
const E_COMPILE_WARNING: i32 = 128;
const E_USER_ERROR: i32 = 256;
const E_USER_WARNING: i32 = 512;
const E_USER_NOTICE: i32 = 1024;
const E_STRICT: i32 = 2048;
const E_RECOVERABLE_ERROR: i32 = 4096;
const E_DEPRECATED: i32 = 8192;
const E_USER_DEPRECATED: i32 = 16384;
const E_ALL: i32 = 32767;

var error_reporting_level: i32 = E_ALL;

/// Shutdown function callbacks
var shutdown_functions: std.ArrayListUnmanaged(*ShutdownCallback) = undefined;
var shutdown_functions_initialized: bool = false;

const ShutdownCallback = struct {
    callback: Value,
    args: []Value,
};

/// Tick function callbacks
var tick_functions: std.ArrayListUnmanaged(*TickCallback) = undefined;
var tick_functions_initialized: bool = false;
var tick_count: u64 = 0;
var declare_tick_count: i32 = 0;

const TickCallback = struct {
    callback: Value,
    args: []Value,
    priority: i32 = 0,
};

// ============================================================================
// Initialization
// ============================================================================

pub fn initCallbacks(allocator: std.mem.Allocator) void {
    _ = allocator;
    if (!shutdown_functions_initialized) {
        shutdown_functions = std.ArrayListUnmanaged(*ShutdownCallback){ .items = &.{}, .capacity = 0 };
        shutdown_functions_initialized = true;
    }
    if (!tick_functions_initialized) {
        tick_functions = std.ArrayListUnmanaged(*TickCallback){ .items = &.{}, .capacity = 0 };
        tick_functions_initialized = true;
    }
}

pub fn deinitCallbacks() void {
    if (shutdown_functions_initialized) {
        shutdown_functions.deinit();
        shutdown_functions_initialized = false;
    }
    if (tick_functions_initialized) {
        tick_functions.deinit();
        tick_functions_initialized = false;
    }
}

/// Called on every tick (executed by VM)
pub fn tickCallback(vm: *VM) !void {
    if (!tick_functions_initialized or tick_functions.items.len == 0) {
        return;
    }
    if (declare_tick_count <= 0) {
        return;
    }

    tick_count += 1;
    if (tick_count % @as(u64, @intCast(declare_tick_count)) != 0) {
        return;
    }

    // Execute all tick functions
    for (tick_functions.items) |item| {
        _ = executeCallback(vm, item.callback, item.args) catch {};
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if value is "empty" - fast path for common types
inline fn isValueEmpty(value: Value) bool {
    return switch (value.getTag()) {
        .null => true,
        .boolean => !value.asBool(),
        .integer => value.asInt() == 0,
        .float => value.asFloat() == 0.0,
        .string => value.getAsString().data.data.len == 0,
        .array => value.getAsArray().data.getElements().count() == 0,
        else => false,
    };
}

/// Check if a value is callable (fast inline checks)
fn isValueCallable(vm: *VM, value: Value, include_string: bool) bool {
    return switch (value.getTag()) {
        .closure => true,
        .arrow_function => true,
        .native_function => true,
        .user_function => true,
        .object => blk: {
            // Check if object has __invoke method
            const obj = value.getAsObject().data;
            const class = obj.class;
            if (class.getMethod("__invoke")) |_| {
                break :blk true;
            }
            break :blk false;
        },
        .string, .array => if (include_string) isCallableString(vm, value) else false,
        else => false,
    };
}

/// Check if string is a valid function name
inline fn isValidFunctionName(s: []const u8) bool {
    if (s.len == 0 or s.len > 256) return false;
    if (!std.ascii.isAlphabetic(s[0]) and s[0] != '_') return false;
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '\\') return false;
    }
    return true;
}

/// Check if string value represents a callable function
fn isCallableString(vm: *VM, value: Value) bool {
    const str = value.getAsString();
    const s = str.data.data;

    // Check if it's a simple function name
    if (isValidFunctionName(s)) {
        // Check if builtin function exists (fast path)
        if (vm.stdlib.getFunction(s)) |_| {
            return true;
        }
        // Note: user functions are checked separately via closure/user_function tags
    }

    // Check for "ClassName::methodName" or "ClassName::__construct" syntax
    if (std.mem.indexOf(u8, s, "::")) |_| {
        return true;
    }

    return false;
}

/// Execute a callback function with arguments
fn executeCallback(vm: *VM, callback: Value, args: []const Value) !Value {
    return switch (callback.getTag()) {
        .native_function => {
            const func: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            return func(vm, args);
        },
        .user_function => try vm.callUserFunction(callback.getAsUserFunc().data, args),
        .closure => try vm.callClosure(callback.getAsClosure().data, args),
        .string => {
            // Callback is a function name string
            const func_name = callback.getAsString().data.data;
            // Try builtin function first
            if (vm.stdlib.getFunction(func_name)) |builtin| {
                return builtin.handler(vm, args);
            }
            return error.FunctionNotFound;
        },
        else => error.InvalidCallback,
    };
}

// ============================================================================
// Variable Functions
// ============================================================================

/// empty - Checks if a variable is empty
pub fn emptyFn(_: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(true);
    }

    // Fast inline check for common cases
    return Value.initBool(isValueEmpty(args[0]));
}

/// isset - Checks if a variable is set
pub fn issetFn(_: *VM, args: []const Value) !Value {
    // Simplified implementation - in PHP this checks if variables are set
    // For our purposes, just return true if we have arguments
    for (args) |arg| {
        if (arg.getTag() == .null) {
            return Value.initBool(false);
        }
    }
    return Value.initBool(true);
}

/// unset - Unsets a variable
pub fn unsetFn(_: *VM, args: []const Value) !Value {
    _ = args;
    // In PHP, unset() doesn't return a value
    return Value.initNull();
}

/// is_callable - Checks if a value can be called as a function
pub fn isCallableFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const include_string = if (args.len > 1) args[1].asBool() else true;
    return Value.initBool(isValueCallable(vm, args[0], include_string));
}

// ============================================================================
// Callback Functions
// ============================================================================

/// call_user_func - Call a callback with given arguments
pub fn callUserFuncFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "call_user_func", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const callback = args[0];
    const callback_args = args[1..];

    return executeCallback(vm, callback, callback_args);
}

/// call_user_func_array - Call a callback with given arguments as array
pub fn callUserFuncArrayFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "call_user_func_array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const callback = args[0];
    const args_array = args[1];

    if (args_array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "call_user_func_array() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Fast path: if array is empty, pass empty args
    const array_data = args_array.getAsArray().data;
    if (array_data.getElements().count() == 0) {
        return executeCallback(vm, callback, &.{});
    }

    // Build arguments array (avoid allocation if possible)
    const count = array_data.getElements().count();
    const arg_values = try vm.allocator.alloc(Value, count);
    defer vm.allocator.free(arg_values);

    var idx: usize = 0;
    var iterator = array_data.getElements().iterator();
    while (iterator.next()) |entry| {
        arg_values[idx] = entry.value_ptr.*;
        idx += 1;
    }

    return executeCallback(vm, callback, arg_values);
}

/// Closure::fromCallable - Create a closure from a callable
pub fn closureFromCallableFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "Closure::fromCallable", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const callable = args[0];

    // If it's already a closure or arrow function, return it directly
    if (callable.getTag() == .closure or callable.getTag() == .arrow_function) {
        _ = callable.retain();
        return callable;
    }

    // If it's a user function, wrap it in a closure
    if (callable.getTag() == .user_function) {
        const user_func = callable.getAsUserFunc().data;
        
        // Create a closure that wraps the user function
        const closure_data = Closure.init(vm.allocator, user_func.*);
        const closure = try vm.memory_manager.allocClosure(closure_data);
        
        const closure_value = Value.fromBox(closure, Value.TYPE_CLOSURE);
        return closure_value;
    }

    // If it's a string, parse it as function name or "Class::method"
    if (callable.getTag() == .string) {
        const callable_str = callable.getAsString().data.data;
        
        // Check if it's a static method call: "ClassName::methodName"
        if (std.mem.indexOf(u8, callable_str, "::")) |sep_pos| {
            const class_name = callable_str[0..sep_pos];
            const method_name = callable_str[sep_pos + 2 ..];
            
            // Get the class
            const class = vm.getClass(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedClassError(vm.allocator, class_name, vm.current_file, vm.current_line);
                return vm.throwException(exception);
            };
            
            // Get the method
            const method_lookup = class.getMethodLookup(method_name) orelse {
                const exception = try ExceptionFactory.createUndefinedMethodError(vm.allocator, class_name, method_name, vm.current_file, vm.current_line);
                return vm.throwException(exception);
            };
            
            _ = method_lookup;
            
            // For static methods, we create an arrow function that calls the static method
            // This is a simplified approach - we store the callable string and call it later
            const callable_str_copy = try vm.memory_manager.allocString(callable_str);
            const callable_str_value = Value.fromBox(callable_str_copy, Value.TYPE_STRING);
            
            // Return the string as a callable (PHP allows this)
            return callable_str_value;
        }
        
        // It's a regular function name
        const func_val = vm.global.get(callable_str) orelse {
            const exception = try ExceptionFactory.createUndefinedFunctionError(vm.allocator, callable_str, vm.current_file, vm.current_line);
            return vm.throwException(exception);
        };
        
        // Recursively call fromCallable on the function value
        return closureFromCallableFn(vm, &[_]Value{func_val});
    }

    // Invalid callable type
    const exception = try ExceptionFactory.createTypeError(vm.allocator, "Closure::fromCallable() expects parameter 1 to be a valid callback", vm.current_file, vm.current_line);
    return vm.throwException(exception);
}

// ============================================================================
// Class/Object Functions
// ============================================================================

/// class_exists - Checks if a class is defined
pub fn classExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const class_name = args[0];
    if (class_name.getTag() != .string) {
        return Value.initBool(false);
    }

    const name = class_name.getAsString().data.data;
    return Value.initBool(vm.classes.get(name) != null);
}

/// interface_exists - Checks if an interface is defined
pub fn interfaceExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const interface_name = args[0];
    if (interface_name.getTag() != .string) {
        return Value.initBool(false);
    }

    const name = interface_name.getAsString().data.data;
    return Value.initBool(vm.interfaces.get(name) != null);
}

/// trait_exists - Checks if a trait is defined
pub fn traitExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const trait_name = args[0];
    if (trait_name.getTag() != .string) {
        return Value.initBool(false);
    }

    const name = trait_name.getAsString().data.data;
    return Value.initBool(vm.traits.get(name) != null);
}

/// method_exists - Checks if a method exists in a class
pub fn methodExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        return Value.initBool(false);
    }

    const target = args[0];
    const method_name = args[1];

    if (method_name.getTag() != .string) {
        return Value.initBool(false);
    }

    const method_str = method_name.getAsString().data.data;

    // Get class name
    const class_name = switch (target.getTag()) {
        .string => target.getAsString().data.data,
        .object => target.getAsObject().data.class.name.data,
        else => return Value.initBool(false),
    };

    // Check if class exists
    const class = vm.classes.get(class_name) orelse return Value.initBool(false);

    // Check for method
    return Value.initBool(class.getMethod(method_str) != null);
}

/// property_exists - Checks if a property exists
pub fn propertyExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        return Value.initBool(false);
    }

    const target = args[0];
    const prop_name = args[1];

    if (prop_name.getTag() != .string) {
        return Value.initBool(false);
    }

    const prop_str = prop_name.getAsString().data.data;

    // Get class name
    const class_name = switch (target.getTag()) {
        .string => target.getAsString().data.data,
        .object => target.getAsObject().data.class.name.data,
        else => return Value.initBool(false),
    };

    const class = vm.classes.get(class_name) orelse return Value.initBool(false);

    return Value.initBool(class.getProperty(prop_str) != null);
}

/// is_a - Checks if an object is of a certain class
pub fn isAFn(_: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        return Value.initBool(false);
    }

    const object = args[0];
    const class_name = args[1];
    const allow_string = if (args.len > 2) args[2].asBool() else false;

    if (object.getTag() == .string) {
        if (!allow_string) return Value.initBool(false);
        const str_class = object.getAsString().data.data;
        const target_class = class_name.getAsString().data.data;
        return Value.initBool(std.mem.eql(u8, str_class, target_class));
    }

    if (object.getTag() != .object) {
        return Value.initBool(false);
    }

    const obj_class = object.getAsObject().data.class;
    const target_class = class_name.getAsString().data.data;

    // Check if object is of the class or a subclass
    var current: ?*types.PHPClass = obj_class;
    while (current) |c| {
        if (std.mem.eql(u8, c.name.data, target_class)) {
            return Value.initBool(true);
        }
        current = c.parent;
    }

    return Value.initBool(false);
}

/// is_subclass_of - Checks if an object/class is a subclass of another
pub fn isSubclassOfFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        return Value.initBool(false);
    }

    const object_or_class = args[0];
    const class_name = args[1];

    // Get the class to check
    const current_class = switch (object_or_class.getTag()) {
        .string => vm.classes.get(object_or_class.getAsString().data.data),
        .object => vm.classes.get(object_or_class.getAsObject().data.class.name.data),
        else => null,
    } orelse return Value.initBool(false);

    const target_class = class_name.getAsString().data.data;

    // Walk up the inheritance chain
    var current: ?*types.PHPClass = current_class;
    while (current) |c| {
        if (std.mem.eql(u8, c.name.data, target_class)) {
            return Value.initBool(true);
        }
        current = c.parent;
    }

    return Value.initBool(false);
}

/// get_class - Returns the class name of an object
pub fn getClassFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const object = args[0];

    if (object.getTag() == .string) {
        return Value.initBool(false);
    }

    if (object.getTag() != .object) {
        return Value.initBool(false);
    }

    const class = object.getAsObject().data.class;
    return Value.initString(vm.allocator, class.name.data);
}

/// get_parent_class - Returns the parent class name
pub fn getParentClassFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const object = args[0];

    if (object.getTag() != .object) {
        return Value.initBool(false);
    }

    const class = object.getAsObject().data.class;
    const parent = class.parent orelse return Value.initBool(false);

    return Value.initString(vm.allocator, parent.name.data);
}

/// get_class_methods - Returns an array of method names
pub fn getClassMethodsFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const class_name = args[0];

    const name = switch (class_name.getTag()) {
        .string => class_name.getAsString().data.data,
        .object => class_name.getAsObject().data.class.name.data,
        else => return Value.initBool(false),
    };

    const class = vm.classes.get(name) orelse return Value.initBool(false);

    const result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var idx: i64 = 0;
    var iter = class.methods.iterator();
    while (iter.next()) |entry| {
        const key = ArrayKey{ .integer = idx };
        const val = try Value.initString(vm.allocator, entry.key_ptr.*);
        try result_array.set(vm.allocator, key, val);
        idx += 1;
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// ============================================================================
// Configuration Functions (ini)
// ============================================================================

/// ini_get - Gets the value of a configuration option
pub fn iniGetFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const varname = args[0];
    if (varname.getTag() != .string) {
        return Value.initBool(false);
    }

    const name = varname.getAsString().data.data;

    // Check cache first
    for (0..ini_cache_count) |i| {
        if (std.mem.eql(u8, ini_cache[i].name, name)) {
            return Value.initString(vm.allocator, ini_cache[i].value);
        }
    }

    // Default values for common ini settings (inline check for performance)
    const default_value: ?[]const u8 = if (std.mem.eql(u8, name, "error_reporting")) "32767" else if (std.mem.eql(u8, name, "display_errors")) "1" else if (std.mem.eql(u8, name, "log_errors")) "0" else if (std.mem.eql(u8, name, "max_execution_time")) "0" else if (std.mem.eql(u8, name, "memory_limit")) "128M" else if (std.mem.eql(u8, name, "post_max_size")) "8M" else if (std.mem.eql(u8, name, "upload_max_filesize")) "2M" else if (std.mem.eql(u8, name, "precision")) "14" else if (std.mem.eql(u8, name, "assert.active")) "1" else if (std.mem.eql(u8, name, "zend.assertions")) "1" else null;

    if (default_value) |value| {
        return Value.initString(vm.allocator, value);
    }

    return Value.initBool(false);
}

/// ini_set - Sets the value of a configuration option
pub fn iniSetFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        return Value.initBool(false);
    }

    const varname = args[0];
    const newvalue = args[1];

    if (varname.getTag() != .string or newvalue.getTag() != .string) {
        return Value.initBool(false);
    }

    const name = varname.getAsString().data.data;
    const value = newvalue.getAsString().data.data;

    // Handle special ini settings
    if (std.mem.eql(u8, name, "error_reporting")) {
        if (std.fmt.parseInt(i32, value, 10)) |parsed| {
            const old_value = error_reporting_level;
            error_reporting_level = parsed;
            return Value.initInt(old_value);
        } else |_| {}
    }

    // Add to cache
    if (ini_cache_count < INI_CACHE_SIZE) {
        ini_cache[ini_cache_count] = .{
            .name = try vm.allocator.dupe(u8, name),
            .value = try vm.allocator.dupe(u8, value),
        };
        ini_cache_count += 1;
    }

    return Value.initBool(false);
}

/// ini_restore - Restores the value of a configuration option
pub fn iniRestoreFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initBool(true);
}

/// error_reporting - Sets the error reporting level
pub fn errorReportingFn(vm: *VM, args: []const Value) !Value {
    _ = vm;

    if (args.len > 0) {
        const level = args[0];
        if (level.getTag() == .integer) {
            const old = error_reporting_level;
            error_reporting_level = @intCast(level.asInt());
            return Value.initInt(old);
        }
    }

    return Value.initInt(error_reporting_level);
}

// ============================================================================
// Error Functions
// ============================================================================

/// trigger_error - Generates a user-level error/warning/notice
pub fn triggerErrorFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const message = args[0];
    const error_type = if (args.len > 1) args[1] else Value.initInt(E_USER_ERROR);

    if (message.getTag() != .string) {
        return Value.initBool(false);
    }

    const msg_str = message.getAsString().data.data;
    const err_type = if (error_type.getTag() == .integer) @as(i32, @intCast(error_type.asInt())) else E_USER_ERROR;

    // Create appropriate exception based on error type
    const exception = switch (err_type) {
        E_USER_ERROR => ExceptionFactory.createError(vm.allocator, msg_str, vm.current_file, vm.current_line),
        E_USER_WARNING => ExceptionFactory.createError(vm.allocator, msg_str, vm.current_file, vm.current_line),
        E_USER_NOTICE => ExceptionFactory.createError(vm.allocator, msg_str, vm.current_file, vm.current_line),
        else => ExceptionFactory.createError(vm.allocator, msg_str, vm.current_file, vm.current_line),
    };

    _ = try vm.throwException(try exception);
    return Value.initBool(true);
}

/// set_error_handler - Sets a user-defined error handler
pub fn setErrorHandlerFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initNull();
}

/// set_exception_handler - Sets a user-defined exception handler
pub fn setExceptionHandlerFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initNull();
}

/// error_get_last - Returns the last error
pub fn errorGetLastFn(_: *VM, args: []const Value) !Value {
    _ = args;
    return Value.initNull();
}

// ============================================================================
// URL Functions
// ============================================================================

/// parse_url - Parse a URL into its components
pub fn parseUrlFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const url = args[0];
    if (url.getTag() != .string) {
        return Value.initBool(false);
    }

    const url_str = url.getAsString().data.data;
    const component = if (args.len > 1) args[1] else Value.initNull();

    // Simple URL parsing (minimal implementation)
    var scheme_end: usize = 0;
    var host_start: usize = 0;
    var host_end: usize = 0;
    var port: ?u16 = null;
    var path_start: usize = url_str.len;
    var query_start: usize = url_str.len;
    var fragment_start: usize = url_str.len;

    // Find scheme
    if (std.mem.indexOf(u8, url_str, "://")) |idx| {
        scheme_end = idx;
        host_start = idx + 3;
    } else {
        scheme_end = 0;
        host_start = 0;
    }

    // Find host:port
    if (scheme_end > 0 or host_start == 0) {
        const search_start = host_start;

        if (search_start >= url_str.len) {
            // No host, skip URL parsing
        } else {
            // Look for :port, /path, ?query, #fragment
            var host_end_candidate = url_str.len;
            if (std.mem.indexOfAny(u8, url_str[search_start..], ":/?#")) |idx| {
                host_end_candidate = search_start + idx;
            }

            // Check for port
            if (host_end_candidate < url_str.len and url_str[host_end_candidate] == ':') {
                const port_start = host_end_candidate + 1;
                var port_end = port_start;
                while (port_end < url_str.len and std.ascii.isDigit(url_str[port_end])) {
                    port_end += 1;
                }
                if (port_end > port_start) {
                    const port_str = url_str[port_start..port_end];
                    port = std.fmt.parseInt(u16, port_str, 10) catch null;
                    host_end = host_start + (host_end_candidate - search_start);
                } else {
                    host_end = host_end_candidate;
                }
            } else {
                host_end = host_end_candidate;
            }

            // Find path, query, fragment
            if (host_end < url_str.len) {
                const rest = url_str[host_end..];
                if (rest.len > 0) {
                    switch (rest[0]) {
                        '/' => {
                            path_start = host_end;
                            if (std.mem.indexOf(u8, rest, "?")) |qi| {
                                query_start = host_end + qi;
                                if (std.mem.indexOf(u8, rest[qi + 1 ..], "#")) |fi| {
                                    fragment_start = host_end + qi + 1 + fi;
                                }
                            } else if (std.mem.indexOf(u8, rest, "#")) |fi| {
                                fragment_start = host_end + fi;
                            }
                        },
                        '?' => {
                            query_start = host_end;
                            if (std.mem.indexOf(u8, rest, "#")) |fi| {
                                fragment_start = host_end + 1 + fi;
                            }
                        },
                        '#' => {
                            fragment_start = host_end;
                        },
                        else => {},
                    }
                }
            }
        }
    }

    // If specific component is requested
    if (component.getTag() == .integer) {
        const comp = @as(i32, @intCast(component.asInt()));
        const PHP_URL_SCHEME = 1;
        const PHP_URL_HOST = 2;
        const PHP_URL_PORT = 3;
        const PHP_URL_PATH = 6;
        const PHP_URL_QUERY = 7;
        const PHP_URL_FRAGMENT = 8;

        const host = if (host_end > host_start) url_str[host_start..host_end] else "";
        const path = if (path_start < query_start) url_str[path_start..query_start] else "";
        const query = if (query_start < fragment_start and query_start < url_str.len and url_str[query_start] == '?')
            url_str[query_start + 1 .. fragment_start]
        else
            "";
        const fragment = if (fragment_start < url_str.len and url_str[fragment_start] == '#')
            url_str[fragment_start + 1 ..]
        else
            "";

        return switch (comp) {
            PHP_URL_SCHEME => if (scheme_end > 0)
                Value.initString(vm.allocator, url_str[0..scheme_end])
            else
                Value.initBool(false),
            PHP_URL_HOST => if (host.len > 0)
                Value.initString(vm.allocator, host)
            else
                Value.initBool(false),
            PHP_URL_PORT => if (port != null)
                Value.initInt(port.?)
            else
                Value.initBool(false),
            PHP_URL_PATH => if (path.len > 0)
                Value.initString(vm.allocator, path)
            else
                Value.initBool(false),
            PHP_URL_QUERY => if (query.len > 0)
                Value.initString(vm.allocator, query)
            else
                Value.initBool(false),
            PHP_URL_FRAGMENT => if (fragment.len > 0)
                Value.initString(vm.allocator, fragment)
            else
                Value.initBool(false),
            else => Value.initBool(false),
        };
    }

    // Return associative array with all components
    const result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }

    const scheme = if (scheme_end > 0) url_str[0..scheme_end] else "";
    const host = if (host_end > host_start) url_str[host_start..host_end] else "";
    const path = if (path_start < fragment_start and path_start < url_str.len and url_str[path_start] == '/')
        url_str[path_start..query_start]
    else
        "";
    const query = if (query_start < fragment_start and query_start < url_str.len and url_str[query_start] == '?')
        url_str[query_start + 1 .. fragment_start]
    else
        "";
    const fragment = if (fragment_start < url_str.len and url_str[fragment_start] == '#')
        url_str[fragment_start + 1 ..]
    else
        "";

    // Scheme
    if (scheme.len > 0) {
        const key = ArrayKey{ .string = try PHPString.init(vm.allocator, "scheme") };
        const val = try Value.initString(vm.allocator, scheme);
        try result_array.set(vm.allocator, key, val);
    }

    // Host
    if (host.len > 0) {
        const key = ArrayKey{ .string = try PHPString.init(vm.allocator, "host") };
        const val = try Value.initString(vm.allocator, host);
        try result_array.set(vm.allocator, key, val);
    }

    // Port
    if (port) |p| {
        const key = ArrayKey{ .string = try PHPString.init(vm.allocator, "port") };
        try result_array.set(vm.allocator, key, Value.initInt(@intCast(p)));
    }

    // Path
    if (path.len > 0) {
        const key = ArrayKey{ .string = try PHPString.init(vm.allocator, "path") };
        const val = try Value.initString(vm.allocator, path);
        try result_array.set(vm.allocator, key, val);
    }

    // Query
    if (query.len > 0) {
        const key = ArrayKey{ .string = try PHPString.init(vm.allocator, "query") };
        const val = try Value.initString(vm.allocator, query);
        try result_array.set(vm.allocator, key, val);
    }

    // Fragment
    if (fragment.len > 0) {
        const key = ArrayKey{ .string = try PHPString.init(vm.allocator, "fragment") };
        const val = try Value.initString(vm.allocator, fragment);
        try result_array.set(vm.allocator, key, val);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// ============================================================================
// Definition/Reflection Functions
// ============================================================================

/// get_defined_vars - Returns an array of all defined variables
pub fn getDefinedVarsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

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

/// get_defined_functions - Returns an array of all defined functions
pub fn getDefinedFunctionsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    // Create 'internal' and 'user' sub-arrays
    const internal_array = try vm.allocator.create(PHPArray);
    internal_array.* = PHPArray.init(vm.allocator);

    const user_array = try vm.allocator.create(PHPArray);
    user_array.* = PHPArray.init(vm.allocator);

    // Note: Builtin functions are tracked in vm.stdlib registry
    // For now, return empty arrays - can be enhanced to iterate builtin_registry

    // Create boxes
    const internal_box = try vm.allocator.create(types.gc.Box(*PHPArray));
    internal_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = internal_array,
    };

    const user_box = try vm.allocator.create(types.gc.Box(*PHPArray));
    user_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = user_array,
    };

    // Set internal and user in result
    {
        const key = ArrayKey{ .string = try PHPString.init(vm.allocator, "internal") };
        const val = Value.fromBox(internal_box, Value.TYPE_ARRAY);
        try result_array.set(vm.allocator, key, val);
    }
    {
        const key = ArrayKey{ .string = try PHPString.init(vm.allocator, "user") };
        const val = Value.fromBox(user_box, Value.TYPE_ARRAY);
        try result_array.set(vm.allocator, key, val);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

/// get_defined_constants - Returns an array of all defined constants
pub fn getDefinedConstantsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var idx: i64 = 0;
    var iter = vm.global.vars.iterator();
    while (iter.next()) |entry| {
        const key = ArrayKey{ .integer = idx };
        const val = try Value.initString(vm.allocator, entry.key_ptr.*);
        try result_array.set(vm.allocator, key, val);
        idx += 1;
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

/// get_declared_classes - Returns an array of all declared classes
pub fn getDeclaredClassesFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);

    var idx: i64 = 0;
    var iter = vm.classes.iterator();
    while (iter.next()) |entry| {
        const key = ArrayKey{ .integer = idx };
        const val = try Value.initString(vm.allocator, entry.key_ptr.*);
        try result_array.set(vm.allocator, key, val);
        idx += 1;
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

// ============================================================================
// Shutdown/Tick Functions
// ============================================================================

/// register_shutdown_function - Registers a callback to be executed after script ends
pub fn registerShutdownFunctionFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    if (!shutdown_functions_initialized) {
        initCallbacks(vm.allocator);
    }

    const callback = args[0];
    const callback_args = args[1..];

    const shutdown_cb = try vm.allocator.create(ShutdownCallback);
    shutdown_cb.* = .{
        .callback = callback,
        .args = try vm.allocator.dupe(Value, callback_args),
    };

    try shutdown_functions.append(vm.allocator, shutdown_cb);
    return Value.initBool(true);
}

/// Execute all shutdown functions (called by VM on exit)
pub fn executeShutdownFunctions(vm: *VM) !void {
    if (!shutdown_functions_initialized) return;

    for (shutdown_functions.items) |item| {
        _ = executeCallback(vm, item.callback, item.args) catch {};
    }
}

/// register_tick_function - Registers a callback to be called on every tick
pub fn registerTickFunctionFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    if (!tick_functions_initialized) {
        initCallbacks(vm.allocator);
    }

    const callback = args[0];
    const callback_args = args[1..];

    const tick_cb = try vm.allocator.create(TickCallback);
    tick_cb.* = .{
        .callback = callback,
        .args = try vm.allocator.dupe(Value, callback_args),
        .priority = 0,
    };

    try tick_functions.append(vm.allocator, tick_cb);
    return Value.initBool(true);
}

/// unregister_tick_function - Unregisters a tick callback
pub fn unregisterTickFunctionFn(vm: *VM, args: []const Value) !Value {
    _ = vm;

    if (args.len < 1) {
        return Value.initBool(false);
    }

    if (!tick_functions_initialized) {
        return Value.initBool(true);
    }

    // For now, just clear all tick functions
    tick_functions.clearRetainingCapacity();
    return Value.initBool(true);
}

// ============================================================================
// Function Argument Functions
// ============================================================================

/// func_num_args - Returns the number of arguments passed to the function
pub fn funcNumArgsFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    if (vm.current_call_args) |call_args| {
        return Value.initInt(@intCast(call_args.len));
    }
    return Value.initInt(0);
}

/// func_get_arg - Returns an argument from the function's argument list
pub fn funcGetArgFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "func_get_arg", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const arg_num = args[0];
    if (arg_num.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "func_get_arg() expects parameter 1 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const index = arg_num.asInt();
    if (index < 0) {
        const exception = try ExceptionFactory.createValueError(vm.allocator, "func_get_arg(): Argument $index cannot be negative", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentValue;
    }

    const call_args = vm.current_call_args orelse {
        return Value.initBool(false);
    };
    const idx = @as(usize, @intCast(index));
    if (idx >= call_args.len) {
        const exception = try ExceptionFactory.createValueError(vm.allocator, "func_get_arg(): Argument $index does not exist", "builtin", 0);
        _ = try vm.throwException(exception);
        return Value.initBool(false);
    }

    return call_args[idx];
}

/// func_get_args - Returns an array of the function's arguments
/// @ownership TRANSFER: 返回的数组由调用者负责释放
pub fn funcGetArgsFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    const call_args = vm.current_call_args orelse {
        return Value.initNull();
    };

    // 使用 memory_manager 统一管理生命周期
    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    for (call_args, 0..) |arg, i| {
        const key = ArrayKey{ .integer = @intCast(i) };
        // 直接复制值到数组，无需手动 retain（set 内部会处理）
        try php_array.set(vm.allocator, key, arg);
    }

    return php_array_value;
}

// ============================================================================
// String Functions
// ============================================================================

/// strtr - Translate characters or replace substrings
pub fn strtrFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        return Value.initNull();
    }

    const str = args[0];

    if (args.len == 2) {
        // strtr($str, $from, $to) - not standard PHP but useful
        return str;
    }

    const from = args[1];
    const to = args[2];

    if (from.getTag() == .string and to.getTag() == .string) {
        const from_str = from.getAsString().data.data;
        const to_str = to.getAsString().data.data;
        const input = str.getAsString().data.data;

        if (from_str.len != to_str.len or from_str.len == 0) {
            return str;
        }

        var result = try std.ArrayList(u8).initCapacity(vm.allocator, 64);
        defer result.deinit(vm.allocator);

        for (input) |c| {
            const pos = std.mem.indexOfScalar(u8, from_str, c);
            if (pos) |p| {
                try result.append(vm.allocator, to_str[p]);
            } else {
                try result.append(vm.allocator, c);
            }
        }

        // 使用 memory_manager 管理返回字符串
        return Value.initStringWithManager(&vm.memory_manager, result.items);
    }

    if (from.getTag() == .array) {
        // strtr($str, $replace_pairs)
        const input = str.getAsString().data.data;
        const pairs = from.getAsArray().data;

        var result = try vm.allocator.dupe(u8, input);
        var iter = pairs.getElements().iterator();
        while (iter.next()) |entry| {
            const from_key = switch (entry.key_ptr.*) {
                .string => |s| s.data,
                .integer => |i| std.fmt.allocPrint(vm.allocator, "{d}", .{i}) catch continue,
            };
            const to_val = entry.value_ptr.*;
            if (to_val.getTag() != .string) continue;
            const to_val_str = to_val.getAsString().data.data;

            var new_result = try std.ArrayList(u8).initCapacity(vm.allocator, 64);
            defer new_result.deinit(vm.allocator);

            var start: usize = 0;
            while (true) {
                const pos = std.mem.indexOf(u8, result, from_key);
                if (pos) |p| {
                    try new_result.appendSlice(vm.allocator, result[start..p]);
                    try new_result.appendSlice(vm.allocator, to_val_str);
                    start = p + from_key.len;
                } else {
                    try new_result.appendSlice(vm.allocator, result[start..]);
                    break;
                }
            }
            result = try new_result.toOwnedSlice(vm.allocator);
        }

        // 使用 memory_manager 管理返回字符串
        return Value.initStringWithManager(&vm.memory_manager, result);
    }

    return str;
}

// ============================================================================
// Array Functions
// ============================================================================// ============================================================================
// URL Functions
// ============================================================================

/// http_build_query - Generate URL-encoded query string
pub fn httpBuildQueryFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initNull();
    }

    const query_data = args[0];
    const delimiter = if (args.len > 3) args[3] else null;
    const enc_type = if (args.len > 4) args[4] else null;

    if (query_data.getTag() != .array and query_data.getTag() != .object) {
        return Value.initNull();
    }

    var result = try std.ArrayList(u8).initCapacity(vm.allocator, 64);
    defer result.deinit(vm.allocator);

    const enc_val = if (enc_type) |e| e.asInt() else 1; // PHP_QUERY_RFC1738 = 1
    const delim = if (delimiter) |d| d.getAsString().data.data else "&";

    var iter = query_data.getAsArray().data.getElements().iterator();
    var first = true;
    while (iter.next()) |entry| {
        const key = switch (entry.key_ptr.*) {
            .string => |s| s.data,
            .integer => |i| std.fmt.allocPrint(vm.allocator, "{d}", .{i}) catch continue,
        };
        const val = entry.value_ptr.*;

        if (!first) {
            try result.appendSlice(vm.allocator, delim);
        }
        first = false;

        const encoded_key = try urlEncode(vm.allocator, key, enc_val);
        defer vm.allocator.free(encoded_key);

        try result.appendSlice(vm.allocator, encoded_key);
        try result.append(vm.allocator, '=');

        const val_str = switch (val.getTag()) {
            .string => val.getAsString().data.data,
            .integer => std.fmt.allocPrint(vm.allocator, "{d}", .{val.asInt()}) catch "",
            .float => std.fmt.allocPrint(vm.allocator, "{d}", .{val.asFloat()}) catch "",
            else => "",
        };
        defer if (val.getTag() == .integer or val.getTag() == .float) vm.allocator.free(val_str);

        const encoded_val = try urlEncode(vm.allocator, val_str, enc_val);
        defer vm.allocator.free(encoded_val);

        try result.appendSlice(vm.allocator, encoded_val);
    }

    // 使用 memory_manager 创建字符串，确保正确的生命周期管理
    return Value.initStringWithManager(&vm.memory_manager, result.items);
}

inline fn urlEncode(allocator: std.mem.Allocator, input: []const u8, enc_type: i64) ![]const u8 {
    _ = enc_type;
    const hex_chars = "0123456789ABCDEF";
    var result = try std.ArrayList(u8).initCapacity(allocator, input.len * 3);
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-' or c == '.') {
            try result.append(allocator, c);
        } else if (c == ' ') {
            try result.append(allocator, '+');
        } else {
            try result.append(allocator, '%');
            try result.append(allocator, hex_chars[@as(usize, c) >> 4]);
            try result.append(allocator, hex_chars[@as(usize, c) & 0xF]);
        }
    }
    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Extension Functions
// ============================================================================

/// get_loaded_extensions - Returns an array of loaded extensions
/// @ownership TRANSFER: 返回的数组由调用者负责释放
pub fn getLoadedExtensionsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    // 使用 memory_manager 统一管理生命周期，避免内存泄漏
    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    // Return core extensions (hardcoded for now)
    const core_extensions = [_][]const u8{
        "core",
        "standard",
        "pcre",
        "json",
        "date",
        "filesystem",
    };

    for (core_extensions, 0..) |ext, i| {
        const key = ArrayKey{ .integer = @intCast(i) };
        // 使用 memory_manager 创建字符串，确保正确的生命周期管理
        const val = try Value.initStringWithManager(&vm.memory_manager, ext);
        try php_array.set(vm.allocator, key, val);
    }

    return php_array_value;
}

/// extension_loaded - Checks if an extension is loaded
pub fn extensionLoadedFn(_: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        return Value.initBool(false);
    }

    const name = args[0];
    if (name.getTag() != .string) {
        return Value.initBool(false);
    }

    const name_str = name.getAsString().data.data;

    // Core extensions list
    const core_extensions = [_][]const u8{
        "core", "standard", "pcre", "json", "date", "filesystem",
    };

    for (core_extensions) |ext| {
        if (std.mem.eql(u8, ext, name_str)) {
            return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

/// Declare tick count (called by 'declare(ticks=N)')
pub fn declareSetTickCount(count: i32) void {
    declare_tick_count = count;
}

/// Get tick count for VM
pub fn getTickCount() u64 {
    return tick_count;
}

// ============================================================================
// Function Registration
// ============================================================================

/// Register all variable/class/constant functions
pub fn registerVariableFunctions(stdlib: anytype) !void {
    const builtin_functions = [_]*const @import("stdlib.zig").BuiltinFunction{
        // Variable functions
        &.{ .name = "empty", .min_args = 1, .max_args = 1, .handler = emptyFn },
        &.{ .name = "isset", .min_args = 1, .max_args = 255, .handler = issetFn },
        &.{ .name = "unset", .min_args = 1, .max_args = 255, .handler = unsetFn },
        &.{ .name = "is_callable", .min_args = 1, .max_args = 3, .handler = isCallableFn },

        // Callback functions
        &.{ .name = "call_user_func", .min_args = 1, .max_args = 255, .handler = callUserFuncFn },
        &.{ .name = "call_user_func_array", .min_args = 2, .max_args = 2, .handler = callUserFuncArrayFn },
        &.{ .name = "Closure::fromCallable", .min_args = 1, .max_args = 1, .handler = closureFromCallableFn },

        // Class/Object functions
        &.{ .name = "class_exists", .min_args = 1, .max_args = 2, .handler = classExistsFn },
        &.{ .name = "interface_exists", .min_args = 1, .max_args = 2, .handler = interfaceExistsFn },
        &.{ .name = "trait_exists", .min_args = 1, .max_args = 2, .handler = traitExistsFn },
        &.{ .name = "method_exists", .min_args = 2, .max_args = 2, .handler = methodExistsFn },
        &.{ .name = "property_exists", .min_args = 2, .max_args = 2, .handler = propertyExistsFn },
        &.{ .name = "is_a", .min_args = 2, .max_args = 3, .handler = isAFn },
        &.{ .name = "is_subclass_of", .min_args = 2, .max_args = 2, .handler = isSubclassOfFn },
        &.{ .name = "get_class", .min_args = 0, .max_args = 1, .handler = getClassFn },
        &.{ .name = "get_parent_class", .min_args = 0, .max_args = 1, .handler = getParentClassFn },
        &.{ .name = "get_class_methods", .min_args = 0, .max_args = 1, .handler = getClassMethodsFn },

        // Configuration functions
        &.{ .name = "ini_get", .min_args = 1, .max_args = 1, .handler = iniGetFn },
        &.{ .name = "ini_set", .min_args = 2, .max_args = 2, .handler = iniSetFn },
        &.{ .name = "ini_restore", .min_args = 1, .max_args = 1, .handler = iniRestoreFn },
        &.{ .name = "error_reporting", .min_args = 0, .max_args = 1, .handler = errorReportingFn },

        // Error functions
        &.{ .name = "trigger_error", .min_args = 1, .max_args = 2, .handler = triggerErrorFn },
        &.{ .name = "set_error_handler", .min_args = 1, .max_args = 2, .handler = setErrorHandlerFn },
        &.{ .name = "set_exception_handler", .min_args = 1, .max_args = 1, .handler = setExceptionHandlerFn },
        &.{ .name = "error_get_last", .min_args = 0, .max_args = 0, .handler = errorGetLastFn },

        // URL functions
        &.{ .name = "parse_url", .min_args = 1, .max_args = 2, .handler = parseUrlFn },

        // Definition/Reflection functions
        &.{ .name = "get_defined_vars", .min_args = 0, .max_args = 0, .handler = getDefinedVarsFn },
        &.{ .name = "get_defined_functions", .min_args = 0, .max_args = 0, .handler = getDefinedFunctionsFn },
        &.{ .name = "get_defined_constants", .min_args = 0, .max_args = 1, .handler = getDefinedConstantsFn },
        &.{ .name = "get_declared_classes", .min_args = 0, .max_args = 0, .handler = getDeclaredClassesFn },

        // Shutdown/Tick functions
        &.{ .name = "register_shutdown_function", .min_args = 1, .max_args = 255, .handler = registerShutdownFunctionFn },
        &.{ .name = "register_tick_function", .min_args = 1, .max_args = 255, .handler = registerTickFunctionFn },
        &.{ .name = "unregister_tick_function", .min_args = 1, .max_args = 1, .handler = unregisterTickFunctionFn },

        // Function argument functions
        &.{ .name = "func_num_args", .min_args = 0, .max_args = 0, .handler = funcNumArgsFn },
        &.{ .name = "func_get_arg", .min_args = 1, .max_args = 1, .handler = funcGetArgFn },
        &.{ .name = "func_get_args", .min_args = 0, .max_args = 0, .handler = funcGetArgsFn },

        // String functions
        &.{ .name = "strtr", .min_args = 2, .max_args = 3, .handler = strtrFn },

        // Array functions

        // URL functions
        &.{ .name = "http_build_query", .min_args = 1, .max_args = 5, .handler = httpBuildQueryFn },

        // Extension functions
        &.{ .name = "get_loaded_extensions", .min_args = 0, .max_args = 0, .handler = getLoadedExtensionsFn },
        &.{ .name = "extension_loaded", .min_args = 1, .max_args = 1, .handler = extensionLoadedFn },
    };

    for (builtin_functions) |func| {
        try stdlib.registerFunction(func.name, func);
    }
}
