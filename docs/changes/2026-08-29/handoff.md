# 交接文档：f028 循环嵌套 if/elseif 死循环修复（loop_end 吞分支 + 嵌套 merge PHI 物化）— Session 2026-08-29

> 日期：2026-08-29 | 涉及文件：`src/aot/native_linker.zig`
> 变更标识：`f028_nested_else_phi_loop_backedge`（工作区未提交，diff +142/-9）
> 编译状态：✅ `zig build-exe` 手动构建通过（绕过 build.zig 注入的含空格路径 bug）
> 上级交接链：
> - `docs/changes/2026-08-25/handoff.md`（`293962a`，嵌套 foreach @ while(true) 死循环，缺陷 B 记为 P1）
> - `docs/changes/2026-08-26/handoff.md`（`07a0e60`/`e9d9514`，f032 merge PHI 物化与共享 return 修复）
> - `docs/changes/2026-08-26/nested_if_phi_loop_codegen_01e76d9.md`（AOT-PHI-001 定位探针）
> - 已知问题登记：`docs/known-issues/AOT-PHI-001-nested-if-phi-bug.md`（已修复）、`docs/known-issues/AOT-CODEGEN-003-while-true-break-missing.md`（部分修复）
> 本会话提交：`fc4417f`（AOT-PHI-001 修复）、`01e76d9`（AOT-PHI-001 探针）

---

## TL;DR

本轮聚焦 AOT 两个已知问题：

1. **AOT-PHI-001（已修复并提交）**：循环内多个顺序 if 修改同一变量时 Phi 赋值丢失（`repro_phi001.php` AOT 输出 `evenoddevenoddeven` 缺逗号）。根因是 `writeBrInLoopContext` 对 `if_merge_` 块误内联导致非 PHI 指令（条件比较）未生成。修复：加守卫跳过内联，交由主循环生成。验证：`repro_phi001.php` 及变体输出与 PHP 一致。

2. **f028 死循环（修复代码完成、已编译验证通过、未提交）**：`repro_lcs_repro.php`（LCS 回溯算法）AOT 执行超时，循环永不退出。根因双重：
   - `loop_last_be` 单次扫描未包含 IR 生成器后置的嵌套 else 分支块（`if_then_20`/`if_else_21`/`if_merge_22`），`loop_end=18` 吞掉 `$j--` 所在 `if_else_21`；
   - 嵌套 else/elseif 分支汇入外层 `if_merge_19` 时，循环携带变量 PHI（`reg_158/reg_152`）未物化写回，`$j` 新值丢失。
   
   修复三处（`generateWhileFromLabels` 迭代扩展 `loop_last_be`、`generateLabelDrivenBlockRange` 非回边 br 的 `materializeBrTargetMergePhis`、嵌套 then 分支外层 merge PHI 物化），并新增 `materializeBrTargetMergePhis` 辅助函数。验证：AOT 输出 `length=4 seq='BCAB'` 与 PHP 完全一致，不再死循环。

**成果**：两项缺陷最小复现均通过，AOT 与 PHP 输出一致。

**详情**：见下「核心变更」与「详细变更分析」。

---

## 影响范围

| 端/模块 | 影响文件 | 影响描述 |
|---------|---------|---------|
| AOT 代码生成器 | `src/aot/native_linker.zig`（+142/-9，未提交） | `generateWhileFromLabels`（while 体回边范围判定）、`generateLabelDrivenBlockRange`（普通线性块 br 的 PHI 物化）、`generateIfFromLabels`（Step7 探针）、`writeBrInLoopContext`（AOT-PHI-001 守卫，已提交） |
| 已知问题登记 | `docs/known-issues/AOT-PHI-001-nested-if-phi-bug.md` | 状态 ✅ 已修复（2026-08-26 更新） |
| 测试用例 | `fuzzy_scripts_720/tmp/repro_lcs_*.php`（8 个）、`repro_phi001.php`/`repro_phi001b.php` | 最小复现与隔离用例（未纳入 pass 永久回归集） |

**破坏式变更**：否。所有修复均为代码生成器分支逻辑增强，不改变 IR 结构，不涉及运行时/ABI。

---

## 核心变更

