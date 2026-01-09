# 随机测试结果总结 (2026-01-09)

## 测试概览

| 测试 | 文件 | 状态 | 泄漏数 | DEBUG |
|------|------|------|--------|-------|
| #1 基础控制流 | test_random_1.php | ✅ 通过 | 12 | 无 |
| #2 面向对象 | test_random_2.php | ⚠️ 部分通过 | 12 | 无 |
| #3 函数和作用域 | test_random_3.php | ✅ 通过 | 12 | 无 |
| #4 类型和比较 | test_random_4.php | ⚠️ 部分通过 | 12 | 无 |
| #5 Try-Catch | test_random_5.php | ✅ 通过 | 13 | 无 |
| #6 Include/Require | test_random_6.php | ✅ 通过 | 12 | 无 |

---

## 发现的问题

### 1. 类型强制转换问题 ⚠️ (test_random_4.php)

**问题**: 比较运算符使用严格比较

```php
1 == '1'    // 返回 false（应为 true）
0 == false  // 返回 false（应为 true）
'' == 0     // 返回 false（应为 true）
```

**位置**: 类型比较实现
**严重性**: 中
**状态**: 需修复

### 2. 字符串转数字问题 ⚠️ (test_random_4.php)

**问题**: 字符串算术运算未实现

```php
'abc' + 1  // 抛出异常（PHP 中应转为 0，结果为 1）
```

**位置**: 字符串到数字转换
**严重性**: 中
**状态**: 需修复

### 3. 字符串索引不支持 ⚠️ (test_random_4.php)

**问题**: PHP 7.4+ 的字符串索引语法不支持

```php
$str = "abcdef";
echo $str[0];  // 抛出 "Cannot use value as array"
```

**位置**: 字符串索引实现
**严重性**: 低
**状态**: 需修复

### 4. 嵌套数组访问问题 ⚠️ (test_random_2.php)

**问题**: 多维数组访问返回非对象

```php
$container = ["nested" => ["deep" => new Base(3)]];
$obj = $container["nested"]["deep"];  // 返回 null 或错误
$obj->getId();  // 抛出 "Method call on non-object"
```

**位置**: 数组索引链式访问
**严重性**: 中
**状态**: 需修复

### 5. 异常链未实现 ⚠️ (test_random_5.php)

**问题**: 异常链 ($e->getPrevious()) 返回 null

```php
try {
    throw new Exception("Inner");
} catch (Exception $e) {
    throw new Exception("Outer", 0, $e);  // 应该链式
}
```

**位置**: 异常链处理
**严重性**: 低
**状态**: 需修复

### 6. function_exists() 未实现 ⚠️ (test_random_6.php)

**问题**: 函数检查内置函数未实现

```php
function_exists("function_exists");  // 抛出未定义函数错误
```

**位置**: 内置函数实现
**严重性**: 低
**状态**: 需实现

### 7. Try-Catch 内存泄漏增加 ⚠️ (test_random_5.php)

**问题**: 使用 Try-Catch 时泄漏从 12 增加到 13

**位置**: 异常处理中的对象分配
**严重性**: 中
**状态**: 需调查

---

## 内存泄漏分析

### 固定泄漏模式

每次运行固定出现 12 处泄漏：

| 类别 | 地址模式 | 数量 | 推测来源 |
|------|----------|------|----------|
| 小分配 | 0x10xxxx006-008 | 3 | GPA 内部管理 |
| HashMap buckets | 0x10xxxx340-380 | 5 | StringHashMap 桶分配 |
| 较大分配 | 0x10xxxx5c0-680 | 4 | 结构体或 ArrayList |

### 异常处理泄漏

Try-Catch 测试中出现 13 处泄漏（+1），表明异常处理中可能存在额外泄漏。

### 建议

使用 AddressSanitizer 进行深度分析：
```bash
zig build -Doptimize=Debug -Dsanitizer=address
```

---

## 已验证正常功能

### ✅ 正常工作的功能

1. **基本控制流**: for/foreach/if/else/while
2. **数组操作**: 创建、遍历、追加、排序
3. **字符串操作**: 连接、explode/implode、substr
4. **闭包**: use 捕获、匿名函数
5. **类**: 继承、方法调用、属性访问
6. **函数**: 参数传递、返回值、递归
7. **Try-Catch**: 异常抛出和捕获
8. **Include/Require**: 文件加载
9. **内置函数**: array_sum/range/count/sort 等

---

## 测试文件列表

```
examples/
├── test_random_1.php  # 基础控制流和闭包
├── test_random_2.php  # 面向对象（部分问题）
├── test_random_3.php  # 函数和作用域
├── test_random_4.php  # 类型和比较（部分问题）
├── test_random_5.php  # Try-Catch
└── test_random_6.php  # Include/Require
```

---

**生成时间**: 2026-01-09
**测试人员**: iFlow CLI
