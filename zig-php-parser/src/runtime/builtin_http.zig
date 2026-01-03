const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const http_server = @import("http_server.zig");
const http_client = @import("http_client.zig");
const coroutine = @import("coroutine.zig");

/// 全局HTTP服务器实例存储（用于PHP函数式API）
var global_servers: std.StringHashMap(*http_server.HttpServer) = undefined;
var global_servers_initialized: bool = false;
var global_mutex: std.Thread.Mutex = .{};

/// 注册HTTP相关类和函数到VM
pub fn registerHttpClasses(vm: anytype) !void {
    // 初始化全局服务器存储
    if (!global_servers_initialized) {
        global_servers = std.StringHashMap(*http_server.HttpServer).init(vm.allocator);
        global_servers_initialized = true;
    }

    // 注册类
    try registerHttpServerClass(vm);
    try registerHttpClientClass(vm);
    try registerHttpRequestClass(vm);
    try registerHttpResponseClass(vm);
    try registerRouterClass(vm);

    // 注册函数式API
    try registerHttpFunctions(vm);
}

/// 清理HTTP相关全局资源
pub fn cleanup() void {
    if (global_servers_initialized) {
        global_servers.deinit();
        global_servers_initialized = false;
    }
}

/// 注册HttpServer类
fn registerHttpServerClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "HttpServer");
    defer name_str.release(vm.allocator);
    const server_class = try vm.allocator.create(types.PHPClass);
    server_class.* = try types.PHPClass.init(vm.allocator, name_str);
    server_class.native_destructor = httpServerDestructor;

    try vm.classes.put("HttpServer", server_class);
    try vm.defineBuiltin("HttpServer", httpServerConstructor);
}

fn httpServerDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const server = @as(*http_server.HttpServer, @ptrCast(@alignCast(ptr)));
    server.deinit();
    allocator.destroy(server);
}

/// HttpServer构造函数
pub fn httpServerConstructor(vm: anytype, args: []Value) !Value {
    var config = http_server.HttpServer.Config{};

    // 解析配置参数
    if (args.len > 0 and args[0].tag == .array) {
        const arr = args[0].data.array.data;

        // 解析host
        const host_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "host") };
        defer host_key.string.release(vm.allocator);
        if (arr.get(host_key)) |host_val| {
            if (host_val.tag == .string) {
                config.host = host_val.data.string.data.data;
            }
        }

        // 解析port
        const port_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "port") };
        defer port_key.string.release(vm.allocator);
        if (arr.get(port_key)) |port_val| {
            if (port_val.tag == .integer) {
                config.port = @intCast(port_val.data.integer);
            }
        }

        // 解析enable_coroutines
        const coroutine_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "enable_coroutines") };
        defer coroutine_key.string.release(vm.allocator);
        if (arr.get(coroutine_key)) |co_val| {
            if (co_val.tag == .boolean) {
                config.enable_coroutines = co_val.data.boolean;
            }
        }

        // 解析max_connections
        const max_conn_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "max_connections") };
        defer max_conn_key.string.release(vm.allocator);
        if (arr.get(max_conn_key)) |max_val| {
            if (max_val.tag == .integer) {
                config.max_connections = @intCast(max_val.data.integer);
            }
        }
    }

    const server = try vm.allocator.create(http_server.HttpServer);
    server.* = try http_server.HttpServer.init(vm.allocator, config, vm);

    const class = vm.classes.get("HttpServer").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(server);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

/// 注册HttpClient类
fn registerHttpClientClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "HttpClient");
    defer name_str.release(vm.allocator);
    const client_class = try vm.allocator.create(types.PHPClass);
    client_class.* = try types.PHPClass.init(vm.allocator, name_str);
    client_class.native_destructor = httpClientDestructor;

    try vm.classes.put("HttpClient", client_class);
    try vm.defineBuiltin("HttpClient", httpClientConstructor);
}

fn httpClientDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const client = @as(*http_client.HttpClient, @ptrCast(@alignCast(ptr)));
    client.deinit();
    allocator.destroy(client);
}

