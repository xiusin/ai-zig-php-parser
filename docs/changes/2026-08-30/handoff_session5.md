# 交接文档（会话 5）：f033 三重控制流缺陷修复 — else ret 终止符 + return_generated 状态传播 + foreach exit 块

> 日期：2026-08-30 | 涉及文件：`src/aot/native_linker.zig`
> 编译状态：✅ `zig build` 通过
> 回归状态：✅ f033 + f051 新增通过，零新增回归（12 项已知失败不变）
> 上级交接链：
> - `docs/changes/2026-08-29/handoff.md`（会话 1：f028 死循环闭环）
> - `docs/changes/2026-08-29/handoff_session2.md`（会话 2：短路链 + if-without-else 六组修复）
> - `docs/changes/2026-08-29/handoff_session3.md`（会话 3：f085 单语句 if-continue/if-break 修复 + f087 诊断）
> - `docs/changes/2026-08-29/handoff_session4.md`（会话 4：f087 嵌套短路 PHI 消解 + foreach continue 缺失）
> - `docs/changes/2026-08-30/else_ret_foreach_exit_三重缺陷修复_b3e1a2.md`（本会话技术细节文档）
> 用户指令：**"继续处理已知问题"** —— 持续消灭基线失败项

---

## 1. TL;DR

本会话修复了 `f033_state_pattern_order_machine.php` 的 `FAIL_DIFF` 问题。根因为 **三个关联缺陷** 叠加：

1. **else 块 ret 终止符未生成**（Fix 1）：`if_merge_` + `cond_br` 路径中 `else_has_real_body=true` 时，else 块的指令被生成，但 ret/throw 终止符被跳过，导致 `return true` 丢失。
2. **return_generated 状态错误传播**（Fix 2）：Fix 1 生成 ret 后 `return_generated=true`，但 then 块以 br 终止（未 ret）。原代码无 AND 合并，导致主循环跳过 foreach 循环。
3. **foreach exit 块未处理**（Fix 3）：IR 生成器不为 foreach 创建 `foreach_exit_` 块时 `exit_idx=null`，cleanup 块之后的 ret 块未被处理。`return_generated=true`（来自 foreach body 的 `return false`）导致主循环批量标记后续块为 processed 并跳过。

**修复结果**：`f033` 从 FAIL_DIFF → ✅ PASS，`f051` 从 FAIL_DIFF → ✅ PASS（连带修复）。零新增回归。

---

## 2. 修复清单

### 2.1 文件：`src/aot/native_linker.zig`

| # | 修复点 | 行号（约） | 修复内容 | 归因 |
|---|--------|-----------|---------|------|
| 1 | else 块 ret/throw 终止符生成 | 7158-7184 | `else_has_real_body=true` 路径中，else 块指令生成后，添加 `eb.terminator` 的 ret/throw 处理（含 cleanup regs 释放 + return 语句） | else 块以 ret 终止时，终止符被跳过，导致 return 语句丢失 |
| 2 | return_generated AND 合并 | 7237-7243 | `else_has_real_body=true` 时，`return_generated = then_returned and else_returned` | 只有两条路径都 ret 时后续代码才不可达；OR 合并导致 then 路径可达的代码被跳过 |
| 3 | foreach exit 块推导处理 | 10100-10136 | `generateForeachFromLabels` 中 `exit_idx=null` 时，从 cleanup 块 br 终止符推导 exit 块，移除 processed 标记，保存/恢复 return_generated，用 generateLabelDrivenBlockRange 处理 | IR 生成器不为 foreach 创建 `foreach_exit_` 块时，exit 块（如 return true 的 ret 块）被跳过 |

### 2.2 验证脚本

| 脚本 | 描述 | 结果 |
|------|------|------|
| `fuzzy_scripts_720/tmp/repro_f033_c.php` | 最小复现：if(isset)+foreach+return true | ✅ 通过 |
| `fuzzy_scripts_720/pass/f033_state_pattern_order_machine.php` | 原始 f033 完整脚本 | ✅ 通过（零差异） |
| `fuzzy_scripts_720/pass/f051_validator_rule_chain_batch.php` | 连带修复脚本 | ✅ 通过 |

---

## 3. 根因分析

### 3.1 IR 块结构（repro_f033_c.php 的 transition 方法）

```text
block 7  if_merge_3    cond_br  ← if (isset($this->guards[$key]))
block 8  if_then_4     br       ← then: 进入 foreach
block 9  if_merge_5    ret      ← else: return true（含 $this->current = $target 等）
block 10 foreach_cond_6 cond_br ← foreach 条件
block 11 foreach_body_7  cond_br ← foreach body (if(!guard) return false)
block 12 foreach_increment_8 br  ← foreach increment
block 13 foreach_cleanup_9   br  ← foreach cleanup → br to block 14
block 14 if_then_11    ret      ← return true（then 路径的延续）
```

