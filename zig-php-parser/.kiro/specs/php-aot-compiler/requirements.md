# Requirements Document

## Introduction

本文档定义了为 Zig PHP 解释器添加 AOT (Ahead-of-Time) 编译功能的需求规范。该功能将允许用户将 PHP 源代码直接编译为独立的原生二进制可执行文件，无需 PHP 运行时依赖。

## Glossary

- **AOT_Compiler**: 提前编译器，将 PHP 源代码在运行前编译为原生机器码的组件
- **IR**: 中间表示 (Intermediate Representation)，介于 AST 和目标代码之间的代码表示形式
- **Code_Generator**: 代码生成器，将 IR 转换为目标平台机器码的组件
- **Runtime_Library**: 运行时库，提供 PHP 内置函数和类型系统支持的静态链接库
- **Static_Linker**: 静态链接器，将生成的目标代码与运行时库链接为最终可执行文件
- **Type_Inferencer**: 类型推断器，在编译时分析和推断 PHP 变量类型的组件
- **Symbol_Table**: 符号表，存储编译期间所有标识符信息的数据结构
- **Target_Triple**: 目标三元组，描述目标平台的架构、操作系统和 ABI 的标识符

## Requirements

### Requirement 1: 命令行接口扩展

**User Story:** 作为开发者，我希望通过命令行参数指定编译模式，以便将 PHP 代码编译为可执行文件。

#### Acceptance Criteria

1. WHEN 用户执行 `zig-php --compile <file.php>` THEN THE AOT_Compiler SHALL 将 PHP 文件编译为与当前平台匹配的可执行文件
2. WHEN 用户执行 `zig-php --compile --output=<name> <file.php>` THEN THE AOT_Compiler SHALL 将输出文件命名为指定名称
3. WHEN 用户执行 `zig-php --compile --target=<triple> <file.php>` THEN THE AOT_Compiler SHALL 为指定目标平台生成可执行文件
4. WHEN 用户执行 `zig-php --compile --optimize=<level> <file.php>` THEN THE AOT_Compiler SHALL 应用指定级别的优化 (debug, release-safe, release-fast, release-small)
5. WHEN 用户执行 `zig-php --compile --static <file.php>` THEN THE AOT_Compiler SHALL 生成完全静态链接的可执行文件
6. IF 编译过程中发生错误 THEN THE AOT_Compiler SHALL 输出详细的错误信息并返回非零退出码

### Requirement 2: 中间表示 (IR) 生成

**User Story:** 作为编译器开发者，我希望有一个清晰的中间表示层，以便在 AST 和机器码之间进行优化和转换。

#### Acceptance Criteria

1. WHEN Parser 生成 AST THEN THE IR_Generator SHALL 将 AST 转换为三地址码形式的 IR
2. THE IR SHALL 支持以下操作类型：算术运算、比较运算、控制流、函数调用、内存操作、类型转换
3. WHEN IR 包含 PHP 动态类型操作 THEN THE IR SHALL 使用带标签的联合类型表示值
4. THE IR SHALL 保留源代码位置信息以支持调试和错误报告
5. WHEN 生成 IR THEN THE IR_Generator SHALL 执行基本的常量折叠优化
6. THE IR SHALL 支持 SSA (Static Single Assignment) 形式以便后续优化

### Requirement 3: 类型推断系统

**User Story:** 作为编译器，我希望能够推断 PHP 变量的类型，以便生成更高效的机器码。

#### Acceptance Criteria

1. WHEN 变量被赋予字面量值 THEN THE Type_Inferencer SHALL 推断出精确类型
2. WHEN 函数参数有类型声明 THEN THE Type_Inferencer SHALL 使用声明的类型
3. WHEN 函数有返回类型声明 THEN THE Type_Inferencer SHALL 使用声明的返回类型
4. WHEN 变量类型无法静态确定 THEN THE Type_Inferencer SHALL 标记为动态类型并生成运行时类型检查代码
5. THE Type_Inferencer SHALL 支持 PHP 8.x 的联合类型和交叉类型
6. WHEN 类型推断完成 THEN THE Type_Inferencer SHALL 生成类型注解的 IR

### Requirement 4: 代码生成

**User Story:** 作为编译器，我希望能够将 IR 转换为目标平台的机器码。

#### Acceptance Criteria

1. THE Code_Generator SHALL 使用 Zig 的内置 LLVM 后端生成机器码
2. WHEN 生成代码 THEN THE Code_Generator SHALL 支持 x86_64、aarch64、arm 架构
3. WHEN 生成代码 THEN THE Code_Generator SHALL 支持 Linux、macOS、Windows 操作系统
4. THE Code_Generator SHALL 为每个 PHP 函数生成对应的原生函数
5. WHEN 遇到动态类型操作 THEN THE Code_Generator SHALL 生成运行时类型检查和分发代码
6. THE Code_Generator SHALL 生成符合目标平台 ABI 的调用约定

### Requirement 5: 运行时库

**User Story:** 作为开发者，我希望编译后的程序能够使用 PHP 的内置函数和类型系统。

#### Acceptance Criteria

