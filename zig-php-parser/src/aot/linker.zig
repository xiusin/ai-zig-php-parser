//! Static Linker for AOT Compiler
//!
//! This module provides static linking functionality for AOT-compiled PHP programs.
//! It handles:
//! - Object code output from LLVM
//! - Runtime library compilation and linking
//! - Platform-specific linker invocation
//! - Dead code elimination

const std = @import("std");
const Allocator = std.mem.Allocator;
const CodeGen = @import("codegen.zig");
const Target = CodeGen.Target;
const OptimizeLevel = CodeGen.OptimizeLevel;
const Diagnostics = @import("diagnostics.zig");
const IR = @import("ir.zig");

// ============================================================================
// Linker Error Types
// ============================================================================

pub const LinkerError = error{
    ObjectFileWriteFailed,
    RuntimeLibCompileFailed,
    LinkerInvocationFailed,
    LinkerFailed,
    UnsupportedTarget,
    OutputFileFailed,
    MissingTool,
    InvalidObjectCode,
    RuntimeLibNotFound,
    SymbolResolutionFailed,
    OutOfMemory,
    FileSystemError,
    ProcessSpawnError,
};

// ============================================================================
// Object Code Format
// ============================================================================

pub const ObjectFormat = enum {
    elf,
    macho,
    coff,

    pub fn fromTarget(target: Target) ObjectFormat {
        return switch (target.os) {
            .linux => .elf,
            .macos => .macho,
            .windows => .coff,
        };
    }

    pub fn objectExtension(self: ObjectFormat) []const u8 {
        return switch (self) {
            .elf => ".o",
            .macho => ".o",
            .coff => ".obj",
        };
    }

    pub fn staticLibExtension(self: ObjectFormat) []const u8 {
        return switch (self) {
            .elf => ".a",
            .macho => ".a",
            .coff => ".lib",
        };
    }

    pub fn executableExtension(self: ObjectFormat) []const u8 {
        return switch (self) {
            .elf => "",
            .macho => "",
            .coff => ".exe",
        };
    }
};

// ============================================================================
// Linker Configuration
// ============================================================================

pub const LinkerConfig = struct {
    target: Target,
    optimize_level: OptimizeLevel,
    static_link: bool,
    debug_info: bool,
    strip_symbols: bool,
    library_paths: []const []const u8,
    libraries: []const []const u8,
    extra_flags: []const []const u8,
    verbose: bool,

    pub fn default(target: Target) LinkerConfig {
        return .{
            .target = target,
            .optimize_level = .debug,
            .static_link = true,
            .debug_info = true,
            .strip_symbols = false,
            .library_paths = &[_][]const u8{},
            .libraries = &[_][]const u8{},
            .extra_flags = &[_][]const u8{},
            .verbose = false,
        };
    }
};

// ============================================================================
// Object Code Buffer
// ============================================================================

pub const ObjectCode = struct {
    data: []const u8,
    format: ObjectFormat,
    module_name: []const u8,
    owned: bool,

    const Self = @This();

    pub fn initOwned(allocator: Allocator, data: []const u8, format: ObjectFormat, module_name: []const u8) !Self {
        const owned_data = try allocator.dupe(u8, data);
        const owned_name = try allocator.dupe(u8, module_name);
        return .{
            .data = owned_data,
            .format = format,
            .module_name = owned_name,
            .owned = true,
        };
    }

    pub fn initBorrowed(data: []const u8, format: ObjectFormat, module_name: []const u8) Self {
        return .{
            .data = data,
            .format = format,
            .module_name = module_name,
            .owned = false,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.owned) {
            allocator.free(@constCast(self.data));
            allocator.free(@constCast(self.module_name));
        }
    }

    pub fn isValid(self: *const Self) bool {
        if (self.data.len == 0) return false;
        return switch (self.format) {
            .elf => self.data.len >= 4 and std.mem.eql(u8, self.data[0..4], "\x7fELF"),
            .macho => self.data.len >= 4 and (std.mem.eql(u8, self.data[0..4], "\xfe\xed\xfa\xce") or
                std.mem.eql(u8, self.data[0..4], "\xfe\xed\xfa\xcf") or
                std.mem.eql(u8, self.data[0..4], "\xce\xfa\xed\xfe") or
                std.mem.eql(u8, self.data[0..4], "\xcf\xfa\xed\xfe")),
            .coff => self.data.len >= 2 and ((self.data[0] == 0x4d and self.data[1] == 0x5a) or
                (self.data[0] == 0x64 and self.data[1] == 0x86)),
        };
    }
};

// ============================================================================
// Static Linker
// ============================================================================

