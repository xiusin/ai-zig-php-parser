const std = @import("std");
const api = @import("api.zig");
const ExtensionFunction = api.ExtensionFunction;
const ExtensionClass = api.ExtensionClass;
const Extension = api.Extension;
const ExtensionError = api.ExtensionError;
const SyntaxHooks = api.SyntaxHooks;
const EXTENSION_API_VERSION = api.EXTENSION_API_VERSION;
const GetExtensionFn = api.GetExtensionFn;

/// Loaded dynamic library handle with associated extension
const LoadedLibrary = struct {
    /// Handle to the dynamic library
    lib: std.DynLib,
    /// Pointer to the extension structure
    extension: *const Extension,
    /// Path to the library file (for debugging)
    path: []const u8,
};

/// Extension Registry
/// Manages loaded extensions, registered functions, and classes
pub const ExtensionRegistry = struct {
    allocator: std.mem.Allocator,
    /// Loaded extensions by name
    extensions: std.StringHashMap(*const Extension),
    /// Registered functions by name
    functions: std.StringHashMap(ExtensionFunction),
    /// Registered classes by name
    classes: std.StringHashMap(ExtensionClass),
    /// Syntax hooks from all extensions
    syntax_hooks: std.ArrayList(*const SyntaxHooks),
    /// Built-in function names (to prevent conflicts)
    builtin_functions: std.StringHashMap(void),
    /// Built-in class names (to prevent conflicts)
    builtin_classes: std.StringHashMap(void),
    /// Loaded dynamic libraries (for cleanup)
    loaded_libraries: std.ArrayList(LoadedLibrary),
    /// Track which extensions have been initialized (for lifecycle management)
    initialized_extensions: std.StringHashMap(bool),

    /// Initialize a new extension registry
    pub fn init(allocator: std.mem.Allocator) ExtensionRegistry {
        return ExtensionRegistry{
            .allocator = allocator,
            .extensions = std.StringHashMap(*const Extension).init(allocator),
            .functions = std.StringHashMap(ExtensionFunction).init(allocator),
            .classes = std.StringHashMap(ExtensionClass).init(allocator),
            .syntax_hooks = .empty,
            .builtin_functions = std.StringHashMap(void).init(allocator),
            .builtin_classes = std.StringHashMap(void).init(allocator),
            .loaded_libraries = .empty,
            .initialized_extensions = std.StringHashMap(bool).init(allocator),
        };
    }

    /// Clean up and release all resources
    pub fn deinit(self: *ExtensionRegistry) void {
        // Call shutdown on all loaded extensions
        var ext_iter = self.extensions.iterator();
        while (ext_iter.next()) |entry| {
            const extension = entry.value_ptr.*;
            // Only call shutdown if extension was initialized
            if (self.initialized_extensions.get(extension.info.name)) |initialized| {
                if (initialized) {
                    if (extension.shutdown_fn) |shutdown| {
                        shutdown(@ptrCast(self));
                    }
                }
            }
        }

        // Close all loaded dynamic libraries
        for (self.loaded_libraries.items) |*lib_entry| {
            self.allocator.free(lib_entry.path);
            lib_entry.lib.close();
        }
        self.loaded_libraries.deinit(self.allocator);

        self.extensions.deinit();
        self.functions.deinit();
        self.classes.deinit();
        self.syntax_hooks.deinit(self.allocator);
        self.builtin_functions.deinit();
        self.builtin_classes.deinit();
        self.initialized_extensions.deinit();
    }


    /// Register a built-in function name (to prevent extension conflicts)
    pub fn registerBuiltinFunction(self: *ExtensionRegistry, name: []const u8) !void {
        try self.builtin_functions.put(name, {});
    }

    /// Register a built-in class name (to prevent extension conflicts)
    pub fn registerBuiltinClass(self: *ExtensionRegistry, name: []const u8) !void {
        try self.builtin_classes.put(name, {});
    }

    /// Register an extension function
    /// Returns error if function name already exists
    pub fn registerFunction(self: *ExtensionRegistry, func: ExtensionFunction) ExtensionError!void {
        // Check for conflict with built-in functions
        if (self.builtin_functions.contains(func.name)) {
            return ExtensionError.FunctionAlreadyExists;
        }

        // Check for conflict with already registered extension functions
        if (self.functions.contains(func.name)) {
            return ExtensionError.FunctionAlreadyExists;
        }

        self.functions.put(func.name, func) catch return ExtensionError.OutOfMemory;
    }

    /// Register an extension class
    /// Returns error if class name already exists
    pub fn registerClass(self: *ExtensionRegistry, class: ExtensionClass) ExtensionError!void {
        // Check for conflict with built-in classes
        if (self.builtin_classes.contains(class.name)) {
            return ExtensionError.ClassAlreadyExists;
        }

        // Check for conflict with already registered extension classes
        if (self.classes.contains(class.name)) {
            return ExtensionError.ClassAlreadyExists;
        }

        self.classes.put(class.name, class) catch return ExtensionError.OutOfMemory;
    }

    /// Find a registered extension function by name
    pub fn findFunction(self: *ExtensionRegistry, name: []const u8) ?ExtensionFunction {
        return self.functions.get(name);
    }

    /// Find a registered extension class by name
    pub fn findClass(self: *ExtensionRegistry, name: []const u8) ?ExtensionClass {
        return self.classes.get(name);
    }

    /// Check if a function is registered
    pub fn hasFunction(self: *ExtensionRegistry, name: []const u8) bool {
        return self.functions.contains(name);
    }

    /// Check if a class is registered
    pub fn hasClass(self: *ExtensionRegistry, name: []const u8) bool {
        return self.classes.contains(name);
    }


    /// Load an extension from a dynamic library
    /// Loads a .so (Linux), .dylib (macOS), or .dll (Windows) file
    /// and registers all functions and classes from the extension.
    /// Requirements: 8.1
    pub fn loadExtension(self: *ExtensionRegistry, path: []const u8) ExtensionError!void {
        // Open the dynamic library
        const lib = std.DynLib.open(path) catch |err| {
            switch (err) {
                error.FileNotFound => return ExtensionError.ExtensionNotFound,
                else => return ExtensionError.InvalidExtension,
            }
        };
        errdefer lib.close();

        // Look up the entry point function
        const get_extension_fn = lib.lookup(GetExtensionFn, "zigphp_get_extension") orelse {
            return ExtensionError.InvalidExtension;
        };

        // Get the extension structure
        const extension = get_extension_fn();

        // Verify API version compatibility (Requirements: 15.2, 15.3)
        if (extension.info.api_version > EXTENSION_API_VERSION) {
            return ExtensionError.IncompatibleApiVersion;
        }

        // Check if extension is already loaded
        if (self.extensions.contains(extension.info.name)) {
            return ExtensionError.ExtensionAlreadyLoaded;
        }

        // Initialize the extension (Requirements: 8.2)
        extension.init_fn(@ptrCast(self)) catch return ExtensionError.InitializationFailed;

        // Mark extension as initialized
        self.initialized_extensions.put(extension.info.name, true) catch return ExtensionError.OutOfMemory;

        // Register all functions from the extension
        for (extension.functions) |func| {
            self.registerFunction(func) catch |err| {
                // Rollback: unmark as initialized and call shutdown
                _ = self.initialized_extensions.remove(extension.info.name);
                if (extension.shutdown_fn) |shutdown| {
                    shutdown(@ptrCast(self));
                }
                return err;
            };
        }

        // Register all classes from the extension
        for (extension.classes) |class| {
            self.registerClass(class) catch |err| {
                // Rollback: remove registered functions
                for (extension.functions) |func| {
                    _ = self.functions.remove(func.name);
                }
                _ = self.initialized_extensions.remove(extension.info.name);
                if (extension.shutdown_fn) |shutdown| {
                    shutdown(@ptrCast(self));
                }
                return err;
            };
        }

        // Register syntax hooks if provided
        if (extension.syntax_hooks) |hooks| {
            self.syntax_hooks.append(self.allocator, hooks) catch return ExtensionError.OutOfMemory;
        }

        // Store the extension
        self.extensions.put(extension.info.name, extension) catch return ExtensionError.OutOfMemory;

        // Store the library handle for cleanup
        const path_copy = self.allocator.dupe(u8, path) catch return ExtensionError.OutOfMemory;
        self.loaded_libraries.append(.{
            .lib = lib,
            .extension = extension,
            .path = path_copy,
        }) catch {
            self.allocator.free(path_copy);
            return ExtensionError.OutOfMemory;
        };
    }

    /// Register an extension directly (for statically linked extensions)
    pub fn registerExtension(self: *ExtensionRegistry, extension: *const Extension) ExtensionError!void {
        if (extension.info.api_version > EXTENSION_API_VERSION) {
            return ExtensionError.IncompatibleApiVersion;
        }

        if (self.extensions.contains(extension.info.name)) {
            return ExtensionError.ExtensionAlreadyLoaded;
        }

        extension.init_fn(@ptrCast(self)) catch return ExtensionError.InitializationFailed;

        // Mark extension as initialized
        self.initialized_extensions.put(extension.info.name, true) catch return ExtensionError.OutOfMemory;

        for (extension.functions) |func| {
            self.registerFunction(func) catch |err| {
                _ = self.initialized_extensions.remove(extension.info.name);
                if (extension.shutdown_fn) |shutdown| {
                    shutdown(@ptrCast(self));
                }
                return err;
            };
        }

        for (extension.classes) |class| {
            self.registerClass(class) catch |err| {
                for (extension.functions) |func| {
                    _ = self.functions.remove(func.name);
                }
                _ = self.initialized_extensions.remove(extension.info.name);
                if (extension.shutdown_fn) |shutdown| {
                    shutdown(@ptrCast(self));
                }
                return err;
            };
        }

        if (extension.syntax_hooks) |hooks| {
            self.syntax_hooks.append(self.allocator, hooks) catch return ExtensionError.OutOfMemory;
        }

        self.extensions.put(extension.info.name, extension) catch return ExtensionError.OutOfMemory;
    }

    /// Unload an extension by name
    pub fn unloadExtension(self: *ExtensionRegistry, name: []const u8) bool {
        const extension = self.extensions.get(name) orelse return false;

        // Only call shutdown if extension was initialized
        if (self.initialized_extensions.get(name)) |initialized| {
            if (initialized) {
                if (extension.shutdown_fn) |shutdown| {
                    shutdown(@ptrCast(self));
                }
            }
        }
        _ = self.initialized_extensions.remove(name);

        for (extension.functions) |func| {
            _ = self.functions.remove(func.name);
        }

        for (extension.classes) |class| {
            _ = self.classes.remove(class.name);
        }

        if (extension.syntax_hooks) |hooks| {
            var i: usize = 0;
            while (i < self.syntax_hooks.items.len) {
                if (self.syntax_hooks.items[i] == hooks) {
                    _ = self.syntax_hooks.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        // Close the dynamic library if it was loaded from a file
        var lib_index: ?usize = null;
        for (self.loaded_libraries.items, 0..) |lib_entry, idx| {
            if (lib_entry.extension == extension) {
                lib_index = idx;
                break;
            }
        }
        if (lib_index) |idx| {
            var lib_entry = self.loaded_libraries.orderedRemove(idx);
            self.allocator.free(lib_entry.path);
            lib_entry.lib.close();
        }

        _ = self.extensions.remove(name);
        return true;
    }


    /// Get all registered function names
    pub fn getFunctionNames(self: *ExtensionRegistry, allocator: std.mem.Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.functions.count());
        var i: usize = 0;
        var iter = self.functions.iterator();
        while (iter.next()) |entry| {
            names[i] = entry.key_ptr.*;
            i += 1;
        }
        return names;
    }

    /// Get all registered class names
    pub fn getClassNames(self: *ExtensionRegistry, allocator: std.mem.Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.classes.count());
        var i: usize = 0;
        var iter = self.classes.iterator();
        while (iter.next()) |entry| {
            names[i] = entry.key_ptr.*;
            i += 1;
        }
        return names;
    }

    /// Get all loaded extension names
    pub fn getExtensionNames(self: *ExtensionRegistry, allocator: std.mem.Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.extensions.count());
        var i: usize = 0;
        var iter = self.extensions.iterator();
        while (iter.next()) |entry| {
            names[i] = entry.key_ptr.*;
            i += 1;
        }
        return names;
    }

    /// Get extension info by name
    pub fn getExtensionInfo(self: *ExtensionRegistry, name: []const u8) ?api.ExtensionInfo {
        const extension = self.extensions.get(name) orelse return null;
        return extension.info;
    }

    /// Check if an extension has been initialized
    pub fn isExtensionInitialized(self: *ExtensionRegistry, name: []const u8) bool {
        return self.initialized_extensions.get(name) orelse false;
    }

    /// Get the number of loaded dynamic libraries
    pub fn loadedLibraryCount(self: *ExtensionRegistry) usize {
        return self.loaded_libraries.items.len;
    }

    /// Get the current API version supported by this registry
    pub fn getApiVersion(_: *ExtensionRegistry) u32 {
        return EXTENSION_API_VERSION;
    }

    /// Check if an extension's API version is compatible
    /// Returns true if the extension can be loaded, false otherwise
    /// Requirements: 15.2, 15.3
    pub fn isApiVersionCompatible(_: *ExtensionRegistry, extension_api_version: u32) bool {
        // Extensions with API version greater than current are incompatible
        // Extensions with API version less than or equal to current are compatible
        // (backward compatibility within major versions)
        return extension_api_version <= EXTENSION_API_VERSION;
    }

    /// Check if an extension would be compatible before loading
    /// This is useful for pre-validation without actually loading the extension
    pub fn checkExtensionCompatibility(self: *ExtensionRegistry, extension: *const Extension) ExtensionError!void {
        // Check API version
        if (!self.isApiVersionCompatible(extension.info.api_version)) {
            return ExtensionError.IncompatibleApiVersion;
        }

        // Check if already loaded
        if (self.extensions.contains(extension.info.name)) {
            return ExtensionError.ExtensionAlreadyLoaded;
        }

        // Check for function conflicts
        for (extension.functions) |func| {
            if (self.builtin_functions.contains(func.name) or self.functions.contains(func.name)) {
                return ExtensionError.FunctionAlreadyExists;
            }
        }

        // Check for class conflicts
        for (extension.classes) |class| {
            if (self.builtin_classes.contains(class.name) or self.classes.contains(class.name)) {
                return ExtensionError.ClassAlreadyExists;
            }
        }
    }

    /// Shutdown all extensions without deallocating the registry
    /// This is useful for graceful shutdown before deinit
    /// Requirements: 8.5
    pub fn shutdownAllExtensions(self: *ExtensionRegistry) void {
        var ext_iter = self.extensions.iterator();
        while (ext_iter.next()) |entry| {
            const extension = entry.value_ptr.*;
            // Only call shutdown if extension was initialized
            if (self.initialized_extensions.get(extension.info.name)) |initialized| {
                if (initialized) {
                    if (extension.shutdown_fn) |shutdown| {
                        shutdown(@ptrCast(self));
                    }
                    // Mark as no longer initialized
                    _ = self.initialized_extensions.put(extension.info.name, false) catch {};
                }
            }
        }
    }

    /// Get the count of initialized extensions
    pub fn initializedExtensionCount(self: *ExtensionRegistry) usize {
        var count: usize = 0;
        var iter = self.initialized_extensions.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*) {
                count += 1;
            }
        }
        return count;
    }

    /// Get all syntax hooks
    pub fn getSyntaxHooks(self: *ExtensionRegistry) []const *const SyntaxHooks {
        return self.syntax_hooks.items;
    }

    /// Get the number of registered functions
    pub fn functionCount(self: *ExtensionRegistry) usize {
        return self.functions.count();
    }

    /// Get the number of registered classes
    pub fn classCount(self: *ExtensionRegistry) usize {
        return self.classes.count();
    }

    /// Get the number of loaded extensions
    pub fn extensionCount(self: *ExtensionRegistry) usize {
        return self.extensions.count();
    }
};


