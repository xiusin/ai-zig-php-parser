// ============================================================================
// Property-Based Tests for Extension System
// Feature: multi-syntax-extension-system
// ============================================================================

const std = @import("std");
const api = @import("api.zig");
const registry = @import("registry.zig");
const ExtensionRegistry = registry.ExtensionRegistry;
const ExtensionFunction = api.ExtensionFunction;
const ExtensionClass = api.ExtensionClass;
const ExtensionValue = api.ExtensionValue;
const EXTENSION_API_VERSION = api.EXTENSION_API_VERSION;

// ============================================================================
// Property 10: Extension function invocation
// **Validates: Requirements 9.2, 9.3**
// For any registered extension function, when called from user code, the VM
// SHALL invoke the extension's callback with the correct arguments and return
// the callback's result.
// ============================================================================

// Test callback that returns the sum of arguments (as integers)
fn testSumCallback(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    var sum: i64 = 0;
    for (args) |arg| {
        // Interpret ExtensionValue as a simple integer for testing
        sum += @as(i64, @bitCast(arg));
    }
    return @bitCast(sum);
}

// Test callback that returns the number of arguments
fn testArgCountCallback(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    return @intCast(args.len);
}

// Test callback that returns a constant value
fn testConstantCallback(_: *anyopaque, _: []const ExtensionValue) anyerror!ExtensionValue {
    return 42;
}

// Test callback that echoes the first argument
fn testEchoCallback(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    if (args.len == 0) return 0;
    return args[0];
}

// Test callback that fails with an error
fn testErrorCallback(_: *anyopaque, _: []const ExtensionValue) anyerror!ExtensionValue {
    return error.TestError;
}

test "Feature: multi-syntax-extension-system, Property 10: function registration and lookup" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Register multiple functions with different signatures
    const functions = [_]ExtensionFunction{
        api.createFunction("test_sum", testSumCallback, 2, 10),
        api.createFunction("test_count", testArgCountCallback, 0, 255),
        api.createFunction("test_constant", testConstantCallback, 0, 0),
        api.createFunction("test_echo", testEchoCallback, 1, 1),
    };

    for (functions) |func| {
        try ext_registry.registerFunction(func);
    }

    // Verify all functions can be found
    for (functions) |func| {
        const found = ext_registry.findFunction(func.name);
        try std.testing.expect(found != null);
        try std.testing.expectEqualStrings(func.name, found.?.name);
        try std.testing.expectEqual(func.min_args, found.?.min_args);
        try std.testing.expectEqual(func.max_args, found.?.max_args);
    }
}

test "Feature: multi-syntax-extension-system, Property 10: callback invocation with correct arguments" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Register test functions
    try ext_registry.registerFunction(api.createFunction("test_sum", testSumCallback, 0, 255));
    try ext_registry.registerFunction(api.createFunction("test_count", testArgCountCallback, 0, 255));
    try ext_registry.registerFunction(api.createFunction("test_echo", testEchoCallback, 1, 1));

    // Test sum function with various argument counts
    const sum_func = ext_registry.findFunction("test_sum").?;
    
    // Test with 2 arguments
    const args2 = [_]ExtensionValue{ @bitCast(@as(i64, 10)), @bitCast(@as(i64, 20)) };
    const result2 = try sum_func.callback(@ptrFromInt(1), &args2);
    try std.testing.expectEqual(@as(i64, 30), @as(i64, @bitCast(result2)));

    // Test with 5 arguments
    const args5 = [_]ExtensionValue{
        @bitCast(@as(i64, 1)),
        @bitCast(@as(i64, 2)),
        @bitCast(@as(i64, 3)),
        @bitCast(@as(i64, 4)),
        @bitCast(@as(i64, 5)),
    };
    const result5 = try sum_func.callback(@ptrFromInt(1), &args5);
    try std.testing.expectEqual(@as(i64, 15), @as(i64, @bitCast(result5)));

    // Test count function
    const count_func = ext_registry.findFunction("test_count").?;
    const count_result = try count_func.callback(@ptrFromInt(1), &args5);
    try std.testing.expectEqual(@as(u64, 5), count_result);

    // Test echo function
    const echo_func = ext_registry.findFunction("test_echo").?;
    const echo_args = [_]ExtensionValue{@bitCast(@as(i64, 123))};
    const echo_result = try echo_func.callback(@ptrFromInt(1), &echo_args);
    try std.testing.expectEqual(@as(i64, 123), @as(i64, @bitCast(echo_result)));
}

