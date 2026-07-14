//! 插件系统
//!
//! 提供可扩展的插件架构，支持动态加载和卸载插件
//!
//! ## 架构
//!
//! ```
//! Plugin Registry -> Plugin Loader -> Plugin Manager
//!        ↓                ↓                ↓
//!  Plugin Info    Dynamic Loading   Lifecycle Management
//!        ↓                ↓                ↓
//!  Dependency     Symbol Resolution  Hook System
//!        ↓                ↓                ↓
//!  Version Check  Plugin Activation  Event Dispatch
//! ```

const std = @import("std");
const Value = @import("types.zig").Value;
const VM = @import("vm.zig").VM;

// ============================================================================
// 常量配置
// ============================================================================

/// 最大插件数
const MAX_PLUGINS: usize = 64;

/// 最大钩子数
const MAX_HOOKS: usize = 256;

/// 插件API版本
const PLUGIN_API_VERSION: u32 = 1;

// ============================================================================
// 插件信息
// ============================================================================

pub const PluginInfo = struct {
    /// 插件名称
    name: []const u8,
    /// 插件版本
    version: Version,
    /// 插件描述
    description: []const u8,
    /// 作者
    author: []const u8,
    /// API版本
    api_version: u32,
    /// 插件类型
    plugin_type: PluginType,
    /// 依赖的插件
    dependencies: std.ArrayListUnmanaged([]const u8),
    /// 提供的函数
    functions: std.ArrayListUnmanaged(BuiltinFunction),
    /// 提供的类
    classes: std.ArrayListUnmanaged(PHPClass),
    /// 初始化函数
    init_fn: ?PluginInitFn,
    /// 关闭函数
    shutdown_fn: ?PluginShutdownFn,

    pub const Version = struct {
        major: u8,
        minor: u8,
        patch: u8,
    };

    pub const PluginType = enum {
        /// 内置插件
        builtin,
        /// 外部插件
        external,
        /// 扩展
        extension,
    };

    pub const BuiltinFunction = struct {
        name: []const u8,
        min_args: u8,
        max_args: u8,
        handler: *const fn (*VM, []const Value) anyerror!Value,
    };

    pub const PHPClass = struct {
        name: []const u8,
        methods: std.ArrayListUnmanaged([]const u8),
        properties: std.ArrayListUnmanaged([]const u8),
    };

    pub const PluginInitFn = *const fn (*PluginSystem) anyerror!void;
    pub const PluginShutdownFn = *const fn (*PluginSystem) void;

    pub fn init(allocator: std.mem.Allocator) PluginInfo {
        return .{
            .name = &.{},
            .version = .{ .major = 0, .minor = 0, .patch = 0 },
            .description = &.{},
            .author = &.{},
            .api_version = PLUGIN_API_VERSION,
            .plugin_type = .external,
            .dependencies = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 },
            .functions = std.ArrayListUnmanaged(BuiltinFunction){ .items = &.{}, .capacity = 0 },
            .classes = std.ArrayListUnmanaged(PHPClass){ .items = &.{}, .capacity = 0 },
            .init_fn = null,
            .shutdown_fn = null,
        };
    }

    pub fn deinit(self: *PluginInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        allocator.free(self.author);

        for (self.dependencies.items) |dep| {
            allocator.free(dep);
        }
        self.dependencies.deinit(allocator);

        for (self.functions.items) |*func| {
            allocator.free(func.name);
        }
        self.functions.deinit(allocator);

        for (self.classes.items) |*cls| {
            allocator.free(cls.name);
            for (cls.methods.items) |method| {
                allocator.free(method);
            }
            cls.methods.deinit(allocator);
            for (cls.properties.items) |prop| {
                allocator.free(prop);
            }
            cls.properties.deinit(allocator);
        }
        self.classes.deinit(allocator);
    }
};

// ============================================================================
// 插件钩子
// ============================================================================