// Unit tests
test "ExtensionRegistry init and deinit" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    try std.testing.expectEqual(@as(usize, 0), registry.functionCount());
    try std.testing.expectEqual(@as(usize, 0), registry.classCount());
    try std.testing.expectEqual(@as(usize, 0), registry.extensionCount());
}

test "ExtensionRegistry registerFunction" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 0;
        }
    }.call;
    
    const func = api.createFunction("test_func", callback, 0, 1);
    try registry.registerFunction(func);
    
    try std.testing.expectEqual(@as(usize, 1), registry.functionCount());
    try std.testing.expect(registry.hasFunction("test_func"));
    try std.testing.expect(!registry.hasFunction("nonexistent"));
}

test "ExtensionRegistry registerClass" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const class = api.createClass("TestClass", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{});
    try registry.registerClass(class);
    
    try std.testing.expectEqual(@as(usize, 1), registry.classCount());
    try std.testing.expect(registry.hasClass("TestClass"));
    try std.testing.expect(!registry.hasClass("NonexistentClass"));
}

test "ExtensionRegistry findFunction" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 42;
        }
    }.call;
    
    const func = api.createFunction("my_func", callback, 1, 2);
    try registry.registerFunction(func);
    
    const found = registry.findFunction("my_func");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("my_func", found.?.name);
    try std.testing.expectEqual(@as(u8, 1), found.?.min_args);
    try std.testing.expectEqual(@as(u8, 2), found.?.max_args);
    
    const not_found = registry.findFunction("nonexistent");
    try std.testing.expect(not_found == null);
}

