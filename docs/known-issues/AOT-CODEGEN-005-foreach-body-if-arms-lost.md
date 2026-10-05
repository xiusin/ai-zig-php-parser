# foreach 体内静默丢语句：后置单语句 `if-break` 整臂丢失 + 前置 `if` 臂内嵌套 `for` 塌缩为仅初始化

**问题 ID**: AOT-CODEGEN-005
**优先级**: P0（**静默语句丢失**：编译成功、运行成功、退出码 0，仅输出与 PHP 不一致，且语料 68 脚本未覆盖该形状）
**状态**: **CLOSED（2026-09-30，RC-1 / RC-2 / RC-3 落地并通过 §5 全门）— 提交 `b21cdfd`；RC-4（①+②）2026-10-01 实测通过 §5 全门六项（见 §7 行 7），2026-10-03 经用户授权提交为 `0ff09cf`；RC-5 经用户裁决走方案 B（mark-rest 扫描改按 CFG 可达性只标记真正不可达块），2026-10-03 以 **+56/−5 落地在工作区（尚未提交；其中 +2/−2 为纯注释修订，实测发射中性）**⇒ **facet-1 关闭**（Y6MIN 与 F-B/F-D/F-E 逐字节等值）、**facet-2 已于 2026-10-04 经用户裁决走「方案 R：一条机制覆盖 F-F/F-H」并落地（工作区未提交；先全量影子实测再按实测口径实现）⇒ facet-2 净增 +72/−18、相对 HEAD 累计 +128/−23，blob `3ae7b34e`，32546 行**；**F-F / F-H 转逐字节等值，RC-5 八形合串整份输出 IDENTICAL**，§5 七门已在该二进制上串行复测全绿 ⇒ **RC-5 两 facet 均关闭（仍未提交）**，落地记录与影子读数见 **§4「facet-2 落地记录」/ §7 行 15**）；**§5 全门已于 2026-10-03 在 v2 二进制上串行复测完毕、七门全绿**（17 形等值 `same=17/17`、RC-4 诊断门 `same=3 differs=1` 唯一红点归 REF-003、官方 68 回归 `67 PASS + 1 SKIP`、漂移 `diff=0`、巡检 `mismatch=0`、抽查 `ok=5 bad=0`、`zig build test` `21/21 步骤 / 326/326 用例` RC=0 ⇒ **语料零漂移，未重冻结基线**），逐门读数与实现记录见 **§7 行 12（facet-1）/ 行 15（facet-2）**）**
- **RC-1**（后置单语句 `if-break` 臂丢失）：`isLoopContinueTarget` 成对谓词 + `if_merge_`+`cond_br` 处理器就地发 break。实测锚点（2026-10-03，当前树 32492 行）：成对谓词 `isLoopBreakTarget` :901、`isLoopContinueTarget` :924（其口径文档注释 :920–:923）；处理器侧「目标块索引查找提前」注释 :7302–:7318 + 双边判定 :7320–:7334（`brk_on_then`/`brk_on_else` :7328–:7333，命中块起于 :7334）。**原登记 `:924 / :7306`** —— `:924` 至今有效，`:7306` 现为块索引查找循环，判定实起于 :7320。
- **RC-2**（foreach 侧臂内嵌 `for` 塌缩）：移植 for 侧 `for_loop_exit_is_outer_merge` 到 foreach 派发点，带 `blk_i >= loop_end` + `if_merge_` 两道前提。实测锚点（2026-10-03）：RC-2 注释 :11542、判据 `for_exit_is_outer_merge_lh` :11556–:11572、`processed.remove(ei_lh)` :11575、其后的口径放宽注释 :11583。**原登记 `:11528`**（`b21cdfd` 代次，现漂移 +14）。
- **RC-3**（while 侧臂内嵌 `for/foreach/while` 整块丢失，新）：`generateWhileFromLabels` 的 body-if then 臂尾 `.br` **原本没有任何循环头派发**（非 exit/非 cond 一律 `merge_bi = blk_i`，实测该赋值仍在 :15188 声明、:15343 命中）⇒ 补循环头派发表 + 「内层 for 出口复用本 if 的 `if_merge_`」救援分支。实测锚点（2026-10-03）：RC-3 WHY 注释段起于 :15323（:15323–:15334+），救援判据 `for_exit_is_outer_merge_lw` :15356–:15372。**原登记 `:15183 起`** —— 该行现为 `self.pending_merge_non_phi = null;`，与 RC-3 派发无关。**取证否证了 RC-2 的「区间截断」前提可复用**：while 侧 `loop_last_be` 迭代扩展后 `loop_end=8` 已覆盖 for 块（非截断），真正致损的是 merge 体被内联进 then 臂 ⇒ RC-3 只留三条结构判据，不含 `blk_i >= loop_end`。
- **全门实测（2026-09-30，RC-1+RC-2+RC-3 二进制 + REF-002 R-1a/R-1b 模板，合并一轮）**：16 探针门 `same=16/16 differs=0`（含函数上下文 J、RC-3 新增形态 P/Q/R，以及 do-while 侧同族 S）；`zig build test` RC=0；官方 68 回归 **PASS=67 / FAIL_COMPILE=0 / FAIL_RUNTIME=0 / FAIL_DIFF=0 / SKIP=1(f004)**；冻结基线全量漂移 **`total=68 ok=68 diff=0 notemp=0 norow=0`**；确定性巡检 **`total=68 mismatch=0 notemp=0`**；基线抽查 **`ok=5 bad=0`** ⇒ **零漂移、零回归**，无需重冻结基线。
- **CLOSED 之后新登记的候选（不重开本工单）**：2026-10-01 在 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) 的归因探针 `ref003_crash_attr_tmp.php` 上实测到同族**第四形状** —— 同一 if 臂内、内层 `for` **之后**的裸 `break` 未发射（W2 PHP `visited=1` vs AOT `visited=5`）。16 探针门未覆盖该形状 ⇒ 登记为 **RC-4**。**2026-10-01 同日取证完成**：根因是「臂尾无条件 `break`/`continue` 被 IR 折叠进内层循环的出口边」+「三个循环生成器的臂尾派发救援判据只覆盖 `if_merge_` 复用形态」⇒ 截空区间零发射零标记，内层循环整块丢失并在循环外被重发（详见 §4 RC-4）。**2026-10-01 同日修复落地（① 派发门控放宽 + ② 出口边语义，纯新增 +145 行；2026-10-03 提交为 `0ff09cf`）**：Y1MIN 与六形 Y1–Y5、`ref003_crash_attr` W1/W2 均**逐字节等值**；① 单独落地时 16 探针门 `same=16/16 differs=0` 已实证零回归（详见 §4 RC-4「分步落地实测」行）。**验收期间由 ② 的实测暴露同族第五形状 ⇒ 另立 RC-5（臂尾 `continue` + if 有真实 merge 块 ⇒ 延续块兄弟语句丢失）；2026-10-01 已把根因取证到行**（`generateLabelDrivenBlockRange` 的 mark-rest 扫描，随 `break_generated` 置位把延续块整段吞进 `processed`），**并拆为两个互不耦合的 facet**（facet-1 丢失延续块、facet-2 发射侧臂尾缺 `continue :<外层标签>` ⇒ then 路径过执行延续块；**原登记「臂尾 `continue` 未翻译」已由 2026-10-03 静态取证否证** —— IR 层出口边折边正确）。**2026-10-03：facet-1 经用户裁决走方案 B 并已落地（+56/−5，工作区未提交，见 §7 行 12）；facet-2 已完成只读静态取证 + 同日 trace 取证轮（11 条非行为 trace，三份单形探针）⇒ 机制与修法口径实测到行**（§4 ④/⑤：`last_loop_fallthrough_idx` 的记录权只在 foreach :12529/:12687 与 for :14640 三处，while 生成器从不记录、for 的 :14677 外层 latch 跳过早退也不记录 ⇒ 外层臂尾无从续进 latch ⇒ 过执行；F-H 与 F-F 判为**同类机制、不同站点**；原修法候选「臂尾补发显式 `continue`」已被 ⑤ **否证** —— 迭代推进发在体尾，裸 continue 会跳过推进）。**2026-10-04：facet-2 经用户裁决走「方案 R」并落地（先跑 75 脚本全量影子实测、再逐字照实测口径实现两站点；净增 +72/−18，工作区未提交，见 §4「facet-2 落地记录」与 §7 行 15）⇒ F-F/F-H 转逐字节等值、八形合串整份 IDENTICAL，§5 七门在该二进制复测全绿**。RC-4 的 §5 全门六项已于 2026-10-01 实测闭环（§7 行 7）。
- **CLOSED 之后的收尾审计（2026-10-04，只读，发射侧一行未动）**：do-while 侧「站点③」（`generateDoWhileFromLabels` :17391–:17400 的外层 latch 跳过分支，不记录、不交还、无 `in_cond_br_branch`）已审计 ⇒ **两份新永久探针 F-I / F-J + 新独立等值门 `c005_dowhile_probe_run_tmp.sh` 实测 `DOWHILE_PROBE_DONE total=2 same=2 differs=0`**，但**等值不来自站点③ 正确**：三条独立证据（IR 无 `do_while_cond_/do_while_exit_` 前置块、F-F↔F-I 生成码 A/B、`generateDoWhileFromLabels` 唯一调用点 :8250 被 :17521/:17566 的 `has_do_while` **函数级否决**）共同证明**该生成器当前不可达** ⇒ 站点③ 是未执行的死代码，**解禁时须同批按方案 R 补第三站点**（§7 行 16）。顺带**否证并更正**了 §修复方案 P2 行对 S 探针的旧归因（`:17155` 实测漂移至 `:17354`；S 等值实为整函数回退状态机）。审计外溢的性能发现另立 [AOT-PERF-001](AOT-PERF-001-默认优化档位与函数级状态机回退.md)（默认 `release_small` + 逐指令全局变量/装箱 Value 热点，§7 行 17）。
**发现日期**: 2026-09-30（AOT-REF-002 引用探针取证过程中顺带暴露，与引用无关）
**关联**: [AOT-REF-002 §3.1](AOT-REF-002-iter-ref-slot-dangling.md)（发现上下文）；历史同类 #16「while 体内嵌套 if-without-else 的 merge 臂丢失」、f085「单语句 if-continue/if-break 发射缺陷」；**同族后继单**：[AOT-CODEGEN-006](AOT-CODEGEN-006-elseif-chain-arm-loop-lost.md)（2026-10-04 立项，站点为 **if/elseif 链自身**而非循环体臂；表征含本单 RC-2 的「臂内 for 塌缩为仅初始化」与本单 RC-4 的「臂尾 `br` 缺失 ⇒ 串臂」；已用 HEAD `0ff09cf` 对照实证**非本单 RC-5 批次引入**；**2026-10-04 该单 trace 取证轮 R1/R2/R3 闭环** ⇒ 机制到行、发射侧一行未改，并证伪了「走 `generateIfFromLabels`」的初判（归属为本单同一处行内 `.cond_br` 处理器 :8357）；其 A 类修复要移植的正是本单 else 臂 `.br` 的三段判据模板（:9659–:9724，`.br` 分支 :9661）；**同日 R4 修复面前置影子轮（全 88 脚本，`drift_diff=0`）亦闭环**，并锁定一条硬约束：移植时**只能取模板 ② 的窄四前缀子集**（`for_cond_`/`while_cond_`/`foreach_cond_`/`do_while_body_`），宽 `isLoopHeadLabel`（含 `foreach_increment_*`）会命中本单已收口面内的 f044/f067/f160 三个通过脚本，属真实回归面；详见 006 §3.5.2 与 §4.1 步骤 2–3）

---

## 1. 复现（永久探针，勿删）

> **读数时点**：本节与 §2 的「AOT」列记录的是 **2026-09-30 缺陷态**读数（RC-1/RC-2/RC-3 落地前），不是当前二进制的输出；该形态（探针 F）在 §5 判据 1 的 17 形等值门中**已逐字节等值**（`PROBE_DONE total=17 same=17 differs=0`）。保留原读数以复现「静默丢失」的判定证据链。

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

## 4. 根因定位（RC-1 / RC-2 / RC-3 / RC-4 四条已到行并落地；RC-5 **facet-1 已到行并落地**（2026-10-03 方案 B，mark-rest 调用点 :7244 / 例程 `markReachableRestBlocks` :25354）；**facet-2 已落地（2026-10-04 方案 R：while 侧站点① :16299 + for 侧站点② :14711 各补「记录 + 交还 latch」）⇒ RC-5 两 facet 均闭环，逐影子读数见 §4「facet-2 落地记录」**）

