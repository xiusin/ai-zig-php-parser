# zig-php 项目上下文

## 项目概述

**zig-php** 是一个用 Zig 语言实现的 PHP 8.5 兼容解释器，具有以下核心特性：

- **完整的 PHP 8.5 语法支持** - 包括类、接口、trait、闭包、箭头函数、管道操作符、属性系统等现代 PHP 特性
- **AOT 编译** - 可将 PHP 代码编译为原生可执行文件，支持交叉编译到多个平台
- **多语法模式** - 支持 PHP 风格和 Go 风格语法，通过命令行参数、文件指令或配置文件切换
- **扩展系统** - 支持动态加载 Zig 编写的第三方扩展，提供完整的 API
- **高性能运行时** - 包含树遍历解释器和字节码虚拟机两种执行模式
- **自动垃圾回收** - 引用计数和循环检测的混合 GC 策略
- **反射系统** - 完整的运行时内省能力
- **标准库** - 实现了 PHP 的核心内置函数（数组、字符串、数学、日期时间、JSON 等）

## 项目结构

```
├── src/
│   ├── compiler/          # 词法分析器、解析器、AST 生成
│   │   ├── lexer.zig      # 词法分析器，支持多语法模式
│   │   ├── parser.zig     # 语法分析器，构建 AST
│   │   ├── ast.zig        # AST 节点定义
│   │   ├── token.zig      # Token 类型定义
│   │   └── syntax_mode.zig # 语法模式配置
│   ├── runtime/           # 虚拟机、类型系统、GC、标准库
│   │   ├── vm.zig         # 虚拟机（树遍历和字节码）
│   │   ├── types.zig      # 类型系统
│   │   ├── gc.zig         # 垃圾回收器
│   │   ├── stdlib.zig     # 标准库
│   │   ├── reflection.zig # 反射系统
│   │   └── environment.zig # 环境和作用域管理
│   ├── aot/               # AOT 编译器模块（34个文件）
│   │   ├── compiler.zig   # AOT 编译器主入口
│   │   ├── type_inference.zig # 静态类型推断
│   │   ├── ir_generator.zig # SSA IR 生成
│   │   ├── ir.zig         # IR 定义
│   │   ├── optimizer.zig  # IR 优化器
│   │   ├── codegen.zig    # LLVM 代码生成
│   │   ├── linker.zig     # 静态链接器
│   │   ├── runtime_lib.zig # 原生运行时库
│   │   ├── diagnostics.zig # 错误诊断
│   │   ├── symbol_table.zig # 符号表
│   │   ├── dependency_resolver.zig # 依赖解析
│   │   ├── multi_file_compiler.zig # 多文件编译
│   │   └── root.zig       # AOT 模块根
│   ├── bytecode/          # 字节码虚拟机
│   ├── extension/         # 扩展系统 API 和注册表
│   │   ├── api.zig        # 扩展 API 定义
│   │   └── registry.zig   # 扩展注册表
│   ├── config/            # 配置文件加载器
│   │   └── loader.zig     # 配置加载器
│   ├── test_*.zig        # 各种测试文件（20+个）
│   ├── builtins.zig      # 内置函数定义
│   ├── reflection.zig    # 反射系统
│   └── main.zig          # 程序入口点
├── examples/             # PHP 示例脚本（100+个）
│   ├── extensions/       # 扩展示例
│   ├── go_syntax_demo.php # Go 语法模式演示
│   ├── hello.php         # Hello World 示例
│   └── ...
├── docs/                 # 项目文档
│   ├── ARCHITECTURE.md   # 架构文档
│   ├── USER_GUIDE.md     # 用户指南（中文）
│   ├── TECHNICAL_REFERENCE.md # 技术参考
│   ├── EXTENSION_DEVELOPMENT.md # 扩展开发指南
│   └── MULTI_SYNTAX_GUIDE.md # 多语法模式详解
├── tests/                # 测试文件
├── build.zig             # Zig 构建配置
└── build.zig.zon         # Zig 包管理配置
```

## 构建和运行

### 环境要求

- **Zig**: 0.15.2 或更高版本
- **libc**: 用于系统集成
- **操作系统**: macOS、Linux 或 Windows

### 构建命令

```bash
# 构建项目
zig build

# 构建产物位置
./zig-out/bin/php-interpreter
```

### 运行命令

```bash
# 运行 PHP 脚本（PHP 模式，默认）
./zig-out/bin/php-interpreter script.php

# 使用 Go 语法模式
./zig-out/bin/php-interpreter --syntax=go script.php

# 使用字节码模式（更高性能）
./zig-out/bin/php-interpreter --mode=bytecode script.php

# 自动选择执行模式
./zig-out/bin/php-interpreter --mode=auto script.php

# 使用自定义配置文件
./zig-out/bin/php-interpreter --config=myconfig.json script.php

# AOT 编译
./zig-out/bin/php-interpreter --compile hello.php

# AOT 编译带优化
./zig-out/bin/php-interpreter --compile --optimize=release-fast --static app.php

# 交叉编译到 Linux
./zig-out/bin/php-interpreter --compile --target=x86_64-linux-gnu app.php
```

### 测试命令

```bash
# 运行所有单元测试
zig build test

# 运行 AOT 编译器测试
zig build test-aot

# 运行 PHP 兼容性测试（需要运行 run_compatibility_tests.sh）
zig build test-compat

# 运行所有测试（单元测试 + 兼容性测试）
zig build test-all

# 性能基准测试
zig build bench

# 内存泄漏检查
zig build leak-check

# 清理构建产物
zig build clean
```

### 开发命令

