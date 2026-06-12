# Zig PHP Parser API 文档

## 概述

本文档描述 Zig PHP Parser 的核心 API，包括解析器、AOT 编译器、运行时库和优化器。

---

## 1. 解析器 API

### 1.1 Lexer（词法分析器）

```zig
const Lexer = @import("src/lexer.zig").Lexer;
```

#### 初始化
```zig
pub fn init(source: []const u8) Lexer
```
- **参数**: `source` - PHP 源代码
- **返回**: 初始化的词法分析器实例

#### 获取下一个 Token
```zig
pub fn next(self: *Lexer) Token
```
- **返回**: 下一个 Token

---

### 1.2 Parser（语法分析器）

```zig
const Parser = @import("src/parser.zig").Parser;
```

#### 初始化
```zig
pub fn init(allocator: Allocator, source: []const u8) !Parser
```

#### 解析
```zig
pub fn parse(self: *Parser) !*Ast
```
- **返回**: 抽象语法树（AST）

---

## 2. AOT 编译器 API

### 2.1 Compiler（编译器）

```zig
const Compiler = @import("src/aot/compiler.zig").Compiler;
```

#### 初始化
```zig
pub fn init(allocator: Allocator, options: CompilerOptions) Compiler
```

#### 编译
```zig
pub fn compile(self: *Compiler, ast: *Ast) !*Module
```

### 2.2 IRGenerator（IR 生成器）

```zig
const IRGenerator = @import("src/aot/ir_generator.zig").IRGenerator;
```

#### 常量折叠
```zig
pub fn tryConstantFold(self: *Self, node: *const Node) !?Register
```
- **功能**: 尝试在编译时折叠常量表达式
- **返回**: 折叠后的寄存器，或 null（不可折叠）

### 2.3 Optimizer（优化器）

```zig
const Optimizer = @import("src/aot/optimizer.zig").Optimizer;
```

#### 优化级别
```zig
pub const OptimizeLevel = enum {
    none,      // 无优化
    size,      // 优化代码体积
    speed,     // 优化执行速度（默认）
    aggressive // 激进优化
};
```

#### 优化模块
```zig
pub fn optimize(self: *Self, module: *Module) !bool
```

#### 支持的优化
| 优化类型 | 描述 |
|---------|------|
| 常量折叠 | 编译时计算常量表达式 |
| 常量传播 | 将常量值传播到使用处 |
| 死代码消除 | 移除未使用的代码和变量 |
| 函数内联 | 将小函数内联到调用点 |
| 公共子表达式消除 | 复用相同的计算结果 |

---

## 3. 运行时库 API

### 3.1 核心函数库

```zig
const core = @import("src/runtime/core/root.zig");
```

#### 字符串函数
```zig
// 获取字符串长度
pub fn strlen(str: []const u8) i64

// 字符串转大写
pub fn strtoupper(ctx: *CoreContext, str: []const u8) ![]u8

// 字符串转小写
pub fn strtolower(ctx: *CoreContext, str: []const u8) ![]u8

// 子字符串
pub fn substr(ctx: *CoreContext, str: []const u8, start: i64, length: ?i64) ![]u8

// 查找子字符串位置
pub fn strpos(haystack: []const u8, needle: []const u8, offset: i64) ?i64
```

#### 数学函数
```zig
pub fn abs(x: anytype) @TypeOf(x)
pub fn floor(x: f64) f64
pub fn ceil(x: f64) f64
pub fn round(x: f64, precision: i32) f64
pub fn sqrt(x: f64) f64
pub fn pow(base: f64, exp: f64) f64
```

#### 时间函数
```zig
pub fn time() i64
pub fn date(ctx: *CoreContext, format: []const u8, timestamp: ?i64) ![]u8
pub fn mktime(hour: i32, min: i32, sec: i32, month: i32, day: i32, year: i32) i64
```

### 3.2 运行时优化

```zig
const optimizations = @import("src/runtime/optimizations.zig");
```

