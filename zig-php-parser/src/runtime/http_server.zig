const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const PHPObject = types.PHPObject;
const PHPClass = types.PHPClass;
const gc = types.gc;
const net = std.net;
const Thread = std.Thread;
const coroutine = @import("coroutine.zig");
const CoroutineManager = coroutine.CoroutineManager;
const http_client = @import("http_client.zig");
const request_arena = @import("request_arena.zig");
const RequestArena = request_arena.RequestArena;
const RequestArenaPool = request_arena.RequestArenaPool;

/// PHP内置HTTP服务器
/// 提供类似Bun的高性能HTTP服务能力
pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    address: net.Address,
    server: ?net.Server,
    running: std.atomic.Value(bool),
    handler: ?Value,
    vm: *anyopaque,
    worker_threads: std.ArrayList(Thread),
    max_connections: u32,
    keep_alive_timeout: u64,
    request_timeout: u64,
    coroutine_manager: ?*CoroutineManager,
    request_context_pool: std.ArrayList(*RequestContext),
    active_requests: std.atomic.Value(u32),
    /// 请求级Arena池 - 用于高效的请求内存管理 (Requirements: 4.1, 4.2, 4.3)
    arena_pool: ?*RequestArenaPool,

    pub const Config = struct {
        host: []const u8 = "127.0.0.1",
        port: u16 = 8080,
        max_connections: u32 = 1024,
        keep_alive_timeout: u64 = 5000, // ms
        request_timeout: u64 = 30000, // ms
        worker_count: u32 = 0, // 0 = auto (CPU count)
        enable_coroutines: bool = true, // 启用协程处理
        context_pool_size: u32 = 100, // 上下文池大小
        enable_request_arena: bool = true, // 启用请求级Arena内存管理
        arena_pool_size: u32 = 50, // Arena池大小
    };

    /// 请求上下文 - 每个请求独立的上下文，防止数据串扰
    pub const RequestContext = struct {
        id: u64,
        request: ?*const HttpRequest,
        response: ?*HttpResponse,
        locals: std.StringHashMap(Value),
        start_time: i64,
        allocator: std.mem.Allocator,
        parent_vm: *anyopaque,
        coroutine_id: ?u64,
        /// 请求级Arena - 用于请求内的快速内存分配 (Requirements: 4.1, 4.2)
        arena: ?*RequestArena,

        pub fn init(allocator: std.mem.Allocator, id: u64, parent_vm: *anyopaque) RequestContext {
            return RequestContext{
                .id = id,
                .request = null,
                .response = null,
                .locals = std.StringHashMap(Value).init(allocator),
                .start_time = std.time.milliTimestamp(),
                .allocator = allocator,
                .parent_vm = parent_vm,
                .coroutine_id = null,
                .arena = null,
            };
        }

        pub fn deinit(self: *RequestContext) void {
            var iter = self.locals.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.release(self.allocator);
            }
            self.locals.deinit();
            // Arena由ArenaPool管理，不在这里释放
        }

        pub fn reset(self: *RequestContext, id: u64) void {
            var iter = self.locals.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.release(self.allocator);
            }
            self.locals.clearRetainingCapacity();
            self.id = id;
            self.request = null;
            self.response = null;
            self.start_time = std.time.milliTimestamp();
            self.coroutine_id = null;
            // Arena会在acquireContext时重新分配
            self.arena = null;
        }

        /// 获取请求局部变量
        pub fn getLocal(self: *RequestContext, name: []const u8) ?Value {
            return self.locals.get(name);
        }

        /// 设置请求局部变量
        pub fn setLocal(self: *RequestContext, name: []const u8, value: Value) !void {
            if (self.locals.get(name)) |old| {
                old.release(self.allocator);
            }
            _ = value.retain();
            try self.locals.put(name, value);
        }

        /// 获取请求执行时间（毫秒）
        pub fn getElapsedTime(self: *RequestContext) i64 {
            return std.time.milliTimestamp() - self.start_time;
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: Config, vm: *anyopaque) !HttpServer {
        const address = try net.Address.parseIp4(config.host, config.port);

        var server = HttpServer{
            .allocator = allocator,
            .address = address,
            .server = null,
            .running = std.atomic.Value(bool).init(false),
            .handler = null,
            .vm = vm,
            .worker_threads = .empty,
            .max_connections = config.max_connections,
            .keep_alive_timeout = config.keep_alive_timeout,
            .request_timeout = config.request_timeout,
            .coroutine_manager = null,
            .request_context_pool = .empty,
            .active_requests = std.atomic.Value(u32).init(0),
            .arena_pool = null,
        };

        // 初始化协程管理器
        if (config.enable_coroutines) {
            server.coroutine_manager = try allocator.create(CoroutineManager);
            server.coroutine_manager.?.* = CoroutineManager.init(allocator);
        }

        // 初始化请求级Arena池 (Requirements: 4.1, 4.2, 4.3)
        if (config.enable_request_arena) {
            server.arena_pool = try allocator.create(RequestArenaPool);
            server.arena_pool.?.* = RequestArenaPool.init(allocator, allocator, config.arena_pool_size);
        }

        // 预分配上下文池
        var i: u32 = 0;
        while (i < config.context_pool_size) : (i += 1) {
            const ctx = try allocator.create(RequestContext);
            ctx.* = RequestContext.init(allocator, 0, vm);
            try server.request_context_pool.append(allocator, ctx);
        }

        return server;
    }

    pub fn deinit(self: *HttpServer) void {
        self.stop();
        self.worker_threads.deinit(self.allocator);
        if (self.handler) |h| {
            h.release(self.allocator);
        }

        // 清理协程管理器
        if (self.coroutine_manager) |cm| {
            cm.deinit();
            self.allocator.destroy(cm);
        }

        // 清理请求级Arena池 (Requirements: 4.6)
        if (self.arena_pool) |pool| {
            pool.deinit();
            self.allocator.destroy(pool);
        }

        // 清理上下文池
        for (self.request_context_pool.items) |ctx| {
            ctx.deinit();
            self.allocator.destroy(ctx);
        }
        self.request_context_pool.deinit(self.allocator);
    }

    /// 设置请求处理器
    pub fn setHandler(self: *HttpServer, handler: Value) void {
        if (self.handler) |h| {
            h.release(self.allocator);
        }
        self.handler = handler.retain();
    }

    /// 启动服务器
    pub fn start(self: *HttpServer) !void {
        if (self.running.load(.seq_cst)) {
            return error.ServerAlreadyRunning;
        }

        self.server = try self.address.listen(.{
            .reuse_address = true,
        });

        self.running.store(true, .seq_cst);

        // 启动主接受循环
        while (self.running.load(.seq_cst)) {
            const connection = self.server.?.accept() catch |err| switch (err) {
                error.ConnectionAborted => continue,
                else => return err,
            };

            // 处理连接
            self.handleConnection(connection) catch |err| {
                std.debug.print("Connection error: {}\n", .{err});
            };
        }
    }

    /// 停止服务器
    pub fn stop(self: *HttpServer) void {
        self.running.store(false, .seq_cst);
        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
    }

    /// 处理单个连接（支持协程上下文隔离）
    fn handleConnection(self: *HttpServer, connection: net.Server.Connection) !void {
        defer connection.stream.close();

        // 获取或创建请求上下文
        const ctx = self.acquireContext();
        defer self.releaseContext(ctx);

        _ = self.active_requests.fetchAdd(1, .seq_cst);
        defer _ = self.active_requests.fetchSub(1, .seq_cst);

        // 读取HTTP请求
        var buffer: [8192]u8 = undefined;
        const bytes_read = try connection.stream.read(&buffer);

        if (bytes_read == 0) return;

        // 解析HTTP请求
        var request = try HttpRequest.parse(self.allocator, buffer[0..bytes_read]);
        defer request.deinit(self.allocator);

        // 创建响应
        var response = HttpResponse.init(self.allocator);
        defer response.deinit();

        // 绑定到上下文
        ctx.request = &request;
        ctx.response = &response;

        // 调用处理器（在协程上下文中）
        if (self.handler) |handler| {
            if (self.coroutine_manager) |cm| {
                // 使用协程处理请求
                const coroutine_id = try cm.spawn(handler, &[_]Value{});
                ctx.coroutine_id = coroutine_id;
                try cm.run(self.vm);
            } else {
                // 直接处理
                try self.invokeHandler(handler, &request, &response);
            }
        } else {
            response.setStatus(404);
            try response.setBody("Not Found");
        }

        // 发送响应
        const response_bytes = try response.toBytes();
        defer self.allocator.free(response_bytes);
        _ = try connection.stream.write(response_bytes);
    }

    /// 获取请求上下文（从池中获取或新建）
    fn acquireContext(self: *HttpServer) *RequestContext {
        var ctx: *RequestContext = undefined;

        if (self.request_context_pool.items.len > 0) {
            if (self.request_context_pool.pop()) |c| {
                ctx = c;
                ctx.reset(self.generateContextId());
            } else {
                ctx = self.allocator.create(RequestContext) catch unreachable;
                ctx.* = RequestContext.init(self.allocator, self.generateContextId(), self.vm);
            }
        } else {
            ctx = self.allocator.create(RequestContext) catch unreachable;
            ctx.* = RequestContext.init(self.allocator, self.generateContextId(), self.vm);
        }

        // 为请求分配Arena (Requirements: 4.1, 4.2)
        if (self.arena_pool) |pool| {
            ctx.arena = pool.acquire() catch null;
        }

        return ctx;
    }

    /// 释放请求上下文（归还到池中）
    fn releaseContext(self: *HttpServer, ctx: *RequestContext) void {
        // 释放请求Arena (Requirements: 4.3, 4.6)
        if (ctx.arena) |arena| {
            if (self.arena_pool) |pool| {
                pool.release(arena);
            }
            ctx.arena = null;
        }

        if (self.request_context_pool.items.len < 100) {
            self.request_context_pool.append(self.allocator, ctx) catch {
                ctx.deinit();
                self.allocator.destroy(ctx);
            };
        } else {
            ctx.deinit();
            self.allocator.destroy(ctx);
        }
    }

    /// 生成唯一的上下文ID
    fn generateContextId(self: *HttpServer) u64 {
        _ = self;
        return @intCast(std.time.nanoTimestamp());
    }

    /// 获取当前活跃请求数
    pub fn getActiveRequestCount(self: *HttpServer) u32 {
        return self.active_requests.load(.seq_cst);
    }

    /// 调用PHP处理器
    fn invokeHandler(self: *HttpServer, handler: Value, request: *const HttpRequest, response: *HttpResponse) !void {
        const VM = @import("vm.zig").VM;
        const vm_instance = @as(*VM, @ptrCast(@alignCast(self.vm)));

        // 创建Request对象
        const req_value = try self.createRequestValue(vm_instance, request);
        defer req_value.release(self.allocator);

        // 创建Response对象
        const res_value = try self.createResponseValue(vm_instance, response);
        defer res_value.release(self.allocator);

        // 调用处理器
        const args = [_]Value{ req_value, res_value };
        _ = try self.callHandler(vm_instance, handler, &args);
    }

    /// 创建Request Value对象
    fn createRequestValue(self: *HttpServer, vm_instance: anytype, request: *const HttpRequest) !Value {
        const result = try Value.initArrayWithManager(&vm_instance.memory_manager);
        const arr = result.data.array.data;

        // method
        const method_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, "method") };
        const method_str = switch (request.method) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
            .TRACE => "TRACE",
            .CONNECT => "CONNECT",
        };
        const method_val = try Value.initStringWithManager(&vm_instance.memory_manager, method_str);
        try arr.set(self.allocator, method_key, method_val);
        method_key.string.release(self.allocator);

        // path
        const path_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, "path") };
        const path_val = try Value.initStringWithManager(&vm_instance.memory_manager, request.path);
        try arr.set(self.allocator, path_key, path_val);
        path_key.string.release(self.allocator);

        // body
        const body_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, "body") };
        const body_val = try Value.initStringWithManager(&vm_instance.memory_manager, request.body);
        try arr.set(self.allocator, body_key, body_val);
        body_key.string.release(self.allocator);

        // headers
        const headers_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, "headers") };
        const headers_val = try Value.initArrayWithManager(&vm_instance.memory_manager);
        const headers_arr = headers_val.data.array.data;

        var header_iter = request.headers.iterator();
        while (header_iter.next()) |entry| {
            const h_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, entry.key_ptr.*) };
            const h_val = try Value.initStringWithManager(&vm_instance.memory_manager, entry.value_ptr.*);
            try headers_arr.set(self.allocator, h_key, h_val);
            h_key.string.release(self.allocator);
        }
        try arr.set(self.allocator, headers_key, headers_val);
        headers_key.string.release(self.allocator);

        // query
        const query_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, "query") };
        const query_val = try Value.initArrayWithManager(&vm_instance.memory_manager);
        const query_arr = query_val.data.array.data;

        var query_iter = request.query_params.iterator();
        while (query_iter.next()) |entry| {
            const q_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, entry.key_ptr.*) };
            const q_val = try Value.initStringWithManager(&vm_instance.memory_manager, entry.value_ptr.*);
            try query_arr.set(self.allocator, q_key, q_val);
            q_key.string.release(self.allocator);
        }
        try arr.set(self.allocator, query_key, query_val);
        query_key.string.release(self.allocator);

        return result;
    }

    /// 创建Response Value对象
    fn createResponseValue(self: *HttpServer, vm_instance: anytype, response: *HttpResponse) !Value {
        _ = response;
        const result = try Value.initArrayWithManager(&vm_instance.memory_manager);
        const arr = result.data.array.data;

        // status
        const status_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, "status") };
        try arr.set(self.allocator, status_key, Value.initInt(200));
        status_key.string.release(self.allocator);

        // headers
        const headers_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, "headers") };
        const headers_val = try Value.initArrayWithManager(&vm_instance.memory_manager);
        try arr.set(self.allocator, headers_key, headers_val);
        headers_key.string.release(self.allocator);

        // body
        const body_key = types.ArrayKey{ .string = try types.PHPString.init(self.allocator, "body") };
        const body_val = try Value.initStringWithManager(&vm_instance.memory_manager, "");
        try arr.set(self.allocator, body_key, body_val);
        body_key.string.release(self.allocator);

        return result;
    }

    /// 调用处理器回调
    fn callHandler(self: *HttpServer, vm_instance: anytype, handler: Value, args: []const Value) !Value {
        _ = self;
        return switch (handler.tag) {
            .builtin_function => {
                const function: *const fn (anytype, []const Value) anyerror!Value = @ptrCast(@alignCast(handler.data.builtin_function));
                return function(vm_instance, args);
            },
            .user_function => {
                return vm_instance.callUserFunction(handler.data.user_function.data, args);
            },
            .closure => {
                return vm_instance.callClosure(handler.data.closure.data, args);
            },
            .arrow_function => {
                return vm_instance.callArrowFunction(handler.data.arrow_function.data, args);
            },
            else => Value.initNull(),
        };
    }

    /// 获取服务器状态信息
    pub fn getStats(self: *HttpServer) ServerStats {
        return ServerStats{
            .active_requests = self.active_requests.load(.seq_cst),
            .context_pool_size = @intCast(self.request_context_pool.items.len),
            .is_running = self.running.load(.seq_cst),
        };
    }

    pub const ServerStats = struct {
        active_requests: u32,
        context_pool_size: u32,
        is_running: bool,
    };
};

