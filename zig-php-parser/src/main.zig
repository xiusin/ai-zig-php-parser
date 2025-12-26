const std = @import("std");
const gc = @import("runtime/gc.zig");
const Value = @import("runtime/value.zig").Value;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mm = gc.MemoryManager.init(allocator);
    defer mm.deinit();

    const str_val = Value{
        .tag = .string,
        .data = .{ .string = try mm.allocString("hello") },
    };
    const arr = try mm.allocArray();
    try arr.data.put(.{ .tag = .integer, .data = .{ .integer = 0 } }, str_val);

    std.debug.print("Initial array ref_count = {d}, string ref_count = {d}\n", .{arr.*.ref_count, str_val.data.string.*.ref_count});

    const arr_val = Value{ .tag = .array, .data = .{ .array = arr } };

    gc.incRef(@TypeOf(arr_val.data.array))(arr_val.data.array);
    std.debug.print("Array ref_count incremented to {d}\n", .{arr.*.ref_count});

    gc.decRef(&mm, arr_val);
    std.debug.print("Array ref_count decremented to {d}\n", .{arr.*.ref_count});

    // This should free both the array and the string
    gc.decRef(&mm, arr_val);
}