```bash
# 运行应用程序
zig build run -- arg1 arg2

# 查看帮助
./zig-out/bin/php-interpreter --help

# 查看版本
./zig-out/bin/php-interpreter --version

# 列出支持的 AOT 目标平台
./zig-out/bin/php-interpreter --list-targets
```

## 配置文件

项目支持配置文件 `.zigphp.json` 或 `zigphp.config.json`：

```json
{
    "syntax": "php",
    "extensions": [],
    "include_paths": ["./lib"],
    "error_reporting": 32767
}
```

配置优先级：命令行参数 > 配置文件

## 多语法模式详解

### PHP 模式（默认）

```php
<?php
$name = "World";
$obj = new stdClass();
$obj->prop = "value";
echo "Hello, " . $name . "\n";
echo $obj->prop . "\n";
```

### Go 模式

```php
// @syntax: go
<?php
name = "World"
obj = new stdClass()
obj.prop = "value"
echo "Hello, " + name + "\n"
echo obj.prop + "\n"
```

### 语法模式对比

| 特性 | PHP 模式 | Go 模式 |
|------|----------|---------|
| 变量声明 | `$name` | `name` |
| 属性访问 | `$obj->prop` | `obj.prop` |
| 方法调用 | `$obj->method()` | `obj.method()` |
| 字符串拼接 | `$a . $b` | `a + b` |

### 切换语法模式

**方式一：命令行参数**
```bash
./zig-out/bin/php-interpreter --syntax=go script.php
```

**方式二：文件指令**
```php
// @syntax: go
<?php
// Go 模式代码
```

**方式三：配置文件**
```json
{
    "syntax": "go"
}
```

## 开发约定

### 代码风格

- 遵循 Zig 语言官方编码规范
- 使用 4 空格缩进
- 函数和类型使用 PascalCase
- 变量使用 camelCase
- 常量使用 ALL_CAPS

### 测试规范

- 所有测试文件以 `test_` 开头
- 使用 Zig 的内置测试框架
- 测试覆盖核心功能：类型系统、GC、解析器、VM、AOT 编译器
- 包含属性测试（property-based testing）验证正确性
- AOT 编译器有 34 个测试文件，覆盖所有模块

### 文档规范

- 关键模块应有详细的文档注释
- 公共 API 需要说明参数、返回值和可能的错误
- 新功能需要更新 README.md 和相关文档

### 提交规范

- 提交前确保所有测试通过
- 检查内存泄漏（使用 `zig build leak-check`）
- 遵循现有提交消息风格

## 核心模块说明

### 编译器模块 (`src/compiler/`)

#### lexer.zig - 词法分析器

支持多语法模式的词法分析，根据配置产生不同的 Token：

```zig
pub const Lexer = struct {
    buffer: [:0]const u8,
    pos: usize = 0,
    syntax_mode: SyntaxMode = .php,

    pub fn initWithMode(buffer: [:0]const u8, mode: SyntaxMode) Lexer;
    pub fn next(self: *Lexer) Token;
};
```

**关键特性：**
- UTF-8 字符串处理
- PHP 特定 token 识别（变量、操作符、关键字）
- 错误恢复机制
- 位置跟踪用于错误报告

#### parser.zig - 语法分析器

递归下降解析器，构建抽象语法树（AST）：

```zig
pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,
    context: *PHPContext,
    syntax_mode: SyntaxMode = .php,

    pub fn initWithMode(
        allocator: std.mem.Allocator,
        context: *PHPContext,
        source: [:0]const u8,
        mode: SyntaxMode
    ) !Parser;

    pub fn parse(self: *Parser) !ast.Node.Index;
};
```

**支持的 AST 节点类型：**
- `root` - 程序根节点
- `function_decl` - 函数声明
- `class_decl` - 类声明
- `variable` - 变量引用
- `property_access` - 属性访问
- `method_call` - 方法调用
- `binary_expr` - 二元表达式
- `assignment` - 赋值语句
- `echo_stmt` - echo 语句
- `if_stmt`, `while_stmt`, `for_stmt`, `foreach_stmt` - 控制流
- `closure`, `arrow_function` - 闭包和箭头函数

### 运行时模块 (`src/runtime/`)

#### vm.zig - 虚拟机

支持两种执行模式：

```zig
pub const ExecutionMode = enum {
    tree_walking,  // 树遍历解释器（默认，兼容性最好）
    bytecode,      // 字节码虚拟机（更高性能）
    auto,          // 自动选择
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    context: *PHPContext,
    syntax_config: SyntaxConfig,
    extension_registry: ?*ExtensionRegistry,

    pub fn init(allocator: std.mem.Allocator) !VM;
    pub fn deinit(self: *VM) void;
    pub fn run(self: *VM, program: ast.Node.Index) !Value;
    pub fn setExecutionMode(self: *VM, mode: ExecutionMode) void;
};
```

**函数调用流程：**
1. 检查扩展函数
2. 检查内置函数
3. 检查用户定义函数

#### types.zig - 类型系统

实现 PHP 的动态类型系统：

```zig
pub const Value = union(enum) {
    null_val,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_val: *String,
    array_val: *Array,
    object_val: *Object,
    callable_val: *Callable,
    resource_val: *Resource,
};
```

支持自动类型转换，遵循 PHP 语义。

#### gc.zig - 垃圾回收器

混合 GC 策略：

- **引用计数** - 即时清理无引用对象
- **循环检测** - 处理循环引用
- **自动触发** - 基于内存阈值

```zig
pub fn Box(comptime T: type) type {
    return struct {
        ref_count: u32,
        gc_info: GCInfo,
        data: T,
    };
}
```

