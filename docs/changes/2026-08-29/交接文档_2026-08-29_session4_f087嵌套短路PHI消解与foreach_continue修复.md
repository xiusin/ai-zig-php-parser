# 交接文档：f087 嵌套短路 PHI 消解与 foreach continue 修复

**日期**：2026-08-29
**Session**：4
**修复状态**：f087 已通过验证

## 一、问题概述

`f087_rbac_abac_policy_inheritance.php` 在 AOT 编译后输出 `false`（应输出 `true`），根因为两类缺陷：

1. **嵌套短路链 PHI 消解 incoming 匹配错误**：`||`/`&&` 嵌套短路中，PHI 消解用 `incoming.block == then_blk`（cond_br 所在块）匹配，但 merge 块的 PHI incoming 来自短路 merge 块（`nested_cb.then_block`/`else_block`），不来自 cond_br 源块。
2. **foreach 循环体 `continue` 缺失**：`logical_merge_to_process` 递归使用 `end_idx` 作为范围终点，包含了 cleanup 之后的块（如第二个 foreach），内层 foreach 的 `return false` 设置了 `return_generated = true`，导致外层 foreach 的 `continue :__foreach_0` 被跳过。

## 二、根因分析

### 缺陷 1：PHI 消解 incoming 匹配

IR 结构（`repro_f087k.php` 的 `hasPermission` 方法）：

```
foreach_body_1:
  br reg_18, logical_merge_6, logical_rhs_5      ← 第一个 ||

logical_merge_6:
  reg_23 = phi [reg_18, foreach_body_1], [reg_22, logical_rhs_5]
  br reg_23, logical_rhs_7, logical_merge_8       ← &&

logical_rhs_7:
  br reg_28, logical_merge_10, logical_rhs_9      ← 第二个 ||

logical_merge_8:
  reg_34 = phi [reg_24, logical_merge_6], [reg_33, logical_merge_10]
  br reg_34, if_then_11, foreach_increment_2     ← if 条件
```

在 `||` 短路中，`nested_cb` = `logical_rhs_7` 的 cond_br：
- `nested_cb.then_block` = `logical_merge_10`（短路 merge）
- `nested_cb.else_block` = `logical_rhs_9`（rhs）

`sc_merge_blk` = `logical_merge_8`，其 PHI `reg_34` 的 incoming：
- `[reg_24, logical_merge_6]` — 来自 `&&` 的 false 路径
- `[reg_33, logical_merge_10]` — 来自 `&&` 的 true 路径

**旧代码**：`incoming.block == then_blk`（`logical_rhs_7`）—— 匹配不到。
**修复**：`incoming.block == nested_cb.then_block`（`logical_merge_10`）—— 正确匹配。

### 缺陷 2：foreach continue 缺失

`logical_merge_to_process` 递归（9982行）处理嵌套短路链时，使用 `end_idx` 作为范围终点。当函数中有第二个 foreach 在第一个 foreach 的 cleanup 之后时，`end_idx` 包含了第二个 foreach 的块。

第二个 foreach 内的 `return false` 设置了 `self.return_generated = true`。9983 行的恢复逻辑 `if (!self.return_generated) self.return_generated = saved_rg;` 不会清除已设置的 true——导致 10085 行 `!self.break_generated and !self.lastLineIsReturn` 中 `lastLineIsReturn` 返回 true，`continue :__foreach_0` 被跳过。

**修复**：将 9982 行的 `end_idx` 改为 `loop_end`（`@min(end_idx, loop_last_be + 1)`），限制递归范围到循环回边之前，不包含 cleanup 之后的块。

## 三、修复内容

### 文件：`src/aot/native_linker.zig`

| 修复点 | 行号（约） | 修复内容 |
|--------|-----------|---------|
| `||` 短路 then 路径 PHI 匹配 | 7720-7733 | `incoming.block == nested_cb.then_block` + fallback 到 `then_blk` |
| `&&` 短路 else 路径 PHI 匹配 | 7698-7714 | `incoming.block == nested_cb.else_block` + fallback 到 `then_blk` |
| `logical_merge_to_process` 范围限制 | 9982, 11625, 12956 | `end_idx` → `loop_end`（3处） |
| foreach body 递归保存/恢复 | 10004, 10020 | 递归前后保存/恢复 `return_generated`/`break_generated` |

### 验证脚本

| 脚本 | 描述 | 结果 |
|------|------|------|
| `fuzzy_scripts_720/tmp/repro_f087k.php` | foreach + 嵌套短路 + 递归调用 | ✅ 通过 |
| `fuzzy_scripts_720/tmp/repro_f087k2.php` | 扩展测试（多权限） | ✅ 通过 |
| `fuzzy_scripts_720/tmp/repro_nested_sc.php` | 最简嵌套短路 | ✅ 通过 |
| `fuzzy_scripts_720/pass/f087_rbac_abac_policy_inheritance.php` | 原始 f087 | ✅ 通过 |

## 四、回归测试结果

全量回归测试（`scripts/regression_test_720.sh`）完成：

- **总失败**：30 项（14 FAIL_DIFF + 13 FAIL_RUNTIME + 3 SKIP）
- **f087**：不在失败列表中 ✅
- **新引入回归**：无（所有失败项均为已知问题）

### 已知失败分类

| 类型 | 数量 | 典型原因 |
|------|------|---------|
| FAIL_DIFF | 14 | 输出微小差异（JSON 转义、浮点精度、状态机逻辑） |
| FAIL_RUNTIME | 13 | 超时(124)、崩溃(133/139)、运行时错误(255) |
| SKIP | 3 | PHP 解释器自身报错 |

## 五、后续建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|--------|--------|---------|------|
| P0 | FAIL_DIFF 14项 | 中 | 逐项排查输出差异根因，重点看 f033（状态机）、f061（图算法） |
| P1 | FAIL_RUNTIME 超时 5项 | 高 | f007/f025/f038/f095/f178 超时，需分析是否死循环或性能问题 |
| P1 | FAIL_RUNTIME 崩溃 3项 | 高 | f113/f124/f135 信号崩溃(133/139)，需排查内存安全 |
| P2 | f067 JSON 解析器 | 中 | 3项 FAIL_RUNTIME + 2项 SKIP，JSON 字符串解析有 bug |
