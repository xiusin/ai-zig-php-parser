const linker = @import("linker.zig");
comptime {
    @compileLog(@typeInfo(@TypeOf(linker)));
}
