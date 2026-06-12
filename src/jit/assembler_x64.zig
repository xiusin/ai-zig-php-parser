/// x86-64 汇编器
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED (单线程)
/// @memory-layout 指令按 x86-64 编码规范生成
const std = @import("std");

/// x86-64 寄存器
pub const Register = enum(u8) {
    rax = 0,
    rcx = 1,
    rdx = 2,
    rbx = 3,
    rsp = 4,
    rbp = 5,
    rsi = 6,
    rdi = 7,
    r8 = 8,
    r9 = 9,
    r10 = 10,
    r11 = 11,
    r12 = 12,
    r13 = 13,
    r14 = 14,
    r15 = 15,
    
    /// 获取寄存器编号（用于编码）
    pub fn code(self: Register) u8 {
        return @intFromEnum(self);
    }
    
    /// 是否需要 REX 前缀
    pub fn needsRex(self: Register) bool {
        return @intFromEnum(self) >= 8;
    }
};

/// 条件码
pub const Condition = enum(u8) {
    O = 0x0,    // Overflow
    NO = 0x1,   // Not overflow
    B = 0x2,    // Below (unsigned <)
    AE = 0x3,   // Above or equal (unsigned >=)
    E = 0x4,    // Equal (==)
    NE = 0x5,   // Not equal (!=)
    BE = 0x6,   // Below or equal (unsigned <=)
    A = 0x7,    // Above (unsigned >)
    S = 0x8,    // Sign
    NS = 0x9,   // Not sign
    P = 0xA,    // Parity
    NP = 0xB,   // Not parity
    L = 0xC,    // Less (signed <)
    GE = 0xD,   // Greater or equal (signed >=)
    LE = 0xE,   // Less or equal (signed <=)
    G = 0xF,    // Greater (signed >)
    
    pub fn code(self: Condition) u8 {
        return @intFromEnum(self);
    }
};

