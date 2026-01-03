# zig-php 用户指南

## 目录

1. [简介](#简介)
2. [安装](#安装)
3. [快速开始](#快速开始)
4. [命令行选项](#命令行选项)
5. [多语法模式](#多语法模式)
6. [配置文件](#配置文件)
7. [扩展系统](#扩展系统)
8. [AOT 编译](#aot-编译)
9. [常见问题](#常见问题)

---

## 简介

zig-php 是一个用 Zig 语言实现的 PHP 8.5 兼容解释器。它提供了以下核心特性：

- **完整的 PHP 8.5 语法支持** - 包括类、接口、trait、闭包、箭头函数等
- **多语法模式** - 支持 PHP 风格和 Go 风格语法
- **第三方扩展系统** - 允许动态加载扩展模块
- **AOT 编译** - 将 PHP 代码编译为原生可执行文件
- **高性能运行时** - 支持树遍历和字节码两种执行模式

---

## 安装

### 系统要求

- Zig 0.15.2 或更高版本
- libc（用于系统集成）
- macOS、Linux 或 Windows 操作系统

### 从源码构建

```bash
# 克隆仓库
git clone <repository-url>
cd zig-php

# 构建项目
zig build

# 编译后的解释器位于
./zig-out/bin/php-interpreter
```

### 验证安装

```bash
# 查看版本信息
./zig-out/bin/php-interpreter --version

# 运行测试脚本
./zig-out/bin/php-interpreter examples/hello.php
```

---

## 快速开始

### 运行 PHP 脚本

```bash
# 基本用法
./zig-out/bin/php-interpreter script.php

# 带参数运行
./zig-out/bin/php-interpreter script.php arg1 arg2
```

### 示例：Hello World

创建文件 `hello.php`：

```php
<?php
echo "Hello, World!\n";

$name = "zig-php";
echo "Welcome to {$name}!\n";
```

运行：

```bash
./zig-out/bin/php-interpreter hello.php
```

输出：

```
Hello, World!
Welcome to zig-php!
```

---

## 命令行选项

| 选项 | 说明 |
|------|------|
| `--help`, `-h` | 显示帮助信息 |
| `--version`, `-v` | 显示版本信息 |
| `--mode=<mode>` | 执行模式：tree, bytecode, auto（默认：tree）|
| `--syntax=<syntax>` | 语法模式：php, go（默认：php）|
| `--config=<file>` | 指定配置文件路径 |
| `--extension=<path>` | 加载扩展模块 |
| `--compile` | 启用 AOT 编译模式 |

### 执行模式说明

- **tree** - 树遍历解释器，兼容性最好（默认）
- **bytecode** - 字节码虚拟机，性能更高
- **auto** - 根据代码特征自动选择

```bash
# 使用字节码模式运行
./zig-out/bin/php-interpreter --mode=bytecode app.php
```

---

## 多语法模式

zig-php 支持多种语法风格，让你可以用熟悉的方式编写代码。

### 语法模式对比

| 特性 | PHP 模式 | Go 模式 |
|------|----------|---------|
| 变量声明 | `$name` | `name` |
| 属性访问 | `$obj->prop` | `obj.prop` |
| 方法调用 | `$obj->method()` | `obj.method()` |
| 字符串拼接 | `$a . $b` | `a + b` |

### 选择语法模式

#### 方式一：命令行参数

```bash
# 使用 Go 语法模式
./zig-out/bin/php-interpreter --syntax=go script.php

# 使用 PHP 语法模式（默认）
./zig-out/bin/php-interpreter --syntax=php script.php
```

#### 方式二：文件指令

在文件开头添加语法指令：

```php
// @syntax: go
<?php
// 使用 Go 风格语法
name = "World"
echo "Hello, " + name + "\n"
```

或者：

```php
<?php // @syntax: go
// 使用 Go 风格语法
```

#### 方式三：配置文件

在项目根目录创建 `.zigphp.json`：

```json
{
    "syntax": "go"
}
```

### Go 模式示例

```php
// @syntax: go
<?php

// 变量声明（无需 $ 前缀）
name = "Alice"
age = 30

// 字符串拼接（使用 + 而非 .）
greeting = "Hello, " + name + "!"
echo greeting + "\n"

// 类定义和属性访问
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

// 创建实例并访问属性
person = new Person("Bob", 25)
echo person.getInfo() + "\n"
echo "Age: " + person.age + "\n"
```

### 跨模式文件包含

不同语法模式的文件可以相互包含：

```php
// lib.php (PHP 模式)
<?php
function greet($name) {
    return "Hello, " . $name;
}
```

```php
// @syntax: go
// main.php (Go 模式)
<?php
include 'lib.php';

name = "World"
result = greet(name)  // 调用 PHP 模式的函数
echo result + "\n"
```

---

## 配置文件

### 配置文件位置

解释器按以下顺序查找配置文件：

1. `.zigphp.json`（当前目录）
2. `zigphp.config.json`（当前目录）

### 配置选项

```json
{
    "syntax": "php",
    "extensions": [
        "./extensions/mysql.so",
        "./extensions/redis.so"
    ],
    "include_paths": [
        "./lib",
        "./vendor"
    ],
    "error_reporting": 32767
}
```

| 选项 | 类型 | 说明 |
|------|------|------|
| `syntax` | string | 默认语法模式："php" 或 "go" |
| `extensions` | array | 自动加载的扩展路径列表 |
| `include_paths` | array | include/require 的搜索路径 |
| `error_reporting` | number | 错误报告级别 |

### 配置优先级

命令行参数始终优先于配置文件：

```bash
# 即使配置文件指定 PHP 模式，这里也会使用 Go 模式
./zig-out/bin/php-interpreter --syntax=go script.php
```

---

## 扩展系统

### 加载扩展

```bash
# 加载单个扩展
./zig-out/bin/php-interpreter --extension=./myext.so script.php

# 加载多个扩展
./zig-out/bin/php-interpreter --extension=./ext1.so --extension=./ext2.so script.php
```

或通过配置文件：

```json
{
    "extensions": [
        "./extensions/mysql.so",
        "./extensions/redis.so"
    ]
}
```

### 使用扩展功能

扩展加载后，其提供的函数和类可直接使用：

```php
<?php
// 假设加载了 sample_extension
$result = sample_add(5, 3);  // 调用扩展函数
echo $result;  // 输出: 8

$counter = new SampleCounter();  // 使用扩展类
$counter->increment();
echo $counter->getValue();
```

---

## AOT 编译

AOT（Ahead-of-Time）编译器可将 PHP 代码编译为原生可执行文件。

### 基本编译

```bash
# 编译 PHP 文件
./zig-out/bin/php-interpreter --compile hello.php

# 指定输出文件名
./zig-out/bin/php-interpreter --compile --output=myapp hello.php

# 启用优化
./zig-out/bin/php-interpreter --compile --optimize=release-fast app.php

# 生成静态链接的可执行文件
./zig-out/bin/php-interpreter --compile --static app.php
```

### AOT 编译选项

| 选项 | 说明 |
|------|------|
| `--compile` | 启用 AOT 编译模式 |
| `--output=<file>` | 输出文件名（默认：输入文件名去掉 .php）|
| `--target=<triple>` | 目标平台（如 x86_64-linux-gnu）|
| `--optimize=<level>` | 优化级别：debug, release-safe, release-fast, release-small |
| `--static` | 生成完全静态链接的可执行文件 |
| `--dump-ir` | 输出生成的 IR（用于调试）|
| `--dump-ast` | 输出解析的 AST（用于调试）|
| `--verbose` | 详细输出编译过程 |
| `--list-targets` | 列出所有支持的目标平台 |

### 支持的目标平台

- **Linux**: x86_64-linux-gnu, x86_64-linux-musl, aarch64-linux-gnu
- **macOS**: x86_64-macos-none, aarch64-macos-none
- **Windows**: x86_64-windows-msvc, x86_64-windows-gnu

### 交叉编译

```bash
# 在 macOS 上编译 Linux 可执行文件
./zig-out/bin/php-interpreter --compile --target=x86_64-linux-gnu app.php
```

---

## 常见问题

### Q: 如何查看支持的语法模式？

```bash
./zig-out/bin/php-interpreter --help
```

### Q: Go 模式下可以使用 $ 符号吗？

不可以。Go 模式下 `$` 符号会被视为语法错误。如果需要使用 PHP 风格的变量，请切换到 PHP 模式。

### Q: 扩展加载失败怎么办？

1. 检查扩展文件路径是否正确
2. 确认扩展是为当前平台编译的
3. 检查扩展的 API 版本是否兼容

### Q: 如何调试 AOT 编译问题？

使用 `--dump-ast` 和 `--dump-ir` 选项查看中间表示：

```bash
./zig-out/bin/php-interpreter --compile --dump-ast --dump-ir app.php
```

---

## 更多资源

- [技术文档](TECHNICAL_REFERENCE.md) - 详细的技术参考
- [扩展开发指南](EXTENSION_DEVELOPMENT.md) - 如何开发扩展
- [多语法模式详解](MULTI_SYNTAX_GUIDE.md) - 语法模式深入指南
