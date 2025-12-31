const std = @import("std");
const CodeGen = @import("codegen.zig");
const Target = CodeGen.Target;
const OptimizeLevel = CodeGen.OptimizeLevel;
const Diagnostics = @import("diagnostics.zig");
const IR = @import("ir.zig");

pub const TestStruct = struct {
    value: i32,
};

test "check imports" {
    _ = Target;
    _ = OptimizeLevel;
    _ = Diagnostics.DiagnosticEngine;
    _ = IR.Module;
}
