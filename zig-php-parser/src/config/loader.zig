const std = @import("std");

/// SyntaxMode enum for configuration
/// This is a separate definition to avoid circular dependencies
/// The main.zig file handles conversion to compiler.syntax_mode.SyntaxMode
pub const SyntaxMode = enum {
    /// PHP 风格: $var, $obj->prop, $obj->method()
    php,
    /// Go 风格: var, obj.prop, obj.method()
    go,

    /// Parse a syntax mode from a string
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

/// Configuration structure for zig-php
/// Loaded from .zigphp.json or zigphp.config.json files
/// Requirements: 12.1, 12.2, 12.3
pub const Config = struct {
    /// Syntax mode (php or go)
    syntax_mode: SyntaxMode = .php,
    /// List of extension paths to auto-load
    extensions: []const []const u8 = &.{},
    /// Include paths for file resolution
    include_paths: []const []const u8 = &.{},
    /// Error reporting level
    error_reporting: u32 = 0xFFFF,

    /// Free allocated memory
    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        for (self.extensions) |ext| {
            allocator.free(ext);
        }
        if (self.extensions.len > 0) {
            allocator.free(self.extensions);
        }

        for (self.include_paths) |path| {
            allocator.free(path);
        }
        if (self.include_paths.len > 0) {
            allocator.free(self.include_paths);
        }
    }
};

/// Configuration loader for zig-php
/// Loads configuration from JSON files
/// Requirements: 12.1, 12.2, 12.3
pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,

    /// Default config file names to search for
    pub const default_config_files = [_][]const u8{
        ".zigphp.json",
        "zigphp.config.json",
    };

    /// Initialize a new ConfigLoader
    pub fn init(allocator: std.mem.Allocator) ConfigLoader {
        return ConfigLoader{
            .allocator = allocator,
        };
    }

    /// Load configuration from a specific file path
    /// Returns default config if file not found
    pub fn load(self: *ConfigLoader, path: []const u8) !Config {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return Config{}; // Return default config
            }
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        if (file_size > 1024 * 1024) {
            return error.FileTooLarge;
        }

        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);

        return self.parseJson(content);
    }

    /// Load configuration from default locations
    /// Searches for .zigphp.json and zigphp.config.json in current directory
    pub fn loadDefault(self: *ConfigLoader) !Config {
        for (default_config_files) |filename| {
            const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    continue;
                }
                return err;
            };
            defer file.close();

            const file_size = try file.getEndPos();
            if (file_size > 1024 * 1024) {
                return error.FileTooLarge;
            }

            const content = try self.allocator.alloc(u8, file_size);
            defer self.allocator.free(content);
            _ = try file.readAll(content);

            return self.parseJson(content);
        }

        // No config file found, return default
        return Config{};
    }

    /// Parse JSON content into Config structure
    fn parseJson(self: *ConfigLoader, content: []const u8) !Config {
        var config = Config{};
        errdefer config.deinit(self.allocator);

        // Handle empty content
        if (content.len == 0) {
            return config;
        }

        // Parse JSON
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch {
            return error.InvalidJson;
        };
        defer parsed.deinit();

        const root = parsed.value;

        // Root must be an object
        if (root != .object) {
            return error.InvalidJson;
        }

        const obj = root.object;

        // Parse syntax mode
        if (obj.get("syntax")) |syntax_value| {
            if (syntax_value == .string) {
                if (SyntaxMode.fromString(syntax_value.string)) |mode| {
                    config.syntax_mode = mode;
                }
            }
        }

        // Parse extensions array
        if (obj.get("extensions")) |exts_value| {
            if (exts_value == .array) {
                var ext_list: std.ArrayListUnmanaged([]const u8) = .empty;
                errdefer {
                    for (ext_list.items) |item| {
                        self.allocator.free(item);
                    }
                    ext_list.deinit(self.allocator);
                }

                for (exts_value.array.items) |item| {
                    if (item == .string) {
                        const ext_copy = try self.allocator.dupe(u8, item.string);
                        try ext_list.append(self.allocator, ext_copy);
                    }
                }

                config.extensions = try ext_list.toOwnedSlice(self.allocator);
            }
        }

        // Parse include_paths array
        if (obj.get("include_paths")) |paths_value| {
            if (paths_value == .array) {
                var path_list: std.ArrayListUnmanaged([]const u8) = .empty;
                errdefer {
                    for (path_list.items) |item| {
                        self.allocator.free(item);
                    }
                    path_list.deinit(self.allocator);
                }

                for (paths_value.array.items) |item| {
                    if (item == .string) {
                        const path_copy = try self.allocator.dupe(u8, item.string);
                        try path_list.append(self.allocator, path_copy);
                    }
                }

                config.include_paths = try path_list.toOwnedSlice(self.allocator);
            }
        }

        // Parse error_reporting
        if (obj.get("error_reporting")) |err_value| {
            if (err_value == .integer) {
                config.error_reporting = @intCast(err_value.integer);
            }
        }

        return config;
    }

    /// Parse JSON from a string (convenience method for testing)
    pub fn parseFromString(self: *ConfigLoader, content: []const u8) !Config {
        return self.parseJson(content);
    }
};