/// HTTP请求
pub const HttpRequest = struct {
    method: Method,
    path: []const u8,
    version: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    query_params: std.StringHashMap([]const u8),

    pub const Method = enum {
        GET,
        POST,
        PUT,
        DELETE,
        PATCH,
        HEAD,
        OPTIONS,
        TRACE,
        CONNECT,

        pub fn fromString(str: []const u8) ?Method {
            const methods = .{
                .{ "GET", Method.GET },
                .{ "POST", Method.POST },
                .{ "PUT", Method.PUT },
                .{ "DELETE", Method.DELETE },
                .{ "PATCH", Method.PATCH },
                .{ "HEAD", Method.HEAD },
                .{ "OPTIONS", Method.OPTIONS },
                .{ "TRACE", Method.TRACE },
                .{ "CONNECT", Method.CONNECT },
            };

            inline for (methods) |m| {
                if (std.mem.eql(u8, str, m[0])) {
                    return m[1];
                }
            }
            return null;
        }
    };

    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !HttpRequest {
        var request = HttpRequest{
            .method = .GET,
            .path = "/",
            .version = "HTTP/1.1",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .query_params = std.StringHashMap([]const u8).init(allocator),
        };

        var lines = std.mem.splitSequence(u8, data, "\r\n");

        // 解析请求行
        if (lines.next()) |request_line| {
            var parts = std.mem.splitScalar(u8, request_line, ' ');

            if (parts.next()) |method_str| {
                request.method = Method.fromString(method_str) orelse .GET;
            }

            if (parts.next()) |path| {
                // 解析查询参数
                if (std.mem.indexOf(u8, path, "?")) |query_start| {
                    request.path = path[0..query_start];
                    const query_string = path[query_start + 1 ..];
                    try request.parseQueryParams(query_string);
                } else {
                    request.path = path;
                }
            }

            if (parts.next()) |version| {
                request.version = version;
            }
        }

        // 解析头部
        var in_headers = true;
        while (lines.next()) |line| {
            if (line.len == 0) {
                in_headers = false;
                continue;
            }

            if (in_headers) {
                if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                    const key = line[0..colon_pos];
                    const value = line[colon_pos + 2 ..];
                    try request.headers.put(key, value);
                }
            } else {
                // Body部分
                request.body = line;
            }
        }

        return request;
    }

    fn parseQueryParams(self: *HttpRequest, query_string: []const u8) !void {
        var params = std.mem.splitScalar(u8, query_string, '&');
        while (params.next()) |param| {
            if (std.mem.indexOf(u8, param, "=")) |eq_pos| {
                const key = param[0..eq_pos];
                const value = param[eq_pos + 1 ..];
                try self.query_params.put(key, value);
            }
        }
    }

    pub fn deinit(self: *const HttpRequest, allocator: std.mem.Allocator) void {
        _ = allocator;
        // StringHashMap中的字符串来自原始buffer，不需要单独释放
        @constCast(&self.headers).deinit();
        @constCast(&self.query_params).deinit();
    }

    /// 获取头部值
    pub fn getHeader(self: *const HttpRequest, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// 获取查询参数
    pub fn getQueryParam(self: *const HttpRequest, name: []const u8) ?[]const u8 {
        return self.query_params.get(name);
    }
};

