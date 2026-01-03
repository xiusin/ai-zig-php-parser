//! Property-Based Tests for ZigLinker Output File Name Correctness
//!
//! **Feature: aot-native-compilation, Property 7: Output file name correctness**
//!
//! *For any* specified output file name, the linker generates the executable
//! at the correct path that matches the specified path exactly.
//!
//! **Validates: Requirements 3.5**

const std = @import("std");
const testing = std.testing;
const Linker = @import("linker.zig");
const ZigLinker = Linker.ZigLinker;
const ZigLinkerConfig = Linker.ZigLinkerConfig;
const Diagnostics = @import("diagnostics.zig");
const CodeGen = @import("codegen.zig");
const Target = CodeGen.Target;
const OptimizeLevel = CodeGen.OptimizeLevel;

/// Random number generator for property tests
const Rng = std.Random.DefaultPrng;

/// Number of iterations for property tests
const PROPERTY_TEST_ITERATIONS = 100;

// ============================================================================
// Test Data Generators
// ============================================================================

/// Generate a random valid file name (alphanumeric with underscores)
fn generateRandomFileName(rng: *Rng, allocator: std.mem.Allocator) ![]const u8 {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
    const len = rng.random().intRangeAtMost(usize, 1, 20);
    
    const name = try allocator.alloc(u8, len);
    for (name) |*c| {
        const idx = rng.random().intRangeAtMost(usize, 0, chars.len - 1);
        c.* = chars[idx];
    }
    
    return name;
}

/// Generate a random PHP file path
fn generateRandomPhpPath(rng: *Rng, allocator: std.mem.Allocator) ![]const u8 {
    const name = try generateRandomFileName(rng, allocator);
    defer allocator.free(name);
    
    // Randomly add directory prefix
    const has_dir = rng.random().boolean();
    if (has_dir) {
        const dir = try generateRandomFileName(rng, allocator);
        defer allocator.free(dir);
        return std.fmt.allocPrint(allocator, "{s}/{s}.php", .{ dir, name });
    }
    
    return std.fmt.allocPrint(allocator, "{s}.php", .{name});
}

/// Generate a random output path
fn generateRandomOutputPath(rng: *Rng, allocator: std.mem.Allocator) ![]const u8 {
    const name = try generateRandomFileName(rng, allocator);
    defer allocator.free(name);
    
    // Randomly add directory prefix
    const has_dir = rng.random().boolean();
    if (has_dir) {
        const dir = try generateRandomFileName(rng, allocator);
        defer allocator.free(dir);
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name });
    }
    
    return std.fmt.allocPrint(allocator, "{s}", .{name});
}

/// Generate a random target platform
fn generateRandomTarget(rng: *Rng) ?[]const u8 {
    const targets = [_]?[]const u8{
        null, // Native
        "x86_64-linux-gnu",
        "aarch64-linux-gnu",
        "x86_64-macos",
        "aarch64-macos",
        "x86_64-windows-msvc",
    };
    
    const idx = rng.random().intRangeAtMost(usize, 0, targets.len - 1);
    return targets[idx];
}

// ============================================================================
// Property 7: Output File Name Correctness
// ============================================================================

// Property 7.1: Explicit output path is preserved exactly
// For any specified output file name, generateOutputPath returns that exact name
test "Property 7.1: Explicit output path preservation (100 iterations)" {
    var rng = Rng.init(@intCast(std.time.timestamp()));
    const allocator = testing.allocator;
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();
    
    var i: usize = 0;
    while (i < PROPERTY_TEST_ITERATIONS) : (i += 1) {
        const input_path = try generateRandomPhpPath(&rng, allocator);
        defer allocator.free(input_path);
        
        const explicit_output = try generateRandomOutputPath(&rng, allocator);
        defer allocator.free(explicit_output);
        
        const result = try linker.generateOutputPath(input_path, explicit_output);
        defer allocator.free(result);
        
        // Property: explicit output path is preserved exactly
        try testing.expectEqualStrings(explicit_output, result);
    }
}

// Property 7.2: Derived output removes .php extension
// For any input file with .php extension, the derived output has no .php extension
test "Property 7.2: PHP extension removal (100 iterations)" {
    var rng = Rng.init(@intCast(std.time.timestamp()));
    const allocator = testing.allocator;
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();
    
    var i: usize = 0;
    while (i < PROPERTY_TEST_ITERATIONS) : (i += 1) {
        const input_path = try generateRandomPhpPath(&rng, allocator);
        defer allocator.free(input_path);
        
        const result = try linker.generateOutputPath(input_path, null);
        defer allocator.free(result);
        
        // Property: derived output does not end with .php
        try testing.expect(!std.mem.endsWith(u8, result, ".php"));
    }
}

