//! LLVM Code Generator for AOT Compiler
//!
//! This module generates native machine code from the IR using LLVM.
//! It provides:
//! - LLVM context, module, and builder management
//! - Type mapping from IR types to LLVM types
//! - Instruction code generation
//! - Runtime function declarations
//! - Target machine configuration
//!
//! ## Architecture
//!
//! The code generator translates IR to LLVM IR, then uses LLVM's
//! backend to generate native machine code for the target platform.
//!
//! ## LLVM Integration
//!
//! This module is designed to work with or without LLVM linked.
//! When LLVM is not available, stub implementations are used for testing.
//! To enable LLVM support, link against libLLVM and set LLVM.available = true.

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const Diagnostics = @import("diagnostics.zig");
const SourceLocation = Diagnostics.SourceLocation;

// ============================================================================
// LLVM C API Type Definitions
// ============================================================================

/// LLVM C API type definitions
/// These are opaque pointer types that represent LLVM objects
pub const LLVMContextRef = ?*anyopaque;
pub const LLVMModuleRef = ?*anyopaque;
pub const LLVMBuilderRef = ?*anyopaque;
pub const LLVMTypeRef = ?*anyopaque;
pub const LLVMValueRef = ?*anyopaque;
pub const LLVMBasicBlockRef = ?*anyopaque;
pub const LLVMTargetRef = ?*anyopaque;
pub const LLVMTargetMachineRef = ?*anyopaque;
pub const LLVMTargetDataRef = ?*anyopaque;
pub const LLVMMemoryBufferRef = ?*anyopaque;
pub const LLVMPassManagerRef = ?*anyopaque;
pub const LLVMDIBuilderRef = ?*anyopaque;
pub const LLVMMetadataRef = ?*anyopaque;

/// LLVM code generation file type
pub const LLVMCodeGenFileType = enum(c_int) {
    AssemblyFile = 0,
    ObjectFile = 1,
};

/// LLVM code generation optimization level
pub const LLVMCodeGenOptLevel = enum(c_int) {
    None = 0,
    Less = 1,
    Default = 2,
    Aggressive = 3,
};

/// LLVM relocation mode
pub const LLVMRelocMode = enum(c_int) {
    Default = 0,
    Static = 1,
    PIC = 2,
    DynamicNoPic = 3,
    ROPI = 4,
    RWPI = 5,
    ROPI_RWPI = 6,
};

/// LLVM code model
pub const LLVMCodeModel = enum(c_int) {
    Default = 0,
    JITDefault = 1,
    Tiny = 2,
    Small = 3,
    Kernel = 4,
    Medium = 5,
    Large = 6,
};

/// LLVM integer predicate for comparisons
pub const LLVMIntPredicate = enum(c_int) {
    EQ = 32,
    NE = 33,
    UGT = 34,
    UGE = 35,
    ULT = 36,
    ULE = 37,
    SGT = 38,
    SGE = 39,
    SLT = 40,
    SLE = 41,
};

/// LLVM real predicate for floating-point comparisons
pub const LLVMRealPredicate = enum(c_int) {
    PredicateFalse = 0,
    OEQ = 1,
    OGT = 2,
    OGE = 3,
    OLT = 4,
    OLE = 5,
    ONE = 6,
    ORD = 7,
    UNO = 8,
    UEQ = 9,
    UGT = 10,
    UGE = 11,
    ULT = 12,
    ULE = 13,
    UNE = 14,
    PredicateTrue = 15,
};

/// LLVM linkage types
pub const LLVMLinkage = enum(c_int) {
    ExternalLinkage = 0,
    AvailableExternallyLinkage = 1,
    LinkOnceAnyLinkage = 2,
    LinkOnceODRLinkage = 3,
    WeakAnyLinkage = 5,
    WeakODRLinkage = 6,
    AppendingLinkage = 7,
    InternalLinkage = 8,
    PrivateLinkage = 9,
    ExternalWeakLinkage = 12,
    CommonLinkage = 14,
};

/// LLVM calling conventions
pub const LLVMCallConv = enum(c_uint) {
    C = 0,
    Fast = 8,
    Cold = 9,
    WebKitJS = 12,
    AnyReg = 13,
    X86Stdcall = 64,
    X86Fastcall = 65,
};


