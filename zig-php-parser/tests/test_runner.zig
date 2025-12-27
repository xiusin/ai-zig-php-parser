const std = @import("std");

pub const tests = .{
    @import("unit/compiler/lexer_test.zig"),
    @import("unit/compiler/parser_test.zig"),
    @import("unit/compiler/test_enhanced_parser.zig"),
    @import("unit/runtime/test_gc.zig"),
    @import("unit/runtime/test_error_handling.zig"),
    @import("unit/runtime/test_object_integration.zig"),
    @import("unit/runtime/test_object_system.zig"),
    @import("unit/runtime/test_reflection.zig"),
    @import("unit/test_enhanced_types.zig"),
    @import("unit/test_enhanced_functions.zig"),
    @import("unit/test_attribute_system.zig"),
};

pub fn main() !void {
    const testing_module = @import("std").testing;
    const test_fn = testing_module.refAllDecls;
    inline for (std.meta.fields(@This().tests)) |field| {
        test_fn(field.value);
    }
}
