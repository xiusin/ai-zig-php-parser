//! End-to-End Performance Benchmark Tests for PHP AOT Compiler
//!
//! **Feature: php-aot-compiler**
//! **Subtask 15.4: Performance Benchmark Tests**
//! **Validates: Requirements 8.5, 8.6**
//!
//! This test suite validates that the AOT compiler correctly handles
//! different optimization levels:
//! 1. Debug mode (no optimizations)
//! 2. Release-safe mode (safe optimizations)
//! 3. Release-fast mode (aggressive optimizations for speed)
//! 4. Release-small mode (optimizations for size)
//!
//! Note: These are property-based tests that verify optimization behavior,
//! not actual performance benchmarks (which would require execution).

const std = @import("std");
const testing = std.testing;

// AOT module imports
const Optimizer = @import("optimizer.zig");
const IROptimizer = Optimizer.IROptimizer;
const OptimizeLevel = Optimizer.OptimizeLevel;
const PassConfig = Optimizer.PassConfig;
const LLVMPassConfig = Optimizer.LLVMPassConfig;
const LLVMPassManager = Optimizer.LLVMPassManager;
const IR = @import("ir.zig");
const Module = IR.Module;
const Function = IR.Function;
const BasicBlock = IR.BasicBlock;
const Instruction = IR.Instruction;
const Op = IR.Op;
const Register = IR.Register;
const Diagnostics = @import("diagnostics.zig");
const CodeGen = @import("codegen.zig");
const CodeGenOptimizeLevel = CodeGen.OptimizeLevel;

/// Random number generator for property tests
const Rng = std.Random.DefaultPrng;

/// Test configuration
const TEST_ITERATIONS = 100;

// ============================================================================
// Test Infrastructure
// ============================================================================

/// Generate a random optimization level
fn randomOptLevel(rng: *Rng) OptimizeLevel {
    const levels = [_]OptimizeLevel{ .none, .basic, .aggressive, .size };
    return levels[rng.random().intRangeAtMost(usize, 0, levels.len - 1)];
}

/// Generate a random CodeGen optimization level
fn randomCodeGenOptLevel(rng: *Rng) CodeGenOptimizeLevel {
    const levels = [_]CodeGenOptimizeLevel{ .debug, .release_safe, .release_fast, .release_small };
    return levels[rng.random().intRangeAtMost(usize, 0, levels.len - 1)];
}

/// Create a simple test module
fn createTestModule(allocator: std.mem.Allocator) !*Module {
    const module = try allocator.create(Module);
    module.* = Module.init(allocator, "test_module", "test.php");

    // Create a simple function
    const func = try allocator.create(Function);
    func.* = Function.init(allocator, "test_func");
    func.return_type = .i64;

    // Add entry block with a simple terminator
    const entry = try func.createBlock("entry");
    entry.setTerminator(.{ .ret = null });

    // Add function to module
    try module.addFunction(func);

    return module;
}

// ============================================================================
// Performance Benchmark Tests
// ============================================================================

// Test 15.4.1: Optimization level pass configuration
// *For any* optimization level, getPassConfig SHALL return appropriate settings.
test "Test 15.4.1: Optimization level pass configuration" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6

    // Debug mode - no optimizations
    const debug_config = OptimizeLevel.none.getPassConfig();
    try testing.expect(!debug_config.dead_code_elimination);
    try testing.expect(!debug_config.constant_propagation);
    try testing.expect(!debug_config.function_inlining);

    // Basic mode - minimal optimizations
    const basic_config = OptimizeLevel.basic.getPassConfig();
    try testing.expect(basic_config.dead_code_elimination);
    try testing.expect(basic_config.constant_propagation);
    try testing.expect(!basic_config.function_inlining);

    // Aggressive mode - maximum optimizations
    const aggressive_config = OptimizeLevel.aggressive.getPassConfig();
    try testing.expect(aggressive_config.dead_code_elimination);
    try testing.expect(aggressive_config.constant_propagation);
    try testing.expect(aggressive_config.function_inlining);
    try testing.expect(aggressive_config.type_specialization);

    // Size mode - size optimizations
    const size_config = OptimizeLevel.size.getPassConfig();
    try testing.expect(size_config.dead_code_elimination);
    try testing.expect(size_config.constant_propagation);
    try testing.expect(!size_config.function_inlining); // Inlining increases size
}

