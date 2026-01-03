//! AOT Compiler Main Entry Point
//!
//! This module provides the main AOT compiler structure that orchestrates
//! the entire compilation pipeline from PHP source to native executable.
//!
//! ## Compilation Pipeline
//!
//! 1. Parse PHP source code into AST
//! 2. Perform type inference on AST
//! 3. Generate IR from typed AST
//! 4. Optimize IR (constant folding, dead code elimination)
//! 5. Generate native code via LLVM
//! 6. Link with runtime library to produce executable
//!
//! ## Usage
//!
//! ```zig
//! var compiler = try AOTCompiler.init(allocator, options);
//! defer compiler.deinit();
//!
//! try compiler.compile();
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Syntax Mode Types (local definitions for AOT module independence)
// ============================================================================

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

// AOT module imports
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const SourceLocation = Diagnostics.SourceLocation;
const IR = @import("ir.zig");
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const SymbolTableMod = @import("symbol_table.zig");
const SymbolTable = SymbolTableMod.SymbolTable;
const TypeInferenceMod = @import("type_inference.zig");
const TypeInferencer = TypeInferenceMod.TypeInferencer;
const CodeGen = @import("codegen.zig");
const CodeGenerator = CodeGen.CodeGenerator;
const LinkerMod = @import("linker.zig");
const StaticLinker = LinkerMod.StaticLinker;
const LinkerConfig = LinkerMod.LinkerConfig;
const ZigLinker = LinkerMod.ZigLinker;
const ZigLinkerConfig = LinkerMod.ZigLinkerConfig;
const ZigOptimizeLevel = LinkerMod.ZigOptimizeLevel;
const OptimizerMod = @import("optimizer.zig");
const IROptimizer = OptimizerMod.IROptimizer;
const IROptimizeLevel = OptimizerMod.OptimizeLevel;
const ZigCodeGen = @import("zig_codegen.zig");
const ZigCodeGenerator = ZigCodeGen.ZigCodeGenerator;

// Root module for shared types
const root = @import("root.zig");

// IR Generator types (for Node definition)
const IRGeneratorMod = @import("ir_generator.zig");

// ============================================================================
// Compile Options
// ============================================================================

/// AOT Compiler configuration options
pub const CompileOptions = struct {
    /// Input PHP source file path
    input_file: []const u8,
    /// Output executable file path (optional, defaults to input name without .php)
    output_file: ?[]const u8 = null,
    /// Target platform triple
    target: Target = Target.native(),
    /// Optimization level
    optimize_level: OptimizeLevel = .debug,
    /// Generate fully static linked executable
    static_link: bool = true,
    /// Generate debug information
    debug_info: bool = true,
    /// Dump generated IR for debugging
    dump_ir: bool = false,
    /// Dump parsed AST for debugging
    dump_ast: bool = false,
    /// Dump generated Zig code for debugging
    dump_zig: bool = false,
    /// Verbose output during compilation
    verbose: bool = false,
    /// Syntax mode for parsing (PHP or Go style)
    syntax_mode: SyntaxMode = .php,

    /// Get the output file path, deriving from input if not specified
    pub fn getOutputPath(self: *const CompileOptions, allocator: Allocator) ![]const u8 {
        if (self.output_file) |out| {
            return try allocator.dupe(u8, out);
        }

        // Derive output name from input file
        const input = self.input_file;
        const basename = std.fs.path.basename(input);

        // Remove .php extension if present
        if (std.mem.endsWith(u8, basename, ".php")) {
            const name_without_ext = basename[0 .. basename.len - 4];
            return try allocator.dupe(u8, name_without_ext);
        }

        return try allocator.dupe(u8, basename);
    }
};

// ============================================================================
// Optimization Level
// ============================================================================

/// Optimization levels for AOT compilation
pub const OptimizeLevel = enum {
    /// Debug mode: no optimizations, full debug info
    debug,
    /// Release safe: optimizations with safety checks
    release_safe,
    /// Release fast: maximum performance optimizations
    release_fast,
    /// Release small: optimize for binary size
    release_small,

    pub fn toString(self: OptimizeLevel) []const u8 {
        return switch (self) {
            .debug => "debug",
            .release_safe => "release-safe",
            .release_fast => "release-fast",
            .release_small => "release-small",
        };
    }

    pub fn fromString(str: []const u8) ?OptimizeLevel {
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "release-safe")) return .release_safe;
        if (std.mem.eql(u8, str, "release-fast")) return .release_fast;
        if (std.mem.eql(u8, str, "release-small")) return .release_small;
        return null;
    }

    /// Convert to CodeGen optimization level
    pub fn toCodeGenLevel(self: OptimizeLevel) CodeGen.OptimizeLevel {
        return switch (self) {
            .debug => .debug,
            .release_safe => .release_safe,
            .release_fast => .release_fast,
            .release_small => .release_small,
        };
    }

    /// Convert to IR optimizer level
    pub fn toIROptimizeLevel(self: OptimizeLevel) IROptimizeLevel {
        return switch (self) {
            .debug => .none,
            .release_safe => .basic,
            .release_fast => .aggressive,
            .release_small => .size,
        };
    }
};

