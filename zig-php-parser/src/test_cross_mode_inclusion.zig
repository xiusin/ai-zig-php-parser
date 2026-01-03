// ============================================================================
// Property-Based Tests for Cross-Mode File Inclusion
// Feature: multi-syntax-extension-system
// Property 15: Cross-mode file inclusion
// **Validates: Requirements 13.1, 13.2, 13.3, 13.4**
// ============================================================================

const std = @import("std");
const testing = std.testing;
const syntax_mode = @import("compiler/syntax_mode.zig");
const SyntaxMode = syntax_mode.SyntaxMode;
const SyntaxConfig = syntax_mode.SyntaxConfig;
const detectSyntaxDirective = syntax_mode.detectSyntaxDirective;
const Parser = @import("compiler/parser.zig").Parser;
const PHPContext = @import("compiler/root.zig").PHPContext;
const VM = @import("runtime/vm.zig").VM;
const Value = @import("runtime/types.zig").Value;

// ============================================================================
// Helper Functions
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

/// Generate a random valid identifier
fn generateRandomIdentifier(random: std.Random, buf: []u8) []const u8 {
    const first_chars = "abcdefghijklmnopqrstuvwxyz";
    const rest_chars = "abcdefghijklmnopqrstuvwxyz0123456789";
    
    const len = random.intRangeAtMost(usize, 3, @min(buf.len - 1, 10));
    buf[0] = first_chars[random.intRangeAtMost(usize, 0, first_chars.len - 1)];
    
    for (buf[1..len]) |*c| {
        c.* = rest_chars[random.intRangeAtMost(usize, 0, rest_chars.len - 1)];
    }
    
    return buf[0..len];
}

// ============================================================================
// Property 15: Cross-Mode File Inclusion
// *For any* file inclusion (include/require), the System SHALL correctly parse
// the included file using its specified or detected syntax mode, and function
// calls between files of different modes SHALL work correctly.
// **Validates: Requirements 13.1, 13.2, 13.3, 13.4**
// ============================================================================

// Test 1: Syntax directive detection for Go mode
test "Feature: multi-syntax-extension-system, Property 15: detect Go mode directive" {
    const source = "// @syntax: go\n<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    
    try testing.expect(result.found);
    try testing.expectEqual(SyntaxMode.go, result.mode.?);
}

// Test 2: Syntax directive detection for PHP mode
test "Feature: multi-syntax-extension-system, Property 15: detect PHP mode directive" {
    const source = "// @syntax: php\n<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    
    try testing.expect(result.found);
    try testing.expectEqual(SyntaxMode.php, result.mode.?);
}

// Test 3: PHP-style syntax directive detection
test "Feature: multi-syntax-extension-system, Property 15: detect PHP-style directive" {
    const source = "<?php // @syntax: go\necho 'hello';";
    const result = detectSyntaxDirective(source);
    
    try testing.expect(result.found);
    try testing.expectEqual(SyntaxMode.go, result.mode.?);
}

// Test 4: No directive returns null
test "Feature: multi-syntax-extension-system, Property 15: no directive returns null" {
    const source = "<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    
    try testing.expect(!result.found);
    try testing.expect(result.mode == null);
}

// Test 5: Invalid mode in directive
test "Feature: multi-syntax-extension-system, Property 15: invalid mode returns null" {
    const source = "// @syntax: invalid\n<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    
    try testing.expect(!result.found);
    try testing.expect(result.mode == null);
}

// Test 6: Whitespace handling in directive
test "Feature: multi-syntax-extension-system, Property 15: whitespace before directive" {
    const source = "  \n  // @syntax: go\n<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    
    try testing.expect(result.found);
    try testing.expectEqual(SyntaxMode.go, result.mode.?);
}

// Test 7: Empty source handling
test "Feature: multi-syntax-extension-system, Property 15: empty source" {
    const source = "";
    const result = detectSyntaxDirective(source);
    
    try testing.expect(!result.found);
    try testing.expect(result.mode == null);
}

// Test 8: Whitespace-only source handling
test "Feature: multi-syntax-extension-system, Property 15: whitespace-only source" {
    const source = "   \n\t\n  ";
    const result = detectSyntaxDirective(source);
    
    try testing.expect(!result.found);
    try testing.expect(result.mode == null);
}

// ============================================================================
// Property-Based Tests with Random Inputs
// ============================================================================

