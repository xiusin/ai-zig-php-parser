//! Property-Based Tests for Static Linker
//!
//! This module contains property-based tests for the static linker module.
//! These tests verify that dead code elimination works correctly and that
//! the linker properly analyzes runtime function usage.
//!
//! **Feature: php-aot-compiler, Property 10: 死代码消除正确性**
//! *For any* code path that is statically determined to be unreachable,
//! the optimized IR SHALL not contain instructions for that path,
//! AND removing this code SHALL not change the observable behavior of the program.
//!
//! **Validates: Requirements 8.2**

const std = @import("std");
const linker = @import("linker.zig");
const IR = @import("ir.zig");
const Diagnostics = @import("diagnostics.zig");
const CodeGen = @import("codegen.zig");

const StaticLinker = linker.StaticLinker;
const LinkerConfig = linker.LinkerConfig;
const ObjectFormat = linker.ObjectFormat;
const ObjectCode = linker.ObjectCode;
const Target = CodeGen.Target;

// ============================================================================
// Test Utilities
// ============================================================================

/// Create a test linker with default configuration
fn createTestLinker(allocator: std.mem.Allocator, target: Target) !struct {
    linker: *StaticLinker,
    diagnostics: *Diagnostics.DiagnosticEngine,
} {
    const diagnostics = try allocator.create(Diagnostics.DiagnosticEngine);
    diagnostics.* = Diagnostics.DiagnosticEngine.init(allocator);

    const config = LinkerConfig.default(target);
    const lnk = try StaticLinker.init(allocator, config, diagnostics);

    return .{ .linker = lnk, .diagnostics = diagnostics };
}

/// Clean up test linker
fn destroyTestLinker(
    allocator: std.mem.Allocator,
    lnk: *StaticLinker,
    diagnostics: *Diagnostics.DiagnosticEngine,
) void {
    lnk.deinit();
    diagnostics.deinit();
    allocator.destroy(diagnostics);
}

/// Create a test IR module with specified functions
fn createTestModule(allocator: std.mem.Allocator, name: []const u8) IR.Module {
    return IR.Module.init(allocator, name, "test.php");
}

/// Create a test function with entry block
fn createTestFunction(allocator: std.mem.Allocator, name: []const u8) !*IR.Function {
    const func = try allocator.create(IR.Function);
    func.* = IR.Function.init(allocator, name);
    _ = try func.createBlock("entry");
    return func;
}

// ============================================================================
// Property 10: Dead Code Elimination Correctness
// ============================================================================

// Property 10.1: Runtime functions used in IR are correctly identified
// For any IR module, the linker should identify all runtime functions that are called
test "Property 10.1: Runtime function usage detection - string operations" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    var module = createTestModule(allocator, "test_string_usage");
    defer module.deinit();

    const func = try createTestFunction(allocator, "test_func");
    try module.addFunction(func);

    const entry = func.getEntryBlock().?;

    // Add string constant instruction (should trigger php_value_create_string)
    const str_reg = func.newRegister(.php_string);
    const str_inst = try allocator.create(IR.Instruction);
    str_inst.* = .{
        .result = str_reg,
        .op = .{ .const_string = 0 },
        .location = .{},
    };
    try entry.appendInstruction(str_inst);

    // Add strlen instruction (should trigger php_string_length)
    const len_reg = func.newRegister(.i64);
    const len_inst = try allocator.create(IR.Instruction);
    len_inst.* = .{
        .result = len_reg,
        .op = .{ .strlen = .{ .operand = str_reg } },
        .location = .{},
    };
    try entry.appendInstruction(len_inst);

    entry.setTerminator(.{ .ret = null });

    // Analyze used functions
    try result.linker.analyzeUsedFunctions(&module);

    // Verify string-related runtime functions are detected
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_create_string"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_string_length"));
    try std.testing.expect(result.linker.getUsedRuntimeFunctionCount() >= 2);
}