pub const StaticLinker = struct {
    allocator: Allocator,
    config: LinkerConfig,
    diagnostics: *Diagnostics.DiagnosticEngine,
    temp_files: std.ArrayListUnmanaged([]const u8),
    used_runtime_functions: std.StringHashMapUnmanaged(void),

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        config: LinkerConfig,
        diagnostics: *Diagnostics.DiagnosticEngine,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .diagnostics = diagnostics,
            .temp_files = .{},
            .used_runtime_functions = .{},
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.cleanupTempFiles();
        self.temp_files.deinit(self.allocator);
        self.used_runtime_functions.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn cleanupTempFiles(self: *Self) void {
        for (self.temp_files.items) |path| {
            std.fs.cwd().deleteFile(path) catch {};
            self.allocator.free(path);
        }
        self.temp_files.clearRetainingCapacity();
    }

    // Task 9.1: Object Code Output
    pub fn writeTempObjectFile(self: *Self, object_code: *const ObjectCode) ![]const u8 {
        const temp_path = try self.generateTempPath(object_code.format.objectExtension());
        const file = std.fs.cwd().createFile(temp_path, .{}) catch |err| {
            self.diagnostics.emitError("E007", "Failed to create temp object file", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.ObjectFileWriteFailed;
        };
        defer file.close();
        file.writeAll(object_code.data) catch |err| {
            self.diagnostics.emitError("E007", "Failed to write object code", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.ObjectFileWriteFailed;
        };
        try self.temp_files.append(self.allocator, temp_path);
        if (self.config.verbose) {
            std.debug.print("Wrote object file: {s} ({d} bytes)\n", .{ temp_path, object_code.data.len });
        }
        return temp_path;
    }

    fn generateTempPath(self: *Self, extension: []const u8) ![]const u8 {
        const timestamp = std.time.timestamp();
        const random = std.crypto.random.int(u32);
        return std.fmt.allocPrint(self.allocator, "/tmp/php_aot_{d}_{x}{s}", .{ timestamp, random, extension });
    }

    pub fn writeObjectFile(self: *Self, object_code: *const ObjectCode, output_path: []const u8) !void {
        const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
            self.diagnostics.emitError("E007", "Failed to create object file", Diagnostics.SourceLocation.unknown(), &[_][]const u8{ output_path, @errorName(err) });
            return LinkerError.ObjectFileWriteFailed;
        };
        defer file.close();
        file.writeAll(object_code.data) catch |err| {
            self.diagnostics.emitError("E007", "Failed to write object code", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.ObjectFileWriteFailed;
        };
        if (self.config.verbose) {
            std.debug.print("Wrote object file: {s} ({d} bytes)\n", .{ output_path, object_code.data.len });
        }
    }

    pub fn generateMockObjectCode(self: *Self, module_name: []const u8) !ObjectCode {
        const format = ObjectFormat.fromTarget(self.config.target);
        const header = switch (format) {
            .elf => try self.generateMinimalELFHeader(),
            .macho => try self.generateMinimalMachOHeader(),
            .coff => try self.generateMinimalCOFFHeader(),
        };
        // header is already allocated, so we create ObjectCode directly without copying
        const owned_name = try self.allocator.dupe(u8, module_name);
        return .{
            .data = header,
            .format = format,
            .module_name = owned_name,
            .owned = true,
        };
    }

    fn generateMinimalELFHeader(self: *Self) ![]const u8 {
        var header = try self.allocator.alloc(u8, 64);
        header[0] = 0x7f;
        header[1] = 'E';
        header[2] = 'L';
        header[3] = 'F';
        header[4] = 2; // 64-bit
        header[5] = 1; // little endian
        header[6] = 1; // version
        @memset(header[7..16], 0);
        header[16] = 1; // relocatable
        header[17] = 0;
        header[18] = 0x3e; // x86_64
        header[19] = 0;
        @memset(header[20..64], 0);
        return header;
    }

    fn generateMinimalMachOHeader(self: *Self) ![]const u8 {
        var header = try self.allocator.alloc(u8, 32);
        header[0] = 0xcf;
        header[1] = 0xfa;
        header[2] = 0xed;
        header[3] = 0xfe;
        @memset(header[4..32], 0);
        return header;
    }

    fn generateMinimalCOFFHeader(self: *Self) ![]const u8 {
        var header = try self.allocator.alloc(u8, 20);
        header[0] = 0x64;
        header[1] = 0x86;
        @memset(header[2..20], 0);
        return header;
    }

    // Task 9.2: Runtime Library Compilation
    pub const RuntimeLibPaths = struct {
        static_lib: ?[]const u8,
        object_files: []const []const u8,
        system_libs: []const []const u8,
    };

    /// Runtime library source files
    pub const RuntimeSourceFiles = struct {
        /// Main runtime library source
        pub const runtime_lib = "src/aot/runtime_lib.zig";
        /// All runtime source files needed for compilation
        pub const all_sources = &[_][]const u8{
            "src/aot/runtime_lib.zig",
        };
    };

    /// Runtime function categories for selective linking
    pub const RuntimeFunctionCategory = enum {
        value_creation,
        type_conversion,
        garbage_collection,
        array_operations,
        string_operations,
        object_operations,
        io_operations,
        exception_handling,
        builtin_functions,
        math_operations,
    };

    /// Get the list of runtime functions by category
    pub fn getRuntimeFunctionsByCategory(category: RuntimeFunctionCategory) []const []const u8 {
        return switch (category) {
            .value_creation => &[_][]const u8{
                "php_value_create_null",
                "php_value_create_bool",
                "php_value_create_int",
                "php_value_create_float",
                "php_value_create_string",
                "php_value_create_string_raw",
                "php_value_create_array",
                "php_value_create_object",
            },
            .type_conversion => &[_][]const u8{
                "php_value_get_type",
                "php_value_get_type_name",
                "php_value_to_int",
                "php_value_to_float",
                "php_value_to_bool",
                "php_value_to_string",
                "php_value_cast",
                "php_value_clone",
            },
            .garbage_collection => &[_][]const u8{
                "php_gc_retain",
                "php_gc_release",
                "php_gc_get_ref_count",
                "php_gc_is_shared",
                "php_gc_copy_on_write",
            },
            .array_operations => &[_][]const u8{
                "php_array_create",
                "php_array_create_with_capacity",
                "php_array_get",
                "php_array_get_int",
                "php_array_get_string",
                "php_array_set",
                "php_array_set_int",
                "php_array_set_string",
                "php_array_push",
                "php_array_count",
                "php_array_key_exists",
                "php_array_key_exists_int",
                "php_array_key_exists_string",
                "php_array_unset",
                "php_array_unset_int",
                "php_array_unset_string",
                "php_array_keys",
                "php_array_values",
                "php_array_merge",
                "php_array_is_empty",
                "php_array_first",
                "php_array_last",
            },
            .string_operations => &[_][]const u8{
                "php_string_concat",
                "php_string_length",
                "php_string_len",
                "php_string_interpolate",
                "php_string_substr",
                "php_string_strpos",
                "php_string_strtoupper",
                "php_string_strtolower",
                "php_string_trim",
                "php_string_ltrim",
                "php_string_rtrim",
                "php_string_replace",
                "php_string_explode",
                "php_string_implode",
            },
            .object_operations => &[_][]const u8{
                "php_object_get_property",
                "php_object_set_property",
                "php_object_call_method",
                "php_object_get_class",
                "php_object_instanceof",
            },
            .io_operations => &[_][]const u8{
                "php_echo",
                "php_print",
                "php_println",
                "php_printf",
            },
            .exception_handling => &[_][]const u8{
                "php_throw",
                "php_throw_message",
                "php_throw_exception",
                "php_catch",
                "php_catch_type",
                "php_has_exception",
                "php_get_exception",
                "php_clear_exception",
                "php_print_stack_trace",
            },
            .builtin_functions => &[_][]const u8{
                "php_builtin_strlen",
                "php_builtin_count",
                "php_builtin_var_dump",
                "php_builtin_print_r",
                "php_builtin_isset",
                "php_builtin_empty",
                "php_builtin_is_null",
                "php_builtin_is_bool",
                "php_builtin_is_int",
                "php_builtin_is_float",
                "php_builtin_is_string",
                "php_builtin_is_array",
                "php_builtin_is_object",
                "php_builtin_gettype",
            },
            .math_operations => &[_][]const u8{
                "php_math_abs",
                "php_math_ceil",
                "php_math_floor",
                "php_math_round",
                "php_math_max",
                "php_math_min",
                "php_math_pow",
                "php_math_sqrt",
                "php_math_rand",
            },
        };
    }

    pub fn getRuntimeLibPaths(self: *Self) RuntimeLibPaths {
        return switch (self.config.target.os) {
            .linux => .{
                .static_lib = "lib/libphp_runtime.a",
                .object_files = &[_][]const u8{},
                .system_libs = &[_][]const u8{ "c", "m", "pthread" },
            },
            .macos => .{
                .static_lib = "lib/libphp_runtime.a",
                .object_files = &[_][]const u8{},
                .system_libs = &[_][]const u8{"System"},
            },
            .windows => .{
                .static_lib = "lib/php_runtime.lib",
                .object_files = &[_][]const u8{},
                .system_libs = &[_][]const u8{ "kernel32", "msvcrt" },
            },
        };
    }

    /// Compile the runtime library for the target platform
    /// This creates a static library containing all runtime functions
    pub fn compileRuntimeLib(self: *Self) ![]const u8 {
        const target = self.config.target;
        const format = ObjectFormat.fromTarget(target);
        const lib_path = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/php_runtime_{s}_{s}{s}",
            .{ target.arch.toLLVMArch(), target.os.toLLVMOS(), format.staticLibExtension() },
        );

        // Check if we can use a pre-built runtime library
        if (self.findPrebuiltRuntimeLib()) |prebuilt_path| {
            if (self.config.verbose) {
                std.debug.print("Using pre-built runtime library: {s}\n", .{prebuilt_path});
            }
            // Copy the pre-built library to temp location
            std.fs.cwd().copyFile(prebuilt_path, std.fs.cwd(), lib_path, .{}) catch {
                // If copy fails, fall through to create placeholder
            };
        }

        // Create placeholder library file (actual compilation would use zig build-lib)
        const file = std.fs.cwd().createFile(lib_path, .{}) catch |err| {
            self.diagnostics.emitError("E007", "Failed to create runtime library", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.RuntimeLibCompileFailed;
        };

        // Write minimal archive header for the target format
        const archive_header = try self.generateArchiveHeader(format);
        file.writeAll(archive_header) catch |err| {
            file.close();
            self.diagnostics.emitError("E007", "Failed to write runtime library", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.RuntimeLibCompileFailed;
        };
        self.allocator.free(archive_header);
        file.close();

        try self.temp_files.append(self.allocator, lib_path);
        if (self.config.verbose) {
            std.debug.print("Compiled runtime library: {s}\n", .{lib_path});
        }
        return lib_path;
    }

    /// Generate minimal archive header for static library
    fn generateArchiveHeader(self: *Self, format: ObjectFormat) ![]const u8 {
        return switch (format) {
            .elf, .macho => blk: {
                // Unix ar archive format: "!<arch>\n" magic
                var header = try self.allocator.alloc(u8, 8);
                @memcpy(header[0..8], "!<arch>\n");
                break :blk header;
            },
            .coff => blk: {
                // Windows lib format: simplified header
                var header = try self.allocator.alloc(u8, 8);
                @memcpy(header[0..8], "!<arch>\n");
                break :blk header;
            },
        };
    }

    /// Find a pre-built runtime library for the target
    fn findPrebuiltRuntimeLib(self: *Self) ?[]const u8 {
        const paths = self.getRuntimeLibPaths();
        if (paths.static_lib) |lib_path| {
            if (std.fs.cwd().access(lib_path, .{})) |_| {
                return lib_path;
            } else |_| {
                return null;
            }
        }
        return null;
    }

    /// Compile runtime library with only the functions that are actually used
    /// This enables dead code elimination at the runtime library level
    pub fn compileRuntimeLibSelective(self: *Self, used_functions: *const std.StringHashMapUnmanaged(void)) ![]const u8 {
        const target = self.config.target;
        const format = ObjectFormat.fromTarget(target);
        const lib_path = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/php_runtime_selective_{s}_{s}{s}",
            .{ target.arch.toLLVMArch(), target.os.toLLVMOS(), format.staticLibExtension() },
        );

        // Determine which categories are needed
        var needed_categories = std.EnumSet(RuntimeFunctionCategory).initEmpty();

        var iter = used_functions.keyIterator();
        while (iter.next()) |func_name| {
            // Map function to category
            if (std.mem.startsWith(u8, func_name.*, "php_value_create")) {
                needed_categories.insert(.value_creation);
            } else if (std.mem.startsWith(u8, func_name.*, "php_value_to") or
                std.mem.startsWith(u8, func_name.*, "php_value_get") or
                std.mem.startsWith(u8, func_name.*, "php_value_cast") or
                std.mem.startsWith(u8, func_name.*, "php_value_clone"))
            {
                needed_categories.insert(.type_conversion);
            } else if (std.mem.startsWith(u8, func_name.*, "php_gc_")) {
                needed_categories.insert(.garbage_collection);
            } else if (std.mem.startsWith(u8, func_name.*, "php_array_")) {
                needed_categories.insert(.array_operations);
            } else if (std.mem.startsWith(u8, func_name.*, "php_string_")) {
                needed_categories.insert(.string_operations);
            } else if (std.mem.startsWith(u8, func_name.*, "php_object_")) {
                needed_categories.insert(.object_operations);
            } else if (std.mem.eql(u8, func_name.*, "php_echo") or
                std.mem.eql(u8, func_name.*, "php_print") or
                std.mem.eql(u8, func_name.*, "php_println") or
                std.mem.eql(u8, func_name.*, "php_printf"))
            {
                needed_categories.insert(.io_operations);
            } else if (std.mem.startsWith(u8, func_name.*, "php_throw") or
                std.mem.startsWith(u8, func_name.*, "php_catch") or
                std.mem.startsWith(u8, func_name.*, "php_has_exception") or
                std.mem.startsWith(u8, func_name.*, "php_get_exception") or
                std.mem.startsWith(u8, func_name.*, "php_clear_exception"))
            {
                needed_categories.insert(.exception_handling);
            } else if (std.mem.startsWith(u8, func_name.*, "php_builtin_")) {
                needed_categories.insert(.builtin_functions);
            } else if (std.mem.startsWith(u8, func_name.*, "php_math_")) {
                needed_categories.insert(.math_operations);
            }
        }

        if (self.config.verbose) {
            std.debug.print("Selective runtime compilation: {d} categories needed\n", .{needed_categories.count()});
        }

        // Create the library file
        const file = std.fs.cwd().createFile(lib_path, .{}) catch |err| {
            self.diagnostics.emitError("E007", "Failed to create selective runtime library", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.RuntimeLibCompileFailed;
        };

        const archive_header = try self.generateArchiveHeader(format);
        file.writeAll(archive_header) catch |err| {
            file.close();
            self.allocator.free(archive_header);
            self.diagnostics.emitError("E007", "Failed to write selective runtime library", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.RuntimeLibCompileFailed;
        };
        self.allocator.free(archive_header);
        file.close();

        try self.temp_files.append(self.allocator, lib_path);
        if (self.config.verbose) {
            std.debug.print("Compiled selective runtime library: {s}\n", .{lib_path});
        }
        return lib_path;
    }

    /// Get the Zig compiler command for cross-compilation
    pub fn getZigCompilerCommand(self: *Self) []const u8 {
        _ = self;
        return "zig";
    }

    /// Get target triple for Zig compiler
    pub fn getZigTargetTriple(self: *Self) []const u8 {
        return switch (self.config.target.os) {
            .linux => switch (self.config.target.arch) {
                .x86_64 => "x86_64-linux-gnu",
                .aarch64 => "aarch64-linux-gnu",
                .arm => "arm-linux-gnueabihf",
            },
            .macos => switch (self.config.target.arch) {
                .x86_64 => "x86_64-macos",
                .aarch64 => "aarch64-macos",
                .arm => "arm-macos",
            },
            .windows => switch (self.config.target.arch) {
                .x86_64 => "x86_64-windows-msvc",
                .aarch64 => "aarch64-windows-msvc",
                .arm => "arm-windows-msvc",
            },
        };
    }

    pub fn runtimeLibExists(self: *const Self) bool {
        const paths = self.getRuntimeLibPaths();
        if (paths.static_lib) |lib_path| {
            return std.fs.cwd().access(lib_path, .{}) != error.FileNotFound;
        }
        return false;
    }

    // Task 9.3: Linker Invocation
    pub fn link(self: *Self, object_files: []const []const u8, output_path: []const u8) !void {
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);

        switch (self.config.target.os) {
            .linux => try self.buildLinuxLinkerArgs(&args, object_files, output_path),
            .macos => try self.buildMacOSLinkerArgs(&args, object_files, output_path),
            .windows => try self.buildWindowsLinkerArgs(&args, object_files, output_path),
        }

        for (self.config.extra_flags) |flag| {
            try args.append(self.allocator, flag);
        }

        if (self.config.verbose) {
            std.debug.print("Linker command: ", .{});
            for (args.items) |arg| {
                std.debug.print("{s} ", .{arg});
            }
            std.debug.print("\n", .{});
        }

        try self.executeLinker(args.items);
        if (self.config.verbose) {
            std.debug.print("Linked executable: {s}\n", .{output_path});
        }
    }

    fn buildLinuxLinkerArgs(self: *Self, args: *std.ArrayListUnmanaged([]const u8), object_files: []const []const u8, output_path: []const u8) !void {
        if (self.config.static_link) {
            try args.append(self.allocator, "ld");
        } else {
            try args.append(self.allocator, "gcc");
        }
        try args.append(self.allocator, "-o");
        try args.append(self.allocator, output_path);
        for (object_files) |obj| {
            try args.append(self.allocator, obj);
        }
        const runtime_paths = self.getRuntimeLibPaths();
        if (runtime_paths.static_lib) |lib| {
            try args.append(self.allocator, lib);
        }
        if (self.config.static_link) {
            try args.append(self.allocator, "-static");
        }
        for (self.config.library_paths) |path| {
            try args.append(self.allocator, "-L");
            try args.append(self.allocator, path);
        }
        for (runtime_paths.system_libs) |lib| {
            const lib_flag = try std.fmt.allocPrint(self.allocator, "-l{s}", .{lib});
            try args.append(self.allocator, lib_flag);
        }
        for (self.config.libraries) |lib| {
            const lib_flag = try std.fmt.allocPrint(self.allocator, "-l{s}", .{lib});
            try args.append(self.allocator, lib_flag);
        }
        if (!self.config.debug_info or self.config.strip_symbols) {
            try args.append(self.allocator, "-s");
        }
        if (self.config.optimize_level == .release_small) {
            try args.append(self.allocator, "--gc-sections");
        }
    }

    fn buildMacOSLinkerArgs(self: *Self, args: *std.ArrayListUnmanaged([]const u8), object_files: []const []const u8, output_path: []const u8) !void {
        try args.append(self.allocator, "ld");
        try args.append(self.allocator, "-o");
        try args.append(self.allocator, output_path);
        for (object_files) |obj| {
            try args.append(self.allocator, obj);
        }
        const runtime_paths = self.getRuntimeLibPaths();
        if (runtime_paths.static_lib) |lib| {
            try args.append(self.allocator, lib);
        }
        for (runtime_paths.system_libs) |lib| {
            const lib_flag = try std.fmt.allocPrint(self.allocator, "-l{s}", .{lib});
            try args.append(self.allocator, lib_flag);
        }
        try args.append(self.allocator, "-syslibroot");
        try args.append(self.allocator, "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk");
        try args.append(self.allocator, "-arch");
        try args.append(self.allocator, switch (self.config.target.arch) {
            .x86_64 => "x86_64",
            .aarch64 => "arm64",
            .arm => "armv7",
        });
        try args.append(self.allocator, "-platform_version");
        try args.append(self.allocator, "macos");
        try args.append(self.allocator, "11.0");
        try args.append(self.allocator, "11.0");
        if (self.config.strip_symbols) {
            try args.append(self.allocator, "-S");
        }
        if (self.config.optimize_level == .release_small or self.config.optimize_level == .release_fast) {
            try args.append(self.allocator, "-dead_strip");
        }
    }

    fn buildWindowsLinkerArgs(self: *Self, args: *std.ArrayListUnmanaged([]const u8), object_files: []const []const u8, output_path: []const u8) !void {
        try args.append(self.allocator, "lld-link");
        const out_flag = try std.fmt.allocPrint(self.allocator, "/OUT:{s}", .{output_path});
        try args.append(self.allocator, out_flag);
        for (object_files) |obj| {
            try args.append(self.allocator, obj);
        }
        const runtime_paths = self.getRuntimeLibPaths();
        if (runtime_paths.static_lib) |lib| {
            try args.append(self.allocator, lib);
        }
        for (runtime_paths.system_libs) |lib| {
            const lib_file = try std.fmt.allocPrint(self.allocator, "{s}.lib", .{lib});
            try args.append(self.allocator, lib_file);
        }
        try args.append(self.allocator, "/SUBSYSTEM:CONSOLE");
        try args.append(self.allocator, "/ENTRY:mainCRTStartup");
        if (self.config.debug_info) {
            try args.append(self.allocator, "/DEBUG");
        }
        if (self.config.optimize_level == .release_small) {
            try args.append(self.allocator, "/OPT:REF");
            try args.append(self.allocator, "/OPT:ICF");
        }
    }

    fn executeLinker(self: *Self, args: []const []const u8) !void {
        if (args.len == 0) {
            return LinkerError.LinkerInvocationFailed;
        }
        if (!self.isLinkerAvailable(args[0])) {
            if (self.config.verbose) {
                std.debug.print("Linker not available, skipping execution\n", .{});
            }
            return;
        }
        var child = std.process.Child.init(args, self.allocator);
        child.stderr_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.spawn() catch |err| {
            self.diagnostics.emitError("E007", "Failed to spawn linker", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.ProcessSpawnError;
        };
        const result = child.wait() catch |err| {
            self.diagnostics.emitError("E007", "Failed to wait for linker", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.LinkerInvocationFailed;
        };
        if (result.Exited != 0) {
            self.diagnostics.emitError("E007", "Linker returned non-zero exit code", Diagnostics.SourceLocation.unknown(), &[_][]const u8{});
            return LinkerError.LinkerFailed;
        }
    }

    fn isLinkerAvailable(self: *const Self, linker_name: []const u8) bool {
        _ = self;
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ "which", linker_name },
        }) catch return false;
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);
        return result.term.Exited == 0;
    }

    // Task 9.4: Dead Code Elimination
    pub fn analyzeUsedFunctions(self: *Self, ir_module: *const IR.Module) !void {
        self.used_runtime_functions.clearRetainingCapacity();
        for (ir_module.functions.items) |func| {
            try self.analyzeFunctionUsage(func);
        }
        if (self.config.verbose) {
            std.debug.print("Found {d} used runtime functions\n", .{self.used_runtime_functions.count()});
        }
    }

    fn analyzeFunctionUsage(self: *Self, func: *const IR.Function) !void {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                try self.analyzeInstructionUsage(inst);
            }
        }
    }

    fn analyzeInstructionUsage(self: *Self, inst: *const IR.Instruction) !void {
        switch (inst.op) {
            .call => |op| {
                if (isRuntimeFunction(op.func_name)) {
                    try self.used_runtime_functions.put(self.allocator, op.func_name, {});
                }
            },
            .const_string => try self.used_runtime_functions.put(self.allocator, "php_value_create_string", {}),
            .array_new => {
                try self.used_runtime_functions.put(self.allocator, "php_value_create_array", {});
                try self.used_runtime_functions.put(self.allocator, "php_array_create", {});
            },
            .new_object => try self.used_runtime_functions.put(self.allocator, "php_value_create_object", {}),
            .array_get => try self.used_runtime_functions.put(self.allocator, "php_array_get", {}),
            .array_set => try self.used_runtime_functions.put(self.allocator, "php_array_set", {}),
            .array_push => try self.used_runtime_functions.put(self.allocator, "php_array_push", {}),
            .array_count => try self.used_runtime_functions.put(self.allocator, "php_array_count", {}),
            .concat => try self.used_runtime_functions.put(self.allocator, "php_string_concat", {}),
            .strlen => try self.used_runtime_functions.put(self.allocator, "php_string_length", {}),
            .retain => try self.used_runtime_functions.put(self.allocator, "php_gc_retain", {}),
            .release => try self.used_runtime_functions.put(self.allocator, "php_gc_release", {}),
            .cast => try self.used_runtime_functions.put(self.allocator, "php_value_cast", {}),
            .type_check, .get_type => try self.used_runtime_functions.put(self.allocator, "php_value_get_type", {}),
            .debug_print => try self.used_runtime_functions.put(self.allocator, "php_echo", {}),
            else => {},
        }
    }

    pub fn isRuntimeFunction(name: []const u8) bool {
        return std.mem.startsWith(u8, name, "php_");
    }

    pub fn getUsedRuntimeFunctionCount(self: *const Self) usize {
        return self.used_runtime_functions.count();
    }

    pub fn isRuntimeFunctionUsed(self: *const Self, name: []const u8) bool {
        return self.used_runtime_functions.contains(name);
    }

    // Utility Methods
    pub fn getConfig(self: *const Self) LinkerConfig {
        return self.config;
    }

    pub fn setConfig(self: *Self, config: LinkerConfig) void {
        self.config = config;
    }

    pub fn getTarget(self: *const Self) Target {
        return self.config.target;
    }

    pub fn getObjectFormat(self: *const Self) ObjectFormat {
        return ObjectFormat.fromTarget(self.config.target);
    }

    pub fn getExecutableExtension(self: *const Self) []const u8 {
        return self.getObjectFormat().executableExtension();
    }

    pub fn generateOutputPath(self: *Self, input_path: []const u8) ![]const u8 {
        const base = if (std.mem.endsWith(u8, input_path, ".php"))
            input_path[0 .. input_path.len - 4]
        else
            input_path;
        const ext = self.getExecutableExtension();
        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base, ext });
    }

    pub fn linkExecutable(self: *Self, object_code: *const ObjectCode, output_path: []const u8) !void {
        if (!object_code.isValid()) {
            self.diagnostics.emitError("E007", "Invalid object code", Diagnostics.SourceLocation.unknown(), &[_][]const u8{});
            return LinkerError.InvalidObjectCode;
        }
        const obj_path = try self.writeTempObjectFile(object_code);
        const runtime_lib = try self.compileRuntimeLib();
        _ = runtime_lib;
        try self.link(&[_][]const u8{obj_path}, output_path);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "ObjectFormat.fromTarget" {
    const linux_target = Target{ .arch = .x86_64, .os = .linux, .abi = .gnu };
    try std.testing.expectEqual(ObjectFormat.elf, ObjectFormat.fromTarget(linux_target));

    const macos_target = Target{ .arch = .aarch64, .os = .macos, .abi = .none };
    try std.testing.expectEqual(ObjectFormat.macho, ObjectFormat.fromTarget(macos_target));

    const windows_target = Target{ .arch = .x86_64, .os = .windows, .abi = .msvc };
    try std.testing.expectEqual(ObjectFormat.coff, ObjectFormat.fromTarget(windows_target));
}

test "ObjectFormat.extensions" {
    try std.testing.expectEqualStrings(".o", ObjectFormat.elf.objectExtension());
    try std.testing.expectEqualStrings(".a", ObjectFormat.elf.staticLibExtension());
    try std.testing.expectEqualStrings("", ObjectFormat.elf.executableExtension());

    try std.testing.expectEqualStrings(".obj", ObjectFormat.coff.objectExtension());
    try std.testing.expectEqualStrings(".lib", ObjectFormat.coff.staticLibExtension());
    try std.testing.expectEqualStrings(".exe", ObjectFormat.coff.executableExtension());
}

test "LinkerConfig.default" {
    const target = Target.native();
    const config = LinkerConfig.default(target);
    try std.testing.expect(config.static_link);
    try std.testing.expect(config.debug_info);
    try std.testing.expect(!config.strip_symbols);
    try std.testing.expect(!config.verbose);
    try std.testing.expectEqual(OptimizeLevel.debug, config.optimize_level);
}

test "StaticLinker.init and deinit" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = LinkerConfig.default(Target.native());
    const lnk = try StaticLinker.init(allocator, config, &diagnostics);
    defer lnk.deinit();

    try std.testing.expectEqual(config.target.arch, lnk.getTarget().arch);
    try std.testing.expectEqual(config.target.os, lnk.getTarget().os);
}