> **锚点几何校验（2026-10-03 只读复核）**：本节 **RC-1..RC-3 取证段**的行号写于 `b21cdfd` **之前**的树，与当前工作区树（`0ff09cf` + RC-5 未提交 **+56/−5**，32492 行；由落地态 `45969ff9` 的 +54/−3 经同日**逐行等长**注释口径校正得到，未增删任何行 ⇒ 下表锚点与折算律在两代 blob 下同时成立）已不一致，**引用前必须重新 grep**。本日实测对照（旧 → 当前）：
>
> ```text
> expandRangeToChainFlow          :10864  → :10935
> writeBrInLoopContext            :921    → :949
> RC-1 then 臂派发守卫 !processed.contains(nti)  :7417  → :7469
> foreach loop_last_be 扫描       :11178–11193 → :11249–11265
> foreach const loop_end          :11195  → :11266
> foreach 预标记 cleanup/increment/exit  :11229–11232 → 注释 :11199、代码紧随其后
> 通用 merge_bi = blk_i（foreach 侧）    :11502  → :11659（另有 :8725 / :9688 / :13780 / :15343 同形站点）
> coalesce 尾部 [mi, loop_end)    :12249  → :12338
> [body_idx+1, last_back_edge+1)  :12344  → :12433
> [body_idx+1, next_after_body)   :12354  → :12443
> —— 任务 #49（2026-10-03 同日全量重测）新增对照 ——
> RC-1 处理器就地发 break         :7306   → 判定实起 :7320（谓词 :901 / :924 未漂移）
> RC-2 foreach 派发点             :11528  → 注释 :11542、判据 :11556–:11573、remove :11575
> RC-3 while 派发段起点           :15183  → WHY 注释 :15323、救援判据 :15356–:15373
> foreach 循环头派发表（RC-3 注释旧引）:11502 → :11516–:11525
> for 循环头派发表（RC-3 注释旧引）:13622  → :13694–:13703
> 顶层 !all_processed 兜底（RC-5 注释旧引）:6511 → :6497–:6514（判定 :6505、return false :6513、顶层调用 :6494）
> B-lite 同帧迭代化站点（CODEGEN-004 旧引）:8075 → 守卫 :8153、兜底递归 :8178
> 发射 main 底账分配器（MEM-001 旧引）:1863 → :1894
> php_object_get_ref builtin 注册（REF-001 旧引）:3803 → :3831
> foreach 引用 alloca 识别段（REF-002 旧引）:5200 → :5203–:5241（消费点 :19602）
> ```
>
> 下列锚点复核于 **RC-5 工作区代次**（blob 链 `45969ff9` → `9c5e8286` → `310536e5`，行数恒 **32492**）：RC-5 段（:7206–7212 调用点 :7209、例程 :25300、`hasPredecessorInRange` :25262、coalesce 判据 :12331–12341、else 臂 :12037–12039、顶层兜底 :6497–6514）与 RC-4 段（`loopHeadKind` :937/:939–946、`isLoopContinueTarget` :924、foreach 派发 :11556–11572 与 :11575、区间 :11576–11633、for :13717–13733 与 :13735–13773、while :15356–15372 与 :15376–15409、`loop_end` for :13459 / while :15131）。
>
> **代次失效告警（2026-10-05 实测）**：CODEGEN-006 的 A 批（`22a217f0`，+65）、D 批（`9490bf9f`）、R9-B 批（`0e38b018`/32796 行，vs RC-5 累计 **+304**）在**多个不相邻 hunk** 各插一段 ⇒ **不存在统一偏移**，上表数字在当前树**全部需按符号重 grep**。今日实测对照（左＝RC-5 代次，右＝当前树 `0e38b018`）：`markReachableRestBlocks` 调用点 :7209 → **`:7452`**；其定义 :25300 → **`:25604`**；`hasPredecessorInRange` :25262 → **`:25566`**；顶层 `!all_processed` 判定 :6505 → **`:6748`**（`var all_processed = true;` **`:6740`**）；`loop_end` foreach :11556 区 → **`:11551`**、for :13459 → **`:13744`**、while :15131 → **`:15424`**；`loopHeadKind` :939 → **`:939`（未变）**、`isLoopContinueTarget` :924 → **`:924`（未变）**、`isOuterLoopLatch` :951 / `findExitEdgeSourceIdx` :959 → **未变**。反证统一偏移不成立：`25300 → 25604` 是 **+304**，而 `6505 → 6748` 是 **+243**、`13459 → 13744` 是 **+285**、`15131 → 15424` 是 **+293** ⇒ 四个不同 hunk ⇒ **只可 grep，不可连加推算**（与 [AOT-PERF-001 §8.4](AOT-PERF-001-默认优化档位与函数级状态机回退.md)、[AOT-CODEGEN-006 §4.5](AOT-CODEGEN-006-elseif-chain-arm-loop-lost.md) 的当代次表同读）。
>
> **同类失效也存在于源码注释内**：`markReachableRestBlocks` 的 doc 注释（当前树 **`:25597`**）仍写着 RC-5 代次的顶层兜底口径 `:6497–:6514，判定 :6505、return false :6513`。当前树逐条 grep 实测：顶层调用 `generateLabelDrivenBlockRange(writer, func, 0, …)` = **`:6737`**（原 `:6494`）、`// 检查是否所有块都已处理` = **`:6739`**、`var all_processed = true;` = **`:6740`**、`if (!all_processed) {` = **`:6748`**（原判定 `:6505`）、`return false;` = **`:6756`**（原 `:6513`）⇒ 兜底区间现属 **`:6748–:6756`**。修正属**纯注释改动**，按 RC-5 既有纪律须与功能改动**分轮**、且单独复验「发射中性」（代次注释仅改文字 ⇒ 生成码逐字节不变，须以九形/十七形等值门 + 冻结基线抽查自证）；门串占用编译窗口期间不动，留作下一个干净批次的卫生项。

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

### RC-4（2026-10-01 登记为候选，同日**取证 + 修复落地（①②）**；2026-10-03 提交为 `0ff09cf`）

> **行号口径**：本节三行（门控缺陷、修复口径、RC-5 候选）里的 `native_linker.zig` 行号是 **①②（RC-4）落地后重新 grep 的实测值**，①② 已于 2026-10-03 提交为 `0ff09cf`；**RC-5 方案 B 的 +54/−3 仍在工作区未提交**，本节 RC-5 行的 `:7206–7212`、`:25300`、`:25262` 与 §修复方案「P2 → 已落地」行的 `:7209` 均为**含 RC-5 改动的当前工作区实测值**。本文其余历史条目（RC-1/RC-2/RC-3 各行、§5、§7）引用的仍是 `b21cdfd` 树锚点，折算到当前树需加纯新增插入量：`<934` 不变、`934–11561` +14、`11562–13662` +72、`13663–15264` +111、`15265–25279` +145、**`≥25280` +196**。RC-5 的两段 hunk 中，调用点 :7204–7212 为**等长替换**（−3/+3，净 0 行 ⇒ 不改 `<25280` 各段的折算律），新增例程 51 行插在 25280 之后（⇒ 其后锚点再 +51）。折算律经 `:8520 → :8534`（范围行走侧注释）与 `:7306 → :7320`（RC-1 判定注释）两点验证；个别当年登记的锚点自带 ±5 误差，**使用前请重新 grep**。

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
| **RC-5（2026-10-01 由 ② 的验收实测暴露 ⇒ 同日追踪取证到行；2026-10-03 按用户裁决以**方案 B** 落地 facet-1）** | **主形**：臂尾裸 `continue` 且 if **有**真实延续块（`if_merge_` 承载后置兄弟语句，或显式 `else` 臂）时，兄弟语句在任一路径都不发射（`c005_rc4_min_y6_tmp.php` 实测 PHP `hit=3` vs AOT `hit=0`）。**机制（追踪实证，非推断）**：走线性派发（`blk_i < loop_end` ⇒ ①/RC-2 门控根本不触发）⇒ 臂尾内联发射外层 latch + `continue :__foreach_0` 置 `break_generated=1` ⇒ 控制回到公共范围行走时起点被回退到 latch 之后、**落在延续块之前**，于是 `generateLabelDrivenBlockRange` 的「return/break 已生成 ⇒ 剩余块整段标记 `processed` 并返回」（**:7206–7212**）把 merge/else 块一并吞进 `processed` ⇒ 下游 coalesce 延后发射（:12331–12341）与 else 臂发射（普通路径 :12037–12039，判据 `!processed.contains(ei)`）双双落空。**原候选归属已否证**：显式 `else` 形根本没有 `if_merge_` 块、`else_is_coalesce=0`，仍以同一 mark-rest 扫描丢失 ⇒ 不是 coalesce 判据过宽，而是扫描越界吞块。八形实测表与逐行追踪读数见 **§RC-5 取证细则**；**落地口径见 §修复方案「P2 方案 B」行**（已采纳并实施，调用点 :7209 + 新增例程 `markReachableRestBlocks` :25300）；**facet-1 已关闭、facet-2 未覆盖**（仍为阅读推论，未经 trace 取证，禁止动发射侧），实施与全门记录见 §7 行 9 / 行 12 |
| 同根派生的兜底 | 空区间「零发射零标记」是静默失效族（与 #18 金丝雀同源）。建议配套加一条发射期断言：`.br → 循环头` 派发后若目标块仍未落进 `processed` ⇒ 打 `[AOT-CANARY]`。是否与修复同批，待一并裁决 |
| 是否阻塞 | **已解除对本工单的阻塞**：② 落地后 W2 首次逐字节等值，[AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) 的 F4b/F5 复测不再被本缺陷污染，且 W2 反转为「迭代器推进前 break ⇒ 不崩」的正向对照。**仍阻塞的是 REF-003 自身**：W3（增长后 `continue`，迭代器继续推进）仍 `rc=139`，属运行时模板的 P0 段错误，需 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) §10 行 1 的裁决后才动 `runtime_lib_template.zig` |

### RC-5 取证细则（2026-10-01 八形实测 + 临时打印追踪，trace 已剥离）

**探针**：`fuzzy_scripts_720/tmp/c005_rc5_merge_loss_tmp.php`（**永久，勿删**，八形 F-A…F-H 一次编译）；**诊断门**：`fuzzy_scripts_720/tmp/c005_rc5_probe_run_tmp.sh`（末行 `RC5_PROBE_DONE`）。该门独立于 RC-4 诊断门与 17 形等值门，避免追溯性改变已登记的验收记录。

**单形探针（2026-10-03 静态取证新增，均永久勿删）**：`c005_rc5fb_only_tmp.php`（F-B 正控制，helper `rc5fb_mk`）、`c005_rc5ff_only_tmp.php`（F-F，helper `rc5ff_mk`）、`c005_rc5fh_only_tmp.php`（F-H）——从八形合串拆出，便于逐形门禁与 `ZIGPHP_AOT_KEEP_TEMP` 读生成码，实测读数见 §4「facet-2 静态取证」。

**八形实测（2026-10-01，同一还原后的二进制，`--compile` 于项目根、真值 `/opt/homebrew/bin/php` 8.5.8）**：

| 形 | 形状（相对 Y6MIN 的变量） | PHP 真值 | AOT 实测 | 判定 |
|---|---|---|---|---|
| F-A | 臂尾 `continue`，if 后**无**兄弟语句（无 `if_merge_`，else 边即 `foreach_increment_`） | `visited=4 hit=0 count_x=4` | 同 | ✅ 等值（**正对照**，RC-4 已闭环子形） |
| F-C | 有兄弟语句 `if_merge_`，臂尾**无**裸 `continue` | `visited=4 hit=4 count_x=4` | 同 | ✅ 等值（**正对照** ⇒ 裸折边是必要条件） |
| F-B | 臂尾 `continue` + 兄弟语句 `$hit++`（= Y6MIN 主形） | `visited=4 hit=2 count_x=4` | `hit=0` | ❌ **facet-1**（延续块丢失） |
| F-D | 同 F-B，兄弟语句写成**显式 `else` 臂**（IR 无 `if_merge_`，else=`if_else_`） | `visited=4 hit=2 count_x=4` | `hit=0` | ❌ **facet-1** ⇒ **否证**「仅 `else_is_coalesce` 判据过宽」 |
| F-E | 同 F-B，兄弟语句换成副作用 `echo` | `E3 E4` + `count_x=4` | 回声缺失、仅 `count_x=4` | ❌ **facet-1** ⇒ 排除「只丢 PHI 目标变量」的解释 |
| F-F | 同 F-B，内层循环换成 `while` | `visited=4 hit=2 count_x=4` | ~~`hit=4`~~ ⇒ **2026-10-04 起 `visited=4 hit=2 count_x=4`（等值）** | ✅ **facet-2 已落地**（原登记「`continue` 未翻译」已由 2026-10-03 静态取证**否证** —— IR 中内层出口边正确指向外层回边 `foreach_increment_2`，缺的是发射侧臂尾未续进外层 latch；**⑤ trace 实测**：`lft` 全程 `null`、② 救援 `FR3` 零命中，`iter_next`+`continue :__foreach_0` 只在**外层 foreach 体尾**（臂缩进之外）发射 ⇒ 根因是 while 生成器（:14741–:16332）无记录点且 :14988 无条件预标记吞掉该 latch。**修法 = 站点①（现 :16299）：出口块命中外层 latch 且本 while 在 if 臂内派发时「记录 + `return exit_idx`」交还 ⇒ 外层臂 range 在臂缩进续走 latch。见 §4「facet-2 落地记录」**） |
| F-G | 臂尾换成 `break` + 兄弟语句 | `visited=1 hit=0 count_x=2` | 同 | ✅ 等值（①/② 已覆盖 break 形） |
| F-H | 同 F-B，外层换成 `for` | `hit=1 count_x=6` | ~~`hit=3`~~ ⇒ **2026-10-04 起 `hit=1 count_x=6`（等值）** | ✅ **facet-2 已落地**（for 侧同族；**⑤ trace 实测**：`FOR1 … defer=0 prem_order=1` ⇒ for 的记录分支（现 :14667）因**第一前提** `defer_loop_fallthrough=0` 不成立，落到外层 latch 跳过分支「`processed.put` + `return exit_idx+1`」且**不记录 `lft`** ⇒ 外层 for 无从把臂尾续进到 `for_loop_3`；`count_x=6` 等值 ⇒ 内层 for 本体发射正确，红点仅在臂尾。**修法 = 站点②（现 :14711）：在 if 臂内派发（`in_cond_br_branch`）时「卸载该 latch 标记 + 记录出口边 + `return exit_idx`」交还。见 §4「facet-2 落地记录」**） |

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

逐条结论：`blk_i=21 < loop_end=23` ⇒ **RC-2 与 ① 的截空门控都不触发**，走既有线性派发（`path=linear`，:11634–11636）⇒ 内层 for 与 `count_x` 正确；臂尾内联发射外层 latch（`foreach_increment_17`）+ `continue :__foreach_0` 置 `brk=1`，且行走起点被回退到 **18**（latch 之后、延续块 20 之前）⇒ `[RC5T7]` 的 `mark-rest-processed i=18 end=23` 把 18/19/20/21/22 **整段标记 `processed`** ⇒ `[RC5T3d] pElse=1`、`[RC5T4] pMerge=1` ⇒ :12331–12341 的 `if (!processed.contains(mi))` 不成立 ⇒ merge 体（`$hit++`）在任一路径都不发射。

