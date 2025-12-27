const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const gc = types.gc;
const net = std.net;

/// PHP cURL库实现
/// 提供HTTP客户端功能
pub const CurlHandle = struct {
    allocator: std.mem.Allocator,
    options: Options,
    response: ?Response,
    error_code: CurlError,
    error_message: []const u8,

    pub const Options = struct {
        url: []const u8 = "",
        method: Method = .GET,
        headers: std.StringHashMap([]const u8),
        post_fields: []const u8 = "",
        timeout: u64 = 30000, // ms
        connect_timeout: u64 = 10000, // ms
        follow_location: bool = true,
        max_redirects: u32 = 10,
        return_transfer: bool = false,
        header: bool = false,
        ssl_verify_peer: bool = true,
        ssl_verify_host: bool = true,
        user_agent: []const u8 = "Zig-PHP/1.0",
        referer: []const u8 = "",
        cookie: []const u8 = "",
        cookie_file: []const u8 = "",
        cookie_jar: []const u8 = "",
        http_auth: ?HttpAuth = null,
        proxy: ?Proxy = null,
        verbose: bool = false,

        pub fn init(allocator: std.mem.Allocator) Options {
            return Options{
                .headers = std.StringHashMap([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *Options) void {
            self.headers.deinit();
        }
    };

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

    pub const HttpAuth = struct {
        username: []const u8,
        password: []const u8,
        auth_type: AuthType = .basic,

        pub const AuthType = enum {
            basic,
            digest,
            bearer,
        };
    };

    pub const Proxy = struct {
        host: []const u8,
        port: u16,
        username: ?[]const u8 = null,
        password: ?[]const u8 = null,
        proxy_type: ProxyType = .http,

        pub const ProxyType = enum {
            http,
            https,
            socks4,
            socks5,
        };
    };

    pub const Response = struct {
        status_code: u16,
        headers: std.StringHashMap([]const u8),
        body: []const u8,
        content_type: []const u8,
        content_length: usize,
        total_time: f64,
        redirect_count: u32,
        effective_url: []const u8,

        pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
            allocator.free(self.body);
            self.headers.deinit();
        }
    };

    pub const CurlError = enum(u32) {
        ok = 0,
        unsupported_protocol = 1,
        failed_init = 2,
        url_malformat = 3,
        couldnt_resolve_proxy = 5,
        couldnt_resolve_host = 6,
        couldnt_connect = 7,
        operation_timedout = 28,
        ssl_connect_error = 35,
        too_many_redirects = 47,
        got_nothing = 52,
        send_error = 55,
        recv_error = 56,
        ssl_certproblem = 58,
        ssl_cipher = 59,
        ssl_cacert = 60,
        bad_content_encoding = 61,
        login_denied = 67,
        unknown = 255,
    };

    pub fn init(allocator: std.mem.Allocator) CurlHandle {
        return CurlHandle{
            .allocator = allocator,
            .options = Options.init(allocator),
            .response = null,
            .error_code = .ok,
            .error_message = "",
        };
    }

    pub fn deinit(self: *CurlHandle) void {
        self.options.deinit();
        if (self.response) |*resp| {
            resp.deinit(self.allocator);
        }
    }

    /// 设置选项
    pub fn setopt(self: *CurlHandle, option: CurlOption, value: anytype) !void {
        switch (option) {
            .url => self.options.url = value,
            .post => {
                if (value) {
                    self.options.method = .POST;
                }
            },
            .postfields => self.options.post_fields = value,
            .customrequest => {
                if (std.mem.eql(u8, value, "GET")) self.options.method = .GET else if (std.mem.eql(u8, value, "POST")) self.options.method = .POST else if (std.mem.eql(u8, value, "PUT")) self.options.method = .PUT else if (std.mem.eql(u8, value, "DELETE")) self.options.method = .DELETE else if (std.mem.eql(u8, value, "PATCH")) self.options.method = .PATCH else if (std.mem.eql(u8, value, "HEAD")) self.options.method = .HEAD else if (std.mem.eql(u8, value, "OPTIONS")) self.options.method = .OPTIONS;
            },
            .httpheader => {
                // 期望值为字符串数组
                const headers: []const []const u8 = value;
                for (headers) |header| {
                    if (std.mem.indexOf(u8, header, ": ")) |colon_pos| {
                        const key = header[0..colon_pos];
                        const val = header[colon_pos + 2 ..];
                        try self.options.headers.put(key, val);
                    }
                }
            },
            .timeout => self.options.timeout = value,
            .connecttimeout => self.options.connect_timeout = value,
            .followlocation => self.options.follow_location = value,
            .maxredirs => self.options.max_redirects = value,
            .returntransfer => self.options.return_transfer = value,
            .header => self.options.header = value,
            .ssl_verifypeer => self.options.ssl_verify_peer = value,
            .ssl_verifyhost => self.options.ssl_verify_host = value,
            .useragent => self.options.user_agent = value,
            .referer => self.options.referer = value,
            .cookie => self.options.cookie = value,
            .cookiefile => self.options.cookie_file = value,
            .cookiejar => self.options.cookie_jar = value,
            .verbose => self.options.verbose = value,
            else => {},
        }
    }

    /// 执行请求
    pub fn exec(self: *CurlHandle) !?[]const u8 {
        // 解析URL
        const parsed_url = try parseUrl(self.options.url);

        // 建立连接
        const address = try net.Address.resolveIp(parsed_url.host, parsed_url.port);
        var stream = try net.tcpConnectToAddress(address);
        defer stream.close();

        // 构建HTTP请求
        const request = try self.buildHttpRequest(parsed_url);
        defer self.allocator.free(request);

        // 发送请求
        _ = try stream.write(request);

        // 读取响应
        var response_buffer = std.ArrayList(u8).init(self.allocator);
        defer response_buffer.deinit();

        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = stream.read(&buffer) catch |err| switch (err) {
                error.ConnectionResetByPeer => break,
                else => return err,
            };
            if (bytes_read == 0) break;
            try response_buffer.appendSlice(buffer[0..bytes_read]);
        }

        // 解析响应
        self.response = try self.parseResponse(response_buffer.items);

        if (self.options.return_transfer) {
            if (self.response) |resp| {
                return resp.body;
            }
        }

        return null;
    }

    fn buildHttpRequest(self: *CurlHandle, url: ParsedUrl) ![]const u8 {
        var request = std.ArrayList(u8).init(self.allocator);

        // 请求行
        try request.writer().print("{s} {s} HTTP/1.1\r\n", .{ self.options.method.toString(), url.path });

        // Host头
        try request.writer().print("Host: {s}\r\n", .{url.host});

        // User-Agent
        try request.writer().print("User-Agent: {s}\r\n", .{self.options.user_agent});

        // 自定义头部
        var header_iter = self.options.headers.iterator();
        while (header_iter.next()) |entry| {
            try request.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // Cookie
        if (self.options.cookie.len > 0) {
            try request.writer().print("Cookie: {s}\r\n", .{self.options.cookie});
        }

        // Referer
        if (self.options.referer.len > 0) {
            try request.writer().print("Referer: {s}\r\n", .{self.options.referer});
        }

        // POST数据
        if (self.options.method == .POST and self.options.post_fields.len > 0) {
            try request.writer().print("Content-Type: application/x-www-form-urlencoded\r\n", .{});
            try request.writer().print("Content-Length: {d}\r\n", .{self.options.post_fields.len});
        }

        // Connection
        try request.appendSlice("Connection: close\r\n");

        // 空行
        try request.appendSlice("\r\n");

        // POST body
        if (self.options.method == .POST and self.options.post_fields.len > 0) {
            try request.appendSlice(self.options.post_fields);
        }

        return request.toOwnedSlice();
    }

    fn parseResponse(self: *CurlHandle, data: []const u8) !Response {
        var response = Response{
            .status_code = 200,
            .headers = std.StringHashMap([]const u8).init(self.allocator),
            .body = "",
            .content_type = "",
            .content_length = 0,
            .total_time = 0,
            .redirect_count = 0,
            .effective_url = self.options.url,
        };

        // 查找头部和body的分隔
        if (std.mem.indexOf(u8, data, "\r\n\r\n")) |header_end| {
            const header_section = data[0..header_end];
            response.body = try self.allocator.dupe(u8, data[header_end + 4 ..]);
            response.content_length = response.body.len;

            // 解析状态行
            var lines = std.mem.splitSequence(u8, header_section, "\r\n");
            if (lines.next()) |status_line| {
                // HTTP/1.1 200 OK
                var parts = std.mem.splitScalar(u8, status_line, ' ');
                _ = parts.next(); // HTTP版本
                if (parts.next()) |code_str| {
                    response.status_code = std.fmt.parseInt(u16, code_str, 10) catch 200;
                }
            }

            // 解析头部
            while (lines.next()) |line| {
                if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                    const key = line[0..colon_pos];
                    const value = line[colon_pos + 2 ..];
                    try response.headers.put(key, value);

                    if (std.ascii.eqlIgnoreCase(key, "content-type")) {
                        response.content_type = value;
                    }
                }
            }
        } else {
            response.body = try self.allocator.dupe(u8, data);
            response.content_length = data.len;
        }

        return response;
    }

    /// 获取信息
    pub fn getinfo(self: *CurlHandle, info: CurlInfo) ?Value {
        if (self.response == null) return null;

        const resp = self.response.?;
        return switch (info) {
            .response_code => Value.initInt(resp.status_code),
            .content_type => Value.initString(self.allocator, resp.content_type) catch null,
            .content_length => Value.initInt(@intCast(resp.content_length)),
            .total_time => Value.initFloat(resp.total_time),
            .redirect_count => Value.initInt(resp.redirect_count),
            .effective_url => Value.initString(self.allocator, resp.effective_url) catch null,
            else => null,
        };
    }

    /// 获取错误
    pub fn getError(self: *CurlHandle) []const u8 {
        return self.error_message;
    }

    /// 获取错误码
    pub fn getErrno(self: *CurlHandle) CurlError {
        return self.error_code;
    }

    /// 重置选项
    pub fn reset(self: *CurlHandle) void {
        self.options.deinit();
        self.options = Options.init(self.allocator);
        if (self.response) |*resp| {
            resp.deinit(self.allocator);
        }
        self.response = null;
        self.error_code = .ok;
        self.error_message = "";
    }
};

/// cURL选项
pub const CurlOption = enum {
    url,
    port,
    post,
    postfields,
    customrequest,
    httpheader,
    timeout,
    connecttimeout,
    followlocation,
    maxredirs,
    returntransfer,
    header,
    ssl_verifypeer,
    ssl_verifyhost,
    useragent,
    referer,
    cookie,
    cookiefile,
    cookiejar,
    verbose,
    userpwd,
    httpauth,
    proxy,
    proxyport,
    proxytype,
    encoding,
    nobody,
    upload,
    infile,
    infilesize,
    readfunction,
    writefunction,
    headerfunction,
    progressfunction,
    noprogress,
};

/// cURL信息
pub const CurlInfo = enum {
    response_code,
    content_type,
    content_length,
    total_time,
    namelookup_time,
    connect_time,
    pretransfer_time,
    starttransfer_time,
    redirect_time,
    redirect_count,
    effective_url,
    primary_ip,
    primary_port,
    local_ip,
    local_port,
    http_version,
    header_size,
    request_size,
    ssl_verifyresult,
};

/// URL解析
const ParsedUrl = struct {
    scheme: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
    query: []const u8,
    fragment: []const u8,
};

fn parseUrl(url: []const u8) !ParsedUrl {
    var result = ParsedUrl{
        .scheme = "http",
        .host = "",
        .port = 80,
        .path = "/",
        .query = "",
        .fragment = "",
    };

    var remaining = url;

    // 解析scheme
    if (std.mem.indexOf(u8, remaining, "://")) |scheme_end| {
        result.scheme = remaining[0..scheme_end];
        remaining = remaining[scheme_end + 3 ..];

        if (std.mem.eql(u8, result.scheme, "https")) {
            result.port = 443;
        }
    }

    // 解析host和port
    var host_end = remaining.len;
    if (std.mem.indexOf(u8, remaining, "/")) |path_start| {
        host_end = path_start;
    }

    const host_port = remaining[0..host_end];
    if (std.mem.indexOf(u8, host_port, ":")) |colon_pos| {
        result.host = host_port[0..colon_pos];
        result.port = std.fmt.parseInt(u16, host_port[colon_pos + 1 ..], 10) catch result.port;
    } else {
        result.host = host_port;
    }

    remaining = remaining[host_end..];

    // 解析path
    if (remaining.len > 0) {
        if (std.mem.indexOf(u8, remaining, "?")) |query_start| {
            result.path = remaining[0..query_start];
            remaining = remaining[query_start + 1 ..];

            // 解析query和fragment
            if (std.mem.indexOf(u8, remaining, "#")) |frag_start| {
                result.query = remaining[0..frag_start];
                result.fragment = remaining[frag_start + 1 ..];
            } else {
                result.query = remaining;
            }
        } else if (std.mem.indexOf(u8, remaining, "#")) |frag_start| {
            result.path = remaining[0..frag_start];
            result.fragment = remaining[frag_start + 1 ..];
        } else {
            result.path = remaining;
        }
    }

    if (result.path.len == 0) {
        result.path = "/";
    }

    return result;
}

/// cURL多句柄（并发请求）
pub const CurlMulti = struct {
    allocator: std.mem.Allocator,
    handles: std.ArrayList(*CurlHandle),

    pub fn init(allocator: std.mem.Allocator) CurlMulti {
        return CurlMulti{
            .allocator = allocator,
            .handles = std.ArrayList(*CurlHandle).init(allocator),
        };
    }

    pub fn deinit(self: *CurlMulti) void {
        self.handles.deinit();
    }

    pub fn addHandle(self: *CurlMulti, handle: *CurlHandle) !void {
        try self.handles.append(handle);
    }

    pub fn removeHandle(self: *CurlMulti, handle: *CurlHandle) void {
        for (self.handles.items, 0..) |h, i| {
            if (h == handle) {
                _ = self.handles.orderedRemove(i);
                break;
            }
        }
    }

    /// 执行所有请求
    pub fn exec(self: *CurlMulti) !u32 {
        var running: u32 = 0;

        for (self.handles.items) |handle| {
            _ = handle.exec() catch {
                continue;
            };
            running += 1;
        }

        return running;
    }
};

/// PHP cURL函数注册
pub fn registerCurlFunctions(vm: anytype) !void {
    _ = vm;
    // 这些函数将在VM中注册为内置函数
    // curl_init, curl_setopt, curl_exec, curl_close等
}

/// curl_init
pub fn curlInit(allocator: std.mem.Allocator, url: ?[]const u8) !*CurlHandle {
    var handle = try allocator.create(CurlHandle);
    handle.* = CurlHandle.init(allocator);

    if (url) |u| {
        handle.options.url = u;
    }

    return handle;
}

/// curl_close
pub fn curlClose(handle: *CurlHandle) void {
    handle.deinit();
    handle.allocator.destroy(handle);
}

/// curl_setopt_array
pub fn curlSetoptArray(handle: *CurlHandle, options: *PHPArray) !void {
    var iter = options.elements.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        // 根据key设置选项
        switch (key) {
            .integer => |opt_id| {
                const option: CurlOption = @enumFromInt(@as(u8, @intCast(opt_id)));
                switch (value.tag) {
                    .string => try handle.setopt(option, value.data.string.data.data),
                    .boolean => try handle.setopt(option, value.data.boolean),
                    .integer => try handle.setopt(option, @as(u64, @intCast(value.data.integer))),
                    else => {},
                }
            },
            else => {},
        }
    }
}

test "url parsing" {
    const url = "https://example.com:8080/path/to/resource?foo=bar#section";
    const parsed = try parseUrl(url);

    try std.testing.expectEqualStrings("https", parsed.scheme);
    try std.testing.expectEqualStrings("example.com", parsed.host);
    try std.testing.expectEqual(@as(u16, 8080), parsed.port);
    try std.testing.expectEqualStrings("/path/to/resource", parsed.path);
    try std.testing.expectEqualStrings("foo=bar", parsed.query);
    try std.testing.expectEqualStrings("section", parsed.fragment);
}

test "curl handle basic" {
    const allocator = std.testing.allocator;

    var handle = CurlHandle.init(allocator);
    defer handle.deinit();

    try handle.setopt(.url, "http://example.com");
    try handle.setopt(.returntransfer, true);

    try std.testing.expectEqualStrings("http://example.com", handle.options.url);
    try std.testing.expect(handle.options.return_transfer);
}
