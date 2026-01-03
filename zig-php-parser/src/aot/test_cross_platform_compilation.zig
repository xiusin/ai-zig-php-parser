//! Cross-Platform Compilation Tests for PHP AOT Compiler
//!
//! **Feature: aot-native-compilation**
//! **Task: 10. 跨平台支持**
//! **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5**
//!
//! This test suite validates cross-platform compilation functionality:
//! - 10.1: Linux x86_64 target compilation
//! - 10.2: Linux ARM64 target compilation
//! - 10.3: macOS x86_64 and ARM64 targets
//! - 10.4: --list-targets output verification

const std = @import("std");
const testing = std.testing;

// AOT module imports
const Compiler = @import("compiler.zig");
const CompilerTarget = Compiler.Target;
const CompileOptions = Compiler.CompileOptions;
const OptimizeLevel = Compiler.OptimizeLevel;
const supported_targets = Compiler.supported_targets;
const listTargets = Compiler.listTargets;

const Linker = @import("linker.zig");
const ZigLinker = Linker.ZigLinker;
const ZigLinkerConfig = Linker.ZigLinkerConfig;
const ZigOptimizeLevel = Linker.ZigOptimizeLevel;
const ObjectFormat = Linker.ObjectFormat;

const CodeGen = @import("codegen.zig");
const CodeGenTarget = CodeGen.Target;
const CodeGenOptimizeLevel = CodeGen.OptimizeLevel;

const Diagnostics = @import("diagnostics.zig");
const ZigCodeGen = @import("zig_codegen.zig");
const IR = @import("ir.zig");
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const Node = @import("ir_generator.zig").Node;
const SymbolTable = @import("symbol_table.zig");
const TypeInference = @import("type_inference.zig");

// ============================================================================
// Test Infrastructure
// ============================================================================

/// Test context for cross-platform compilation tests
const CrossPlatformTestContext = struct {
    allocator: std.mem.Allocator,
    diagnostics: *Diagnostics.DiagnosticEngine,

    fn init(allocator: std.mem.Allocator) !CrossPlatformTestContext {
        const diagnostics = try allocator.create(Diagnostics.DiagnosticEngine);
        diagnostics.* = Diagnostics.DiagnosticEngine.init(allocator);

        return .{
            .allocator = allocator,
            .diagnostics = diagnostics,
        };
    }

    fn deinit(self: *CrossPlatformTestContext) void {
        self.diagnostics.deinit();
        self.allocator.destroy(self.diagnostics);
    }
};

/// Generate simple test Zig code for compilation testing
fn generateTestZigCode() []const u8 {
    return
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    const stdout = std.io.getStdOut().writer();
        \\    stdout.print("Hello from cross-compiled code!\n", .{}) catch {};
        \\}
        \\
    ;
}

// ============================================================================
// Task 10.1: Linux x86_64 Target Tests
// ============================================================================

test "10.1.1: Linux x86_64 target parsing" {
    // Feature: aot-native-compilation, Task 10.1
    // Validates: Requirements 7.1

    const target = try CompilerTarget.fromString("x86_64-linux-gnu");
    try testing.expectEqual(CompilerTarget.Arch.x86_64, target.arch);
    try testing.expectEqual(CompilerTarget.OS.linux, target.os);
    try testing.expectEqual(CompilerTarget.ABI.gnu, target.abi);
}

test "10.1.2: Linux x86_64 musl target parsing" {
    // Feature: aot-native-compilation, Task 10.1
    // Validates: Requirements 7.1

    const target = try CompilerTarget.fromString("x86_64-linux-musl");
    try testing.expectEqual(CompilerTarget.Arch.x86_64, target.arch);
    try testing.expectEqual(CompilerTarget.OS.linux, target.os);
    try testing.expectEqual(CompilerTarget.ABI.musl, target.abi);
}

test "10.1.3: Linux x86_64 object format is ELF" {
    // Feature: aot-native-compilation, Task 10.1
    // Validates: Requirements 7.1

    const target = CodeGenTarget{ .arch = .x86_64, .os = .linux, .abi = .gnu };
    const format = ObjectFormat.fromTarget(target);
    try testing.expectEqual(ObjectFormat.elf, format);
    try testing.expectEqualStrings(".o", format.objectExtension());
    try testing.expectEqualStrings(".a", format.staticLibExtension());
    try testing.expectEqualStrings("", format.executableExtension());
}

