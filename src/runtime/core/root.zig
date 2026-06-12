//! 核心函数库入口模块
//!
//! 提供统一的核心函数导出，供 VM、AOT、JIT 适配器使用。
//! 所有核心函数都是纯函数，与执行模式无关。
//!
//! 架构设计：
//! ```
//! ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
//! │   VM 适配   │  │  AOT 适配   │  │  JIT 适配   │
//! └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
//!        │                │                │
//!        └────────────────┼────────────────┘
//!                         ▼
//!                ┌─────────────────┐
//!                │   核心函数库     │
//!                │  (本模块)       │
//!                └─────────────────┘
//! ```
//!
//! @ownership NON-OWNING
//! @thread-safety ISOLATED

const std = @import("std");

pub const common = @import("common.zig");
pub const string = @import("string_functions.zig");
pub const math = @import("math_functions.zig");
pub const time = @import("time_functions.zig");
pub const types = @import("type_functions.zig");
pub const random = @import("random_functions.zig");
pub const json = @import("json_functions.zig");
pub const vm_adapter = @import("vm_adapter.zig");
pub const aot_adapter = @import("aot_adapter.zig");

pub const CoreContext = common.CoreContext;
pub const CoreError = common.CoreError;
pub const StringResult = common.StringResult;
pub const NumberResult = common.NumberResult;

/// 核心函数版本
pub const VERSION = "1.0.0";

/// 初始化核心库（目前为空操作）
pub fn init() void {}

/// 清理核心库（目前为空操作）
pub fn deinit() void {}

// ============================================================================
// 测试
// ============================================================================

test "core module imports" {
    try std.testing.expect(true);

    _ = common;
    _ = string;
    _ = math;
    _ = time;
    _ = types;
    _ = random;
    _ = json;
}

test "string functions" {
    try std.testing.expectEqual(@as(i64, 5), string.strlen("hello"));
    try std.testing.expect(string.str_contains("hello world", "world"));
}

test "math functions" {
    try std.testing.expectEqual(@as(f64, 4.0), math.ceil(3.1));
    try std.testing.expectEqual(@as(f64, 3.0), math.floor(3.9));
}

test "type functions" {
    try std.testing.expectEqual(@as(i64, 42), types.intval("42", 10));
    try std.testing.expect(types.is_numeric("3.14"));
}

test "time functions" {
    const ts = time.time();
    try std.testing.expect(ts > 0);
}

test "random functions" {
    random.srand(42);
    const r1 = random.rand(1, 100);
    try std.testing.expect(r1 >= 1 and r1 <= 100);
}