// Property 10.2: Array operations trigger correct runtime function detection
test "Property 10.2: Runtime function usage detection - array operations" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    var module = createTestModule(allocator, "test_array_usage");
    defer module.deinit();

    const func = try createTestFunction(allocator, "test_func");
    try module.addFunction(func);

    const entry = func.getEntryBlock().?;

    // Add array_new instruction
    const arr_reg = func.newRegister(.php_array);
    const arr_inst = try allocator.create(IR.Instruction);
    arr_inst.* = .{
        .result = arr_reg,
        .op = .{ .array_new = .{ .capacity = 10 } },
        .location = .{},
    };
    try entry.appendInstruction(arr_inst);

    // Add array_get instruction
    const key_reg = func.newRegister(.i64);
    const key_inst = try allocator.create(IR.Instruction);
    key_inst.* = .{
        .result = key_reg,
        .op = .{ .const_int = 0 },
        .location = .{},
    };
    try entry.appendInstruction(key_inst);

    const get_reg = func.newRegister(.php_value);
    const get_inst = try allocator.create(IR.Instruction);
    get_inst.* = .{
        .result = get_reg,
        .op = .{ .array_get = .{ .array = arr_reg, .key = key_reg } },
        .location = .{},
    };
    try entry.appendInstruction(get_inst);

    // Add array_set instruction
    const val_reg = func.newRegister(.php_value);
    const val_inst = try allocator.create(IR.Instruction);
    val_inst.* = .{
        .result = val_reg,
        .op = .{ .const_int = 42 },
        .location = .{},
    };
    try entry.appendInstruction(val_inst);

    const set_inst = try allocator.create(IR.Instruction);
    set_inst.* = .{
        .result = null,
        .op = .{ .array_set = .{ .array = arr_reg, .key = key_reg, .value = val_reg } },
        .location = .{},
    };
    try entry.appendInstruction(set_inst);

    entry.setTerminator(.{ .ret = null });

    // Analyze used functions
    try result.linker.analyzeUsedFunctions(&module);

    // Verify array-related runtime functions are detected
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_create_array"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_array_create"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_array_get"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_array_set"));
}

// Property 10.3: GC operations trigger correct runtime function detection
test "Property 10.3: Runtime function usage detection - GC operations" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    var module = createTestModule(allocator, "test_gc_usage");
    defer module.deinit();

    const func = try createTestFunction(allocator, "test_func");
    try module.addFunction(func);

    const entry = func.getEntryBlock().?;

    // Create a value
    const val_reg = func.newRegister(.php_value);
    const val_inst = try allocator.create(IR.Instruction);
    val_inst.* = .{
        .result = val_reg,
        .op = .{ .const_int = 42 },
        .location = .{},
    };
    try entry.appendInstruction(val_inst);

    // Add retain instruction
    const retain_inst = try allocator.create(IR.Instruction);
    retain_inst.* = .{
        .result = null,
        .op = .{ .retain = .{ .operand = val_reg } },
        .location = .{},
    };
    try entry.appendInstruction(retain_inst);

    // Add release instruction
    const release_inst = try allocator.create(IR.Instruction);
    release_inst.* = .{
        .result = null,
        .op = .{ .release = .{ .operand = val_reg } },
        .location = .{},
    };
    try entry.appendInstruction(release_inst);

    entry.setTerminator(.{ .ret = null });

    // Analyze used functions
    try result.linker.analyzeUsedFunctions(&module);

    // Verify GC-related runtime functions are detected
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_gc_retain"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_gc_release"));
}

// Property 10.4: Unused runtime functions are not marked as used
test "Property 10.4: Unused runtime functions not detected" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    var module = createTestModule(allocator, "test_minimal");
    defer module.deinit();

    const func = try createTestFunction(allocator, "test_func");
    try module.addFunction(func);

    const entry = func.getEntryBlock().?;

    // Only add a simple integer constant (no runtime calls needed)
    const val_reg = func.newRegister(.i64);
    const val_inst = try allocator.create(IR.Instruction);
    val_inst.* = .{
        .result = val_reg,
        .op = .{ .const_int = 42 },
        .location = .{},
    };
    try entry.appendInstruction(val_inst);

    entry.setTerminator(.{ .ret = val_reg });

    // Analyze used functions
    try result.linker.analyzeUsedFunctions(&module);

    // Verify no runtime functions are detected for simple integer operations
    try std.testing.expect(!result.linker.isRuntimeFunctionUsed("php_value_create_string"));
    try std.testing.expect(!result.linker.isRuntimeFunctionUsed("php_array_create"));
    try std.testing.expect(!result.linker.isRuntimeFunctionUsed("php_gc_retain"));
    try std.testing.expectEqual(@as(usize, 0), result.linker.getUsedRuntimeFunctionCount());
}

