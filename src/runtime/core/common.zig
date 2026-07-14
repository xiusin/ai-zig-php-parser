//! 核心函数公共接口定义
//!
//! 提供统一的类型抽象，使核心函数实现与具体的 Value 类型解耦。
//! 通过 VTable 机制实现零成本抽象，编译时内联优化。
//!
//! @ownership NON-OWNING (CoreContext 不拥有 allocator)
//! @thread-safety ISOLATED (每个调用独立)

const std = @import("std");
const Allocator = std.mem.Allocator;

/// 核心函数执行上下文
/// 包含执行所需的公共资源
pub const CoreContext = struct {
    allocator: Allocator,

    /// 创建上下文
    pub fn init(allocator: Allocator) CoreContext {
        return .{ .allocator = allocator };
    }
};

/// 核心值类型 - 通过 VTable 实现多态
/// 使用 comptime 泛型避免运行时开销
pub fn CoreValue(comptime T: type) type {
    return struct {
        data: T,

        const Self = @This();

        /// 类型检查
        pub fn isNull(self: Self) bool {
            return self.data.isNull();
        }

        pub fn isBool(self: Self) bool {
            return self.data.isBool();
        }

        pub fn isInt(self: Self) bool {
            return self.data.isInt();
        }

        pub fn isFloat(self: Self) bool {
            return self.data.isFloat();
        }

        pub fn isString(self: Self) bool {
            return self.data.isString();
        }

        pub fn isArray(self: Self) bool {
            return self.data.isArray();
        }

        /// 数据提取
        pub fn asBool(self: Self) bool {
            return self.data.asBool();
        }

        pub fn asInt(self: Self) i64 {
            return self.data.asInt();
        }

        pub fn asFloat(self: Self) f64 {
            return self.data.asFloat();
        }

        /// 类型转换
        pub fn toBool(self: Self) bool {
            return self.data.toBool();
        }

        pub fn toInt(self: Self) i64 {
            return self.data.toInt();
        }

        pub fn toFloat(self: Self) f64 {
            return self.data.toFloat();
        }

        /// 获取原始数据
        pub fn getRaw(self: Self) T {
            return self.data;
        }
    };
}

/// 字符串操作结果类型
pub const StringResult = union(enum) {
    /// 静态字符串（无需释放）
    static: []const u8,
    /// 动态分配的字符串（需要释放）
    allocated: []u8,

    /// 获取字符串内容
    pub fn get(self: StringResult) []const u8 {
        return switch (self) {
            .static => |s| s,
            .allocated => |s| s,
        };
    }

    /// 释放动态分配的内存
    pub fn deinit(self: *StringResult, allocator: Allocator) void {
        switch (self.*) {
            .allocated => |s| allocator.free(s),
            .static => {},
        }
    }
};

/// 数值结果类型（支持整数和浮点数）
pub const NumberResult = union(enum) {
    int: i64,
    float: f64,

    pub fn toInt(self: NumberResult) i64 {
        return switch (self) {
            .int => |i| i,
            .float => |f| @intFromFloat(f),
        };
    }

    pub fn toFloat(self: NumberResult) f64 {
        return switch (self) {
            .int => |i| @floatFromInt(i),
            .float => |f| f,
        };
    }
};

/// 核心函数错误类型
pub const CoreError = error{
    InvalidArgument,
    InvalidType,
    OutOfMemory,
    IndexOutOfBounds,
    DivisionByZero,
    MathDomainError,
    StringTooLarge,
    InvalidEncoding,
    PatternError,
};

test "CoreContext basic" {
    const allocator = std.testing.allocator;
    const ctx = CoreContext.init(allocator);
    try std.testing.expect(ctx.allocator.ptr == allocator.ptr);
}

test "StringResult static" {
    var result = StringResult{ .static = "hello" };
    try std.testing.expectEqualStrings("hello", result.get());
    result.deinit(std.testing.allocator);
}

test "StringResult allocated" {
    const allocator = std.testing.allocator;
    const data = try allocator.alloc(u8, 5);
    @memcpy(data, "hello");

    var result = StringResult{ .allocated = data };
    try std.testing.expectEqualStrings("hello", result.get());
    result.deinit(allocator);
}