/// HTTP响应
pub const HttpResponse = struct {
    allocator: std.mem.Allocator,
    status_code: u16,
    status_text: []const u8,
    headers: std.StringHashMap([]const u8),
    body: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) HttpResponse {
        return HttpResponse{
            .allocator = allocator,
            .status_code = 200,
            .status_text = "OK",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = .empty,
        };
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
        self.body.deinit(self.allocator);
    }

    /// 设置状态码
    pub fn setStatus(self: *HttpResponse, code: u16) void {
        self.status_code = code;
        self.status_text = getStatusText(code);
    }

    /// 设置头部
    pub fn setHeader(self: *HttpResponse, name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }

    /// 设置响应体
    pub fn setBody(self: *HttpResponse, content: []const u8) !void {
        self.body.clearRetainingCapacity();
        try self.body.appendSlice(self.allocator, content);
    }

    /// 追加响应体
    pub fn appendBody(self: *HttpResponse, content: []const u8) !void {
        try self.body.appendSlice(self.allocator, content);
    }

    /// 转换为HTTP响应字节
    pub fn toBytes(self: *HttpResponse) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;

        // 状态行
        try result.writer(self.allocator).print("HTTP/1.1 {d} {s}\r\n", .{ self.status_code, self.status_text });

        // 自动添加Content-Length
        try result.writer(self.allocator).print("Content-Length: {d}\r\n", .{self.body.items.len});

        // 头部
        var header_iter = self.headers.iterator();
        while (header_iter.next()) |entry| {
            try result.writer(self.allocator).print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // 空行分隔
        try result.appendSlice(self.allocator, "\r\n");

        // 响应体
        try result.appendSlice(self.allocator, self.body.items);

        return result.toOwnedSlice(self.allocator);
    }

    /// 发送JSON响应
    pub fn json(self: *HttpResponse, data: []const u8) !void {
        try self.setHeader("Content-Type", "application/json");
        try self.setBody(data);
    }

    /// 发送HTML响应
    pub fn html(self: *HttpResponse, content: []const u8) !void {
        try self.setHeader("Content-Type", "text/html; charset=utf-8");
        try self.setBody(content);
    }

    /// 发送重定向
    pub fn redirect(self: *HttpResponse, url: []const u8, code: u16) !void {
        self.setStatus(code);
        try self.setHeader("Location", url);
    }

    fn getStatusText(code: u16) []const u8 {
        return switch (code) {
            100 => "Continue",
            101 => "Switching Protocols",
            200 => "OK",
            201 => "Created",
            202 => "Accepted",
            204 => "No Content",
            301 => "Moved Permanently",
            302 => "Found",
            303 => "See Other",
            304 => "Not Modified",
            307 => "Temporary Redirect",
            308 => "Permanent Redirect",
            400 => "Bad Request",
            401 => "Unauthorized",
            403 => "Forbidden",
            404 => "Not Found",
            405 => "Method Not Allowed",
            408 => "Request Timeout",
            409 => "Conflict",
            410 => "Gone",
            413 => "Payload Too Large",
            414 => "URI Too Long",
            415 => "Unsupported Media Type",
            422 => "Unprocessable Entity",
            429 => "Too Many Requests",
            500 => "Internal Server Error",
            501 => "Not Implemented",
            502 => "Bad Gateway",
            503 => "Service Unavailable",
            504 => "Gateway Timeout",
            else => "Unknown",
        };
    }
};