// Property 10.5: Multiple functions are analyzed correctly
test "Property 10.5: Multiple function analysis" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    var module = createTestModule(allocator, "test_multi_func");
    defer module.deinit();

    // Function 1: uses string operations
    const func1 = try createTestFunction(allocator, "func1");
    try module.addFunction(func1);
    const entry1 = func1.getEntryBlock().?;

    const str_reg = func1.newRegister(.php_string);
    const str_inst = try allocator.create(IR.Instruction);
    str_inst.* = .{
        .result = str_reg,
        .op = .{ .const_string = 0 },
        .location = .{},
    };
    try entry1.appendInstruction(str_inst);
    entry1.setTerminator(.{ .ret = null });

    // Function 2: uses array operations
    const func2 = try createTestFunction(allocator, "func2");
    try module.addFunction(func2);
    const entry2 = func2.getEntryBlock().?;

    const arr_reg = func2.newRegister(.php_array);
    const arr_inst = try allocator.create(IR.Instruction);
    arr_inst.* = .{
        .result = arr_reg,
        .op = .{ .array_new = .{ .capacity = 5 } },
        .location = .{},
    };
    try entry2.appendInstruction(arr_inst);
    entry2.setTerminator(.{ .ret = null });

    // Analyze used functions
    try result.linker.analyzeUsedFunctions(&module);

    // Verify both string and array functions are detected
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_create_string"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_create_array"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_array_create"));
}

// Property 10.6: Re-analysis clears previous results
test "Property 10.6: Re-analysis clears previous results" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    // First module with string operations
    var module1 = createTestModule(allocator, "test_module1");
    defer module1.deinit();

    const func1 = try createTestFunction(allocator, "func1");
    try module1.addFunction(func1);
    const entry1 = func1.getEntryBlock().?;

    const str_reg = func1.newRegister(.php_string);
    const str_inst = try allocator.create(IR.Instruction);
    str_inst.* = .{
        .result = str_reg,
        .op = .{ .const_string = 0 },
        .location = .{},
    };
    try entry1.appendInstruction(str_inst);
    entry1.setTerminator(.{ .ret = null });

    try result.linker.analyzeUsedFunctions(&module1);
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_create_string"));

    // Second module with only array operations (no strings)
    var module2 = createTestModule(allocator, "test_module2");
    defer module2.deinit();

    const func2 = try createTestFunction(allocator, "func2");
    try module2.addFunction(func2);
    const entry2 = func2.getEntryBlock().?;

    const arr_reg = func2.newRegister(.php_array);
    const arr_inst = try allocator.create(IR.Instruction);
    arr_inst.* = .{
        .result = arr_reg,
        .op = .{ .array_new = .{ .capacity = 5 } },
        .location = .{},
    };
    try entry2.appendInstruction(arr_inst);
    entry2.setTerminator(.{ .ret = null });

    // Re-analyze with second module
    try result.linker.analyzeUsedFunctions(&module2);

    // String function should no longer be marked as used
    try std.testing.expect(!result.linker.isRuntimeFunctionUsed("php_value_create_string"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_create_array"));
}

// Property 10.7: Direct runtime function calls are detected
test "Property 10.7: Direct runtime function call detection" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    var module = createTestModule(allocator, "test_direct_call");
    defer module.deinit();

    const func = try createTestFunction(allocator, "test_func");
    try module.addFunction(func);

    const entry = func.getEntryBlock().?;

    // Direct call to a runtime function
    const call_inst = try allocator.create(IR.Instruction);
    call_inst.* = .{
        .result = null,
        .op = .{ .call = .{
            .func_name = "php_echo",
            .args = &[_]IR.Register{},
            .return_type = .void,
        } },
        .location = .{},
    };
    try entry.appendInstruction(call_inst);

    entry.setTerminator(.{ .ret = null });

    // Analyze used functions
    try result.linker.analyzeUsedFunctions(&module);

    // Verify the directly called function is detected
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_echo"));
}