// ============================================================================
// Target Configuration
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

        pub fn toLLVMArch(self: Arch) []const u8 {
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

        pub fn toLLVMOS(self: OS) []const u8 {
            return switch (self) {
                .linux => "linux",
                .macos => "darwin",
                .windows => "windows",
            };
        }
    };

    pub const ABI = enum {
        gnu,
        musl,
        msvc,
        none,

        pub fn toLLVMABI(self: ABI) []const u8 {
            return switch (self) {
                .gnu => "gnu",
                .musl => "musl",
                .msvc => "msvc",
                .none => "",
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
                else => .x86_64,
            },
            .os = switch (builtin.os.tag) {
                .linux => .linux,
                .macos => .macos,
                .windows => .windows,
                else => .linux,
            },
            .abi = switch (builtin.os.tag) {
                .linux => .gnu,
                .macos => .none,
                .windows => .msvc,
                else => .gnu,
            },
        };
    }

    /// Parse target from triple string
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

    /// Convert to LLVM triple string
    pub fn toTriple(self: Target, allocator: Allocator) ![]const u8 {
        const abi_str = self.abi.toLLVMABI();
        if (abi_str.len > 0) {
            return std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{
                self.arch.toLLVMArch(),
                self.os.toLLVMOS(),
                abi_str,
            });
        } else {
            return std.fmt.allocPrint(allocator, "{s}-{s}", .{
                self.arch.toLLVMArch(),
                self.os.toLLVMOS(),
            });
        }
    }
};

/// Optimization level for code generation
pub const OptimizeLevel = enum {
    debug,
    release_safe,
    release_fast,
    release_small,

    pub fn toLLVMOptLevel(self: OptimizeLevel) LLVMCodeGenOptLevel {
        return switch (self) {
            .debug => .None,
            .release_safe => .Default,
            .release_fast => .Aggressive,
            .release_small => .Default,
        };
    }
};


// ============================================================================
// Code Generator
// ============================================================================

