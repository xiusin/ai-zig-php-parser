# foreach 体内静默丢语句：后置单语句 `if-break` 整臂丢失 + 前置 `if` 臂内嵌套 `for` 塌缩为仅初始化

**问题 ID**: AOT-CODEGEN-005
**优先级**: P0（**静默语句丢失**：编译成功、运行成功、退出码 0，仅输出与 PHP 不一致，且语料 68 脚本未覆盖该形状）
**状态**: **CLOSED（2026-09-30，RC-1 / RC-2 / RC-3 落地并通过 §5 全门）— 提交 `b21cdfd`；RC-4（①+②）已于 2026-10-01 落地在工作区（未提交），§5 全门六项**已全部实测通过**（见 §7 行 7），RC-5 为同族第五形状、已取证到行待裁决**
- **RC-1**（后置单语句 `if-break` 臂丢失）：`isLoopContinueTarget` 成对谓词 + `if_merge_`+`cond_br` 处理器就地发 break（:924 / :7306）。
- **RC-2**（foreach 侧臂内嵌 `for` 塌缩）：移植 for 侧 `for_loop_exit_is_outer_merge` 到 foreach 派发点（:11528），带 `blk_i >= loop_end` + `if_merge_` 两道前提。
- **RC-3**（while 侧臂内嵌 `for/foreach/while` 整块丢失，新）：`generateWhileFromLabels` 的 body-if then 臂尾 `.br` **原本没有任何循环头派发**（非 exit/非 cond 一律 `merge_bi = blk_i`）⇒ 补循环头派发表 + 「内层 for 出口复用本 if 的 `if_merge_`」救援分支（:15183 起）。**取证否证了 RC-2 的「区间截断」前提可复用**：while 侧 `loop_last_be` 迭代扩展后 `loop_end=8` 已覆盖 for 块（非截断），真正致损的是 merge 体被内联进 then 臂 ⇒ RC-3 只留三条结构判据，不含 `blk_i >= loop_end`。
- **全门实测（2026-09-30，RC-1+RC-2+RC-3 二进制 + REF-002 R-1a/R-1b 模板，合并一轮）**：16 探针门 `same=16/16 differs=0`（含函数上下文 J、RC-3 新增形态 P/Q/R，以及 do-while 侧同族 S）；`zig build test` RC=0；官方 68 回归 **PASS=67 / FAIL_COMPILE=0 / FAIL_RUNTIME=0 / FAIL_DIFF=0 / SKIP=1(f004)**；冻结基线全量漂移 **`total=68 ok=68 diff=0 notemp=0 norow=0`**；确定性巡检 **`total=68 mismatch=0 notemp=0`**；基线抽查 **`ok=5 bad=0`** ⇒ **零漂移、零回归**，无需重冻结基线。
- **CLOSED 之后新登记的候选（不重开本工单）**：2026-10-01 在 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) 的归因探针 `ref003_crash_attr_tmp.php` 上实测到同族**第四形状** —— 同一 if 臂内、内层 `for` **之后**的裸 `break` 未发射（W2 PHP `visited=1` vs AOT `visited=5`）。16 探针门未覆盖该形状 ⇒ 登记为 **RC-4**。**2026-10-01 同日取证完成**：根因是「臂尾无条件 `break`/`continue` 被 IR 折叠进内层循环的出口边」+「三个循环生成器的臂尾派发救援判据只覆盖 `if_merge_` 复用形态」⇒ 截空区间零发射零标记，内层循环整块丢失并在循环外被重发（详见 §4 RC-4）。**2026-10-01 同日修复落地（① 派发门控放宽 + ② 出口边语义，纯新增 +145 行，未提交）**：Y1MIN 与六形 Y1–Y5、`ref003_crash_attr` W1/W2 均**逐字节等值**；① 单独落地时 16 探针门 `same=16/16 differs=0` 已实证零回归（详见 §4 RC-4「分步落地实测」行）。**验收期间由 ② 的实测暴露同族第五形状 ⇒ 另立 RC-5（臂尾 `continue` + if 有真实 merge 块 ⇒ 延续块兄弟语句丢失）；2026-10-01 已把根因取证到行**（`generateLabelDrivenBlockRange` 的 mark-rest 扫描 :7206–7211，随 `break_generated` 置位把延续块整段吞进 `processed`），**并拆为两个互不耦合的 facet**（facet-1 丢失延续块、facet-2 臂尾 `continue` 未翻译），**未经裁决不改一行代码**（§7 行 9）。RC-4 的 §5 全门六项已于同日实测闭环（§7 行 7）。
**发现日期**: 2026-09-30（AOT-REF-002 引用探针取证过程中顺带暴露，与引用无关）
**关联**: [AOT-REF-002 §3.1](AOT-REF-002-iter-ref-slot-dangling.md)（发现上下文）；历史同类 #16「while 体内嵌套 if-without-else 的 merge 臂丢失」、f085「单语句 if-continue/if-break 发射缺陷」

---

## 1. 复现（永久探针，勿删）

```php
$a = [];
for ($i = 0; $i < 20; $i++) { $a['k' . $i] = $i; }
$hits = 0;
foreach ($a as $key => $value) {
    $hits++;
    if ($hits === 1) {
        for ($j = 0; $j < 40; $j++) { $a['g' . $j] = -$j; }   // 臂① 整块未发射
    }
    if ($hits > 3) {
        break;                                                  // 臂② 整块未发射
    }
}
echo "F hits=", $hits, " count=", count($a), "\n";
```

📄 `fuzzy_scripts_720/tmp/ref002_iso_f_break_after_nested_for_tmp.php`

| 侧 | 输出 | 解读 |
|---|---|---|
| PHP 8.5 | `F hits=4 count=60` | 臂①执行 1 次（20+40=60），臂②在第 4 轮 break |
| AOT | `F hits=20 count=20` | 两个臂**都没执行**：外层跑满原集合 20 轮，数组从未增长 |

编译与运行均无错误、无告警（`rc=0`，stderr 空）⇒ 属**静默丢失**，不是降级也不是运行期缺陷。

## 2. 因子 bisect 矩阵（2026-09-30 实测，逐字节比对）

| 探针 | 臂① 条件 | 臂① 体 | 臂② `if-break` | PHP | AOT | 读出 |
|---|---|---|---|---|---|---|
| `ref002_iso_a_break_foreach_tmp` | —（无前置兄弟） | — | 有 | `hits=4 count=20` | 等值 | 无前置块时 break 正常 |
| `ref002_iso_b_foreach_snapshot_tmp` | `$first` 旗标 | 嵌套 for | 无 | `hits=20 count=60` | 等值 | 无后置 break 时嵌套 for 正常 |
| `ref002_iso_h_no_break_tmp` | `$hits === 1` | 嵌套 for | 无 | `hits=20 count=60` | 等值 | 同上，且与条件形态无关 |
| `ref002_iso_i_no_nested_for_tmp` | `$hits === 1` | 单条赋值 | 有 | `hits=4 count=21` | **`hits=20`** `count=21` | 臂①正常发射 ⇒ **内层 for 不是 break 丢失的必要因子** |
| `ref002_iso_f_break_after_nested_for_tmp` | `$hits === 1` | 嵌套 for | 有 | `hits=4 count=60` | `hits=20 count=20` | 两臂同时失效 |
| `ref002_iso_g_flag_and_break_tmp` | `$first` 旗标 | 嵌套 for | 有 | `hits=4 count=60` | `hits=20 count=20` | 与 F 同 ⇒ **`===` vs bool 旗标无关** |

⇒ 这是**两个独立失效点**，不是一个：

1. **`break` 丢失**：必要条件是「foreach 体内存在**前置的无 `else` 兄弟 `if` 块**」。A（无前置）正常；I/F/G（有前置）全部丢失，与前置臂的内容（赋值 / 嵌套 for）和条件形态（`===` / 旗标）均无关。
2. **嵌套 `for` 塌缩**：当前置 `if` 臂内含 `for`、且其后还有 `if-break` 兄弟时，该 `for` **只剩初始化语句**，条件/体/增量/出口全部消失（H/B 无后置 break 时完全正常）。

