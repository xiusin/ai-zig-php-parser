const std = @import("std");

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    expires: ?i64 = null,
    max_age: ?u64 = null,
    path: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    secure: bool = false,
    http_only: bool = false,
    same_site: ?SameSite = null,

    pub const SameSite = enum {
        Strict,
        Lax,
        None,
    };
};
