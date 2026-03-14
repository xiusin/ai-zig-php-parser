# AOT模糊测试最终报告

**测试时间**: 2026-03-14  
**测试脚本数**: 207  
**通过**: 164 (79.23%)  
**失败**: 43 (20.77%)  
**内存泄漏**: 0

---

## 测试统计

### 按类别统计

| 类别 | 通过 | 失败 | 通过率 |
|------|------|------|--------|
| 类型转换 (type_conversions) | 8 | 1 | 88.89% |
| 算术运算 (arithmetic_ops) | 20 | 0 | 100% |
| 字符串操作 (string_ops) | 10 | 0 | 100% |
| 数组操作 (array_ops) | 0 | 15 | 0% |
| 控制流 (control_flow) | 15 | 0 | 100% |
| 函数 (functions) | 15 | 0 | 100% |
| 类 (classes) | 10 | 0 | 100% |
| 继承 (inheritance) | 8 | 0 | 100% |
| 接口 (interfaces) | 8 | 0 | 100% |
| Trait (traits) | 8 | 0 | 100% |
| 闭包 (closures_param) | 0 | 8 | 0% |
| 异常 (exceptions_param) | 10 | 0 | 100% |
| 静态方法 (static_methods) | 9 | 0 | 100% |
| 魔法方法 (magic_methods) | 8 | 0 | 100% |
| 数组函数 (array_functions) | 0 | 15 | 0% |
| 字符串函数 (string_functions) | 0 | 4 | 0% |
| 引用 (references_param) | 10 | 0 | 100% |
| 三元运算符 (ternary_param) | 15 | 0 | 100% |
| 空合并 (null_coalesce) | 10 | 0 | 100% |

---

## 发现的问题

### 1. 数组排序函数未实现 (15个失败)

**问题**: `sort()` 和 `rsort()` 函数在AOT编译后不输出结果

**示例**:
```php
$arr = [27, 18, 41, 44, 36];
sort($arr);
print_r($arr);  // AOT: 无输出, PHP: 正常输出排序后数组
```

**影响**: 所有使用 `sort()`, `rsort()` 的测试失败

---

### 2. 闭包中的静态变量编译错误 (8个失败)

**问题**: 闭包内使用 `static` 变量导致编译错误

**错误信息**:
```
COMPILE_ERROR: warning: unable to open library directory '/usr/local/lib': FileNotFound
```

**示例**:
```php
$counter = function() {
    static $count = 18;
    return ++$count;
};
```

**影响**: 所有使用闭包静态变量的测试失败

---

### 3. 数组函数链式调用输出不完整 (15个失败)

**问题**: `array_map()` + `array_filter()` + `array_reduce()` 链式调用时，只输出最后的 `array_reduce()` 结果

**示例**:
```php
$arr = [48, 39, 7, 18, 2, 1];
$mapped = array_map(function($x) { return $x * 2; }, $arr);
print_r($mapped);  // AOT: 无输出
$filtered = array_filter($mapped, function($x) { return $x > 20; });
print_r($filtered);  // AOT: 无输出
$sum = array_reduce($filtered, function($carry, $item) { return $carry + $item; }, 0);
echo "Sum: $sum\n";  // AOT: 正常输出
```

**影响**: 所有使用数组函数链的测试失败

---

### 4. 字符串函数 explode() 输出缺失 (4个失败)

**问题**: `explode()` 函数返回的数组无法通过 `print_r()` 输出

**示例**:
```php
$str = "hello world";
$parts = explode(" ", $str);
print_r($parts);  // AOT: 无输出, PHP: 正常输出数组
```

**影响**: 所有使用 `explode()` + `print_r()` 的测试失败

---

### 5. 数组到整数/浮点数转换不一致 (1个失败)

**问题**: 数组转换为 int/float 时，AOT返回0，PHP返回1

**示例**:
```php
$x = [1,2,3];
$int = (int)$x;    // AOT: 0, PHP: 1
$float = (float)$x;  // AOT: 0.0, PHP: 1.0
```

**影响**: 1个类型转换测试失败

---

## 优先级修复建议

### P0 - 关键问题（阻塞基本功能）

1. **数组排序函数** - 15个测试失败
   - 修复 `sort()`, `rsort()` 函数
   - 确保排序后数组可以正常输出

2. **数组函数输出** - 15个测试失败
   - 修复 `array_map()`, `array_filter()` 返回值
   - 确保中间结果可以被 `print_r()` 输出

### P1 - 重要问题（影响高级特性）

3. **闭包静态变量** - 8个测试失败
   - 修复闭包内 `static` 变量的编译
   - 解决库路径问题

4. **字符串函数输出** - 4个测试失败
   - 修复 `explode()` 返回值
   - 确保可以被 `print_r()` 输出

### P2 - 次要问题（边界情况）

5. **类型转换一致性** - 1个测试失败
   - 修复数组到数值类型的转换
   - 与PHP行为保持一致

---

## 测试覆盖的功能

### ✅ 完全通过的功能 (100%通过率)

- 算术运算 (+, -, *, /, %, **)
- 字符串基本操作 (拼接, strlen, strtoupper, strtolower, str_replace)
- 控制流 (if/else, for, while, foreach)
- 函数定义和调用
- 类定义和实例化
- 继承 (extends)
- 接口 (implements)
- Trait (use)
- 异常处理 (try/catch/throw)
- 静态方法和属性
- 魔法方法 (__get, __set, __isset)
- 引用传递 (&$param)
- 三元运算符 (? :)
- 空合并运算符 (??)

### ❌ 存在问题的功能

- 数组排序 (sort, rsort)
- 数组高阶函数 (array_map, array_filter, array_reduce)
- 字符串分割 (explode)
- 闭包静态变量
- 数组类型转换

---

## 内存安全

- ✅ 无内存泄漏检测到
- ✅ 所有编译产物已清理
- ✅ 通过的测试脚本已删除

---

## 建议

1. **优先修复数组相关函数** - 占失败测试的70%
2. **修复闭包编译问题** - 影响高级特性使用
3. **增加更多边界测试** - 当前207个测试，建议扩展到300+
4. **添加性能基准测试** - 验证AOT性能目标
5. **添加并发测试** - 验证线程安全性

---

## 附录：失败测试脚本

所有失败的测试脚本已保留在 `fuzzy_scripts/` 目录，可用于回归测试。

**脚本列表**:
- test_0005_type_conversions.php
- test_0040-0054_array_ops.php (15个)
- test_0119-0126_closures_param.php (8个)
- test_0154-0168_array_functions.php (15个)
- test_0169-0172_string_functions.php (4个)