test "10.1.4: Linux x86_64 ZigLinker configuration" {
    // Feature: aot-native-compilation, Task 10.1
    // Validates: Requirements 7.1
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    // Create ZigLinker with Linux x86_64 target
    var config = ZigLinkerConfig.default();
    config.target = "x86_64-linux-gnu";
    config.optimize_level = .release_safe;

    const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
    defer linker.deinit();

    // Verify configuration
    try testing.expectEqualStrings("x86_64-linux-gnu", linker.getConfig().target.?);
    try testing.expectEqual(ZigOptimizeLevel.release_safe, linker.getConfig().optimize_level);

    // Verify executable extension (no extension for Linux)
    try testing.expectEqualStrings("", linker.getExecutableExtension());
}

test "10.1.5: Linux x86_64 Zig command generation" {
    // Feature: aot-native-compilation, Task 10.1
    // Validates: Requirements 7.1
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    var config = ZigLinkerConfig.default();
    config.target = "x86_64-linux-gnu";
    config.optimize_level = .release_fast;
    config.strip_symbols = true;

    const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
    defer linker.deinit();

    var args = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (args.items) |arg| {
            if (std.mem.startsWith(u8, arg, "-femit-bin=")) {
                allocator.free(arg);
            }
        }
        args.deinit(allocator);
    }

    try linker.buildZigCommand(&args, "test.zig", "test_output");

    // Verify command structure
    try testing.expectEqualStrings("zig", args.items[0]);
    try testing.expectEqualStrings("build-exe", args.items[1]);

    // Verify target is set
    var found_target = false;
    var i: usize = 0;
    while (i < args.items.len) : (i += 1) {
        if (std.mem.eql(u8, args.items[i], "-target")) {
            found_target = true;
            try testing.expect(i + 1 < args.items.len);
            try testing.expectEqualStrings("x86_64-linux-gnu", args.items[i + 1]);
        }
    }
    try testing.expect(found_target);

    // Verify optimization flag
    var found_opt = false;
    for (args.items) |arg| {
        if (std.mem.eql(u8, arg, "-OReleaseFast")) {
            found_opt = true;
        }
    }
    try testing.expect(found_opt);
}

// ============================================================================
// Task 10.2: Linux ARM64 Target Tests
// ============================================================================

test "10.2.1: Linux ARM64 target parsing" {
    // Feature: aot-native-compilation, Task 10.2
    // Validates: Requirements 7.2

    const target = try CompilerTarget.fromString("aarch64-linux-gnu");
    try testing.expectEqual(CompilerTarget.Arch.aarch64, target.arch);
    try testing.expectEqual(CompilerTarget.OS.linux, target.os);
    try testing.expectEqual(CompilerTarget.ABI.gnu, target.abi);
}

test "10.2.2: Linux ARM64 musl target parsing" {
    // Feature: aot-native-compilation, Task 10.2
    // Validates: Requirements 7.2

    const target = try CompilerTarget.fromString("aarch64-linux-musl");
    try testing.expectEqual(CompilerTarget.Arch.aarch64, target.arch);
    try testing.expectEqual(CompilerTarget.OS.linux, target.os);
    try testing.expectEqual(CompilerTarget.ABI.musl, target.abi);
}

test "10.2.3: Linux ARM64 object format is ELF" {
    // Feature: aot-native-compilation, Task 10.2
    // Validates: Requirements 7.2

    const target = CodeGenTarget{ .arch = .aarch64, .os = .linux, .abi = .gnu };
    const format = ObjectFormat.fromTarget(target);
    try testing.expectEqual(ObjectFormat.elf, format);
}

test "10.2.4: Linux ARM64 ZigLinker configuration" {
    // Feature: aot-native-compilation, Task 10.2
    // Validates: Requirements 7.2
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    var config = ZigLinkerConfig.default();
    config.target = "aarch64-linux-gnu";
    config.optimize_level = .release_safe;

    const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
    defer linker.deinit();

    try testing.expectEqualStrings("aarch64-linux-gnu", linker.getConfig().target.?);
    try testing.expectEqualStrings("", linker.getExecutableExtension());
}

test "10.2.5: Linux ARM64 Zig command generation" {
    // Feature: aot-native-compilation, Task 10.2
    // Validates: Requirements 7.2
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    var config = ZigLinkerConfig.default();
    config.target = "aarch64-linux-gnu";

    const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
    defer linker.deinit();

    var args = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (args.items) |arg| {
            if (std.mem.startsWith(u8, arg, "-femit-bin=")) {
                allocator.free(arg);
            }
        }
        args.deinit(allocator);
    }

    try linker.buildZigCommand(&args, "test.zig", "test_output");

    // Verify target is set to ARM64
    var found_target = false;
    var i: usize = 0;
    while (i < args.items.len) : (i += 1) {
        if (std.mem.eql(u8, args.items[i], "-target")) {
            found_target = true;
            try testing.expect(i + 1 < args.items.len);
            try testing.expectEqualStrings("aarch64-linux-gnu", args.items[i + 1]);
        }
    }
    try testing.expect(found_target);
}

