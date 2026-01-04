//! End-to-End Cross-Platform Property Tests for PHP AOT Compiler
//!
//! **Feature: php-aot-compiler**
//! **Subtask 15.3: Cross-Platform Tests**
//! **Validates: Requirements 4.2, 4.3, 9.1**
//!
//! This test suite validates that the AOT compiler correctly supports
//! cross-platform compilation:
//! 1. Linux target compilation (ELF format)
//! 2. macOS target compilation (Mach-O format)
//! 3. Windows target compilation (COFF format)
//! 4. Target triple parsing and validation
//! 5. Object format selection based on target

const std = @import("std");
const testing = std.testing;

// AOT module imports
const Compiler = @import("compiler.zig");
const CompilerTarget = Compiler.Target;
const supported_targets = Compiler.supported_targets;
const Linker = @import("linker.zig");
const ObjectFormat = Linker.ObjectFormat;
const LinkerConfig = Linker.LinkerConfig;
const StaticLinker = Linker.StaticLinker;
const CodeGen = @import("codegen.zig");
const CodeGenTarget = CodeGen.Target;
const CodeGenOptimizeLevel = CodeGen.OptimizeLevel;
const Diagnostics = @import("diagnostics.zig");

/// Random number generator for property tests
const Rng = std.Random.DefaultPrng;

/// Test configuration
const TEST_ITERATIONS = 100;

// ============================================================================
// Test Infrastructure
// ============================================================================

/// Generate a random architecture for compiler target
fn randomCompilerArch(rng: *Rng) CompilerTarget.Arch {
    const archs = [_]CompilerTarget.Arch{ .x86_64, .aarch64, .arm };
    return archs[rng.random().intRangeAtMost(usize, 0, archs.len - 1)];
}

/// Generate a random OS for compiler target
fn randomCompilerOS(rng: *Rng) CompilerTarget.OS {
    const oses = [_]CompilerTarget.OS{ .linux, .macos, .windows };
    return oses[rng.random().intRangeAtMost(usize, 0, oses.len - 1)];
}

/// Generate a random ABI for compiler target
fn randomCompilerABI(rng: *Rng) CompilerTarget.ABI {
    const abis = [_]CompilerTarget.ABI{ .gnu, .musl, .msvc, .none };
    return abis[rng.random().intRangeAtMost(usize, 0, abis.len - 1)];
}

/// Generate a random architecture for codegen target
fn randomCodeGenArch(rng: *Rng) CodeGenTarget.Arch {
    const archs = [_]CodeGenTarget.Arch{ .x86_64, .aarch64, .arm };
    return archs[rng.random().intRangeAtMost(usize, 0, archs.len - 1)];
}

/// Generate a random OS for codegen target
fn randomCodeGenOS(rng: *Rng) CodeGenTarget.OS {
    const oses = [_]CodeGenTarget.OS{ .linux, .macos, .windows };
    return oses[rng.random().intRangeAtMost(usize, 0, oses.len - 1)];
}

/// Generate a random ABI for codegen target
fn randomCodeGenABI(rng: *Rng) CodeGenTarget.ABI {
    const abis = [_]CodeGenTarget.ABI{ .gnu, .musl, .msvc, .none };
    return abis[rng.random().intRangeAtMost(usize, 0, abis.len - 1)];
}

/// Generate a random optimization level
fn randomOptLevel(rng: *Rng) CodeGenOptimizeLevel {
    const levels = [_]CodeGenOptimizeLevel{ .debug, .release_safe, .release_fast, .release_small };
    return levels[rng.random().intRangeAtMost(usize, 0, levels.len - 1)];
}

// ============================================================================
// Cross-Platform Tests
// ============================================================================

// Test 15.3.1: Target triple parsing
// *For any* valid target triple string, parsing SHALL produce a valid Target.
test "Test 15.3.1: Target triple parsing" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 9.1

    // Test all supported targets
    for (supported_targets) |triple| {
        const target = try CompilerTarget.fromString(triple);
        _ = target.arch.toString();
        _ = target.os.toString();
        _ = target.abi.toString();
    }
}