## 3. 发射侧取证（2026-09-30，临时 env 门控 trace `ZIGPHP_AOT_T005`，取证后已剥离）

取证手法：在 `generateLabelDrivenBlockRange` 主循环（VISIT/STOP）与 `generateForeachFromLabels` 的 body `cond_br` 分支（块布局 dump + then 臂 `.br` 派发）挂 `std.c.getenv("ZIGPHP_AOT_T005") != null` 门控打印 ⇒ 未设环境变量时零行为变化。取证完成后四处 trace 全部剥离，`git diff src/aot/native_linker.zig` 行数 = **0**（回到取证前的暂存态），复建 `zig build` RC=0。

### 3.1 F 探针的完整 IR 块布局（顶层脚本，函数共 12 块）

| idx | label | 终止符 | 目标 | ninst | 角色 |
|---|---|---|---|---|---|
| 4 | `foreach_cond_5` | cond_br | then=5 / else=7 | 2 | 循环条件 |
| 5 | `foreach_body_6` | cond_br | **then=8 / else=9** | 11 | 体内 `++$hits` + **臂① 的 if** |
| 6 | `foreach_increment_7` | br | 4 | 3 | 回边（iter_next） |
| 7 | `foreach_cleanup_8` | **ret** | — | 13 | 清理（顶层即 `return`） |
| 8 | `if_then_10` | **br → 10** | 10 | 2 | 臂① then（只含 `$j = 0` 初始化） |
| 9 | `if_merge_11` | **cond_br** | **then=7 / else=6** | 3 | 臂① 的 merge，**同时是臂② `if ($hits>3) break` 的决策块** |
| 10 | `for_cond_12` | cond_br | then=11 / else=9 | 3 | 内层 for 头 |
| 11 | `for_body_13` | br | 10 | 11 | 内层 for 体（`$a['g'.$j] = -$j`） |

关键 trace 序列（F）：

```text
[005-FE] cond=4 body=5 inc=6 clean=7 exit=- end_par=12 loop_end=10 then=8 else=9
[005-THENBR] DISPATCH ti=8 tgt=10 label=for_cond_12 loop_end=10 end_par=12   ← 派发区间 [10,10) 为空
[005-RW] VISIT i=9 label=if_merge_11 range=[9,10) ret=0 brk=0                ← 臂② 由 if_merge_ 处理器接管
[005-RW] STOP range=[4,12) at=8 ret=1 brk=0 -> mark processed               ← cleanup 的 return 置 ret=1
[005-RW] STOP range=[0,12) at=4 ret=1 brk=0 -> mark processed
```

⇒ 块 10、11 **从未被任何行走 VISIT**（内层 for 整体未发射）；块 9 被 `if_merge_`+`cond_br` 处理器接管后产出 `main.zig:776` 的空双臂 `if (reg_40.toBool()) { } else { }`。

### 3.2 四探针对照（同一 trace，证明丢失点与布局强相关）

| 探针 | body `cond_br` 的 then/else | 是否存在独立 `if_merge_` 携带第二个 if | `loop_end` | 内层 for 头索引 | 结果 |
|---|---|---|---|---|---|
| `a_break_foreach`（仅 `if-break`，**正常**） | 7(cleanup) / 6(increment) | 否（break 直接是 body 的 cond_br） | 7 | — | `then_is_break` 路径发 `break :__foreach_0` ⇒ 等值 |
| `h_no_break`（臂①含 for，**正常**） | 8 / **6(increment)** | 否（无后置 if ⇒ 假边直接回落 increment） | **11** | 9（< 11，**在区间内**） | `[005-THENBR] DISPATCH tgt=9 loop_end=11` → `[005-RW] VISIT i=9 for_cond_12` ⇒ for 正常发射 |
| `i_no_nested_for`（臂①单赋值 + `if-break`，**臂②丢**） | 8 / 9(`if_merge_11`) | **是**（merge 的 cond_br 目标 = 7/6） | 10 | — | 臂② 走 `if_merge_` 处理器 ⇒ 空双臂 |
| `f_break_after_nested_for`（两者皆有，**双丢**） | 8 / 9 | **是** | **10** | **10（== loop_end，落在区间外）** | 两条根因同时命中 |

⇒ 决定性差异是「**臂①与臂②之间是否插入了一个 `if_merge_` 块**」。该 merge 块一旦出现：① 它自己携带臂② 的 break 决策边，② 它的索引排在臂① 内层 for 块之前，把 for 挤出 `loop_end`。

### 3.3 函数上下文同样丢失（新永久探针 J，勿删）

📄 `fuzzy_scripts_720/tmp/ref002_iso_j_func_context_tmp.php`（F 的形状整体搬进 `function runJ($seed)`）

| 侧 | 输出 | IR 布局 |
|---|---|---|
| PHP 8.5 | `J hits=4 count=60` | 与顶层同构（`loop_end=10`、for 块 10/11、`if_merge_11` cond_br 目标 7/6） |
| AOT | **`J hits=20 count=20`** | 同上，`[005-THENBR] DISPATCH ... loop_end=10` 空区间 |

⇒ 曾疑「函数里 cleanup 不以 `return` 终结，外层行走可能把 for **补发到循环之外**（位置错误）」，被实测**否证**：函数上下文里 `foreach_cleanup_8` 的终止符仍是 `.ret`（函数返回值就是它的后继），`ret=1` 依旧成立 ⇒ 块 10/11 在两种上下文下都是**彻底丢失**，不是位置错误。修复验收必须同时覆盖顶层与函数两种上下文。

## 4. 根因定位（RC-1 / RC-2 / RC-3 / RC-4 四条已到行并落地；RC-5 **已取证到行**（:7206–7211 的 mark-rest 扫描）并拆为两个独立 facet，**待裁决后才落地**）

### RC-1 后置单语句 `if-break` 整臂丢失

| 项 | 内容 |
|---|---|
| 归属 | `native_linker.zig` `generateLabelDrivenBlockRange` 的 **`if_merge_` + `cond_br` 处理器**（入口判定 :7260，then 臂派发守卫 :7417 `if (!processed.contains(nti))`，else 臂同型判定在其后） |
| 机理 | 臂② 的 `if ($hits>3) break` 被 IR 折叠进 `if_merge_11` 的 cond_br，其 then 目标 = 本循环 `foreach_cleanup_8`（块 7）、else 目标 = `foreach_increment_7`（块 6）。而 foreach 收尾早已把这两个块**预标记 processed**（`generateForeachFromLabels` :11229-11232 预标记 increment/cleanup/exit，:12442 标记 cleanup）⇒ 处理器两侧都走「已处理」空分支 ⇒ 只发条件计算与 `if/else` 骨架，**既不生成 `break :label`，也不物化 exit PHI** |
| 已有能力对照 | 「then 目标 == cleanup/exit ⇒ 发本地 break」的能力**确实存在**，但只在两条路径上：① `generateForeachFromLabels` 的 body `cond_br` → `else_is_be` + `then_is_break`（:11586-11596，正是探针 A 走通的路径）；② `writeBrInLoopContext`（:921）经 `isLoopBreakTarget`（:901）处理 `.br` 型 break 边。**`if_merge_`+`cond_br` 处理器两者都没接** |
| 为何 #18 金丝雀没报 | 金丝雀判据是「空 else 臂 + 其后 `unreachable`」；本形态两条边都是**已 processed 的循环块**、且 `unreachable` 指令并不存在，条件不成立 ⇒ foreach 侧的该形态在闸门覆盖之外 |

### RC-2 臂① 内层 `for` 整体丢失（只剩初始化）

