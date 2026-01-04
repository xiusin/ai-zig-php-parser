const std = @import("std");
const testing = std.testing;
const VM = @import("runtime/vm.zig").VM;
const types = @import("runtime/types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const UserFunction = types.UserFunction;
const Closure = types.Closure;
const ArrowFunction = types.ArrowFunction;

test "UserFunction parameter validation" {
    const allocator = testing.allocator;
    
    // Create a function with 2 required parameters
    const func_name = try PHPString.init(allocator, "test_func");
    defer func_name.deinit(allocator);
    
    var user_function = UserFunction.init(func_name);
    user_function.min_args = 2;
    user_function.max_args = 2;
    
    // Test with correct number of arguments
    const args_correct = [_]Value{ Value.initInt(1), Value.initInt(2) };
    try user_function.validateArguments(&args_correct);
    
    // Test with too few arguments
    const args_few = [_]Value{Value.initInt(1)};
    try testing.expectError(error.TooFewArguments, user_function.validateArguments(&args_few));
    
    // Test with too many arguments
    const args_many = [_]Value{ Value.initInt(1), Value.initInt(2), Value.initInt(3) };
    try testing.expectError(error.TooManyArguments, user_function.validateArguments(&args_many));
}

test "UserFunction variadic parameters" {
    const allocator = testing.allocator;
    
    // Create a variadic function
    const func_name = try PHPString.init(allocator, "variadic_func");
    defer func_name.deinit(allocator);
    
    var user_function = UserFunction.init(func_name);
    user_function.min_args = 1;
    user_function.max_args = null; // Unlimited
    user_function.is_variadic = true;
    
    // Test with minimum arguments
    const args_min = [_]Value{Value.initInt(1)};
    try user_function.validateArguments(&args_min);
    
    // Test with many arguments (should be allowed)
    const args_many = [_]Value{ Value.initInt(1), Value.initInt(2), Value.initInt(3), Value.initInt(4) };
    try user_function.validateArguments(&args_many);
    
    // Test with too few arguments
    const args_few: []const Value = &[_]Value{};
    try testing.expectError(error.TooFewArguments, user_function.validateArguments(args_few));
}

test "Parameter type validation" {
    const allocator = testing.allocator;
    
    // Create parameter with int type constraint
    const param_name = try PHPString.init(allocator, "test_param");
    defer param_name.deinit(allocator);
    
    const type_name = try PHPString.init(allocator, "int");
    defer type_name.deinit(allocator);
    
    var parameter = types.Method.Parameter.init(param_name);
    parameter.type = types.TypeInfo.init(type_name, .integer);
    
    // Test with correct type
    const int_value = Value.initInt(42);
    try parameter.validateType(int_value);
    
    // Test with incorrect type
    const string_value = try Value.initString(allocator, "not an int");
    defer {
        string_value.release(allocator);
    }
    try testing.expectError(error.TypeError, parameter.validateType(string_value));
}

test "Parameter nullable type validation" {
    const allocator = testing.allocator;
    
    // Create parameter with nullable int type constraint
    const param_name = try PHPString.init(allocator, "nullable_param");
    defer param_name.deinit(allocator);
    
    const type_name = try PHPString.init(allocator, "int");
    defer type_name.deinit(allocator);
    
    var parameter = types.Method.Parameter.init(param_name);
    var type_info = types.TypeInfo.init(type_name, .integer);
    type_info.is_nullable = true;
    parameter.type = type_info;
    
    // Test with null value (should be allowed)
    const null_value = Value.initNull();
    try parameter.validateType(null_value);
    
    // Test with correct type
    const int_value = Value.initInt(42);
    try parameter.validateType(int_value);
    
    // Test with incorrect type
    const string_value = try Value.initString(allocator, "not an int");
    defer {
        string_value.release(allocator);
    }
    try testing.expectError(error.TypeError, parameter.validateType(string_value));
}

test "Closure creation and variable capture" {
    const allocator = testing.allocator;
    
    // Create a simple function
    const func_name = try PHPString.init(allocator, "closure_func");
    defer func_name.deinit(allocator);
    
    const user_function = UserFunction.init(func_name);
    var closure = Closure.init(allocator, user_function);
    defer closure.deinit(allocator);
    
    // Capture a variable
    const captured_value = Value.initInt(100);
    try closure.captureVariable("x", captured_value);
    
    // Verify variable was captured
    const retrieved_value = closure.captured_vars.get("x");
    try testing.expect(retrieved_value != null);
    try testing.expectEqual(@as(i64, 100), retrieved_value.?.asInt());
}

test "ArrowFunction creation and auto-capture" {
    const allocator = testing.allocator;
    
    var arrow_function = ArrowFunction.init(allocator);
    defer arrow_function.deinit(allocator);
    
    // Auto-capture a variable
    const captured_value = Value.initInt(200);
    try arrow_function.autoCaptureVariable("y", captured_value);
    
    // Verify variable was captured
    const retrieved_value = arrow_function.captured_vars.get("y");
    try testing.expect(retrieved_value != null);
    try testing.expectEqual(@as(i64, 200), retrieved_value.?.asInt());
}

test "Value isCallable function" {
    const allocator = testing.allocator;
    
    // Test builtin function (native function)
    const builtin_value = Value.initNativeFunction(@as(*const fn (*anyopaque, []const Value) anyerror!Value, undefined));
    try testing.expect(builtin_value.isCallable());
    
    // Test user function
    const func_name = try PHPString.init(allocator, "test");
    defer func_name.deinit(allocator);
    
    const user_function = try allocator.create(UserFunction);
    defer allocator.destroy(user_function);
    user_function.* = UserFunction.init(func_name);
    
    const box = try allocator.create(types.gc.Box(*UserFunction));
    defer allocator.destroy(box);
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = user_function,
    };
    
    const user_func_value = Value.fromBox(box, Value.TYPE_USER_FUNC);
    try testing.expect(user_func_value.isCallable());
    
    // Test closure
    const closure = try allocator.create(Closure);
    defer allocator.destroy(closure);
    closure.* = Closure.init(allocator, user_function.*);
    defer closure.deinit(allocator);
    
    const closure_box = try allocator.create(types.gc.Box(*Closure));
    defer allocator.destroy(closure_box);
    closure_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = closure,
    };
    
    const closure_value = Value.fromBox(closure_box, Value.TYPE_CLOSURE);
    try testing.expect(closure_value.isCallable());
    
    // Test arrow function
    const arrow_function = try allocator.create(ArrowFunction);
    defer allocator.destroy(arrow_function);
    arrow_function.* = ArrowFunction.init(allocator);
    defer arrow_function.deinit(allocator);
    
    const arrow_box = try allocator.create(types.gc.Box(*ArrowFunction));
    defer allocator.destroy(arrow_box);
    arrow_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = arrow_function,
    };
    
    const arrow_value = Value.fromBox(arrow_box, Value.TYPE_CLOSURE);
    try testing.expect(arrow_value.isCallable());
    
    // Test non-callable value
    const int_value = Value.initInt(42);
    try testing.expect(!int_value.isCallable());
}

test "VM enhanced function calls" {
    const allocator = testing.allocator;
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    // Test is_callable builtin function
    const callable_value = Value.initNativeFunction(@as(*const fn (*anyopaque, []const Value) anyerror!Value, undefined));
    _ = callable_value;
    
    // This would test the is_callable function, but we need a proper VM context
    // For now, just verify the function exists
    const is_callable_func = vm.global.get("is_callable");
    try testing.expect(is_callable_func != null);
    try testing.expect(is_callable_func.?.getTag() == .native_function);
}