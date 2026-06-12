const std = @import("std");

/// Extension API version - used for compatibility checking
/// Extensions must be compiled against a compatible API version
pub const EXTENSION_API_VERSION: u32 = 1;

/// Opaque value type for extension callbacks
/// The actual Value type is defined in runtime/types.zig
/// Extensions work with this opaque representation
pub const ExtensionValue = u64;

/// Extension information structure
/// Contains metadata about the extension for identification and compatibility
pub const ExtensionInfo = struct {
    /// Unique name of the extension
    name: []const u8,
    /// Version string (e.g., "1.0.0")
    version: []const u8,
    /// API version this extension was built against
    api_version: u32,
    /// Author or organization name
    author: []const u8,
    /// Brief description of the extension's functionality
    description: []const u8,
};

/// Extension function callback signature
/// VM pointer is passed as opaque to avoid circular dependencies
/// Arguments and return value use ExtensionValue (opaque u64)
pub const ExtensionFunctionCallback = *const fn (*anyopaque, []const ExtensionValue) anyerror!ExtensionValue;

/// Extension function definition
/// Defines a function that can be registered and called from PHP/Go code
pub const ExtensionFunction = struct {
    /// Function name as it will be called from user code
    name: []const u8,
    /// Callback function to execute
    callback: ExtensionFunctionCallback,
    /// Minimum number of required arguments
    min_args: u8,
    /// Maximum number of arguments (255 for unlimited)
    max_args: u8,
    /// Optional return type hint (null for any)
    return_type: ?[]const u8,
    /// Parameter type hints
    param_types: []const []const u8,
};

/// Extension method callback signature
/// Object pointer is passed as opaque to avoid circular dependencies
pub const ExtensionMethodCallback = *const fn (*anyopaque, *anyopaque, []const ExtensionValue) anyerror!ExtensionValue;

/// Extension method definition
/// Defines a method that belongs to an extension class
pub const ExtensionMethod = struct {
    /// Method name
    name: []const u8,
    /// Callback function to execute
    callback: ExtensionMethodCallback,
    /// Access modifiers
    modifiers: Modifiers,
    /// Minimum number of required arguments
    min_args: u8,
    /// Maximum number of arguments
    max_args: u8,

    pub const Modifiers = packed struct {
        is_public: bool = true,
        is_protected: bool = false,
        is_private: bool = false,
        is_static: bool = false,
        is_final: bool = false,
        is_abstract: bool = false,
    };
};

/// Extension property definition
/// Defines a property that belongs to an extension class
pub const ExtensionProperty = struct {
    /// Property name
    name: []const u8,
    /// Default value as opaque (null if none)
    default_value: ?ExtensionValue,
    /// Access modifiers
    modifiers: Modifiers,
    /// Optional type hint
    type_hint: ?[]const u8,

    pub const Modifiers = packed struct {
        is_public: bool = true,
        is_protected: bool = false,
        is_private: bool = false,
        is_static: bool = false,
        is_readonly: bool = false,
    };
};

/// Extension constructor callback signature
pub const ExtensionConstructorCallback = *const fn (*anyopaque, *anyopaque, []const ExtensionValue) anyerror!void;

/// Extension destructor callback signature
pub const ExtensionDestructorCallback = *const fn (*anyopaque, *anyopaque) void;

/// Extension class definition
/// Defines a class that can be registered and instantiated from user code
pub const ExtensionClass = struct {
    /// Class name
    name: []const u8,
    /// Parent class name (null if none)
    parent: ?[]const u8,
    /// Implemented interfaces
    interfaces: []const []const u8,
    /// Class methods
    methods: []const ExtensionMethod,
    /// Class properties
    properties: []const ExtensionProperty,
    /// Constructor callback (null if none)
    constructor: ?ExtensionConstructorCallback,
    /// Destructor callback (null if none)
    destructor: ?ExtensionDestructorCallback,
};

/// Syntax hooks interface
/// Allows extensions to hook into the parsing process for custom syntax
pub const SyntaxHooks = struct {
    /// Custom keywords registered by this extension
    custom_keywords: []const []const u8,
    /// Statement parsing hook (returns null if not handled)
    parse_statement: ?*const fn (*anyopaque, u32) anyerror!?u32,
    /// Expression parsing hook (returns null if not handled)
    parse_expression: ?*const fn (*anyopaque, u8) anyerror!?u32,
};

