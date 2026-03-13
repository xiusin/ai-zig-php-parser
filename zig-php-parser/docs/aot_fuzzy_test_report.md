# AOT 模糊测试报告

## 测试概览

| 指标 | 值 |
|------|-----|
| 测试时间 | 2026-03-13 |
| 总测试数 | 1283 |
| 已处理数 | 1025 |
| 通过数 | 767 |
| 失败数 | 258 |
| **通过率** | **74.83%** |

> 注：测试因进程异常中断，剩余258个测试脚本未执行

## 失败分类

| 类型 | 数量 | 占比 |
|------|------|------|
| 编译错误 | 58 | 22.5% |
| 结果不一致 | 200 | 77.5% |

---

## 一、编译错误分析

### 1.1 缺失的内置函数

以下PHP内置函数在AOT运行时中尚未实现：

| 函数名 | 分类 |
|--------|------|
| `addslashes` | 字符串函数 |
| `array_diff_assoc` | 数组函数 |
| `array_diff_key` | 数组函数 |
| `array_intersect_key` | 数组函数 |
| `checkdate` | 日期函数 |
| `getdate` | 日期函数 |
| `is_finite` | 数学函数 |
| `is_infinite` | 数学函数 |
| `is_nan` | 数学函数 |
| `is_object` | 变量函数 |
| `is_scalar` | 变量函数 |
| `mktime` | 日期函数 |
| `ob_start` | 输出缓冲 |
| `quotemeta` | 字符串函数 |
| `str_rot13` | 字符串函数 |
| `str_shuffle` | 字符串函数 |
| `strchr` | 字符串函数 |
| `stripslashes` | 字符串函数 |
| `stristr` | 字符串函数 |
| `strpbrk` | 字符串函数 |
| `strrchr` | 字符串函数 |
| `substr_count` | 字符串函数 |
| `substr_replace` | 字符串函数 |

**共计 23 个缺失函数**

---

## 二、结果不一致分析

### 2.1 主要问题模式

#### 模式1：浮点精度问题
- **PHP输出**: `12303.14`
- **AOT输出**: `12303.141`
- **原因**: AOT浮点格式化精度处理与PHP不一致

#### 模式2：整数溢出处理
- **PHP输出**: `0`
- **AOT输出**: `-92233720368548`（类似INT_MIN值）
- **原因**: 整数溢出时AOT处理方式与PHP不同

#### 模式3：正负判断
- **PHP输出**: `positive`
- **AOT输出**: `negative`
- **原因**: PHP_INT_MAX边界值处理差异

#### 模式4：字符串长度计算
- **PHP输出**: `14`
- **AOT输出**: `18`
- **原因**: 特殊字符（如转义字符）长度计算方式不同

#### 模式5：未定义变量处理
- **PHP输出**: `Warning: Undefined variable $var...`
- **AOT输出**: 直接使用默认值
- **原因**: AOT未实现Warning输出机制

#### 模式6：解析错误信息格式
- **PHP输出**: `Parse error: syntax error, unexpected identifier "..."`
- **AOT输出**: `Parse error: Unexpected token in expression...`
- **原因**: 错误信息格式化方式不同

---

## 三、失败详情表格

| 脚本 | 类型 | PHP正确结果 | AOT执行结果 |
|------|------|-------------|-------------|
| test_0009.php | mismatch | `0` | `-92233720368548` |
| test_0010.php | mismatch | `193` | (空) |
| test_0028.php | mismatch | `0` | `-92233720368548` |
| test_0031.php | mismatch | `-314689023962513408` | `-31468902396251` |
| test_0039.php | mismatch | `0` | `-92233720368548` |
| test_0082.php | mismatch | `Warning: Undefined variable` | `5` |
| test_0574.php | compile_error | `5` | `undeclared identifier 'str_shuffle'` |
| test_0580.php | compile_error | `123` | `undeclared identifier 'ob_start'` |
| test_0804.php | compile_error | `1` | `undeclared identifier 'is_nan'` |

> 完整失败列表保存在 `test_scripts/failed_scripts/` 目录

---

## 四、问题优先级建议

### P0 - 紧急修复

1. **整数溢出处理** - 影响多个测试用例
2. **浮点精度格式化** - 输出结果不一致

### P1 - 高优先级

1. **缺失的字符串函数** (str_shuffle, str_rot13, strchr等)
2. **缺失的数组函数** (array_diff_assoc, array_diff_key等)
3. **缺失的数学函数** (is_nan, is_finite, is_infinite)

### P2 - 中优先级

1. **缺失的日期函数** (checkdate, getdate, mktime)
2. **未定义变量Warning输出**
3. **错误信息格式统一**

---

## 五、测试覆盖范围

本次测试覆盖以下PHP特性：

- ✅ 基础类型运算（整数、浮点、字符串、布尔、NULL）
- ✅ 控制流（if/else/switch/match/三元运算）
- ✅ 循环（for/while/do-while/foreach）
- ✅ 数组操作（创建、访问、函数）
- ✅ 字符串操作（各种字符串函数）
- ✅ OOP特性（类、继承、接口、Trait、静态成员、魔法方法）
- ✅ 闭包和箭头函数
- ✅ 边界条件测试
- ✅ 混合复杂场景

---

## 六、结论

1. **总体通过率 74.83%**，AOT编译器基本功能稳定
2. **主要问题**：
   - 23个内置函数尚未实现
   - 浮点精度处理需优化
   - 整数溢出处理需对齐PHP行为
3. **建议后续工作**：
   - 补充缺失的内置函数实现
   - 统一浮点格式化逻辑
   - 完善错误/警告输出机制

---

## 七、文件位置

| 内容 | 路径 |
|------|------|
| 测试脚本生成器 | `test_scripts/generate_tests.py` |
| 测试运行器 | `test_scripts/run_tests.py` |
| 失败脚本 | `test_scripts/failed_scripts/*.php` |
| 失败详情 | `test_scripts/failed_scripts/*.info` |

---

*报告生成时间: 2026-03-13*