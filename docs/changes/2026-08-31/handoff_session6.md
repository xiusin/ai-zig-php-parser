# 交接文档（会话 6）：f061 Dijkstra while-continue 缺陷定位与部分修复

> 日期：2026-08-31 | 涉及文件：`src/aot/native_linker.zig`
> 编译状态：✅ `zig build` 通过
> 回归状态：✅ f033/f051 仍 PASS，已知 FAIL_DIFF 脚本无新增回归
> 上级交接链：
> - `docs/changes/2026-08-30/handoff_session5.md`（会话 5：f033 三重控制流缺陷修复）
> - 本文档
> 用户指令：**"接手已知问题继续修复"**

---

## 1. TL;DR

本会话以 f061_graph_dijkstra_bellmanford_floyd.php 为攻坚目标。根因为 **while 循环内嵌套 foreach + if(isset) continue 的 IR 生成缺陷**，涉及两个关联问题：

1. **else_is_coalesce 误判**（Fix A）：while body 终止符 cond_br 的 else 块（if_merge_）有 cond_br 终止符时，被误判为 coalesce 短路 merge，导致 else 块的 cond_br（isset continue）未生成 if/continue 结构。
2. **then_is_back_edge 未生成 continue**（Fix B）：while body 终止符 cond_br 的 then 块指向 cond_block（continue 语义）时，`then_is_back_edge=true` 但未生成 `continue :label` 语句。

**修复结果**：isset continue 已正确生成（`if (reg_60.toBool()) { continue :__while_1; }`），但 f061 仍因 **while 内嵌套 foreach 第二次迭代时 foreach adj 循环体被跳过** 而失败。此为遗留问题。

---

## 2. 修复清单

### 2.1 文件：`src/aot/native_linker.zig`

| # | 修复点 | 行号（约） | 修复内容 | 归因 |
|---|--------|-----------|---------|------|
| A | else_is_coalesce 排除 cond_br | ~12311 | `else_is_coalesce` 定义改为：else 块有 cond_br 终止符时不走 coalesce 路径 | coalesce 模式假设 else 是短路 merge（仅 PHI+br），else 有 cond_br（如 isset continue）时需走正常 else 处理 |
| B | then_is_back_edge 生成 continue | ~12120 | while body 终止符 cond_br 的 then 指向 cond_block 时，生成 `continue :label_name` | then 指向 cond = continue 语义，原仅设 then_is_back_edge=true 但未生成 continue |
| C | 嵌套 cond_br then 指向 cond 生成 continue | ~12692 | while body 内 else 块的嵌套 cond_br，then 指向 cond 时生成 `continue :label_name` | 与 Fix B 对称，覆盖 else 块内嵌套 cond_br 的 continue 语义 |

### 2.2 验证脚本

| 脚本 | 描述 | 结果 |
|------|------|------|
| `f061_min_dijkstra2.php` | 最小复现：while+usort+array_shift+isset continue+foreach adj | isset continue 已生成，但第二轮 foreach adj 被跳过（abort=142） |
| `f061_no_continue.php` | 移除 isset continue 的对照 | 不 abort，但第二轮 foreach adj 仍被跳过 |
| `f061_while_continue.php` | 纯 while+continue（无 foreach） | ✅ 通过（证明 continue 生成正确） |

---

## 3. 根因分析

### 3.1 IR 块结构（f061 的 dijkstra 方法）

```text
while_cond_5:
  PHI [foreach_cleanup_3, if_merge_9, foreach_cleanup_15]
  br reg_37, while_body_6, while_exit_7

while_body_6:
  $iter++
  br reg_42, if_then_8, if_merge_9    // if ($iter > 100) break

if_then_8:
  echo "LOOP"; br while_exit_7       // break

if_merge_9:
  usort + array_shift + [$u,$d]
  reg_60 = isset($visited[$u])
  br reg_60, while_cond_5, if_merge_11  // if (isset) continue → while_cond_5

if_merge_11:
  $visited[$u] = true
  br foreach_cond_10

foreach_cond_10:
  foreach adj 循环
  foreach_cleanup_15: br while_cond_5  // foreach 结束后回 while
```

### 3.2 缺陷 1：else_is_coalesce 误判

while body 终止符 cond_br `br reg_42, if_then_8, if_merge_9`：
- then = if_then_8（break）
- else = if_merge_9（isset continue + foreach adj）

`merge_bi` 在行 12271-12278 被推导为 else_bi（if_merge_9 标签匹配 if_merge_ 前缀）。

`else_is_coalesce = merge_bi == else_bi` = true。

coalesce 路径（行 12320-12355）把 if_merge_9 当作短路 merge 块，只生成 PHI + 非 PHI 指令，**不处理 cond_br 终止符**。导致 isset 的 if/continue 未生成。