/// Merged configuration with command line overrides
/// Requirements: 12.4
pub const MergedConfig = struct {
    /// Base configuration from file
    file_config: Config,
    /// Command line syntax mode override (null if not specified)
    cli_syntax_mode: ?SyntaxMode,
    /// Command line extensions to load
    cli_extensions: []const []const u8,

    /// Get the effective syntax mode (CLI takes precedence)
    pub fn getSyntaxMode(self: *const MergedConfig) SyntaxMode {
        return self.cli_syntax_mode orelse self.file_config.syntax_mode;
    }

    /// Get all extensions to load (CLI extensions added to file extensions)
    pub fn getExtensions(self: *const MergedConfig, allocator: std.mem.Allocator) ![]const []const u8 {
        const total_len = self.file_config.extensions.len + self.cli_extensions.len;
        if (total_len == 0) {
            return &.{};
        }

        var result = try allocator.alloc([]const u8, total_len);
        var i: usize = 0;

        // Add file extensions first
        for (self.file_config.extensions) |ext| {
            result[i] = ext;
            i += 1;
        }

        // Add CLI extensions
        for (self.cli_extensions) |ext| {
            result[i] = ext;
            i += 1;
        }

        return result;
    }

    /// Get include paths from file config
    pub fn getIncludePaths(self: *const MergedConfig) []const []const u8 {
        return self.file_config.include_paths;
    }

    /// Get error reporting level from file config
    pub fn getErrorReporting(self: *const MergedConfig) u32 {
        return self.file_config.error_reporting;
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "Config default values" {
    const config = Config{};
    try std.testing.expectEqual(SyntaxMode.php, config.syntax_mode);
    try std.testing.expectEqual(@as(usize, 0), config.extensions.len);
    try std.testing.expectEqual(@as(usize, 0), config.include_paths.len);
    try std.testing.expectEqual(@as(u32, 0xFFFF), config.error_reporting);
}

test "ConfigLoader init" {
    const loader = ConfigLoader.init(std.testing.allocator);
    _ = loader;
}

test "ConfigLoader parseJson empty object" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString("{}");
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(SyntaxMode.php, config.syntax_mode);
    try std.testing.expectEqual(@as(usize, 0), config.extensions.len);
}

test "ConfigLoader parseJson syntax mode php" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString(
        \\{"syntax": "php"}
    );
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(SyntaxMode.php, config.syntax_mode);
}

test "ConfigLoader parseJson syntax mode go" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString(
        \\{"syntax": "go"}
    );
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(SyntaxMode.go, config.syntax_mode);
}

test "ConfigLoader parseJson extensions array" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString(
        \\{"extensions": ["./ext1.so", "./ext2.so"]}
    );
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), config.extensions.len);
    try std.testing.expectEqualStrings("./ext1.so", config.extensions[0]);
    try std.testing.expectEqualStrings("./ext2.so", config.extensions[1]);
}

