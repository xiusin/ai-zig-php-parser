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
        void_type,
        bool_type,
        i8_type,
        i32_type,
        i64_type,
        f64_type,
        ptr_type,
        php_value_ptr,
        php_string_ptr,
        php_array_ptr,
        php_object_ptr,
    };

    /// All runtime function signatures
    pub const runtime_function_signatures = [_]RuntimeFunctionSig{
        // Value creation functions
        .{ .name = "php_value_create_null", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{} },
        .{ .name = "php_value_create_bool", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.bool_type} },
        .{ .name = "php_value_create_int", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.i64_type} },
        .{ .name = "php_value_create_float", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.f64_type} },
        .{ .name = "php_value_create_string", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .ptr_type, .i64_type } },
        .{ .name = "php_value_create_array", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{} },
        .{ .name = "php_value_create_object", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .ptr_type, .i64_type } },

        // Type conversion functions
        .{ .name = "php_value_get_type", .return_type = .i8_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_value_to_int", .return_type = .i64_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_value_to_float", .return_type = .f64_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_value_to_bool", .return_type = .bool_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_value_to_string", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_value_clone", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },

        // GC functions
        .{ .name = "php_gc_retain", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_gc_release", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_gc_get_ref_count", .return_type = .i32_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_gc_is_shared", .return_type = .bool_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_gc_copy_on_write", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },

        // Array functions
        .{ .name = "php_array_create", .return_type = .php_array_ptr, .param_types = &[_]RuntimeType{} },
        .{ .name = "php_array_create_with_capacity", .return_type = .php_array_ptr, .param_types = &[_]RuntimeType{.i64_type} },
        .{ .name = "php_array_get_int", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_array_ptr, .i64_type } },
        .{ .name = "php_array_get_string", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_string_ptr } },
        .{ .name = "php_array_get", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_value_ptr } },
        .{ .name = "php_array_set_int", .return_type = .void_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .i64_type, .php_value_ptr } },
        .{ .name = "php_array_set_string", .return_type = .void_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_string_ptr, .php_value_ptr } },
        .{ .name = "php_array_set", .return_type = .void_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_value_ptr, .php_value_ptr } },
        .{ .name = "php_array_push", .return_type = .void_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_value_ptr } },
        .{ .name = "php_array_count", .return_type = .i64_type, .param_types = &[_]RuntimeType{.php_array_ptr} },
        .{ .name = "php_array_key_exists", .return_type = .bool_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_value_ptr } },
        .{ .name = "php_array_key_exists_int", .return_type = .bool_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .i64_type } },
        .{ .name = "php_array_unset", .return_type = .void_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_value_ptr } },
        .{ .name = "php_array_unset_int", .return_type = .void_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .i64_type } },
        .{ .name = "php_array_keys", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_array_ptr} },
        .{ .name = "php_array_values", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_array_ptr} },
        .{ .name = "php_array_merge", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_array_ptr } },
        .{ .name = "php_array_is_empty", .return_type = .bool_type, .param_types = &[_]RuntimeType{.php_array_ptr} },
        .{ .name = "php_array_first", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_array_ptr} },
        .{ .name = "php_array_last", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_array_ptr} },
    };

    /// More runtime function signatures (string, I/O, builtins)
    pub const runtime_function_signatures_2 = [_]RuntimeFunctionSig{
        // String functions
        .{ .name = "php_string_concat", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_value_ptr, .php_value_ptr } },
        .{ .name = "php_string_length", .return_type = .i64_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_string_len", .return_type = .i64_type, .param_types = &[_]RuntimeType{.php_string_ptr} },
        .{ .name = "php_string_substr", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_value_ptr, .i64_type, .i64_type } },
        .{ .name = "php_string_strpos", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_value_ptr, .php_value_ptr, .i64_type } },
        .{ .name = "php_string_strtoupper", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },

        // I/O functions
        .{ .name = "php_echo", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_print", .return_type = .i64_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_println", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },

        // Builtin functions
        .{ .name = "php_builtin_strlen", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_count", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_var_dump", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_gettype", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_is_null", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_is_bool", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_is_int", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_is_float", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_is_numeric", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_is_string", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_is_array", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_is_object", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_empty", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_isset", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_intval", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_floatval", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_strval", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_boolval", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_abs", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_floor", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_ceil", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_builtin_round", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_value_ptr, .i64_type } },

        // Exception functions
        .{ .name = "php_throw", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
        .{ .name = "php_throw_message", .return_type = .void_type, .param_types = &[_]RuntimeType{ .ptr_type, .i64_type } },
        .{ .name = "php_print_stack_trace", .return_type = .void_type, .param_types = &[_]RuntimeType{} },
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
        self.runtime_functions.deinit();
        self.register_map.deinit();
        self.block_map.deinit();
        self.allocator.destroy(self);
    }

    /// Create LLVM module for code generation
    pub fn createModule(self: *Self, name: []const u8) !void {
        _ = name;
        if (!self.llvm_available) {
            return;
        }
    }

    /// Initialize LLVM types for PHPValue and other runtime structures
    /// PHPValue layout: tag (u8) + padding (3 bytes) + ref_count (u32) + data (16 bytes) = 24 bytes
    pub fn initializeTypes(self: *Self) void {
        if (!self.llvm_available) return;
        // In real LLVM mode, we would create struct types here
        // For now, this is a stub
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
            .php_value => self.type_cache.php_value_ptr_type,
            .php_string => self.type_cache.php_string_ptr_type,
            .php_array => self.type_cache.php_array_ptr_type,
            .php_object => self.type_cache.php_object_ptr_type,
            .php_resource => self.type_cache.ptr_type,
            .php_callable => self.type_cache.ptr_type,
            .function => self.type_cache.ptr_type,
            .nullable => self.type_cache.ptr_type,
        };
    }

    /// Map runtime type to LLVM type
    pub fn mapRuntimeType(self: *Self, rt_type: RuntimeType) LLVMTypeRef {
        if (!self.llvm_available) return null;

        return switch (rt_type) {
            .void_type => self.type_cache.void_type,
            .bool_type => self.type_cache.bool_type,
            .i8_type => self.type_cache.i8_type,
            .i32_type => self.type_cache.i32_type,
            .i64_type => self.type_cache.i64_type,
            .f64_type => self.type_cache.f64_type,
            .ptr_type => self.type_cache.ptr_type,
            .php_value_ptr => self.type_cache.php_value_ptr_type,
            .php_string_ptr => self.type_cache.php_string_ptr_type,
            .php_array_ptr => self.type_cache.php_array_ptr_type,
            .php_object_ptr => self.type_cache.php_object_ptr_type,
        };
    }

    /// Declare all runtime functions
    pub fn declareRuntimeFunctions(self: *Self) !void {
        // Declare functions from first signature list
        for (runtime_function_signatures) |sig| {
            try self.declareRuntimeFunction(sig);
        }

        // Declare functions from second signature list
        for (runtime_function_signatures_2) |sig| {
            try self.declareRuntimeFunction(sig);
        }
    }

    /// Declare a single runtime function
    fn declareRuntimeFunction(self: *Self, sig: RuntimeFunctionSig) !void {
        // In real LLVM mode, we would:
        // 1. Create parameter types array
        // 2. Create function type with LLVMFunctionType
        // 3. Add function to module with LLVMAddFunction
        // 4. Set calling convention
        // 5. Store in runtime_functions map

        // Store null as placeholder (or real LLVM value when available)
        try self.runtime_functions.put(sig.name, null);
    }

    /// Generate LLVM IR from an IR module
    pub fn generateModule(self: *Self, ir_module: *const IR.Module) !void {
        self.current_ir_module = ir_module;

        // Create LLVM module
        try self.createModule(ir_module.name);

        // Initialize types
        self.initializeTypes();

        // Declare runtime functions
        try self.declareRuntimeFunctions();

        // Generate code for each function
        for (ir_module.functions.items) |func| {
            try self.generateFunction(func);
        }

        self.current_ir_module = null;
    }

    /// Generate LLVM IR for a function
    pub fn generateFunction(self: *Self, func: *const IR.Function) !void {
        if (!self.llvm_available) return;

        // Clear register and block maps for new function
        self.register_map.clearRetainingCapacity();
        self.block_map.clearRetainingCapacity();

        // In real LLVM mode:
        // 1. Create function type from parameters and return type
        // 2. Add function to module
        // 3. Create entry block
        // 4. Generate code for each basic block
        // 5. Set up phi nodes

        for (func.blocks.items) |block| {
            try self.generateBasicBlock(block);
        }
    }

    /// Generate LLVM IR for a basic block
    pub fn generateBasicBlock(self: *Self, block: *const IR.BasicBlock) !void {
        if (!self.llvm_available) return;

        // In real LLVM mode:
        // 1. Create LLVM basic block
        // 2. Position builder at end of block
        // 3. Generate each instruction
        // 4. Generate terminator

        for (block.instructions.items) |inst| {
            try self.generateInstruction(inst);
        }

        if (block.terminator) |term| {
            try self.generateTerminator(term);
        }
    }

    /// Generate LLVM IR for an instruction
    pub fn generateInstruction(self: *Self, inst: *const IR.Instruction) !void {
        if (!self.llvm_available) return;

        const result = switch (inst.op) {
            // Arithmetic operations
            .add => |op| try self.buildArithmetic(.add, op.lhs, op.rhs),
            .sub => |op| try self.buildArithmetic(.sub, op.lhs, op.rhs),
            .mul => |op| try self.buildArithmetic(.mul, op.lhs, op.rhs),
            .div => |op| try self.buildArithmetic(.div, op.lhs, op.rhs),
            .mod => |op| try self.buildArithmetic(.mod, op.lhs, op.rhs),
            .neg => |op| try self.buildUnary(.neg, op.operand),
            .pow => |op| try self.buildArithmetic(.pow, op.lhs, op.rhs),

            // Bitwise operations
            .bit_and => |op| try self.buildArithmetic(.bit_and, op.lhs, op.rhs),
            .bit_or => |op| try self.buildArithmetic(.bit_or, op.lhs, op.rhs),
            .bit_xor => |op| try self.buildArithmetic(.bit_xor, op.lhs, op.rhs),
            .bit_not => |op| try self.buildUnary(.bit_not, op.operand),
            .shl => |op| try self.buildArithmetic(.shl, op.lhs, op.rhs),
            .shr => |op| try self.buildArithmetic(.shr, op.lhs, op.rhs),

            // Comparison operations
            .eq => |op| try self.buildComparison(.eq, op.lhs, op.rhs),
            .ne => |op| try self.buildComparison(.ne, op.lhs, op.rhs),
            .lt => |op| try self.buildComparison(.lt, op.lhs, op.rhs),
            .le => |op| try self.buildComparison(.le, op.lhs, op.rhs),
            .gt => |op| try self.buildComparison(.gt, op.lhs, op.rhs),
            .ge => |op| try self.buildComparison(.ge, op.lhs, op.rhs),
            .identical => |op| try self.buildComparison(.identical, op.lhs, op.rhs),
            .not_identical => |op| try self.buildComparison(.not_identical, op.lhs, op.rhs),
            .spaceship => |op| try self.buildComparison(.spaceship, op.lhs, op.rhs),

            // Logical operations
            .and_ => |op| try self.buildArithmetic(.and_, op.lhs, op.rhs),
            .or_ => |op| try self.buildArithmetic(.or_, op.lhs, op.rhs),
            .not => |op| try self.buildUnary(.not, op.operand),

            // Memory operations
            .alloca => |op| try self.buildAlloca(op.type_, op.count),
            .load => |op| try self.buildLoad(op.ptr, op.type_),
            .store => |op| try self.buildStore(op.ptr, op.value),

            // Constants
            .const_int => |val| try self.buildConstInt(val),
            .const_float => |val| try self.buildConstFloat(val),
            .const_bool => |val| try self.buildConstBool(val),
            .const_string => |id| try self.buildConstString(id),
            .const_null => try self.buildConstNull(),

            // Function calls
            .call => |op| try self.buildCall(op.func_name, op.args, op.return_type),
            .call_indirect => |op| try self.buildCallIndirect(op.func_ptr, op.args, op.return_type),

            // Type operations
            .cast => |op| try self.buildCast(op.value, op.from_type, op.to_type),
            .type_check => |op| try self.buildTypeCheck(op.value, op.expected_type),
            .get_type => |op| try self.buildGetType(op.operand),

            // Array operations
            .array_new => |op| try self.buildArrayNew(op.capacity),
            .array_get => |op| try self.buildArrayGet(op.array, op.key),
            .array_set => |op| try self.buildArraySet(op.array, op.key, op.value),
            .array_push => |op| try self.buildArrayPush(op.array, op.value),
            .array_count => |op| try self.buildArrayCount(op.operand),
            .array_key_exists => |op| try self.buildArrayKeyExists(op.array, op.key),
            .array_unset => |op| try self.buildArrayUnset(op.array, op.key),

            // String operations
            .concat => |op| try self.buildConcat(op.lhs, op.rhs),
            .strlen => |op| try self.buildStrlen(op.operand),
            .interpolate => |op| try self.buildInterpolate(op.parts),

            // Object operations
            .new_object => |op| try self.buildNewObject(op.class_name, op.args),
            .property_get => |op| try self.buildPropertyGet(op.object, op.property_name),
            .property_set => |op| try self.buildPropertySet(op.object, op.property_name, op.value),
            .method_call => |op| try self.buildMethodCall(op.object, op.method_name, op.args),
            .clone => |op| try self.buildClone(op.operand),
            .instanceof => |op| try self.buildInstanceof(op.object, op.class_name),

            // PHP value operations
            .box => |op| try self.buildBox(op.value, op.from_type),
            .unbox => |op| try self.buildUnbox(op.value, op.to_type),
            .retain => |op| try self.buildRetain(op.operand),
            .release => |op| try self.buildRelease(op.operand),

            // Control flow
            .phi => |op| try self.buildPhi(op.incoming),
            .select => |op| try self.buildSelect(op.cond, op.then_value, op.else_value),

            // Exception handling
            .try_begin => try self.buildTryBegin(),
            .try_end => try self.buildTryEnd(),
            .catch_ => |op| try self.buildCatch(op.exception_type),
            .get_exception => try self.buildGetException(),
            .clear_exception => try self.buildClearException(),

            // Debug
            .debug_print => |op| try self.buildDebugPrint(op.operand),
        };

        // Store result in register map if instruction has a result
        if (inst.result) |reg| {
            try self.register_map.put(reg.id, result);
        }

        // Emit debug location if enabled
        if (self.debug_info) {
            self.emitDebugLocation(inst.location);
        }
    }

    /// Generate LLVM IR for a terminator
    pub fn generateTerminator(self: *Self, term: IR.Terminator) !void {
        if (!self.llvm_available) return;

        switch (term) {
            .ret => |val| {
                if (val) |reg| {
                    const llvm_val = self.register_map.get(reg.id);
                    _ = llvm_val;
                    // LLVMBuildRet(self.builder, llvm_val)
                } else {
                    // LLVMBuildRetVoid(self.builder)
                }
            },
            .br => |block| {
                const llvm_block = self.block_map.get(block.label);
                _ = llvm_block;
                // LLVMBuildBr(self.builder, llvm_block)
            },
            .cond_br => |cb| {
                const cond_val = self.register_map.get(cb.cond.id);
                const then_block = self.block_map.get(cb.then_block.label);
                const else_block = self.block_map.get(cb.else_block.label);
                _ = cond_val;
                _ = then_block;
                _ = else_block;
                // LLVMBuildCondBr(self.builder, cond_val, then_block, else_block)
            },
            .switch_ => |sw| {
                const switch_val = self.register_map.get(sw.value.id);
                const default_block = self.block_map.get(sw.default.label);
                _ = switch_val;
                _ = default_block;
                // Build switch instruction with cases
            },
            .unreachable_ => {
                // LLVMBuildUnreachable(self.builder)
            },
            .throw => |reg| {
                const exc_val = self.register_map.get(reg.id);
                _ = exc_val;
                // Call php_throw and then unreachable
            },
        }
    }

    // ========================================================================
    // Arithmetic Operations
    // ========================================================================

    const ArithOp = enum { add, sub, mul, div, mod, pow, bit_and, bit_or, bit_xor, shl, shr, and_, or_ };

    fn buildArithmetic(self: *Self, op: ArithOp, lhs: IR.Register, rhs: IR.Register) !LLVMValueRef {
        _ = self;
        _ = op;
        _ = lhs;
        _ = rhs;
        // In real LLVM mode, build appropriate instruction based on op
        return null;
    }

    const UnaryOp = enum { neg, bit_not, not };

    fn buildUnary(self: *Self, op: UnaryOp, operand: IR.Register) !LLVMValueRef {
        _ = self;
        _ = op;
        _ = operand;
        return null;
    }

    // ========================================================================
    // Comparison Operations
    // ========================================================================

    const CmpOp = enum { eq, ne, lt, le, gt, ge, identical, not_identical, spaceship };

    fn buildComparison(self: *Self, op: CmpOp, lhs: IR.Register, rhs: IR.Register) !LLVMValueRef {
        _ = self;
        _ = op;
        _ = lhs;
        _ = rhs;
        return null;
    }

    // ========================================================================
    // Memory Operations
    // ========================================================================

    fn buildAlloca(self: *Self, type_: IR.Type, count: u32) !LLVMValueRef {
        _ = self;
        _ = type_;
        _ = count;
        return null;
    }

    fn buildLoad(self: *Self, ptr: IR.Register, type_: IR.Type) !LLVMValueRef {
        _ = self;
        _ = ptr;
        _ = type_;
        return null;
    }

    fn buildStore(self: *Self, ptr: IR.Register, value: IR.Register) !LLVMValueRef {
        _ = self;
        _ = ptr;
        _ = value;
        return null;
    }

    // ========================================================================
    // Constant Operations
    // ========================================================================

    fn buildConstInt(self: *Self, val: i64) !LLVMValueRef {
        _ = self;
        _ = val;
        return null;
    }

    fn buildConstFloat(self: *Self, val: f64) !LLVMValueRef {
        _ = self;
        _ = val;
        return null;
    }

    fn buildConstBool(self: *Self, val: bool) !LLVMValueRef {
        _ = self;
        _ = val;
        return null;
    }

    fn buildConstString(self: *Self, id: u32) !LLVMValueRef {
        _ = self;
        _ = id;
        return null;
    }

    fn buildConstNull(self: *Self) !LLVMValueRef {
        _ = self;
        return null;
    }

    // ========================================================================
    // Function Call Operations
    // ========================================================================

    fn buildCall(self: *Self, func_name: []const u8, args: []const IR.Register, return_type: IR.Type) !LLVMValueRef {
        _ = self;
        _ = func_name;
        _ = args;
        _ = return_type;
        return null;
    }

    fn buildCallIndirect(self: *Self, func_ptr: IR.Register, args: []const IR.Register, return_type: IR.Type) !LLVMValueRef {
        _ = self;
        _ = func_ptr;
        _ = args;
        _ = return_type;
        return null;
    }

    // ========================================================================
    // Type Operations
    // ========================================================================

    fn buildCast(self: *Self, value: IR.Register, from_type: IR.Type, to_type: IR.Type) !LLVMValueRef {
        _ = self;
        _ = value;
        _ = from_type;
        _ = to_type;
        return null;
    }

    fn buildTypeCheck(self: *Self, value: IR.Register, expected_type: IR.Type) !LLVMValueRef {
        _ = self;
        _ = value;
        _ = expected_type;
        return null;
    }

    fn buildGetType(self: *Self, operand: IR.Register) !LLVMValueRef {
        _ = self;
        _ = operand;
        return null;
    }

    // ========================================================================
    // Array Operations
    // ========================================================================

    fn buildArrayNew(self: *Self, capacity: u32) !LLVMValueRef {
        _ = self;
        _ = capacity;
        return null;
    }

    fn buildArrayGet(self: *Self, array: IR.Register, key: IR.Register) !LLVMValueRef {
        _ = self;
        _ = array;
        _ = key;
        return null;
    }

    fn buildArraySet(self: *Self, array: IR.Register, key: IR.Register, value: IR.Register) !LLVMValueRef {
        _ = self;
        _ = array;
        _ = key;
        _ = value;
        return null;
    }

    fn buildArrayPush(self: *Self, array: IR.Register, value: IR.Register) !LLVMValueRef {
        _ = self;
        _ = array;
        _ = value;
        return null;
    }

    fn buildArrayCount(self: *Self, operand: IR.Register) !LLVMValueRef {
        _ = self;
        _ = operand;
        return null;
    }

    fn buildArrayKeyExists(self: *Self, array: IR.Register, key: IR.Register) !LLVMValueRef {
        _ = self;
        _ = array;
        _ = key;
        return null;
    }

    fn buildArrayUnset(self: *Self, array: IR.Register, key: IR.Register) !LLVMValueRef {
        _ = self;
        _ = array;
        _ = key;
        return null;
    }

    // ========================================================================
    // String Operations
    // ========================================================================

    fn buildConcat(self: *Self, lhs: IR.Register, rhs: IR.Register) !LLVMValueRef {
        _ = self;
        _ = lhs;
        _ = rhs;
        return null;
    }

    fn buildStrlen(self: *Self, operand: IR.Register) !LLVMValueRef {
        _ = self;
        _ = operand;
        return null;
    }

    fn buildInterpolate(self: *Self, parts: []const IR.Register) !LLVMValueRef {
        _ = self;
        _ = parts;
        return null;
    }

    // ========================================================================
    // Object Operations
    // ========================================================================

    fn buildNewObject(self: *Self, class_name: []const u8, args: []const IR.Register) !LLVMValueRef {
        _ = self;
        _ = class_name;
        _ = args;
        return null;
    }

    fn buildPropertyGet(self: *Self, object: IR.Register, property_name: []const u8) !LLVMValueRef {
        _ = self;
        _ = object;
        _ = property_name;
        return null;
    }

    fn buildPropertySet(self: *Self, object: IR.Register, property_name: []const u8, value: IR.Register) !LLVMValueRef {
        _ = self;
        _ = object;
        _ = property_name;
        _ = value;
        return null;
    }

    fn buildMethodCall(self: *Self, object: IR.Register, method_name: []const u8, args: []const IR.Register) !LLVMValueRef {
        _ = self;
        _ = object;
        _ = method_name;
        _ = args;
        return null;
    }

    fn buildClone(self: *Self, operand: IR.Register) !LLVMValueRef {
        _ = self;
        _ = operand;
        return null;
    }

    fn buildInstanceof(self: *Self, object: IR.Register, class_name: []const u8) !LLVMValueRef {
        _ = self;
        _ = object;
        _ = class_name;
        return null;
    }

    // ========================================================================
    // PHP Value Operations
    // ========================================================================

    fn buildBox(self: *Self, value: IR.Register, from_type: IR.Type) !LLVMValueRef {
        _ = self;
        _ = value;
        _ = from_type;
        return null;
    }

    fn buildUnbox(self: *Self, value: IR.Register, to_type: IR.Type) !LLVMValueRef {
        _ = self;
        _ = value;
        _ = to_type;
        return null;
    }

    fn buildRetain(self: *Self, operand: IR.Register) !LLVMValueRef {
        _ = self;
        _ = operand;
        return null;
    }

    fn buildRelease(self: *Self, operand: IR.Register) !LLVMValueRef {
        _ = self;
        _ = operand;
        return null;
    }

    // ========================================================================
    // Control Flow Operations
    // ========================================================================

    fn buildPhi(self: *Self, incoming: []const IR.Instruction.PhiIncoming) !LLVMValueRef {
        _ = self;
        _ = incoming;
        return null;
    }

    fn buildSelect(self: *Self, cond: IR.Register, then_value: IR.Register, else_value: IR.Register) !LLVMValueRef {
        _ = self;
        _ = cond;
        _ = then_value;
        _ = else_value;
        return null;
    }

    // ========================================================================
    // Exception Handling Operations
    // ========================================================================

    fn buildTryBegin(self: *Self) !LLVMValueRef {
        _ = self;
        return null;
    }

    fn buildTryEnd(self: *Self) !LLVMValueRef {
        _ = self;
        return null;
    }

    fn buildCatch(self: *Self, exception_type: ?[]const u8) !LLVMValueRef {
        _ = self;
        _ = exception_type;
        return null;
    }

    fn buildGetException(self: *Self) !LLVMValueRef {
        _ = self;
        return null;
    }

    fn buildClearException(self: *Self) !LLVMValueRef {
        _ = self;
        return null;
    }

    // ========================================================================
    // Debug Operations
    // ========================================================================

    fn buildDebugPrint(self: *Self, operand: IR.Register) !LLVMValueRef {
        _ = self;
        _ = operand;
        return null;
    }

    // ========================================================================
    // Safety Check Generation
    // ========================================================================

    /// Generate array bounds check
    pub fn generateArrayBoundsCheck(self: *Self, array: IR.Register, index: IR.Register) !void {
        if (!self.llvm_available) return;
        _ = array;
        _ = index;
        // In real LLVM mode:
        // 1. Get array length
        // 2. Compare index with length
        // 3. Branch to error handler if out of bounds
    }

    /// Generate null pointer check
    pub fn generateNullCheck(self: *Self, ptr: IR.Register) !void {
        if (!self.llvm_available) return;
        _ = ptr;
        // In real LLVM mode:
        // 1. Compare pointer with null
        // 2. Branch to error handler if null
    }

    /// Generate type check for dynamic values
    pub fn generateDynamicTypeCheck(self: *Self, value: IR.Register, expected_tag: u8) !void {
        if (!self.llvm_available) return;
        _ = value;
        _ = expected_tag;
        // In real LLVM mode:
        // 1. Load type tag from PHPValue
        // 2. Compare with expected tag
        // 3. Branch to error handler if mismatch
    }

    // ========================================================================
    // Debug Info Generation (DWARF)
    // ========================================================================

    /// Initialize debug info builder
    pub fn initDebugInfo(self: *Self, source_file: []const u8, source_dir: []const u8) !void {
        if (!self.llvm_available or !self.debug_info) return;
        _ = source_file;
        _ = source_dir;
        // In real LLVM mode:
        // 1. Create DIBuilder
        // 2. Create compile unit
        // 3. Create file descriptor
    }

    /// Emit debug location for current instruction
    pub fn emitDebugLocation(self: *Self, loc: SourceLocation) void {
        if (!self.llvm_available or !self.debug_info) return;
        _ = loc;
        // In real LLVM mode:
        // 1. Create debug location metadata
        // 2. Set current debug location on builder
    }

    /// Create debug info for a function
    pub fn createFunctionDebugInfo(self: *Self, func: *const IR.Function) !void {
        if (!self.llvm_available or !self.debug_info) return;
        _ = func;
        // In real LLVM mode:
        // 1. Create subroutine type
        // 2. Create subprogram descriptor
        // 3. Attach to function
    }

    /// Create debug info for a local variable
    pub fn createLocalVariableDebugInfo(self: *Self, name: []const u8, type_: IR.Type, loc: SourceLocation) !void {
        if (!self.llvm_available or !self.debug_info) return;
        _ = name;
        _ = type_;
        _ = loc;
        // In real LLVM mode:
        // 1. Create local variable descriptor
        // 2. Insert declare intrinsic
    }

    /// Finalize debug info
    pub fn finalizeDebugInfo(self: *Self) void {
        if (!self.llvm_available or !self.debug_info) return;
        // In real LLVM mode:
        // DIBuilderFinalize(self.di_builder)
    }

    // ========================================================================
    // Object Code Emission
    // ========================================================================

    /// Emit object code to a file
    pub fn emitObjectCode(self: *Self, output_path: []const u8) !void {
        if (!self.llvm_available) return;
        _ = output_path;
        // In real LLVM mode:
        // 1. Verify module
        // 2. Run optimization passes based on optimize_level
        // 3. Emit object code using target machine
    }

    /// Emit assembly code to a file
    pub fn emitAssembly(self: *Self, output_path: []const u8) !void {
        if (!self.llvm_available) return;
        _ = output_path;
        // In real LLVM mode:
        // 1. Verify module
        // 2. Run optimization passes
        // 3. Emit assembly using target machine
    }

    /// Emit LLVM IR to a file (for debugging)
    pub fn emitLLVMIR(self: *Self, output_path: []const u8) !void {
        if (!self.llvm_available) return;
        _ = output_path;
        // In real LLVM mode:
        // LLVMPrintModuleToFile(self.module, output_path, &error_msg)
    }

    // ========================================================================
    // Utility Methods
    // ========================================================================

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

    /// Get a runtime function by name
    pub fn getRuntimeFunction(self: *const Self, name: []const u8) ?LLVMValueRef {
        return self.runtime_functions.get(name);
    }

    /// Get the number of declared runtime functions
    pub fn getRuntimeFunctionCount(self: *const Self) usize {
        return self.runtime_functions.count();
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
    RuntimeFunctionNotFound,
    InvalidType,
    InvalidInstruction,
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

    try codegen.createModule("test_module");
}