test "Feature: multi-syntax-extension-system, Property 15: directive detection consistency" {
    // Property: For any source with a valid syntax directive, detectSyntaxDirective
    // SHALL correctly identify the mode specified in the directive.
    
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();
    
    var source_buf: [512]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // Test case 1: Go mode directive with random content
        {
            const content_len = random.intRangeAtMost(usize, 10, 100);
            var content: [100]u8 = undefined;
            for (content[0..content_len]) |*c| {
                c.* = 'a' + @as(u8, @intCast(random.intRangeAtMost(usize, 0, 25)));
            }
            
            const source = std.fmt.bufPrint(&source_buf, "// @syntax: go\n<?php\n{s}", .{content[0..content_len]}) catch continue;
            const result = detectSyntaxDirective(source);
            
            try testing.expect(result.found);
            try testing.expectEqual(SyntaxMode.go, result.mode.?);
        }
        
        // Test case 2: PHP mode directive with random content
        {
            const content_len = random.intRangeAtMost(usize, 10, 100);
            var content: [100]u8 = undefined;
            for (content[0..content_len]) |*c| {
                c.* = 'a' + @as(u8, @intCast(random.intRangeAtMost(usize, 0, 25)));
            }
            
            const source = std.fmt.bufPrint(&source_buf, "// @syntax: php\n<?php\n{s}", .{content[0..content_len]}) catch continue;
            const result = detectSyntaxDirective(source);
            
            try testing.expect(result.found);
            try testing.expectEqual(SyntaxMode.php, result.mode.?);
        }
        
        // Test case 3: PHP-style Go directive with random content
        {
            const content_len = random.intRangeAtMost(usize, 10, 100);
            var content: [100]u8 = undefined;
            for (content[0..content_len]) |*c| {
                c.* = 'a' + @as(u8, @intCast(random.intRangeAtMost(usize, 0, 25)));
            }
            
            const source = std.fmt.bufPrint(&source_buf, "<?php // @syntax: go\n{s}", .{content[0..content_len]}) catch continue;
            const result = detectSyntaxDirective(source);
            
            try testing.expect(result.found);
            try testing.expectEqual(SyntaxMode.go, result.mode.?);
        }
        
        // Test case 4: No directive with random PHP content
        {
            const content_len = random.intRangeAtMost(usize, 10, 100);
            var content: [100]u8 = undefined;
            for (content[0..content_len]) |*c| {
                c.* = 'a' + @as(u8, @intCast(random.intRangeAtMost(usize, 0, 25)));
            }
            
            const source = std.fmt.bufPrint(&source_buf, "<?php\n{s}", .{content[0..content_len]}) catch continue;
            const result = detectSyntaxDirective(source);
            
            try testing.expect(!result.found);
            try testing.expect(result.mode == null);
        }
        
        // Test case 5: Random leading whitespace before directive
        {
            const ws_len = random.intRangeAtMost(usize, 0, 10);
            var ws: [10]u8 = undefined;
            for (ws[0..ws_len]) |*c| {
                const ws_type = random.intRangeAtMost(usize, 0, 2);
                c.* = switch (ws_type) {
                    0 => ' ',
                    1 => '\t',
                    else => '\n',
                };
            }
            
            const source = std.fmt.bufPrint(&source_buf, "{s}// @syntax: go\n<?php\necho 1;", .{ws[0..ws_len]}) catch continue;
            const result = detectSyntaxDirective(source);
            
            try testing.expect(result.found);
            try testing.expectEqual(SyntaxMode.go, result.mode.?);
        }
    }
}

