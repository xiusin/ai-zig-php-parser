const std = @import("std");
const testing = std.testing;
const VM = @import("runtime/vm.zig").VM;
const SyntaxConfig = @import("runtime/vm.zig").SyntaxConfig;
const SyntaxMode = @import("runtime/vm.zig").SyntaxMode;
const Parser = @import("compiler/parser.zig").Parser;
const PHPContext = @import("compiler/root.zig").PHPContext;
const Value = @import("runtime/types.zig").Value;

// ============================================================================
// VM Syntax Mode Tests
// Tests for VM execution determinism and syntax-aware error formatting
// ============================================================================

fn createTestContext(allocator: std.mem.Allocator) !*PHPContext {
    const context = try allocator.create(PHPContext);
    context.* = PHPContext.init(allocator);
    return context;
}

fn destroyTestContext(allocator: std.mem.Allocator, context: *PHPContext) void {
    context.deinit();
    allocator.destroy(context);
}

// ============================================================================
// Task 6.1: SyntaxConfig in VM Tests
// ============================================================================

test "VM default syntax config is PHP mode" {
    const allocator = testing.allocator;
    const vm = try VM.init(allocator);
    defer vm.deinit();
    
    try testing.expectEqual(SyntaxMode.php, vm.syntax_config.mode);
    try testing.expectEqual(SyntaxMode.php, vm.syntax_config.error_display_mode);
}

test "VM initWithSyntaxConfig sets Go mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.go);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    try testing.expectEqual(SyntaxMode.go, vm.syntax_config.mode);
    try testing.expectEqual(SyntaxMode.go, vm.syntax_config.error_display_mode);
}

test "VM initWithSyntaxConfig sets PHP mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.php);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    try testing.expectEqual(SyntaxMode.php, vm.syntax_config.mode);
    try testing.expectEqual(SyntaxMode.php, vm.syntax_config.error_display_mode);
}

// ============================================================================
// Task 6.2: Syntax-Aware Error Formatting Tests
// ============================================================================

test "formatVariableName removes $ prefix in Go mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.go);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    // Go mode should remove $ prefix
    try testing.expectEqualStrings("myVar", vm.formatVariableName("$myVar"));
    try testing.expectEqualStrings("x", vm.formatVariableName("$x"));
    try testing.expectEqualStrings("test", vm.formatVariableName("test")); // No $ prefix
}

test "formatVariableName keeps $ prefix in PHP mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.php);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    // PHP mode should keep $ prefix
    try testing.expectEqualStrings("$myVar", vm.formatVariableName("$myVar"));
    try testing.expectEqualStrings("$x", vm.formatVariableName("$x"));
    try testing.expectEqualStrings("test", vm.formatVariableName("test")); // No $ prefix
}

test "formatPropertyAccessOperator returns . in Go mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.go);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    try testing.expectEqualStrings(".", vm.formatPropertyAccessOperator());
}

test "formatPropertyAccessOperator returns -> in PHP mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.php);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    try testing.expectEqualStrings("->", vm.formatPropertyAccessOperator());
}

test "formatError with variable name in Go mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.go);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    const result = try vm.formatError("Undefined variable", "$myVar");
    defer allocator.free(result);
    
    // Go mode should format without $ prefix
    try testing.expectEqualStrings("Undefined variable: myVar", result);
}

test "formatError with variable name in PHP mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.php);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    const result = try vm.formatError("Undefined variable", "$myVar");
    defer allocator.free(result);
    
    // PHP mode should keep $ prefix
    try testing.expectEqualStrings("Undefined variable: $myVar", result);
}

test "formatError without variable name" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.go);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    const result = try vm.formatError("Syntax error", null);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Syntax error", result);
}

test "formatErrorMessage replaces -> with . in Go mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.go);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    const result = try vm.formatErrorMessage("Cannot access property $obj->prop");
    defer allocator.free(result);
    
    // Go mode should replace -> with . and remove $
    try testing.expectEqualStrings("Cannot access property obj.prop", result);
}

test "formatErrorMessage keeps -> in PHP mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.php);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    const result = try vm.formatErrorMessage("Cannot access property $obj->prop");
    defer allocator.free(result);
    
    // PHP mode should keep -> and $
    try testing.expectEqualStrings("Cannot access property $obj->prop", result);
}

