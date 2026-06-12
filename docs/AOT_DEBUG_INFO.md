# AOT 编译器调试信息支持

## 概述

Zig-PHP AOT 编译器支持生成完整的 DWARF 调试信息，使得编译后的原生可执行文件可以使用 gdb 和 lldb 等调试器进行调试。

## 功能特性

### 1. DWARF 格式支持

- **DWARF 版本**: 支持 DWARF 4 标准
- **调试 Section**: 生成所有必要的 DWARF section
  - `.debug_info`: 调试信息条目（DIE）
  - `.debug_abbrev`: 缩写表
  - `.debug_line`: 行号表
  - `.debug_str`: 字符串表
  - `.debug_aranges`: 地址范围表

### 2. 源代码映射

- **行号映射**: 将机器码地址映射到源代码行号
- **列号支持**: 精确到列的位置信息
- **文件信息**: 支持多文件编译的源文件追踪

### 3. 类型信息

- **基本类型**: int8/16/32/64, uint8/16/32/64, float32/64, bool, void
- **复合类型**: 指针类型、数组类型、结构体类型
- **类型缓存**: 自动去重相同的类型定义

### 4. 符号信息

- **函数信息**: 函数名称、地址范围、返回类型
- **参数信息**: 参数名称、类型、位置（寄存器或栈偏移）
- **局部变量**: 变量名称、类型、作用域、位置

### 5. 调用栈支持

- **帧信息**: 完整的调用帧信息
- **栈回溯**: 支持 gdb/lldb 的 backtrace 命令
- **变量查看**: 在调试器中查看局部变量和参数

## 使用方法

### 编译时启用调试信息

```bash
# 使用 --debug-info 标志启用调试信息生成
zig-php-aot --input test.php --output test --debug-info

# 或者使用 debug 优化级别（默认启用调试信息）
zig-php-aot --input test.php --output test --optimize debug
```

### 使用 GDB 调试

```bash
# 启动 gdb
gdb ./test

# 常用 gdb 命令
(gdb) break main              # 在 main 函数设置断点
(gdb) break test.php:10       # 在源文件第 10 行设置断点
(gdb) run                     # 运行程序
(gdb) step                    # 单步执行（进入函数）
(gdb) next                    # 单步执行（跳过函数）
(gdb) print x                 # 打印变量 x 的值
(gdb) backtrace               # 显示调用栈
(gdb) info locals             # 显示局部变量
(gdb) info args               # 显示函数参数
(gdb) list                    # 显示当前源代码
(gdb) continue                # 继续执行
```

### 使用 LLDB 调试

```bash
# 启动 lldb
lldb ./test

# 常用 lldb 命令
(lldb) breakpoint set --name main        # 在 main 函数设置断点
(lldb) breakpoint set --file test.php --line 10  # 在源文件第 10 行设置断点
(lldb) run                               # 运行程序
(lldb) step                              # 单步执行（进入函数）
(lldb) next                              # 单步执行（跳过函数）
(lldb) print x                           # 打印变量 x 的值
(lldb) bt                                # 显示调用栈
(lldb) frame variable                    # 显示局部变量
(lldb) source list                       # 显示当前源代码
(lldb) continue                          # 继续执行
```

## 实现细节

### DWARF 数据结构

#### 调试信息条目（DIE）

每个 DIE 包含：
- **标签（Tag）**: 标识 DIE 的类型（编译单元、函数、变量等）
- **属性（Attributes）**: 描述 DIE 的详细信息
- **子节点（Children）**: 嵌套的 DIE 结构

```zig
pub const DIE = struct {
    tag: DW_TAG,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(*DIE),
    parent: ?*DIE,
    offset: u32,
};
```

#### 字符串表

用于存储所有字符串（函数名、变量名、文件名等），自动去重：

```zig
pub const StringTable = struct {
    strings: std.StringHashMap(u32),
    buffer: std.ArrayList(u8),
    
    pub fn addString(self: *StringTable, str: []const u8) !u32;
};
```

#### 行号表

记录机器码地址到源代码行号的映射：