test "ConfigLoader parseJson include_paths array" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString(
        \\{"include_paths": ["./lib", "./vendor"]}
    );
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), config.include_paths.len);
    try std.testing.expectEqualStrings("./lib", config.include_paths[0]);
    try std.testing.expectEqualStrings("./vendor", config.include_paths[1]);
}

test "ConfigLoader parseJson error_reporting" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString(
        \\{"error_reporting": 32767}
    );
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 32767), config.error_reporting);
}

test "ConfigLoader parseJson full config" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString(
        \\{
        \\  "syntax": "go",
        \\  "extensions": ["./mysql.so", "./redis.so"],
        \\  "include_paths": ["./lib", "./vendor"],
        \\  "error_reporting": 32767
        \\}
    );
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(SyntaxMode.go, config.syntax_mode);
    try std.testing.expectEqual(@as(usize, 2), config.extensions.len);
    try std.testing.expectEqual(@as(usize, 2), config.include_paths.len);
    try std.testing.expectEqual(@as(u32, 32767), config.error_reporting);
}

test "ConfigLoader parseJson invalid syntax mode ignored" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString(
        \\{"syntax": "invalid"}
    );
    defer config.deinit(std.testing.allocator);

    // Invalid syntax mode should be ignored, default to php
    try std.testing.expectEqual(SyntaxMode.php, config.syntax_mode);
}

test "ConfigLoader parseJson empty content" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var config = try loader.parseFromString("");
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(SyntaxMode.php, config.syntax_mode);
}

test "ConfigLoader parseJson invalid json" {
    var loader = ConfigLoader.init(std.testing.allocator);
    const result = loader.parseFromString("not valid json");
    try std.testing.expectError(error.InvalidJson, result);
}

test "MergedConfig getSyntaxMode with CLI override" {
    const file_config = Config{ .syntax_mode = .php };
    const merged = MergedConfig{
        .file_config = file_config,
        .cli_syntax_mode = .go,
        .cli_extensions = &.{},
    };

    try std.testing.expectEqual(SyntaxMode.go, merged.getSyntaxMode());
}

test "MergedConfig getSyntaxMode without CLI override" {
    const file_config = Config{ .syntax_mode = .go };
    const merged = MergedConfig{
        .file_config = file_config,
        .cli_syntax_mode = null,
        .cli_extensions = &.{},
    };

    try std.testing.expectEqual(SyntaxMode.go, merged.getSyntaxMode());
}

test "MergedConfig getExtensions combines file and CLI" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var file_config = try loader.parseFromString(
        \\{"extensions": ["./file_ext.so"]}
    );
    defer file_config.deinit(std.testing.allocator);

    const cli_exts = [_][]const u8{"./cli_ext.so"};
    const merged = MergedConfig{
        .file_config = file_config,
        .cli_syntax_mode = null,
        .cli_extensions = &cli_exts,
    };

    const all_exts = try merged.getExtensions(std.testing.allocator);
    defer std.testing.allocator.free(all_exts);

    try std.testing.expectEqual(@as(usize, 2), all_exts.len);
    try std.testing.expectEqualStrings("./file_ext.so", all_exts[0]);
    try std.testing.expectEqualStrings("./cli_ext.so", all_exts[1]);
}


// ============================================================================
// Property 14: Configuration precedence
// **Validates: Requirements 12.2, 12.3, 12.4**
// For any configuration option specified in both config file and command line,
// the command line value SHALL take precedence over the config file value.
// ============================================================================

test "Feature: multi-syntax-extension-system, Property 14: CLI syntax mode overrides config file" {
    // Test that CLI syntax mode takes precedence over config file
    var loader = ConfigLoader.init(std.testing.allocator);

    // Config file specifies PHP mode
    var file_config = try loader.parseFromString(
        \\{"syntax": "php"}
    );
    defer file_config.deinit(std.testing.allocator);

    // CLI specifies Go mode
    const cli_syntax_mode: ?SyntaxMode = .go;

    // Apply precedence: CLI overrides config file
    const effective_mode = cli_syntax_mode orelse file_config.syntax_mode;

    // CLI should win
    try std.testing.expectEqual(SyntaxMode.go, effective_mode);
}