### AOT 编译器模块 (`src/aot/`)

完整的 AOT 编译管道，包含 34 个模块文件：

#### 编译流程

```
PHP Source → Lexer → Parser → AST → Type Inference → IR Generation →
Optimization → Code Generation → Linking → Native Executable
```

#### 核心模块

| 模块 | 文件 | 功能 |
|------|------|------|
| 编译器入口 | `compiler.zig` | AOT 编译器主入口，协调整个编译流程 |
| 类型推断 | `type_inference.zig` | 静态类型分析，推断变量和表达式类型 |
| 符号表 | `symbol_table.zig` | 管理作用域和符号信息 |
| IR 生成 | `ir_generator.zig` | 从 AST 生成 SSA 形式的中间表示 |
| IR 定义 | `ir.zig` | 中间表示的数据结构定义 |
| 优化器 | `optimizer.zig` | IR 优化（死代码消除、常量折叠、内联等） |
| 代码生成 | `codegen.zig` | LLVM 机器码生成 |
| 链接器 | `linker.zig` | 静态链接，生成最终可执行文件 |
| 运行时库 | `runtime_lib.zig` | 原生 PHP 运行时支持 |
| 诊断 | `diagnostics.zig` | 错误报告和诊断信息 |
| 依赖解析 | `dependency_resolver.zig` | 解析 include/require 依赖 |
| 多文件编译 | `multi_file_compiler.zig` | 支持多文件项目编译 |

#### 编译选项

```zig
pub const CompileOptions = struct {
    input_file: []const u8,
    output_file: ?[]const u8 = null,
    target: Target = .native,
    optimize_level: OptimizeLevel = .debug,
    static_link: bool = false,
    dump_ir: bool = false,
    dump_ast: bool = false,
    verbose: bool = false,
    syntax_mode: SyntaxMode = .php,
};

pub const OptimizeLevel = enum {
    debug,           // 调试构建，无优化
    release_safe,    // 发布构建，安全优化
    release_fast,    // 发布构建，最大性能
    release_small,   // 发布构建，最小体积
};
```

#### 支持的目标平台

- **Linux**: x86_64-linux-gnu, x86_64-linux-musl, aarch64-linux-gnu
- **macOS**: x86_64-macos-none, aarch64-macos-none
- **Windows**: x86_64-windows-msvc, x86_64-windows-gnu

---

### AOT IR（中间表示）详解

位置：`src/aot/ir.zig`

IR 是 AOT 编译器的核心，采用 SSA（Static Single Assignment）形式，便于优化和代码生成。

#### IR 层次结构

```
Module (编译单元)
├── Function (函数)
│   ├── BasicBlock (基本块)
│   │   ├── Instruction (指令)
│   │   └── Terminator (终止符)
│   └── Parameter (参数)
├── Global (全局变量)
└── TypeDef (类型定义)
```

#### 核心数据结构

**1. Module（编译单元）**

```zig
pub const Module = struct {
    allocator: Allocator,
    name: []const u8,                    // 模块名（通常是源文件名）
    source_file: []const u8,             // 源文件路径
    functions: std.ArrayListUnmanaged(*Function),  // 所有函数
    globals: std.ArrayListUnmanaged(*Global),      // 全局变量
    types: std.ArrayListUnmanaged(*TypeDef),       // 类型定义
    string_table: std.ArrayListUnmanaged([]const u8), // 字符串表

    // 添加函数、全局变量、类型定义
    pub fn addFunction(self: *Self, func: *Function) !void;
    pub fn addGlobal(self: *Self, global: *Global) !void;
    pub fn addTypeDef(self: *Self, type_def: *TypeDef) !void;

    // 字符串驻留
    pub fn internString(self: *Self, str: []const u8) !u32;
    pub fn getString(self: *const Self, id: u32) ?[]const u8;

    // 查找函数
    pub fn findFunction(self: *const Self, name: []const u8) ?*Function;
};
```

**2. Function（函数）**

```zig
pub const Function = struct {
    allocator: Allocator,
    name: []const u8,                    // 函数名
    params: std.ArrayListUnmanaged(Parameter),  // 参数列表
    return_type: Type,                  // 返回类型
    blocks: std.ArrayListUnmanaged(*BasicBlock), // 基本块列表
    is_exported: bool,                  // 是否导出
    is_method: bool,                    // 是否为方法
    class_name: ?[]const u8,            // 类名（如果是方法）
    location: SourceLocation,           // 源码位置
    next_register_id: u32,              // 下一个寄存器 ID

    // 创建基本块
    pub fn createBlock(self: *Self, label: []const u8) !*BasicBlock;

    // 分配新的 SSA 寄存器
    pub fn newRegister(self: *Self, type_: Type) Register;

    // 获取入口块
    pub fn getEntryBlock(self: *const Self) ?*BasicBlock;
};
```

**3. BasicBlock（基本块）**

基本块是具有单一入口和单一出口的指令序列：

```zig
pub const BasicBlock = struct {
    allocator: Allocator,
    label: []const u8,                   // 块标签（用于跳转）
    instructions: std.ArrayListUnmanaged(*Instruction), // 指令列表
    terminator: ?Terminator,            // 终止符
    predecessors: std.ArrayListUnmanaged(*BasicBlock), // 前驱块
    successors: std.ArrayListUnmanaged(*BasicBlock),   // 后继块

    // 添加指令
    pub fn appendInstruction(self: *Self, inst: *Instruction) !void;

    // 设置终止符
    pub fn setTerminator(self: *Self, term: Terminator) void;

    // 检查是否已终止
    pub fn isTerminated(self: *const Self) bool;

    // 添加前驱/后继块
    pub fn addPredecessor(self: *Self, pred: *BasicBlock) !void;
    pub fn addSuccessor(self: *Self, succ: *BasicBlock) !void;
};
```

