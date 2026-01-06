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

const cookie = @import("cookie.zig");
const session = @import("session.zig");
const Session = session.Session;
const SessionManager = session.SessionManager;
const Cookie = cookie.Cookie;
const request = @import("request.zig");
const response = @import("response.zig");
const HttpRequest = request.HttpRequest;
const PHPRequest = request.PHPRequest;
const HttpResponse = response.HttpResponse;
const PHPResponse = response.PHPResponse;


/// PHP内置HTTP服务器
/// 提供类似Bun的高性能HTTP服务能力
pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    address: net.Address,
    server: ?net.Server,
    running: std.atomic.Value(bool),
    handler: ?Value,
    vm: *anyopaque,
    session_manager: SessionManager,
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
        session_cookie_name: []const u8 = "kiro_session_id",
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
        session: ?*Session,
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
                .session = null,
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
            self.session = null;
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
            .session_manager = SessionManager.init(allocator),
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
        self.session_manager.deinit();
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
                try self.invokeHandler(handler, ctx);
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
    fn invokeHandler(self: *HttpServer, handler: Value, ctx: *RequestContext) !void {
        const VM = @import("vm.zig").VM;
        const vm_instance = @as(*VM, @ptrCast(@alignCast(self.vm)));

        const request_obj = try vm_instance.createObject(PHPRequest, .{
            ctx.request,
            ctx,
            vm_instance.allocator,
        });
        defer request_obj.release(vm_instance.allocator);

        const response_obj = try vm_instance.createObject(PHPResponse, .{
            ctx.response,
        });
        defer response_obj.release(vm_instance.allocator);

        const args = [_]Value{ request_obj, response_obj };
        _ = try self.callHandler(vm_instance, handler, &args);
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

/// PHP HTTP服务器函数绑定
pub fn registerHttpFunctions(vm: *anyopaque) !void {
    const VM = @import("vm.zig").VM;
    const vm_instance = @as(*VM, @ptrCast(@alignCast(vm)));

    // Register Request class
    const request_class = try vm_instance.createBuiltinClass("Request");
    try vm_instance.registerMethod(request_class, "getMethod", PHPRequest.getMethod);
    try vm_instance.registerMethod(request_class, "getPath", PHPRequest.getPath);
    try vm_instance.registerMethod(request_class, "getBody", PHPRequest.getBody);
    try vm_instance.registerMethod(request_class, "getHeader", PHPRequest.getHeader);
    try vm_instance.registerMethod(request_class, "getQuery", PHPRequest.getQuery);
    try vm_instance.registerMethod(request_class, "getCookie", PHPRequest.getCookie);
    try vm_instance.registerMethod(request_class, "session", PHPRequest.session);
    try vm_instance.registerMethod(request_class, "getParam", PHPRequest.getParam);

    // Register Response class
    const response_class = try vm_instance.createBuiltinClass("Response");
    try vm_instance.registerMethod(response_class, "setStatus", PHPResponse.setStatus);
    try vm_instance.registerMethod(response_class, "setHeader", PHPResponse.setHeader);
    try vm_instance.registerMethod(response_class, "setBody", PHPResponse.setBody);
    try vm_instance.registerMethod(response_class, "json", PHPResponse.json);
    try vm_instance.registerMethod(response_class, "html", PHPResponse.html);
    try vm_instance.registerMethod(response_class, "redirect", PHPResponse.redirect);
    try vm_instance.registerMethod(response_class, "text", PHPResponse.text);
    try vm_instance.registerMethod(response_class, "setCookie", PHPResponse.setCookie);

    // Register Session class
    const session_class = try vm_instance.createBuiltinClass("Session");
    try vm_instance.registerMethod(session_class, "get", session.PHPSession.get);
    try vm_instance.registerMethod(session_class, "set", session.PHPSession.set);
    try vm_instance.registerMethod(session_class, "has", session.PHPSession.has);
    try vm_instance.registerMethod(session_class, "destroy", session.PHPSession.destroy);
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