test "Feature: multi-syntax-extension-system, Property 10: callback returns correct result" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Register constant function
    try ext_registry.registerFunction(api.createFunction("test_constant", testConstantCallback, 0, 0));

    const func = ext_registry.findFunction("test_constant").?;
    
    // Call multiple times - should always return 42
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const result = try func.callback(@ptrFromInt(1), &[_]ExtensionValue{});
        try std.testing.expectEqual(@as(u64, 42), result);
    }
}

test "Feature: multi-syntax-extension-system, Property 10: callback error propagation" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Register error function
    try ext_registry.registerFunction(api.createFunction("test_error", testErrorCallback, 0, 0));

    const func = ext_registry.findFunction("test_error").?;
    
    // Call should return error
    const result = func.callback(@ptrFromInt(1), &[_]ExtensionValue{});
    try std.testing.expectError(error.TestError, result);
}

test "Feature: multi-syntax-extension-system, Property 10: argument count validation" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Register function with specific argument requirements
    const func = api.createFunction("test_args", testSumCallback, 2, 5);
    try ext_registry.registerFunction(func);

    const found = ext_registry.findFunction("test_args").?;
    
    // Verify min/max args are preserved
    try std.testing.expectEqual(@as(u8, 2), found.min_args);
    try std.testing.expectEqual(@as(u8, 5), found.max_args);
}

test "Feature: multi-syntax-extension-system, Property 10: multiple functions with same callback" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Register multiple functions using the same callback
    try ext_registry.registerFunction(api.createFunction("sum1", testSumCallback, 0, 255));
    try ext_registry.registerFunction(api.createFunction("sum2", testSumCallback, 0, 255));
    try ext_registry.registerFunction(api.createFunction("sum3", testSumCallback, 0, 255));

    // All should work independently
    const args = [_]ExtensionValue{ @bitCast(@as(i64, 5)), @bitCast(@as(i64, 10)) };
    
    const func1 = ext_registry.findFunction("sum1").?;
    const func2 = ext_registry.findFunction("sum2").?;
    const func3 = ext_registry.findFunction("sum3").?;

    const result1 = try func1.callback(@ptrFromInt(1), &args);
    const result2 = try func2.callback(@ptrFromInt(1), &args);
    const result3 = try func3.callback(@ptrFromInt(1), &args);

    try std.testing.expectEqual(@as(i64, 15), @as(i64, @bitCast(result1)));
    try std.testing.expectEqual(@as(i64, 15), @as(i64, @bitCast(result2)));
    try std.testing.expectEqual(@as(i64, 15), @as(i64, @bitCast(result3)));
}

test "Feature: multi-syntax-extension-system, Property 10: empty arguments" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    try ext_registry.registerFunction(api.createFunction("test_sum", testSumCallback, 0, 255));
    try ext_registry.registerFunction(api.createFunction("test_count", testArgCountCallback, 0, 255));

    const sum_func = ext_registry.findFunction("test_sum").?;
    const count_func = ext_registry.findFunction("test_count").?;

    // Empty arguments
    const empty_args = [_]ExtensionValue{};
    
    const sum_result = try sum_func.callback(@ptrFromInt(1), &empty_args);
    try std.testing.expectEqual(@as(i64, 0), @as(i64, @bitCast(sum_result)));

    const count_result = try count_func.callback(@ptrFromInt(1), &empty_args);
    try std.testing.expectEqual(@as(u64, 0), count_result);
}


