# x86-64 代码生成器实现文档

## 概述

本文档描述了 Zig-PHP JIT 编译器的 x86-64 代码生成器实现，包括指令编码、类型特化、强度削减优化和方法内联等功能。

## 实现的组件

### 1. x86-64 汇编器 (`src/jit/assembler_x64.zig`)

完整实现了 x86-64 指令集的汇编器，支持：

#### 1.1 寄存器定义
- 16 个通用寄存器：RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI, R8-R15
- 自动处理 REX 前缀（用于 64 位操作和扩展寄存器）

#### 1.2 指令编码

**数据传输指令**：
- `MOV reg, reg` - 寄存器间传输
- `MOV reg, imm64` - 加载 64 位立即数
- `MOV reg, [base + offset]` - 内存加载
- `MOV [base + offset], reg` - 内存存储
- `LEA reg, [base + offset]` - 加载有效地址

**算术指令**：
- `ADD dst, src` - 加法
- `SUB dst, src` - 减法
- `IMUL dst, src` - 有符号乘法
- `IMUL dst, src, imm` - 带立即数的乘法

**位运算指令**（强度削减优化）：
- `SHL reg, imm` - 左移（乘以 2 的幂）
- `SHR reg, imm` - 逻辑右移（除以 2 的幂）
- `SAR reg, imm` - 算术右移
- `AND dst, src` - 按位与
- `OR dst, src` - 按位或
- `XOR dst, src` - 按位异或

**比较和测试指令**：
- `CMP reg1, reg2` - 比较
- `CMP reg, imm` - 与立即数比较
- `TEST reg1, reg2` - 测试（按位与但不保存结果）
- `SETcc reg` - 根据条件设置字节

**控制流指令**：
- `JMP rel32` - 无条件跳转
- `Jcc rel32` - 条件跳转（支持所有条件码）
- `CALL rel32` - 函数调用
- `CALL reg` - 间接调用
- `RET` - 返回

**栈操作指令**：
- `PUSH reg` - 压栈
- `POP reg` - 出栈

#### 1.3 编码细节

- **REX 前缀**：自动生成 REX.W 前缀用于 64 位操作
- **ModR/M 字节**：正确编码寻址模式和寄存器
- **SIB 字节**：处理 RSP/R12 作为基址寄存器的特殊情况
- **立即数**：支持 8 位、32 位和 64 位立即数

### 2. x86-64 代码生成器 (`src/jit/codegen_x64.zig`)

#### 2.1 函数序言和尾声

**序言**（遵循 System V AMD64 ABI）：
```asm
push rbp
mov rbp, rsp
push rbx
push r12
push r13
push r14
push r15
sub rsp, 64  ; 分配栈空间
mov r12, rdi ; 保存 stack_base
mov r13, rsi ; 保存 bp
mov r14, rdx ; 保存 stack_top
```

**尾声**：
```asm
add rsp, 64
pop r15
pop r14
pop r13
pop r12
pop rbx
pop rbp
ret
```

#### 2.2 类型特化代码生成

根据类型信息生成优化的代码：

**整数加法**（类型特化）：
```zig
if (type_info[0] == .int and type_info[1] == .int) {
    // 直接使用 ADD 指令
    try self.asm_.add(.rax, .rbx);
} else {
    // 调用运行时函数处理动态类型
    // ...
}
```

#### 2.3 强度削减优化

自动将乘以 2 的幂优化为左移：

```zig
if (constant_value) |val| {
    if (val > 0 and std.math.isPowerOfTwo(@as(u64, @intCast(val)))) {
        // 优化：x * 8 => x << 3
        const shift = std.math.log2_int(u64, @intCast(val));
        try self.asm_.shl(.rax, @intCast(shift));
        return;
    }
}
// 普通乘法
try self.asm_.imul(.rax, .rbx);
```

#### 2.4 方法内联

支持内联小函数（< 50 字节）：

```zig
fn shouldInline(self: *const CodeGenX64, func: *const CompiledFunc) bool {
    const max_inline_size = 50;
    if (func.code.len > max_inline_size) {
        return false;
    }
    return true;
}
```

#### 2.5 支持的字节码指令

- `push_0`, `push_1`, `push_int` - 常量推入
- `push_local`, `store_local` - 局部变量访问
- `pop`, `dup` - 栈操作
- `add`, `sub`, `mul`, `div` - 算术运算
- `lt`, `le`, `gt`, `ge`, `eq`, `ne` - 比较运算
- `jz`, `jnz`, `jmp` - 跳转指令
- `call`, `ret`, `ret_nil`, `halt` - 控制流

### 3. 编译器集成 (`src/jit/compiler.zig`)