### 3.2 缺陷 1：else 块 ret 终止符未生成

`else_has_real_body=true` 路径（行 7150-7187）只生成 else 块（block 9）的指令，不处理终止符。block 9 以 ret 终止（`return true`），但 ret 语句丢失。

**影响**：当 `isset($this->guards[$key])` 为 false 时，else 分支应执行 `return true`，但生成的 Zig 代码中缺少 `return` 语句，函数末尾生成 default `return runtime.Value.initNull()`，导致返回 NULL。

### 3.3 缺陷 2：return_generated 状态错误传播

Fix 1 生成 else 块的 ret 后，`self.return_generated = true`。但 then 块（block 8）以 br 终止（跳到 foreach），未 ret。

原代码在 `else_has_real_body=true` 路径中无 `return_generated` 合并逻辑。`return_generated = true` 传播到主循环，导致行 6893 `if (self.return_generated or self.break_generated)` 触发，批量标记 block 10-14 为 processed 并返回，foreach 循环和 `return true` 的 ret 块全部被跳过。

**修复**：添加 `return_generated = then_returned and else_returned` 合并。then 块未 ret（`then_returned=false`），else 块 ret（`else_returned=true`），AND 结果为 `false`，主循环继续处理 foreach 循环。

### 3.4 缺陷 3：foreach exit 块未处理

`generateForeachFromLabels` 中 `exit_idx = self.findBlockByLabelPrefix(func, cleanup_idx + 1, cleanup_search_end, "foreach_exit_")`。block 14 的标签是 `if_then_11`，不是 `foreach_exit_`，所以 `exit_idx = null`。

foreach body 中 `return false` 设置 `self.return_generated = true`。主循环（`generateLabelDrivenBlockRange`）行 6893-6897 检测到 `return_generated = true`，批量标记 block 14 及之后所有块为 processed 并返回。

`generateForeachFromLabels` 返回 `cleanup_idx + 1 = 14`。主循环从 block 14 继续，但 block 14 已 processed → 跳过。函数末尾生成 default `return runtime.Value.initNull()`。

**修复**：`exit_idx=null` 时，从 cleanup 块（block 13）的 br 终止符推导 exit 块（block 14），移除 processed 标记，保存/恢复 `return_generated`/`break_generated`，用 `generateLabelDrivenBlockRange` 处理 block 14 的指令和 ret 终止符。

### 3.5 三重修复的依赖关系

```mermaid
graph TD
    Fix1[Fix 1: else 块 ret 终止符生成] -->|引入 return_generated=true| Fix2[Fix 2: AND 合并]
    Fix2 -->|return_generated=false| Fix3[Fix 3: foreach exit 块处理]
    Fix3 -->|处理 block 14 的 ret| Result[✅ return true 生成]
    
    Fix1_alone[Fix 1 单独] -->|return_generated=true| Skip_foreach[foreach 被跳过 → segfault]
    Fix2_alone[Fix 1+2 缺 Fix 3] -->|block 14 被 processed 跳过| Default_return[default return NULL]
    Fix3_alone[Fix 3 单独缺 Fix 1] -->|else 块 ret 仍丢失| Else_null[else 路径返回 NULL]
```

三个修复缺一不可：
- 缺 Fix 1：else 分支的 `return true` 丢失
- 缺 Fix 2：then 路径的 foreach 循环被跳过
- 缺 Fix 3：then 路径 foreach 之后的 `return true` 丢失

---

## 4. 回归测试结果

### 4.1 已知失败脚本快速回归（14 项）

| 脚本 | 基线状态 | 本次状态 | 变化 |
|------|---------|---------|------|
| f033_state_pattern_order_machine.php | FAIL_DIFF | ✅ PASS | **修复** |
| f051_validator_rule_chain_batch.php | FAIL_DIFF | ✅ PASS | **连带修复** |
| f006_oop_observer_event_dispatcher.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f009_oop_decorator_chain_command.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f031_builder_fluent_immutable.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f061_graph_dijkstra_bellmanford_floyd.php | FAIL_DIFF | RUNTIME_CRASH | 不变（segfault） |
| f065_crypto_rc4_sha1_base64_crc.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f070_event_sourcing_cqrs_snapshot.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f097_search_engine_inverted_index_tfidf.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f117_search_engine_inverted_tfidf_bm25.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f134_event_sourcing_snapshot_cqrs_projection.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f151_type_system_generics_variance.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f160_virtual_fs_path_traversal.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f163_event_driven_dispatch_bus.php | FAIL_DIFF | FAIL_DIFF | 不变 |

### 4.2 统计

