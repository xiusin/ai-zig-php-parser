# zig-php 多语法模式详解

## 目录

1. [概述](#概述)
2. [语法模式对比](#语法模式对比)
3. [PHP 模式详解](#php-模式详解)
4. [Go 模式详解](#go-模式详解)
5. [模式选择方式](#模式选择方式)
6. [跨模式互操作](#跨模式互操作)
7. [错误消息](#错误消息)
8. [迁移指南](#迁移指南)
9. [常见问题](#常见问题)

---

## 概述

zig-php 的多语法模式功能允许开发者使用不同的语法风格编写代码。这对于：

- 从其他语言迁移的开发者
- 团队有不同语法偏好
- 需要更简洁语法的场景

### 设计原则

1. **前端处理** - 语法差异在 Lexer/Parser 层处理
2. **运行时无关** - VM 执行相同的 AST
3. **完全兼容** - 不同模式的代码可以互相调用

---

## 语法模式对比

### 完整对比表

| 特性 | PHP 模式 | Go 模式 |
|------|----------|---------|
| 变量声明 | `$name = "value"` | `name = "value"` |
| 变量引用 | `$name` | `name` |
| 属性访问 | `$obj->property` | `obj.property` |
| 方法调用 | `$obj->method()` | `obj.method()` |
| 静态访问 | `Class::method()` | `Class::method()` |
| 字符串拼接 | `$a . $b` | `a + b` |
| 数组访问 | `$arr[0]` | `arr[0]` |
| this 引用 | `$this->prop` | `this.prop` |
| 类属性声明 | `public $name` | `public name` |

### 相同的语法

以下语法在两种模式中完全相同：

- 关键字：`function`, `class`, `if`, `while`, `for`, `foreach`, `return` 等
- 运算符：`+`, `-`, `*`, `/`, `%`, `==`, `===`, `&&`, `||` 等
- 控制结构语法
- 函数定义语法
- 类定义语法（除属性声明外）
- 静态方法/属性访问

---

## PHP 模式详解

PHP 模式是默认模式，完全兼容标准 PHP 语法。

### 变量

```php
<?php
// 变量必须以 $ 开头
$name = "Alice";
$age = 30;
$isActive = true;

// 变量引用
echo $name;
echo "Hello, $name!";
echo "Age: {$age}";
```

### 属性和方法

```php
<?php
class Person {
    public $name;      // 属性需要 $
    private $age;
    
    public function __construct($name, $age) {
        $this->name = $name;   // 使用 ->
        $this->age = $age;
    }
    
    public function greet() {
        return "Hello, " . $this->name;  // 字符串拼接用 .
    }
}

$person = new Person("Bob", 25);
echo $person->name;           // 属性访问用 ->
echo $person->greet();        // 方法调用用 ->
```

### 字符串操作

```php
<?php
$first = "Hello";
$second = "World";

// 字符串拼接使用 .
$greeting = $first . ", " . $second . "!";

// 字符串插值
$name = "Alice";
echo "Hello, $name!";
echo "Hello, {$name}!";
```

---

## Go 模式详解

Go 模式提供更简洁的语法，类似 Go/JavaScript 风格。

### 变量

```php
// @syntax: go
<?php
// 变量不需要 $ 前缀
name = "Alice"
age = 30
isActive = true

// 变量引用
echo name
echo "Hello, " + name + "!"
```

### 属性和方法

```php
// @syntax: go
<?php
class Person {
    public name      // 属性不需要 $
    private age
    
    function __construct(name, age) {
        this.name = name   // 使用 .
        this.age = age
    }
    
    function greet() {
        return "Hello, " + this.name  // 字符串拼接用 +
    }
}

person = new Person("Bob", 25)
echo person.name           // 属性访问用 .
echo person.greet()        // 方法调用用 .
```

### 字符串操作

```php
// @syntax: go
<?php
first = "Hello"
second = "World"

// 字符串拼接使用 +
greeting = first + ", " + second + "!"

// 注意：Go 模式不支持字符串插值
// 使用拼接代替
name = "Alice"
echo "Hello, " + name + "!"
```

### 数组和循环

```php
// @syntax: go
<?php
// 数组语法相同
numbers = [1, 2, 3, 4, 5]
person = ["name" => "Alice", "age" => 30]

// 循环语法相同
foreach (numbers as num) {
    echo num + " "
}

foreach (person as key => value) {
    echo key + ": " + value + "\n"
}
```

### 静态成员

```php
// @syntax: go
<?php
class Counter {
    private static count = 0
    
    static function increment() {
        Counter::count = Counter::count + 1  // 静态访问仍用 ::
    }
    
    static function getCount() {
        return Counter::count
    }
}

Counter::increment()
echo Counter::getCount()
```

---

## 模式选择方式

### 优先级（从高到低）

1. 命令行参数 `--syntax=`
2. 文件指令 `// @syntax:`
3. 配置文件 `syntax` 字段
4. 默认值（PHP 模式）

### 命令行参数

```bash
# 强制使用 Go 模式
./zig-out/bin/php-interpreter --syntax=go script.php

# 强制使用 PHP 模式
./zig-out/bin/php-interpreter --syntax=php script.php
```

### 文件指令

在文件开头添加指令：

```php
// @syntax: go
<?php
// 文件内容使用 Go 模式
```

或者：

```php
<?php // @syntax: go
// 文件内容使用 Go 模式
```

### 配置文件

`.zigphp.json`：

```json
{
    "syntax": "go"
}
```

---

## 跨模式互操作

不同语法模式的文件可以相互调用。

### 示例：PHP 库 + Go 主程序

`lib/utils.php`（PHP 模式）：

```php
<?php
function formatName($first, $last) {
    return $first . " " . $last;
}

class Calculator {
    public function add($a, $b) {
        return $a + $b;
    }
}
```

`main.php`（Go 模式）：

```php
// @syntax: go
<?php
include 'lib/utils.php'

// 调用 PHP 模式的函数
fullName = formatName("John", "Doe")
echo "Name: " + fullName + "\n"

// 使用 PHP 模式的类
calc = new Calculator()
result = calc.add(10, 20)  // Go 模式语法调用
echo "Result: " + result + "\n"
```

### 内部机制

1. 解析器为每个文件检测语法模式
2. 变量名在内部统一添加 `$` 前缀
3. AST 结构完全相同
4. VM 执行时无语法模式概念

---

## 错误消息

错误消息会根据源文件的语法模式格式化。

### PHP 模式错误

```
Error: Undefined variable $name at line 10
Error: Cannot access property $obj->property
```

### Go 模式错误

```
Error: Undefined variable name at line 10
Error: Cannot access property obj.property
```

### 配置错误显示模式

```zig
const config = SyntaxConfig{
    .mode = .go,
    .error_display_mode = .go,  // 错误消息使用 Go 风格
};
```

---

## 迁移指南

### 从 PHP 迁移到 Go 模式

1. 添加文件指令：`// @syntax: go`
2. 移除变量的 `$` 前缀
3. 将 `->` 替换为 `.`
4. 将字符串拼接的 `.` 替换为 `+`
5. 移除类属性声明中的 `$`

### 示例迁移

PHP 模式：

```php
<?php
$name = "Alice";
$person = new Person($name);
echo $person->getName() . " is " . $person->getAge();
```

Go 模式：

```php
// @syntax: go
<?php
name = "Alice"
person = new Person(name)
echo person.getName() + " is " + person.getAge()
```

### 自动迁移工具

目前没有自动迁移工具，建议手动迁移并测试。

---

## 常见问题

### Q: Go 模式下可以使用 $ 吗？

不可以。Go 模式下 `$` 会被视为语法错误。

### Q: 两种模式的性能有差异吗？

没有。语法差异只在解析阶段处理，运行时完全相同。

### Q: 可以在同一文件中混合两种语法吗？

不可以。每个文件只能使用一种语法模式。但不同文件可以使用不同模式。

### Q: Go 模式支持字符串插值吗？

不支持。请使用 `+` 拼接：

```php
// @syntax: go
name = "Alice"
// 不支持: echo "Hello, $name!"
// 使用: 
echo "Hello, " + name + "!"
```

### Q: 静态方法调用语法相同吗？

是的。两种模式都使用 `::`：

```php
// PHP 模式
$result = Math::add(1, 2);

// Go 模式
result = Math::add(1, 2)
```

### Q: 如何在 IDE 中获得语法高亮？

目前建议：
- PHP 模式：使用 PHP 语法高亮
- Go 模式：使用 PHP 语法高亮（大部分关键字相同）
