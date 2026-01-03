//! Sample Extension for zig-php
//!
//! This file demonstrates how to create a third-party extension for zig-php.
//! Extensions can register custom functions and classes that can be called
//! from PHP/Go mode code.
//!
//! To build this extension as a dynamic library (from project root):
//!   zig build-lib -dynamic -I src examples/extensions/sample_extension.zig
//!
//! To use the extension:
//!   zigphp --extension=./libsample_extension.so your_script.php
//!
//! Note: When building as part of the zig-php project, the extension API
//! is available via the build system. For standalone extensions, you would
//! need to include the API definitions.

const std = @import("std");

// ============================================================================
// Extension API Types (from src/extension/api.zig)
// These are duplicated here for demonstration purposes.
// In a real extension, you would import from the zig-php SDK.
// ============================================================================

/// Extension API version - must match the interpreter's version
pub const EXTENSION_API_VERSION: u32 = 1;

/// Opaque value type for extension callbacks
pub const ExtensionValue = u64;

/// Extension information structure
pub const ExtensionInfo = struct {
    name: []const u8,
    version: []const u8,
    api_version: u32,
    author: []const u8,
    description: []const u8,
};

/// Extension function callback signature
pub const ExtensionFunctionCallback = *const fn (*anyopaque, []const ExtensionValue) anyerror!ExtensionValue;

/// Extension function definition
pub const ExtensionFunction = struct {
    name: []const u8,
    callback: ExtensionFunctionCallback,
    min_args: u8,
    max_args: u8,
    return_type: ?[]const u8,
    param_types: []const []const u8,
};

/// Extension method callback signature
pub const ExtensionMethodCallback = *const fn (*anyopaque, *anyopaque, []const ExtensionValue) anyerror!ExtensionValue;