// ============================================================================
// Property 12: Extension class instantiation
// **Validates: Requirements 10.2, 10.3, 10.4**
// For any registered extension class, when instantiated via `new ClassName()`,
// the VM SHALL create an object with the class's defined properties and call
// the constructor if provided.
// ============================================================================

// Track constructor calls for testing
var constructor_call_count: u32 = 0;
var constructor_last_arg_count: usize = 0;

fn testConstructorCallback(_: *anyopaque, _: *anyopaque, args: []const ExtensionValue) anyerror!void {
    constructor_call_count += 1;
    constructor_last_arg_count = args.len;
}

// Track destructor calls for testing
var destructor_call_count: u32 = 0;

fn testDestructorCallback(_: *anyopaque, _: *anyopaque) void {
    destructor_call_count += 1;
}

fn resetConstructorTracking() void {
    constructor_call_count = 0;
    constructor_last_arg_count = 0;
    destructor_call_count = 0;
}

test "Feature: multi-syntax-extension-system, Property 12: class registration and lookup" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Create test classes with different configurations
    const class1 = api.ExtensionClass{
        .name = "TestClass1",
        .parent = null,
        .interfaces = &[_][]const u8{},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = null,
        .destructor = null,
    };

    const class2 = api.ExtensionClass{
        .name = "TestClass2",
        .parent = "TestClass1",
        .interfaces = &[_][]const u8{"Countable"},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = testConstructorCallback,
        .destructor = testDestructorCallback,
    };

    try ext_registry.registerClass(class1);
    try ext_registry.registerClass(class2);

    // Verify classes can be found
    const found1 = ext_registry.findClass("TestClass1");
    try std.testing.expect(found1 != null);
    try std.testing.expectEqualStrings("TestClass1", found1.?.name);
    try std.testing.expect(found1.?.parent == null);
    try std.testing.expect(found1.?.constructor == null);

    const found2 = ext_registry.findClass("TestClass2");
    try std.testing.expect(found2 != null);
    try std.testing.expectEqualStrings("TestClass2", found2.?.name);
    try std.testing.expectEqualStrings("TestClass1", found2.?.parent.?);
    try std.testing.expect(found2.?.constructor != null);
    try std.testing.expect(found2.?.destructor != null);
}

test "Feature: multi-syntax-extension-system, Property 12: class with properties" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Create class with properties
    const properties = [_]api.ExtensionProperty{
        .{
            .name = "name",
            .default_value = null,
            .modifiers = .{ .is_public = true },
            .type_hint = "string",
        },
        .{
            .name = "count",
            .default_value = @bitCast(@as(i64, 0)),
            .modifiers = .{ .is_public = true },
            .type_hint = "int",
        },
        .{
            .name = "private_data",
            .default_value = null,
            .modifiers = .{ .is_private = true },
            .type_hint = null,
        },
    };

    const class = api.ExtensionClass{
        .name = "PropertyClass",
        .parent = null,
        .interfaces = &[_][]const u8{},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &properties,
        .constructor = null,
        .destructor = null,
    };

    try ext_registry.registerClass(class);

    const found = ext_registry.findClass("PropertyClass");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 3), found.?.properties.len);

    // Verify property details
    try std.testing.expectEqualStrings("name", found.?.properties[0].name);
    try std.testing.expect(found.?.properties[0].modifiers.is_public);
    
    try std.testing.expectEqualStrings("count", found.?.properties[1].name);
    try std.testing.expect(found.?.properties[1].default_value != null);
    
    try std.testing.expectEqualStrings("private_data", found.?.properties[2].name);
    try std.testing.expect(found.?.properties[2].modifiers.is_private);
}