/// HttpClient构造函数
pub fn httpClientConstructor(vm: anytype, args: []Value) !Value {
    var config = http_client.HttpClient.Config{};

    // 解析配置参数
    if (args.len > 0 and args[0].tag == .array) {
        const arr = args[0].data.array.data;

        // 解析timeout
        const timeout_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "timeout") };
        defer timeout_key.string.release(vm.allocator);
        if (arr.get(timeout_key)) |timeout_val| {
            if (timeout_val.tag == .integer) {
                config.timeout = @intCast(timeout_val.data.integer);
            }
        }

        // 解析follow_redirects
        const redirect_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "follow_redirects") };
        defer redirect_key.string.release(vm.allocator);
        if (arr.get(redirect_key)) |redirect_val| {
            if (redirect_val.tag == .boolean) {
                config.follow_redirects = redirect_val.data.boolean;
            }
        }
    }

    const client = try vm.allocator.create(http_client.HttpClient);
    client.* = http_client.HttpClient.init(vm.allocator, config);

    const class = vm.classes.get("HttpClient").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(client);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

/// 注册HttpRequest类
fn registerHttpRequestClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "HttpRequest");
    defer name_str.release(vm.allocator);
    const request_class = try vm.allocator.create(types.PHPClass);
    request_class.* = try types.PHPClass.init(vm.allocator, name_str);

    try vm.classes.put("HttpRequest", request_class);
}

/// 注册HttpResponse类
fn registerHttpResponseClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "HttpResponse");
    defer name_str.release(vm.allocator);
    const response_class = try vm.allocator.create(types.PHPClass);
    response_class.* = try types.PHPClass.init(vm.allocator, name_str);
    response_class.native_destructor = httpResponseDestructor;

    // Add status() method
    const status_method_name = try types.PHPString.init(vm.allocator, "status");
    var status_method = types.Method.init(status_method_name);
    status_method_name.release(vm.allocator); // Release after Method.init retains it
    status_method.modifiers = .{ .visibility = .public };
    status_method.parameters = &[_]types.Method.Parameter{};
    status_method.body = null; // Builtin method
    try response_class.methods.put("status", status_method);

    // Add json() method
    const json_method_name = try types.PHPString.init(vm.allocator, "json");
    var json_method = types.Method.init(json_method_name);
    json_method_name.release(vm.allocator); // Release after Method.init retains it
    json_method.modifiers = .{ .visibility = .public };
    json_method.parameters = &[_]types.Method.Parameter{};
    json_method.body = null; // Builtin method
    try response_class.methods.put("json", json_method);

    try vm.classes.put("HttpResponse", response_class);
    try vm.defineBuiltin("HttpResponse", httpResponseConstructor);
}

/// 注册Router类
fn registerRouterClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "Router");
    defer name_str.release(vm.allocator);
    const router_class = try vm.allocator.create(types.PHPClass);
    router_class.* = try types.PHPClass.init(vm.allocator, name_str);
    router_class.native_destructor = routerDestructor;

    try vm.classes.put("Router", router_class);
    try vm.defineBuiltin("Router", routerConstructor);
}

fn httpResponseDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const response = @as(*http_server.HttpResponse, @ptrCast(@alignCast(ptr)));
    response.deinit();
    allocator.destroy(response);
}