test "ExtensionRegistry findClass" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const class = api.ExtensionClass{
        .name = "MyClass",
        .parent = "BaseClass",
        .interfaces = &[_][]const u8{"Interface1"},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = null,
        .destructor = null,
    };
    try registry.registerClass(class);
    
    const found = registry.findClass("MyClass");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("MyClass", found.?.name);
    try std.testing.expectEqualStrings("BaseClass", found.?.parent.?);
    
    const not_found = registry.findClass("NonexistentClass");
    try std.testing.expect(not_found == null);
}


test "ExtensionRegistry function conflict detection" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 0;
        }
    }.call;
    
    const func1 = api.createFunction("duplicate_func", callback, 0, 1);
    const func2 = api.createFunction("duplicate_func", callback, 0, 2);
    
    try registry.registerFunction(func1);
    
    const result = registry.registerFunction(func2);
    try std.testing.expectError(ExtensionError.FunctionAlreadyExists, result);
}

test "ExtensionRegistry class conflict detection" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const class1 = api.createClass("DuplicateClass", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{});
    const class2 = api.createClass("DuplicateClass", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{});
    
    try registry.registerClass(class1);
    
    const result = registry.registerClass(class2);
    try std.testing.expectError(ExtensionError.ClassAlreadyExists, result);
}

