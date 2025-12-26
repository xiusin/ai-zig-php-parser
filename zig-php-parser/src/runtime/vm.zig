const std = @import("std");
const ast = @import("../compiler/ast.zig");
const Environment = @import("environment.zig").Environment;
const types = @import("types.zig");
const Value = types.Value;
const PHPContext = @import("../compiler/parser.zig").PHPContext;

pub const VM = struct {
    allocator: std.mem.Allocator,
    global: *Environment,
    context: *PHPContext,

    pub fn init(allocator: std.mem.Allocator) !*VM {
        const vm = try allocator.create(VM);
        vm.* = .{
            .allocator = allocator,
            .global = try allocator.create(Environment),
            .context = undefined,
        };
        vm.global.* = Environment.init(allocator);
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.global.deinit();
        self.allocator.destroy(self.global);
        self.allocator.destroy(self);
    }

    pub fn defineBuiltin(self: *VM, name: []const u8, function: types.Value.BuiltinFn) void {
        const value = Value{
            .tag = .builtin_function,
            .data = .{ .builtin_function = function },
        };
        try self.global.set(name, value);
    }

    pub fn run(self: *VM, node: ast.Node.Index) !Value {
        return self.eval(node);
    }

    fn eval(self: *VM, node: ast.Node.Index) !Value {
        const ast_node = self.context.nodes.items[node];

        switch (ast_node.tag) {
            .root => {
                var last_val = Value.initNull();
                for (ast_node.data.root.stmts) |stmt| {
                    last_val = try self.eval(stmt);
                }
                return last_val;
            },
            .function_call => {
                const name_node = self.context.nodes.items[ast_node.data.function_call.name];

                if (name_node.tag != .variable) {
                    return error.InvalidFunctionName;
                }
                const name_id = name_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];

                const function_val = self.global.get(name) orelse return error.UndefinedFunction;

                if (function_val.tag != .builtin_function) {
                    return error.NotAFunction;
                }
                const function = function_val.data.builtin_function;

                var args = std.ArrayList(Value).init(self.allocator);
                defer args.deinit();

                for (ast_node.data.function_call.args) |arg_node_idx| {
                    try args.append(try self.eval(arg_node_idx));
                }

                return function(self, args.items);
            },
            .assignment => {
                const target_node = self.context.nodes.items[ast_node.data.assignment.target];
                if (target_node.tag != .variable) {
                    return error.InvalidAssignmentTarget;
                }
                const name_id = target_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];
                const value = try self.eval(ast_node.data.assignment.value);
                try self.global.set(name, value);
                return value;
            },
            .variable => {
                const name_id = ast_node.data.variable.name;
                const name = self.context.string_pool.keys()[name_id];
                return self.global.get(name) orelse error.UndefinedVariable;
            },
            .literal_string => {
                const str_id = ast_node.data.literal_string.value;
                const str_val = self.context.string_pool.keys()[str_id];
                return Value.initString(self.allocator, str_val);
            },
            .echo_stmt => {
                const value = try self.eval(ast_node.data.echo_stmt.expr);
                try value.print();
                std.debug.print("\n", .{});
                return Value.initNull();
            },
            else => {
                std.debug.print("Unsupported node type: {s}\n", .{@tagName(ast_node.tag)});
                return error.UnsupportedNodeType;
            },
        }
    }
};
