const std = @import("std");
const testing = std.testing;
const exceptions = @import("runtime/exceptions.zig");
const types = @import("runtime/types.zig");
const PHPException = exceptions.PHPException;
const ErrorHandler = exceptions.ErrorHandler;
const ErrorType = exceptions.ErrorType;
const TryCatchContext = exceptions.TryCatchContext;
const ExceptionFactory = exceptions.ExceptionFactory;
const ErrorRecovery = exceptions.ErrorRecovery;

test "PHPException creation and basic functionality" {
    const allocator = testing.allocator;
    
    // Test basic exception creation
    const exception = try PHPException.init(allocator, .type_error, "Test error message", "test.php", 42);
    defer exception.deinit(allocator);
    
    try testing.expect(exception.exception_type == .type_error);
    try testing.expectEqualStrings("Test error message", exception.message.data);
    try testing.expectEqualStrings("test.php", exception.file.data);
    try testing.expectEqual(@as(u32, 42), exception.line);
    try testing.expectEqual(@as(i64, 0), exception.code);
    try testing.expect(exception.previous == null);
}

test "PHPException with code" {
    const allocator = testing.allocator;
    
    // Create exception with code
    const exception = try PHPException.initWithCode(allocator, .type_error, "Current error", 123, "test.php", 20);
    defer exception.deinit(allocator);
    
    try testing.expectEqual(@as(i64, 123), exception.code);
    try testing.expect(exception.exception_type == .type_error);
}

test "PHPException toString functionality" {
    const allocator = testing.allocator;
    
    const exception = try PHPException.init(allocator, .parse_error, "Syntax error", "script.php", 15);
    defer exception.deinit(allocator);
    
    const str = try exception.toString(allocator);
    defer str.deinit(allocator);
    
    try testing.expect(std.mem.indexOf(u8, str.data, "ParseError") != null);
    try testing.expect(std.mem.indexOf(u8, str.data, "Syntax error") != null);
    try testing.expect(std.mem.indexOf(u8, str.data, "script.php") != null);
    try testing.expect(std.mem.indexOf(u8, str.data, "15") != null);
}

test "ErrorHandler basic functionality" {
    const allocator = testing.allocator;
    
    var error_handler = ErrorHandler.init(allocator);
    defer error_handler.deinit();
    
    // Test error reporting settings
    error_handler.setErrorReporting(0xFFFF);
    error_handler.setDisplayErrors(false);
    error_handler.setLogErrors(false);
    
    // Test handling a warning (should not throw)
    try error_handler.handleError(.warning, "Test warning", "test.php", 10);
    
    // Test handling a fatal error (should throw)
    const result = error_handler.handleError(.fatal_error, "Fatal error", "test.php", 20);
    try testing.expectError(error.FatalError, result);
}

test "ErrorHandler with custom handler" {
    const allocator = testing.allocator;
    
    var error_handler = ErrorHandler.init(allocator);
    defer error_handler.deinit();
    
    const CustomHandler = struct {
        fn handler(error_type: ErrorType, message: []const u8, file: []const u8, line: u32) void {
            _ = error_type;
            _ = message;
            _ = file;
            _ = line;
            // Custom handler logic would go here
        }
    };
    
    error_handler.setErrorHandler(.warning, CustomHandler.handler);
    
    // This should call our custom handler
    try error_handler.handleError(.warning, "Custom warning", "test.php", 5);
}

test "TryCatchContext exception matching" {
    const allocator = testing.allocator;
    
    var context = TryCatchContext.init(allocator);
    defer context.deinit();
    
    // Create an exception
    const exception = try PHPException.init(allocator, .type_error, "Type error", "test.php", 1);
    defer if (context.caught_exception == null) exception.deinit(allocator);
    
    // Test catching the exception
    const caught = context.catchException(exception, .type_error);
    try testing.expect(caught);
    try testing.expect(context.caught_exception != null);
    try testing.expect(context.caught_exception.?.exception_type == .type_error);
    
    // Test finally execution
    try testing.expect(!context.finally_executed);
    context.executeFinally();
    try testing.expect(context.finally_executed);
}

test "TryCatchContext exception hierarchy matching" {
    const allocator = testing.allocator;
    
    var context = TryCatchContext.init(allocator);
    defer context.deinit();
    
    // Create a specific exception
    const exception = try PHPException.init(allocator, .type_error, "Type error", "test.php", 1);
    defer if (context.caught_exception == null) exception.deinit(allocator);
    
    // Test catching with base Exception type (should match)
    const caught = context.catchException(exception, .exception);
    try testing.expect(caught);
}

