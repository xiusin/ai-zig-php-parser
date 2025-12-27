const std = @import("std");

pub const tests = .{
    // Compiler tests - compatible with the new architecture
    @import("unit/compiler/lexer_test.zig"),
    @import("unit/compiler/parser_test.zig"),
    @import("unit/compiler/compiler_test.zig"),

    // Integration test for the new VM
    @import("integration/bytecode_vm_test.zig"),

    // TODO: The following tests are disabled as they depend on the old tree-walking VM.
    // They need to be re-enabled and adapted as their features are re-implemented
    // on top of the new bytecode VM.
    // @import("unit/compiler/test_enhanced_parser.zig"),
    // @import("unit/runtime/test_gc.zig"),
    // @import("unit/runtime/test_error_handling.zig"),
    // @import("unit/runtime/test_object_integration.zig"),
    // @import("unit/runtime/test_object_system.zig"),
    // @import("unit/runtime/test_reflection.zig"),
    // @import("unit/test_enhanced_types.zig"),
    // @import("unit/test_enhanced_functions.zig"),
    // @import("unit/test_attribute_system.zig"),
};

pub fn main() !void {
    const testing_module = @import("std").testing;
    const test_fn = testing_module.refAllDecls;
    inline for (std.meta.fields(@This().tests)) |field| {
        test_fn(field.value);
    }
}