// ============================================================================
// Target Platform
// ============================================================================

/// Target platform specification
pub const Target = struct {
    arch: Arch,
    os: OS,
    abi: ABI,

    pub const Arch = enum {
        x86_64,
        aarch64,
        arm,

        pub fn toString(self: Arch) []const u8 {
            return switch (self) {
                .x86_64 => "x86_64",
                .aarch64 => "aarch64",
                .arm => "arm",
            };
        }
    };

    pub const OS = enum {
        linux,
        macos,
        windows,

        pub fn toString(self: OS) []const u8 {
            return switch (self) {
                .linux => "linux",
                .macos => "macos",
                .windows => "windows",
            };
        }
    };

    pub const ABI = enum {
        gnu,
        musl,
        msvc,
        none,

        pub fn toString(self: ABI) []const u8 {
            return switch (self) {
                .gnu => "gnu",
                .musl => "musl",
                .msvc => "msvc",
                .none => "none",
            };
        }
    };

    /// Get the native target for the current platform
    pub fn native() Target {
        const builtin = @import("builtin");
        return .{
            .arch = switch (builtin.cpu.arch) {
                .x86_64 => .x86_64,
                .aarch64 => .aarch64,
                .arm => .arm,
                else => .x86_64, // Default fallback
            },
            .os = switch (builtin.os.tag) {
                .linux => .linux,
                .macos => .macos,
                .windows => .windows,
                else => .linux, // Default fallback
            },
            .abi = switch (builtin.os.tag) {
                .linux => .gnu,
                .macos => .none,
                .windows => .msvc,
                else => .gnu,
            },
        };
    }

    /// Parse target from triple string (e.g., "x86_64-linux-gnu")
    pub fn fromString(triple: []const u8) !Target {
        var it = std.mem.splitScalar(u8, triple, '-');

        const arch_str = it.next() orelse return error.InvalidTarget;
        const os_str = it.next() orelse return error.InvalidTarget;
        const abi_str = it.next();

        const arch: Arch = if (std.mem.eql(u8, arch_str, "x86_64"))
            .x86_64
        else if (std.mem.eql(u8, arch_str, "aarch64"))
            .aarch64
        else if (std.mem.eql(u8, arch_str, "arm"))
            .arm
        else
            return error.InvalidTarget;

        const os: OS = if (std.mem.eql(u8, os_str, "linux"))
            .linux
        else if (std.mem.eql(u8, os_str, "macos") or std.mem.eql(u8, os_str, "darwin"))
            .macos
        else if (std.mem.eql(u8, os_str, "windows"))
            .windows
        else
            return error.InvalidTarget;

        const abi: ABI = if (abi_str) |s| blk: {
            if (std.mem.eql(u8, s, "gnu")) break :blk .gnu;
            if (std.mem.eql(u8, s, "musl")) break :blk .musl;
            if (std.mem.eql(u8, s, "msvc")) break :blk .msvc;
            break :blk .none;
        } else switch (os) {
            .linux => .gnu,
            .macos => .none,
            .windows => .msvc,
        };

        return .{ .arch = arch, .os = os, .abi = abi };
    }

    /// Convert target to triple string
    pub fn toTriple(self: Target, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{
            self.arch.toString(),
            self.os.toString(),
            self.abi.toString(),
        });
    }

    /// Convert to CodeGen target
    pub fn toCodeGenTarget(self: Target) CodeGen.Target {
        return .{
            .arch = switch (self.arch) {
                .x86_64 => .x86_64,
                .aarch64 => .aarch64,
                .arm => .arm,
            },
            .os = switch (self.os) {
                .linux => .linux,
                .macos => .macos,
                .windows => .windows,
            },
            .abi = switch (self.abi) {
                .gnu => .gnu,
                .musl => .musl,
                .msvc => .msvc,
                .none => .none,
            },
        };
    }
};

/// List of all supported target platforms
pub const supported_targets = [_][]const u8{
    "x86_64-linux-gnu",
    "x86_64-linux-musl",
    "aarch64-linux-gnu",
    "aarch64-linux-musl",
    "x86_64-macos-none",
    "aarch64-macos-none",
    "x86_64-windows-msvc",
    "aarch64-windows-msvc",
};

/// Print list of supported targets to stdout
pub fn listTargets(writer: anytype) !void {
    try writer.writeAll("Supported target platforms:\n\n");
    for (supported_targets) |target| {
        try writer.print("  {s}\n", .{target});
    }
    try writer.writeAll("\nUse --target=<triple> to specify a target platform.\n");
}

// ============================================================================
// Compilation Result
// ============================================================================

