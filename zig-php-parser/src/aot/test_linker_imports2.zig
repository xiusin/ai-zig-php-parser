const linker_imports = @import("test_linker_imports.zig");
test "check linker_imports" {
    _ = linker_imports.TestStruct;
}