F-D（显式 else，else=`if_else_39`(28)）同一扫描 `[RC5T7] mark-rest-processed i=26 end=31 brk=1 start=29` ⇒ `pElse=1` ⇒ :12037–12039 的 else 臂连 `} else {` 都不发 ⇒ **归属改判**：缺陷在 mark-rest 扫描的吞块范围，不在 coalesce 判据。

F-A 也触发同一扫描（`i=4 end=8 brk=1`），但该形延续块就是 increment(3)，**在被吞区间之前** ⇒ 零丢失 ⇒ 解释等值门（17 形）为何从未抓到本缺陷。F-C 走 `[RC5T3a] path=rc2_outer_merge` ⇒ `pElse=0` ⇒ 正常；RC-2 的 `_ = processed.remove(ei_lh)`（:11575）正是同一吞块行为的**既有局部解法**，方案 A 即把它推广。

F-F **无** `[RC5T7]` 命中、`pElse=0`、`brk=0`、`lft=null` ⇒ 臂尾 `continue` 根本没进入出口边翻译机制（facet-2 独立于 facet-1，不能靠同一修法关闭）。

**facet-2 静态取证（2026-10-03，只读 ⇒ 发射侧一行未动，`native_linker.zig` 仍为 RC-5 三代 blob `310536e5`）**

新增三份**永久单形探针（勿删）**，把八形文件里的三个形拆出以便逐形门禁与 KEEP_TEMP 读生成码：

| 探针 | 形 | 复跑命令（项目根） | 实测读数 |
|---|---|---|---|
| `fuzzy_scripts_720/tmp/c005_rc5fb_only_tmp.php` | F-B（正控制：foreach 外 + for 内） | `timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info --output=/tmp/aot_compile_c005_rc5fb_only_tmp <src>` ⇒ `timeout 10` 跑产物 | PHP `visited=4 hit=2 count_x=4` = AOT ⇒ **IDENTICAL** |
| `fuzzy_scripts_720/tmp/c005_rc5ff_only_tmp.php` | F-F（foreach 外 + while 内） | 同上，换文件名 | PHP `visited=4 hit=2 count_x=4` vs AOT `visited=4 hit=4 count_x=4` ⇒ **DIFFERS（过执行 2 次）** |
| `fuzzy_scripts_720/tmp/c005_rc5fh_only_tmp.php` | F-H（for 外 + for 内） | 同上，换文件名 | PHP `hit=1 count_x=6` vs AOT `hit=3 count_x=6` ⇒ **DIFFERS（过执行 2 次）** |

**① IR 侧：原登记口径「臂尾 `continue` 未翻译」在 IR 层被证伪。** F-F 与 F-B 的 IR 在相关结构上**逐字同形**：

```text
F-B  for_cond_7:     br .{id=21}, for_body_8,      foreach_increment_2     ← 内层出口边 = 外层 increment
F-F  while_cond_7:   br .{id=21}, while_body_8,    foreach_increment_2     ← 同一目标，仅内层循环种类不同
两形公共布局： if_then_5（臂尾 br → 内层循环头）紧邻 if_merge_6（$hit++，br → foreach_increment_2）
```

⇒ `continue` 已被正确折进**内层循环的出口边**、且该边直指外层 `foreach_increment_2`（跳过 `if_merge_6`），语义完全正确；丢失只可能发生在发射侧。

**② 生成码侧：F-B 与 F-F 的唯一差别是臂尾有没有续上外层回边。**

```text
F-B（等值）main.zig:
  1064-1066   reg_50 = reg_34; _ = reg_50.retain(); continue :__foreach_0;   ← 臂尾内联 iter_next + continue
  1067-1068   } else { }
  1071-1072   reg_31 = getGlobalVar("$hit");        ← merge 体只在 false 边到达

F-F（过执行）main.zig:
  833   if (reg_17.toBool()) {
  839     __while_1: while (true) {
  850-852   if (!(reg_21.toBool())) { break :__while_1; }     ← IR 的 foreach_increment_2 目标被发成「仅退出内层 while」
  983       continue :__while_1;
  984     }                ← 内层 while 收尾
  985   } else {
  986   }                  ← then 臂尾【没有任何】continue :__foreach_0
  987-1070  reg_31/reg_32 = $hit++                            ← 两条形都直落执行到它
  1073-1152 reg_34 = iter_next(reg_50); ... continue :__foreach_0;
```

⇒ **F-F 机制已到行**：内层 `while` 的出口边落点是**外层回边**（`foreach_increment_2`），发射时只发了 `break :<内层标签>`，臂尾未再续 `continue :<外层标签>`；因 `if_merge_6` 在布局上紧邻 then 臂，条形一出 `if` 就撞上 merge 体 ⇒ 后置兄弟语句被执行 4 次而非 2 次。与 RC-4 步骤② 的分工清晰：② 只在 `lft == exit_idx` 时发 break（foreach 侧 :11623–:11633、while 侧 :15401–:15408），而 `lft == 外层 increment` 一支按 :11619–:11622 的注释口径「不发任何语句」，其成立前提是**臂后没有兄弟语句**（F-A 形）——本形前提不成立。

**③ F-H 不是同一机制（勿一并修法）**：其生成码几何不同 —— `} else {` 出现在 main.zig:225，而内层 for 的 `continue :__for_1` 直到 :300 才出现、`$hit++` 在 :305，说明内层 `for` 的本体被裹进了 if/else 结构之内（属 RC-2 家族乱序），与 F-F 的「臂尾缺 continue」不同因 ⇒ 需各自的 trace 轮次，禁止用一条修法同时宣称关闭。

**④ 全量 grep 补充（2026-10-03 只读，行号口径 = blob `310536e5` / +56/−5）：`last_loop_fallthrough_idx` 的「记录权」在三侧生成器不对等 ⇒ facet-2 的行级候选根因。**
- 全树该字段**只有 3 处非空赋值**：`generateForeachFromLabels`（:12529 `= ei`、:12687 `= ni`，发射 exit / cleanup-next 时记录）与 `generateForFromLabels`（:14640 `= exit_idx`，带 `self.defer_loop_fallthrough and exit_idx < cond_idx` 双前提）。
- `generateWhileFromLabels`（:14741–:16332，实测下一个 `fn` 起于 :16333 `generateIfFromLabels`）对该字段**只读不写**：:15354 / :15406 / :15428 全为置 `null`，:15392 / :15402 / :15417-15418 为消费；`defer_loop_fallthrough` 在该函数内也只出现在 ① 救援分支的保存/恢复（:15352-15353、:15413）⇒ **外层为 foreach/for、内层为 while 时，外层 ② 的 `if (self.last_loop_fallthrough_idx) |lft_|` 必然落空** ⇒ 与 RC-5 八形 trace 读数「F-F `lft=null`、`brk=0`」逐字吻合，即 F-F 不是「臂尾判据写错」而是**上游根本没交回出口边**。
- while 侧还把 exit 块**无条件预标记**为已处理（:14988-14989 `processed.put(exit_idx)`，注释 :14984-14986 明言「无论 body 终止符类型如何，exit 块都将在本函数内处理……必须提前标记以防止父调用者重复处理」）⇒ 当 while 的出口边恰是外层 latch（F-F 的 `while_cond_7: br …, foreach_increment_2`）时，该 latch 归 while 生成器消费，外层 foreach 臂尾既无从内联增量、也没有 `continue :<外层标签>` 可发 ⇒ then 路径直落兄弟语句 `$hit++`（过执行，方向与实测 `hit=4` vs `hit=2` 一致）。
- **trace 轮已跑完（2026-10-03，见下 ⑤）—— 上述两点均已实测回答**：(a) F-F 生成码 main.zig:1073-1152 的 `iter_next` + `continue :__foreach_0` 由**外层 foreach 自己的体尾发射**产生（不是 while 生成器的 exit 发射）；(b) F-H 的 for 侧 :14640 **根本没有执行** —— 它在 :14677-14682 的外层 latch 跳过分支里提前 `return exit_idx + 1`，双前提的第一项 `defer_loop_fallthrough` 在该形状实测为 0。
- 顺带登记的**注释锚点漂移**（不在本批处理，禁改发射侧文件）：:14985 注释内引的「L9758-9761」与 while 生成器实际范围（:14741–:16332）不符，疑为早期代次行号；后续如需修正须走「纯注释代次 + 发射中性复跑」流程。

**⑤ facet-2 trace 取证轮（2026-10-03 已跑完 ⇒ 发射侧仍一行未动；行号口径 = 还原后 blob `310536e5` / +56/−5，trace 代次仅作读数不作锚点）**

手段：在临时插桩代次（11 条 `std.debug.print`，tag `[F2T-*]`，全部非行为）上编三份**单形**探针，读 walk 序列与决策位；随后由 `/tmp` 备份整份还原并复验。trace 只写 stderr、不经 `writer`，故插桩代次生成的 `main.zig` 与还原代次逐字节相同 ⇒ 下表的 `main.zig` 行号读数可直接视为落地代次的读数。成本实测：插桩态 `timeout 240 zig build` 通过（首次因 `{?d}` 用于非 optional 的 `usize` 报 1 错，改正后 RC=0）→ 三形编译 + 运行 → 还原 → `zig build` **62s** → 门 A `PROBE_DONE total=17 same=17 differs=0`、RC-5 八形门 `F-A/F-B/F-C/F-D/F-E/F-G` 等值 + `F-F hit=4`、`F-H hit=3` 两红点原样、RC-4 诊断门 `same=3 differs=1`、stderr 零 `[F2T` 残留 ⇒ **取证未污染落地态**（KEEP_TEMP 临时目录 `.zigphp_aot_build_57383`/`57556` 与全部 `/tmp` 捕获已删，**零 `.php` 删除**）。

| 探针 | 关键 trace 读数（实测原文，节选） | 判定 |
|---|---|---|
| F-B（等值正控制） | `FR1 … defer=1` ⇒ `FOR1 for label=__for_1 exit=3/foreach_increment_2 cond=7 … defer=1 prem_defer=1 prem_order=1` ⇒ `LDR walk i=3 label=foreach_increment_2 start=7 end=9 ilen=12` ⇒ `FR2b … lft=3 brk=1` ⇒ `LDR walk i=6 label=if_merge_6 start=6 end=9 ilen=8` ⇒ `FGINC … brk=0 lastline_ret=0` | 内层 for 命中 :14638（`defer=1` 且 `exit<cond`）⇒ `processed.remove(exit)` + 记录 `lft=exit_idx`（:14640）+ `return exit_idx` ⇒ **臂内 range 从 i=3 续走**，在臂缩进（12）内联发射外层 latch + `continue :__foreach_0`（生成码 main.zig:988 iter_next / :1066 continue），merge 再以体缩进（8）发射 ⇒ 兄弟语句仅 false 边到达；体尾 `FGINC brk=0` 再发一份 latch（:1156/:1234）⇒ **两份各司一路径，非重复发射** |
| F-F（过执行） | `FR1 blk=7 blklabel=while_cond_7 … fm_lh=0 lft=null defer=1` ⇒ `W1 while ENTER label=__while_1 cond=7 body=8 exit=3/foreach_increment_2 end=9 defer=1` ⇒ `W2 while PRE-MARK exit=3/foreach_increment_2` ⇒ **`FR2b … lft=null brk=0`** ⇒ `LDR walk i=6 … ilen=8` ⇒ `LDR walk i=3 label=foreach_increment_2 start=3 end=9 ilen=8` ⇒ `FGINC … brk=1 lastline_ret=1` | ① **`lft` 全程为 null** ⇒ foreach ②/救援（:11613-:11628）从未进入（`FR3` 零命中）；② while 生成器既无 :14638 那样的记录点，也无 :12543/:14677/:17341 那样的外层 latch 跳过分支 ⇒ 出口边在 while 内被 `break :__while_1` 消费掉；③ 臂 range（start=7 end=9）**永远走不到索引 3**，latch 只能由**外层 foreach 体尾**的 range（ilen=8）发射 ⇒ 生成码 `iter_next` 出现在 main.zig:1073、`continue :__foreach_0` 出现在 :1152，**均在 `if` 之外** ⇒ then 臂尾无跳过语句 ⇒ `$hit++` 被执行 4 次（真值 2） |
| F-H（过执行） | `LDR walk i=7 label=for_cond_7 start=7 end=9 ilen=12` ⇒ `FOR1 for label=__for_1 exit=3/for_loop_3 cond=7 … defer=0 prem_defer=0 prem_order=1` ⇒ `FOR2 for OUTER-LATCH skip exit=3/for_loop_3 ret=4 lft=null defer=0` ⇒ `LDR walk i=6 label=if_merge_6 start=7 end=9 ilen=12` | 双前提第一项 **`defer_loop_fallthrough=0`**（该字段只在 ① 救援派发前后由 :11542/:13758 等臂内联上下文置位，F-H 的内层 for 由 range 行走的 `for_cond_` 分派直接派发，未经该上下文）⇒ :14638 分支不成立 ⇒ 落到 :14677-14682 的**外层 latch 跳过**：`processed.put(exit)` + `return exit_idx + 1`，**不记录 `lft`** ⇒ 外层 for 无从翻译臂尾裸 `continue` ⇒ merge 体（`$hit++`）在臂缩进被直落执行 3 次（真值 1）。注：`count_x=6` 与真值等值 ⇒ 内层 for 本体发射**正确**，红点只在臂尾 |