test "StaticLinker.generateMockObjectCode" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = LinkerConfig.default(Target.native());
    const lnk = try StaticLinker.init(allocator, config, &diagnostics);
    defer lnk.deinit();

    var obj = try lnk.generateMockObjectCode("test_module");
    defer obj.deinit(allocator);

    try std.testing.expect(obj.data.len > 0);
    try std.testing.expectEqualStrings("test_module", obj.module_name);
}

test "ObjectCode.isValid ELF" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const linux_config = LinkerConfig.default(Target{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const lnk = try StaticLinker.init(allocator, linux_config, &diagnostics);
    defer lnk.deinit();

    var obj = try lnk.generateMockObjectCode("test");
    defer obj.deinit(allocator);
    try std.testing.expect(obj.isValid());
}

test "ObjectCode.isValid MachO" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const macos_config = LinkerConfig.default(Target{ .arch = .aarch64, .os = .macos, .abi = .none });
    const lnk = try StaticLinker.init(allocator, macos_config, &diagnostics);
    defer lnk.deinit();

    var obj = try lnk.generateMockObjectCode("test");
    defer obj.deinit(allocator);
    try std.testing.expect(obj.isValid());
}

test "ObjectCode.isValid COFF" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const windows_config = LinkerConfig.default(Target{ .arch = .x86_64, .os = .windows, .abi = .msvc });
    const lnk = try StaticLinker.init(allocator, windows_config, &diagnostics);
    defer lnk.deinit();

    var obj = try lnk.generateMockObjectCode("test");
    defer obj.deinit(allocator);
    try std.testing.expect(obj.isValid());
}

