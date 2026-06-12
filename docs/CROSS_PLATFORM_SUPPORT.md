# 跨平台支持实现文档

## 概述

本文档描述了 Zig-PHP AOT 编译器的跨平台代码生成支持。编译器能够为以下平台生成原生可执行文件：

- **Linux** (x86_64, aarch64)
- **macOS** (x86_64, aarch64/Apple Silicon)
- **Windows** (x86_64)

## 架构设计

### 1. 平台抽象层

跨平台支持通过 `src/aot/platform.zig` 模块实现，提供以下抽象：

```
┌─────────────────────────────────────┐
│      Platform Configuration         │
│  (Target Triple, ABI, Conventions)  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      Platform Code Generator        │
│  (Prologue, Epilogue, Syscalls)     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│         LLVM Code Generator          │
│    (IR → Native Machine Code)       │
└─────────────────────────────────────┘
```

### 2. 支持的平台配置

#### Linux

| 配置项 | x86_64 | aarch64 | x86_64-musl |
|--------|--------|---------|-------------|
| 目标三元组 | x86_64-unknown-linux-gnu | aarch64-unknown-linux-gnu | x86_64-unknown-linux-musl |
| 对象格式 | ELF | ELF | ELF |
| 调用约定 | System V | AAPCS64 | System V |
| 动态链接器 | /lib64/ld-linux-x86-64.so.2 | /lib/ld-linux-aarch64.so.1 | /lib/ld-musl-x86_64.so.1 |
| 必需库 | c, m, pthread, dl | c, m, pthread, dl | c |

#### macOS

| 配置项 | x86_64 | aarch64 (Apple Silicon) |
|--------|--------|-------------------------|
| 目标三元组 | x86_64-apple-darwin | aarch64-apple-darwin |
| 对象格式 | Mach-O | Mach-O |
| 调用约定 | System V | AAPCS64 |
| 动态链接器 | /usr/lib/dyld | /usr/lib/dyld |
| 必需库 | System | System |
| 最低版本 | macOS 10.15 | macOS 11.0 |

#### Windows

| 配置项 | x86_64 (MSVC) | x86_64 (GNU/MinGW) |
|--------|---------------|---------------------|
| 目标三元组 | x86_64-pc-windows-msvc | x86_64-w64-windows-gnu |
| 对象格式 | PE/COFF | PE/COFF |
| 调用约定 | Win64 | Win64 |
| 必需库 | kernel32, user32, msvcrt, ucrt | kernel32, msvcrt, mingw32, gcc |

## 核心组件

### 1. PlatformConfig

平台配置结构体，包含所有平台特定的信息：

```zig
pub const PlatformConfig = struct {
    name: []const u8,                    // 平台名称
    triple: []const u8,                  // 目标三元组
    object_format: ObjectFormat,         // 对象文件格式
    calling_convention: CallingConvention, // 调用约定
    syscall_convention: SyscallConvention, // 系统调用约定
    dynamic_linker: ?[]const u8,         // 动态链接器路径
    system_lib_paths: []const []const u8, // 系统库路径
    required_libs: []const []const u8,   // 必需的系统库
    compile_flags: []const []const u8,   // 编译标志
    link_flags: []const []const u8,      // 链接标志
};
```

### 2. PlatformSelector

平台选择器，根据目标三元组选择合适的平台配置：

```zig
pub const PlatformSelector = struct {
    /// 根据目标三元组选择平台配置
    pub fn selectByTriple(triple: []const u8) !*const PlatformConfig;
    
    /// 获取当前主机平台配置
    pub fn getNativePlatform() *const PlatformConfig;
    
    /// 列出所有支持的平台
    pub fn getAllSupportedPlatforms() []const *const PlatformConfig;
};
```

### 3. PlatformCodeGen

平台代码生成器，生成平台特定的汇编代码：