/// 路由器 - 提供简单的路由功能
pub const Router = struct {
    allocator: std.mem.Allocator,
    routes: std.ArrayList(Route),
    middleware: std.ArrayList(Value),

    pub const Route = struct {
        method: HttpRequest.Method,
        path: []const u8,
        handler: Value,
        params: std.StringHashMap(usize), // 参数名 -> 位置
    };

    pub fn init(allocator: std.mem.Allocator) Router {
        return Router{
            .allocator = allocator,
            .routes = .empty,
            .middleware = .empty,
        };
    }

    pub fn deinit(self: *Router) void {
        for (self.routes.items) |*route| {
            route.handler.release(self.allocator);
            route.params.deinit();
        }
        self.routes.deinit(self.allocator);

        for (self.middleware.items) |*mw| {
            mw.release(self.allocator);
        }
        self.middleware.deinit(self.allocator);
    }

    /// 添加GET路由
    pub fn get(self: *Router, path: []const u8, handler: Value) !void {
        try self.addRoute(.GET, path, handler);
    }

    /// 添加POST路由
    pub fn post(self: *Router, path: []const u8, handler: Value) !void {
        try self.addRoute(.POST, path, handler);
    }

    /// 添加PUT路由
    pub fn put(self: *Router, path: []const u8, handler: Value) !void {
        try self.addRoute(.PUT, path, handler);
    }

    /// 添加DELETE路由
    pub fn delete(self: *Router, path: []const u8, handler: Value) !void {
        try self.addRoute(.DELETE, path, handler);
    }

    /// 添加路由
    pub fn addRoute(self: *Router, method: HttpRequest.Method, path: []const u8, handler: Value) !void {
        var route = Route{
            .method = method,
            .path = path,
            .handler = handler.retain(),
            .params = std.StringHashMap(usize).init(self.allocator),
        };

        // 解析路径参数 (如 /users/:id)
        var segments = std.mem.splitScalar(u8, path, '/');
        var pos: usize = 0;
        while (segments.next()) |segment| {
            if (segment.len > 0 and segment[0] == ':') {
                try route.params.put(segment[1..], pos);
            }
            pos += 1;
        }

        try self.routes.append(self.allocator, route);
    }

    /// 添加中间件
    pub fn use(self: *Router, middleware: Value) !void {
        try self.middleware.append(self.allocator, middleware.retain());
    }

    /// 匹配路由
    pub fn match(self: *Router, method: HttpRequest.Method, path: []const u8) ?*Route {
        for (self.routes.items) |*route| {
            if (route.method == method and self.pathMatches(route.path, path)) {
                return route;
            }
        }
        return null;
    }

    fn pathMatches(self: *Router, pattern: []const u8, path: []const u8) bool {
        _ = self;
        var pattern_segments = std.mem.splitScalar(u8, pattern, '/');
        var path_segments = std.mem.splitScalar(u8, path, '/');

        while (true) {
            const pattern_seg = pattern_segments.next();
            const path_seg = path_segments.next();

            if (pattern_seg == null and path_seg == null) {
                return true;
            }

            if (pattern_seg == null or path_seg == null) {
                return false;
            }

            // 参数匹配
            if (pattern_seg.?.len > 0 and pattern_seg.?[0] == ':') {
                continue;
            }

            // 精确匹配
            if (!std.mem.eql(u8, pattern_seg.?, path_seg.?)) {
                return false;
            }
        }
    }
};

