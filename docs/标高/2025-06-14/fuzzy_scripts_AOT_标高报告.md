# fuzzy_scripts AOT 编译标高报告

**日期**: 2025-06-14  
**环境**: Zig 0.17.0-dev.813+2153f8143, Linux x86_64, 3.6GB RAM + 8.2GB Swap  
**测试范围**: fuzzy_scripts/ 下 25 个 PHP 测试脚本  
**测试命令**: `php-interpreter --compile <file.php>`  

---

## 一、总览

| 指标 | 数值 |
|------|------|
| 测试脚本总数 | **25** |
| 解释器执行 PASS | **25** (100%) |
| AOT 编译 PASS | **0** (0%) |
| AOT 生成二进制运行 | **0** (0%) |
| AOT IR 生成阶段成功 | ~20 (80%) |
| AOT Zig 编译阶段成功 | **0** (0%) |

---

## 二、问题分类与影响

### 🔴 P0 — AOT 编译全量失败 (25/25)

#### 1. Zig 编译 OOM（19 个脚本，76%）

**现象**: IR 生成成功、Zig 代码生成成功、`zig build-exe` 调用时 OOM

**涉及文件**:
```
test_001_variables.php   (Zig代码 112KB + runtime_lib.zig 970KB = ~1MB)
test_003_type_juggling.php
test_007_loops_while.php
test_008_loops_foreach.php
test_010_closures.php
test_012_arrays_basic.php
test_018_magic_methods.php
test_021_math_functions.php
test_023_string_advanced.php
test_029_callback.php
test_047_readonly_props.php
test_051_closures_advanced.php
test_056_superglobals.php
test_057_output_buffering.php
test_063_sorting_algorithms.php
test_064_string_manipulation.php
test_065_array_walk.php
test_068_misc_functions.php
```

**根因**: `runtime_lib.zig`（969KB）+ 生成的 `main.zig`（平均 ~100KB）在 Zig 0.17 编译时需要大量内存（预估峰值 >4GB），当前机器只有 3.6GB RAM + 8.2GB Swap，编译进程 OOM 被 kill。

**错误日志**: `Zig 编译器 OOM，请手动执行: cd ... && zig build-exe main.zig ...`

#### 2. Native Linker Segfault（1 个脚本，4%）

**涉及文件**: `test_006_loops_for.php`

**现象**: `native_linker.zig:5843` 的 `generateTerminatorSimple` 函数中访问 `target.instructions.items` 时触发 General Protection Exception (segfault)

**错误堆栈**:
```
native_linker.zig:5843:41 — for (target.instructions.items) |inst|
native_linker.zig:4917:50 — generateControlFlowStateMachine
native_linker.zig:4444:53 — generateFunction
native_linker.zig:590:38 — generateZigCode
compiler.zig:1089:55 — linkExecutable
```

**根因**: `generateTerminatorSimple` 遍历目标块指令时，`target` 指针或 `instructions` 列表可能指向无效内存（use-after-free 或 dangling pointer）。

#### 3. FileNotFound 编译前崩溃（5 个脚本，20%）

**涉及文件**:
```
test_009_functions_basic.php
test_030_variables_advanced.php
test_033_namespaces.php
test_048_dnf_types.php
test_049_type_system.php
test_052_complex_expressions.php
```

**现象**: 解释器可正常执行，但 AOT 编译打印完配置抬头后立刻失败 `error: FileNotFound`，无额外错误信息。

**根因**: 未知。这些文件包含 `function` 声明/命名空间/复杂表达式等特性，解析时可能触发了 AOT 编译器内部的某些路径导致文件查找。也可能是由于 Zig 0.17 的 `std.Io.Dir.openFile()` API 适配问题（需要 `.{}` 打开标志的兼容性），或 `file.stat()` 在特定条件下返回 FileNotFound。

---

## 三、详细对比表

| 测试脚本 | 解释器 | AOT 编译 | 错误类型 |
|----------|--------|-----------|----------|
| `test_001_variables.php` | PASS | FAIL | OOM |
| `test_003_type_juggling.php` | PASS | FAIL | OOM |
| `test_006_loops_for.php` | PASS | FAIL | **SEGFAULT** |
| `test_007_loops_while.php` | PASS | FAIL | OOM |
| `test_008_loops_foreach.php` | PASS | FAIL | OOM |
| `test_009_functions_basic.php` | PASS | FAIL | **FileNotFound** |
| `test_010_closures.php` | PASS | FAIL | OOM |
| `test_012_arrays_basic.php` | PASS | FAIL | OOM |
| `test_018_magic_methods.php` | PASS | FAIL | OOM |
| `test_021_math_functions.php` | PASS | FAIL | OOM |
| `test_023_string_advanced.php` | PASS | FAIL | OOM |
| `test_029_callback.php` | PASS | FAIL | OOM |
| `test_030_variables_advanced.php` | PASS | FAIL | **FileNotFound** |
| `test_033_namespaces.php` | PASS | FAIL | **FileNotFound** |
| `test_047_readonly_props.php` | PASS | FAIL | OOM |
| `test_048_dnf_types.php` | PASS | FAIL | **FileNotFound** |
| `test_049_type_system.php` | PASS | FAIL | **FileNotFound** |
| `test_051_closures_advanced.php` | PASS | FAIL | OOM |
| `test_052_complex_expressions.php` | PASS | FAIL | **FileNotFound** |
| `test_056_superglobals.php` | PASS | FAIL | OOM |
| `test_057_output_buffering.php` | PASS | FAIL | OOM |
| `test_063_sorting_algorithms.php` | PASS | FAIL | OOM |
| `test_064_string_manipulation.php` | PASS | FAIL | OOM |
| `test_065_array_walk.php` | PASS | FAIL | OOM |
| `test_068_misc_functions.php` | PASS | FAIL | OOM |

---

## 四、问题雷达图

```
                  OOM (76%)
              ████████████████████
              ████████████████████
    FileNotFound (20%)     ██     SEGFAULT (4%)
              ████████████████████
              ████████████████████
              编译总失败率 100%
```

---

## 五、风险与建议

### 风险等级评估

| 问题 | 严重度 | 影响面 | 修复难度 |
|------|--------|--------|----------|
| Zig 编译 OOM | P0 | 76% 脚本阻塞 | 中 — 需优化 runtime_lib.zig 体积或增加内存 |
| `native_linker` segfault | P0 | 4% 脚本崩溃 | 高 — 内存安全问题需深入调试 |
| FileNotFound | P0 | 20% 脚本阻塞 | 中 — 需诊断文件打开失败的真实原因 |

### 后续修复建议

1. **P0 — OOM 问题**: `runtime_lib.zig` 高达 969KB，主要问题。建议拆分模板大小、使用条件编译移除不需要的运行时功能，或使用 `-OReleaseFast` 替代 `-OReleaseSmall`（某些场景内存更优）。
2. **P0 — Segfault**: `native_linker.zig::generateTerminatorSimple` 访问 `target.instructions` 时悬空指针。需检查 `target` 块的生命周期管理，确保在生成阶段所有引用均有效。
3. **P0 — FileNotFound**: 这 6 个文件触发了 AOT 编译器文件读取阶段的未知路径。建议在 `runAOTCompilation` 的 `openFile` 调用处添加详细日志，输出 `FileNotFound` 的确切调用位置。

---

*报告生成时间: 2025-06-14 10:01 UTC*  
*测试工具: AtomCode (deepseek-v4-flash)*  
*生成策略: 仅收集结果，未做任何代码调整*
