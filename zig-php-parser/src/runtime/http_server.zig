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

    pub const Config = struct {
        host: []const u8 = "127.0.0.1",
        port: u16 = 8080,
        max_connections: u32 = 1024,
        keep_alive_timeout: u64 = 5000, // ms
        request_timeout: u64 = 30000, // ms
        worker_count: u32 = 0, // 0 = auto (CPU count)
    };

    pub fn init(allocator: std.mem.Allocator, config: Config, vm: *anyopaque) !HttpServer {
        const address = try net.Address.parseIp4(config.host, config.port);

        return HttpServer{
            .allocator = allocator,
            .address = address,
            .server = null,
            .running = std.atomic.Value(bool).init(false),
            .handler = null,
            .vm = vm,
            .worker_threads = std.ArrayList(Thread).init(allocator),
            .max_connections = config.max_connections,
            .keep_alive_timeout = config.keep_alive_timeout,
            .request_timeout = config.request_timeout,
        };
    }

    pub fn deinit(self: *HttpServer) void {
        self.stop();
        self.worker_threads.deinit();
        if (self.handler) |h| {
            h.release(self.allocator);
        }
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

    /// 处理单个连接
    fn handleConnection(self: *HttpServer, connection: net.Server.Connection) !void {
        defer connection.stream.close();

        // 读取HTTP请求
        var buffer: [8192]u8 = undefined;
        const bytes_read = try connection.stream.read(&buffer);

        if (bytes_read == 0) return;

        // 解析HTTP请求
        const request = try HttpRequest.parse(self.allocator, buffer[0..bytes_read]);
        defer request.deinit(self.allocator);

        // 创建响应
        var response = HttpResponse.init(self.allocator);
        defer response.deinit();

        // 调用处理器
        if (self.handler) |handler| {
            try self.invokeHandler(handler, &request, &response);
        } else {
            response.setStatus(404);
            try response.setBody("Not Found");
        }

        // 发送响应
        const response_bytes = try response.toBytes();
        defer self.allocator.free(response_bytes);
        _ = try connection.stream.write(response_bytes);
    }

    /// 调用PHP处理器
    fn invokeHandler(self: *HttpServer, handler: Value, request: *const HttpRequest, response: *HttpResponse) !void {
        _ = self;
        _ = handler;
        _ = request;
        // 这里需要调用VM来执行PHP回调
        // 将request转换为PHP对象，将response作为引用传入
        response.setStatus(200);
        try response.setBody("Hello from Zig-PHP!");
    }
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
            .body = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
        self.body.deinit();
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
        try self.body.appendSlice(content);
    }

    /// 追加响应体
    pub fn appendBody(self: *HttpResponse, content: []const u8) !void {
        try self.body.appendSlice(content);
    }

    /// 转换为HTTP响应字节
    pub fn toBytes(self: *HttpResponse) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        // 状态行
        try result.writer().print("HTTP/1.1 {d} {s}\r\n", .{ self.status_code, self.status_text });

        // 自动添加Content-Length
        try result.writer().print("Content-Length: {d}\r\n", .{self.body.items.len});

        // 头部
        var header_iter = self.headers.iterator();
        while (header_iter.next()) |entry| {
            try result.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // 空行分隔
        try result.appendSlice("\r\n");

        // 响应体
        try result.appendSlice(self.body.items);

        return result.toOwnedSlice();
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
            .routes = std.ArrayList(Route).init(allocator),
            .middleware = std.ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Router) void {
        for (self.routes.items) |*route| {
            route.handler.release(self.allocator);
            route.params.deinit();
        }
        self.routes.deinit();

        for (self.middleware.items) |*mw| {
            mw.release(self.allocator);
        }
        self.middleware.deinit();
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

        try self.routes.append(route);
    }

    /// 添加中间件
    pub fn use(self: *Router, middleware: Value) !void {
        try self.middleware.append(middleware.retain());
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
pub fn registerHttpFunctions(stdlib: anytype) !void {
    _ = stdlib;
    // 注册 http_server_create, http_server_start 等函数
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