// Property 10.8: Non-runtime function calls are not marked
test "Property 10.8: Non-runtime function calls not marked" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    var module = createTestModule(allocator, "test_user_call");
    defer module.deinit();

    const func = try createTestFunction(allocator, "test_func");
    try module.addFunction(func);

    const entry = func.getEntryBlock().?;

    // Call to a user-defined function (not a runtime function)
    const call_inst = try allocator.create(IR.Instruction);
    call_inst.* = .{
        .result = null,
        .op = .{ .call = .{
            .func_name = "my_user_function",
            .args = &[_]IR.Register{},
            .return_type = .void,
        } },
        .location = .{},
    };
    try entry.appendInstruction(call_inst);

    entry.setTerminator(.{ .ret = null });

    // Analyze used functions
    try result.linker.analyzeUsedFunctions(&module);

    // Verify user function is not marked as runtime function
    try std.testing.expect(!result.linker.isRuntimeFunctionUsed("my_user_function"));
    try std.testing.expectEqual(@as(usize, 0), result.linker.getUsedRuntimeFunctionCount());
}

// ============================================================================
// Property 10 Iteration Tests (100 iterations)
// ============================================================================

// Property 10.9: Randomized instruction coverage test
// For any combination of IR instructions, the linker correctly identifies used runtime functions
test "Property 10.9: Randomized instruction coverage (100 iterations)" {
    const allocator = std.testing.allocator;

    // Run 100 iterations with different instruction combinations
    var iteration: usize = 0;
    while (iteration < 100) : (iteration += 1) {
        const result = try createTestLinker(allocator, Target.native());
        defer destroyTestLinker(allocator, result.linker, result.diagnostics);

        var module = createTestModule(allocator, "test_random");
        defer module.deinit();

        const func = try createTestFunction(allocator, "test_func");
        try module.addFunction(func);

        const entry = func.getEntryBlock().?;

        // Use iteration number to determine which instructions to add
        var expected_functions = std.StringHashMap(void).init(allocator);
        defer expected_functions.deinit();

        // Add instructions based on iteration bits
        if (iteration & 1 != 0) {
            const str_reg = func.newRegister(.php_string);
            const str_inst = try allocator.create(IR.Instruction);
            str_inst.* = .{
                .result = str_reg,
                .op = .{ .const_string = 0 },
                .location = .{},
            };
            try entry.appendInstruction(str_inst);
            try expected_functions.put("php_value_create_string", {});
        }

        if (iteration & 2 != 0) {
            const arr_reg = func.newRegister(.php_array);
            const arr_inst = try allocator.create(IR.Instruction);
            arr_inst.* = .{
                .result = arr_reg,
                .op = .{ .array_new = .{ .capacity = 5 } },
                .location = .{},
            };
            try entry.appendInstruction(arr_inst);
            try expected_functions.put("php_value_create_array", {});
            try expected_functions.put("php_array_create", {});
        }

        if (iteration & 4 != 0) {
            const val_reg = func.newRegister(.php_value);
            const val_inst = try allocator.create(IR.Instruction);
            val_inst.* = .{
                .result = val_reg,
                .op = .{ .const_int = @as(i64, @intCast(iteration)) },
                .location = .{},
            };
            try entry.appendInstruction(val_inst);

            const retain_inst = try allocator.create(IR.Instruction);
            retain_inst.* = .{
                .result = null,
                .op = .{ .retain = .{ .operand = val_reg } },
                .location = .{},
            };
            try entry.appendInstruction(retain_inst);
            try expected_functions.put("php_gc_retain", {});
        }

        if (iteration & 8 != 0) {
            const print_inst = try allocator.create(IR.Instruction);
            print_inst.* = .{
                .result = null,
                .op = .{ .debug_print = .{ .operand = func.newRegister(.php_value) } },
                .location = .{},
            };
            try entry.appendInstruction(print_inst);
            try expected_functions.put("php_echo", {});
        }

        entry.setTerminator(.{ .ret = null });

        // Analyze
        try result.linker.analyzeUsedFunctions(&module);

        // Verify all expected functions are detected
        var iter = expected_functions.keyIterator();
        while (iter.next()) |key| {
            try std.testing.expect(result.linker.isRuntimeFunctionUsed(key.*));
        }
    }
}