/// Result of a compilation operation
pub const CompileResult = struct {
    /// Whether compilation succeeded
    success: bool,
    /// Output file path (if successful)
    output_path: ?[]const u8,
    /// Number of errors encountered
    error_count: u32,
    /// Number of warnings encountered
    warning_count: u32,
    /// Generated IR module (if dump_ir was requested)
    ir_module: ?*IR.Module,

    pub fn succeeded(output_path: []const u8) CompileResult {
        return .{
            .success = true,
            .output_path = output_path,
            .error_count = 0,
            .warning_count = 0,
            .ir_module = null,
        };
    }

    pub fn failed(error_count: u32, warning_count: u32) CompileResult {
        return .{
            .success = false,
            .output_path = null,
            .error_count = error_count,
            .warning_count = warning_count,
            .ir_module = null,
        };
    }
};

/// Compilation error types
pub const CompileError = error{
    FileNotFound,
    FileReadError,
    ParseError,
    TypeInferenceError,
    IRGenerationError,
    CodeGenerationError,
    ZigCodeGenerationError,
    ZigCompilationError,
    ZigCompilerNotFound,
    LinkError,
    OutputWriteError,
    InvalidTarget,
    OutOfMemory,
    RuntimeLibNotFound,
};

/// Error context for detailed error reporting
pub const ErrorContext = struct {
    /// Error code (e.g., "E001", "E002")
    code: []const u8,
    /// Error message
    message: []const u8,
    /// Source file (if applicable)
    file: ?[]const u8,
    /// Line number (if applicable)
    line: ?u32,
    /// Column number (if applicable)
    column: ?u32,
    /// Additional context or suggestion
    hint: ?[]const u8,

    pub fn format(self: ErrorContext, writer: anytype) !void {
        try writer.print("[{s}] ", .{self.code});
        if (self.file) |f| {
            try writer.print("{s}", .{f});
            if (self.line) |l| {
                try writer.print(":{d}", .{l});
                if (self.column) |c| {
                    try writer.print(":{d}", .{c});
                }
            }
            try writer.print(": ", .{});
        }
        try writer.print("{s}\n", .{self.message});
        if (self.hint) |h| {
            try writer.print("  hint: {s}\n", .{h});
        }
    }
};

// ============================================================================
// AOT Compiler
// ============================================================================