// ============================================================================
// Task 10.3: macOS Target Tests
// ============================================================================

test "10.3.1: macOS x86_64 target parsing" {
    // Feature: aot-native-compilation, Task 10.3
    // Validates: Requirements 7.3

    const target = try CompilerTarget.fromString("x86_64-macos-none");
    try testing.expectEqual(CompilerTarget.Arch.x86_64, target.arch);
    try testing.expectEqual(CompilerTarget.OS.macos, target.os);
    try testing.expectEqual(CompilerTarget.ABI.none, target.abi);
}

test "10.3.2: macOS ARM64 target parsing" {
    // Feature: aot-native-compilation, Task 10.3
    // Validates: Requirements 7.4

    const target = try CompilerTarget.fromString("aarch64-macos-none");
    try testing.expectEqual(CompilerTarget.Arch.aarch64, target.arch);
    try testing.expectEqual(CompilerTarget.OS.macos, target.os);
    try testing.expectEqual(CompilerTarget.ABI.none, target.abi);
}

test "10.3.3: macOS darwin alias parsing" {
    // Feature: aot-native-compilation, Task 10.3
    // Validates: Requirements 7.3, 7.4

    // Test that "darwin" is accepted as an alias for "macos"
    const target = try CompilerTarget.fromString("x86_64-darwin-none");
    try testing.expectEqual(CompilerTarget.Arch.x86_64, target.arch);
    try testing.expectEqual(CompilerTarget.OS.macos, target.os);
}

test "10.3.4: macOS object format is Mach-O" {
    // Feature: aot-native-compilation, Task 10.3
    // Validates: Requirements 7.3, 7.4

    // Test x86_64
    const x86_target = CodeGenTarget{ .arch = .x86_64, .os = .macos, .abi = .none };
    const x86_format = ObjectFormat.fromTarget(x86_target);
    try testing.expectEqual(ObjectFormat.macho, x86_format);
    try testing.expectEqualStrings(".o", x86_format.objectExtension());
    try testing.expectEqualStrings(".a", x86_format.staticLibExtension());
    try testing.expectEqualStrings("", x86_format.executableExtension());

    // Test ARM64
    const arm_target = CodeGenTarget{ .arch = .aarch64, .os = .macos, .abi = .none };
    const arm_format = ObjectFormat.fromTarget(arm_target);
    try testing.expectEqual(ObjectFormat.macho, arm_format);
}

test "10.3.5: macOS x86_64 ZigLinker configuration" {
    // Feature: aot-native-compilation, Task 10.3
    // Validates: Requirements 7.3
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    var config = ZigLinkerConfig.default();
    config.target = "x86_64-macos";

    const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
    defer linker.deinit();

    try testing.expectEqualStrings("x86_64-macos", linker.getConfig().target.?);
    try testing.expectEqualStrings("", linker.getExecutableExtension());
}

test "10.3.6: macOS ARM64 ZigLinker configuration" {
    // Feature: aot-native-compilation, Task 10.3
    // Validates: Requirements 7.4
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    var config = ZigLinkerConfig.default();
    config.target = "aarch64-macos";

    const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
    defer linker.deinit();

    try testing.expectEqualStrings("aarch64-macos", linker.getConfig().target.?);
    try testing.expectEqualStrings("", linker.getExecutableExtension());
}

test "10.3.7: macOS Zig command generation" {
    // Feature: aot-native-compilation, Task 10.3
    // Validates: Requirements 7.3, 7.4
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    // Test both x86_64 and ARM64
    const targets = [_][]const u8{ "x86_64-macos", "aarch64-macos" };

    for (targets) |target_str| {
        var config = ZigLinkerConfig.default();
        config.target = target_str;

        const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
        defer linker.deinit();

        var args = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (args.items) |arg| {
                if (std.mem.startsWith(u8, arg, "-femit-bin=")) {
                    allocator.free(arg);
                }
            }
            args.deinit(allocator);
        }

        try linker.buildZigCommand(&args, "test.zig", "test_output");

        // Verify target is set
        var found_target = false;
        var i: usize = 0;
        while (i < args.items.len) : (i += 1) {
            if (std.mem.eql(u8, args.items[i], "-target")) {
                found_target = true;
                try testing.expect(i + 1 < args.items.len);
                try testing.expectEqualStrings(target_str, args.items[i + 1]);
            }
        }
        try testing.expect(found_target);
    }
}

