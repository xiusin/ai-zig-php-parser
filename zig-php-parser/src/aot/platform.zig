//! 跨平台代码生成支持
//!
//! 本模块提供跨平台代码生成的抽象层，支持：
//! - Linux (x86_64, aarch64)
//! - macOS (x86_64, aarch64/Apple Silicon)
//! - Windows (x86_64)
//!
//! ## 架构
//!
//! 平台特定的代码生成通过以下机制实现：
//! 1. 目标三元组（Target Triple）配置
//! 2. 平台特定的调用约定
//! 3. 平台特定的系统调用接口
//! 4. 平台特定的对象文件格式（ELF, Mach-O, PE/COFF）
//!
//! ## 内存安全
//!
//! @memory-safety 所有平台配置数据为编译时常量，无运行时分配
//! @ownership NON-OWNING (所有字符串为字面量)

const std = @import("std");
const Allocator = std.mem.Allocator;

/// 目标平台配置
/// 
/// @memory-layout 编译时常量结构体
/// @ownership NON-OWNING (所有字段为字面量或值类型)
pub const PlatformConfig = struct {
    /// 平台名称
    name: []const u8,
    
    /// 目标三元组
    triple: []const u8,
    
    /// 对象文件格式
    object_format: ObjectFormat,
    
    /// 调用约定
    calling_convention: CallingConvention,
    
    /// 系统调用约定
    syscall_convention: SyscallConvention,
    
    /// 动态链接器路径（Linux）
    dynamic_linker: ?[]const u8,
    
    /// 系统库搜索路径
    system_lib_paths: []const []const u8,
    
    /// 必需的系统库
    required_libs: []const []const u8,
    
    /// 平台特定的编译标志
    compile_flags: []const []const u8,
    
    /// 平台特定的链接标志
    link_flags: []const []const u8,
};

/// 对象文件格式
pub const ObjectFormat = enum {
    /// ELF (Executable and Linkable Format) - Linux, BSD
    elf,
    
    /// Mach-O (Mach Object) - macOS, iOS
    macho,
    
    /// PE/COFF (Portable Executable/Common Object File Format) - Windows
    coff,
    
    /// 转换为 LLVM 对象格式字符串
    pub fn toLLVMString(self: ObjectFormat) []const u8 {
        return switch (self) {
            .elf => "elf",
            .macho => "macho",
            .coff => "coff",
        };
    }
};

/// 调用约定
pub const CallingConvention = enum {
    /// System V AMD64 ABI - Linux, macOS, BSD
    sysv,
    
    /// Microsoft x64 calling convention - Windows
    win64,
    
    /// ARM64 calling convention (AAPCS64)
    aapcs64,
    
    /// 转换为 LLVM 调用约定
    pub fn toLLVMCallConv(self: CallingConvention) u32 {
        return switch (self) {
            .sysv => 0,  // C calling convention
            .win64 => 0,  // C calling convention (LLVM handles platform differences)
            .aapcs64 => 0,  // C calling convention
        };
    }
};

/// 系统调用约定
pub const SyscallConvention = enum {
    /// Linux syscall convention
    linux,
    
    /// macOS syscall convention (BSD-style)
    darwin,
    
    /// Windows syscall convention (via ntdll.dll)
    windows,
};

// ============================================================================
// Linux 平台配置
// ============================================================================

/// Linux x86_64 配置
/// 
/// @platform Linux
/// @arch x86_64
/// @abi GNU
pub const linux_x86_64 = PlatformConfig{
    .name = "Linux x86_64",
    .triple = "x86_64-unknown-linux-gnu",
    .object_format = .elf,
    .calling_convention = .sysv,
    .syscall_convention = .linux,
    .dynamic_linker = "/lib64/ld-linux-x86-64.so.2",
    .system_lib_paths = &[_][]const u8{
        "/lib/x86_64-linux-gnu",
        "/usr/lib/x86_64-linux-gnu",
        "/lib64",
        "/usr/lib64",
    },
    .required_libs = &[_][]const u8{
        "c",
        "m",
        "pthread",
        "dl",
    },
    .compile_flags = &[_][]const u8{
        "-fPIC",
        "-fstack-protector-strong",
    },
    .link_flags = &[_][]const u8{
        "-z", "relro",
        "-z", "now",
        "-z", "noexecstack",
    },
};