// Test 15.3.2: Target triple roundtrip
// *For any* Target, converting to triple and back SHALL produce equivalent Target.
test "Test 15.3.2: Target triple roundtrip" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 9.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const original = CompilerTarget{
            .arch = randomCompilerArch(&rng),
            .os = randomCompilerOS(&rng),
            .abi = randomCompilerABI(&rng),
        };

        const triple = try original.toTriple(allocator);
        defer allocator.free(triple);

        const parsed = try CompilerTarget.fromString(triple);

        try testing.expectEqual(original.arch, parsed.arch);
        try testing.expectEqual(original.os, parsed.os);
        try testing.expectEqual(original.abi, parsed.abi);
    }
}

// Test 15.3.3: Linux target object format
// *For any* Linux target, the object format SHALL be ELF.
test "Test 15.3.3: Linux target object format" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 4.2

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const target = CodeGenTarget{
            .arch = randomCodeGenArch(&rng),
            .os = .linux,
            .abi = if (rng.random().boolean()) .gnu else .musl,
        };

        const format = ObjectFormat.fromTarget(target);
        try testing.expectEqual(ObjectFormat.elf, format);
        try testing.expectEqualStrings(".o", format.objectExtension());
        try testing.expectEqualStrings(".a", format.staticLibExtension());
        try testing.expectEqualStrings("", format.executableExtension());
    }
}

// Test 15.3.4: macOS target object format
// *For any* macOS target, the object format SHALL be Mach-O.
test "Test 15.3.4: macOS target object format" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 4.3

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const target = CodeGenTarget{
            .arch = if (rng.random().boolean()) .x86_64 else .aarch64,
            .os = .macos,
            .abi = .none,
        };

        const format = ObjectFormat.fromTarget(target);
        try testing.expectEqual(ObjectFormat.macho, format);
        try testing.expectEqualStrings(".o", format.objectExtension());
        try testing.expectEqualStrings(".a", format.staticLibExtension());
        try testing.expectEqualStrings("", format.executableExtension());
    }
}

// Test 15.3.5: Windows target object format
// *For any* Windows target, the object format SHALL be COFF.
test "Test 15.3.5: Windows target object format" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 4.2

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const target = CodeGenTarget{
            .arch = if (rng.random().boolean()) .x86_64 else .aarch64,
            .os = .windows,
            .abi = .msvc,
        };

        const format = ObjectFormat.fromTarget(target);
        try testing.expectEqual(ObjectFormat.coff, format);
        try testing.expectEqualStrings(".obj", format.objectExtension());
        try testing.expectEqualStrings(".lib", format.staticLibExtension());
        try testing.expectEqualStrings(".exe", format.executableExtension());
    }
}

// Test 15.3.6: Native target detection
// *For any* call to Target.native(), it SHALL return a valid target for the current platform.
test "Test 15.3.6: Native target detection" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 9.1

    const native = CompilerTarget.native();

    // Verify arch is valid
    _ = native.arch.toString();

    // Verify OS is valid
    _ = native.os.toString();

    // Verify ABI is valid
    _ = native.abi.toString();

    // Convert to CodeGen target and verify object format can be determined
    const cg_target = native.toCodeGenTarget();
    const format = ObjectFormat.fromTarget(cg_target);
    _ = format.objectExtension();
    _ = format.staticLibExtension();
    _ = format.executableExtension();
}

// Test 15.3.7: Architecture string conversion
// *For any* architecture, toString SHALL return a non-empty string.
test "Test 15.3.7: Architecture string conversion" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 4.2, 4.3

    const archs = [_]CompilerTarget.Arch{ .x86_64, .aarch64, .arm };
    const expected = [_][]const u8{ "x86_64", "aarch64", "arm" };

    for (archs, expected) |arch, exp| {
        const str = arch.toString();
        try testing.expectEqualStrings(exp, str);
    }
}