**由 ⑤ 得出的三条修法约束（不含实施，实施待裁决）**：
1. **正确的翻译几何 = 在臂缩进内联发射外层 latch 块 + 紧随 `continue :<外层标签>`**（F-B 即此形态且等值）。裸发 `continue :<外层标签>` 而**不**先发 latch 是错的 —— label-driven foreach/for 的迭代推进（`iter_next` / `$i++`）发在**体尾**，跳到 `while (true)` 头会跳过推进 ⇒ 死循环或漏元素。故 F-F/F-H 的修法必须让外层 range 在臂尾「续走到 latch」，而不是补一条 continue 语句。
2. **F-F 与 F-H 同属一类机制、但落在两个不同站点**：F-F 是 `generateWhileFromLabels` 缺记录点（:14741–:16332 区间内 `last_loop_fallthrough_idx` 只读不写），F-H 是 `generateForFromLabels` 的外层 latch 跳过分支（:14677-:14682）早退不记录。⇒ 可共用一个「记录 + `return exit_idx`」的口径，但**站点不同、须分别过门**，不得以一处改动宣称同时关闭（本行同时**部分否证**上方 ③ 的「F-H 属 RC-2 乱序家族、与 F-F 不同因」—— 实测 `count_x` 与 `visited` 均等值，F-H 的红点与 F-F 同为「臂尾未续 latch」，差别只在触发路径）。
3. **两处改动都要避开探针 H 的反例**：`lft` 若指向外层自身控制块，foreach 侧 :11613-:11616 已有「恢复标记」逻辑；新增记录点不得 `processed.remove` 非本次消费的块，也不得卸载外层 latch 的既有标记（卸载 ⇒ 增量重复发射，`$i` 跳号）。`defer_loop_fallthrough` 的置位面**不建议**作为 F-H 的修法（放宽它会改写 f161 缺陷B / xp8 幻影输出的守卫前提，回归面远大于「跳过分支补记录」）。

**facet-2 落地记录（2026-10-04，用户裁决 = 方案 R「一条机制覆盖 F-F/F-H」；先全量影子实测、再逐字照实测口径实现）**

流程约束沿用 facet-1 的 process rule (a)：**任何触及共享发射语义的改动，必须先用非行为影子插桩在全语料量出命中面，实现必须字面等于实测口径**。本轮实测数据如下。**留存口径**：全部读数已逐条转录进下表（下表的聚合计数即由原始文件用 `awk` 复算得出），故影子插桩的原始捕获 `/tmp/sh5_shadow_all.txt`、扫描 stdout `/tmp/sh5_scan_stdout.txt` 与一次性扫描脚本 `fuzzy_scripts_720/tmp/c005_sh5_shadow_tmp.sh` 已于 **2026-10-04 清理删除** —— 该插桩本身也已从 `native_linker.zig` 还原移除（当前树 `SH5-` 残留为 0），**此影子扫描不可复跑**；需要新读数时须按本节方法重插。永久探针与四份门脚本不受影响。

| 项 | 实测读数 |
|---|---|
| 影子插桩 | 5 类非行为读数标签（只写 stderr、不经 `writer` ⇒ 生成码不变）：`SH5-FR`（foreach ② 记录/消费点）、`SH5-FS`（**for 外层 latch 跳过分支**＝候选站点②）、`SH5-W1`（while ENTER，打印 `exit_label`/`is_latch`/`defer`/`in_branch`/`indent.len`）、`SH5-W2`（while 自有 exit 发射）、`SH5-W3`（while **乱序 exit**＝候选站点①） |
| 扫描规模 | 75 脚本 = `fuzzy_scripts_720/pass/*.php`（68）+ 7 份永久探针，逐脚本 `--compile` 不运行产物 ⇒ `SH5_DONE total=75 scripts_with_hits=31`、聚合 207 条读数 |
| 标签分布 | `SH5-FR` 17 / `SH5-FS` 16 / `SH5-W1` 50 / `SH5-W2` 41 / `SH5-W3` 7 |
| **门控判别式的来源**（关键） | ① **`defer_loop_fallthrough` 不可用**：`SH5-FS` 的 16 条读数里 **`defer=true` 为 0 条**（F-H 正落此组），故旧「放宽 defer 置位面」的候选连触发都触发不了；② **`in_cond_br_branch` 可用且唯一区分**：`SH5-FS` 中 `in_branch=true` 恰 **3 条**（另 13 条 `in_branch=false`）；while 侧 `is_latch=true` 共 8 条（W1 4 + W3 4），其中 `in_branch=true` **4 条 = 2 个事件**（每事件在 ENTER 与乱序两处各印一次），且这 2 个事件的 latch **全部**是 `foreach_increment_*` ⇒ 判别式取 **`isOuterLoopLatch(label) && in_cond_br_branch`**，线性体派发（`in_branch=false`）保持原消费不动 |
| **按脚本归因**（用聚合文件里的 `===SCRIPT\|name` 顺序标记定位） | **站点①（while 交还）触发集 = 2 脚本，全部是探针**：`c005_rc5ff_only_tmp`（`order_exit idx=3 label=foreach_increment_2`）、`c005_rc5_merge_loss_tmp`（`idx=41 label=foreach_increment_58`）⇒ **68 语料 0 命中**；**站点②（for 交还）触发集 = 3 脚本**：`c005_rc5fh_only_tmp`（`exit_idx=3 for_loop_3 cond=7`）、`c005_rc5_merge_loss_tmp`（`exit_idx=56 for_loop_80 cond=60`）、**`f028_dp_knapsack_lcs_lis`（`exit_idx=5 for_loop_5 cond=7`，语料唯一命中）** ⇒ 整个语料的回归面 = **1 脚本 / 1 事件**，三条站点②事件 `ilen` 均为 12（即落在臂缩进） |

落地代码（三处新增 + 一处 DRY 复用；`src/aot/native_linker.zig`，行号口径 = 落地代次 blob `3ae7b34e`、32546 行、相对 HEAD **+128/−23**，其中 facet-2 净增 **+72/−18**）：

```zig
// src/aot/native_linker.zig :951 —— 共用谓词：块是否为【外层循环 latch/回边】（NativeLinker 结构体内，缩进 4）
    fn isOuterLoopLatch(label: []const u8) bool {
        return std.mem.startsWith(u8, label, "for_loop_") or
            std.mem.startsWith(u8, label, "foreach_increment_");
    }

    // :959 —— 出口边源块查找（原 generateForFromLabels 记录分支的内联 blk_src: 计算抽出共用，DRY）
    fn findExitEdgeSourceIdx(
        func: *const IR.Function,
        cands: []const usize,
        exit_idx: usize,
        exit_block: *const IR.BasicBlock,
        fallback_idx: usize,
    ) usize { /* .br / .cond_br 命中 exit_block 即返回该候选索引，否则 fallback */ }
```

- **站点①（`generateWhileFromLabels` 乱序 exit 分支，:16299–:16303）**：既有 `_ = processed.remove(exit_idx)` 之后、resume 到 `extended_end`/`end_idx` 之前插入「出口块是外层 latch 且 `in_cond_br_branch` ⇒ `last_loop_fallthrough_idx = exit_idx` + `last_loop_fallthrough_src_idx = exit_src_idx orelse cond_idx` + `return exit_idx`」。⇒ while 不再把外层 latch 消费成自己的收尾，外层 foreach 臂 range 从 latch 索引续走，在臂缩进内联发射 `iter_next` + `continue :<外层标签>`。
- **站点②（`generateForFromLabels` 外层 latch 跳过分支，:14711–:14721）**：原「`processed.put(exit)` + `return exit_idx + 1`」之前插入 `if (self.in_cond_br_branch)` 的「**卸载该 latch 标记** + 记录出口边（`findExitEdgeSourceIdx`）+ `return exit_idx`」交还分支；线性体派发仍走原「标记 + 跳过」。
- **DRY 复用（:14678）**：既有 `defer_loop_fallthrough and exit_idx < cond_idx` 记录分支的同一段内联源块扫描（17 行）改为调用 `findExitEdgeSourceIdx` ⇒ 记录口径三处共享一份实现（−17/+7）。

**两条自证更正（本轮实测，非推演）**：

1. **首版站点② 缺 `processed.remove(exit_idx)` ⇒ F-H 未修**：只补「记录 + `return exit_idx`」时 F-B/F-F 已等值但 `F-H` 仍 `hit=3`。根因是**该分支的既有标记**：跳过分支先前 `put(exit_idx)` 留下的标记使外层臂 range 一见 `processed.contains` 就跳过 latch ⇒ 无从内联。补上与 F-B 模板（:14668）同形的 `_ = processed.remove(exit_idx)` 后三形全等值。此 remove **只作用于本次由我们接管消费的块**（即该 latch 本身），不触碰任何非本次消费的标记 ⇒ 不违反行 12 立下的「不得卸载外层既有 latch 标记」约束（该约束针对的是共享控制块，如探针 H 的 `if_merge_`）。
2. **「f028 会漂 DIFF」这条预测被实测否证**：f028 是站点② 在语料里的唯一命中，我据此预期门 D 漂移报 `DIFF`。实测 **`DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`**，并对该脚本单形复验：`live=24741/6daa5bd7117a977bfa6d3171eee2c2b6` == `frozen=24741/6daa5bd7117a977bfa6d3171eee2c2b6` ⇒ 交还路径在 f028 上的**发射结果与旧口径逐字节相同**。**结论口径**：影子命中面 ≠ 发射差异面；安全性判定以漂移门实测为准，不得以命中面反推风险等级（本条按「预测未成立」留存，禁止在后续文档里反述为「命中即漂移」）。

**复测记录**：落地态七门见 §7 行 15；三处调用/签名折行（纯排版，152/156 列 → Zig 100 列风格）后在**重编译二进制**上复跑 门A `same=17/17`、RC-4 诊断门 `same=3 differs=1`（唯一红点为 REF-003 的 W3 段错误）、RC-5 八形合串 `IDENTICAL`、三形单形探针 `c005_rc5fb/rc5ff/rc5fh` 全 `IDENTICAL`、冻结基线抽查 `SPOT_DONE ok=5 bad=0` ⇒ 折行发射中性。

**facet-2 候选归属（2026-10-03 只读静态取证 + 同日 trace 取证轮已跑完；机制已实测 ⇒ 下表「修法口径」行已于 2026-10-04 按方案 R 实施，最终口径与实测读数见上一小节，本表保留为取证记录）**：

| 项 | 内容 |
|---|---|
| 判别事实（trace 读数 + 2026-10-03 静态复验） | F-B 与 F-F/F-H **同走线性派发**（`blk_i < loop_end` ⇒ ①/② 门控不触发，进 `else` 分支的 `generateLabelDrivenBlockRange(blk_i, loop_end)`）；但只有 F-B 出现「臂尾内联发射外层 latch + `continue :__foreach_0` 并置 `brk=1`」，F-F（内层换 while）与 F-H（外层换 for）为 `brk=0`、`lft=null`。**静态复验（IR + `ZIGPHP_AOT_KEEP_TEMP` 生成码）已证伪本工单原登记口径「臂尾 `continue` 未翻译」**：F-B 与 F-F 的 IR 里内层循环出口边都已正确指向外层回边 `foreach_increment_2`，缺的是**发射侧臂尾没有落 `continue :<外层标签>`**（逐条对照见上 ②） |
| 推论 | 「臂尾裸 `continue` 靠直落到本层回边」这一处理**只在外层 foreach 的体行走里成立**（foreach 有 increment latch 可被内联到臂尾，直落即等价于 continue）；外层为 for（回边是 `for_loop_`/`for_cond_`，臂尾之后还有兄弟语句 `$hit++`）或内层为 while（实测 IR：`while_cond_7: br …, foreach_increment_2`，出口边直接就是**外层 latch** 而非自身的 `while_exit_` ⇒ 该 latch 被 while 生成器消费，见上 ④）时，直落会把 `$hit++` 一并执行 ⇒ 过执行（F-F `hit=4` vs PHP `hit=2`、F-H `hit=3` vs PHP `hit=1`，方向一致）。**F-H 站点另案但同类**（见上 ⑤：`count_x`/`visited` 等值 ⇒ 内层 for 本体发射正确，红点与 F-F 同为「臂尾未把外层 latch 续进到臂缩进」；差别只在触发站点 —— for 的 :14677-:14682 外层 latch 跳过早退不记录，vs while 在 :14741–:16332 根本没有记录点 ⇒ 可共用「记录 + 交还 latch」的口径，但**必须分站点对门、分别取证**，不得以一处改动宣称同时关闭） |
| 代码位置（行号口径 = blob `310536e5`、`git diff --numstat` +56/−5，2026-10-03 grep/Read 实测） | 三处线性派发点的 `else` 回落分支：foreach :11634-11636、for :13774-13775、while :15410-15412（三者同形，均调 `generateLabelDrivenBlockRange(writer, func, blk_i, loop_end, …)`）；「落点为外层回边（裸 continue）⇒ 不发任何语句」口径实测在 foreach :11619-11622 与 for :13761-13764，其 ② 判定/发射分别为 :11623-11628 与 :13765-13768（**均只在 ①/② 救援分支内，线性路径无对应翻译**）；while 侧臂尾 `.br` 处理自 :15294 起，对本层回边 `br_target == cond_block_ptr` 是**真发** `continue :label`（:15311-15314），② break 发射 :15404 ⇒ 「三侧口径不一致」本身即取证目标。**更上游的行级候选见上 ④**：`last_loop_fallthrough_idx` 的非空赋值仅 :12529 / :12687（foreach）与 :14640（for），while 生成器（:14741–:16332）从不记录 ⇒ 内层为 while 时外层 ② 无从触发 |
| 修法口径（由 ⑤ 实测反推 ⇒ **2026-10-04 已按方案 R 实施，最终读数见上「facet-2 落地记录」**；本行保留为实施前的口径记录） | **原候选「在线性派发臂尾补发一条显式 `continue :<外层标签>`」已被 ⑤ 否证** —— label-driven `foreach`/`for` 的迭代推进（`iter_next` / `$i++`）发射在**体尾**，跳到 `while (true)` 头会跳过推进 ⇒ 死循环/漏元素，故不可用「补语句」达成语义。**实测成立的口径是复制 F-B 的几何**：内层循环把「出口边 = 外层 latch」作为 `last_loop_fallthrough_idx` 交还外层，并**不**预先消费该 latch 块，使外层臂内 range 从 latch 索引续走 ⇒ 在臂缩进内联发射 latch + `continue :<外层标签>`（F-B 的 main.zig:988/:1066 即该形态，且体尾另有一份供 false 边，各司其职）。落到代码即两处：**① 给 `generateWhileFromLabels`（:14741–:16332）补记录点并取消对该 latch 的消费/预标记**（:14988-:14989 的无条件预标记在 `exit` 命中外层 latch 时不应吞块）；**② 把 `generateForFromLabels` 的外层 latch 跳过分支（:14677-:14682）由「标记 + `return exit_idx + 1`」改为「记录 + 交还」**。**约束**：不得放宽 `defer_loop_fallthrough` 的置位面（回归面涉及 f161 缺陷B / xp8 幻影输出守卫）；不得 `remove` 非本次消费的标记、不得卸载外层既有 latch 标记（探针 H 反例）；F-A/F-B/F-C/F-D/F-E/F-G 六形必须逐字节不变。**实施结果（2026-10-04，与本行口径的两处实测偏差）**：① 站点① **无需**取消 while 的无条件预标记（原 :14988-:14989 一行未动）—— 乱序 exit 分支本身已有 `_ = processed.remove(exit_idx)`，只需在其后补「记录 + 交还」；② 站点② 除「记录 + `return exit_idx`」外**必须**同时卸载**本分支自己先前写入**的 `processed` 标记，否则外层臂 range 一见 `processed.contains` 就跳过 latch（首轮实测 F-H 仍 `hit=3`，补 remove 后才等值）；六形未回退，见上「facet-2 落地记录」 |
| 取证计划 | ✅ **已完成（2026-10-03 trace 取证轮，见上 ⑤）**：插桩站点为 foreach 臂尾派发/线性回落/① 消费（:11576 区、:11634 区、:11613 区）、foreach 增量发射（:12449 区）、for 的 :14638 门控与 :14677 跳过、while 的 ENTER/预标记/exit 两路、`writeBrInLoopContext`（:949）与 `generateLabelDrivenBlockRange` 主循环逐块 walk —— 共 11 条 `std.debug.print`（实测站点数多于原计划的 4 条，因需区分「谁消费 latch」）。只编三份单形探针 ⇒ 实测成本 2 次 `zig build`（插桩态 + 还原态 62s）。原计划判据「F-F 是否走到目标为外层回边 + 臂后兄弟语句非空」的答案是否定的：**F-F 根本没进入该机制**（`lft=null`、`FR3` 零命中），故修法不在臂尾判定而在记录权 —— 已据此把上行的候选改法推翻重写 |

