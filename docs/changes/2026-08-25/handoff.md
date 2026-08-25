# 交接文档：嵌套 foreach 于 while(true) 内 cond_br 回边展平为空分支死循环修复 — Session 2026-08-25

> 日期：2026-08-25 | 涉及文件：`src/aot/native_linker.zig`
> 变更标识：`nested_foreach_while_cond_br_delegate`（commit `293962a` + 调试清理 `3185489`）
> 编译状态：✅ `zig build` 通过
> 上级交接链：`docs/changes/2026-08-24/handoff.md`（821f0e3a，while/botbreak 出口 PHI、缺陷 B 记为 P1 待办）
> 详情文档：`docs/changes/2026-08-25/nested_foreach_while_cond_br_delegate_293962a.md`

---

## TL;DR

攻下缺陷 B（上轮 P1 阻断项）：**嵌套 foreach 于 while(true) 内**，`foreach_cleanup` 终止符是**指向外层 while exit/cond 的 `cond_br`**，原 `generateForeachFromLabels` cleanup 仅处理 `.ret`，该 `cond_br` 落入空分支 → 判定丢失 → 尾随无条件 continue → 死循环 OOM（`f177` exit=137）。

**修复链（三次提交）**：
1. `dd27b06` — `generateWhileFromLabels` 的 `.br` 终止符：识别嵌套循环头，`body_idx` 保持 `cond_idx`，让嵌套 foreach 走独立的 `generateForeachFromLabels`（不被外层 while 内联展平）。
2. `293962a` — cleanup 终符**新增 `.cond_br` 分支**：用标签前缀识别跨循环回边（then/else 分属外层 exit/回边），生成 `if(cond){ 物化外层 exit 循环携带 PHI; break :外层 }`；反向布局取反条件；外层 exit 块索引按标签匹配（绕过边界映射误解析的 saved 索引）。
3. `3185489` — 清理定位期间遗留的调试日志（`/* WALK */` 等写入生成代码导致 `expected statement found '/'`）。

**成果**：`repro_wbreak.php`（w1 简单 while+break、w2 嵌套 foreach+外层 break）AOT 运行输出 `w1 ok i=3 / w2 ok i=3 / END`，与真实 PHP 完全一致；不再死循环。

**详情**：`nested_foreach_while_cond_br_delegate_293962a.md`

---

## 后续建议（承接）

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|---------|
| P1 | 用真实 `f177_graph_traversal_dfs_bfs.php` 复测：缺陷 B 修复后应从 exit=137 转为可跑通，纳入 f177 进度判定 | AOT 运行稳定性 | 低 |
| P1 | 验证 `switch` 内 `break` 指向外层 `while(true)` exit 是否触发同类空分支（推测类似交界未覆盖，需最小复现确认） | 控制流正确性 | 中 |
| P2 | 将跨循环回边识别（exit/回边标签前缀集合 + 方向判定）抽为共享工具 fn，供 while/for/foreach/do_while 四类终符处理器复用 | 可维护性 | 低 |
| P2 | 把 `repro_wbreak.php`（嵌套 foreach + 外层 break）纳入 `fuzzy_scripts_720/pass/` 永久回归集 | 回归覆盖 | 低 |

---

## 复测路径

```bash
cd /Users/wangjianjun/products/parser
T=$(mktemp -d)
# 缺陷B 最小复现（嵌套 foreach 于 while(true)）
./zig-out/bin/php-interpreter --compile --output="$T/wb" fuzzy_scripts_720/tmp/repro_wbreak.php
diff <("$T/wb") <(php fuzzy_scripts_720/tmp/repro_wbreak.php)   # 期望无输出：(w1 ok i=3 / w2 ok i=3 / END)
rm -rf "$T"
```

---

## 核心变更

### `generateForeachFromLabels` cleanup 终符 `.cond_br` 分支（新增）

```zig
.cond_br => {
    // 跨循环条件回边委托外层循环：if(cond){ 物化外层 exit PHI; break :外层 }，
    // false 侧落入外层 while 尾部回边 writeback + continue（else=cond）。
    const cb = term.cond_br;
    const is_loop_exit_label = ...,  // while_exit_/for_exit_/foreach_exit_/do_while_exit_
    const is_loop_backedge_label = ..., // *_cond_/*_body_/*_increment_
    const exit_is_then = is_loop_exit_label(t_lbl);
    if ((fwd or rev) and saved_loop_label != null) {
        const negate = !exit_is_then;             // 反向布局取反条件
        print "if (" + [negate?"!("] + cond + [negate?")"] + ") {"
        outer_exit_idx = 按标签匹配 func.blocks 中的 While exit 块
        if (outer_exit_idx != cond_idx)
            materializeExitPHIOnThenBreak(func, outer_exit_idx, cleanup_idx, oi);
        print "  break :外层;"
        print "}"
    }
}
```