### AOT-PHI-001（已提交 `fc4417f` + 探针 `01e76d9`）

`writeBrInLoopContext`：当 br 目标是 `if_merge_` 块且带 `cond_br` 终止符时，跳过 `generateBrToMergeCondBr` 内联，交由主循环处理，确保非 PHI 指令生成。

### f028 死循环（未提交，工作区 diff）

**变更 1 — `generateWhileFromLabels` 迭代扩展 `loop_last_be`（间接回边）**

原单次扫描只能定位「直接回边块」（br/cond_br 目标 == cond 块）。IR 生成器会把 while 体内嵌套 if/elseif 子块（`if_then_`/`if_else_`/`if_merge_`）后置到直接回边块之后。改为迭代扫描：对每个终止符判定「直接回边」或「间接回边」（br/cond_br 任一目标落在已确定的循环体范围 `[body_idx, loop_last_be]` 内），逐轮扩展 `loop_last_be` 直至稳定，确保 `loop_end` 覆盖所有嵌套分支。与 `generateForFromLabels` 的迭代扩展模式一致。

**变更 2 — 新增 `materializeBrTargetMergePhis` 辅助函数**

```zig
fn materializeBrTargetMergePhis(self, writer, source_block, br_target, indent) !void
```

对「source_block → br_target」这条非回边 br 边消解 br 目标 merge 块（`if_merge_`/`logical_merge_` 等）的 PHI：遍历目标块 phi 指令，匹配 incoming.block 为 source_block 的边，`writePtrAwareAssign` 写回。仅对含 phi 的目标生效；目标已处理/无匹配 incoming 时不产生任何指令。当前保留 `[[MBTM src=... tgt=...]]` 调试探针（提交前须清理）。

**变更 3 — `generateLabelDrivenBlockRange` 普通线性块 `.br` 分支**

新增 `br_was_backedge` 标记：回边场景（目标为当前循环 cond/increment 块）已在原逻辑物化 cond 块 PHI，跳过；非回边 br 调用 `materializeBrTargetMergePhis` 补上 else 侧（嵌套 if 的 else 分支汇入 `if_merge_`，及 `if_merge_` 再汇入外层 merge）的物化缺口。

**变更 4 — `generateWhileFromLabels` 嵌套 then 分支外层 merge PHI 物化**

嵌套 if/elseif 的 then 真分支（`if_then_20`）br 到嵌套 merge（`if_merge_22`），该嵌套 merge 再 br 到外层 merge（`merge_bi`，如 `if_merge_19`）。在 then 分支 br 处理处补物化外层 merge 的循环携带 PHI，与嵌套 else 分支经 `materializeBrTargetMergePhis` 的物化对称。否则 elseif 真分支（`$i--`）读外层循环携带 PHI 为陈旧值，循环退出变量永不推进 → 死循环。

---

## 可视化概览（Code & Logic Map）

### f028 死循环控制流与修复点映射（repro_lcs_repro.php 回溯 while）

```mermaid
flowchart TD
    WC[while_cond_12<br/>cond: i>0 && j>0] --> WB[while_body<br/>if: s1[i-1]===s2[j-1]]
    WB -->|true| IT20[if_then_20<br/>$result .=; i--; j--]
    WB -->|false| IE18[if_else_18]
    IE18 -->|true| IT20b[elseif: dp[i-1][j]>=dp[i][j-1]<br/>i--]
    IE18 -->|false| IE21[if_else_21<br/>j--]
    IT20b --> IM22[if_merge_22]
    IE21 --> IM22
    IT20 --> IM22
    IM22 --> IM19[if_merge_19<br/>PHI: reg_157/reg_151<br/>= f(reg_158/reg_152)]
    IM19 -->|回边| WC
    IM19 -->|guard break| WEXIT[while_exit]

    subgraph FIX1["变更1: 迭代扩展 loop_last_be"]
        IE21 -.被 loop_end 吞掉.-> IM19
        FIX1B[loop_last_be 迭代扫描<br/>间接回边 → 覆盖 IE21/IM22/IM19]
    end
    subgraph FIX2["变更2+3: 非回边 br 物化"]
        IE21 -.materializeBrTargetMergePhis.-> IM22
        IM22 -.materializeBrTargetMergePhis.-> IM19
    end
    subgraph FIX3["变更4: 嵌套 then 外层 merge 物化"]
        IT20 -.materializeBrTargetMergePhis.-> IM22
        IT20b -.外层 merge PHI 物化.-> IM19
    end
```