/// Linux aarch64 配置
/// 
/// @platform Linux
/// @arch aarch64
/// @abi GNU
pub const linux_aarch64 = PlatformConfig{
    .name = "Linux aarch64",
    .triple = "aarch64-unknown-linux-gnu",
    .object_format = .elf,
    .calling_convention = .aapcs64,
    .syscall_convention = .linux,
    .dynamic_linker = "/lib/ld-linux-aarch64.so.1",
    .system_lib_paths = &[_][]const u8{
        "/lib/aarch64-linux-gnu",
        "/usr/lib/aarch64-linux-gnu",
        "/lib64",
        "/usr/lib64",
    },
    .required_libs = &[_][]const u8{
        "c",
        "m",
        "pthread",
        "dl",
    },
    .compile_flags = &[_][]const u8{
        "-fPIC",
        "-fstack-protector-strong",
    },
    .link_flags = &[_][]const u8{
        "-z", "relro",
        "-z", "now",
        "-z", "noexecstack",
    },
};

/// Linux musl x86_64 配置（静态链接友好）
/// 
/// @platform Linux
/// @arch x86_64
/// @abi musl
pub const linux_x86_64_musl = PlatformConfig{
    .name = "Linux x86_64 (musl)",
    .triple = "x86_64-unknown-linux-musl",
    .object_format = .elf,
    .calling_convention = .sysv,
    .syscall_convention = .linux,
    .dynamic_linker = "/lib/ld-musl-x86_64.so.1",
    .system_lib_paths = &[_][]const u8{
        "/lib",
        "/usr/lib",
    },
    .required_libs = &[_][]const u8{
        "c",
    },
    .compile_flags = &[_][]const u8{
        "-fPIC",
        "-static-pie",
    },
    .link_flags = &[_][]const u8{
        "-static",
        "-z", "relro",
        "-z", "now",
    },
};

// ============================================================================
// macOS 平台配置
// ============================================================================

/// macOS x86_64 配置
/// 
/// @platform macOS
/// @arch x86_64
/// @min-version 10.15
pub const macos_x86_64 = PlatformConfig{
    .name = "macOS x86_64",
    .triple = "x86_64-apple-darwin",
    .object_format = .macho,
    .calling_convention = .sysv,
    .syscall_convention = .darwin,
    .dynamic_linker = "/usr/lib/dyld",
    .system_lib_paths = &[_][]const u8{
        "/usr/lib",
        "/usr/local/lib",
    },
    .required_libs = &[_][]const u8{
        "System",
    },
    .compile_flags = &[_][]const u8{
        "-mmacosx-version-min=10.15",
        "-fPIC",
    },
    .link_flags = &[_][]const u8{
        "-macosx_version_min", "10.15",
        "-platform_version", "macos", "10.15", "10.15",
    },
};

/// macOS aarch64 配置（Apple Silicon）
/// 
/// @platform macOS
/// @arch aarch64
/// @min-version 11.0
pub const macos_aarch64 = PlatformConfig{
    .name = "macOS aarch64 (Apple Silicon)",
    .triple = "aarch64-apple-darwin",
    .object_format = .macho,
    .calling_convention = .aapcs64,
    .syscall_convention = .darwin,
    .dynamic_linker = "/usr/lib/dyld",
    .system_lib_paths = &[_][]const u8{
        "/usr/lib",
        "/usr/local/lib",
        "/opt/homebrew/lib",
    },
    .required_libs = &[_][]const u8{
        "System",
    },
    .compile_flags = &[_][]const u8{
        "-mmacosx-version-min=11.0",
        "-fPIC",
    },
    .link_flags = &[_][]const u8{
        "-macosx_version_min", "11.0",
        "-platform_version", "macos", "11.0", "11.0",
    },
};

// ============================================================================
// Windows 平台配置
// ============================================================================

/// Windows x86_64 配置（MSVC ABI）
/// 
/// @platform Windows
/// @arch x86_64
/// @abi MSVC
pub const windows_x86_64_msvc = PlatformConfig{
    .name = "Windows x86_64 (MSVC)",
    .triple = "x86_64-pc-windows-msvc",
    .object_format = .coff,
    .calling_convention = .win64,
    .syscall_convention = .windows,
    .dynamic_linker = null,  // Windows uses PE loader
    .system_lib_paths = &[_][]const u8{
        // 这些路径在实际编译时由 MSVC 环境变量提供
        // "C:\\Program Files (x86)\\Windows Kits\\10\\Lib\\...\\um\\x64",
        // "C:\\Program Files (x86)\\Windows Kits\\10\\Lib\\...\\ucrt\\x64",
    },
    .required_libs = &[_][]const u8{
        "kernel32",
        "user32",
        "msvcrt",
        "ucrt",
    },
    .compile_flags = &[_][]const u8{
        "/MD",  // Multi-threaded DLL runtime
        "/GS",  // Buffer security check
        "/Gy",  // Enable function-level linking
    },
    .link_flags = &[_][]const u8{
        "/DYNAMICBASE",  // ASLR
        "/NXCOMPAT",     // DEP
        "/SUBSYSTEM:CONSOLE",
    },
};