**取证成本与还原（实测）**：`zig build` 61.85s（插入 7 处 trace）→ 取证 → 由 `/tmp` 备份整份还原（`md5 9dff465ff6276ceb03c971e1212ca835`，`git diff --stat` 回到 +145/−0）→ `zig build` 61.53s → 等值门复跑 `PROBE_DONE total=17 same=17 differs=0` 且 stderr 无 `RC5T` 残留 ⇒ **RC-4 落地态未受取证污染**。

### do-while 侧「站点③」审计（2026-10-04，只读取证 + 两份新永久探针，发射侧一行未动）

**动机**：facet-2 只在 while 站点①（:16299–:16303）与 for 站点②（:14711–:14721）落了「记录 + 交还 latch」。`generateDoWhileFromLabels`（:17317–:17426）在 **:17391–:17400** 有一个**同形但更早存在**的外层 latch 跳过分支（`for_loop_` / `foreach_increment_` ⇒ `processed.put(exit_idx)` + `return exit_idx + 1`），既不记录 `last_loop_fallthrough_idx`，也没有 `in_cond_br_branch` 判据 ⇒ 它是潜在的**第三站点**：若该分支在 F-F/F-H 同族几何下会被执行，就是同类缺口的漏网之处。

**取证资产（永久，勿删）**：

| 探针 | 几何 | PHP 真值 | 与谁成对 |
|---|---|---|---|
| `fuzzy_scripts_720/tmp/c005_rc5fi_only_tmp.php`（F-I） | 外层 foreach + 臂内嵌 **do-while** + 臂尾裸 `continue` + 兄弟语句 `$hit++` | `F-I visited=4 hit=2 count_x=4` | 与 F-F 逐字同构，仅内层 `while`→`do-while` |
| `fuzzy_scripts_720/tmp/c005_rc5fj_only_tmp.php`（F-J） | 外层 for + 臂内嵌 **do-while** + 臂尾裸 `continue` + 兄弟语句 `$hit++` | `F-J hit=1 count_x=6` | 与 F-H 逐字同构，仅内层 `for`→`do-while` |

**独立门脚本**：`fuzzy_scripts_720/tmp/c005_dowhile_probe_run_tmp.sh` ⇒ 判据 `DOWHILE_PROBE_DONE total=2 same=2 differs=0`。2026-10-04 实测 **`total=2 same=2 differs=0`**（两形均 `IDENTICAL|rc=0`）。该门**不并入** 17 形等值门，避免追溯性改变 RC-4/RC-5 已登记的验收记录。

**结论：等值成立，但**不是**站点③ 正确，而是**整条原生发射路径被函数级否决**。三条独立证据：

1. **IR（F-I，`--compile --dump-ir`，走 stderr）**：do-while 在函数里**只有一个块** `do_while_body_7`，其终止符自指回边 —— `br .{id=30}, do_while_body_7, foreach_increment_2`；全函数**不存在** `do_while_cond_*` / `do_while_exit_*`（`ir_generator.zig` 生成三块，是后续折叠/边线程化把它们并掉了）。⇒ `generateDoWhileFromLabels` 的前置搜索 :17330（`"do_while_cond_"`）与 :17331（`"do_while_exit_"`）`orelse return end_idx` **必然落空** ⇒ 该生成器不接受此形态。
2. **生成码 A/B（`ZIGPHP_AOT_KEEP_TEMP=1` 逐字计数）**：

   | 代次目录 | 探针 | `current_block` | `switch (current_block)` | `: while (true)` label 循环 | `__do_while` |
   |---|---|---|---|---|---|
   | `16519` | F-I（foreach + 内嵌 do-while） | 23 | 1 | 1（在辅助函数 `rc5fi_mk` 的 `__for_0`，顶层脚本零） | **0** |
   | `18338` | F-J（for + 内嵌 do-while） | 23 | 1 | **0**（连外层 for 都没拿到原生循环） | **0** |
   | `16623` | F-F（foreach + 内嵌 while，F-I 的对照） | **0** | 0 | 3（`__for_0` / `__foreach_0` / `__while_1`） | — |
   | `19179` | S（外层 do-while + 臂内嵌 for，2026-09-30 等值探针） | 25 | 1 | 0 | **0** |

   ⇒ F-F ↔ F-I 只差一个内层关键字就使发射策略从「原生 label 循环」翻转为「`switch (current_block)` 逐块派发」，一次 A/B 即证**否决由 do-while 触发**；且 F-J 的 `: while (true)` 计数为 0 说明否决是**函数级**（整个函数体一起回退，不只是 do-while 那一层）。
3. **结构证明（强于推测）**：`generateDoWhileFromLabels` 在全树的**唯一**调用点是 :8250，位于 `generateLabelDrivenBlockRange`（:7223）内；该 range 生成器的非递归入口只有 :6529（在 `tryGenerateFromLabels` :6496 内）与 :1033（在 `writeBrInLoopContext` :984 内），后两者属同一 AST-direct 族；AST-direct 的唯一入口是 :17525，受 **:17521 门** `if (!func.has_multi_level_break and !has_do_while and !has_switch and !has_match and !has_exception_handler)` 约束，而 `has_do_while` 由 **:17482** 对**同一函数**的块标签扫 `"do_while"` 置位 ⇒ 含 do-while 的函数被自己的特征**否决了唯一能发射它的路径**。第二条结构化路径受 :17566 同一否决，且 `tryGenerateStructuredControlFlowNew`（:24628–:24731）内 `do_while` **零命中** ⇒ 不存在其它原生 do-while 派发口。**⇒ `generateDoWhileFromLabels` 在当前管线不可达（死代码），:17391–:17400 的站点③ 从不执行。**

**两处自证更正（对本文 §修复方案 的 P2 同族扫描行）**：① 该行旧引「do-while 生成器把 body 交回 `generateLabelDrivenBlockRange(..., body_idx + 1, cond_idx, ...)`（**:17155**）」的锚点已漂移，实测现处 **:17354**；② 更关键的是**机制归因错误** —— S 探针（外层 do-while）当时被记为「循环头派发表本已生效」，实测 S 的生成码同样是 `current_block` 25 次 + `switch (current_block)` 1 处 + `__do_while` 0 处 ⇒ S 等值的真实原因是「整个函数落进状态机（保守但正确）」，**与 `generateDoWhileFromLabels` 无关**。「S 无需新增代码」的结论不变，依据必须按上表改写。

**对 RC-5 的意义与风险搬家**：facet-2 的两站点覆盖面**不向 do-while 扩展、也无需扩展**（站点③ 不可达，该形态的正确性目前由状态机兜底）。风险换了位置：**一旦解禁 `has_do_while`**（把 do-while 交给原生发射），:17391–:17400 会以 facet-2 落地前的**原始缺陷形态**（不记录、不交还、且无 `in_cond_br_branch` 判据）立即生效 ⇒ 解禁必须**同时**按方案 R 口径补第三站点，并复用 F-I/F-J 两形作验收门。工单登记见 §7 行 16；性能侧副作用（否决导致整函数丢原生循环）另立 [AOT-PERF-001](AOT-PERF-001-默认优化档位与函数级状态机回退.md)。

**取证成本（实测）**：本轮 `zig build` **0 次**（发射侧一行未动），AOT 编译 4 次（F-I/F-J 门 + S 生成码 + F-J 生成码，均 `timeout 300`），其余为 IR/生成码读取与计数。

### 修复方案（P0/P1/P2 · 影响面 · 落地成本）

