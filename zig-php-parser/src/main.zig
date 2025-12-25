const std = @import("std");
const PHPContext = @import("root.zig").PHPContext;
const ReflectionManager = @import("reflection.zig").ReflectionManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = PHPContext.init(allocator);
    defer ctx.deinit();

    const flat_source = "<?php namespace App\\Core; use Library\\Logger; class Service { public $status { get => $this->_status; } public function execute(...$params) { go task(...$params); } }";

    _ = try ctx.parseSource(flat_source);
    std.debug.print("PHP 8.5 Advanced Features Parser: Success.\n", .{});
    std.debug.print("Nodes: {d}, Namespace: {s}\n", .{
        ctx.nodes.items.len,
        if (ctx.current_namespace) |id| ctx.string_pool.keys()[id] else "None"
    });
}