| 项 | 内容 |
|---|---|
| 归属 | `native_linker.zig` `generateForeachFromLabels` body `cond_br` 分支的**循环体范围界定**：`loop_last_be` 扫描 :11178-11193 + `const loop_end = @min(end_idx, loop_last_be + 1)` :11195；以及 then 臂尾 `.br → 循环头` 的派发终点 :11471 |
| 机理 | `loop_last_be` 的定义是「**回边块的最大索引**」。本形态里回边块只有块 6（increment）、块 9（merge 的 cond_br 双边飞向 7/6）⇒ `loop_last_be=9`、`loop_end=10`。而内层 for 的块 10/11 索引**恰在 10 之后** ⇒ :11471 拿到空区间 `[10,10)`，for 本体一个块都不发；臂① 只剩块 8 内联发射的 `$j = 0` |
| 闭包为何补不上 | `expandRangeToChainFlow`（:10864）要求「br 目标、或 cond_br **双侧**目标」都落进当前区间才扩张：块 10 的 then=11 在区间外、块 11 的 br=10 也在区间外 ⇒ 不动点不扩张 |
| 后续行走为何救不回 | foreach 内所有尾部行走同样以 `loop_end`/`last_back_edge` 为界（:12249 coalesce 尾部 `[mi, loop_end)`、:12344 `[body_idx+1, last_back_edge+1)`、:12354 `[body_idx+1, next_after_body)` = `[6,6)`）；外层函数行走此时因 cleanup 的 `return` 置 `ret=1` 而 STOP 并把 8..11 标记 processed ⇒ **块 10/11 无任何补发机会** |
| 与 H 的对照 | H 无臂② ⇒ 不存在独立 merge 块，body 的 cond_br 假边直接飞向 increment(6)，`loop_last_be` 由块 9/10/11 的回边推到 ≥10 ⇒ `loop_end=11` 覆盖 for 块 ⇒ 正常。**这证明缺陷只在「merge 块索引 < 嵌套循环块索引」的乱序布局下触发** |

### RC-3 while 侧同族：body-if 的 then 臂尾 `.br` 无循环头派发（新，2026-09-30 实测定位）

探针门第一轮（RC-1+RC-2 二进制，15 探针）暴露的关键分化：**内层循环种类决定命运**。

| 探针 | 外层循环 | 臂①内层 | PHP | AOT（RC-2 后） | 读出 |
|---|---|---|---|---|---|
| `c005_n_while_nested_for_break_tmp` | while | **for** | `hits=4 count=40` | **`hits=4 count=0`** | for 整块丢失 |
| `c005_p_while_nested_foreach_tmp` | while | foreach | `hits=4 count=4` | `hits=4 count=0` | foreach 整块丢失 |
| `c005_q_while_nested_while_tmp` | while | while | `hits=4 count=40` | `hits=4 count=0` | while 整块丢失 |
| `c005_r_while_else_nested_for_tmp` | while | for（在 **else** 臂） | `hits=4 count=11` | 等值 | else 臂路径已具备派发 |
| `c005_o_for_nested_for_break_tmp` | for | for | `hits=4 count=40` | 等值 | for 侧 :13622 派发已存在 |

⇒ 缺陷在 **`generateWhileFromLabels` 的 body `cond_br` → then 块 `.br` 处理**（:15183 起）：该处对「br 到非 exit/非 cond 目标」**一律 `merge_bi = blk_i`**，没有 foreach（:11502）/ for（:13622）/ 范围行走（:8500）三处都有的「循环头标签派发」⇒ 内层 `for_cond_5`（块 6）被误当成本 if 的 merge 跟踪，循环本体从未派发。

**取证**（`--dump-zig-path`，非侵入）：N 的 IR 块序为 `entry0 / while_cond_0=1 / while_body_1=2 / while_exit_2=3 / if_then_3=4 / if_merge_4=5 / for_cond_5=6 / for_body_6=7`；`loop_last_be` 经迭代扩展（间接回边判据）推到 7 ⇒ **`loop_end=8`，区间并未截空** ⇒ 「RC-2 的 `blk_i >= loop_end` 截断」假设在 while 侧**被否证**。补上循环头派发后 count 恢复 40，但 `hits` 由 4 变 20，dump 显示臂②的 `if (reg_24) break :__while_0` 落在 `if (reg_9.toBool()) { … }` **内部**（brace depth=2）⇒ 真正的致损条件是「**内层 for 的出口复用本 if 的 `if_merge_` 块**」：范围行走把该 merge 体（后置兄弟语句）内联进 then 臂，臂② 只在本臂条件成立的那一轮执行。

**修复口径（已落地）**：在 while 侧该 `.br` 处理点移植 foreach/for 的派发表 —— ① 目标标签命中 `for_cond_`/`while_cond_`/`foreach_cond_`/`do_while_body_` 即在 then 缩进内派发范围行走 `[blk_i, loop_end)`（非循环头目标保持原 `merge_bi` 行为不变）；② 派发期 `defer_loop_fallthrough=true` 并清空 `last_loop_fallthrough_*`（f124 修复 12 同款臂内联保护）；③ 当 `for_cond_` 的出口正是本 if 的 `if_merge_`（`else_bi` 标签为 `if_merge_` 且其 `cond_br` 单边等于该块）时，改交自包含的 `generateForFromLabels(blk_i, end_idx)` 并 `processed.remove(else_bi)`，把 merge 交还外层 if 流程在正确缩进发射；④ 臂尾按 `last_loop_fallthrough_idx == else_bi` 物化来源边 PHI。**注意与 RC-2 的判据差异**：foreach 侧多一道 `blk_i >= loop_end` 前提（那里截断是真触发条件），while 侧实测该前提**不成立且有害**（会漏掉全部 P/N 形态），故此处只留三条结构判据。

### RC-4（2026-10-01 登记为候选，同日**取证 + 修复落地（①②，未提交）**）

> **行号口径**：本节三行（门控缺陷、修复口径、RC-5 候选）里的 `native_linker.zig` 行号是 **①② 落地后重新 grep 的当前树实测值**（工作区未提交）。本文其余历史条目（RC-1/RC-2/RC-3 各行、§5、§7）引用的仍是 `b21cdfd` 树锚点，折算到当前树需加纯新增插入量：`<934` 不变、`934–11561` +14、`11562–13662` +72、`13663–15264` +111、`≥15265` +145。折算律经 `:8520 → :8534`（范围行走侧注释）与 `:7306 → :7320`（RC-1 判定注释）两点验证；个别当年登记的锚点自带 ±5 误差，**使用前请重新 grep**。

**一句话根因**：`if (…) { <内层循环> break; }` 这种臂尾**无条件** `break`/`continue` 形态，IR 里没有代表它的块 —— 该语句被 IR 生成器折叠进**内层循环出口边**（`for_cond_` 的 `cond_br` 假边直接指向外层循环的 `foreach_cleanup_`/`foreach_increment_`）。而三个循环生成器的臂尾 `.br → 循环头` 派发点，救援判据都只覆盖「内层循环出口复用本 if 的 `if_merge_`」这一子集；本形态的 if **没有 else 块**（else 边就是外层循环自己的延续块），判据不成立 ⇒ 回落到被 `loop_end` 截空的范围行走 ⇒ **内层循环整块静默丢失，连同被折叠在其出口边上的 `break`**。

