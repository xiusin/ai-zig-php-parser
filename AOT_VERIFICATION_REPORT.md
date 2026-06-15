# AOT 模块验证报告

**测试日期**: 2026-06-13
**测试环境**: x86_64-linux (TencentOS), Zig 0.17.0-dev, PHP 8.3.31
**测试脚本数**: 25

---

## 总览

| 类别 | 数量 |
|------|------|
| AOT 完整编译失败（OOM） | 25/25 |
| AOT IR 生成失败 | 6/25 |
| 解释器运行时崩溃 | 1/25 |
| 解释器运行时异常（PHP 可运行） | 14/25 |
| 解释器输出与 PHP 不一致 | 25/25 |
| 字节码 VM 回退到 tree-walking | 23/25 |
| 调试信息泄露到 stdout | 23/25 |

**结论**: 无任何脚本能够通过 AOT 完整编译流程产生可执行二进制。解释器模式下仅 2 个脚本能完整运行，但输出仍与 PHP 存在格式差异。

---

## 1. AOT 编译问题

### 1.1 全部脚本 AOT 链接阶段 OutOfMemory（严重 - 阻塞）

**影响**: 所有 25 个脚本
**现象**: `--compile` 在执行 `zig build-exe` 链接阶段崩溃，报 `OutOfMemory`
**根因**: 生成的 `runtime_lib.zig`（~968KB）加上用户代码，编译时内存需求超过系统可用内存（3.6GB）
**示例**:
```
Error: Compilation failed with 1 errors, 0 warnings
test_001_variables.php: error: executable generation failed: OutOfMemory
```

### 1.2 AOT IR 生成失败（6 个脚本）

**影响**: test_009_functions_basic, test_030_variables_advanced, test_033_namespaces, test_048_dnf_types, test_049_type_system, test_052_complex_expressions
**现象**: `--compile --no-link` 返回 `error: FileNotFound`
**根因**: AOT 编译器在解析阶段检测到不支持的语法，生成了仅输出错误信息的 stub main.zig，而非正确编译后的 IR。FileNotFound 是内部错误路径处理不当导致的误报。

| 脚本 | AOT 检测到的编译错误 |
|------|---------------------|
| test_009_functions_basic | `Can't use function return value in write context` (line 63) |
| test_030_variables_advanced | `Can't use function return value in write context` (line 88) |
| test_033_namespaces | PHP 检测到 namespace 语法错误但解释器不检测 |
| test_048_dnf_types | DNF 类型语法解析问题 |
| test_049_type_system | `strict_types` 声明位置问题 |
| test_052_complex_expressions | match 表达式语法解析问题 |

### 1.3 runtime_lib.zig 语法兼容性问题（阻塞手动编译）

**现象**: 手动编译 AOT 生成的 Zig 代码时，`runtime_lib.zig` 存在两类 Zig 0.17 不兼容问题：

1. **`**` 运算符空白不一致**（3 处）：
   - `runtime_lib.zig:18844`: `[_]usize{0} ** 256` → 应为 `[_]usize{0}**256`
   - `runtime_lib.zig:20669`: `Value.initNull()} ** MAX_SIGNALS` → 应为 `}**MAX_SIGNALS`
   - `runtime_lib.zig:20670`: `false} ** MAX_SIGNALS` → 应为 `}**MAX_SIGNALS`

2. **Zig API 不兼容**：
   - `std.ArrayListUnmanaged` 初始化 `.{}`
   - 缺少 `items` 和 `capacity` 字段（Zig 0.17 修改了 ArrayList 初始化方式）
   - `std.ArrayHashMap` 不存在（0.17 中已移除/重命名）

**根因**: `runtime_lib_template.zig` 是为旧版 Zig 编写的，未适配 0.17 API 变更。

### 1.4 AOT 编译警告（非阻塞）

以下脚本在 AOT 编译时产生警告：

| 脚本 | 警告 |
|------|------|
| test_003_type_juggling | 未使用变量（乱码变量名） |
| test_010_closures | 未使用变量 `$func`, `$count`, `$value` |
| test_029_callback | 未使用变量 `$callback` |
| test_051_closures_advanced | 未使用变量 `$fn`, `$functions` |
| test_065_array_walk | 未使用变量 `$key`, `$flattened` |

---

## 2. 解释器运行时问题

### 2.1 崩溃（1 个脚本 - 严重）

**test_012_arrays_basic**: `var_export()` 调用时发生 integer overflow 导致 panic
```
thread 617590 panic: integer overflow
/opt/zig/lib/std/multi_array_list.zig:246:35: 0x12c97b2 in slice (php-interpreter)
/root/products/zig-php-parser/src/runtime/stdlib.zig:4155:21: 0x12c8ef5 in varExportFn
```
**根因**: `varExportFn` 内部调用 `exportValueDebug` 时触发 multi_array_list 容量溢出