/// AOT Compiler - Main entry point for PHP to native compilation
pub const AOTCompiler = struct {
    allocator: Allocator,
    options: CompileOptions,
    diagnostics: *DiagnosticEngine,
    symbol_table: ?*SymbolTable,
    type_inferencer: ?*TypeInferencer,
    ir_generator: ?*IRGenerator,
    codegen: ?*CodeGenerator,
    linker: ?*StaticLinker,
    optimizer: ?*IROptimizer,
    /// Zig code generator for AOT compilation
    zig_codegen: ?*ZigCodeGenerator,
    /// Zig linker for compiling generated Zig code
    zig_linker: ?*ZigLinker,
    /// Generated Zig source code (for --dump-zig option)
    generated_zig_source: ?[]const u8,
    /// Syntax configuration derived from options
    syntax_config: SyntaxConfig,

    /// Source code (loaded from file)
    source: ?[]const u8,
    /// Parsed AST nodes
    ast_nodes: ?[]const IRGeneratorMod.Node,
    /// String table from parser
    string_table: ?[]const []const u8,
    /// Root node index in AST (for IR generation)
    root_node_index: u32,
    /// Generated IR module
    ir_module: ?*IR.Module,

    const Self = @This();

    /// Initialize a new AOT compiler
    pub fn init(allocator: Allocator, options: CompileOptions) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize diagnostics engine
        const diagnostics = try allocator.create(DiagnosticEngine);
        diagnostics.* = DiagnosticEngine.init(allocator);

        // Initialize syntax config from options
        const syntax_config = SyntaxConfig.init(options.syntax_mode);

        self.* = .{
            .allocator = allocator,
            .options = options,
            .diagnostics = diagnostics,
            .symbol_table = null,
            .type_inferencer = null,
            .ir_generator = null,
            .codegen = null,
            .linker = null,
            .optimizer = null,
            .zig_codegen = null,
            .zig_linker = null,
            .generated_zig_source = null,
            .syntax_config = syntax_config,
            .source = null,
            .ast_nodes = null,
            .string_table = null,
            .root_node_index = 0,
            .ir_module = null,
        };

        return self;
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self) void {
        // Free generated Zig source
        if (self.generated_zig_source) |src| {
            self.allocator.free(src);
        }

        // Free Zig code generator
        if (self.zig_codegen) |gen| {
            gen.deinit();
            self.allocator.destroy(gen);
        }

        // Free Zig linker (deinit already destroys itself)
        if (self.zig_linker) |lnk| {
            lnk.deinit();
        }

        // Free IR module
        if (self.ir_module) |module| {
            module.deinit();
            self.allocator.destroy(module);
        }

        // Free IR generator
        if (self.ir_generator) |gen| {
            gen.deinit();
            self.allocator.destroy(gen);
        }

        // Free optimizer
        if (self.optimizer) |opt| {
            opt.deinit();
            self.allocator.destroy(opt);
        }

        // Free type inferencer
        if (self.type_inferencer) |ti| {
            self.allocator.destroy(ti);
        }

        // Free symbol table
        if (self.symbol_table) |st| {
            st.deinit();
            self.allocator.destroy(st);
        }

        // Free code generator (deinit already destroys itself)
        if (self.codegen) |cg| {
            cg.deinit();
        }

        // Free linker (deinit already destroys itself)
        if (self.linker) |lnk| {
            lnk.deinit();
        }

        // Free AST nodes
        if (self.ast_nodes) |nodes| {
            self.allocator.free(nodes);
        }

        // Free string table
        if (self.string_table) |table| {
            for (table) |s| {
                self.allocator.free(s);
            }
            self.allocator.free(table);
        }

        // Free source
        if (self.source) |src| {
            self.allocator.free(src);
        }

        // Free diagnostics
        self.diagnostics.deinit();
        self.allocator.destroy(self.diagnostics);

        // Free self
        self.allocator.destroy(self);
    }

    /// Initialize compilation components
    fn initComponents(self: *Self) !void {
        // Initialize symbol table
        const symbol_table = try self.allocator.create(SymbolTable);
        symbol_table.* = try SymbolTable.init(self.allocator);
        self.symbol_table = symbol_table;

        // Initialize type inferencer
        const type_inferencer = try self.allocator.create(TypeInferencer);
        type_inferencer.* = TypeInferencer.init(self.allocator, symbol_table, self.diagnostics);
        self.type_inferencer = type_inferencer;

        // Initialize IR generator
        self.ir_generator = try self.allocator.create(IRGenerator);
        self.ir_generator.?.* = IRGenerator.init(
            self.allocator,
            symbol_table,
            type_inferencer,
            self.diagnostics,
        );

        // Initialize optimizer
        const optimizer = try self.allocator.create(IROptimizer);
        optimizer.* = IROptimizer.init(
            self.allocator,
            self.options.optimize_level.toIROptimizeLevel(),
            self.diagnostics,
        );
        self.optimizer = optimizer;

        // Initialize Zig code generator (replaces LLVM-based code generator)
        const zig_codegen = try self.allocator.create(ZigCodeGenerator);
        zig_codegen.* = ZigCodeGenerator.init(self.allocator, self.diagnostics);
        self.zig_codegen = zig_codegen;

        // Initialize Zig linker
        var zig_linker_config = ZigLinkerConfig.fromTarget(self.options.target.toCodeGenTarget(), self.options.optimize_level.toCodeGenLevel());
        zig_linker_config.verbose = self.options.verbose;
        self.zig_linker = try ZigLinker.init(self.allocator, zig_linker_config, self.diagnostics);

        // Initialize legacy code generator (for backward compatibility)
        self.codegen = try CodeGenerator.init(
            self.allocator,
            self.options.target.toCodeGenTarget(),
            self.options.optimize_level.toCodeGenLevel(),
            self.options.debug_info,
            self.diagnostics,
        );

        // Initialize legacy linker (for backward compatibility)
        const linker_config = LinkerConfig{
            .target = self.options.target.toCodeGenTarget(),
            .optimize_level = self.options.optimize_level.toCodeGenLevel(),
            .static_link = self.options.static_link,
            .debug_info = self.options.debug_info,
            .strip_symbols = self.options.optimize_level == .release_small,
            .library_paths = &[_][]const u8{},
            .libraries = &[_][]const u8{},
            .extra_flags = &[_][]const u8{},
            .verbose = self.options.verbose,
        };
        self.linker = try StaticLinker.init(self.allocator, linker_config, self.diagnostics);
    }

    /// Main compilation entry point
    pub fn compile(self: *Self) !CompileResult {
        if (self.options.verbose) {
            self.printCompileInfo();
        }

        // Initialize all components
        try self.initComponents();

        // Step 1: Load and parse source file
        try self.loadSource();
        if (self.diagnostics.hasErrors()) {
            return CompileResult.failed(self.diagnostics.error_count, self.diagnostics.warning_count);
        }

        // Step 2: Parse source into AST
        try self.parseSource();
        if (self.diagnostics.hasErrors()) {
            return CompileResult.failed(self.diagnostics.error_count, self.diagnostics.warning_count);
        }

        // Dump AST if requested
        if (self.options.dump_ast) {
            self.dumpAST();
        }

        // Step 3: Generate IR
        try self.generateIR();
        if (self.diagnostics.hasErrors()) {
            return CompileResult.failed(self.diagnostics.error_count, self.diagnostics.warning_count);
        }

        // Step 4: Optimize IR
        try self.optimizeIR();
        if (self.diagnostics.hasErrors()) {
            return CompileResult.failed(self.diagnostics.error_count, self.diagnostics.warning_count);
        }

        // Dump IR if requested (after optimization)
        if (self.options.dump_ir) {
            self.dumpIR();
        }

        // Step 5: Generate native code
        try self.generateCode();
        if (self.diagnostics.hasErrors()) {
            return CompileResult.failed(self.diagnostics.error_count, self.diagnostics.warning_count);
        }

        // Dump generated Zig code if requested
        if (self.options.dump_zig) {
            self.dumpZig();
        }

        // Step 6: Link executable
        const output_path = try self.options.getOutputPath(self.allocator);
        try self.linkExecutable(output_path);
        if (self.diagnostics.hasErrors()) {
            self.allocator.free(output_path);
            return CompileResult.failed(self.diagnostics.error_count, self.diagnostics.warning_count);
        }

        if (self.options.verbose) {
            std.debug.print("Compilation successful: {s}\n", .{output_path});
        }

        return CompileResult.succeeded(output_path);
    }

    /// Print compilation information (verbose mode)
    fn printCompileInfo(self: *const Self) void {
        std.debug.print("AOT Compiler starting...\n", .{});
        std.debug.print("  Input file: {s}\n", .{self.options.input_file});
        if (self.options.output_file) |out| {
            std.debug.print("  Output file: {s}\n", .{out});
        } else {
            std.debug.print("  Output file: (derived from input)\n", .{});
        }
        if (self.options.target.toTriple(self.allocator)) |target_triple| {
            defer self.allocator.free(target_triple);
            std.debug.print("  Target: {s}\n", .{target_triple});
        } else |_| {
            std.debug.print("  Target: native\n", .{});
        }
        std.debug.print("  Optimize: {s}\n", .{self.options.optimize_level.toString()});
        std.debug.print("  Static link: {}\n", .{self.options.static_link});
        std.debug.print("  Debug info: {}\n", .{self.options.debug_info});
        std.debug.print("  Syntax mode: {s}\n", .{self.options.syntax_mode.toString()});
        std.debug.print("  Dump options:\n", .{});
        std.debug.print("    --dump-ast: {}\n", .{self.options.dump_ast});
        std.debug.print("    --dump-ir: {}\n", .{self.options.dump_ir});
        std.debug.print("    --dump-zig: {}\n", .{self.options.dump_zig});
        std.debug.print("\n", .{});
    }

    /// Load source file
    fn loadSource(self: *Self) !void {
        const file = std.fs.cwd().openFile(self.options.input_file, .{}) catch |err| {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "cannot open file: {s}",
                .{@errorName(err)},
            );
            return;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const source = try self.allocator.alloc(u8, file_size);
        errdefer self.allocator.free(source);

        const bytes_read = try file.readAll(source);
        if (bytes_read != file_size) {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "incomplete file read",
                .{},
            );
            return;
        }

        self.source = source;

        // Set source for diagnostic context
        try self.diagnostics.setSource(source);

        if (self.options.verbose) {
            std.debug.print("  Loaded {d} bytes from {s}\n", .{ file_size, self.options.input_file });
        }
    }

    /// Set pre-parsed AST nodes and string table
    /// This is used when the parser is invoked externally (e.g., from main.zig)
    pub fn setAST(self: *Self, nodes: []const IRGeneratorMod.Node, string_table: []const []const u8) !void {
        // Copy nodes to our allocator
        const owned_nodes = try self.allocator.alloc(IRGeneratorMod.Node, nodes.len);
        @memcpy(owned_nodes, nodes);
        self.ast_nodes = owned_nodes;

        // Copy string table to our allocator
        const owned_table = try self.allocator.alloc([]const u8, string_table.len);
        for (string_table, 0..) |s, i| {
            owned_table[i] = try self.allocator.dupe(u8, s);
        }
        self.string_table = owned_table;

        if (self.options.verbose) {
            std.debug.print("  AST set: {d} nodes, {d} strings\n", .{ nodes.len, string_table.len });
        }
    }

    /// Set pre-parsed AST nodes, string table, and root node index
    /// This is used when the parser is invoked externally (e.g., from main.zig)
    /// and provides the root node index for proper IR generation
    pub fn setASTWithRoot(self: *Self, nodes: []const IRGeneratorMod.Node, string_table: []const []const u8, root_index: u32) !void {
        try self.setAST(nodes, string_table);
        self.root_node_index = root_index;

        if (self.options.verbose) {
            std.debug.print("  Root node index: {d}\n", .{root_index});
        }
    }

    /// Parse source into AST
    /// Note: This method requires the parser module to be available.
    /// When testing the AOT module in isolation, use setAST() instead.
    fn parseSource(self: *Self) !void {
        if (self.source == null) {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "no source loaded",
                .{},
            );
            return;
        }

        // If AST was already set externally, skip parsing
        if (self.ast_nodes != null and self.string_table != null) {
            if (self.options.verbose) {
                std.debug.print("  Using pre-set AST: {d} nodes, {d} strings\n", .{
                    self.ast_nodes.?.len,
                    self.string_table.?.len,
                });
            }
            return;
        }

        // Parser integration is handled externally via setAST()
        // This allows the AOT module to be tested independently
        self.diagnostics.reportError(
            .{ .file = self.options.input_file },
            "parser not available - use setAST() to provide pre-parsed AST",
            .{},
        );
    }

    /// Generate IR from AST
    fn generateIR(self: *Self) !void {
        if (self.ast_nodes == null or self.string_table == null) {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "no AST available for IR generation",
                .{},
            );
            return;
        }

        if (self.options.verbose) {
            std.debug.print("  Generating IR...\n", .{});
            std.debug.print("  Root node index: {d}\n", .{self.root_node_index});
        }

        const ir_gen = self.ir_generator orelse {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "IR generator not initialized",
                .{},
            );
            return;
        };

        // Generate IR module using the root node index
        self.ir_module = ir_gen.generateFromRoot(
            self.ast_nodes.?,
            self.string_table.?,
            self.root_node_index,
            self.options.input_file,
            self.options.input_file,
        ) catch |err| {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "IR generation failed: {s}",
                .{@errorName(err)},
            );
            return;
        };

        if (self.options.verbose) {
            if (self.ir_module) |module| {
                std.debug.print("  IR generation completed: {d} functions\n", .{module.functions.items.len});
            }
        }
    }

    /// Optimize IR using configured optimization passes
    fn optimizeIR(self: *Self) !void {
        if (self.ir_module == null) {
            // No IR to optimize, skip silently
            return;
        }

        const optimizer = self.optimizer orelse {
            // No optimizer configured, skip optimization
            return;
        };

        // Skip optimization in debug mode
        if (self.options.optimize_level == .debug) {
            if (self.options.verbose) {
                std.debug.print("  Skipping IR optimization (debug mode)\n", .{});
            }
            return;
        }

        if (self.options.verbose) {
            std.debug.print("  Optimizing IR ({s})...\n", .{self.options.optimize_level.toString()});
        }

        // Run optimization passes
        optimizer.optimize(self.ir_module.?) catch |err| {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "IR optimization failed: {s}",
                .{@errorName(err)},
            );
            return;
        };

        // Print optimization statistics in verbose mode
        if (self.options.verbose) {
            const stats = optimizer.getStats();
            std.debug.print("  Optimization completed:\n", .{});
            std.debug.print("    - Dead instructions removed: {d}\n", .{stats.dead_instructions_removed});
            std.debug.print("    - Dead blocks removed: {d}\n", .{stats.dead_blocks_removed});
            std.debug.print("    - Constants propagated: {d}\n", .{stats.constants_propagated});
            std.debug.print("    - Functions inlined: {d}\n", .{stats.functions_inlined});
            std.debug.print("    - CSE eliminations: {d}\n", .{stats.cse_eliminations});
            std.debug.print("    - Passes run: {d}\n", .{stats.passes_run});
        }
    }

    /// Generate native code from IR using Zig code generator
    fn generateCode(self: *Self) !void {
        if (self.ir_module == null) {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "no IR module available for code generation",
                .{},
            );
            return;
        }

        if (self.options.verbose) {
            std.debug.print("  Generating Zig code from IR...\n", .{});
        }

        const zig_codegen = self.zig_codegen orelse {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "Zig code generator not initialized",
                .{},
            );
            return;
        };

        // Generate Zig source code from IR
        self.generated_zig_source = zig_codegen.generate(self.ir_module.?) catch |err| {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "Zig code generation failed: {s}",
                .{@errorName(err)},
            );
            return;
        };

        if (self.options.verbose) {
            if (self.generated_zig_source) |src| {
                std.debug.print("  Zig code generation completed: {d} bytes\n", .{src.len});
            }
        }
    }

    /// Link executable using Zig compiler
    fn linkExecutable(self: *Self, output_path: []const u8) !void {
        if (self.options.verbose) {
            std.debug.print("  Compiling and linking executable: {s}\n", .{output_path});
        }

        // Check if we have generated Zig source code
        const zig_source = self.generated_zig_source orelse {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "[E005] No Zig source code generated - IR to Zig conversion may have failed",
                .{},
            );
            return;
        };

        // Get the Zig linker
        const zig_linker = self.zig_linker orelse {
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "[E006] Zig linker not initialized - internal compiler error",
                .{},
            );
            return;
        };

        // Read the runtime library source
        const runtime_source = std.fs.cwd().readFileAlloc(
            self.allocator,
            zig_linker.getRuntimeLibSourcePath(),
            1024 * 1024, // 1MB max
        ) catch |err| {
            if (self.options.verbose) {
                std.debug.print("  Warning: Could not read runtime library ({s}): {s}\n", .{ zig_linker.getRuntimeLibSourcePath(), @errorName(err) });
                std.debug.print("  Attempting compilation without embedded runtime...\n", .{});
            }
            // Try to compile without embedded runtime
            zig_linker.compileAndLink(zig_source, output_path) catch |link_err| {
                self.reportZigCompilationError(link_err);
                return;
            };
            if (self.options.verbose) {
                std.debug.print("  Compilation completed.\n", .{});
            }
            return;
        };
        defer self.allocator.free(runtime_source);

        // Compile with embedded runtime library
        zig_linker.compileWithEmbeddedRuntime(zig_source, runtime_source, output_path) catch |err| {
            self.reportZigCompilationError(err);
            return;
        };

        if (self.options.verbose) {
            std.debug.print("  Compilation and linking completed.\n", .{});
        }
    }

    /// Report Zig compilation error with user-friendly message
    fn reportZigCompilationError(self: *Self, err: anyerror) void {
        const error_code = switch (err) {
            LinkerMod.LinkerError.MissingTool => "[E006]",
            LinkerMod.LinkerError.LinkerFailed => "[E006]",
            LinkerMod.LinkerError.ProcessSpawnError => "[E006]",
            LinkerMod.LinkerError.LinkerInvocationFailed => "[E006]",
            else => "[E006]",
        };

        const error_msg = switch (err) {
            LinkerMod.LinkerError.MissingTool => "Zig compiler not found. Please ensure Zig is installed and in your PATH.",
            LinkerMod.LinkerError.LinkerFailed => "Zig compilation failed. Check the generated Zig code with --dump-zig for details.",
            LinkerMod.LinkerError.ProcessSpawnError => "Failed to start Zig compiler process.",
            LinkerMod.LinkerError.LinkerInvocationFailed => "Zig compiler invocation failed.",
            LinkerMod.LinkerError.ObjectFileWriteFailed => "Failed to write temporary source file.",
            LinkerMod.LinkerError.RuntimeLibCompileFailed => "Failed to compile runtime library.",
            else => "Zig compilation failed.",
        };

        self.diagnostics.reportError(
            .{ .file = self.options.input_file },
            "{s} {s} ({s})",
            .{ error_code, error_msg, @errorName(err) },
        );

        // Provide additional hints based on error type
        if (err == LinkerMod.LinkerError.MissingTool) {
            std.debug.print("  Hint: Install Zig from https://ziglang.org/download/\n", .{});
        } else if (err == LinkerMod.LinkerError.LinkerFailed) {
            std.debug.print("  Hint: Use --dump-zig to see the generated Zig code and identify issues.\n", .{});
        }
    }

    /// Dump AST for debugging
    fn dumpAST(self: *const Self) void {
        std.debug.print("\n=== AST Dump ===\n", .{});

        if (self.ast_nodes) |nodes| {
            std.debug.print("Total nodes: {d}\n", .{nodes.len});

            const max_nodes = @min(nodes.len, 20);
            for (nodes[0..max_nodes], 0..) |node, i| {
                std.debug.print("  Node {d}: tag={s}\n", .{ i, @tagName(node.tag) });
            }

            if (nodes.len > 20) {
                std.debug.print("  ... and {d} more nodes\n", .{nodes.len - 20});
            }
        } else {
            std.debug.print("No AST nodes available.\n", .{});
        }

        if (self.string_table) |table| {
            std.debug.print("String table size: {d}\n", .{table.len});
        }

        std.debug.print("=== End AST ===\n\n", .{});
    }

    /// Dump IR for debugging
    fn dumpIR(self: *const Self) void {
        std.debug.print("\n=== IR Dump ===\n", .{});

        if (self.ir_module) |module| {
            // Serialize and print IR
            const ir_text = IR.serializeModule(self.allocator, module) catch |err| {
                std.debug.print("IR serialization error: {s}\n", .{@errorName(err)});
                std.debug.print("=== End IR ===\n\n", .{});
                return;
            };
            defer self.allocator.free(ir_text);

            std.debug.print("{s}", .{ir_text});
        } else {
            std.debug.print("No IR module available.\n", .{});
        }

        std.debug.print("=== End IR ===\n\n", .{});
    }

    /// Dump generated Zig code for debugging
    fn dumpZig(self: *const Self) void {
        std.debug.print("\n=== Generated Zig Code ===\n", .{});

        if (self.generated_zig_source) |src| {
            std.debug.print("{s}", .{src});
        } else {
            std.debug.print("No Zig code generated.\n", .{});
        }

        std.debug.print("=== End Zig Code ===\n\n", .{});
    }

    /// Get the generated Zig source code (for external use)
    pub fn getGeneratedZigSource(self: *const Self) ?[]const u8 {
        return self.generated_zig_source;
    }

    /// Compile to IR only (for testing/debugging)
    pub fn compileToIR(self: *Self) !?*IR.Module {
        try self.initComponents();
        try self.loadSource();
        if (self.diagnostics.hasErrors()) return null;

        try self.parseSource();
        if (self.diagnostics.hasErrors()) return null;

        try self.generateIR();
        if (self.diagnostics.hasErrors()) return null;

        // Optionally optimize IR
        try self.optimizeIR();
        if (self.diagnostics.hasErrors()) return null;

        return self.ir_module;
    }

    /// Get diagnostics engine
    pub fn getDiagnostics(self: *const Self) *DiagnosticEngine {
        return self.diagnostics;
    }

    /// Get syntax configuration
    pub fn getSyntaxConfig(self: *const Self) SyntaxConfig {
        return self.syntax_config;
    }

    /// Get syntax mode
    pub fn getSyntaxMode(self: *const Self) SyntaxMode {
        return self.options.syntax_mode;
    }

    /// Check if compilation had errors
    pub fn hasErrors(self: *const Self) bool {
        return self.diagnostics.hasErrors();
    }

    /// Check if compilation had warnings
    pub fn hasWarnings(self: *const Self) bool {
        return self.diagnostics.hasWarnings();
    }

    /// Print all diagnostics to stderr
    pub fn printDiagnostics(self: *const Self) void {
        self.diagnostics.printToStderr();
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "CompileOptions.getOutputPath" {
    const allocator = std.testing.allocator;

    // Test with explicit output
    {
        const opts = CompileOptions{
            .input_file = "test.php",
            .output_file = "myapp",
        };
        const path = try opts.getOutputPath(allocator);
        defer allocator.free(path);
        try std.testing.expectEqualStrings("myapp", path);
    }

    // Test deriving from input
    {
        const opts = CompileOptions{
            .input_file = "hello.php",
        };
        const path = try opts.getOutputPath(allocator);
        defer allocator.free(path);
        try std.testing.expectEqualStrings("hello", path);
    }

    // Test input without .php extension
    {
        const opts = CompileOptions{
            .input_file = "script",
        };
        const path = try opts.getOutputPath(allocator);
        defer allocator.free(path);
        try std.testing.expectEqualStrings("script", path);
    }
}

test "OptimizeLevel.fromString" {
    try std.testing.expectEqual(OptimizeLevel.debug, OptimizeLevel.fromString("debug").?);
    try std.testing.expectEqual(OptimizeLevel.release_safe, OptimizeLevel.fromString("release-safe").?);
    try std.testing.expectEqual(OptimizeLevel.release_fast, OptimizeLevel.fromString("release-fast").?);
    try std.testing.expectEqual(OptimizeLevel.release_small, OptimizeLevel.fromString("release-small").?);
    try std.testing.expect(OptimizeLevel.fromString("invalid") == null);
}

test "Target.native" {
    const target = Target.native();
    _ = target.arch.toString();
    _ = target.os.toString();
    _ = target.abi.toString();
}

test "Target.fromString" {
    const target = try Target.fromString("x86_64-linux-gnu");
    try std.testing.expectEqual(Target.Arch.x86_64, target.arch);
    try std.testing.expectEqual(Target.OS.linux, target.os);
    try std.testing.expectEqual(Target.ABI.gnu, target.abi);
}

test "Target.fromString macos" {
    const target = try Target.fromString("aarch64-macos-none");
    try std.testing.expectEqual(Target.Arch.aarch64, target.arch);
    try std.testing.expectEqual(Target.OS.macos, target.os);
    try std.testing.expectEqual(Target.ABI.none, target.abi);
}

test "Target.toTriple" {
    const allocator = std.testing.allocator;
    const target = Target{
        .arch = .x86_64,
        .os = .linux,
        .abi = .gnu,
    };
    const triple = try target.toTriple(allocator);
    defer allocator.free(triple);
    try std.testing.expectEqualStrings("x86_64-linux-gnu", triple);
}

test "CompileOptions default syntax mode is PHP" {
    const opts = CompileOptions{
        .input_file = "test.php",
    };
    try std.testing.expectEqual(SyntaxMode.php, opts.syntax_mode);
}

test "CompileOptions with Go syntax mode" {
    const opts = CompileOptions{
        .input_file = "test.php",
        .syntax_mode = .go,
    };
    try std.testing.expectEqual(SyntaxMode.go, opts.syntax_mode);
}

test "AOTCompiler initializes syntax config from options" {
    const allocator = std.testing.allocator;
    
    // Test with PHP mode
    {
        const opts = CompileOptions{
            .input_file = "test.php",
            .syntax_mode = .php,
        };
        var compiler = try AOTCompiler.init(allocator, opts);
        defer compiler.deinit();
        
        try std.testing.expectEqual(SyntaxMode.php, compiler.getSyntaxMode());
        try std.testing.expect(compiler.getSyntaxConfig().isPhpMode());
    }
    
    // Test with Go mode
    {
        const opts = CompileOptions{
            .input_file = "test.php",
            .syntax_mode = .go,
        };
        var compiler = try AOTCompiler.init(allocator, opts);
        defer compiler.deinit();
        
        try std.testing.expectEqual(SyntaxMode.go, compiler.getSyntaxMode());
        try std.testing.expect(compiler.getSyntaxConfig().isGoMode());
    }
}