// ============================================================================
// Task 10.4: --list-targets Output Tests
// ============================================================================

test "10.4.1: Supported targets list contains Linux x86_64" {
    // Feature: aot-native-compilation, Task 10.4
    // Validates: Requirements 7.5

    var found_x86_64_gnu = false;
    var found_x86_64_musl = false;

    for (supported_targets) |target| {
        if (std.mem.eql(u8, target, "x86_64-linux-gnu")) {
            found_x86_64_gnu = true;
        }
        if (std.mem.eql(u8, target, "x86_64-linux-musl")) {
            found_x86_64_musl = true;
        }
    }

    try testing.expect(found_x86_64_gnu);
    try testing.expect(found_x86_64_musl);
}

test "10.4.2: Supported targets list contains Linux ARM64" {
    // Feature: aot-native-compilation, Task 10.4
    // Validates: Requirements 7.5

    var found_aarch64_gnu = false;
    var found_aarch64_musl = false;

    for (supported_targets) |target| {
        if (std.mem.eql(u8, target, "aarch64-linux-gnu")) {
            found_aarch64_gnu = true;
        }
        if (std.mem.eql(u8, target, "aarch64-linux-musl")) {
            found_aarch64_musl = true;
        }
    }

    try testing.expect(found_aarch64_gnu);
    try testing.expect(found_aarch64_musl);
}

test "10.4.3: Supported targets list contains macOS" {
    // Feature: aot-native-compilation, Task 10.4
    // Validates: Requirements 7.5

    var found_x86_64_macos = false;
    var found_aarch64_macos = false;

    for (supported_targets) |target| {
        if (std.mem.eql(u8, target, "x86_64-macos-none")) {
            found_x86_64_macos = true;
        }
        if (std.mem.eql(u8, target, "aarch64-macos-none")) {
            found_aarch64_macos = true;
        }
    }

    try testing.expect(found_x86_64_macos);
    try testing.expect(found_aarch64_macos);
}

test "10.4.4: Supported targets list contains Windows" {
    // Feature: aot-native-compilation, Task 10.4
    // Validates: Requirements 7.5

    var found_x86_64_windows = false;
    var found_aarch64_windows = false;

    for (supported_targets) |target| {
        if (std.mem.eql(u8, target, "x86_64-windows-msvc")) {
            found_x86_64_windows = true;
        }
        if (std.mem.eql(u8, target, "aarch64-windows-msvc")) {
            found_aarch64_windows = true;
        }
    }

    try testing.expect(found_x86_64_windows);
    try testing.expect(found_aarch64_windows);
}

test "10.4.5: All supported targets are parseable" {
    // Feature: aot-native-compilation, Task 10.4
    // Validates: Requirements 7.5

    for (supported_targets) |target_str| {
        const target = try CompilerTarget.fromString(target_str);
        // Verify we can convert back to string
        const allocator = testing.allocator;
        const triple = try target.toTriple(allocator);
        defer allocator.free(triple);
        try testing.expect(triple.len > 0);
    }
}

test "10.4.6: listTargets function produces output" {
    // Feature: aot-native-compilation, Task 10.4
    // Validates: Requirements 7.5

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(testing.allocator);

    try listTargets(output.writer(testing.allocator));

    // Verify output contains expected content
    try testing.expect(output.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, output.items, "Supported target platforms") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "x86_64-linux-gnu") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "aarch64-macos-none") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "--target=") != null);
}

// ============================================================================
// Additional Cross-Platform Tests
// ============================================================================

test "10.5.1: Target to CodeGen target conversion preserves values" {
    // Feature: aot-native-compilation, Task 10
    // Validates: Requirements 7.1, 7.2, 7.3, 7.4

    // Test Linux x86_64
    const linux_x86 = try CompilerTarget.fromString("x86_64-linux-gnu");
    const cg_linux_x86 = linux_x86.toCodeGenTarget();
    try testing.expectEqual(CodeGenTarget.Arch.x86_64, cg_linux_x86.arch);
    try testing.expectEqual(CodeGenTarget.OS.linux, cg_linux_x86.os);

    // Test Linux ARM64
    const linux_arm = try CompilerTarget.fromString("aarch64-linux-gnu");
    const cg_linux_arm = linux_arm.toCodeGenTarget();
    try testing.expectEqual(CodeGenTarget.Arch.aarch64, cg_linux_arm.arch);
    try testing.expectEqual(CodeGenTarget.OS.linux, cg_linux_arm.os);

    // Test macOS x86_64
    const macos_x86 = try CompilerTarget.fromString("x86_64-macos-none");
    const cg_macos_x86 = macos_x86.toCodeGenTarget();
    try testing.expectEqual(CodeGenTarget.Arch.x86_64, cg_macos_x86.arch);
    try testing.expectEqual(CodeGenTarget.OS.macos, cg_macos_x86.os);

    // Test macOS ARM64
    const macos_arm = try CompilerTarget.fromString("aarch64-macos-none");
    const cg_macos_arm = macos_arm.toCodeGenTarget();
    try testing.expectEqual(CodeGenTarget.Arch.aarch64, cg_macos_arm.arch);
    try testing.expectEqual(CodeGenTarget.OS.macos, cg_macos_arm.os);
}