说明：`if_merge_19` 的 PHI 把嵌套 if/elseif 三个分支（`if_then_20`/`if_then_20b`/`if_else_21`）的循环携带变量（`$i`/`$j`）汇聚写回，供外层 while 条件判定。三处修复保证任一分支路径都完成物化，`$j`/`$i` 持续推进，循环条件最终为 false 退出。

---

## 详细变更分析

### 涉及文件列表

| 文件 | 变更类型 | 变更点 |
|------|---------|--------|
| `src/aot/native_linker.zig` | 修改（+142/-9，未提交） | 见「核心变更」f028 四小点 |
| `fuzzy_scripts_720/tmp/repro_lcs_repro.php` | 新增 | f028 最小复现（LCS 回溯 while，`$j--` 在嵌套 else） |
| `fuzzy_scripts_720/tmp/repro_lcs_backtrack_only.php` | 新增 | 隔离回溯 while，硬编码 DP 表 |
| `fuzzy_scripts_720/tmp/repro_lcs_dp_only.php` | 新增 | 隔离 DP 双层 for，不做回溯 |
| `fuzzy_scripts_720/tmp/repro_lcs_probe*.php`（probe2-4） | 新增 | stderr 进度标记/分支打印，定位挂点 |
| `fuzzy_scripts_720/tmp/repro_phi001.php`/`repro_phi001b.php` | 新增 | AOT-PHI-001 复现及变体 |
| `docs/known-issues/AOT-PHI-001-nested-if-phi-bug.md` | 修改（已提交 `fc4417f` 前） | 状态更新为已修复 |

### 探针清单（提交前必须清理）

| 探针标记 | 所在函数 | 用途 |
|---------|---------|------|
| `[[LDR walk i=...]]` | `generateLabelDrivenBlockRange` | 追踪 if 块访问 |
| `[[MBTM src=... tgt=...]]` | `materializeBrTargetMergePhis` | 追踪非回边 br 物化触发 |
| `[[WHELSEB else=... merge=...]]` | `generateWhileFromLabels` | 追踪外层 else 处理 |
| `[[WINESTELSE nei2=...]]` | `generateWhileFromLabels`（多处） | 追踪嵌套 else 处理 |
| `[[S7_PHI merge=... else_idx=...]]` | `generateIfFromLabels` Step7 | 追踪 merge PHI 物化来源 |

---

## 验证结果

| 用例 | 命令 | 结果 |
|------|------|------|
| f028 死循环 | AOT `repro_lcs_repro.php` 编译+运行（timeout 10s） | ✅ `length=4 seq='BCAB'`，与 PHP 一致，无超时 |
| AOT-PHI-001 | AOT `repro_phi001.php` | ✅ `even,odd,even,odd,even`，与 PHP 一致 |
| 编译器构建 | `zig build-exe ... -OReleaseSafe`（手动） | ✅ 通过，产物 `zig-out/bin/php-interpreter`（4955824 B） |

> 注意：`zig build` 因 build runner 注入含空格路径（`/Users/wangjianjun/Library/Application Support/...`）扫描失败（`unable to open library directory`），须用手动 `zig build-exe` 命令（含全部依赖模块），详见 AGENTS.md 相关记录。

### 回归状态（f028 修复后）

| 范围 | 状态 |
|------|------|
| 复现用例 | ✅ 全部通过 |
| 全量 720 回归基线 | ⏳ 未跑（交接待办） |
| 编译产物 | ⏳ `/tmp/aot_lcs_v3/`、`/tmp/phi_v3/` 待清理（不影响仓库） |

---

## 影响与风险评估