test "ExceptionFactory functions" {
    const allocator = testing.allocator;
    
    // Test parse error creation
    const parse_error = try ExceptionFactory.createParseError(allocator, "Parse error", "test.php", 1);
    defer parse_error.deinit(allocator);
    try testing.expect(parse_error.exception_type == .parse_error);
    
    // Test type error creation
    const type_error = try ExceptionFactory.createTypeError(allocator, "Type error", "test.php", 2);
    defer type_error.deinit(allocator);
    try testing.expect(type_error.exception_type == .type_error);
    
    // Test argument count error creation
    const arg_error = try ExceptionFactory.createArgumentCountError(allocator, 2, 1, "testFunc", "test.php", 3);
    defer arg_error.deinit(allocator);
    try testing.expect(arg_error.exception_type == .argument_count_error);
    try testing.expect(std.mem.indexOf(u8, arg_error.message.data, "testFunc") != null);
    try testing.expect(std.mem.indexOf(u8, arg_error.message.data, "expects 2") != null);
    try testing.expect(std.mem.indexOf(u8, arg_error.message.data, "1 given") != null);
    
    // Test undefined variable error
    const var_error = try ExceptionFactory.createUndefinedVariableError(allocator, "undefinedVar", "test.php", 4);
    defer var_error.deinit(allocator);
    try testing.expect(var_error.exception_type == .undefined_variable_error);
    try testing.expect(std.mem.indexOf(u8, var_error.message.data, "$undefinedVar") != null);
    
    // Test undefined function error
    const func_error = try ExceptionFactory.createUndefinedFunctionError(allocator, "undefinedFunc", "test.php", 5);
    defer func_error.deinit(allocator);
    try testing.expect(func_error.exception_type == .undefined_function_error);
    try testing.expect(std.mem.indexOf(u8, func_error.message.data, "undefinedFunc()") != null);
    
    // Test undefined class error
    const class_error = try ExceptionFactory.createUndefinedClassError(allocator, "UndefinedClass", "test.php", 6);
    defer class_error.deinit(allocator);
    try testing.expect(class_error.exception_type == .undefined_class_error);
    try testing.expect(std.mem.indexOf(u8, class_error.message.data, "UndefinedClass") != null);
    
    // Test undefined method error
    const method_error = try ExceptionFactory.createUndefinedMethodError(allocator, "TestClass", "undefinedMethod", "test.php", 7);
    defer method_error.deinit(allocator);
    try testing.expect(method_error.exception_type == .undefined_method_error);
    try testing.expect(std.mem.indexOf(u8, method_error.message.data, "TestClass::undefinedMethod()") != null);
    
    // Test undefined property error
    const prop_error = try ExceptionFactory.createUndefinedPropertyError(allocator, "TestClass", "undefinedProp", "test.php", 8);
    defer prop_error.deinit(allocator);
    try testing.expect(prop_error.exception_type == .undefined_property_error);
    try testing.expect(std.mem.indexOf(u8, prop_error.message.data, "TestClass::$undefinedProp") != null);
    
    // Test readonly property error
    const readonly_error = try ExceptionFactory.createReadonlyPropertyError(allocator, "TestClass", "readonlyProp", "test.php", 9);
    defer readonly_error.deinit(allocator);
    try testing.expect(readonly_error.exception_type == .readonly_property_error);
    try testing.expect(std.mem.indexOf(u8, readonly_error.message.data, "readonly property") != null);
    
    // Test division by zero error
    const div_error = try ExceptionFactory.createDivisionByZeroError(allocator, "test.php", 10);
    defer div_error.deinit(allocator);
    try testing.expect(div_error.exception_type == .division_by_zero_error);
    try testing.expectEqualStrings("Division by zero", div_error.message.data);
}

test "ErrorType utility functions" {
    // Test isFatal function
    try testing.expect(ErrorType.fatal_error.isFatal());
    try testing.expect(ErrorType.parse_error.isFatal());
    try testing.expect(ErrorType.compile_error.isFatal());
    try testing.expect(ErrorType.core_error.isFatal());
    
    try testing.expect(!ErrorType.warning.isFatal());
    try testing.expect(!ErrorType.notice.isFatal());
    try testing.expect(!ErrorType.deprecated.isFatal());
    
    // Test toString function
    try testing.expectEqualStrings("Fatal error", ErrorType.fatal_error.toString());
    try testing.expectEqualStrings("Parse error", ErrorType.parse_error.toString());
    try testing.expectEqualStrings("Warning", ErrorType.warning.toString());
    try testing.expectEqualStrings("Notice", ErrorType.notice.toString());
}

test "ErrorRecovery functions" {
    const allocator = testing.allocator;
    
    // Test parse error recovery
    const source = "<?php $x = ; echo 'hello';";
    const recovered = try ErrorRecovery.recoverFromParseError(allocator, source, 11); // Position after "= "
    try testing.expect(recovered.len < source.len);
    
    // Test runtime error recovery
    try ErrorRecovery.recoverFromRuntimeError(.warning); // Should not throw
    try ErrorRecovery.recoverFromRuntimeError(.notice); // Should not throw
    
    const fatal_result = ErrorRecovery.recoverFromRuntimeError(.fatal_error);
    try testing.expectError(error.FatalError, fatal_result);
    
    // Test suggestion system
    const suggestion1 = ErrorRecovery.suggestFix(.undefined_variable_error, "");
    try testing.expect(suggestion1 != null);
    try testing.expect(std.mem.indexOf(u8, suggestion1.?, "variable") != null);
    
    const suggestion2 = ErrorRecovery.suggestFix(.type_error, "");
    try testing.expect(suggestion2 != null);
    try testing.expect(std.mem.indexOf(u8, suggestion2.?, "types") != null);
    
    const suggestion3 = ErrorRecovery.suggestFix(.division_by_zero_error, "");
    try testing.expect(suggestion3 != null);
    try testing.expect(std.mem.indexOf(u8, suggestion3.?, "division by zero") != null);
    
    // Test no suggestion for unknown types
    const no_suggestion = ErrorRecovery.suggestFix(.exception, "");
    try testing.expect(no_suggestion == null);
}

test "Stack trace functionality" {
    const allocator = testing.allocator;
    
    // Create exception
    const exception = try PHPException.init(allocator, .type_error, "Test error", "test.php", 25);
    defer exception.deinit(allocator);
    
    // Test that exception was created successfully
    try testing.expect(exception.exception_type == .type_error);
    try testing.expectEqualStrings("Test error", exception.message.data);
}