/// Windows x86_64 配置（GNU ABI / MinGW）
/// 
/// @platform Windows
/// @arch x86_64
/// @abi GNU
pub const windows_x86_64_gnu = PlatformConfig{
    .name = "Windows x86_64 (GNU/MinGW)",
    .triple = "x86_64-w64-windows-gnu",
    .object_format = .coff,
    .calling_convention = .win64,
    .syscall_convention = .windows,
    .dynamic_linker = null,
    .system_lib_paths = &[_][]const u8{
        "/mingw64/lib",
        "/mingw64/x86_64-w64-mingw32/lib",
    },
    .required_libs = &[_][]const u8{
        "kernel32",
        "msvcrt",
        "mingw32",
        "gcc",
        "moldname",
        "mingwex",
    },
    .compile_flags = &[_][]const u8{
        "-fPIC",
        "-fstack-protector-strong",
    },
    .link_flags = &[_][]const u8{
        "-Wl,--dynamicbase",
        "-Wl,--nxcompat",
        "-Wl,--high-entropy-va",
    },
};

// ============================================================================
// 平台检测与选择
// ============================================================================

/// 平台选择器
/// 
/// @concurrency-model ISOLATED (无共享状态)
pub const PlatformSelector = struct {
    /// 根据目标三元组选择平台配置
    /// 
    /// @pre triple 必须是有效的 LLVM 目标三元组
    /// @post 返回匹配的平台配置或错误
    /// @memory-safety 无内存分配，返回静态配置引用
    pub fn selectByTriple(triple: []const u8) !*const PlatformConfig {
        // Linux
        if (std.mem.indexOf(u8, triple, "linux") != null) {
            if (std.mem.indexOf(u8, triple, "x86_64") != null or 
                std.mem.indexOf(u8, triple, "amd64") != null) {
                if (std.mem.indexOf(u8, triple, "musl") != null) {
                    return &linux_x86_64_musl;
                }
                return &linux_x86_64;
            } else if (std.mem.indexOf(u8, triple, "aarch64") != null or
                       std.mem.indexOf(u8, triple, "arm64") != null) {
                return &linux_aarch64;
            }
        }
        
        // macOS
        if (std.mem.indexOf(u8, triple, "darwin") != null or
            std.mem.indexOf(u8, triple, "macos") != null) {
            if (std.mem.indexOf(u8, triple, "x86_64") != null or
                std.mem.indexOf(u8, triple, "amd64") != null) {
                return &macos_x86_64;
            } else if (std.mem.indexOf(u8, triple, "aarch64") != null or
                       std.mem.indexOf(u8, triple, "arm64") != null) {
                return &macos_aarch64;
            }
        }
        
        // Windows
        if (std.mem.indexOf(u8, triple, "windows") != null or
            std.mem.indexOf(u8, triple, "win32") != null or
            std.mem.indexOf(u8, triple, "mingw") != null) {
            if (std.mem.indexOf(u8, triple, "msvc") != null) {
                return &windows_x86_64_msvc;
            } else if (std.mem.indexOf(u8, triple, "gnu") != null or
                       std.mem.indexOf(u8, triple, "mingw") != null) {
                return &windows_x86_64_gnu;
            }
            // 默认使用 MSVC
            return &windows_x86_64_msvc;
        }
        
        return error.UnsupportedPlatform;
    }
    
    /// 获取当前主机平台配置
    /// 
    /// @post 返回当前编译主机的平台配置
    /// @memory-safety 无内存分配，返回静态配置引用
    pub fn getNativePlatform() *const PlatformConfig {
        const builtin = @import("builtin");
        
        return switch (builtin.os.tag) {
            .linux => switch (builtin.cpu.arch) {
                .x86_64 => &linux_x86_64,
                .aarch64 => &linux_aarch64,
                else => &linux_x86_64,  // 默认
            },
            .macos => switch (builtin.cpu.arch) {
                .x86_64 => &macos_x86_64,
                .aarch64 => &macos_aarch64,
                else => &macos_x86_64,  // 默认
            },
            .windows => &windows_x86_64_msvc,
            else => &linux_x86_64,  // 默认回退到 Linux
        };
    }
    
    /// 列出所有支持的平台
    /// 
    /// @post 返回所有支持的平台配置数组
    /// @memory-safety 返回静态数组，无需释放
    pub fn getAllSupportedPlatforms() []const *const PlatformConfig {
        const platforms = [_]*const PlatformConfig{
            &linux_x86_64,
            &linux_aarch64,
            &linux_x86_64_musl,
            &macos_x86_64,
            &macos_aarch64,
            &windows_x86_64_msvc,
            &windows_x86_64_gnu,
        };
        return &platforms;
    }
};

