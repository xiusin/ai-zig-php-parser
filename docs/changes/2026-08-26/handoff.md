# 交接文档：if/coalesce/else if 的 merge PHI 物化与共享 return 修复 — Session 2026-08-26

> 日期：2026-08-26 | 涉及文件：`src/aot/native_linker.zig`（未提交工作区改动）
> 变更标识：`if_else_coalesce_merge_phi_codegen`（基于 HEAD `f24d913`，本轮 166 行新增/8 行删除，工作区待提交）
> 编译状态：✅ `zig build` 通过（`zig-out/bin/php-interpreter` 08:31 重建）
> 上级交接链：`docs/changes/2026-08-25/handoff.md`（f177 完全跑通，`6245443`）
> 详情文档：`docs/changes/2026-08-26/if_else_coalesce_merge_phi_codegen_f24d913.md`
> 会话功能目标：啃下 f032（责任链 + 中间件管道）Test1 全链路返回 null 的深层方法链返回值传播丢失 + `parent::handle` 传 null 问题

---

## TL;DR

攻下 f032（上轮 P1 态度目标）：责任链 + 中间件管道中，**else/coalesce 分支持续里 merge 块 PHI 未物化 + 共享 return 丢失**，导致：
- 旧 AOT：f032 Test1 全链路返回 `null`（PHP 应输出完整数组），且 AuthHandler 返回 `["Authentication required"]`（错误短路）。
- 修复后：f032 AOT 输出与系统 PHP 8.5.8 **逐字节一致**（含 `\/` 转义、`rate_limit_remaining:2`、Test3 限流消息）。

**根因（`generateIfFromLabels` 三条独立缺陷，叠加）**：
1. **隐式 else PHI 未消解**：`else_idx == merge_idx`（if 无显式 else / elseif false 边直落 merge）时，Step 7b 守卫 `else_idx == null` 不触发 → merge PHI 在 false 边未物化 → 后续读 null（正是 `parent::handle` 收 null 的根因）。修复：守卫扩展为 `(else_idx == null or is_else_is_merge)`。
2. **共享 return 丢失**：外层 if 无显式 else 时 `merge_idx==null` 但 `else_idx` 是汇聚块，merge 被当独立 else 内联 → 尾随 ret 被吞，函数尾部退化为 `return initNull()`。修复：`merge_idx` 提升为 `else_idx`（多前驱时）。
3. **嵌套 else 分支被整块吞掉**：Step 5 内联嵌套 then 后把 else 块标 processed 却不生成 → 嵌套 `if($x===1){}else{}` 的 `$req['b']=2` 丢失、coalesce 赋值 `$req['v'] = $req['resp'] ?? 'default'` 丢失。修复：新增 `nested_else_is_outer_merge` / `nested_else_is_nested_merge` 双路判定——外层 merge 仅闭合 if，独立嵌套 else 就地生成完整指令 + PHI 物化，内部 merge（coalesce_merge_）仅物化 PHI、merge 体在 if/else 后共享生成。

**成果**：`min_c3.php`、`min_chain.php`、`r_al/b/bco`、`repro_chain5.php` 等最小复现全部通过；`f177`、`f032` 均在 pass 集回归中通过。

---

## 全量回归结论（零新增）

对 `fuzzy_scripts_720/pass` 全部 **114 个用例**（AOT vs 系统 `php 8.5.8`，按 `batch_test_pass.sh` 同一套规范化规则）：
- PASS 77、RUNTIME_DIFF 31、TIMEOUT 6。
- **所有 37 个失败用例全部命中 `regression_failures.tsv`（108 条）基线，零新增回归。**
- 基线中 **71 个用例现已实测通过**（含本轮目标 f032、f177、f027 等），基线未改动（保留现状，避免大范围删除风险）。

> 注：项目自带解释器 `zig-out/bin/php-interpreter file.php` 对 f032 的 Test2/Test3 有异常（Test1 `rate_limit_remaining` 为 null、Test2 后中断），属解释器模式缺陷，超出 AOT 修复范围，按宪法未动，需用户确认后另行评估。

---

## 后续建议（承接）

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|---------|
| P1 | 更新 `regression_failures.tsv`：将 71 个已实测通过用例移出基线，使基线贴近现状（需用户确认删除范围） | 回归基线准确性 | 低 |
| P1 | 排查项目解释器对 f032 的异常（remaining=null、Test2 后中断）——若 f032 需同时过解释器模式，须先确认修复范围是否含解释器 | 解释器模式 | 中 |
| P2 | 将 `countPredecessors`/标签前缀（`coalesce_merge_`/`logical_merge_`）等多处 `generateIfFromLabels` 判定抽为共享工具，避免后续散布 | 可维护性 | 低 |
| P2 | 把 `min_c3.php`/`min_chain.php`（嵌套 if/else + coalesce 赋值 + 共享 return 的最小复现）纳入 `fuzzy_scripts_720/pass/` 永久回归集 | 回归覆盖 | 低 |

---

## 复测路径

```bash
cd /Users/wangjianjun/products/parser
# 重建
env -i PATH="/opt/homebrew/bin:/usr/bin:/bin" HOME="$HOME" \
  SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" \
  python3 bin/to.py 240 zig build
# 最小复现
python3 bin/to.py 40 ./zig-out/bin/php-interpreter --compile --no-debug-info fuzzy_scripts_720/tmp/min_chain.php
python3 bin/to.py 10 fuzzy_scripts_720/tmp/aot_compile_min_chain   # 应与 php 输出一致
# f032
python3 bin/to.py 80 ./zig-out/bin/php-interpreter --compile --no-debug-info fuzzy_scripts_720/pass/f032_chain_responsibility_middleware.php
python3 bin/to.py 10 fuzzy_scripts_720/pass/aot_compile_f032_chain_responsibility_middleware
diff <(python3 bin/to.py 10 php fuzzy_scripts_720/pass/f032_chain_responsibility_middleware.php 2>/dev/null) /tmp/f032_aot.txt
```

---

## 复测结果快照

- `min_c3.php`：AOT `a=NULL b=2 / a2=1 b2=NULL`，与系统 PHP 一致（`b=2` 修复即本会话核心）。
- `min_chain.php`：AOT `v='default' e='n' / 2nd cached=true v=NULL`，与 PHP 一致。
- `f032`：与系统 PHP 逐字节一致。
- `f177`：pass 集回归通过。