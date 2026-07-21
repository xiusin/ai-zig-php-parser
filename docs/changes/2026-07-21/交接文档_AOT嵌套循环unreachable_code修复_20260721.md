# 交接文档：AOT 嵌套循环 unreachable code 修复

> **生成时间**：2026-07-21  
> **任务目标**：修复 f071/f089 的 `unreachable code` 编译错误，使全部 18 个 fail_compile 脚本编译通过  
> **接手来源**：[交接文档_AOT编译器fail_compile验证与修复_20260721.md](交接文档_AOT编译器fail_compile验证与修复_20260721.md)

---

## 一、高层摘要（TL;DR）

前一会话定位到 f071/f089 的 `unreachable code` 根因在 `generateWhileLoopStructuredNew` 的嵌套循环体 for 循环中：`generateBrChain` 因 br-to-exit_block 生成 `break;` 后，for 循环未中断，继续生成后续块的指令，产生不可达代码。

本会话完成修复：

1. **根因定位**：在 `native_linker.zig` 的嵌套循环体 for 循环（原 14112 行）中，`generateBrChain`（13276-13281 行）检测到 br 目标 == `current_loop_exit_block` 时生成 `break;`（退出 while 循环），但调用者 for 循环不感知此 break，继续生成后续块
2. **修复方案**：增加 `nested_broke_out` 标志，在 `generateBrChain` 生成 break 后设置标志并退出 for 循环；同时跳过 break 后的 phi 更新（因 phi 更新在 while 循环内、break 之后，不可达）
3. **验证结果**：18/18 fail_compile 全部编译通过（零编译失败），f071/f089 的 `unreachable code` 错误消除

---

## 二、影响范围

### 2.1 fail_compile 全部脚本最新状态

```
PASS_COMPILE|RUN_EXIT=139|f029_backtracking_nqueens_perm_maze      ← SIGSEGV（运行时问题）
PASS_COMPILE|RUN_EXIT=139|f030_greedy_huffman_scheduling            ← SIGSEGV
PASS_COMPILE|RUN_EXIT=0  |f042_array_functions_full                 ← ✓
PASS_COMPILE|RUN_EXIT=0  |f043_math_functions_full                  ← ✓
PASS_COMPILE|RUN_EXIT=0  |f047_closures_curry_compose               ← ✓
PASS_COMPILE|RUN_EXIT=139|f064_matrix_det_inverse_eigenvalue        ← SIGSEGV
PASS_COMPILE|RUN_EXIT=139|f071_compression_huffman_rle_lz77         ← SIGSEGV（新暴露）
PASS_COMPILE|RUN_EXIT=0  |f089_blockchain_pow_merkle_tx             ← ✓（新通过）
PASS_COMPILE|RUN_EXIT=0  |f091_os_scheduler_banker_algorithm        ← ✓
PASS_COMPILE|RUN_EXIT=0  |f117_search_engine_inverted_tfidf_bm25    ← ✓
PASS_COMPILE|RUN_EXIT=0  |f128_linear_algebra_matrix_lu_qr_eigenvalue ← ✓（输出有差异）
PASS_COMPILE|RUN_EXIT=0  |f129_regex_engine_nfa_backtrack_capture   ← ✓（输出有差异）
PASS_COMPILE|RUN_EXIT=255|f138_neural_network_forward_backprop_activation ← PHP错误
PASS_COMPILE|RUN_EXIT=0  |f148_dsp_fft_filter_convolution_spectrum  ← ✓
PASS_COMPILE|RUN_EXIT=255|f149_ml_clustering_pca_crossvalidation_feature ← PHP错误
PASS_COMPILE|RUN_EXIT=0  |f152_closure_arrow_higher_order           ← ✓
PASS_COMPILE|RUN_EXIT=0  |f160_virtual_fs_path_traversal            ← ✓
PASS_COMPILE|RUN_EXIT=0  |f162_crypto_hash_hmac_sign                ← ✓
```

| 状态 | 数量 | 脚本 |
|------|------|------|
| 编译通过 + exit=0 | **12** | f042, f043, f047, f089, f091, f117, f128, f129, f148, f152, f160, f162 |
| 编译通过 + SIGSEGV (139) | **5** | f029, f030, f064, f071 |
| 编译通过 + exit=255 | **2** | f138, f149 |
| **编译失败** | **0** | **无！全部通过！** |

### 2.2 已修改文件

