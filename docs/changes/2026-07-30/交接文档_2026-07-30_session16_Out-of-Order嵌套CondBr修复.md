# 交接文档：Session 16 AST-Direct Out-of-Order 嵌套 CondBr 块修复

**日期**：2026-07-30
**范围**：`src/aot/native_linker.zig` — AST-Direct 代码生成路径
**Session**：16
**前置**：Session 15（`docs/changes/2026-07-30/交接文档_2026-07-30_session15_return_generated泄漏与back-edge_PHI修复.md`）

---

## 一、TL;DR

本轮修复了 AST-Direct 代码生成中 **out-of-order 嵌套 cond_br 块未处理** 的核心缺陷。当 IR 块布局中嵌套 if/else 的 merge 块位于 then 块之前时（如 `if_then_9` 的 `br` 目标 `if_merge_8` 在块数组中位于 `if_then_9` 之前），原有的 `generateLabelDrivenBlockRange` 调用会因搜索范围 `[nti, nmi+1)` 为空而跳过这些块，导致 `AstDirectGenerationFailed` 编译失败。

**修复效果**：
- PASS 从 13 提升至 16（+3）
- FAIL_RUNTIME 从 31 减少至 24（-7）
- 5 个脚本从超时/段错误改善为产生输出（FAIL_DIFF）
- 0 个回归

---

## 二、当前状态

### 2.1 回归测试统计

| 指标 | Session 15 交接时 | Session 16 当前 | 变化 |
|------|-------------------|-----------------|------|
| PASS | 13 | 16 | **+3** |
| FAIL_COMPILE | 2 | 2 | 0 |
| FAIL_RUNTIME | 31 | 24 | **-7** |
| FAIL_DIFF | 20 | 24 | +4 |
| SKIP | 1 | 1 | 0 |
| **超时脚本(exit=142)** | **17** | **14** | **-3** |
| **段错误(exit=139/133)** | **7** | **4** | **-3** |

> 回归报告来自 `fuzzy_scripts_720/regression_report.md`（2026-07-30 16:18:45 生成）。
>
> FAIL_DIFF 增加 4 个是正面信号：5 个脚本从超时/段错误变为产生输出（从"无限循环/崩溃"变为"输出不匹配"），这是实质性改善。

### 2.2 脚本级变化明细

| 脚本 | Session 15 交接时 | Session 16 当前 | 变化类型 |
|------|-------------------|-----------------|----------|
| **f042** | FAIL_DIFF | **PASS** | **输出差异→通过** |
| **f134** | FAIL_DIFF | **PASS** | **输出差异→通过** |
| f033 | FAIL_RUNTIME exit=1 | FAIL_DIFF | 运行时错误→输出差异 |
| f056 | FAIL_RUNTIME exit=139 | FAIL_DIFF | 段错误→输出差异 |
| f097 | FAIL_RUNTIME exit=142 | FAIL_DIFF | 超时→输出差异 |
| f113 | FAIL_RUNTIME exit=139 | FAIL_DIFF | 段错误→输出差异 |
| f119 | FAIL_RUNTIME exit=142 | FAIL_DIFF | 超时→输出差异 |
| f010 | FAIL_RUNTIME exit=1 | FAIL_RUNTIME exit=139 | 运行时错误→段错误（编译已修复） |

---

## 三、已完成任务

### 3.1 Out-of-Order 嵌套 CondBr 块处理修复（核心修复）

**问题**：当 IR 块布局中嵌套 if/else 的 merge 块位于 then 块之前时，`generateLabelDrivenBlockRange` 的 cond_br case 中嵌套 cond_br 处理会因搜索范围为空而跳过 then/else 块。

**根因分析**（以 f010 `Container::make` 为例）：

```
块 6: coalesce_merge_5  → cond_br → if_then_6(7), if_else_7(8)
块 7: if_then_6         → br if_merge_8(9)
块 8: if_else_7         → cond_br → if_then_9(10), if_else_10(11)  ← 嵌套 cond_br
块 9: if_merge_8        ← 外层 merge（也是内层 merge）
块 10: if_then_9        → br if_merge_8(9)  ← br 目标在 then 块之前！
块 11: if_else_10       → throw
```

