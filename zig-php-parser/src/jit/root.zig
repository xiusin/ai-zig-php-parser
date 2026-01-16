const std = @import("std");
const builtin = @import("builtin");

pub const CodeCache = @import("code_cache.zig").CodeCache;

pub const Assembler = if (builtin.cpu.arch == .aarch64)
    @import("assembler_arm64.zig").Assembler
else
    // Placeholder for x64, using arm64 for now to avoid build errors if file missing, 
    // but in real world we need assembler_x64.zig
    @import("assembler_arm64.zig").Assembler; 

pub const Register = if (builtin.cpu.arch == .aarch64)
    @import("assembler_arm64.zig").Register
else
    @import("assembler_arm64.zig").Register;

pub const Compiler = @import("compiler.zig").Compiler;

test {
    _ = CodeCache;
    _ = Assembler;
    _ = Compiler;
}