/// HttpResponse构造函数
pub fn httpResponseConstructor(vm: anytype, args: []Value) !Value {
    _ = args;

    const response = try vm.allocator.create(http_server.HttpResponse);
    response.* = http_server.HttpResponse.init(vm.allocator);

    const class = vm.classes.get("HttpResponse").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(response);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

fn routerDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const router = @as(*http_server.Router, @ptrCast(@alignCast(ptr)));
    router.deinit();
    allocator.destroy(router);
}
pub fn routerConstructor(vm: anytype, args: []Value) !Value {
    _ = args;

    const router = try vm.allocator.create(http_server.Router);
    router.* = http_server.Router.init(vm.allocator);

    const class = vm.classes.get("Router").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(router);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

/// 注册函数式API
fn registerHttpFunctions(vm: anytype) !void {
    try vm.defineBuiltin("http_server_create", httpServerCreate);
    try vm.defineBuiltin("http_server_handle", httpServerHandle);
    try vm.defineBuiltin("http_server_start", httpServerStart);
    try vm.defineBuiltin("http_server_stop", httpServerStop);
    try vm.defineBuiltin("http_get", httpGet);
    try vm.defineBuiltin("http_post", httpPost);
    try vm.defineBuiltin("http_request", httpRequest);
}

/// 函数式API: http_server_create
pub fn httpServerCreate(vm: anytype, args: []Value) !Value {
    return httpServerConstructor(vm, args);
}

/// 函数式API: http_server_handle
pub fn httpServerHandle(vm: anytype, args: []Value) !Value {
    if (args.len < 2) return Value.initBool(false);

    if (args[0].tag != .object) return Value.initBool(false);

    const obj = args[0].data.object.data;
    if (obj.native_data == null) return Value.initBool(false);

    const server = @as(*http_server.HttpServer, @ptrCast(@alignCast(obj.native_data.?)));
    const handler = args[1];

    server.setHandler(handler);
    _ = vm;

    return Value.initBool(true);
}

/// 函数式API: http_server_start
pub fn httpServerStart(vm: anytype, args: []Value) !Value {
    if (args.len < 1 or args[0].tag != .object) return Value.initBool(false);

    const obj = args[0].data.object.data;
    if (obj.native_data == null) return Value.initBool(false);

    const server = @as(*http_server.HttpServer, @ptrCast(@alignCast(obj.native_data.?)));

    // 在后台线程启动服务器
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(s: *http_server.HttpServer) void {
            s.start() catch |err| {
                std.debug.print("HTTP Server error: {}\n", .{err});
            };
        }
    }.run, .{server});
    thread.detach();

    _ = vm;
    return Value.initBool(true);
}

/// 函数式API: http_server_stop
pub fn httpServerStop(vm: anytype, args: []Value) !Value {
    if (args.len < 1 or args[0].tag != .object) return Value.initBool(false);

    const obj = args[0].data.object.data;
    if (obj.native_data == null) return Value.initBool(false);

    const server = @as(*http_server.HttpServer, @ptrCast(@alignCast(obj.native_data.?)));
    server.stop();

    _ = vm;
    return Value.initBool(true);
}

/// 函数式API: http_get
pub fn httpGet(vm: anytype, args: []Value) !Value {
    if (args.len < 1 or args[0].tag != .string) {
        return Value.initNull();
    }

    const url = args[0].data.string.data.data;

    var client = http_client.HttpClient.init(vm.allocator, .{});
    defer client.deinit();

    const response = client.get(url) catch |err| {
        std.debug.print("HTTP GET error: {}\n", .{err});
        return Value.initNull();
    };

    // 创建响应数组
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    const arr = result.data.array.data;

    // 添加status
    const status_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "status") };
    try arr.set(vm.allocator, status_key, Value.initInt(response.status_code));
    status_key.string.release(vm.allocator);

    // 添加body
    const body_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "body") };
    const body_val = try Value.initStringWithManager(&vm.memory_manager, response.body);
    try arr.set(vm.allocator, body_key, body_val);
    body_key.string.release(vm.allocator);

    return result;
}

/// 函数式API: http_post
pub fn httpPost(vm: anytype, args: []Value) !Value {
    if (args.len < 1 or args[0].tag != .string) {
        return Value.initNull();
    }

    const url = args[0].data.string.data.data;
    const body: ?[]const u8 = if (args.len > 1 and args[1].tag == .string)
        args[1].data.string.data.data
    else
        null;

    var client = http_client.HttpClient.init(vm.allocator, .{});
    defer client.deinit();

    const response = client.post(url, body) catch |err| {
        std.debug.print("HTTP POST error: {}\n", .{err});
        return Value.initNull();
    };

    // 创建响应数组
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    const arr = result.data.array.data;

    // 添加status
    const status_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "status") };
    try arr.set(vm.allocator, status_key, Value.initInt(response.status_code));
    status_key.string.release(vm.allocator);

    // 添加body
    const body_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "body") };
    const body_val = try Value.initStringWithManager(&vm.memory_manager, response.body);
    try arr.set(vm.allocator, body_key, body_val);
    body_key.string.release(vm.allocator);

    return result;
}