```zig
pub const PlatformCodeGen = struct {
    /// 生成函数序言
    pub fn generateFunctionPrologue(
        self: *const PlatformCodeGen,
        allocator: Allocator,
        stack_size: usize,
    ) ![]const u8;
    
    /// 生成函数尾声
    pub fn generateFunctionEpilogue(
        self: *const PlatformCodeGen,
        allocator: Allocator,
    ) ![]const u8;
    
    /// 生成系统调用
    pub fn generateSyscall(
        self: *const PlatformCodeGen,
        allocator: Allocator,
        syscall_number: u32,
        args: []const []const u8,
    ) ![]const u8;
    
    /// 获取栈对齐要求
    pub fn getStackAlignment(self: *const PlatformCodeGen) usize;
    
    /// 获取指针大小
    pub fn getPointerSize(self: *const PlatformCodeGen) usize;
};
```

## 使用示例

### 1. 为特定平台编译

```zig
const std = @import("std");
const CodeGenerator = @import("aot/codegen.zig").CodeGenerator;
const Target = @import("aot/codegen.zig").Target;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建 Linux x86_64 目标
    const target = Target{
        .arch = .x86_64,
        .os = .linux,
        .abi = .gnu,
    };
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    // 初始化代码生成器
    const codegen = try CodeGenerator.init(
        allocator,
        target,
        .release_fast,
        false,
        &diagnostics,
    );
    defer codegen.deinit();
    
    // 生成代码
    try codegen.generateModule(ir_module);
    
    // 生成对象文件
    try codegen.generateObjectFileForPlatform("output.o");
    
    // 获取链接器命令
    const object_files = [_][]const u8{"output.o"};
    const link_cmd = try codegen.getPlatformLinkerCommand(
        allocator,
        &object_files,
        "output",
    );
    defer allocator.free(link_cmd);
    
    std.debug.print("Link command: {s}\n", .{link_cmd});
}
```

### 2. 交叉编译到多个平台

```zig
pub fn crossCompile(
    allocator: Allocator,
    ir_module: *const IR.Module,
    output_dir: []const u8,
) !void {
    // 获取所有支持的平台
    const platforms = PlatformSelector.getAllSupportedPlatforms();
    
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    // 为每个平台生成代码
    for (platforms) |platform| {
        std.debug.print("Compiling for {s}...\n", .{platform.name});
        
        // 从平台配置创建目标
        const target = try Target.fromString(platform.triple);
        
        const codegen = try CodeGenerator.init(
            allocator,
            target,
            .release_fast,
            false,
            &diagnostics,
        );
        defer codegen.deinit();
        
        // 生成代码
        try codegen.generateModule(ir_module);
        
        // 生成对象文件
        const output_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}.o",
            .{ output_dir, platform.name }
        );
        defer allocator.free(output_path);
        
        try codegen.generateObjectFileForPlatform(output_path);
    }
}
```

### 3. 获取平台信息

```zig
pub fn printPlatformInfo(codegen: *const CodeGenerator) !void {
    const allocator = std.heap.page_allocator;
    
    const summary = try codegen.getPlatformSummary(allocator);
    defer allocator.free(summary);
    
    std.debug.print("{s}\n", .{summary});
}
```

## 平台特定的实现细节

### 1. 函数调用约定

#### System V (Linux, macOS x86_64)

- 参数传递：RDI, RSI, RDX, RCX, R8, R9（前 6 个整数参数）
- 返回值：RAX（整数），XMM0（浮点）
- 调用者保存：RAX, RCX, RDX, RSI, RDI, R8-R11
- 被调用者保存：RBX, RBP, R12-R15
- 栈对齐：16 字节

#### Win64 (Windows)

- 参数传递：RCX, RDX, R8, R9（前 4 个整数参数）
- 返回值：RAX（整数），XMM0（浮点）
- 调用者保存：RAX, RCX, RDX, R8-R11
- 被调用者保存：RBX, RBP, RDI, RSI, R12-R15
- 栈对齐：16 字节
- Shadow space：32 字节（为前 4 个参数预留）

#### AAPCS64 (ARM64)

