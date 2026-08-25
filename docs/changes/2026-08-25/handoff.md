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