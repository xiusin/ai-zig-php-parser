# 更新日志 - 2026年1月1日

## 测试通过率

**当前进度: 93/94 (98.9%)**

---

## 新功能

### 1. 双变量风格支持 (实验性)

支持两种变量和属性访问风格，用户可以选择使用：

#### PHP 风格 (默认)
```php
<?php
$a = 1;
$obj->property = 2;
$obj->method();
```

#### Go 风格 (实验性)
```php
<?php
a = 1;       // 无需 $ 前缀
obj.property = 2;    // 使用 . 代替 ->
obj.method();
```

**使用方法:**
```bash
# PHP 风格 (默认)
./zig-out/bin/php-interpreter script.php

# Go 风格
./zig-out/bin/php-interpreter --syntax=go script.php
```

**注意:** 不允许在同一个文件中混用两种风格。

---

### 2. Nowdoc/Heredoc 语法修复

现在完整支持 PHP 的 heredoc 和 nowdoc 语法：

```php
<?php
// Nowdoc - 不解析变量
echo <<<'TEXT'
This is a nowdoc string.
$variables are not parsed here.
TEXT;

// Heredoc - 解析变量
$name = "World";
echo <<<HTML
Hello, {$name}!
HTML;
```

---

### 3. 类型转换表达式

支持 PHP 风格的类型转换：

```php
<?php
$arr = ['name' => 'John', 'age' => 30];
$obj = (object)$arr;  // 数组转对象

$str = (string)123;   // 整数转字符串
$int = (int)"42";     // 字符串转整数
$float = (float)"3.14";
$bool = (bool)1;
$arr = (array)$value;
```

---

### 4. 异常处理增强

#### getMessage() 方法
```php
<?php
try {
    throw new Exception("Error message", 500);
} catch (Exception $e) {
    echo $e->getMessage();  // 输出: Error message
    echo $e->getCode();     // 输出: 500
}
```

#### 内置异常类
- `Exception`
- `RuntimeException`
- `TypeError`
- `ArgumentCountError`
- `DivisionByZeroError`
- `ValidationException`

---

### 5. 错误处理函数

```php
<?php
// 设置自定义错误处理器
set_error_handler(function($errno, $errstr) {
    echo "Error: $errstr\n";
});

// 恢复默认错误处理器
restore_error_handler();
```

---

### 6. 除零处理改进

符合 PHP 8 行为，除零返回 `INF` 而不是抛出异常：

```php
<?php
$result = 10 / 0;  // 返回 INF
echo $result;      // 输出: INF
```

---

### 7. !empty() 解析修复

现在正确支持 `!empty()` 等组合表达式：

```php
<?php
$arr = [1, 2, 3];
if (!empty($arr)) {
    echo "Array is not empty";
}
```

---

### 8. require_once/include 基础框架

已添加 require/include 语句的解析和基础框架：

```php
<?php
require_once __DIR__ . '/config.php';
include 'header.php';
```

**注意:** 完整的文件加载功能需要架构调整，目前返回 null。

---

## 命令行参数

| 参数 | 描述 |
|------|------|
| `--syntax=php` | PHP 风格语法 (默认) |
| `--syntax=go` | Go 风格语法 (实验性) |
| `--mode=tree` | 树遍历解释器 (默认) |
| `--mode=bytecode` | 字节码虚拟机 |
| `--compile` | AOT 编译模式 |
| `--help` | 显示帮助信息 |

---

## 已知限制

1. **router.php (1/94 失败)**: 依赖 `require_once` 完整实现
2. **require_once**: 由于 Zig 类型系统限制，递归调用 eval() 存在类型推断问题
3. **Go 风格语法**: 实验性功能，可能存在边界情况

---

## 内存管理

- 使用引用计数 + 循环检测的混合 GC
- 内置类自动内存管理
- 字符串池优化

---

## 下一步计划

1. 完善 require_once 实现（需要架构重构）
2. 完善 Go 风格语法支持
3. 减少内存泄漏
4. 添加更多内置函数

---

## 贡献者

Zig-PHP 解释器开发团队