/// Extension method definition
pub const ExtensionMethod = struct {
    name: []const u8,
    callback: ExtensionMethodCallback,
    modifiers: Modifiers,
    min_args: u8,
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
pub const ExtensionProperty = struct {
    name: []const u8,
    default_value: ?ExtensionValue,
    modifiers: Modifiers,
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
pub const ExtensionClass = struct {
    name: []const u8,
    parent: ?[]const u8,
    interfaces: []const []const u8,
    methods: []const ExtensionMethod,
    properties: []const ExtensionProperty,
    constructor: ?ExtensionConstructorCallback,
    destructor: ?ExtensionDestructorCallback,
};

/// Syntax hooks interface
pub const SyntaxHooks = struct {
    custom_keywords: []const []const u8,
    parse_statement: ?*const fn (*anyopaque, u32) anyerror!?u32,
    parse_expression: ?*const fn (*anyopaque, u8) anyerror!?u32,
};

/// Extension initialization callback signature
pub const ExtensionInitCallback = *const fn (*anyopaque) anyerror!void;

/// Extension shutdown callback signature
pub const ExtensionShutdownCallback = *const fn (*anyopaque) void;

/// Extension interface - all extensions must provide this structure
pub const Extension = struct {
    info: ExtensionInfo,
    init_fn: ExtensionInitCallback,
    shutdown_fn: ?ExtensionShutdownCallback,
    functions: []const ExtensionFunction,
    classes: []const ExtensionClass,
    syntax_hooks: ?*const SyntaxHooks,
};

/// Helper to create a simple extension function
fn createFunction(
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
fn createClass(
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
fn createExtensionInfo(
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

// ============================================================================
// Extension Functions
// ============================================================================

/// A simple function that adds two numbers
/// Usage in PHP: $result = sample_add(5, 3);
/// Usage in Go mode: result = sample_add(5, 3)
fn sampleAdd(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    if (args.len < 2) return 0;
    
    // ExtensionValue is u64, interpret as i64 for signed arithmetic
    const a: i64 = @bitCast(args[0]);
    const b: i64 = @bitCast(args[1]);
    const result: i64 = a + b;
    
    return @bitCast(result);
}

/// A function that returns a greeting message
/// Usage in PHP: $msg = sample_greet("World");
/// Usage in Go mode: msg = sample_greet("World")
fn sampleGreet(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    _ = args;
    // In a real implementation, this would construct a string value
    // For demonstration, we return a placeholder
    return 0;
}

/// A function that demonstrates variable arguments
/// Usage: sample_sum(1, 2, 3, 4, 5)
fn sampleSum(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    var sum: i64 = 0;
    for (args) |arg| {
        const val: i64 = @bitCast(arg);
        sum += val;
    }
    return @bitCast(sum);
}

// Define the extension functions array
const extension_functions = [_]ExtensionFunction{
    createFunction("sample_add", sampleAdd, 2, 2),
    createFunction("sample_greet", sampleGreet, 1, 1),
    createFunction("sample_sum", sampleSum, 1, 255), // Variable args
};

// ============================================================================
// Extension Classes
// ============================================================================

/// Counter class - demonstrates a simple stateful class
/// Usage in PHP:
///   $counter = new SampleCounter();
///   $counter->increment();
///   echo $counter->getValue();
///
/// Usage in Go mode:
///   counter = new SampleCounter()
///   counter.increment()
///   echo counter.getValue()

fn counterConstructor(_: *anyopaque, _: *anyopaque, _: []const ExtensionValue) anyerror!void {
    // Initialize counter to 0
    // In a real implementation, this would set up the object's internal state
}

fn counterIncrement(_: *anyopaque, _: *anyopaque, _: []const ExtensionValue) anyerror!ExtensionValue {
    // Increment the counter
    // In a real implementation, this would modify the object's state
    return 1;
}

fn counterDecrement(_: *anyopaque, _: *anyopaque, _: []const ExtensionValue) anyerror!ExtensionValue {
    // Decrement the counter
    return 1;
}

fn counterGetValue(_: *anyopaque, _: *anyopaque, _: []const ExtensionValue) anyerror!ExtensionValue {
    // Return current counter value
    return 0;
}

fn counterReset(_: *anyopaque, _: *anyopaque, _: []const ExtensionValue) anyerror!ExtensionValue {
    // Reset counter to 0
    return 0;
}

const counter_methods = [_]ExtensionMethod{
    .{
        .name = "increment",
        .callback = counterIncrement,
        .modifiers = .{ .is_public = true },
        .min_args = 0,
        .max_args = 0,
    },
    .{
        .name = "decrement",
        .callback = counterDecrement,
        .modifiers = .{ .is_public = true },
        .min_args = 0,
        .max_args = 0,
    },
    .{
        .name = "getValue",
        .callback = counterGetValue,
        .modifiers = .{ .is_public = true },
        .min_args = 0,
        .max_args = 0,
    },
    .{
        .name = "reset",
        .callback = counterReset,
        .modifiers = .{ .is_public = true },
        .min_args = 0,
        .max_args = 0,
    },
};

const counter_properties = [_]ExtensionProperty{
    .{
        .name = "value",
        .default_value = 0,
        .modifiers = .{ .is_private = true, .is_public = false },
        .type_hint = "int",
    },
};

/// Calculator class - demonstrates a class with multiple operations
/// Usage:
///   $calc = new SampleCalculator();
///   $result = $calc->add(5, 3);
///   $result = $calc->multiply(4, 2);

fn calcAdd(_: *anyopaque, _: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    if (args.len < 2) return 0;
    const a: i64 = @bitCast(args[0]);
    const b: i64 = @bitCast(args[1]);
    return @bitCast(a + b);
}

fn calcSubtract(_: *anyopaque, _: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    if (args.len < 2) return 0;
    const a: i64 = @bitCast(args[0]);
    const b: i64 = @bitCast(args[1]);
    return @bitCast(a - b);
}

fn calcMultiply(_: *anyopaque, _: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    if (args.len < 2) return 0;
    const a: i64 = @bitCast(args[0]);
    const b: i64 = @bitCast(args[1]);
    return @bitCast(a * b);
}

fn calcDivide(_: *anyopaque, _: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    if (args.len < 2) return 0;
    const a: i64 = @bitCast(args[0]);
    const b: i64 = @bitCast(args[1]);
    if (b == 0) return 0; // Division by zero protection
    return @bitCast(@divTrunc(a, b));
}

const calculator_methods = [_]ExtensionMethod{
    .{
        .name = "add",
        .callback = calcAdd,
        .modifiers = .{ .is_public = true },
        .min_args = 2,
        .max_args = 2,
    },
    .{
        .name = "subtract",
        .callback = calcSubtract,
        .modifiers = .{ .is_public = true },
        .min_args = 2,
        .max_args = 2,
    },
    .{
        .name = "multiply",
        .callback = calcMultiply,
        .modifiers = .{ .is_public = true },
        .min_args = 2,
        .max_args = 2,
    },
    .{
        .name = "divide",
        .callback = calcDivide,
        .modifiers = .{ .is_public = true },
        .min_args = 2,
        .max_args = 2,
    },
};

// Define the extension classes array
const extension_classes = [_]ExtensionClass{
    .{
        .name = "SampleCounter",
        .parent = null,
        .interfaces = &[_][]const u8{},
        .methods = &counter_methods,
        .properties = &counter_properties,
        .constructor = counterConstructor,
        .destructor = null,
    },
    createClass("SampleCalculator", &calculator_methods, &[_]ExtensionProperty{}),
};

// ============================================================================
// Extension Lifecycle
// ============================================================================

/// Called when the extension is loaded
fn extensionInit(_: *anyopaque) anyerror!void {
    // Perform any initialization needed
    // This could include:
    // - Allocating resources
    // - Opening database connections
    // - Loading configuration
    // - Registering additional hooks
}

/// Called when the interpreter shuts down
fn extensionShutdown(_: *anyopaque) void {
    // Clean up resources
    // This could include:
    // - Freeing allocated memory
    // - Closing connections
    // - Flushing buffers
}

// ============================================================================
// Extension Definition
// ============================================================================

/// The main extension structure
/// This is what gets returned by zigphp_get_extension()
const sample_extension = Extension{
    .info = createExtensionInfo(
        "sample_extension",
        "1.0.0",
        "zig-php Team",
        "A sample extension demonstrating function and class registration",
    ),
    .init_fn = extensionInit,
    .shutdown_fn = extensionShutdown,
    .functions = &extension_functions,
    .classes = &extension_classes,
    .syntax_hooks = null, // No custom syntax in this example
};

/// Entry point for dynamic library loading
/// This function MUST be exported with this exact name
pub export fn zigphp_get_extension() *const Extension {
    return &sample_extension;
}

// ============================================================================
// Tests
// ============================================================================

test "sample_add function" {
    const result = try sampleAdd(undefined, &[_]ExtensionValue{
        @bitCast(@as(i64, 5)),
        @bitCast(@as(i64, 3)),
    });
    const value: i64 = @bitCast(result);
    try std.testing.expectEqual(@as(i64, 8), value);
}

test "sample_sum function" {
    const result = try sampleSum(undefined, &[_]ExtensionValue{
        @bitCast(@as(i64, 1)),
        @bitCast(@as(i64, 2)),
        @bitCast(@as(i64, 3)),
        @bitCast(@as(i64, 4)),
        @bitCast(@as(i64, 5)),
    });
    const value: i64 = @bitCast(result);
    try std.testing.expectEqual(@as(i64, 15), value);
}

test "extension info" {
    const ext = zigphp_get_extension();
    try std.testing.expectEqualStrings("sample_extension", ext.info.name);
    try std.testing.expectEqualStrings("1.0.0", ext.info.version);
    try std.testing.expectEqual(EXTENSION_API_VERSION, ext.info.api_version);
}

test "extension has functions" {
    const ext = zigphp_get_extension();
    try std.testing.expectEqual(@as(usize, 3), ext.functions.len);
    try std.testing.expectEqualStrings("sample_add", ext.functions[0].name);
    try std.testing.expectEqualStrings("sample_greet", ext.functions[1].name);
    try std.testing.expectEqualStrings("sample_sum", ext.functions[2].name);
}

test "extension has classes" {
    const ext = zigphp_get_extension();
    try std.testing.expectEqual(@as(usize, 2), ext.classes.len);
    try std.testing.expectEqualStrings("SampleCounter", ext.classes[0].name);
    try std.testing.expectEqualStrings("SampleCalculator", ext.classes[1].name);
}
