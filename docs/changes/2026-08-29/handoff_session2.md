# 交接文档（会话 2）：&&/|| 短路链根治 + if-without-else 系列修复 — 进行中：f085 单语句 if-continue 缺陷

> 日期：2026-08-29 | 涉及文件：`src/aot/native_linker.zig`
> 当前 HEAD：`77872d7`（已提交）；工作区：**有未提交改动**（1 个诊断探针，见 §6.4）
> 上级交接链：
> - `docs/changes/2026-08-29/handoff.md`（会话 1 上半段：f028 死循环修复待办快照，已全部闭环）
> - `docs/changes/2026-08-29/f028_nested_else_phi_loop_backedge_081942_c6e3d37.md`（f028 闭环摘要）
> 用户指令：**"继续修复不要停，已知问题始终修复"** —— 持续消灭基线失败项

---

## 1. TL;DR

本会话在 f028 闭环之后，顺着 f044 残留差异一路深挖，**根治了 &&/|| 短路链发射与 if-without-else 两大缺陷家族**（6 组修复，提交 `77872d7`，+858/-334）：

- **f044 与 PHP 逐字节一致**（该脚本进基线以来首次）
- 全量回归 108 用例：**零新增**，**8 个基线失败转通过**（f012/f028/f044/f045/f072/f080/f097/f105），f085 由 FAIL_RUNTIME 改善为 FAIL_DIFF，PASS 72 → 80
- 期间连环定位并修复：短路链吞分支（多处）、box 指令 RC 失衡导致递归键悬空、共享延续块被误内联进 else 导致的死循环

**正在进行**：f085 残留 FAIL_DIFF —— `foreach` 内单语句 `if ($k === $name) continue;` 被发射成空 if/else + 循环体无条件执行（诊断到一半，探针已插 1/2，见 §6）。

---

## 2. 提交链（本会话产出）

| 提交 | 内容 |
|------|------|
| `c6e3d37` | f028 修复：loop_last_be 迭代扩展 + materializeBrTargetMergePhis（含 logical_ 守卫）|
| `5934cf2` | f028 交接与摘要文档 |
| `77872d7` | **本轮主体**：短路链与 if-without-else 六组修复（详见 §3）|
| 工作区 | 未提交：1 个 `[[PROBE-FORE coalesce ...]]` 探针（§6.4），诊断 f085 用 |

---

## 3. `77872d7` 六组修复清单（含归因）

| # | 修复 | 位置（提交后行号，±20） | 归因/症状 |
|---|------|------|-----------|
| 1 | foreach 生成器 `pending_merge_non_phi`：merge 块以 **cond_br** 结尾时，不再「预发射非 PHI 指令 + 标记 processed + 从 mi+1 递归」（该旧路径把 cond_br 整个吞掉），改为**整体移交主循环** `generateLabelDrivenBlockRange(mi, loop_end)` | `generateForeachFromLabels` 内 ~9735 | **f044 flatten**：`is_array && !empty && !array_is_list` 的第一个守卫块是 `ternary_merge_7`（带 cond_br），旧路径吞分支 → 条件恒假/退化 |
| 2 | 移除 `materializeBrTargetMergePhis` 的 `logical_` 临时守卫 | ~8543 | 守卫是 c6e3d37 为止血 f044 TypeError 加的；#1 修复短路链后放开 |
| 3 | **box 指令发射改为所有者语义**：`条件释放旧值 + 赋值 + retain`（对齐 cast）；原来是裸别名 `reg_33 = reg_32`，cleanup 把源/目标都释放 → 双重释放 | `generateInstructionSimple` 的 `.box`，~15931 | **递归 foreach 末位键悬空**：`$path` 字符串在帧末被过度释放，数组键变 `''`（repro_sc_rec/flatten）。注意：这是**既有缺陷**（fc4417f 之前就有），被短路链修复暴露 |
| 4 | else 侧嵌套 cond_br 增加 **&&/|| 短路链检测**：`sc_is_and`（else 目标 == logical_merge_）/`sc_is_or`（then 目标 == logical_merge_），真/假边分别物化 merge PHI，替代旧的 `[nti, nmi+1)` 线性范围发射 | 主循环 `.cond_br` case 的 else 侧 ~8116 | **deepDiff elseif 条件退化**：`!$inA && $inB` 恒等于 `$inB`（假边不物化 + rhs 无条件执行）|
| 5 | 6 处 elseif 链处理器（foreach/for/while 生成器各 2 处）增加 **if-without-else 守卫**（`nested_then_br_to_else`）：then 块 br 目标 == else 块时，发射 `if(cond){then}`（内联 then 指令 + then 边 PHI 物化），else 块作为**共享延续**在 if 闭合后经主循环发射 | ~9348/9549/11030/11231/12307/12489 | 共享延续块（循环增量/回边/函数延续）被当作 elseif 的 else 体内联 |
| 6 | `if_merge_+cond_br` 处理器（6957）的 `else_has_real_body` 判定增加 **then-br-to-else 检测**：then br 直落 else 块 → 判为非真实 else 体，走既有短路流程（空 else + 闭合后主循环发射延续块） | ~6996 | **repro_sc_twoif 死循环**：`foreach 内两个顺序 if 修改同一变量`，循环增量块 `if_merge_8` 被误判为 if2 的真实 else 体 → 增量只在条件假路径执行 → 死循环。陈年缺陷（07a0e60 之前就在）|