| 项 | 内容（2026-10-01 实测/取证，非推断） |
|---|---|
| 复现探针 | 永久探针（勿删）：`c005_rc4_break_after_nested_loop_tmp.php`（Y1–Y6 六形）、`c005_rc4_min_y1_tmp.php`（Y1MIN 单形，供 dump 阅读）、`c005_rc4_min_y6_tmp.php`（Y6MIN 单形，RC-5 主形复现体）、**`c005_rc5_merge_loss_tmp.php`（RC-5 八形 F-A…F-H，2026-10-01 新增）**。同族早先证据：`ref003_crash_attr_tmp.php` 的 W1/W2/W3。诊断门：`c005_rc4_probe_run_tmp.sh`（四探针，末行 `RC4_PROBE_DONE`）、**`c005_rc5_probe_run_tmp.sh`（RC-5 八形，末行 `RC5_PROBE_DONE file=…`）**；等值门：`c005_probe_run_tmp.sh` 已把 Y1MIN 纳入（16 ⇒ 17 形）。RC-5 的门**独立成篇、不并入 17 形等值门**，以免追溯性改变 RC-4 已登记的验收记录 |
| IR 块序（Y1MIN，`--dump-ir` 走 stderr） | `func.blocks` 下标（**标签后缀是全局块计数器，不等于下标**）：`entry=0 / foreach_cond_0=1 / foreach_body_1=2 / foreach_increment_2=3 / foreach_cleanup_3=4 / if_then_5=5 / for_cond_7=6 / for_body_8=7`。`foreach_body_1` 尾 `cond_br(reg_16, if_then_5, foreach_increment_2)`；`if_then_5` 内容仅 `nop; global.set $j; br for_cond_7`；`for_cond_7` 假边 = **`foreach_cleanup_3`**（`br reg_20, for_body_8, foreach_cleanup_3`）⇒ 臂内**没有** break 块，也没有 if 的 else 块 |
| 派发点门控缺陷（三处，同一形状；行号为**①② 落地后的当前树**，括号内为 `b21cdfd` 旧号，机械位移 +14 / +72 / +111，源于三处纯新增插入） | ① foreach 侧 :11556–11572（旧 :11542–11558）`for_exit_is_outer_merge_lh`：要求 ①`blk_i >= loop_end` 且 ②`else_bi` 标签以 `if_merge_` 开头；本形 `else_bi = foreach_increment_2` ⇒ ② 落空。② while 侧 :15356–15372（旧 :15245–15261）`for_exit_is_outer_merge_lw`：同样硬要求 `if_merge_` ⇒ 落空。③ for 侧 :13717–13733（旧 :13645–13659）`for_loop_exit_is_outer_merge`：只要求内层 `cond_br` 单边等于 `else_bi`，本形内层出口是外层 **cleanup**、else 边是外层 **increment**，两者不等 ⇒ 亦落空。三处落空后统一走 `generateLabelDrivenBlockRange(blk_i, loop_end)`；而 `loop_end = @min(end_idx, loop_last_be + 1)`（当前 :11266 / for :13459 / while :15131），`loop_last_be` 只扫到外层最后回边 —— **按 :11249–11266 逻辑推得**本形为 3（块 5/6/7 的终止符都不回指 `foreach_cond_0`/`foreach_increment_2`）⇒ `loop_end=4`，而内层 for 块在下标 6/7 ⇒ **起点 ≥ 终点 ⇒ 空区间 ⇒ 零发射零标记**（该推论与「臂内只剩 for 初始化语句」的发射结果自洽） |
| 症状 S1（臂内丢失） | Y1MIN AOT `visited=5 count_x=0` vs PHP `visited=1 count_x=4`；六形 AOT 全部 `visited=5`，`count_x=0`。生成的 `if (reg_16.toBool()) { … }` 臂内只剩内层 for 的初始化语句 `setGlobalVar("$j", reg_3)` |
| 症状 S2（顶层重发 + 尾部回声） | 空区间同时**不置 `processed`** ⇒ 外层块行走随后在循环体外把这些块当兄弟块再发一遍：六形 dump 的 `__main__` 内出现 `__foreach_0 … php_echo(reg_48) / __for_1 … php_echo(reg_48)` —— 尾部 echo 两份，第一份 `count_x=0`、第二份 `count_x=4`（副作用被二次执行）。同现象见 Y1/Y2/Y4/Y5。**两症状同根因**，非两个缺陷 |
| W2 读数更正（**历史误读记录**，② 落地后本行结论已被 §7 行 10 部分推翻） | 原登记「W2 内层 for 已正确发射（`count=205`、`g199=199` 与真值等值）」是**误读**：本轮结构化 dump 显示 W2 的 `__foreach_2` 臂内**没有** `__for_`，内层 for 以顶层兄弟 `__for_3` 形态出现在 foreach 之后，随后才是那一条 tail echo ⇒ `count=205` 来自**二次执行**而非臂内正确发射。对照组 W1（`__for_1` 真在 `__foreach_0` 内、后跟 `break :__foreach_0`）与 W3（`__for_5` 在 `__foreach_4` 内、后跟 `continue :__foreach_4`）均等值 ⇒ 差异只在「if 有独立兄弟块 ⇒ `else_bi` 命中判据」与「if 无 else ⇒ 判据落空」之间，与门控分析完全吻合 |
| 修复口径（**已落地**，两步缺一不可） | **(i) 派发门控放宽** —— 三处 `.br → 循环头` 站点各加一条「区间将被截空」的放宽分支：`blk_i >= loop_end` 且目标是任意循环头（新增共用语义判据 `loopHeadKind` :937–946，口径取自公共处理器 :7535–7539 的 `ah_is_*`）且目标不是本层自身的控制边且头块未 processed ⇒ 按前缀交自包含 `generateForeachFromLabels` / `generateForFromLabels` / `generateWhileFromLabels`（终点用外层 `end_idx`），派发后补记循环头的 `processed` 标记，并把被内层乱序回落分支卸载的**本层控制块**（increment/cleanup/exit）标记恢复；`processed.remove(else_bi)` 仍**严格限定 `if_merge_`** 的既有分支（RC-2 原路径逐字未动，探针 H 教训）。站点：foreach :11576–11633、for :13735–13773、while :15376–15409（均为 ①② 落地后的当前树行号）。**(ii) 出口边语义** —— 内层循环出口边落在外层 cleanup/exit（foreach）、exit（for）、exit（while）时，按 `last_loop_fallthrough_src_idx` 消解该边 PHI 并发 `break :<本层标签>` + 置 `break_generated`；落在外层回边（increment/cond/loop，即裸 `continue`）时**不发语句**，靠直落到本层增量（foreach 若在臂发 `continue` 会跳过 `iter_next`，与 generic `.br` 回边处理同口径）。`break_generated` 的抑制边界复用 :12389–12392 的「双臂 AND」既有机制：本形 else 边是回边、不参与 AND ⇒ 尾部的增量与 `continue` 照常发射（CODEGEN-003 修复 4 的同款约束）。**实测落地成本**：`git diff --stat` 纯新增 **+145/−0 行**、四段 hunk（共用判据 +14 @`:934`、foreach +58、for +39、while +34），未删除任何既有行，RC-2/RC-3 的三条既有救援分支逐字未动 |
| 分步落地实测（2026-10-01，同一棵树先后两次构建） | **仅 ①**：Y1MIN AOT `visited=5 count_x=4`（真值 `visited=1 count_x=4`）⇒ S1 复原、S2 回声消失（六形每行只出现一次），但 `visited` 仍为 5 —— **这是 ① 单独落地的预期中间态，不是回归**；16 探针门 `same=16/16 differs=0` ⇒ ① 零回归。**①+②**：Y1MIN **逐字节等值**；六形 Y1–Y5 全部等值（`visited=1`、`key=k0`、`tail=none`）；`ref003_crash_attr` W1 ✓ 且 **W2 首次逐字节等值**（`visited=1 count=205 g199=199`）。`zig build test` 21/21 步骤、326/326 用例、exit=0。崩溃面三点序列：`b21cdfd` W2 不崩（内层 for 被丢到循环外 ⇒ 迭代期根本没增长）→ ① W2 崩（增长真的进了迭代期，stdout 只剩 W1）→ ①+② W2 不崩且等值、W3 仍崩（`break` 使迭代器不再推进）⇒ **反证崩溃点在「搬迁后的下一次 `next()` 推进」，不在槽读取**，见 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) §3/§5 |
| **RC-5（2026-10-01 由 ② 的验收实测暴露 ⇒ 同日追踪取证到行，一行代码未改）** | **主形**：臂尾裸 `continue` 且 if **有**真实延续块（`if_merge_` 承载后置兄弟语句，或显式 `else` 臂）时，兄弟语句在任一路径都不发射（`c005_rc4_min_y6_tmp.php` 实测 PHP `hit=3` vs AOT `hit=0`）。**机制（追踪实证，非推断）**：走线性派发（`blk_i < loop_end` ⇒ ①/RC-2 门控根本不触发）⇒ 臂尾内联发射外层 latch + `continue :__foreach_0` 置 `break_generated=1` ⇒ 控制回到公共范围行走时起点被回退到 latch 之后、**落在延续块之前**，于是 `generateLabelDrivenBlockRange` 的「return/break 已生成 ⇒ 剩余块整段标记 `processed` 并返回」（**:7206–7211**）把 merge/else 块一并吞进 `processed` ⇒ 下游 coalesce 延后发射（:12339–12349）与 else 臂发射（普通路径 :12037–12039，判据 `!processed.contains(ei)`）双双落空。**原候选归属已否证**：显式 `else` 形根本没有 `if_merge_` 块、`else_is_coalesce=0`，仍以同一 mark-rest 扫描丢失 ⇒ 不是 coalesce 判据过宽，而是扫描越界吞块。八形实测表与逐行追踪读数见 **§RC-5 取证细则**；修复口径见 §修复方案的三行（**P0 方案 A** 窄口径 / **P2 方案 B** 可达性根治 / **P1 facet-2** 另立取证）；**未经裁决不改**（§7 行 9） |
| 同根派生的兜底 | 空区间「零发射零标记」是静默失效族（与 #18 金丝雀同源）。建议配套加一条发射期断言：`.br → 循环头` 派发后若目标块仍未落进 `processed` ⇒ 打 `[AOT-CANARY]`。是否与修复同批，待一并裁决 |
| 是否阻塞 | **已解除对本工单的阻塞**：② 落地后 W2 首次逐字节等值，[AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) 的 F4b/F5 复测不再被本缺陷污染，且 W2 反转为「迭代器推进前 break ⇒ 不崩」的正向对照。**仍阻塞的是 REF-003 自身**：W3（增长后 `continue`，迭代器继续推进）仍 `rc=139`，属运行时模板的 P0 段错误，需 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) §10 行 1 的裁决后才动 `runtime_lib_template.zig` |

