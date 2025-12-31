const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const PHPObject = types.PHPObject;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;

// Forward declaration for VM
const VM = @import("vm.zig").VM;

/// PHP 8.5 URI Extension
pub const Uri = struct {
    scheme: ?*PHPString,
    host: ?*PHPString,
    port: ?u16,
    path: ?*PHPString,
    query: ?*PHPString,
    fragment: ?*PHPString,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Uri {
        return Uri{
            .scheme = null,
            .host = null,
            .port = null,
            .path = null,
            .query = null,
            .fragment = null,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Uri) void {
        if (self.scheme) |s| s.deinit(self.allocator);
        if (self.host) |h| h.deinit(self.allocator);
        if (self.path) |p| p.deinit(self.allocator);
        if (self.query) |q| q.deinit(self.allocator);
        if (self.fragment) |f| f.deinit(self.allocator);
    }
    
    pub fn parse(uri_string: *PHPString, allocator: std.mem.Allocator) !Uri {
        var uri = Uri.init(allocator);
        const uri_str = uri_string.data;
        
        // Simple URI parsing - would need full RFC 3986 implementation
        var remaining = uri_str;
        
        // Parse scheme
        if (std.mem.indexOf(u8, remaining, "://")) |scheme_end| {
            uri.scheme = try PHPString.init(allocator, remaining[0..scheme_end]);
            remaining = remaining[scheme_end + 3..];
        }
        
        // Parse authority (host:port)
        var authority_end = remaining.len;
        if (std.mem.indexOf(u8, remaining, "/")) |path_start| {
            authority_end = path_start;
        } else if (std.mem.indexOf(u8, remaining, "?")) |query_start| {
            authority_end = query_start;
        } else if (std.mem.indexOf(u8, remaining, "#")) |fragment_start| {
            authority_end = fragment_start;
        }
        
        if (authority_end > 0) {
            const authority = remaining[0..authority_end];
            if (std.mem.indexOf(u8, authority, ":")) |port_start| {
                uri.host = try PHPString.init(allocator, authority[0..port_start]);
                const port_str = authority[port_start + 1..];
                uri.port = std.fmt.parseInt(u16, port_str, 10) catch null;
            } else {
                uri.host = try PHPString.init(allocator, authority);
            }
            remaining = remaining[authority_end..];
        }
        
        // Parse path
        if (remaining.len > 0 and remaining[0] == '/') {
            var path_end = remaining.len;
            if (std.mem.indexOf(u8, remaining, "?")) |query_start| {
                path_end = query_start;
            } else if (std.mem.indexOf(u8, remaining, "#")) |fragment_start| {
                path_end = fragment_start;
            }
            
            uri.path = try PHPString.init(allocator, remaining[0..path_end]);
            remaining = remaining[path_end..];
        }
        
        // Parse query
        if (remaining.len > 0 and remaining[0] == '?') {
            remaining = remaining[1..];
            var query_end = remaining.len;
            if (std.mem.indexOf(u8, remaining, "#")) |fragment_start| {
                query_end = fragment_start;
            }
            
            uri.query = try PHPString.init(allocator, remaining[0..query_end]);
            remaining = remaining[query_end..];
        }
        
        // Parse fragment
        if (remaining.len > 0 and remaining[0] == '#') {
            uri.fragment = try PHPString.init(allocator, remaining[1..]);
        }
        
        return uri;
    }
    
    pub fn toString(self: *const Uri, allocator: std.mem.Allocator) !*PHPString {
        var result = std.ArrayListUnmanaged(u8){};
        defer result.deinit(allocator);
        
        if (self.scheme) |scheme| {
            try result.appendSlice(allocator, scheme.data);
            try result.appendSlice(allocator, "://");
        }
        
        if (self.host) |host| {
            try result.appendSlice(allocator, host.data);
            if (self.port) |port| {
                const port_str = try std.fmt.allocPrint(allocator, ":{d}", .{port});
                defer allocator.free(port_str);
                try result.appendSlice(allocator, port_str);
            }
        }
        
        if (self.path) |path| {
            try result.appendSlice(allocator, path.data);
        }
        
        if (self.query) |query| {
            try result.append(allocator, '?');
            try result.appendSlice(allocator, query.data);
        }
        
        if (self.fragment) |fragment| {
            try result.append(allocator, '#');
            try result.appendSlice(allocator, fragment.data);
        }
        
        return try PHPString.init(allocator, result.items);
    }
    
    pub fn getHost(self: *Uri) ?*PHPString {
        return self.host;
    }
    
    pub fn getPath(self: *Uri) ?*PHPString {
        return self.path;
    }
    
    pub fn resolve(self: *const Uri, relative: *PHPString, allocator: std.mem.Allocator) !Uri {
        // Simplified relative URI resolution
        var resolved = Uri.init(allocator);
        
        // Copy base URI components
        if (self.scheme) |scheme| {
            resolved.scheme = try PHPString.init(allocator, scheme.data);
        }
        if (self.host) |host| {
            resolved.host = try PHPString.init(allocator, host.data);
        }
        resolved.port = self.port;
        
        // Resolve relative path
        const rel_str = relative.data;
        if (rel_str.len > 0 and rel_str[0] == '/') {
            // Absolute path
            resolved.path = try PHPString.init(allocator, rel_str);
        } else {
            // Relative path - combine with base path
            if (self.path) |base_path| {
                const base_dir = std.fs.path.dirname(base_path.data) orelse "/";
                const combined = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, rel_str });
                defer allocator.free(combined);
                resolved.path = try PHPString.init(allocator, combined);
            } else {
                resolved.path = try PHPString.init(allocator, rel_str);
            }
        }
        
        return resolved;
    }
};