pub const PluginHook = struct {
    /// 钩子名称
    name: []const u8,
    /// 钩子类型
    hook_type: HookType,
    /// 处理器列表
    handlers: std.ArrayListUnmanaged(HookHandler),
    /// 分配器
    allocator: std.mem.Allocator,

    pub const HookType = enum {
        /// 函数调用前
        before_function_call,
        /// 函数调用后
        after_function_call,
        /// 类实例化前
        before_class_instantiation,
        /// 类实例化后
        after_class_instantiation,
        /// GC开始前
        before_gc,
        /// GC结束后
        after_gc,
        /// 错误发生时
        on_error,
        /// 自定义
        custom,
    };

    pub const HookHandler = struct {
        /// 插件名称
        plugin_name: []const u8,
        /// 处理函数
        handler: *const fn (*VM, []const Value) anyerror!Value,
        /// 优先级
        priority: u32,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8, hook_type: HookType) PluginHook {
        return .{
            .name = try allocator.dupe(u8, name),
            .hook_type = hook_type,
            .handlers = std.ArrayListUnmanaged(HookHandler){ .items = &.{}, .capacity = 0 },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginHook) void {
        self.allocator.free(self.name);

        for (self.handlers.items) |*handler| {
            self.allocator.free(handler.plugin_name);
        }
        self.handlers.deinit(self.allocator);
    }

    /// 添加处理器
    pub fn addHandler(self: *PluginHook, plugin_name: []const u8, handler: *const fn (*VM, []const Value) anyerror!Value, priority: u32) !void {
        try self.handlers.append(self.allocator, .{
            .plugin_name = try self.allocator.dupe(u8, plugin_name),
            .handler = handler,
            .priority = priority,
        });

        // 按优先级排序
        std.sort.insertion(HookHandler, self.handlers.items, {}, struct {
            fn compare(_: void, a: HookHandler, b: HookHandler) bool {
                return a.priority < b.priority;
            }
        });
    }

    /// 触发钩子
    pub fn trigger(self: *PluginHook, vm: *VM, args: []const Value) !Value {
        var result = Value.initNull();

        for (self.handlers.items) |handler| {
            result = try handler.handler(vm, args);
        }

        return result;
    }
};

// ============================================================================
// 插件系统
// ============================================================================

pub const PluginSystem = struct {
    /// 已加载的插件
    plugins: std.StringHashMap(Plugin),
    /// 钩子注册表
    hooks: std.StringHashMap(PluginHook),
    /// 插件API
    api: PluginAPI,
    /// 分配器
    allocator: std.mem.Allocator,
    /// 统计信息
    stats: PluginStats,

    const Plugin = struct {
        info: PluginInfo,
        loaded: bool,
        enabled: bool,
        load_time: i64,
    };

    const PluginStats = struct {
        /// 加载的插件数
        loaded_plugins: u64 = 0,
        /// 启用的插件数
        enabled_plugins: u64 = 0,
        /// 注册的函数数
        registered_functions: u64 = 0,
        /// 注册的类数
        registered_classes: u64 = 0,
        /// 触发的钩子数
        triggered_hooks: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) PluginSystem {
        return .{
            .plugins = std.StringHashMap(Plugin).init(allocator),
            .hooks = std.StringHashMap(PluginHook).init(allocator),
            .api = PluginAPI.init(),
            .allocator = allocator,
            .stats = .{},
        };
    }

    pub fn deinit(self: *PluginSystem) void {
        var iter = self.plugins.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.info.deinit(self.allocator);
        }
        self.plugins.deinit();

        var hook_iter = self.hooks.iterator();
        while (hook_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.hooks.deinit(self.allocator);
    }

    /// 加载插件
    pub fn loadPlugin(self: *PluginSystem, info: PluginInfo) !void {
        // 检查插件数量
        if (self.plugins.count() >= MAX_PLUGINS) {
            return error.TooManyPlugins;
        }

        // 检查API版本
        if (info.api_version != PLUGIN_API_VERSION) {
            return error.IncompatibleAPIVersion;
        }

        // 检查依赖
        for (info.dependencies.items) |dep| {
            if (!self.plugins.contains(dep)) {
                return error.DependencyNotFound;
            }
        }

        // 创建插件
        const plugin = Plugin{
            .info = info,
            .loaded = false,
            .enabled = false,
            .load_time = std.time.nanoTimestamp(),
        };

        // 添加到注册表
        try self.plugins.put(info.name, plugin);

        // 调用初始化函数
        if (info.init_fn) |init_fn| {
            try init_fn(self);
        }

        // 标记为已加载
        if (self.plugins.get(info.name)) |p| {
            p.loaded = true;
            p.enabled = true;
        }

        self.stats.loaded_plugins += 1;
        self.stats.enabled_plugins += 1;

        // 注册函数
        for (info.functions.items) |func| {
            try self.api.registerFunction(func.name, func.min_args, func.max_args, func.handler);
            self.stats.registered_functions += 1;
        }

        // 注册类
        for (info.classes.items) |cls| {
            try self.api.registerClass(cls.name);
            self.stats.registered_classes += 1;
        }
    }

    /// 卸载插件
    pub fn unloadPlugin(self: *PluginSystem, plugin_name: []const u8) !void {
        const plugin = self.plugins.get(plugin_name) orelse {
            return error.PluginNotFound;
        };

        // 调用关闭函数
        if (plugin.info.shutdown_fn) |shutdown_fn| {
            shutdown_fn(self);
        }

        // 注销函数
        for (plugin.info.functions.items) |func| {
            try self.api.unregisterFunction(func.name);
            self.stats.registered_functions -= 1;
        }

        // 注销类
        for (plugin.info.classes.items) |cls| {
            try self.api.unregisterClass(cls.name);
            self.stats.registered_classes -= 1;
        }

        // 从注册表移除
        _ = self.plugins.remove(plugin_name);

        self.stats.loaded_plugins -= 1;
        self.stats.enabled_plugins -= 1;
    }

    /// 启用插件
    pub fn enablePlugin(self: *PluginSystem, plugin_name: []const u8) !void {
        const plugin = self.plugins.get(plugin_name) orelse {
            return error.PluginNotFound;
        };

        if (plugin.loaded and !plugin.enabled) {
            if (self.plugins.get(plugin_name)) |p| {
                p.enabled = true;
            }
            self.stats.enabled_plugins += 1;
        }
    }

    /// 禁用插件
    pub fn disablePlugin(self: *PluginSystem, plugin_name: []const u8) !void {
        const plugin = self.plugins.get(plugin_name) orelse {
            return error.PluginNotFound;
        };

        if (plugin.enabled) {
            if (self.plugins.get(plugin_name)) |p| {
                p.enabled = false;
            }
            self.stats.enabled_plugins -= 1;
        }
    }

    /// 注册钩子
    pub fn registerHook(self: *PluginSystem, hook_name: []const u8, hook_type: PluginHook.HookType) !void {
        if (self.hooks.count() >= MAX_HOOKS) {
            return error.TooManyHooks;
        }

        const hook = try PluginHook.init(self.allocator, hook_name, hook_type);
        try self.hooks.put(hook_name, hook);
    }

    /// 添加钩子处理器
    pub fn addHookHandler(
        self: *PluginSystem,
        hook_name: []const u8,
        plugin_name: []const u8,
        handler: *const fn (*VM, []const Value) anyerror!Value,
        priority: u32,
    ) !void {
        const hook = self.hooks.get(hook_name) orelse {
            return error.HookNotFound;
        };

        try hook.addHandler(plugin_name, handler, priority);
    }

    /// 触发钩子
    pub fn triggerHook(self: *PluginSystem, hook_name: []const u8, vm: *VM, args: []const Value) !Value {
        const hook = self.hooks.get(hook_name) orelse {
            return Value.initNull();
        };

        self.stats.triggered_hooks += 1;
        return try hook.trigger(vm, args);
    }

    /// 获取插件API
    pub fn getAPI(self: *PluginSystem) *PluginAPI {
        return &self.api;
    }

    /// 获取统计信息
    pub fn getStats(self: *PluginSystem) PluginStats {
        return self.stats;
    }

    /// 列出所有插件
    pub fn listPlugins(self: *PluginSystem) !std.ArrayList([]const u8) {
        var plugins = std.ArrayList([]const u8).init(self.allocator);

        var iter = self.plugins.iterator();
        while (iter.next()) |entry| {
            try plugins.append(try self.allocator.dupe(u8, entry.key_ptr.*));
        }

        return plugins;
    }
};

// ============================================================================
// 插件API
// ============================================================================

pub const PluginAPI = struct {
    /// 注册的函数
    functions: std.StringHashMap(BuiltinFunction),
    /// 注册的类
    classes: std.StringHashMap(PHPClass),
    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init() PluginAPI {
        return .{
            .functions = std.StringHashMap(BuiltinFunction).init(std.heap.page_allocator),
            .classes = std.StringHashMap(PHPClass).init(std.heap.page_allocator),
            .allocator = std.heap.page_allocator,
        };
    }

    /// 注册函数
    pub fn registerFunction(
        self: *PluginAPI,
        name: []const u8,
        min_args: u8,
        max_args: u8,
        handler: *const fn (*VM, []const Value) anyerror!Value,
    ) !void {
        try self.functions.put(name, .{
            .name = name,
            .min_args = min_args,
            .max_args = max_args,
            .handler = handler,
        });
    }

    /// 注销函数
    pub fn unregisterFunction(self: *PluginAPI, name: []const u8) !void {
        _ = self.functions.remove(name);
    }

    /// 注册类
    pub fn registerClass(self: *PluginAPI, name: []const u8) !void {
        try self.classes.put(name, .{
            .name = name,
            .methods = std.ArrayListUnmanaged([]const u8).init(self.allocator),
            .properties = std.ArrayListUnmanaged([]const u8).init(self.allocator),
        });
    }

    /// 注销类
    pub fn unregisterClass(self: *PluginAPI, name: []const u8) !void {
        if (self.classes.remove(name)) |cls| {
            for (cls.value_ptr.methods.items) |method| {
                self.allocator.free(method);
            }
            cls.value_ptr.methods.deinit(self.allocator);
            for (cls.value_ptr.properties.items) |prop| {
                self.allocator.free(prop);
            }
            cls.value_ptr.properties.deinit(self.allocator);
        }
    }

    /// 查找函数
    pub fn findFunction(self: *PluginAPI, name: []const u8) ?*const BuiltinFunction {
        return self.functions.get(name);
    }

    /// 查找类
    pub fn findClass(self: *PluginAPI, name: []const u8) ?*const PHPClass {
        return self.classes.get(name);
    }
};

// ============================================================================
// 测试
// ============================================================================

test "plugin info basic" {
    var info = PluginInfo.init(std.testing.allocator);
    defer info.deinit(std.testing.allocator);

    info.name = try std.testing.allocator.dupe(u8, "test_plugin");
    info.version = .{ .major = 1, .minor = 0, .patch = 0 };

    try std.testing.expect(std.mem.eql(u8, info.name, "test_plugin"));
    try std.testing.expect(info.version.major == 1);
}

test "plugin hook basic" {
    var hook = try PluginHook.init(std.testing.allocator, "test_hook", .before_function_call);
    defer hook.deinit();

    try std.testing.expect(std.mem.eql(u8, hook.name, "test_hook"));
    try std.testing.expect(hook.hook_type == .before_function_call);
}

test "plugin system basic" {
    var system = PluginSystem.init(std.testing.allocator);
    defer system.deinit();

    var info = PluginInfo.init(std.testing.allocator);
    defer info.deinit(std.testing.allocator);

    info.name = try std.testing.allocator.dupe(u8, "test_plugin");
    info.api_version = PLUGIN_API_VERSION;

    try system.loadPlugin(info);

    const stats = system.getStats();
    try std.testing.expect(stats.loaded_plugins == 1);
    try std.testing.expect(stats.enabled_plugins == 1);
}

test "plugin API basic" {
    var api = PluginAPI.init();
    defer _ = api; // 不需要deinit

    const test_handler = struct {
        fn handler(vm: *VM, args: []const Value) anyerror!Value {
            _ = vm;
            _ = args;
            return Value.initNull();
        }
    }.handler;

    try api.registerFunction("test_func", 0, 0, &test_handler);

    const found = api.findFunction("test_func");
    try std.testing.expect(found != null);
}