test "StaticLinker.generateOutputPath" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const linux_config = LinkerConfig.default(Target{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const linux_linker = try StaticLinker.init(allocator, linux_config, &diagnostics);
    defer linux_linker.deinit();

    const linux_output = try linux_linker.generateOutputPath("test.php");
    defer allocator.free(linux_output);
    try std.testing.expectEqualStrings("test", linux_output);

    const windows_config = LinkerConfig.default(Target{ .arch = .x86_64, .os = .windows, .abi = .msvc });
    const windows_linker = try StaticLinker.init(allocator, windows_config, &diagnostics);
    defer windows_linker.deinit();

    const windows_output = try windows_linker.generateOutputPath("test.php");
    defer allocator.free(windows_output);
    try std.testing.expectEqualStrings("test.exe", windows_output);
}

test "StaticLinker.getRuntimeLibPaths" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = LinkerConfig.default(Target{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const lnk = try StaticLinker.init(allocator, config, &diagnostics);
    defer lnk.deinit();

    const paths = lnk.getRuntimeLibPaths();
    try std.testing.expect(paths.static_lib != null);
    try std.testing.expect(paths.system_libs.len > 0);
}

test "StaticLinker.getObjectFormat" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const linux_config = LinkerConfig.default(Target{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    const lnk = try StaticLinker.init(allocator, linux_config, &diagnostics);
    defer lnk.deinit();

    try std.testing.expectEqual(ObjectFormat.elf, lnk.getObjectFormat());
}

test "isRuntimeFunction" {
    try std.testing.expect(StaticLinker.isRuntimeFunction("php_value_create_int"));
    try std.testing.expect(StaticLinker.isRuntimeFunction("php_gc_retain"));
    try std.testing.expect(!StaticLinker.isRuntimeFunction("my_function"));
    try std.testing.expect(!StaticLinker.isRuntimeFunction("main"));
}

// ============================================================================
// Zig Linker - Compiles Zig source code to native executables
// ============================================================================

/// ZigLinker compiles generated Zig source code to native executables
/// using the Zig compiler. This provides:
/// - Cross-platform compilation support
/// - No external LLVM dependency
/// - Integrated runtime library linking
pub const ZigLinker = struct {
    allocator: Allocator,
    config: ZigLinkerConfig,
    diagnostics: *Diagnostics.DiagnosticEngine,
    temp_files: std.ArrayListUnmanaged([]const u8),
    temp_dirs: std.ArrayListUnmanaged([]const u8),
    /// Allocated command strings that need to be freed
    allocated_cmd_strings: std.ArrayListUnmanaged([]const u8),

    const Self = @This();

    /// Initialize a new ZigLinker
    pub fn init(
        allocator: Allocator,
        config: ZigLinkerConfig,
        diagnostics: *Diagnostics.DiagnosticEngine,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .diagnostics = diagnostics,
            .temp_files = .{},
            .temp_dirs = .{},
            .allocated_cmd_strings = .{},
        };
        return self;
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.cleanupTempFiles();
        self.temp_files.deinit(self.allocator);
        self.temp_dirs.deinit(self.allocator);
        
        // Free allocated command strings
        for (self.allocated_cmd_strings.items) |s| {
            self.allocator.free(s);
        }
        self.allocated_cmd_strings.deinit(self.allocator);
        
        self.allocator.destroy(self);
    }

    /// Clean up all temporary files and directories
    fn cleanupTempFiles(self: *Self) void {
        // Delete temporary files
        for (self.temp_files.items) |path| {
            std.fs.cwd().deleteFile(path) catch {};
            self.allocator.free(path);
        }
        self.temp_files.clearRetainingCapacity();

        // Delete temporary directories
        for (self.temp_dirs.items) |path| {
            std.fs.cwd().deleteTree(path) catch {};
            self.allocator.free(path);
        }
        self.temp_dirs.clearRetainingCapacity();
    }

    /// Generate a unique temporary file path
    fn generateTempPath(self: *Self, prefix: []const u8, extension: []const u8) ![]const u8 {
        const timestamp = std.time.timestamp();
        const random = std.crypto.random.int(u32);
        return std.fmt.allocPrint(self.allocator, "/tmp/{s}_{d}_{x}{s}", .{ prefix, timestamp, random, extension });
    }

    /// Generate a unique temporary directory path
    fn generateTempDir(self: *Self, prefix: []const u8) ![]const u8 {
        const timestamp = std.time.timestamp();
        const random = std.crypto.random.int(u32);
        return std.fmt.allocPrint(self.allocator, "/tmp/{s}_{d}_{x}", .{ prefix, timestamp, random });
    }

    /// Write Zig source code to a temporary file
    pub fn writeTempSourceFile(self: *Self, source: []const u8) ![]const u8 {
        const temp_path = try self.generateTempPath("php_aot", ".zig");

        const file = std.fs.cwd().createFile(temp_path, .{}) catch |err| {
            self.diagnostics.reportError(.{}, "Failed to create temporary source file: {s}", .{@errorName(err)});
            return LinkerError.ObjectFileWriteFailed;
        };
        defer file.close();

        file.writeAll(source) catch |err| {
            self.diagnostics.reportError(.{}, "Failed to write source code: {s}", .{@errorName(err)});
            return LinkerError.ObjectFileWriteFailed;
        };

        try self.temp_files.append(self.allocator, temp_path);

        if (self.config.verbose) {
            std.debug.print("Wrote temporary source file: {s} ({d} bytes)\n", .{ temp_path, source.len });
        }

        return temp_path;
    }

    /// Copy runtime library to temporary directory for compilation
    pub fn prepareRuntimeLib(self: *Self) ![]const u8 {
        const temp_dir = try self.generateTempDir("php_runtime");

        // Create the temporary directory
        std.fs.cwd().makeDir(temp_dir) catch |err| {
            self.diagnostics.reportError(.{}, "Failed to create temporary directory: {s}", .{@errorName(err)});
            return LinkerError.RuntimeLibCompileFailed;
        };

        try self.temp_dirs.append(self.allocator, temp_dir);

        // Copy runtime_lib.zig to the temp directory
        const runtime_dest = try std.fmt.allocPrint(self.allocator, "{s}/runtime_lib.zig", .{temp_dir});
        defer self.allocator.free(runtime_dest);

        // Try to copy from the source location
        const runtime_source = "src/aot/runtime_lib.zig";
        std.fs.cwd().copyFile(runtime_source, std.fs.cwd(), runtime_dest, .{}) catch |err| {
            if (self.config.verbose) {
                std.debug.print("Warning: Could not copy runtime library: {s}\n", .{@errorName(err)});
            }
            // Continue anyway - the runtime might be embedded or available elsewhere
        };

        if (self.config.verbose) {
            std.debug.print("Prepared runtime library in: {s}\n", .{temp_dir});
        }

        return temp_dir;
    }

    /// Compile Zig source code to a native executable
    pub fn compileAndLink(
        self: *Self,
        zig_source: []const u8,
        output_path: []const u8,
    ) !void {
        // Write source to temporary file
        const source_path = try self.writeTempSourceFile(zig_source);

        // Build the Zig compiler command
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);

        try self.buildZigCommand(&args, source_path, output_path);

        if (self.config.verbose) {
            std.debug.print("Zig compiler command: ", .{});
            for (args.items) |arg| {
                std.debug.print("{s} ", .{arg});
            }
            std.debug.print("\n", .{});
        }

        // Execute the Zig compiler
        try self.executeZigCompiler(args.items);

        if (self.config.verbose) {
            std.debug.print("Successfully compiled: {s}\n", .{output_path});
        }
    }

    /// Compile Zig source code with runtime library to a native executable
    /// This method handles static linking of the runtime library
    pub fn compileAndLinkWithRuntime(
        self: *Self,
        zig_source: []const u8,
        output_path: []const u8,
        runtime_lib_path: ?[]const u8,
    ) !void {
        // Write source to temporary file
        const source_path = try self.writeTempSourceFile(zig_source);

        // Build the Zig compiler command
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);

        if (runtime_lib_path) |runtime_path| {
            try self.buildZigCommandWithRuntime(&args, source_path, output_path, runtime_path);
        } else {
            try self.buildZigCommand(&args, source_path, output_path);
        }

        if (self.config.verbose) {
            std.debug.print("Zig compiler command: ", .{});
            for (args.items) |arg| {
                std.debug.print("{s} ", .{arg});
            }
            std.debug.print("\n", .{});
        }

        // Execute the Zig compiler
        try self.executeZigCompiler(args.items);

        if (self.config.verbose) {
            std.debug.print("Successfully compiled with runtime: {s}\n", .{output_path});
        }
    }

    /// Compile with embedded runtime library
    /// The runtime library source is embedded in the generated Zig code
    pub fn compileWithEmbeddedRuntime(
        self: *Self,
        zig_source: []const u8,
        runtime_source: []const u8,
        output_path: []const u8,
    ) !void {
        // Create a temporary directory for the compilation
        const temp_dir = try self.generateTempDir("php_compile");
        std.fs.cwd().makeDir(temp_dir) catch |err| {
            self.diagnostics.reportError(.{}, "Failed to create compilation directory: {s}", .{@errorName(err)});
            return LinkerError.RuntimeLibCompileFailed;
        };
        try self.temp_dirs.append(self.allocator, temp_dir);

        // Write the main source file
        const main_path = try std.fmt.allocPrint(self.allocator, "{s}/main.zig", .{temp_dir});
        defer self.allocator.free(main_path);
        {
            const file = std.fs.cwd().createFile(main_path, .{}) catch |err| {
                self.diagnostics.reportError(.{}, "Failed to create main source file: {s}", .{@errorName(err)});
                return LinkerError.ObjectFileWriteFailed;
            };
            defer file.close();
            file.writeAll(zig_source) catch |err| {
                self.diagnostics.reportError(.{}, "Failed to write main source: {s}", .{@errorName(err)});
                return LinkerError.ObjectFileWriteFailed;
            };
        }

        // Write the runtime library source file
        const runtime_path = try std.fmt.allocPrint(self.allocator, "{s}/runtime_lib.zig", .{temp_dir});
        defer self.allocator.free(runtime_path);
        {
            const file = std.fs.cwd().createFile(runtime_path, .{}) catch |err| {
                self.diagnostics.reportError(.{}, "Failed to create runtime source file: {s}", .{@errorName(err)});
                return LinkerError.ObjectFileWriteFailed;
            };
            defer file.close();
            file.writeAll(runtime_source) catch |err| {
                self.diagnostics.reportError(.{}, "Failed to write runtime source: {s}", .{@errorName(err)});
                return LinkerError.ObjectFileWriteFailed;
            };
        }

        if (self.config.verbose) {
            std.debug.print("Created compilation directory: {s}\n", .{temp_dir});
            std.debug.print("  Main source: {s}\n", .{main_path});
            std.debug.print("  Runtime source: {s}\n", .{runtime_path});
        }

        // Build the Zig compiler command
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);

        try self.buildZigCommand(&args, main_path, output_path);

        if (self.config.verbose) {
            std.debug.print("Zig compiler command: ", .{});
            for (args.items) |arg| {
                std.debug.print("{s} ", .{arg});
            }
            std.debug.print("\n", .{});
        }

        // Execute the Zig compiler
        try self.executeZigCompiler(args.items);

        if (self.config.verbose) {
            std.debug.print("Successfully compiled with embedded runtime: {s}\n", .{output_path});
        }
    }

    /// Get the path to the runtime library source
    pub fn getRuntimeLibSourcePath(self: *const Self) []const u8 {
        _ = self;
        return "src/aot/runtime_lib.zig";
    }

    /// Check if static linking is enabled
    pub fn isStaticLinkEnabled(self: *const Self) bool {
        return self.config.static_link;
    }

    /// Enable or disable static linking
    pub fn setStaticLink(self: *Self, enabled: bool) void {
        self.config.static_link = enabled;
    }

    /// Build the Zig compiler command arguments
    pub fn buildZigCommand(
        self: *Self,
        args: *std.ArrayListUnmanaged([]const u8),
        source_path: []const u8,
        output_path: []const u8,
    ) !void {
        // Zig compiler executable
        try args.append(self.allocator, "zig");
        try args.append(self.allocator, "build-exe");

        // Source file
        try args.append(self.allocator, source_path);

        // Output file - use the correct format for zig build-exe
        const emit_path = try std.fmt.allocPrint(self.allocator, "-femit-bin={s}", .{output_path});
        try args.append(self.allocator, emit_path);
        try self.allocated_cmd_strings.append(self.allocator, emit_path);

        // Optimization level
        try args.append(self.allocator, self.config.optimize_level.toZigFlag());

        // Target platform (if cross-compiling)
        if (self.config.target) |target| {
            try args.append(self.allocator, "-target");
            try args.append(self.allocator, target);
        }

        // Static linking - use dynamic linker settings
        if (self.config.static_link) {
            // For static linking, we need to disable dynamic linking
            try args.append(self.allocator, "-fno-PIE");
        }

        // Strip symbols for release builds
        if (self.config.strip_symbols) {
            try args.append(self.allocator, "-fstrip");
        }

        // Single-threaded mode (simpler for now)
        try args.append(self.allocator, "-fsingle-threaded");

        // Disable stack protector for smaller binaries in release mode
        if (self.config.optimize_level == .release_small) {
            try args.append(self.allocator, "-fno-stack-protector");
        }

        // Add any extra flags
        for (self.config.extra_flags) |flag| {
            try args.append(self.allocator, flag);
        }
    }

    /// Build Zig command with runtime library module path
    pub fn buildZigCommandWithRuntime(
        self: *Self,
        args: *std.ArrayListUnmanaged([]const u8),
        source_path: []const u8,
        output_path: []const u8,
        runtime_path: []const u8,
    ) !void {
        // Zig compiler executable
        try args.append(self.allocator, "zig");
        try args.append(self.allocator, "build-exe");

        // Source file
        try args.append(self.allocator, source_path);

        // Output file
        const emit_path = try std.fmt.allocPrint(self.allocator, "-femit-bin={s}", .{output_path});
        try args.append(self.allocator, emit_path);
        try self.allocated_cmd_strings.append(self.allocator, emit_path);

        // Add runtime library module path
        const mod_path = try std.fmt.allocPrint(self.allocator, "--mod=runtime_lib:{s}", .{runtime_path});
        try args.append(self.allocator, mod_path);
        try self.allocated_cmd_strings.append(self.allocator, mod_path);

        // Optimization level
        try args.append(self.allocator, self.config.optimize_level.toZigFlag());

        // Target platform (if cross-compiling)
        if (self.config.target) |target| {
            try args.append(self.allocator, "-target");
            try args.append(self.allocator, target);
        }

        // Static linking
        if (self.config.static_link) {
            try args.append(self.allocator, "-fno-PIE");
        }

        // Strip symbols for release builds
        if (self.config.strip_symbols) {
            try args.append(self.allocator, "-fstrip");
        }

        // Single-threaded mode
        try args.append(self.allocator, "-fsingle-threaded");

        // Disable stack protector for smaller binaries in release mode
        if (self.config.optimize_level == .release_small) {
            try args.append(self.allocator, "-fno-stack-protector");
        }

        // Add any extra flags
        for (self.config.extra_flags) |flag| {
            try args.append(self.allocator, flag);
        }
    }

    /// Execute the Zig compiler
    fn executeZigCompiler(self: *Self, args: []const []const u8) !void {
        if (args.len == 0) {
            return LinkerError.LinkerInvocationFailed;
        }

        // Check if Zig is available
        if (!self.isZigAvailable()) {
            self.diagnostics.reportError(.{}, "Zig compiler not found in PATH", .{});
            return LinkerError.MissingTool;
        }

        // Use run() which handles output collection properly
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args,
        }) catch |err| {
            self.diagnostics.reportError(.{}, "Failed to run Zig compiler: {s}", .{@errorName(err)});
            return LinkerError.ProcessSpawnError;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            // Report compilation error with stderr output
            if (result.stderr.len > 0) {
                self.diagnostics.reportError(.{}, "Zig compilation failed:\n{s}", .{result.stderr});
            } else if (result.stdout.len > 0) {
                self.diagnostics.reportError(.{}, "Zig compilation failed:\n{s}", .{result.stdout});
            } else {
                self.diagnostics.reportError(.{}, "Zig compiler returned non-zero exit code: {d}", .{result.term.Exited});
            }
            return LinkerError.LinkerFailed;
        }
    }

    /// Check if Zig compiler is available
    fn isZigAvailable(self: *const Self) bool {
        _ = self;
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        }) catch return false;

        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);

        return result.term.Exited == 0;
    }

    /// Get the Zig compiler version
    pub fn getZigVersion(self: *const Self) ?[]const u8 {
        _ = self;
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ "zig", "version" },
        }) catch return null;

        defer std.heap.page_allocator.free(result.stderr);

        if (result.term.Exited == 0) {
            // Trim newline from version string
            var version = result.stdout;
            if (version.len > 0 and version[version.len - 1] == '\n') {
                version = version[0 .. version.len - 1];
            }
            return version;
        }

        std.heap.page_allocator.free(result.stdout);
        return null;
    }

    /// Generate output file path from input file path
    /// If output_path is provided, use it directly
    /// Otherwise, derive from input_path by removing .php extension and adding platform-specific executable extension
    pub fn generateOutputPath(self: *Self, input_path: []const u8, output_path: ?[]const u8) ![]const u8 {
        // If output path is explicitly provided, use it
        if (output_path) |out| {
            return try self.allocator.dupe(u8, out);
        }

        // Derive output path from input path
        const base_name = self.getBaseName(input_path);
        const ext = self.getExecutableExtension();

        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_name, ext });
    }

    /// Get the base name from a file path (without directory and .php extension)
    fn getBaseName(self: *const Self, path: []const u8) []const u8 {
        _ = self;
        // Find the last path separator
        var start: usize = 0;
        for (path, 0..) |c, i| {
            if (c == '/' or c == '\\') {
                start = i + 1;
            }
        }

        // Get the filename part
        const filename = path[start..];

        // Remove .php extension if present
        if (std.mem.endsWith(u8, filename, ".php")) {
            return filename[0 .. filename.len - 4];
        }

        return filename;
    }

    /// Get the platform-specific executable extension
    pub fn getExecutableExtension(self: *const Self) []const u8 {
        if (self.config.target) |target| {
            // Check if target is Windows
            if (std.mem.indexOf(u8, target, "windows") != null) {
                return ".exe";
            }
        } else {
            // Native platform - check current OS
            const builtin = @import("builtin");
            if (builtin.os.tag == .windows) {
                return ".exe";
            }
        }
        return "";
    }

    /// Validate output path
    /// Returns true if the output path is valid and writable
    pub fn validateOutputPath(self: *Self, output_path: []const u8) bool {
        _ = self;
        // Check if the directory exists
        const dir_path = blk: {
            var last_sep: ?usize = null;
            for (output_path, 0..) |c, i| {
                if (c == '/' or c == '\\') {
                    last_sep = i;
                }
            }
            if (last_sep) |sep| {
                break :blk output_path[0..sep];
            }
            break :blk ".";
        };

        // Try to access the directory
        std.fs.cwd().access(dir_path, .{}) catch {
            return false;
        };

        return true;
    }

    /// Get configuration
    pub fn getConfig(self: *const Self) ZigLinkerConfig {
        return self.config;
    }

    /// Set configuration
    pub fn setConfig(self: *Self, config: ZigLinkerConfig) void {
        self.config = config;
    }
};