test "ExtensionRegistry builtin function conflict" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    try registry.registerBuiltinFunction("echo");
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 0;
        }
    }.call;
    
    const func = api.createFunction("echo", callback, 0, 1);
    const result = registry.registerFunction(func);
    try std.testing.expectError(ExtensionError.FunctionAlreadyExists, result);
}

test "ExtensionRegistry builtin class conflict" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    try registry.registerBuiltinClass("stdClass");
    
    const class = api.createClass("stdClass", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{});
    const result = registry.registerClass(class);
    try std.testing.expectError(ExtensionError.ClassAlreadyExists, result);
}

test "ExtensionRegistry getFunctionNames" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 0;
        }
    }.call;
    
    try registry.registerFunction(api.createFunction("func_a", callback, 0, 0));
    try registry.registerFunction(api.createFunction("func_b", callback, 0, 0));
    
    const names = try registry.getFunctionNames(std.testing.allocator);
    defer std.testing.allocator.free(names);
    
    try std.testing.expectEqual(@as(usize, 2), names.len);
}

test "ExtensionRegistry getClassNames" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    try registry.registerClass(api.createClass("ClassA", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{}));
    try registry.registerClass(api.createClass("ClassB", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{}));
    
    const names = try registry.getClassNames(std.testing.allocator);
    defer std.testing.allocator.free(names);
    
    try std.testing.expectEqual(@as(usize, 2), names.len);
}

