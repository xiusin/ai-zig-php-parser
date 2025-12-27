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
        };
        vm.global.* = Environment.init(allocator);
        vm.reflection_system = ReflectionSystem.init(allocator, vm);

        try vm.defineBuiltin("count", countFn);
        try vm.defineBuiltin("call_user_func", callUserFuncFn);
        try vm.defineBuiltin("call_user_func_array", callUserFuncArrayFn);
        try vm.defineBuiltin("is_callable", isCallableFn);
        
        // Reflection functions
        try vm.defineBuiltin("class_exists", classExistsFn);
        try vm.defineBuiltin("method_exists", methodExistsFn);
        try vm.defineBuiltin("property_exists", propertyExistsFn);
        try vm.defineBuiltin("get_class", getClassFn);
        try vm.defineBuiltin("get_class_methods", getClassMethodsFn);
        try vm.defineBuiltin("get_class_vars", getClassVarsFn);
        try vm.defineBuiltin("get_object_vars", getObjectVarsFn);
        try vm.defineBuiltin("is_a", isAFn);
        try vm.defineBuiltin("is_subclass_of", isSubclassOfFn);

        // Register all standard library functions
        try vm.registerStandardLibraryFunctions();

        return vm;
    }

    pub fn deinit(self: *VM) void {
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
    
    pub fn registerStandardLibraryFunctions(self: *VM) !void {
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
    }
    
    pub fn setCurrentLocation(self: *VM, file: []const u8, line: u32) void {
        self.current_file = file;
        self.current_line = line;
    }
    
    pub fn throwException(self: *VM, exception: *PHPException) !Value {
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
        
        // Initialize properties with default values
        var prop_iterator = class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                try object.setProperty(entry.key_ptr.*, default_val);
            }
        }
        
        // Call constructor if it exists
        if (class.hasMethod("__construct")) {
            _ = try self.callObjectMethod(value, "__construct", &[_]Value{});
        }
        
        return value;
    }
    
    pub fn callObjectMethod(self: *VM, object_value: Value, method_name: []const u8, args: []const Value) !Value {
        if (object_value.tag != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Method call on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }
        
        const object = object_value.data.object.data;
        return object.callMethod(self, method_name, args);
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
        return Value.initNull();
    }
    
    pub fn callClosure(self: *VM, closure: *types.Closure, args: []const Value) !Value {
        return closure.call(self, args);
    }
    
    pub fn callArrowFunction(self: *VM, arrow_function: *types.ArrowFunction, args: []const Value) !Value {
        return arrow_function.call(self, args);
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
        return switch (op) {
            .plus => {
                // Addition
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initInt(left.data.integer + right.data.integer);
                } else if (left.tag == .float and right.tag == .float) {
                    return Value.initFloat(left.data.float + right.data.float);
                } else if (left.tag == .integer and right.tag == .float) {
                    return Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) + right.data.float);
                } else if (left.tag == .float and right.tag == .integer) {
                    return Value.initFloat(left.data.float + @as(f64, @floatFromInt(right.data.integer)));
                } else if (left.tag == .string and right.tag == .string) {
                    // String concatenation - use proper string concatenation instead of allocPrint
                    const left_str = left.data.string.data.data;
                    const right_str = right.data.string.data.data;
                    const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_str, right_str });
                    defer self.allocator.free(result); // Safe to free - initStringWithManager will copy
                    return Value.initStringWithManager(&self.memory_manager, result);
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for addition", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .minus => {
                // Subtraction
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initInt(left.data.integer - right.data.integer);
                } else if (left.tag == .float and right.tag == .float) {
                    return Value.initFloat(left.data.float - right.data.float);
                } else if (left.tag == .integer and right.tag == .float) {
                    return Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) - right.data.float);
                } else if (left.tag == .float and right.tag == .integer) {
                    return Value.initFloat(left.data.float - @as(f64, @floatFromInt(right.data.integer)));
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for subtraction", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .asterisk => {
                // Multiplication
                if (left.tag == .integer and right.tag == .integer) {
                    return Value.initInt(left.data.integer * right.data.integer);
                } else if (left.tag == .float and right.tag == .float) {
                    return Value.initFloat(left.data.float * right.data.float);
                } else if (left.tag == .integer and right.tag == .float) {
                    return Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) * right.data.float);
                } else if (left.tag == .float and right.tag == .integer) {
                    return Value.initFloat(left.data.float * @as(f64, @floatFromInt(right.data.integer)));
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for multiplication", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .slash => {
                // Division
                if (left.tag == .integer and right.tag == .integer) {
                    if (right.data.integer == 0) {
                        const exception = try ExceptionFactory.createDivisionByZeroError(self.allocator, self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                    return Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) / @as(f64, @floatFromInt(right.data.integer)));
                } else if (left.tag == .float and right.tag == .float) {
                    if (right.data.float == 0.0) {
                        const exception = try ExceptionFactory.createDivisionByZeroError(self.allocator, self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                    return Value.initFloat(left.data.float / right.data.float);
                } else if (left.tag == .integer and right.tag == .float) {
                    if (right.data.float == 0.0) {
                        const exception = try ExceptionFactory.createDivisionByZeroError(self.allocator, self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                    return Value.initFloat(@as(f64, @floatFromInt(left.data.integer)) / right.data.float);
                } else if (left.tag == .float and right.tag == .integer) {
                    if (right.data.integer == 0) {
                        const exception = try ExceptionFactory.createDivisionByZeroError(self.allocator, self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                    return Value.initFloat(left.data.float / @as(f64, @floatFromInt(right.data.integer)));
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operands for division", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .dot => {
                // String concatenation
                const left_result = try self.valueToString(left);
                defer if (left_result.needs_free) self.allocator.free(left_result.str);
                
                const right_result = try self.valueToString(right);
                defer if (right_result.needs_free) self.allocator.free(right_result.str);
                
                const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_result.str, right_result.str });
                defer self.allocator.free(result); // Safe to free - initStringWithManager will copy
                
                return Value.initStringWithManager(&self.memory_manager, result);
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Unsupported binary operator", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        };
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
        const ast_node = self.context.nodes.items[node];

        switch (ast_node.tag) {
            .root => {
                var last_val = Value.initNull();
                for (ast_node.data.root.stmts) |stmt| {
                    // Release the previous value before evaluating the next one
                    switch (last_val.tag) {
                        .string => last_val.data.string.release(self.allocator),
                        .array => last_val.data.array.release(self.allocator),
                        .object => last_val.data.object.release(self.allocator),
                        .resource => last_val.data.resource.release(self.allocator),
                        .user_function => last_val.data.user_function.release(self.allocator),
                        .closure => last_val.data.closure.release(self.allocator),
                        .arrow_function => last_val.data.arrow_function.release(self.allocator),
                        else => {},
                    }
                    last_val = try self.eval(stmt);
                }
                return last_val;
            },
            .class_decl => {
                const class_data = ast_node.data.container_decl;
                const class_name = self.context.string_pool.keys()[class_data.name];
                
                // Create PHP string for class name
                const php_class_name = try types.PHPString.init(self.allocator, class_name);
                
                // Create the class
                const php_class = try self.allocator.create(types.PHPClass);
                php_class.* = types.PHPClass.init(self.allocator, php_class_name);
                
                // Set modifiers
                php_class.modifiers.is_abstract = class_data.modifiers.is_abstract;
                php_class.modifiers.is_final = class_data.modifiers.is_final;
                php_class.modifiers.is_readonly = class_data.modifiers.is_readonly;
                
                // Process class members (properties and methods)
                for (class_data.members) |member_idx| {
                    const member_node = self.context.nodes.items[member_idx];
                    switch (member_node.tag) {
                        .property_decl => {
                            const prop_data = member_node.data.property_decl;
                            const prop_name = self.context.string_pool.keys()[prop_data.name];
                            const php_prop_name = try types.PHPString.init(self.allocator, prop_name);
                            
                            var property = types.Property.init(php_prop_name);
                            property.modifiers.visibility = if (prop_data.modifiers.is_public) .public 
                                                          else if (prop_data.modifiers.is_protected) .protected 
                                                          else .private;
                            property.modifiers.is_static = prop_data.modifiers.is_static;
                            property.modifiers.is_readonly = prop_data.modifiers.is_readonly;
                            property.modifiers.is_final = prop_data.modifiers.is_final;
                            
                            // Set default value if provided
                            if (prop_data.default_value) |default_idx| {
                                property.default_value = try self.eval(default_idx);
                            }
                            
                            try php_class.properties.put(prop_name, property);
                        },
                        .method_decl => {
                            const method_data = member_node.data.method_decl;
                            const method_name = self.context.string_pool.keys()[method_data.name];
                            const php_method_name = try types.PHPString.init(self.allocator, method_name);
                            
                            var method = types.Method.init(php_method_name);
                            method.modifiers.visibility = if (method_data.modifiers.is_public) .public 
                                                        else if (method_data.modifiers.is_protected) .protected 
                                                        else .private;
                            method.modifiers.is_static = method_data.modifiers.is_static;
                            method.modifiers.is_final = method_data.modifiers.is_final;
                            method.modifiers.is_abstract = method_data.modifiers.is_abstract;
                            
                            // Store method body reference (simplified)
                            method.body = if (method_data.body) |body_idx| @ptrFromInt(body_idx) else null;
                            
                            try php_class.methods.put(method_name, method);
                        },
                        else => {
                            // Skip other member types for now
                        },
                    }
                }
                
                // Register the class
                try self.defineClass(class_name, php_class);
                
                return Value.initNull();
            },
            .function_call => {
                const name_node = self.context.nodes.items[ast_node.data.function_call.name];

                if (name_node.tag != .variable) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid function name", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
                const name_id = name_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];

                // Check if it's a class instantiation (new ClassName())
                if (std.mem.eql(u8, name, "new")) {
                    if (ast_node.data.function_call.args.len == 0) {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Missing class name for instantiation", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                    
                    const class_name_node = self.context.nodes.items[ast_node.data.function_call.args[0]];
                    if (class_name_node.tag != .variable) {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid class name", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                    
                    const class_name_id = class_name_node.data.variable.name;
                    const class_name = self.context.string_pool.keys()[class_name_id];
                    
                    return self.createObject(class_name);
                }

                // First check if it's a standard library function
                if (self.stdlib.getFunction(name)) |builtin_func| {
                    var args = try std.ArrayList(Value).initCapacity(self.allocator, 0);
                    defer args.deinit(self.allocator);

                    for (ast_node.data.function_call.args) |arg_node_idx| {
                        try args.append(self.allocator, try self.eval(arg_node_idx));
                    }

                    return builtin_func.call(self, args.items);
                }

                // Then check global functions
                const function_val = self.global.get(name) orelse {
                    const exception = try ExceptionFactory.createUndefinedFunctionError(self.allocator, name, self.current_file, self.current_line);
                    return self.throwException(exception);
                };

                var args = try std.ArrayList(Value).initCapacity(self.allocator, 0);
                defer args.deinit(self.allocator);

                for (ast_node.data.function_call.args) |arg_node_idx| {
                    try args.append(self.allocator, try self.eval(arg_node_idx));
                }

                return switch (function_val.tag) {
                    .builtin_function => {
                        const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(function_val.data.builtin_function));
                        return function(self, args.items);
                    },
                    .user_function => {
                        return self.callUserFunction(function_val.data.user_function.data, args.items);
                    },
                    .closure => {
                        return self.callClosure(function_val.data.closure.data, args.items);
                    },
                    .arrow_function => {
                        return self.callArrowFunction(function_val.data.arrow_function.data, args.items);
                    },
                    else => {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Not a callable function", self.current_file, self.current_line);
                        return self.throwException(exception);
                    },
                };
            },
            .method_call => {
                const method_data = ast_node.data.method_call;
                const target_value = try self.eval(method_data.target);
                const method_name = self.context.string_pool.keys()[method_data.method_name];
                
                var args = try std.ArrayList(Value).initCapacity(self.allocator, 0);
                defer args.deinit(self.allocator);

                for (method_data.args) |arg_node_idx| {
                    try args.append(self.allocator, try self.eval(arg_node_idx));
                }
                
                return self.callObjectMethod(target_value, method_name, args.items);
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
            .variable => {
                const name_id = ast_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];
                return self.global.get(name) orelse {
                    const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, name, self.current_file, self.current_line);
                    return self.throwException(exception);
                };
            },
            .literal_string => {
                const str_id = ast_node.data.literal_string.value;
                const str_val = self.context.string_pool.keys()[str_id];
                return Value.initStringWithManager(&self.memory_manager, str_val);
            },
            .echo_stmt => {
                const value = try self.eval(ast_node.data.echo_stmt.expr);
                defer {
                    // Release the value after printing
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
                try value.print();
                std.debug.print("\n", .{});
                return Value.initNull();
            },
            .array_init => {
                const php_array_value = try Value.initArrayWithManager(&self.memory_manager);
                const php_array = php_array_value.data.array.data;
                
                for (ast_node.data.array_init.elements, 0..) |item_node_idx, i| {
                    const value = try self.eval(item_node_idx);
                    const key = types.ArrayKey{ .integer = @intCast(i) };
                    try php_array.set(key, value);
                }
                
                return php_array_value;
            },
            .literal_int => {
                return Value.initInt(ast_node.data.literal_int.value);
            },
            .literal_float => {
                return Value.initFloat(ast_node.data.literal_float.value);
            },
            .try_stmt => {
                const try_data = ast_node.data.try_stmt;
                
                // Enter try-catch context
                try self.enterTryCatch();
                defer self.exitTryCatch();
                
                var result = Value.initNull();
                var exception_caught = false;
                
                // Execute try block
                result = self.eval(try_data.body) catch |err| blk: {
                    // Check if it's a PHP exception
                    if (err == error.UncaughtException) {
                        // Try to match with catch clauses
                        for (try_data.catch_clauses) |catch_idx| {
                            const catch_node = self.context.nodes.items[catch_idx];
                            if (catch_node.tag == .catch_clause) {
                                const catch_data = catch_node.data.catch_clause;
                                
                                // For now, catch all exceptions (simplified)
                                exception_caught = true;
                                
                                // Set exception variable if specified
                                if (catch_data.variable) |var_idx| {
                                    const var_node = self.context.nodes.items[var_idx];
                                    if (var_node.tag == .variable) {
                                        const var_name = self.context.string_pool.keys()[var_node.data.variable.name];
                                        // Create exception object (simplified)
                                        const exception_value = Value.initNull();
                                        try self.global.set(var_name, exception_value);
                                    }
                                }
                                
                                // Execute catch block
                                result = try self.eval(catch_data.body);
                                break;
                            }
                        }
                        
                        if (!exception_caught) {
                            return err; // Re-throw if not caught
                        }
                        
                        break :blk result;
                    } else {
                        return err; // Re-throw non-PHP exceptions
                    }
                };
                
                // Execute finally block if present
                if (try_data.finally_clause) |finally_idx| {
                    const finally_node = self.context.nodes.items[finally_idx];
                    if (finally_node.tag == .finally_clause) {
                        self.executeFinally();
                        _ = try self.eval(finally_node.data.finally_clause.body);
                    }
                }
                
                return result;
            },
            .throw_stmt => {
                const throw_data = ast_node.data.throw_stmt;
                _ = try self.eval(throw_data.expression);
                
                // Create a generic exception (simplified)
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Thrown exception", self.current_file, self.current_line);
                return self.throwException(exception);
            },
            .closure => {
                const closure_data = ast_node.data.closure;
                
                // Create user function from closure data
                const function_name = try types.PHPString.init(self.allocator, "anonymous");
                var user_function = types.UserFunction.init(function_name);
                
                // Process parameters
                var parameters = try self.allocator.alloc(types.Method.Parameter, closure_data.params.len);
                for (closure_data.params, 0..) |param_idx, i| {
                    const param_node = self.context.nodes.items[param_idx];
                    if (param_node.tag == .parameter) {
                        const param_data = param_node.data.parameter;
                        const param_name = self.context.string_pool.keys()[param_data.name];
                        const php_param_name = try types.PHPString.init(self.allocator, param_name);
                        
                        parameters[i] = types.Method.Parameter.init(php_param_name);
                        parameters[i].is_variadic = param_data.is_variadic;
                        parameters[i].is_reference = param_data.is_reference;
                        
                        // Set default value if provided
                        // This would be implemented with proper AST evaluation
                    }
                }
                user_function.parameters = parameters;
                user_function.body = @ptrFromInt(closure_data.body);
                
                // Create closure with captured variables
                var captured_vars_list = try std.ArrayList(CapturedVar).initCapacity(self.allocator, 0);
                defer captured_vars_list.deinit(self.allocator);
                
                // Process capture list
                for (closure_data.captures) |capture_idx| {
                    const capture_node = self.context.nodes.items[capture_idx];
                    if (capture_node.tag == .variable) {
                        const var_name = self.context.string_pool.keys()[capture_node.data.variable.name];
                        const var_value = self.global.get(var_name) orelse Value.initNull();
                        try captured_vars_list.append(self.allocator, .{ .name = var_name, .value = var_value });
                    }
                }
                
                return self.createClosure(user_function, captured_vars_list.items);
            },
            .arrow_function => {
                const arrow_data = ast_node.data.arrow_function;
                
                // Process parameters
                var parameters = try self.allocator.alloc(types.Method.Parameter, arrow_data.params.len);
                for (arrow_data.params, 0..) |param_idx, i| {
                    const param_node = self.context.nodes.items[param_idx];
                    if (param_node.tag == .parameter) {
                        const param_data = param_node.data.parameter;
                        const param_name = self.context.string_pool.keys()[param_data.name];
                        const php_param_name = try types.PHPString.init(self.allocator, param_name);
                        
                        parameters[i] = types.Method.Parameter.init(php_param_name);
                    }
                }
                
                return self.createArrowFunction(parameters, @ptrFromInt(arrow_data.body));
            },
            .function_decl => {
                const func_data = ast_node.data.function_decl;
                const func_name = self.context.string_pool.keys()[func_data.name];
                const php_func_name = try types.PHPString.init(self.allocator, func_name);
                
                var user_function = types.UserFunction.init(php_func_name);
                
                // Process parameters
                var parameters = try self.allocator.alloc(types.Method.Parameter, func_data.params.len);
                var min_args: u32 = 0;
                var max_args: ?u32 = @intCast(func_data.params.len);
                var is_variadic = false;
                
                for (func_data.params, 0..) |param_idx, i| {
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
                user_function.body = @ptrFromInt(func_data.body);
                user_function.is_variadic = is_variadic;
                user_function.min_args = min_args;
                user_function.max_args = max_args;
                
                // Store function in global scope using memory manager
                const box = try self.memory_manager.allocUserFunction(user_function);
                const function_value = Value{ .tag = .user_function, .data = .{ .user_function = box } };
                try self.global.set(func_name, function_value);
                
                return Value.initNull();
            },
            .pipe_expr => {
                const pipe_data = ast_node.data.pipe_expr;
                const left_value = try self.eval(pipe_data.left);
                const right_value = try self.eval(pipe_data.right);
                
                // Import PHP 8.5 features
                const php85 = @import("php85_features.zig");
                return php85.PipeOperator.evaluate(self, left_value, right_value);
            },
            .clone_with_expr => {
                const clone_data = ast_node.data.clone_with_expr;
                const object_value = try self.eval(clone_data.object);
                const properties_value = try self.eval(clone_data.properties);
                
                if (object_value.tag != .object) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Clone with requires an object", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
                
                if (properties_value.tag != .array) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Clone with requires an array of properties", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
                
                // Import PHP 8.5 features
                const php85 = @import("php85_features.zig");
                const new_object = try php85.CloneWith.cloneWithProperties(self, object_value.data.object.data, properties_value.data.array.data);
                
                return Value.initObjectWithManager(&self.memory_manager, new_object.class);
            },
            .binary_expr => {
                const binary_data = ast_node.data.binary_expr;
                const left_value = try self.eval(binary_data.lhs);
                defer {
                    // Release left value after operation
                    switch (left_value.tag) {
                        .string => left_value.data.string.release(self.allocator),
                        .array => left_value.data.array.release(self.allocator),
                        .object => left_value.data.object.release(self.allocator),
                        .resource => left_value.data.resource.release(self.allocator),
                        .user_function => left_value.data.user_function.release(self.allocator),
                        .closure => left_value.data.closure.release(self.allocator),
                        .arrow_function => left_value.data.arrow_function.release(self.allocator),
                        else => {},
                    }
                }
                
                const right_value = try self.eval(binary_data.rhs);
                defer {
                    // Release right value after operation
                    switch (right_value.tag) {
                        .string => right_value.data.string.release(self.allocator),
                        .array => right_value.data.array.release(self.allocator),
                        .object => right_value.data.object.release(self.allocator),
                        .resource => right_value.data.resource.release(self.allocator),
                        .user_function => right_value.data.user_function.release(self.allocator),
                        .closure => right_value.data.closure.release(self.allocator),
                        .arrow_function => right_value.data.arrow_function.release(self.allocator),
                        else => {},
                    }
                }
                
                return self.evaluateBinaryOperation(left_value, binary_data.op, right_value);
            },
            .block => {
                const block_data = ast_node.data.block;
                var last_val = Value.initNull();
                for (block_data.stmts) |stmt| {
                    // Release the previous value before evaluating the next one
                    switch (last_val.tag) {
                        .string => last_val.data.string.release(self.allocator),
                        .array => last_val.data.array.release(self.allocator),
                        .object => last_val.data.object.release(self.allocator),
                        .resource => last_val.data.resource.release(self.allocator),
                        .user_function => last_val.data.user_function.release(self.allocator),
                        .closure => last_val.data.closure.release(self.allocator),
                        .arrow_function => last_val.data.arrow_function.release(self.allocator),
                        else => {},
                    }
                    last_val = try self.eval(stmt);
                }
                return last_val;
            },
            else => {
                std.debug.print("Unsupported node type: {s}\n", .{@tagName(ast_node.tag)});
                return error.UnsupportedNodeType;
            },
        }
    }
};