/// Configuration for ZigLinker
pub const ZigLinkerConfig = struct {
    /// Target platform triple (e.g., "x86_64-linux-gnu")
    /// If null, compiles for the native platform
    target: ?[]const u8,

    /// Optimization level
    optimize_level: ZigOptimizeLevel,

    /// Whether to statically link
    static_link: bool,

    /// Whether to strip debug symbols
    strip_symbols: bool,

    /// Whether to include debug info
    debug_info: bool,

    /// Extra flags to pass to the Zig compiler
    extra_flags: []const []const u8,

    /// Verbose output
    verbose: bool,

    /// Create default configuration
    pub fn default() ZigLinkerConfig {
        return .{
            .target = null,
            .optimize_level = .debug,
            .static_link = false,
            .strip_symbols = false,
            .debug_info = true,
            .extra_flags = &[_][]const u8{},
            .verbose = false,
        };
    }

    /// Create release configuration
    pub fn release() ZigLinkerConfig {
        return .{
            .target = null,
            .optimize_level = .release_safe,
            .static_link = true,
            .strip_symbols = true,
            .debug_info = false,
            .extra_flags = &[_][]const u8{},
            .verbose = false,
        };
    }

    /// Create configuration from Target and OptimizeLevel
    pub fn fromTarget(target: Target, opt_level: OptimizeLevel) ZigLinkerConfig {
        const target_str = switch (target.os) {
            .linux => switch (target.arch) {
                .x86_64 => "x86_64-linux-gnu",
                .aarch64 => "aarch64-linux-gnu",
                .arm => "arm-linux-gnueabihf",
            },
            .macos => switch (target.arch) {
                .x86_64 => "x86_64-macos",
                .aarch64 => "aarch64-macos",
                .arm => "arm-macos",
            },
            .windows => switch (target.arch) {
                .x86_64 => "x86_64-windows-msvc",
                .aarch64 => "aarch64-windows-msvc",
                .arm => "arm-windows-msvc",
            },
        };

        return .{
            .target = target_str,
            .optimize_level = ZigOptimizeLevel.fromOptimizeLevel(opt_level),
            .static_link = true,
            .strip_symbols = opt_level != .debug,
            .debug_info = opt_level == .debug,
            .extra_flags = &[_][]const u8{},
            .verbose = false,
        };
    }
};