/// PHP 8.5 Pipe Operator Implementation
pub const PipeOperator = struct {
    pub fn evaluate(vm: *VM, left: Value, right: Value) !Value {
        // left |> right equivalent to right(left)
        switch (right.getTag()) {
            .builtin_function => {
                const func = right.data.builtin_function;
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(func));
                return function(vm, &[_]Value{left});
            },
            .user_function => {
                return vm.callUserFunction(right.data.user_function.data, &[_]Value{left});
            },
            .closure => {
                return vm.callClosure(right.data.closure.data, &[_]Value{left});
            },
            .arrow_function => {
                return vm.callArrowFunction(right.data.arrow_function.data, &[_]Value{left});
            },
            else => {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "Pipe operator requires callable on right side", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidPipeTarget;
            },
        }
    }
};

/// PHP 8.5 Clone With Implementation
pub const CloneWith = struct {
    pub fn cloneWithProperties(vm: *VM, object: *PHPObject, properties: *PHPArray) !*PHPObject {
        // Create a new object with the same class
        const new_object = try vm.allocator.create(PHPObject);
        new_object.* = PHPObject{
            .class = object.class,
            .properties = try object.properties.clone(),
        };
        
        // Update specified properties
        var iterator = properties.elements.iterator();
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            
            switch (key) {
                .string => |prop_name| {
                    try new_object.setProperty(prop_name.data, value);
                },
                else => {
                    const exception = try ExceptionFactory.createTypeError(vm.allocator, "Clone with requires string property names", "builtin", 0);
                    _ = try vm.throwException(exception);
                    return error.InvalidPropertyKey;
                },
            }
        }
        
        return new_object;
    }
};

/// PHP 8.5 NoDiscard Attribute
pub const NoDiscardAttribute = struct {
    pub const name = "NoDiscard";
    
    pub fn validate(vm: *VM, function_name: []const u8, return_value: Value) !void {
        // Check if return value is being discarded
        // This would be integrated into the VM's function call handling
        _ = vm;
        _ = function_name;
        _ = return_value;
        
        // In a real implementation, this would track whether the return value
        // is assigned to a variable or used in an expression
        // For now, this is a placeholder
    }
};

/// URI-related builtin functions
pub fn registerUriFunctions(stdlib: *@import("stdlib.zig").StandardLibrary) !void {
    const uri_functions = [_]*const @import("stdlib.zig").BuiltinFunction{
        &.{ .name = "uri_parse", .min_args = 1, .max_args = 1, .handler = uriParseFn },
        &.{ .name = "uri_build", .min_args = 1, .max_args = 1, .handler = uriBuildFn },
        &.{ .name = "uri_resolve", .min_args = 2, .max_args = 2, .handler = uriResolveFn },
    };
    
    for (uri_functions) |func| {
        try stdlib.registerFunction(func.name, func);
    }
}

