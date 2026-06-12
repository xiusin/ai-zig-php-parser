# 类常量支持实现进度报告

日期：2026-02-09 22:40 - 23:40

## 目标

实现 PHP 类常量支持，允许在类中定义常量并通过 `ClassName::CONST_NAME` 访问。

## 已完成的工作

### 1. 分析现有实现
- ✅ Parser 已经支持类常量解析（`parseConst`）
- ✅ AST 已经有 `const_decl` 节点
- ✅ IR 生成器已经有 `generateClassConstDecl` 函数
- ✅ 运行时库已经有静态属性支持（`php_get/set_static_property`）

### 2. 实现类常量作为静态属性
**设计决策**：将类常量实现为只读的静态属性

**修改的文件**：
1. `src/aot/ir_generator.zig`
   - 修改 `generateClassConstDecl`：生成特殊的 call 指令
   - 修改 `generateClassConstantAccess`：调用 `php_get_static_property_value`

2. `src/aot/runtime_lib_template.zig`
   - 添加 `php_get_static_property_value`：接受 Value 参数
   - 添加 `php_set_static_property_value`：接受 Value 参数

3. `src/aot/native_linker.zig`
   - 添加特殊处理：识别 `__set_class_const_value_` 前缀的函数调用
   - 生成直接调用 `php_set_static_property` 的代码

### 3. 测试
创建了 `tests/aot/test_class_constants.php`：
```php
class Config {
    public const VERSION = "1.0.0";
    public const MAX_SIZE = 1024;
    public const DEBUG = true;
    
    private const SECRET = "secret_key";
}

echo Config::VERSION;  // 访问类常量
```

## 遇到的问题

### 问题 1：类常量设置时机
**现象**：运行时报错 `error: ClassNotFound`

**根本原因**：
- 类常量在类声明时被处理（`generateClassConstDecl`）
- 但是生成的设置代码没有被添加到任何函数中
- 类常量需要在类注册之后才能设置

**当前状态**：
- 类常量访问代码生成正确（调用 `php_get_static_property_value`）
- 类常量设置代码没有生成到输出中

### 问题 2：架构限制
**核心问题**：类声明不生成可执行代码

在当前的 AOT 编译器架构中：
1. 类声明只生成元数据（TypeDef）
2. 类成员（方法、属性）的处理不生成到 `__main__` 函数
3. 类常量需要在运行时设置，但没有合适的位置放置设置代码

**可能的解决方案**：

#### 方案 A：在类注册时设置常量（推荐）
修改 `native_linker.zig` 中的类注册代码生成：
```zig
// 在 registerClass 之后
try writer.print("    try runtime.registerClass({s}_meta);\n", .{cname});

// 添加：设置类常量
for (class_constants) |const_info| {
    try writer.print("    _ = try runtime.php_set_static_property(\"{s}\", \"{s}\", {value});\n",
        .{ class_name, const_name, const_value });
}
```

**优点**：
- 类常量在类注册后立即可用
- 不需要修改 IR 生成器的架构
- 代码生成简单直接

**缺点**：
- 需要在 native_linker 中跟踪类常量信息
- 需要从 IR 模块中提取类常量数据

#### 方案 B：生成类初始化函数
为每个类生成一个初始化函数：
```zig
fn __init_Config_constants() void {
    _ = runtime.php_set_static_property("Config", "VERSION", ...);
    _ = runtime.php_set_static_property("Config", "MAX_SIZE", ...);
}
```

在 `__main__` 开始处调用所有初始化函数。

**优点**：
- 清晰的代码结构
- 易于调试

**缺点**：
- 需要生成额外的函数
- 需要跟踪所有类的初始化函数

#### 方案 C：在 IR 中添加类初始化块
修改 IR 生成器，为每个类添加一个初始化块，在 `__main__` 开始处执行。

**优点**：
- 架构清晰
- 符合编译器设计原则

**缺点**：
- 需要较大的架构改动
- 实现复杂度高

## 推荐方案

**方案 A：在类注册时设置常量**

### 实现步骤

1. **在 IR 模块中添加类常量信息**
   - 修改 `TypeDef` 结构，添加 `constants` 字段
   - 在 `generateClassConstDecl` 中将常量信息保存到 TypeDef

2. **在 native_linker 中生成设置代码**
   - 在类注册后，遍历类的常量
   - 为每个常量生成 `php_set_static_property` 调用

3. **处理常量值**
   - 常量值需要在编译时求值
   - 支持基本类型（int, float, string, bool）

### 预计工作量
- 修改 IR 生成器：30 分钟
- 修改 native_linker：30 分钟
- 测试和调试：30 分钟
- **总计**：约 1.5 小时

## 当前状态

- ✅ 基础架构已就绪
- ✅ 运行时支持已完成
- ⚠️ 类常量设置代码生成未完成
- ❌ 测试未通过

## 下一步

由于时间限制，建议：
1. 先处理其他已知问题（优先级更高）
2. 将类常量支持作为后续优化项
3. 当前可以使用静态属性作为替代方案

## 替代方案

在类常量完全实现之前，用户可以使用静态属性：
```php
class Config {
    public static string $VERSION = "1.0.0";
    public static int $MAX_SIZE = 1024;
}

echo Config::$VERSION;  // 使用静态属性
```

## 总结

类常量的实现需要解决类声明和运行时初始化的时机问题。推荐使用方案 A（在类注册时设置常量），预计需要 1.5 小时完成。当前可以使用静态属性作为替代方案。