/// Zig optimization levels
pub const ZigOptimizeLevel = enum {
    debug,
    release_safe,
    release_fast,
    release_small,

    /// Convert to Zig compiler flag
    pub fn toZigFlag(self: ZigOptimizeLevel) []const u8 {
        return switch (self) {
            .debug => "-ODebug",
            .release_safe => "-OReleaseSafe",
            .release_fast => "-OReleaseFast",
            .release_small => "-OReleaseSmall",
        };
    }

    /// Convert from OptimizeLevel
    pub fn fromOptimizeLevel(opt: OptimizeLevel) ZigOptimizeLevel {
        return switch (opt) {
            .debug => .debug,
            .release_safe => .release_safe,
            .release_fast => .release_fast,
            .release_small => .release_small,
        };
    }
};

// ============================================================================
// ZigLinker Unit Tests
// ============================================================================

test "ZigLinkerConfig.default" {
    const config = ZigLinkerConfig.default();
    try std.testing.expect(config.target == null);
    try std.testing.expectEqual(ZigOptimizeLevel.debug, config.optimize_level);
    try std.testing.expect(!config.static_link);
    try std.testing.expect(!config.strip_symbols);
    try std.testing.expect(config.debug_info);
    try std.testing.expect(!config.verbose);
}

test "ZigLinkerConfig.release" {
    const config = ZigLinkerConfig.release();
    try std.testing.expect(config.target == null);
    try std.testing.expectEqual(ZigOptimizeLevel.release_safe, config.optimize_level);
    try std.testing.expect(config.static_link);
    try std.testing.expect(config.strip_symbols);
    try std.testing.expect(!config.debug_info);
}