- 参数传递：X0-X7（整数），V0-V7（浮点）
- 返回值：X0（整数），V0（浮点）
- 调用者保存：X0-X18
- 被调用者保存：X19-X29
- 栈对齐：16 字节

### 2. 系统调用约定

#### Linux

```zig
// 系统调用号在 RAX
// 参数在 RDI, RSI, RDX, R10, R8, R9
// 使用 syscall 指令
mov rax, 1      // sys_write
mov rdi, 1      // stdout
mov rsi, msg    // buffer
mov rdx, len    // length
syscall
```

#### macOS

```zig
// 系统调用号在 RAX（加上 0x2000000 偏移）
// 参数在 RDI, RSI, RDX, R10, R8, R9
// 使用 syscall 指令
mov rax, 0x2000004  // sys_write (4 + 0x2000000)
mov rdi, 1          // stdout
mov rsi, msg        // buffer
mov rdx, len        // length
syscall
```

#### Windows

```zig
// Windows 不直接暴露系统调用
// 需要通过 ntdll.dll 的 NtXxx 函数
// 或使用 kernel32.dll 的 Win32 API
```

### 3. 对象文件格式

#### ELF (Linux)

- 节（Section）：.text, .data, .bss, .rodata
- 符号表：.symtab, .strtab
- 重定位：.rel.text, .rela.text
- 动态链接：.dynamic, .dynsym, .dynstr

#### Mach-O (macOS)

- 段（Segment）：__TEXT, __DATA, __LINKEDIT
- 节（Section）：__text, __data, __bss, __const
- 符号表：LC_SYMTAB
- 动态链接：LC_DYLD_INFO, LC_LOAD_DYLIB

#### PE/COFF (Windows)

- 节（Section）：.text, .data, .rdata, .bss
- 符号表：COFF Symbol Table
- 导入表：Import Directory Table
- 导出表：Export Directory Table

## 链接过程

### Linux

```bash
# 编译对象文件
zig build-obj -target x86_64-linux-gnu main.zig

# 链接可执行文件
ld -o output \
   -dynamic-linker /lib64/ld-linux-x86-64.so.2 \
   -L/lib/x86_64-linux-gnu \
   -L/usr/lib/x86_64-linux-gnu \
   main.o \
   -lc -lm -lpthread -ldl \
   -z relro -z now -z noexecstack
```

### macOS

```bash
# 编译对象文件
zig build-obj -target x86_64-macos main.zig

# 链接可执行文件
ld -o output \
   -macosx_version_min 10.15 \
   -platform_version macos 10.15 10.15 \
   -L/usr/lib \
   main.o \
   -lSystem
```

### Windows (MSVC)

```cmd
REM 编译对象文件
zig build-obj -target x86_64-windows-msvc main.zig

REM 链接可执行文件
link.exe /OUT:output.exe ^
   /SUBSYSTEM:CONSOLE ^
   /DYNAMICBASE /NXCOMPAT ^
   main.obj ^
   kernel32.lib user32.lib msvcrt.lib ucrt.lib
```

### Windows (MinGW)

```bash
# 编译对象文件
zig build-obj -target x86_64-windows-gnu main.zig

# 链接可执行文件
ld -o output.exe \
   -L/mingw64/lib \
   main.o \
   -lkernel32 -lmsvcrt -lmingw32 -lgcc -lmoldname -lmingwex \
   -Wl,--dynamicbase -Wl,--nxcompat -Wl,--high-entropy-va
```

## 测试

### 单元测试

```bash
# 运行平台模块测试
zig test src/aot/platform.zig

# 运行代码生成器测试
zig test src/aot/codegen.zig
```

### 集成测试

```bash
# 测试 Linux 编译
zig build test-linux

# 测试 macOS 编译
zig build test-macos

# 测试 Windows 编译
zig build test-windows

# 测试所有平台
zig build test-all-platforms
```

## 性能考虑

### 1. 编译时优化

- 平台配置为编译时常量，无运行时开销
- 平台选择通过编译时已知的目标三元组进行
- 无动态分配的平台配置数据