| 优先级 | 方案 | 影响面 | 落地成本 |
|---|---|---|---|
| **P0** | **RC-1 收口（已落地）**：新增成对谓词 `isLoopContinueTarget`（:924，块自身即本循环条件块、或以 `br` 落回条件块 ⇒ 认定为本层回边/continue），并在 `if_merge_`+`cond_br` 处理器（:7306）的 then/else 派发**之前**判定「两条边分别落在本循环的 break 目标（cleanup/exit）与 continue 回边上」，命中则就地发 `if (cond) { <exit PHI>; break :current_loop_label; }`（break 边在 else 侧时条件取反），假边侧不置 `break_generated`（否则尾部增量与 `continue` 被抑制），末以 `i += 1; continue;` 交回范围行走 | 单一处理器，且该处理器在**公共**范围行走内 ⇒ foreach / while / for 体内同形态一并收敛 | 实测 +63/−6 行（判据全部复用 `isLoopBreakTarget` :901 与 `generateExitPHIAssignments`，无新抽象） |
| **P0** | **RC-2 收口（已落地，口径修订）**：原设想「派发终点越界时回退外层 `end_idx`」被 grep 否证 —— for 侧**已有同形且已实证**的修法：`for_loop_exit_is_outer_merge`（:13638，内层 for 的 exit 复用外层 if 的 merge ⇒ 交自包含 `generateForFromLabels(blk_i, end_idx)` + 卸载被预标记的共享 merge）。范围行走侧 :8520 的注释「for/foreach 的 exit 复用外层 merge 场景暂不在此处理」正是本缺口登记处。故把该分支镜像到 foreach 侧 then 臂尾派发点（:11528），并加两道严格前提：① `blk_i >= loop_end`（仅救援【区间已被截空】的形态，正常布局零影响）；② 延续块标签必须是 `if_merge_` —— 探针 H 的 `else_bi` 是 `foreach_increment_` 且内层 for 的 exit 同样落在其上，缺此排除会把 increment 误卸载标记 ⇒ 增量重复发射 | 改动臂内嵌循环的派发终点，但被两道前提约束在乱序截断形态内 | 实测 +37/−1 行 |
| P1 | 金丝雀扩展：在 `if_merge_`+`cond_br` 处理器里，若双臂目标均已被 processed 且本次未发出任何 `break/continue/return` ⇒ 发射期 `[AOT-CANARY]` 报警（把本形态纳入 #18 闸门，防同类静默回归）。**注**：RC-1 已让该形态真发 break，金丝雀是「万一判据不成立时不再静默」的兜底，仍待裁决 | 1 处判据 | 低（≈8 行） |
| P1 | 语料检测力：把 F/J 形状（体内「前置无 else if + 后置单语句 if-break」+ 臂内嵌循环）补进 `fuzzy_scripts_720` 生成模板 | 测试资产；需重冻结一次基线 | 低 |
| **P0** | **RC-4 收口（已落地，2026-10-01，见 §4 RC-4 三行）**：两步缺一不可 —— **(i)** 三处臂尾 `.br → 循环头` 派发点各补一条「区间将被截空」救援分支（foreach :11576–11633 / for :13735–13773 / while :15376–15409）：`blk_i >= loop_end` 且目标命中任意循环头（新增共用谓词 `loopHeadKind` :937–946，取代三处各写一遍的前缀串，符合 DRY）⇒ 按类别交自包含 `generate*FromLabels(blk_i, end_idx)`，派发后补记循环头 `processed` 并恢复被内层乱序回落卸载的**本层**控制块标记；`processed.remove(else_bi)` 仍严格限定 `if_merge_`（探针 H 教训）。**(ii)** 出口边语义：内层出口落在外层 cleanup/exit ⇒ 消解该边 PHI + `break :<本层标签>` + 置 `break_generated`；落在外层回边（裸 `continue`）⇒ 不发语句，靠直落本层增量；`break_generated` 抑制边界复用 :12389–12392 的「双臂 AND」既有机制，守 CODEGEN-003 修复 4 的约束 | 三处派发点 + 出口边语义；触到 break/continue 语义而非仅派发终点，风险高于 RC-1；但四段 hunk 全部为**新增分支**、既有救援路径逐字未动 ⇒ 正常布局（未截空）零路径改变 | 实测 **+145/−0 行**（+14 共用谓词 / +58 foreach / +39 for / +34 while）；`timeout 240 zig build` 通过、`zig build test` 326/326、① 单独态 16 探针门 `same=16/16` |
| ~~P0~~ **未采纳** | **RC-5 facet-1 方案 A（窄口径）** —— 2026-10-03 用户裁决改走方案 B，本行**保留为对照记录，不再实施**。原设想：臂尾线性派发返回后，若本 if 的**延续块**索引（`merge_bi`/`else_bi`）被 mark-rest 扫描连带标记，则卸载标记交还既有共享发射（即把 RC-2 的 `_ = processed.remove(ei_lh)` 推广到「线性派发 + 任意延续块」） | 只触臂尾折边 + 有延续块的 if | 未落地；站点与判据保留：F-B/F-D/F-E 三形转绿、正对照不变，但**只治三个探针命中的形态**，公共扫描的越界吞块语义仍在 |
| **P2 → 已落地** | **RC-5 facet-1 方案 B（根治，2026-10-03 落地）**：mark-rest 扫描不再「整段标记到 `end_idx`」，改调新增例程 **`markReachableRestBlocks`**（:25300，调用点 :7209）—— 只把「**无法**从已发射前缀到达」的剩余块标记为 `processed`，仍可达的块（典型为该 if 的 `if_merge_`/显式 `else` 延续块）留在 `processed` 之外交还下游发射。**口径三条（全部为实测所得，非设计推演）**：① **种子集 = 前缀 `[0, sweep_start)` 的 `.br` / `.cond_br` 目标**，与影子插桩完全一致，**不做正向闭包**（f007 实证：闭包会保留无发射消费者的块 ⇒ 撞 `!all_processed` 兜底）；② 只看 `.br`/`.cond_br` 两类边，`switch_`/`unreachable` 等不参与；③ **只「不加标记」，绝不 `remove` 既有标记**（探针 H 教训：卸载共享控制块标记 ⇒ 增量重复发射） | 该扫描是**公共出口** ⇒ 触及所有循环/if 的收尾语义；实测差异面见右列 | **实测 +54/−3 行**、两段 hunk（调用点 :7204–7212 等长替换 3 行 + 新增例程 51 行 @:25280 之后）；`timeout 240 zig build` 通过（**69s**，v1/v2 两次一致）。**影子扫描实测回归面**（临时插桩，非行为改变，73 脚本 = 68 语料 + 5 探针门）：`RC5B_DONE total=73 fail=0 scripts_with_swallow=4` ⇒ **68 语料 0 处**、命中仅 4 个探针共 **6 个收尾点**（`c005_rc5_merge_loss_tmp` 3 点，`c005_rc4_min_y6_tmp` / `c005_rc4_break_after_nested_loop_tmp` / `ref003_crash_attr_tmp` 各 1 点），**每点从剩余 5 块中只放行 1 块**（`swallowed=1 tot=5`），放行块名 5 处为 `if_merge_*`、1 处为 `if_else_39`，无一个控制块/循环块 ⇒ 与「只影响延续块」的设计意图吻合。**v1→v2 教训**：v1（+92/−3，含正向闭包 + `switch_` 种子）在 68 回归上打出 **`FAIL_COMPILE f007 AstDirectGenerationFailed`** ⇒ 按影子口径收紧后 f007 复测 `COMPILE_RC=0`、`OUTPUT_IDENTICAL`、无 `[AST-DIRECT-FAIL]`/`[AOT-CANARY]`。**RC-5 八形门（v1、v2 两次实测一致）**：正对照 F-A/F-C/F-G 等值不变，**facet-1 三形 F-B / F-D / F-E 全部转逐字节等值**（`F-B visited=4 hit=2 count_x=4`、`F-D visited=4 hit=2 count_x=4`、`F-E` 输出 `E3 E4` 且 `count_x=4`），F-F/F-H 仍为 facet-2 已知红点。**六项全门（17 形等值门 / RC-4 诊断门 / 68 回归 / 基线漂移 / 确定性巡检 / 冻结基线抽查 + v2 上 `zig build test`）本批正在串行复测，实测值待回填 §7 行 12** |
| **P1 → 已落地**（2026-10-04 方案 R） | **RC-5 facet-2（取证闭环 ⇒ 已按方案 R 落地，见 §4「facet-2 落地记录」与 §7 行 15）**：F-F（while 内层）与 F-H（for 外层）的过执行**不是**臂尾判据写错，而是**出口边的记录权缺失** —— 全树 `last_loop_fallthrough_idx` 的非空赋值只有 foreach :12529/:12687 与 for :14640（后者还需 `defer_loop_fallthrough`，F-H 实测为 0 ⇒ 落空），`generateWhileFromLabels` 从不记录且 :14989 无条件预标记吞掉外层 latch，for 的 :14677-:14682 外层 latch 跳过分支「标记 + `return exit_idx+1`」也不记录 ⇒ 外层臂尾无从续进 latch，`iter_next`/`continue` 只能在体尾（臂外）发射（⑤ 逐形 trace 原文与判定见 §4 ⑤）。**修法两站点**：while 侧补记录 + 取消对 latch 的预标记消费；for 侧把跳过分支改为「记录 + 交还」。**已否证的候选**：在臂尾补发显式 `continue :<外层标签>`（迭代推进发在体尾 ⇒ 跳过推进，会引入死循环/漏元素） | while/for/foreach 三侧臂尾语义 + `processed` 标记所有权 | **trace 轮已花完**（实测 2 次 `zig build`：插桩态 + 还原态 62s；三份单形探针已永久化）；修复**未报价**，且须先影子实测再实现（承接 facet-1 的 process rule (a)）；约束：六形 F-A/F-B/F-C/F-D/F-E/F-G 逐字节不得回退，不得放宽 `defer` 置位面，不得卸载外层既有 latch 标记。**实测落地（2026-10-04）**：影子扫描 `SH5_DONE total=75 scripts_with_hits=31` ⇒ 新口径命中面 = **站点① 2 脚本（全是探针，语料 0）+ 站点② 3 脚本（语料唯一命中 `f028_dp_knapsack_lcs_lis` 1 事件）**；净增 **+72/−18**（含 DRY 复用 −17/+7）、两站点为 while :16299–:16303 与 for :14711–:14721，另新增共用谓词 :951 与例程 :959；F-B/F-F/F-H 三形与八形合串**全部逐字节等值**，六形未回退，§5 七门在该二进制串行复测全绿（§7 行 15）；`f028` 的 `main.zig` 与冻结基线同 md5 ⇒ 语料零漂移、未重冻结 |
| P2 | **DRY 收口**：把三处形近的 ① 分支抽成一个共用例程（参数化「本层控制块集合 + break 边判据 + defer 保存点」，骨架共享：截空判定 → `loopHeadKind` 派发 → 补记循环头 `processed` → 恢复本层标记 → 出口边语义），消除 +58/+39/+34 行的三写重复（详见 §6 末条） | 横跨 foreach/for/while 三个生成器的签名改造；语义不变 ⇒ 判据仍是「等值门 + 诊断门 + 全门」三轮不变 | 中（≈ −60/+40 行净收敛）；**必须单独成批、单独过 §5 全门**，禁止与功能修复混提 |
| P2 | 同族形状扫描（**已实测收敛，2026-09-30**）：`c005_k_seq_if_for_tmp`（CODEGEN-002 原文复现，`K x=c`）、`c005_l_while_sibling_break_tmp`（while 侧同形，`L hits=4 mark=7`）、`c005_m_for_sibling_break_tmp`（for 侧同形，`M hits=4 seen=0`）、`c005_n_while_nested_for_break_tmp`（while + 臂内嵌 for，`N hits=4 count=40`）、`c005_o_for_nested_for_break_tmp`（for + 臂内嵌 for，`O hits=4 count=40`）、`c005_p_while_nested_foreach_tmp`（while + 臂内嵌 foreach，`P hits=4 count=4`）、`c005_q_while_nested_while_tmp`（while + 臂内嵌 while，`Q hits=4 count=40`）、`c005_r_while_else_nested_for_tmp`（while 的 **else** 臂内嵌 for，`R hits=4 count=11`）、`c005_s_dowhile_nested_for_tmp`（do-while + 臂内嵌 for，`S hits=4 count=40`）。**结论**：RC-1 在公共处理器 ⇒ for/while/foreach 三侧同步收敛（K/L/M 实测印证）；N/O 分化出 RC-3（while 侧缺循环头派发、for 侧本已有）；~~S 无需新增代码 —— do-while 生成器把 body 交回 `generateLabelDrivenBlockRange(..., body_idx + 1, cond_idx, ...)`（:17155），循环头派发表本已生效~~ **【机制归因已被 2026-10-04 实测否证：该调用锚点现处 :17354，但 S 的生成码实测为 `current_block` 25 次 + `switch (current_block)` 1 处 + `__do_while` label 0 处 ⇒ S 等值的真实原因是含 do-while 的函数被函数级门控（:17482 置位 → :17521/:17566 否决）**整函数**回退到状态机，`generateDoWhileFromLabels` 根本未被执行；「S 无需新增代码」的结论不变，依据见 §4「do-while 侧站点③ 审计」**】。九探针 AOT 输出与 `/opt/homebrew/bin/php` **逐字节等值**，同族扫描关闭（**关闭范围限当时覆盖的形状**；2026-10-01 新登记的 RC-4「同臂内、内层循环之后的 break」不在其中，见上表 RC-4 行；do-while 侧另立 F-I/F-J 两形与独立门，见 §4 审计小节） | 潜在同族 | 实测 9 探针（≈3 分钟），零新增代码 |

## 5. 验收门（修复时）

