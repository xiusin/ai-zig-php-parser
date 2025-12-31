const linker = @import("linker.zig");
test "check linker" {
    _ = linker.StaticLinker;
}