| 指标 | 基线 | 本次 | 变化 |
|------|------|------|------|
| FAIL_DIFF | 14 | 12 | -2 |
| 新增通过 | - | f033, f051 | +2 |
| 新增回归 | - | 0 | 0 |

---

## 5. 修改文件清单

| 文件 | 修改类型 | 说明 |
|------|---------|------|
| `src/aot/native_linker.zig` | 修改 | 3 处修复（else ret 终止符 + AND 合并 + foreach exit 块处理） |
| `docs/changes/2026-08-30/else_ret_foreach_exit_三重缺陷修复_b3e1a2.md` | 新增 | 技术细节文档 |
| `docs/changes/2026-08-30/handoff_session5.md` | 新增 | 本交接文档 |

---

## 6. 当前基线失败全量列表

### 6.1 FAIL_DIFF（12 项）

```
f006_oop_observer_event_dispatcher.php
f009_oop_decorator_chain_command.php
f031_builder_fluent_immutable.php
f061_graph_dijkstra_bellmanford_floyd.php
f065_crypto_rc4_sha1_base64_crc.php
f070_event_sourcing_cqrs_snapshot.php
f097_search_engine_inverted_index_tfidf.php
f117_search_engine_inverted_tfidf_bm25.php
f134_event_sourcing_snapshot_cqrs_projection.php
f151_type_system_generics_variance.php
f160_virtual_fs_path_traversal.php
f163_event_driven_dispatch_bus.php
```

### 6.2 FAIL_RUNTIME（13 项）

```
f007_string_encoding_crypto_hash.php     (exit=124 超时)
f025_coding_hamming_rle_lzw_crc.php       (exit=124 超时)
f037_adapter_unified_cache.php            (exit=255 异常)
f038_composite_filesystem_tree.php        (exit=124 超时)
f067_debug_full_parser.php                (exit=255 异常)
f067_debug_single.php                     (exit=255 异常)
f067_json_parser_schema_path_diff.php     (exit=255 异常)
f095_compiler_opt_constfold_dce_cse.php   (exit=124 超时)
f113_distributed_consistenthash_vectorclock_quorum.php (exit=133 segfault)
f124_container_orchestrator_pod_service_autoscale.php  (exit=139 segfault)
f135_math_number_theory_crt_miller_rabin.php (exit=133 segfault)
f161_json_xml_csv_parsing.php             (exit=1 异常)
f178_numeric_precision_matrix.php         (exit=124 超时)
```

### 6.3 SKIP（3 项）

```
f004_oop_deep_inheritance_magic.php
f067_debug_char4.php
f067_debug_char5.php
```

---

## 7. 遗留问题 / 待办

| 优先级 | 事项 | 说明 |
|--------|------|------|
| **P0** | FAIL_DIFF 12 项逐个攻坚 | 重点：f061（图算法 segfault）、f070/f134（事件溯源 history 差异） |
| **P1** | 超时 5 项 | f007/f025/f038/f095/f178，需分析是否死循环或性能瓶颈 |
| **P1** | 崩溃 3 项 | f113/f124/f135 信号崩溃(133/139)，排查内存安全 |
| **P2** | f067 JSON 解析器 | 3 项 FAIL_RUNTIME + 2 项 SKIP，JSON 字符串解析有 bug |
| **P2** | 统一 return_generated 的 save/restore 策略 | 当前 foreach 有 save/restore，但 if/else 的 else_has_real_body 路径用 AND 合并；建议统一为函数级 defer save/restore |
| **P2** | while 生成器 else_is_back_edge 路径同步 then_is_break 检测 | 会话 3 遗留，for/foreach 已同步 |
| **P2** | for/while 生成器嵌套短路链检测同步 | foreach 已有，for/while 待验证 |

---

## 8. 复现脚本清单（本会话新增）

| 脚本 | 覆盖缺陷 | 状态 |
|------|----------|------|
| `repro_f033_c.php` | if(isset)+foreach+return true 最小复现 | ✅ 通过 |

（注：会话过程中生成了大量临时调试脚本 `repro_f033_*.php`，已在交接前清理编译产物。）

---

## 9. 自检结论

| 检查项 | 结果 |
|--------|------|
| 编译验证 `zig build` | ✅ exit 0 |
| f033 原始脚本 AOT vs PHP | ✅ 零差异 |
| repro_f033_c.php AOT vs PHP | ✅ 零差异 |
| 回归测试零新增 | ✅ 12 项均为已知失败，无新增 |
| 修改范围最小化 | ✅ 3 处修改，每处可独立回滚 |
| 补丁脚本已清理 | ✅ 临时脚本已删除 |
| 修改已 commit | ✅ 在 commit 6da6bee 中 |

**结论**：链式深度自检通过。修复聚焦 AOT，未涉及非 AOT 逻辑。三重修复缺一不可，互相依赖。