// Property 10.10: Object and type operations detection
test "Property 10.10: Object and type operations detection" {
    const allocator = std.testing.allocator;
    const result = try createTestLinker(allocator, Target.native());
    defer destroyTestLinker(allocator, result.linker, result.diagnostics);

    var module = createTestModule(allocator, "test_object_type");
    defer module.deinit();

    const func = try createTestFunction(allocator, "test_func");
    try module.addFunction(func);

    const entry = func.getEntryBlock().?;

    // Add new_object instruction
    const obj_reg = func.newRegister(.{ .php_object = "TestClass" });
    const obj_inst = try allocator.create(IR.Instruction);
    obj_inst.* = .{
        .result = obj_reg,
        .op = .{ .new_object = .{ .class_name = "TestClass", .args = &[_]IR.Register{} } },
        .location = .{},
    };
    try entry.appendInstruction(obj_inst);

    // Add type_check instruction
    const check_reg = func.newRegister(.bool);
    const check_inst = try allocator.create(IR.Instruction);
    check_inst.* = .{
        .result = check_reg,
        .op = .{ .type_check = .{ .value = obj_reg, .expected_type = .{ .php_object = "TestClass" } } },
        .location = .{},
    };
    try entry.appendInstruction(check_inst);

    // Add get_type instruction
    const type_reg = func.newRegister(.i64);
    const type_inst = try allocator.create(IR.Instruction);
    type_inst.* = .{
        .result = type_reg,
        .op = .{ .get_type = .{ .operand = obj_reg } },
        .location = .{},
    };
    try entry.appendInstruction(type_inst);

    // Add cast instruction
    const cast_reg = func.newRegister(.php_value);
    const cast_inst = try allocator.create(IR.Instruction);
    cast_inst.* = .{
        .result = cast_reg,
        .op = .{ .cast = .{ .value = obj_reg, .from_type = .{ .php_object = "TestClass" }, .to_type = .php_value } },
        .location = .{},
    };
    try entry.appendInstruction(cast_inst);

    entry.setTerminator(.{ .ret = null });

    // Analyze used functions
    try result.linker.analyzeUsedFunctions(&module);

    // Verify object and type-related runtime functions are detected
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_create_object"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_get_type"));
    try std.testing.expect(result.linker.isRuntimeFunctionUsed("php_value_cast"));
}

// ============================================================================
// Object Code Validation Tests
// ============================================================================

