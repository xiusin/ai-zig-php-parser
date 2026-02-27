# AOT 编译器模糊测试指南

## 项目概述

这是一个用 Zig 实现的 PHP 8.5 解释器，包含 AOT（Ahead-of-Time）编译器，可以将 PHP 代码编译为原生可执行文件。

**当前状态**: AOT 编译器已完成核心功能开发，正在进行全面测试和问题修复阶段。

## 测试目标

通过随机生成各种 PHP 代码片段，发现 AOT 编译器的边界情况和潜在问题，确保编译器的稳定性和正确性。

## 环境准备

### 1. 编译项目

```bash
cd /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser
rm -rf .zig-cache zig-out
zig build
```

### 2. 验证环境

```bash
# 测试解释器
./zig-out/bin/php-interpreter --version

# 测试 AOT 编译
cat > /tmp/hello.php << 'EOF'
<?php
echo "Hello, World!\n";
?>
EOF

./zig-out/bin/php-interpreter --compile --output=/tmp/hello_aot /tmp/hello.php
/tmp/hello_aot
```

## 测试方法

### 基本测试流程

1. **创建测试文件** (`/tmp/testN.php`)
2. **运行 PHP 标准解释器** 获取期望输出
3. **运行 AOT 编译** 生成可执行文件
4. **运行 AOT 可执行文件** 获取实际输出
5. **对比输出** 验证正确性

### 测试模板

```bash
cat > /tmp/testN.php << 'EOF'
<?php
// 你的测试代码
?>
EOF

# 获取 PHP 标准输出
php /tmp/testN.php > /tmp/php_output.txt

# AOT 编译并运行
cd /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser
rm -rf .zigphp_aot_build
./zig-out/bin/php-interpreter --compile --output=/tmp/testN_aot /tmp/testN.php > /dev/null 2>&1
/tmp/testN_aot > /tmp/aot_output.txt

# 对比输出
diff /tmp/php_output.txt /tmp/aot_output.txt
```

### 简化的单行测试

```bash
php /tmp/testN.php && echo "---" && \
cd /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser && \
rm -rf .zigphp_aot_build && \
./zig-out/bin/php-interpreter --compile --output=/tmp/testN_aot /tmp/testN.php > /dev/null 2>&1 && \
/tmp/testN_aot
```

## 已测试的功能（76 个测试，75 通过）

### ✅ 已验证正常的功能

1. **基础语法**
   - 变量赋值和输出
   - 字符串插值
   - 注释

2. **数据类型**
   - 整数、浮点数、字符串、布尔值、null
   - 类型转换（字符串 + 数字）
   - 假值测试（空字符串、0、null）

3. **运算符**
   - 算术运算符：`+`, `-`, `*`, `/`, `%`
   - 比较运算符：`>`, `<`, `>=`, `<=`, `==`, `!=`
   - 逻辑运算符：`&&`, `||`, `!`（包括短路求值）
   - 位运算符：`&`, `|`, `^`, `~`
   - 复合赋值：`+=`, `-=`, `*=`, `.=`
   - 递增递减：`++`, `--`（前缀和后缀）

4. **控制流**
   - `if-else`（包括多层嵌套）
   - `for` 循环（包括嵌套）
   - `while` 循环
   - `do-while` 循环
   - `switch-case`（包括 fallthrough）
   - `break` 和 `continue`
   - 三元运算符（包括嵌套）

5. **函数**
   - 函数定义和调用
   - 参数传递
   - 返回值
   - 默认参数
   - 递归函数（factorial, fibonacci）
   - 嵌套函数调用
   - 多个 return 语句

6. **数组**
   - 数组字面量：`[1, 2, 3]`
   - 数组访问：`$arr[0]`
   - 数组修改：`$arr[0] = 10`
   - 数组 push：`$arr[] = value`
   - 多维数组（2D, 3D, 4D, 5D）
   - 关联数组（字符串键）
   - 混合类型数组
   - 数组元素复合赋值：`$arr[0] += 5`
   - 大数组（100+ 元素）

7. **全局变量**
   - `global` 声明
   - 全局变量读写
   - 全局变量递增递减
   - 全局变量复合赋值
   - 多个全局变量
   - 嵌套函数中的全局变量
   - 循环中访问全局数组

8. **字符串**
   - 字符串连接：`.`
   - 字符串索引访问：`$str[0]`
   - 字符串和数字混合运算

### ⚠️ 已知限制

1. **数组按值传递** (test68)
   - **问题**: PHP 中数组是按值传递的（写时复制），但当前实现是按引用传递
   - **影响**: 函数内修改数组会影响外部数组
   - **原因**: 需要实现完整的写时复制（COW）机制
   - **优先级**: P2（不影响大多数场景）

