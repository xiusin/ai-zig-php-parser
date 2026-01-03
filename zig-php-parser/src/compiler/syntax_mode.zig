const std = @import("std");

/// Syntax directive prefix for file-level syntax mode specification
pub const SYNTAX_DIRECTIVE_PREFIX = "// @syntax:";
/// Alternative PHP-style syntax directive prefix
pub const SYNTAX_DIRECTIVE_PREFIX_PHP = "<?php // @syntax:";

/// Result of detecting syntax directive in a file
pub const SyntaxDirectiveResult = struct {
    /// The detected syntax mode, or null if no directive found
    mode: ?SyntaxMode,
    /// Whether a directive was found
    found: bool,
    /// The line number where the directive was found (0-indexed)
    line: usize,
};

/// Detect syntax directive at the beginning of source code
/// Supports both `// @syntax: go` and `<?php // @syntax: php` formats
/// Returns the detected mode or null if no directive found
pub fn detectSyntaxDirective(source: []const u8) SyntaxDirectiveResult {
    if (source.len == 0) {
        return .{ .mode = null, .found = false, .line = 0 };
    }

    // Skip leading whitespace and find the first non-whitespace content
    var pos: usize = 0;
    var line: usize = 0;
    
    while (pos < source.len) {
        // Skip whitespace
        while (pos < source.len and (source[pos] == ' ' or source[pos] == '\t' or source[pos] == '\r')) {
            pos += 1;
        }
        
        // Check for newline
        if (pos < source.len and source[pos] == '\n') {
            pos += 1;
            line += 1;
            continue;
        }
        
        // We found non-whitespace content
        break;
    }
    
    if (pos >= source.len) {
        return .{ .mode = null, .found = false, .line = 0 };
    }
    
    // Check for PHP-style directive: <?php // @syntax:
    if (std.mem.startsWith(u8, source[pos..], "<?php")) {
        var php_pos = pos + 5; // Skip "<?php"
        
        // Skip whitespace after <?php
        while (php_pos < source.len and (source[php_pos] == ' ' or source[php_pos] == '\t')) {
            php_pos += 1;
        }
        
        // Check for // @syntax:
        if (std.mem.startsWith(u8, source[php_pos..], "// @syntax:")) {
            const mode_start = php_pos + 11; // Skip "// @syntax:"
            if (parseSyntaxModeFromDirective(source[mode_start..])) |mode| {
                return .{ .mode = mode, .found = true, .line = line };
            }
        }
    }
    
    // Check for simple directive: // @syntax:
    if (std.mem.startsWith(u8, source[pos..], "// @syntax:")) {
        const mode_start = pos + 11; // Skip "// @syntax:"
        if (parseSyntaxModeFromDirective(source[mode_start..])) |mode| {
            return .{ .mode = mode, .found = true, .line = line };
        }
    }
    
    return .{ .mode = null, .found = false, .line = 0 };
}

/// Parse the syntax mode value from the directive content
/// Handles whitespace and extracts the mode name
fn parseSyntaxModeFromDirective(content: []const u8) ?SyntaxMode {
    if (content.len == 0) {
        return null;
    }
    
    // Skip leading whitespace
    var start: usize = 0;
    while (start < content.len and (content[start] == ' ' or content[start] == '\t')) {
        start += 1;
    }
    
    if (start >= content.len) {
        return null;
    }
    
    // Find end of mode name (until whitespace, newline, or end)
    var end = start;
    while (end < content.len and 
           content[end] != ' ' and content[end] != '\t' and 
           content[end] != '\n' and content[end] != '\r') {
        end += 1;
    }
    
    if (end == start) {
        return null;
    }
    
    const mode_str = content[start..end];
    return SyntaxMode.fromString(mode_str);
}

/// 语法模式枚举
/// Defines the syntax style for variable declarations and property access
pub const SyntaxMode = enum {
    /// PHP 风格: $var, $obj->prop, $obj->method()
    php,
    /// Go 风格: var, obj.prop, obj.method()
    go,

    /// Parse a syntax mode from a string
    /// Returns null if the string doesn't match any valid mode
    pub fn fromString(str: []const u8) ?SyntaxMode {
        if (std.mem.eql(u8, str, "php")) return .php;
        if (std.mem.eql(u8, str, "go")) return .go;
        return null;
    }

    /// Convert the syntax mode to its string representation
    pub fn toString(self: SyntaxMode) []const u8 {
        return switch (self) {
            .php => "php",
            .go => "go",
        };
    }
};