// Test that object code validation works correctly
test "Object code validation: Valid formats" {
    const allocator = std.testing.allocator;

    // Test ELF validation
    const elf_result = try createTestLinker(allocator, Target{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    defer destroyTestLinker(allocator, elf_result.linker, elf_result.diagnostics);

    var elf_obj = try elf_result.linker.generateMockObjectCode("test_elf");
    defer elf_obj.deinit(allocator);
    try std.testing.expect(elf_obj.isValid());
    try std.testing.expectEqual(ObjectFormat.elf, elf_obj.format);

    // Test MachO validation
    const macho_result = try createTestLinker(allocator, Target{ .arch = .aarch64, .os = .macos, .abi = .none });
    defer destroyTestLinker(allocator, macho_result.linker, macho_result.diagnostics);

    var macho_obj = try macho_result.linker.generateMockObjectCode("test_macho");
    defer macho_obj.deinit(allocator);
    try std.testing.expect(macho_obj.isValid());
    try std.testing.expectEqual(ObjectFormat.macho, macho_obj.format);

    // Test COFF validation
    const coff_result = try createTestLinker(allocator, Target{ .arch = .x86_64, .os = .windows, .abi = .msvc });
    defer destroyTestLinker(allocator, coff_result.linker, coff_result.diagnostics);

    var coff_obj = try coff_result.linker.generateMockObjectCode("test_coff");
    defer coff_obj.deinit(allocator);
    try std.testing.expect(coff_obj.isValid());
    try std.testing.expectEqual(ObjectFormat.coff, coff_obj.format);
}

// Test that invalid object code is rejected
test "Object code validation: Invalid formats" {
    // Empty data
    const empty_obj = ObjectCode.initBorrowed(&[_]u8{}, .elf, "empty");
    try std.testing.expect(!empty_obj.isValid());

    // Invalid ELF magic
    const invalid_elf = ObjectCode.initBorrowed(&[_]u8{ 0x00, 0x00, 0x00, 0x00 }, .elf, "invalid_elf");
    try std.testing.expect(!invalid_elf.isValid());

    // Invalid MachO magic
    const invalid_macho = ObjectCode.initBorrowed(&[_]u8{ 0x00, 0x00, 0x00, 0x00 }, .macho, "invalid_macho");
    try std.testing.expect(!invalid_macho.isValid());

    // Invalid COFF magic
    const invalid_coff = ObjectCode.initBorrowed(&[_]u8{ 0x00, 0x00 }, .coff, "invalid_coff");
    try std.testing.expect(!invalid_coff.isValid());
}

// ============================================================================
// Linker Configuration Tests
// ============================================================================

// Test linker configuration for different targets
test "Linker configuration: Target-specific settings" {
    const allocator = std.testing.allocator;

    // Linux target
    const linux_result = try createTestLinker(allocator, Target{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    defer destroyTestLinker(allocator, linux_result.linker, linux_result.diagnostics);

    const linux_paths = linux_result.linker.getRuntimeLibPaths();
    try std.testing.expect(linux_paths.static_lib != null);
    try std.testing.expect(linux_paths.system_libs.len > 0);
    try std.testing.expectEqual(ObjectFormat.elf, linux_result.linker.getObjectFormat());

    // macOS target
    const macos_result = try createTestLinker(allocator, Target{ .arch = .aarch64, .os = .macos, .abi = .none });
    defer destroyTestLinker(allocator, macos_result.linker, macos_result.diagnostics);

    const macos_paths = macos_result.linker.getRuntimeLibPaths();
    try std.testing.expect(macos_paths.static_lib != null);
    try std.testing.expectEqual(ObjectFormat.macho, macos_result.linker.getObjectFormat());

    // Windows target
    const windows_result = try createTestLinker(allocator, Target{ .arch = .x86_64, .os = .windows, .abi = .msvc });
    defer destroyTestLinker(allocator, windows_result.linker, windows_result.diagnostics);

    const windows_paths = windows_result.linker.getRuntimeLibPaths();
    try std.testing.expect(windows_paths.static_lib != null);
    try std.testing.expectEqual(ObjectFormat.coff, windows_result.linker.getObjectFormat());
}

// Test output path generation
test "Linker configuration: Output path generation" {
    const allocator = std.testing.allocator;

    // Linux (no extension)
    const linux_result = try createTestLinker(allocator, Target{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    defer destroyTestLinker(allocator, linux_result.linker, linux_result.diagnostics);

    const linux_output = try linux_result.linker.generateOutputPath("test.php");
    defer allocator.free(linux_output);
    try std.testing.expectEqualStrings("test", linux_output);

    // Windows (.exe extension)
    const windows_result = try createTestLinker(allocator, Target{ .arch = .x86_64, .os = .windows, .abi = .msvc });
    defer destroyTestLinker(allocator, windows_result.linker, windows_result.diagnostics);

    const windows_output = try windows_result.linker.generateOutputPath("test.php");
    defer allocator.free(windows_output);
    try std.testing.expectEqualStrings("test.exe", windows_output);
}

// ============================================================================
// isRuntimeFunction Tests
// ============================================================================

test "isRuntimeFunction: Correctly identifies runtime functions" {
    // Runtime functions start with "php_"
    try std.testing.expect(StaticLinker.isRuntimeFunction("php_value_create_int"));
    try std.testing.expect(StaticLinker.isRuntimeFunction("php_gc_retain"));
    try std.testing.expect(StaticLinker.isRuntimeFunction("php_array_get"));
    try std.testing.expect(StaticLinker.isRuntimeFunction("php_echo"));
    try std.testing.expect(StaticLinker.isRuntimeFunction("php_"));

    // Non-runtime functions
    try std.testing.expect(!StaticLinker.isRuntimeFunction("my_function"));
    try std.testing.expect(!StaticLinker.isRuntimeFunction("main"));
    try std.testing.expect(!StaticLinker.isRuntimeFunction(""));
    try std.testing.expect(!StaticLinker.isRuntimeFunction("PHP_VALUE")); // Case sensitive
    try std.testing.expect(!StaticLinker.isRuntimeFunction("_php_internal"));
}