/// PHP 内置 Request 类
pub const PHPRequest = struct {
    request: *const HttpRequest,
    allocator: std.mem.Allocator,
    params: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, request: *const HttpRequest) PHPRequest {
        return PHPRequest{
            .request = request,
            .allocator = allocator,
            .params = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PHPRequest) void {
        self.params.deinit();
    }

    /// 获取请求方法
    pub fn getMethod(self: *const PHPRequest) []const u8 {
        return switch (self.request.method) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
            .TRACE => "TRACE",
            .CONNECT => "CONNECT",
        };
    }

    /// 获取请求路径
    pub fn getPath(self: *const PHPRequest) []const u8 {
        return self.request.path;
    }

    /// 获取请求体
    pub fn getBody(self: *const PHPRequest) []const u8 {
        return self.request.body;
    }

    /// 获取请求头
    pub fn getHeader(self: *const PHPRequest, name: []const u8) ?[]const u8 {
        return self.request.getHeader(name);
    }

    /// 获取查询参数
    pub fn getQuery(self: *const PHPRequest, name: []const u8) ?[]const u8 {
        return self.request.getQueryParam(name);
    }

    /// 获取路由参数
    pub fn getParam(self: *const PHPRequest, name: []const u8) ?[]const u8 {
        return self.params.get(name);
    }

    /// 设置路由参数
    pub fn setParam(self: *PHPRequest, name: []const u8, value: []const u8) !void {
        try self.params.put(name, value);
    }
};