| 文件 | 改动内容 |
|------|----------|
| `src/aot/native_linker.zig` | 嵌套循环体 for 循环（原 14112 行区域）增加 `nested_broke_out` 标志：(1) `generateBrChain` 生成 break 后设置标志并退出 for 循环；(2) 跳过 break 后的 phi 更新 |

---

## 三、核心问题分析

### 3.1 已修复：f071/f089 — `unreachable code` 编译错误

**根因**：`generateWhileLoopStructuredNew` 的嵌套循环体 for 循环（原 14112 行）遍历 `nested_body_indices` 时，对每个块的 br 终止符调用 `generateBrChain`。`generateBrChain`（13276-13281 行）检测到 br 目标 == `current_loop_exit_block` 时生成 `break;`（退出生成的 Zig while 循环），但调用者 for 循环不感知此 break，继续生成后续块的指令，导致 `break;` 后的代码不可达。

**修复**：
1. 增加 `var nested_broke_out = false;` 标志
2. `generateBrChain` 调用后检查 `nb_target_idx == self.current_loop_exit_block`，若匹配则设置 `nested_broke_out = true` 并 `break;`（退出 native_linker.zig 的 for 循环）
3. phi 更新段用 `if (!nested_broke_out) { ... }` 包裹，跳过 break 后不可达的 phi 更新

**验证**：f071/f089 编译均通过，无 `unreachable code` 错误。

### 3.2 待修复：f029/f030/f064/f071 — 运行时 SIGSEGV (exit=139)

**现象**：编译通过，运行时段错误。

**f071 崩溃分析**（lldb 回溯）：
- 崩溃地址：`0x105f38038`（堆地址，疑 use-after-free）
- 崩溃位置：`main + 301056`，在 `LZ77::compress` 函数内
- 崩溃前输出：`Huffman: 135 bytes`，崩溃于 LZ77 压缩调用
- 伴随警告：`Trying to access array offset on null`（PHP 第 150 行，`$result[$start + $i]`）

**f029/f030/f064**：前一会话记录，回溯算法结果不正确（board 值为 -1）、矩阵运算段错误。

**共同根因推断**：嵌套循环中 br-to-exit 路径的 phi 处理不正确，导致变量在循环迭代间丢失值（null 或 use-after-free）。`nested_broke_out` 修复正确跳过了 break 后不可达的 phi 更新，但 break 前的变量初始化/引用参数传递可能仍有问题。

### 3.3 待修复：f138/f149 — 运行时 exit=255 (PHP TypeError)

**f138 具体错误**：
```
Fatal error: Uncaught TypeError: NeuralLayer::backward(): Argument #1 ($outputGrad) must be of type Matrix2D, null given
```
- PHP 第 170 行：`$grad = $this->layers[$i]->backward($grad, $lr);`
- `$grad` 在循环迭代间通过 phi 节点传递，若 phi 更新缺失则 $grad 变 null
- 与 SIGSEGV 同类问题：循环 phi 更新不正确

**f149**：类似 PHP 错误，需进一步查看具体错误信息。

---

## 四、待办事项

### 4.1 高优先级（P0）

| ID | 任务 | 状态 | 说明 |
|----|------|------|------|
| 1 | 修复 f029/f030/f064/f071 SIGSEGV | 待办 | 共同类：嵌套循环 phi 更新/引用参数处理。需深入调试 phi 更新机制 |
| 2 | 修复 f138/f149 exit=255 | 待办 | 同类：循环 phi 更新导致变量 null。f138 根因已定位（$grad phi 丢失） |

### 4.2 中优先级（P1）

| ID | 任务 | 状态 | 说明 |
|----|------|------|------|
| 3 | 将 12 个已编译通过脚本移回 pass/ | 待办 | f042,f043,f047,f089,f091,f117,f128,f129,f148,f152,f160,f162 |
| 4 | 修复 f128/f129 输出差异 | 待办 | f128 有矩阵值差异+null警告，f129 有 PHP 警告差异（pre-existing） |
| 5 | 修复 fail_runtime/ 77 个脚本 | 待办 | 按错误类型分类处理 |
| 6 | 运行 multi_file_projects 测试 | 待办 | 尚未开始 |

### 4.3 低优先级（P2）

| ID | 任务 | 状态 | 说明 |
|----|------|------|------|
| 7 | 全量回归验证 | 待办 | 所有修复完成后运行 `run_all_tests.sh` |
| 8 | 增加 keep_temp 调试选项 | 待办 | 改善调试体验 |