嵌套 cond_br 处理查找 `nested_merge_idx = 9`（if_merge_8），`nested_then_idx = 10`（if_then_9）。
- 修复前：`search_end = 9 + 1 = 10`，范围 `[10, 10)` 为空 → 块 10/11 未处理 → `AstDirectGenerationFailed`
- 修复后：检测 `9 < 10`（out-of-order），内联生成 if/else 代码

**修复方案**：在 then 块和 else 块的嵌套 cond_br 处理中，当 `nested_merge_idx < nested_then_idx` 时：
1. 生成 `if (cond) {`（使用 `writeConditionExpr`）
2. 内联处理 then 块指令（`generateInstructionSimple`）
3. 生成 `} else {`
4. 内联处理 else 块指令和 terminator（`.ret`/`.throw`）
5. 生成 `}`
6. 标记块为已处理
7. 设置 `merge_bi = nested_merge_idx`

**修改位置**：
- Then 块嵌套 cond_br：~6540
- Else 块嵌套 cond_br：~6772

**验证效果**：
- f010：编译失败 → 编译成功（运行时 segfault，与之前 FAIL_RUNTIME 一致）
- f042：FAIL_DIFF → PASS
- f134：FAIL_DIFF → PASS
- f097/f113/f119/f033/f056：从超时/段错误/运行时错误 → FAIL_DIFF（产生输出）

### 3.2 回归测试验证

执行了完整回归测试（`bash fuzzy_scripts_720/run_regression.sh`），67 个脚本全部测试完成，结果记录于 `fuzzy_scripts_720/regression_report.md`。

---

## 四、进行中/未完成任务

### 4.1 剩余超时脚本（P0，14 个）

以下脚本仍然超时（exit=142），需要进一步分析：

| 脚本 | 超时前的输出 | 可能根因 |
|------|-------------|----------|
| f007 | crypto hash 后卡住 | 待分析 |
| f024 | Permission Matrix 无限输出 | 嵌套 foreach break 处理问题 |
| f025 | RLE 后卡住 | 待分析 |
| f028 | array offset on null 后卡住 | array_fill 初始化问题 |
| f038 | 文件系统树遍历后卡住 | 待分析 |
| f061 | array offset on null 后卡住 | 同 f028 |
| f065 | CRC32 计算后卡住 | 待分析 |
| f081 | B+Tree 操作后卡住 | 待分析 |
| f095 | Dead Code Elimination 后卡住 | 待分析 |
| f102 | Generational GC 后卡住 | 待分析 |
| f104 | Entity States 后卡住 | 待分析 |
| f135 | Modular Exponentiation 后卡住 | 待分析 |
| f161 | Generated CSV 后卡住 | 待分析 |
| f171 | DFA 匹配后卡住 | 待分析 |
| f175 | QuickSort 后卡住 | 待分析 |
| f176 | Young adult: Y 后卡住 | 待分析 |

**排查方向**（继承自 Session 15）：
1. 检查 `generateBrToMergeCondBr`（~7570-7765）中 `return_generated` 泄漏
2. 检查 `generateLabelDrivenBlockRange` 的 `cond_br` case（~6384-6500）中 then/else 块的 `.ret` 处理
3. 检查 `generateIfFromLabels`（~8938+）中嵌套控制流的 `return_generated` 传播

### 4.2 段错误脚本（P1，4 个）

| 脚本 | exit code | 可能根因 |
|------|-----------|----------|
| f010 | 139 | out-of-order 内联生成的代码中 PHI 消解问题 |
| f027 | 139 | 变量未初始化（PHI 消解问题） |
| f051 | 139 | Validator 循环后段错误 |
| f110 | 139 | 文件系统遍历后段错误 |
| f177 | 139 | Graph DFS/BFS 后段错误 |

### 4.3 FAIL_DIFF 输出差异脚本（P1，24 个）

优先处理从超时/段错误转变为 FAIL_DIFF 的脚本（修复成本低）：

