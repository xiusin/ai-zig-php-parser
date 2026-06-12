// Extension 模块统一入口
// 用于解决 Zig 0.15.2 模块系统的导入问题

pub const api = @import("api.zig");
pub const registry = @import("registry.zig");

// 导出常用类型
pub const ExtensionRegistry = registry.ExtensionRegistry;
pub const ExtensionFunction = api.ExtensionFunction;
pub const ExtensionClass = api.ExtensionClass;
pub const ExtensionValue = api.ExtensionValue;
pub const SyntaxHooks = api.SyntaxHooks;