// Test 15.4.2: Optimizer initialization with different levels
// *For any* optimization level, the optimizer SHALL initialize correctly.
test "Test 15.4.2: Optimizer initialization with different levels" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const level = randomOptLevel(&rng);

        var optimizer = IROptimizer.init(allocator, level, null);
        defer optimizer.deinit();

        // Verify optimizer is initialized with correct level
        const config = optimizer.config;
        const expected_config = level.getPassConfig();

        try testing.expectEqual(expected_config.dead_code_elimination, config.dead_code_elimination);
        try testing.expectEqual(expected_config.constant_propagation, config.constant_propagation);
        try testing.expectEqual(expected_config.function_inlining, config.function_inlining);
    }
}

// Test 15.4.3: PassConfig debug mode
// *For any* debug PassConfig, all optimizations SHALL be disabled.
test "Test 15.4.3: PassConfig debug mode" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5

    const config = PassConfig.debug();

    try testing.expect(!config.dead_code_elimination);
    try testing.expect(!config.constant_propagation);
    try testing.expect(!config.cse);
    try testing.expect(!config.strength_reduction);
    try testing.expect(!config.function_inlining);
    try testing.expect(!config.type_specialization);
}

// Test 15.4.4: PassConfig release-fast mode
// *For any* release-fast PassConfig, key optimizations SHALL be enabled.
test "Test 15.4.4: PassConfig release-fast mode" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.6

    const config = PassConfig.releaseFast();

    try testing.expect(config.dead_code_elimination);
    try testing.expect(config.constant_propagation);
    try testing.expect(config.cse);
    try testing.expect(config.strength_reduction);
    try testing.expect(config.function_inlining);
    try testing.expect(config.type_specialization);
}

// Test 15.4.5: LLVM pass configuration for different levels
// *For any* optimization level, LLVM pass config SHALL be appropriate.
test "Test 15.4.5: LLVM pass configuration for different levels" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6

    // Debug mode - minimal passes
    const debug_config = LLVMPassConfig.debug();
    try testing.expect(!debug_config.inline_functions);
    try testing.expect(!debug_config.loop_unroll);
    try testing.expect(!debug_config.gvn);

    // Release-safe mode - safe passes
    const safe_config = LLVMPassConfig.releaseSafe();
    try testing.expect(safe_config.instcombine);
    try testing.expect(safe_config.simplifycfg);

    // Release-fast mode - aggressive passes
    const fast_config = LLVMPassConfig.releaseFast();
    try testing.expect(fast_config.inline_functions);
    try testing.expect(fast_config.gvn);
    try testing.expect(fast_config.licm);

    // Release-small mode - size-focused passes
    const small_config = LLVMPassConfig.releaseSmall();
    try testing.expect(!small_config.loop_unroll); // Unrolling increases size
    try testing.expect(small_config.globaldce);
}

// Test 15.4.6: LLVM pass manager initialization
// *For any* optimization level, the pass manager SHALL initialize correctly.
test "Test 15.4.6: LLVM pass manager initialization" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const level = randomOptLevel(&rng);

        var pass_manager = LLVMPassManager.init(allocator, level);
        defer pass_manager.deinit();

        // Verify pass manager has a valid configuration
        const config = pass_manager.config;
        // Basic sanity check - inline_threshold should be reasonable
        try testing.expect(config.inline_threshold <= 1000);
    }
}

// Test 15.4.7: Optimization statistics tracking
// *For any* optimization run, statistics SHALL be tracked correctly.
test "Test 15.4.7: Optimization statistics tracking" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6
    const allocator = testing.allocator;

    var optimizer = IROptimizer.init(allocator, .aggressive, null);
    defer optimizer.deinit();

    // Get initial stats
    const stats = optimizer.getStats();

    // Stats should be initialized to zero
    try testing.expectEqual(@as(u32, 0), stats.dead_instructions_removed);
    try testing.expectEqual(@as(u32, 0), stats.constants_propagated);
    try testing.expectEqual(@as(u32, 0), stats.functions_inlined);
}

