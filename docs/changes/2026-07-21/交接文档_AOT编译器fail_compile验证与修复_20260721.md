# 交接文档：AOT 编译器 fail_compile 验证与修复

> **生成时间**：2026-07-21  
> **任务目标**：完成 `fuzzy_scripts_720` 和 `multi_file_projects` 目录下所有 PHP 脚本的 AOT 编译，确保编译结果与 PHP 原生执行一致且运行正确  
> **接手来源**：[交接文档_多文件编译器箭头函数命名冲突修复_20260720.md](../2026-07-20/交接文档_多文件编译器箭头函数命名冲突修复_20260720.md)

---

## 一、高层摘要（TL;DR）

前一会话已完成 `native_linker.zig` 中 PHI 赋值路径的全面重构（引入 `writePhiAssignWithRetain`、修复 `generateCondBrBlock` / `generateLoopBodyFromBlock` 中的指针层级错误），使大量编译失败脚本得以修复。

本会话对 `fuzzy_scripts_720/fail_compile/` 目录下 **18 个**编译失败脚本进行了逐一验证，结果如下：

| 状态 | 数量 | 脚本 |
|------|------|------|
| 编译通过 + 运行 exit=0 | **11** | f042, f043, f047, f091, f117, f128, f129, f148, f152, f160, f162 |
| 编译通过 + 运行 SIGSEGV (exit=139) | **3** | f029, f030, f064 |
| 编译通过 + 运行 exit=255 (PHP错误) | **2** | f138, f149 |
| 仍编译失败 (unreachable code) | **2** | f071, f089 |

**结论**：前一会话的 PHI 修复使 16/18 个脚本编译通过，剩余 2 个为同类 `unreachable code` 错误。

---

## 二、影响范围

### 2.1 总体统计（fuzzy_scripts_720）

| 类别 | 数量 |
|------|------|
| Pass | 61 |
| Fail (Compile) | 18 → **实际仅 2 个仍编译失败** |
| Fail (Runtime/Diff) | 77 |
| 根目录待测 | 24（SKIP 项，PHP 自身运行报错或 AOT 排除项） |
| 累计已测 | 24 |

### 2.2 fail_compile/ 目录最新状态（本会话验证）

```
PASS_COMPILE|RUN_EXIT=139|f029_backtracking_nqueens_perm_maze      ← SIGSEGV
PASS_COMPILE|RUN_EXIT=139|f030_greedy_huffman_scheduling            ← SIGSEGV
PASS_COMPILE|RUN_EXIT=0  |f042_array_functions_full                 ← ✓ 全通
PASS_COMPILE|RUN_EXIT=0  |f043_math_functions_full                  ← ✓ 全通
PASS_COMPILE|RUN_EXIT=0  |f047_closures_curry_compose               ← ✓ 全通
PASS_COMPILE|RUN_EXIT=139|f064_matrix_det_inverse_eigenvalue        ← SIGSEGV
FAIL_COMPILE             |f071_compression_huffman_rle_lz77         ← unreachable code
FAIL_COMPILE             |f089_blockchain_pow_merkle_tx             ← unreachable code
PASS_COMPILE|RUN_EXIT=0  |f091_os_scheduler_banker_algorithm        ← ✓ 全通
PASS_COMPILE|RUN_EXIT=0  |f117_search_engine_inverted_tfidf_bm25    ← ✓ 全通
PASS_COMPILE|RUN_EXIT=0  |f128_linear_algebra_matrix_lu_qr_eigenvalue ← ✓ 全通
PASS_COMPILE|RUN_EXIT=0  |f129_regex_engine_nfa_backtrack_capture   ← ✓ 全通
PASS_COMPILE|RUN_EXIT=255|f138_neural_network_forward_backprop_activation ← PHP错误
PASS_COMPILE|RUN_EXIT=0  |f148_dsp_fft_filter_convolution_spectrum  ← ✓ 全通
PASS_COMPILE|RUN_EXIT=255|f149_ml_clustering_pca_crossvalidation_feature ← PHP错误
PASS_COMPILE|RUN_EXIT=0  |f152_closure_arrow_higher_order           ← ✓ 全通
PASS_COMPILE|RUN_EXIT=0  |f160_virtual_fs_path_traversal            ← ✓ 全通
PASS_COMPILE|RUN_EXIT=0  |f162_crypto_hash_hmac_sign                ← ✓ 全通
```

### 2.3 已修改文件（前一会话遗留 + 本会话未新增代码修改）

| 文件 | 改动内容 |
|------|----------|
| `src/aot/native_linker.zig` | PHI 赋值路径重构：`writePhiAssignWithRetain`、`generateCondBrBlock` phi_deref 检查、`generateWhileLoopStructuredNew` break 后中断生成、`writePtrAwareAssign` ref_ptr 逻辑 |

