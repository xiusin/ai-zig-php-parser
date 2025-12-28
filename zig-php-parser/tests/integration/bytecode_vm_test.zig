const std = @import("std");
const testing = std.testing;
const main = @import("main");
const Parser = main.compiler.parser.Parser;
const PHPContext = main.compiler.parser.PHPContext;
const Compiler = main.compiler.compiler.Compiler;
const VM = main.runtime.vm.VM;
const Value = main.runtime.types.Value;

fn testE2E(source: []const u8, expected_value: Value) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // 1. Parsing
    var context = PHPContext.init(arena_allocator);
    var parser = try Parser.init(arena_allocator, &context, source);
    const root_node_index = try parser.parse();

    // 2. Compiling
    var compiler = Compiler.init(allocator, &context, null);
    const main_func = try compiler.compile(root_node_index);
    defer main_func.deinit(allocator);

    // 3. Execution
    var vm = VM.init(allocator);
    defer vm.deinit();
    const result = try vm.interpret(main_func.chunk);

    // 4. Verification
    try testing.expectEqual(expected_value.tag, result.tag);
    switch (expected_value.tag) {
        .integer => try testing.expectEqual(expected_value.data.integer, result.data.integer),
        .boolean => try testing.expectEqual(expected_value.data.boolean, result.data.boolean),
        .null => {},
        else => return error.UnsupportedVerificationType,
    }
}

test "end-to-end execution: return 1 + 2" {
    try testE2E("<?php return 1 + 2;", Value.initInt(3));
}

test "end-to-end execution: if-else statement (true)" {
    try testE2E("<?php if (2 > 1) { return 10; } else { return 20; }", Value.initInt(10));
}

test "end-to-end execution: if-else statement (false)" {
    try testE2E("<?php if (1 > 2) { return 10; } else { return 20; }", Value.initInt(20));
}

test "end-to-end execution: if statement without else" {
    try testE2E("<?php if (1 > 2) { return 10; } return 5;", Value.initInt(5));
}

test "end-to-end execution: while loop" {
    const source = "<?php $a = 0; while ($a < 5) { $a = $a + 1; } return $a;";
    try testE2E(source, Value.initInt(5));
}

test "end-to-end execution: function declaration and call" {
    const source = "<?php function my_func() { return 10; } return my_func();";
    try testE2E(source, Value.initInt(10));
}

test "end-to-end execution: function with parameters" {
    const source = "<?php function add($a, $b) { return $a + $b; } return add(3, 4);";
    try testE2E(source, Value.initInt(7));
}

test "end-to-end execution: recursive function (fibonacci)" {
    const source = "<?php function fib($n) { if ($n < 2) { return $n; } return fib($n - 1) + fib($n - 2); } return fib(10);";
    try testE2E(source, Value.initInt(55));
}