### RC-5 取证细则（2026-10-01 八形实测 + 临时打印追踪，trace 已剥离）

**探针**：`fuzzy_scripts_720/tmp/c005_rc5_merge_loss_tmp.php`（**永久，勿删**，八形 F-A…F-H 一次编译）；**诊断门**：`fuzzy_scripts_720/tmp/c005_rc5_probe_run_tmp.sh`（末行 `RC5_PROBE_DONE`）。该门独立于 RC-4 诊断门与 17 形等值门，避免追溯性改变已登记的验收记录。

**八形实测（2026-10-01，同一还原后的二进制，`--compile` 于项目根、真值 `/opt/homebrew/bin/php` 8.5.8）**：

| 形 | 形状（相对 Y6MIN 的变量） | PHP 真值 | AOT 实测 | 判定 |
|---|---|---|---|---|
| F-A | 臂尾 `continue`，if 后**无**兄弟语句（无 `if_merge_`，else 边即 `foreach_increment_`） | `visited=4 hit=0 count_x=4` | 同 | ✅ 等值（**正对照**，RC-4 已闭环子形） |
| F-C | 有兄弟语句 `if_merge_`，臂尾**无**裸 `continue` | `visited=4 hit=4 count_x=4` | 同 | ✅ 等值（**正对照** ⇒ 裸折边是必要条件） |
| F-B | 臂尾 `continue` + 兄弟语句 `$hit++`（= Y6MIN 主形） | `visited=4 hit=2 count_x=4` | `hit=0` | ❌ **facet-1**（延续块丢失） |
| F-D | 同 F-B，兄弟语句写成**显式 `else` 臂**（IR 无 `if_merge_`，else=`if_else_`） | `visited=4 hit=2 count_x=4` | `hit=0` | ❌ **facet-1** ⇒ **否证**「仅 `else_is_coalesce` 判据过宽」 |
| F-E | 同 F-B，兄弟语句换成副作用 `echo` | `E3 E4` + `count_x=4` | 回声缺失、仅 `count_x=4` | ❌ **facet-1** ⇒ 排除「只丢 PHI 目标变量」的解释 |
| F-F | 同 F-B，内层循环换成 `while` | `visited=4 hit=2 count_x=4` | `hit=4` | ❌ **facet-2**（**反向**：`continue` 未翻译，then 路径直落延续块 ⇒ 过执行） |
| F-G | 臂尾换成 `break` + 兄弟语句 | `visited=1 hit=0 count_x=2` | 同 | ✅ 等值（①/② 已覆盖 break 形） |
| F-H | 同 F-B，外层换成 `for` | `hit=1 count_x=6` | `hit=3` | ❌ **facet-2**（for 侧同族） |

**追踪读数（临时 `std.debug.print`，站点：foreach-if 的 `loop_end`/then/else 索引、臂尾 `.br` 目标、三条派发路径标记、`merge_bi` 兜底、`else_is_coalesce`、coalesce merge 延后发射、`generateLabelDrivenBlockRange` 的「剩余块整段标记」分支；取证后全部剥离）**

F-B（`foreach_body_23`，then=`if_then_27`(19)，else/merge=`if_merge_28`(20)，内层 for 头 `for_cond_29`(21)，increment=17，cleanup=18）：

```text
[RC5T1] foreach-if body=foreach_body_23(16) loop_end=23 end_idx=62 then=19 else=20 pT=0 pE=0
[RC5T2] then=19 br->for_cond_29(21) loop_end=23 inc=17 clean=18 pTgt=0
[RC5T3c] path=linear blk=21 loop_end=23
[RC5T7] mark-rest-processed i=18 end=23 rg=0 brk=1 start=21
[RC5T3d] after-dispatch else=20 pElse=1 rg=0 brk=1 lft=17
[RC5T4] merge_bi=20 else_bi=20 rg=0 then_is_be=0 pMerge=1 pElse=1
[RC5T5] coalesce=1 else_is_be=0 then_is_be=0
```

逐条结论：`blk_i=21 < loop_end=23` ⇒ **RC-2 与 ① 的截空门控都不触发**，走既有线性派发（`path=linear`，:11634–11636）⇒ 内层 for 与 `count_x` 正确；臂尾内联发射外层 latch（`foreach_increment_17`）+ `continue :__foreach_0` 置 `brk=1`，且行走起点被回退到 **18**（latch 之后、延续块 20 之前）⇒ `[RC5T7]` 的 `mark-rest-processed i=18 end=23` 把 18/19/20/21/22 **整段标记 `processed`** ⇒ `[RC5T3d] pElse=1`、`[RC5T4] pMerge=1` ⇒ :12339–12349 的 `if (!processed.contains(mi))` 不成立 ⇒ merge 体（`$hit++`）在任一路径都不发射。

F-D（显式 else，else=`if_else_39`(28)）同一扫描 `[RC5T7] mark-rest-processed i=26 end=31 brk=1 start=29` ⇒ `pElse=1` ⇒ :12037–12039 的 else 臂连 `} else {` 都不发 ⇒ **归属改判**：缺陷在 mark-rest 扫描的吞块范围，不在 coalesce 判据。

F-A 也触发同一扫描（`i=4 end=8 brk=1`），但该形延续块就是 increment(3)，**在被吞区间之前** ⇒ 零丢失 ⇒ 解释等值门（17 形）为何从未抓到本缺陷。F-C 走 `[RC5T3a] path=rc2_outer_merge` ⇒ `pElse=0` ⇒ 正常；RC-2 的 `_ = processed.remove(ei_lh)`（:11575）正是同一吞块行为的**既有局部解法**，方案 A 即把它推广。

F-F **无** `[RC5T7]` 命中、`pElse=0`、`brk=0`、`lft=null` ⇒ 臂尾 `continue` 根本没进入出口边翻译机制（facet-2 独立于 facet-1，不能靠同一修法关闭）。