test "Feature: multi-syntax-extension-system, Property 14: config file used when CLI not specified" {
    // Test that config file value is used when CLI doesn't specify
    var loader = ConfigLoader.init(std.testing.allocator);

    // Config file specifies Go mode
    var file_config = try loader.parseFromString(
        \\{"syntax": "go"}
    );
    defer file_config.deinit(std.testing.allocator);

    // CLI doesn't specify syntax mode
    const cli_syntax_mode: ?SyntaxMode = null;

    // Apply precedence: use config file when CLI is null
    const effective_mode = cli_syntax_mode orelse file_config.syntax_mode;

    // Config file should be used
    try std.testing.expectEqual(SyntaxMode.go, effective_mode);
}

test "Feature: multi-syntax-extension-system, Property 14: default used when neither specified" {
    // Test that default is used when neither CLI nor config file specifies
    var loader = ConfigLoader.init(std.testing.allocator);

    // Config file doesn't specify syntax mode (uses default)
    var file_config = try loader.parseFromString("{}");
    defer file_config.deinit(std.testing.allocator);

    // CLI doesn't specify syntax mode
    const cli_syntax_mode: ?SyntaxMode = null;

    // Apply precedence
    const effective_mode = cli_syntax_mode orelse file_config.syntax_mode;

    // Default (PHP) should be used
    try std.testing.expectEqual(SyntaxMode.php, effective_mode);
}

test "Feature: multi-syntax-extension-system, Property 14: all syntax mode combinations" {
    // Test all combinations of CLI and config file syntax modes
    var loader = ConfigLoader.init(std.testing.allocator);

    const modes = [_]SyntaxMode{ .php, .go };
    const cli_options = [_]?SyntaxMode{ null, .php, .go };

    for (modes) |config_mode| {
        // Create config with this mode
        const config_json: []const u8 = if (config_mode == .php)
            "{\"syntax\": \"php\"}"
        else
            "{\"syntax\": \"go\"}";

        var file_config = try loader.parseFromString(config_json);
        defer file_config.deinit(std.testing.allocator);

        for (cli_options) |cli_mode| {
            const effective_mode = cli_mode orelse file_config.syntax_mode;

            if (cli_mode) |cli| {
                // CLI specified - should use CLI value
                try std.testing.expectEqual(cli, effective_mode);
            } else {
                // CLI not specified - should use config file value
                try std.testing.expectEqual(config_mode, effective_mode);
            }
        }
    }
}

test "Feature: multi-syntax-extension-system, Property 14: MergedConfig getSyntaxMode precedence" {
    var loader = ConfigLoader.init(std.testing.allocator);

    // Test with config file specifying PHP
    var file_config_php = try loader.parseFromString(
        \\{"syntax": "php"}
    );
    defer file_config_php.deinit(std.testing.allocator);

    // CLI override to Go
    const merged_with_override = MergedConfig{
        .file_config = file_config_php,
        .cli_syntax_mode = .go,
        .cli_extensions = &.{},
    };
    try std.testing.expectEqual(SyntaxMode.go, merged_with_override.getSyntaxMode());

    // No CLI override - use config file
    const merged_without_override = MergedConfig{
        .file_config = file_config_php,
        .cli_syntax_mode = null,
        .cli_extensions = &.{},
    };
    try std.testing.expectEqual(SyntaxMode.php, merged_without_override.getSyntaxMode());
}