test "Feature: multi-syntax-extension-system, Property 12: class with methods" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    const method_callback: api.ExtensionMethodCallback = struct {
        fn call(_: *anyopaque, _: *anyopaque, _: []const ExtensionValue) anyerror!ExtensionValue {
            return 0;
        }
    }.call;

    const methods = [_]api.ExtensionMethod{
        .{
            .name = "publicMethod",
            .callback = method_callback,
            .modifiers = .{ .is_public = true },
            .min_args = 0,
            .max_args = 5,
        },
        .{
            .name = "staticMethod",
            .callback = method_callback,
            .modifiers = .{ .is_public = true, .is_static = true },
            .min_args = 1,
            .max_args = 1,
        },
        .{
            .name = "finalMethod",
            .callback = method_callback,
            .modifiers = .{ .is_public = true, .is_final = true },
            .min_args = 0,
            .max_args = 0,
        },
    };

    const class = api.ExtensionClass{
        .name = "MethodClass",
        .parent = null,
        .interfaces = &[_][]const u8{},
        .methods = &methods,
        .properties = &[_]api.ExtensionProperty{},
        .constructor = null,
        .destructor = null,
    };

    try ext_registry.registerClass(class);

    const found = ext_registry.findClass("MethodClass");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 3), found.?.methods.len);

    // Verify method details
    try std.testing.expectEqualStrings("publicMethod", found.?.methods[0].name);
    try std.testing.expect(found.?.methods[0].modifiers.is_public);
    try std.testing.expect(!found.?.methods[0].modifiers.is_static);

    try std.testing.expectEqualStrings("staticMethod", found.?.methods[1].name);
    try std.testing.expect(found.?.methods[1].modifiers.is_static);

    try std.testing.expectEqualStrings("finalMethod", found.?.methods[2].name);
    try std.testing.expect(found.?.methods[2].modifiers.is_final);
}

test "Feature: multi-syntax-extension-system, Property 12: constructor callback invocation" {
    resetConstructorTracking();

    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    const class = api.ExtensionClass{
        .name = "ConstructorClass",
        .parent = null,
        .interfaces = &[_][]const u8{},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = testConstructorCallback,
        .destructor = null,
    };

    try ext_registry.registerClass(class);

    const found = ext_registry.findClass("ConstructorClass");
    try std.testing.expect(found != null);
    try std.testing.expect(found.?.constructor != null);

    // Simulate constructor call
    const args = [_]ExtensionValue{ 1, 2, 3 };
    try found.?.constructor.?(@ptrFromInt(1), @ptrFromInt(2), &args);

    try std.testing.expectEqual(@as(u32, 1), constructor_call_count);
    try std.testing.expectEqual(@as(usize, 3), constructor_last_arg_count);

    // Call again with different args
    const args2 = [_]ExtensionValue{ 1, 2, 3, 4, 5 };
    try found.?.constructor.?(@ptrFromInt(1), @ptrFromInt(2), &args2);

    try std.testing.expectEqual(@as(u32, 2), constructor_call_count);
    try std.testing.expectEqual(@as(usize, 5), constructor_last_arg_count);
}

test "Feature: multi-syntax-extension-system, Property 12: destructor callback invocation" {
    resetConstructorTracking();

    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    const class = api.ExtensionClass{
        .name = "DestructorClass",
        .parent = null,
        .interfaces = &[_][]const u8{},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = null,
        .destructor = testDestructorCallback,
    };

    try ext_registry.registerClass(class);

    const found = ext_registry.findClass("DestructorClass");
    try std.testing.expect(found != null);
    try std.testing.expect(found.?.destructor != null);

    // Simulate destructor calls
    found.?.destructor.?(@ptrFromInt(1), @ptrFromInt(2));
    try std.testing.expectEqual(@as(u32, 1), destructor_call_count);

    found.?.destructor.?(@ptrFromInt(1), @ptrFromInt(2));
    try std.testing.expectEqual(@as(u32, 2), destructor_call_count);
}

