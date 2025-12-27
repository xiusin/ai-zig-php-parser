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
const ReflectionSystem = reflection.ReflectionSystem;

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
    
    pub fn deinit(self: *CallFrame) void {
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
        try php_array.push(method_name_value);
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
            try php_array.set(key, value);
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
        try php_array.set(key, property_value);
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

pub const VM = struct {
    allocator: std.mem.Allocator,
    global: *Environment,
    context: *PHPContext,
    classes: std.StringHashMap(*types.PHPClass),
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
    string_intern_pool: std.StringHashMap(*types.PHPString),

    pub fn init(allocator: std.mem.Allocator) !*VM {
        var vm = try allocator.create(VM);
        vm.* = .{
            .allocator = allocator,
            .global = try allocator.create(Environment),
            .context = undefined,
            .classes = std.StringHashMap(*types.PHPClass).init(allocator),
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
            .string_intern_pool = std.StringHashMap(*types.PHPString).init(allocator),
        };
        
        vm.global.* = Environment.init(allocator);
        vm.reflection_system = ReflectionSystem.init(allocator, vm);

        // Register built-in functions with optimized registration
        try vm.registerBuiltinFunctions();

        // Register all standard library functions
        try vm.registerStandardLibraryFunctions();
        
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
            frame.deinit();
        }
        self.call_stack.deinit(self.allocator);
        
        // Clean up string intern pool
        var intern_iterator = self.string_intern_pool.iterator();
        while (intern_iterator.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.string_intern_pool.deinit();
        
        // Clean up error context
        self.error_context.deinit(self.allocator);
        
        // Clean up all global variables (this will release their references)
        var global_iterator = self.global.vars.iterator();
        while (global_iterator.next()) |entry| {
            // Only release if it's a managed type
            switch (entry.value_ptr.*.tag) {
                .string, .array, .object, .resource, .user_function, .closure, .arrow_function => {
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
        
        // Clean up classes
        var class_iterator = self.classes.iterator();
        while (class_iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.classes.deinit();
        
        // Clean up memory manager (this will force final garbage collection)
        self.memory_manager.deinit();
        
        self.global.deinit();
        self.allocator.destroy(self.global);
        self.allocator.destroy(self);
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
        std.debug.print("=== PHP Interpreter Performance Statistics ===\n", .{});
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
        var to_remove = std.ArrayList([]const u8){};
        defer to_remove.deinit(self.allocator);
        
        var iterator = self.string_intern_pool.iterator();
        while (iterator.next()) |entry| {
            // Check if string is still referenced (simplified check)
            // In a real implementation, this would check reference counts
            _ = entry.value_ptr.*;
            // For now, we'll keep all strings in the pool
        }
        
        // Remove unused strings
        for (to_remove.items) |key| {
            if (self.string_intern_pool.fetchRemove(key)) |removed| {
                removed.value.deinit(self.allocator);
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
        try self.error_context.addError(
            self.allocator,
            error_type,
            message,
            self.current_file,
            self.current_line,
            stack_trace
        );
        
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
        if (self.string_intern_pool.get(str)) |interned| {
            // Return reference to existing string
            const box = try self.allocator.create(types.gc.Box(*types.PHPString));
            box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = interned,
            };
            return Value{ .tag = .string, .data = .{ .string = box } };
        }
        
        // Create new interned string
        const php_string = try types.PHPString.init(self.allocator, str);
        const key = try self.allocator.dupe(u8, str);
        try self.string_intern_pool.put(key, php_string);
        
        const box = try self.allocator.create(types.gc.Box(*types.PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_string,
        };
        
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
        
        try self.error_context.addError(
            self.allocator,
            .fatal_error, // Map exception type to error type
            exception.message.data,
            exception.file.data,
            exception.line,
            stack_trace
        );
        
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
        const current_frame = try exceptions.StackFrame.init(
            self.allocator,
            "main",
            self.current_file,
            self.current_line,
            0
        );
        try stack_frames.append(self.allocator, current_frame);
        
        // Add call stack frames
        for (self.call_stack.items) |frame| {
            const stack_frame = try exceptions.StackFrame.init(
                self.allocator,
                frame.function_name,
                frame.file,
                frame.line,
                0
            );
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
    
    pub fn getClass(self: *VM, name: []const u8) ?*types.PHPClass {
        return self.classes.get(name);
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
        
        // Call constructor if it exists
        if (class.hasMethod("__construct")) {
            _ = try self.callObjectMethod(value, "__construct", &[_]Value{});
        }
        
        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        
        return value;
    }
    
    fn initializeObjectProperties(self: *VM, object: *types.PHPObject, class: *types.PHPClass) !void {
        _ = self; // Unused in this simplified implementation
        var prop_iterator = class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                try object.setProperty(entry.key_ptr.*, default_val);
            }
        }
    }
    
    fn initializeObjectPropertiesOptimized(self: *VM, object: *types.PHPObject, class: *types.PHPClass) !void {
        _ = self; // Unused in this simplified implementation
        // Pre-allocate property map with expected size
        const expected_size = class.properties.count();
        try object.properties.ensureTotalCapacity(expected_size);
        
        var prop_iterator = class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                // Use putAssumeCapacity for better performance
                object.properties.putAssumeCapacity(entry.key_ptr.*, default_val);
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
        
        // Push call frame for better error reporting
        const full_method_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ object.class.name.data, method_name });
        defer self.allocator.free(full_method_name);
        
        try self.pushCallFrame(full_method_name, self.current_file, self.current_line);
        defer self.popCallFrame();
        
        const result = try object.callMethod(self, method_name, args);
        
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
        return object.getProperty(property_name) catch |err| switch (err) {
            error.UndefinedProperty => {
                const exception = try ExceptionFactory.createUndefinedPropertyError(self.allocator, object.class.name.data, property_name, self.current_file, self.current_line);
                return self.throwException(exception);
            },
            else => return err,
        };
    }
    
    pub fn setObjectProperty(self: *VM, object_value: Value, property_name: []const u8, value: Value) !void {
        if (object_value.tag != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property assignment on non-object", self.current_file, self.current_line);
            _ = try self.throwException(exception);
            return;
        }
        
        const object = object_value.data.object.data;
        object.setProperty(property_name, value) catch |err| switch (err) {
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
        defer bound_args.deinit();
        
        // Type check arguments
        for (function.parameters, 0..) |param, i| {
            if (i < args.len) {
                try param.validateType(args[i]);
            }
        }
        
        // Create new environment for function execution
        // This would execute the function body in a real implementation
        const result = Value.initNull();
        
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
        
        const result = try closure.call(self, args);
        
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
        
        const result = try arrow_function.call(self, args);
        
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
    
    fn evaluateBinaryOperation(self: *VM, left: Value, op: Token.Tag, right: Value) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }
        
        return switch (op) {
            .plus => self.evaluateAddition(left, right),
            .minus => self.evaluateSubtraction(left, right),
            .asterisk => self.evaluateMultiplication(left, right),
            .slash => self.evaluateDivision(left, right),
            .dot => self.evaluateConcatenation(left, right),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Unsupported binary operator", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        };
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
        return switch (value.tag) {
            .integer => .{ 
                .str = try std.fmt.allocPrint(self.allocator, "{d}", .{value.data.integer}), 
                .needs_free = true 
            },
            .float => .{ 
                .str = try std.fmt.allocPrint(self.allocator, "{d}", .{value.data.float}), 
                .needs_free = true 
            },
            .string => .{ 
                .str = value.data.string.data.data, 
                .needs_free = false 
            },
            .boolean => .{ 
                .str = if (value.data.boolean) "1" else "", 
                .needs_free = false 
            },
            .null => .{ 
                .str = "", 
                .needs_free = false 
            },
            else => .{ 
                .str = "Object", 
                .needs_free = false 
            },
        };
    }

    fn eval(self: *VM, node: ast.Node.Index) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }
        
        const ast_node = self.context.nodes.items[node];

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
            .variable => {
                const name_id = ast_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];
                return self.global.get(name) orelse {
                    const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, name, self.current_file, self.current_line);
                    return self.throwException(exception);
                };
            },
            .assignment => {
                const target_node = self.context.nodes.items[ast_node.data.assignment.target];
                if (target_node.tag != .variable) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid assignment target", self.current_file, self.current_line);
                    return self.throwException(exception);
                }

                const value = try self.eval(ast_node.data.assignment.value);

                if (target_node.tag == .variable) {
                    const name_id = target_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    try self.global.set(name, value);
                }

                return value;
            },
            .echo_stmt => {
                const value = try self.eval(ast_node.data.echo_stmt.expr);
                defer self.releaseValue(value);
                
                try value.print();
                std.debug.print("\n", .{});
                return Value.initNull();
            },
            .function_call => {
                return self.evaluateFunctionCall(ast_node.data.function_call);
            },
            .method_call => {
                return self.evaluateMethodCall(ast_node.data.method_call);
            },
            .array_init => {
                return self.evaluateArrayInit(ast_node.data.array_init);
            },
            .class_decl => {
                return self.evaluateClassDeclaration(ast_node.data.container_decl);
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
            .foreach_stmt => {
                return self.evaluateForeachStatement(ast_node.data.foreach_stmt);
            },
            .return_stmt => {
                return self.evaluateReturnStatement(ast_node.data.return_stmt);
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Unsupported AST node type", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }
    }
    
    fn releaseValue(self: *VM, value: Value) void {
        switch (value.tag) {
            .string => value.data.string.release(self.allocator),
            .array => value.data.array.release(self.allocator),
            .object => value.data.object.release(self.allocator),
            .resource => value.data.resource.release(self.allocator),
            .user_function => value.data.user_function.release(self.allocator),
            .closure => value.data.closure.release(self.allocator),
            .arrow_function => value.data.arrow_function.release(self.allocator),
            else => {},
        }
    }
    
    fn evaluateFunctionCall(self: *VM, call_data: anytype) anyerror!Value {
        const name_node = self.context.nodes.items[call_data.name];

        if (name_node.tag != .variable) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid function name", self.current_file, self.current_line);
            return self.throwException(exception);
        }
        
        const name_id = name_node.data.variable.name;
        const name = self.context.string_pool.keys()[name_id];

        // Check if it's a class instantiation (new ClassName())
        if (std.mem.eql(u8, name, "new")) {
            return self.evaluateObjectInstantiation(call_data);
        }

        // Evaluate arguments
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

        // First check if it's a standard library function (optimized lookup)
        if (self.stdlib.getFunction(name)) |builtin_func| {
            return builtin_func.call(self, args.items);
        }

        // Then check global functions
        const function_val = self.global.get(name) orelse {
            const exception = try ExceptionFactory.createUndefinedFunctionError(self.allocator, name, self.current_file, self.current_line);
            return self.throwException(exception);
        };

        return switch (function_val.tag) {
            .builtin_function => {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(function_val.data.builtin_function));
                return function(self, args.items);
            },
            .user_function => self.callUserFunction(function_val.data.user_function.data, args.items),
            .closure => self.callClosure(function_val.data.closure.data, args.items),
            .arrow_function => self.callArrowFunction(function_val.data.arrow_function.data, args.items),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Not a callable function", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        };
    }
    
    fn evaluateObjectInstantiation(self: *VM, call_data: anytype) !Value {
        if (call_data.args.len == 0) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Missing class name for instantiation", self.current_file, self.current_line);
            return self.throwException(exception);
        }
        
        const class_name_node = self.context.nodes.items[call_data.args[0]];
        if (class_name_node.tag != .variable) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid class name", self.current_file, self.current_line);
            return self.throwException(exception);
        }
        
        const class_name_id = class_name_node.data.variable.name;
        const class_name = self.context.string_pool.keys()[class_name_id];
        
        return self.createObject(class_name);
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
        
        return self.callObjectMethod(target_value, method_name, args.items);
    }
    
    fn evaluateArrayInit(self: *VM, array_data: anytype) !Value {
        const php_array_value = try Value.initArrayWithManager(&self.memory_manager);
        const php_array = php_array_value.data.array.data;
        
        // Pre-allocate capacity for better performance
        if (self.optimization_flags.enable_memory_pooling) {
            try php_array.elements.ensureTotalCapacity(array_data.elements.len);
        }
        
        for (array_data.elements, 0..) |item_node_idx, i| {
            const value = try self.eval(item_node_idx);
            const key = types.ArrayKey{ .integer = @intCast(i) };
            try php_array.set(key, value);
        }
        
        return php_array_value;
    }
    
    // Missing evaluation methods implementation
    fn evaluateArrowFunction(self: *VM, arrow_func: anytype) !Value {
        // Arrow functions are similar to closures but with automatic variable capture
        const closure_data = try self.allocator.create(types.Closure);
        closure_data.* = types.Closure{
            .function = types.UserFunction{
                .name = try types.PHPString.init(self.allocator, "arrow_function"),
                .parameters = &[_]types.Method.Parameter{}, // TODO: Convert arrow_func.params
                .return_type = null,
                .attributes = &[_]types.Attribute{},
                .body = @constCast(@ptrCast(&arrow_func.body)),
                .is_variadic = false,
                .min_args = 0,
                .max_args = null,
            },
            .captured_vars = std.StringHashMap(Value).init(self.allocator),
            .is_static = arrow_func.is_static,
        };
        
        const closure_box = try self.memory_manager.allocClosure(closure_data.*);
        return Value{ .tag = .closure, .data = .{ .closure = closure_box } };
    }

    fn evaluateBinaryExpression(self: *VM, binary_expr: anytype) !Value {
        const left = try self.eval(binary_expr.lhs);
        defer self.releaseValue(left);
        const right = try self.eval(binary_expr.rhs);
        defer self.releaseValue(right);
        
        return self.evaluateBinaryOp(binary_expr.op, left, right);
    }

    fn evaluateUnaryExpression(self: *VM, unary_expr: anytype) !Value {
        const operand = try self.eval(unary_expr.expr);
        defer self.releaseValue(operand);
        
        return self.evaluateUnaryOp(unary_expr.op, operand);
    }

    fn evaluateTernaryExpression(self: *VM, ternary_expr: anytype) !Value {
        const condition = try self.eval(ternary_expr.cond);
        defer self.releaseValue(condition);
        
        const is_truthy = condition.toBool();
        
        if (is_truthy) {
            if (ternary_expr.then_expr) |then_expr| {
                return self.eval(then_expr);
            } else {
                return condition; // Elvis operator: condition ?: else_expr
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
                        try cloned_object.setProperty(prop_name.data, value);
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
        
        const user_func = try self.allocator.create(types.UserFunction);
        user_func.* = types.UserFunction{
            .name = try types.PHPString.init(self.allocator, name),
            .parameters = &[_]types.Method.Parameter{}, // TODO: Convert func_decl.params
            .return_type = null,
            .attributes = &[_]types.Attribute{}, // TODO: Convert func_decl.attributes
            .body = @constCast(@ptrCast(&func_decl.body)),
            .is_variadic = false,
            .min_args = 0,
            .max_args = null,
        };
        
        const func_box = try self.memory_manager.allocUserFunction(user_func.*);
        const func_value = Value{ .tag = .user_function, .data = .{ .user_function = func_box } };
        try self.global.set(name, func_value);
        
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
        
        while (true) {
            const condition = try self.eval(while_stmt.condition);
            defer self.releaseValue(condition);
            
            if (!condition.toBool()) break;
            
            self.releaseValue(last_val);
            last_val = try self.eval(while_stmt.body);
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
        
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            
            // Set key variable if specified
            if (foreach_stmt.key) |key_idx| {
                const key_node = self.context.nodes.items[key_idx];
                if (key_node.tag == .variable) {
                    const key_name_id = key_node.data.variable.name;
                    const key_name = self.context.string_pool.keys()[key_name_id];
                    const key_value = switch (key) {
                        .integer => |i| Value.initInt(i),
                        .string => |s| try Value.initStringWithManager(&self.memory_manager, s.data),
                    };
                    try self.global.set(key_name, key_value);
                }
            }
            
            // Set value variable
            const value_node = self.context.nodes.items[foreach_stmt.value];
            if (value_node.tag == .variable) {
                const value_name_id = value_node.data.variable.name;
                const value_name = self.context.string_pool.keys()[value_name_id];
                try self.global.set(value_name, value);
            }
            
            // Execute body
            self.releaseValue(last_val);
            last_val = try self.eval(foreach_stmt.body);
        }
        
        return last_val;
    }

    fn evaluateReturnStatement(self: *VM, return_stmt: anytype) !Value {
        if (return_stmt.expr) |expr| {
            return self.eval(expr);
        } else {
            return Value.initNull();
        }
    }

    fn evaluateBinaryOp(self: *VM, op: Token.Tag, left: Value, right: Value) !Value {
        switch (op) {
            .plus => return self.addValues(left, right),
            .minus => return self.subtractValues(left, right),
            .asterisk => return self.multiplyValues(left, right),
            .slash => return self.divideValues(left, right),
            .percent => return self.moduloValues(left, right),
            .equal_equal => return Value.initBool(false), // TODO: implement proper comparison
            .bang_equal => return Value.initBool(true), // TODO: implement proper comparison
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
            else => {
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
        const left_str = try left.toString(self.allocator);
        defer self.allocator.free(left_str);
        const right_str = try right.toString(self.allocator);
        defer self.allocator.free(right_str);
        
        const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_str, right_str });
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
    fn evaluateClassDeclaration(self: *VM, class_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }
        
        const class_name = self.context.string_pool.keys()[class_data.name];
        const php_class_name = try types.PHPString.init(self.allocator, class_name);
        
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
        
        // Process implements clause (simplified - just skip for now)
        for (class_data.implements) |interface_idx| {
            _ = interface_idx; // Skip interface processing for now
        }
        
        // Process class members
        for (class_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];
            
            switch (member_node.tag) {
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
        
        // Register the class
        const class_ptr = try self.allocator.create(types.PHPClass);
        class_ptr.* = php_class;
        try self.defineClass(class_name, class_ptr);
        
        return Value.initNull();
    }
    
    fn processMethodDeclaration(self: *VM, class: *types.PHPClass, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];
        const php_method_name = try types.PHPString.init(self.allocator, method_name);
        
        // Create method
        var method = types.Method.init(php_method_name);
        
        // Set method modifiers
        method.modifiers = .{
            .is_static = method_data.modifiers.is_static,
            .is_final = method_data.modifiers.is_final,
            .is_abstract = method_data.modifiers.is_abstract,
            .visibility = if (method_data.modifiers.is_public) .public 
                         else if (method_data.modifiers.is_protected) .protected 
                         else .private,
        };
        
        // Process parameters
        var parameters = try self.allocator.alloc(types.Method.Parameter, method_data.params.len);
        for (method_data.params, 0..) |param_idx, i| {
            const param_node = self.context.nodes.items[param_idx];
            if (param_node.tag == .parameter) {
                const param_data = param_node.data.parameter;
                const param_name = self.context.string_pool.keys()[param_data.name];
                const php_param_name = try types.PHPString.init(self.allocator, param_name);
                
                parameters[i] = types.Method.Parameter.init(php_param_name);
                parameters[i].is_variadic = param_data.is_variadic;
                parameters[i].is_reference = param_data.is_reference;
                
                // Process parameter type if present
                if (param_data.type) |type_idx| {
                    // Would process type information here
                    _ = type_idx;
                }
            }
        }
        method.parameters = parameters;
        
        // Set method body
        if (method_data.body) |body_idx| {
            method.body = @ptrFromInt(body_idx);
        }
        
        // Add method to class (simplified - just store in methods map)
        try class.methods.put(method_name, method);
    }
    
    fn processPropertyDeclaration(self: *VM, class: *types.PHPClass, property_data: anytype) !void {
        const property_name = self.context.string_pool.keys()[property_data.name];
        
        // Create property
        const property_name_str = try types.PHPString.init(self.allocator, property_name);
        var property = types.Property.init(property_name_str);
        
        // Set property modifiers
        property.modifiers = .{
            .is_static = property_data.modifiers.is_static,
            .is_readonly = property_data.modifiers.is_readonly,
            .visibility = if (property_data.modifiers.is_public) .public 
                         else if (property_data.modifiers.is_protected) .protected 
                         else .private,
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
        var parameters = try self.allocator.alloc(types.Method.Parameter, closure_data.params.len);
        var min_args: u32 = 0;
        var max_args: ?u32 = @intCast(closure_data.params.len);
        var is_variadic = false;
        
        for (closure_data.params, 0..) |param_idx, i| {
            const param_node = self.context.nodes.items[param_idx];
            if (param_node.tag == .parameter) {
                const param_data = param_node.data.parameter;
                const param_name = self.context.string_pool.keys()[param_data.name];
                const php_param_name = try types.PHPString.init(self.allocator, param_name);
                
                parameters[i] = types.Method.Parameter.init(php_param_name);
                parameters[i].is_variadic = param_data.is_variadic;
                parameters[i].is_reference = param_data.is_reference;
                
                if (param_data.is_variadic) {
                    is_variadic = true;
                    max_args = null; // Unlimited for variadic functions
                }
                
                // Count required parameters (those without default values)
                if (parameters[i].default_value == null and !param_data.is_variadic) {
                    min_args += 1;
                }
            }
        }
        
        user_function.parameters = parameters;
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
            if (capture_node.tag == .variable) {
                const var_name = self.context.string_pool.keys()[capture_node.data.variable.name];
                const var_value = self.global.get(var_name) orelse Value.initNull();
                try captured_vars_list.append(self.allocator, .{ .name = var_name, .value = var_value });
            }
        }
        
        return self.createClosure(user_function, captured_vars_list.items);
    }
};