/// 函数式API: http_request
pub fn httpRequest(vm: anytype, args: []Value) !Value {
    if (args.len < 2) return Value.initNull();

    const method_str = if (args[0].tag == .string) args[0].data.string.data.data else "GET";
    const url = if (args[1].tag == .string) args[1].data.string.data.data else return Value.initNull();

    var client = http_client.HttpClient.init(vm.allocator, .{});
    defer client.deinit();

    const method: http_client.HttpClient.Method = if (std.mem.eql(u8, method_str, "POST"))
        .POST
    else if (std.mem.eql(u8, method_str, "PUT"))
        .PUT
    else if (std.mem.eql(u8, method_str, "DELETE"))
        .DELETE
    else if (std.mem.eql(u8, method_str, "PATCH"))
        .PATCH
    else
        .GET;

    const body: ?[]const u8 = if (args.len > 2 and args[2].tag == .string)
        args[2].data.string.data.data
    else
        null;

    const response = client.request(method, url, body, null) catch |err| {
        std.debug.print("HTTP request error: {}\n", .{err});
        return Value.initNull();
    };

    // 创建响应数组
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    const arr = result.data.array.data;

    const status_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "status") };
    try arr.set(vm.allocator, status_key, Value.initInt(response.status_code));
    status_key.string.release(vm.allocator);

    const body_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "body") };
    const body_val = try Value.initStringWithManager(&vm.memory_manager, response.body);
    try arr.set(vm.allocator, body_key, body_val);
    body_key.string.release(vm.allocator);

    return result;
}

/// 调用HttpServer方法
pub fn callHttpServerMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []Value) !Value {
    const server = @as(*http_server.HttpServer, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "handle")) {
        if (args.len > 0) {
            server.setHandler(args[0]);
        }
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "start")) {
        try server.start();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "stop")) {
        server.stop();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "getActiveRequestCount")) {
        const count = server.getActiveRequestCount();
        return Value.initInt(@intCast(count));
    } else if (std.mem.eql(u8, method_name, "isRunning")) {
        return Value.initBool(server.running.load(.seq_cst));
    }

    _ = vm;
    return error.MethodNotFound;
}