**4. Register（SSA 寄存器）**

SSA 寄存器表示一个值，每个寄存器只被赋值一次：

```zig
pub const Register = struct {
    id: u32,                            // 唯一 ID（函数内）
    type_: Type,                        // 值的类型

    // 格式化输出（如 %0, %1, %2）
    pub fn format(self: Register, ... writer: anytype) !void;

    // 比较相等
    pub fn eql(self: Register, other: Register) bool;
};
```

**5. Terminator（终止符）**

终止符定义控制流如何离开基本块：

```zig
pub const Terminator = union(enum) {
    ret: ?Register,                     // 返回（可选返回值）
    br: *BasicBlock,                    // 无条件跳转
    cond_br: struct {                   // 条件跳转
        cond: Register,
        then_block: *BasicBlock,
        else_block: *BasicBlock,
    },
    switch_: struct {                    // switch 语句
        value: Register,
        cases: []const SwitchCase,
        default: *BasicBlock,
    },
    unreachable_: void,                 // 不可达（死代码）
    throw: Register,                    // 抛出异常

    pub const SwitchCase = struct {
        value: i64,
        block: *BasicBlock,
    };
};
```

**6. Type（类型系统）**

IR 类型系统映射 PHP 类型到原生类型：

```zig
pub const Type = union(enum) {
    void: void,                         // 无返回值
    bool: void,                         // 布尔
    i64: void,                          // 64位整数
    f64: void,                          // 64位浮点
    ptr: *const Type,                   // 指针
    php_value: void,                    // 动态 PHP 值
    php_string: void,                   // PHP 字符串
    php_array: void,                    // PHP 数组
    php_object: []const u8,             // PHP 对象（带类名）
    php_resource: void,                 // PHP 资源
    php_callable: void,                 // PHP 可调用对象
    function: FunctionType,             // 函数类型
    nullable: *const Type,              // 可空类型

    pub const FunctionType = struct {
        params: []const Type,
        return_type: *const Type,
    };

    // 检查是否为动态类型
    pub fn isDynamic(self: Type) bool;

    // 检查是否为基本类型
    pub fn isPrimitive(self: Type) bool;

    // 获取类型大小（字节）
    pub fn sizeOf(self: Type) usize;

    // 格式化输出
    pub fn format(self: Type, ... writer: anytype) !void;
};
```

**7. Instruction（指令）**

IR 指令类型（部分）：

```zig
pub const Instruction = union(enum) {
    // 常量
    const_int: i64,
    const_float: f64,
    const_bool: bool,
    const_null: void,
    const_string: u32,                  // 字符串表索引

    // 算术运算
    add: struct { lhs: Register, rhs: Register },
    sub: struct { lhs: Register, rhs: Register },
    mul: struct { lhs: Register, rhs: Register },
    div: struct { lhs: Register, rhs: Register },
    mod: struct { lhs: Register, rhs: Register },

    // 位运算
    bit_and: struct { lhs: Register, rhs: Register },
    bit_or: struct { lhs: Register, rhs: Register },
    bit_xor: struct { lhs: Register, rhs: Register },
    bit_not: struct { operand: Register },
    shl: struct { lhs: Register, rhs: Register },
    shr: struct { lhs: Register, rhs: Register },

    // 比较运算
    eq: struct { lhs: Register, rhs: Register },
    ne: struct { lhs: Register, rhs: Register },
    lt: struct { lhs: Register, rhs: Register },
    le: struct { lhs: Register, rhs: Register },
    gt: struct { lhs: Register, rhs: Register },
    ge: struct { lhs: Register, rhs: Register },

    // 逻辑运算
    logical_and: struct { lhs: Register, rhs: Register },
    logical_or: struct { lhs: Register, rhs: Register },
    logical_not: struct { operand: Register },

    // 类型转换
    cast: struct { value: Register, target_type: Type },
    trunc: struct { value: Register },
    zext: struct { value: Register },
    sext: struct { value: Register },
    fptrunc: struct { value: Register },
    fpext: struct { value: Register },
    fptoui: struct { value: Register },
    fptosi: struct { value: Register },
    uitofp: struct { value: Register },
    sitofp: struct { value: Register },
    ptrtoint: struct { value: Register },
    inttoptr: struct { value: Register },
    bitcast: struct { value: Register },

    // 内存操作
    alloc: Type,                        // 栈分配
    load: Register,                     // 加载
    store: struct { ptr: Register, value: Register },
    getelementptr: struct { ptr: Register, indices: []const Register },

    // 控制流
    phi: PhiNode,                       // PHI 节点
    call: CallInfo,                     // 函数调用
    invoke: InvokeInfo,                 // 可调用对象调用
    tail_call: CallInfo,                // 尾调用

    // PHP 特定操作
    php_new: struct { class_name: u32, args: []const Register },
    php_clone: Register,
    php_property_get: struct { obj: Register, prop: u32 },
    php_property_set: struct { obj: Register, prop: u32, value: Register },
    php_method_call: struct { obj: Register, method: u32, args: []const Register },
    php_array_get: struct { array: Register, key: Register },
    php_array_set: struct { array: Register, key: Register, value: Register },
    php_array_push: struct { array: Register, value: Register },
    php_array_count: Register,
    php_string_concat: struct { lhs: Register, rhs: Register },
    php_string_length: Register,
    php_echo: Register,
    php_print: Register,
    php_println: Register,

    // 其他
    unreachable: void,
    comment: []const u8,

    pub const PhiNode = struct {
        incoming: []const struct {
            value: Register,
            block: *BasicBlock,
        },
    };

    pub const CallInfo = struct {
        callee: []const u8,             // 函数名
        args: []const Register,         // 参数
        is_tail: bool = false,          // 是否尾调用
    };

    pub const InvokeInfo = struct {
        callable: Register,             // 可调用对象
        args: []const Register,         // 参数
        normal_block: *BasicBlock,      // 正常返回块
    };
};
```

