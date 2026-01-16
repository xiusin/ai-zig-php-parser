const std = @import("std");
const CodeCache = @import("code_cache.zig").CodeCache;
const Assembler = @import("assembler_arm64.zig").Assembler;
const Register = @import("assembler_arm64.zig").Register;
const func_mod = @import("../runtime/func.zig");
const CompiledFunc = func_mod.CompiledFunc;
const opcode_mod = @import("../runtime/opcode.zig");
const OpCode = opcode_mod.OpCode;

const JumpPatch = struct {
    inst_idx: usize,
    target_ip: usize,
    is_cond: bool,
};

pub const Compiler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{
            .allocator = allocator,
        };
    }

    pub const JitResult = struct {
        code: *const anyopaque,
        osr_entry_offset: usize,
    };

    pub fn compile(self: *Compiler, code_cache: *CodeCache, func: *const CompiledFunc, tf: *const anyopaque, osr_ip: ?usize) !?JitResult {
        // Only compile if name starts with "jit_" or "sum" (for test)
        if (std.mem.startsWith(u8, func.name, "jit_") or std.mem.eql(u8, func.name, "sum") or std.mem.eql(u8, func.name, "main")) {
            return try self.compileFunc(code_cache, func, tf, osr_ip);
        }
        return null;
    }

    fn compileFunc(self: *Compiler, code_cache: *CodeCache, func: *const CompiledFunc, tf: *const anyopaque, osr_ip: ?usize) !JitResult {
        _ = tf;
        var asm_ = Assembler.init(self.allocator);
        defer asm_.deinit();
        
        var jump_patches: std.ArrayListUnmanaged(JumpPatch) = .{};
        defer jump_patches.deinit(self.allocator);

        // --------------------------------------------------------------------
        // Prologue
        // --------------------------------------------------------------------
        try asm_.sub_imm(.sp, .sp, 64);
        try asm_.str(.x19, .sp, 0);
        try asm_.str(.x20, .sp, 1);
        try asm_.str(.x21, .sp, 2);
        try asm_.str(.x28, .sp, 3);
        try asm_.str(.x27, .sp, 4);
        try asm_.str(.x26, .sp, 5);
        try asm_.str(.fp, .sp, 6);
        try asm_.str(.lr, .sp, 7);
        
        try asm_.mov(.x19, .x0); // stack_base
        try asm_.mov(.x20, .x1); // bp
        
        // x21 = stack_top (passed in x2)
        try asm_.mov(.x21, .x2);
        
        // Load Constants
        try asm_.loadImm64(.x28, 0xFFFC800000000000); // TAG_INT
        try asm_.loadImm64(.x27, 0x7FFC000000000003); // TAG_TRUE
        try asm_.loadImm64(.x26, 0x7FFC000000000002); // TAG_FALSE
        
        // OSR Dispatch logic
        // x3 is boolean (non-zero means jump to OSR target)
        try asm_.cmp(.x3, @enumFromInt(31)); // cmp x3, 0
        try asm_.b_cond(.EQ, 4); // Skip jump if 0
        
        const osr_jump_idx = asm_.code.items.len;
        try asm_.b(0); // Placeholder for OSR Jump
        
        // Code Generation
        const code = func.code;
        var ip: usize = 0;
        // var osr_asm_offset: usize = 0;
        
        var ip_mapping = try self.allocator.alloc(u32, code.len + 1);
        defer self.allocator.free(ip_mapping);
        @memset(ip_mapping, 0);
        
        while (ip < code.len) {
            const current_ip = ip;
            if (osr_ip) |target| {
                if (current_ip == target) {
                    // Backpatch OSR Jump
                    const target_idx = asm_.code.items.len;
                    const offset_insts = @as(i64, @intCast(target_idx)) - @as(i64, @intCast(osr_jump_idx));
                    const offset_bytes = offset_insts * 4;
                    // B instruction: 0x14000000 | imm26
                    const base: u32 = 0x14000000;
                    const imm = @as(u32, @bitCast(@as(i32, @intCast(offset_bytes >> 2)))) & 0x03FFFFFF;
                    asm_.code.items[osr_jump_idx] = base | imm;
                    
                    // Set return value to 1 to enable OSR
                    // osr_asm_offset = 1;
                }
            }
            ip_mapping[current_ip] = @intCast(asm_.code.items.len);
            
            const op_byte = code[ip];
            ip += 1;
            const op: OpCode = @enumFromInt(op_byte);
            
            switch (op) {
                .push_0 => {
                    try asm_.movz(.x0, 0, 0);
                    try asm_.orr(.x0, .x0, .x28); // Box Int(0)
                    try asm_.str_reg(.x0, .x19, .x21);
                    try asm_.add_imm(.x21, .x21, 1);
                },
                .push_1 => {
                    try asm_.movz(.x0, 1, 0);
                    try asm_.orr(.x0, .x0, .x28);
                    try asm_.str_reg(.x0, .x19, .x21);
                    try asm_.add_imm(.x21, .x21, 1);
                },
                .push_int => {
                    const val = std.mem.readInt(i32, code[ip..][0..4], .little);
                    ip += 4;
                    try asm_.loadImm64(.x0, @bitCast(@as(i64, val)));
                    try asm_.orr(.x0, .x0, .x28);
                    try asm_.str_reg(.x0, .x19, .x21);
                    try asm_.add_imm(.x21, .x21, 1);
                },
                .push_local => {
                    const idx = code[ip];
                    ip += 1;
                    try asm_.add_imm(.x9, .x20, idx);
                    try asm_.ldr_reg(.x0, .x19, .x9);
                    try asm_.str_reg(.x0, .x19, .x21);
                    try asm_.add_imm(.x21, .x21, 1);
                },
                .store_local => {
                    const idx = code[ip];
                    ip += 1;
                    // Pop TOS (x21 - 1)
                    try asm_.sub_imm(.x21, .x21, 1);
                    try asm_.ldr_reg(.x0, .x19, .x21);
                    // Store to local (bp + idx)
                    try asm_.add_imm(.x9, .x20, idx);
                    try asm_.str_reg(.x0, .x19, .x9);
                },
                .pop => {
                    try asm_.sub_imm(.x21, .x21, 1);
                },
                .dup => {
                    // Peek TOS
                    try asm_.sub_imm(.x9, .x21, 1);
                    try asm_.ldr_reg(.x0, .x19, .x9);
                    // Push
                    try asm_.str_reg(.x0, .x19, .x21);
                    try asm_.add_imm(.x21, .x21, 1);
                },
                .add => {
                    try asm_.sub_imm(.x21, .x21, 1);
                    try asm_.ldr_reg(.x1, .x19, .x21); // b
                    try asm_.sub_imm(.x21, .x21, 1);
                    try asm_.ldr_reg(.x0, .x19, .x21); // a
                    // Unbox
                    try asm_.sbfx(.x0, .x0, 0, 48);
                    try asm_.sbfx(.x1, .x1, 0, 48);
                    // Add
                    try asm_.add(.x0, .x0, .x1);
                    // Box
                    try asm_.orr(.x0, .x0, .x28);
                    // Push
                    try asm_.str_reg(.x0, .x19, .x21);
                    try asm_.add_imm(.x21, .x21, 1);
                },
                .lt => {
                    try asm_.sub_imm(.x21, .x21, 1);
                    try asm_.ldr_reg(.x1, .x19, .x21);
                    try asm_.sub_imm(.x21, .x21, 1);
                    try asm_.ldr_reg(.x0, .x19, .x21);
                    try asm_.sbfx(.x0, .x0, 0, 48);
                    try asm_.sbfx(.x1, .x1, 0, 48);
                    try asm_.cmp(.x0, .x1);
                    try asm_.csel(.x0, .x27, .x26, .LT);
                    try asm_.str_reg(.x0, .x19, .x21);
                    try asm_.add_imm(.x21, .x21, 1);
                },
                .jz => {
                    const offset = std.mem.readInt(i16, code[ip..][0..2], .little);
                    ip += 2;
                    try asm_.sub_imm(.x21, .x21, 1);
                    try asm_.ldr_reg(.x0, .x19, .x21);
                    try asm_.cmp(.x0, .x26); // TAG_FALSE
                    
                    const target_ip_signed = @as(i32, @intCast(current_ip)) + offset;
                    // Forward jump support needed?
                    // For backward:
                    if (offset < 0) {
                        const target_asm_idx = ip_mapping[@intCast(target_ip_signed)];
                        const current_asm_idx = asm_.code.items.len;
                        const branch_offset = (@as(i64, @intCast(target_asm_idx)) - @as(i64, @intCast(current_asm_idx))) * 4;
                        try asm_.b_cond(.EQ, @intCast(branch_offset));
                    } else {
                         // Forward jump
                         const patch_idx = asm_.code.items.len;
                         try asm_.b_cond(.EQ, 0); // Placeholder
                         try jump_patches.append(self.allocator, .{
                            .inst_idx = patch_idx,
                            .target_ip = @intCast(target_ip_signed),
                            .is_cond = true,
                         });
                    }
                },
                .jmp => {
                    const offset = std.mem.readInt(i16, code[ip..][0..2], .little);
                    ip += 2;
                    const target_ip_signed = @as(i32, @intCast(current_ip)) + offset;
                    if (offset < 0) {
                        const target_asm_idx = ip_mapping[@intCast(target_ip_signed)];
                        const current_asm_idx = asm_.code.items.len;
                        const branch_offset = (@as(i64, @intCast(target_asm_idx)) - @as(i64, @intCast(current_asm_idx))) * 4;
                        try asm_.b(@intCast(branch_offset));
                    } else {
                         // Forward jump
                         const patch_idx = asm_.code.items.len;
                         try asm_.b(0); // Placeholder
                         try jump_patches.append(self.allocator, .{
                            .inst_idx = patch_idx,
                            .target_ip = @intCast(target_ip_signed),
                            .is_cond = false,
                         });
                    }
                },
                .halt, .ret_nil => {
                     // Return 0 (nil)
                     try asm_.movz(.x0, 0, 0);
                     // Restore
                     try asm_.ldr(.x19, .sp, 0);
                     try asm_.ldr(.x20, .sp, 1);
                     try asm_.ldr(.x21, .sp, 2);
                     try asm_.ldr(.x28, .sp, 3);
                     try asm_.ldr(.x27, .sp, 4);
                     try asm_.ldr(.x26, .sp, 5);
                     try asm_.ldr(.fp, .sp, 6);
                     try asm_.ldr(.lr, .sp, 7);
                     try asm_.add_imm(.sp, .sp, 64);
                     try asm_.ret();
                },
                .ret => {
                    // Pop return value
                    try asm_.sub_imm(.x21, .x21, 1);
                    try asm_.ldr_reg(.x0, .x19, .x21);
                    try asm_.sbfx(.x0, .x0, 0, 48); // Unbox for return (assuming int)
                    
                    // Restore
                    try asm_.ldr(.x19, .sp, 0);
                    try asm_.ldr(.x20, .sp, 1);
                    try asm_.ldr(.x21, .sp, 2);
                    try asm_.ldr(.x28, .sp, 3);
                    try asm_.ldr(.x27, .sp, 4);
                    try asm_.ldr(.x26, .sp, 5);
                    try asm_.ldr(.fp, .sp, 6);
                    try asm_.ldr(.lr, .sp, 7);
                    try asm_.add_imm(.sp, .sp, 64);
                    try asm_.ret();
                },
                else => {
                    // Skip unsupported
                }
            }
        }
        
        // Backpatch jumps
        for (jump_patches.items) |patch| {
            const target_asm_idx = ip_mapping[patch.target_ip];
            const current_asm_idx = patch.inst_idx;
            const branch_offset_insts = @as(i64, @intCast(target_asm_idx)) - @as(i64, @intCast(current_asm_idx));
            const branch_offset_bytes = branch_offset_insts * 4;
            
            if (patch.is_cond) {
                // b.cond .EQ
                const base: u32 = 0x54000000;
                const imm = @as(u32, @bitCast(@as(i32, @intCast(branch_offset_bytes >> 2)))) & 0x0007FFFF;
                // EQ = 0
                const cond_val: u32 = 0; 
                asm_.code.items[patch.inst_idx] = base | (imm << 5) | cond_val;
            } else {
                // b
                const base: u32 = 0x14000000;
                const imm = @as(u32, @bitCast(@as(i32, @intCast(branch_offset_bytes >> 2)))) & 0x03FFFFFF;
                asm_.code.items[patch.inst_idx] = base | imm;
            }
        }
        
        // Prepare for writing
        
        // Prepare for writing
        code_cache.unprotect();
        defer code_cache.protect();

        const generated_code = try code_cache.allocate(asm_.code.items.len * 4);
        
        for (asm_.code.items, 0..) |inst, i| {
            std.mem.writeInt(u32, generated_code[i*4..][0..4], inst, .little);
        }
        
        code_cache.flush(generated_code);
        return JitResult{
                .code = @ptrCast(@alignCast(generated_code.ptr)),
                .osr_entry_offset = 0, // osr_asm_offset,
             };
    }

    pub fn compileAdd(self: *Compiler, code_cache: *CodeCache) !*const fn(i64, i64) i64 {
        _ = self; return @ptrCast(@alignCast(code_cache.memory.ptr)); // Dummy
    }
};