### 2.2 运行时异常（14 个脚本 - 解释器与 PHP 行为不一致）

| 脚本 | 错误类型 | 详情 |
|------|----------|------|
| test_001_variables | TypeError | `Variable variable name must be a string` (line 13: `$$a = "indirect"` — `$a` 为整数) |
| test_008_loops_foreach | TypeError | `Foreach can only iterate over arrays or Iterator objects` |
| test_010_closures | TypeError | `Undefined class constant or static property Counter::class` |
| test_018_magic_methods | UndefinedVariableError | `Undefined variable: $name` — 构造函数参数未正确绑定 |
| test_021_math_functions | UndefinedFunctionError | 缺少 `sinh()`, `cosh()`, `tanh()` 等函数 |
| test_023_string_advanced | UndefinedFunctionError | 缺少 `mb_strlen()`, `mb_substr()`, `strstr()` 等函数 |
| test_033_namespaces | UndefinedClassError | 命名空间类查找失败 |
| test_047_readonly_props | UndefinedPropertyError | 构造函数参数属性绑定失败 |
| test_048_dnf_types | UndefinedVariableError | DNF 类型语法导致变量未定义 |
| test_051_closures_advanced | TypeError | `Increment/decrement only supports variables` — 闭包内 `$count++` 不支持 |
| test_052_complex_expressions | TypeError | `array_map() expects parameter 1 to be a valid callback` |
| test_056_superglobals | UndefinedVariableError | `$GLOBALS` 超全局变量未实现 |
| test_057_output_buffering | UndefinedFunctionError | `ob_start()` 等输出控制函数未实现 |
| test_065_array_walk | UndefinedFunctionError | `array_walk_recursive()` 未实现 |

### 2.3 输出格式问题（所有脚本）

#### 2.3.1 调试信息泄露到 stdout

23/25 个脚本的 tree-walking 解释器将调试信息输出到 stdout，与正常输出混合：
- `eval: depth=N tag=xxx` — 语法树遍历调试信息
- `DEBUG: About to run VM...` — VM 启动调试信息
- `=== PHP Interpreter Performance Statistics ===` — 性能统计信息
- `Peak memory usage: N bytes` 等

test_063_sorting_algorithms 产生了 **72164 条** eval 调试行。

#### 2.3.2 bool/null 值输出格式错误

解释器将 `true`、`false`、`NULL` 输出与后续内容粘连：
```
# PHP 正确输出:
true
is_array: true

# 解释器错误输出:
trueeval: depth=4 tag=literal_string
is_array: 
```

这是因为 `echo true` 时解释器未正确输出换行，且 `echo` 对 `true`/`false`/`NULL` 的字符串转换行为与 PHP 不一致。

#### 2.3.3 运算结果错误

| 脚本 | 问题 |
|------|------|
| test_003_type_juggling | `"5" + 3` 结果为 5（应为 8），`"20" + 10` 结果为 20（应为 30） |
| test_006_loops_for | 多重循环输出不完整 |
| test_007_loops_while | continue/break 在嵌套循环中行为不正确 |
| test_008_loops_foreach | `array_map` 回调未正确修改原数组 |
| test_010_closures | 闭包 `use` 变量绑定不正确 |
| test_012_arrays_basic | `array_shift` 后数组顺序错误，`var_export` 崩溃 |
| test_063_sorting_algorithms | quicksort 输出完全错误（无限展开），merge sort 也失败 |

### 2.4 字节码 VM 回退

23/25 个脚本在字节码 VM 模式下失败并回退到 tree-walking：
- **UndefinedFunction** (19 个): 字节码 VM 未实现用户自定义函数调用
- **TypeMismatch** (3 个): 字节码 VM 类型系统问题
- **StackOverflow** (1 个): test_063 递归函数导致栈溢出

### 2.5 内存统计异常

几乎所有脚本的 `Peak memory usage` 报告为 **0 bytes**，即使脚本创建了数组、对象等数据结构。这表明内存追踪系统存在 bug。

---

## 3. PHP 语法差异

3 个脚本在 PHP 8.3 中本身就会报错，但解释器不报错：

| 脚本 | PHP 错误 | 解释器行为 |
|------|----------|-----------|
| test_003_type_juggling | `Unsupported operand types: string + int` (line 7) | 继续执行（类型转换逻辑与 PHP 不同） |
| test_033_namespaces | `Cannot mix bracketed namespace declarations` (line 25) | 继续执行但后续命名空间解析失败 |
| test_048_dnf_types | `syntax error, unexpected token "&"` (line 59) | 继续执行但变量绑定失败 |

