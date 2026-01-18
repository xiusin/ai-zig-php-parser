/// x86-64 代码生成器集成测试
const std = @import("std");
const testing = std.testing;
const Assembler = @import("assembler_x64.zig").Assembler;
const Register = @import("assembler_x64.zig").Register;
const Condition = @import("assembler_x64.zig").Condition;

test "Assembler: MOV instructions" {
    const allocator = testing.allocator;
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // MOV rax, rbx
    try asm_.mov(.rax, .rbx);
    try testing.expect(asm_.code.items.len > 0);
    
    // MOV rax, 42
    try asm_.movImm64(.rax, 42);
    try testing.expect(asm_.code.items.len > 3);
}

test "Assembler: arithmetic instructions" {
    const allocator = testing.allocator;
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // ADD rax, rbx
    try asm_.add(.rax, .rbx);
    try testing.expect(asm_.code.items.len > 0);
    
    // SUB rax, rbx
    try asm_.sub(.rax, .rbx);
    try testing.expect(asm_.code.items.len > 3);
    
    // IMUL rax, rbx
    try asm_.imul(.rax, .rbx);
    try testing.expect(asm_.code.items.len > 6);
}

test "Assembler: shift instructions (strength reduction)" {
    const allocator = testing.allocator;
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // SHL rax, 3 (multiply by 8)
    try asm_.shl(.rax, 3);
    try testing.expect(asm_.code.items.len > 0);
    
    // SHR rax, 2 (divide by 4)
    try asm_.shr(.rax, 2);
    try testing.expect(asm_.code.items.len > 3);
}

test "Assembler: comparison and conditional" {
    const allocator = testing.allocator;
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // CMP rax, rbx
    try asm_.cmp(.rax, .rbx);
    try testing.expect(asm_.code.items.len > 0);
    
    // Note: setcc 需要 8 位寄存器，我们使用 cmov 代替
    // 测试 cmov 指令
    try asm_.cmov(.L, .rax, .rbx);
    try testing.expect(asm_.code.items.len > 3);
}

test "Assembler: jump instructions" {
    const allocator = testing.allocator;
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // JMP +10
    try asm_.jmp(10);
    try testing.expect(asm_.code.items.len == 5);
    
    // JE +20 (jump if equal)
    try asm_.jcc(.E, 20);
    try testing.expect(asm_.code.items.len == 11);
}

test "Assembler: function prologue and epilogue" {
    const allocator = testing.allocator;
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // Prologue
    try asm_.push(.rbp);
    try asm_.mov(.rbp, .rsp);
    try asm_.subImm(.rsp, 32);
    
    // Epilogue
    try asm_.addImm(.rsp, 32);
    try asm_.pop(.rbp);
    try asm_.ret();
    
    try testing.expect(asm_.code.items.len > 10);
}

test "Assembler: memory operations" {
    const allocator = testing.allocator;
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // MOV rax, [rbp - 8]
    try asm_.movLoad(.rax, .rbp, -8);
    try testing.expect(asm_.code.items.len > 0);
    
    // MOV [rbp - 16], rbx
    try asm_.movStore(.rbp, -16, .rbx);
    try testing.expect(asm_.code.items.len > 4);
    
    // LEA rax, [rbp + 32]
    try asm_.lea(.rax, .rbp, 32);
    try testing.expect(asm_.code.items.len > 8);
}

test "Assembler: complete function example" {
    const allocator = testing.allocator;
    var asm_ = Assembler.init(allocator);
    defer asm_.deinit();
    
    // 生成一个简单的函数：int add(int a, int b) { return a + b; }
    // 参数在 RDI 和 RSI 中（System V ABI）
    
    // Prologue
    try asm_.push(.rbp);
    try asm_.mov(.rbp, .rsp);
    
    // Function body: rax = rdi + rsi
    try asm_.mov(.rax, .rdi);
    try asm_.add(.rax, .rsi);
    
    // Epilogue
    try asm_.pop(.rbp);
    try asm_.ret();
    
    // 验证生成了代码
    try testing.expect(asm_.code.items.len > 0);
    
    // 打印生成的机器码（用于调试）
    std.debug.print("\nGenerated machine code ({d} bytes):\n", .{asm_.code.items.len});
    for (asm_.code.items, 0..) |byte, i| {
        if (i % 16 == 0) std.debug.print("\n{x:0>4}: ", .{i});
        std.debug.print("{x:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});
}
