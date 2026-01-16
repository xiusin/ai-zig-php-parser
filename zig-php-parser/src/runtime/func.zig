const fast_value = @import("fast_value.zig");
const FastValue = fast_value.FastValue;

pub const CompiledFunc = struct {
    name: []const u8,
    code: []const u8,
    constants: []FastValue,
    locals_count: u16,
    params_count: u16,
    max_stack: u16,
    
    // JIT Cache
    jit_code: ?*const anyopaque = null,
    osr_entry_offset: usize = 0,
};