// Property 7.3: Windows target adds .exe extension
// For any Windows target, the derived output has .exe extension
test "Property 7.3: Windows executable extension (100 iterations)" {
    var rng = Rng.init(@intCast(std.time.timestamp()));
    const allocator = testing.allocator;
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    var config = ZigLinkerConfig.default();
    config.target = "x86_64-windows-msvc";
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();
    
    var i: usize = 0;
    while (i < PROPERTY_TEST_ITERATIONS) : (i += 1) {
        const input_path = try generateRandomPhpPath(&rng, allocator);
        defer allocator.free(input_path);
        
        const result = try linker.generateOutputPath(input_path, null);
        defer allocator.free(result);
        
        // Property: Windows output ends with .exe
        try testing.expect(std.mem.endsWith(u8, result, ".exe"));
    }
}

// Property 7.4: Non-Windows target has no .exe extension
// For any non-Windows target, the derived output has no .exe extension
test "Property 7.4: Non-Windows no executable extension (100 iterations)" {
    var rng = Rng.init(@intCast(std.time.timestamp()));
    const allocator = testing.allocator;
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    const non_windows_targets = [_][]const u8{
        "x86_64-linux-gnu",
        "aarch64-linux-gnu",
        "x86_64-macos",
        "aarch64-macos",
    };
    
    var i: usize = 0;
    while (i < PROPERTY_TEST_ITERATIONS) : (i += 1) {
        const target_idx = rng.random().intRangeAtMost(usize, 0, non_windows_targets.len - 1);
        
        var config = ZigLinkerConfig.default();
        config.target = non_windows_targets[target_idx];
        const linker = try ZigLinker.init(allocator, config, &diagnostics);
        defer linker.deinit();
        
        const input_path = try generateRandomPhpPath(&rng, allocator);
        defer allocator.free(input_path);
        
        const result = try linker.generateOutputPath(input_path, null);
        defer allocator.free(result);
        
        // Property: non-Windows output does not end with .exe
        try testing.expect(!std.mem.endsWith(u8, result, ".exe"));
    }
}

// Property 7.5: Base name extraction is consistent
// For any input path, the base name (without directory and extension) is preserved
test "Property 7.5: Base name preservation (100 iterations)" {
    var rng = Rng.init(@intCast(std.time.timestamp()));
    const allocator = testing.allocator;
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();
    
    var i: usize = 0;
    while (i < PROPERTY_TEST_ITERATIONS) : (i += 1) {
        // Generate a simple file name (no directory)
        const base_name = try generateRandomFileName(&rng, allocator);
        defer allocator.free(base_name);
        
        const input_path = try std.fmt.allocPrint(allocator, "{s}.php", .{base_name});
        defer allocator.free(input_path);
        
        const result = try linker.generateOutputPath(input_path, null);
        defer allocator.free(result);
        
        // Property: result starts with the base name
        try testing.expect(std.mem.startsWith(u8, result, base_name));
    }
}

// Property 7.6: Output path determinism
// For the same input and configuration, generateOutputPath always returns the same result
test "Property 7.6: Output path determinism (100 iterations)" {
    var rng = Rng.init(@intCast(std.time.timestamp()));
    const allocator = testing.allocator;
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    var i: usize = 0;
    while (i < PROPERTY_TEST_ITERATIONS) : (i += 1) {
        const target = generateRandomTarget(&rng);
        
        var config = ZigLinkerConfig.default();
        config.target = target;
        const linker = try ZigLinker.init(allocator, config, &diagnostics);
        defer linker.deinit();
        
        const input_path = try generateRandomPhpPath(&rng, allocator);
        defer allocator.free(input_path);
        
        // Generate output twice
        const result1 = try linker.generateOutputPath(input_path, null);
        defer allocator.free(result1);
        
        const result2 = try linker.generateOutputPath(input_path, null);
        defer allocator.free(result2);
        
        // Property: same input produces same output
        try testing.expectEqualStrings(result1, result2);
    }
}

// ============================================================================
// Additional Property Tests for Zig Command Building
// ============================================================================

// Property 7.7: Zig command always includes output path
// For any configuration, the built command includes the output path
test "Property 7.7: Zig command includes output path (100 iterations)" {
    var rng = Rng.init(@intCast(std.time.timestamp()));
    const allocator = testing.allocator;
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    var i: usize = 0;
    while (i < PROPERTY_TEST_ITERATIONS) : (i += 1) {
        const target = generateRandomTarget(&rng);
        
        var config = ZigLinkerConfig.default();
        config.target = target;
        const linker = try ZigLinker.init(allocator, config, &diagnostics);
        defer linker.deinit();
        
        const output_path = try generateRandomOutputPath(&rng, allocator);
        defer allocator.free(output_path);
        
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(allocator);
        
        try linker.buildZigCommand(&args, "test.zig", output_path);
        
        // Property: command includes output path in -femit-bin flag
        var found_output = false;
        for (args.items) |arg| {
            if (std.mem.startsWith(u8, arg, "-femit-bin=")) {
                found_output = true;
                try testing.expect(std.mem.endsWith(u8, arg, output_path));
            }
        }
        try testing.expect(found_output);
    }
}