1. THE Runtime_Library SHALL 提供所有 PHP 内置函数的原生实现
2. THE Runtime_Library SHALL 提供 PHP 动态类型系统的支持 (Value 类型、类型转换、类型检查)
3. THE Runtime_Library SHALL 提供垃圾回收支持
4. THE Runtime_Library SHALL 提供异常处理机制
5. THE Runtime_Library SHALL 支持静态链接到最终可执行文件
6. WHEN 编译时 THEN THE Static_Linker SHALL 只链接实际使用的运行时函数 (死代码消除)

### Requirement 6: PHP 语言特性支持

**User Story:** 作为开发者，我希望编译后的程序能够支持主要的 PHP 语言特性。

#### Acceptance Criteria

1. THE AOT_Compiler SHALL 支持编译 PHP 函数定义和调用
2. THE AOT_Compiler SHALL 支持编译 PHP 类、接口、trait
3. THE AOT_Compiler SHALL 支持编译 PHP 控制流语句 (if, while, for, foreach, switch, match)
4. THE AOT_Compiler SHALL 支持编译 PHP 异常处理 (try-catch-finally)
5. THE AOT_Compiler SHALL 支持编译 PHP 闭包和箭头函数
6. THE AOT_Compiler SHALL 支持编译 PHP 数组操作
7. THE AOT_Compiler SHALL 支持编译 PHP 字符串操作和插值
8. IF PHP 代码使用 eval() 或动态特性 THEN THE AOT_Compiler SHALL 报告警告并生成解释执行的回退代码

### Requirement 7: 错误处理和诊断

**User Story:** 作为开发者，我希望在编译失败时获得清晰的错误信息。

#### Acceptance Criteria

1. WHEN 语法错误发生 THEN THE AOT_Compiler SHALL 报告错误位置和建议修复
2. WHEN 类型错误发生 THEN THE AOT_Compiler SHALL 报告类型不匹配的详细信息
3. WHEN 未定义的函数或类被引用 THEN THE AOT_Compiler SHALL 报告未解析的符号
4. THE AOT_Compiler SHALL 支持 `--verbose` 选项输出详细的编译过程信息
5. THE AOT_Compiler SHALL 支持 `--dump-ir` 选项输出生成的 IR 用于调试
6. THE AOT_Compiler SHALL 支持 `--dump-ast` 选项输出解析的 AST 用于调试

### Requirement 8: 性能和优化

**User Story:** 作为开发者，我希望编译后的程序具有良好的性能。

#### Acceptance Criteria

1. THE AOT_Compiler SHALL 执行常量折叠优化
2. THE AOT_Compiler SHALL 执行死代码消除优化
3. THE AOT_Compiler SHALL 执行函数内联优化 (对于小函数)
4. THE AOT_Compiler SHALL 利用类型推断结果生成特化代码
5. WHEN 优化级别为 release-small THEN THE AOT_Compiler SHALL 优先减小二进制体积
6. WHEN 优化级别为 release-fast THEN THE AOT_Compiler SHALL 优先提升执行速度

### Requirement 9: 跨平台支持

**User Story:** 作为开发者，我希望能够为不同平台交叉编译 PHP 程序。

#### Acceptance Criteria

1. THE AOT_Compiler SHALL 支持从任意主机平台交叉编译到支持的目标平台
2. WHEN 交叉编译时 THEN THE AOT_Compiler SHALL 使用目标平台的运行时库
3. THE AOT_Compiler SHALL 生成的可执行文件无需任何外部依赖 (完全静态链接)
4. THE AOT_Compiler SHALL 支持通过 `--list-targets` 列出所有支持的目标平台

### Requirement 10: 多文件项目支持

**User Story:** 作为开发者，我希望能够编译包含多个文件的 PHP 项目。

#### Acceptance Criteria

1. WHEN PHP 代码使用 include/require THEN THE AOT_Compiler SHALL 解析并编译被包含的文件
2. THE AOT_Compiler SHALL 支持通过配置文件指定项目入口点和包含路径
3. THE AOT_Compiler SHALL 检测并报告循环依赖
4. THE AOT_Compiler SHALL 支持增量编译 (只重新编译修改的文件)
5. WHEN 编译多文件项目 THEN THE AOT_Compiler SHALL 生成单一可执行文件

### Requirement 11: 调试支持

**User Story:** 作为开发者，我希望能够调试编译后的程序。

#### Acceptance Criteria

1. WHEN 优化级别为 debug THEN THE AOT_Compiler SHALL 生成 DWARF 调试信息
2. THE AOT_Compiler SHALL 在调试信息中保留 PHP 源代码行号映射
3. THE AOT_Compiler SHALL 支持生成源代码映射文件
4. WHEN 运行时错误发生 THEN THE Runtime_Library SHALL 输出包含 PHP 源代码位置的堆栈跟踪

### Requirement 12: 安全性

**User Story:** 作为开发者，我希望编译后的程序是安全的。

#### Acceptance Criteria

1. THE AOT_Compiler SHALL 对所有数组访问生成边界检查代码
2. THE AOT_Compiler SHALL 对所有指针操作生成空指针检查代码
3. THE Runtime_Library SHALL 使用安全的内存分配和释放机制
4. THE AOT_Compiler SHALL 不执行任何可能导致未定义行为的优化
5. WHEN 检测到潜在的安全问题 THEN THE AOT_Compiler SHALL 发出警告
