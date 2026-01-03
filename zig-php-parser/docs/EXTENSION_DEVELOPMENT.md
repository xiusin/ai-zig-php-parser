# zig-php 扩展开发指南

## 目录

1. [概述](#概述)
2. [快速开始](#快速开始)
3. [扩展结构](#扩展结构)
4. [注册函数](#注册函数)
5. [注册类](#注册类)
6. [语法钩子](#语法钩子)
7. [生命周期管理](#生命周期管理)
8. [构建和测试](#构建和测试)
9. [最佳实践](#最佳实践)
10. [完整示例](#完整示例)

---

## 概述

zig-php 扩展系统允许第三方开发者在不修改核心源代码的情况下扩展解释器功能。扩展可以：

- 注册自定义函数
- 注册自定义类
- 添加语法钩子
- 访问 VM 状态

### 扩展类型

| 类型 | 说明 | 加载方式 |
|------|------|----------|
| 动态扩展 | 编译为 .so/.dylib/.dll | `--extension=path` |
| 静态扩展 | 编译进解释器 | 源码集成 |

---

## 快速开始

### 1. 创建扩展文件

创建 `my_extension.zig`：

```zig
const std = @import("std");

// API 版本必须匹配
pub const EXTENSION_API_VERSION: u32 = 1;
pub const ExtensionValue = u64;

// ... 类型定义（见下文）...

// 扩展入口点
pub export fn zigphp_get_extension() *const Extension {
    return &my_extension;
}
```

### 2. 构建扩展

```bash
zig build-lib -dynamic my_extension.zig -o libmy_extension.so
```

### 3. 使用扩展

```bash
./zig-out/bin/php-interpreter --extension=./libmy_extension.so script.php
```

---

## 扩展结构

### 必需的类型定义

```zig
const std = @import("std");

/// API 版本 - 必须与解释器匹配
pub const EXTENSION_API_VERSION: u32 = 1;

/// 不透明值类型
pub const ExtensionValue = u64;

/// 扩展信息
pub const ExtensionInfo = struct {
    name: []const u8,
    version: []const u8,
    api_version: u32,
    author: []const u8,
    description: []const u8,
};

/// 函数回调签名
pub const ExtensionFunctionCallback = *const fn (
    *anyopaque,              // VM 指针
    []const ExtensionValue   // 参数
) anyerror!ExtensionValue;

/// 方法回调签名
pub const ExtensionMethodCallback = *const fn (
    *anyopaque,              // VM 指针
    *anyopaque,              // 对象指针
    []const ExtensionValue   // 参数
) anyerror!ExtensionValue;

/// 函数定义
pub const ExtensionFunction = struct {
    name: []const u8,
    callback: ExtensionFunctionCallback,
    min_args: u8,
    max_args: u8,
    return_type: ?[]const u8,
    param_types: []const []const u8,
};

/// 方法定义
pub const ExtensionMethod = struct {
    name: []const u8,
    callback: ExtensionMethodCallback,
    modifiers: Modifiers,
    min_args: u8,
    max_args: u8,

    pub const Modifiers = packed struct {
        is_public: bool = true,
        is_protected: bool = false,
        is_private: bool = false,
        is_static: bool = false,
        is_final: bool = false,
        is_abstract: bool = false,
    };
};

/// 属性定义
pub const ExtensionProperty = struct {
    name: []const u8,
    default_value: ?ExtensionValue,
    modifiers: Modifiers,
    type_hint: ?[]const u8,

    pub const Modifiers = packed struct {
        is_public: bool = true,
        is_protected: bool = false,
        is_private: bool = false,
        is_static: bool = false,
        is_readonly: bool = false,
    };
};

/// 构造函数回调
pub const ExtensionConstructorCallback = *const fn (
    *anyopaque,
    *anyopaque,
    []const ExtensionValue
) anyerror!void;

/// 析构函数回调
pub const ExtensionDestructorCallback = *const fn (
    *anyopaque,
    *anyopaque
) void;

/// 类定义
pub const ExtensionClass = struct {
    name: []const u8,
    parent: ?[]const u8,
    interfaces: []const []const u8,
    methods: []const ExtensionMethod,
    properties: []const ExtensionProperty,
    constructor: ?ExtensionConstructorCallback,
    destructor: ?ExtensionDestructorCallback,
};

/// 语法钩子
pub const SyntaxHooks = struct {
    custom_keywords: []const []const u8,
    parse_statement: ?*const fn (*anyopaque, u32) anyerror!?u32,
    parse_expression: ?*const fn (*anyopaque, u8) anyerror!?u32,
};

/// 初始化回调
pub const ExtensionInitCallback = *const fn (*anyopaque) anyerror!void;

/// 关闭回调
pub const ExtensionShutdownCallback = *const fn (*anyopaque) void;

/// 扩展主结构
pub const Extension = struct {
    info: ExtensionInfo,
    init_fn: ExtensionInitCallback,
    shutdown_fn: ?ExtensionShutdownCallback,
    functions: []const ExtensionFunction,
    classes: []const ExtensionClass,
    syntax_hooks: ?*const SyntaxHooks,
};
```

---

## 注册函数

### 基本函数

```zig
/// 加法函数实现
fn myAdd(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    if (args.len < 2) return 0;
    
    const a: i64 = @bitCast(args[0]);
    const b: i64 = @bitCast(args[1]);
    const result: i64 = a + b;
    
    return @bitCast(result);
}

/// 函数定义
const my_functions = [_]ExtensionFunction{
    .{
        .name = "my_add",
        .callback = myAdd,
        .min_args = 2,
        .max_args = 2,
        .return_type = "int",
        .param_types = &[_][]const u8{ "int", "int" },
    },
};
```

### 可变参数函数

```zig
/// 求和函数（可变参数）
fn mySum(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    var sum: i64 = 0;
    for (args) |arg| {
        const val: i64 = @bitCast(arg);
        sum += val;
    }
    return @bitCast(sum);
}

const sum_function = ExtensionFunction{
    .name = "my_sum",
    .callback = mySum,
    .min_args = 1,
    .max_args = 255,  // 255 表示无限制
    .return_type = "int",
    .param_types = &[_][]const u8{},
};
```

### 使用辅助函数

```zig
fn createFunction(
    name: []const u8,
    callback: ExtensionFunctionCallback,
    min_args: u8,
    max_args: u8,
) ExtensionFunction {
    return ExtensionFunction{
        .name = name,
        .callback = callback,
        .min_args = min_args,
        .max_args = max_args,
        .return_type = null,
        .param_types = &[_][]const u8{},
    };
}

// 使用
const func = createFunction("my_func", myCallback, 0, 2);
```

---

## 注册类

### 基本类

```zig
/// 构造函数
fn counterConstructor(
    _: *anyopaque,
    _: *anyopaque,
    _: []const ExtensionValue
) anyerror!void {
    // 初始化对象状态
}

/// 方法实现
fn counterIncrement(
    _: *anyopaque,
    _: *anyopaque,
    _: []const ExtensionValue
) anyerror!ExtensionValue {
    return 1;
}

fn counterGetValue(
    _: *anyopaque,
    _: *anyopaque,
    _: []const ExtensionValue
) anyerror!ExtensionValue {
    return 0;
}

/// 方法定义
const counter_methods = [_]ExtensionMethod{
    .{
        .name = "increment",
        .callback = counterIncrement,
        .modifiers = .{ .is_public = true },
        .min_args = 0,
        .max_args = 0,
    },
    .{
        .name = "getValue",
        .callback = counterGetValue,
        .modifiers = .{ .is_public = true },
        .min_args = 0,
        .max_args = 0,
    },
};

/// 属性定义
const counter_properties = [_]ExtensionProperty{
    .{
        .name = "value",
        .default_value = 0,
        .modifiers = .{ .is_private = true, .is_public = false },
        .type_hint = "int",
    },
};

/// 类定义
const counter_class = ExtensionClass{
    .name = "Counter",
    .parent = null,
    .interfaces = &[_][]const u8{},
    .methods = &counter_methods,
    .properties = &counter_properties,
    .constructor = counterConstructor,
    .destructor = null,
};
```

### 继承和接口

```zig
const child_class = ExtensionClass{
    .name = "ChildClass",
    .parent = "ParentClass",  // 继承
    .interfaces = &[_][]const u8{ "Interface1", "Interface2" },
    .methods = &child_methods,
    .properties = &child_properties,
    .constructor = childConstructor,
    .destructor = childDestructor,
};
```

---

## 语法钩子

语法钩子允许扩展添加自定义语法：

```zig
const my_syntax_hooks = SyntaxHooks{
    .custom_keywords = &[_][]const u8{ "mykey", "another" },
    .parse_statement = myParseStatement,
    .parse_expression = myParseExpression,
};

fn myParseStatement(
    parser: *anyopaque,
    token: u32
) anyerror!?u32 {
    // 返回 AST 节点索引，或 null 表示不处理
    return null;
}

fn myParseExpression(
    parser: *anyopaque,
    precedence: u8
) anyerror!?u32 {
    return null;
}
```

---

## 生命周期管理

### 初始化

```zig
fn extensionInit(_: *anyopaque) anyerror!void {
    // 分配资源
    // 打开连接
    // 加载配置
}
```

### 关闭

```zig
fn extensionShutdown(_: *anyopaque) void {
    // 释放资源
    // 关闭连接
    // 刷新缓冲区
}
```

### 完整扩展定义

```zig
const my_extension = Extension{
    .info = .{
        .name = "my_extension",
        .version = "1.0.0",
        .api_version = EXTENSION_API_VERSION,
        .author = "Your Name",
        .description = "My custom extension",
    },
    .init_fn = extensionInit,
    .shutdown_fn = extensionShutdown,
    .functions = &my_functions,
    .classes = &[_]ExtensionClass{ counter_class },
    .syntax_hooks = null,
};

/// 必须导出的入口点
pub export fn zigphp_get_extension() *const Extension {
    return &my_extension;
}
```

---

## 构建和测试

### 构建命令

```bash
# Linux
zig build-lib -dynamic my_extension.zig -o libmy_extension.so

# macOS
zig build-lib -dynamic my_extension.zig -o libmy_extension.dylib

# Windows
zig build-lib -dynamic my_extension.zig -o my_extension.dll
```

### 测试扩展

```bash
# 加载并测试
./zig-out/bin/php-interpreter --extension=./libmy_extension.so test.php
```

测试脚本 `test.php`：

```php
<?php
// 测试函数
$result = my_add(5, 3);
echo "my_add(5, 3) = $result\n";

// 测试类
$counter = new Counter();
$counter->increment();
$counter->increment();
echo "Counter value: " . $counter->getValue() . "\n";
```

### 单元测试

```zig
test "my_add function" {
    const result = try myAdd(undefined, &[_]ExtensionValue{
        @bitCast(@as(i64, 5)),
        @bitCast(@as(i64, 3)),
    });
    const value: i64 = @bitCast(result);
    try std.testing.expectEqual(@as(i64, 8), value);
}

test "extension info" {
    const ext = zigphp_get_extension();
    try std.testing.expectEqualStrings("my_extension", ext.info.name);
    try std.testing.expectEqual(EXTENSION_API_VERSION, ext.info.api_version);
}
```

运行测试：

```bash
zig test my_extension.zig
```

---

## 最佳实践

### 1. 版本兼容性

始终检查 API 版本：

```zig
.api_version = EXTENSION_API_VERSION,  // 使用常量
```

### 2. 错误处理

```zig
fn myFunction(_: *anyopaque, args: []const ExtensionValue) anyerror!ExtensionValue {
    if (args.len < 2) {
        return error.ArgumentCountMismatch;
    }
    // ...
}
```

### 3. 内存管理

- 避免在回调中分配长期内存
- 使用 VM 提供的分配器
- 在 shutdown 中清理所有资源

### 4. 命名约定

- 函数名使用小写下划线：`my_function`
- 类名使用 PascalCase：`MyClass`
- 添加前缀避免冲突：`myext_function`

### 5. 文档

为每个公开的函数和类添加文档注释。

---

## 完整示例

参见 `examples/extensions/sample_extension.zig`，包含：

- 函数注册示例
- 类注册示例
- 生命周期管理
- 单元测试

### 使用示例扩展

```bash
# 构建
zig build-lib -dynamic examples/extensions/sample_extension.zig -o libsample.so

# 运行
./zig-out/bin/php-interpreter --extension=./libsample.so script.php
```

### PHP/Go 模式使用

```php
<?php
// PHP 模式
$result = sample_add(10, 20);
$counter = new SampleCounter();
$counter->increment();
```

```php
// @syntax: go
<?php
// Go 模式
result = sample_add(10, 20)
counter = new SampleCounter()
counter.increment()
```
