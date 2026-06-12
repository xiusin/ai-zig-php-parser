# zig-php 文档索引

## 文档列表

### 用户文档

| 文档 | 说明 | 语言 |
|------|------|------|
| [用户指南](USER_GUIDE.md) | 完整的安装和使用说明 | 中文 |
| [多语法模式详解](MULTI_SYNTAX_GUIDE.md) | PHP/Go 语法模式深入指南 | 中文 |
| [项目概述](README_CN.md) | 项目简介和快速开始 | 中文 |

### 开发者文档

| 文档 | 说明 | 语言 |
|------|------|------|
| [技术参考](TECHNICAL_REFERENCE.md) | 架构、API 和内部实现 | 中文 |
| [扩展开发指南](EXTENSION_DEVELOPMENT.md) | 如何开发第三方扩展 | 中文 |

### 规范文档

| 文档 | 说明 |
|------|------|
| [需求文档](../.kiro/specs/multi-syntax-extension-system/requirements.md) | 多语法扩展系统需求 |
| [设计文档](../.kiro/specs/multi-syntax-extension-system/design.md) | 多语法扩展系统设计 |
| [任务列表](../.kiro/specs/multi-syntax-extension-system/tasks.md) | 实现任务清单 |

---

## 快速导航

### 我想...

- **开始使用 zig-php** → [用户指南](USER_GUIDE.md)
- **了解多语法模式** → [多语法模式详解](MULTI_SYNTAX_GUIDE.md)
- **开发扩展** → [扩展开发指南](EXTENSION_DEVELOPMENT.md)
- **了解内部实现** → [技术参考](TECHNICAL_REFERENCE.md)
- **查看项目概述** → [项目概述](README_CN.md)

---

## 示例代码

### 示例文件

| 文件 | 说明 |
|------|------|
| [go_syntax_demo.php](../examples/go_syntax_demo.php) | Go 语法模式演示 |
| [sample_extension.zig](../examples/extensions/sample_extension.zig) | 扩展开发示例 |

---

## 版本历史

- **v0.1.0** - 初始版本
  - 完整的 PHP 8.5 语法支持
  - 多语法模式（PHP/Go）
  - 第三方扩展系统
  - AOT 编译支持
