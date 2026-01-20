const std = @import("std");
pub const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const token = @import("token.zig");
const runtime = @import("runtime");
const fast_string = runtime.fast_string;

pub const Error = struct {
    msg: []const u8,
    line: u32,
    column: u32,
};

pub const PHPContext = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    nodes: std.ArrayListUnmanaged(ast.Node),
    tokens: std.ArrayListUnmanaged(token.Token), // Store tokens for line number calculation
    string_pool: std.StringArrayHashMapUnmanaged(void),
    errors: std.ArrayListUnmanaged(Error),

    // High-performance string interning pool
    fast_pool: ?*fast_string.StringPool = null,
    use_fast_pool: bool = false,

    // Name Resolution
    current_namespace: ?u32 = null,
    imports: std.AutoArrayHashMapUnmanaged(u32, u32),

    pub fn init(allocator: std.mem.Allocator) PHPContext {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .nodes = .{},
            .tokens = .{},
            .string_pool = .{},
            .errors = .{},
            .imports = .{},
            .fast_pool = null,
            .use_fast_pool = false,
        };
    }

    /// Initialize with high-performance string pool enabled
    pub fn initWithFastPool(allocator: std.mem.Allocator) !PHPContext {
        const pool = try allocator.create(fast_string.StringPool);
        pool.* = try fast_string.StringPool.init(allocator);
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .nodes = .{},
            .tokens = .{},
            .string_pool = .{},
            .errors = .{},
            .imports = .{},
            .fast_pool = pool,
            .use_fast_pool = true,
        };
    }

    pub fn deinit(self: *PHPContext) void {
        if (self.fast_pool) |pool| {
            pool.deinit();
            self.allocator.destroy(pool);
        }
        self.arena.deinit();
        self.nodes.deinit(self.allocator);
        self.tokens.deinit(self.allocator);
        self.string_pool.deinit(self.allocator);
        self.errors.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *PHPContext) void {
        _ = self.arena.reset(.retain_capacity);
        self.nodes.clearRetainingCapacity();
        self.tokens.clearRetainingCapacity();
        self.string_pool.clearRetainingCapacity();
        self.errors.clearRetainingCapacity();
        self.imports.clearRetainingCapacity();
        self.current_namespace = null;
    }

    /// Intern a string - uses fast pool if enabled, otherwise standard pool
    pub fn intern(self: *PHPContext, name: []const u8) !u32 {
        // Use fast pool for string interning if enabled
        if (self.use_fast_pool and self.fast_pool != null) {
            const interned = try self.fast_pool.?.intern(name);
            // Still need to add to string_pool for index lookup
            const result = try self.string_pool.getOrPut(self.allocator, interned);
            return @intCast(result.index);
        }

        // Standard interning
        const result = try self.string_pool.getOrPut(self.allocator, name);
        if (!result.found_existing) {
            result.key_ptr.* = try self.arena.allocator().dupe(u8, name);
        }
        return @intCast(result.index);
    }

    /// Intern a string literal with fast pool optimization
    /// This is specifically for string literals which benefit most from interning
    pub fn internLiteral(self: *PHPContext, literal: []const u8) !u32 {
        if (self.use_fast_pool and self.fast_pool != null) {
            // Fast path: use high-performance pool
            const interned = try self.fast_pool.?.intern(literal);
            const result = try self.string_pool.getOrPut(self.allocator, interned);
            return @intCast(result.index);
        }
        return self.intern(literal);
    }

    /// Get string pool statistics (if fast pool is enabled)
    pub fn getPoolStats(self: *const PHPContext) ?struct { hits: usize, misses: usize, hit_rate: f64 } {
        if (self.fast_pool) |pool| {
            return .{
                .hits = pool.hits,
                .misses = pool.misses,
                .hit_rate = pool.hitRate(),
            };
        }
        return null;
    }

    pub fn parseSource(self: *PHPContext, source: [:0]const u8) anyerror!ast.Node.Index {
        // Pre-allocate nodes capacity based on source length heuristic
        // Conservative estimate: 1 node per 20 bytes of source code
        const estimated_nodes = source.len / 20;
        try self.nodes.ensureUnusedCapacity(self.allocator, estimated_nodes);

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