> #5 曾先用 `break;` 实现（3 处编译错"break outside loop"，另 3 处会错误跳出外层循环），后用一次性脚本机械改写为 `if/else` 包裹（64 行 × 6 处重缩进，这是 +858/-334 的主要来源）。脚本已删。

---

## 4. 验证结果

| 验证项 | 结果 |
|--------|------|
| `repro_sc_*` mini 全家桶（§7） | 全部与 PHP 一致 |
| `f044_json_deepops_merge_diff.php` | **IDENTICAL**（逐字节）|
| `repro_lcs_repro.php` / `repro_phi001.php` | 通过（f028/PHI-001 不回退）|
| 全量回归 `fuzzy_scripts_720/run_regression.sh`（108 用例） | **零新增**；8 个基线失败转 PASS；f085 FAIL_RUNTIME→FAIL_DIFF；PASS=80 FAIL=28 |
| 基线文件 | 回归后已 `git restore`（保持 108 条不收缩；收缩需用户定夺）|

---

## 5. 关键代码地图（77872d7 基线，行号 ±20；均带唯一中文注释可 grep）

```text
generateLabelDrivenBlockRange        ~6878   主循环分派器（foreach_/for_/while_/if_then_/if_merge_/ternary_/coalesce_/do_while_ 前缀）
├─ if_merge_ + cond_br 处理器         ~6957   「else_has_real_body」判定 ~6996（#6 修复点）
├─ 普通线性块 .br（change-1 物化）     ~7287   br_was_backedge 标记 + materializeBrTargetMergePhis
├─ 普通线性块 .cond_br                ~7352   隐式 if/else；7370 双目标已处理跳过；
│   ├─ then 边 PHI 物化               ~7822
│   ├─ then_br_to_else                ~7858   「if 无 else」+ else 边物化 ~7911
│   ├─ else_is_coalesce_merge         ~7948
│   └─ else 侧嵌套 cond_br（#4 短路链守卫） ~8116
├─ merge 块处理（if 闭合后）           ~8304
materializeBrTargetMergePhis          ~8543   非回边「线性块→merge」边 PHI 物化（无守卫了）
generateForeachFromLabels             ~8591
├─ isLoopBackEdge（局部 struct fn）    ~8964   ptr==cond/inc 或 br→cond 为回边；**br→inc 不算**
├─ body cond_br 发射                  ~8978   if_indent=body_indent
│   ├─ then 处理                      ~9005   then_is_be/logical_merge_to_process/merge_bi
│   ├─ else 分派                      ~9255   else_is_coalesce(9257,有探针)/else_is_be(9281)/then_is_be(9283)/普通(9332+)
│   ├─ else 嵌套 cond_br ×2（#5 守卫） ~9348/~9549
│   └─ else .br→merge-with-cond_br → pending_merge_non_phi  ~9453-9488
└─ pending_merge_non_phi 发射（#1 修复）~9735   cond_br 结尾 → 移交主循环
for 生成器同构代码                     ~11030/~11231（#5 守卫 ×2）
while 生成器同构代码                   ~12307/~12489（#5 守卫 ×2，变体内联式）
generateIfFromLabels                  ~12445  Step10 merge cond_br 提前返回 ~13710
box 发射（#3）                         ~15931
phi 注释发射「(handled in terminator)」 ~20330
```

运行时参考：`src/aot/runtime_lib_template.zig` —— `set` 会 retain 字符串键（~2157）；`cloneShallow`（~2016）快路径走 `packed_values`（list 数组）；快照迭代器 `php_array_iter_init_snapshot`（~7698）= cloneShallow + 原地推进（`iter_next` 返回同一指针，cond 块迭代器 PHI 物化与否通常无害）。

---

## 6. 进行中：f085 残留 FAIL_DIFF（单语句 if-continue 缺陷）

### 6.1 症状

`f085_geo_rtree_knn_geocoder.php` 的 GeoCoder::findNearby 输出多出查询点自身：