// Test 15.3.8: OS string conversion
// *For any* OS, toString SHALL return a non-empty string.
test "Test 15.3.8: OS string conversion" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 4.2, 4.3

    const oses = [_]CompilerTarget.OS{ .linux, .macos, .windows };
    const expected = [_][]const u8{ "linux", "macos", "windows" };

    for (oses, expected) |os, exp| {
        const str = os.toString();
        try testing.expectEqualStrings(exp, str);
    }
}

// Test 15.3.9: ABI string conversion
// *For any* ABI, toString SHALL return a non-empty string.
test "Test 15.3.9: ABI string conversion" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 4.2, 4.3

    const abis = [_]CompilerTarget.ABI{ .gnu, .musl, .msvc, .none };
    const expected = [_][]const u8{ "gnu", "musl", "msvc", "none" };

    for (abis, expected) |abi, exp| {
        const str = abi.toString();
        try testing.expectEqualStrings(exp, str);
    }
}

// Test 15.3.10: Invalid target triple rejection
// *For any* invalid target triple, parsing SHALL return an error.
test "Test 15.3.10: Invalid target triple rejection" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 9.1

    const invalid_triples = [_][]const u8{
        "invalid",
        "x86_64",
        "x86_64-invalid-gnu",
        "invalid-linux-gnu",
        "",
        "---",
    };

    for (invalid_triples) |triple| {
        const result = CompilerTarget.fromString(triple);
        try testing.expectError(error.InvalidTarget, result);
    }
}

// Test 15.3.11: Linker configuration for different targets
// *For any* target, the linker SHALL be configurable with appropriate settings.
test "Test 15.3.11: Linker configuration for different targets" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 4.2, 4.3, 9.1
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const cg_target = CodeGenTarget{
            .arch = randomCodeGenArch(&rng),
            .os = randomCodeGenOS(&rng),
            .abi = randomCodeGenABI(&rng),
        };

        // Use default config and modify as needed
        var config = LinkerConfig.default(cg_target);
        config.optimize_level = randomOptLevel(&rng);
        config.static_link = rng.random().boolean();
        config.strip_symbols = rng.random().boolean();

        var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
        defer diagnostics.deinit();

        const linker = try StaticLinker.init(allocator, config, &diagnostics);
        defer linker.deinit();

        // Verify linker can determine object format
        const format = linker.getObjectFormat();
        try testing.expect(format == .elf or format == .macho or format == .coff);

        // Verify executable extension is correct for target
        const ext = linker.getExecutableExtension();
        switch (cg_target.os) {
            .linux, .macos => try testing.expectEqualStrings("", ext),
            .windows => try testing.expectEqualStrings(".exe", ext),
        }
    }
}

// Test 15.3.12: CodeGen target conversion
// *For any* Target, conversion to CodeGen.Target SHALL preserve architecture and OS.
test "Test 15.3.12: CodeGen target conversion" {
    // Feature: php-aot-compiler, Subtask 15.3: Cross-platform tests
    // Validates: Requirements 4.2, 4.3

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const target = CompilerTarget{
            .arch = randomCompilerArch(&rng),
            .os = randomCompilerOS(&rng),
            .abi = randomCompilerABI(&rng),
        };

        const cg_target = target.toCodeGenTarget();

        // Verify architecture is preserved
        const expected_arch: CodeGenTarget.Arch = switch (target.arch) {
            .x86_64 => .x86_64,
            .aarch64 => .aarch64,
            .arm => .arm,
        };
        try testing.expectEqual(expected_arch, cg_target.arch);

        // Verify OS is preserved
        const expected_os: CodeGenTarget.OS = switch (target.os) {
            .linux => .linux,
            .macos => .macos,
            .windows => .windows,
        };
        try testing.expectEqual(expected_os, cg_target.os);
    }
}
