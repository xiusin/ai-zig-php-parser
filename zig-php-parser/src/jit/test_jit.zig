const std = @import("std");
const Assembler = @import("assembler_arm64.zig").Assembler;
const CodeCache = @import("code_cache.zig").CodeCache;
const Register = @import("assembler_arm64.zig").Register;

test "Assembler Encoding" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // Test 1: sub sp, sp, 64
    // 0xD10103FF
    try asm_.sub_imm(.sp, .sp, 64);
    
    // Test 2: str x19, [sp, 0]
    // 0xF90003F3
    try asm_.str(.x19, .sp, 0);
    
    // Test 3: mov x29, sp (add x29, sp, 0)
    // 0x910003FD
    try asm_.add_imm(.fp, .sp, 0);
    
    const code = asm_.code.items;
    
    try std.testing.expectEqual(@as(u32, 0xD10103FF), code[0]);
    try std.testing.expectEqual(@as(u32, 0xF90003F3), code[1]);
    try std.testing.expectEqual(@as(u32, 0x910003FD), code[2]);
}

test "JIT Execution" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    var code_cache = try CodeCache.init(allocator, 4096);
    defer code_cache.deinit();
    
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // Simple function: return 42
    // mov x0, 42
    // ret
    try asm_.movz(.x0, 42, 0);
    try asm_.ret();
    
    code_cache.unprotect();
    const code_ptr = try code_cache.allocate(asm_.code.items.len * 4);
    for (asm_.code.items, 0..) |inst, i| {
        std.mem.writeInt(u32, code_ptr[i*4..][0..4], inst, .little);
    }
    code_cache.flush(code_ptr);
    code_cache.protect();
    
    const func_ptr = @as(*const fn() usize, @ptrCast(@alignCast(code_ptr.ptr)));
    const result = func_ptr();
    
    try std.testing.expectEqual(@as(usize, 42), result);
}
