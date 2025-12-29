//!zig-autodoc-section: examples/http_server_demo.zig
//! HTTP服务器完整演示
//! 展示协程安全、路由、中间件等完整功能
//!
//! 运行方式:
//! zig build run -- examples/http_server_demo.zig

const std = @import("std");
const http_server = @import("runtime/http_server.zig");
const coroutine = @import("runtime/coroutine.zig");
const types = @import("runtime/types.zig");
const vm_mod = @import("runtime/vm.zig");

/// 演示协程安全的计数器处理器
/// 每个请求都有独立的上下文，不会相互污染
fn counterHandler(vm: *vm_mod.VM, args: []const types.Value) anyerror!types.Value {
    const allocator = vm.memory_manager.allocator;

    // 获取Request和Response对象
    const req_value = args[0];
    const res_value = args[1];

    // 从请求上下文中获取或设置计数器
    // 注意：这个计数器是协程安全的，每个请求独立
    const ctx_key = "counter";
    var counter: i64 = 0;

    // 尝试获取现有的计数器
    if (req_value.data.array.data.get(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, ctx_key) })) |existing| {
        counter = existing.data.int + 1;
    } else {
        counter = 1;
    }

    // 更新计数器
    const counter_value = types.Value.initInt(counter);
    _ = req_value.data.array.data.put(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, ctx_key) }, counter_value);

    // 模拟异步操作（在协程中安全）
    std.time.sleep(100 * std.time.ns_per_ms);

    // 构造响应
    const response_data = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    try response_data.object.put("request_id", std.json.Value{ .integer = std.time.nanoTimestamp() });
    try response_data.object.put("counter", std.json.Value{ .integer = counter });
    try response_data.object.put("message", std.json.Value{ .string = "每个请求的计数器都是独立的！" });

    // 发送JSON响应
    const json_str = try std.json.stringifyAlloc(allocator, response_data, .{});
    defer allocator.free(json_str);

    // 设置响应状态和内容
    const status_key = types.ArrayKey{ .string = try types.PHPString.init(allocator, "status") };
    const body_key = types.ArrayKey{ .string = try types.PHPString.init(allocator, "body") };

    _ = res_value.data.array.data.put(allocator, status_key, types.Value.initInt(200));
    _ = res_value.data.array.data.put(allocator, body_key, types.Value.initStringWithManager(&vm.memory_manager, json_str));

    return types.Value.initNull();
}

/// 用户API处理器 - 演示完整的CRUD操作
fn userApiHandler(vm: *vm_mod.VM, args: []const types.Value) anyerror!types.Value {
    const allocator = vm.memory_manager.allocator;

    const req_value = args[0];
    const res_value = args[1];

    // 获取请求方法和路径
    const method = req_value.data.array.data.get(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, "method") });
    const path = req_value.data.array.data.get(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, "path") });

    if (method == null or path == null) {
        return types.Value.initNull();
    }

    // 简单的路由处理
    if (std.mem.eql(u8, method.?.data.string.data.items, "GET")) {
        if (std.mem.eql(u8, path.?.data.string.data.items, "/api/users")) {
            // 返回用户列表
            const users_data = std.json.Value{ .array = std.json.Array.initCapacity(allocator, 2) };
            try users_data.array.append(std.json.Value{ .object = std.json.ObjectMap.init(allocator) });
            try users_data.array.items[0].object.put("id", std.json.Value{ .integer = 1 });
            try users_data.array.items[0].object.put("name", std.json.Value{ .string = "张三" });

            try users_data.array.append(std.json.Value{ .object = std.json.ObjectMap.init(allocator) });
            try users_data.array.items[1].object.put("id", std.json.Value{ .integer = 2 });
            try users_data.array.items[1].object.put("name", std.json.Value{ .string = "李四" });

            const json_str = try std.json.stringifyAlloc(allocator, users_data, .{});
            defer allocator.free(json_str);

            _ = res_value.data.array.data.put(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, "status") }, types.Value.initInt(200));
            _ = res_value.data.array.data.put(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, "body") }, types.Value.initStringWithManager(&vm.memory_manager, json_str));
        }
    } else if (std.mem.eql(u8, method.?.data.string.data.items, "POST")) {
        if (std.mem.eql(u8, path.?.data.string.data.items, "/api/users")) {
            // 创建新用户
            const new_user = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
            try new_user.object.put("id", std.json.Value{ .integer = 3 });
            try new_user.object.put("name", std.json.Value{ .string = "王五" });
            try new_user.object.put("created", std.json.Value{ .bool = true });

            const json_str = try std.json.stringifyAlloc(allocator, new_user, .{});
            defer allocator.free(json_str);

            _ = res_value.data.array.data.put(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, "status") }, types.Value.initInt(201));
            _ = res_value.data.array.data.put(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, "body") }, types.Value.initStringWithManager(&vm.memory_manager, json_str));
        }
    }

    return types.Value.initNull();
}