---

### AOT 优化器详解

位置：`src/aot/optimizer.zig`

优化器对 IR 应用多种优化 pass，提高生成代码的性能和大小。

#### 优化级别配置

```zig
pub const OptimizeLevel = enum {
    none,           // 无优化（debug）
    basic,          // 基本优化（release-safe）
    aggressive,     // 激进优化（release-fast）
    size,           // 大小优化（release-small）
};

pub const PassConfig = struct {
    dead_code_elimination: bool = true,      // 死代码消除
    constant_propagation: bool = true,      // 常量传播
    function_inlining: bool = false,        // 函数内联
    inline_threshold: u32 = 20,             // 内联阈值（指令数）
    type_specialization: bool = false,       // 类型特化
    cse: bool = false,                      // 公共子表达式消除
    licm: bool = false,                     // 循环不变量外提
    strength_reduction: bool = false,       // 强度削减
    max_iterations: u32 = 3,                // 最大优化迭代次数

    // 预设配置
    pub fn debug() PassConfig;              // 无优化
    pub fn releaseSafe() PassConfig;        // 基本优化
    pub fn releaseFast() PassConfig;        // 激进优化
    pub fn releaseSmall() PassConfig;       // 大小优化
};
```

#### 优化 Pass

**1. 死代码消除（DCE）**

移除未被使用的指令和基本块：

```zig
// 算法：
// 1. 标记所有被使用的寄存器（从终止符和 PHI 节点开始）
// 2. 向后遍历，标记定义这些寄存器的指令
// 3. 移除所有未被标记的指令
// 4. 移除所有未被引用的基本块
```

**2. 常量传播**

将常量值传播到使用点：

```zig
// 示例：
// 优化前：
//   %1 = const_int 42
//   %2 = const_int 10
//   %3 = add %1, %2
//   %4 = const_int 52
//
// 优化后：
//   %3 = const_int 52  // 直接计算结果
```

**3. 函数内联**

将小函数内联到调用点：

```zig
// 内联条件：
// - 函数大小 < inline_threshold
// - 函数不被递归调用
// - 函数不包含循环（或循环很小）

// 示例：
// 优化前：
//   fn add(a, b) { return a + b; }
//   %result = call add(%x, %y)
//
// 优化后：
//   %result = add %x, %y  // 直接内联
```

**4. 公共子表达式消除（CSE）**

消除重复计算：

```zig
// 示例：
// 优化前：
//   %1 = add %a, %b
//   %2 = add %a, %b
//   %3 = mul %1, %2
//
// 优化后：
//   %1 = add %a, %b
//   %3 = mul %1, %1  // 重用 %1
```

**5. 循环不变量外提（LICM）**

将循环内不变的计算移到循环外：

```zig
// 示例：
// 优化前：
//   loop:
//     %1 = mul %x, %y  // x 和 y 在循环内不变
//     %2 = add %i, %1
//     ...
//
// 优化后：
//   %1 = mul %x, %y  // 移到循环外
//   loop:
//     %2 = add %i, %1
//     ...
```

**6. 强度削减**

用更快的操作替换慢速操作：

```zig
// 示例：
// 优化前：
//   %1 = mul %x, 4
//   %2 = mul %x, 2
//
// 优化后：
//   %1 = shl %x, 2  // 乘以 4 改为左移 2 位
//   %2 = shl %x, 1  // 乘以 2 改为左移 1 位
```

**7. 类型特化**

为特定类型生成特化代码：

```zig
// 示例：
// 优化前：
//   fn add(a, b) { return a + b; }  // 通用版本
//
// 优化后：
//   fn add_int(a: i64, b: i64) -> i64 { return a + b; }
//   fn add_float(a: f64, b: f64) -> f64 { return a + b; }
```

#### 优化统计

```zig
pub const OptimizationStats = struct {
    dead_instructions_removed: u32 = 0,
    dead_blocks_removed: u32 = 0,
    constants_propagated: u32 = 0,
    functions_inlined: u32 = 0,
    type_specializations: u32 = 0,
    cse_eliminations: u32 = 0,
    passes_run: u32 = 0,

    pub fn print(self: *const OptimizationStats, writer: anytype) !void;
};
```

---

### AOT 代码生成器详解

位置：`src/aot/codegen.zig`

代码生成器将 IR 转换为 LLVM IR，然后使用 LLVM 后端生成原生机器码。

#### LLVM 集成

```zig
// LLVM C API 类型（不透明指针）
pub const LLVMContextRef = ?*anyopaque;
pub const LLVMModuleRef = ?*anyopaque;
pub const LLVMBuilderRef = ?*anyopaque;
pub const LLVMTypeRef = ?*anyopaque;
pub const LLVMValueRef = ?*anyopaque;
pub const LLVMBasicBlockRef = ?*anyopaque;
pub const LLVMTargetMachineRef = ?*anyopaque;
```

#### 目标平台配置

