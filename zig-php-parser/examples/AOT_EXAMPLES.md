# AOT 编译示例

本目录包含可用于 AOT（Ahead-of-Time）编译的 PHP 示例程序。

## 快速开始

### 1. 构建解释器

```bash
cd zig-php
zig build
```

### 2. 编译示例程序

```bash
# 编译 Hello World 示例
./zig-out/bin/php-interpreter --compile examples/aot_hello.php

# 运行编译后的程序
./aot_hello
```

## 示例文件

| 文件 | 说明 | 演示特性 |
|------|------|----------|
| `aot_hello.php` | Hello World | 基本输出、变量、字符串 |
| `aot_functions.php` | 函数示例 | 函数定义、递归、默认参数 |
| `aot_arrays.php` | 数组操作 | 索引数组、关联数组、foreach |
| `aot_strings.php` | 字符串操作 | 连接、插值、内置函数 |
| `aot_classes.php` | 面向对象 | 类、继承、方法 |
| `aot_control_flow.php` | 控制流 | if/else、循环、break/continue |

## 编译选项示例

### 基本编译

```bash
# 默认编译（debug 模式）
./zig-out/bin/php-interpreter --compile examples/aot_hello.php

# 指定输出文件名
./zig-out/bin/php-interpreter --compile --output=hello examples/aot_hello.php
```

### 优化编译

```bash
# 最大性能优化
./zig-out/bin/php-interpreter --compile --optimize=release-fast examples/aot_functions.php

# 最小体积优化
./zig-out/bin/php-interpreter --compile --optimize=release-small examples/aot_hello.php

# 带安全检查的优化
./zig-out/bin/php-interpreter --compile --optimize=release-safe examples/aot_arrays.php
```

### 静态链接

```bash
# 生成完全静态链接的可执行文件
./zig-out/bin/php-interpreter --compile --static examples/aot_hello.php
```

### 交叉编译

```bash
# 为 Linux x86_64 编译
./zig-out/bin/php-interpreter --compile --target=x86_64-linux-gnu examples/aot_hello.php

# 为 Linux ARM64 编译
./zig-out/bin/php-interpreter --compile --target=aarch64-linux-gnu examples/aot_hello.php

# 为 macOS ARM64 编译
./zig-out/bin/php-interpreter --compile --target=aarch64-macos-none examples/aot_hello.php
```

### 调试选项

```bash
# 查看生成的 AST
./zig-out/bin/php-interpreter --compile --dump-ast examples/aot_hello.php

# 查看生成的 IR
./zig-out/bin/php-interpreter --compile --dump-ir examples/aot_hello.php

# 查看生成的 Zig 代码
./zig-out/bin/php-interpreter --compile --dump-zig examples/aot_hello.php

# 详细输出
./zig-out/bin/php-interpreter --compile --verbose examples/aot_hello.php
```

## 完整编译流程示例

### 开发阶段

```bash
# 快速编译，便于调试
./zig-out/bin/php-interpreter --compile --optimize=debug --verbose examples/aot_functions.php
./aot_functions
```

### 测试阶段

```bash
# 优化编译，保留安全检查
./zig-out/bin/php-interpreter --compile --optimize=release-safe examples/aot_functions.php
./aot_functions
```

### 生产部署

```bash
# 最大性能优化，静态链接
./zig-out/bin/php-interpreter --compile --optimize=release-fast --static --output=myapp examples/aot_functions.php
./myapp
```

## 支持的 PHP 特性

AOT 编译器目前支持以下 PHP 特性：

### 数据类型
- `null`
- `bool` (true/false)
- `int` (整数)
- `float` (浮点数)
- `string` (字符串)
- `array` (数组)

### 运算符
- 算术运算符: `+`, `-`, `*`, `/`, `%`
- 比较运算符: `==`, `!=`, `<`, `>`, `<=`, `>=`
- 逻辑运算符: `&&`, `||`, `!`
- 字符串连接: `.`
- 赋值运算符: `=`, `+=`, `-=`, etc.

### 控制结构
- `if` / `else` / `elseif`
- `while` 循环
- `for` 循环
- `foreach` 循环
- `break` / `continue`

### 函数
- 用户定义函数
- 递归函数
- 默认参数值
- 类型声明（部分支持）

### 内置函数
- `echo`, `print`
- `strlen`, `substr`, `strpos`
- `strtoupper`, `strtolower`
- `str_replace`
- `count`
- `var_dump`, `print_r`
- `sqrt`, `abs`, `pow`

## 注意事项

1. **变量支持**: 当前 AOT 编译器对变量的支持是实验性的，复杂的变量操作可能不完全支持
2. **类支持**: 类和对象的支持是实验性的，复杂的 OOP 特性可能不完全支持
3. **命名空间**: 暂不支持命名空间
4. **异常处理**: try/catch 暂不支持
5. **动态特性**: `eval()`, 可变变量等动态特性不支持

## 已知限制

当前 AOT 编译器处于开发阶段，以下功能可能存在限制：

- 变量赋值和读取（部分支持）
- 字符串插值（部分支持）
- 复杂的控制流结构
- 类和对象操作

建议先使用解释器模式验证程序正确性，然后再尝试 AOT 编译。

## 故障排除

### 编译错误

如果遇到编译错误，使用 `--verbose` 选项获取详细信息：

```bash
./zig-out/bin/php-interpreter --compile --verbose your_file.php
```

### 查看中间表示

使用调试选项查看编译过程中的中间表示：

```bash
# 查看 AST
./zig-out/bin/php-interpreter --compile --dump-ast your_file.php

# 查看 IR
./zig-out/bin/php-interpreter --compile --dump-ir your_file.php

# 查看生成的 Zig 代码
./zig-out/bin/php-interpreter --compile --dump-zig your_file.php
```

## 更多信息

- [用户指南](../docs/USER_GUIDE.md) - 完整的使用说明
- [技术参考](../docs/TECHNICAL_REFERENCE.md) - 技术细节