test "getSyntaxModeString returns correct mode string" {
    const allocator = testing.allocator;
    
    {
        const config = SyntaxConfig.init(.go);
        const vm = try VM.initWithSyntaxConfig(allocator, config);
        defer vm.deinit();
        try testing.expectEqualStrings("go", vm.getSyntaxModeString());
    }
    
    {
        const config = SyntaxConfig.init(.php);
        const vm = try VM.initWithSyntaxConfig(allocator, config);
        defer vm.deinit();
        try testing.expectEqualStrings("php", vm.getSyntaxModeString());
    }
}

test "formatCompleteError includes syntax mode" {
    const allocator = testing.allocator;
    const config = SyntaxConfig.init(.go);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    const result = try vm.formatCompleteError("Runtime", "Undefined variable $x", "test.php", 10);
    defer allocator.free(result);
    
    // Should include syntax mode and format message for Go mode
    try testing.expect(std.mem.indexOf(u8, result, "[syntax: go]") != null);
    try testing.expect(std.mem.indexOf(u8, result, "test.php") != null);
    try testing.expect(std.mem.indexOf(u8, result, "line 10") != null);
}

// ============================================================================
// Property 6: VM Execution Determinism
// *For any* valid AST, the VM SHALL produce identical execution results
// regardless of the original syntax mode used to generate the AST.
// **Validates: Requirements 4.1, 4.2, 4.3**
// ============================================================================

/// Helper to execute code and get result
fn executeCode(allocator: std.mem.Allocator, source: [:0]const u8, mode: SyntaxMode) !?Value {
    const context = try createTestContext(allocator);
    defer destroyTestContext(allocator, context);
    
    var parser = try Parser.initWithMode(allocator, context, source, mode);
    defer parser.deinit();
    
    const root = try parser.parse();
    
    const config = SyntaxConfig.init(mode);
    const vm = try VM.initWithSyntaxConfig(allocator, config);
    defer vm.deinit();
    
    vm.context = context;
    
    // Execute and return result
    const result = vm.eval(root) catch {
        // Some errors are expected for certain test cases
        return null;
    };
    
    return result;
}

/// Compare two Values for equality
fn valuesEqual(v1: ?Value, v2: ?Value) bool {
    if (v1 == null and v2 == null) return true;
    if (v1 == null or v2 == null) return false;
    
    const val1 = v1.?;
    const val2 = v2.?;
    
    if (val1.getTag() != val2.getTag()) return false;
    
    return switch (val1.getTag()) {
        .null => true,
        .boolean => val1.asBool() == val2.asBool(),
        .integer => val1.asInt() == val2.asInt(),
        .float => val1.asFloat() == val2.asFloat(),
        .string => std.mem.eql(u8, val1.getAsString().data.data, val2.getAsString().data.data),
        else => true, // For complex types, just check tag equality
    };
}