/// x86-64 汇编器
pub const Assembler = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayList(u8),
    
    /// @pre allocator 必须有效
    /// @post 返回初始化的汇编器实例
    pub fn init(allocator: std.mem.Allocator) Assembler {
        return .{
            .allocator = allocator,
            .code = .{},
        };
    }
    
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *Assembler) void {
        self.code.deinit(self.allocator);
    }
    
    /// 获取当前代码位置
    pub fn position(self: *const Assembler) usize {
        return self.code.items.len;
    }
    
    // ========================================================================
    // REX 前缀生成
    // ========================================================================
    
    /// 生成 REX 前缀
    /// REX = 0100WRXB
    /// W = 1 for 64-bit operand size
    /// R = extension of ModR/M reg field
    /// X = extension of SIB index field
    /// B = extension of ModR/M r/m field, SIB base field, or opcode reg field
    fn emitRex(self: *Assembler, w: bool, r: bool, x: bool, b: bool) !void {
        var rex: u8 = 0x40;
        if (w) rex |= 0x08;
        if (r) rex |= 0x04;
        if (x) rex |= 0x02;
        if (b) rex |= 0x01;
        try self.code.append(self.allocator, rex);
    }
    
    /// 生成 REX.W 前缀（64位操作）
    fn emitRexW(self: *Assembler, reg: Register, rm: Register) !void {
        const r = reg.needsRex();
        const b = rm.needsRex();
        try self.emitRex(true, r, false, b);
    }
    
    // ========================================================================
    // ModR/M 和 SIB 字节生成
    // ========================================================================
    
    /// 生成 ModR/M 字节
    /// ModR/M = MMRRRMMM
    /// MM = addressing mode (00=indirect, 01=disp8, 10=disp32, 11=register)
    /// RRR = register operand
    /// MMM = r/m operand
    fn emitModRM(self: *Assembler, mod: u8, reg: u8, rm: u8) !void {
        const modrm = (mod << 6) | ((reg & 0x7) << 3) | (rm & 0x7);
        try self.code.append(self.allocator, modrm);
    }
    
    /// 生成 SIB 字节
    /// SIB = SSIIIBBB
    /// SS = scale (00=1, 01=2, 10=4, 11=8)
    /// III = index register
    /// BBB = base register
    fn emitSIB(self: *Assembler, scale: u8, index: u8, base: u8) !void {
        const sib = (scale << 6) | ((index & 0x7) << 3) | (base & 0x7);
        try self.code.append(self.allocator, sib);
    }
    
    // ========================================================================
    // 立即数编码
    // ========================================================================
    
    fn emitImm8(self: *Assembler, imm: i8) !void {
        try self.code.append(self.allocator, @bitCast(imm));
    }
    
    fn emitImm32(self: *Assembler, imm: i32) !void {
        const bytes = std.mem.toBytes(imm);
        try self.code.appendSlice(self.allocator, &bytes);
    }
    
    fn emitImm64(self: *Assembler, imm: i64) !void {
        const bytes = std.mem.toBytes(imm);
        try self.code.appendSlice(self.allocator, &bytes);
    }
    
    // ========================================================================
    // 基本指令：MOV
    // ========================================================================
    
    /// MOV reg, reg (64-bit)
    /// @pre dst 和 src 必须是有效寄存器
    /// @post 生成 mov dst, src 指令
    pub fn mov(self: *Assembler, dst: Register, src: Register) !void {
        try self.emitRexW(dst, src);
        try self.code.append(self.allocator, 0x89); // MOV r/m64, r64
        try self.emitModRM(0b11, src.code(), dst.code());
    }
    
    /// MOV reg, imm64
    /// @pre reg 必须是有效寄存器
    /// @post 生成 mov reg, imm 指令
    pub fn movImm64(self: *Assembler, reg: Register, imm: i64) !void {
        // REX.W + B0+rd io
        if (reg.needsRex()) {
            try self.emitRex(true, false, false, true);
        } else {
            try self.emitRex(true, false, false, false);
        }
        try self.code.append(self.allocator, 0xB8 + (reg.code() & 0x7));
        try self.emitImm64(imm);
    }
    
    /// MOV reg, imm32 (zero-extended to 64-bit)
    pub fn movImm32(self: *Assembler, reg: Register, imm: i32) !void {
        if (reg.needsRex()) {
            try self.emitRex(false, false, false, true);
        }
        try self.code.append(self.allocator, 0xB8 + (reg.code() & 0x7));
        try self.emitImm32(imm);
    }
    
    /// MOV reg, [base + offset]
    /// @pre reg 和 base 必须是有效寄存器
    /// @post 生成 mov reg, [base + offset] 指令
    pub fn movLoad(self: *Assembler, dst: Register, base: Register, offset: i32) !void {
        try self.emitRexW(dst, base);
        try self.code.append(self.allocator, 0x8B); // MOV r64, r/m64
        
        if (offset == 0 and base != .rbp and base != .r13) {
            // [base]
            try self.emitModRM(0b00, dst.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code()); // SIB needed for RSP/R12
            }
        } else if (offset >= -128 and offset <= 127) {
            // [base + disp8]
            try self.emitModRM(0b01, dst.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code());
            }
            try self.emitImm8(@intCast(offset));
        } else {
            // [base + disp32]
            try self.emitModRM(0b10, dst.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code());
            }
            try self.emitImm32(offset);
        }
    }
    
    /// MOV [base + offset], reg
    /// @pre reg 和 base 必须是有效寄存器
    /// @post 生成 mov [base + offset], reg 指令
    pub fn movStore(self: *Assembler, base: Register, offset: i32, src: Register) !void {
        try self.emitRexW(src, base);
        try self.code.append(self.allocator, 0x89); // MOV r/m64, r64
        
        if (offset == 0 and base != .rbp and base != .r13) {
            try self.emitModRM(0b00, src.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code());
            }
        } else if (offset >= -128 and offset <= 127) {
            try self.emitModRM(0b01, src.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code());
            }
            try self.emitImm8(@intCast(offset));
        } else {
            try self.emitModRM(0b10, src.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code());
            }
            try self.emitImm32(offset);
        }
    }
    
    // ========================================================================
    // 算术指令
    // ========================================================================
    
    /// ADD dst, src (64-bit)
    /// @pre dst 和 src 必须是有效寄存器
    /// @post 生成 add dst, src 指令
    pub fn add(self: *Assembler, dst: Register, src: Register) !void {
        try self.emitRexW(src, dst);
        try self.code.append(self.allocator, 0x01); // ADD r/m64, r64
        try self.emitModRM(0b11, src.code(), dst.code());
    }
    
    /// ADD reg, imm32
    pub fn addImm(self: *Assembler, reg: Register, imm: i32) !void {
        try self.emitRexW(.rax, reg);
        if (imm >= -128 and imm <= 127) {
            try self.code.append(self.allocator, 0x83); // ADD r/m64, imm8
            try self.emitModRM(0b11, 0, reg.code());
            try self.emitImm8(@intCast(imm));
        } else {
            try self.code.append(self.allocator, 0x81); // ADD r/m64, imm32
            try self.emitModRM(0b11, 0, reg.code());
            try self.emitImm32(imm);
        }
    }
    
    /// SUB dst, src (64-bit)
    pub fn sub(self: *Assembler, dst: Register, src: Register) !void {
        try self.emitRexW(src, dst);
        try self.code.append(self.allocator, 0x29); // SUB r/m64, r64
        try self.emitModRM(0b11, src.code(), dst.code());
    }
    
    /// SUB reg, imm32
    pub fn subImm(self: *Assembler, reg: Register, imm: i32) !void {
        try self.emitRexW(.rax, reg);
        if (imm >= -128 and imm <= 127) {
            try self.code.append(self.allocator, 0x83); // SUB r/m64, imm8
            try self.emitModRM(0b11, 5, reg.code());
            try self.emitImm8(@intCast(imm));
        } else {
            try self.code.append(self.allocator, 0x81); // SUB r/m64, imm32
            try self.emitModRM(0b11, 5, reg.code());
            try self.emitImm32(imm);
        }
    }
    
    /// IMUL dst, src (64-bit)
    /// @pre dst 和 src 必须是有效寄存器
    /// @post 生成 imul dst, src 指令
    pub fn imul(self: *Assembler, dst: Register, src: Register) !void {
        try self.emitRexW(dst, src);
        try self.code.append(self.allocator, 0x0F);
        try self.code.append(self.allocator, 0xAF); // IMUL r64, r/m64
        try self.emitModRM(0b11, dst.code(), src.code());
    }
    
    /// IMUL dst, src, imm32
    pub fn imulImm(self: *Assembler, dst: Register, src: Register, imm: i32) !void {
        try self.emitRexW(dst, src);
        if (imm >= -128 and imm <= 127) {
            try self.code.append(self.allocator, 0x6B); // IMUL r64, r/m64, imm8
            try self.emitModRM(0b11, dst.code(), src.code());
            try self.emitImm8(@intCast(imm));
        } else {
            try self.code.append(self.allocator, 0x69); // IMUL r64, r/m64, imm32
            try self.emitModRM(0b11, dst.code(), src.code());
            try self.emitImm32(imm);
        }
    }
    
    // ========================================================================
    // 位运算指令
    // ========================================================================
    
    /// SHL reg, imm8 (左移)
    /// @pre reg 必须是有效寄存器
    /// @post 生成 shl reg, imm 指令（强度削减优化：乘法转移位）
    pub fn shl(self: *Assembler, reg: Register, shift: u8) !void {
        try self.emitRexW(.rax, reg);
        if (shift == 1) {
            try self.code.append(self.allocator, 0xD1); // SHL r/m64, 1
            try self.emitModRM(0b11, 4, reg.code());
        } else {
            try self.code.append(self.allocator, 0xC1); // SHL r/m64, imm8
            try self.emitModRM(0b11, 4, reg.code());
            try self.code.append(self.allocator, shift);
        }
    }
    
    /// SHR reg, imm8 (逻辑右移)
    pub fn shr(self: *Assembler, reg: Register, shift: u8) !void {
        try self.emitRexW(.rax, reg);
        if (shift == 1) {
            try self.code.append(self.allocator, 0xD1); // SHR r/m64, 1
            try self.emitModRM(0b11, 5, reg.code());
        } else {
            try self.code.append(self.allocator, 0xC1); // SHR r/m64, imm8
            try self.emitModRM(0b11, 5, reg.code());
            try self.code.append(self.allocator, shift);
        }
    }
    
    /// SAR reg, imm8 (算术右移)
    pub fn sar(self: *Assembler, reg: Register, shift: u8) !void {
        try self.emitRexW(.rax, reg);
        if (shift == 1) {
            try self.code.append(self.allocator, 0xD1); // SAR r/m64, 1
            try self.emitModRM(0b11, 7, reg.code());
        } else {
            try self.code.append(self.allocator, 0xC1); // SAR r/m64, imm8
            try self.emitModRM(0b11, 7, reg.code());
            try self.code.append(self.allocator, shift);
        }
    }
    
    /// AND dst, src
    pub fn andReg(self: *Assembler, dst: Register, src: Register) !void {
        try self.emitRexW(src, dst);
        try self.code.append(self.allocator, 0x21); // AND r/m64, r64
        try self.emitModRM(0b11, src.code(), dst.code());
    }
    
    /// OR dst, src
    pub fn orReg(self: *Assembler, dst: Register, src: Register) !void {
        try self.emitRexW(src, dst);
        try self.code.append(self.allocator, 0x09); // OR r/m64, r64
        try self.emitModRM(0b11, src.code(), dst.code());
    }
    
    /// XOR dst, src
    pub fn xorReg(self: *Assembler, dst: Register, src: Register) !void {
        try self.emitRexW(src, dst);
        try self.code.append(self.allocator, 0x31); // XOR r/m64, r64
        try self.emitModRM(0b11, src.code(), dst.code());
    }
    
    // ========================================================================
    // 比较和测试指令
    // ========================================================================
    
    /// CMP reg1, reg2
    /// @pre reg1 和 reg2 必须是有效寄存器
    /// @post 生成 cmp reg1, reg2 指令，设置标志位
    pub fn cmp(self: *Assembler, reg1: Register, reg2: Register) !void {
        try self.emitRexW(reg2, reg1);
        try self.code.append(self.allocator, 0x39); // CMP r/m64, r64
        try self.emitModRM(0b11, reg2.code(), reg1.code());
    }
    
    /// CMP reg, imm32
    pub fn cmpImm(self: *Assembler, reg: Register, imm: i32) !void {
        try self.emitRexW(.rax, reg);
        if (imm >= -128 and imm <= 127) {
            try self.code.append(self.allocator, 0x83); // CMP r/m64, imm8
            try self.emitModRM(0b11, 7, reg.code());
            try self.emitImm8(@intCast(imm));
        } else {
            try self.code.append(self.allocator, 0x81); // CMP r/m64, imm32
            try self.emitModRM(0b11, 7, reg.code());
            try self.emitImm32(imm);
        }
    }
    
    /// TEST reg, reg
    pub fn testReg(self: *Assembler, reg1: Register, reg2: Register) !void {
        try self.emitRexW(reg2, reg1);
        try self.code.append(self.allocator, 0x85); // TEST r/m64, r64
        try self.emitModRM(0b11, reg2.code(), reg1.code());
    }
    
    /// TEST reg, imm32
    pub fn testImm(self: *Assembler, reg: Register, imm: i32) !void {
        try self.emitRexW(.rax, reg);
        if (reg == .rax) {
            try self.code.append(self.allocator, 0xA9); // TEST RAX, imm32
            try self.emitImm32(imm);
        } else {
            try self.code.append(self.allocator, 0xF7); // TEST r/m64, imm32
            try self.emitModRM(0b11, 0, reg.code());
            try self.emitImm32(imm);
        }
    }
    
    // ========================================================================
    // 条件设置指令
    // ========================================================================
    
    /// SETcc reg (设置字节条件)
    /// @pre reg 必须是有效寄存器
    /// @post 根据条件码设置寄存器低字节为 0 或 1
    pub fn setcc(self: *Assembler, cond: Condition, reg: Register) !void {
        if (reg.needsRex()) {
            try self.emitRex(false, false, false, true);
        }
        try self.code.append(self.allocator, 0x0F);
        try self.code.append(self.allocator, 0x90 + cond.code()); // SETcc r/m8
        try self.emitModRM(0b11, 0, reg.code());
    }
    
    /// CMOVcc dst, src (条件移动)
    /// @pre dst 和 src 必须是有效寄存器
    /// @post 如果条件满足，将 src 的值移动到 dst
    pub fn cmov(self: *Assembler, cond: Condition, dst: Register, src: Register) !void {
        // REX 前缀（如果需要）
        const needs_rex = dst.needsRex() or src.needsRex();
        if (needs_rex) {
            try self.emitRex(true, dst.needsRex(), false, src.needsRex());
        }
        
        // CMOVcc 指令：0F 40+cc /r
        try self.code.append(self.allocator, 0x0F);
        try self.code.append(self.allocator, 0x40 + cond.code());
        try self.emitModRM(0b11, dst.code(), src.code());
    }
    
    // ========================================================================
    // 跳转指令
    // ========================================================================
    
    /// JMP rel32 (无条件跳转)
    /// @pre offset 必须在 32 位范围内
    /// @post 生成 jmp 指令
    pub fn jmp(self: *Assembler, offset: i32) !void {
        try self.code.append(self.allocator, 0xE9); // JMP rel32
        try self.emitImm32(offset);
    }
    
    /// Jcc rel32 (条件跳转)
    /// @pre offset 必须在 32 位范围内
    /// @post 根据条件码生成条件跳转指令
    pub fn jcc(self: *Assembler, cond: Condition, offset: i32) !void {
        try self.code.append(self.allocator, 0x0F);
        try self.code.append(self.allocator, 0x80 + cond.code()); // Jcc rel32
        try self.emitImm32(offset);
    }
    
    /// JMP rel8 (短跳转)
    pub fn jmpShort(self: *Assembler, offset: i8) !void {
        try self.code.append(self.allocator, 0xEB); // JMP rel8
        try self.emitImm8(offset);
    }
    
    /// Jcc rel8 (短条件跳转)
    pub fn jccShort(self: *Assembler, cond: Condition, offset: i8) !void {
        try self.code.append(self.allocator, 0x70 + cond.code()); // Jcc rel8
        try self.emitImm8(offset);
    }
    
    // ========================================================================
    // 函数调用和返回
    // ========================================================================
    
    /// CALL rel32
    /// @pre offset 必须在 32 位范围内
    /// @post 生成 call 指令
    pub fn call(self: *Assembler, offset: i32) !void {
        try self.code.append(self.allocator, 0xE8); // CALL rel32
        try self.emitImm32(offset);
    }
    
    /// CALL reg (间接调用)
    pub fn callReg(self: *Assembler, reg: Register) !void {
        if (reg.needsRex()) {
            try self.emitRex(false, false, false, true);
        }
        try self.code.append(self.allocator, 0xFF); // CALL r/m64
        try self.emitModRM(0b11, 2, reg.code());
    }
    
    /// RET
    /// @post 生成 ret 指令
    pub fn ret(self: *Assembler) !void {
        try self.code.append(self.allocator, 0xC3); // RET
    }
    
    /// RET imm16 (带立即数的返回)
    pub fn retImm(self: *Assembler, imm: u16) !void {
        try self.code.append(self.allocator, 0xC2); // RET imm16
        const bytes = std.mem.toBytes(imm);
        try self.code.appendSlice(self.allocator, &bytes);
    }
    
    // ========================================================================
    // 栈操作
    // ========================================================================
    
    /// PUSH reg
    /// @pre reg 必须是有效寄存器
    /// @post 生成 push reg 指令
    pub fn push(self: *Assembler, reg: Register) !void {
        if (reg.needsRex()) {
            try self.emitRex(false, false, false, true);
        }
        try self.code.append(self.allocator, 0x50 + (reg.code() & 0x7)); // PUSH r64
    }
    
    /// POP reg
    /// @pre reg 必须是有效寄存器
    /// @post 生成 pop reg 指令
    pub fn pop(self: *Assembler, reg: Register) !void {
        if (reg.needsRex()) {
            try self.emitRex(false, false, false, true);
        }
        try self.code.append(self.allocator, 0x58 + (reg.code() & 0x7)); // POP r64
    }
    
    // ========================================================================
    // 其他指令
    // ========================================================================
    
    /// NOP
    pub fn nop(self: *Assembler) !void {
        try self.code.append(self.allocator, 0x90); // NOP
    }
    
    /// INT3 (断点)
    pub fn int3(self: *Assembler) !void {
        try self.code.append(self.allocator, 0xCC); // INT3
    }
    
    /// LEA dst, [base + offset]
    /// @pre dst 和 base 必须是有效寄存器
    /// @post 生成 lea dst, [base + offset] 指令
    pub fn lea(self: *Assembler, dst: Register, base: Register, offset: i32) !void {
        try self.emitRexW(dst, base);
        try self.code.append(self.allocator, 0x8D); // LEA r64, m
        
        if (offset == 0 and base != .rbp and base != .r13) {
            try self.emitModRM(0b00, dst.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code());
            }
        } else if (offset >= -128 and offset <= 127) {
            try self.emitModRM(0b01, dst.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code());
            }
            try self.emitImm8(@intCast(offset));
        } else {
            try self.emitModRM(0b10, dst.code(), base.code());
            if (base == .rsp or base == .r12) {
                try self.emitSIB(0, 4, base.code());
            }
            try self.emitImm32(offset);
        }
    }
};
