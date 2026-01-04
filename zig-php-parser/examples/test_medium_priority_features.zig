//! 中优先级功能集成示例
//!
//! 演示压缩GC、插件系统和调试器的集成使用

const std = @import("std");

// 导入中优先级功能
const compacting_gc = @import("src/runtime/compacting_gc.zig");
const plugin_system = @import("src/runtime/plugin_system.zig");
const debugger_mod = @import("src/runtime/debugger.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== 中优先级功能集成示例 ===\n\n", .{});

    // 1. 压缩GC测试
    try testCompactingGC(allocator);

    // 2. 插件系统测试
    try testPluginSystem(allocator);

    // 3. 调试器测试
    try testDebugger(allocator);

    std.debug.print("\n=== 所有测试完成 ===\n", .{});
}

/// 测试压缩GC
fn testCompactingGC(allocator: std.mem.Allocator) !void {
    std.debug.print("1. 压缩GC测试\n", .{});
    std.debug.print("----------------\n", .{});

    // 初始化压缩GC
    var gc = try compacting_gc.CompactingGC.init(allocator, 1024 * 1024);
    defer gc.deinit();

    std.debug.print("  - 初始化压缩GC: OK\n", .{});

    // 添加一些对象
    try gc.region.addObject(gc.region.base, 100);
    try gc.region.addObject(gc.region.base + 100, 200);
    try gc.region.addObject(gc.region.base + 300, 150);
    try gc.region.addObject(gc.region.base + 450, 300);
    try gc.region.addObject(gc.region.base + 750, 250);

    std.debug.print("  - 添加对象: OK\n", .{});

    // 标记一些对象为死亡
    gc.region.objects.items[1].alive = false;
    gc.region.objects.items[3].alive = false;

    std.debug.print("  - 标记死亡对象: OK\n", .{});

    // 计算碎片化
    const fragmentation = gc.getFragmentation();
    std.debug.print("  - 碎片化程度: {d:.2%}\n", .{fragmentation});

    // 检查是否需要压缩
    const needs = gc.needsCompaction();
    std.debug.print("  - 需要压缩: {}\n", .{needs});

    // 执行压缩
    try gc.compact();
    std.debug.print("  - 执行压缩: OK\n", .{});

    // 获取统计
    const stats = gc.getStats();
    std.debug.print("  - 压缩统计:\n", .{});
    std.debug.print("    * 压缩次数: {}\n", .{stats.compaction_count});
    std.debug.print("    * 移动对象数: {}\n", .{stats.moved_objects});
    std.debug.print("    * 移动字节数: {} bytes\n", .{stats.moved_bytes});
    std.debug.print("    * 更新引用数: {}\n", .{stats.updated_references});
    std.debug.print("    * 压缩前碎片化: {d:.2%}\n", .{stats.fragmentation_before});
    std.debug.print("    * 压缩后碎片化: {d:.2%}\n", .{stats.fragmentation_after});
    std.debug.print("    * 压缩时间: {} ms\n", .{stats.compaction_time_ns / 1_000_000});

    std.debug.print("\n", .{});
}

