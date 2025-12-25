const std = @import("std");
const ast = @import("ast.zig");
const PHPContext = @import("root.zig").PHPContext;

pub const ReflectionManager = struct {
    allocator: std.mem.Allocator,
    classes: std.AutoHashMapUnmanaged(ast.Node.StringId, ClassInfo),

    pub const ClassInfo = struct {
        node_idx: ast.Node.Index,
        attributes: []const ast.Node.Index,
        methods: std.AutoHashMapUnmanaged(ast.Node.StringId, ast.Node.Index),
        properties: std.AutoHashMapUnmanaged(ast.Node.StringId, ast.Node.Index),
        traits: []const ast.Node.Index = &.{},
    };

    pub fn init(allocator: std.mem.Allocator) ReflectionManager {
        return .{
            .allocator = allocator,
            .classes = .{},
        };
    }

    pub fn deinit(self: *ReflectionManager) void {
        var it = self.classes.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.methods.deinit(self.allocator);
            entry.value_ptr.properties.deinit(self.allocator);
        }
        self.classes.deinit(self.allocator);
    }

    pub fn buildIndex(self: *ReflectionManager, ctx: *PHPContext) !void {
        for (ctx.nodes.items, 0..) |node, i| {
            if (node.tag == .class_decl or node.tag == .trait_decl or node.tag == .interface_decl) {
                const data = node.data.container_decl;
                var class_info = ClassInfo{
                    .node_idx = @intCast(i),
                    .attributes = data.attributes,
                    .methods = .{},
                    .properties = .{},
                };

                for (data.members) |m_idx| {
                    const member_node = ctx.nodes.items[m_idx];
                    if (member_node.tag == .method_decl) {
                        try class_info.methods.put(self.allocator, member_node.data.method_decl.name, m_idx);
                    } else if (member_node.tag == .property_decl) {
                        try class_info.properties.put(self.allocator, member_node.data.property_decl.name, m_idx);
                    }
                }
                try self.classes.put(self.allocator, data.name, class_info);
            }
        }
    }
    
    pub fn linkTraits(self: *ReflectionManager, ctx: *PHPContext) !void {
        // Post-processing to mix in traits
        // This is a simplified version
        var it = self.classes.iterator();
        while (it.next()) |entry| {
            _ = entry;
            _ = ctx;
            // logic to find 'use Trait' in members and copy methods
        }
    }
};

// C API Exports for Reflection
export fn php_reflection_create(allocator_ptr: ?*anyopaque) ?*ReflectionManager {
    _ = allocator_ptr;
    const allocator = std.heap.c_allocator;
    const rm = allocator.create(ReflectionManager) catch return null;
    rm.* = ReflectionManager.init(allocator);
    return rm;
}

export fn php_reflection_build(rm: *ReflectionManager, ctx: *PHPContext) i32 {
    rm.buildIndex(ctx) catch return -1;
    return 0;
}

export fn php_reflection_get_class_attr_count(rm: *ReflectionManager, name_id: u32) i32 {
    if (rm.classes.get(name_id)) |info| {
        return @intCast(info.attributes.len);
    }
    return -1;
}