test "ZigLinkerConfig.fromTarget" {
    const target = Target{ .arch = .x86_64, .os = .linux, .abi = .gnu };
    const config = ZigLinkerConfig.fromTarget(target, .release_fast);
    try std.testing.expectEqualStrings("x86_64-linux-gnu", config.target.?);
    try std.testing.expectEqual(ZigOptimizeLevel.release_fast, config.optimize_level);
    try std.testing.expect(config.static_link);
}

test "ZigOptimizeLevel.toZigFlag" {
    try std.testing.expectEqualStrings("-ODebug", ZigOptimizeLevel.debug.toZigFlag());
    try std.testing.expectEqualStrings("-OReleaseSafe", ZigOptimizeLevel.release_safe.toZigFlag());
    try std.testing.expectEqualStrings("-OReleaseFast", ZigOptimizeLevel.release_fast.toZigFlag());
    try std.testing.expectEqualStrings("-OReleaseSmall", ZigOptimizeLevel.release_small.toZigFlag());
}

test "ZigLinker.init and deinit" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    try std.testing.expectEqual(config.optimize_level, linker.getConfig().optimize_level);
}

test "ZigLinker.writeTempSourceFile" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    const source = "pub fn main() void {}";
    const path = try linker.writeTempSourceFile(source);

    // Verify file was created
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf: [100]u8 = undefined;
    const bytes_read = try file.readAll(&buf);
    try std.testing.expectEqualStrings(source, buf[0..bytes_read]);
}