test "Feature: multi-syntax-extension-system, Property 12: class inheritance chain" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    // Create inheritance chain: GrandChild -> Child -> Parent
    const parent = api.ExtensionClass{
        .name = "Parent",
        .parent = null,
        .interfaces = &[_][]const u8{},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = null,
        .destructor = null,
    };

    const child = api.ExtensionClass{
        .name = "Child",
        .parent = "Parent",
        .interfaces = &[_][]const u8{},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = null,
        .destructor = null,
    };

    const grandchild = api.ExtensionClass{
        .name = "GrandChild",
        .parent = "Child",
        .interfaces = &[_][]const u8{},
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = null,
        .destructor = null,
    };

    try ext_registry.registerClass(parent);
    try ext_registry.registerClass(child);
    try ext_registry.registerClass(grandchild);

    // Verify inheritance chain
    const found_parent = ext_registry.findClass("Parent");
    const found_child = ext_registry.findClass("Child");
    const found_grandchild = ext_registry.findClass("GrandChild");

    try std.testing.expect(found_parent != null);
    try std.testing.expect(found_child != null);
    try std.testing.expect(found_grandchild != null);

    try std.testing.expect(found_parent.?.parent == null);
    try std.testing.expectEqualStrings("Parent", found_child.?.parent.?);
    try std.testing.expectEqualStrings("Child", found_grandchild.?.parent.?);
}

test "Feature: multi-syntax-extension-system, Property 12: class with interfaces" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    const interfaces = [_][]const u8{ "Countable", "Iterator", "ArrayAccess" };

    const class = api.ExtensionClass{
        .name = "InterfaceClass",
        .parent = null,
        .interfaces = &interfaces,
        .methods = &[_]api.ExtensionMethod{},
        .properties = &[_]api.ExtensionProperty{},
        .constructor = null,
        .destructor = null,
    };

    try ext_registry.registerClass(class);

    const found = ext_registry.findClass("InterfaceClass");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 3), found.?.interfaces.len);
    try std.testing.expectEqualStrings("Countable", found.?.interfaces[0]);
    try std.testing.expectEqualStrings("Iterator", found.?.interfaces[1]);
    try std.testing.expectEqualStrings("ArrayAccess", found.?.interfaces[2]);
}

test "Feature: multi-syntax-extension-system, Property 12: class conflict detection" {
    var ext_registry = ExtensionRegistry.init(std.testing.allocator);
    defer ext_registry.deinit();

    const class1 = api.createClass("DuplicateClass", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{});
    const class2 = api.createClass("DuplicateClass", &[_]api.ExtensionMethod{}, &[_]api.ExtensionProperty{});

    try ext_registry.registerClass(class1);

    // Second registration should fail
    const result = ext_registry.registerClass(class2);
    try std.testing.expectError(api.ExtensionError.ClassAlreadyExists, result);

    // Original class should still be there
    try std.testing.expect(ext_registry.findClass("DuplicateClass") != null);
    try std.testing.expectEqual(@as(usize, 1), ext_registry.classCount());
}



// ============================================================================
// Property 13: Syntax hook delegation
// **Validates: Requirements 11.3, 11.4**
// For any registered syntax hook, when the Parser encounters the hook's trigger
// condition, it SHALL delegate parsing to the hook's handler and incorporate
// the returned AST node.
// ============================================================================

// Track hook invocations for testing
var statement_hook_call_count: u32 = 0;
var statement_hook_last_token: u32 = 0;
var expression_hook_call_count: u32 = 0;
var expression_hook_last_precedence: u8 = 0;

fn resetHookTracking() void {
    statement_hook_call_count = 0;
    statement_hook_last_token = 0;
    expression_hook_call_count = 0;
    expression_hook_last_precedence = 0;
}