test "10.5.2: ZigLinkerConfig.fromTarget creates correct configuration" {
    // Feature: aot-native-compilation, Task 10
    // Validates: Requirements 7.1, 7.2, 7.3, 7.4

    // Test Linux x86_64
    const linux_target = CodeGenTarget{ .arch = .x86_64, .os = .linux, .abi = .gnu };
    const linux_config = ZigLinkerConfig.fromTarget(linux_target, .release_fast);
    try testing.expectEqualStrings("x86_64-linux-gnu", linux_config.target.?);
    try testing.expectEqual(ZigOptimizeLevel.release_fast, linux_config.optimize_level);
    try testing.expect(linux_config.static_link);

    // Test macOS ARM64
    const macos_target = CodeGenTarget{ .arch = .aarch64, .os = .macos, .abi = .none };
    const macos_config = ZigLinkerConfig.fromTarget(macos_target, .debug);
    try testing.expectEqualStrings("aarch64-macos", macos_config.target.?);
    try testing.expectEqual(ZigOptimizeLevel.debug, macos_config.optimize_level);
}

test "10.5.3: Windows target configuration" {
    // Feature: aot-native-compilation, Task 10
    // Validates: Requirements 7.5
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    var config = ZigLinkerConfig.default();
    config.target = "x86_64-windows-msvc";

    const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
    defer linker.deinit();

    // Windows should have .exe extension
    try testing.expectEqualStrings(".exe", linker.getExecutableExtension());
}

test "10.5.4: Output path generation for different targets" {
    // Feature: aot-native-compilation, Task 10
    // Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    // Test Linux (no extension)
    {
        var config = ZigLinkerConfig.default();
        config.target = "x86_64-linux-gnu";
        const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
        defer linker.deinit();

        const output = try linker.generateOutputPath("hello.php", null);
        defer allocator.free(output);
        try testing.expectEqualStrings("hello", output);
    }

    // Test macOS (no extension)
    {
        var config = ZigLinkerConfig.default();
        config.target = "aarch64-macos";
        const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
        defer linker.deinit();

        const output = try linker.generateOutputPath("hello.php", null);
        defer allocator.free(output);
        try testing.expectEqualStrings("hello", output);
    }

    // Test Windows (.exe extension)
    {
        var config = ZigLinkerConfig.default();
        config.target = "x86_64-windows-msvc";
        const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
        defer linker.deinit();

        const output = try linker.generateOutputPath("hello.php", null);
        defer allocator.free(output);
        try testing.expectEqualStrings("hello.exe", output);
    }
}

test "10.5.5: Optimization level flags for cross-compilation" {
    // Feature: aot-native-compilation, Task 10
    // Validates: Requirements 7.1, 7.2, 7.3, 7.4
    const allocator = testing.allocator;

    var ctx = try CrossPlatformTestContext.init(allocator);
    defer ctx.deinit();

    const opt_levels = [_]ZigOptimizeLevel{ .debug, .release_safe, .release_fast, .release_small };
    const expected_flags = [_][]const u8{ "-ODebug", "-OReleaseSafe", "-OReleaseFast", "-OReleaseSmall" };

    for (opt_levels, expected_flags) |opt, expected_flag| {
        var config = ZigLinkerConfig.default();
        config.target = "x86_64-linux-gnu";
        config.optimize_level = opt;

        const linker = try ZigLinker.init(allocator, config, ctx.diagnostics);
        defer linker.deinit();

        var args = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (args.items) |arg| {
                if (std.mem.startsWith(u8, arg, "-femit-bin=")) {
                    allocator.free(arg);
                }
            }
            args.deinit(allocator);
        }

        try linker.buildZigCommand(&args, "test.zig", "test_output");

        // Verify optimization flag is present
        var found_opt = false;
        for (args.items) |arg| {
            if (std.mem.eql(u8, arg, expected_flag)) {
                found_opt = true;
            }
        }
        try testing.expect(found_opt);
    }
}