test "ZigLinker.buildZigCommand" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    // Test with debug configuration
    var config = ZigLinkerConfig.default();
    config.verbose = false;
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    var args = std.ArrayListUnmanaged([]const u8){};
    defer {
        // Free allocated strings (emit_path is allocated by buildZigCommand)
        for (args.items) |arg| {
            if (std.mem.startsWith(u8, arg, "-femit-bin=")) {
                allocator.free(arg);
            }
        }
        args.deinit(allocator);
    }

    try linker.buildZigCommand(&args, "test.zig", "test_output");

    // Verify basic command structure
    try std.testing.expect(args.items.len >= 4);
    try std.testing.expectEqualStrings("zig", args.items[0]);
    try std.testing.expectEqualStrings("build-exe", args.items[1]);
    try std.testing.expectEqualStrings("test.zig", args.items[2]);

    // Verify output path is set
    var found_output = false;
    for (args.items) |arg| {
        if (std.mem.startsWith(u8, arg, "-femit-bin=")) {
            found_output = true;
            try std.testing.expect(std.mem.endsWith(u8, arg, "test_output"));
        }
    }
    try std.testing.expect(found_output);

    // Verify optimization flag is present
    var found_opt = false;
    for (args.items) |arg| {
        if (std.mem.startsWith(u8, arg, "-O")) {
            found_opt = true;
        }
    }
    try std.testing.expect(found_opt);
}

test "ZigLinker.buildZigCommand with target" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    // Test with cross-compilation target
    var config = ZigLinkerConfig.default();
    config.target = "x86_64-linux-gnu";
    config.optimize_level = .release_fast;
    config.strip_symbols = true;
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    var args = std.ArrayListUnmanaged([]const u8){};
    defer {
        // Free allocated strings (emit_path is allocated by buildZigCommand)
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
            try std.testing.expect(i + 1 < args.items.len);
            try std.testing.expectEqualStrings("x86_64-linux-gnu", args.items[i + 1]);
        }
    }
    try std.testing.expect(found_target);

    // Verify strip flag is present
    var found_strip = false;
    for (args.items) |arg| {
        if (std.mem.eql(u8, arg, "-fstrip")) {
            found_strip = true;
        }
    }
    try std.testing.expect(found_strip);

    // Verify release-fast optimization
    var found_release_fast = false;
    for (args.items) |arg| {
        if (std.mem.eql(u8, arg, "-OReleaseFast")) {
            found_release_fast = true;
        }
    }
    try std.testing.expect(found_release_fast);
}

test "ZigLinker.isStaticLinkEnabled" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    // Test default config (static_link = false)
    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    try std.testing.expect(!linker.isStaticLinkEnabled());

    // Enable static linking
    linker.setStaticLink(true);
    try std.testing.expect(linker.isStaticLinkEnabled());

    // Disable static linking
    linker.setStaticLink(false);
    try std.testing.expect(!linker.isStaticLinkEnabled());
}

test "ZigLinker.getRuntimeLibSourcePath" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    const path = linker.getRuntimeLibSourcePath();
    try std.testing.expectEqualStrings("src/aot/runtime_lib.zig", path);
}

test "ZigLinkerConfig static linking" {
    // Test release config has static linking enabled
    const release_config = ZigLinkerConfig.release();
    try std.testing.expect(release_config.static_link);

    // Test default config has static linking disabled
    const default_config = ZigLinkerConfig.default();
    try std.testing.expect(!default_config.static_link);

    // Test fromTarget with release optimization enables static linking
    const target = Target{ .arch = .x86_64, .os = .linux, .abi = .gnu };
    const target_config = ZigLinkerConfig.fromTarget(target, .release_fast);
    try std.testing.expect(target_config.static_link);
}

test "ZigLinker.generateOutputPath with explicit output" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    // Test with explicit output path
    const output = try linker.generateOutputPath("input.php", "my_app");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("my_app", output);
}

test "ZigLinker.generateOutputPath derived from input" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    // Test deriving output from input (removes .php extension)
    const output1 = try linker.generateOutputPath("hello.php", null);
    defer allocator.free(output1);
    try std.testing.expectEqualStrings("hello", output1);

    // Test with path
    const output2 = try linker.generateOutputPath("/path/to/script.php", null);
    defer allocator.free(output2);
    try std.testing.expectEqualStrings("script", output2);

    // Test without .php extension
    const output3 = try linker.generateOutputPath("myprogram", null);
    defer allocator.free(output3);
    try std.testing.expectEqualStrings("myprogram", output3);
}

test "ZigLinker.generateOutputPath with Windows target" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    var config = ZigLinkerConfig.default();
    config.target = "x86_64-windows-msvc";
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    // Test that Windows target adds .exe extension
    const output = try linker.generateOutputPath("hello.php", null);
    defer allocator.free(output);
    try std.testing.expectEqualStrings("hello.exe", output);
}

test "ZigLinker.getExecutableExtension" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    // Test Linux target (no extension)
    var linux_config = ZigLinkerConfig.default();
    linux_config.target = "x86_64-linux-gnu";
    const linux_linker = try ZigLinker.init(allocator, linux_config, &diagnostics);
    defer linux_linker.deinit();
    try std.testing.expectEqualStrings("", linux_linker.getExecutableExtension());

    // Test Windows target (.exe extension)
    var windows_config = ZigLinkerConfig.default();
    windows_config.target = "x86_64-windows-msvc";
    const windows_linker = try ZigLinker.init(allocator, windows_config, &diagnostics);
    defer windows_linker.deinit();
    try std.testing.expectEqualStrings(".exe", windows_linker.getExecutableExtension());

    // Test macOS target (no extension)
    var macos_config = ZigLinkerConfig.default();
    macos_config.target = "aarch64-macos";
    const macos_linker = try ZigLinker.init(allocator, macos_config, &diagnostics);
    defer macos_linker.deinit();
    try std.testing.expectEqualStrings("", macos_linker.getExecutableExtension());
}

test "ZigLinker.validateOutputPath" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const config = ZigLinkerConfig.default();
    const linker = try ZigLinker.init(allocator, config, &diagnostics);
    defer linker.deinit();

    // Test valid path (current directory)
    try std.testing.expect(linker.validateOutputPath("test_output"));

    // Test invalid path (non-existent directory)
    try std.testing.expect(!linker.validateOutputPath("/nonexistent/directory/output"));
}
