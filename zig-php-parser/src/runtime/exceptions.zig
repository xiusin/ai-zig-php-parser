const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;

/// Stack frame information for exception traces
pub const StackFrame = struct {
    function_name: *PHPString,
    file_name: *PHPString,
    line: u32,
    column: u32,
    
    pub fn init(allocator: std.mem.Allocator, function_name: []const u8, file_name: []const u8, line: u32, column: u32) !StackFrame {
        return StackFrame{
            .function_name = try PHPString.init(allocator, function_name),
            .file_name = try PHPString.init(allocator, file_name),
            .line = line,
            .column = column,
        };
    }
    
    pub fn deinit(self: *StackFrame, allocator: std.mem.Allocator) void {
        self.function_name.deinit(allocator);
        self.file_name.deinit(allocator);
    }
};

/// Base PHP Exception class
pub const PHPException = struct {
    message: *PHPString,
    code: i64,
    file: *PHPString,
    line: u32,
    trace: []StackFrame,
    previous: ?*PHPException,
    exception_type: ExceptionType,
    
    pub const ExceptionType = enum {
        // Base exceptions
        exception,
        error_exception,
        
        // Parse and compile errors
        parse_error,
        compile_error,
        
        // Runtime errors
        fatal_error,
        type_error,
        value_error,
        argument_count_error,
        
        // User-defined exceptions
        user_exception,
        
        // Specific PHP exceptions
        undefined_variable_error,
        undefined_function_error,
        undefined_class_error,
        undefined_method_error,
        undefined_property_error,
        readonly_property_error,
        invalid_argument_error,
        out_of_bounds_error,
        division_by_zero_error,
    };
    
    pub fn init(allocator: std.mem.Allocator, exception_type: ExceptionType, message: []const u8, file: []const u8, line: u32) !*PHPException {
        const exception = try allocator.create(PHPException);
        exception.* = PHPException{
            .message = try PHPString.init(allocator, message),
            .code = 0,
            .file = try PHPString.init(allocator, file),
            .line = line,
            .trace = &[_]StackFrame{},
            .previous = null,
            .exception_type = exception_type,
        };
        return exception;
    }
    
    pub fn initWithCode(allocator: std.mem.Allocator, exception_type: ExceptionType, message: []const u8, code: i64, file: []const u8, line: u32) !*PHPException {
        const exception = try init(allocator, exception_type, message, file, line);
        exception.code = code;
        return exception;
    }
    
    pub fn initWithPrevious(allocator: std.mem.Allocator, exception_type: ExceptionType, message: []const u8, file: []const u8, line: u32, previous: *PHPException) !*PHPException {
        const exception = try init(allocator, exception_type, message, file, line);
        exception.previous = previous;
        return exception;
    }
    
    pub fn deinit(self: *PHPException, allocator: std.mem.Allocator) void {
        self.message.deinit(allocator);
        self.file.deinit(allocator);
        
        // Clean up stack trace
        for (self.trace) |*frame| {
            frame.deinit(allocator);
        }
        allocator.free(self.trace);
        
        // Clean up previous exception
        if (self.previous) |prev| {
            prev.deinit(allocator);
        }
        
        allocator.destroy(self);
    }
    
    pub fn setTrace(self: *PHPException, allocator: std.mem.Allocator, trace: []StackFrame) !void {
        // Free existing trace
        for (self.trace) |*frame| {
            frame.deinit(allocator);
        }
        allocator.free(self.trace);
        
        // Set new trace
        self.trace = try allocator.dupe(StackFrame, trace);
    }
    
    pub fn getTraceAsString(self: *PHPException, allocator: std.mem.Allocator) !*PHPString {
        // Simple implementation without ArrayList for now
        var total_len: usize = 0;
        
        // Calculate total length needed
        for (self.trace, 0..) |frame, i| {
            const line_len = std.fmt.count("#{d} {s}({d}): {s}\n", .{
                i, frame.file_name.data, frame.line, frame.function_name.data
            });
            total_len += line_len;
        }
        
        // Allocate buffer
        const buffer = try allocator.alloc(u8, total_len);
        var pos: usize = 0;
        
        // Fill buffer
        for (self.trace, 0..) |frame, i| {
            const written = try std.fmt.bufPrint(buffer[pos..], "#{d} {s}({d}): {s}\n", .{
                i, frame.file_name.data, frame.line, frame.function_name.data
            });
            pos += written.len;
        }
        
        const result = try PHPString.init(allocator, buffer);
        allocator.free(buffer);
        return result;
    }
    
    pub fn getMessage(self: *PHPException) *PHPString {
        return self.message;
    }
    
    pub fn getCode(self: *PHPException) i64 {
        return self.code;
    }
    
    pub fn getFile(self: *PHPException) *PHPString {
        return self.file;
    }
    
    pub fn getLine(self: *PHPException) u32 {
        return self.line;
    }
    
    pub fn getPrevious(self: *PHPException) ?*PHPException {
        return self.previous;
    }
    
    pub fn toString(self: *PHPException, allocator: std.mem.Allocator) !*PHPString {
        const type_name = switch (self.exception_type) {
            .exception => "Exception",
            .error_exception => "ErrorException",
            .parse_error => "ParseError",
            .compile_error => "CompileError",
            .fatal_error => "FatalError",
            .type_error => "TypeError",
            .value_error => "ValueError",
            .argument_count_error => "ArgumentCountError",
            .user_exception => "UserException",
            .undefined_variable_error => "UndefinedVariableError",
            .undefined_function_error => "UndefinedFunctionError",
            .undefined_class_error => "UndefinedClassError",
            .undefined_method_error => "UndefinedMethodError",
            .undefined_property_error => "UndefinedPropertyError",
            .readonly_property_error => "ReadonlyPropertyError",
            .invalid_argument_error => "InvalidArgumentError",
            .out_of_bounds_error => "OutOfBoundsError",
            .division_by_zero_error => "DivisionByZeroError",
        };
        
        const str = try std.fmt.allocPrint(allocator, "{s}: {s} in {s}:{d}", .{
            type_name, self.message.data, self.file.data, self.line
        });
        defer allocator.free(str);
        
        return PHPString.init(allocator, str);
    }
};