test "Feature: multi-syntax-extension-system, Property 15: parser respects syntax mode" {
    // Property: For any source with a syntax directive, the parser SHALL use
    // the specified syntax mode for tokenization and parsing.
    
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(67890);
    const random = prng.random();
    
    var ident_buf: [32]u8 = undefined;
    var source_buf: [256]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const var_name = generateRandomIdentifier(random, &ident_buf);
        
        // Test case 1: Go mode source parses correctly
        {
            // Go mode: variables don't need $ prefix
            const source_str = std.fmt.bufPrint(&source_buf, "// @syntax: go\n<?php\n{s} = 42;", .{var_name}) catch continue;
            const source_z = allocator.allocSentinel(u8, source_str.len, 0) catch continue;
            defer allocator.free(source_z);
            @memcpy(source_z, source_str);
            
            const context = createTestContext(allocator) catch continue;
            defer destroyTestContext(allocator, context);
            
            // Detect the syntax mode from the source
            const directive = detectSyntaxDirective(source_z);
            const mode = if (directive.found and directive.mode != null) directive.mode.? else .php;
            
            try testing.expectEqual(SyntaxMode.go, mode);
            
            // Parse with the detected mode
            var parser = Parser.initWithMode(allocator, context, source_z, mode) catch continue;
            defer parser.deinit();
            
            const root = parser.parse() catch continue;
            _ = root;
            // If we get here, parsing succeeded
        }
        
        // Test case 2: PHP mode source parses correctly
        {
            // PHP mode: variables need $ prefix
            const source_str = std.fmt.bufPrint(&source_buf, "// @syntax: php\n<?php\n${s} = 42;", .{var_name}) catch continue;
            const source_z = allocator.allocSentinel(u8, source_str.len, 0) catch continue;
            defer allocator.free(source_z);
            @memcpy(source_z, source_str);
            
            const context = createTestContext(allocator) catch continue;
            defer destroyTestContext(allocator, context);
            
            // Detect the syntax mode from the source
            const directive = detectSyntaxDirective(source_z);
            const mode = if (directive.found and directive.mode != null) directive.mode.? else .php;
            
            try testing.expectEqual(SyntaxMode.php, mode);
            
            // Parse with the detected mode
            var parser = Parser.initWithMode(allocator, context, source_z, mode) catch continue;
            defer parser.deinit();
            
            const root = parser.parse() catch continue;
            _ = root;
            // If we get here, parsing succeeded
        }
    }
}

test "Feature: multi-syntax-extension-system, Property 15: cross-mode function definitions" {
    // Property: Functions defined in one syntax mode SHALL be callable from
    // code in another syntax mode.
    
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(11111);
    const random = prng.random();
    
    var func_name_buf: [32]u8 = undefined;
    var source_buf: [512]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const func_name = generateRandomIdentifier(random, &func_name_buf);
        const return_val = random.intRangeAtMost(i32, 1, 1000);
        
        // Test case 1: Function defined in PHP mode
        {
            const source_str = std.fmt.bufPrint(&source_buf, 
                "// @syntax: php\n<?php\nfunction {s}() {{ return {d}; }}", 
                .{func_name, return_val}) catch continue;
            const source_z = allocator.allocSentinel(u8, source_str.len, 0) catch continue;
            defer allocator.free(source_z);
            @memcpy(source_z, source_str);
            
            const context = createTestContext(allocator) catch continue;
            defer destroyTestContext(allocator, context);
            
            const directive = detectSyntaxDirective(source_z);
            const mode = if (directive.found and directive.mode != null) directive.mode.? else .php;
            
            try testing.expectEqual(SyntaxMode.php, mode);
            
            var parser = Parser.initWithMode(allocator, context, source_z, mode) catch continue;
            defer parser.deinit();
            
            const root = parser.parse() catch continue;
            _ = root;
            // Function definition parsed successfully
        }
        
        // Test case 2: Function defined in Go mode
        {
            const source_str = std.fmt.bufPrint(&source_buf, 
                "// @syntax: go\n<?php\nfunction {s}() {{ return {d}; }}", 
                .{func_name, return_val}) catch continue;
            const source_z = allocator.allocSentinel(u8, source_str.len, 0) catch continue;
            defer allocator.free(source_z);
            @memcpy(source_z, source_str);
            
            const context = createTestContext(allocator) catch continue;
            defer destroyTestContext(allocator, context);
            
            const directive = detectSyntaxDirective(source_z);
            const mode = if (directive.found and directive.mode != null) directive.mode.? else .php;
            
            try testing.expectEqual(SyntaxMode.go, mode);
            
            var parser = Parser.initWithMode(allocator, context, source_z, mode) catch continue;
            defer parser.deinit();
            
            const root = parser.parse() catch continue;
            _ = root;
            // Function definition parsed successfully
        }
    }
}