### 2. 代码生成优化

- 使用平台特定的指令集（SSE, AVX, NEON）
- 利用平台特定的调用约定减少参数传递开销
- 针对平台特定的缓存行大小优化数据布局

### 3. 链接时优化（LTO）

- 跨模块内联
- 死代码消除
- 常量传播

## 安全性

### 1. 内存安全

- 所有平台配置为静态常量，无悬垂指针风险
- 平台代码生成器不持有可变状态
- 使用 Zig 的编译时安全检查

### 2. 平台特定的安全特性

#### Linux

- ASLR（地址空间布局随机化）
- DEP（数据执行保护）：`-z noexecstack`
- RELRO（重定位只读）：`-z relro -z now`
- Stack Canary：`-fstack-protector-strong`

#### macOS

- ASLR（默认启用）
- DEP（默认启用）
- Code Signing（需要开发者证书）
- Hardened Runtime

#### Windows

- ASLR：`/DYNAMICBASE`
- DEP：`/NXCOMPAT`
- Control Flow Guard：`/GUARD:CF`
- High Entropy ASLR：`/HIGHENTROPYVA`

## 故障排除

### 常见问题

#### 1. 链接器找不到系统库

**问题**：`ld: library not found for -lc`

**解决方案**：
- 检查系统库路径配置
- 确保安装了必要的开发工具包
- Linux: `sudo apt-get install build-essential`
- macOS: `xcode-select --install`
- Windows: 安装 Visual Studio 或 MinGW

#### 2. 目标三元组不支持

**问题**：`error: UnsupportedPlatform`

**解决方案**：
- 检查目标三元组格式是否正确
- 使用 `PlatformSelector.getAllSupportedPlatforms()` 查看支持的平台
- 确保目标架构和操作系统组合有效

#### 3. 调用约定不匹配

**问题**：程序崩溃或参数传递错误

**解决方案**：
- 确保所有函数使用正确的调用约定
- 检查外部函数声明是否正确
- 使用平台特定的函数属性标注

## 未来扩展

### 计划支持的平台

- **FreeBSD** (x86_64, aarch64)
- **OpenBSD** (x86_64)
- **Android** (aarch64, x86_64)
- **iOS** (aarch64)
- **WebAssembly** (wasm32, wasm64)

### 计划支持的架构

- **RISC-V** (rv64gc)
- **PowerPC** (ppc64le)
- **MIPS** (mips64)

## 参考资料

### 规范文档

- [System V ABI](https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf)
- [Windows x64 Calling Convention](https://docs.microsoft.com/en-us/cpp/build/x64-calling-convention)
- [ARM64 AAPCS](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst)
- [ELF Specification](https://refspecs.linuxfoundation.org/elf/elf.pdf)
- [Mach-O File Format](https://github.com/aidansteele/osx-abi-macho-file-format-reference)
- [PE/COFF Specification](https://docs.microsoft.com/en-us/windows/win32/debug/pe-format)

### 工具文档

- [LLVM Target Triple](https://llvm.org/docs/LangRef.html#target-triple)
- [Zig Build System](https://ziglang.org/documentation/master/#Build-System)
- [GNU Binutils](https://sourceware.org/binutils/docs/)

## 贡献指南

### 添加新平台支持

1. 在 `src/aot/platform.zig` 中添加平台配置常量
2. 更新 `PlatformSelector.selectByTriple()` 以识别新平台
3. 实现平台特定的代码生成逻辑
4. 添加单元测试和集成测试
5. 更新文档

### 代码审查清单

- [ ] 平台配置完整且正确
- [ ] 调用约定实现正确
- [ ] 系统调用约定正确
- [ ] 对象文件格式正确
- [ ] 链接器命令正确
- [ ] 安全特性已启用
- [ ] 测试覆盖充分
- [ ] 文档已更新

---

**版本**: 1.0  
**最后更新**: 2026-01-18  
**作者**: Kiro AI Assistant