// ============================================================================
// 平台特定代码生成辅助函数
// ============================================================================

/// 平台代码生成器
/// 
/// @ownership NON-OWNING (platform_config)
/// @concurrency-model ISOLATED
pub const PlatformCodeGen = struct {
    platform_config: *const PlatformConfig,
    
    /// 初始化平台代码生成器
    /// 
    /// @pre platform_config 必须有效
    /// @post 返回初始化的代码生成器
    pub fn init(platform_config: *const PlatformConfig) PlatformCodeGen {
        return .{
            .platform_config = platform_config,
        };
    }
    
    /// 生成平台特定的函数序言
    /// 
    /// @post 返回函数序言的汇编代码
    /// @memory-safety allocator 管理返回的内存
    pub fn generateFunctionPrologue(
        self: *const PlatformCodeGen,
        allocator: Allocator,
        stack_size: usize,
    ) ![]const u8 {
        return switch (self.platform_config.calling_convention) {
            .sysv => try std.fmt.allocPrint(allocator,
                \\  push rbp
                \\  mov rbp, rsp
                \\  sub rsp, {d}
                \\
            , .{stack_size}),
            
            .win64 => try std.fmt.allocPrint(allocator,
                \\  push rbp
                \\  mov rbp, rsp
                \\  sub rsp, {d}
                \\  ; Windows x64 calling convention
                \\  ; RCX, RDX, R8, R9 for first 4 args
                \\
            , .{stack_size}),
            
            .aapcs64 => try std.fmt.allocPrint(allocator,
                \\  stp x29, x30, [sp, #-16]!
                \\  mov x29, sp
                \\  sub sp, sp, #{d}
                \\
            , .{stack_size}),
        };
    }
    
    /// 生成平台特定的函数尾声
    /// 
    /// @post 返回函数尾声的汇编代码
    /// @memory-safety allocator 管理返回的内存
    pub fn generateFunctionEpilogue(
        self: *const PlatformCodeGen,
        allocator: Allocator,
    ) ![]const u8 {
        _ = allocator;
        
        return switch (self.platform_config.calling_convention) {
            .sysv, .win64 =>
                \\  mov rsp, rbp
                \\  pop rbp
                \\  ret
                \\
            ,
            
            .aapcs64 =>
                \\  mov sp, x29
                \\  ldp x29, x30, [sp], #16
                \\  ret
                \\
            ,
        };
    }
    
    /// 生成平台特定的系统调用
    /// 
    /// @pre syscall_number 必须有效
    /// @post 返回系统调用的汇编代码
    /// @memory-safety allocator 管理返回的内存
    pub fn generateSyscall(
        self: *const PlatformCodeGen,
        allocator: Allocator,
        syscall_number: u32,
        args: []const []const u8,
    ) ![]const u8 {
        return switch (self.platform_config.syscall_convention) {
            .linux => try self.generateLinuxSyscall(allocator, syscall_number, args),
            .darwin => try self.generateDarwinSyscall(allocator, syscall_number, args),
            .windows => try self.generateWindowsSyscall(allocator, syscall_number, args),
        };
    }
    
    /// 生成 Linux 系统调用
    fn generateLinuxSyscall(
        self: *const PlatformCodeGen,
        allocator: Allocator,
        syscall_number: u32,
        args: []const []const u8,
    ) ![]const u8 {
        _ = self;
        
        var code: std.ArrayList(u8) = .{};
        errdefer code.deinit(allocator);
        
        const writer = code.writer(allocator);
        
        // Linux x86_64 syscall convention:
        // rax = syscall number
        // rdi, rsi, rdx, r10, r8, r9 = args 1-6
        try writer.print("  mov rax, {d}\n", .{syscall_number});
        
        const reg_names = [_][]const u8{ "rdi", "rsi", "rdx", "r10", "r8", "r9" };
        for (args, 0..) |arg, i| {
            if (i >= reg_names.len) break;
            try writer.print("  mov {s}, {s}\n", .{ reg_names[i], arg });
        }
        
        try writer.writeAll("  syscall\n");
        
        return code.toOwnedSlice(allocator);
    }
    
    /// 生成 macOS 系统调用
    fn generateDarwinSyscall(
        self: *const PlatformCodeGen,
        allocator: Allocator,
        syscall_number: u32,
        args: []const []const u8,
    ) ![]const u8 {
        _ = self;
        
        var code: std.ArrayList(u8) = .{};
        errdefer code.deinit(allocator);
        
        const writer = code.writer(allocator);
        
        // macOS syscall convention (similar to Linux but with 0x2000000 offset)
        const darwin_syscall_offset = 0x2000000;
        try writer.print("  mov rax, {d}\n", .{syscall_number + darwin_syscall_offset});
        
        const reg_names = [_][]const u8{ "rdi", "rsi", "rdx", "r10", "r8", "r9" };
        for (args, 0..) |arg, i| {
            if (i >= reg_names.len) break;
            try writer.print("  mov {s}, {s}\n", .{ reg_names[i], arg });
        }
        
        try writer.writeAll("  syscall\n");
        
        return code.toOwnedSlice(allocator);
    }
    
    /// 生成 Windows 系统调用
    fn generateWindowsSyscall(
        self: *const PlatformCodeGen,
        allocator: Allocator,
        syscall_number: u32,
        args: []const []const u8,
    ) ![]const u8 {
        _ = self;
        _ = syscall_number;
        _ = args;
        
        // Windows 不直接暴露系统调用，需要通过 ntdll.dll
        // 这里生成调用 ntdll 函数的代码
        return try allocator.dupe(u8,
            \\  ; Windows syscall via ntdll.dll
            \\  ; Use NtXxx functions instead of direct syscall
            \\
        );
    }
    
    /// 获取平台特定的对齐要求
    /// 
    /// @post 返回平台的栈对齐字节数
    pub fn getStackAlignment(self: *const PlatformCodeGen) usize {
        return switch (self.platform_config.calling_convention) {
            .sysv => 16,      // System V ABI requires 16-byte alignment
            .win64 => 16,     // Windows x64 requires 16-byte alignment
            .aapcs64 => 16,   // ARM64 requires 16-byte alignment
        };
    }
    
    /// 获取平台特定的指针大小
    /// 
    /// @post 返回平台的指针大小（字节）
    pub fn getPointerSize(self: *const PlatformCodeGen) usize {
        _ = self;
        // 所有支持的平台都是 64 位
        return 8;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "PlatformSelector.selectByTriple - Linux x86_64" {
    const config = try PlatformSelector.selectByTriple("x86_64-unknown-linux-gnu");
    try std.testing.expectEqualStrings("Linux x86_64", config.name);
    try std.testing.expectEqual(ObjectFormat.elf, config.object_format);
    try std.testing.expectEqual(CallingConvention.sysv, config.calling_convention);
}

test "PlatformSelector.selectByTriple - macOS aarch64" {
    const config = try PlatformSelector.selectByTriple("aarch64-apple-darwin");
    try std.testing.expectEqualStrings("macOS aarch64 (Apple Silicon)", config.name);
    try std.testing.expectEqual(ObjectFormat.macho, config.object_format);
    try std.testing.expectEqual(CallingConvention.aapcs64, config.calling_convention);
}

test "PlatformSelector.selectByTriple - Windows x86_64" {
    const config = try PlatformSelector.selectByTriple("x86_64-pc-windows-msvc");
    try std.testing.expectEqualStrings("Windows x86_64 (MSVC)", config.name);
    try std.testing.expectEqual(ObjectFormat.coff, config.object_format);
    try std.testing.expectEqual(CallingConvention.win64, config.calling_convention);
}

test "PlatformSelector.getNativePlatform" {
    const config = PlatformSelector.getNativePlatform();
    try std.testing.expect(config.name.len > 0);
    try std.testing.expect(config.triple.len > 0);
}

test "PlatformSelector.getAllSupportedPlatforms" {
    const platforms = PlatformSelector.getAllSupportedPlatforms();
    try std.testing.expectEqual(@as(usize, 7), platforms.len);
}

test "PlatformCodeGen.generateFunctionPrologue" {
    const config = &linux_x86_64;
    const codegen = PlatformCodeGen.init(config);
    
    const prologue = try codegen.generateFunctionPrologue(std.testing.allocator, 64);
    defer std.testing.allocator.free(prologue);
    
    try std.testing.expect(std.mem.indexOf(u8, prologue, "push rbp") != null);
    try std.testing.expect(std.mem.indexOf(u8, prologue, "mov rbp, rsp") != null);
}

test "PlatformCodeGen.getStackAlignment" {
    const config = &linux_x86_64;
    const codegen = PlatformCodeGen.init(config);
    
    try std.testing.expectEqual(@as(usize, 16), codegen.getStackAlignment());
}