- **破坏式变更**：否。
- **风险点 1**：`materializeBrTargetMergePhis` 是无条件匹配 incoming 块指针/标签后写回，若出现「多个 incoming 引用同一 source_block」的异常 IR，可能重复赋值。已按第一匹配 break，行为等价 PHP 合法路径。
- **风险点 2**：迭代扩展 `loop_last_be` 是尽力扫描，若出现更深层（3 层以上）嵌套 + 间接回边组合，需回归验证是否仍存在范围吞并。
- **风险点 3**：探针仍在代码中，若直接提交会把 `[[...]]` 日志写入生成代码，导致生成产物不可编译（历史教训：`3185489` 清理 `/* WALK */`）。**提交前必须清理。**
- **特别提醒**：`reg_161=reg_162` 这类非循环携带赋值若出现在 merge 块，需确认不会因物化被误提升到分支内；当前修复仅对含 phi 的目标操作，已规避。

---

## 遗留问题 / 待办

| 优先级 | 事项 | 说明 |
|--------|------|------|
| P0 | 清理 5 类调试探针（`[[LDR/MBTM/WHELSEB/WINESTELSE/S7_PHI]]`） | 提交前必须完成，否则污染生成代码 |
| P0 | 提交 f028 修复（git commit） | 当前工作区 diff +142/-9 未提交 |
| P1 | 全量回归 `regression_test_720.sh` 或 `batch_test_aot.sh` | 确认无新增失败（基线 `fuzzy_scripts_720/regression_failures.tsv`） |
| P1 | 生成变更摘要文档 `docs/changes/2026-08-29/` 下详细版 | 本 handoff 已覆盖概要，可补 `{His}_{HASH}.md` |
| P1 | 清理 `/tmp` 下编译产物 | `/tmp/aot_lcs_test/`、`/tmp/aot_lcs_test2/`、`/tmp/aot_lcs_v3/`、`/tmp/phi_v3/` |
| P2 | 将 `repro_lcs_repro.php`、`repro_phi001.php` 提炼为最小回归用例纳入 `fuzzy_scripts_720/pass/` | 防止复发 |

---

## 后续优化建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|---------|
| P1 | 将「回边范围判定」（直接回边 + 间接回边迭代扩展）抽为共享工具 fn，供 while/for/foreach/do_while 四类循环头复用，消除三处重复实现 | 可维护性、收敛一致性 | 低 |
| P1 | 把「merge 块 PHI 物化」统一收敛到单一入口（按边物化 vs 按块物化），消除 then/else 不对称缺口再次出现的可能 | 正确性 | 中 |
| P2 | 用真实 `f177_graph_traversal_dfs_bfs.php` / LCS 类算法脚本复测，确认修复覆盖非最小用例 | AOT 运行稳定性 | 低 |
| P2 | 为嵌套 if/elseif 循环携带变量场景增加结构化测试（3 层嵌套、混合 break/continue/return） | 回归覆盖 | 中 |
| P2 | 排查 `AOT-CODEGEN-003`（while(true) break 缺失）剩余部分，验证与本次 f028 修复是否同源 | 已知问题收敛 | 中 |

---

## 复测路径

```bash
cd /Users/wangjianjun/products/parser
T=$(mktemp -d)
# f028 死循环（嵌套 if/elseif 的 else 分支含循环退出变量）
./zig-out/bin/php-interpreter --compile --no-debug-info --output="$T/lcs" fuzzy_scripts_720/tmp/repro_lcs_repro.php
diff <("$T/lcs" 2>/dev/null | grep -v '^\[\[') <(php fuzzy_scripts_720/tmp/repro_lcs_repro.php)   # 期望无输出
# AOT-PHI-001 回归
./zig-out/bin/php-interpreter --compile --no-debug-info --output="$T/p1" fuzzy_scripts_720/tmp/repro_phi001.php
diff <("$T/p1" 2>/dev/null | grep -v '^\[\[') <(php fuzzy_scripts_720/tmp/repro_phi001.php)            # 期望无输出
rm -rf "$T"
```

---

## 会话状态速查

- **本轮已完成**：AOT-PHI-001 修复+提交；f028 根因定位、三处修复代码、编译验证、最小复现通过。
- **未完成**：探针清理、f028 提交、全量回归、变更摘要详细版、产物清理。
- **下一步推荐**：清理探针 → 手动 `zig build-exe` 重编 → 复测两项 → 全量回归 → 提交 → 补详细变更摘要。
