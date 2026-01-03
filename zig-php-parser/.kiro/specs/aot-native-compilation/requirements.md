# 需求文档：AOT 原生编译功能

## 简介

本功能旨在实现完整的 AOT（Ahead-of-Time）编译管道，将 PHP 源代码编译为可直接运行的原生二进制可执行文件。当前项目已有 AOT 编译器的框架代码，但 LLVM 代码生成和链接功能尚未实现。本需求将完成整个编译管道，使用户能够通过 `--compile` 选项生成真正可执行的二进制文件。

## 术语表

- **AOT_Compiler**: 提前编译器，将 PHP 源码转换为原生机器码的编译器
- **IR**: 中间表示（Intermediate Representation），编译器内部使用的代码表示形式
- **LLVM**: 底层虚拟机，用于生成优化的机器码的编译器基础设施
- **Runtime_Library**: 运行时库，提供 PHP 值类型、垃圾回收、内置函数等运行时支持
- **Linker**: 链接器，将目标文件和运行时库链接为最终可执行文件
- **CodeGenerator**: 代码生成器，将 IR 转换为 LLVM IR 并生成机器码
- **PHPValue**: PHP 动态值类型，支持 null、bool、int、float、string、array、object 等类型

## 需求

### 需求 1：Zig 原生代码生成

**用户故事：** 作为开发者，我希望 AOT 编译器能够生成原生机器码，以便我的 PHP 程序可以直接运行而无需解释器。

#### 验收标准

1. WHEN 用户执行 `--compile` 命令 THEN AOT_Compiler SHALL 生成目标平台的原生目标文件（.o 或 .obj）
2. WHEN 编译简单的 PHP 程序（如 `echo "Hello";`）THEN CodeGenerator SHALL 生成正确的机器码指令
3. WHEN 编译包含算术运算的 PHP 程序 THEN CodeGenerator SHALL 生成对应的 CPU 算术指令
4. WHEN 编译包含控制流（if/while/for）的 PHP 程序 THEN CodeGenerator SHALL 生成正确的分支和跳转指令
5. WHEN 编译包含函数调用的 PHP 程序 THEN CodeGenerator SHALL 生成正确的调用约定代码
6. THE CodeGenerator SHALL 支持 x86_64、aarch64 目标架构
7. THE CodeGenerator SHALL 支持 Linux、macOS、Windows 目标操作系统

### 需求 2：运行时库编译

**用户故事：** 作为开发者，我希望运行时库能够被编译为静态库，以便链接到最终的可执行文件中。

#### 验收标准

1. WHEN AOT 编译开始 THEN Runtime_Library SHALL 被编译为目标平台的静态库（.a 或 .lib）
2. THE Runtime_Library SHALL 提供 PHPValue 类型的创建、转换和销毁函数
3. THE Runtime_Library SHALL 提供引用计数垃圾回收功能
4. THE Runtime_Library SHALL 提供数组操作函数（创建、获取、设置、遍历）
5. THE Runtime_Library SHALL 提供字符串操作函数（连接、长度、子串）
6. THE Runtime_Library SHALL 提供 I/O 函数（echo、print）
7. THE Runtime_Library SHALL 提供内置函数（strlen、count、var_dump、gettype 等）
8. WHEN 运行时库函数被调用 THEN Runtime_Library SHALL 正确处理 PHP 类型转换规则

### 需求 3：静态链接

**用户故事：** 作为开发者，我希望编译后的程序能够静态链接所有依赖，以便生成独立的可执行文件。

#### 验收标准

1. WHEN 编译完成 THEN Linker SHALL 将目标文件与运行时库链接为可执行文件
2. WHEN 使用 `--static` 选项 THEN Linker SHALL 生成完全静态链接的可执行文件
3. WHEN 链接 Linux 目标 THEN Linker SHALL 使用 ld 或 gcc 进行链接
4. WHEN 链接 macOS 目标 THEN Linker SHALL 使用 ld 并设置正确的 SDK 路径
5. WHEN 链接 Windows 目标 THEN Linker SHALL 使用 lld-link 进行链接
6. THE Linker SHALL 支持死代码消除以减小可执行文件大小
7. IF 链接失败 THEN Linker SHALL 返回描述性错误信息

### 需求 4：完整编译管道集成

**用户故事：** 作为开发者，我希望通过单个命令完成从 PHP 源码到可执行文件的整个编译过程。

#### 验收标准