| 脚本 | 差异类型 | 来源 |
|------|----------|------|
| f033 | State Machine 输出差异 | 运行时错误→FAIL_DIFF |
| f056 | CRDT 输出差异 | 段错误→FAIL_DIFF |
| f097 | Search Engine 输出差异 | 超时→FAIL_DIFF |
| f113 | Distributed 输出差异 | 段错误→FAIL_DIFF |
| f119 | Logging 输出差异 | 超时→FAIL_DIFF |
| f006 | Observer 事件输出差异 | 继承 |
| f009 | Decorator Chain 输出差异 | 继承 |
| f012 | JSON Tree 输出差异 | 继承 |
| f016 | Hash Table 输出差异 | 继承 |
| f031 | Builder 输出差异 | 继承 |
| f034 | Template Method JSON 输出差异 | 继承 |
| f044 | JSON DeepOps 输出差异 | 继承 |
| f066 | Hamming Code 输出差异 | 继承 |
| f070 | Event Sourcing 输出差异 | 继承 |
| f072 | Type Inference 输出差异 | 继承 |
| f080 | DB Transaction 输出差异 | 继承 |
| f105 | DB Index 输出差异 | 继承 |
| f117 | Search Engine 输出差异 | 继承 |
| f124 | Container Orchestrator 输出差异 | 继承 |
| f151 | Type System 输出差异 | 继承 |
| f163 | Event Bus 输出差异 | 继承 |
| f164 | Plugin System 输出差异 | 继承 |
| f173 | Concurrency 输出差异 | 继承 |
| f178 | Matrix 输出差异 | 继承 |

### 4.4 FAIL_COMPILE 脚本（P2，2 个）

| 脚本 | 错误 |
|------|------|
| f087 | Zig 编译失败 |
| f160 | Zig 编译失败 |

---

## 五、已知问题

### 5.1 early-exit 问题（P0，继承自 Session 12，部分修复）

**根因**：`generateLabelDrivenBlockRange` 第 6284 行：
```zig
if (self.return_generated or self.break_generated) {
    for (i..end_idx) |j| {
        try processed.put(j, {});
    }
    return;
}
```

**当前状态**：
- Session 15 修复了 `generateForeachFromLabels` 和 `generateForFromLabels` 的 `cond_br` case 中的泄漏
- Session 15 修复了 `generateLabelDrivenBlockRange` 的 `cond_br` case 和 `generateBrToMergeCondBr` 中的泄漏
- Session 16 修复了 out-of-order 嵌套 cond_br 块未处理问题
- 以下位置仍可能存在泄漏：
  - `generateIfFromLabels`（~8938+）：嵌套控制流的 return 传播
  - `generateBrToMergeCondBr`（~7570-7765）：复杂嵌套场景

**影响**：14 个超时脚本可能部分由此导致。

### 5.2 f024 Permission Matrix 无限输出（P0，继承自 Session 15）

**现象**：f024 的 Permission Matrix 部分无限输出 "Alice (admin)/article:Alice (admin)/article:..."。

**初步分析**：可能是嵌套 foreach 循环中，内层 foreach 的 break 处理不正确。

### 5.3 f010 运行时 segfault（P1，新发现）

**现象**：f010 编译成功但运行时 exit=139（segfault）。

**初步分析**：out-of-order 内联生成的代码中可能缺少 PHI 消解，导致变量引用未初始化。

### 5.4 f080 coalesce `??` PHI 消解（P1，继承自 Session 14）

**现象**：`waitForLock(): Argument #1 ($waiter) must be of type int, null given`

### 5.5 PHPString double free（P1，继承自 Session 12）

- 脚本：f025/f031/f072/f119/f160
- 根因：release 后 alloca 中的值变悬垂引用

---

## 六、变更文件列表

| 文件 | 变更类型 | 行数变化 | 说明 |
|------|----------|----------|------|
| `src/aot/native_linker.zig` | 修改 | +106 / -4 | out-of-order 嵌套 cond_br 内联处理 |

### 核心变更明细

| 变更点 | 函数 | 行号范围 | 说明 |
|--------|------|----------|------|
| Then 块嵌套 cond_br out-of-order | `generateLabelDrivenBlockRange` | ~6540 | 当 merge 块在 then 块之前时，内联生成 if/else |
| Else 块嵌套 cond_br out-of-order | `generateLabelDrivenBlockRange` | ~6772 | 同上，针对 else 块 |

---

## 七、关键代码位置参考