/// PHP 内置 Response 类
pub const PHPResponse = struct {
    response: *HttpResponse,

    pub fn init(response: *HttpResponse) PHPResponse {
        return PHPResponse{
            .response = response,
        };
    }

    /// 设置状态码
    pub fn setStatus(self: *PHPResponse, code: u16) void {
        self.response.setStatus(code);
    }

    /// 设置响应头
    pub fn setHeader(self: *PHPResponse, name: []const u8, value: []const u8) !void {
        try self.response.setHeader(name, value);
    }

    /// 设置响应体
    pub fn setBody(self: *PHPResponse, content: []const u8) !void {
        try self.response.setBody(content);
    }

    /// 发送 JSON 响应
    pub fn json(self: *PHPResponse, data: []const u8) !void {
        try self.response.json(data);
    }

    /// 发送 HTML 响应
    pub fn html(self: *PHPResponse, content: []const u8) !void {
        try self.response.html(content);
    }

    /// 发送重定向
    pub fn redirect(self: *PHPResponse, url: []const u8, code: u16) !void {
        try self.response.redirect(url, code);
    }

    /// 发送文本响应
    pub fn text(self: *PHPResponse, content: []const u8) !void {
        try self.response.setHeader("Content-Type", "text/plain; charset=utf-8");
        try self.response.setBody(content);
    }
};

/// PHP HTTP服务器函数绑定
pub fn registerHttpFunctions(stdlib: anytype) !void {
    _ = stdlib;
    // 注册 http_server_create, http_server_start 等函数
    // 注册 Request, Response, Router 类
}

test "http request parsing" {
    const allocator = std.testing.allocator;

    const raw_request = "GET /test?foo=bar HTTP/1.1\r\nHost: localhost\r\nContent-Type: text/plain\r\n\r\n";

    const request = try HttpRequest.parse(allocator, raw_request);
    defer request.deinit(allocator);

    try std.testing.expect(request.method == .GET);
    try std.testing.expectEqualStrings("/test", request.path);
    try std.testing.expectEqualStrings("bar", request.getQueryParam("foo").?);
}

test "http response building" {
    const allocator = std.testing.allocator;

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    response.setStatus(200);
    try response.setHeader("Content-Type", "text/plain");
    try response.setBody("Hello, World!");

    const bytes = try response.toBytes();
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "Hello, World!") != null);
}