**取证成本与还原（实测）**：`zig build` 61.85s（插入 7 处 trace）→ 取证 → 由 `/tmp` 备份整份还原（`md5 9dff465ff6276ceb03c971e1212ca835`，`git diff --stat` 回到 +145/−0）→ `zig build` 61.53s → 等值门复跑 `PROBE_DONE total=17 same=17 differs=0` 且 stderr 无 `RC5T` 残留 ⇒ **RC-4 落地态未受取证污染**。

### 修复方案（P0/P1/P2 · 影响面 · 落地成本）

| 优先级 | 方案 | 影响面 | 落地成本 |
|---|---|---|---|
| **P0** | **RC-1 收口（已落地）**：新增成对谓词 `isLoopContinueTarget`（:924，块自身即本循环条件块、或以 `br` 落回条件块 ⇒ 认定为本层回边/continue），并在 `if_merge_`+`cond_br` 处理器（:7306）的 then/else 派发**之前**判定「两条边分别落在本循环的 break 目标（cleanup/exit）与 continue 回边上」，命中则就地发 `if (cond) { <exit PHI>; break :current_loop_label; }`（break 边在 else 侧时条件取反），假边侧不置 `break_generated`（否则尾部增量与 `continue` 被抑制），末以 `i += 1; continue;` 交回范围行走 | 单一处理器，且该处理器在**公共**范围行走内 ⇒ foreach / while / for 体内同形态一并收敛 | 实测 +63/−6 行（判据全部复用 `isLoopBreakTarget` :901 与 `generateExitPHIAssignments`，无新抽象） |
| **P0** | **RC-2 收口（已落地，口径修订）**：原设想「派发终点越界时回退外层 `end_idx`」被 grep 否证 —— for 侧**已有同形且已实证**的修法：`for_loop_exit_is_outer_merge`（:13638，内层 for 的 exit 复用外层 if 的 merge ⇒ 交自包含 `generateForFromLabels(blk_i, end_idx)` + 卸载被预标记的共享 merge）。范围行走侧 :8520 的注释「for/foreach 的 exit 复用外层 merge 场景暂不在此处理」正是本缺口登记处。故把该分支镜像到 foreach 侧 then 臂尾派发点（:11528），并加两道严格前提：① `blk_i >= loop_end`（仅救援【区间已被截空】的形态，正常布局零影响）；② 延续块标签必须是 `if_merge_` —— 探针 H 的 `else_bi` 是 `foreach_increment_` 且内层 for 的 exit 同样落在其上，缺此排除会把 increment 误卸载标记 ⇒ 增量重复发射 | 改动臂内嵌循环的派发终点，但被两道前提约束在乱序截断形态内 | 实测 +37/−1 行 |
| P1 | 金丝雀扩展：在 `if_merge_`+`cond_br` 处理器里，若双臂目标均已被 processed 且本次未发出任何 `break/continue/return` ⇒ 发射期 `[AOT-CANARY]` 报警（把本形态纳入 #18 闸门，防同类静默回归）。**注**：RC-1 已让该形态真发 break，金丝雀是「万一判据不成立时不再静默」的兜底，仍待裁决 | 1 处判据 | 低（≈8 行） |
| P1 | 语料检测力：把 F/J 形状（体内「前置无 else if + 后置单语句 if-break」+ 臂内嵌循环）补进 `fuzzy_scripts_720` 生成模板 | 测试资产；需重冻结一次基线 | 低 |
| **P0** | **RC-4 收口（已落地，2026-10-01，见 §4 RC-4 三行）**：两步缺一不可 —— **(i)** 三处臂尾 `.br → 循环头` 派发点各补一条「区间将被截空」救援分支（foreach :11576–11633 / for :13735–13773 / while :15376–15409）：`blk_i >= loop_end` 且目标命中任意循环头（新增共用谓词 `loopHeadKind` :937–946，取代三处各写一遍的前缀串，符合 DRY）⇒ 按类别交自包含 `generate*FromLabels(blk_i, end_idx)`，派发后补记循环头 `processed` 并恢复被内层乱序回落卸载的**本层**控制块标记；`processed.remove(else_bi)` 仍严格限定 `if_merge_`（探针 H 教训）。**(ii)** 出口边语义：内层出口落在外层 cleanup/exit ⇒ 消解该边 PHI + `break :<本层标签>` + 置 `break_generated`；落在外层回边（裸 `continue`）⇒ 不发语句，靠直落本层增量；`break_generated` 抑制边界复用 :12389–12392 的「双臂 AND」既有机制，守 CODEGEN-003 修复 4 的约束 | 三处派发点 + 出口边语义；触到 break/continue 语义而非仅派发终点，风险高于 RC-1；但四段 hunk 全部为**新增分支**、既有救援路径逐字未动 ⇒ 正常布局（未截空）零路径改变 | 实测 **+145/−0 行**（+14 共用谓词 / +58 foreach / +39 for / +34 while）；`timeout 240 zig build` 通过、`zig build test` 326/326、① 单独态 16 探针门 `same=16/16` |
| **P0（待裁决）** | **RC-5 facet-1 方案 A（窄口径·推荐）**：臂尾线性派发返回后，若本 if 的**延续块**索引（`merge_bi`/`else_bi`）被 `generateLabelDrivenBlockRange` 的 mark-rest 扫描（:7206–7211）连带标记，则卸载标记交还既有共享发射 —— 即把 RC-2 已在用的 `_ = processed.remove(ei_lh)`（:11575，当时严格限定 `if_merge_` 且仅在截空区间）推广到「线性派发 + 任意延续块（`if_merge_` 或显式 `else`）」，站点仍是三处派发点之后的公共位置（foreach :11637 起）。卸载前须校验该块**真可达**（其 `phi`/指令尚未在任何路径发射），否则会退回 `tryGenerateFromLabels` 的未处理块告警 | 只触臂尾折边 + 有延续块的 if；F-B/F-D/F-E 三形转绿，F-A/F-C/F-G 正对照不变；facet-2 不受影响 | **未落地，不报价**（预计小，单点卸载 + 一处判据）；探针与诊断门已就位，复测成本 ≈1 分钟 |
| P2 | **RC-5 facet-1 方案 B（根治）**：mark-rest 扫描不再「整段标记到 `end_idx`」，改为按 CFG 反向可达性只标记真正不可达块 | 触及所有循环/if 的收尾语义（该扫描是公共出口），回归面 = 68 回归 + 基线漂移 + 巡检全套 | 高；**必须单独成批**，禁止与功能修复混提，未报价 |
| P1 | **RC-5 facet-2（待裁决，另立取证）**：F-F（while 内层）与 F-H（for 外层）的臂尾裸 `continue` **未进入**出口边翻译机制（trace 无 `[RC5T7]` 命中、`brk=0`、`lft=null`）⇒ `continue` 丢失、then 路径过执行延续块（`hit` 反而变大）。与 facet-1 无耦合，同一修法关不掉；需先在 while/for 侧定位「为何 `last_loop_fallthrough_idx` 为空」 | while/for 两侧臂尾语义 | 取证 ≈0（F-F/F-H 已在永久探针内），修复**未报价** |
| P2 | **DRY 收口**：把三处形近的 ① 分支抽成一个共用例程（参数化「本层控制块集合 + break 边判据 + defer 保存点」，骨架共享：截空判定 → `loopHeadKind` 派发 → 补记循环头 `processed` → 恢复本层标记 → 出口边语义），消除 +58/+39/+34 行的三写重复（详见 §6 末条） | 横跨 foreach/for/while 三个生成器的签名改造；语义不变 ⇒ 判据仍是「等值门 + 诊断门 + 全门」三轮不变 | 中（≈ −60/+40 行净收敛）；**必须单独成批、单独过 §5 全门**，禁止与功能修复混提 |
| P2 | 同族形状扫描（**已实测收敛，2026-09-30**）：`c005_k_seq_if_for_tmp`（CODEGEN-002 原文复现，`K x=c`）、`c005_l_while_sibling_break_tmp`（while 侧同形，`L hits=4 mark=7`）、`c005_m_for_sibling_break_tmp`（for 侧同形，`M hits=4 seen=0`）、`c005_n_while_nested_for_break_tmp`（while + 臂内嵌 for，`N hits=4 count=40`）、`c005_o_for_nested_for_break_tmp`（for + 臂内嵌 for，`O hits=4 count=40`）、`c005_p_while_nested_foreach_tmp`（while + 臂内嵌 foreach，`P hits=4 count=4`）、`c005_q_while_nested_while_tmp`（while + 臂内嵌 while，`Q hits=4 count=40`）、`c005_r_while_else_nested_for_tmp`（while 的 **else** 臂内嵌 for，`R hits=4 count=11`）、`c005_s_dowhile_nested_for_tmp`（do-while + 臂内嵌 for，`S hits=4 count=40`）。**结论**：RC-1 在公共处理器 ⇒ for/while/foreach 三侧同步收敛（K/L/M 实测印证）；N/O 分化出 RC-3（while 侧缺循环头派发、for 侧本已有）；S 无需新增代码 —— do-while 生成器把 body 交回 `generateLabelDrivenBlockRange(..., body_idx + 1, cond_idx, ...)`（:17155），循环头派发表本已生效。九探针 AOT 输出与 `/opt/homebrew/bin/php` **逐字节等值**，同族扫描关闭（**关闭范围限当时覆盖的形状**；2026-10-01 新登记的 RC-4「同臂内、内层循环之后的 break」不在其中，见上表 RC-4 行） | 潜在同族 | 实测 9 探针（≈3 分钟），零新增代码 |