fn uriParseFn(vm: *VM, args: []const Value) !Value {
    const uri_string = args[0];
    
    if (uri_string.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "uri_parse() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const uri = try Uri.parse(uri_string.getAsString().data, vm.allocator);
    
    // Create PHP array with URI components
    var result_array = try vm.allocator.create(PHPArray);
    result_array.* = PHPArray.init(vm.allocator);
    
    if (uri.scheme) |scheme| {
        const scheme_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "scheme") };
        const scheme_box = try vm.allocator.create(types.gc.Box(*PHPString));
        scheme_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = scheme,
        };
        
        const scheme_val = Value.fromBox(scheme_box, Value.TYPE_STRING);
        try result_array.set(vm.allocator, scheme_key, scheme_val);
        vm.releaseValue(scheme_val);
    }
    
    if (uri.host) |host| {
        const host_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "host") };
        const host_box = try vm.allocator.create(types.gc.Box(*PHPString));
        host_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = host,
        };
        
        const host_val = Value.fromBox(host_box, Value.TYPE_STRING);
        try result_array.set(vm.allocator, host_key, host_val);
        vm.releaseValue(host_val);
    }
    
    if (uri.port) |port| {
        const port_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "port") };
        try result_array.set(vm.allocator, port_key, Value.initInt(@intCast(port)));
    }
    
    if (uri.path) |path| {
        const path_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "path") };
        const path_box = try vm.allocator.create(types.gc.Box(*PHPString));
        path_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = path,
        };
        
        const path_val = Value.fromBox(path_box, Value.TYPE_STRING);
        try result_array.set(vm.allocator, path_key, path_val);
        vm.releaseValue(path_val);
    }
    
    if (uri.query) |query| {
        const query_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "query") };
        const query_box = try vm.allocator.create(types.gc.Box(*PHPString));
        query_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = query,
        };
        
        const query_val = Value.fromBox(query_box, Value.TYPE_STRING);
        try result_array.set(vm.allocator, query_key, query_val);
        vm.releaseValue(query_val);
    }
    
    if (uri.fragment) |fragment| {
        const fragment_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "fragment") };
        const fragment_box = try vm.allocator.create(types.gc.Box(*PHPString));
        fragment_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = fragment,
        };
        
        const fragment_val = Value.fromBox(fragment_box, Value.TYPE_STRING);
        try result_array.set(vm.allocator, fragment_key, fragment_val);
        vm.releaseValue(fragment_val);
    }
    
    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };
    
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

fn uriBuildFn(vm: *VM, args: []const Value) !Value {
    const components = args[0];
    
    if (components.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "uri_build() expects parameter 1 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    var uri = Uri.init(vm.allocator);
    
    // Extract components from array
    const scheme_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "scheme") };
    if (components.getAsArray().data.get(scheme_key)) |scheme_val| {
        if (scheme_val.getTag() == .string) {
            uri.scheme = try PHPString.init(vm.allocator, scheme_val.getAsString().data.data);
        }
    }
    
    const host_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "host") };
    if (components.getAsArray().data.get(host_key)) |host_val| {
        if (host_val.getTag() == .string) {
            uri.host = try PHPString.init(vm.allocator, host_val.getAsString().data.data);
        }
    }
    
    const port_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "port") };
    if (components.getAsArray().data.get(port_key)) |port_val| {
        if (port_val.getTag() == .integer) {
            uri.port = @intCast(port_val.asInt());
        }
    }
    
    const path_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "path") };
    if (components.getAsArray().data.get(path_key)) |path_val| {
        if (path_val.getTag() == .string) {
            uri.path = try PHPString.init(vm.allocator, path_val.getAsString().data.data);
        }
    }
    
    const query_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "query") };
    if (components.getAsArray().data.get(query_key)) |query_val| {
        if (query_val.getTag() == .string) {
            uri.query = try PHPString.init(vm.allocator, query_val.getAsString().data.data);
        }
    }
    
    const fragment_key = types.ArrayKey{ .string = try PHPString.init(vm.allocator, "fragment") };
    if (components.getAsArray().data.get(fragment_key)) |fragment_val| {
        if (fragment_val.getTag() == .string) {
            uri.fragment = try PHPString.init(vm.allocator, fragment_val.getAsString().data.data);
        }
    }
    
    const result_str = try uri.toString(vm.allocator);
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value.fromBox(box, Value.TYPE_STRING);
}

fn uriResolveFn(vm: *VM, args: []const Value) !Value {
    const base_uri = args[0];
    const relative_uri = args[1];
    
    if (base_uri.getTag() != .string or relative_uri.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "uri_resolve() expects both parameters to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
    
    const base = try Uri.parse(base_uri.getAsString().data, vm.allocator);
    const resolved = try base.resolve(relative_uri.getAsString().data, vm.allocator);
    
    const result_str = try resolved.toString(vm.allocator);
    
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };
    
    return Value.fromBox(box, Value.TYPE_STRING);
}