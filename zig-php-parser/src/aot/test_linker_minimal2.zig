const linker_minimal = @import("linker_minimal.zig");
test "check linker_minimal" {
    _ = linker_minimal.LinkerError;
}
