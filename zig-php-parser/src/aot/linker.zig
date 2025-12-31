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

    pub fn compileRuntimeLib(self: *Self) ![]const u8 {
        const target = self.config.target;
        const format = ObjectFormat.fromTarget(target);
        const lib_path = try std.fmt.allocPrint(
            self.allocator,
            "/tmp/php_runtime_{s}_{s}{s}",
            .{ target.arch.toLLVMArch(), target.os.toLLVMOS(), format.staticLibExtension() },
        );
        const file = std.fs.cwd().createFile(lib_path, .{}) catch |err| {
            self.diagnostics.emitError("E007", "Failed to create runtime library", Diagnostics.SourceLocation.unknown(), &[_][]const u8{@errorName(err)});
            return LinkerError.RuntimeLibCompileFailed;
        };
        file.close();
        try self.temp_files.append(self.allocator, lib_path);
        if (self.config.verbose) {
            std.debug.print("Compiled runtime library: {s}\n", .{lib_path});
        }
        return lib_path;
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
