const std = @import("std");

pub const compiler = @import("compiler/compiler.zig");
pub const bytecode = @import("compiler/bytecode.zig");
pub const parser = @import("compiler/parser.zig");

const vm = @import("runtime/vm.zig");
const types = @import("runtime/types.zig");
const Value = types.Value;
const PHPContext = @import("compiler/parser.zig").PHPContext;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var context = PHPContext.init(arena_allocator);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    var php_code: [:0]const u8 = "<?php 1 + 2;";
    if (args.len > 1) {
        const filename = args[1];
        const file_contents = std.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024) catch |err| {
            std.debug.print("Error opening file '{s}': {s}\n", .{ filename, @errorName(err) });
            return;
        };
        defer allocator.free(file_contents);
        php_code = file_contents;
    }

    // 1. Parsing
    var p = try parser.Parser.init(arena_allocator, &context, php_code);
    const root_node_index = p.parse() catch |err| {
        std.debug.print("Error parsing code: {s}\n", .{@errorName(err)});
        return;
    };

    // 2. Compiling
    var comp = compiler.Compiler.init(allocator, &context);
    defer comp.deinit();
    const chunk = try comp.compile(root_node_index);
    defer chunk.deinit();

    // 3. Execution
    var vm_instance = vm.VM.init(allocator);
    defer vm_instance.deinit();
    
    const result = try vm_instance.interpret(chunk);
    try result.print();
    std.debug.print("\n", .{});
}