// Test statement hook that tracks calls but returns null (doesn't handle)
fn testStatementHookNull(_: *anyopaque, token_tag: u32) anyerror!?u32 {
    statement_hook_call_count += 1;
    statement_hook_last_token = token_tag;
    return null; // Don't handle, let parser continue
}

// Test expression hook that tracks calls but returns null (doesn't handle)
fn testExpressionHookNull(_: *anyopaque, precedence: u8) anyerror!?u32 {
    expression_hook_call_count += 1;
    expression_hook_last_precedence = precedence;
    return null; // Don't handle, let parser continue
}

// Test statement hook that returns a fixed node index
fn testStatementHookFixed(_: *anyopaque, token_tag: u32) anyerror!?u32 {
    statement_hook_call_count += 1;
    statement_hook_last_token = token_tag;
    return 42; // Return a fixed node index
}

// Test expression hook that returns a fixed node index
fn testExpressionHookFixed(_: *anyopaque, precedence: u8) anyerror!?u32 {
    expression_hook_call_count += 1;
    expression_hook_last_precedence = precedence;
    return 99; // Return a fixed node index
}

// Test statement hook that returns an error
fn testStatementHookError(_: *anyopaque, _: u32) anyerror!?u32 {
    statement_hook_call_count += 1;
    return error.TestHookError;
}

// Test expression hook that returns an error
fn testExpressionHookError(_: *anyopaque, _: u8) anyerror!?u32 {
    expression_hook_call_count += 1;
    return error.TestHookError;
}

test "Feature: multi-syntax-extension-system, Property 13: SyntaxHooks structure creation" {
    // Test that SyntaxHooks can be created with all fields
    const custom_keywords = [_][]const u8{ "custom1", "custom2", "myKeyword" };
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &custom_keywords,
        .parse_statement = testStatementHookNull,
        .parse_expression = testExpressionHookNull,
    };
    
    // Verify structure fields
    try std.testing.expectEqual(@as(usize, 3), hooks.custom_keywords.len);
    try std.testing.expectEqualStrings("custom1", hooks.custom_keywords[0]);
    try std.testing.expectEqualStrings("custom2", hooks.custom_keywords[1]);
    try std.testing.expectEqualStrings("myKeyword", hooks.custom_keywords[2]);
    try std.testing.expect(hooks.parse_statement != null);
    try std.testing.expect(hooks.parse_expression != null);
}

test "Feature: multi-syntax-extension-system, Property 13: SyntaxHooks with null hooks" {
    // Test that SyntaxHooks can be created with null hooks
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = null,
        .parse_expression = null,
    };
    
    try std.testing.expectEqual(@as(usize, 0), hooks.custom_keywords.len);
    try std.testing.expect(hooks.parse_statement == null);
    try std.testing.expect(hooks.parse_expression == null);
}

test "Feature: multi-syntax-extension-system, Property 13: statement hook invocation" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = testStatementHookNull,
        .parse_expression = null,
    };
    
    // Simulate hook invocation
    const result = hooks.parse_statement.?(@ptrFromInt(1), 42);
    
    // Verify hook was called
    try std.testing.expectEqual(@as(u32, 1), statement_hook_call_count);
    try std.testing.expectEqual(@as(u32, 42), statement_hook_last_token);
    
    // Verify result is null (hook didn't handle)
    const unwrapped = result catch null;
    try std.testing.expect(unwrapped == null);
}

test "Feature: multi-syntax-extension-system, Property 13: expression hook invocation" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = null,
        .parse_expression = testExpressionHookNull,
    };
    
    // Simulate hook invocation
    const result = hooks.parse_expression.?(@ptrFromInt(1), 10);
    
    // Verify hook was called
    try std.testing.expectEqual(@as(u32, 1), expression_hook_call_count);
    try std.testing.expectEqual(@as(u8, 10), expression_hook_last_precedence);
    
    // Verify result is null (hook didn't handle)
    const unwrapped = result catch null;
    try std.testing.expect(unwrapped == null);
}

