# zig-php 技术参考文档

## 目录

1. [架构概述](#架构概述)
2. [编译器前端](#编译器前端)
3. [运行时系统](#运行时系统)
4. [扩展系统架构](#扩展系统架构)
5. [AOT 编译器](#aot-编译器)
6. [内存管理](#内存管理)
7. [类型系统](#类型系统)
8. [API 参考](#api-参考)

---

## 架构概述

zig-php 采用分层架构设计，主要包含以下组件：

```
┌─────────────────────────────────────────────────────────────┐
│                    Command Line Interface                    │
├─────────────────────────────────────────────────────────────┤
│                    Configuration Layer                       │
│              (Config Loader, Syntax Mode)                    │
├─────────────────────────────────────────────────────────────┤
│                    Compiler Frontend                         │
│              (Lexer → Parser → AST)                          │
├─────────────────────────────────────────────────────────────┤
│                    Extension System                          │
│         (Extension Registry, API, Loader)                    │
├─────────────────────────────────────────────────────────────┤
│                    Runtime Layer                             │
│    (Tree-Walking VM | Bytecode VM | AOT Compiler)           │
├─────────────────────────────────────────────────────────────┤
│                    Standard Library                          │
│         (Array, String, Math, File, JSON, etc.)             │
└─────────────────────────────────────────────────────────────┘
```

### 核心设计原则

1. **语法模式在前端处理** - Lexer 和 Parser 处理语法差异
2. **运行时语法无关** - VM 和字节码不关心原始语法模式
3. **扩展系统解耦** - 扩展通过定义良好的 API 接口集成
4. **内存安全** - 利用 Zig 的内存安全特性

---

## 编译器前端

### 词法分析器 (Lexer)

位置：`src/compiler/lexer.zig`

#### 语法模式支持

Lexer 根据配置的语法模式产生不同的 Token：

```zig
pub const Lexer = struct {
    buffer: [:0]const u8,
    pos: usize = 0,
    syntax_mode: SyntaxMode = .php,
    
    /// 初始化带语法模式的词法分析器
    pub fn initWithMode(buffer: [:0]const u8, mode: SyntaxMode) Lexer;
    
    /// 词法分析主函数
    pub fn next(self: *Lexer) Token;
};
```

#### Token 类型

| Token 类型 | PHP 模式 | Go 模式 |
|-----------|----------|---------|
| 变量 | `t_variable` ($name) | `t_go_identifier` (name) |
| 属性访问 | `arrow` (->) | `arrow` (. 转换为 ->) |
| 字符串拼接 | `dot` (.) | `plus` (+) |

### 语法分析器 (Parser)

位置：`src/compiler/parser.zig`

#### 初始化

```zig
pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,
    context: *PHPContext,
    syntax_mode: SyntaxMode = .php,
    
    /// 初始化带语法模式的解析器
    pub fn initWithMode(
        allocator: std.mem.Allocator,
        context: *PHPContext,
        source: [:0]const u8,
        mode: SyntaxMode
    ) !Parser;
    
    /// 解析源代码
    pub fn parse(self: *Parser) !ast.Node.Index;
};
```

#### AST 节点类型

主要节点类型定义在 `src/compiler/ast.zig`：

| 节点类型 | 说明 |
|---------|------|
| `root` | 程序根节点 |
| `function_decl` | 函数声明 |
| `class_decl` | 类声明 |
| `variable` | 变量引用 |
| `property_access` | 属性访问 |
| `method_call` | 方法调用 |
| `binary_expr` | 二元表达式 |
| `assignment` | 赋值语句 |

### 语法模式配置

位置：`src/compiler/syntax_mode.zig`

```zig
/// 语法模式枚举
pub const SyntaxMode = enum {
    php,  // PHP 风格: $var, $obj->prop
    go,   // Go 风格: var, obj.prop
    
    pub fn fromString(str: []const u8) ?SyntaxMode;
    pub fn toString(self: SyntaxMode) []const u8;
};

/// 语法模式配置
pub const SyntaxConfig = struct {
    mode: SyntaxMode = .php,
    allow_mixed_mode: bool = true,
    error_display_mode: SyntaxMode = .php,
    
    pub fn init(mode: SyntaxMode) SyntaxConfig;
    pub fn isPhpMode(self: SyntaxConfig) bool;
    pub fn isGoMode(self: SyntaxConfig) bool;
};
```

### 语法指令检测

```zig
/// 检测文件开头的语法指令
pub fn detectSyntaxDirective(source: []const u8) SyntaxDirectiveResult;

pub const SyntaxDirectiveResult = struct {
    mode: ?SyntaxMode,  // 检测到的模式
    found: bool,        // 是否找到指令
    line: usize,        // 指令所在行
};
```

支持的指令格式：
- `// @syntax: go`
- `// @syntax: php`
- `<?php // @syntax: go`

---

## 运行时系统

### 虚拟机 (VM)

位置：`src/runtime/vm.zig`

#### 执行模式

```zig
pub const ExecutionMode = enum {
    tree_walking,  // 树遍历解释器
    bytecode,      // 字节码虚拟机
    auto,          // 自动选择
};
```

#### VM 结构

```zig
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

#### 函数调用流程

1. 检查扩展函数
2. 检查内置函数
3. 检查用户定义函数

```zig
pub fn callFunction(self: *VM, name: []const u8, args: []const Value) !Value {
    // 1. 扩展函数
    if (self.extension_registry) |registry| {
        if (registry.findFunction(name)) |ext_func| {
            return ext_func.callback(self, args);
        }
    }
    
    // 2. 内置函数
    if (self.stdlib.getFunction(name)) |builtin| {
        return builtin(self, args);
    }
    
    // 3. 用户定义函数
    return self.callUserFunc(name, args);
}
```

### 字节码生成器

位置：`src/compiler/bytecode.zig`

字节码生成器将 AST 转换为字节码指令，与语法模式无关。

### 错误格式化

VM 支持语法感知的错误消息：

```zig
pub fn formatError(self: *VM, message: []const u8, var_name: ?[]const u8) []const u8 {
    if (self.syntax_config.error_display_mode == .go) {
        // Go 模式：移除 $ 前缀，使用 . 而非 ->
    }
    return message;
}
```

---

## 扩展系统架构

### 扩展 API

位置：`src/extension/api.zig`

#### API 版本

```zig
pub const EXTENSION_API_VERSION: u32 = 1;
```

#### 核心类型

```zig
/// 扩展值类型（不透明）
pub const ExtensionValue = u64;

/// 扩展信息
pub const ExtensionInfo = struct {
    name: []const u8,
    version: []const u8,
    api_version: u32,
    author: []const u8,
    description: []const u8,
};

/// 扩展函数
pub const ExtensionFunction = struct {
    name: []const u8,
    callback: ExtensionFunctionCallback,
    min_args: u8,
    max_args: u8,
    return_type: ?[]const u8,
    param_types: []const []const u8,
};

/// 扩展类
pub const ExtensionClass = struct {
    name: []const u8,
    parent: ?[]const u8,
    interfaces: []const []const u8,
    methods: []const ExtensionMethod,
    properties: []const ExtensionProperty,
    constructor: ?ExtensionConstructorCallback,
    destructor: ?ExtensionDestructorCallback,
};

/// 扩展接口
pub const Extension = struct {
    info: ExtensionInfo,
    init_fn: ExtensionInitCallback,
    shutdown_fn: ?ExtensionShutdownCallback,
    functions: []const ExtensionFunction,
    classes: []const ExtensionClass,
    syntax_hooks: ?*const SyntaxHooks,
};
```

### 扩展注册表

位置：`src/extension/registry.zig`

```zig
pub const ExtensionRegistry = struct {
    allocator: std.mem.Allocator,
    extensions: std.StringHashMap(*const Extension),
    functions: std.StringHashMap(ExtensionFunction),
    classes: std.StringHashMap(ExtensionClass),
    syntax_hooks: std.ArrayList(*const SyntaxHooks),
    
    pub fn init(allocator: std.mem.Allocator) ExtensionRegistry;
    pub fn deinit(self: *ExtensionRegistry) void;
    
    /// 加载动态库扩展
    pub fn loadExtension(self: *ExtensionRegistry, path: []const u8) ExtensionError!void;
    
    /// 注册静态扩展
    pub fn registerExtension(self: *ExtensionRegistry, extension: *const Extension) ExtensionError!void;
    
    /// 查找函数
    pub fn findFunction(self: *ExtensionRegistry, name: []const u8) ?ExtensionFunction;
    
    /// 查找类
    pub fn findClass(self: *ExtensionRegistry, name: []const u8) ?ExtensionClass;
};
```

### 扩展错误类型

```zig
pub const ExtensionError = error{
    ExtensionAlreadyLoaded,
    FunctionAlreadyExists,
    ClassAlreadyExists,
    IncompatibleApiVersion,
    InitializationFailed,
    InvalidExtension,
    ExtensionNotFound,
    OutOfMemory,
};
```

### 语法钩子

```zig
pub const SyntaxHooks = struct {
    custom_keywords: []const []const u8,
    parse_statement: ?*const fn (*anyopaque, u32) anyerror!?u32,
    parse_expression: ?*const fn (*anyopaque, u8) anyerror!?u32,
};
```

---

## AOT 编译器

位置：`src/aot/`

### 编译流程

```
PHP Source → Lexer → Parser → AST → Type Inference → IR Generation →
Optimization → Code Generation → Linking → Native Executable
```

### 主要模块

| 模块 | 文件 | 功能 |
|------|------|------|
| 类型推断 | `type_inference.zig` | 静态类型分析 |
| 符号表 | `symbol_table.zig` | 作用域和符号管理 |
| IR 生成 | `ir_generator.zig` | SSA 中间表示生成 |
| 优化器 | `optimizer.zig` | DCE、常量折叠、内联 |
| 代码生成 | `codegen.zig` | LLVM 机器码生成 |
| 链接器 | `linker.zig` | 静态链接 |
| 运行时库 | `runtime_lib.zig` | 原生 PHP 运行时支持 |

### 编译选项

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
    debug,
    release_safe,
    release_fast,
    release_small,
};
```

---

## 内存管理

### 垃圾回收

zig-php 使用引用计数 + 循环检测的混合 GC 策略：

- **引用计数** - 即时清理无引用对象
- **循环检测** - 处理循环引用
- **自动触发** - 基于内存阈值

### 分配器

使用 Zig 的 `GeneralPurposeAllocator` 和 `ArenaAllocator`：

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();

var arena = std.heap.ArenaAllocator.init(gpa.allocator());
defer arena.deinit();
```

---

## 类型系统

### Value 类型

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

### 类型转换

PHP 的动态类型转换规则在 `src/runtime/types.zig` 中实现。

---

## API 参考

### 配置加载器

位置：`src/config/loader.zig`

```zig
pub const ConfigLoader = struct {
    pub fn init(allocator: std.mem.Allocator) ConfigLoader;
    pub fn load(self: *ConfigLoader, path: []const u8) !Config;
    pub fn loadDefault(self: *ConfigLoader) !Config;
};

pub const Config = struct {
    syntax_mode: SyntaxMode = .php,
    extensions: []const []const u8 = &.{},
    include_paths: []const []const u8 = &.{},
    error_reporting: u32 = 0xFFFF,
};
```

### 辅助函数

```zig
// 创建扩展函数
pub fn createFunction(
    name: []const u8,
    callback: ExtensionFunctionCallback,
    min_args: u8,
    max_args: u8,
) ExtensionFunction;

// 创建扩展类
pub fn createClass(
    name: []const u8,
    methods: []const ExtensionMethod,
    properties: []const ExtensionProperty,
) ExtensionClass;

// 创建扩展信息
pub fn createExtensionInfo(
    name: []const u8,
    version: []const u8,
    author: []const u8,
    description: []const u8,
) ExtensionInfo;
```