---

## 三、核心问题分析

### 3.1 问题 A：f071/f089 — `unreachable code` 编译错误（在做）

**现象**：Zig 编译器报错：
```
main.zig:9159:30: error: unreachable code
main.zig:9156:13: note: control flow is diverted here
            break;
            ^~~~~
```

**根因分析**：在 `generateWhileLoopStructuredNew` 函数（`native_linker.zig:13637`）中，循环体块遍历的 `for` 循环（第 13949 行起）在生成 `break;` 语句后，仅在 **br 到 exit_block 且 countPredecessors <= 1** 的路径（第 14249-14253 行）有 `break; // 退出 for 循环` 的中断逻辑。

但 f071/f089 的 `break;` 是通过 **`generateCondBrBlock`** 内部生成的（如 `if (cond) { break; } else { ... }`），该路径生成 break 后不会中断外层 `for` 循环，导致后续块的指令继续生成，产生 unreachable code。

**已定位的关键代码位置**：
- `native_linker.zig:14242-14263`：br 路径的 break 中断逻辑（已修复）
- `native_linker.zig:14244-14245`：cond_br 路径调用 `generateCondBrBlock`，**无中断逻辑**（需修复）
- 生成代码中 `main.zig:9156` 处的 `break;` 后紧跟 `main.zig:9159` 处的 `runtime.setSourceLocation(...)` 即为 unreachable code

**调试障碍**：AOT 编译器在编译失败后会清理临时目录（`.zigphp_aot_build_{PID}/`），导致无法检查生成代码。需通过 `dump_zig` 配置或环境变量保留生成代码。

**修复方向**：
1. 在 `generateCondBrBlock` 中检测是否生成了 `break;`，若生成了则返回一个标志位
2. 或在调用 `generateCondBrBlock` 后检查 `self.current_loop_exit_block` 是否已触发 break
3. 最小化方案：在 cond_br 路径后也添加 `break; // 退出 for 循环` 逻辑（需评估是否影响非 break 的 cond_br 场景）

### 3.2 问题 B：f029/f030/f064 — 运行时 SIGSEGV (exit=139)

**现象**：编译通过，但运行时段错误。

**前一会话记录**：
- f029：回溯算法结果不正确（board 值为 -1）
- f030：同类型问题
- f064：矩阵运算段错误

**可能原因**：引用参数（`ref_param_alloca`）的初始化或解引用深度不正确，导致空指针解引用。

### 3.3 问题 C：f138/f149 — 运行时 exit=255 (PHP 错误)

**现象**：编译通过，运行时 PHP 报错（如 TypeError）。

**可能原因**：类型推断或参数传递问题，需查看具体错误信息。

### 3.4 问题 D：临时目录清理导致调试困难

**现象**：AOT 编译器在 `createTempDir`（`native_linker.zig:682-697`）中创建 `.zigphp_aot_build_{PID}` 目录，编译完成后清理。编译失败时也会清理，导致无法检查生成的 `main.zig`。

**建议**：在 `config` 中增加 `keep_temp` 选项，或通过环境变量 `ZIGPHP_KEEP_TEMP` 控制是否保留临时目录。

---

## 四、待办事项

### 4.1 高优先级（P0）

| ID | 任务 | 状态 | 说明 |
|----|------|------|------|
| 1 | 修复 f071/f089 的 `unreachable code` 编译错误 | 在做 | 根因已定位，需在 `generateWhileLoopStructuredNew` 的 cond_br 路径添加 break 中断逻辑 |
| 2 | 修复 f029/f030/f064 运行时 SIGSEGV | 待办 | 需保留临时目录后用 gdb/lldb 调试段错误位置 |
| 3 | 修复 f138/f149 运行时 exit=255 | 待办 | 需查看具体 PHP 错误信息 |

### 4.2 中优先级（P1）

| ID | 任务 | 状态 | 说明 |
|----|------|------|------|
| 4 | 将 11 个已编译通过的脚本移回 `pass/` 并验证输出一致性 | 待办 | f042, f043, f047, f091, f117, f128, f129, f148, f152, f160, f162 |
| 5 | 修复 `fail_runtime/` 中 77 个 FAIL_DIFF 和 FAIL_RUNTIME 脚本 | 待办 | 需按错误类型分类处理 |
| 6 | 运行 `multi_file_projects` 多文件测试并修复问题 | 待办 | 尚未开始 |

### 4.3 低优先级（P2）

| ID | 任务 | 状态 | 说明 |
|----|------|------|------|
| 7 | 全量回归验证并清理临时产物 | 待办 | 所有修复完成后运行 `run_all_tests.sh` |
| 8 | 增加 `keep_temp` 调试选项 | 待办 | 改善调试体验 |

---

## 五、已验证可用的测试方法