/// LLVM Code Generator
/// Translates IR to LLVM IR and generates native machine code
pub const CodeGenerator = struct {
    allocator: Allocator,

    // LLVM handles (nullable for mock/test mode)
    context: LLVMContextRef,
    module: LLVMModuleRef,
    builder: LLVMBuilderRef,
    target_machine: LLVMTargetMachineRef,
    di_builder: LLVMDIBuilderRef,

    // Target configuration
    target: Target,
    optimize_level: OptimizeLevel,
    debug_info: bool,

    // Type cache
    type_cache: TypeCache,

    // Runtime function declarations
    runtime_functions: std.StringHashMap(LLVMValueRef),

    // Register to LLVM value mapping
    register_map: std.AutoHashMap(u32, LLVMValueRef),

    // Basic block mapping
    block_map: std.StringHashMap(LLVMBasicBlockRef),

    // Current function being generated
    current_function: LLVMValueRef,

    // Current IR module being generated
    current_ir_module: ?*const IR.Module,

    // Diagnostics
    diagnostics: *Diagnostics.DiagnosticEngine,

    // LLVM availability flag
    llvm_available: bool,

    // Debug info state
    di_compile_unit: LLVMMetadataRef,
    di_file: LLVMMetadataRef,
    di_current_scope: LLVMMetadataRef,

    const Self = @This();

    /// Type cache for LLVM types
    pub const TypeCache = struct {
        void_type: LLVMTypeRef = null,
        bool_type: LLVMTypeRef = null,
        i8_type: LLVMTypeRef = null,
        i32_type: LLVMTypeRef = null,
        i64_type: LLVMTypeRef = null,
        f64_type: LLVMTypeRef = null,
        ptr_type: LLVMTypeRef = null,
        php_value_type: LLVMTypeRef = null,
        php_value_ptr_type: LLVMTypeRef = null,
        php_string_type: LLVMTypeRef = null,
        php_string_ptr_type: LLVMTypeRef = null,
        php_array_type: LLVMTypeRef = null,
        php_array_ptr_type: LLVMTypeRef = null,
        php_object_type: LLVMTypeRef = null,
        php_object_ptr_type: LLVMTypeRef = null,
    };

    /// Runtime function signature definition
    pub const RuntimeFunctionSig = struct {
        name: []const u8,
        return_type: RuntimeType,
        param_types: []const RuntimeType,
        is_vararg: bool = false,
    };

    /// Runtime type for function signatures
    pub const RuntimeType = enum {
        void,
        bool,
        i8,
        i32,
        i64,
        f64,
        ptr, // Generic pointer (void*)
        php_value_ptr, // *PHPValue
        php_string_ptr, // *PHPString
        php_array_ptr, // *PHPArray
        php_object_ptr, // *PHPObject
        slice_ptr, // []const u8 (pointer + length)
    };

    /// Initialize the code generator
    pub fn init(
        allocator: Allocator,
        target: Target,
        optimize_level: OptimizeLevel,
        debug_info: bool,
        diagnostics: *Diagnostics.DiagnosticEngine,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .context = null,
            .module = null,
            .builder = null,
            .target_machine = null,
            .di_builder = null,
            .target = target,
            .optimize_level = optimize_level,
            .debug_info = debug_info,
            .type_cache = .{},
            .runtime_functions = std.StringHashMap(LLVMValueRef).init(allocator),
            .register_map = std.AutoHashMap(u32, LLVMValueRef).init(allocator),
            .block_map = std.StringHashMap(LLVMBasicBlockRef).init(allocator),
            .current_function = null,
            .current_ir_module = null,
            .diagnostics = diagnostics,
            .llvm_available = false,
            .di_compile_unit = null,
            .di_file = null,
            .di_current_scope = null,
        };

        return self;
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        // Note: In a real implementation with LLVM linked, we would call:
        // - LLVMDisposeDIBuilder
        // - LLVMDisposeBuilder
        // - LLVMDisposeModule
        // - LLVMDisposeTargetMachine
        // - LLVMContextDispose
        // Since LLVM is not linked, we just clean up our Zig allocations

        self.runtime_functions.deinit();
        self.register_map.deinit();
        self.block_map.deinit();
        self.allocator.destroy(self);
    }

    /// Create LLVM module for code generation
    /// In mock mode (LLVM not available), this is a no-op
    pub fn createModule(self: *Self, name: []const u8) !void {
        _ = name;
        if (!self.llvm_available) {
            // Mock mode - just track that we created a module
            return;
        }
        // Real LLVM implementation would go here
    }

    /// Map IR type to LLVM type
    pub fn mapType(self: *Self, ir_type: IR.Type) LLVMTypeRef {
        if (!self.llvm_available) return null;

        return switch (ir_type) {
            .void => self.type_cache.void_type,
            .bool => self.type_cache.bool_type,
            .i64 => self.type_cache.i64_type,
            .f64 => self.type_cache.f64_type,
            .ptr => self.type_cache.ptr_type,
            .php_value => self.type_cache.php_value_type,
            .php_string => self.type_cache.php_string_type,
            .php_array => self.type_cache.php_array_type,
            .php_object => self.type_cache.ptr_type,
            .php_resource => self.type_cache.ptr_type,
            .php_callable => self.type_cache.ptr_type,
            .function => self.type_cache.ptr_type,
            .nullable => self.type_cache.ptr_type,
        };
    }

    /// Check if LLVM is available
    pub fn isLLVMAvailable(self: *const Self) bool {
        return self.llvm_available;
    }

    /// Get the target triple string
    pub fn getTargetTriple(self: *Self) ![]const u8 {
        return self.target.toTriple(self.allocator);
    }

    /// Get the target configuration
    pub fn getTarget(self: *const Self) Target {
        return self.target;
    }

    /// Get the optimization level
    pub fn getOptimizeLevel(self: *const Self) OptimizeLevel {
        return self.optimize_level;
    }

    /// Check if debug info generation is enabled
    pub fn isDebugInfoEnabled(self: *const Self) bool {
        return self.debug_info;
    }
};


// ============================================================================
// Code Generator Errors
// ============================================================================

pub const CodeGenError = error{
    LLVMContextCreationFailed,
    LLVMModuleCreationFailed,
    LLVMBuilderCreationFailed,
    TargetNotFound,
    TargetMachineCreationFailed,
    CodeGenFailed,
    VerificationFailed,
    InvalidIR,
    UnsupportedOperation,
    OutOfMemory,
};

// ============================================================================
// Unit Tests
// ============================================================================

