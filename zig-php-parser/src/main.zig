const std = @import("std");
const ast = @import("compiler/ast.zig");
const parser = @import("compiler/parser.zig");
const vm = @import("runtime/vm.zig");
const types = @import("runtime/types.zig");
const Value = types.Value;
const Environment = @import("runtime/environment.zig");
const PHPContext = @import("compiler/parser.zig").PHPContext;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var context = PHPContext.init(arena_allocator);
    // defer context.deinit();

    const php_code = "<?php echo 42;";
    var p = try parser.Parser.init(arena_allocator, &context, php_code);
    const program = p.parse() catch |err| {
        std.debug.print("Error parsing code: {s}\n", .{@errorName(err)});
        return;
    };

    var vm_instance = try vm.VM.init(allocator);
    vm_instance.context = &context;
    defer vm_instance.deinit();

    _ = try vm_instance.run(program);
}
