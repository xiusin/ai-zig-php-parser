/// 平台特定的崩溃处理器实现
/// 
/// 提供跨平台的寄存器和故障地址提取
/// 
/// @platform Linux, macOS
/// @architecture x86_64, aarch64

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// C 导入 - 平台特定结构
// ============================================================================

const c_defs = if (builtin.os.tag == .macos or builtin.os.tag == .ios or 
                   builtin.os.tag == .tvos or builtin.os.tag == .watchos or 
                   builtin.os.tag == .visionos)
    @cImport({
        @cInclude("signal.h");
        @cInclude("sys/ucontext.h");
    })
else if (builtin.os.tag == .linux)
    @cImport({
        @cInclude("signal.h");
        @cInclude("ucontext.h");
    })
else
    struct {};

// ============================================================================
// 寄存器提取
// ============================================================================

/// 寄存器上下文
pub const RegisterContext = struct {
    /// 指令指针
    instruction_pointer: usize,
    
    /// 堆栈指针
    stack_pointer: usize,
    
    /// 帧指针
    frame_pointer: usize,
    
    /// 通用寄存器（平台相关）
    general_registers: [16]usize,
    
    /// 初始化空的寄存器上下文
    pub fn init() RegisterContext {
        return .{
            .instruction_pointer = 0,
            .stack_pointer = 0,
            .frame_pointer = 0,
            .general_registers = [_]usize{0} ** 16,
        };
    }
};

/// 从 ucontext 提取寄存器（Linux x86_64）
fn extractRegistersLinuxX64(ucontext: *anyopaque) RegisterContext {
    const uc: *std.os.linux.ucontext_t = @ptrCast(@alignCast(ucontext));
    
    var ctx = RegisterContext.init();
    ctx.instruction_pointer = @intCast(uc.mcontext.gregs[std.os.linux.REG.RIP]);
    ctx.stack_pointer = @intCast(uc.mcontext.gregs[std.os.linux.REG.RSP]);
    ctx.frame_pointer = @intCast(uc.mcontext.gregs[std.os.linux.REG.RBP]);
    
    // 提取通用寄存器
    ctx.general_registers[0] = @intCast(uc.mcontext.gregs[std.os.linux.REG.RAX]);
    ctx.general_registers[1] = @intCast(uc.mcontext.gregs[std.os.linux.REG.RBX]);
    ctx.general_registers[2] = @intCast(uc.mcontext.gregs[std.os.linux.REG.RCX]);
    ctx.general_registers[3] = @intCast(uc.mcontext.gregs[std.os.linux.REG.RDX]);
    ctx.general_registers[4] = @intCast(uc.mcontext.gregs[std.os.linux.REG.RSI]);
    ctx.general_registers[5] = @intCast(uc.mcontext.gregs[std.os.linux.REG.RDI]);
    ctx.general_registers[8] = @intCast(uc.mcontext.gregs[std.os.linux.REG.R8]);
    ctx.general_registers[9] = @intCast(uc.mcontext.gregs[std.os.linux.REG.R9]);
    ctx.general_registers[10] = @intCast(uc.mcontext.gregs[std.os.linux.REG.R10]);
    ctx.general_registers[11] = @intCast(uc.mcontext.gregs[std.os.linux.REG.R11]);
    ctx.general_registers[12] = @intCast(uc.mcontext.gregs[std.os.linux.REG.R12]);
    ctx.general_registers[13] = @intCast(uc.mcontext.gregs[std.os.linux.REG.R13]);
    ctx.general_registers[14] = @intCast(uc.mcontext.gregs[std.os.linux.REG.R14]);
    ctx.general_registers[15] = @intCast(uc.mcontext.gregs[std.os.linux.REG.R15]);
    
    return ctx;
}

/// 从 ucontext 提取寄存器（Linux ARM64）
fn extractRegistersLinuxARM64(ucontext: *anyopaque) RegisterContext {
    const uc: *std.os.linux.ucontext_t = @ptrCast(@alignCast(ucontext));
    
    var ctx = RegisterContext.init();
    ctx.instruction_pointer = @intCast(uc.mcontext.pc);
    ctx.instruction_pointer = @intCast(uc.mcontext.sp);
    ctx.frame_pointer = @intCast(uc.mcontext.regs[29]); // x29 is FP
    
    // 提取通用寄存器 x0-x15
    for (0..16) |i| {
        ctx.general_registers[i] = @intCast(uc.mcontext.regs[i]);
    }
    
    return ctx;
}