```zig
pub const LineEntry = struct {
    address: u64,
    file: u32,
    line: u32,
    column: u32,
    is_stmt: bool,
    basic_block: bool,
    end_sequence: bool,
};
```

### 调试信息生成流程

1. **初始化**: 创建 `DwarfDebugInfoBuilder`
2. **编译单元**: 调用 `createCompileUnit()` 创建根 DIE
3. **函数信息**: 为每个函数调用 `createFunction()`
4. **参数和变量**: 添加参数和局部变量信息
5. **行号映射**: 在代码生成时调用 `addLineMapping()`
6. **完成构建**: 调用 `finalize()` 生成 DWARF 数据
7. **写入文件**: 将 DWARF section 写入目标文件

### 代码示例

```zig
// 创建调试信息构建器
var builder = try DwarfDebugInfoBuilder.init(allocator);
defer builder.deinit();

// 创建编译单元
try builder.createCompileUnit("test.php", "/path/to/source");

// 创建函数调试信息
const func_die = try builder.createFunction("calculate", 0x1000, 0x1200, .float64);

// 添加函数参数
try builder.createFormalParameter(func_die, "a", .float64, 0);
try builder.createFormalParameter(func_die, "b", .float64, 8);

// 添加局部变量
try builder.createLocalVariable(func_die, "result", .float64, 16, 10);

// 添加行号映射
try builder.addLineMapping(0x1000, 0, 10, 1);
try builder.addLineMapping(0x1050, 0, 11, 1);
try builder.addLineMapping(0x1100, 0, 12, 1);

// 完成构建
var dwarf_data = try builder.finalize();
defer dwarf_data.deinit(allocator);

// 将 DWARF 数据写入目标文件
// ...
```

## 性能考虑

### 调试信息大小

- 调试信息会增加可执行文件的大小（通常增加 20-50%）
- 可以使用 `strip` 命令移除调试信息以减小文件大小
- Release 构建可以禁用调试信息以获得最小的二进制文件

### 编译时间

- 生成调试信息会增加编译时间（通常增加 10-20%）
- 对于大型项目，建议在开发时启用，发布时禁用

### 运行时性能

- 调试信息不影响运行时性能
- 调试信息存储在独立的 section 中，不会被加载到内存

## 限制和已知问题

### 当前限制

1. **优化代码调试**: 高优化级别可能导致调试信息不准确
2. **内联函数**: 内联函数的调试信息可能不完整
3. **宏展开**: 不支持宏展开的调试信息
4. **模板实例化**: 不支持模板实例化的调试信息

### 解决方案

- 使用 `--optimize debug` 进行调试
- 使用 `--optimize release-safe` 保留部分调试信息
- 使用 `--no-inline` 禁用函数内联

## 调试技巧

### 1. 设置条件断点

```bash
# GDB
(gdb) break test.php:10 if x > 100

# LLDB
(lldb) breakpoint set --file test.php --line 10 --condition 'x > 100'
```

### 2. 监视变量

```bash
# GDB
(gdb) watch x

# LLDB
(lldb) watchpoint set variable x
```

### 3. 查看汇编代码

```bash
# GDB
(gdb) disassemble

# LLDB
(lldb) disassemble
```

### 4. 查看内存

```bash
# GDB
(gdb) x/10x $rsp

# LLDB
(lldb) memory read --size 8 --format x --count 10 $rsp
```

## 参考资料

- [DWARF Debugging Standard](http://dwarfstd.org/)
- [GDB Documentation](https://sourceware.org/gdb/documentation/)
- [LLDB Tutorial](https://lldb.llvm.org/use/tutorial.html)
- [Debugging with GDB](https://sourceware.org/gdb/current/onlinedocs/gdb/)

## 相关文档

- [JIT 调试信息](JIT_DEBUG_INFO.md)
- [性能剖析](PERFORMANCE_PROFILING.md)
- [错误诊断](ERROR_DIAGNOSTICS.md)

---

**文档版本**: 1.0  
**最后更新**: 2026-01-20  
**作者**: Kiro AI Assistant