## 测试建议

### 重点测试领域

1. **边界情况**
   - 空数组、空字符串
   - 负数、零
   - 大数值
   - 深层嵌套（循环、数组、函数调用）

2. **组合场景**
   - 全局变量 + 循环 + 数组
   - 递归 + 数组操作
   - 复杂表达式（多个运算符）
   - 嵌套控制流

3. **错误处理**
   - 除以零
   - 数组越界
   - 未定义变量

### 测试用例生成策略

#### 1. 简单功能测试

```php
<?php
// 测试单个功能
$x = 10;
echo $x + 5;
?>
```

#### 2. 组合功能测试

```php
<?php
// 测试多个功能组合
$arr = [1, 2, 3];
for ($i = 0; $i < 3; $i++) {
    $arr[$i] *= 2;
}
echo $arr[0] + $arr[1] + $arr[2];
?>
```

#### 3. 边界测试

```php
<?php
// 测试边界情况
$x = 0;
$y = -1;
$z = 999999;
echo $x && $y || $z;
?>
```

#### 4. 压力测试

```php
<?php
// 测试大量数据
$arr = [];
for ($i = 0; $i < 1000; $i++) {
    $arr[] = $i;
}
echo $arr[500];
?>
```

## 问题报告格式

当发现问题时，请按以下格式报告：

```markdown
### 测试 N: [简短描述]

**测试代码**:
```php
<?php
// 代码
?>
```

**PHP 输出**:
```
期望输出
```

**AOT 输出**:
```
实际输出
```

**问题描述**:
- 现象：[描述差异]
- 错误信息：[如果有编译错误]
- 影响范围：[哪些场景会受影响]
```

## 调试技巧

### 1. 查看 IR（中间表示）

```bash
./zig-out/bin/php-interpreter --compile --dump-ir /tmp/test.php 2>&1 | grep -A 20 "=== IR Dump ==="
```

### 2. 查看生成的 Zig 代码

```bash
cat .zigphp_aot_build/main.zig
```

### 3. 查看编译错误

```bash
./zig-out/bin/php-interpreter --compile --output=/tmp/test_aot /tmp/test.php 2>&1 | grep "error:"
```

### 4. 控制测试时长

**重要**: AOT 编译可能存在死循环或长时间运行的情况，建议使用超时控制：

```bash
# macOS
gtimeout 10 ./zig-out/bin/php-interpreter --compile --output=/tmp/test_aot /tmp/test.php

# Linux
timeout 10 ./zig-out/bin/php-interpreter --compile --output=/tmp/test_aot /tmp/test.php
```

## 最近修复的问题（参考）

1. **全局变量在后缀/前缀表达式中不工作** (Commit: ff74c38)
   - 问题：`$counter++` 不会写回全局变量
   - 修复：在 `generatePostfixExpr` 和 `generateUnaryExpr` 中添加全局变量检查

2. **复合赋值运算符不工作** (Commit: 5cea952)
   - 问题：`$x += 5` 不会写回全局变量
   - 修复：在 `generateCompoundAssignment` 中添加全局变量支持

3. **not 指令类型不匹配** (Commit: d36152b)
   - 问题：复杂布尔表达式中的 `!` 运算符导致编译错误
   - 修复：简化 `not` 指令生成，总是返回 `runtime.Value`

4. **全局变量引用计数问题** (Commit: d72dd3f)
   - 问题：循环中访问全局数组导致段错误
   - 修复：`getGlobalVar` 返回时调用 `retain()` 增加引用计数

5. **位运算指令代码生成错误** (Commit: bbea37b)
   - 问题：位运算符（`&`, `|`, `^`）导致编译错误
   - 修复：转换为整数后进行位运算

6. **bit_not (~) 运算符不工作** (Commit: e0da5ad)
   - 问题：`~` 运算符导致整个语句被跳过
   - 修复：在解析器、VM 和 AOT 代码生成器中添加 `tilde` 支持

## 测试进度跟踪

当前测试数：**76**  
通过测试：**75** ✅  
已知限制：**1** ⚠️  
成功率：**98.7%**

## 下一步测试方向

1. **类和对象**（如果支持）
2. **异常处理**（try-catch）
3. **命名空间**
4. **闭包和匿名函数**
5. **引用传递**（`&$var`）
6. **可变参数**（`...$args`）
7. **类型声明**（如果支持）
8. **内置函数**（`strlen`, `array_push`, 等）

## 联系方式

如有问题或发现 bug，请：
1. 记录详细的测试用例
2. 保存 PHP 和 AOT 的输出对比
3. 提供 IR dump（如果可能）
4. 提交 issue 或 commit

---

**祝测试顺利！** 🚀