/// 从 ucontext 提取寄存器（macOS x86_64）
fn extractRegistersMacOSX64(ucontext: *anyopaque) RegisterContext {
    // macOS 的 ucontext 结构访问需要通过 C
    const uc: *c_defs.ucontext_t = @ptrCast(@alignCast(ucontext));
    
    var ctx = RegisterContext.init();
    
    // macOS x86_64 mcontext 访问
    if (builtin.cpu.arch == .x86_64) {
        const mc = uc.uc_mcontext;
        
        // 使用 C 结构访问寄存器
        // 注意：这些字段名可能因 macOS 版本而异
        ctx.instruction_pointer = @intCast(@as(usize, @bitCast(mc.*.ss.rip)));
        ctx.stack_pointer = @intCast(@as(usize, @bitCast(mc.*.ss.rsp)));
        ctx.frame_pointer = @intCast(@as(usize, @bitCast(mc.*.ss.rbp)));
        
        ctx.general_registers[0] = @intCast(@as(usize, @bitCast(mc.*.ss.rax)));
        ctx.general_registers[1] = @intCast(@as(usize, @bitCast(mc.*.ss.rbx)));
        ctx.general_registers[2] = @intCast(@as(usize, @bitCast(mc.*.ss.rcx)));
        ctx.general_registers[3] = @intCast(@as(usize, @bitCast(mc.*.ss.rdx)));
        ctx.general_registers[4] = @intCast(@as(usize, @bitCast(mc.*.ss.rsi)));
        ctx.general_registers[5] = @intCast(@as(usize, @bitCast(mc.*.ss.rdi)));
        ctx.general_registers[8] = @intCast(@as(usize, @bitCast(mc.*.ss.r8)));
        ctx.general_registers[9] = @intCast(@as(usize, @bitCast(mc.*.ss.r9)));
        ctx.general_registers[10] = @intCast(@as(usize, @bitCast(mc.*.ss.r10)));
        ctx.general_registers[11] = @intCast(@as(usize, @bitCast(mc.*.ss.r11)));
        ctx.general_registers[12] = @intCast(@as(usize, @bitCast(mc.*.ss.r12)));
        ctx.general_registers[13] = @intCast(@as(usize, @bitCast(mc.*.ss.r13)));
        ctx.general_registers[14] = @intCast(@as(usize, @bitCast(mc.*.ss.r14)));
        ctx.general_registers[15] = @intCast(@as(usize, @bitCast(mc.*.ss.r15)));
    }
    
    return ctx;
}

/// 从 ucontext 提取寄存器（macOS ARM64）
fn extractRegistersMacOSARM64(ucontext: *anyopaque) RegisterContext {
    const uc: *c_defs.ucontext_t = @ptrCast(@alignCast(ucontext));
    
    var ctx = RegisterContext.init();
    
    if (builtin.cpu.arch == .aarch64) {
        const mc = uc.uc_mcontext;
        
        // Apple Silicon (ARM64) 寄存器访问
        ctx.instruction_pointer = @intCast(@as(usize, @bitCast(mc.*.ss.pc)));
        ctx.stack_pointer = @intCast(@as(usize, @bitCast(mc.*.ss.sp)));
        ctx.frame_pointer = @intCast(@as(usize, @bitCast(mc.*.ss.fp)));
        
        // 提取通用寄存器 x0-x15
        for (0..16) |i| {
            ctx.general_registers[i] = @intCast(@as(usize, @bitCast(mc.*.ss.x[i])));
        }
    }
    
    return ctx;
}

/// 提取寄存器上下文（跨平台）
pub fn extractRegisters(ucontext: ?*anyopaque) RegisterContext {
    if (ucontext == null) {
        return RegisterContext.init();
    }
    
    const uc = ucontext.?;
    
    return switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => extractRegistersLinuxX64(uc),
            .aarch64 => extractRegistersLinuxARM64(uc),
            else => RegisterContext.init(),
        },
        .macos, .ios, .tvos, .watchos, .visionos => switch (builtin.cpu.arch) {
            .x86_64 => extractRegistersMacOSX64(uc),
            .aarch64 => extractRegistersMacOSARM64(uc),
            else => RegisterContext.init(),
        },
        else => RegisterContext.init(),
    };
}

// ============================================================================
// 故障地址提取
// ============================================================================

/// 提取故障地址（跨平台）
pub fn extractFaultAddress(info: *const std.posix.siginfo_t) ?usize {
    return switch (builtin.os.tag) {
        .linux => {
            return @intFromPtr(info.fields.sigfault.addr);
        },
        .macos, .ios, .tvos, .watchos, .visionos => {
            // macOS 使用 C 结构
            const c_info: *const c_defs.siginfo_t = @ptrCast(info);
            
            // macOS siginfo_t 中的故障地址
            // 字段名可能是 si_addr
            const addr_ptr: ?*anyopaque = @ptrCast(c_info.si_addr);
            if (addr_ptr) |ptr| {
                return @intFromPtr(ptr);
            }
            return null;
        },
        else => {
            _ = info;
            return null;
        },
    };
}

// ============================================================================
// 便捷函数
// ============================================================================

/// 提取指令指针
pub fn extractInstructionPointer(ucontext: ?*anyopaque) usize {
    const ctx = extractRegisters(ucontext);
    return ctx.instruction_pointer;
}

/// 提取堆栈指针
pub fn extractStackPointer(ucontext: ?*anyopaque) usize {
    const ctx = extractRegisters(ucontext);
    return ctx.stack_pointer;
}

/// 提取帧指针
pub fn extractFramePointer(ucontext: ?*anyopaque) usize {
    const ctx = extractRegisters(ucontext);
    return ctx.frame_pointer;
}

// ============================================================================
// 测试
// ============================================================================

test "RegisterContext 初始化" {
    const ctx = RegisterContext.init();
    
    try std.testing.expectEqual(@as(usize, 0), ctx.instruction_pointer);
    try std.testing.expectEqual(@as(usize, 0), ctx.stack_pointer);
    try std.testing.expectEqual(@as(usize, 0), ctx.frame_pointer);
    
    for (ctx.general_registers) |reg| {
        try std.testing.expectEqual(@as(usize, 0), reg);
    }
}

test "extractRegisters null ucontext" {
    const ctx = extractRegisters(null);
    
    try std.testing.expectEqual(@as(usize, 0), ctx.instruction_pointer);
    try std.testing.expectEqual(@as(usize, 0), ctx.stack_pointer);
    try std.testing.expectEqual(@as(usize, 0), ctx.frame_pointer);
}

test "便捷函数 null ucontext" {
    try std.testing.expectEqual(@as(usize, 0), extractInstructionPointer(null));
    try std.testing.expectEqual(@as(usize, 0), extractStackPointer(null));
    try std.testing.expectEqual(@as(usize, 0), extractFramePointer(null));
}