```text
AOT 多: "  Beijing: 0km"（Nearby Beijing 段）/ "  Shanghai: 0km"（Nearby Shanghai 段）
```

源码（f085:147-148）：

```php
foreach ($this->locations as $locName => $loc) {
    if ($locName === $name) continue;      // ← 单语句 if-continue，被 AOT 丢失
    ...
}
```

### 6.2 最小复现（已确认无类版即可复现）

`fuzzy_scripts_720/tmp/repro_sc_knn3.php`：

```php
function findNearby(array $locations, string $name): array {
    $nearby = [];
    foreach ($locations as $locName => $loc) {
        if ($locName === $name) continue;
        $nearby[$locName] = $loc;
    }
    return $nearby;
}
```

变体对照：`repro_sc_knn.php`（类方法版，复现）；`repro_sc_knn2.php`（if 带 `{ echo; continue; }` 块体 → **正常**）。即：**单语句**形态是触发器。

### 6.3 IR 结构（knn3 的 findNearby，已核实）

```text
foreach_body_1:
  ... reg_18 = identical(reg_16, reg_17)
  br reg_18, foreach_increment_2, if_merge_6     ← 真边=continue（折叠为跳增量块）；假边=循环体剩余（标签误名 if_merge_6）
foreach_increment_2: iter_next; br foreach_cond_0
if_merge_6:
  array.set $nearby[key] = value; store
  br foreach_increment_2
```

**错误发射形态**（当前生成代码）：

```zig
if (reg_18.toBool()) {
} else {
}
// if_merge_6 的 body（array.set）被无条件发射在 if/else 之后 → 每次迭代都执行 → Beijing 不被跳过
reg_21 = val_deref(reg_5).*; ... setByValue(reg_12, reg_14); ...
reg_23 = iter_next(reg_28);
```

### 6.4 诊断进度与探针状态

- 嫌疑区域：`generateForeachFromLabels` body cond_br 的 else 分派（§5 树）。静态推演：`then_is_be` 应为 true（then==increment 块），预期走 9283 分支把 if_merge_6 发射进 `} else {` —— 但实际生成了空 else，说明**实际路径与推演不符**，需实证。
- **已插探针 1**（工作区未提交）：`else_is_coalesce` 分支，打印 `[[PROBE-FORE coalesce else=...]]`（foreach 版，~9258）。
- **探针 2 未插成功**：目标是 `} else if (else_is_be) {` / `} else if (then_is_be) {` 分支（9281/9283）。两次 Edit 失败——同文本在 foreach 与 while 生成器各一份（9281 与 10963）。**插入办法**：以探针 1 的 `PROBE-FORE coalesce` 行为锚点扩大 old_string 范围，或用 `sed -i` 按行号插入（插入内容见下）。

```zig
// else_is_be 分支内首行：
std.debug.print("[[PROBE-FORE else_be then_is_be={any} else={s}]]\n", .{ then_is_be, if (else_bi) |ei| func.blocks.items[ei].label else "?" });
// then_is_be 分支内首行：
std.debug.print("[[PROBE-FORE then_be else={s} proc={any} merge={s}]]\n", .{ if (else_bi) |ei| func.blocks.items[ei].label else "?", if (else_bi) |ei| processed.contains(ei) else false, if (merge_bi) |mi| func.blocks.items[mi].label else "null" });
```

### 6.5 下一步（按序执行）

1. 按 §6.4 插入探针 2（注意只插 foreach 版 9281/9283；10963 是 while 版，别插错——插错也不致命，输出会暴露）。
2. `zig build`（本会话 `zig build` 一直正常；无 `timeout` 命令，用 `perl -e 'alarm 10; exec @ARGV'` 包裹运行）。
3. 编译 `repro_sc_knn3.php`，stderr 抓 `PROBE-FORE`，确定实际走的分支与 `else_bi/processed/merge_bi` 状态。
4. 按实证结果修复。**修复方向预判**：此 IR 形态（then=增量块=continue 折叠，else=循环体剩余）的正确发射是 `if (!cond) { body }`（或空 then + else 装 body）——body 末尾自然落回循环尾的统一增量发射，**无需显式 continue**。警惕：若 then 边语义不只是"跳过 body"（如真回边），不能简单反转。
5. 修后验证顺序：`repro_sc_knn{,2,3}` → f085 与 PHP diff → `repro_sc_twoif`/`and2`/`diff10`/`flatten`（防回退）→ LCS/PHI001 → **全量回归**（~35 分钟，`nohup bash fuzzy_scripts_720/run_regression.sh > /tmp/reg.log 2>&1 &`，完成后与基线 `/tmp/baseline_regression_failures_20260829.tsv` 对比：`grep -v '^PASS|' ... | cut -d'|' -f1,2 | sort` 后 comm；注意 comm 输入必须纯名字排序，类型混杂会误报）。
6. **清理全部 `PROBE-FORE` 探针**再提交（探针只进编译器 stderr、不进生成代码，但提交前必须清）。