/// 中间件演示 - 日志记录
fn loggingMiddleware(vm: *vm_mod.VM, args: []const types.Value) anyerror!types.Value {
    const start_time = std.time.milliTimestamp();

    // 调用下一个处理器
    const next_result = try vm.callUserFunction(args[0].data.user_function.data, &[_]types.Value{});

    const duration = std.time.milliTimestamp() - start_time;
    std.debug.print("[LOG] 请求处理完成，耗时: {}ms\n", .{duration});

    return next_result;
}

/// 演示并发协程隔离的处理器
fn concurrentIsolationDemo(vm: *vm_mod.VM, args: []const types.Value) anyerror!types.Value {
    const allocator = vm.memory_manager.allocator;

    const res_value = args[1];

    // 每个协程都有独立的变量空间
    const fiber_id = std.Thread.getCurrentId();
    const coroutine_data = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    try coroutine_data.object.put("fiber_id", std.json.Value{ .integer = @intCast(fiber_id) });
    try coroutine_data.object.put("timestamp", std.json.Value{ .integer = std.time.nanoTimestamp() });
    try coroutine_data.object.put("isolation_demo", std.json.Value{ .string = "每个协程的变量都是隔离的" });

    const json_str = try std.json.stringifyAlloc(allocator, coroutine_data, .{});
    defer allocator.free(json_str);

    _ = res_value.data.array.data.put(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, "status") }, types.Value.initInt(200));
    _ = res_value.data.array.data.put(allocator, types.ArrayKey{ .string = try types.PHPString.init(allocator, "body") }, types.Value.initStringWithManager(&vm.memory_manager, json_str));

    return types.Value.initNull();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 启动 Zig-PHP HTTP 服务器演示\n\n", .{});

    // 初始化VM
    var vm = try vm_mod.VM.init(allocator);
    defer vm.deinit();

    // 创建HTTP服务器配置
    const config = http_server.HttpServer.Config{
        .host = "127.0.0.1",
        .port = 8080,
        .enable_coroutines = true, // 启用协程处理
        .max_connections = 1000,
        .context_pool_size = 100, // 上下文池优化
    };

    // 创建HTTP服务器
    var server = try http_server.HttpServer.init(allocator, config, &vm);
    defer server.deinit();

    // 注册路由处理器
    const counter_handler = types.Value{ .tag = .builtin_function, .data = .{ .builtin_function = counterHandler } };
    const user_api_handler = types.Value{ .tag = .builtin_function, .data = .{ .builtin_function = userApiHandler } };
    const isolation_handler = types.Value{ .tag = .builtin_function, .data = .{ .builtin_function = concurrentIsolationDemo } };

    // 创建路由器
    var router = http_server.Router.init(allocator);
    defer router.deinit();

    // 添加路由
    try router.get("/counter", counter_handler);
    try router.get("/api/users", user_api_handler);
    try router.post("/api/users", user_api_handler);
    try router.get("/isolation", isolation_handler);

    // 添加中间件
    const logging_mw = types.Value{ .tag = .builtin_function, .data = .{ .builtin_function = loggingMiddleware } };
    try router.use(logging_mw);

    // 设置服务器处理器（使用路由器）
    server.setHandler(types.Value{ .tag = .object, .data = .{ .object = &router } });

    std.debug.print("📡 服务器配置:\n", .{});
    std.debug.print("   - 地址: {}:{}\n", .{ config.host, config.port });
    std.debug.print("   - 协程支持: {}\n", .{config.enable_coroutines});
    std.debug.print("   - 最大连接数: {}\n", .{config.max_connections});
    std.debug.print("   - 上下文池大小: {}\n", .{config.context_pool_size});

    std.debug.print("\n🔗 可用路由:\n", .{});
    std.debug.print("   GET  /counter     - 协程安全计数器演示\n", .{});
    std.debug.print("   GET  /api/users   - 获取用户列表\n", .{});
    std.debug.print("   POST /api/users   - 创建新用户\n", .{});
    std.debug.print("   GET  /isolation   - 并发协程隔离演示\n", .{});

    std.debug.print("\n🌐 服务器启动在: http://{}:{}\n", .{ config.host, config.port });
    std.debug.print("💡 测试命令:\n", .{});
    std.debug.print("   curl http://127.0.0.1:8080/counter\n", .{});
    std.debug.print("   curl http://127.0.0.1:8080/api/users\n", .{});
    std.debug.print("   curl -X POST http://127.0.0.1:8080/api/users\n", .{});
    std.debug.print("   # 并发测试\n", .{});
    std.debug.print("   for i in {1..5}; do curl http://127.0.0.1:8080/counter & done\n\n", .{});

    // 启动服务器
    try server.start();
}

test "http server demo compilation" {
    // 确保代码可以编译
    std.testing.refAllDecls(@This());
}