// Force test discovery - reference all tests
comptime {
    _ = @import("api.zig");
}

// Explicit test references for zig test command
test {
    _ = @import("api.zig");
}

// ============================================================================
// Property 11: Extension function conflict detection
// **Validates: Requirements 9.4**
// For any attempt to register a function with a name that already exists
// (either built-in or previously registered), the Extension Registry SHALL
// return an error and not overwrite the existing function.
// ============================================================================

test "Feature: multi-syntax-extension-system, Property 11: multiple function conflicts" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 0;
        }
    }.call;
    
    // Test with multiple function names
    const names = [_][]const u8{ "func_a", "func_b", "func_c", "test_func", "helper" };
    
    for (names) |name| {
        const func1 = api.ExtensionFunction{
            .name = name,
            .callback = callback,
            .min_args = 1,
            .max_args = 5,
            .return_type = null,
            .param_types = &[_][]const u8{},
        };
        
        const func2 = api.ExtensionFunction{
            .name = name,
            .callback = callback,
            .min_args = 0,
            .max_args = 10,
            .return_type = null,
            .param_types = &[_][]const u8{},
        };
        
        // First registration should succeed
        try registry.registerFunction(func1);
        
        // Second registration with same name MUST fail
        const result = registry.registerFunction(func2);
        try std.testing.expectError(ExtensionError.FunctionAlreadyExists, result);
        
        // Verify original function is unchanged
        const found = registry.findFunction(name);
        try std.testing.expect(found != null);
        try std.testing.expectEqual(@as(u8, 1), found.?.min_args);
        try std.testing.expectEqual(@as(u8, 5), found.?.max_args);
    }
    
    // Verify total count matches unique names
    try std.testing.expectEqual(names.len, registry.functionCount());
}

test "Feature: multi-syntax-extension-system, Property 11: multiple builtin function conflicts" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 0;
        }
    }.call;
    
    // Register multiple builtins
    const builtin_names = [_][]const u8{ "echo", "print", "var_dump", "isset", "empty" };
    
    for (builtin_names) |name| {
        try registry.registerBuiltinFunction(name);
        
        const func = api.ExtensionFunction{
            .name = name,
            .callback = callback,
            .min_args = 0,
            .max_args = 255,
            .return_type = null,
            .param_types = &[_][]const u8{},
        };
        
        // Registration MUST fail
        const result = registry.registerFunction(func);
        try std.testing.expectError(ExtensionError.FunctionAlreadyExists, result);
    }
    
    // No extension functions should be registered
    try std.testing.expectEqual(@as(usize, 0), registry.functionCount());
}

test "Feature: multi-syntax-extension-system, Property 11: multiple class conflicts" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Test with multiple class names
    const names = [_][]const u8{ "ClassA", "ClassB", "MyClass", "TestClass", "Helper" };
    
    for (names) |name| {
        const class1 = api.ExtensionClass{
            .name = name,
            .parent = null,
            .interfaces = &[_][]const u8{},
            .methods = &[_]api.ExtensionMethod{},
            .properties = &[_]api.ExtensionProperty{},
            .constructor = null,
            .destructor = null,
        };
        
        const class2 = api.ExtensionClass{
            .name = name,
            .parent = "SomeParent",
            .interfaces = &[_][]const u8{},
            .methods = &[_]api.ExtensionMethod{},
            .properties = &[_]api.ExtensionProperty{},
            .constructor = null,
            .destructor = null,
        };
        
        // First registration should succeed
        try registry.registerClass(class1);
        
        // Second registration with same name MUST fail
        const result = registry.registerClass(class2);
        try std.testing.expectError(ExtensionError.ClassAlreadyExists, result);
        
        // Verify original class is unchanged
        const found = registry.findClass(name);
        try std.testing.expect(found != null);
        try std.testing.expect(found.?.parent == null);
    }
    
    // Verify total count matches unique names
    try std.testing.expectEqual(names.len, registry.classCount());
}

