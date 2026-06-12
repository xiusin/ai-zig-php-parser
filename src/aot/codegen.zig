const std = @import("std");
const IR = @import("ir.zig");
const Diagnostics = @import("diagnostics.zig");

pub const CodeGenError = error{
    InvalidRegister,
    InvalidBlock,
    InvalidType,
    UnsupportedOperation,
    LLVMUnavailable,
    CompilationFailed,
    InvalidInstruction,
    InvalidValue,
};

pub const Target = struct {
    arch: Arch,
    os: OS,
    abi: ABI,
    
    pub const Arch = enum { x86_64, aarch64, arm };
    pub const OS = enum { linux, macos, windows };
    pub const ABI = enum { gnu, musl, msvc, none };
};

pub const OptimizeLevel = enum {
    debug,
    release_safe,
    release_fast,
    release_small,
};

pub const CodeGenerator = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(
        allocator: std.mem.Allocator, 
        target: Target, 
        optimize: OptimizeLevel, 
        debug_info: bool, 
        diagnostics: *Diagnostics.DiagnosticEngine
    ) !*CodeGenerator {
        _ = target;
        _ = optimize;
        _ = debug_info;
        _ = diagnostics;
        const self = try allocator.create(CodeGenerator);
        self.* = CodeGenerator{
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *CodeGenerator) void {
        self.allocator.destroy(self);
    }

    pub fn generateModule(self: *CodeGenerator, module: *IR.Module) !void {
        _ = self;
        _ = module;
        // In native mode (no LLVM), this path should effectively be disabled or unused.
        // However, existing compiler.zig might call it.
        return error.LLVMUnavailable;
    }
    
    pub fn getObjectCode(self: *CodeGenerator) ![]const u8 {
        _ = self;
        return error.LLVMUnavailable;
    }
};
