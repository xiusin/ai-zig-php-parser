# Issue: Arrow Function参数导致后续参数丢失

## 问题描述

当arrow function作为函数参数时，后续的参数在IR生成时被丢失。

## 复现

```php
// 问题代码
$r = array_map(fn($x) => $x * 2, [1, 2, 3]);

// 生成的IR（错误）
call @array_map(closure)  // 缺少第二个参数

// 期望的IR
call @array_map(closure, array)  // 应该有2个参数
```

## 对比测试

```php
// 使用字符串callback - 正常工作
function double($x) { return $x * 2; }
$r = array_map('double', [1, 2, 3]);

// 生成的IR（正确）
call @array_map(string, array)  // 有2个参数
```

## 影响范围

- 所有使用arrow function作为参数的高阶函数
- array_map, array_filter, array_reduce等
- 影响51个测试文件（9.9%）

## 根本原因

在`generateFunctionCall`中，当处理arrow function参数时，后续参数被跳过。

可能的原因：
1. Arrow function被转换为closure时，参数索引计算错误
2. 参数循环逻辑有bug，提前退出
3. AST解析阶段就丢失了参数

## 修复方向

1. 检查`generateFunctionCall`中的参数循环逻辑
2. 确认arrow function不会影响后续参数的处理
3. 添加测试用例覆盖这种情况

## 优先级

P0 - 高优先级（影响10%测试）

---

*创建时间: 2026-03-05*
*文件: src/aot/ir_generator.zig:3266*