/// 语法模式配置
/// Configuration for syntax mode behavior
pub const SyntaxConfig = struct {
    /// The active syntax mode
    mode: SyntaxMode = .php,
    /// 是否允许混合模式（文件级别切换）
    allow_mixed_mode: bool = true,
    /// 错误消息使用的语法风格
    error_display_mode: SyntaxMode = .php,

    /// Initialize a SyntaxConfig with the specified mode
    /// Sets error_display_mode to match the specified mode
    pub fn init(mode: SyntaxMode) SyntaxConfig {
        return .{
            .mode = mode,
            .error_display_mode = mode,
        };
    }

    /// Check if the current mode is PHP
    pub fn isPhpMode(self: SyntaxConfig) bool {
        return self.mode == .php;
    }

    /// Check if the current mode is Go
    pub fn isGoMode(self: SyntaxConfig) bool {
        return self.mode == .go;
    }
};

// Unit tests
test "SyntaxMode.fromString parses valid modes" {
    try std.testing.expectEqual(SyntaxMode.php, SyntaxMode.fromString("php").?);
    try std.testing.expectEqual(SyntaxMode.go, SyntaxMode.fromString("go").?);
}

test "SyntaxMode.fromString returns null for invalid modes" {
    try std.testing.expect(SyntaxMode.fromString("invalid") == null);
    try std.testing.expect(SyntaxMode.fromString("") == null);
    try std.testing.expect(SyntaxMode.fromString("PHP") == null);
    try std.testing.expect(SyntaxMode.fromString("Go") == null);
    try std.testing.expect(SyntaxMode.fromString("rust") == null);
}

test "SyntaxMode.toString returns correct strings" {
    try std.testing.expectEqualStrings("php", SyntaxMode.php.toString());
    try std.testing.expectEqualStrings("go", SyntaxMode.go.toString());
}

test "SyntaxConfig default mode is PHP" {
    const config = SyntaxConfig{};
    try std.testing.expectEqual(SyntaxMode.php, config.mode);
    try std.testing.expectEqual(SyntaxMode.php, config.error_display_mode);
    try std.testing.expect(config.allow_mixed_mode);
}

test "SyntaxConfig.init sets mode and error_display_mode" {
    const php_config = SyntaxConfig.init(.php);
    try std.testing.expectEqual(SyntaxMode.php, php_config.mode);
    try std.testing.expectEqual(SyntaxMode.php, php_config.error_display_mode);

    const go_config = SyntaxConfig.init(.go);
    try std.testing.expectEqual(SyntaxMode.go, go_config.mode);
    try std.testing.expectEqual(SyntaxMode.go, go_config.error_display_mode);
}

test "SyntaxConfig.isPhpMode and isGoMode" {
    const php_config = SyntaxConfig.init(.php);
    try std.testing.expect(php_config.isPhpMode());
    try std.testing.expect(!php_config.isGoMode());

    const go_config = SyntaxConfig.init(.go);
    try std.testing.expect(!go_config.isPhpMode());
    try std.testing.expect(go_config.isGoMode());
}

// Syntax directive detection tests
test "detectSyntaxDirective detects Go mode directive" {
    const source = "// @syntax: go\n<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    try std.testing.expect(result.found);
    try std.testing.expectEqual(SyntaxMode.go, result.mode.?);
    try std.testing.expectEqual(@as(usize, 0), result.line);
}

test "detectSyntaxDirective detects PHP mode directive" {
    const source = "// @syntax: php\n<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    try std.testing.expect(result.found);
    try std.testing.expectEqual(SyntaxMode.php, result.mode.?);
}

test "detectSyntaxDirective detects PHP-style directive" {
    const source = "<?php // @syntax: go\necho 'hello';";
    const result = detectSyntaxDirective(source);
    try std.testing.expect(result.found);
    try std.testing.expectEqual(SyntaxMode.go, result.mode.?);
}

test "detectSyntaxDirective returns null for no directive" {
    const source = "<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    try std.testing.expect(!result.found);
    try std.testing.expect(result.mode == null);
}

test "detectSyntaxDirective handles whitespace before directive" {
    const source = "  \n  // @syntax: go\n<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    try std.testing.expect(result.found);
    try std.testing.expectEqual(SyntaxMode.go, result.mode.?);
}

test "detectSyntaxDirective returns null for invalid mode" {
    const source = "// @syntax: invalid\n<?php\necho 'hello';";
    const result = detectSyntaxDirective(source);
    try std.testing.expect(!result.found);
    try std.testing.expect(result.mode == null);
}

test "detectSyntaxDirective handles empty source" {
    const source = "";
    const result = detectSyntaxDirective(source);
    try std.testing.expect(!result.found);
    try std.testing.expect(result.mode == null);
}

test "detectSyntaxDirective handles whitespace-only source" {
    const source = "   \n\t\n  ";
    const result = detectSyntaxDirective(source);
    try std.testing.expect(!result.found);
    try std.testing.expect(result.mode == null);
}