### 6.6 风险与注意

- 该缺陷可能不止 foreach：for/while 生成器有同构的 else 分派代码（~10963 等），修复时检查是否需要同步。
- 「单语句 if + continue/break」家族可能还有未暴露变体（如 `if (...) break;`），修完 knn3 建议补一个 `break` 版 mini 验证。
- f085 若转 PASS，基线失败降至 27——**不要动基线文件**（用户未批准收缩），回归后 `git restore`。

---

## 7. 复现脚本清单（`fuzzy_scripts_720/tmp/`，均本会话创建，勿删勿入 pass/）

| 脚本 | 覆盖缺陷 | 当前状态 |
|------|----------|----------|
| `repro_sc_twoif.php` | #6 双顺序 if 死循环 | 通过 |
| `repro_sc_and1.php` / `repro_sc_and2.php` | #4 elseif && 短路 | 通过 |
| `repro_sc_diff.php` ~ `repro_sc_diff15.php` | f044 deepDiff 二分系列（10/14 为关键形态） | 通过 |
| `repro_sc_rec.php` / `rec2` / `rec3` / `rec4` | #3 box RC / 递归 | 通过 |
| `repro_sc_flatten.php` / `flatten2` / `flatten3` | #1+#3 flatten 递归 | 通过 |
| `repro_sc_merge.php` / `repro_sc_ret.php` | array_merge/返回路径（对照组） | 通过 |
| `repro_sc_knn.php` / `knn2` / `knn3` | **§6 在办缺陷**（knn3 最小复现） | **失败** |
| `repro_lcs_repro.php` / `repro_phi001.php` | f028 / PHI-001 哨兵 | 通过 |

> `repro_lcs_backtrack_only.php` 自身在 PHP 下即 TypeError（脚本返回类型声明错误），是遗留调试脚本，勿用勿入库。

---

## 8. 遗留问题 / 待办

| 优先级 | 事项 |
|--------|------|
| **P0** | §6：f085 单语句 if-continue 缺陷（在办）|
| P1 | `AOT-CODEGEN-003`（while(true) break 缺失）剩余部分，验证与本轮 if-without-else 家族是否同源 |
| P1 | 基线收缩决策：实测 80 PASS vs 基线 108 条（~80 条已可通过），待用户定夺 |
| P2 | 其余 28 条基线失败逐个攻坚（用户指令：已知问题始终修复）|
| P2 | `repro_lcs_repro.php`/`repro_phi001.php`/`repro_sc_*` 关键形态提炼入 `pass/` 永久回归集（需用户确认命名）|
| P2 | `repro_lcs_backtrack_only.php` 修正或删除（需用户确认）|

---

## 9. 后续建议

| 优先级 | 建议 | 影响面 | 成本 |
|--------|------|--------|------|
| P1 | foreach/for/while 三份同构的「body cond_br else 分派」抽共享方法（本轮 6 处守卫 ×3 份的重复是维护隐患）| 可维护性 | 中 |
| P1 | 「merge PHI 物化」收敛单一入口（按边物化），消除 then/else 不对称缺口 | 正确性 | 中 |
| P2 | `cast`/`box`/`move` 别名类指令做一次统一的 owner 语义审计（#3 可能不是孤例）| 正确性 | 中 |

---

## 10. 会话状态速查

- **分支/提交**：main @ `77872d7`，领先 origin 21 个提交（未推送）。
- **工作区**：`src/aot/native_linker.zig` 有 1 处未提交探针（`[[PROBE-FORE coalesce`，foreach 版 else_is_coalesce 分支）；基线/报告文件干净。
- **构建**：`zig build`（ReleaseSafe，~1-5 分钟增量）；本会话未复现「含空格路径」问题。
- **超时技巧**：mac 无 `timeout`；运行 AOT 产物用 `perl -e 'alarm 10; exec @ARGV' "$bin"`；长回归用 `nohup ... &` + `kill -0 PID` 查活。
- **回归基线备份**：`/tmp/baseline_regression_failures_20260829.tsv`（108 条；如丢失可从 `git show 5934cf2:fuzzy_scripts_720/regression_failures.tsv` 恢复）。
- **诊断产物**：`/tmp/regression_20260829_v3.log`、`/tmp/sc_wip2.patch`（77872d7 前快照，可删）。