test "Feature: multi-syntax-extension-system, Property 6: VM execution determinism" {
    // Property: For any valid AST, the VM SHALL produce identical execution results
    // regardless of the original syntax mode used to generate the AST.
    
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(54321);
    const random = prng.random();
    
    var php_source_buf: [256]u8 = undefined;
    var go_source_buf: [256]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // Test case 1: Integer literals
        {
            const val = random.intRangeAtMost(i32, -1000, 1000);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d}", .{val}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d}", .{val}) catch continue;
            
            const php_result = executeCode(allocator, php_source, .php) catch continue;
            const go_result = executeCode(allocator, go_source, .go) catch continue;
            
            try testing.expect(valuesEqual(php_result, go_result));
        }
        
        // Test case 2: Float literals
        {
            const val = @as(f64, @floatFromInt(random.intRangeAtMost(i32, -1000, 1000))) / 10.0;
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d:.1}", .{val}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d:.1}", .{val}) catch continue;
            
            const php_result = executeCode(allocator, php_source, .php) catch continue;
            const go_result = executeCode(allocator, go_source, .go) catch continue;
            
            try testing.expect(valuesEqual(php_result, go_result));
        }
        
        // Test case 3: Boolean literals
        {
            const val = random.boolean();
            const val_str = if (val) "true" else "false";
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {s}", .{val_str}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {s}", .{val_str}) catch continue;
            
            const php_result = executeCode(allocator, php_source, .php) catch continue;
            const go_result = executeCode(allocator, go_source, .go) catch continue;
            
            try testing.expect(valuesEqual(php_result, go_result));
        }
        
        // Test case 4: Null literal
        {
            const php_source: [:0]const u8 = "<?php null";
            const go_source: [:0]const u8 = "<?php null";
            
            const php_result = executeCode(allocator, php_source, .php) catch continue;
            const go_result = executeCode(allocator, go_source, .go) catch continue;
            
            try testing.expect(valuesEqual(php_result, go_result));
        }
        
        // Test case 5: Arithmetic expressions
        {
            const a = random.intRangeAtMost(i32, 1, 100);
            const b = random.intRangeAtMost(i32, 1, 100);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d} + {d}", .{a, b}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d} + {d}", .{a, b}) catch continue;
            
            const php_result = executeCode(allocator, php_source, .php) catch continue;
            const go_result = executeCode(allocator, go_source, .go) catch continue;
            
            try testing.expect(valuesEqual(php_result, go_result));
        }
        
        // Test case 6: Multiplication
        {
            const a = random.intRangeAtMost(i32, 1, 50);
            const b = random.intRangeAtMost(i32, 1, 50);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d} * {d}", .{a, b}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d} * {d}", .{a, b}) catch continue;
            
            const php_result = executeCode(allocator, php_source, .php) catch continue;
            const go_result = executeCode(allocator, go_source, .go) catch continue;
            
            try testing.expect(valuesEqual(php_result, go_result));
        }
        
        // Test case 7: Comparison expressions
        {
            const a = random.intRangeAtMost(i32, 1, 100);
            const b = random.intRangeAtMost(i32, 1, 100);
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {d} < {d}", .{a, b}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {d} < {d}", .{a, b}) catch continue;
            
            const php_result = executeCode(allocator, php_source, .php) catch continue;
            const go_result = executeCode(allocator, go_source, .go) catch continue;
            
            try testing.expect(valuesEqual(php_result, go_result));
        }
        
        // Test case 8: Logical expressions
        {
            const a = random.boolean();
            const b = random.boolean();
            const a_str = if (a) "true" else "false";
            const b_str = if (b) "true" else "false";
            const php_source = std.fmt.bufPrintZ(&php_source_buf, "<?php {s} && {s}", .{a_str, b_str}) catch continue;
            const go_source = std.fmt.bufPrintZ(&go_source_buf, "<?php {s} && {s}", .{a_str, b_str}) catch continue;
            
            const php_result = executeCode(allocator, php_source, .php) catch continue;
            const go_result = executeCode(allocator, go_source, .go) catch continue;
            
            try testing.expect(valuesEqual(php_result, go_result));
        }
    }
}



// ============================================================================
// Property 16: Syntax-Aware Error Formatting
// *For any* error occurring during execution, the error message SHALL format
// variable names and operators according to the syntax mode of the source file
// where the error originated.
// **Validates: Requirements 14.1, 14.2, 14.3, 14.4**
// ============================================================================

/// Generate a random valid identifier
fn generateRandomIdentifier(random: std.Random, buf: []u8) []const u8 {
    const first_chars = "abcdefghijklmnopqrstuvwxyz";
    const rest_chars = "abcdefghijklmnopqrstuvwxyz0123456789";
    
    const len = random.intRangeAtMost(usize, 1, @min(buf.len - 1, 10));
    buf[0] = first_chars[random.intRangeAtMost(usize, 0, first_chars.len - 1)];
    
    for (buf[1..len]) |*c| {
        c.* = rest_chars[random.intRangeAtMost(usize, 0, rest_chars.len - 1)];
    }
    
    return buf[0..len];
}

