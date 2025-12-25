const std = @import("std");
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");

pub const Error = struct {
    msg: []const u8,
    line: u32,
    column: u32,
};

pub const PHPContext = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    nodes: std.ArrayListUnmanaged(ast.Node),
    string_pool: std.StringArrayHashMapUnmanaged(void),
    errors: std.ArrayListUnmanaged(Error),
    
    // Name Resolution
    current_namespace: ?u32 = null,
    imports: std.AutoArrayHashMapUnmanaged(u32, u32),

    pub fn init(allocator: std.mem.Allocator) PHPContext {
        return .{ 
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .nodes = .{}, 
            .string_pool = .{}, 
            .errors = .{}, 
            .imports = .{}, 
        };
    }

    pub fn deinit(self: *PHPContext) void {
        self.arena.deinit();
        self.nodes.deinit(self.allocator);
        self.string_pool.deinit(self.allocator);
        self.errors.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *PHPContext) void {
        _ = self.arena.reset(.retain_capacity);
        self.nodes.clearRetainingCapacity();
        self.string_pool.clearRetainingCapacity();
        self.errors.clearRetainingCapacity();
        self.imports.clearRetainingCapacity();
        self.current_namespace = null;
    }

    pub fn intern(self: *PHPContext, name: []const u8) !u32 {
        const result = try self.string_pool.getOrPut(self.allocator, name);
        if (!result.found_existing) {
            result.key_ptr.* = try self.arena.allocator().dupe(u8, name);
        }
        return @intCast(result.index);
    }

    pub fn parseSource(self: *PHPContext, source: [:0]const u8) anyerror!ast.Node.Index {
        var parser = try Parser.init(self.allocator, self, source);
        defer parser.deinit();
        return try parser.parse();
    }
    
    pub fn resolveName(self: *PHPContext, name_id: u32) !u32 {
        // Simple name resolution logic
        // 1. Check imports
        if (self.imports.get(name_id)) |resolved| return resolved;
        
        // 2. Append current namespace if exists
        if (self.current_namespace) |ns_id| {
            const ns_str = self.string_pool.keys()[ns_id];
            const name_str = self.string_pool.keys()[name_id];
            var fqcn = std.ArrayListUnmanaged(u8){};
            defer fqcn.deinit(self.allocator);
            try fqcn.appendSlice(self.allocator, ns_str);
            try fqcn.append(self.allocator, '\\');
            try fqcn.appendSlice(self.allocator, name_str);
            return try self.intern(fqcn.items);
        }
        
        return name_id;
    }
};

// C API 增强：防止 Null 指针崩溃和双重释放
export fn php_parser_destroy(ctx_opt: ?*PHPContext) void {
    if (ctx_opt) |ctx| {
        ctx.deinit();
        std.heap.c_allocator.destroy(ctx);
    }
}

export fn php_parser_parse(ctx: *PHPContext, source: [*:0]const u8) i32 {
    ctx.reset();
    const src = std.mem.span(source);
    const source_z = std.heap.c_allocator.dupeZ(u8, src) catch return -1;
    defer std.heap.c_allocator.free(source_z);

    const root_idx = ctx.parseSource(source_z) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return -1;
    };
    return @intCast(root_idx);
}