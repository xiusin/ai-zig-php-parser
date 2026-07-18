const std = @import("std");
const testing = std.testing;
const runtime = @import("runtime_lib_template.zig");
const Value = runtime.Value;
const PHPArray = runtime.PHPArray;

fn withRuntime(allocator: std.mem.Allocator, comptime f: fn (std.mem.Allocator) anyerror!void) !void {
    try runtime.initRuntime(allocator);
    defer runtime.deinitRuntime();
    try f(allocator);
}

test "AOT runtime - array_unshift/array_shift/array_pop" {
    try withRuntime(testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            const arr = try PHPArray.init(allocator);
            defer arr.release(allocator);

            try arr.push(allocator, Value.initInt(1));
            try arr.push(allocator, Value.initInt(2));
            try arr.push(allocator, Value.initInt(3));

            const arr_val = Value.initArray(arr);
            const unshifted = try runtime.php_array_unshift(arr_val, &[_]Value{Value.initInt(0)}, allocator);
            try testing.expectEqual(@as(i64, 4), unshifted.asInt());

            const first = try runtime.php_array_shift(arr_val, allocator);
            try testing.expectEqual(@as(i64, 0), first.asInt());

            const last = try runtime.php_array_pop(arr_val, allocator);
            try testing.expectEqual(@as(i64, 3), last.asInt());

            const cnt = try runtime.php_count(arr_val, Value.initInt(0));
            try testing.expectEqual(@as(i64, 2), cnt.asInt());
        }
    }.run);
}

test "AOT runtime - array_splice modifies array and returns removed" {
    try withRuntime(testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            const arr = try PHPArray.init(allocator);
            defer arr.release(allocator);

            try arr.push(allocator, Value.initInt(1));
            try arr.push(allocator, Value.initInt(2));
            try arr.push(allocator, Value.initInt(3));
            try arr.push(allocator, Value.initInt(4));

            const arr_val = Value.initArray(arr);
            const removed = try runtime.php_array_splice(arr_val, Value.initInt(1), Value.initInt(2), Value.initNull(), allocator);
            defer removed.release(allocator);

            try testing.expect(removed.isArray());
            try testing.expectEqual(@as(usize, 2), removed.asArray().count());

            const v0 = try runtime.php_array_shift(removed, allocator);
            const v1 = try runtime.php_array_shift(removed, allocator);
            try testing.expectEqual(@as(i64, 2), v0.asInt());
            try testing.expectEqual(@as(i64, 3), v1.asInt());

            const cnt = try runtime.php_count(arr_val, Value.initInt(0));
            try testing.expectEqual(@as(i64, 2), cnt.asInt());

            const a0 = try runtime.php_array_shift(arr_val, allocator);
            const a1 = try runtime.php_array_shift(arr_val, allocator);
            try testing.expectEqual(@as(i64, 1), a0.asInt());
            try testing.expectEqual(@as(i64, 4), a1.asInt());
        }
    }.run);
}

test "AOT runtime - sort and ksort" {
    try withRuntime(testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            const arr = try PHPArray.init(allocator);
            defer arr.release(allocator);
            try arr.push(allocator, Value.initInt(3));
            try arr.push(allocator, Value.initInt(1));
            try arr.push(allocator, Value.initInt(2));
            const arr_val = Value.initArray(arr);

            const sorted = try runtime.php_sort(arr_val, allocator);
            // php_sort 返回排序后的数组（原地排序，返回数组引用）
            try testing.expect(sorted.isArray());
            const v0 = try runtime.php_array_shift(arr_val, allocator);
            const v1 = try runtime.php_array_shift(arr_val, allocator);
            const v2 = try runtime.php_array_shift(arr_val, allocator);
            try testing.expectEqual(@as(i64, 1), v0.asInt());
            try testing.expectEqual(@as(i64, 2), v1.asInt());
            try testing.expectEqual(@as(i64, 3), v2.asInt());

            const assoc = try PHPArray.init(allocator);
            defer assoc.release(allocator);
            try assoc.set(allocator, .{ .integer = 2 }, Value.initInt(20));
            try assoc.set(allocator, .{ .integer = 1 }, Value.initInt(10));
            const assoc_val = Value.initArray(assoc);

            const sorted2 = try runtime.php_ksort(assoc_val, allocator);
            // php_ksort 返回排序后的数组（原地排序，返回数组引用）
            try testing.expect(sorted2.isArray());

            var it = assoc.elements.iterator();
            const e0 = it.next().?;
            const e1 = it.next().?;
            try testing.expect(e0.key_ptr.* == .integer and e0.key_ptr.*.integer == 1);
            try testing.expect(e1.key_ptr.* == .integer and e1.key_ptr.*.integer == 2);
        }
    }.run);
}

test "AOT runtime - current/next/reset/key/each" {
    try withRuntime(testing.allocator, struct {
        fn run(allocator: std.mem.Allocator) !void {
            const arr = try PHPArray.init(allocator);
            defer arr.release(allocator);
            try arr.push(allocator, Value.initInt(10));
            try arr.push(allocator, Value.initInt(20));
            const arr_val = Value.initArray(arr);

            const r = try runtime.php_reset(arr_val, allocator);
            try testing.expectEqual(@as(i64, 10), r.asInt());
            const k0 = try runtime.php_key(arr_val, allocator);
            try testing.expectEqual(@as(i64, 0), k0.asInt());

            const n = try runtime.php_next(arr_val, allocator);
            try testing.expectEqual(@as(i64, 20), n.asInt());
            const k1 = try runtime.php_key(arr_val, allocator);
            try testing.expectEqual(@as(i64, 1), k1.asInt());

            const each = try runtime.php_each(arr_val, allocator);
            defer each.release(allocator);
            try testing.expect(each.isArray());
            try testing.expectEqual(@as(usize, 4), each.asArray().count());
        }
    }.run);
}