test "CodeGenerator.declareRuntimeFunctions" {
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

    try codegen.declareRuntimeFunctions();

    // Verify runtime functions were registered
    const expected_count = CodeGenerator.runtime_function_signatures.len + CodeGenerator.runtime_function_signatures_2.len;
    try std.testing.expectEqual(expected_count, codegen.getRuntimeFunctionCount());
}

test "CodeGenerator.mapRuntimeType" {
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

    // Without LLVM, all types map to null
    try std.testing.expect(codegen.mapRuntimeType(.void_type) == null);
    try std.testing.expect(codegen.mapRuntimeType(.i64_type) == null);
    try std.testing.expect(codegen.mapRuntimeType(.php_value_ptr) == null);
}

test "RuntimeFunctionSig structure" {
    // Verify runtime function signatures are properly defined
    try std.testing.expect(CodeGenerator.runtime_function_signatures.len > 0);
    try std.testing.expect(CodeGenerator.runtime_function_signatures_2.len > 0);

    // Check first signature
    const first_sig = CodeGenerator.runtime_function_signatures[0];
    try std.testing.expectEqualStrings("php_value_create_null", first_sig.name);
    try std.testing.expectEqual(CodeGenerator.RuntimeType.php_value_ptr, first_sig.return_type);
    try std.testing.expectEqual(@as(usize, 0), first_sig.param_types.len);
}