```zig
pub const Target = struct {
    arch: Arch,                         // 架构
    os: OS,                             // 操作系统
    abi: ABI,                           // ABI

    pub const Arch = enum {
        x86_64,                         // x86_64
        aarch64,                        // ARM64
        arm,                            // ARM
    };

    pub const OS = enum {
        linux,                          // Linux
        macos,                          // macOS
        windows,                        // Windows
    };

    pub const ABI = enum {
        gnu,                            // GNU ABI
        musl,                           // musl libc
        msvc,                           // MSVC
        none,                           // 无 ABI（macOS）
    };

    // 获取原生目标
    pub fn native() Target;

    // 从 triple 字符串解析
    pub fn fromString(triple: []const u8) !Target;

    // 转换为 LLVM triple
    pub fn toTriple(self: Target, allocator: Allocator) ![]const u8;
};
```

#### 代码生成器结构

```zig
pub const CodeGenerator = struct {
    allocator: Allocator,

    // LLVM 句柄
    context: LLVMContextRef,
    module: LLVMModuleRef,
    builder: LLVMBuilderRef,
    target_machine: LLVMTargetMachineRef,
    di_builder: LLVMDIBuilderRef,

    // 配置
    target: Target,
    optimize_level: OptimizeLevel,
    debug_info: bool,

    // 类型缓存
    type_cache: TypeCache,

    // 运行时函数声明
    runtime_functions: std.StringHashMap(LLVMValueRef),

    // 寄存器映射
    register_map: std.AutoHashMap(u32, LLVMValueRef),

    // 基本块映射
    block_map: std.StringHashMap(LLVMBasicBlockRef),

    // 当前函数
    current_function: LLVMValueRef,
    current_ir_module: ?*const IR.Module,

    // 诊断
    diagnostics: *Diagnostics.DiagnosticEngine,

    // LLVM 可用性标志
    llvm_available: bool,

    // 调试信息
    di_compile_unit: LLVMMetadataRef,
    di_file: LLVMMetadataRef,
    di_current_scope: LLVMMetadataRef,

    pub const TypeCache = struct {
        void_type: LLVMTypeRef = null,
        bool_type: LLVMTypeRef = null,
        i8_type: LLVMTypeRef = null,
        i32_type: LLVMTypeRef = null,
        i64_type: LLVMTypeRef = null,
        f64_type: LLVMTypeRef = null,
        ptr_type: LLVMTypeRef = null,
        php_value_type: LLVMTypeRef = null,
        php_value_ptr_type: LLVMTypeRef = null,
        php_string_type: LLVMTypeRef = null,
        php_string_ptr_type: LLVMTypeRef = null,
        php_array_type: LLVMTypeRef = null,
        php_array_ptr_type: LLVMTypeRef = null,
        php_object_type: LLVMTypeRef = null,
        php_object_ptr_type: LLVMTypeRef = null,
    };
};
```

#### 运行时函数签名

代码生成器需要声明所有运行时函数：

```zig
pub const RuntimeFunctionSig = struct {
    name: []const u8,
    return_type: RuntimeType,
    param_types: []const RuntimeType,
    is_vararg: bool = false,
};

pub const RuntimeType = enum {
    void_type,
    bool_type,
    i8_type,
    i32_type,
    i64_type,
    f64_type,
    ptr_type,
    php_value_ptr,
    php_string_ptr,
    php_array_ptr,
    php_object_ptr,
};

// 运行时函数示例
pub const runtime_function_signatures = [_]RuntimeFunctionSig{
    // 值创建
    .{ .name = "php_value_create_null", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{} },
    .{ .name = "php_value_create_bool", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.bool_type} },
    .{ .name = "php_value_create_int", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.i64_type} },
    .{ .name = "php_value_create_float", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{.f64_type} },

    // 类型转换
    .{ .name = "php_value_to_int", .return_type = .i64_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
    .{ .name = "php_value_to_float", .return_type = .f64_type, .param_types = &[_]RuntimeType{.php_value_ptr} },

    // GC 函数
    .{ .name = "php_gc_retain", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
    .{ .name = "php_gc_release", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },

    // 数组函数
    .{ .name = "php_array_create", .return_type = .php_array_ptr, .param_types = &[_]RuntimeType{} },
    .{ .name = "php_array_get", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_value_ptr } },
    .{ .name = "php_array_set", .return_type = .void_type, .param_types = &[_]RuntimeType{ .php_array_ptr, .php_value_ptr, .php_value_ptr } },

    // 字符串函数
    .{ .name = "php_string_concat", .return_type = .php_value_ptr, .param_types = &[_]RuntimeType{ .php_value_ptr, .php_value_ptr } },
    .{ .name = "php_string_length", .return_type = .i64_type, .param_types = &[_]RuntimeType{.php_value_ptr} },

    // I/O 函数
    .{ .name = "php_echo", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
    .{ .name = "php_print", .return_type = .i64_type, .param_types = &[_]RuntimeType{.php_value_ptr} },

    // 异常函数
    .{ .name = "php_throw", .return_type = .void_type, .param_types = &[_]RuntimeType{.php_value_ptr} },
};
```

#### 代码生成流程

```zig
// 1. 初始化
pub fn init(
    allocator: Allocator,
    target: Target,
    optimize_level: OptimizeLevel,
    debug_info: bool,
    diagnostics: *Diagnostics.DiagnosticEngine,
) !*CodeGenerator;

// 2. 生成模块
pub fn generateModule(self: *Self, ir_module: *const IR.Module) !void;

// 3. 生成函数
pub fn generateFunction(self: *Self, ir_func: *const IR.Function) !void;

// 4. 生成基本块
pub fn generateBasicBlock(self: *Self, ir_block: *const IR.BasicBlock) !void;

// 5. 生成指令
pub fn generateInstruction(self: *Self, ir_inst: *const IR.Instruction) !LLVMValueRef;

// 6. 生成终止符
pub fn generateTerminator(self: *Self, ir_term: *const IR.Terminator) !void;

// 7. 清理
pub fn deinit(self: *Self) void;
```

