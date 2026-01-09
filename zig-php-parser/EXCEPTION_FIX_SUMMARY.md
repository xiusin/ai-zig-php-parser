# Exception Type Preservation Fix - 2026-01-09

## 问题描述

当 PHP 异常被捕获时，原始异常类型丢失：
- `get_class($e)` 返回 `"Exception"` 而不是实际的子类（如 `"MyException"`）
- `method_exists($e, 'myMethod')` 返回 `false`（自定义方法不可用）

## 根本原因

1. `evaluateThrowStatement` 将用户异常对象转换为新的 `PHPException`，丢失原始类型
2. `current_exception` 存储内部 `PHPException`，而非原始 PHP 对象
3. catch 子句创建新的通用 Exception 对象，丢失原始类型信息

## 修复方案

### 1. 添加 `original_exception_value` 字段 (vm.zig:1189)

```zig
original_exception_value: ?Value = null,
current_exception: ?*exceptions.PHPException = null,
```

### 2. 修改 `evaluateThrowStatement` (vm.zig:7484)

- 对于异常对象，保留原始对象引用
- 将原始异常对象存储在 `original_exception_value` 中
- 仍创建 `PHPException` 供内部使用

### 3. 修改 catch 子句 (vm.zig:7405)

- 首先检查 `original_exception_value` 是否可用
- 如果可用，直接使用原始异常对象（保持类型）
- 同时清理 `current_exception` (PHPException)
- 如果不可用，回退到原有逻辑

## 测试结果

```
=== Test 1: Basic exception type preservation ===
Exception type: MyException
Has myMethod: yes
Test 1 PASSED

=== Test 2: AnotherException type preservation ===
Exception type: AnotherException
Has getCustomInfo: yes
Test 2 PASSED

=== Test 3: Nested exception handling ===
Inner catch - type: MyException
Outer catch - type: AnotherException
Test 3 PASSED
```

## 内存泄漏统计

| 测试 | 泄漏数 | 额外泄漏 |
|------|--------|----------|
| Baseline (Hello World) | 12 | - |
| Simple Exception | 17 | +5 |
| Full Exception Test | 32 | +20 |

内存泄漏有所改善（从 +15/+60 降至 +5/+20），但仍有一些遗留问题需要后续修复。

## 已知问题

1. **`instanceof` 关键字** - 解析器尚未完全支持，可能导致 Test 4 失败
2. **残余内存泄漏** - Exception 对象的生命周期管理需要进一步优化
3. **解析器警告** - `parseStatement failed with error: error.UnexpectedToken at token: .t_string (and)`

## 待修复项

1. 完善 `instanceof` 操作符的解析和求值
2. 进一步优化异常对象的内存管理
3. 修复解析器对 `and` 关键字的处理

## 文件修改

- `src/runtime/vm.zig`:
  - 行 1189: 添加 `original_exception_value` 字段
  - 行 7484-7527: 重写 `evaluateThrowStatement`
  - 行 7405-7462: 重写 catch 子句