/// 测试插件系统
fn testPluginSystem(allocator: std.mem.Allocator) !void {
    std.debug.print("2. 插件系统测试\n", .{});
    std.debug.print("----------------\n", .{});

    // 初始化插件系统
    var system = plugin_system.PluginSystem.init(allocator);
    defer system.deinit();

    std.debug.print("  - 初始化插件系统: OK\n", .{});

    // 创建插件信息
    var info = plugin_system.PluginInfo.init(allocator);
    defer info.deinit(allocator);

    info.name = try allocator.dupe(u8, "test_plugin");
    info.version = .{ .major = 1, .minor = 0, .patch = 0 };
    info.description = try allocator.dupe(u8, "Test plugin for demonstration");
    info.author = try allocator.dupe(u8, "AI Assistant");
    info.api_version = plugin_system.PLUGIN_API_VERSION;

    // 添加一个函数
    const test_handler = struct {
        fn handler(vm: *anyopaque, args: []const plugin_system.Value) anyerror!plugin_system.Value {
            _ = vm;
            _ = args;
            return plugin_system.Value.initString(allocator, "Hello from plugin!");
        }
    }.handler;

    try info.functions.append(allocator, .{
        .name = try allocator.dupe(u8, "plugin_hello"),
        .min_args = 0,
        .max_args = 0,
        .handler = @ptrCast(&test_handler),
    });

    std.debug.print("  - 创建插件信息: OK\n", .{});

    // 加载插件
    try system.loadPlugin(info);
    std.debug.print("  - 加载插件: OK\n", .{});

    // 注册钩子
    try system.registerHook("before_gc", plugin_system.PluginHook.HookType.before_gc);
    std.debug.print("  - 注册钩子: OK\n", .{});

    // 获取统计
    const stats = system.getStats();
    std.debug.print("  - 插件统计:\n", .{});
    std.debug.print("    * 加载的插件数: {}\n", .{stats.loaded_plugins});
    std.debug.print("    * 启用的插件数: {}\n", .{stats.enabled_plugins});
    std.debug.print("    * 注册的函数数: {}\n", .{stats.registered_functions});
    std.debug.print("    * 注册的类数: {}\n", .{stats.registered_classes});
    std.debug.print("    * 触发的钩子数: {}\n", .{stats.triggered_hooks});

    // 列出所有插件
    const plugins = try system.listPlugins();
    std.debug.print("  - 插件列表: {} 个\n", .{plugins.items.len});
    for (plugins.items) |plugin| {
        std.debug.print("    * {}\n", .{plugin});
        allocator.free(plugin);
    }
    plugins.deinit();

    std.debug.print("\n", .{});
}

/// 测试调试器
fn testDebugger(allocator: std.mem.Allocator) !void {
    std.debug.print("3. 调试器测试\n", .{});
    std.debug.print("----------------\n", .{});

    // 初始化调试器
    var debugger = debugger_mod.Debugger.init(allocator);
    defer debugger.deinit();

    std.debug.print("  - 初始化调试器: OK\n", .{});

    // 设置断点
    try debugger.setBreakpoint("test.php", 10, false);
    try debugger.setBreakpoint("test.php", 20, true); // 临时断点
    std.debug.print("  - 设置断点: OK\n", .{});

    // 添加监视变量
    try debugger.addWatch("test_var");
    try debugger.addWatch("counter");
    std.debug.print("  - 添加监视变量: OK\n", .{});

    // 推入调用栈帧
    try debugger.pushStackFrame("main", "index.php", 1);
    try debugger.pushStackFrame("processRequest", "index.php", 10);
    try debugger.pushStackFrame("renderResponse", "index.php", 20);
    std.debug.print("  - 推入调用栈帧: OK\n", .{});

    // 检查断点
    const triggered = debugger.checkBreakpoints("test.php", 10, null);
    std.debug.print("  - 检查断点: {}\n", .{triggered});

    // 暂停
    debugger.pause();
    std.debug.print("  - 暂停调试器: OK\n", .{});

    // 步进
    debugger.step();
    std.debug.print("  - 步进: OK\n", .{});

    // 继续
    debugger.resume();
    std.debug.print("  - 继续执行: OK\n", .{});

    // 获取统计
    const stats = debugger.getStats();
    std.debug.print("  - 调试器统计:\n", .{});
    std.debug.print("    * 断点命中次数: {}\n", .{stats.breakpoint_hits});
    std.debug.print("    * 步进次数: {}\n", .{stats.step_count});
    std.debug.print("    * 继续次数: {}\n", .{stats.continue_count});
    std.debug.print("    * 查看变量次数: {}\n", .{stats.variable_inspects});

    // 列出断点
    const breakpoints = try debugger.listBreakpoints();
    std.debug.print("  - 断点列表: {} 个\n", .{breakpoints.items.len});
    for (breakpoints.items) |bp| {
        std.debug.print("    * {}\n", .{bp});
        allocator.free(bp);
    }
    breakpoints.deinit();

    // 列出监视变量
    const watches = try debugger.listWatches();
    std.debug.print("  - 监视变量: {} 个\n", .{watches.items.len});
    for (watches.items) |wp| {
        std.debug.print("    * {}\n", .{wp});
        allocator.free(wp);
    }
    watches.deinit();

    // 弹出调用栈帧
    debugger.popStackFrame();
    debugger.popStackFrame();
    debugger.popStackFrame();

    std.debug.print("\n", .{});
}
