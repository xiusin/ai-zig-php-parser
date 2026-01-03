# 设计文档：AOT 原生编译功能

## 概述

本设计文档描述了 zig-php AOT 编译器的完整实现方案。核心思路是利用 Zig 编译器的原生代码生成能力，将 PHP 源代码通过 IR 转换为 Zig 源代码，然后编译链接成原生可执行文件。

### 设计目标

1. **零外部依赖** - 不依赖 LLVM 或其他外部编译器库
2. **跨平台支持** - 利用 Zig 的跨平台编译能力
3. **简单可维护** - 代码生成逻辑清晰，易于调试和扩展
4. **性能合理** - 生成的代码性能接近手写 Zig 代码

## 架构

### 编译流水线

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  PHP 源码   │────▶│   Parser    │────▶│    AST      │
└─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ 可执行文件  │◀────│   Linker    │◀────│ Zig 编译器  │
└─────────────┘     └─────────────┘     └─────────────┘
                                              ▲
                                              │
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Zig 源码   │◀────│  CodeGen    │◀────│     IR      │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 模块结构

```
src/aot/
├── compiler.zig          # 主编译器入口（已存在）
├── ir.zig                # IR 定义（已存在）
├── ir_generator.zig      # AST → IR（已存在）
├── zig_codegen.zig       # IR → Zig 源码（新增）
├── runtime_lib.zig       # 运行时库（已存在，需完善）
├── linker.zig            # 链接器（已存在，需修改）
├── optimizer.zig         # IR 优化器（已存在）
└── diagnostics.zig       # 诊断引擎（已存在）
```

## 组件和接口

### 1. Zig 代码生成器 (ZigCodeGenerator)

新增模块，负责将 IR 转换为 Zig 源代码。

```zig
pub const ZigCodeGenerator = struct {
    allocator: Allocator,
    output: std.ArrayList(u8),
    indent_level: u32,
    runtime_imports: std.StringHashMap(void),
    
    const Self = @This();
    
    /// 初始化代码生成器
    pub fn init(allocator: Allocator) Self;
    
    /// 生成完整的 Zig 程序
    pub fn generate(self: *Self, module: *const IR.Module) ![]const u8;
    
    /// 生成函数定义
    fn generateFunction(self: *Self, func: *const IR.Function) !void;
    
    /// 生成基本块
    fn generateBasicBlock(self: *Self, block: *const IR.BasicBlock) !void;
    
    /// 生成指令
    fn generateInstruction(self: *Self, inst: *const IR.Instruction) !void;
    
    /// 生成运行时库导入
    fn generateRuntimeImports(self: *Self) !void;
    
    /// 生成 main 函数入口
    fn generateMainEntry(self: *Self) !void;
};
```

### 2. 运行时库接口

运行时库提供 PHP 值类型和操作的 Zig 实现。

```zig
// 值创建
pub extern fn php_value_create_null() *PHPValue;
pub extern fn php_value_create_bool(b: bool) *PHPValue;
pub extern fn php_value_create_int(i: i64) *PHPValue;
pub extern fn php_value_create_float(f: f64) *PHPValue;
pub extern fn php_value_create_string(data: [*]const u8, len: usize) *PHPValue;
pub extern fn php_value_create_array() *PHPValue;

// 类型转换
pub extern fn php_value_to_int(val: *PHPValue) i64;
pub extern fn php_value_to_float(val: *PHPValue) f64;
pub extern fn php_value_to_bool(val: *PHPValue) bool;
pub extern fn php_value_to_string(val: *PHPValue) *PHPValue;

// 引用计数
pub extern fn php_gc_retain(val: *PHPValue) void;
pub extern fn php_gc_release(val: *PHPValue) void;

// 数组操作
pub extern fn php_array_get(arr: *PHPValue, key: *PHPValue) *PHPValue;
pub extern fn php_array_set(arr: *PHPValue, key: *PHPValue, val: *PHPValue) void;
pub extern fn php_array_push(arr: *PHPValue, val: *PHPValue) void;

// I/O
pub extern fn php_echo(val: *PHPValue) void;
pub extern fn php_print(val: *PHPValue) i64;

// 算术运算
pub extern fn php_add(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_sub(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_mul(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_div(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_mod(a: *PHPValue, b: *PHPValue) *PHPValue;

// 比较运算
pub extern fn php_eq(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_ne(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_lt(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_le(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_gt(a: *PHPValue, b: *PHPValue) *PHPValue;
pub extern fn php_ge(a: *PHPValue, b: *PHPValue) *PHPValue;

// 字符串操作
pub extern fn php_string_concat(a: *PHPValue, b: *PHPValue) *PHPValue;
```

