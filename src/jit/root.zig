const std = @import("std");
const builtin = @import("builtin");

pub const CodeCache = @import("code_cache.zig").CodeCache;

pub const Assembler = if (builtin.cpu.arch == .aarch64)
    @import("assembler_arm64.zig").Assembler
else
    // Placeholder for x64, using arm64 for now to avoid build errors if file missing,
    // but in real world we need assembler_x64.zig
    @import("assembler_arm64.zig").Assembler;

pub const Register = if (builtin.cpu.arch == .aarch64)
    @import("assembler_arm64.zig").Register
else
    @import("assembler_arm64.zig").Register;

pub const Compiler = @import("compiler.zig").Compiler;
pub const HotspotDetector = @import("hotspot_detector.zig").HotspotDetector;
pub const HotspotConfig = @import("hotspot_detector.zig").HotspotConfig;
pub const RegisterAllocator = @import("register_allocator.zig").RegisterAllocator;
pub const LiveInterval = @import("register_allocator.zig").LiveInterval;
pub const RegisterMap = @import("register_allocator.zig").RegisterMap;

// SIMD 优化模块
pub const SIMDCapabilities = @import("simd.zig").SIMDCapabilities;
pub const SIMDInstructionSet = @import("simd.zig").SIMDInstructionSet;
pub const SIMDVectorizer = @import("simd.zig").SIMDVectorizer;

// 调试信息模块
pub const DebugInfoManager = @import("debug_info.zig").DebugInfoManager;
pub const DebugInfoBuilder = @import("debug_info.zig").DebugInfoBuilder;
pub const SourceLocation = @import("debug_info.zig").SourceLocation;
pub const AddressRange = @import("debug_info.zig").AddressRange;
pub const CodeMapping = @import("debug_info.zig").CodeMapping;
pub const DebugSymbol = @import("debug_info.zig").DebugSymbol;
pub const SymbolType = @import("debug_info.zig").SymbolType;

test {
    _ = CodeCache;
    _ = Assembler;
    _ = Compiler;
    _ = HotspotDetector;
    _ = RegisterAllocator;
    _ = @import("test_register_allocator_properties.zig");
    _ = @import("test_simd_properties.zig");
    _ = @import("debug_info.zig");
    _ = @import("test_debug_info_integration.zig");
}