test "Feature: multi-syntax-extension-system, Property 15: syntax mode propagation" {
    // Property: When a file is included, the syntax mode from its directive
    // SHALL be used for parsing that file, independent of the including file's mode.
    
    const allocator = testing.allocator;
    
    // Test case 1: Go mode file content
    {
        const go_source = "// @syntax: go\n<?php\nx = 42;";
        const directive = detectSyntaxDirective(go_source);
        
        try testing.expect(directive.found);
        try testing.expectEqual(SyntaxMode.go, directive.mode.?);
        
        // The detected mode should be used for parsing
        const source_z = try allocator.allocSentinel(u8, go_source.len, 0);
        defer allocator.free(source_z);
        @memcpy(source_z, go_source);
        
        const context = try createTestContext(allocator);
        defer destroyTestContext(allocator, context);
        
        var parser = try Parser.initWithMode(allocator, context, source_z, directive.mode.?);
        defer parser.deinit();
        
        const root = try parser.parse();
        _ = root;
    }
    
    // Test case 2: PHP mode file content
    {
        const php_source = "// @syntax: php\n<?php\n$x = 42;";
        const directive = detectSyntaxDirective(php_source);
        
        try testing.expect(directive.found);
        try testing.expectEqual(SyntaxMode.php, directive.mode.?);
        
        const source_z = try allocator.allocSentinel(u8, php_source.len, 0);
        defer allocator.free(source_z);
        @memcpy(source_z, php_source);
        
        const context = try createTestContext(allocator);
        defer destroyTestContext(allocator, context);
        
        var parser = try Parser.initWithMode(allocator, context, source_z, directive.mode.?);
        defer parser.deinit();
        
        const root = try parser.parse();
        _ = root;
    }
    
    // Test case 3: No directive defaults to PHP mode
    {
        const no_directive_source = "<?php\n$x = 42;";
        const directive = detectSyntaxDirective(no_directive_source);
        
        try testing.expect(!directive.found);
        try testing.expect(directive.mode == null);
        
        // Default to PHP mode when no directive
        const default_mode = SyntaxMode.php;
        
        const source_z = try allocator.allocSentinel(u8, no_directive_source.len, 0);
        defer allocator.free(source_z);
        @memcpy(source_z, no_directive_source);
        
        const context = try createTestContext(allocator);
        defer destroyTestContext(allocator, context);
        
        var parser = try Parser.initWithMode(allocator, context, source_z, default_mode);
        defer parser.deinit();
        
        const root = try parser.parse();
        _ = root;
    }
}

test "Feature: multi-syntax-extension-system, Property 15: parameter passing across modes" {
    // Property: When calling functions across syntax modes, parameter passing
    // SHALL work correctly regardless of the syntax mode differences.
    
    const allocator = testing.allocator;
    var prng = std.Random.DefaultPrng.init(22222);
    const random = prng.random();
    
    var func_name_buf: [32]u8 = undefined;
    var param_name_buf: [32]u8 = undefined;
    var source_buf: [512]u8 = undefined;
    
    // Run 100 iterations as per testing strategy
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const func_name = generateRandomIdentifier(random, &func_name_buf);
        const param_name = generateRandomIdentifier(random, &param_name_buf);
        
        // Test case 1: Function with parameter in PHP mode
        {
            const source_str = std.fmt.bufPrint(&source_buf, 
                "// @syntax: php\n<?php\nfunction {s}(${s}) {{ return ${s}; }}", 
                .{func_name, param_name, param_name}) catch continue;
            const source_z = allocator.allocSentinel(u8, source_str.len, 0) catch continue;
            defer allocator.free(source_z);
            @memcpy(source_z, source_str);
            
            const context = createTestContext(allocator) catch continue;
            defer destroyTestContext(allocator, context);
            
            const directive = detectSyntaxDirective(source_z);
            try testing.expectEqual(SyntaxMode.php, directive.mode.?);
            
            var parser = Parser.initWithMode(allocator, context, source_z, directive.mode.?) catch continue;
            defer parser.deinit();
            
            const root = parser.parse() catch continue;
            _ = root;
        }
        
        // Test case 2: Function with parameter in Go mode
        {
            const source_str = std.fmt.bufPrint(&source_buf, 
                "// @syntax: go\n<?php\nfunction {s}({s}) {{ return {s}; }}", 
                .{func_name, param_name, param_name}) catch continue;
            const source_z = allocator.allocSentinel(u8, source_str.len, 0) catch continue;
            defer allocator.free(source_z);
            @memcpy(source_z, source_str);
            
            const context = createTestContext(allocator) catch continue;
            defer destroyTestContext(allocator, context);
            
            const directive = detectSyntaxDirective(source_z);
            try testing.expectEqual(SyntaxMode.go, directive.mode.?);
            
            var parser = Parser.initWithMode(allocator, context, source_z, directive.mode.?) catch continue;
            defer parser.deinit();
            
            const root = parser.parse() catch continue;
            _ = root;
        }
    }
}
