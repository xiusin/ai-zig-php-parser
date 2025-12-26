const std = @import("std");
const ast = @import("compiler/ast.zig");
const parser = @import("compiler/parser.zig");
const vm = @import("runtime/vm.zig");
const types = @import("runtime/types.zig");
const Value = types.Value;
const Environment = @import("runtime/environment.zig");
const PHPContext = @import("compiler/parser.zig").PHPContext;

fn printFn(vm_ptr: *anyopaque, args: []const Value) !Value {
    const vm_instance = @ptrCast(*vm.VM, @alignCast(@constCast(vm_ptr)));
    for (args) |arg| {
        try arg.print();
        std.debug.print(" ", .{});
    }
    std.debug.print("\n", .{});
    return Value.initNull();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var context = PHPContext.init(arena_allocator);
    // defer context.deinit();

    const php_code = "$message = \"Hello from a variable!\"; echo $message;";
    var p = try parser.Parser.init(arena_allocator, &context, php_code);
    const program = p.parse() catch |err| {
        std.debug.print("Error parsing code: {s}\n", .{@errorName(err)});
        return;
    };

    var vm_instance = try vm.VM.init(allocator);
    vm_instance.context = &context;
    defer vm_instance.deinit();

    vm_instance.defineBuiltin("print", printFn);

    _ = try vm_instance.run(program);
}