2 个脚本在 PHP 中致命错误，AOT 编译器正确检测但 FileNotFound 掩盖了真实错误：

| 脚本 | PHP 错误 |
|------|----------|
| test_009_functions_basic | `Can't use function return value in write context` (line 63) |
| test_049_type_system | `strict_types declaration must be the very first statement` (line 37) |

---

## 4. 按脚本详细结果

| 脚本 | AOT编译 | IR生成 | 解释器运行 | 输出匹配PHP | 主要问题 |
|------|---------|--------|-----------|-------------|----------|
| test_001_variables | OOM | OK | 异常终止 | 否 | 变量变量 `$$a` 不支持整数键 |
| test_003_type_juggling | OOM | OK | 运行 | 否 | 类型转换逻辑与PHP不一致 |
| test_006_loops_for | OOM | OK | 运行 | 否 | 多重循环输出不完整 |
| test_007_loops_while | OOM | OK | 运行 | 否 | 嵌套循环 continue/break 行为不正确 |
| test_008_loops_foreach | OOM | OK | 异常终止 | 否 | foreach 对非数组报错 |
| test_009_functions_basic | OOM | 失败 | 运行 | 否 | 引用返回函数调用不支持 |
| test_010_closures | OOM | OK | 异常终止 | 否 | 闭包use绑定、类常量访问失败 |
| test_012_arrays_basic | OOM | OK | **崩溃** | 否 | var_export integer overflow |
| test_018_magic_methods | OOM | OK | 异常终止 | 否 | 构造函数参数未绑定 |
| test_021_math_functions | OOM | OK | 异常终止 | 否 | 缺少 sinh/cosh/tanh 等函数 |
| test_023_string_advanced | OOM | OK | 异常终止 | 否 | 缺少 mb_* 和 strstr 等函数 |
| test_029_callback | OOM | OK | 运行 | 否 | 回调/排序结果不正确 |
| test_030_variables_advanced | OOM | 失败 | 运行 | 否 | 引用返回赋值不支持 |
| test_033_namespaces | OOM | 失败 | 异常终止 | 否 | 命名空间类查找失败 |
| test_047_readonly_props | OOM | OK | 异常终止 | 否 | 构造函数属性提升未实现 |
| test_048_dnf_types | OOM | 失败 | 异常终止 | 否 | DNF类型语法不支持 |
| test_049_type_system | OOM | 失败 | 运行 | 否 | strict_types 位置检查缺失 |
| test_051_closures_advanced | OOM | OK | 异常终止 | 否 | 闭包内自增操作不支持 |
| test_052_complex_expressions | OOM | 失败 | 运行 | 否 | array_map 回调类型不匹配 |
| test_056_superglobals | OOM | OK | 异常终止 | 否 | $GLOBALS 超全局变量未实现 |
| test_057_output_buffering | OOM | OK | 异常终止 | 否 | ob_start 等函数未实现 |
| test_063_sorting_algorithms | OOM | OK | 运行 | 否 | quicksort 完全错误，7万+调试行 |
| test_064_string_manipulation | OOM | OK | 异常终止 | 否 | mb_* 函数未实现 |
| test_065_array_walk | OOM | OK | 异常终止 | 否 | array_walk_recursive 未实现 |
| test_068_misc_functions | OOM | OK | 异常终止 | 否 | 类型检查函数、序列化等不正确 |

---

## 5. 问题优先级排序

### P0 - 阻塞（必须修复）
1. **AOT 链接阶段 OutOfMemory** — 所有 AOT 编译被阻塞
2. **runtime_lib.zig Zig 0.17 API 不兼容** — 即使绕过 OOM 也无法手动编译
3. **解释器崩溃（test_012）** — var_export integer overflow panic

### P1 - 严重（应尽快修复）
4. **调试信息泄露到 stdout** — 23/25 脚本受影响，无法获取干净输出
5. **bool/null 值输出格式错误** — `trueeval:` 等粘连输出
6. **14 个脚本运行时异常** — 解释器缺少大量 PHP 标准函数和特性
7. **AOT IR 生成 FileNotFound 误报** — 应显示真实的编译错误

### P2 - 中等
8. **类型转换逻辑不一致** — 字符串+数字运算结果错误
9. **内存统计始终为 0** — 追踪系统 bug
10. **字节码 VM 频繁回退** — 23/25 脚本回退到 tree-walking
11. **排序算法实现错误** — quicksort 结果完全错误

### P3 - 低
12. **AOT 编译警告** — 未使用变量误报（变量名乱码）