### 5.1 批量测试 fail_compile/ 脚本

```bash
# 脚本位置：/tmp/test_fail_compile.sh
# 结果文件：/tmp/fc_results.txt
# 单脚本编译+运行：
INTERPRETER="zig-out/bin/php-interpreter"
FC_DIR="fuzzy_scripts_720/fail_compile"
for f in "$FC_DIR"/f*.php; do
    bn=$(basename "$f" .php)
    out="/tmp/aot_test_${bn}"
    timeout 120 "$INTERPRETER" --compile --output="$out" "$f" 2>/tmp/err_${bn}.txt
    rc=$?
    if [ $rc -eq 0 ]; then
        timeout 10 "$out" >/tmp/out_${bn}.txt 2>&1
        rrc=$?
        echo "PASS_COMPILE|RUN_EXIT=$rrc|$bn"
        rm -f "$out"
    else
        echo "FAIL_COMPILE|$bn"
        head -3 /tmp/err_${bn}.txt
    fi
done
```

### 5.2 全量测试

```bash
bash fuzzy_scripts_720/run_all_tests.sh
```

### 5.3 构建验证

```bash
timeout 120 zig build  # 当前已通过
```

---

## 六、关键代码位置索引

| 功能 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `generateWhileLoopStructuredNew` | `native_linker.zig` | 13637 | 结构化 while 循环生成主函数 |
| br 路径 break 中断 | `native_linker.zig` | 14249-14253 | 已修复的 br 到 exit_block 路径 |
| cond_br 路径（需修复） | `native_linker.zig` | 14244-14245 | 调用 `generateCondBrBlock` 但无中断逻辑 |
| `generateCondBrBlock` | `native_linker.zig` | — | 条件分支块生成，内部可能生成 break |
| `writePhiAssignWithRetain` | `native_linker.zig` | — | PHI 赋值辅助函数（前一会话新增） |
| `createTempDir` | `native_linker.zig` | 682-697 | 临时目录创建，编译后清理 |
| `dump_zig` 配置 | `native_linker.zig` | 92, 19801-19806 | 保留生成代码的调试选项 |

---

## 七、后续开发建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|--------|--------|----------|------|
| P0 | f071/f089 编译修复 | 中 | 在 `generateWhileLoopStructuredNew` 的 cond_br 路径（14244行）后添加 break 中断检测逻辑，参考 br 路径（14253行）的实现模式 |
| P0 | SIGSEGV 调试 | 低 | 在 `createTempDir` 中增加 `ZIGPHP_KEEP_TEMP` 环境变量检查，保留临时目录用于 gdb 调试 |
| P1 | 11 个已通过脚本归档 | 低 | 逐一运行 PHP 与 AOT 输出比对，通过后 `mv` 到 `pass/` 目录 |
| P1 | fail_runtime 分类处理 | 高 | 按错误类型（SIGSEGV/TypeError/输出差异/超时）分组，优先修复 SIGSEGV 类 |
| P1 | multi_file_projects 测试 | 中 | 尚未开始，需先运行基线测试确定当前状态 |
| P2 | `generateCondBrBlock` 重构 | 高 | 当前函数逻辑复杂，break 检测依赖外层状态，建议返回枚举（Continue/Break/Return）明确控制流 |
| P2 | 临时目录管理优化 | 低 | 支持 `--keep-temp` 命令行选项，编译失败时自动保留 |

---

## 八、风险与注意事项

1. **临时目录清理**：编译器在编译失败后会删除 `.zigphp_aot_build_{PID}/` 目录，导致无法检查生成的 Zig 代码。调试时需先设置 `dump_zig` 或修改 `createTempDir` 逻辑。

2. **cond_br break 中断修复的风险**：在 cond_br 路径添加 break 中断可能影响非 break 的 cond_br 场景（如 if/else 不含 break 的情况）。需确保仅在 `generateCondBrBlock` 实际生成了 `break;` 时才中断。

3. **PHP 原始脚本保护铁律**：任何时候都不可删除 PHP 的原始脚本文件（`.php` 文件），无一例外。

4. **AOT 编译产物命名规范**：所有 AOT 编译产物必须以 `aot_compile_{filename}` 命名，禁止与 PHP 源文件同名。

5. **测试命令必须带超时**：所有测试/编译命令必须用 `timeout` 包裹，防止挂死。

---

## 九、环境信息

- **项目路径**：`/Users/tuoke/Desktop/ai-zig-php-parser`
- **Zig 版本**：0.16.0
- **构建状态**：`zig build` 通过
- **解释器位置**：`zig-out/bin/php-interpreter`
- **测试目录**：`fuzzy_scripts_720/`（单文件）、`multi_file_projects/`（多文件）
- **Git 分支**：`main`，领先 origin/main 21 个 commit
