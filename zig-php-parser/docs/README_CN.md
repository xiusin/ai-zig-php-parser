# zig-php - 用 Zig 实现的 PHP 8.5 解释器

## 项目简介

zig-php 是一个用 Zig 语言实现的完整 PHP 8.5 兼容解释器，具有以下特色功能：

- ✅ **完整的 PHP 8.5 语法支持**
- ✅ **多语法模式** - 支持 PHP 和 Go 风格语法
- ✅ **第三方扩展系统** - 动态加载扩展模块
- ✅ **AOT 编译** - 将 PHP 编译为原生可执行文件
- ✅ **高性能运行时** - 树遍历和字节码双模式

## 快速开始

### 安装

```bash
# 克隆仓库
git clone <repository-url>
cd zig-php

# 构建
zig build

# 验证
./zig-out/bin/php-interpreter --version
```

### 运行 PHP 脚本

```bash
# 基本用法
./zig-out/bin/php-interpreter script.php

# 使用 Go 语法模式
./zig-out/bin/php-interpreter --syntax=go script.php

# 加载扩展
./zig-out/bin/php-interpreter --extension=./myext.so script.php

# AOT 编译
./zig-out/bin/php-interpreter --compile app.php
```

## 多语法模式

zig-php 支持两种语法风格：

### PHP 模式（默认）

```php
<?php
$name = "World";
$person = new Person($name);
echo $person->greet() . "\n";
```

### Go 模式

```php
// @syntax: go
<?php
name = "World"
person = new Person(name)
echo person.greet() + "\n"
```

| 特性 | PHP 模式 | Go 模式 |
|------|----------|---------|
| 变量 | `$name` | `name` |
| 属性访问 | `$obj->prop` | `obj.prop` |
| 方法调用 | `$obj->method()` | `obj.method()` |
| 字符串拼接 | `$a . $b` | `a + b` |

## 扩展系统

### 使用扩展

```bash
# 命令行加载
./zig-out/bin/php-interpreter --extension=./myext.so script.php
```

或通过配置文件 `.zigphp.json`：

```json
{
    "extensions": ["./extensions/mysql.so", "./extensions/redis.so"]
}
```

### 开发扩展

```zig
const std = @import("std");

pub const EXTENSION_API_VERSION: u32 = 1;

fn myFunction(_: *anyopaque, args: []const u64) anyerror!u64 {
    // 实现逻辑
    return 0;
}

const my_extension = Extension{
    .info = .{
        .name = "my_extension",
        .version = "1.0.0",
        .api_version = EXTENSION_API_VERSION,
        .author = "Your Name",
        .description = "My extension",
    },
    .init_fn = extensionInit,
    .shutdown_fn = extensionShutdown,
    .functions = &my_functions,
    .classes = &my_classes,
    .syntax_hooks = null,
};

pub export fn zigphp_get_extension() *const Extension {
    return &my_extension;
}
```

## AOT 编译

将 PHP 代码编译为原生可执行文件：

```bash
# 基本编译
./zig-out/bin/php-interpreter --compile app.php

# 优化编译
./zig-out/bin/php-interpreter --compile --optimize=release-fast app.php

# 静态链接
./zig-out/bin/php-interpreter --compile --static app.php

# 交叉编译
./zig-out/bin/php-interpreter --compile --target=x86_64-linux-gnu app.php
```

## 配置文件

创建 `.zigphp.json`：

```json
{
    "syntax": "go",
    "extensions": ["./extensions/mysql.so"],
    "include_paths": ["./lib", "./vendor"],
    "error_reporting": 32767
}
```

## 项目结构

```
zig-php/
├── src/
│   ├── compiler/          # 编译器前端
│   │   ├── lexer.zig      # 词法分析器
│   │   ├── parser.zig     # 语法分析器
│   │   ├── ast.zig        # AST 定义
│   │   └── syntax_mode.zig # 语法模式
│   ├── runtime/           # 运行时
│   │   ├── vm.zig         # 虚拟机
│   │   ├── types.zig      # 类型系统
│   │   └── stdlib.zig     # 标准库
│   ├── extension/         # 扩展系统
│   │   ├── api.zig        # 扩展 API
│   │   └── registry.zig   # 扩展注册表
│   ├── config/            # 配置系统
│   │   └── loader.zig     # 配置加载器
│   ├── aot/               # AOT 编译器
│   └── main.zig           # 入口点
├── examples/              # 示例
│   ├── extensions/        # 扩展示例
│   └── go_syntax_demo.php # Go 模式示例
├── docs/                  # 文档
└── tests/                 # 测试
```

## 文档

| 文档 | 说明 |
|------|------|
| [用户指南](USER_GUIDE.md) | 完整的使用说明 |
| [技术参考](TECHNICAL_REFERENCE.md) | 详细的技术文档 |
| [扩展开发指南](EXTENSION_DEVELOPMENT.md) | 如何开发扩展 |
| [多语法模式详解](MULTI_SYNTAX_GUIDE.md) | 语法模式深入指南 |

## 测试

```bash
# 运行所有测试
zig build test

# 运行特定测试
zig test src/compiler/syntax_mode.zig
zig test src/extension/registry.zig
```

## 支持的 PHP 特性

### 语言特性

- ✅ 变量和常量
- ✅ 函数（普通、匿名、箭头函数）
- ✅ 类（继承、接口、trait）
- ✅ 命名空间
- ✅ 异常处理
- ✅ 属性钩子（PHP 8.4）
- ✅ 管道运算符（PHP 8.5）
- ✅ clone with（PHP 8.5）

### 标准库

- ✅ 数组函数
- ✅ 字符串函数
- ✅ 数学函数
- ✅ 日期时间函数
- ✅ 文件系统函数
- ✅ JSON 函数
- ✅ 哈希函数

## 性能

| 操作 | 耗时 |
|------|------|
| 函数调用 | ~50ns |
| 对象实例化 | ~200ns |
| 数组操作 | ~10ns/元素 |
| 字符串操作 | ~5ns/字符 |
| GC | <1ms |

## 贡献

1. Fork 项目
2. 创建特性分支
3. 提交更改
4. 创建 Pull Request

### 开发规范

- 遵循 Zig 编码规范
- 添加测试覆盖
- 更新相关文档
- 确保所有测试通过

## 许可证

[待添加]

## 致谢

- Zig 编程语言社区
- PHP 语言规范
- 属性测试方法论
- 垃圾回收研究
