//! AOT (Ahead-of-Time) Compiler Module
//!
//! This module provides functionality to compile PHP source code directly
//! into native binary executables without requiring a PHP runtime.
//!
//! ## Architecture
//!
//! The AOT compiler pipeline:
//! ```
//! PHP Source → Lexer → Parser → AST → Type Inference → IR Generation →
//! LLVM IR → Machine Code → Linker → Executable
//! ```
//!
//! ## Components
//!
//! - `compiler.zig`: Main AOT compiler entry point
//! - `diagnostics.zig`: Error/warning collection and reporting
//! - `ir.zig`: Intermediate Representation definitions (future)
//! - `ir_generator.zig`: AST to IR conversion (future)
//! - `type_inference.zig`: Static type inference (future)
//! - `codegen.zig`: LLVM code generation (future)
//! - `linker.zig`: Static linking (future)
//! - `runtime_lib.zig`: Runtime library interface (future)

const std = @import("std");

// Re-export public interfaces
pub const Diagnostics = @import("diagnostics.zig");
pub const DiagnosticEngine = Diagnostics.DiagnosticEngine;
pub const Diagnostic = Diagnostics.Diagnostic;
pub const Severity = Diagnostics.Severity;
pub const SourceLocation = Diagnostics.SourceLocation;

// IR module
pub const IR = @import("ir.zig");
pub const Module = IR.Module;
pub const Function = IR.Function;
pub const BasicBlock = IR.BasicBlock;
pub const Instruction = IR.Instruction;
pub const Register = IR.Register;
pub const Type = IR.Type;
pub const Terminator = IR.Terminator;
pub const IRPrinter = IR.IRPrinter;
pub const serializeModule = IR.serializeModule;

// Symbol Table module
pub const SymbolTableMod = @import("symbol_table.zig");
pub const SymbolTable = SymbolTableMod.SymbolTable;
pub const Symbol = SymbolTableMod.Symbol;
pub const Scope = SymbolTableMod.Scope;
pub const InferredType = SymbolTableMod.InferredType;
pub const ConcreteType = SymbolTableMod.ConcreteType;
pub const SymbolKind = SymbolTableMod.SymbolKind;

// Type Inference module
pub const TypeInferenceMod = @import("type_inference.zig");
pub const TypeInferencer = TypeInferenceMod.TypeInferencer;
pub const TypeContext = TypeInferenceMod.TypeContext;
pub const InferenceNode = TypeInferenceMod.InferenceNode;
pub const NodeTag = TypeInferenceMod.NodeTag;
pub const OperatorKind = TypeInferenceMod.OperatorKind;
pub const getBuiltinReturnType = TypeInferenceMod.getBuiltinReturnType;

// IR Generator module
pub const IRGeneratorMod = @import("ir_generator.zig");
pub const IRGenerator = IRGeneratorMod.IRGenerator;

// Property tests (included for test runs)
test {
    _ = @import("test_type_inference_property.zig");
    _ = @import("test_ir_generator_property.zig");
}

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
    /// Verbose output during compilation
    verbose: bool = false,
};

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
};

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
    pub fn toTriple(self: Target, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{
            self.arch.toString(),
            self.os.toString(),
            self.abi.toString(),
        });
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

// Tests
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

test "OptimizeLevel.fromString" {
    try std.testing.expectEqual(OptimizeLevel.debug, OptimizeLevel.fromString("debug").?);
    try std.testing.expectEqual(OptimizeLevel.release_fast, OptimizeLevel.fromString("release-fast").?);
    try std.testing.expect(OptimizeLevel.fromString("invalid") == null);
}