/// Error types for PHP error handling
pub const ErrorType = enum {
    // Fatal errors
    fatal_error,
    parse_error,
    compile_error,
    core_error,
    core_warning,
    
    // Recoverable errors
    warning,
    notice,
    strict,
    deprecated,
    
    // User errors
    user_error,
    user_warning,
    user_notice,
    user_deprecated,
    
    // Catchable fatal errors
    recoverable_error,
    
    pub fn isFatal(self: ErrorType) bool {
        return switch (self) {
            .fatal_error, .parse_error, .compile_error, .core_error => true,
            else => false,
        };
    }
    
    pub fn toString(self: ErrorType) []const u8 {
        return switch (self) {
            .fatal_error => "Fatal error",
            .parse_error => "Parse error",
            .compile_error => "Compile error",
            .core_error => "Core error",
            .core_warning => "Core warning",
            .warning => "Warning",
            .notice => "Notice",
            .strict => "Strict Standards",
            .deprecated => "Deprecated",
            .user_error => "User error",
            .user_warning => "User warning",
            .user_notice => "User notice",
            .user_deprecated => "User deprecated",
            .recoverable_error => "Recoverable error",
        };
    }
};

/// Error callback function type
pub const ErrorCallback = *const fn (error_type: ErrorType, message: []const u8, file: []const u8, line: u32) void;

/// Exception callback function type
pub const ExceptionCallback = *const fn (exception: *PHPException) void;

