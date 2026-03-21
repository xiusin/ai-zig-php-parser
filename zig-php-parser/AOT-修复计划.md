# AOT 模糊测试问题深度修复计划

**创建时间**: 2026-03-20  
**问题总数**: 141 (MISMATCH: 40, COMPILE_FAIL: 32, AOT_FAIL: 69)  
**修复策略**: 分层修复，从底层到上层，确保每个修复都有测试验证

## 问题深度分类

### 第一层：核心运行时缺陷 (P0 - 阻塞性)

#### 1.1 致命崩溃问题
- **match表达式unreachable崩溃** (test_019_match.php)
  - 影响面: 所有使用match的代码
  - 根因: IR生成时未正确处理match的所有分支
  - 修复位置: `src/aot/ir_generator.zig` - `generateMatchExpr()`

#### 1.2 类型系统核心缺陷
- **常量表达式计算返回null** (test_047, test_105, test_144, test_165)
  - 影响面: 类常量、枚举、编译时计算
  - 根因: 常量折叠优化器未正确处理复杂表达式
  - 修复位置: `src/aot/optimizer.zig` - 常量折叠pass

- **枚举常量继承失败** (test_007_enums.php)
  - 影响面: 所有枚举继承场景
  - 根因: 符号表未正确处理枚举常量的继承链
  - 修复位置: `src/aot/symbol_table.zig` - 枚举解析

### 第二层：编译器前端问题 (P0 - 编译失败)

#### 2.1 函数签名不匹配 (32个COMPILE_FAIL中的主要原因)
```
json_encode: 期望2参数，实际1参数
preg_match: 期望3参数，实际2参数
mt_rand: 期望2参数，实际0或1参数
array_column: 期望3参数，实际2参数
isset: 期望1参数，实际可变参数
```
- **根因**: stdlib函数签名定义与PHP标准不一致
- **修复位置**: `src/aot/runtime_lib.zig` - 函数签名表

#### 2.2 Trait冲突检测缺失
- test_017_traits.php, test_090_traits.php, test_139_trait_resolution.php
- **根因**: 编译时未检测同名方法冲突
- **修复位置**: `src/compiler/parser.zig` - Trait解析阶段

#### 2.3 引用类型参数
- test_021_database.php: 引用赋值参数类型错误
- **根因**: IR生成器未正确处理`&$var`语法
- **修复位置**: `src/aot/ir_generator.zig` - 参数处理

### 第三层：标准库缺失 (P1 - 功能不完整)

#### 3.1 数学/类型检查函数
```zig
缺失函数清单:
- is_infinite(), is_nan(), is_finite()
- is_scalar(), is_countable()
- fdiv()
```

#### 3.2 字符串函数
```zig
缺失函数清单:
- strchr() (strstr别名)
- str_contains(), str_starts_with(), str_ends_with()
```

#### 3.3 数组函数
```zig
缺失/错误函数:
- array_push(), array_pop() (参数处理错误)
- array_slice(), array_keys(), array_merge()
- array_reverse(), array_search()
```

#### 3.4 日期时间类
```zig
缺失类:
- DateTimeZone
- DateInterval
- DateTimeImmutable
```

#### 3.5 SPL类
```zig
缺失类:
- ArrayObject, ArrayIterator
- SplStack, SplQueue
- WeakMap, WeakReference
```

#### 3.6 系统/网络函数
```zig
缺失函数:
- getmypid(), gethostname()
- gethostbyname(), dns_get_record()
- stream_wrapper_register()
```

#### 3.7 错误处理
```zig
缺失函数:
- set_error_handler()
- restore_error_handler()
- error_get_last()
```

### 第四层：语义差异 (P1 - 行为不一致)

#### 4.1 isset vs nullsafe运算符
- test_031_nullsafe.php
- **问题**: `isset($obj?->prop)` 在AOT返回true，PHP返回false
- **根因**: nullsafe运算符的短路求值未正确实现

#### 4.2 异常处理顺序
- test_041_exceptions2.php, test_077_exceptions.php, test_136_multi_catch.php
- **问题**: finally块执行时机、multi-catch顺序
- **根因**: IR生成时未按PHP规范生成控制流

#### 4.3 后期静态绑定
- test_073_late_static.php, test_055_static_late.php
- **问题**: `static::` 解析错误
- **根因**: 符号表未正确维护静态绑定上下文

#### 4.4 对象克隆
- test_076_clone.php, test_023_cloning.php
- **问题**: `__clone()` 魔术方法调用时机错误
- **根因**: 克隆操作的IR生成顺序错误

## 修复策略

### 阶段1: 核心稳定性 (Week 1)
**目标**: 消除所有崩溃和编译失败

1. **修复match崩溃** (1天)
2. **修复函数签名不匹配** (2天)
3. **修复常量表达式** (2天)

### 阶段2: 标准库补全 (Week 2-3)
**目标**: 实现缺失的核心函数/类

4. **数组函数** (3天)
5. **类型检查函数** (1天)
6. **字符串函数** (2天)
7. **DateTime类族** (3天)
8. **SPL基础类** (3天)

### 阶段3: 语义对齐 (Week 4)
**目标**: 修复行为差异

9. **isset/nullsafe对齐** (1天)
10. **异常处理顺序** (2天)
11. **后期静态绑定** (2天)
12. **对象克隆** (1天)

## 进度跟踪

| 阶段 | 任务 | 状态 | 测试通过 | 负责模块 |
|------|------|------|----------|----------|
| 1 | match崩溃 | ✅ 已完成 | 1/1 | native_linker |
| 1 | 函数签名 | 🔴 待开始 | 0/32 | runtime_lib |
| 1 | 常量表达式 | 🔴 待开始 | 0/4 | optimizer |
