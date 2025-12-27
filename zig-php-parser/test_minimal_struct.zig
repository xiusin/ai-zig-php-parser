const std = @import("std");
const types = @import("src/runtime/types.zig");

test "minimal struct test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a struct type
    const struct_name = try types.PHPString.init(allocator, "Point");
    var php_struct = types.PHPStruct.init(allocator, struct_name);
    defer php_struct.deinit();
    
    // Create a struct value
    const struct_value = try types.Value.initStruct(allocator, &php_struct);
    
    // Test that it works
    try std.testing.expect(struct_value.tag == .struct_instance);
}