/// Error handler for managing PHP errors and exceptions
pub const ErrorHandler = struct {
    allocator: std.mem.Allocator,
    handlers: std.EnumMap(ErrorType, ?ErrorCallback),
    exception_handler: ?ExceptionCallback,
    error_reporting: u32,
    display_errors: bool,
    log_errors: bool,
    error_log: ?std.fs.File,
    
    pub fn init(allocator: std.mem.Allocator) ErrorHandler {
        return ErrorHandler{
            .allocator = allocator,
            .handlers = std.EnumMap(ErrorType, ?ErrorCallback).init(.{}),
            .exception_handler = null,
            .error_reporting = 0xFFFFFFFF, // Report all errors by default
            .display_errors = true,
            .log_errors = false,
            .error_log = null,
        };
    }
    
    pub fn deinit(self: *ErrorHandler) void {
        if (self.error_log) |log_file| {
            log_file.close();
        }
    }
    
    pub fn setErrorHandler(self: *ErrorHandler, error_type: ErrorType, handler: ?ErrorCallback) void {
        self.handlers.put(error_type, handler);
    }
    
    pub fn setExceptionHandler(self: *ErrorHandler, handler: ?ExceptionCallback) void {
        self.exception_handler = handler;
    }
    
    pub fn setErrorReporting(self: *ErrorHandler, level: u32) void {
        self.error_reporting = level;
    }
    
    pub fn setDisplayErrors(self: *ErrorHandler, display: bool) void {
        self.display_errors = display;
    }
    
    pub fn setLogErrors(self: *ErrorHandler, log: bool) void {
        self.log_errors = log;
    }
    
    pub fn setErrorLog(self: *ErrorHandler, log_file: ?std.fs.File) void {
        if (self.error_log) |old_log| {
            old_log.close();
        }
        self.error_log = log_file;
    }
    
    pub fn handleError(self: *ErrorHandler, error_type: ErrorType, message: []const u8, file: []const u8, line: u32) !void {
        // Check if this error type should be reported
        const error_bit = @as(u32, 1) << @intFromEnum(error_type);
        if ((self.error_reporting & error_bit) == 0) {
            return; // Error reporting is disabled for this type
        }
        
        // Check for custom handler
        if (self.handlers.get(error_type)) |handler| {
            if (handler) |h| {
                h(error_type, message, file, line);
                return;
            }
        }
        
        // Default error handling
        const error_str = try std.fmt.allocPrint(self.allocator, "{s}: {s} in {s} on line {d}", .{
            error_type.toString(), message, file, line
        });
        defer self.allocator.free(error_str);
        
        // Display error if enabled
        if (self.display_errors) {
            std.debug.print("{s}\n", .{error_str});
        }
        
        // Log error if enabled
        if (self.log_errors) {
            try self.logError(error_str);
        }
        
        // For fatal errors, we should terminate execution
        if (error_type.isFatal()) {
            return error.FatalError;
        }
    }
    
    pub fn handleException(self: *ErrorHandler, exception: *PHPException) !void {
        // Check for custom exception handler
        if (self.exception_handler) |handler| {
            handler(exception);
            return;
        }
        
        // Default exception handling
        const exception_str = try exception.toString(self.allocator);
        defer exception_str.deinit(self.allocator);
        
        // Display exception
        if (self.display_errors) {
            std.debug.print("Uncaught {s}\n", .{exception_str.data});
            
            // Display stack trace
            const trace_str = try exception.getTraceAsString(self.allocator);
            defer trace_str.deinit(self.allocator);
            std.debug.print("Stack trace:\n{s}", .{trace_str.data});
        }
        
        // Log exception
        if (self.log_errors) {
            try self.logError(exception_str.data);
        }
        
        // Uncaught exceptions are fatal
        return error.UncaughtException;
    }
    
    pub fn throwException(self: *ErrorHandler, exception: *PHPException) !void {
        // This would normally unwind the stack looking for a catch block
        // For now, we'll just handle it as an uncaught exception
        return self.handleException(exception);
    }
    
    fn logError(self: *ErrorHandler, message: []const u8) !void {
        if (self.error_log) |log_file| {
            const timestamp = std.time.timestamp();
            const log_entry = try std.fmt.allocPrint(self.allocator, "[{d}] {s}\n", .{ timestamp, message });
            defer self.allocator.free(log_entry);
            
            _ = try log_file.writeAll(log_entry);
        }
    }
};

/// Try-catch-finally block execution context
pub const TryCatchContext = struct {
    allocator: std.mem.Allocator,
    caught_exception: ?*PHPException,
    finally_executed: bool,
    
    pub fn init(allocator: std.mem.Allocator) TryCatchContext {
        return TryCatchContext{
            .allocator = allocator,
            .caught_exception = null,
            .finally_executed = false,
        };
    }
    
    pub fn deinit(self: TryCatchContext) void {
        if (self.caught_exception) |exception| {
            exception.deinit(self.allocator);
        }
    }
    
    pub fn catchException(self: *TryCatchContext, exception: *PHPException, exception_type: PHPException.ExceptionType) bool {
        // Check if the exception matches the catch type
        if (self.matchesExceptionType(exception.exception_type, exception_type)) {
            self.caught_exception = exception;
            return true;
        }
        return false;
    }
    
    pub fn executeFinally(self: *TryCatchContext) void {
        self.finally_executed = true;
    }
    
    fn matchesExceptionType(self: *TryCatchContext, thrown_type: PHPException.ExceptionType, catch_type: PHPException.ExceptionType) bool {
        _ = self;
        
        // Exact match
        if (thrown_type == catch_type) return true;
        
        // Check inheritance hierarchy
        return switch (catch_type) {
            .exception => true, // Exception catches all
            .error_exception => switch (thrown_type) {
                .fatal_error, .type_error, .value_error, .argument_count_error => true,
                else => false,
            },
            else => false,
        };
    }
};

