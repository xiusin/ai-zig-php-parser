const std = @import("std");
const testing = std.testing;
const main = @import("main");
const Parser = main.compiler.parser.Parser;
const PHPContext = main.compiler.parser.PHPContext;
const Compiler = main.compiler.compiler.Compiler;
const VM = main.runtime.vm.VM;

test "end-to-end execution: return 1 + 2" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const source = "<?php return 1 + 2;";

    // 1. Parsing
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    // 2. Compiling
    var compiler = Compiler.init(allocator, &context);
    defer compiler.deinit();
    const chunk = try compiler.compile(root_node_index);
    defer chunk.deinit();

    // 3. Execution
    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(chunk);

    // 4. Verification
    try testing.expectEqual(result.tag, .integer);
    try testing.expectEqual(@as(i64, 3), result.data.integer);
}
