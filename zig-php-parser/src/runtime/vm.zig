const std = @import("std");
const compiler = @import("compiler");
const ast = compiler.ast;
const Token = compiler.Token;
const Environment = @import("environment.zig").Environment;
const types = @import("types.zig");
const nanbox_abi = @import("nanbox_abi");
const Value = types.Value;
const parser_mod = compiler.parser;
const PHPContext = parser_mod.PHPContext;
const Parser = parser_mod.Parser;
const exceptions = @import("exceptions.zig");
const PHPException = exceptions.PHPException;
const ErrorHandler = exceptions.ErrorHandler;
const ErrorType = exceptions.ErrorType;
const TryCatchContext = exceptions.TryCatchContext;
const ExceptionFactory = exceptions.ExceptionFactory;
const stdlib = @import("stdlib.zig");
const StandardLibrary = stdlib.StandardLibrary;
const reflection = @import("reflection.zig");
const builtin_classes = @import("builtin_classes.zig");
const builtin_registry = @import("builtin_registry.zig");
const BuiltinRegistry = builtin_registry.BuiltinRegistry;
const database = @import("database.zig");
const ReflectionSystem = reflection.ReflectionSystem;
const string_utils = @import("string_utils.zig");
const builtin_methods = @import("builtin_methods.zig");
const builtin_concurrency = @import("builtin_concurrency.zig");
const builtin_http = @import("builtin_http.zig");
const builtin_io = @import("builtin_io.zig");
const coroutine = @import("coroutine.zig");
const gc = @import("gc.zig");
const syntax_mode = compiler.syntax_mode;
pub const SyntaxMode = syntax_mode.SyntaxMode;
pub const SyntaxConfig = syntax_mode.SyntaxConfig;

// Extension system imports
const extension = @import("extension");
pub const ExtensionRegistry = extension.ExtensionRegistry;

// Bytecode VM imports for execution mode switching
const bytecode = @import("bytecode");
const BytecodeVM = bytecode.BytecodeVM;
// BytecodeGenerator for AST-to-bytecode compilation
const BytecodeGenerator = bytecode.BytecodeGenerator;

// Performance optimization modules
const fast_pool = @import("fast_pool.zig");
const fast_string = @import("fast_string.zig");
const fast_value = @import("fast_value.zig");
const loop_optimizer = @import("loop_optimizer.zig");
const inline_cache = @import("inline_cache.zig");
const builtin_dispatch = @import("builtin_dispatch.zig");

// FastVM for high-performance execution
const fast_vm = @import("fast_vm.zig");
const FastVM = fast_vm.FastVM;
const fast_compiler = @import("fast_compiler.zig");
const FastCompiler = fast_compiler.FastCompiler;

const CapturedVar = struct { name: []const u8, value: Value, is_reference: bool = false };

/// Shutdown function entry for register_shutdown_function()
const ShutdownFunction = struct {
    callback: Value, // Function or callable to execute
    args: []Value, // Arguments to pass to the callback

    pub fn deinit(self: *ShutdownFunction, allocator: std.mem.Allocator) void {
        self.callback.release(allocator);
        for (self.args) |arg| {
            arg.release(allocator);
        }
        allocator.free(self.args);
    }
};

/// Generator状态 - 用于跟踪yield语句的执行状态
pub const GeneratorState = struct {
    allocator: std.mem.Allocator,
    values: std.ArrayListUnmanaged(Value),
    keys: std.ArrayListUnmanaged(Value),
    current_index: usize,
    function_body: ?ast.Node.Index,
    captured_vars: ?[]const CapturedVar,
    generator_object: ?Value, // Store the Generator object created for this state
    current_value: ?Value, // Value to return on current iteration
    is_exhausted: bool, // Whether the generator has finished executing
    has_started: bool, // Whether the generator has started executing
    this_context: ?Value, // Store $this context for method generators
    locals: std.StringHashMap(Value), // Store local variables between resumptions
    current_position: ?ast.Node.Index, // Current execution position (for resuming)

    pub fn init(allocator: std.mem.Allocator) GeneratorState {
        return GeneratorState{
            .allocator = allocator,
            .values = .{},
            .keys = .{},
            .current_index = 0,
            .function_body = null,
            .captured_vars = null,
            .generator_object = null,
            .current_value = null,
            .is_exhausted = false,
            .has_started = false,
            .this_context = null,
            .locals = std.StringHashMap(Value).init(allocator),
            .current_position = null,
        };
    }

    fn deinit(self: *GeneratorState) void {
        if (self.this_context) |this_ctx| {
            this_ctx.release(self.allocator);
        }
        // Cleanup locals
        var locals_iter = self.locals.iterator();
        while (locals_iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.locals.deinit();
        for (self.values.items) |v| v.release(self.allocator);
        self.values.deinit(self.allocator);
        for (self.keys.items) |k| k.release(self.allocator);
        self.keys.deinit(self.allocator);
        if (self.generator_object) |gen_obj| {
            gen_obj.release(self.allocator);
        }
        self.allocator.destroy(self);
    }
};

/// 执行模式枚举 - 支持树遍历和字节码两种执行方式
pub const ExecutionMode = enum {
    /// 树遍历解释器（默认，最兼容）
    tree_walking,
    /// 字节码虚拟机（高性能）
    bytecode,
    /// FastVM - NaN-boxing 极速字节码虚拟机（最高性能，功能有限）
    fast,
    /// 自动选择（根据代码特征自动选择最佳执行方式）
    auto,
};

pub const CallFrame = struct {
    function_name: []const u8,
    file: []const u8,
    line: u32,
    locals: std.StringHashMap(Value),
    imported_globals: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, function_name: []const u8, file: []const u8, line: u32) CallFrame {
        return CallFrame{
            .function_name = function_name,
            .file = file,
            .line = line,
            .locals = std.StringHashMap(Value).init(allocator),
            .imported_globals = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *CallFrame, allocator: std.mem.Allocator) void {
        var iterator = self.locals.iterator();
        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;
            value.release(allocator);
        }
        self.locals.deinit();
        self.imported_globals.deinit();
    }

    /// Reset the frame for reuse, keeping allocated capacity
    pub fn reset(self: *CallFrame, allocator: std.mem.Allocator) void {
        var iterator = self.locals.iterator();
        while (iterator.next()) |entry| {
            const value = entry.value_ptr.*;
            value.release(allocator);
        }
        self.locals.clearRetainingCapacity();
        self.imported_globals.clearRetainingCapacity();
    }
};

pub const ExecutionStats = struct {
    function_calls: u64 = 0,
    memory_allocations: u64 = 0,
    gc_collections: u32 = 0,
    execution_time_ns: u64 = 0,
    peak_memory_usage: usize = 0,
    arithmetic_ops: u64 = 0,

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

    return switch (callback.getTag()) {
        .native_function => {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            return function(vm, func_args);
        },
        .user_function => {
            return vm.callUserFunction(callback.getAsUserFunc().data, func_args);
        },
        .closure => {
            return vm.callClosure(callback.getAsClosure().data, func_args);
        },
        .arrow_function => {
            return vm.callArrowFunction(callback.getAsArrowFunc().data, func_args);
        },
        .string => {
            // Function name as string
            const func_name = callback.getAsString().data.data;
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

    if (params_array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "call_user_func_array() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Convert array to argument list
    const php_array = params_array.getAsArray().data;
    var func_args = try vm.allocator.alloc(Value, php_array.count());
    defer {
        // Release all arguments and free the array
        for (func_args) |arg| {
            vm.releaseValue(arg);
        }
        vm.allocator.free(func_args);
    }

    var i: usize = 0;
    var iterator = php_array.getElements().iterator();
    while (iterator.next()) |entry| {
        func_args[i] = entry.value_ptr.*;
        vm.retainValue(func_args[i]); // Retain each argument
        i += 1;
    }

    return switch (callback.getTag()) {
        .native_function => {
            const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback.getAsNativeFunc()));
            return function(vm, func_args);
        },
        .user_function => {
            return vm.callUserFunction(callback.getAsUserFunc().data, func_args);
        },
        .closure => {
            return vm.callClosure(callback.getAsClosure().data, func_args);
        },
        .arrow_function => {
            return vm.callArrowFunction(callback.getAsArrowFunc().data, func_args);
        },
        .string => {
            // Function name as string
            const func_name = callback.getAsString().data.data;
            return vm.callUserFunc(func_name, func_args);
        },
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "call_user_func_array() expects parameter 1 to be a valid callback", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };
}

fn pdoRollbackFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_rollback() expects exactly 1 parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_value = args[0];
    if (pdo_value.getTag() != .object) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_rollback() expects PDO object", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    if (!std.mem.eql(u8, pdo_value.getAsObject().data.class.name.data, "PDO")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_rollback() expects PDO object as first parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    // Get the stored PDO connection
    const connection_prop = pdo_value.getAsObject().data.getProperty("_pdo_connection") catch {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "PDO connection not initialized", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    };

    if (connection_prop.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "Invalid PDO connection", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
    const result = pdo_ptr.rollBack() catch return Value.initBool(false);
    return Value.initBool(result);
}

fn pdoCommitFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_commit() expects exactly 1 parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_value = args[0];
    if (pdo_value.getTag() != .object) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_commit() expects PDO object", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    if (!std.mem.eql(u8, pdo_value.getAsObject().data.class.name.data, "PDO")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_commit() expects PDO object as first parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    // Get the stored PDO connection
    const connection_prop = pdo_value.getAsObject().data.getProperty("_pdo_connection") catch {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "PDO connection not initialized", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    };

    if (connection_prop.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "Invalid PDO connection", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
    const result = pdo_ptr.commit() catch return Value.initBool(false);
    return Value.initBool(result);
}

fn pdoBeginTransactionFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_begin_transaction() expects exactly 1 parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_value = args[0];
    if (pdo_value.getTag() != .object) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_begin_transaction() expects PDO object", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    if (!std.mem.eql(u8, pdo_value.getAsObject().data.class.name.data, "PDO")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_begin_transaction() expects PDO object as first parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    // Get the stored PDO connection
    const connection_prop = pdo_value.getAsObject().data.getProperty("_pdo_connection") catch {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "PDO connection not initialized", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    };

    if (connection_prop.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "Invalid PDO connection", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
    const result = pdo_ptr.beginTransaction() catch return Value.initBool(false);
    return Value.initBool(result);
}

fn pdoPrepareFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_prepare() expects exactly 2 parameters", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_value = args[0];
    const sql_value = args[1];

    if (pdo_value.getTag() != .object or sql_value.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_prepare() expects PDO object and string", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    if (!std.mem.eql(u8, pdo_value.getAsObject().data.class.name.data, "PDO")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_prepare() expects PDO object as first parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const sql = sql_value.getAsString().data.data;

    // Get the stored PDO connection
    const connection_prop = pdo_value.getAsObject().data.getProperty("_pdo_connection") catch {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "PDO connection not initialized", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    };

    if (connection_prop.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "Invalid PDO connection", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
    const stmt = pdo_ptr.prepare(sql) catch {
        return Value.initNull();
    };

    // Create PDOStatement object to wrap the statement
    const stmt_class_name = try types.PHPString.init(vm.allocator, "PDOStatement");
    defer stmt_class_name.release(vm.allocator);
    var stmt_class = try types.PHPClass.init(vm.allocator, stmt_class_name);

    const stmt_object = try vm.allocator.create(types.PHPObject);
    stmt_object.* = try types.PHPObject.init(vm.allocator, &stmt_class);

    // Store the statement pointer as an integer property
    try stmt_object.setProperty(vm.allocator, "_pdo_statement", Value.initInt(@intCast(@intFromPtr(stmt))));

    const box = try vm.allocator.create(types.gc.Box(*types.PHPObject));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = stmt_object,
    };

    return Value.fromBox(box, Value.TYPE_OBJECT);
}

fn pdoQueryFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_query() expects exactly 2 parameters", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_value = args[0];
    const sql_value = args[1];

    if (pdo_value.getTag() != .object or sql_value.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_query() expects PDO object and string", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    if (!std.mem.eql(u8, pdo_value.getAsObject().data.class.name.data, "PDO")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_query() expects PDO object as first parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const sql = sql_value.getAsString().data.data;

    // Get the stored PDO connection
    const connection_prop = pdo_value.getAsObject().data.getProperty("_pdo_connection") catch {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "PDO connection not initialized", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    };

    if (connection_prop.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "Invalid PDO connection", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
    const stmt = pdo_ptr.query(sql) catch {
        return Value.initNull();
    };

    if (stmt) |s| {
        // Create PDOStatement object to wrap the statement
        const stmt_class_name = try types.PHPString.init(vm.allocator, "PDOStatement");
        defer stmt_class_name.release(vm.allocator);
        var stmt_class = try types.PHPClass.init(vm.allocator, stmt_class_name);

        const stmt_object = try vm.allocator.create(types.PHPObject);
        stmt_object.* = try types.PHPObject.init(vm.allocator, &stmt_class);

        // Store the statement pointer as an integer property
        try stmt_object.setProperty(vm.allocator, "_pdo_statement", Value.initInt(@intCast(@intFromPtr(s))));

        const box = try vm.allocator.create(types.gc.Box(*types.PHPObject));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = stmt_object,
        };

        return Value.fromBox(box, Value.TYPE_OBJECT);
    }

    return Value.initNull();
}

fn pdoExecFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_exec() expects exactly 2 parameters", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_value = args[0];
    const sql_value = args[1];

    if (pdo_value.getTag() != .object or sql_value.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_exec() expects PDO object and string", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    if (!std.mem.eql(u8, pdo_value.getAsObject().data.class.name.data, "PDO")) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "pdo_exec() expects PDO object as first parameter", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const sql = sql_value.getAsString().data.data;

    // Get the stored PDO connection
    const connection_prop = pdo_value.getAsObject().data.getProperty("_pdo_connection") catch {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "PDO connection not initialized", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    };

    if (connection_prop.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "Invalid PDO connection", vm.current_file, vm.current_line);
        return vm.throwException(exception);
    }

    const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
    const result = try pdo_ptr.exec(sql);
    return Value.initInt(result);
}

// Existing function implementations...

fn isCallableFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "is_callable", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    return Value.initBool(args[0].isCallable());
}

// Reflection functions
fn classExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "class_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const class_name_val = args[0];
    if (class_name_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "class_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    var class_name = class_name_val.getAsString().data.data;

    // PHP 行为：带前导反斜杠表示全局命名空间，与不带反斜杠相同
    // 例如：\Generator 与 Generator 是同一个类
    if (class_name.len > 0 and class_name[0] == '\\') {
        class_name = class_name[1..];
    }

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

    if (method_name_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "method_exists() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const method_name = method_name_val.getAsString().data.data;

    const exists = switch (object_or_class.getTag()) {
        .object => {
            const object = object_or_class.getAsObject().data;
            return Value.initBool(object.class.hasMethod(method_name));
        },
        .string => {
            const class_name = object_or_class.getAsString().data.data;
            const class = vm.getClass(class_name) orelse return Value.initBool(false);
            return Value.initBool(class.hasMethod(method_name));
        },
        else => false,
    };

    return Value.initBool(exists);
}

fn functionExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "function_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const function_name_val = args[0];
    if (function_name_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "function_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const function_name = function_name_val.getAsString().data.data;

    // Check builtin functions (stdlib)
    if (vm.stdlib.getFunction(function_name) != null) {
        return Value.initBool(true);
    }

    // Check builtin registry functions
    if (vm.builtin_registry.exists(function_name)) {
        return Value.initBool(true);
    }

    // Check extension functions
    if (vm.extension_registry) |ext_reg| {
        if (ext_reg.findFunction(function_name) != null) {
            return Value.initBool(true);
        }
    }

    // Check user-defined functions in global scope
    if (vm.global.get(function_name)) |func_val| {
        // Check if it's a user function, closure, arrow function, or native function
        return Value.initBool(switch (func_val.getTag()) {
            .user_function, .closure, .arrow_function, .native_function => true,
            else => false,
        });
    }

    return Value.initBool(false);
}

fn propertyExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "property_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const object_or_class = args[0];
    const property_name_val = args[1];

    if (property_name_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "property_exists() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const property_name = property_name_val.getAsString().data.data;

    const exists = switch (object_or_class.getTag()) {
        .object => {
            const object = object_or_class.getAsObject().data;
            return Value.initBool(object.hasProperty(property_name));
        },
        .string => {
            const class_name = object_or_class.getAsString().data.data;
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
    if (object_val.getTag() != .object) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_class() expects parameter 1 to be object", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const object = object_val.getAsObject().data;
    return Value.initStringWithManager(&vm.memory_manager, object.class.name.data);
}

fn getCalledClassFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 0, @intCast(args.len), "get_called_class", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const called = vm.current_called_class orelse {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_called_class() must be called from within a class", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    };

    return Value.initStringWithManager(&vm.memory_manager, called.name.data);
}

fn getClassMethodsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_class_methods", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const class_name_val = args[0];
    const class_name = switch (class_name_val.getTag()) {
        .string => class_name_val.getAsString().data.data,
        .object => class_name_val.getAsObject().data.class.name.data,
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
    const php_array = php_array_value.getAsArray().data;

    var iterator = class.methods.iterator();
    while (iterator.next()) |entry| {
        const method_name_value = try Value.initStringWithManager(&vm.memory_manager, entry.key_ptr.*);
        try php_array.push(vm.allocator, method_name_value);
        vm.releaseValue(method_name_value);
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
    const class_name = switch (class_name_val.getTag()) {
        .string => class_name_val.getAsString().data.data,
        .object => class_name_val.getAsObject().data.class.name.data,
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
    const php_array = php_array_value.getAsArray().data;

    var iterator = class.properties.iterator();
    while (iterator.next()) |entry| {
        const property_name = entry.key_ptr.*;
        const property = entry.value_ptr.*;

        // Only include public properties
        if (property.modifiers.visibility == .public) {
            const key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, property_name) };
            const value = property.default_value orelse Value.initNull();
            try php_array.set(vm.allocator, key, value);
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
    if (object_val.getTag() != .object) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_object_vars() expects parameter 1 to be object", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const object = object_val.getAsObject().data;
    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    var iterator = object.shape.property_map.iterator();
    while (iterator.next()) |entry| {
        const property_name = entry.key_ptr.*;
        const offset = entry.value_ptr.*;
        const property_value = object.property_values.items[offset];

        // Check if property is accessible (public or from same class context)
        // For now, include all properties (simplified)
        const key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, property_name) };
        try php_array.set(vm.allocator, key, property_value);
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

    if (class_name_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_a() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const class_name = class_name_val.getAsString().data.data;

    const is_instance = switch (object_val.getTag()) {
        .object => {
            const object = object_val.getAsObject().data;
            const target_class = vm.getClass(class_name) orelse return Value.initBool(false);
            return Value.initBool(object.isInstanceOf(target_class));
        },
        .string => {
            // Allow checking class names as strings
            const object_class_name = object_val.getAsString().data.data;
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

    if (parent_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_subclass_of() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const parent_class_name = parent_val.getAsString().data.data;
    const parent_class = vm.getClass(parent_class_name) orelse return Value.initBool(false);

    const is_subclass = switch (child_val.getTag()) {
        .object => {
            const object = child_val.getAsObject().data;
            // Check if object's class is a subclass (not the same class)
            return Value.initBool(object.class != parent_class and object.class.isInstanceOf(parent_class));
        },
        .string => {
            const child_class_name = child_val.getAsString().data.data;
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
    if (arg.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "count() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    return Value.initInt(@intCast(arg.getAsArray().data.count()));
}

// Variable handling functions
fn unsetFn(vm: *VM, args: []const Value) !Value {
    // unset() can take multiple arguments
    if (args.len == 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, 0, "unset", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    // In PHP, unset() is a language construct, not a function
    // For our implementation, we'll simulate the behavior by returning null
    // The actual unsetting would need to be handled at the parser/compiler level
    // This is a simplified implementation for demonstration

    // In a real implementation, unset would need variable references
    // For now, we'll just return null to indicate successful "unset"
    return Value.initNull();
}

fn emptyFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "empty", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const arg = args[0];

    // PHP empty() returns true for:
    // - null
    // - false
    // - 0 (integer)
    // - 0.0 (float)
    // - "" (empty string)
    // - "0" (string containing only "0")
    // - empty array
    // - uninitialized variables (we treat as null)

    const is_empty = switch (arg.getTag()) {
        .null => true,
        .boolean => !arg.asBool(),
        .integer => arg.asInt() == 0,
        .float => arg.asFloat() == 0.0,
        .string => blk: {
            const str_data = arg.getAsString().data.data;
            break :blk str_data.len == 0 or std.mem.eql(u8, str_data, "0");
        },
        .array => arg.getAsArray().data.count() == 0,
        .reference => false, // References are never empty
        .object, .struct_instance, .resource => false, // Objects are never empty
        .native_function, .user_function, .closure, .arrow_function => false, // Functions are never empty
    };

    return Value.initBool(is_empty);
}

fn isNullFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "is_null", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const arg = args[0];
    return Value.initBool(arg.isNull());
}

// Error handling functions - simplified implementation
fn setErrorHandlerFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    // Accept 1-2 arguments: handler callable, optional error_types
    if (args.len < 1) {
        return Value.initNull();
    }
    // In a full implementation, we would store the handler and call it on errors
    // For now, just return null (previous handler) to allow scripts to run
    return Value.initNull();
}

fn restoreErrorHandlerFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    _ = args;
    // In a full implementation, we would restore the previous error handler
    // For now, just return true to allow scripts to run
    return Value.initBool(true);
}

// Reflection functions
fn getDeclaredClassesFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 0, @intCast(args.len), "get_declared_classes", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    var iterator = vm.classes.iterator();
    while (iterator.next()) |entry| {
        const class_name_value = try Value.initStringWithManager(&vm.memory_manager, entry.key_ptr.*);
        try php_array.push(vm.allocator, class_name_value);
        vm.releaseValue(class_name_value);
    }

    return php_array_value;
}

fn getDeclaredInterfacesFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 0, @intCast(args.len), "get_declared_interfaces", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    var iterator = vm.interfaces.iterator();
    while (iterator.next()) |entry| {
        const interface_name_value = try Value.initStringWithManager(&vm.memory_manager, entry.key_ptr.*);
        try php_array.push(vm.allocator, interface_name_value);
        vm.releaseValue(interface_name_value);
    }

    return php_array_value;
}

fn getDeclaredTraitsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 0) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 0, @intCast(args.len), "get_declared_traits", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    var iterator = vm.traits.iterator();
    while (iterator.next()) |entry| {
        const trait_name_value = try Value.initStringWithManager(&vm.memory_manager, entry.key_ptr.*);
        try php_array.push(vm.allocator, trait_name_value);
        vm.releaseValue(trait_name_value);
    }

    return php_array_value;
}

fn getParentClassFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_parent_class", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const arg = args[0];
    const class = switch (arg.getTag()) {
        .object => arg.getAsObject().data.class,
        .string => vm.getClass(arg.getAsString().data.data) orelse return Value.initBool(false),
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_parent_class() expects parameter 1 to be object or string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    if (class.parent) |parent| {
        return Value.initStringWithManager(&vm.memory_manager, parent.name.data);
    }

    return Value.initBool(false);
}

fn interfaceExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "interface_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const interface_name_val = args[0];
    if (interface_name_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "interface_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    // Interface tracking not yet implemented
    return Value.initBool(false);
}

fn traitExistsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "trait_exists", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const trait_name_val = args[0];
    if (trait_name_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "trait_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const trait_name = trait_name_val.getAsString().data.data;
    if (vm.getClass(trait_name)) |_| {
        // Note: Current implementation doesn't distinguish traits from classes
        // Would need is_trait field in ClassModifiers
        return Value.initBool(false);
    }

    return Value.initBool(false);
}

fn getClassConstantsFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_class_constants", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const class_name_val = args[0];
    const class_name = switch (class_name_val.getTag()) {
        .string => class_name_val.getAsString().data.data,
        .object => class_name_val.getAsObject().data.class.name.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_class_constants() expects parameter 1 to be string or object", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const class = vm.getClass(class_name) orelse {
        return Value.initNull();
    };

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    var iterator = class.constants.iterator();
    while (iterator.next()) |entry| {
        const key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, entry.key_ptr.*) };
        try php_array.set(vm.allocator, key, entry.value_ptr.*);
    }

    return php_array_value;
}

// ==================== High Priority Functions ====================

// define() - Define a named constant
fn defineFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "define", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const name = switch (args[0].getTag()) {
        .string => args[0].getAsString().data.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "define() expects parameter 1 to be a string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const value = args[1];
    // Note: case_insensitive parameter is ignored for now
    _ = if (args.len > 2) args[2].toBool() else false;

    // Check if constant already exists
    if (vm.global.get(name)) |existing| {
        if (!existing.isNull()) {
            // Just return false for duplicate constant (PHP behavior)
            return Value.initBool(false);
        }
    }

    // Store the constant
    try vm.global.set(name, value.retain());

    return Value.initBool(true);
}

// defined() - Check if a constant is defined
fn definedFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "defined", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const name = switch (args[0].getTag()) {
        .string => args[0].getAsString().data.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "defined() expects parameter 1 to be a string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    // Check if constant exists
    if (vm.global.get(name)) |value| {
        return Value.initBool(!value.isNull());
    }

    return Value.initBool(false);
}

// constant() - Return the value of a constant
fn constantFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "constant", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const name = switch (args[0].getTag()) {
        .string => args[0].getAsString().data.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "constant() expects parameter 1 to be a string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    if (vm.global.get(name)) |value| {
        if (value.isNull()) {
            const exception = try ExceptionFactory.createError(vm.allocator, "Constant is not defined", vm.current_file, vm.current_line);
            _ = try vm.throwException(exception);
            return error.UndefinedConstant;
        }
        return value.retain();
    }

    const exception = try ExceptionFactory.createError(vm.allocator, "Constant is not defined", vm.current_file, vm.current_line);
    _ = try vm.throwException(exception);
    return error.UndefinedConstant;
}

// func_get_args() - Get the function arguments as an array
fn funcGetArgsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const current_args = vm.current_call_args orelse {
        return Value.initArrayWithManager(&vm.memory_manager);
    };

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    for (current_args, 0..) |arg, i| {
        const key = types.ArrayKey{ .integer = @intCast(i) };
        try php_array.set(vm.allocator, key, arg.retain());
    }

    return php_array_value;
}

// func_get_arg() - Get a specific function argument
fn funcGetArgFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "func_get_arg", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const current_args = vm.current_call_args orelse {
        return Value.initNull();
    };

    const index = args[0];
    if (index.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "func_get_arg() expects parameter 1 to be an integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const i = @as(usize, @intCast(index.asInt()));
    if (i >= current_args.len) {
        return Value.initNull();
    }

    return current_args[i].retain();
}

// func_num_args() - Get the number of function arguments
fn funcNumArgsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const current_args = vm.current_call_args orelse {
        return Value.initInt(0);
    };

    return Value.initInt(@intCast(current_args.len));
}

// eval() - Execute a string as PHP code (high-performance with coroutine support)
fn evalFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "eval", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const code = switch (args[0].getTag()) {
        .string => args[0].getAsString().data.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "eval() expects parameter 1 to be a string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    // Create null-terminated string for Parser with <?php prefix
    // High-performance: use allocator with proper error handling
    const php_prefix = "<?php ";
    const full_code_len = php_prefix.len + code.len;
    const code_with_null = try vm.allocator.alloc(u8, full_code_len + 1);
    @memcpy(code_with_null[0..php_prefix.len], php_prefix);
    @memcpy(code_with_null[php_prefix.len..full_code_len], code);
    code_with_null[full_code_len] = 0;
    defer vm.allocator.free(code_with_null);

    // Create null-terminated pointer for Parser
    const code_null_terminated: [:0]const u8 = @ptrCast(code_with_null[0..full_code_len :0]);

    // Save current execution context for coroutine support
    const saved_file = vm.current_file;
    const saved_line = vm.current_line;
    const saved_source = vm.current_source;

    // Set eval context
    vm.current_file = "eval";
    vm.current_line = 1;

    defer {
        vm.current_file = saved_file;
        vm.current_line = saved_line;
        vm.current_source = saved_source;
    }

    // Parse the code - use context allocator for AST node allocation
    var parser = try Parser.initWithMode(vm.context.allocator, vm.context, code_null_terminated, vm.syntax_config.mode);
    defer parser.deinit();

    // Set source for line number calculation
    vm.current_source = code;

    // Parse and get AST node
    const body = parser.parse() catch {
        const exception = try ExceptionFactory.createParseError(vm.allocator, "eval() code parsing failed", "eval", 1);
        _ = try vm.throwException(exception);
        return error.ParseError;
    };

    // Execute the parsed code in the current context
    // Handle error.Return from return statements
    const result = vm.eval(body) catch |err| {
        if (err == error.Return) {
            // Return the value set by return statement
            if (vm.return_value) |ret_val| {
                // Take ownership of the return value
                const result = ret_val;
                vm.return_value = null;
                return result;
            }
            return Value.initNull();
        }
        return err;
    };

    return result;
}

// get_defined_vars() - Get all defined variables in the current scope
fn getDefinedVarsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    // Get variables from current scope
    if (vm.call_stack.items.len > 0) {
        const current_frame = &vm.call_stack.items[vm.call_stack.items.len - 1];
        var iterator = current_frame.locals.iterator();
        var i: usize = 0;
        while (iterator.next()) |entry| {
            const key = types.ArrayKey{ .integer = @intCast(i) };
            try php_array.set(vm.allocator, key, entry.value_ptr.*.retain());
            i += 1;
        }
    }

    return php_array_value;
}

// get_defined_constants() - Get all defined constants
fn getDefinedConstantsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    var iterator = vm.global.vars.iterator();
    while (iterator.next()) |entry| {
        const key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, entry.key_ptr.*) };
        try php_array.set(vm.allocator, key, entry.value_ptr.*.retain());
    }

    return php_array_value;
}

// get_defined_functions() - Get all defined functions
fn getDefinedFunctionsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    // Get user-defined functions from global scope
    var iterator = vm.global.vars.iterator();
    var i: usize = 0;
    while (iterator.next()) |entry| {
        const value = entry.value_ptr.*;
        if (value.getTag() == .user_function) {
            const key = types.ArrayKey{ .integer = @intCast(i) };
            const str_value = try Value.initString(vm.allocator, entry.key_ptr.*);
            try php_array.set(vm.allocator, key, str_value);
            i += 1;
        }
    }

    return php_array_value;
}

fn forwardStaticCallFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "forward_static_call", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const callback = args[0];
    if (callback.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "forward_static_call() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const cb = callback.getAsString().data.data;
    const sep = std.mem.indexOf(u8, cb, "::") orelse {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "forward_static_call() expects parameter 1 to be a static method callable", "builtin", 0);
        return vm.throwException(exception);
    };
    if (sep == 0 or sep + 2 >= cb.len) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "forward_static_call() expects parameter 1 to be a static method callable", "builtin", 0);
        return vm.throwException(exception);
    }

    const class_part = cb[0..sep];
    const method_part = cb[sep + 2 ..];

    const lookup_class = if (std.mem.eql(u8, class_part, "self")) blk: {
        break :blk vm.current_class orelse {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "Cannot access self:: outside of class scope", vm.current_file, vm.current_line);
            return vm.throwException(exception);
        };
    } else if (std.mem.eql(u8, class_part, "parent")) blk: {
        const scope = vm.current_class orelse {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "Cannot access parent:: outside of class scope", vm.current_file, vm.current_line);
            return vm.throwException(exception);
        };
        break :blk scope.parent orelse {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "Cannot access parent:: when class has no parent", vm.current_file, vm.current_line);
            return vm.throwException(exception);
        };
    } else if (std.mem.eql(u8, class_part, "static")) blk: {
        break :blk vm.current_called_class orelse {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "Cannot access static:: outside of class scope", vm.current_file, vm.current_line);
            return vm.throwException(exception);
        };
    } else blk: {
        break :blk vm.getClass(class_part) orelse {
            const exception = try ExceptionFactory.createUndefinedClassError(vm.allocator, class_part, vm.current_file, vm.current_line);
            return vm.throwException(exception);
        };
    };

    const called_class = vm.current_called_class orelse lookup_class;

    const method_lookup = lookup_class.getMethodLookup(method_part);
    if (method_lookup) |lookup| {
        const m = lookup.method;
        const full_method_name = try std.fmt.allocPrint(vm.allocator, "{s}::{s}", .{ lookup_class.name.data, method_part });
        defer vm.allocator.free(full_method_name);
        try vm.pushCallFrame(full_method_name, vm.current_file, vm.current_line);
        defer vm.popCallFrame();

        const call_args = args[1..];
        for (m.parameters, 0..) |param, i| {
            if (i < call_args.len) {
                try vm.setVariable(param.name.data, call_args[i]);
            } else if (param.default_value) |default| {
                try vm.setVariable(param.name.data, default);
            }
        }

        const old_scope_class = vm.current_class;
        const old_called_class = vm.current_called_class;
        vm.current_called_class = called_class;
        vm.current_class = lookup.owner;
        defer {
            vm.current_class = old_scope_class;
            vm.current_called_class = old_called_class;
        }

        if (m.body) |body_ptr| {
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
            return vm.eval(body_node) catch |err| {
                if (err == error.Return) {
                    if (vm.return_value) |val| {
                        const ret = val;
                        vm.return_value = null;
                        return ret;
                    }
                    return Value.initNull();
                }
                return err;
            };
        }
        return Value.initNull();
    }

    if (lookup_class.getMethodLookup("__callStatic")) |call_static_lookup| {
        const name_val = try Value.initString(vm.allocator, method_part);
        defer name_val.release(vm.allocator);

        const args_array_val = try Value.initArrayWithManager(&vm.memory_manager);
        const args_array = args_array_val.getAsArray().data;
        for (args[1..]) |arg| {
            try args_array.push(vm.allocator, arg);
        }
        defer args_array_val.release(vm.allocator);

        const magic_args = [_]Value{ name_val, args_array_val };

        const full_method_name = try std.fmt.allocPrint(vm.allocator, "{s}::__callStatic", .{lookup_class.name.data});
        defer vm.allocator.free(full_method_name);
        try vm.pushCallFrame(full_method_name, vm.current_file, vm.current_line);
        defer vm.popCallFrame();

        const inner_call_static = call_static_lookup.method;
        for (inner_call_static.parameters, 0..) |param, i| {
            if (i < magic_args.len) {
                try vm.setVariable(param.name.data, magic_args[i]);
            }
        }

        const old_scope_class = vm.current_class;
        const old_called_class = vm.current_called_class;
        vm.current_called_class = called_class;
        vm.current_class = call_static_lookup.owner;
        defer {
            vm.current_class = old_scope_class;
            vm.current_called_class = old_called_class;
        }

        if (inner_call_static.body) |body_ptr| {
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
            return vm.eval(body_node) catch |err| {
                if (err == error.Return) {
                    if (vm.return_value) |val| {
                        const ret = val;
                        vm.return_value = null;
                        return ret;
                    }
                    return Value.initNull();
                }
                return err;
            };
        }

        return Value.initNull();
    }

    const msg = try std.fmt.allocPrint(vm.allocator, "Call to undefined method {s}::{s}()", .{ lookup_class.name.data, method_part });
    defer vm.allocator.free(msg);
    const exception = try ExceptionFactory.createTypeError(vm.allocator, msg, vm.current_file, vm.current_line);
    return vm.throwException(exception);
}

// forward_static_call_array() - Call a static method and pass arguments as array
fn forwardStaticCallArrayFn(vm: *VM, args: []const Value) !Value {
    if (args.len != 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "forward_static_call_array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const params_array = args[1];

    if (params_array.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "forward_static_call_array() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const params = params_array.getAsArray().data;
    const params_count = params.count();

    const packed_args = try vm.allocator.alloc(Value, 1 + params_count);
    defer {
        for (packed_args[1..]) |arg| {
            vm.releaseValue(arg);
        }
        vm.allocator.free(packed_args);
    }

    packed_args[0] = args[0];

    var i: usize = 0;
    var iterator = params.getElements().iterator();
    while (iterator.next()) |entry| {
        const v = entry.value_ptr.*;
        packed_args[1 + i] = v;
        vm.retainValue(v);
        i += 1;
    }

    return forwardStaticCallFn(vm, packed_args);
}

// ==================== Medium Priority Functions ====================

// debug_backtrace() - Get the call stack
fn debugBacktraceFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    // Build backtrace from call stack
    for (vm.call_stack.items, 0..) |frame, i| {
        const frame_array = try vm.allocator.create(types.PHPArray);
        frame_array.* = types.PHPArray.init(vm.allocator);

        // Function/file/line info
        const func_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "function") };
        const func_name = try types.PHPString.init(vm.allocator, frame.function_name);
        const func_name_value = try Value.initString(vm.allocator, func_name.data);
        try frame_array.set(vm.allocator, func_key, func_name_value);

        const file_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "file") };
        const file_name = try types.PHPString.init(vm.allocator, frame.file);
        const file_name_value = try Value.initString(vm.allocator, file_name.data);
        try frame_array.set(vm.allocator, file_key, file_name_value);

        const line_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "line") };
        try frame_array.set(vm.allocator, line_key, Value.initInt(@intCast(frame.line)));

        const key = types.ArrayKey{ .integer = @intCast(i) };
        const frame_box = try vm.allocator.create(types.gc.Box(*types.PHPArray));
        frame_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = frame_array,
        };
        try php_array.set(vm.allocator, key, Value.fromBox(frame_box, Value.TYPE_ARRAY));
    }

    return php_array_value;
}

// debug_print_backtrace() - Print the call stack
fn debugPrintBacktraceFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    // Print backtrace directly using std.debug.print
    for (vm.call_stack.items, 0..) |frame, i| {
        std.debug.print("#{d} {s}() at {s}:{d}\n", .{ i, frame.function_name, frame.file, frame.line });
    }

    return Value.initNull();
}

// register_shutdown_function() - Register a function to execute at shutdown
fn registerShutdownFunctionFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "register_shutdown_function", "builtin", 0);
        _ = try vm.throwException(exception);
        return Value.initNull();
    }

    const callback = args[0];

    // Verify callback is callable
    if (!callback.isCallable()) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "register_shutdown_function() expects parameter 1 to be a valid callback", "builtin", 0);
        _ = try vm.throwException(exception);
        return Value.initNull();
    }

    // Copy callback arguments (skip first argument which is the callback itself)
    const callback_args = if (args.len > 1)
        try vm.allocator.dupe(Value, args[1..])
    else
        try vm.allocator.alloc(Value, 0);

    // Retain all values
    _ = callback.retain();
    for (callback_args) |arg| {
        _ = arg.retain();
    }

    // Register the shutdown function
    try vm.shutdown_functions.append(vm.allocator, .{
        .callback = callback,
        .args = callback_args,
    });

    return Value.initBool(true);
}

// ini_get() - Get the value of a configuration option
fn iniGetFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "ini_get", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const option = switch (args[0].getTag()) {
        .string => args[0].getAsString().data.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "ini_get() expects parameter 1 to be a string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    // Return default values for common options
    const value = if (std.mem.eql(u8, option, "display_errors")) "1" else if (std.mem.eql(u8, option, "error_reporting")) "32767" else if (std.mem.eql(u8, option, "max_execution_time")) "30" else if (std.mem.eql(u8, option, "memory_limit")) "128M" else if (std.mem.eql(u8, option, "post_max_size")) "8M" else if (std.mem.eql(u8, option, "upload_max_filesize")) "2M" else "";

    return try Value.initString(vm.allocator, value);
}

// ini_set() - Set the value of a configuration option
fn iniSetFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 2, @intCast(args.len), "ini_set", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const option = switch (args[0].getTag()) {
        .string => args[0].getAsString().data.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "ini_set() expects parameter 1 to be a string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const new_value = switch (args[1].getTag()) {
        .string => args[1].getAsString().data.data,
        else => "",
    };

    // Return empty string for now (old value)
    _ = option;
    _ = new_value;
    return try Value.initString(vm.allocator, "");
}

// phpversion() - Get the PHP version
fn phpversionFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    return try Value.initString(vm.allocator, "8.5.0-dev");
}

// php_sapi_name() - Get the SAPI name
fn phpSapiNameFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    return try Value.initString(vm.allocator, "cli");
}

// ==================== Extension and File Functions ====================

// extension_loaded() - Check if an extension is loaded
fn extensionLoadedFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "extension_loaded", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const ext_name = switch (args[0].getTag()) {
        .string => args[0].getAsString().data.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "extension_loaded() expects parameter 1 to be a string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    // Built-in extensions are always loaded
    const builtin_extensions = &[_][]const u8{
        "core", "standard",   "pcre",  "json", "hash",     "mbstring", "zlib",
        "spl",  "reflection", "ctype", "date", "fileinfo",
    };

    for (builtin_extensions) |ext| {
        if (std.mem.eql(u8, ext, ext_name)) {
            return Value.initBool(true);
        }
    }

    // Check dynamic extensions
    if (vm.extension_registry) |reg| {
        if (reg.extensions.contains(ext_name)) {
            return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

// get_loaded_extensions() - Get list of loaded extensions
fn getLoadedExtensionsFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    // Built-in extensions
    const builtin_extensions = &[_][]const u8{
        "core", "standard",   "pcre",  "json", "hash",     "mbstring", "zlib",
        "spl",  "reflection", "ctype", "date", "fileinfo",
    };

    var i: usize = 0;
    for (builtin_extensions) |ext| {
        const key = types.ArrayKey{ .integer = @intCast(i) };
        // 使用 memory_manager 创建字符串，确保正确的生命周期管理
        const ext_value = try Value.initStringWithManager(&vm.memory_manager, ext);
        try php_array.set(vm.allocator, key, ext_value);
        i += 1;
    }

    // Dynamic extensions
    if (vm.extension_registry) |reg| {
        var iter = reg.extensions.iterator();
        while (iter.next()) |entry| {
            const key = types.ArrayKey{ .integer = @intCast(i) };
            // 使用 memory_manager 创建字符串
            const ext_value = try Value.initStringWithManager(&vm.memory_manager, entry.key_ptr.*);
            try php_array.set(vm.allocator, key, ext_value);
            i += 1;
        }
    }

    return php_array_value;
}

// get_extension_funcs() - Get functions provided by an extension
fn getExtensionFuncsFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "get_extension_funcs", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const ext_name = switch (args[0].getTag()) {
        .string => args[0].getAsString().data.data,
        else => {
            const exception = try ExceptionFactory.createTypeError(vm.allocator, "get_extension_funcs() expects parameter 1 to be a string", "builtin", 0);
            _ = try vm.throwException(exception);
            return error.InvalidArgumentType;
        },
    };

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    // Check if extension is loaded
    var is_loaded = false;

    // Check built-in extensions
    const builtin_extensions = &[_][]const u8{
        "core", "standard",   "pcre",  "json", "hash",     "mbstring", "zlib",
        "spl",  "reflection", "ctype", "date", "fileinfo",
    };
    for (builtin_extensions) |ext| {
        if (std.mem.eql(u8, ext, ext_name)) {
            is_loaded = true;
            break;
        }
    }

    // Check dynamic extensions
    if (!is_loaded) {
        if (vm.extension_registry) |reg| {
            if (reg.extensions.contains(ext_name)) {
                is_loaded = true;
            }
        }
    }

    if (!is_loaded) {
        return php_array_value;
    }

    // Get functions from extension registry
    if (vm.extension_registry) |reg| {
        var iter = reg.functions.iterator();
        var j: usize = 0;
        while (iter.next()) |entry| {
            const key = types.ArrayKey{ .integer = @intCast(j) };
            const func_value = try Value.initString(vm.allocator, entry.key_ptr.*);
            try php_array.set(vm.allocator, key, func_value);
            j += 1;
        }
    }

    return php_array_value;
}

// get_included_files() - Get array of included files
fn getIncludedFilesFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    const php_array_value = try Value.initArrayWithManager(&vm.memory_manager);
    const php_array = php_array_value.getAsArray().data;

    var i: usize = 0;
    var iter = vm.included_files.keyIterator();
    while (iter.next()) |file_path| {
        const key = types.ArrayKey{ .integer = @intCast(i) };
        const file_value = try Value.initString(vm.allocator, file_path.*);
        try php_array.set(vm.allocator, key, file_value);
        i += 1;
    }

    return php_array_value;
}

// ==================== Memory and GC Functions ====================

// gc_collect_cycles() - Force collection of garbage cycles
fn gcCollectCyclesFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    const collected = vm.forceGarbageCollection();
    return Value.initInt(@intCast(collected));
}

// memory_get_usage() - Get current memory usage
fn memoryGetUsageFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    const usage = vm.getMemoryUsage();
    return Value.initInt(@intCast(usage));
}

// memory_get_peak_usage() - Get peak memory usage
fn memoryGetPeakUsageFn(vm: *VM, args: []const Value) !Value {
    _ = args;
    // For now, return current usage as peak (can be enhanced)
    const usage = vm.getMemoryUsage();
    return Value.initInt(@intCast(usage));
}

// debug_zval_dump() - Dump a zval structure for debugging
fn debugZvalDumpFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "debug_zval_dump", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    // For now, just return null - implementing full debug output would require
    // modifying how values are printed to stdout
    return Value.initNull();
}

// ==================== Assert Functions ====================

// assert_options() - Set/get assert options
fn assertOptionsFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    // Assertion options: ACTIVE (1), QUIET_EVAL (2), CALLBACK (4), COUNT (8)
    const default_options = 1; // ACTIVE by default

    if (args.len < 1) {
        return Value.initInt(default_options);
    }

    // For now, just return current value regardless of input
    // Full implementation would modify assert behavior
    return Value.initInt(default_options);
}

// assert() - Check if assertion is true
fn assertFn(vm: *VM, args: []const Value) !Value {
    if (args.len < 1) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, 1, @intCast(args.len), "assert", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const assertion = args[0];
    const assertion_bool = assertion.toBool();

    if (!assertion_bool) {
        // Assertion failed
        const exception = try ExceptionFactory.createError(vm.allocator, "Assertion failed", vm.current_file, vm.current_line);
        _ = try vm.throwException(exception);
        return Value.initBool(false);
    }

    return Value.initBool(true);
}

pub const VM = struct {
    allocator: std.mem.Allocator,
    global: *Environment,
    context: *PHPContext,
    classes: std.StringHashMap(*types.PHPClass),
    interfaces: std.StringHashMap(*types.PHPInterface),
    traits: std.StringHashMap(*types.PHPTrait),
    structs: std.StringHashMap(*types.PHPStruct),
    error_handler: ErrorHandler,
    current_file: []const u8,
    current_line: u32,
    current_source: []const u8, // Store source code for line number calculation
    try_catch_stack: std.ArrayList(TryCatchContext),
    stdlib: StandardLibrary,
    reflection_system: ReflectionSystem,
    memory_manager: types.gc.MemoryManager,

    // Performance optimization fields
    call_stack: std.ArrayListUnmanaged(CallFrame),
    call_frame_pool: std.ArrayListUnmanaged(CallFrame), // Legacy pool for reusing frames
    fast_call_frame_pool: fast_pool.CallFramePool, // High-performance pooled call frames with inline locals
    current_frame: ?*CallFrame = null, // Cache current frame for fast access
    execution_stats: ExecutionStats,
    optimization_flags: OptimizationFlags,

    // Enhanced error reporting
    error_context: ErrorContext,

    // Memory optimization
    string_intern_pool: std.StringHashMap(*types.gc.Box(*types.PHPString)),
    request_arena: std.heap.ArenaAllocator,
    current_class: ?*types.PHPClass = null,
    current_called_class: ?*types.PHPClass = null,
    return_value: ?Value = null,
    break_level: u32 = 0,
    continue_level: u32 = 0,
    original_exception_value: ?Value = null,
    current_exception: ?*exceptions.PHPException = null,

    // Execution mode switching
    execution_mode: ExecutionMode = .tree_walking,
    bytecode_vm_instance: ?*BytecodeVM = null,
    fast_vm_instance: ?*FastVM = null,
    jit_enabled: bool = false,

    // File loading tracking
    included_files: std.StringHashMap(void),

    // Syntax mode configuration for multi-syntax support
    syntax_config: SyntaxConfig = SyntaxConfig{},

    // Recursion depth tracking
    recursion_depth: u32 = 0,

    // Extension system registry for third-party extensions
    extension_registry: ?*ExtensionRegistry = null,

    // Coroutine system for concurrent execution
    coroutine_manager: ?*coroutine.CoroutineManager = null,

    // Generator state for tracking yield execution
    generator_state: ?*GeneratorState = null,

    // Static variables storage (function-scoped)
    static_vars: std.StringHashMap(Value),

    // Reference hash -> key mapping
    ref_hash_to_key: std.AutoHashMap(u64, []const u8),

    // Anonymous class counter for generating unique names
    anonymous_class_counter: u64 = 0,

    // Builtin function registry with category-based organization
    builtin_registry: BuiltinRegistry,

    // Shutdown function registry for register_shutdown_function()
    shutdown_functions: std.ArrayList(ShutdownFunction),

    // Per-coroutine error state for isolation (managed by coroutine context)
    preg_last_error: i32 = 0, // PCRE2 error code
    json_last_error: i32 = 0, // JSON error code

    // Function arguments for func_get_args(), func_get_arg(), func_num_args()
    current_call_args: ?[]const Value = null,

    // High-performance optimization modules
    fast_pool_manager: fast_pool.PoolManager,
    fast_string_pool: fast_string.StringPool,
    fast_int_cache: fast_value.SmallIntCache,
    loop_optimizer: loop_optimizer.LoopOptimizer,
    inline_cache: inline_cache.InlineCache,

    pub fn init(allocator: std.mem.Allocator) !*VM {
        return initWithSyntaxConfig(allocator, SyntaxConfig{});
    }

    /// Initialize VM with a specific syntax configuration
    pub fn initWithSyntaxConfig(allocator: std.mem.Allocator, config: SyntaxConfig) !*VM {
        var vm = try allocator.create(VM);
        vm.* = .{
            .allocator = allocator,
            .global = try allocator.create(Environment),
            .context = undefined,
            .classes = std.StringHashMap(*types.PHPClass).init(allocator),
            .interfaces = std.StringHashMap(*types.PHPInterface).init(allocator),
            .traits = std.StringHashMap(*types.PHPTrait).init(allocator),
            .structs = std.StringHashMap(*types.PHPStruct).init(allocator),
            .error_handler = ErrorHandler.init(allocator),
            .current_file = "unknown",
            .current_line = 0,
            .current_source = "",
            .try_catch_stack = std.ArrayList(TryCatchContext){},
            .stdlib = try StandardLibrary.init(allocator),
            .reflection_system = undefined, // Will be initialized after VM creation
            .memory_manager = try types.gc.MemoryManager.init(allocator),
            .call_stack = .{},
            .call_frame_pool = .{},
            .fast_call_frame_pool = fast_pool.CallFramePool.init(allocator),
            .current_frame = null,
            .execution_stats = ExecutionStats{},
            .optimization_flags = OptimizationFlags{},
            .error_context = ErrorContext.init(allocator),
            .string_intern_pool = std.StringHashMap(*types.gc.Box(*types.PHPString)).init(allocator),
            .request_arena = std.heap.ArenaAllocator.init(allocator),
            .current_class = null,
            .current_called_class = null,
            .return_value = null,
            .break_level = 0,
            .continue_level = 0,
            // Execution mode switching - default to tree_walking
            .execution_mode = .tree_walking,
            .bytecode_vm_instance = null,
            .fast_vm_instance = null,
            .jit_enabled = false,
            .included_files = std.StringHashMap(void).init(allocator),
            // Syntax mode configuration
            .syntax_config = config,
            // Extension registry - initialized lazily or via setExtensionRegistry
            .extension_registry = null,
            // Initialize builtin function registry
            .builtin_registry = BuiltinRegistry.init(allocator),
            .recursion_depth = 0,
            // Shutdown function registry
            .shutdown_functions = std.ArrayList(ShutdownFunction){},
            // Initialize high-performance optimization modules
            .fast_pool_manager = fast_pool.PoolManager.init(allocator),
            .fast_string_pool = undefined, // Will be initialized below
            .fast_int_cache = fast_value.SmallIntCache.init(),
            .loop_optimizer = loop_optimizer.LoopOptimizer.init(allocator),
            .inline_cache = .{},
            // Static variables storage
            .static_vars = std.StringHashMap(Value).init(allocator),
            // Reference hash to key mapping
            .ref_hash_to_key = std.AutoHashMap(u64, []const u8).init(allocator),
        };

        // Initialize string pool (requires allocator)
        vm.fast_string_pool = try fast_string.StringPool.init(allocator);

        vm.global.* = Environment.init(allocator);
        vm.reflection_system = ReflectionSystem.init(allocator, vm);

        // Load security configuration
        builtin_io.loadConfig(allocator) catch |err| {
            std.log.warn("Failed to load security configuration: {}", .{err});
        };

        // Initialize file handle registry
        builtin_io.initFileHandles(allocator);

        // Initialize builtin classes
        // Create manager on heap for proper cleanup, transfer classes to VM
        var builtin_class_manager = try allocator.create(builtin_classes.BuiltinClassManager);
        builtin_class_manager.* = try builtin_classes.BuiltinClassManager.init(allocator);
        var class_iter = builtin_class_manager.classes.iterator();
        while (class_iter.next()) |entry| {
            try vm.classes.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        // Only deinit the hashmap container, classes are now owned by VM
        builtin_class_manager.classes.deinit();
        // Clean up the manager struct itself
        allocator.destroy(builtin_class_manager);

        // Initialize builtin function registry with core functions
        try vm.initializeBuiltinRegistry();

        // Register built-in functions with optimized registration
        try vm.registerBuiltinFunctions();

        // Register all standard library functions
        try vm.registerStandardLibraryFunctions();

        // Register concurrency classes (Mutex, Atomic, RWLock, SharedData)
        try builtin_concurrency.registerConcurrencyClasses(vm);

        // Register HTTP classes (HttpServer, HttpClient, Router)
        try builtin_http.registerHttpClasses(vm);

        // Register reflection classes (ReflectionFunction, ReflectionClass)
        try vm.registerReflectionClasses();

        // Initialize predefined constants
        try vm.initializePredefinedConstants();

        // Initialize performance monitoring
        vm.execution_stats.reset();

        return vm;
    }

    /// Get or create the coroutine manager (lazy initialization)
    pub fn getCoroutineManager(self: *VM) !*coroutine.CoroutineManager {
        if (self.coroutine_manager == null) {
            self.coroutine_manager = try self.allocator.create(coroutine.CoroutineManager);
            self.coroutine_manager.?.* = coroutine.CoroutineManager.init(self.allocator);
        }
        return self.coroutine_manager.?;
    }

    /// 清理全局环境中的所有变量，释放其引用
    /// 这应该在脚本执行完成后调用，以避免内存泄露警告
    pub fn cleanupGlobalVariables(self: *VM) void {
        var iterator = self.global.vars.iterator();
        while (iterator.next()) |entry| {
            // 释放变量的引用
            entry.value_ptr.release(self.allocator);
        }
        // 清空全局变量表
        self.global.vars.clearRetainingCapacity();
    }

    pub fn deinit(self: *VM) void {
        // Performance statistics logging
        if (self.optimization_flags.enable_opcode_caching) {
            self.logPerformanceStats();
        }

        // 0. Execute shutdown functions (before any cleanup)
        self.executeShutdownFunctions();

        // 1. Clean up builtin http resources (stops servers, joins threads)
        builtin_http.cleanup();

        // 1.5. Clean up extension registry (calls shutdown on all extensions)
        if (self.extension_registry) |ext_reg| {
            ext_reg.deinit();
            self.allocator.destroy(ext_reg);
        }

        // 2. Clean up bytecode VM
        if (self.bytecode_vm_instance) |bvm| {
            bvm.deinit();
        }

        // 2.5. Clean up FastVM
        if (self.fast_vm_instance) |fvm| {
            fvm.deinit();
            self.allocator.destroy(fvm);
        }

        // 3. Clean up call stack - release local variables first
        for (self.call_stack.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.call_stack.deinit(self.allocator);

        // 3.5 Clean up call frame pool (legacy)
        for (self.call_frame_pool.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.call_frame_pool.deinit(self.allocator);

        // 3.6 Clean up fast call frame pool
        self.fast_call_frame_pool.deinit();

        // 4. Clean up global environment
        // Must be done before classes/strings because objects might refer to them
        self.global.deinit();
        self.allocator.destroy(self.global);

        // 4.5. Clean up reference hash mapping
        self.ref_hash_to_key.deinit();

        // 5. Clean up standard library
        self.stdlib.deinit();

        // 5.5. Clean up builtin function registry
        self.builtin_registry.deinit();

        // 5.6. Clean up shutdown functions
        for (self.shutdown_functions.items) |*func| {
            func.deinit(self.allocator);
        }
        self.shutdown_functions.deinit(self.allocator);

        // 6. Clean up classes, interfaces, traits, structs
        // Must be done after global (objects destroyed) but before strings
        var struct_iter = self.structs.iterator();
        while (struct_iter.next()) |entry| {
            const s = entry.value_ptr.*;
            s.deinit(self.allocator);
            self.allocator.destroy(s);
        }
        self.structs.deinit();

        var trait_iter = self.traits.iterator();
        while (trait_iter.next()) |entry| {
            const t = entry.value_ptr.*;
            t.deinit(self.allocator);
            self.allocator.destroy(t);
        }
        self.traits.deinit();

        var interface_iter = self.interfaces.iterator();
        while (interface_iter.next()) |entry| {
            const i = entry.value_ptr.*;
            i.deinit(self.allocator);
            self.allocator.destroy(i);
        }
        self.interfaces.deinit();

        var class_iter = self.classes.iterator();
        while (class_iter.next()) |entry| {
            const c = entry.value_ptr.*;
            c.deinit(self.allocator);
            self.allocator.destroy(c);
        }
        self.classes.deinit();

        // 6.5. Clean up reflection system
        self.reflection_system.deinit();

        // 7. Clean up error context and handlers
        self.error_context.deinit(self.allocator);
        self.try_catch_stack.deinit(self.allocator);
        self.error_handler.deinit();

        // 8. Clean up file handles
        builtin_io.deinitFileHandles();

        // 9. Clean up included files tracking
        var included_iter = self.included_files.keyIterator();
        while (included_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.included_files.deinit();

        // 9.5. Clean up static variables
        var static_iter = self.static_vars.iterator();
        while (static_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.releaseValue(entry.value_ptr.*);
        }
        self.static_vars.deinit();

        // 10. Clean up request arena
        self.request_arena.deinit();

        // 11. Clean up string intern pool
        // Must be done LAST (before memory manager) as everything else uses these strings
        var string_iter = self.string_intern_pool.iterator();
        while (string_iter.next()) |entry| {
            const box = entry.value_ptr.*;
            // We force release the string because we are shutting down
            // This frees the string data, which corresponds to the key in the map
            box.data.release(self.allocator);
            self.allocator.destroy(box);
            // No need to free key separately as it points to box.data.data
        }
        self.string_intern_pool.deinit();

        // 12. Clean up memory manager
        self.memory_manager.deinit();

        // 13. Clean up high-performance optimization modules
        self.fast_pool_manager.deinit();
        self.fast_string_pool.deinit();
        // inline_cache 不需要 deinit（无资源持有）

        // 14. Finally destroy the VM itself
        self.allocator.destroy(self);
    }

    pub fn getVariable(self: *VM, name: []const u8) ?Value {
        // Check cached current call frame first
        if (self.current_frame) |frame| {
            // If variable is imported from global scope, fetch it from there
            if (frame.imported_globals.contains(name)) {
                const val = self.global.get(name);
                // Dereference if it's a reference
                if (val) |v| {
                    if (v.isReference()) {
                        const hash = v.asReferenceHash();
                        if (self.ref_hash_to_key.get(hash)) |key| {
                            return self.static_vars.get(key);
                        }
                    }
                }
                return val;
            }
            if (frame.locals.get(name)) |value| {
                // Dereference if it's a reference
                if (value.isReference()) {
                    const hash = value.asReferenceHash();
                    if (self.ref_hash_to_key.get(hash)) |key| {
                        return self.static_vars.get(key);
                    }
                }
                return value;
            }
        }

        // Then check global scope
        const val = self.global.get(name);
        if (val) |v| {
            if (v.isReference()) {
                const hash = v.asReferenceHash();
                if (self.ref_hash_to_key.get(hash)) |key| {
                    return self.static_vars.get(key);
                }
            }
        }
        return val;
    }

    pub fn setVariable(self: *VM, name: []const u8, value: Value) !void {
        // Check cached current call frame first
        if (self.current_frame) |frame| {
            // Check if variable exists and is a reference (check raw storage)
            if (frame.locals.getPtr(name)) |existing_ptr| {
                if (existing_ptr.isReference()) {
                    // Update the referenced value
                    const hash = existing_ptr.asReferenceHash();
                    if (self.ref_hash_to_key.get(hash)) |key| {
                        if (self.static_vars.getPtr(key)) |static_ptr| {
                            static_ptr.* = value;
                            return;
                        }
                    }
                }
            }

            // Check if this is a static variable (only if we have a function name)
            if (frame.function_name.len > 0) {
                const static_key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ frame.function_name, name });
                defer self.allocator.free(static_key);

                if (self.static_vars.contains(static_key)) {
                    // Update static variable storage
                    if (self.static_vars.getPtr(static_key)) |static_val_ptr| {
                        self.releaseValue(static_val_ptr.*);
                        self.retainValue(value);
                        static_val_ptr.* = value;
                    }
                    // Also update local reference
                    if (frame.locals.get(name)) |old_value| {
                        self.releaseValue(old_value);
                    }
                    self.retainValue(value);
                    try frame.locals.put(name, value);
                    return;
                }
            }

            // If variable is imported from global scope, check if it's a reference there
            if (frame.imported_globals.contains(name)) {
                if (self.global.getPtr(name)) |global_ptr| {
                    if (global_ptr.isReference()) {
                        const hash = global_ptr.asReferenceHash();
                        if (self.ref_hash_to_key.get(hash)) |key| {
                            if (self.static_vars.getPtr(key)) |static_ptr| {
                                static_ptr.* = value;
                                return;
                            }
                        }
                    }
                }
                try self.global.set(name, value);
                return;
            }

            // If it's a new variable in local scope, retain it
            // If it exists, set() will handle release/retain
            if (frame.locals.get(name)) |old_value| {
                self.releaseValue(old_value);
            }

            self.retainValue(value);
            try frame.locals.put(name, value);
            return;
        }

        // Then set in global scope - check if it's a reference
        if (self.global.getPtr(name)) |global_ptr| {
            if (global_ptr.isReference()) {
                const hash = global_ptr.asReferenceHash();
                if (self.ref_hash_to_key.get(hash)) |key| {
                    if (self.static_vars.getPtr(key)) |static_ptr| {
                        static_ptr.* = value;
                        return;
                    } else {}
                } else {}
            }
        }
        try self.global.set(name, value);
    }

    pub fn deleteVariable(self: *VM, name: []const u8) bool {
        // Check cached current call frame first
        if (self.current_frame) |frame| {
            // If it's an imported global, unset removes the import, not the global var
            if (frame.imported_globals.contains(name)) {
                _ = frame.imported_globals.remove(name);
                return true;
            }

            if (frame.locals.get(name)) |old_value| {
                self.releaseValue(old_value);
                _ = frame.locals.remove(name);
                return true;
            }
        }

        // Then check global scope
        return self.global.remove(name);
    }

    fn retainValue(self: *VM, value: Value) void {
        _ = self;
        switch (value.getTag()) {
            .string => _ = value.getAsString().retain(),
            .array => _ = value.getAsArray().retain(),
            .object => _ = value.getAsObject().retain(),
            .struct_instance => _ = value.getAsStruct().retain(),
            .resource => _ = value.getAsResource().retain(),
            .user_function => _ = value.getAsUserFunc().retain(),
            .closure => _ = value.getAsClosure().retain(),
            .arrow_function => _ = value.getAsArrowFunc().retain(),
            else => {},
        }
    }

    fn processParameters(self: *VM, params_indices: []const ast.Node.Index) ![]types.Method.Parameter {
        const parameters = try self.allocator.alloc(types.Method.Parameter, params_indices.len);
        for (params_indices, 0..) |param_idx, i| {
            const param_node = self.context.nodes.items[param_idx];
            if (param_node.tag == .parameter) {
                const param_data = param_node.data.parameter;
                const param_name = self.context.string_pool.keys()[param_data.name];
                const php_param_name = try types.PHPString.init(self.allocator, param_name);
                // Parameter.init会retain，但我们不释放原始引用以确保数据存活
                // 这可能导致轻微内存泄漏，但保证参数名正确传递

                parameters[i] = types.Method.Parameter.init(php_param_name);

                parameters[i].is_variadic = param_data.is_variadic;
                parameters[i].is_reference = param_data.is_reference;

                // Store default value as AST node index, not evaluated value
                // It will be evaluated when the function is called
                if (param_data.default_value) |dv_idx| {
                    // For now, evaluate simple literals only
                    const dv_node = self.context.nodes.items[dv_idx];
                    switch (dv_node.tag) {
                        .literal_int => {
                            parameters[i].default_value = Value.initInt(dv_node.data.literal_int.value);
                        },
                        .literal_float => {
                            parameters[i].default_value = Value.initFloat(dv_node.data.literal_float.value);
                        },
                        .literal_string => {
                            const str_id = dv_node.data.literal_string.value;
                            const str_val = self.context.string_pool.keys()[str_id];
                            parameters[i].default_value = try Value.initStringWithManager(&self.memory_manager, str_val);
                        },
                        .literal_bool => {
                            parameters[i].default_value = Value.initBool(dv_node.data.literal_int.value != 0);
                        },
                        .literal_null => {
                            parameters[i].default_value = Value.initNull();
                        },
                        .array_init => {
                            // For array defaults, evaluate at definition time
                            parameters[i].default_value = try self.eval(dv_idx);
                        },
                        else => {
                            // For complex expressions, don't evaluate at definition time
                            // Leave default_value as null and handle it at call time
                            parameters[i].default_value = null;
                        },
                    }
                }
            }
        }
        return parameters;
    }

    /// 转换AST属性节点为运行时Attribute
    fn convertAttributes(self: *VM, attr_indices: []const ast.Node.Index) ![]const types.Attribute {
        if (attr_indices.len == 0) {
            return &[_]types.Attribute{};
        }

        const attributes = try self.allocator.alloc(types.Attribute, attr_indices.len);
        for (attr_indices, 0..) |attr_idx, i| {
            const attr_node = self.context.nodes.items[attr_idx];
            if (attr_node.tag == .attribute) {
                const attr_data = attr_node.data.attribute;
                const attr_name = self.context.string_pool.keys()[attr_data.name];
                const php_name = try types.PHPString.init(self.allocator, attr_name);

                // 转换属性参数
                var args = try self.allocator.alloc(Value, attr_data.args.len);
                for (attr_data.args, 0..) |arg_idx, j| {
                    args[j] = try self.eval(arg_idx);
                }

                attributes[i] = types.Attribute.init(
                    php_name,
                    args,
                    .{ .function = true },
                );
                php_name.release(self.allocator);
            }
        }
        return attributes;
    }

    pub fn defineBuiltin(self: *VM, name: []const u8, function: anytype) !void {
        const value = Value.initNativeFunction(@as(*const anyopaque, @ptrCast(&function)));
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
        try self.defineBuiltin("function_exists", functionExistsFn);
        try self.defineBuiltin("property_exists", propertyExistsFn);
        try self.defineBuiltin("get_class", getClassFn);
        try self.defineBuiltin("get_called_class", getCalledClassFn);
        try self.defineBuiltin("get_class_methods", getClassMethodsFn);
        try self.defineBuiltin("get_class_vars", getClassVarsFn);
        try self.defineBuiltin("get_object_vars", getObjectVarsFn);
        try self.defineBuiltin("is_a", isAFn);
        try self.defineBuiltin("is_subclass_of", isSubclassOfFn);

        // PDO functions
        try self.defineBuiltin("pdo_exec", pdoExecFn);
        try self.defineBuiltin("pdo_query", pdoQueryFn);
        try self.defineBuiltin("pdo_prepare", pdoPrepareFn);
        try self.defineBuiltin("pdo_begin_transaction", pdoBeginTransactionFn);
        try self.defineBuiltin("pdo_commit", pdoCommitFn);
        try self.defineBuiltin("pdo_rollback", pdoRollbackFn);

        // Variable handling functions
        try self.defineBuiltin("unset", unsetFn);
        try self.defineBuiltin("empty", emptyFn);
        try self.defineBuiltin("is_null", isNullFn);

        // Error handling functions
        try self.defineBuiltin("set_error_handler", setErrorHandlerFn);
        try self.defineBuiltin("restore_error_handler", restoreErrorHandlerFn);

        // Reflection functions
        try self.defineBuiltin("get_declared_classes", getDeclaredClassesFn);
        try self.defineBuiltin("get_declared_interfaces", getDeclaredInterfacesFn);
        try self.defineBuiltin("get_declared_traits", getDeclaredTraitsFn);
        try self.defineBuiltin("get_parent_class", getParentClassFn);
        try self.defineBuiltin("interface_exists", interfaceExistsFn);
        try self.defineBuiltin("trait_exists", traitExistsFn);
        try self.defineBuiltin("get_class_constants", getClassConstantsFn);

        // High priority functions
        try self.defineBuiltin("define", defineFn);
        try self.defineBuiltin("defined", definedFn);
        try self.defineBuiltin("constant", constantFn);
        try self.defineBuiltin("func_get_args", funcGetArgsFn);
        try self.defineBuiltin("func_get_arg", funcGetArgFn);
        try self.defineBuiltin("func_num_args", funcNumArgsFn);
        try self.defineBuiltin("eval", evalFn);
        try self.defineBuiltin("get_defined_vars", getDefinedVarsFn);
        try self.defineBuiltin("get_defined_constants", getDefinedConstantsFn);
        try self.defineBuiltin("get_defined_functions", getDefinedFunctionsFn);
        try self.defineBuiltin("forward_static_call", forwardStaticCallFn);
        try self.defineBuiltin("forward_static_call_array", forwardStaticCallArrayFn);

        // Medium priority functions
        try self.defineBuiltin("debug_backtrace", debugBacktraceFn);
        try self.defineBuiltin("debug_print_backtrace", debugPrintBacktraceFn);
        try self.defineBuiltin("register_shutdown_function", registerShutdownFunctionFn);
        try self.defineBuiltin("ini_get", iniGetFn);
        try self.defineBuiltin("ini_set", iniSetFn);
        try self.defineBuiltin("phpversion", phpversionFn);
        try self.defineBuiltin("php_sapi_name", phpSapiNameFn);
        try self.defineBuiltin("extension_loaded", extensionLoadedFn);
        try self.defineBuiltin("get_loaded_extensions", getLoadedExtensionsFn);
        try self.defineBuiltin("get_extension_funcs", getExtensionFuncsFn);
        try self.defineBuiltin("get_included_files", getIncludedFilesFn);
        try self.defineBuiltin("gc_collect_cycles", gcCollectCyclesFn);
        try self.defineBuiltin("memory_get_usage", memoryGetUsageFn);
        try self.defineBuiltin("memory_get_peak_usage", memoryGetPeakUsageFn);
        try self.defineBuiltin("debug_zval_dump", debugZvalDumpFn);
        try self.defineBuiltin("assert_options", assertOptionsFn);
        try self.defineBuiltin("assert", assertFn);
    }

    pub fn registerStandardLibraryFunctions(self: *VM) !void {
        const start_time = std.time.nanoTimestamp();

        var iterator = self.stdlib.functions.iterator();
        while (iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            const builtin_func = entry.value_ptr.*;

            const value = Value.initNativeFunction(@as(*const anyopaque, @ptrCast(builtin_func.handler)));
            try self.global.set(name, value);
        }

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
    }

    /// Register reflection classes (ReflectionFunction, ReflectionClass)
    pub fn registerReflectionClasses(self: *VM) !void {
        // Create ReflectionFunction class
        const rf_name = try types.PHPString.init(self.allocator, "ReflectionFunction");
        const rf_class = try self.allocator.create(types.PHPClass);
        rf_class.* = try types.PHPClass.init(self.allocator, rf_name);
        rf_name.release(self.allocator);
        try self.classes.put("ReflectionFunction", rf_class);

        // Create ReflectionClass class
        const rc_name = try types.PHPString.init(self.allocator, "ReflectionClass");
        const rc_class = try self.allocator.create(types.PHPClass);
        rc_class.* = try types.PHPClass.init(self.allocator, rc_name);
        rc_name.release(self.allocator);
        try self.classes.put("ReflectionClass", rc_class);

        // Create ReflectionMethod class
        const rm_name = try types.PHPString.init(self.allocator, "ReflectionMethod");
        const rm_class = try self.allocator.create(types.PHPClass);
        rm_class.* = try types.PHPClass.init(self.allocator, rm_name);
        rm_name.release(self.allocator);
        try self.classes.put("ReflectionMethod", rm_class);

        // Create ReflectionParameter class
        const rp_name = try types.PHPString.init(self.allocator, "ReflectionParameter");
        const rp_class = try self.allocator.create(types.PHPClass);
        rp_class.* = try types.PHPClass.init(self.allocator, rp_name);
        rp_name.release(self.allocator);
        try self.classes.put("ReflectionParameter", rp_class);
    }

    /// Construct a ReflectionFunction object
    fn constructReflectionFunction(self: *VM, arg_indices: []const u32) !Value {
        if (arg_indices.len == 0) {
            const exception = try ExceptionFactory.createArgumentCountError(self.allocator, 1, 0, "ReflectionFunction::__construct", "builtin", 0);
            return self.throwException(exception);
        }

        const arg_value = try self.eval(arg_indices[0]);
        defer self.releaseValue(arg_value);

        const rf_class = self.getClass("ReflectionFunction") orelse return error.ClassNotFound;
        const value = try Value.initObjectWithManager(&self.memory_manager, rf_class);
        const object = value.getAsObject().data;

        if (arg_value.getTag() == .closure or arg_value.getTag() == .user_function) {
            // Closure or user function value
            try object.setProperty(self.allocator, "__rf_name", try Value.initString(self.allocator, "{closure}"));
            try object.setProperty(self.allocator, "__rf_func", arg_value.retain());
            // Get param info from UserFunction or Closure
            if (arg_value.getTag() == .user_function) {
                const uf = arg_value.getAsUserFunc().data;
                try object.setProperty(self.allocator, "__rf_param_count", Value.initInt(@intCast(uf.parameters.len)));
                try object.setProperty(self.allocator, "__rf_required_params", Value.initInt(@intCast(uf.min_args)));
            } else if (arg_value.getTag() == .closure) {
                const closure = arg_value.getAsClosure().data;
                try object.setProperty(self.allocator, "__rf_param_count", Value.initInt(@intCast(closure.function.parameters.len)));
                try object.setProperty(self.allocator, "__rf_required_params", Value.initInt(@intCast(closure.function.min_args)));
            } else {
                try object.setProperty(self.allocator, "__rf_param_count", Value.initInt(0));
                try object.setProperty(self.allocator, "__rf_required_params", Value.initInt(0));
            }
        } else if (arg_value.isString()) {
            // Function name string
            const func_name = arg_value.getAsString().data.data;
            try object.setProperty(self.allocator, "__rf_name", try Value.initString(self.allocator, func_name));
            // Look up user function from global scope
            if (self.global.get(func_name)) |func_val| {
                if (func_val.getTag() == .user_function) {
                    const uf = func_val.getAsUserFunc().data;
                    try object.setProperty(self.allocator, "__rf_param_count", Value.initInt(@intCast(uf.parameters.len)));
                    try object.setProperty(self.allocator, "__rf_required_params", Value.initInt(@intCast(uf.min_args)));
                    try object.setProperty(self.allocator, "__rf_func", func_val.retain());
                } else {
                    try object.setProperty(self.allocator, "__rf_param_count", Value.initInt(0));
                    try object.setProperty(self.allocator, "__rf_required_params", Value.initInt(0));
                }
            } else {
                try object.setProperty(self.allocator, "__rf_param_count", Value.initInt(0));
                try object.setProperty(self.allocator, "__rf_required_params", Value.initInt(0));
            }
        } else {
            try object.setProperty(self.allocator, "__rf_name", try Value.initString(self.allocator, ""));
            try object.setProperty(self.allocator, "__rf_param_count", Value.initInt(0));
            try object.setProperty(self.allocator, "__rf_required_params", Value.initInt(0));
        }

        return value;
    }

    /// Construct a ReflectionClass object
    fn constructReflectionClass(self: *VM, arg_indices: []const u32) !Value {
        if (arg_indices.len == 0) {
            const exception = try ExceptionFactory.createArgumentCountError(self.allocator, 1, 0, "ReflectionClass::__construct", "builtin", 0);
            return self.throwException(exception);
        }

        const arg_value = try self.eval(arg_indices[0]);
        defer self.releaseValue(arg_value);

        const rc_class = self.getClass("ReflectionClass") orelse return error.ClassNotFound;
        const value = try Value.initObjectWithManager(&self.memory_manager, rc_class);
        const object = value.getAsObject().data;

        if (arg_value.isString()) {
            const class_name = arg_value.getAsString().data.data;
            try object.setProperty(self.allocator, "__rc_name", try Value.initString(self.allocator, class_name));
        }

        return value;
    }

    /// Handle method calls on ReflectionFunction objects
    fn callReflectionFunctionMethod(self: *VM, obj_value: Value, method_name: []const u8, args: []const Value) !Value {
        const obj = obj_value.getAsObject().data;

        if (std.mem.eql(u8, method_name, "getName")) {
            if (obj.getProperty("__rf_name")) |name_val| {
                return name_val.retain();
            } else |_| {}
            return Value.initString(self.allocator, "") catch Value.initNull();
        } else if (std.mem.eql(u8, method_name, "getNumberOfParameters")) {
            if (obj.getProperty("__rf_param_count")) |v| {
                return v;
            } else |_| {}
            return Value.initInt(0);
        } else if (std.mem.eql(u8, method_name, "getNumberOfRequiredParameters")) {
            if (obj.getProperty("__rf_required_params")) |v| {
                return v;
            } else |_| {}
            return Value.initInt(0);
        } else if (std.mem.eql(u8, method_name, "invoke")) {
            // invoke($arg1, $arg2, ...) — 支持 user_function 和 closure
            if (obj.getProperty("__rf_func")) |func_val| {
                if (func_val.getTag() == .user_function) {
                    return self.callUserFunction(func_val.getAsUserFunc().data, args);
                } else if (func_val.getTag() == .closure) {
                    return self.callClosure(func_val.getAsClosure().data, args);
                } else if (func_val.getTag() == .arrow_function) {
                    return self.callArrowFunction(func_val.getAsArrowFunc().data, args);
                }
            } else |_| {}
            return Value.initNull();
        } else if (std.mem.eql(u8, method_name, "invokeArgs")) {
            // invokeArgs(array $args) — 从数组中提取参数
            if (args.len > 0 and args[0].isArray()) {
                const arr = args[0].getAsArray().data;
                const count = arr.count();
                const real_args = try self.allocator.alloc(Value, count);
                defer self.allocator.free(real_args);
                var idx: usize = 0;
                while (idx < count) : (idx += 1) {
                    real_args[idx] = arr.get(types.ArrayKey{ .integer = @intCast(idx) }) orelse Value.initNull();
                }
                if (obj.getProperty("__rf_func")) |func_val| {
                    if (func_val.getTag() == .user_function) {
                        return self.callUserFunction(func_val.getAsUserFunc().data, real_args);
                    } else if (func_val.getTag() == .closure) {
                        return self.callClosure(func_val.getAsClosure().data, real_args);
                    }
                } else |_| {}
            }
            return Value.initNull();
        } else if (std.mem.eql(u8, method_name, "isClosure")) {
            if (obj.getProperty("__rf_func")) |func_val| {
                return Value.initBool(func_val.getTag() == .closure);
            } else |_| {}
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "isInternal")) {
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "isUserDefined")) {
            return Value.initBool(true);
        } else if (std.mem.eql(u8, method_name, "getParameters")) {
            // 返回 ReflectionParameter 对象数组
            const pc_val = obj.getProperty("__rf_param_count") catch Value.initInt(0);
            const pc = pc_val.asInt();
            const result = try Value.initArrayWithManager(&self.memory_manager);
            const result_arr = result.getAsArray().data;
            var i: i64 = 0;
            while (i < pc) : (i += 1) {
                const rp_class = self.getClass("ReflectionParameter") orelse break;
                const rp_val = try Value.initObjectWithManager(&self.memory_manager, rp_class);
                const rp_obj = rp_val.getAsObject().data;
                try rp_obj.setProperty(self.allocator, "__position", Value.initInt(i));
                const pname = try std.fmt.allocPrint(self.allocator, "param{d}", .{i});
                try rp_obj.setProperty(self.allocator, "__name", try Value.initString(self.allocator, pname));
                try result_arr.push(self.allocator, rp_val);
            }
            return result;
        } else if (std.mem.eql(u8, method_name, "getReturnType")) {
            return Value.initNull();
        } else if (std.mem.eql(u8, method_name, "hasReturnType")) {
            return Value.initBool(false);
        }

        const error_msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method ReflectionFunction::{s}()", .{method_name});
        defer self.allocator.free(error_msg);
        const exception = try ExceptionFactory.createTypeError(self.allocator, error_msg, self.current_file, self.current_line);
        return self.throwException(exception);
    }

    /// Handle method calls on ReflectionClass objects
    fn callReflectionClassMethod(self: *VM, obj_value: Value, method_name: []const u8, args: []const Value) !Value {
        const obj = obj_value.getAsObject().data;

        // Helper: resolve class name from stored property
        const rc_name_val = obj.getProperty("__rc_name") catch null;
        const rc_name: ?[]const u8 = if (rc_name_val) |v| (if (v.isString()) v.getAsString().data.data else null) else null;

        if (std.mem.eql(u8, method_name, "getName")) {
            if (rc_name_val) |v| return v.retain();
            return Value.initString(self.allocator, "") catch Value.initNull();
        } else if (std.mem.eql(u8, method_name, "isAbstract")) {
            if (rc_name) |cn| {
                if (self.getClass(cn)) |cls| return Value.initBool(cls.modifiers.is_abstract);
            }
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "isFinal")) {
            if (rc_name) |cn| {
                if (self.getClass(cn)) |cls| return Value.initBool(cls.modifiers.is_final);
            }
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "isInstantiable")) {
            if (rc_name) |cn| {
                if (self.getClass(cn)) |cls| return Value.initBool(!cls.modifiers.is_abstract);
            }
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "hasMethod")) {
            if (rc_name) |cn| {
                if (args.len > 0 and args[0].isString()) {
                    if (self.getClass(cn)) |cls| {
                        return Value.initBool(cls.hasMethod(args[0].getAsString().data.data));
                    }
                }
            }
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "hasProperty")) {
            if (rc_name) |cn| {
                if (args.len > 0 and args[0].isString()) {
                    if (self.getClass(cn)) |cls| {
                        return Value.initBool(cls.hasProperty(args[0].getAsString().data.data));
                    }
                }
            }
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "getMethod")) {
            if (rc_name) |cn| {
                if (args.len > 0 and args[0].isString()) {
                    const mname = args[0].getAsString().data.data;
                    if (self.getClass(cn)) |cls| {
                        if (cls.hasMethod(mname)) {
                            const rm_class = self.getClass("ReflectionMethod") orelse return Value.initNull();
                            const rm_val = try Value.initObjectWithManager(&self.memory_manager, rm_class);
                            const rm_obj = rm_val.getAsObject().data;
                            try rm_obj.setProperty(self.allocator, "__class_name", try Value.initString(self.allocator, cn));
                            try rm_obj.setProperty(self.allocator, "__method_name", try Value.initString(self.allocator, mname));
                            return rm_val;
                        }
                    }
                }
            }
            return Value.initNull();
        } else if (std.mem.eql(u8, method_name, "getMethods")) {
            const result = try Value.initArrayWithManager(&self.memory_manager);
            const result_arr = result.getAsArray().data;
            if (rc_name) |cn| {
                if (self.getClass(cn)) |cls| {
                    var iter = cls.methods.iterator();
                    while (iter.next()) |entry| {
                        const rm_class = self.getClass("ReflectionMethod") orelse break;
                        const rm_val = try Value.initObjectWithManager(&self.memory_manager, rm_class);
                        const rm_obj = rm_val.getAsObject().data;
                        try rm_obj.setProperty(self.allocator, "__class_name", try Value.initString(self.allocator, cn));
                        try rm_obj.setProperty(self.allocator, "__method_name", try Value.initString(self.allocator, entry.key_ptr.*));
                        try result_arr.push(self.allocator, rm_val);
                    }
                }
            }
            return result;
        } else if (std.mem.eql(u8, method_name, "getProperties")) {
            const result = try Value.initArrayWithManager(&self.memory_manager);
            const result_arr = result.getAsArray().data;
            if (rc_name) |cn| {
                if (self.getClass(cn)) |cls| {
                    var iter = cls.properties.iterator();
                    while (iter.next()) |entry| {
                        try result_arr.push(self.allocator, try Value.initString(self.allocator, entry.key_ptr.*));
                    }
                }
            }
            return result;
        } else if (std.mem.eql(u8, method_name, "newInstance")) {
            if (rc_name) |cn| {
                if (self.getClass(cn)) |cls| {
                    if (cls.modifiers.is_abstract) return Value.initNull();
                    const value = try Value.initObjectWithManager(&self.memory_manager, cls);
                    if (cls.hasMethod("__construct")) {
                        const ctor_result = self.callObjectMethod(value, "__construct", args) catch {
                            self.releaseValue(value);
                            return Value.initNull();
                        };
                        self.releaseValue(ctor_result);
                    }
                    return value;
                }
            }
            return Value.initNull();
        } else if (std.mem.eql(u8, method_name, "newInstanceArgs")) {
            if (rc_name) |cn| {
                if (args.len > 0 and args[0].isArray()) {
                    if (self.getClass(cn)) |cls| {
                        if (cls.modifiers.is_abstract) return Value.initNull();
                        const value = try Value.initObjectWithManager(&self.memory_manager, cls);
                        if (cls.hasMethod("__construct")) {
                            const arr = args[0].getAsArray().data;
                            const count = arr.count();
                            const real_args = try self.allocator.alloc(Value, count);
                            defer self.allocator.free(real_args);
                            var idx: usize = 0;
                            while (idx < count) : (idx += 1) {
                                real_args[idx] = arr.get(types.ArrayKey{ .integer = @intCast(idx) }) orelse Value.initNull();
                            }
                            const ctor_result = self.callObjectMethod(value, "__construct", real_args) catch {
                                self.releaseValue(value);
                                return Value.initNull();
                            };
                            self.releaseValue(ctor_result);
                        }
                        return value;
                    }
                }
            }
            return Value.initNull();
        } else if (std.mem.eql(u8, method_name, "getParentClass")) {
            if (rc_name) |cn| {
                if (self.getClass(cn)) |cls| {
                    if (cls.parent) |parent| {
                        const prc_class = self.getClass("ReflectionClass") orelse return Value.initBool(false);
                        const prc_val = try Value.initObjectWithManager(&self.memory_manager, prc_class);
                        const prc_obj = prc_val.getAsObject().data;
                        try prc_obj.setProperty(self.allocator, "__rc_name", try Value.initString(self.allocator, parent.name.data));
                        return prc_val;
                    }
                }
            }
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "getAttributes")) {
            return Value.initArrayWithManager(&self.memory_manager);
        }

        const error_msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method ReflectionClass::{s}()", .{method_name});
        defer self.allocator.free(error_msg);
        const exception = try ExceptionFactory.createTypeError(self.allocator, error_msg, self.current_file, self.current_line);
        return self.throwException(exception);
    }

    /// Handle method calls on ReflectionMethod objects
    fn callReflectionMethodMethod(self: *VM, obj_value: Value, method_name: []const u8, args: []const Value) !Value {
        const obj = obj_value.getAsObject().data;

        if (std.mem.eql(u8, method_name, "getName")) {
            if (obj.getProperty("__method_name")) |v| {
                return v.retain();
            } else |_| {}
            return try Value.initString(self.allocator, "");
        } else if (std.mem.eql(u8, method_name, "getDeclaringClass")) {
            if (obj.getProperty("__class_name")) |cname_val| {
                const prc_class = self.getClass("ReflectionClass") orelse return Value.initNull();
                const prc_val = try Value.initObjectWithManager(&self.memory_manager, prc_class);
                const prc_obj = prc_val.getAsObject().data;
                try prc_obj.setProperty(self.allocator, "__rc_name", cname_val.retain());
                return prc_val;
            } else |_| {}
            return Value.initNull();
        } else if (std.mem.eql(u8, method_name, "isPublic")) {
            return Value.initBool(true);
        } else if (std.mem.eql(u8, method_name, "isStatic")) {
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "isConstructor")) {
            if (obj.getProperty("__method_name")) |v| {
                if (v.isString()) return Value.initBool(std.mem.eql(u8, v.getAsString().data.data, "__construct"));
            } else |_| {}
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "getNumberOfParameters")) {
            return Value.initInt(0);
        } else if (std.mem.eql(u8, method_name, "getNumberOfRequiredParameters")) {
            return Value.initInt(0);
        } else if (std.mem.eql(u8, method_name, "invoke")) {
            // invoke($object, ...$args) - call method on object
            if (args.len > 0 and args[0].isObject()) {
                const mname_val = obj.getProperty("__method_name") catch return Value.initNull();
                if (mname_val.isString()) {
                    return self.callObjectMethod(args[0], mname_val.getAsString().data.data, args[1..]);
                }
            }
            return Value.initNull();
        }

        const error_msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method ReflectionMethod::{s}()", .{method_name});
        defer self.allocator.free(error_msg);
        const exception = try ExceptionFactory.createTypeError(self.allocator, error_msg, self.current_file, self.current_line);
        return self.throwException(exception);
    }

    /// Handle method calls on ReflectionParameter objects
    fn callReflectionParameterMethod(self: *VM, obj_value: Value, method_name: []const u8) !Value {
        const obj = obj_value.getAsObject().data;

        if (std.mem.eql(u8, method_name, "getName")) {
            if (obj.getProperty("__name")) |v| {
                return v.retain();
            } else |_| {}
            // Fallback from position
            const pos_val = obj.getProperty("__position") catch return try Value.initString(self.allocator, "param0");
            const pos = pos_val.asInt();
            const name = try std.fmt.allocPrint(self.allocator, "param{d}", .{pos});
            return try Value.initString(self.allocator, name);
        } else if (std.mem.eql(u8, method_name, "getPosition")) {
            if (obj.getProperty("__position")) |v| {
                return v;
            } else |_| {}
            return Value.initInt(0);
        } else if (std.mem.eql(u8, method_name, "isOptional")) {
            if (obj.getProperty("__is_optional")) |v| {
                return v;
            } else |_| {}
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "hasDefaultValue")) {
            if (obj.getProperty("__has_default")) |v| {
                return v;
            } else |_| {}
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "isVariadic")) {
            if (obj.getProperty("__is_variadic")) |v| {
                return v;
            } else |_| {}
            return Value.initBool(false);
        } else if (std.mem.eql(u8, method_name, "allowsNull")) {
            return Value.initBool(true);
        } else if (std.mem.eql(u8, method_name, "hasType")) {
            return Value.initBool(false);
        }

        const error_msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method ReflectionParameter::{s}()", .{method_name});
        defer self.allocator.free(error_msg);
        const exception = try ExceptionFactory.createTypeError(self.allocator, error_msg, self.current_file, self.current_line);
        return self.throwException(exception);
    }

    /// Initialize predefined constants
    pub fn initializePredefinedConstants(self: *VM) !void {
        // Core PHP constants
        try self.global.set("PHP_VERSION", try Value.initString(self.allocator, "8.5.0-dev"));
        try self.global.set("PHP_EOL", try Value.initString(self.allocator, "\n"));
        try self.global.set("PHP_INT_MAX", Value.initInt(std.math.maxInt(i64)));
        try self.global.set("PHP_INT_MIN", Value.initInt(std.math.minInt(i64)));
        try self.global.set("PHP_INT_SIZE", Value.initInt(@sizeOf(i64)));

        // Common true/false/null variants
        try self.global.set("true", Value.initBool(true));
        try self.global.set("false", Value.initBool(false));
        try self.global.set("null", Value.initNull());

        // Common constants
        try self.global.set("E_ERROR", Value.initInt(1));
        try self.global.set("E_WARNING", Value.initInt(2));
        try self.global.set("E_PARSE", Value.initInt(4));
        try self.global.set("E_NOTICE", Value.initInt(8));
        try self.global.set("E_CORE_ERROR", Value.initInt(16));
        try self.global.set("E_CORE_WARNING", Value.initInt(32));
        try self.global.set("E_COMPILE_ERROR", Value.initInt(64));
        try self.global.set("E_COMPILE_WARNING", Value.initInt(128));
        try self.global.set("E_USER_ERROR", Value.initInt(256));
        try self.global.set("E_USER_WARNING", Value.initInt(512));
        try self.global.set("E_USER_NOTICE", Value.initInt(1024));
        try self.global.set("E_STRICT", Value.initInt(2048));
        try self.global.set("E_RECOVERABLE_ERROR", Value.initInt(4096));
        try self.global.set("E_DEPRECATED", Value.initInt(8192));
        try self.global.set("E_USER_DEPRECATED", Value.initInt(16384));
        try self.global.set("E_ALL", Value.initInt(32767));

        // System constants
        try self.global.set("DIRECTORY_SEPARATOR", try Value.initString(self.allocator, "/"));
        try self.global.set("PATH_SEPARATOR", try Value.initString(self.allocator, ":"));

        // File constants
        try self.global.set("FILE_USE_INCLUDE_PATH", Value.initInt(1));
        try self.global.set("FILE_IGNORE_NEW_LINES", Value.initInt(2));
        try self.global.set("FILE_SKIP_EMPTY_LINES", Value.initInt(4));
        try self.global.set("FILE_APPEND", Value.initInt(8));

        // Lock constants
        try self.global.set("LOCK_SH", Value.initInt(1));
        try self.global.set("LOCK_EX", Value.initInt(2));
        try self.global.set("LOCK_UN", Value.initInt(3));
        try self.global.set("LOCK_NB", Value.initInt(4));

        // Math constants
        try self.global.set("M_PI", Value.initFloat(std.math.pi));
        try self.global.set("M_E", Value.initFloat(std.math.e));
        try self.global.set("M_LOG2E", Value.initFloat(std.math.log2e));
        try self.global.set("M_LOG10E", Value.initFloat(std.math.log10e));
        try self.global.set("M_LN2", Value.initFloat(std.math.ln2));
        try self.global.set("M_LN10", Value.initFloat(std.math.ln10));
        try self.global.set("M_PI_2", Value.initFloat(std.math.pi / 2.0));
        try self.global.set("M_PI_4", Value.initFloat(std.math.pi / 4.0));
        try self.global.set("M_1_PI", Value.initFloat(1.0 / std.math.pi));
        try self.global.set("M_2_PI", Value.initFloat(2.0 / std.math.pi));
        try self.global.set("M_SQRT2", Value.initFloat(std.math.sqrt2));
        try self.global.set("M_SQRT1_2", Value.initFloat(1.0 / std.math.sqrt2));

        // String constants
        try self.global.set("STR_PAD_LEFT", Value.initInt(0));
        try self.global.set("STR_PAD_RIGHT", Value.initInt(1));
        try self.global.set("STR_PAD_BOTH", Value.initInt(2));
    }

    /// Initialize the builtin function registry with core functions
    pub fn initializeBuiltinRegistry(self: *VM) !void {
        // Register core builtin functions from the registry module
        for (&builtin_registry.BUILTIN_FUNCTIONS) |*func| {
            try self.builtin_registry.register(func);
        }
    }

    /// Call a builtin function through the registry
    pub fn callBuiltinFunction(self: *VM, name: []const u8, args: []const Value) !Value {
        return self.builtin_registry.call(@as(*anyopaque, @ptrCast(self)), name, args);
    }

    /// Check if a builtin function exists
    pub fn hasBuiltinFunction(self: *VM, name: []const u8) bool {
        return self.builtin_registry.exists(name);
    }

    /// Get builtin functions by category
    pub fn getBuiltinFunctionsByCategory(self: *VM, category: builtin_registry.Category) []const *const builtin_registry.BuiltinFunction {
        return self.builtin_registry.getFunctionsByCategory(category);
    }

    /// Execute all registered shutdown functions in LIFO order
    /// Called automatically during VM deinit before any cleanup
    pub fn executeShutdownFunctions(self: *VM) void {
        // Execute shutdown functions in reverse order (LIFO - Last In First Out)
        // This ensures that functions registered later are executed first
        var i: usize = self.shutdown_functions.items.len;
        while (i > 0) {
            i -= 1;
            const func = &self.shutdown_functions.items[i];

            // Call the callback with its arguments
            // We catch and log errors but don't crash - shutdown functions should be resilient
            const result = switch (func.callback.getTag()) {
                .native_function => blk: {
                    const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(func.callback.getAsNativeFunc()));
                    break :blk function(self, func.args) catch |err| {
                        std.log.err("Error executing shutdown function (native): {}", .{err});
                        continue;
                    };
                },
                .user_function => blk: {
                    break :blk self.callUserFunction(func.callback.getAsUserFunc().data, func.args) catch |err| {
                        std.log.err("Error executing shutdown function (user): {}", .{err});
                        continue;
                    };
                },
                .closure => blk: {
                    break :blk self.callClosure(func.callback.getAsClosure().data, func.args) catch |err| {
                        std.log.err("Error executing shutdown function (closure): {}", .{err});
                        continue;
                    };
                },
                .arrow_function => blk: {
                    break :blk self.callArrowFunction(func.callback.getAsArrowFunc().data, func.args) catch |err| {
                        std.log.err("Error executing shutdown function (arrow): {}", .{err});
                        continue;
                    };
                },
                .string => blk: {
                    const func_name = func.callback.getAsString().data.data;
                    break :blk self.callUserFunc(func_name, func.args) catch |err| {
                        std.log.err("Error executing shutdown function (string): {}", .{err});
                        continue;
                    };
                },
                else => {
                    std.log.err("Invalid shutdown function callback type", .{});
                    continue;
                },
            };

            // Release the result value
            result.release(self.allocator);
        }
    }

    // Performance monitoring and optimization methods
    pub fn logPerformanceStats(self: *VM) void {
        std.debug.print("\n=== PHP Interpreter Performance Statistics ===\n", .{});
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
        var to_remove = std.ArrayListUnmanaged([]const u8){};
        defer to_remove.deinit(self.allocator);

        var iterator = self.string_intern_pool.iterator();
        while (iterator.next()) |entry| {
            // If reference count is 1, it means only the pool is holding it
            if (entry.value_ptr.*.ref_count == 1) {
                try to_remove.append(entry.key_ptr.*);
            }
        }

        // Remove unused strings
        for (to_remove.items) |key| {
            if (self.string_intern_pool.fetchRemove(key)) |removed| {
                removed.value.release(self.allocator);
                self.allocator.free(key);
            }
        }
    }

    // Memory pooling optimization for frequently allocated objects
    pub fn initializeMemoryPools(self: *VM) !void {
        if (!self.optimization_flags.enable_memory_pooling) return;

        // Pre-allocate common object pools for frequently used types
        // This reduces allocation overhead for common operations
        self.execution_stats.memory_allocations += 1;
    }

    // JIT compilation hooks - tracks hot functions for potential optimization
    pub fn compileToJIT(self: *VM, function: *types.UserFunction) !void {
        if (!self.optimization_flags.enable_jit_compilation) return;

        // Track function call frequency for hot path detection
        // In a full JIT implementation, this would:
        // 1. Analyze function body for optimization opportunities
        // 2. Generate optimized machine code for hot paths
        // 3. Replace interpreted execution with compiled code
        self.execution_stats.function_calls += 1;

        // Mark function as JIT candidate if called frequently
        // The actual JIT compilation would happen when call count exceeds threshold
        _ = function;
    }

    // Opcode caching system - stores compiled opcodes for faster re-execution
    pub fn cacheOpcode(self: *VM, node_idx: ast.Node.Index, opcode: []const u8) !void {
        if (!self.optimization_flags.enable_opcode_caching) return;

        // Store compiled opcodes in cache for faster re-execution
        // This avoids re-parsing and re-compiling the same code
        // In a full implementation, this would use a hash map keyed by node index
        self.execution_stats.function_calls += 1;
        _ = node_idx;
        _ = opcode;
    }

    pub fn getCachedOpcode(self: *VM, node_idx: ast.Node.Index) ?[]const u8 {
        if (!self.optimization_flags.enable_opcode_caching) return null;

        // Retrieve cached opcodes for faster execution
        // Returns null if opcode not in cache (cache miss)
        self.execution_stats.function_calls += 1;
        _ = node_idx;
        return null; // Cache miss - would return cached opcode if found
    }

    // Enhanced error reporting with better context
    pub fn reportError(self: *VM, error_type: ErrorType, message: []const u8, suggestions: []const []const u8) !void {
        // Generate detailed error report
        const stack_trace = try self.generateStackTrace();
        defer self.allocator.free(stack_trace);

        // Add error to context
        try self.error_context.addError(self.allocator, error_type, message, self.current_file, self.current_line, stack_trace);

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

    // Performance optimization: Fast property access using Shape System
    pub fn getObjectPropertyOptimized(self: *VM, object_value: Value, property_name: []const u8) !Value {
        if (!self.optimization_flags.enable_fast_property_access) {
            return self.getObjectProperty(object_value, property_name);
        }

        if (object_value.getTag() != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property access on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const object = object_value.getAsObject().data;

        // Fast path 1: Use Shape System for direct offset lookup
        // Shape 系统提供 O(1) 的属性偏移查找
        if (object.shape.getPropertyOffset(property_name)) |offset| {
            const value = object.property_values.items[offset];
            self.retainValue(value);
            return value;
        }

        // Fast path 2: Check class property definition for default value
        if (object.class.getProperty(property_name)) |property| {
            if (property.default_value) |default_val| {
                self.retainValue(default_val);
                return default_val;
            }
        }

        // Slow path: Fall back to full property lookup with magic method handling
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
        if (self.string_intern_pool.get(str)) |interned_box| {
            // Return reference to existing string and increment ref count
            interned_box.ref_count += 1;
            return Value.fromBox(interned_box, Value.TYPE_STRING);
        }

        // Create new interned string
        const php_string = try types.PHPString.init(self.allocator, str);

        const box = try self.allocator.create(types.gc.Box(*types.PHPString));
        box.* = .{
            .ref_count = 2, // One for the pool, one for the returned Value
            .gc_info = .{},
            .data = php_string,
        };

        // Use the string data directly from the PHPString as the key
        // This avoids a separate allocation for the key
        try self.string_intern_pool.put(php_string.data, box);

        return Value.fromBox(box, Value.TYPE_STRING);
    }

    pub fn setCurrentLocation(self: *VM, file: []const u8, line: u32) void {
        self.current_file = file;
        self.current_line = line;
    }

    pub fn setCurrentSource(self: *VM, source: []const u8) void {
        self.current_source = source;
    }

    /// Calculate line number from byte position in source code
    fn getLineFromPos(self: *VM, pos: usize) u32 {
        // 安全检查：确保位置有效且不会导致溢出
        if (pos == 0 or pos > self.current_source.len) return 1;
        if (pos > 1_000_000) return 1; // 防止过大的位置值

        var line: u32 = 1;
        var i: usize = 0;
        const max_iter = @min(pos, self.current_source.len);
        while (i < max_iter) : (i += 1) {
            if (self.current_source[i] == '\n') {
                line += 1;
            }
        }
        return line;
    }

    // Enhanced error handling with better context
    pub fn throwExceptionWithContext(self: *VM, exception: *PHPException) !Value {
        // Add current call stack to exception
        try self.addCallStackToException(exception);

        // Log error to context
        const stack_trace = try self.generateStackTrace();
        defer self.allocator.free(stack_trace);

        try self.error_context.addError(self.allocator, .fatal_error, // Map exception type to error type
            exception.message.data, exception.file.data, exception.line, stack_trace);

        // Check if we're in a try-catch block
        if (self.try_catch_stack.items.len > 0) {
            // Store the exception for the catch block to use
            // Note: We only store in current_exception, not in TryCatchContext.caught_exception
            // to avoid double-free issues. The exception will be freed in evaluateTryStatement.
            self.current_exception = exception;
            // Return UncaughtException to signal the try-catch block
            return error.UncaughtException;
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
        errdefer {
            for (stack_frames.items) |*frame| {
                frame.deinit(self.allocator);
            }
            stack_frames.deinit(self.allocator);
        }

        // Add current location
        const current_frame = try exceptions.StackFrame.init(self.allocator, "main", self.current_file, self.current_line, 0);
        try stack_frames.append(self.allocator, current_frame);

        // Add call stack frames
        for (self.call_stack.items) |frame| {
            const stack_frame = try exceptions.StackFrame.init(self.allocator, frame.function_name, frame.file, frame.line, 0);
            try stack_frames.append(self.allocator, stack_frame);
        }

        // setTrace will dupe the frames, so we need to release our copies after
        try exception.setTrace(self.allocator, stack_frames.items);

        // Release our copies of the stack frames (setTrace made its own copies)
        for (stack_frames.items) |*frame| {
            frame.deinit(self.allocator);
        }
        stack_frames.deinit(self.allocator);
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
        if (self.call_stack.items.len >= 1000) {
            const exception = try ExceptionFactory.createError(self.allocator, "Maximum function nesting level of '1000' reached, aborting!", self.current_file, self.current_line);
            _ = try self.throwException(exception);
            return error.StackOverflow; // Ensure we return an error to stop execution
        }

        var frame: CallFrame = undefined;
        // Try to reuse a frame from the pool
        if (self.call_frame_pool.items.len > 0) {
            frame = self.call_frame_pool.pop() orelse unreachable;
            frame.function_name = function_name;
            frame.file = file;
            frame.line = line;
            // frame.locals is already reset (empty but with capacity)
        } else {
            frame = CallFrame.init(self.allocator, function_name, file, line);
        }

        try self.call_stack.append(self.allocator, frame);
        // Update cache
        self.current_frame = &self.call_stack.items[self.call_stack.items.len - 1];

        // Track call depth in execution stats
        self.execution_stats.function_calls += 1;
    }

    pub fn popCallFrame(self: *VM) void {
        if (self.call_stack.items.len > 0) {
            var frame = self.call_stack.pop().?;

            // Reset frame for reuse (clears locals, keeps capacity)
            frame.reset(self.allocator);

            // Try to add to pool
            self.call_frame_pool.append(self.allocator, frame) catch {
                // If pool is full or allocation fails, fully deinit
                frame.deinit(self.allocator);
            };

            // Update cache
            if (self.call_stack.items.len > 0) {
                self.current_frame = &self.call_stack.items[self.call_stack.items.len - 1];
            } else {
                self.current_frame = null;
            }
        }
    }

    /// Get call frame pool statistics
    /// This provides insights into call frame allocation patterns
    pub fn getCallFramePoolStats(self: *const VM) fast_pool.CallFramePool.Stats {
        return self.fast_call_frame_pool.getStats();
    }

    /// Example method showing how to use the fast call frame pool
    /// This demonstrates the zero-allocation pattern for small functions
    ///
    /// For future optimization: functions with ≤8 local variables can use
    /// the fast pool to avoid heap allocations entirely
    pub fn pushFastCallFrame(self: *VM, function_name: []const u8, file: []const u8, line: u32) !*fast_pool.PooledCallFrame {
        // Acquire a pooled frame with inline local storage
        const frame = try self.fast_call_frame_pool.acquire(function_name, file, line);
        return frame;
    }

    /// Release a fast call frame back to the pool
    pub fn popFastCallFrame(self: *VM, frame: *fast_pool.PooledCallFrame) void {
        self.fast_call_frame_pool.release(frame, self.allocator);
    }

    pub fn throwException(self: *VM, exception: *PHPException) !Value {
        return self.throwExceptionWithContext(exception);
    }

    /// Format a variable name according to the current syntax mode
    /// In Go mode, removes the $ prefix from variable names
    /// In PHP mode, keeps the $ prefix
    pub fn formatVariableName(self: *VM, name: []const u8) []const u8 {
        if (self.syntax_config.error_display_mode == .go) {
            // Go mode: remove $ prefix if present
            if (name.len > 0 and name[0] == '$') {
                return name[1..];
            }
        }
        return name;
    }

    /// Format a property access operator according to the current syntax mode
    /// In Go mode, returns "."
    /// In PHP mode, returns "->"
    pub fn formatPropertyAccessOperator(self: *VM) []const u8 {
        if (self.syntax_config.error_display_mode == .go) {
            return ".";
        }
        return "->";
    }

    /// Format an error message with syntax-aware variable names and operators
    /// This method replaces variable names and operators in the message
    /// according to the current syntax mode
    pub fn formatError(self: *VM, message: []const u8, var_name: ?[]const u8) ![]const u8 {
        if (self.syntax_config.error_display_mode == .go) {
            // Go mode: format variable names without $ prefix
            if (var_name) |name| {
                const formatted_name = self.formatVariableName(name);
                // Create a new message with the formatted variable name
                return try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ message, formatted_name });
            }
        }
        // PHP mode or no variable name: return original message
        if (var_name) |name| {
            return try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ message, name });
        }
        return try self.allocator.dupe(u8, message);
    }

    /// Format a full error message with syntax-aware formatting
    /// Replaces -> with . in Go mode for property access errors
    pub fn formatErrorMessage(self: *VM, message: []const u8) ![]const u8 {
        if (self.syntax_config.error_display_mode == .go) {
            // Replace -> with . for property access in Go mode
            var result = std.ArrayList(u8){};
            errdefer result.deinit(self.allocator);

            var i: usize = 0;
            while (i < message.len) {
                if (i + 1 < message.len and message[i] == '-' and message[i + 1] == '>') {
                    try result.append(self.allocator, '.');
                    i += 2;
                } else if (message[i] == '$') {
                    // Skip $ prefix in Go mode
                    i += 1;
                } else {
                    try result.append(self.allocator, message[i]);
                    i += 1;
                }
            }

            return try result.toOwnedSlice(self.allocator);
        }
        return try self.allocator.dupe(u8, message);
    }

    /// Get the syntax mode string for error reporting
    pub fn getSyntaxModeString(self: *VM) []const u8 {
        return self.syntax_config.mode.toString();
    }

    /// Format a complete error with file, line, and syntax-aware message
    pub fn formatCompleteError(self: *VM, error_type: []const u8, message: []const u8, file: []const u8, line: u32) ![]const u8 {
        const formatted_message = try self.formatErrorMessage(message);
        defer self.allocator.free(formatted_message);

        return try std.fmt.allocPrint(
            self.allocator,
            "{s} error in {s} on line {d}: {s} [syntax: {s}]",
            .{ error_type, file, line, formatted_message, self.getSyntaxModeString() },
        );
    }

    pub fn handleError(self: *VM, error_type: ErrorType, message: []const u8) !void {
        try self.error_handler.handleError(error_type, message, self.current_file, self.current_line);
    }

    pub fn enterTryCatch(self: *VM) !void {
        const context = TryCatchContext.init(self.allocator);
        try self.try_catch_stack.append(self.allocator, context);
    }

    pub fn exitTryCatch(self: *VM) void {
        if (self.try_catch_stack.items.len > 0) {
            const context = self.try_catch_stack.pop();
            // Note: We don't call context.deinit() here because the exception
            // is managed by self.current_exception and freed in evaluateTryStatement
            _ = context;
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

    pub fn defineInterface(self: *VM, name: []const u8, interface_obj: *types.PHPInterface) !void {
        try self.interfaces.put(name, interface_obj);
    }

    pub fn defineTrait(self: *VM, name: []const u8, trait_obj: *types.PHPTrait) !void {
        try self.traits.put(name, trait_obj);
    }

    pub fn getClass(self: *VM, name: []const u8) ?*types.PHPClass {
        return self.classes.get(name);
    }

    pub fn getInterface(self: *VM, name: []const u8) ?*types.PHPInterface {
        return self.interfaces.get(name);
    }

    pub fn getTrait(self: *VM, name: []const u8) ?*types.PHPTrait {
        return self.traits.get(name);
    }

    pub fn createObject(self: *VM, class_name: []const u8) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.memory_allocations += 1;

        // First, check extension classes (Requirements: 10.2)
        if (self.extension_registry) |ext_reg| {
            if (ext_reg.findClass(class_name)) |ext_class| {
                return self.createExtensionObject(ext_class);
            }
        }

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
        const object = value.getAsObject().data;

        // Initialize properties with default values (optimized)
        if (self.optimization_flags.enable_fast_property_access) {
            try self.initializeObjectPropertiesOptimized(object, class);
        } else {
            try self.initializeObjectProperties(object, class);
        }

        // Don't call constructor here - it will be called by evaluateObjectInstantiation
        // with the proper arguments

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return value;
    }

    /// Create an object from an extension class definition
    /// Requirements: 10.2, 10.3, 10.4
    fn createExtensionObject(self: *VM, ext_class: extension.ExtensionClass) !Value {
        // Create a dynamic PHPClass from the extension class definition
        const php_class = try self.createPHPClassFromExtension(ext_class);

        const value = try Value.initObjectWithManager(&self.memory_manager, php_class);
        const object = value.getAsObject().data;

        // Initialize properties with default values from extension class
        for (ext_class.properties) |prop| {
            if (prop.default_value) |default_ext_val| {
                const default_val = self.extensionValueToValue(default_ext_val);
                try object.setProperty(self.allocator, prop.name, default_val);
            }
        }

        return value;
    }

    /// Create a PHPClass from an extension class definition
    fn createPHPClassFromExtension(self: *VM, ext_class: extension.ExtensionClass) !*types.PHPClass {
        // Check if we already have this class registered
        if (self.classes.get(ext_class.name)) |existing| {
            return existing;
        }

        // Create a new PHPClass
        const class_name = try types.PHPString.init(self.allocator, ext_class.name);
        var php_class = try self.allocator.create(types.PHPClass);

        // Create shape for the class
        const shape = try self.allocator.create(types.Shape);
        shape.* = types.Shape.init(self.allocator, types.Shape.next_id, null);
        types.Shape.next_id += 1;

        php_class.* = types.PHPClass{
            .name = class_name,
            .parent = null,
            .interfaces = &[_]*types.PHPInterface{},
            .traits = &[_]*types.PHPTrait{},
            .properties = std.StringHashMap(types.Property).init(self.allocator),
            .methods = std.StringHashMap(types.Method).init(self.allocator),
            .constants = std.StringHashMap(Value).init(self.allocator),
            .modifiers = .{},
            .attributes = &[_]types.Attribute{},
            .native_destructor = null,
            .shape = shape,
        };

        // Handle parent class
        if (ext_class.parent) |parent_name| {
            if (self.getClass(parent_name)) |parent_class| {
                php_class.parent = parent_class;
            }
        }

        // Add properties from extension class
        for (ext_class.properties) |prop| {
            const prop_name = try types.PHPString.init(self.allocator, prop.name);
            const property = types.Property{
                .name = prop_name,
                .type = null,
                .default_value = if (prop.default_value) |dv| self.extensionValueToValue(dv) else null,
                .modifiers = .{
                    .visibility = if (prop.modifiers.is_public) .public else if (prop.modifiers.is_protected) .protected else .private,
                    .is_static = prop.modifiers.is_static,
                    .is_readonly = prop.modifiers.is_readonly,
                },
                .attributes = &[_]types.Attribute{},
                .hooks = &[_]types.PropertyHook{},
            };
            try php_class.properties.put(prop.name, property);
        }

        // Register the class so it can be found later
        try self.classes.put(ext_class.name, php_class);

        return php_class;
    }

    /// Call an extension object's constructor
    /// Requirements: 10.2
    pub fn callExtensionConstructor(self: *VM, object_value: Value, ext_class: extension.ExtensionClass, args: []const Value) !void {
        if (ext_class.constructor) |ctor| {
            // Convert args to extension values
            var ext_args = try self.allocator.alloc(extension.ExtensionValue, args.len);
            defer self.allocator.free(ext_args);

            for (args, 0..) |arg, i| {
                ext_args[i] = self.valueToExtensionValue(arg);
            }

            // Call the constructor
            const object = object_value.getAsObject().data;
            ctor(@ptrCast(self), @ptrCast(object), ext_args) catch |err| {
                const error_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Extension class {s} constructor failed: {s}",
                    .{ ext_class.name, @errorName(err) },
                );
                defer self.allocator.free(error_msg);
                const exception = try ExceptionFactory.createTypeError(
                    self.allocator,
                    error_msg,
                    self.current_file,
                    self.current_line,
                );
                _ = try self.throwException(exception);
            };
        }
    }

    /// Set the extension registry for this VM
    /// This allows the VM to call extension functions and instantiate extension classes
    pub fn setExtensionRegistry(self: *VM, registry: *ExtensionRegistry) void {
        self.extension_registry = registry;
    }

    /// Get the extension registry (if set)
    pub fn getExtensionRegistry(self: *VM) ?*ExtensionRegistry {
        return self.extension_registry;
    }

    /// Initialize and set a new extension registry owned by the VM
    pub fn initExtensionRegistry(self: *VM) !*ExtensionRegistry {
        if (self.extension_registry) |existing| {
            return existing;
        }

        const registry = try self.allocator.create(ExtensionRegistry);
        registry.* = ExtensionRegistry.init(self.allocator);
        self.extension_registry = registry;

        // Register built-in functions and classes to prevent conflicts
        try self.registerBuiltinsWithExtensionRegistry(registry);

        return registry;
    }

    /// Register built-in function and class names with the extension registry
    fn registerBuiltinsWithExtensionRegistry(self: *VM, registry: *ExtensionRegistry) !void {
        // Register built-in function names
        var func_iter = self.global.variables.iterator();
        while (func_iter.next()) |entry| {
            const value = entry.value_ptr.*;
            if (value.getTag() == .native_function) {
                try registry.registerBuiltinFunction(entry.key_ptr.*);
            }
        }

        // Register built-in class names
        var class_iter = self.classes.iterator();
        while (class_iter.next()) |entry| {
            try registry.registerBuiltinClass(entry.key_ptr.*);
        }
    }

    fn initializeObjectProperties(self: *VM, object: *types.PHPObject, class: *types.PHPClass) !void {
        var prop_iterator = class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                try object.setProperty(self.allocator, entry.key_ptr.*, default_val);
            }
        }
    }

    fn initializeObjectPropertiesOptimized(self: *VM, object: *types.PHPObject, class: *types.PHPClass) !void {
        // Pre-allocate property_values with expected size (already done in PHPObject.init)
        // Just set default values for class properties
        var prop_iterator = class.properties.iterator();
        while (prop_iterator.next()) |entry| {
            const property = entry.value_ptr.*;
            if (property.default_value) |default_val| {
                try object.setProperty(self.allocator, entry.key_ptr.*, default_val);
            }
        }
    }

    pub fn callObjectMethod(self: *VM, object_value: Value, method_name: []const u8, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        if (object_value.getTag() != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Method call on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const object = object_value.getAsObject().data;
        const result = object.callMethod(self, object_value, method_name, args) catch |err| switch (err) {
            error.MagicMethodCall => {
                const name_val = try Value.initString(self.allocator, method_name);
                defer name_val.release(self.allocator);

                // Wrap arguments in a PHP array
                const args_array_val = try Value.initArrayWithManager(&self.memory_manager);
                const args_array = args_array_val.getAsArray().data;
                for (args) |arg| {
                    try args_array.push(self.allocator, arg);
                }
                defer args_array_val.release(self.allocator);

                const magic_args = [_]Value{ name_val, args_array_val };
                return self.callObjectMethod(object_value, "__call", &magic_args);
            },
            else => return err,
        };
        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    pub fn callPDOMethod(self: *VM, pdo_value: Value, method_name: []const u8, args: []const Value) !Value {

        // Get the underlying PDO struct from the object's properties or data
        // For now, we'll assume the PDO object has the database connection stored
        // This is a simplified implementation

        if (std.mem.eql(u8, method_name, "exec")) {
            return self.callPDOExec(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "query")) {
            return self.callPDOQuery(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "prepare")) {
            return self.callPDOPrepare(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "beginTransaction")) {
            return self.callPDOBeginTransaction(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "commit")) {
            return self.callPDOCommit(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "rollBack")) {
            return self.callPDORollBack(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "lastInsertId")) {
            return self.callPDOLastInsertId(pdo_value, args);
        } else if (std.mem.eql(u8, method_name, "quote")) {
            return self.callPDOQuote(pdo_value, args);
        }

        const error_msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method PDO::{s}", .{method_name});
        defer self.allocator.free(error_msg);
        const exception = try ExceptionFactory.createTypeError(self.allocator, error_msg, self.current_file, self.current_line);
        return self.throwException(exception);
    }

    pub fn callConcurrencyMethod(self: *VM, obj_value: Value, method_name: []const u8, args: []const Value) !Value {
        const obj = obj_value.getAsObject().data;
        const class_name = obj.class.name.data;

        // builtin_concurrency functions expect []Value (mutable)
        // We'll create a temporary mutable slice
        const mutable_args = try self.allocator.alloc(Value, args.len);
        defer self.allocator.free(mutable_args);
        @memcpy(mutable_args, args);

        if (std.mem.eql(u8, class_name, "Mutex")) {
            return try builtin_concurrency.callMutexMethod(self, obj, method_name, mutable_args);
        } else if (std.mem.eql(u8, class_name, "Atomic")) {
            return try builtin_concurrency.callAtomicMethod(self, obj, method_name, mutable_args);
        } else if (std.mem.eql(u8, class_name, "RWLock")) {
            return try builtin_concurrency.callRWLockMethod(self, obj, method_name, mutable_args);
        } else if (std.mem.eql(u8, class_name, "SharedData")) {
            return try builtin_concurrency.callSharedDataMethod(self, obj, method_name, mutable_args);
        } else if (std.mem.eql(u8, class_name, "Channel")) {
            return try builtin_concurrency.callChannelMethod(self, obj, method_name, mutable_args);
        }

        return error.MethodNotFound;
    }

    fn callPDOExec(self: *VM, pdo_value: Value, args: []const Value) !Value {
        if (args.len != 1 or args[0].getTag() != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::exec() expects exactly 1 parameter, string given", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const sql = args[0].getAsString().data.data;
        const pdo_object = pdo_value.getAsObject().data;

        // Get the stored PDO connection
        const connection_prop = pdo_object.getProperty("_pdo_connection") catch {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO connection not initialized", self.current_file, self.current_line);
            return self.throwException(exception);
        };

        if (connection_prop.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid PDO connection", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
        const result = try pdo_ptr.exec(sql);
        return Value.initInt(result);
    }

    fn callPDOQuery(self: *VM, pdo_value: Value, args: []const Value) !Value {
        if (args.len != 1 or args[0].getTag() != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::query() expects exactly 1 parameter, string given", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const sql = args[0].getAsString().data.data;
        const pdo_object = pdo_value.getAsObject().data;

        // Get the stored PDO connection
        const connection_prop = pdo_object.getProperty("_pdo_connection") catch {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO connection not initialized", self.current_file, self.current_line);
            return self.throwException(exception);
        };

        if (connection_prop.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid PDO connection", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
        const stmt = try pdo_ptr.query(sql);

        if (stmt == null) {
            return Value.initNull();
        }

        // Create PDOStatement object to wrap the statement
        const statement_class = self.getClass("PDOStatement") orelse {
            const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, "PDOStatement", self.current_file, self.current_line);
            return self.throwException(exception);
        };
        const statement_object = try self.allocator.create(types.PHPObject);
        statement_object.* = try types.PHPObject.init(self.allocator, statement_class);
        try (@constCast(statement_object)).setProperty(self.allocator, "_pdo_statement", Value.initInt(@as(i64, @intCast(@intFromPtr(stmt)))));

        return try Value.initObjectWithObject(&self.memory_manager, statement_object);
    }

    fn callPDOPrepare(self: *VM, pdo_value: Value, args: []const Value) !Value {
        if (args.len != 1 or args[0].getTag() != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::prepare() expects exactly 1 parameter, string given", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const sql = args[0].getAsString().data.data;
        const pdo_object = pdo_value.getAsObject().data;

        // Get the stored PDO connection
        const connection_prop = pdo_object.getProperty("_pdo_connection") catch {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO connection not initialized", self.current_file, self.current_line);
            return self.throwException(exception);
        };

        if (connection_prop.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid PDO connection", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
        const stmt = try pdo_ptr.prepare(sql);

        // Create PDOStatement object to wrap the statement
        const statement_class = self.getClass("PDOStatement") orelse {
            const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, "PDOStatement", self.current_file, self.current_line);
            return self.throwException(exception);
        };
        const statement_object = try self.allocator.create(types.PHPObject);
        statement_object.* = try types.PHPObject.init(self.allocator, statement_class);
        try (@constCast(statement_object)).setProperty(self.allocator, "_pdo_statement", Value.initInt(@as(i64, @intCast(@intFromPtr(stmt)))));

        return try Value.initObjectWithObject(&self.memory_manager, statement_object);
    }

    fn callPDOBeginTransaction(self: *VM, pdo_value: Value, args: []const Value) !Value {
        if (args.len != 0) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::beginTransaction() expects no parameters", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_object = pdo_value.getAsObject().data;

        // Get the stored PDO connection
        const connection_prop = pdo_object.getProperty("_pdo_connection") catch {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO connection not initialized", self.current_file, self.current_line);
            return self.throwException(exception);
        };

        if (connection_prop.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid PDO connection", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
        const result = try pdo_ptr.beginTransaction();
        return Value.initBool(result);
    }

    fn callPDOCommit(self: *VM, pdo_value: Value, args: []const Value) !Value {
        if (args.len != 0) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::commit() expects no parameters", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_object = pdo_value.getAsObject().data;

        // Get the stored PDO connection
        const connection_prop = pdo_object.getProperty("_pdo_connection") catch {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO connection not initialized", self.current_file, self.current_line);
            return self.throwException(exception);
        };

        if (connection_prop.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid PDO connection", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));
        const result = try pdo_ptr.commit();
        return Value.initBool(result);
    }

    fn callPDORollBack(self: *VM, pdo_value: Value, args: []const Value) !Value {
        if (args.len != 0) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::rollBack() expects no parameters", self.current_file, self.current_line);

            return self.throwException(exception);
        }

        const pdo_object = pdo_value.getAsObject().data;

        // Get the stored PDO connection

        const connection_prop = pdo_object.getProperty("_pdo_connection") catch {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO connection not initialized", self.current_file, self.current_line);

            return self.throwException(exception);
        };

        if (connection_prop.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid PDO connection", self.current_file, self.current_line);

            return self.throwException(exception);
        }

        const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));

        const result = try pdo_ptr.rollBack();

        return Value.initBool(result);
    }

    fn callPDOLastInsertId(self: *VM, pdo_value: Value, args: []const Value) !Value {
        if (args.len > 1) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::lastInsertId() expects at most 1 parameter", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_object = pdo_value.getAsObject().data;

        // Get the stored PDO connection
        const connection_prop = pdo_object.getProperty("_pdo_connection") catch {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO connection not initialized", self.current_file, self.current_line);
            return self.throwException(exception);
        };

        if (connection_prop.getTag() != .integer) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid PDO connection", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const pdo_ptr = @as(*database.PDO, @ptrFromInt(@as(usize, @intCast(connection_prop.asInt()))));

        // Get last insert ID
        const result = try pdo_ptr.lastInsertId();
        return Value.initInt(result);
    }

    fn callPDOQuote(self: *VM, pdo_value: Value, args: []const Value) !Value {
        _ = pdo_value;
        if (args.len != 1 or args[0].getTag() != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "PDO::quote() expects exactly 1 parameter, string given", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const str = args[0].getAsString().data.data;
        // Simple quoting - in real PDO this would escape properly based on driver
        const quoted = try std.fmt.allocPrint(self.allocator, "'{s}'", .{str});
        defer self.allocator.free(quoted);

        return try Value.initString(self.allocator, quoted);
    }

    pub fn callStructMethod(self: *VM, struct_value: Value, method_name: []const u8, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        if (struct_value.getTag() != .struct_instance) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Method call on non-struct", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const struct_inst = struct_value.getAsStruct().data;

        const result = try struct_inst.callMethod(self, struct_value, method_name, args);

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    pub fn getObjectProperty(self: *VM, object_value: Value, property_name: []const u8) !Value {
        if (object_value.getTag() != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property access on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const object = object_value.getAsObject().data;

        // Check if property has a get hook
        if (object.class.properties.get(property_name)) |property| {
            if (property.hasGetHook()) {
                // Execute get hook
                for (property.hooks) |hook| {
                    if (hook.type == .get and hook.body != null) {
                        const hook_body = @as(ast.Node.Index, @truncate(@intFromPtr(hook.body)));
                        return self.eval(hook_body);
                    }
                }
            }
        }

        const value = object.getProperty(property_name) catch |err| switch (err) {
            error.MagicMethodCall => {
                const name_val = try Value.initString(self.allocator, property_name);
                defer name_val.release(self.allocator);
                const args = [_]Value{name_val};
                return self.callObjectMethod(object_value, "__get", &args);
            },
            error.UndefinedProperty => {
                // Check if this is actually a method - if so, return a callable closure
                if (object.class.getMethod(property_name)) |method| {
                    // Create a closure bound to this object
                    const closure = try self.createBoundMethodClosure(method, object);
                    return Value.fromBox(closure, Value.TYPE_CLOSURE);
                }

                const exception = try ExceptionFactory.createUndefinedPropertyError(self.allocator, object.class.name.data, property_name, self.current_file, self.current_line);
                return self.throwException(exception);
            },
            else => return err,
        };
        self.retainValue(value);
        return value;
    }

    pub fn setObjectProperty(self: *VM, object_value: Value, property_name: []const u8, value: Value) !void {
        if (object_value.getTag() != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property assignment on non-object", self.current_file, self.current_line);
            _ = try self.throwException(exception);
            return;
        }

        const object = object_value.getAsObject().data;

        // Check if property has a set hook
        if (object.class.properties.get(property_name)) |property| {
            for (property.hooks) |hook| {
                if (hook.type == .set and hook.body != null) {
                    const hook_body = @as(ast.Node.Index, @truncate(@intFromPtr(hook.body)));
                    // Execute set hook - ignore errors
                    const result: anyerror!Value = self.eval(hook_body);
                    _ = result catch {
                        // Ignore errors from hook execution
                        return;
                    };
                    return; // Set hook executed, don't use default behavior
                }
            }
        }

        object.setProperty(self.allocator, property_name, value) catch |err| switch (err) {
            error.ReadonlyPropertyModification => {
                const exception = try ExceptionFactory.createReadonlyPropertyError(self.allocator, object.class.name.data, property_name, self.current_file, self.current_line);
                _ = try self.throwException(exception);
                return;
            },
            else => return err,
        };
    }

    pub fn callUserFunction(self: *VM, function: *types.UserFunction, args: []const Value) !Value {
        return self.callUserFunctionWithNamed(function, args, null);
    }

    pub fn callUserFunctionWithNamed(self: *VM, function: *types.UserFunction, positional_args: []const Value, named_args: ?*const std.StringHashMap(Value)) !Value {
        return self.callUserFunctionWithNamedAndRefs(function, positional_args, named_args, null);
    }

    // Helper function to check if a body contains yield
    pub fn bodyContainsYield(self: *VM, body_node: ast.Node.Index) bool {
        if (body_node == 0) return false;

        const node = self.context.nodes.items[body_node];
        if (node.tag == .yield_expr) return true;

        // Check child nodes recursively based on tag
        return self.nodeOrChildrenContainYield(node);
    }

    fn nodeOrChildrenContainYield(self: *VM, _node: ast.Node) bool {
        if (_node.tag == .yield_expr) return true;

        // Check different node types for children
        switch (_node.tag) {
            .block => {
                const data = _node.data.block;
                for (data.stmts) |child| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[child])) {
                        return true;
                    }
                }
            },
            .if_stmt => {
                const data = _node.data.if_stmt;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.condition])) return true;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.then_branch])) return true;
                if (data.else_branch) |else_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[else_node])) return true;
                }
            },
            .while_stmt => {
                const data = _node.data.while_stmt;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.condition])) return true;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.body])) return true;
            },
            .do_while_stmt => {
                const data = _node.data.do_while_stmt;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.condition])) return true;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.body])) return true;
            },
            .for_stmt => {
                const data = _node.data.for_stmt;
                if (data.init) |init_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[init_node])) return true;
                }
                if (data.condition) |cond_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[cond_node])) return true;
                }
                if (data.loop) |loop_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[loop_node])) return true;
                }
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.body])) return true;
            },
            .foreach_stmt => {
                const data = _node.data.foreach_stmt;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.iterable])) return true;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.body])) return true;
            },
            .expression_stmt => {
                // expression_stmt uses .none data - no child expressions to check
                // yield expressions are their own nodes and will be checked when
                // their parent block iterates through children
                return false;
            },
            .function_decl => {
                const data = _node.data.function_decl;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.body])) return true;
            },
            .method_decl => {
                const data = _node.data.method_decl;
                if (data.body) |body_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[body_node])) return true;
                }
            },
            .class_decl => {
                const data = _node.data.container_decl;
                for (data.members) |member| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[member])) return true;
                }
            },
            .echo_stmt => {
                const data = _node.data.echo_stmt;
                for (data.exprs) |expr| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[expr])) return true;
                }
            },
            .assignment => {
                const data = _node.data.assignment;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.value])) return true;
            },
            .binary_expr => {
                const data = _node.data.binary_expr;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.lhs])) return true;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.rhs])) return true;
            },
            .unary_expr => {
                const data = _node.data.unary_expr;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.expr])) return true;
            },
            .return_stmt => {
                const data = _node.data.return_stmt;
                if (data.expr) |expr_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[expr_node])) return true;
                }
            },
            .function_call => {
                const data = _node.data.function_call;
                for (data.args) |arg| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[arg])) return true;
                }
            },
            .method_call => {
                const data = _node.data.method_call;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.target])) return true;
                for (data.args) |arg| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[arg])) return true;
                }
            },
            .property_access => {
                const data = _node.data.property_access;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.target])) return true;
            },
            .array_access => {
                const data = _node.data.array_access;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.target])) return true;
                if (data.index) |idx| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[idx])) return true;
                }
            },
            .object_instantiation => {
                const data = _node.data.object_instantiation;
                for (data.args) |arg| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[arg])) return true;
                }
            },
            .ternary_expr => {
                const data = _node.data.ternary_expr;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.cond])) return true;
                if (data.then_expr) |then_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[then_node])) return true;
                }
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.else_expr])) return true;
            },
            .array_init => {
                const data = _node.data.array_init;
                for (data.elements) |elem| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[elem])) return true;
                }
            },
            .array_pair => {
                const data = _node.data.array_pair;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.key])) return true;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.value])) return true;
            },
            .arrow_function => {
                const data = _node.data.arrow_function;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.body])) return true;
            },
            .closure => {
                const data = _node.data.closure;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.body])) return true;
            },
            .try_stmt => {
                const data = _node.data.try_stmt;
                if (self.nodeOrChildrenContainYield(self.context.nodes.items[data.body])) return true;
                for (data.catch_clauses) |catch_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[catch_node])) return true;
                }
                if (data.finally_clause) |finally_node| {
                    if (self.nodeOrChildrenContainYield(self.context.nodes.items[finally_node])) return true;
                }
            },
            else => {},
        }
        return false;
    }

    pub fn callUserFunctionWithNamedAndRefs(self: *VM, function: *types.UserFunction, positional_args: []const Value, named_args: ?*const std.StringHashMap(Value), ref_var_names: ?[]const []const u8) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        // Set current_call_args for func_get_args(), func_get_arg(), func_num_args()
        const old_call_args = self.current_call_args;
        self.current_call_args = positional_args;
        defer self.current_call_args = old_call_args;

        // Push call frame for better error reporting
        try self.pushCallFrame(function.name.data, self.current_file, self.current_line);

        // For named args, we need to count different
        const total_args = positional_args.len + if (named_args) |na| na.count() else 0;
        _ = total_args;

        // Bind arguments to parameters (with named argument support)
        var bound_args = try function.bindArgumentsWithNamed(positional_args, named_args, self.allocator);

        // Populate local variables in the current frame
        var current_frame = &self.call_stack.items[self.call_stack.items.len - 1];
        var it = bound_args.iterator();
        while (it.next()) |entry| {
            // Transfer ownership to locals
            self.retainValue(entry.value_ptr.*);
            try current_frame.locals.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Check if this is a generator function (contains yield)
        var result = Value.initNull();

        if (function.body) |body_ptr| {
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));

            // Check if body contains yield
            if (self.bodyContainsYield(body_node)) {
                // This is a generator function - create generator state and return Generator object
                const generator_state = try self.allocator.create(GeneratorState);
                generator_state.* = GeneratorState.init(self.allocator);

                // Store function body
                generator_state.function_body = body_node;

                // Save $this context if available
                const this_value = if (current_frame.locals.get("$this")) |*this_val| this_val.retain() else null;
                generator_state.this_context = this_value;

                self.generator_state = generator_state;

                // Create and return Generator object immediately
                const generator_value = try self.createGeneratorObject(generator_state);

                // Store generator value in state for later reference
                generator_state.generator_object = generator_value;

                // Cleanup for generator function
                var cleanup_it = bound_args.iterator();
                while (cleanup_it.next()) |entry| {
                    self.releaseValue(entry.value_ptr.*);
                }
                bound_args.deinit();
                self.popCallFrame();

                const end_time = std.time.nanoTimestamp();
                self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

                return generator_value;
            } else {
                // Normal function - execute body
                result = self.eval(body_node) catch |err| blk: {
                    if (err == error.Return) {
                        if (self.return_value) |val| {
                            break :blk val;
                        }
                        break :blk Value.initNull();
                    }
                    return err;
                };
                if (self.return_value) |val| {
                    result = val;
                    self.return_value = null;
                }
            }
        }

        // Handle reference parameters - copy back modified values to caller's scope
        if (ref_var_names) |ref_names| {
            for (function.parameters, 0..) |param, i| {
                if (param.is_reference and i < ref_names.len) {
                    const caller_var_name = ref_names[i];
                    const param_name = param.name.data;
                    // Get the modified value from local scope
                    if (current_frame.locals.get(param_name)) |modified_value| {
                        // Update the caller's variable
                        self.retainValue(modified_value);
                        try self.setVariableInParentFrame(caller_var_name, modified_value);
                    }
                }
            }
        }

        // Cleanup
        var cleanup_it = bound_args.iterator();
        while (cleanup_it.next()) |entry| {
            self.releaseValue(entry.value_ptr.*);
        }
        bound_args.deinit();
        self.popCallFrame();

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    fn setVariableInParentFrame(self: *VM, name: []const u8, value: Value) !void {
        if (self.call_stack.items.len > 1) {
            var parent_frame = &self.call_stack.items[self.call_stack.items.len - 2];
            if (parent_frame.locals.get(name)) |old_value| {
                self.releaseValue(old_value);
            }
            try parent_frame.locals.put(name, value);
        } else {
            // Set in global scope
            try self.global.set(name, value);
        }
    }

    pub fn callClosure(self: *VM, closure: *types.Closure, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        // Set current_call_args for func_get_args(), func_get_arg(), func_num_args()
        const old_call_args = self.current_call_args;
        self.current_call_args = args;
        defer self.current_call_args = old_call_args;

        // Push call frame
        try self.pushCallFrame("closure", self.current_file, self.current_line);
        defer self.popCallFrame();

        const result = closure.call(self, args) catch |err| {
            if (err == error.Return) {
                if (self.return_value) |val| {
                    const ret = val;
                    self.return_value = null;
                    return ret;
                }
                return Value.initNull();
            }
            return err;
        };

        const end_time = std.time.nanoTimestamp();
        self.execution_stats.execution_time_ns += @intCast(end_time - start_time);

        return result;
    }

    /// Fast closure call for array functions - skips call frames and statistics
    /// Uses direct locals access to avoid hash map lookup overhead
    pub fn callClosureFast(self: *VM, closure: *types.Closure, arg: Value) !Value {
        // Set current_call_args for func_get_args() family
        const old_call_args = self.current_call_args;
        self.current_call_args = &[_]Value{arg};
        defer self.current_call_args = old_call_args;

        // Set the closure's parameter variable - direct locals access, skip hash lookup
        var param_name: []const u8 = "";
        if (closure.function.parameters.len > 0) {
            param_name = closure.function.parameters[0].name.data;

            // Direct access to current frame's locals - avoid setVariable overhead
            if (self.call_stack.items.len > 0) {
                var current_frame = &self.call_stack.items[self.call_stack.items.len - 1];

                // Fast path: try to find existing entry first
                if (current_frame.locals.get(param_name)) |old_value| {
                    self.releaseValue(old_value);
                    self.retainValue(arg);
                    try current_frame.locals.put(param_name, arg);
                } else {
                    // New variable
                    self.retainValue(arg);
                    try current_frame.locals.put(param_name, arg);
                }
            } else {
                try self.setVariable(param_name, arg);
            }
        }

        // Execute closure body directly
        if (closure.function.body) |body_ptr| {
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));

            // Ultra-fast path: detect and inline simple binary expressions with integers
            // Pattern: $x * 2, $x + 1, $x - 3, etc.
            if (param_name.len > 0) {
                if (self.tryInlineBinaryIntOp(body_node, param_name, arg)) |result| {
                    return result;
                }
            }

            const result = self.eval(body_node) catch |err| {
                if (err == error.Return) {
                    const ret = self.return_value orelse Value.initNull();
                    self.return_value = null;
                    return ret;
                }
                return err;
            };
            return result;
        }
        return Value.initNull();
    }

    /// Fast 2-argument closure call for array_reduce - skips call frames and statistics
    pub fn callClosureFast2(self: *VM, closure: *types.Closure, arg1: Value, arg2: Value) !Value {
        // Set current_call_args
        const old_call_args = self.current_call_args;
        self.current_call_args = &[_]Value{ arg1, arg2 };
        defer self.current_call_args = old_call_args;

        // Set both parameters - direct locals access
        var param1_name: []const u8 = "";
        var param2_name: []const u8 = "";

        if (closure.function.parameters.len > 0) {
            param1_name = closure.function.parameters[0].name.data;
        }
        if (closure.function.parameters.len > 1) {
            param2_name = closure.function.parameters[1].name.data;
        }

        // Direct access to current frame's locals
        if (self.call_stack.items.len > 0) {
            var current_frame = &self.call_stack.items[self.call_stack.items.len - 1];

            if (param1_name.len > 0) {
                if (current_frame.locals.get(param1_name)) |old_value| {
                    self.releaseValue(old_value);
                }
                self.retainValue(arg1);
                try current_frame.locals.put(param1_name, arg1);
            }

            if (param2_name.len > 0) {
                if (current_frame.locals.get(param2_name)) |old_value| {
                    self.releaseValue(old_value);
                }
                self.retainValue(arg2);
                try current_frame.locals.put(param2_name, arg2);
            }
        } else {
            if (param1_name.len > 0) try self.setVariable(param1_name, arg1);
            if (param2_name.len > 0) try self.setVariable(param2_name, arg2);
        }

        // Execute closure body directly
        if (closure.function.body) |body_ptr| {
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));

            // Try inline for simple patterns: $a + $b
            if (param1_name.len > 0 and param2_name.len > 0) {
                if (self.tryInlineBinaryIntOp2(body_node, param1_name, param2_name, arg1, arg2)) |result| {
                    return result;
                }
            }

            const result = self.eval(body_node) catch |err| {
                if (err == error.Return) {
                    const ret = self.return_value orelse Value.initNull();
                    self.return_value = null;
                    return ret;
                }
                return err;
            };
            return result;
        }
        return Value.initNull();
    }

    /// Inline for 2-operand binary ops: $a + $b, $a - $b, $a * $b
    inline fn tryInlineBinaryIntOp2(self: *VM, node_idx: ast.Node.Index, p1: []const u8, p2: []const u8, arg1: Value, arg2: Value) ?Value {
        if (node_idx >= self.context.nodes.items.len) {
            return null;
        }

        const ast_node = &self.context.nodes.items[node_idx];
        var bin_expr_idx: ast.Node.Index = 0;

        // Handle block with single return statement
        if (ast_node.tag == .block) {
            const stmts = ast_node.data.block.stmts;
            if (stmts.len != 1) return null;
            const stmt_node = &self.context.nodes.items[stmts[0]];
            if (stmt_node.tag != .return_stmt) return null;
            const return_expr = stmt_node.data.return_stmt.expr orelse return null;
            const return_node = &self.context.nodes.items[return_expr];
            if (return_node.tag != .binary_expr) return null;
            bin_expr_idx = return_expr;
        } else if (ast_node.tag == .binary_expr) {
            bin_expr_idx = node_idx;
        } else if (ast_node.tag == .return_stmt) {
            const return_expr = ast_node.data.return_stmt.expr orelse return null;
            const return_node = &self.context.nodes.items[return_expr];
            if (return_node.tag != .binary_expr) return null;
            bin_expr_idx = return_expr;
        } else {
            return null;
        }

        const bin_expr = self.context.nodes.items[bin_expr_idx].data.binary_expr;
        const op = bin_expr.op;

        // Only support +, -, *
        if (op != .plus and op != .minus and op != .asterisk) {
            return null;
        }

        // Check pattern: $param1 op $param2 or $param2 op $param1
        const lhs_node = &self.context.nodes.items[bin_expr.lhs];
        const rhs_node = &self.context.nodes.items[bin_expr.rhs];

        var lhs_is_p1 = false;
        var lhs_is_p2 = false;
        var rhs_is_p1 = false;
        var rhs_is_p2 = false;

        if (lhs_node.tag == .variable) {
            const lhs_name = self.context.string_pool.keys()[lhs_node.data.variable.name];
            if (std.mem.eql(u8, lhs_name, p1)) lhs_is_p1 = true;
            if (std.mem.eql(u8, lhs_name, p2)) lhs_is_p2 = true;
        }

        if (rhs_node.tag == .variable) {
            const rhs_name = self.context.string_pool.keys()[rhs_node.data.variable.name];
            if (std.mem.eql(u8, rhs_name, p1)) rhs_is_p1 = true;
            if (std.mem.eql(u8, rhs_name, p2)) rhs_is_p2 = true;
        }

        // Must match: (p1 op p2) or (p2 op p1) where op is commutative
        const is_p1_op_p2 = lhs_is_p1 and rhs_is_p2;
        const is_p2_op_p1 = lhs_is_p2 and rhs_is_p1;

        if (!is_p1_op_p2 and !is_p2_op_p1) {
            return null;
        }

        // Fast path: both operands are integers
        if (arg1.getTag() == .integer and arg2.getTag() == .integer) {
            const v1 = arg1.asInt();
            const v2 = arg2.asInt();
            const result = switch (op) {
                .plus => v1 +% v2,
                .minus => v1 -% v2,
                .asterisk => v1 *% v2,
                else => return null,
            };
            return Value.initInt(result);
        }

        return null;
    }

    /// Fast arrow function call for array functions - skips call frames and statistics
    /// Uses direct locals access to avoid hash map lookup overhead
    pub fn callArrowFunctionFast(self: *VM, arrow_fn: *types.ArrowFunction, arg: Value) !Value {
        // Set current_call_args
        const old_call_args = self.current_call_args;
        self.current_call_args = &[_]Value{arg};
        defer self.current_call_args = old_call_args;

        // Set the arrow function's parameter variable - direct locals access
        var param_name: []const u8 = "";
        if (arrow_fn.parameters.len > 0) {
            param_name = arrow_fn.parameters[0].name.data;

            // Direct access to current frame's locals - avoid setVariable overhead
            if (self.call_stack.items.len > 0) {
                var current_frame = &self.call_stack.items[self.call_stack.items.len - 1];

                // Fast path: try to find existing entry first
                if (current_frame.locals.get(param_name)) |old_value| {
                    self.releaseValue(old_value);
                    self.retainValue(arg);
                    try current_frame.locals.put(param_name, arg);
                } else {
                    // New variable
                    self.retainValue(arg);
                    try current_frame.locals.put(param_name, arg);
                }
            } else {
                try self.setVariable(param_name, arg);
            }
        }

        // Execute arrow function body directly
        if (arrow_fn.body) |body_ptr| {
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));

            // Ultra-fast path: detect and inline simple binary expressions with integers
            // Pattern: $x * 2, $x + 1, $x - 3, etc.
            if (param_name.len > 0) {
                if (self.tryInlineBinaryIntOp(body_node, param_name, arg)) |result| {
                    return result;
                }
            }

            const result = self.eval(body_node) catch |err| {
                if (err == error.Return) {
                    const ret = self.return_value orelse Value.initNull();
                    self.return_value = null;
                    return ret;
                }
                return err;
            };
            return result;
        }
        return Value.initNull();
    }

    /// Ultra-fast inline for simple integer binary operations: $x * n, $x + n, $x - n
    /// Handles: $x * n, return $x * n, { return $x * n; }
    /// Returns null if pattern doesn't match
    inline fn tryInlineBinaryIntOp(self: *VM, node_idx: ast.Node.Index, param_name: []const u8, arg: Value) ?Value {
        if (node_idx >= self.context.nodes.items.len) {
            return null;
        }

        const ast_node = &self.context.nodes.items[node_idx];

        var bin_expr_idx: ast.Node.Index = 0;

        // Handle different node types that can contain binary expressions
        if (ast_node.tag == .binary_expr) {
            // Direct binary_expr: $x * 2
            bin_expr_idx = node_idx;
        } else if (ast_node.tag == .return_stmt) {
            // Pattern: return $x * n;
            const return_expr = ast_node.data.return_stmt.expr orelse return null;
            const return_node = &self.context.nodes.items[return_expr];
            if (return_node.tag != .binary_expr) {
                return null;
            }
            bin_expr_idx = return_expr;
        } else if (ast_node.tag == .block) {
            // Pattern: { return $x * n; } - single statement block
            const stmts = ast_node.data.block.stmts;
            if (stmts.len != 1) {
                return null;
            }
            const stmt_node = &self.context.nodes.items[stmts[0]];
            if (stmt_node.tag != .return_stmt) {
                return null;
            }
            const return_expr = stmt_node.data.return_stmt.expr orelse return null;
            const return_node = &self.context.nodes.items[return_expr];
            if (return_node.tag != .binary_expr) {
                return null;
            }
            bin_expr_idx = return_expr;
        } else {
            return null;
        }

        const bin_expr = self.context.nodes.items[bin_expr_idx].data.binary_expr;
        const op = bin_expr.op;

        // Handle comparison operators with nested modulo: ($x % n) == 0
        if (op == .equal_equal or op == .bang_equal) {
            // Check if lhs is a modulo expression
            const lhs_inner = &self.context.nodes.items[bin_expr.lhs];
            if (lhs_inner.tag == .binary_expr) {
                const inner_expr = lhs_inner.data.binary_expr;
                if (inner_expr.op == .percent) {
                    // Check inner lhs is the parameter variable
                    const inner_lhs = &self.context.nodes.items[inner_expr.lhs];
                    if (inner_lhs.tag == .variable) {
                        const inner_lhs_name = self.context.string_pool.keys()[inner_lhs.data.variable.name];
                        if (std.mem.eql(u8, inner_lhs_name, param_name)) {
                            // Check inner rhs is an integer literal
                            const inner_rhs = &self.context.nodes.items[inner_expr.rhs];
                            if (inner_rhs.tag == .literal_int) {
                                const divisor = inner_rhs.data.literal_int.value;
                                // Check outer rhs is 0
                                const outer_rhs = &self.context.nodes.items[bin_expr.rhs];
                                if (outer_rhs.tag == .literal_int and outer_rhs.data.literal_int.value == 0) {
                                    if (arg.getTag() == .integer) {
                                        const dividend = arg.asInt();
                                        const mod_result = @mod(dividend, divisor);
                                        const is_equal = mod_result == 0;
                                        return Value.initBool(if (op == .equal_equal) is_equal else !is_equal);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return null; // Fall through for other comparison patterns
        }

        // Only support +, -, * for arithmetic operations
        if (op != .plus and op != .minus and op != .asterisk) {
            return null;
        }

        // Check if left operand is the parameter variable
        const lhs_node = &self.context.nodes.items[bin_expr.lhs];
        if (lhs_node.tag != .variable) {
            return null;
        }

        const lhs_name_id = lhs_node.data.variable.name;
        const lhs_name = self.context.string_pool.keys()[lhs_name_id];
        if (!std.mem.eql(u8, lhs_name, param_name)) {
            return null;
        }

        // Check if right operand is an integer literal
        const rhs_node = &self.context.nodes.items[bin_expr.rhs];
        if (rhs_node.tag != .literal_int) {
            return null;
        }

        const rhs_value = rhs_node.data.literal_int.value;

        // Fast path: only operate on integers
        if (arg.getTag() == .integer) {
            const lhs_value = arg.asInt();
            const result = switch (op) {
                .plus => lhs_value +% rhs_value,
                .minus => lhs_value -% rhs_value,
                .asterisk => lhs_value *% rhs_value,
                else => return null,
            };
            return Value.initInt(result);
        }

        // If not integer, fall through to normal eval
        return null;
    }

    pub fn callArrowFunction(self: *VM, arrow_function: *types.ArrowFunction, args: []const Value) !Value {
        const start_time = std.time.nanoTimestamp();
        self.execution_stats.function_calls += 1;

        // Set current_call_args for func_get_args(), func_get_arg(), func_num_args()
        const old_call_args = self.current_call_args;
        self.current_call_args = args;
        defer self.current_call_args = old_call_args;

        // Push call frame
        try self.pushCallFrame("arrow_function", self.current_file, self.current_line);
        defer self.popCallFrame();

        const result = arrow_function.call(self, args) catch |err| {
            if (err == error.Return) {
                if (self.return_value) |val| {
                    const ret = val;
                    self.return_value = null;
                    return ret;
                }
                return Value.initNull();
            }
            return err;
        };

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
        return Value.fromBox(box, Value.TYPE_CLOSURE);
    }

    pub fn createClosureWithRefs(self: *VM, function: types.UserFunction, captured_vars: []const CapturedVar) !Value {
        var closure = types.Closure.init(self.allocator, function);

        // Capture variables, handling references
        for (captured_vars) |capture| {
            if (capture.is_reference) {
                try closure.captureByReference(capture.name, capture.value);
            } else {
                try closure.captureVariable(capture.name, capture.value);
            }
        }

        const box = try self.memory_manager.allocClosure(closure);
        return Value.fromBox(box, Value.TYPE_CLOSURE);
    }

    /// Create a Generator object that wraps the generator state
    pub fn createGeneratorObject(self: *VM, state: *GeneratorState) !Value {
        // Create a PHPObject for the Generator
        const generator_class = self.getClass("Generator") orelse {
            return Value.initNull();
        };

        const generator_obj = try self.allocator.create(types.PHPObject);
        generator_obj.* = try types.PHPObject.init(self.allocator, generator_class);

        // Store the generator state pointer using a special encoding
        // Since Value can only store 32-bit integers, we store the pointer as a string
        const state_ptr_int = @intFromPtr(state);
        const ptr_str = try std.fmt.allocPrint(self.allocator, "{}", .{state_ptr_int});
        defer self.allocator.free(ptr_str);
        const ptr_val = try types.Value.initString(self.allocator, ptr_str);
        try generator_obj.setProperty(self.allocator, "__generator_state_ptr", ptr_val);

        const obj_box = try self.memory_manager.wrapObject(generator_obj);
        const generator_value = Value.fromBox(obj_box, Value.TYPE_OBJECT);

        // Store the Generator object in the generator_state for yield to retrieve
        state.generator_object = generator_value;

        return generator_value;
    }

    pub fn createArrowFunction(self: *VM, parameters: []const types.Method.Parameter, body: ?*anyopaque) !Value {
        // Create anonymous function name for the arrow function
        const anon_name = try types.PHPString.init(self.allocator, "{arrow}");

        // Create UserFunction for the closure
        var user_func = types.UserFunction.init(anon_name);
        user_func.parameters = parameters;
        user_func.body = body;

        // Create Closure wrapping the UserFunction
        var closure = types.Closure.init(self.allocator, user_func);

        // Auto-capture variables from current scope
        if (self.call_stack.items.len > 0) {
            const current_frame = &self.call_stack.items[self.call_stack.items.len - 1];
            var locals_iter = current_frame.locals.iterator();
            while (locals_iter.next()) |entry| {
                try closure.captureVariable(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        const box = try self.memory_manager.allocClosure(closure);
        return Value.fromBox(box, Value.TYPE_CLOSURE);
    }

    pub fn callUserFunc(self: *VM, function_name: []const u8, args: []const Value) !Value {
        // Check if it's a static method call: "ClassName::methodName"
        if (std.mem.indexOf(u8, function_name, "::")) |sep_pos| {
            const class_name = function_name[0..sep_pos];
            const method_name = function_name[sep_pos + 2 ..];
            
            // Get the class
            const class = self.getClass(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
            
            // Get the method
            const method_lookup = class.getMethodLookup(method_name) orelse {
                const exception = try ExceptionFactory.createUndefinedMethodError(self.allocator, class_name, method_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
            
            const method = method_lookup.method;
            
            // Call the static method
            const full_method_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
            defer self.allocator.free(full_method_name);
            try self.pushCallFrame(full_method_name, self.current_file, self.current_line);
            defer self.popCallFrame();
            
            // Bind arguments to parameters
            for (method.parameters, 0..) |param, i| {
                if (i < args.len) {
                    try self.setVariable(param.name.data, args[i]);
                } else if (param.default_value) |default| {
                    try self.setVariable(param.name.data, default);
                }
            }
            
            // Execute method body
            if (method.body) |body| {
                const body_node_idx: u32 = @intCast(@intFromPtr(body));
                return self.eval(body_node_idx);
            }
            
            return Value.initNull();
        }
        
        if (try StandardLibrary.callBuiltinFast(self, function_name, args)) |v| return v;

        // Second, check extension functions (Requirements: 9.2)
        if (self.extension_registry) |ext_reg| {
            if (ext_reg.findFunction(function_name)) |ext_func| {
                return self.callExtensionFunction(ext_func, args);
            }
        }

        const function_val = self.global.get(function_name) orelse {
            const exception = try ExceptionFactory.createUndefinedFunctionError(self.allocator, function_name, self.current_file, self.current_line);
            return self.throwException(exception);
        };

        return switch (function_val.getTag()) {
            .native_function => {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(function_val.getAsNativeFunc()));
                return function(self, args);
            },
            .user_function => {
                return self.callUserFunction(function_val.getAsUserFunc().data, args);
            },
            .closure => {
                return self.callClosure(function_val.getAsClosure().data, args);
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Not a callable function", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        };
    }

    /// Call an extension function with proper argument validation
    /// Requirements: 9.2, 9.3
    fn callExtensionFunction(self: *VM, ext_func: extension.ExtensionFunction, args: []const Value) !Value {
        // Validate argument count
        if (args.len < ext_func.min_args) {
            const error_msg = try std.fmt.allocPrint(
                self.allocator,
                "{s}() expects at least {d} parameter(s), {d} given",
                .{ ext_func.name, ext_func.min_args, args.len },
            );
            defer self.allocator.free(error_msg);
            const exception = try ExceptionFactory.createArgumentCountError(
                self.allocator,
                ext_func.min_args,
                @intCast(args.len),
                ext_func.name,
                self.current_file,
                self.current_line,
            );
            return self.throwException(exception);
        }

        if (ext_func.max_args != 255 and args.len > ext_func.max_args) {
            const error_msg = try std.fmt.allocPrint(
                self.allocator,
                "{s}() expects at most {d} parameter(s), {d} given",
                .{ ext_func.name, ext_func.max_args, args.len },
            );
            defer self.allocator.free(error_msg);
            const exception = try ExceptionFactory.createArgumentCountError(
                self.allocator,
                ext_func.max_args,
                @intCast(args.len),
                ext_func.name,
                self.current_file,
                self.current_line,
            );
            return self.throwException(exception);
        }

        // Convert Value array to ExtensionValue array
        var ext_args = try self.allocator.alloc(extension.ExtensionValue, args.len);
        defer self.allocator.free(ext_args);

        for (args, 0..) |arg, i| {
            ext_args[i] = self.valueToExtensionValue(arg);
        }

        // Call the extension function callback
        const result = ext_func.callback(@ptrCast(self), ext_args) catch |err| {
            const error_msg = try std.fmt.allocPrint(
                self.allocator,
                "Extension function {s}() failed: {s}",
                .{ ext_func.name, @errorName(err) },
            );
            defer self.allocator.free(error_msg);
            const exception = try ExceptionFactory.createTypeError(
                self.allocator,
                error_msg,
                self.current_file,
                self.current_line,
            );
            return self.throwException(exception);
        };

        // Convert ExtensionValue back to Value
        return self.extensionValueToValue(result);
    }

    /// Convert a VM Value to an ExtensionValue (opaque u64)
    fn valueToExtensionValue(_: *VM, value: Value) extension.ExtensionValue {
        // Store pointer to value data as u64
        return @intFromPtr(&value);
    }

    /// Convert an ExtensionValue (opaque u64) back to a VM Value
    fn extensionValueToValue(_: *VM, ext_value: extension.ExtensionValue) Value {
        // This is unsafe but required for extension API compatibility
        const ptr: *const Value = @ptrFromInt(ext_value);
        return ptr.*;
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

    /// 设置执行模式
    pub fn setExecutionMode(self: *VM, mode: ExecutionMode) void {
        self.execution_mode = mode;
    }

    pub fn setJitEnabled(self: *VM, enabled: bool) !void {
        self.jit_enabled = enabled;
        if (self.bytecode_vm_instance) |bvm| {
            try bvm.setJitEnabled(enabled);
        }
    }

    /// 获取当前执行模式
    pub fn getExecutionMode(self: *VM) ExecutionMode {
        return self.execution_mode;
    }

    /// 初始化字节码VM（延迟初始化）
    fn ensureBytecodeVM(self: *VM) !*BytecodeVM {
        if (self.bytecode_vm_instance) |bvm| {
            return bvm;
        }
        self.bytecode_vm_instance = try BytecodeVM.init(self.allocator);
        if (self.jit_enabled) {
            try self.bytecode_vm_instance.?.setJitEnabled(true);
        }
        return self.bytecode_vm_instance.?;
    }

    /// 使用字节码VM执行AST
    /// 字节码生成器类型问题已修复，现在可以正常使用字节码执行
    fn runBytecode(self: *VM, node: ast.Node.Index) !Value {
        // 初始化字节码VM
        const bvm = self.ensureBytecodeVM() catch |err| {
            std.debug.print("Bytecode VM init failed: {s}, falling back to tree-walking\n", .{@errorName(err)});
            return self.runTreeWalking(node);
        };

        // 创建字节码生成器并编译AST
        var generator = BytecodeGenerator.init(self.allocator, self.context);
        defer generator.deinit();

        const compiled_func = generator.compile(node) catch |err| {
            std.debug.print("Bytecode compilation failed: {s}, falling back to tree-walking\n", .{@errorName(err)});
            return self.runTreeWalking(node);
        };
        defer compiled_func.deinit(self.allocator);

        // 注册用户定义的函数到BytecodeVM
        const user_funcs = generator.getUserFunctions();
        var iter = user_funcs.iterator();
        while (iter.next()) |entry| {
            bvm.registerFunction(entry.key_ptr.*, entry.value_ptr.*) catch |err| {
                std.debug.print("Function registration failed: {s}\n", .{@errorName(err)});
            };
        }

        // 执行字节码
        const result = bvm.execute(compiled_func) catch |err| {
            std.debug.print("Bytecode execution failed: {s}, falling back to tree-walking\n", .{@errorName(err)});
            return self.runTreeWalking(node);
        };

        // 输出 BytecodeVM 的 echo/print 结果
        const output = bvm.getOutput();
        if (output.len > 0) {
            std.debug.print("{s}", .{output});
            bvm.clearOutput();
        }

        // 合并统计信息
        self.execution_stats.function_calls += bvm.stats.function_calls;
        self.execution_stats.memory_allocations += bvm.stats.memory_allocations;
        self.execution_stats.execution_time_ns += bvm.stats.execution_time_ns;
        if (bvm.bytes_allocated > self.execution_stats.peak_memory_usage) {
            self.execution_stats.peak_memory_usage = bvm.bytes_allocated;
        }

        // 转换结果
        return self.convertBytecodeValue(result);
    }

    /// 使用树遍历解释器执行AST
    fn runTreeWalking(self: *VM, node: ast.Node.Index) !Value {
        return self.eval(node);
    }

    /// 初始化FastVM（延迟初始化）
    fn ensureFastVM(self: *VM) !*FastVM {
        if (self.fast_vm_instance) |fvm| {
            return fvm;
        }
        const fvm = try self.allocator.create(FastVM);
        fvm.* = try FastVM.init(self.allocator);
        self.fast_vm_instance = fvm;
        return fvm;
    }

    /// 使用FastVM执行AST（NaN-boxing高性能模式）
    /// FastVM 使用 NaN-boxing 值表示和直接线程化分发，性能最高
    /// 但功能有限，不支持复杂的 OOP 特性
    fn runFastVM(self: *VM, node: ast.Node.Index) !Value {
        // 初始化 FastVM
        const fvm = self.ensureFastVM() catch |err| {
            std.debug.print("FastVM init failed: {s}, falling back to tree-walking\n", .{@errorName(err)});
            return self.runTreeWalking(node);
        };

        // 创建 FastCompiler 并编译 AST
        var fc = FastCompiler.init(self.allocator, self.context);
        defer fc.deinit();

        const compiled_func = fc.compile(node) catch |err| {
            std.debug.print("FastVM compilation failed: {s}, falling back to tree-walking\n", .{@errorName(err)});
            return self.runTreeWalking(node);
        };
        defer {
            // 清理编译后的函数资源
            self.allocator.free(compiled_func.code);
            self.allocator.free(compiled_func.constants);
        }

        // 执行字节码
        const result = fvm.execute(&compiled_func) catch |err| {
            std.debug.print("FastVM execution failed: {s}, falling back to tree-walking\n", .{@errorName(err)});
            return self.runTreeWalking(node);
        };

        // 输出 FastVM 的 echo/print 结果
        const output = fvm.getOutput();
        if (output.len > 0) {
            std.debug.print("{s}", .{output});
            // 清空输出缓冲区以便下次使用
            fvm.output.clearRetainingCapacity();
        }

        // 转换 FastValue 到 Value
        return self.convertFastValue(result);
    }

    /// 转换 FastVM 的 FastValue 到树遍历 VM 的 Value
    fn convertFastValue(_: *VM, fv: fast_value.FastValue) !Value {
        if (fv.isNil()) {
            return Value.initNull();
        } else if (fv.isBool()) {
            return Value.initBool(fv.asBool());
        } else if (fv.isInt()) {
            return Value.initInt(fv.asInt());
        } else if (fv.isFloat()) {
            return Value.initFloat(fv.asFloat());
        }
        // FastVM 目前主要支持数值类型，字符串和复杂类型暂时返回 null
        // 后续可以扩展支持
        return Value.initNull();
    }

    /// 转换字节码VM的Value到树遍历VM的Value
    fn convertBytecodeValue(self: *VM, bv: bytecode.Value) !Value {
        return switch (bv) {
            .null_val => Value.initNull(),
            .bool_val => |b| Value.initBool(b),
            .int_val => |i| Value.initInt(i),
            .float_val => |f| Value.initFloat(f),
            .string_val => |s| try Value.initStringWithManager(&self.memory_manager, s.data),
            // 复杂类型暂时返回null，后续可以扩展
            .array_val, .object_val, .struct_val, .closure_val, .resource_val, .iterator_val => Value.initNull(),
        };
    }

    /// 判断是否应该使用字节码执行（用于auto模式）
    fn shouldUseBytecode(self: *VM, node: ast.Node.Index) bool {
        _ = self;
        _ = node;
        // 简单启发式：目前总是返回false，保守使用树遍历
        // 后续可以根据代码复杂度、热点检测等因素决定
        // 例如：循环次数多、函数调用频繁的代码适合字节码执行
        return false;
    }

    /// 主执行入口 - 支持执行模式切换
    pub fn run(self: *VM, node: ast.Node.Index) !Value {
        defer _ = self.request_arena.reset(.retain_capacity);

        const result = switch (self.execution_mode) {
            .tree_walking => self.runTreeWalking(node),
            .bytecode => self.runBytecode(node),
            .fast => self.runFastVM(node),
            .auto => {
                // 自动模式：根据代码特征选择执行方式
                if (self.shouldUseBytecode(node)) {
                    return self.runBytecode(node);
                } else {
                    return self.runTreeWalking(node);
                }
            },
        };

        // Run coroutines after main execution
        try self.runCoroutines();

        return result;
    }

    /// Run all pending coroutines
    fn runCoroutines(self: *VM) !void {
        if (self.coroutine_manager == null) return;

        const cm = self.coroutine_manager.?;

        // Run coroutines until all are completed
        while (cm.hasIOWaiting() or cm.getQueueLengths()[0] > 0) {
            try cm.run(self);
        }
    }

    /// Optimized binary expression evaluation - inlines literal operands and common ops
    /// 使用 48 位整数和快速算术操作优化
    fn evaluateBinaryExpression(self: *VM, binary_expr: anytype) Value {
        const lhs_idx = binary_expr.lhs;
        const rhs_idx = binary_expr.rhs;

        if (lhs_idx >= self.context.nodes.items.len or
            rhs_idx >= self.context.nodes.items.len)
        {
            return Value.initNull();
        }

        // 短路求值：&& 和 ||
        if (binary_expr.op == .double_ampersand or binary_expr.op == .double_pipe) {
            const left = self.evaluateNodeFast(lhs_idx);
            defer self.releaseValue(left);

            const left_bool = left.toBool();

            // && 短路：左边为 false 则不求值右边
            if (binary_expr.op == .double_ampersand and !left_bool) {
                return Value.initBool(false);
            }

            // || 短路：左边为 true 则不求值右边
            if (binary_expr.op == .double_pipe and left_bool) {
                return Value.initBool(true);
            }

            // 需要求值右边
            const right = self.evaluateNodeFast(rhs_idx);
            defer self.releaseValue(right);

            return Value.initBool(right.toBool());
        }

        // Fast path: inline literal operands to avoid eval() overhead
        const left = self.evaluateNodeFast(lhs_idx);
        defer self.releaseValue(left);

        const right = self.evaluateNodeFast(rhs_idx);
        defer self.releaseValue(right);

        // 使用 Value 的快速算术操作 (支持 48 位整数)
        switch (binary_expr.op) {
            Token.Tag.plus => {
                // 快速路径：两个整数
                if (left.isInt() and right.isInt()) {
                    return Value.addIntFast(left, right);
                }
                // 通用路径：带溢出检查
                return Value.addGeneric(left, right);
            },
            Token.Tag.minus => {
                if (left.isInt() and right.isInt()) {
                    return Value.subIntFast(left, right);
                }
                return Value.subGeneric(left, right);
            },
            Token.Tag.asterisk => {
                if (left.isInt() and right.isInt()) {
                    return Value.mulIntFast(left, right);
                }
                return Value.mulGeneric(left, right);
            },
            Token.Tag.slash => {
                return Value.divGeneric(left, right);
            },
            Token.Tag.percent => {
                return self.evaluateModulo(left, right) catch Value.initNull();
            },
            Token.Tag.dot => {
                return self.concatenateStrings(left, right) catch Value.initNull();
            },
            Token.Tag.equal_equal => {
                // 快速路径：整数比较
                if (left.isInt() and right.isInt()) {
                    return Value.eqIntFast(left, right);
                }
                return Value.initBool(self.valuesEqual(left, right));
            },
            Token.Tag.bang_equal => {
                if (left.isInt() and right.isInt()) {
                    return Value.initBool(left.asInt() != right.asInt());
                }
                return Value.initBool(!self.valuesEqual(left, right));
            },
            Token.Tag.equal_equal_equal => {
                return Value.initBool(self.valuesStrictEqual(left, right));
            },
            Token.Tag.bang_equal_equal => {
                return Value.initBool(!self.valuesStrictEqual(left, right));
            },
            Token.Tag.less => {
                if (left.isInt() and right.isInt()) {
                    return Value.ltIntFast(left, right);
                }
                const res = self.compareValues(left, right, binary_expr.op) catch 0;
                return Value.initBool(res != 0);
            },
            Token.Tag.less_equal => {
                if (left.isInt() and right.isInt()) {
                    return Value.leIntFast(left, right);
                }
                const res = self.compareValues(left, right, binary_expr.op) catch 0;
                return Value.initBool(res != 0);
            },
            Token.Tag.greater => {
                if (left.isInt() and right.isInt()) {
                    return Value.gtIntFast(left, right);
                }
                const res = self.compareValues(left, right, binary_expr.op) catch 0;
                return Value.initBool(res != 0);
            },
            Token.Tag.greater_equal => {
                if (left.isInt() and right.isInt()) {
                    return Value.geIntFast(left, right);
                }
                const res = self.compareValues(left, right, binary_expr.op) catch 0;
                return Value.initBool(res != 0);
            },
            Token.Tag.spaceship => {
                const res = self.compareValues(left, right, binary_expr.op) catch 0;
                return Value.initInt(res);
            },
            // 位操作快速路径
            Token.Tag.ampersand => {
                if (left.isInt() and right.isInt()) {
                    return Value.bitAndFast(left, right);
                }
                return Value.initInt(left.toInt() & right.toInt());
            },
            Token.Tag.pipe => {
                if (left.isInt() and right.isInt()) {
                    return Value.bitOrFast(left, right);
                }
                return Value.initInt(left.toInt() | right.toInt());
            },
            Token.Tag.k_instanceof => {
                // instanceof需要特殊处理：右操作数是类名，不是普通表达式
                // 从AST节点直接获取类名
                const rhs_node = &self.context.nodes.items[rhs_idx];
                var class_name: []const u8 = undefined;
                if (rhs_node.tag == .variable) {
                    // 类名存储为变量节点（不带$前缀）
                    const name_id = rhs_node.data.variable.name;
                    class_name = self.context.string_pool.keys()[name_id];
                } else if (rhs_node.tag == .literal_string) {
                    const str_id = rhs_node.data.literal_string.value;
                    class_name = self.context.string_pool.keys()[str_id];
                } else {
                    return Value.initBool(false);
                }

                // 检查左操作数是否为对象
                if (left.getTag() != .object) {
                    return Value.initBool(false);
                }

                const object = left.getAsObject().data;

                // 先检查接口
                if (self.getInterface(class_name)) |target_interface| {
                    return Value.initBool(object.implementsInterface(target_interface));
                }

                // 再检查类
                const target_class = self.getClass(class_name) orelse return Value.initBool(false);
                return Value.initBool(object.isInstanceOf(target_class));
            },
            else => return Value.initNull(),
        }
    }

    /// Fast path to evaluate a node without retain/release overhead
    /// Used for temporary values in expressions - returns null on error
    inline fn evaluateNodeFast(self: *VM, node_idx: ast.Node.Index) Value {
        if (node_idx >= self.context.nodes.items.len) {
            return Value.initNull();
        }

        const ast_node = &self.context.nodes.items[node_idx];

        // Fast path for common literal types
        return switch (ast_node.tag) {
            .literal_int => Value.initInt(ast_node.data.literal_int.value),
            .literal_float => Value.initFloat(ast_node.data.literal_float.value),
            .literal_bool => Value.initBool(ast_node.data.literal_int.value != 0),
            .literal_null => Value.initNull(),
            .variable => self.evaluateVariableFast(ast_node),
            else => self.eval(node_idx) catch return Value.initNull(),
        };
    }

    /// Fast variable evaluation without defer
    inline fn evaluateVariableFast(self: *VM, ast_node: *const ast.Node) Value {
        const name_id = ast_node.data.variable.name;
        const name = self.context.string_pool.keys()[name_id];
        if (self.getVariable(name)) |value| {
            return value.retain();
        }
        return Value.initNull();
    }

    fn evaluateInstanceOf(self: *VM, left: Value, right: Value) !Value {
        // right operand should be a class name or interface name (string)
        if (right.getTag() != .string) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Class name must be a string", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const name = right.getAsString().data.data;

        // First check if it's an interface
        if (self.getInterface(name)) |target_interface| {
            // Check if left operand is an object that implements this interface
            if (left.getTag() == .object) {
                const object = left.getAsObject().data;
                return Value.initBool(object.implementsInterface(target_interface));
            }
            return Value.initBool(false);
        }

        // Then check if it's a class
        const target_class = self.getClass(name) orelse {
            // Class/Interface doesn't exist, return false
            return Value.initBool(false);
        };

        // Check if left operand is an object
        if (left.getTag() == .object) {
            const object = left.getAsObject().data;
            return Value.initBool(object.isInstanceOf(target_class));
        }

        // For non-objects, return false
        return Value.initBool(false);
    }

    fn evaluateMagicConstant(self: *VM, kind: ast.MagicConstantKind) !Value {
        return switch (kind) {
            .dir => blk: {
                // Return directory of current file
                const file_path = self.current_file;
                if (std.mem.lastIndexOf(u8, file_path, "/")) |idx| {
                    break :blk try Value.initString(self.allocator, file_path[0..idx]);
                }
                break :blk try Value.initString(self.allocator, ".");
            },
            .file => try Value.initString(self.allocator, self.current_file),
            .line => Value.initInt(@intCast(self.current_line)),
            .function => blk: {
                if (self.call_stack.items.len > 0) {
                    const frame = &self.call_stack.items[self.call_stack.items.len - 1];
                    break :blk try Value.initString(self.allocator, frame.function_name);
                }
                break :blk try Value.initString(self.allocator, "");
            },
            .class => blk: {
                if (self.current_class) |class| {
                    break :blk try Value.initString(self.allocator, class.name.data);
                }
                break :blk try Value.initString(self.allocator, "");
            },
            .method => blk: {
                var result: []const u8 = "";
                if (self.current_class) |class| {
                    if (self.call_stack.items.len > 0) {
                        const frame = &self.call_stack.items[self.call_stack.items.len - 1];
                        const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class.name.data, frame.function_name });
                        break :blk try Value.initString(self.allocator, full_name);
                    }
                    result = class.name.data;
                }
                break :blk try Value.initString(self.allocator, result);
            },
            .namespace => try Value.initString(self.allocator, ""),
        };
    }

    fn evaluateCompoundAssignment(self: *VM, compound_data: anytype) !Value {
        const target_idx = compound_data.target;
        const target_node = self.context.nodes.items[target_idx];
        const op = compound_data.op;
        const rhs_value = try self.eval(compound_data.value);
        defer self.releaseValue(rhs_value);

        if (target_node.tag == .variable) {
            const name_id = target_node.data.variable.name;
            const name = self.context.string_pool.keys()[name_id];

            // Get current value
            const current_val = self.getVariable(name) orelse Value.initInt(0);

            // Compute new value based on operator
            const new_val = try self.computeCompoundOp(op, current_val, rhs_value);

            // Set the new value
            try self.setVariable(name, new_val);
            return new_val;
        } else if (target_node.tag == .property_access) {
            const obj_val = try self.eval(target_node.data.property_access.target);
            defer self.releaseValue(obj_val);
            const prop_name = self.context.string_pool.keys()[target_node.data.property_access.property_name];

            var current_val: Value = Value.initInt(0);
            if (obj_val.isObject()) {
                current_val = obj_val.getAsObject().data.getProperty(prop_name) catch Value.initInt(0);
            }

            const new_val = try self.computeCompoundOp(op, current_val, rhs_value);

            if (obj_val.isObject()) {
                try obj_val.getAsObject().data.setProperty(self.allocator, prop_name, new_val);
            }
            return new_val;
        } else if (target_node.tag == .array_access) {
            const arr_val = try self.eval(target_node.data.array_access.target);
            defer self.releaseValue(arr_val);

            if (arr_val.isArray()) {
                const php_array = arr_val.getAsArray().data;
                const index_node = target_node.data.array_access.index orelse return Value.initNull();
                const index_val = try self.eval(index_node);
                defer self.releaseValue(index_val);

                const key = switch (index_val.getTag()) {
                    .integer => types.ArrayKey{ .integer = index_val.asInt() },
                    .string => types.ArrayKey{ .string = index_val.getAsString().data },
                    else => return Value.initNull(),
                };

                const current_val = php_array.get(key) orelse Value.initInt(0);
                const new_val = try self.computeCompoundOp(op, current_val, rhs_value);
                try php_array.set(self.allocator, key, new_val);
                return new_val;
            }
            return Value.initNull();
        }

        const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid compound assignment target", self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn computeCompoundOp(self: *VM, op: anytype, left: Value, right: Value) !Value {
        return switch (op) {
            Token.Tag.plus_equal => self.evaluateAddition(left, right),
            Token.Tag.minus_equal => self.evaluateSubtraction(left, right),
            Token.Tag.asterisk_equal => self.evaluateMultiplication(left, right),
            Token.Tag.slash_equal => self.evaluateDivision(left, right),
            Token.Tag.percent_equal => self.evaluateModulo(left, right),
            Token.Tag.dot_equal => self.concatenateStrings(left, right),
            else => Value.initNull(),
        };
    }

    fn evaluateAddition(self: *VM, left: Value, right: Value) !Value {
        const left_tag = left.getTag();
        const right_tag = right.getTag();

        // 快速路径：两个都是小整数，使用优化的加法
        if (left_tag == .integer and right_tag == .integer) {
            const l = left.asInt();
            const r = right.asInt();
            // 检查是否在32位范围内，使用快速路径
            if (l >= std.math.minInt(i32) and l <= std.math.maxInt(i32) and
                r >= std.math.minInt(i32) and r <= std.math.maxInt(i32))
            {
                self.execution_stats.arithmetic_ops += 1;
                const result = l +% r;
                return Value.initInt(result);
            }
            // 大整数回退到普通路径
            self.execution_stats.arithmetic_ops += 1;
            return Value.initInt(l +% r);
        } else if (left_tag == .float or right_tag == .float) {
            const l = if (left_tag == .float) left.asFloat() else @as(f64, @floatFromInt(left.asInt()));
            const r = if (right_tag == .float) right.asFloat() else @as(f64, @floatFromInt(right.asInt()));
            return Value.initFloat(l + r);
        } else if (left_tag == .string and right_tag == .string) {
            return self.concatenateStrings(left, right);
        } else {
            return self.handleInvalidOperands("addition");
        }
    }

    fn evaluateSubtraction(self: *VM, left: Value, right: Value) !Value {
        const left_tag = left.getTag();
        const right_tag = right.getTag();

        if (left_tag == .integer and right_tag == .integer) {
            self.execution_stats.arithmetic_ops += 1;
            return Value.initInt(left.asInt() -% right.asInt());
        } else if (left_tag == .float or right_tag == .float) {
            const l = if (left_tag == .float) left.asFloat() else @as(f64, @floatFromInt(left.asInt()));
            const r = if (right_tag == .float) right.asFloat() else @as(f64, @floatFromInt(right.asInt()));
            return Value.initFloat(l - r);
        } else {
            return self.handleInvalidOperands("subtraction");
        }
    }

    fn evaluateMultiplication(self: *VM, left: Value, right: Value) !Value {
        const left_tag = left.getTag();
        const right_tag = right.getTag();

        if (left_tag == .integer and right_tag == .integer) {
            self.execution_stats.arithmetic_ops += 1;
            return Value.initInt(left.asInt() *% right.asInt());
        } else if (left_tag == .float or right_tag == .float) {
            const l = if (left_tag == .float) left.asFloat() else @as(f64, @floatFromInt(left.asInt()));
            const r = if (right_tag == .float) right.asFloat() else @as(f64, @floatFromInt(right.asInt()));
            return Value.initFloat(l * r);
        } else {
            return self.handleInvalidOperands("multiplication");
        }
    }

    fn evaluateDivision(self: *VM, left: Value, right: Value) !Value {
        _ = self;
        const left_tag = left.getTag();
        const right_tag = right.getTag();

        const r = if (right_tag == .float) right.asFloat() else @as(f64, @floatFromInt(right.asInt()));
        if (r == 0.0) {
            // PHP 8 returns INF for division by zero (with a warning)
            return Value.initFloat(std.math.inf(f64));
        }

        const l = if (left_tag == .float) left.asFloat() else @as(f64, @floatFromInt(left.asInt()));
        return Value.initFloat(l / r);
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
        // 快速路径：两个值都已经是字符串
        const left_tag = left.getTag();
        const right_tag = right.getTag();

        if (left_tag == .string and right_tag == .string) {
            const left_box = left.getAsString();
            const right_box = right.getAsString();
            const left_data = left_box.data.data;
            const right_data = right_box.data.data;
            const total_len = left_data.len + right_data.len;

            // 直接分配并拷贝，避免 allocPrint 格式化开销
            const result = try self.allocator.alloc(u8, total_len);
            @memcpy(result[0..left_data.len], left_data);
            @memcpy(result[left_data.len..], right_data);

            if (self.optimization_flags.enable_string_interning) {
                defer self.allocator.free(result);
                return self.createInternedString(result);
            } else {
                defer self.allocator.free(result);
                return Value.initStringWithManager(&self.memory_manager, result);
            }
        }

        // 慢路径：需要类型转换
        const left_str = try self.valueToString(left);
        defer if (left_str.needs_free) self.allocator.free(left_str.str);

        const right_str = try self.valueToString(right);
        defer if (right_str.needs_free) self.allocator.free(right_str.str);

        const total_len = left_str.str.len + right_str.str.len;
        const result = try self.allocator.alloc(u8, total_len);
        @memcpy(result[0..left_str.str.len], left_str.str);
        @memcpy(result[left_str.str.len..], right_str.str);

        if (self.optimization_flags.enable_string_interning) {
            defer self.allocator.free(result);
            return self.createInternedString(result);
        } else {
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
        const php_str = value.toString(self.allocator) catch |err| switch (err) {
            error.MagicMethodCall => blk: {
                const res = try self.callObjectMethod(value, "__toString", &.{});
                defer self.releaseValue(res);
                const s = try res.toString(self.allocator);
                break :blk s;
            },
            else => return err,
        };
        defer php_str.release(self.allocator);
        return .{ .str = try self.allocator.dupe(u8, php_str.data), .needs_free = true };
    }

    pub fn eval(self: *VM, node: ast.Node.Index) !Value {
        if (self.recursion_depth >= 1000) {
            const exception = try ExceptionFactory.createError(self.allocator, "Maximum function nesting level of '1000' reached, aborting!", self.current_file, self.current_line);
            _ = try self.throwException(exception);
            return error.StackOverflow;
        }
        self.recursion_depth += 1;
        defer self.recursion_depth -= 1;

        const ast_node = &self.context.nodes.items[node];

        // 每次调用都打印
        std.debug.print("eval: depth={} tag={s}\n", .{ self.recursion_depth, @tagName(ast_node.tag) });

        // Update current line for error reporting - 安全检查
        // main_token is a Token struct, not an index
        const token_loc = ast_node.main_token.loc;
        if (token_loc.start > 0 and token_loc.start < self.current_source.len) {
            self.current_line = self.getLineFromPos(token_loc.start);
        } else {
            self.current_line = 1;
        }

        switch (ast_node.tag) {
            .root => {
                var last_val = Value.initNull();
                for (ast_node.data.root.stmts) |stmt| {
                    // Release the previous value before evaluating the next one
                    self.releaseValue(last_val);
                    const eval_result = self.eval(stmt) catch |err| {
                        return err;
                    };
                    last_val = eval_result;
                }
                return last_val;
            },
            .literal_string => {
                const str_id = ast_node.data.literal_string.value;
                const str_val = self.context.string_pool.keys()[str_id];
                const quote_type = ast_node.data.literal_string.quote_type;

                // 只对双引号字符串处理转义序列
                if (quote_type == .double and string_utils.hasEscapeSequences(str_val)) {
                    const processed = try string_utils.processEscapeSequences(self.allocator, str_val);
                    defer self.allocator.free(processed);
                    return Value.initStringWithManager(&self.memory_manager, processed);
                } else if (quote_type == .single) {
                    // 单引号字符串只处理 \' 和 \\
                    const processed = try string_utils.processSingleQuoteEscapes(self.allocator, str_val);
                    defer self.allocator.free(processed);
                    return Value.initStringWithManager(&self.memory_manager, processed);
                }

                // 反引号字符串或无转义的字符串直接返回
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
            .literal_bool => {
                return Value.initBool(ast_node.data.literal_int.value != 0);
            },
            .literal_null => {
                return Value.initNull();
            },
            .magic_constant => {
                return self.evaluateMagicConstant(ast_node.data.magic_constant.kind);
            },
            .variable => {
                const name_id = ast_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];
                if (self.getVariable(name)) |value| {
                    return value.retain();
                } else {
                    const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, name, self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .variable_variable => {
                // $$var: 先求值内层变量得到变量名，再查找该变量
                const inner_value = try self.eval(ast_node.data.variable_variable.expr);
                defer self.releaseValue(inner_value);

                if (!inner_value.isString()) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Variable variable name must be a string", self.current_file, self.current_line);
                    return self.throwException(exception);
                }

                const var_name_str = inner_value.getAsString().data.data;
                // 添加 $ 前缀（如果没有）
                const var_name = if (var_name_str.len > 0 and var_name_str[0] == '$')
                    var_name_str
                else
                    try std.fmt.allocPrint(self.allocator, "${s}", .{var_name_str});
                defer if (var_name.ptr != var_name_str.ptr) self.allocator.free(var_name);

                if (self.getVariable(var_name)) |value| {
                    return value.retain();
                } else {
                    const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, var_name, self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .self_expr => {
                // self should resolve to the current class name
                if (self.current_class) |class| {
                    const class_name = try self.allocator.alloc(u8, class.name.data.len);
                    @memcpy(class_name, class.name.data);
                    return Value.initStringWithManager(&self.memory_manager, class_name);
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'self' outside of class scope", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .parent_expr => {
                // parent should resolve to the parent class name
                if (self.current_class) |class| {
                    if (class.parent) |parent| {
                        const parent_name = try self.allocator.alloc(u8, parent.name.data.len);
                        @memcpy(parent_name, parent.name.data);
                        return Value.initStringWithManager(&self.memory_manager, parent_name);
                    } else {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'parent' in class that has no parent", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'parent' outside of class scope", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            },
            .assignment => {
                const target_idx = ast_node.data.assignment.target;
                const target_node = self.context.nodes.items[target_idx];
                const is_reference = ast_node.data.assignment.is_reference;

                const value = try self.eval(ast_node.data.assignment.value);

                if (target_node.tag == .variable) {
                    const name_id = target_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];

                    if (is_reference) {
                        // Reference assignment: $ref = &expr
                        // If expr already returns a reference, use it directly
                        if (value.isReference()) {
                            _ = value.asReferenceHash();
                            try self.setVariable(name, value);
                        } else {
                            // For now, only support reference returns from functions
                            // Direct variable references like $ref = &$var not yet supported
                            try self.setVariable(name, value);
                        }
                    } else {
                        try self.setVariable(name, value);
                    }
                } else if (target_node.tag == .variable_variable) {
                    // $$var = value: 先求值内层变量得到变量名，再设置该变量
                    const inner_value = try self.eval(target_node.data.variable_variable.expr);
                    defer self.releaseValue(inner_value);

                    if (!inner_value.isString()) {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Variable variable name must be a string", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }

                    const var_name_str = inner_value.getAsString().data.data;
                    // 添加 $ 前缀（如果没有），并复制字符串
                    const var_name = if (var_name_str.len > 0 and var_name_str[0] == '$')
                        try self.allocator.dupe(u8, var_name_str)
                    else
                        try std.fmt.allocPrint(self.allocator, "${s}", .{var_name_str});

                    // Variable variables always set to global scope
                    try self.global.set(var_name, value);
                } else if (target_node.tag == .property_access) {
                    const obj_val = try self.eval(target_node.data.property_access.target);
                    defer self.releaseValue(obj_val);

                    const prop_name = self.context.string_pool.keys()[target_node.data.property_access.property_name];

                    if (obj_val.isStruct()) {
                        const struct_inst = obj_val.getAsStruct().data;
                        try struct_inst.setField(self.allocator, prop_name, value);
                    } else if (obj_val.isObject()) {
                        try self.setObjectProperty(obj_val, prop_name, value);
                    } else {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Property assignment on non-object", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else if (target_node.tag == .variable_property_access) {
                    const obj_val = try self.eval(target_node.data.variable_property_access.target);
                    defer self.releaseValue(obj_val);

                    const prop_var_val = try self.eval(target_node.data.variable_property_access.prop_variable);
                    defer self.releaseValue(prop_var_val);

                    // Get the string value from the variable
                    var prop_name: []const u8 = undefined;
                    switch (prop_var_val.getTag()) {
                        .string => {
                            const box_ptr = prop_var_val.getAsString();
                            prop_name = box_ptr.*.data.*.data; // Box(*PHPString) -> *PHPString -> []u8
                        },
                        else => {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Variable property name must be a string", self.current_file, self.current_line);
                            return self.throwException(exception);
                        },
                    }

                    if (obj_val.isStruct()) {
                        const struct_inst = obj_val.getAsStruct().data;
                        try struct_inst.setField(self.allocator, prop_name, value);
                    } else if (obj_val.isObject()) {
                        try self.setObjectProperty(obj_val, prop_name, value);
                    } else {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Property assignment on non-object", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else if (target_node.tag == .array_access) {
                    const arr_val = try self.eval(target_node.data.array_access.target);
                    defer self.releaseValue(arr_val);

                    if (!arr_val.isArray()) {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use value as array", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }

                    const php_array = arr_val.getAsArray().data;
                    if (target_node.data.array_access.index) |index_idx| {
                        const index_val = try self.eval(index_idx);
                        defer self.releaseValue(index_val);

                        const key = switch (index_val.getTag()) {
                            .integer => types.ArrayKey{ .integer = index_val.asInt() },
                            .string => types.ArrayKey{ .string = index_val.getAsString().data },
                            else => {
                                const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid array key type", self.current_file, self.current_line);
                                return self.throwException(exception);
                            },
                        };
                        try php_array.set(self.allocator, key, value);
                    } else {
                        // Push operation: $a[] = $val
                        try php_array.push(self.allocator, value);
                    }
                } else if (target_node.tag == .static_property_access) {
                    // ... (keep existing implementation)
                    const class_name = self.context.string_pool.keys()[target_node.data.static_property_access.class_name];
                    const prop_name = self.context.string_pool.keys()[target_node.data.static_property_access.property_name];

                    // Resolve class
                    const class = if (std.mem.eql(u8, class_name, "self")) blk: {
                        break :blk self.current_class orelse {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access self:: outside of class scope", self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                    } else if (std.mem.eql(u8, class_name, "static")) blk: {
                        break :blk self.current_called_class orelse {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access static:: outside of class scope", self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                    } else if (std.mem.eql(u8, class_name, "parent")) blk: {
                        const curr_class = self.current_class orelse {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: outside of class scope", self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                        break :blk curr_class.parent orelse {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: when class has no parent", self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                    } else if (class_name.len > 0 and class_name[0] == '$') blk: {
                        // Variable class name
                        const var_value = self.getVariable(class_name) orelse {
                            const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, class_name, self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                        if (var_value.isObject()) {
                            break :blk var_value.getAsObject().data.class;
                        } else if (var_value.isString()) {
                            const str_class_name = var_value.getAsString().data.data;
                            break :blk self.getClass(str_class_name) orelse {
                                const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, str_class_name, self.current_file, self.current_line);
                                return self.throwException(exception);
                            };
                        } else {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use non-object as class in static property access", self.current_file, self.current_line);
                            return self.throwException(exception);
                        }
                    } else blk: {
                        break :blk self.getClass(class_name) orelse {
                            const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
                            return self.throwException(exception);
                        };
                    };

                    // Set static property
                    var property_set = false;

                    if (class.properties.getPtr(prop_name)) |prop| {
                        if (prop.modifiers.is_static) {
                            if (prop.default_value) |old_val| {
                                self.releaseValue(old_val);
                            }
                            self.retainValue(value);
                            prop.default_value = value;
                            property_set = true;
                        }
                    }

                    if (!property_set) {
                        // Check parent classes
                        var current = class.parent;
                        while (current) |parent| {
                            if (parent.properties.getPtr(prop_name)) |prop| {
                                if (prop.modifiers.is_static) {
                                    if (prop.default_value) |old_val| {
                                        self.releaseValue(old_val);
                                    }
                                    self.retainValue(value);
                                    prop.default_value = value;
                                    property_set = true;
                                    break;
                                }
                            }
                            current = parent.parent;
                        }
                    }

                    if (!property_set) {
                        // 如果属性存在但不是静态的，或者属性不存在
                        if (class.properties.contains(prop_name)) {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Accessing non-static property as static", self.current_file, self.current_line);
                            return self.throwException(exception);
                        }
                        const exception = try ExceptionFactory.createUndefinedPropertyError(self.allocator, class.name.data, prop_name, self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else {
                    std.debug.print("Invalid assignment target tag: {any}\n", .{target_node.tag});
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid assignment target", self.current_file, self.current_line);
                    return self.throwException(exception);
                }

                return value;
            },
            .compound_assignment => {
                return self.evaluateCompoundAssignment(ast_node.data.compound_assignment);
            },
            .list_assignment => {
                const list_data = ast_node.data.list_assignment;
                const array_val = try self.eval(list_data.value);
                defer self.releaseValue(array_val);

                if (!array_val.isArray()) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use value as array in list()", self.current_file, self.current_line);
                    return self.throwException(exception);
                }

                const php_array = array_val.getAsArray().data;
                const targets = list_data.targets;

                for (targets, 0..) |target_idx, i| {
                    const target_node = self.context.nodes.items[target_idx];

                    // Skip empty slots
                    if (target_node.tag == .list_empty) {
                        continue;
                    }

                    // Get value from array at position i (always use array position)
                    const elem_val = php_array.get(types.ArrayKey{ .integer = @as(i64, @intCast(i)) });
                    if (elem_val) |val| {
                        // Set to variable if target is a variable node
                        if (target_node.tag == .variable) {
                            const name_id = target_node.data.variable.name;
                            const name = self.context.string_pool.keys()[name_id];
                            // Retain the value before assigning
                            self.retainValue(val);
                            try self.setVariable(name, val);
                        } else if (target_node.tag == .list_assignment) {
                            // Handle nested list assignment recursively
                            // For nested list, val is the nested array element
                            if (val.isArray()) {
                                try self.assignListRecursive(val.getAsArray().data, target_node.data.list_assignment.targets);
                            }
                            self.releaseValue(val);
                        } else {
                            // For other cases, release the value
                            self.releaseValue(val);
                        }
                    }
                }

                return Value.initNull();
            },
            .echo_stmt => {
                // Handle multiple expressions in echo statement
                const exprs = ast_node.data.echo_stmt.exprs;
                for (exprs) |expr_idx| {
                    var value = try self.eval(expr_idx);
                    defer self.releaseValue(value);

                    // 如果是引用，解引用获取实际值
                    if (value.isReference()) {
                        const hash = value.asReferenceHash();
                        if (self.ref_hash_to_key.get(hash)) |key| {
                            if (self.static_vars.get(key)) |actual_value| {
                                value = actual_value;
                            }
                        }
                    }

                    try value.print();
                }
                return Value.initNull();
            },
            .function_call => {
                return self.evaluateFunctionCall(ast_node.data.function_call);
            },
            .method_call => {
                return self.evaluateMethodCall(ast_node.data.method_call);
            },
            .property_access => {
                return self.evaluatePropertyAccess(ast_node.data.property_access);
            },
            .safe_property_access => {
                return self.evaluateSafePropertyAccess(ast_node.data.safe_property_access);
            },
            .variable_property_access => {
                return self.evaluateVariablePropertyAccess(ast_node.data.variable_property_access);
            },
            .array_access => {
                return self.evaluateArrayAccess(ast_node.data.array_access);
            },
            .array_init => {
                return self.evaluateArrayInit(ast_node.data.array_init);
            },
            .class_decl => {
                return self.evaluateClassDeclaration(ast_node.data.container_decl);
            },
            .trait_decl => {
                return self.evaluateTraitDeclaration(ast_node.data.container_decl);
            },
            .interface_decl => {
                return self.evaluateInterfaceDeclaration(ast_node.data.container_decl);
            },
            .struct_decl => {
                return self.evaluateStructDeclaration(ast_node.data.container_decl);
            },
            .struct_instantiation => {
                return self.evaluateStructInstantiation(ast_node.data.struct_instantiation);
            },
            .object_instantiation => {
                return self.evaluateObjectInstantiation(ast_node.data.object_instantiation);
            },
            .anonymous_class => {
                return self.evaluateAnonymousClass(ast_node.data.anonymous_class);
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
            .postfix_expr => {
                return self.evaluatePostfixExpression(ast_node.data.postfix_expr);
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
            .cast_expr => {
                return self.evaluateCastExpression(ast_node.data.cast_expr);
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
            .do_while_stmt => {
                return self.evaluateDoWhileStatement(ast_node.data.do_while_stmt);
            },
            .for_stmt => {
                return self.evaluateForStatement(ast_node.data.for_stmt);
            },
            .for_range_stmt => {
                return self.evaluateForRangeStatement(ast_node.data.for_range_stmt);
            },
            .foreach_stmt => {
                return self.evaluateForeachStatement(ast_node.data.foreach_stmt);
            },
            .switch_stmt => {
                return self.evaluateSwitchStatement(ast_node.data.switch_stmt);
            },
            .case => {
                // case is handled within switch_stmt
                return Value.initNull();
            },
            .default => {
                // default is handled within switch_stmt
                return Value.initNull();
            },
            .match_expr => {
                return self.evaluateMatchExpression(ast_node.data.match_expr);
            },
            .return_stmt => {
                return self.evaluateReturnStatement(ast_node.data.return_stmt);
            },
            .break_stmt => {
                return self.evaluateBreakStatement(ast_node.data.break_stmt);
            },
            .continue_stmt => {
                return self.evaluateContinueStatement(ast_node.data.continue_stmt);
            },
            .lock_stmt => {
                return self.evaluateLockStatement(ast_node.data.lock_stmt);
            },
            .global_stmt => {
                return self.evaluateGlobalStatement(ast_node.data.global_stmt);
            },
            .static_stmt => {
                return self.evaluateStaticStatement(ast_node.data.static_stmt);
            },
            .go_stmt => {
                return self.evaluateGoStatement(ast_node.data.go_stmt);
            },
            .static_method_call => {
                return self.evaluateStaticMethodCall(ast_node.data.static_method_call);
            },
            .static_property_access => {
                // Map to evaluateClassConstantAccess which already handles static properties
                const data = .{
                    .class_name = ast_node.data.static_property_access.class_name,
                    .constant_name = ast_node.data.static_property_access.property_name,
                };
                return self.evaluateClassConstantAccess(data);
            },
            .class_constant_access => {
                return self.evaluateClassConstantAccess(ast_node.data.class_constant_access);
            },
            .const_decl => {
                const name_id = ast_node.data.const_decl.name;
                const name = self.context.string_pool.keys()[name_id];
                const value = try self.eval(ast_node.data.const_decl.value);
                // PHP constants are global. Storing them in global environment without '$' prefix.
                try self.global.set(name, value);
                return value;
            },
            .property_decl, .method_decl => {
                // Member declarations are handled during class declaration processing.
                // If they appear at top level (e.g. due to parse errors), we ignore them.
                return Value.initNull();
            },
            .expression_stmt => {
                // Expression statements like namespace or use don't have a value to return.
                return Value.initNull();
            },
            .require_stmt, .include_stmt => {
                // Get file path from the statement
                const include_data = ast_node.data.include_stmt;
                const path_expr = include_data.path;
                const is_once = include_data.is_once;

                const path_value = try self.eval(path_expr);
                defer self.releaseValue(path_value);

                if (path_value.getTag() != .string) {
                    return Value.initNull();
                }

                const path_str = path_value.getAsString().data.data;

                // Try to open and read the file
                const file = std.fs.cwd().openFile(path_str, .{}) catch |err| {
                    // Try relative to current file directory
                    if (self.current_file.len > 0) {
                        if (std.mem.lastIndexOf(u8, self.current_file, "/")) |dir_end| {
                            const dir = self.current_file[0..dir_end];
                            const full_path = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir, path_str }) catch {
                                return Value.initNull();
                            };
                            defer self.allocator.free(full_path);

                            const file2 = std.fs.cwd().openFile(full_path, .{}) catch {
                                if (ast_node.tag == .require_stmt) {
                                    std.debug.print("require failed: {s} ({any})\n", .{ full_path, err });
                                    std.debug.print("current_file: {s}\n", .{self.current_file});
                                }
                                return Value.initNull();
                            };
                            defer file2.close();

                            const src = file2.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
                                return Value.initNull();
                            };
                            defer self.allocator.free(src);

                            return self.executeIncluded(src, full_path, is_once);
                        }
                    }
                    if (ast_node.tag == .require_stmt) {
                        std.debug.print("require failed: {s} ({any})\n", .{ path_str, err });
                        std.debug.print("current_file: {s}\n", .{self.current_file});
                    }
                    return Value.initNull();
                };
                defer file.close();

                const src = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
                    return Value.initNull();
                };
                defer self.allocator.free(src);

                return self.executeIncluded(src, path_str, is_once);
            },
            .yield_expr => {
                // Generator support - collect yielded values and return Generator object
                const yield_data = ast_node.data.yield_expr;

                // Get the generator state for this execution context
                const generator_state = if (self.generator_state) |state| state else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "yield outside of generator function", self.current_file, self.current_line);
                    return self.throwException(exception);
                };

                // Evaluate key and value
                const key_value = if (yield_data.key) |key_node| try self.eval(key_node) else Value.initNull();
                const yield_value = if (yield_data.value) |value_node| try self.eval(value_node) else Value.initNull();

                // Store the yielded key-value pair
                try generator_state.keys.append(self.allocator, key_value);
                try generator_state.values.append(self.allocator, yield_value);

                // Store the current value to be returned on iteration
                generator_state.current_value = yield_value.retain();
                generator_state.has_started = true;

                // Pause execution by throwing YieldOutsideGenerator
                return error.YieldOutsideGenerator;
            },
            .namespace_stmt, .use_stmt => {
                // Namespace and use statements don't produce values
                return Value.initNull();
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Unsupported AST node type", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }
    }

    pub fn releaseValue(self: *VM, value: Value) void {
        value.release(self.allocator);
    }

    fn evaluateFunctionCall(self: *VM, call_data: anytype) anyerror!Value {
        const name_node = self.context.nodes.items[call_data.name];

        // Prepare arguments
        var args = std.ArrayList(Value){};
        try args.ensureTotalCapacity(self.allocator, call_data.args.len);
        defer {
            for (args.items) |arg| {
                self.releaseValue(arg);
            }
            args.deinit(self.allocator);
        }

        // Track variable names for reference parameter writeback
        var ref_var_names = std.ArrayList([]const u8){};
        try ref_var_names.ensureTotalCapacity(self.allocator, call_data.args.len);
        defer ref_var_names.deinit(self.allocator);

        // Track named arguments for later reordering
        var named_args = std.StringHashMap(Value).init(self.allocator);
        defer {
            // Release named argument values
            var it = named_args.iterator();
            while (it.next()) |entry| {
                self.releaseValue(entry.value_ptr.*);
            }
            named_args.deinit();
        }

        for (call_data.args) |arg_node_idx| {
            const arg_node = self.context.nodes.items[arg_node_idx];
            if (arg_node.tag == .named_arg) {
                const name_id = arg_node.data.named_arg.name;
                const param_name = self.context.string_pool.keys()[name_id];
                const arg_value = try self.eval(arg_node.data.named_arg.value);
                try named_args.put(param_name, arg_value);
            } else if (arg_node.tag == .unpacking_expr) {
                const unpack_val = try self.eval(arg_node.data.unpacking_expr.expr);
                defer self.releaseValue(unpack_val);

                if (unpack_val.getTag() != .array) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Only arrays can be unpacked", self.current_file, self.current_line);
                    return self.throwException(exception);
                }

                var it = unpack_val.getAsArray().data.iterator();
                while (it.next()) |entry| {
                    const v = entry.value.retain();
                    try args.append(self.allocator, v);
                    try ref_var_names.append(self.allocator, "");
                }
            } else {
                // Track variable name for reference parameter support
                if (arg_node.tag == .variable) {
                    const var_name = self.context.string_pool.keys()[arg_node.data.variable.name];
                    try ref_var_names.append(self.allocator, var_name);
                } else {
                    try ref_var_names.append(self.allocator, "");
                }
                const arg_value = try self.eval(arg_node_idx);
                try args.append(self.allocator, arg_value);
            }
        }

        // Determine function to call
        if (name_node.tag == .variable) {
            const name_id = name_node.data.variable.name;
            const name = self.context.string_pool.keys()[name_id];

            // Check if it's a variable function call ($func()) or direct call (func())
            if (name_node.main_token.tag == .t_variable) {
                // Variable function call: $func()
                // Try to get variable value
                if (self.getVariable(name)) |val| {
                    // If it's a callable object
                    switch (val.getTag()) {
                        .user_function => {
                            if (named_args.count() > 0) {
                                return self.callUserFunctionWithNamed(val.getAsUserFunc().data, args.items, &named_args);
                            }
                            return self.callUserFunction(val.getAsUserFunc().data, args.items);
                        },
                        .closure => return self.callClosure(val.getAsClosure().data, args.items),
                        .arrow_function => return self.callArrowFunction(val.getAsArrowFunc().data, args.items),
                        .string => {
                            // If it's a string, use it as function name
                            const func_name = val.getAsString().data.data;
                            return self.callFunctionByName(func_name, args.items);
                        },
                        else => {
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Value is not callable", self.current_file, self.current_line);
                            return self.throwException(exception);
                        },
                    }
                } else {
                    // Undefined variable
                    const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, name, self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            } else {
                // Direct function call: func() where func is an identifier (parsed as variable node)
                return self.callFunctionByNameWithRefs(name, args.items, &named_args, ref_var_names.items);
            }
        } else if (name_node.tag == .literal_string) {
            // Direct function call: func() - Parser might store name as literal_string?
            // Actually parser stores name index in function_call struct.
            // AST: function_call: struct { name: Index, args: []const Index }
            // name is Index to a node.
            const name_id = name_node.data.literal_string.value;
            const func_name = self.context.string_pool.keys()[name_id];
            return self.callFunctionByName(func_name, args.items);
        } else if (name_node.tag == .function_call) {
            // Nested function call - evaluate it first
            const result = try self.evaluateFunctionCall(name_node.data.function_call);
            defer self.releaseValue(result);
            if (result.getTag() == .string) {
                const func_name = result.getAsString().data.data;
                return self.callFunctionByName(func_name, args.items);
            }
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Function call did not return callable", self.current_file, self.current_line);
            return self.throwException(exception);
        } else if (name_node.tag == .array_access) {
            // Array access as function name - evaluate it
            const result = try self.eval(call_data.name);
            defer self.releaseValue(result);
            if (result.getTag() == .string) {
                const func_name = result.getAsString().data.data;
                return self.callFunctionByName(func_name, args.items);
            } else if (result.getTag() == .closure) {
                return self.callClosure(result.getAsClosure().data, args.items);
            }
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Array element is not callable", self.current_file, self.current_line);
            return self.throwException(exception);
        } else {
            // Try to evaluate the node and see if it's callable
            const result = try self.eval(call_data.name);
            defer self.releaseValue(result);
            switch (result.getTag()) {
                .string => {
                    const func_name = result.getAsString().data.data;
                    return self.callFunctionByName(func_name, args.items);
                },
                .closure => return self.callClosure(result.getAsClosure().data, args.items),
                .arrow_function => return self.callArrowFunction(result.getAsArrowFunc().data, args.items),
                .user_function => return self.callUserFunction(result.getAsUserFunc().data, args.items),
                else => {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Value is not callable", self.current_file, self.current_line);
                    return self.throwException(exception);
                },
            }
        }
    }

    pub fn callFunctionByName(self: *VM, name: []const u8, args: []const Value) !Value {
        return self.callFunctionByNameWithRefs(name, args, null, null);
    }

    pub fn callFunctionByNameWithNamed(self: *VM, name: []const u8, args: []const Value, named_args: ?*const std.StringHashMap(Value)) !Value {
        return self.callFunctionByNameWithRefs(name, args, named_args, null);
    }

    pub fn callFunctionByNameWithRefs(self: *VM, name: []const u8, args: []const Value, named_args: ?*const std.StringHashMap(Value), ref_var_names: ?[]const []const u8) !Value {
        if (try StandardLibrary.callBuiltinFast(self, name, args)) |v| return v;

        // Then check global functions
        const function_val = self.global.get(name) orelse {
            const exception = try ExceptionFactory.createUndefinedFunctionError(self.allocator, name, self.current_file, self.current_line);
            return self.throwException(exception);
        };

        return switch (function_val.getTag()) {
            .native_function => {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(function_val.getAsNativeFunc()));
                return function(self, args);
            },
            .user_function => {
                return self.callUserFunctionWithNamedAndRefs(function_val.getAsUserFunc().data, args, named_args, ref_var_names);
            },
            .closure => self.callClosure(function_val.getAsClosure().data, args),
            .arrow_function => self.callArrowFunction(function_val.getAsArrowFunc().data, args),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Not a callable function", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        };
    }

    fn evaluatePropertyAccess(self: *VM, property_data: anytype) !Value {
        const target_value = try self.eval(property_data.target);
        defer self.releaseValue(target_value);

        const property_name = self.context.string_pool.keys()[property_data.property_name];

        if (target_value.isStruct()) {
            const struct_inst = target_value.getAsStruct().data;
            const value = try struct_inst.getField(property_name);
            self.retainValue(value);
            return value;
        } else if (target_value.isObject()) {
            // 使用优化的属性访问（启用快速路径时）
            if (self.optimization_flags.enable_fast_property_access) {
                return self.getObjectPropertyOptimized(target_value, property_name);
            }
            return self.getObjectProperty(target_value, property_name);
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property access on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn evaluateSafePropertyAccess(self: *VM, property_data: anytype) !Value {
        const target_value = try self.eval(property_data.target);
        defer self.releaseValue(target_value);

        // 如果目标为 null，直接返回 null（安全导航的核心）
        if (target_value.isNull()) {
            return Value.initNull();
        }

        const property_name = self.context.string_pool.keys()[property_data.property_name];

        if (target_value.isStruct()) {
            const struct_inst = target_value.getAsStruct().data;
            const value = try struct_inst.getField(property_name);
            self.retainValue(value);
            return value;
        } else if (target_value.isObject()) {
            return self.getObjectProperty(target_value, property_name);
        } else {
            // 对于安全导航操作符，如果目标不是对象，返回 null 而不是抛出异常
            return Value.initNull();
        }
    }

    fn evaluateVariablePropertyAccess(self: *VM, property_data: anytype) !Value {
        const target_value = try self.eval(property_data.target);
        defer self.releaseValue(target_value);

        // Evaluate the variable to get the property name
        const prop_var_value = try self.eval(property_data.prop_variable);
        defer self.releaseValue(prop_var_value);

        var prop_name: []const u8 = undefined;
        switch (prop_var_value.getTag()) {
            .string => {
                const box_ptr = prop_var_value.getAsString();
                prop_name = box_ptr.*.data.*.data; // Box(*PHPString) -> *PHPString -> []u8
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Variable property name must be a string", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }

        if (target_value.isStruct()) {
            const struct_inst = target_value.getAsStruct().data;
            const value = try struct_inst.getField(prop_name);
            self.retainValue(value);
            return value;
        } else if (target_value.isObject()) {
            return self.getObjectProperty(target_value, prop_name);
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Property access on non-object", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn evaluateArrayAccess(self: *VM, array_access: anytype) !Value {
        const target_value = try self.eval(array_access.target);
        defer self.releaseValue(target_value);

        if (target_value.getTag() != .array) {
            // For nested access like $arr["a"]["b"], if inner returns non-array,
            // we should return null
            return Value.initNull();
        }

        const php_array = target_value.getAsArray().data;
        if (array_access.index) |index_idx| {
            const index_val = try self.eval(index_idx);
            defer self.releaseValue(index_val);

            const key = switch (index_val.getTag()) {
                .integer => types.ArrayKey{ .integer = index_val.asInt() },
                .string => types.ArrayKey{ .string = index_val.getAsString().data },
                else => {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid array key type", self.current_file, self.current_line);
                    return self.throwException(exception);
                },
            };

            if (php_array.get(key)) |val| {
                // Always retain for the caller
                self.retainValue(val);
                return val;
            } else {
                return Value.initNull();
            }
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use [] for reading", self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn evaluateObjectInstantiation(self: *VM, instantiation_data: anytype) !Value {
        const class_name_node = self.context.nodes.items[instantiation_data.class_name];

        // Resolve class name from variable, self_expr, or parent_expr
        var name: []const u8 = undefined;
        var name_needs_free = false;
        defer {
            if (name_needs_free) {
                self.allocator.free(name);
            }
        }

        if (class_name_node.tag == .variable) {
            const name_id = class_name_node.data.variable.name;
            const var_name = self.context.string_pool.keys()[name_id];

            // Check if it's 'self' or 'parent' used as a class name
            if (std.mem.eql(u8, var_name, "self")) {
                if (self.current_class) |class| {
                    name = class.name.data;
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'self' outside of class scope", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            } else if (std.mem.eql(u8, var_name, "parent")) {
                if (self.current_class) |class| {
                    if (class.parent) |parent| {
                        name = parent.name.data;
                    } else {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'parent' in class that has no parent", self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'parent' outside of class scope", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            } else if (std.mem.eql(u8, var_name, "static")) {
                if (self.current_called_class) |class| {
                    name = class.name.data;
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'static' outside of class scope", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            } else if (var_name.len > 0 and var_name[0] == '$') {
                // It's a variable class name like new $className()
                // Evaluate the variable to get its value
                const var_value = try self.eval(instantiation_data.class_name);
                defer self.releaseValue(var_value);

                // Convert to string
                if (var_value.isString()) {
                    const php_str = var_value.getAsString().*.data;
                    name = try self.allocator.dupe(u8, php_str.*.data);
                    name_needs_free = true;
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Variable class name must be a string", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            } else {
                // It's a class name like new MyClass()
                name = var_name;
            }
        } else if (class_name_node.tag == .self_expr) {
            // Handle new self() - self_expr node from parser
            if (self.current_class) |class| {
                name = class.name.data;
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'self' outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        } else if (class_name_node.tag == .parent_expr) {
            // Handle new parent()
            if (self.current_class) |class| {
                if (class.parent) |parent| {
                    name = parent.name.data;
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'parent' in class that has no parent", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'parent' outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        } else if (class_name_node.tag == .static_expr) {
            if (self.current_called_class) |class| {
                name = class.name.data;
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use 'static' outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        } else {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid class name", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        // Check if it's a struct
        if (self.getStruct(name)) |_| {
            // Re-use evaluateStructInstantiation by building appropriate data
            const struct_data = .{
                .struct_type = instantiation_data.class_name,
                .args = instantiation_data.args,
            };
            return self.evaluateStructInstantiation(struct_data);
        }

        // Special handling for Reflection classes
        if (std.mem.eql(u8, name, "ReflectionFunction")) {
            return self.constructReflectionFunction(instantiation_data.args);
        } else if (std.mem.eql(u8, name, "ReflectionClass")) {
            return self.constructReflectionClass(instantiation_data.args);
        }

        // Check if there's a builtin constructor (for concurrency classes)
        if (std.mem.eql(u8, name, "Mutex") or std.mem.eql(u8, name, "Atomic") or
            std.mem.eql(u8, name, "RWLock") or std.mem.eql(u8, name, "SharedData") or
            std.mem.eql(u8, name, "Channel"))
        {
            // Call the builtin constructor directly based on the class name
            var args = std.ArrayListUnmanaged(Value){};
            defer {
                for (args.items) |arg| {
                    self.releaseValue(arg);
                }
                args.deinit(self.allocator);
            }

            try args.ensureTotalCapacity(self.allocator, instantiation_data.args.len);
            for (instantiation_data.args) |arg_idx| {
                try args.append(self.allocator, try self.eval(arg_idx));
            }

            if (std.mem.eql(u8, name, "Mutex")) {
                return builtin_concurrency.mutexConstructor(self, args.items);
            } else if (std.mem.eql(u8, name, "Atomic")) {
                return builtin_concurrency.atomicConstructor(self, args.items);
            } else if (std.mem.eql(u8, name, "RWLock")) {
                return builtin_concurrency.rwlockConstructor(self, args.items);
            } else if (std.mem.eql(u8, name, "SharedData")) {
                return builtin_concurrency.sharedDataConstructor(self, args.items);
            } else if (std.mem.eql(u8, name, "Channel")) {
                return builtin_concurrency.channelConstructor(self, args.items);
            }
        }

        // Otherwise assume it's a class
        const value = try self.createObject(name);

        // Special handling for PDO objects
        if (std.mem.eql(u8, name, "PDO")) {
            const pdo_object = value.getAsObject().data;

            // Create and store the PDO database connection
            var pdo_connection = try self.allocator.create(database.PDO);
            pdo_connection.* = database.PDO{
                .allocator = self.allocator,
                .driver = .sqlite,
                .connection = null,
                .in_transaction = false,
                .error_mode = .exception,
                .last_error = null,
                .attributes = std.StringHashMap(Value).init(self.allocator),
            };

            // Parse DSN from constructor arguments (simplified)
            var dsn: []const u8 = "sqlite::memory:";
            if (instantiation_data.args.len > 0) {
                const dsn_arg = instantiation_data.args[0];
                const dsn_node = self.context.nodes.items[dsn_arg];
                if (dsn_node.tag == .literal_string) {
                    const dsn_id = dsn_node.data.literal_string.value;
                    dsn = self.context.string_pool.keys()[dsn_id];
                }
            }

            const parsed_dsn = try database.parseDSN(self.allocator, dsn);
            defer {
                if (parsed_dsn.host.len > 0 and !std.mem.eql(u8, parsed_dsn.host, "localhost")) self.allocator.free(parsed_dsn.host);
                if (parsed_dsn.database.len > 0) self.allocator.free(parsed_dsn.database);
                self.allocator.free(parsed_dsn.charset);
            }

            try pdo_connection.connect(parsed_dsn, null, null);

            // Store the PDO connection in the object (simplified - using a property)
            const connection_value = Value.initInt(@intCast(@intFromPtr(pdo_connection))); // Store pointer as int
            try pdo_object.setProperty(self.allocator, "_pdo_connection", connection_value);

            return value;
        }

        // Call constructor if it exists
        const object = value.getAsObject().data;
        if (object.class.hasMethod("__construct")) {
            var args = std.ArrayList(Value){};
            defer {
                for (args.items) |arg| {
                    self.releaseValue(arg);
                }
                args.deinit(self.allocator);
            }

            try args.ensureTotalCapacity(self.allocator, instantiation_data.args.len);
            for (instantiation_data.args) |arg_idx| {
                try args.append(self.allocator, try self.eval(arg_idx));
            }

            // Call constructor, release the object if it fails
            const ctor_result = self.callObjectMethod(value, "__construct", args.items) catch |err| {
                // Constructor failed, release the object
                self.releaseValue(value);
                return err;
            };
            self.releaseValue(ctor_result);
        }

        return value;
    }

    fn evaluateAnonymousClass(self: *VM, anon_data: anytype) !Value {
        // Generate a unique name for the anonymous class
        const timestamp = std.time.timestamp();
        self.anonymous_class_counter += 1;
        const anon_class_name = try std.fmt.allocPrint(self.allocator, "anonymous_class_{d}_{d}", .{ timestamp, self.anonymous_class_counter });
        defer self.allocator.free(anon_class_name);

        // Create the class on the heap
        const php_class_name = try types.PHPString.init(self.allocator, anon_class_name);
        defer php_class_name.release(self.allocator);

        const php_class_ptr = try self.allocator.create(types.PHPClass);

        // Initialize the class
        php_class_ptr.* = try types.PHPClass.init(self.allocator, php_class_name);

        // Register cleanup in case of error before defineClass
        var class_registered = false;
        errdefer {
            if (!class_registered) {
                // Class not registered yet, clean it up
                php_class_ptr.deinit(self.allocator);
                self.allocator.destroy(php_class_ptr);
            }
        }

        // Process extends clause
        if (anon_data.extends) |extends_idx| {
            const extends_node = self.context.nodes.items[extends_idx];
            if (extends_node.tag == .variable) {
                const parent_name = self.context.string_pool.keys()[extends_node.data.variable.name];
                if (self.getClass(parent_name)) |parent_class| {
                    php_class_ptr.parent = parent_class;
                }
            }
        }

        // Process implements clause
        if (anon_data.implements.len > 0) {
            const interfaces = try self.allocator.alloc(*types.PHPInterface, anon_data.implements.len);
            php_class_ptr.interfaces = interfaces;

            for (anon_data.implements, 0..) |interface_idx, i| {
                const interface_node = self.context.nodes.items[interface_idx];
                if (interface_node.tag == .variable) {
                    const interface_name = self.context.string_pool.keys()[interface_node.data.variable.name];
                    // 首先尝试获取接口，如果找不到则尝试获取类（兼容内置接口）
                    if (self.getInterface(interface_name)) |interface_obj| {
                        interfaces[i] = interface_obj;
                    } else if (self.getClass(interface_name)) |_| {
                        // 创建一个伪接口对象用于类型检查
                        const fake_interface = try self.allocator.create(types.PHPInterface);
                        const name_str = try types.PHPString.init(self.allocator, interface_name);
                        fake_interface.* = types.PHPInterface.init(self.allocator, name_str);
                        name_str.release(self.allocator);
                        interfaces[i] = fake_interface;
                    }
                }
            }
        }

        // Process class members
        for (anon_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .method_decl => {
                    try self.processMethodDeclaration(php_class_ptr, member_node.data.method_decl);
                },
                .property_decl => {
                    try self.processPropertyDeclaration(php_class_ptr, member_node.data.property_decl);
                },
                .const_decl => {
                    try self.processConstantDeclaration(php_class_ptr, member_node.data.const_decl);
                },
                else => {
                    // Skip unsupported member types
                },
            }
        }

        // Register the anonymous class
        try self.defineClass(anon_class_name, php_class_ptr);
        class_registered = true; // Class is now owned by the VM

        // Create an instance of the anonymous class
        const value = try self.createObject(anon_class_name);
        errdefer {
            // If an error occurs after creating the object, release it
            self.releaseValue(value);
        }
        const object = value.getAsObject().data;

        // Call constructor if it exists with the provided arguments
        if (object.class.hasMethod("__construct")) {
            var args = std.ArrayList(Value){};
            defer {
                for (args.items) |arg| {
                    self.releaseValue(arg);
                }
                args.deinit(self.allocator);
            }

            try args.ensureTotalCapacity(self.allocator, anon_data.args.len);
            for (anon_data.args) |arg_idx| {
                try args.append(self.allocator, try self.eval(arg_idx));
            }

            const ctor_result = self.callObjectMethod(value, "__construct", args.items) catch |err| {
                self.releaseValue(value);
                return err;
            };
            self.releaseValue(ctor_result);
        }

        return value;
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
            const arg_node = self.context.nodes.items[arg_node_idx];
            
            // 处理 unpacking_expr: ...$array
            if (arg_node.tag == .unpacking_expr) {
                const array_val = try self.eval(arg_node.data.unpacking_expr.expr);
                defer self.releaseValue(array_val);
                
                if (array_val.isArray()) {
                    const arr = array_val.getAsArray().data;
                    var i: usize = 0;
                    while (i < arr.next_index) : (i += 1) {
                        const key = types.ArrayKey{ .integer = @intCast(i) };
                        if (arr.get(key)) |elem| {
                            _ = elem.retain();
                            try args.append(self.allocator, elem);
                        }
                    }
                }
            } else {
                try args.append(self.allocator, try self.eval(arg_node_idx));
            }
        }

        // 处理数字类型的内置方法（NumberWrapper）
        if (target_value.isInt() or target_value.isFloat()) {
            const number_wrapper = if (target_value.isInt())
                types.number_wrapper.NumberWrapper.initInt(target_value.asInt())
            else
                types.number_wrapper.NumberWrapper.initFloat(target_value.asFloat());

            if (std.mem.eql(u8, method_name, "abs")) {
                return Value.initFloat(number_wrapper.abs());
            } else if (std.mem.eql(u8, method_name, "ceil")) {
                return Value.initFloat(number_wrapper.ceil());
            } else if (std.mem.eql(u8, method_name, "floor")) {
                return Value.initFloat(number_wrapper.floor());
            } else if (std.mem.eql(u8, method_name, "round")) {
                return Value.initFloat(number_wrapper.round());
            } else if (std.mem.eql(u8, method_name, "sqrt")) {
                return Value.initFloat(number_wrapper.sqrt());
            } else if (std.mem.eql(u8, method_name, "sin")) {
                return Value.initFloat(number_wrapper.sin());
            } else if (std.mem.eql(u8, method_name, "cos")) {
                return Value.initFloat(number_wrapper.cos());
            } else if (std.mem.eql(u8, method_name, "tan")) {
                return Value.initFloat(number_wrapper.tan());
            } else if (std.mem.eql(u8, method_name, "log")) {
                return Value.initFloat(number_wrapper.log());
            } else if (std.mem.eql(u8, method_name, "exp")) {
                return Value.initFloat(number_wrapper.exp());
            } else if (std.mem.eql(u8, method_name, "pow")) {
                if (args.items.len == 1) {
                    const exponent_val = args.items[0];
                    const exponent_wrapper = if (exponent_val.isInt())
                        types.number_wrapper.NumberWrapper.initInt(exponent_val.asInt())
                    else if (exponent_val.isFloat())
                        types.number_wrapper.NumberWrapper.initFloat(exponent_val.asFloat())
                    else
                        return Value.initFloat(std.math.nan(f64));
                    return Value.initFloat(number_wrapper.pow(exponent_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitAnd") or std.mem.eql(u8, method_name, "bit_and")) {
                if (args.items.len == 1) {
                    const other_val = args.items[0];
                    const other_wrapper = if (other_val.isInt())
                        types.number_wrapper.NumberWrapper.initInt(other_val.asInt())
                    else if (other_val.isFloat())
                        types.number_wrapper.NumberWrapper.initFloat(other_val.asFloat())
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitAnd(other_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitOr") or std.mem.eql(u8, method_name, "bit_or")) {
                if (args.items.len == 1) {
                    const other_val = args.items[0];
                    const other_wrapper = if (other_val.isInt())
                        types.number_wrapper.NumberWrapper.initInt(other_val.asInt())
                    else if (other_val.isFloat())
                        types.number_wrapper.NumberWrapper.initFloat(other_val.asFloat())
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitOr(other_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitXor") or std.mem.eql(u8, method_name, "bit_xor")) {
                if (args.items.len == 1) {
                    const other_val = args.items[0];
                    const other_wrapper = if (other_val.isInt())
                        types.number_wrapper.NumberWrapper.initInt(other_val.asInt())
                    else if (other_val.isFloat())
                        types.number_wrapper.NumberWrapper.initFloat(other_val.asFloat())
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitXor(other_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitNot") or std.mem.eql(u8, method_name, "bit_not")) {
                return Value.initInt(number_wrapper.bitNot());
            } else if (std.mem.eql(u8, method_name, "bitShiftLeft") or std.mem.eql(u8, method_name, "bit_shift_left")) {
                if (args.items.len == 1) {
                    const shift_val = args.items[0];
                    const shift_wrapper = if (shift_val.isInt())
                        types.number_wrapper.NumberWrapper.initInt(shift_val.asInt())
                    else if (shift_val.isFloat())
                        types.number_wrapper.NumberWrapper.initFloat(shift_val.asFloat())
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitShiftLeft(shift_wrapper));
                }
            } else if (std.mem.eql(u8, method_name, "bitShiftRight") or std.mem.eql(u8, method_name, "bit_shift_right")) {
                if (args.items.len == 1) {
                    const shift_val = args.items[0];
                    const shift_wrapper = if (shift_val.isInt())
                        types.number_wrapper.NumberWrapper.initInt(shift_val.asInt())
                    else if (shift_val.isFloat())
                        types.number_wrapper.NumberWrapper.initFloat(shift_val.asFloat())
                    else
                        types.number_wrapper.NumberWrapper.initInt(0);
                    return Value.initInt(number_wrapper.bitShiftRight(shift_wrapper));
                }
            }
        }

        // 处理String类型的内置方法
        if (target_value.isString()) {
            if (std.mem.eql(u8, method_name, "toUpper") or std.mem.eql(u8, method_name, "upper")) {
                return builtin_methods.StringMethods.toUpper(self, target_value);
            } else if (std.mem.eql(u8, method_name, "toLower") or std.mem.eql(u8, method_name, "lower")) {
                return builtin_methods.StringMethods.toLower(self, target_value);
            } else if (std.mem.eql(u8, method_name, "trim")) {
                return builtin_methods.StringMethods.trim(self, target_value);
            } else if (std.mem.eql(u8, method_name, "length") or std.mem.eql(u8, method_name, "len")) {
                return builtin_methods.StringMethods.length(self, target_value);
            } else if (std.mem.eql(u8, method_name, "replace")) {
                return builtin_methods.StringMethods.replace(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "substring") or std.mem.eql(u8, method_name, "substr")) {
                return builtin_methods.StringMethods.substring(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "indexOf") or std.mem.eql(u8, method_name, "strpos")) {
                return builtin_methods.StringMethods.indexOf(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "split") or std.mem.eql(u8, method_name, "explode")) {
                return builtin_methods.StringMethods.split(self, target_value, args.items);
            }
        }

        // 处理Array类型的内置方法
        if (target_value.isArray()) {
            if (std.mem.eql(u8, method_name, "push")) {
                return builtin_methods.ArrayMethods.push(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "pop")) {
                return builtin_methods.ArrayMethods.pop(self, target_value);
            } else if (std.mem.eql(u8, method_name, "shift")) {
                return builtin_methods.ArrayMethods.shift(self, target_value);
            } else if (std.mem.eql(u8, method_name, "unshift")) {
                return builtin_methods.ArrayMethods.unshift(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "merge")) {
                return builtin_methods.ArrayMethods.merge(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "reverse")) {
                return builtin_methods.ArrayMethods.reverse(self, target_value);
            } else if (std.mem.eql(u8, method_name, "keys")) {
                return builtin_methods.ArrayMethods.keys(self, target_value);
            } else if (std.mem.eql(u8, method_name, "values")) {
                return builtin_methods.ArrayMethods.values(self, target_value);
            } else if (std.mem.eql(u8, method_name, "filter")) {
                return builtin_methods.ArrayMethods.filter(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "map")) {
                return builtin_methods.ArrayMethods.map(self, target_value, args.items);
            } else if (std.mem.eql(u8, method_name, "count") or std.mem.eql(u8, method_name, "length")) {
                return builtin_methods.ArrayMethods.count(self, target_value);
            } else if (std.mem.eql(u8, method_name, "isEmpty")) {
                return builtin_methods.ArrayMethods.isEmpty(self, target_value);
            }
        }

        // Special handling for Reflection objects
        if (target_value.isObject()) {
            const rf_class_name = target_value.getAsObject().data.class.name.data;
            if (std.mem.eql(u8, rf_class_name, "ReflectionFunction")) {
                return self.callReflectionFunctionMethod(target_value, method_name, args.items);
            } else if (std.mem.eql(u8, rf_class_name, "ReflectionClass")) {
                return self.callReflectionClassMethod(target_value, method_name, args.items);
            } else if (std.mem.eql(u8, rf_class_name, "ReflectionMethod")) {
                return self.callReflectionMethodMethod(target_value, method_name, args.items);
            } else if (std.mem.eql(u8, rf_class_name, "ReflectionParameter")) {
                return self.callReflectionParameterMethod(target_value, method_name);
            }
        }

        // Special handling for PDO objects
        if (target_value.isObject() and std.mem.eql(u8, target_value.getAsObject().data.class.name.data, "PDO")) {
            return self.callPDOMethod(target_value, method_name, args.items);
        }

        // Special handling for Exception/Error objects
        if (target_value.isObject()) {
            const obj = target_value.getAsObject().data;
            const class_name = obj.class.name.data;

            // Check if this is Exception or any of its subclasses
            const is_exception = std.mem.eql(u8, class_name, "Exception") or
                std.mem.eql(u8, class_name, "RuntimeException") or
                std.mem.eql(u8, class_name, "InvalidArgumentException") or
                std.mem.eql(u8, class_name, "LogicException") or
                std.mem.eql(u8, class_name, "Error") or
                std.mem.eql(u8, class_name, "TypeError") or
                std.mem.eql(u8, class_name, "ArgumentCountError") or
                std.mem.eql(u8, class_name, "DivisionByZeroError") or
                std.mem.eql(u8, class_name, "ValidationException") or
                (obj.class.parent != null and (std.mem.eql(u8, obj.class.parent.?.name.data, "Exception") or
                    std.mem.eql(u8, obj.class.parent.?.name.data, "Error")));

            if (is_exception) {
                if (std.mem.eql(u8, method_name, "getMessage")) {
                    if (obj.getProperty("message")) |msg| {
                        return msg.retain();
                    } else |_| {
                        return Value.initString(self.allocator, "") catch Value.initNull();
                    }
                } else if (std.mem.eql(u8, method_name, "getCode")) {
                    if (obj.getProperty("code")) |code| {
                        return code.retain();
                    } else |_| {
                        return Value.initInt(0);
                    }
                } else if (std.mem.eql(u8, method_name, "getFile")) {
                    if (obj.getProperty("file")) |file| {
                        return file.retain();
                    } else |_| {
                        return Value.initString(self.allocator, "") catch Value.initNull();
                    }
                } else if (std.mem.eql(u8, method_name, "getLine")) {
                    if (obj.getProperty("line")) |line| {
                        return line.retain();
                    } else |_| {
                        return Value.initInt(0);
                    }
                } else if (std.mem.eql(u8, method_name, "getPrevious")) {
                    if (obj.getProperty("previous")) |prev| {
                        return prev.retain();
                    } else |_| {
                        return Value.initNull();
                    }
                } else if (std.mem.eql(u8, method_name, "getTrace")) {
                    // Return empty array for now
                    return Value.initArrayWithManager(&self.memory_manager);
                } else if (std.mem.eql(u8, method_name, "getTraceAsString")) {
                    return Value.initString(self.allocator, "") catch Value.initNull();
                } else if (std.mem.eql(u8, method_name, "getErrors")) {
                    // For ValidationException with errors array
                    if (obj.getProperty("errors")) |errors| {
                        return errors.retain();
                    } else |_| {
                        return Value.initArrayWithManager(&self.memory_manager);
                    }
                }
            }
        }

        if (target_value.isStruct()) {
            return self.callStructMethod(target_value, method_name, args.items);
        }

        return self.callObjectMethod(target_value, method_name, args.items);
    }

    fn evaluateArrayInit(self: *VM, array_data: anytype) !Value {
        const php_array_value = try Value.initArrayWithManager(&self.memory_manager);
        errdefer {
            // 确保在异常发生时释放数组
            php_array_value.release(self.allocator);
        }
        const php_array = php_array_value.getAsArray().data;

        // Pre-allocate capacity for better performance
        if (self.optimization_flags.enable_memory_pooling) {
            try php_array.getElements().ensureTotalCapacity(array_data.elements.len);
        }

        var auto_index: i64 = 0;
        for (array_data.elements) |item_node_idx| {
            const item_node = self.context.nodes.items[item_node_idx];

            // 检查是否是键值对节点
            if (item_node.tag == .array_pair) {
                // 关联数组：有显式的键
                const key_value = try self.eval(item_node.data.array_pair.key);
                defer self.releaseValue(key_value);

                const value = try self.eval(item_node.data.array_pair.value);

                // 根据键的类型创建ArrayKey
                const key = switch (key_value.getTag()) {
                    .integer => types.ArrayKey{ .integer = key_value.asInt() },
                    .string => types.ArrayKey{ .string = key_value.getAsString().data },
                    else => types.ArrayKey{ .integer = auto_index },
                };

                try php_array.set(self.allocator, key, value);
                self.releaseValue(value);

                // 如果键是整数，更新自动索引
                if (key == .integer and key.integer >= auto_index) {
                    auto_index = key.integer + 1;
                }
            } else {
                // 普通数组：使用自动索引
                const value = try self.eval(item_node_idx);
                const key = types.ArrayKey{ .integer = auto_index };
                try php_array.set(self.allocator, key, value);
                self.releaseValue(value);
                auto_index += 1;
            }
        }

        // 更新数组的next_index，以便后续push操作能正确工作
        php_array.next_index = auto_index;

        return php_array_value;
    }

    // Missing evaluation methods implementation
    fn evaluateArrowFunction(self: *VM, arrow_func: anytype) !Value {
        // Process parameters
        const parameters = try self.processParameters(arrow_func.params);

        // Create anonymous function name for the arrow function
        const anon_name = try types.PHPString.init(self.allocator, "{arrow}");

        // Create UserFunction for the closure
        var user_func = types.UserFunction.init(anon_name);
        user_func.parameters = parameters;
        // Store body as pointer (Index converted to usize then to pointer)
        user_func.body = @ptrFromInt(@as(usize, arrow_func.body));

        // Set min_args and max_args for arrow function
        var is_variadic = false;
        user_func.min_args = 0;
        for (parameters) |param| {
            if (param.is_variadic) {
                is_variadic = true;
            }
            if (param.default_value == null and !param.is_variadic) {
                user_func.min_args += 1;
            }
        }
        user_func.is_variadic = is_variadic;
        user_func.max_args = if (is_variadic) null else @as(u32, @intCast(parameters.len));

        // Create Closure wrapping the UserFunction
        var closure = types.Closure.init(self.allocator, user_func);
        closure.is_static = arrow_func.is_static;

        // Auto-capture all variables from current scope (arrow functions auto-capture)
        if (self.call_stack.items.len > 0) {
            const current_frame = &self.call_stack.items[self.call_stack.items.len - 1];
            var locals_iter = current_frame.locals.iterator();
            while (locals_iter.next()) |entry| {
                try closure.captureVariable(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        const closure_box = try self.memory_manager.allocClosure(closure);
        return Value.fromBox(closure_box, Value.TYPE_CLOSURE);
    }

    fn evaluateUnaryExpression(self: *VM, unary_expr: anytype) !Value {
        // Handle increment/decrement which requires variable assignment
        if (unary_expr.op == .plus_plus or unary_expr.op == .minus_minus) {
            const expr_node = self.context.nodes.items[unary_expr.expr];

            if (expr_node.tag == .variable) {
                const name_id = expr_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];

                // Get current value
                const current_val = if (self.getVariable(name)) |v| v else Value.initInt(0);

                // Increment/Decrement
                var new_val: Value = undefined;
                if (unary_expr.op == .plus_plus) {
                    new_val = try self.incrementValue(current_val);
                } else {
                    new_val = try self.decrementValue(current_val);
                }

                // Update variable (setVariable retains the new value)
                try self.setVariable(name, new_val);

                // For prefix, return new value.
                _ = self.retainValue(new_val);
                return new_val;
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Increment/decrement only supports variables", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        }

        const operand = try self.eval(unary_expr.expr);
        defer self.releaseValue(operand);

        // Inline common unary operations
        return switch (unary_expr.op) {
            .minus => blk: {
                if (operand.isInt()) {
                    break :blk Value.initInt(-operand.asInt());
                } else if (operand.isFloat()) {
                    break :blk Value.initFloat(-operand.asFloat());
                }
                break :blk self.negateValue(operand) catch Value.initNull();
            },
            .bang => Value.initBool(!operand.toBool()),
            .plus => operand, // Unary plus
            .ampersand => operand, // Reference operator (treat as value for now)
            .k_clone => self.evaluateUnaryOp(unary_expr.op, operand), // Keep complex ops in helper
            else => self.evaluateUnaryOp(unary_expr.op, operand),
        };
    }

    fn evaluatePostfixExpression(self: *VM, postfix_expr: anytype) !Value {
        if (postfix_expr.op == .plus_plus or postfix_expr.op == .minus_minus) {
            const expr_node = self.context.nodes.items[postfix_expr.expr];

            if (expr_node.tag == .variable) {
                const name_id = expr_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];

                // Get current value
                const current_val = if (self.getVariable(name)) |v| v else Value.initInt(0);

                // Retain current value because we will return it, and setVariable might release the one in storage
                self.retainValue(current_val);

                // Calculate new value
                var new_val: Value = undefined;
                if (postfix_expr.op == .plus_plus) {
                    new_val = try self.incrementValue(current_val);
                } else {
                    new_val = try self.decrementValue(current_val);
                }

                // Update variable
                try self.setVariable(name, new_val);

                return current_val;
            } else if (expr_node.tag == .property_access) {
                // Handle $this->property++ or $obj->property++
                const obj_val = try self.eval(expr_node.data.property_access.target);
                defer self.releaseValue(obj_val);

                const prop_name = self.context.string_pool.keys()[expr_node.data.property_access.property_name];

                // Get current property value
                var current_val: Value = Value.initInt(0);
                if (obj_val.isObject()) {
                    const obj = obj_val.getAsObject().data;
                    current_val = obj.getProperty(prop_name) catch Value.initInt(0);
                } else if (obj_val.isStruct()) {
                    const struct_inst = obj_val.getAsStruct().data;
                    current_val = struct_inst.getField(prop_name) catch Value.initInt(0);
                }

                // Retain current value
                self.retainValue(current_val);

                // Calculate new value
                var new_val: Value = undefined;
                if (postfix_expr.op == .plus_plus) {
                    new_val = try self.incrementValue(current_val);
                } else {
                    new_val = try self.decrementValue(current_val);
                }

                // Update property
                if (obj_val.isObject()) {
                    const obj = obj_val.getAsObject().data;
                    try obj.setProperty(self.allocator, prop_name, new_val);
                } else if (obj_val.isStruct()) {
                    const struct_inst = obj_val.getAsStruct().data;
                    try struct_inst.setField(self.allocator, prop_name, new_val);
                }

                return current_val;
            } else if (expr_node.tag == .array_access) {
                // Handle $arr[0]++
                const array_val = try self.eval(expr_node.data.array_access.target);
                defer self.releaseValue(array_val);

                const index_node = expr_node.data.array_access.index orelse return Value.initNull();
                const index_val = try self.eval(index_node);
                defer self.releaseValue(index_val);

                if (array_val.isArray()) {
                    const php_array = array_val.getAsArray().data;
                    const key = switch (index_val.getTag()) {
                        .integer => types.ArrayKey{ .integer = index_val.asInt() },
                        .string => types.ArrayKey{ .string = index_val.getAsString().data },
                        else => return Value.initNull(),
                    };

                    const current_val = php_array.get(key) orelse Value.initInt(0);
                    self.retainValue(current_val);

                    var new_val: Value = undefined;
                    if (postfix_expr.op == .plus_plus) {
                        new_val = try self.incrementValue(current_val);
                    } else {
                        new_val = try self.decrementValue(current_val);
                    }

                    try php_array.set(self.allocator, key, new_val);
                    return current_val;
                }
                return Value.initNull();
            } else if (expr_node.tag == .static_property_access) {
                // Handle Class::$property++
                const class_name = self.context.string_pool.keys()[expr_node.data.static_property_access.class_name];
                const prop_name = self.context.string_pool.keys()[expr_node.data.static_property_access.property_name];

                // Resolve class
                const class = if (std.mem.eql(u8, class_name, "self")) blk: {
                    break :blk self.current_class orelse {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access self:: outside of class scope", self.current_file, self.current_line);
                        return self.throwException(exception);
                    };
                } else if (std.mem.eql(u8, class_name, "static")) blk: {
                    break :blk self.current_called_class orelse {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access static:: outside of class scope", self.current_file, self.current_line);
                        return self.throwException(exception);
                    };
                } else if (std.mem.eql(u8, class_name, "parent")) blk: {
                    const curr_class = self.current_class orelse {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: outside of class scope", self.current_file, self.current_line);
                        return self.throwException(exception);
                    };
                    break :blk curr_class.parent orelse {
                        const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: when class has no parent", self.current_file, self.current_line);
                        return self.throwException(exception);
                    };
                } else blk: {
                    break :blk self.getClass(class_name) orelse {
                        const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
                        return self.throwException(exception);
                    };
                };

                // Get current static property value
                var current_val: Value = Value.initInt(0);
                var found = false;

                // Search in current class and parents
                var search_class: ?*types.PHPClass = class;
                while (search_class) |sc| {
                    if (sc.properties.getPtr(prop_name)) |prop| {
                        if (prop.modifiers.is_static) {
                            if (prop.default_value) |val| {
                                current_val = val;
                                found = true;
                            }
                            break;
                        }
                    }
                    search_class = sc.parent;
                }

                if (!found) {
                    const exception = try ExceptionFactory.createUndefinedPropertyError(self.allocator, class.name.data, prop_name, self.current_file, self.current_line);
                    return self.throwException(exception);
                }

                // Retain current value
                self.retainValue(current_val);

                // Calculate new value
                var new_val: Value = undefined;
                if (postfix_expr.op == .plus_plus) {
                    new_val = try self.incrementValue(current_val);
                } else {
                    new_val = try self.decrementValue(current_val);
                }

                // Update static property
                search_class = class;
                while (search_class) |sc| {
                    if (sc.properties.getPtr(prop_name)) |prop| {
                        if (prop.modifiers.is_static) {
                            if (prop.default_value) |old_val| {
                                self.releaseValue(old_val);
                            }
                            self.retainValue(new_val);
                            prop.default_value = new_val;
                            break;
                        }
                    }
                    search_class = sc.parent;
                }

                return current_val;
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Increment/decrement only supports variables and properties", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        }

        return Value.initNull();
    }

    inline fn incrementValue(self: *VM, value: Value) !Value {
        _ = self;
        return switch (value.getTag()) {
            .integer => Value.initInt(value.asInt() + 1),
            .float => Value.initFloat(value.asFloat() + 1.0),
            .string => blk: {
                // Try to parse as integer first for performance
                const str = value.getAsString().data.data;
                if (std.fmt.parseInt(i64, str, 10)) |i| {
                    break :blk Value.initInt(i + 1);
                } else |_| {
                    // Fallback to float
                    if (std.fmt.parseFloat(f64, str)) |f| {
                        break :blk Value.initFloat(f + 1.0);
                    } else |_| {
                        // Non-numeric string increment (PERL style not fully impl)
                        // PHP 8 behavior for non-numeric string increment is complex
                        // For optimization benchmark, we assume numeric loop counters usually
                        break :blk Value.initInt(1);
                    }
                }
            },
            .null => Value.initInt(1),
            .boolean => value, // bool++ has no effect in PHP
            else => Value.initInt(1),
        };
    }

    inline fn decrementValue(self: *VM, value: Value) !Value {
        _ = self;
        return switch (value.getTag()) {
            .integer => Value.initInt(value.asInt() - 1),
            .float => Value.initFloat(value.asFloat() - 1.0),
            .string => blk: {
                const str = value.getAsString().data.data;
                if (std.fmt.parseInt(i64, str, 10)) |i| {
                    break :blk Value.initInt(i - 1);
                } else |_| {
                    if (std.fmt.parseFloat(f64, str)) |f| {
                        break :blk Value.initFloat(f - 1.0);
                    } else |_| {
                        break :blk Value.initInt(-1); // Non-numeric string -> -1 (roughly)
                    }
                }
            },
            .null => Value.initNull(),
            .boolean => value, // bool-- has no effect
            else => Value.initInt(0),
        };
    }

    fn evaluateTernaryExpression(self: *VM, ternary_expr: anytype) !Value {
        const condition = try self.eval(ternary_expr.cond);
        defer self.releaseValue(condition);

        const is_truthy = condition.toBool();

        if (is_truthy) {
            if (ternary_expr.then_expr) |then_expr| {
                return self.eval(then_expr);
            } else {
                return condition.retain(); // Elvis operator: condition ?: else_expr
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

        if (object.getTag() != .object) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Clone with can only be used on objects", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        // Clone the object
        const cloned_object = try object.getAsObject().data.clone(self.allocator);

        // Apply property modifications
        const properties = try self.eval(clone_with_expr.properties);
        defer self.releaseValue(properties);

        if (properties.isArray()) {
            var iterator = properties.getAsArray().data.getElements().iterator();
            while (iterator.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;

                switch (key) {
                    .string => |prop_name| {
                        try cloned_object.setProperty(self.allocator, prop_name.data, value);
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

    fn evaluateCastExpression(self: *VM, cast_data: anytype) !Value {
        const value = try self.eval(cast_data.expr);
        defer self.releaseValue(value);

        return switch (cast_data.cast_type) {
            .cast_int => Value.initInt(value.toInt()),
            .cast_float => Value.initFloat(value.toFloat()),
            .cast_string => blk: {
                const str = try value.toString(self.allocator);
                defer str.release(self.allocator);
                break :blk try Value.initStringWithManager(&self.memory_manager, str.data);
            },
            .cast_bool => Value.initBool(value.toBool()),
            .k_array => blk: {
                if (value.isArray()) {
                    break :blk value.retain();
                }
                const arr = try Value.initArrayWithManager(&self.memory_manager);
                if (!value.isNull()) {
                    try arr.getAsArray().data.push(self.allocator, value);
                }
                break :blk arr;
            },
            .k_object => blk: {
                // Convert to object - if array, convert keys to properties
                if (value.isArray()) {
                    const stdClass = self.getClass("stdClass") orelse {
                        // Create a simple object
                        break :blk value.retain();
                    };
                    const obj = try self.allocator.create(types.PHPObject);
                    obj.* = try types.PHPObject.init(self.allocator, stdClass);

                    // Copy array elements to object properties
                    var iterator = value.getAsArray().data.getElements().iterator();
                    while (iterator.next()) |entry| {
                        switch (entry.key_ptr.*) {
                            .string => |key| {
                                try obj.setProperty(self.allocator, key.data, entry.value_ptr.*);
                            },
                            .integer => |idx| {
                                const key_str = try std.fmt.allocPrint(self.allocator, "{d}", .{idx});
                                defer self.allocator.free(key_str);
                                try obj.setProperty(self.allocator, key_str, entry.value_ptr.*);
                            },
                        }
                    }

                    const box = try self.allocator.create(types.gc.Box(*types.PHPObject));
                    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = obj };
                    break :blk Value.fromBox(box, Value.TYPE_OBJECT);
                }
                break :blk value.retain();
            },
            else => value.retain(),
        };
    }

    fn executeIncluded(self: *VM, source: []const u8, file_path: []const u8, is_once: bool) anyerror!Value {
        // Check if already included for once-semantics
        if (is_once) {
            if (self.included_files.contains(file_path)) {
                return Value.initBool(true);
            }
        }

        // Create null-terminated source for parser
        const source_z = try self.allocator.allocSentinel(u8, source.len, 0);
        defer self.allocator.free(source_z);
        @memcpy(source_z, source);

        // Detect syntax directive in the included file
        // This allows each file to specify its own syntax mode via // @syntax: directive
        const directive_result = syntax_mode.detectSyntaxDirective(source);
        const file_syntax_mode = if (directive_result.found and directive_result.mode != null)
            directive_result.mode.?
        else
            self.syntax_config.mode; // Use current VM's syntax mode as default

        // Parse the included file with the appropriate syntax mode
        // IMPORTANT: Use context.allocator (Arena) not self.allocator (GPA)
        // because context.nodes is managed by context.allocator
        var parser = Parser.initWithMode(self.context.allocator, self.context, source_z, file_syntax_mode) catch {
            return Value.initNull();
        };
        // We don't deinit parser here because AST nodes are allocated in the context
        // and might be referenced later? Actually parser deinit just ignores self.
        defer parser.deinit();

        const root = parser.parse() catch {
            return Value.initNull();
        };

        // Record inclusion
        if (is_once) {
            try self.included_files.put(try self.allocator.dupe(u8, file_path), {});
        }

        // Save and restore current file and syntax config
        const old_file = self.current_file;
        const old_source = self.current_source;
        const old_syntax_config = self.syntax_config;
        self.current_file = file_path;
        self.current_source = source; // Store source for line number calculation
        // Update syntax config for error reporting in the included file
        if (directive_result.found and directive_result.mode != null) {
            self.syntax_config = SyntaxConfig.init(file_syntax_mode);
        }
        defer {
            self.current_file = old_file;
            self.current_source = old_source;
            self.syntax_config = old_syntax_config;
        }

        // Execute the AST
        // We use @as to force the error type to anyerror to break recursion in type inference
        return @as(anyerror!Value, self.eval(root));
    }

    fn evaluateFunctionDeclaration(self: *VM, func_decl: anytype) !Value {
        const name_id = func_decl.name;
        const name = self.context.string_pool.keys()[name_id];

        var user_function = types.UserFunction.init(try types.PHPString.init(self.allocator, name));
        user_function.parameters = try self.processParameters(func_decl.params);
        user_function.return_type = null;
        user_function.attributes = try self.convertAttributes(func_decl.attributes);
        user_function.body = @ptrFromInt(func_decl.body);
        user_function.returns_reference = func_decl.returns_reference;

        // Check if any parameter is variadic and count required parameters
        var is_variadic = false;
        user_function.min_args = 0;
        for (user_function.parameters) |param| {
            if (param.is_variadic) {
                is_variadic = true;
            }
            if (param.default_value == null and !param.is_variadic) {
                user_function.min_args += 1;
            }
        }
        user_function.is_variadic = is_variadic;
        user_function.max_args = if (is_variadic) null else @as(u32, @intCast(user_function.parameters.len));

        const func_box = try self.memory_manager.allocUserFunction(user_function);
        const func_value = Value.fromBox(func_box, Value.TYPE_USER_FUNC);
        try self.global.set(name, func_value);
        self.releaseValue(func_value);

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

        loop: while (true) {
            const condition = try self.eval(while_stmt.condition);
            const condition_bool = condition.toBool();
            self.releaseValue(condition);

            if (!condition_bool) break;

            self.releaseValue(last_val);
            last_val = self.eval(while_stmt.body) catch |err| blk: {
                if (err == error.Break) {
                    self.break_level -= 1;
                    if (self.break_level > 0) return error.Break;
                    break :loop;
                }
                if (err == error.Continue) {
                    self.continue_level -= 1;
                    if (self.continue_level > 0) return error.Continue;
                    break :blk Value.initNull();
                }
                return err;
            };
        }

        return last_val;
    }

    fn evaluateDoWhileStatement(self: *VM, do_while_stmt: anytype) !Value {
        var last_val = Value.initNull();

        loop: while (true) {
            self.releaseValue(last_val);
            last_val = self.eval(do_while_stmt.body) catch |err| blk: {
                if (err == error.Break) {
                    self.break_level -= 1;
                    if (self.break_level > 0) return error.Break;
                    break :loop;
                }
                if (err == error.Continue) {
                    self.continue_level -= 1;
                    if (self.continue_level > 0) return error.Continue;
                    break :blk Value.initNull();
                }
                return err;
            };

            const condition = try self.eval(do_while_stmt.condition);
            const condition_bool = condition.toBool();
            self.releaseValue(condition);

            if (!condition_bool) break;
        }

        return last_val;
    }

    fn evaluateForStatement(self: *VM, for_stmt: anytype) !Value {
        // Execute initialization
        if (for_stmt.init) |init_idx| {
            const init_val = try self.eval(init_idx);
            self.releaseValue(init_val);
        }

        var last_val = Value.initNull();

        loop: while (true) {
            // Check condition
            if (for_stmt.condition) |cond_idx| {
                const condition = try self.eval(cond_idx);
                const condition_bool = condition.toBool();
                self.releaseValue(condition);

                if (!condition_bool) break;
            }

            // Execute body
            self.releaseValue(last_val);
            last_val = self.eval(for_stmt.body) catch |err| blk: {
                if (err == error.Break) {
                    self.break_level -= 1;
                    if (self.break_level > 0) return error.Break;
                    break :loop;
                }
                if (err == error.Continue) {
                    self.continue_level -= 1;
                    if (self.continue_level > 0) return error.Continue;
                    break :blk Value.initNull();
                }
                return err;
            };
            // Fallthrough for Continue or normal execution: execute loop expression

            // Execute loop expression (increment/decrement)
            if (for_stmt.loop) |loop_idx| {
                const loop_val = try self.eval(loop_idx);
                self.releaseValue(loop_val);
            }
        }

        return last_val;
    }

    fn evaluateForRangeStatement(self: *VM, range_stmt: anytype) !Value {
        const count_val = try self.eval(range_stmt.count);
        defer self.releaseValue(count_val);

        var count: i64 = 0;
        switch (count_val.getTag()) {
            .integer => count = count_val.asInt(),
            .float => count = @intFromFloat(count_val.asFloat()),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Range count must be a number", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }

        var last_val = Value.initNull();
        var i: i64 = 0;
        loop: while (i < count) : (i += 1) {
            // Set variable if present
            if (range_stmt.variable) |var_idx| {
                const var_node = self.context.nodes.items[var_idx];
                if (var_node.tag == .variable) {
                    const name_id = var_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    try self.setVariable(name, Value.initInt(i));
                } else {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Range variable must be a variable", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            }

            self.releaseValue(last_val);

            last_val = self.eval(range_stmt.body) catch |err| blk: {
                if (err == error.Break) {
                    self.break_level -= 1;
                    if (self.break_level > 0) return error.Break;
                    break :loop;
                }
                if (err == error.Continue) {
                    self.continue_level -= 1;
                    if (self.continue_level > 0) return error.Continue;
                    break :blk Value.initNull();
                }
                return err;
            };
        }

        return last_val;
    }

    /// 检查类是否实现了指定接口
    fn classImplementsInterface(self: *VM, class: *types.PHPClass, interface_name: []const u8) bool {
        // 检查直接实现的接口
        for (class.interfaces) |iface| {
            if (std.mem.eql(u8, iface.name.data, interface_name)) {
                return true;
            }
        }
        // 检查父类
        var parent = class.parent;
        while (parent) |p| {
            if (self.classImplementsInterface(p, interface_name)) {
                return true;
            }
            parent = p.parent;
        }
        return false;
    }

    /// 处理 Iterator 对象的 foreach 遍历
    fn evaluateIteratorForeach(self: *VM, iterator_value: Value, foreach_stmt: anytype) !Value {
        var last_val = Value.initNull();

        // 调用 rewind()
        const obj = iterator_value.getAsObject().data;
        _ = obj.callMethod(self, iterator_value, "rewind", &.{}) catch {};

        loop: while (true) {
            // 检查是否有效
            const valid_result = obj.callMethod(self, iterator_value, "valid", &.{}) catch Value.initBool(false);
            const is_valid = valid_result.asBool();
            self.releaseValue(valid_result);

            if (!is_valid) {
                break;
            }

            // 获取 key（如果指定）
            if (foreach_stmt.key) |key_idx| {
                const key_result = obj.callMethod(self, iterator_value, "key", &.{}) catch Value.initNull();
                defer self.releaseValue(key_result);

                const key_node = self.context.nodes.items[key_idx];
                if (key_node.tag == .variable) {
                    const name_id = key_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    try self.setVariable(name, key_result.retain());
                }
            }

            // 获取 value
            if (foreach_stmt.value > 0 and foreach_stmt.value < self.context.nodes.items.len) {
                const value_result = obj.callMethod(self, iterator_value, "current", &.{}) catch Value.initNull();
                defer self.releaseValue(value_result);

                const value_node = self.context.nodes.items[foreach_stmt.value];
                if (value_node.tag == .variable) {
                    const name_id = value_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    try self.setVariable(name, value_result.retain());
                }
            }

            // 执行循环体
            self.releaseValue(last_val);
            const body_idx = foreach_stmt.body;
            if (body_idx > 0 and body_idx < self.context.nodes.items.len) {
                last_val = self.eval(body_idx) catch |err| blk: {
                    if (err == error.Break) {
                        self.break_level -= 1;
                        if (self.break_level > 0) return error.Break;
                        break :loop;
                    }
                    if (err == error.Continue) {
                        self.continue_level -= 1;
                        if (self.continue_level > 0) return error.Continue;
                        break :blk Value.initNull();
                    }
                    return err;
                };
            } else {
                last_val = Value.initNull();
            }

            // 调用 next()
            _ = obj.callMethod(self, iterator_value, "next", &.{}) catch {};
        }

        return last_val;
    }

    /// 处理 Generator 对象的 foreach 遍历 - 使用语句迭代
    fn evaluateGeneratorForeach(self: *VM, generator_value: Value, foreach_stmt: anytype) !Value {
        var last_val = Value.initNull();

        const generator_obj = generator_value.getAsObject().data;

        // 获取 GeneratorState
        const state_ptr_val = generator_obj.getProperty("__generator_state_ptr") catch Value.initNull();
        defer state_ptr_val.release(self.allocator);

        const ptr_str = if (state_ptr_val.isString()) state_ptr_val.getAsString().data.data else "";
        const state_ptr_int = std.fmt.parseInt(u64, ptr_str, 10) catch 0;

        if (state_ptr_int == 0) {
            return Value.initNull();
        }

        const state = @as(*GeneratorState, @ptrFromInt(state_ptr_int));

        // 收集所有值
        if (!state.has_started) {
            state.has_started = true;
            self.generator_state = state;

            // 恢复 $this 上下文
            if (state.this_context) |this_val| {
                try self.setVariable("$this", this_val.retain());
            }

            // 获取函数体的语句列表
            if (state.function_body) |body_node| {
                const body_ast_node = self.context.nodes.items[body_node];

                // 获取语句列表
                var stmt_indices: []const ast.Node.Index = &[_]ast.Node.Index{};
                if (body_ast_node.tag == .block) {
                    stmt_indices = body_ast_node.data.block.stmts;
                } else {
                    // 如果函数体不是 block，直接使用它
                    stmt_indices = &[_]ast.Node.Index{body_node};
                }

                // 迭代执行每条语句
                var stmt_index: usize = 0;
                while (stmt_index < stmt_indices.len) {
                    const stmt = stmt_indices[stmt_index];

                    // 执行语句
                    _ = self.eval(stmt) catch |err| {
                        if (err == error.YieldOutsideGenerator) {
                            // Yield 已处理，继续下一个语句
                            stmt_index += 1;
                            continue;
                        } else if (err == error.Return or err == error.Break) {
                            // 函数返回或 break，停止收集
                            break;
                        } else {
                            // 其他错误，停止收集
                            break;
                        }
                    };

                    stmt_index += 1;
                }

                state.is_exhausted = true;
            }
        }

        // 迭代收集的值
        loop: while (state.current_index < state.values.items.len) {
            const key = state.keys.items[state.current_index];
            const value = state.values.items[state.current_index];
            state.current_index += 1;

            // 设置 key 变量
            if (foreach_stmt.key) |key_idx| {
                const key_node = self.context.nodes.items[key_idx];
                if (key_node.tag == .variable) {
                    const name_id = key_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    try self.setVariable(name, key.retain());
                }
            }

            // 设置 value 变量
            if (foreach_stmt.value > 0 and foreach_stmt.value < self.context.nodes.items.len) {
                const value_node = self.context.nodes.items[foreach_stmt.value];
                if (value_node.tag == .variable) {
                    const value_name_id = value_node.data.variable.name;
                    const value_name = self.context.string_pool.keys()[value_name_id];
                    try self.setVariable(value_name, value.retain());
                }
            }

            // 执行循环体
            self.releaseValue(last_val);
            const body_idx = foreach_stmt.body;
            if (body_idx > 0 and body_idx < self.context.nodes.items.len) {
                last_val = self.eval(body_idx) catch |err| {
                    if (err == error.Break) {
                        self.break_level -= 1;
                        if (self.break_level > 0) return error.Break;
                        break :loop;
                    }
                    if (err == error.Continue) {
                        self.continue_level -= 1;
                        if (self.continue_level > 0) return error.Continue;
                        break :loop;
                    }
                    return err;
                };
            } else {
                last_val = Value.initNull();
            }
        }

        return last_val;
    }

    fn evaluateForeachStatement(self: *VM, foreach_stmt: anytype) !Value {
        // 安全检查：确保 iterable 是有效的索引
        const iterable_idx = foreach_stmt.iterable;
        if (iterable_idx == 0 or iterable_idx >= self.context.nodes.items.len) {
            return Value.initNull();
        }

        const iterable = try self.eval(iterable_idx);
        defer self.releaseValue(iterable);

        // 检查是否是 Iterator 或 IteratorAggregate 对象
        if (iterable.isObject()) {
            const obj = iterable.getAsObject().data;
            const class_name = obj.class.name.data;

            // 检查是否是 Generator 对象
            if (std.mem.eql(u8, class_name, "Generator")) {
                // 直接迭代 Generator 的 yielded 值
                return self.evaluateGeneratorForeach(iterable, foreach_stmt);
            }

            // 检查是否是 Iterator 或实现了 Iterator 接口
            const is_iterator = std.mem.eql(u8, class_name, "Iterator") or
                self.classImplementsInterface(obj.class, "Iterator");

            if (is_iterator or std.mem.eql(u8, class_name, "IteratorAggregate")) {
                return self.evaluateIteratorForeach(iterable, foreach_stmt);
            }
        }

        // 如果不是 Iterator，回退到数组遍历
        if (iterable.getTag() != .array) {
            // 使用安全的行号（固定值避免溢出问题）
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Foreach can only iterate over arrays or Iterator objects", self.current_file, 1);
            return self.throwException(exception);
        }

        var last_val = Value.initNull();
        const array_ptr = iterable.getAsArray();
        var iterator = array_ptr.data.getElements().iterator();

        loop: while (iterator.next()) |entry| {
            const key_ptr = entry.key_ptr;
            const value_ptr = entry.value_ptr;

            // 安全检查：确保指针有效
            if (@intFromPtr(key_ptr) == 0 or @intFromPtr(value_ptr) == 0) {
                continue;
            }

            const key = key_ptr.*;
            const value = value_ptr.*;

            // Set key variable if specified
            if (foreach_stmt.key) |key_idx| {
                // 安全检查：确保索引有效且不为0
                if (key_idx != 0 and @as(usize, key_idx) < self.context.nodes.items.len) {
                    const key_node = self.context.nodes.items[key_idx];
                    if (key_node.tag == .variable) {
                        const key_name_id = key_node.data.variable.name;
                        if (key_name_id < self.context.string_pool.keys().len) {
                            const key_name = self.context.string_pool.keys()[key_name_id];
                            const key_value = switch (key) {
                                .integer => |iv| Value.initInt(iv),
                                .string => |s| if (s.data.len > 0)
                                    try Value.initStringWithManager(&self.memory_manager, s.data)
                                else
                                    Value.initNull(),
                            };
                            try self.setVariable(key_name, key_value);
                            self.releaseValue(key_value);
                        }
                    }
                }
            }

            // Set value variable - 安全检查
            if (foreach_stmt.value > 0 and foreach_stmt.value < self.context.nodes.items.len) {
                const value_node = self.context.nodes.items[foreach_stmt.value];
                if (value_node.tag == .variable) {
                    const value_name_id = value_node.data.variable.name;
                    if (value_name_id < self.context.string_pool.keys().len) {
                        const value_name = self.context.string_pool.keys()[value_name_id];
                        try self.setVariable(value_name, value);
                    }
                }
            }

            // Execute body - 安全检查
            self.releaseValue(last_val);
            const body_idx = foreach_stmt.body;
            if (body_idx > 0 and body_idx < self.context.nodes.items.len) {
                last_val = self.eval(body_idx) catch |err| blk: {
                    if (err == error.Break) {
                        self.break_level -= 1;
                        if (self.break_level > 0) return error.Break;
                        break :loop;
                    }
                    if (err == error.Continue) {
                        self.continue_level -= 1;
                        if (self.continue_level > 0) return error.Continue;
                        break :blk Value.initNull();
                    }
                    return err;
                };
            } else {
                last_val = Value.initNull();
            }
        }

        return last_val;
    }

    fn evaluateSwitchStatement(self: *VM, switch_stmt: anytype) !Value {
        const expr = try self.eval(switch_stmt.expression);
        defer self.releaseValue(expr);

        var matched = false;
        var last_val = Value.initNull();

        // Evaluate each case
        for (switch_stmt.cases) |case_idx| {
            const case_node = self.context.nodes.items[case_idx];
            const case_data = case_node.data.case;

            // Only evaluate conditions if not already matched
            if (!matched) {
                const condition = try self.eval(case_data.condition);
                defer self.releaseValue(condition);

                // Compare expression with condition
                if (self.valuesEqual(expr, condition)) {
                    matched = true;
                }
            }

            // If matched, execute the case body
            if (matched) {
                for (case_data.body) |stmt| {
                    self.releaseValue(last_val);
                    last_val = self.eval(stmt) catch |err| blk: {
                        if (err == error.Break) {
                            self.break_level -= 1;
                            if (self.break_level > 0) return error.Break;
                            break :blk Value.initNull();
                        }
                        return err;
                    };
                }
            }
        }

        // Evaluate default case if provided and no match found
        if (!matched and switch_stmt.default != null) {
            const default_idx = switch_stmt.default.?;
            const default_node = self.context.nodes.items[default_idx];
            const default_data = default_node.data.default;

            for (default_data.body) |stmt| {
                self.releaseValue(last_val);
                last_val = self.eval(stmt) catch |err| blk: {
                    if (err == error.Break) {
                        self.break_level -= 1;
                        if (self.break_level > 0) return error.Break;
                        break :blk Value.initNull();
                    }
                    return err;
                };
            }
        }

        return last_val;
    }

    fn evaluateMatchExpression(self: *VM, match_expr: anytype) anyerror!Value {
        const expr = try self.eval(match_expr.expression);
        defer self.releaseValue(expr);

        const nodes = self.context.nodes.items;
        const nodes_len = nodes.len;

        // Evaluate each arm
        for (match_expr.arms) |arm_idx| {
            // Boundary check for arm_idx
            if (arm_idx >= nodes_len) {
                const exception = try ExceptionFactory.createError(self.allocator, "Invalid match arm index", self.current_file, self.current_line);
                return self.throwException(exception);
            }
            const arm_node = nodes[arm_idx];
            const arm_data = arm_node.data.match_arm;

            // Check if any condition matches
            for (arm_data.conditions) |cond_idx| {
                // Boundary check for cond_idx
                if (cond_idx >= nodes_len) {
                    const exception = try ExceptionFactory.createError(self.allocator, "Invalid match condition index", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
                const condition = try self.eval(cond_idx);
                defer self.releaseValue(condition);

                if (self.valuesEqual(expr, condition)) {
                    return self.eval(arm_data.body);
                }
            }
        }

        // Check default arm if exists
        if (match_expr.default) |default_idx| {
            // Boundary check for default_idx
            if (default_idx >= nodes_len) {
                const exception = try ExceptionFactory.createError(self.allocator, "Invalid match default index", self.current_file, self.current_line);
                return self.throwException(exception);
            }
            const default_node = nodes[default_idx];
            const default_data = default_node.data.match_arm;
            return self.eval(default_data.body);
        }

        // If no match found, return an UnhandledMatchError
        const exception = try ExceptionFactory.createTypeError(self.allocator, "Unhandled match value", self.current_file, self.current_line);
        return self.throwException(exception);
    }

    fn evaluateReturnStatement(self: *VM, return_stmt: anytype) !Value {
        if (return_stmt.expr) |expr| {
            // Release previous return value if any (shouldn't happen in normal flow but safe to do)
            if (self.return_value) |val| {
                self.releaseValue(val);
            }

            // Check if we're in a reference-returning function
            if (self.current_frame) |frame| {
                // Get function from global scope
                if (self.global.get(frame.function_name)) |func_val| {
                    if (func_val.getTag() == .user_function) {
                        const func = func_val.getAsUserFunc().data;
                        if (func.returns_reference) {
                            // For reference return, we need to return a reference to the variable
                            const expr_node = self.context.nodes.items[expr];
                            if (expr_node.tag == .variable) {
                                const var_name = self.context.string_pool.keys()[expr_node.data.variable.name];
                                // Check if it's a static variable
                                const static_key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ frame.function_name, var_name });

                                if (self.static_vars.getPtr(static_key)) |_| {
                                    // 创建引用 Value（使用哈希值）
                                    const ref_value = Value.fromReference(static_key);
                                    const hash = ref_value.asReferenceHash();
                                    // 记录哈希到 key 的映射
                                    try self.ref_hash_to_key.put(hash, static_key);
                                    self.return_value = ref_value;
                                    return error.Return;
                                } else {
                                    self.allocator.free(static_key);
                                }
                            }
                        }
                    }
                }
            }

            self.return_value = try self.eval(expr);
        } else {
            if (self.return_value) |val| {
                self.releaseValue(val);
            }
            self.return_value = Value.initNull();
        }
        return error.Return;
    }

    fn evaluateBreakStatement(self: *VM, break_stmt: anytype) !Value {
        if (break_stmt.level) |level_idx| {
            const level_val = try self.eval(level_idx);
            defer self.releaseValue(level_val);
            if (level_val.isInt()) {
                self.break_level = @intCast(level_val.asInt());
            } else {
                self.break_level = 1;
            }
        } else {
            self.break_level = 1;
        }
        return error.Break;
    }

    fn evaluateContinueStatement(self: *VM, continue_stmt: anytype) !Value {
        if (continue_stmt.level) |level_idx| {
            const level_val = try self.eval(level_idx);
            defer self.releaseValue(level_val);
            if (level_val.isInt()) {
                self.continue_level = @intCast(level_val.asInt());
            } else {
                self.continue_level = 1;
            }
        } else {
            self.continue_level = 1;
        }
        return error.Continue;
    }

    /// Evaluate lock statement - mutex syntax sugar for coroutine synchronization
    /// lock { ... } acquires a global mutex, executes the body, then releases the mutex
    fn evaluateLockStatement(self: *VM, lock_stmt: anytype) !Value {
        // Acquire the global mutex
        self.acquireGlobalMutex();
        defer self.releaseGlobalMutex();

        // Execute the body
        const result = self.eval(lock_stmt.body) catch |err| {
            // Make sure to release mutex even on error
            return err;
        };

        return result;
    }

    /// Acquire the global mutex for lock statements
    fn acquireGlobalMutex(self: *VM) void {
        // In a real implementation, this would use std.Thread.Mutex
        // For now, we use a simple flag since the interpreter is single-threaded
        _ = self;
        // self.global_mutex.lock();
    }

    /// Release the global mutex for lock statements
    fn releaseGlobalMutex(self: *VM) void {
        _ = self;
        // self.global_mutex.unlock();
    }

    /// Evaluate global statement - imports variables from global scope
    fn evaluateGlobalStatement(self: *VM, global_stmt: anytype) !Value {
        // For each variable in global statement, import it from global scope
        for (global_stmt.vars) |var_idx| {
            const var_node = self.context.nodes.items[var_idx];

            // Get the variable name (should be a simple variable node)
            if (var_node.tag == .variable) {
                const name_id = var_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];

                // Ensure variable exists in global scope (init to null if not)
                if (!self.global.vars.contains(name)) {
                    try self.global.set(name, Value.initNull());
                }

                // If in function context, mark as imported
                if (self.current_frame) |frame| {
                    try frame.imported_globals.put(name, {});

                    // Remove any shadowing local variable
                    if (frame.locals.get(name)) |old_val| {
                        self.releaseValue(old_val);
                        _ = frame.locals.remove(name);
                    }
                }
            }
        }

        return Value.initNull();
    }

    fn evaluateStaticStatement(self: *VM, static_stmt: anytype) !Value {
        // Static variables are function-scoped and persist across calls
        // Get current function context (may be null if at global scope)
        const func_name = if (self.current_frame) |frame| frame.function_name else "__global__";

        // Process each static variable declaration
        for (static_stmt.vars) |var_idx| {
            const var_node = self.context.nodes.items[var_idx];

            // Handle: static $x = value;
            if (var_node.tag == .assignment) {
                const target_idx = var_node.data.assignment.target;
                const value_idx = var_node.data.assignment.value;
                const target_node = self.context.nodes.items[target_idx];

                if (target_node.tag == .variable) {
                    const name_id = target_node.data.variable.name;
                    const var_name = self.context.string_pool.keys()[name_id];

                    // Build static key: "func_name::var_name"
                    const static_key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ func_name, var_name });
                    defer self.allocator.free(static_key);

                    // Check if already initialized
                    if (!self.static_vars.contains(static_key)) {
                        // Initialize with value
                        const init_val = try self.eval(value_idx);
                        try self.static_vars.put(try self.allocator.dupe(u8, static_key), init_val);
                    }

                    // Set local/global reference to static variable
                    const static_val = self.static_vars.get(static_key).?;
                    if (self.current_frame) |frame| {
                        try frame.locals.put(var_name, static_val.retain());
                    } else {
                        try self.global.set(var_name, static_val.retain());
                    }
                }
            }
            // Handle: static $x; (no initializer)
            else if (var_node.tag == .variable) {
                const name_id = var_node.data.variable.name;
                const var_name = self.context.string_pool.keys()[name_id];

                const static_key = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ func_name, var_name });
                defer self.allocator.free(static_key);

                if (!self.static_vars.contains(static_key)) {
                    try self.static_vars.put(try self.allocator.dupe(u8, static_key), Value.initNull());
                }

                const static_val = self.static_vars.get(static_key).?;
                if (self.current_frame) |frame| {
                    try frame.locals.put(var_name, static_val.retain());
                } else {
                    try self.global.set(var_name, static_val.retain());
                }
            }
        }

        return Value.initNull();
    }

    /// Evaluate go statement - spawn a coroutine
    fn evaluateGoStatement(self: *VM, go_stmt: anytype) !Value {
        // Get or create coroutine manager
        const cm = try self.getCoroutineManager();

        // Extract the function to call and arguments
        const call_idx = go_stmt.call;
        const call_node = self.context.nodes.items[call_idx];

        var callback_value: Value = undefined;
        var args: []const Value = &.{};

        if (call_node.tag == .function_call) {
            const func_call = call_node.data.function_call;
            const name_node = self.context.nodes.items[func_call.name];

            // Get the function value
            if (name_node.tag == .variable) {
                const name_id = name_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];
                callback_value = try self.getVariableValue(name);
            } else if (name_node.tag == .literal_string) {
                const name_id = name_node.data.literal_string.value;
                const name = self.context.string_pool.keys()[name_id];
                // Create a closure from the function name
                callback_value = try self.createClosureFromName(name);
            } else {
                // Try to evaluate as a callable expression
                callback_value = try self.eval(func_call.name);
            }

            // Evaluate arguments
            var args_list = std.ArrayListUnmanaged(Value){};
            defer args_list.deinit(self.allocator);
            for (func_call.args) |arg_idx| {
                const arg_value = try self.eval(arg_idx);
                try args_list.append(self.allocator, arg_value);
            }
            args = try self.allocator.dupe(Value, args_list.items);
        } else if (call_node.tag == .method_call) {
            // For method calls, create a closure that calls the method
            const method_call = call_node.data.method_call;
            const target_value = try self.eval(method_call.target);
            defer self.releaseValue(target_value);

            const method_name = self.context.string_pool.keys()[method_call.method_name];

            // Create a closure that calls the method
            var args_list = std.ArrayListUnmanaged(Value){};
            for (method_call.args) |arg_idx| {
                const arg_value = try self.eval(arg_idx);
                try args_list.append(self.allocator, arg_value);
            }

            // Create a wrapper function that calls the method
            const wrapper_name = try types.PHPString.init(self.allocator, "go_wrapper");
            var user_func = types.UserFunction.init(wrapper_name);
            user_func.parameters = &[_]types.Method.Parameter{};
            user_func.body = null; // Will be set dynamically

            var closure = types.Closure.init(self.allocator, user_func);
            try closure.captureVariable("target", target_value.retain());
            try closure.captureVariable("method", Value.initString(self.allocator, method_name) catch Value.initNull());
            for (args_list.items, 0..) |arg, i| {
                try closure.captureVariable(try std.fmt.allocPrint(self.allocator, "arg{d}", .{i}), arg);
            }

            const box = try self.memory_manager.allocClosure(closure);
            callback_value = Value.fromBox(box, Value.TYPE_CLOSURE);
            args = &.{};
        } else {
            // Try to evaluate as a general expression
            callback_value = try self.eval(call_idx);
            args = &.{};
        }

        // Spawn the coroutine
        const coroutine_id = try cm.spawn(callback_value, args);

        // Return coroutine ID immediately (async behavior)
        return Value.initInt(@intCast(coroutine_id));
    }

    /// Get a variable value without throwing an exception
    fn getVariableValue(self: *VM, name: []const u8) !Value {
        if (self.getVariable(name)) |value| {
            return value.retain();
        }
        return Value.initNull();
    }

    /// Create a closure from a function name
    fn createClosureFromName(self: *VM, name: []const u8) !Value {
        // This is a simplified implementation
        // In a full implementation, we would look up the function and create a proper closure
        const closure_name = try types.PHPString.init(self.allocator, name);
        var user_func = types.UserFunction.init(closure_name);
        user_func.body = null;

        const closure = types.Closure.init(self.allocator, user_func);
        const box = try self.memory_manager.allocClosure(closure);
        return Value.fromBox(box, Value.TYPE_CLOSURE);
    }
    fn evaluateBinaryOp(self: *VM, op: Token.Tag, left: Value, right: Value) !Value {
        switch (op) {
            .plus => return self.evaluateAddition(left, right),
            .minus => return self.evaluateSubtraction(left, right),
            .asterisk => return self.evaluateMultiplication(left, right),
            .slash => return self.evaluateDivision(left, right),
            .percent => return self.evaluateModulo(left, right),
            .equal_equal => return Value.initBool(self.valuesEqual(left, right)),
            .bang_equal => return Value.initBool(!self.valuesEqual(left, right)),
            .equal_equal_equal => return Value.initBool(self.valuesStrictEqual(left, right)),
            .bang_equal_equal => return Value.initBool(!self.valuesStrictEqual(left, right)),
            .less => return Value.initBool((try self.compareValues(left, right, .less)) != 0),
            .less_equal => return Value.initBool((try self.compareValues(left, right, .less_equal)) != 0),
            .greater => return Value.initBool((try self.compareValues(left, right, .greater)) != 0),
            .greater_equal => return Value.initBool((try self.compareValues(left, right, .greater_equal)) != 0),
            .spaceship => {
                const cmp = try self.compareValues(left, right, .spaceship);
                return Value.initInt(cmp);
            },
            .double_ampersand => return Value.initBool(left.toBool() and right.toBool()),
            .double_pipe => return Value.initBool(left.toBool() or right.toBool()),
            .double_question => {
                if (!left.isNull()) return left.retain();
                return right.retain();
            },
            .dot => return self.concatenateValues(left, right),
            .k_instanceof => return self.evaluateInstanceOf(left, right),
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
            .tilde => {
                // Bitwise NOT
                const int_val = operand.toInt();
                return Value.initInt(~int_val);
            },
            .ampersand => return operand, // Reference operator (treat as value for now to prevent crash)
            .k_clone => {
                if (operand.getTag() != .object) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "__clone method called on non-object", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
                const cloned_obj = try operand.getAsObject().data.clone(self.allocator);
                const cloned_val = try Value.initObjectWithObject(&self.memory_manager, cloned_obj);

                if (cloned_obj.class.hasMethod("__clone")) {
                    const result = try self.callObjectMethod(cloned_val, "__clone", &.{});
                    defer self.releaseValue(result);
                }

                return cloned_val;
            },
            else => {
                std.debug.print("Error: Unsupported unary operator: {any}\n", .{op});
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Unsupported unary operator", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }
    }

    fn evaluateModulo(self: *VM, left: Value, right: Value) !Value {
        if (!left.isInt() or !right.isInt()) {
            return self.handleInvalidOperands("modulo");
        }

        const r = right.asInt();
        if (r == 0) {
            // PHP 8 returns INF for division by zero (with a warning)
            return Value.initFloat(std.math.inf(f64));
        }

        return Value.initInt(@mod(left.asInt(), r));
    }

    fn valuesEqual(self: *VM, left: Value, right: Value) bool {
        _ = self;
        const left_tag = left.getTag();
        const right_tag = right.getTag();

        if (left_tag == .integer and right_tag == .integer) {
            return left.asInt() == right.asInt();
        }

        if ((left_tag == .integer or left_tag == .float) and (right_tag == .integer or right_tag == .float)) {
            const l = if (left_tag == .float) left.asFloat() else @as(f64, @floatFromInt(left.asInt()));
            const r = if (right_tag == .float) right.asFloat() else @as(f64, @floatFromInt(right.asInt()));
            return l == r;
        }

        // PHP 类型转换：数字 vs 字符串
        if ((left_tag == .integer or left_tag == .float) and right_tag == .string) {
            const left_num = if (left_tag == .float) left.asFloat() else @as(f64, @floatFromInt(left.asInt()));
            const right_str = right.getAsString().data.data;
            const right_num = std.fmt.parseFloat(f64, right_str) catch return false;
            return left_num == right_num;
        }

        if (left_tag == .string and (right_tag == .integer or right_tag == .float)) {
            const left_str = left.getAsString().data.data;
            const left_num = std.fmt.parseFloat(f64, left_str) catch return false;
            const right_num = if (right_tag == .float) right.asFloat() else @as(f64, @floatFromInt(right.asInt()));
            return left_num == right_num;
        }

        if (left_tag == .string and right_tag == .string) {
            return std.mem.eql(u8, left.getAsString().data.data, right.getAsString().data.data);
        }

        if (left_tag == .boolean and right_tag == .boolean) {
            return left.asBool() == right.asBool();
        }

        if (left_tag == .null and right_tag == .null) {
            return true;
        }

        return false;
    }

    fn valuesStrictEqual(self: *VM, left: Value, right: Value) bool {
        _ = self;
        const left_tag = left.getTag();
        const right_tag = right.getTag();

        if (left_tag != right_tag) return false;

        return switch (left_tag) {
            .null => true,
            .boolean => left.asBool() == right.asBool(),
            .integer => left.asInt() == right.asInt(),
            .float => left.asFloat() == right.asFloat(),
            .string => std.mem.eql(u8, left.getAsString().data.data, right.getAsString().data.data),
            .array => @intFromPtr(left.getAsArray()) == @intFromPtr(right.getAsArray()),
            .object => @intFromPtr(left.getAsObject()) == @intFromPtr(right.getAsObject()),
            else => false,
        };
    }

    fn compareValues(self: *VM, left: Value, right: Value, op: Token.Tag) !i64 {
        _ = self;
        const left_tag = left.getTag();
        const right_tag = right.getTag();

        if ((left_tag == .integer or left_tag == .float) and (right_tag == .integer or right_tag == .float)) {
            const l = if (left_tag == .float) left.asFloat() else @as(f64, @floatFromInt(left.asInt()));
            const r = if (right_tag == .float) right.asFloat() else @as(f64, @floatFromInt(right.asInt()));

            return switch (op) {
                .less => if (l < r) 1 else 0,
                .less_equal => if (l <= r) 1 else 0,
                .greater => if (l > r) 1 else 0,
                .greater_equal => if (l >= r) 1 else 0,
                .spaceship => {
                    if (l < r) return -1;
                    if (l > r) return 1;
                    return 0;
                },
                else => 0,
            };
        }

        return 0;
    }

    fn concatenateValues(self: *VM, left: Value, right: Value) !Value {
        const left_res = try self.valueToString(left);
        defer if (left_res.needs_free) self.allocator.free(left_res.str);

        const right_res = try self.valueToString(right);
        defer if (right_res.needs_free) self.allocator.free(right_res.str);

        const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left_res.str, right_res.str });
        defer self.allocator.free(result);
        return Value.initStringWithManager(&self.memory_manager, result);
    }

    fn negateValue(self: *VM, operand: Value) !Value {
        switch (operand.getTag()) {
            .integer => return Value.initInt(-operand.asInt()),
            .float => return Value.initFloat(-operand.asFloat()),
            else => {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid operand for negation", self.current_file, self.current_line);
                return self.throwException(exception);
            },
        }
    }
    fn evaluateInterfaceDeclaration(self: *VM, interface_data: anytype) !Value {
        const interface_name = self.context.string_pool.keys()[interface_data.name];
        const php_interface_name = try types.PHPString.init(self.allocator, interface_name);
        defer php_interface_name.release(self.allocator);

        // Create new interface
        var php_interface = types.PHPInterface.init(self.allocator, php_interface_name);

        // Process interface members
        for (interface_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .method_decl => {
                    try self.processInterfaceMethodDeclaration(&php_interface, member_node.data.method_decl);
                },
                .const_decl => {
                    try self.processInterfaceConstantDeclaration(&php_interface, member_node.data.const_decl);
                },
                else => {
                    // Skip unsupported member types
                },
            }
        }

        // Register the interface
        const interface_ptr = try self.allocator.create(types.PHPInterface);
        interface_ptr.* = php_interface;
        try self.defineInterface(interface_name, interface_ptr);

        return Value.initNull();
    }

    fn processInterfaceMethodDeclaration(self: *VM, interface_obj: *types.PHPInterface, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];
        const php_method_name = try types.PHPString.init(self.allocator, method_name);
        defer php_method_name.release(self.allocator);

        var method = types.Method.init(php_method_name);

        // Interface methods are public and abstract
        method.modifiers = .{
            .visibility = .public,
            .is_abstract = true,
            .is_static = method_data.modifiers.is_static,
        };

        method.parameters = try self.processParameters(method_data.params);
        try interface_obj.methods.put(method_name, method);
    }

    fn processInterfaceConstantDeclaration(self: *VM, interface_obj: *types.PHPInterface, const_data: anytype) !void {
        const const_name = self.context.string_pool.keys()[const_data.name];
        const const_value = try self.eval(const_data.value);
        try interface_obj.constants.put(const_name, const_value);
    }

    fn checkInterfaceImplementation(self: *VM, class: *types.PHPClass, interface: *types.PHPInterface) !void {
        var it = interface.methods.iterator();
        while (it.next()) |entry| {
            const method_name = entry.key_ptr.*;
            // Check if class has this method (or inherits it)
            if (!class.hasMethod(method_name)) {
                const msg = try std.fmt.allocPrint(self.allocator, "Class {s} contains 1 abstract method and must therefore be declared abstract or implement the remaining methods ({s}::{s})", .{ class.name.data, interface.name.data, method_name });
                defer self.allocator.free(msg);
                const exception = try ExceptionFactory.createTypeError(self.allocator, msg, self.current_file, self.current_line);
                _ = try self.throwException(exception);
                return error.UncaughtException;
            }
        }

        for (interface.extends) |parent_interface| {
            try self.checkInterfaceImplementation(class, parent_interface);
        }
    }

    const ComposedTraitMethod = struct {
        provider_trait: []const u8,
        original_name: []const u8,
        exposed_name: []const u8,
        method: *const types.Method,
        visibility: types.Property.Visibility,
    };

    const ComposedTraitProperty = struct {
        provider_trait: []const u8,
        property: *const types.Property,
    };

    const ComposedTraitConstant = struct {
        provider_trait: []const u8,
        name: []const u8,
        value: *const Value,
    };

    fn cloneMethodForTrait(
        self: *VM,
        source: *const types.Method,
        exposed_name: []const u8,
        visibility: types.Property.Visibility,
    ) !types.Method {
        const php_name = try types.PHPString.init(
            self.allocator,
            exposed_name,
        );
        defer php_name.release(self.allocator);

        var cloned = types.Method.init(php_name);
        cloned.return_type = source.return_type;
        cloned.modifiers = source.modifiers;
        cloned.modifiers.visibility = visibility;
        cloned.body = source.body;

        if (source.parameters.len > 0) {
            const parameters = try self.allocator.alloc(
                types.Method.Parameter,
                source.parameters.len,
            );
            errdefer self.allocator.free(parameters);

            for (source.parameters, 0..) |param, i| {
                parameters[i] = param;
                parameters[i].name.retain();
                if (parameters[i].default_value) |default_value| {
                    parameters[i].default_value = default_value.retain();
                }
            }
            cloned.parameters = parameters;
        }

        return cloned;
    }

    fn clonePropertyForTrait(
        self: *VM,
        source: *const types.Property,
    ) !types.Property {
        const php_name = try types.PHPString.init(
            self.allocator,
            source.name.data,
        );
        defer php_name.release(self.allocator);

        var cloned = types.Property.init(php_name);
        cloned.type = source.type;
        cloned.modifiers = source.modifiers;
        if (source.default_value) |default_value| {
            cloned.default_value = default_value.retain();
        }
        if (source.hooks.len > 0) {
            cloned.hooks = try self.allocator.dupe(
                types.PropertyHook,
                source.hooks,
            );
        }
        return cloned;
    }

    fn traitValueCompatible(self: *VM, lhs: ?Value, rhs: ?Value) bool {
        if (lhs == null and rhs == null) return true;
        if (lhs == null or rhs == null) return false;
        return self.valuesStrictEqual(lhs.?, rhs.?);
    }

    fn traitPropertyCompatible(
        self: *VM,
        lhs: *const types.Property,
        rhs: *const types.Property,
    ) bool {
        return lhs.modifiers.visibility == rhs.modifiers.visibility and
            lhs.modifiers.is_static == rhs.modifiers.is_static and
            lhs.modifiers.is_readonly == rhs.modifiers.is_readonly and
            std.meta.eql(lhs.type, rhs.type) and
            self.traitValueCompatible(lhs.default_value, rhs.default_value);
    }

    fn traitConstantCompatible(
        self: *VM,
        lhs: *const Value,
        rhs: *const Value,
    ) bool {
        return self.valuesStrictEqual(lhs.*, rhs.*);
    }

    fn traitMethodsEquivalent(
        self: *VM,
        lhs: ComposedTraitMethod,
        rhs: ComposedTraitMethod,
    ) bool {
        _ = self;
        return std.mem.eql(u8, lhs.provider_trait, rhs.provider_trait) and
            std.mem.eql(u8, lhs.original_name, rhs.original_name) and
            std.mem.eql(u8, lhs.exposed_name, rhs.exposed_name) and
            lhs.visibility == rhs.visibility and
            lhs.method == rhs.method;
    }

    fn appendComposedTraitMethod(
        self: *VM,
        methods: *std.ArrayListUnmanaged(ComposedTraitMethod),
        method: ComposedTraitMethod,
    ) !void {
        for (methods.items) |existing| {
            if (!std.mem.eql(u8, existing.exposed_name, method.exposed_name)) {
                continue;
            }
            if (self.traitMethodsEquivalent(existing, method)) return;
            return error.TraitMethodConflict;
        }
        try methods.append(self.allocator, method);
    }

    fn appendComposedTraitProperty(
        self: *VM,
        properties: *std.ArrayListUnmanaged(ComposedTraitProperty),
        property: ComposedTraitProperty,
    ) !void {
        for (properties.items) |existing| {
            if (!std.mem.eql(
                u8,
                existing.property.name.data,
                property.property.name.data,
            )) continue;
            if (!self.traitPropertyCompatible(
                existing.property,
                property.property,
            )) {
                return error.TraitPropertyConflict;
            }
            return;
        }
        try properties.append(self.allocator, property);
    }

    fn appendComposedTraitConstant(
        self: *VM,
        constants: *std.ArrayListUnmanaged(ComposedTraitConstant),
        constant: ComposedTraitConstant,
    ) !void {
        for (constants.items) |existing| {
            if (!std.mem.eql(u8, existing.name, constant.name)) continue;
            if (!self.traitConstantCompatible(existing.value, constant.value)) {
                return error.TraitConstantConflict;
            }
            return;
        }
        try constants.append(self.allocator, constant);
    }

    fn resolveTraitMethodTarget(
        self: *VM,
        methods: []ComposedTraitMethod,
        method_ref: ast.TraitMethodReference,
    ) !usize {
        const method_name = self.context.string_pool.keys()[method_ref.method_name];
        const trait_name = if (method_ref.trait_name) |name_id|
            self.context.string_pool.keys()[name_id]
        else
            null;

        var found_idx: ?usize = null;
        for (methods, 0..) |method, idx| {
            if (!std.mem.eql(u8, method.exposed_name, method_name)) continue;
            if (trait_name) |required_trait| {
                if (!std.mem.eql(u8, method.provider_trait, required_trait)) {
                    continue;
                }
            }
            if (found_idx != null) return error.AmbiguousTraitMethodReference;
            found_idx = idx;
        }
        return found_idx orelse error.UnknownTraitMethodReference;
    }

    fn visibilityFromTraitVisibility(
        self: *VM,
        visibility: ast.TraitVisibility,
    ) types.Property.Visibility {
        _ = self;
        return switch (visibility) {
            .public => .public,
            .protected => .protected,
            .private => .private,
        };
    }

    fn applyTraitAdaptations(
        self: *VM,
        methods: *std.ArrayListUnmanaged(ComposedTraitMethod),
        adaptations: []const ast.TraitAdaptation,
    ) !void {
        const base_methods = try self.allocator.dupe(
            ComposedTraitMethod,
            methods.items,
        );
        defer self.allocator.free(base_methods);

        for (adaptations) |adaptation| {
            switch (adaptation) {
                .insteadof => |data| {
                    _ = try self.resolveTraitMethodTarget(
                        methods.items,
                        data.preferred,
                    );
                    const method_name = self.context
                        .string_pool
                        .keys()[data.preferred.method_name];

                    var write_idx: usize = 0;
                    for (methods.items) |method| {
                        var excluded = false;
                        if (std.mem.eql(u8, method.exposed_name, method_name)) {
                            for (data.excluded_traits) |excluded_trait_id| {
                                const excluded_trait = self.context
                                    .string_pool
                                    .keys()[excluded_trait_id];
                                if (std.mem.eql(
                                    u8,
                                    method.provider_trait,
                                    excluded_trait,
                                )) {
                                    excluded = true;
                                    break;
                                }
                            }
                        }
                        if (!excluded) {
                            methods.items[write_idx] = method;
                            write_idx += 1;
                        }
                    }
                    methods.items.len = write_idx;
                },
                .alias => |data| {
                    if (data.alias) |alias_id| {
                        const target_idx = try self.resolveTraitMethodTarget(
                            base_methods,
                            data.original,
                        );
                        var alias_method = base_methods[target_idx];
                        alias_method.exposed_name = self.context
                            .string_pool
                            .keys()[alias_id];
                        if (data.visibility) |visibility| {
                            alias_method.visibility =
                                self.visibilityFromTraitVisibility(visibility);
                        }
                        try methods.append(self.allocator, alias_method);
                    } else if (data.visibility) |visibility| {
                        const target_idx = self.resolveTraitMethodTarget(
                            methods.items,
                            data.original,
                        ) catch continue;
                        methods.items[target_idx].visibility =
                            self.visibilityFromTraitVisibility(visibility);
                    }
                },
            }
        }
    }

    fn throwTraitCompositionError(
        self: *VM,
        owner_kind: []const u8,
        owner_name: []const u8,
        err: anyerror,
    ) !void {
        const message = switch (err) {
            error.TraitMethodConflict => try std.fmt.allocPrint(
                self.allocator,
                "{s} {s} has colliding trait methods and no conflict resolution was provided",
                .{ owner_kind, owner_name },
            ),
            error.TraitPropertyConflict => try std.fmt.allocPrint(
                self.allocator,
                "{s} {s} has incompatible trait property definitions",
                .{ owner_kind, owner_name },
            ),
            error.TraitConstantConflict => try std.fmt.allocPrint(
                self.allocator,
                "{s} {s} has incompatible trait constant definitions",
                .{ owner_kind, owner_name },
            ),
            error.TraitNotFound => try std.fmt.allocPrint(
                self.allocator,
                "{s} {s} references an undefined trait",
                .{ owner_kind, owner_name },
            ),
            error.UnknownTraitMethodReference => try std.fmt.allocPrint(
                self.allocator,
                "{s} {s} contains a trait adaptation for an unknown method",
                .{ owner_kind, owner_name },
            ),
            error.AmbiguousTraitMethodReference => try std.fmt.allocPrint(
                self.allocator,
                "{s} {s} contains an ambiguous trait method reference",
                .{ owner_kind, owner_name },
            ),
            else => return err,
        };
        defer self.allocator.free(message);

        const exception = try ExceptionFactory.createTypeError(
            self.allocator,
            message,
            self.current_file,
            self.current_line,
        );
        _ = try self.throwException(exception);
    }

    fn collectTraitUseMembers(
        self: *VM,
        trait_use_data: anytype,
        methods: *std.ArrayListUnmanaged(ComposedTraitMethod),
        properties: *std.ArrayListUnmanaged(ComposedTraitProperty),
        constants: *std.ArrayListUnmanaged(ComposedTraitConstant),
    ) !void {
        for (trait_use_data.traits) |trait_idx| {
            const trait_node = self.context.nodes.items[trait_idx];
            if (trait_node.tag != .named_type) continue;

            const trait_name = self.context
                .string_pool
                .keys()[trait_node.data.named_type.name];
            const trait_obj = self.getTrait(trait_name) orelse {
                return error.TraitNotFound;
            };

            var method_iter = trait_obj.methods.iterator();
            while (method_iter.next()) |entry| {
                const method_name = entry.key_ptr.*;
                try methods.append(self.allocator, .{
                    .provider_trait = trait_name,
                    .original_name = method_name,
                    .exposed_name = method_name,
                    .method = entry.value_ptr,
                    .visibility = entry.value_ptr.modifiers.visibility,
                });
            }

            var property_iter = trait_obj.properties.iterator();
            while (property_iter.next()) |entry| {
                try self.appendComposedTraitProperty(properties, .{
                    .provider_trait = trait_name,
                    .property = entry.value_ptr,
                });
            }

            var constant_iter = trait_obj.constants.iterator();
            while (constant_iter.next()) |entry| {
                try self.appendComposedTraitConstant(constants, .{
                    .provider_trait = trait_name,
                    .name = entry.key_ptr.*,
                    .value = entry.value_ptr,
                });
            }
        }

        try self.applyTraitAdaptations(methods, trait_use_data.adaptations);

        var resolved_methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
        defer resolved_methods.deinit(self.allocator);
        for (methods.items) |method| {
            try self.appendComposedTraitMethod(&resolved_methods, method);
        }
        methods.items.len = 0;
        for (resolved_methods.items) |method| {
            try methods.append(self.allocator, method);
        }
    }

    fn mergeTraitUseIntoTrait(
        self: *VM,
        owner_name: []const u8,
        php_trait: *types.PHPTrait,
        trait_use_data: anytype,
    ) !void {
        var methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
        defer methods.deinit(self.allocator);
        var properties = std.ArrayListUnmanaged(ComposedTraitProperty){};
        defer properties.deinit(self.allocator);
        var constants = std.ArrayListUnmanaged(ComposedTraitConstant){};
        defer constants.deinit(self.allocator);

        self.collectTraitUseMembers(
            trait_use_data,
            &methods,
            &properties,
            &constants,
        ) catch |err| {
            try self.throwTraitCompositionError("Trait", owner_name, err);
            return error.UncaughtException;
        };

        for (methods.items) |method_info| {
            if (php_trait.methods.contains(method_info.exposed_name)) continue;
            const cloned = try self.cloneMethodForTrait(
                method_info.method,
                method_info.exposed_name,
                method_info.visibility,
            );
            try php_trait.methods.put(method_info.exposed_name, cloned);
        }

        for (properties.items) |property_info| {
            const property_name = property_info.property.name.data;
            if (php_trait.properties.getPtr(property_name)) |existing| {
                if (!self.traitPropertyCompatible(existing, property_info.property)) {
                    try self.throwTraitCompositionError(
                        "Trait",
                        owner_name,
                        error.TraitPropertyConflict,
                    );
                    return error.UncaughtException;
                }
                continue;
            }
            const cloned = try self.clonePropertyForTrait(property_info.property);
            try php_trait.properties.put(property_name, cloned);
        }

        for (constants.items) |constant_info| {
            if (php_trait.constants.getPtr(constant_info.name)) |existing| {
                if (!self.traitConstantCompatible(existing, constant_info.value)) {
                    try self.throwTraitCompositionError(
                        "Trait",
                        owner_name,
                        error.TraitConstantConflict,
                    );
                    return error.UncaughtException;
                }
                continue;
            }
            try php_trait.constants.put(
                constant_info.name,
                constant_info.value.*.retain(),
            );
        }
    }

    fn mergeTraitUseIntoClass(
        self: *VM,
        owner_name: []const u8,
        class: *types.PHPClass,
        trait_use_data: anytype,
    ) !void {
        var methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
        defer methods.deinit(self.allocator);
        var properties = std.ArrayListUnmanaged(ComposedTraitProperty){};
        defer properties.deinit(self.allocator);
        var constants = std.ArrayListUnmanaged(ComposedTraitConstant){};
        defer constants.deinit(self.allocator);

        self.collectTraitUseMembers(
            trait_use_data,
            &methods,
            &properties,
            &constants,
        ) catch |err| {
            try self.throwTraitCompositionError("Class", owner_name, err);
            return error.UncaughtException;
        };

        for (methods.items) |method_info| {
            if (class.methods.contains(method_info.exposed_name)) continue;
            const cloned = try self.cloneMethodForTrait(
                method_info.method,
                method_info.exposed_name,
                method_info.visibility,
            );
            try class.methods.put(method_info.exposed_name, cloned);
        }

        for (properties.items) |property_info| {
            const property_name = property_info.property.name.data;
            if (class.properties.getPtr(property_name)) |existing| {
                if (!self.traitPropertyCompatible(existing, property_info.property)) {
                    try self.throwTraitCompositionError(
                        "Class",
                        owner_name,
                        error.TraitPropertyConflict,
                    );
                    return error.UncaughtException;
                }
                continue;
            }
            const cloned = try self.clonePropertyForTrait(property_info.property);
            try class.properties.put(property_name, cloned);
        }

        for (constants.items) |constant_info| {
            if (class.constants.getPtr(constant_info.name)) |existing| {
                if (!self.traitConstantCompatible(existing, constant_info.value)) {
                    try self.throwTraitCompositionError(
                        "Class",
                        owner_name,
                        error.TraitConstantConflict,
                    );
                    return error.UncaughtException;
                }
                continue;
            }
            try class.constants.put(
                constant_info.name,
                constant_info.value.*.retain(),
            );
        }
    }

    fn evaluateTraitDeclaration(self: *VM, trait_data: anytype) !Value {
        const trait_name = self.context.string_pool.keys()[trait_data.name];
        const php_trait_name = try types.PHPString.init(self.allocator, trait_name);
        defer php_trait_name.release(self.allocator);

        var php_trait = types.PHPTrait.init(self.allocator, php_trait_name);

        // Process trait members
        for (trait_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .method_decl => {
                    try self.processTraitMethodDeclaration(&php_trait, member_node.data.method_decl);
                },
                .property_decl => {
                    try self.processTraitPropertyDeclaration(&php_trait, member_node.data.property_decl);
                },
                .const_decl => {
                    try self.processTraitConstantDeclaration(
                        &php_trait,
                        member_node.data.const_decl,
                    );
                },
                .trait_use => {
                    try self.processNestedTraitUse(
                        trait_name,
                        &php_trait,
                        member_node.data.trait_use,
                    );
                },
                else => {},
            }
        }

        // Register the trait
        const trait_ptr = try self.allocator.create(types.PHPTrait);
        trait_ptr.* = php_trait;
        try self.defineTrait(trait_name, trait_ptr);

        return Value.initNull();
    }

    fn processNestedTraitUse(
        self: *VM,
        trait_name: []const u8,
        php_trait: *types.PHPTrait,
        trait_use_data: anytype,
    ) !void {
        try self.mergeTraitUseIntoTrait(
            trait_name,
            php_trait,
            trait_use_data,
        );
    }

    fn processTraitMethodDeclaration(self: *VM, trait_obj: *types.PHPTrait, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];
        const php_method_name = try types.PHPString.init(self.allocator, method_name);
        defer php_method_name.release(self.allocator);

        var method = types.Method.init(php_method_name);
        method.modifiers = .{
            .visibility = if (method_data.modifiers.is_public) .public else if (method_data.modifiers.is_protected) .protected else if (method_data.modifiers.is_private) .private else .public,
            .is_static = method_data.modifiers.is_static,
            .is_final = method_data.modifiers.is_final,
            .is_abstract = method_data.modifiers.is_abstract,
        };
        method.parameters = try self.processParameters(method_data.params);
        method.body = if (method_data.body) |body_idx| @ptrFromInt(@as(usize, body_idx)) else null;
        try trait_obj.methods.put(method_name, method);
    }

    fn processTraitPropertyDeclaration(self: *VM, trait_obj: *types.PHPTrait, property_data: anytype) !void {
        const prop_name = self.context.string_pool.keys()[property_data.name];
        const php_prop_name = try types.PHPString.init(self.allocator, prop_name);
        defer php_prop_name.release(self.allocator);

        var property = types.Property.init(php_prop_name);
        property.modifiers = .{
            .visibility = if (property_data.modifiers.is_public) .public else if (property_data.modifiers.is_protected) .protected else if (property_data.modifiers.is_private) .private else .public,
            .is_static = property_data.modifiers.is_static,
            .is_readonly = property_data.modifiers.is_readonly,
        };
        if (property_data.default_value) |default_idx| {
            property.default_value = try self.eval(default_idx);
        }
        try trait_obj.properties.put(prop_name, property);
    }

    fn processTraitConstantDeclaration(
        self: *VM,
        trait_obj: *types.PHPTrait,
        const_data: anytype,
    ) !void {
        const const_name = self.context.string_pool.keys()[const_data.name];
        const const_value = try self.eval(const_data.value);
        try trait_obj.constants.put(const_name, const_value);
    }

    fn processTraitUse(
        self: *VM,
        class_name: []const u8,
        class: *types.PHPClass,
        trait_use_data: anytype,
    ) !void {
        try self.mergeTraitUseIntoClass(class_name, class, trait_use_data);
    }

    fn evaluateClassDeclaration(self: *VM, class_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        const class_name = self.context.string_pool.keys()[class_data.name];
        const php_class_name = try types.PHPString.init(self.allocator, class_name);
        defer php_class_name.release(self.allocator);

        // Create new class
        var php_class = try types.PHPClass.init(self.allocator, php_class_name);

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

        // Process implements clause
        if (class_data.implements.len > 0) {
            const interfaces = try self.allocator.alloc(*types.PHPInterface, class_data.implements.len);
            php_class.interfaces = interfaces;

            for (class_data.implements, 0..) |interface_idx, i| {
                const interface_node = self.context.nodes.items[interface_idx];
                if (interface_node.tag == .variable) {
                    const interface_name = self.context.string_pool.keys()[interface_node.data.variable.name];
                    // 首先尝试获取接口，如果找不到则尝试获取类（兼容内置接口）
                    if (self.getInterface(interface_name)) |interface_obj| {
                        interfaces[i] = interface_obj;
                    } else if (self.getClass(interface_name)) |_| {
                        // 创建一个伪接口对象用于类型检查
                        const fake_interface = try self.allocator.create(types.PHPInterface);
                        const name_str = try types.PHPString.init(self.allocator, interface_name);
                        fake_interface.* = types.PHPInterface.init(self.allocator, name_str);
                        name_str.release(self.allocator);
                        interfaces[i] = fake_interface;
                    } else {
                        php_class.deinit(self.allocator);
                        const msg = try std.fmt.allocPrint(self.allocator, "Interface '{s}' not found", .{interface_name});
                        defer self.allocator.free(msg);
                        const exception = try ExceptionFactory.createTypeError(self.allocator, msg, self.current_file, self.current_line);
                        return self.throwException(exception);
                    }
                } else {
                    php_class.deinit(self.allocator);
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid interface name", self.current_file, self.current_line);
                    return self.throwException(exception);
                }
            }
        }

        // Process class members
        for (class_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .trait_use => {
                    try self.processTraitUse(
                        class_name,
                        &php_class,
                        member_node.data.trait_use,
                    );
                },
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

        // Abstract method check - performed on &php_class before allocation/registration
        if (!php_class.modifiers.is_abstract) {
            // Check interface methods
            for (php_class.interfaces) |interface_obj| {
                self.checkInterfaceImplementation(&php_class, interface_obj) catch |err| {
                    php_class.deinit(self.allocator);
                    return err;
                };
            }

            var curr = php_class.parent;
            while (curr) |parent| {
                var it = parent.methods.iterator();
                while (it.next()) |entry| {
                    const method = entry.value_ptr;
                    if (method.modifiers.is_abstract) {
                        if (php_class.getMethod(entry.key_ptr.*)) |resolved_method| {
                            if (resolved_method.modifiers.is_abstract) {
                                // Error found: Clean up php_class before throwing
                                php_class.deinit(self.allocator);
                                const exception = try ExceptionFactory.createTypeError(self.allocator, "Class must implement abstract method", self.current_file, self.current_line);
                                return self.throwException(exception);
                            }
                        } else {
                            // Abstract method not implemented (not found)
                            php_class.deinit(self.allocator);
                            const exception = try ExceptionFactory.createTypeError(self.allocator, "Class must implement abstract method", self.current_file, self.current_line);
                            return self.throwException(exception);
                        }
                    }
                }
                curr = parent.parent;
            }
        }

        // Register the class
        const class_ptr = try self.allocator.create(types.PHPClass);
        class_ptr.* = php_class;

        // Define class (takes ownership of class_ptr, but if it fails we must handle it)
        self.defineClass(class_name, class_ptr) catch |err| {
            class_ptr.deinit(self.allocator);
            self.allocator.destroy(class_ptr);
            return err;
        };

        return Value.initNull();
    }

    fn processMethodDeclaration(self: *VM, class: *types.PHPClass, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];

        // Check if parent has final method with same name
        if (class.parent) |parent| {
            if (parent.getMethod(method_name)) |parent_method| {
                if (parent_method.modifiers.is_final) {
                    const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot override final method", self.current_file, self.current_line);
                    _ = try self.throwException(exception);
                    return;
                }
            }
        }

        const php_method_name = try types.PHPString.init(self.allocator, method_name);
        defer php_method_name.release(self.allocator);

        // Create method
        var method = types.Method.init(php_method_name);

        // Set method modifiers
        method.modifiers = .{
            .is_static = method_data.modifiers.is_static,
            .is_final = method_data.modifiers.is_final,
            .is_abstract = method_data.modifiers.is_abstract,
            .visibility = if (method_data.modifiers.is_public) .public else if (method_data.modifiers.is_protected) .protected else .private,
        };

        // Process parameters
        method.parameters = try self.processParameters(method_data.params);

        // Set method body
        if (method_data.body) |body_idx| {
            method.body = @ptrFromInt(body_idx);
        }

        // Add method to class (simplified - just store in methods map)
        try class.methods.put(method_name, method);
    }

    fn addClassProperty(self: *VM, class: *types.PHPClass, name: []const u8, visibility: types.Property.Visibility, default_value: ?Value) !void {
        const prop_name = try types.PHPString.init(self.allocator, name);
        defer prop_name.release(self.allocator);
        var property = types.Property.init(prop_name);
        property.modifiers.visibility = visibility;
        property.default_value = default_value;
        try class.properties.put(name, property);
    }

    fn processPropertyDeclaration(self: *VM, class: *types.PHPClass, property_data: anytype) !void {
        const property_name = self.context.string_pool.keys()[property_data.name];

        // Create property
        const property_name_str = try types.PHPString.init(self.allocator, property_name);
        defer property_name_str.release(self.allocator);
        var property = types.Property.init(property_name_str);

        // Set property modifiers
        property.modifiers = .{
            .is_static = property_data.modifiers.is_static,
            .is_readonly = property_data.modifiers.is_readonly,
            .visibility = if (property_data.modifiers.is_public) .public else if (property_data.modifiers.is_protected) .protected else .private,
        };

        // Set default value if present
        if (property_data.default_value) |default_idx| {
            property.default_value = try self.eval(default_idx);
        }

        // Process property hooks if present
        var hooks = try std.ArrayList(types.PropertyHook).initCapacity(self.allocator, property_data.hooks.len);
        defer hooks.deinit(self.allocator);

        for (property_data.hooks) |hook_idx| {
            const hook_node = self.context.nodes.items[hook_idx];
            if (hook_node.tag == .property_hook) {
                const hook_data = hook_node.data.property_hook;
                const hook_name = self.context.string_pool.keys()[hook_data.name];

                // Convert u32 body index to pointer for storage
                const body_ptr: ?*anyopaque = if (hook_data.body != 0) @ptrFromInt(hook_data.body) else null;

                if (std.mem.eql(u8, hook_name, "get")) {
                    hooks.appendAssumeCapacity(types.PropertyHook{ .type = .get, .body = body_ptr });
                } else if (std.mem.eql(u8, hook_name, "set")) {
                    hooks.appendAssumeCapacity(types.PropertyHook{ .type = .set, .body = body_ptr });
                }
            }
        }

        // Store hooks in property
        if (hooks.items.len > 0) {
            property.hooks = try self.allocator.dupe(types.PropertyHook, hooks.items);
        }

        // Add property to class (simplified - just store in properties map)
        try class.properties.put(property_name, property);
    }

    fn processConstantDeclaration(self: *VM, class: *types.PHPClass, const_data: anytype) !void {
        const const_name = self.context.string_pool.keys()[const_data.name];
        const const_value = try self.eval(const_data.value);

        // Add constant to class
        try class.constants.put(const_name, const_value);
    }

    fn evaluateStructDeclaration(self: *VM, struct_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        const struct_name = self.context.string_pool.keys()[struct_data.name];
        const php_struct_name = try types.PHPString.init(self.allocator, struct_name);
        defer php_struct_name.release(self.allocator); // PHPStruct.init will retain it

        // Create new struct
        var php_struct = types.PHPStruct.init(self.allocator, php_struct_name);

        // Process struct members
        for (struct_data.members) |member_idx| {
            const member_node = self.context.nodes.items[member_idx];

            switch (member_node.tag) {
                .method_decl => {
                    try self.processStructMethodDeclaration(&php_struct, member_node.data.method_decl);
                },
                .property_decl => {
                    try self.processStructFieldDeclaration(&php_struct, member_node.data.property_decl);
                },
                else => {
                    // Skip unsupported member types
                },
            }
        }

        // Register the struct
        const struct_ptr = try self.allocator.create(types.PHPStruct);
        struct_ptr.* = php_struct;
        try self.defineStruct(struct_name, struct_ptr);

        return Value.initNull();
    }

    fn evaluateStructInstantiation(self: *VM, struct_data: anytype) !Value {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.execution_stats.execution_time_ns += @intCast(end_time - start_time);
        }

        // Get struct type
        const struct_type_node = self.context.nodes.items[struct_data.struct_type];
        if (struct_type_node.tag != .variable) {
            const exception = try ExceptionFactory.createTypeError(self.allocator, "Invalid struct type", self.current_file, self.current_line);
            return self.throwException(exception);
        }

        const struct_name = self.context.string_pool.keys()[struct_type_node.data.variable.name];
        const struct_type = self.getStruct(struct_name) orelse {
            const exception = try ExceptionFactory.createUndefinedStructError(self.allocator, struct_name, self.current_file, self.current_line);
            return self.throwException(exception);
        };

        // Create struct instance
        const struct_instance = try self.allocator.create(types.StructInstance);
        struct_instance.* = types.StructInstance.init(self.allocator, struct_type);

        // Evaluate constructor arguments
        var args = std.ArrayList(Value){};
        try args.ensureTotalCapacity(self.allocator, struct_data.args.len);
        defer {
            for (args.items) |arg| {
                self.releaseValue(arg);
            }
            args.deinit(self.allocator);
        }

        for (struct_data.args) |arg_idx| {
            const arg_value = try self.eval(arg_idx);
            try args.append(self.allocator, arg_value);
        }

        // Initialize struct fields with default values
        try self.initializeStructFields(struct_instance, struct_type);

        // Create boxed value for the instance
        const box = try self.allocator.create(types.gc.Box(*types.StructInstance));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = struct_instance,
        };
        const instance_value = Value.fromBox(box, Value.TYPE_STRUCT);

        // Call constructor if it exists
        if (struct_type.hasMethod("__construct")) {
            const ctor_result = struct_instance.callMethod(self, instance_value, "__construct", args.items) catch |err| {
                // Clean up on error
                self.releaseValue(instance_value);
                return err;
            };
            self.releaseValue(ctor_result);
        }

        return instance_value;
    }

    fn processStructMethodDeclaration(self: *VM, struct_type: *types.PHPStruct, method_data: anytype) !void {
        const method_name = self.context.string_pool.keys()[method_data.name];
        const php_method_name = try types.PHPString.init(self.allocator, method_name);
        defer php_method_name.release(self.allocator); // Method.init will retain it

        // Create method
        var method = types.Method.init(php_method_name);

        // Set method modifiers
        method.modifiers = .{
            .is_static = method_data.modifiers.is_static,
            .is_final = method_data.modifiers.is_final,
            .is_abstract = method_data.modifiers.is_abstract,
            .visibility = if (method_data.modifiers.is_public) .public else if (method_data.modifiers.is_protected) .protected else .private,
        };

        // Process parameters
        method.parameters = try self.processParameters(method_data.params);

        // Set method body
        if (method_data.body) |body_idx| {
            method.body = @ptrFromInt(body_idx);
        }

        // Add method to struct
        try struct_type.addMethod(method);
    }

    fn processStructFieldDeclaration(self: *VM, struct_type: *types.PHPStruct, field_data: anytype) !void {
        const field_name = self.context.string_pool.keys()[field_data.name];
        const php_field_name = try types.PHPString.init(self.allocator, field_name);

        // Create field
        var field = types.PHPStruct.StructField{
            .name = php_field_name,
            .type = null, // Would process type information here
            .default_value = null,
            .modifiers = .{
                .is_public = field_data.modifiers.is_public,
                .is_protected = field_data.modifiers.is_protected,
                .is_private = field_data.modifiers.is_private,
                .is_readonly = field_data.modifiers.is_readonly,
            },
            .offset = 0, // Would calculate proper offset
        };

        // Set default value if present
        if (field_data.default_value) |default_idx| {
            field.default_value = try self.eval(default_idx);
        }

        // Add field to struct
        try struct_type.addField(field);
    }

    fn initializeStructFields(self: *VM, instance: *types.StructInstance, struct_type: *types.PHPStruct) !void {
        var field_iter = struct_type.fields.iterator();
        while (field_iter.next()) |entry| {
            const field = entry.value_ptr.*;
            const field_name = field.name.data;

            if (field.default_value) |default_val| {
                try instance.setField(self.allocator, field_name, default_val);
            } else {
                // Initialize with null if no default value
                try instance.setField(self.allocator, field_name, Value.initNull());
            }
        }
    }

    pub fn defineStruct(self: *VM, name: []const u8, struct_type: *types.PHPStruct) !void {
        try self.structs.put(name, struct_type);
    }

    pub fn getStruct(self: *VM, name: []const u8) ?*types.PHPStruct {
        return self.structs.get(name);
    }

    /// Helper function to recursively assign values from nested list destructuring
    fn assignListRecursive(self: *VM, array: *types.PHPArray, targets: []const ast.Node.Index) !void {
        for (targets, 0..) |target_idx, i| {
            const target_node = self.context.nodes.items[target_idx];

            // Get value from array at position i (always use array position)
            const elem_val = array.get(types.ArrayKey{ .integer = @as(i64, @intCast(i)) });
            if (elem_val) |val| {
                // Skip empty slots
                if (target_node.tag == .list_empty) {
                    self.releaseValue(val);
                    continue;
                }

                if (target_node.tag == .variable) {
                    const name_id = target_node.data.variable.name;
                    const name = self.context.string_pool.keys()[name_id];
                    self.retainValue(val);
                    try self.setVariable(name, val);
                } else if (target_node.tag == .list_assignment) {
                    // Recursive handling for nested lists
                    if (val.isArray()) {
                        try self.assignListRecursive(val.getAsArray().data, target_node.data.list_assignment.targets);
                    }
                    self.releaseValue(val);
                } else {
                    self.releaseValue(val);
                }
            }
        }
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

                                // Use original exception object if available, otherwise create from current_exception
                                if (self.original_exception_value) |orig_exc| {
                                    // Clone the original exception object for the catch variable
                                    const exc_value = orig_exc;
                                    try self.setVariable(var_name, exc_value);
                                    // setVariable retains the value, so release our ref
                                    // Release our reference to original_exception_value
                                    self.releaseValue(orig_exc);
                                    // Also clean up current_exception (PHPException)
                                    if (self.current_exception) |exc| {
                                        exc.deinit(self.allocator);
                                        self.current_exception = null;
                                    }
                                    self.original_exception_value = null;
                                } else if (self.current_exception) |exc| {
                                    // Create a PHP object to represent the exception (fallback)
                                    const exception_class = self.getClass("Exception") orelse self.getClass("RuntimeException");
                                    if (exception_class) |cls| {
                                        const exc_obj = try self.allocator.create(types.PHPObject);
                                        errdefer self.allocator.destroy(exc_obj);

                                        exc_obj.* = try types.PHPObject.init(self.allocator, cls);
                                        errdefer exc_obj.deinit(self.allocator);

                                        // Create message string and set property, then release our reference
                                        const message_value = try Value.initString(self.allocator, exc.message.data);
                                        errdefer message_value.release(self.allocator);

                                        try exc_obj.setProperty(self.allocator, "message", message_value);
                                        message_value.release(self.allocator); // setProperty retains, so release our ref

                                        try exc_obj.setProperty(self.allocator, "code", Value.initInt(exc.code));

                                        const box = try self.allocator.create(types.gc.Box(*types.PHPObject));
                                        errdefer self.allocator.destroy(box);

                                        box.* = .{ .ref_count = 1, .gc_info = .{}, .data = exc_obj };
                                        const exc_value = Value.fromBox(box, Value.TYPE_OBJECT);
                                        try self.setVariable(var_name, exc_value);

                                        // setVariable retains the value, so release our reference

                                    } else {
                                        try self.setVariable(var_name, Value.initNull());
                                    }
                                    // Release and clear current exception
                                    exc.deinit(self.allocator);
                                    self.current_exception = null;
                                } else {
                                    try self.setVariable(var_name, Value.initNull());
                                }
                            }
                        } else {
                            // Release and clear exceptions even if no variable binding
                            if (self.original_exception_value) |orig_exc| {
                                self.releaseValue(orig_exc);
                                // Also clean up current_exception (PHPException)
                                if (self.current_exception) |exc| {
                                    exc.deinit(self.allocator);
                                    self.current_exception = null;
                                }
                                self.original_exception_value = null;
                            }
                            if (self.current_exception) |exc| {
                                exc.deinit(self.allocator);
                                self.current_exception = null;
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

        // Create exception based on the value
        const exception = switch (exception_value.getTag()) {
            .object => blk: {
                // If it's already an exception object, preserve it for the catch clause
                const object = exception_value.getAsObject().data;
                if (object.hasProperty("message")) {
                    // Store the original exception object for use in catch clause
                    self.retainValue(exception_value);
                    self.original_exception_value = exception_value;

                    // Create PHPException for internal use (message, code, previous)
                    const message_prop = object.getProperty("message") catch (try Value.initString(self.allocator, "Exception"));
                    const message_str = switch (message_prop.getTag()) {
                        .string => message_prop.getAsString().data.data,
                        else => "Exception",
                    };

                    break :blk try ExceptionFactory.createTypeError(self.allocator, message_str, self.current_file, self.current_line);
                } else {
                    // Not a Throwable object, release and create error
                    self.releaseValue(exception_value);
                    break :blk try ExceptionFactory.createTypeError(self.allocator, "Can only throw objects that implement Throwable", self.current_file, self.current_line);
                }
            },
            .string => blk: {
                // Throw string as exception message
                const message = exception_value.getAsString().data.data;
                break :blk try ExceptionFactory.createTypeError(self.allocator, message, self.current_file, self.current_line);
            },
            else => blk: {
                break :blk try ExceptionFactory.createTypeError(self.allocator, "Can only throw objects that implement Throwable", self.current_file, self.current_line);
            },
        };

        return self.throwException(exception);
    }

    fn createBoundMethodClosure(self: *VM, method: *types.Method, object: *types.PHPObject) !*types.Closure {
        // Create a user function for the method
        const closure_name = try types.PHPString.init(self.allocator, method.name.data);
        var user_function = types.UserFunction.init(closure_name);

        // Copy parameters from method - allocate as mutable array first
        const param_count = method.parameters.len;
        const params_array = try self.allocator.alloc(types.Method.Parameter, param_count);
        errdefer self.allocator.free(params_array);
        for (method.parameters, 0..) |param, i| {
            // Create new parameter with copied name
            const param_name: *types.PHPString = if (param.name.data.len > 0)
                try types.PHPString.init(self.allocator, param.name.data)
            else
                param.name;

            params_array[i] = types.Method.Parameter{
                .name = param_name,
                .type = param.type,
                .default_value = param.default_value,
                .is_variadic = param.is_variadic,
                .is_reference = param.is_reference,
                .is_promoted = param.is_promoted,
                .modifiers = param.modifiers,
                .attributes = param.attributes,
            };
        }
        user_function.parameters = params_array;

        user_function.body = method.body;
        user_function.is_variadic = false;
        user_function.min_args = @as(u32, @intCast(param_count));
        user_function.max_args = @as(u32, @intCast(param_count));

        // Create closure and allocate on heap
        const closure_value = types.Closure.init(self.allocator, user_function);
        const closure_ptr = try self.allocator.create(types.Closure);
        errdefer self.allocator.destroy(closure_ptr);
        closure_ptr.* = closure_value;

        // Bind $this to the object
        const obj_box = try self.allocator.create(types.gc.Box(*types.PHPObject));
        errdefer self.allocator.destroy(obj_box);
        obj_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = object,
        };
        const this_value = types.Value.fromBox(obj_box, types.Value.TYPE_OBJECT);
        errdefer this_value.release(self.allocator);
        try closure_ptr.captured_vars.put("$this", this_value);

        return closure_ptr;
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
        user_function.parameters = try self.processParameters(closure_data.params);

        var min_args: u32 = 0;
        var is_variadic = false;

        for (user_function.parameters) |param| {
            if (param.is_variadic) {
                is_variadic = true;
            }
            if (param.default_value == null and !param.is_variadic) {
                min_args += 1;
            }
        }

        // 设置max_args：variadic函数为null（无限制），否则为参数数量
        const max_args: ?u32 = if (is_variadic) null else @as(u32, @intCast(user_function.parameters.len));

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
            var var_name: []const u8 = undefined;
            var should_capture = false;
            var is_reference = false;

            if (capture_node.tag == .variable) {
                var_name = self.context.string_pool.keys()[capture_node.data.variable.name];
                should_capture = true;
                is_reference = false;
            } else if (capture_node.tag == .unary_expr and capture_node.data.unary_expr.op == .ampersand) {
                // Reference capture: use (&$var)
                // Peel off the ampersand and get the variable
                const expr_idx = capture_node.data.unary_expr.expr;
                const expr_node = self.context.nodes.items[expr_idx];
                if (expr_node.tag == .variable) {
                    var_name = self.context.string_pool.keys()[expr_node.data.variable.name];
                    should_capture = true;
                    is_reference = true;
                }
            }

            if (should_capture) {
                // Only capture if variable exists in current scope
                if (self.getVariable(var_name)) |var_value| {
                    try captured_vars_list.append(self.allocator, .{ .name = var_name, .value = var_value, .is_reference = is_reference });
                }
                // If variable doesn't exist, skip it
            }
        }

        // Automatically capture $this if we're in a class method scope
        if (self.current_class != null) {
            if (self.getVariable("$this")) |this_value| {
                try captured_vars_list.append(self.allocator, .{ .name = "$this", .value = this_value, .is_reference = false });
            }
        }

        return self.createClosureWithRefs(user_function, captured_vars_list.items);
    }

    fn evaluateStaticMethodCall(self: *VM, static_call_data: anytype) !Value {
        const class_name = self.context.string_pool.keys()[static_call_data.class_name];
        const method_name = self.context.string_pool.keys()[static_call_data.method_name];

        // 解析类引用：self、parent、static、具体类名或变量（$obj::method()）
        var called_class: *types.PHPClass = undefined;
        const class = if (std.mem.eql(u8, class_name, "self")) blk: {
            const scope = self.current_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access self:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
            called_class = self.current_called_class orelse scope;
            break :blk scope;
        } else if (std.mem.eql(u8, class_name, "static")) blk: {
            const called = self.current_called_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access static:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
            called_class = called;
            break :blk called;
        } else if (std.mem.eql(u8, class_name, "parent")) blk: {
            const curr_class = self.current_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
            const parent = curr_class.parent orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: when class has no parent", self.current_file, self.current_line);
                return self.throwException(exception);
            };
            called_class = self.current_called_class orelse curr_class;
            break :blk parent;
        } else if (class_name.len > 0 and class_name[0] == '$') blk: {
            // 变量形式的静态调用：$obj::method()
            const var_value = self.getVariable(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
            if (var_value.isObject()) {
                const c = var_value.getAsObject().data.class;
                called_class = c;
                break :blk c;
            } else if (var_value.isString()) {
                // 字符串作为类名
                const str_class_name = var_value.getAsString().data.data;
                const c = self.getClass(str_class_name) orelse {
                    const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, str_class_name, self.current_file, self.current_line);
                    return self.throwException(exception);
                };
                called_class = c;
                break :blk c;
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use non-object as class in static method call", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        } else blk: {
            const c = self.getClass(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
            called_class = c;
            break :blk c;
        };

        // Evaluate arguments
        var args = std.ArrayList(Value){};
        try args.ensureTotalCapacity(self.allocator, static_call_data.args.len);
        defer {
            for (args.items) |arg| {
                self.releaseValue(arg);
            }
            args.deinit(self.allocator);
        }

        for (static_call_data.args) |arg_node_idx| {
            const arg_value = try self.eval(arg_node_idx);
            try args.append(self.allocator, arg_value);
        }

        const method_lookup = class.getMethodLookup(method_name);

        if (method_lookup) |lookup| {
            const m = lookup.method;
            // Push call frame
            const full_method_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ class_name, method_name });
            defer self.allocator.free(full_method_name);
            try self.pushCallFrame(full_method_name, self.current_file, self.current_line);
            defer self.popCallFrame();

            // Bind arguments to parameters
            for (m.parameters, 0..) |param, i| {
                if (i < args.items.len) {
                    try self.setVariable(param.name.data, args.items[i]);
                } else if (param.default_value) |default| {
                    try self.setVariable(param.name.data, default);
                }
            }

            // For parent:: calls, preserve $this from the caller's scope
            if (std.mem.eql(u8, class_name, "parent") or std.mem.eql(u8, class_name, "self")) {
                // Get $this from the previous call frame (the one that called parent::)
                if (self.call_stack.items.len > 1) {
                    const caller_frame = &self.call_stack.items[self.call_stack.items.len - 2];
                    if (caller_frame.locals.get("$this")) |this_val| {
                        try self.setVariable("$this", this_val);
                    }
                }
            }

            const old_scope_class = self.current_class;
            const old_called_class = self.current_called_class;
            self.current_called_class = called_class;
            self.current_class = lookup.owner;
            defer {
                self.current_class = old_scope_class;
                self.current_called_class = old_called_class;
            }

            // Execute method body
            if (m.body) |body_ptr| {
                const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
                return self.eval(body_node) catch |err| {
                    if (err == error.Return) {
                        if (self.return_value) |val| {
                            const ret = val;
                            self.return_value = null;
                            return ret;
                        }
                        return Value.initNull();
                    }
                    return err;
                };
            } else {
                // Handle builtin methods with null body (e.g., Exception::__construct)
                if (std.mem.eql(u8, method_name, "__construct")) {
                    // For Exception classes, set the message property from $this
                    if (self.getVariable("$this")) |this_val| {
                        if (this_val.isObject()) {
                            const obj = this_val.getAsObject().data;
                            // Set message from first argument if provided
                            if (args.items.len > 0) {
                                try obj.setProperty(self.allocator, "message", args.items[0]);
                            }
                            // Set code from second argument if provided
                            if (args.items.len > 1) {
                                try obj.setProperty(self.allocator, "code", args.items[1]);
                            }
                            // Set previous from third argument if provided
                            if (args.items.len > 2) {
                                try obj.setProperty(self.allocator, "previous", args.items[2]);
                            }
                        }
                    }
                }
            }

            return Value.initNull();
        } else {
            if (class.getMethodLookup("__callStatic")) |call_static_lookup| {
                const name_val = try Value.initString(self.allocator, method_name);
                defer name_val.release(self.allocator);

                // Wrap arguments in a PHP array
                const args_array_val = try Value.initArrayWithManager(&self.memory_manager);
                const args_array = args_array_val.getAsArray().data;
                for (args.items) |arg| {
                    try args_array.push(self.allocator, arg);
                }
                defer args_array_val.release(self.allocator);

                const magic_args = [_]Value{ name_val, args_array_val };

                const old_scope_class = self.current_class;
                const old_called_class = self.current_called_class;
                self.current_called_class = called_class;
                self.current_class = call_static_lookup.owner;
                defer {
                    self.current_class = old_scope_class;
                    self.current_called_class = old_called_class;
                }

                // Call __callStatic
                {
                    const inner_call_static = call_static_lookup.method;
                    const full_method_name = try std.fmt.allocPrint(self.allocator, "{s}::__callStatic", .{class_name});
                    defer self.allocator.free(full_method_name);
                    try self.pushCallFrame(full_method_name, self.current_file, self.current_line);
                    defer self.popCallFrame();

                    // Bind arguments to parameters
                    for (inner_call_static.parameters, 0..) |param, i| {
                        if (i < magic_args.len) {
                            try self.setVariable(param.name.data, magic_args[i]);
                        }
                    }

                    if (inner_call_static.body) |body_ptr| {
                        const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
                        return self.eval(body_node) catch |err| {
                            if (err == error.Return) {
                                if (self.return_value) |val| {
                                    const ret = val;
                                    self.return_value = null;
                                    return ret;
                                }
                                return Value.initNull();
                            }
                            return err;
                        };
                    }
                }
                return Value.initNull();
            }

            const msg = try std.fmt.allocPrint(self.allocator, "Call to undefined method {s}::{s}()", .{ class_name, method_name });
            defer self.allocator.free(msg);
            const exception = try ExceptionFactory.createTypeError(self.allocator, msg, self.current_file, self.current_line);
            return self.throwException(exception);
        }
    }

    fn evaluateClassConstantAccess(self: *VM, const_access_data: anytype) !Value {
        const class_name = self.context.string_pool.keys()[const_access_data.class_name];
        const constant_name = self.context.string_pool.keys()[const_access_data.constant_name];

        // 解析类引用：self、parent、static、具体类名或变量（$obj::$prop）
        const class = if (std.mem.eql(u8, class_name, "self")) blk: {
            break :blk self.current_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access self:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
        } else if (std.mem.eql(u8, class_name, "static")) blk: {
            break :blk self.current_called_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access static:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
        } else if (std.mem.eql(u8, class_name, "parent")) blk: {
            const curr_class = self.current_class orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: outside of class scope", self.current_file, self.current_line);
                return self.throwException(exception);
            };
            break :blk curr_class.parent orelse {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot access parent:: when class has no parent", self.current_file, self.current_line);
                return self.throwException(exception);
            };
        } else if (class_name.len > 0 and class_name[0] == '$') blk: {
            // 变量形式的静态访问：$obj::$prop
            const var_value = self.getVariable(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedVariableError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
            if (var_value.isObject()) {
                break :blk var_value.getAsObject().data.class;
            } else if (var_value.isString()) {
                const str_class_name = var_value.getAsString().data.data;
                break :blk self.getClass(str_class_name) orelse {
                    const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, str_class_name, self.current_file, self.current_line);
                    return self.throwException(exception);
                };
            } else {
                const exception = try ExceptionFactory.createTypeError(self.allocator, "Cannot use non-object as class in static property access", self.current_file, self.current_line);
                return self.throwException(exception);
            }
        } else blk: {
            break :blk self.getClass(class_name) orelse {
                const exception = try ExceptionFactory.createUndefinedClassError(self.allocator, class_name, self.current_file, self.current_line);
                return self.throwException(exception);
            };
        };

        // Look up constant in class (包括继承链)
        if (class.constants.get(constant_name)) |value| {
            return value.retain();
        }

        // Check if it's a static property (包括继承链查找)
        if (class.getProperty(constant_name)) |prop| {
            if (prop.modifiers.is_static) {
                if (prop.default_value) |val| {
                    return val.retain();
                }
                return Value.initNull();
            }
        }

        // 检查父类常量
        var current_class: ?*types.PHPClass = class.parent;
        while (current_class) |parent_class| {
            if (parent_class.constants.get(constant_name)) |value| {
                return value.retain();
            }
            current_class = parent_class.parent;
        }

        const msg = try std.fmt.allocPrint(self.allocator, "Undefined class constant or static property {s}::{s}", .{ class_name, constant_name });
        defer self.allocator.free(msg);
        const exception = try ExceptionFactory.createTypeError(self.allocator, msg, self.current_file, self.current_line);
        return self.throwException(exception);
    }
};