#### 类型映射

IR 类型到 LLVM 类型的映射：

```zig
fn mapType(self: *Self, ir_type: IR.Type) !LLVMTypeRef {
    return switch (ir_type) {
        .void => self.type_cache.void_type,
        .bool => self.type_cache.bool_type,
        .i64 => self.type_cache.i64_type,
        .f64 => self.type_cache.f64_type,
        .ptr => |inner| {
            const inner_llvm = try self.mapType(inner.*);
            return LLVMPointerType(inner_llvm, 0);
        },
        .php_value => self.type_cache.php_value_type,
        .php_string => self.type_cache.php_string_type,
        .php_array => self.type_cache.php_array_type,
        .php_object => self.type_cache.php_object_type,
        .php_callable => self.type_cache.ptr_type,
        .function => |func_type| {
            const param_types = try self.allocator.alloc(LLVMTypeRef, func_type.params.len);
            for (func_type.params, 0..) |param, i| {
                param_types[i] = try self.mapType(param);
            }
            const return_type = try self.mapType(func_type.return_type.*);
            return LLVMFunctionType(return_type, param_types.ptr, @intCast(param_types.len), 0);
        },
        .nullable => |inner| {
            const inner_llvm = try self.mapType(inner.*);
            return LLVMPointerType(inner_llvm, 0);
        },
    };
}
```

### 扩展系统 (`src/extension/`)

#### api.zig - 扩展 API

定义扩展系统的核心类型和接口：

```zig
pub const EXTENSION_API_VERSION: u32 = 1;

pub const ExtensionInfo = struct {
    name: []const u8,
    version: []const u8,
    api_version: u32,
    author: []const u8,
    description: []const u8,
};

pub const ExtensionFunction = struct {
    name: []const u8,
    callback: ExtensionFunctionCallback,
    min_args: u8,
    max_args: u8,
    return_type: ?[]const u8,
    param_types: []const []const u8,
};

pub const ExtensionClass = struct {
    name: []const u8,
    parent: ?[]const u8,
    interfaces: []const []const u8,
    methods: []const ExtensionMethod,
    properties: []const ExtensionProperty,
    constructor: ?ExtensionConstructorCallback,
    destructor: ?ExtensionDestructorCallback,
};

pub const Extension = struct {
    info: ExtensionInfo,
    init_fn: ExtensionInitCallback,
    shutdown_fn: ?ExtensionShutdownCallback,
    functions: []const ExtensionFunction,
    classes: []const ExtensionClass,
    syntax_hooks: ?*const SyntaxHooks,
};
```

#### registry.zig - 扩展注册表

管理扩展的加载和注册：

```zig
pub const ExtensionRegistry = struct {
    allocator: std.mem.Allocator,
    extensions: std.StringHashMap(*const Extension),
    functions: std.StringHashMap(ExtensionFunction),
    classes: std.StringHashMap(ExtensionClass),
    syntax_hooks: std.ArrayList(*const SyntaxHooks),

    pub fn init(allocator: std.mem.Allocator) ExtensionRegistry;
    pub fn deinit(self: *ExtensionRegistry) void;

    pub fn loadExtension(self: *ExtensionRegistry, path: []const u8) ExtensionError!void;
    pub fn registerExtension(self: *ExtensionRegistry, extension: *const Extension) ExtensionError!void;
    pub fn findFunction(self: *ExtensionRegistry, name: []const u8) ?ExtensionFunction;
    pub fn findClass(self: *ExtensionRegistry, name: []const u8) ?ExtensionClass;
};
```

## 常见任务

### 添加新的内置函数

1. 在 `src/runtime/stdlib.zig` 中定义函数
2. 实现处理函数
3. 在标准库初始化中注册
4. 添加测试

**示例：**

```zig
// 在 stdlib.zig 中
fn builtinMyFunction(vm: *VM, args: []const Value) !Value {
    if (args.len < 2) return error.ArgumentCountError;
    // 实现逻辑
    return Value.initInt(result);
}

// 注册
try stdlib.registerFunction("my_function", &.{
    .name = "my_function",
    .min_args = 2,
    .max_args = 2,
    .handler = builtinMyFunction,
});
```

### 添加新的语言特性

1. 扩展 `src/compiler/lexer.zig` 中的 token 类型
2. 更新 `src/compiler/parser.zig` 中的语法规则
3. 在 `src/compiler/ast.zig` 中添加新的节点类型
4. 在 `src/runtime/vm.zig` 中实现求值逻辑
5. 更新类型系统（如需要）

### 开发扩展

1. 创建 Zig 文件，定义扩展函数和类
2. 实现 `zigphp_get_extension()` 导出函数
3. 编译为动态库
4. 通过 `--extension` 参数加载

**示例扩展：**

```zig
const std = @import("std");
const extension_api = @import("extension/api.zig");

fn myAdd(_: *anyopaque, args: []const extension_api.ExtensionValue) anyerror!extension_api.ExtensionValue {
    if (args.len < 2) return 0;
    const a: i64 = @bitCast(args[0]);
    const b: i64 = @bitCast(args[1]);
    return @bitCast(a + b);
}

const my_functions = [_]extension_api.ExtensionFunction{
    .{
        .name = "my_add",
        .callback = myAdd,
        .min_args = 2,
        .max_args = 2,
    },
};

const my_extension = extension_api.Extension{
    .info = .{
        .name = "my_extension",
        .version = "1.0.0",
        .api_version = extension_api.EXTENSION_API_VERSION,
        .author = "Your Name",
        .description = "My custom extension",
    },
    .init_fn = null,
    .shutdown_fn = null,
    .functions = &my_functions,
    .classes = &.{},
    .syntax_hooks = null,
};

pub export fn zigphp_get_extension() *const extension_api.Extension {
    return &my_extension;
}
```