## 5. 验收门（修复时）

1. **17 探针等值门**：`fuzzy_scripts_720/tmp/c005_probe_run_tmp.sh` 全绿 —— A,B,F,G,H,I,J,K,L,M,N,O,P,Q,R,S + **Y1MIN**（RC-4 复现单形，2026-10-01 纳入）全部与 `/opt/homebrew/bin/php` 逐字节等值（含函数上下文 J、RC-3 新增的 P/Q/R、do-while 侧同族 S），验收判据为脚本末行 `PROBE_DONE total=17 same=17 differs=0`（2026-10-01 RC-5 取证的临时 trace 剥离并重建后**复跑仍为 17/17**，stderr 无 `RC5T` 残留）；
1b. **RC-4 诊断门**（非等值门，专盯本轮四探针）：`fuzzy_scripts_720/tmp/c005_rc4_probe_run_tmp.sh` ⇒ 判据是 **Y1MIN 等值 + 六形文件仅在 Y6 行差异 + `ref003_crash_attr` 仅崩在 W3**；剩余红点必须逐行归到 RC-5（`hit=0`）与 REF-003（`rc=139`）两个已登记缺陷上，出现任何其他差异即视为 RC-4 未收口；
1c. **RC-5 诊断门**（非等值门，八形）：`fuzzy_scripts_720/tmp/c005_rc5_probe_run_tmp.sh` ⇒ 判据（2026-10-01 实测登记）：**F-A / F-C / F-G 三形必须等值**（正对照），**F-B / F-D / F-E 为 facet-1 已知红点**（延续块丢失 ⇒ `hit` 少算），**F-F / F-H 为 facet-2 已知红点**（臂尾 `continue` 未翻译 ⇒ `hit` 多算）；出现清单外的差异即视为有新缺陷；
2. 官方回归 `scripts/regression_test_720.sh`：68 项，FAIL_COMPILE=0 / FAIL_RUNTIME=0 / **FAIL_DIFF=0**（f004 SKIP 允许）；
3. **发射侧改动 ⇒ 冻结基线 `fuzzy_scripts_720/baseline_main_zig_md5.tsv` 必须逐字节复验**：语料未覆盖该形状 ⇒ 理想为 **0 个语料脚本漂移**；若出现漂移，须逐脚本解释后才允许走重冻结；
4. `timeout 120 zig build` + `timeout 120 zig build test`（发射侧改动必须跑单测，与纯模板改动不同）；
5. 确定性巡检 `f12_determinism_tmp.sh`：`SWEEP_DONE total=68 mismatch=0 notemp=0`；
6. 冻结基线抽查 `s7_baseline_spotcheck_tmp.sh`：`SPOT_DONE ok=5 bad=0`；
7. 复测前 `ps -A -o pid,ppid,etime,command | grep -E "zig build-exe|php-interpreter"` 排查 PPID=1 孤儿；批次期间禁止编辑 `runtime_lib_template.zig`、禁止 `zig build`、禁止并发编译。

## 6. 风险

- **影响面未知但性质恶劣**：静默丢语句意味着任何使用「foreach 体内多个无 else 短 if」写法的业务脚本都可能已经算错而无人察觉。语料 68 脚本 0 FAIL_DIFF 只说明**没踩到**，不说明不存在。
- RC-1 的修复位于**公共**范围行走处理器，覆盖面广 ⇒ 必须警惕「break 边判定过宽」把正常的 merge 延续误吞成本循环 break（表现为循环提前退出）。**已落地的缓解**：判据为「一边 `isLoopBreakTarget`（:901，精确匹配 `current_loop_cleanup_block`/`current_loop_exit_block` 索引）+ 另一边 `isLoopContinueTarget`（:924，本层条件块或其 `br` 回边）且两侧互斥」，全程不用标签前缀猜测；实测 A/B/H/I 四探针逐字节不变 ⇒ 正常形态未被吞。
- RC-2 的修复触及臂内嵌循环的派发终点 ⇒ 是两者中风险更高的一步。**已落地的缓解**：不改 `loop_last_be`/`loop_end` 主定义，而是镜像 for 侧已实证的 `for_loop_exit_is_outer_merge` 分支，并加「`blk_i >= loop_end`（只在区间被截空时救援）+ 延续块必须是 `if_merge_`（排除探针 H 的 increment 目标）」两道前提，把触发面约束在乱序截断形态内。
- 两条根因**互相独立** ⇒ 已按「先 RC-1 过全门、再 RC-2」两步执行，避免一次改动两条不变量导致回归失败难以归因（RC-1 单独过门时 F/G/J 呈 `hits=4 count=20` 的**中间态**属预期，不是回归）。
- **归因折中（须披露）**：本次按「①→②」两步走，但**只有 ① 单独过了独立的一轮**（16 探针门 `same=16/16`，⇒ ① 零回归）；68 回归 / 基线漂移 / 确定性巡检 **只在 ①+② 合并态跑了一轮**，理由是 ① 单独态留有已知错误的 `visited=5`，以其为基线跑全门无意义。代价：若合并态全门出现红点，无法直接归到某一步 ⇒ 预案已定 —— ② 的三处改动小而局部（各一个 `if (lft_is_break_*)` 块），注释掉三处后重编重跑即可二分定位。
- **三处 ① 分支形近而词表不同**（foreach :11576–11633 / for :13735–13773 / while :15376–15409，+58/+39/+34 行）：骨架（截空判定 → 按 `loopHeadKind` 派发 → 补记循环头 `processed` → 恢复本层控制块标记 → 出口边语义）完全一致，差异只在外层循环的控制块词汇（`cleanup_idx`/`increment_idx`/`exit_idx` vs `exit_idx`/`loop_idx`/`cond_idx`）与 `defer_loop_fallthrough` 的保存点。**DRY 上应当抽成一个共用例程**（把控制块集合参数化），但那是横跨三个生成器的签名改造，风险高于本轮收益 ⇒ 记为 P2，**必须单独成批、单独过门**，不得顺手夹带。

## 7. 裁决状态