/// 调用Router方法
pub fn callRouterMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []const Value) !Value {
    const router = @as(*http_server.Router, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "get")) {
        if (args.len < 2 or args[0].getTag() != .string or args[1].getTag() != .string) return Value.initNull();
        const method = args[0].getAsString().data.data;
        const path = args[1].getAsString().data.data;

        const MethodType = http_server.HttpRequest.Method;
        const http_method = if (std.mem.eql(u8, method, "GET"))
            MethodType.GET
        else if (std.mem.eql(u8, method, "POST"))
            MethodType.POST
        else if (std.mem.eql(u8, method, "PUT"))
            MethodType.PUT
        else if (std.mem.eql(u8, method, "DELETE"))
            MethodType.DELETE
        else
            return Value.initNull();

        const route = router.match(http_method, path);
        if (route) |r| {
            // Return route info as array
            const result = try Value.initArrayWithManager(&vm.memory_manager);
            const arr = result.getAsArray().data;

            const method_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "method") };
            const method_val = switch (r.method) {
                .GET => "GET",
                .POST => "POST",
                .PUT => "PUT",
                .DELETE => "DELETE",
                else => "UNKNOWN",
            };
            try arr.set(vm.allocator, method_key, try Value.initStringWithManager(&vm.memory_manager, method_val));
            method_key.string.release(vm.allocator);

            const path_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "path") };
            try arr.set(vm.allocator, path_key, try Value.initStringWithManager(&vm.memory_manager, r.path));
            path_key.string.release(vm.allocator);

            return result;
        }
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "addRoute")) {
        if (args.len < 3 or args[0].getTag() != .string or args[1].getTag() != .string) return Value.initNull();
        const method = args[0].getAsString().data.data;
        const path = args[1].getAsString().data.data;

        const MethodType = http_server.HttpRequest.Method;
        const http_method = if (std.mem.eql(u8, method, "GET"))
            MethodType.GET
        else if (std.mem.eql(u8, method, "POST"))
            MethodType.POST
        else if (std.mem.eql(u8, method, "PUT"))
            MethodType.PUT
        else if (std.mem.eql(u8, method, "DELETE"))
            MethodType.DELETE
        else
            return Value.initBool(false);

        try router.addRoute(http_method, path, args[2]);
        return Value.initBool(true);
    } else if (std.mem.eql(u8, method_name, "match")) {
        if (args.len < 2) return Value.initNull();

        // Convert PHP method string to HttpRequest.Method enum
        const method_arg = args[0];
        const path_arg = args[1];

        if (method_arg.getTag() != .string or path_arg.getTag() != .string) return Value.initNull();

        const method_str = method_arg.getAsString().data.data;
        const path = path_arg.getAsString().data.data;

        const MethodType = http_server.HttpRequest.Method;
        const http_method = if (std.mem.eql(u8, method_str, "GET"))
            MethodType.GET
        else if (std.mem.eql(u8, method_str, "POST"))
            MethodType.POST
        else if (std.mem.eql(u8, method_str, "PUT"))
            MethodType.PUT
        else if (std.mem.eql(u8, method_str, "DELETE"))
            MethodType.DELETE
        else
            return Value.initNull();

        const route = router.match(http_method, path);
        if (route) |r| {
            // Return route info as array
            const result = try Value.initArrayWithManager(&vm.memory_manager);
            const arr = result.getAsArray().data;

            const method_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "method") };
            const method_val = switch (r.method) {
                .GET => "GET",
                .POST => "POST",
                .PUT => "PUT",
                .DELETE => "DELETE",
                else => "UNKNOWN",
            };
            try arr.set(vm.allocator, method_key, try Value.initStringWithManager(&vm.memory_manager, method_val));
            method_key.string.release(vm.allocator);

            const path_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "path") };
            try arr.set(vm.allocator, path_key, try Value.initStringWithManager(&vm.memory_manager, r.path));
            path_key.string.release(vm.allocator);

            const handler_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "handler") };
            _ = r.handler.retain();
            try arr.set(vm.allocator, handler_key, r.handler);
            handler_key.string.release(vm.allocator);

            return result;
        }
        return Value.initNull();
    }

    return error.MethodNotFound;
}

/// 调用HttpResponse方法
pub fn callHttpResponseMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []const Value) !Value {
    const response = @as(*http_server.HttpResponse, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "status")) {
        if (args.len < 1 or args[0].getTag() != .integer) return Value.initNull();
        const code = @as(u16, @intCast(args[0].asInt()));
        response.setStatus(code);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "json")) {
        if (args.len < 1 or args[0].getTag() != .string) return Value.initNull();
        const data = args[0].getAsString().data.data;
        try response.json(data);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "html")) {
        if (args.len < 1 or args[0].getTag() != .string) return Value.initNull();
        const content = args[0].getAsString().data.data;
        try response.html(content);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "text")) {
        if (args.len < 1 or args[0].getTag() != .string) return Value.initNull();
        const content = args[0].getAsString().data.data;
        try response.setHeader("Content-Type", "text/plain; charset=utf-8");
        try response.setBody(content);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "header")) {
        if (args.len < 2 or args[0].getTag() != .string or args[1].getTag() != .string) return Value.initNull();
        const name = args[0].getAsString().data.data;
        const value = args[1].getAsString().data.data;
        try response.setHeader(name, value);
        return Value.initNull();
    }

    _ = vm;
    return error.MethodNotFound;
}

/// 创建响应Value
fn createResponseValue(vm: anytype, response: http_client.HttpResponse) !Value {
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    const arr = result.getAsArray().data;

    const status_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "status") };
    try arr.set(vm.allocator, status_key, Value.initInt(response.status_code));
    status_key.string.release(vm.allocator);

    const body_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "body") };
    const body_val = try Value.initStringWithManager(&vm.memory_manager, response.body);
    try arr.set(vm.allocator, body_key, body_val);
    body_key.string.release(vm.allocator);

    const success_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "success") };
    try arr.set(vm.allocator, success_key, Value.initBool(response.isSuccess()));
    success_key.string.release(vm.allocator);

    return result;
}