设计要点：不依赖 `saved_exit_block/saved_cond_block`（边界映射会把外层 while 的 cond 误解析为内层 foreach cond）；exit PHI 物化在 break 前发出，否则读回回边残留旧值。

---

## 回归概览

| 范围 | 结果 |
|------|------|
| 首要目标 | `repro_wbreak.php`（嵌套 foreach + 外层 break）：AOT 运行 `w1 ok i=3 / w2 ok i=3 / END` 与真实 PHP 一致（修复前 w2 死循环） |
| `repro_whiletrue_break.php` | 同构最小用例，验证同路径 |
| 全量 pass（108 脚本） | 复跑待本轮全量回归确认（预期 ≥49 Pass，f177 有望转 PASS/收敛） |

---

## 遗留与后续建议

- 跨循环委托人前覆盖 while/for/foreach/do_while 前缀；`switch` 内嵌于 while(true) 的 break 交界未验证（见上 P1）。
- `f177` 真实脚本还叠加其他复杂度（dijkstra/DFS/BFS 多算法），复测通过后应更新其状态评估。

---

# 补充轮（commit `6245443`）：f177 完全跑通

> 变更标识：`nested_loop_condbr_f177` | 详情文档：`docs/changes/2026-08-25/nested_loop_condbr_f177_6245443.md`
> 编译状态：✅ `zig build` 通过 | 全量回归：✅ 零新增

## TL;DR

缺陷 B 修复后 `f177` 虽不再 OOM，但仍死循环/超时。本轮定位并修复 `generateLabelDrivenBlockRange` 共享终符处理器中 **4 类相互交织的缺陷**，使 `f177_graph_traversal_dfs_bfs.php`（dijkstra / 有向+无向环检测 / 拓扑排序）**完全 PASS，输出与 PHP 解释器逐字符一致**。

**4 类修复**：
1. **循环 increment/PHI/continue 门控误判（5 处统一）**：移除 `!self.return_generated`，仅留 `!self.break_generated and !self.lastLineIsReturn(writer)`。原逻辑在"条件性 return"（如 `elseif ($neighbor !== $parent) return true;`）后误跳 foreach 迭代器 `php_array_iter_next` → 无向图环检测挂死（`repro_und_edge` A↔B）。
2. **嵌套 cond_br 范围倒置吞块（foreach/do-while 2 处）**：then 尾部 `if(cond) return` 且 else 为循环延续块时，原用 else 的 `.br` 循环回边（如 `foreach_increment_2 br foreach_cond_0`）推导 `nested_end`，回边索引 < start → 范围空 → 递归返回分支被吞（dfs 环检测返回 N）。改为内联 `if(cond){ then }`。
3. **if 无 else 直落 merge 的 else 边 PHI 未物化**：`then_br_to_else` 分支补发 `} else {` + else 边 merge PHI 物化，消除跨迭代陈值污染（`repro_wd` 中 `$minVertex` 残留 → dijkstra 死循环）。
4. **then_end 乱序退化（5 处对称副本）**：else 块索引在 then 之前时 `range(nti, nei)` 为空吞掉 then 分支（`return`/副作用），退化为 `nti+1` 仅处理 then 块本身。

## 验证

| 用例 | 结果 |
|------|------|
| `repro_wd.php`（dijkstra 最小复现） | AOT 输出与 PHP 一致 |
| `repro_und_edge.php`（无向 A↔B 环检测） | `u1=N visited1_keys=A,B` 与 PHP 一致 |
| `repro_cycle_pure.php` / `repro_dfs_acyclic.php` | 环检测/无环链返回与 PHP 一致 |
| `f177_graph_traversal_dfs_bfs.php` | 从 exit=137/124 → **PASS** |
| 全量 114 pass 脚本回归 | **零新增回归**；f177 移出失败集 |

## 本轮遗留

- **f032**：基线失败集内（`FAIL_DIFF`）→ 本轮 `AOT_FAIL`（同一 OOP 方法链分发缺陷不同表现），仍在基线 108 失败集内，**非新增回归**，纳入后续 AOT 缺陷跟踪（详见详情文档 §7）。