1. **17 探针等值门**：`fuzzy_scripts_720/tmp/c005_probe_run_tmp.sh` 全绿 —— A,B,F,G,H,I,J,K,L,M,N,O,P,Q,R,S + **Y1MIN**（RC-4 复现单形，2026-10-01 纳入）全部与 `/opt/homebrew/bin/php` 逐字节等值（含函数上下文 J、RC-3 新增的 P/Q/R、do-while 侧同族 S），验收判据为脚本末行 `PROBE_DONE total=17 same=17 differs=0`（2026-10-01 RC-5 取证的临时 trace 剥离并重建后**复跑仍为 17/17**，stderr 无 `RC5T` 残留）；
1b. **RC-4 诊断门**（非等值门，专盯本轮四探针）：`fuzzy_scripts_720/tmp/c005_rc4_probe_run_tmp.sh` ⇒ 判据**随 RC-5 facet-1 落地而收紧（2026-10-03 实测口径 `total=4 same=3 differs=1`）**：**Y1MIN + 六形文件 + Y6MIN 三探针全等值**（六形文件不再允许「仅 Y6 行差异」，Y6 属 facet-1 已修形态），**唯一允许的红点是 `ref003_crash_attr`**，且必须满足「W1/W2 等值、AOT 输出止于 W2、`rc=139`」⇒ 归 REF-003；出现任何其他差异（含 Y6 回退）即视为 RC-4 或 RC-5 未收口；
1c. **RC-5 诊断门**（八形）：`fuzzy_scripts_720/tmp/c005_rc5_probe_run_tmp.sh` + 三份单形探针 ⇒ 判据**随 facet-1（2026-10-03）、facet-2（2026-10-04 方案 R）两次落地逐次收紧，当前口径（2026-10-04 实测）为等值门**：**八形合串 `c005_rc5_merge_loss_tmp` 整份输出必须 `IDENTICAL`**（原「仅 F-F / F-H 两形允许红点」的豁免**已作废** —— F-F/F-H 随两站点交还 latch 转逐字节等值），且 **F-A / F-B / F-C / F-D / F-E / F-G 六形不得回退**；配套三份永久单形探针 `c005_rc5fb_only_tmp` / `c005_rc5ff_only_tmp` / `c005_rc5fh_only_tmp` **逐形 `IDENTICAL`**（即与 PHP 真值一致：F-B/F-F `visited=4 hit=2 count_x=4`、F-H `hit=1 count_x=6`）。合串或六形中任一回退、或三份单形任一差异，即视为 facet-1/facet-2 回归或新缺陷；
1d. **do-while 侧独立等值门**（2026-10-04 新建，**不并入** 17 形门，以免追溯性改变 RC-4/RC-5 已登记的验收记录）：`fuzzy_scripts_720/tmp/c005_dowhile_probe_run_tmp.sh` ⇒ 判据 `DOWHILE_PROBE_DONE total=2 same=2 differs=0`，2026-10-04 实测**全绿**（`IDENTICAL|c005_rc5fi_only_tmp|rc=0`、`IDENTICAL|c005_rc5fj_only_tmp|rc=0`，真值 `F-I visited=4 hit=2 count_x=4` / `F-J hit=1 count_x=6`）。**判据边界（必须写入复测结论，不得反述）**：本门只证「do-while 同族几何的输出等值」，**不证站点③ 正确** —— 两形的函数体都被 `has_do_while` 函数级否决、整份落进 `switch (current_block)` 状态机（取证见 §4「do-while 侧站点③ 审计」）⇒ 只要解禁该否决，本门立刻升级为真正的站点③ 验收门。命名区分：本门的 F-I/F-J 属 RC-5 系列（`c005_rc5fi_only_tmp` / `c005_rc5fj_only_tmp`），与 17 形门里的 `ref002_iso_i_no_nested_for_tmp`（该门简称「I」）无关；
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
| 7 | **RC-4 是否按已定口径落地**（同臂内、内层循环之后的裸 `break`/`continue` 未发射。**2026-10-01 取证完成**：臂尾 break 被 IR 折叠进内层循环的出口边 ⇒ 三处派发点的救援判据（只覆盖「内层出口复用本 if 的 `if_merge_`」）落空 ⇒ `loop_end` 截空区间 ⇒ 零发射零标记 ⇒ 内层循环整块丢失并在循环外被重发（尾部回声）。Y1–Y6 六形 + W1/W2/W3 对照均已结构化实证） | ✅ **已按 ①→② 两步落地（2026-10-01 编码，纯新增 +145/−0 行；2026-10-03 经用户授权提交为 `0ff09cf`）**：授权口径为「保存 zig 文件，继续推进已知问题」+ 本工单先前给出的「你点头我就按 ①→② 分两次过全门」。**已实测**：① 单独态 16 探针门 `same=16/16 differs=0`（⇒ ① 零回归）、①+② 态 Y1MIN 与六形 Y1–Y5、`ref003_crash_attr` W1/W2 逐字节等值、`zig build test` 326/326（细节见 §4「分步落地实测」）。**§5 全门已闭环（2026-10-01 实测）**：① 等值门 `PROBE_DONE total=17 same=17 differs=0`；② RC-4 诊断门 `RC4_PROBE_DONE total=4 same=1 differs=3`（唯一等值项 Y1MIN；三个红点逐行归到已登记缺陷：六形仅 Y6 行 `hit=0` ⇒ RC-5；`ref003_crash_attr` `rc=139` 崩在 W3 ⇒ REF-003）；③ 官方 68 回归 `TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1`（f004 `PHP_error_exit=255`），`regression_failures.tsv` 仅 1 行；④ 基线漂移 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`；⑤ 确定性巡检 `SWEEP_DONE total=68 mismatch=0 notemp=0`；⑥ 冻结基线抽查 `SPOT_DONE ok=5 bad=0`（f067 `47364`/`ad2f742d…`、f113 `104334`/`dab7d3a6…`）⇒ **语料零漂移，未重冻结基线**。REF-003 的 F4b/F5 前置阻塞已随之解除（见行 9 与 REF-003 §6/§10） |
| 8 | 文档自证更正（续行 6） | ✅ 本轮取证**推翻**了 2026-10-01 早前登记的「W2 内层 for 已正确发射（`count=205`、`g199=199` 与真值等值）」：结构化 dump 显示 W2 的 `__foreach_2` 臂内并无 `__for_`，内层 for 以顶层兄弟块出现，`count=205` 来自循环外的**二次执行**。已在 §4「W2 读数更正」与 [AOT-REF-003](AOT-REF-003-byref-iteration-liveset-and-iterator-relocation-crash.md) §5 同步更正 |
| 9 | **RC-5 是否落地**（臂尾裸 `continue` 且 if **有**真实延续块 ⇒ 后置兄弟语句在任一路径都不发射。Y6MIN 实测 PHP `hit=3` vs AOT `hit=0`）。**2026-10-01 追踪取证到行**：机制是公共范围行走的「`return`/`break` 已生成 ⇒ 剩余块整段标记 `processed` 并返回」（`generateLabelDrivenBlockRange` :7206–7211）在臂尾内联发射外层 latch 后回退起点到延续块之前，把 `if_merge_`/显式 `else` 块一并吞进 `processed` ⇒ 下游 :12331–12341 与 :12037–12039 的 `!processed.contains(...)` 判据双双落空 | ✅ **2026-10-03 用户裁决：走方案 B（mark-rest 扫描改按 CFG 反向可达性只标记真正不可达块）**，本批**单独成批**实施，禁止与功能修复混提；**不覆盖 facet-2**（另立取证），与 REF-003 的 P0（迭代器推进崩溃）无耦合。**取证阶段保留的四点须知**：① 该读数在 `b21cdfd`（①/② 之前）即已如此 ⇒ 非本轮引入的回归，是**先于本工单存在**的缺陷；② **原候选归属已否证** —— 显式 `else` 形（F-D）没有 `if_merge_` 块、`else_is_coalesce=0`，仍以同一扫描丢失 ⇒ 不是 coalesce 判据过宽（见行 11）；③ 八形实测**裂成两个 facet**：facet-1（F-B/F-D/F-E，延续块丢失）与 facet-2（F-F while / F-H for，发射侧臂尾缺 `continue :<外层标签>` ⇒ 过执行；原登记「`continue` 未翻译」已由 2026-10-03 静态取证否证），**互不耦合、同一修法关不掉**，正对照 F-A/F-C/F-G 均等值；④ 方案 A（窄口径推广 RC-2 的 `processed.remove`）**未采纳**，其站点与判据保留作对照记录。RC-4 的 +145/−0 已于同日单独提交为 `0ff09cf`（见行 7） |
| 10 | 文档自证更正（续行 8，本轮第二次） | ✅ 两处：① 行 8 的更正本身在 ② 落地后**部分失效** —— W2 现在真的等值（`visited=1 count=205 g199=199`），`count=205` 的来源从「二次执行」回到「臂内正确发射」，故 §4「W2 读数更正」行保留为**历史误读记录**并加注；② **①单独落地态的 `visited=5` 不是回归** —— ① 只把内层循环请回臂内（`count_x` 复原、S2 回声消失），臂尾 `break` 的语义要靠 ② 才发；该中间态若被误判为「修复失败」会导致回滚 ①，故显式登记。顺带得到 REF-003 的三点崩溃序列（`b21cdfd` 不崩 → ① 崩 → ①+② 等值且不崩、W3 仍崩），把 P0 崩溃点定位到「搬迁后的下一次 `next()` 推进」 |
| 11 | 文档自证更正（续行 10，本轮第三次） | ✅ **否证自己的候选归属**：2026-10-01 早先把 RC-5 登记为「`else_is_coalesce`（定义 :11723）成立条件过宽」，本轮八形探针 + 追踪实证显示 F-D（显式 `else`，`coalesce=0`）同样丢失，且丢失发生在 coalesce 判据**之前**的 mark-rest 扫描 ⇒ 该行已按实测改写为「扫描越界吞块」，原推断保留为**已否证的候选记录**。同时新增永久探针 `c005_rc5_merge_loss_tmp.php` 与独立诊断门 `c005_rc5_probe_run_tmp.sh`（不并入 17 形等值门，以免追溯性改变 RC-4 的验收记录） |
| 12 | **RC-5 facet-1 方案 B 的落地记录（承接行 9 的裁决）** | ✅ **2026-10-03 落地，工作区未提交**（`git diff --numstat` = **+54 / −3**，两段 hunk：`generateLabelDrivenBlockRange` 的 mark-rest 分支 :7204–7212 等长替换为 `try self.markReachableRestBlocks(func, i, end_idx, processed)`（:7209）+ 新增例程 `markReachableRestBlocks` :25300）。**实现口径由影子实测反推，不靠设计推演**：先在同一棵树插一条**非行为**影子插桩（只打印「若按新规则会保留哪些块」），跑 73 脚本（68 语料 + 5 探针门）⇒ `RC5B_DONE total=73 fail=0 scripts_with_swallow=4`，**68 语料 0 处命中**、命中面仅 4 个探针共 **6 个收尾点**、**每点从剩余 5 块中只放行 1 块**（`swallowed=1 tot=5`）、被保留块**全部**是 `if_merge_*`（5 处）/ `if_else_39`（1 处） ⇒ 据该口径实现（种子 = 前缀 `.br`/`.cond_br` 目标，无正向闭包，只看这两类边，**绝不 `remove` 既有标记**）。**v1→v2 自证更正（重要）**：v1（+92/−3）自行加了「正向闭包 + `switch_` 也算种子」两条**未经实测**的扩展 ⇒ 官方 68 回归打出 `FAIL_COMPILE f007_string_encoding_crypto_hash.php / AstDirectGenerationFailed`（撞顶层 `!all_processed` 兜底（:6497–6514，判定 :6505、`return false` :6513）：闭包保留了**没有发射消费者**的块）。**处置**：不是放宽规则，而是把实现收回实测口径并删除多余机制（v1 的 `RestReachEdge` 嵌套类型与 `collectRestReachEdge` 一并删）⇒ v2 复测 f007 `COMPILE_RC=0`、`RUN_RC=0`、`OUTPUT_IDENTICAL`、stderr 无 `[AST-DIRECT-FAIL]`/`[AOT-CANARY]`。**已实测门（v2 二进制，`timeout 240 zig build` 69s）**：① 17 形等值门 `PROBE_DONE total=17 same=17 differs=0`；② RC-5 八形门 ⇒ **facet-1 三形 F-B / F-D / F-E 全部转逐字节等值**（`F-B`/`F-D` 均为 `visited=4 hit=2 count_x=4`，`F-E` 为 `E3 E4` + `count_x=4`），正对照 F-A/F-C/F-G 等值不变，**F-F/F-H 仍为 facet-2 已知红点**（本行范围外，见行 9 须知③）；③ `ref003_crash_attr` 的 W1/W2 已随 RC-4 等值、W3 仍 `rc=139`（REF-003，非本批）。**2026-10-03 同日 v2 复测**：RC-4 诊断门 `RC4_PROBE_DONE total=4 same=3 differs=1` —— 相比 RC-4 落地时登记的 `same=1 differs=3`，**Y6MIN（RC-5 主形）与六形文件 `c005_rc4_break_after_nested_loop_tmp` 双双转为逐字节等值**，唯一红点 `ref003_crash_attr_tmp` 为 `DIFFERS`、`rc=139`（AOT 输出止于 W2、W3 段错误）归 REF-003，**清单外零新增差异** ⇒ 符合 §5 判据 1b。**同源站点审计（只读，2026-10-03）**：全树 120 处 `processed.put` 里**区间吞标只有本处一处**（其余全是单索引标记；:16220 的 `for (cond_idx..end_idx)` 是找 exit 边源块的**只读**扫描，不写标记），:7292 / :8220 的 `processed.put(i)` 为当前块单点标记 ⇒ 「扫描越界吞块」在本工单范围内已**根治到唯一站点**，无需向其他生成器扩散。**其余门已于 2026-10-03 在 v2 二进制上串行复测完毕并全绿（同批未并发编译）**：官方 68 回归 `TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1`（`regression_failures.tsv` 仅 1 行 `SKIP\|f004_oop_deep_inheritance_magic.php\|PHP_error_exit=255`，与 RC-4 落地时逐字相同）；冻结基线漂移 `DRIFT_DONE total=68 ok=68 diff=0 notemp=0 norow=0`；确定性巡检 `SWEEP_DONE total=68 mismatch=0 notemp=0`；基线抽查 `SPOT_DONE ok=5 bad=0`（f031/f010/f042/f067/f113 五例实时 `main.zig` 行数与 md5 双双等于冻结记录）；`zig build test --summary all` ⇒ `Build Summary: 21/21 steps succeeded; 326/326 tests passed`、RC=0（其中一行 `failed command: ./.zig-cache/o/55e298300f7347fe4f670dbeb02073ec/test ... --listen=-` 为 `ci_integration.test.CIRunner` 内部嵌套再调用泄漏的既有 stderr 噪声：开批前基线日志同位置逐字一致、该二进制单独复跑 `All 3 tests passed`）。**语料零漂移 ⇒ 未重冻结基线**。**注释代次发射中性自证（同日两次纯注释改动，均不改生成码）**：二代 `9c5e8286` 复跑门 A+B ⇒ `PROBE_DONE total=17 same=17 differs=0`、`GATE_A_RC=0`、`RC4_PROBE_DONE total=4 same=3 differs=1`、`GATE_B_RC=0`；三代 `310536e5` 复跑冻结基线抽查 + 门 A ⇒ `SPOT_DONE ok=5 bad=0`（f031 `5838`/`06e6ec76…`、f010 `16111`/`f8d8e64b…`、f042 `29420`/`a96ab31a…`、f067 `47364`/`ad2f742d…`、f113 `104334`/`dab7d3a6…` 五代次行数与 md5 均等于冻结记录）、17 形逐条 `IDENTICAL` ⇒ `PROBE_DONE total=17 same=17 differs=0`。当前工作区 `git diff --numstat` = **+56 / −5**（三代行数恒为 32492；相对 v2 的 +54/−3 多出的 +2/−2 全在注释行内，即 RC-5 口径注释的 `:6511`→实测 `:6497–6514` 与 RC-3 注释的旧引 `:11502`/`:13622`→实测循环头派发表 `:11516–:11525`/`:13694–:13703`） |
| 13 | **RC-5 facet-2 的只读静态取证轮（承接行 9 须知③）** | ✅ **2026-10-03 完成，发射侧一行未动**（`native_linker.zig` 仍为 blob `310536e5`、`git diff --numstat` **+56/−5**、32492 行，本轮无任何 `zig build`）。**手段全为读**：三份新永久单形探针（`c005_rc5fb_only_tmp.php` / `c005_rc5ff_only_tmp.php` / `c005_rc5fh_only_tmp.php`）逐形取 PHP 真值与 AOT 实跑、`--compile --dump-ir`（IR 走 stderr）读折边、`ZIGPHP_AOT_KEEP_TEMP=1` 保留临时目录并 awk 剥离异常守卫块后读 `main.zig` 几何、以及全量 grep 定位 `last_loop_fallthrough_idx` 的赋值权。**三条结论**：① **否证**工单原登记「臂尾 `continue` 未翻译」（IR 层内层出口边正确指向外层回边 `foreach_increment_2`）；② F-F 机制到行 ⇒ 全树仅 foreach :12529/:12687 与 for :14640 记录该字段，`generateWhileFromLabels`（:14741–:16332）**从不记录**且无条件预标记自身 exit（:14988-14989）⇒ 外层 ② 判据必然落空（详见 §4 ④）；③ **F-H 另案**（for 侧本已有 :14640 记录却不生效，需查 `defer_loop_fallthrough and exit_idx < cond_idx` 双前提）。**修法待裁决**：trace 轮次（≈2 次 `zig build`，站点 :11634 / :13774 / :15410 / `writeBrInLoopContext` :949）未获点头前禁止改发射侧；F-A/F-B/F-C/F-D/F-E/F-G 六形已等值，禁止无条件显式 `continue` 以免打断 latch 内联。**产物已清**：三个 KEEP_TEMP 目录（`52904`/`53149`/`53230`）与 `/tmp` 本轮 IR/生成码/输出捕获全部删除，**零 `.php` 删除** |
| 14 | **RC-5 facet-2 的 trace 取证轮（承接行 13 的「trace 轮次未跑」缺口）** | ✅ **2026-10-03 跑完，发射侧仍一行未动**。**插桩**：11 条 `std.debug.print`（tag `[F2T-*]`，只写 stderr、不进 `writer` ⇒ 生成码逐字节不变），站点为 `writeBrInLoopContext` 入口 :949、foreach 臂尾派发/① 消费/线性回落前后（:11576 区 / :11613 区 / :11634 区）、foreach 增量发射 :12449 区、for 的 :14638 门控与 :14677 跳过、while 的 ENTER / exit 预标记 / exit 两路、`generateLabelDrivenBlockRange` 主循环逐块 walk（打印 `i`/`label`/`start`/`end`/三标志/`indent.len`）。**成本实测**：插桩态 `zig build` 首次报 1 个编译错（`{?d}` 用在非 optional 的 `usize` 上）⇒ 改正后 RC=0；三形编译 + 运行；还原后 `zig build` **62s**；门链复跑见下。**两条待答问题的答案**：**(a) F-F 的 `iter_next`(main.zig:1073) + `continue :__foreach_0`(:1152) 由外层 foreach 自己的体尾 range 发射（`walk i=3 label=foreach_increment_2 start=3 end=9 ilen=8`），不是 while 生成器的 exit 发射** —— 臂 range 是 `start=7 end=9`，索引 3 在它之前 ⇒ 臂内永远走不到 latch；`FGINC` 读数 `brk=1 lastline_ret=1` ⇒ foreach 自己的增量尾部被抑制（不重复发射）。**(b) F-H 的 for :14640 记录分支根本没执行** —— `FOR1 … defer=0 prem_order=1` ⇒ `defer_loop_fallthrough and exit_idx < cond_idx` 的**第一前提**为 0，控制流落到 :14677-:14682 外层 latch 跳过分支「`processed.put(exit)` + `return exit_idx+1`」且不记录 `lft`。**正控制 F-B 的对照组读数是修法的模板**：`defer=1` ⇒ 记录 `lft=3` + `return exit_idx` ⇒ 臂 range 从 i=3 续走 ⇒ 在**臂缩进（12）**内联发射 latch + `continue :__foreach_0`（main.zig:988/:1066），merge 再以体缩进（8）发射，体尾另发一份供 false 边（:1156/:1234）⇒ 等值。**两处自证更正**：① **行 13 结论③「F-H 另案、几何不同因」被部分否证** —— 实测 `count_x=6`、`visited` 等值 ⇒ 内层 for 本体发射正确，F-H 的红点与 F-F **同类**（臂尾未续进 latch），只是站点不同（可共用口径、须分站点对门）；② **§修复方案原 P1 行「在臂尾补发显式 `continue :<外层标签>`」的修法候选被否证** —— label-driven 循环的迭代推进发在**体尾**，裸 `continue` 跳到 `while (true)` 头会跳过推进 ⇒ 死循环/漏元素；正确口径是「内层交还出口边 + 外层把 latch 续进到臂缩进」。**还原复验（与行 12/13 的落地态逐字对齐）**：`native_linker.zig` 回到 blob `310536e5`、`git diff --numstat` **+56/−5**、**32492 行**、`grep -c F2T-` = 0；模板 md5 全程 `008b7b639f1069cb73e443064e115ed1` 未动；门 A `PROBE_DONE total=17 same=17 differs=0`，RC-5 八形门六形等值 + 仅 `F-F hit=4`、`F-H hit=3` 两红点原样，RC-4 诊断门 `RC4_PROBE_DONE total=4 same=3 differs=1`（唯一红点仍归 REF-003 的 W3 段错误）⇒ **取证未污染落地态**。**产物已清**：两个 KEEP_TEMP 目录（`57383`/`57556`）、三形 AOT 产物与 `/tmp` 全部 trace/输出捕获、以及 `/tmp` 上的整份备份 `nl_before_f2trace_tmp.zig` 均已删除，**零 `.php` 删除**（三份单形探针永久保留）。**修法实施仍待裁决**（§六：改发射侧 + 触 `processed` 标记所有权，且须按 facet-1 的 process rule (a) 先做全量影子实测再实现） |
| 15 | **RC-5 facet-2 的落地记录（承接行 14 的「修法实施待裁决」缺口）** | ✅ **2026-10-04 落地，工作区未提交**。**裁决**：用户选「**方案 R：一条机制覆盖 F-F/F-H**」⇒ 授权按 §4 ⑤ 口径实施发射侧两站点，并**先跑全量影子实测**（承接行 12 的 process rule (a)：实现必须字面等于实测口径）。**影子实测**（非行为插桩，聚合为 `SH5-FR/FS/W1/W2/W3` 五类读数，覆盖 foreach 记录/消费点、for 外层 latch 跳过点、while 的 ENTER / 自有 exit / 乱序 exit，只写 stderr ⇒ 生成码不变；75 脚本 = 68 语料 `pass/*.php` + 7 永久探针，逐脚本 `--compile` 不运行）⇒ `SH5_DONE total=75 scripts_with_hits=31`、207 条读数（FR 17 / FS 16 / W1 50 / W2 41 / W3 7）。**判别式由数据反推而非设计推演**：`defer_loop_fallthrough` **不可用**（候选站点② 的 16 条 FS 读数里 `defer=true` 为 **0** 条 ⇒ F-H 永远不触发）；`in_cond_br_branch` **可用且唯一区分**（FS 中 `in_branch=true` 恰 3 条；while 侧 `is_latch=true` 8 条中 `in_branch=true` 4 条 = 2 事件，latch 全为 `foreach_increment_*`）⇒ 取 **`isOuterLoopLatch(label) && in_cond_br_branch`**，线性体派发（`in_branch=false`）保持原消费。**按脚本归因（= 回归面）**：站点① 触发集 **2 脚本全是探针**（`c005_rc5ff_only_tmp`、`c005_rc5_merge_loss_tmp`）⇒ **语料 0 命中**；站点② 触发集 **3 脚本**（`c005_rc5fh_only_tmp`、`c005_rc5_merge_loss_tmp`、语料唯一命中 `f028_dp_knapsack_lcs_lis`）⇒ 整个语料回归面 = **1 脚本 / 1 事件**。**落地**：facet-2 净增 **+72/−18**（相对 HEAD 累计 **+128/−23**）⇒ 四段 hunk = 共用谓词 `isOuterLoopLatch` :951、抽出共用的 `findExitEdgeSourceIdx` :959（并把 for 既有记录分支 :14678 的 17 行内联源块扫描改为调用它，**DRY −17/+7**）、**站点②** for 外层 latch 跳过分支新增 `in_cond_br_branch` 交还分支 :14711–:14721、**站点①** while 乱序 exit 分支交还 :16299–:16303。**两条自证**：① **首版站点② 缺 `processed.remove(exit_idx)` ⇒ F-H 仍 `hit=3`**（跳过分支先前写入的标记让外层臂 range 一见 `processed.contains` 就跳过 latch）⇒ 补与 F-B 模板 :14668 同形的卸载后 F-B/F-F/F-H 三形全等值；该 remove 只作用于本次接管消费的 latch，不违反行 12 的「不得卸载共享控制块既有标记」约束。② **「f028 会在漂移门报 DIFF」这条预测被实测否证** —— 门 D `DRIFT_DONE total=68 ok=68 diff=0`，且单形复验 `live=24741/6daa5bd7117a977bfa6d3171eee2c2b6` == `frozen` 同值 ⇒ **影子命中面 ≠ 发射差异面**，安全性判定以漂移门为准。**七门实测（facet-2 落地二进制，串行、无并发编译）**：门A `PROBE_DONE total=17 same=17 differs=0`；门B `RC4_PROBE_DONE total=4 same=3 differs=1`（唯一红点 `ref003_crash_attr_tmp` `rc=139`，归 REF-003）；**RC-5 八形合串 `IDENTICAL|c005_rc5_merge_loss_tmp|rc=0`**（原 F-F `hit=4`/F-H `hit=3` 两红点消除，六形未回退）+ 三份单形探针 `c005_rc5fb/rc5ff/rc5fh` 全 `IDENTICAL`；门C 官方 68 回归 `TOTAL 68 / PASS 67 / FAIL_COMPILE 0 / FAIL_RUNTIME 0 / FAIL_DIFF 0 / SKIP 1`（`regression_failures.tsv` 仍仅 `SKIP\|f004_oop_deep_inheritance_magic.php\|PHP_error_exit=255`）；门D 冻结基线漂移 `diff=0` ⇒ **语料零漂移、未重冻结**；门E 巡检 `mismatch=0`；门F 抽查 `ok=5 bad=0`；门G `Build Summary: 21/21 steps succeeded; 326/326 tests passed` RC=0（`failed command: ./.zig-cache/o/55e2…/test … --listen=-` 一行仍为 `ci_integration.test.CIRunner` 自调用泄漏的既有 stderr 噪声，非失败）。**排版代次复测**：三处超列（152/156 列）调用/签名按 Zig 100 列风格折行 ⇒ 代次 blob `3ae7b34e`、**32546 行**、`timeout 240 zig build` **63s**；重编译二进制复跑 门A `same=17/17`、门B `same=3 differs=1`、八形合串 `IDENTICAL`、三单形 `IDENTICAL`、门F `ok=5 bad=0`（f031/f010/f042/f067/f113 行数与 md5 均等于冻结记录）⇒ **折行发射中性**。**产物已清**：影子脚本与其 `/tmp` 捕获、KEEP_TEMP 目录、全部 `aot_compile_*` 产物删除，原始读数已转录进 §4「facet-2 落地记录」⇒ 一次性插桩不再可复跑（永久探针与四份门脚本不受影响）；**零 `.php` 删除**。**提交边界**：本行仅为工作区落地记录；提交需用户明示「提交」，且 `native_linker.zig`（facet-1 + facet-2）+ 本工单 + 变更文档 [docs/changes/2026-10-04/AOT臂尾latch交还发射根治_CODEGEN-005RC5方案R_2026-10-04_3ae7b34e.md](../changes/2026-10-04/AOT臂尾latch交还发射根治_CODEGEN-005RC5方案R_2026-10-04_3ae7b34e.md) 自成一批，**禁止**与 REF-003 模板改造、行 12 提过的 DRY 三写收口、`scripts/batch_test_aot.sh` 的 `gtimeout`→`timeout` 混提 |
| 16 | **do-while 侧「站点③」是否也按方案 R 补齐**（承接行 15：facet-2 只落 while/for 两站点，`generateDoWhileFromLabels` :17391–:17400 是同形第三站点） | ✅ **2026-10-04 只读审计完成，发射侧一行未动**：两份新永久探针 F-I / F-J + 独立等值门 `c005_dowhile_probe_run_tmp.sh` 实测 `DOWHILE_PROBE_DONE total=2 same=2 differs=0`（逐形 `IDENTICAL|rc=0`）。**裁决问题的答案是「现在不必补，但必须登记为解禁前置条件」** —— 三条独立证据（IR 缺 `do_while_cond_/do_while_exit_` 前置块、F-I↔F-F 生成码 A/B、`generateDoWhileFromLabels` 唯一调用点 :8250 被 :17521/:17566 的 `has_do_while` 函数级否决）共同证明**该生成器在当前管线不可达** ⇒ 站点③ 既不成立也不复成立，是**未执行的死代码**；同时**否证并更正**了行 4 同族扫描对 S 探针的机制归因（旧引 `:17155` 实测现处 `:17354`；S 等值来自整函数回退状态机，非 do-while 生成器生效），更正已写回 §修复方案 P2 行与 §4 审计小节。**待裁决**：解禁 `has_do_while`（把 do-while 交回原生发射）属**性能+语义双赢但高风险**的发射侧改造，须按 §六 先获用户点头，且**必须同批**按方案 R 口径补第三站点、以 F-I/F-J 两形作验收门；另须注意 IR 侧缺前置块 ⇒ 解禁前得先确认生成器是否改按「自指回边块」形态接受（见 [AOT-PERF-001](AOT-PERF-001-默认优化档位与函数级状态机回退.md) §3） |
| 17 | 本次审计外溢的**性能**发现如何处置（非 RC-5 语义缺陷，另立工单） | ⏳ **待裁决**：审计过程中实测到两条与发射正确性无关、但直接影响「语言级性能」的结构性事实 —— ① `has_do_while` / `has_switch` / `has_match` / `has_exception_handler` / `has_recursive_call` 是**函数级否决位**，命中即整个函数丢原生循环、退回 `switch (current_block)` 逐块派发（F-J 实测 `: while (true)` 计数 **0**）；② AOT 默认优化档位为 `release_small`（`compiler.zig:140`），仅在生成码 > 200KB 时被 :32195 静默升级为 `release_fast`，小脚本因此慢 **2.6–3.4 倍**。二者与「AOT 产物在数组/纯计算负载上仍慢于 PHP 8.5 解释器」一同登记于 [AOT-PERF-001](AOT-PERF-001-默认优化档位与函数级状态机回退.md)。**是否改默认档位、是否解禁否决位属设计/性能决策（§六 第 6、7 条），未经点头禁止动手** |