#### 3.1 多架构支持

```zig
pub const TargetArch = enum {
    x86_64,
    aarch64,
    
    pub fn current() TargetArch {
        return switch (builtin.cpu.arch) {
            .x86_64 => .x86_64,
            .aarch64 => .aarch64,
            else => .x86_64,
        };
    }
};
```

#### 3.2 架构选择

编译器根据目标架构自动选择代码生成器：

```zig
return switch (self.target_arch) {
    .x86_64 => try self.compileFuncX64(code_cache, func, tf, osr_ip),
    .aarch64 => try self.compileFunc(code_cache, func, tf, osr_ip),
};
```

### 4. 属性测试 (`src/jit/test_codegen_x64_properties.zig`)

#### 4.1 属性 9：JIT 编译语义保持

验证 JIT 编译后的代码执行结果与解释执行相同：

```zig
test "Property 9: JIT compilation semantic preservation" {
    // 生成随机函数
    // 解释执行
    // JIT 编译执行
    // 比较结果
}
```

#### 4.2 属性 11：方法内联语义保持

验证内联后的代码执行结果与未内联时相同：

```zig
test "Property 11: Method inlining semantic preservation" {
    // 创建可内联函数
    // 生成内联代码
    // 比较结果
}
```

### 5. 集成测试 (`src/jit/test_x64_integration.zig`)

完整的集成测试套件，验证：

1. **MOV 指令**：寄存器传输和立即数加载
2. **算术指令**：ADD, SUB, IMUL
3. **位移指令**：SHL, SHR（强度削减优化）
4. **比较指令**：CMP, SETcc
5. **跳转指令**：JMP, Jcc
6. **函数序言/尾声**：完整的函数框架
7. **内存操作**：加载、存储、LEA
8. **完整函数示例**：生成可执行的机器码

## 测试结果

所有 8 个集成测试通过：

```
1/8 test.Assembler: MOV instructions...OK
2/8 test.Assembler: arithmetic instructions...OK
3/8 test.Assembler: shift instructions (strength reduction)...OK
4/8 test.Assembler: comparison and conditional...OK
5/8 test.Assembler: jump instructions...OK
6/8 test.Assembler: function prologue and epilogue...OK
7/8 test.Assembler: memory operations...OK
8/8 test.Assembler: complete function example...OK
```

生成的机器码示例（简单加法函数）：
```
0000: 55 48 89 e5 48 89 f8 48 01 f0 5d c3
```

对应的汇编代码：
```asm
push rbp        ; 55
mov rbp, rsp    ; 48 89 e5
mov rax, rdi    ; 48 89 f8
add rax, rsi    ; 48 01 f0
pop rbp         ; 5d
ret             ; c3
```

## 性能优化

### 1. 强度削减优化

自动将乘法优化为移位：
- `x * 2` → `x << 1`
- `x * 4` → `x << 2`
- `x * 8` → `x << 3`
- `x * 16` → `x << 4`

### 2. 类型特化

根据运行时类型信息生成特化代码：
- 整数运算：直接使用机器指令
- 动态类型：调用运行时函数

### 3. 方法内联

内联小函数以减少调用开销：
- 阈值：50 字节
- 深度限制：≤ 3 层

## 符合规范

### 需求验证

- ✅ **需求 2.2**：实现 x86-64 指令编码器
- ✅ **需求 2.4**：实现类型特化代码生成和方法内联

### 设计验证

- ✅ 完整的函数序言和尾声生成
- ✅ 基本指令生成（算术、逻辑、控制流）
- ✅ 类型特化代码生成
- ✅ 强度削减优化
- ✅ 方法内联支持

### 内存安全

- ✅ 所有内存操作使用显式 Allocator
- ✅ 使用 defer 确保资源释放
- ✅ 边界检查（通过 Zig 的安全检查）
- ✅ 无悬垂指针（生命周期明确）

## 未来改进

1. **完整的 OSR 支持**：实现栈上替换
2. **寄存器分配器**：实现线性扫描寄存器分配
3. **更多优化**：
   - 常量传播
   - 死代码消除
   - 公共子表达式消除
4. **SIMD 支持**：利用 SSE/AVX 指令
5. **调试信息**：生成 DWARF 调试信息

## 参考资料

- [Intel® 64 and IA-32 Architectures Software Developer's Manual](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
- [System V Application Binary Interface AMD64 Architecture Processor Supplement](https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf)
- [x86-64 Instruction Encoding](https://wiki.osdev.org/X86-64_Instruction_Encoding)

## 作者

Kiro AI Assistant

## 版本

1.0 - 2026-01-18