test "Feature: multi-syntax-extension-system, Property 11: multiple builtin class conflicts" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Register multiple builtin classes
    const builtin_names = [_][]const u8{ "stdClass", "Exception", "Error", "Iterator", "Countable" };
    
    for (builtin_names) |name| {
        try registry.registerBuiltinClass(name);
        
        const class = api.ExtensionClass{
            .name = name,
            .parent = null,
            .interfaces = &[_][]const u8{},
            .methods = &[_]api.ExtensionMethod{},
            .properties = &[_]api.ExtensionProperty{},
            .constructor = null,
            .destructor = null,
        };
        
        // Registration MUST fail
        const result = registry.registerClass(class);
        try std.testing.expectError(ExtensionError.ClassAlreadyExists, result);
    }
    
    // No extension classes should be registered
    try std.testing.expectEqual(@as(usize, 0), registry.classCount());
}

test "Feature: multi-syntax-extension-system, Property 11: case sensitivity" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 0;
        }
    }.call;
    
    // Register lowercase function
    const func1 = api.createFunction("myfunction", callback, 0, 0);
    try registry.registerFunction(func1);
    
    // Register uppercase function (should succeed - different name)
    const func2 = api.createFunction("MYFUNCTION", callback, 0, 0);
    try registry.registerFunction(func2);
    
    // Both should exist
    try std.testing.expect(registry.hasFunction("myfunction"));
    try std.testing.expect(registry.hasFunction("MYFUNCTION"));
    try std.testing.expectEqual(@as(usize, 2), registry.functionCount());
}

test "Feature: multi-syntax-extension-system, Property 11: mixed builtin and extension" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const callback: api.ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const api.ExtensionValue) anyerror!api.ExtensionValue {
            return 0;
        }
    }.call;
    
    // Register some builtins
    try registry.registerBuiltinFunction("echo");
    try registry.registerBuiltinClass("stdClass");
    
    // Builtin conflicts should fail
    const echo_func = api.createFunction("echo", callback, 1, 1);
    try std.testing.expectError(ExtensionError.FunctionAlreadyExists, registry.registerFunction(echo_func));
    
    const std_class = api.createClass("stdClass", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{});
    try std.testing.expectError(ExtensionError.ClassAlreadyExists, registry.registerClass(std_class));
    
    // Different names should work
    const custom_func = api.createFunction("custom_echo", callback, 1, 1);
    try registry.registerFunction(custom_func);
    try std.testing.expect(registry.hasFunction("custom_echo"));
    
    const custom_class = api.createClass("CustomClass", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{});
    try registry.registerClass(custom_class);
    try std.testing.expect(registry.hasClass("CustomClass"));
}

// ============================================================================
// Property 9: Extension lifecycle management
// **Validates: Requirements 7.5, 8.2, 8.5**
// For any loaded extension, the Extension Registry SHALL call the init function
// exactly once during loading and the shutdown function exactly once during
// interpreter shutdown (if provided).
// ============================================================================

// Thread-safe counter for tracking init/shutdown calls
const LifecycleCounter = struct {
    init_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    shutdown_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    
    fn incrementInit(self: *LifecycleCounter) void {
        _ = self.init_count.fetchAdd(1, .seq_cst);
    }
    
    fn incrementShutdown(self: *LifecycleCounter) void {
        _ = self.shutdown_count.fetchAdd(1, .seq_cst);
    }
    
    fn getInitCount(self: *LifecycleCounter) u32 {
        return self.init_count.load(.seq_cst);
    }
    
    fn getShutdownCount(self: *LifecycleCounter) u32 {
        return self.shutdown_count.load(.seq_cst);
    }
    
    fn reset(self: *LifecycleCounter) void {
        self.init_count.store(0, .seq_cst);
        self.shutdown_count.store(0, .seq_cst);
    }
};

// Global counter for testing (used by test extensions)
var test_lifecycle_counter = LifecycleCounter{};

// Test extension init callback
fn testExtensionInit(_: *anyopaque) anyerror!void {
    test_lifecycle_counter.incrementInit();
}

// Test extension shutdown callback
fn testExtensionShutdown(_: *anyopaque) void {
    test_lifecycle_counter.incrementShutdown();
}

// Create a test extension with lifecycle tracking
fn createTestExtension(name: []const u8, with_shutdown: bool) api.Extension {
    return api.Extension{
        .info = api.ExtensionInfo{
            .name = name,
            .version = "1.0.0",
            .api_version = EXTENSION_API_VERSION,
            .author = "Test",
            .description = "Test extension for lifecycle testing",
        },
        .init_fn = testExtensionInit,
        .shutdown_fn = if (with_shutdown) testExtensionShutdown else null,
        .functions = &[_]api.ExtensionFunction{},
        .classes = &[_]api.ExtensionClass{},
        .syntax_hooks = null,
    };
}

test "Feature: multi-syntax-extension-system, Property 9: init called exactly once" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const ext = createTestExtension("test_ext_init", false);
    
    // Register extension
    try registry.registerExtension(&ext);
    
    // Init should be called exactly once
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
    
    // Extension should be marked as initialized
    try std.testing.expect(registry.isExtensionInitialized("test_ext_init"));
}