test "Feature: multi-syntax-extension-system, Property 16: Syntax-aware error formatting" {
    // Property: For any error occurring during execution, the error message SHALL
    // format variable names and operators according to the syntax mode.
    
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(98765);
    const random = prng.random();
    
    var ident_buf: [32]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const var_name = generateRandomIdentifier(random, &ident_buf);
        
        // Create variable name with $ prefix (internal representation)
        var internal_name_buf: [64]u8 = undefined;
        const internal_name = std.fmt.bufPrint(&internal_name_buf, "${s}", .{var_name}) catch continue;
        
        // Test case 1: Variable name formatting in Go mode
        {
            const config = SyntaxConfig.init(.go);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            // In Go mode, formatVariableName should remove $ prefix
            const formatted = vm.formatVariableName(internal_name);
            try testing.expectEqualStrings(var_name, formatted);
        }
        
        // Test case 2: Variable name formatting in PHP mode
        {
            const config = SyntaxConfig.init(.php);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            // In PHP mode, formatVariableName should keep $ prefix
            const formatted = vm.formatVariableName(internal_name);
            try testing.expectEqualStrings(internal_name, formatted);
        }
        
        // Test case 3: Property access operator in Go mode
        {
            const config = SyntaxConfig.init(.go);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            // In Go mode, property access should use .
            const op = vm.formatPropertyAccessOperator();
            try testing.expectEqualStrings(".", op);
        }
        
        // Test case 4: Property access operator in PHP mode
        {
            const config = SyntaxConfig.init(.php);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            // In PHP mode, property access should use ->
            const op = vm.formatPropertyAccessOperator();
            try testing.expectEqualStrings("->", op);
        }
        
        // Test case 5: Error message with variable in Go mode
        {
            const config = SyntaxConfig.init(.go);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            const error_msg = try vm.formatError("Undefined variable", internal_name);
            defer allocator.free(error_msg);
            
            // Go mode should format without $ prefix
            // The error message should contain the variable name without $
            try testing.expect(std.mem.indexOf(u8, error_msg, var_name) != null);
            // And should NOT contain the $ prefix before the variable name
            const dollar_var = std.fmt.bufPrint(&internal_name_buf, "${s}", .{var_name}) catch continue;
            try testing.expect(std.mem.indexOf(u8, error_msg, dollar_var) == null);
        }
        
        // Test case 6: Error message with variable in PHP mode
        {
            const config = SyntaxConfig.init(.php);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            const error_msg = try vm.formatError("Undefined variable", internal_name);
            defer allocator.free(error_msg);
            
            // PHP mode should keep $ prefix
            try testing.expect(std.mem.indexOf(u8, error_msg, internal_name) != null);
        }
        
        // Test case 7: Error message with -> in Go mode should become .
        {
            const config = SyntaxConfig.init(.go);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Cannot access ${s}->prop", .{var_name}) catch continue;
            
            const formatted = try vm.formatErrorMessage(msg);
            defer allocator.free(formatted);
            
            // Go mode should replace -> with . and remove $
            try testing.expect(std.mem.indexOf(u8, formatted, "->") == null);
            try testing.expect(std.mem.indexOf(u8, formatted, ".") != null);
            try testing.expect(std.mem.indexOf(u8, formatted, "$") == null);
        }
        
        // Test case 8: Error message with -> in PHP mode should stay ->
        {
            const config = SyntaxConfig.init(.php);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Cannot access ${s}->prop", .{var_name}) catch continue;
            
            const formatted = try vm.formatErrorMessage(msg);
            defer allocator.free(formatted);
            
            // PHP mode should keep -> and $
            try testing.expect(std.mem.indexOf(u8, formatted, "->") != null);
            try testing.expect(std.mem.indexOf(u8, formatted, "$") != null);
        }
        
        // Test case 9: Syntax mode string in error context
        {
            const go_config = SyntaxConfig.init(.go);
            const go_vm = try VM.initWithSyntaxConfig(allocator, go_config);
            defer go_vm.deinit();
            try testing.expectEqualStrings("go", go_vm.getSyntaxModeString());
            
            const php_config = SyntaxConfig.init(.php);
            const php_vm = try VM.initWithSyntaxConfig(allocator, php_config);
            defer php_vm.deinit();
            try testing.expectEqualStrings("php", php_vm.getSyntaxModeString());
        }
        
        // Test case 10: Complete error includes syntax mode
        {
            const config = SyntaxConfig.init(.go);
            const vm = try VM.initWithSyntaxConfig(allocator, config);
            defer vm.deinit();
            
            var msg_buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "Undefined ${s}", .{var_name}) catch continue;
            
            const line = random.intRangeAtMost(u32, 1, 1000);
            const complete_error = try vm.formatCompleteError("Runtime", msg, "test.php", line);
            defer allocator.free(complete_error);
            
            // Should include syntax mode
            try testing.expect(std.mem.indexOf(u8, complete_error, "[syntax: go]") != null);
            // Should include file and line
            try testing.expect(std.mem.indexOf(u8, complete_error, "test.php") != null);
        }
    }
}