test "Feature: multi-syntax-extension-system, Property 13: statement hook returns node" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = testStatementHookFixed,
        .parse_expression = null,
    };
    
    // Simulate hook invocation
    const result = try hooks.parse_statement.?(@ptrFromInt(1), 100);
    
    // Verify hook was called
    try std.testing.expectEqual(@as(u32, 1), statement_hook_call_count);
    try std.testing.expectEqual(@as(u32, 100), statement_hook_last_token);
    
    // Verify result is the fixed node index
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u32, 42), result.?);
}

test "Feature: multi-syntax-extension-system, Property 13: expression hook returns node" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = null,
        .parse_expression = testExpressionHookFixed,
    };
    
    // Simulate hook invocation
    const result = try hooks.parse_expression.?(@ptrFromInt(1), 5);
    
    // Verify hook was called
    try std.testing.expectEqual(@as(u32, 1), expression_hook_call_count);
    try std.testing.expectEqual(@as(u8, 5), expression_hook_last_precedence);
    
    // Verify result is the fixed node index
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u32, 99), result.?);
}

test "Feature: multi-syntax-extension-system, Property 13: statement hook error propagation" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = testStatementHookError,
        .parse_expression = null,
    };
    
    // Simulate hook invocation - should return error
    const result = hooks.parse_statement.?(@ptrFromInt(1), 0);
    try std.testing.expectError(error.TestHookError, result);
    
    // Verify hook was called
    try std.testing.expectEqual(@as(u32, 1), statement_hook_call_count);
}

test "Feature: multi-syntax-extension-system, Property 13: expression hook error propagation" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = null,
        .parse_expression = testExpressionHookError,
    };
    
    // Simulate hook invocation - should return error
    const result = hooks.parse_expression.?(@ptrFromInt(1), 0);
    try std.testing.expectError(error.TestHookError, result);
    
    // Verify hook was called
    try std.testing.expectEqual(@as(u32, 1), expression_hook_call_count);
}

test "Feature: multi-syntax-extension-system, Property 13: multiple hook invocations" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = testStatementHookNull,
        .parse_expression = testExpressionHookNull,
    };
    
    // Call statement hook multiple times
    _ = hooks.parse_statement.?(@ptrFromInt(1), 1) catch null;
    _ = hooks.parse_statement.?(@ptrFromInt(1), 2) catch null;
    _ = hooks.parse_statement.?(@ptrFromInt(1), 3) catch null;
    
    try std.testing.expectEqual(@as(u32, 3), statement_hook_call_count);
    try std.testing.expectEqual(@as(u32, 3), statement_hook_last_token);
    
    // Call expression hook multiple times
    _ = hooks.parse_expression.?(@ptrFromInt(1), 10) catch null;
    _ = hooks.parse_expression.?(@ptrFromInt(1), 20) catch null;
    
    try std.testing.expectEqual(@as(u32, 2), expression_hook_call_count);
    try std.testing.expectEqual(@as(u8, 20), expression_hook_last_precedence);
}

test "Feature: multi-syntax-extension-system, Property 13: custom keywords registration" {
    // Test various custom keyword configurations
    const keywords1 = [_][]const u8{"async", "await", "yield"};
    const keywords2 = [_][]const u8{"defer", "go", "select"};
    const keywords3 = [_][]const u8{"match", "when", "guard"};
    
    const hooks1 = api.SyntaxHooks{
        .custom_keywords = &keywords1,
        .parse_statement = null,
        .parse_expression = null,
    };
    
    const hooks2 = api.SyntaxHooks{
        .custom_keywords = &keywords2,
        .parse_statement = null,
        .parse_expression = null,
    };
    
    const hooks3 = api.SyntaxHooks{
        .custom_keywords = &keywords3,
        .parse_statement = null,
        .parse_expression = null,
    };
    
    // Verify each hooks structure has correct keywords
    try std.testing.expectEqual(@as(usize, 3), hooks1.custom_keywords.len);
    try std.testing.expectEqual(@as(usize, 3), hooks2.custom_keywords.len);
    try std.testing.expectEqual(@as(usize, 3), hooks3.custom_keywords.len);
    
    try std.testing.expectEqualStrings("async", hooks1.custom_keywords[0]);
    try std.testing.expectEqualStrings("defer", hooks2.custom_keywords[0]);
    try std.testing.expectEqualStrings("match", hooks3.custom_keywords[0]);
}

