# AOT编译器使用指南

## 快速开始

### 编译PHP代码

```bash
# 编译PHP文件到原生可执行文件
./zig-out/bin/php-interpreter --compile your_script.php

# 指定输出文件名
./zig-out/bin/php-interpreter --compile --output=myapp your_script.php

# 运行生成的可执行文件
./hello  # 或 ./myapp
```

### 示例

#### 1. Hello World

```php
<?php
$message = "Hello, World!";
echo $message;
```

```bash
$ ./zig-out/bin/php-interpreter --compile hello.php
Success: Compiled to hello

$ ./hello
Hello, World!
```

#### 2. 数学运算

```php
<?php
$a = 10;
$b = 20;
$sum = $a + $b;
$diff = $a - $b;
$prod = $a * $b;
echo $sum;
echo $diff;
echo $prod;
```

```bash
$ ./zig-out/bin/php-interpreter --compile math.php
Success: Compiled to hello

$ ./hello
30-10200
```

#### 3. 字符串操作

```php
<?php
$first = "Hello";
$second = "World";
$greeting = $first . " " . $second;
echo $greeting;
```

```bash
$ ./zig-out/bin/php-interpreter --compile string.php
Success: Compiled to hello

$ ./hello
Hello World
```

---

## 支持的功能

### ✅ 已支持

#### 数据类型
- 整数（int）
- 字符串（string）
- 布尔（bool）
- 浮点数（float）

#### 运算符
- 算术：`+`, `-`, `*`, `/`
- 比较：`==`, `!=`, `<`, `<=`, `>`, `>=`
- 字符串：`.`（拼接）

#### 语句
- 变量赋值：`$x = 10;`
- 函数调用：`echo $x;`

### ❌ 暂不支持

- 控制流（if/else, while, for）
- 数组和对象
- 用户定义函数
- 类和继承
- 异常处理

---

## 编译选项

```bash
# 基本编译
--compile                    编译PHP到原生可执行文件

# 输出选项
--output=<file>             指定输出文件名（默认：hello）

# 优化选项
--optimize=<level>          优化级别：debug, release-safe, 
                           release-fast, release-small
                           （默认：debug）

# 调试选项
--dump-ir                   输出IR中间表示
--dump-ast                  输出AST语法树
--verbose                   详细输出

# 目标平台
--target=<triple>           目标平台（如：x86_64-linux-gnu）
--static                    生成静态链接的可执行文件
```

### 示例

```bash
# 优化编译
./zig-out/bin/php-interpreter --compile --optimize=release-fast app.php

# 查看IR
./zig-out/bin/php-interpreter --compile --dump-ir app.php

# 静态链接
./zig-out/bin/php-interpreter --compile --static app.php
```

---

## 性能优化建议

### 1. 使用基本类型

```php
// 好：直接使用整数
$x = 10;
$y = 20;
$z = $x + $y;

// 避免：不必要的类型转换
$x = "10";
$y = "20";
$z = $x + $y;  // 需要运行时转换
```

### 2. 减少字符串操作

```php
// 好：一次性拼接
$message = "Hello" . " " . "World";

// 避免：多次拼接
$message = "Hello";
$message = $message . " ";
$message = $message . "World";
```

### 3. 避免复杂表达式

```php
// 好：分步计算
$a = $x + $y;
$b = $a * $z;

// 避免：嵌套表达式
$result = ($x + $y) * $z;  // 暂不支持
```

---

## 故障排除

### 编译错误

#### 错误：Unknown option '--aot'
```bash
# 错误
./zig-out/bin/php-interpreter --aot script.php

# 正确
./zig-out/bin/php-interpreter --compile script.php
```

#### 错误：Compilation failed
```bash
# 检查生成的代码
ls -la .zigphp_aot_build/

# 查看详细错误
./zig-out/bin/php-interpreter --compile --verbose script.php
```

### 运行时错误

#### 错误：Segmentation fault
- 检查是否使用了不支持的功能
- 查看生成的代码是否正确
- 报告bug

#### 错误：Memory leak
- 检查是否正确释放了资源
- 使用valgrind检查：`valgrind ./hello`

---

## 测试

### 运行测试套件

```bash
# 运行所有测试
./test_aot_suite.sh

# 添加新测试
# 编辑 test_aot_suite.sh，添加：
test_case "测试名称" "test_file.php" "期望输出"
```

### 创建测试用例

```php
// test_my_feature.php
<?php
$x = 42;
echo $x;
```

```bash
# 测试
./zig-out/bin/php-interpreter --compile test_my_feature.php
./hello
# 应该输出：42
```

---

## 性能基准

### 简单基准测试

```bash
# 编译
./zig-out/bin/php-interpreter --compile --optimize=release-fast benchmark.php

# 测试执行时间
time ./hello

# 比较解释器
time ./zig-out/bin/php-interpreter benchmark.php
```

### 预期性能

- **启动时间**: < 0.01秒
- **执行速度**: 比解释器快100倍以上
- **内存占用**: 比解释器少50%以上

---

## 最佳实践

### 1. 代码组织

```php
<?php
// 变量声明在前
$x = 10;
$y = 20;

// 计算在中
$result = $x + $y;

// 输出在后
echo $result;
```

### 2. 错误处理

```php
<?php
// 检查输入
if ($x > 0) {  // 暂不支持
    echo $x;
}

// 当前：假设输入有效
$x = 10;
echo $x;
```

### 3. 性能考虑

```php
<?php
// 使用局部变量
$temp = $x + $y;
$result = $temp * $z;

// 避免重复计算
$sum = $a + $b;
echo $sum;
echo $sum;  // 重用变量
```

---

## 限制和注意事项

### 当前限制

1. **单基本块**：不支持循环和条件分支
2. **简单表达式**：不支持嵌套表达式
3. **基本类型**：不支持数组和对象
4. **内置函数**：只支持echo和print

### 计划支持

- v1.2：控制流（if/else, while）
- v1.3：数组操作
- v1.4：用户函数
- v2.0：完整PHP支持

---

## 贡献

### 报告问题

1. 创建最小可复现示例
2. 包含PHP代码和错误信息
3. 提供系统信息（OS, Zig版本）

### 提交代码

1. Fork项目
2. 创建功能分支
3. 添加测试
4. 提交PR

---

## 许可证

MIT License

---

## 联系方式

- GitHub: [项目地址]
- 文档: [文档地址]
- 问题: [Issues]

---

**最后更新**: 2026-01-22 19:25  
**版本**: v1.1