/// Error recovery mechanisms
pub const ErrorRecovery = struct {
    pub fn recoverFromParseError(allocator: std.mem.Allocator, source: []const u8, error_pos: usize) ![]const u8 {
        _ = allocator;
        
        // Simple recovery: skip to next statement boundary
        var pos = error_pos;
        while (pos < source.len) {
            if (source[pos] == ';' or source[pos] == '}' or source[pos] == '\n') {
                return source[pos + 1..];
            }
            pos += 1;
        }
        
        return source[source.len..];
    }
    
    pub fn recoverFromRuntimeError(error_type: ErrorType) !void {
        // Decide recovery strategy based on error type
        switch (error_type) {
            .fatal_error, .parse_error, .compile_error => return error.FatalError,
            .warning, .notice, .deprecated => {
                // Continue execution for non-fatal errors
                return;
            },
            else => return error.RecoverableError,
        }
    }
    
    pub fn suggestFix(exception_type: PHPException.ExceptionType, context: []const u8) ?[]const u8 {
        _ = context;
        
        return switch (exception_type) {
            .undefined_variable_error => "Check if the variable is declared and spelled correctly",
            .undefined_function_error => "Check if the function exists and is spelled correctly",
            .undefined_class_error => "Check if the class is defined and the namespace is correct",
            .undefined_method_error => "Check if the method exists in the class",
            .undefined_property_error => "Check if the property exists in the class",
            .type_error => "Check the types of arguments passed to the function",
            .argument_count_error => "Check the number of arguments passed to the function",
            .division_by_zero_error => "Check for division by zero in mathematical operations",
            else => null,
        };
    }
};

/// Utility functions for creating common exceptions
pub const ExceptionFactory = struct {
    pub fn createParseError(allocator: std.mem.Allocator, message: []const u8, file: []const u8, line: u32) !*PHPException {
        return PHPException.init(allocator, .parse_error, message, file, line);
    }
    
    pub fn createTypeError(allocator: std.mem.Allocator, message: []const u8, file: []const u8, line: u32) !*PHPException {
        return PHPException.init(allocator, .type_error, message, file, line);
    }
    
    pub fn createValueError(allocator: std.mem.Allocator, message: []const u8, file: []const u8, line: u32) !*PHPException {
        return PHPException.init(allocator, .value_error, message, file, line);
    }
    
    pub fn createArgumentCountError(allocator: std.mem.Allocator, expected: u32, actual: u32, function_name: []const u8, file: []const u8, line: u32) !*PHPException {
        const message = try std.fmt.allocPrint(allocator, "{s}() expects {d} arguments, {d} given", .{ function_name, expected, actual });
        defer allocator.free(message);
        return PHPException.init(allocator, .argument_count_error, message, file, line);
    }
    
    pub fn createUndefinedVariableError(allocator: std.mem.Allocator, variable_name: []const u8, file: []const u8, line: u32) !*PHPException {
        const message = try std.fmt.allocPrint(allocator, "Undefined variable: ${s}", .{variable_name});
        defer allocator.free(message);
        return PHPException.init(allocator, .undefined_variable_error, message, file, line);
    }
    
    pub fn createUndefinedFunctionError(allocator: std.mem.Allocator, function_name: []const u8, file: []const u8, line: u32) !*PHPException {
        const message = try std.fmt.allocPrint(allocator, "Call to undefined function {s}()", .{function_name});
        defer allocator.free(message);
        return PHPException.init(allocator, .undefined_function_error, message, file, line);
    }
    
    pub fn createUndefinedClassError(allocator: std.mem.Allocator, class_name: []const u8, file: []const u8, line: u32) !*PHPException {
        const message = try std.fmt.allocPrint(allocator, "Class '{s}' not found", .{class_name});
        defer allocator.free(message);
        return PHPException.init(allocator, .undefined_class_error, message, file, line);
    }
    
    pub fn createUndefinedMethodError(allocator: std.mem.Allocator, class_name: []const u8, method_name: []const u8, file: []const u8, line: u32) !*PHPException {
        const message = try std.fmt.allocPrint(allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name });
        defer allocator.free(message);
        return PHPException.init(allocator, .undefined_method_error, message, file, line);
    }
    
    pub fn createUndefinedPropertyError(allocator: std.mem.Allocator, class_name: []const u8, property_name: []const u8, file: []const u8, line: u32) !*PHPException {
        const message = try std.fmt.allocPrint(allocator, "Undefined property: {s}::${s}", .{ class_name, property_name });
        defer allocator.free(message);
        return PHPException.init(allocator, .undefined_property_error, message, file, line);
    }
    
    pub fn createReadonlyPropertyError(allocator: std.mem.Allocator, class_name: []const u8, property_name: []const u8, file: []const u8, line: u32) !*PHPException {
        const message = try std.fmt.allocPrint(allocator, "Cannot modify readonly property {s}::${s}", .{ class_name, property_name });
        defer allocator.free(message);
        return PHPException.init(allocator, .readonly_property_error, message, file, line);
    }
    
    pub fn createDivisionByZeroError(allocator: std.mem.Allocator, file: []const u8, line: u32) !*PHPException {
        return PHPException.init(allocator, .division_by_zero_error, "Division by zero", file, line);
    }
};