1. WHEN 用户执行 `zig-php --compile hello.php` THEN AOT_Compiler SHALL 生成名为 `hello` 的可执行文件
2. WHEN 用户指定 `--output=app` THEN AOT_Compiler SHALL 生成名为 `app` 的可执行文件
3. WHEN 编译成功 THEN 生成的可执行文件 SHALL 能够直接运行并产生正确输出
4. WHEN 编译失败 THEN AOT_Compiler SHALL 显示清晰的错误信息和源码位置
5. THE AOT_Compiler SHALL 支持 `--verbose` 选项显示编译过程详情
6. THE AOT_Compiler SHALL 支持 `--dump-ir` 选项输出中间表示
7. THE AOT_Compiler SHALL 支持 `--dump-ast` 选项输出语法树

### 需求 5：优化级别支持

**用户故事：** 作为开发者，我希望能够选择不同的优化级别，以便在调试便利性和运行性能之间取得平衡。

#### 验收标准

1. WHEN 使用 `--optimize=debug` THEN AOT_Compiler SHALL 生成未优化的代码并包含完整调试信息
2. WHEN 使用 `--optimize=release-safe` THEN AOT_Compiler SHALL 生成优化代码并保留安全检查
3. WHEN 使用 `--optimize=release-fast` THEN AOT_Compiler SHALL 生成最大性能优化的代码
4. WHEN 使用 `--optimize=release-small` THEN AOT_Compiler SHALL 生成最小体积的代码
5. THE IR_Optimizer SHALL 执行常量折叠优化
6. THE IR_Optimizer SHALL 执行死代码消除优化
7. THE IR_Optimizer SHALL 执行公共子表达式消除优化

### 需求 6：跨平台编译支持

**用户故事：** 作为开发者，我希望能够为不同的目标平台编译程序，以便在一台机器上生成多平台的可执行文件。

#### 验收标准

1. WHEN 使用 `--target=x86_64-linux-gnu` THEN AOT_Compiler SHALL 生成 Linux x86_64 可执行文件
2. WHEN 使用 `--target=aarch64-macos-none` THEN AOT_Compiler SHALL 生成 macOS ARM64 可执行文件
3. WHEN 使用 `--target=x86_64-windows-msvc` THEN AOT_Compiler SHALL 生成 Windows x64 可执行文件
4. WHEN 使用 `--list-targets` THEN AOT_Compiler SHALL 显示所有支持的目标平台
5. IF 目标平台不支持 THEN AOT_Compiler SHALL 返回清晰的错误信息

### 需求 7：PHP 语言特性支持

**用户故事：** 作为开发者，我希望 AOT 编译器支持常用的 PHP 语言特性，以便我的程序能够正确编译和运行。

#### 验收标准

1. THE AOT_Compiler SHALL 支持基本数据类型（null、bool、int、float、string）
2. THE AOT_Compiler SHALL 支持数组类型（索引数组和关联数组）
3. THE AOT_Compiler SHALL 支持算术运算符（+、-、*、/、%、**）
4. THE AOT_Compiler SHALL 支持比较运算符（==、===、!=、!==、<、>、<=、>=、<=>）
5. THE AOT_Compiler SHALL 支持逻辑运算符（&&、||、!、and、or）
6. THE AOT_Compiler SHALL 支持控制结构（if/else、while、for、foreach）
7. THE AOT_Compiler SHALL 支持函数定义和调用
8. THE AOT_Compiler SHALL 支持 echo 和 print 语句
9. THE AOT_Compiler SHALL 支持字符串连接运算符（.）
10. THE AOT_Compiler SHALL 支持数组访问和修改操作

### 需求 8：错误处理和诊断

**用户故事：** 作为开发者，我希望编译器能够提供清晰的错误信息，以便我能够快速定位和修复问题。

#### 验收标准

1. WHEN 源码包含语法错误 THEN AOT_Compiler SHALL 显示错误位置（文件、行、列）和描述
2. WHEN 源码包含类型错误 THEN AOT_Compiler SHALL 显示类型不匹配的详细信息
3. WHEN 链接失败 THEN AOT_Compiler SHALL 显示缺失的符号或库信息
4. WHEN 目标文件生成失败 THEN AOT_Compiler SHALL 显示具体的失败原因
5. THE AOT_Compiler SHALL 支持警告信息的显示
6. THE AOT_Compiler SHALL 在 `--verbose` 模式下显示编译各阶段的进度

### 需求 9：构建系统集成

**用户故事：** 作为开发者，我希望 AOT 编译功能能够通过 Zig 构建系统正确配置和构建。

#### 验收标准

1. THE build.zig SHALL 包含编译运行时库为静态库的构建步骤
2. THE build.zig SHALL 支持为不同目标平台构建运行时库
3. WHEN 执行 `zig build` THEN 构建系统 SHALL 生成 php-interpreter 可执行文件
4. WHEN 执行 `zig build runtime` THEN 构建系统 SHALL 生成运行时静态库
5. THE 构建系统 SHALL 支持 Release 和 Debug 构建模式