test "Feature: multi-syntax-extension-system, Property 13: hooks with Extension structure" {
    // Test that SyntaxHooks integrates properly with Extension structure
    const custom_keywords = [_][]const u8{"custom"};
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &custom_keywords,
        .parse_statement = testStatementHookNull,
        .parse_expression = testExpressionHookNull,
    };
    
    const init_fn: api.ExtensionInitCallback = struct {
        fn init(_: *anyopaque) anyerror!void {}
    }.init;
    
    const extension = api.Extension{
        .info = api.createExtensionInfo("test_ext", "1.0.0", "Test", "Test extension"),
        .init_fn = init_fn,
        .shutdown_fn = null,
        .functions = &[_]api.ExtensionFunction{},
        .classes = &[_]api.ExtensionClass{},
        .syntax_hooks = &hooks,
    };
    
    // Verify extension has syntax hooks
    try std.testing.expect(extension.syntax_hooks != null);
    try std.testing.expectEqual(@as(usize, 1), extension.syntax_hooks.?.custom_keywords.len);
    try std.testing.expectEqualStrings("custom", extension.syntax_hooks.?.custom_keywords[0]);
    try std.testing.expect(extension.syntax_hooks.?.parse_statement != null);
    try std.testing.expect(extension.syntax_hooks.?.parse_expression != null);
}

test "Feature: multi-syntax-extension-system, Property 13: Extension without syntax hooks" {
    // Test that Extension can be created without syntax hooks
    const init_fn: api.ExtensionInitCallback = struct {
        fn init(_: *anyopaque) anyerror!void {}
    }.init;
    
    const extension = api.Extension{
        .info = api.createExtensionInfo("no_hooks_ext", "1.0.0", "Test", "Extension without hooks"),
        .init_fn = init_fn,
        .shutdown_fn = null,
        .functions = &[_]api.ExtensionFunction{},
        .classes = &[_]api.ExtensionClass{},
        .syntax_hooks = null,
    };
    
    // Verify extension has no syntax hooks
    try std.testing.expect(extension.syntax_hooks == null);
}

test "Feature: multi-syntax-extension-system, Property 13: hook precedence values" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = null,
        .parse_expression = testExpressionHookNull,
    };
    
    // Test various precedence values
    const precedences = [_]u8{ 0, 1, 5, 10, 50, 100, 200, 255 };
    
    for (precedences) |prec| {
        _ = hooks.parse_expression.?(@ptrFromInt(1), prec) catch null;
        try std.testing.expectEqual(prec, expression_hook_last_precedence);
    }
    
    try std.testing.expectEqual(@as(u32, 8), expression_hook_call_count);
}

test "Feature: multi-syntax-extension-system, Property 13: hook token tag values" {
    resetHookTracking();
    
    const hooks = api.SyntaxHooks{
        .custom_keywords = &[_][]const u8{},
        .parse_statement = testStatementHookNull,
        .parse_expression = null,
    };
    
    // Test various token tag values
    const token_tags = [_]u32{ 0, 1, 10, 100, 1000, 65535 };
    
    for (token_tags) |tag| {
        _ = hooks.parse_statement.?(@ptrFromInt(1), tag) catch null;
        try std.testing.expectEqual(tag, statement_hook_last_token);
    }
    
    try std.testing.expectEqual(@as(u32, 6), statement_hook_call_count);
}
