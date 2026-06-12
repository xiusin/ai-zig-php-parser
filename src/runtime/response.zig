const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const cookie = @import("cookie.zig");
const Cookie = cookie.Cookie;

/// HTTP响应
pub const HttpResponse = struct {
    allocator: std.mem.Allocator,
    status_code: u16,
    status_text: []const u8,
    headers: std.StringHashMap([]const u8),
    body: std.ArrayList(u8),
    cookies: std.ArrayList(Cookie),

    pub fn init(allocator: std.mem.Allocator) HttpResponse {
        return HttpResponse{
            .allocator = allocator,
            .status_code = 200,
            .status_text = "OK",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = .empty,
            .cookies = .empty,
        };
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
        self.body.deinit(self.allocator);
        self.cookies.deinit(self.allocator);
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

    /// 设置Cookie
    pub fn setCookie(self: *HttpResponse, new_cookie: Cookie) !void {
        try self.cookies.append(self.allocator, new_cookie);
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

        // Cookies
        for (self.cookies.items) |c| {
            try result.writer(self.allocator).print("Set-Cookie: {s}={s}", .{ c.name, c.value });
            if (c.expires) |expires| {
                // Output expires as Unix timestamp (simplified for compatibility)
                try result.writer(self.allocator).print("; Expires={d}", .{expires});
            }
            if (c.max_age) |max_age| {
                try result.writer(self.allocator).print("; Max-Age={d}", .{max_age});
            }
            if (c.path) |path| {
                try result.writer(self.allocator).print("; Path={s}", .{path});
            }
            if (c.domain) |domain| {
                try result.writer(self.allocator).print("; Domain={s}", .{domain});
            }
            if (c.secure) {
                try result.writer(self.allocator).print("; Secure", .{});
            }
            if (c.http_only) {
                try result.writer(self.allocator).print("; HttpOnly", .{});
            }
            if (c.same_site) |same_site| {
                switch (same_site) {
                    .Strict => try result.writer(self.allocator).print("; SameSite=Strict", .{}),
                    .Lax => try result.writer(self.allocator).print("; SameSite=Lax", .{}),
                    .None => try result.writer(self.allocator).print("; SameSite=None", .{}),
                }
            }
            try result.appendSlice(self.allocator, "\r\n");
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

    // setCookie
    pub fn setCookie(
        self: *PHPResponse,
        name: []const u8,
        value: []const u8,
        options: ?Value,
    ) !void {
        var new_cookie = Cookie{
            .name = name,
            .value = value,
        };

        if (options) |opts| {
            if (opts.isPartialArray()) {
                const arr = opts.data.partial_array;
                if (arr.get("expires")) |expires| {
                    if (expires.isInt()) {
                        new_cookie.expires = expires.data.integer;
                    }
                }
                if (arr.get("max_age")) |max_age| {
                    if (max_age.isInt()) {
                        new_cookie.max_age = @intCast(max_age.data.integer);
                    }
                }
                if (arr.get("path")) |path| {
                    if (path.isString()) {
                        new_cookie.path = path.data.string.ptr;
                    }
                }
                if (arr.get("domain")) |domain| {
                    if (domain.isString()) {
                        new_cookie.domain = domain.data.string.ptr;
                    }
                }
                if (arr.get("secure")) |secure| {
                    if (secure.isBool()) {
                        new_cookie.secure = secure.data.boolean;
                    }
                }
                if (arr.get("http_only")) |http_only| {
                    if (http_only.isBool()) {
                        new_cookie.http_only = http_only.data.boolean;
                    }
                }
                if (arr.get("same_site")) |same_site| {
                    if (same_site.isString()) {
                        if (std.ascii.eqlIgnoreCase(same_site.data.string.ptr, "Strict")) {
                            new_cookie.same_site = .Strict;
                        } else if (std.ascii.eqlIgnoreCase(same_site.data.string.ptr, "Lax")) {
                            new_cookie.same_site = .Lax;
                        } else if (std.ascii.eqlIgnoreCase(same_site.data.string.ptr, "None")) {
                            new_cookie.same_site = .None;
                        }
                    }
                }
            }
        }
        try self.response.setCookie(new_cookie);
    }

    /// 发送文本响应
    pub fn text(self: *PHPResponse, content: []const u8) !void {
        try self.response.setHeader("Content-Type", "text/plain; charset=utf-8");
        try self.response.setBody(content);
    }
};