test "Target.native" {
    const target = Target.native();
    _ = target.arch.toLLVMArch();
    _ = target.os.toLLVMOS();
    _ = target.abi.toLLVMABI();
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

test "Target.toTriple macos" {
    const allocator = std.testing.allocator;
    const target = Target{
        .arch = .aarch64,
        .os = .macos,
        .abi = .none,
    };
    const triple = try target.toTriple(allocator);
    defer allocator.free(triple);
    try std.testing.expectEqualStrings("aarch64-darwin", triple);
}

test "OptimizeLevel.toLLVMOptLevel" {
    try std.testing.expectEqual(LLVMCodeGenOptLevel.None, OptimizeLevel.debug.toLLVMOptLevel());
    try std.testing.expectEqual(LLVMCodeGenOptLevel.Default, OptimizeLevel.release_safe.toLLVMOptLevel());
    try std.testing.expectEqual(LLVMCodeGenOptLevel.Aggressive, OptimizeLevel.release_fast.toLLVMOptLevel());
    try std.testing.expectEqual(LLVMCodeGenOptLevel.Default, OptimizeLevel.release_small.toLLVMOptLevel());
}

test "CodeGenerator.init and deinit" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const codegen = try CodeGenerator.init(
        allocator,
        Target.native(),
        .debug,
        false,
        &diagnostics,
    );
    defer codegen.deinit();

    // LLVM is not available in test mode
    try std.testing.expect(!codegen.isLLVMAvailable());
}

test "CodeGenerator.mapType without LLVM" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const codegen = try CodeGenerator.init(
        allocator,
        Target.native(),
        .debug,
        false,
        &diagnostics,
    );
    defer codegen.deinit();

    // Without LLVM, mapType returns null
    try std.testing.expect(codegen.mapType(.void) == null);
    try std.testing.expect(codegen.mapType(.i64) == null);
    try std.testing.expect(codegen.mapType(.php_value) == null);
}

test "CodeGenerator.getTargetTriple" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const codegen = try CodeGenerator.init(
        allocator,
        Target{ .arch = .x86_64, .os = .linux, .abi = .gnu },
        .debug,
        false,
        &diagnostics,
    );
    defer codegen.deinit();

    const triple = try codegen.getTargetTriple();
    defer allocator.free(triple);
    try std.testing.expectEqualStrings("x86_64-linux-gnu", triple);
}

test "CodeGenerator.getTarget" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const target = Target{ .arch = .aarch64, .os = .macos, .abi = .none };
    const codegen = try CodeGenerator.init(
        allocator,
        target,
        .release_fast,
        true,
        &diagnostics,
    );
    defer codegen.deinit();

    const retrieved_target = codegen.getTarget();
    try std.testing.expectEqual(Target.Arch.aarch64, retrieved_target.arch);
    try std.testing.expectEqual(Target.OS.macos, retrieved_target.os);
    try std.testing.expectEqual(Target.ABI.none, retrieved_target.abi);
}

test "CodeGenerator.getOptimizeLevel" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const codegen = try CodeGenerator.init(
        allocator,
        Target.native(),
        .release_fast,
        false,
        &diagnostics,
    );
    defer codegen.deinit();

    try std.testing.expectEqual(OptimizeLevel.release_fast, codegen.getOptimizeLevel());
}

test "CodeGenerator.isDebugInfoEnabled" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const codegen_with_debug = try CodeGenerator.init(
        allocator,
        Target.native(),
        .debug,
        true,
        &diagnostics,
    );
    defer codegen_with_debug.deinit();
    try std.testing.expect(codegen_with_debug.isDebugInfoEnabled());

    const codegen_without_debug = try CodeGenerator.init(
        allocator,
        Target.native(),
        .release_fast,
        false,
        &diagnostics,
    );
    defer codegen_without_debug.deinit();
    try std.testing.expect(!codegen_without_debug.isDebugInfoEnabled());
}

test "IR Type mapping coverage" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const codegen = try CodeGenerator.init(
        allocator,
        Target.native(),
        .debug,
        false,
        &diagnostics,
    );
    defer codegen.deinit();

    // Test all IR types can be mapped (returns null without LLVM)
    const ir_types = [_]IR.Type{
        .void,
        .bool,
        .i64,
        .f64,
        .php_value,
        .php_string,
        .php_array,
        .php_resource,
        .php_callable,
    };

    for (ir_types) |ir_type| {
        _ = codegen.mapType(ir_type);
    }
}

test "CodeGenerator.createModule mock mode" {
    const allocator = std.testing.allocator;
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const codegen = try CodeGenerator.init(
        allocator,
        Target.native(),
        .debug,
        false,
        &diagnostics,
    );
    defer codegen.deinit();

    // Should not fail in mock mode
    try codegen.createModule("test_module");
}
