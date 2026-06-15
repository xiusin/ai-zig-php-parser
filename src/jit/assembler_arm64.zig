const std = @import("std");

pub const Register = enum(u5) {
    x0 = 0, x1, x2, x3, x4, x5, x6, x7,
    x8, x9, x10, x11, x12, x13, x14, x15,
    x16, x17, x18, x19, x20, x21, x22, x23,
    x24, x25, x26, x27, x28,
    fp = 29,
    lr = 30,
    sp = 31, // or zr depending on context
};

pub const Assembler = struct {
    code: std.ArrayListUnmanaged(u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Assembler {
        return .{
            .code = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Assembler) void {
        self.code.deinit(self.allocator);
    }

    pub fn emit(self: *Assembler, inst: u32) !void {
        try self.code.append(self.allocator, inst);
    }

    /// RET (Return from subroutine)
    pub fn ret(self: *Assembler) !void {
        try self.emit(0xD65F03C0);
    }

    /// ADD (Immediate) - 64-bit
    /// add rd, rn, #imm
    pub fn add_imm(self: *Assembler, rd: Register, rn: Register, imm: u12) !void {
        // sf=1, op=0, S=0, 100010, sh=0, imm12, Rn, Rd
        // 0x91000000
        const base: u32 = 0x91000000;
        const imm_val = @as(u32, imm) << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(base | imm_val | rn_val | rd_val);
    }

    /// SUB (Immediate) - 64-bit
    /// sub rd, rn, #imm
    pub fn sub_imm(self: *Assembler, rd: Register, rn: Register, imm: u12) !void {
        // sf=1, op=1, S=0, 100010, sh=0, imm12, Rn, Rd
        // 0xD1000000
        const base: u32 = 0xD1000000;
        const imm_val = @as(u32, imm) << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(base | imm_val | rn_val | rd_val);
    }

    /// ADD (shifted register) - 64-bit
    /// add xd, xn, xm
    pub fn add(self: *Assembler, rd: Register, rn: Register, rm: Register) !void {
        const sf: u32 = 1 << 31;
        const op: u32 = 0b0001011 << 24;
        const shift: u32 = 0 << 22;
        const rm_val = @as(u32, @intFromEnum(rm)) << 16;
        const imm6: u32 = 0 << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(sf | op | shift | rm_val | imm6 | rn_val | rd_val);
    }

    /// SUB (shifted register) - 64-bit
    /// sub xd, xn, xm
    pub fn sub(self: *Assembler, rd: Register, rn: Register, rm: Register) !void {
        const sf: u32 = 1 << 31;
        const op: u32 = 0b1001011 << 24; // Bit 30 is 1 for SUB (10)
        const shift: u32 = 0 << 22;
        const rm_val = @as(u32, @intFromEnum(rm)) << 16;
        const imm6: u32 = 0 << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(sf | op | shift | rm_val | imm6 | rn_val | rd_val);
    }
    
    /// SUBS (shifted register) - 64-bit (Set Flags)
    /// subs xd, xn, xm
    pub fn subs(self: *Assembler, rd: Register, rn: Register, rm: Register) !void {
        const sf: u32 = 1 << 31;
        const op: u32 = 0b1101011 << 24; // Bit 30,29 is 11 for SUBS
        const shift: u32 = 0 << 22;
        const rm_val = @as(u32, @intFromEnum(rm)) << 16;
        const imm6: u32 = 0 << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(sf | op | shift | rm_val | imm6 | rn_val | rd_val);
    }

    /// CMP (shifted register) - alias for SUBS xzr, xn, xm
    pub fn cmp(self: *Assembler, rn: Register, rm: Register) !void {
        // xzr is 31
        try self.subs(@enumFromInt(31), rn, rm);
    }

    /// B.cond (Conditional Branch)
    /// b.cond label
    pub const Cond = enum(u4) {
        EQ = 0x0, // Equal (Z=1)
        NE = 0x1, // Not Equal (Z=0)
        CS = 0x2, // Carry Set
        CC = 0x3, // Carry Clear
        MI = 0x4, // Minus (N=1)
        PL = 0x5, // Plus (N=0)
        VS = 0x6, // Overflow Set
        VC = 0x7, // Overflow Clear
        HI = 0x8, // Unsigned Higher
        LS = 0x9, // Unsigned Lower or Same
        GE = 0xA, // Signed Greater or Equal
        LT = 0xB, // Signed Less Than
        GT = 0xC, // Signed Greater Than
        LE = 0xD, // Signed Less or Equal
    };

    pub fn b_cond(self: *Assembler, cond: Cond, offset_bytes: i19) !void {
        // 0101 0100 ...
        // 0x54000000
        const base: u32 = 0x54000000;
        // imm19 is instruction offset (divide by 4)
        const imm = @as(u32, @bitCast(@as(i32, offset_bytes >> 2))) & 0x0007FFFF;
        const cond_val = @as(u32, @intFromEnum(cond));
        try self.emit(base | (imm << 5) | cond_val);
    }
    
    /// MOV (register) - alias for ORR xd, xzr, xm
    pub fn mov(self: *Assembler, rd: Register, rm: Register) !void {
        // ORR (shifted register)
        // sf=1, op=0, S=0, 1010, shift=00, 0, Rm, imm6=0, Rn=XZR(31), Rd
        const sf: u32 = 1 << 31;
        const op: u32 = 0b00101010 << 24;
        const rm_val = @as(u32, @intFromEnum(rm)) << 16;
        const rn_val = 31 << 5; // XZR
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(sf | op | rm_val | rn_val | rd_val);
    }

    /// MOVK (Move wide with keep) - 16-bit immediate
    /// movk xd, #imm, lsl #shift
    pub fn movk(self: *Assembler, rd: Register, imm: u16, shift_val: u2) !void {
        const sf: u32 = 1 << 31;
        // 1 11 100101
        const op: u32 = 0b111100101 << 23;
        const hw: u32 = @as(u32, shift_val) << 21;
        const imm16: u32 = @as(u32, imm) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));

        try self.emit(sf | op | hw | imm16 | rd_val);
    }

    /// MOVZ (Move wide with zero) - 16-bit immediate
    /// movz xd, #imm, lsl #shift
    pub fn movz(self: *Assembler, rd: Register, imm: u16, shift_val: u2) !void {
        const sf: u32 = 1 << 31;
        // 1 10 100101
        const op: u32 = 0b110100101 << 23;
        const hw: u32 = @as(u32, shift_val) << 21;
        const imm16: u32 = @as(u32, imm) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));

        try self.emit(sf | op | hw | imm16 | rd_val);
    }
    
    /// Load 64-bit immediate into register
    pub fn loadImm64(self: *Assembler, rd: Register, val: u64) !void {
        try self.movz(rd, @truncate(val), 0);
        if ((val >> 16) & 0xFFFF != 0) try self.movk(rd, @truncate(val >> 16), 1);
        if ((val >> 32) & 0xFFFF != 0) try self.movk(rd, @truncate(val >> 32), 2);
        if ((val >> 48) & 0xFFFF != 0) try self.movk(rd, @truncate(val >> 48), 3);
    }

    /// LDR (Register) - 64-bit
    /// ldr rt, [rn, rm, lsl #3]
    pub fn ldr_reg(self: *Assembler, rt: Register, rn: Register, rm: Register) !void {
        // size=11, 111, 000, 01, V=0, Rm, option=011, S=1, 10, Rn, Rt
        // 0xF8607800 | (Rm << 16) | (Rn << 5) | Rt
        // Bit 21=1, Bit 12=1 for scaled offset
        const base: u32 = 0xF8607800;
        const rm_val = @as(u32, @intFromEnum(rm)) << 16;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rt_val = @as(u32, @intFromEnum(rt));
        
        try self.emit(base | rm_val | rn_val | rt_val);
    }

    /// STR (Register) - 64-bit
    /// str rt, [rn, rm, lsl #3]
    pub fn str_reg(self: *Assembler, rt: Register, rn: Register, rm: Register) !void {
        // size=11, 111, 000, 00, V=0, Rm, option=011, S=1, 10, Rn, Rt
        // 0xF8207800
        const base: u32 = 0xF8207800;
        const rm_val = @as(u32, @intFromEnum(rm)) << 16;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rt_val = @as(u32, @intFromEnum(rt));
        
        try self.emit(base | rm_val | rn_val | rt_val);
    }

    /// LSL (Logical Shift Left) - alias for UBFM
    /// lsl rd, rn, #shift
    pub fn lsl(self: *Assembler, rd: Register, rn: Register, shift: u6) !void {
        // UBFM 64-bit: 1 10 10011 0 ...
        // sf=1, opc=10, 10011, 0, N, immr, imms, Rn, Rd
        // For LSL #shift: immr = -shift mod 64, imms = 63 - shift
        // immr = (64 - shift) & 63
        // imms = 63 - shift
        
        const sf: u32 = 1 << 31;
        const opc: u32 = 0b10100110 << 23;
        const n: u32 = 1 << 22;
        const shift_val = @as(u32, shift);
        const immr = ((64 - shift_val) & 63) << 16;
        const imms = (63 - shift_val) << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(sf | opc | n | immr | imms | rn_val | rd_val);
    }

    /// STR (Immediate, Unsigned offset) - 64-bit
    /// str rt, [rn, #imm]
    /// imm is scaled by 8
    pub fn str(self: *Assembler, rt: Register, rn: Register, imm_offset: u12) !void {
        // size=11, 111, 001, 00, imm12, Rn, Rt
        // 0xF9000000
        const base: u32 = 0xF9000000;
        const imm = @as(u32, imm_offset) << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rt_val = @as(u32, @intFromEnum(rt));
        try self.emit(base | imm | rn_val | rt_val);
    }

    /// LDR (Immediate, Unsigned offset) - 64-bit
    /// ldr rt, [rn, #imm]
    /// imm is scaled by 8
    pub fn ldr(self: *Assembler, rt: Register, rn: Register, imm_offset: u12) !void {
        // size=11, 111, 001, 01, imm12, Rn, Rt
        // 0xF9400000
        const base: u32 = 0xF9400000;
        const imm = @as(u32, imm_offset) << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rt_val = @as(u32, @intFromEnum(rt));
        try self.emit(base | imm | rn_val | rt_val);
    }

    /// B (Unconditional Branch)
    /// b label (offset in bytes)
    pub fn b(self: *Assembler, offset_bytes: i28) !void {
        // 0001 0100 ...
        // 0x14000000
        const base: u32 = 0x14000000;
        // Divide by 4 for instruction offset
        const imm = @as(u32, @bitCast(@as(i32, offset_bytes >> 2))) & 0x03FFFFFF;
        try self.emit(base | imm);
    }

    /// BL (Branch with Link)
    /// bl label (offset in bytes)
    pub fn bl(self: *Assembler, offset_bytes: i28) !void {
        // 1001 0100 ...
        // 0x94000000
        const base: u32 = 0x94000000;
        const imm = @as(u32, @bitCast(@as(i32, offset_bytes >> 2))) & 0x03FFFFFF;
        try self.emit(base | imm);
    }
    
    /// BR (Branch to Register)
    pub fn br(self: *Assembler, rn: Register) !void {
        // 1101 0110 0001 1111 0000 00 Rn 00000
        // 0xD61F0000
        const base: u32 = 0xD61F0000;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        try self.emit(base | rn_val);
    }

    /// BLR (Branch with Link to Register)
    pub fn blr(self: *Assembler, rn: Register) !void {
        // 1101 0110 0011 1111 0000 00 Rn 00000
        // 0xD63F0000
        const base: u32 = 0xD63F0000;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        try self.emit(base | rn_val);
    }

    /// SBFX (Signed Bitfield Extract)
    /// sbfx rd, rn, #lsb, #width
    pub fn sbfx(self: *Assembler, rd: Register, rn: Register, lsb: u6, width: u6) !void {
        // sf=1, opc=00, 100110, N=1, immr=lsb, imms=lsb+width-1, Rn, Rd
        // 0x93400000
        const sf: u32 = 1 << 31;
        const opc: u32 = 0b00100110 << 23;
        const n: u32 = 1 << 22; // N=1 for 64-bit
        const immr = @as(u32, lsb) << 16;
        const imms = @as(u32, lsb + width - 1) << 10;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(sf | opc | n | immr | imms | rn_val | rd_val);
    }
    
    /// ORR (shifted register)
    /// orr rd, rn, rm
    pub fn orr(self: *Assembler, rd: Register, rn: Register, rm: Register) !void {
        // sf=1, op=0, S=0, 1010, shift=00, 0, Rm, imm6=0, Rn, Rd
        // 0xAA000000
        const base: u32 = 0xAA000000;
        const rm_val = @as(u32, @intFromEnum(rm)) << 16;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        try self.emit(base | rm_val | rn_val | rd_val);
    }
    
    /// CSEL (Conditional Select)
    /// csel rd, rn, rm, cond
    pub fn csel(self: *Assembler, rd: Register, rn: Register, rm: Register, cond: Cond) !void {
        // sf=1, op=0, S=0, 11010, 1, Rm, cond, 0, Rn, Rd
        // 0x9A800000
        const base: u32 = 0x9A800000;
        const rm_val = @as(u32, @intFromEnum(rm)) << 16;
        const cond_val = @as(u32, @intFromEnum(cond)) << 12;
        const rn_val = @as(u32, @intFromEnum(rn)) << 5;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(base | rm_val | cond_val | rn_val | rd_val);
    }

    /// ADR (Form PC-relative address)
    /// adr rd, label
    pub fn adr(self: *Assembler, rd: Register, offset: i21) !void {
        // 0 00 10000 ...
        // 0x10000000
        // immlo (2 bits), immhi (19 bits)
        // imm = offset
        const base: u32 = 0x10000000;
        const imm = @as(u32, @bitCast(@as(i32, offset)));
        const immlo = imm & 3;
        const immhi = (imm >> 2) & 0x7FFFF;
        const rd_val = @as(u32, @intFromEnum(rd));
        
        try self.emit(base | (immlo << 29) | (immhi << 5) | rd_val);
    }
};
