const std = @import("std");
const CodeGen = @import("codegen.zig");
const Target = CodeGen.Target;
comptime {
    @compileLog(Target);
}