| # | 事项 | 状态 |
|---|---|---|
| 1 | 按「**RC-1 先行、RC-2 随后**」两步推进修复（每步独立过 §5 全门） | ✅ 已授权（用户「继续推进已知问题」），两步代码均已落地。**计划外扩展**：同族扫描（N/O 分化）暴露第三条根因 RC-3（while 侧缺循环头派发），一并收口；三条根因合并进单次提交 `b21cdfd`（仅 `src/aot/native_linker.zig` + `src/aot/runtime_lib_template.zig`） |
| 2 | RC-2 实现口径（派发终点回退 `end_idx` / `loop_end` 改前向可达闭包） | ✅ 已由 grep 收敛为第三方案：移植 for 侧既有实证分支 + 两道严格前提（口径修订理由见 §4） |
| 3 | P1 金丝雀扩展 + 把 F/J 形状纳入语料生成模板（代价：基线需重冻结一次） | ⏳ **仍待裁决** |
| 4 | 同族形状（while/for 体内同款）探针扫描（§4 表末 P2） | ✅ **已实测关闭**：K/L/M/N/O/P/Q/R/S 九探针 AOT 输出与 PHP 真值逐字节等值，其中 N/P/Q/R 为 RC-3 的复现与验收形态，for/while 侧无需再补代码 |
| 5 | RC-1/RC-2 的发射侧改动是否接受「先证明语料零漂移再重冻结」路径 | ✅ **已闭环**：全量漂移 `total=68 ok=68 diff=0 notemp=0 norow=0` + 巡检 `mismatch=0` + 抽查 `ok=5 bad=0` ⇒ 语料零漂移，**未重冻结基线**（`baseline_main_zig_md5.tsv` 保持原状） |
| 6 | 文档自证更正 | ✅ RC-3 取证期间曾把探针 R 的 PHP 真值记为 `count=21`（推测值），实测为 **`R hits=4 count=11`**，已在 §4 与 P2 行更正；R-1b 判据缺口另记于 [AOT-REF-002](AOT-REF-002-iter-ref-slot-dangling.md) |
| 7 | **RC-4 是否按已定口径落地**（同臂内、内层循环之后的裸 `break`/`continue` 未发射。**2026-10-01 取证完成**：臂尾 break 被 IR 折叠进内层循环的出口边 ⇒ 三处派发点的救援判据（只覆盖「内层出口复用本 if 的 `if_merge_`」）落空 ⇒ `loop_end` 截空区间 ⇒ 零发射零标记 ⇒ 内层循环整块丢失并在循环外被重发（尾部回声）。Y1–Y6 六形 + W1/W2/W3 对照均已结构化实证） | ✅ **已按 ①→② 两步落地（2026-10-01，未提交，纯新增 +145/−0 行）**：授权口径为「保存 zig 文件，继续推进已知问题」+ 本工单先前给出的「你点头我就按 ①→② 分两次过全门」。**已实测**：① 单独态 16 探针门 `same=16/16 differs=0`（⇒ ① 零回归）、①+② 态 Y1MIN 与六形 Y1–Y5、`ref003_crash_attr` W1/W2 逐字节等值、`zig build test` 326/326（细节见 §4「分步落地实测」）。**§5 全门已闭环（2026-10-01 实测）**：① 等值门 `PROBE_DONE total=17 same=17 differs=0`；② RC-4 诊断门 `RC4_PROBE_DONE total=4 same=1 differs=3`（唯一等值项 Y1MIN；三个红点逐行归到已登记缺陷：六形仅 Y6 行 `hit=0` ⇒ RC-5；`ref003_crash_attr` `rc=139` 崩在 W3 ⇒ REF-003）；③ 官方 68 回归 `TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1`（f004 `PHP_error_exit=255`），`regression_failures.tsv` 仅 1 行；④ 基线漂移 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`；⑤ 确定性巡检 `SWEEP_DONE total=68 mismatch=0 notemp=0`；⑥ 冻结基线抽查 `SPOT_DONE ok=5 bad=0`（f067 `47364`/`ad2f742d…`、f113 `104334`/`dab7d3a6…`）⇒ **语料零漂移，未重冻结基线**。REF-003 的 F4b/F5 前置阻塞已随之解除（见行 9 与 REF-003 §6/§10） |
| 8 | 文档自证更正（续行 6） | ✅ 本轮取证**推翻**了 2026-10-01 早前登记的「W2 内层 for 已正确发射（`count=205`、`g199=199` 与真值等值）」：结构化 dump 显示 W2 的 `__foreach_2` 臂内并无 `__for_`，内层 for 以顶层兄弟块出现，`count=205` 来自循环外的**二次执行**。已在 §4「W2 读数更正」与 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) §5 同步更正 |
| 9 | **RC-5 是否落地**（臂尾裸 `continue` 且 if **有**真实延续块 ⇒ 后置兄弟语句在任一路径都不发射。Y6MIN 实测 PHP `hit=3` vs AOT `hit=0`）。**2026-10-01 追踪取证到行**：机制是公共范围行走的「`return`/`break` 已生成 ⇒ 剩余块整段标记 `processed` 并返回」（`generateLabelDrivenBlockRange` :7206–7211）在臂尾内联发射外层 latch 后回退起点到延续块之前，把 `if_merge_`/显式 `else` 块一并吞进 `processed` ⇒ 下游 :12339–12349 与 :12037–12039 的 `!processed.contains(...)` 判据双双落空 | ⏳ **待裁决**：**取证到位、一行代码未改**。四点须知：① 该读数在 `b21cdfd`（①/② 之前）即已如此 ⇒ 非本轮引入的回归，是**先于本工单存在**的缺陷；② **原候选归属已否证** —— 显式 `else` 形（F-D）没有 `if_merge_` 块、`else_is_coalesce=0`，仍以同一扫描丢失 ⇒ 不是 coalesce 判据过宽（见行 11）；③ 八形实测**裂成两个 facet**：facet-1（F-B/F-D/F-E，延续块丢失）与 facet-2（F-F while / F-H for，臂尾 `continue` 未翻译 ⇒ 过执行），**互不耦合、同一修法关不掉**，正对照 F-A/F-C/F-G 均等值；④ 与 REF-003 的 P0（迭代器推进崩溃）**无耦合**，可独立裁决。修法见 §修复方案三行（**P0 方案 A** 窄口径推广 RC-2 的 `processed.remove` / **P2 方案 B** 可达性根治 / **P1 facet-2** 另立取证）。未经裁决不动 `native_linker.zig` |
| 10 | 文档自证更正（续行 8，本轮第二次） | ✅ 两处：① 行 8 的更正本身在 ② 落地后**部分失效** —— W2 现在真的等值（`visited=1 count=205 g199=199`），`count=205` 的来源从「二次执行」回到「臂内正确发射」，故 §4「W2 读数更正」行保留为**历史误读记录**并加注；② **①单独落地态的 `visited=5` 不是回归** —— ① 只把内层循环请回臂内（`count_x` 复原、S2 回声消失），臂尾 `break` 的语义要靠 ② 才发；该中间态若被误判为「修复失败」会导致回滚 ①，故显式登记。顺带得到 REF-003 的三点崩溃序列（`b21cdfd` 不崩 → ① 崩 → ①+② 等值且不崩、W3 仍崩），把 P0 崩溃点定位到「搬迁后的下一次 `next()` 推进」 |
| 11 | 文档自证更正（续行 10，本轮第三次） | ✅ **否证自己的候选归属**：2026-10-01 早先把 RC-5 登记为「`else_is_coalesce`（定义 :11723）成立条件过宽」，本轮八形探针 + 追踪实证显示 F-D（显式 `else`，`coalesce=0`）同样丢失，且丢失发生在 coalesce 判据**之前**的 mark-rest 扫描 ⇒ 该行已按实测改写为「扫描越界吞块」，原推断保留为**已否证的候选记录**。同时新增永久探针 `c005_rc5_merge_loss_tmp.php` 与独立诊断门 `c005_rc5_probe_run_tmp.sh`（不并入 17 形等值门，以免追溯性改变 RC-4 的验收记录） |