---

## 五、关键代码位置索引

| 功能 | 文件 | 行号（修复后约） | 说明 |
|------|------|------|------|
| 嵌套循环体 for 循环 | `native_linker.zig` | ~14112 | `nested_broke_out` 标志、break 检测、phi 跳过 |
| `generateBrChain` | `native_linker.zig` | ~13276 | br-to-exit_block 生成 break 的逻辑 |
| `generateCondBrBlock` | `native_linker.zig` | ~12927 | 条件分支块生成（cond_br 路径未加 break 中断） |
| 嵌套循环 phi 更新 | `native_linker.zig` | ~14180 | `if (!nested_broke_out)` 包裹 |
| 嵌套循环 cleanup 块 | `native_linker.zig` | ~14213 | else_idx_nl 块指令生成（phi 跳过） |

---

## 六、调试方法

### 6.1 保留生成代码

```bash
timeout 120 zig-out/bin/php-interpreter --compile --dump-zig-path=/tmp/debug.zig --output=/tmp/aot_out script.php
```

### 6.2 lldb 调试 SIGSEGV

```bash
timeout 15 lldb -o run -o bt -o quit /tmp/aot_out 2>&1 | grep -E "stop reason|frame #"
```

### 6.3 批量测试 fail_compile

```bash
INTERPRETER="zig-out/bin/php-interpreter"
FC_DIR="fuzzy_scripts_720/fail_compile"
for f in "$FC_DIR"/f*.php; do
    bn=$(basename "$f" .php)
    out="/tmp/aot_test_${bn}"
    timeout 120 "$INTERPRETER" --compile --output="$out" "$f" 2>/dev/null
    rc=$?
    if [ $rc -eq 0 ]; then
        timeout 10 "$out" >/dev/null 2>&1
        rrc=$?
        echo "PASS_COMPILE|RUN_EXIT=$rrc|$bn"
        rm -f "$out"
    else
        echo "FAIL_COMPILE|$bn"
    fi
done
```

---

## 七、后续开发建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|--------|--------|----------|------|
| P0 | SIGSEGV+exit=255 共 7 脚本 | 高 | 深入调试嵌套循环 phi 更新机制：(1) 在 break 前生成 exit_block 的 phi 赋值（当前 cleanup 块跳过 phi）；(2) 检查 br-to-exit 是否需要先生成 phi 拷贝再 break |
| P0 | f138 具体 | 中 | 检查 for 循环中 `$grad = backward($grad)` 的 phi 更新：返回值是否正确写入 phi 寄存器 |
| P1 | 12 脚本归档 | 低 | 逐一运行 PHP 与 AOT 输出比对，通过后 mv 到 pass/ |
| P1 | f128/f129 差异 | 中 | 检查矩阵运算中 null 警告根因（可能与 phi 更新同类） |
| P2 | cond_br 路径 | 高 | 当前 `generateCondBrBlock` 内部生成 break 后也不中断外层 for 循环，若两分支均 break 则有同类 unreachable code 风险。建议返回枚举（Continue/Break/Return）明确控制流 |
| P2 | 临时目录管理 | 低 | 支持 `--keep-temp` 命令行选项，编译失败时自动保留 |

---

## 八、风险与注意事项

1. **phi 更新跳过的安全性**：`nested_broke_out` 跳过 phi 更新是安全的（break 后 phi 不可达），但 break **前**的变量初始化/引用参数传递可能仍有问题，需进一步排查
2. **f128/f129 输出差异**：不是本修复引入的回归（git stash 验证 f129 修复前已有 DIFF），但 f128 在无 PHI 修复时编译失败无法对比
3. **PHP 原始脚本保护铁律**：任何时候不可删除 PHP 原始脚本文件
4. **AOT 编译产物命名**：必须以 `aot_compile_{filename}` 命名
5. **测试命令必须带超时**：所有测试/编译命令必须用 `timeout` 包裹

---

## 九、环境信息

- **项目路径**：`/Users/tuoke/Desktop/ai-zig-php-parser`
- **Zig 版本**：0.16.0
- **构建状态**：`zig build` 通过
- **解释器位置**：`zig-out/bin/php-interpreter`
- **测试目录**：`fuzzy_scripts_720/`（单文件）、`multi_file_projects/`（多文件）
- **Git 分支**：`main`，领先 origin/main 22 commits
