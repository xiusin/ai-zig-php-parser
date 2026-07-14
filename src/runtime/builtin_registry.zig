//! ============================================================================
//! 内置函数注册表 (Builtin Function Registry)
//! ============================================================================
//!
//! @deprecated 此文件已废弃，请使用 fn_dispatch.zig 替代
//! 保留 BuiltinRegistry 结构体和 Category 枚举以兼容现有代码
//! BuiltinError 已迁移到 fn_dispatch.BuiltinError
//!
//! 功能：管理所有PHP内置函数的注册、分类和调用
//!
//! 主要组件：
//! - Category: 函数分类枚举（时间、数学、随机数、字符串、数组等）
//! - BuiltinFunction: 内置函数定义结构
//! - BuiltinRegistry: 函数注册表，支持按名称和分类查询
//!
//! 需求：支持PHP标准库函数的统一管理和高效调用
//! ============================================================================
const time_compat = @import("time_compat.zig");

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const fn_dispatch_mod = @import("fn_dispatch.zig");

// Forward declaration for VM - will be resolved at compile time
const VM = anyopaque;

/// 内置函数分类
/// Category-based organization for builtin functions
pub const Category = enum {
    time,
    math,
    random,
    string,
    array,
    bigdecimal,
    concurrency,
    http,
    io,
    reflection,
    variable,
    error_handling,
    database,
    misc,

    pub fn toString(self: Category) []const u8 {
        return switch (self) {
            .time => "time",
            .math => "math",
            .random => "random",
            .string => "string",
            .array => "array",
            .bigdecimal => "bigdecimal",
            .concurrency => "concurrency",
            .http => "http",
            .io => "io",
            .reflection => "reflection",
            .variable => "variable",
            .error_handling => "error_handling",
            .database => "database",
            .misc => "misc",
        };
    }
};

/// Error types for builtin function operations
/// 已迁移到 fn_dispatch.BuiltinError，此处重导出以兼容现有代码
pub const BuiltinError = fn_dispatch_mod.BuiltinError;

/// Builtin function definition with metadata
pub const BuiltinFunction = struct {
    name: []const u8,
    category: Category,
    handler: *const fn (*anyopaque, []const Value) anyerror!Value,
    min_args: u8,
    max_args: u8, // 255 means unlimited
    is_variadic: bool,
    description: []const u8,

    pub fn init(
        name: []const u8,
        category: Category,
        handler: *const fn (*anyopaque, []const Value) anyerror!Value,
        min_args: u8,
        max_args: u8,
        description: []const u8,
    ) BuiltinFunction {
        return BuiltinFunction{
            .name = name,
            .category = category,
            .handler = handler,
            .min_args = min_args,
            .max_args = max_args,
            .is_variadic = max_args == 255,
            .description = description,
        };
    }

    /// 调用内置函数 — 参数校验已由 fn_dispatch.validateArgs 统一处理
    /// 此方法直接调用 handler，不再重复校验参数数量
    /// 保留错误转换逻辑（DivisionByZero, MathDomainError, InvalidArgumentType）
    pub fn call(self: *const BuiltinFunction, vm: *anyopaque, args: []const Value) !Value {
        // Call the handler with error handling
        return self.handler(vm, args) catch |err| {
            // Convert specific errors to appropriate exceptions
            switch (err) {
                BuiltinError.DivisionByZero => {
                    const exception = try ExceptionFactory.createRuntimeError(
                        vm.allocator,
                        "Division by zero",
                        vm.current_file,
                        vm.current_line,
                    );
                    _ = try vm.throwException(exception);
                    return err;
                },
                BuiltinError.MathDomainError => {
                    const exception = try ExceptionFactory.createRuntimeError(
                        vm.allocator,
                        "Math domain error",
                        vm.current_file,
                        vm.current_line,
                    );
                    _ = try vm.throwException(exception);
                    return err;
                },
                BuiltinError.InvalidArgumentType => {
                    const exception = try ExceptionFactory.createTypeError(
                        vm.allocator,
                        "Invalid argument type",
                        vm.current_file,
                        vm.current_line,
                    );
                    _ = try vm.throwException(exception);
                    return err;
                },
                else => return err,
            }
        };
    }
};