#### 小整数缓存
```zig
pub const small_int_cache = SmallIntCache.init();

// 检查是否为小整数
pub fn isSmallInt(i: i64) bool

// 获取缓存的整数值
pub fn get(self: *const Self, i: i64) ?u64
```

#### 字符串池
```zig
pub const StringPool = struct {
    pub fn init(allocator: Allocator) Self
    pub fn deinit(self: *Self) void
    pub fn intern(self: *Self, str: []const u8) ![]const u8
};
```

#### 快速路径函数
```zig
// 带溢出检查的整数运算
pub fn fastIntAdd(a: i64, b: i64) ?i64
pub fn fastIntSub(a: i64, b: i64) ?i64
pub fn fastIntMul(a: i64, b: i64) ?i64
pub fn fastIntDiv(a: i64, b: i64) ?i64

// 快速类型检查
pub fn isQuickInt(val: u64) bool
pub fn quickExtractInt(val: u64) i64
```

---

## 4. 错误处理 API

### 4.1 编译时诊断

```zig
const DiagnosticEngine = @import("src/aot/diagnostics.zig").DiagnosticEngine;
```

#### 错误级别
```zig
pub const Severity = enum {
    note,
    warning,
    @"error"
};
```

#### CWE 标识
```zig
pub const CWE = enum(u32) {
    buffer_overflow = 119,
    use_after_free = 416,
    null_pointer_dereference = 476,
    division_by_zero = 369,
    // ...
};
```

#### 报告错误
```zig
pub fn reportError(self: *Self, location: SourceLocation, comptime fmt: []const u8, args: anytype) void
pub fn reportErrorWithCWE(self: *Self, location: SourceLocation, cwe: CWE, comptime fmt: []const u8, args: anytype) void
```

### 4.2 运行时错误处理

```zig
const RuntimeErrorHandler = @import("src/runtime/error_handler.zig").RuntimeErrorHandler;
```

#### 错误类型
```zig
pub const RuntimeErrorType = enum {
    division_by_zero,
    array_index_out_of_bounds,
    type_error,
    null_reference,
    // ...
};
```

#### 运行时检查函数
```zig
pub fn checkDivisionByZero(divisor: i64) !void
pub fn checkArrayBounds(index: i64, length: usize) !usize
pub fn checkedIntAdd(a: i64, b: i64) !i64
pub fn checkedIntSub(a: i64, b: i64) !i64
pub fn checkedIntMul(a: i64, b: i64) !i64
```

---

## 5. 值类型系统

### 5.1 PHPValue（NaN Boxing）

```zig
const Value = @import("src/aot/runtime_lib_template.zig").Value;
```

#### 构造函数
```zig
pub fn initNull() Value
pub fn initBool(b: bool) Value
pub fn initInt(i: i64) Value
pub fn initFloat(f: f64) Value
pub fn initString(allocator: Allocator, str: []const u8) !Value
pub fn initArray(allocator: Allocator) !Value
```

#### 类型检查
```zig
pub fn isNull(self: Value) bool
pub fn isBool(self: Value) bool
pub fn isInt(self: Value) bool
pub fn isFloat(self: Value) bool
pub fn isString(self: Value) bool
pub fn isArray(self: Value) bool
```

#### 值提取
```zig
pub fn asBool(self: Value) bool
pub fn asInt(self: Value) i64
pub fn asFloat(self: Value) f64
pub fn asString(self: Value) *PHPString
pub fn asArray(self: Value) *PHPArray
```

### 5.2 PHPString

```zig
const PHPString = @import("src/aot/runtime_lib_template.zig").PHPString;
```

#### 创建与管理
```zig
pub fn init(allocator: Allocator, str: []const u8) !*PHPString
pub fn retain(self: *PHPString) void
pub fn release(self: *PHPString, allocator: Allocator) void
```