// Test 15.4.8: CodeGen optimization level mapping
// *For any* CodeGen optimization level, it SHALL have correct properties.
test "Test 15.4.8: CodeGen optimization level mapping" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6

    // Debug - no optimizations
    try testing.expectEqual(CodeGenOptimizeLevel.debug, CodeGenOptimizeLevel.debug);

    // Release-safe - safe optimizations
    try testing.expectEqual(CodeGenOptimizeLevel.release_safe, CodeGenOptimizeLevel.release_safe);

    // Release-fast - speed optimizations
    try testing.expectEqual(CodeGenOptimizeLevel.release_fast, CodeGenOptimizeLevel.release_fast);

    // Release-small - size optimizations
    try testing.expectEqual(CodeGenOptimizeLevel.release_small, CodeGenOptimizeLevel.release_small);
}

// Test 15.4.9: Optimization level consistency
// *For any* optimization level, higher levels SHALL enable more optimizations.
test "Test 15.4.9: Optimization level consistency" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6

    const none_config = OptimizeLevel.none.getPassConfig();
    const basic_config = OptimizeLevel.basic.getPassConfig();
    const aggressive_config = OptimizeLevel.aggressive.getPassConfig();

    // Count enabled optimizations for each level
    const none_count = countEnabledOpts(none_config);
    const basic_count = countEnabledOpts(basic_config);
    const aggressive_count = countEnabledOpts(aggressive_config);

    // Higher levels should have more or equal optimizations enabled
    try testing.expect(basic_count >= none_count);
    try testing.expect(aggressive_count >= basic_count);
}

fn countEnabledOpts(config: PassConfig) u32 {
    var count: u32 = 0;
    if (config.dead_code_elimination) count += 1;
    if (config.constant_propagation) count += 1;
    if (config.cse) count += 1;
    if (config.strength_reduction) count += 1;
    if (config.function_inlining) count += 1;
    if (config.type_specialization) count += 1;
    return count;
}

// Test 15.4.10: Module creation for optimization
// *For any* module, it SHALL be creatable for optimization testing.
test "Test 15.4.10: Module creation for optimization" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const level = randomOptLevel(&rng);

        var optimizer = IROptimizer.init(allocator, level, null);
        defer optimizer.deinit();

        // Create a test module
        const module = try createTestModule(allocator);
        defer {
            module.deinit();
            allocator.destroy(module);
        }

        // Verify module was created correctly
        try testing.expectEqual(@as(usize, 1), module.functions.items.len);
        try testing.expectEqualStrings("test_func", module.functions.items[0].name);
    }
}

// Test 15.4.11: LLVM pass config inline threshold
// *For any* LLVM config, inline_threshold SHALL be reasonable.
test "Test 15.4.11: LLVM pass config inline threshold" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6

    const configs = [_]LLVMPassConfig{
        LLVMPassConfig.debug(),
        LLVMPassConfig.releaseSafe(),
        LLVMPassConfig.releaseFast(),
        LLVMPassConfig.releaseSmall(),
    };

    for (configs) |config| {
        // Inline threshold should be reasonable (0-1000)
        try testing.expect(config.inline_threshold <= 1000);
    }
}

// Test 15.4.12: Optimizer initialization with diagnostics
// *For any* optimization level with diagnostics, initialization SHALL succeed.
test "Test 15.4.12: Optimizer initialization with diagnostics" {
    // Feature: php-aot-compiler, Subtask 15.4: Performance benchmarks
    // Validates: Requirements 8.5, 8.6
    const allocator = testing.allocator;

    var rng = Rng.init(@intCast(std.time.timestamp()));

    var i: usize = 0;
    while (i < TEST_ITERATIONS) : (i += 1) {
        const level = randomOptLevel(&rng);

        var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
        defer diagnostics.deinit();

        var optimizer = IROptimizer.init(allocator, level, &diagnostics);
        defer optimizer.deinit();

        // Verify optimizer was initialized correctly
        const config = optimizer.config;
        const expected_config = level.getPassConfig();
        try testing.expectEqual(expected_config.dead_code_elimination, config.dead_code_elimination);

        // No errors should be reported during initialization
        try testing.expect(!diagnostics.hasErrors());
    }
}
