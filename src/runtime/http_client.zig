const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const net = std.net;

/// HTTP客户端 - 用于发起外部HTTP请求
/// 采用Go风格的简洁API设计
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    timeout: u64, // 超时时间（毫秒）
    follow_redirects: bool,
    max_redirects: u8,
    user_agent: []const u8,
    default_headers: std.StringHashMap([]const u8),

    pub const Config = struct {
        timeout: u64 = 30000, // 默认30秒
        follow_redirects: bool = true,
        max_redirects: u8 = 10,
        user_agent: []const u8 = "ZigPHP/1.0",
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) HttpClient {
        return HttpClient{
            .allocator = allocator,
            .timeout = config.timeout,
            .follow_redirects = config.follow_redirects,
            .max_redirects = config.max_redirects,
            .user_agent = config.user_agent,
            .default_headers = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.default_headers.deinit();
    }

    /// 发送GET请求
    pub fn get(self: *HttpClient, url: []const u8) !HttpResponse {
        return self.request(.GET, url, null, null);
    }

    /// 发送POST请求
    pub fn post(self: *HttpClient, url: []const u8, body: ?[]const u8) !HttpResponse {
        return self.request(.POST, url, body, null);
    }

    /// 发送PUT请求
    pub fn put(self: *HttpClient, url: []const u8, body: ?[]const u8) !HttpResponse {
        return self.request(.PUT, url, body, null);
    }

    /// 发送DELETE请求
    pub fn delete(self: *HttpClient, url: []const u8) !HttpResponse {
        return self.request(.DELETE, url, null, null);
    }

    /// 发送PATCH请求
    pub fn patch(self: *HttpClient, url: []const u8, body: ?[]const u8) !HttpResponse {
        return self.request(.PATCH, url, body, null);
    }

    /// 通用请求方法
    pub fn request(
        self: *HttpClient,
        method: Method,
        url: []const u8,
        body: ?[]const u8,
        headers: ?*std.StringHashMap([]const u8),
    ) !HttpResponse {
        const parsed_url = try parseUrl(url);

        const address = try net.Address.resolveIp(parsed_url.host, parsed_url.port);
        const stream = try net.tcpConnectToAddress(address);
        defer stream.close();

        var request_builder = std.ArrayList(u8).init(self.allocator);
        defer request_builder.deinit();

        try request_builder.writer().print("{s} {s} HTTP/1.1\r\n", .{ method.toString(), parsed_url.path });
        try request_builder.writer().print("Host: {s}\r\n", .{parsed_url.host});
        try request_builder.writer().print("User-Agent: {s}\r\n", .{self.user_agent});
        try request_builder.writer().print("Connection: close\r\n", .{});

        var default_iter = self.default_headers.iterator();
        while (default_iter.next()) |entry| {
            try request_builder.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        if (headers) |h| {
            var header_iter = h.iterator();
            while (header_iter.next()) |entry| {
                try request_builder.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }

        if (body) |b| {
            try request_builder.writer().print("Content-Length: {d}\r\n", .{b.len});
        }

        try request_builder.appendSlice("\r\n");

        if (body) |b| {
            try request_builder.appendSlice(b);
        }

        _ = try stream.write(request_builder.items);

        var response_buffer: [16384]u8 = undefined;
        const bytes_read = try stream.read(&response_buffer);

        return HttpResponse.parse(self.allocator, response_buffer[0..bytes_read]);
    }

    /// 设置默认请求头
    pub fn setHeader(self: *HttpClient, name: []const u8, value: []const u8) !void {
        try self.default_headers.put(name, value);
    }

    pub const Method = enum {
        GET,
        POST,
        PUT,
        DELETE,
        PATCH,
        HEAD,
        OPTIONS,

        pub fn toString(self: Method) []const u8 {
            return switch (self) {
                .GET => "GET",
                .POST => "POST",
                .PUT => "PUT",
                .DELETE => "DELETE",
                .PATCH => "PATCH",
                .HEAD => "HEAD",
                .OPTIONS => "OPTIONS",
            };
        }
    };
};

/// HTTP响应
pub const HttpResponse = struct {
    allocator: std.mem.Allocator,
    status_code: u16,
    status_text: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    raw_response: []u8,

    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !HttpResponse {
        var response = HttpResponse{
            .allocator = allocator,
            .status_code = 200,
            .status_text = "OK",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .raw_response = try allocator.dupe(u8, data),
        };

        var lines = std.mem.splitSequence(u8, data, "\r\n");

        if (lines.next()) |status_line| {
            var parts = std.mem.splitScalar(u8, status_line, ' ');
            _ = parts.next(); // HTTP/1.1

            if (parts.next()) |code_str| {
                response.status_code = std.fmt.parseInt(u16, code_str, 10) catch 200;
            }

            if (parts.next()) |status| {
                response.status_text = status;
            }
        }

        var in_headers = true;
        var body_start: usize = 0;
        var offset: usize = 0;

        while (lines.next()) |line| {
            offset += line.len + 2;

            if (line.len == 0) {
                in_headers = false;
                body_start = offset;
                continue;
            }

            if (in_headers) {
                if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                    const key = line[0..colon_pos];
                    const value = line[colon_pos + 2 ..];
                    try response.headers.put(key, value);
                }
            }
        }

        if (body_start < data.len) {
            response.body = response.raw_response[body_start..];
        }

        return response;
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
        self.allocator.free(self.raw_response);
    }

    /// 获取响应头
    pub fn getHeader(self: *const HttpResponse, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// 检查是否成功（2xx状态码）
    pub fn isSuccess(self: *const HttpResponse) bool {
        return self.status_code >= 200 and self.status_code < 300;
    }

    /// 检查是否重定向（3xx状态码）
    pub fn isRedirect(self: *const HttpResponse) bool {
        return self.status_code >= 300 and self.status_code < 400;
    }

    /// 检查是否客户端错误（4xx状态码）
    pub fn isClientError(self: *const HttpResponse) bool {
        return self.status_code >= 400 and self.status_code < 500;
    }

    /// 检查是否服务器错误（5xx状态码）
    pub fn isServerError(self: *const HttpResponse) bool {
        return self.status_code >= 500;
    }

    /// 转换为PHP Value
    pub fn toValue(self: *HttpResponse, memory_manager: anytype) !Value {
        _ = memory_manager;
        _ = self;
        return Value.initNull();
    }
};

/// URL解析结果
const ParsedUrl = struct {
    scheme: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
    query: ?[]const u8,
};

/// 解析URL
fn parseUrl(url: []const u8) !ParsedUrl {
    var result = ParsedUrl{
        .scheme = "http",
        .host = "",
        .port = 80,
        .path = "/",
        .query = null,
    };

    var remaining = url;

    if (std.mem.indexOf(u8, remaining, "://")) |scheme_end| {
        result.scheme = remaining[0..scheme_end];
        remaining = remaining[scheme_end + 3 ..];

        if (std.mem.eql(u8, result.scheme, "https")) {
            result.port = 443;
        }
    }

    if (std.mem.indexOf(u8, remaining, "/")) |path_start| {
        result.host = remaining[0..path_start];
        result.path = remaining[path_start..];
    } else {
        result.host = remaining;
    }

    if (std.mem.indexOf(u8, result.host, ":")) |port_start| {
        const port_str = result.host[port_start + 1 ..];
        result.port = std.fmt.parseInt(u16, port_str, 10) catch result.port;
        result.host = result.host[0..port_start];
    }

    if (std.mem.indexOf(u8, result.path, "?")) |query_start| {
        result.query = result.path[query_start + 1 ..];
        result.path = result.path[0..query_start];
    }

    return result;
}

test "url parsing" {
    const url1 = try parseUrl("http://example.com/path");
    try std.testing.expectEqualStrings("http", url1.scheme);
    try std.testing.expectEqualStrings("example.com", url1.host);
    try std.testing.expectEqual(@as(u16, 80), url1.port);
    try std.testing.expectEqualStrings("/path", url1.path);

    const url2 = try parseUrl("https://api.example.com:8080/v1/users?page=1");
    try std.testing.expectEqualStrings("https", url2.scheme);
    try std.testing.expectEqualStrings("api.example.com", url2.host);
    try std.testing.expectEqual(@as(u16, 8080), url2.port);
    try std.testing.expectEqualStrings("/v1/users", url2.path);
}
