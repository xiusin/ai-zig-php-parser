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

/// 注册HttpServer类
fn registerHttpServerClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "HttpServer");
    defer name_str.release(vm.allocator);
    const server_class = try vm.allocator.create(types.PHPClass);
    server_class.* = types.PHPClass.init(vm.allocator, name_str);
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
    client_class.* = types.PHPClass.init(vm.allocator, name_str);
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
    request_class.* = types.PHPClass.init(vm.allocator, name_str);

    try vm.classes.put("HttpRequest", request_class);
}

/// 注册HttpResponse类
fn registerHttpResponseClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "HttpResponse");
    defer name_str.release(vm.allocator);
    const response_class = try vm.allocator.create(types.PHPClass);
    response_class.* = types.PHPClass.init(vm.allocator, name_str);

    try vm.classes.put("HttpResponse", response_class);
}

/// 注册Router类
fn registerRouterClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "Router");
    defer name_str.release(vm.allocator);
    const router_class = try vm.allocator.create(types.PHPClass);
    router_class.* = types.PHPClass.init(vm.allocator, name_str);
    router_class.native_destructor = routerDestructor;

    try vm.classes.put("Router", router_class);
    try vm.defineBuiltin("Router", routerConstructor);
}

fn routerDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const router = @as(*http_server.Router, @ptrCast(@alignCast(ptr)));
    router.deinit();
    allocator.destroy(router);
}

/// Router构造函数
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

    // 添加body
    const body_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "body") };
    const body_val = try Value.initStringWithManager(&vm.memory_manager, response.body);
    try arr.set(vm.allocator, body_key, body_val);

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

    // 添加body
    const body_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "body") };
    const body_val = try Value.initStringWithManager(&vm.memory_manager, response.body);
    try arr.set(vm.allocator, body_key, body_val);

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

    const body_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "body") };
    const body_val = try Value.initStringWithManager(&vm.memory_manager, response.body);
    try arr.set(vm.allocator, body_key, body_val);

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

/// 调用HttpClient方法
pub fn callHttpClientMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []Value) !Value {
    const client = @as(*http_client.HttpClient, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "get")) {
        if (args.len < 1 or args[0].tag != .string) return Value.initNull();
        const url = args[0].data.string.data.data;

        const response = client.get(url) catch return Value.initNull();
        return try createResponseValue(vm, response);
    } else if (std.mem.eql(u8, method_name, "post")) {
        if (args.len < 1 or args[0].tag != .string) return Value.initNull();
        const url = args[0].data.string.data.data;
        const body: ?[]const u8 = if (args.len > 1 and args[1].tag == .string)
            args[1].data.string.data.data
        else
            null;

        const response = client.post(url, body) catch return Value.initNull();
        return try createResponseValue(vm, response);
    } else if (std.mem.eql(u8, method_name, "put")) {
        if (args.len < 1 or args[0].tag != .string) return Value.initNull();
        const url = args[0].data.string.data.data;
        const body: ?[]const u8 = if (args.len > 1 and args[1].tag == .string)
            args[1].data.string.data.data
        else
            null;

        const response = client.put(url, body) catch return Value.initNull();
        return try createResponseValue(vm, response);
    } else if (std.mem.eql(u8, method_name, "delete")) {
        if (args.len < 1 or args[0].tag != .string) return Value.initNull();
        const url = args[0].data.string.data.data;

        const response = client.delete(url) catch return Value.initNull();
        return try createResponseValue(vm, response);
    } else if (std.mem.eql(u8, method_name, "setHeader")) {
        if (args.len < 2) return Value.initNull();
        if (args[0].tag != .string or args[1].tag != .string) return Value.initNull();

        const name = args[0].data.string.data.data;
        const value = args[1].data.string.data.data;
        try client.setHeader(name, value);
        return Value.initNull();
    }

    return error.MethodNotFound;
}

/// 调用Router方法
pub fn callRouterMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []Value) !Value {
    const router = @as(*http_server.Router, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "get")) {
        if (args.len < 2) return Value.initNull();
        if (args[0].tag != .string) return Value.initNull();

        const path = args[0].data.string.data.data;
        try router.get(path, args[1]);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "post")) {
        if (args.len < 2) return Value.initNull();
        if (args[0].tag != .string) return Value.initNull();

        const path = args[0].data.string.data.data;
        try router.post(path, args[1]);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "put")) {
        if (args.len < 2) return Value.initNull();
        if (args[0].tag != .string) return Value.initNull();

        const path = args[0].data.string.data.data;
        try router.put(path, args[1]);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "delete")) {
        if (args.len < 2) return Value.initNull();
        if (args[0].tag != .string) return Value.initNull();

        const path = args[0].data.string.data.data;
        try router.delete(path, args[1]);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "use")) {
        if (args.len < 1) return Value.initNull();
        try router.use(args[0]);
        return Value.initNull();
    }

    _ = vm;
    return error.MethodNotFound;
}

/// 创建响应Value
fn createResponseValue(vm: anytype, response: http_client.HttpResponse) !Value {
    const result = try Value.initArrayWithManager(&vm.memory_manager);
    const arr = result.data.array.data;

    const status_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "status") };
    try arr.set(vm.allocator, status_key, Value.initInt(response.status_code));

    const body_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "body") };
    const body_val = try Value.initStringWithManager(&vm.memory_manager, response.body);
    try arr.set(vm.allocator, body_key, body_val);

    const success_key = types.ArrayKey{ .string = try types.PHPString.init(vm.allocator, "success") };
    try arr.set(vm.allocator, success_key, Value.initBool(response.isSuccess()));

    return result;
}