test "Feature: multi-syntax-extension-system, Property 14: extensions from both sources" {
    var loader = ConfigLoader.init(std.testing.allocator);

    // Config file with extensions
    var file_config = try loader.parseFromString(
        \\{"extensions": ["./config_ext1.so", "./config_ext2.so"]}
    );
    defer file_config.deinit(std.testing.allocator);

    // CLI extensions
    const cli_exts = [_][]const u8{ "./cli_ext1.so", "./cli_ext2.so" };

    const merged = MergedConfig{
        .file_config = file_config,
        .cli_syntax_mode = null,
        .cli_extensions = &cli_exts,
    };

    // Get all extensions
    const all_exts = try merged.getExtensions(std.testing.allocator);
    defer std.testing.allocator.free(all_exts);

    // Should have all 4 extensions (2 from config + 2 from CLI)
    try std.testing.expectEqual(@as(usize, 4), all_exts.len);

    // Config extensions come first
    try std.testing.expectEqualStrings("./config_ext1.so", all_exts[0]);
    try std.testing.expectEqualStrings("./config_ext2.so", all_exts[1]);

    // CLI extensions come after
    try std.testing.expectEqualStrings("./cli_ext1.so", all_exts[2]);
    try std.testing.expectEqualStrings("./cli_ext2.so", all_exts[3]);
}

test "Feature: multi-syntax-extension-system, Property 14: include_paths from config" {
    var loader = ConfigLoader.init(std.testing.allocator);

    // Config file with include paths
    var file_config = try loader.parseFromString(
        \\{"include_paths": ["./lib", "./vendor", "./src"]}
    );
    defer file_config.deinit(std.testing.allocator);

    const merged = MergedConfig{
        .file_config = file_config,
        .cli_syntax_mode = null,
        .cli_extensions = &.{},
    };

    const paths = merged.getIncludePaths();
    try std.testing.expectEqual(@as(usize, 3), paths.len);
    try std.testing.expectEqualStrings("./lib", paths[0]);
    try std.testing.expectEqualStrings("./vendor", paths[1]);
    try std.testing.expectEqualStrings("./src", paths[2]);
}

test "Feature: multi-syntax-extension-system, Property 14: error_reporting from config" {
    var loader = ConfigLoader.init(std.testing.allocator);

    // Config file with error_reporting
    var file_config = try loader.parseFromString(
        \\{"error_reporting": 32767}
    );
    defer file_config.deinit(std.testing.allocator);

    const merged = MergedConfig{
        .file_config = file_config,
        .cli_syntax_mode = null,
        .cli_extensions = &.{},
    };

    try std.testing.expectEqual(@as(u32, 32767), merged.getErrorReporting());
}

test "Feature: multi-syntax-extension-system, Property 14: empty config with CLI override" {
    var loader = ConfigLoader.init(std.testing.allocator);

    // Empty config file
    var file_config = try loader.parseFromString("{}");
    defer file_config.deinit(std.testing.allocator);

    // CLI specifies Go mode
    const merged = MergedConfig{
        .file_config = file_config,
        .cli_syntax_mode = .go,
        .cli_extensions = &.{},
    };

    // CLI should override default
    try std.testing.expectEqual(SyntaxMode.go, merged.getSyntaxMode());
}

test "Feature: multi-syntax-extension-system, Property 14: full config with full CLI override" {
    var loader = ConfigLoader.init(std.testing.allocator);

    // Full config file
    var file_config = try loader.parseFromString(
        \\{
        \\  "syntax": "php",
        \\  "extensions": ["./config.so"],
        \\  "include_paths": ["./lib"],
        \\  "error_reporting": 1000
        \\}
    );
    defer file_config.deinit(std.testing.allocator);

    // CLI overrides
    const cli_exts = [_][]const u8{"./cli.so"};
    const merged = MergedConfig{
        .file_config = file_config,
        .cli_syntax_mode = .go,
        .cli_extensions = &cli_exts,
    };

    // Syntax mode: CLI wins
    try std.testing.expectEqual(SyntaxMode.go, merged.getSyntaxMode());

    // Extensions: combined
    const all_exts = try merged.getExtensions(std.testing.allocator);
    defer std.testing.allocator.free(all_exts);
    try std.testing.expectEqual(@as(usize, 2), all_exts.len);

    // Include paths: from config
    try std.testing.expectEqual(@as(usize, 1), merged.getIncludePaths().len);

    // Error reporting: from config
    try std.testing.expectEqual(@as(u32, 1000), merged.getErrorReporting());
}