/// Extension initialization callback signature
/// Called when the extension is loaded
pub const ExtensionInitCallback = *const fn (*anyopaque) anyerror!void;

/// Extension shutdown callback signature
/// Called when the interpreter shuts down
pub const ExtensionShutdownCallback = *const fn (*anyopaque) void;

/// Extension interface
/// All extensions must provide this structure
pub const Extension = struct {
    /// Extension metadata
    info: ExtensionInfo,
    /// Initialization function (called on load)
    init_fn: ExtensionInitCallback,
    /// Shutdown function (called on interpreter exit, optional)
    shutdown_fn: ?ExtensionShutdownCallback,
    /// Functions provided by this extension
    functions: []const ExtensionFunction,
    /// Classes provided by this extension
    classes: []const ExtensionClass,
    /// Syntax hooks (optional)
    syntax_hooks: ?*const SyntaxHooks,
};

/// Entry point function signature for dynamic library extensions
/// Extensions must export a function with this signature named "zigphp_get_extension"
pub const GetExtensionFn = *const fn () *const Extension;

/// Extension error types
pub const ExtensionError = error{
    /// Extension with this name already loaded
    ExtensionAlreadyLoaded,
    /// Function with this name already exists
    FunctionAlreadyExists,
    /// Class with this name already exists
    ClassAlreadyExists,
    /// Extension API version is incompatible
    IncompatibleApiVersion,
    /// Extension failed to initialize
    InitializationFailed,
    /// Invalid extension (missing entry point or malformed)
    InvalidExtension,
    /// Extension not found at specified path
    ExtensionNotFound,
    /// Out of memory
    OutOfMemory,
};

/// Helper to create a simple extension function
pub fn createFunction(
    name: []const u8,
    callback: ExtensionFunctionCallback,
    min_args: u8,
    max_args: u8,
) ExtensionFunction {
    return ExtensionFunction{
        .name = name,
        .callback = callback,
        .min_args = min_args,
        .max_args = max_args,
        .return_type = null,
        .param_types = &[_][]const u8{},
    };
}

/// Helper to create a simple extension class
pub fn createClass(
    name: []const u8,
    methods: []const ExtensionMethod,
    properties: []const ExtensionProperty,
) ExtensionClass {
    return ExtensionClass{
        .name = name,
        .parent = null,
        .interfaces = &[_][]const u8{},
        .methods = methods,
        .properties = properties,
        .constructor = null,
        .destructor = null,
    };
}

/// Helper to create extension info
pub fn createExtensionInfo(
    name: []const u8,
    version: []const u8,
    author: []const u8,
    description: []const u8,
) ExtensionInfo {
    return ExtensionInfo{
        .name = name,
        .version = version,
        .api_version = EXTENSION_API_VERSION,
        .author = author,
        .description = description,
    };
}

// Unit tests
test "ExtensionInfo creation" {
    const info = createExtensionInfo(
        "test_extension",
        "1.0.0",
        "Test Author",
        "A test extension",
    );
    try std.testing.expectEqualStrings("test_extension", info.name);
    try std.testing.expectEqualStrings("1.0.0", info.version);
    try std.testing.expectEqual(EXTENSION_API_VERSION, info.api_version);
}

test "ExtensionFunction creation" {
    const callback: ExtensionFunctionCallback = struct {
        fn call(_: *anyopaque, _: []const ExtensionValue) anyerror!ExtensionValue {
            return 0;
        }
    }.call;
    
    const func = createFunction("test_func", callback, 1, 3);
    try std.testing.expectEqualStrings("test_func", func.name);
    try std.testing.expectEqual(@as(u8, 1), func.min_args);
    try std.testing.expectEqual(@as(u8, 3), func.max_args);
}

test "ExtensionClass creation" {
    const class = createClass("TestClass", &[_]ExtensionMethod{}, &[_]ExtensionProperty{});
    try std.testing.expectEqualStrings("TestClass", class.name);
    try std.testing.expect(class.parent == null);
    try std.testing.expectEqual(@as(usize, 0), class.methods.len);
}