test "Feature: multi-syntax-extension-system, Property 9: shutdown called exactly once on deinit" {
    test_lifecycle_counter.reset();
    
    {
        var registry = ExtensionRegistry.init(std.testing.allocator);
        
        const ext = createTestExtension("test_ext_shutdown", true);
        try registry.registerExtension(&ext);
        
        // Init should be called
        try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
        // Shutdown not called yet
        try std.testing.expectEqual(@as(u32, 0), test_lifecycle_counter.getShutdownCount());
        
        // deinit will call shutdown
        registry.deinit();
    }
    
    // Shutdown should be called exactly once
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getShutdownCount());
}

test "Feature: multi-syntax-extension-system, Property 9: shutdown called on unload" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const ext = createTestExtension("test_ext_unload", true);
    try registry.registerExtension(&ext);
    
    // Init called
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
    try std.testing.expectEqual(@as(u32, 0), test_lifecycle_counter.getShutdownCount());
    
    // Unload extension
    const unloaded = registry.unloadExtension("test_ext_unload");
    try std.testing.expect(unloaded);
    
    // Shutdown should be called exactly once
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getShutdownCount());
    
    // Extension should no longer be initialized
    try std.testing.expect(!registry.isExtensionInitialized("test_ext_unload"));
}

test "Feature: multi-syntax-extension-system, Property 9: no shutdown if not provided" {
    test_lifecycle_counter.reset();
    
    {
        var registry = ExtensionRegistry.init(std.testing.allocator);
        
        // Extension without shutdown function
        const ext = createTestExtension("test_ext_no_shutdown", false);
        try registry.registerExtension(&ext);
        
        try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
        
        registry.deinit();
    }
    
    // Shutdown should NOT be called (no shutdown_fn provided)
    try std.testing.expectEqual(@as(u32, 0), test_lifecycle_counter.getShutdownCount());
}

test "Feature: multi-syntax-extension-system, Property 9: multiple extensions lifecycle" {
    test_lifecycle_counter.reset();
    
    {
        var registry = ExtensionRegistry.init(std.testing.allocator);
        
        // Register multiple extensions
        const ext1 = createTestExtension("ext1", true);
        const ext2 = createTestExtension("ext2", true);
        const ext3 = createTestExtension("ext3", false); // No shutdown
        
        try registry.registerExtension(&ext1);
        try registry.registerExtension(&ext2);
        try registry.registerExtension(&ext3);
        
        // All three should have init called
        try std.testing.expectEqual(@as(u32, 3), test_lifecycle_counter.getInitCount());
        try std.testing.expectEqual(@as(u32, 0), test_lifecycle_counter.getShutdownCount());
        
        // All should be initialized
        try std.testing.expectEqual(@as(usize, 3), registry.initializedExtensionCount());
        
        registry.deinit();
    }
    
    // Only ext1 and ext2 have shutdown functions
    try std.testing.expectEqual(@as(u32, 2), test_lifecycle_counter.getShutdownCount());
}

test "Feature: multi-syntax-extension-system, Property 9: shutdown all extensions" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const ext1 = createTestExtension("ext_shutdown_all_1", true);
    const ext2 = createTestExtension("ext_shutdown_all_2", true);
    
    try registry.registerExtension(&ext1);
    try registry.registerExtension(&ext2);
    
    try std.testing.expectEqual(@as(u32, 2), test_lifecycle_counter.getInitCount());
    try std.testing.expectEqual(@as(usize, 2), registry.initializedExtensionCount());
    
    // Shutdown all extensions
    registry.shutdownAllExtensions();
    
    // Both should have shutdown called
    try std.testing.expectEqual(@as(u32, 2), test_lifecycle_counter.getShutdownCount());
    
    // Extensions should no longer be marked as initialized
    try std.testing.expectEqual(@as(usize, 0), registry.initializedExtensionCount());
}

test "Feature: multi-syntax-extension-system, Property 9: double registration prevented" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const ext = createTestExtension("test_double_reg", true);
    
    // First registration succeeds
    try registry.registerExtension(&ext);
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
    
    // Second registration should fail
    const result = registry.registerExtension(&ext);
    try std.testing.expectError(ExtensionError.ExtensionAlreadyLoaded, result);
    
    // Init should still be called only once
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
}

test "Feature: multi-syntax-extension-system, Property 9: unload non-existent extension" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Unloading non-existent extension should return false
    const result = registry.unloadExtension("non_existent");
    try std.testing.expect(!result);
}


// ============================================================================
// Property 17: Extension API version compatibility
// **Validates: Requirements 15.2, 15.3**
// For any extension with API version greater than the interpreter's supported
// version, the Extension Loader SHALL reject the extension and report an
// incompatibility error.
// ============================================================================