编译：
```bash
zig build-lib -dynamic my_extension.zig -o libmy_extension.so
```

使用：
```bash
./zig-out/bin/php-interpreter --extension=./libmy_extension.so script.php
```

### 调试 AOT 编译

使用调试选项查看中间表示：

```bash
# 查看解析的 AST
./zig-out/bin/php-interpreter --compile --dump-ast app.php

# 查看生成的 IR
./zig-out/bin/php-interpreter --compile --dump-ir app.php

# 详细输出
./zig-out/bin/php-interpreter --compile --verbose app.php

# 同时查看 AST 和 IR
./zig-out/bin/php-interpreter --compile --dump-ast --dump-ir app.php
```

## 关键文件路径

- **主入口**: `src/main.zig:1`
- **构建配置**: `build.zig:1`
- **包配置**: `build.zig.zon:1`
- **词法分析器**: `src/compiler/lexer.zig:1`
- **语法分析器**: `src/compiler/parser.zig:1`
- **AST 定义**: `src/compiler/ast.zig:1`
- **Token 定义**: `src/compiler/token.zig:1`
- **语法模式**: `src/compiler/syntax_mode.zig:1`
- **虚拟机**: `src/runtime/vm.zig:1`
- **类型系统**: `src/runtime/types.zig:1`
- **垃圾回收器**: `src/runtime/gc.zig:1`
- **标准库**: `src/runtime/stdlib.zig:1`
- **反射系统**: `src/runtime/reflection.zig:1`
- **AOT 编译器**: `src/aot/compiler.zig:1`
- **AOT 类型推断**: `src/aot/type_inference.zig:1`
- **AOT IR 生成**: `src/aot/ir_generator.zig:1`
- **AOT IR 定义**: `src/aot/ir.zig:1`
- **AOT 优化器**: `src/aot/optimizer.zig:1`
- **AOT 代码生成**: `src/aot/codegen.zig:1`
- **AOT 链接器**: `src/aot/linker.zig:1`
- **AOT 运行时库**: `src/aot/runtime_lib.zig:1`
- **AOT 诊断**: `src/aot/diagnostics.zig:1`
- **扩展 API**: `src/extension/api.zig:1`
- **扩展注册表**: `src/extension/registry.zig:1`
- **配置加载器**: `src/config/loader.zig:1`

## 性能特性

- **函数调用开销**: ~50ns
- **对象实例化**: ~200ns
- **数组操作**: ~10ns/元素
- **字符串操作**: ~5ns/字符
- **垃圾回收**: <1ms（典型工作负载）

**性能优化特性：**
- 内联缓存用于方法调用
- 字符串驻留减少内存使用
- 数组专用存储优化
- 函数调用优化（内置函数直接调用）

## 已知限制

- 部分高级反射特性尚未实现
- 某些类型转换的边缘情况
- 性能优化仍有提升空间
- AOT 编译器的代码生成和链接部分尚未完全实现

## 相关文档

- [README.md](README.md) - 项目概述和快速开始
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - 详细架构文档
- [docs/USER_GUIDE.md](docs/USER_GUIDE.md) - 用户指南（中文）
- [docs/TECHNICAL_REFERENCE.md](docs/TECHNICAL_REFERENCE.md) - 技术参考
- [docs/EXTENSION_DEVELOPMENT.md](docs/EXTENSION_DEVELOPMENT.md) - 扩展开发指南
- [docs/MULTI_SYNTAX_GUIDE.md](docs/MULTI_SYNTAX_GUIDE.md) - 多语法模式详解

## 实用示例

### 基本用法

```php
<?php
// examples/hello.php
echo "Hello, World!\n";

$name = "PHP 8.5";
echo "Welcome to {$name}!\n";

$a = 10;
$b = 20;
$sum = $a + $b;
echo "Sum: {$sum}\n";
```

运行：
```bash
./zig-out/bin/php-interpreter examples/hello.php
```

### Go 语法模式

```php
// @syntax: go
<?php
name = "World"
count = 42
echo "name: " + name + "\n"
echo "count: " + count + "\n"

class Person {
    public name
    public age

    function __construct(name, age) {
        this.name = name
        this.age = age
    }

    function getInfo() {
        return "Name: " + this.name + ", Age: " + this.age
    }
}

person = new Person("Alice", 30)
echo person.getInfo() + "\n"
```

运行：
```bash
./zig-out/bin/php-interpreter examples/go_syntax_demo.php
```

### AOT 编译

```bash
# 基本编译
./zig-out/bin/php-interpreter --compile hello.php

# 带优化的编译
./zig-out/bin/php-interpreter --compile --optimize=release-fast --static app.php

# 交叉编译
./zig-out/bin/php-interpreter --compile --target=x86_64-linux-gnu app.php
```

## 故障排除

### 构建失败

1. 确认 Zig 版本 >= 0.15.2
2. 检查 libc 是否可用
3. 清理构建产物：`zig build clean`

### 运行时错误

1. 检查语法模式是否正确
2. 查看错误消息和堆栈跟踪
3. 使用 `--verbose` 选项获取更多信息

### 内存泄漏

1. 运行内存泄漏检查：`zig build leak-check`
2. 检查 Value 是否正确释放
3. 确认 GC 正常工作