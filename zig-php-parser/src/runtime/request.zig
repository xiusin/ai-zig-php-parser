const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const session = @import("session.zig");
const Session = session.Session;
const PHPSession = session.PHPSession;
const HttpServer = @import("http_server.zig").HttpServer;
const HttpResponse = @import("response.zig").HttpResponse;

/// HTTP请求
pub const HttpRequest = struct {
    method: Method,
    path: []const u8,
    version: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    query_params: std.StringHashMap([]const u8),
    cookies: std.StringHashMap([]const u8),

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
            .cookies = std.StringHashMap([]const u8).init(allocator),
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

                    if (std.ascii.eqlIgnoreCase(key, "Cookie")) {
                        try request.parseCookies(value);
                    }
                }
            } else {
                // Body部分
                request.body = line;
            }
        }

        return request;
    }

    fn parseCookies(self: *HttpRequest, cookie_string: []const u8) !void {
        var cookies = std.mem.splitScalar(u8, cookie_string, ';');
        while (cookies.next()) |cookie| {
            const trimmed_cookie = std.mem.trim(u8, cookie, " \t");
            if (std.mem.indexOf(u8, trimmed_cookie, "=")) |eq_pos| {
                const key = trimmed_cookie[0..eq_pos];
                const value = trimmed_cookie[eq_pos + 1 ..];
                try self.cookies.put(key, value);
            }
        }
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
        @constCast(&self.cookies).deinit();
    }

    /// 获取头部值
    pub fn getHeader(self: *const HttpRequest, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// 获取查询参数
    pub fn getQueryParam(self: *const HttpRequest, name: []const u8) ?[]const u8 {
        return self.query_params.get(name);
    }

    /// 获取Cookie值
    pub fn getCookie(self: *const HttpRequest, name: []const u8) ?[]const u8 {
        return self.cookies.get(name);
    }
};

/// PHP 内置 Request 类
pub const PHPRequest = struct {
    request: *const HttpRequest,
    ctx: *HttpServer.RequestContext,
    params: std.StringHashMap([]const u8),

    pub fn init(request: *const HttpRequest, ctx: *HttpServer.RequestContext, allocator: std.mem.Allocator) PHPRequest {
        return PHPRequest{
            .request = request,
            .ctx = ctx,
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

    /// 获取Cookie
    pub fn getCookie(self: *const PHPRequest, name: []const u8) ?[]const u8 {
        return self.request.getCookie(name);
    }

    /// 获取或创建Session
    pub fn session(self: *PHPRequest, vm: *anyopaque) !Value {
        const VM = @import("vm.zig").VM;
        const vm_instance = @as(*VM, @ptrCast(@alignCast(vm)));

        if (self.ctx.session) |sess| {
            return vm_instance.createObject(PHPSession, .{sess});
        }

        const server = @fieldParentPtr(HttpServer, "request_context_pool", self.ctx);
        const session_id = self.request.getCookie(server.config.session_cookie_name);

        if (session_id) |id| {
            if (server.session_manager.getSession(id)) |sess| {
                self.ctx.session = sess;
                return vm_instance.createObject(PHPSession, .{sess});
            }
        }

        const new_session = try server.session_manager.createSession();
        self.ctx.session = new_session;

        // Set the session ID cookie on the response
        const cookie = HttpResponse.Cookie{
            .name = server.config.session_cookie_name,
            .value = new_session.id,
            .http_only = true,
            .path = "/",
        };
        try self.ctx.response.?.setCookie(cookie);

        return vm_instance.createObject(PHPSession, .{new_session});
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
