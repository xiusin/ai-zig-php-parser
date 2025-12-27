const std = @import("std");
const parser = @import("compiler/parser.zig");
const PHPContext = parser.PHPContext;
const Scheduler = @import("runtime/scheduler.zig").Scheduler;
const Coroutine = @import("runtime/coroutine.zig").Coroutine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var context = PHPContext.init(arena_allocator);

    const php_code =
        \\<?php
        \\
        \\function task($name) {
        \\    echo "start ", $name, "\n";
        \\    echo "end ", $name, "\n";
        \\}
        \\
        \\go task("A");
        \\go task("B");
        \\
    ;
    var p = try parser.Parser.init(arena_allocator, &context, php_code);
    const root_node_idx = p.parse() catch |err| {
        std.debug.print("Error parsing code: {s}\n", .{@errorName(err)});
        return;
    };

    var scheduler = Scheduler.init(allocator, &context);
    defer scheduler.deinit();

    try scheduler.run(root_node_idx);
}