### 3. 链接器接口

修改现有链接器，使用 Zig 编译器进行编译和链接。

```zig
pub const ZigLinker = struct {
    allocator: Allocator,
    config: LinkerConfig,
    diagnostics: *DiagnosticEngine,
    
    /// 编译并链接生成可执行文件
    pub fn compileAndLink(
        self: *Self,
        zig_source: []const u8,
        output_path: []const u8,
    ) !void;
    
    /// 构建 Zig 编译命令
    fn buildZigCommand(
        self: *Self,
        source_path: []const u8,
        output_path: []const u8,
    ) ![]const []const u8;
    
    /// 执行 Zig 编译器
    fn executeZigCompiler(self: *Self, args: []const []const u8) !void;
};
```

## 数据模型

### IR 到 Zig 的映射

| IR 类型 | Zig 类型 |
|---------|----------|
| IR.Type.void | void |
| IR.Type.bool | bool |
| IR.Type.i64 | i64 |
| IR.Type.f64 | f64 |
| IR.Type.php_value | *runtime.PHPValue |
| IR.Type.php_string | *runtime.PHPString |
| IR.Type.php_array | *runtime.PHPArray |

### 生成的 Zig 代码结构

```zig
// 自动生成的代码
const std = @import("std");
const runtime = @import("runtime");

// PHP 函数定义
fn php_user_function_name(args: []*runtime.PHPValue) *runtime.PHPValue {
    // 函数体
}

// 主入口
pub fn main() !void {
    runtime.initRuntime();
    defer runtime.deinitRuntime();
    
    // PHP 主程序代码
    php_main();
}

fn php_main() void {
    // 生成的 PHP 代码
}
```

## 正确性属性

*正确性属性是一种特征或行为，应该在系统的所有有效执行中保持为真——本质上是关于系统应该做什么的正式声明。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1: 编译输出等价性（往返属性）

*对于任意*有效的 PHP 程序，AOT 编译后运行的输出应该与解释器运行的输出完全相同。

**验证: 需求 4.2, 5.1-5.7**

### Property 2: IR 到 Zig 代码的语法正确性

*对于任意*有效的 IR 模块，生成的 Zig 代码应该能够通过 Zig 编译器的语法检查。

**验证: 需求 1.1, 1.2**

### Property 3: 引用计数正确性

*对于任意* PHPValue 的创建和使用序列，当引用计数降为零时，值应该被正确释放，且不会发生内存泄漏或双重释放。

**验证: 需求 2.5**

### Property 4: 类型转换一致性

*对于任意* PHP 值和目标类型，AOT 编译代码的类型转换结果应该与 PHP 语义一致。

**验证: 需求 1.4, 5.1**

### Property 5: 控制流正确性

*对于任意*包含控制流语句的 PHP 程序，AOT 编译后的执行路径应该与解释器相同。

**验证: 需求 1.5, 5.3**

### Property 6: 数组操作正确性

*对于任意*数组操作序列（创建、读取、写入、追加），AOT 编译代码的结果应该与解释器相同。

**验证: 需求 5.6**

### Property 7: 输出文件名正确性

*对于任意*指定的输出文件名，链接器生成的可执行文件路径应该与指定的路径完全匹配。

**验证: 需求 3.5**

## 错误处理

### 编译时错误

| 错误类型 | 错误码 | 描述 |
|----------|--------|------|
| FileNotFound | E001 | 输入文件不存在 |
| ParseError | E002 | PHP 语法错误 |
| TypeInferenceError | E003 | 类型推断失败 |
| IRGenerationError | E004 | IR 生成失败 |
| CodeGenerationError | E005 | Zig 代码生成失败 |
| CompilationError | E006 | Zig 编译失败 |
| LinkError | E007 | 链接失败 |

### 运行时错误

| 错误类型 | 描述 |
|----------|------|
| TypeError | 类型不匹配 |
| DivisionByZero | 除零错误 |
| OutOfMemory | 内存分配失败 |
| ArrayIndexOutOfBounds | 数组索引越界 |

## 测试策略

### 单元测试

- 测试 IR 指令到 Zig 代码的映射
- 测试运行时库的各个函数
- 测试链接器命令构建

### 属性测试

- 使用随机生成的 PHP 程序测试编译输出等价性
- 使用随机生成的 IR 测试代码生成正确性
- 使用随机的值操作序列测试引用计数

### 集成测试

- 端到端编译测试
- 跨平台编译测试
- 优化级别测试

### 测试配置

- 属性测试最少运行 100 次迭代
- 每个属性测试必须引用设计文档中的属性
- 标签格式: **Feature: aot-native-compilation, Property {number}: {property_text}**