**修复**：else_is_coalesce 检测中，排除 else 块有 cond_br 终止符的情况。

### 3.3 缺陷 2：then_is_back_edge 未生成 continue

f061 中 isset 的 cond_br `br reg_60, while_cond_5, if_merge_11`，then_block = while_cond_5（cond 块）。

while body 终止符 cond_br 的 then 块处理中（行 12118-12119），`then_is_back_edge = true` 但未生成 `continue :label`。

**修复**：then_is_back_edge=true 时生成 `continue :label_name`。

### 3.4 遗留问题：foreach adj 第二次迭代被跳过

修复 isset continue 后，f061 的 Dijkstra 仍全 INF。最小复现（f061_no_continue.php，移除 isset continue）显示：
- 第一次 while 迭代（u=A）：foreach adj 正常执行（relax B=4, C=2）
- 第二次 while 迭代（u=C）：foreach adj **循环体未执行**（直接跳过到下一轮）
- 不 abort，但 Dijkstra 结果错误

此问题与 isset continue 无关，是 **while 循环内嵌套 foreach 的 IR 生成在第二次迭代时 foreach 循环体被跳过**。

可能原因：
1. foreach 的 `while(true)` 结构在 while 回边后 PHI 消解不正确
2. foreach 迭代器在第一次迭代后被释放，第二次 init_snapshot 取到空/旧值
3. `generateForeachFromLabels` 的 `processed` 标记导致 foreach 块在第二次 while 迭代时被跳过

**待定位**。

---

## 4. 回归测试结果

### 4.1 已知失败脚本快速验证

| 脚本 | 基线状态 | 本次状态 | 变化 |
|------|---------|---------|------|
| f033_state_pattern_order_machine.php | ✅ PASS | ✅ PASS | 不变 |
| f051_validator_rule_chain_batch.php | ✅ PASS | ✅ PASS | 不变 |
| f006_oop_observer_event_dispatcher.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f031_builder_fluent_immutable.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f065_crypto_rc4_sha1_base64_crc.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f097_search_engine_inverted_index_tfidf.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f151_type_system_generics_variance.php | FAIL_DIFF | FAIL_DIFF | 不变 |
| f061_graph_dijkstra_bellmanford_floyd.php | RUNTIME_CRASH | RUNTIME_CRASH | 不变（exit 137/142） |

### 4.2 统计

| 指标 | 基线 | 本次 | 变化 |
|------|------|------|------|
| 新增回归 | - | 0 | 0 |
| 新增通过 | - | 0 | 0 |

---

## 5. 修改文件清单

| 文件 | 修改类型 | 说明 |
|------|---------|------|
| `src/aot/native_linker.zig` | 修改 | 3 处修复（else_is_coalesce 排除 cond_br + then_is_back_edge continue + 嵌套 cond_br then continue） |

---

## 6. 遗留问题 / 待办

| 优先级 | 事项 | 说明 |
|--------|------|------|
| **P0** | f061 foreach adj 第二次迭代被跳过 | while 内嵌套 foreach 的 IR 生成问题，需定位 foreach 在第二次 while 迭代时循环体为何被跳过 |
| **P0** | FAIL_DIFF 12 项逐个攻坚 | f061 是首个攻坚目标，未完成 |
| **P1** | 超时 5 项 | f007/f025/f038/f095/f178 |
| **P1** | 崩溃 3 项 | f113/f124/f135 信号崩溃(133/139) |
| **P2** | f067 JSON 解析器 | 3 项 FAIL_RUNTIME + 2 项 SKIP |
| **P2** | `generateLabelDrivenBlockRange` 中 if_merge_ cond_br 的 then 指向 cond 的同类问题 | 与 Fix B/C 对称，需在行 7049 添加 nti == cond_idx 检测 |

---

## 7. 自检结论

| 检查项 | 结果 |
|--------|------|
| 编译验证 `zig build` | ✅ exit 0 |
| f033/f051 仍 PASS | ✅ 零回归 |
| 已知 FAIL_DIFF 无新增 | ✅ 5 项均不变 |
| isset continue 已生成 | ✅ `if (reg_60.toBool()) { continue :__while_1; }` |
| f061 仍 RUNTIME_CRASH | ❌ foreach adj 第二次迭代被跳过（遗留） |
| 修改范围最小化 | ✅ 3 处修改，每处可独立回滚 |

**结论**：isset continue 缺陷已修复（Fix A/B/C），但 f061 仍有 foreach adj 第二次迭代被跳过的遗留问题。修复聚焦 AOT，未涉及非 AOT 逻辑。需在下一会话继续定位 foreach 嵌套 while 的 IR 生成问题。