#### 操作
```zig
pub fn concat(self: *PHPString, other: *PHPString, allocator: Allocator) !*PHPString
pub fn substring(self: *PHPString, start: i64, length: ?i64, allocator: Allocator) !*PHPString
pub fn len(self: *PHPString) usize
```

### 5.3 PHPArray

```zig
const PHPArray = @import("src/aot/runtime_lib_template.zig").PHPArray;
```

#### 创建与管理
```zig
pub fn init(allocator: Allocator) !*PHPArray
pub fn retain(self: *PHPArray) void
pub fn release(self: *PHPArray, allocator: Allocator) void
```

#### 操作
```zig
pub fn get(self: *PHPArray, key: ArrayKey) ?Value
pub fn set(self: *PHPArray, allocator: Allocator, key: ArrayKey, value: Value) !void
pub fn push(self: *PHPArray, allocator: Allocator, value: Value) !void
pub fn count(self: *PHPArray) usize
```

---

## 6. 性能基准测试

### 6.1 基准测试框架

```zig
const PerformanceComparison = @import("tests/benchmarks/performance_comparison.zig");
```

#### 执行模式
```zig
pub const ExecutionMode = enum {
    interpreter,
    aot,
    php_native
};
```

#### 运行基准测试
```zig
pub fn runBenchmark(self: *Self, name: []const u8, code: []const u8, mode: ExecutionMode) !BenchmarkResult
pub fn compareAllModes(self: *Self, name: []const u8, code: []const u8) !void
```

### 6.2 性能回归检测

```zig
const RegressionDetector = @import("tests/benchmarks/regression_detector.zig").RegressionDetector;
```

#### 检测回归
```zig
pub fn detectRegressions(self: *Self, current: []const BenchmarkResult) ![]RegressionResult
pub fn generateReport(self: *Self, results: []const RegressionResult) ![]u8
```

---

## 7. 使用示例

### 7.1 解析 PHP 代码
```zig
const std = @import("std");
const Parser = @import("parser.zig").Parser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "<?php echo 'Hello, World!'; ?>";
    var parser = try Parser.init(allocator, source);
    defer parser.deinit();

    const ast = try parser.parse();
    // 处理 AST...
}
```

### 7.2 AOT 编译
```zig
const Compiler = @import("aot/compiler.zig").Compiler;

pub fn compilePhp(allocator: Allocator, ast: *Ast) !*Module {
    var compiler = Compiler.init(allocator, .{
        .optimize_level = .speed,
        .debug_info = false,
    });
    defer compiler.deinit();

    return try compiler.compile(ast);
}
```

### 7.3 使用运行时函数
```zig
const core = @import("runtime/core/root.zig");

pub fn example(allocator: Allocator) !void {
    var ctx = core.common.CoreContext.init(allocator);
    
    const upper = try core.string.strtoupper(&ctx, "hello");
    defer allocator.free(upper);
    
    std.debug.print("Result: {s}\n", .{upper});
}
```

---

## 8. 内存管理约定

### 所有权规则
- **TRANSFER**: 调用者获得返回值所有权，负责释放
- **NON-OWNING**: 调用者不获得所有权，不应释放
- **SHARED**: 使用引用计数共享所有权

### 资源释放
```zig
// 使用 defer 确保资源释放
const result = try allocateResource();
defer freeResource(result);

// 使用 errdefer 处理错误路径
const resource = try allocate();
errdefer deallocate(resource);
```

---

## 9. 线程安全

- 所有核心函数为 **纯函数**，无共享状态
- `CoreContext` 为线程本地，不跨线程共享
- 引用计数操作为 **非原子**，单线程环境下使用
- 多线程环境需使用 `std.Thread.Mutex` 保护共享数据

---

## 10. 版本兼容性

| 组件 | 最低版本 | 推荐版本 |
|-----|---------|---------|
| Zig | 0.13.0 | 0.15.2 |
| PHP | 8.0 | 8.3 |

---

*文档版本: 1.0.0*
*最后更新: 2026-01-31*