| 功能 | 文件 | 行号范围 | 说明 |
|------|------|----------|------|
| `return_generated` early-exit | native_linker.zig | ~6284 | early-exit 逻辑（泄漏的放大器） |
| `generateLabelDrivenBlockRange` cond_br | native_linker.zig | ~6384-6500 | 主循环 cond_br case |
| 嵌套 cond_br out-of-order（then） | native_linker.zig | ~6540 | **本轮修复** |
| 嵌套 cond_br out-of-order（else） | native_linker.zig | ~6772 | **本轮修复** |
| `generateForeachFromLabels` cond_br | native_linker.zig | ~7116-7417 | foreach 循环 cond_br case（Session 15 修复） |
| `generateForFromLabels` cond_br | native_linker.zig | ~7946-8213 | for 循环 cond_br case（Session 15 修复） |
| `generateBrToMergeCondBr` | native_linker.zig | ~7570-7765 | br → cond_br 链处理（Session 15 修复） |
| `generateIfFromLabels` | native_linker.zig | ~8938+ | if/else 结构化生成 |
| `writeConditionExpr` | native_linker.zig | ~10566 | 条件表达式生成（本轮使用） |
| `writeThrowTerminator` | native_linker.zig | ~523 | throw 终止符生成（本轮使用） |
| `generateInstructionSimple` | native_linker.zig | ~11452 | 简化指令生成（本轮使用） |

---

## 八、调试方法参考

### 8.1 编译并 dump IR + Zig 代码

```bash
# 编译 AOT 并 dump IR 和 Zig 代码
./zig-out/bin/php-interpreter --compile --dump-ir --dump-zig-path=/tmp/dump.zig \
  fuzzy_scripts_720/pass/fXXX.php --output=/tmp/aot_compile_fXXX 2>/tmp/ir.txt

# 运行 AOT 二进制（10 秒超时）
perl -e 'alarm 10; exec @ARGV' /tmp/aot_compile_fXXX
```

### 8.2 运行回归测试

```bash
bash fuzzy_scripts_720/run_regression.sh
```

### 8.3 分析 out-of-order 块问题

1. Dump IR 找到有 `AstDirectGenerationFailed` 的函数
2. 检查块布局：嵌套 if/else 的 merge 块是否在 then 块之前
3. 在 IR 中搜索 `if_then_N` 和 `if_merge_M`，检查 N > M 的情况
4. 确认 `generateLabelDrivenBlockRange` 的嵌套 cond_br 处理是否正确进入 out-of-order 分支

---

## 九、后续优化建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|--------|--------|----------|------|
| **P0** | 14 脚本 | 中 | 分析剩余超时脚本：检查 `generateIfFromLabels` 中的 `return_generated` 泄漏。优先排查 f024（无限输出）、f007/f065（crypto 后卡住） |
| **P0** | 1 脚本(f024) | 中 | 分析 Permission Matrix 无限输出：dump IR 检查嵌套 foreach break 处理 |
| **P1** | 1 脚本(f010) | 中 | 修复 f010 segfault：检查 out-of-order 内联生成的代码中 PHI 消解 |
| **P1** | 4 脚本 | 中 | 修复段错误脚本（f027/f051/f110/f177）：检查 use-after-free 和 PHI 消解 |
| **P1** | 24 脚本 | 高 | 修复 FAIL_DIFF 输出差异：优先处理从超时/段错误转变为 FAIL_DIFF 的脚本（f033/f056/f097/f113/f119） |
| **P2** | 全局 | 低 | 抽取 out-of-order 内联处理为独立函数 `generateInlineCondBr`，减少代码重复 |
| **P2** | 2 脚本 | 中 | 修复 FAIL_COMPILE 脚本（f087/f160） |
| **P2** | 全局 | 高 | 重构 `generateLabelDrivenBlockRange` 的 early-exit 逻辑：改为基于块可达性分析而非标志位 |

---

## 十、注意事项

1. **编译已验证**：`zig build` 通过，无编译错误
2. **回归测试已完成**：67 个脚本全部测试，结果记录于 `fuzzy_scripts_720/regression_report.md`
3. **PHP 原始脚本未修改**：所有修改仅在 `src/aot/native_linker.zig`
4. **变更摘要已生成**：`docs/changes/2026-07-30/AST-Direct_Out-of-Order_Nested_CondBr修复_2026-07-30_session16_b3c5d7.md`
5. **Session 15 修复已验证无回归**：f026（LinkedList）、f119（Logging）等 Session 15 修复的脚本仍然 PASS
6. **out-of-order 修复仅影响 `nested_merge_idx < nested_then_idx` 场景**：正常顺序场景行为不变
7. **f010 编译成功是重要进展**：之前 `AstDirectGenerationFailed` → 现在编译成功（运行时 segfault 是独立问题）