/// Central registry for all builtin functions with category-based organization
pub const BuiltinRegistry = struct {
    functions: std.StringHashMap(*const BuiltinFunction),
    categories: std.EnumMap(Category, std.ArrayList(*const BuiltinFunction)),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BuiltinRegistry {
        var categories = std.EnumMap(Category, std.ArrayList(*const BuiltinFunction)){};

        // Initialize category lists
        inline for (@typeInfo(Category).@"enum".fields) |field| {
            const category = @field(Category, field.name);
            categories.put(category, std.ArrayList(*const BuiltinFunction).empty);
        }

        return BuiltinRegistry{
            .functions = std.StringHashMap(*const BuiltinFunction).init(allocator),
            .categories = categories,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BuiltinRegistry) void {
        self.functions.deinit();

        // Deinit category lists
        var category_iter = self.categories.iterator();
        while (category_iter.next()) |entry| {
            entry.value.deinit(self.allocator);
        }
    }

    /// Register a builtin function
    pub fn register(self: *BuiltinRegistry, func: *const BuiltinFunction) !void {
        // Add to main function map
        try self.functions.put(func.name, func);

        // Add to category list
        if (self.categories.getPtr(func.category)) |category_list| {
            try category_list.append(self.allocator, func);
        }
    }

    /// Call a builtin function by name
    /// 参数校验由 fn_dispatch.validateArgs 统一处理
    pub fn call(self: *BuiltinRegistry, vm: *anyopaque, name: []const u8, args: []const Value) !Value {
        const func = self.functions.get(name) orelse {
            const exception = try ExceptionFactory.createRuntimeError(
                vm.allocator,
                "Undefined function",
                vm.current_file,
                vm.current_line,
            );
            _ = try vm.throwException(exception);
            return BuiltinError.FunctionNotFound;
        };

        // 统一参数校验 — 通过 fn_dispatch_mod 的 O(1) 查找获取 id，然后 validateArgs
        if (fn_dispatch_mod.lookup(name)) |id| {
            fn_dispatch_mod.validateArgs(id, args.len) catch |err| {
                const meta = fn_dispatch_mod.getMeta(id).?;
                const expected = switch (err) {
                    error.TooFewArguments => meta.min_args,
                    error.TooManyArguments => meta.max_args,
                };
                const exception = try ExceptionFactory.createArgumentCountError(
                    vm.allocator,
                    expected,
                    @intCast(args.len),
                    name,
                    "builtin",
                    0,
                );
                _ = try vm.throwException(exception);
                return BuiltinError.ArgumentCountMismatch;
            };
        }

        return func.call(vm, args);
    }

    /// Check if a function exists
    pub fn exists(self: *BuiltinRegistry, name: []const u8) bool {
        return self.functions.contains(name);
    }

    /// Get function by name
    pub fn getFunction(self: *BuiltinRegistry, name: []const u8) ?*const BuiltinFunction {
        return self.functions.get(name);
    }

    /// Get all functions in a category
    pub fn getFunctionsByCategory(self: *BuiltinRegistry, category: Category) []const *const BuiltinFunction {
        if (self.categories.getPtr(category)) |category_list| {
            return category_list.items;
        }
        return &[_]*const BuiltinFunction{};
    }

    /// Get all function names
    pub fn getAllFunctionNames(self: *BuiltinRegistry, allocator: std.mem.Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.functions.count());
        var i: usize = 0;
        var iterator = self.functions.iterator();
        while (iterator.next()) |entry| {
            names[i] = entry.key_ptr.*;
            i += 1;
        }
        return names;
    }

    /// Get function count by category
    pub fn getCategoryCount(self: *BuiltinRegistry, category: Category) usize {
        if (self.categories.getPtr(category)) |category_list| {
            return category_list.items.len;
        }
        return 0;
    }

    /// Get total function count
    pub fn getTotalCount(self: *BuiltinRegistry) usize {
        return self.functions.count();
    }
};

// Test functions for demonstration (will be replaced by actual implementations)
fn testTimeFn(vm: *anyopaque, args: []const Value) !Value {
    _ = vm;
    _ = args;
    return Value.initInt(time_compat.timestamp());
}

fn testMathFn(vm: *anyopaque, args: []const Value) !Value {
    _ = vm;
    if (args.len != 1) return BuiltinError.ArgumentCountMismatch;
    if (args[0].getTag() != .integer and args[0].getTag() != .float) {
        return BuiltinError.InvalidArgumentType;
    }

    const val = if (args[0].getTag() == .integer)
        @as(f64, @floatFromInt(args[0].asInt()))
    else
        args[0].asFloat();

    return Value.initFloat(@abs(val));
}

// Example builtin functions for testing
pub const BUILTIN_FUNCTIONS = [_]BuiltinFunction{
    BuiltinFunction.init("time", .time, testTimeFn, 0, 0, "Returns current Unix timestamp"),
    BuiltinFunction.init("abs", .math, testMathFn, 1, 1, "Returns absolute value of a number"),
};

/// Initialize and populate the builtin registry with core functions
pub fn initializeRegistry(allocator: std.mem.Allocator) !BuiltinRegistry {
    var registry = BuiltinRegistry.init(allocator);

    // Register core builtin functions
    for (BUILTIN_FUNCTIONS) |*func| {
        try registry.register(func);
    }

    return registry;
}

test "BuiltinRegistry basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var registry = BuiltinRegistry.init(allocator);
    defer registry.deinit();

    // Test registration
    const test_func = BuiltinFunction.init("test", .misc, testTimeFn, 0, 0, "Test function");
    try registry.register(&test_func);

    // Test existence check
    try testing.expect(registry.exists("test"));
    try testing.expect(!registry.exists("nonexistent"));

    // Test function retrieval
    const retrieved = registry.getFunction("test");
    try testing.expect(retrieved != null);
    try testing.expectEqualStrings("test", retrieved.?.name);

    // Test category functionality
    try testing.expect(registry.getCategoryCount(.misc) == 1);
    try testing.expect(registry.getTotalCount() == 1);
}

test "BuiltinFunction argument validation" {
    const testing = std.testing;

    const test_func = BuiltinFunction.init("test", .misc, testMathFn, 1, 1, "Test function");

    // Test argument count validation
    try testing.expect(test_func.min_args == 1);
    try testing.expect(test_func.max_args == 1);
    try testing.expect(!test_func.is_variadic);
}