// Create a test extension with specific API version
fn createTestExtensionWithVersion(name: []const u8, version: u32) api.Extension {
    return api.Extension{
        .info = api.ExtensionInfo{
            .name = name,
            .version = "1.0.0",
            .api_version = version,
            .author = "Test",
            .description = "Test extension for API version testing",
        },
        .init_fn = testExtensionInit,
        .shutdown_fn = testExtensionShutdown,
        .functions = &[_]api.ExtensionFunction{},
        .classes = &[_]api.ExtensionClass{},
        .syntax_hooks = null,
    };
}

test "Feature: multi-syntax-extension-system, Property 17: compatible API version" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Extension with current API version should be accepted
    const ext = createTestExtensionWithVersion("ext_current_api", EXTENSION_API_VERSION);
    try registry.registerExtension(&ext);
    
    try std.testing.expect(registry.extensions.contains("ext_current_api"));
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
}

test "Feature: multi-syntax-extension-system, Property 17: older API version compatible" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Extension with older API version should be accepted (backward compatibility)
    if (EXTENSION_API_VERSION > 0) {
        const ext = createTestExtensionWithVersion("ext_old_api", EXTENSION_API_VERSION - 1);
        try registry.registerExtension(&ext);
        
        try std.testing.expect(registry.extensions.contains("ext_old_api"));
        try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
    }
}

test "Feature: multi-syntax-extension-system, Property 17: newer API version rejected" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Extension with newer API version should be rejected
    const ext = createTestExtensionWithVersion("ext_new_api", EXTENSION_API_VERSION + 1);
    const result = registry.registerExtension(&ext);
    
    try std.testing.expectError(ExtensionError.IncompatibleApiVersion, result);
    try std.testing.expect(!registry.extensions.contains("ext_new_api"));
    // Init should NOT be called for incompatible extensions
    try std.testing.expectEqual(@as(u32, 0), test_lifecycle_counter.getInitCount());
}

test "Feature: multi-syntax-extension-system, Property 17: much newer API version rejected" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Extension with much newer API version should be rejected
    const ext = createTestExtensionWithVersion("ext_future_api", EXTENSION_API_VERSION + 100);
    const result = registry.registerExtension(&ext);
    
    try std.testing.expectError(ExtensionError.IncompatibleApiVersion, result);
    try std.testing.expect(!registry.extensions.contains("ext_future_api"));
    try std.testing.expectEqual(@as(u32, 0), test_lifecycle_counter.getInitCount());
}

test "Feature: multi-syntax-extension-system, Property 17: isApiVersionCompatible helper" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Current version is compatible
    try std.testing.expect(registry.isApiVersionCompatible(EXTENSION_API_VERSION));
    
    // Older versions are compatible (backward compatibility)
    if (EXTENSION_API_VERSION > 0) {
        try std.testing.expect(registry.isApiVersionCompatible(EXTENSION_API_VERSION - 1));
    }
    try std.testing.expect(registry.isApiVersionCompatible(0));
    
    // Newer versions are NOT compatible
    try std.testing.expect(!registry.isApiVersionCompatible(EXTENSION_API_VERSION + 1));
    try std.testing.expect(!registry.isApiVersionCompatible(EXTENSION_API_VERSION + 100));
    try std.testing.expect(!registry.isApiVersionCompatible(std.math.maxInt(u32)));
}

test "Feature: multi-syntax-extension-system, Property 17: getApiVersion returns current" {
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    try std.testing.expectEqual(EXTENSION_API_VERSION, registry.getApiVersion());
}

test "Feature: multi-syntax-extension-system, Property 17: checkExtensionCompatibility" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Compatible extension should pass check
    const ext_ok = createTestExtensionWithVersion("ext_check_ok", EXTENSION_API_VERSION);
    try registry.checkExtensionCompatibility(&ext_ok);
    
    // Incompatible extension should fail check
    const ext_bad = createTestExtensionWithVersion("ext_check_bad", EXTENSION_API_VERSION + 1);
    const result = registry.checkExtensionCompatibility(&ext_bad);
    try std.testing.expectError(ExtensionError.IncompatibleApiVersion, result);
    
    // Init should NOT be called during compatibility check
    try std.testing.expectEqual(@as(u32, 0), test_lifecycle_counter.getInitCount());
}

test "Feature: multi-syntax-extension-system, Property 17: multiple versions mixed" {
    test_lifecycle_counter.reset();
    
    var registry = ExtensionRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Try to register extensions with various API versions
    const ext_current = createTestExtensionWithVersion("ext_v_current", EXTENSION_API_VERSION);
    const ext_future = createTestExtensionWithVersion("ext_v_future", EXTENSION_API_VERSION + 1);
    
    // Current version should succeed
    try registry.registerExtension(&ext_current);
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
    
    // Future version should fail
    const result = registry.registerExtension(&ext_future);
    try std.testing.expectError(ExtensionError.IncompatibleApiVersion, result);
    
    // Only one extension should be registered
    try std.testing.expectEqual(@as(usize, 1), registry.extensionCount());
    try std.testing.expectEqual(@as(u32, 1), test_lifecycle_counter.getInitCount());
}
