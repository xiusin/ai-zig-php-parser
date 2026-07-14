const std = @import("std");
const testing = std.testing;
const runtime = @import("runtime_lib_template.zig");
const Value = runtime.Value;
const PHPArray = runtime.PHPArray;

fn withRuntime(allocator: std.mem.Allocator, comptime f: fn (std.mem.Allocator) anyerror!void) !void {
    runtime.initRuntime(allocator);
    defer runtime.deinitRuntime();
    try f(allocator);
}

test "AOT runtime - cycle GC collects cyclic arrays" {
    try withRuntime(testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            const a = try PHPArray.init(allocator);
            const b = try PHPArray.init(allocator);

            try a.set(allocator, .{ .integer = 0 }, Value.initArray(b));
            try b.set(allocator, .{ .integer = 0 }, Value.initArray(a));

            a.release(allocator);
            b.release(allocator);

            runtime.php_collect_cycles();
        }
    }.run);
}

test "AOT runtime - cycle GC collects cyclic objects" {
    try withRuntime(testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            const o1 = try runtime.PHPObject.init(allocator, "C1");
            const o2 = try runtime.PHPObject.init(allocator, "C2");

            try o1.setProperty("peer", runtime.Value_initObject(o2));
            try o2.setProperty("peer", runtime.Value_initObject(o1));

            o1.release();
            o2.release();

            runtime.php_collect_cycles();
        }
    }.run);
}
